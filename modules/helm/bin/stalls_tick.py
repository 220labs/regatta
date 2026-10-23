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

stalls.jsonl (~/Library/Logs/claude-weekly/, laptop-local, O_APPEND) is the log and the retry
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

def read_log():
    try:
        text = log_path().read_text(encoding="utf-8")
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


def append(line):
    """One line, O_APPEND, as helmlib.append_event: two ticks never interleave a line."""
    p = log_path()
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
    # dispatch's own numbers (its max_runs; test_dispatch.sh checks the copy): 10 on a build box (a
    # host the laptop reaches over ssh, `wharf-runs/ssh`), 3 elsewhere, DISPATCH_MAX_RUNS over either
    cap = int(os.environ.get("DISPATCH_MAX_RUNS") or (10 if helmlib.host() in helmlib.ssh_peers() else 3))
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


def tick(dry_run=False, peer=True):
    """Judge, gate, act: {"mode", "mode_why", "decisions": [(stall, line)], "followups", "notes", …}.
    dry_run: the verdicts as an armed tick would reach them, nothing called past the judge and
    nothing written."""
    t = clock()
    m, m_why = mode(t)
    try:
        deadline = float(os.environ.get("STALLS_DEADLINE") or 0)   # epoch; ask poll passes its kill time
    except ValueError:
        deadline = 0
    if dry_run:
        m, m_why = "dry-run", "--dry-run: nothing called, nothing written"
    res = stalls.judge(peer=peer)
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
    return {"mode": m, "mode_why": m_why, "as_of": t, "hosts": res["hosts"], "decisions": decisions,
            "followups": followups, "notes": notes, "log": str(log_path()), "wrote": write}


CLASSIFIER_NOTE = "bin/gate classify %s would say retry or raise" % CLASSIFY_SITE


# ---------------------------------------------------------------------------- the scopes' skippers (skipper-resilience S5)

def ensure_skippers(mode_now):
    """The pass over the scopes' skippers (bin/skipperlib.py's ensure, after wharf's pass): lines. It
    acts only when the tick is armed past its dry hours and its caller passes `helm skipper --start`'s
    own refusal (skipperlib.session_refusal: no session, none directly above it, no CLAUDE_UNATTENDED) — a
    session typing `helm tick` must not get round it by calling it in-process — and otherwise prints
    `would …`. A host with no lease and no
    skipper record prints nothing: the tick is what it was before S5. TICK_STARTS is not this
    pass's (one start per scope per pass is its own limit). A failure is one line, never the tick's."""
    if os.environ.get("PLAN_NO_SKIPPERS"):
        return []
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
            "followups": r["followups"], "log": r["log"], "wrote": r["wrote"],
            "decisions": [dict(line, title=s.get("title"), rule=s.get("rule"), new=new) for s, line, new in r["decisions"]]}
