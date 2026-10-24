#!/usr/bin/env bash
# Tests for bin/harness and its adapters. V3 status and V4 list of Claude Code: a fixture HOME with
# a registry (~/.claude/sessions/<pid>.json) whose pids are live `sleep`s with their real start
# times, transcripts, and dispatch run records — one per state mapping in the adapter's header —
# read through the real bin/dispatch-rc. A fake ssh runs the peer's half locally from stdin.
# V1 run, V2 (the next turn) and V5 stop (B5 part 2) of all three adapters against stand-ins on PATH: a
# `dispatch` that writes run records, an `orca` that answers in the shapes Orca 1.4.225 printed on
# 2026-10-14 and makes real git worktrees, a `codex` that prints `exec --json` events. No real
# agent is started. Last, on a Mac with `claude`: the real list against `claude agents --json`.
#   bash modules/wharf-runs/tests/test_harness.sh
set -u
unset CLAUDE_UNATTENDED   # an unattended /finish runs this check: the cases are an attended caller unless they say
B="$(cd "$(dirname "$0")/../bin" && pwd)"   # the module's bin/ (B7: the suites moved to tests/)
T=$(mktemp -d); T=$(cd "$T" && pwd -P)
PIDS=()
trap 'kill ${PIDS[@]+"${PIDS[@]}"} $(cat "$T/stub.pids" 2>/dev/null) 2>/dev/null; rm -rf "$T"' EXIT
fails=0
check() { if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3: expected [$2] got [$1]"; fails=$((fails+1)); fi; }
has()   { if grep -qF -- "$2" "$1"; then echo "  ok   $3"; else echo "  FAIL $3: missing [$2]"; fails=$((fails+1)); fi; }

REAL_HOME=$HOME
. "$(cd "$(dirname "$0")" && pwd)/config_fixture.sh"; fixture_config "$T/config"   # the suite's own config dir, never the login's (config_fixture.sh)
export HOME="$T/home" HARNESS_HOST=laptop
unset HARNESS_PEER_BUILDBOX HARNESS_SSH HARNESS_LAUNCHER CLAUDE_CONFIG_DIR CODEX_HOME
mkdir -p "$HOME/.claude/sessions" "$HOME/.claude/projects" "$HOME/Library/Logs/claude-weekly/run-seed-runs"
# the stand-ins (written below) answer every orca, codex and dispatch call, from the first list on:
# the real Orca app is never asked, and ELECTRON_RUN_AS_NODE=1, as a VS Code session has it, must be
# cleared before each orca call (lessons/claude-code.md)
export HARNESS_ORCA="$T/orca" STUB_ORCA_STATE="$T/orca.state" STUB_ORCA_CALLS="$T/orca.calls" STUB_ORCA_WS="$T/orca-ws" \
       HARNESS_CODEX="$T/codex" STUB_CODEX_CALLS="$T/codex.calls" HARNESS_DISPATCH="$T/dispatch" \
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
cat > "$T/codex" <<'SH'
#!/bin/sh
# codex exec --json, as OpenAI documents its events; the prompt arrives on stdin ("-")
echo "codex $*" >> "$STUB_CODEX_CALLS"
echo "stdin: $(cat)" >> "$STUB_CODEX_CALLS"
echo '{"type":"thread.started","thread_id":"'"${STUB_CODEX_THREAD:-th-000001}"'"}'
echo '{"type":"turn.started"}'
if [ -n "${STUB_CODEX_HOLD:-}" ]; then trap 'exit 143' TERM; while :; do sleep 1; done; fi
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
runs = os.path.join(os.environ["HOME"], "Library", "Logs", "claude-weekly", "run-seed-runs")
lstart = lambda pid: " ".join(subprocess.run(["ps", "-o", "lstart=", "-p", str(pid)], capture_output=True, text=True,
                                             env=dict(os.environ, TZ="UTC", LC_ALL="C")).stdout.split())
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
chmod +x "$T/orca" "$T/codex" "$T/dispatch"

# one live process per registry entry and live run: `sleep`s, so pid and start time are real
sleeper() { sleep 600 & PIDS+=($!); disown $!; }   # disowned: no "Terminated" lines at the end
for i in $(seq 1 18); do sleeper; done
DEAD=$(sh -c 'echo $$')   # a pid that has exited
P=$(printf '%s,' "${PIDS[@]}")
REPO="$T/repo"; git init -q "$REPO"; git -C "$REPO" checkout -q -b claude/laptop/2026-10-14-fixture
printf -- '- physical: none\n' > "$REPO/AGENTS.md"   # bin/harness run's rule, as dispatch's

python3 - "$HOME" "$P" "$DEAD" "$REPO" <<'PY'
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
a = lambda model, **kw: dict(type="assistant", message={"model": model, "content": []}, effort="high", **kw)
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
has "$STUB_DISPATCH_CALLS" "claude/laptop/2026-10-14-seeded --repo $(cd "$REPO" && pwd -P) --on buildbox" "  is dispatch BRANCH --repo --on, as a person types it"
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
sleeper; python3 - "$HOME" "${PIDS[${#PIDS[@]}-1]}" "$OWT" <<'PY'
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
STUB_CODEX_THREAD=th-aaaa0001 H run --harness codex --cwd "$CW" --name cx --prompt "reply DONE" --model gpt-6 --effort high --json > "$T/c.json" 2>"$T/err"
check "$?" 0 "run --harness codex exits 0"
check "$(jget "$T/c.json" '(d["harness"], d["session_id"], d["branch"])')" "('codex', 'th-aaaa0001', 'claude/laptop/2026-10-14-w')" "  the thread id read from codex's first event"
has "$STUB_CODEX_CALLS" "codex exec --json --approve-for-me -C $CW -m gpt-6 -c model_reasoning_effort=\"high\" -" "  exec --json --approve-for-me -C, model and effort, the prompt from stdin"
has "$STUB_CODEX_CALLS" "stdin: reply DONE" "  the prompt on stdin"
grep -q -- "--dangerously" "$STUB_CODEX_CALLS"; check "$?" 1 "  never --dangerously-bypass-approvals-and-sandbox"
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
H run --harness codex --cwd "$T/scratch" --prompt x > /dev/null 2>&1; check "$?" 2 "--cwd on main: refused"

echo "codex: a run still going, stopped"
STUB_CODEX_THREAD=th-bbbb0002 STUB_CODEX_HOLD=1 H run --harness codex --cwd "$CW" --name hold --prompt x --json > "$T/h.json" 2>"$T/err"
HP=$(jget "$T/h.json" 'd["pid"]')
check "$(jget "$T/h.json" 'd["state"]')/$(kill -0 "$HP" 2>/dev/null && echo alive)" "working/alive" "a live run: working, its codex alive after the call returned"
check "$(H list --harness codex --json | python3 -c 'import json,sys; print([r["session_id"] for r in json.load(sys.stdin)])')" "['th-bbbb0002']" "  listed"
H resume th-bbbb0002 --prompt x > /dev/null 2>&1; check "$?" 2 "  not continued beside itself"
H stop th-bbbb0002 --json > "$T/hst.json" 2>"$T/err"; check "$?" 0 "stop exits 0"
check "$(jget "$T/hst.json" '(d["state"], d["stop_reason"])')/$(kill -0 "$HP" 2>/dev/null && echo alive || echo gone)" \
      "('canceled', 'stopped by harness stop')/gone" "  SIGTERM after the start-time check: canceled, the process gone"

echo "codex V2: exec resume and exec fork"
: > "$STUB_CODEX_CALLS"
STUB_CODEX_THREAD=th-aaaa0001 H resume th-aaaa0001 --prompt next --json > "$T/cr.json" 2>"$T/err"; check "$?" 0 "continue an ended thread"
has "$STUB_CODEX_CALLS" "codex exec --json --approve-for-me -C $CW resume th-aaaa0001 -" "  exec resume THREAD, the prompt on stdin"
check "$(jget "$T/cr.json" '(d["session_id"], d["native"]["resumed_from"])')" "('th-aaaa0001', 'th-aaaa0001')" "  the same thread, resumed_from naming it"
cx_state th-aaaa0001 completed > /dev/null
STUB_CODEX_THREAD=th-cccc0003 H resume th-aaaa0001 --prompt again --fork --json > "$T/cf.json" 2>"$T/err"; check "$?" 0 "--fork"
has "$STUB_CODEX_CALLS" "codex exec --json --approve-for-me -C $CW fork th-aaaa0001 -" "  exec fork THREAD: headless in 0.162.1"
check "$(jget "$T/cf.json" '(d["session_id"], d["native"]["resumed_from"], d["native"]["fork"])')" "('th-cccc0003', 'th-aaaa0001', True)" "  a new thread, forked from the old"

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

echo "codex --runner orca: an Orca codex worker"
: > "$STUB_ORCA_CALLS"
H run --harness codex --runner orca --repo "$T/scratch" --name cxo --prompt x --json > "$T/cxo.json" 2>"$T/err"; check "$?" 0 "run --harness codex --runner orca"
has "$STUB_ORCA_CALLS" "--agent codex --run run_1" "  worker-start --agent codex"
check "$(jget "$T/cxo.json" '(d["harness"], d["branch"])')" "('orca', 'claude/laptop/$TODAY-cxo')" "  the record is the orca adapter's"

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
check "$(CLAUDE_UNATTENDED=dispatch python3 - "$B/harness" "$T/projects/site-wt" <<'PY'
import importlib.machinery, importlib.util, sys
loader = importlib.machinery.SourceFileLoader("harness", sys.argv[1])
h = importlib.util.module_from_spec(importlib.util.spec_from_loader("harness", loader)); loader.exec_module(h)
out = []
for harness, req in (("orca", {}), ("codex", {}), ("claude-code", {"runner": "orca"}), ("claude-code", {})):
    try:
        h.guard(dict(req, cwd=sys.argv[2]), harness); out.append("ok")
    except h.Failed as e:
        out.append(str(e.code))
print(" ".join(out))
PY
)" "2 2 2 ok" "unattended: no Orca worker or Codex run (no run cap counts them yet); claude-code through dispatch still"

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
: > "$STUB_ACCOUNT_CALLS"
(cd / && env -u HARNESS_ACCOUNT python3 "$T/copy/bin/harness" run --harness orca --repo "$T/scratch" --name acct11 --prompt x \
  --account auto > /dev/null 2>"$T/err")
check "$?" 0 "--account auto from another cwd, bin/account by the checkout ctx names"
has "$STUB_ACCOUNT_CALLS" "pick --repo $T/scratch --json" "  the checkout's own bin/account answered"
unset HARNESS_ACCOUNT STUB_ACCOUNT_CALLS HARNESS_ORCA_START_WAIT HARNESS_ORCA_OWN

[ "$fails" = 0 ] && echo "test_harness: all passed" || echo "test_harness: $fails FAILED"
[ "$fails" = 0 ]
