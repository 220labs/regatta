"""The scope's skipper (skipper-resilience S5; the build's skipper component, "The scope skipper —
start, record, stand-down, hand-over"): one Claude session per scope on the yard host, holding the
leases of the scope's ships (bin/leaselib.py), hearing their questions and answering what is its
own. The tick starts it when a ship needs it and ends it when none has for a while; nothing here
runs while the tick is disarmed, and a host with no lease file sees no line of it.

    helm skipper --start SCOPE [--dry-run]   start(): the one-shot launchd job
                                             dev.regatta.helm.skipper-<scope>-<start id> (RunAtLoad, no
                                             KeepAlive, no LaunchOnlyOnce, which can refuse a label it has
                                             seen), whose program is `screen -D -m -S skipper-<scope>
                                             /bin/bash libexec/skipper-run SCOPE START_ID`; every older
                                             label of the scope booted out and its screen quit first
    helm skipper --stop SCOPE [--why W]      stop(): every ship the scope's skipper holds back to the yard
                                             (`held by yard`), its screen quit, its record deleted, its jobs
                                             booted out
    libexec/skipper-run SCOPE START_ID       the job: strips the environment, then `python3 skipperlib.py
                                             run`, which picks the login, checks it is signed in, trusts the
                                             anchor, makes the Talk page, writes the record and execs claude
    helm tick                                ensure(): per scope, the hand-overs (a lapse, a deaf skipper),
                                             the start's verdict, the re-hail, the belt, the rotation, the daily
                                             hand-over, at most one start — acting only when the tick is armed

Both verbs refuse under CLAUDE_CODE_SESSION_ID: a session may not load a plist (the tick is launchd's
own child), and the allow rule that names the session verbs one by one never names these.

Files, all beside the record leaselib.record_path names (asklib.manager_dir(), `<host>-<scope>.*`):
    <host>-<scope>.json            the record the runner writes just before it execs claude (or claude-host): {session,
                                   name: "skipper · <scope>", scope, account, host, started, pid, space,
                                   gen: null, start, job, screen, anchor}; asklib.standing_manager(host,
                                   scope) reads it, and `space` is the Talk page relays reach it on
    <host>-<scope>.starts.jsonl    one line per start event — launched, refused, failed, took, stopped —
                                   the memory the tick counts failed starts in (three in a row raise the
                                   stall class `skipper won't start`, bin/stalls.py)
    <host>-<scope>.space           the scope's Talk page, kept across starts: one page per scope, not
                                   one per start (each start redeploys it stamped with its new session)
    skipper-<scope>.log            the job's stdout and stderr

A start succeeded once its session takes a ship (a `picked up by` or `taken by` lease event naming
it): a session stuck at a dialog has a live pid and a record too, so only the take counts, within
TAKE_WITHIN of the start. A refusal the runner can tell at once (no login every repo allows, a login
that is not signed in, an untrusted anchor) is a failed start the next pass reads, never a 5-minute
wait. Stdlib only, Python 3.9. Tests: HELM_LAUNCHCTL, HELM_LAUNCH_DIR, HELM_SCREEN, HELM_SCREENDIR, HELM_CLAUDE,
HELM_ACCOUNT, HELM_DISPATCH_RC, HELM_TRUST, HELM_RC_HOSTS replace the tools; STALLS_NOW pins the clock (as the tick's).
"""
import json
import os
import plistlib
import re
import shutil
import signal
import subprocess
import sys
import time
import uuid
from importlib.machinery import SourceFileLoader
from pathlib import Path

HERE = Path(__file__).resolve().parent
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))
import helmlib  # noqa: E402
import leaselib  # noqa: E402

LABEL_PREFIX = "dev.regatta.helm.skipper-"
START_ID_RE = r"\d{8}-\d{6}-[0-9a-f]{4}"
TAKE_WITHIN = 300        # a start whose session took no ship in 5 minutes failed (a stuck dialog included)
RUNNER_MARGIN = 60       # the runner writes its record no later than TAKE_WITHIN - this after the launch, or refuses
FAILS = 3                # failed starts in a row → the stall class `skipper won't start`
# …after which the tick tries once an hour, never more: a cause that passes by itself (every login's week
# out, a network blip at the Talk deploy) is not left to the owner's hand, and the stall stays raised
# until a start takes
RETRY_AFTER = 3600
# One window, never two: a launch with no outcome waits while it is at most TAKE_WITHIN old and is a
# failed start once older — a separate, shorter wait left a start between the two that was neither,
# booted out and relaunched with no failure counted (round 2 of the finish review).
IDLE_STOP = 30 * 60      # the belt: no ship needing the skipper for 30 minutes (G6) → --stop
CRASH_WITHIN = IDLE_STOP  # a claude that ends this soon after its start, a ship taken or not, is a failed start
DAILY = 24 * 3600        # the daily hand-over: a record older than this, at the 04:00 pass — the ceiling
DAILY_HOUR = 4
# The rotation (the owner, 2026-10-24: "keep their runs fairly short, so they don't carry too much context"):
# a skipper this old, or whose last turn carried this much context, hands over at its first quiet pass —
# the same hand-over as the daily one, since what a skipper knows lives in files (answers are commits,
# open questions are re-hailed). Not two skippers overlapping: every relay finds its skipper by (host,
# scope), and a skipper runs no builds that would need to drain. Age is the weak proxy (8 idle hours
# with two asks is a small context), so context is read too: claude-opus-5-5 sessions on the laptop's
# logins reached 970k (probed 2026-10-24; the yard's logins unprobed), so the cap fires long before
# auto-compact would. The context rule waits ROTATE_CONTEXT_AFTER from the start, so a scope busy enough
# to fill the cap fast rotates at most hourly — bounded churn, never a loop each pass.
ROTATE_AGE = 8 * 3600
ROTATE_CONTEXT = 200000
ROTATE_CONTEXT_AFTER = 3600
# quiet: idle this long by the registry's statusUpdatedAt — a session idle between the owner's Remote
# Control messages, or a Talk wake whose turn has not begun, is idle for a moment, never 10 minutes
QUIET_FOR = 10 * 60
TAIL_BYTES = 2000000     # the transcript's tail read for its last call, as wharf-runs' cold_prompt reads it
DEAF = 15 * 60           # a relay to the skipper unanswered this long while its session sits idle → deaf
# Opus, not Sonnet (the owner, 2026-10-24): the skipper's work is judgement on questions nobody spec'd,
# and the rotation keeps its runs short; `high`, as xhigh is the review gate's (D1)
MODEL, EFFORT = "claude-opus-5-5", "high"
# what the job's PATH holds: helm's poll plist's (install.sh), the user's own bin for claude
PATH = "/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:%s/.local/bin"
# the overrides a test or an overlay sets, carried into the job (launchd hands a job no shell's environment)
CARRY = ("REGATTA_CONFIG", "REGATTA_HOME", "SURFACES_FILE", "PLANS_DIR", "ASK_MANAGER_DIR", "ASK_SESSIONS_DIR",
         "PLAN_HOST", "CLAUDE_REPOS_JSON", "ACCOUNTS_FILE", "PLAN_PROJECTS_ROOT", "HELM_CLAUDE", "HELM_ACCOUNT",
         "HELM_DISPATCH_RC", "HELM_TRUST", "MEMO_SHEEP_BIN", "HELM_RC_HOSTS")
# a block only the owner can move — a person's task, a decision block's memo gate (wharf's "gated on")
# — is the yard's to hold. An escalation is marked on its ask (`helm skipper --escalate`), never read
# from the task's progress: that text sticks, and a later question would read as escalated too.
OWNER_PROGRESS = ("gated on ",)


class Refused(Exception):
    """A start, a stop or a runner step that will not go; str() is the line printed after `won't start: `."""


def clock():
    """The tick's own clock (stalls_tick.clock: STALLS_NOW pins it), one reader for both."""
    try:
        import stalls_tick
    except ImportError:   # no core: stalls_tick will not load, and the same rule is this one
        return float(os.environ.get("STALLS_NOW") or time.time())
    return stalls_tick.clock()


def holder(scope):
    return leaselib.holder_of(scope)


def screen_name(scope):
    return "skipper-%s" % scope


def job_label(scope, start_id):
    return LABEL_PREFIX + scope + "-" + start_id


# ---------------------------------------------------------------------------- where things are

def manager_dir():
    import asklib
    return asklib.manager_dir()


def _side(scope, suffix, host=None):
    return manager_dir() / ("%s-%s%s" % (host or helmlib.host(), scope, suffix))


def starts_path(scope, host=None):
    return _side(scope, ".starts.jsonl", host)


def space_path(scope, host=None):
    return _side(scope, ".space", host)


def log_path(scope):
    return manager_dir() / ("skipper-%s.log" % scope)


def launch_dir():
    return Path(os.environ.get("HELM_LAUNCH_DIR") or Path(os.environ.get("HOME") or Path.home()) / "Library/LaunchAgents")


def screendir():
    # dispatch's socket dir (wharf-runs' run_rc): one `screen -ls` there lists the runs and the skippers;
    # HELM_SCREENDIR moves it (the tests')
    v = os.environ.get("HELM_SCREENDIR")
    return Path(v) if v else Path(os.environ.get("HOME") or Path.home()) / "Library/Caches/run-seed/screen"


def module_dir():
    """This module as the job should name it: the main checkout's, when this runs from a linked
    worktree (as install.sh's plist does) — /finish removes a worktree, and a job that names one
    would start nothing after it."""
    here = HERE.parent
    try:
        r = subprocess.run(["git", "-C", str(here), "rev-parse", "--path-format=absolute", "--git-common-dir"],
                           capture_output=True, text=True, timeout=10)
        common = Path(r.stdout.strip())
        if r.returncode == 0 and common.name == ".git" and (common.parent / "modules" / "helm").is_dir():
            return common.parent / "modules" / "helm"
    except (OSError, subprocess.TimeoutExpired):
        pass
    return here


def tool_cmd(name):
    """The path a session is handed for `ask` or `helm`: this module's own file, which the account
    dirs' allow rules name (the overlay's shim came first until B14b, 2026-10-23, which deleted it)."""
    return str(HERE.parent / ("libexec" if name == "helm" else "bin") / name)


def _tool(env_name, peer_name):
    v = os.environ.get(env_name)
    if v:
        return Path(v)
    return helmlib.peer(peer_name)


def _run(argv, env=None, timeout=60, cwd=None):
    """(rc, stdout, stderr); rc None when it did not run (absent, timed out)."""
    try:
        r = subprocess.run([str(x) for x in argv], capture_output=True, text=True, timeout=timeout, env=env, cwd=cwd)
    except (OSError, subprocess.TimeoutExpired) as e:
        return None, "", "%s: %s" % (Path(str(argv[0])).name, e.__class__.__name__)
    return r.returncode, r.stdout, r.stderr


def _py(path):
    """A peer script, run by this Python whatever its own shebang (the tools are Python 3.9 stdlib)."""
    return [sys.executable, str(path)]


# ---------------------------------------------------------------------------- the scope

def projects_root():
    v = os.environ.get("PLAN_PROJECTS_ROOT")
    return Path(v) if v else Path(helmlib._common().PROJECTS)


def scope_repos(scope):
    """(anchor key, [every repo key of the scope, anchor first]) from the registry, through the core's
    reader. A torn registry refuses (the fence trap: an unreadable registry is never read as none)."""
    try:
        c = helmlib._common()
    except ImportError:
        raise Refused("no regatta core here: no registry to read the scope from")
    if c.registry_unreadable():
        raise Refused("the registry does not read (%s): no scope can be told from it" % c.repos_json())
    repos, scopes = c.scope_registry()
    s = scopes.get(scope)
    if not isinstance(s, dict):
        raise Refused("no scope %s in the registry" % scope)
    keys = c.scope_members(s, repos)
    if not keys:
        raise Refused("scope %s lists no repo" % scope)
    return keys[0], keys


def repo_path(key):
    return projects_root() / key


# ---------------------------------------------------------------------------- the login
# No scope `login` key is read or written (S3's call): `account pick` pins a scope's login hard and
# waits when it cannot run, which would stop every run of the scope's repos. So the login is chosen
# here without a pin: the anchor's pick first; when a repo of the scope denies it, the pick for that
# repo; the first pick every repo allows wins, and each repo is picked for at most once.

def login_env(env):
    """This process's environment on the login `env` (account's start env: CLAUDE_CONFIG_DIR, or
    nothing for the default dir, which must run with it unset)."""
    e = {k: v for k, v in os.environ.items() if k != "CLAUDE_CONFIG_DIR"}
    e.update(env or {})
    return e


def pick(path):
    """(label, env, None), or (None, None, why) when no login may run there."""
    tool = _tool("HELM_ACCOUNT", "account")
    if not tool:
        raise Refused("no login (lighthouse's account is not installed)")
    rc, out, err = _run(_py(tool) + ["pick", "--repo", str(path), "--json"])
    if rc == 4:   # no registry on this Mac: callers start on the default login, as dispatch does
        return "default", {}, None
    try:
        d = json.loads(out or "{}")
    except ValueError:
        d = {}
    if rc == 0 and d.get("account"):
        return d["account"], d.get("env") or {}, None
    skipped = "; ".join("%s: %s" % tuple(x) for x in d.get("skipped") or [] if isinstance(x, (list, tuple)) and len(x) == 2)
    return None, None, skipped or (err or out).strip()[-200:] or "account pick exit %s" % rc


class CannotTell(Refused):
    """`account allowed` gave neither a yes nor a no: never read as a denial (AGENTS.md's probe trap)."""


def denies(env, path):
    """None when the login may work in path (the guard's own question, `account allowed`), else the
    account's refusal line. `allowed` refuses with exit 1 and its line on stdout; Python exits 1 on
    any uncaught error too, with a traceback on stderr and nothing on stdout, so only an exit 1 that
    printed a line and no traceback is a denial. Anything else is CannotTell — the start is refused
    as "could not tell", and no login is named as denying what it never denied."""
    tool = _tool("HELM_ACCOUNT", "account")
    rc, out, err = _run(_py(tool) + ["allowed", str(path)], env=login_env(env))
    if rc == 0:
        return None
    if rc == 1 and (out or "").strip() and "Traceback" not in (err or ""):
        return out.strip()
    raise CannotTell("could not tell whether the login may work in %s (account allowed: %s)" % (
        path, ((err or out).strip().splitlines() or ["exit %s" % rc])[-1][:160]))


def choose_login(scope, anchor, keys):
    """(label, env): a login every repo of the scope allows, or Refused naming each denial."""
    tried, denials, seen, queue = set(), [], set(), [anchor]
    while queue:
        repo = queue.pop(0)
        if repo in seen:
            continue
        seen.add(repo)
        label, env, why = pick(repo_path(repo))
        if label is None:
            if repo == anchor:
                raise Refused("no login (%s)" % why)
            denials.append("%s: no login (%s)" % (repo, why))
            continue
        if label in tried:
            continue
        tried.add(label)
        try:
            off = [k for k in keys if denies(env, repo_path(k))]
        except CannotTell as e:
            raise CannotTell("%s: %s" % (label, e))
        if not off:
            return label, env
        denials += ["%s denies %s" % (label, k) for k in off]
        queue += off
    # the picks ran out: every other row the walk would run the anchor on (`account limits --repo`,
    # cached: no probe), each tested as the picks were — a third login may allow every repo where
    # the anchor's pick and the denying repo's pick each deny one (the review of the S5 branch)
    for label, env in eligible_rows(repo_path(anchor)):
        if label in tried:
            continue
        tried.add(label)
        try:
            off = [k for k in keys if denies(env, repo_path(k))]
        except CannotTell as e:
            raise CannotTell("%s: %s" % (label, e))
        if not off:
            return label, env
        denials += ["%s denies %s" % (label, k) for k in off]
    raise Refused("no login every repo of %s allows (%s)" % (scope, ", ".join(denials)))


def eligible_rows(path):
    """[(label, env)] of the Claude rows `account limits --all --repo PATH --json --cached` calls
    eligible there, in the walk's order; [] when it does not answer."""
    tool = _tool("HELM_ACCOUNT", "account")
    rc, out, _ = _run(_py(tool) + ["limits", "--all", "--repo", str(path), "--json", "--cached"])
    try:
        rows = json.loads(out or "[]") if rc == 0 else []
    except ValueError:
        return []
    return [(r["label"], r.get("env") or {}) for r in rows if isinstance(r, dict) and r.get("eligible")
            and (r.get("provider") or "claude") == "claude" and r.get("label")]


def claude_cmd():
    return os.environ.get("HELM_CLAUDE") or shutil.which("claude", path=PATH % Path.home()) or "claude"


def launcher():
    """claude-host's path when this Mac's grant lets it start claude (wharf-runs' `rc-hosts --launcher
    claude`, the question dispatch and weekly-run ask), else None: a bare claude, as before. Skipper-ears
    S1 (2026-10-24): under launchd a bare claude is charged to its own versioned binary, which TCC denied
    Full Disk Access on the yard, and it hung before its first turn; through claude-host every case
    passed. claude-host forwards TERM, INT and HUP to claude and waits for it, so the pid exec gives the
    record (claude-host's) lives as long as claude, which is its child (SIGKILL aside); readers that
    signal the session's claude take it from the registry (stop(), helm's --stand-down). A path that
    is not an executable file is no launcher: a bare claude then, never a start that fails at exec.
    HELM_RC_HOSTS stands in for rc-hosts (the suite's stub; HELM_CLAUDE never turns claude-host off,
    so an overlay that pins claude's path keeps the grant)."""
    lib = _launcherlib()
    return lib.ask(os.environ.get("HELM_RC_HOSTS") or helmlib.peer("rc-hosts"), "claude") if lib else None


_LAUNCHERLIB = []


def _launcherlib():
    """wharf-runs' launcherlib.py, the launcher rule's one home (clock and rc-hosts use it too), found
    through the core's tool lookup like every peer; None when wharf-runs is not installed."""
    if not _LAUNCHERLIB:
        path = helmlib.peer("launcherlib.py")
        lib = None
        try:
            if path:
                lib = SourceFileLoader("launcherlib_for_helm", str(path)).load_module()
        except Exception:   # a torn checkout is no launcher: the skipper starts a bare claude, as before
            lib = None
        _LAUNCHERLIB.append(lib)
    return _LAUNCHERLIB[0]


def claude_argv(host_bin, *rest):
    """[claude, *rest] as the runner starts it: through claude-host where launcher() named one (it takes
    the word `claude` and starts the current one), else the bare claude."""
    return _launcherlib().through(["claude", *rest], host_bin) if host_bin else [claude_cmd(), *rest]


def logged_in(env, host_bin=None):
    """True or False from `claude auth status --json` on the login (probed 2026-10-22 on 2.1.309: an
    empty config dir prints {"loggedIn": false, …} and exits 1, in under a second), None when it
    cannot be told — then the start goes on and the 5-minute rule judges it. `account pick` probes
    limits, never the credential, so a login that answers "Not logged in" passes it."""
    # through claude-host where the runner found one: under launchd a bare claude is the binary TCC
    # denied (skipper-ears S1)
    cmd = claude_argv(host_bin)
    rc, out, err = _run(cmd + ["auth", "status", "--json"], env=login_env(env), timeout=30)
    try:
        v = json.loads(out or "").get("loggedIn")
    except (ValueError, AttributeError):
        return None
    return v if isinstance(v, bool) else None


def ensure_trusted(path, env):
    """dispatch's trust step for the login's config dir: `dispatch-rc trusted`, else trust-projects
    there, read back. A session at the trust dialog is S1's stuck start: never started untrusted."""
    rc_tool = _tool("HELM_DISPATCH_RC", "dispatch-rc")
    if not rc_tool:
        raise Refused("no trust check (wharf-runs' dispatch-rc is not installed)")
    cfg = (env or {}).get("CLAUDE_CONFIG_DIR", "")

    def trusted():
        # exit 0 trusted, 1 untrusted — and a traceback exits 1 too: told apart by its stderr, as
        # denies() does, so a crash is "could not tell", never "untrusted" (AGENTS.md's probe trap)
        rc, _, err = _run(_py(rc_tool) + ["trusted", str(path), "--config-dir", cfg])
        if rc not in (0, 1) or "Traceback" in (err or ""):
            raise CannotTell("could not tell whether %s is trusted (dispatch-rc trusted: %s)" % (
                path, ((err or "").strip().splitlines() or ["exit %s" % rc])[-1][:160]))
        return rc == 0

    if trusted():
        return "trusted"
    trust = _tool("HELM_TRUST", "trust-projects")
    if trust:
        _run(_py(trust), env=login_env(env), timeout=120)
    if trusted():
        return "trusted now (trust-projects, %s)" % (cfg or "the default login")
    raise Refused("untrusted (%s)" % (cfg or str(Path.home() / ".claude")))


# ---------------------------------------------------------------------------- the Talk page

PAGE = ("<!doctype html><meta charset=utf-8><title>Skipper · %s</title>"
        "<p>skipper · %s — the scope's skipper. Relays reach it on this page's Talk thread.</p>")


def make_space(scope, sid):
    """(uuid or None, note): the scope's Talk page, deployed by the CLI with the session's id in the
    environment, which the CLI stamps on the deploy (stray-manager L5) — redeployed to the page an
    earlier start made, else a new one. With no page the start is refused (run()): the skipper's
    only ear is `ask listen` on Talk, and nothing a script sends by the file road wakes an idle
    session — a skipper with no page would hear nothing (round 2 of the finish review)."""
    import helm_render
    src = manager_dir() / "pages" / scope
    src.mkdir(parents=True, exist_ok=True)
    (src / "index.html").write_text(PAGE % (scope, scope))
    try:
        old = space_path(scope).read_text().strip() or None
    except OSError:
        old = None
    prev = os.environ.get("CLAUDE_CODE_SESSION_ID")
    os.environ["CLAUDE_CODE_SESSION_ID"] = sid
    try:
        for space in ([old, None] if old else [None]):
            try:
                got, _ = helm_render.deploy_dir(src, ("index.html",), space=space, title="Skipper · %s" % scope,
                                                message="start %s" % sid[:8])
            except (RuntimeError, OSError, subprocess.TimeoutExpired) as e:
                note = "no Talk page (%s)" % e
                continue
            space_path(scope).write_text(got + "\n")
            return got, "Talk page %s%s" % (got, " (the scope's, redeployed)" if space == old and old else "")
        return None, note
    finally:
        if prev is None:
            os.environ.pop("CLAUDE_CODE_SESSION_ID", None)
        else:
            os.environ["CLAUDE_CODE_SESSION_ID"] = prev


# ---------------------------------------------------------------------------- the record and the starts log

def read_record(scope, host=None):
    return leaselib.read_record(scope, host)


def write_record(scope, rec):
    p = leaselib.record_path(scope)
    p.parent.mkdir(parents=True, exist_ok=True)
    tmp = p.with_name("%s.%d.tmp" % (p.name, os.getpid()))
    tmp.write_text(json.dumps(rec, indent=1, ensure_ascii=False, sort_keys=True))
    tmp.replace(p)


def log_start(scope, event, start_id=None, **kw):
    p = starts_path(scope)
    p.parent.mkdir(parents=True, exist_ok=True)
    line = dict(kw, t=clock(), event=event, start=start_id, scope=scope, host=helmlib.host())
    fd = os.open(str(p), os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o644)
    try:
        os.write(fd, (json.dumps(line, ensure_ascii=False, sort_keys=True) + "\n").encode())
    finally:
        os.close(fd)
    return line


def starts(scope, host=None):
    try:
        text = starts_path(scope, host).read_text()
    except OSError:
        return []
    out = []
    for raw in text.splitlines():
        try:
            d = json.loads(raw)
        except ValueError:
            continue
        if isinstance(d, dict):
            out.append(d)
    return out


def consecutive_failures(lines):
    """[the failed or refused lines since the last start that took], newest first — or since a start
    by hand: the owner starting one from a shell is "try again", and the tick may then try its three,
    so the hand start's own failure is not one of them. A start by hand is refused to every unattended
    caller (session_refusal), so no run can write itself this reset."""
    out = []
    failed = set()
    for ln in reversed(lines):
        ev = ln.get("event")
        if ev == "took" and ln.get("start") not in failed:
            break   # a start that took and never failed after: the run of failures ends here
        if ev in ("refused", "failed"):
            out.append(ln)
            failed.add(ln.get("start"))
        elif ev == "launched" and ln.get("by") == "hand":
            return [x for x in out if x.get("start") != ln.get("start")]
    return out


def outcome(lines, start_id):
    """The verdict line of a start (refused, failed or took — or stopped: a stop before any pass judged
    it, a hand --stop within its first minutes, is its end, never a failure later), or None while it
    has none."""
    for ln in reversed(lines):
        if ln.get("start") == start_id and ln.get("event") in ("refused", "failed", "took", "stopped"):
            return ln
    return None


def note_wont_start(scope, why):
    """One `skipper won't start` lease event on each live ship of the scope: the ship's own record says
    why nobody holds it but the yard."""
    for pid, rec in leaselib.leases(scope):
        try:
            leaselib.note(pid, "skipper won't start", rec, refused=why)
        except (OSError, FileNotFoundError):
            pass


# ---------------------------------------------------------------------------- the brief

BRIEF = """You are {holder}, the skipper of scope {scope} on {host}: you hold the leases of its ships, hear their questions and answer what is yours. Nobody types here; your doors are Remote Control and your Talk page.

1. Run `{helm} skipper --hold --scope {scope} --once` (it takes every ship of the scope the yard holds), then `{helm} skipper --ships {scope}`.
2. Start two background shells: `{helm} skipper --hold --scope {scope}` (the sidecar: it renews your leases every 5 minutes for as long as you run; start it once and never again — if it exits 4 a newer holder has a ship, so run `{helm} skipper --stand-down`) and `{ask} listen` (your ear: re-arm it after every wake).
3. On an ASK line: a `Reversible: yes` item you answer yourself with `{ask} answer <doc> <Dn> "<text>" --from {screen} --source "yes item"` and the rest of the reply line it carries (keep its --plan). An ASK in `mode: ask` is the owner's alone: leave it carded. Anything else goes into one batched D-list for the owner; for each item run `{helm} skipper --escalate <ship> <Dn>` (it refuses a question the ship has not open, and lists the open ones); commit the D-list, run `{ask} relay <its doc> <Dn>` for it (a skipper's own relay goes to no skipper) and end that turn on the WAITING line it prints.
4. Never land or merge a branch, never run /talk, never edit a file outside docs/.
5. After each wake read `{helm} skipper --ships {scope}`. When it says nothing needs you on two reads 5 minutes apart, run `{helm} skipper --stand-down`."""


def brief(scope):
    return BRIEF.format(holder=holder(scope), scope=scope, host=helmlib.host(), helm=tool_cmd("helm"),
                        ask=tool_cmd("ask"), screen=screen_name(scope))


# ---------------------------------------------------------------------------- the runner (libexec/skipper-run)

def run(scope, start_id):
    """The job, inside its screen. Every line goes to the scope's log file itself: the plist's
    StandardOutPath captures screen's own output, and inside `screen -D -m` the runner's stdout is the
    screen's terminal, which nobody reads (probed in round 2 of the finish review: the log stayed
    empty). stdout is never redirected there instead — claude, exec'd from here, draws its screen on
    it. An uncaught error is a failed start with its traceback in the log, never a silent exit."""
    path = log_path(scope)

    def say(s):
        line = "%s %s" % (time.strftime("%Y-%m-%d %H:%M:%S"), s)
        print(line, flush=True)
        try:
            path.parent.mkdir(parents=True, exist_ok=True)
            with open(str(path), "a") as f:
                f.write(line + "\n")
        except OSError:
            pass

    try:
        return run_body(scope, start_id, say)
    except Exception:   # noqa: BLE001 — logged and counted, so three in a row raise the stall
        import traceback
        say("skipper won't start: the runner failed\n" + traceback.format_exc())
        try:
            log_start(scope, "failed", start_id, why="the runner failed (%s)" % sys.exc_info()[1])
        except OSError:
            pass
        return 1


def run_body(scope, start_id, say):
    """Every step that can refuse at once, then the record, then claude itself (exec: the record's
    pid is claude's, or claude-host's with claude its child when launcher() names one). Returns an
    exit code only on a refusal."""
    say("skipper-run %s, start %s, on %s" % (scope, start_id, helmlib.host()))
    if os.environ.get("CLAUDE_CODE_SESSION_ID"):
        say("won't start: CLAUDE_CODE_SESSION_ID is set — the runner is launchd's (skipper-run strips it)")
        return 2
    # the job's plist goes first, whatever follows: a RunAtLoad plist left in LaunchAgents is loaded
    # again at the next login and starts a skipper outside the tick (dispatch's cleanup: "a plist
    # left behind fires again"). The job stays loaded until then, but RunAtLoad fires only at a load.
    try:
        (launch_dir() / ("%s.plist" % job_label(scope, start_id))).unlink()
    except OSError:
        pass
    # only the start the tick (or the owner) just launched runs: a job launchd loads again — a plist
    # some earlier version left, a login after a crash — finds its start stale or already judged
    log_ = starts(scope)
    launched = next((x for x in reversed(log_) if x.get("event") == "launched" and x.get("start") == start_id), None)
    verdict = outcome(log_, start_id)
    if not launched or verdict or clock() - float(launched.get("t") or 0) > TAKE_WITHIN:
        say("won't run: start %s is %s — only a start just launched runs" % (
            start_id, "not in the starts log" if not launched else "judged already (%s)" % verdict.get("event")
            if verdict else "%ds old" % (clock() - float(launched.get("t") or 0))))
        return 1
    try:
        # the launcher first, inside the runner's own deadline: the sign-in probe and the exec both use it
        host_bin = launcher()
        say("claude through %s" % (host_bin if host_bin else "no claude-host (bare)"))
        anchor, keys = scope_repos(scope)
        cwd = repo_path(anchor)
        if not cwd.is_dir():
            raise Refused("no checkout of %s's anchor %s here (%s)" % (scope, anchor, cwd))
        label, env = choose_login(scope, anchor, keys)
        say("login %s (every repo of %s allows it: %s)" % (label, scope, ", ".join(keys)))
        auth = logged_in(env, host_bin)
        if auth is False:
            raise Refused("%s is not logged in" % label)
        say("signed in" if auth else "sign-in not readable (claude auth status): the 5-minute rule judges this start")
        say(ensure_trusted(cwd, env))
        sid = str(uuid.uuid4())
        space, note = make_space(scope, sid)
        say(note)
        if not space:
            raise Refused("%s — a skipper with no Talk page hears nothing (its ear is ask listen)" % note)
        # the runner's own deadline, a minute inside the tick's TAKE_WITHIN: a record written later
        # could meet a pass that already judged this start record-less and boots its job out
        took_s = clock() - float(launched.get("t") or 0)
        if took_s > TAKE_WITHIN - RUNNER_MARGIN:
            raise Refused("the runner took %ds to get here, past its own %ds — slow login, trust or Talk steps"
                          % (took_s, TAKE_WITHIN - RUNNER_MARGIN))
    except Refused as e:
        why = str(e)
        say("skipper won't start: %s" % why)
        log_start(scope, "refused", start_id, why=why)
        note_wont_start(scope, why)
        return 1
    rec = {"session": sid, "name": holder(scope), "scope": scope, "account": label, "host": helmlib.host(),
           "started": clock(), "pid": os.getpid(), "space": space, "gen": None, "start": start_id,
           "job": job_label(scope, start_id), "screen": screen_name(scope), "anchor": anchor}
    write_record(scope, rec)
    # the start's session, so a pass that finds the record already gone (a stand-down within the
    # first 5 minutes) still tells a start that took from one that failed
    log_start(scope, "recorded", start_id, session=sid)
    say("record %s; claude %s, session %s" % (leaselib.record_path(scope), os.getpid(), sid))
    e = login_env(env)
    e.pop("CLAUDE_CODE_SESSION_ID", None)
    # HELM_HOLD_PARENT: the sidecar lives by this pid, which exec makes claude's (or claude-host's, which
    # lives as long as its child claude) — never by a walk up
    # the process tree (S4's fallback, untested on a real session). CLAUDE_UNATTENDED=skipper: nobody
    # types here, so every guard that stands for a person's yes (helmlib.raise_refusal, ask answer's
    # mode-ask rule, tick and lookout arming, autofinish-run --merge, checkpoint.py's live rule) must
    # read it as unattended, as dispatch's runs are (CLAUDE_UNATTENDED=dispatch).
    # both of the marker's names (vendor-fence's stage 1: the core's unattended_env)
    e.update(SKIPPER_SCOPE=scope, SKIPPER_ACCOUNT=label, HELM_HOLD_PARENT=str(os.getpid()),
             REGATTA_UNATTENDED="skipper", CLAUDE_UNATTENDED="skipper")
    # the prompt first: --disallowedTools takes every word after it; through claude-host where this
    # Mac's grant allows it (launcher()), which takes the word `claude` and starts the current one
    argv = claude_argv(host_bin, brief(scope), "--session-id", sid, "--remote-control", holder(scope), "-n", screen_name(scope),
                       "--permission-mode", "auto", "--model", MODEL, "--effort", EFFORT, "--disallowedTools", "AskUserQuestion")
    os.chdir(str(cwd))
    sys.stdout.flush()
    try:
        os.execvpe(argv[0], argv, e)
    except OSError as err:
        why = "claude did not start (%s)" % err
        say("skipper won't start: %s" % why)
        log_start(scope, "failed", start_id, why=why)
        try:
            leaselib.record_path(scope).unlink()
        except OSError:
            pass
        return 1


# ---------------------------------------------------------------------------- launchd and screen

def launchctl():
    return os.environ.get("HELM_LAUNCHCTL") or "launchctl"


def screen():
    return os.environ.get("HELM_SCREEN") or "/usr/bin/screen"


def screen_env(create=True):
    """The environment for screen with dispatch's socket dir; `create` makes it (mode 700, which screen
    insists on) — a read (`-ls`) never does, so a dry run touches nothing of dispatch's."""
    d = screendir()
    if create:
        d.mkdir(parents=True, exist_ok=True)
        os.chmod(str(d), 0o700)   # screen refuses a socket directory others can read
    return dict(os.environ, SCREENDIR=str(d))


def labels(scope):
    """Every job label of the scope's skipper here: its plists and what launchd lists."""
    pat = re.compile("^" + re.escape(LABEL_PREFIX + scope + "-") + START_ID_RE + "$")
    out = set()
    try:
        for p in launch_dir().glob(LABEL_PREFIX + "*.plist"):
            if pat.match(p.stem):
                out.add(p.stem)
    except OSError:
        pass
    rc, so, _ = _run([launchctl(), "list"], timeout=20)
    for line in (so or "").splitlines() if rc == 0 else []:
        parts = line.split()
        if parts and pat.match(parts[-1]):
            out.add(parts[-1])
    return sorted(out)


def boot_out(label):
    _run([launchctl(), "bootout", "gui/%d/%s" % (os.getuid(), label)], timeout=30)
    try:
        (launch_dir() / ("%s.plist" % label)).unlink()
    except OSError:
        pass


def screens(scope):
    """`<pid>.skipper-<scope>` for each live screen of exactly that name. `-S <name>` alone is a
    prefix match: `skipper-dock` would quit `skipper-dockyard`, and with both up it matches several
    and quits neither (dispatch-rc's screen_target names the pid for this). `screen -ls` exits
    non-zero even when it lists, so its output is read whatever the code."""
    if not screendir().is_dir():
        return []
    _, out, _ = _run([screen(), "-ls"], env=screen_env(create=False), timeout=20)
    name = screen_name(scope)
    got = []
    for line in (out or "").splitlines():
        m = re.match(r"\s*(\d+)\.(\S+)\s", line + " ")
        if m and m.group(2) == name and "Dead" not in line:
            got.append("%s.%s" % (m.group(1), name))
    return got


def quit_screen(scope):
    for target in screens(scope):
        _run([screen(), "-S", target, "-X", "quit"], env=screen_env(), timeout=20)


def plist_of(scope, start_id):
    mod = module_dir()
    env = {"PATH": PATH % Path.home(), "SCREENDIR": str(screendir()), "TERM": "xterm-256color",
           "LANG": os.environ.get("LANG") or "en_US.UTF-8"}
    env.update((k, os.environ[k]) for k in CARRY if os.environ.get(k))
    log = str(log_path(scope))
    return {"Label": job_label(scope, start_id),
            # foreground screen (-D -m): launchd owns it, and the poll's kill of the tick never reaches it
            "ProgramArguments": [screen(), "-D", "-m", "-S", screen_name(scope), "/bin/bash",
                                 str(mod / "libexec" / "skipper-run"), scope, start_id],
            "RunAtLoad": True, "EnvironmentVariables": env, "StandardOutPath": log, "StandardErrorPath": log}


def session_ancestor():
    """The pid of a live Claude Code session this process runs under, or None: an ancestor with a
    record in the session registry (`<sessions dir>/<pid>.json` naming that pid). The variables a
    session carries can be dropped (`env -u CLAUDE_CODE_SESSION_ID`), and a direct descendant still
    shows its session here. A double fork re-parents to launchd and is not seen (the third review of
    S5): this check backs CLAUDE_UNATTENDED, which every unattended run carries, and the permission
    rules, which never allow --start; it is no wall on its own."""
    try:
        import asklib
        reg = asklib.sessions_dir()
    except ImportError:
        return None
    p = os.getppid()
    for _ in range(40):
        if p <= 1:
            return None
        f = reg / ("%d.json" % p)
        try:
            r = json.loads(f.read_text())
            # the process the record was written for (same_process): a record a crash left over a
            # reboot names a pid a shell may hold now, and would refuse every verb from it
            if r.get("pid") == p and same_process(p, r):
                return p
        except (OSError, ValueError, AttributeError):
            pass
        rc, out, _ = _run(["/bin/ps", "-o", "ppid=", "-p", str(p)], timeout=5)
        if rc != 0 or not (out or "").strip().isdigit():
            return None
        p = int(out.strip())
    return None


def session_refusal(verb):
    """Why VERB may not run here, or None. Loading a job is the tick's (launchd's own child) or the
    owner's from a plain shell: refused under CLAUDE_CODE_SESSION_ID, under CLAUDE_UNATTENDED (every
    dispatched run and the skipper itself carry it; a start by hand resets the failure count, a
    person's yes no run may give itself — AGENTS.md's trap), and as a direct descendant of a live
    session's process, whatever its environment says (session_ancestor: a double fork is not seen)."""
    sid = os.environ.get("CLAUDE_CODE_SESSION_ID")
    if sid:
        return ("helm skipper %s: refused inside a session (CLAUDE_CODE_SESSION_ID %s) — a session may not load "
                "or boot out a job; the tick, launchd's own child, does" % (verb, sid[:8]))
    mark = next(("%s=%s" % (n, os.environ[n]) for n in ("REGATTA_UNATTENDED", "CLAUDE_UNATTENDED") if os.environ.get(n)), None)
    if mark:   # the core's unattended_label, read here as this guard reads every name: from the environment
        return ("helm skipper %s: refused in an unattended caller (%s) — the tick or the owner's "
                "shell starts and stops a skipper" % (verb, mark))
    anc = session_ancestor()
    if anc:
        return ("helm skipper %s: refused below a live session (pid %d in the registry) — a session may not load "
                "or boot out a job, with or without its variables" % (verb, anc))
    return None


def start(scope, dry=False, by="hand"):
    """The one-shot job for SCOPE: (start id, lines). Refused under a session, for a scope the registry
    does not name; a dry run prints the plist and loads nothing."""
    why = session_refusal("--start")
    if why:
        raise Refused(why)
    scope_repos(scope)
    start_id = time.strftime("%Y%m%d-%H%M%S", time.localtime(clock())) + "-" + os.urandom(2).hex()
    label = job_label(scope, start_id)
    plist = plist_of(scope, start_id)
    # a skipper of the scope that holds ships or has a record is stopped as --stop stops it — its
    # ships back to the yard first — never only killed: a killed holder's leases would stay its own
    # until they lapsed, and the new session's take would be refused for every ship until then
    # The tick only replaces what it started (a record): a ship some other live session holds with no
    # record — a hold by hand — is left to it, and the new skipper takes what the yard holds. A start
    # by hand replaces whatever holds the scope.
    running = bool(read_record(scope)) or (by == "hand" and any(r["holder"] != leaselib.YARD for _, r in leaselib.leases(scope)))
    if dry:
        return start_id, ((stop(scope, "replaced by start %s" % start_id, by=by, dry=True) if running else
                           ["would boot out %s" % x for x in labels(scope)] +
                           ["would quit screen %s" % x for x in screens(scope)]) +
                          ["would load %s:" % label, plistlib.dumps(plist).decode()])
    lines = stop(scope, "replaced by start %s" % start_id, by=by) if running else []
    for x in labels(scope):
        boot_out(x)
        lines.append("booted out %s" % x)
    quit_screen(scope)
    # the job's SCREENDIR (dispatch's), made here: on a host where no run has made it yet, screen
    # would refuse to start the job's session (it cannot make the socket directory)
    screen_env(create=True)
    launch_dir().mkdir(parents=True, exist_ok=True)
    manager_dir().mkdir(parents=True, exist_ok=True)
    path = launch_dir() / ("%s.plist" % label)
    with open(str(path), "wb") as f:
        plistlib.dump(plist, f)
    log_start(scope, "launched", start_id, job=label, by=by)
    target = "gui/%d" % os.getuid()
    rc, _, err = _run([launchctl(), "bootstrap", target, str(path)], timeout=30)
    if rc != 0:   # bootout returns before the old job is gone (dispatch met "5: Input/output error"): once more
        time.sleep(2)
        rc, _, err = _run([launchctl(), "bootstrap", target, str(path)], timeout=30)
    if rc != 0:
        try:
            path.unlink()
        except OSError:
            pass
        why = "launchctl bootstrap failed (%s)" % ((err or "").strip()[-160:] or "exit %s" % rc)
        log_start(scope, "failed", start_id, why=why)
        raise Refused(why)
    lines.append("started %s: %s; log %s" % (holder(scope), label, log_path(scope)))
    return start_id, lines


def stop(scope, why, by="hand", dry=False):
    """The scope's skipper ended: its ships back to the yard first (gen + 1, `held by yard`, so its
    sidecar's next renewal is refused), then its screen quit, its record deleted, every job of the
    scope booted out, and the record's claude sent SIGTERM while its session's registry record still
    names that pid. Lines. A dry run changes nothing and says what it would do. The tick's stops
    (by="tick") hand back only the ships the record's session holds: a ship some live session holds
    with no skipper record, a hold by hand, is that session's (the third review of S5); the owner's
    stop by hand hands back every ship the scope's skippers hold."""
    w = session_refusal("--stop")
    if w:
        raise Refused(w)
    rec = read_record(scope)

    def ours(lease):
        return lease["holder"] != leaselib.YARD and (by != "tick" or (rec and lease.get("session") == rec.get("session")))

    # the start this stop ends: the record's, else a launch no verdict has judged yet (a stop before the
    # runner wrote its record), so that start is never judged a failure afterwards
    log_ = starts(scope)
    pending = next((x.get("start") for x in reversed(log_) if x.get("event") == "launched"), None)
    start_id = (rec or {}).get("start") or (pending if pending and not outcome(log_, pending) else None)
    if dry:
        held = [p for p, l in leaselib.leases(scope) if ours(l)]
        return (["would hand %s to the yard" % p for p in held] + ["would quit screen %s" % x for x in screens(scope)]
                + (["would delete the record %s" % leaselib.record_path(scope)] if rec else [])
                + ["would boot out %s" % x for x in labels(scope)]
                + ["would stop %s (%s): %s" % (holder(scope), why, ", ".join(held) or "no ship held")])
    lines, back = [], []
    for pid, lease in leaselib.leases(scope):
        if not ours(lease):
            continue
        try:
            leaselib.hand_back(pid, lease["gen"], lease.get("session"), "%s stopped: %s" % (lease["holder"], why))
            back.append(pid)
        except (leaselib.Refused, leaselib.Unreadable, OSError) as e:
            lines.append("%s: not handed back (%s)" % (pid, e))
    quit_screen(scope)
    if rec:
        try:
            leaselib.record_path(scope).unlink()
        except OSError:
            pass
    for x in labels(scope):
        boot_out(x)
    # only a pid the registry still gives its session: a record outlives its claude (the failed and
    # the lapsed starts are such), and a reused pid is someone else's process. The record's pid is
    # claude's own, or claude-host's when launcher() named one (claude its child, which the registry
    # names): the registry's claude is signalled when it is the record's pid or that pid's child
    reg = registry_of(rec.get("session")) if rec else None
    cpid = reg.get("pid") if reg else None
    if rec and rec.get("pid") and cpid and pid_alive(cpid) and same_process(cpid, reg) \
            and str(rec["pid"]) in (str(cpid), str(ppid_of(cpid))):
        try:
            os.kill(int(cpid), signal.SIGTERM)
        except OSError:
            pass
    log_start(scope, "stopped", start_id, why=why, by=by)
    lines.append("stopped %s (%s): %s back to the yard" % (holder(scope), why, ", ".join(back) or "no ship"))
    return lines


def pid_alive(pid):
    import asklib   # the one "is this pid alive" test, standing_manager's
    return asklib.pid_alive(pid)


def ppid_of(pid):
    """The parent pid of PID, or None: under claude-host the registry's claude is the record's child."""
    rc, out, _ = _run(["/bin/ps", "-o", "ppid=", "-p", str(pid)], timeout=5)
    return int(out.strip()) if rc == 0 and out.strip().isdigit() else None


# ---------------------------------------------------------------------------- what a ship needs

def waits_on_owner(t, pid=None):
    """A block only the owner moves: a person's task; a `waiting` one whose progress says it is gated
    on a decision doc (wharf); or one whose open questions are all the owner's (owners_ask: escalated —
    marked on each ask by `helm skipper --escalate`, so a later status report never un-escalates them
    and a later question is never read as escalated —, held by mode ask or dnd, or answered in its doc)."""
    if t.get("kind") == "human":
        return True
    if t.get("status") == "waiting" and str(t.get("progress") or "").startswith(OWNER_PROGRESS):
        return True
    open_ = [a for a in t.get("asks") or [] if a.get("open")]
    return bool(open_) and all(owners_ask(pid, t, a) for a in open_) and t.get("status") in ("waiting", "relayed", "parked")


class Fenced(Refused):
    """An acting verb the ship's lease refuses: exit leaselib.REFUSED_EXIT (4)."""


def escalate(pid, ref):
    """`helm skipper --escalate PLAN REF`: mark one open question of the ship as handed to the owner —
    the skipper's own verb, fenced by the ship's lease. REF is the ask's ref (`docs/x.md#D2`) or its
    item alone (`D2`) when that names one open question; anything else is refused, listing the open
    ones, so a mistyped ref never makes a phantom ask while the real one stays open. The event holds
    the task, the ask and the mark only: no session, host, repo, status or progress of the caller's is
    stamped on the run's task. Returns the line to print."""
    if helmlib.load_plan(pid) is None:
        raise Refused("no ship %s here" % pid)
    # the fence and the mark under the plan's lock, as every hand-over writes: a holder handed over
    # between the check and the append never marks a question it no longer holds
    with helmlib.locked(pid):
        why = leaselib.fence(pid, "helm skipper --escalate")
        if why:
            raise Fenced(why)
        tasks = helmlib.state(pid)["tasks"]
        open_ = [(t, a) for t in tasks if t["status"] not in helmlib.ENDED for a in t["asks"] if a.get("open")]
        hits = [(t, a) for t, a in open_ if a["ref"] == ref or a["ref"].endswith("#" + ref)]
        if len(hits) != 1:
            raise Refused("%s names %s open question of ship %s — open: %s" % (
                ref, "no" if not hits else "more than one", pid, ", ".join(a["ref"] for _, a in open_) or "none"))
        t, a = hits[0]
        if a.get("escalated"):
            return "%s %s: escalated already" % (pid, a["ref"])
        helmlib.append_event(pid, {"task": t["id"], "ask": a["ref"], "escalated": True, "plan": pid,
                                   "via": "helm skipper --escalate"})
        return "%s %s: escalated to the owner (task %s)" % (pid, a["ref"], t["id"])


_PASS = None   # one pass's reads (ensure sets it): each ship's merged tasks, its docs, a take seen


def tasks_of(pid):
    cache = _PASS.setdefault("tasks", {}) if _PASS is not None else None
    if cache is not None and pid in cache:
        return cache[pid]
    tasks = helmlib.state(pid)["tasks"]
    if cache is not None:
        cache[pid] = tasks
    return tasks


def needs(pid, tasks=None):
    """(needs a skipper, [ids of open blocks that wait on the owner]): a ship needs its scope's skipper
    while any block is open that is not the owner's alone — or one `helm send` sent and no skipper has
    picked up yet (S7: the sender waits on that pickup, whoever the block itself waits on). TASKS: the
    merged tasks when the caller has them already (helm skipper --ships)."""
    try:
        tasks = tasks if tasks is not None else tasks_of(pid)
    except (FileNotFoundError, ValueError):
        return False, []
    live = [t for t in tasks if t["status"] not in helmlib.ENDED]
    owner = [t["id"] for t in live if waits_on_owner(t, pid)]
    # S7: a task helm send sent and no skipper has picked up needs one, whoever its block waits on
    return len(owner) < len(live) or any(t.get("send") == "sent" for t in live), owner


def took(scope, session):
    """True once SESSION has taken a ship of SCOPE (the S4 words: `picked up by` from the yard's gen 0,
    `taken by` after a hand-back)."""
    if not session:
        return False
    if _PASS is not None and (scope, session) in _PASS.setdefault("took", {}):
        return _PASS["took"][(scope, session)]
    got = any(e.get("lease") in ("picked up by", "taken by") and e.get("session") == session
              for pid, _ in leaselib.leases(scope, include_ended=True) for e in helmlib.events(pid))
    if _PASS is not None and got:   # a take never un-happens; a "not yet" is read again
        _PASS["took"][(scope, session)] = got
    return got


def registry_of(session):
    import asklib
    return asklib.registry(session) if session else None


def same_process(pid, reg):
    """True when PID is the process the registry record REG was written for: its `procStart` (the
    registry writes it in UTC, `ps -o lstart` in TZ=UTC prints the same — probed 2026-10-23 on four
    live sessions) equals the pid's start. A record left over a reboot names a pid some other process
    may hold now. A record with no procStart cannot be told apart: the pid alone decides, as before."""
    want = (reg or {}).get("procStart")
    if not want:
        return pid_alive(pid)
    rc, out, _ = _run(["/bin/ps", "-o", "lstart=", "-p", str(pid)], env=dict(os.environ, TZ="UTC", LC_ALL="C"), timeout=5)
    return rc == 0 and " ".join((out or "").split()) == " ".join(str(want).split())


def record_alive(rec):
    """The record's pid lives, and so does its session's registry pid, the very process the registry
    names (asklib.standing_manager's test, and the process's start against the registry's)."""
    if not rec or not pid_alive(rec.get("pid")):
        return False
    reg = registry_of(rec.get("session"))
    return bool(reg) and pid_alive(reg.get("pid")) and same_process(reg.get("pid"), reg)


# ---------------------------------------------------------------------------- the re-hail and the deaf rule

def ask_events(pid):
    """{ask ref: its first event} — the ask's repo (main checkout), the asking session, its task."""
    out = {}
    for e in helmlib.events(pid):
        if e.get("ask") and e["ask"] not in out:
            out[e["ask"]] = e
    return out


OWNER_MODES = ("ask", "dnd")   # skipper-modes: in ask nobody but the owner answers; in dnd what is relayed is the held slice


def anchor_of(pid):
    """The anchor key of the scope PID's lease names, or None: the repo task_mode reads a scope's mode
    by — a registry key, never a path a scope's glob could take."""
    try:
        rec = leaselib.read(pid)
        return scope_repos(rec["scope"])[0] if rec else None
    except (Refused, leaselib.Unreadable, KeyError):
        return None


def ask_mode(pid, t, a=None):
    """The mode a question was asked in: the ask's recorded mode (bin/ask relay writes it) as the hint
    `ask answer` reads it by, else the task's, the plan's or the scope's (helmlib.task_mode, read by the
    scope's anchor key). Any fault is the default's, as ask_guard reads it."""
    hint = (a or {}).get("mode")
    try:
        return helmlib.task_mode(pid, t["id"], anchor_of(pid), hint)[0]
    except Exception:   # noqa: BLE001
        return hint or "default"


def doc_answer(a):
    """True when the ask's doc (bin/ask relay's `doc`) shows its ➤ Answer filled: an answer through
    keel's form or GitHub reaches the doc, not the ship's events. Read by keel's own parser, once a doc
    a pass; no doc, no keel or an unreadable one: not answered."""
    doc = a.get("doc")
    if not doc:
        return False
    cache = _PASS.setdefault("docs", {}) if _PASS is not None else {}
    if doc not in cache:
        cache[doc] = {}
        try:
            from importlib.machinery import SourceFileLoader
            k = helmlib.peer("keel")
            if k:
                m = _PASS.get("keel") if _PASS is not None else None
                if m is None:
                    m = SourceFileLoader("keel_for_skipper", str(k)).load_module()
                    if _PASS is not None:
                        _PASS["keel"] = m
                _, items, _ = m.parse(Path(doc).read_text(encoding="utf-8"))
                cache[doc] = {i.get("id"): bool(str(i.get("answer") or "").strip()) for i in items}
        except (Exception, SystemExit):   # noqa: BLE001 — a doc keel cannot read is unanswered
            cache[doc] = {}
    return bool(cache[doc].get(a["ref"].rpartition("#")[2]))


def owners_ask(pid, t, a):
    """True when the open question is the owner's, not a skipper's: escalated, asked in mode ask or dnd,
    or answered already in its doc."""
    return bool(a.get("escalated")) or ask_mode(pid, t, a) in OWNER_MODES or doc_answer(a)


def open_asks(pid):
    """[(task, ask)] of the ship's open asks a skipper may answer: on blocks that are not the owner's
    alone, and not the owner's (owners_ask)."""
    try:
        tasks = tasks_of(pid)
    except (FileNotFoundError, ValueError):
        return []
    return [(t, a) for t in tasks if t["status"] not in helmlib.ENDED and not waits_on_owner(t, pid)
            for a in t["asks"] if a.get("open") and not owners_ask(pid, t, a)]


def hails(pid):
    return [r for r in (helmlib.load_plan(pid) or {}).get("relayed") or [] if isinstance(r, dict)]


# A re-hail is a script's send: Talk, else the file queue — never SendMessage, which is a model's
# tool (asklib's backend only says "call SendMessage"), so the tick could never make it. wharf-runs'
# hail sends from scripts in the same order.
REHAIL_ROADS = ("talk", "file")
REHAIL_TRIES = 3                 # per (question, gen): a road that did not wake the holder is tried again next pass, this often
# What wakes the holder: only Talk — its ear is `ask listen`. A line the file road queued waits for a
# prompt an idle skipper never gets (a Remote Control message would print it), so a queued re-hail is
# a try, never a delivery, and a run's relay by file never counts as heard (round 2 of the review).
DELIVERED = ("sent",)
# a run's own relay that woke the holder: Talk alone, which bin/ask relay sends itself. Its sendmessage
# road only tells the run's model to call SendMessage, and nothing records that it did — counted as
# heard, a run that never called it would make the holder deaf for a question it never got; as it is,
# the question is re-hailed by Talk (a duplicate at worst)
HEARD = ("talk",)
# the registry's statuses of a session that is not working a turn: idle, or stopped at a dialog
# (`waiting` on a permission prompt) — either way it answers nothing (round 2 of the review)
STILL = ("idle", "waiting")


def reached(a, lease, pid=None, t=None):
    """True when the ask's own relay woke this holder after it took the ship: bin/ask relay's `to` is
    the holder, by a road that wakes it (HEARD). A relay heard in an owner mode, of a question judged
    in a skipper mode now (the ship raised since), is not: the brief told the holder to leave it
    carded, so it is re-hailed in the new mode and the deaf rule counts from that re-hail (the
    finish review of the rebased branch)."""
    if pid is not None and t is not None and a.get("mode") in OWNER_MODES \
            and ask_mode(pid, t, a) not in OWNER_MODES:
        return False
    return bool(lease.get("session")) and a.get("to") == lease.get("session") and a.get("backend") in HEARD \
        and float(a.get("relayed_at") or 0) >= float(lease.get("since") or 0)


def elsewhere(a, lease):
    """True when the ask's relay went to another session that may be live — on this Mac by its
    registry; on another Mac (`to_host`) always, since its registry is not readable here and a re-hail
    would have two sessions answer one question: that session's question, never re-hailed here nor
    charged to this holder."""
    to = a.get("to")
    if not to or to == lease.get("session"):
        return False
    if a.get("to_host") and a["to_host"] != helmlib.host():
        return True
    reg = registry_of(to)
    return bool(reg) and pid_alive(reg.get("pid"))


def due_rehail(pid, lease):
    """[(task, ask)] the holder has not heard: no relay of its own reached it, none went to another live
    session, and no re-hail at its gen was delivered (or tried REHAIL_TRIES times). An ask whose relay
    found no road (`to` None) is due too, whenever it was asked. An event from before S5 carries no
    `to`: due only when it was asked before the take, the rule it was judged by."""
    gen = lease["gen"]
    tries, done = {}, set()
    for r in hails(pid):
        if r.get("gen") != gen:
            continue
        tries[r.get("question")] = tries.get(r.get("question"), 0) + 1
        if r.get("verdict") in DELIVERED:
            done.add(r.get("question"))
    since = float(lease.get("since") or 0)
    out = []
    for t, a in open_asks(pid):
        if a["ref"] in done or tries.get(a["ref"], 0) >= REHAIL_TRIES or reached(a, lease, pid, t) or elsewhere(a, lease):
            continue
        if "to" not in a and float(a.get("opened") or 0) >= since:
            continue
        out.append((t, a))
    return out


def rehail(pid, lease, act):
    """Every open question of the ship the holder has not heard (due_rehail), hailed to it by a script's
    road and recorded per (question, gen) in the plan's `relayed` list — so a question asked of a lapsed
    skipper, while the yard held the ship, or by a run whose relay found nobody, never waits in a dead
    session. Lines."""
    import asklib
    import surfaces
    scope = lease.get("scope")
    gen = lease["gen"]
    due = due_rehail(pid, lease)
    if not due:
        return []
    ctx = asklib.standing_manager(scope=scope)
    if not ctx or ctx.get("manager") != lease.get("session"):
        return []   # the holder has no live record here: the deaf rule and the lapse decide
    roads = [b for b in surfaces.row("ask.relay") if b in REHAIL_ROADS]
    evs = ask_events(pid)
    lines = []
    for t, a in due:
        if not act:
            lines.append("would re-hail %s %s to %s at gen %d" % (pid, a["ref"], holder(scope), gen))
            continue
        text = rehail_line(pid, lease, t, a, evs.get(a["ref"]) or {})
        name, verdict, detail, _ = asklib.relay(dict(ctx, session=None, plan=pid), text, roads)
        with helmlib.locked(pid):
            plan = helmlib.load_plan(pid)
            if plan is not None:
                plan.setdefault("relayed", []).append({"question": a["ref"], "gen": gen, "t": helmlib.now(), "to": lease.get("session"),
                                                       "backend": name, "verdict": verdict, "task": t["id"]})
                helmlib.save_plan(plan)
        lines.append("re-hailed %s %s to %s at gen %d: %s (%s)" % (pid, a["ref"], holder(scope), gen, verdict, name or detail))
    return lines


def rehail_line(pid, lease, t, a, ev):
    """The ASK line a re-hail carries: bin/ask relay's shape (an ASK prefix, so `ask listen` wakes on
    it), the reply naming the doc where it is (the relay's `doc`: the run's worktree, not the main
    checkout) and --plan, and a guarded repo's text left out as relay leaves it (K6)."""
    repo_dir = ev.get("repo") or ""
    repo = Path(repo_dir).name or "?"
    rel, _, item = a["ref"].rpartition("#")
    guarded = helmlib.guarded(repo)
    title = "an ask in a guarded session" if guarded else (a.get("summary") or "")
    rec = "—" if guarded else " ".join((a.get("recommended") or "").split()) or "none"
    asker = ev.get("session") or "?"
    doc = a.get("doc") or (str(Path(repo_dir) / rel) if repo_dir else rel)
    # the relay's own road back (its --to-account, --space when the run listens on Talk, --send-only for
    # a run on another Mac), as bin/ask relay wrote it into the ship's event: without them the answer
    # reaches a listening or remote run only as a commit it may never read (round 2 of the review)
    flags = str(ev.get("reply_flags") or "")
    # the mode the question is judged in (ask_mode, as owners_ask judged it), never the ask's recorded
    # hint alone: a ship raised from ask to default since would re-hail `mode: ask`, which the brief
    # leaves carded, and the deaf rule would fire (the fifth finish review)
    m = ask_mode(pid, t, a)
    mode = " — mode: %s" % m if (a.get("mode") or m != "default") else ""
    return ("ASK %s %s — %s — Reversible: %s — Recommended: %s%s — doc: %s:%s — from: %s — re-hailed to %s at gen %d "
            "after a hand-over (asked of an earlier holder, while the yard held the ship, or with no road) — reply: "
            "%s answer %s %s \"<text>\" --from %s --to %s --task %s%s --plan %s" % (
                repo, item, title, a.get("reversible") or "unmarked", rec, mode, repo, rel, asker, holder(lease.get("scope")),
                lease["gen"], tool_cmd("ask"), doc, item, screen_name(lease.get("scope")), asker, t["id"], flags, pid))


def deaf(pid, lease, now):
    """The question the holder has not answered in DEAF while its session is not working a turn (idle,
    or stopped at a dialog: STILL), or None. Only a question that woke this holder counts: a run's
    relay to it after it took the ship by Talk (HEARD), or a re-hail at its
    gen that Talk sent. A queued line is never heard (it is re-hailed by Talk instead), and a question
    relayed to another session is that one's. DEAF counts the holder's own time only: minutes inside a
    studio brake's window are not its (S13a)."""
    reg = registry_of(lease.get("session"))
    if not reg or reg.get("status") not in STILL:
        return None
    hailed = {}
    for r in hails(pid):
        if r.get("gen") == lease["gen"] and r.get("verdict") in DELIVERED:
            hailed[r.get("question")] = max(hailed.get(r.get("question"), 0), float(r.get("t") or 0))
    for t, a in open_asks(pid):
        ats = [hailed.get(a["ref"]) or 0]
        if reached(a, lease, pid, t):
            ats.append(float(a.get("relayed_at") or 0))
        at = max(ats)
        # the time the studio brake froze the holder is never charged (helmlib.braked_within, S13a)
        quiet = now - at - helmlib.braked_within(at, now) if at else 0
        if at and quiet > DEAF:
            return "%s %s unanswered %dm, the session %s" % (pid, a["ref"], quiet // 60, reg.get("status"))
    return None


# ---------------------------------------------------------------------------- the rotation

def context_of(session):
    """The context tokens of the session's last main-thread call (input, cache read and cache write),
    or None when its transcript is not on this host or holds no call — then age alone rotates it. Claude
    Code's own `<synthetic>` entries (an API error, "No response requested.") carry zero usage and are
    no call: skipped, as helmlib.session_cost skips them."""
    p = helmlib.transcript(session) if session else None
    if not p:
        return None
    try:
        with p.open("rb") as f:
            f.seek(0, 2)
            f.seek(max(0, f.tell() - TAIL_BYTES))
            lines = f.read().decode("utf-8", "replace").splitlines()
    except OSError:
        return None
    for raw in reversed(lines):
        if '"assistant"' not in raw:
            continue
        try:
            r = json.loads(raw)
        except ValueError:
            continue
        msg = r.get("message") or {}
        if r.get("type") != "assistant" or r.get("isSidechain") or msg.get("model") == "<synthetic>":
            continue
        u = msg.get("usage") or {}
        ctx = (u.get("input_tokens") or 0) + (u.get("cache_read_input_tokens") or 0) \
            + (u.get("cache_creation_input_tokens") or 0)
        if ctx:
            return ctx
    return None


def rotate_why(rec, ls, now):
    """Why the healthy skipper REC hands over now (the rotation), or None. Due when ROTATE_AGE old, or
    past ROTATE_CONTEXT once ROTATE_CONTEXT_AFTER old; and only when quiet: its session idle for
    QUIET_FOR (the registry's; one stopped at a dialog is the deaf rule's) with no question of its own
    open — one that is not another live session's (elsewhere) on a ship it holds, so one it is working on
    is never cut off. The cheap reads first, the transcript last. A scope that is never quiet meets the
    daily ceiling instead."""
    age = now - float(rec.get("started") or now)
    if age < min(ROTATE_AGE, ROTATE_CONTEXT_AFTER):
        return None
    sess = rec.get("session")
    reg = registry_of(sess)
    if not reg or reg.get("status") != "idle":
        return None
    since = float(reg.get("statusUpdatedAt") or reg.get("updatedAt") or 0) / 1000
    if helmlib.now() - since < QUIET_FOR:
        return None
    for p, lease in ls:
        if lease.get("session") == sess and any(not elsewhere(a, lease) for _, a in open_asks(p)):
            return None
    if age >= ROTATE_AGE:
        return "rotated: %dh old, quiet" % (age // 3600)
    ctx = context_of(sess)
    if ctx is not None and ctx >= ROTATE_CONTEXT:
        return "rotated: its context %dk tokens, quiet" % (ctx // 1000)
    return None


# ---------------------------------------------------------------------------- the tick's pass

def scopes_here():
    """The scopes with a lease or a record on this host."""
    out = {rec.get("scope") for _, rec in leaselib.leases() if isinstance(rec, dict) and rec.get("scope")}
    pre = "%s-" % helmlib.host()
    try:
        for p in manager_dir().glob(pre + "*.json"):
            out.add(p.name[len(pre):-len(".json")])
    except OSError:
        pass
    return sorted(x for x in out if x)


def belt_path():
    import stalls_tick
    return stalls_tick.state_dir() / "skippers.json"


def belt_read():
    try:
        d = json.loads(belt_path().read_text())
    except (OSError, ValueError):
        return {}
    return d if isinstance(d, dict) else {}


def belt_write(d):
    p = belt_path()
    p.parent.mkdir(parents=True, exist_ok=True)
    tmp = p.with_name(".%s.%d" % (p.name, os.getpid()))
    tmp.write_text(json.dumps(d, sort_keys=True))
    tmp.replace(p)


def ensure(act, why_not=None):
    """One pass over every scope here (the tick's, after wharf's): lines. With act False (a disarmed,
    dry or session-run tick) every verdict is printed as `would …` and nothing is written."""
    global _PASS
    now = clock()
    scopes = scopes_here()
    if not scopes:
        return []   # no lease and no record here: nothing read or written, the tick as before S5
    _PASS = {}   # a pass's own writes are lease events and the plan's `relayed` list, neither in the tasks
    belt = belt_read()
    lines = []
    try:
        try:
            dl = float(os.environ.get("STALLS_DEADLINE") or 0)
        except ValueError:
            dl = 0
        for scope in scopes:
            # the poll's kill time, read again before each scope: a stop and a start take launchctl and
            # screen calls of up to 30 s each, and the pass is killed with whatever it began
            if dl and dl - time.time() < 60:
                lines.append("skippers: %s and after left to the next pass — %ds before the tick's kill time"
                             % (holder(scope), max(0, dl - time.time())))
                break
            try:
                lines += [x if holder(scope) in x else "%s: %s" % (holder(scope), x) for x in ensure_scope(scope, act, now, belt)]
            except Exception as e:   # noqa: BLE001 — one scope's bad record costs that scope's pass, never the others'
                lines.append("%s: the pass failed (%s: %s)" % (holder(scope), e.__class__.__name__, str(e)[:200]))
    finally:
        _PASS = None
    if act:
        belt_write(belt)
    if lines and not act and why_not:
        lines.append("skippers: nothing done — %s" % why_not)
    return lines


def ensure_scope(scope, act, now, belt):
    """The scope's pass, in order, one stop or one start at most: a lapse handed to the yard, a deaf
    holder handed over, the last start's verdict, the re-hail, a sidecar that takes nothing, the belt,
    the rotation (rotate_why), the daily hand-over, and a start when a ship needs one and nothing live or pending holds it."""
    out, stopped = [], None
    host = helmlib.host()
    w = "" if act else "would "
    # the leases' and the events' own clock: they are stamped with helmlib.now(), never STALLS_NOW,
    # which pins only what the tick judges by its own (the record's age, the belt, the hour)
    real = helmlib.now()
    rec = read_record(scope)
    ls = [(p, r) for p, r in leaselib.leases(scope)]
    gone = set()   # sessions handed over in this pass

    # a lapse: the holder's lease ran past its until (its sidecar died with its claude, or alone)
    for pid, lease in ls:
        if lease["holder"] != leaselib.YARD and leaselib.lapsed(pid, now=real, rec=lease):
            if act:
                try:   # under the plan's lock, still lapsed at the gen read: a renewal in between keeps it
                    leaselib.hand_back(pid, lease["gen"], lease.get("session"), "lapsed: %s past its until" % lease["holder"],
                                       event="lease lapsed", only_lapsed=True)
                except (leaselib.Refused, leaselib.Unreadable, OSError) as e:   # a torn record or a plan gone: this ship only
                    out.append(str(e))
                    continue
            out.append("%shand %s to the yard: lease lapsed (gen %d, %s)" % (w, pid, lease["gen"], str(lease.get("session"))[:8]))
            gone.add(lease.get("session"))
    # deaf: a question reached the holder 15 minutes ago and it sits idle — the same hand-over
    for pid, lease in ls:
        if lease["holder"] == leaselib.YARD or lease.get("session") in gone:
            continue
        d = deaf(pid, lease, real)
        if d:
            for p2, l2 in ls:
                if l2.get("session") == lease.get("session") and l2["holder"] != leaselib.YARD:
                    if act:
                        try:
                            leaselib.hand_back(p2, l2["gen"], l2.get("session"), "lapsed: deaf — %s" % d, event="lease lapsed")
                        except (leaselib.Refused, leaselib.Unreadable, OSError) as e:
                            out.append(str(e))
                            continue
                    # handed over (or would be): only then is the holder gone, and stopped below — a
                    # skipper whose every hand-back failed still holds its ships (the fix review)
                    gone.add(lease.get("session"))
                    out.append("%shand %s to the yard: lapsed: deaf (%s)" % (w, p2, d))
    if rec and rec.get("session") in gone:
        stopped = "its lease was handed over"
    ls = [(p, r) for p, r in leaselib.leases(scope)] if act else ls

    # the last start's verdict
    log_ = starts(scope)
    alive = record_alive(rec)
    # the record is written just before exec (the launcher is asked before it), so for a while its claude lives but has no registry
    # record yet: within TAKE_WITHIN a live pid is a start still coming up, never a failure
    proc = bool(rec) and pid_alive(rec.get("pid"))
    taken = took(scope, rec.get("session")) if rec else False
    # its own minutes since the start: a start the studio brake froze before its take is no failed start (S13a)
    own = (now - float(rec.get("started") or 0) - helmlib.braked_within(float(rec.get("started") or 0), now)) if rec else 0
    young = bool(rec) and own <= TAKE_WITHIN
    if not stopped and rec:
        sid8 = str(rec.get("session"))[:8]
        if taken and not outcome(log_, rec.get("start")) and act:
            log_start(scope, "took", rec.get("start"), session=rec.get("session"))
        if not taken and not proc:
            stopped = "failed start: its claude ended without taking a ship"
        elif not taken and not young:
            stopped = "failed start: no ship taken in %dm (a dialog, a refused tool)" % (own // 60)
        elif taken and not alive:
            stopped = "its claude has ended (session %s)" % sid8
            # an end within CRASH_WITHIN of the start is a failed start too, though it took a ship:
            # a skipper that takes and then crashes would otherwise reset the count every time and be
            # restarted forever with nothing on the board (the third review of S5)
            # its own minutes, as TAKE_WITHIN's: a skipper the brake froze that crashes soon after is still a failed start (S13a)
            if own < CRASH_WITHIN and not any(x.get("event") == "failed" and x.get("start") == rec.get("start") for x in log_):
                why = "its claude ended %dm after its start, having taken a ship" % (own // 60)
                if act:
                    log_start(scope, "failed", rec.get("start"), why=why, session=rec.get("session"))
                else:
                    log_ = log_ + [{"event": "failed", "start": rec.get("start"), "why": why, "t": now}]
        if stopped and stopped.startswith("failed start") and not outcome(log_, rec.get("start")):
            if act:
                log_start(scope, "failed", rec.get("start"), why=stopped[len("failed start: "):], session=rec.get("session"))
            else:
                log_ = log_ + [{"event": "failed", "start": rec.get("start"), "why": stopped, "t": now}]
    elif not stopped and not rec:
        last = next((x for x in reversed(log_) if x.get("event") == "launched"), None)
        if last and not outcome(log_, last.get("start")) and now - float(last.get("t") or 0) > TAKE_WITHIN:
            # the runner logs its session when it writes the record: a start whose session took a ship
            # and then stood down (its record deleted) before any armed pass saw it took, all the same
            sess = next((x.get("session") for x in reversed(log_)
                         if x.get("event") == "recorded" and x.get("start") == last.get("start")), None)
            if sess and took(scope, sess):
                if act:
                    log_start(scope, "took", last.get("start"), session=sess)
            else:
                why = ("its claude ended without taking a ship" if sess
                       else "the runner wrote no record in %dm (launchd or screen)" % (TAKE_WITHIN // 60))
                out.append("%srecord failed start %s: %s" % (w, last.get("start"), why))
                if act:
                    log_start(scope, "failed", last.get("start"), why=why, session=sess)
                    for x in labels(scope):
                        boot_out(x)
                else:
                    log_ = log_ + [{"event": "failed", "start": last.get("start"), "why": why, "t": now}]
    # what this pass wrote counts below: no fourth start in the pass that logged the third failure
    log_ = starts(scope) if act else log_

    healthy = bool(rec) and not stopped and alive and taken
    need = {p: needs(p)[0] for p, _ in ls}
    work = [p for p, r in ls if r["holder"] == leaselib.YARD and need[p]]
    wanted = any(need.values())
    if healthy:
        for pid, lease in ls:
            if lease.get("session") == rec.get("session"):
                out += rehail(pid, lease, act)
        # waited since the yard's hold or the start, whichever is later, less the brake's time (S13a): a
        # sidecar the brake froze has taken nothing for that long through no fault of its own
        def waited(r):
            s = max(float(r.get("since") or 0), float(rec.get("started") or 0))
            return real - s - helmlib.braked_within(s, real)
        stale = [p for p, r in ls if r["holder"] == leaselib.YARD and p in work and waited(r) > leaselib.TTL]
        if stale:
            stopped = "its sidecar has taken %s in %dm" % (", ".join(stale), leaselib.TTL // 60)
    b = belt.setdefault(scope, {})
    if rec and b.get("start") != rec.get("start"):
        # the idle mark is one start's: a skipper that stood down by itself leaves its mark, and the next
        # start must get its own 30 minutes
        b.clear()
        b["start"] = rec.get("start")
    if healthy and not stopped:
        if wanted:
            b.pop("idle_since", None)
        else:
            b.setdefault("idle_since", now)
            if now - float(b["idle_since"]) >= IDLE_STOP:
                stopped = "no ship has needed it for %dm" % ((now - float(b["idle_since"])) // 60)
        if not stopped and wanted:
            stopped = rotate_why(rec, ls, now)
        if not stopped and now - float(rec.get("started") or now) > DAILY and time.localtime(now).tm_hour == DAILY_HOUR:
            stopped = "the daily hand-over (%dh old at the 0%d:00 pass)" % ((now - float(rec["started"])) // 3600, DAILY_HOUR)
    if stopped:
        b.pop("idle_since", None)
        # an end within CRASH_WITHIN of the start, whatever ended it — a crash, a lapse, deafness, a
        # sidecar that takes nothing — is a failed start, so that a skipper that never works its ships
        # is not restarted every pass for ever (the review of the S5 branch); the belt and the daily
        # hand-over end a skipper that did its work, and a failed start is logged above already
        if rec and now - float(rec.get("started") or 0) < CRASH_WITHIN and not stopped.startswith(("no ship has", "rotated", "the daily")) \
                and not any(x.get("event") == "failed" and x.get("start") == rec.get("start") for x in log_):
            why = "%s, %dm after its start" % (stopped, (now - float(rec.get("started") or 0)) // 60)
            if act:
                log_start(scope, "failed", rec.get("start"), why=why, session=rec.get("session"))
            else:
                out.append("would record failed start %s: %s" % (rec.get("start"), why))
        if act:
            out += stop(scope, stopped, by="tick")
        else:
            out.append("would stop: %s" % stopped)
        return out

    # a start: a ship the yard holds needs a skipper, and nothing live or pending holds the scope
    if not work:
        return out
    if rec and (alive or (proc and young)):
        return out + (["waits: start %s is %ds old, no ship taken yet" % (rec.get("start"), now - float(rec.get("started") or 0))]
                      if not taken else [])
    fails = consecutive_failures(log_)
    if len(fails) >= FAILS and now - float(fails[0].get("t") or 0) < RETRY_AFTER:
        return out + ["won't start: %d failed starts in a row (last: %s) — raised as `skipper won't start`; the tick tries "
                      "once more an hour after the last, and `helm skipper --start %s` from a shell here tries now"
                      % (len(fails), fails[0].get("why"), scope)]
    last = next((x for x in reversed(log_) if x.get("event") == "launched"), None)
    if last and not outcome(log_, last.get("start")) and now - float(last.get("t") or 0) <= TAKE_WITHIN:
        return out + ["waits: start %s launched %ds ago" % (last.get("start"), now - float(last["t"]))]
    if not act:
        return out + ["would start %s (%s)" % (holder(scope), ", ".join(work))]
    _, said = start(scope, by="tick")
    return out + said


# ---------------------------------------------------------------------------- the stall road

def wont_start_stalls(host=None):
    """[(scope, [failure lines, newest first], {anchor, guarded})] for each scope here whose last FAILS
    starts failed and that still needs a skipper — the registry still names it and a ship of it is
    live: bin/stalls.py raises each as the class `skipper won't start`. `guarded` is true when a repo
    of the scope is guarded or the scope is confidential: the card then carries none of the failure
    text (repo keys, login labels, the anchor's path), as every guarded card on the board."""
    host = host or helmlib.host()
    pre = "%s-" % host
    out = []
    try:
        files = sorted(manager_dir().glob(pre + "*.starts.jsonl"))
    except OSError:
        return []
    for p in files:
        scope = p.name[len(pre):-len(".starts.jsonl")]
        fails = consecutive_failures(starts(scope, host))
        if len(fails) < FAILS or not any(needs(p)[0] for p, _ in leaselib.leases(scope)):
            continue
        try:
            anchor, keys = scope_repos(scope)
        except Refused:
            continue   # the scope is gone from the registry, or it will not read: nothing to raise for it
        try:
            conf = scope in helmlib._common().confidential_scopes()
        except (ImportError, AttributeError):
            conf = True   # cannot tell: the card is guarded
        out.append((scope, fails, {"anchor": anchor, "guarded": conf or any(helmlib.guarded(k) for k in keys)}))
    return out


def main(argv):
    if len(argv) == 3 and argv[0] == "run":
        return run(argv[1], argv[2])
    print("usage: skipperlib.py run SCOPE START_ID  (libexec/skipper-run's; nobody else's)", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
