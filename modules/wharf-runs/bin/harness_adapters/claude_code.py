"""The Claude Code adapter: V4 `list` and V3 `status` of the harness contract
(docs/harness-contract-2026-10-11.md section 3, the session record; docs/chain-manager-2026-10-11.md
section 5). B1 wrote the two reads bin/stalls.py needs (list(), status()); B5 part 1 (orchestration
step B5, this file's second half) put it behind `bin/harness` (sessions(), candidates()) and filled
the record's other fields. B5 part 2 added V1 run, V2 (the next turn) and V5 stop (the end of this file),
each a bin/dispatch call: dispatch keeps the start lock, the run cap, the trust step, the watcher
and the allow and deny lists, so a harness-started run is a dispatch run like any other.

Self-contained — stdlib, Python 3.9, every path from $HOME — because bin/stalls.py and bin/harness
both send this file's source to a peer Mac over ssh and run it there (pickup's PEER_PROBE does the
same): one reader judges a session on both Macs, never two copies that drift. Hence every helper's
name starts with an underscore: stalls.py's probe appends dispatch-rc's typed(), running(),
proc_start() and watcher_gone() after this source, and a public name here would be overwritten.
Two things come from the repo: what counts as a call (_model_of), the core's hooks/transcript.py
from the peer's own checkout, so the rule is never a fifth copy (2026-10-24; none there, no model);
and bin/dispatch-rc, which is loaded when it is there and skipped when it
is not (_rc()): the registry alone still answers.

What it reads:
    ~/.claude/sessions/<pid>.json   the live registry (the three login dirs share it by symlink;
                                    ASK_SESSIONS_DIR moves it, as for bin/asklib). Removed when the
                                    process exits; one a crash left is ruled out by `procStart`
                                    (dispatch-rc's running(), when loaded). `claude agents --json`
                                    prints these same records (24 of 24 on 2026-10-14) at about a
                                    second's cost; the contract's R5 has the file win, so the file
                                    is read
    the run records                 ~/Library/Logs/claude-weekly/run-seed-runs/, through dispatch-rc:
                                    live(reap=False) — `dispatch-rc live --no-reap` without the count
                                    — and load()/typed(). They add what the registry lacks: branch,
                                    topic, repo, the screen to attach to, a run's end
    ~/.claude*/projects/*/<id>.jsonl  a session's transcript, any login's: the last assistant text,
                                    when it was said, the model and effort Claude Code writes on each
                                    assistant record (what a call is: the core's transcript.call,
                                    the one import outside this file, found on the peer
                                    through its own regatta checkout), and whether the last record
                                    is Claude Code's stand-in for an API failure

The mapping (contract section 3, S1–S7), exactly its table:
    registry busy, shell            → working (shell: idle with a background shell — still working)
    registry waiting                → input-required; attention.kind from `waitingFor` (_WAITING)
    registry idle                   → idle, attention.kind idle
    any other registry status       → working (the safe side, as dispatch-rc's parked() counts it)
    a live run, no registry entry   → submitted (`--remote-control` before its first registry
                                      write); a headless run → working (`claude -p` keeps none)
    a run that is over              → completed, failed or canceled by its end (_end_state)
    no run record, no process       → completed, or failed when the last record is an API error
An API error ending an idle session's turn is reported (`api_error`, `error_kind`), not mapped to
auth-required: the contract's S7 names it, and bin/stalls.py reads `idle` and `api_error` apart
today — the state changes when its reader does.

Times are epoch seconds (B1's convention, which stalls.py computes with). `account` is null unless a
run record names one: registry and transcripts are shared by every login, so neither says which.
"""
import builtins
import glob
import importlib.machinery
import importlib.util
import json
import os
import re
import socket
import subprocess
import time
import uuid

HARNESS = "claude-code"
NAME = HARNESS   # what bin/harness reads
# Claude Code's registry status → the contract's state (A2A's names plus `idle`)
STATES = {"busy": "working", "shell": "working", "idle": "idle", "waiting": "input-required"}
TAIL_BYTES = 512 * 1024   # a transcript's last turn is near its end; a long session is many MB
TEXT_CAP = 4000           # the last reply's text kept: its closing line and the tail the rules read
# `waitingFor` → sessionpipe's attention kind: Claude Code 2.1.300's own table, read in its binary on
# 2026-10-14 — the four below → permission, "input needed" → question, "dialog open" → none (a dialog
# is a form to answer: elicitation here). A value not in it falls to _attention()'s word test.
_WAITING = {"permission prompt": "permission", "sandbox request": "permission", "worker request": "permission",
            "goal proposal": "permission", "input needed": "question", "dialog open": "elicitation"}
_RANK = {"busy": 3, "shell": 2, "waiting": 1}   # pickup's: two processes on one session, the busier speaks


def _home():
    return os.environ.get("HOME") or os.path.expanduser("~")


def sessions_dir():
    return os.environ.get("ASK_SESSIONS_DIR") or os.path.join(_home(), ".claude", "sessions")


def _alive(pid):
    try:
        os.kill(int(pid), 0)
        return True
    except PermissionError:
        return True
    except (OSError, ValueError, TypeError, OverflowError):
        return False


# ---- dispatch-rc, when it is there ---------------------------------------------------------

_RCS = {}
_RUNS = {}


def _launcher(ctx):
    """The checkout bin/dispatch-rc and bin/dispatch live in: bin/harness's ctx; else
    HARNESS_LAUNCHER; else this file's own, two folders up; else this module in the checkout the
    config dir's `home` names (source sent over stdin has no path; the overlay came first until B14b)."""
    if ctx is not None:
        return ctx.coding
    if os.environ.get("HARNESS_LAUNCHER"):
        return os.environ["HARNESS_LAUNCHER"]
    here = os.path.abspath(globals().get("__file__") or "")
    up = os.path.dirname(os.path.dirname(os.path.dirname(here)))
    if os.path.exists(os.path.join(up, "bin", "dispatch-rc")):
        return up
    cfg = os.path.expanduser(os.environ.get("REGATTA_CONFIG") or os.path.join("~", ".config", "regatta"))

    def first(name):
        try:
            with open(os.path.join(cfg, name)) as f:
                return os.path.expanduser(f.readline().strip())
        except OSError:
            return ""

    core = first("home")
    return os.path.join(core, "modules", "wharf-runs") if core else os.path.join(_home(), "projects", "regatta", "modules", "wharf-runs")


def _rc(ctx=None):
    """bin/dispatch-rc as a module (a dash in its name; helm_render loads it so), or None when it is
    missing or broken — then the run fields stay empty. Once per checkout and HOME: its paths are
    read at import."""
    key = (_launcher(ctx), _home())
    if key not in _RCS:
        path = os.path.join(key[0], "bin", "dispatch-rc")
        mod = None
        if os.path.exists(path):
            try:
                loader = importlib.machinery.SourceFileLoader("dispatch_rc", path)
                mod = importlib.util.module_from_spec(importlib.util.spec_from_loader("dispatch_rc", loader))
                loader.exec_module(mod)
            except Exception as e:   # noqa: BLE001 — a broken dispatch-rc must not take the list with it
                mod = None
                if ctx is not None:
                    ctx.warn("%s: %s did not load (%s); run records not read" % (HARNESS, path, e))
        _RCS[key] = mod
    return _RCS[key]


def _runs_dir():
    return os.path.join(_home(), "Library", "Logs", "claude-weekly", "run-seed-runs")


def _all_runs(ctx=None):
    """[(path, record)] of every run record, typed, oldest first; kept 5 s, since status() is
    called once per run by stalls.py."""
    mod = _rc(ctx)
    if mod is None:
        return []
    key = (_runs_dir(), id(mod))
    hit = _RUNS.get(key)
    if hit and time.time() - hit[0] < 5:
        return hit[1]
    out = []
    for p in sorted(glob.glob(os.path.join(_runs_dir(), "*.json"))):
        try:
            out.append((p, mod.load(p)))
        except (OSError, ValueError):
            continue
    _RUNS[key] = (time.time(), out)
    return out


def _live_runs(ctx=None):
    """{session id: (path, record)} of the runs whose claude is still the run's — dispatch-rc's
    live() with reaping off: a read never ends anything."""
    mod = _rc(ctx)
    if mod is None:
        return {}
    return {st.get("session"): (p, st) for p, st in mod.live(reap=False) if st.get("session")}


def _same_process(ctx, pid, start):
    mod = _rc(ctx)
    return mod.running(pid, start) if mod is not None else _alive(pid)


# ---- the registry --------------------------------------------------------------------------

def _registry(ctx=None):
    """{session id: registry record} of every live claude process here."""
    live = {}
    for f in sorted(glob.glob(os.path.join(sessions_dir(), "*.json"))):
        try:
            with open(f) as fh:
                rec = json.load(fh)
        except (OSError, ValueError):
            continue
        if not isinstance(rec, dict) or not rec.get("sessionId") or not isinstance(rec.get("pid"), int):
            continue
        if not _same_process(ctx, rec["pid"], rec.get("procStart")):
            continue
        prev = live.get(rec["sessionId"])
        if prev is None or _RANK.get(rec.get("status"), 0) > _RANK.get(prev.get("status"), 0):
            live[rec["sessionId"]] = rec
    return live


# ---- the transcript ------------------------------------------------------------------------

def transcript(session_id, cwd=None):
    """Under cwd's slug first, else any login's, any slug: a session that entered a worktree keeps
    writing under the slug it started in (seen 2026-10-14)."""
    if cwd:
        p = os.path.join(_home(), ".claude", "projects", re.sub(r"[^A-Za-z0-9]", "-", cwd), "%s.jsonl" % session_id)
        if os.path.exists(p):
            return p
    hits = glob.glob(os.path.join(_home(), ".claude*", "projects", "*", "%s.jsonl" % session_id))
    return hits[0] if hits else None


def _epoch(ts):
    """An ISO timestamp from a transcript (`2026-10-06T17:50:12.345Z`) as epoch seconds, or None."""
    import calendar
    try:
        return float(calendar.timegm(time.strptime(str(ts)[:19], "%Y-%m-%dT%H:%M:%S")))
    except (ValueError, TypeError):
        return None


def _tail(path):
    """The parseable records of the transcript's last TAIL_BYTES, oldest first."""
    if not path:
        return []
    try:
        with open(path, "rb") as fh:
            fh.seek(0, os.SEEK_END)
            size = fh.tell()
            fh.seek(max(0, size - TAIL_BYTES))
            raw = fh.read().decode("utf-8", "replace")
    except OSError:
        return []
    lines = raw.splitlines()
    if size > TAIL_BYTES:
        lines = lines[1:]   # the first line of a tail is cut
    out = []
    for line in lines:
        if '"type"' not in line:
            continue
        try:
            e = json.loads(line)
        except ValueError:
            continue
        if isinstance(e, dict):
            out.append(e)
    return out


def last_reply(session_id, records=None):
    """{"text", "at", "api_error", "last_at"} of a session's transcript, or None when no transcript
    is on this Mac. `text` is the last assistant entry's text (a streamed reply's last block with
    text, as dispatch-rc's last_answer reads it); `api_error` is true when the last assistant
    record is Claude Code's stand-in for a failed call; `last_at` is the last entry of any kind."""
    if records is None:
        path = transcript(session_id)
        if not path:
            return None
        records = _tail(path)
    text, at, api_error, last_at = "", None, False, None
    for e in records:
        if e.get("type") not in ("assistant", "user"):
            continue
        last_at = _epoch(e.get("timestamp")) or last_at
        if e.get("type") != "assistant":
            continue
        api_error = bool(e.get("isApiErrorMessage"))
        content = (e.get("message") or {}).get("content")
        if isinstance(content, builtins.list):   # `list` here is V4, the contract's verb
            said = "\n".join(c.get("text", "") for c in content if isinstance(c, dict) and c.get("type") == "text").strip()
            if said:
                text, at = said, _epoch(e.get("timestamp"))
    return {"text": text[-TEXT_CAP:], "at": at, "api_error": api_error, "last_at": last_at}


_CORE_TRANSCRIPT = []


def _transcript_lib():
    """The core's hooks/transcript.py — the one rule for what a main-chain call is — or None.
    Imported where the caller put the core on sys.path (bin/harness here, dispatch-rc, stalls.py),
    else loaded from the regatta checkout _launcher() names: source sent over stdin has no path, so
    on a peer it is that Mac's own core. Loaded once. None (no core): no model is read."""
    if not _CORE_TRANSCRIPT:
        mod = None
        try:
            import transcript as mod
            if not callable(getattr(mod, "call", None)):
                mod = None   # some other module of that name
        except Exception:   # noqa: BLE001 — no core on the path: the checkout's below
            mod = None
        if mod is None:
            f = os.path.join(os.path.dirname(os.path.normpath(_launcher(None))), "regatta", "hooks", "transcript.py")
            try:
                loader = importlib.machinery.SourceFileLoader("regatta_core_transcript", f)
                mod = importlib.util.module_from_spec(importlib.util.spec_from_loader(loader.name, loader))
                loader.exec_module(mod)
            except Exception:   # noqa: BLE001
                mod = None
        _CORE_TRANSCRIPT.append(mod)
    return _CORE_TRANSCRIPT[0]


def _model_of(records):
    """(model, effort) of the main chain's last call, as the core's transcript.call judges one
    (sidechains, `<synthetic>` stand-ins and zero totals skipped); (None, None) with none, or no core."""
    lib = _transcript_lib()
    for e in reversed(records if lib else []):
        c = lib.call(e)
        if c:
            return c[1] or None, e.get("effort")
    return None, None


def _error_turn(records):
    """The main chain's last user or assistant record when it is an assistant record Claude Code
    wrote in place of a failed call, else None: {"at" (its ISO timestamp), "text", "kind" (its
    `error`, "unknown" when it names none), "flagged" (`isApiErrorMessage`)}. Such a record carries
    the flag or the `<synthetic>` model (the review of 2026-10-22 found every "API Error" text in the
    transcripts carrying both); a text alone marks nothing. dispatch-rc's nudge reads it (the turn's name is `at`)."""
    for e in reversed(records):
        if e.get("isSidechain") or e.get("type") not in ("user", "assistant"):
            continue
        if e.get("type") != "assistant":
            return None
        msg = e.get("message") or {}
        if not (e.get("isApiErrorMessage") or msg.get("model") == "<synthetic>"):
            return None
        content = msg.get("content")
        text = "\n".join(c.get("text", "") for c in content if isinstance(c, dict) and c.get("type") == "text").strip() \
            if isinstance(content, builtins.list) else ""
        return {"at": e.get("timestamp") or "", "text": text, "kind": e.get("error") or "unknown",
                "flagged": bool(e.get("isApiErrorMessage"))}
    return None


def _error_kind(records):
    """Claude Code's error kind (`rate_limit`, `server_error`, …) when the main chain's last user or
    assistant record is an API error, else None. A kind, never the message: no text leaves here."""
    t = _error_turn(records)
    return t["kind"] if t and t["flagged"] else None


def _branch_of(cwd, records):
    """The branch checked out in cwd now (git, the ground truth), else the transcript's last."""
    if cwd and os.path.isdir(cwd):
        try:
            r = subprocess.run(["git", "-C", cwd, "symbolic-ref", "--short", "-q", "HEAD"],
                               capture_output=True, text=True, timeout=5)
            if r.returncode == 0 and r.stdout.strip():
                return r.stdout.strip()
        except (OSError, subprocess.TimeoutExpired):
            pass
    for e in reversed(records):
        if e.get("gitBranch") and not e.get("isSidechain"):
            return e["gitBranch"]
    return None


# ---- the mapping ---------------------------------------------------------------------------

def _attention(rec):
    """The contract's attention for a live session: `waitingFor` through Claude Code's own table,
    else by its words; `idle` for an idle one (sessionpipe's attention.needed kind=idle)."""
    since = (rec.get("statusUpdatedAt") or rec.get("updatedAt") or 0) / 1000.0 or None
    if rec.get("status") == "idle":
        return {"kind": "idle", "message": None, "since": since}
    if rec.get("status") != "waiting":
        return None
    what = str(rec.get("waitingFor") or "")
    low = what.lower()
    kind = _WAITING.get(low) or ("permission" if ("permission" in low or "tool" in low)
                                 else "elicitation" if "elicit" in low else "question")
    return {"kind": kind, "message": what or None, "since": since}


def _end_state(st):
    """completed, failed or canceled for a run that is over, from dispatch's own words: watch()'s,
    end()'s, end_warm()'s, tidy()'s and run_headless()'s end_reason. A run that handed the owner an ask
    past its skipper failed (dispatch-rc's ask_guard). A reason not known here is no success."""
    if st.get("ask_guard"):
        return "failed"
    reason = str(st.get("end_reason") or "")
    if reason.startswith("ended by dispatch --end"):
        return "canceled"
    # a run dispatch-rc ended idle on a turn that ended on an API error (its nudge spent or not delivered)
    # stopped halfway: not a completion (bin/dispatch's yolo_launch refuses the same words)
    if "its last turn ended on an API error" in reason:
        return "failed"
    if reason.startswith(("idle ", "orphaned:", "claude exited by itself", "ended for its landing")):
        return "completed"
    m = re.match(r"exit (\d+)$", reason)
    if m:
        code = int(m.group(1))
        return "completed" if code == 0 else "canceled" if code in (130, 143) else "failed"
    return "failed"   # never started, max lifetime, tidied (its claude gone unseen), anything new


_HOST = []


def _machine(ctx):
    """This Mac's name (bin/harness's ctx, else HARNESS_HOST, else LocalHostName), read once."""
    if ctx is not None:
        return ctx.machine
    if os.environ.get("HARNESS_HOST"):
        return os.environ["HARNESS_HOST"]
    if not _HOST:
        try:
            r = subprocess.run(["/usr/sbin/scutil", "--get", "LocalHostName"], capture_output=True, text=True, timeout=5)
            _HOST.append(r.stdout.strip().lower() or None)
        except (OSError, subprocess.TimeoutExpired):
            _HOST.append(None)
    return _HOST[0]


def _num(v):
    return float(v) if isinstance(v, (int, float)) and not isinstance(v, bool) and v > 0 else None


def _record(ctx, reg=None, run=None, run_path=None, records=None, state=None, attention=None, ended=False):
    """One contract record from what is known: the registry entry (live), the run record, or both."""
    reg, run, records = reg or {}, run or {}, records or []
    cwd = reg.get("cwd") or run.get("wt") or run.get("repo")
    model, effort = _model_of(records)
    err = _error_kind(records)
    native = {"status": reg.get("status"), "waiting_for": reg.get("waitingFor"), "kind": reg.get("kind"),
              "entrypoint": reg.get("entrypoint"), "version": reg.get("version"),
              "run": run_path, "mode": run.get("mode"), "topic": run.get("topic"), "repo": run.get("repo"),
              "manager": run.get("manager"), "error_kind": err, "resumed_from": run.get("resumed_from"),
              "ended_at": _num(run.get("ended")) if ended else None,
              "end_reason": (run.get("end_reason") or ("gone: its claude ended with no end recorded" if run else None)) if ended else None}
    return {"harness": HARNESS, "account": run.get("account"), "session_id": reg.get("sessionId") or run.get("session"),
            "machine": _machine(ctx), "cwd": cwd, "branch": run.get("branch") or _branch_of(cwd, records),
            "pid": reg.get("pid") if reg else run.get("pid"),
            "started_at": (_num(reg.get("startedAt")) or 0) / 1000.0 or _num(run.get("started")),
            "updated_at": ((_num(reg.get("statusUpdatedAt") or reg.get("updatedAt")) or 0) / 1000.0
                           or _num(run.get("ended")) or _num(run.get("started"))),
            "state": state, "attention": attention, "model": model or run.get("model"),
            "effort": effort or run.get("effort"), "title": reg.get("name") or run.get("title") or run.get("topic"),
            "attach": "screen %s" % run["screen"] if run.get("screen") and not ended else None,
            "native": {k: v for k, v in native.items() if v is not None}}


def _live_record(ctx, sid, reg, run, records=None):
    path, st = run if run else (None, None)
    if records is None:
        records = _tail(transcript(sid, reg.get("cwd") if reg else (st or {}).get("wt")))
    if reg:
        state, att = STATES.get(reg.get("status"), "working"), _attention(reg)
    else:   # a run whose claude is up with no registry entry yet
        state, att = ("working" if (st or {}).get("mode") == "headless" else "submitted"), None
    return _record(ctx, reg, st, path, records, state, att)


# ---- the verbs -----------------------------------------------------------------------------

def sessions(ctx=None):
    """V4 for bin/harness: every live Claude Code session on this machine — the registry's, joined
    to their runs, plus the runs whose claude is up with no registry entry yet."""
    reg, runs = _registry(ctx), _live_runs(ctx)
    out = [_live_record(ctx, sid, r, runs.get(sid)) for sid, r in sorted(reg.items())]
    out += [_live_record(ctx, sid, None, run) for sid, run in sorted(runs.items()) if sid not in reg]
    return out


def list():  # noqa: A001 — the contract's verb name
    """V4: every live session on this Mac, as records (bin/stalls.py reads session_id and state)."""
    return sessions(None)


def _matches(ref, sid, title=None, topic=None):
    if not ref:
        return False
    if sid and (sid == ref or (len(ref) >= 6 and sid.startswith(ref))):
        return True
    return ref in (title, topic)


def candidates(ctx, ref):
    """V3 for bin/harness: every record REF may mean — a live session by id, prefix of 6+ or title;
    a run, live or over, by id, prefix or topic. bin/harness's pick() chooses, one rule for all."""
    reg, live = _registry(ctx), _live_runs(ctx)
    out, done = [], set()
    for path, st in _all_runs(ctx):
        sid = st.get("session")
        if not _matches(ref, sid, st.get("title"), st.get("topic")):
            continue
        if sid in reg or sid in live:
            if sid not in done:
                out.append(_live_record(ctx, sid, reg.get(sid), live.get(sid) or (path, st)))
                done.add(sid)
            continue
        records = _tail(transcript(sid, st.get("wt") or st.get("repo"))) if sid else []
        out.append(_record(ctx, None, st, path, records, _end_state(st) if st.get("ended") else "failed", None, ended=True))
    for sid, r in sorted(reg.items()):
        if sid not in done and _matches(ref, sid, r.get("name")):
            out.append(_live_record(ctx, sid, r, live.get(sid)))
            done.add(sid)
    return out


def status(session_id, read_reply=True):
    """V3: one session's record. Live: the registry's state and attention. Not live: by its run's end
    when a run record names it (_end_state), else `completed`, or `failed` when the last record is
    an API error — the contract's words; whether the reply *closed* the work is Atlas's rule
    (bin/session_status.py), never the adapter's. `process` says whether a live process holds it;
    `last_message` is the last reply (None for a guarded session: the caller passes read_reply=False
    and its text is never opened)."""
    reg, live = _registry().get(session_id), _live_runs()
    run = live.get(session_id)
    if run is None:
        run = next(((p, st) for p, st in reversed(_all_runs()) if st.get("session") == session_id), None)
    cwd = (reg or {}).get("cwd") or (run[1].get("wt") if run else None)
    # a guarded session's transcript is never opened, not even for its model (K6)
    path = transcript(session_id, cwd) if read_reply else None
    records = _tail(path)
    reply = last_reply(session_id, records) if path else None
    if reg or session_id in live:
        out = _live_record(None, session_id, reg, run, records)
    elif run:
        st = run[1]
        out = _record(None, None, st, run[0], records, _end_state(st) if st.get("ended") else "failed", None, ended=True)
    else:
        out = _record(None, {}, None, None, records, "failed" if (reply or {}).get("api_error") else "completed", None)
        out["session_id"] = session_id
    out["process"] = bool(reg) or session_id in live
    out["last_message"] = (reply or {}).get("text")
    out["last_message_at"] = (reply or {}).get("at")
    out["api_error"] = bool((reply or {}).get("api_error"))
    out["last_at"] = (reply or {}).get("last_at")
    out["transcript"] = reply is not None
    return out


# ---- V1 run, V2 next turn, V5 stop: bin/dispatch, as bin/autofinish-run drives it --------------
# This Mac only, never over ssh: what crosses to a peer is the reads above. `dispatch --start`
# runs in the caller's process until its watcher ends the session (dispatch's header), so V1 starts
# it detached, as autofinish-run's detach() does: a double fork and setsid, out of the caller's
# process group, so the run outlives a Bash call or a session that ends. The session id is ours to
# give (--session-id), so it is known at once; the record is then read back, never predicted.

_FINAL = ("completed", "failed", "canceled")


def _start_wait():
    """Seconds to wait for a started run's record (HARNESS_START_WAIT; tests shorten it)."""
    try:
        return float(os.environ.get("HARNESS_START_WAIT") or 30)
    except ValueError:
        return 30.0


def _dispatch(ctx):
    return os.environ.get("HARNESS_DISPATCH") or os.path.join(ctx.coding, "bin", "dispatch")


def _log_path(name):
    d = os.environ.get("HARNESS_LOG_DIR") or os.path.join(_home(), "Library", "Logs", "claude-weekly", "harness")
    os.makedirs(d, exist_ok=True)
    return os.path.join(d, "%s-%s.log" % (time.strftime("%Y-%m-%d-%H%M%S"), re.sub(r"[^A-Za-z0-9.-]+", "-", name)))


def _detach(argv, log, cwd=None):
    """ARGV in a grandchild in its own session, stdout and stderr appended to LOG; returns at once."""
    pid = os.fork()
    if pid:
        _, status = os.waitpid(pid, 0)
        if not os.WIFEXITED(status) or os.WEXITSTATUS(status):
            raise OSError("the detaching child ended with status %d" % status)
        return
    try:
        os.setsid()
        if os.fork():
            os._exit(0)
        fd = os.open(log, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o644)
        null = os.open(os.devnull, os.O_RDONLY)
        os.dup2(null, 0)
        os.dup2(fd, 1)
        os.dup2(fd, 2)
        if cwd:
            os.chdir(cwd)
        os.execvp(argv[0], argv)
    except BaseException as e:   # noqa: BLE001 — the grandchild says why in the log, then goes
        try:
            os.write(2, ("harness: could not start %s: %s\nFAILED\n" % (argv[0], e)).encode())
        except OSError:
            pass
    os._exit(127)


def _slug(text):
    return re.sub(r"-+", "-", re.sub(r"[^A-Za-z0-9-]", "-", text or "")).strip("-").lower()


def _tier(req):
    out = []
    for k in ("model", "effort", "account"):
        if req.get(k):
            out += ["--" + k, req[k]]
    return out + (["--headless"] if req.get("headless") else [])


def _wait_record(ctx, sid, log, t0, prior=None):
    """(path, record) of the run once dispatch wrote it — its session, started at or after t0 — or
    None when the wait passed first; fails when dispatch's log says FAILED."""
    end = time.time() + _start_wait()
    while True:
        _RUNS.clear()
        for path, st in reversed(_all_runs(ctx)):
            if st.get("session") == sid and (_num(st.get("started")) or 0) >= t0 - 2 \
                    and (prior is None or st.get("resumed_from") == prior):
                return path, st
        try:
            with open(log) as f:
                said = f.read()
        except OSError:
            said = ""
        if "FAILED" in said:
            last = [l for l in said.splitlines() if "FAILED" in l][-1]
            ctx.fail("dispatch did not start it: %s (log %s)" % (last.strip(), log), 1)
        if time.time() >= end:
            return None
        time.sleep(0.5)


def _started(ctx, sid, log, t0, req, prior=None):
    """The record of a run just started: read back once dispatch has written it, else `submitted`
    with what is known (the start lock may hold it up to 150 s behind another start)."""
    got = _wait_record(ctx, sid, log, t0, prior)
    if got:
        rec = _live_record(ctx, sid, _registry(ctx).get(sid), _live_runs(ctx).get(sid) or got)
    else:
        rec = _record(ctx, None, {"session": sid, "wt": req.get("cwd"), "repo": req.get("repo")}, None, [], "submitted", None)
    rec["native"]["log"] = log
    if prior:
        rec["native"]["resumed_from"] = prior
    return rec


def run(ctx, req):
    """V1. --prompt in --cwd: `dispatch --start` detached, under our session id. --branch alone: a
    seeded branch, `dispatch BRANCH`, which schedules itself through launchd (about 2 min) and picks
    the id at fire time — the record is then `submitted` with no id; status finds it by its topic."""
    disp = _dispatch(ctx)
    if req.get("branch") and not req.get("prompt"):
        argv = [disp, req["branch"], "--repo", req["repo"]] + (["--on", req["on"]] if req.get("on") else []) + _tier(req)
        try:
            r = subprocess.run(argv, capture_output=True, text=True, timeout=300)
        except (OSError, subprocess.TimeoutExpired) as e:
            ctx.fail("dispatch %s: %s" % (req["branch"], e), 1)
        said = (r.stdout + r.stderr).strip().splitlines()
        if r.returncode:
            ctx.fail("dispatch %s: exit %d: %s" % (req["branch"], r.returncode, said[-1] if said else ""), 1 if r.returncode == 1 else 2)
        topic = re.sub(r"^\d{4}-\d{2}-\d{2}-", "", req["branch"].rsplit("/", 1)[-1])
        rec = _record(ctx, None, {"branch": req["branch"], "repo": req["repo"], "topic": topic}, None, [], "submitted", None)
        rec["native"]["dispatch_said"] = said[-1] if said else None
        # where it went: --on here is this Mac; no --on takes dispatch's default host (the build Mac
        # since 2026-10-13), this Mac only on its --fallback here — dispatch's own output says which
        on, default = req.get("on"), os.environ.get("DISPATCH_DEFAULT_ON") or getattr(ctx, "dispatch_host", "")
        if on == "here":
            on = rec["machine"]
        elif not on:
            on = default if default and default in " ".join(said) else rec["machine"]
        rec["machine"] = on
        return rec
    if req.get("on"):
        ctx.fail("--on goes with --branch (a seeded run); a --prompt run starts on this Mac", 2)
    cwd = req.get("cwd")
    if not cwd:
        ctx.fail("claude-code run --prompt needs --cwd: a worktree on a claude/* branch", 2)
    branch = _branch_of(cwd, [])
    if not (branch or "").startswith("claude/"):
        ctx.fail("%s is on %s, not a claude/* branch: a run writes in a worktree of its own (rules/git-workflow.md)"
                 % (cwd, branch or "no branch"), 2)
    name = req.get("name") or re.sub(r"^\d{4}-\d{2}-\d{2}-", "", branch.rsplit("/", 1)[-1])
    sid = str(uuid.uuid4())
    log = _log_path(name)
    t0 = time.time()
    _detach([disp, "--start", req["prompt"], cwd, name, "--session-id", sid] + _tier(req), log, cwd)
    return _started(ctx, sid, log, t0, req)


def resume(ctx, rec, req):
    """V2 through `dispatch --start --resume` (bin/dispatch's D9 commit). A live session is not
    continued beside itself — two claude processes on one transcript — so a plain next turn takes one
    that is over; --fork copies an idle or ended one under a new id."""
    sid, state = rec.get("session_id"), rec.get("state")
    if not sid:
        ctx.fail("this record has no session id yet (a seeded run before it fired): nothing to continue", 2)
    if state not in _FINAL and not req.get("fork"):
        ctx.fail("%s is live (%s): stop it first (harness stop %s), or --fork a copy" % (sid, state, sid), 2)
    if req.get("fork") and state in ("working", "submitted", "input-required"):
        ctx.fail("%s is mid-turn (%s): a fork copies the turn still running; fork it once it is idle" % (sid, state), 2)
    cwd = rec.get("cwd")
    if not cwd or not os.path.isdir(cwd):
        ctx.fail("%s's directory %s is not here: nothing to continue in" % (sid, cwd), 2)
    branch = _branch_of(cwd, [])
    if not (branch or "").startswith("claude/"):
        # run()'s rule: an unattended turn never writes in a checkout on main (the owner's own session's, say)
        ctx.fail("%s is on %s, not a claude/* branch: a continued run writes in a worktree of its own (rules/git-workflow.md)"
                 % (cwd, branch or "no branch"), 2)
    base = _slug((rec.get("native") or {}).get("topic") or rec.get("title") or "") or "next-" + sid[:8]
    new = str(uuid.uuid4()) if req.get("fork") else sid
    name = req.get("name") or (base + "-fork" if req.get("fork") else base)
    argv = [_dispatch(ctx), "--start", req["prompt"], cwd, name, "--resume", sid]
    if req.get("fork"):
        argv += ["--fork", "--session-id", new]
    log = _log_path(name)
    t0 = time.time()
    _detach(argv + _tier(req), log, cwd)
    return _started(ctx, new, log, t0, dict(req, cwd=cwd), prior=sid)


def stop(ctx, rec):
    """V5: `dispatch --end TOPIC --repo REPO` — busy or not, its window and screen with it — then the
    run's record once its watcher has written the end. A dispatch run only: a session with no run
    record is the owner's own, not this verb's to end."""
    native = rec.get("native") or {}
    sid = rec.get("session_id")
    if not native.get("run") or not native.get("topic"):
        ctx.fail("%s is no dispatch run (no run record): harness stop ends only what dispatch or a harness started" % sid, 2)
    if rec.get("state") not in _FINAL:
        argv = [_dispatch(ctx), "--end", native["topic"]] + (["--repo", native["repo"]] if native.get("repo") else [])
        try:
            r = subprocess.run(argv, capture_output=True, text=True, timeout=120)
        except (OSError, subprocess.TimeoutExpired) as e:
            ctx.fail("dispatch --end %s: %s" % (native["topic"], e), 1)
        if r.returncode:
            ctx.fail("dispatch --end %s: exit %d: %s" % (native["topic"], r.returncode, (r.stdout + r.stderr).strip()), 1)
        end = time.time() + _start_wait()
        while True:
            _RUNS.clear()
            got = [c for c in candidates(ctx, sid) if (c.get("native") or {}).get("run") == native["run"]]
            if got and got[0].get("state") in _FINAL:
                rec = got[0]
                break
            if time.time() >= end:
                ctx.warn("%s: ended, but its record has no end yet after %d s" % (sid, _start_wait()))
                rec = got[0] if got else rec
                break
            time.sleep(0.5)
    reply = last_reply(sid) if sid else None
    rec["last_message"] = (reply or {}).get("text") or None
    return rec



# ---- send: bin/hail's door into a live session ---------------------------------------------
# The inbox socket, as S1 of the Lookout and Hail design probed it (cli 2.1.306, attended, 2026-10-21):
# one connection to the registry's `messagingSocketPath`, newline-terminated JSON — an optional
# {"type":"auth","token":<peerToken>} from the receiver's sessions/<pid>.<sha>.key, then
# {"type":"user","message":{"role":"user","content":<frame>}}. The socket answers nothing (0 bytes),
# so whether it arrived is read back from the receiver: its transcript's `queue-operation` enqueue
# of the frame, or its registry status turning busy after the post. A post mid-turn lands at the
# receiver's next tool boundary — in the middle of someone's work — hence the re-read just before
# posting and the 60 s of quiet it demands (the design's F11).

IDLE_S = 60   # the quiet a socket post needs (the design's contract line)
# `idle` and `shell` both mean the turn is over: `shell` is idle with a background shell (a listener,
# say), and S1 saw one take a hail at once. The contract's state for `shell` stays `working` (STATES).
_DOOR_OPEN = ("idle", "shell")


def _readback_s():
    try:
        return float(os.environ.get("HAIL_READBACK_S") or 10)
    except ValueError:
        return 10.0


def _peer_token(pid, proc_start=None):
    """The receiver's peer token, or None: its sessions/<pid>.<sha>.key (0600), JSON with `peerToken`
    or the bare token. Read, sent on the socket, never printed or logged. A key whose `procStart` is
    the registry's goes first: a pid reused after a crash can leave an orphan key beside the live one."""
    keys = sorted(glob.glob(os.path.join(sessions_dir(), "%d.*.key" % pid)))
    if proc_start is not None:
        def _own(p):
            try:
                with open(p) as f:
                    return json.loads(f.read()).get("procStart") == proc_start
            except (OSError, ValueError, AttributeError):
                return False
        keys.sort(key=lambda p: not _own(p))
    for p in keys:
        try:
            with open(p) as f:
                raw = f.read().strip()
        except OSError:
            continue
        try:
            d = json.loads(raw)
        except ValueError:
            d = raw
        tok = d.get("peerToken") if isinstance(d, dict) else d
        if isinstance(tok, str) and tok:
            return tok
    return None


def _reg_file(pid, sid):
    """The registry record of PID, re-read from its file now, if it is still SID's."""
    try:
        with open(os.path.join(sessions_dir(), "%d.json" % pid)) as f:
            reg = json.load(f)
    except (OSError, ValueError, TypeError):
        return None
    return reg if isinstance(reg, dict) and reg.get("sessionId") == sid else None


def _arrived(sid, cwd, frame, t0, pid):
    """How the post shows on the receiver's side, or None: its transcript enqueued the frame, or its
    registry turned busy after the post."""
    head = frame[:60]
    for e in reversed(_tail(transcript(sid, cwd))):
        if e.get("type") != "queue-operation" or e.get("operation") != "enqueue":
            continue
        at = _epoch(e.get("timestamp"))
        if at is not None and at < int(t0) - 1:
            break
        if head in json.dumps(e.get("content"), ensure_ascii=False) or head in str(e.get("content")):
            return "the receiver's transcript enqueued it"
    reg = _reg_file(pid, sid) or {}
    if reg.get("status") == "busy" and (_num(reg.get("statusUpdatedAt")) or 0) / 1000.0 >= t0 - 1:
        return "the receiver's registry turned busy after the post"
    return None


def send(ctx, rec, msg):
    """bin/hail's socket road into REC, a live session on this Mac. MSG: frame, dry, idle_s. Returns
    {"verdict": delivered|held|refused|unreachable|dry-run, "why"}: refused while the session works
    or has been idle under idle_s (a pointer waits; `hail --when idle` waits for it); held when the
    post went out and nothing on the receiver's side shows it within HAIL_READBACK_S (the vendor holds
    a peer message for review under some permission modes)."""
    sid, pid = rec.get("session_id"), rec.get("pid")
    if not sid or not isinstance(pid, int):
        return {"verdict": "unreachable", "why": "no live process to post to"}
    reg = _reg_file(pid, sid)   # the re-read, right before the post
    if reg is None or not _alive(pid):
        return {"verdict": "unreachable", "why": "%s has no registry record for pid %s now" % (sid[:8], pid)}
    sock = reg.get("messagingSocketPath")
    if not sock:
        return {"verdict": "unreachable", "why": "%s binds no inbox (a -p session)" % sid[:8]}
    st = reg.get("status")
    if st not in _DOOR_OPEN:
        return {"verdict": "refused", "why": "%s is %s: a post would land at its next tool boundary" % (sid[:8], st or "in an unknown state")}
    at = _num(reg.get("statusUpdatedAt") or reg.get("updatedAt"))
    quiet = time.time() - at / 1000.0 if at else 0   # no time on the record: not known quiet, refused
    need = msg.get("idle_s", IDLE_S)
    if quiet < need:
        return {"verdict": "refused", "why": "%s has been %s for %d s, under %d s" % (sid[:8], st, quiet, need)}
    if msg.get("dry"):
        return {"verdict": "dry-run", "why": "%s %s for %d s; would post to its inbox" % (sid[:8], st, quiet)}
    token = _peer_token(pid, reg.get("procStart"))
    lines = ([{"type": "auth", "token": token}] if token else []) + [
        {"type": "user", "message": {"role": "user", "content": msg["frame"]}}]
    t0 = time.time()
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        s.settimeout(5)
        s.connect(sock)
        s.sendall("".join(json.dumps(l) + "\n" for l in lines).encode())
    except OSError as e:
        return {"verdict": "unreachable", "why": "%s's inbox: %s" % (sid[:8], e)}
    finally:
        s.close()
    end = t0 + _readback_s()
    while True:
        how = _arrived(sid, reg.get("cwd"), msg["frame"], t0, pid)
        if how:
            return {"verdict": "delivered", "why": how}
        if time.time() >= end:
            return {"verdict": "held", "why": "posted; nothing on %s's side shows it after %d s" % (sid[:8], _readback_s())}
        time.sleep(0.25)
