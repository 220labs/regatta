#!/usr/bin/env python3
"""Stalls: work that stopped without saying so, sorted into the stall classes S1–S7
(docs/chain-manager-2026-10-11.md section 4 and its launch review; orchestration B1).

    stalls.py [--json] [--no-peer]   every stall on this Mac and each peer that is no yard, one line each

`helm board` draws a card per stall and `helm tick --dry-run` prints what it would do; both call
judge(). Nothing here acts: the one live call is `dispatch-rc live --no-reap` (the run count an S2
needs; it never reaps), and the build box is read over one ssh, never written (ssh runs laptop → build
box only) — while it is no scope's yard: a yard judges its own store on its own tick (skipper-resilience
S8), and the laptop leaves it out (peers()). The actions are B3's, bin/stalls_tick.py, and so are the gates (armed, the week, `account
pick`, the lock, the depth cap, the retry memory in stalls.jsonl): a stall here carries the class's
action and the facts those gates read, nothing decided past that.

What is read:
    run records      ~/Library/Logs/claude-weekly/run-seed-runs/*.json on both Macs, through
                     dispatch-rc's typed() (dispatch wrote every value as a string until B2)
    the registry     through the harness adapter's V4 list and V3 status
                     (bin/harness_adapters/claude_code.py) — nothing of Claude's is read here
    autofinished     <common git dir>/claude/autofinished of each repo in repos.json cloned here,
                     with the stopped worktree's autofinish.json (the laptop's only: the build box
                     is disarmed for launch, and a landing the laptop sends there writes its end
                     here too — autofinish-run's Where — so a launch stalls only here)
    the plan store   helmlib.state() of every plan on this Mac (S7)
    ask poll's cache ~/Library/Caches/ask/asks.json: a WAITING line whose branch holds an open D-item
                     is already an ask (`asks N`), never also a stall (launch review, S6)
    Codex            the codex adapter's own run records (harness-runs/codex-*.json): a harness Codex run
                     that ended failed is an S1 card, raised (the Codex section below; vendor-fence)
    Orca             `bin/harness list --harness orca --unsettled`, and the orca adapter's task-list,
                     run-show and `check --peek` (this Mac only; the Orca section below, B8)
    the canary       wharf-runs' `clock canary check --json` (this Mac only; the class `start path dead`,
                     orca-launcher S7): one stall per canary beat that fails, raised

A stall record — the shape B3 acts on and its classifier (D4 = C, `bin/gate classify`) reads:
    class      S1…S7, or None in `unsure` (the rules could not tell; B3's classifier's input)
    action     retry (A1, S1) | start (A1, S2) | relaunch (A2, S4) | relay (an Orca question, S6) |
               raise (A3) | classify (unsure)
    raise_to   owner | skipper, for a raise (`manager` before rename S5, and the owner's name before
               the scrub: stalls.jsonl keeps both, read forever — only the skipper's is matched)
    key        the retry memory's key: (host, repo, topic, brief_blob) for a build step — the tip
               moves with every checkpoint, so it cannot key a step's once — (host, branch, tip)
               for a launch, (host, plan, task) for S7. key_kind says which
    rule       the rule that decided, as bin/session_status.py names its rules
    evidence   short lines for the card: the record, its end, the last reply's last line, the
               autofinished line
    plus host, repo, topic, branch, run (the record's file name), session, since, depth, brief,
    manager, plan, tip, guarded, title, column (the board's); `dispatch`, the record's fields a
    re-dispatch needs (DISPATCH_KEYS); for S4 the worktree, the stopped run's `by` and `af_rule`;
    for an unsure run its last reply (REPLY_CHARS) and its end, the classifier's input

Which records are judged: a build step (topic not `finish-*`; S1, S2, S6 apply to build steps
only, launches are autofinish's), whose branch still exists where it ran (a launched branch moves to
refs/archive) and that nothing has superseded — no later record of the same repo on the same topic
or branch, on either Mac (a step run again, by hand or by the chain, or a launch started on it).

Stdlib only, Python 3.9. STALLS_PEERS (`buildbox=buildbox-ssh`; empty: none;
unset: the config dir's `wharf-runs/ssh`), STALLS_SSH,
STALLS_REPOS (colon-separated repo paths), STALLS_ORCA (0: no Orca read, and so no canary read unless
STALLS_CANARY names a stand-in), STALLS_CANARY (0: no canary read; a command: stands in for `clock
canary check --json`), STALLS_HARNESS (bin/harness stands in) and the HOME the tests move are the knobs.
"""
import argparse
import glob
import hashlib
import inspect
import json
import os
import re
import shlex
import subprocess
import sys
import time
from importlib.machinery import SourceFileLoader
from importlib.util import module_from_spec, spec_from_loader
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import helmlib  # noqa: E402

# wharf-runs' Claude Code adapter, found beside its harness (helmlib.harness_adapter); None when
# wharf-runs is not installed, and then there are no runs to judge (judge() says so)
ADAPTER = helmlib.harness_adapter("claude_code.py")
# machine → the ssh alias the laptop reads it with (pickup's PEERS, the config dir's `wharf-runs/ssh`):
# the build box has none for the laptop, which sleeps, so a stall is judged from the laptop
# (chain-manager D2 = digest D5 A) — until the box is a scope's yard, which judges its own
# (skipper-resilience S8, peers())
PEERS = helmlib.ssh_peers()
SSH_TIMEOUT = 10        # ConnectTimeout: a sleeping peer holds a connect ~75 s (R2)
PROBE_TIMEOUT = 90      # the whole read, transcripts included
IDLE_DECIDES = 3600     # a live run idle this long: its last reply decides (section 4, A4)
S7_QUIET = 30 * 60      # a ready task nobody reported on for this long (S7)
TEXT_LINE = 160         # an evidence line's length
GUARDED = helmlib.GUARDED

# autofinished's stop text that means the network or sleep, anchored at its start (R4: a WAITING
# line that quotes an API error must not match). "Not logged in" is a person's (S5, auth-required).
NET_RE = re.compile(r"^(?:API Error\b|Your computer went to sleep|.{0,60}\bECONNREFUSED\b)")
LOGIN_RE = re.compile(r"Not logged in|/login\b|OAuth token|authentication_error", re.I)
# dispatch's own words (bin/dispatch): the run-cap refusal a `--next` ends on (S2), and deep()'s
# depth line (S6, never retried)
CAP_RE = re.compile(r"the next step waits for a run to end", re.I)
# dispatch's pending line once the queue holds a step (its queue_close): `queued <branch> (<priority>); the next
# step waits for a run to end`, the branch it queued named in it (S3's third landing review, item 6)
PENDING_RE = re.compile(r"\bqueued (\S+) \((?:low|normal|high|force)\); the next step waits for a run to end\b")
DEEP_RE = re.compile(r"the next step waits for [\w' ]{1,40}? to start it", re.I)   # a person's name, or the owner
# a record's end that is a person's decision or dispatch's own retry: never a stall (F11)
NOT_STALLS = re.compile(r"^(?:ended by dispatch --end|never started)")
# S10 (dispatch --requeue): a run its host handed back, ended with this reason; its step waits in the queue
REQUEUED_END = re.compile(r"^requeued from (\S+)")
# S10(e): a host that may sleep says so — a `<host>:sleeps` line here, or the core's laptop — and, unreachable with
# no fresh queue word of its own (seen_at, which its sweep writes), reads `asleep`; any other host stays unreachable
POWER_KEY = "wharf-runs/power"
SLEEP_AFTER = 2 * 600   # two of dispatch-queue's sweeps, as its queue-silent card waits
GONE_ENDS = re.compile(r"^(?:tidied: its claude was gone|claude exited by itself)")

ACTIONS = {"S1": "retry", "S2": "start", "S4": "relaunch"}
WONT_START = "skipper won't start"   # skipper-resilience S5's class: a scope's skipper failed three starts (raised)
CANARY_DEAD = "start path dead"      # orca-launcher S7's class: a canary beat is outside its window, or its run reached no first turn (raised)
CANARY_TIMEOUT = 135                 # `clock canary check`: two Orca CLI reads of 60 s each and two 5 s sysctl
CANARY_BRAKE_GRACE = 90 * 60         # an hourly beat's window (60 + clock's CANARY_GRACE 30): what a brake's end owes it
CANARY_AGO_RE = re.compile(r"\d+ min ago")
CANARY_KEY_RE = re.compile(r"^canary ([^:\s]+):\s*(.*)$", re.S)
# a raise to the ship's live skipper: written `skipper` since rename S5, `manager` read forever (stalls.jsonl)
RAISE_TO_SKIPPER = ("skipper", "manager")
DISPATCH_KEYS = ("repo", "wt", "model", "effort", "yolo", "pin", "manager", "manager_host", "manager_account",
                 "plan", "plan_space")
REPLY_CHARS = 1500      # of an unsure run's last reply, for B3's classifier (never a guarded repo's)
SUGGESTED = {
    "retry": "re-dispatch once, fresh from the brief, with a note (A1)",
    "start": "start the next step once dispatch-rc live --no-reap is under the cap (A1)",
    "relaunch": "autofinish-run <worktree> --by chain, once on this tip (A2)",
    "raise": "raise it (A3)",
    "classify": "ask B3's classifier (bin/gate classify)",
    "relay": "bin/ask relay <doc> <Dn>, once, to the run's skipper (an Orca worker's question, B8)",
}


def _load_bin(name):
    """A peer's dash-named script as a module (wharf-runs' dispatch-rc: typed(), same(),
    watcher_gone()), through the core's tool(); None when it is not installed."""
    path = helmlib.peer(name)
    if not path:
        return None
    loader = SourceFileLoader(name.replace("-", "_"), str(path))
    mod = module_from_spec(spec_from_loader(loader.name, loader))
    loader.exec_module(mod)
    return mod


def adapter():
    if not ADAPTER:
        return None
    loader = SourceFileLoader("claude_code_adapter", str(ADAPTER))
    mod = module_from_spec(spec_from_loader(loader.name, loader))
    loader.exec_module(mod)
    return mod


def runs_dir():
    return Path(os.environ.get("HOME") or Path.home()) / "Library/Logs/claude-weekly/run-seed-runs"


def launching(topic):
    return str(topic or "").startswith("finish-")


def repo_name(path):
    return Path(str(path or "")).name


# ---------------------------------------------------------------------------- facts, here or there

def waiting_prefix():
    """The core's WAITING line opening (common.WAITING_PREFIX: the owner's address, if configured, then
    the words); the words alone without a core. Read here and sent to the peer: facts() runs there
    without the core."""
    try:
        return helmlib._common().WAITING_PREFIX
    except Exception:
        return "THIS SESSION IS WAITING FOR YOU — "


def facts(records, ad, same, watcher_gone, guarded, waiting=None):
    """What each record's host knows of it, in one shape for both Macs — this function runs here,
    and on a peer inside the ssh probe (its source is sent, as pickup sends PEER_PROBE): {name:
    {"alive", "watcher", "branch", "status", "owner"}} plus "live", the V4 list's session ids and
    states. `branch` is True/False for the branch's refs/heads on this host, None when the repo is
    not here. `status` (V3) is read for a build step only, without its text in a guarded repo.
    `owner` is the run's worktree lock (`<git dir>/claude/owner.json`, hooks/common.py's shape) as
    its host has it: B3's gate 5 reads it, and a peer's can only be read there. `waiting`: the WAITING
    line's opening (waiting_prefix(), the caller's), matched as common.ending reads a reply — link lines
    may follow it, markup around it changes nothing; without an address in it, any `<name>, ` opens it."""
    import re as _re
    import subprocess as sp
    refs = {}
    words = (waiting or "THIS SESSION IS WAITING FOR YOU — ").strip()
    if "," not in words.split(" THIS SESSION")[0]:
        words = words.split(", ", 1)[-1]
    link = _re.compile(r"^(?:\[[^\]]*\]\([^)]*\)|https?://\S+|<[^>]+>)(?:\s*[|·—-]\s*(?:\[[^\]]*\]\([^)]*\)|https?://\S+))*$")

    def ends_waiting(text):
        lines = [x.strip() for x in (text or "").splitlines() if x.strip()]
        while lines and link.match(lines[-1]):
            lines.pop()
        last = lines[-1].strip("*`_ ") if lines else ""
        # the core's mark (🛑, its MARKS; spaced or not, as the core's _MARK_RE) and markup inside it; written out, as this runs on a peer without the core
        last = _re.sub("^[\u2190-\u2bff\U0001F000-\U0001FAFF\ufe0f\u200d]+[ \t]*", "", last).strip("*`_ ")
        last = _re.sub(r"^[^,]{1,40}, (?=THIS SESSION)", "", last) if "," not in words.split(" THIS SESSION")[0] else last
        return last.startswith(words)

    def has_branch(repo, branch):
        if not repo or not branch:
            return None
        if repo not in refs:
            try:
                r = sp.run(["git", "-C", repo, "for-each-ref", "--format=%(refname)", "refs/heads/"],
                           capture_output=True, text=True, timeout=15)
                refs[repo] = set(r.stdout.split()) if r.returncode == 0 else None
            except (OSError, sp.TimeoutExpired):
                refs[repo] = None
        return None if refs[repo] is None else ("refs/heads/" + branch) in refs[repo]

    def owner(wt):
        if not wt:
            return None
        try:
            r = sp.run(["git", "-C", wt, "rev-parse", "--absolute-git-dir"], capture_output=True, text=True, timeout=15)
            if r.returncode or not r.stdout.strip():
                return None   # a worktree gone: no lock, never ./claude/owner.json of the tick's own cwd
            with open(os.path.join(r.stdout.strip(), "claude", "owner.json")) as fh:
                d = json.load(fh)
        except (OSError, ValueError, sp.TimeoutExpired):
            return None
        return d if isinstance(d, dict) else None

    out = {}
    for name, st in records:
        f = {"alive": False, "watcher": False, "branch": None, "status": None, "owner": None}
        try:
            f["alive"] = bool(same(st))
        except Exception:   # a pid past 2**31, a registry file that is no object: not running
            f["alive"] = False
        try:
            f["watcher"] = isinstance(st.get("watcher"), int) and not watcher_gone(st)
        except Exception:
            f["watcher"] = False
        f["branch"] = has_branch(st.get("repo"), st.get("branch"))
        reason = str(st.get("end_reason") or "")
        topic = str(st.get("topic") or "")
        if st.get("session") and not topic.startswith("finish-") and f["branch"] \
                and not reason.startswith(("ended by dispatch --end", "never started")):
            # helmlib.guarded's rule, spelled out: this function's source runs on the peer too, without helmlib
            g = any(part.casefold() in {x.casefold() for x in guarded} for part in str(st.get("repo") or "").split("/"))
            try:
                f["status"] = ad.status(st["session"], read_reply=not g)
            except Exception as e:
                f["status"] = {"error": str(e)[:200]}
            f["owner"] = owner(st.get("wt"))
        out[name] = f
    # skipper-modes S5: every live session's state, cwd and branch (a peer's permission prompts are
    # carded from these), and the sessions no run owns whose last reply ends on the WAITING line —
    # read for that line only, never kept: the card is the repo, "waiting on <owner>" and a link (K6)
    live, waiting = [], []
    try:
        for r in ad.list():
            live.append({"session_id": r["session_id"], "state": r["state"], "cwd": r.get("cwd"),
                         "branch": r.get("branch"), "updated": r.get("updated_at")})
            if (r.get("native") or {}).get("run") or not r.get("session_id"):
                continue
            # a guarded repo's reply is never read (this function's rule above; landing review 15)
            if any(part.casefold() in {x.casefold() for x in guarded} for part in str(r.get("cwd") or "").split("/")):
                continue
            try:
                text = (ad.last_reply(r["session_id"]) or {}).get("text") or ""
            except Exception:
                continue
            if ends_waiting(text):
                waiting.append({"session_id": r["session_id"], "cwd": r.get("cwd"), "branch": r.get("branch"),
                                "since": r.get("updated_at")})
    except Exception:
        pass
    return {"records": out, "live": live, "waiting": waiting}


PROBE_MAIN = r'''
import types
RUNS = os.path.join(os.environ.get("HOME") or os.path.expanduser("~"), "Library/Logs/claude-weekly/run-seed-runs")
recs = []
for path in sorted(glob.glob(os.path.join(RUNS, "*.json"))):
    try:
        with open(path) as fh:
            st = typed(json.load(fh))
    except (OSError, ValueError):
        continue
    if isinstance(st, dict):
        recs.append((os.path.basename(path), st))
ad = types.SimpleNamespace(status=status, list=list, last_reply=last_reply)
res = facts(recs, ad, same_lite, watcher_gone, tuple(json.loads(sys.argv[1])), json.loads(sys.argv[2]) if len(sys.argv) > 2 else None)
res["raw"] = dict(recs)
res["home"] = os.environ.get("HOME")
print(json.dumps(res))
'''

SAME_LITE = r'''
def same_lite(st):
    """dispatch-rc's same() for the probe: the pid alive with its recorded start; a record from
    before proc_start was recorded counts as alive while its pid is (no registry to ask here)."""
    pid = st.get("pid")
    if not isinstance(pid, int):
        return False
    if st.get("proc_start"):
        return running(pid, st["proc_start"])
    try:
        os.kill(pid, 0)
        return True
    except (OSError, OverflowError):
        return False
'''


def probe_source(rc):
    """The script a peer runs: the adapter, dispatch-rc's own typed()/proc_start()/running()/
    watcher_gone(), facts() — the same code as here — and a main that prints one JSON object."""
    # the adapter's own source: bin/harness_adapters/ holds source shims since regatta-modules B7, and
    # a shim sent to the peer would load the peer's copy (or fail without a regatta clone there);
    # the loaded module's __file__ is the real file's, as the shim sets it (carried from B7, 325eac3)
    parts = [Path(adapter().__file__).read_text(), "import subprocess, sys", "INTS = %r" % (rc.INTS,)]
    for fn in (rc.typed, rc.proc_start, rc.running, rc.watcher_gone, facts):
        parts.append(inspect.getsource(fn))
    parts += [SAME_LITE, PROBE_MAIN]
    return "\n\n".join(parts)


def peers():
    """{host: ssh alias} to read, this Mac left out. STALLS_PEERS overrides: `name=alias,…`, empty for none.
    Every peer is read, a yard too: its records and live sessions are the facts both Macs share (the
    superseded test, a skipper live over there). Which of them are judged is self_judging()'s."""
    if "STALLS_PEERS" in os.environ:
        spec = os.environ["STALLS_PEERS"].strip()
        out = dict(x.split("=", 1) for x in spec.split(",") if "=" in x)
    else:
        out = dict(PEERS)
    out.pop(helmlib.host(), None)
    return out


def self_judging():
    """(hosts, torn): the hosts, other than this one, whose runs are acted on where they are
    (skipper-resilience S8) — each host some scope's `yard` names runs its own tick (bin/ask
    poll_tick) — and whether that could not be told (helmlib.yard_hosts: a torn registry, no core).
    The judge still judges their records (the board shows them); the tick acts on no stall of a host
    in `hosts`, and on none of any peer's while `torn` (fail closed, the fence trap: a yard and the
    laptop must never both act on one run). With no yard set and a registry that reads, nothing changes."""
    yards, torn = helmlib.yard_hosts()
    return yards - {helmlib.host()}, torn


def asleep(host, queued, now):
    """S10(e): why an unreachable HOST reads asleep, or None. Only a host that may sleep, by a positive word: a
    `<host>:sleeps` line in POWER_KEY, or the core's laptop; a build host that goes down stays unreachable (the
    landing review: keyed on a missing line, every down host read asleep). And only while the queue holds no
    fresh word from it — the seen_at its sweep writes on the entries it runs, younger than SLEEP_AFTER, says it is
    awake with its ssh down. The queue is read only for such a host."""
    try:
        c = helmlib._common()
        lines = c.config_lines(POWER_KEY) or []
        laptop = str(getattr(c, "LAPTOP", "") or "").lower()
    except Exception:   # noqa: BLE001 — no core: nothing can be told, so no new word
        return None
    word = next((l.partition(":")[2].strip().lower() for l in lines if l.partition(":")[0].strip().lower() == host.lower()), None)
    if word != "sleeps" and not (word is None and host.lower() == laptop):
        return None
    ents = queued.entries()
    if ents is None:
        return None   # the queue gave no answer this pass: could not tell, so unreachable as before
    seen = [int(e.get("seen_at") or 0) for e in ents if (e.get("running_on") or "").lower() == host.lower()]
    last = max(seen) if seen else 0
    if last and now - last < SLEEP_AFTER:
        return None
    return "asleep (it may sleep; %s)" % ("its queue entries unseen %d min" % ((now - last) // 60) if last else "no queue word of its own")


def read_peer(host, alias, rc):
    """(facts, note): a peer's records and facts over one ssh, or (None, "<host>: unreachable …")."""
    ssh = os.environ.get("STALLS_SSH") or "ssh"
    cmd = [ssh, "-o", "BatchMode=yes", "-o", "ConnectTimeout=%d" % SSH_TIMEOUT, alias,
           "python3 - %s %s" % (shlex.quote(json.dumps(list(GUARDED))), shlex.quote(json.dumps(waiting_prefix())))]
    try:
        r = subprocess.run(cmd, input=probe_source(rc), capture_output=True, text=True, timeout=PROBE_TIMEOUT)
    except (OSError, subprocess.TimeoutExpired) as e:
        return None, "%s: unreachable (%s)" % (host, e.__class__.__name__)
    if r.returncode != 0:
        why = (r.stderr.strip().splitlines() or ["exit %d" % r.returncode])[-1][:160]
        return None, "%s: unreachable (%d s) — %s" % (host, SSH_TIMEOUT, why)
    try:
        d = json.loads(r.stdout)
    except ValueError:
        return None, "%s: the probe printed no JSON" % host
    return d, "%s: %d records read" % (host, len(d.get("raw") or {}))


def local_view(rc, ad):
    recs = []
    for f in sorted(glob.glob(str(runs_dir() / "*.json"))):
        try:
            st = rc.typed(json.loads(Path(f).read_text()))
        except (OSError, ValueError):
            continue
        if isinstance(st, dict):
            recs.append((Path(f).name, st))
    d = facts(recs, ad, rc.same, rc.watcher_gone, GUARDED, waiting_prefix())
    d["raw"] = dict(recs)
    return d


# ---------------------------------------------------------------------------- the classes

def _last_line(text):
    lines = [x.strip() for x in (text or "").splitlines() if x.strip()]
    return lines[-1][:TEXT_LINE] if lines else ""


def pending_branch(text):
    """The branch dispatch's pending line names, when the reply ends on it, or None. The line is the reply's
    closing line as the Stop hook reads it (the core's ending(): the last closing line, only link lines after
    it, never inside a code fence), so a pending line quoted above another closing line, or in a fence, is no
    queued step; and the exact line, never the cap's words alone (S3's third landing review, item 6, and its
    in-round review). Without the core: the last line alone."""
    try:
        line = helmlib._common().ending(text)[1]
    except Exception:   # noqa: BLE001 — no core here, or one without ending(): the last line, the strict side
        line = _last_line(text)
    m = PENDING_RE.search(line or "")
    return m.group(1).strip("*`_") if m else None


def _ago(t, now):
    if not t:
        return "?"
    s = max(0, int(now - float(t)))
    return "%dm" % (s // 60) if s < 5400 else "%dh" % (s // 3600) if s < 172800 else "%dd" % (s // 86400)


def _num(x):
    return x if isinstance(x, (int, float)) and not isinstance(x, bool) else None


def poll_asks():
    """{(repo name, branch)} with an open D-item in ask poll's cache (they are asks already), and each
    branch the poll skipped for its merged or closed PR (`ended`, board-cleanup S1): a WAITING run there
    was asked before the poll dropped its rows, and is no new stall now."""
    p = Path(os.environ.get("ASK_CACHE_DIR") or Path(os.environ.get("HOME") or Path.home()) / "Library/Caches/ask") / "asks.json"
    try:
        d = json.loads(p.read_text())
    except (OSError, ValueError):
        return set()
    return {(a.get("repo"), a.get("branch")) for a in (d.get("asks") or []) + (d.get("ended") or []) if isinstance(a, dict)}


# one queue read per pass: a fetch of the queue's home, or its cache when the home is away. list's fetch may
# wait 45 s for the clone's lock and then 30 s for the home, so 45 cut a slow read short and held every
# branch as unreadable (dispatch-queue S3's landing review, item 10): autofinish's and soundings' 90
QUEUE_TIMEOUT = 90


def queue_reader():
    """wharf-runs' queue_holds.Holds over dispatch-queue, or None with no wharf-runs here (nothing held,
    readable): the one "does the queue hold this branch" reader autofinish and sextant's soundings share
    (dispatch-queue S4; S3's third landing review, item 7). STALLS_DISPATCH_QUEUE is the tests' stand-in."""
    lib = helmlib.peer("queue_holds.py")
    q = os.environ.get("STALLS_DISPATCH_QUEUE") or helmlib.peer("dispatch-queue")
    if not q:
        return None
    if not lib:
        raise RuntimeError("a dispatch-queue with no queue_holds.py beside it")   # could not tell: held
    if str(lib.parent) not in sys.path:
        sys.path.insert(0, str(lib.parent))
    import queue_holds  # noqa: PLC0415 — wharf-runs', found through the core's tool()
    return queue_holds.Holds(q, timeout=QUEUE_TIMEOUT)


class QueueRead:
    """The queue-first rule (dispatch-queue S3; the contract's readers): a session that queued its step ends
    on the pending line, `queued <branch> …; the next step waits for a run to end`, and its run then ends —
    which read alone is S1's "nothing woke it", a retry of a step the queue already holds, or, on the cap's
    words, S2's start beside it. So a branch the queue holds is `queued`, never a stall; a queue that cannot
    be read holds every branch, and one store that cannot be read the branches routed to it (the readers'
    rule, queue_holds). Read once per pass, and only when a run's line asks: most passes judge no pending
    run, and a read fetches the home."""

    def __init__(self):
        self.reader, self.made, self.bad, self.last_bad = None, False, None, None

    def entries(self):
        """The queue's entries as this pass read them, or None when it gave none (S10(e)'s asleep test)."""
        if not self.made:
            self(None, None)
        if not self.reader:
            return None
        return self.reader.read()[0]

    def __call__(self, repo, branch, here=None):
        """True when the queue holds BRANCH of REPO (a name). `last_bad`: this answer held only because the
        queue (or the store the branch routes to) does not read, the card's why; `bad`: any answer of the pass
        did, the pass's note."""
        if not self.made:
            self.made = True
            try:
                self.reader = queue_reader()
            except Exception:   # wharf-runs present but its reader broken: could not tell, so held
                self.reader = False
        if self.reader is False:
            self.bad = self.last_bad = "dispatch's queue reader failed"
            return True
        if repo is None:
            return False
        why = self.reader.why(repo, branch, here=here) if self.reader else None
        self.last_bad = why if why and why.endswith("counts as there") else None
        self.bad = self.bad or self.last_bad
        return bool(why)


WAITING_ON_OWNER = "waiting on the owner"


def reply_kind(text):
    """bin/session_status.py's closing() on the last reply: done | waiting on the owner (WAITING_ON_OWNER,
    whatever wharf's WAITING says) | waiting on skipper (manager) | handed to its launch | waiting on its own work | None — the
    Stop hook's own reading of the line, so the same line counts here or none."""
    if not text:
        return None
    try:
        p = helmlib.peer("session_status.py")   # wharf's: the Stop hook's reader
        if not p:
            return None
        if str(p.parent) not in sys.path:
            sys.path.insert(0, str(p.parent))
        import session_status
        kind = session_status.closing(text)
        return WAITING_ON_OWNER if kind == getattr(session_status, "WAITING", None) else kind
    except Exception:
        return None


def evidence_line(s, n=2):
    """The card's evidence: the first n lines past the record's own name."""
    return " · ".join([e for e in s["evidence"] if not e.startswith("record ")][:n]) or None


def _stall(cls, host, st, name, rule, evidence, now, since=None, **kw):
    action = kw.pop("action", None) or ACTIONS.get(cls, "raise")
    repo = repo_name(st.get("repo"))
    rec = {"class": cls, "host": host, "repo": repo, "topic": st.get("topic"), "branch": st.get("branch"),
           "key": [host, repo, st.get("topic"), st.get("brief_blob")], "key_kind": "step",
           "action": action, "raise_to": kw.pop("raise_to", "owner" if action == "raise" else None),
           "suggested": SUGGESTED[action], "rule": rule, "evidence": [e for e in evidence if e],
           "run": name, "session": st.get("session"), "since": since or _num(st.get("started")),
           "depth": _num(st.get("depth")), "brief": st.get("brief"), "manager": st.get("manager"),
           "plan": st.get("plan"), "tip": None, "guarded": helmlib.guarded(repo)}
    # what B3's re-dispatch needs to start the same step again, as dispatch recorded it (B2): the
    # repo's path on its host, the worktree, the run's mode and its skipper's road
    rec["dispatch"] = {k: st.get(k) for k in DISPATCH_KEYS if st.get(k) not in (None, "")}
    rec.update(kw)
    return rec


def judge_runs(host, view, all_records, live_ids, asked, now, live_count=None, read=None, queued=None, queued_out=None):
    """(stalls, unsure) of one host's run records. `all_records` is every record of both Macs, as
    (host, name, st), for the superseded test; `live_ids` every live session id on both; `read` the
    hosts this one has a road to (itself and its peers, read or not; None: no rule) — a skipper on any
    other host cannot be seen from here, so its RELAYED run is never called orphaned (a yard reads no
    laptop; skipper-resilience S8). A peer that did not answer this pass keeps the rule it had. `queued`
    (a QueueRead) says whether dispatch's queue holds a branch: such a run is put in `queued_out` (a
    `queued` line in the pass's notes), never an S1 or S2 stall (dispatch-queue S3)."""
    stalls, unsure = [], []
    raw = view.get("raw") or {}
    # a stall B3 may act on carries its worktree's lock as facts() read it on its host (`owner`):
    # the tick's lock gate reads it, and a peer's run's lock can only be read there
    for name, f in sorted((view.get("records") or {}).items()):
        st = raw.get(name)
        if not isinstance(st, dict) or launching(st.get("topic")) or st.get("probe"):
            continue
        reason = str(st.get("end_reason") or "")
        # `ending` too: a headless run writes its own exit code over the requeue's reason (dispatch's requeued_end)
        rq = REQUEUED_END.match(str(st.get("ending") or "")) or REQUEUED_END.match(reason)
        if NOT_STALLS.match(reason) or f.get("branch") is not True:
            continue
        started = _num(st.get("started")) or 0
        repo = repo_name(st.get("repo"))
        later = [(h, n) for h, n, o in all_records if (h, n) != (host, name) and repo_name(o.get("repo")) == repo
                 and (o.get("topic") == st.get("topic") or (st.get("branch") and o.get("branch") == st.get("branch")))
                 and (_num(o.get("started")) or 0) > started]
        if later:
            continue   # run again, or a launch started on it: the newer record is judged instead
        # held means queued for another host: an entry still running on this one is the requeue's op lost (here=)
        if rq and queued is not None and queued(repo, st.get("branch"), here=host):
            # handed back by its host (S10) and held by the queue: the board reads where it went. One the queue no
            # longer holds (its op lost, or dropped) falls through to the rules below, the requeue in its evidence
            if queued_out is not None:
                queued_out.append({"host": host, "repo": repo, "branch": st.get("branch"), "topic": st.get("topic"),
                                   "run": name, "why": "unreadable queue" if queued.last_bad else "requeued from %s" % rq.group(1)})
            continue
        s = f.get("status") or {}
        text = s.get("last_message") or ""
        kind = reply_kind(text)
        last = _last_line(text)
        guarded = helmlib.guarded(repo)
        ev = ["record %s" % name]
        if reason:
            ev.append("ended %s: %s" % (_ago(st.get("ended"), now), reason))
        if last and not guarded:
            ev.append("last reply: %s" % last)
        since = s.get("last_at") or s.get("last_message_at") or started
        ended, alive = bool(st.get("ended")), bool(f.get("alive"))
        skipper = st.get("manager")

        if reason.startswith("max lifetime"):
            stalls.append(_stall("S3", host, st, name, "max lifetime", ev, now, since))
            continue
        if not ended and alive:
            state = s.get("state")
            if state == "input-required":
                att = s.get("attention") or {}
                stalls.append(_stall("S6", host, st, name, "live: waiting", ev + ["waits: %s" % (att.get("message") or att.get("kind") or "input")], now, since))
                continue
            idle_for = now - (s.get("updated_at") or now) if state == "idle" else 0
            if state != "idle" or idle_for < IDLE_DECIDES:
                continue   # A4: working, or idle inside the warm hour
        if not ended and not alive and f.get("watcher"):
            continue   # its watcher is ending it now: not gone until `ended` is written
        gone = (not ended and not alive) or GONE_ENDS.match(reason) or re.match(r"^exit [1-9]", reason) \
            or (s.get("api_error") and not alive)
        if guarded:
            if gone:   # its text is never read (K6): the record alone says gone
                stalls.append(_stall("S1", host, st, name, "gone, guarded — not read", ev + ["guarded — open it"], now, since,
                                     owner=f.get("owner")))
            continue
        if kind == "done" or (kind or "").startswith("done"):
            continue
        # the queue-first rule on the exact pending line, judged by the branch it names: the run's own, or the
        # one it queued (a run of X that queued Y waits on Y, which the queue holds; read for X, it was S1's
        # retry of finished work) — S3's third landing review, item 6
        pend = pending_branch(text) if kind in (WAITING_ON_OWNER, "waiting on its own work") else None
        if pend and queued is not None and queued(repo, pend):
            if queued_out is not None:
                queued_out.append({"host": host, "repo": repo, "branch": pend, "topic": st.get("topic"),
                                   "run": name, "why": "unreadable queue" if queued.last_bad else "in dispatch's queue"})
            continue
        if kind == WAITING_ON_OWNER:
            if CAP_RE.search(last):
                stalls.append(_stall("S2", host, st, name, "closing line: the run cap", ev + (
                    ["runs busy now: %s" % live_count(st)] if live_count else []), now, since, owner=f.get("owner")))
            elif (repo, st.get("branch")) in asked:
                continue   # its D-items are open asks already (asks N), not a second card
            else:
                stalls.append(_stall("S6", host, st, name, "closing line: deep()" if DEEP_RE.search(last) else "closing line: WAITING", ev, now, since))
            continue
        # session_status.RELAYED, and its word from a peer whose checkout predates rename S5
        if kind in ("waiting on skipper", "waiting on manager"):
            if skipper and skipper in live_ids:
                continue   # A4: RELAYED, and its skipper is live
            far = st.get("manager_host")
            if skipper and read is not None and far and far not in read:
                continue   # its skipper runs on a host with no road from here (a yard to the laptop): unknown, never "gone" (S8)
            stalls.append(_stall("S6", host, st, name, "closing line: RELAYED, its skipper gone", ev, now, since))
            continue
        # session_status.HANDED: a yolo or dnd run handed its landing to dispatch's launch, and no launch
        # record superseded it (`later`, above) — dispatch declined, and says why in the record's `launch`.
        # Raised, never retried: a re-dispatched build ends on the same line and meets the same gate
        # (yolo-launch review D1-B, 2026-10-25; before it this read as S1's "nothing woke it").
        if kind == "handed to its launch":
            why = str(st.get("launch") or "")
            if (ended or not alive) and not why.startswith("started"):   # a launch that stopped is S4/S5's card
                stalls.append(_stall("S6", host, st, name, "closing line: hand-over, its launch never started",
                                     ev + ["dispatch: %s" % (why[:TEXT_LINE] if why else "no launch recorded")], now, since))
            continue
        if kind == "waiting on its own work":   # session_status.PENDING: ended, or idle past A4, and nothing woke it
            if ended or not alive:   # S1 retries: never under a live process
                stalls.append(_stall("S1", host, st, name, "closing line: WAITING FOR SOMETHING, nothing woke it", ev, now, since,
                                     owner=f.get("owner")))
            else:
                stalls.append(_stall("S6", host, st, name, "closing line: WAITING FOR SOMETHING, idle past the warm hour", ev, now, since))
            continue
        if gone:
            why = "api error, its process gone" if s.get("api_error") else "gone without an end" if not ended \
                else "gone, no closing line"
            if not s.get("transcript"):
                ev.append("no transcript on %s" % host)
            stalls.append(_stall("S1", host, st, name, why, ev, now, since, owner=f.get("owner")))
            continue
        # ended idle (or exit 0) with no closing line, no WAITING, no error: the rules cannot tell
        unsure.append(_stall(None, host, st, name, "no closing line" if s.get("transcript") else "no transcript on %s" % host,
                             ev, now, since, action="classify", reply=text[-REPLY_CHARS:] or None,
                             end_reason=reason or None, owner=f.get("owner")))
    return stalls, unsure


# ---------------------------------------------------------------------------- launches (S4, S5)

def repos():
    if os.environ.get("STALLS_REPOS") is not None:
        return [Path(p) for p in os.environ["STALLS_REPOS"].split(":") if p]
    try:
        return helmlib._common().cloned_repos()
    except Exception:
        return []


def _git(repo, *args):
    try:
        r = subprocess.run(["git", "-C", str(repo)] + list(args), capture_output=True, text=True, timeout=20)
    except (OSError, subprocess.TimeoutExpired):
        return None
    return r.stdout if r.returncode == 0 else None


def worktrees(repo):
    """{branch: worktree path} from `git worktree list --porcelain`."""
    out, path = {}, None
    for line in (_git(repo, "worktree", "list", "--porcelain") or "").splitlines():
        if line.startswith("worktree "):
            path = line[9:]
        elif line.startswith("branch refs/heads/") and path:
            out[line[18:]] = path
    return out


def _run_record(wt):
    """The worktree's autofinish.json (autofinish-run's record of its last run), or None."""
    gd = _git(wt, "rev-parse", "--absolute-git-dir")
    if not gd:
        return None
    try:
        d = json.loads((Path(gd.strip()) / "claude" / "autofinish.json").read_text())
    except (OSError, ValueError):
        return None
    return d if isinstance(d, dict) else None


def judge_launches(host, live_branches, now):
    """S4 and S5 from each repo's autofinished: a branch whose last line is `stopped`, `died` or
    `never-started` (bar `not-launched`, which the sweep starts again), still open, with no landing
    running on it now. The sweep never retries a tip it ended on, so each of these waits for someone."""
    try:
        common = helmlib._common()
    except Exception as e:
        return [], ["launches: the regatta core did not load (%s)" % e]
    stalls, notes = [], []
    for repo in repos():
        common_dir = repo / ".git"
        entries = common.autofinished(common_dir)
        if not entries:
            continue
        last = {}
        for e in entries:
            last[e["branch"]] = e
        stopped = {b: e for b, e in last.items() if (repo.name, b) not in live_branches and (
            e["outcome"] in ("stopped", "died")
            # the old gate word only (common.NOT_LAUNCHED): no `autofinished` line is written for a
            # `refused` start, so a `refused` prefix could only hide a real never-started line (S1's review)
            or e["outcome"] == "never-started" and not (e["detail"] or "").startswith(common.NOT_LAUNCHED))}
        if not stopped:
            continue
        heads = set((_git(repo, "for-each-ref", "--format=%(refname)", "refs/heads/") or "").split())
        wts = None
        for branch, e in sorted(stopped.items()):
            if "refs/heads/" + branch not in heads:
                continue   # launched (refs/archive) or deleted
            gate, _, text = (e["detail"] or "").partition(" ")
            tip = (_git(repo, "rev-parse", "refs/heads/" + branch) or "").strip() or None
            st = {"repo": str(repo), "topic": re.sub(r"^claude/(?:[^/]+/)?(?:\d{4}-\d{2}-\d{2}-)?", "", branch), "branch": branch}
            ev = ["autofinished %s: %s %s %s" % (e["ts"][:16], e["outcome"], gate, text[:TEXT_LINE])]
            try:
                since = __import__("datetime").datetime.fromisoformat(e["ts"]).timestamp()
            except ValueError:
                since = None
            kw = {"key": [host, branch, tip], "key_kind": "landing", "tip": tip, "gate": gate}
            if helmlib.guarded(repo.name):
                ev = ["guarded — open it"]
            if e["outcome"] != "stopped":
                rule = "the launch never started (no reply on its tip)" if e["outcome"] == "never-started" else \
                    "the launch's runner died before an outcome"
                stalls.append(_stall("S5", host, st, None, rule, ev, now, since, **kw))
            elif gate == "no-landing" and NET_RE.match(text) and not LOGIN_RE.search(text):
                wts = worktrees(repo) if wts is None else wts
                wt = wts.get(branch)
                prev = _run_record(wt) if wt else None
                if not wt:
                    stalls.append(_stall("S5", host, st, None, "S4 stop, but no worktree to relaunch in", ev, now, since, **kw))
                elif prev and not prev.get("ended"):
                    continue   # a launch is going on it (autofinish.json not ended)
                elif prev and prev.get("tip") and tip and prev["tip"] != tip:
                    stalls.append(_stall("S5", host, st, None, "S4 stop, but the tip moved since (%s → %s)" % (prev["tip"][:7], tip[:7]),
                                         ev, now, since, **kw))
                else:
                    stalls.append(_stall("S4", host, st, None, "stopped: the network or sleep", ev + ["worktree %s" % wt],
                                         now, since, worktree=wt, by=(prev or {}).get("by"),
                                         af_rule=(prev or {}).get("rule"), **kw))
            else:
                rule = "login" if LOGIN_RE.search(text) else "WAITING line" if "WAITING FOR YOU" in text else \
                    "gate %s" % gate if re.match(r"^G\d+$", gate) else "stopped mid-work (%s)" % gate
                stalls.append(_stall("S5", host, st, None, rule, ev, now, since, **kw))
    return stalls, notes


# ---------------------------------------------------------------------------- plans (S7)

# dispatch-queue S9: the queue's cards for a step that waits on an --after predecessor which will not land by
# itself (after-gone: archived, or deleted from origin, unlanded) or past the queue's bound (after-overdue)
AFTER_CARDS = ("after-gone", "after-overdue")
AFTER_CARD_DAYS = 7


def queue_log():
    return Path(os.environ.get("HOME") or Path.home()) / "Library/Logs/claude-weekly/queue.jsonl"


def judge_after_cards(host, now, queued=None):
    """S6, raised: one stall per queued step and predecessor its claim carded on this host (dispatch-queue's
    after_holds writes the card to queue.jsonl), naming both branches; the newest card of each in the last
    AFTER_CARD_DAYS, and only while the queue still holds the step (QUEUED, the pass's one read: a queue that
    does not read holds it, so the card stays). The entry itself stays queued: a person — or the skipper —
    lands or re-seeds the predecessor, or cancels the step and dispatches it again without --after."""
    try:
        lines = queue_log().read_text().splitlines()[-5000:]
    except OSError:
        return []
    last = {}
    for line in lines:
        try:
            e = json.loads(line)
        except ValueError:
            continue
        if isinstance(e, dict) and e.get("event") == "card" and e.get("card") in AFTER_CARDS and e.get("after") and e.get("key"):
            last[(e["key"], e["after"])] = e
    out = []
    for (k, pred), e in sorted(last.items()):
        at = _num(e.get("at")) or 0
        br = e.get("branch") or ""
        if now - at > AFTER_CARD_DAYS * 86400 or not br:
            continue
        if queued is not None and not queued(e.get("repo") or "", br):
            continue   # claimed since, cancelled or gone: the card's step is no longer waiting
        rule = ("waits on %s, which will not land by itself" % pred if e["card"] == "after-gone"
                else "has waited past the queue's bound on %s" % pred)
        st = {"repo": e.get("repo"), "topic": br.rsplit("/", 1)[-1], "branch": br}
        out.append(_stall("S6", host, st, None, rule, ["step %s" % br, "after %s" % pred, str(e.get("why") or "")[:TEXT_LINE]],
                          now, at, key=[host, k, pred], key_kind="after", predecessor=pred))
    return out


def judge_plans(host, live_ids, all_records, now):
    """S7: a planned task whose dependencies are all done, nothing reported on it or them for
    S7_QUIET, and no live run of it. A task with no dependency is the skipper's own to start: not one."""
    stalls = []
    # an Orca-backed plan (`plan apply`'s one Run); a wharf ship's plan keeps S7 here for its other tasks
    owned = {p["id"] for p in plan_runs().values() if not p.get("wharf")} if orca_on() else set()
    for pid in helmlib.list_plans():
        if pid in owned:
            continue   # an Orca-backed plan: its ready Tasks are judge_orca()'s (task-list --ready)
        try:
            st = helmlib.state(pid)
        except (FileNotFoundError, ValueError):
            continue
        tasks = {t["id"]: t for t in st["tasks"]}
        skipper = (st.get("manager") or {}).get("session")
        for t in st["tasks"]:
            if t.get("kind") == "human" or t["status"] != "planned" or not t["deps"] or t["blockers"]:
                continue
            if (t.get("blueprint") or {}).get("name"):
                continue   # a wharf ship's block: wharf starts it on the same tick
            ends = [tasks[d].get("updated") or 0 for d in t["deps"] if d in tasks]
            quiet_since = max(ends + [t.get("updated") or 0])
            if now - quiet_since < S7_QUIET:
                continue
            running = [n for h, n, o in all_records if o.get("plan") == pid and not o.get("ended")
                       and (o.get("topic") == t["id"] or (t.get("branch") and o.get("branch") == t.get("branch")))]
            if running:
                continue
            to = "skipper" if skipper and skipper in live_ids else "owner"
            rec = {"repo": t.get("repo") or st.get("repo"), "topic": t["id"], "branch": t.get("branch"), "plan": pid}
            ev = ["plan %s (%s)" % (st.get("topic") or pid, pid[:8]), "deps done: %s" % ", ".join(t["deps"]),
                  "quiet %s" % _ago(quiet_since, now)]
            s = _stall("S7", host, rec, None, "ready, nobody started it", ev, now, quiet_since, raise_to=to,
                       key=[host, pid, t["id"]], key_kind="task", task=t["id"])
            s["guarded"] = bool(t.get("guarded"))
            s["manager"] = skipper
            stalls.append(s)
    return stalls


# ---------------------------------------------------------------------------- Orca workers (B8)
#
# An Orca step has no run record: its facts are Orca's Dispatches, read through the orca adapter
# behind `bin/harness list --harness orca --unsettled` (docs/orchestration-orca-2026-10-15.md
# section 7 item 4). The adapter joins each worker to its agent's own session by worktree path and
# puts a live session's state above Orca's liveness and above a `failed` Orca recorded (the owner's
# D2-B, 2026-10-15: on 10-14 Orca said `unverifiable` while Claude Code's registry said `waiting`),
# so a record's `state` already believes the registry. Orca's word decides only what Orca alone
# knows: completed, stopped, the process exit, the Task's status, a question in the Run's mailbox.
#
#   S1  the Task's newest Dispatch failed with stage `process_exited` and no worker_done → retry,
#       which is `harness retry` (a plain start of the Task Orca reopened as ready, or --retry-of
#       when it is failed; placement repeated); Orca's breaker (circuit_broken), a reported failure
#       or a failure with no process exit → raised, never retried
#   S6  the worker waits on a prompt (`input-required`, from the registry); and a `question` row in
#       the Run's mailbox (`check --peek`) from a Task's newest unfinished attempt: one naming a
#       `<doc> Dn` inside its worktree, in a plan whose skipper is live, is relayed by `bin/ask relay
#       <doc> <Dn>` (action relay, the tick's); any other raised with its message id
#   S7  a Task `task-list --ready` names, quiet S7_QUIET, in a Run a plan owns — such a plan's
#       planned tasks are Orca's to report, so judge_plans() leaves them alone
# Whose Runs: a plan's (`orca_run` in its plan.json, or a wharf ship's `blueprints.<ship>.orca_run`,
# B7 — S1 raises and never retries there, and no S7: wharf starts and counts its own; an exited
# worker still raises its card though wharf may start the Task again later in the same tick) and a Run whose
# Task is titled with its own claude/* branch (`harness run --harness orca`'s mark); Orca's own
# scratch Runs and the app's hand-made ones are neither. A Dispatch whose worktree is gone is
# none (its branch launched or was cleaned), as a run record's branch that left refs/heads.
# Not judged: Orca's own agentWait (worker-show only; a list read has none) for a worker with no
# registry entry — a codex worker waiting on a prompt shows as working.

ORCA_ADAPTER = helmlib.harness_adapter("orca.py")   # wharf-runs'; None: no Orca read
ORCA_TIMEOUT = 120
DOC_ITEM_RE = re.compile(r"(?P<doc>[\w./~-]+\.md)(?:#|:|\s+|\s*,\s*)(?P<item>D\d+)\b")


# S13a: the notes that say Orca did not answer — the dead-man's count (stalls_tick.ORCA_UNREAD_PASSES) counts
# only these, never a warning Orca answered with (a registry the adapter could not read, a harness stderr
# line beside its JSON), which would turn every ping on a yard into a --fail. Each maps to fixed words, the
# only text a --fail carries off the machine (K6: no run id, path or exception message). A Run with no
# coordinator is left out: Orca answered, and a Run may have none. One Run's task-list unread is left out
# too — the adapter cannot tell an Orca that did not answer from one that answered an error for a Run it no
# longer knows, which would --fail every pass — so only "no Run's task-list answered" counts (the landing
# review). The judge's own failure counts: three in a row is a yard that reads no Orca, which the switch
# is for, and its words say it was the judge.
ORCA_DEAD = ((re.compile(r"^orca: harness list did not answer"), "harness list did not answer"),
             (re.compile(r"^orca: harness list printed no JSON"), "harness list printed no JSON"),
             (re.compile(r"^orca: harness not installed"), "harness not installed"),
             (re.compile(r"^orca: no Run's task-list answered"), "no Run's task-list answered"),
             (re.compile(r"^orca: no reader"), "no Orca reader (wharf-runs not installed)"),
             (re.compile(r"^orca: the judge failed \((\w+)"), "the judge failed (%s)"))


def orca_dead(notes):
    """The fixed words of the first note that says Orca did not answer, or None."""
    for n in notes or []:
        for rx, words in ORCA_DEAD:
            m = rx.match(str(n))
            if m:
                return words % m.group(1) if m.groups() else words
    return None


def orca_on():
    """STALLS_ORCA=0 turns the Orca read off (the tests that are not about it: never the real app)."""
    return os.environ.get("STALLS_ORCA", "1") not in ("0", "", "off")


def orca_adapter():
    if not ORCA_ADAPTER:
        raise ImportError("harness_adapters/orca.py not installed (wharf-runs)")
    loader = SourceFileLoader("orca_adapter_for_stalls", str(ORCA_ADAPTER))
    mod = module_from_spec(spec_from_loader(loader.name, loader))
    loader.exec_module(mod)
    return mod


def orca_records():
    """(records, note): `harness list --harness orca --unsettled --json`, or ([], why not)."""
    exe = os.environ.get("STALLS_HARNESS") or helmlib.peer("harness")
    if not exe:
        return [], "orca: harness not installed (wharf-runs)"
    try:
        r = subprocess.run([str(exe), "list", "--harness", "orca", "--unsettled", "--json"], capture_output=True,
                           text=True, timeout=ORCA_TIMEOUT)
    except (OSError, subprocess.TimeoutExpired) as e:
        return [], "orca: harness list did not answer (%s)" % e.__class__.__name__
    try:
        recs = json.loads(r.stdout or "[]")
    except ValueError:
        return [], "orca: harness list printed no JSON (exit %d)" % r.returncode
    warn = [x for x in (r.stderr or "").splitlines() if x.strip()]
    return [x for x in recs if isinstance(x, dict)], ("orca: " + warn[-1][:200]) if warn else None


def plan_runs():
    """{orca run id: the plan's plan.json} of every plan on this Mac whose plan.json names one."""
    out = {}
    for pid in helmlib.list_plans():
        try:
            p = helmlib.load_plan(pid) or {}
        except (OSError, ValueError):
            continue
        if p.get("orca_run"):
            out[p["orca_run"]] = dict(p, id=pid)
        # wharf's ships: one Run each, under blueprints.<ship> (bin/wharf, B7). Its Task titles are
        # block ids, not branches; wharf counts its own starts, and its shell and claude-code Tasks
        # stay `ready` by design — so S6 is read, and S1's retry and S7 are wharf's own (judge_orca)
        for ship, rec in sorted((p.get("blueprints") or {}).items()):
            if isinstance(rec, dict) and rec.get("orca_run") and not rec.get("ended"):
                out[rec["orca_run"]] = dict(p, id=pid, wharf=ship)
    return out


def _topic(title, branch):
    """A step's topic: a plan task's id (its Orca Task title), or a branch's topic for a harness run."""
    t = title if title and not str(title).startswith("claude/") else (branch or title or "")
    return re.sub(r"^claude/(?:[^/]+/)?(?:\d{4}-\d{2}-\d{2}-)?", "", str(t))


def _repo_of(path):
    gd = _git(path, "rev-parse", "--path-format=absolute", "--git-common-dir") if path else None
    return str(Path(gd.strip()).parent) if gd and gd.strip() else None


def _owner_of(wt):
    """The worktree's lock (<git dir>/claude/owner.json), as facts() reads it for a run record."""
    gd = _git(wt, "rev-parse", "--absolute-git-dir") if wt else None
    try:
        d = json.loads((Path(gd.strip()) / "claude" / "owner.json").read_text()) if gd else None
    except (OSError, ValueError):
        return None
    return d if isinstance(d, dict) else None


def judge_orca(host, live_states, live_ids, asked, now, recs=None, read=None):
    """(stalls, unsure, runs, notes) of this Mac's Orca workers (the block above). `live_states` is
    {session id: state} of this Mac's live Claude Code sessions, `live_ids` every live session on
    both Macs (a plan's skipper may be on the build box), `asked` ask poll's open D-items by (repo,
    branch), `read` the adapter whose tasks()/coordinator()/questions()/times() are called (tests
    pass one), `recs` the list (else read)."""
    stalls, unsure, runs, notes = [], [], [], []
    if recs is None:
        recs, note = orca_records()
        if note:
            notes.append(note)
    owned = plan_runs()
    if not recs and not owned:
        return stalls, unsure, runs, notes
    ad = read or orca_adapter()
    ctx = __import__("types").SimpleNamespace(machine=host, warn=lambda m: notes.append(m[:200]))
    by_run = {}
    for r in recs:
        run = (r.get("native") or {}).get("run")
        if run:
            by_run.setdefault(run, []).append(r)
    # Orca keeps every Dispatch it ever ran: a Run no plan owns is read only while one of its
    # Dispatches could still be a stall — its worktree there, not stopped (calls grow with history)
    live_runs = {run for run, rs in by_run.items() if any(r.get("branch") and r.get("state") != "canceled" for r in rs)}
    asked_runs, unread_runs = sorted(live_runs | set(owned)), 0
    for run in asked_runs:
        tasks = ad.tasks(ctx, run)
        if tasks is None:
            notes.append("orca: task-list --run %s unread: its workers are not judged this tick" % run)
            unread_runs += 1
            if unread_runs == len(asked_runs):   # the last asked, and none answered: what the dead-man's count reads (S13a)
                notes.append("orca: no Run's task-list answered (%d asked)" % unread_runs)
            continue
        tmap = {t.get("id"): t for t in tasks}
        plan = owned.get(run) or {}
        pid, sk = plan.get("id"), plan.get("manager") or {}
        to = "skipper" if sk.get("session") and sk["session"] in live_ids else "owner"
        road = {"plan": pid, "manager": sk.get("session"), "manager_host": sk.get("host"),
                "manager_account": sk.get("account"), "plan_space": plan.get("space")}

        def ours(r):
            t = tmap.get((r.get("native") or {}).get("task"))
            return bool(t) and bool(pid or (r.get("branch") and t.get("task_title") == r.get("branch")))

        mine = [r for r in by_run.get(run, []) if ours(r)]
        if not mine and not pid:
            continue   # not ours (the block above): no coordinator, no mailbox read
        latest = {}
        for r in mine:   # Orca lists newest first: the first seen per Task is its newest attempt
            t = tmap[(r.get("native") or {}).get("task")]
            latest.setdefault(t["id"], r)
            runs.append({"host": host, "run": r.get("session_id"), "repo": repo_name(_repo_of(r.get("cwd"))),
                         "topic": _topic(t.get("task_title"), r.get("branch")), "branch": r.get("branch"),
                         "brief_blob": "orca:" + t["id"], "started": _num(r.get("started_at"))})
        for tid, r in sorted(latest.items()):
            t, native = tmap[tid], r.get("native") or {}
            if t.get("status") == "completed" or not r.get("branch") or not r.get("cwd"):
                continue   # done, or its worktree is gone (launched, cleaned)
            repo = _repo_of(r["cwd"])
            topic = _topic(t.get("task_title"), r.get("branch"))
            did = r.get("session_id")
            st = dict(road, repo=repo, topic=topic, branch=r.get("branch"), session=native.get("agent_session") or did,
                      started=r.get("started_at"), depth=0, brief_blob="orca:" + tid, wt=r.get("cwd"),
                      model=r.get("model"), effort=r.get("effort"))
            nxt = native.get("next_action")
            ev = ["orca %s (run %s, task %s)" % (did, run, tid), "Orca's next: %s" % (nxt or "nothing named"),
                  "Orca: dispatch %s, liveness %s, Task %s" % (native.get("dispatch_status") or "?",
                                                               native.get("liveness") or "?", t.get("status") or "?")]
            kw = {"harness": "orca", "orca_dispatch": did, "orca_run": run, "orca_task": tid, "next_action": nxt}
            state = r.get("state")   # the registry's already, where the worker's claude is in it (D2-B)
            if state not in ("input-required", "failed"):
                continue   # working, submitted, idle: A4 (live); canceled: a stop someone asked for
            when = ad.times(ctx, did)
            since = when.get("ended") or when.get("updated") or r.get("updated_at") or when.get("started") or r.get("started_at")
            if state == "input-required":
                att = r.get("attention") or {}
                stalls.append(_stall("S6", host, st, did, "live: waiting", ev + ["waits: %s" % (
                    att.get("message") or att.get("kind") or "input")], now, since, raise_to=to, **kw))
                continue
            said = " ".join(str(x or "") for x in (native.get("end_reason"), native.get("stage"), when.get("reason"))).lower()
            exited = "process_exited" in said
            kw["owner"] = _owner_of(r["cwd"])
            # Orca's own rules (its 1.4.225 source): a worker's exit fails its Dispatch (stage
            # process_exited) and puts the Task back to ready; the third failure in a row is
            # circuit_broken and fails the Task. A plain start takes a ready Task, --retry-of a failed one.
            if native.get("dispatch_status") == "circuit_broken" or "circuit" in said:
                why = "Orca's breaker: three failures in a row (R4) — raised, never retried"
            elif ad.foreign_terminal(native):
                why = "ran in a terminal Orca did not launch (a picked login): a retry would run on Orca's login — raised"
            elif plan.get("wharf"):
                why = "a wharf ship's worker (%s): wharf counts its own starts — raised, never retried here" % plan["wharf"]
            elif exited and t.get("status") in ("ready", "failed", "blocked") and "worker_done" not in said:
                stalls.append(_stall("S1", host, st, did, "exited, no worker_done", ev, now, since, **kw))
                continue
            elif t.get("status") == "failed":
                why = "its Task failed with no process exit: a reported failure, or failed by hand"
            else:
                why = "failed, not proven gone (Task %s, %s)" % (t.get("status") or "?", said.strip()[:60] or "no reason")
            stalls.append(_stall("S1", host, st, did, why, ev, now, since, action="raise", raise_to=to, **kw))
        coord = ad.coordinator(ctx, run)
        qs = ad.questions(ctx, run, coord) if coord else None
        if qs is None:
            if coord is None:
                notes.append("orca: run %s names no coordinator: its questions are unread" % run)
            qs = []
        recs_by_did = {r.get("session_id"): r for r in by_run.get(run, [])}
        for q in qs:
            r = recs_by_did.get(q.get("dispatch"))
            t = tmap.get(((r or {}).get("native") or {}).get("task")) or {}
            # --peek never consumes: a question is live only while its sender is its Task's newest,
            # unfinished attempt; one from a finished or superseded attempt is history
            if not r or not ours(r) or t.get("status") == "completed" or latest.get(t.get("id")) is not r:
                continue
            repo = _repo_of(r.get("cwd"))
            if (repo_name(repo), r.get("branch")) in asked:
                continue   # its D-item is an open ask already (asks N), not a second card
            topic = _topic(t.get("task_title"), r.get("branch"))
            m = DOC_ITEM_RE.search(str(q.get("text") or ""))
            doc = None
            if m and r.get("cwd"):
                base = os.path.realpath(r["cwd"])
                d = os.path.realpath(os.path.join(base, os.path.expanduser(m.group("doc"))))
                doc = d if d.startswith(base + os.sep) and os.path.isfile(d) else None   # the worker's own worktree only
            st = dict(road, repo=repo, topic=topic, branch=r.get("branch"), wt=r.get("cwd"), started=q.get("since"),
                      session=(r.get("native") or {}).get("agent_session") or q.get("dispatch"))
            guarded = repo_name(repo) in GUARDED
            ev = ["orca question %s from %s" % (q["id"], q.get("dispatch") or "?"),
                  "guarded — open it" if guarded else "asks: %s" % _last_line(str(q.get("text") or "")),
                  "answer: orca orchestration reply --id %s --body …" % q["id"]]
            kw = {"key": [host, run, q["id"]], "key_kind": "question", "harness": "orca", "orca_dispatch": q.get("dispatch"),
                  "orca_run": run, "orca_task": t.get("id"), "orca_message": q["id"], "raise_to": to}
            if doc and pid and to == "skipper":   # a relay needs a ship's skipper to hear it
                stalls.append(_stall("S6", host, st, q["id"], "question: %s %s" % (m.group("doc"), m.group("item")), ev, now,
                                     q.get("since"), action="relay", relay={"doc": doc, "item": m.group("item"), "task": topic},
                                     **kw))
            else:
                rule = "question: %s %s, no skipper to relay to" % (m.group("doc"), m.group("item")) if doc else "question in the Run's mailbox"
                stalls.append(_stall("S6", host, st, q["id"], rule, ev, now, q.get("since"), **kw))
        if not pid or plan.get("wharf"):
            continue
        done = {t.get("id"): t.get("completed") for t in tasks if t.get("status") == "completed"}
        for t in ad.tasks(ctx, run, ready=True) or []:
            if t.get("id") in latest:
                continue   # a Task Orca reopened after its worker exited: the S1 above is its card
            deps = [str(d) for d in t.get("deps") or []]
            quiet_since = max([t.get("created") or 0] + [done.get(d) or 0 for d in deps])
            if not deps or now - quiet_since < S7_QUIET:
                continue   # a first step is the skipper's own to start, as in judge_plans()
            title = str(t.get("task_title") or t.get("id"))
            ev = ["orca task %s ready in run %s (plan %s)" % (t.get("id"), run, pid), "deps done: %s" % ", ".join(deps),
                  "quiet %s" % _ago(quiet_since, now)]
            s = _stall("S7", host, dict(road, repo=plan.get("repo"), topic=title), None, "ready, nobody started it",
                       ev, now, quiet_since, raise_to=to, key=[host, pid, title], key_kind="task", task=title,
                       harness="orca", orca_run=run, orca_task=t.get("id"))
            s["guarded"] = helmlib._guarded_repo(plan.get("repo"))
            stalls.append(s)
    return stalls, unsure, runs, notes


# ---------------------------------------------------------------------------- Codex
#
# A harness Codex run (`harness run --harness codex`: codex exec under the codex adapter's wrapper) has no
# run record of dispatch's and no Orca Dispatch: its facts are the wrapper's own record. One that ended
# failed — a timeout, a rate limit, an exit that was not 0, or a wrapper gone with no end — within CODEX_H
# is an S1 card, raised and never retried (a retry is a fresh `harness run`, the brief's to give), unless a
# later run of the same topic in the same directory has started since (vendor-fence, F6 of
# docs/codex-agy-gaps-2026-10-29.md). A stop someone asked for is canceled, never a card.

CODEX_ADAPTER = helmlib.harness_adapter("codex.py")   # wharf-runs'; None: no Codex read
CODEX_H = 24


def codex_adapter():
    if not CODEX_ADAPTER:
        return None
    loader = SourceFileLoader("codex_adapter_for_stalls", str(CODEX_ADAPTER))
    mod = module_from_spec(spec_from_loader(loader.name, loader))
    loader.exec_module(mod)
    return mod


def judge_codex(host, now, read=None):
    """(stalls, notes) of this Mac's harness Codex runs (the block above). READ: the adapter (tests)."""
    try:
        ad = read or codex_adapter()
    except Exception as e:   # noqa: BLE001 — a reader that cannot load costs its cards, never the judge
        return [], ["codex: the adapter did not load (%s)" % e.__class__.__name__]
    if ad is None:
        return [], []
    ctx = __import__("types").SimpleNamespace(machine=host, warn=lambda m: None)
    recs = [(p, r, ad._run_record(ctx, p, r)) for p, r in ad._records()]
    stalls = []
    for path, raw, rec in recs:
        native = rec.get("native") or {}
        if rec.get("state") != "failed":
            continue
        since = _num(raw.get("ended")) or _num(raw.get("updated")) or _num(raw.get("started"))
        if not since or now - since > CODEX_H * 3600:
            continue
        later = [r for _, x, r in recs if x is not raw and (x.get("name") == raw.get("name")) and x.get("cwd") == raw.get("cwd")
                 and (_num(x.get("started")) or 0) > (_num(raw.get("started")) or 0)]
        if later:
            continue   # run again since: the later run is the one to judge
        why = native.get("end_reason") or "failed"
        st = {"repo": raw.get("repo") or raw.get("cwd"), "topic": raw.get("name"), "branch": raw.get("branch"),
              "started": raw.get("started"), "session": rec.get("session_id")}
        ev = ["codex run %s (%s)" % (raw.get("run"), os.path.basename(path)), "end: %s" % why,
              "error: %s" % (raw.get("error") or "none recorded"), "log: %s" % raw.get("log")]
        rule = ("rate limited" if raw.get("rate_limited") else "timed out" if raw.get("timed_out")
                else "gone, no end recorded" if not raw.get("ended") else "exited %s" % raw.get("exit"))
        stalls.append(_stall("S1", host, st, raw.get("run"), "codex run: " + rule, ev, now, since, action="raise",
                             key=[host, "codex", raw.get("run")], key_kind="codex", harness="codex",
                             codex_run=raw.get("run")))
    return stalls, []


# ---------------------------------------------------------------------------- all of it

TITLES = {"S1": "gone %s", "S2": "next step refused by the run cap", "S3": "ended at max lifetime",
          "S4": "launch stopped by the network", "S5": "launch stopped", "S6": "waiting on the owner",
          "S7": "ready, nobody started it", WONT_START: "(%d failed starts in a row)", CANARY_DEAD: "(the canary fails)"}


def judge_skippers(host, now, notes=None):
    """skipper-resilience S5: a scope whose last three skipper starts failed (bin/skipperlib.py's starts
    log) is one stall of the class `skipper won't start`, raised: the tick starts no fourth, and the
    yard keeps holding its ships, driving their blocks while nobody answers their questions. A host
    with no starts log has none; a skipperlib that will not load, or a read that fails, costs this class
    only — and says so in NOTES (the judge's notes), never silently."""
    try:
        import skipperlib
        found = skipperlib.wont_start_stalls(host)
    except Exception as e:   # noqa: BLE001 — the class is S5's; the judge's other classes never wait on it
        if notes is not None:
            notes.append("stalls: the `%s` class not judged (%s: %s)" % (WONT_START, e.__class__.__name__, str(e)[:160]))
        return []
    out = []
    for scope, fails, info in found:
        last = fails[0]
        ev = ["%s %s: %s" % (time.strftime("%m-%d %H:%M", time.localtime(float(f.get("t") or 0))), f.get("event"),
                             f.get("why") or "?") for f in fails[:3]]
        # the scope's anchor as the card's repo; a guarded or confidential scope's card is guarded —
        # its failure text names repo keys, login labels and paths (the board's K6 scrub keeps the column)
        s = _stall(WONT_START, host, {"topic": "skipper · %s" % scope, "repo": info.get("anchor")}, None,
                   "%d failed starts in a row, the last: %s — the yard keeps holding; `helm skipper --start %s` from a "
                   "shell on %s tries again once it is fixed" % (len(fails), last.get("why") or "?", scope, host),
                   ev, now, float(last.get("t") or now), key=[host, "skipper", scope], key_kind="skipper",
                   fails=len(fails))
        s["guarded"] = bool(s.get("guarded") or info.get("guarded"))
        out.append(s)
    return out


def canary_argv():
    """argv of `clock canary check --json`, or None when it is not read: STALLS_CANARY=0 (or off), the Orca read
    off with no stand-in named (the tests that are not about it: never the real app), or wharf-runs' clock not
    installed. STALLS_CANARY=<command> stands in for it."""
    v = os.environ.get("STALLS_CANARY")
    if v is not None and v.strip() not in ("1", "on"):   # 1 or on: the default read, never a command named `1`
        return None if v.strip() in ("", "0", "off") else shlex.split(v)
    if not orca_on():
        return None
    clock = helmlib.peer("clock")
    return [str(clock), "canary", "check", "--json"] if clock else None


def canary_guarded(key):
    """True when a canary beat's key names a login (`path@login`) that a confidential scope runs on, or the
    registry cannot say: its card and issue then carry the class and host alone (K6), as a skipper's do."""
    login = key.split("@", 1)[1] if "@" in key else None
    if not login:
        return False
    try:
        c = helmlib._common()
        if c.registry_unreadable():
            return True
        return any(isinstance(s, dict) and s.get("login") == login for s in c.confidential_scopes().values())
    except Exception:   # noqa: BLE001 — cannot tell: guarded
        return True


def brake_ended_within(now, span):
    """The end of the studio brake's last window when it is under `span` seconds before now, else None
    (helmlib.brake_windows: written where the tick records the brake; no record, no grace)."""
    try:
        ends = [float(e) for _, e in helmlib.brake_windows(now)]
    except Exception:   # noqa: BLE001 — an unreadable record is no brake, as everywhere else
        return None
    end = max(ends) if ends else None
    return end if end is not None and 0 <= now - end < span else None


def judge_canary(host, now, notes=None, held=None, dead=None):
    """(stalls, read): the class `start path dead` (orca-launcher S7, docs/orca-launcher-2026-10-24.md G2): one
    raised stall per canary beat `clock canary check` fails — a beat outside its window, an automation that
    never beat, a fired one-shot that beat nothing, a run that reached no first turn — keyed [host, "canary", key].
    This Mac's own check only: the canary reads this Mac's Orca and beat files, so no peer is asked and the
    laptop is no dependency. `read` is False when the check was not read this pass (off, not installed, the
    studio brake, no answer, no JSON, or an Orca it could not read itself): the stall road then closes no
    issue on an absence, and a failure that did read still raises. A read that fails costs this class
    only and says so in NOTES, never silently."""
    argv = canary_argv()
    if not argv:
        return [], False
    if held:
        if notes is not None:
            notes.append("canary: not read — the studio brake holds (%s)" % held)
        return [], False
    if dead:   # Orca did not answer this pass: the check would spend CANARY_TIMEOUT on the same dead app
        if notes is not None:
            notes.append("canary: not read — Orca did not answer this pass (%s)" % dead)
        return [], False
    # the brake froze Orca serve, so no beat fired under it: a beat's window starts again at its end
    braked = brake_ended_within(now, CANARY_BRAKE_GRACE)
    if braked is not None:
        if notes is not None:
            notes.append("canary: not judged — the studio brake ended %d min ago, under a beat's window" % ((now - braked) // 60))
        return [], False

    def failed(why):
        if notes is not None:
            notes.append("canary: the `%s` class not judged (%s)" % (CANARY_DEAD, why))
        return [], False

    try:
        r = subprocess.run(argv, capture_output=True, text=True, timeout=CANARY_TIMEOUT)
    except (OSError, subprocess.TimeoutExpired) as e:
        return failed("clock canary check did not answer: %s" % e.__class__.__name__)
    try:
        d = json.loads(r.stdout or "")
        found = [f for f in d["findings"] if isinstance(f, dict)]
    except (ValueError, KeyError, TypeError):
        return failed("clock canary check printed no findings (exit %d)" % r.returncode)
    read = r.returncode in (0, 1)
    if not read and notes is not None:
        notes.append("canary: clock canary check exit %d — its failures are raised, an absence is not read" % r.returncode)
    # its own note when it could not read this Mac's Orca: the beats were judged, the automations were not
    if any(str(f.get("level")) == "NOTE" and "Orca not read" in str(f.get("text")) for f in found):
        read = False
    keys = {}
    for f in found:
        if str(f.get("level")) != "FAIL":
            continue
        m = CANARY_KEY_RE.match(str(f.get("text") or ""))
        keys.setdefault(m.group(1) if m else "?", []).append((m.group(2) if m else str(f.get("text")))[:240])
    out = []
    for key, whys in sorted(keys.items()):
        # the rule is fixed words (the minutes in a finding move every pass); the card's evidence carries the finding.
        # `run` is the episode: a hash of the finding less its moving minutes (a stale beat's names its last beat), so a beat
        # that fails again after it cleared is a new instance and waits ESCALATE_AFTER again, as its first did
        s = _stall(CANARY_DEAD, host, {"topic": "canary %s" % key}, "episode " + hashlib.sha1(CANARY_AGO_RE.sub("", whys[0]).encode()).hexdigest()[:10],
                   "its canary check fails, so a start on that path may reach no first turn (`clock canary check` on %s says why)" % host,
                   [w[:TEXT_LINE] for w in whys[:2]], now, None,
                   key=[host, "canary", key], key_kind="canary", beat=key)
        s["guarded"] = bool(s.get("guarded") or canary_guarded(key))
        out.append(s)
    return out, read


def title(s, now):
    what = TITLES[s["class"]]
    if s["class"] == "S1" and s.get("harness") in ("orca", "codex") and s["action"] == "raise":
        what = "failed %s ago" % _ago(s.get("since"), now)
    elif s["class"] == "S1":
        what = what % _ago(s.get("since"), now)
    elif s["class"] == "S5":
        what += " at %s" % (s.get("gate") or "?")
    elif s["class"] == "S6" and "RELAYED" in (s.get("rule") or ""):
        what = "relayed to a skipper that is gone"
    elif s["class"] == "S6" and "hand-over" in (s.get("rule") or ""):
        what = "handed over, its launch never started"
    elif s["class"] == "S6" and s.get("key_kind") == "question":
        what = "an Orca worker asks"
    elif s["class"] == WONT_START:
        what = what % (s.get("fails") or 0)
    return "%s · %s %s" % (s.get("topic") or s.get("branch") or "?", s["class"], what)


def column(s):
    """The board's column: Blocked for a class the tick acts on (A1/A2) or a raise to a live
    skipper, the owner's column (helmlib.columns()) for every other raise (chain-manager E1)."""
    if s["action"] in ("retry", "start", "relaunch", "relay") or s.get("raise_to") in RAISE_TO_SKIPPER:
        return "Blocked"
    return helmlib.columns()[0]


def judge(peer=True, live_call=True, orca_held=None):
    """{"stalls", "unsure", "notes", "as_of", "hosts"} over both Macs. `orca_held` is the studio brake's
    reason (helmlib.brake_refusal, skipper-resilience S11): the brake freezes Orca serve's tree, so a
    read of Orca would spend ORCA_TIMEOUT against a frozen serve and read nothing — none is made, and the card says so."""
    now = time.time()
    me = helmlib.host()
    rc = _load_bin("dispatch-rc")
    ad = adapter()
    if not rc or not ad:
        # wharf-runs is the runs' module (dispatch-rc reads them, its adapter reads a transcript):
        # without it there is no run to stall, which is said, never a traceback (G-guard, B12)
        return {"as_of": now, "host": me, "hosts": [], "stalls": [], "unsure": [],
                "notes": ["stalls: wharf-runs not installed (dispatch-rc, its harness adapter) — no runs to judge"], "runs": [],
                # nothing was read: the stall road closes no issue on this pass's absences
                "unread": {"hosts": [], "launches": True, "orca": True, "skippers": True, "canary": True},
                # counted only while the Orca read is on: STALLS_ORCA=0 reads no Orca, so none went unread
                "orca_dead": orca_dead(["orca: no reader"]) if orca_on() else None}
    views, notes = {me: local_view(rc, ad)}, []
    if peer:
        for h, alias in sorted(peers().items()):
            v, note = read_peer(h, alias, rc)
            notes.append(note)
            if v:
                for n, st in list((v.get("raw") or {}).items()):
                    v["raw"][n] = rc.typed(st)
                views[h] = v
    all_records = [(h, n, st) for h, v in views.items() for n, st in (v.get("raw") or {}).items() if isinstance(st, dict)]
    live_ids = {x["session_id"] for v in views.values() for x in v.get("live") or []}
    asked = poll_asks()
    queued, queued_runs = QueueRead(), []
    for i, n in enumerate(notes):
        m = re.match(r"^(\S+): unreachable", n)
        w = asleep(m.group(1), queued, now) if m else None
        if w:
            notes[i] = "%s: %s — %s" % (m.group(1), w, n[len(m.group(1)) + 2:])
    # a launch running now (a finish-* record not ended, alive on its host): autofinish's, not a stall
    live_branches = {(repo_name(st.get("repo")), st.get("branch")) for h, n, st in all_records
                     if launching(st.get("topic")) and not st.get("ended") and (views[h]["records"].get(n) or {}).get("alive")}

    def live_count(st):
        if not live_call or not st.get("repo"):
            return "not read"
        try:
            r = subprocess.run([str(helmlib.peer("dispatch-rc")), "live", "--no-reap", st["repo"], st.get("topic") or ""],
                               capture_output=True, text=True, timeout=60)
            return r.stdout.strip() or "?"
        except (OSError, subprocess.TimeoutExpired):
            return "?"

    stalls, unsure = [], []
    # every store read is judged, a yard's too: the board shows its stalls; only the tick's acting is
    # left to the yard's own tick (stalls_tick, by `self_judging` below) — S8
    for h, v in views.items():
        s, u = judge_runs(h, v, all_records, live_ids, asked, now, live_count if h == me else None,
                          read=set(views) | set(peers()) if peer else None, queued=queued, queued_out=queued_runs)
        stalls += s
        unsure += u
    # what this pass could not read, by source: the stall road closes no issue on an absence it cannot vouch for
    unread = {"hosts": sorted(set(peers()) - set(views)) if peer else [], "launches": False, "orca": False,
              "skippers": False, "canary": False}
    s, n = judge_launches(me, live_branches, now)
    stalls += s
    notes += n
    unread["launches"] = bool(n)
    orca_runs, dead = [], None
    if orca_on() and orca_held:
        # the studio brake freezes Orca serve's tree: a read would spend ORCA_TIMEOUT and read nothing (S11)
        notes.append("orca: not read — the studio brake holds (%s)" % orca_held)
        unread["orca"] = True   # an absence says nothing: the stall road closes no issue on it
    elif orca_on():   # Orca runs on this Mac only (design F6, F8): the build box's workers wait for B11
        live_states = {x["session_id"]: x.get("state") for x in views[me].get("live") or []}
        try:
            s, u, orca_runs, n = judge_orca(me, live_states, live_ids, asked, now)
        except Exception as e:   # noqa: BLE001 — Orca's shapes are partly unprobed: its failure costs its cards, never the judge
            s, u, orca_runs, n = [], [], [], ["orca: the judge failed (%s: %s)" % (e.__class__.__name__, str(e)[:160])]
        stalls += s
        unsure += u
        notes += n
        unread["orca"] = bool(n)
        dead = orca_dead(n)   # what the dead-man's count counts and names (S13a): a warning Orca answered with is not it
    stalls += judge_plans(me, live_ids, all_records, now)
    stalls += judge_after_cards(me, now, queued)   # S9: a queued step whose --after predecessor will not land
    s, n = judge_codex(me, now)
    stalls += s
    notes += n
    k = len(notes)
    stalls += judge_skippers(me, now, notes)
    unread["skippers"] = len(notes) > k
    s, canary_read = judge_canary(me, now, notes, orca_held, dead)
    stalls += s
    unread["canary"] = not canary_read
    for x in stalls:
        x["title"] = title(x, now)
        x["column"] = column(x)
    for x in unsure:
        x["title"] = "%s · unsure: %s" % (x.get("topic") or "?", x["rule"])
    order = {c: i for i, c in enumerate(("S1", "S2", "S4", "S3", "S5", "S6", "S7", WONT_START, CANARY_DEAD))}
    stalls.sort(key=lambda x: (order[x["class"]], -(x.get("since") or 0)))
    # every record, light: B3 matches a retry to the run it started by (repo, topic, brief blob,
    # started after the retry) — the launch review's "the retry died", which `run:` cannot carry
    runs = [{"host": h, "run": n, "repo": repo_name(st.get("repo")), "topic": st.get("topic"),
             "branch": st.get("branch"), "brief_blob": st.get("brief_blob"), "started": _num(st.get("started"))}
            for h, n, st in all_records] + orca_runs
    # skipper-modes S5: what the board cards beside the stalls — WAITING sessions on every Mac, and a
    # peer's permission prompts (this Mac's are the board's own registry read)
    waiting = [dict(w, host=h) for h, v in views.items() for w in v.get("waiting") or []]
    prompts = [dict(x, host=h) for h, v in views.items() if h != me for x in v.get("live") or []
               if x.get("state") == "input-required"]
    # every live session on either Mac with its branch: the board's WIP PR held by a session is a Running
    # card, an idle one a count (board-cleanup S1)
    live = [dict(x, host=h) for h, v in views.items() for x in v.get("live") or []]
    own, torn = self_judging()
    # the queue's cards: a run that queued its step and ended, waiting on the queue, not a stall (S3)
    for x in queued_runs:
        notes.append("queued: %s on %s — %s (%s); not a stall (dispatch --queue)" % (x.get("topic"), x["host"], x.get("branch"), x["why"]))
    if queued.bad:
        notes.append("queue: unreadable (%s) — every run on the queue's closing line whose branch the unread store may hold counts as queued" % queued.bad)
    return {"as_of": now, "host": me, "hosts": sorted(views), "stalls": stalls, "unsure": unsure, "notes": notes,
            "runs": runs, "waiting": waiting, "prompts": prompts, "live": live, "unread": unread, "orca_dead": dead,
            "self_judging": sorted(own), "registry_torn": torn, "queued": queued_runs}


def main(argv=None):
    ap = argparse.ArgumentParser(prog="stalls.py", description=__doc__.split("\n\n")[0])
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--no-peer", action="store_true", help="this Mac's records only (no ssh)")
    a = ap.parse_args(argv)
    res = judge(peer=not a.no_peer, orca_held=helmlib.brake_refusal())
    if a.json:
        print(json.dumps(res, ensure_ascii=False, sort_keys=True))
        return 0
    for s in res["stalls"]:
        print("%s %s %s %s — %s; %s" % (s["class"], s["host"], s["repo"], s.get("topic") or s.get("branch"), s["rule"], s["action"]))
    for s in res["unsure"]:
        print("?  %s %s %s — %s" % (s["host"], s["repo"], s.get("topic"), s["rule"]))
    for n in res["notes"]:
        print(n)
    return 0


if __name__ == "__main__":
    sys.exit(main())
