#!/usr/bin/env bash
# The agy road (agy-road, 2026-11-04): harness's agy adapter against a stand-in agy that checks the arguments the
# real CLI takes (the branch's probes of agy 1.4.2: the stream-json flags, --mode, --sandbox, --log-file, -p= last,
# the prompt as one NDJSON line on stdin) and exits 2 on any other, as agy's usage error does; the vendor fence on a
# confidential repo; dispatch-queue's `agy` need and `--harness` flag; dispatch-rc's count; dispatch's own refusals.
# Portable (Linux and macOS): no launchd, no real agy, no network.
#   bash modules/wharf-runs/tests/test_agy.sh
set -u
unset CLAUDE_UNATTENDED REGATTA_UNATTENDED AUTOFINISH_CALLER_UNATTENDED DISPATCH_DEPTH DISPATCH_MAX_DEPTH \
      CLAUDE_CODE_SESSION_ID CLAUDE_CODE_DISABLE_BACKGROUND_TASKS CLAUDECODE CLAUDE_CONFIG_DIR GEMINI_CLI_HOME \
      HARNESS_DISPATCHED DISPATCH_HOST
for v in $(env | sed -n 's/^\(DISPATCH_[A-Z_]*\)=.*/\1/p'); do unset "$v"; done
B="$(cd "$(dirname "$0")/../bin" && pwd)"
T=$(mktemp -d); T=$(cd "$T" && pwd -P)
trap 'kill $(cat "$T/agy.pids" 2>/dev/null) 2>/dev/null; rm -rf "$T"' EXIT
fails=0
rm_own() { local p; for p; do case "$p" in */..|*/../*|*//*) ;; "${T:?}"/?*) rm -rf -- "$p"; continue ;; esac; echo "rm_own: refused $p, outside $T" >&2; return 1; done; }
check() { if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3: expected [$2] got [$1]"; fails=$((fails+1)); fi; }
has()   { if grep -qF -- "$2" "$1"; then echo "  ok   $3"; else echo "  FAIL $3: missing [$2]"; fails=$((fails+1)); fi; }
hasnt() { if grep -qF -- "$2" "$1"; then echo "  FAIL $3: has [$2]"; fails=$((fails+1)); else echo "  ok   $3"; fi; }

. "$(cd "$(dirname "$0")" && pwd)/config_fixture.sh"; fixture_config "$T/config"
export HOME="$T/home" HARNESS_HOST=laptop
HD="$T/home"
mkdir -p "$HD/Library/Logs/claude-weekly/run-seed-runs" "$HD/.gemini/config"
# git's identity: a moved HOME drops the caller's (AGENTS.md's trap)
printf '[user]\n\tname = t\n\temail = acct-t\n[init]\n\tdefaultBranch = main\n' > "$T/gitconfig"
export GIT_CONFIG_GLOBAL="$T/gitconfig"
export HARNESS_AGY="$T/bin/agy" STUB_AGY_CALLS="$T/agy.calls" STUB_AGY_PIDS="$T/agy.pids" HARNESS_RUNS_DIR="$T/hruns" \
       HARNESS_DISPATCH="$T/dispatch" HARNESS_ACCOUNT="$T/account" STUB_ACCOUNT_CALLS="$T/account.calls" \
       HARNESS_START_WAIT=10 HARNESS_AGY_INIT_WAIT=5 HARNESS_AGY_WHO_WAIT=2 DISPATCH_RC_VENDORS=1
mkdir -p "$T/bin"

# agy, as the branch's probes saw 1.4.2: every flag the adapter passes, each value checked; anything else is
# agy's usage error (exit 2). The prompt arrives on stdin as one `user` event, after `init`.
cat > "$T/bin/agy" <<'PY'
#!/usr/bin/env python3
import json, os, signal, sys, time
a = sys.argv[1:]
open(os.environ["STUB_AGY_CALLS"], "a").write(json.dumps({"argv": a, "cwd": os.getcwd(),
    "env": {k: os.environ.get(k) for k in ("CLAUDECODE", "CLAUDE_CONFIG_DIR", "CLAUDE_CODE_SESSION_ID", "PLAN_HARNESS",
                                           "REGATTA_UNATTENDED", "HARNESS_DISPATCHED")}}) + "\n")
if a == ["--help"]:
    print("Usage: agy [options]\n  --input-format\n  --output-format\n  --mode\n  --log-file\n  --model\n  --effort\n  --conversation"
          + ("" if os.environ.get("STUB_AGY_NOSANDBOX") else "\n  --sandbox") + "\n  -p, --print")
    sys.exit(0)
VALUED = {"--input-format": ("stream-json",), "--output-format": ("stream-json",), "--mode": ("accept-edits", "auto"),
          "--log-file": None, "--model": None, "--effort": None, "--conversation": None}
seen, log, i = set(), None, 0
while i < len(a):
    f = a[i]
    if f == "-p=":
        if i != len(a) - 1:
            print("usage: -p= must come last here", file=sys.stderr); sys.exit(2)
        seen.add(f); break
    if f == "--sandbox":
        seen.add(f); i += 1; continue
    if f not in VALUED or i + 1 >= len(a) or (VALUED[f] and a[i + 1] not in VALUED[f]):
        print("usage: unknown or malformed flag %r" % f, file=sys.stderr); sys.exit(2)
    if f == "--log-file":
        log = a[i + 1]
    seen.add(f); i += 2
for need in ("--input-format", "--output-format", "--mode", "--sandbox", "--log-file", "-p="):
    if need not in seen:
        print("usage: %s missing" % need, file=sys.stderr); sys.exit(2)
open(os.environ["STUB_AGY_PIDS"], "a").write("%d\n" % os.getpid())
open(log, "a").write("OAuth: authenticated successfully as %s\n" % os.environ.get("STUB_AGY_EMAIL", "acct-a"))
def out(e):
    print(json.dumps(e), flush=True)
if os.environ.get("STUB_AGY_NOINIT"):
    time.sleep(30); sys.exit(0)
conv = os.environ.get("STUB_AGY_CONV", "conv-0001abcd")
out({"event": "init", "conversation_id": conv, "model": "gemini-x", "cwd": os.getcwd(), "permission_mode": a[a.index("--mode") + 1]})
line = sys.stdin.readline()
try:
    e = json.loads(line)
    assert e["event"] == "user" and e["message"]["role"] == "user" and isinstance(e["message"]["content"], str)
except Exception:
    print('stream input message is missing the "event" field', file=sys.stderr); sys.exit(2)
open(os.environ["STUB_AGY_CALLS"] + ".prompt", "a").write(e["message"]["content"] + "\n--\n")
def term(*_):
    out({"event": "result", "result": {"status": "ERROR", "error": "interrupted", "num_turns": 1}}); sys.exit(1)
signal.signal(signal.SIGTERM, signal.SIG_IGN if os.environ.get("STUB_AGY_IGNORE_TERM") else term)
if os.environ.get("STUB_AGY_EDIT"):
    open(os.path.join(os.getcwd(), "agy-edit.txt"), "w").write("an edit\n")
time.sleep(float(os.environ.get("STUB_AGY_SLEEP") or 0))
if os.environ.get("STUB_AGY_BADBYTE"):
    sys.stdout.flush(); sys.stdout.buffer.write(b"\xff\xfe not utf-8\n"); sys.stdout.buffer.flush()
out({"event": "step_update", "step_update": {"step_type": "agent_response", "state": "ACTIVE", "text_delta": "done: "}})
out({"event": "step_update", "step_update": {"step_type": "agent_response", "state": "DONE", "text_delta": "the brief"}})
out({"event": "result", "result": {"status": "SUCCESS", "response": "done: the brief", "num_turns": 1,
                                   "usage": {"input_tokens": 3}, "denied_actions": []}})
sys.exit(0)
PY
chmod +x "$T/bin/agy"
# bin/account's pick: checks the arguments a pick takes, names an Antigravity login, and says whether it owns the repo
cat > "$T/account" <<'PY'
#!/usr/bin/env python3
import json, os, sys
a = sys.argv[1:]
open(os.environ["STUB_ACCOUNT_CALLS"], "a").write(" ".join(a) + "\n")
if a[:1] != ["pick"] or "--provider" not in a or "--repo" not in a or "--json" not in a:
    print("account: usage", file=sys.stderr); sys.exit(2)
if a[a.index("--provider") + 1] not in ("claude", "codex", "antigravity"):
    print("account: --provider takes claude, codex or antigravity", file=sys.stderr); sys.exit(2)
if os.environ.get("STUB_PICK_NONE"):
    print(json.dumps({"account": None, "skipped": [["agy-x", "denied repo"]]})); sys.exit(3)
d = {"account": "agy-x", "provider": a[a.index("--provider") + 1], "skipped": [], "owns": bool(os.environ.get("STUB_OWNS"))}
if "--cached" not in a and os.environ.get("STUB_LIVE_UNOWNED"):
    d["owns"] = False   # the live pick named a row the cached one (the fence's) did not
if os.environ.get("STUB_PICK_EMAIL"):
    d["email"] = os.environ["STUB_PICK_EMAIL"]
print(json.dumps(d))
PY
chmod +x "$T/account"
printf '#!/bin/sh\n[ "$1" = --slots ] && { echo "${STUB_SLOTS:-0 4}"; exit 0; }\nexit 2\n' > "$T/dispatch"; chmod +x "$T/dispatch"
# the hook the entry names is there (a stand-in): the adapter refuses an entry whose vendor_hook.py is gone
mkdir -p "$T/m/lighthouse/hooks"; : > "$T/m/lighthouse/hooks/vendor_hook.py"
guards() {   # vendor-hooks' entry (plan_ag's shape), enabled unless $1 is off; $1 gone names a hook not there
  local vh="$T/m/lighthouse/hooks/vendor_hook.py"; [ "${1:-}" = gone ] && vh="$T/gone/lighthouse/hooks/vendor_hook.py"
  printf '{"regatta": {"enabled": %s, "PreToolUse": [{"matcher": "*", "hooks": [{"type": "command", "command": "python3 -c x %s antigravity guards", "timeout": 30}]}]}}\n' \
    "$([ "${1:-}" = off ] && echo false || echo true)" "$vh" > "$HD/.gemini/config/hooks.json"
}
guards
mkrepo() {   # DIR CONTRACT: a repo, and its worktree DIR/.claude/worktrees/w on a claude/* branch
  mkdir -p "$(dirname "$1")"; git init -q -b main "$1"; printf -- '%s\n' "$2" > "$1/AGENTS.md"
  git -C "$1" add AGENTS.md; git -C "$1" commit -qm init
  git -C "$1" worktree add -q -b claude/laptop/2026-11-04-w "$1/.claude/worktrees/w"
}
H() { python3 "$B/harness" "$@"; }
rec_of() { ls "$T/hruns"/agy-*-"$1"-*.json 2>/dev/null | head -1; }
ended() {   # NAME: wait for the run's record to say ended (the wrapper writes it), then its state through harness
  local i r; for i in $(seq 1 100); do r=$(rec_of "$1"); [ -n "$r" ] && grep -q '"ended"' "$r" && break; sleep 0.2; done
  H status "$1" --harness agy --json 2>/dev/null | python3 -c 'import json, sys; print(json.load(sys.stdin).get("state"))'
}
jget() { python3 -c 'import json, sys; d = json.load(open(sys.argv[1]))
for k in sys.argv[2].split("."):
    d = d.get(k) if isinstance(d, dict) else None
print(d)' "$@"; }

mkrepo "$T/projects/site" "- physical: none"
WT="$T/projects/site/.claude/worktrees/w"
echo "read the brief at $WT/docs/handoff/x.md and do what it says" > "$T/prompt"

echo "run: agy under the wrapper, recorded, ended (the stand-in checks agy's arguments)"
: > "$STUB_AGY_CALLS"; : > "$STUB_ACCOUNT_CALLS"
CLAUDECODE=1 CLAUDE_CODE_SESSION_ID=sess-parent H run --harness agy --cwd "$WT" --prompt-file "$T/prompt" --name t1 --json > "$T/out" 2>"$T/err"
check "$?" 0 "a run in a claude/* worktree starts"
check "$(jget "$T/out" harness)/$(jget "$T/out" account)" "agy/agy-x" "  its record: harness agy, the login account pick named"
check "$(ended t1)" "completed" "  and ends completed"
R=$(rec_of t1)
check "$(jget "$R" last_message)" "done: the brief" "  the reply kept"
check "$(jget "$R" thread)/$(jget "$R" mode)/$(jget "$R" sandbox)" "conv-0001abcd/accept-edits/True" "  agy's conversation id, mode accept-edits, the sandbox on"
has "$STUB_AGY_CALLS.prompt" "read the brief at $WT/docs/handoff/x.md" "  the prompt went in on stdin, as one user event"
python3 - "$STUB_AGY_CALLS" "$WT" > "$T/argv" <<'PY'
import json, sys
calls = [json.loads(l) for l in open(sys.argv[1])]
run = [c for c in calls if c["argv"] != ["--help"]][-1]
print(" ".join(run["argv"][:7]), run["argv"][-1], run["cwd"] == sys.argv[2], json.dumps(run["env"], sort_keys=True))
PY
has "$T/argv" "--input-format stream-json --output-format stream-json --mode accept-edits --sandbox -p= True" "  argv: stream-json both ways, accept-edits, --sandbox, -p= last, in the worktree"
has "$T/argv" '"CLAUDECODE": null, "CLAUDE_CODE_SESSION_ID": null, "CLAUDE_CONFIG_DIR": null' "  no Claude Code variable reaches agy"
has "$T/argv" '"PLAN_HARNESS": "agy"' "  PLAN_HARNESS says agy"
has "$STUB_ACCOUNT_CALLS" "pick --provider antigravity --repo $T/projects/site --json" "  the login is account pick's, provider antigravity, for the checkout the fence judged"
H list --harness agy --json > "$T/list" 2>/dev/null; check "$(python3 -c 'import json, sys; print(len(json.load(open(sys.argv[1]))))' "$T/list")" "0" "  an ended run is in no list"

echo "stop: a live run is listed, then ended by harness stop"
STUB_AGY_SLEEP=30 STUB_AGY_CONV=conv-0002stop H run --harness agy --cwd "$WT" --prompt x --name t2 --json > /dev/null 2>&1
check "$?" 0 "a long run starts"
H list --harness agy --json > "$T/list" 2>/dev/null
check "$(python3 -c 'import json, sys; print([r["state"] for r in json.load(open(sys.argv[1]))])' "$T/list")" "['working']" "  listed as working"
H stop conv-0002stop --harness agy --json > "$T/stop" 2>"$T/err"; check "$?" 0 "harness stop ends it"
check "$(ended t2)" "canceled" "  canceled"

echo "the login: an e-mail the pick names must be agy's own"
STUB_PICK_EMAIL=acct-b H run --harness agy --cwd "$WT" --prompt x --name t3 > /dev/null 2>"$T/err"; check "$?" 2 "agy signed in as another login: refused"
has "$T/err" "the native agy login is acct-a, not acct-b" "  naming both"
check "$(grep -c 'content' "$STUB_AGY_CALLS.prompt" 2>/dev/null || true)/$(grep -cx -- '--' "$STUB_AGY_CALLS.prompt")" "0/2" "  nothing sent (two prompts from the runs before, none from this one)"
STUB_PICK_EMAIL=acct-a H run --harness agy --cwd "$WT" --prompt x --name t4 > /dev/null 2>&1; check "$?" 0 "  the same login: the run starts"
ended t4 > /dev/null

echo "refused before agy runs (exit 2)"
: > "$STUB_AGY_CALLS"
H run --harness agy --cwd "$T/projects/site" --prompt x > /dev/null 2>"$T/err"; check "$?" 2 "the primary checkout: refused"
has "$T/err" "not a claude/* branch" "  (it is on main)"
git -C "$T/projects/site" worktree add -q -b claude/laptop/2026-11-04-out "$T/out-wt"
H run --harness agy --cwd "$T/out-wt" --prompt x > /dev/null 2>"$T/err"; check "$?" 2 "a worktree outside .claude/worktrees/: refused"
guards off
H run --harness agy --cwd "$WT" --prompt x > /dev/null 2>"$T/err"; check "$?" 2 "the guards entry disabled: refused"
has "$T/err" "disabled" "  saying so"
rm -f "$HD/.gemini/config/hooks.json"
H run --harness agy --cwd "$WT" --prompt x > /dev/null 2>"$T/err"; check "$?" 2 "no hooks.json: refused"
has "$T/err" "vendor-hooks apply" "  naming the fix"
guards gone
: > "$STUB_AGY_CALLS"
H run --harness agy --cwd "$WT" --prompt x > /dev/null 2>"$T/err"; check "$?" 2 "an entry naming a vendor_hook.py that is gone: refused (vendor-hooks' launcher would allow every call)"
has "$T/err" "$T/gone/lighthouse/hooks/vendor_hook.py, which is gone" "  naming the path"
check "$(grep -c '"-p="' "$STUB_AGY_CALLS")" "0" "  and agy never ran"
guards
STUB_AGY_NOSANDBOX=1 H run --harness agy --cwd "$WT" --prompt x > /dev/null 2>"$T/err"; check "$?" 2 "an agy without --sandbox: refused"
python3 -c 'print("x" * 170000)' > "$T/big"
H run --harness agy --cwd "$WT" --prompt-file "$T/big" > /dev/null 2>"$T/err"; check "$?" 2 "a prompt over the cap: refused"
has "$T/err" "hand agy its brief by path" "  naming the trap"
echo bogus > "$T/config/wharf-runs/agy-mode"
H run --harness agy --cwd "$WT" --prompt x > /dev/null 2>"$T/err"; check "$?" 2 "an agy-mode that is no mode: refused"
echo auto > "$T/config/wharf-runs/agy-mode"
H run --harness agy --cwd "$WT" --prompt x --name t5 > /dev/null 2>&1; check "$?" 0 "agy-mode auto: the run starts"
ended t5 > /dev/null
has "$STUB_AGY_CALLS" '"--mode", "auto"' "  under --mode auto"
rm -f "$T/config/wharf-runs/agy-mode"; : > "$STUB_AGY_CALLS"
H run --harness agy --runner orca --cwd "$WT" --prompt x > /dev/null 2>"$T/err"; check "$?" 2 "--runner orca: refused"
H run --harness agy --account other --cwd "$WT" --prompt x > /dev/null 2>&1; check "$?" 2 "--account LABEL: refused"
echo site > "$T/config/wharf-runs/public-repos"
H run --harness agy --cwd "$WT" --prompt x > /dev/null 2>"$T/err"; check "$?" 2 "a public repo: refused"
has "$T/err" "agy does not run in" "  in the public-repo rule's words"
rm -f "$T/config/wharf-runs/public-repos"
mkrepo "$T/live" "- physical: a sweep"
H run --harness agy --cwd "$T/live/.claude/worktrees/w" --prompt x > /dev/null 2>"$T/err"; check "$?" 2 "a repo not physical: none: refused"
STUB_SLOTS="4 4" H run --harness agy --cwd "$WT" --prompt x > /dev/null 2>"$T/err"; check "$?" 2 "the run cap full: refused"
STUB_PICK_NONE=1 H run --harness agy --cwd "$WT" --prompt x > /dev/null 2>"$T/err"; check "$?" 2 "no Antigravity login may run it: refused"
has "$T/err" "agy-x: denied repo" "  with the pick's reason"
check "$(grep -vc '"--help"' "$STUB_AGY_CALLS")" "0" "  agy itself never ran for any of them"

echo "the wrapper: a byte agy prints that is no UTF-8 neither ends the loop nor loses the end"
STUB_AGY_BADBYTE=1 H run --harness agy --cwd "$WT" --prompt x --name t9 > /dev/null 2>&1; check "$?" 0 "the run starts"
check "$(ended t9)" "completed" "  and ends completed, its end written"

echo "the cap dispatch counted: HARNESS_SLOTS beside HARNESS_DISPATCHED stands for harness's own --slots read"
STUB_SLOTS="4 4" HARNESS_DISPATCHED="$T/disp.json" HARNESS_SLOTS="0 1" H run --harness agy --cwd "$WT" --prompt x --name t10 > /dev/null 2>&1
check "$?" 0 "dispatch's count (0 of 1) is the one judged, not a --slots read that holds its own claim"
ended t10 > /dev/null
STUB_SLOTS="0 4" HARNESS_DISPATCHED="$T/disp.json" HARNESS_SLOTS="1 1" H run --harness agy --cwd "$WT" --prompt x > /dev/null 2>"$T/err"
check "$?" 2 "  and a full count still refuses"
has "$T/err" "the next step waits for a run to end" "  in the cap's waiting words"
STUB_SLOTS="4 4" HARNESS_SLOTS="0 1" H run --harness agy --cwd "$WT" --prompt x > /dev/null 2>&1
check "$?" 2 "  HARNESS_SLOTS without HARNESS_DISPATCHED is no count: --slots decides"

echo "the vendor fence: a confidential repo only on a login its tenant owns"
mkrepo "$T/projects/conf" "- physical: none"
printf '{"repos": {}, "scopes": {"all": {"repos": ["*"]}, "conf": {"confidential": true, "repos": ["%s"]}}}\n' "$T/projects/conf" > "$T/conf.json"
export CLAUDE_REPOS_JSON="$T/conf.json"; : > "$STUB_ACCOUNT_CALLS"; : > "$STUB_AGY_CALLS"
REGATTA_ACCOUNT="$T/account" H run --harness agy --cwd "$T/projects/conf/.claude/worktrees/w" --prompt x > /dev/null 2>"$T/err"
check "$?" 2 "a confidential repo, the login no tenant's: refused"
has "$T/err" "its text goes only to a login its tenant owns, and the antigravity login account pick names, agy-x, is not one" "  in the vendor fence's words"
has "$STUB_ACCOUNT_CALLS" "pick --provider antigravity --repo $T/projects/conf --json --cached" "  judged by account pick, provider antigravity"
check "$(grep -vc '"--help"' "$STUB_AGY_CALLS")" "0" "  agy never ran"
STUB_OWNS=1 REGATTA_ACCOUNT="$T/account" H run --harness agy --cwd "$T/projects/conf/.claude/worktrees/w" --prompt x --name t6 > /dev/null 2>"$T/err"
check "$?" 0 "a login its tenant owns: the run starts"
ended t6 > /dev/null
: > "$STUB_AGY_CALLS"
STUB_OWNS=1 STUB_LIVE_UNOWNED=1 REGATTA_ACCOUNT="$T/account" H run --harness agy --cwd "$T/projects/conf/.claude/worktrees/w" --prompt x > /dev/null 2>"$T/err"
check "$?" 2 "the fence's cached pick owns it, the live pick names a login no tenant's: refused (the finish review)"
has "$T/err" "the live pick names agy-x, not one" "  saying the live pick is held to the fence's rule"
has "$T/err" "is in confidential scope" "  in the core's words, which dispatch's agy road reads as refused for good"
check "$(grep -vc '"--help"' "$STUB_AGY_CALLS")" "0" "  agy never ran"
unset CLAUDE_REPOS_JSON

echo "dispatch-rc's run count: a live agy run holds a slot, once"
STUB_AGY_SLEEP=30 STUB_AGY_CONV=conv-0007count H run --harness agy --cwd "$WT" --prompt x --name t7 > /dev/null 2>&1
echo '{}' > "$T/a-dispatch-record.json"
STUB_AGY_SLEEP=30 STUB_AGY_CONV=conv-0008disp HARNESS_DISPATCHED="$T/a-dispatch-record.json" H run --harness agy --cwd "$WT" --prompt x --name t8 > /dev/null 2>&1
check "$(python3 - "$B/dispatch-rc" <<'PY'
import importlib.machinery, importlib.util, sys
ld = importlib.machinery.SourceFileLoader("drc", sys.argv[1])
m = importlib.util.module_from_spec(importlib.util.spec_from_loader("drc", ld)); ld.exec_module(m)
print(m.vendor_slots())
PY
)" "1" "the harness's own agy run counts; one dispatch started counts by dispatch's record only"
echo '{"ended": 1}' > "$T/a-dispatch-record.json"
check "$(python3 - "$B/dispatch-rc" <<'PY'
import importlib.machinery, importlib.util, sys
ld = importlib.machinery.SourceFileLoader("drc", sys.argv[1])
m = importlib.util.module_from_spec(importlib.util.spec_from_loader("drc", ld)); ld.exec_module(m)
print(m.vendor_slots())
PY
)" "2" "  once dispatch's record has ended (a stop that failed), the live agy counts here again (the finish review)"
H stop conv-0007count --harness agy > /dev/null 2>&1; H stop conv-0008disp --harness agy > /dev/null 2>&1

echo "dispatch-queue: the agy need, and --harness agy as a carried flag"
mkdir -p "$T/noagy"
python3 - "$B/dispatch-queue" "$T" > "$T/q" 2>&1 <<'PY'
import importlib.machinery, importlib.util, os, sys
ld = importlib.machinery.SourceFileLoader("dq", sys.argv[1])
q = importlib.util.module_from_spec(importlib.util.spec_from_loader("dq", ld)); ld.exec_module(q)
T = sys.argv[2]
os.environ.pop("HARNESS_AGY", None); os.environ["PATH"] = T + "/noagy:/usr/bin:/bin"; os.environ["DISPATCH_HOST"] = "laptop"
e = {"repo": T + "/projects/site", "branch": "claude/laptop/2026-11-04-w", "needs": ["agy"],
     "args": ["--needs", "agy", "--harness", "agy"]}
print("no-agy:", q.eligibility(e, "laptop", feats={}))
print("peer:", q.eligibility(e, "buildbox", feats={}))
print("line-noagy:", q.eligibility(e, "laptop", feats={"laptop": {"agy"}}))
print("peer-line:", q.eligibility(e, "buildbox", feats={"buildbox": {"agy"}}))
LB = os.path.join(os.environ["HOME"], ".local", "bin")
os.makedirs(LB, exist_ok=True)
os.symlink(T + "/bin/agy", os.path.join(LB, "agy")); q._AGY.clear()   # agy_here reads once per process
print("local-bin:", q.eligibility(e, "laptop", feats={"laptop": {"agy"}}))
print("installed-no-line:", q.eligibility(e, "laptop", feats={}))
print("installed-finish-line:", q.eligibility(e, "laptop", feats={"laptop": {"finish-queue"}}))
q._AGY.clear(); HJ = os.path.join(os.environ["HOME"], ".gemini", "config", "hooks.json")
os.rename(HJ, T + "/hooks.away")
print("no-guards:", q.eligibility(e, "laptop", feats={"laptop": {"agy"}}))
os.rename(T + "/hooks.away", HJ); q._AGY.clear()
good = open(HJ).read(); open(HJ, "w").write(good.replace("/m/lighthouse/", "/gone/lighthouse/"))
print("gone-guards:", q.eligibility(e, "laptop", feats={"laptop": {"agy"}}))
open(HJ, "w").write(good); q._AGY.clear()
import json as _j
c = _j.loads(good); c["regatta"]["PreToolUse"][0]["matcher"] = "run_command"; open(HJ, "w").write(_j.dumps(c))
print("narrow-matcher:", q.eligibility(e, "laptop", feats={"laptop": {"agy"}}))
open(HJ, "w").write(good); q._AGY.clear()
ld2 = importlib.machinery.SourceFileLoader("ag", os.path.join(os.path.dirname(sys.argv[1]), "harness_adapters", "agy.py"))
ag = importlib.util.module_from_spec(importlib.util.spec_from_loader("ag", ld2)); ld2.exec_module(ag)
ag._pstart = lambda pid: None
print("blank-ps:", ag._running({"pid": os.getpid(), "proc_start": "Thu Nov  5 00:00:00 2026"}))
print("bad-none:", q.bad_args(e))
print("bad-noneed:", q.bad_args(dict(e, needs=[], args=["--harness", "agy"])))
print("bad-claude:", q.bad_args(dict(e, args=["--needs", "agy", "--harness", "claude"])))
print("finish:", q.builtin_met(q.FINISH_NEED, "laptop") == (sys.platform == "darwin"), q.builtin_met(q.FINISH_NEED, "buildbox"))
PY
has "$T/q" "no-agy: laptop has no feature line, so lacks agy" "a host without agy never claims the entry"
has "$T/q" "peer: buildbox has no feature line, so lacks agy" "  a peer meets it only by its feature line (a builder host's; the owner's D1)"
has "$T/q" "line-noagy: laptop declares agy, but no agy here the adapter would run" "  a line naming agy on a host with no agy meets none"
has "$T/q" "peer-line: None" "  a peer's line naming agy meets it (its own agy judged on its own claim)"
has "$T/q" "local-bin: None" "  a line and an agy in the home folder's .local/bin meet it (Linux's install path)"
has "$T/q" "installed-no-line: laptop has no feature line, so lacks agy" "  an agy installed with no line meets none: the owner's Macs run agy for the council, never a build (D1)"
has "$T/q" "installed-finish-line: laptop lacks agy" "  nor a line that names other features"
has "$T/q" "no-guards: laptop declares agy, but no agy here" "  an agy the adapter would refuse (no guards entry) meets none"
has "$T/q" "gone-guards: laptop declares agy, but no agy here" "  nor one whose guards entry names a vendor_hook.py that is gone"
has "$T/q" "narrow-matcher: laptop declares agy, but no agy here" "  nor one whose guards group's matcher narrows it to some tools (the finish review)"
has "$T/q" "blank-ps: True" "  a live pid whose start ps does not print reads as agy still (dispatch-rc's rule)"
has "$T/q" "bad-none: None" "  --harness agy with the need: a flag an entry may carry"
has "$T/q" "bad-noneed: --harness agy without the agy need" "  without the need: refused"
has "$T/q" "bad-claude: --harness 'claude' does not match its pattern" "  only agy rides as a harness"
has "$T/q" "finish: True True" "  the finish need's rule unchanged"

echo "dispatch: --harness's refusals (exit 2, before anything is queued)"
printf '#!/bin/sh\nexit 0\n' > "$T/launchctl"; chmod +x "$T/launchctl"   # no job reaches the real launcher
D() { DISPATCH_LAUNCHCTL="$T/launchctl" DISPATCH_DEFAULT_ON="" bash "$B/dispatch" "$@"; }
D claude/laptop/2026-11-04-w --repo "$T/projects/site" --harness bogus --dry-run > /dev/null 2>"$T/err"; check "$?" 2 "--harness bogus: refused"
has "$T/err" "--harness takes claude or agy" "  naming the two"
D claude/laptop/2026-11-04-w --repo "$T/projects/site" --harness agy --harness agy --dry-run > /dev/null 2>&1; check "$?" 2 "--harness twice: refused"
D claude/laptop/2026-11-04-w --repo "$T/projects/site" --harness claude --harness agy --dry-run > /dev/null 2>&1; check "$?" 2 "  claude, then agy: refused too"
for f in --yolo --headless --probe --if-room; do
  D claude/laptop/2026-11-04-w --repo "$T/projects/site" --harness agy $f --dry-run > /dev/null 2>"$T/err"; check "$?" 2 "--harness agy $f: refused"
done
D claude/laptop/2026-11-04-w --repo "$T/projects/site" --harness agy --account acct-b --dry-run > /dev/null 2>"$T/err"; check "$?" 2 "--harness agy --account LABEL: refused"
has "$T/err" "agy's login is account pick --provider antigravity's" "  saying whose login it is"
DISPATCH_MODE=dnd DISPATCH_LABEL=org.example.claude.dispatch.site.w D claude/laptop/2026-11-04-w --repo "$T/projects/site" --harness agy --dry-run > "$T/out" 2>"$T/err"
has "$T/out" "DRY RUN: would" "an agy job carrying a dnd (a dnd run's --next, its plist): its dry run reads"
hasnt "$T/out" "mode dnd" "an inherited dnd (a dnd run's --next) never rides on an agy entry: no landing follows (the finish review)"
D claude/laptop/2026-11-04-w --repo "$T/projects/site" --harness agy --mode dnd --dry-run > /dev/null 2>"$T/err"; check "$?" 2 "--harness agy --mode dnd: refused (no landing follows an agy build)"

echo "dispatch's agy road: a fired job runs agy through harness in the branch's worktree, records it and ends"
HN=$(python3 "$B/dispatch-queue" agy-host 2>/dev/null | awk '{print $1}')   # this host's name, as the rule reads it
check "$([ -n "$HN" ] && echo named)" "named" "  agy-host names this host while it declares no agy"
# a seeded branch on an origin; the job fired as launchd fires it (DISPATCH_LABEL), here with no queue home and a
# stand-in launchctl: the one-shot road, whose fire path is the queue's claim's too
git init -q --bare "$T/origin.git"
git clone -q "$T/origin.git" "$T/projects/road" 2>/dev/null
printf -- '- physical: none\n' > "$T/projects/road/AGENTS.md"; git -C "$T/projects/road" add AGENTS.md
git -C "$T/projects/road" commit -qm init; git -C "$T/projects/road" push -q origin main 2>/dev/null
git -C "$T/projects/road" checkout -q -b claude/laptop/2026-11-04-ar
mkdir -p "$T/projects/road/docs/handoff"; echo "# ar — build it" > "$T/projects/road/docs/handoff/2026-11-04-ar.md"
git -C "$T/projects/road" add docs; git -C "$T/projects/road" commit -qm "Seed: ar"
git -C "$T/projects/road" push -q origin claude/laptop/2026-11-04-ar 2>/dev/null; git -C "$T/projects/road" checkout -q main
: > "$STUB_AGY_CALLS"
DISPATCH_LAUNCHCTL="$T/launchctl" DISPATCH_LABEL=org.example.claude.dispatch.road.ar DISPATCH_DEFAULT_ON="" DISPATCH_AGY_POLL=1 \
  bash "$B/dispatch" claude/laptop/2026-11-04-ar --repo "$T/projects/road" --harness agy > "$T/fire.out" 2>&1
check "$?" 2 "a host whose features line names no agy: refused, though agy is installed (the owner's D1: a builder host only)"
has "$T/fire.out" "runs only on a builder host: $HN declares no agy feature" "  naming the rule"
hasnt "$STUB_AGY_CALLS" "-p" "  agy never started"
sed -n '/^agy_road() {$/,/^}$/p' "$B/dispatch" | grep -q 'FAILED: refused for good, $hwhy' \
  && check ok ok "  the fire path rechecks it (a claim judged it; a one-shot did not)" || check missing ok "  the fire path rechecks it"
mkdir -p "$T/config/wharf-runs"; echo "$HN:agy" > "$T/config/wharf-runs/features"   # this host a builder's from here on
: > "$STUB_AGY_CALLS"; rm -f "$STUB_AGY_CALLS.prompt"
STUB_AGY_EDIT=1 DISPATCH_LAUNCHCTL="$T/launchctl" DISPATCH_LABEL=org.example.claude.dispatch.road.ar DISPATCH_DEFAULT_ON="" \
  DISPATCH_AGY_POLL=1 bash "$B/dispatch" claude/laptop/2026-11-04-ar --repo "$T/projects/road" --harness agy > "$T/fire.out" 2>&1
check "$?" 0 "the fired job ends"
LOG=$(ls -t "$HD"/Library/Logs/claude-weekly/run-seed*/*ar*.log "$HD"/Library/Logs/claude-weekly/*ar*.log 2>/dev/null | head -1)
[ -n "$LOG" ] || { LOG="$T/fire.out"; echo "  (no run log found; the job's own output stands in)"; }
has "$LOG" "== started (agy):" "  agy started through harness"
has "$LOG" "== exit 0" "  and ended with agy's exit"
has "$LOG" "agy left 1 changed path(s) uncommitted" "  its edits left in the worktree for the owner's session"
hasnt "$LOG" "FAILED" "  no refusal on the way"
has "$STUB_AGY_CALLS.prompt" "Read the brief at $T/projects/road/.claude/worktrees/ar/docs/handoff/2026-11-04-ar.md" "  the prompt names the brief by path"
ST=$(ls -t "$HD"/Library/Logs/claude-weekly/run-seed-runs/*road.ar.*.json 2>/dev/null | head -1)
check "$( [ -n "$ST" ] && python3 -c 'import json, sys; s = json.load(open(sys.argv[1])); print(s.get("mode"), s.get("agent"), s.get("exit"), bool(s.get("ended")), s.get("agy_account"), str(s.get("harness_run", "")).endswith(".json"), isinstance(s.get("pid"), int) and bool(s.get("proc_start")))' "$ST")" \
  "agy agy 0 True agy-x True True" "  dispatch's run record: mode and agent agy, its exit, ended, the login, the harness record, agy's pid and start"
check "$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1])).get("dispatched") == sys.argv[2])' "$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["harness_run"])' "$ST")" "$ST")" "True" \
  "  the harness record names dispatch's, which holds the slot"
check "$(python3 -c 'import json, sys; r = json.load(open(json.load(open(sys.argv[1]))["harness_run"])); print(isinstance(r.get("wrapper"), int) and bool(r.get("wrapper_start")))' "$ST")" "True" \
  "  the harness record keeps its wrapper's start beside its pid, so a reused pid never keeps it alive (the finish review)"

fire() {   # a fired job of the road branch, its log's bytes from here on in $T/fire.log
  local n0=0; [ -f "$LOG" ] && n0=$(wc -c < "$LOG" | tr -d ' ')
  DISPATCH_LAUNCHCTL="$T/launchctl" DISPATCH_LABEL=org.example.claude.dispatch.road.ar DISPATCH_DEFAULT_ON="" DISPATCH_AGY_POLL=1 \
    bash "$B/dispatch" claude/laptop/2026-11-04-ar --repo "$T/projects/road" --harness agy "$@" > /dev/null 2>&1
  local rc=$?; tail -c +$((n0 + 1)) "$LOG" > "$T/fire.log"; return $rc
}
echo "dispatch: a brief of a principal tier is refused before it queues (the finish review)"
git -C "$T/projects/road" checkout -q -b claude/laptop/2026-11-04-pt
mkdir -p "$T/projects/road/docs/handoff"; printf '# pt\nTier: principal-worker\n' > "$T/projects/road/docs/handoff/2026-11-04-pt.md"
git -C "$T/projects/road" add docs; git -C "$T/projects/road" commit -qm "Seed: pt"; git -C "$T/projects/road" checkout -q main
D claude/laptop/2026-11-04-pt --repo "$T/projects/road" --harness agy --dry-run > /dev/null 2>"$T/err"; check "$?" 2 "--harness agy on a principal brief: refused"
has "$T/err" "builds no principal tier" "  saying a principal tier runs Claude"
echo "dispatch's agy road: the last step a chain allows still runs (harness judges its caller's depth)"
DISPATCH_DEPTH=5 DISPATCH_MAX_DEPTH=5 fire
has "$T/fire.log" "== exit 0" "a run at depth 5 of 5 starts and ends"
hasnt "$T/fire.log" "DISPATCH_MAX_DEPTH" "  no depth refusal"
echo "dispatch's agy road: what harness refused decides the end"
rm -f "$HD/.gemini/config/hooks.json"
fire
has "$T/fire.log" "FAILED: agy did not start on" "no guards entry here: this host's own refusal, never 'for good'"
hasnt "$T/fire.log" "refused for good" "  so a host that can run it may still"
guards
echo road > "$T/config/wharf-runs/public-repos"
fire
has "$T/fire.log" "FAILED: agy refused for good" "a public repo: refused for good"
rm -f "$T/config/wharf-runs/public-repos"
# the tenant's fence: for good for a confidential scope (its entry no other host claims), this host's own otherwise
# (a guarded repo's answer is this host's agy login, round 3's item 4)
printf '#!/bin/sh\necho "harness: /r/road is guarded: its text goes only to a login its tenant owns, and the antigravity login account pick names, agy-x, is not one" >&2\nexit 2\n' > "$T/harness-guarded"
printf '#!/bin/sh\necho "harness: /r/road is in confidential scope conf: its text goes only to a login its tenant owns, and the antigravity login account pick names, agy-x, is not one" >&2\nexit 2\n' > "$T/harness-conf"
chmod +x "$T/harness-guarded" "$T/harness-conf"
HARNESS_BIN="$T/harness-guarded" fire
has "$T/fire.log" "FAILED: agy did not start on" "a guarded repo on a login its tenant does not own: this host's refusal"
hasnt "$T/fire.log" "refused for good" "  never for good: another host's agy login may be the tenant's"
HARNESS_BIN="$T/harness-conf" fire
has "$T/fire.log" "FAILED: agy refused for good" "  a confidential scope's: refused for good"
check "$(ls "$HD"/Library/Logs/claude-weekly/run-seed-runs/ | grep -c 'harness-err$')" "0" "  harness's stderr goes to the run log, and its file no further"
has "$T/fire.log" "harness: /r/road is in confidential scope conf" "  (its words in the log)"
echo "dispatch's agy road: a torn registry's ask is this run's alone, no DISPATCH_MODE for agy (the build review)"
printf '#!/bin/sh\necho "DISPATCH_MODE=${DISPATCH_MODE-unset}" > "%s"\necho "harness: the scope registry does not read" >&2\nexit 2\n' "$T/mode.seen" > "$T/harness-mode"
chmod +x "$T/harness-mode"; rm -f "$T/mode.seen"
# a torn registry at fire time meets the spawn gate first (it fails closed), so a tear between it and the mode read
# is a race no case makes: the road's own rule, as resolve_mode's for a Claude run's chain, is read from its text
sed -n '/^agy_road() {$/,/^}$/p' "$B/dispatch" > "$T/agy_road.sh"
check "$(grep -c '\[ "\$mode_torn" = 1 \] || menv=(DISPATCH_MODE="\$mode")' "$T/agy_road.sh") $(grep -c 'DISPATCH_MODE="\$mode" ' "$T/agy_road.sh")" "1 0" \
  "a torn mode read puts no DISPATCH_MODE on agy's env (resolve_mode's rule), only menv does"
HARNESS_BIN="$T/harness-mode" fire
check "$(cat "$T/mode.seen" 2>/dev/null)" "DISPATCH_MODE=default" "  a registry that reads: agy gets the mode that runs"
echo "dispatch's agy road: a fired job its own arguments refuse hands back its plist (round 3's item 2)"
mkdir -p "$HD/Library/LaunchAgents"; : > "$HD/Library/LaunchAgents/org.example.claude.dispatch.road.ar.plist"
printf '#!/bin/sh\necho "$*" >> "%s"\nexit 0\n' "$T/lc.calls" > "$T/launchctl"; : > "$T/lc.calls"
fire --account acct-b; check "$?" 2 "a fired agy job carrying --account: refused"
check "$([ -e "$HD/Library/LaunchAgents/org.example.claude.dispatch.road.ar.plist" ] && echo left || echo gone)" "gone" "  its plist removed"
has "$T/lc.calls" "bootout gui/" "  and its job booted out"
printf '#!/bin/sh\nexit 0\n' > "$T/launchctl"
echo "dispatch's agy road: agy and its wrapper gone with no end recorded end the run here"
cat > "$T/harness-gone" <<'SH'
#!/bin/sh
# harness run's answer for a run whose wrapper died at once: a record with a dead pid and no end
r="$HARNESS_RUNS_DIR/agy-gone-ar-000000.json"
printf '{"run": "agy-run-000000000000", "pid": DEADPID, "proc_start": "Thu Jan  1 00:00:00 1970", "wrapper": DEADPID}\n' > "$r"
printf '{"harness": "agy", "native": {"run": "%s"}}\n' "$r"
SH
# a pid known dead, never a fixed number a busy Linux box may have live (pid_max 4194304: the finish review)
sleep 0 & deadpid=$!; wait "$deadpid"
sed "s/DEADPID/$deadpid/g" "$T/harness-gone" > "$T/harness-gone.new" && mv "$T/harness-gone.new" "$T/harness-gone"
chmod +x "$T/harness-gone"
HARNESS_BIN="$T/harness-gone" fire
has "$T/fire.log" "agy and its wrapper are gone with no end recorded" "a dead wrapper ends the run within two polls"
has "$T/fire.log" "== exit 1" "  failed"
echo "dispatch's agy road: past DISPATCH_MAX_H the run is ended only once agy no longer runs (the build review, round 2)"
: > "$STUB_AGY_PIDS"
STUB_AGY_SLEEP=60 STUB_AGY_IGNORE_TERM=1 HARNESS_START_WAIT=1 DISPATCH_MAX_H=0.0003 DISPATCH_AGY_GRACE=2 fire
apid=$(tail -1 "$STUB_AGY_PIDS")
has "$T/fire.log" "ending agy: still running after" "an agy past its cap is stopped…"
has "$T/fire.log" "outlived its stop by 2 s: SIGKILL" "  …and, deaf to the SIGTERM, killed once the grace is spent"
has "$T/fire.log" "== exit 143" "  the cap's exit"
check "$( [ -n "$apid" ] && kill -0 "$apid" 2>/dev/null && echo alive || echo dead)" "dead" "  agy no longer runs when the record is ended"
hasnt "$T/fire.log" "agy may still run" "  never ended with agy unseen to end"
echo "  …and a start ps could not read for a live agy is read again, never taken for an end (the build review, round 3)"
# a ps that prints no lstart while $T/ps-blank exists (a loaded Mac), armed when harness stop returns and cleared
# once the run's log shows the re-read (12 s at most: a clock window raced the grace check under load), so the
# grace check meets the blank read, and the kill must still come once ps reads again
mkdir -p "$T/psbin"; realps=$(command -v ps)
printf '#!/bin/sh\ncase " $* " in *" lstart= "*) [ -e "%s" ] && exit 0;; esac\nexec "%s" "$@"\n' "$T/ps-blank" "$realps" > "$T/psbin/ps"
printf '#!/bin/sh\n"%s" "$@"; rc=$?\n[ "$1" = stop ] && { : > "%s"; ( i=0; while [ $i -lt 60 ] && ! grep -q "ps printed no start" "%s"; do sleep 0.2; i=$((i + 1)); done; rm -f "%s" ) > /dev/null 2>&1 & }\nexit $rc\n' \
  "$B/harness" "$T/ps-blank" "$LOG" "$T/ps-blank" > "$T/harness-blank"
chmod +x "$T/psbin/ps" "$T/harness-blank"; : > "$STUB_AGY_PIDS"; rm -f "$T/ps-blank"
PATH="$T/psbin:$PATH" HARNESS_BIN="$T/harness-blank" STUB_AGY_SLEEP=60 STUB_AGY_IGNORE_TERM=1 HARNESS_START_WAIT=1 \
  DISPATCH_MAX_H=0.0003 DISPATCH_AGY_GRACE=2 fire
apid=$(tail -1 "$STUB_AGY_PIDS")
has "$T/fire.log" "ps printed no start for agy's live pid" "  a blank start read at the grace check…"
has "$T/fire.log" "outlived its stop by 2 s: SIGKILL" "  …waits for the next poll, then the kill"
hasnt "$T/fire.log" "agy may still run" "  never ended on one blank read"
check "$( [ -n "$apid" ] && kill -0 "$apid" 2>/dev/null && echo alive || echo dead)" "dead" "  agy no longer runs when the record is ended"
rm -f "$T/ps-blank"
cat > "$T/same.py" <<'PY'
import importlib.machinery, importlib.util, os, sys
ld = importlib.machinery.SourceFileLoader("drc", sys.argv[1])
m = importlib.util.module_from_spec(importlib.util.spec_from_loader("drc", ld)); ld.exec_module(m)
print(m.same({"mode": "agy", "pid": os.getpid()}), m.same({"mode": "agy", "pid": os.getpid(), "proc_start": "Thu Jan  1 00:00:00 1970"}))
PY
check "$(python3 "$T/same.py" "$B/dispatch-rc")" "True False" \
  "dispatch-rc: a live agy record whose start ps could not read still holds its slot, as a headless one does"
echo "dispatch --status reads a live agy record"
STUB_AGY_SLEEP=30 STUB_AGY_CONV=conv-0011stat HARNESS_DISPATCHED=x H run --harness agy --cwd "$WT" --prompt x --name t11 > /dev/null 2>&1
R11=$(rec_of t11)
python3 - "$R11" "$HD/Library/Logs/claude-weekly/run-seed-runs/20261104-000000-site.t11.00000000.json" <<'PY'
import json, sys
r = json.load(open(sys.argv[1]))
json.dump({"mode": "agy", "harness": "agy", "topic": "t11", "repo": "/x/site", "branch": "claude/laptop/2026-11-04-t11",
           "session": "00000000-0000", "pid": r["pid"], "proc_start": r["proc_start"], "started": int(r["started"]),
           "harness_run": sys.argv[1], "log": "/x/log"}, open(sys.argv[2], "w"))
PY
DISPATCH_RC_VENDORS=0 python3 "$B/dispatch-rc" status > "$T/status" 2>&1; check "$?" 0 "dispatch-rc status passes it"
has "$T/status" "agy (harness run --harness agy): record $R11" "  naming its harness record"
H stop conv-0011stat --harness agy > /dev/null 2>&1
echo "helm's stalls: an ended agy build is a card, raised, never retried as a Claude build"
python3 - "$B/../../helm/bin" <<'PY' > "$T/stall" 2>&1
import sys, time
sys.path.insert(0, sys.argv[1])
import stalls
now = time.time()
for rc in ("1", "143", "0"):
    st = {"mode": "agy", "harness": "agy", "agent": "agy", "branch": "claude/laptop/2026-11-04-x", "repo": "/r/site",
          "topic": "x", "session": "u-1", "started": now - 4000, "ended": now - 3000, "end_reason": "exit " + rc,
          "exit": int(rc), "depth": 1, "wt": "/r/site/.claude/worktrees/x"}
    view = {"raw": {"n.json": st}, "records": {"n.json": {"branch": True, "alive": False, "status": {}}}}
    s, u = stalls.judge_runs("laptop", view, [("laptop", "n.json", st)], set(), set(), now)
    print(rc, [(x["class"], x["action"]) for x in s], len(u))
    print("title", rc, stalls.title(s[0], now))
live = dict(st, ended=None, end_reason=None)
view = {"raw": {"n.json": live}, "records": {"n.json": {"branch": True, "alive": True, "watcher": True, "status": {}}}}
print("live", stalls.judge_runs("laptop", view, [("laptop", "n.json", live)], set(), set(), now))
view = {"raw": {"n.json": live}, "records": {"n.json": {"branch": True, "alive": False, "watcher": False, "status": {}}}}
s, u = stalls.judge_runs("laptop", view, [("laptop", "n.json", live)], set(), set(), now)
print("gone", [(x["class"], x["action"], x["rule"]) for x in s], len(u))
print("title gone", stalls.title(s[0], now))
PY
has "$T/stall" "1 [('S1', 'raise')] 0" "an agy build that exited 1: S1, raised"
has "$T/stall" "143 [('S1', 'raise')] 0" "  stopped at the cap (143): the same"
has "$T/stall" "0 [('S1', 'raise')] 0" "  exited 0: a card too, its edits wait for the owner"
has "$T/stall" "live ([], [])" "  a live one: nothing"
has "$T/stall" "gone [('S1', 'raise', 'agy build gone without an end')] 0" "  gone with no end (agy and its watcher dead): a card, raised"
has "$T/stall" "title 0 x · S1 ended 50m ago, its edits wait" "  an ended build's card reads as a hand-over, never 'gone' (round 3's item 3)"
has "$T/stall" "title gone x · S1 gone " "  one gone with no end still reads 'gone'"

echo "the requeue of an agy record with no entry stays an agy build"
python3 - "$B/dispatch-queue" "$T" > "$T/eor" 2>&1 <<'PY'
import importlib.machinery, importlib.util, os, sys
ld = importlib.machinery.SourceFileLoader("dq", sys.argv[1])
q = importlib.util.module_from_spec(importlib.util.spec_from_loader("dq", ld)); ld.exec_module(q)
st = {"mode": "agy", "harness": "agy", "repo": sys.argv[2] + "/projects/site", "branch": "claude/laptop/2026-11-04-w",
      "yolo": 1, "task_mode": "yolo", "depth": 1, "started": 1}
e = q.entry_of_record(st, "laptop", 2)
print("needs", e["needs"], "args", e["args"], "mode", repr(e["mode"]), "bad", q.bad_args(e))
PY
has "$T/eor" "needs ['agy']" "the entry needs agy"
has "$T/eor" "'--needs', 'agy', '--harness', 'agy'" "  and carries --harness agy"
hasnt "$T/eor" "--yolo" "  never --yolo"
has "$T/eor" "mode '' bad None" "  no landing mode, and an entry the claim takes"

echo "dispatch --requeue leaves an agy build: its edits are never committed and pushed as a wip (the finish review)"
python3 - "$B/dispatch-queue" "$T" > "$T/rq" 2>&1 <<'PY'
import argparse, importlib.machinery, importlib.util, sys
ld = importlib.machinery.SourceFileLoader("dq", sys.argv[1])
q = importlib.util.module_from_spec(importlib.util.spec_from_loader("dq", ld)); ld.exec_module(q)
st = {"mode": "agy", "harness": "agy", "repo": sys.argv[2] + "/projects/site", "branch": "claude/laptop/2026-11-04-w",
      "topic": "w", "brief": "docs/handoff/2026-11-04-w.md", "wt": sys.argv[2] + "/projects/site/.claude/worktrees/w"}
class RC:
    @staticmethod
    def live(reap=False):
        return [("/nowhere/rec.json", st)]
q.home = lambda: "file:///nowhere"
q.caller_unattended = lambda: False
q.rc_mod = lambda: RC
q.Fleet = lambda url: None
q.cut_run = lambda *a, **k: print("CUT")
print("rc", q.cmd_requeue(argparse.Namespace(all=True, topic=None, repo=None, why="", dry_run=True), None))
PY
has "$T/rq" "left w (site): an agy build" "an agy record is left, said"
hasnt "$T/rq" "CUT" "  never cut"
has "$T/rq" "rc 0" "  and the verb ends 0"
echo "harness list: a live agy run is agy's alone, never a phantom Claude session"
STUB_AGY_SLEEP=30 STUB_AGY_CONV=conv-0012list HARNESS_DISPATCHED=x H run --harness agy --cwd "$WT" --prompt x --name t12 > /dev/null 2>&1
R12=$(rec_of t12)
python3 - "$R12" "$HD/Library/Logs/claude-weekly/run-seed-runs/20261104-000001-site.t12.00000001.json" <<'PY'
import json, sys
r = json.load(open(sys.argv[1]))
json.dump({"mode": "agy", "harness": "agy", "topic": "t12", "repo": "/x/site", "branch": "claude/laptop/2026-11-04-t12",
           "session": "00000001-0000", "pid": r["pid"], "proc_start": r["proc_start"], "started": int(r["started"])},
          open(sys.argv[2], "w"))
PY
DISPATCH_RC_VENDORS=0 H list --harness claude-code --json > "$T/cl" 2>/dev/null
hasnt "$T/cl" "00000001-0000" "claude-code's list leaves the agy record out"
H list --harness agy --json > "$T/al" 2>/dev/null; has "$T/al" "conv-0012list" "  agy's list has it"
H stop conv-0012list --harness agy > /dev/null 2>&1

echo
[ "$fails" = 0 ] && echo "test_agy: all passed" || echo "test_agy: $fails failed"
[ "$fails" = 0 ]
