"""The Codex adapter: OpenAI's Codex CLI 0.162.1 behind the harness contract
(docs/harness-contract-2026-10-11.md section 3 and H2, E4; orchestration B5 part 2 — the owner's D6-B,
2026-10-14: ChatGPT Pro, the CLI from the Homebrew cask on both Macs; the laptop's is signed in).

Codex keeps no live registry, so the contract's wrapper shim (section 3, "How the shims work"):
V1 runs `codex exec --json` under a wrapper process this file forks off, detached (double fork,
setsid: it outlives the caller's Bash call), which owns the codex pid and writes the run's record
from the JSONL stream — the thread id from the first event, the last agent message, the turns,
the exit. V3/V5 answer from that record; V4 is the directory of records whose codex still runs.

    HARNESS_RUNS_DIR (default ~/Library/Logs/claude-weekly/harness-runs/)
        codex-<stamp>-<name>.json    the record: run, thread, pid, proc_start, cwd, branch, repo,
                                     model, effort, started, ended, exit, end_reason, last_message,
                                     turns, resumed_from, fork, codex_home
        codex-<stamp>-<name>.jsonl   codex's own events, as printed
        codex-<stamp>-<name>.log     its stderr

Codex's own store is read too, for a thread no wrapper ran (the desktop app, a TUI): $CODEX_HOME
(else ~/.codex) `state_5.sqlite` table `threads` (id, rollout_path, cwd, title, model,
reasoning_effort, git_branch, created_at_ms, updated_at_ms, archived), `goals_1.sqlite`
`thread_goals.status`, and the rollout JSONL's last `event_msg` of type task_started, task_complete
(`last_agent_message`) or turn_aborted. All read-only (sqlite `mode=ro`); shapes read on this
laptop 2026-10-14 (the B5 part 2 report). Such a thread is live only while its turn is open and
its rollout was written in the last FRESH_S seconds: Codex says no more than that.

The command, every time: `codex exec --json --approve-for-me -C <cwd> [-m M] [-c model_reasoning_effort="E"]
[resume|fork <thread>] -`, the prompt on stdin (so no prompt is ever parsed as a flag). Never
`--dangerously-bypass-approvals-and-sandbox`: `--approve-for-me` routes approval requests through
automatic review inside the workspace-write sandbox (`codex exec --help`, 0.162.1). `exec fork`
exists in 0.162.1 (the contract's H2 read only the interactive `codex fork`): a headless fork.
`resume` and `fork` list neither `--approve-for-me` nor `-C` among their own options; given before
the subcommand they hold (probe 2026-10-15, 0.162.1, a scratch repo: a thread started in dir a,
continued with this argv from dir b, ran `pwd` in b and wrote a file there with no prompt; `fork`
not probed, same parent flags). Event names are OpenAI's documented ones (thread.started,
turn.started, item.completed with an agent_message item, turn.completed, turn.failed, error),
seen in that probe's --json stream.

bin/harness refuses Codex in a public repo before this file runs (its guard()).
"""
import json
import os
import re
import signal
import sqlite3
import subprocess
import time
import uuid

HARNESS = "codex"
NAME = HARNESS
_FINAL = ("completed", "failed", "canceled")
FRESH_S = 300      # a thread no wrapper ran is live while its open turn wrote in the last 5 minutes
TAIL_BYTES = 256 * 1024
TEXT_CAP = 4000
# goals_1's statuses that say more than the turn does (the rest — active, complete — do not)
_GOALS = {"usage_limited": "auth-required", "budget_limited": "auth-required", "blocked": "input-required",
          "paused": "idle"}


def _home():
    return os.environ.get("HOME") or os.path.expanduser("~")


def _codex_home():
    return os.environ.get("CODEX_HOME") or os.path.join(_home(), ".codex")


def _runs_dir():
    return os.environ.get("HARNESS_RUNS_DIR") or os.path.join(_home(), "Library", "Logs", "claude-weekly", "harness-runs")


def _bin():
    return os.environ.get("HARNESS_CODEX") or "codex"


def _start_wait():
    try:
        return float(os.environ.get("HARNESS_START_WAIT") or 30)
    except ValueError:
        return 30.0


def _load(path):
    try:
        with open(path) as f:
            d = json.load(f)
        return d if isinstance(d, dict) else None
    except (OSError, ValueError):
        return None


def _save(path, rec):
    tmp = "%s.%d.tmp" % (path, os.getpid())   # the wrapper and `harness stop` both write it: never one temp name
    with open(tmp, "w") as f:
        json.dump(rec, f, indent=1)
    os.replace(tmp, path)


def _update(path, **kw):
    """Merge KW into the record on disk (a stop may have written `ending` since it was read)."""
    rec = _load(path) or {}
    rec.update(kw)
    _save(path, rec)
    return rec


def _pstart(pid):
    """`ps -o lstart` in UTC, as bin/dispatch and dispatch-rc record a process's start."""
    try:
        r = subprocess.run(["ps", "-o", "lstart=", "-p", str(pid)], capture_output=True, text=True, timeout=5,
                           env=dict(os.environ, TZ="UTC", LC_ALL="C"))
        return " ".join(r.stdout.split()) or None
    except (OSError, subprocess.TimeoutExpired):
        return None


def _running(rec):
    """The record's codex is still the process it started: its pid alive with the recorded start."""
    pid = rec.get("pid")
    if not isinstance(pid, int):
        return False
    try:
        os.kill(pid, 0)
    except PermissionError:
        pass
    except OSError:
        return False
    return not rec.get("proc_start") or _pstart(pid) == rec["proc_start"]


def _git(cwd, *argv):
    try:
        r = subprocess.run(["git", "-C", cwd] + list(argv), capture_output=True, text=True, timeout=20)
    except (OSError, subprocess.TimeoutExpired):
        return None
    return r.stdout.strip() if r.returncode == 0 else None


# ---- Codex's own store ---------------------------------------------------------------------

def _db(name):
    """A read-only connection. Codex's databases are WAL: while Codex runs, `mode=ro` reads through
    its -shm; once Codex has closed them the -shm is gone and `mode=ro` cannot open the file at all
    ("unable to open database file", seen 2026-10-14), so `immutable=1` then — nobody is writing."""
    path = os.path.join(_codex_home(), name)
    if not os.path.exists(path):
        return None
    for q in ("mode=ro", "mode=ro&immutable=1"):
        try:
            con = sqlite3.connect("file:%s?%s" % (path, q), uri=True, timeout=2)
            con.execute("SELECT 1 FROM sqlite_master LIMIT 1")
            con.row_factory = sqlite3.Row
            return con
        except sqlite3.Error:
            continue
    return None


def _threads(where="", args=()):
    con = _db("state_5.sqlite")
    if con is None:
        return []
    try:
        return [dict(r) for r in con.execute(
            "SELECT id, rollout_path, cwd, title, model, reasoning_effort, git_branch, created_at_ms, updated_at_ms, archived "
            "FROM threads %s ORDER BY updated_at_ms DESC LIMIT 200" % where, args)]
    except sqlite3.Error:
        return []
    finally:
        con.close()


def _goal(thread_id):
    con = _db("goals_1.sqlite")
    if con is None:
        return None
    try:
        row = con.execute("SELECT status FROM thread_goals WHERE thread_id = ?", (thread_id,)).fetchone()
        return row[0] if row else None
    except sqlite3.Error:
        return None
    finally:
        con.close()


def _turn(rollout):
    """(open, last_message, last_at, aborted) from a rollout's tail: whether the last task started
    has not completed, the last agent message, and when the file was last written."""
    try:
        with open(rollout, "rb") as fh:
            fh.seek(0, os.SEEK_END)
            size = fh.tell()
            fh.seek(max(0, size - TAIL_BYTES))
            lines = fh.read().decode("utf-8", "replace").splitlines()
        at = os.path.getmtime(rollout)
    except (OSError, TypeError):
        return False, None, None, False
    if size > TAIL_BYTES:
        lines = lines[1:]
    is_open, said, aborted = False, None, False
    for line in lines:
        if '"event_msg"' not in line:
            continue
        try:
            p = (json.loads(line).get("payload") or {})
        except ValueError:
            continue
        t = p.get("type")
        if t == "task_started":
            is_open, aborted = True, False
        elif t == "task_complete":
            is_open = False
            said = p.get("last_agent_message") or said
        elif t == "turn_aborted":
            is_open, aborted = False, True
    return is_open, said, at, aborted


def _thread_record(ctx, th, run=None):
    """A thread no live wrapper holds: its state from the rollout's last turn and its goal."""
    is_open, said, at, aborted = _turn(th.get("rollout_path"))
    fresh = at is not None and time.time() - at < FRESH_S
    state = "working" if is_open and fresh else "canceled" if aborted else "failed" if is_open else "completed"
    end = None if state == "working" else ("aborted" if aborted else "its last turn never completed" if is_open else "turn complete")
    goal = _goal(th["id"])
    if goal in _GOALS and state == "working":
        state = _GOALS[goal]
    att = {"kind": "question", "message": "goal %s" % goal, "since": at} if state == "input-required" else None
    native = {"source": "codex store", "rollout": th.get("rollout_path"), "goal": goal, "archived": bool(th.get("archived")),
              "end_reason": end, "codex_home": _codex_home()}
    return {"harness": HARNESS, "account": None, "session_id": th["id"], "machine": ctx.machine if ctx else None,
            "cwd": th.get("cwd"), "branch": th.get("git_branch"), "pid": None,
            "started_at": (th.get("created_at_ms") or 0) / 1000.0 or None, "updated_at": (th.get("updated_at_ms") or 0) / 1000.0 or at,
            "state": state, "attention": att, "model": th.get("model"), "effort": th.get("reasoning_effort"),
            "title": th.get("title") or None, "attach": None,
            "native": {k: v for k, v in native.items() if v is not None}}


# ---- the wrapper's records -----------------------------------------------------------------

def _records():
    """[(path, record)] of every harness-run codex record, oldest first."""
    d = _runs_dir()
    try:
        names = sorted(n for n in os.listdir(d) if n.startswith("codex-") and n.endswith(".json"))
    except OSError:
        return []
    out = []
    for n in names:
        rec = _load(os.path.join(d, n))
        if rec:
            out.append((os.path.join(d, n), rec))
    return out


def _end_state(rec):
    if rec.get("ending"):
        return "canceled"
    code = rec.get("exit")
    if code == 0:
        return "completed"
    if code in (130, 143, -2, -15):
        return "canceled"
    return "failed"


def _run_record(ctx, path, rec):
    live = not rec.get("ended") and _running(rec)
    if live:
        state = "working" if rec.get("thread") else "submitted"
        goal = _goal(rec["thread"]) if rec.get("thread") else None
        if goal in _GOALS:
            state = _GOALS[goal]
    elif rec.get("ended"):
        state = _end_state(rec)
    else:
        state = "failed"   # its wrapper and codex are gone and nobody wrote an end
    native = {"source": "harness run", "run": path, "run_id": rec.get("run"), "events": rec.get("events"),
              "turns": rec.get("turns"), "resumed_from": rec.get("resumed_from"), "fork": rec.get("fork") or None,
              "error": rec.get("error"), "codex_home": rec.get("codex_home"), "topic": rec.get("name"),
              "repo": rec.get("repo"), "exit": rec.get("exit"),
              "end_reason": (rec.get("end_reason") or ("gone: no end recorded" if not live else None)) if state in _FINAL else None,
              "ended_at": rec.get("ended")}
    return {"harness": HARNESS, "account": rec.get("account"), "session_id": rec.get("thread") or rec.get("run"),
            "machine": ctx.machine if ctx else None, "cwd": rec.get("cwd"), "branch": rec.get("branch"),
            "pid": rec.get("pid") if live else None, "started_at": rec.get("started"),
            "updated_at": rec.get("updated") or rec.get("ended") or rec.get("started"), "state": state,
            "attention": None, "model": rec.get("model"), "effort": rec.get("effort"), "title": rec.get("name"),
            "attach": None, "native": {k: v for k, v in native.items() if v is not None}}


# ---- the verbs: reads ----------------------------------------------------------------------

def sessions(ctx):
    """V4: harness runs whose codex still runs, plus threads of the store with an open, fresh turn
    that no such run holds."""
    out, held = [], set()
    for path, rec in _records():
        r = _run_record(ctx, path, rec)
        if r["state"] not in _FINAL:
            out.append(r)
            held.add(r["session_id"])
    cutoff = int((time.time() - FRESH_S) * 1000)
    for th in _threads("WHERE updated_at_ms >= ? AND archived = 0", (cutoff,)):
        if th["id"] not in held:
            r = _thread_record(ctx, th)
            if r["state"] not in _FINAL:
                out.append(r)
    return out


def _matches(ref, *ids):
    for i in ids:
        if i and (i == ref or (len(ref) >= 6 and str(i).startswith(ref))):
            return True
    return False


def candidates(ctx, ref):
    """V3: every run or thread REF may mean — a thread id or a prefix of 6+, a run id, a run's
    name, a thread's title."""
    if not ref:
        return []
    out, held = [], set()
    for path, rec in _records():
        if _matches(ref, rec.get("thread"), rec.get("run")) or ref == rec.get("name"):
            r = _run_record(ctx, path, rec)
            out.append(r)
            held.add(rec.get("thread"))
    for th in _threads():
        if th["id"] not in held and (_matches(ref, th["id"]) or ref == th.get("title")):
            out.append(_thread_record(ctx, th))
    return out


# ---- V1, V2, V5 ----------------------------------------------------------------------------

def _argv(req, cwd, sub=None):
    argv = [_bin(), "exec", "--json", "--approve-for-me", "-C", cwd]
    if req.get("model"):
        argv += ["-m", req["model"]]
    if req.get("effort"):
        argv += ["-c", 'model_reasoning_effort="%s"' % req["effort"]]
    return argv + (sub or []) + ["-"]


def _wrap(path, argv, prompt, cwd):
    """The wrapper, in the detached grandchild: codex as its child, the record kept from its stream."""
    rec = _load(path) or {}
    events = open(rec["events"], "a")
    err = open(rec["log"], "a")
    try:
        p = subprocess.Popen(argv, cwd=cwd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=err, text=True)
    except OSError as e:
        _update(path, ended=time.time(), exit=127, end_reason="could not start %s: %s" % (argv[0], e))
        return
    _update(path, pid=p.pid, proc_start=_pstart(p.pid), wrapper=os.getpid())
    try:
        p.stdin.write(prompt)
        p.stdin.close()
    except OSError:
        pass
    turns = 0
    for line in p.stdout:
        events.write(line)
        events.flush()
        try:
            e = json.loads(line)
        except ValueError:
            continue
        t = e.get("type") if isinstance(e, dict) else None
        if t == "thread.started" and e.get("thread_id"):
            _update(path, thread=e["thread_id"], updated=time.time())
        elif t == "item.completed" and (e.get("item") or {}).get("type") == "agent_message":
            _update(path, last_message=((e["item"].get("text") or "")[-TEXT_CAP:]) or None, updated=time.time())
        elif t == "turn.completed":
            turns += 1
            _update(path, turns=turns, usage=e.get("usage"), updated=time.time())
        elif t in ("turn.failed", "error"):
            inner = e.get("error")
            msg = e.get("message") or (inner.get("message") if isinstance(inner, dict) else inner)
            _update(path, error=str(msg)[:500] if msg else t, updated=time.time())
    code = p.wait()
    cur = _load(path) or {}
    _update(path, ended=time.time(), exit=code,
            end_reason=cur.get("ending") or "exit %d" % code)


def _detach(fn):
    pid = os.fork()
    if pid:
        _, status = os.waitpid(pid, 0)
        if not os.WIFEXITED(status) or os.WEXITSTATUS(status):
            raise OSError("the detaching child ended with status %d" % status)
        return
    code = 0
    try:
        os.setsid()
        if os.fork():
            os._exit(0)
        null = os.open(os.devnull, os.O_RDWR)
        for fd in (0, 1, 2):
            os.dup2(null, fd)
        fn()
    except BaseException:   # noqa: BLE001 — the grandchild has nobody to tell but its record
        code = 1
    os._exit(code)


def _start(ctx, req, cwd, sub, name, prior=None, fork=False):
    os.makedirs(_runs_dir(), exist_ok=True)
    stamp = time.strftime("%Y%m%d-%H%M%S")
    base = os.path.join(_runs_dir(), "codex-%s-%s" % (stamp, re.sub(r"[^A-Za-z0-9.-]+", "-", name)))
    run_id = "codex-run-" + uuid.uuid4().hex[:12]
    path = base + ".json"
    _save(path, {"harness": HARNESS, "run": run_id, "name": name, "cwd": cwd, "repo": req.get("repo"),
                 "branch": _git(cwd, "symbolic-ref", "--short", "-q", "HEAD"), "model": req.get("model"),
                 "effort": req.get("effort"), "started": time.time(), "events": base + ".jsonl", "log": base + ".log",
                 "resumed_from": prior, "fork": fork, "codex_home": _codex_home(), "account": None})
    argv = _argv(req, cwd, sub)
    _detach(lambda: _wrap(path, argv, req["prompt"], cwd))
    # the id is codex's (thread.started, its first event), so it is read back, never made up here
    end = time.time() + _start_wait()
    while time.time() < end:
        rec = _load(path) or {}
        if rec.get("thread") or rec.get("ended"):
            break
        time.sleep(0.25)
    rec = _load(path) or {}
    if rec.get("ended") and not rec.get("thread"):
        ctx.fail("codex did not start: %s (log %s)" % (rec.get("error") or rec.get("end_reason"), rec.get("log")), 1)
    return _run_record(ctx, path, rec)


def run(ctx, req):
    """V1: `codex exec --json` under the wrapper, in --cwd (a claude/* worktree, as every run here)."""
    if req.get("branch") or req.get("on"):
        ctx.fail("codex run takes --prompt in --cwd (a worktree); --branch and --on are dispatch's", 2)
    cwd = req.get("cwd")
    if not cwd or not req.get("prompt"):
        ctx.fail("codex run needs --cwd (a claude/* worktree) and --prompt; --runner orca makes the worktree itself", 2)
    branch = _git(cwd, "symbolic-ref", "--short", "-q", "HEAD")
    if not (branch or "").startswith("claude/"):
        ctx.fail("%s is on %s, not a claude/* branch: a run writes in a worktree of its own (rules/git-workflow.md)"
                 % (cwd, branch or "no branch"), 2)
    name = req.get("name") or re.sub(r"^\d{4}-\d{2}-\d{2}-", "", branch.rsplit("/", 1)[-1])
    return _start(ctx, req, cwd, None, name)


def resume(ctx, rec, req):
    """V2: `codex exec resume <thread>`, or `exec fork <thread>` for a copy under a new id."""
    tid = rec.get("session_id")
    native = rec.get("native") or {}
    if not tid or tid.startswith("codex-run-"):
        ctx.fail("this run has no Codex thread id (it never started): nothing to continue", 2)
    if rec.get("state") not in _FINAL and not req.get("fork"):
        ctx.fail("%s is live (%s): stop it first (harness stop %s), or --fork a copy" % (tid, rec.get("state"), tid), 2)
    cwd = rec.get("cwd")
    if not cwd or not os.path.isdir(cwd):
        ctx.fail("%s's directory %s is not here: nothing to continue in" % (tid, cwd), 2)
    sub = ["fork" if req.get("fork") else "resume", tid]
    name = req.get("name") or ((native.get("topic") or rec.get("title") or tid[:8]) + ("-fork" if req.get("fork") else ""))
    name = re.sub(r"[^A-Za-z0-9-]+", "-", name).strip("-")[:60] or tid[:8]
    return _start(ctx, dict(req, repo=req.get("repo") or native.get("repo")), cwd, sub, name, prior=tid, fork=bool(req.get("fork")))


def stop(ctx, rec):
    """V5: SIGTERM to the run's codex — its pid and start time checked first — then the record once
    the wrapper wrote the end. A thread no harness run holds is not this verb's to end."""
    native = rec.get("native") or {}
    path = native.get("run")
    if not path:
        ctx.fail("%s is no harness run (Codex's own thread): end it where it runs" % rec.get("session_id"), 2)
    cur = _load(path) or {}
    if rec.get("state") not in _FINAL and not cur.get("ended"):
        if not _running(cur):
            ctx.fail("%s: its codex (pid %s) is not the process the run started; nothing signalled" % (rec.get("session_id"), cur.get("pid")), 1)
        _update(path, ending="stopped by harness stop")
        try:
            os.kill(cur["pid"], signal.SIGTERM)
        except OSError as e:
            ctx.fail("SIGTERM to %s: %s" % (cur["pid"], e), 1)
        end = time.time() + _start_wait()
        while time.time() < end and not (_load(path) or {}).get("ended"):
            time.sleep(0.25)
    # the reply's text only in the exit report, as Claude Code's adapter does: a status or a list
    # never carries what a session said
    final = _load(path) or cur
    out = _run_record(ctx, path, final)
    out["last_message"] = final.get("last_message")
    return out


def send(ctx, rec, msg):
    """bin/hail's Codex road: `codex queue --thread <id> --message <frame>` (S1 of the Lookout and Hail
    design: it woke an idle Codex TUI thread within about 1 s, framed as a plain user message with no
    peer mark, so the frame's `HAIL <kind> from <sender>` is the only provenance). By an explicit
    thread id only: this adapter lists a thread only while a turn is open (FRESH_S). The CLI's exit 0
    is a durable enqueue, not a reading: `queued`, never `delivered`."""
    tid = rec.get("session_id")
    if not tid or tid.startswith("codex-run-"):
        return {"verdict": "unreachable", "why": "no Codex thread id"}
    if msg.get("dry"):
        return {"verdict": "dry-run", "why": "would run %s queue --thread %s" % (_bin(), tid)}
    try:
        r = subprocess.run([_bin(), "queue", "--thread", tid, "--message", msg["frame"]],
                           capture_output=True, text=True, timeout=30, stdin=subprocess.DEVNULL)
    except (OSError, subprocess.TimeoutExpired) as e:
        return {"verdict": "unreachable", "why": "codex queue: %s" % e}
    if r.returncode:
        tail = (r.stderr or r.stdout or "").strip().splitlines()
        return {"verdict": "unreachable", "why": "codex queue: exit %d: %s" % (r.returncode, tail[-1] if tail else "no output")}
    return {"verdict": "queued", "why": "codex queue: enqueued on thread %s" % tid}
