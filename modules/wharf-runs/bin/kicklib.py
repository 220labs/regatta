"""kicklib — the dispatch queue's kick roads (S8 of docs/dispatch-queue-2026-10-25.md; the component,
docs/dispatch-queue-kick-2026-10-25.md). dispatch-queue's `kick`, `kicked`, `roads` and the sweep's hold-back and
watchdog load it, and dispatch-rc's `kick-listen`; nothing else needs to.

A host that enqueued an entry it cannot take kicks every eligible peer, in parallel, over the first road the
peer's line names that takes it, each verdict a line in claude-weekly/kicks.jsonl:

  sheep  a press named `kick` on the peer's spacesheep stream (`kick/<peer>`, or the stream
         `wharf-runs/kick-stream` names for it), heard by the peer's `spacesheep stream … --on-dir` listener; the
         press goes through a web session this host's full key mints (the CLI has no press verb)
  orca   `orca terminal create --environment <peer> --worktree path:<its core> --command "<dispatch> --claim …;
         exit"`, then `terminal wait --for exit` and `terminal close`, each with `--environment`
  ssh    `ssh -o BatchMode=yes -o ConnectTimeout=10 <alias> "<the peer's core>/…/dispatch" --claim …`, the core
         read from the peer's own `home` file by its shell (an ssh command's PATH lacks it)

The payload is the same on every road: `kick`, `from` (the kicker) and `full` (the hosts known full) — host
names, never a repo, branch, scope or entry. The receiver (`dispatch --claim --full …`, or the sheep button's
`--from-stream`) notes the kick and kickstarts its own queue-sweep job, which holds back for higher-ranked
hosts of unknown room and claims under its own identity: nothing reads the registry inside an Orca terminal
or a listener (AGENTS.md's Drive trap).

Which roads reach a peer: its line in `wharf-runs/kick-roads` (`<host>:<road>[,<road>…]`, or `none`), else
what exists — `orca` where `wharf-runs/orca-pairs` names this host's pair with it, `ssh` where `wharf-runs/ssh`
has its alias. `sheep` only where a line names it: a kicker cannot see another host's listener, and a press
from a script is unprobed until the probe lands one (docs/dispatch-queue-2026-10-25/kick_probe.py). The kick is
on only where the `kick-roads` file exists, the switch as `queue-repo` is the queue's: a fleet that set no line
kicks nobody, and no suite with an ssh fixture reaches a real alias. Python 3.9, stdlib.
"""
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import threading
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "lib"))
import core_path  # noqa: E402 — the regatta core (C2)
core_path.require()
import common  # noqa: E402

HOST_RE = re.compile(r"[a-z0-9][a-z0-9._-]{0,62}")
ROADS = ("sheep", "orca", "ssh")
ROADS_KEY = "wharf-runs/kick-roads"
TIMEOUT = 15             # one road's call, at most: each returns well under it (the receiver only notes and kickstarts)
ORCA_WAIT_MS = 10000     # `terminal wait --for exit`, as the component names it
PROVE_S = float(os.environ.get("DISPATCH_KICK_PROVE_S") or 8)   # kick-listen's one bounded proving run (the suites shorten it)
REFUSALS = 2             # refusals in the listener's log tail that make the watchdog boot it out (a restart loop)
# The press's route. UNPROBED: the CLI has no press verb and the docs show a press only as a page viewer's act;
# kick_probe.py's first case finds whether this route takes one (and its latency). Until it lands a press, the
# sheep road runs only where `kick-roads` names it.
PRESS_PATH = "/api/streams/%s/-/press"
KEY_SLOT = "full key"    # what the sheep road needs on a kicker; never read here but by sheep_press, never printed

# The receiver's dispatch on a peer: its core from its own `home` file, read by the peer's shell (dispatch's rbin)
PEER_DISPATCH = '"$(head -1 "${REGATTA_CONFIG:-$HOME/.config/regatta}/home" 2>/dev/null)/modules/wharf-runs/bin/dispatch"'


def now():
    return int(os.environ.get("DISPATCH_QUEUE_NOW") or time.time())


def logdir():
    return Path.home() / "Library" / "Logs" / "claude-weekly"


def log(kind, **kw):
    """One line in claude-weekly/kicks.jsonl: a kick's verdict per road, a kick heard, a listener booted out.
    Never raises."""
    try:
        logdir().mkdir(parents=True, exist_ok=True)
        with open(logdir() / "kicks.jsonl", "a") as f:
            f.write(json.dumps(dict(at=now(), event=kind, **kw), sort_keys=True) + "\n")
    except OSError:
        pass


def host_ok(h):
    return isinstance(h, str) and bool(HOST_RE.fullmatch(h))


def payload(me, full):
    """The kick's whole content: host names only (the component's "A kick carrying an entry" risk)."""
    hosts = sorted({x.lower() for x in full} | {me.lower()})
    if not host_ok(me.lower()) or not all(host_ok(x) for x in hosts):
        raise ValueError("a kick names hosts only, each [a-z0-9._-]")
    return {"kick": 1, "from": me.lower(), "full": hosts}


def parse_payload(text):
    """(from, full) of a kick's data, or ValueError. Strict: anyone who can open a stream's page can press
    it (the CLI's README), so the press's data is parsed, never interpolated, and holds nothing but host names."""
    d = json.loads(text) if isinstance(text, str) else text
    if not isinstance(d, dict) or set(d) - {"kick", "from", "full"}:
        raise ValueError("a kick's data holds kick, from and full only")
    frm, full = d.get("from"), d.get("full") or []
    if not host_ok(frm) or not isinstance(full, list) or len(full) > 32 or not all(host_ok(x) for x in full):
        raise ValueError("a kick's from and full name hosts only")
    return frm, sorted(set(full))


def _pairs(key):
    out = []
    for ln in common.config_lines(key) or []:
        a, sep, b = ln.partition(":")
        if sep and a.strip() and b.strip():
            out.append((a.strip().lower(), b.strip()))
    return out


def kicks_on():
    """The kick is switched on where the `kick-roads` file exists (empty or not)."""
    return common.config_lines(ROADS_KEY) is not None


def ssh_alias(peer):
    return next((b for a, b in _pairs("wharf-runs/ssh") if a == peer), None)


def orca_paired(me, peer):
    return any(a == me and b.lower() == peer for a, b in _pairs("wharf-runs/orca-pairs"))


ROAD_WORD = re.compile(r"\b(sheep|orca|ssh)\b")


def road_lines():
    """{host: roads} from the `kick-roads` file, its first line per host winning (as the core's check reads it). A
    line with no `host:` continues the host before it: the overlay's bootstrap writes a value one word per line, so
    `peer: sheep, ssh` arrives as `peer:`, `sheep,` and `ssh` (AGENTS.md's trap; the S8 review). A `#` line, and
    anything after `#` or `(` on a line (the notes `dispatch --roads` prints), is no road; a host whose text
    names no road is `none`."""
    text, order = {}, []
    last = None
    for ln in common.config_lines(ROADS_KEY) or []:
        ln = re.split(r"[#(]", ln, 1)[0].strip()
        if not ln:
            continue
        name, sep, rest = ln.partition(":")
        if sep and host_ok(name.strip().lower()):
            last = name.strip().lower()
            if last in text:
                last = "#dup"   # a second line for a host: the first one stands
                continue
            text[last] = rest
            order.append(last)
        elif last and last != "#dup":
            text[last] += " " + ln
    return {h: ROAD_WORD.findall(text[h].lower()) for h in order}


def line_of(host):
    """HOST's roads as its `kick-roads` line names them, in its order ([] for `none`), or None with no line."""
    return road_lines().get(host)


def derived(peer, me):
    """The roads that exist from ME to PEER: orca where the pairing runs this way, ssh where the alias is.
    Never sheep: a kicker cannot see the peer's listener."""
    out = []
    if orca_paired(me, peer):
        out.append("orca")
    if ssh_alias(peer):
        out.append("ssh")
    return out


def roads_for(peer, me):
    """(roads in order, where they came from) for kicking PEER from ME."""
    named = line_of(peer)
    if named is not None:
        return named, "kick-roads"
    return derived(peer, me), "derived"


def reached(h):
    """A kick road reaches host H (item 12 of the S2a review, stated here): the kick is on (the roads file
    exists), and H's line names a road, or H has no line and a road exists to it from some host — a pairing
    naming H as the peer, or an alias for H in `wharf-runs/ssh` (the overlay writes one table for every
    host). `none`, or no file, is not reached: the pending poll is then H's way to hear of room."""
    if not kicks_on():
        return False
    named = line_of(h)
    if named is not None:
        return bool(named)
    return bool(ssh_alias(h)) or any(b.lower() == h for _, b in _pairs("wharf-runs/orca-pairs"))


# ---------------------------------------------------------------------------- the roads

def receiver_args(pl):
    return ["--claim", "--full", ",".join(pl["full"]), "--from", pl["from"]]


def road_ssh(peer, pl):
    alias = ssh_alias(peer)
    if not alias:
        return False, "no wharf-runs/ssh alias for %s" % peer
    ssh = os.environ.get("DISPATCH_SSH") or "ssh"
    cmd = " ".join([PEER_DISPATCH] + [shlex.quote(a) for a in receiver_args(pl)])
    try:
        r = subprocess.run([ssh, "-o", "BatchMode=yes", "-o", "ConnectTimeout=10", alias, cmd],
                           capture_output=True, text=True, timeout=TIMEOUT)
    except (OSError, subprocess.TimeoutExpired) as x:
        return False, "ssh %s: %s" % (alias, type(x).__name__)
    if r.returncode != 0:
        return False, "ssh %s: exit %d %s" % (alias, r.returncode, (r.stderr.strip().splitlines() or [""])[-1][:160])
    return True, "ssh %s" % alias


def orca_bin():
    """orca-host's lookup: its override, Linux's `orca-ide`, the app's own CLI (a bare `orca` may be another tool)."""
    if os.environ.get("DISPATCH_ORCA") or os.environ.get("ORCA_HOST_CLI"):
        return os.environ.get("DISPATCH_ORCA") or os.environ["ORCA_HOST_CLI"]
    if sys.platform.startswith("linux"):
        return shutil.which("orca-ide")
    app = Path("/Applications/Orca.app/Contents/Resources/bin/orca")
    return str(app) if app.exists() else None


ORCA_CALL_S = 60   # create and repo list, as orca-host and the harness's Orca adapter give them: a create cut
                   # short after its RPC landed leaves a tab and sends a second kick (the S8 review)


def _orca(*args, timeout=ORCA_CALL_S):
    exe = orca_bin()
    if not exe:
        raise RuntimeError("no orca CLI here")
    env = {k: v for k, v in os.environ.items() if k != "ELECTRON_RUN_AS_NODE"}
    env["PATH"] = "/opt/homebrew/bin:" + env.get("PATH", "")
    r = subprocess.run([exe, *args, "--json"], capture_output=True, text=True, env=env, timeout=timeout)
    try:
        out = json.loads(r.stdout or "null")
    except ValueError:
        out = None
    if r.returncode != 0 or not isinstance(out, dict) or out.get("ok") is False:
        raise RuntimeError("orca %s: exit %d %s" % (" ".join(args[:2]), r.returncode, (r.stderr or r.stdout).strip()[-160:]))
    return out.get("result", out)


def _find(d, key):
    """The first string under KEY anywhere in D: a handle's or a path's place in Orca's JSON is read, not
    assumed (no live probe of `terminal create`'s answer yet: the component's Not verified)."""
    if isinstance(d, dict):
        if isinstance(d.get(key), str):
            return d[key]
        for v in d.values():
            f = _find(v, key)
            if f:
                return f
    if isinstance(d, list):
        for v in d:
            f = _find(v, key)
            if f:
                return f
    return None


def peer_core(peer):
    """The peer's regatta checkout as its Orca knows it: the repo whose folder is named as this host's core
    is (`--worktree path:` needs one the serve holds)."""
    cfg = Path(os.environ.get("REGATTA_CONFIG") or Path.home() / ".config" / "regatta").expanduser()
    try:
        mine = Path((cfg / "home").read_text().split("\n")[0].strip()).name   # the main checkout's, not a worktree's
    except OSError:
        mine = ""
    mine = mine or HERE.parents[2].name
    for rp in _orca("repo", "list", "--environment", peer).get("repos") or []:
        p = (rp.get("path") if isinstance(rp, dict) else None) or ""
        if p and Path(p).name == mine:
            return p
    return None


def road_orca(peer, pl):
    """One terminal on the peer's serve, its command ending in `; exit` (typed into a login shell that would
    outlive it), waited for and closed: no tab is left on the peer (the component's risk; a case counts them)."""
    t0 = time.monotonic()
    try:
        core = peer_core(peer)
        if not core:
            return False, "orca: %s's serve holds no checkout named as this host's core" % peer
        cmd = " ".join([PEER_DISPATCH] + [shlex.quote(a) for a in receiver_args(pl)]) + "; exit"
        made = _orca("terminal", "create", "--environment", peer, "--worktree", "path:" + core, "--command", cmd)
        handle = _find(made, "handle") or _find(made, "terminal")
        if not handle:
            return False, "orca: terminal create named no handle"
        try:
            waited = _orca("terminal", "wait", "--environment", peer, "--terminal", handle, "--for", "exit",
                           "--timeout-ms", str(ORCA_WAIT_MS), timeout=ORCA_WAIT_MS / 1000 + 5)
        finally:
            try:
                # --tab: the whole tab and its resume record, not one pane (Orca's help; the S8 review)
                _orca("terminal", "close", "--environment", peer, "--terminal", handle, "--tab")
            except (RuntimeError, OSError, subprocess.TimeoutExpired):
                pass   # a terminal that exited may be gone already; the wait's verdict stands
        # the receiver's own status, which `; exit` hands the terminal: 127 for a peer with no `home` file, say,
        # is no kick taken, and the next road is tried (the S8 review: the wait alone read as success)
        code = _find_num(waited, "exitCode")
        if code is None:
            return False, "orca: the wait named no exit code"
        if code != 0:
            return False, "orca: the receiver on %s exited %d" % (peer, code)
    except (RuntimeError, OSError, subprocess.TimeoutExpired) as x:
        return False, "orca: %s" % (str(x) or type(x).__name__)[:200]
    return True, "orca %s in %.1f s" % (peer, time.monotonic() - t0)


def _find_num(d, key):
    if isinstance(d, dict):
        if isinstance(d.get(key), int) and not isinstance(d.get(key), bool):
            return d[key]
        for v in d.values():
            f = _find_num(v, key)
            if f is not None:
                return f
    if isinstance(d, list):
        for v in d:
            f = _find_num(v, key)
            if f is not None:
                return f
    return None


def stream_of(host):
    """HOST's kick stream: `wharf-runs/kick-stream`'s `<host>:<stream>` (a shared listener's stream), else
    kick/<host>."""
    for a, b in _pairs("wharf-runs/kick-stream"):
        if a == host:
            return b
    return "kick/%s" % host


def app_origin():
    return (os.environ.get("SPACESHEEP_APP_ORIGIN") or "https://spacesheep.dev").rstrip("/")


def _full_key():
    """The kicker's full key: SPACESHEEP_KEY, else the CLI's own login in its default config dir — never the
    listener's dir (its streams-only key can press nothing, and its SPACESHEEP_CONFIG_DIR is the listener's
    alone), never the overlay's .env (a hook-side read of a Drive link: AGENTS.md's trap). Never printed."""
    if os.environ.get("SPACESHEEP_KEY"):
        return os.environ["SPACESHEEP_KEY"].strip()
    cfg = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config") / "spacesheep" / "config.json"
    try:
        return (json.loads(cfg.read_text()).get("key") or "").strip() or None
    except (OSError, ValueError, AttributeError):
        return None


def can_press():
    """This host may press: a full key is where the CLI keeps it (presence only, never read here)."""
    cfg = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config") / "spacesheep" / "config.json"
    return bool(os.environ.get("SPACESHEEP_KEY")) or cfg.exists()


def sheep_press(stream, name, data, key=None, timeout=TIMEOUT):
    """Press NAME on STREAM with DATA through a web session the full key mints (POST /api/account/web-session,
    as keel does). (ok, why, seconds). Redirects are refused: urllib would carry the cookie anywhere. The
    route is PRESS_PATH's, unprobed: kick_probe.py says whether it lands."""
    import urllib.error
    import urllib.request

    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, *a, **kw):
            return None

    k = key or _full_key()
    if not k:
        return False, "no %s on this host" % KEY_SLOT, 0.0
    op = urllib.request.build_opener(NoRedirect)
    ua = {"User-Agent": "dispatch-kick/1", "Content-Type": "application/json"}
    t0 = time.monotonic()
    try:
        req = urllib.request.Request(app_origin() + "/api/account/web-session", data=b"{}", method="POST",
                                     headers=dict(ua, Authorization="Bearer " + k))
        with op.open(req, timeout=timeout) as r:
            s = json.loads(r.read().decode())
        cookie = "%s=%s" % (s["cookie"], s["token"])
        path = PRESS_PATH % "/".join(urllib.request.quote(p, safe="") for p in stream.split("/"))
        req = urllib.request.Request(app_origin() + path, method="POST", headers=dict(ua, Cookie=cookie),
                                     data=json.dumps({"name": name, "data": data}).encode())
        with op.open(req, timeout=timeout) as r:
            r.read()
    except urllib.error.HTTPError as x:
        return False, "press: HTTP %d" % x.code, time.monotonic() - t0
    except (OSError, ValueError, KeyError, TypeError) as x:
        return False, "press: %s" % type(x).__name__, time.monotonic() - t0
    return True, "pressed", time.monotonic() - t0


def road_sheep(peer, pl):
    stream = stream_of(peer)
    data = {"from": pl["from"], "full": pl["full"], "kick": 1}
    stand = os.environ.get("DISPATCH_SHEEP_PRESS")   # the suites' stand-in for the web press
    if stand:
        try:
            r = subprocess.run([stand, stream, "kick", json.dumps(data, sort_keys=True)], capture_output=True,
                               text=True, timeout=TIMEOUT)
        except (OSError, subprocess.TimeoutExpired) as x:
            return False, "press: %s" % type(x).__name__
        return r.returncode == 0, "press %s: exit %d" % (stream, r.returncode)
    ok, why, secs = sheep_press(stream, "kick", data)
    return ok, "%s %s in %.2f s" % (why, stream, secs)


ROAD_FN = {"sheep": road_sheep, "orca": road_orca, "ssh": road_ssh}


def kick_peer(peer, me, pl, kid):
    """Each road PEER's line names, in order, until one takes the kick; each verdict logged."""
    roads, src = roads_for(peer, me)
    if not roads:
        log("kick", kid=kid, to=peer, road=None, ok=False, why="no road (%s)" % src)
        return None
    for road in roads:
        t0 = time.monotonic()
        try:
            ok, why = ROAD_FN[road](peer, pl)
        except Exception as x:   # one road's crash is that road's verdict; the next is tried
            ok, why = False, "%s: %s" % (type(x).__name__, x)
        log("kick", kid=kid, to=peer, road=road, ok=ok, why=why[:240], secs=round(time.monotonic() - t0, 2), source=src)
        if ok:
            return road
    return None


def kick(peers, me, full, kid=""):
    """Kick every peer in PEERS in parallel; {peer: the road that took it, or None}."""
    pl = payload(me, full)
    out = {}

    def one(p):
        out[p] = kick_peer(p, me, pl, kid)
    # not daemons, joined with no bound of their own: each road is bounded by its calls' timeouts, and a process that
    # exited mid-road left an Orca tab open and the roads after it untried (the S8 review)
    ts = [threading.Thread(target=one, args=(p,)) for p in peers]
    for t in ts:
        t.start()
    for t in ts:
        t.join()
    return out


# ---------------------------------------------------------------------------- the sheep listener

def listen_dir():
    """The listener's own SPACESHEEP_CONFIG_DIR: its streams-only key lives here, apart from the host's full
    key (`keys save` would overwrite that one, and the build host holds one)."""
    return Path(os.environ.get("DISPATCH_KICK_LISTEN_DIR") or Path.home() / "Library" / "Caches" / "run-seed" / "kick-listen")


def slug(name):
    """The CLI's own slug (stream-service.js): its service label is dev.spacesheep.stream.<slug>."""
    s = re.sub(r"^-+|-+$", "", re.sub(r"[^a-z0-9]+", "-", str(name).lower()))[:60]
    return s or "stream"


def service_label(stream):
    return "dev.spacesheep.stream.%s" % slug(stream)


def spacesheep_bin():
    return os.environ.get("DISPATCH_SPACESHEEP") or shutil.which("spacesheep") or "/opt/homebrew/bin/spacesheep"


def listener_loaded(launchctl, stream):
    """launchd holds the listener service (`launchctl print`), True/False, None when it could not tell — the
    line is derived from this, never from `spacesheep streams`, which lists only streams made by a push."""
    if sys.platform != "darwin" and not os.environ.get("DISPATCH_LAUNCHCTL"):
        try:
            r = subprocess.run(["systemctl", "--user", "is-active", "spacesheep-stream-%s.service" % slug(stream)],
                               capture_output=True, text=True, timeout=10)
        except (OSError, subprocess.TimeoutExpired):
            return None   # no systemctl here: could not tell, never a crash of --roads or status (the S8 review)
        return r.returncode == 0
    try:
        return subprocess.run([launchctl, "print", "gui/%d/%s" % (os.getuid(), service_label(stream))],
                              capture_output=True, timeout=10).returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        return None


BUTTON = """#!/bin/sh
# The kick button (dispatch-queue S8): a press on this host's kick stream runs the receiver, which reads the
# press's data from SS_STREAM_DATA itself (parsed, never interpolated: anyone who can open the page can press).
exec %s --claim --from-stream
""" % PEER_DISPATCH


def write_button(d):
    d.mkdir(parents=True, exist_ok=True)
    p = d / "kick"
    p.write_text(BUTTON)
    p.chmod(0o755)
    return p


def listen_env():
    env = dict(os.environ)
    env["SPACESHEEP_CONFIG_DIR"] = str(listen_dir())
    env.pop("SPACESHEEP_KEY", None)   # the listener hears on its own streams-only key, never this shell's
    return env


def prove(stream, buttons, secs=PROVE_S):
    """One bounded run of the listener in the foreground: (ok, why). It must say it is listening and not exit 3
    (a key the server refused). Killed after SECS."""
    try:
        p = subprocess.Popen([spacesheep_bin(), "stream", stream, "--on-dir", str(buttons)], stdin=subprocess.DEVNULL,
                             stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, env=listen_env())
    except OSError as x:
        return False, "the spacesheep CLI did not start (%s)" % x
    try:
        out, _ = p.communicate(timeout=secs)
    except subprocess.TimeoutExpired:
        p.terminate()
        try:
            out, _ = p.communicate(timeout=5)
        except subprocess.TimeoutExpired:
            p.kill()
            out, _ = p.communicate()
    out = out or ""
    if p.returncode == 3 or "refused the key" in out:
        return False, "the server refused the listener's key: %s" % (out.strip().splitlines() or [""])[-1][:200]
    if "listening for" not in out:
        return False, "no `listening for` line in %d s (exit %s): %s" % (secs, p.returncode, (out.strip().splitlines() or [""])[-1][:200])
    return True, "listening"


UNATTENDED_MARKS = ("REGATTA_UNATTENDED", "CLAUDE_UNATTENDED", "AUTOFINISH_CALLER_UNATTENDED", "DISPATCH_LABEL")


def unattended():
    """A caller nobody is at: an unattended run's mark, a peer job's, or a fired launchd job's label. Every
    kick-listen write refuses it — a button in a live listener runs dispatch on any page viewer's press, and a
    remove deletes the owner's service (the S8 review: --shared and remove passed)."""
    return next((m for m in UNATTENDED_MARKS if os.environ.get(m)), None)


def shared_listener(me):
    """The stream `wharf-runs/kick-stream` names for ME, or None: such a host's button sits in another listener's
    --on-dir, and that listener's service is its owner's. A plain install or remove would rewrite or boot out that
    service, which the CLI finds by its label alone (the S8 review, pass 2)."""
    return next((b for a, b in _pairs("wharf-runs/kick-stream") if a == me), None)


def listen_install(me, launchctl, shared=None):
    """kick-listen install (S8): the button, one bounded proving run, then the CLI's own `--service`. SHARED: an
    existing listener's --on-dir instead — the button joins it, and no process is added (its stream goes into
    `wharf-runs/kick-stream`). Refused under an unattended caller (the classifier's line: a session does not
    install a service). Exit 3 when the owner's step is missing."""
    m = unattended()
    if m:
        print("kick-listen: refused under %s — a listener is installed by the owner, or a session the owner is in" % m)
        return 2
    if shared:
        d = Path(shared).expanduser()
        if not d.is_dir():
            print("kick-listen: --shared %s is no folder (the running listener's --on-dir)" % d)
            return 2
        write_button(d)
        print("kick-listen: the kick button is in %s; name that listener's stream for %s in wharf-runs/kick-stream "
              "(%s:<its stream>)" % (d, me, me))
        log("listen-shared", host=me, dir=str(d))
        return 0
    if shared_listener(me):
        print("kick-listen: %s's kick stream is %s, a shared listener's (wharf-runs/kick-stream) — use --shared DIR"
              % (me, shared_listener(me)))
        return 2
    d = listen_dir()
    stream = stream_of(me)
    if not (d / "config.json").exists():
        # the local pipe: the key never crosses ssh, and a host with no sshd (a keyboard Mac) is served the same
        print("kick-listen: no streams-only key in %s. The owner's step, on this host, signed in (never printed):\n"
              "  spacesheep keys create --scope stream --name %s | SPACESHEEP_CONFIG_DIR=%s spacesheep keys save"
              % (d, me, d))
        return 3
    buttons = write_button(d / "buttons").parent
    ok, why = prove(stream, buttons)
    log("listen-prove", host=me, stream=stream, ok=ok, why=why)
    if not ok:
        print("kick-listen: the proving run failed — %s; nothing installed" % why)
        return 3
    # a fresh log: the CLI's service appends to it, and refusals from before this install would read as a loop
    # to the watchdog (the S8 review: a reinstall with a good key was booted out at the next sweep)
    logf = d / ("stream-%s.log" % slug(stream))
    if logf.exists():
        logf.replace(logf.with_name(logf.name + ".old"))
    r = subprocess.run([spacesheep_bin(), "stream", stream, "--on-dir", str(buttons), "--service"],
                       capture_output=True, text=True, env=listen_env(), timeout=120)
    if r.returncode != 0:
        print("kick-listen: the CLI's --service failed (exit %d): %s" % (r.returncode, (r.stderr or r.stdout).strip()[-200:]))
        return 1
    print("kick-listen: %s listens on %s (%s); add sheep to %s's line in %s where every kicker holds a full key"
          % (me, stream, service_label(stream), me, ROADS_KEY))
    log("listen-installed", host=me, stream=stream)
    return 0


def listen_remove(me, shared=None):
    m = unattended()
    if m:
        print("kick-listen: refused under %s — the owner's listener is removed by the owner" % m)
        return 2
    if shared:
        (Path(shared).expanduser() / "kick").unlink(missing_ok=True)
        print("kick-listen: the kick button removed from %s" % shared)
        return 0
    if shared_listener(me):
        print("kick-listen: %s's kick stream is %s, a shared listener's (wharf-runs/kick-stream) — use --shared DIR"
              % (me, shared_listener(me)))
        return 2
    stream = stream_of(me)
    r = subprocess.run([spacesheep_bin(), "stream", stream, "--remove-service"], capture_output=True, text=True,
                       env=listen_env(), timeout=60)
    (listen_dir() / "buttons" / "kick").unlink(missing_ok=True)
    print("kick-listen: %s's listener on %s removed (exit %d)" % (me, stream, r.returncode))
    log("listen-removed", host=me, stream=stream)
    return 0 if r.returncode == 0 else 1


def refusal_loop(tail):
    """The refused starts since the listener last listened: each start writes `streaming to`, and a healthy one then
    `listening for`; a refused one ends in the CLI's `✗` line instead, whatever the server's own error text (it prints
    the body's `error` when there is one). Only what follows the last `listening for` counts, so a log whose old
    refusals are followed by a healthy start is no loop (the S8 review)."""
    after = tail.rsplit("listening for", 1)[1] if "listening for" in tail else tail
    return sum(1 for ln in after.splitlines() if ln.strip().startswith("✗"))


def watchdog(me, launchctl):
    """The sweep's watchdog over this host's listener: REFUSALS refused starts since it last listened is a restart
    loop (the CLI exits 3, launchd starts it again), so the service is booted out and its plist moved aside — left
    in place, it loaded again at the next login (the S8 review) — and said once. A plan refusal (a 402 or 429) loops
    inside one process with no log line (the CLI checks no res.ok), which no log tail can see: reported to
    spacesheep, not caught here. None when nothing was done."""
    if shared_listener(me):
        return None   # a shared listener's service is its owner's to judge (the S8 review, pass 2)
    stream = stream_of(me)
    logf = listen_dir() / ("stream-%s.log" % slug(stream))
    try:
        with open(logf, "rb") as f:
            f.seek(0, 2)
            f.seek(max(0, f.tell() - 4096))
            tail = f.read().decode("utf-8", "replace")
    except OSError:
        return None
    n = refusal_loop(tail)
    if n < REFUSALS or listener_loaded(launchctl, stream) is not True:
        return None
    subprocess.run([launchctl, "bootout", "gui/%d/%s" % (os.getuid(), service_label(stream))], capture_output=True)
    plist = Path.home() / "Library" / "LaunchAgents" / ("%s.plist" % service_label(stream))
    if plist.exists():
        # out of LaunchAgents, not renamed in it: whether launchd skips a name not ending .plist at login is not
        # documented (the S8 review, pass 2)
        listen_dir().mkdir(parents=True, exist_ok=True)
        plist.replace(listen_dir() / (plist.name + ".refused"))
    why = "the listener on %s was refused %d times since it last listened; booted out, its plist moved aside — " \
          "`dispatch-rc kick-listen install` again once its key is good" % (stream, n)
    log("listener-refused", host=me, stream=stream, why=why)
    return why


def roads_lines(me, launchctl):
    """What exists, as `kick-roads` lines, each a bare `<host>:<roads>` with its note on a `#` line before it (a line
    copied into the file reads as written; the S8 review: a trailing note swallowed the last road): each peer this
    host reaches, and this host's own sheep listener where launchd holds it. One line per host: the overlay merges
    the hosts' words before writing, and a reader takes a host's first line."""
    peers = sorted({a for a, _ in _pairs("wharf-runs/ssh")} | {b.lower() for a, b in _pairs("wharf-runs/orca-pairs") if a == me}
                   | set(road_lines()))
    out = []
    for p in peers:
        if p == me:
            continue
        roads, src = roads_for(p, me)
        out += ["# %s from %s" % (src, me), "%s:%s" % (p, ",".join(roads) or "none")]
    lo = listener_loaded(launchctl, stream_of(me))
    out += ["# this host's listener on %s: %s; sheep belongs on a line only where every kicker holds a %s"
            % (stream_of(me), {True: "loaded", False: "not loaded", None: "could not tell"}[lo], KEY_SLOT),
            ] + (["%s:sheep" % me] if lo else [])
    # no `<me>:none` line: written first into the merged file, a host's first line wins, and `none` there would
    # switch off the orca and ssh roads the peers derive to this host (the S8 review, pass 2)
    return out
