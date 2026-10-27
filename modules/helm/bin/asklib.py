"""The relay seam (S1) of session-asks: one sender, two callers (bin/ask, bin/plan; memo notify, E15,
is to be the third). docs/session-asks-2026-10-09.md R4.

Every backend has the same four functions — available(ctx), send(ctx, text), receive(ctx),
describe() — so an internal replacement is one more class, never a rewrite. Which backends are
tried, in which order, is `ask.relay` in settings/surfaces.json. Stdlib only, Python 3.9, nothing
of Claude's imported (R8): CLAUDE_CODE_SESSION_ID is read only as one of the ids accepted.

The context (`ctx`) a backend reads, all optional:
    manager          the manager's session id (DISPATCH_SKIPPER, or the older DISPATCH_MANAGER)
    manager_host     the Mac the manager runs on (DISPATCH_SKIPPER_HOST, or DISPATCH_MANAGER_HOST)
    manager_account  the manager's login: its config dir, or a registry label ('' = ~/.claude)
    account          this session's login, in either form — account_home() makes both one
    space            the manager's plan page (uuid or link; DISPATCH_PLAN_SPACE) — the Talk address
    session          this session's id
    plan             the ship id (DISPATCH_SHIP, or DISPATCH_PLAN)
    standing         set by with_standing(): the manager is the Mac's standing one (stray-manager M5)
"""
import json
import os
import re
import shlex
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent


def _common():
    """The regatta core's common.py through lib/find_core.py, loaded on first use; None when there
    is no core. Never exits: keel's Stop lint loads this file alone (G24), and a missing core must
    cost that caller one check, not the hook."""
    if "common" in sys.modules:
        return sys.modules["common"]
    lib = str(HERE.parent / "lib")
    if lib not in sys.path:
        sys.path.insert(0, lib)
    try:
        import find_core
        hooks = find_core.hooks()
    except (ImportError, SystemExit):
        return None
    if hooks not in sys.path:
        sys.path.insert(0, hooks)
    try:
        import common
    except Exception:
        return None
    return common


def _peer(name):
    """A peer's file through the core's tool() (keel's sheep, plumb's attention.py), or None."""
    c = _common()
    return c.tool(name) if c else None


# P2 (2026-10-10): Python's default agent gets Cloudflare's 403 code 1010 on the Talk service's
# hosts; a curl agent passes. Every call here sets it.
UA = "curl/8.7.1 (bin/ask)"
TIMEOUT = 20


def talk_url():
    """The Talk service's base URL: $SPACESHEEP_URL, else the config dir's `helm/talk-url` (the
    overlay writes it); "" when neither names one, and the talk backend says so."""
    v = os.environ.get("SPACESHEEP_URL")
    if v:
        return v.rstrip("/")
    c = _common()
    return (c.config_line("helm/talk-url") if c else "").rstrip("/")


def owner():
    """The owner's name, lower-case, as the core reads it (`regatta/owner`); `owner` without one."""
    c = _common()
    return ((getattr(c, "OWNER_NAME", "") if c else "") or "owner").lower()


def _home():
    return Path(os.environ.get("HOME") or Path.home())


def sessions_dir():
    """The shared registry: every login dir's sessions/ links to ~/.claude/sessions."""
    return Path(os.environ.get("ASK_SESSIONS_DIR") or _home() / ".claude" / "sessions")


def queue_dir():
    return Path(os.environ.get("ASK_QUEUE_DIR") or _home() / "Library/Logs/claude-weekly/asks")


def sheep_cli():
    """The Talk service's CLI, `spacesheep` (memo's sheep_bin order): $MEMO_SHEEP_BIN, PATH, ~/.local/bin, Homebrew."""
    import shutil
    if "MEMO_SHEEP_BIN" in os.environ:
        c = os.environ["MEMO_SHEEP_BIN"]
        return c if c and os.access(c, os.X_OK) else None
    for c in (shutil.which("spacesheep"), str(_home() / ".local/bin/spacesheep"), "/opt/homebrew/bin/spacesheep"):
        if c and os.access(c, os.X_OK):
            return c
    return None


def sheep_key():
    """SPACESHEEP_KEY: the environment, else the overlay's .env through bin/sheep's reader, else the
    CLI's stored login — bin/keel's sheep_key order. Never printed."""
    if os.environ.get("SPACESHEEP_KEY"):
        return os.environ["SPACESHEEP_KEY"].strip().strip("'\"")
    if os.environ.get("ASK_NO_KEY_FILES"):  # tests
        return None
    try:
        from importlib.machinery import SourceFileLoader
        v = SourceFileLoader("sheep_tool", str(_peer("sheep"))).load_module().env_value("SPACESHEEP_KEY")
        if v:
            return v.strip().strip("'\"")
    except Exception:  # Drive offline, no Full Disk Access, no bin/sheep (a cloud VM)
        pass
    cfg = Path(os.environ.get("SPACESHEEP_CONFIG_DIR") or Path(os.environ.get("XDG_CONFIG_HOME") or _home() / ".config") / "spacesheep") / "config.json"
    try:
        return (json.loads(cfg.read_text()).get("key") or "").strip() or None
    except (OSError, ValueError):
        return None


def sheep_env(cli):
    """The CLI's environment: the key as sheep_key() finds it, the CLI's folder first on PATH (node)."""
    env = dict(os.environ)
    k = sheep_key()
    if k:
        env["SPACESHEEP_KEY"] = k
    env["PATH"] = os.pathsep.join([str(Path(cli).parent), env.get("PATH", ""), "/opt/homebrew/bin"])
    return env


def sheep_plan(refresh=False, cached_only=False):
    """The account's plan through the core's sheep_plan() (cached an hour): no CLI here is "none",
    never an error; no core is None, and every caller then behaves as before plans were read."""
    c = _common()
    if not c or not hasattr(c, "sheep_plan"):
        return None
    cli = sheep_cli()
    try:   # a cached read runs no CLI, so it needs no key (sheep_env reads .env through bin/secrets)
        env = sheep_env(cli) if cli and not cached_only else None
        return c.sheep_plan(cli, env, refresh=refresh, cached_only=cached_only)
    except Exception:  # a hook's or a relay's read of the plan never costs it the relay
        return None


def space_id(space):
    """A page link or a uuid → the uuid (the last path part of /s/<uuid>), else the text as given."""
    s = (space or "").strip().rstrip("/")
    if "/s/" in s:
        return s.split("/s/", 1)[1].split("/", 1)[0]
    return s


def registry(session_id):
    """The registry record of a session id, or None. Several files may name one id (a session
    picked up again): the newest wins."""
    best = None
    try:
        files = list(sessions_dir().glob("*.json"))
    except OSError:
        return None
    for f in files:
        try:
            d = json.loads(f.read_text())
        except (OSError, ValueError):
            continue
        if d.get("sessionId") == session_id and (best is None or d.get("updatedAt", 0) > best.get("updatedAt", 0)):
            best = d
    return best


def pid_alive(pid):
    try:
        os.kill(int(pid), 0)
        return True
    except (OSError, ValueError, TypeError):
        return False


def this_host():
    """The Mac this runs on, as dispatch names it (laptop, buildbox): PLAN_HOST, DISPATCH_HOST, else
    the LocalHostName."""
    h = os.environ.get("PLAN_HOST") or os.environ.get("DISPATCH_HOST")
    if h:
        return h
    try:
        r = subprocess.run(["/usr/sbin/scutil", "--get", "LocalHostName"], capture_output=True, text=True, timeout=5)
        return r.stdout.strip().lower() or None
    except (OSError, subprocess.TimeoutExpired):
        return None


def elsewhere(ctx):
    """True when ctx's manager runs on another Mac than this one (manager_host names it)."""
    mh, here = ctx.get("manager_host"), this_host()
    return bool(mh and here and mh.lower() != here.lower())


# ---------------------------------------------------------------------------- a manager on a peer Mac

# A run on one Mac whose manager is a session on another has no registry here to read, and builds go
# to the build box while typed sessions run on the laptop. Before this, such a manager was `remote`,
# Talk's alone, and a manager with no plan page had no road at all: board-cleanup's D2 parked as "no
# skipper live" on the build box while its manager on the laptop was live (peer-manager-relay,
# 2026-10-26). Now one ssh to the manager's host reads its registry there: the hosts this Mac reaches
# are the config dir's `wharf-runs/ssh` (`<host>:<alias>`, as stalls and harness read them). ssh runs
# one way: a host with no alias here stays `remote`, as before.
PEER_CONNECT = 6    # ssh's ConnectTimeout, seconds (hail uses 6; stalls 10)
PEER_TIMEOUT = 30
_PEER_SEEN = {}     # (alias, session) → (answer, why): resolve(), File and the name read it once a process

# Runs on the peer under its own python3, stdlib only: the newest registry record of argv[1] and whether
# its pid lives. It reads the ssh login's registries: `~/.claude/sessions` and every Orca profile's own
# `sessions/` (lighthouse's `account` links one only where it can). A pid that answers EPERM belongs to
# another user, so it is not the manager's (the registry is this login's): dead, as pid_alive reads it.
PEER_PROBE = r'''
import glob, json, os, sys
from pathlib import Path
sid, best = sys.argv[1], None
regs = [str(Path.home() / ".claude" / "sessions")] + glob.glob(str(Path.home() / "Library" / "Application Support" / "orca" / "claude-profiles" / "*" / "home" / "sessions"))
for f in [Path(x) for r in regs for x in glob.glob(os.path.join(r, "*.json"))]:
    try:
        d = json.loads(f.read_text())
    except (OSError, ValueError):
        continue
    if isinstance(d, dict) and d.get("sessionId") == sid and (best is None or d.get("updatedAt", 0) > best.get("updatedAt", 0)):
        best = d
alive = False
if best:
    try:
        os.kill(int(best.get("pid")), 0)
        alive = True
    except (OSError, ValueError, TypeError):
        pass
rec = {k: best.get(k) for k in ("pid", "name", "status")} if best else None
print(json.dumps({"record": rec, "alive": alive}))
'''

# Appends LINE (set in front, as an ascii() literal) to the peer's file queue for argv[1]: the path
# queue_dir() and ask_guard.py's prompt hook read there by default.
PEER_QUEUE = r'''
import os, sys
from pathlib import Path
p = Path.home() / "Library/Logs/claude-weekly/asks" / ("%s.jsonl" % sys.argv[1])
p.parent.mkdir(parents=True, exist_ok=True)
fd = os.open(str(p), os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
try:
    os.write(fd, (LINE + "\n").encode())
finally:
    os.close(fd)
print(p)
'''


def peer_alias(host):
    """The ssh alias this Mac reads HOST over (the config dir's `wharf-runs/ssh`), or None: no host, this
    Mac, no line for it, no core."""
    return peer_hosts().get(host.lower()) if host else None


def peer_ssh(alias, argv, script, timeout=PEER_TIMEOUT):
    """(stdout, None) of `python3 - ARGV` with SCRIPT on its stdin on ALIAS, or (None, why). ASK_SSH stands
    in for ssh (tests)."""
    cmd = [os.environ.get("ASK_SSH") or "ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=%d" % PEER_CONNECT, alias,
           "python3 - " + " ".join(shlex.quote(a) for a in argv)]
    try:
        r = subprocess.run(cmd, input=script, capture_output=True, text=True, timeout=timeout)
    except (OSError, subprocess.TimeoutExpired) as e:
        return None, "ssh %s: %s" % (alias, e.__class__.__name__)
    if r.returncode != 0:
        return None, "ssh %s: %s" % (alias, ((r.stderr or "").strip().splitlines() or ["exit %d" % r.returncode])[-1][:160])
    return r.stdout, None


def peer_hosts():
    """{host: alias} of the peers `wharf-runs/ssh` names, this Mac left out; {} without the key or a core."""
    c = _common()
    try:
        lines = (c.config_lines("wharf-runs/ssh") if c else None) or []
    except Exception:
        return {}
    here = (this_host() or "").lower()
    out = {}
    for line in lines:
        name, _, alias = line.partition(":")
        if alias.strip() and name.strip() and name.strip().lower() != here:
            out[name.strip().lower()] = alias.strip()
    return out


# Runs on a peer: its live dispatched runs that relay over Talk (a manager, a plan page, not ended, a pid
# that lives), as {manager, topic}. dispatch-rc's same() also checks the pid's start time; this probe does
# not, so a reused pid can cost one extra listen reminder, never a missed relay.
PEER_RUNS_PROBE = r'''
import glob, json, os
from pathlib import Path
out = []
for f in glob.glob(str(Path.home() / "Library/Logs/claude-weekly/run-seed-runs" / "*.json")):
    try:
        st = json.load(open(f))
    except (OSError, ValueError):
        continue
    if not isinstance(st, dict) or not st.get("manager") or not st.get("plan_space") or st.get("ended"):
        continue
    try:
        os.kill(int(st.get("pid")), 0)
    except (OSError, ValueError, TypeError):
        continue
    out.append({"manager": st["manager"], "topic": st.get("topic") or "?"})
print(json.dumps(out))
'''
PEER_RUNS_TTL = 600   # keel's Stop hook asks every turn of every session; one ssh a peer per 10 minutes
PEER_RUNS_WAIT = 10   # …and waits at most this long for one, once a TTL


def peer_runs(cache_dir):
    """[{manager, topic, host}] of the live runs on every peer that relay over Talk, for keel's listen
    reminder (paste-paths manager_findings): a manager on the laptop of a run on the build box is told to
    listen as one of a local run is (peer-manager-relay). Cached PEER_RUNS_TTL in
    CACHE_DIR/peer-runs.json, shared by every session here; a peer that does not answer counts as none
    until the cache ages. Never raises."""
    p = Path(cache_dir) / "peer-runs.json"
    try:
        d = json.loads(p.read_text())
        if time.time() - float(d.get("t", 0)) < PEER_RUNS_TTL and isinstance(d.get("runs"), list):
            return d["runs"]
    except (OSError, ValueError, TypeError, AttributeError):
        pass
    # one refresher at a time (finish review): every session's Stop lands here once the cache ages, and
    # each would start its own ssh and wait; the others read none until the refresher writes. A marker a
    # killed refresher left goes stale after a TTL of its own.
    lock = Path(cache_dir) / "peer-runs.refreshing"
    try:
        Path(cache_dir).mkdir(parents=True, exist_ok=True)
        if lock.exists() and time.time() - lock.stat().st_mtime > PEER_RUNS_WAIT * 3:
            lock.unlink()
        os.close(os.open(str(lock), os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600))
    except FileExistsError:
        return []
    except OSError:
        pass
    try:
        return _peer_runs_read(p)
    finally:
        try:
            lock.unlink()
        except OSError:
            pass


def _peer_runs_read(p):
    runs = []
    for host, alias in sorted(peer_hosts().items()):
        out, _ = peer_ssh(alias, [], PEER_RUNS_PROBE, timeout=PEER_RUNS_WAIT)
        try:
            got = json.loads(out.strip().splitlines()[-1]) if out and out.strip() else []
        except ValueError:
            got = []
        runs += [dict(r, host=host) for r in got if isinstance(r, dict) and r.get("manager")] if isinstance(got, list) else []
    try:
        p.parent.mkdir(parents=True, exist_ok=True)
        tmp = p.with_suffix(".%d.tmp" % os.getpid())
        tmp.write_text(json.dumps({"t": int(time.time()), "runs": runs}))
        tmp.replace(p)
    except OSError:
        pass
    return runs


def peer_manager(ctx):
    """(alias, answer, why) for a manager on a peer this Mac reaches, or None when ctx's manager is not
    elsewhere or its host has no alias here. answer is the peer's {"record", "alive"}, None when the peer
    did not answer (why says so). One ssh per (alias, session) a process."""
    m = ctx.get("manager")
    if not m or not elsewhere(ctx):
        return None
    alias = peer_alias(ctx.get("manager_host"))
    if not alias:
        return None
    if (alias, m) not in _PEER_SEEN:
        out, why = peer_ssh(alias, [m], PEER_PROBE)
        ans = None
        if out is not None:
            try:
                ans = json.loads(out.strip().splitlines()[-1])
            except (ValueError, IndexError):
                why = "ssh %s: the probe printed no JSON" % alias
            if not isinstance(ans, dict):
                ans, why = None, why or "ssh %s: the probe printed no record" % alias
        _PEER_SEEN[(alias, m)] = (ans, why)
    return (alias,) + _PEER_SEEN[(alias, m)]


def manager_state(ctx):
    """('live' | 'gone' | 'remote', why) for ctx['manager'] (finding 4 of the launch review,
    2026-10-10): a record in this Mac's registry with a live pid is live, with a dead pid gone; no
    record on the manager's own Mac is gone too — a leftover plan dir is not a manager. A manager
    on another Mac (DISPATCH_MANAGER_HOST names it) is judged by that Mac's registry, read over the
    ssh alias `wharf-runs/ssh` names (peer-manager-relay): live, or gone on a dead pid. With no alias, a
    peer that does not answer, or no record there, it is 'remote', and only Talk can reach it. No host recorded and no
    record here reads as gone."""
    m = ctx.get("manager")
    if not m:
        return "gone", "no manager (DISPATCH_SKIPPER unset)"
    rec = registry(m)
    if rec:
        if pid_alive(rec.get("pid")):
            return "live", "pid %s" % rec.get("pid")
        return "gone", "the manager's session has ended (pid %s is gone)" % rec.get("pid")
    mh = ctx.get("manager_host")
    if elsewhere(ctx):
        peer = peer_manager(ctx)
        if not peer:
            return "remote", "on %s: its registry is not readable here (no ssh road to it in wharf-runs/ssh)" % mh
        alias, ans, why = peer
        if ans is None:
            return "remote", "on %s: its registry is not readable here (%s)" % (mh, why)
        prec = ans.get("record")
        if not prec:
            # a registry the probe cannot see (another login, a profile it does not glob, an id /clear
            # changed) is no proof of an end: Talk keeps the road it had (finish review)
            return "remote", "on %s: no record of it in the registries there" % mh
        if not ans.get("alive"):
            return "gone", "the manager's session has ended (pid %s on %s is gone)" % (prec.get("pid"), mh)
        return "live", "on %s, pid %s (its registry, over ssh %s)" % (mh, prec.get("pid"), alias)
    return "gone", "the manager's session has ended (no record in %s)" % sessions_dir()


def manager_dir():
    return Path(os.environ.get("ASK_MANAGER_DIR") or _home() / "Library/Logs/claude-weekly/manager")


def standing_manager(host=None, scope=None):
    """This Mac's standing manager as the ctx fields relay() needs, or None (stray-manager M5, B1).
    With a scope, the scope's skipper instead (skipper-resilience S5): `<manager_dir>/<host>-<scope>.json`,
    which bin/skipperlib.py's runner writes just before it execs claude (or claude-host). Without, the record is
    `<manager_dir>/<host>.json`, `{session, name, plan, space, account, host, started, pid}`, which
    bin/manager's runner was to write (stray-manager B2, superseded by the scope skippers: read, never
    written). Either is live when its pid is alive and the registry's record of its session has a live
    pid too — a crashed one leaves a record that reads as none. No record: None, and every caller does
    what it did before the seam."""
    h = host or this_host()
    if not h:
        return None
    try:
        rec = json.loads((manager_dir() / ("%s-%s.json" % (h, scope) if scope else "%s.json" % h)).read_text())
    except (OSError, ValueError):
        return None
    sid = rec.get("session") if isinstance(rec, dict) else None
    if not sid or not pid_alive(rec.get("pid")):
        return None
    reg = registry(sid)
    if not reg or not pid_alive(reg.get("pid")):
        return None
    out = {"manager": sid, "manager_host": h, "space": rec.get("space"), "plan": rec.get("plan"),
           "manager_account": rec.get("account") or "",
           "manager_name": rec.get("name") or ("skipper · %s" % scope if scope else "manager · %s" % h), "standing": True}
    if scope:
        out["scope"] = scope
    return out


def ship_scope(plan):
    """The scope of PLAN's lease (plans/<id>/skipper.json, skipper-resilience S4), or None: a ship with
    no lease, one that does not read, or no plan. A road, never a fence: anything unreadable is no
    scope, and the relay goes where it went before S5."""
    if not plan:
        return None
    try:
        # lazily, and from beside this file: keel's Stop lint and ask_guard load it alone, by path
        if str(HERE) not in sys.path:
            sys.path.insert(0, str(HERE))
        import leaselib
        rec = leaselib.read(plan)
    except Exception:   # noqa: BLE001 — Unreadable, no core, a bad id: no scope
        return None
    return rec.get("scope") if rec else None


def scope_skipper(plan=None):
    """The live skipper of the scope whose lease PLAN (else $DISPATCH_SHIP / $DISPATCH_PLAN) holds, as
    standing_manager() gives it, or None. Only a leased ship's relay goes to a scope skipper: its
    lifetime, its re-hail and its deaf rule all count leased ships' questions, so a relay for any
    other run stays the Mac's standing manager's, or nobody's (the third review of S5). No path is
    read for a scope: a scope's glob would take a worktree whose name it matches."""
    plan = plan or os.environ.get("DISPATCH_SHIP") or os.environ.get("DISPATCH_PLAN")
    scope = ship_scope(plan)
    return standing_manager(scope=scope) if scope else None


def resolve(ctx):
    """(ctx, (state, why)): where a relay from this run goes, decided once — ctx with the Mac's
    standing manager in place of a manager that is unset or gone (M1: a run with no live manager of
    its own is the standing manager's), and manager_state of the result. A remote or live manager
    stays. The run's own plan, if any, keeps its events; the Talk address is the standing manager's
    page. bin/ask relay resolves once and hands both to relay(), so the registry is read once a
    manager and the host once a run (review gate, 2026-10-16: it was twice and up to four times).
    The scope's skipper comes first (skipper-resilience S5) for a relay about a ship its scope leases
    (ctx["plan"]); the Mac's standing manager after it. A skipper's own relay (SKIPPER_SCOPE, which its
    runner sets) goes to neither: its escalation is the owner's, and a skipper relaying to itself
    would wake only itself."""
    if ctx.get("standing"):
        return ctx, ("live", "this Mac's standing manager" if not ctx.get("scope") else "the scope's skipper")
    st = manager_state(ctx) if ctx.get("manager") else ("gone", "no manager (DISPATCH_SKIPPER unset)")
    if st[0] != "gone":
        peer = peer_manager(ctx) if st[0] == "live" and not ctx.get("manager_name") else None
        if peer and peer[1] and (peer[1].get("record") or {}).get("name"):
            # the RELAYED line names a peer's manager as a local one is named: its registry name
            ctx = dict(ctx, manager_name=peer[1]["record"]["name"])
        return ctx, st
    if os.environ.get("SKIPPER_SCOPE"):
        return ctx, ("gone", "a skipper's own ask goes to the owner (skipper · %s relays to no skipper)" % os.environ["SKIPPER_SCOPE"])
    # each live by its own test: its pid and its session's registry pid
    sk = scope_skipper(ctx.get("plan"))
    if sk and sk.get("manager") == ctx.get("session"):
        sk = None
    sm = sk or standing_manager()
    if not sm:
        return ctx, st
    out = dict(ctx)
    out.update({k: v for k, v in sm.items() if k != "plan"})
    out["plan"] = ctx.get("plan") or sm.get("plan")
    out["stand_in"] = True   # put in for the caller's missing manager: relay() reads it (the file road)
    return out, ("live", "the scope's skipper" if sm.get("scope") else "this Mac's standing manager")


def with_standing(ctx):
    """resolve()'s ctx alone."""
    return resolve(ctx)[0]


# Who answered a relayed D-item, from bin/ask answer's line `Relayed from <who> (<source>, <date>):
# <text>` (bin/ask RELAYED_ANSWER). One predicate for bin/keel (taken_answer: an answer the owner
# never gave is `taken`, which rule D never launches) and bin/ask (log_relay: escalated vs answered),
# so the two never disagree (review gate, 2026-10-16: memo's own pattern failed open on a `who`
# holding a parenthesis, `--from "manager (buildbox)"`, and ask tested for the name anywhere in the
# source). The owner's only when the source names the owner (`regatta/owner`) AND one of the routes
# the owner's own word arrives on — the form, GitHub, chat, the Session tab signed on the owner's
# device; anything else (`manager`, `yes item`, the bare name, an unsigned tab line, a line this
# cannot parse) is somebody else's, so it fails closed.
OWNER_ROUTES = r"(?:'s|\u2019s|,)?\s+(?:form|github|chat|session tab(?:,\s*|\s+)\(?signed\)?)$"
RELAYED_HEAD_RE = re.compile(r"^\s*Relayed from (.*?), \d{4}-\d{2}-\d{2}\): ")


def owner_source(source):
    """True when a relayed answer's --source is one of the owner's routes (OWNER_ROUTES after the
    owner's name)."""
    return bool(re.match("^" + re.escape(owner()) + OWNER_ROUTES, " ".join(str(source or "").split()), re.I))


def relayed_by_owner(line):
    """None when line is not a `Relayed from` answer; else True when its source is the owner's.
    `who` may hold a parenthesis of its own (`manager (buildbox)`), the source too (`<owner>,
    Session tab (signed)`), so the text after every " (" of the head is tried as the source, and only
    one that runs whole to the date counts; a line with no date is not the owner's."""
    if not re.match(r"^\s*Relayed from ", line or ""):
        return None
    m = RELAYED_HEAD_RE.match(line)
    if not m:
        return False
    head, i = m.group(1), 0
    while True:
        i = head.find(" (", i)
        if i < 0:
            return False
        if owner_source(head[i + 2:]):
            return True
        i += 2


def __getattr__(name):
    """The predicate's name before the scrub (`relayed_by_<owner>`) for a caller that still uses it:
    keel's main called it so until its own scrub (which reads relayed_by_owner first). Any other
    `relayed_by_*` is the same test; anything else is the usual AttributeError."""
    if name.startswith("relayed_by_"):
        return relayed_by_owner
    raise AttributeError("module %r has no attribute %r" % (__name__, name))


def account_home(value):
    """One vocabulary for a login (finding 6): dispatch wrote the manager's from `account which`
    (nothing for the default dir) and the run's from `account pick` (a label, `claude-a`), so one
    account looked like two. A config dir or a label → the config dir's real path ('' → ~/.claude;
    a label through the account registry, ACCOUNTS_FILE in tests). A label the registry does not
    know is compared as written."""
    v = (value or "").strip()
    if not v:
        p = _home() / ".claude"
    elif "/" in v or v.startswith("~"):
        p = Path(os.path.expanduser(v))
    else:
        p = None
        try:
            # lighthouse's registry, by the config dir's key (C3), as bin/account reads it
            cfg = Path(os.environ.get("REGATTA_CONFIG") or _home() / ".config" / "regatta").expanduser()
            reg = json.loads(Path(os.environ.get("ACCOUNTS_FILE") or cfg / "lighthouse" / "accounts.json").read_text())
            common = _common()  # a `via: orca` row's dir is this Mac's read-back (docs/orca-accounts-2026-10-16.md)
            for a in common.account_rows(reg.get("accounts"), _home()):  # Orca's logins are rows too
                if a.get("label") == v and (a.get("provider") or "claude") == "claude":
                    p = common.account_home(a, _home())
                    break
        except (OSError, ValueError, AttributeError, ImportError):
            pass
        if p is None:
            return v
    try:
        return str(p.resolve())
    except OSError:
        return str(p)


def own_account():
    """This process's login, as account_home() spells it: $ASK_ACCOUNT (dispatch's), else the
    config dir it runs under."""
    return account_home(os.environ.get("ASK_ACCOUNT") or os.environ.get("CLAUDE_CONFIG_DIR") or "")


def same_named(rec):
    """Other live records carrying the same name (K2: `coding-50` twice): the cwd tells them apart."""
    if not rec or not rec.get("name"):
        return []
    out = []
    for f in sessions_dir().glob("*.json"):
        try:
            d = json.loads(f.read_text())
        except (OSError, ValueError):
            continue
        if d.get("name") == rec["name"] and d.get("sessionId") != rec.get("sessionId") and pid_alive(d.get("pid")):
            out.append(d)
    return out


# ---------------------------------------------------------------------------- backends

class Talk:
    """The Talk service (`helm/talk-url`): `POST /api/talk/send` as the owner, to a session that published `space`.
    The target is woken by its own background `spacesheep talk listen --once` (R4)."""
    name = "talk"

    def available(self, ctx):
        if not ctx.get("space") or not ctx.get("manager"):
            return False, "no plan space or manager id to address"
        if not sheep_key():
            if not sheep_cli():
                return False, "no SPACESHEEP_KEY and no spacesheep CLI: no spacesheep on this Mac — the file backend still relays here"
            return False, "no SPACESHEEP_KEY (environment, the overlay's .env or the CLI's login)"
        if not talk_url():
            return False, "no Talk service named (SPACESHEEP_URL, or the config dir's helm/talk-url)"
        # the plan (spacesheep talk status, cached an hour in the core's sheep dir): Free has no Talk,
        # and a send would only come back refused; unknown (no CLI, the read failed) tries as before
        c = _common()
        why = c.sheep_talk_refusal(sheep_plan()) if c and hasattr(c, "sheep_talk_refusal") else None
        if why:
            return False, why
        return True, "key and address"

    def request(self, ctx, text):
        body = {"space": space_id(ctx["space"]), "session_id": ctx["manager"], "text": text}
        return talk_url() + "/api/talk/send", body

    def send(self, ctx, text):
        url, body = self.request(ctx, text)
        req = urllib.request.Request(url, data=json.dumps(body).encode(), method="POST", headers={
            "Authorization": "Bearer " + (sheep_key() or ""), "Content-Type": "application/json", "User-Agent": UA})
        try:
            with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
                res = json.loads(r.read().decode() or "{}")
            return ("sent", "talk: %s" % (res.get("id") or "ok")) if res.get("ok", True) else ("unreachable", "talk: %s" % res)
        except urllib.error.HTTPError as e:
            try:
                err = json.loads(e.read().decode() or "{}")
            except ValueError:
                err = {}
            code = err.get("code") or e.code
            # an account without Talk (Free): the plan's line, and the cached plan read again next time
            c = _common()
            if (code == "plan_required" or e.code == 402) and c and hasattr(c, "sheep_talk_refusal"):
                sheep_plan(refresh=True)
                return "unreachable", c.sheep_talk_refusal({"talk": False})
            # K10: Talk switched off says so; the next backend takes the message
            return "unreachable", "talk: %s %s" % (code, err.get("error") or "")
        except (urllib.error.URLError, OSError, ValueError) as e:
            return "unreachable", "talk: %s" % e

    def receive(self, ctx):
        """The messages for ctx['session'] (blocks until one arrives): the CLI's `talk listen --once`.
        A list of dicts, each with a str `text`; [{"stopped": True}] when the link ended with no
        message; None when there is no CLI or the listen failed.

        The wire format is unverified until B0a (section 8): one JSON object per stdout line, its
        text in `text` or `message`, is read off the plugin's /talk skill, not a recorded exchange.
        So every JSON line of a body is a message — a listen that returns two must not drop the
        second — and a line whose JSON is not an object, or whose text is not a string, is coerced
        rather than trusted."""
        cli = sheep_cli()
        if not cli:
            return None
        sid = ctx.get("session") or os.environ.get("CLAUDE_CODE_SESSION_ID")
        r = subprocess.run([cli, "talk", "listen", "--once"] + (["--session", sid] if sid else []),
                           capture_output=True, text=True)
        out = []
        for line in r.stdout.splitlines():
            line = line.strip()
            if not line.startswith(("{", "[", '"')):
                continue
            try:
                d = json.loads(line)
            except ValueError:
                continue
            if not isinstance(d, dict):
                d = {"text": d}
            t = d.get("text") if d.get("text") is not None else d.get("message")
            d["text"] = t if isinstance(t, str) else ("" if t is None else json.dumps(t, ensure_ascii=False))
            out.append(d)
        if out:
            return out
        return [{"stopped": True, "raw": r.stdout[-500:]}] if r.returncode == 0 else None

    def curl(self, ctx, text):
        """The exact POST for a brief (a cloud run has no bin/ask): the key stays a variable, since a
        brief is committed and logged."""
        url, body = self.request(ctx, text)
        return ("curl -sS -X POST %s -H \"Authorization: Bearer $SPACESHEEP_KEY\" -H 'Content-Type: application/json' "
                "-A 'curl/8.7.1' --data %s" % (url, _shq(json.dumps(body, ensure_ascii=False))))

    def describe(self):
        return "talk — the Talk service's POST /api/talk/send to the manager's plan page; any Mac, login or harness"


class SendMessage:
    """Claude Code's own SendMessage — a model tool, so this backend resolves the road and prints the
    call for the session to make: same account and a live record with a socket (R4)."""
    name = "sendmessage"

    def available(self, ctx):
        m = ctx.get("manager")
        if not m:
            return False, "no manager id"
        rec = registry(m)
        if not rec:
            return False, "the manager has no record in %s (another Mac, or it ended)" % sessions_dir()
        if not pid_alive(rec.get("pid")):
            return False, "the manager's process %s is gone" % rec.get("pid")
        if not rec.get("messagingSocketPath"):
            return False, "the manager binds no inbox (a -p session)"
        theirs, mine = account_home(ctx.get("manager_account")), account_home(ctx.get("account"))
        if theirs != mine:
            return False, "a different login (%s vs %s): no road across accounts" % (theirs, mine)
        return True, rec.get("status") or "live"

    def send(self, ctx, text):
        rec = registry(ctx["manager"]) or {}
        twins = same_named(rec)
        name = rec.get("name") or ctx["manager"][:8]
        hint = " (cwd %s — %d other live session(s) share the name)" % (rec.get("cwd"), len(twins)) if twins else ""
        verdict = "busy" if rec.get("status") == "busy" else "live"
        return verdict, "sendmessage: call SendMessage to %s%s with the text above" % (name, hint)

    def receive(self, ctx):
        return None  # the inbox is the session's own; nothing for a script to read

    def describe(self):
        return "sendmessage — Claude Code's SendMessage, same account and a live socket; nothing leaves the Mac"


class File:
    """A JSON line in ~/Library/Logs/claude-weekly/asks/<manager>.jsonl, printed into the manager's
    context by its UserPromptSubmit hook at its next prompt. Nothing wakes it."""
    name = "file"

    def path(self, ctx):
        return queue_dir() / ("%s.jsonl" % ctx["manager"])

    def available(self, ctx):
        """A live manager on this Mac: its registry record with a live pid (finding 4). A plan dir
        left behind by a session that ended is not one — the queue would wait for a prompt that
        never comes. Or a live manager on a peer this Mac reaches over ssh (peer-manager-relay): its
        own queue there, which its prompt hook prints as it prints a local one."""
        if not ctx.get("manager"):
            return False, "no manager id"
        rec = registry(ctx["manager"])
        if rec is None:
            peer = peer_manager(ctx)
            if peer and peer[1] and peer[1].get("alive"):
                return True, "%s over ssh %s, pid %s" % (ctx.get("manager_host"), peer[0], (peer[1].get("record") or {}).get("pid"))
            return False, "the manager is not on this Mac" + (" (%s)" % peer[2] if peer and peer[2] else "")
        if not pid_alive(rec.get("pid")):
            return False, "the manager's process %s is gone" % rec.get("pid")
        return True, "this Mac, pid %s" % rec.get("pid")

    def send(self, ctx, text):
        line = json.dumps({"t": int(time.time()), "from": ctx.get("session"), "text": text}, ensure_ascii=False)
        if registry(ctx["manager"]) is None and peer_manager(ctx):
            alias = peer_manager(ctx)[0]
            # ascii(): a literal Python 3.9 reads from stdin whatever the line holds (hail's bundle())
            out, why = peer_ssh(alias, [ctx["manager"]], "LINE = %s\n%s" % (ascii(line), PEER_QUEUE))
            if out is None:
                return "unreachable", "file: %s" % why
            return "queued", "file: %s on %s" % (out.strip().splitlines()[-1] if out.strip() else "the queue", ctx.get("manager_host"))
        p = self.path(ctx)
        p.parent.mkdir(parents=True, exist_ok=True)
        fd = os.open(str(p), os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
        try:
            os.write(fd, (line + "\n").encode())
        finally:
            os.close(fd)
        return "queued", "file: %s" % p

    def receive(self, ctx):
        p = self.path(ctx)
        try:
            lines = p.read_text().splitlines()
        except OSError:
            return []
        return [json.loads(x) for x in lines if x.strip().startswith("{")]

    def describe(self):
        return "file — a line the manager's next prompt prints; this Mac, or a peer `wharf-runs/ssh` reaches"


BACKENDS = {b.name: b for b in (Talk(), SendMessage(), File())}


def relay(ctx, text, order, dry=False, resolved=None):
    """Try each backend of `order` until one delivers. Returns (backend, verdict, detail, tried):
    verdict is sent | live | busy | queued | none | unreachable; `tried` lists each skip with why.
    A run whose manager is unset or gone relays to the Mac's standing manager when one runs (M5).
    `resolved` is resolve(ctx) when the caller has it already (bin/ask relay); else it runs here."""
    tried = []
    ctx, (alive, why) = resolved or resolve(ctx)
    if not ctx.get("manager"):
        return None, "none", "no live manager (DISPATCH_SKIPPER unset)", tried
    # finding 4: a dead or gone manager is `none` — the run takes the WAITING path — whatever
    # backend would carry the message (a Talk send to an ended session goes to a thread nobody
    # reads, and the file queue in a prompt that never comes). A remote one: Talk alone.
    if alive == "gone":
        return None, "none", "no live manager: %s" % why, tried
    # a scope's skipper resolve() put in for a caller's missing manager never reads the file queue
    # (it hears its `ask listen` and a SendMessage): a file line waits for a prompt it never gets and
    # is marked relayed, so that road is skipped for it, and a caller that pinned no other road gets
    # `none` — the board (the fifth finish review of S5: wharf's file road for a yard-held scope
    # ship). A caller that names the skipper itself (the re-hail) keeps its roads: it counts a file
    # line as a try, never a delivery.
    if ctx.get("scope") and ctx.get("stand_in") and "file" in order:
        tried.append(("file", "the scope's skipper never reads the file queue"))
        order = [n for n in order if n != "file"]
        if not order:
            return None, "none", "the scope's skipper never reads the file queue, the one road this relay takes", tried
    for name in order:
        b = BACKENDS.get(name)
        if not b:
            tried.append((name, "unknown backend"))
            continue
        ok, why = b.available(ctx)
        if not ok:
            tried.append((name, why))
            continue
        if dry:
            return name, "dry-run", why, tried
        verdict, detail = b.send(ctx, text)
        if verdict == "unreachable":
            tried.append((name, detail))
            continue
        return name, verdict, detail, tried
    return None, "unreachable", "every backend refused", tried


def _shq(s):
    return "'" + s.replace("'", "'\"'\"'") + "'"


# ---------------------------------------------------------------------------- the interruption log

def log_relay(kind, detail, session=None, cwd=None):
    """One interruption row per settled relay, in the class hooks/attention.py defines (DESIGN.md
    number 6 of the interruptions design, owned by session coding-d1): event "Relay",
    type "answered" (the manager settled it without the owner — an interruption avoided) or "escalated"
    (it went on to the owner). bin/interruptions counts relay apart from the total, since an escalation
    reaches the owner again as an ask or a handoff; a managerless WAITING line is already a handoff row.
    attention.record() when that module is here; until it launches, the same row by hand, to the same
    file, so the shape stays one (coding-d1, 2026-10-10: a new field is agreed with it first).
    Never raises."""
    import datetime as _dt
    import sys as _sys
    try:
        at = _peer("attention.py")   # plumb's (G26): absent → the row by hand, below
        if not at:
            raise ImportError("attention.py not installed (plumb)")
        if str(at.parent) not in _sys.path:
            _sys.path.insert(0, str(at.parent))
        import attention  # noqa: F401
        if kind in getattr(attention, "RELAY_KINDS", (kind,)):
            return attention.record("Relay", kind, detail=detail, session=session, cwd=cwd)
    except Exception:
        pass
    try:
        c = _common()   # the core's log dir (`regatta/log-dir`), as plumb's attention.py writes there
        d = Path(os.environ.get("ATTENTION_LOG_DIR") or (c.LOG_DIR if c else _home() / ".local" / "state" / "regatta") / "attention")
        now = _dt.datetime.now().astimezone()
        row = {"ts": now.isoformat(timespec="seconds"), "event": "Relay", "type": kind, "tool": "",
               "detail": (detail or "")[:300], "session": (session or "")[:8], "cwd": cwd or os.getcwd(),
               "login": Path(os.environ.get("CLAUDE_CONFIG_DIR") or "~/.claude").name}
        d.mkdir(parents=True, exist_ok=True)
        with open(d / ("%s.jsonl" % now.strftime("%Y-%m")), "a") as f:
            f.write(json.dumps(row, ensure_ascii=False) + "\n")
        return True
    except Exception:
        return False


# ---------------------------------------------------------------------------- message lines

PREFIXES = ("ASK", "ANSWER", "REPORT")


def classify(text):
    """(kind, rest): ASK | ANSWER | REPORT from a session; CHAT for an unprefixed line — unverified:
    the account owner's page, or any session holding the key, sends one (K13). Shown to the manager
    as that, never taken as an answer to a D-item, never as the owner's word."""
    t = (text or "").strip()
    for p in PREFIXES:
        if t.startswith(p + " "):
            return p, t[len(p) + 1:]
    return "CHAT", t
