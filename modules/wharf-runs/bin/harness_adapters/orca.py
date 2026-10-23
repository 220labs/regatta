"""The Orca adapter: Orca 1.4.225's orchestration runtime behind the harness contract
(docs/harness-contract-2026-10-11.md section 3; orchestration B5 part 2 — the owner's D1-E, 2026-10-14:
"Orca … more of an implementation for Wharf, and an engine to execute other parts"). Orca is a
runner, not a model: it starts `claude` or `codex` as a supervised worker in a worktree it makes,
so `--agent claude|codex` picks which. One Orca Dispatch (one attempt at one Task) is one session
here: its id is the record's session_id.

What it runs: the `orca` CLI with `--json` — HARNESS_ORCA, else `orca` on PATH, else the app's own
/Applications/Orca.app/Contents/Resources/bin/orca — always with ELECTRON_RUN_AS_NODE cleared: a
Claude Code session in VS Code inherits it from the extension host, and Orca then runs as plain
Node and exits 9 (lessons/claude-code.md, "A session in VS Code cannot start an Electron app as-is").

V1 run, in order (each step's result read back, never predicted — rules/engineering.md):
    repo list / repo add --path       the repo's Orca id
    worktree create --name <yyyy-mm-dd>-<topic> --repo <id> --no-parent
                                      Orca names the branch itself: given `claude/laptop/x` it made
                                      `claude/laptop/claude-laptop-x`; given the bare
                                      `2026-10-14-harness-probe` it made
                                      `claude/laptop/2026-10-14-harness-probe` (both probed
                                      2026-10-14, Orca's prefix setting as it stood). So the name goes
                                      in bare and the branch is checked, and renamed with `git branch
                                      -m` to claude/<host>/<yyyy-mm-dd>-<topic> before any agent starts
                                      if a setting ever names it otherwise (rules/git-workflow.md)
    terminal list --worktree id:<wt>  the shell Orca opened there: the Run's coordinator. run-create
                                      outside an Orca terminal fails `no_active_sender_terminal`
    orchestration run-create --objective … --from <shell>
    orchestration worker-start --spec PROMPT --worktree id:<wt> --agent A --run R --from <shell>
                                      exits 0 only once the worker is ready
With Orca's default setting the worker is a chat session (`structworker_…`), not a terminal: the
probe's claude ran as Claude Code's SDK entrypoint (`sdk-ts`) in the worktree.
V2 (resume()): a terminal worker's next turn is typed into its terminal (`terminal send --enter`); a
chat worker's goes by `orchestration send --to dispatch:<id>` (Orca refuses `terminal send` for it
and names that route). A send proves a durable enqueue, not that the worker read it. No fork.
V5 stop: `worker-stop`, then `worker-release` when Orca's own nextAction names it (it archives the
output and closes only that worker's terminal). Neither ever removes the worktree or its branch.
Retry (`harness retry`, Orca only): `worker-start --task [--retry-of]`, placement repeated — the
tick's S1 action for an Orca step (B8). tasks(), coordinator() and questions() are the tick's
other reads: `task-list` (S7), `run-show`, `check --peek --types question` (S6).

V3/V4 read `orchestration worker-list` and, for one dispatch, `worker-show`, and join a live worker
to its agent's own session by worktree path (_inner_index): the probe's claude sat at a permission
prompt that Orca reported only as `unverifiable` with no agentWait, while Claude Code's registry
said `waiting: permission prompt`. The mapping is _state(); the shapes are above it. A field Orca
leaves out is absence, never "not waiting" (its own guide), so an unknown shape maps to `working`.
"""
import json
import os
import re
import shlex
import shutil
import subprocess
import time

HARNESS = "orca"
NAME = HARNESS
APP_CLI = "/Applications/Orca.app/Contents/Resources/bin/orca"
AGENTS = ("claude", "codex")
_FINAL = ("completed", "failed", "canceled")


def _bin():
    return os.environ.get("HARNESS_ORCA") or shutil.which("orca") or (APP_CLI if os.path.exists(APP_CLI) else None)


def _app_up():
    """The Orca app is running here. A read never starts it (an `orca` call may launch the runtime;
    not probed), so with the app down there is nothing live to read and V1 refuses. A stub
    (HARNESS_ORCA, the tests) stands in for the app."""
    if os.environ.get("HARNESS_ORCA"):
        return True
    try:
        return subprocess.run(["pgrep", "-f", "Orca.app/Contents/MacOS/Orca"], capture_output=True, timeout=5).returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        return False


def _env():
    env = dict(os.environ)
    env.pop("ELECTRON_RUN_AS_NODE", None)   # the lesson in the module docstring
    return env


def _call(ctx, args, timeout=60):
    """(result, None) or (None, error message) of `orca ARGS --json`."""
    b = _bin()
    if not b:
        return None, "no orca CLI (HARNESS_ORCA, PATH, %s)" % APP_CLI
    try:
        r = subprocess.run([b] + list(args) + ["--json"], env=_env(), capture_output=True, text=True, timeout=timeout)
    except (OSError, subprocess.TimeoutExpired) as e:
        return None, "orca %s: %s" % (" ".join(args[:2]), e)
    try:
        d = json.loads(r.stdout)
    except ValueError:
        tail = (r.stderr or r.stdout or "").strip().splitlines()
        return None, "orca %s: exit %d: %s" % (" ".join(args[:2]), r.returncode, tail[-1] if tail else "no output")
    if not isinstance(d, dict) or not d.get("ok", r.returncode == 0):
        err = (d.get("error") if isinstance(d, dict) else None) or {}
        msg = err.get("message") if isinstance(err, dict) else str(err)
        code = err.get("code") if isinstance(err, dict) else None
        return None, "orca %s: %s%s" % (" ".join(args[:2]), msg or "failed (exit %d)" % r.returncode, " (%s)" % code if code else "")
    return d.get("result") if "result" in d else d, None


START_WAIT = float(os.environ.get("HARNESS_ORCA_START_WAIT") or 90)   # s for a claude of ours to reach Orca


def _account_tool(ctx):
    """bin/account: by the launcher checkout ctx names (bin/harness loads this file with a bare
    __file__, so its abspath is the cwd's), else this file's own, else HARNESS_ACCOUNT (tests)."""
    if os.environ.get("HARNESS_ACCOUNT"):
        return os.environ["HARNESS_ACCOUNT"]
    root = getattr(ctx, "coding", None)
    if root and os.path.exists(os.path.join(str(root), "bin", "account")):
        return os.path.join(str(root), "bin", "account")
    try:   # account is lighthouse's: the core finds it (bin/harness put the core on the path)
        import common
        found = common.tool("account")
        if found:
            return str(found)
    except Exception:   # noqa: BLE001 — no core: the path below, whose absence the caller reports
        pass
    if root:
        return os.path.join(str(root), "bin", "account")
    return os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "account")


def _login(ctx, req, agent):
    """(label, env) of --account (docs/orca-accounts-2026-10-16.md): `auto` is bin/account's pick for
    the repo — with --ship, the login that ship is pinned to, never pinned here (run() pins once a
    worker started) — a label is that row. env is empty for the default dir (the primary login)."""
    acct = req.get("account")
    if not acct:
        return None, {}
    if agent != "claude":
        ctx.fail("--account picks a Claude login; a %s worker runs on the login Orca holds for it" % agent, 2)
    tool = _account_tool(ctx)
    if acct == "auto":
        argv = [tool, "pick", "--repo", req["repo"], "--json"] + (["--ship", req["ship"], "--no-pin"] if req.get("ship") else [])
    else:
        argv = [tool, "limits", acct, "--cached", "--repo", req["repo"], "--json"]
    try:
        r = subprocess.run(argv, capture_output=True, text=True, timeout=240)
        d = json.loads(r.stdout) if r.stdout.strip() else None
    except (OSError, ValueError, subprocess.TimeoutExpired) as e:
        ctx.fail("account %s: %s" % (argv[1], e), 1)
    if acct == "auto":
        if not d or not d.get("account"):
            why = "; ".join("%s: %s" % (l, w) for l, w in (d or {}).get("skipped") or []) or (r.stderr or "").strip()[:300]
            ctx.fail("no login may run it now (%s)" % why, 1)
        if d.get("provider", "claude") != "claude":  # a Codex row's env has no CLAUDE_CONFIG_DIR: claude would run on the default login
            ctx.fail("%s is a %s login; this adapter launches claude only" % (d["account"], d["provider"]), 2)
        return d["account"], d.get("env") or {}
    o = (d or [None])[0] if isinstance(d, list) else None
    if not o:
        ctx.fail("account %s: %s" % (acct, (r.stderr or r.stdout or "unknown").strip()[:300]), 2)
    if o.get("provider", "claude") != "claude":
        ctx.fail("%s is a %s login; this adapter launches claude only" % (acct, o["provider"]), 2)
    if o.get("denied"):
        ctx.fail("%s is on %s's deny list (accounts.json)" % (o["denied"], acct), 2)
    if not o.get("here"):
        ctx.fail("%s's login is not on this Mac (%s): account check says what is owed" % (acct, o.get("why") or o.get("home")), 2)
    return acct, o.get("env") or {}


def _login_terminal(ctx, where, name, env, req):
    """A terminal in the worktree running `claude` on that login's own dir: Orca has no login per
    worker (F6) and selects a Claude account only from its app (P7), but a worker may be a
    terminal we start (`worker-start --terminal`, probed 2026-10-16: the worker's process had the
    env our command gave it). --model and --effort go on our command line: Orca refuses them
    beside --terminal. The default dir runs here too, with CLAUDE_CONFIG_DIR unset: Orca's own
    launch takes the account selected in its app (its `claude-profiles/selected-host` pointer,
    review 2026-10-16), which may not be the primary login."""
    cmd = ["env", "-u", "CLAUDE_CODE_OAUTH_TOKEN"] + (["%s=%s" % kv for kv in sorted(env.items())] or ["-u", "CLAUDE_CONFIG_DIR"]) + ["claude"]
    if req.get("model"):
        cmd += ["--model", req["model"]] + (["--effort", req["effort"]] if req.get("effort") else [])
    res = _must(ctx, ["terminal", "create", "--worktree", where, "--title", name,
                      "--command", " ".join(shlex.quote(c) for c in cmd)], timeout=60) or {}
    h = _first(res, "terminal.handle", "handle")
    if not h:
        ctx.fail("orca terminal create returned no handle: %s" % json.dumps(res)[:300], 1)
    _own(add=h)
    return h


def _own(add=None, drop=None):
    """The agent terminals this adapter started (OWN_FILE): stop closes those and no other — Orca
    marks any terminal it did not make `external`, a shell of the owner's handed to a worker included."""
    path = os.environ.get("HARNESS_ORCA_OWN") or os.path.expanduser("~/.claude/harness-orca-terminals.json")
    try:
        cur = json.load(open(path))
        cur = cur if isinstance(cur, list) else []
    except (OSError, ValueError):
        cur = []
    if add is None and drop is None:
        return cur
    cur = [h for h in cur if h != drop] + ([add] if add and add not in cur else [])
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        tmp = "%s.%d.tmp" % (path, os.getpid())
        with open(tmp, "w") as f:
            json.dump(cur[-200:], f)
        os.replace(tmp, path)
    except OSError:
        pass
    return cur


def foreign_terminal(native):
    """A worker in a terminal Orca did not launch: run()'s own on a picked login (_login_terminal), or
    a shell handed to it. Orca marks it `external` for good (its ownership column; a release of it is
    `retained`, docs/orca-accounts-2026-10-16.md P2), while _own() forgets a handle once stop closes it.
    Its claude outlives the Dispatch, and its login is not in Orca's record: a plain worker-start
    would run on the login Orca holds (/finish review of B8 on main's orca-accounts, 2026-10-16)."""
    native = native or {}
    return native.get("ownership") == "external" or bool(native.get("terminal") and native["terminal"] in _own())


def _close_own(ctx, h):
    _, err = _call(ctx, ["terminal", "close", "--terminal", h], timeout=30)
    if not err:
        _own(drop=h)
    return err


def _start_on(ctx, args):
    """worker-start --terminal once Orca knows the agent there. Orca learns it from the agent's own
    hook events, so the first tries are refused `agent_unconfigured` (probe 2026-10-16); a refused
    start creates nothing, and the wait is bounded. A claude held at the folder-trust dialog never
    reports: said as such."""
    end = time.time() + START_WAIT
    while True:
        res, err = _call(ctx, args, timeout=60)
        if not err or "agent_unconfigured" not in err or time.time() >= end:
            break
        time.sleep(3)
    if err and "agent_unconfigured" in err:
        term = args[args.index("--terminal") + 1]
        scr, _ = _call(ctx, ["terminal", "read", "--terminal", term, "--screen"], timeout=30)
        if "trust this folder" in json.dumps(scr or {}):
            err = ("the claude in %s waits at the folder-trust dialog: that login has not trusted the repo "
                   "(CLAUDE_CONFIG_DIR=<its dir> bin/trust-projects)" % term)
        else:
            err = "no Claude Code reached Orca in %s within %ds: %s" % (term, START_WAIT, err)
    return res, err


def _must(ctx, args, timeout=60, code=1):
    res, err = _call(ctx, args, timeout)
    if err:
        ctx.fail(err, code)
    return res


def _first(d, *paths):
    """The first value found along dotted PATHS in D (Orca's optional fields: absent is None)."""
    for p in paths:
        cur = d
        for k in p.split("."):
            cur = cur.get(k) if isinstance(cur, dict) else None
            if cur is None:
                break
        if cur is not None:
            return cur
    return None


def _ms(v):
    """Epoch seconds from Orca's times: epoch milliseconds, or an ISO string (run-list's)."""
    if isinstance(v, (int, float)) and not isinstance(v, bool):
        return v / 1000.0 if v > 1e11 else float(v)
    if isinstance(v, str) and v:
        import calendar
        try:
            return float(calendar.timegm(time.strptime(v[:19].replace(" ", "T"), "%Y-%m-%dT%H:%M:%S")))
        except ValueError:
            return None
    return None


def _git(cwd, *argv):
    try:
        r = subprocess.run(["git", "-C", cwd] + list(argv), capture_output=True, text=True, timeout=20)
    except (OSError, subprocess.TimeoutExpired):
        return None
    return r.stdout.strip() if r.returncode == 0 else None


# ---- the mapping ---------------------------------------------------------------------------

# The fields, as Orca 1.4.225 printed them for a live claude worker (2026-10-14):
#   worker-list row  dispatchId, taskId, runId, workerState (ready), dispatchStatus (dispatched),
#                    agentTerminalHandle (structworker_… for a chat worker), terminalState (active),
#                    resource.{worktreeId, releaseState}, projection.{stage.{worker, dispatch, detail,
#                    activity}, outcome (in_progress), liveness.{verdict, reason}, attention, nextAction}
#   worker-show      dispatch.{status, terminationReason, createdAt "YYYY-MM-DD HH:MM:SS" UTC,
#                    completedAt}, worker.{updatedAt, startOptions.agent, startOptions.launch.effective
#                    .{model, effort}}, observation.{status, agentWait — absent: Orca never looked}
# A chat worker read `unverifiable` (missing_status) with no agentWait while its claude sat at a
# permission prompt; Claude Code's own registry said `waiting: permission prompt` for the same
# session. So a live worker's state is its agent's own, read by that harness's adapter (_inner),
# and Orca's word decides only what Orca alone knows: settled, stopped, released, exited.
_INNER = {"claude": "claude-code", "codex": "codex"}


def _state(row, show=None, inner=None):
    """(state, attention) of one worker: Orca's settlement first, then Orca's agentWait, then the
    agent's own session (inner), then Orca's liveness verdict."""
    show = show or {}
    proj = row.get("projection") or _first(show, "projection") or {}
    disp = str(row.get("dispatchStatus") or _first(show, "dispatch.status") or "").lower()
    outcome = str(proj.get("outcome") or "").lower()
    worker = str(row.get("workerState") or _first(proj, "stage.worker") or "").lower()
    why = str(_first(show, "dispatch.terminationReason") or _first(show, "dispatch.lastFailure") or "").lower()
    verdict = str(_first(proj, "liveness.verdict") or "").lower()
    wait = _first(show, "observation.agentWait")
    if outcome == "succeeded" or disp in ("completed", "succeeded"):
        return "completed", None
    # a worker-stop leaves dispatch failed, outcome failed, worker stopped, liveness exited with
    # source worker_stop, lastFailure stopped (2026-10-14): a stop asked for is canceled, not failed
    if disp in ("stopped", "canceled", "cancelled", "abandoned") or worker == "stopped" or "stop" in why \
            or _first(proj, "liveness.source") == "worker_stop":
        return "canceled", None
    # D2-B (the owner, 2026-10-15): a live session of the worker's own agent outranks Orca's liveness
    # and a `failed` Orca recorded — only completion and a stop asked for are Orca's alone
    live_inner = bool(inner) and inner.get("state") not in _FINAL + (None,)
    # …except an idle claude in a terminal Orca did not launch: it stays after its Dispatch ends
    # (foreign_terminal), so idle there says nothing of the worker
    if live_inner and inner.get("state") == "idle" and _first(row, "resource.ownershipState") == "external":
        live_inner = False
    if (outcome == "failed" or disp in ("failed", "circuit_broken") or worker == "failed") and not live_inner:
        return "failed", None
    if isinstance(wait, dict) and wait:
        low = json.dumps(wait).lower()
        kind = "permission" if any(w in low for w in ("permission", "trust", "approv")) else "question"
        return "input-required", {"kind": kind, "message": wait.get("prompt") or wait.get("text") or wait.get("evidence"),
                                  "since": _ms(wait.get("since") or wait.get("observedAt"))}
    if live_inner:
        return inner["state"], inner.get("attention")
    if verdict == "exited":
        return "failed", None   # proven gone with no settlement: no worker_done came
    if worker in ("pending", "starting", "launching", "created"):
        return "submitted", None
    return "working", None   # live, or unverifiable: absence is never a verdict (module docstring)


def _row_id(row):
    return _first(row, "dispatchId", "dispatch.id", "id")


def _wt_path(row, show=None):
    wid = _first(row, "resource.worktreeId", "projection.workspace.id") or _first(show or {}, "worker.worktreeId")
    return wid.split("::", 1)[1] if isinstance(wid, str) and "::" in wid else None


def _inner_index(ctx):
    """{(agent, realpath of cwd): that harness's live record} — one per directory; two sessions in
    one worktree are not guessed between (neither is used)."""
    out, seen = {}, set()
    for agent, name in _INNER.items():
        mod = ctx.adapter(name) if ctx is not None and hasattr(ctx, "adapter") else None
        if mod is None:
            continue
        try:
            recs = mod.sessions(ctx)
        except Exception as e:   # noqa: BLE001 — the other harness's failure only loses the join
            ctx.warn("%s: %s's sessions unread: %s" % (HARNESS, name, e))
            continue
        for r in recs:
            key = (agent, os.path.realpath(r.get("cwd") or "/nonexistent"))
            if key in seen:
                out.pop(key, None)
                continue
            seen.add(key)
            out[key] = r
    return out


def _record(ctx, row, show=None, inner_index=None):
    show = show or {}
    path = _wt_path(row, show)
    agent = _first(show, "worker.startOptions.agent", "worker.startOptions.launch.effective.agent")
    if inner_index is None:
        inner_index = {}
    inner = None
    for a in ([agent] if agent else list(_INNER)):
        inner = inner_index.get((a, os.path.realpath(path or "/nonexistent")))
        if inner:
            agent = agent or a
            break
    state, att = _state(row, show, inner)
    branch = _git(path, "symbolic-ref", "--short", "-q", "HEAD") if path and os.path.isdir(path) else None
    proj = row.get("projection") or {}
    eff = _first(show, "worker.startOptions.launch.effective") or {}
    term = row.get("agentTerminalHandle") or _first(show, "worker.agentTerminalHandle")
    native = {"run": row.get("runId"), "task": row.get("taskId"), "worker_state": row.get("workerState"),
              "dispatch_status": row.get("dispatchStatus"), "outcome": proj.get("outcome"),
              "stage": _first(proj, "stage.detail"), "liveness": _first(proj, "liveness.verdict"),
              "liveness_reason": _first(proj, "liveness.reason"), "terminal_state": row.get("terminalState"),
              "release_state": _first(row, "resource.releaseState"), "terminal": term, "agent": agent,
              "ownership": _first(row, "resource.ownershipState"),
              "agent_session": (inner or {}).get("session_id"),
              "next_action": " ".join(_first(proj, "nextAction.argv") or []) or None,
              "worktree_id": _first(row, "resource.worktreeId", "projection.workspace.id")}
    if state in _FINAL:
        native["end_reason"] = (_first(show, "dispatch.terminationReason") or _first(show, "dispatch.lastFailure")
                                or _first(proj, "stage.detail"))
        native["ended_at"] = _ms(_first(show, "dispatch.completedAt"))
    tail = (branch or "").rsplit("/", 1)[-1] or None
    return {"harness": HARNESS, "account": None, "session_id": _row_id(row), "machine": ctx.machine if ctx else None,
            "cwd": path, "branch": branch, "pid": (inner or {}).get("pid"),
            "started_at": _ms(_first(show, "dispatch.createdAt")) or (inner or {}).get("started_at"),
            "updated_at": _ms(_first(show, "worker.updatedAt")) or (inner or {}).get("updated_at"),
            "state": state, "attention": att,
            "model": eff.get("model") or (inner or {}).get("model"), "effort": eff.get("effort") or (inner or {}).get("effort"),
            "title": tail, "attach": "Orca app, worker %s" % _row_id(row) if state not in _FINAL else None,
            "native": {k: v for k, v in native.items() if v is not None}}


def _workers(ctx, run=None):
    """Every worker row Orca holds (all Runs unless RUN), following its pages; [] with no Orca.
    `--include-remote` adds the rows of a paired worker server (wharf-on-orca S3: a worker started
    `--on` a host is otherwise missing here and reads `unverifiable`); with no environment paired
    it lists the same rows (probed 2026-10-18, Orca 1.4.227)."""
    if not _bin() or not _app_up():
        return []
    out, cursor = [], None
    for _ in range(10):
        args = ["orchestration", "worker-list", "--include-remote", "--limit", "100"] + (["--run", run] if run else []) + (["--cursor", cursor] if cursor else [])
        res, err = _call(ctx, args)
        if err:
            if ctx is not None:
                ctx.warn("%s: %s" % (HARNESS, err))
            return out
        out.extend(r for r in (res or {}).get("workers") or [] if isinstance(r, dict))
        page = (res or {}).get("page") or {}
        cursor = page.get("nextCursor")
        if not page.get("hasMore") or not cursor:
            return out
    return out


def _show(ctx, did):
    res, err = _call(ctx, ["orchestration", "worker-show", "--dispatch", did])
    return res if isinstance(res, dict) else {}


# ---- the verbs -----------------------------------------------------------------------------

def _over(row):
    """Orca's own word that a worker is history: settled, or its terminal released."""
    return _state(row)[0] in _FINAL or row.get("terminalState") == "released"


def sessions(ctx):
    """V4: every worker that is not over. Orca's list is every Dispatch this runtime ever recorded,
    newest first, so the settled and released ones are dropped before anything else is read.
    With ctx.unsettled (`harness list --unsettled`, bin/stalls.py's read) the Dispatches that ended
    without completing — failed or canceled, released or not — stay in: a worker that exited with
    no worker_done is `failed` here (_state), and only the newest attempt of a Task tells whether
    someone retried or stopped it, which is the caller's to judge (orchestration B8)."""
    keep = getattr(ctx, "unsettled", False)
    rows = _workers(ctx)
    if not rows:
        return []
    idx = _inner_index(ctx)
    # a row Orca settled `failed` whose claude is still live stays in: _state() puts the session first
    alive = {os.path.realpath(r.get("cwd") or "/nonexistent") for r in idx.values()}
    rows = [r for r in rows if not _over(r) or (keep and _state(r)[0] != "completed")
            or (_state(r)[0] == "failed" and os.path.realpath(_wt_path(r) or "/nonexistent") in alive)]
    return [rec for rec in (_record(ctx, r, None, idx) for r in rows)
            if rec["state"] not in _FINAL or (keep and rec["state"] != "completed")]


# ---- what the tick reads beside the workers (bin/stalls.py, orchestration B8) ----------------
# Shapes: task-list rows as P3 printed them on 2026-10-15 (id, run_id, task_title, display_name,
# status, deps as a JSON string, created_at / completed_at "YYYY-MM-DD HH:MM:SS" UTC); check's
# message rows were not probed — the readers take the fields under every name Orca's guides use.

def tasks(ctx, run, ready=False):
    """[task row] of RUN (`task-list --run R [--ready]`), or None when Orca did not answer."""
    if not _bin() or not _app_up():
        return None
    res, err = _call(ctx, ["orchestration", "task-list", "--run", run] + (["--ready"] if ready else []))
    if err:
        if ctx is not None:
            ctx.warn("%s: %s" % (HARNESS, err))
        return None
    rows = (res or {}).get("tasks") if isinstance(res, dict) else res
    out = []
    for t in rows or []:
        if not isinstance(t, dict):
            continue
        deps = t.get("deps")
        if isinstance(deps, str):
            try:
                deps = json.loads(deps or "[]")
            except ValueError:
                deps = []
        out.append(dict(t, deps=deps if isinstance(deps, list) else [],
                        created=_ms(t.get("created_at") or t.get("createdAt")),
                        completed=_ms(t.get("completed_at") or t.get("completedAt"))))
    return out


def coordinator(ctx, run):
    """The Run's coordinator terminal handle (run-show), or None."""
    res, _ = _call(ctx, ["orchestration", "run-show", "--id", run])
    return _first(res or {}, "run.coordinator_handle", "run.coordinatorHandle")


def times(ctx, did):
    """{"started", "updated", "ended", "reason"} of one Dispatch from worker-show: a list row carries
    no time, and its termination reason (a worker_done's failure, a stop) only worker-show has."""
    show = _show(ctx, did)
    return {"started": _ms(_first(show, "dispatch.createdAt")), "updated": _ms(_first(show, "worker.updatedAt")),
            "ended": _ms(_first(show, "dispatch.completedAt")),
            "reason": _first(show, "dispatch.terminationReason", "dispatch.lastFailure")}


def questions(ctx, run, coord):
    """[{"id", "dispatch", "text", "since"}] of RUN's unread `question` messages, read with `check
    --peek` — never a consuming check, which a script must not make (Orca replays the batch until
    --ack, design Q2) — or None when Orca did not answer."""
    res, err = _call(ctx, ["orchestration", "check", "--terminal", coord, "--run", run, "--peek", "--types", "question"])
    if err:
        if ctx is not None:
            ctx.warn("%s: %s" % (HARNESS, err))
        return None
    rows = _first(res or {}, "messages", "delivery.messages", "rows") if isinstance(res, dict) else res
    out = []
    for m in rows or []:
        if not isinstance(m, dict) or str(m.get("type") or "question") != "question":
            continue
        # Orca's rows are its `messages` table (1.4.225 source, read 2026-10-16): the sender is
        # from_handle, `dispatch:<id>` for a worker; payload is a JSON string
        payload = m.get("payload")
        if isinstance(payload, str):
            try:
                payload = json.loads(payload)
            except ValueError:
                payload = None
        sender = str(m.get("from_handle") or m.get("fromHandle") or "")
        did = sender[len("dispatch:"):] if sender.startswith("dispatch:") else None
        did = did or _first(payload if isinstance(payload, dict) else {}, "dispatchId", "dispatch_id")
        text = _first(m, "body", "subject") or _first(payload if isinstance(payload, dict) else {}, "question") or ""
        out.append({"id": _first(m, "id", "message_id", "messageId"), "dispatch": did,
                    "handle": sender or None, "text": text if isinstance(text, str) else json.dumps(text),
                    "since": _ms(_first(m, "created_at", "createdAt"))})
    return [q for q in out if q["id"]]


def _matches(ref, rec):
    sid = rec.get("session_id") or ""
    if sid == ref or (len(ref) >= 6 and sid.startswith(ref)):
        return True
    names = (rec.get("title"), rec.get("branch"), (rec.get("branch") or "").rsplit("/", 1)[-1],
             re.sub(r"^\d{4}-\d{2}-\d{2}-", "", (rec.get("branch") or "").rsplit("/", 1)[-1]))
    return ref in names


def candidates(ctx, ref):
    """V3: the workers REF may mean — a dispatch id or a prefix of 6+, the task title, the branch,
    its last part or its topic — each read again with worker-show for the wait a list leaves out."""
    hits = [row for row in _workers(ctx) if ref and _matches(ref, _record(ctx, row))]
    idx = _inner_index(ctx) if any(not _over(r) for r in hits) else {}
    return [_record(ctx, row, _show(ctx, _row_id(row)) if _row_id(row) else None, idx) for row in hits]


def _one(ctx, did, run=None):
    """One dispatch's record, read fresh: its row, worker-show, and its agent's own session."""
    rows = [r for r in _workers(ctx, run) if _row_id(r) == did]
    if not rows:
        return None
    return _record(ctx, rows[0], _show(ctx, did), _inner_index(ctx))


def _last_text(ctx, did):
    """The worker's last assistant text, from worker-read (its transcript when Orca has one)."""
    res, _ = _call(ctx, ["orchestration", "worker-read", "--dispatch", did, "--limit", "40"])
    msgs = _first(res or {}, "transcript.messages") or []
    for m in reversed(msgs if isinstance(msgs, list) else []):
        if isinstance(m, dict) and m.get("role") == "assistant":
            said = "\n".join(b.get("text") or "" for b in m.get("blocks") or [] if isinstance(b, dict) and b.get("type") == "text").strip()
            if said:
                return said[-4000:]
    tail = _first(res or {}, "terminal.tail", "tail", "text")
    return tail[-4000:] if isinstance(tail, str) and tail else None


def _repo_id(ctx, repo):
    real = os.path.realpath(repo)
    res = _must(ctx, ["repo", "list"]) or {}
    for r in res.get("repos") or []:
        if os.path.realpath(r.get("path") or "") == real:
            return r["id"]
    got = _must(ctx, ["repo", "add", "--path", real]) or {}
    rid = _first(got, "repo.id", "id")
    if not rid:
        ctx.fail("orca repo add %s returned no id: %s" % (real, json.dumps(got)[:300]), 1)
    return rid


def start(ctx, req, where, run_id, coord, login, task=None, title=None, term_title=None, on=None):
    """worker-start in an existing Run, the one start bin/harness run and bin/wharf (B7) share:
    on a picked login in a terminal of ours (_login_terminal), else Orca's own launch of --agent
    with --model/--effort; on an existing Task (--task, wharf's compiled block) or a new one (--spec
    and --task-title, harness run's). WHERE is Orca's worktree selector (`id:<wt>`, or `path:<p>`
    for a worktree made our way, B6a's pick A). Returns (dispatch id, the start's result, own
    terminal or None), or (None, why, None) when Orca refused or failed — nothing of ours is left:
    a terminal we opened is closed. A ship's first start pins it to its login (`account ships --pin`).
    ON names a paired Orca environment (`worker-start --on`; the Run stays here): Orca's own launch
    only, as a terminal of ours is a terminal on this Mac, and WHERE must be a selector valid there
    (Orca refuses `current` and `new-child` remotely)."""
    agent = req.get("agent") or "claude"
    label, env = login
    own = _login_terminal(ctx, where, term_title or title or "worker", env, req) if label and not on else None
    args = ["orchestration", "worker-start"] + (["--task", task] if task else ["--spec", req["prompt"]]) \
        + (["--on", on] if on else []) + ["--worktree", where] + (["--terminal", own] if own else ["--agent", agent]) \
        + ["--run", run_id, "--from", coord] + ([] if task else ["--task-title", title])
    if own:
        res, err = _start_on(ctx, args)
    else:
        if req.get("model"):
            args += ["--model", req["model"]] + (["--effort", req["effort"]] if req.get("effort") else [])
        res, err = _call(ctx, args, timeout=300)
    did = None if err else _first(res or {}, "dispatch.id", "dispatchId", "worker.dispatchId", "id")
    if not did:
        if own:
            _close_own(ctx, own)
        return None, err or "orca worker-start returned no dispatch id: %s" % json.dumps(res)[:400], None
    if label and not on and req.get("ship") and req.get("account") == "auto":  # the ship stays on this login from now on
        tool = _account_tool(ctx)
        try:
            subprocess.run([tool, "ships", "--pin", req["ship"], label], capture_output=True, timeout=60)
        except (OSError, subprocess.TimeoutExpired):
            pass
    return did, res, own


def run(ctx, req):
    """V1 (module docstring, in order). The worktree is Orca's; the branch is Atlas's name for it."""
    agent = req.get("agent") or "claude"
    if agent not in AGENTS:
        ctx.fail("--agent takes %s (got %r)" % (" or ".join(AGENTS), agent), 2)
    if req.get("effort") and not req.get("model"):
        ctx.fail("Orca takes --effort only with --model (its worker-start rule)", 2)
    if req.get("branch") or req.get("on"):
        ctx.fail("orca run makes its own worktree: --name TOPIC and --repo, not --branch or --on", 2)
    topic = re.sub(r"^\d{4}-\d{2}-\d{2}-", "", re.sub(r"[^A-Za-z0-9-]+", "-", req.get("name") or "").strip("-").lower())
    if not topic or not req.get("prompt"):
        ctx.fail("orca run needs --name TOPIC and --prompt", 2)
    if not _bin() or not _app_up():
        ctx.fail("Orca is not running here (open the app, with ELECTRON_RUN_AS_NODE cleared from a VS Code session)", 2)
    name = "%s-%s" % (req.get("date") or time.strftime("%Y-%m-%d"), topic)
    want = "claude/%s/%s" % (ctx.machine, name)
    repo = req["repo"]
    login = _login(ctx, req, agent)   # before anything is made: a refusal leaves nothing behind (no pin either)
    if _git(repo, "show-ref", "--verify", "--quiet", "refs/heads/" + want) is not None:
        ctx.fail("%s already exists in %s: one branch per run — pick another --name" % (want, repo), 2)
    rid = _repo_id(ctx, repo)
    made = _must(ctx, ["worktree", "create", "--name", name, "--repo", rid, "--no-parent"], timeout=120) or {}
    wt = made.get("worktree") or {}
    path, wid = wt.get("path"), wt.get("id")
    if not path or not wid:
        ctx.fail("orca worktree create returned no worktree: %s" % json.dumps(made)[:300], 1)
    got = _git(path, "symbolic-ref", "--short", "-q", "HEAD")
    renamed = None
    if got != want:
        if _git(path, "branch", "-m", got or "HEAD", want) is None or _git(path, "symbolic-ref", "--short", "-q", "HEAD") != want:
            ctx.fail("Orca named the branch %s and it could not be renamed to %s; no agent started (worktree %s is left)"
                     % (got, want, path), 1)
        renamed = got
    terms = _must(ctx, ["terminal", "list", "--worktree", "id:" + wid]) or {}
    shells = [t for t in terms.get("terminals") or [] if isinstance(t, dict) and t.get("handle")]
    if not shells:
        ctx.fail("Orca opened no terminal in %s to coordinate from; no agent started" % path, 1)
    shell = shells[0]["handle"]
    runr = _must(ctx, ["orchestration", "run-create", "--objective", "%s (bin/harness run)" % want, "--from", shell]) or {}
    run_id = _first(runr, "run.id", "id", "runId")
    if not run_id:
        ctx.fail("orca run-create returned no run id: %s" % json.dumps(runr)[:300], 1)
    did, res, own = start(ctx, req, "id:" + wid, run_id, shell, login, title=want, term_title=name)
    if not did:
        ctx.fail("%s (worktree %s, branch %s, run %s are left)" % (res, path, want, run_id), 1)
    label = login[0]
    rec = _one(ctx, did, run_id) or {"harness": HARNESS, "account": None, "session_id": did, "machine": ctx.machine,
                                     "cwd": path, "branch": want, "pid": None, "started_at": None, "updated_at": None,
                                     "state": "submitted", "attention": None, "model": None, "effort": None,
                                     "title": name, "attach": None, "native": {}}
    rec["account"] = label or rec.get("account")
    rec["native"].update({"orca_run": run_id, "coordinator": shell, "worktree_id": wid, "agent": agent,
                          "renamed_from": renamed, "own_terminal": own,
                          "start": _first(res or {}, "stage", "worker.stage", "status")})
    rec["native"] = {k: v for k, v in rec["native"].items() if v is not None}
    return rec


def resume(ctx, rec, req):
    """V2: the next turn, by the way Orca takes it. A terminal worker (`term_…`): typed into its
    terminal, `terminal send --enter`. A chat worker (`structworker_…`, Orca's default for new agent
    tabs): `terminal send` refuses it (terminal_unsupported_for_agent_session, 2026-10-14, whose
    message names the route), so `orchestration send --to dispatch:<id>` from the Run's coordinator.
    No fork in Orca; a released worker has nothing left to take a turn: a fresh run then."""
    if req.get("fork"):
        ctx.fail("Orca has no fork: `harness run --harness orca` starts a fresh worker", 2)
    native, did = rec.get("native") or {}, rec.get("session_id")
    term = native.get("terminal")
    if not term or native.get("terminal_state") == "released":
        ctx.fail("%s has no terminal left (released): start a fresh run" % did, 2)
    if term.startswith("term_"):
        res = _must(ctx, ["terminal", "send", "--terminal", term, "--text", req["prompt"], "--enter", "--wait-submit", "10"], timeout=60)
        how = "terminal send: %s" % (_first(res or {}, "submission.state", "submission.status", "status") or "accepted")
    else:
        runr = _must(ctx, ["orchestration", "run-show", "--id", native.get("run") or ""]) or {}
        coord = _first(runr, "run.coordinator_handle")
        if not coord:
            ctx.fail("run %s names no coordinator to send from" % native.get("run"), 1)
        res = _must(ctx, ["orchestration", "send", "--to", "dispatch:" + did, "--from", coord, "--subject", "bin/harness resume",
                          "--body", req["prompt"], "--type", "dispatch"], timeout=60)
        how = "orchestration send: message %s" % (_first(res or {}, "message.id", "messageId", "id") or "queued")
    out = _one(ctx, did) or rec
    out["native"]["sent"] = how
    return out


def retry(ctx, rec, req):
    """A fresh attempt at a failed Dispatch's Task, placement repeated (it is never inherited: the
    same worktree, agent, model and effort), from the Run's coordinator; the Task's spec is Orca's
    already. Which start, by Orca's own rules (1.4.225 source, read 2026-10-16): a worker's exit
    fails its Dispatch and puts the Task back to `ready`, which takes a plain `worker-start --task`;
    a `failed` or `blocked` Task takes `--retry-of <its latest settled Dispatch>`. Only a failed
    attempt — a live, completed or stopped one is refused (exit 2), as is a circuit-broken one:
    Orca's breaker fails the Task after three failures in a row and the tick's two retries stop
    before it (R4). bin/stalls_tick.py's S1 retry (B8)."""
    native, did = rec.get("native") or {}, rec.get("session_id")
    if rec.get("state") != "failed":
        ctx.fail("%s is %s: only a failed attempt is retried" % (did, rec.get("state")), 2)
    if foreign_terminal(native):   # before the agent check: such a start names none
        ctx.fail("%s ran in a terminal Orca did not launch (a picked login): a retry would run on the login "
                 "Orca holds — start a fresh run with --account" % did, 2)
    task, run, wid = native.get("task"), native.get("run"), native.get("worktree_id")
    agent = native.get("agent") or req.get("agent")
    if not (task and run and wid and agent):
        ctx.fail("%s names no task, run, worktree or agent to retry with: %s" % (
            did, json.dumps({k: native.get(k) for k in ("task", "run", "worktree_id", "agent")})), 1)
    if native.get("dispatch_status") == "circuit_broken":
        ctx.fail("%s is circuit-broken: Orca failed its Task after three failures in a row" % did, 2)
    tk = next((t for t in tasks(ctx, run) or [] if t.get("id") == task), None)
    if tk is None:
        ctx.fail("task %s of run %s is not in Orca's task-list" % (task, run), 1)
    if tk.get("status") == "ready":
        again = []                       # Orca reopened it after the worker exited
    elif tk.get("status") in ("failed", "blocked"):
        again = ["--retry-of", did]
    else:
        ctx.fail("task %s is %s: Orca starts only a ready Task, or retries a failed or blocked one" % (task, tk.get("status")), 2)
    coord = coordinator(ctx, run)
    if not coord:
        ctx.fail("run %s names no coordinator to start the retry from" % run, 1)
    args = ["orchestration", "worker-start", "--task", task] + again + ["--worktree", "id:" + wid,
            "--agent", agent, "--run", run, "--from", coord]
    model = req.get("model") or rec.get("model")
    if model:
        effort = req.get("effort") or rec.get("effort")
        args += ["--model", model] + (["--effort", effort] if effort else [])
    res, err = _call(ctx, args, timeout=300)
    if err:
        ctx.fail("%s (task %s, retry of %s)" % (err, task, did), 1)
    new = _first(res or {}, "dispatch.id", "dispatchId", "worker.dispatchId", "id")
    if not new:
        ctx.fail("orca worker-start --retry-of returned no dispatch id: %s" % json.dumps(res)[:400], 1)
    out = _one(ctx, new, run) or {"harness": HARNESS, "account": None, "session_id": new, "machine": ctx.machine,
                                  "cwd": rec.get("cwd"), "branch": rec.get("branch"), "pid": None, "started_at": None,
                                  "updated_at": None, "state": "submitted", "attention": None, "model": model,
                                  "effort": None, "title": rec.get("title"), "attach": None, "native": {}}
    out["native"].update({"retry_of": did, "run": run, "task": task, "start": "--retry-of" if again else "a ready Task"})
    return out


def stop(ctx, rec):
    """V5: worker-stop (closes only its own agent terminal); a settled worker is released instead.
    The worktree and its branch stay: removing either is never this verb's."""
    did = rec.get("session_id")
    if not did:
        ctx.fail("no dispatch id to stop", 2)
    done = []
    if rec.get("state") not in _FINAL:
        _must(ctx, ["orchestration", "worker-stop", "--dispatch", did], timeout=120)
        done.append("worker-stop")
        rec = _one(ctx, did) or rec
    # A stopped worker still owns its agent terminal; Orca's own nextAction then names its release
    # (worker-release closes only that terminal and archives the output). Only that exact argv.
    if (rec.get("native") or {}).get("next_action") == "orchestration worker-release --dispatch %s" % did \
            or (not done and rec.get("native", {}).get("terminal_state") not in ("released", None)):
        res, err = _call(ctx, ["orchestration", "worker-release", "--dispatch", did], timeout=120)
        done.append("worker-release" + (" (%s)" % err if err else ""))
    nat = rec.get("native") or {}
    own = nat.get("own_terminal") or nat.get("terminal")
    if own and own in _own():  # one this adapter started: Orca retains it on release (`external_terminal`)
        err = _close_own(ctx, own)
        done.append("terminal close" + (" (%s)" % err if err else ""))
    out = _one(ctx, did) or rec
    out["native"]["stopped_by"] = ", ".join(done) or "nothing: already over and released"
    out["last_message"] = _last_text(ctx, did)
    return out


def send(ctx, rec, msg):
    """bin/hail's Orca road, by the way Orca takes a worker's next input (resume()'s two routes). A chat
    worker: `orchestration send --to dispatch:<id>` from the Run's coordinator, a mailbox the worker
    polls — whether it reaches a worker between turns is not probed (the design's Not verified), so
    `queued`. A terminal worker: `terminal send --enter` types into it, so only an idle one; a busy
    one is refused, as the socket road refuses. A released worker has nothing left to read it."""
    native, did = rec.get("native") or {}, rec.get("session_id")
    term = native.get("terminal")
    if not did or not term or native.get("terminal_state") == "released" or rec.get("state") in _FINAL:
        return {"verdict": "unreachable", "why": "%s has no worker left to read it" % (did or "the record")}
    if term.startswith("term_"):
        if rec.get("state") != "idle":
            return {"verdict": "refused", "why": "%s is %s: typing into its terminal would land mid-turn" % (did, rec.get("state"))}
        quiet = time.time() - rec["updated_at"] if rec.get("updated_at") else 0
        if quiet < msg.get("idle_s", 0):   # the socket road's F11 guard: idle a moment ago is a turn boundary
            return {"verdict": "refused", "why": "%s has been idle %d s, under %d s" % (did, quiet, msg.get("idle_s", 0))}
        if msg.get("dry"):
            return {"verdict": "dry-run", "why": "would type into terminal %s" % term}
        res, err = _call(ctx, ["terminal", "send", "--terminal", term, "--text", msg["frame"], "--enter", "--wait-submit", "10"])
        if err:
            return {"verdict": "unreachable", "why": err}
        return {"verdict": "queued", "why": "terminal send: %s" % (_first(res or {}, "submission.state", "submission.status", "status") or "accepted")}
    runr, err = _call(ctx, ["orchestration", "run-show", "--id", native.get("run") or ""])
    coord = _first(runr or {}, "run.coordinator_handle", "run.coordinatorHandle")
    if not coord:
        return {"verdict": "unreachable", "why": err or "run %s names no coordinator to send from" % native.get("run")}
    if msg.get("dry"):
        return {"verdict": "dry-run", "why": "would send to dispatch:%s from %s" % (did, coord)}
    # the one send shape probed (resume()'s, 2026-10-14)
    res, err = _call(ctx, ["orchestration", "send", "--to", "dispatch:" + did, "--from", coord,
                           "--subject", "hail %s" % (msg.get("kind") or "event"), "--body", msg["frame"], "--type", "dispatch"])
    if err:
        return {"verdict": "unreachable", "why": err}
    return {"verdict": "queued", "why": "orchestration send: message %s" % (_first(res or {}, "message.id", "messageId", "id") or "queued")}
