#!/usr/bin/env bash
# Tests for bin/hail and the adapters' send(): one case per road against stand-ins, never a live
# session. The socket road posts to fake inbox servers in a scratch registry (live `sleep` pids with
# their real start times, a key file): one writes the transcript's enqueue line as Claude Code does,
# one stays silent (held). `codex`, `orca` and `ssh` are stubs on their HARNESS_* variables; Talk and
# file go through a stub asklib (HAIL_ASKLIB). Then the idle re-read, the frame's K13 rule, --dry-run,
# --when idle and `hail subs --fulfil`.
#   bash modules/wharf-runs/tests/test_hail.sh
set -u
unset CLAUDE_UNATTENDED CLAUDE_CODE_SESSION_ID DISPATCH_SKIPPER DISPATCH_MANAGER DISPATCH_PLAN_SPACE HAIL_SPACE HAIL_FROM
B="$(cd "$(dirname "$0")/../bin" && pwd)"
T=$(mktemp -d); T=$(cd "$T" && pwd -P)
PIDS=()
trap 'kill ${PIDS[@]+"${PIDS[@]}"} 2>/dev/null; rm -rf "$T"' EXIT
fails=0
check() { if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3: expected [$2] got [$1]"; fails=$((fails+1)); fi; }
has()   { if grep -qF -- "$2" "$1"; then echo "  ok   $3"; else echo "  FAIL $3: missing [$2]"; fails=$((fails+1)); fi; }
hasnt() { if grep -qF -- "$2" "$1"; then echo "  FAIL $3: found [$2]"; fails=$((fails+1)); else echo "  ok   $3"; fi; }
posted() { python3 -c 'import json, sys
for l in open(sys.argv[1]):
    d = json.loads(l)
    if d.get("type") == "user": print(d["message"]["content"])' "$1"; }   # the frames an inbox took
jget()  { python3 -c 'import json, sys; d = json.load(open(sys.argv[1])); print(eval(sys.argv[2]))' "$1" "$2" 2>&1; }

export REGATTA_CONFIG="${REGATTA_CONFIG:-$HOME/.config/regatta}"   # before HOME moves: the core is found there
export HOME="$T/home" HARNESS_HOST=laptop HARNESS_PEER_BUILDBOX=buildbox-ssh MEMO_STATE_DIR="$T/state" \
       HAIL_ASKLIB="$T/asklib.py" HAIL_FROM=tester HAIL_READBACK_S=3 \
       HARNESS_ORCA="$T/orca" STUB_ORCA_STATE="$T/orca.json" STUB_ORCA_CALLS="$T/orca.calls" \
       HARNESS_CODEX="$T/codex" STUB_CODEX_CALLS="$T/codex.calls" HARNESS_RUNS_DIR="$T/hruns" \
       STUB_TALK="$T/talk.log" STUB_FILE="$T/file.log"
unset HARNESS_SSH HARNESS_LAUNCHER CLAUDE_CONFIG_DIR CODEX_HOME ASK_SESSIONS_DIR STUB_FILE_OK
REG="$HOME/.claude/sessions"
mkdir -p "$REG" "$HOME/.claude/projects/-x" "$HOME/Library/Logs/claude-weekly/run-seed-runs" "$T/s" "$T/peer/.claude/sessions" "$T/peer/.claude/projects/-x"

# ---- stand-ins -------------------------------------------------------------------------------
cat > "$T/inbox.py" <<'PY'
# A fake inbox: reads each connection to EOF, logs the bytes; `ack` also writes the transcript's
# enqueue record of the user line, as Claude Code does when it takes a peer message
import datetime, json, os, socket, sys
path, logf, mode, transcript = sys.argv[1:5]
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.bind(path)
s.listen(5)
while True:
    c, _ = s.accept()
    c.settimeout(3)
    data = b""
    try:
        while True:
            chunk = c.recv(4096)
            if not chunk:
                break
            data += chunk
    except socket.timeout:
        pass
    c.close()
    with open(logf, "ab") as f:
        f.write(data)
    if mode != "ack":
        continue
    for line in data.decode().splitlines():
        d = json.loads(line)
        if d.get("type") == "user":
            at = datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%S.000Z")
            with open(transcript, "a") as f:
                f.write(json.dumps({"type": "queue-operation", "operation": "enqueue", "timestamp": at,
                                    "sessionId": os.path.basename(transcript)[:-6], "content": d["message"]["content"]}) + "\n")
PY
inbox() {   # inbox NAME MODE TRANSCRIPT: a server on $T/s/NAME.sock, logging to $T/NAME.log
  python3 "$T/inbox.py" "$T/s/$1.sock" "$T/$1.log" "$2" "$3" & PIDS+=($!); disown $!
  for _ in 1 2 3 4 5 6 7 8 9 10; do [ -S "$T/s/$1.sock" ] && return; sleep 0.2; done
  echo "  FAIL inbox $1 never bound"; fails=$((fails+1))
}
cat > "$T/asklib.py" <<'PY'
# helm's asklib, cut to what bin/hail calls: BACKENDS talk and file, standing_manager()
import os
class Talk:
    name = "talk"
    def available(self, ctx):
        return (True, "key and address") if ctx.get("space") else (False, "no plan space or manager id to address")
    def send(self, ctx, text):
        with open(os.environ["STUB_TALK"], "a") as f:
            f.write("%s %s %s\n" % (ctx["space"], ctx["manager"], text))
        return "sent", "talk: m-1"
class File:
    name = "file"
    def available(self, ctx):
        return (True, "this Mac") if os.environ.get("STUB_FILE_OK") else (False, "the manager is not on this Mac")
    def send(self, ctx, text):
        with open(os.environ["STUB_FILE"], "a") as f:
            f.write("%s %s\n" % (ctx["manager"], text))
        return "queued", "file: asks/%s.jsonl" % ctx["manager"]
BACKENDS = {"talk": Talk(), "file": File()}
def standing_manager(host=None):
    return None
PY
cat > "$T/codex" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >> "$STUB_CODEX_CALLS"
[ -n "${STUB_CODEX_FAIL:-}" ] && { echo "error: no thread $3" >&2; exit 1; }
exit 0
SH
cat > "$T/orca" <<'PY'
#!/usr/bin/env python3
# Orca's answers, cut to what the adapter's list and send read (shapes as test_harness.sh's stub)
import json, os, sys
args = [a for a in sys.argv[1:] if a != "--json"]
with open(os.environ["STUB_ORCA_CALLS"], "a") as f:
    f.write(" ".join(args) + "\n")
st = json.load(open(os.environ["STUB_ORCA_STATE"]))
opt = lambda k: args[args.index(k) + 1] if k in args else None
def out(res):
    print(json.dumps({"id": "x", "ok": True, "result": res}))
    sys.exit(0)
cmd = " ".join(args[:2])
if cmd == "orchestration worker-list":
    out({"workers": st["workers"], "page": {"hasMore": False}})
if cmd == "orchestration worker-show":
    out({})
if cmd == "orchestration run-show":
    out({"run": {"id": opt("--id"), "coordinator_handle": "term_coord"}})
if cmd == "orchestration send":
    out({"message": {"id": "msg_1"}})
if cmd == "terminal send":
    out({"submission": {"state": "submitted"}})
print(json.dumps({"id": "x", "ok": False, "error": {"message": "stub: no %s" % cmd}}))
sys.exit(1)
PY
cat > "$T/orca.json" <<'JSON'
{"workers": [
 {"dispatchId": "dsp_chat01", "taskId": "task_1", "runId": "run_1", "workerState": "ready", "dispatchStatus": "dispatched",
  "agentTerminalHandle": "structworker_1", "terminalState": "retained", "resource": {}},
 {"dispatchId": "dsp_term01", "taskId": "task_2", "runId": "run_1", "workerState": "ready", "dispatchStatus": "dispatched",
  "agentTerminalHandle": "term_7", "terminalState": "retained", "resource": {}}]}
JSON
chmod +x "$T/codex" "$T/orca"

# ---- the registry ----------------------------------------------------------------------------
sleeper() { sleep 600 & PIDS+=($!); disown $!; }
for i in 1 2 3 4 5 6 7 8; do sleeper; done
P=$(printf '%s,' "${PIDS[@]}")
# entry INDEX SID STATUS QUIET_S SOCKET_NAME [HOME]: a live registry record, idle for QUIET_S seconds
entry() {
  python3 - "${6:-$HOME}" "$P" "$1" "$2" "$3" "$4" "$5" "$T/s" <<'PY'
import json, os, subprocess, sys, time
home, pids, i, sid, status, quiet, sock, sdir = sys.argv[1:9]
pid = [int(p) for p in pids.split(",") if p][int(i)]
ps = " ".join(subprocess.run(["ps", "-o", "lstart=", "-p", str(pid)], capture_output=True, text=True,
                             env=dict(os.environ, TZ="UTC", LC_ALL="C")).stdout.split())
now = int(time.time() * 1000)
e = dict(pid=pid, sessionId=sid, cwd="/x", startedAt=now - 3600000, procStart=ps, kind="interactive", name="name-" + sid,
         status=status, updatedAt=now - int(quiet) * 1000, statusUpdatedAt=now - int(quiet) * 1000)
if sock != "-":
    e["messagingSocketPath"] = os.path.join(sdir, sock + ".sock")
json.dump(e, open(os.path.join(home, ".claude", "sessions", "%d.json" % pid), "w"))
PY
}
pid_of() { python3 -c 'import sys; print([p for p in sys.argv[1].split(",") if p][int(sys.argv[2])])' "$P" "$1"; }
TR="$HOME/.claude/projects/-x"
inbox ack ack "$TR/s-idle-0001.jsonl"
inbox ack2 ack "$TR/s-busy-0002.jsonl"
inbox silent silent "$TR/s-silent-03.jsonl"
inbox shell ack "$TR/s-shell-006.jsonl"
entry 0 s-idle-0001 idle 120 ack
printf '{"peerToken": "tok-test-1"}' > "$REG/$(pid_of 0).abc123.key"; chmod 600 "$REG/$(pid_of 0).abc123.key"
entry 1 s-busy-0002 busy 5 ack2
entry 2 s-silent-03 idle 300 silent
entry 3 s-fresh-004 idle 10 ack
entry 4 s-pipe-0005 idle 300 -
entry 5 s-shell-006 shell 90 shell
entry 6 s-perm-0007 waiting 300 ack
H() { python3 "$B/hail" "$@"; }

echo "socket: an idle session takes it, read back from its transcript"
H s-idle-0001 --text "the doc moved" --about "notes:claude/laptop/2026-10-21-x:docs/a.md#D2" --json > "$T/r.json"; check "$?" 0 "exit 0"
check "$(jget "$T/r.json" 'd["road"], d["verdict"], d["target"]')" "('socket', 'delivered', 's-idle-0001')" "road socket, delivered, the session id"
check "$(jget "$T/r.json" 'd["why"]')" "the receiver's transcript enqueued it" "delivered is the receiver's reading, never the socket's"
has "$T/ack.log" '{"type": "auth", "token": "tok-test-1"}' "the auth line carries the key file's peerToken"
check "$(posted "$T/ack.log")" "HAIL event from tester — the doc moved — about notes:claude/laptop/2026-10-21-x:docs/a.md#D2" "the user line carries the fixed frame"
check "$(python3 -c 'import sys; print(sys.stdin.read().count("\n"))' < "$T/ack.log")" "2" "two newline-terminated lines"
hasnt "$T/r.json" "tok-test-1" "the token is never printed"
check "$(jget "$T/r.json" 'd["notes"][0]')" "no commit found for notes:claude/laptop/2026-10-21-x: the frame has no @sha" "an unknown repo: no @sha, said"
check "$(wc -l < "$MEMO_STATE_DIR/hail.jsonl" | tr -d ' ')" "1" "the hail is logged under state_dir()"

echo "socket: a background shell is idle too (S1)"
H s-shell-006 --text "look" --json > "$T/r.json"; check "$(jget "$T/r.json" 'd["verdict"]')" "delivered" "status shell, 90 s quiet: delivered"

echo "the idle re-read refuses a session at work"
: > "$T/ack2.log"
H s-busy-0002 --text "look" --json > "$T/r.json"; check "$?" 2 "busy: exit 2"
check "$(jget "$T/r.json" 'd["road"], d["verdict"]')" "('socket', 'refused')" "busy: refused on the socket road"
has "$T/r.json" "a post would land at its next tool boundary" "the reason is the tool boundary"
check "$(wc -c < "$T/ack2.log" | tr -d ' ')" "0" "nothing was posted"
check "$(HAIL_SPACE=sp-1 H s-busy-0002 --text look --json | jget /dev/stdin 'd["road"], d["verdict"]')" "('socket', 'refused')" "a refusal is never routed around to Talk"
check "$(H s-fresh-004 --text look --json | jget /dev/stdin 'd["verdict"], "under 60 s" in d["why"]')" "('refused', True)" "idle 10 s: under the 60 s"
check "$(H s-perm-0007 --text look --json | jget /dev/stdin 'd["verdict"]')" "refused" "at a permission prompt: refused"
# the record harness read said idle; the file now says busy — the re-read is what counts
python3 - "$REG/$(pid_of 0).json" <<'PY'
import json, sys, time
p = sys.argv[1]; d = json.load(open(p)); d["status"] = "busy"; d["statusUpdatedAt"] = int(time.time() * 1000); json.dump(d, open(p, "w"))
PY
python3 - "$B" "$REG/$(pid_of 0).json" > "$T/reread.out" <<'PY'
import importlib.machinery, importlib.util, json, sys, time
b, p = sys.argv[1], sys.argv[2]
ld = importlib.machinery.SourceFileLoader("cc", b + "/harness_adapters/claude_code.py")
cc = importlib.util.module_from_spec(importlib.util.spec_from_loader("cc", ld)); ld.exec_module(cc)
d = json.load(open(p))
rec = {"session_id": d["sessionId"], "pid": d["pid"], "state": "idle"}   # stale: read before it turned busy
print(cc.send(None, rec, {"frame": "HAIL event from tester — x", "idle_s": 60})["verdict"])
PY
check "$(cat "$T/reread.out")" "refused" "send() re-reads the registry: a record read idle that is now busy is refused"
entry 0 s-idle-0001 idle 120 ack

echo "held: posted, nothing on the receiver's side, then Talk"
H s-silent-03 --text look --json > "$T/r.json"; check "$?" 0 "held exits 0"
check "$(jget "$T/r.json" 'd["road"], d["verdict"]')" "('socket', 'held')" "no enqueue within HAIL_READBACK_S: held"
has "$T/silent.log" '"type": "user"' "the post did go out"
HAIL_SPACE=sp-1 H s-silent-03 --text look --json > "$T/r.json"
check "$(jget "$T/r.json" 'd["road"], d["verdict"], d["tried"][0][0]')" "('talk', 'queued', 'socket')" "held falls through to Talk, the socket named in tried"

echo "talk and file: a session with no inbox"
HAIL_SPACE=sp-1 H s-pipe-0005 --text look --json > "$T/r.json"; check "$?" 0 "exit 0"
check "$(jget "$T/r.json" 'd["road"], d["verdict"]')" "('talk', 'queued')" "no inbox (-p): Talk, queued"
has "$T/talk.log" "sp-1 s-pipe-0005 HAIL event from tester" "Talk addressed to the page and the session id"
STUB_FILE_OK=1 H s-pipe-0005 --text look --json > "$T/r.json"
check "$(jget "$T/r.json" 'd["road"], d["verdict"]')" "('file', 'queued')" "no page: the file queue"
has "$T/file.log" "s-pipe-0005 HAIL event from tester" "the file line names the session"
H s-pipe-0005 --text look --json > "$T/r.json"; check "$?" 3 "no road at all: exit 3"
check "$(jget "$T/r.json" 'd["verdict"], len(d["tried"])')" "('unreachable', 3)" "unreachable, each road tried named"
HAIL_ASKLIB="$T/none.py" H s-pipe-0005 --text look --json > "$T/r.json"
has "$T/r.json" "helm's asklib is not installed" "asklib absent: one line, no trace"
HAIL_SPACE=sp-1 H nobody-xyz --text look --json > "$T/r.json"
check "$(jget "$T/r.json" 'd["road"], d["tried"][0][1]')" "('talk', \"no session here answers to 'nobody-xyz'\")" "a session on no registry here: Talk only"

echo "codex: by an explicit thread"
H codex-label --thread th-0001 --text look --kind report --json > "$T/r.json"; check "$?" 0 "exit 0"
check "$(jget "$T/r.json" 'd["road"], d["verdict"], d["target"]')" "('codex', 'queued', 'th-0001')" "codex queue: queued on the thread"
check "$(cat "$T/codex.calls")" "queue --thread th-0001 --message HAIL report from tester — look" "the argv: queue, the thread, the frame"
STUB_CODEX_FAIL=1 HAIL_SPACE=sp-1 H codex-label --thread th-0002 --text look --json > "$T/r.json"
check "$(jget "$T/r.json" 'd["road"], d["tried"][0][0]')" "('talk', 'codex')" "codex queue failing: Talk takes it"

echo "orca: a chat worker's mailbox, a terminal worker only idle"
H dsp_chat01 --text look --json > "$T/r.json"; check "$?" 0 "exit 0"
check "$(jget "$T/r.json" 'd["road"], d["verdict"], d["why"]')" "('orca', 'queued', 'orchestration send: message msg_1')" "chat worker: orchestration send"
has "$T/orca.calls" "orchestration send --to dispatch:dsp_chat01 --from term_coord --subject hail event --body HAIL event from tester — look" "sent from the run's coordinator"
H dsp_term01 --text look --json > "$T/r.json"; check "$?" 2 "a terminal worker at work: exit 2"
hasnt "$T/orca.calls" "terminal send" "nothing typed into a busy terminal"

echo "ssh: the adapter roads on the peer"
P_ACK="$T/peer/.claude/projects/-x/p-idle-0001.jsonl"
inbox peer ack "$P_ACK"
entry 7 p-idle-0001 idle 200 peer "$T/peer"
cat > "$T/ssh" <<EOF
#!/bin/sh
# the last argument is the remote command; run it here as the peer would, reading stdin
for a; do last=\$a; done
[ "\$5" = buildbox-ssh ] || { echo "wrong alias \$5" >&2; exit 255; }
printf '%s\n' "\$last" >> "$T/ssh.calls"
cd / && HOME="$T/peer" HARNESS_HOST=buildbox HARNESS_LAUNCHER="$B/.." MEMO_STATE_DIR="$T/peer-state" exec sh -c "\$last"
EOF
chmod +x "$T/ssh"
HARNESS_SSH="$T/ssh" H p-idle-0001 --host buildbox --text look --json > "$T/r.json"; check "$?" 0 "exit 0"
check "$(jget "$T/r.json" 'd["road"], d["verdict"], d["host"]')" "('socket', 'delivered', 'buildbox')" "delivered on the peer, read back there"
posted "$T/peer.log" > "$T/frames" 2>/dev/null; has "$T/frames" "HAIL event from tester — look" "the peer's inbox got the frame built here"
has "$T/ssh.calls" "--peer-half" "the peer runs the adapter half only"
printf '#!/bin/sh\necho "ssh: connect to host buildbox port 22: Operation timed out" >&2; exit 255\n' > "$T/ssh-down"; chmod +x "$T/ssh-down"
HARNESS_SSH="$T/ssh-down" HAIL_SPACE=sp-1 H p-idle-0001 --host buildbox --text look --json > "$T/r.json"
check "$(jget "$T/r.json" 'd["road"], d["tried"][0][0]')" "('talk', 'ssh')" "a peer that does not answer: Talk from here"
HARNESS_HOST=buildbox HAIL_SPACE=sp-1 H x-session --host laptop --text look --json > "$T/r.json"
check "$(jget "$T/r.json" 'd["road"], "ssh runs one way" in d["tried"][0][1]')" "('talk', True)" "no ssh alias back: Talk only"

echo "the frame never carries an answer"
REPO="$T/repo"; git init -q "$REPO"; git -C "$REPO" checkout -q -b claude/laptop/2026-10-21-doc
mkdir -p "$REPO/docs"; printf '## D1\n\n➤ Answer:\n\nB, the secret-word plan\n' > "$REPO/docs/d.md"
git -C "$REPO" add -A; git -C "$REPO" -c user.name=t -c user.email=t@example.com commit -qm doc
SHA=$(git -C "$REPO" rev-parse --short HEAD)
: > "$T/ack.log"
H s-idle-0001 --text "answered on the page" --about "$REPO:claude/laptop/2026-10-21-doc:docs/d.md#D1" --json > "$T/r.json"
check "$(jget "$T/r.json" 'd["verdict"]')" "delivered" "a hail about an answered doc is delivered"
posted "$T/ack.log" > "$T/frames"; has "$T/frames" "about $REPO:claude/laptop/2026-10-21-doc:docs/d.md#D1 @$SHA" "the frame names the doc, the item and the branch's commit"
hasnt "$T/ack.log" "secret-word" "the answer's words are not in it"
: > "$T/ack.log"
H s-idle-0001 --text "➤ Answer: B" --json > "$T/r.json"; check "$?" 2 "an answer in the text: exit 2"
has "$T/r.json" "never ride in a hail (K13)" "refused by K13"
H s-idle-0001 --text "Relayed from manager (talk, 2026-10-21): yes" --json > /dev/null; check "$?" 2 "a relayed answer: refused"
H s-idle-0001 --text "$(python3 -c 'print("x" * 401)')" --json > /dev/null; check "$?" 2 "over 400 characters: refused"
check "$(wc -c < "$T/ack.log" | tr -d ' ')" "0" "none of them was posted"
CLAUDE_CODE_SESSION_ID=s-idle-0001 H s-idle-0001 --text look --json > "$T/r.json"; check "$?" 2 "a session does not hail itself"
H s-idle-0001 --text "fyi Relayed from manager (talk, 2026-10-21): yes" --json > /dev/null; check "$?" 2 "a relay quoted mid-line: refused"
H s-idle-0001 --text look --about "r:b:docs/x.md ➤ Answer: B" --json > /dev/null 2>&1; check "$?" 1 "an --about that is not a path: refused"
H --peer-half s-idle-0001 --frame "➤ Answer: B, not a frame" > "$T/r.json"; check "$?" 2 "--peer-half: a frame that is not a hail's, exit 2"
has "$T/r.json" "not a HAIL frame" "said why"
H --peer-half s-idle-0001 --frame "HAIL event from x — ➤ Answer: B" > /dev/null; check "$?" 2 "--peer-half: an answer in the frame, exit 2"
H --peer-half s-idle-0001 > /dev/null; check "$?" 2 "--peer-half without --frame: exit 2, no traceback"
check "$(wc -c < "$T/ack.log" | tr -d ' ')" "0" "none of them was posted"

echo "--dry-run prints the record and sends nothing"
N=$(wc -l < "$MEMO_STATE_DIR/hail.jsonl")
H s-idle-0001 --text look --dry-run --json > "$T/r.json"; check "$?" 0 "exit 0"
check "$(jget "$T/r.json" 'd["road"], d["verdict"], d["dry_run"], d["frame"]')" "('socket', 'dry-run', True, 'HAIL event from tester — look')" "the road, the verdict dry-run, the frame"
check "$(jget "$T/r.json" 'sorted(k for k in ("road", "verdict", "target", "at") if k in d)')" "['at', 'road', 'target', 'verdict']" "the contract's four keys"
check "$(wc -c < "$T/ack.log" | tr -d ' ')" "0" "nothing posted"
check "$(wc -l < "$MEMO_STATE_DIR/hail.jsonl")" "$N" "nothing logged"
H codex-label --thread th-9 --text look --dry-run --json > /dev/null; check "$(grep -c th-9 "$T/codex.calls")" "0" "codex: not called"
H dsp_chat01 --text look --dry-run --json > /dev/null; check "$(grep -c 'orchestration send' "$T/orca.calls")" "1" "orca: no send"

echo "--when idle: a subscription, fulfilled by the tick"
: > "$T/ack2.log"
H s-busy-0002 --text "the doc moved" --when idle --json > "$T/r.json"; check "$?" 0 "subscribed: exit 0"
check "$(jget "$T/r.json" 'd["road"], d["verdict"], d["target"]')" "('subs', 'queued', 's-busy-0002')" "road subs, queued"
SUBS="$MEMO_STATE_DIR/hail-subs.jsonl"
check "$(wc -l < "$SUBS" | tr -d ' ')" "1" "one row under state_dir()"
H s-busy-0002 --text again --when idle --dry-run --json > /dev/null; check "$(wc -l < "$SUBS" | tr -d ' ')" "1" "a dry subscription writes no row"
H subs --json > "$T/subs.json"; check "$(jget "$T/subs.json" 'd[0]["target"], d[0]["kind"]')" "('s-busy-0002', 'event')" "hail subs lists it"
H subs --fulfil --json > "$T/f.json"; check "$?" 0 "fulfil while busy: exit 0"
check "$(jget "$T/f.json" 'd[0]["verdict"], d[0]["kept"]')" "('refused', True)" "still busy: kept"
check "$(wc -l < "$SUBS" | tr -d ' ')" "1" "the row stays"
check "$(wc -c < "$T/ack2.log" | tr -d ' ')" "0" "nothing posted while it works"
entry 1 s-busy-0002 idle 120 ack2
H subs --fulfil --dry-run --json > "$T/f.json"; check "$(jget "$T/f.json" 'd[0]["verdict"]')" "dry-run" "a dry fulfil says what it would do"
check "$(wc -l < "$SUBS" | tr -d ' ')" "1" "and keeps the row"
H subs --fulfil --json > "$T/f.json"; check "$?" 0 "fulfil once idle: exit 0"
check "$(jget "$T/f.json" 'd[0]["road"], d[0]["verdict"]')" "('socket', 'delivered')" "idle: hailed and read back"
posted "$T/ack2.log" > "$T/frames"; has "$T/frames" "HAIL event from tester — the doc moved" "the frame stored at subscription time"
check "$(wc -l < "$SUBS" | tr -d ' ')" "0" "the row is dropped"
H s-idle-0001 --text now --when idle --json > "$T/r.json"
check "$(jget "$T/r.json" 'd["road"], d["verdict"]')" "('socket', 'delivered')" "--when idle on an idle session sends now"
# a target that ends, and a row past its time
python3 - "$SUBS" <<'PY'
import json, sys, time
rows = [{"id": "gone1", "at": int(time.time()), "ref": "s-ended-99", "target": "s-ended-99", "host": "here", "kind": "event",
         "text": "x", "frame": "HAIL event from tester — x"},
        {"id": "old1", "at": int(time.time()) - 80 * 3600, "ref": "s-busy-0002", "target": "s-busy-0002", "host": "here",
         "kind": "event", "text": "x", "frame": "HAIL event from tester — x"}]
open(sys.argv[1], "w").write("".join(json.dumps(r) + "\n" for r in rows))
PY
H subs --fulfil --json > "$T/f.json"; check "$?" 3 "a target gone with no road: exit 3"
check "$(jget "$T/f.json" '[(r["sub"], r["verdict"]) for r in d]')" "[('gone1', 'unreachable'), ('old1', 'unreachable')]" "the ended one tried, the old one expired"
has "$T/f.json" "expired after 72 h unsent" "the expiry is said"
check "$(wc -l < "$SUBS" | tr -d ' ')" "0" "both dropped"
printf '{"id": "cut\n{"id": "ok1", "at": %s, "ref": "s-busy-0002", "target": "s-busy-0002", "host": "here", "kind": "event", "text": "x", "frame": "HAIL event from tester — x"}\n' "$(date +%s)" > "$SUBS"
H subs --json > "$T/subs.json" 2> "$T/err"; check "$(jget "$T/subs.json" '[r["id"] for r in d]')" "['ok1']" "a line that does not parse costs only itself"
has "$T/err" "line 1 does not parse" "and is named"

echo
if [ "$fails" -eq 0 ]; then echo "test_hail: all passed"; else echo "test_hail: $fails failed"; fi
[ "$fails" -eq 0 ]
