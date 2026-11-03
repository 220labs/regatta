#!/usr/bin/env bash
# Tests for the sheep kick road's press over spacesheep's stream socket (kicklib.sheep_press; TODO.md [sheep-kick]'s build,
# the owner's "yes, websockets", 2026-11-02; docs/dispatch-queue-2026-10-25.md, "S8's first case, run"):
#   - the frame road (kicklib.socket_press) against a stand-in connection, everywhere: ready/sent/ack, no ack in
#     time, a refused stream, a space with no press, nothing listening, another press's acks, an ack read early;
#   - the package missing (none, or one older than 14.0, whose close could hang a kick): the road says so in one line, presses
#     nothing, and the kick falls to the next road;
#   - the whole press against a local stub socket server, where this python3 has websockets 14.0+ (a host without
#     it says so and runs the rest: the road itself is unavailable there, the cases above prove what it says).
# Scratch HOME and config dir; no network, no key, no real web session (the mint is stood in). Synthetic names.
#   bash modules/wharf-runs/tests/test_kick_socket.sh
set -u
unset WEEKLY_RUN REGATTA_UNATTENDED CLAUDE_UNATTENDED AUTOFINISH_CALLER_UNATTENDED CLAUDE_CODE_DISABLE_BACKGROUND_TASKS CLAUDE_CODE_SESSION_ID CLAUDE_CONFIG_DIR XPC_SERVICE_NAME
unset $(compgen -v | grep '^DISPATCH_')   # every DISPATCH_* a run carries (AGENTS.md: a fixed list goes stale)
unset SPACESHEEP_KEY SPACESHEEP_APP_ORIGIN SPACESHEEP_CONFIG_DIR XDG_CONFIG_HOME http_proxy https_proxy all_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY
B="$(cd "$(dirname "$0")/../bin" && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
. "$(cd "$(dirname "$0")" && pwd)/config_fixture.sh"; fixture_config "$T/config"
# the user site stays where it was (a Mac's websockets sits there) once HOME moves, as test_queue keeps it
export PYTHONUSERBASE="${PYTHONUSERBASE:-$(python3 -m site --user-base)}"
export HOME="$T/home"; mkdir -p "$HOME"
fails=0
check() { if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3: expected [$2] got [$1]"; fails=$((fails+1)); fi; }
has()   { if printf '%s' "$1" | grep -qF -- "$2"; then echo "  ok   $3"; else echo "  FAIL $3: missing [$2] in [$1]"; fails=$((fails+1)); fi; }

# k.py: kicklib loaded; each case a function named on the command line, printing its answer
cat > "$T/k.py" <<'PY'
import json, os, sys, time
sys.path.insert(0, os.environ["KB"])
import kicklib


class Conn:
    """A stand-in socket: FRAMES answered in order (None: recv times out), every send kept."""
    def __init__(self, frames):
        self.frames, self.sent = list(frames), []

    def send(self, m):
        self.sent.append(json.loads(m))

    def recv(self, timeout=None):
        if not self.frames:
            time.sleep(min(timeout or 0, 0.05))
            raise TimeoutError
        f = self.frames.pop(0)
        if f is None:
            raise TimeoutError
        return f if isinstance(f, str) else json.dumps(f)


S = "kick/buildbox"
N = "kick-n1"


def ready(allow=("kick/*",), press=True):
    return {"type": "ready", "allow": list(allow), "press": press}


def sent(ok=True, seq=6, listening=True, **kw):
    return dict({"type": "sent", "id": N, "ok": ok, "path": S, "seq": seq, "listening": listening}, **kw)


def ack(status, seq=6, path=S, note="kick"):
    return {"type": "ack", "path": path, "seq": seq, "status": status, "note": note}


def press(frames, wait=2.0):
    c = Conn(frames)
    ok, why = kicklib.socket_press(c, S, "kick", {"kick": 1, "from": "laptop", "full": ["laptop"]}, N, time.monotonic() + wait)
    return c, ok, why


def case_frames():
    c, ok, why = press([ready(), {"type": "hello", "path": S, "seq": 0}, sent(), ack("started"), ack("done")])
    print(ok, why, "|", json.dumps(c.sent, sort_keys=True))


def case_done_first():
    print(*press([ready(), sent(), ack("done", note="exit 0")])[1:])


def case_noise():
    print(*press(["pong", "not json", "[1, 2]", ready(), sent(), "pong", ack("started")])[1:])


def case_no_ack():
    t0 = time.monotonic()
    _, ok, why = press([ready(), sent()], wait=0.6)
    secs = time.monotonic() - t0
    print(ok, why, "in time" if 0.6 <= secs < 2.5 else "at %.1f s" % secs)


def case_no_answer():
    print(*press([], wait=0.7)[1:])


def case_refused_allow():
    print(*press([ready(allow=["plans/*"]), sent(), ack("started")])[1:])


def case_refused_sent():
    print(*press([ready(), sent(ok=False, error="no such stream"), ack("started")])[1:])


def case_no_press():
    print(*press([ready(press=False), sent(), ack("started")])[1:])


def case_not_listening():
    print(*press([ready(), sent(listening=False)])[1:])


def case_other_press():
    # another viewer's press on the same stream (seq 5), and our stream's acks only for our seq
    print(*press([ready(), sent(), ack("failed", seq=5), ack("started", seq=6, path="kick/other"), None, ack("started")])[1:])


def case_ack_early():
    print(*press([ready(), ack("started"), sent()])[1:])


def case_ack_failed():
    print(*press([ready(), sent(), ack("unheard", note="no button named kick")])[1:])


def case_no_seq():
    print(*press([ready(), sent(seq=None), ack("started")])[1:])


def case_bad_seq():
    # an ack whose seq is no int (unhashable) is passed over, never a crash
    print(*press([ready(), ack("started", seq=[6]), sent(), ack("started")])[1:])


def case_late():
    c = Conn([ready(), sent(), ack("started")])
    ok, why = kicklib.socket_press(c, S, "kick", {}, N, time.monotonic() - 0.1)
    print(ok, why, len(c.sent))


def case_near():
    c = Conn([ready(), sent(), ack("started")])
    ok, why = kicklib.socket_press(c, S, "kick", {}, N, time.monotonic() + 0.2)
    print(ok, why, len(c.sent))


def case_old_ws():
    """a websockets older than 14.0 (here a stand-in 13.1 with a sync client): not used"""
    print(kicklib.ws_client())


def case_slow_mint():
    """a mint that spends the whole budget: nothing is pressed, never a press then 'failed'"""
    has_ws()
    kicklib.ws_client = lambda: (lambda *a, **kw: (_ for _ in ()).throw(AssertionError("connected")), (OSError,))
    kicklib.web_session = lambda key, timeout: (time.sleep(timeout), "c=1")[1]
    print(*kicklib.sheep_press(S, "kick", {}, key="k", timeout=0.6, space="s1")[:2])


def case_error_frame():
    print(*press([{"type": "error", "error": "not signed in"}])[1:])


def nomint(*a, **kw):
    raise AssertionError("minted a web session")


def case_missing():
    """websockets absent (or older than its sync client): one line, nothing pressed, no session minted."""
    kicklib.web_session = nomint
    ok, why, secs = kicklib.sheep_press(S, "kick", {"kick": 1}, key="k", space="space-1")
    print(kicklib.ws_client(), ok, why.replace(sys.executable, "PY"), secs)


def case_missing_road():
    """...and the kick falls to the next road the line names, the sheep road's verdict one line in kicks.jsonl."""
    kicklib.web_session = nomint
    kicklib.line_of = lambda h: ["sheep", "ssh"]
    kicklib.ROAD_FN["ssh"] = lambda peer, pl: (True, "ssh stood in")
    print(kicklib.kick(["buildbox"], "laptop", []))
    rows = [json.loads(ln) for ln in open(kicklib.logdir() / "kicks.jsonl")]
    print(" | ".join("%s %s %s" % (r["road"], r["ok"], r["why"].replace(sys.executable, "PY")) for r in rows))


def has_ws():
    """The space cases stand the package in: press_ready asks it first, and these cases are about what follows."""
    kicklib.ws_client = lambda: (None, (OSError,))


def case_ready():
    has_ws()
    print(kicklib.press_ready() is None, (kicklib.press_ready() or "").replace(sys.executable, "PY"), kicklib.kick_space())


def case_roads():
    if os.environ.get("STAND_WS"):
        has_ws()
    os.environ["DISPATCH_LAUNCHCTL"] = os.environ["STUB_LAUNCHCTL"]
    print("\n".join(ln.replace(sys.executable, "PY") for ln in kicklib.roads_lines("laptop", os.environ["STUB_LAUNCHCTL"])
                    if "sheep press" in ln))


def case_no_space():
    has_ws()
    kicklib.web_session = nomint
    print(*kicklib.sheep_press(S, "kick", {"kick": 1}, key="k")[:2])


def case_bad_space():
    has_ws()
    kicklib.web_session = nomint
    print(*kicklib.sheep_press(S, "kick", {"kick": 1}, key="k", space="../x?y")[:2])


if __name__ == "__main__":
    globals()["case_" + sys.argv[1]]()
PY
export KB="$B"
k() { python3 "$T/k.py" "$@" 2>&1; }
HAS_WS=$(python3 -c 'from websockets.sync.client import connect; from websockets.version import version as v
import re, sys; sys.exit(tuple(int(x) for x in re.findall(r"\d+", v)[:2]) < (14, 0))' 2>/dev/null && echo 1 || echo 0)

echo "== the frame road (a stand-in socket)"
out=$(k frames)
has "$out" "True ack started |" "ready, sent, ack started: pressed, at the first ack that says the button began"
has "$out" '[{"p": ["kick/buildbox"], "t": "sub"}, {"data": {"from": "laptop", "full": ["laptop"], "kick": 1}, "id": "kick-n1", "name": "kick", "path": "kick/buildbox", "t": "send"}]' "  sends the page runtime's sub, then its send with our id"
check "$(k done_first)" "True ack done" "an ack done with no started before it: pressed"
check "$(k noise)" "True ack started" "the keepalive's pong, text that is no JSON and a frame that is no object are passed over"
out=$(k no_ack)
has "$out" "False sent, no ack from the listener in time" "sent and no ack before the deadline: not pressed, saying so"
has "$out" " in time" "  at the deadline, not after it"
check "$(k no_answer)" "False no answer to the press in time" "no frame at all: not pressed"
check "$(k refused_allow)" "False refused: the space declares no kick/buildbox (it allows plans/*)" "a space whose page does not declare the stream: refused, before any ack is read"
check "$(k refused_sent)" "False refused: no such stream" "the server's sent with ok false: refused, its error said"
check "$(k no_press)" "False the space grants no press" "a ready with press false: refused"
check "$(k not_listening)" "False sent, but nothing listens on kick/buildbox" "sent with no listener on: not pressed, at once"
check "$(k other_press)" "True ack started" "another press's ack (its seq) and another stream's are not ours"
check "$(k ack_early)" "True ack started" "an ack read before our sent counts once the sent names its seq"
check "$(k ack_failed)" "False ack unheard: no button named kick" "an ack that is no start: not pressed, its note said"
check "$(k error_frame)" "False the socket said: not signed in" "an error frame: not pressed"
check "$(k no_seq)" "False the server's sent named no seq for the press" "a sent naming no seq: not pressed, said at once (no ack could match)"
check "$(k bad_seq)" "True ack started" "an ack whose seq is no int is passed over, never a crash"
check "$(k late)" "False no time left to press 0" "past the deadline before the send: nothing sent (never a press then called failed)"
check "$(k near)" "False no time left to press 0" "less than the press window left: nothing sent either"
check "$(k slow_mint)" "False web session: no time left to press" "a mint that spent the budget: no socket opened"

echo "== the package missing"
mkdir -p "$T/old/websockets"; : > "$T/old/websockets/__init__.py"   # a websockets before 11.0: no sync client
cat > "$T/none.py" <<'PY'
import runpy, sys
sys.modules["websockets"] = None   # import websockets raises ImportError, as on a python3 that never had it
sys.argv = sys.argv[1:]
runpy.run_path(sys.argv[0], run_name="__main__")
PY
check "$(python3 "$T/none.py" "$T/k.py" missing 2>&1)" "None False unavailable: no websockets 14.0+ (its blocking client) for PY 0.0" "no websockets: the road says it is unavailable in one line, mints and presses nothing"
check "$(PYTHONPATH="$T/old" python3 "$T/k.py" missing 2>&1)" "None False unavailable: no websockets 14.0+ (its blocking client) for PY 0.0" "a websockets older than its blocking client: the same"
mkdir -p "$T/old13/websockets/sync"; : > "$T/old13/websockets/__init__.py"; : > "$T/old13/websockets/sync/__init__.py"
printf 'def connect(*a, **kw):
    raise AssertionError("connected")
' > "$T/old13/websockets/sync/client.py"
printf 'class WebSocketException(Exception):
    pass
' > "$T/old13/websockets/exceptions.py"
echo 'version = "13.1"' > "$T/old13/websockets/version.py"
check "$(PYTHONPATH="$T/old13" python3 "$T/k.py" old_ws 2>&1)" "None" "a websockets with a sync client but before 14.0 (whose close could hang a kick): not used"
echo 'version = "15.0.1"' > "$T/old13/websockets/version.py"
check "$(PYTHONPATH="$T/old13" python3 "$T/k.py" old_ws 2>&1 | cut -c1-6)" "(<func" "  and the same stand-in at 15.0.1 is (the floor reads the version)"
echo 'version = "16"' > "$T/old13/websockets/version.py"
check "$(PYTHONPATH="$T/old13" python3 "$T/k.py" old_ws 2>&1 | cut -c1-6)" "(<func" "  a one-part version past the floor is used too"
echo 'def connect(:' > "$T/old13/websockets/sync/client.py"
check "$(PYTHONPATH="$T/old13" python3 "$T/k.py" old_ws 2>&1)" "None" "a broken install (a SyntaxError on import): none, never a raise"
out=$(python3 "$T/none.py" "$T/k.py" missing_road 2>&1)
has "$out" "{'buildbox': 'ssh'}" "  the kick falls to the next road the line names"
has "$out" "sheep False unavailable: no websockets 14.0+ (its blocking client) for PY kick/buildbox in 0.00 s | ssh True ssh stood in" "  the sheep road's verdict a line in kicks.jsonl, never a crash"
printf '#!/bin/sh\nexit 1\n' > "$T/launchctl"; chmod +x "$T/launchctl"; export STUB_LAUNCHCTL="$T/launchctl"
check "$(python3 "$T/none.py" "$T/k.py" roads 2>&1)" "# this host's sheep press: unavailable: no websockets 14.0+ (its blocking client) for PY" "dispatch --roads notes it, as a # line"

echo "== the kick space (wharf-runs/kick-space)"
check "$(k no_space)" "False unavailable: no kick space (wharf-runs/kick-space)" "no space id configured: unavailable, nothing minted"
check "$(k bad_space)" "False unavailable: no kick space (wharf-runs/kick-space)" "a space id that is no id (a path, a query) is never put in the URL"
check "$(k ready)" "False unavailable: no kick space (wharf-runs/kick-space, the id of the page that declares kick/*) None" "press_ready says what is missing"
printf '# the kick page, published once\n\n0f1e2d3c-aaaa-bbbb-cccc-000000000001   (kick/*)\n' > "$REGATTA_CONFIG/wharf-runs/kick-space"
check "$(k ready)" "False unavailable: no full key on this host 0f1e2d3c-aaaa-bbbb-cccc-000000000001" "the space read past a # line, a blank one and a note; then the key is what is missing"
export XDG_CONFIG_HOME="$T/xdg"; mkdir -p "$XDG_CONFIG_HOME/spacesheep"; echo '{}' > "$XDG_CONFIG_HOME/spacesheep/config.json"
check "$(k ready)" "True  0f1e2d3c-aaaa-bbbb-cccc-000000000001" "with the CLI's login present: ready (presence only, no key read)"
check "$(STAND_WS=1 k roads)" "# this host's sheep press: ready (space 0f1e2d3c-aaaa-bbbb-cccc-000000000001)" "  and dispatch --roads says so"
rm -f "$XDG_CONFIG_HOME/spacesheep/config.json" "$REGATTA_CONFIG/wharf-runs/kick-space"; unset XDG_CONFIG_HOME

echo "== the whole press, against a local stub socket server"
if [ "$HAS_WS" != 1 ]; then
  echo "  --   skipped: this python3 ($(command -v python3)) has no websockets 14.0+, so the sheep road is unavailable"
  echo "       here too (the cases above prove what it says); a host that kicks over it has the package"
else
cat > "$T/srv.py" <<'PY'
import faulthandler, json, os, sys, threading, time
faulthandler.dump_traceback_later(20, exit=True)   # a hang fails this case, never the whole suite
sys.path.insert(0, os.environ["KB"])
import kicklib
from websockets.sync.server import serve

SPACE = "0f1e2d3c-aaaa-bbbb-cccc-000000000001"
seen = []


def process_request(conn, request):
    seen.append((request.path, request.headers.get("Cookie"), request.headers.get("Origin")))
    if request.headers.get("Cookie") != "ss_web=tok-1":
        return conn.respond(403, "no\n")
    return None


def handler(conn):
    try:
        conn.recv(timeout=5)
        snd = json.loads(conn.recv(timeout=5))
        stream = snd["path"]
        mode = stream.split("/", 1)[1]
        conn.send(json.dumps({"type": "ready", "allow": ["kick/*"], "press": True}))
        if mode == "closed":
            return
        conn.send(json.dumps({"type": "hello", "path": stream, "seq": 0, "listening": True}))
        conn.send(json.dumps({"type": "sent", "id": snd["id"], "ok": True, "path": stream, "seq": 6, "listening": True}))
        if mode == "quiet":
            time.sleep(4)
            return
        conn.send("pong")
        conn.send(json.dumps({"type": "ack", "path": stream, "seq": 6, "status": "started", "note": "kick"}))
        conn.send(json.dumps({"type": "ack", "path": stream, "seq": 6, "status": "done", "note": "exit 0"}))
        time.sleep(1)
    except Exception:
        pass


srv = serve(handler, "127.0.0.1", 0, process_request=process_request)
port = srv.socket.getsockname()[1]
threading.Thread(target=srv.serve_forever, daemon=True).start()
os.environ["SPACESHEEP_APP_ORIGIN"] = "http://127.0.0.1:%d" % port
cookie = sys.argv[2] if len(sys.argv) > 2 else "ss_web=tok-1"
kicklib.web_session = lambda key, timeout: cookie
t0 = time.monotonic()
ok, why, secs = kicklib.sheep_press("kick/" + sys.argv[1], "kick", {"kick": 1}, key="k", timeout=2, space=SPACE)
print(ok, why, "late" if time.monotonic() - t0 > 4 else "in time")
# what the stub was handed, the cookie judged here and never printed
print("seen", json.dumps([[p, c == "ss_web=tok-1", o] for p, c, o in seen[:1]]))
srv.shutdown()
PY
  out=$(python3 "$T/srv.py" ok 2>&1)
  has "$out" "True ack started in time" "ready, sent, ack started over a real socket: pressed"
  has "$out" "seen [[\"/api/space/0f1e2d3c-aaaa-bbbb-cccc-000000000001/streams/ws\", true, \"http://127.0.0.1:" "  at the space's streams socket, signed in by the web session's cookie, its Origin the app's"
  out=$(python3 "$T/srv.py" quiet 2>&1)
  has "$out" "False sent, no ack from the listener in time in time" "sent and no ack: not pressed, within the press's timeout"
  check "$(python3 "$T/srv.py" closed 2>&1 | head -1)" "False socket: ConnectionClosedOK in time" "the server closes before the sent: not pressed, saying how"
  out=$(python3 "$T/srv.py" ok "ss_web=wrong" 2>&1)
  has "$out" "False socket: HTTP 403 in time" "a session the server refuses at the handshake: its status, never its headers"
  case "$(printf '%s\n' "$out" | head -1)" in *wrong*) echo "  FAIL the cookie reached the verdict: $out"; fails=$((fails+1));; *) echo "  ok   the cookie never reaches the verdict";; esac
  out2=$(SPACESHEEP_APP_ORIGIN=http://127.0.0.1:9 python3 -c 'import os,sys; sys.path.insert(0, os.environ["KB"]); import kicklib
kicklib.web_session = lambda key, timeout: "c=1"
print(*kicklib.sheep_press("kick/x", "kick", {}, key="k", timeout=2, space="s1")[:2])' 2>&1)
  has "$out2" "False socket: ConnectionRefusedError" "nothing listening at the origin: not pressed, never a crash"
fi

echo
if [ "$fails" -eq 0 ]; then echo "test_kick_socket: all passed"; else echo "test_kick_socket: $fails failed"; fi
[ "$fails" -eq 0 ]
