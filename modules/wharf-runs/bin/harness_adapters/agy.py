"""The Antigravity adapter: Google's agy CLI behind the harness contract (docs/harness-contract-2026-10-11.md
section 3), the start road `dispatch BRANCH --harness agy` takes (agy-road, 2026-11-04; the owner: "let's sign in
agy there, too, let it run agy builds"). Ported from the stranded agy-machines-port branch (its
harness_adapters/antigravity.py, 2026-10-17/21, agy 1.4.2), less what main has since replaced: the overlay's
permission project (agy's own hooks.json now carries the guards, lighthouse's vendor-hooks) and the e-mail
binding (an Antigravity row of bin/account stands for whichever login this host's agy holds, agy-tenant).

agy keeps no live registry we can read, so the contract's wrapper shim, as codex.py has it: V1 runs agy in print
mode under a wrapper process this file forks off, detached (double fork, setsid), which owns the agy pid and
writes the run's record from the stream-json events. V3/V5 answer from that record; V4 is the directory of
records whose agy still runs. A conversation agy ran itself (its TUI, Orca) is not listed.

    HARNESS_RUNS_DIR (default: Library/Logs/claude-weekly/harness-runs/ in the home folder, on Linux too: dispatch-rc reads it)
        agy-<stamp>-<name>-<id>.json      the record: run, thread (agy's conversation id), pid, proc_start, cwd,
                                          branch, repo, model, effort, account, seen, sent, started, ended, exit,
                                          status, end_reason, last_message, turns, denied_actions, usage, mode,
                                          dispatched — the wrapper its only writer once agy runs
        agy-<stamp>-<name>-<id>.jsonl     agy's own events, as printed
        agy-<stamp>-<name>-<id>.log       its stderr
        agy-<stamp>-<name>-<id>.agy.log   agy's own log (--log-file): the identity line
        agy-<stamp>-<name>-<id>.stop      `harness stop`'s reason, read by the wrapper at the end
    <id>: six hex characters, the .json made exclusively, so two starts in one second never collide.

The command, every time: `agy --input-format stream-json --output-format stream-json --mode MODE --sandbox
--log-file <run>.agy.log [--model M] [--effort E] [--conversation <id>] -p=` in the worktree, with CLAUDECODE,
CLAUDE_CONFIG_DIR and CLAUDE_CODE_SESSION_ID unset (an agy worker is no Claude Code session) and PLAN_HARNESS=agy.
`-p` takes a value (1.4.2: "-p took "--input-format" as its prompt"), so `-p=` gives it an empty one and the
prompt arrives as one NDJSON line on stdin, `{"event": "user", "message": {"role": "user", "content": PROMPT}}`:
a prompt is never parsed as a flag, and never cut as `-p TEXT` is (at about 187 KB, without an error: the
brief's trap). A prompt over PROMPT_CAP bytes is refused all the same: a run hands agy its brief by path, as
dispatch's prompt does. Closing stdin ends the run after that turn.

Seen in four model runs on 1.4.2 (2026-10-17, a scratch repo, the owner's own login), the branch's probes:
- events: `init` (conversation_id, model, cwd, tools, permission_mode) first, before any input is read, and by
  then agy's log carries `OAuth: authenticated successfully as <email>`; then `step_update` (step_type
  user_input | agent_response | tool | system_message, state ACTIVE | DONE, text_delta on agent_response), last
  `result` (status SUCCESS | ERROR, response, error, num_turns, usage, denied_actions).
- resume: `--conversation <id>` continues it under the same id; agy has no fork, so --fork is refused.
- SIGTERM mid-turn: agy exits 1 after a `result` with status ERROR, error "interrupted".
- exit codes (agy's changelog): 0 done, 1 error or interrupted, 2 usage error, 3 a model or agent API failure.

What bounds an unattended agy run, each checked before agy starts (exit 2, nothing started):
- bin/harness's guard(): the contract's `physical: none`, the public-repo rule Codex meets (a plan login stays
  out of scripts in a public repo), the core's vendor_refusal (a confidential or guarded repo only on a login its
  tenant owns, `account pick --provider antigravity`), the spawn gate, the depth cap and the run cap.
- this file: a `.claude/worktrees/` worktree on a claude/* branch, never a primary checkout, never main
  (_worktree); `account pick --provider antigravity --repo <checkout>` naming a login (_pick; an e-mail it names
  is checked against agy's log before the prompt goes in, nothing sent otherwise — inert today, as no Antigravity
  row names one); agy's hooks.json carrying the
  guards entry vendor-hooks writes, enabled (_guards_why: checkpoint and the secrets guard on every tool call);
  an agy whose --help lists --sandbox (sandbox_flag).
- MODE: `accept-edits` (edits, every shell command soft-denied: the branch's probe, `ls` included), unless
  `<config>/wharf-runs/agy-mode` says `auto` (agy's edits-and-safe-commands mode; "not available for this
  account" on the owner's login in 1.4.2). Never `--dangerously-skip-permissions`: whether an unattended agy build
  may run commands is the owner's call (TODO.md [agy-mode]). `--sandbox` keeps a command off files outside the workspace while the model does not ask to leave it,
  and git does not run inside it in a linked worktree (its git dir lies outside): the branch's probes.

The run record's `dispatched` is HARNESS_DISPATCHED (dispatch's run record, which counts the run's slot);
harness_live() leaves such a run out, so dispatch-rc's count holds each run once.

Python 3.9, stdlib only.
"""
import json
import os
import re
import shlex
import shutil
import signal
import subprocess
import threading
import time
import uuid

HARNESS = "agy"
NAME = HARNESS
VENDOR = "antigravity"   # bin/account's provider word, and the vendor fence's
_FINAL = ("completed", "failed", "canceled")
TEXT_CAP = 4000
PROMPT_CAP = 160 * 1024   # bytes: under the ~187 KB where `agy -p` cut a prompt without a word (the brief's trap)
MODES = ("accept-edits", "auto")
WHO = re.compile(r"OAuth: authenticated successfully as (\S+)")


def _home():
    return os.environ.get("HOME") or os.path.expanduser("~")


def _runs_dir():
    return os.environ.get("HARNESS_RUNS_DIR") or os.path.join(_home(), "Library", "Logs", "claude-weekly", "harness-runs")


def exe():
    """The agy a run starts and sandbox_flag() asks: HARNESS_AGY (a suite's stand-in), else .local/bin/agy in the home folder, where
    Google's installer puts it on Linux and the Macs alike, when it is an executable file, else PATH's — one binary
    for both, so the one checked is the one run. None when there is none: dispatch-queue's `agy` need asks this."""
    if os.environ.get("HARNESS_AGY"):
        return os.environ["HARNESS_AGY"]
    local = os.path.join(_home(), ".local", "bin", "agy")
    if os.path.isfile(local) and os.access(local, os.X_OK):
        return local
    return shutil.which("agy")


def _account_tool(ctx):
    """bin/account: HARNESS_ACCOUNT (tests), else the core's tool() — lighthouse's, which bin/harness put on the path."""
    if os.environ.get("HARNESS_ACCOUNT"):
        return os.environ["HARNESS_ACCOUNT"]
    try:
        import common
        found = common.tool("account")
        if found:
            return str(found)
    except Exception:   # noqa: BLE001 — no core: no account, which the pick reports
        pass
    return None


def _wait(name, default):
    try:
        return float(os.environ.get(name) or default)
    except ValueError:
        return float(default)


def _config_first(key):
    try:
        import common
        return ((common.config_lines(key) or [""])[0] or "").strip()
    except Exception:   # noqa: BLE001 — a reader that cannot be used is no key
        return ""


def mode():
    """(mode, None) or (None, why): `wharf-runs/agy-mode`'s first line, `accept-edits` when absent."""
    m = _config_first("wharf-runs/agy-mode") or "accept-edits"
    return (m, None) if m in MODES else (None, "wharf-runs/agy-mode says %r, not one of %s" % (m, ", ".join(MODES)))


def sandbox_flag(agy=None):
    """None when this agy's --help lists --sandbox, else why not (the run refuses without it)."""
    agy = agy or exe()
    if not agy:
        return "no agy here (.local/bin/agy in the home folder, PATH)"
    try:
        r = subprocess.run([agy, "--help"], capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.TimeoutExpired) as e:
        return "%s --help did not run (%s)" % (agy, e)
    if "--sandbox" not in (r.stdout or "") + (r.stderr or ""):
        return "%s --help lists no --sandbox" % agy
    return None


def _gemini():
    return os.environ.get("GEMINI_CLI_HOME") or os.path.join(_home(), ".gemini")


def _guards_why():
    """None when agy's hooks.json (`<GEMINI_CLI_HOME, else .gemini in the home folder>/config/hooks.json`) holds vendor-hooks' `regatta`
    entry, enabled, with a PreToolUse handler running vendor_hook.py's guards; else why not. Fails closed: a file
    that does not read is no entry. The shape is vendor-hooks' plan_ag()."""
    path = os.path.join(_gemini(), "config", "hooks.json")
    try:
        with open(path) as f:
            cfg = json.load(f)
    except (OSError, ValueError) as e:
        return "agy's %s does not read (%s): no guards run on its tool calls — lighthouse's `vendor-hooks apply`" % (path, type(e).__name__)
    entry = cfg.get("regatta") if isinstance(cfg, dict) else None
    if not isinstance(entry, dict):
        return "agy's %s holds no regatta guards entry — lighthouse's `vendor-hooks apply`" % path
    if entry.get("enabled") is False:
        return "agy's regatta guards entry in %s is disabled (`enabled: false`): no unattended agy run without it" % path
    # a group whose matcher narrows it guards only those tools: only every tool's ("*", vendor-hooks' plan_ag) counts,
    # or a hooks.json edited to `"matcher": "run_command"` would pass while edits ran unguarded (the finish review)
    cmds = [h.get("command") or "" for g in entry.get("PreToolUse") or [] if isinstance(g, dict)
            and g.get("matcher", "*") in ("*", "", ".*") for h in g.get("hooks") or [] if isinstance(h, dict)]
    cmds = [c for c in cmds if isinstance(c, str) and "vendor_hook.py" in c and "guards" in c]
    if not cmds:
        return "agy's regatta entry in %s runs no vendor_hook.py guards — lighthouse's `vendor-hooks apply`" % path
    # the hook it names must be there: vendor-hooks' launcher answers `{}` when vendor_hook.py is gone (a deny on agy
    # 1.5.2, an allow on an agy that reads it as carry-on), so an entry naming a moved checkout's path runs no guard (the build review, 2026-11-05)
    gone = []
    for c in cmds:
        try:
            words = shlex.split(c)
        except ValueError:
            return "agy's regatta guards command in %s does not read as a command line — lighthouse's `vendor-hooks apply`" % path
        hooks = [w for w in words if w.endswith("/hooks/vendor_hook.py")]
        if not hooks:
            return "agy's regatta guards command in %s names no vendor_hook.py path — lighthouse's `vendor-hooks apply`" % path
        gone += [w for w in hooks if not os.path.isfile(w)]
    if gone:
        return ("agy's regatta guards entry in %s names %s, which is gone: no guard would run on its tool calls — "
                "lighthouse's `vendor-hooks apply`" % (path, gone[0]))
    return None


# ---- the record on disk ----------------------------------------------------------------------

def _load(path):
    try:
        with open(path) as f:
            d = json.load(f)
        return d if isinstance(d, dict) else None
    except (OSError, ValueError):
        return None


def _save(path, rec):
    tmp = "%s.%d.tmp" % (path, os.getpid())   # the wrapper and `harness stop` both write it
    with open(tmp, "w") as f:
        json.dump(rec, f, indent=1)
    os.replace(tmp, path)


_LOCK = threading.RLock()   # the wrapper's loop and its init watchdog both write the record


def _update(path, **kw):
    with _LOCK:
        rec = _load(path) or {}
        rec.update(kw)
        _save(path, rec)
        return rec


def _pstart(pid):
    """`ps -o lstart=` of PID, read up to three times (dispatch's pstart: a fresh child may not show yet)."""
    for i in range(3):
        try:
            r = subprocess.run(["ps", "-o", "lstart=", "-p", str(pid)], capture_output=True, text=True, timeout=5,
                               env=dict(os.environ, TZ="UTC", LC_ALL="C"))
            got = " ".join(r.stdout.split())
        except (OSError, subprocess.TimeoutExpired):
            got = ""
        if got:
            return got
        if i < 2:
            time.sleep(0.5)
    return None


def _running(rec):
    pid = rec.get("pid")
    if not isinstance(pid, int) or isinstance(pid, bool):
        return False
    try:
        os.kill(pid, 0)
    except PermissionError:
        pass
    except OSError:
        return False
    if not rec.get("proc_start"):
        return True
    cur = _pstart(pid)
    # a `ps` that prints nothing (a loaded Mac) reads as the same process, as dispatch-rc's running() reads it:
    # read as gone, a live agy's record would end with nobody watching it (the finish review, 2026-11-05)
    return cur is None or cur == rec["proc_start"]


def _git(cwd, *argv):
    try:
        r = subprocess.run(["git", "-C", cwd] + list(argv), capture_output=True, text=True, timeout=20)
    except (OSError, subprocess.TimeoutExpired):
        return None
    return r.stdout.strip() if r.returncode == 0 else None


def _records():
    d = _runs_dir()
    try:
        names = sorted(n for n in os.listdir(d) if n.startswith(HARNESS + "-") and n.endswith(".json"))
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
    if rec.get("exit") == 0 and rec.get("status") in (None, "SUCCESS"):
        return "completed"
    if rec.get("exit") in (130, 143, -2, -15):
        return "canceled"
    return "failed"


def _run_record(ctx, path, rec):
    live = not rec.get("ended") and _running(rec)
    if live:
        state = "working" if rec.get("thread") else "submitted"
    elif rec.get("ended"):
        state = _end_state(rec)
    elif rec.get("pid") is None and time.time() - (rec.get("started") or 0) < 60:
        state = "submitted"   # the wrapper has not started agy yet
    else:
        state = "failed"   # its wrapper and agy are gone and nobody wrote an end
    native = {"source": "harness run", "run": path, "run_id": rec.get("run"), "events": rec.get("events"),
              "agent": "agy", "turns": rec.get("turns"), "resumed_from": rec.get("resumed_from"),
              "error": rec.get("error"), "topic": rec.get("name"), "repo": rec.get("repo"), "exit": rec.get("exit"),
              "native_login": rec.get("seen"), "denied_actions": rec.get("denied_actions") or None,
              "agy_log": rec.get("agy_log"), "mode": rec.get("mode"), "sandbox": rec.get("sandbox"),
              "dispatched": rec.get("dispatched"), "usage": rec.get("usage"),
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
    """V4: harness runs whose agy still runs."""
    out = []
    for path, rec in _records():
        r = _run_record(ctx, path, rec)
        if r["state"] not in _FINAL:
            out.append(r)
    return out


def harness_live(ctx):
    """[record] of the live runs dispatch-rc's run count holds (vendor-fence, F6): V4 less a run dispatch started,
    whose own run record holds its slot (`dispatched`) — only while that record does: one that is gone, does not read
    or has ended (dispatch gave up on an agy whose stop failed) no longer counts it, so this count does (the finish
    review, 2026-11-05)."""
    return [r for r in sessions(ctx) if not _held_by_dispatch((r.get("native") or {}).get("dispatched"))]


def _held_by_dispatch(path):
    """True while PATH, a dispatch run record, is there, reads and has not ended: that record holds the run's slot."""
    if not path or not isinstance(path, str):
        return False
    try:
        with open(path) as f:
            st = json.load(f)
    except (OSError, ValueError):
        return False
    return isinstance(st, dict) and not st.get("ended")


def _matches(ref, *ids):
    return any(i and (i == ref or (len(ref) >= 6 and str(i).startswith(ref))) for i in ids)


def candidates(ctx, ref):
    """V3: every run REF may mean — a conversation id or a prefix of 6+, a run id, a run's name."""
    if not ref:
        return []
    return [_run_record(ctx, p, rec) for p, rec in _records()
            if _matches(ref, rec.get("thread"), rec.get("run")) or ref == rec.get("name")]


# ---- V1, V2, V5 ----------------------------------------------------------------------------

def _worktree(ctx, cwd):
    """(branch, the worktree's top), or a refusal: a run writes only in a linked `.claude/worktrees/` worktree on a
    claude/* branch — never a primary checkout, never main."""
    branch = _git(cwd, "symbolic-ref", "--short", "-q", "HEAD")
    if not (branch or "").startswith("claude/"):
        ctx.fail("%s is on %s, not a claude/* branch: an agy run writes in a worktree of its own" % (cwd, branch or "no branch"), 2)
    top = _git(cwd, "rev-parse", "--show-toplevel")
    gd, cd = _git(cwd, "rev-parse", "--git-dir"), _git(cwd, "rev-parse", "--git-common-dir")
    if not (top and gd and cd):
        ctx.fail("%s: git could not say which checkout this is" % cwd, 2)

    def real(p):
        return os.path.realpath(os.path.join(cwd, p))
    if real(gd) == real(cd):
        ctx.fail("%s is the repo's primary checkout (on %s): an agy run writes only in a .claude/worktrees/ worktree" % (top, branch), 2)
    if "/.claude/worktrees/" not in real(top) + "/":
        ctx.fail("%s is a worktree outside .claude/worktrees/: an agy run writes only in one of those" % top, 2)
    return branch, real(top)


def _pick(ctx, req, cwd):
    """(label, e-mail or None) of the agy login bin/account picks for this repo; none → refused. The pick's own
    rules decide (a row's allow and deny lists, a tenant's logins, the vendor fence's `owns`)."""
    acct = _account_tool(ctx)
    if not acct:
        ctx.fail("bin/account is not here to name an Antigravity login: nothing started", 2)
    argv = [acct, "pick", "--provider", VENDOR, "--repo", req.get("repo") or cwd, "--json"]   # the checkout the fence judged
    try:
        r = subprocess.run(argv, capture_output=True, text=True, timeout=120)
        d = json.loads(r.stdout) if r.stdout.strip() else None
    except (OSError, ValueError, subprocess.TimeoutExpired) as e:
        ctx.fail("account pick --provider %s did not answer (%s): nothing started" % (VENDOR, type(e).__name__), 2)
    if not isinstance(d, dict) or not d.get("account"):
        skipped = (d or {}).get("skipped") if isinstance(d, dict) else None
        why = "; ".join("%s: %s" % tuple(x[:2]) for x in skipped or [] if isinstance(x, list) and len(x) >= 2) \
            or (r.stderr or "").strip()[:300]
        ctx.fail("no Antigravity login may run it (%s)" % (why or "account pick exit %d" % r.returncode), 2)
    if d.get("provider") not in (None, VENDOR):
        ctx.fail("account pick gave %s, a %s login, not an Antigravity one" % (d["account"], d.get("provider")), 2)
    why = _fenced_why(req.get("repo") or cwd)
    if why and d.get("owns") is not True:
        # the fence judged the cached pick; this live one may name another row (the first out of room), so it is held
        # to the same rule: a fenced repo's text goes only to a login its tenant owns (the finish review, 2026-11-05)
        ctx.fail("%s: its text goes only to a login its tenant owns, and the live pick names %s, not one: nothing started"
                 % (why, d["account"]), 2)
    return d["account"], d.get("email") or None


def _fenced_why(repo):
    """Why REPO is fenced (`<key> is guarded` …), or None for an open one, by the core harness loaded. No core, or a
    registry that does not read or walk: fenced, as vendor_refusal fails closed."""
    import sys
    core = sys.modules.get("common")
    if core is None or not hasattr(core, "fenced_scopes"):
        return "the regatta core is not here to judge %s" % repo
    try:
        reg, torn = core.read_registry()
        if torn:
            return "the scope registry does not read"
        fenced = core.fenced_scopes(repo, reg or {})
    except Exception as e:   # noqa: BLE001 — a registry it cannot walk is never known open
        return "the scope registry does not walk (%s)" % type(e).__name__
    # the core's own words (vendor_refusal's): dispatch's agy road reads "in confidential scope" as refused for good
    return "%s is %s" % (repo, " and ".join("guarded" if n == "guarded" else "in confidential scope " + n
                                           for n in fenced)) if fenced else None


def _argv(req, log, run_mode, conversation=None, add_dirs=()):
    argv = [exe(), "--input-format", "stream-json", "--output-format", "stream-json"]
    # A dispatched build must run shell tools headlessly. The interactive harness
    # retains its configured mode; a builder uses the explicit permission flag.
    argv += ["--mode", run_mode] if run_mode else ["--dangerously-skip-permissions", "--print-timeout", "0"]
    argv += ["--sandbox", "--log-file", log]
    for directory in add_dirs:
        argv += ["--add-dir", str(directory)]
    if req.get("model"):
        argv += ["--model", req["model"]]
    if req.get("effort"):
        argv += ["--effort", req["effort"]]
    if conversation:
        argv += ["--conversation", conversation]
    return argv + ["-p="]


def _who(log, wait):
    """The e-mail agy's log says it authenticated as, polled up to `wait` s (it is there by init)."""
    end = time.time() + wait
    while True:
        try:
            with open(log, errors="replace") as f:
                found = WHO.findall(f.read())
        except OSError:
            found = []
        if found or time.time() >= end:
            return found[-1] if found else None
        time.sleep(0.2)


def _init_wait():
    """How long agy has to print its `init` (HARNESS_AGY_INIT_WAIT, default 60 s); without one the run is killed."""
    return _wait("HARNESS_AGY_INIT_WAIT", 60)


def _child_env():
    env = {k: v for k, v in os.environ.items() if k not in ("CLAUDECODE", "CLAUDE_CONFIG_DIR", "CLAUDE_CODE_SESSION_ID",
                                                            "HARNESS_DISPATCHED")}
    env["PLAN_HARNESS"] = "agy"
    # one deeper than its caller, as codex.py's child_env counts: a dispatch from inside agy is the chain's next step
    d = env.get("DISPATCH_DEPTH") or "0"
    env["DISPATCH_DEPTH"] = str((int(d) if d.isdigit() else 0) + 1)
    return env


def _wrap(path, argv, prompt, cwd):
    """The wrapper, in the detached grandchild: _wrap_run, and an end written whatever it raised (a byte agy printed
    that is no UTF-8 once ended the loop with no end, and dispatch polled a dead run: agy-road's round 1)."""
    try:
        _wrap_run(path, argv, prompt, cwd)
    except BaseException as e:   # noqa: BLE001 — the grandchild has nobody to tell but its record
        cur = _load(path) or {}
        if not cur.get("ended"):
            pid = cur.get("pid")
            if _running(cur):
                try:
                    os.kill(pid, signal.SIGTERM)
                except OSError:
                    pass
            why = "the wrapper failed (%s: %s): agy ended" % (type(e).__name__, str(e)[:200])
            _update(path, ended=time.time(), exit=cur.get("exit") if cur.get("exit") is not None else 1, status="ERROR",
                    error=why, end_reason=why)
        raise


def _wrap_run(path, argv, prompt, cwd):
    """agy as the wrapper's child; the prompt goes in once agy's init came (and, when the pick named an e-mail, once
    agy's log names it); the record kept from the stream. An agy that prints no `init` within _init_wait() is
    killed and the run ended failed with that reason."""
    rec = _load(path) or {}
    events = open(rec["events"], "a")
    err = open(rec["log"], "a")
    try:
        p = subprocess.Popen(argv, cwd=cwd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=err, text=True,
                             encoding="utf-8", errors="replace", env=_child_env())
    except OSError as e:
        _update(path, ended=time.time(), exit=127, end_reason="could not start %s: %s" % (argv[0], e))
        return
    # the wrapper's start beside its pid: dispatch's poll judges it as agy's, so a reused pid never keeps it alive
    _update(path, pid=p.pid, proc_start=_pstart(p.pid), wrapper=os.getpid(), wrapper_start=_pstart(os.getpid()))
    late, inited = [], []
    gate = threading.Lock()

    def no_init():
        with gate:   # init seen first: the prompt is the read loop's, and no kill follows (the finish review)
            if inited:
                return
            late.append(True)
            try:
                p.kill()
            except OSError:
                pass
    watchdog = threading.Timer(_init_wait(), no_init)
    watchdog.daemon = True
    watchdog.start()
    text, turns = "", 0
    for line in p.stdout:
        events.write(line)
        events.flush()
        try:
            e = json.loads(line)
        except ValueError:
            continue
        ev = e.get("event") if isinstance(e, dict) else None
        if ev == "init":
            with gate:
                watchdog.cancel()
                inited.append(True)
                killed = bool(late)
            if killed:   # killed already: no prompt goes to a process past its deadline
                continue
            want = rec.get("email") or ""
            seen = _who(rec["agy_log"], _wait("HARNESS_AGY_WHO_WAIT", 5) if want else 0)
            _update(path, thread=e.get("conversation_id"), seen=seen, updated=time.time())
            if want and (seen or "").lower() != want.lower():
                # nothing sent: no turn runs, nobody's quota is spent; the run ends here
                _update(path, refused=True, ending="the native agy login is %s, not %s, the login account pick "
                        "named: nothing sent" % (seen or "unknown", want))
                try:
                    p.stdin.close()
                except OSError:
                    pass
                p.terminate()
                continue
            try:
                p.stdin.write(json.dumps({"event": "user", "message": {"role": "user", "content": prompt}}) + "\n")
                p.stdin.close()
            except OSError:
                pass
            _update(path, sent=True, updated=time.time())
        elif ev == "step_update":
            s = e.get("step_update") or {}
            if s.get("step_type") == "agent_response":
                if s.get("text_delta"):
                    text += s["text_delta"]
                if s.get("state") == "DONE" and text.strip():
                    _update(path, last_message=text[-TEXT_CAP:], updated=time.time())
                    text = ""
            else:
                _update(path, updated=time.time())
        elif ev == "result":
            r = e.get("result") or {}
            turns = r.get("num_turns") or turns
            kw = dict(status=r.get("status"), turns=turns, usage=r.get("usage"), updated=time.time(),
                      denied_actions=r.get("denied_actions") or None)
            if (r.get("response") or "").strip():
                kw["last_message"] = r["response"][-TEXT_CAP:]
            if r.get("error"):
                kw["error"] = str(r["error"])[:500]
            _update(path, **kw)
    code = p.wait()
    watchdog.cancel()
    cur = _load(path) or {}
    if late and not cur.get("thread"):
        why = "agy printed no init event in %g s: killed, nothing sent" % _init_wait()
        _update(path, ended=time.time(), exit=code, status="ERROR", error=why, end_reason=why)
        return
    if not cur.get("thread"):
        try:
            with open(rec["log"], errors="replace") as f:
                tail = f.read()[-500:].strip()
        except OSError:
            tail = ""
        _update(path, error=cur.get("error") or tail or None)
    ending = cur.get("ending") or _stop_marker(path)
    _update(path, ended=time.time(), exit=code, ending=ending, end_reason=ending or "exit %d" % code)


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


def _claim(stem):
    """(base, run id): run files of their own — a short id in the name, the .json made exclusively."""
    while True:
        rid = uuid.uuid4().hex[:12]
        base = "%s-%s" % (stem, rid[:6])
        try:
            os.close(os.open(base + ".json", os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o644))
            return base, rid
        except FileExistsError:
            continue


def _stop_marker(path):
    """`harness stop`'s reason, in a file of its own beside the record (the wrapper owns the record's writes)."""
    try:
        with open(path[:-len(".json")] + ".stop", errors="replace") as f:
            return f.read().strip() or None
    except OSError:
        return None


def _preflight(ctx, req):
    """The refusals of this file that need no worktree (exit 2): the prompt's size, the mode key, the guards
    entry, the sandbox flag. Returns the mode."""
    if len((req.get("prompt") or "").encode("utf-8")) > PROMPT_CAP:
        ctx.fail("the prompt is over %d KB: hand agy its brief by path (agy -p cut one at about 187 KB without a word)"
                 % (PROMPT_CAP // 1024), 2)
    run_mode, why = mode()
    if why:
        ctx.fail("agy: %s — nothing started" % why, 2)
    why = _guards_why()
    if why:
        ctx.fail("%s — nothing started" % why, 2)
    why = sandbox_flag()
    if why:
        ctx.fail("agy sandbox: %s — nothing started" % why, 2)
    return run_mode


def _start(ctx, req, cwd, name, account, email, run_mode, conversation=None):
    os.makedirs(_runs_dir(), exist_ok=True)
    stamp = time.strftime("%Y%m%d-%H%M%S")
    base, rid = _claim(os.path.join(_runs_dir(), "%s-%s-%s" % (HARNESS, stamp, re.sub(r"[^A-Za-z0-9.-]+", "-", name))))
    path = base + ".json"
    _save(path, {"harness": HARNESS, "run": "agy-run-" + rid, "name": name, "cwd": cwd,
                 "repo": req.get("repo"), "branch": _git(cwd, "symbolic-ref", "--short", "-q", "HEAD"),
                 "model": req.get("model"), "effort": req.get("effort"), "started": time.time(),
                 "events": base + ".jsonl", "log": base + ".log", "agy_log": base + ".agy.log",
                 "resumed_from": conversation, "account": account, "email": email, "sandbox": True, "mode": run_mode,
                 "dispatched": os.environ.get("HARNESS_DISPATCHED") or None})
    argv = _argv(req, base + ".agy.log", run_mode, conversation)
    _detach(lambda: _wrap(path, argv, req["prompt"], cwd))
    # the conversation id is agy's (its init event), read back, never made up here; the start counts once the
    # prompt went in, or the run ended without it. The wait covers the wrapper's init deadline and its login check
    wait = max(_wait("HARNESS_START_WAIT", 30), _init_wait() + _wait("HARNESS_AGY_WHO_WAIT", 5) + 5)
    end = time.time() + wait
    while time.time() < end:
        rec = _load(path) or {}
        if rec.get("sent") or rec.get("ended"):
            break
        time.sleep(0.25)
    rec = _load(path) or {}
    if not rec.get("sent") and not rec.get("ended"):
        # the wrapper missed its own deadline (it died, or agy outlived its kill): end it here, failed
        if _running(rec):
            try:
                os.kill(rec["pid"], signal.SIGKILL)
            except OSError:
                pass
        why = "agy neither started nor ended within %g s: killed, nothing sent" % wait
        _update(path, ended=time.time(), exit=rec.get("exit") if rec.get("exit") is not None else -9,
                status="ERROR", error=why, end_reason=why)
        ctx.fail("agy did not start: %s (log %s)" % (why, rec.get("log")), 1)
    if rec.get("refused"):
        while time.time() < end and not (_load(path) or {}).get("ended"):
            time.sleep(0.25)
        ctx.fail(rec.get("ending"), 2)
    if rec.get("ended") and not rec.get("sent"):
        ctx.fail("agy did not start: %s (log %s)" % (rec.get("error") or rec.get("end_reason"), rec.get("log")), 1)
    return _run_record(ctx, path, _load(path) or rec)


def run(ctx, req):
    """V1: agy in print mode under the wrapper, in --cwd (a claude/* worktree, as every run here)."""
    if req.get("branch") or req.get("on"):
        ctx.fail("agy run takes --prompt in --cwd (a worktree); a seeded branch goes `dispatch BRANCH --harness agy`", 2)
    if req.get("runner"):
        ctx.fail("an agy run is agy under this harness's own wrapper; no --runner (Orca's agy agent is orca-vendors S2)", 2)
    if req.get("agent") not in (None, "", "agy"):
        ctx.fail("--harness agy runs agy, not --agent %s" % req["agent"], 2)
    if req.get("account") not in (None, "", "auto"):
        ctx.fail("agy picks its login itself (bin/account pick --provider antigravity); --account %s is not taken" % req["account"], 2)
    for k in ("ephemeral", "headless"):
        if req.get(k):
            ctx.fail("--%s is not an agy run's: agy runs in print mode, its record kept" % k, 2)
    cwd = req.get("cwd")
    if not cwd or not req.get("prompt"):
        ctx.fail("agy run needs --cwd (a claude/* worktree) and --prompt or --prompt-file", 2)
    run_mode = _preflight(ctx, req)
    branch, top = _worktree(ctx, cwd)
    account, email = _pick(ctx, req, cwd)
    name = req.get("name") or re.sub(r"^\d{4}-\d{2}-\d{2}-", "", branch.rsplit("/", 1)[-1])
    return _start(ctx, req, top, name, account, email, run_mode)


def resume(ctx, rec, req):
    """V2: the conversation's next turn, `--conversation <id>`, on the login it ran on."""
    tid = rec.get("session_id")
    native = rec.get("native") or {}
    if req.get("fork"):
        ctx.fail("agy has no fork of a conversation: resume it, or start a new run", 2)
    if not tid or str(tid).startswith("agy-run-"):
        ctx.fail("this run has no agy conversation id (it never started): nothing to resume", 2)
    if rec.get("state") not in _FINAL:
        ctx.fail("%s is live (%s): stop it first (harness stop %s)" % (tid, rec.get("state"), tid), 2)
    cwd = rec.get("cwd")
    if not cwd or not os.path.isdir(cwd):
        ctx.fail("%s's directory %s is not here: nothing to resume in" % (tid, cwd), 2)
    if not req.get("prompt"):
        ctx.fail("agy resume needs --prompt or --prompt-file", 2)
    run_mode = _preflight(ctx, req)
    _, top = _worktree(ctx, cwd)
    account, email = _pick(ctx, req, cwd)
    if rec.get("account") and account != rec["account"]:
        ctx.fail("%s ran on %s; the pick now gives %s — a conversation stays on its login" % (tid, rec["account"], account), 2)
    name = req.get("name") or native.get("topic") or rec.get("title") or str(tid)[:8]
    name = re.sub(r"[^A-Za-z0-9-]+", "-", name).strip("-")[:60] or str(tid)[:8]
    req = dict(req, repo=req.get("repo") or native.get("repo"), model=req.get("model") or rec.get("model"),
               effort=req.get("effort") or rec.get("effort"))
    return _start(ctx, req, top, name, account, email, run_mode, conversation=tid)


def stop(ctx, rec):
    """V5: SIGTERM to the run's agy — its pid and start time checked first — then the record once the wrapper wrote
    the end (agy answers SIGTERM with a `result` of error "interrupted")."""
    path = (rec.get("native") or {}).get("run")
    if not path:
        ctx.fail("%s is no harness run: end it where it runs" % rec.get("session_id"), 2)
    cur = _load(path) or {}
    if rec.get("state") not in _FINAL and not cur.get("ended"):
        if not _running(cur):
            ctx.fail("%s: its agy (pid %s) is not the process the run started; nothing signalled" % (rec.get("session_id"), cur.get("pid")), 1)
        with open(path[:-len(".json")] + ".stop", "w") as f:
            f.write("stopped by harness stop\n")
        try:
            os.kill(cur["pid"], signal.SIGTERM)
        except OSError as e:
            ctx.fail("SIGTERM to %s: %s" % (cur["pid"], e), 1)
        end = time.time() + _wait("HARNESS_START_WAIT", 30)
        while time.time() < end and not (_load(path) or {}).get("ended"):
            time.sleep(0.25)
    final = _load(path) or cur
    out = _run_record(ctx, path, final)
    out["last_message"] = final.get("last_message")
    return out
