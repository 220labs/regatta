#!/usr/bin/env bash
# Tests for bin/harness and its adapters. V3 status and V4 list of Claude Code: a fixture HOME with
# a registry (~/.claude/sessions/<pid>.json) whose pids are live `sleep`s with their real start
# times, transcripts, and dispatch run records — one per state mapping in the adapter's header —
# read through the real bin/dispatch-rc. A fake ssh runs the peer's half locally from stdin.
# V1 run, V2 (the next turn) and V5 stop (B5 part 2) of all three adapters against stand-ins on PATH: a
# `dispatch` that writes run records, an `orca` that answers in the shapes Orca 1.4.225 printed on
# 2026-10-14 and makes real git worktrees, a `codex` that prints `exec --json` events. No real
# agent is started. Codex's research mode (principal tier S3): its profile, --review, the timeout, the
# refusals judged by --repo, the unattended bound and dispatch-rc's count of a running one. Last, on a Mac with `claude`: the real list against `claude agents --json`.
#   bash modules/wharf-runs/tests/test_harness.sh
set -u
# an unattended /finish runs this check: the cases are an attended caller unless they say — and harness's
# unattended() reads every marker (the core's unattended_caller; the council's second landing review, finding 12)
unset CLAUDE_UNATTENDED REGATTA_UNATTENDED AUTOFINISH_CALLER_UNATTENDED DISPATCH_DEPTH DISPATCH_MAX_DEPTH
B="$(cd "$(dirname "$0")/../bin" && pwd)"   # the module's bin/ (B7: the suites moved to tests/)
T=$(mktemp -d); T=$(cd "$T" && pwd -P)
# F4's start probe reads every process of this user (finding 1): a stand-in names none (fence.sh has the live cases)
: > "$T/holders-none"; export REGATTA_FENCE_HOLDERS="$T/holders-none"
PIDS=()
trap 'kill ${PIDS[@]+"${PIDS[@]}"} $(cat "$T/stub.pids" 2>/dev/null) 2>/dev/null; rm -rf "$T"' EXIT
fails=0
# a recursive delete under HOME goes through here: only under the suite's own $T (the core's home_rm lint)
rm_own() { local p; for p; do case "$p" in */..|*/../*|*//*) ;; "${T:?}"/?*) rm -rf -- "$p"; continue ;; esac; echo "rm_own: refused $p, outside $T" >&2; return 1; done; }
check() { if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3: expected [$2] got [$1]"; fails=$((fails+1)); fi; }
has()   { if grep -qF -- "$2" "$1"; then echo "  ok   $3"; else echo "  FAIL $3: missing [$2]"; fails=$((fails+1)); fi; }
hasnt() { if grep -qF -- "$2" "$1"; then echo "  FAIL $3: has [$2]"; fails=$((fails+1)); else echo "  ok   $3"; fi; }

REAL_HOME=$HOME
. "$(cd "$(dirname "$0")" && pwd)/config_fixture.sh"; fixture_config "$T/config"   # the suite's own config dir, never the login's (config_fixture.sh)
export HOME="$T/home" HARNESS_HOST=laptop
HD="$T/home"   # the suite's HOME, by a name the publish gate reads as no home path (finding 6: never a bare HOME)
unset HARNESS_PEER_BUILDBOX HARNESS_SSH HARNESS_LAUNCHER CLAUDE_CONFIG_DIR CODEX_HOME
mkdir -p "$HD/.claude/sessions" "$HD/.claude/projects" "$HD/Library/Logs/claude-weekly/run-seed-runs"
# the stand-ins (written below) answer every orca, codex and dispatch call, from the first list on:
# the real Orca app is never asked, and ELECTRON_RUN_AS_NODE=1, as a VS Code session has it, must be
# cleared before each orca call (lessons/claude-code.md)
export HARNESS_ORCA="$T/orca" STUB_ORCA_STATE="$T/orca.state" STUB_ORCA_CALLS="$T/orca.calls" STUB_ORCA_WS="$T/orca-ws" \
       HARNESS_CODEX="$T/cbin/codex" STUB_CODEX_CALLS="$T/codex.calls" HARNESS_DISPATCH="$T/dispatch" \
       STUB_DISPATCH_CALLS="$T/dispatch.calls" STUB_PIDS="$T/stub.pids" HARNESS_RUNS_DIR="$T/hruns" \
       HARNESS_LOG_DIR="$T/hlogs" HARNESS_START_WAIT=8 ELECTRON_RUN_AS_NODE=1
mkdir -p "$STUB_ORCA_WS"

cat > "$T/orca" <<'PY'
#!/usr/bin/env python3
# Orca 1.4.225's answers, cut down to the fields the adapter reads (shapes from the live probe)
import json, os, subprocess, sys
args = [a for a in sys.argv[1:] if a != "--json"]
with open(os.environ["STUB_ORCA_CALLS"], "a") as f:
    f.write("%s ELECTRON_RUN_AS_NODE=%s\n" % (" ".join(args), os.environ.get("ELECTRON_RUN_AS_NODE", "unset")))
try:
    st = json.load(open(os.environ["STUB_ORCA_STATE"]))
except (OSError, ValueError):
    st = {"repos": [], "workers": {}, "n": 0, "terminals": {}}
opt = lambda k: args[args.index(k) + 1] if k in args else None
def out(res, ok=True):
    json.dump(st, open(os.environ["STUB_ORCA_STATE"], "w"))
    print(json.dumps({"id": "x", "ok": True, "result": res} if ok else {"id": "x", "ok": False, "error": res}))
    sys.exit(0 if ok else 1)
cmd = " ".join(args[:2])
if cmd == "repo list":
    out({"repos": st["repos"]})
if cmd == "repo add":
    r = {"id": "repo-1", "path": opt("--path")}; st["repos"].append(r); out({"repo": r})
if cmd == "worktree create":
    name, repo = opt("--name"), next(r for r in st["repos"] if r["id"] == opt("--repo"))
    # Orca's own naming: its prefix setting, then the name; STUB_ORCA_PREFIX plays a different setting
    branch = os.environ.get("STUB_ORCA_PREFIX", "claude/laptop/") + name
    path = os.path.join(os.environ["STUB_ORCA_WS"], name)
    subprocess.run(["git", "-C", repo["path"], "worktree", "add", "-q", "-b", branch, path], check=True, capture_output=True)
    wid = "repo-1::" + path
    st["terminals"][wid] = "term_shell"
    out({"worktree": {"id": wid, "path": path, "branch": "refs/heads/" + branch}})
if cmd == "terminal list":
    wid = opt("--worktree")[3:]
    out({"terminals": [{"handle": st["terminals"][wid], "worktreeId": wid}] if wid in st["terminals"] else []})
if cmd == "orchestration run-create":
    out({"run": {"id": "run_1", "coordinator_handle": opt("--from")}})
if cmd == "orchestration run-show":
    out({"run": {"id": opt("--id"), "coordinator_handle": "term_shell"}})
if cmd == "terminal create":
    st["n"] += 1
    h = "term_own_%d" % st["n"]
    st.setdefault("own", {})[h] = {"command": opt("--command"), "worktree": opt("--worktree"), "tries": 0}
    out({"terminal": {"handle": h, "worktreeId": opt("--worktree")[3:]}})
if cmd == "terminal close":
    st.setdefault("closed", []).append(opt("--terminal")); out({"close": {"handle": opt("--terminal"), "ptyKilled": True}})
if cmd == "terminal read":
    out({"terminal": {"handle": opt("--terminal"), "tail": [os.environ.get("STUB_ORCA_SCREEN", "")]}})
if cmd == "orchestration worker-start" and opt("--terminal"):
    own = st.get("own", {}).get(opt("--terminal"))
    # Orca knows the agent in a terminal only from its hook events: the first tries are refused (probe 2026-10-16)
    if own is not None and own["tries"] < int(os.environ.get("STUB_ORCA_UNCONF", "1")):
        own["tries"] += 1
        out({"code": "agent_unconfigured", "message": "Terminal %s is not running a recognized agent." % opt("--terminal")}, ok=False)
if cmd == "orchestration worker-start":
    st["n"] += 1
    did = "ctx_%012d" % st["n"]
    st["workers"][did] = {"dispatchId": did, "taskId": "task_1", "runId": opt("--run"), "workerState": "ready",
        "dispatchStatus": "dispatched", "agentTerminalHandle": "structworker_%d" % st["n"], "terminalState": "active",
        "resource": {"worktreeId": opt("--worktree")[3:], "releaseState": "not_requested"},
        "projection": {"stage": {"worker": "ready", "dispatch": "dispatched", "detail": "input_accepted", "activity": "unknown"},
                       "outcome": "in_progress", "liveness": {"verdict": "unverifiable", "reason": "missing_status"},
                       "nextAction": {"kind": "none", "argv": []}},
        "_agent": opt("--agent"), "_model": opt("--model"), "_effort": opt("--effort"), "_terminal": opt("--terminal")}
    if opt("--terminal"):
        st["workers"][did].update(agentTerminalHandle=opt("--terminal"), terminalState="retained")
        st["workers"][did]["resource"].update(ownershipState="external", retainedReason="external_terminal")
    out({"dispatch": {"id": did}, "stage": "input_accepted"})
if cmd == "orchestration worker-list":
    rows = [{k: v for k, v in w.items() if not k.startswith("_")} for w in st["workers"].values() if not opt("--run") or w["runId"] == opt("--run")]
    out({"workers": rows[::-1], "page": {"hasMore": False, "nextCursor": None}, "scope": {"source": "all"}})
if cmd == "orchestration worker-show":
    w = st["workers"][opt("--dispatch")]
    out({"dispatch": {"id": w["dispatchId"], "status": w["dispatchStatus"], "createdAt": "2026-10-15 05:03:05",
                      "completedAt": w.get("_completed"), "lastFailure": w.get("_failure"), "terminationReason": None},
         "worker": {"state": w["workerState"], "updatedAt": "2026-10-15 05:03:06", "worktreeId": w["resource"]["worktreeId"],
                    "startOptions": {"agent": w["_agent"], "launch": {"effective": {"agent": w["_agent"], "model": w["_model"], "effort": w["_effort"]}}}},
         "projection": w["projection"], "observation": {"status": "live", "exactWorker": True, "addressable": True}})
if cmd == "orchestration worker-stop":
    w = st["workers"][opt("--dispatch")]
    w.update(workerState="stopped", dispatchStatus="failed", terminalState="retained", _failure="stopped", _completed="2026-10-15T05:07:54.028Z")
    w["projection"].update(outcome="failed", liveness={"verdict": "exited", "source": "worker_stop"},
                           nextAction={"kind": "release", "argv": ["orchestration", "worker-release", "--dispatch", w["dispatchId"]]})
    out({"status": "stopped"})
if cmd == "orchestration worker-release":
    w = st["workers"][opt("--dispatch")]
    w.update(terminalState="released"); w["resource"]["releaseState"] = "released"
    w["projection"].update(liveness={"verdict": "exited", "source": "resource_release"}, nextAction={"kind": "none", "argv": []})
    out({"status": "released"})
if cmd == "orchestration worker-read":
    out({"source": "transcript", "transcript": {"messages": [{"role": "assistant", "blocks": [{"type": "text", "text": "DONE"}]}]}})
if cmd == "orchestration send":
    out({"message": {"id": "msg_1"}})
if cmd == "terminal send":
    out({"code": "terminal_unsupported_for_agent_session", "message": "is an agent session, not a terminal"}, ok=False)
out({"code": "stub", "message": "the stub has no %s" % cmd}, ok=False)
PY
# in a folder of its own: research mode's seatbelt reads the CLI's install folder, and $T holds the suite's HOME
mkdir -p "$T/cbin"; cat > "$T/cbin/codex" <<'SH'
#!/bin/sh
# codex exec --json, as OpenAI documents its events; the prompt arrives on stdin ("-"). Research mode starts it
# under the seatbelt, where $STUB_CODEX_CALLS (outside its box) is refused: what it was given goes into its own
# events as a {"type": "stub"} line too. The listing research mode reads first: the features (a `plugin list` is
# no longer asked; one would be written down). STUB_CODEX_VENDOR: its first request to chatgpt.com through the proxy,
# as codex makes it (F7 withdraws the box's auth.json there); STUB_CODEX_CMD: a command item, codex's first tool call.
case "$1 $2" in
  "plugin list") echo "codex plugin list" >> "$STUB_CODEX_CALLS"; exit 0;;
  "features list") [ -n "${STUB_LOCKDIR:-}" ] && { [ -d "$STUB_LOCKDIR" ] && echo held || echo free; } >> "$STUB_LOCKLOG"
                   cat "$STUB_FEATURES"; exit 0;;
esac
in=$(cat)
[ -n "${STUB_CODEX_VENDOR:-}" ] && python3 -c 'import os, socket
h, p = os.environ["HTTPS_PROXY"].split("//")[1].rsplit(":", 1)
s = socket.create_connection((h, int(p)), timeout=5); s.sendall(b"CONNECT chatgpt.com:443 HTTP/1.1\r\n\r\n"); s.recv(200); s.close()' 2>/dev/null
# what the child was handed (vendor-fence): the marker, no Claude session, its own TMPDIR
[ -n "${STUB_CODEX_KID:-}" ] && { sleep 60 & echo $! > kid.pid; }   # left running by the arm's shell (round 3)
( echo "codex $*" >> "$STUB_CODEX_CALLS"; echo "stdin: $in" >> "$STUB_CODEX_CALLS"
  echo "env: RU=${REGATTA_UNATTENDED:-unset} CU=${CLAUDE_UNATTENDED:-unset} SID=${CLAUDE_CODE_SESSION_ID:-unset} PH=${PLAN_HARNESS:-unset} TMP=${TMPDIR:-unset}" >> "$STUB_CODEX_CALLS" ) 2>/dev/null
python3 -c 'import json, os, sys; print(json.dumps({"type": "stub", "argv": sys.argv[1], "stdin": sys.argv[2], "cwd": os.getcwd(),
  "env": {k: os.environ.get(k) for k in ("CODEX_HOME", "HOME", "HTTPS_PROXY")}, "names": sorted(os.environ)}))' "$*" "$in"
echo '{"type":"thread.started","thread_id":"'"${STUB_CODEX_THREAD:-th-000001}"'"}'
echo '{"type":"turn.started"}'
if [ -n "${STUB_CODEX_RATE:-}" ]; then
  echo '{"type":"turn.failed","error":{"message":"You have hit your usage limit. Try again in 3 hours."}}'; exit 1
fi
# a TERM waits for the sleep in hand before its trap runs: 0.2 s steps, not 1 s, as test_dispatch's stub
if [ -n "${STUB_CODEX_HOLD:-}" ]; then trap 'exit 143' TERM; while :; do sleep 0.2; done; fi
[ -n "${STUB_CODEX_CMD:-}" ] && echo '{"type":"item.completed","item":{"id":"c1","type":"command_execution","command":"ls","exit_code":0}}'
echo '{"type":"item.completed","item":{"id":"i1","type":"agent_message","text":"DONE"}}'
echo '{"type":"turn.completed","usage":{"input_tokens":1,"output_tokens":1}}'
SH
cat > "$T/dispatch" <<'PY'
#!/usr/bin/env python3
# bin/dispatch's part the adapter relies on: --start writes a run record (a `sleep` stands in for
# claude) and prints claude's line; --end ends the topic's live run; a branch is "through launchd"
import json, os, re, subprocess, sys, time
a = sys.argv[1:]
open(os.environ["STUB_DISPATCH_CALLS"], "a").write(" ".join(a) + "\n")
if a[0] == "--slots":   # the run cap a non-Claude start asks (vendor-fence): STUB_SLOTS `<busy> <cap>`, or garbage
    print(os.environ.get("STUB_SLOTS", "0 4")); sys.exit(0)
runs =os.path.join(os.environ["HOME"], "Library", "Logs", "claude-weekly", "run-seed-runs")
lstart = lambda pid: " ".join(subprocess.run(["ps", "-o", "lstart=", "-p", str(pid)], capture_output=True, text=True,
                                             env=dict(os.environ, TZ="UTC", LC_ALL="C")).stdout.split())
if a and a[0] == "--cap":   # bin/dispatch's cap alone (research mode asks it unattended)
    print(os.environ.get("STUB_DISPATCH_CAP") or "99"); sys.exit(0)
if os.environ.get("STUB_DISPATCH_FAIL"):
    print("FAILED: %s" % os.environ["STUB_DISPATCH_FAIL"]); sys.exit(1)
if a[0] == "--start":
    prompt, wt, name = a[1:4]
    sid = a[a.index("--session-id") + 1] if "--session-id" in a else a[a.index("--resume") + 1]
    p = subprocess.Popen(["sleep", "120"], start_new_session=True)
    open(os.environ["STUB_PIDS"], "a").write("%d\n" % p.pid)
    open(os.environ["STUB_PIDS"] + ".sid", "w").write("%d\n" % os.getsid(0))   # dispatch's own session
    topic = re.sub(r"-+", "-", re.sub(r"[^A-Za-z0-9-]", "-", name)).strip("-").lower()
    common = subprocess.run(["git", "-C", wt, "rev-parse", "--path-format=absolute", "--git-common-dir"], capture_output=True, text=True).stdout.strip()
    st = dict(mode="rc", branch=subprocess.run(["git", "-C", wt, "symbolic-ref", "--short", "HEAD"], capture_output=True, text=True).stdout.strip(),
              repo=os.path.dirname(common), topic=topic, session=sid, pid=p.pid, proc_start=lstart(p.pid), started=int(time.time()),
              wt=wt, screen="run-x-" + topic, model=a[a.index("--model") + 1] if "--model" in a else "opus")
    if "--resume" in a:
        st["resumed_from"] = a[a.index("--resume") + 1]
    json.dump(st, open(os.path.join(runs, "%s-x.%s.%s.json" % (time.strftime("%Y%m%d-%H%M%S"), topic, sid[:8])), "w"))
    print("== claude %d, session %s" % (p.pid, sid)); sys.exit(0)
if a[0] == "--end":
    for n in sorted(os.listdir(runs)):
        st = json.load(open(os.path.join(runs, n)))
        if st.get("topic") == a[1] and not st.get("ended") and "screen" in st and n.endswith(".json"):
            try:
                os.kill(int(st["pid"]), 15)
            except OSError:
                continue
            st.update(ended=int(time.time()), end_reason="ended by dispatch --end (was busy)")
            json.dump(st, open(os.path.join(runs, n), "w"))
            print("ended"); sys.exit(0)
    print("no live run of %s" % a[1]); sys.exit(1)
print("dispatch: through launchd, in about 2 min — run here, it would die with this shell"); sys.exit(0)
PY
chmod +x "$T/orca" "$T/cbin/codex" "$T/dispatch"

# one live process per registry entry and live run: `sleep`s, so pid and start time are real
sleeper() { sleep 600 & PIDS+=($!); disown $!; }   # disowned: no "Terminated" lines at the end
for i in $(seq 1 18); do sleeper; done
DEAD=$(sh -c 'echo $$')   # a pid that has exited
P=$(printf '%s,' "${PIDS[@]}")
REPO="$T/repo"; git init -q "$REPO"; git -C "$REPO" checkout -q -b claude/laptop/2026-10-14-fixture
printf -- '- physical: none\n' > "$REPO/AGENTS.md"   # bin/harness run's rule, as dispatch's

python3 - "$HD" "$P" "$DEAD" "$REPO" <<'PY'
import json, os, re, subprocess, sys, time
home, pids, dead, repo = sys.argv[1], [int(p) for p in sys.argv[2].split(",") if p], int(sys.argv[3]), sys.argv[4]
def lstart(pid):
    r = subprocess.run(["ps", "-o", "lstart=", "-p", str(pid)], capture_output=True, text=True, env=dict(os.environ, TZ="UTC", LC_ALL="C"))
    return " ".join(r.stdout.split())
now = int(time.time() * 1000)
reg = os.path.join(home, ".claude", "sessions")
def entry(i, sid, status, cwd="/tmp/x", **kw):
    pid = pids[i]
    e = dict(pid=pid, sessionId=sid, cwd=cwd, startedAt=now - 3600000, procStart=lstart(pid), version="2.1.300",
             kind="interactive", entrypoint="cli", name="name-" + sid, status=status, updatedAt=now - 60000,
             statusUpdatedAt=now - 60000, **kw)
    json.dump(e, open(os.path.join(reg, "%d.json" % pid), "w"))
entry(0, "s-busy", "busy", cwd=repo)
entry(1, "s-shell", "shell")
entry(2, "s-perm", "waiting", waitingFor="permission prompt")
entry(3, "s-input", "waiting", waitingFor="input needed")
entry(4, "s-dialog", "waiting", waitingFor="dialog open")
entry(5, "s-newwait", "waiting", waitingFor="something new")
entry(17, "s-legacy", "waiting", waitingFor="permission to run Bash")   # B1's word test, kept
entry(6, "s-idle", "idle")
entry(7, "s-limit", "idle")
entry(8, "s-neterr", "idle")
entry(9, "s-novel", "thinking")
entry(10, "s-twice", "idle")
entry(11, "s-twice", "busy")         # a second process on one session: the busier speaks
entry(12, "s-run", "busy", cwd=repo)   # joined to its run record below
# a dead process's record and a reused pid's: neither is live
json.dump(dict(pid=dead, sessionId="s-dead", cwd="/tmp", status="idle", procStart="Mon Jan  1 00:00:00 2001"),
          open(os.path.join(reg, "%d.json" % dead), "w"))
json.dump(dict(pid=pids[13], sessionId="s-reused", cwd="/tmp", status="idle", procStart="Mon Jan  1 00:00:00 2001"),
          open(os.path.join(reg, "x%d.json" % pids[13]), "w"))

proj = os.path.join(home, ".claude", "projects")
def transcript(slug, sid, rows):
    d = os.path.join(proj, slug); os.makedirs(d, exist_ok=True)
    open(os.path.join(d, sid + ".jsonl"), "w").write("".join(json.dumps(r) + "\n" for r in rows))
a = lambda model, **kw: dict(type="assistant", message={"model": model, "content": [], "usage": {"input_tokens": 5, "cache_read_input_tokens": 1000}}, effort="high", **kw)   # every real call carries usage (0 of 27,062 without, 2026-10-24)
transcript(re.sub(r"[^A-Za-z0-9]", "-", repo), "s-busy", [a("claude-opus-5-5", gitBranch="x"), a("claude-sonnet-5-5", isSidechain=True)])
transcript("-elsewhere", "s-idle", [a("claude-sonnet-5-5")])   # not under its cwd's slug: found by search
err = lambda kind, **kw: dict(type="assistant", isApiErrorMessage=True, error=kind, message={"model": "<synthetic>", "content": []}, **kw)
transcript("-t", "s-limit", [a("claude-opus-5-5"), err("rate_limit", apiErrorStatus=429)])
transcript("-t", "s-neterr", [a("claude-opus-5-5"), err("server_error")])

runs = os.path.join(home, "Library", "Logs", "claude-weekly", "run-seed-runs")
def run(name, **kw):
    st = dict(mode="rc", branch="claude/laptop/2026-10-14-" + kw.get("topic", "t"), repo=repo, started=str(int(time.time()) - 600))
    st.update({k: str(v) if k in ("pid", "started", "ended") else v for k, v in kw.items()})
    json.dump(st, open(os.path.join(runs, name + ".json"), "w"))
run("live-joined", topic="joined", session="s-run", pid=pids[12], proc_start=lstart(pids[12]), screen="run-repo-joined", wt=repo, model="opus", effort="high", account="acct-c")
run("live-unregistered", topic="fresh", session="s-fresh", pid=pids[14], proc_start=lstart(pids[14]), screen="run-repo-fresh")
run("live-headless", topic="quiet", session="s-headless", mode="headless", pid=pids[15], proc_start=lstart(pids[15]))
run("twin-a", topic="twin", session="s-twin-a", pid=pids[16], proc_start=lstart(pids[16]), repo=repo, wt=repo)
run("twin-b", topic="twin", session="s-twin-b", pid=pids[13], proc_start=lstart(pids[13]), repo="/tmp/other-repo", wt="/tmp/other-repo")
for name, reason, extra in [("idle", "idle 60 min", {}), ("cancel", "ended by dispatch --end (was busy)", {}),
                            ("never", "never started", {}), ("max", "max lifetime 8.0 h", {}),
                            ("exit0", "exit 0", {"mode": "headless"}), ("exit1", "exit 1", {"mode": "headless"}),
                            ("exit143", "exit 143", {"mode": "headless"}), ("guarded", "idle 60 min", {"ask_guard": "failed: ended on WAITING"}),
                            ("tidied", "tidied: its claude was gone", {}), ("odd", "a reason nobody wrote yet", {}),
                            ("apierr", "idle 11 min, its last turn ended on an API error", {})]:
    run("ended-" + name, topic="e-" + name, session="s-e-" + name, pid=dead, ended=int(time.time()) - 60, end_reason=reason, screen="run-x", **extra)
run("gone", topic="e-gone", session="s-e-gone", pid=dead, proc_start="Mon Jan  1 00:00:00 2001")
run("older", topic="e-twice", session="s-e-old", pid=dead, ended=int(time.time()) - 7200, end_reason="never started")
run("newer", topic="e-twice", session="s-e-new", pid=dead, ended=int(time.time()) - 60, end_reason="idle 60 min")
PY

H() { python3 "$B/harness" "$@"; }
J="$T/list.json"
H list --json > "$J"; rc=$?
st() { python3 -c 'import json,sys; r=[x for x in json.load(open(sys.argv[1])) if x["session_id"]==sys.argv[2]]; print(len(r) and (r[0]["state"]+(" "+r[0]["attention"]["kind"] if r[0]["attention"] else "")) or "absent")' "$J" "$1"; }
field() { python3 -c 'import json,sys; r=[x for x in json.load(open(sys.argv[1])) if x["session_id"]==sys.argv[2]][0]; print(r.get(sys.argv[3]) if "." not in sys.argv[3] else r["native"].get(sys.argv[3][1:]))' "$J" "$1" "$2"; }

echo "list: the state mapping"
check "$rc" 0 "list exits 0"
check "$(st s-busy)" "working" "busy -> working"
check "$(st s-shell)" "working" "shell -> working"
check "$(st s-perm)" "input-required permission" "waiting on a permission prompt -> input-required, kind permission"
check "$(st s-input)" "input-required question" "waiting, input needed -> question"
check "$(st s-dialog)" "input-required elicitation" "waiting, dialog open -> elicitation"
check "$(st s-newwait)" "input-required question" "a waitingFor not in the table -> question"
check "$(st s-legacy)" "input-required permission" "... unless its words say permission (B1's test, kept)"
check "$(st s-idle)" "idle idle" "idle -> idle, attention kind idle"
check "$(st s-limit)/$(field s-limit .error_kind)" "idle idle/rate_limit" "idle after a rate_limit API error: idle, the kind reported (S7 waits for stalls.py)"
check "$(st s-neterr)/$(field s-neterr .error_kind)" "idle idle/server_error" "idle after a server_error: idle, the kind reported"
check "$(st s-novel)" "working" "a status the table does not know -> working"
check "$(st s-twice)" "working" "two processes on one session: one record, the busier"
check "$(st s-fresh)" "submitted" "a live run with no registry entry -> submitted"
check "$(st s-headless)" "working" "a live headless run -> working"
check "$(st s-dead)" "absent" "a dead process's registry file is not listed"
check "$(st s-reused)" "absent" "a reused pid (start time differs) is not listed"
check "$(st s-e-idle)" "absent" "an ended run is not listed"

echo "list: the record"
check "$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(len(d), len([1 for x in d if x["session_id"]=="s-twice"]))' "$J")" "17 1" "17 live sessions (13 registered, 4 runs without an entry), each once"
check "$(python3 -c '
import json,sys
want = {"harness","account","session_id","machine","cwd","branch","pid","started_at","updated_at","state","attention","model","effort","title","attach","native"}
bad = [x["session_id"] for x in json.load(open(sys.argv[1])) if set(x) != want or x["harness"] != "claude-code" or x["machine"] != "laptop"]
print(bad or "ok")' "$J")" "ok" "every record has the contract's keys, harness and machine"
check "$(field s-busy model)/$(field s-busy effort)" "claude-opus-5-5/high" "model and effort from the main chain, not a subagent"
check "$(field s-idle model)" "claude-sonnet-5-5" "a transcript under another slug is found"
check "$(field s-busy branch)" "claude/laptop/2026-10-14-fixture" "branch read from the cwd's checkout"
check "$(field s-run branch)|$(field s-run attach)|$(field s-run account)|$(field s-run .topic)" \
      "claude/laptop/2026-10-14-joined|screen run-repo-joined|acct-c|joined" "a live run joins its record: branch, attach, account, topic"
check "$(field s-run state)/$(field s-run pid)" "working/${PIDS[12]}" "a joined run's state is the registry's, its pid the registry's"
check "$(field s-perm attention | grep -c "'message': 'permission prompt'")" 1 "attention carries waitingFor as its message"
check "$(field s-limit account)" "None" "account null with no run record naming one"

echo "status (V3)"
s() { H status "$@" --json 2>"$T/err" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["state"], d["session_id"], d["native"].get("end_reason",""))' 2>/dev/null; }
check "$(s s-busy)" "working s-busy " "by whole session id"
check "$(s name-s-perm)" "input-required s-perm " "by title"
check "$(s joined)" "working s-run " "by a live run's topic"
for t in "idle completed" "cancel canceled" "never failed" "max failed" "exit0 completed" "exit1 failed" \
         "exit143 canceled" "guarded failed" "tidied failed" "odd failed" "apierr failed"; do
  set -- $t
  check "$(s "e-$1" | cut -d' ' -f1)" "$2" "an ended run, $1 -> $2"
done
check "$(s e-gone)" "failed s-e-gone gone: its claude ended with no end recorded" "a run gone without an end -> failed, said so"
check "$(s e-twice | cut -d' ' -f2)" "s-e-new" "two ended runs of a topic: the newest"
H status twin --json > /dev/null 2>"$T/err"; check "$?" 2 "two live runs of one topic: ambiguous, exit 2"
has "$T/err" "s-twin-a" "the ambiguous ones are listed"
check "$(s twin --repo "$REPO" | cut -d' ' -f2)" "s-twin-a" "--repo narrows it"
H status s-nothing > /dev/null 2>&1; check "$?" 1 "nothing matches: exit 1"
check "$(s s-e-tid | cut -d' ' -f2)" "s-e-tidied" "a unique prefix of 6+"
H status s-bu > "$T/out" 2>&1; check "$?" 1 "a prefix under 6 is no match"
H status s-perm > "$T/out"; has "$T/out" "attention   {\"kind\": \"permission\"" "the text form prints the attention"

echo "B1's calls, as bin/stalls.py makes them"
b1() { python3 - "$B/harness_adapters/claude_code.py" "$@" <<'PY'
import json, sys
src = open(sys.argv[1]).read()
if sys.argv[2] == "stdin":   # as stalls.py ships it to the build Mac: source text, no __file__, no repo
    g = {"__name__": "probe"}; exec(compile(src, "<stdin>", "exec"), g)
    print(len(g["list"]()), g["status"]("s-busy")["state"])
    sys.exit(0)
import importlib.machinery, importlib.util
loader = importlib.machinery.SourceFileLoader("ad", sys.argv[1])
ad = importlib.util.module_from_spec(importlib.util.spec_from_loader("ad", loader)); loader.exec_module(ad)
s = ad.status(sys.argv[2], read_reply=sys.argv[3] == "1")
print(s["state"], s["process"], s["transcript"], bool(s["last_message"] is not None), s["api_error"], type(s["updated_at"]).__name__)
PY
}
check "$(b1 s-busy 1)" "working True True True False float" "status(): live, its transcript read, times as numbers"
check "$(b1 s-limit 0)" "idle True False False False float" "status(read_reply=False): the transcript never opened"

echo "last_reply: Claude Code's unflagged No response requested. read past (task-shape S3)"
lr() { python3 - "$B/harness_adapters/claude_code.py" "$1" <<'PY'
import importlib.machinery, importlib.util, sys
loader = importlib.machinery.SourceFileLoader("ad", sys.argv[1])
ad = importlib.util.module_from_spec(importlib.util.spec_from_loader("ad", loader)); loader.exec_module(ad)
say = lambda t, model="claude-opus-5-5", **kw: dict(type="assistant", message={"model": model, "content": [{"type": "text", "text": t}]}, **kw)
nrr = say("No response requested.", model="<synthetic>")
err = say("API Error: Connection dropped", model="<synthetic>", isApiErrorMessage=True)
rows = {"plain": [say("hand over"), nrr], "error": [say("hand over"), err, nrr],
        "nulltext": [say("hand over"), dict(type="assistant", message={"model": "x", "content": [{"type": "text", "text": None}]})]}[sys.argv[2]]
r = ad.last_reply("s-x", records=rows)
print("%s|%s" % (r["text"], r["api_error"]))
PY
}
check "$(lr plain)" "hand over|False" "a reply then that entry: the reply, no API error"
check "$(lr error)" "API Error: Connection dropped|True" "an API error then that entry: the error's words, still flagged (the S3 landing review)"
check "$(lr nulltext)" "hand over|False" "a text block whose text is null: read as empty, the reply before kept"
check "$(b1 s-e-idle 1)" "completed False False False False float" "status() of an ended run: its end, no process"
check "$(b1 s-unknown 1)" "completed False False False False NoneType" "status() of an unknown id: completed, nothing read (B1's)"
check "$(cd / && HARNESS_LAUNCHER=/nonexistent b1 stdin)" "14 working" "as source over stdin with no dispatch-rc: the registry alone answers (alive only, so the reused pid too)"

echo "the peer, over a fake ssh"
mkdir -p "$T/peer/.claude/sessions"
python3 - "$T/peer" "${PIDS[0]}" <<'PY'
import json, os, subprocess, sys
home, pid = sys.argv[1], int(sys.argv[2])
ps = " ".join(subprocess.run(["ps", "-o", "lstart=", "-p", str(pid)], capture_output=True, text=True, env=dict(os.environ, TZ="UTC", LC_ALL="C")).stdout.split())
json.dump(dict(pid=pid, sessionId="p-idle", cwd="/Users/sam/projects/shop", status="idle", procStart=ps, name="shop-bf",
               startedAt=1, statusUpdatedAt=2), open(os.path.join(home, ".claude", "sessions", "%d.json" % pid), "w"))
PY
cat > "$T/ssh" <<EOF
#!/bin/sh
# the last argument is the remote command; run it here as the peer would, reading stdin
for a; do last=\$a; done
[ "\$5" = buildbox-ssh ] || { echo "wrong alias \$5" >&2; exit 255; }
cd / && HOME="$T/peer" HARNESS_HOST=buildbox HARNESS_LAUNCHER="$B/.." exec sh -c "\$last"
EOF
chmod +x "$T/ssh"
HARNESS_SSH="$T/ssh" H list --host buildbox --json > "$T/peer.json"; check "$?" 0 "list --host buildbox exits 0"
check "$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(len(d), d[0]["machine"], d[0]["session_id"], d[0]["state"])' "$T/peer.json")" \
      "1 buildbox p-idle idle" "the peer's record, read by the code sent on stdin"
HARNESS_SSH="$T/ssh" H list --host all --json > "$T/all.json"; check "$?" 0 "list --host all exits 0"
check "$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(len(d), sorted({x["machine"] for x in d}))' "$T/all.json")" \
      "18 ['buildbox', 'laptop']" "--host all: both machines"
check "$(HARNESS_SSH="$T/ssh" s p-idle --host all | cut -d' ' -f1,2)" "idle p-idle" "status across hosts finds the peer's session"
printf '#!/bin/sh\necho "ssh: connect to host buildbox port 22: Operation timed out" >&2; exit 255\n' > "$T/ssh-down"; chmod +x "$T/ssh-down"
HARNESS_SSH="$T/ssh-down" H list --host all --json > "$T/down.json" 2>"$T/err"; check "$?" 3 "a peer that does not answer: exit 3"
check "$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))))' "$T/down.json")" 17 "... with this Mac's records still printed"
has "$T/err" "buildbox did not answer" "... and the peer named"
HARNESS_HOST=buildbox H list --host all --json > /dev/null 2>&1; check "$?" 0 "from the build Mac, all is the build Mac alone (no ssh back)"

# jget FILE EXPR: a Python expression over the JSON in FILE (d), printed
jget() { python3 -c 'import json, sys; d = json.load(open(sys.argv[1])); print(eval(sys.argv[2]))' "$1" "$2" 2>&1; }
# a repo with one commit, its contract, and a claude/* worktree beside it at DIR-wt
mkrepo() {
  mkdir -p "$(dirname "$1")"; git init -q -b main "$1"; printf -- '%s\n' "$2" > "$1/AGENTS.md"
  git -C "$1" add AGENTS.md; git -C "$1" -c user.email=t@t -c user.name=t commit -qm init
  git -C "$1" worktree add -q -b claude/laptop/2026-10-14-w "$1-wt"
}
TODAY=$(date +%Y-%m-%d)

echo "run: the rules every harness shares (exit 2, nothing started)"
mkrepo "$T/live" "- physical: a sweep"
H run --prompt x --cwd "$T/live-wt" > /dev/null 2>"$T/err"; check "$?" 2 "a repo whose contract is not physical: none: refused"
has "$T/err" "must say \`physical: none\`" "  saying why (dispatch's rule, which --start leaves to its caller)"
mkrepo "$T/projects/site" "- physical: none"
mkrepo "$T/projects/oss/lib" "- physical: none"
mkrepo "$T/projects/overlay" "- physical: none"
# the overlay is named by a config dir's marker (B14b): the suite's, plus the marker and the core's keys
rm -rf "$T/config-ovl"; cp -R "$T/config" "$T/config-ovl"; echo "$T/projects/overlay" > "$T/config-ovl/regatta/overlay"
for k in guarded orca-deny log-dir; do [ -e "$T/config-ovl/regatta/$k" ] || echo "$T/$k" > "$T/config-ovl/regatta/$k"; done
[ -e "$T/config-ovl/regatta/projects" ] || echo "$T/projects" > "$T/config-ovl/regatta/projects"
echo site > "$T/config/wharf-runs/public-repos"   # the repos Codex stays out of: a key, never a name in code
: > "$STUB_CODEX_CALLS"; : > "$STUB_ORCA_CALLS"
H run --harness codex --prompt x --cwd "$T/projects/site-wt" > /dev/null 2>"$T/err"; check "$?" 2 "Codex in site (a worktree of it): refused"
has "$T/err" "a public repo" "  naming the rule"
H run --harness codex --prompt x --cwd "$T/projects/oss/lib-wt" > /dev/null 2>&1; check "$?" 2 "Codex in a repo under oss/: refused"
REGATTA_CONFIG="$T/config-ovl" H run --harness orca --agent codex --name t --prompt x --repo "$T/projects/overlay" > /dev/null 2>&1; check "$?" 2 "an Orca codex worker in the overlay's checkout: refused"
REGATTA_CONFIG="$T/config-ovl" H run --harness codex --runner orca --name t --prompt x --repo "$T/projects/overlay" > /dev/null 2>&1; check "$?" 2 "codex through Orca (--runner orca) in the overlay's checkout: refused"
check "$(wc -c < "$STUB_CODEX_CALLS" | tr -d ' ')/$(grep -c worktree "$STUB_ORCA_CALLS")" "0/0" "  codex never ran, Orca made no worktree"
mv "$T/config/wharf-runs/public-repos" "$T/config/public-repos.keep"
H run --harness codex --prompt x --cwd "$T/projects/oss/lib-wt" > /dev/null 2>"$T/err"; check "$?" 2 "no public-repos key: oss/ still refused"
has "$T/err" "wharf-runs/public-repos is not set" "  with one stderr line saying the key is missing"
mv "$T/config/public-repos.keep" "$T/config/wharf-runs/public-repos"
H run --prompt x > /dev/null 2>&1; check "$?" 2 "no --cwd or --repo: refused"

echo "claude-code V1: dispatch --start, detached, under the harness's own session id"
H run --prompt "do the thing" --cwd "$T/projects/site-wt" --name v1-probe --model sonnet --effort medium --json > "$T/run.json" 2>"$T/err"
check "$?" 0 "run exits 0 (claude-code in site: only Codex stays out)"
SID=$(jget "$T/run.json" 'd["session_id"]')
has "$STUB_DISPATCH_CALLS" "--start do the thing $T/projects/site-wt v1-probe --session-id $SID --model sonnet --effort medium" \
    "dispatch --start PROMPT DIR NAME --session-id <ours> --model --effort"
check "$(jget "$T/run.json" '(d["harness"], d["state"], d["native"]["topic"], d["branch"])')" \
      "('claude-code', 'submitted', 'v1-probe', 'claude/laptop/2026-10-14-w')" "the record, read back: submitted (no registry entry yet), its run's topic and branch"
kill -0 "$(jget "$T/run.json" 'd["pid"]')" 2>/dev/null; check "$?" 0 "  the run outlives the call that started it"
check "$([ "$(tr -d ' \n' < "$STUB_PIDS.sid")" != "$(python3 -c 'import os; print(os.getsid(0))')" ] && echo own)" "own" \
      "  dispatch --start runs in a session of its own (setsid): detached from the caller's"
has "$T/run.json" "\"log\": \"$T/hlogs/" "  dispatch's output in a log of its own"
H run --prompt x --cwd "$T/projects/site" > /dev/null 2>"$T/err"; check "$?" 2 "a --cwd on main, not claude/*: refused"
STUB_DISPATCH_FAIL="3 other runs are busy" H run --prompt x --cwd "$T/projects/site-wt" --name f > /dev/null 2>"$T/err"
check "$?" 1 "dispatch says FAILED: exit 1"
has "$T/err" "3 other runs are busy" "  with dispatch's own line"
H run --branch claude/laptop/2026-10-14-seeded --repo "$REPO" --on buildbox --json > "$T/seed.json" 2>"$T/err"; check "$?" 0 "--branch: a seeded run"
has "$STUB_DISPATCH_CALLS" "claude/laptop/2026-10-14-seeded --repo $(cd "$REPO" && pwd -P) --pin buildbox" "  is dispatch BRANCH --repo --pin: the record names that machine, so a pin (dispatch-queue S12: --on is a preference)"
check "$(jget "$T/seed.json" '(d["state"], d["session_id"], d["title"], d["machine"])')" "('submitted', None, 'seeded', 'buildbox')" \
      "  submitted, no id until it fires (status finds it by topic), on the host named"
H run --branch claude/laptop/2026-10-14-seeded --repo "$REPO" --on here --json > "$T/seedh.json" 2>/dev/null
check "$(jget "$T/seedh.json" 'd["machine"]')" "laptop" "  --on here: this Mac's name on the record, never the word"
H run --prompt x --cwd "$T/projects/site-wt" --on buildbox > /dev/null 2>&1; check "$?" 2 "--on with --prompt: refused (a peer's runs start through a seeded branch)"

echo "claude-code V2: dispatch --start --resume [--fork]"
H resume s-e-idle --prompt "go on" --json > "$T/res.json" 2>"$T/err"; check "$?" 0 "continue an ended run"
has "$STUB_DISPATCH_CALLS" "--start go on $REPO e-idle --resume s-e-idle" "  dispatch --start in its directory, named by its topic, --resume ID"
check "$(jget "$T/res.json" '(d["session_id"], d["native"]["resumed_from"])')" "('s-e-idle', 's-e-idle')" "  the same session, resumed_from naming it"
H resume s-e-cancel --prompt again --fork --json > "$T/fork.json" 2>"$T/err"; check "$?" 0 "--fork an ended run"
NEW=$(jget "$T/fork.json" 'd["session_id"]')
has "$STUB_DISPATCH_CALLS" "--start again $REPO e-cancel-fork --resume s-e-cancel --fork --session-id $NEW" "  --resume ID --fork --session-id NEW, under a name of its own"
check "$(jget "$T/fork.json" 'd["native"]["resumed_from"]')/$([ "$NEW" != s-e-cancel ] && echo new)" "s-e-cancel/new" "  a new id, resumed_from the old"
H status s-e-idle --json > "$T/st.json"; check "$(jget "$T/st.json" 'd["native"].get("resumed_from")')" "s-e-idle" "status of a continued id: the live run, not the old one"
H resume s-busy --prompt x > /dev/null 2>"$T/err"; check "$?" 2 "a live session is not continued beside itself"
has "$T/err" "stop it first" "  saying what to do"
H resume s-busy --prompt x --fork > /dev/null 2>&1; check "$?" 2 "nor forked mid-turn"
H resume s-nothing --prompt x > /dev/null 2>&1; check "$?" 1 "continuing nothing: exit 1"
RB=$(git -C "$REPO" symbolic-ref --short HEAD); git -C "$REPO" checkout -q -b not-claude
H resume s-e-cancel --prompt x > /dev/null 2>"$T/err"; check "$?" 2 "continue in a directory not on a claude/* branch: refused, as run is"
has "$T/err" "not a claude/* branch" "  saying why"
git -C "$REPO" checkout -q "$RB"

echo "claude-code V5: dispatch --end, then the record's end"
echo x > "$T/projects/site-wt/abc.txt"
H stop "$SID" --json > "$T/stop.json" 2>"$T/err"; check "$?" 0 "stop exits 0"
check "$(jget "$T/stop.json" '"abc.txt" in d["files_changed"]')" "True" "  files_changed names a changed file whole (git status's first column kept)"
has "$STUB_DISPATCH_CALLS" "--end v1-probe --repo $T/projects/site" "  dispatch --end TOPIC --repo REPO"
check "$(jget "$T/stop.json" '(d["state"], d["stop_reason"], d["session_id"] == "'"$SID"'")')" "('canceled', 'ended by dispatch --end (was busy)', True)" \
      "  the exit report: canceled, dispatch's reason"
check "$(jget "$T/stop.json" 'sorted(set(["session_id", "state", "stop_reason", "last_message", "turns", "cost", "started_at", "ended_at", "files_changed"]) - set(d))')" \
      "[]" "  with every key of the contract's exit report"
H stop s-busy > /dev/null 2>"$T/err"; check "$?" 2 "a session with no run record (the owner's own) is not stopped"
has "$T/err" "no dispatch run" "  saying so"
H stop s-busy --host buildbox > /dev/null 2>&1; check "$?" 1 "stop on a peer: refused (this Mac only)"

echo "orca V1: Orca makes the worktree; the branch is named Atlas's way before any worker starts"
mkrepo "$T/scratch" "- physical: none"
: > "$STUB_ORCA_CALLS"
STUB_ORCA_PREFIX="claude/laptop/claude-laptop-" H run --harness orca --agent claude --repo "$T/scratch" --name probe \
  --prompt "reply DONE and stop" --model opus --effort high --json > "$T/o.json" 2>"$T/err"
check "$?" 0 "run --harness orca exits 0"
DID=$(jget "$T/o.json" 'd["session_id"]'); OWT=$(jget "$T/o.json" 'd["cwd"]')
check "$(jget "$T/o.json" '(d["harness"], d["branch"], d["native"].get("renamed_from"))')" \
      "('orca', 'claude/laptop/$TODAY-probe', 'claude/laptop/claude-laptop-$TODAY-probe')" "Orca's own branch name renamed to claude/<host>/<date>-<topic>"
check "$(git -C "$OWT" symbolic-ref --short HEAD)" "claude/laptop/$TODAY-probe" "  as git has it in the worktree"
has "$STUB_ORCA_CALLS" "worktree create --name $TODAY-probe --repo repo-1 --no-parent" "  the worktree named <date>-<topic>, bare (Orca adds its prefix)"
check "$(awk '/worktree create/ {w=NR} /worker-start/ {s=NR} END {print (w && s > w) ? "after" : "before"}' "$STUB_ORCA_CALLS")" "after" "  the worker starts after the worktree exists"
has "$STUB_ORCA_CALLS" "orchestration run-create --objective claude/laptop/$TODAY-probe (bin/harness run) --from term_shell" "  a Run, coordinated from the worktree's shell"
has "$STUB_ORCA_CALLS" "--agent claude --run run_1 --from term_shell --task-title claude/laptop/$TODAY-probe --model opus --effort high" "  worker-start with the agent, model and effort asked"
check "$(grep -c 'ELECTRON_RUN_AS_NODE=1' "$STUB_ORCA_CALLS")/$(grep -c 'ELECTRON_RUN_AS_NODE=unset' "$STUB_ORCA_CALLS")" \
      "0/$(wc -l < "$STUB_ORCA_CALLS" | tr -d ' ')" "  ELECTRON_RUN_AS_NODE cleared for every orca call (the caller had it set)"
check "$(jget "$T/o.json" 'd["state"]')" "working" "  unverifiable liveness, nothing waiting: working (absence is no verdict)"
H run --harness orca --repo "$T/scratch" --name probe --prompt x > /dev/null 2>"$T/err"; check "$?" 2 "the same branch again: refused"
H run --harness orca --repo "$T/scratch" --name p2 --prompt x --effort high > /dev/null 2>&1; check "$?" 2 "--effort without --model: refused (Orca's rule)"
H run --harness orca --repo "$T/scratch" --name p3 --prompt x --agent gemini > /dev/null 2>&1; check "$?" 2 "an agent Orca is not driven with here: refused"

echo "orca V3/V4: Orca's word for settlement, the agent's own word for a live worker"
H status "$DID" --json > "$T/os.json"; check "$(jget "$T/os.json" '(d["state"], d["title"], d["native"]["agent"], d["model"])')" \
  "('working', '$TODAY-probe', 'claude', 'opus')" "status by dispatch id: working, the agent and model from worker-show"
check "$(H status "$TODAY-probe" --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["session_id"])')" "$DID" "status by the branch's last part"
# its claude, as Claude Code's registry showed the probe's: parked on a permission prompt
sleeper; python3 - "$HD" "${PIDS[${#PIDS[@]}-1]}" "$OWT" <<'PY'
import json, os, subprocess, sys
home, pid, cwd = sys.argv[1], int(sys.argv[2]), sys.argv[3]
ps = " ".join(subprocess.run(["ps", "-o", "lstart=", "-p", str(pid)], capture_output=True, text=True, env=dict(os.environ, TZ="UTC", LC_ALL="C")).stdout.split())
json.dump(dict(pid=pid, sessionId="s-orca-inner", cwd=cwd, status="waiting", waitingFor="permission prompt", procStart=ps,
               kind="interactive", entrypoint="sdk-ts", startedAt=1, statusUpdatedAt=2), open(os.path.join(home, ".claude", "sessions", "%d.json" % pid), "w"))
PY
H status "$DID" --json > "$T/os.json"
check "$(jget "$T/os.json" '(d["state"], d["attention"]["kind"], d["native"]["agent_session"])')" "('input-required', 'permission', 's-orca-inner')" \
      "a worker whose claude waits on a permission prompt: input-required, joined to that session"
H list --harness orca --json > "$T/ol.json"; check "$(jget "$T/ol.json" '[(r["session_id"], r["state"]) for r in d]')" "[('$DID', 'input-required')]" "list --harness orca: the one live worker"
has "$STUB_ORCA_CALLS" "orchestration worker-list --include-remote --limit 100" "  worker-list --include-remote: a worker on a paired host is listed, not unverifiable (wharf-on-orca S3)"
: > "$STUB_ORCA_CALLS"
cp "$T/orca.state" "$T/orca-s3.state"   # a copy: the start below must not add a worker to the cases after it
check "$(STUB_ORCA_STATE="$T/orca-s3.state" python3 - "$B" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("orca_s3", sys.argv[1] + "/harness_adapters/orca.py")
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
did, res, own = m.start(None, {"agent": "claude", "prompt": "p", "ship": "s", "account": "auto"}, "path:/remote/wt",
                        "run_1", "term_shell", ("acct-a", {}), title="t", on="buildbox")
print(bool(did), own)
PY
)" "True None" "start(on=…): a Dispatch, and no terminal of ours (one would open on this Mac)"
has "$STUB_ORCA_CALLS" "orchestration worker-start --spec p --on buildbox --worktree path:/remote/wt --agent claude --run run_1" "  worker-start --on the host, Orca's own launch"
check "$(grep -c '^terminal create' "$STUB_ORCA_CALLS")" "0" "  no login terminal of ours"

echo "orca V2: a chat worker's next turn goes by orchestration send"
H resume "$DID" --prompt "and again" --json > "$T/or.json" 2>"$T/err"; check "$?" 0 "continue exits 0"
has "$STUB_ORCA_CALLS" "orchestration send --to dispatch:$DID --from term_shell --subject bin/harness resume --body and again --type dispatch" \
    "  orchestration send to the dispatch, from the Run's coordinator (terminal send refuses a chat worker)"
check "$(jget "$T/or.json" 'd["native"]["sent"]')" "orchestration send: message msg_1" "  the message id read back"
H resume "$DID" --prompt x --fork > /dev/null 2>&1; check "$?" 2 "--fork: refused (Orca has none)"

echo "orca V5: worker-stop, then the release Orca's nextAction names"
H stop "$DID" --json > "$T/ost.json" 2>"$T/err"; check "$?" 0 "stop exits 0"
check "$(jget "$T/ost.json" '(d["state"], d["stop_reason"], d["native"]["stopped_by"], d["native"]["terminal_state"], d["last_message"])')" \
      "('canceled', 'stopped', 'worker-stop, worker-release', 'released', 'DONE')" "canceled (a stop, not a failure), released, its last reply"
grep -q "worktree rm" "$STUB_ORCA_CALLS"; check "$?" 1 "  the worktree is never removed"
check "$(H list --harness orca --json | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))')" "0" "  and the list has no live worker left"
H status "$DID" --json > "$T/os.json"; check "$(jget "$T/os.json" 'd["state"]')" "canceled" "  status still reads it canceled once released"
check "$(H list --harness orca --unsettled --json | python3 -c 'import json,sys; print([(r["session_id"], r["state"]) for r in json.load(sys.stdin)])')" "[('$DID', 'canceled')]" \
      "  list --unsettled keeps it: a Dispatch that did not complete (bin/stalls.py's read, B8)"
H retry "$DID" > /dev/null 2>"$T/err"; check "$?" 2 "  retry of a stopped worker: refused (only a failed attempt is retried)"
grep -q "retry-of" "$STUB_ORCA_CALLS"; check "$?" 1 "  and Orca was never asked to start one"

echo "codex V1: codex exec --json under a detached wrapper"
CW="$T/scratch-wt"; : > "$STUB_CODEX_CALLS"
# the run's scratch dir (its TMPDIR, writable under the fence) lands here, not in /private/tmp
export HARNESS_CODEX_SCRATCH="$T/cxs"; mkdir -p "$HARNESS_CODEX_SCRATCH"
# an attended caller, pinned: with no session, no terminal app and no tty (CI, launchd) a start reads unattended
HC() { CLAUDE_CODE_SESSION_ID=sess-attended H "$@"; }
FENCE="-c default_permissions=\"regatta-fence\" -c permissions.regatta-fence.extends=\":workspace\" -c permissions.regatta-fence.filesystem={"
STUB_CODEX_THREAD=th-aaaa0001 HC run --harness codex --cwd "$CW" --name cx --prompt "reply DONE" --model gpt-6 --effort high --json > "$T/c.json" 2>"$T/err"
check "$?" 0 "run --harness codex exits 0"
check "$(jget "$T/c.json" '(d["harness"], d["session_id"], d["branch"])')" "('codex', 'th-aaaa0001', 'claude/laptop/2026-10-14-w')" "  the thread id read from codex's first event"
has "$STUB_CODEX_CALLS" "codex exec --json --approve-for-me -C $CW $FENCE" "  exec --json --approve-for-me -C, then the fence's permissions profile (vendor-fence, F2)"
has "$STUB_CODEX_CALLS" "\"$HOME\"=\"deny\"" "    the home folder denied (the worktree lies outside it here)"
has "$STUB_CODEX_CALLS" "\"$CW\"=\"write\"" "    the worktree writable"
has "$STUB_CODEX_CALLS" "\"$HARNESS_CODEX_SCRATCH/codex-run-" "    and the run's scratch dir"
has "$STUB_CODEX_CALLS" "} -m gpt-6 -c model_reasoning_effort=\"high\" -" "  model and effort after it, the prompt from stdin"
has "$STUB_CODEX_CALLS" "stdin: reply DONE" "  the prompt on stdin"
grep -q -- "--dangerously" "$STUB_CODEX_CALLS"; check "$?" 1 "  never --dangerously-bypass-approvals-and-sandbox"
has "$STUB_CODEX_CALLS" "--disable apps" "  attended too: the account apps off, as the run is detached and its approvals go to auto-review (landing review, F3)"
grep -q -- "--ephemeral" "$STUB_CODEX_CALLS"; check "$?" 1 "  no --ephemeral unless asked"
has "$STUB_CODEX_CALLS" "env: RU=unset CU=unset SID=unset PH=codex TMP=$HARNESS_CODEX_SCRATCH/codex-run-" \
  "  the child: no marker (attended), no CLAUDE_CODE_SESSION_ID (helmlib.harness() misread it), PLAN_HARNESS=codex, TMPDIR its scratch"
cx_state() {   # the thread's state once it reads $2, or what it read last (4 s)
  local s="" i
  for i in $(seq 1 20); do
    s=$(H status "$1" --harness codex --json 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["state"])' 2>/dev/null)
    [ "$s" = "$2" ] && break; sleep 0.2
  done; echo "$s"
}
check "$(cx_state th-aaaa0001 completed)" "completed" "the run ends by itself: completed (exit 0)"
H stop th-aaaa0001 --json > "$T/cst.json"; check "$(jget "$T/cst.json" '(d["state"], d["last_message"], d["turns"], d["stop_reason"])')" \
  "('completed', 'DONE', 1, 'exit 0')" "stop on an ended run: its exit report, the reply and the turns the wrapper counted"
check "$(jget "$T/cst.json" '(d["cost"]["input_tokens"], d["cost"]["output_tokens"], d["cost"]["usd"])')" "(1, 1, None)" \
  "  cost: the turns' usage summed, no price for a plan login (F11)"
check "$(H status th-aaaa0001 --harness codex --json | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["model"], d["effort"])')" "gpt-6 high" \
  "  the model and effort it ran with (the request's, where Codex's store has no thread)"
check "$(ls "$HARNESS_CODEX_SCRATCH" | grep -c codex-run-)" 0 "  the run's scratch dir removed at its end"
H run --harness codex --cwd "$T/scratch" --prompt x > /dev/null 2>&1; check "$?" 2 "--cwd on main: refused"

echo "codex unattended: the marker, the apps off, the run cap (vendor-fence, F3, F5, F6)"
: > "$STUB_CODEX_CALLS"
REGATTA_UNATTENDED=dispatch CLAUDE_CODE_SESSION_ID=sess-x STUB_SLOTS="1 4" STUB_CODEX_THREAD=th-uuuu0004 \
  H run --harness codex --cwd "$CW" --name cxu --prompt x --ephemeral --json > /dev/null 2>"$T/err"
check "$?" 0 "an unattended caller starts a Codex run while the cap has room (counted since vendor-fence)"
has "$STUB_DISPATCH_CALLS" "--slots" "  the cap asked: dispatch --slots"
has "$STUB_CODEX_CALLS" "--disable apps --disable plugins" "  the account apps and plugins off"
has "$STUB_CODEX_CALLS" "--disable computer_use --disable in_app_browser -c mcp_servers={} --ephemeral -" "  computer use, the browser and every MCP server off; --ephemeral asked for"
has "$STUB_CODEX_CALLS" "env: RU=dispatch CU=dispatch SID=unset PH=codex" "  the child carries the marker under both names, the caller's session id dropped"
: > "$STUB_CODEX_CALLS"
CLAUDE_UNATTENDED=dispatch STUB_CODEX_THREAD=th-uuuu0005 H run --harness codex --cwd "$CW" --name cxo1 --prompt x > /dev/null 2>"$T/err"
check "$?" 0 "only the old name set (CLAUDE_UNATTENDED): still an unattended caller"
has "$STUB_CODEX_CALLS" "env: RU=dispatch CU=dispatch" "  its child gets both names"
has "$STUB_CODEX_CALLS" "--disable apps" "  and the apps off"
: > "$STUB_CODEX_CALLS"
REGATTA_UNATTENDED=dispatch STUB_SLOTS="4 4" H run --harness codex --cwd "$CW" --name cxf --prompt x > /dev/null 2>"$T/err"
check "$?" 2 "the cap full: refused"
has "$T/err" "4 runs are busy of 4 (dispatch --slots): no codex run starts; the next step waits for a run to end" "  in the cap's waiting words"
REGATTA_UNATTENDED=dispatch STUB_SLOTS="?" H run --harness codex --cwd "$CW" --name cxq --prompt x > /dev/null 2>"$T/err"
check "$?" 2 "a cap that does not read: an unattended start refused"
REGATTA_UNATTENDED=dispatch DISPATCH_DEPTH=5 H run --harness codex --cwd "$CW" --name cxd --prompt x > /dev/null 2>"$T/err"
check "$?" 2 "a caller at DISPATCH_MAX_DEPTH (5): refused, as dispatch's chain stops (landing review)"
has "$T/err" "at depth 5 of DISPATCH_MAX_DEPTH 5: no codex run starts" "  naming the depth"
check "$(wc -c < "$STUB_CODEX_CALLS" | tr -d ' ')" 0 "  codex never ran for any of the three"
check "$(python3 - "$B/harness_adapters/codex.py" <<'PY'
import importlib.util as u, sys
s = u.spec_from_file_location("cx_ua", sys.argv[1]); m = u.module_from_spec(s); s.loader.exec_module(m)
m._tty = lambda: False
print(m.caller_unattended({}), m.caller_unattended({"CLAUDE_CODE_SESSION_ID": "s"}), m.caller_unattended({"TERM_PROGRAM": "vscode"}),
      m.caller_unattended({"CLAUDE_UNATTENDED": "old"}), m.caller_unattended({"REGATTA_UNATTENDED": "new", "CLAUDE_UNATTENDED": "old"}))
m._tty = lambda: True
print(m.caller_unattended({}))
PY
)" "launchd None None old new
None" "caller_unattended: launchd's start (no session, no terminal app, no tty) is unattended; the new name before the old"

echo "codex: bounded — a timeout, a rate limit (vendor-fence, F6)"
STUB_CODEX_THREAD=th-tttt0006 STUB_CODEX_HOLD=1 HC run --harness codex --cwd "$CW" --name tmo --prompt x --timeout 1 --json > /dev/null 2>"$T/err"
check "$?" 0 "--timeout 1: started"
check "$(cx_state th-tttt0006 failed)" "failed" "  past its timeout: failed"
H stop th-tttt0006 --json > "$T/tmo.json"; check "$(jget "$T/tmo.json" '(d["state"], d["stop_reason"], d["native"]["timed_out"])')" \
  "('failed', 'timed out after 1s', True)" "  the end says why"
STUB_CODEX_RATE=1 STUB_CODEX_THREAD=th-rrrr0007 HC run --harness codex --cwd "$CW" --name rate --prompt x --json > /dev/null 2>"$T/err"
check "$(cx_state th-rrrr0007 failed)" "failed" "a turn that fails on a usage limit: failed"
H stop th-rrrr0007 --json > "$T/rate.json"; check "$(jget "$T/rate.json" '(d["stop_reason"], d["native"]["rate_limited"])')" \
  "('rate limited: You have hit your usage limit. Try again in 3 hours.', True)" "  the reason recorded, rate_limited true"
check "$(python3 - "$B/../../helm/bin" <<'PY'
import sys, time
sys.path.insert(0, sys.argv[1])
import stalls
s, n = stalls.judge_codex("laptop", time.time())
print(sorted(x["class"] + " " + x["action"] for x in s), n)
PY
)" "['S1 raise', 'S1 raise'] []" "stalls.py judges the harness's Codex runs: the timed-out and the rate-limited one are S1 cards, raised"

echo "codex: a run still going, stopped"
STUB_CODEX_THREAD=th-bbbb0002 STUB_CODEX_HOLD=1 HC run --harness codex --cwd "$CW" --name hold --prompt x --json > "$T/h.json" 2>"$T/err"
HP=$(jget "$T/h.json" 'd["pid"]')
check "$(jget "$T/h.json" 'd["state"]')/$(kill -0 "$HP" 2>/dev/null && echo alive)" "working/alive" "a live run: working, its codex alive after the call returned"
check "$(H list --harness codex --json | python3 -c 'import json,sys; print([r["session_id"] for r in json.load(sys.stdin)])')" "['th-bbbb0002']" "  listed"
rc_live() { python3 "$B/dispatch-rc" live --no-reap "" "" 2>/dev/null; }
check "$(( $(rc_live) - $(DISPATCH_RC_VENDORS=0 rc_live) ))" 1 "  dispatch-rc's run count holds it: one slot of the cap (vendor-fence, F6)"
H resume th-bbbb0002 --prompt x > /dev/null 2>&1; check "$?" 2 "  not continued beside itself"
H stop th-bbbb0002 --json > "$T/hst.json" 2>"$T/err"; check "$?" 0 "stop exits 0"
check "$(jget "$T/hst.json" '(d["state"], d["stop_reason"])')/$(kill -0 "$HP" 2>/dev/null && echo alive || echo gone)" \
      "('canceled', 'stopped by harness stop')/gone" "  SIGTERM after the start-time check: canceled, the process gone"

echo "codex V2: exec resume and exec fork"
: > "$STUB_CODEX_CALLS"
STUB_CODEX_THREAD=th-aaaa0001 HC resume th-aaaa0001 --prompt next --json > "$T/cr.json" 2>"$T/err"; check "$?" 0 "continue an ended thread"
has "$STUB_CODEX_CALLS" "codex exec --json --approve-for-me -C $CW $FENCE" "  exec resume behind the same fence"
has "$STUB_CODEX_CALLS" "} resume th-aaaa0001 -" "  exec resume THREAD, the prompt on stdin"
check "$(jget "$T/cr.json" '(d["session_id"], d["native"]["resumed_from"])')" "('th-aaaa0001', 'th-aaaa0001')" "  the same thread, resumed_from naming it"
cx_state th-aaaa0001 completed > /dev/null
STUB_CODEX_THREAD=th-cccc0003 HC resume th-aaaa0001 --prompt again --fork --json > "$T/cf.json" 2>"$T/err"; check "$?" 0 "--fork"
has "$STUB_CODEX_CALLS" "} fork th-aaaa0001 -" "  exec fork THREAD: headless in 0.162.1"
check "$(jget "$T/cf.json" '(d["session_id"], d["native"]["resumed_from"], d["native"]["fork"])')" "('th-cccc0003', 'th-aaaa0001', True)" "  a new thread, forked from the old"
git -C "$CW" checkout -q --detach
HC resume th-aaaa0001 --prompt x > /dev/null 2>"$T/err"; check "$?" 2 "a thread whose worktree left its claude/* branch: not resumed there (run's rule, F5)"
has "$T/err" "not a claude/* branch" "  saying why"
git -C "$CW" checkout -q claude/laptop/2026-10-14-w

echo "codex V3/V4: threads Codex ran itself, from its store, read-only"
CH="$T/codexhome"; mkdir -p "$CH/sessions"
python3 - "$CH" <<'PY'
import json, os, sqlite3, sys, time
ch = sys.argv[1]; now = int(time.time() * 1000)
con = sqlite3.connect(os.path.join(ch, "state_5.sqlite"))
con.execute("CREATE TABLE threads (id TEXT PRIMARY KEY, rollout_path TEXT, cwd TEXT, title TEXT, model TEXT, reasoning_effort TEXT, "
            "git_branch TEXT, created_at_ms INTEGER, updated_at_ms INTEGER, archived INTEGER DEFAULT 0)")
g = sqlite3.connect(os.path.join(ch, "goals_1.sqlite"))
g.execute("CREATE TABLE thread_goals (thread_id TEXT PRIMARY KEY, status TEXT)")
ev = lambda t, **kw: json.dumps({"timestamp": "2026-10-15T00:50:25.408Z", "type": "event_msg", "payload": dict(type=t, **kw)})
for tid, rows, age_s, goal in [("th-done", ["task_started", "task_complete"], 30, None), ("th-open", ["task_started"], 10, None),
                               ("th-stale", ["task_started"], 3600, None), ("th-limited", ["task_started"], 10, "usage_limited"),
                               ("th-abort", ["task_started", "turn_aborted"], 30, None)]:
    p = os.path.join(ch, "sessions", "rollout-%s.jsonl" % tid)
    open(p, "w").write(json.dumps({"type": "session_meta", "payload": {"id": tid}}) + "\n" +
                       "".join(ev(t, last_agent_message="said %s" % tid) + "\n" for t in rows))
    os.utime(p, (time.time() - age_s, time.time() - age_s))
    con.execute("INSERT INTO threads VALUES (?,?,?,?,?,?,?,?,?,0)", (tid, p, "/tmp/w", "title " + tid, "gpt-6-astra", "medium", None, now - 7200000, now - age_s * 1000))
    if goal:
        g.execute("INSERT INTO thread_goals VALUES (?,?)", (tid, goal))
con.commit(); g.commit()
PY
for t in "th-done completed" "th-open working" "th-stale failed" "th-limited auth-required" "th-abort canceled"; do
  set -- $t
  check "$(CODEX_HOME="$CH" H status "$1" --harness codex --json 2>&1 | python3 -c 'import json,sys; print(json.load(sys.stdin)["state"])' 2>&1)" "$2" "a store thread, $1 -> $2"
done
check "$(CODEX_HOME="$CH" H list --harness codex --json | python3 -c 'import json,sys; print(sorted(r["session_id"] for r in json.load(sys.stdin)))')" \
      "['th-limited', 'th-open']" "list: the store's open, fresh turns (a run of ours would join them)"
check "$(CODEX_HOME="$CH" H status "title th-done" --harness codex --json | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["session_id"], "last_message" in json.dumps(d))')" \
      "th-done False" "status by title; a status never carries what the session said"
CODEX_HOME="$CH" H stop th-open > /dev/null 2>"$T/err"; check "$?" 2 "a thread Codex ran itself is not stopped from here"

echo "codex --runner orca: an Orca codex worker, in a terminal of ours behind the fence (vendor-fence, F4)"
# Orca's settings document as its store holds it: codex's default args clean, another agent's holding a bypass
printf '{"agentDefaultArgs": {"codex": "--approve-for-me", "antigravity": "--dangerously-skip-permissions"}}\n' > "$T/orca-settings.json"
export HARNESS_ORCA_SETTINGS="$T/orca-settings.json"
: > "$STUB_ORCA_CALLS"
HC run --harness codex --runner orca --repo "$T/scratch" --name cxo --prompt x --json > "$T/cxo.json" 2>"$T/err"; check "$?" 0 "run --harness codex --runner orca (another agent's bypass flag refuses no codex worker)"
has "$STUB_ORCA_CALLS" "terminal create --worktree id:repo-1::$STUB_ORCA_WS/$TODAY-cxo --title $TODAY-cxo --command env -u CLAUDE_CODE_SESSION_ID -u CLAUDECODE PLAN_HARNESS=codex TMPDIR=$HARNESS_CODEX_SCRATCH/codex-worker-" \
    "  a terminal of ours in the worktree: no Claude session in its env, its own TMPDIR"
has "$STUB_ORCA_CALLS" "$HARNESS_CODEX --approve-for-me -C $STUB_ORCA_WS/$TODAY-cxo -c 'default_permissions=\"regatta-fence\"'" \
    "  running codex behind the fence's permissions profile, never Orca's own launch"
check "$(grep 'worker-start' "$STUB_ORCA_CALLS" | grep -c -- '--agent')/$(grep -c 'worker-start.*--terminal term_own_' "$STUB_ORCA_CALLS")" "0/2" \
    "  worker-start --terminal (refused once while Orca learns the agent), never --agent codex"
check "$(jget "$T/cxo.json" '(d["harness"], d["branch"])')" "('orca', 'claude/laptop/$TODAY-cxo')" "  the record is the orca adapter's"
check "$(python3 -c 'import json,sys; print([x["agent"] for x in json.load(open(sys.argv[1]))])' "$HARNESS_RUNS_DIR/orca-workers.json")" "['codex']" \
    "  in the adapter's ledger of non-Claude workers"
check "$(( $(rc_live) - $(DISPATCH_RC_VENDORS=0 rc_live) ))" 1 "  dispatch-rc's run count holds the live worker (F6)"
H stop "$(jget "$T/cxo.json" 'd["session_id"]')" --harness orca > /dev/null 2>&1
check "$(( $(rc_live) - $(DISPATCH_RC_VENDORS=0 rc_live) ))" 0 "  stopped: no longer counted"
printf '{"agentDefaultArgs": {"codex": "--approve-for-me --dangerously-bypass-approvals-and-sandbox"}}\n' > "$T/orca-bad.json"
: > "$STUB_ORCA_CALLS"
HARNESS_ORCA_SETTINGS="$T/orca-bad.json" HC run --harness codex --runner orca --repo "$T/scratch" --name cxb --prompt x > /dev/null 2>"$T/err"
check "$?" 2 "Orca's default args for codex hold a bypass flag: refused"
has "$T/err" "--dangerously-bypass-approvals-and-sandbox (settings.agentDefaultArgs.codex in $T/orca-bad.json)" "  naming the flag and what was read"
HARNESS_ORCA_SETTINGS="$T/orca-bad.json" HC run --harness orca --agent codex --repo "$T/scratch" --name cxb2 --prompt x > /dev/null 2>"$T/err"
check "$?" 2 "  the same through --harness orca --agent codex"
printf '{"agentDefaultArgs": {}, "experimentalNativeChat": true, "nativeChatPermissionMode": "full-access"}\n' > "$T/orca-chat.json"
HARNESS_ORCA_SETTINGS="$T/orca-chat.json" HC run --harness orca --agent codex --repo "$T/scratch" --name cxb3 --prompt x > /dev/null 2>"$T/err"
check "$?" 2 "Orca's chat workers on full-access (its Yolo's other half): refused"
HARNESS_ORCA_SETTINGS="$T/no-such.json" HC run --harness orca --agent codex --repo "$T/scratch" --name cxb4 --prompt x > /dev/null 2>"$T/err"
check "$?" 2 "Orca's settings unread: refused, never assumed clean"
check "$(grep -c 'worktree create' "$STUB_ORCA_CALLS")" 0 "  nothing made in Orca for any of them"
# Orca's own store, read-only: the active profile's profile-state.db, domain settings
OD="$T/orcadata"; mkdir -p "$OD/profiles/p1"; echo '{"activeProfileId": "p1"}' > "$OD/orca-profile-index.json"
python3 - "$OD/profiles/p1/profile-state.db" <<'PY'
import json, sqlite3, sys
c = sqlite3.connect(sys.argv[1]); c.execute("CREATE TABLE profile_state_documents (domain TEXT PRIMARY KEY, payload TEXT)")
c.execute("INSERT INTO profile_state_documents VALUES ('settings', ?)", (json.dumps({"agentDefaultArgs": {"codex": "--yolo"}}),)); c.commit()
PY
check "$(env -u HARNESS_ORCA_SETTINGS HARNESS_ORCA_DATA="$OD" python3 - "$B/harness_adapters/orca.py" <<'PY'
import importlib.util as u, sys
s = u.spec_from_file_location("orca_bp", sys.argv[1]); m = u.module_from_spec(s); s.loader.exec_module(m)
print(m.bypass_refusal("codex").split(" (")[0], m.bypass_refusal("claude"))
PY
)" "Orca's default args for codex hold --yolo None" "  read from Orca's own store (the active profile's settings document); a Claude worker is not this check's"
unset HARNESS_ORCA_SETTINGS

echo "the real list against claude agents --json"
if command -v claude > /dev/null 2>&1 && [ "$(uname)" = Darwin ] && [ -d "$REAL_HOME/.claude/sessions" ]; then
  # sessions start and end between the two reads: compare, then once more on a difference
  same_ids() {
    HOME="$REAL_HOME" python3 "$B/harness" list --json 2>/dev/null > "$T/real.json"
    HOME="$REAL_HOME" claude agents --json 2>/dev/null > "$T/agents.json"
    python3 -c '
import json, sys
a = {x["session_id"] for x in json.load(open(sys.argv[1])) if x["native"].get("status")}   # registry-backed only
b = {x["sessionId"] for x in json.load(open(sys.argv[2]))}
print("same: %d" % len(a) if a == b else "differ: harness only %s, agents only %s" % (sorted(a - b), sorted(b - a)))' "$T/real.json" "$T/agents.json"
  }
  r=$(unset HARNESS_HOST; same_ids); case "$r" in same*) ;; *) sleep 2; r=$(unset HARNESS_HOST; same_ids);; esac
  case "$r" in same*) check same same "real list: the $r sessions claude agents --json lists";; *) check "$r" same "real list matches claude agents --json";; esac
else
  echo "  skip no claude here (CI): the real comparison runs on a Mac"
fi

echo "pick and the continue guard (review 2026-10-15)"
check "$(python3 - "$B/harness" "$T/projects/site" <<'PY'
import importlib.machinery, importlib.util, sys
loader = importlib.machinery.SourceFileLoader("harness", sys.argv[1])
h = importlib.util.module_from_spec(importlib.util.spec_from_loader("harness", loader)); loader.exec_module(h)
two = [{"machine": "m", "session_id": None, "state": "submitted"}, {"machine": "m", "session_id": None, "state": "submitted"}]
rec, many = h.pick(two, "topic")
try:
    h.guard({"agent": "codex", "cwd": sys.argv[2]}, "orca"); g = "allowed"
except h.Failed as e:
    g = "refused %d" % e.code
print(rec, len(many or []), g)
PY
)" "None 2 refused 2" "two live records with no id yet are two (never guessed between); an Orca codex worker meets the public-repo rule"
# guarded(MARKER): each road's guard() for an unattended caller marked MARKER=dispatch, the cap with room
guarded() { env "$1=dispatch" STUB_SLOTS="0 4" python3 - "$B/harness" "$CW" <<'PY'
import importlib.machinery, importlib.util, sys
loader = importlib.machinery.SourceFileLoader("harness", sys.argv[1])
h = importlib.util.module_from_spec(importlib.util.spec_from_loader("harness", loader)); loader.exec_module(h)
out = []
for harness, req in (("orca", {}), ("codex", {}), ("claude-code", {"runner": "orca"}), ("claude-code", {}), ("orca", {"agent": "codex"})):
    try:
        h.guard(dict(req, cwd=sys.argv[2]), harness); out.append("ok")
    except h.Failed as e:
        out.append(str(e.code))
print(" ".join(out))
PY
}
check "$(guarded REGATTA_UNATTENDED)" "2 ok 2 ok ok" \
  "unattended: an Orca Claude worker still refused (no cap counts it); a Codex run and an Orca codex worker pass, counted by the cap (vendor-fence, F6)"
check "$(guarded CLAUDE_UNATTENDED)" "2 ok 2 ok ok" "  the old marker name alone: judged the same"

echo "the spawn gate (confidential-reach S6's fourth landing review, item 6): a start around dispatch asks it"
# an open repo, and a confidential scope's checkout under the projects folder the core reads (common.PROJECTS)
S6P=$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import core_path; core_path.require(); import common; print(common.PROJECTS)' "$B/../lib")
git init -q "$S6P/s6node"; git init -q -b main "$T/s6open"; printf -- '- physical: none\n' > "$T/s6open/AGENTS.md"
git -C "$T/s6open" add -A; git -C "$T/s6open" -c user.email=t@t -c user.name=t commit -qm init
printf '{"repos": {"s6node": {}}, "scopes": {"node": {"repos": ["s6node"], "confidential": true}}}\n' > "$T/s6-reg.json"
cat > "$T/s6guard.py" <<'PY'
import importlib.machinery, importlib.util, os, sys
loader = importlib.machinery.SourceFileLoader("harness", sys.argv[1])
h = importlib.util.module_from_spec(importlib.util.spec_from_loader("harness", loader)); loader.exec_module(h)
out = []
# run --harness orca, run --harness codex, an Orca-run claude worker, retry (an Orca worker), resume of a Codex
# run, and a claude-code run, which bin/dispatch judges itself
for harness, req in (("orca", {}), ("codex", {}), ("claude-code", {"runner": "orca"}), ("orca", {"agent": "claude"}),
                     ("codex", {"prompt": "next turn"}), ("claude-code", {})):
    try:
        h.guard(dict(req, cwd=sys.argv[2]), harness); out.append("ok")
    except h.Failed as e:
        out.append(str(e.code)); print(e, file=sys.stderr)
print(" ".join(out))
PY
# attended callers: this suite may run inside a dispatched session, whose CLAUDE_UNATTENDED refuses every Orca start
S6ENV=(env -u CLAUDE_UNATTENDED -u CLAUDE_CODE_DISABLE_BACKGROUND_TASKS -u CLAUDE_CODE_SESSION_ID)
(cd "$S6P/s6node" && "${S6ENV[@]}" CLAUDE_REPOS_JSON="$T/s6-reg.json" python3 "$T/s6guard.py" "$B/harness" "$T/s6open") > "$T/out" 2> "$T/err"
check "$(cat "$T/out")" "2 2 2 2 2 ok" "item 6: from inside a confidential scope into an open repo, orca, codex, an Orca claude worker, a retry and a resume: refused; claude-code goes by dispatch's own gate"
has "$T/err" "refused for good, a run out of a confidential scope with no review that vouches for what it is handed" "  in the gate's words"
has "$T/err" "a --start from inside a confidential scope hands the run a prompt no review read" "  saying why: its prompt is unreviewed"
(cd "$T/s6open" && "${S6ENV[@]}" CLAUDE_REPOS_JSON="$T/s6-reg.json" python3 "$T/s6guard.py" "$B/harness" "$T/s6open") > "$T/out" 2> "$T/err"
check "$(cat "$T/out")" "ok ok ok ok ok ok" "  the same starts from an open caller: let through"
# the sessions folder of the suite's own login dir, as the core names it (the publish gate)
S6SD=$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import core_path; core_path.require(); import common; print(common.Path.home() / ".claude" / "sessions")' "$B/../lib")
mkdir -p "$S6SD"; printf '{"pid": 99996, "sessionId": "s6-harness", "cwd": "%s", "updatedAt": 9}\n' "$S6P/s6node" > "$S6SD/99996.json"
(cd "$T/s6open" && "${S6ENV[@]}" CLAUDE_CODE_SESSION_ID=s6-harness CLAUDE_REPOS_JSON="$T/s6-reg.json" python3 "$T/s6guard.py" "$B/harness" "$T/s6open") > "$T/out" 2> "$T/err"
check "$(cat "$T/out")" "2 2 2 2 2 ok" "  a node session's \`cd <open repo> && harness …\`: refused by its session's folder, as dispatch judges it"
rm -f "$S6SD/99996.json"
for v in run resume retry; do
  check "$(sed -n "/^def cmd_$v(/,/^def /p" "$B/harness" | grep -c 'guard(')" "1" "  cmd_$v goes through guard, the gate with it"
done
# S6's fifth landing review, item 12: the tree judged is the one the run reads — the worktree's own HEAD, so a
# reviewed seed with a newer unreviewed brief that origin never got is refused, where origin's ref (none) passed
S6M="confidential:$(printf node | shasum -a 256 | cut -c1-8)"
git -C "$T/s6open" checkout -q -b claude/laptop/2026-10-30-hx; mkdir -p "$T/s6open/docs/handoff"
echo "# hx brief" > "$T/s6open/docs/handoff/2026-10-30-hx.md"
printf '{"origin": "%s", "sha256": "%s", "scan": "clean", "judge": "clean"}\n' "$S6M" "$(shasum -a 256 "$T/s6open/docs/handoff/2026-10-30-hx.md" | cut -d' ' -f1)" > "$T/s6open/docs/handoff/2026-10-30-hx.review"
echo "# a later brief, never reviewed" > "$T/s6open/docs/handoff/2026-10-31-hx.md"
git -C "$T/s6open" add docs; git -C "$T/s6open" -c user.email=t@t -c user.name=t commit -qm "seed: hx, and a newer brief"
cat > "$T/s6one.py" <<'PY'
import importlib.machinery, importlib.util, sys
loader = importlib.machinery.SourceFileLoader("harness", sys.argv[1])
h = importlib.util.module_from_spec(importlib.util.spec_from_loader("harness", loader)); loader.exec_module(h)
print(h.spawn_refusal({"branch": sys.argv[3]} if len(sys.argv) > 3 else {}, "orca", sys.argv[2]))
PY
(cd "$T/s6open" && "${S6ENV[@]}" CLAUDE_REPOS_JSON="$T/s6-reg.json" python3 "$T/s6one.py" "$B/harness" "$T/s6open" claude/laptop/2026-10-30-hx) > "$T/out" 2>&1
has "$T/out" "its seed carries docs/handoff/2026-10-31-hx.md, newer than the brief its review vouches for" \
  "item 12: an Orca start on its branch's worktree judges the worktree's HEAD (unpushed), not origin's ref: refused"
git -C "$T/s6open" checkout -q main
# the sixth landing review: a branch named that this host has neither made nor fetched judged no tree, so an open
# caller's spawn passed (the fallback named a remote ref that is not there). Refused for now, in the waiting words
(cd "$T/s6open" && "${S6ENV[@]}" CLAUDE_REPOS_JSON="$T/s6-reg.json" python3 "$T/s6one.py" "$B/harness" "$T/s6open" claude/laptop/2026-10-30-nothere) > "$T/out" 2>&1
has "$T/out" "is refused for now" "sixth review: an Orca start naming a branch this host has not got: refused for now"
has "$T/out" "the next step waits for a run to end" "  in the cap's waiting words"
printf '{"repos": {"s6node": {}}, "scopes": {"node": {"repos": ["s6node"]}}}\n' > "$T/s6-open-reg.json"
(cd "$T/s6open" && "${S6ENV[@]}" CLAUDE_REPOS_JSON="$T/s6-open-reg.json" python3 "$T/s6one.py" "$B/harness" "$T/s6open" claude/laptop/2026-10-30-nothere) > "$T/out" 2>&1
check "$(cat "$T/out")" "None" "  with no confidential scope in the registry: nothing to judge, let through as before"
# a copy run from its file whose core does not import refuses (dispatch does); a peer's stdin copy judges nothing
mkdir -p "$T/hcopy/bin" "$T/hcopy/lib"; cp "$B/harness" "$T/hcopy/bin/harness"; echo 'raise ImportError("no core here")' > "$T/hcopy/lib/core_path.py"
(cd "$S6P/s6node" && "${S6ENV[@]}" CLAUDE_REPOS_JSON="$T/s6-reg.json" python3 "$T/s6one.py" "$T/hcopy/bin/harness" "$T/s6open") > "$T/out" 2>&1
has "$T/out" "the regatta core did not load here" "  a harness whose core did not import: refused, never an ungated start (fails closed)"
cat > "$T/s6peer.py" <<'PY'
import sys
g = {"__name__": "harness_peer"}
exec(compile(open(sys.argv[1]).read(), "<stdin>", "exec"), g)   # as a peer runs it from stdin: no __file__, no core
print(g["spawn_refusal"]({}, "orca", sys.argv[2]))
PY
check "$(python3 "$T/s6peer.py" "$B/harness" "$T/s6open")" "None" "  a peer's stdin copy: no core by design, nothing judged (its caller was judged on its own Mac)"
# a refusal a wait fixes (a torn registry) says the cap's waiting words, as dispatch's does (AGENTS.md's trap)
printf '{"repos": ' > "$T/s6-torn.json"
(cd "$S6P/s6node" && "${S6ENV[@]}" CLAUDE_REPOS_JSON="$T/s6-torn.json" python3 "$T/s6one.py" "$B/harness" "$T/s6open") > "$T/out" 2>&1
has "$T/out" "is refused for now" "  a torn registry from inside the node: refused for now"
has "$T/out" "the next step waits for a run to end" "  in the cap's waiting words, so a managed run ending on it is no unrelayed ask"

echo "orca --account: a Claude worker on a login Orca cannot select, in a terminal of ours (docs/orca-accounts-2026-10-16.md)"
# a stand-in bin/account: pick → acct-b on its own dir; limits → the row asked for; every call logged
cat > "$T/account" <<'PY'
#!/usr/bin/env python3
import json, os, sys
open(os.environ["STUB_ACCOUNT_CALLS"], "a").write(" ".join(sys.argv[1:]) + "\n")
if sys.argv[1] == "pick":
    if os.environ.get("STUB_ACCOUNT_SHORT"):
        print(json.dumps({"account": None, "skipped": [["acct-b", "ship s stays on acct-b and waits: 5h 60% > 50%"]]})); sys.exit(3)
    if os.environ.get("STUB_ACCOUNT_CODEX"):
        print(json.dumps({"account": "codex-x", "provider": "codex", "env": {"CODEX_HOME": "/c"}, "skipped": []})); sys.exit(0)
    print(json.dumps({"account": "acct-b", "env": {"CLAUDE_CONFIG_DIR": "/orca data/acct-b"}, "skipped": []}))
elif sys.argv[1] == "limits":
    lab = sys.argv[2]
    print(json.dumps([{"label": lab, "here": lab != "acct-gone", "denied": "shop" if lab == "acct-c" else None,
                       "provider": "codex" if lab.startswith("codex-") else "claude",
                       "env": {} if lab == "acct-a" else {"CLAUDE_CONFIG_DIR": "/orca data/" + lab}, "why": "ok"}]))
PY
chmod +x "$T/account"
export HARNESS_ACCOUNT="$T/account" STUB_ACCOUNT_CALLS="$T/account.calls" HARNESS_ORCA_START_WAIT=10 HARNESS_ORCA_OWN="$T/own.json"
: > "$STUB_ORCA_CALLS"; : > "$STUB_ACCOUNT_CALLS"
H run --harness orca --repo "$T/scratch" --name acct --prompt "reply DONE" --account auto --ship shop/b7 \
  --model sonnet --effort high --json > "$T/oa.json" 2>"$T/err"
check "$?" 0 "run --harness orca --account auto --ship: exits 0"
has "$STUB_ACCOUNT_CALLS" "pick --repo $T/scratch --json --ship shop/b7 --no-pin" "  the login is bin/account's pick, for the ship, not pinned yet"
has "$STUB_ACCOUNT_CALLS" "ships --pin shop/b7 acct-b" "  pinned once the worker started"
check "$(awk '/pick --repo/ {p=NR} /ships --pin/ {q=NR} END {print (p && q > p) ? "after" : "before"}' "$STUB_ACCOUNT_CALLS")" "after" "  the pin after the pick"
has "$STUB_ORCA_CALLS" "terminal create --worktree id:repo-1::$STUB_ORCA_WS/$TODAY-acct --title $TODAY-acct --command env -u CLAUDE_CODE_OAUTH_TOKEN 'CLAUDE_CONFIG_DIR=/orca data/acct-b' claude --model sonnet --effort high" \
    "  a terminal in the worktree runs claude on that login's dir, model and effort on its command line"
check "$(grep -c 'worker-start.*--terminal term_own_' "$STUB_ORCA_CALLS")" 2 "  worker-start --terminal: refused once (agent not yet known), then taken"
check "$(grep 'worker-start' "$STUB_ORCA_CALLS" | grep -c -- '--agent\|--model')" 0 "  no --agent or --model beside --terminal (Orca refuses them)"
check "$(jget "$T/oa.json" 'd["account"]')" "acct-b" "  the record names the login"
OWN=$(jget "$T/oa.json" 'd["native"]["own_terminal"]')
check "$(jget "$T/own.json" 'd')" "['$OWN']" "  the terminal recorded as this adapter's own"
H stop "$(jget "$T/oa.json" 'd["session_id"]')" --harness orca --json > "$T/os2.json" 2>"$T/err"
check "$?" 0 "stop: exits 0"
has "$STUB_ORCA_CALLS" "terminal close --terminal $OWN" "  the terminal we started is closed (Orca retains an external one)"
check "$(jget "$T/own.json" 'd')" "[]" "  and no longer recorded"
: > "$STUB_ORCA_CALLS"
H run --harness orca --repo "$T/scratch" --name acct4 --prompt x --account acct-a --json > "$T/o4.json" 2>"$T/err"
check "$?" 0 "--account acct-a (the default dir)"
has "$STUB_ORCA_CALLS" "--command env -u CLAUDE_CODE_OAUTH_TOKEN -u CLAUDE_CONFIG_DIR claude" "  our terminal with CLAUDE_CONFIG_DIR unset — never the account Orca has selected"
check "$(grep -c 'worker-start.*--agent' "$STUB_ORCA_CALLS") $(jget "$T/o4.json" 'd["account"]')" "0 acct-a" "  no Orca --agent start, the label recorded"
check "$(grep -c 'ships --pin' "$STUB_ACCOUNT_CALLS")" 1 "  a named login with no --ship pins nothing"
: > "$STUB_ORCA_CALLS"
STUB_ACCOUNT_SHORT=1 H run --harness orca --repo "$T/scratch" --name acct5 --prompt x --account auto --ship s > /dev/null 2>"$T/err"
check "$?" 1 "no login may run it (the ship's waits): exit 1"
has "$T/err" "ship s stays on acct-b and waits" "  saying why"
check "$(grep -c 'worktree create' "$STUB_ORCA_CALLS")" 0 "  nothing made in Orca first"
H run --harness orca --repo "$T/scratch" --name acct6 --prompt x --account acct-c > /dev/null 2>"$T/err"; check "$?" 2 "a login whose deny list names the repo: refused"
H run --harness orca --repo "$T/scratch" --name acct7 --prompt x --account acct-gone > /dev/null 2>"$T/err"; check "$?" 2 "a login not on this Mac: refused"
H run --harness orca --repo "$T/scratch" --name acct9 --prompt x --account codex-x > /dev/null 2>"$T/err"; check "$?" 2 "a Codex login named: refused (claude would run on the default login)"
STUB_ACCOUNT_CODEX=1 H run --harness orca --repo "$T/scratch" --name acct10 --prompt x --account auto > /dev/null 2>"$T/err"; check "$?" 2 "a pick that answers a Codex login: refused"
H run --harness orca --repo "$T/scratch" --name acct8 --prompt x --account auto --agent codex > /dev/null 2>"$T/err"; check "$?" 2 "--account with a codex worker: refused"
STUB_ORCA_UNCONF=99 STUB_ORCA_SCREEN="Yes, I trust this folder" HARNESS_ORCA_START_WAIT=4 \
  H run --harness orca --repo "$T/scratch" --name acct9 --prompt x --account auto > /dev/null 2>"$T/err"
check "$?" 1 "a claude that never reaches Orca: exit 1 after the bounded wait"
has "$T/err" "folder-trust dialog" "  the trust dialog named as the cause"
check "$(tail -1 "$STUB_ORCA_CALLS" | cut -d' ' -f1-2)" "terminal close" "  and its terminal closed"
# bin/harness loads an adapter with a bare __file__, so orca.py's own path resolves against the cwd:
# a checkout whose bin/account is the stub, run from / with no HARNESS_ACCOUNT, finds it through ctx.coding
mkdir -p "$T/copy/bin" && cp -R "$B/harness" "$B/harness_adapters" "$T/copy/bin/" && cp "$T/account" "$T/copy/bin/account"
# with its lib/ and the core named (REGATTA_HOME): a copy whose core does not import refuses every Orca start
# (the spawn gate fails closed, S6's fifth landing review), which is not what this case is about
cp -R "$B/../lib" "$T/copy/lib"
: > "$STUB_ACCOUNT_CALLS"
(cd / && env -u HARNESS_ACCOUNT REGATTA_HOME="$(cd "$B/../../.." && pwd)" python3 "$T/copy/bin/harness" run --harness orca --repo "$T/scratch" --name acct11 --prompt x \
  --account auto > /dev/null 2>"$T/err")
check "$?" 0 "--account auto from another cwd, bin/account by the checkout ctx names"
has "$STUB_ACCOUNT_CALLS" "pick --repo $T/scratch --json" "  the checkout's own bin/account answered"
unset HARNESS_ACCOUNT STUB_ACCOUNT_CALLS HARNESS_ORCA_START_WAIT HARNESS_ORCA_OWN

check "$(python3 - "$B/harness" "$T" <<'PY'
import importlib.machinery, importlib.util, os, sys
l = importlib.machinery.SourceFileLoader("hx", sys.argv[1]); m = importlib.util.module_from_spec(importlib.util.spec_from_loader("hx", l)); l.exec_module(m)
open(sys.argv[2] + "/cx-bin", "wb").write(b"\xcf\xfa\xed\xfe")
os.environ["HARNESS_CODEX"] = sys.argv[2] + "/cx-bin"; a = m.stand_in_codex()
os.environ["HARNESS_CODEX"] = sys.argv[2] + "/cbin/codex"; b = m.stand_in_codex()
open(sys.argv[2] + "/cx-node", "w").write("#!/usr/bin/env node\n")
os.environ["HARNESS_CODEX"] = sys.argv[2] + "/cx-node"; print(a, b, m.stand_in_codex())
PY
)" "False True False" "stand_in_codex(): a copy of a compiled codex is the real one, as is npm's node launcher; the suite's script is a stand-in (rounds 2, 5)"
env -i PATH="$PATH" HOME="$HOME" REGATTA_FENCE_CLEAN=1 OPENAI_API_KEY=x python3 "$B/harness" run --harness codex --mode research --prompt x \
  > /dev/null 2>"$T/rx.err"
check "$?/$(grep -c '^harness: refused: .*OPENAI_API_KEY' "$T/rx.err")/$(grep -c Traceback "$T/rx.err")" "2/1/0" \
  "research mode whose one clean re-exec still holds a credential-named variable: refused, exit 2, never a traceback (round 5b)"
env -i PATH="$PATH" HOME="$HOME" REGATTA_FENCE_CLEAN=1 OPENAI_API_KEY=x python3 "$B/harness" --mode x research > /dev/null 2>"$T/rx2.err"
check "$(grep -c -e '^harness: refused' -e Traceback "$T/rx2.err")" 0 "  'research' as another flag's word: no re-exec judged (round 5b)"
env -i PATH="$PATH" HOME="$HOME" REGATTA_FENCE_CLEAN=1 OPENAI_API_KEY=x python3 "$B/harness" run --harness codex --mode x --mode research --prompt x \
  > /dev/null 2>"$T/rx3.err"
check "$?/$(grep -c '^harness: refused: .*OPENAI_API_KEY' "$T/rx3.err")" "2/1" \
  "  --mode given twice, research last: judged as parse() reads it, the re-exec's refusal included (round 6)"
check "$(python3 - "$B/harness_adapters/codex.py" "$T/detach.out" <<'PY'
import importlib.machinery, importlib.util, os, socket, stat, sys, time
l = importlib.machinery.SourceFileLoader("cx", sys.argv[1]); m = importlib.util.module_from_spec(importlib.util.spec_from_loader("cx", l)); l.exec_module(m)
srv = socket.socket(); srv.bind(("127.0.0.1", 0)); srv.listen(1); fd = srv.fileno()
def fn():
    try:
        r = "socket" if stat.S_ISSOCK(os.fstat(fd).st_mode) else "none"
    except OSError:
        r = "none"
    open(sys.argv[2], "w").write(r)
m._detach(fn, close=[fd])
for _ in range(50):
    if os.path.exists(sys.argv[2]) and open(sys.argv[2]).read():
        break
    time.sleep(0.1)
print(open(sys.argv[2]).read())
PY
)" "none" "_detach(close=…): the detached wrapper holds no copy of the proxy's socket (round 6)"
echo "exit_report: no git in a research run's copy (round 2: a planted core.fsmonitor ran as the owner)"
git init -q "$T/fsm" && git -C "$T/fsm" config core.fsmonitor "touch $T/fsm-ran; false"
check "$(python3 - "$B/harness" "$T/fsm" <<'PY'
import importlib.machinery, importlib.util, sys
l = importlib.machinery.SourceFileLoader("hx", sys.argv[1]); m = importlib.util.module_from_spec(importlib.util.spec_from_loader("hx", l)); l.exec_module(m)
r = m.exit_report({"cwd": sys.argv[2], "native": {"mode": "research"}})
m.git_out(sys.argv[2], "status", "--porcelain")
print(r["files_changed"])
PY
)/$([ -e "$T/fsm-ran" ] && echo ran || echo never)" "None/never" "  a research record's cwd is never read by git, and no repo's fsmonitor runs from git_out"
echo "codex research mode: one fenced, read-only turn over a copy, judged by --repo and the copy (principal tier S3)"
# a dot-free scratch root of its own: the copy's path is a key of codex's profile, split at dots
RS=$(mktemp -d "${TMPDIR:-/tmp}/harness-research-XXXXXX"); RS=$(cd "$RS" && pwd -P)
# a stand-in bin/account for the vendor fence research mode asks since the fourth landing review (finding 2): the
# login it names owns the repo, unless STUB_RESEARCH_FOREIGN
cat > "$RS/account" <<'PY'
#!/usr/bin/env python3
import json, os, sys
if sys.argv[1] == "pick":
    print(json.dumps({"account": "codex-r", "provider": "codex", "env": {}, "skipped": [],
                      "owns": not os.environ.get("STUB_RESEARCH_FOREIGN")}))
PY
chmod +x "$RS/account"; export HARNESS_ACCOUNT="$RS/account"
# a copy as wharf's council lays one out: <run>/arms/<arm>/copy, the run dir 0700 and marked
RR="$RS/run"; CP="$RR/arms/a/box/copy"; mkdir -p "$CP"; chmod 700 "$RR"; : > "$RR/.council-run"
# the box's scratch CODEX_HOME, as council's fence.arm_home makes it: auth.json alone
mkhome() { mkdir -p "$1/home"/.codex && printf '{}' > "$1/home"/.codex/auth.json; }
BH=box/home   # an arm's scratch HOME, by a name the publish gate reads as no home path
mkhome "$RR/arms/a/box"
export STUB_FEATURES="$RS/features.txt"
python3 -c 'import sys
from importlib.machinery import SourceFileLoader
f = SourceFileLoader("fence", sys.argv[1]).load_module()
open(sys.argv[2], "w").write("".join("%-40s stable             true\n" % n for n in sorted(f.CODEX_FEATURES)))' \
  "$B/../../regatta/hooks/fence.py" "$STUB_FEATURES"
nrec() { ls "$HARNESS_RUNS_DIR"/codex-*.json 2>/dev/null | wc -l | tr -d ' '; }
lastev() { ls -t "$HARNESS_RUNS_DIR"/codex-*.jsonl | head -1; }
stubev() { python3 -c 'import json,sys
for l in open(sys.argv[1]):
    try: e = json.loads(l)
    except ValueError: continue
    if isinstance(e, dict) and e.get("type") == "stub": print(eval(sys.argv[2], {"d": e})); break' "$(lastev)" "$1"; }
HC="$HD/copy"; mkdir -p "$RS/dot.ted" "$HC"; echo x > "$CP/AGENTS.md"
CXA="$B/harness_adapters/codex.py"
cxa() {   # cxa <python using module m> [arg…]: the codex adapter loaded as a module, the args from sys.argv[3]
  python3 - "$CXA" "$@" <<'PY'
import sys, types
m = types.ModuleType("codex_adapter"); m.__file__ = sys.argv[1]
exec(compile(open(sys.argv[1]).read(), sys.argv[1], "exec"), m.__dict__)
exec(sys.argv[2])
PY
}
: > "$STUB_CODEX_CALLS"
H run --harness codex --mode research --repo "$T/scratch" --cwd "$CP" --prompt "a paper" --name rs1 --json > "$T/rs.json" 2>"$T/err"
check "$?" 0 "a research run in a copy outside ~ and the repo: exit 0, in the foreground"
check "$(jget "$T/rs.json" '(d["state"], d["last_message"], d["native"]["mode"], d["native"]["usage"], d["cwd"])')" \
  "('completed', 'DONE', 'research', {'input_tokens': 1, 'output_tokens': 1}, '$CP')" "  ended when it returns: the reply, the mode, the usage, the copy as cwd"
check "$(stubev 'd["argv"].split(" --disable ")[0]')" "exec --json --ephemeral --skip-git-repo-check -C $CP" \
  "  codex exec in the copy, ephemeral"
check "$(stubev '[x for x in ("--disable apps", "--disable plugins", "--disable multi_agent", "--disable hooks", "--disable shell_tool", "--dangerously-bypass-approvals-and-sandbox", "shell_environment_policy.inherit=\"core\"", "--approve-for-me", "permissions.research") if x in d["argv"]]')" \
  "['--disable apps', '--disable plugins', '--disable multi_agent', '--disable hooks', '--dangerously-bypass-approvals-and-sandbox', 'shell_environment_policy.inherit=\"core\"']" \
  "  the connectors, sub-agents and hooks off, its shell on, its own sandbox off (the seatbelt holds it); never --approve-for-me"
check "$(stubev '(d["argv"].endswith(" -"), d["stdin"], d["cwd"], d["env"]["CODEX_HOME"], d["env"]["HTTPS_PROXY"].startswith("http://127.0.0.1:"))')" \
  "(True, 'a paper', '$CP', '$RR/arms/a/$BH/.codex', True)" "  the prompt on stdin; the box's scratch CODEX_HOME; the proxy its door"
check "$(stubev '[n for n in ("STUB_CODEX_CALLS", "HARNESS_RUNS_DIR", "GIT_CONFIG_GLOBAL", "REGATTA_CONFIG") if n in d["names"]]')" "['STUB_CODEX_CALLS', 'GIT_CONFIG_GLOBAL']" \
  "  an allowlisted environment: the stand-in's own variables and git's pointed-away config, none of the caller's"
check "$(wc -c < "$STUB_CODEX_CALLS" | tr -d ' ')/$([ -s "$RR/arms/a/arm.sb" ] && echo profile)" "0/profile" \
  "  under the seatbelt: no write outside its box; the profile beside the box, the caller's"
check "$(cxa '
import types
m._fence = lambda: types.SimpleNamespace(available=lambda: False)
class Ctx:
    def fail(self, msg, code=1): raise SystemExit("%d %s" % (code, msg))
try:
    m.research(Ctx(), {"cwd": "/nowhere", "prompt": "p", "timeout": 5}); print("ran")
except SystemExit as e:
    print(str(e)[:20])')" "2 no seatbelt here (" "  no seatbelt (off macOS): refused"
H resume "$(jget "$T/rs.json" 'd["session_id"]')" --prompt more > /dev/null 2>"$T/err"; check "$?" 2 "  a research run is never continued"
: > "$STUB_CODEX_CALLS"
H run --harness codex --mode research --repo "$T/scratch" --cwd "$CP" --review main --json > "$T/rv.json" 2>"$T/err"; check "$?" 0 "--review BASE: codex exec review, no prompt needed"
check "$(stubev 'd["argv"].endswith(" review --base main") and "--dangerously-bypass-approvals-and-sandbox" in d["argv"]')" "True" \
  "  the fence's flags, then review --base main, no stdin dash"
hasnt "$STUB_CODEX_CALLS" "codex plugin list" "no \`codex plugin list\` gate: the shell is the arm's, whatever the account holds (F7 fences its connectors)"
H run --harness codex --mode research --repo "$T/scratch" --cwd "$CP" --prompt x --text-only > /dev/null 2>"$T/err"; check "$?" 1 "--text-only is no flag now: no text-only road"
has "$T/err" "unexpected '--text-only'" "  saying so"
echo "codex research mode: F7, the login withdrawn at codex's first request to chatgpt.com"
STUB_CODEX_VENDOR=1 STUB_CODEX_CMD=1 H run --harness codex --mode research --repo "$T/scratch" --cwd "$CP" --prompt x --json > "$T/r7.json" 2>"$T/err"
check "$?" 0 "a turn whose codex asks chatgpt.com first, then runs a command"
check "$(jget "$T/r7.json" '(d["native"]["credential"]["withdrawn"]["ok"], d["native"]["credential"]["withdrawn"]["host"], d["native"]["credential"]["at_first_tool"])')/$([ -e "$RR/arms/a/$BH/.codex/auth.json" ] && echo there || echo gone)" \
  "(True, 'chatgpt.com', [])/gone" "  its auth.json withdrawn at that request, before the reply; nothing of it on disk at the first command"
check "$(jget "$T/r7.json" '([x == d["native"]["events"] for x in d["native"]["files"]].count(True), len(d["native"]["files"]))')" "(1, 4)" \
  "  the files the turn wrote outside the arm's dir (its record, events, log, reply) named for council's scan"
check "$(python3 -c 'import json,sys; print(["withdraw" in e for e in map(json.loads, open(sys.argv[1]))].count(True))' "$RR/arms/a/proxy.jsonl")" "1" \
  "  the withdrawal a line of the proxy's log, beside the box"
mkhome "$RR/arms/a/box"
STUB_CODEX_CMD=1 H run --harness codex --mode research --repo "$T/scratch" --cwd "$CP" --prompt x --json > "$T/r8.json" 2>"$T/err"
check "$(jget "$T/r8.json" '(d["native"]["credential"]["withdrawn"], d["native"]["credential"]["at_first_tool"])')" "(None, ['auth.json'])" \
  "  a codex that ran a command with no request to its vendor first: never withdrawn, auth.json on disk at it (council fails that arm)"
STUB_CODEX_THREAD=th-rs-hold STUB_CODEX_HOLD=1 H run --harness codex --mode research --repo "$T/scratch" --cwd "$CP" --prompt x --timeout 2 --json > "$T/rh.json" 2>"$T/err"
check "$?" 1 "a turn past --timeout: stopped, exit 1"
check "$(jget "$T/rh.json" '(d["state"], d["native"]["end_reason"])')/$(kill -0 "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("pid"))' "$(jget "$T/rh.json" 'd["native"]["run"]')")" 2>/dev/null && echo alive || echo gone)" \
  "('canceled', 'timeout after 2 s')/gone" "  canceled, saying so, its codex gone"
check "$(cxa '
import threading
path = sys.argv[3]; m._save(path, {}); errs = []
def go(i):
    for j in range(300):
        try:
            m._update(path, **{"k%d" % i: j})
        except Exception as e:
            errs.append(repr(e)); return
ts = [threading.Thread(target=go, args=(i,)) for i in range(4)]
[t.start() for t in ts]; [t.join() for t in ts]
print(len(errs), sorted(m._load(path).items()) == [("k%d" % i, 299) for i in range(4)])' "$RS/race.json")" "0 True" \
  "  the deadline thread and the loop write one record: no shared temp file, no update lost (the landing review)"
: > "$STUB_CODEX_CALLS"
for c in "--mode research --cwd $CP --prompt x" \
         "--mode research --repo $T/scratch --prompt x" \
         "--mode research --repo $T/scratch --cwd $HC --prompt x" \
         "--mode research --repo $T/scratch --cwd $T/scratch-wt --prompt x" \
         "--mode research --repo $T/scratch --cwd $RS/dot.ted --prompt x" \
         "--mode research --repo $T/projects/site --cwd $CP --prompt x" \
         "--mode research --repo $T/live --cwd $CP --prompt x" \
         "--mode research --repo $T/scratch --cwd $CP --prompt x --runner orca" \
         "--mode research --repo $T/scratch --cwd $CP --prompt x --timeout 0" \
         "--mode other --repo $T/scratch --cwd $CP --prompt x"; do
  H run --harness codex $c > /dev/null 2>"$T/err"; check "$?" 2 "refused: $(echo "$c" | sed "s|$RS|RS|g; s|$T|T|g; s|$HOME|~|g")"
done
n0=$(nrec); mkdir -p "$RR/arms/b/box/copy"
H run --harness codex --mode research --repo "$T/scratch" --cwd "$RR/arms/b/box/copy" --prompt x > /dev/null 2>"$T/err"
check "$?/$(nrec)" "2/$n0" "refused: a box with no scratch CODEX_HOME (codex never starts from the login's own)"; has "$T/err" "no scratch CODEX_HOME" "  saying why"
# a folder under ~, in the home repo or in another repo is no council arm's box: the one rule over --cwd since S3 (the
# core's fence.box_why; the ~, home-repo, other-repo and dot rules it replaced read what the seatbelt holds now)
mkdir -p "$RS/h/copy"; git init -q -b main "$RS/homerepo"; printf -- '- physical: none\n' > "$RS/homerepo/AGENTS.md"; mkdir -p "$RS/homerepo/sub"
git init -q -b main "$RS/other"; mkdir -p "$RS/other/sub"
for c in "$RS/h/copy" "$RS/homerepo/sub" "$RS/other/sub"; do
  H run --harness codex --mode research --repo "$T/scratch" --cwd "$c" --prompt x > /dev/null 2>"$T/err"
  check "$?" 2 "refused: $(echo "$c" | sed "s|$RS|RS|g") is no council arm's box"; has "$T/err" "no council arm's copy" "  by the box rule"
done
git init -q -b main "$RS/conf-co"
printf '{"repos": {"scratch": {}, "conf-co": {}}, "scopes": {"open": {"file": "o.code-workspace", "repos": ["scratch"]}, "w": {"file": "w.code-workspace", "repos": ["conf-co"], "confidential": true}}}\n' > "$RS/conf-cwd.json"
CLAUDE_REPOS_JSON="$RS/conf-cwd.json" H run --harness codex --mode research --repo "$T/scratch" --cwd "$RS/conf-co" --prompt x > /dev/null 2>"$T/err"
check "$?" 2 "refused: a confidential checkout named as --cwd, whatever --repo says"; has "$T/err" "confidential" "  by the confidential rule, on the copy too"
H run --mode research --repo "$T/scratch" --cwd "$CP" --prompt x > /dev/null 2>&1; check "$?" 2 "refused: research mode with claude-code (Codex's only)"
H run --harness codex --mode research --repo "$T/scratch" --cwd /tmp --prompt x > /dev/null 2>"$T/err"; check "$?" 2 "refused: a shared scratch root as --cwd (no council arm's box)"
printf '{"repos": {"scratch": {}}, "scopes": {"w": {"file": "w.code-workspace", "repos": ["scratch"], "confidential": true}}}\n' > "$RS/conf.json"
CLAUDE_REPOS_JSON="$RS/conf.json" H run --harness codex --mode research --repo "$T/scratch" --cwd "$CP" --prompt x > /dev/null 2>"$T/err"
check "$?" 2 "refused: a confidential scope's repo, whoever calls"
printf '{"repos": {' > "$RS/torn.json"
CLAUDE_REPOS_JSON="$RS/torn.json" H run --harness codex --mode research --repo "$T/scratch" --cwd "$CP" --prompt x > /dev/null 2>&1
check "$?" 2 "refused: any repo while the registry cannot be read"
check "$(nrec)" "$n0" "  codex never ran for any of them"
: > "$STUB_CODEX_CALLS"
CLAUDE_UNATTENDED=dispatch H run --harness codex --mode research --repo "$T/scratch" --cwd "$CP" --prompt x > /dev/null 2>"$T/err"
check "$?" 2 "unattended, unbounded: refused"
has "$T/err" "bounded" "  saying it must be bounded"
CLAUDE_UNATTENDED=dispatch H run --harness codex --mode research --repo "$T/scratch" --cwd "$CP" --prompt x --timeout 3600 --council c1:arms > /dev/null 2>&1
check "$?" 2 "  a timeout past 1800 s: refused"
AUTOFINISH_CALLER_UNATTENDED=1 H run --harness codex --mode research --repo "$T/scratch" --cwd "$CP" --prompt x --timeout 60 --council c1 > /dev/null 2>"$T/err"
check "$?" 2 "  a --council that is not RUN:VERB: refused (a peer's unattended caller too)"
# every other Codex mode: an unattended caller may start one since vendor-fence (main's cases, below, hold the cap)
CLAUDE_UNATTENDED=dispatch H run --harness codex --mode research --repo "$T/scratch" --cwd "$CP" --prompt x --timeout 60 --council c1:arms > /dev/null 2>&1
check "$?" 0 "unattended with --timeout, --council RUN:VERB and a free slot: runs"
has "$STUB_DISPATCH_CALLS" "--cap" "  this Mac's cap asked before codex starts"
CLAUDE_UNATTENDED=dispatch H run --harness codex --mode research --repo "$T/scratch" --cwd "$CP" --prompt x --timeout 60 --council c1:arms > /dev/null 2>"$T/err"
check "$?" 2 "  the same council verb's second Codex run: refused"
has "$T/err" "one per council verb" "  saying why"
CLAUDE_UNATTENDED=dispatch H run --harness codex --mode research --repo "$T/scratch" --cwd "$CP" --prompt x --timeout 60 --council c1:examine > /dev/null 2>&1
check "$?" 0 "  its examine: runs (two per council run)"
CLAUDE_UNATTENDED=dispatch H run --harness codex --mode research --repo "$T/scratch" --cwd "$CP" --prompt x --timeout 60 --council c1:examine-2 > /dev/null 2>"$T/err"
check "$?" 2 "  a third, under a fresh verb name: refused"
has "$T/err" "its arms and one examine" "  saying why"
n0=$(nrec)
STUB_DISPATCH_CAP=0 CLAUDE_UNATTENDED=dispatch H run --harness codex --mode research --repo "$T/scratch" --cwd "$CP" --prompt x --timeout 60 --council c4:arms > /dev/null 2>"$T/err"
check "$?" 2 "unattended with this Mac's cap full: refused before codex starts"
has "$T/err" "the next step waits for a run to end" "  in the cap's own waiting words"
check "$(nrec)" "$n0" "  codex never ran"
cxa '
import json, os, time
d = os.environ["HARNESS_RUNS_DIR"]
for i in range(m.UNATTENDED_PER_DAY):
    json.dump({"mode": "research", "unattended": True, "started": time.time() - 60, "ended": time.time(), "council": "day%d:arms" % i},
              open(os.path.join(d, "codex-20000101-000000-dd%04d-day.json" % i), "w"))'
CLAUDE_UNATTENDED=dispatch H run --harness codex --mode research --repo "$T/scratch" --cwd "$CP" --prompt x --timeout 60 --council c5:arms > /dev/null 2>"$T/err"
check "$?" 2 "unattended, the day's cap of research runs reached: refused"
has "$T/err" "in the last 24 h" "  saying why"
has "$T/err" "the next step waits for a run to end" "  in the cap's waiting words (AGENTS.md: a new refusal a wait fixes)"
rm -f "$HARNESS_RUNS_DIR"/codex-20000101-000000-dd*-day.json
STUB_CODEX_THREAD=th-rs-cap STUB_CODEX_HOLD=1 H run --harness codex --mode research --repo "$T/scratch" --cwd "$CP" --prompt x --timeout 8 --council c2:arms > /dev/null 2>&1 &
RSP=$!
n=""; for i in $(seq 1 40); do
  n=$(python3 - "$B/dispatch-rc" <<'PY'
import importlib.machinery, importlib.util, sys
loader = importlib.machinery.SourceFileLoader("dispatch_rc", sys.argv[1])
m = importlib.util.module_from_spec(importlib.util.spec_from_loader("dispatch_rc", loader)); loader.exec_module(m)
print("%d %d %d" % (len(m.research_live()), m.counted([]), m.vendor_slots()))
PY
); [ "$n" = "1 1 0" ] && break; sleep 0.25; done
check "$n" "1 1 0" "dispatch-rc's cap counts a running research run: one slot, once (vendor_slots leaves it to research_live: round 1)"
H stop th-rs-cap > /dev/null 2>&1; wait "$RSP" 2>/dev/null
check "$(python3 - "$B/dispatch-rc" "$HARNESS_RUNS_DIR" <<'PY'
import importlib.machinery, importlib.util, json, os, sys
loader = importlib.machinery.SourceFileLoader("dispatch_rc", sys.argv[1])
m = importlib.util.module_from_spec(importlib.util.spec_from_loader("dispatch_rc", loader)); loader.exec_module(m)
m.proc_start = lambda pid: ""   # `ps -o lstart=` printing nothing for a live pid (the docstring of running())
p = os.path.join(sys.argv[2], "codex-20000101-000000-ee0000-empty-ps.json")
json.dump({"mode": "research", "pid": os.getpid(), "proc_start": "Thu Jan  1 00:00:00 1970"}, open(p, "w"))
print(len([x for x in m.research_live() if x == p])); os.remove(p)
PY
)" "1" "  a live run whose ps prints nothing still holds its slot (running(), as a run's)"
check "$(DISPATCH_RC_VENDORS=0 python3 - "$B/dispatch-rc" "$HARNESS_RUNS_DIR" <<'PY'
import importlib.machinery, importlib.util, json, os, sys
loader = importlib.machinery.SourceFileLoader("dispatch_rc", sys.argv[1])
m = importlib.util.module_from_spec(importlib.util.spec_from_loader("dispatch_rc", loader)); loader.exec_module(m)
p = os.path.join(sys.argv[2], "codex-20000101-000000-ee0001-off.json")
json.dump({"mode": "research", "pid": os.getpid()}, open(p, "w"))
print(len(m.research_live())); os.remove(p)
PY
)" "0" "  DISPATCH_RC_VENDORS=0 counts no research run either, as vendor_slots() (the landing review)"
check "$(REGATTA_UNATTENDED=1 DISPATCH_RC_VENDORS=0 python3 - "$B/dispatch-rc" "$HARNESS_RUNS_DIR" <<'PY'
import importlib.machinery, importlib.util, json, os, sys
loader = importlib.machinery.SourceFileLoader("dispatch_rc", sys.argv[1])
m = importlib.util.module_from_spec(importlib.util.spec_from_loader("dispatch_rc", loader)); loader.exec_module(m)
p = os.path.join(sys.argv[2], "codex-20000101-000000-ee0002-off-unattended.json")
json.dump({"mode": "research", "pid": os.getpid()}, open(p, "w"))
print(len([x for x in m.research_live() if x == p])); os.remove(p)
PY
)" "1" "  but never for an unattended caller, which may inherit the switch: its run is the spend (the fix round)"
STUB_CODEX_THREAD=th-rs-orphan STUB_CODEX_HOLD=1 H run --harness codex --mode research --repo "$T/scratch" --cwd "$CP" --prompt x --timeout 2 --name orphan > /dev/null 2>&1 &
# killed once codex runs: the gates and the probe come first (S1), so wait for its record's pid
RSP=$!; for i in $(seq 1 60); do ls "$HARNESS_RUNS_DIR"/codex-*-orphan.json > /dev/null 2>&1 && \
  [ -n "$(jget "$(ls -t "$HARNESS_RUNS_DIR"/codex-*-orphan.json | head -1)" 'd.get("pid") or ""')" ] && break; sleep 0.25; done
kill -9 "$RSP" 2>/dev/null; wait "$RSP" 2>/dev/null
OR=$(ls -t "$HARNESS_RUNS_DIR"/codex-*-orphan.json | head -1); OP=$(jget "$OR" 'd.get("pid")')
st=alive; for i in $(seq 1 60); do kill -0 "$OP" 2>/dev/null || { st=gone; break; }; sleep 0.25; done
check "$st/$(jget "$OR" 'd.get("end_reason")')" "gone/timeout after 2 s" "the deadline holds with its waiter killed: the wrapper ends codex itself"

echo "research mode: the council's S3 one-liners (the third landing review)"
# finding 12: a --timeout that is no finite number passes no bound
for v in nan inf -inf; do
  H run --harness codex --mode research --repo "$T/scratch" --cwd "$CP" --prompt x --timeout "$v" > /dev/null 2>"$T/err"
  check "$?" 2 "refused: --timeout $v"; has "$T/err" "finite" "  saying it must be finite"
done
# finding 11: the caller's deadline is the turn's, so the start's waits come out of the caller's bound
DL=$(python3 -c 'import time; print("%.3f" % (time.time() + 40))')
H run --harness codex --mode research --repo "$T/scratch" --cwd "$CP" --prompt x --timeout 60 --deadline "$DL" --json > "$T/rd.json" 2>"$T/err"
check "$?/$(jget "$(jget "$T/rd.json" 'd["native"]["run"]')" '"%.3f" % d["deadline"]')" "0/$DL" "--deadline: the turn's deadline is the caller's, not --timeout from harness's start"
for v in "$(python3 -c 'import time; print(time.time() - 5)')" "$(python3 -c 'import time; print(time.time() + 600)')" nan; do
  H run --harness codex --mode research --repo "$T/scratch" --cwd "$CP" --prompt x --timeout 60 --deadline "$v" > /dev/null 2>"$T/err"
  check "$?" 2 "  refused: a deadline passed, past --timeout, or no number"
done
H run --harness codex --cwd "$CW" --prompt x --deadline "$DL" > /dev/null 2>&1; check "$?" 2 "  --deadline outside research mode: refused"
H run --harness codex --cwd "$CW" --prompt x --review main > /dev/null 2>&1; check "$?" 2 "  --review outside research mode: refused, never dropped (round 6)"
H run --harness codex --cwd "$CW" --prompt x --council r:run > /dev/null 2>&1; check "$?" 2 "  --council too"
# finding 8: the counts read the records by mtime, before dispatch's start lock: an old run's record never blocks
cxa '
import json, os, time
p = os.path.join(os.environ["HARNESS_RUNS_DIR"], "codex-20000101-000000-ff0000-old.json")
json.dump({"mode": "research", "council": "old1:arms", "started": time.time() - 8 * 86400}, open(p, "w"))
os.utime(p, (time.time() - 8 * 86400,) * 2)'
H run --harness codex --mode research --repo "$T/scratch" --cwd "$CP" --prompt x --council old1:arms > /dev/null 2>"$T/err"
check "$?" 0 "a record older than the counts' horizon (8 days by mtime) is never read: its council verb runs"
check "$(cxa 'print(len(m._recent(m.COUNCIL_HORIZON)) == len([1 for p, r in m._records() if r.get("mode") == "research"]) - 1, m.research_counts({"council": "old1:arms"}, False) is not None)')" "True True" \
  "  _recent leaves it out, and the fresh run of that verb now counts"
rm -f "$HARNESS_RUNS_DIR"/codex-20000101-000000-ff0000-old.json
# finding 14: the deadline's mark is written only while the record has no end, under the record's lock
check "$(cxa '
import os
class P:
    def poll(self): return None
d = sys.argv[3]; os.makedirs(d, exist_ok=True); path = os.path.join(d, "r14.json")
m._save(path, {"ended": 1.0, "exit": 0})
a = m._mark_ending(path, P(), "timeout after 5 s")
m._save(path, {})
b = m._mark_ending(path, P(), "timeout after 5 s")
print(a, m._load(path).get("ending"), b)' "$RS/r14")" "False timeout after 5 s True" \
  "_kill's mark: none once the wrapper wrote the end (a finished turn never reads canceled); written while codex runs"
# finding 6: a fixture is spelled under $HD (the suite's $T/home), never a bare HOME — a block run outside the suite has the real one
check "$(grep -c '"\$HOME"\{0,1\}/' "$0")" 0 "finding 6: no fixture path in this suite starts at a bare HOME"

echo "research mode: the council's second landing review (2026-10-28)"
# finding 5: a copy the council made, never some folder or a clone
mkdir -p "$RS/bare/x/box/copy"; echo x > "$RS/bare/x/box/copy/AGENTS.md"
H run --harness codex --mode research --repo "$T/scratch" --cwd "$RS/bare/x/box/copy" --prompt x > /dev/null 2>"$T/err"
check "$?" 2 "refused: a copy in no council run dir (no .council-run two or three folders above its box)"; has "$T/err" "no run dir holding .council-run" "  saying why"
mkdir -p "$RR/arms/c/copy"
H run --harness codex --mode research --repo "$T/scratch" --cwd "$RR/arms/c/copy" --prompt x > /dev/null 2>"$T/err"
check "$?" 2 "refused: a copy under the run dir but in no box"; has "$T/err" "no council arm's copy" "  saying why"
mkdir -p "$RS/open/arms/a/box/copy"; : > "$RS/open/.council-run"; chmod 755 "$RS/open"
H run --harness codex --mode research --repo "$T/scratch" --cwd "$RS/open/arms/a/box/copy" --prompt x > /dev/null 2>"$T/err"
check "$?" 2 "refused: a marked run dir others can read"; has "$T/err" "not this account's alone" "  saying why"
mkdir -p "$RR/review/box"; git clone -q "$T/scratch" "$RR/review/box/clone" 2>/dev/null
H run --harness codex --mode research --repo "$T/scratch" --cwd "$RR/review/box/clone" --prompt x > /dev/null 2>"$T/err"
check "$?" 2 "refused: a folder in the review's box that is neither its copy nor its repo"; has "$T/err" "no council arm's copy" "  saying why"
git init -q -b base "$RR/review/box/repo"; mkhome "$RR/review/box"
H run --harness codex --mode research --repo "$T/scratch" --cwd "$RR/review/box/repo" --prompt x > /dev/null 2>&1
check "$?" 0 "  the review's own scratch repo runs"
# S3: the rules box_why replaced are gone — a remote in the review's repo (F4 denies every object outside the box, and
# no login to fetch with is in it) and a dot in the run dir's path (the old Codex profile's keys; the seatbelt quotes it)
git -C "$RR/review/box/repo" remote add origin "$T/scratch"
H run --harness codex --mode research --repo "$T/scratch" --cwd "$RR/review/box/repo" --prompt x > /dev/null 2>&1
check "$?" 0 "  with a remote too: runs (S3: no .git rule; the seatbelt holds the box)"
DR="$RS/dot.run"; mkdir -p "$DR/arms/a/box/copy"; chmod 700 "$DR"; : > "$DR/.council-run"; mkhome "$DR/arms/a/box"
H run --harness codex --mode research --repo "$T/scratch" --cwd "$DR/arms/a/box/copy" --prompt x > /dev/null 2>&1
check "$?" 0 "  a run dir with a dot in its path: runs (S3: no dot rule)"
# finding 4: the guarded-source rule, on --repo and on the prompt file
echo scratch > "$REGATTA_CONFIG/regatta/guarded"; n0=$(nrec)
H run --harness codex --mode research --repo "$T/scratch" --cwd "$CP" --prompt x > /dev/null 2>"$T/err"
check "$?" 2 "refused: a guarded --repo without the owner's quote (bin/gate's vet)"; has "$T/err" "--approved" "  naming --approved"
check "$(nrec)" "$n0" "  codex never ran"
H run --harness codex --mode research --repo "$T/scratch" --cwd "$CP" --prompt x --approved "Sam, 2026-10-28: yes" > /dev/null 2>&1
check "$?" 0 "  with --approved: runs"
STUB_RESEARCH_FOREIGN=1 H run --harness codex --mode research --repo "$T/scratch" --cwd "$CP" --prompt x --approved "Sam, 2026-10-28: yes" > /dev/null 2>"$T/err"
check "$?" 2 "  on a login the guarded repo's tenant does not own: refused, quote or not (the vendor fence; the fourth landing review, finding 2)"
has "$T/err" "goes only to a login its tenant owns" "  in the vendor fence's words"
DISPATCH_DEPTH=5 H run --harness codex --mode research --repo "$T/scratch" --cwd "$CP" --prompt x --approved "Sam, 2026-10-28: yes" > /dev/null 2>"$T/err"
check "$?" 2 "  a caller at DISPATCH_MAX_DEPTH: refused, as every other Codex start (finding 2)"; has "$T/err" "depth 5" "  saying why"
CLAUDE_UNATTENDED=dispatch H run --harness codex --mode research --repo "$T/scratch" --cwd "$CP" --prompt x --timeout 60 --council g1:arms \
  --approved "Sam, 2026-10-28: yes" > /dev/null 2>"$T/err"
check "$?" 2 "  --approved from an unattended caller: refused (the quote is the owner's yes)"; has "$T/err" "unattended" "  saying why"
git init -q -b main "$RS/gnotes"; printf 'a guarded note\n' > "$RS/gnotes/brief.md"; echo gnotes > "$REGATTA_CONFIG/regatta/guarded"
H run --harness codex --mode research --repo "$T/scratch" --cwd "$CP" --prompt-file "$RS/gnotes/brief.md" > /dev/null 2>"$T/err"
check "$?" 2 "refused: a prompt file from a guarded repo, whatever --repo says"
rm -f "$REGATTA_CONFIG/regatta/guarded"
H run --harness codex --cwd "$CW" --prompt x --approved q > /dev/null 2>&1; check "$?" 2 "--approved outside research mode: refused"
H run --harness codex --mode research --repo "$T/scratch" --cwd "$CP" --prompt x --timeout 90000 > /dev/null 2>&1
check "$?" 2 "refused: a --timeout past a day (dispatch-rc reads only the last day's records)"
# finding 9: the bounds' variables move them only beside a stand-in codex
mkdir -p "$RS/pathbin"; ln -s "$HARNESS_CODEX" "$RS/pathbin/codex"
PATH="$RS/pathbin:$PATH" CLAUDE_UNATTENDED=dispatch H run --harness codex --mode research --repo "$T/scratch" --cwd "$CP" --prompt x \
  --timeout 60 --council m1:arms > /dev/null 2>"$T/err"
check "$?" 2 "unattended, HARNESS_RUNS_DIR and HARNESS_DISPATCH set and HARNESS_CODEX the codex on PATH: refused"
has "$T/err" "would move them" "  saying why"
# finding 2 (S3): no config parser; Codex's administrator layers refuse the turn — any /etc/codex/*.toml, a managed
# preferences plist or the com.openai.codex domain holding config_toml_base64 or requirements_toml_base64. A login's own
# config.toml is not codex's here (the box's scratch home is), and the copy's own .codex/ is stripped by council (S2)
mkdir -p "$HD/.codex"; printf '[mcp_servers.files]\ncommand = "x"\n' > "$HD/.codex/config.toml"
H run --harness codex --mode research --repo "$T/scratch" --cwd "$CP" --prompt x > /dev/null 2>&1
check "$?" 0 "the login's own config.toml with an MCP server: not codex's here (the scratch home is), runs"
rm_own "$HD/.codex"
mkdir -p "$RS/etc" "$RS/mdm"
printf '#!/bin/sh\n[ "$3" = "%s" ] && exit 0; exit 1\n' requirements_toml_base64 > "$RS/defaults-yes"; chmod +x "$RS/defaults-yes"
printf '#!/bin/sh\nexit 1\n' > "$RS/defaults-no"; chmod +x "$RS/defaults-no"
mw() { cxa '
m.CODEX_ETC, m.CODEX_DEFAULTS = sys.argv[3], (sys.argv[4], "read", "com.openai.codex")
m.CODEX_MDM_PLISTS = (sys.argv[5],)
print(m.managed_why())' "$RS/etc" "$1" "$RS/mdm/com.openai.codex.plist"; }
check "$(mw "$RS/defaults-no")" "None" "managed_why: no administrator layer, None"
: > "$RS/etc/requirements.toml"
mw "$RS/defaults-no" > "$T/mw"; has "$T/mw" "Codex's administrator config $RS/etc/requirements.toml is here" "  an /etc/codex/*.toml: refused, named"
rm -f "$RS/etc/requirements.toml"
python3 -c 'import plistlib,sys; plistlib.dump({"config_toml_base64": "eA==", "other": 1}, open(sys.argv[1], "wb"))' "$RS/mdm/com.openai.codex.plist"
mw "$RS/defaults-no" > "$T/mw"; has "$T/mw" "set config_toml_base64" "  a managed plist setting config_toml_base64: refused"
hasnt "$T/mw" "eA==" "  its value never read out"
python3 -c 'import plistlib,sys; plistlib.dump({"other": 1}, open(sys.argv[1], "wb"))' "$RS/mdm/com.openai.codex.plist"
check "$(mw "$RS/defaults-no")" "None" "  the Codex app's own keys in the domain: no refusal (only the two keys count)"
printf 'torn' > "$RS/mdm/com.openai.codex.plist"
mw "$RS/defaults-no" > "$T/mw"; has "$T/mw" "do not read" "  a managed plist that does not read: refused"
rm -f "$RS/mdm/com.openai.codex.plist"
mw "$RS/defaults-yes" > "$T/mw"; has "$T/mw" "the com.openai.codex domain sets requirements_toml_base64" "  cfprefsd answering requirements_toml_base64: refused"
echo "a research turn's leftovers die with it (round 3: its own process group)"
if [ "$(uname)" = Darwin ]; then
  rm -f "$CP/kid.pid"
  STUB_CODEX_KID=1 H run --harness codex --mode research --repo "$T/scratch" --cwd "$CP" --prompt x > /dev/null 2>&1; rc=$?
  sleep 0.5; KP=$(cat "$CP/kid.pid" 2>/dev/null)
  check "$rc/$([ -n "$KP" ] && { kill -0 "$KP" 2>/dev/null && echo alive || echo gone; } || echo no-kid)" "0/gone" \
    "  a process the stub codex left running in its copy is gone once the turn ends"
  rm -f "$CP/kid.pid"; t0=$(date +%s)
  STUB_CODEX_KID=pipe H run --harness codex --mode research --repo "$T/scratch" --cwd "$CP" --prompt x --timeout 120 > /dev/null 2>&1; rc=$?
  t1=$(date +%s); sleep 0.5; KP=$(cat "$CP/kid.pid" 2>/dev/null)
  check "$rc/$([ $((t1 - t0)) -lt 30 ] && echo prompt || echo "waited $((t1 - t0)) s")/$([ -n "$KP" ] && { kill -0 "$KP" 2>/dev/null && echo alive || echo gone; } || echo no-kid)" "0/prompt/gone" \
    "  one that holds codex's stdout: the turn still ends when codex does, the process gone (round 5b)"
fi
# finding 6: the queue's reservations count, under dispatch's start lock
qb() { python3 - "$B/dispatch-queue" <<'PY'
import sys
from importlib.machinery import SourceFileLoader
print(SourceFileLoader("dq", sys.argv[1]).load_module().busy("launchctl"))
PY
}
CAP=$(( $(qb) + 1 )); CL="$HD/Library/Caches/run-seed/queue/claims"; mkdir -p "$CL"
printf '{"qid": "q-test", "at": %d, "pid": %d}\n' "$(date +%s)" "$$" > "$CL/q-test.t1.json"
STUB_DISPATCH_CAP=$CAP CLAUDE_UNATTENDED=dispatch H run --harness codex --mode research --repo "$T/scratch" --cwd "$CP" --prompt x \
  --timeout 60 --council q1:arms > /dev/null 2>"$T/err"
check "$?" 2 "unattended, the last slot held by a queue claim: refused (its reservation counts)"
has "$T/err" "the next step waits for a run to end" "  in the cap's own waiting words"
rm -f "$CL/q-test.t1.json"
LK="$HD/Library/Caches/run-seed/start.lock"; mkdir -p "$LK"
( sleep 3 & echo $! > "$LK/pid" )   # an orphan: launchd reaps it, so it reads as gone once it ends
t0=$(date +%s)
STUB_DISPATCH_CAP=$CAP CLAUDE_UNATTENDED=dispatch H run --harness codex --mode research --repo "$T/scratch" --cwd "$CP" --prompt x \
  --timeout 60 --council q2:arms > /dev/null 2>&1; rc=$?
check "$rc/$(( $(date +%s) - t0 >= 2 ))" "0/1" "  dispatch's start lock held by a live start: waited for, then the run"
check "$([ -d "$LK" ] && echo held || echo free)" "free" "  and given back once codex runs"
: > "$T/locklog"
STUB_LOCKDIR="$LK" STUB_LOCKLOG="$T/locklog" STUB_DISPATCH_CAP=$CAP CLAUDE_UNATTENDED=dispatch H run --harness codex --mode research \
  --repo "$T/scratch" --cwd "$CP" --prompt x --timeout 60 --council q3:arms > /dev/null 2>&1; rc=$?
check "$rc/$(cat "$T/locklog")/$([ -d "$LK" ] && echo held || echo free)" "0/free/free" \
  "  the lock is not held while codex's features are listed and the seatbelt probed: taken right before codex starts (the fourth landing review, finding 9)"
# finding 7: a turn that ends as its deadline fires is completed, never a timeout
for lie in "" 1; do
  check "$(cxa '
import json, os, subprocess as sp, threading, types, time
d = sys.argv[3]; lie = sys.argv[4]; os.makedirs(d, exist_ok=True)
path = os.path.join(d, "r7%s.json" % lie)
m._save(path, {"events": path + ".jsonl", "log": path + ".log", "deadline": time.time() + 60, "timeout": 60,
               "mode": "research", "reply": path + ".reply"})
fired = []
class T:
    def __init__(self, delay, fn):
        fired.append(fn)
    def start(self):
        pass
    def cancel(self):
        pass
real = sp.Popen
class P(real):
    lying = False
    def poll(self):
        if self.lying:
            self.lying = False
            return None
        return real.poll(self)
    def wait(self, *a, **k):
        code = real.wait(self, *a, **k)
        self.lying = bool(lie)   # with lie: the timer reads codex as running once, then it is gone
        fired[0]()               # the deadline lands as the turn ends
        return code
m.threading = types.SimpleNamespace(Timer=T, Event=threading.Event, RLock=threading.RLock, get_ident=threading.get_ident,
                                    Thread=threading.Thread)
m.subprocess = types.SimpleNamespace(**{k: getattr(sp, k) for k in dir(sp) if not k.startswith("__")})
m.subprocess.Popen = P
m._wrap(path, ["/bin/sh", "-c", "cat > /dev/null; echo done"], "p", d)
r = m._load(path)
print(m._end_state(r), r.get("end_reason"))' "$RS/k7" "$lie")" "completed exit 0" \
    "a turn that ends as its deadline fires: completed, not recorded a timeout$([ -n "$lie" ] && echo ' (the timer saw it running once, sent nothing)')"
done
# finding 11: dispatch-rc reads the last day's records only
check "$(python3 - "$B/dispatch-rc" "$HARNESS_RUNS_DIR" <<'PY'
import importlib.machinery, importlib.util, json, os, sys, time
loader = importlib.machinery.SourceFileLoader("dispatch_rc", sys.argv[1])
m = importlib.util.module_from_spec(importlib.util.spec_from_loader("dispatch_rc", loader)); loader.exec_module(m)
m.proc_start = lambda pid: ""
p = os.path.join(sys.argv[2], "codex-20000101-000000-ff0000-old.json")
json.dump({"mode": "research", "pid": os.getpid(), "proc_start": "x"}, open(p, "w"))
fresh = len([x for x in m.research_live() if x == p])
os.utime(p, (time.time() - 3 * 86400, time.time() - 3 * 86400))
old = len([x for x in m.research_live() if x == p])
os.remove(p)
print(fresh, old)
PY
)" "1 0" "dispatch-rc's research count skips a record older than a research turn lives (none is pruned)"
rm -rf "$RS"

echo "the vendor fence: a confidential or guarded repo only on a login its tenant owns (vendor-fence, F1)"
mkrepo "$T/projects/conf" "- physical: none"
# an umbrella scope sorts first: a fence that took scope_of_repo's first match would read the repo open (AGENTS.md's trap)
printf '{"repos": {}, "scopes": {"all": {"repos": ["*"]}, "conf": {"confidential": true, "repos": ["%s"]}}}\n' "$T/projects/conf" > "$T/conf.json"
cat > "$T/account-v" <<'PY'
#!/usr/bin/env python3
# bin/account's pick for a vendor: the login named, and whether the repo is its own (`owns`)
import json, os, sys
open(os.environ["STUB_ACCOUNT_CALLS"], "a").write(" ".join(sys.argv[1:]) + "\n")
if os.environ.get("STUB_PICK_NONE"):
    print(json.dumps({"account": None, "skipped": [["codex-x", "week 100%"]]})); sys.exit(3)
print(json.dumps({"account": "codex-x", "provider": sys.argv[sys.argv.index("--provider") + 1], "env": {}, "skipped": [],
                  "owns": bool(os.environ.get("STUB_OWNS"))}))
PY
chmod +x "$T/account-v"
export CLAUDE_REPOS_JSON="$T/conf.json" HARNESS_ACCOUNT="$T/account-v" STUB_ACCOUNT_CALLS="$T/account-v.calls"
: > "$STUB_CODEX_CALLS"; : > "$STUB_ORCA_CALLS"; : > "$STUB_ACCOUNT_CALLS"
HC run --harness codex --cwd "$T/projects/conf-wt" --name cf1 --prompt x > /dev/null 2>"$T/err"; check "$?" 2 "Codex in a confidential repo's worktree, the login no tenant's: refused"
has "$T/err" "$T/projects/conf is in confidential scope conf: its text goes only to a login its tenant owns, and the codex login account pick names, codex-x, is not one" \
    "  naming the scope, the rule and the login"
has "$STUB_ACCOUNT_CALLS" "pick --provider codex --repo $T/projects/conf --json --cached" "  the login is account pick's, for the vendor and the repo"
HC run --harness codex --runner orca --repo "$T/projects/conf" --name cf2 --prompt x > /dev/null 2>&1; check "$?" 2 "  codex through Orca (--runner orca): refused"
HC run --harness orca --agent codex --repo "$T/projects/conf" --name cf3 --prompt x > /dev/null 2>&1; check "$?" 2 "  an Orca codex worker: refused"
check "$(wc -c < "$STUB_CODEX_CALLS" | tr -d ' ')/$(grep -c 'worktree create' "$STUB_ORCA_CALLS")" "0/0" "  codex never ran, Orca made no worktree"
STUB_OWNS=1 STUB_CODEX_THREAD=th-own00008 HC run --harness codex --cwd "$T/projects/conf-wt" --name cf4 --prompt x > /dev/null 2>"$T/err"
check "$?" 0 "a Codex login its tenant owns: the run starts"
STUB_PICK_NONE=1 HC run --harness codex --cwd "$T/projects/conf-wt" --name cf5 --prompt x > /dev/null 2>"$T/err"; check "$?" 2 "no Codex login may run it: refused"
has "$T/err" "no codex login may run it (codex-x: week 100%)" "  with pick's reason"
check "$(python3 - "$B/harness" "$T/projects/conf-wt" <<'PY'
import importlib.machinery, importlib.util, sys
loader = importlib.machinery.SourceFileLoader("harness", sys.argv[1])
h = importlib.util.module_from_spec(importlib.util.spec_from_loader("harness", loader)); loader.exec_module(h)
out = []
for harness, req in (("claude-code", {}), ("orca", {}), ("orca", {"agent": "claude"})):
    try:
        h.guard(dict(req, cwd=sys.argv[2]), harness); out.append("ok")
    except h.Failed as e:
        out.append(str(e.code))
print(" ".join(out))
PY
)" "ok ok ok" "  a Claude run there, direct or an Orca Claude worker: its rule unchanged"
printf '{"repos": {"x": ' > "$T/torn.json"
CLAUDE_REPOS_JSON="$T/torn.json" HC run --harness codex --cwd "$CW" --name cf6 --prompt x > /dev/null 2>"$T/err"; check "$?" 2 "a torn registry: every Codex start refused (fails closed)"
has "$T/err" "the scope registry does not read" "  saying so"
printf '{"repos": {}, "guarded": ["conf"]}\n' > "$T/guarded.json"
CLAUDE_REPOS_JSON="$T/guarded.json" HC run --harness codex --cwd "$T/projects/conf-wt" --name cf7 --prompt x > /dev/null 2>"$T/err"; check "$?" 2 "a guarded repo: refused the same"
has "$T/err" "is guarded" "  named guarded"
unset CLAUDE_REPOS_JSON HARNESS_ACCOUNT STUB_ACCOUNT_CALLS

echo "the fence, live: codex sandbox under the start's permissions profile (no model call)"
if command -v codex > /dev/null 2>&1 && [ "$(uname)" = Darwin ]; then
  # a home with a key in it, and a repo under it with a worktree inside the repo
  FH="$T/fhome"; mkdir -p "$FH/.ssh" "$FH/.codex" "$T/fscratch"; echo SECRET > "$FH/.ssh/id_test"
  FR="$FH/projects/r"; git init -q -b main "$FR"; printf -- '- physical: none\n' > "$FR/AGENTS.md"
  git -C "$FR" add -A; git -C "$FR" -c user.email=t@t -c user.name=t commit -qm init
  FW="$FR/trees/w"; git -C "$FR" worktree add -q -b claude/laptop/w "$FW"
  HOME="$FH" python3 -c 'import sys, json; sys.path.insert(0, sys.argv[1]); import codex; print(json.dumps(codex.fence_profile(sys.argv[2], sys.argv[3])))' \
    "$B/harness_adapters" "$FW" "$T/fscratch" > "$T/fence.json"
  sbx() { python3 - "$T/fence.json" "$@" <<'PY'
import json, os, subprocess, sys
argv = ["codex", "sandbox"] + json.load(open(sys.argv[1])) + ["--"] + sys.argv[2:]
r = subprocess.run(argv, capture_output=True, text=True, env=dict(os.environ, HOME=os.environ["FH"], CODEX_HOME=os.environ["FH"] + "/.codex"))
print(r.returncode, (r.stdout.strip().splitlines() or [""])[-1])
PY
  }
  export FH
  check "$(sbx cat "$FH/.ssh/id_test" | cut -d' ' -f1)" 1 "  the home folder's .ssh key unreadable under the fence"
  check "$(sbx cat "$FW/AGENTS.md")" "0 - physical: none" "  the worktree readable"
  check "$(sbx git -C "$FW" rev-parse --abbrev-ref HEAD)" "0 claude/laptop/w" "  git runs in it"
  check "$(sbx touch "$FW/new" "$T/fscratch/new" | cut -d' ' -f1)/$(sbx touch "$FR/x" | cut -d' ' -f1)" "0/1" "  the worktree and the scratch dir writable, the checkout above read-only"
  check "$(HOME="$FH" CODEX_HOME="$FH/.codex" codex sandbox -- cat "$FH/.ssh/id_test" 2>/dev/null)" "SECRET" "  the control: without the profile the same read succeeds"
  unset FH
else
  echo "  skip no codex here, or not macOS (seatbelt): the live fence runs on a Mac with Codex"
fi

[ "$fails" = 0 ] && echo "test_harness: all passed" || echo "test_harness: $fails FAILED"
[ "$fails" = 0 ]
