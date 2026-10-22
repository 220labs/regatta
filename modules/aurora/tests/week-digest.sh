#!/usr/bin/env bash
# week-digest's suite: the fence (knowledge-layers S4) over synthetic transcripts and docs under a
# scratch HOME and config dir, one made-up confidential scope (`node`: repo `sec`) and one open
# (`pub`: repo `open`). Without --scope a confidential session is counted, never quoted, and
# --promote-tags never reads its folder; --scope reads that scope alone; a torn registry quotes
# nothing. No network, no real repo touched.
#   bash modules/aurora/tests/week-digest.sh
set -u
D="$(cd "$(dirname "$0")/.." && pwd -P)"
W="$D/bin/week-digest"
T="$(mktemp -d)"; T="$(cd "$T" && pwd -P)"
trap 'rm -rf "$T"' EXIT
for v in $(env | sed -n 's/^\(REGATTA[A-Za-z0-9_]*\)=.*/\1/p; s/^\(CLAUDE[A-Za-z0-9_]*\)=.*/\1/p'); do unset "$v"; done
export HOME="$T/u" REGATTA_CONFIG="$T/config" ACCOUNTS_FILE="$T/no-accounts.json" CLAUDE_REPOS_JSON="$T/repos.json"
fails=0
check() {
  if [ "$1" = "$2" ]; then echo "  ok  $3"; else echo "  FAIL $3"; echo "       got:  $1"; echo "       want: $2"; fails=$((fails + 1)); fi
}
P="$T/u/projects"; L="$T/u/.claude/projects"
mkdir -p "$REGATTA_CONFIG" "$P/sec/docs" "$P/open/docs" "$P/transcripts/sec" "$P/transcripts/open"
printf '{"repos": {"sec": {}, "open": {}},\n "scopes": {"node": {"file": "n", "repos": ["sec"], "confidential": true},\n  "pub": {"file": "p", "repos": ["open"]}}}\n' > "$CLAUDE_REPOS_JSON"
slug() { printf '%s' "$1" | sed 's/[^A-Za-z0-9]/-/g'; }
NOW=$(python3 -c 'import datetime as d; print(d.datetime.now(d.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z"))')
session() {   # session <file> <id> <prompt>
  mkdir -p "$(dirname "$1")"
  printf '{"type": "user", "origin": {"kind": "human"}, "sessionId": "%s", "timestamp": "%s", "message": {"content": "%s"}}\n' "$2" "$NOW" "$3" > "$1"
}
session "$L/$(slug "$P/sec")/a.jsonl" sec-live-1 "PLUMWORD in the live folder"
session "$L/$(slug "$P/sec")--claude-worktrees-gone/b.jsonl" sec-tree-2 "PLUMWORD from a removed worktree"
session "$P/transcripts/sec/c.jsonl" sec-arch-3 "PLUMWORD in the archive"
session "$L/$(slug "$P/open")/d.jsonl" open-live-4 "open words here"
session "$P/transcripts/open/e.jsonl" open-arch-5 "open words archived"
printf 'x\n<!-- promote: coding --> PLUMWORD tag\n' > "$P/sec/docs/a.md"
printf '<!-- promote: coding --> open tag\n' > "$P/open/docs/b.md"
printf '<!-- promote: coding --> not markdown\n' > "$P/open/docs/c.txt"

echo "no --scope: a confidential scope's sessions counted, never quoted"
out=$("$W" --days 7); check $? 0 "exit 0"
check "$(echo "$out" | grep -c PLUMWORD)" 0 "  no line of the confidential scope's"
check "$(echo "$out" | grep -c 'open words')" 2 "  the open scope's prompts, live and archived"
check "$(echo "$out" | head -1 | grep -o '5 sessions, 5 prompts')" "5 sessions, 5 prompts" "  the heading counts all five"
check "$(echo "$out" | grep -o '^_3 sessions (3 prompts) of a confidential scope')" "_3 sessions (3 prompts) of a confidential scope" \
  "  one line says three were counted, not quoted (live, a removed worktree's, the archive)"

echo "--scope"
out=$("$W" --days 7 --scope node)
check "$(echo "$out" | grep -c PLUMWORD) $(echo "$out" | grep -c 'open words')" "3 0" "the confidential scope's own pass reads it, and nothing else"
check "$(echo "$out" | head -1 | grep -o '3 sessions, 3 prompts.*scope node')" "3 sessions, 3 prompts ($(date +%F)) — scope node" "  the heading names the scope"
out=$("$W" --days 7 --scope pub)
check "$(echo "$out" | grep -c PLUMWORD) $(echo "$out" | grep -c 'open words') $(echo "$out" | grep -c 'confidential')" "0 2 0" \
  "an open scope: its own, the confidential one not even counted"
"$W" --scope nope > /dev/null 2> "$T/err"; check "$? $(cat "$T/err")" "2 week-digest: no scope 'nope' in the registry" "an unknown scope: exit 2, one line"

echo "--promote-tags"
out=$("$W" --promote-tags)
check "$out" "$P/open/docs/b.md:1:<!-- promote: coding --> open tag
(2 folder(s) of a confidential scope not read — its own pass reads them)" "grep -rn's lines, the confidential checkout and archive never read"
check "$("$W" --promote-tags --scope pub)" "$P/open/docs/b.md:1:<!-- promote: coding --> open tag" "  --scope pub: the confidential folders not even counted"
"$W" --promote-tags --scope > /dev/null 2> "$T/err"; check "$? $(cat "$T/err")" "2 week-digest: --scope needs a scope's name" "  --scope with no name: exit 2, one line"
check "$("$W" --promote-tags --scope node)" "$P/sec/docs/a.md:2:<!-- promote: coding --> PLUMWORD tag" "  --scope: that scope's tags alone"

echo "a torn registry: nothing quoted"
head -c 30 "$T/repos.json" > "$T/torn.json"
out=$(CLAUDE_REPOS_JSON="$T/torn.json" "$W" --days 7)
check "$(echo "$out" | grep -c 'PLUMWORD\|open words') $(echo "$out" | grep -o '^_5 sessions')" "0 _5 sessions" "every session counted, none quoted (fails closed)"
CLAUDE_REPOS_JSON="$T/torn.json" "$W" --scope pub > /dev/null 2>&1; check $? 2 "  and a scope asked of it refused"
check "$(CLAUDE_REPOS_JSON="$T/none.json" "$W" --days 7 | grep -c 'PLUMWORD')" 3 "no registry at all: no scope is confidential, all quoted (as before S4)"

[ "$fails" -eq 0 ] && echo "week-digest: all ok" || { echo "week-digest: $fails failed"; exit 1; }
