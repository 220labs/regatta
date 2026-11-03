#!/usr/bin/env bash
# tier_check's effort warning (xhigh-warning, 2026-11-01): the session's effort read from the tail of
# its transcript at every prompt, one line past the table's `high`, once per stretch at a value; the
# first-prompt report's settings pin flagged the same way; quiet under an unattended run, on a
# subagent's or a `<synthetic>` entry, and on a missing or unreadable transcript. The rest of the
# report's cases live in the overlay's hooks/test_hooks.sh. Scratch HOME and state; no network.
#   bash modules/plumb/tests/tier-check.sh
set -u
D="$(cd "$(dirname "$0")/.." && pwd -P)"
TK="$D/hooks/tier_check.py"
T="$(mktemp -d)"; T="$(cd "$T" && pwd -P)"
trap 'chmod -R u+rwx "$T" 2>/dev/null; rm -rf "$T"' EXIT
for v in $(env | sed -n 's/^\(REGATTA_UNATTENDED\)=.*/\1/p; s/^\(CLAUDE[A-Za-z0-9_]*\)=.*/\1/p'); do unset "$v"; done
export HOME="$T/u" REGATTA_CONFIG="$T/config" ACCOUNTS_FILE="$T/no-accounts.json"
export CLAUDE_TIER_SETTINGS="$T/settings.json" CLAUDE_TIER_CLAUDE_JSON="$T/claude.json" \
       CLAUDE_TIER_APP_HISTORY="$T/none.json" CLAUDE_TIER_SEEN="$T/seen" CLAUDE_TIER_NOW=1790000000
mkdir -p "$HOME" "$REGATTA_CONFIG"
echo '{"model":"opus","modelSettings":{"claude-opus-5-5":{"effortLevel":"high"}}}' > "$T/settings.json"
echo '{"oauthAccount":{"emailAddress":"a@b","organizationType":"claude_max"}}' > "$T/claude.json"
fails=0
check() {
  if [ "$1" = "$2" ]; then echo "  ok  $3"; else echo "  FAIL $3"; echo "       got:  $1"; echo "       want: $2"; fails=$((fails + 1)); fi
}
# entry <effort> [extra JSON fields] [model]: one assistant line as Claude Code writes it
entry() {
  printf '{"type":"assistant","sessionId":"s","effort":"%s"%s,"message":{"model":"%s","content":[]}}\n' \
    "$1" "${2:-}" "${3:-claude-opus-5-5}"
}
# hook <session> <transcript>: the hook's output for one prompt, then its exit code on the last line
hook() {
  printf '{"session_id":"%s","transcript_path":"%s","prompt":"x"}' "$1" "$2" | python3 "$TK" 2>"$T/err"
  echo "rc=$?"
}
# live <session> <transcript> <effort>: the same, with the hook input's `effort` for the turn, in Claude
# Code's shape (`{"level": …}`, its 2.1.316 hook schema; UserPromptSubmit does not carry it yet)
live() {
  printf '{"session_id":"%s","transcript_path":"%s","effort":{"level":"%s"},"prompt":"x"}' "$1" "$2" "$3" | python3 "$TK" 2>"$T/err"
  echo "rc=$?"
}
# rawin <session> <transcript> <effort JSON>: the hook input's `effort` as given, any shape
rawin() {
  printf '{"session_id":"%s","transcript_path":"%s","effort":%s,"prompt":"x"}' "$1" "$2" "$3" | python3 "$TK" 2>"$T/err"
  echo "rc=$?"
}
warns() { grep -c '^⚠️ Effort' || true; }

echo "the first prompt"
out=$(hook f1 "$T/none.jsonl")
check "$(echo "$out" | grep -c '^⚙️ Tier check')|$(echo "$out" | warns)|$(echo "$out" | tail -1)" "1|0|rc=0" \
  "the report once, no warning at high, no transcript yet: exit 0"
echo '{"effortLevel":"xhigh","modelSettings":{"claude-opus-5-5":{"effortLevel":"xhigh"},"claude-sonnet-5-5":{"effortLevel":"low"}}}' > "$T/settings.json"
out=$(hook f2 "$T/none.jsonl")
check "$(echo "$out" | warns)" "2" "a settings pin at xhigh: one line per pin, the global one and each model's"
check "$(echo "$out" | grep -c '^⚠️ Effort `xhigh` (settings pin): the tier table (.*) runs main sessions at `high`. Say so to the owner first thing in this reply and suggest `/effort high` — unless the owner asked for `xhigh` in this session.$')" "1" \
  "  …in the same words as the transcript's warning: the table, tell the owner, suggest /effort high"
check "$(echo "$out" | grep -c '^⚠️ Effort `xhigh` (settings pin for opus-5-5)')" "1" "  …a model's pin named by its model"
check "$(hook f2 "$T/none.jsonl")" "rc=0" "  …and said once: the next prompt is quiet"
TR="$T/f2b.jsonl"; entry xhigh > "$TR"
check "$(live f2b "$T/none.jsonl" xhigh | warns)|$(hook f2b "$TR" | warns)" "2|0" \
  "  …two pins and a turn at their value: two lines, not three, and its reply quiet"
echo '{"effortLevel":"max","modelSettings":{"claude-opus-5-5":{"effortLevel":"max"}}}' > "$T/settings.json"
TR="$T/f2c.jsonl"; entry max > "$TR"
check "$(hook f2c "$T/none.jsonl" | warns)|$(ls "$T/seen/f2c.effort" 2>/dev/null | wc -l | tr -d ' ')|$(hook f2c "$TR" | warns)" "0|0|1" \
  "a max pin is not flagged (Claude Code keeps none in settings) and marks nothing: a real reply at max warns"
echo '{"effortLevel":"xhigh","modelSettings":{"claude-opus-5-5":{"effortLevel":"xhigh"}}}' > "$T/settings.json"
check "$(CLAUDE_UNATTENDED=1 hook f3 "$T/none.jsonl" | warns)" "0" "  …and not under an unattended run (CLAUDE_UNATTENDED)"
check "$(REGATTA_UNATTENDED=1 hook f4 "$T/none.jsonl" | warns)" "0" "  …nor REGATTA_UNATTENDED"
echo '{"effortLevel":"xhigh"}' > "$T/settings.json"
TR="$T/f5.jsonl"; entry xhigh > "$TR"
check "$(hook f5 "$T/none.jsonl" | warns)|$(hook f5 "$TR" | warns)" "1|0" "a session at its pin hears it once: the pin at the first prompt, its reply at xhigh quiet"
check "$(live f6 "$T/none.jsonl" xhigh | warns)" "1" "  …and once when the turn's own effort is the pin's, in the same prompt"
echo '{"effortLevel":"xhigh","modelSettings":{"claude-opus-5-5":"not a mapping"}}' > "$T/settings.json"
out=$(hook f7 "$T/none.jsonl")
check "$(echo "$out" | warns)|$(echo "$out" | tail -1)|$(grep -c '^tier_check: report:' "$T/err")" "1|rc=0|1" \
  "a report that raises (a model's settings not a mapping): the pin line still goes out, the error to stderr"
echo '{"model":"opus","effortLevel":"high"}' > "$T/settings.json"

echo "the transcript's effort, every prompt"
TR="$T/s1.jsonl"; entry high > "$TR"
hook s1 "$TR" > /dev/null    # the first prompt: the report
check "$(hook s1 "$TR")" "rc=0" "high: quiet"
entry xhigh >> "$TR"
out=$(hook s1 "$TR")
check "$(echo "$out" | warns)|$(echo "$out" | grep -c 'Effort `xhigh` (this session.s last reply)')" "1|1" "xhigh in the tail: one line, naming what showed it"
check "$(hook s1 "$TR")" "rc=0" "  …a second prompt at xhigh is quiet"
entry high >> "$TR"
check "$(hook s1 "$TR")" "rc=0" "  …a drop to high is quiet"
entry xhigh >> "$TR"
check "$(hook s1 "$TR" | warns)" "1" "  …and a climb back to xhigh warns again"
entry max >> "$TR"
check "$(hook s1 "$TR" | warns)" "1" "  …as does a move to max, another value"
check "$(cat "$T/seen/s1.effort")" "max" "  …the mark beside the seen mark holds the last effort read"

TR="$T/s2.jsonl"; { entry high; entry xhigh '' '<synthetic>'; } > "$TR"
check "$(hook s2 "$TR" | warns)" "0" "a <synthetic> last entry is skipped (it is Claude Code's own)"
TR="$T/s3.jsonl"; { entry xhigh; entry high '' '<synthetic>'; } > "$TR"
check "$(hook s3 "$TR" | warns)" "1" "  …and the walk goes on past it to the real one"
TR="$T/s4.jsonl"; { entry high; entry xhigh ',"agentId":"a1"'; } > "$TR"
check "$(hook s4 "$TR" | warns)" "0" "a subagent's xhigh entry (agentId) is ignored"
TR="$T/s4b.jsonl"; { entry high; entry xhigh ',"agentId":"a1","isSidechain":true'; } > "$TR"
check "$(hook s4b "$TR" | warns)" "0" "  …with isSidechain beside it too"
TR="$T/s5.jsonl"; { entry high; entry xhigh ',"isSidechain":true'; } > "$TR"
check "$(hook s5 "$TR" | warns)" "0" "  …a sidechain one too"
TR="$T/s6.jsonl"; { entry xhigh; printf '{"type":"assistant","sessionId":"s","message":{"model":"m","content":[]}}\n'; printf '{"type":"user"}\n'; } > "$TR"
check "$(hook s6 "$TR" | warns)" "1" "an entry with no effort, and a user entry, are passed over"
TR="$T/s7.jsonl"; entry xhigh > "$TR"
check "$(CLAUDE_UNATTENDED=1 hook s7 "$TR" | warns)|$(REGATTA_UNATTENDED=1 hook s7 "$TR" | warns)" "0|0" "unattended: quiet, under either marker"
check "$(ls "$T/seen/s7.effort" 2>/dev/null | wc -l | tr -d ' ')" "0" "  …and no mark written, so an owner's prompt later still hears it"

echo "the turn's own effort, from the hook input"
TR="$T/l1.jsonl"; entry high > "$TR"
hook l1 "$TR" > /dev/null
out=$(live l1 "$TR" xhigh)
check "$(echo "$out" | warns)|$(echo "$out" | grep -c 'Effort `xhigh` (this turn)')" "1|1" "xhigh in the input, high in the transcript: the input wins, no prompt's lag"
check "$(live l1 "$TR" xhigh)" "rc=0" "  …a second prompt at xhigh is quiet"
TR="$T/l2.jsonl"; entry xhigh > "$TR"
hook l2 "$T/none.jsonl" > /dev/null
check "$(live l2 "$TR" high)" "rc=0" "high in the input, xhigh in the transcript: quiet (the owner lowered it)"
check "$(CLAUDE_UNATTENDED=1 live l3 "$TR" max | warns)" "0" "  …and unattended, quiet whatever the input says"

TR="$T/l4.jsonl"; entry xhigh > "$TR"
hook l4 "$T/none.jsonl" > /dev/null
check "$(rawin l4 "$TR" '{"level":"auto"}' | warns)" "1" "an input effort that is no effort word: the transcript decides"
check "$(cat "$T/seen/l4.effort")" "xhigh" "  …and the mark holds the effort, not the input's junk"
TR="$T/l5.jsonl"; entry high > "$TR"
hook l5 "$T/none.jsonl" > /dev/null
check "$(rawin l5 "$TR" '"max"' | warns)" "1" "  …a bare word is read as well"
echo '{"effortLevel":"xhigh","modelSettings":["not","a","mapping"]}' > "$T/settings.json"
out=$(hook l6 "$T/none.jsonl")
check "$(echo "$out" | warns)|$(grep -c '^tier_check: pins:' "$T/err")|$(echo "$out" | tail -1)" "1|0|rc=0" \
  "model settings that are a list: the global pin still flagged (the report raises, as f7), exit 0"
echo '{"model":"opus","effortLevel":"high"}' > "$T/settings.json"

echo "a bounded read"
TR="$T/big1.jsonl"; { entry xhigh; python3 -c 'pad = "x" * 1000
for _ in range(300): print("{\"type\":\"user\",\"pad\":\"%s\"}" % pad)'; } > "$TR"
check "$(hook b1 "$TR" | warns)" "0" "the only effort entry, more than 256 KB back, is not read"
TR="$T/big2.jsonl"; { python3 -c 'print("{\"type\":\"assistant\",\"effort\":\"high\",\"pad\":\"%s\"}" % ("y" * 400000))'; entry xhigh; } > "$TR"
check "$(hook b2 "$TR" | warns)" "1" "  …and a tail that starts mid-entry still finds the newest one"
TR="$T/big3.jsonl"; python3 -c 'print("{\"type\":\"assistant\",\"effort\":\"xhigh\",\"pad\":\"%s\"}" % ("z" * 400000))' > "$TR"
check "$(hook b3 "$TR" | warns)" "0" "  …an entry cut by the bound is not guessed at"
TR="$T/big4.jsonl"; python3 - "$TR" <<'PY2'
import sys
e = b'{"type":"assistant","sessionId":"s","effort":"xhigh","message":{"model":"m","content":[]}}\n'
pad = lambda n: b'{"type":"user","pad":"' + b"p" * (n - 25) + b'"}\n'
tail = e + pad(256 * 1024 - len(e))
assert len(tail) == 256 * 1024
open(sys.argv[1], "wb").write(pad(5000) + tail)
PY2
check "$(hook b4 "$TR" | warns)" "1" "  …and a tail that starts on a whole line keeps it"

echo "never blocks a turn"
check "$(hook m1 "$T/missing.jsonl" | tail -1)|$(hook m1 "$T/missing.jsonl")" "rc=0|rc=0" "a missing transcript: quiet, exit 0"
mkdir -p "$T/adir"
hook m2 "$T/adir" > /dev/null
check "$(hook m2 "$T/adir")" "rc=0" "a transcript path that is a folder: quiet, exit 0"
TR="$T/locked.jsonl"; entry xhigh > "$TR"; chmod 000 "$TR"
if [ -r "$TR" ]; then echo "  skip an unreadable transcript (this user reads every file)"
else hook m3 "$TR" > /dev/null; check "$(hook m3 "$TR")" "rc=0" "an unreadable transcript: quiet, exit 0"; fi
chmod 600 "$TR"
printf 'not json\n{"type":"assistant", broken\n' > "$T/junk.jsonl"
hook m4 "$T/junk.jsonl" > /dev/null
check "$(hook m4 "$T/junk.jsonl")" "rc=0" "lines that do not parse: quiet, exit 0"
check "$(printf '{"session_id":"m5"}' | python3 "$TK" > /dev/null; printf '{"session_id":"m5"}' | python3 "$TK"; echo "rc=$?")" "rc=0" \
  "no transcript_path in the input: quiet, exit 0"
hook w1 "$T/none.jsonl" > /dev/null
chmod 500 "$T/seen"
if [ -w "$T/seen" ]; then echo "  skip a seen folder it cannot write (this user writes every folder)"
else
  out=$(hook w1 "$T/s7.jsonl")
  check "$(echo "$out" | warns)|$(echo "$out" | tail -1)|$(grep -c '^tier_check: effort mark:' "$T/err")" "1|rc=0|1" \
    "an effort mark it cannot write: the warning still goes out, exit 0, the error to stderr"
  out=$(hook w2 "$T/s7.jsonl")
  check "$(echo "$out" | grep -c '^⚙️ Tier check')|$(echo "$out" | warns)|$(echo "$out" | tail -1)|$(grep -c '^tier_check: seen mark:' "$T/err")" "0|1|rc=0|1" \
    "a seen mark it cannot write (a new session): no report, the warning still out, exit 0, the error to stderr"
fi
chmod 700 "$T/seen"

[ "$fails" -eq 0 ] && echo "tier-check: all passed" || { echo "tier-check: $fails failed"; exit 1; }
