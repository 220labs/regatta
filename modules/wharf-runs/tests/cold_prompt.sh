#!/usr/bin/env bash
# cold_prompt: every typed /finish in a claude/* worktree goes to a fresh run (autofinish E7; costs S7,
# docs/host-power-costs-2026-10-24.md). Cold or Fable: the hook starts the runner and blocks; warm: the
# prompt passes with a context line asking for the commit summary, then the runner. Moved from the
# overlay's hooks/test_hooks.sh with S7 (2026-10-24). Scratch paths only; the runner is a stand-in.
#   bash modules/wharf-runs/tests/cold_prompt.sh
set -u
M="$(cd "$(dirname "$0")/.." && pwd)"
H="$M/hooks"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fails=0
check() { if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3: expected [$2] got [$1]"; fails=$((fails+1)); fi; }
has()   { case "$1" in *"$2"*) echo "  ok   $3";; *) echo "  FAIL $3: [$2] not in [${1:0:400}]"; fails=$((fails+1));; esac; }

echo "cold_prompt: a typed /finish goes to the launcher"
CP="$T/cold"; mkdir -p "$CP/state"
git init -q -b main "$CP/repo" && git -C "$CP/repo" commit -q --allow-empty -m init
git -C "$CP/repo" checkout -q -b claude/acct-host/2026-10-05-cold
TOP="$(cd "$CP/repo" && pwd -P)"
CPNOW=1791200000
# a transcript whose last main-chain call is <age> s old on <model> with <ctx> tokens of context
# (a subagent's later call is not it); the file is written by a plain heredoc, never inside "$(…)"
cat > "$T/tr.py" <<'EOF'
import datetime, json, sys
p, now, ago, model, ctx = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4], int(sys.argv[5])
iso = lambda t: datetime.datetime.fromtimestamp(t, datetime.timezone.utc).isoformat().replace("+00:00", "Z")
u = {"input_tokens": 2000, "cache_read_input_tokens": ctx - 12000, "cache_creation_input_tokens": 10000}
with open(p, "w") as f:
    f.write(json.dumps({"type": "user", "timestamp": iso(now - ago - 60), "message": {"content": "hi"}}) + "\n")
    f.write(json.dumps({"type": "assistant", "timestamp": iso(now - ago), "message": {"model": model, "usage": u}}) + "\n")
    f.write(json.dumps({"type": "assistant", "isSidechain": True, "timestamp": iso(now - 5), "message": {"model": "claude-haiku", "usage": u}}) + "\n")
print(p)
EOF
cptr() { python3 "$T/tr.py" "$CP/t-$1-$2-$3.jsonl" "$CPNOW" "$1" "$2" "$3"; }
printf '#!/bin/sh\necho "$@" >> "%s"\necho "started: /finish b --unattended — window and Remote Control \\"finish · cold · host\\", session x; state s; log l"\n' "$CP/calls" > "$CP/runner"
printf '#!/bin/sh\necho "autofinish-run: not starting — no retry on the same tip" >&2\nexit 3\n' > "$CP/refuser"
printf '#!/bin/sh\necho "$@" >> "%s"\nexec sleep 5\n' "$CP/calls" > "$CP/hanger"
chmod +x "$CP/runner" "$CP/refuser" "$CP/hanger"
CPSID=0badc0de-0000-4000-8000-000000000000
cpr() { # prompt transcript [runner] — the hook's stdout
  python3 -c 'import json,sys; print(json.dumps({"prompt": sys.argv[1], "cwd": sys.argv[2], "transcript_path": sys.argv[3], "session_id": sys.argv[4]}))' "$1" "$CP/repo" "$2" "$CPSID" \
    | env -u CLAUDE_HOOK_NO_AUTOFINISH -u CLAUDE_UNATTENDED -u CLAUDE_CODE_DISABLE_BACKGROUND_TASKS COLD_PROMPT_NOW=$CPNOW \
      AUTOFINISH_STATE_DIR="$CP/state" CLAUDE_AUTOFINISH_RUN="${3:-$CP/runner}" python3 "$H/cold_prompt.py"; }
field() { python3 -c 'import json,sys; d=json.load(sys.stdin); print(eval(sys.argv[1]))' "$1" 2>&1; }
COLD=$(cptr 7200 claude-opus-5-5 312000); FAB=$(cptr 600 claude-fable-5-1 312000)
SMALL=$(cptr 600 claude-opus-5-5 40000); LARGE=$(cptr 600 claude-opus-5-5 612000); SON=$(cptr 600 claude-sonnet-5-5 90000)

check "$(cpr /finish "$COLD")" "" "disarmed: a cold /finish passes, nothing started"
echo '{"by":"t","ts":0}' > "$CP/state/armed"

echo "warm: the prompt passes with the summary-first context, and no runner from the hook"
out=$(cpr /finish "$SMALL")
check "$(echo "$out" | field 'd.get("decision")')" "None" "warm small (40k, Opus): not blocked"
ctx=$(echo "$out" | field 'd["hookSpecificOutput"]["additionalContext"]')
check "$(echo "$out" | field 'd["hookSpecificOutput"]["hookEventName"]')" "UserPromptSubmit" "  a UserPromptSubmit context line"
has "$ctx" "re-read this 40k context on Opus" "  names the context and the model"
has "$ctx" "Do not follow the finish skill's phases in this turn" "  holds the skill back"
has "$ctx" "1. Write the branch's commit summary to commit-summary.md" "  the summary first"
has "$ctx" "git -C $TOP add -A && git -C $TOP commit -q --allow-empty -F <that file>" "  committed in this worktree, empty allowed"
has "$ctx" "2. Hand the branch over: \`$CP/runner $TOP --rule C --by typed --session $CPSID\`" "  then the runner, by typed, with this session's id"
has "$ctx" "If step 2 is denied or exits non-zero" "  a refusal or a denial leaves the /finish here"
has "$ctx" "/finish --here" "  and --here named"
check "$([ -e "$CP/calls" ] && echo called || echo none)" "none" "  the hook started no runner: the session runs it after its summary"
out=$(cpr /finish "$LARGE")
check "$(echo "$out" | field 'd.get("decision")')" "None" "warm large (612k, Opus): not blocked either"
has "$(echo "$out" | field 'd["hookSpecificOutput"]["additionalContext"]')" "re-read this 612k context on Opus" "  the same road, its size named"
has "$(cpr /finish "$SON" | field 'd["hookSpecificOutput"]["additionalContext"]')" "re-read this 90k context on Sonnet" "warm Sonnet: the same road"
out=$(cpr '/finish claude/acct-host/2026-10-05-cold' "$SMALL")
has "$out" '"additionalContext"' "warm, /finish <this branch>: the same road"
check "$([ -e "$CP/calls" ] && echo called || echo none)" "none" "  still no runner from the hook"
out=$(python3 -c 'import json,sys; print(json.dumps({"prompt": "/finish", "cwd": sys.argv[1], "transcript_path": sys.argv[2]}))' "$CP/repo" "$SMALL" \
  | env -u CLAUDE_HOOK_NO_AUTOFINISH -u CLAUDE_UNATTENDED COLD_PROMPT_NOW=$CPNOW AUTOFINISH_STATE_DIR="$CP/state" \
    CLAUDE_AUTOFINISH_RUN="$CP/runner" python3 "$H/cold_prompt.py")
ctx=$(echo "$out" | field 'd["hookSpecificOutput"]["additionalContext"]')
has "$ctx" "--rule C --by typed\`" "no session id in the input: the command carries no --session"

echo "cold or Fable: the hook starts the runner and blocks"
out=$(cpr "/finish" "$COLD")
check "$(echo "$out" | field 'd["decision"]')" "block" "armed, cold 2 h: blocked"
why=$(echo "$out" | field 'd["reason"]')
has "$why" 'cold 312k (2 h) — /finish runs by itself in the window "finish · cold · host"' "  the reason names the context, the age and the window"
has "$why" '/finish --here runs it in this tab at the full re-write (~$2.50 (' "  and the way to run it here, priced (312k at Opus's 1-hour write)"
check "$(cat "$CP/calls")" "$TOP --rule C --by typed --session $CPSID" \
  "  the runner started on the worktree, by typed, with this session's id (its own lock is no refusal)"
: > "$CP/calls"
out=$(cpr /finish "$FAB")
check "$(echo "$out" | field 'd["decision"]')" "block" "warm Fable: blocked, the runner started at once"
has "$(echo "$out" | field 'd["reason"]')" "on Fable, 312k" "  the reason says Fable"
check "$(wc -l < "$CP/calls" | tr -d ' ')" "1" "  one runner call"
: > "$CP/calls"
check "$(cpr '/finish claude/acct-host/2026-10-05-cold' "$COLD" | grep -c '"block"')" "1" "cold, /finish <this branch>: the runner's own words, blocked too"
: > "$CP/calls"
# Claude Code's own <synthetic> entry after the last call (an API error): no call, read past it (AGENTS.md trap)
SYN="$CP/t-syn.jsonl"; cp "$FAB" "$SYN"
printf '{"type":"assistant","timestamp":"%s","message":{"model":"<synthetic>","usage":{"input_tokens":0,"output_tokens":0}}}\n' \
  "$(python3 -c "import datetime;print(datetime.datetime.fromtimestamp($CPNOW-30,datetime.timezone.utc).isoformat().replace('+00:00','Z'))")" >> "$SYN"
out=$(cpr /finish "$SYN")
check "$(echo "$out" | field 'd["decision"]')" "block" "Fable with a <synthetic> entry after its call: still Fable, blocked"
has "$(echo "$out" | field 'd["reason"]')" "on Fable, 312k" "  its context the real call's, not 0k"
: > "$CP/calls"

echo "what passes untouched"
check "$(cpr '/finish --here' "$COLD")" "" "/finish --here passes, cold"
check "$(cpr '/finish --here' "$SMALL")" "" "/finish --here passes, warm"
check "$(cpr '/finish --here' "$FAB")" "" "/finish --here passes, Fable"
check "$(cpr '/finish --local' "$COLD")" "" "/finish --local passes: the runner would drop it (review, 2026-10-05)"
check "$(cpr '/finish --local' "$SMALL")" "" "  warm too"
check "$(cpr '/finish claude/acct-host/2026-10-05-other' "$COLD")" "" "/finish <another branch> passes"
check "$(cpr '/finish claude/x --unattended' "$SMALL")" "" "the runner's own /finish --unattended passes"
check "$(cpr 'please /finish later' "$SMALL")" "" "a prompt that is not /finish passes"
check "$(wc -c < "$CP/calls" | tr -d ' ')" "0" "  none of them started a runner"
check "$(cpr /finish "$COLD" "$CP/refuser")" "" "the runner refuses (that tip tried, a lock in use): the typed /finish runs here"
out=$(COLD_PROMPT_TIMEOUT=1 cpr /finish "$COLD" "$CP/hanger")
check "$(echo "$out" | field 'd["decision"]')" "block" \
  "a runner that does not answer in time: blocked, never a second /finish beside one that may be starting"
has "$(echo "$out" | field 'd["reason"]')" "may be starting" "  the reason says it may be starting"
check "$(cpr /finish "$CP/no-such.jsonl")" "" "no transcript: passes"
: > "$CP/calls"
check "$(python3 -c 'import json,sys; print(json.dumps({"prompt": "/finish", "cwd": sys.argv[1], "transcript_path": sys.argv[2]}))' "$CP/repo" "$SMALL" \
  | env -u CLAUDE_HOOK_NO_AUTOFINISH CLAUDE_UNATTENDED=dispatch COLD_PROMPT_NOW=$CPNOW AUTOFINISH_STATE_DIR="$CP/state" \
    CLAUDE_AUTOFINISH_RUN="$CP/runner" python3 "$H/cold_prompt.py")" "" "an unattended session, armed and warm: passes (the CLAUDE_UNATTENDED guard alone)"
check "$(python3 -c 'import json,sys; print(json.dumps({"prompt": "/finish", "cwd": sys.argv[1], "transcript_path": sys.argv[2]}))' "$CP/repo" "$COLD" \
  | env -u CLAUDE_UNATTENDED CLAUDE_HOOK_NO_AUTOFINISH=1 COLD_PROMPT_NOW=$CPNOW AUTOFINISH_STATE_DIR="$CP/state" \
    CLAUDE_AUTOFINISH_RUN="$CP/runner" python3 "$H/cold_prompt.py")" "" "CLAUDE_HOOK_NO_AUTOFINISH: passes"
check "$(wc -c < "$CP/calls" | tr -d ' ')" "0" "  and no runner"
# a fresh run already stopped on this tip: the warm road would move the tip with its summary commit
GD="$(git -C "$CP/repo" rev-parse --absolute-git-dir)"; mkdir -p "$GD/claude"
printf '{"tip": "%s"}' "$(git -C "$CP/repo" rev-parse HEAD)" > "$GD/claude/autofinish.json"
check "$(cpr /finish "$SMALL")" "" "warm, the last run stopped on this tip: passes untouched, /finish runs here"
printf '{"tip": "0000000000000000000000000000000000000000"}' > "$GD/claude/autofinish.json"
has "$(cpr /finish "$SMALL")" '"additionalContext"' "  a run on an older tip: the warm road as before"
rm -f "$GD/claude/autofinish.json"
check "$(cpr /finish "$(cptr 600 claude-haiku-4-5 40000)" | field 'd["hookSpecificOutput"]["additionalContext"]' | grep -c 'context on claude-haiku-4-5')" "1" \
  "a model the price table does not know is named as written, never as Opus"
git -C "$CP/repo" checkout -q main
check "$(cpr /finish "$SMALL")" "" "not a claude/* branch: passes, warm"
check "$(cpr /finish "$COLD")" "" "  and cold"
check "$(echo 'not json' | python3 "$H/cold_prompt.py"; echo "rc=$?")" "rc=0" "bad input: silent, exit 0"

echo; [ $fails -eq 0 ] && echo "all passed" || { echo "$fails FAILED"; exit 1; }
