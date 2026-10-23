#!/usr/bin/env bash
# Tests for bin/autofinish-run (autofinish E1) and the dispatch --start it starts through — a scratch
# HOME, a scratch repo with a bare origin, and stand-ins for claude, screen, GitHub's API and (for
# the crash cases) dispatch itself. No session, screen, window or GitHub call is real.
#   bash modules/wharf-runs/tests/test_autofinish_run.sh
set -u
# a dispatch session runs this suite inside its own run: its markers would change what is tested
unset CLAUDE_UNATTENDED RUN_SEED_DEPTH RUN_SEED_BRIEF RUN_SEED_LABEL RUN_SEED_LOG RUN_SEED_YEAR \
      DISPATCH_DEPTH DISPATCH_BRIEF DISPATCH_LABEL DISPATCH_LOG DISPATCH_YEAR \
      DISPATCH_MAX_DEPTH DISPATCH_MAX_RUNS DISPATCH_MAX_H AUTOFINISH_DISPATCH AUTOFINISH_ACCOUNT \
      ACCOUNTS_FILE ACCOUNT_NOW ACCOUNT_CLAUDE CLAUDE_CODE_OAUTH_TOKEN
unset SKIPPER_GEN SKIPPER_SCOPE SKIPPER_ACCOUNT HELM_HOLD_EVERY HELM_HOLD_PARENT   # the lease's inputs (S4)
B="$(cd "$(dirname "$0")/../bin" && pwd)"   # the module's bin/ (B7: the suites moved to tests/)
# the regatta core's hooks/ (common.py), found as the tools find it (lib/core_path.py); wharf's peers by its tool()
CORE="$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import core_path; print(core_path.hooks() or "")' "$B/../lib")"
[ -n "$CORE" ] || { echo "FAIL: the regatta core is missing"; exit 1; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fails=0
check() { if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3: expected [$2] got [$1]"; fails=$((fails+1)); fi; }
has()   { if grep -qF -- "$2" "$1" 2>/dev/null; then echo "  ok   $3"; else echo "  FAIL $3: missing [$2]"; sed 's/^/         | /' "$1" 2>/dev/null | tail -20; fails=$((fails+1)); fi; }
hasnt() { if grep -qF -- "$2" "$1" 2>/dev/null; then echo "  FAIL $3: found [$2]"; fails=$((fails+1)); else echo "  ok   $3"; fi; }
. "$(cd "$(dirname "$0")" && pwd)/config_fixture.sh"; fixture_config "$T/config"   # the suite's own config dir, never the login's (config_fixture.sh)
export HOME="$T/home"; mkdir -p "$HOME"
export ACCOUNTS_FILE="$T/no-accounts.json"   # no registry unless a case names one: the default is the config dir's lighthouse/accounts.json, the real one (B9)
export CLAUDE_CONFIG_DIR="$HOME/.claude"   # kept for the session: it names the account

# the repo: main with a contract, a claude/* branch in its own worktree, both on a bare origin that
# answers to a GitHub URL (the runner reads owner/name from the configured URL)
git init -q --bare "$T/origin.git"
git init -q -b main "$T/repo"; R="$T/repo"
git -C "$R" config user.email t@t; git -C "$R" config user.name t
printf -- '- check: `true` — prose after the command, as a repo may have it\n- physical: none\n' > "$R/AGENTS.md"
git -C "$R" add AGENTS.md; git -C "$R" commit -qm init
git -C "$R" remote add origin https://github.com/test/repo.git
git -C "$R" config url."$T/origin.git".insteadOf https://github.com/test/repo.git
BR=claude/laptop/2026-10-05-demo
W="$R/.claude/worktrees/demo"
git -C "$R" worktree add -q -b $BR "$W" main
echo work > "$W/f"; git -C "$W" add f; git -C "$W" commit -qm "the work" -m "Prompt: build the demo"
# published without a push verb in this file's text (the checkpoint hook reads command text)
git -C "$R" send-pack "$T/origin.git" "$BR:refs/heads/$BR" "main:refs/heads/main" >/dev/null 2>&1
git -C "$R" update-ref refs/remotes/origin/main main  # as a fetched primary has it
GD="$(git -C "$W" rev-parse --absolute-git-dir)"; CD="$R/.git"
STATE="$GD/claude/autofinish.json"; LOCK="$GD/claude/owner.json"
next_tip() { git -C "$W" commit -q --allow-empty -m "$1"; }

# claude: snapshots what it finds at its start, then plays STUB_RUN — reply with STUB_REPLY's text and
# go idle, crash, or stay busy (and, on SIGTERM, leave its lock behind as R29 saw)
cat > "$T/claude" <<EOF
#!/bin/bash
echo "claude \$*" >> "$T/claude.calls"; env > "$T/claude.env"
sid=; prev=; for a in "\$@"; do [ "\$prev" = --session-id ] && sid=\$a; prev=\$a; done
gd=\$(git rev-parse --absolute-git-dir)
cp "\$gd/claude/owner.json" "$T/at-start.\$sid.lock" 2>/dev/null
[ -n "\${STUB_MARK:-}" ] && touch "\$gd/claude/finishing"
cp "\$gd/claude/autofinish.json" "$T/at-start.\$sid.state" 2>/dev/null
[ -s "\$gd/claude/autofinish-bundle.md" ] && cp "\$gd/claude/autofinish-bundle.md" "$T/at-start.\$sid.bundle"
rec="\$HOME/.claude/sessions/\$\$.json"; mkdir -p "\$HOME/.claude/sessions" "\$HOME/.claude/projects/x"
old=\$(( (\$(date +%s) - 700) * 1000 ))
trap 'rm -f "\$rec"; exit 0' TERM
case "\${STUB_RUN:-reply}" in
  reply) python3 -c 'import json, sys; print(json.dumps({"type": "assistant", "message": {"content": [{"type": "text", "text": open(sys.argv[1]).read()}]}}))' "\$STUB_REPLY" > "\$HOME/.claude/projects/x/\$sid.jsonl"
         printf '{"sessionId":"%s","status":"idle","statusUpdatedAt":%s}' "\$sid" \$old > "\$rec";;
  crash) exit 1;;
  busy)  printf '{"sessionId":"%s","status":"busy","statusUpdatedAt":%s}' "\$sid" \$old > "\$rec"
         echo '{"type":"user","message":{"content":"/finish"},"timestamp":"2026-10-15T00:00:00Z"}' > "\$HOME/.claude/projects/x/\$sid.jsonl"
         trap 'printf "{\\"session\\": \\"%s\\"}" "\$sid" > "\$gd/claude/owner.json"; rm -f "\$rec"; exit 0' TERM;;
esac
while :; do sleep 0.2; done
EOF
cat > "$T/screen" <<EOF
#!/bin/bash
case "\$1" in
  -U) [ "\$2" = -dmS ] || exit 1; shift 3; "\$@" >/dev/null 2>&1 & exit 0;;
  -ls) exit 1;;
  -S) case "\$*" in *quit*) pkill -TERM -f "\${2#*.}.sh" 2>/dev/null;; esac;;
esac
exit 0
EOF
# GitHub: one open PR, #7; a closed merged one, #42; every call logged
cat > "$T/api_stub.py" <<'EOF'
import json, os
def api(method, path, body=None, tok=None, timeout=15):
    with open(os.environ["STUB_API_LOG"], "a") as f:
        f.write(json.dumps({"method": method, "path": path, "body": body}, ensure_ascii=False) + "\n")
    if method == "GET" and "state=open" in path:
        return 200, [{"number": 7, "html_url": "https://github.com/test/repo/pull/7"}]
    if method == "GET" and "state=closed" in path:
        return 200, ([] if os.environ.get("STUB_NO_MERGED") else [{"number": 42, "merged_at": "2026-10-05T00:00:00Z"}])
    if method == "POST":
        return 201, {"id": 1}
    return 404, None
EOF
echo '[]' > "$T/prs.json"
chmod +x "$T/claude" "$T/screen"
export DISPATCH_CLAUDE="$T/claude" DISPATCH_SCREEN="$T/screen" DISPATCH_HOST=buildbox DISPATCH_POLL=0.2 DISPATCH_START_WAIT=2 \
       AUTOFINISH_API_STUB="$T/api_stub.py" STUB_API_LOG="$T/api.log" PICKUP_PRS="$T/prs.json"
LOGS="$HOME/Library/Logs/claude-weekly"; AFLOG="$LOGS/autofinish-$(date +%Y-%m-%d).log"
field() { python3 -c 'import json, sys; v = json.load(open(sys.argv[1])).get(sys.argv[2]); print("null" if v is None else v)' "$STATE" "$1"; }
# the runner returns at once; its child records the end: wait for it (up to ~30 s)
ended() { for _ in $(seq 1 150); do [ "$(field ended 2>/dev/null)" != null ] && [ -n "$(field ended 2>/dev/null)" ] && return 0; sleep 0.2; done; echo "  (no end recorded in 30 s)"; return 1; }
af() { CLAUDE_CODE_CHILD_SESSION=1 CLAUDE_CODE_SESSION_ID=caller "$B/autofinish-run" "$W" "$@"; }

echo "a stop: the lock before the start, the state at each stage, the ⚠ on the PR"
printf 'Ran the check: all pass.\n\n⚠ step 4 — 2 open items before this branch can be finished:\n1. the README row — not recorded anywhere\n2. a test for --x — TODO.md\n\nSAM, THIS SESSION IS WAITING FOR YOU — two open items, above\n' > "$T/stop.txt"
TIP=$(git -C "$W" rev-parse HEAD)
start=$(date +%s)
STUB_REPLY="$T/stop.txt" af --rule A --by sweep > "$T/out" 2>&1; check "$?" "0" "started"
check "$(( $(date +%s) - start <= 3 ))" "1" "  the caller returned at once (the wait is the child's)"
has "$T/out" 'started: /finish claude/laptop/2026-10-05-demo --unattended — window and Remote Control "finish · demo"' "  and said where to watch"
SID=$(field session)
ended
S0="$T/at-start.$SID"
has "$S0.lock" "\"session\": \"$SID\"" "the lock named the session before claude started (P8)"
has "$S0.bundle" "── context ──" "  the bundle (pickup's context_bundle) was written before the start"
has "$S0.bundle" "the work" "    with the branch's commits"
python3 - "$S0.state" "$SID" "$TIP" > "$T/out" <<'PY'
import json, sys
st = json.load(open(sys.argv[1]))
keys = ["started", "session", "tip", "by", "rule", "window", "account", "ended", "outcome", "pr", "gate"]
ok = (list(st) == keys and st["session"] == sys.argv[2] and st["tip"] == sys.argv[3] and st["by"] == "sweep"
      and st["rule"] == "A" and st["window"] == "finish · demo" and st["ended"] is None and st["outcome"] is None
      and st["pr"] is None and st["gate"] is None and st["started"])
print("ok" if ok else st)
PY
check "$(cat "$T/out")" "ok" "  the state at the start: the contract's keys exactly, ended/outcome/pr/gate null"
check "$(field outcome)" "stopped" "the state after the end: stopped"
check "$(field gate)" "G4" "  at G4 (step 4 named in the ⚠ line)"
check "$(field pr)" "7" "  on the branch's PR"
check "$(python3 -c 'import json, sys; print(list(json.load(open(sys.argv[1]))))' "$STATE")" \
      "['started', 'session', 'tip', 'by', 'rule', 'window', 'account', 'ended', 'outcome', 'pr', 'gate']" "  still the contract's keys, nothing else"
has "$T/api.log" '"method": "POST", "path": "/repos/test/repo/issues/7/comments"' "the stop posted as a PR comment through the api"
has "$T/api.log" '⚠ step 4 — 2 open items' "  carrying the ⚠ block"
hasnt "$T/api.log" "WAITING FOR YOU" "  without the closing line"
has "$CD/claude/autofinished" "stopped $BR G4 ⚠ step 4 — 2 open items before this branch can be finished:" "the autofinished line (design section 7)"
has "$AFLOG" " run repo $BR started session=${SID:0:8}" "the log: the start"
has "$AFLOG" " run repo $BR stopped gate=G4 pr=#7 session=${SID:0:8}" "  and the end, in <iso> run <repo> <branch> <outcome> form"
check "$([ -f "$LOCK" ] && echo kept || echo gone)" "gone" "the lock released after the end"
has "$T/claude.calls" "claude /finish $BR --unattended --session-id $SID --remote-control finish · demo · buildbox --model opus" \
    "claude: the prompt, the chosen id, Remote Control \"finish · <topic> · <machine>\", opus"
has "$T/claude.calls" "--permission-mode auto" "  auto mode"
for a in "EnterWorktree" "Bash(git:*)" "Agent Bash(./bootstrap.sh --check)"; do
  has "$T/claude.calls" "$a" "  allowed: $a"
done
hasnt "$T/claude.calls" "/hooks/carried.py" "  no overlay installed: no rule for its bin/ or carried.py"
# with an overlay (the core's legacy_root, a stand-in here): its bin/ and carried.py, under ~/ and absolute
check "$(REGATTA_LEGACY="$HOME/projects/ovl" python3 - "$B/autofinish-run" <<'PY'
import importlib.machinery, os, sys, types
af = importlib.machinery.SourceFileLoader("afr", sys.argv[1]).load_module()
t = types.SimpleNamespace(branch="b", path="/w", window="finish · w", primary="/p")
cmd = af.start_cmd(t, "sid")
print(" ".join(cmd[i + 1] for i, a in enumerate(cmd) if a == "--allow" and "ovl" in cmd[i + 1]))
PY
)" "Bash(~/projects/ovl/bin/*) Bash(python3 ~/projects/ovl/bin/*) Bash(python3 ~/projects/ovl/hooks/carried.py:*) Bash($HOME/projects/ovl/bin/*) Bash(python3 $HOME/projects/ovl/bin/*) Bash(python3 $HOME/projects/ovl/hooks/carried.py:*)" \
  "  with an overlay installed: its bin/ and carried.py, in both spellings"
hasnt "$T/claude.calls" "Bash(true" "  no allow rule for the contract's check: a branch may change it unwatched since D1-A (2026-10-13)"
sed 's/.*--disallowedTools//' "$T/claude.calls" > "$T/denied"
has "$T/denied" "Bash(gh:*) Bash(ssh:*) Bash(python3 scripts/deploy.py:*)" "  denied: dispatch's list…"
hasnt "$T/denied" "git push" "  …minus git push"
hasnt "$T/denied" "bin/pr" "  …and bin/pr (the ref guards judge them)"
grep -q '^CLAUDE_CODE_CHILD_SESSION=' "$T/claude.env"; check "$?" "1" "the caller's CLAUDE_CODE_* never reaches the session"
grep -q '^CLAUDE_CODE_SESSION_ID=caller' "$T/claude.env"; check "$?" "1" "  nor its session id"
grep -q '^CLAUDE_CONFIG_DIR=' "$T/claude.env"; check "$?" "1" "  CLAUDE_CONFIG_DIR=~/.claude is the default login: unset, or it runs logged out (bin/account's header)"
grep -q '^CLAUDE_UNATTENDED=dispatch$' "$T/claude.env"; check "$?" "0" "  CLAUDE_UNATTENDED is dispatch's"
grep -q '^CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1$' "$T/claude.env"; check "$?" "0" "  background tasks off: dispatch's foreground default reaches the /finish runner"

echo "no retry on the same tip"
: > "$T/claude.calls"
STUB_REPLY="$T/stop.txt" af > "$T/out" 2>&1; check "$?" "3" "a second start on the stopped tip is refused"
has "$T/out" "no retry on the same tip" "  saying why"
check "$(wc -c < "$T/claude.calls" | tr -d ' ')" "0" "  and no session starts"
check "$(field session)" "$SID" "  the state still the stopped run's"
has "$AFLOG" " run repo $BR refused tip=${TIP:0:7}" "  logged"

echo "a launch read back"
next_tip "fix the open items"; : > "$T/api.log"
printf 'merged #42: Pull Request successfully merged\nrollback: cd %s && git revert --no-edit aaa..bbb && GIT_PUSH_OK=1 git push origin main\n\n⛵ 🚢 ⚓ **Shipped:** %s — #42\n\nSAM, IT'"'"'S FINE — THIS SESSION IS REALLY DONE. YOU HAVEN'"'"'T FORGOTTEN ANYTHING.\n' "$R" "$BR" > "$T/launch.txt"
echo '{"by":"sam","ts":0,"now":true}' > "$GD/claude/autofinish"
STUB_REPLY="$T/launch.txt" af --rule C --by override > "$T/out" 2>&1; check "$?" "0" "started on the new tip"
ended
check "$([ -e "$GD/claude/autofinish" ] && echo kept || echo gone)" "gone" "/autofinish's marker cleared once the run ended"
check "$(field outcome)" "launched" "launched"
check "$(field pr)" "42" "  as #42, read from the reply"
check "$(field gate)" "null" "  no gate"
hasnt "$T/api.log" '"POST"' "  no comment"
has "$CD/claude/autofinished" "launched $BR #42" "the autofinished line"
check "$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import common; e = common.autofinished(sys.argv[2])[-1]; print(e["outcome"] + ":" + e["branch"])' "$CORE" "$CD")" "launched:$BR" "  …which the hooks' reader parses (common.autofinished)"
has "$AFLOG" " run repo $BR launched pr=#42 " "the log: launched…"
has "$AFLOG" "rollback: cd $R && git revert" "  …with the rollback line"
check "$([ -f "$LOCK" ] && echo kept || echo gone)" "gone" "the lock released"

echo "an improvised ending is a stop, never a launch (R16)"
next_tip "more"; : > "$T/api.log"
printf 'All done, I think this is fine.\n' > "$T/vague.txt"
STUB_REPLY="$T/vague.txt" af > /dev/null 2>&1; ended
check "$(field outcome)" "stopped" "stopped"
check "$(field gate)" "no-landing" "  gate no-landing"
has "$T/api.log" "All done, I think this is fine." "  posted"

echo "an empty branch is a nothing-to-land stop, in either word (rename S4; the gate token keeps its word)"
for w in land launch; do
  next_tip "empty $w"; : > "$T/api.log"
  printf 'Nothing to %s: %s is empty (nothing committed)\n\nSAM, IT'"'"'S FINE — THIS SESSION IS REALLY DONE. YOU HAVEN'"'"'T FORGOTTEN ANYTHING.\n' "$w" "$BR" > "$T/empty.txt"
  STUB_REPLY="$T/empty.txt" af > /dev/null 2>&1; ended
  check "$(field outcome)/$(field gate)" "stopped/nothing-to-land" "  'Nothing to $w': stopped/nothing-to-land"
done

echo "a ⚠ anywhere is a stop, whatever else the reply names (review, 2026-10-05)"
next_tip "stop naming a merge"; : > "$T/api.log"
printf 'Rebased onto origin/main.\n\n⚠ step 11 — rebase conflict after origin/main moved (merged #57 touched hooks/x.py)\nrollback: none needed — nothing was pushed\n\nSAM, THIS SESSION IS WAITING FOR YOU — the conflict, above\n' > "$T/stop57.txt"
STUB_REPLY="$T/stop57.txt" af > /dev/null 2>&1; ended
check "$(field outcome)/$(field gate)/$(field pr)" "stopped/G11/7" "a stop naming 'merged #57' and a rollback line: stopped at G11, on the branch's own PR"
check "$(tail -1 "$CD/claude/autofinished" | cut -d' ' -f2-4)" "stopped $BR G11" "  the autofinished line says stopped, never launched #57"
has "$T/api.log" "merged #57 touched hooks/x.py" "  and the stop is on the PR"

echo "a launch whose number nobody read: no #None"
next_tip "launch, no number"; : > "$T/api.log"
printf '⛵ 🚢 ⚓ **Shipped:** %s — launched\n\nSAM, IT'"'"'S FINE — THIS SESSION IS REALLY DONE. YOU HAVEN'"'"'T FORGOTTEN ANYTHING.\n' "$BR" > "$T/launch-nonum.txt"
STUB_NO_MERGED=1 STUB_REPLY="$T/launch-nonum.txt" af > /dev/null 2>&1; ended
check "$(field outcome)/$(field pr)" "launched/null" "launched, no PR number read"
check "$(tail -1 "$CD/claude/autofinished" | cut -d' ' -f2-)" "launched $BR" "  the line ends at the branch: no #None"
# Either word (rename S3, 2026-10-19): the phrase comes from regatta's core, whose S3 half goes in apart
# from this repo's; each order must leave both checks green. Rename S8 (a week on) asserts the new word only.
check "$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import common; print(common.autofinished_phrase(common.autofinished(sys.argv[2])[-1]))' "$CORE" "$CD" | sed 's/ landed as / launched as /')" \
      "$BR launched as #?" "  which the hooks' reader says as #? (rename S3: in the new word)"

echo "rename S2 (M7): an outcome in the word S4 writes is a launch to every check record() makes"
: > "$T/api.log"
python3 - "$B/autofinish-run" "$W" <<'EOF' > "$T/out" 2>&1
import sys
from importlib.machinery import SourceFileLoader
m = SourceFileLoader("afr", sys.argv[1]).load_module()
t = m.Tree(sys.argv[2])
m.read_outcome = lambda t, sid, log_from: ("launched", 43, None, ["Shipped: #43"])
m.record(t, m.read_state(t), 0, 0, "a why a stop would carry", [])
EOF
check "$(field outcome)/$(field pr)/$(field gate)" "launched/43/null" "  the state: launched as #43, no gate"
hasnt "$T/api.log" '"POST"' "  no comment, as for launched"
check "$(tail -1 "$CD/claude/autofinished" | cut -d' ' -f2-)" "launched $BR #43" "  the autofinished line in its own word, the shape of landed's"
check "$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import common; print(common.autofinished_phrase(common.autofinished(sys.argv[2])[-1]))' "$CORE" "$CD" | sed 's/ landed as / launched as /')" \
      "$BR launched as #43" "  which the hooks' reader says in the new word (rename S3)"
has "$AFLOG" " run repo $BR launched pr=#43 " "  and the log's end line, which the door's RUN_LAUNCHED reads"

echo "a fake crash: claude exits at once, and dispatch itself dies"
next_tip "crash"; : > "$T/api.log"
STUB_RUN=crash af > /dev/null 2>&1; ended
check "$(field outcome)" "never-started" "claude crashed before a reply: never-started"
check "$([ -f "$LOCK" ] && echo kept || echo gone)" "gone" "  the lock released"
has "$T/api.log" "autofinish never started" "  said on the PR"
check "$(tail -1 "$CD/claude/autofinished" | cut -d' ' -f2-3)" "never-started $BR" "  the autofinished line: <iso> never-started <branch> <line>"
check "$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import common; e = common.autofinished(sys.argv[2])[-1]; print(e["outcome"] + ":" + e["branch"] + ":" + str(bool(e["detail"])))' "$CORE" "$CD")" \
      "never-started:$BR:True" "  …which the hooks' reader parses as never-started, with its line"
echo "memory past the host's limit: dispatch --start refuses before any session (bin/headroom)"
next_tip "no room"; : > "$T/api.log"
HEADROOM_SAMPLE="50 1 500" af > /dev/null 2>&1; ended
check "$(field outcome)/$(field gate)" "never-started/refused" "a launch on a host swapping past its limit: never-started at gate refused, as at the cap"
next_tip "start crash"; : > "$T/api.log"
cat > "$T/dispatch-crash" <<EOF
#!/bin/bash
echo "\$(ps -o pgid= -p \$\$ | tr -d ' ') \$PPID" > "$T/crash.who"
echo "dispatch: crashed" >&2; exit 137
EOF
chmod +x "$T/dispatch-crash"
AUTOFINISH_DISPATCH="$T/dispatch-crash" af > /dev/null 2>&1; ended
check "$([ -f "$LOCK" ] && echo kept || echo gone)" "gone" "dispatch crashed before any session: the lock released in finally"
check "$(field outcome)/$(field gate)" "never-started/refused" "  recorded as refused: never started"
check "$(wc -c < "$T/api.log" | tr -d ' ')" "0" "  nothing on the PR: nothing ran"
read -r PG WP < "$T/crash.who"
check "$([ "$PG" != "$(ps -o pgid= -p $$ | tr -d ' ')" ] && echo own || echo shared)" "own" "the waiter runs in its own process group (setsid), not the caller's"
AUTOFINISH_DISPATCH="$T/dispatch-crash" af > "$T/out" 2>&1; check "$?" "0" "a tip that never started may start again"
ended
# a record written before S1 of docs/wharf-rename-2026-10-16.md says `not-launched`: still read as refused
python3 -c 'import json, sys; d = json.load(open(sys.argv[1])); d["gate"] = "not-launched"; json.dump(d, open(sys.argv[1], "w"))' "$STATE"
af --dry > "$T/out" 2>&1; check "$?" "0" "  an old record's gate not-launched reads as refused: the tip may start again"

echo "a fake SIGTERM end: the session ended by SIGTERM, leaving its lock behind (R29)"
next_tip "term"; : > "$T/claude.calls"
STUB_RUN=busy af > /dev/null 2>&1
for _ in $(seq 1 50); do CP=$(pgrep -f "$T/claude /finish" | head -1); [ -n "$CP" ] && break; sleep 0.2; done
sleep 1; kill -TERM "$CP"
ended
check "$([ -f "$LOCK" ] && echo kept || echo gone)" "gone" "the lock the dead session left is gone after the end"
check "$(field outcome)" "never-started" "  no reply: never-started"
has "$HOME/Library/Logs/claude-weekly/$(date +%Y-%m-%d)-dispatch-finish-demo.log" "claude exited by itself" "  the watcher saw claude go"

echo "the waiter itself ended by SIGTERM: finally still runs"
next_tip "waiter"
cat > "$T/dispatch-hang" <<EOF
#!/bin/bash
echo \$PPID > "$T/hang.waiter"; exec sleep 60
EOF
chmod +x "$T/dispatch-hang"
AUTOFINISH_DISPATCH="$T/dispatch-hang" af > /dev/null 2>&1
for _ in $(seq 1 50); do [ -s "$T/hang.waiter" ] && break; sleep 0.2; done
check "$([ -f "$LOCK" ] && echo held || echo free)" "held" "the lock is held while the run goes"
kill -TERM "$(cat "$T/hang.waiter")"
ended
check "$([ -f "$LOCK" ] && echo kept || echo gone)" "gone" "the waiter's SIGTERM: the lock released in finally"
has "$AFLOG" "the waiter ended: signal 143" "  and the log says why"
next_tip "waiter, live"; : > "$T/claude.calls"
STUB_RUN=busy STUB_MARK=1 af > /dev/null 2>&1
for _ in $(seq 1 50); do CP=$(pgrep -f "$T/claude /finish" | head -1); [ -n "$CP" ] && break; sleep 0.2; done
sleep 1
# the waiter is the forked runner: the one process left with the runner's command line
WPID=$(pgrep -f "bin/autofinish-run $W" | head -1)
check "$([ -f "$GD/claude/finishing" ] && echo set || echo unset)" "set" "a /finish under way (its finishing marker set)…"
kill -TERM "$WPID"
ended
sleep 0.5; kill -0 "$CP" 2>/dev/null; check "$?" "1" "  …whose waiter is ended: its session is ended first"
check "$([ -f "$LOCK" ] && echo kept || echo gone)" "gone" "  then the lock released"
check "$([ -f "$GD/claude/finishing" ] && echo kept || echo gone)" "gone" "  and the finishing marker removed"
grep -q '"end_reason": "ended with its autofinish waiter"' "$HOME"/Library/Logs/claude-weekly/run-seed-runs/*.json; check "$?" "0" "  dispatch's record says why it ended"

echo "a lock held by a session at work is never taken (review, 2026-10-05)"
next_tip "locks"
sleep 300 & HOLDER=$!; trap 'kill $HOLDER 2>/dev/null; rm -rf "$T"' EXIT
H=4f1e0000-0000-4000-8000-000000000000
mkdir -p "$HOME/.claude/sessions"
holder() { # holder <status> <seen-ago-s> [handover]: session H live in the registry with that status, and owning the lock
  echo "{\"pid\": $HOLDER, \"sessionId\": \"$H\", \"cwd\": \"$W\", \"status\": \"$1\"}" > "$HOME/.claude/sessions/holder.json"
  echo "{\"session\": \"$H\", \"branch\": \"$BR\", \"seen\": $(( $(date +%s) - $2 ))${3:+, \"handover\": $(date +%s)}}" > "$LOCK"; }
holder shell 60
af --dry > "$T/out" 2>&1; check "$?" "3" "the lock's session is live with a background shell (the Session-tab waiter): refused"
has "$T/out" "live and shell" "  saying so"
holder shell 60 handover
af --dry > "$T/out" 2>&1; check "$?" "0" "  the same lock marked handover (wharf settled the block): the dry run starts"
af --dry --by typed --session caller-0000-4000-8000-000000000000 > /dev/null 2>&1; check "$?" "0" "  a typed hand-off may take a handed-over lock too"
holder busy 60 handover
af --dry > "$T/out" 2>&1; check "$?" "3" "  handed over but busy (its last turn still running): refused"
holder busy 60
af --dry > "$T/out" 2>&1; check "$?" "3" "the lock's session is live and busy: refused, whoever calls (the sweep here)"
has "$T/out" "held by session ${H:0:8}, live and busy" "  saying whose and why"
holder waiting 60
af --dry > "$T/out" 2>&1; check "$?" "3" "  live and waiting on a dialog: refused too"
has "$T/out" "live and waiting" "    (the live-session rule, not the typed one)"
holder idle 60
af --dry > /dev/null 2>&1; check "$?" "0" "live and idle: the sweep may take it (the panel is told at its next prompt)"
af --dry --by typed --session caller-0000-4000-8000-000000000000 > "$T/out" 2>&1; check "$?" "3" "  a typed hand-off may not: the lock is another session's, unexpired"
has "$T/out" "not the one that typed /finish" "  saying so"
af --dry --by typed --session "$H" > /dev/null 2>&1; check "$?" "0" "  the caller's own lock is no refusal"
rm "$HOME/.claude/sessions/holder.json"; holder idle 60; rm "$HOME/.claude/sessions/holder.json"
af --dry --by typed --session caller-0000-4000-8000-000000000000 > /dev/null 2>&1; check "$?" "3" "  a dead holder's unexpired lock still refuses a typed hand-off"
holder idle 7300; rm "$HOME/.claude/sessions/holder.json"
af --dry --by typed --session caller-0000-4000-8000-000000000000 > /dev/null 2>&1; check "$?" "0" "  an expired one does not"
rm -f "$LOCK"

echo "one start at a time: autofinish.json.lock (O_EXCL), around the refusals and the writes"
SL="$GD/claude/autofinish.json.lock"
cp "$STATE" "$T/state.before"; : > "$T/claude.calls"
echo 99999 > "$SL"
af > "$T/out" 2>&1; check "$?" "3" "a start lock another start holds: refused"
has "$T/out" "another start on this worktree is under way" "  saying so"
check "$(cmp -s "$STATE" "$T/state.before" && echo same || echo changed):$(wc -c < "$T/claude.calls" | tr -d ' ')" "same:0" "  nothing written, nothing started"
check "$([ -f "$SL" ] && echo kept || echo gone)" "kept" "  and the holder's lock left alone"
touch -t "$(date -v-3M +%Y%m%d%H%M.%S)" "$SL"
STUB_REPLY="$T/stop.txt" af > /dev/null 2>&1; check "$?" "0" "a start lock older than 2 min is a start that died: taken over"
ended
check "$([ -f "$SL" ] && echo kept || echo gone)" "gone" "  and freed once the start returned"

echo "a detach that fails gives the lock back (review, 2026-10-05)"
next_tip "detach fails"
printf '{"session": "panel-0000-4000-8000-000000000000", "branch": "%s", "seen": 1}' "$BR" > "$LOCK"; cp "$LOCK" "$T/lock.before"
python3 - "$B/autofinish-run" "$W" <<'EOF' > "$T/out" 2>&1
import sys
from importlib.machinery import SourceFileLoader
m = SourceFileLoader("autofinish_run", sys.argv[1]).load_module()
def no_fork(fn, out):
    raise OSError("fork: resource temporarily unavailable")
m.detach = no_fork
print("rc=%s" % m.main([sys.argv[2], "--rule", "A", "--by", "sweep"]))
EOF
has "$T/out" "rc=1" "the detach failed: exit 1"
check "$(cmp -s "$LOCK" "$T/lock.before" && echo restored || echo changed)" "restored" "  the previous lock restored, byte for byte"
check "$(field outcome)/$(field gate)" "never-started/refused" "  the state ended never-started at refused: nothing ran"
check "$([ -f "$SL" ] && echo kept || echo gone)" "gone" "  the start lock freed"
af --dry > /dev/null 2>&1; check "$?" "0" "  and that tip may start again"
rm -f "$LOCK"
python3 - "$B/autofinish-run" "$W" <<'EOF' > /dev/null 2>&1
import sys
from importlib.machinery import SourceFileLoader
m = SourceFileLoader("autofinish_run", sys.argv[1]).load_module()
def no_fork(fn, out):
    raise OSError("fork failed")
m.detach = no_fork
m.main([sys.argv[2], "--rule", "A", "--by", "sweep"])
EOF
check "$([ -f "$LOCK" ] && echo kept || echo gone)" "gone" "  with no lock before it, ours is removed"

echo "the login: picked at start from the account pool (work-account E5, 2026-10-08)"
ln -s "$T" "$HOME/projects"   # bin/account names a repo by its path under ~/projects: $T/repo is "repo"
mkdir -p "$HOME/.acct-c"
# pool <acct-c deny list> <acct-c 5h> <acct-a 5h>: both rows read just now, so no probe runs
pool() {
  python3 - "$T/accounts.json" "$HOME" "$@" <<'EOF'
import json, sys, time
f, home, deny, i5, d5 = sys.argv[1], sys.argv[2], json.loads(sys.argv[3]), float(sys.argv[4]), float(sys.argv[5])
json.dump({"accounts": [
    {"label": "acct-c", "home": home + "/.acct-c", "rules": {"window_max": 50}, "repos": {"deny": deny}},
    {"label": "acct-a", "home": home + "/.claude", "primary": True, "rules": {"window_max": 50}}]}, open(f, "w"))
now = time.time()
for d, fh in ((home + "/.acct-c", i5), (home + "/.claude", d5)):
    json.dump({"at": now, "limits": {"five_hour": fh, "seven_day": 6, "five_hour_resets": now + 3600,
                                     "seven_day_resets": now + 86400, "locked": []}}, open(d + "/usage-probe.json", "w"))
EOF
}
export ACCOUNTS_FILE="$T/accounts.json" ACCOUNT_CLAUDE=false
# the sweep's launchd job: no login of its own in the env
afp() { env -u CLAUDE_CONFIG_DIR -u CLAUDE_CODE_OAUTH_TOKEN CLAUDE_CODE_CHILD_SESSION=1 CLAUDE_CODE_SESSION_ID=caller "$B/autofinish-run" "$W" "$@"; }
# afl <dir> <token> …: a caller with these login variables ("" leaves one out)
afl() { local cfg=$1 tok=$2; shift 2; env -u CLAUDE_CONFIG_DIR -u CLAUDE_CODE_OAUTH_TOKEN ${cfg:+CLAUDE_CONFIG_DIR=$cfg} ${tok:+CLAUDE_CODE_OAUTH_TOKEN=$tok} CLAUDE_CODE_CHILD_SESSION=1 CLAUDE_CODE_SESSION_ID=caller "$B/autofinish-run" "$W" "$@"; }
next_tip "pool: acct-c"; pool '[]' 10 10
STUB_REPLY="$T/stop.txt" afp --rule A --by sweep > "$T/out" 2>&1; check "$?" "0" "started with no CLAUDE_CONFIG_DIR in the caller's env"
ended
grep -q "^CLAUDE_CONFIG_DIR=$HOME/.acct-c$" "$T/claude.env"; check "$?" "0" "  acct-c, first in the walk: its CLAUDE_CONFIG_DIR reaches the session"
check "$(field account)" "acct-c" "  the state names the account"
has "$AFLOG" " run repo $BR started session=$(field session | cut -c1-8) tip=$(git -C "$W" rev-parse --short=7 HEAD) rule=A by=sweep account=acct-c" "  so does the start's log line"
has "$AFLOG" "by=sweep account=acct-c — ⚠ step 4" "  and the end's"
has "$T/out" ", account acct-c;" "  and the caller's line"
next_tip "pool: denied"; pool '["repo"]' 10 10
STUB_REPLY="$T/stop.txt" afp --rule A --by sweep > "$T/out" 2>&1; check "$?" "0" "a repo on acct-c's deny list starts too"
ended
check "$(field account)" "acct-a" "  on the next row, acct-a"
grep -q '^CLAUDE_CONFIG_DIR=' "$T/claude.env"; check "$?" "1" "  the default dir: CLAUDE_CONFIG_DIR unset (bin/account's header)"
next_tip "pool: explicit"; pool '[]' 10 10
STUB_REPLY="$T/stop.txt" afl "$HOME/.acct-c" "" --rule A --by sweep > "$T/out" 2>&1; check "$?" "0" "a caller with CLAUDE_CONFIG_DIR of its own"
ended
grep -q "^CLAUDE_CONFIG_DIR=$HOME/.acct-c$" "$T/claude.env"; check "$?" "0" "  keeps it, with no pick: an explicit choice (bin/autofinish passes its gate's pick this way)"
next_tip "pool: explicit, cooling down"; pool '[]' 10 10
printf '{"at": %s, "window": "seven_day", "used": 99, "resets_at": %s, "session": "t"}\n' "$(date +%s)" "$(( $(date +%s) + 3600 ))" > "$HOME/.acct-c/exhaustion.jsonl"
STUB_REPLY="$T/stop.txt" afl "$HOME/.acct-c" "" --rule A --by sweep > "$T/out" 2>&1; rc=$?; rm -f "$HOME/.acct-c/exhaustion.jsonl"
check "$rc" "0" "a caller whose own login is cooling down"
ended
check "$(field account)" "acct-a" "  is not kept: the pick moves the run off the locked row"
grep -q '^CLAUDE_CONFIG_DIR=' "$T/claude.env"; check "$?" "1" "  the default dir: CLAUDE_CONFIG_DIR unset"
has "$AFLOG" "acct-c is cooling down, so picked" "  and the start's log line says why"
# the caller second in the walk, on the default dir: pick returns acct-c at once and never judges it
next_tip "pool: explicit default, cooling down"; pool '[]' 10 10
printf '{"at": %s, "window": "five_hour", "used": 100, "resets_at": %s, "session": "t"}\n' "$(date +%s)" "$(( $(date +%s) + 3600 ))" > "$HOME/.claude/exhaustion.jsonl"
STUB_REPLY="$T/stop.txt" afl "$HOME/.claude" "" --rule A --by sweep > "$T/out" 2>&1; rc=$?; rm -f "$HOME/.claude/exhaustion.jsonl"
check "$rc" "0" "a caller on the default login, cooling down, behind an eligible row"
ended
check "$(field account)" "acct-c" "  is not kept either: its row is read by its home, not from pick's skipped"
has "$AFLOG" "acct-a is cooling down, so picked" "  the log line names the default row"
next_tip "pool: explicit, parked"; pool '[]' 10 10
python3 -c 'import json,sys; f=sys.argv[1]; d=json.load(open(f)); d["accounts"][0]["enabled"]=False; json.dump(d, open(f, "w"))' "$T/accounts.json"
STUB_REPLY="$T/stop.txt" afl "$HOME/.acct-c" "" --rule A --by sweep > "$T/out" 2>&1; check "$?" "0" "a caller on a parked row (enabled: false)"
ended
check "$(field account)" "acct-a" "  is not kept: the pick moves it"
next_tip "pool: explicit default"; pool '[]' 10 10
STUB_REPLY="$T/stop.txt" afl "$HOME/.claude" "" --rule A --by sweep > "$T/out" 2>&1; check "$?" "0" "a caller with CLAUDE_CONFIG_DIR=~/.claude"
ended
grep -q '^CLAUDE_CONFIG_DIR=' "$T/claude.env"; check "$?" "1" "  the default login runs with it unset (bin/account's header), though acct-c has room"
next_tip "pool: token"; pool '[]' 10 10
STUB_REPLY="$T/stop.txt" afl "$HOME/.acct-c" x --rule A --by sweep > "$T/out" 2>&1; check "$?" "0" "a caller with a token and a dir"
ended
check "$(field account)" "oauth-token" "  the token outranks the dir: the state says so, with no space for the log's key=value"
next_tip "pool: none"; pool '[]' 90 90; : > "$T/claude.calls"; SBEFORE=$(field session)
afp --rule A --by sweep > "$T/out" 2>&1; check "$?" "3" "no row may run now: refused"
has "$T/out" "no account may run this now — acct-c: 5h 90.0% > 50%" "  with each row's reason"
has "$T/out" "acct-a: 5h 90.0% > 50%" "    the primary's too"
check "$(wc -c < "$T/claude.calls" | tr -d ' ')" "0" "  no session starts"
check "$(field session)" "$SBEFORE" "  no state written: the next tick tries this tip again"
has "$AFLOG" " run repo $BR refused tip=$(git -C "$W" rev-parse --short=7 HEAD) rule=A by=sweep — no account may run" "  logged"
pool '[]' 10 10
afp --dry > "$T/out" 2>&1; check "$?" "0" "--dry picks too"
has "$T/out" "account acct-c ($HOME/.acct-c): " "  and says which"
printf '#!/bin/sh\necho nope\nexit 1\n' > "$T/acct-broken"; chmod +x "$T/acct-broken"
AUTOFINISH_ACCOUNT="$T/acct-broken" afp --dry > "$T/out" 2>&1; check "$?" "0" "an unreadable pick still starts"
has "$T/out" "account unchanged: account pick failed (nope) — the login this run was started with" "  on the login it was started with"
ACCOUNTS_FILE="$T/no-registry.json" afp --dry > "$T/out" 2>&1; check "$?" "0" "no registry (the pick's exit 4) still starts"
has "$T/out" "account unchanged: no account registry here — the login this run was started with" "  on the login it was started with"
# a typed hand-off waits in cold_prompt's 45 s: its pick reads the cache, never probes
printf '#!/bin/sh\necho "$*" >> "%s"\necho "{}"\nexit 1\n' "$T/acct.calls" > "$T/acct-log"; chmod +x "$T/acct-log"
next_tip "pool: typed"; : > "$T/acct.calls"
STUB_REPLY="$T/stop.txt" AUTOFINISH_ACCOUNT="$T/acct-log" afp --rule C --by typed > "$T/out" 2>&1; check "$?" "0" "a typed hand-off starts"
ended
check "$(sed 's/--repo [^ ]*repo /--repo R /' "$T/acct.calls")" "pick --repo R --json --cached" "  its pick was --cached"
unset ACCOUNT_CLAUDE; export ACCOUNTS_FILE="$T/no-accounts.json"; rm "$HOME/projects"

echo "refusals"
"$B/autofinish-run" "$R" > "$T/out" 2>&1; check "$?" "2" "the primary checkout is refused"
git -C "$R" worktree add -q "$T/plain" -b feature main
"$B/autofinish-run" "$T/plain" > "$T/out" 2>&1; check "$?" "2" "a branch that is not claude/* is refused"
has "$T/out" "not a claude/* branch" "  saying why"

echo "dry run"
next_tip "dry"; : > "$T/claude.calls"
cp "$STATE" "$T/state.before"
af --dry > "$T/out" 2>&1; check "$?" "0" "--dry exits 0"
has "$T/out" "would write $STATE" "  names the state it would write"
has "$T/out" "would write $LOCK: session" "  and the lock"
has "$T/out" "exec env CLAUDE_UNATTENDED=dispatch" "  dispatch's dry run: the runner's exec line"
has "$T/out" "--remote-control finish\\ ·\\ demo\\ ·\\ buildbox" "  with the whole claude command line"
check "$(wc -c < "$T/claude.calls" | tr -d ' ')" "0" "  starts nothing"
check "$(cmp -s "$STATE" "$T/state.before" && echo same || echo changed)" "same" "  writes no state"
check "$([ -f "$LOCK" ] && echo held || echo free)" "free" "  takes no lock"
af --dry --by yolo > "$T/out" 2>&1; check "$?" "0" "--by yolo (E12: the launch of a dispatch --yolo run)"
has "$T/out" "/finish\ $BR\ --unattended\ --yolo" "  asks /finish for --yolo, which follows the repo's merge key"
has "$T/out" "--undeny 'Bash(git push:*)'" "  and lifts the push denial for the launching run only"
cp "$T/out" "$T/out.yolo"
af --dry > "$T/out" 2>&1
grep -q -- "--unattended\\ --yolo" "$T/out"; check "$?" "1" "  any other caller: no --yolo"
check "$(grep -c -- "--undeny 'Bash(\*bin/pr merge\*)'" "$T/out") $(grep -c -- "--undeny 'Bash(\*bin/pr merge\*)'" "$T/out.yolo")" "1 0" \
  "  a yolo launch outside a merge: auto repo keeps bin/pr merge denied; any other lifts it"
check "$(grep -c -- "--undeny 'Bash(\*libexec/pr merge\*)'" "$T/out") $(grep -c -- "--undeny 'Bash(\*libexec/pr merge\*)'" "$T/out.yolo")" "1 0" \
  "  libexec/pr merge alike, the path /finish names with no overlay"

echo "--merge: the owner's up-front yes, carried into the run (override and typed only)"
af --dry --merge > "$T/out" 2>&1; check "$?" "0" "--merge --dry"
has "$T/out" "/finish\ $BR\ --unattended\ --merge" "  the prompt carries --merge"
has "$T/out" '"merge": true' "  and the state it would write says so"
check "$(cmp -s "$STATE" "$T/state.before" && echo same || echo changed)" "same" "  the dry run writes no state"
af --dry --merge --by typed > "$T/out" 2>&1; check "$?" "0" "  --by typed may carry it"
has "$T/out" "--unattended\ --merge" "  into the prompt"
for by in sweep chain yolo; do
  af --dry --merge --by $by > "$T/out" 2>&1; check "$?" "2" "  --by $by is refused"
  check "$(wc -l < "$T/out" | tr -d ' ')" "1" "    in one line"
  has "$T/out" "needs a person's yes" "    saying why"
done
CLAUDE_UNATTENDED=dispatch af --dry --merge > "$T/out" 2>&1; check "$?" "2" "  an unattended caller is refused"
has "$T/out" "unattended run" "    saying why"
af --dry > "$T/out" 2>&1
grep -q -- "--merge" "$T/out"; check "$?" "1" "a launch without it: no --merge in the prompt"
grep -q '"merge"' "$T/out"; check "$?" "1" "  and no merge key in the state"

echo "the lease (skipper-resilience S4): a launch acting for a leased ship (DISPATCH_SHIP) is fenced by its generation"
LB="$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import common; t = common.tool("leaselib.py"); print(t.parent if t else "")' "$CORE")"
if [ -z "$LB" ]; then echo "  --   skipped: helm's leaselib.py is not installed here"; else
  export PLANS_DIR="$T/plans"
  python3 - "$LB" <<'PY'
import sys; sys.path.insert(0, sys.argv[1]); import helmlib, leaselib
helmlib.new_plan("lp", "leased"); helmlib.new_plan("np", "unleased")
leaselib.write_yard("lp", "dock", "testhost", "the suite")
leaselib.take("lp", "dock", "skp-1", 99999, None)
PY
  af --dry > /dev/null 2>&1; rc0=$?
  DISPATCH_SHIP=np af --dry > "$T/out" 2>&1; check "$?" "$rc0" "DISPATCH_SHIP naming a ship with no lease: the dry run's exit as without it"
  hasnt "$T/out" "refused" "  nothing refused"
  hasnt "$T/out" "lease at gen" "  and no word of a lease"
  st0=$(cat "$STATE" 2>/dev/null)
  DISPATCH_SHIP=lp af --dry > "$T/out" 2>&1; check "$?" "4" "DISPATCH_SHIP naming a leased ship the caller does not hold: exit 4"
  has "$T/out" "autofinish-run: refused: lease at gen 1 held by skipper · dock — you are gen none; stand down (helm skipper --stand-down)" "  the spec's line"
  check "$(grep -c '"lease": "refused"' "$T/plans/lp/events.jsonl")" "0" "  a dry run writes no event"
  DISPATCH_SHIP=lp af > "$T/out" 2>&1; check "$?" "4" "  a real start: refused"
  check "$(grep -c '"lease": "refused"' "$T/plans/lp/events.jsonl")" "1" "    one 'refused' event in the ship"
  check "$(cat "$STATE" 2>/dev/null)" "$st0" "    and nothing written: its state is as it was"
  DISPATCH_PLAN=lp af --dry > /dev/null 2>&1; check "$?" "4" "  the older name, DISPATCH_PLAN, the same"
  DISPATCH_SHIP=lp SKIPPER_GEN=1 af --dry > /dev/null 2>&1; check "$?" "$rc0" "  SKIPPER_GEN at the lease's gen: the launch goes ahead"
  DISPATCH_SHIP=lp SKIPPER_GEN=0 af --dry > /dev/null 2>&1; check "$?" "4" "  SKIPPER_GEN stale: refused"
  unset PLANS_DIR
fi
next_tip "merge"
STUB_REPLY="$T/stop.txt" af --rule C --merge > "$T/out" 2>&1; check "$?" "0" "a real --merge start"
has "$T/out" "started: /finish $BR --unattended --merge" "  said what it started"
SID=$(field session); ended
check "$(field merge)" "True" "  autofinish.json carries merge: true"
grep "started session=${SID:0:8}" "$AFLOG" | grep -q " merge=yes "; check "$?" "0" "  and the log's start line says merge=yes"
has "$T/claude.calls" "/finish $BR --unattended --merge" "  and claude was given the prompt with --merge"
# its stub claude is gone before the next case looks for "the" claude it started (pgrep below)
for _ in $(seq 1 100); do pgrep -f "$T/claude /finish" > /dev/null || break; sleep 0.2; done
next_tip "after merge"

echo "a dispatch run of the branch: a warm one is ended first, a busy one stops the launch (D2: C)"
RS="$HOME/Library/Logs/claude-weekly/run-seed-runs"; mkdir -p "$RS" "$HOME/.claude/sessions"
sleep 120 & BP=$!
printf '{"mode":"headless","repo":"%s","topic":"demo","branch":"%s","pid":%s,"proc_start":"%s","session":"s-busy","started":%s}' \
  "$R" "$BR" $BP "$(TZ=UTC LC_ALL=C ps -o lstart= -p $BP | xargs)" "$(date +%s)" > "$RS/00000000-000077-repo.demo.json"
printf '{"pid":%s,"sessionId":"s-busy","status":"busy","statusUpdatedAt":%s}' $BP "$(( $(date +%s) * 1000 ))" > "$HOME/.claude/sessions/$BP.json"
af --dry > "$T/out" 2>&1; check "$?" "3" "a busy run of the branch: not started"
has "$T/out" "is busy (session s-busy)" "  saying which"
printf '{"pid":%s,"sessionId":"s-busy","status":"idle","statusUpdatedAt":%s}' $BP "$(( ($(date +%s) - 900) * 1000 ))" > "$HOME/.claude/sessions/$BP.json"
af --dry > "$T/out" 2>&1; check "$?" "0" "a warm one: the dry run goes on…"
has "$T/out" "would end the warm run of $BR" "  …naming the run it would end first"
kill $BP 2>/dev/null; wait $BP 2>/dev/null; rm -f "$RS/00000000-000077-repo.demo.json" "$HOME/.claude/sessions/$BP.json"

echo "a runner that died: dead() reads it, bury() records it, its tip starts once more (2026-10-07)"
next_tip "died"; DTIP=$(git -C "$W" rev-parse HEAD); : > "$T/api.log"; rm -f "$LOCK" "$GD/claude/autofinish"
DSID=dddddddd-0000-4000-8000-000000000000
RUNS="$LOGS/run-seed-runs"; mkdir -p "$RUNS"; DREC="$RUNS/finish-demo.dddddddd.json"
ME_START=$(TZ=UTC LC_ALL=C ps -o lstart= -p $$ | tr -s ' ' | sed 's/^ //; s/ $//')
# died <minutes since start>: the state a dead runner leaves — started, no outcome — its lock, its marker
died() {
  python3 - "$STATE" "$DSID" "$DTIP" "$1" <<'EOF'
import datetime, json, sys
iso = (datetime.datetime.now().astimezone() - datetime.timedelta(minutes=int(sys.argv[4]))).isoformat(timespec="seconds")
json.dump({"started": iso, "session": sys.argv[2], "tip": sys.argv[3], "by": "sweep", "rule": "D", "window": "finish · demo",
           "ended": None, "outcome": None, "pr": None, "gate": None}, open(sys.argv[1], "w"))
EOF
  printf '{"session": "%s", "branch": "%s", "seen": 0}' "$DSID" "$BR" > "$LOCK"; touch "$GD/claude/finishing"
}
# rec <pid> <proc_start> <watcher> <watcher_start> [ended epoch]: dispatch's record of the run
rec() { printf '{"session": "%s", "mode": "rc", "pid": "%s", "proc_start": "%s", "watcher": "%s", "watcher_start": "%s"%s, "last_status": "busy"}' \
          "$DSID" "$1" "$2" "$3" "$4" "${5:+, \"ended\": \"$5\"}" > "$DREC"; }
dead() { python3 - "$B/autofinish-run" "$W" <<'EOF'
import json, sys
from importlib.machinery import SourceFileLoader
m = SourceFileLoader("afr", sys.argv[1]).load_module()
t = m.Tree(sys.argv[2])
print(m.dead(t, m.read_state(t)) or "alive")
EOF
}
died 30
rec $$ "$ME_START" 99998 "Thu Jan  1 00:00:00 2026"; check "$(dead)" "alive" "its claude's pid alive with its start time: alive"
rec $$ "Thu Jan  1 00:00:00 2026" $$ "$ME_START"; check "$(dead)" "alive" "  its watcher alive: alive"
rec $$ "Thu Jan  1 00:00:00 2026" 99998 "Thu Jan  1 00:00:00 2026"
check "$(dead)" "claude (pid $$) and its watcher (pid 99998) are gone, and dispatch wrote no end" "a reused pid and a gone watcher: dead"
rec 99997 "" "" ""; check "$(dead)" "alive" "  no watcher recorded and a fresh record: alive (dispatch may be starting it)"
touch -t 202001010000 "$DREC"; check "$(dead)" "claude (pid 99997) and its watcher (pid never recorded) are gone, and dispatch wrote no end" "  an old one: dead"
rec 99997 "" 99998 "" $(( $(date +%s) - 60 )); check "$(dead)" "alive" "dispatch ended it a minute ago: its waiter is recording — alive"
rec 99997 "" 99998 "" $(( $(date +%s) - 1200 )); case "$(dead)" in "dispatch ended the run 20 min ago"*) echo "  ok     20 min ago and no outcome: dead";; *) echo "  FAIL ended 20 min: $(dead)"; fails=$((fails+1));; esac
rm -f "$DREC"; check "$(dead)" "no dispatch record 30 min after its start" "no dispatch record half an hour on: dead"
died 2; check "$(dead)" "alive" "  two minutes on: alive (it may not have reached dispatch)"
died 30; rm -f "$DREC"
printf '{"session": "%s", "pid": %s, "start": "%s"}' "$DSID" $$ "$ME_START" > "$GD/claude/autofinish-waiter.json"
deadsd() { python3 - "$B/autofinish-run" "$W" "$GD/claude" <<'EOF'
import sys
from importlib.machinery import SourceFileLoader
m = SourceFileLoader("afr", sys.argv[1]).load_module()
t = m.Tree(sys.argv[2])
print(m.dead(t, m.read_state(t), state_dir=sys.argv[3]) or "alive")
EOF
}
check "$(deadsd)" "alive" "its waiter still running (a Mac asleep before dispatch wrote its record): alive, whatever the clock (review 2026-10-08)"
printf '{"session": "%s", "pid": %s, "start": "Thu Jan  1 00:00:00 2026"}' "$DSID" $$ > "$GD/claude/autofinish-waiter.json"
check "$(deadsd)" "no dispatch record 30 min after its start" "  a waiter pid reused by another process: judged as before"
rm -f "$GD/claude/autofinish-waiter.json"

echo "  bury"
died 30; rec 99997 "" 99998 ""; touch -t 202001010000 "$DREC"
# named for the day the run started, as autofinish-run named it (half an hour ago may be yesterday)
DLOG="$LOGS/$(python3 -c 'import datetime; print((datetime.datetime.now() - datetime.timedelta(minutes=30)).date())')-dispatch-finish-demo.log"; printf 'dispatch: started\ndispatch: busy, step 11.2\n' > "$DLOG"
cp "$CD/claude/autofinished" "$T/record.before" 2>/dev/null || : > "$T/record.before"
bury() { python3 - "$B/autofinish-run" "$W" <<'EOF'
import sys
from importlib.machinery import SourceFileLoader
m = SourceFileLoader("afr", sys.argv[1]).load_module()
t = m.Tree(sys.argv[2])
print(m.bury(t, m.dead(t, m.read_state(t)) or "test") or "nothing")
EOF
}
bury > "$T/out" 2>&1
has "$T/out" "run repo $BR died session=dddddddd tip=${DTIP:0:7} rule=D by=sweep account=- — dispatch: busy, step 11.2" "returns the log line"
has "$AFLOG" "run repo $BR died session=dddddddd tip=${DTIP:0:7} rule=D by=sweep account=- — dispatch: busy, step 11.2; commented on #7" "  logged, with the comment"
check "$(field outcome):$(field gate):$([ "$(field ended)" != null ] && echo ended)" "died:null:ended" "  the state: died, ended, no gate"
check "$([ -f "$LOCK" ] && echo held || echo free):$([ -e "$GD/claude/finishing" ] && echo marker || echo none)" "free:none" "  the dead session's lock and marker gone"
diff "$T/record.before" "$CD/claude/autofinished" | grep '^>' | sed 's/^> [^ ]* //' > "$T/rec.new"
check "$(cat "$T/rec.new")" "died $BR ${DTIP:0:7} dispatch: busy, step 11.2" "  one line in autofinished: died <branch> <tip7> <dispatch's last line>"
has "$T/api.log" '"path": "/repos/test/repo/issues/7/comments"' "  one comment on the PR"
has "$T/api.log" "autofinish runner died" "    headed as a death"
has "$T/api.log" "the runner died before an outcome: the Mac lost power or the process was killed; nothing merged" "    in the brief's words"
check "$(bury)" "nothing" "a second bury finds it ended: nothing"
python3 - "$CORE" "$CD" <<'EOF' > "$T/out"
import sys
sys.path.insert(0, sys.argv[1])
import common
e = common.autofinished(sys.argv[2])[-1]
print(e["outcome"], common.autofinished_phrase(e))
print(common.autofinish_outcome({"outcome": "died"}))
EOF
has "$T/out" "died $BR died before an outcome at ${DTIP:0:7}: dispatch: busy, step 11.2" "common reads it: sync.py's line"
has "$T/out" "autofinish's runner died here before an outcome" "  and the old panel's prompt note"
died 30; printf '{"session": "someone-else", "branch": "%s", "seen": 0}' "$BR" > "$LOCK"; rm -f "$DREC"
bury > /dev/null 2>&1
has "$LOCK" '"session": "someone-else"' "a lock another session took since is left as it is"
check "$([ -e "$GD/claude/finishing" ] && echo marker || echo none)" "marker" "  and so is the marker"
rm -f "$LOCK" "$GD/claude/finishing"
died 30; rec 99997 "" 99998 "" $(( $(date +%s) - 1200 ))
out=$(bury 2>&1)
case "$out" in *"recorded after its waiter died"*) echo "  ok   dispatch ended it, only the waiter died: recorded from its reply, as the waiter would have (review 2026-10-08)";;
  *) echo "  FAIL waiter-only death: $out"; fails=$((fails+1));; esac
check "$([ "$(field outcome)" != died ] && echo "not died")" "not died" "  its outcome is the reply's, never died"
rm -f "$DREC"; died 30; bury > /dev/null 2>&1   # back to a died state for the start below
rm -f "$LOCK" "$GD/claude/finishing"
: > "$T/claude.calls"
STUB_REPLY="$T/stop.txt" af --rule D --by sweep > "$T/out" 2>&1; check "$?" "0" "a died tip is no same-tip refusal: it starts again"
ended

echo "--by chain: the chain manager's tick relaunches an S4 stop only, twice per tip (orchestration B3)"
CHAINF="$GD/claude/autofinish-chain.json"
af --dry --by chain > "$T/out" 2>&1; check "$?" "3" "the G4 stop just above: no chain relaunch"
has "$T/out" "ended stopped at G4, not stopped by the network — no chain relaunch" "  saying why"
printf 'API Error: Connection refused — a firewall or proxy may be blocking it (ECONNREFUSED)\n' > "$T/net.txt"
next_tip "chain: a network stop"; NTIP=$(git -C "$W" rev-parse HEAD)
STUB_REPLY="$T/net.txt" af --rule D --by sweep > /dev/null 2>&1; ended
check "$(field outcome)/$(field gate)" "stopped/no-landing" "a network stop: stopped at no-landing"
af --dry > "$T/out" 2>&1; check "$?" "3" "  every other caller: no retry on the same tip, as before"
STUB_REPLY="$T/net.txt" af --rule D --by chain > "$T/out" 2>&1; check "$?" "0" "--by chain relaunches it"
ended
check "$(field tip)/$(field by)" "$NTIP/chain" "  on the same tip, recorded by chain"
check "$(python3 -c 'import json, sys; d = json.load(open(sys.argv[1])); print(d["tip"] == sys.argv[2], len(d["sessions"]))' "$CHAINF" "$NTIP")" "True 1" \
  "  counted in autofinish-chain.json against this tip"
has "$AFLOG" "tip=${NTIP:0:7} rule=D by=chain via=chain account=" "  the log says the tick started it"
# a chain start dispatch refused before any session (refused) leaves the stop and is not counted
AUTOFINISH_DISPATCH="$T/dispatch-crash" af --rule D --by chain > /dev/null 2>&1; ended
check "$(field gate)" "refused" "a chain start dispatch refused…"
STUB_REPLY="$T/net.txt" af --rule D --by chain > "$T/out" 2>&1; check "$?" "0" "  …is no relaunch spent: the second starts"
ended
check "$(python3 -c 'import json, sys; print(len(json.load(open(sys.argv[1]))["sessions"]))' "$CHAINF")" "2" "  the file counts it once a later start ran: two, the refused one dropped"
af --dry --by chain > "$T/out" 2>&1; check "$?" "3" "a third chain relaunch on the tip is refused"
has "$T/out" "2 chain relaunches on this tip already" "  saying how many"
printf 'Not logged in · Please run /login\n' > "$T/login.txt"
next_tip "chain: a login stop"
STUB_REPLY="$T/login.txt" af --rule D --by sweep > /dev/null 2>&1; ended
af --dry --by chain > "$T/out" 2>&1; check "$?" "3" "a no-landing stop that is a login (LOGIN_RE), not the network: refused"
has "$T/out" "no network or sleep stop" "  saying so"
echo "  a yolo launch stopped by the network is relaunched as a yolo one"
next_tip "chain: yolo"
STUB_REPLY="$T/net.txt" af --rule C --by yolo > /dev/null 2>&1; ended
check "$(field by)/$(field gate)" "yolo/no-landing" "the yolo landing stopped at no-landing"
af --dry --by chain > "$T/out" 2>&1; check "$?" "0" "--by chain --dry"
has "$T/out" ", by yolo via=chain" "  runs it as yolo, the tick named"
has "$T/out" "/finish\ $BR\ --unattended\ --yolo" "  /finish --yolo again"
check "$(grep -c -- "--undeny 'Bash(\*bin/pr merge\*)'" "$T/out")" "0" "  and bin/pr merge still denied in a repo without merge: auto"
STUB_REPLY="$T/net.txt" af --rule C --by chain > /dev/null 2>&1; ended
check "$(field by)" "yolo" "  the state says yolo, so the next chain relaunch reads it as one"
rm -f "$CHAINF"

echo "the landing ladder (skipper-modes S3b): autofinish-run reads the mode from plan.json itself"
MRUNS="$HOME/Library/Logs/claude-weekly/run-seed-runs"; mkdir -p "$MRUNS"
modefix() { printf '{"branch": "%s", "started": 1, "task_mode": "%s", "repo": "%s"}\n' "$BR" "$1" "$R" > "$MRUNS/zz-mode.json"; }
undeny_merge() { grep -c -- "--undeny 'Bash(\*bin/pr merge\*)'" "$1"; }
has "$T/out.yolo" "mode none: held at a ready PR — mode default — a taken answer never lands there (yolo-veto D1)" \
  "no sent task: a yolo launch holds, as before (yolo-veto D1 for default)"
has "$T/out.yolo" "--unattended\ --yolo\ --hold" "  /finish is told --hold"
next_tip "modes: the dry runs"
modefix yolo
af --dry --by yolo > "$T/out" 2>&1; check "$?" "0" "mode yolo, --by yolo --dry"
has "$T/out" "mode yolo: may merge, past the check and the review gate" "  the ship in yolo: it may merge"
has "$T/out" "/finish\ $BR\ --unattended\ --yolo --session-id" "  no --hold"
check "$(undeny_merge "$T/out")" "1" "  bin/pr merge lifted for this run"
CLAUDE_UNATTENDED=dispatch af --dry --by yolo > "$T/out" 2>&1
has "$T/out" "mode yolo: may merge" "  an unattended caller gets what plan.json says: the mode, not its label, is the yes"
modefix dnd
af --dry --by dnd > "$T/out" 2>&1; check "$?" "0" "mode dnd, --by dnd --dry"
has "$T/out" "mode dnd: may merge" "  plain work in a physical: none repo lands under dnd"
has "$T/out" "/finish\ $BR\ --unattended\ --dnd --session-id" "  /finish is told --dnd"
af --dry --by yolo > "$T/out" 2>&1
has "$T/out" "mode dnd: may merge" "  a yolo launch of a ship lowered to dnd is judged by dnd's slice"
modefix default
CLAUDE_UNATTENDED=dispatch af --dry --by dnd > "$T/out" 2>&1
has "$T/out" "held at a ready PR — mode default — a taken answer never lands there" "an unattended --by dnd on a default ship: held (the label grants nothing)"
check "$(undeny_merge "$T/out")" "0" "  bin/pr merge denied"
modefix ask
af --dry --by sweep --rule A > "$T/out" 2>&1
has "$T/out" "mode ask: held at a ready PR — mode ask — nothing lands by itself" "mode ask: the sweep's rule A start holds"
has "$T/out" "/finish\ $BR\ --unattended\ --hold --session-id" "  /finish --unattended --hold"
check "$(undeny_merge "$T/out")" "0" "  bin/pr merge denied"
af --dry > "$T/out" 2>&1
has "$T/out" "mode ask: may merge" "  the owner's own /autofinish (override, attended) is no 'by itself': today's rules"
CLAUDE_UNATTENDED=dispatch af --dry > "$T/out" 2>&1
has "$T/out" "mode ask: held at a ready PR" "  the same label from an unattended caller holds"
printf "PR #7 is ready.\n\n⚠ step 11 — held: PR #7 waits for the owner's tap\n" > "$T/held.txt"
next_tip "held: mode ask"
STUB_REPLY="$T/held.txt" af --rule A --by sweep > /dev/null 2>&1; ended
check "$(field gate)/$(field hold)" "held/mode ask — nothing lands by itself" "a held run that stops at step 11: gate held, the class in the state"
has "$CD/claude/autofinished" "stopped $BR held held (mode ask — nothing lands by itself): ⚠ step 11 — held: PR #7 waits for the owner's tap" \
  "  the autofinished line names the class (the board's held card reads it)"
rm -f "$MRUNS/zz-mode.json"
echo "  E12's merge:auto standing yes: only for a yolo launch with no mode, from a caller who is no run (landing review 3, 4c)"
mauto() { python3 - "$B/autofinish-run" "$W" "$R" "$BR" <<'PYMA'
import sys
from importlib.machinery import SourceFileLoader
m = SourceFileLoader("autofinish_run_ma", sys.argv[1]).load_module()
m.merge_auto = lambda t: True
t = type("T", (), {"path": sys.argv[2], "primary": sys.argv[3], "branch": sys.argv[4]})()
print(m.landing(t, "yolo", "C")[0])
PYMA
}
check "$(mauto)" "None" "a yolo launch with no mode in a merge:auto repo, attended: may merge (E12)"
check "$(CLAUDE_UNATTENDED=dispatch mauto)" "mode default — a taken answer never lands there (yolo-veto D1)" \
  "  the same from an unattended caller (any run may type --by yolo): held"
modefix default
check "$(mauto)" "mode default — a taken answer never lands there (yolo-veto D1)" "  a ship lowered to default: held, the standing yes is for no mode only"
rm -f "$MRUNS/zz-mode.json"

echo "the sessions open on the branch are told, by the run's own session (the owner, 2026-10-18)"
next_tip "notify"; : > "$T/claude.calls"
sleep 300 & PANEL_PID=$!
PANEL=11111111-2222-4333-8444-555555555555
mkdir -p "$HOME/.claude/sessions"
sleep 300 & MUTE_PID=$!; sleep 300 & TWIN_PID=$!
MUTE=22222222-2222-4333-8444-555555555555
printf '{"pid":%s,"sessionId":"%s","cwd":"%s","status":"idle","name":"demo-panel","messagingSocketPath":"/tmp/cc-socks/x.sock"}' \
  $PANEL_PID $PANEL "$W" > "$HOME/.claude/sessions/$PANEL_PID.json"
printf '{"pid":%s,"sessionId":"%s","cwd":"%s","status":"idle","name":"demo-mute"}' \
  $MUTE_PID $MUTE "$W" > "$HOME/.claude/sessions/$MUTE_PID.json"
af --dry > "$T/out" 2>&1
has "$T/out" "autofinish-notify.json: tell 11111111, 22222222" "--dry says whom it would tell"
STUB_RUN=busy af --rule A --by sweep > /dev/null 2>&1
for _ in $(seq 1 50); do CP=$(pgrep -f "$T/claude /finish" | head -1); [ -n "$CP" ] && break; sleep 0.2; done
SID=$(field session)
# dispatch writes its record, rc_name and all, only after claude's pid is read: notify reads that
# name, so wait for the record too — on a loaded build Mac pgrep won the race (suites-host, 2026-10-20)
for _ in $(seq 1 50); do grep -qs '"rc_name"' "$LOGS"/run-seed-runs/*."${SID:0:8}".json && break; sleep 0.2; done
has "$GD/claude/autofinish-notify.json" "\"$PANEL\"" "the panels open on the worktree are recorded at the start"
hasnt "$T/claude.calls" "SendMessage" "  no allow rule for SendMessage: the classifier judges each send"
# a session elsewhere with the panel's name: ListAgents needs its row, not the bare name
printf '{"pid":%s,"sessionId":"33333333-2222-4333-8444-555555555555","cwd":"/elsewhere","status":"idle","name":"demo-panel","messagingSocketPath":"/tmp/cc-socks/y.sock"}' \
  $TWIN_PID > "$HOME/.claude/sessions/$TWIN_PID.json"
env -u CLAUDE_CODE_SESSION_ID "$B/autofinish-run" notify "$W" > "$T/out" 2>&1
has "$T/out" "nothing to send: the run on $BR is session ${SID:0:8}, not this one (no CLAUDE" "no session id: closed, nothing to send"
CLAUDE_CODE_SESSION_ID=$PANEL "$B/autofinish-run" notify "$W" > "$T/out" 2>&1
has "$T/out" "nothing to send: the run on $BR is session ${SID:0:8}, not this one" "another session gets no lines to send"
CLAUDE_CODE_SESSION_ID=$SID "$B/autofinish-run" notify "$W" > "$T/out" 2>&1; check "$?" "0" "notify, from the run's session"
has "$T/out" "SendMessage to demo-panel  — 1 other live session(s) share the name: send to the ListAgents row whose cwd is $W" "  names the panel, and its cwd where the name is shared"
has "$T/out" "skip demo-mute — binds no inbox" "  skips a session with no inbox, naming the backstop"
has "$T/out" "autofinish picked up this session's branch $BR" "  says the branch is taken"
has "$T/out" "The run: session $SID (ListAgents lists it by its cwd, $(git -C "$W" rev-parse --show-toplevel)), window and Remote Control \"finish · demo · buildbox\"" "  the run's id, how to find it, and the Remote Control name dispatch recorded"
has "$T/out" "rule A (by sweep)" "  its rule"
has "$T/out" "/autofinish off stops only the next start" "  and how to stop it, honestly"
has "$AFLOG" "notify session=${SID:0:8} asked=11111111 skipped=1" "  the day's log says who was asked"
CLAUDE_CODE_SESSION_ID=$SID "$B/autofinish-run" notify "$W" > "$T/out" 2>&1
has "$T/out" "nothing to send: the lines were printed at" "a second call prints nothing again"
sleep 1; kill -TERM "$CP"; ended
CLAUDE_CODE_SESSION_ID=$SID "$B/autofinish-run" notify "$W" > "$T/out" 2>&1
has "$T/out" "nothing to send: no autofinish run is under way" "an ended run sends nothing"
kill $PANEL_PID $MUTE_PID $TWIN_PID 2>/dev/null
rm -f "$HOME/.claude/sessions/$PANEL_PID.json" "$HOME/.claude/sessions/$MUTE_PID.json" "$HOME/.claude/sessions/$TWIN_PID.json"

echo "dispatch --start's own guards"
"$B/dispatch" --start p "$W" n --undeny 'Bash(nope)' --dry-run > "$T/out" 2>&1; check "$?" "2" "--undeny of an entry not on the list is refused"
"$B/dispatch" $BR --allow x > /dev/null 2>&1; check "$?" "2" "--allow without --start is refused"
"$B/dispatch" --start p "$W" n --at "2030-01-01 00:00" > /dev/null 2>&1; check "$?" "2" "--start with --at is refused"
# --launch: the old name, an alias for a week (S1 of docs/wharf-rename-2026-10-16.md; S8 drops it)
"$B/dispatch" --start p "$W" n --session-id 00000000-0000-4000-8000-000000000001 --dry-run > "$T/out-start" 2>&1; check "$?" "0" "--start --dry-run"
"$B/dispatch" --launch p "$W" n --session-id 00000000-0000-4000-8000-000000000001 --dry-run > "$T/out" 2>&1; check "$?" "0" "the alias --launch still starts"
check "$(diff "$T/out-start" "$T/out" > /dev/null && echo same || echo differs)" "same" "  …the very run --start would"
"$B/dispatch" --launch p "$W" n --at "2030-01-01 00:00" > "$T/out" 2>&1; check "$?" "2" "  …with --start's guards"
has "$T/out" "dispatch: --start takes no BRANCH" "  …saying --start, the word now"

[ "$fails" = 0 ] && echo "all ok" || { echo "$fails FAILED"; exit 1; }
