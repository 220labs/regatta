#!/usr/bin/env bash
# Tests for bin/autofinish-run (autofinish E1) and the dispatch --start it starts through — a scratch
# HOME, a scratch repo with a bare origin, and stand-ins for claude, screen, GitHub's API and (for
# the crash cases) dispatch itself. No session, screen, window or GitHub call is real, bar one case's
# name lookups and one GET of api.github.com/zen (the waiter-fork-crash case: errors swallowed, so offline passes).
#   bash modules/wharf-runs/tests/test_autofinish_run.sh
set -u
# a dispatch session runs this suite inside its own run: its markers would change what is tested
unset CLAUDE_UNATTENDED REGATTA_UNATTENDED RUN_SEED_DEPTH RUN_SEED_BRIEF RUN_SEED_LABEL RUN_SEED_LOG RUN_SEED_YEAR \
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
# dispatch speaks within seconds; a case that wants it silent shortens the wait itself (the verdict wait, AUTOFINISH_VERDICT_S)
export AUTOFINISH_VERDICT_S=20
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
require_process_probe test_autofinish_run || exit $?
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
[ -n "\${STUB_FINISH:-}" ] && printf '{"session": "%s", "phase": "finish", "outcome": "%s", "ended": 1}' "\$sid" "\$STUB_FINISH" > "\$gd/claude/build-review-finish.json"
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
while [ -d "$T" ] && [ \$SECONDS -lt 900 ]; do sleep 0.2; done   # ends with its suite's \$T, or at 15 min: an endless loop outlived every killed suite run (99 on one Mac, 2026-11-05)
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
check "$(( $(date +%s) - start <= 15 ))" "1" "  the caller returned once dispatch had spoken, inside the bound (the run's end is the child's)"
has "$T/out" 'started: /finish claude/laptop/2026-10-05-demo --unattended — window and Remote Control "finish-demo"' "  and said where to watch"
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
      and st["rule"] == "A" and st["window"] == "finish-demo" and st["ended"] is None and st["outcome"] is None
      and st["pr"] is None and st["gate"] is None and st["started"])
print("ok" if ok else st)
PY
check "$(cat "$T/out")" "ok" "  the state at the start: the contract's keys exactly, ended/outcome/pr/gate null"
check "$(field outcome)" "stopped" "the state after the end: stopped"
check "$(field gate)" "G4" "  at G4 (step 4 named in the ⚠ line)"
check "$(field pr)" "7" "  on the branch's PR"
check "$(python3 -c 'import json, sys; print(list(json.load(open(sys.argv[1]))))' "$STATE")" \
      "['started', 'session', 'tip', 'by', 'rule', 'window', 'account', 'ended', 'outcome', 'pr', 'gate', 'base', 'base_tip']" \
      "  still the contract's keys, and the base and its tip once ended (task-shape S1; no push read: no pushed)"
has "$T/api.log" '"method": "POST", "path": "/repos/test/repo/issues/7/comments"' "the stop posted as a PR comment through the api"
has "$T/api.log" '⚠ step 4 — 2 open items' "  carrying the ⚠ block"
hasnt "$T/api.log" "WAITING FOR YOU" "  without the closing line"
has "$CD/claude/autofinished" "stopped $BR G4 ⚠ step 4 — 2 open items before this branch can be finished:" "the autofinished line (design section 7)"
has "$AFLOG" " run repo $BR started session=${SID:0:8}" "the log: the start"
has "$AFLOG" " run repo $BR stopped gate=G4 pr=#7 session=${SID:0:8}" "  and the end, in <iso> run <repo> <branch> <outcome> form"
check "$([ -f "$LOCK" ] && echo kept || echo gone)" "gone" "the lock released after the end"
has "$T/claude.calls" "claude /finish $BR --unattended --session-id $SID --remote-control finish-demo · buildbox --model opus" \
    "claude: the prompt, the chosen id, Remote Control \"finish-<topic> · <machine>\" (the session name), opus"
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
         "python3 $HOME/rg/modules/wharf/hooks/carried.py*" "~/rg/modules/regatta/bin/regatta which*" \
         "~/rg/modules/wharf-runs/bin/build-review covers*"; do
  has "$T/rules" "- --allow Bash($r)" "  allowed in the regatta main checkout: $r"
done
check "$(grep -c -F -- 'build-review*' "$T/rules") $(grep -c -E -- 'build-review (round|end)\*' "$T/rules")" "0 0" "  build-review by its covers verb, never a build's round or end (TODO.md [second-review] D1-B)"
for r in "~/rg/modules/wharf-runs/bin/build-review round * --phase finish*" "$HOME/rg/modules/wharf-runs/bin/build-review end * --phase finish*" \
         "~/rg/modules/wharf-runs/bin/build-review picks*"; do
  has "$T/rules" "- --allow Bash($r)" "  the landing's own loop by its finish phase alone (landing-fixes-in-run): $r"
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
hasnt "$T/api.log" "**Do this now** — the fix round" "  a stop past the review (G11) carries no fix-round line"

echo "a review stop (G1r) hands its fix round on at the landing's priority, never a plain normal build (landing-fixes-in-run)"
next_tip "review stop"; : > "$T/api.log"
printf 'Ran the check: all pass.\n\n⚠ step 1 — the review found 2 real items, one a Reversible: no choice (D1 in the fix round brief)\n\nSAM, THIS SESSION IS WAITING FOR YOU — the choice, above\n' > "$T/g1r.txt"
STUB_REPLY="$T/g1r.txt" af > /dev/null 2>&1; ended
check "$(field outcome)/$(field gate)" "stopped/G1r" "a G1r stop whose run kept no review loop of its own (a plan refused, a principal route)"
hasnt "$T/api.log" "**Do this now** — the fix round" "  carries no fix-round line: there is no fix round to hand on"
next_tip "review stop, held"; : > "$T/api.log"
STUB_FINISH=held STUB_REPLY="$T/g1r.txt" af > /dev/null 2>&1; ended
check "$(field outcome)/$(field gate)/$(field priority)" "stopped/G1r/null" "a landing with no --priority whose own loop ended held stops at G1r; its state keeps no priority"
has "$T/api.log" "**Do this now** — the fix round, at the landing's priority (\`high\`" "  the PR comment's Do this now: the fix round at high, a finish's fix ahead of the builds"
# the line names the repo by its real path: a runner's TMPDIR is a link (/var -> /private/var), and the tool prints what pwd -P does
has "$T/api.log" "dispatch $BR --repo $(cd "$R" && pwd -P) --priority high" "  as one dispatch line naming the branch, the repo and the priority"
has "$T/api.log" "never a plain \`normal\` dispatch" "  saying why not normal"
next_tip "review stop, high"; : > "$T/api.log"
STUB_FINISH=cap STUB_REPLY="$T/g1r.txt" af --priority high > /dev/null 2>&1; ended
check "$(field gate)/$(field priority)" "G1r/high" "a landing started --priority high keeps it in its state"
has "$T/api.log" "--priority high" "  and its fix round goes at it"
python3 - "$B/autofinish-run" "$W" <<'EOF' > "$T/out"
import sys
from importlib.machinery import SourceFileLoader
m = SourceFileLoader("afr", sys.argv[1]).load_module()
t = m.Tree(sys.argv[2])
for p in ("force", "high", None, "low"):
    print(m.fix_round_line(t, {"priority": p}).split("--priority ")[-1].split("`")[0])
EOF
check "$(tr '\n' ' ' < "$T/out")" "force high high high " "  fix_round_line: the landing's own force or high, else high"
next_tip "review stop, worded as the check"; : > "$T/api.log"
printf '⚠ step 1 — 2 real findings left at the round cap (3 rounds); the check is green\n\nSAM, THIS SESSION IS WAITING FOR YOU — the findings, above\n' > "$T/g1.txt"
STUB_FINISH=cap STUB_REPLY="$T/g1.txt" af > /dev/null 2>&1; ended
check "$(field gate)" "G1" "a capped loop whose stop names the check first reads G1"
has "$T/api.log" "**Do this now** — the fix round" "  and still hands its fix round on: its own loop ended cap (round 2's verifier)"

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
AUTOFINISH_DISPATCH="$T/dispatch-crash" af > "$T/out" 2>&1; check "$?" "5" "a tip that never started may start again (and says dispatch refused it: exit 5)"
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
AUTOFINISH_VERDICT_S=2 AUTOFINISH_DISPATCH="$T/dispatch-hang" af > /dev/null 2>&1
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
# the waiter: its pid in autofinish-waiter.json (an exec'd `autofinish-run waiter` since waiter-fork-crash,
# 2026-11-03: no process keeps the runner's own command line)
# this run's file, never the last case's: its session is the one the run's state names
WSID=$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["session"])' "$GD/claude/autofinish.json" 2>/dev/null)
for _ in $(seq 1 50); do
  python3 -c 'import json, sys; sys.exit(json.load(open(sys.argv[1])).get("session") != sys.argv[2])' \
    "$GD/claude/autofinish-waiter.json" "$WSID" 2>/dev/null && break; sleep 0.2
done
WPID=$(python3 -c 'import json, sys; w = json.load(open(sys.argv[1])); print(w["pid"] if w.get("session") == sys.argv[2] else "")' \
       "$GD/claude/autofinish-waiter.json" "$WSID" 2>/dev/null)
check "$(ps -o args= -p "$WPID" | grep -c 'autofinish-run waiter')" "1" "the waiter runs as an exec'd \`autofinish-run waiter\`"
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
python3 -c 'import os,sys,time; t=time.time()-180; os.utime(sys.argv[1], (t,t))' "$SL"
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
def no_fork(*_):
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
def no_fork(*_):
    raise OSError("fork failed")
m.detach = no_fork
m.main([sys.argv[2], "--rule", "A", "--by", "sweep"])
EOF
check "$([ -f "$LOCK" ] && echo kept || echo gone)" "gone" "  with no lock before it, ours is removed"

echo "the waiter is a fresh interpreter: a parent that resolved names first still gets its end (waiter-fork-crash, 2026-11-03)"
# macOS: once a process has called getaddrinfo, a forked child's next one may die in Apple's Network framework
# (SIGSEGV; fourteen waiters on the laptop died so, 2026-11-01/03, detach()'s docstring). The race is not
# deterministic, so the case proves both halves: the waiter's own GitHub call (the stop's comment, through a
# stub that resolves names in the waiter's process) runs in a process exec'd as `autofinish-run waiter`, and the
# run records its end. Offline, the resolves fail with an error, which is no crash either.
next_tip "a parent that resolved names"; : > "$T/api.log"; rm -f "$T/gai.log" "$T/claude.env"
RL="$LOGS/$AUTOFINISH_DAY-dispatch-finish-demo.log"; RL0=$(wc -c < "$RL" 2>/dev/null || echo 0)   # the day's log: earlier cases wrote it too
cat > "$T/api_stub_gai.py" <<'EOF'
import importlib.util, json, os, socket, sys
_spec = importlib.util.spec_from_file_location("api_stub_base", os.environ["STUB_API_BASE"])
_base = importlib.util.module_from_spec(_spec); _spec.loader.exec_module(_base)
def api(method, path, body=None, tok=None, timeout=15):
    said = []
    for host in ("localhost", "github.com", "api.github.com"):
        try:
            socket.getaddrinfo(host, 443); said.append("ok")
        except OSError as e:
            said.append(type(e).__name__)
    with open(os.environ["STUB_GAI_LOG"], "a") as f:
        f.write(json.dumps({"argv": sys.argv[1:], "spec": os.environ.get("AUTOFINISH_WAITER_SPEC") is not None, "gai": said}) + "\n")
    return _base.api(method, path, body, tok, timeout)
EOF
STUB_REPLY="$T/stop.txt" AUTOFINISH_API_STUB="$T/api_stub_gai.py" STUB_API_BASE="$T/api_stub.py" STUB_GAI_LOG="$T/gai.log" \
  CLAUDE_CODE_CHILD_SESSION=1 CLAUDE_CODE_SESSION_ID=caller python3 - "$B/autofinish-run" "$W" <<'EOF' > "$T/out" 2>&1
import socket, sys, urllib.request
from importlib.machinery import SourceFileLoader
for host in ("localhost", "github.com", "api.github.com"):
    try:
        socket.getaddrinfo(host, 443)
    except OSError:
        pass
try:   # what the night's callers did before their detach: an HTTPS call, which loads the Network framework
    urllib.request.urlopen("https://api.github.com/zen", timeout=5).read()
except Exception:
    pass
m = SourceFileLoader("autofinish_run", sys.argv[1]).load_module()
print("rc=%s" % m.main([sys.argv[2], "--rule", "A", "--by", "sweep"]))
EOF
has "$T/out" "rc=0" "a caller that resolved names and called GitHub first: started"
ended; check "$(field outcome)/$(field gate)" "stopped/G4" "  the waiter recorded the run's end"
has "$T/api.log" '"method": "POST"' "  its comment went through GitHub's stand-in, from the waiter"
check "$(python3 -c 'import json, sys; print(sorted({" ".join(json.loads(l)["argv"]) for l in open(sys.argv[1])}))' "$T/gai.log" 2>&1)" "['waiter']" \
      "  every GitHub call of the run ran in the waiter, a process exec'd as \`autofinish-run waiter\`"
check "$(python3 -c 'import json, sys; print({json.loads(l)["spec"] for l in open(sys.argv[1])})' "$T/gai.log" 2>&1)" "{False}" \
      "  its spec left the environment before the waiter ran"
check "$([ -f "$T/claude.env" ] && echo ran || echo missing)" "ran" "  claude ran for this case"
hasnt "$T/claude.env" "AUTOFINISH_WAITER_" "  nor its spec or ready fd reached claude's"
check "$(python3 -c 'import json, sys; print(all(set(json.loads(l)["gai"]) <= {"ok", "gaierror"} for l in open(sys.argv[1])))' "$T/gai.log" 2>&1)" "True" \
      "  and the waiter's own getaddrinfo calls came back (an answer, or an error offline)"
tail -c +$((RL0 + 1)) "$RL" > "$T/rl.new"
has "$T/rl.new" "autofinish-run: bundle " "  its log line written, by this run"
python3 - "$B/autofinish-run" "$W" "$T/gone.log" <<'EOF' > "$T/out" 2>&1
import os, sys
from importlib.machinery import SourceFileLoader
m = SourceFileLoader("autofinish_run", sys.argv[1]).load_module()
t = m.Tree(sys.argv[2])
PY = sys.executable   # m.sys is this sys: the cases below change it, so the real one is kept here
cases = (("a waiter not in WAITERS", lambda: m.detach("print", t, (), sys.argv[3])),
         ("a spec that will not encode", lambda: (setattr(m.sys, "executable", "x\ud83d"),   # a lone surrogate:
                                                 m.detach("wait_for_end", t, ({}, []), sys.argv[3]))),   # no exec encodes it
         ("no interpreter named", lambda: (setattr(m.sys, "executable", ""),
                                           m.detach("wait_for_end", t, ({}, []), sys.argv[3]))),
         ("an interpreter that is gone", lambda: (setattr(m.sys, "executable", "/nonexistent/python3"),
                                                 m.detach("wait_for_end", t, ({}, []), sys.argv[3]))),
         ("a waiter that dies at its start", lambda: (setattr(m.sys, "executable", PY),
                                                     m.detach("wait_for_end", t, ({},), sys.argv[3]))))
for name, fix in cases:
    try:
        fix()
        print(name, "detached")
    except OSError as e:
        print(name, "OSError:", e)
EOF
has "$T/out" "a waiter not in WAITERS OSError: no such waiter: print" "detach names its waiter from WAITERS, never any function"
has "$T/out" "a spec that will not encode OSError: the waiter's spec does not encode" "  a spec no exec could carry: the caller's OSError"
has "$T/out" "no interpreter named OSError: no interpreter to exec the waiter with" "  no sys.executable: the caller's OSError"
has "$T/out" "an interpreter that is gone OSError: [Errno 2] the waiter's exec failed: No such file or directory" \
    "  an exec that fails is the caller's OSError (its callers give the lock back), never a silent grandchild"
has "$T/out" "a waiter that dies at its start OSError: the waiter died at its start" \
    "  a waiter whose arguments do not bind says no ok: the caller's OSError, not a lock held for 10 min"
has "$T/gone.log" "TypeError" "  and its traceback is in the run's log"

echo "the login: picked at start from the account pool (work-account E5, 2026-10-08)"
ln -s "$T" "$HOME/projects"   # bin/account names a repo by its path under ~/projects: $T/repo is "repo"
mkdir -p "$HOME/.acct-c"
# pool <repos acct-a's tenant holds, off acct-c> <acct-c 5h> <acct-a 5h>: both rows read just now, so no probe runs
# (a deny list on acct-c until deny-drift, 2026-11-03: tenancy routes, nothing bans)
pool() {
  python3 - "$T/accounts.json" "$HOME" "$@" <<'EOF'
import json, sys, time
f, home, held, i5, d5 = sys.argv[1], sys.argv[2], json.loads(sys.argv[3]), float(sys.argv[4]), float(sys.argv[5])
reg = {"accounts": [
    {"label": "acct-c", "home": home + "/.acct-c", "rules": {"window_max": 50}},
    {"label": "acct-a", "home": home + "/.claude", "primary": True, "rules": {"window_max": 50}}]}
if held:
    reg["accounts"][1]["tenant"] = "own"
    reg["tenants"] = {"own": {"repos": held}}
json.dump(reg, open(f, "w"))
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
STUB_REPLY="$T/stop.txt" afp --rule A --by sweep > "$T/out" 2>&1; check "$?" "0" "a repo acct-a's tenant holds starts too"
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
check "$(sed 's/--repo [^ ]*repo /--repo R /' "$T/acct.calls")" "pick --repo R --json --cached --overdraw --job $BR" "  its pick was --cached (an overdraw judged too: the pick only decides)"
next_tip "pool: overdraw"; : > "$T/acct.calls"
STUB_REPLY="$T/stop.txt" AUTOFINISH_ACCOUNT="$T/acct-log" afp --rule A --by sweep > "$T/out" 2>&1; check "$?" "0" "a sweep's landing starts"
ended
check "$(sed 's/--repo [^ ]*repo /--repo R /' "$T/acct.calls")" "pick --repo R --json --overdraw --job $BR" \
  "  its fresh pick asks for an overdraw, naming the branch (the owner, 2026-11-04: a landing is a job too)"
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
has "$T/out" "exec env REGATTA_UNATTENDED=dispatch CLAUDE_UNATTENDED=dispatch" "  dispatch's dry run: the runner's exec line, the marker under both names (vendor-fence)"
has "$T/out" "--remote-control finish-demo\\ ·\\ buildbox" "  with the whole claude command line"
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
  DISPATCH_SHIP= DISPATCH_PLAN=lp af --dry > /dev/null 2>&1; check "$?" "4" "  the older name, DISPATCH_PLAN, the same (DISPATCH_SHIP cleared: a skippered run exports it)"
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

echo "--by chain: the tick relaunches an S4 stop only, twice per tip (orchestration B3)"
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
has "$T/out" "no network, sleep or usage-limit stop" "  saying so"
echo "  a login's usage limit is relaunched as a network stop is (queue-followthrough, 2026-11-01)"
printf "You've hit your 5-hour limit · resets 9:20pm (America/Los_Angeles)\n" > "$T/limit.txt"
next_tip "chain: a usage-limit stop"; LTIP=$(git -C "$W" rev-parse HEAD); rm -f "$CHAINF"
STUB_REPLY="$T/limit.txt" af --rule D --by sweep > /dev/null 2>&1; ended
check "$(field outcome)/$(field gate)" "stopped/no-landing" "a usage-limit stop: stopped at no-landing"
af --dry > "$T/out" 2>&1; check "$?" "3" "  every other caller: no retry on the same tip, as before"
# no login has room: the pick refuses before any session (count_chain runs after it), and no relaunch is spent
afa() { ACCOUNTS_FILE="$T/accounts.json" ACCOUNT_CLAUDE=false afp "$@"; }   # the pool's registry (the accounts' cases above)
pool '[]' 90 90; SBEFORE=$(field session)
afa --rule D --by chain > "$T/out" 2>&1; check "$?" "3" "  --by chain while no login has room: refused"
has "$T/out" "no account may run this now" "    by the pick"
check "$(field session):$([ -e "$CHAINF" ] && echo counted || echo none)" "$SBEFORE:none" "    no state written, no relaunch counted: the next tick tries again"
pool '[]' 10 10
STUB_REPLY="$T/limit.txt" afa --rule D --by chain > "$T/out" 2>&1; check "$?" "0" "  a login with room: --by chain relaunches it"
ended
check "$(field tip)/$(field by)/$(field account)" "$LTIP/chain/acct-c" "    on the same tip, recorded by chain, on the login the pick chose"
STUB_REPLY="$T/limit.txt" afa --rule D --by chain > /dev/null 2>&1; ended
afa --dry --by chain > "$T/out" 2>&1; check "$?" "3" "  a third relaunch on the tip is refused: the cap counts a limit's relaunches too"
has "$T/out" "2 chain relaunches on this tip already" "    saying how many"
printf "⏳ SAM, THIS SESSION IS WAITING FOR SOMETHING — You've hit your 5-hour limit, CI first\n" > "$T/limitq.txt"
next_tip "chain: a WAITING line quoting the limit"
STUB_REPLY="$T/limitq.txt" af --rule D --by sweep > /dev/null 2>&1; ended
af --dry --by chain > "$T/out" 2>&1; check "$?" "3" "  a WAITING line that quotes the limit is no S4 stop (R4): refused"
has "$T/out" "no network, sleep or usage-limit stop" "    by the pattern"
printf "You've hit your Opus limit · resets Fri 9am\n" > "$T/limito.txt"
next_tip "chain: a per-model limit"
STUB_REPLY="$T/limito.txt" af --rule D --by sweep > /dev/null 2>&1; ended
af --dry --by chain > "$T/out" 2>&1; check "$?" "3" "  a per-model limit, which no pick judges, is no S4 stop: refused"
has "$T/out" "no network, sleep or usage-limit stop" "    by the pattern"
rm -f "$CHAINF"
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
echo "  a handed launch stays one on a chain relaunch (task-shape S2)"
next_tip "chain: handed"
STUB_REPLY="$T/net.txt" af --rule C --by handed > /dev/null 2>&1; ended
check "$(field by)/$(field gate)" "handed/no-landing" "the handed landing stopped at no-landing"
af --dry --by chain > "$T/out" 2>&1; check "$?" "0" "--by chain --dry"
has "$T/out" ", by handed via=chain" "  runs it as handed: no person's yes is minted by the tick"
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
echo "  a handed launch (task-shape S2, D1-C): judged as a typed /finish, never a person's yes"
handland() { python3 - "$B/autofinish-run" "$W" "$R" "$BR" "$1" "$2" "${3:-C}" <<'PYHL'
import sys
from importlib.machinery import SourceFileLoader
m = SourceFileLoader("autofinish_run_hl", sys.argv[1]).load_module()
real = SourceFileLoader("autofinish_hl", sys.argv[1].rsplit("/", 1)[0] + "/autofinish").load_module()
class Af:
    LAND_MODES = ("yolo", "dnd")
    effective_mode = staticmethod(real.effective_mode)
    def landing_mode(self, branch, repo): return (None if sys.argv[6] in "-!" else sys.argv[6], "the mode")
    def mode_unreadable(self, why): return sys.argv[6] == "!"
    def handed_held(self, repo, wt, main):
        if sys.argv[5] == "raises":
            raise OSError("git")
        return None if sys.argv[5] == "lands" else "a held path (hooks/h.py; the handed slice, task-shape D1)"
    def held_slice(self, repo, wt, main, mode): return "held_slice under %s" % mode
m._lander = (lambda: None) if sys.argv[5] == "absent" else (lambda: Af())
t = type("T", (), {"path": sys.argv[2], "primary": sys.argv[3], "branch": sys.argv[4]})()
print(m.landing(t, "handed", sys.argv[7])[0])
PYHL
}
check "$(handland lands default)" "None" "a --by handed launch in mode default: may merge, judged by handed_held"
check "$(CLAUDE_UNATTENDED=dispatch handland lands default)" "None" "  from dispatch's unattended caller too: the label is the road, the slice the judge"
check "$(handland held default)" "a held path (hooks/h.py; the handed slice, task-shape D1)" "  a slice handed_held names (D1-A or B later) holds it"
check "$(handland raises default)" "the handed slice could not be read (OSError)" "  a judge that raises: held"
check "$(handland absent default)" "the lander's judge did not load (bin/autofinish)" "  the lander absent: held"
check "$(handland lands ask)" "mode ask — nothing lands by itself" "  mode ask holds it: handed is never in PERSON_BY"
check "$(handland lands !)" "the mode is unreadable now (the mode)" "  a mode that cannot be read: held, as a mode launch is (mode ask is its one wall)"
check "$(handland lands default M)" "held_slice under default" "  with rule M it is a mode launch, judged by held_slice under the mode (so S3 never sends that pair)"
python3 - "$B/autofinish-run" > "$T/out" 2>&1 <<'PYHC'
import sys
from importlib.machinery import SourceFileLoader
m = SourceFileLoader("autofinish_run_hc", sys.argv[1]).load_module()
print(m.HANDED in m.CHAIN_KEEPS, m.HANDED in m.PERSON_BY, m.HANDED in m.MERGE_BY)
print(m.ladder_stay(type("T", (), {})(), type("A", (), {"rule": "C"})(), "handed"))
PYHC
check "$(sed -n 1p "$T/out")" "True False False" "  handed in CHAIN_KEEPS, never in PERSON_BY or MERGE_BY"
check "$(sed -n 2p "$T/out")" "a --by handed launch is judged by this host's plans (mode ask holds it)" \
  "  ladder_stay pins its finish to this host"
next_tip "handed: the dry runs"
modefix default
af --dry --by handed > "$T/out" 2>&1; check "$?" "0" "mode default, --by handed --dry"
has "$T/out" "mode default: may merge, past the check and the review gate" "  a done default build's hand-over carries no hold (D1-C)"
has "$T/out" "/finish\ $BR\ --unattended --session-id" "  a plain /finish --unattended: no --hold, no mode flag"
has "$T/out" '"by": "handed"' "  the state says handed, which bin/pr re-judges by handed_held"
af --dry --by handed --rule M > "$T/out" 2>&1
has "$T/out" "held at a ready PR — mode default — a taken answer never lands there (yolo-veto D1)" "  --by handed --rule M: held"
af --dry --by handed --merge > "$T/out" 2>&1; check "$?" "2" "--merge with --by handed: refused, exit 2"
has "$T/out" "--merge needs a person's yes" "  saying why"
rm -f "$MRUNS/zz-mode.json"

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
has "$T/out" "The run: session $SID (ListAgents lists it by its cwd, $(git -C "$W" rev-parse --show-toplevel)), window and Remote Control \"finish-demo · buildbox\"" "  the run's id, how to find it, and the Remote Control name dispatch recorded"
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
printf '{"repos": {}, "scopes": {"home": {"repos": ["*/repo"]}, "work": {"repos": ["*/repo"], "confidential": true, "rotation": false}}}\n' > "$T/repos.json"
af --dry > "$T/out" 2>&1
has "$T/out" "rotation fenced: scope work does not rotate (rotation: false)" "a repo in an open scope and one with rotation: false: fenced, not only the first scope judged"
printf '{"repos": {}, "scopes": {"work": {"repos": ["*/repo"], "confidential": true, "rotation": "no"}}}\n' > "$T/repos.json"
af --dry > "$T/out" 2>&1
has "$T/out" "rotation fenced: scope work's rotation is 'no', not true or false" "a rotation that is no bool: fenced (a narrowing key that does not read)"
printf '{"repos": {}, "scopes": {"home": {"repos": ["*/repo"]}, "work": {"repos": ["*/repo"], "confidential": true}}}\n' > "$T/repos.json"
AUTOFINISH_COIN=1 af --dry > "$T/out" 2>&1
has "$T/out" "finisher sonnet-medium (claude-sonnet-5-5, medium): rotation on until 2099-12-31; coin 1: sonnet-medium" "a confidential scope with no rotation key draws (the drawing shape)"
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
next_tip "rotation: confidential, drawing"; : > "$T/claude.calls"; N0=$(rows)
AUTOFINISH_COIN=1 STUB_REPLY="$T/stop.txt" af --rule A --by sweep > /dev/null 2>&1; ended
has "$T/claude.calls" "--model claude-sonnet-5-5 --effort medium" "a confidential scope with no rotation key: claude ran the drawn arm"
check "$(rows)" "$((N0 + 1))" "  one row at the end"
check "$(tail -1 "$ROWS" | python3 -c 'import json, sys; r = json.load(sys.stdin); print(r["arm"], r["scope"], r["confidential"])')" "sonnet-medium work True" \
  "  the row carries its scope and confidential: true, so trim can tell"
reg ', "confidential": true, "rotation": false'
next_tip "rotation: confidential"; : > "$T/claude.calls"; N0=$(rows)
af --dry > "$T/out" 2>&1
has "$T/out" "finisher today's: rotation fenced: scope work does not rotate (rotation: false) — today's finisher, no row" "a confidential scope with rotation: false: today's finisher (the opted-out shape)"
AUTOFINISH_COIN=1 STUB_REPLY="$T/stop.txt" af --rule A --by sweep > /dev/null 2>&1; ended
hasnt "$T/claude.calls" "--model claude-" "  no arm passed, whatever the coin"
check "$(armof)" "none" "  no arm in the state"
has "$AFLOG" "arm=off (rotation fenced: scope work does not rotate (rotation: false)" "  the key there, no arm: the start line says why"
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
reg ', "confidential": true, "rotation": false'
sleep 1; kill -TERM "$CP"; ended
check "$(rows)" "$N0" "  …writes no row once the scope opted out of the coins"
has "$AFLOG" "no rotation row: scope work does not rotate (rotation: false)" "  and its end line says so"

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
reg ', "confidential": true, "rotation": false'
"$B/autofinish-run" rotation --json > "$T/out" 2>&1
check "$(python3 -c 'import json, sys; d = json.load(open(sys.argv[1])); print(d["rows"], d["fenced_now"] > 0)' "$T/out")" "0 True" "  a repo whose scope opted out now: its rows are passed over"
reg ', "confidential": true'
"$B/autofinish-run" rotation --json > "$T/out" 2>&1
check "$(python3 -c 'import json, sys; d = json.load(open(sys.argv[1])); print(d["rows"] > 0, d["fenced_now"])' "$T/out")" "True 0" "  a confidential scope that rotates: its rows are counted"
rm -f "$ROT"; unset CLAUDE_REPOS_JSON

echo "the ledger reads a landing: the pushed head, a row for every run, --settle's nine conditions (task-shape S1)"
export CLAUDE_REPOS_JSON="$T/repos.json"; reg ""
cat > "$T/push.py" <<'PY'
import importlib.machinery, json, os, subprocess, sys, types
af = importlib.machinery.SourceFileLoader("afr", sys.argv[1]).load_module()
t = af.Tree(sys.argv[2]); br = t.branch
head = af.remote_heads(t, br, "main"); sha = head[br]
d = os.path.join(os.environ["CLAUDE_CONFIG_DIR"], "projects", "push"); os.makedirs(d, exist_ok=True)
def tr(sid, calls):
    with open(os.path.join(d, sid + ".jsonl"), "w") as f:
        for i, (cmd, out) in enumerate(calls):
            f.write(json.dumps({"type": "assistant", "message": {"content": [
                {"type": "tool_use", "id": "u%d" % i, "name": "Bash", "input": {"command": cmd}}]}}) + "\n")
            f.write(json.dumps({"type": "user", "message": {"content": [
                {"type": "tool_result", "tool_use_id": "u%d" % i, "content": out}]}}) + "\n")
send = "git push --force-with-lease -u origin "
upd = lambda new, ref, old="1111111", sep="...": " + %s%s%s %s -> %s (forced update)" % (old, sep, new, ref, ref)
tr("p-ok", [(send + br, "To github.com:test/repo.git\n" + upd(sha[:7], br) + "\nbranch set up to track")])
tr("p-list", [(send + br, [{"type": "text", "text": upd(sha[:9], br, sep="..")}])])
tr("p-later", [(send + br, upd(sha[:7], br)), (send + br, upd("2222222", br, old=sha[:7]))])
tr("p-cat", [("cat push.log", upd(sha[:7], br))])
tr("p-other", [(send + "claude/x/other", upd(sha[:7], "claude/x/other"))])
tr("p-gone", [(send + "claude/x/gone", upd(sha[:7], "claude/x/gone"))])
utd = "Everything up-to-date"
tr("p-utd", [(send + br, utd)])
tr("p-utd-other", [(send + "claude/x/other", utd)])
for sid in ("p-ok", "p-list", "p-later", "p-cat", "p-other", "p-none"):
    f = af.landing_fields(t, sid)
    print(sid, f["pushed"] == sha if f["pushed"] else None, f["pushed"] != t.tip, f["base"], f["base_tip"] == head["main"])
gone = types.SimpleNamespace(primary=t.primary, branch="claude/x/gone")
print("p-gone", af.landing_fields(gone, "p-gone")["pushed"])
print("p-utd-moved", af.landing_fields(t, "p-utd")["pushed"])
wt = os.path.join(d, "wt-utd")
subprocess.run(["git", "-C", t.primary, "fetch", "-q", "origin", br], check=True)
subprocess.run(["git", "-C", t.primary, "worktree", "add", "-q", "--detach", wt, "FETCH_HEAD"], check=True)
at = types.SimpleNamespace(primary=t.primary, branch=br, path=wt)
print("p-utd", af.landing_fields(at, "p-utd")["pushed"] == sha, "p-utd-other", af.landing_fields(at, "p-utd-other")["pushed"])
PY
python3 "$T/push.py" "$B/autofinish-run" "$W" > "$T/out" 2>&1
has "$T/out" "p-ok True True main True" "pushed: the sha the run's own push sent, origin's branch holding it at the end; never the local HEAD; the base and its tip"
has "$T/out" "p-list True True" "  a tool result as a list of text blocks, a fast-forward's two dots"
has "$T/out" "p-later None" "  a later push that origin does not hold: unknown, never the earlier one"
has "$T/out" "p-cat None" "  a push report the session only printed: no push"
has "$T/out" "p-other None" "  a push of another branch: no push of this one"
has "$T/out" "p-none None" "  no transcript: unknown"
has "$T/out" "p-gone None" "  a branch origin no longer has (merged and deleted): unknown"
has "$T/out" "p-utd True p-utd-other None" "  a push that found origin up to date: origin's head, the worktree at it (the hook pushed first); never another branch's"
has "$T/out" "p-utd-moved None" "  …and unknown while the worktree's HEAD is not origin's head"

next_tip "ledger: a run with no arm"; N0=$(rows)
STUB_REPLY="$T/stop.txt" af --rule A --by sweep > /dev/null 2>&1; ended; SID=$(field session)
check "$(rows)" "$((N0 + 1))" "the rotation off: a row all the same"
RREC=$(ls "$LOGS"/run-seed-runs/*."${SID:0:8}".json | head -1)
check "$(tail -1 "$ROWS" | python3 -c '
import json, sys
r = json.load(sys.stdin); d = json.load(open(sys.argv[1]))
print(r["arm"], r["coin"], r["forced"], r["model"] == d["model"] and bool(r["model"]), r["effort"], r["by"], r["rule"],
      r["outcome"], r["gate"], r["pushed"], r["base"], r["base_tip"] == sys.argv[2], r["landing"])' "$RREC" "$(git -C "$T/origin.git" rev-parse main)")" \
  "None None False True medium sweep A stopped G4 None main True None" "  arm null, the model dispatch ran and the finish skill's effort (not dispatch's), by and rule; the base and its tip; no push read (the stub never pushed)"
check "$(python3 -c 'import json, sys; s = json.load(open(sys.argv[1])); print(s.get("base"), "pushed" in s, len(s.get("base_tip") or ""))' "$STATE")" \
  "main False 40" "  the record gains the base and its tip; an unknown push is left out"
"$B/autofinish-run" rotation --json > "$T/out" 2>&1
check "$(python3 -c 'import json, sys; d = json.load(open(sys.argv[1])); print(d["armless"] >= 1, d["arms"]["(no arm)"]["runs"] == d["armless"])' "$T/out")" \
  "True True" "  rotation counts arm-less rows apart, never in an arm"

# --settle: no-landing rows of repo2; P<n> the head the run pushed, BT main's tip at the run's end
LIVE="$T/r2-live"; git -C "$R2" worktree add -q -b b-live "$LIVE" main
# a peer's run ends in the repo's autofinished, its row on that Mac: one after l-peer's row; l-peerown's own end
# before its row, and a never-started line after it (nothing ran)
AFD="$(git -C "$R2" rev-parse --path-format=absolute --git-common-dir)/claude"; mkdir -p "$AFD"
printf '%s\n' "2026-10-10T11:30:00-07:00 stopped l-peer no-landing a peer's run" \
  "2026-10-10T10:20:00-07:00 stopped l-peerown no-landing its own end" \
  "2026-10-10T11:30:00-07:00 never-started l-peerown nothing ran" >> "$AFD/autofinished"
mkdir -p "$T/link" && ln -s "$R2" "$T/link/repo2"   # another spelling of repo2 (its scope's glob still matches)
mkdir -p "$(git -C "$LIVE" rev-parse --absolute-git-dir)/claude"
printf '{"started": "2026-10-10T11:00:00-07:00", "session": "l-live-2"}\n' > "$(git -C "$LIVE" rev-parse --absolute-git-dir)/claude/autofinish.json"
python3 - "$ROWS" "$R2" "$T/link/repo2" <<'PY'
import json, sys
rows, primary, link = sys.argv[1], sys.argv[2], sys.argv[3]
def row(b, pr, sid=None, started="2026-10-10T10:00:00-07:00", **k):
    r = {"ts": "2026-10-10T13:00:00-07:00", "host": "laptop", "repo": "repo2", "primary": primary, "slug": "test/repo2",
         "main": "main", "branch": b, "session": sid or b, "started": started, "arm": "opus-medium", "coin": 0,
         "outcome": "stopped", "gate": "no-landing", "pr": pr, "pushed": "%040x" % pr, "base": "main", "base_tip": "b" * 40,
         "settled": None, "landing": None}
    r.update(k)
    return r
out = [row("l-ok", 60), row("l-reset", 61, pushed="b" * 40), row("l-net0", 62), row("l-older", 63),
       row("l-missing", 64, base_tip=None), row("l-moved", 65),
       row("l-later", 66, sid="l9a"), row("l-later", 66, sid="l9b", started="2026-10-10T11:00:00-07:00"),
       row("l-before", 67), row("l-base", 68), row("l-mcs", 69), row("l-by", 70), row("l-open", 71), row("l-closed", 72),
       row("b-live", 74, sid="l-live-1"), row("l-stopped", 75, gate="G1r"),
       row("l-peer", 76, ts="2026-10-10T10:30:00-07:00"), row("l-peerown", 77, ts="2026-10-10T10:30:00-07:00"),
       row("l-spell", 78, sid="ls-a"), row("l-spell", 78, sid="ls-b", started="2026-10-10T11:00:00-07:00", primary=link),
       row("l-ns", 79, sid="ln-a"), row("l-ns", 79, sid="ln-b", started="2026-10-10T11:00:00-07:00",
                                         outcome="never-started", gate="never-started")]
old = row("l-old", 73)
for k in ("pushed", "base", "base_tip", "landing"):
    old.pop(k)
out.append(old)
with open(rows, "a") as f:
    f.writelines(json.dumps(r) + "\n" for r in out)
PY
cat > "$T/api_land.py" <<'PY'
import json, os
MERGED = "2026-10-10T19:00:00Z"   # 12:00 PDT: after every row's start but l-before's merge
def api(method, path, body=None, tok=None, timeout=15):
    with open(os.environ["STUB_LAND_LOG"], "a") as f:
        f.write(path + "\n")
    if not path.startswith("/repos/test/repo2/pulls/") or "/" in path[len("/repos/test/repo2/pulls/"):]:
        return 404, None
    n = int(path.rsplit("/", 1)[1]); pushed = "%040x" % n
    p = {"number": n, "state": "closed", "merged_at": MERGED, "base": {"ref": "main"}, "head": {"sha": pushed},
         "merge_commit_sha": "c" * 40, "merged_by": {"login": "automerge"}, "additions": 3, "deletions": 1}
    p.update({61: {"head": {"sha": "b" * 40}},             # (5) the branch reset onto main: the head is main's tip
              62: {"additions": 0, "deletions": 0},        # (8) commits that net to nothing
              63: {"head": {"sha": "d" * 40}},             # (4) an older PR of the branch, merged at another head
              65: {"head": {"sha": "e" * 40}},             # (4) origin's head moved after the run: a second push merged
              67: {"merged_at": "2026-10-10T16:00:00Z"},   # (2) merged before the run started
              68: {"base": {"ref": "release"}},            # (3) merged into another base
              69: {"merge_commit_sha": pushed},            # (6) no merge commit apart from the head
              70: {"merged_by": None},                     # (7) nobody merged it
              71: {"state": "open", "merged_at": None},    # open: read again later
              72: {"merged_at": None}}.get(n, {}))         # closed unmerged
    return 200, p
PY
: > "$T/api_land.log"
STUB_LAND_LOG="$T/api_land.log" AUTOFINISH_API_STUB="$T/api_land.py" "$B/autofinish-run" rotation --settle > "$T/out" 2>&1; check "$?" "0" "rotation --settle over no-landing rows"
has "$T/out" "5 landing(s) settled now" "  five runs proved landed"
land() { python3 - "$ROWS" "$1" <<'PY'
import json, sys
for l in open(sys.argv[1]):
    r = json.loads(l)
    if r.get("session") == sys.argv[2]:
        print(r.get("landing"), (r.get("landing_why") or "-").split(" ")[0], r.get("merged_at"))
PY
}
check "$(land l-ok)" "settled - 2026-10-10T19:00:00Z" "  all nine hold: launched (settled), the merge time kept"
check "$(land l-reset)" "unknown (5) 2026-10-10T19:00:00Z" "  a branch reset onto main (the head is the base's tip): unknown (5)"
check "$(land l-net0)" "unknown (8) 2026-10-10T19:00:00Z" "  work that nets to nothing: unknown (8)"
check "$(land l-older)" "unknown (4) 2026-10-10T19:00:00Z" "  an older merged PR at another head: unknown (4)"
check "$(land l-missing)" "None - None" "  a field missing: never read (1)"
check "$(land l-moved)" "unknown (4) 2026-10-10T19:00:00Z" "  origin's head moved after the run, a second push merged: unknown (4)"
check "$(land l9a)" "unknown (9) 2026-10-10T19:00:00Z" "  a later run readied the same head before the merge: the earlier row unknown (9)"
check "$(land l9b)" "settled - 2026-10-10T19:00:00Z" "  …and the later one settles"
check "$(land l-before)" "unknown (2) 2026-10-10T16:00:00Z" "  merged before the run started: unknown (2)"
check "$(land l-base)" "unknown (3) 2026-10-10T19:00:00Z" "  merged into another base: unknown (3)"
check "$(land l-mcs)" "unknown (6) 2026-10-10T19:00:00Z" "  no merge commit apart from the head: unknown (6)"
check "$(land l-by)" "unknown (7) 2026-10-10T19:00:00Z" "  no merged_by: unknown (7)"
check "$(land l-open)" "None - None" "  an open PR: read again at the next settle"
check "$(land l-closed)" "unknown (2) None" "  closed unmerged: unknown"
check "$(land l-peer)" "unknown (9) 2026-10-10T19:00:00Z" "  a peer Mac's run on the branch ended after the row, before the merge (its autofinished line): unknown (9)"
check "$(land l-peerown)" "settled - 2026-10-10T19:00:00Z" "  …but the row's own end before it, and a never-started line, are no later run"
check "$(land ls-a)" "unknown (9) 2026-10-10T19:00:00Z" "  a later run whose row spells the repo by a link (same_repo, real paths): unknown (9)"
check "$(land ls-b)" "settled - 2026-10-10T19:00:00Z" "  …and the later one settles"
check "$(land ln-a)" "settled - 2026-10-10T19:00:00Z" "  a later row that never started ran nothing: no later run (9)"
check "$(land l-live-1)" "unknown (9) 2026-10-10T19:00:00Z" "  a later run still going (its worktree's record, no row yet): unknown (9)"
check "$(land l-stopped)" "None - None" "  a stop at another gate is never settled"
check "$(land l-old)" "None - None" "  a row from before S1, its branch's PR merged: never settled on its branch name"
check "$(grep -cE '/pulls/(64|73|75)$' "$T/api_land.log")" "0" "  and neither it, the row missing a field nor another gate's stop asked GitHub"
"$B/autofinish-run" rotation --json > "$T/out" 2>&1
check "$(python3 -c 'import json, sys; d = json.load(open(sys.argv[1])); print(d["arms"]["opus-medium"]["landed_settled"])' "$T/out")" \
  "5" "  rotation: launched (settled) counted on its own"
: > "$T/api_land.log"
STUB_LAND_LOG="$T/api_land.log" AUTOFINISH_API_STUB="$T/api_land.py" "$B/autofinish-run" rotation --settle > "$T/out" 2>&1
has "$T/out" "0 landing(s) settled now" "  a second settle changes no row it read"
check "$(sed -nE 's|^/repos/test/repo2/pulls/([6-9][0-9])$|\1|p' "$T/api_land.log" | sort -u | tr '\n' ' ')" "60 66 71 77 78 79 " \
  "  and asks GitHub again only for the open PR and the settled rows' 48 h (of these cases' PRs)"

python3 - "$B/autofinish-run" > "$T/out" 2>&1 <<'PY'
import importlib.machinery, sys
af = importlib.machinery.SourceFileLoader("afr", sys.argv[1]).load_module()
for w in ("⚠ step 1 — not merged: the check failed twice", "⚠ step 1 — the review found 3 defects",
          "⚠ the checkpoint hook refused the commit", "⚠ the panel session is still alive",
          "⚠ step 11 — the merge was refused", "⚠ the review gate refused", "⚠ 2 open items", "⚠ the live system differs",
          "⚠ step 1 — the check failed; the review never ran", "⚠ the deployment differs", "⚠ the branch is still unmerged",
          "⚠ automerge refused: the base is protected", "⚠ the redeploy differs", "⚠ the worktree deadlocked"):
    print(af.gate_of(w))
PY
check "$(tr '\n' ' ' < "$T/out")" "G1 G1r stop stop G11 G1r G4 G1 G1 G1 G11 G11 G1 G0 " \
  "gate_of: step first (step 1 never the merge's G11), step 1 split into G1r and G1 (G1r only when the review is the stop it names); words as words (checkpoint no check, alive no live; deployment, unmerged, automerge, redeploy and deadlocked still read)"
rm -f "$ROT"; unset CLAUDE_REPOS_JSON

echo "the verdict: what the caller prints is what dispatch reached, never predicted (night-landings finding 1)"
# stand-ins for dispatch --start: (a) the run's header, its own --session-id ($6) in it, then it goes on; (b) FAILED for
# room, exit 1; (c) silent (dispatch-hang); (d) another session's header and FAILED line in the shared log, then silent
cat > "$T/dispatch-header" <<EOF
#!/bin/bash
echo \$PPID > "$T/hdr.waiter"
echo "== claude 4242, session \$6, screen s, Remote Control \"finish · demo\"; state /x"
exec sleep 60
EOF
cat > "$T/dispatch-sibling" <<EOF
#!/bin/bash
echo \$PPID > "$T/sib.waiter"
echo "== claude 999, session aaaaaaaa-0000-4000-8000-000000000000, screen s, Remote Control \"finish · demo\"; state /x"
echo "FAILED: buildbox: no room: 86 % free, under 101 % (wharf-runs/headroom buildbox:); not starting another"
exec sleep 60
EOF
cat > "$T/dispatch-noroom" <<EOF
#!/bin/bash
echo "FAILED: buildbox: no room: 86 % free, under 101 % (wharf-runs/headroom buildbox:); not starting another"; exit 1
EOF
chmod +x "$T/dispatch-header" "$T/dispatch-sibling" "$T/dispatch-noroom"

next_tip "verdict: header"; : > "$T/api.log"
AUTOFINISH_DISPATCH="$T/dispatch-header" af > "$T/out" 2> "$T/err"; check "$?" "0" "a run's header in the log: started, exit 0"
has "$T/out" 'started: /finish claude/laptop/2026-10-05-demo --unattended — window and Remote Control "finish-demo"' "  the line is the started one"
check "$(field ended)" "null" "  the run goes on: not ended"
check "$([ -f "$LOCK" ] && echo held || echo free)" "held" "  and holds the lock"
kill -TERM "$(cat "$T/hdr.waiter")"; ended

next_tip "verdict: a sibling's lines"; : > "$T/api.log"; rm -f "$T/sib.waiter"
AUTOFINISH_VERDICT_S=2 AUTOFINISH_DISPATCH="$T/dispatch-sibling" af > "$T/out" 2> "$T/err"; check "$?" "0" "another session's header and FAILED line: not this run's verdict, exit 0"
has "$T/out" "not confirmed after 2 s:" "  not confirmed, neither started nor refused"
hasnt "$T/out" "started:" "  no \"started\" line for another session's header"
hasnt "$T/err" "not started" "  no refusal for another session's FAILED line"
check "$(field ended)" "null" "  the run is not ended: the waiter settles it"
for _ in $(seq 1 50); do [ -s "$T/sib.waiter" ] && break; sleep 0.2; done
kill -TERM "$(cat "$T/sib.waiter")"; ended

next_tip "verdict: no room"; : > "$T/api.log"
AUTOFINISH_DISPATCH="$T/dispatch-noroom" af > "$T/out" 2> "$T/err"; check "$?" "5" "dispatch refused for room: exit 5, not 0 and not 1"
has "$T/err" "not started: buildbox: no room: 86 % free, under 101 % (wharf-runs/headroom buildbox:); not starting another" "  dispatch's own FAILED text"
has "$T/err" "the next step waits for a run to end" "  in the cap's waiting words (CAP_RE, ASK_EXEMPT_RE)"
hasnt "$T/out" "started" "  no \"started\" line"
ended
check "$(field outcome)/$(field gate)" "never-started/refused" "  the state: never-started at refused, ended"
check "$([ -f "$LOCK" ] && echo kept || echo gone)" "gone" "  the lock given back"
check "$(wc -c < "$T/api.log" | tr -d ' ')" "0" "  nothing on the PR: nothing ran"
next_tip "verdict: refused, again"
AUTOFINISH_DISPATCH="$T/dispatch-noroom" af > /dev/null 2>&1; check "$?" "5" "  the tip may start again, and is refused again as plainly"; ended

next_tip "verdict: silent"; : > "$T/api.log"; rm -f "$T/hang.waiter"
AUTOFINISH_VERDICT_S=2 AUTOFINISH_DISPATCH="$T/dispatch-hang" af > "$T/out" 2> "$T/err"; check "$?" "0" "dispatch silent past the bound: exit 0, as callers read a start that may begin"
has "$T/out" "not confirmed after 2 s: dispatch has not said whether the run began" "  not confirmed, on stdout"
has "$T/out" 'Remote Control "finish-demo"; read '"$LOGS/$AUTOFINISH_DAY-dispatch-finish-demo.log" "  naming the window and the log"
hasnt "$T/out" "started:" "  no \"started\" line"
check "$(field ended)" "null" "  the run is not ended: the waiter settles it"
check "$([ -f "$LOCK" ] && echo held || echo free)" "held" "  the lock stays"
for _ in $(seq 1 50); do [ -s "$T/hang.waiter" ] && break; sleep 0.2; done
kill -TERM "$(cat "$T/hang.waiter")"; ended

echo "a second repo, its own origin: the origin gate's fixture (the peer road's until finish-as-task)"
# the laptop's repo in the projects folder, on its own bare origin
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
LGD="$(git -C "$LW" rev-parse --absolute-git-dir)"; LSTATE="$LGD/claude/autofinish.json"; LLOCK="$LGD/claude/owner.json"
lfield() { python3 -c 'import json, sys; v = json.load(open(sys.argv[1])).get(sys.argv[2]); print("null" if v is None else v)' "$LSTATE" "$1"; }
lended() { for _ in $(seq 1 200); do [ "$(lfield ended 2>/dev/null)" != null ] && [ -n "$(lfield ended 2>/dev/null)" ] && return 0; sleep 0.2; done; echo "  (no end recorded here in 40 s)"; tail -5 "$LOGS"/*-dispatch-finish-land.log 2>/dev/null; return 1; }
laf() { AUTOFINISH_HOST=laptop CLAUDE_CODE_SESSION_ID=caller "$B/autofinish-run" "$LW" "$@"; }
lnext() { git -C "$LW" commit -q --allow-empty -m "$1"; }

echo "the origin gate: a tip origin moved past is fast-forwarded or refused (finish-stale-tip)"
# lsync: origin's branch at this worktree's tip. origin_on <message>: origin gains a commit this worktree never saw,
# its sha on stdout. Both without a push verb in this file's text, as the fixture above (the checkpoint hook reads command text)
lsync() { git -C "$L" send-pack "$T/land.git" "+$LB:refs/heads/$LB" >/dev/null 2>&1; }
# Each changes a file, gate-file.txt, to its message: a fast-forward that moved only HEAD would show
origin_on() { local o="$T/land.git" p b; p=$(git -C "$o" rev-parse "refs/heads/$LB"); b=$(printf '%s\n' "$1" | git -C "$o" hash-object -w --stdin)
  GIT_INDEX_FILE="$T/land.idx" git -C "$o" read-tree "$p"; GIT_INDEX_FILE="$T/land.idx" git -C "$o" update-index --add --cacheinfo "100644,$b,gate-file.txt"
  git -C "$o" update-ref "refs/heads/$LB" "$(git -C "$o" -c user.name=t -c user.email=t@t commit-tree "$(GIT_INDEX_FILE="$T/land.idx" git -C "$o" write-tree)" -p "$p" -m "$1")"
  rm -f "$T/land.idx"; git -C "$o" rev-parse "refs/heads/$LB"; }
catch_up() { git -C "$LW" fetch -q origin; git -C "$LW" merge -q --ff-only "$(git -C "$T/land.git" rev-parse "refs/heads/$LB")"; }
lhead() { git -C "$LW" rev-parse HEAD; }
calls() { wc -l < "$T/claude.calls" | tr -d ' '; }

lnext "gate: a stop on this tip"; lsync; GOLD=$(lhead)
STUB_REPLY="$T/stop.txt" laf --on here > "$T/out" 2>&1; lended
GNEW=$(origin_on "the build, on origin")
STUB_REPLY="$T/stop.txt" laf --on here > "$T/out" 2>&1; check "$?" "0" "here, behind and clean: started, though its old tip has a stop on record"
has "$T/out" "autofinish-run: $LB fast-forwarded from ${GOLD:0:7} to ${GNEW:0:7}, origin's tip: that tip is the one landed" "  saying so in one line"
hasnt "$T/out" "no retry on the same tip" "  the tip refusal read the tip it lands"
check "$(lhead)/$(cat "$LW/gate-file.txt")" "$GNEW/the build, on origin" "  the worktree is at origin's tip, its files too"
check "$(lfield tip)" "$GNEW" "  and the run's state names it"
lended
has "$T/at-start.$(lfield session).bundle" "fast-forwarded this worktree from ${GOLD:0:7} to ${GNEW:0:7}" "  its bundle says what it took in: /finish's own step finds nothing to take"
has "$T/at-start.$(lfield session).bundle" "the build, on origin" "    naming the commits"
STUB_REPLY="$T/stop.txt" laf --on here > "$T/out" 2>&1; check "$?" "3" "  that tip's stop then holds it, as any tip's"
has "$T/out" "no retry on the same tip" "    the same-tip refusal, on the tip it landed"

GOLD=$(lhead); GNEW=$(origin_on "more of the build, on origin")
STUB_REPLY="$T/launch.txt" laf > "$T/out" 2>&1; check "$?" "0" "no --on here, no queue home: behind and clean, started here"
has "$T/out" "$LB fast-forwarded from ${GOLD:0:7} to ${GNEW:0:7}" "  fast-forwarded first"
lended
lnext "past that launch: a launched tip keeps its refusal, below"; lsync

GOLD=$(lhead); GNEW=$(origin_on "a third, on origin"); git -C "$LW" fetch -q origin
STUB_REPLY="$T/stop.txt" laf --on here > "$T/out" 2>&1; check "$?" "0" "origin's commit already fetched here: the same fast-forward"
check "$(lhead)" "$GNEW" "  at origin's tip"
lended

GOLD=$(lhead); GNEW=$(origin_on "a typed turn")
AUTOFINISH_SEND_BUDGET=110 STUB_REPLY="$T/stop.txt" laf --on here --by typed > "$T/out" 2>&1; check "$?" "0" "a typed start, behind and clean: a person's, so it lands that tip"
check "$(lhead)/$(lfield tip)" "$GNEW/$GNEW" "  moved, and the state names it"
lended

GOLD=$(lhead); GNEW=$(origin_on "the sweep's turn"); N=$(calls)
STUB_REPLY="$T/stop.txt" laf --on here --rule A --by sweep > "$T/out" 2>&1; check "$?" "6" "the sweep, behind and clean: refused, nothing ran"
has "$T/out" "this start was judged on ${GOLD:0:7}, not ${GNEW:0:7}: the next start judges that tip" "  its gates judged the old tip"
check "$(lhead)" "$GNEW" "  the tree moved, so the next pass judges that tip"
check "$(calls)" "$N" "  no session began"
STUB_REPLY="$T/stop.txt" laf --on here --rule A --by sweep > "$T/out" 2>&1; check "$?" "0" "  the next pass starts it"
hasnt "$T/out" "fast-forwarded" "    with nothing left to move"
has "$T/at-start.$(lfield session).bundle" "fast-forwarded this worktree from ${GOLD:0:7} to ${GNEW:0:7}" "    its bundle names the move the pass before made (landing review)"
has "$T/at-start.$(lfield session).bundle" "git diff ${GOLD:0:7} ${GNEW:0:7} -- <memo>" "    and the diff that shows an answer, never keel pull"
lended
for by in yolo brief; do
  GOLD=$(lhead); GNEW=$(origin_on "the $by turn"); N=$(calls)
  STUB_REPLY="$T/stop.txt" laf --on here --by "$by" > "$T/out" 2>&1; check "$?" "6" "--by $by, behind and clean: stopped too, no verdict judged that tip"
  has "$T/out" "this start was judged on ${GOLD:0:7}" "  saying so"
  check "$(lhead)/$(calls)" "$GNEW/$N" "  the tree moved, no session"
done
GOLD=$(lhead); GNEW=$(origin_on "an unattended person's word"); N=$(calls)
CLAUDE_UNATTENDED=dispatch STUB_REPLY="$T/stop.txt" laf --on here > "$T/out" 2>&1; check "$?" "6" "--by override from an unattended run: a label, no person: stopped too"
check "$(lhead)/$(calls)" "$GNEW/$N" "  the tree moved, no session"

GOLD=$(lhead); GNEW=$(origin_on "a skipper's word"); N=$(calls)
SKIPPER_SCOPE=dock STUB_REPLY="$T/stop.txt" laf --on here > "$T/out" 2>&1; check "$?" "6" "--by override from a skipper: no person either (wharf --watch's launch names no --by)"
check "$(lhead)/$(calls)" "$GNEW/$N" "  the tree moved, no session"
GOLD=$(lhead); GNEW=$(origin_on "a chain's turn"); N=$(calls)
printf '#!/bin/bash\necho "ending the warm run of it"\n' > "$T/warm-noted"; chmod +x "$T/warm-noted"
AUTOFINISH_END_WARM="$T/warm-noted" STUB_REPLY="$T/stop.txt" laf --on here --by chain > "$T/out" 2>&1; check "$?" "3" "--by chain, no stop of its kind on this tip: refused as on main"
hasnt "$T/out" "ending the warm run" "  no warm run ended for it"
check "$(lhead)/$(calls)" "$GOLD/$N" "  and nothing moved"
catch_up

GOLD=$(lhead); GNEW=$(origin_on "ahead of a dirty tree"); echo scratch > "$LW/untracked.txt"; N=$(calls); before=$(cksum < "$LSTATE")
STUB_REPLY="$T/stop.txt" laf --on here > "$T/out" 2>&1; check "$?" "6" "here, behind and dirty: refused"
has "$T/out" "origin's $LB is at ${GNEW:0:7}, ahead of this worktree's tip ${GOLD:0:7}, and 1 uncommitted file(s) keep it from fast-forwarding" "  saying why"
check "$(lhead)/$(calls)" "$GOLD/$N" "  the tree unmoved, no session"
check "$(cksum < "$LSTATE")" "$before" "  the state untouched"
has "$AFLOG" "refused tip=${GOLD:0:7} rule=C by=override — origin's $LB is at ${GNEW:0:7}, ahead" "  logged as a refusal"
# a warm run ended first may be what made the dirt: its end is judged before the worktree is
printf '#!/bin/bash\necho "ending the warm run of it"\nrm -f "%s"\n' "$LW/untracked.txt" > "$T/warm-cleans"; chmod +x "$T/warm-cleans"
AUTOFINISH_END_WARM="$T/warm-cleans" STUB_REPLY="$T/stop.txt" laf --on here > "$T/out" 2>&1; check "$?" "0" "behind, the dirt a warm run's: ended first, then fast-forwarded"
check "$(lhead)" "$GNEW" "  the tree moved"
lended

# a busy run sees no fast-forward: end-warm's check is the one that reads a run on any login
GOLD=$(lhead); GNEW=$(origin_on "beside a busy run"); N=$(calls)
printf '#!/bin/bash\necho "a run of it is busy (session s): not ending it, not launching"\nexit 3\n' > "$T/warm-busy"; chmod +x "$T/warm-busy"
AUTOFINISH_END_WARM="$T/warm-busy" STUB_REPLY="$T/stop.txt" laf --on here > "$T/out" 2>&1; check "$?" "6" "behind, a dispatch run busy on it: refused"
has "$T/out" "its dispatch run could not be ended first" "  for that"
check "$(lhead)/$(calls)" "$GOLD/$N" "  its tree not moved under it"
catch_up

GNEW=$(origin_on "apart, on origin"); lnext "apart, here"; GOLD=$(lhead); N=$(calls)
STUB_REPLY="$T/stop.txt" laf --on here > "$T/out" 2>&1; check "$?" "6" "here, diverged: refused"
has "$T/out" "origin's $LB is at ${GNEW:0:7}, apart from this worktree's tip ${GOLD:0:7}: neither holds the other" "  saying so"
check "$(lhead)/$(calls)" "$GOLD/$N" "  the tree unmoved, no session"
git -C "$LW" fetch -q origin; git -C "$LW" reset -q --hard "$GNEW"

lnext "gate: equal"; lsync; GOLD=$(lhead)
laf --on here --dry > "$T/out" 2>&1
has "$T/out" "tip ${GOLD:0:7}" "equal: the dry run names the tip"
hasnt "$T/out" "origin's" "  and the gate says nothing"
lnext "gate: ahead"; GOLD=$(lhead)
laf --on here --dry > "$T/out" 2>&1
has "$T/out" "tip ${GOLD:0:7}" "ahead of origin: unchanged too"
hasnt "$T/out" "origin's" "  no word from the gate"
lsync

GOLD=$(lhead); GNEW=$(origin_on "a dry look"); before=$(cksum < "$LSTATE")
laf --on here --dry > "$T/out" 2>&1; check "$?" "0" "--dry, origin's commit not here: exit 0"
has "$T/out" "origin's $LB is at ${GNEW:0:7}, not here: a start fetches it and judges it" "  says what a start does, and fetches nothing"
check "$(git -C "$LW" rev-parse --verify --quiet "$GNEW^{commit}" >/dev/null && echo fetched || echo absent)/$(lhead)" "absent/$GOLD" "  nothing written"
git -C "$LW" fetch -q origin
laf --on here --dry > "$T/out" 2>&1
has "$T/out" "would fast-forward $LB from ${GOLD:0:7} to ${GNEW:0:7}, origin's tip, and land that" "--dry, the commit here: says it would move"
has "$T/out" "tip ${GNEW:0:7}" "  and judges the tip that lands"
check "$(lhead)" "$GOLD" "  the tree unmoved"
laf --on here --dry --rule A --by sweep > "$T/out" 2>&1; check "$?" "6" "--dry --by sweep, origin's commit not here: stops, as a start would"
has "$T/out" "this start was judged on ${GOLD:0:7}" "  saying so"
git -C "$LW" fetch -q origin

# a run launched on this tip, whose own push moved origin on: main's same-tip refusal stands, and the tree stays
python3 - "$LSTATE" "$GOLD" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); d.update(tip=sys.argv[2], ended="2026-10-05T00:00:00+00:00", outcome="launched", gate=None, pr=7, host="buildbox"); json.dump(d, open(sys.argv[1], "w"))
PY
laf --on here --merge > "$T/out" 2>&1; check "$?" "3" "a run launched on this tip, origin past it by that run's push: refused"
has "$T/out" "no retry on the same tip" "  the same-tip refusal"
check "$(lhead)" "$GOLD" "  the tree unmoved"

# a tree in use is never moved: the run going, then a live session's lock
python3 - "$LSTATE" "$GOLD" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); d.update(tip=sys.argv[2], ended=None, outcome=None, gate=None, session="77777777-0000-4000-8000-000000000000")
d.pop("host", None); json.dump(d, open(sys.argv[1], "w"))
PY
laf --on here > "$T/out" 2>&1; check "$?" "3" "a run on the tip not ended: refused"
has "$T/out" "has not ended" "  for that"
check "$(lhead)" "$GOLD" "  its tree not moved under it"
python3 - "$LSTATE" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); d.update(ended="2026-10-05T00:00:00+00:00", outcome="stopped", gate="G4"); json.dump(d, open(sys.argv[1], "w"))
PY
mkdir -p "$HOME"/.claude/sessions; printf '{"pid": %s, "sessionId": "88888888-0000-4000-8000-000000000000", "cwd": "%s", "status": "busy"}' "$$" "$LW" > "$HOME"/.claude/sessions/gate.json
printf '{"session": "88888888-0000-4000-8000-000000000000", "branch": "%s", "seen": %s}' "$LB" "$(date +%s)" > "$LLOCK"
laf --on here > "$T/out" 2>&1; check "$?" "3" "a live session's lock: refused"
has "$T/out" "the worktree's lock is held by session 88888888" "  for that"
check "$(lhead)" "$GOLD" "  its tree not moved under it"
rm -f "$LLOCK" "$HOME"/.claude/sessions/gate.json

git -C "$LW" merge -q --ff-only "$GNEW"; catch_up; GOLD=$(lhead); N=$(calls)
printf '#!/bin/bash\necho "ending the warm run of it"\ngit -C "%s" update-ref "refs/heads/%s" "$(git -C "%s" -c user.name=t -c user.email=t@t commit-tree "%s^{tree}" -p "%s" -m "pushed as it ended")"\n' \
  "$T/land.git" "$LB" "$T/land.git" "$GOLD" "$GOLD" > "$T/warm-moves-here"; chmod +x "$T/warm-moves-here"
AUTOFINISH_END_WARM="$T/warm-moves-here" STUB_REPLY="$T/stop.txt" laf --on here > "$T/out" 2>&1; check "$?" "6" "here, a warm run's end moves origin: read again, refused"
has "$T/out" "moved on to" "  saying so"
check "$(calls)" "$N" "  no session"
catch_up; GOLD=$(lhead); N=$(calls)
# a warm run's end on the gate's own road: its last commit is the tip judged, and origin is read past any failure
GOLD=$(lhead); GNEW=$(origin_on "a warm run commits too"); N=$(calls)
printf '#!/bin/bash\necho "ending the warm run of it"\ngit -C "%s" commit -q --allow-empty -m "its last checkpoint"\n' "$LW" > "$T/warm-commits"; chmod +x "$T/warm-commits"
AUTOFINISH_END_WARM="$T/warm-commits" STUB_REPLY="$T/stop.txt" laf --on here > "$T/out" 2>&1; check "$?" "6" "behind, its warm run's last commit sets the tip apart: refused"
has "$T/out" "apart from this worktree's tip $(git -C "$LW" rev-parse --short=7 HEAD)" "  judged on the tip that commit made"
check "$(calls)" "$N" "  no session"
git -C "$LW" reset -q --hard "$GOLD"; catch_up
GOLD=$(lhead); GNEW=$(origin_on "a warm run takes it in"); N=$(calls)
printf '#!/bin/bash\necho "ending the warm run of it"\ngit -C "%s" fetch -q origin\ngit -C "%s" merge -q --ff-only "%s"\n' "$LW" "$LW" "$GNEW" > "$T/warm-takes"; chmod +x "$T/warm-takes"
AUTOFINISH_END_WARM="$T/warm-takes" STUB_REPLY="$T/stop.txt" laf --on here --rule A --by sweep > "$T/out" 2>&1; check "$?" "6" "the sweep, its warm run took origin in: the tip is not the one it judged"
has "$T/out" "this start was judged on ${GOLD:0:7}, not ${GNEW:0:7}" "  saying so"
check "$(calls)" "$N" "  no session"
git -C "$LW" reset -q --hard "$GOLD"
GOLD=$(lhead); GNEW=$(origin_on "origin goes away"); N=$(calls)
printf '#!/bin/bash\necho "ending the warm run of it"\ngit -C "%s" remote set-url origin "%s"\n' "$L" "$T/gone.git" > "$T/warm-cuts"; chmod +x "$T/warm-cuts"
AUTOFINISH_END_WARM="$T/warm-cuts" STUB_REPLY="$T/stop.txt" laf --on here > "$T/out" 2>&1; check "$?" "6" "proved behind, origin unreadable as the warm run ended: refused, no second pass"
has "$T/out" "could not be read to confirm tip ${GOLD:0:7}" "  saying so"
check "$(lhead)/$(calls)" "$GOLD/$N" "  the tree unmoved, no session"
git -C "$L" remote set-url origin https://github.com/test/land.git; catch_up
GOLD=$(lhead); N=$(calls)
AUTOFINISH_END_WARM="$T/warm-cuts" STUB_REPLY="$T/stop.txt" laf --on here > "$T/out" 2>&1; check "$?" "6" "equal, but a warm run ended here and origin went: refused, start_here reads strictly"
has "$T/out" "could not be read to confirm tip ${GOLD:0:7}" "  saying so"
check "$(calls)" "$N" "  no session"
git -C "$L" remote set-url origin https://github.com/test/land.git

# the one pass, and what is no pass: origin that cannot be read, a commit that cannot be fetched
lnext "gate: offline"; lsync
git -C "$L" remote set-url origin "$T/gone.git"
STUB_REPLY="$T/stop.txt" laf --on here > "$T/out" 2>&1; check "$?" "0" "origin unreadable: started, as it always was"
has "$T/out" "was not compared with origin's" "  saying so"
lended
git -C "$L" remote set-url origin https://github.com/test/land.git
GOLD=$(lhead); GNEW=$(origin_on "not fetchable"); mkdir -p "$T/nofetch"; N=$(calls)
printf '#!/bin/bash\nfor a; do [ "$a" = fetch ] && { echo "fatal: fetch stand-in" >&2; exit 1; }; done\nexec %s "$@"\n' "$(command -v git)" > "$T/nofetch/git"; chmod +x "$T/nofetch/git"
PATH="$T/nofetch:$PATH" STUB_REPLY="$T/stop.txt" laf --on here > "$T/out" 2>&1; check "$?" "6" "origin's commit not here, its fetch failing: refused, the tip surely lacks it"
has "$T/out" "origin's $LB is at ${GNEW:0:7}, which this worktree lacks, and fetching it failed: fatal: fetch stand-in" "  saying so"
check "$(lhead)/$(calls)" "$GOLD/$N" "  the tree unmoved, no session"
catch_up

rm -rf "$REGATTA_CONFIG/wharf-runs"

echo "force-any: autofinish-run --priority, judged here, carried to dispatch --start (a queued finish's raise: test_finish_queue.sh)"
RS="${LOGS%/Logs/claude-weekly}/Caches/run-seed"   # under the suite's HOME, as LOGS is
FM="$RS/force"; mkdir -p "$FM"; rm -f "$FM/caller"
next_tip "force-any"
af --dry > "$T/out" 2>&1; check "$?" "0" "baseline: a dry run starts"
CLAUDE_UNATTENDED=dispatch af --dry --priority force > "$T/out" 2>&1; check "$?" "2" "--priority force from an unattended caller: refused"
has "$T/out" "an unattended caller never raises to it (CLAUDE_UNATTENDED)" "  saying why"
af --dry --priority force > "$T/out" 2>&1; check "$?" "2" "--priority force from a session without its force mark: refused"
has "$T/out" "use the force" "  with force-ok's words"
SKIPPER_SCOPE=x af --dry --priority high > "$T/out" 2>&1; check "$?" "2" "--priority high from a skipper with no high record of its own: refused"
: > "$FM/caller"
af --dry --priority force > "$T/out" 2>&1; check "$?" "0" "with the session's mark: the dry run starts"
has "$T/out" "--session-id" "  (the start command shown)"
check "$(grep -c -- "--priority force" "$T/out")" "1" "  --priority force on the dispatch --start line it would run"
check "$([ -f "$FM/caller" ] && echo kept || echo spent)" "kept" "  a dry run spends nothing"
af --dry --priority high > "$T/out" 2>&1; check "$?" "0" "--priority high from a session: no mark asked"
check "$(REGATTA_UNATTENDED=x CLAUDE_UNATTENDED=x python3 -c 'import sys, types
from importlib.machinery import SourceFileLoader
m = SourceFileLoader("afr", sys.argv[1]).load_module()
e = m.start_env(types.SimpleNamespace(runlog="/dev/null"))
print(" ".join(n for n in ("REGATTA_UNATTENDED", "CLAUDE_UNATTENDED") if n in e) or "none")' "$B/autofinish-run" 2>&1 | tail -1)" "none" \
  "start_env drops the unattended marker under both names (the detached --start judges no caller)"
check "$(env -u CLAUDE_UNATTENDED -u AUTOFINISH_CALLER_UNATTENDED REGATTA_UNATTENDED=x python3 -c 'import sys
from importlib.machinery import SourceFileLoader
m = SourceFileLoader("afr", sys.argv[1]).load_module()
print(m.unattended_caller(), "REGATTA_UNATTENDED" in m.SHIP_NOT_TICK)' "$B/autofinish-run" 2>&1 | tail -1)" "True True" \
  "the marker under its new name alone: an unattended caller, and no ship tick (force-any's fix round)"

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
"$B/dispatch" --start p "$W" n --priority low --dry-run > "$T/out" 2>&1; check "$?" "2" "--start --priority low: refused (a landing takes normal, high or force)"
"$B/dispatch" --start p "$W" n --session-id 00000000-0000-4000-8000-000000000001 --priority high --dry-run > "$T/out" 2>&1; check "$?" "0" "--start --priority high: a dry run (force-any)"
CLAUDE_UNATTENDED=dispatch "$B/dispatch" --start p "$W" n --priority force --dry-run > "$T/out" 2>&1; check "$?" "2" "--start --priority force, unattended: refused"
CLAUDECODE=1 CLAUDE_CODE_SESSION_ID=s-nomark "$B/dispatch" --start p "$W" n --priority force --dry-run > "$T/out" 2>&1; check "$?" "2" "--start --priority force from a session without its mark: refused"
has "$T/out" "use the force" "  with force-ok's words"

echo "the review stop's dispatch line preserves every shell argument"
cat > "$T/fix-command.py" <<'PY'
import shlex, sys
from importlib.machinery import SourceFileLoader
from types import SimpleNamespace
m = SourceFileLoader("afr", sys.argv[1]).load_module()
m.HERE = "/tmp/tool's directory"
t = SimpleNamespace(primary="/tmp/shop's project", branch="claude/test/fix;$value")
command = m.fix_round_line(t, {"priority": "force"}).split("dispatch): `", 1)[1].split("`.", 1)[0]
print(shlex.split(command) == [m.HERE + "/dispatch", t.branch, "--repo", t.primary, "--priority", "force"])
PY
check "$(python3 "$T/fix-command.py" "$B/autofinish-run")" "True" \
  "the PR comment quotes the tool and repo paths with spaces and apostrophes, and a branch with shell syntax"

[ "$fails" = 0 ] && echo "all ok" || { echo "$fails FAILED"; exit 1; }
