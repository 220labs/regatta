#!/usr/bin/env bash
# The core's attribution: common.attribution(session, cwd) and `regatta attribution add|list`.
# A session row beats a path row, the newest ts wins among rows of one kind, a path glob matches a
# folder and every folder under it (a worktree's part kept), a bad line is skipped with one warning,
# the file moves or turns off by the config key, and the verb appends without rewriting.
# Scratch HOME and config dir; every name made up (proj-a, proj-b, proj-c, sess-1 …).
#   bash modules/regatta/tests/attribution.sh
set -u
M="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
for v in $(env | sed -n 's/^\(REGATTA[A-Za-z0-9_]*\)=.*/\1/p; s/^\(CLAUDE[A-Za-z0-9_]*\)=.*/\1/p'); do unset "$v"; done
export HOME="$T/home" REGATTA_CONFIG="$T/config"
P="$HOME/projects"
mkdir -p "$P/proj-a/.git" "$P/proj-b/.git" "$P/proj-c/.git" "$P/not-a-repo" "$REGATTA_CONFIG"
AF="$HOME/.local/state/regatta/attribution.jsonl"
VERB="$M/libexec/attribution"

fails=0
check() { if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3: expected [$2] got [$1]"; fails=$((fails+1)); fi; }
# attr SESSION CWD [ROOT]: the reader's answer, in a fresh process (it caches per process)
attr() { python3 -I -c "
import sys; sys.path.insert(0, '$M/hooks'); import common
print(common.attribution(sys.argv[1] or None, sys.argv[2] or None, sys.argv[3] or None))" "$1" "$2" "${3:-}" 2>&1; }
rows() { mkdir -p "$(dirname "$AF")"; printf '%s\n' "$@" > "$AF"; }
W1="$P/proj-a/.claude/worktrees/topic-1"

echo "attribution: the reader"
rm -f "$AF"
check "$(attr sess-1 "$P/proj-a")" None "no file: no attribution"

rows '{"ts": "2026-03-03T09:00:00Z", "project": "proj-b", "session": "sess-1", "why": "t"}'
check "$(attr sess-1 "$P/proj-a")" proj-b "a session row attributes that session"
check "$(attr sess-2 "$P/proj-a")" None "  and no other"
check "$(attr sess-1 "")" proj-b "  whatever the folder, none given included"

rows '{"ts": "2026-03-03T09:00:00Z", "project": "proj-b", "path": "proj-a/.claude/worktrees/topic-1"}'
check "$(attr sess-9 "$W1")" proj-b "a path row matches the worktree's folder"
check "$(attr sess-9 "$W1/sub/deeper")" proj-b "  and any folder under it"
check "$(attr sess-9 "$P/proj-a/.claude/worktrees/topic-10")" None "  not a sibling whose name starts the same"
check "$(attr sess-9 "$P/proj-a")" None "  nor the parent repo"
check "$(attr "" "$W1")" proj-b "  with no session at all"
rows '{"ts": "2026-03-03T09:00:00Z", "project": "proj-b", "path": "proj-a/.claude/worktrees/topic-*"}'
check "$(attr sess-9 "$P/proj-a/.claude/worktrees/topic-10")" proj-b "a glob takes topic-1 and topic-10"
rows '{"ts": "2026-03-03T09:00:00Z", "project": "proj-b", "path": "proj-a"}'
check "$(attr sess-9 "$W1")" proj-b "a repo's folder takes every session under it, worktrees included"
check "$(attr sess-9 "$T/elsewhere/proj-a")" None "a folder outside the projects folder matches nothing"
check "$(attr sess-9 "$T/otherhome/projects/proj-a/sub")" proj-b "another home's prefix is read as this one's"
check "$(attr sess-9 "$P/proj-a/sub" "$T/alt")" None "a caller's root replaces the projects folder (this one is then no root)"
check "$(attr sess-9 "$T/alt/proj-a/sub" "$T/alt")" proj-b "  and a folder under it matches"

echo "attribution: precedence"
rows '{"ts": "2026-03-04T09:00:00Z", "project": "proj-b", "path": "proj-a/.claude/worktrees/topic-1"}' \
     '{"ts": "2026-03-02T09:00:00Z", "project": "proj-c", "session": "sess-2"}'
check "$(attr sess-2 "$W1")" proj-c "a session row beats a path row, newer or not"
check "$(attr sess-3 "$W1")" proj-b "  another session falls to the path row"
rows '{"ts": "2026-03-04T09:00:00Z", "project": "proj-c", "session": "sess-1"}' \
     '{"ts": "2026-03-02T09:00:00Z", "project": "proj-b", "session": "sess-1"}'
check "$(attr sess-1 "")" proj-c "the newest session row wins, whatever the file order"
rows '{"ts": "2026-03-04T09:00:00Z", "project": "proj-c", "path": "proj-a/.claude/worktrees/topic-1"}' \
     '{"ts": "2026-03-05T09:00:00Z", "project": "proj-b", "path": "proj-a/.claude/worktrees/topic-1/sub"}'
check "$(attr sess-9 "$W1/sub")" proj-b "the newest path row wins where two match"
check "$(attr sess-9 "$W1")" proj-c "  and the older one stands where the newer does not"
rows '{"project": "proj-b", "session": "sess-1"}' '{"ts": "not a time", "project": "proj-c", "session": "sess-1"}' \
     '{"ts": "2026-03-04T09:00:00Z", "project": "proj-a", "session": "sess-1"}'
check "$(attr sess-1 "")" proj-a "a row without a readable ts is the oldest; a later line breaks a tie"

echo "attribution: bad lines, the key"
rows 'not json' \
     '{"ts": "2026-03-03T09:00:00Z", "project": "proj-b"}' \
     '{"ts": "2026-03-03T09:00:00Z", "project": "proj-b", "session": "sess-1", "path": "proj-a"}' \
     '[1, 2]' \
     '{"ts": "2026-03-03T09:00:00Z", "project": "proj-b", "session": "sess-1"}'
out=$(python3 -I -c "
import sys; sys.path.insert(0, '$M/hooks'); import common
for _ in range(3): print(common.attribution('sess-1', None))" 2>&1)
check "$(printf '%s\n' "$out" | grep -c 'is not an attribution row: skipped')" 4 "one warning per bad line (4), read once per process"
check "$(printf '%s\n' "$out" | grep -c '^proj-b$')" 3 "  the good row still applies"
check "$(printf '%s\n' "$out" | grep -c 'attribution.jsonl line 3 is not')" 1 "  the warning names the line"

mkdir -p "$REGATTA_CONFIG/regatta"
printf '%s\n' "$T/moved.jsonl" > "$REGATTA_CONFIG/regatta/attribution"
printf '%s\n' '{"ts": "2026-03-03T09:00:00Z", "project": "proj-c", "session": "sess-1"}' > "$T/moved.jsonl"
check "$(attr sess-1 "")" proj-c "regatta/attribution moves the file"
: > "$REGATTA_CONFIG/regatta/attribution"
check "$(attr sess-1 "")" None "  written empty it turns attribution off"
printf '%s\n' "relative/file.jsonl" > "$REGATTA_CONFIG/regatta/attribution"
out=$(python3 -I -c "
import sys; sys.path.insert(0, '$M/hooks'); import common
print(common.config_problems(), common.attribution('sess-1', None))" 2>&1)
check "$(printf '%s\n' "$out" | tail -1)" "[] None" "  a relative path: the core still imports, no config problem, attribution off"
check "$(printf '%s\n' "$out" | grep -c 'regatta/attribution is not an absolute path: relative/file.jsonl: attribution off')" 1 "  and says so once on stderr"
printf '%s\n' "$T/elsewhere/log" > "$REGATTA_CONFIG/regatta/log-dir"
printf '%s\n' '{"ts": "2026-03-03T09:00:00Z", "project": "proj-c", "session": "sess-1"}' > "$AF"
rm -f "$REGATTA_CONFIG/regatta/attribution"
check "$(attr sess-1 "")" proj-c "  the default file ignores regatta/log-dir"
rm -f "$REGATTA_CONFIG/regatta/log-dir" "$AF"
rm -f "$REGATTA_CONFIG/regatta/attribution"

echo "attribution: the verb"
rm -f "$AF"
verb() { python3 "$VERB" "$@" 2>&1; }
out=$(verb add proj-nope --session sess-1); code=$?
check "$code" 2 "add: a missing project is refused (exit 2)"
case "$out" in *"'proj-nope' is not a repo under"*) check ok ok "  and says so" ;; *) check "$out" "the refusal" "  and says so" ;; esac
verb add not-a-repo --session sess-1 >/dev/null; check "$?" 2 "add: a folder without .git is refused (exit 2)"
verb add ../elsewhere --session sess-1 >/dev/null; check "$?" 2 "add: a project outside the root is refused (exit 2)"
verb add proj-b >/dev/null; check "$?" 2 "add: no session and none in the environment is refused (exit 2)"
verb add proj-b --session sess-1 --path proj-a >/dev/null; check "$?" 2 "add: --session with --path is refused (exit 2)"
verb add proj-b --path '/' >/dev/null; check "$?" 2 "add: an empty --path is refused (exit 2)"
verb add proj-b --path /tmp/nowhere >/dev/null; check "$?" 2 "add: an absolute --path outside the root is refused (exit 2)"
verb add proj-b --path "$P" >/dev/null; check "$?" 2 "  the root itself is an empty --path (exit 2)"
check "$([ -e "$AF" ] && echo written || echo none)" none "  no refusal wrote the file"
CLAUDE_CODE_SESSION_ID=sess-1 verb add proj-b --why "from the environment" >/dev/null; check "$?" 0 "add: the session defaults to CLAUDE_CODE_SESSION_ID"
check "$(grep -c '"session": "sess-1"' "$AF")" 1 "  and the row names it"
verb add proj-c --path "$W1/" --why "a worktree" >/dev/null; check "$?" 0 "add: --path takes an absolute path under the root"
check "$(grep -c '"path": "proj-a/.claude/worktrees/topic-1"' "$AF")" 1 "  and stores it relative"
check "$(wc -l < "$AF" | tr -d ' ')" 2 "two rows, one per accepted call"
check "$(attr sess-1 "")" proj-b "the reader sees the row the verb wrote"
printf '%s' '{"ts": "2026-03-01T00:00:00Z", "project": "proj-b", "session": "sess-3"}' >> "$AF"   # no newline at the end
before=$(head -n 2 "$AF")
verb add proj-b --session sess-2 >/dev/null
check "$(wc -l < "$AF" | tr -d ' ')" 4 "a last line without its newline is not joined to the next"
check "$(head -n 2 "$AF")" "$before" "the earlier rows are not rewritten"
out=$(verb list)
case "$out" in *"proj-b  session sess-1  from the environment"*) check ok ok "list: shows a session row with its note" ;; *) check "$out" "a row" "list: shows a session row with its note" ;; esac
case "$out" in *"proj-c  path proj-a/.claude/worktrees/topic-1  a worktree"*) check ok ok "list: shows a path row" ;; *) check "$out" "a row" "list: shows a path row" ;; esac
rm -f "$AF"
case "$(verb list)" in "no attribution rows ("*) check ok ok "list: no file" ;; *) check bad ok "list: no file" ;; esac
: > "$REGATTA_CONFIG/regatta/attribution"
verb add proj-b --session sess-1 >/dev/null; check "$?" 2 "add: attribution turned off is refused (exit 2)"
rm -f "$REGATTA_CONFIG/regatta/attribution"
out=$(python3 "$M/bin/regatta" attribution list 2>&1)
case "$out" in "no attribution rows ("*) check ok ok "regatta attribution: the core's CLI runs the verb" ;; *) check "$out" "no rows" "regatta attribution: the core's CLI runs the verb" ;; esac

if [ "$fails" -ne 0 ]; then echo "attribution: $fails FAILED"; exit 1; fi
echo "attribution: all passed"
