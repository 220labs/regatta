#!/usr/bin/env python3
"""tier_check: at a session's first prompt, the facts the model-tier rule needs and can't see.

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

Every time, it asks the model for a tier hint per the owner's routing rules (`plumb/tier-rules` in
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

Wired user-wide on UserPromptSubmit by `bootstrap.sh --hooks` (dream 2026-09-27 P3).
Limits: a mid-session `/model` or effort change is invisible to it; it speaks once, at the
first prompt. Stdlib only; never blocks a turn (any failure → stderr, exit 0).
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
    core's source shim. Imported on use, not at the top: every prompt runs this file and returns at
    once after the first. No core: ImportError, which each caller takes."""
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
        out.append(f"Account {a['label']}{' (primary)' if a.get('primary') else ''} — 5h {lim.get('five_hour')}%, "
                   f"week {lim.get('seven_day')}% (reset {when}), sampled {age(a['sampled'] * 1000)}; "
                   + ("eligible" if a["eligible"] else f"not eligible: {a['why']}") + ".")
    return out


def cost_tool(common):
    """The cost formatter the line names, home as `~`: the overlay's bin/cost where it exists (the
    path the login dirs' allow rules name, AGENTS.md's Traps), else the core's through tool()."""
    legacy = common.legacy_root()
    p = legacy / "bin" / "cost" if legacy and (legacy / "bin" / "cost").is_file() else common.tool("cost")
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
    SEEN_DIR.mkdir(parents=True, exist_ok=True)
    mark = SEEN_DIR / sid
    if mark.exists():
        return 0
    mark.touch()
    print(report())
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as e:  # never block a turn
        print(f"tier_check: {e}", file=sys.stderr)
        sys.exit(0)
