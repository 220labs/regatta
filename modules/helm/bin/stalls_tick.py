#!/usr/bin/env python3
"""The chain manager's tick: what is done about each stall bin/stalls.py finds (orchestration B3;
docs/chain-manager-2026-10-11.md section 4 and E3; D4 = C, the owner 2026-10-14, as revised there).

    helm tick [--json]                judge every stall on both Macs, gate it, and act when armed
    helm tick --dry-run [--json]      the same verdicts, printed; nothing called, nothing written
    helm tick --arm [--by WHO] | --disarm | --status

What it may do (A1/A2), everything else raised (A3, a card and a line, nothing called):
    S1   a build step gone without an end: re-dispatched fresh from its brief with a note
    S2   a step whose --next the run cap refused: its next step started once the cap has room
    S4   a launch stopped by the network or sleep: `autofinish-run <worktree> --by chain`
    S1   an Orca step whose worker exited with no worker_done: `harness retry <dispatch>`, which is
         Orca's `worker-start --task --retry-of` with the same placement — the Task's spec is its
         brief, so there is no note; the same two retries, keys and gates (B8)
    S6   an Orca worker's `question` naming `<doc> Dn`: `bin/ask relay <doc> <Dn>` once, with the
         plan's manager road; after it the stall waits on the answer, which goes back to the worker
         by `orca orchestration reply --id <msg>` (not this tick's; B8)
    ?    a run the rules cannot tell (stalls.py's `unsure`, action `classify`): `bin/gate classify`
         at site plan.stall answers yes (retry it as S1) or no (raise it). S3, S5, S6 and S7 are
         never classified: their class already says a person decides (a gate, a WAITING line, a
         lifetime cap, a manager's next move) — D4's "outside S1, S2 and S4" read as the brief does
Two retries per step (D4 = C), keyed as stalls.py keys them: (host, repo, topic, brief blob) for a
step — every checkpoint moves the tip — and (host, branch, tip) for a launch. Backoff BACKOFF:
the first retry 10 min after the stall was first seen, the second 40 min after the first. Why
those: a stall is restarted fresh, never continued in place (the warm cache is the 5-minute kind
and a cold continuation rewrites it for nothing, the subagent-cache record), so waiting costs no cache;
10 min is two of `ask poll`'s 5-minute ticks, so one misread tick never spends a build step, and a
dead run's watcher and the API blip that stopped it have time to clear; 40 min lets the first
retry get going (its record then supersedes the stall) or fail on its own, and keeps the worst
case — two retries per step at the median $1.85 ($0.033 effective) — at most two starts an hour.

The gates, before any call, first refusal wins (section 4's, with the backoff and the
classifier added; the cheap and permanent ones first, the live reads last):
    armed          ~/.local/state/stalls/armed, written only by `--arm` (refused under
                   CLAUDE_UNATTENDED); the first DRY_AFTER_ARM (3 h) after arming are dry
    memory         stalls.jsonl: RETRIES performed for this key → raised; within the backoff → wait
    depth          the record's depth (B2) under DISPATCH_MAX_DEPTH, the retry's as dispatch counts
                   it; no depth (a run before B2) → raised
    the lock       a build step: hooks/checkpoint.py's held_by_other() rule, as `dispatch --next`
                   uses — any lock on its worktree younger than OWNER_TTL and not handed over
                   refuses, idle or dead (read on the run's own Mac by stalls.py's facts());
                   a launch: autofinish armed here, and autofinish-run's own lock_refusal()
    the run cap    a step on this Mac: `dispatch-rc live --no-reap` under dispatch's cap, else wait
    the week       bin/autofinish's week_tight() with cached readings: its verdict "tight" refuses
                   (the week), "none" refuses (`account pick` found no login with room)
    the tools      dispatch and autofinish-run keep every guard of their own; a refusal is a
                   line, never a loop: it moves the backoff, and REFUSALS of them raise the stall
A re-dispatch keeps the run's manager (the five DISPATCH_MANAGER*/DISPATCH_PLAN* values from its
record), its depth (an S1 or classified re-run passes depth - 1: the same step, dispatch adds
one; S2 passes it as recorded), model, effort, yolo and a bound pin; it runs where it ran — the
laptop's worktree may hold commits its gone session never pushed — so `--on here` here and
`--on <peer> --at @<now+120> --fallback here` for a peer's (never a bare ssh). A managed run
gets `helm report --status blocked`, then `running` once its retry's record appears; `failed`
never (helmlib.ENDED would close its asks and let S7 fire on its successors).

The tick runs on the laptop and, since skipper-resilience S8, on each scope's yard (bin/ask poll_tick),
each judging its own store; on a yard what it raises also goes out by the stall road — escalations.jsonl
and the `notify.<host>` row (escalate(), below the classifier).

stalls.jsonl (~/Library/Logs/claude-weekly/, the host's own, O_APPEND) is the log and the retry
memory in one: one JSON line per verdict that changed, never per tick (R6) — `{t, host, repo,
branch, tip, topic, class, run, key, key_kind, action, why, …}` with action dry | wait | refused |
raise | retry | started (the retry's record appeared) — and the classifier's answer, so a stall is
classified once. A retry's record does not exist when its line is written (launchd fires it ~90 s
later): the next tick matches it by (repo, topic, brief blob, started after the line), or reads
its dispatch log from the recorded offset for a FAILED line (a refusal at fire time, not counted).

Stdlib, Python 3.9. STALLS_NOW pins the clock, STALLS_LOG and STALLS_STATE_DIR move the files,
STALLS_DISPATCH, STALLS_AUTOFINISH_RUN, STALLS_HARNESS and STALLS_ASK replace the tools (the tests'); the classifier's
provider is the plan.stall row's (GATE_PLAN_STALL_PROVIDER overrides it, bin/gate).
"""
import contextlib
import datetime
import json
import os
import re
import subprocess
import sys
import time
from importlib.machinery import SourceFileLoader
from importlib.util import module_from_spec, spec_from_loader
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import helmlib  # noqa: E402
common = helmlib._common()   # the regatta core (lib/find_core.py); none is an ImportError naming it
import stalls  # noqa: E402

HELM = HERE.parent / "libexec" / "helm"   # off PATH (C1), beside this module's bin/


def peer_exe(name):
    """A peer's program through the core's tool() (wharf-runs' dispatch, dispatch-rc, harness,
    autofinish-run; the core's gate), else its bare name: on PATH where the plugin is enabled, else
    the OSError each caller already takes as "did not run"."""
    return str(helmlib.peer(name) or name)

RETRIES = 2                      # D4 = C: two per step
BACKOFF = (10 * 60, 40 * 60)     # before retry 1, before retry 2 (header)
DRY_AFTER_ARM = 3 * 3600         # the owner's precedent for autofinish (2026-10-05), D4-B's gate kept
REFUSALS = 6                     # tool refusals of one stall before it is raised (a loop is never the answer)
CLASSIFY_SITE = "plan.stall"
CLASSIFY_AGAIN = 3600            # a classifier that failed is asked again after this, not every tick
ON_PEER_DELAY = 120              # --at for a run sent to a peer (dispatch's --on takes @EPOCH)
TOOL_TIMEOUT = float(os.environ.get("STALLS_TOOL_TIMEOUT") or 150)
ORCA_RETRY_TIMEOUT = 330         # the orca adapter waits up to 300 s for worker-start ("exits 0 only once ready")   # dispatch's --fallback probe (10 s) and ssh; autofinish-run's 120 s
LOG_WARN = 5 * 1024 * 1024       # R6
# a run record's road (its keys keep their names) → the environment a retry gets: each value under
# its new name and its old one until rename S8 (helmlib.ENV_NAMES; a peer's older checkout reads the old)
DISPATCH_KEYS = {"manager": helmlib.ENV_NAMES["skipper"], "manager_host": helmlib.ENV_NAMES["skipper_host"],
                 "manager_account": helmlib.ENV_NAMES["skipper_account"], "plan": helmlib.ENV_NAMES["ship"],
                 "plan_space": ("DISPATCH_PLAN_SPACE",)}
# a caller's chain and manager must never become the retry's: launchd's tick has none, a session
# typing `helm tick` has its own (dispatch would name that session the retry's manager)
STRIP_ENV = ("CLAUDE_CODE_SESSION_ID", "CLAUDECODE") + tuple(
    "DISPATCH_" + v for v in ("LABEL", "LOG", "YEAR", "DEPTH", "BRIEF", "MANAGER", "MANAGER_ACCOUNT",
                              "MANAGER_HOST", "PLAN", "SKIPPER", "SKIPPER_ACCOUNT", "SKIPPER_HOST", "SHIP",
                              "PLAN_SPACE", "TASK", "REPO", "PIN")) + tuple(
    "RUN_SEED_" + v for v in ("LABEL", "LOG", "YEAR", "DEPTH", "BRIEF"))
LOGIN_ENV = ("CLAUDE_CONFIG_DIR", "CLAUDE_CODE_OAUTH_TOKEN")   # autofinish-run picks its own, as start_runner lets it
CLASSIFY_ASK = "Should this stalled run be started again, fresh from its brief, by an unattended agent?"
CLASSIFY_LABELS = {
    "yes": "it stopped mid-task — interrupted, an error, a loop it was still in, a check it was still "
           "fixing — and nothing in it waits on a person: a fresh run from the same brief would likely finish",
    "no": "it finished, reported or handed over its result, asked a person something, or stopped on "
          "purpose: running it again would repeat finished work or go past a person",
}
CLASSIFY_CONTEXT = (
    "Each item is one unattended Claude Code build run that ended without the closing line it is "
    "asked to end with (done, or waiting for the owner). The text is how it ended and the end of its "
    "last reply. A retry costs about $1.85 of plan usage and starts the step from its written brief "
    "with the branch as the earlier run left it. Prefer no when unsure.")


def home():
    return Path(os.environ.get("HOME") or Path.home())


def state_dir():
    return Path(os.environ.get("STALLS_STATE_DIR") or home() / ".local/state/stalls")


def log_path():
    return Path(os.environ.get("STALLS_LOG") or home() / "Library/Logs/claude-weekly/stalls.jsonl")


def clock():
    return float(os.environ.get("STALLS_NOW") or time.time())


def iso(t):
    return datetime.datetime.fromtimestamp(t).astimezone().isoformat(timespec="seconds")


def hm(t):
    return datetime.datetime.fromtimestamp(t).strftime("%m-%d %H:%M")


def _load(name, path):
    if not path:
        raise ImportError("%s: not installed" % name)
    loader = SourceFileLoader(name, str(path))
    mod = module_from_spec(spec_from_loader(loader.name, loader))
    loader.exec_module(mod)
    return mod


# ---------------------------------------------------------------------------- the switch

def armed():
    try:
        d = json.loads((state_dir() / "armed").read_text())
    except (OSError, ValueError):
        return None
    return d if isinstance(d, dict) else None


def unattended_refusal(verb):
    """As `autofinish arm`: a runner or any dispatch session never arms the tick (nothing
    unattended arms itself); the owner's word in an attended session does."""
    if os.environ.get("CLAUDE_UNATTENDED"):
        return ("helm tick --%s: refused in an unattended session (CLAUDE_UNATTENDED=%s) — arming is the owner's"
                % (verb, os.environ["CLAUDE_UNATTENDED"]))
    return None


def arm(by):
    """Write the switch; an armed tick stays armed from its first arming (re-arming never shortens
    the dry hours, nor restarts them)."""
    a = armed()
    if a:
        return a
    t = clock()
    d = {"by": by, "ts": iso(t), "t": t}
    state_dir().mkdir(parents=True, exist_ok=True)
    tmp = state_dir() / (".armed.%d" % os.getpid())
    tmp.write_text(json.dumps(d) + "\n")
    os.replace(tmp, state_dir() / "armed")
    return d


def disarm():
    try:
        (state_dir() / "armed").unlink()
    except FileNotFoundError:
        pass


def mode(t=None):
    """(mode, why): disarmed | dry (armed, inside its first 3 h) | armed."""
    t = clock() if t is None else t
    a = armed()
    if not a:
        return "disarmed", "not armed (helm tick --arm) — verdicts and the log only, nothing called"
    since = a.get("t")
    if not isinstance(since, (int, float)):
        try:
            since = datetime.datetime.fromisoformat(a.get("ts") or "").timestamp()
        except ValueError:
            since = t   # an unreadable time is a fresh arming: dry for the next 3 h
    if t - since < DRY_AFTER_ARM:
        return "dry", "armed by %s at %s; dry until %s (the first 3 h)" % (a.get("by") or "?", hm(since), hm(since + DRY_AFTER_ARM))
    return "armed", "armed by %s at %s" % (a.get("by") or "?", hm(since))


def status_lines():
    m, why = mode()
    out = ["helm tick: %s — %s" % (m, why)]
    lines = read_log()
    p = log_path()
    if lines:
        by = {}
        for ln in lines:
            by[ln.get("action")] = by.get(ln.get("action"), 0) + 1
        out.append("%s: %d lines, last %s (%s)" % (p, len(lines), hm(lines[-1].get("t") or 0),
                                                   ", ".join("%d %s" % (n, a) for a, n in sorted(by.items(), key=str))))
    else:
        out.append("%s: no lines yet" % p)
    return out


# ---------------------------------------------------------------------------- the memory

def read_log(path=None):
    """The log's lines (stalls.jsonl, or PATH: escalations.jsonl), a torn one skipped."""
    try:
        text = Path(path or log_path()).read_text(encoding="utf-8")
    except OSError:
        return []
    out = []
    for raw in text.splitlines():
        try:
            d = json.loads(raw)
        except ValueError:
            continue   # a torn line is skipped, never fatal
        if isinstance(d, dict):
            out.append(d)
    return out


def append(line, path=None):
    """One line, O_APPEND, as helmlib.append_event: two ticks never interleave a line."""
    p = Path(path or log_path())
    p.parent.mkdir(parents=True, exist_ok=True)
    fd = os.open(str(p), os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o644)
    try:
        os.write(fd, (json.dumps(line, ensure_ascii=False, sort_keys=True) + "\n").encode())
    finally:
        os.close(fd)


def _k(x):
    return json.dumps(x, sort_keys=True)


def ident(s):
    """One stall instance: its key and the record it was judged on (a launch's key holds its tip)."""
    return _k([s.get("key_kind"), s.get("key"), s.get("run")])


class Memory:
    def __init__(self, lines):
        self.lines = lines
        self.by_ident, self.by_key = {}, {}
        for ln in lines:
            self.by_ident.setdefault(_k([ln.get("key_kind"), ln.get("key"), ln.get("run")]), []).append(ln)
            self.by_key.setdefault(_k(ln.get("key")), []).append(ln)
        # a retry is (its key, its time): one tick's retries share their `t`, so a follow-up names
        # both, or one retry FAILED at fire time would void every other retry of that tick
        self.fire_refused = {(_k(ln.get("key")), ln.get("retry_t")) for ln in lines
                             if ln.get("action") == "refused" and ln.get("retry_t")}
        self.followed = {(_k(ln.get("key")), ln.get("retry_t")) for ln in lines
                         if ln.get("action") in ("started", "refused") and ln.get("retry_t")}

    def last(self, i):
        ls = self.by_ident.get(i)
        return ls[-1] if ls else None

    def first_t(self, i):
        ls = self.by_ident.get(i)
        return ls[0].get("t") if ls else None

    def retries(self, key):
        """The retries performed for this key that were not refused when they fired. One per tick
        time: a retry's `firing` line, written before the tool runs, and its outcome share `t`."""
        by_t = {}
        for ln in self.by_key.get(_k(key), []):
            if ln.get("action") == "retry" and (_k(key), ln.get("t")) not in self.fire_refused:
                by_t[ln.get("t")] = ln
        return list(by_t.values())

    def refusals(self, key):
        return [ln for ln in self.by_key.get(_k(key), []) if ln.get("action") == "refused"
                and (ln.get("tool") or ln.get("retry_t"))]

    def classified(self, i):
        for ln in reversed(self.by_ident.get(i, [])):
            if isinstance(ln.get("classifier"), dict):
                return ln["classifier"]
        return None

    def classify_failed_at(self, i):
        for ln in reversed(self.by_ident.get(i, [])):
            if ln.get("classifier_error"):
                return ln.get("t") or 0
            if isinstance(ln.get("classifier"), dict):
                return None
        return None

    def pending(self):
        """Retries of a step whose run has neither appeared nor been refused at fire time."""
        by = {}
        for ln in self.lines:
            if ln.get("action") == "retry" and ln.get("key_kind") == "step" \
                    and (_k(ln.get("key")), ln.get("t")) not in self.followed:
                by[(_k(ln.get("key")), ln.get("t"))] = ln   # the outcome line wins over its `firing` line
        return list(by.values())


# ---------------------------------------------------------------------------- the gates

def held(owner, t):
    """hooks/checkpoint.py's held_by_other() for a caller that is no session: any lock not handed
    over and seen inside OWNER_TTL holds the worktree."""
    return bool(owner and owner.get("session") and not owner.get("handover")
                and t - float(owner.get("seen") or 0) < common.OWNER_TTL)


def max_depth():
    try:
        return int(os.environ.get("DISPATCH_MAX_DEPTH") or 5)   # dispatch's default
    except ValueError:
        return 5


def local_repo(s):
    """The repo's checkout on this Mac, or None: the record's own path for a run here, else
    projects/<name> in the home folder (dispatch --on resolves the peer's path from it)."""
    d = s.get("dispatch") or {}
    if s.get("host") == helmlib.host() and d.get("repo") and Path(d["repo"]).is_dir():
        return Path(d["repo"])
    p = home() / "projects" / (s.get("repo") or "")
    return p if s.get("repo") and p.is_dir() else None


def what_of(s):
    return {"retry": "redispatch", "start": "start", "relaunch": "relaunch", "classify": "redispatch",
            "relay": "relay"}.get(s["action"])


_AF = None


def autofinish_mod():
    global _AF
    if _AF is None:
        _AF = _load("autofinish_for_tick", helmlib.peer("autofinish"))
    return _AF


def week_refusal(repo):
    try:
        verdict, detail = autofinish_mod().week_tight(repo)
    except Exception as e:  # an odd answer is no account, never a crashed tick (bin/autofinish's rule)
        verdict, detail = "none", "the pick could not be read (%s)" % type(e).__name__
    if verdict == "tight":
        return "the week is tight (%s)" % (detail or "?")
    if verdict == "none":
        return "account pick: no login may run it now (%s)" % (detail or "?")
    return None


def run_cap(s):
    """(busy, cap) on this Mac for a step run here, or None (a peer's run cap is its dispatch's)."""
    if s.get("host") != helmlib.host():
        return None
    d = s.get("dispatch") or {}
    try:
        r = subprocess.run([peer_exe("dispatch-rc"), "live", "--no-reap", str(d.get("repo") or ""), s.get("topic") or ""],
                           capture_output=True, text=True, timeout=60)
        busy = int(r.stdout.strip())
    except (OSError, subprocess.TimeoutExpired, ValueError):
        return None
    # dispatch's own numbers (its max_runs; test_dispatch.sh checks the copy): 8 on a build box (a
    # host the laptop reaches over ssh, `wharf-runs/ssh`), 3 elsewhere, DISPATCH_MAX_RUNS over either
    cap = int(os.environ.get("DISPATCH_MAX_RUNS") or (8 if helmlib.host() in helmlib.ssh_peers() else 3))
    return busy, cap


def decide(s, mem, t, mode_now, label=None):
    """The verdict for one stall, through the gates in the header's order: {"action": raise | wait
    | refused | dry | go, "why", ["would", "what", "attempt"]}. `label` is the classifier's answer
    for an unsure run (retry | raise), None before it is asked."""
    if s["action"] == "raise":
        return {"action": "raise", "why": s["rule"]}
    if s["action"] == "classify" and label == "raise":
        return {"action": "raise", "why": "the classifier says no retry"}
    what = what_of(s)
    done = mem.retries(s["key"])
    n = len(done)
    if what == "relay":
        # once, at once: a worker's `ask` blocks it until a reply (R3), and a relay costs nothing;
        # a relay bin/ask found no road for is raised for good, never tried every tick
        nowhere = [ln for ln in mem.by_key.get(_k(s["key"]), []) if ln.get("undelivered")]
        if nowhere:
            return {"action": "raise", "why": "bin/ask relay found no road to the manager at %s (%s) — raised" % (
                hm(nowhere[-1]["t"]), (nowhere[-1].get("verdict") or "?"))}
        if n:
            return {"action": "wait", "why": "relayed at %s — the answer goes back by `orca orchestration reply --id %s`" % (
                hm(done[-1]["t"]), s.get("orca_message"))}
        refused = mem.refusals(s["key"])
        if len(refused) >= REFUSALS:
            return {"action": "raise", "why": "refused %d times by bin/ask (last: %s) — raised" % (
                len(refused), (refused[-1].get("why") or "")[:120])}
        if mode_now != "armed":
            return {"action": "dry", "would": "relay", "why": "not armed for action"}
        return {"action": "go", "what": "relay", "attempt": 1}
    if n >= RETRIES:
        return {"action": "raise", "why": "%d retries spent on this %s (%s) — raised" % (
            n, "launch's tip" if what == "relaunch" else "step", ", ".join(hm(x["t"]) for x in done))}
    refused = mem.refusals(s["key"])
    if len(refused) >= REFUSALS:
        return {"action": "raise", "why": "refused %d times by its tool (last: %s) — raised" % (
            len(refused), (refused[-1].get("why") or "")[:120])}
    if what in ("redispatch", "start"):
        depth = s.get("depth")
        if depth is None:
            return {"action": "raise", "why": "no depth recorded (a run before B2): raised, not retried"}
        run_at = depth if what == "redispatch" else depth + 1
        if run_at > max_depth():
            return {"action": "raise", "why": "it would be run %d of a chain past the cap of %d (dispatch's deep())" % (run_at, max_depth())}
    # the backoff: from the first sight of this stall, the last retry of its key, or the last refusal
    base = mem.first_t(ident(s)) if n == 0 else done[-1]["t"]
    base = max([b for b in [base] + [r.get("t") for r in refused] if b] or [t])
    due = base + BACKOFF[n]
    if t < due:
        # the wait names what it waits to do, so a dry run's count of waits says which actions are due later
        return {"action": "wait", "why": "%s %d of %d due %s (backoff %d min)" % (what, n + 1, RETRIES, hm(due), BACKOFF[n] // 60)}
    if what in ("redispatch", "start"):
        if held(s.get("owner"), t):
            # no `seen` in the text: a live holder refreshes it every turn, and a changed text is a new line (R6)
            return {"action": "refused", "why": "its worktree's lock is held by session %s, inside OWNER_TTL (2 h)" % (
                str(s["owner"].get("session"))[:8])}
        if not local_repo(s):
            return {"action": "refused", "why": "no checkout of %s on this Mac to dispatch from" % s.get("repo")}
    else:
        if not common.autofinish_armed():
            return {"action": "refused", "why": "autofinish is disarmed on this Mac: a relaunch waits for it"}
        if not s.get("worktree"):
            return {"action": "raise", "why": "no worktree to relaunch in"}
    if mode_now != "armed":
        return {"action": "dry", "would": "%s (retry %d of %d)" % (what, n + 1, RETRIES), "why": "not armed for action"}
    if what in ("redispatch", "start"):
        cap = run_cap(s)
        if cap and cap[0] >= cap[1]:
            return {"action": "wait", "why": "the run cap is full here (%d of %d)" % cap}
    why = week_refusal(local_repo(s) or Path(s.get("worktree") or "."))
    if why:
        return {"action": "refused", "why": why}
    return {"action": "go", "what": what, "attempt": n + 1}


# ---------------------------------------------------------------------------- the actions

def tool_env(drop=()):
    env = {k: v for k, v in os.environ.items() if k not in STRIP_ENV and k not in drop}
    return env


def manager_road(s):
    d = s.get("dispatch") or {}
    return {k: d[k] for k in DISPATCH_KEYS if d.get(k)}


def dispatch_cmd(s, what, attempt, t):
    """(argv, env) of the re-dispatch (header): where it ran, its depth, its manager, its mode."""
    d = s.get("dispatch") or {}
    exe = os.environ.get("STALLS_DISPATCH") or peer_exe("dispatch")
    cls = s.get("class") or "an unsure end the classifier said to retry"
    if what == "redispatch":
        note = ("stalls: re-dispatched (retry %d of %d) after %s — its run (%s) stopped without its closing line, "
                "last seen %s. Start fresh from this brief; the branch holds what the earlier run committed — "
                "read its git log first." % (attempt, RETRIES, cls, s.get("run"), hm(s.get("since") or t)))
    else:
        note = ("stalls: started (retry %d of %d) after S2 — the previous step's --next was refused by the run cap "
                "(%s)." % (attempt, RETRIES, s.get("run")))
    argv = [exe, s["branch"], "--repo", str(local_repo(s)), "--note", note]
    if d.get("model"):
        argv += ["--model", str(d["model"])]
    if d.get("effort"):
        argv += ["--effort", str(d["effort"])]
    if str(d.get("yolo") or "0") not in ("0", "", "False"):
        argv.append("--yolo")
    if d.get("pin") == "bound":
        argv += ["--account", "bound"]
    if s.get("host") == helmlib.host():
        argv += ["--on", "here"]
    else:
        argv += ["--on", s["host"], "--at", "@%d" % (int(t) + ON_PEER_DELAY), "--fallback", "here"]
    env = tool_env()
    # S1 and a classified retry are the same step again: dispatch adds one to DISPATCH_DEPTH
    env["DISPATCH_DEPTH"] = str(max(0, s["depth"] - 1) if what == "redispatch" else s["depth"])
    for k, v in manager_road(s).items():
        env.update((name, str(v)) for name in DISPATCH_KEYS[k])
    return argv, env


def orca_retry_cmd(s):
    """(argv, env) of an Orca step's retry: `harness retry <dispatch>` (the orca adapter's retry())."""
    exe = os.environ.get("STALLS_HARNESS") or peer_exe("harness")
    return [exe, "retry", s["orca_dispatch"], "--harness", "orca", "--json"], tool_env()


def relay_cmd(s):
    """(argv, env) of an Orca question's relay: `bin/ask relay <doc> <Dn> --task <step>`, the plan's
    manager road in the environment as a dispatched run has it."""
    exe = os.environ.get("STALLS_ASK") or str(HERE / "ask")
    r = s.get("relay") or {}
    env = tool_env()
    for k, v in manager_road(s).items():
        env.update((name, str(v)) for name in DISPATCH_KEYS[k])
    if s.get("session"):
        env["ASK_SESSION"] = str(s["session"])   # the asking worker's claude: the ASK's from: and its reply --to
    return [exe, "relay", r.get("doc") or "", r.get("item") or "", "--task", r.get("task") or s.get("topic") or "run"], env


def relaunch_cmd(s):
    exe = os.environ.get("STALLS_AUTOFINISH_RUN") or peer_exe("autofinish-run")
    rule = s.get("af_rule") if s.get("af_rule") in tuple("ABCDELM") else "C"
    # --by chain only: autofinish-run keeps a yolo launch yolo itself (its start()), so a retry
    # here can never forget it
    return [exe, s["worktree"], "--by", "chain", "--rule", rule], tool_env(drop=LOGIN_ENV)


def tool_timeout(s, what):
    return ORCA_RETRY_TIMEOUT if s.get("harness") == "orca" and what == "redispatch" else TOOL_TIMEOUT


def run_tool(argv, env, timeout=None):
    timeout = timeout or TOOL_TIMEOUT
    try:
        r = subprocess.run(argv, env=env, capture_output=True, text=True, timeout=timeout)
    except (OSError, subprocess.TimeoutExpired) as e:
        return None, "", "%s: %s" % (Path(argv[0]).name, e.__class__.__name__)
    return r.returncode, r.stdout, r.stderr


def last_line(text):
    lines = [x.strip() for x in (text or "").splitlines() if x.strip()]
    return lines[-1][:200] if lines else ""


def act(s, dec, t):
    """Run the decided retry; the line to write (a retry, or the tool's refusal)."""
    what, attempt = dec["what"], dec["attempt"]
    if what == "relaunch":
        argv, env = relaunch_cmd(s)
    elif what == "relay":
        argv, env = relay_cmd(s)
    elif s.get("harness") == "orca":
        argv, env = orca_retry_cmd(s)
    else:
        argv, env = dispatch_cmd(s, what, attempt, t)
    rc, out, err = run_tool(argv, env, tool_timeout(s, what))
    shown = [Path(argv[0]).name] + argv[1:]
    if rc is None and "TimeoutExpired" in err:
        # it may have started the run before the timeout: spent, never a refusal that frees the retry
        return {"action": "retry", "what": what, "attempt": attempt, "cmd": shown,
                "why": "%s timed out after %d s — counted as spent" % (shown[0], tool_timeout(s, what))}
    if rc != 0:
        return {"action": "refused", "tool": shown[0], "rc": rc,
                "why": "%s refused it (exit %s): %s" % (shown[0], rc, last_line(err) or last_line(out) or "no output")}
    line = {"action": "retry", "what": what, "attempt": attempt, "cmd": shown, "why": last_line(out) or "started"}
    if what == "relay":
        # bin/ask exits 0 on every verdict: only a road that delivered is a relay (a `none` or
        # `unreachable` verdict, or a SendMessage it leaves to its caller, which the tick cannot make)
        m = re.search(r"verdict: (\S+)", out or "")
        verdict = m.group(1) if m else "?"
        if verdict in ("none", "unreachable", "?") or "call SendMessage" in (out or ""):
            return {"action": "raise", "undelivered": True, "verdict": verdict, "cmd": shown,
                    "why": "bin/ask relay found no road to the manager (verdict %s) — raised" % verdict}
    if s.get("harness") == "orca" and what == "redispatch":
        try:
            new = json.loads(out or "{}").get("session_id")
        except (ValueError, AttributeError):
            new = None
        # worker-start exits 0 only once the worker is ready (Orca's spec): the retry has started
        line["why"] = "worker-start: dispatch %s ready" % (new or "(no id read back)")
        if new:
            line["orca_new"] = new
    road = manager_road(s)
    if road:
        line["manager_road"] = dict(road, session=s.get("session"))
    m = re.search(r"; log (\S+)\s*$", out or "", re.M)
    if m and s.get("host") == helmlib.host() and what != "relaunch":
        try:
            line["log"], line["log_offset"] = m.group(1), os.path.getsize(m.group(1))
        except OSError:
            line["log"], line["log_offset"] = m.group(1), 0
    return line


def report(road, topic, status, progress):
    """`helm report` for a managed run, as any child reports (chain-manager section 4); its exit."""
    if not road or not road.get("plan") or not topic:
        return None
    env = tool_env()
    for k, names in DISPATCH_KEYS.items():
        if road.get(k):
            env.update((name, str(road[k])) for name in names)
    argv = [sys.executable, str(HELM), "report", road["plan"], "--task", topic, "--status", status,
            "--progress", progress]
    if road.get("session"):
        argv += ["--session", road["session"]]
    rc, _, _ = run_tool(argv, env)
    return rc


# ---------------------------------------------------------------------------- the classifier

def classify(items, t):
    """{ident: {"label": retry | raise, "p", "provider"} | {"error": …}} for unsure stalls, through
    bin/gate classify (one call per repo: a call has one source, and the source decides the vendor
    rules). Never a model called directly (AGENTS.md); never a guarded repo's text (stalls.py reads
    none, and the gate refuses one without the owner's quote)."""
    out = {}
    if not items:
        return out
    try:
        gate = _load("gate_for_tick", helmlib.peer("gate"))
    except Exception as e:
        return {i: {"error": "bin/gate did not load (%s)" % e} for i, _ in items}
    by_repo = {}
    for i, s in items:
        by_repo.setdefault(s.get("repo") or "?", []).append((i, s))
    for repo, group in sorted(by_repo.items()):
        ids = {"u%d" % n: (i, s) for n, (i, s) in enumerate(group)}
        texts = {k: "Topic %s, repo %s. How it ended: %s. The end of its last reply: %s" % (
            s.get("topic"), repo, s.get("end_reason") or "no end recorded", (s.get("reply") or "(none read)").strip())
            for k, (i, s) in ids.items()}
        try:
            r = gate.classify(CLASSIFY_SITE, texts, CLASSIFY_ASK, CLASSIFY_LABELS, context=CLASSIFY_CONTEXT,
                              source=repo, caller="helm tick", timeout=120)
        except Exception as e:   # GateOff, GateError, a vendor down: fail closed — raised, asked again later
            for k, (i, s) in ids.items():
                out[i] = {"error": "%s: %s" % (e.__class__.__name__, str(e)[:160])}
            continue
        if r is None:
            for k, (i, s) in ids.items():
                out[i] = {"error": "the %s row is off" % CLASSIFY_SITE}
            continue
        for k, (i, s) in ids.items():
            got = (r.get("items") or {}).get(k) or {}
            if got.get("label") not in CLASSIFY_LABELS:
                out[i] = {"error": "no label for this item"}
                continue
            out[i] = {"label": "retry" if got["label"] == "yes" else "raise", "p": got.get("p"),
                      "provider": r.get("provider")}
    return out


# ---------------------------------------------------------------------------- one tick

def base_line(s, t):
    return {"t": t, "host": s.get("host"), "repo": s.get("repo"), "branch": s.get("branch"), "tip": s.get("tip"),
            "topic": s.get("topic"), "class": s.get("class"), "run": s.get("run"), "key": s.get("key"),
            "key_kind": s.get("key_kind")}


def follow_up(mem, res, t, write, mode_now):
    """The retries of earlier ticks: their record appeared (`started`, the plan told `running`), or
    their dispatch log says FAILED since the retry (a refusal at fire time: not a spent retry)."""
    out = []
    for r in mem.pending():
        key = r.get("key") or [None] * 4
        # the blob matches only a re-dispatch of the same step: an S2 start runs the next step's brief
        seen = [x for x in res.get("runs") or [] if x.get("repo") == r.get("repo") and x.get("topic") == r.get("topic")
                and (key[3] is None or r.get("what") != "redispatch" or x.get("brief_blob") == key[3])
                and (x.get("started") or 0) >= (r.get("t") or 0) - 60]
        line = None
        if r.get("orca_new"):
            seen = [{"run": r["orca_new"]}]   # act() read it back from worker-start, which exits 0 only once ready
        if seen:
            new = sorted(seen, key=lambda x: x.get("started") or 0)[0]
            line = dict({k: r.get(k) for k in ("host", "repo", "branch", "tip", "topic", "class", "run", "key", "key_kind")},
                        t=t, action="started", retry_t=r["t"], new_run=new["run"], why="its retry's run %s started" % new["run"])
            if write and mode_now == "armed":
                line["report"] = report(r.get("manager_road"), r.get("topic"), "running",
                                        "retry %s of %d running (%s)" % (r.get("attempt"), RETRIES, new["run"]))
        elif r.get("log"):
            try:
                with open(r["log"], "rb") as fh:
                    fh.seek(int(r.get("log_offset") or 0))
                    text = fh.read().decode("utf-8", "replace")
            except OSError:
                text = ""
            failed = [x for x in text.splitlines() if x.startswith("FAILED")]
            if failed:
                line = dict({k: r.get(k) for k in ("host", "repo", "branch", "tip", "topic", "class", "run", "key", "key_kind")},
                            t=t, action="refused", retry_t=r["t"], why="at fire time: %s" % failed[0][:200])
        if line:
            out.append(line)
            if write:
                append(line)
    return out


def acted_elsewhere(res):
    """The hosts whose stalls this tick must not act on (stalls.self_judging, carried in the judge's
    result): each yard but this one; every host but this one while the registry does not read, and
    on a yard (its own store only: a yard whose ssh row names the laptop must not act on its runs)."""
    me = helmlib.host()
    others = {s.get("host") for s in res.get("stalls", []) + res.get("unsure", []) if s.get("host") != me}
    if res.get("registry_torn") or me in helmlib.yard_hosts()[0]:
        return others
    return set(res.get("self_judging") or []) - {me}


def tick(dry_run=False, peer=True):
    """Judge, gate, act: {"mode", "mode_why", "decisions": [(stall, line)], "followups", "notes", …}.
    dry_run: the verdicts as an armed tick would reach them, nothing called past the judge and
    nothing written. While the studio brake holds (helmlib.brake_refusal, read here and returned as
    "brake") no Orca is read — the brake freezes Orca serve's tree, and a read would spend ORCA_TIMEOUT
    against it and read nothing — no retry starts, and the caller reads it again before its later passes
    (wharf's, the skippers'), taking the result's when set."""
    t = clock()
    brake = helmlib.brake_refusal()
    m, m_why = mode(t)
    try:
        deadline = float(os.environ.get("STALLS_DEADLINE") or 0)   # epoch; ask poll passes its kill time
    except ValueError:
        deadline = 0
    if dry_run:
        m, m_why = "dry-run", "--dry-run: nothing called, nothing written"
    # the stall road's fence, asked before the judge: a guarded mark read off a torn registry is no mark
    # (the gate's list reads no name then), so a registry torn at either moment sends nothing (S8)
    try:
        road_before = road_open()
    except Exception as e:   # noqa: BLE001
        road_before = (False, "the fence did not read (%s)" % e.__class__.__name__)
    res = stalls.judge(peer=peer, orca_held=brake)
    # S8: the judge judges every store it read (the board shows a yard's stalls); the tick acts on none
    # of a host that runs its own tick, and on no peer's while the registry cannot tell (fail closed)
    left = acted_elsewhere(res)
    if left:
        res = dict(res, stalls=[s for s in res["stalls"] if s.get("host") not in left],
                   unsure=[s for s in res["unsure"] if s.get("host") not in left],
                   notes=list(res.get("notes") or []) + [
                       "S8: the stalls of %s are left to %s (%d)" % (", ".join(sorted(left)), "their own tick" if not res.get(
                           "registry_torn") else "nobody this pass — the registry does not read", sum(
                           1 for s in res["stalls"] + res["unsure"] if s.get("host") in left))])
    mem = Memory(read_log())
    write = not dry_run
    followups = follow_up(mem, res, t, write, m)
    if followups:
        mem = Memory(mem.lines + followups)
    decisions = []

    # the unsure: a permanent raise first (no classifier spent on it), then the memo, then one call per repo
    unsure = []
    ask = []
    for s in res["unsure"]:
        i = ident(s)
        pre = decide(s, mem, t, "dry", label="retry")   # "dry": the pre-check makes no live read
        c = mem.classified(i)
        if pre["action"] == "raise":
            unsure.append((s, None, pre))
        elif c:
            unsure.append((s, c, None))
        elif m == "armed" and not (mem.classify_failed_at(i) and t - mem.classify_failed_at(i) < CLASSIFY_AGAIN):
            ask.append((i, s))
            unsure.append((s, "ask", None))
        else:
            failed = mem.classify_failed_at(i)
            unsure.append((s, None, {"action": "raise" if failed else "dry", "would": None if failed else "classify",
                                     "why": "the classifier failed at %s; asked again after %d min" % (hm(failed), CLASSIFY_AGAIN // 60)
                                     if failed else "not armed for action: %s" % CLASSIFIER_NOTE}))
    answers = classify(ask, t) if ask else {}

    todo = [(s, None, None) for s in res["stalls"]] + unsure
    for s, c, pre in todo:
        i = ident(s)
        extra = {}
        if c == "ask":
            c = answers.get(i) or {"error": "no answer"}
            if c.get("error"):
                extra["classifier_error"] = c["error"]
                dec = {"action": "raise", "why": "the classifier failed (%s) — raised; asked again after %d min" % (
                    c["error"], CLASSIFY_AGAIN // 60)}
            else:
                extra["classifier"] = c
                dec = decide(s, mem, t, m, label=c["label"])
        elif isinstance(c, dict):
            dec = decide(s, mem, t, m, label=c.get("label"))
        elif pre is not None:
            dec = pre
        else:
            dec = decide(s, mem, t, m)
        if m != "armed" and dec["action"] != "dry":
            dec = {"action": "dry", "would": dec["action"] if dec["action"] != "go" else dec.get("what"), "why": dec["why"]}
        if brake and dec["action"] == "go":
            # S11: no redispatch, start, relaunch or relay while the studio brake holds: dispatch and the
            # harness do not read it, and a relay to a frozen skipper is no delivery; the retry waits, unspent
            dec = {"action": "wait", "why": "held — the studio brake holds (%s)" % brake}
        if dec["action"] == "go" and deadline and time.time() + tool_timeout(s, dec.get("what")) > deadline:
            dec = {"action": "wait", "why": "no time left in this tick for %s (ask poll's timeout)" % dec["what"]}
        if dec["action"] == "go":
            if write:
                # the retry is on record before the tool runs: a tick killed mid-call (ask poll's
                # timeout) has still spent it, so the cap and the backoff hold
                firing = dict(base_line(s, t), action="retry", what=dec["what"], attempt=dec["attempt"], why="firing")
                append(firing)
                mem = Memory(mem.lines + [firing])
            line = dict(base_line(s, t), **act(s, dec, t))
            if line["action"] == "refused":
                line["retry_t"] = t   # voids its own `firing` line
            new = True
        else:
            line = dict(base_line(s, t), **{k: v for k, v in dec.items() if v is not None})
            last = mem.last(i)
            new = last is None or (last.get("action"), last.get("would"), last.get("why")) != (line.get("action"), line.get("would"), line.get("why"))
        line.update(extra)
        if write and new and m == "armed" and s.get("key_kind") == "step":
            road = dict(manager_road(s), session=s.get("session"))
            if line["action"] == "retry":
                line["report"] = report(road, s.get("topic"), "blocked", "stalled %s — retry %d of %d at %s" % (
                    s.get("class") or "?", line["attempt"], RETRIES, hm(t)))
            elif line["action"] == "raise":
                line["report"] = report(road, s.get("topic"), "blocked", "stalled %s — raised: %s" % (
                    s.get("class") or "?", line["why"][:160]))
        if write and new:
            append(line)
            mem = Memory(mem.lines + [line])
        decisions.append((s, line, new))

    notes = list(res.get("notes") or [])
    try:
        size = log_path().stat().st_size
        if size > LOG_WARN:
            notes.append("%s is %.1f MB (R6: a line per changed verdict should keep it small — look)" % (log_path(), size / 1e6))
    except OSError:
        pass
    # skipper-resilience S8: the stall road, after the decisions (never in follow_up) — on a yard only
    try:
        esc = escalate(res, decisions, mem, t, dry=dry_run, road_before=road_before, mode_now=m)
    except Exception as e:   # noqa: BLE001 — the road's fault costs its lines, never the tick's verdicts
        esc = ["escalations: the pass failed (%s: %s)" % (e.__class__.__name__, str(e)[:160])]
    return {"mode": m, "mode_why": m_why, "as_of": t, "hosts": res["hosts"], "decisions": decisions,
            "followups": followups, "notes": notes, "log": str(log_path()), "wrote": write, "escalations": esc,
            "brake": brake}


CLASSIFIER_NOTE = "bin/gate classify %s would say retry or raise" % CLASSIFY_SITE


# ---------------------------------------------------------------------------- the stall road (skipper-resilience S8)
#
# On a yard nobody watches the board, so what the tick raises reaches the owner as one notify — the host's
# `notify.<host>` row, `github-issue` on the yard: an issue in the config's helm/inbox-repo, its body led by
# helm/mention (bin/ask notice()) — and one row in escalations.jsonl, beside stalls.jsonl, O_APPEND:
#     {t, yard, ekey, plan, block, key, key_kind, kind, src, class, rule, title, guarded, road, issue, state, why}
#     (ekey: kind and key in one string; plus was, was_class, was_open, was_tries, retried, transient,
#     also (older followed issues still open), close_tries, close_left (what a first close left open),
#     close_failed, close_failed_issues, reopened)
#     state  open (the first notify of a key) | class-changed (the key's class moved: a second issue, which
#            names the first; the first is closed once the second is open, a failed close of it tried once
#            more) | unrouted (the config gives no road: nothing called, re-checked each pass without a
#            row, opened once it does) | closed (the key missing CLEAR_AFTER with its source read: a comment
#            naming what cleared it, then the issue closed; a failed close tried once more)
# One issue per key at a time. Three kinds are wanted, on this host's own store only:
#     stall  a decision whose verdict is raise (dry or not), first seen ESCALATE_AFTER ago — S3, S5, S6, S7,
#            `skipper won't start`, a spent or refused retry, an unsure one the classifier refused — but
#            never one raised to a live skipper (it hears it), nor a class in NEVER
#     block  a block of a ship the yard holds (a lease here) that waits on the owner as a whole — gated on
#            a decision doc (skipperlib.OWNER_PROGRESS) or a person's task whose deps are done — quiet
#            ESCALATE_AFTER: the yard holds such a block by escalating it, and nothing else
#     ask    an open question on such a ship, by S5's owner rule (skipperlib.owners_ask): the owner's —
#            escalated by `helm skipper --escalate`, or asked in mode ask or dnd — after ESCALATE_AFTER;
#            the skipper's, once RELAY_UNANSWERED (the deaf rule's 15 minutes) passes from the relay that
#            reached it; one answered in its doc already, never. An escalation moves an unanswered one's
#            class: a second issue, the first closed
# Who acts: only a yard (a host some scope's `yard` names), only while the registry reads and keel's
# gate can name every guarded repo (helmlib.guard_unread) — both asked before the judge and after —,
# and only a tick armed past its dry hours, run by launchd (no session, not CLAUDE_UNATTENDED), one at a
# time (a lock beside the log). Any other tick prints `would …` (with when each not yet due is) and
# calls nothing; a refused one (not --dry-run) writes only the absences' clock, under the same lock. A guarded repo's escalation names its class and host alone: no ship, task,
# key, holder or run, in the issue or its comments. A failed open is tried once more on the next pass;
# one that fails again stays on the board as a card (helm_render.road_cards), never in a loop. At most
# ESCALATE_MAX issues open in one pass, and no call starts within ESCALATE_LEFT of the tick's kill time.

ESCALATE_AFTER = 10 * 60      # a raised stall's first sight, a quiet owner's block: with the 5-minute tick, G2's 15 min
RELAY_UNANSWERED = 15 * 60    # an open question on a yard's ship (skipperlib.DEAF's 15 minutes)
NEVER = ("braked",)           # the brake is the owner's own hold: never escalated (no judge names this class yet; under the brake S11 holds the Orca read and the tick's own retries)
OPEN_STATES = ("open", "class-changed")   # `unrouted` (no road by the config) and `closed` are not
ESCALATE_MAX = 5              # issues opened in one pass at most: the rest wait for the next (a yard's first pass may hold dozens)
ESCALATE_LEFT = 60            # no GitHub call with less of the tick's kill time (STALLS_DEADLINE) left
CLEAR_AFTER = 10 * 60         # a key closes once it has been missing this long: one pass's glitch never closes and reopens it


def escalations_path():
    return Path(os.environ.get("STALLS_ESCALATIONS") or log_path().with_name("escalations.jsonl"))


def read_escalations():
    return [d for d in read_log(escalations_path()) if d.get("ekey")]


def append_escalation(row):
    append(row, escalations_path())


def yard_here():
    """True when this host is some scope's yard and the registry reads (helmlib.yard_hosts fails closed)."""
    yards, torn = helmlib.yard_hosts()
    return not torn and helmlib.host() in yards


def road_open(fresh=False):
    """(True, None), or (False, why) when what leaves the machine cannot be vouched for: this host no yard,
    the registry torn, or keel's gate unable to name every guarded repo."""
    if not yard_here():
        return False, "no yard"
    if helmlib.guard_unread(fresh=fresh):
        return False, "the guarded list did not read (keel's gate, its regatta/guarded or the registry's confidential scopes)"
    return True, None


def act_refusal(mode_now):
    """None when this tick may call GitHub; else why it only says `would …` (the tick's own acting rule:
    armed past its dry hours, launchd's — never a session's tick beside the poll's, never an unattended run)."""
    if mode_now != "armed":
        return "the tick is %s" % mode_now
    if os.environ.get("CLAUDE_UNATTENDED"):
        return "an unattended caller (CLAUDE_UNATTENDED=%s)" % os.environ["CLAUDE_UNATTENDED"]
    if os.environ.get("CLAUDE_CODE_SESSION_ID"):
        return "the tick runs inside session %s: the stall road is launchd's tick's" % os.environ["CLAUDE_CODE_SESSION_ID"][:8]
    return None


def _shown_key(key):
    return json.dumps(key, ensure_ascii=False)


def wanted(res, decisions, mem, t):
    """({ekey: what to escalate}, {"ships": bool, "plans": set}) — the three kinds above, each {kind, key,
    key_kind, src, class, rule, plan, block, since, after, ready, title, body, guarded}; and what of the
    yard's ships could not be read this pass (no lease reader: ships False; a ship unread: its id)."""
    me = helmlib.host()
    out = {}
    for s, line, _ in decisions:
        verdict = line.get("would") if line.get("action") == "dry" else line.get("action")
        cls = s.get("class") or "unsure"
        if verdict != "raise" or s.get("host") != me or cls in NEVER or s.get("raise_to") in stalls.RAISE_TO_SKIPPER:
            continue
        since = mem.first_t(ident(s)) or t
        g = bool(s.get("guarded"))
        if g:   # K6: its class and host, nothing else of it
            title = "stall on %s: %s in a guarded repo" % (me, cls)
            body = ["A stall in a guarded repo on %s has waited %d min: open the board there (`helm board`)." % (me, (t - since) // 60),
                    "", "- class: %s" % cls]
        else:
            ev = [e for e in s.get("evidence") or [] if not e.startswith("record ")][:3]
            title = "stall on %s: %s" % (me, s.get("title") or cls)
            body = ["A stall on %s has waited %d min: %s" % (me, (t - since) // 60, s.get("title")), "",
                    "- key: `%s`" % _shown_key(s.get("key")), "- class: %s — rule: %s" % (cls, s.get("rule"))]
            body += ["- evidence: %s" % " · ".join(ev)] if ev else []
            body += ["- why raised: %s" % line.get("why")] if line.get("why") else []
            body += ["- board: %s — `helm board` on %s" % (s.get("column") or stalls.column(s), me)]
        src = "orca" if s.get("harness") == "orca" else {"landing": "launches", "skipper": "skippers"}.get(s.get("key_kind"), "runs")
        ek = _k(["stall", s.get("key_kind"), s.get("key")])
        out[ek] = {"kind": "stall", "key": s.get("key"), "key_kind": s.get("key_kind"), "src": src, "class": cls,
                   "rule": s.get("rule"), "plan": s.get("plan"), "block": s.get("task") or s.get("topic"), "since": since,
                   "after": ESCALATE_AFTER, "ready": t - since >= ESCALATE_AFTER, "title": title, "body": body, "guarded": g}
    unread = {"ships": True, "plans": set()}
    try:
        import leaselib
        import skipperlib
        ships = []
        for p, r in leaselib.leases():
            if isinstance(r, dict):
                ships.append((p, r))
            else:
                unread["plans"].add(p)   # a torn lease: its keys are neither opened nor closed this pass
    except Exception:   # noqa: BLE001 — no lease reader: no ship of the yard's read, none of their keys closed
        unread["ships"] = False
        return out, unread
    # S5's owner rule, read once per pass as its own tick reads it (skipperlib's _PASS cache: each ship's
    # merged tasks, each doc's answers)
    saved, skipperlib._PASS = skipperlib._PASS, {}
    try:
        for pid, lease in ships:
            if not _ship_wanted(out, pid, lease, me, t, skipperlib, unread.setdefault("errors", [])):
                unread["plans"].add(pid)
    finally:
        skipperlib._PASS = saved
    return out, unread


def _ship_wanted(out, pid, lease, me, t, sk, errors=None):
    """The block and ask kinds of one ship the yard holds, into OUT (wanted()'s); False when it did not read.
    A ship's keys are merged only when all of it read: a raise half-way opens none of them."""
    mine = {}
    try:
        ok = _ship_wanted1(mine, pid, lease, me, t, sk)
    except Exception as e:   # noqa: BLE001 — one malformed or unreadable ship costs its own keys, never the pass
        if errors is not None:
            errors.append(type(e).__name__)   # the class only: a guarded ship's text never reaches the log
        return False
    if ok:
        out.update(mine)
    return ok


def _ship_wanted1(out, pid, lease, me, t, sk):
    try:
        st = helmlib.state(pid)
    except (FileNotFoundError, ValueError):
        return False
    tasks = {x["id"]: x for x in st["tasks"]}
    ship = st.get("topic") or pid
    for task in st["tasks"]:
        if task["status"] in helmlib.ENDED:
            continue
        g = bool(task.get("guarded"))
        prog = str(task.get("progress") or "")
        cls = None
        if task.get("kind") == "human":
            deps = [tasks.get(d) for d in task["deps"]]
            if not all(d and d["status"] in helmlib.DONE for d in deps):
                continue   # not the owner's turn yet
            cls, since = "person's", max([d.get("updated") or 0 for d in deps] + [task.get("updated") or 0]) or st.get("created") or t
        elif task.get("status") == "waiting" and prog.startswith(sk.OWNER_PROGRESS):
            cls, since = "gated", task.get("updated") or t
        if cls:
            key = [me, pid, task["id"]]
            if g:   # K6: no ship, task, plan id or progress
                title = "a guarded block on %s: waits on the owner (%s)" % (me, cls)
                body = ["A block in a guarded repo on %s waits on you: open the board there (`helm board`)." % me, "",
                        "- class: waits on the owner (%s)" % cls]
            else:
                asks = [a["ref"] for a in task["asks"] if a.get("open")]
                title = "%s/%s on %s: waits on the owner (%s)" % (ship, task["id"], me, cls)
                body = ["A block of ship %s on %s waits on you: %s." % (ship, me, prog or "a person's task"), "",
                        "- key: `%s`" % _shown_key(key), "- class: waits on the owner (%s)" % cls]
                body += ["- open questions: %s" % ", ".join(asks)] if asks else []
                body += ["- the ship: `helm show %s` on %s" % (pid, me)]
            out[_k(["block", key])] = {
                "kind": "block", "key": key, "key_kind": "block", "src": "ships", "class": cls, "rule": "waits on the owner",
                "plan": pid, "block": task["id"], "since": since, "after": ESCALATE_AFTER,
                "ready": t - float(since) >= ESCALATE_AFTER, "guarded": g, "title": title, "body": body}
            continue   # its questions are the doc's D-items this issue already names
        for a in task["asks"]:
            if not a.get("open") or sk.doc_answer(a):
                continue   # answered in its doc already: nobody's to chase
            # S5's rule (skipperlib.owners_ask): escalated by `helm skipper --escalate`, or asked in mode
            # ask or dnd, the question is the owner's — escalated after ESCALATE_AFTER; else the skipper's,
            # escalated once RELAY_UNANSWERED passes unanswered
            amode = sk.ask_mode(pid, task, a)
            mode = "escalated" if a.get("escalated") else "mode %s" % amode if amode in sk.OWNER_MODES else None
            # the skipper's clock starts at the relay that reached it (a re-hail after a hand-over too), as the
            # deaf rule's; the owner's at the question
            opened = float((None if mode else a.get("relayed_at")) or a.get("opened") or t)
            key = [me, pid, a["ref"]]
            cls = "owner's (%s)" % mode if mode else "unanswered"
            wait = ESCALATE_AFTER if mode else RELAY_UNANSWERED
            if g:   # K6: no ship, task, ref, holder or text
                title = "a guarded question on %s: %s" % (me, "for the owner" if mode else "unanswered")
                body = ["A question in a guarded repo on %s has waited %d min%s: open the board there (`helm board`)." % (
                    me, (t - opened) // 60, " for you" if mode else " with no answer from its skipper"), "", "- class: %s" % cls]
            else:
                title = "%s/%s on %s: %s %s" % (ship, task["id"], me, a["ref"], "for the owner" if mode else "unanswered")
                body = ["A question on ship %s (%s) has waited %d min on %s%s." % (
                    ship, task["id"], (t - opened) // 60, me, " for you (%s)" % mode if mode else " with no answer from its skipper"), "",
                        "- key: `%s`" % _shown_key(key), "- class: %s (lease gen %s)" % (cls, lease.get("gen")),
                        "- %s — Reversible: %s — Recommended: %s" % (a.get("summary") or a["ref"], a.get("reversible") or "unmarked",
                                                                    a.get("recommended") or "none")]
            out[_k(["ask", key])] = {
                "kind": "ask", "key": key, "key_kind": "ask", "src": "ships", "class": cls,
                "rule": "the owner's question" if mode else "a relay unanswered", "plan": pid, "block": task["id"],
                "since": opened, "after": wait, "ready": t - opened >= wait, "guarded": g, "title": title, "body": body}
    return True


_ASK = None


def ask_mod():
    """bin/ask as a module: the notify seam (notice(), stall_road(), issue_state()) is its, as the poll's bell is."""
    global _ASK
    if _ASK is None:
        _ASK = _load("ask_for_tick", HERE / "ask")
    return _ASK


def seen_path():
    return state_dir() / "escalations-seen.json"


def read_seen():
    try:
        d = json.loads(seen_path().read_text())
    except (OSError, ValueError):
        return {}
    return d if isinstance(d, dict) else {}


def write_seen(d):
    p = seen_path()
    p.parent.mkdir(parents=True, exist_ok=True)
    tmp = p.with_name(".%s.%d" % (p.name, os.getpid()))
    tmp.write_text(json.dumps(d, sort_keys=True))
    tmp.replace(p)


@contextlib.contextmanager
def road_lock():
    """One stall road at a time on this host: a non-blocking lock beside the log. Yields False when
    another tick holds it (that pass then calls nothing: two at once would open each issue twice)."""
    import fcntl
    p = escalations_path().with_name(".escalations.lock")
    p.parent.mkdir(parents=True, exist_ok=True)
    fd = os.open(str(p), os.O_WRONLY | os.O_CREAT, 0o644)
    try:
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            yield False
            return
        yield True
    finally:
        os.close(fd)


def escalate(res, decisions, mem, t, dry=False, road_before=(True, None), mode_now="armed"):
    """The stall road's pass (the block above): lines. Nothing on a host that is no yard. road_before:
    road_open() as asked before the judge (the guarded marks were read then)."""
    ok_after, why_after = road_open(fresh=True)
    if not road_before[0] or not ok_after:
        why = road_before[1] if not road_before[0] else why_after
        return [] if why == "no yard" else ["escalations: none this pass — %s" % why]
    refusal = None if dry else act_refusal(mode_now)
    if dry:
        lines = _escalate(res, decisions, mem, t, True)   # --dry-run writes nothing
    elif refusal:
        # a refused pass keeps the absences' clock (local state, no call), so the next acting pass
        # never judges a key gone from a stale memory — under the lock, or a stale read it holds
        # would overwrite what the acting pass just wrote; locked out, it writes nothing
        with road_lock() as got:
            lines = _escalate(res, decisions, mem, t, True, keep=got)
    else:
        with road_lock() as got:
            if not got:
                return ["escalations: another tick holds the stall road — none this pass"]
            lines = _escalate(res, decisions, mem, t, False)
    if refusal and lines:
        lines.append("escalations: nothing called — %s" % refusal)
    return lines


def _escalate(res, decisions, mem, t, dry, keep=False):
    """seen (escalations-seen.json) holds, per key, [last pass it was present, first pass it was missing
    with its source read]: a key closes once missing CLEAR_AFTER and on two passes in a row, so a stale
    memory (a stretch of refused or fenced passes) never closes it on one miss. keep: write it on a dry pass."""
    me = helmlib.host()
    want, ships_unread = wanted(res, decisions, mem, t)
    if ships_unread.get("errors"):
        lines_pre = ["escalations: %d ship(s) did not read (%s) — their keys kept" % (
            len(ships_unread["errors"]), ", ".join(sorted(set(ships_unread["errors"]))))]
    else:
        lines_pre = []
    last = {}
    for row in read_escalations():
        last[row["ekey"]] = row
    seen = read_seen()
    try:
        deadline = float(os.environ.get("STALLS_DEADLINE") or 0)
    except ValueError:
        deadline = 0
    lines, opened, held = lines_pre, 0, 0
    road_ok, road_why = ask_mod().stall_road(me)

    def row_of(ek, w, state, road, issue, why, **kw):
        r = {"t": t, "yard": me, "ekey": ek, "plan": w.get("plan"), "block": w.get("block"), "key": w.get("key"),
             "key_kind": w.get("key_kind"), "kind": w.get("kind"), "src": w.get("src"), "class": w.get("class"),
             "rule": w.get("rule"), "title": w.get("title"), "guarded": bool(w.get("guarded")),
             "road": road, "issue": issue, "state": state, "why": why}
        r.update({k: v for k, v in kw.items() if v is not None})
        return r

    def say(w, prefix, extra=""):
        lines.append("%s %s%s" % (prefix, w.get("title"), extra))

    def late():
        return bool(deadline) and deadline - time.time() < ESCALATE_LEFT

    for ek, w in sorted(want.items()):
        seen[ek] = [t, None]   # present: no absence to count
        prev = last.get(ek) or {}
        state = prev.get("state")
        is_open = state in OPEN_STATES
        same = prev.get("class") == w["class"]
        if is_open and prev.get("close_tries") and not dry:
            # back before its close's retry: the next clear starts with a fresh try. close_left names what
            # the first try failed to close; the rest is closed on GitHub: its own issue is reopened (a live
            # stall never keeps only a closed issue), a followed one is no longer followed
            left = set(prev.get("close_left") or [])
            own = prev.get("issue") if prev.get("road") == "github-issue" else None
            fix = {}
            if own and own not in left:
                ok, why = ask_mod().issue_state(int(own), "open", "Back on %s: %s" % (me, w["title"]))
                if not ok:
                    # its issue stays closed: a new one opens below, as a failed open is tried once more
                    lines.append("escalation: #%s not reopened (%s) — a new notify instead" % (own, why))
                    fix = {"transient": True, "retried": None}
            prev = dict(prev, t=t, close_tries=None, close_left=None,
                        was_open=True if prev.get("was_open") and prev.get("was") in left else None,
                        also=[n for n in (prev.get("also") or []) if n in left] or None, **fix)
            append_escalation({k: v for k, v in prev.items() if v is not None})
        # the issues an open row follows, still open after their close failed: tried once more, then a card
        if is_open and prev.get("issue") and (prev.get("was_open") or prev.get("also")) and not prev.get("was_tries") \
                and not dry and not late():
            failed = []
            for n in followed(prev):
                ok, why = ask_mod().issue_state(int(n), "closed", "The class moved to %s: followed in #%s." % (
                    prev.get("class"), prev.get("issue")))
                lines.append("escalation: #%s %s" % (n, "closed" if ok else "not closed again (%s) — carded" % why))
                if not ok:
                    failed.append(n)
            was_left = prev.get("was") if prev.get("was_open") and prev.get("was") in failed else None
            prev = dict(prev, t=t, was_open=True if was_left else None, also=[n for n in failed if n != was_left] or None,
                        was_tries=1 if failed else None,
                        why="#%s not closed; left open" % ", #".join(map(str, failed)) if failed else prev.get("why"))
            append_escalation({k: v for k, v in prev.items() if v is not None})
        # a failed open that was no config absence (the API down, a refused token) is tried once more
        retry = is_open and same and prev.get("transient") and not prev.get("retried")
        if (is_open and same and not retry) or (not w["ready"] and not is_open):
            if dry and not w["ready"] and not is_open:
                say(w, "would escalate", " (due %s)" % hm(float(w["since"]) + w["after"]))
            continue
        moved = is_open and not same
        # the same key and class back after it cleared: its own issue reopened, never a second
        back = state == "closed" and same and prev.get("road") == "github-issue" and prev.get("issue")
        # back after a clear, the issues its close left open (carded) are carried, still carded
        left_open = [n for n in (prev.get("close_failed_issues") or []) if n != prev.get("issue")] if state == "closed" else []
        if not road_ok:
            if is_open:
                continue   # the config lost its road: the open issue stays the stall's, nothing called
            # no road by the config: nothing called; one row, re-checked each pass without another
            if not (state == "unrouted" and same and prev.get("why") == road_why):
                if dry:
                    say(w, "would escalate", ": no road — %s" % road_why)
                    continue
                append_escalation(row_of(ek, w, "unrouted", "none", None, road_why))
                say(w, "escalated", ": none — %s" % road_why)
            continue
        if dry:
            say(w, "would escalate", " (the class moved from %s)" % prev.get("class") if moved else
                " (#%s reopened)" % prev["issue"] if back else " (tried once more)" if retry else "")
            continue
        if opened >= ESCALATE_MAX or late():
            held += 1
            continue
        opened += 1
        if back:
            ok, why = ask_mod().issue_state(int(prev["issue"]), "open", "Back on %s: %s" % (me, w["title"]))
            if ok:
                append_escalation(row_of(ek, w, "open", "github-issue", prev["issue"], "back after it cleared", reopened=True,
                                         also=left_open or None, was_tries=1 if left_open else None))
                say(w, "escalated", ": github-issue #%s, reopened" % prev["issue"])
                continue
            lines.append("escalation: #%s not reopened (%s) — a new notify instead" % (prev["issue"], why))
        # the issue this one follows, and the class it had: on a move the row's own; on a retry of a moved
        # one, the row's `was` and `was_class` (a second move reads the class it moved from, never the one before)
        # (a move from a row whose own open failed follows that row's `was`, the issue still open)
        was = (prev.get("issue") or prev.get("was")) if moved else prev.get("was") if retry and prev.get("was_open") else None
        # older issues still open (a followed one whose close failed): carried, never dropped by a second move
        also = [n for n in followed(prev) if n != was] if moved else list(prev.get("also") or []) if retry else left_open
        from_cls = prev.get("class") if moved else prev.get("was_class")
        body = list(w["body"])
        if was:
            body += ["", "The class moved from %s to %s: this follows #%s." % (from_cls, w["class"], was)]
        body += ["", "The yard's tick opened this (helm tick, the stall road) and closes it when this clears."]
        n = ask_mod().notice(w["title"], "\n".join(body), kind="stall", host=me)
        new_state = "class-changed" if (moved or (retry and state == "class-changed")) else "open"
        row = row_of(ek, w, new_state, n["road"], n["issue"],
                     n["said"] if n["road"] == "none" else "the class moved from %s" % from_cls if moved else w["rule"],
                     was=was, was_class=from_cls if was else None, retried=True if retry else None,
                     transient=True if n["road"] == "none" else None, also=also or None,
                     was_tries=1 if left_open and not moved and not retry else None)
        # the issues it follows are closed only once this one is open: a stall is never left with none.
        # The row is written first, its followed issues still open, so a kill before the closes leaves
        # no issue that no row names; a second row says what closed.
        if was:
            row["was_open"] = True
        append_escalation(row)
        if was and n["issue"] and not late():
            failed = []
            for f in [was] + also:
                ok, why = ask_mod().issue_state(int(f), "closed", "The class moved from %s to %s: followed in #%s." % (
                    from_cls, w["class"], n["issue"]))
                if not ok:
                    failed.append(f)
                    lines.append("escalation: #%s not closed (%s) — tried once more next pass" % (f, why))
            row = dict(row, was_open=True if was in failed else None, also=[f for f in failed if f != was] or None)
            append_escalation({k: v for k, v in row.items() if v is not None})
        say(w, "escalated", ": %s%s" % (n["road"], " #%s" % n["issue"] if n["issue"] else " — %s" % n["said"]))
    if held:
        lines.append("escalations: %d more wait for the next pass (at most %d a pass, and none past the tick's kill time)"
                     % (held, ESCALATE_MAX))

    # a key's absence counts only where its source was read this pass
    unread = res.get("unread") or {}
    gaps = {"runs": not res.get("hosts") or bool(unread.get("hosts")), "launches": bool(unread.get("launches")),
            "orca": bool(unread.get("orca")), "skippers": bool(unread.get("skippers")), "ships": not ships_unread["ships"]}
    for ek, prev in sorted(last.items()):
        if prev.get("state") not in OPEN_STATES + ("unrouted",) or ek in want or prev.get("yard") not in (None, me):
            continue
        src = prev.get("src") or ("ships" if prev.get("kind") in ("block", "ask") else "runs")
        if gaps.get(src) or prev.get("plan") in ships_unread["plans"] and src == "ships":
            continue   # its source unread this pass: a key missing from it may still be there
        v = seen.get(ek)
        last_p, absent = (list(v) + [None, None])[:2] if isinstance(v, list) else (v, None)
        last_p = float(last_p or prev.get("t") or t)
        if absent is None:
            seen[ek] = [last_p, t]   # the first miss on a pass that read its source: never a clear by itself
            continue
        if t - last_p < CLEAR_AFTER:
            continue   # one pass's absence is no clear: a glitch would close and reopen it
        why = "cleared" if prev.get("guarded") else cleared(prev, mem)
        if dry:
            lines.append("would close the escalation of %s: %s" % (prev.get("title") or "?", why))
            continue
        note = None
        # its own issue where it has one, and the one it followed while that is still open, whatever its road
        live = [n for n in ((prev.get("issue") if prev.get("road") == "github-issue" and prev.get("state") != "unrouted" else None),
                            ) if n] + followed(prev)
        if prev.get("close_tries") and prev.get("close_left"):
            live = list(prev["close_left"])   # the retry closes only what failed: no second comment on a closed one
        if live and late():
            continue   # no time left in this tick: tried on the next, no try spent
        failed = []
        for n in live:
            ok, err = ask_mod().issue_state(int(n), "closed", "Cleared on %s: %s." % (me, why))
            if not ok:
                failed.append(n)
                note = "#%s: %s" % (n, err)
        if note and not prev.get("close_tries"):
            # verify, then retry once: the row stays open, the next pass tries the close again
            append_escalation(dict(prev, t=t, close_tries=1, close_left=failed,
                                   why="its close failed (%s); tried once more next pass" % note))
            lines.append("escalation: %s not closed — tried once more next pass" % note)
            continue
        seen.pop(ek, None)
        append_escalation(row_of(ek, prev, "closed", prev.get("road"), prev.get("issue"), why, close_failed=note,
                                 close_failed_issues=failed or None))
        lines.append("escalation closed%s: %s — %s%s" % (" (#%s)" % prev["issue"] if prev.get("issue") else "",
                                                          prev.get("title") or _shown_key(prev.get("key")), why,
                                                          " (the issue not closed: %s — carded)" % note if note else ""))
    if not dry or keep:
        write_seen({k: v for k, v in seen.items() if k in want or (last.get(k) or {}).get("state") in OPEN_STATES + ("unrouted",)})
    return lines


def followed(row):
    """The issues an open row follows that are still open: its `was` while `was_open`, then `also`."""
    return ([row["was"]] if row.get("was_open") and row.get("was") else []) + list(row.get("also") or [])


ROAD_CARD_DAYS = 7   # a close that failed twice is carded this long; the owner may have closed it by hand


def road_faults(rows=None):
    """[row]: the escalations the road could not deliver or settle, newest per key — an open row with no
    issue after its one retry, a followed issue left open, a close that failed twice. helm_render cards
    each (road_cards): the owner sees on the board what GitHub never got."""
    last = {}
    for row in read_escalations() if rows is None else rows:
        last[row["ekey"]] = row
    out = []
    for r in last.values():
        st = r.get("state")
        if (st in OPEN_STATES and r.get("issue") is None and r.get("retried") and r.get("road") in (None, "none")) \
                or (st in OPEN_STATES and followed(r) and r.get("was_tries")) \
                or (st == "closed" and r.get("close_failed") and clock() - float(r.get("t") or 0) < ROAD_CARD_DAYS * 86400):
            out.append(r)
    return out


def cleared(prev, mem=None):
    """What cleared an unguarded escalation, in a phrase for the closing comment."""
    kind, pid, block = prev.get("kind"), prev.get("plan"), prev.get("block")
    if kind == "stall":
        ls = (mem.by_key.get(_k(prev.get("key"))) if mem else None) or []
        if ls and ls[-1].get("action") == "started":
            return "its retry's run started (%s)" % ls[-1].get("new_run")
        return "no longer judged a stall here"
    if kind in ("block", "ask") and pid:
        try:
            st = helmlib.state(pid)
        except (FileNotFoundError, ValueError):
            return "its ship is gone from this host"
        t = next((x for x in st["tasks"] if x["id"] == block), None)
        if not t:
            return "its block is gone from the ship"
        if t.get("guarded"):
            return "cleared"   # guarded since its issue opened (K6): nothing of it in the comment
        if kind == "ask":
            a = next((x for x in t["asks"] if x["ref"] == (prev.get("key") or [None] * 3)[2]), None)
            if a and a.get("answered"):
                return "answered%s" % (" by %s" % a["answer_from"] if a.get("answer_from") else "")
            if t["status"] in helmlib.ENDED:
                return "its block ended (%s)" % t["status"]
            try:
                import skipperlib
                if a and skipperlib.doc_answer(a):
                    return "answered in its doc"
            except Exception:   # noqa: BLE001 — the plain phrase below
                pass
            return "no longer open"
        if t["status"] in helmlib.ENDED:
            return "the block ended (%s)" % t["status"]
        return "the block is %s%s" % (t["status"], (" — %s" % t["progress"]) if t.get("progress") else "")
    if kind in ("block", "ask"):
        return "its ship ended or left the yard"
    return "no longer judged a stall here"


# ---------------------------------------------------------------------------- the scopes' skippers (skipper-resilience S5)

def ensure_skippers(mode_now, brake=None):
    """The pass over the scopes' skippers (bin/skipperlib.py's ensure, after wharf's pass): lines. It
    acts only when the tick is armed past its dry hours and its caller passes `helm skipper --start`'s
    own refusal (skipperlib.session_refusal: no session, none directly above it, no CLAUDE_UNATTENDED) — a
    session typing `helm tick` must not get round it by calling it in-process — and otherwise prints
    `would …`. A host with no lease and no
    skipper record prints nothing: the tick is what it was before S5. TICK_STARTS is not this
    pass's (one start per scope per pass is its own limit). A failure is one line, never the tick's.
    While the studio brake holds (`brake`, skipper-resilience S11) the pass starts and stops nothing, armed
    or not: the brake freezes a skipper's whole tree, and a job booted out while frozen would leave its
    claude orphaned and frozen with nothing listing it. It says so only where a scope is held here, so a
    host with no lease and no record still prints no line."""
    if os.environ.get("PLAN_NO_SKIPPERS"):
        return []
    if brake:
        try:
            import skipperlib
            held = skipperlib.scopes_here()
        except Exception:   # noqa: BLE001 — a fault in the look is no reason to act under the brake
            held = ["?"]
        return ["skippers: held — the studio brake holds (%s): none started or stopped" % brake] if held else []
    try:
        import skipperlib
        if not skipperlib.scopes_here():
            return []   # no lease, no record: not even the deadline's line (a host as before S5)
        try:
            dl = float(os.environ.get("STALLS_DEADLINE") or 0)
        except ValueError:
            dl = 0
        if dl and dl - time.time() < 40:
            return ["skippers: skipped — %ds before the tick's kill time" % max(0, dl - time.time())]
        # --start's own refusal, asked first: a session (and its direct descendants) and any
        # unattended caller (CLAUDE_UNATTENDED: a dispatched run, the skipper itself) get `would …`
        refused = skipperlib.session_refusal("the tick's pass") if mode_now == "armed" else None
        act = mode_now == "armed" and not refused
        why = None if act else (refused or "the tick is %s" % mode_now)
        return skipperlib.ensure(act, why)
    except Exception as e:   # noqa: BLE001 — a skipper's fault costs its lines, never the stalls' pass
        return ["skippers: the pass failed (%s: %s)" % (e.__class__.__name__, str(e)[:160])]


# ---------------------------------------------------------------------------- the dead-man's switch (skipper-resilience S11)
# A yard's tick ends by telling the switch off the yard that it ran (lighthouse's bin/deadman, a Cloudflare
# Worker that opens an issue when a yard that has pinged goes silent). It is the tick's last act, after the
# Orca read, wharf's pass and the skippers', so a tick killed at its deadline never gets here and the yard
# goes silent — the point. (Each Orca read is time-limited and returns a note, so an Orca that does not answer
# does not stop the ping; its source is only marked unread.) Three pings: plain (alive), `--braked` (alive, and the owner's
# studio brake holds: the Worker holds its alarm off until a plain ping), `--fail --why` (the pass raised).
# Only a host some scope's `yard` names pings (helmlib.yard_hosts: a torn registry reads no yard here, as the
# poll's own gate fails closed), so the laptop pings nothing; deadman itself pings only for the host it is
# on and only when its config lists that host.

PING_TIMEOUT = 40   # deadman's own request is 15 s; a vault read on Drive can be slow


def deadman_exe():
    """lighthouse's deadman through the core's tool(); HELM_DEADMAN replaces it (the tests': a path that
    is no file stands for an absent peer)."""
    v = os.environ.get("HELM_DEADMAN")
    if v is not None:
        return Path(v) if v and Path(v).is_file() else None
    return helmlib.peer("deadman")


def deadman_ping(brake=None, fail=None):
    """The ping, as lines: nothing on a host that is no yard; one quiet line when deadman is absent or
    the ping did not go (its failure is never the tick's, and never a `--fail`: that would be the switch
    reporting its own unreachability to itself). `fail` is the pass's one-line why."""
    yards, torn = helmlib.yard_hosts()
    me = helmlib.host()
    if torn or me not in yards:
        return []
    # the stall road's caller rule (act_refusal, less its mode): a session's or an unattended run's tick beside
    # launchd's would cover a dead poll with a plain ping, or open an issue from a run the owner typed
    if os.environ.get("CLAUDE_UNATTENDED"):
        return ["deadman: not pinged — an unattended caller (CLAUDE_UNATTENDED=%s)" % os.environ["CLAUDE_UNATTENDED"]]
    if os.environ.get("CLAUDE_CODE_SESSION_ID"):
        return ["deadman: not pinged — the tick runs inside session %s: the ping is launchd's tick's" % os.environ["CLAUDE_CODE_SESSION_ID"][:8]]
    exe = deadman_exe()
    if not exe:
        return ["deadman: not pinged — not installed (lighthouse)"]
    argv = [sys.executable, str(exe), "ping", me]
    if fail:
        argv += ["--fail", "--why", " ".join(str(fail).split())[:300]]
    elif brake:
        argv.append("--braked")
    try:
        # deadman pings only for the name it has for itself: hand it the tick's, so the two cannot differ
        p = subprocess.run(argv, capture_output=True, text=True, timeout=PING_TIMEOUT, env=dict(os.environ, DEADMAN_HOST=me))
    except (OSError, subprocess.TimeoutExpired) as e:
        return ["deadman: ping failed (%s)" % e.__class__.__name__]
    def tail(text):
        said = [x.strip() for x in (text or "").splitlines() if x.strip()]
        return re.sub(r"^deadman: ", "", said[-1])[:200] if said else ""
    out, err = tail(p.stdout), tail(p.stderr)
    if p.returncode:
        last = err or out
        return ["deadman: ping failed (exit %d)%s" % (p.returncode, ": " + last if last else "")]
    # a warning on stderr (a secret file at the wrong mode, an alarm the Worker could not close) is its own
    # line: it never replaces the line that says the ping went
    return ["deadman: " + (out or "pinged")] + (["deadman: " + err] if err else [])


def summary(line):
    a = line.get("action")
    if a == "retry":
        if line.get("what") == "relay":
            return "relayed: %s" % line.get("why")
        return "%s (retry %s of %d): %s" % ({"redispatch": "re-dispatched", "start": "started", "relaunch": "relaunched",
                                               "reland": "relaunched"}.get(   # a stalls.jsonl line from before rename S5
            line.get("what"), line.get("what")), line.get("attempt"), RETRIES, line.get("why"))
    if a == "dry":
        return "would %s — %s" % ({"refused": "be refused"}.get(line.get("would"), line.get("would")), line.get("why"))
    if a == "wait":
        return "waits — %s" % line.get("why")
    return "%s — %s" % ({"raise": "raised", "refused": "refused"}.get(a, a), line.get("why"))


def lines_of(r):
    out = ["helm tick: %s — %s" % (r["mode"], r["mode_why"])]
    if r.get("brake"):
        out.append("helm tick: the studio brake holds (%s) — no Orca read, no wharf pass, no skipper start or stop" % r["brake"])
    for f in r["followups"]:
        out.append("follow-up %s %s %s: %s" % (f.get("host"), f.get("repo"), f.get("topic"), f.get("why")))
    by, would = {}, {}
    for s, line, new in r["decisions"]:
        out.append("%s %s %s %s: %s%s" % (s.get("class") or "?", s.get("host"), s.get("repo"), s.get("topic") or s.get("branch"),
                                          summary(line), "" if new else " (unchanged)"))
        notes = [s.get("rule")]
        if s.get("guarded"):
            notes = [s.get("rule"), "guarded — open it"]
        else:
            notes.append(stalls.evidence_line(s))
        if line.get("classifier"):
            c = line["classifier"]
            notes.append("classifier: %s%s" % (c.get("label"), " p=%.2f" % c["p"] if isinstance(c.get("p"), (int, float)) else ""))
        out.append("    " + " · ".join(n for n in notes if n))
        out.append("    key %s" % json.dumps(s.get("key")))
        by[line["action"]] = by.get(line["action"], 0) + 1
        if line["action"] == "dry":
            w = str(line.get("would") or "?").split(" ")[0]
            would[w] = would.get(w, 0) + 1
    out += r.get("escalations") or []
    out += r["notes"]
    n_unsure = sum(1 for s, _, _ in r["decisions"] if s.get("class") is None)
    counts = ", ".join("%d %s" % (n, a) for a, n in sorted(by.items())) or "none"
    if would:
        counts += " (would: %s)" % ", ".join("%d %s" % (n, a) for a, n in sorted(would.items()))
    out.append("%d stalls, %d unsure — %s; hosts %s; log %s%s" % (
        len(r["decisions"]) - n_unsure, n_unsure, counts, ", ".join(r["hosts"]), r["log"],
        "" if r["wrote"] else " (not written)"))
    return out


def as_json(r):
    # stalls, unsure and dry are what ask poll's cache and the statusline read (B4)
    brief = lambda s: {k: s.get(k) for k in ("class", "host", "repo", "topic", "branch")}
    return {"mode": r["mode"], "mode_why": r["mode_why"], "as_of": r["as_of"], "hosts": r["hosts"], "notes": r["notes"],
            "dry": r["mode"] != "armed",
            "stalls": [brief(s) for s, _, _ in r["decisions"] if s.get("class")],
            "unsure": [brief(s) for s, _, _ in r["decisions"] if not s.get("class")],
            "followups": r["followups"], "log": r["log"], "wrote": r["wrote"], "escalations": r.get("escalations") or [],
            "brake": r.get("brake"),
            "decisions": [dict(line, title=s.get("title"), rule=s.get("rule"), new=new) for s, line, new in r["decisions"]]}
