#!/usr/bin/env python3
"""tier_check: at a session's first prompt, the facts the model-tier rule needs and can't see;
at every prompt, an effort past the table.

Prints, once per session, as context for the model:
  - the configured model and effort per model (~/.claude/settings.json), because a pinned
    `xhigh` nobody looked at was 46% of the $916 day before the Max week ran out (2026-09-25);
  - the login (~/.claude.json oauthAccount — or $CLAUDE_CONFIG_DIR/.claude.json in a session
    started on another account's config dir, which before 2026-10-03 reported the primary's
    login), because a Pro fallback login exists since 2026-09-26; and the registry label of that
    dir (`— <label>`), so a VS Code profile window says which account it is on (work-account E8);
  - one line per other account in the registry (bin/account limits --all --cached): its
    windows, how old the probe is, and whether `account pick` would take it now. A hook never
    probes (multi-account design E2);
  - the cost ratio in use (hooks/common.py cost_text), so a session quoting money shows list and
    effective without remembering a factor that moves every week (the owner, 2026-10-05);
  - the week's plan usage against pace, from whichever is fresher: Claude Code's own /usage
    cache (~/.claude.json cachedUsageUtilization) or the Claude app's 15-minute samples for the
    same organisation. The cache went 41 h without a refresh on 2026-09-29 while the app's
    samples were minutes old — so each figure says how old it is.

At the first prompt, it also asks the model for a tier hint per the owner's routing rules (`plumb/tier-rules` in
the config dir names them; the overlay's docs/record/model-routing-2026-09-30.md D1, 2026-10-04): name the tier; spawn `worker`, `sr-worker` or
`architect` unasked for a slice that fits, and say so; set effort with `/effort` or the skill;
ask to switch only when the whole conversation needs another model. It no longer says "ask if
it differs": that prompt is what led to `/model`, and a model switch re-reads the whole
conversation uncached, where an agent or an effort change costs nothing. When the budget is tight (10 points over pace, or 80%
of the week gone) it turns conservative: is this task for a current goal now, or can it wait;
no `xhigh`/`max` beyond the table; short context (a fresh session per task, `/clear` between
topics, no 8-hour sessions — 63% of the week of 09-20's spend was in sessions longer than 8 h). On the Pro fallback login the table is the same: low
limits are no reason for a lower tier. The owner, sextant D23 (2026-09-29): "I absolutely want you
to give me hints on which model is right for which tasks. I meant that I don't want to degrade
quality on Pro just because of lower limits. But I still need to find ways to spend tokens
more efficiently."

At every prompt, it reads the session's effort: the newest main-thread assistant entry's `effort` in
the transcript's last 256 KB (a subagent's entry and Claude Code's `<synthetic>` one skipped). The hook
input's `effort`, `{"level": "<effort>"}`, would name the turn about to run, and is read first when it
holds an effort word; as of Claude Code 2.1.316 only hooks in a tool-use context get it, never
UserPromptSubmit (its binary's strings, read by the round-2 review), so today the transcript is the
source and an `/effort` change shows one prompt late. At `xhigh`
or `max` it prints one line asking the model to tell the owner first thing and suggest
`/effort high`, unless the owner asked for it (xhigh-warning, 2026-11-01: over 2026-10-28..11-01
`xhigh` was a third of the list spend, $1,480 ($27 effective) of $4,432 ($82 effective), $477
($8.80 effective) of it main sessions the table pins at `high`). It warns once per stretch at a
value: a mark beside the seen mark keeps the last effort read, so a second prompt at `xhigh` is
quiet, and one that drops to `high` and climbs back is warned again. The first-prompt report flags
a settings pin at `xhigh` the same way (a `max` there never runs: Claude Code 2.1.316 keeps `low` to
`xhigh` only in settings, its `eOe` filter read from the binary, so flagging it would warn of an
effort not running and its mark would quiet a real `/effort max`), and records the pins' values in that mark, so a
session running at a pin it was just told of hears it once. Silent under an unattended run (`CLAUDE_UNATTENDED`,
`REGATTA_UNATTENDED`): its effort is dispatch's choice, and no owner reads the reply.

Wired user-wide on UserPromptSubmit by `bootstrap.sh --hooks` (dream 2026-09-27 P3).
Limits: a mid-session `/model` change is invisible to it; an `/effort` change shows one prompt late
(above); a per-model pin heard at the first prompt also quiets that value on another model. Stdlib only; never blocks a turn (any failure → stderr, exit 0).
"""
import datetime as dt
import json
import os
import subprocess
import sys
import time
from pathlib import Path

HOME = Path.home()
CORE_MISSING = "regatta core not found — install the regatta plugin, or run your overlay's bootstrap.sh --config"
# A session on another account runs under its own config dir; set to it, the login and the
# settings are that dir's. Unset means ~/.claude, whose .claude.json sits in HOME, not inside it.
CONFIG = os.environ.get("CLAUDE_CONFIG_DIR")
SETTINGS = Path(os.environ.get("CLAUDE_TIER_SETTINGS") or Path(CONFIG or HOME / ".claude") / "settings.json")
CLAUDE_JSON = Path(os.environ.get("CLAUDE_TIER_CLAUDE_JSON")
                   or (Path(CONFIG) / ".claude.json" if CONFIG else HOME / ".claude.json"))
APP_HISTORY = Path(os.environ.get("CLAUDE_TIER_APP_HISTORY",
                                  HOME / "Library/Application Support/Claude/plan-usage-history.json"))
SEEN_DIR = Path(os.environ.get("CLAUDE_TIER_SEEN", HOME / ".claude" / "tier-check-seen"))
WEEK = 7 * 86400
AHEAD = 10  # percentage points over pace before it turns conservative
LOW = 80    # ...or this much of the week gone, whatever the pace (the owner, 2026-09-29: "get more
            # conservative with spending if the budget is low")
HIGH_EFFORTS = ("xhigh", "max")  # past the table's `high` for a main session
EFFORTS = ("low", "medium", "high") + HIGH_EFFORTS  # a value outside these is no reading
PIN_EFFORTS = ("xhigh",)  # past the table and kept in settings (a `max` pin is dropped: the header)
TAIL = 256 * 1024  # bytes of the transcript read per prompt: a long session's file runs to hundreds of MB


def now() -> float:
    return float(os.environ.get("CLAUDE_TIER_NOW") or time.time())


def load(p: Path) -> dict:
    try:
        return json.loads(p.read_text())
    except (OSError, ValueError):
        return {}


def age(ms: float) -> str:
    m = max(0, (now() * 1000 - ms) / 60000)
    return f"{m:.0f} min ago" if m < 90 else f"{m / 60:.0f} h ago"


def unattended() -> bool:
    """The core's common.unattended() (UNATTENDED_NAMES), copied: importing the core at every prompt
    to ask it costs more than the hook's own work. A change to the names changes this too."""
    return bool(os.environ.get("CLAUDE_UNATTENDED") or os.environ.get("REGATTA_UNATTENDED"))


def effort_warning(effort: str, where: str) -> str:
    """The one line for an effort past the table; `where` says what showed it."""
    return (f"⚠️ Effort `{effort}` ({where}): the tier table ({tier_rules()}) runs main sessions at `high`. "
            f"Say so to the owner first thing in this reply and suggest `/effort high` — unless the owner "
            f"asked for `{effort}` in this session.")


def pinned_efforts(settings: dict) -> list:
    """-> [(where, effort)] for each settings pin past the table that Claude Code keeps: the global one
    and each model's."""
    out = []
    if not isinstance(settings, dict):  # a settings file that is not an object pins nothing
        return out
    if str(settings.get("effortLevel") or "") in PIN_EFFORTS:
        out.append(("settings pin", settings["effortLevel"]))
    per = settings.get("modelSettings")
    for k, v in sorted(per.items() if isinstance(per, dict) else []):
        e = str((v or {}).get("effortLevel") or "") if isinstance(v, dict) else ""
        if e in PIN_EFFORTS:
            out.append((f"settings pin for {k.replace('claude-', '')}", e))
    return out


def effort_word(v) -> str:
    """An effort as Claude Code writes it, `{"level": …}` (its hook schema) or a bare word (the
    transcript's), or "" for anything else: an unknown shape is no reading, never junk in the mark."""
    v = v.get("level") if isinstance(v, dict) else v
    v = v if isinstance(v, str) else ""
    return v if v in EFFORTS else ""


def transcript_effort(path) -> str:
    """The newest main-thread assistant entry's `effort` in the transcript's last TAIL bytes, or "".
    A subagent's entry (agentId, isSidechain) is not this session's effort, and a `<synthetic>` one
    is Claude Code's own (AGENTS.md's trap); both are skipped. Any read error is ""."""
    try:
        with open(path, "rb") as f:
            f.seek(0, os.SEEK_END)
            size = f.tell()
            start = max(0, size - TAIL - 1)  # one byte more: whether the tail starts on a whole line
            f.seek(start)
            chunk = f.read(size - start)
    except (OSError, TypeError, ValueError):
        return ""
    lines = chunk.split(b"\n")
    if start > 0:
        lines = lines[1:]  # the bytes before the tail's first newline: a cut entry, or the byte before a whole one
    for raw in reversed(lines):
        if b'"assistant"' not in raw:
            continue
        try:
            d = json.loads(raw)
        except ValueError:
            continue
        if not isinstance(d, dict) or d.get("type") != "assistant":
            continue
        if d.get("agentId") or d.get("isSidechain"):
            continue
        m = d.get("message")
        if isinstance(m, dict) and m.get("model") == "<synthetic>":
            continue
        e = effort_word(d.get("effort"))
        if e:
            return e
    return ""


def effort_mark(sid: str) -> Path:
    return SEEN_DIR / f"{sid}.effort"


def remember(sid: str, effort: str) -> None:
    """Write the last effort read; a failure loses only the once-per-stretch quiet, never a warning."""
    try:
        effort_mark(sid).write_text(effort)
    except OSError as exc:
        print(f"tier_check: effort mark: {exc}", file=sys.stderr)


def input_effort(data: dict) -> str:
    """The hook input's effort for the turn, or "" (then the transcript decides)."""
    return effort_word(data.get("effort"))


def effort_check(sid: str, data: dict) -> str:
    """One warning line when this session's effort is past the table and was not the last one read,
    else "". The mark `<sid>.effort` holds the last effort read, `high` included, so a drop and a
    climb back warns again; after the first prompt it may hold the pins' values, comma-joined, each
    one already heard."""
    live = input_effort(data)
    effort = live or transcript_effort(data.get("transcript_path"))
    if not effort:
        return ""
    try:
        last = effort_mark(sid).read_text().strip().split(",")
    except OSError:
        last = []
    if effort in last:
        return ""
    line = effort_warning(effort, "this turn" if live else "this session's last reply") if effort in HIGH_EFFORTS else ""
    remember(sid, effort)
    return line


def effort_line(settings: dict) -> str:
    per = settings.get("modelSettings") or {}
    parts = [f"{k.replace('claude-', '')} {v.get('effortLevel', '?')}" for k, v in sorted(per.items())]
    default = settings.get("effortLevel")
    s = f"model {settings.get('model', 'default')}"
    if parts:
        s += "; effort per model: " + ", ".join(parts)
    elif default:
        s += f"; effort {default}"
    return s


def weekly(cj: dict):
    """-> (percent, sampled_ms, resets_at_epoch or None) from the fresher source, or None."""
    oa = cj.get("oauthAccount") or {}
    best = None
    resets = None
    cache = cj.get("cachedUsageUtilization") or {}
    for l in (cache.get("utilization") or {}).get("limits") or []:
        if l.get("kind") == "weekly_all":
            try:
                resets = dt.datetime.fromisoformat(l["resets_at"]).timestamp()
            except (KeyError, TypeError, ValueError):
                resets = None
            if l.get("percent") is not None and cache.get("fetchedAtMs"):
                best = (l["percent"], cache["fetchedAtMs"])
    org = oa.get("organizationUuid")
    if org:
        for s in reversed((load(APP_HISTORY).get("samples") or [])[-200:]):
            if s.get("org") == org and (s.get("u") or {}).get("sd") is not None:
                if best is None or s["t"] > best[1]:
                    best = (s["u"]["sd"], s["t"])
                break
    if best is None:
        return None
    if resets:  # a reset time in the past means the cache predates a reset: roll it forward
        while resets < now():
            resets += WEEK
    return best[0], best[1], resets


def week_pace(resets: float) -> float:
    """Percent of the week gone, by whole hours, one decimal (the owner, 2026-10-02): an hour is 0.6
    points, so a whole percent moved only every 1.7 h. Counted in seconds, not via the elapsed
    fraction, whose float error drops an hour at 34 of 169 exact hour boundaries. The anchor is
    the plan's own resets_at (Sun 04:00 Pacific on the Max login). bin/review-gate calls this
    too, so the tier line and the review gate agree on "tight"."""
    hours = min(max(int((WEEK - (resets - now())) // 3600), 0), 168)
    return round(100 * hours / 168, 1)


def _common():
    """The core's common module. In regatta's plumb module the core's hooks/ is found by
    lib/find_core.py; in the overlay hooks/ is this file's own folder, whose common.py is the
    core's source shim. Imported on use, not at the top: after the first prompt the hook reads only
    the transcript's tail, and imports the core only to word a warning. No core: ImportError, which
    each caller takes."""
    here = os.path.dirname(os.path.abspath(__file__))
    lib = os.path.join(os.path.dirname(here), "lib")
    if os.path.isfile(os.path.join(lib, "find_core.py")):
        sys.path.insert(0, lib)
        import find_core
        try:
            sys.path.insert(0, find_core.hooks())
        except SystemExit:
            raise ImportError("the regatta core is missing")
    else:
        sys.path.insert(0, here)
    import common
    return common


def account_lines() -> list:
    """The other accounts from the registry, from their cached probes only; lighthouse's bin/account
    through the core's tool() (G13), none without it."""
    try:
        acct = _common().tool("account")
        if not acct:
            return []
        r = subprocess.run([sys.executable, str(acct), "limits", "--all", "--cached", "--json"],
                           capture_output=True, text=True, timeout=5)
        rows = json.loads(r.stdout) if r.returncode == 0 else []
    except Exception:
        return []
    here = Path(CONFIG or HOME / ".claude").expanduser().absolute()
    out = []
    try:
        return account_rows(rows, here, out)
    except Exception:  # the tier report goes out without them rather than not at all
        return out


def account_rows(rows, here, out):
    for a in rows:
        if Path(a["home"]) == here or not a.get("here", True):  # itself; or not on this Mac (the other one)
            continue
        if (a.get("provider") or "claude") != "claude":  # a Codex login no session runs on (the widget shows it)
            continue
        lim = a.get("limits")
        if a.get("same_as"):  # pick never probes it, so it may have no cache; the reason is the news
            out.append(f"Account {a['label']}: not eligible: {a['why']}.")
            continue
        if not lim:
            out.append(f"Account {a['label']}: no probe yet (bin/account limits {a['label']}).")
            continue
        reset = lim.get("seven_day_resets")
        when = dt.datetime.fromtimestamp(reset).strftime("%a %H:%M") if reset else "?"
        five = "no 5-hour window" if a.get("no_five_hour") else f"5h {lim.get('five_hour')}%"   # account's no_five_hour
        out.append(f"Account {a['label']}{' (primary)' if a.get('primary') else ''} — {five}, "
                   f"week {lim.get('seven_day')}% (reset {when}), sampled {age(a['sampled'] * 1000)}; "
                   + ("eligible" if a["eligible"] else f"not eligible: {a['why']}") + ".")
    return out


def cost_tool(common):
    """The cost formatter the line names, home as `~`: the core's through tool() (the overlay's
    bin/cost came first until B14b, 2026-10-23, which deleted it)."""
    p = common.tool("cost")
    if not p:
        return "regatta's bin/cost"
    p = str(p)
    return "~" + p[len(str(HOME)):] if p.startswith(str(HOME) + "/") else p


def cost_line() -> str:
    common = _common()
    return ("Cost: any model cost or price you quote, in chat or a doc or deck, is `$<list> ($<eff> effective)` — "
            f"`{cost_tool(common)} <list>` prints it, the amount without `$` ({common.ratio_note()}; "
            "pay-per-use providers × 1). Real money — extra usage, a subscription, a domain — is plain; in a doc, "
            "`list-only` on its line.")


def account_label():
    """The registry label of the dir this session runs under, so a profile window says
    which account it is on (work-account E8); None when the registry has no row for it."""
    try:
        here = Path(CONFIG or HOME / ".claude").expanduser().absolute()
        common = _common()
        reg = json.loads(Path(os.environ.get("ACCOUNTS_FILE") or common.CONFIG / "lighthouse" / "accounts.json").read_text())
        for a in common.account_rows(reg.get("accounts"), HOME):
            if (a.get("provider") or "claude") == "claude" and common.account_home(a, HOME) == here:
                return a.get("label")
    except Exception:
        pass
    return None


def tier_rules():
    """Where the tier table lives, as the hint names it: `plumb/tier-rules` in the config dir, its
    items joined by a space (a config value holds one word per line), else a neutral phrase."""
    try:
        return " ".join(_common().config_lines("plumb/tier-rules") or []) or "your model-routing rules"
    except Exception:  # no core: the hint still goes out
        return "your model-routing rules"


def report() -> str:
    settings = load(SETTINGS)
    cj = load(CLAUDE_JSON)
    oa = cj.get("oauthAccount") or {}
    plan = {"claude_max": "Max", "claude_pro": "Pro"}.get(oa.get("organizationType") or "", oa.get("organizationType") or "?")
    label = account_label()
    lines = [f"⚙️ Tier check — login {oa.get('emailAddress', '?')} ({plan}){' — ' + label if label else ''}; {effort_line(settings)}."]
    w = weekly(cj)
    if w:
        pct, t, resets = w
        if resets:
            elapsed = min(max(1 - (resets - now()) / WEEK, 0), 1)
            pace = week_pace(resets)
            day = min(7, int(elapsed * 7) + 1)
            s = f"Week: {pct}% used on day {day} of 7 (pace {pace}%; sampled {age(t)})."
            if pct > pace + AHEAD or pct >= LOW:
                s += (" Budget tight — be conservative: say whether this task serves a current goal "
                      "now, and propose deferring it if not; what runs gets the tier it needs, no "
                      "`xhigh`/`max` beyond the table, and short context — a fresh session per task, "
                      "`/clear` between topics, no 8-hour sessions.")
            lines.append(s)
        else:
            lines.append(f"Week: {pct}% used (sampled {age(t)}; reset time unknown).")
    lines.extend(account_lines())
    try:
        lines.append(cost_line())
    except ImportError as exc:  # no core (regatta-modules C4): the report goes out without it, one line said
        # a core that loads but refuses its config says so itself; only a missing one is CORE_MISSING
        print(f"tier_check: {exc}" if "config incomplete" in str(exc) else f"tier_check: {CORE_MISSING} ({exc})",
              file=sys.stderr)
    except Exception:  # the tier report goes out without it
        pass
    lines.append("Tier hint: before the first tool call, name the tier this task needs "
                 f"({tier_rules()}): the main session runs Opus `high` — say "
                 "so when the model or effort above differs (a leftover Fable or `xhigh`); a "
                 "slice that fits an agent goes to it unasked, said in chat — `worker` (Sonnet) for a "
                 "spec'd slice, `sr-worker` (Opus) where judgement is the work, `architect` (Fable) "
                 "for design; copy and doc edits drop to `medium` with `/effort` or the skill. Ask to "
                 "switch only when the whole conversation needs another model.")
    if plan == "Pro":
        lines.append("This is the Pro fallback login: the same tier table as on Max — low limits are no "
                     "reason for a lower tier. Routines, connectors and account skills live on the Max one.")
    return "\n".join(lines)


def main() -> int:
    try:
        data = json.load(sys.stdin)
    except Exception:
        return 0
    sid = str(data.get("session_id", ""))
    if not sid:
        return 0
    mark = SEEN_DIR / sid
    lines = []
    try:
        SEEN_DIR.mkdir(parents=True, exist_ok=True)
        first = not mark.exists()
        if first:
            mark.touch()
    except OSError as exc:  # no seen mark, no report (it would print at every prompt); the effort line still goes out
        print(f"tier_check: seen mark: {exc}", file=sys.stderr)
        first = False
    if first:
        try:
            lines.append(report())
        except Exception as exc:  # the effort lines below still go out
            print(f"tier_check: report: {exc}", file=sys.stderr)
        if not unattended():
            try:
                pins = pinned_efforts(load(SETTINGS))
            except Exception as exc:
                print(f"tier_check: pins: {exc}", file=sys.stderr)
                pins = []
            lines.extend(effort_warning(e, where) for where, e in pins)
            if pins:  # a session at a pin it was just told of hears it once, two pins included
                remember(sid, ",".join(sorted({e for _, e in pins})))
    if not unattended():
        try:
            w = effort_check(sid, data)
        except Exception as exc:  # the report above still goes out
            print(f"tier_check: effort: {exc}", file=sys.stderr)
            w = ""
        if w:
            lines.append(w)
    if lines:
        print("\n".join(lines))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as e:  # never block a turn
        print(f"tier_check: {e}", file=sys.stderr)
        sys.exit(0)
