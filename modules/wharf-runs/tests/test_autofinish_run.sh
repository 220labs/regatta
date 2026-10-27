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
unset DISPATCH_SHIP DISPATCH_PLAN   # a ship's block running this suite: --by ship would read it as one (S6)
# …and by pattern, since a fixed list goes stale (AGENTS.md's attended-behaviour trap): every DISPATCH_*,
# RUN_SEED_*, SKIPPER_*, HELM_* and AUTOFINISH_* a run carries, its background switch, its session, and the
# registry a caller points at (the rotation's fence reads it)
for v in $(env | sed -nE 's/^((DISPATCH|RUN_SEED|SKIPPER|HELM|AUTOFINISH)_[A-Za-z0-9_]*)=.*/\1/p'); do unset "$v"; done
unset CLAUDE_CODE_DISABLE_BACKGROUND_TASKS CLAUDE_CODE_SESSION_ID CLAUDE_REPOS_JSON
# One day for every day-named log, the script's and the suite's alike (autofinish-run's AUTOFINISH_DAY):
# a case that crossed local midnight read the new day's empty file (a CI run at 00:00 PDT, 2026-10-26, the
# night-landings digest's finding 7). Set after the reset above, which unsets AUTOFINISH_*.
export AUTOFINISH_DAY="$(date +%Y-%m-%d)"
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
# a pinned blueprint is read by PyYAML, installed per user on these Macs: keep its site when HOME moves (--by ship, S6)
export PYTHONUSERBASE="${PYTHONUSERBASE:-$(python3 -m site --user-base)}"
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
# go idle, crash, or stay busy (and, on SIGTERM, leave its lock behind as R29 saw). The reply is compact
# JSON, as Claude Code writes it: dispatch-rc's replied() reads `"type":"assistant"`, and a spaced dump
# made every reply run wait out DISPATCH_START_WAIT and end "never started" (3 s a run, 27 runs)
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
  reply) python3 -c 'import json, sys; print(json.dumps({"type": "assistant", "message": {"content": [{"type": "text", "text": open(sys.argv[1]).read()}]}}, separators=(",", ":")))' "\$STUB_REPLY" > "\$HOME/.claude/projects/x/\$sid.jsonl"
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
  -S) case "\$*" in *quit*) pkill -TERM -f "run-seed/\${2#*.}.sh" 2>/dev/null;; esac;;
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
LOGS="$HOME/Library/Logs/claude-weekly"; AFLOG="$LOGS/autofinish-$AUTOFINISH_DAY.log"
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
# B14b (B14a's D1-A): the module tools /finish names and wharf's carried.py in the regatta main
# checkout, one rule per tool (never modules/*/bin/* wholesale: the landing review); a stand-in main
# checkout under ~ (never ~/projects: a later case links that to $T)
mkdir -p "$HOME/rg"; git init -q "$HOME/rg"
python3 - "$B/autofinish-run" "$HOME/rg" > "$T/rules" <<'PY'
import importlib.machinery, os, sys, types
af = importlib.machinery.SourceFileLoader("afr", sys.argv[1]).load_module()
af.common.regatta_root = lambda: af.pathlib.Path(sys.argv[2])
t = types.SimpleNamespace(branch="b", path="/w", window="finish · w", primary="/p")
for hold in (None, "ask"):
    cmd = af.start_cmd(t, "sid", hold=hold)
    for i, a in enumerate(cmd):
        if a in ("--allow", "--undeny"):
            print("%s %s %s" % (hold or "-", a, cmd[i + 1]))
PY
for r in "~/rg/modules/wharf/libexec/pr*" "python3 ~/rg/modules/keel/bin/keel*" "$HOME/rg/modules/wharf-runs/bin/check*" \
         "python3 $HOME/rg/modules/wharf/hooks/carried.py*" "~/rg/modules/regatta/bin/regatta which*"; do
  has "$T/rules" "- --allow Bash($r)" "  allowed in the regatta main checkout: $r"
done
check "$(grep -c -- '--allow Bash(.*modules/\*' "$T/rules")" "0" "  no wholesale modules/*/bin/* rule (it pre-approved clock, scope-pass, regatta pr merge)"
check "$(grep -c -F -- '- --undeny Bash(*regatta pr merge*)' "$T/rules") $(grep -c -F -- 'ask --undeny Bash(*regatta pr merge*)' "$T/rules")" "1 0" \
  "  a held launch keeps the core's regatta pr merge denied; any other lifts it"
check "$(python3 - "$B/autofinish-run" <<'PY'
import importlib.machinery, sys, types
af = importlib.machinery.SourceFileLoader("afr", sys.argv[1]).load_module()
af.common.regatta_root = lambda: None
cmd = af.start_cmd(types.SimpleNamespace(branch="b", path="/w", window="finish · w", primary="/p"), "sid")
print(sum(1 for i, a in enumerate(cmd) if a == "--allow" and "modules/" in cmd[i + 1]))
PY
)" "0" "  no regatta checkout (a plugin install): no such rule"
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
has "$HOME/Library/Logs/claude-weekly/$AUTOFINISH_DAY-dispatch-finish-demo.log" "claude exited by itself" "  the watcher saw claude go"

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
for _ in $(seq 1 25); do kill -0 "$CP" 2>/dev/null || break; sleep 0.1; done   # a poll, not a flat 0.5 s: the check decides
kill -0 "$CP" 2>/dev/null; check "$?" "1" "  …whose waiter is ended: its session is ended first"
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
  DISPATCH_SHIP= DISPATCH_PLAN=lp af --dry > /dev/null 2>&1; check "$?" "4" "  the older name, DISPATCH_PLAN, the same (DISPATCH_SHIP cleared: a managed run exports it)"
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
echo "  a brief launch stays one on a chain relaunch, and a relaunch carries the hold (autofinish-exclude landing review, finding 5)"
next_tip "chain: brief"
BRIEFF="$(git -C "$W" rev-parse --path-format=absolute --git-common-dir)/claude/autofinish-briefs/$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$BR").json"
mkdir -p "$(dirname "$BRIEFF")"; echo '{}' > "$BRIEFF"
STUB_REPLY="$T/net.txt" af --rule C --by brief > /dev/null 2>&1; ended
check "$(field by)/$(field gate):$([ -e "$BRIEFF" ] && echo there || echo gone)" "brief/no-landing:gone" \
  "the brief landing stopped at no-landing, and the yes at the brief is used up (finding 7)"
af --dry --by chain > "$T/out" 2>&1; check "$?" "0" "--by chain --dry"
has "$T/out" ", by brief via=chain" "  runs it as brief: landing() and bin/pr judge it by brief_held again"
python3 - "$STATE" <<'PYH'
import json, sys
d = json.load(open(sys.argv[1])); d.update(by="sweep", hold="held for the test"); json.dump(d, open(sys.argv[1], "w"))
PYH
af --dry --by chain > "$T/out" 2>&1
has "$T/out" "held at a ready PR — held for the test" "  a run held at its start: the chain relaunch keeps the hold"
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
has "$T/out" '"eff_mode": "dnd"' "  autofinish.json records the mode landing() judged it by (follow-ups item 4)"
has "$T/out" '"land_mode": "dnd"' "  …and the branch's mode it read, which bin/pr names beside the mode now (follow-ups' landing review, item 8)"
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
mauto() { python3 - "$B/autofinish-run" "$W" "$R" "$BR" "$@" <<'PYMA'
import sys
from importlib.machinery import SourceFileLoader
m = SourceFileLoader("autofinish_run_ma", sys.argv[1]).load_module()
m.merge_auto = lambda t: True
t = type("T", (), {"path": sys.argv[2], "primary": sys.argv[3], "branch": sys.argv[4]})()
print(m.landing(t, "yolo", "C")[int(sys.argv[5]) if len(sys.argv) > 5 else 0])
PYMA
}
check "$(mauto)" "None" "a yolo launch with no mode in a merge:auto repo, attended: may merge (E12)"
check "$(mauto 2)" "yolo" "  its eff_mode is yolo, for bin/pr's re-check (follow-ups item 4)"
check "$(CLAUDE_UNATTENDED=dispatch mauto 2)" "None" "  from an unattended caller: no eff_mode, so bin/pr holds it too"
check "$(CLAUDE_UNATTENDED=dispatch mauto)" "mode default — a taken answer never lands there (yolo-veto D1)" \
  "  the same from an unattended caller (any run may type --by yolo): held"
modefix default
check "$(mauto)" "mode default — a taken answer never lands there (yolo-veto D1)" "  a ship lowered to default: held, the standing yes is for no mode only"
rm -f "$MRUNS/zz-mode.json"
echo "  a ship launch is judged by held_slice too: the keel's yes predates the diff (S6's finish review)"
shipland() { python3 - "$B/autofinish-run" "$W" "$R" "$BR" "$1" "$2" <<'PYSL'
import sys
from importlib.machinery import SourceFileLoader
m = SourceFileLoader("autofinish_run_sl", sys.argv[1]).load_module()
real = SourceFileLoader("autofinish_sl", sys.argv[1].rsplit("/", 1)[0] + "/autofinish").load_module()
class Af:
    LAND_MODES = ("yolo", "dnd")
    effective_mode = staticmethod(real.effective_mode)   # the one rule, shared with bin/pr (item 8)
    mode_unreadable = staticmethod(real.mode_unreadable)
    def landing_mode(self, branch, repo):
        if sys.argv[6] == "!":
            return None, "the mode is unreadable (RuntimeError)"
        return (None, "no sent task") if sys.argv[6] == "-" else (sys.argv[6], "ship s")
    def held_slice(self, repo, wt, main, mode): return "gated under %s" % mode
m._lander = (lambda: None) if sys.argv[5] == "absent" else (lambda: Af())
t = type("T", (), {"path": sys.argv[2], "primary": sys.argv[3], "branch": sys.argv[4]})()
print(m.landing(t, "ship", "C")[0])
PYSL
}
check "$(shipland af -)" "gated under yolo" "a --by ship launch with no landing mode: held_slice under yolo (the gates, autofinish_exclude, in_place)"
check "$(shipland af dnd)" "gated under dnd" "  a ship in dnd: dnd's held slice"
check "$(shipland absent -)" "the lander's judge did not load (bin/autofinish)" "  the lander absent: held, never merged unjudged"
echo "  a brief launch is judged by brief_held: the yes at the brief predates the diff (autofinish-exclude S7)"
briefland() { python3 - "$B/autofinish-run" "$W" "$R" "$BR" "$1" "$2" <<'PYBL'
import sys
from importlib.machinery import SourceFileLoader
m = SourceFileLoader("autofinish_run_bl", sys.argv[1]).load_module()
class Af:
    LAND_MODES = ("yolo", "dnd")
    def landing_mode(self, branch, repo): return (None if sys.argv[6] == "-" else sys.argv[6], "the mode")
    def mode_unreadable(self, why): return False
    def brief_held(self, repo, wt, main): return None if sys.argv[5] == "lands" else "a held path (leak/l.py)"
    def held_slice(self, repo, wt, main, mode): return "held_slice was asked"
m._lander = (lambda: None) if sys.argv[5] == "absent" else (lambda: Af())
t = type("T", (), {"path": sys.argv[2], "primary": sys.argv[3], "branch": sys.argv[4]})()
print(m.landing(t, "brief", "C")[0])
PYBL
}
check "$(briefland lands -)" "None" "a --by brief launch whose diff is class 1 or 3: may merge"
check "$(briefland held -)" "a held path (leak/l.py)" "  class 2 or the list in the diff: held at a ready PR, by brief_held, not held_slice"
check "$(briefland lands ask)" "mode ask — nothing lands by itself" "  mode ask holds it: the yes at the brief is no person at the keyboard"
check "$(briefland absent -)" "the lander's judge did not load (bin/autofinish)" "  the lander absent: held"
check "$(shipland af !)" "the mode is unreadable now (the mode is unreadable (RuntimeError))" \
  "  a mode the start cannot read: held, never judged yolo as no mode (the second landing review)"

echo "--hold: the keel's no (skipper-resilience S6), whatever the mode"
next_tip "s6: hold"
af --dry --hold > "$T/out" 2>&1; check "$?" "0" "--hold --dry"
has "$T/out" "/finish\ $BR\ --unattended\ --hold --session-id" "  /finish <branch> --unattended --hold"
has "$T/out" '"hold": "the keel holds it (--hold)"' "  the state's hold says the keel holds it"
check "$(undeny_merge "$T/out")" "0" "  bin/pr merge stays denied"
af --dry --hold --merge > "$T/out" 2>&1; check "$?" "2" "--hold with --merge: refused"
has "$T/out" "ask opposite things" "  saying why"
af --dry --digest "$(printf '%064d' 0)" > "$T/out" 2>&1; check "$?" "2" "--digest without --by ship: refused"
SKIPPER_SCOPE=dock af --dry --merge > "$T/out" 2>&1; check "$?" "2" "--merge from a skipper (SKIPPER_SCOPE): refused as an unattended run is"
has "$T/out" "SKIPPER_SCOPE=dock" "  naming it"
AUTOFINISH_CALLER_UNATTENDED=1 af --dry --merge > "$T/out" 2>&1; check "$?" "2" "--merge under AUTOFINISH_CALLER_UNATTENDED: refused, never sent to fall back here"
has "$T/out" "AUTOFINISH_CALLER_UNATTENDED=1" "  naming it"

echo "--by ship: the keel's yes, read again from the plan store (S6)"
if [ -z "$LB" ]; then echo "  --   skipped: helm's helmlib.py is not installed here"; else
  export PLANS_DIR="$T/shipplans"
  # the tick's caller: no session id; the suite's af() is a session's
  afs() { env -u CLAUDE_CODE_SESSION_ID CLAUDE_CODE_CHILD_SESSION=1 "$B/autofinish-run" "$W" "$@"; }
  # shipfix <plan> <ship> <front-matter line> <laid mode> <keel merge> <block branch>: a pinned ship as --yard records it; prints the digest
  # the pin's repo is the registry key of the suite's repo, as --yard pins it; "elsewhere" names another repo
  RKEY=$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import common; print(common.repo_key(sys.argv[2]))' "$CORE" "$R")
  shipfix() { python3 - "$LB" "$B" "$RKEY" "$@" <<'PYS'
import json, os, sys
sys.path.insert(0, sys.argv[1]); sys.path.insert(0, sys.argv[2])
import helmlib, blueprintlib
rkey = sys.argv[3]
pid, ship, extra, laid, keel, branch = sys.argv[4:10]
if len(sys.argv) > 10:
    rkey = sys.argv[10]
helmlib.new_plan(pid, ship)
copy = os.path.join(str(helmlib.plan_dir(pid)), "blueprint-%s.md" % ship)
text = ("---\nship: %s\nrepo: demo\ncreated: 2026-10-05\n%sblocks:\n  - id: demo\n    provider: orca\n    agent: claude\n"
        "    branch: %s\n---\n## demo\nTask: t\nTier: worker\nWhy: w\nStart here: s\nDone means: d\nNot this: n\n") % (
        ship, extra.replace("\\n", "\n"), branch)
open(copy, "w").write(text)
d = blueprintlib.digest(blueprintlib.load(copy, key=rkey))
p = helmlib.load_plan(pid)
p.setdefault("blueprints", {})[ship] = {"file": copy, "digest": d, "pin": {"repo": rkey, "branch": "b", "rel": "r.md", "digest": d},
                                        "laid_by": {"mode": laid, "depth": 0, "session": None, "host": "h", "t": 1},
                                        "merge": {"value": keel, "why": "default" if keel == "yes" else "keel"}}
helmlib.save_plan(p)
print(d)
PYS
}
  DY=$(shipfix sy ship-yes '' attended yes "$BR")
  DN=$(shipfix sn ship-no 'merge: no\n' attended yes "$BR")
  DU=$(shipfix su ship-un '' unattended yes "$BR")
  DK=$(shipfix sk ship-keel '' attended no "$BR")
  DB=$(shipfix sb ship-other '' attended yes claude/laptop/2026-10-05-other)
  DR=$(shipfix sr ship-repo 'sent_by: x\n' attended yes "$BR" elsewhere)
  check "$(printf '%s\n' "$DY" "$DN" "$DU" "$DK" "$DB" "$DR" | sort -u | grep -c '^[0-9a-f]\{64\}$')" "6" "(the fixture: six ships, six digests)"
  afs --dry --merge --by ship --digest "$DY" > "$T/out" 2>&1; check "$?" "0" "the tick's --merge --by ship --digest at an attended, merge-yes pin: accepted"
  has "$T/out" "/finish\ $BR\ --unattended\ --merge" "  the prompt carries --merge"
  check "$(undeny_merge "$T/out")" "1" "  bin/pr merge lifted"
  afs --dry --merge --by ship > "$T/out" 2>&1; check "$?" "2" "  without --digest: refused"
  has "$T/out" "--by ship needs --digest D" "    saying so"
  for env_ in CLAUDE_CODE_SESSION_ID=s-1 CLAUDE_UNATTENDED=dispatch SKIPPER_SCOPE=dock DISPATCH_DEPTH=1 DISPATCH_SHIP=sy DISPATCH_PLAN=sy; do
    # --hold, not --merge (which refuses CLAUDE_UNATTENDED and SKIPPER_SCOPE on its own, above), and no session id
    # of the suite's own (a /finish runs this check inside one): --by ship's own check, naming the marker it read
    env -u CLAUDE_CODE_SESSION_ID "$env_" "$B/autofinish-run" "$W" --dry --by ship --hold > "$T/out" 2>&1
    check "$?" "2" "  from a caller that is not the tick ($env_): refused"
    has "$T/out" "is the yard's tick's, and this caller is " "    saying whose it is"
    has "$T/out" "$env_" "    naming $env_"
  done
  afs --dry --by ship > "$T/out" 2>&1; check "$?" "2" "--by ship with neither --merge nor --hold: refused"
  has "$T/out" "the tick's landing call: --merge --digest D, or --hold" "  saying so"
  afs --dry --by ship --hold --digest "$DY" > "$T/out" 2>&1; check "$?" "2" "  --digest with --hold: refused (it goes with --merge)"
  afs --dry --by ship --hold > "$T/out" 2>&1; check "$?" "0" "the tick's --by ship --hold: accepted, no digest asked"
  has "$T/out" "/finish\ $BR\ --unattended\ --hold --session-id" "  /finish --unattended --hold"
  check "$(undeny_merge "$T/out")" "0" "  bin/pr merge denied"
  afs --dry --merge --by ship --digest "$DR" > "$T/out" 2>&1; check "$?" "2" "a pin of another repo whose block branch has this name: refused"
  has "$T/out" "is not in ship ship-repo of plan sr's repo elsewhere" "  saying so (a branch name repeats across repos)"
  afs --dry --merge --by ship --digest "$DN" > "$T/out" 2>&1; check "$?" "2" "a digest whose blueprint says merge: no: refused"
  has "$T/out" "blueprint says merge: no" "  saying so"
  afs --dry --merge --by ship --digest "$DU" > "$T/out" 2>&1; check "$?" "2" "laid_by unattended: refused"
  has "$T/out" "was laid unattended" "  saying so"
  afs --dry --merge --by ship --digest "$DK" > "$T/out" 2>&1; check "$?" "2" "the keel said no (--no-merge): refused"
  has "$T/out" "keel said no" "  saying so"
  afs --dry --merge --by ship --digest "$DB" > "$T/out" 2>&1; check "$?" "2" "a ship whose blocks do not own this branch: refused"
  has "$T/out" "is no block branch of ship ship-other" "  saying so"
  afs --dry --merge --by ship --digest "$(printf '%064d' 7)" > "$T/out" 2>&1; check "$?" "2" "a digest no ship here is pinned at: refused"
  echo tampered >> "$T/shipplans/sy/blueprint-ship-yes.md"
  afs --dry --merge --by ship --digest "$DY" > "$T/out" 2>&1; check "$?" "2" "a pinned copy no longer at its digest: refused"
  has "$T/out" "is not at" "  saying so"
  echo "  the keel's hold is sticky: a later launch of the worktree keeps it"
  next_tip "s6: sticky hold"
  STUB_REPLY="$T/held.txt" afs --rule C --by ship --hold > /dev/null 2>&1; ended
  check "$(field hold)" "the keel holds it (--hold)" "a real --by ship --hold start: the state's hold"
  next_tip "s6: the sweep's retry"
  af --dry --by sweep --rule A > "$T/out" 2>&1
  has "$T/out" "held at a ready PR — the keel holds it (--hold)" "  the sweep's next start on the worktree: still held"
  has "$T/out" "--unattended\ --hold --session-id" "    /finish --unattended --hold"
  af --dry --merge > "$T/out" 2>&1
  hasnt "$T/out" "--hold --merge" "  a person's --merge beside the keel's hold: no --merge in the prompt"
  python3 -c 'import json, sys; d = json.load(open(sys.argv[1])); d["hold"] = "mode ask — nothing lands by itself"; json.dump(d, open(sys.argv[1], "w"))' "$STATE"
  next_tip "s6: the keel's hold under another hold"
  af --dry --by sweep --rule A > "$T/out" 2>&1
  has "$T/out" "held at a ready PR — the keel holds it (--hold)" "  a hold recorded for another reason first: the keel's own key keeps it"
  rm -f "$STATE"   # the keel's hold is this fixture's alone: the cases below start from a worktree with no launch
  unset PLANS_DIR; unset -f afs shipfix
fi

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

echo "the finisher rotation: a coin per start, the fence first, one row per run (S2 of docs/bench-continuous-2026-10-24.md)"
ROT="$T/config/wharf-runs/finisher-rotation"; ROWS="$LOGS/finisher-rotation.jsonl"
rows() { if [ -f "$ROWS" ]; then wc -l < "$ROWS" | tr -d ' '; else echo 0; fi; }
reg() { printf '{"repos": {}, "scopes": {"work": {"repos": ["*/repo", "*/repo2"]%s}}}\n' "$1" > "$T/repos.json"; }
armof() { python3 -c 'import json, sys; a = json.load(open(sys.argv[1])).get("arm"); print("none" if a is None else "%s %s %s" % (a["name"], a["coin"], a["forced"]))' "$STATE"; }
export CLAUDE_REPOS_JSON="$T/repos.json"; reg ""
next_tip "rotation: the dry runs"   # a tip no run ended on: the same-tip refusal would print nothing else
af --dry > "$T/out" 2>&1
has "$T/out" "finisher today's: rotation off: no wharf-runs/finisher-rotation" "no key: today's finisher"
hasnt "$T/out" "--model claude-" "  no model flag: dispatch's default, as before"
echo "until 2020-01-01" > "$ROT"
af --dry > "$T/out" 2>&1
has "$T/out" "finisher today's: rotation off: it ended 2020-01-01" "a window that has passed: today's finisher, by itself"
echo "soon" > "$ROT"
af --dry > "$T/out" 2>&1
has "$T/out" "rotation off: wharf-runs/finisher-rotation says 'soon', not \`until YYYY-MM-DD\`" "a line that does not parse: off, and says why"
echo "until 2099-12-31" > "$ROT"
AUTOFINISH_COIN=1 af --dry > "$T/out" 2>&1
has "$T/out" "finisher sonnet-medium (claude-sonnet-5-5, medium): rotation on until 2099-12-31; coin 1: sonnet-medium" "in the window, coin 1: Sonnet 5.5 at medium"
has "$T/out" "--model claude-sonnet-5-5 --effort medium" "  passed to dispatch by full id"
echo "2099-12-31" > "$ROT"
AUTOFINISH_COIN=0 af --dry > "$T/out" 2>&1
has "$T/out" "finisher opus-medium (claude-opus-5-5, medium)" "coin 0: today's finisher spelled out, Opus 5.5 at medium (a bare date reads too)"
has "$T/out" "--model claude-opus-5-5 --effort medium" "  with the same flags as the other arm"
printf 'until\n2099-12-31\n' > "$ROT"   # bootstrap.sh's config_values: one word per line
AUTOFINISH_COIN=1 af --dry > "$T/out" 2>&1
has "$T/out" "rotation on until 2099-12-31; coin 1: sonnet-medium" "the key as bootstrap.sh writes it, a word per line: on"
printf '{"repos": {}, "scopes": {"home": {"repos": ["*/repo"]}, "work": {"repos": ["*/repo"], "confidential": true}}}\n' > "$T/repos.json"
af --dry > "$T/out" 2>&1
has "$T/out" "rotation fenced: scope work is confidential" "a repo in an open scope and a confidential one: fenced, not only the first scope judged"
printf '{"repos": {}, "scopes": {"work": {"repos": 5}}}\n' > "$T/repos.json"
af --dry > "$T/out" 2>&1
has "$T/out" "rotation fenced: the scope registry does not walk (TypeError)" "a scope whose repos is no list: fenced, never a crashed start"
reg ""
check "$(python3 - "$B/autofinish-run" "$R" <<'PY'
import collections, importlib.machinery, sys, types
af = importlib.machinery.SourceFileLoader("afr", sys.argv[1]).load_module()
t = types.SimpleNamespace(primary=sys.argv[2])
n = collections.Counter(af.draw_arm(t)[0]["name"] for _ in range(64))
print(" ".join(sorted(n)) if min(n.values()) >= 10 else n)
PY
)" "opus-medium sonnet-medium" "an unforced coin draws both arms (64 draws, each at least 10)"

next_tip "rotation: sonnet"; : > "$T/claude.calls"; N0=$(rows)
AUTOFINISH_COIN=1 STUB_REPLY="$T/stop.txt" af --rule A --by sweep > "$T/out" 2>&1; check "$?" "0" "a start in the window"
ended; SID=$(field session)
has "$T/claude.calls" "--model claude-sonnet-5-5 --effort medium" "  claude ran the drawn arm"
check "$(armof)" "sonnet-medium 1 True" "  the state's arm: name, coin, forced"
has "$AFLOG" "by=sweep arm=sonnet-medium account=" "  the start's log line names it"
check "$(rows)" "$((N0 + 1))" "  one row at the end"
check "$(tail -1 "$ROWS" | python3 -c '
import json, sys
r = json.load(sys.stdin)
print(r["arm"], r["coin"], r["forced"], r["model"], r["effort"], r["outcome"], r["gate"], r["pr"], r["host"], r["repo"], r["session"] == sys.argv[1], r["voided"], r["fix_48h"])' "$SID")" \
  "sonnet-medium 1 True claude-sonnet-5-5 medium stopped G4 7 buildbox repo True no-reply None" "  the row: coin, arm, model, outcome, gate, PR, host; the stub returns no model (no-reply); the fix read later"

reg ', "confidential": true'
next_tip "rotation: confidential"; : > "$T/claude.calls"; N0=$(rows)
af --dry > "$T/out" 2>&1
has "$T/out" "finisher today's: rotation fenced: scope work is confidential — today's finisher, no row" "a confidential scope: today's finisher"
AUTOFINISH_COIN=1 STUB_REPLY="$T/stop.txt" af --rule A --by sweep > /dev/null 2>&1; ended
hasnt "$T/claude.calls" "--model claude-" "  no arm passed, whatever the coin"
check "$(armof)" "none" "  no arm in the state"
has "$AFLOG" "arm=off (rotation fenced: scope work is confidential" "  the key there, no arm: the start line says why"
check "$(rows)" "$N0" "  and no row"
next_tip "rotation: fenced dry runs"
printf '{"repos": {}, "scopes": {"work": {"repos": ["*/other"]}}}\n' > "$T/repos.json"
af --dry > "$T/out" 2>&1
has "$T/out" "rotation fenced: repo is in no scope" "a repo in no scope: fenced, never known not to be confidential"
printf '{"repos": {}, "scopes": {<<<<<<< HEAD\n' > "$T/repos.json"
af --dry > "$T/out" 2>&1
has "$T/out" "rotation fenced: the scope registry does not read" "a torn registry: fenced, not open"
"$B/autofinish-run" rotation > "$T/out" 2>&1; check "$?" "3" "  and the rows are not shown (exit 3)"

reg ""
next_tip "rotation: fenced mid-run"; N0=$(rows)
AUTOFINISH_COIN=0 STUB_RUN=busy af --rule A --by sweep > /dev/null 2>&1
for _ in $(seq 1 50); do CP=$(pgrep -f "$T/claude /finish" | head -1); [ -n "$CP" ] && break; sleep 0.2; done
check "$(armof)" "opus-medium 0 True" "a run that drew its arm in an open scope…"
reg ', "confidential": true'
sleep 1; kill -TERM "$CP"; ended
check "$(rows)" "$N0" "  …writes no row once the scope turned confidential"
has "$AFLOG" "no rotation row: scope work is confidential" "  and its end line says so"

reg ""
mkdir -p "$CLAUDE_CONFIG_DIR/projects/cost/s1/subagents"
cat > "$T/cost.py" <<'PY'
import importlib.machinery, json, os, sys, types
af = importlib.machinery.SourceFileLoader("afr", sys.argv[1]).load_module()
d = os.path.join(os.environ["CLAUDE_CONFIG_DIR"], "projects", "cost")
def a(model, rid, inp, out):
    return json.dumps({"type": "assistant", "requestId": rid, "message": {"model": model, "usage": {
        "input_tokens": inp, "output_tokens": out, "cache_read_input_tokens": 0, "cache_creation_input_tokens": 0}}})
with open(os.path.join(d, "s1.jsonl"), "w") as f:   # a streamed reply's last block counts; <synthetic> never
    f.write("\n".join([a("claude-sonnet-5-5", "r1", 1000, 10), a("claude-sonnet-5-5", "r1", 1000, 100),
                       a("claude-haiku-5-5", "r2", 500, 5), a("<synthetic>", "r3", 0, 0)]) + "\n")
with open(os.path.join(d, "s1", "subagents", "agent-x.jsonl"), "w") as f:
    f.write(a("claude-opus-5-5", "r9", 1000000, 0) + "\n")
print(json.dumps(af.transcript_cost("s1"), sort_keys=True))
t = types.SimpleNamespace(primary=sys.argv[2], repo="repo", branch="b", tip="0" * 40, path=sys.argv[2])
for name, model in (("sonnet-medium", "claude-sonnet-5-5"), ("opus-medium", "claude-opus-5-5")):
    af.rotation_row(t, {"session": "s1", "arm": {"name": name, "model": model, "effort": "medium", "coin": 0}}, "launched", None, 9)
    with open(os.path.join(af.LOGS, af.ROTATION_LOG)) as f:
        r = json.loads(f.readlines()[-1])
    print(name, r["voided"], r["models_unrequested"], r["cost_usd"], r["agents_cost_usd"])
af.rotation_row(t, {"session": "no-such", "arm": {"name": "sonnet-medium", "model": "claude-sonnet-5-5", "coin": 1}}, "never-started", "never-started", None)
with open(os.path.join(af.LOGS, af.ROTATION_LOG)) as f:
    r = json.loads(f.readlines()[-1])
print("silent", r["voided"])
PY
python3 "$T/cost.py" "$B/autofinish-run" "$R" > "$T/out" 2>&1
has "$T/out" '{"agents_cost_usd": 4.0, "cost_usd": 0.0031, "models": {"claude-haiku-5-5": 505, "claude-sonnet-5-5": 1100}}' "the cost from the transcript, at usage-report's prices, the agents apart"
has "$T/out" "sonnet-medium None ['claude-haiku-5-5'] 0.0031 4.0" "  a row in the arm's model: scored, the unrequested model named"
has "$T/out" "opus-medium fallback ['claude-haiku-5-5', 'claude-sonnet-5-5'] 0.0031 4.0" "  a session that never answered in its arm's model: voided, fallback"
has "$T/out" "silent no-reply" "  a session that returned no model at all: voided, no-reply"
cat > "$T/drop.py" <<'PY'
import json, sys   # the cost case's rows are no part of the settle cases below
with open(sys.argv[1]) as f:
    keep = [l for l in f if json.loads(l).get("branch") != "b"]
with open(sys.argv[1], "w") as f:
    f.writelines(keep)
PY
python3 "$T/drop.py" "$ROWS"

R2="$T/repo2"; git init -q -b main "$R2"; git -C "$R2" config user.email t@t; git -C "$R2" config user.name t
c2() { echo "$1" >> "$R2/$2"; git -C "$R2" add "$2"; GIT_AUTHOR_DATE="$3" GIT_COMMITTER_DATE="$3" git -C "$R2" commit -qm "$4"; }
c2 a f 2026-09-30T00:00:00Z "init"
c2 b f 2026-10-01T00:00:00Z "the work"
c2 c f 2026-10-01T05:00:00Z "Wharf: fix the demo's stop"
c2 d g 2026-10-01T06:00:00Z "Other: a fix in a file the landing never touched"
c2 e f 2026-10-02T01:00:00Z "Docs: the demo's line"
c2 h f 2026-10-04T00:00:00Z "Wharf: fix after the window"
git -C "$R2" update-ref refs/remotes/origin/main main
for pr in 42 43; do
  printf '{"ts": "2026-10-01T00:00:00-07:00", "host": "laptop", "repo": "repo2", "primary": "%s", "slug": "test/repo2", "main": "main", "branch": "b%s", "arm": "opus-medium", "outcome": "launched", "pr": %s, "cost_usd": 1.5, "settled": null}\n' "$R2" $pr $pr >> "$ROWS"
done
# 44's window ends 2026-10-05, past origin/main's tip: a stale ref is no read; the forced row is no draw
printf '{"ts": "2026-10-03T00:00:00-07:00", "host": "other", "repo": "repo2", "primary": "%s", "slug": "test/repo2", "main": "main", "branch": "b44", "arm": "opus-medium", "outcome": "launched", "pr": 44, "settled": null}\n' "$R2" >> "$ROWS"
printf '{"ts": "2026-10-03T00:00:00-07:00", "host": "other", "repo": "repo2", "primary": "%s", "slug": "test/repo2", "main": "main", "branch": "b45", "arm": "sonnet-medium", "forced": true, "outcome": "stopped", "gate": "G4", "settled": null}\n' "$R2" >> "$ROWS"
cat > "$T/api_settle.py" <<'PY'
import datetime
def api(method, path, body=None, tok=None, timeout=15):
    if path == "/repos/test/repo2/pulls/42":
        return 200, {"merged_at": "2026-10-01T00:00:00Z"}
    if path == "/repos/test/repo2/pulls/43":   # merged an hour ago: its 48 h are still open
        return 200, {"merged_at": (datetime.datetime.utcnow() - datetime.timedelta(hours=1)).strftime("%Y-%m-%dT%H:%M:%SZ")}
    if path == "/repos/test/repo2/pulls/44":
        return 200, {"merged_at": "2026-10-03T00:00:00Z"}
    if path.startswith("/repos/test/repo2/pulls/4") and "/files" in path:
        return 200, [{"filename": "f"}]
    if path.startswith("/repos/test/repo2/pulls/4") and "/commits" in path:
        return 200, [{"commit": {"message": "the work\n\nPrompt: build it"}}]
    return 404, None
PY
AUTOFINISH_API_STUB="$T/api_settle.py" "$B/autofinish-run" rotation --settle > "$T/out" 2>&1; check "$?" "0" "rotation --settle"
has "$T/out" "1 settled now" "  settles the launch 48 h past its merge, not the young one"
check "$(grep '"b42"' "$ROWS" | python3 -c 'import json, sys; r = json.load(sys.stdin); print(r["touched_48h"], r["fix_48h"], bool(r["settled"]))')" "2 1 True" \
  "  the commits within 48 h on the same files, its own left out; one says fix"
check "$(grep '"b43"' "$ROWS" | python3 -c 'import json, sys; print(json.load(sys.stdin)["settled"])')" "None" "  the young one waits"
check "$(grep '"b44"' "$ROWS" | python3 -c 'import json, sys; print(json.load(sys.stdin)["settled"])')" "None" "  one whose window ends past origin/main's tip waits for a fresher ref"
"$B/autofinish-run" rotation --json > "$T/out" 2>&1
check "$(python3 -c 'import json, sys; d = json.load(open(sys.argv[1])); print(d["hosts"].get("laptop"), d["arms"]["opus-medium"]["fix_48h"], d["arms"]["opus-medium"]["settled"], d["fenced_now"], d["forced"] > 0, "sonnet-medium" in d["arms"])' "$T/out")" \
  "2 1 1 0 True False" "rotation --json: each host's runs (its share of the landings), the arm's fixes of its settled launches; forced rows in no arm"
reg ', "confidential": true'
"$B/autofinish-run" rotation --json > "$T/out" 2>&1
check "$(python3 -c 'import json, sys; d = json.load(open(sys.argv[1])); print(d["rows"], d["fenced_now"] > 0)' "$T/out")" "0 True" "  a repo confidential now: its rows are passed over"
rm -f "$ROT"; unset CLAUDE_REPOS_JSON

echo "Where: a run started on the laptop goes to its peer (the owner, 2026-10-22: the laptop is mobile)"
# the peer is a second HOME and config dir; ssh runs the command there as a login would, with none of
# this shell's variables a real ssh would not carry, and launchctl runs a bootstrapped job at once
PH="$(cd "$T" && pwd -P)/peer"   # realpath: git reports /private/var
mkdir -p "$PH/projects"; cp -R "$REGATTA_CONFIG" "$PH/config"
cat > "$T/ssh" <<EOF
#!/bin/bash
echo "ssh \$*" >> "$T/ssh.calls"
while [ "\${1:-}" = -o ]; do shift 2; done
host=\$1; shift
[ -n "\${SSH_DOWN:-}" ] && { echo "ssh: connect to host \$host port 22: Operation timed out" >&2; exit 255; }
# SSH_SYNC_DOWN: the peer stops answering once the run is sent; SSH_START_RC: peer-start dies with a traceback
case "\$1" in *peer-sync*) [ -n "\${SSH_SYNC_DOWN:-}" ] && { echo "ssh: connect to host \$host: Network is unreachable" >&2; exit 255; };; esac
case "\$1" in *"peer-start --repo"*) [ -n "\${SSH_START_RC:-}" ] && { echo "Traceback (most recent call last):" >&2; echo "KeyError: 'x'" >&2; exit "\$SSH_START_RC"; };;
               *) [ -n "\${SSH_STDIN_LOG:-}" ] && cat >> "\$SSH_STDIN_LOG";; esac
sh=/bin/bash; [ -x /bin/zsh ] && sh=/bin/zsh
exec env -u CLAUDE_CONFIG_DIR -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CODE_CHILD_SESSION -u AUTOFINISH_ON -u SSH_DOWN \
  -u SSH_SYNC_DOWN -u SSH_START_RC -u SSH_STDIN_LOG -u AUTOFINISH_PEER_WAIT -u AUTOFINISH_END_WARM -u AUTOFINISH_SEND_BUDGET \
  -u CLAUDE_UNATTENDED -u SKIPPER_SCOPE \
  HOME="$PH" REGATTA_CONFIG="$PH/config" AUTOFINISH_HOST=buildbox "\$sh" -c "\$1"
EOF
cat > "$T/launchctl" <<EOF
#!/bin/bash
echo "launchctl \$*" >> "$T/launchctl.calls"
[ "\$1" = bootstrap ] || exit 0
cp "\$3" "$T/last.plist"
exec python3 - "\$3" <<'PY'
import os, plistlib, subprocess, sys
p = plistlib.load(open(sys.argv[1], "rb"))
out = open(p["StandardOutPath"], "a")
subprocess.Popen(p["ProgramArguments"], env=dict(os.environ, **p.get("EnvironmentVariables", {})),
                 stdin=subprocess.DEVNULL, stdout=out, stderr=out, start_new_session=True)
PY
EOF
chmod +x "$T/ssh" "$T/launchctl"
# the laptop's repo in the projects folder (the peer has its clone at the same place), on its own bare origin
git init -q --bare "$T/land.git"
L="$HOME/projects/land"; git init -q -b main "$L"
git -C "$L" config user.email t@t; git -C "$L" config user.name t
printf -- '- check: `true`\n- physical: none\n' > "$L/AGENTS.md"; git -C "$L" add AGENTS.md; git -C "$L" commit -qm init
git -C "$L" remote add origin https://github.com/test/land.git
git -C "$L" config url."$T/land.git".insteadOf https://github.com/test/land.git
LB=claude/laptop/2026-10-22-land; LW="$L/.claude/worktrees/land"
git -C "$L" worktree add -q -b $LB "$LW" main
echo work > "$LW/f"; git -C "$LW" add f; git -C "$LW" commit -qm "the land work" -m "Prompt: land it from the peer"
git -C "$L" send-pack "$T/land.git" "$LB:refs/heads/$LB" "main:refs/heads/main" >/dev/null 2>&1
git -C "$L" update-ref refs/remotes/origin/main main
git clone -q "$T/land.git" "$PH/projects/land"; PR="$PH/projects/land"
git -C "$PR" remote set-url origin https://github.com/test/land.git
git -C "$PR" config url."$T/land.git".insteadOf https://github.com/test/land.git
git -C "$PR" config user.email t@t; git -C "$PR" config user.name t
mkdir -p "$REGATTA_CONFIG/wharf-runs"
echo "laptop:buildbox" > "$REGATTA_CONFIG/wharf-runs/orca-pairs"; echo "buildbox:box-alias" > "$REGATTA_CONFIG/wharf-runs/ssh"
export AUTOFINISH_SSH="$T/ssh" AUTOFINISH_LAUNCHCTL="$T/launchctl" AUTOFINISH_PEER_POLL=0.3 DISPATCH_RCHOSTS=/usr/bin/false
LGD="$(git -C "$LW" rev-parse --absolute-git-dir)"; LSTATE="$LGD/claude/autofinish.json"; LLOCK="$LGD/claude/owner.json"
PW="$PR/.claude/worktrees/land"; PLOGS="$PH/Library/Logs/claude-weekly"
lfield() { python3 -c 'import json, sys; v = json.load(open(sys.argv[1])).get(sys.argv[2]); print("null" if v is None else v)' "$LSTATE" "$1"; }
lended() { for _ in $(seq 1 200); do [ "$(lfield ended 2>/dev/null)" != null ] && [ -n "$(lfield ended 2>/dev/null)" ] && return 0; sleep 0.2; done; echo "  (no end recorded here in 40 s)"; tail -5 "$LOGS"/*-dispatch-finish-land.log 2>/dev/null; return 1; }
laf() { AUTOFINISH_HOST=laptop CLAUDE_CODE_SESSION_ID=caller "$B/autofinish-run" "$LW" "$@"; }
lnext() { git -C "$LW" commit -q --allow-empty -m "$1"; }

: > "$T/ssh.calls"; : > "$T/api.log"
LTIP=$(git -C "$LW" rev-parse HEAD)
STUB_REPLY="$T/launch.txt" laf --rule A --by sweep > "$T/out" 2>&1; check "$?" "0" "sent: exit 0"
has "$T/out" "started on buildbox: /finish $LB --unattended --from=laptop in $PW" "  said where: the peer, in the worktree it made there"
check "$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import cold_prompt; print(cold_prompt.sent_to(open(sys.argv[2]).read()))' "$B/../hooks" "$T/out")" \
  "buildbox" "  a typed hand-off's line names the peer, where the window is (cold_prompt.sent_to; second landing review, 13)"
LSID=$(lfield session)
check "$(lfield host)" "buildbox" "  the state here names the host"
has "$T/ssh.calls" "-o ConnectTimeout=10 -o BatchMode=yes box-alias" "  ssh by the config's alias, a 10 s connect, never a prompt"
has "$T/ssh.calls" "peer-start --repo \"\$HOME/projects/\"land --branch $LB --tip $LTIP --run-session $LSID" "  peer-start with the tip and the session id chosen here"
lended
check "$(lfield outcome)/$(lfield pr)/$(lfield gate)" "launched/42/null" "the peer's end, written here: launched #42"
check "$(git -C "$PW" symbolic-ref --short HEAD 2>/dev/null)/$(git -C "$PW" rev-parse HEAD 2>/dev/null)" "$LB/$LTIP" "  the peer's worktree made from origin, at this very tip"
has "$T/launchctl.calls" "bootstrap gui/$(id -u) $PH/Library/LaunchAgents/org.regatta.autofinish.land.${LSID:0:8}.plist" "  started by a LaunchAgent in the GUI domain (the keychain)"
check "$(ls "$PH/Library/LaunchAgents/" 2>/dev/null | wc -l | tr -d ' ')" "0" "  whose plist is gone once it ran: a login never runs it again"
has "$T/claude.calls" "claude /finish $LB --unattended --from=laptop --session-id $LSID" "  the session there has the id chosen here…"
PGD="$(git -C "$PW" rev-parse --absolute-git-dir)"
check "$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1])).get("from"))' "$PGD/claude/autofinish.json")" "laptop" \
  "  …and carries the laptop's approval (D2-A): --from=laptop, \"from\" in its state there"
check "$(python3 -c 'import plistlib, sys; print("/opt/homebrew/bin" in plistlib.load(open(sys.argv[1], "rb"))["EnvironmentVariables"]["PATH"].split(":"))' "$T/last.plist")" \
  "True" "  its job's PATH has Homebrew's (gh for the stop comment)"
has "$T/at-start.$LSID.bundle" "the land work" "  its bundle is the one written here"
check "$([ -f "$LLOCK" ] && echo kept || echo gone)" "gone" "the lock here released"
has "$L/.git/claude/autofinished" "launched $LB #42" "the peer's autofinished line appended here"
has "$AFLOG" " run land $LB started session=${LSID:0:8} tip=${LTIP:0:7} rule=A by=sweep account=- window=\"finish · land\" — on buildbox" "the log here: the send"
has "$AFLOG" " run land $LB launched pr=#42 session=${LSID:0:8}" "  and the end"
has "$AFLOG" "; on buildbox" "  saying where it ran"
has "$PLOGS/autofinish-$AUTOFINISH_DAY.log" " run land $LB launched pr=#42 session=${LSID:0:8}" "the peer's own log has the run"
python3 "$B/dispatch-rc" status > "$T/out" 2>&1
has "$T/out" "finish-land" "dispatch --status here lists it…"
has "$T/out" "on buildbox · ended" "  …on the peer, ended"
has "$T/out" "launched #42" "  …launched #42"

echo "Where: the same tip, refused here from the record the peer's end left"
STUB_REPLY="$T/launch.txt" laf > "$T/out" 2>&1; check "$?" "3" "refused"
has "$T/out" "no retry on the same tip" "  as for a run here"

echo "Where: --on here keeps today's run"
lnext "here on purpose"; : > "$T/ssh.calls"
STUB_REPLY="$T/stop.txt" laf --on here > "$T/out" 2>&1; check "$?" "0" "started"
has "$T/out" "started: /finish $LB --unattended — window" "  here"
check "$(wc -c < "$T/ssh.calls" | tr -d ' ')" "0" "  no ssh at all"
lended; check "$(lfield host)/$(lfield outcome)" "null/stopped" "  no host in its state"

echo "Where: an unpushed tip is pushed first, then sent"
lnext "not pushed yet"; LTIP=$(git -C "$LW" rev-parse HEAD)
STUB_REPLY="$T/launch.txt" laf > "$T/out" 2>&1; check "$?" "0" "sent"
check "$(git -C "$T/land.git" rev-parse "refs/heads/$LB")" "$LTIP" "  origin has the tip"
has "$T/out" "started on buildbox" "  and the run went to the peer"
lended; check "$(lfield outcome)" "launched" "  launched there"

echo "Where: a typed /finish's --merge travels with the send (D3-A: the typed word stays the yes, wherever it lands)"
lnext "typed, with the yes"; : > "$T/ssh.calls"
AUTOFINISH_SEND_BUDGET=110 STUB_REPLY="$T/launch.txt" laf --by typed --merge > "$T/out" 2>&1; check "$?" "0" "sent: exit 0 (the untyped budget: a loaded runner outlasts the typed 40 s)"
has "$T/out" "started on buildbox: /finish $LB --unattended --merge --from=laptop in $PW" "  said so: --merge beside --from"
has "$T/ssh.calls" "--by typed --merge --from laptop" "  peer-start is given --by typed --merge"
lended; LSID=$(lfield session)
has "$T/claude.calls" "claude /finish $LB --unattended --merge --from=laptop --session-id $LSID" "  the peer's /finish carries --merge"
check "$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1])).get("merge"))' "$PGD/claude/autofinish.json")/$(lfield merge)" \
  "True/True" "  \"merge\" in the state there and here"
lnext "typed, kept here"
STUB_REPLY="$T/stop.txt" laf --on here --by typed --merge > "$T/out" 2>&1; check "$?" "0" "kept on the laptop (--on here): started"
has "$T/out" "started: /finish $LB --unattended --merge — window" "  here, with --merge, as before the peer"
lended; check "$(lfield host)/$(lfield merge)" "null/True" "  a run here that carries the yes"

echo "Where: what keeps a run here says why"
lnext "dirty"; echo scratch > "$LW/untracked.txt"
STUB_REPLY="$T/stop.txt" laf > "$T/out" 2>&1; check "$?" "0" "uncommitted files: started"
has "$T/out" "stays on this Mac — 1 uncommitted file(s) in the worktree" "  here, saying why"
lended; check "$(lfield host)" "null" "  a run here"
has "$AFLOG" "; here: 1 uncommitted file(s)" "  and the start's log line says it stayed"
rm -f "$LW/untracked.txt"
lnext "peer down"
SSH_DOWN=1 STUB_REPLY="$T/stop.txt" laf > "$T/out" 2>&1; check "$?" "0" "the peer unreachable: started"
has "$T/out" "stays on this Mac — buildbox is unreachable (ssh exit 255" "  here, saying so"
lended; check "$(lfield host)" "null" "  a run here"
lnext "no clone there"; mv "$PR" "$PR.off"
STUB_REPLY="$T/stop.txt" laf > "$T/out" 2>&1; check "$?" "0" "the peer has no clone: started"
has "$T/out" "stays on this Mac — no clone of land on" "  here, saying so"
lended; mv "$PR.off" "$PR"
lnext "a token"
CLAUDE_CODE_OAUTH_TOKEN=tok laf --dry > "$T/out" 2>&1
has "$T/out" "stays on this Mac — the caller's CLAUDE_CODE_OAUTH_TOKEN" "a caller's OAuth token keeps it here"
sed -i.bak '/^laptop:/d' "$REGATTA_CONFIG/wharf-runs/orca-pairs" && rm -f "$REGATTA_CONFIG/wharf-runs/orca-pairs.bak"
laf --dry > "$T/out" 2>&1
hasnt "$T/out" "stays on this Mac" "no peer line for this Mac: here, without a word"
hasnt "$T/out" "on buildbox" "  and nothing sent"
echo "laptop:buildbox" > "$REGATTA_CONFIG/wharf-runs/finish-on"
before=$(cksum < "$LSTATE")
laf --dry > "$T/out" 2>&1
has "$T/out" "— on buildbox" "finish-on names the peer as well (a --dry: what would be sent)"
has "$T/out" "would send the bundle" "  the bundle and the ssh line"
check "$(cksum < "$LSTATE")" "$before" "  and nothing written"
rm -f "$REGATTA_CONFIG/wharf-runs/finish-on"; echo "laptop:buildbox" > "$REGATTA_CONFIG/wharf-runs/orca-pairs"

echo "Where: peer-start refuses --merge from an unattended caller, before anything is written"
CLAUDE_UNATTENDED=1 "$B/autofinish-run" peer-start --repo "$HOME/projects/land" --branch "$LB" --tip "$LTIP" \
  --run-session 00000000-0000-4000-8000-000000000000 --by override --merge > "$T/out" 2>&1
check "$?" "2" "refused"
has "$T/out" "needs a person's yes" "  saying why"
"$B/autofinish-run" peer-start --repo "$HOME/projects/land" --branch "$LB" --tip "$LTIP" \
  --run-session 00000000-0000-4000-8000-000000000000 --by sweep --merge > "$T/out" 2>&1
check "$?" "2" "a --by outside the person's yes is refused too"
for by in chain yolo; do
  "$B/autofinish-run" peer-start --repo "$HOME/projects/land" --branch "$LB" --tip "$LTIP" \
    --run-session 00000000-0000-4000-8000-000000000000 --by $by --merge > "$T/out" 2>&1
  check "$?" "2" "  --by $by --merge: refused"
done
"$B/autofinish-run" peer-start --repo "$HOME/projects/land" --branch "$LB" --tip "$LTIP" \
  --run-session 00000000-0000-4000-8000-000000000000 --by typed --merge --unattended-caller > "$T/out" 2>&1
check "$?" "2" "--by typed --merge from the sender's unattended caller (--unattended-caller): refused"
has "$T/out" "needs a person's yes" "  saying why"
CLAUDE_UNATTENDED=dispatch laf --by typed --merge --dry > "$T/out" 2>&1; check "$?" "2" "a typed --merge from an unattended caller is refused before any send"
has "$T/out" "unattended run" "  saying why"
SKIPPER_SCOPE=s "$B/autofinish-run" peer-start --repo "$HOME/projects/land" --branch "$LB" --tip "$LTIP" \
  --run-session 00000000-0000-4000-8000-000000000000 --by override --merge > "$T/out" 2>&1
check "$?" "2" "--merge from a skipper (SKIPPER_SCOPE): refused, as run_main refuses it (CR 1)"

echo "Where: the peer cannot take it (its worktree dirty): started here instead"
echo dirt > "$PW/dirt.txt"
STUB_REPLY="$T/stop.txt" laf > "$T/out" 2>&1; check "$?" "0" "started"
has "$T/out" "stays on this Mac — buildbox cannot take it: autofinish-run peer-start: its worktree here ($PW) has uncommitted changes" "  here, with the peer's words"
lended; check "$(lfield host)/$(lfield outcome)" "null/stopped" "  a run here"
rm -f "$PW/dirt.txt"

echo "Where: the waiter here dies; a start is refused while the run goes on there, and the sweep settles it"
lnext "waiter dies"; LTIP=$(git -C "$LW" rev-parse HEAD)
AUTOFINISH_PEER_POLL=600 STUB_REPLY="$T/stop.txt" laf > "$T/out" 2>&1; check "$?" "0" "sent"
LSID=$(lfield session)
for _ in $(seq 1 50); do [ -s "$LGD/claude/autofinish-waiter.json" ] && break; sleep 0.2; done
WP=$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["pid"])' "$LGD/claude/autofinish-waiter.json")
kill -TERM "$WP"; sleep 0.5
laf > "$T/out" 2>&1; check "$?" "3" "a second start while it goes on there: refused"
has "$T/out" "(session ${LSID:0:8}) has not ended, on buildbox" "  naming the host"
for _ in $(seq 1 150); do grep -q '"line"' "$PR/.git/claude/autofinish-peer/$LSID.json" 2>/dev/null && grep -q '"stopped"' "$PR/.git/claude/autofinish-peer/$LSID.json" && break; sleep 0.2; done
check "$(lfield ended)" "null" "  the peer ended it, nothing here knows yet"
AUTOFINISH_HOST=laptop python3 - "$B/autofinish-run" "$LW" > "$T/out" 2>&1 <<'EOF'
import sys
from importlib.machinery import SourceFileLoader
m = SourceFileLoader("afr", sys.argv[1]).load_module()
t = m.Tree(sys.argv[2])
st = m.read_state(t)
why = m.dead(None, st, state_dir=t.state_dir)
print("dead:", why)
print("bury:", m.bury(t, why) if why else None)
EOF
has "$T/out" "dead: its waiter here is gone, and buildbox has the run's end (ended)" "dead() asks the peer"
has "$T/out" "recorded from buildbox after its waiter here died — ended, stopped" "bury() writes the peer's end here"
check "$(lfield outcome)/$(lfield gate)" "stopped/G4" "  the state: stopped at G4"
check "$([ -f "$LLOCK" ] && echo kept || echo gone)" "gone" "  the lock released"
has "$L/.git/claude/autofinished" "stopped $LB G4 ⚠ step 4" "  the stop's line appended here"

echo "Where: D2-A — only a plain landing is sent; --from is the peer's job's alone"
lnext "yolo"
laf --by yolo --dry > "$T/out" 2>&1
has "$T/out" "stays on this Mac — " "a yolo launch stays here: the landing ladder reads this Mac's plans…"
hasnt "$T/out" "— on buildbox" "  …so nothing is sent"
hasnt "$T/out" "--from" "  …and it carries no approval"
"$B/autofinish-run" "$LW" --from laptop --dry > "$T/out" 2>&1; check "$?" "2" "--from without --ticket: refused"
has "$T/out" "--from is the peer's job's" "  saying whose it is"
CLAUDE_UNATTENDED=1 "$B/autofinish-run" peer-start --repo "$HOME/projects/land" --branch "$LB" --tip "$LTIP" \
  --run-session 00000000-0000-4000-8000-000000000000 --by sweep --from laptop > "$T/out" 2>&1
check "$?" "2" "peer-start's --from from an unattended caller: refused"
SKIPPER_SCOPE=s "$B/autofinish-run" peer-start --repo "$HOME/projects/land" --branch "$LB" --tip "$LTIP" \
  --run-session 00000000-0000-4000-8000-000000000000 --by sweep --from laptop > "$T/out" 2>&1
check "$?" "2" "peer-start's --from from a skipper: refused (CR 1)"

echo "Where: a peer that goes silent — the lock here kept fresh, then the run buried as died past its time"
lnext "silent peer"; LTIP=$(git -C "$LW" rev-parse HEAD); : > "$T/api.log"
SSH_SYNC_DOWN=1 AUTOFINISH_PEER_WAIT=20 STUB_REPLY="$T/stop.txt" laf > "$T/out" 2>&1; check "$?" "0" "sent"
LSID=$(lfield session)
python3 - "$LLOCK" <<'EOF'
import json, sys, time
d = json.load(open(sys.argv[1])); d["seen"] = time.time() - 7000; json.dump(d, open(sys.argv[1], "w"))
EOF
fresh() { python3 -c 'import json, sys, time; d = json.load(open(sys.argv[1])); print("fresh" if time.time() - d["seen"] < 60 and d["session"] == sys.argv[2] else "stale")' "$LLOCK" "$LSID" 2>/dev/null; }
for _ in $(seq 1 50); do [ "$(fresh)" = fresh ] && break; sleep 0.2; done   # a poll is 0.3 s; the run is buried at 20 s
check "$(fresh)" \
  "fresh" "  the waiter refreshed the lock an hour and more of quiet had aged (checkpoint.py frees it at 2 h)"
lended
check "$(lfield outcome)/$(lfield gate)" "died/null" "  no answer past AUTOFINISH_PEER_WAIT: died here"
check "$([ -f "$LLOCK" ] && echo kept || echo gone)" "gone" "  the lock released"
has "$AFLOG" " run land $LB died session=${LSID:0:8}" "  the day's log says so…"
has "$AFLOG" "no answer from buildbox" "  …and why"
has "$T/api.log" "may have ended there unseen" "  the PR comment says the run may have ended there"
laf --on here --dry > "$T/out" 2>&1; check "$?" "0" "  and the worktree is free again: --on here is no longer refused"
AUTOFINISH_HOST=laptop python3 - "$B/autofinish-run" > "$T/out" 2>&1 <<'EOF'
import datetime, sys, uuid
from importlib.machinery import SourceFileLoader
m = SourceFileLoader("afr", sys.argv[1]).load_module()
ago = lambda s: (datetime.datetime.now().astimezone() - datetime.timedelta(seconds=s)).isoformat(timespec="seconds")
print("old:", m.dead(None, {"session": str(uuid.uuid4()), "started": ago(660), "host": "buildbox"}))
print("young:", m.dead(None, {"session": str(uuid.uuid4()), "started": ago(120), "host": "buildbox"}))
EOF
has "$T/out" "old: no record here of the send to buildbox, 11 min after its start" "dead(): a sent run with no record here, past PRE_START_S"
has "$T/out" "young: None" "  not before"

echo "Where: peer-start refuses what the job would, at once"
for _ in $(seq 1 150); do grep -q '"line"' "$PR/.git/claude/autofinish-peer/$LSID.json" 2>/dev/null && break; sleep 0.2; done
"$T/ssh" box-alias "\"$B/autofinish-run\" peer-start --repo \"\$HOME/projects/land\" --branch $LB --tip $LTIP --run-session 00000000-0000-4000-8000-0000000000aa --by sweep" > "$T/out" 2>&1
check "$?" "3" "a tip the peer already ran: 3"
has "$T/out" "no retry on the same tip" "  saying why"

echo "Where: a send the peer refuses for a run of its own on this tip — that run recorded here, never sent again (second landing review, 2)"
# here: the silent peer's run buried as died; there: that very run, stopped at G4. The died tip may start once more
check "$(lfield session)/$(lfield outcome)" "$LSID/died" "the state here: the run buried as died"
: > "$T/ssh.calls"
STUB_REPLY="$T/stop.txt" laf --by sweep --rule A > "$T/out" 2>&1; check "$?" "3" "sent again, refused there: 3"
has "$T/out" "its run ${LSID:0:8} on this tip ended there" "  the peer's run on that tip…"
has "$T/out" "recorded here" "  …recorded here"
check "$(lfield session)/$(lfield outcome)/$(lfield gate)/$(lfield host)" "$LSID/stopped/G4/buildbox" "  the state: that run, stopped at G4 there"
check "$(tail -1 "$L/.git/claude/autofinished" | cut -d' ' -f2-5)" "stopped $LB G4 ⚠" "  its stop line appended here"
check "$([ -f "$LLOCK" ] && echo held || echo free)" "free" "  no lock left behind"
: > "$T/ssh.calls"
STUB_REPLY="$T/stop.txt" laf --by sweep --rule A > "$T/out" 2>&1; check "$?" "3" "the next sweep's start: refused here"
has "$T/out" "no retry on the same tip" "  by the same-tip rule"
check "$(wc -c < "$T/ssh.calls" | tr -d ' ')" "0" "  with no send: the loop is broken"

echo "Where: the peer's answers, written here — a refused job may start again; an end without its line"
AUTOFINISH_HOST=laptop python3 - "$B/autofinish-run" "$LW" > "$T/out" 2>&1 <<'EOF'
import sys, uuid
from importlib.machinery import SourceFileLoader
m = SourceFileLoader("afr", sys.argv[1]).load_module()
t = m.Tree(sys.argv[2])
for kind, ans in (("refused", lambda sid: {"ticket": {"session": sid, "rc": 3, "said": "a session holds it"}, "state": None, "line": None}),
                  ("ended", lambda sid: {"ticket": None, "line": None, "state": {"session": sid, "ended": m.now_iso(),
                                         "outcome": "stopped", "gate": "G4", "pr": None}})):
    sid = str(uuid.uuid4())
    st = {"started": m.now_iso(), "session": sid, "tip": t.tip, "by": "sweep", "rule": "A", "window": t.window,
          "account": None, "ended": None, "outcome": None, "pr": None, "gate": None, "host": "buildbox"}
    m.write_state(t, st)
    print(kind, m.settle(t, st, ans(sid), None), m.read_state(t).get("outcome"), m.read_state(t).get("gate"))
EOF
has "$T/out" "refused refused never-started refused" "a job that refused there: never-started at refused, the tip may start again"
has "$T/out" "ended ended stopped G4" "an end whose line did not come: written, no crash"
has "$L/.git/claude/autofinished" "stopped $LB G4 its end on buildbox came without its line" "  its autofinished line made here"

echo "Where: peer-start dies (exit 1): nothing went there, so the run starts here"
lnext "peer-start dies"
SSH_START_RC=1 STUB_REPLY="$T/stop.txt" laf > "$T/out" 2>&1; check "$?" "0" "started"
has "$T/out" "stays on this Mac — buildbox cannot take it: KeyError: 'x' (exit 1)" "  here, with the peer's last words and the exit"
lended; check "$(lfield host)/$(lfield outcome)" "null/stopped" "  a run here, not a run waited on there"

echo "Where: a job launchd starts late refuses; the next send boots out one that never ran"
STALE=00000000-0000-4000-8000-0000000000bb; TK="$PR/.git/claude/autofinish-peer/$STALE.json"
mkdir -p "$PH/Library/LaunchAgents"; : > "$PH/Library/LaunchAgents/org.regatta.autofinish.land.never.plist"
python3 - "$TK" "$STALE" <<'EOF'
import datetime, json, sys
then = (datetime.datetime.now().astimezone() - datetime.timedelta(minutes=20)).isoformat(timespec="seconds")
json.dump({"session": sys.argv[2], "scheduled": then, "rc": None, "said": None, "label": "org.regatta.autofinish.land.never"}, open(sys.argv[1], "w"))
EOF
"$T/ssh" box-alias "\"$B/autofinish-run\" \"$PW\" --on here --run-session $STALE --ticket \"$TK\" --by sweep" > "$T/out" 2>&1
check "$?" "3" "a job 20 min late: refused"
check "$(python3 -c 'import json, sys; d = json.load(open(sys.argv[1])); print(d["rc"], "writes it off" in (d["said"] or ""))' "$TK")" "3 True" "  its ticket says so"
python3 - "$TK" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1])); d["rc"] = None; d["said"] = None; json.dump(d, open(sys.argv[1], "w"))
EOF

echo "Where: the warm run is ended before the send, and its last commit goes with it"
cat > "$T/end-warm" <<EOF
#!/bin/bash
git -C "$LW" commit -q --allow-empty -m "the warm run's last checkpoint"
EOF
chmod +x "$T/end-warm"
lnext "warm"; : > "$T/ssh.calls"
AUTOFINISH_END_WARM="$T/end-warm" STUB_REPLY="$T/launch.txt" laf > "$T/out" 2>&1; check "$?" "0" "sent"
LTIP=$(git -C "$LW" rev-parse HEAD)
has "$T/out" "moved to ${LTIP:0:7} as its warm run ended" "  the tip read again after the warm run's end"
has "$T/ssh.calls" "--tip $LTIP" "  and that tip sent"
check "$(git -C "$T/land.git" rev-parse "refs/heads/$LB")" "$LTIP" "  pushed first"
lended; check "$(lfield outcome)" "launched" "  launched there"
check "$([ -e "$PH/Library/LaunchAgents/org.regatta.autofinish.land.never.plist" ] && echo kept || echo gone)" "gone" \
  "the send booted out the job that never ran, its plist gone"
check "$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1])).get("booted"))' "$TK")" "True" "  its ticket marked"

echo "Where: the send's budget, and ssh's stdin"
lnext "budget"
AUTOFINISH_SEND_BUDGET=20 laf --dry > "$T/out" 2>&1
has "$T/out" "stays on this Mac — out of time for the send's checks (20 s budget)" "checks that would outrun the caller's wait: here, saying so"
: > "$T/stdin.log"
echo "the caller's stdin" | SSH_STDIN_LOG="$T/stdin.log" laf --dry > "$T/out" 2>&1
has "$T/out" "— on buildbox" "a probe ran…"
check "$(wc -c < "$T/stdin.log" | tr -d ' ')" "0" "  …reading /dev/null, never the caller's stdin"

echo "Where: a chain relaunch goes to the peer, judged here where its stop happened (second landing review, 1)"
lnext "network drop"; LTIP=$(git -C "$LW" rev-parse HEAD)
printf 'Working on step 11.\nAPI Error: Connection error.\n' > "$T/netdrop.txt"
STUB_REPLY="$T/netdrop.txt" laf --on here > "$T/out" 2>&1; lended
check "$(lfield outcome)/$(lfield gate)" "stopped/no-landing" "a run here stopped by the network"
: > "$T/ssh.calls"
CLAUDE_UNATTENDED=1 STUB_REPLY="$T/launch.txt" laf --by chain > "$T/out" 2>&1; check "$?" "0" "the chain's relaunch: sent"
has "$T/out" "started on buildbox" "  to the peer, which has no record of the stop and judges it plainly"
LSID=$(lfield session)
lended; check "$(lfield outcome)/$(lfield host)" "launched/buildbox" "  launched there"
check "$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1])).get("by"))' "$PGD/claude/autofinish.json")" "chain" "  recorded there as the chain's"
has "$T/ssh.calls" "--by chain --from laptop --unattended-caller" "an unattended caller's send says so (second landing review, 6)…"
check "$(python3 -c 'import plistlib, sys; print(plistlib.load(open(sys.argv[1], "rb"))["EnvironmentVariables"].get("AUTOFINISH_CALLER_UNATTENDED"))' "$T/last.plist")" \
  "1" "  …and the job there reads it as one: landing() holds as it would here"
AUTOFINISH_CALLER_UNATTENDED=1 python3 - "$B/autofinish-run" > "$T/out" 2>&1 <<'EOF'
import sys
from importlib.machinery import SourceFileLoader
m = SourceFileLoader("afr", sys.argv[1]).load_module()
print("unattended:", m.unattended_caller())
EOF
has "$T/out" "unattended: True" "  (unattended_caller reads the job's variable)"
python3 - "$B/autofinish-run" "$LW" > "$T/out" 2>&1 <<'EOF'
import sys
from importlib.machinery import SourceFileLoader
m = SourceFileLoader("afr", sys.argv[1]).load_module()
t = m.Tree(sys.argv[2])
m.last_stop = lambda t: None   # the peer has no autofinished line of the laptop's stop
on = lambda **k: dict({"tip": t.tip, "session": "11111111-0000-4000-8000-000000000000", "started": "2026-10-25T10:00:00-07:00",
                      "ended": "2026-10-25T10:05:00-07:00"}, **k)
for name, prev in (("refused", on(outcome="refused", gate="refused")), ("died", on(outcome=m.DIED, gate=None)),
                   ("stopped elsewhere", on(outcome="stopped", gate="review")), ("going", on(ended=None))):
    print("%s: %s" % (name, m.refusal(t, prev, "chain", sent=True) or "starts"))
EOF
has "$T/out" "refused: starts" "a sent chain on a peer whose own run on the tip was refused starts: the stop was not there (third landing review, S2)"
has "$T/out" "died: starts" "  nor when that run died: the plain refusal, as --by sweep gets"
has "$T/out" "stopped elsewhere: its run on this tip ended stopped at review, not stopped by the network" "  a stop the peer's own run made there is still judged there"
has "$T/out" "going: a run on this tip started" "  and a run still going there still refuses"
python3 - "$B/autofinish-run" "$LW" > "$T/out" 2>&1 <<'EOF'
import argparse, os, sys
from importlib.machinery import SourceFileLoader
m = SourceFileLoader("afr", sys.argv[1]).load_module()
t = m.Tree(sys.argv[2]); seen = []
m.refusal = lambda t, prev, by=None, sent=False: seen.append(sent) or "stop"
m.refuse = lambda t, args, why: 9
args = argparse.Namespace(by="chain", run_session="11111111-0000-4000-8000-000000000000", session=None)
os.environ.pop("AUTOFINISH_JOB", None); m.start(t, args)
os.environ["AUTOFINISH_JOB"] = "/nonexistent.plist"; m.start(t, args)
print("sent:", seen)
EOF
has "$T/out" "sent: [False, True]" "  a --run-session outside the job's env is judged as a run of this Mac's, chain_refusal and all (fourth landing review, CR 3)"
python3 - "$B/autofinish-run" "$T" > "$T/out" 2>&1 <<'EOF'
import os, sys
from importlib.machinery import SourceFileLoader
m = SourceFileLoader("afr", sys.argv[1]).load_module()
os.environ["AUTOFINISH_JOB"] = "/x.plist"; os.environ["AUTOFINISH_CALLER_UNATTENDED"] = "1"
env = m.start_env(type("T", (), {"runlog": "/dev/null"})())
print("job env:", "AUTOFINISH_JOB" in env, "AUTOFINISH_CALLER_UNATTENDED" in env)
wt = os.path.join(sys.argv[2], "ffwt"); os.makedirs(wt, exist_ok=True)
merges = []
m.quiet_git = lambda d, *a, **k: (merges.append(a) if a[:1] == ("merge",) else None) or (0, "", "")
m.git = lambda d, *a: {"status": ""}.get(a[0], "aaaa" if a[-1] == "HEAD" else "bbbb")
m.worktree_of = lambda repo, branch: wt
m.is_ancestor = lambda d, a, b: True
m.Tree = lambda p: type("T", (), {"state_dir": p})()
m.lock_refusal = lambda t, caller, typed: None
m.read_state = lambda t: {"tip": "aaaa", "session": "s", "started": "2026-10-25T10:00:00-07:00", "ended": None}
for name, died in (("live", None), ("dead", "died")):
    m.dead = lambda t, st, **k: died; m.bury = lambda t, d: True; merges.clear()
    _, code, why = m.peer_worktree("/repo", "claude/h/2026-10-25-x", "bbbb")
    print("%s: %s %s merged=%s" % (name, code, why, bool(merges)))
EOF
has "$T/out" "job env: False False" "the peer's job markers stay out of the /finish session's env (fourth landing review, CR 5)"
has "$T/out" "live: 3 a run here on aaaa has not ended: its tree is not moved under it merged=False" "an unended run on the peer keeps its tree: refused before the fast-forward (CR 4)"
has "$T/out" "dead: 0 None merged=True" "  a dead one is buried and the tree moves"

echo "Where: --from is the job's alone — its env, a pending ticket of its session, no skipper (second landing review, 4)"
FS=00000000-0000-4000-8000-0000000000cc; FTK="$T/from-ticket.json"
fticket() { python3 - "$FTK" "$FS" "$1" <<'EOF'
import datetime, json, sys
json.dump({"session": sys.argv[2], "scheduled": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
           "rc": None if sys.argv[3] == "none" else int(sys.argv[3])}, open(sys.argv[1], "w"))
EOF
}
fticket none
"$B/autofinish-run" "$LW" --on here --run-session $FS --ticket "$FTK" --from laptop --dry > "$T/out" 2>&1; check "$?" "2" "a --ticket without the job's env: refused"
has "$T/out" "no AUTOFINISH_JOB" "  saying so"
AUTOFINISH_JOB="$T/no.plist" SKIPPER_SCOPE=s "$B/autofinish-run" "$LW" --on here --run-session $FS --ticket "$FTK" --from laptop --dry > "$T/out" 2>&1
check "$?" "2" "a skipper: refused"
fticket 0
AUTOFINISH_JOB="$T/no.plist" "$B/autofinish-run" "$LW" --on here --run-session $FS --ticket "$FTK" --from laptop --dry > "$T/out" 2>&1
check "$?" "2" "a ticket whose run has an exit already: refused"
has "$T/out" "names no pending run" "  saying so"

echo "Where: the peer's silence, its lost runs, the sweep's asks (second landing review, 3, 5, 7, 9, 10, 12)"
T="$T" AUTOFINISH_HOST=laptop SSH_DOWN=1 python3 - "$B/autofinish-run" "$LW" > "$T/out" 2>&1 <<'EOF'
import datetime, json, os, subprocess, sys, time, uuid
from importlib.machinery import SourceFileLoader
m = SourceFileLoader("afr", sys.argv[1]).load_module()
t = m.Tree(sys.argv[2])
ago = lambda s: (datetime.datetime.now().astimezone() - datetime.timedelta(seconds=s)).isoformat(timespec="seconds")
def sent(started_s, **rec):
    sid = str(uuid.uuid4())
    st = {"session": sid, "started": ago(started_s), "host": "buildbox", "tip": t.tip}
    r = dict({"host": "buildbox", "alias": "box-alias", "rel": "land", "branch": t.branch, "topic": t.topic,
              "session": sid, "started": st["started"]}, **rec)
    return st, r
# 3: ten hours after the start, the peer answered a minute ago; this ask fails
st, rec = sent(36000, answered=ago(60), silent=None, asked=ago(60))
print("answered lately:", m.peer_overdue(st, rec, m.peer_ask(rec, fresh=True)))
# 3: the last ask was a night ago (asleep), silent since then: the silence starts again now
st, rec = sent(36000, answered=ago(35000), silent=ago(34000), asked=ago(33000))
print("woke offline:", m.peer_overdue(st, rec, m.peer_ask(rec, fresh=True)))
# 3: asked all along, silent for ten hours: died
st, rec = sent(36000, answered=ago(35000), silent=ago(34000), asked=ago(300))
print("silent all along:", m.peer_overdue(st, rec, m.peer_ask(rec, fresh=True)))
# 9: the sweep's second ask of a peer that just failed one is not made; dead() reads `now`
calls = open(os.environ["T"] + "/ssh.calls").read().count("peer-sync")
st2, rec2 = sent(120)
print("asked again:", m.peer_ask(rec2), open(os.environ["T"] + "/ssh.calls").read().count("peer-sync") - calls)
print("counted:", bool(rec2.get("asked")), rec2.get("silent") == rec2.get("asked"))
print("now:", m.dead(None, {"session": str(uuid.uuid4()), "started": ago(0), "host": "buildbox"}, now=time.time() + 3600))
# 10: the peer's job exited 0 and the peer holds no record of the run
st, rec = sent(1200)
gone = {"ticket": {"session": st["session"], "rc": 0, "scheduled": ago(1190)}, "state": None, "line": None}
print("gone:", m.settle(None, st, gone, rec, apply=False), "|", m.peer_overdue(st, rec, gone))
# 7: a job that began, younger than its write-off, is going — not lost
began = {"ticket": {"session": st["session"], "rc": None, "scheduled": ago(700), "began": ago(400)}, "state": None}
print("began:", m.settle(None, st, began, rec, apply=False))
began["ticket"]["began"] = ago(650)
print("began long ago:", m.settle(None, st, began, rec, apply=False))
# 5: the sweep's dead() refreshes the lock while the peer answers that the run goes on
st, rec = sent(60)
m.save_peer_record(rec)
sd = os.path.join(os.environ["T"], "lockdir"); os.makedirs(sd, exist_ok=True)
m.common.write_owner(sd, st["session"], t.branch)
lk = json.load(open(os.path.join(sd, m.common.OWNER_FILE))); lk["seen"] = time.time() - 7000
json.dump(lk, open(os.path.join(sd, m.common.OWNER_FILE), "w"))
m._asked.clear(); m._down.clear()
calls = open(os.environ["T"] + "/ssh.calls").read().count("peer-sync")
before = open(m.peer_record(st["session"])[0]).read()
print("read-only:", m.dead(None, st, state_dir=sd, apply=False),
      open(os.environ["T"] + "/ssh.calls").read().count("peer-sync") - calls,
      open(m.peer_record(st["session"])[0]).read() == before,
      round(time.time() - json.load(open(os.path.join(sd, m.common.OWNER_FILE)))["seen"]) > 6000)
m.peer_ask = lambda r, fresh=False, timeout=90, apply=True: {"ticket": {"session": r["session"], "rc": 0, "scheduled": ago(60)},
                                                 "state": {"session": r["session"], "ended": None}}
print("going:", m.dead(None, st, state_dir=sd), round(time.time() - json.load(open(os.path.join(sd, m.common.OWNER_FILE)))["seen"]) < 60)
# 12: a ticket write waits for the lock another writer holds
tk = os.path.join(os.environ["T"], "lock-ticket.json"); m.write_json(tk, {"session": "x"})
import fcntl
h = open(tk + ".lock", "a"); fcntl.flock(h, fcntl.LOCK_EX)
p = subprocess.Popen([sys.executable, "-c", "import sys; from importlib.machinery import SourceFileLoader; "
                      "m = SourceFileLoader('afr', sys.argv[1]).load_module(); m.update_json(sys.argv[2], lambda d: dict(d, rc=0))",
                      sys.argv[1], tk])
time.sleep(1.5)
print("waits:", p.poll() is None)
fcntl.flock(h, fcntl.LOCK_UN); p.wait(timeout=20)
print("then:", json.load(open(tk)).get("rc"))
EOF
has "$T/out" "answered lately: None" "a peer that answered a minute ago is not buried for one failed ask, 10 h from the start (3)"
has "$T/out" "woke offline: None" "  nor on waking offline after a night: the silence starts again"
has "$T/out" "silent all along: no answer from buildbox for 9." "  asked and silent for PEER_WAIT_S: died"
has "$T/out" "asked again: None 0" "the sweep does not ask a peer that just failed again (9)"
has "$T/out" "counted: True True" "  and that run counts as asked, silent from then: k runs on a down peer bury in PEER_WAIT_S, not k × (third landing review, S3)"
has "$T/out" "now: no record here of the send to buildbox, 60 min after its start" "  and dead() reads its now"
has "$T/out" "gone: None | buildbox started the run and has no record of it now" "a run the peer started and lost: died, not going on forever (10)"
has "$T/out" "began: None" "a job that began is no lost job (7)"
has "$T/out" "began long ago: lost" "  until it wrote nothing for PRE_START_S"
has "$T/out" "going: None True" "the sweep's dead() refreshes the lock while the peer answers (5)"
has "$T/out" "read-only: None 0 True True" "dead(apply=False) asks no peer, writes no record and leaves the lock (third landing review, S3)"
has "$T/out" "waits: True" "a ticket write waits for the lock (12)…"
has "$T/out" "then: 0" "  …then writes"
python3 - "$B/autofinish" "$LW" > "$T/out" 2>&1 <<'EOF'
import subprocess, sys, types
from importlib.machinery import SourceFileLoader
from pathlib import Path
af = SourceFileLoader("af", sys.argv[1]).load_module()
seen = {}
def dead(t, run, now=None, state_dir=None, apply=True):
    seen["apply"] = apply
    return "stub"
af._runner = types.SimpleNamespace(dead=dead)
wt = Path(sys.argv[2])
gd = Path(subprocess.run(["git", "-C", str(wt), "rev-parse", "--path-format=absolute", "--git-dir"],
                         capture_output=True, text=True).stdout.strip())
top = Path(subprocess.run(["git", "-C", str(wt), "rev-parse", "--path-format=absolute", "--git-common-dir"],
                          capture_output=True, text=True).stdout.strip()).parent
af.common.autofinish_run = lambda state: {"session": "x", "started": "2026-10-25T10:00:00-07:00"}
af.common.moved = lambda state: None
af.override = lambda state: "yes"
print("verdict:", af.verdict(top, wt, "claude/laptop/2026-10-22-land", gd, "main", ("all", [], None, [])).split(" (")[0],
      "apply:", seen.get("apply"))
print("bury pass:", af.dead_run(gd / "claude", {"session": "x", "started": "2026-10-25T10:00:00-07:00"}), "apply:", seen["apply"])
EOF
has "$T/out" "verdict: skip: died, not recorded yet apply: False" "bin/autofinish's verdict (the sweep's verdicts, --dry-run) asks dead() read-only (S3)"
has "$T/out" "bury pass: stub apply: True" "  and its bury pass asks it to act"
STALE6=00000000-0000-4000-8000-0000000000dd; TK6="$PR/.git/claude/autofinish-peer/$STALE6.json"
python3 - "$TK6" "$STALE6" <<'EOF'
import datetime, json, sys
then = (datetime.datetime.now().astimezone() - datetime.timedelta(minutes=6)).isoformat(timespec="seconds")
json.dump({"session": sys.argv[2], "scheduled": then, "rc": None, "said": None, "label": "x"}, open(sys.argv[1], "w"))
EOF
"$T/ssh" box-alias "\"$B/autofinish-run\" \"$PW\" --on here --run-session $STALE6 --ticket \"$TK6\" --by sweep" > "$T/out" 2>&1
check "$?" "3" "a job 6 min late refuses: inside the sending Mac's 10 min, with a margin (7)"
has "$T/out" "writes it off at 600 s" "  saying why"

echo "Where: the send's ssh leaves STAY_RESERVE to a run that stays (second landing review, 11)"
AUTOFINISH_HOST=laptop python3 - "$B/autofinish-run" "$LW" > "$T/out" 2>&1 <<'EOF'
import sys, time, types
from importlib.machinery import SourceFileLoader
m = SourceFileLoader("afr", sys.argv[1]).load_module()
t = m.Tree(sys.argv[2])
t.deadline, t.reserve, t.budget = time.time() + 40, 25, 110
seen = {}
def ssh_run(alias, cmd, stdin=None, timeout=60):
    seen["timeout"] = timeout
    return 4, "", "the peer cannot"
m.ssh_run = ssh_run
m.bundle_text = lambda t: "bundle"
def start_here(t, args, prev, by, via):
    seen["cached"] = getattr(t, "pick_cached", False)
    return 0
m.start_here = start_here
args = types.SimpleNamespace(rule="A", merge=False, dry=False, by="sweep")
m.start_on_peer(t, args, m.read_state(t), "sweep", "", "buildbox", "box-alias")
print("ssh wait:", round(seen["timeout"]), "pick cached:", seen.get("cached"))
EOF
has "$T/out" "ssh wait: 15 pick cached: False" "  its wait is what the budget leaves less the reserve, so the stay keeps its pick"
rm -rf "$REGATTA_CONFIG/wharf-runs"
unset AUTOFINISH_SSH AUTOFINISH_LAUNCHCTL AUTOFINISH_PEER_POLL DISPATCH_RCHOSTS

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
