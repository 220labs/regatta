#!/usr/bin/env bash
# Tests for bin/finish-stuck-rebase — a scratch repo left mid-rebase of main the way the vault was
# (2026-10-10): the first pick committed, three to go, records written in place meanwhile.
#   bash modules/wharf/tests/test_finish_stuck_rebase.sh
set -u
B="$(cd "$(dirname "$0")/../bin" && pwd)"   # the module's bin/ (B6)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fails=0
check() { if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3: expected [$2] got [$1]"; fails=$((fails+1)); fi; }
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t TMPDIR="$T"

# stuck <dir> [<file>]: main = base + four picks appending to <file> (default bulletin.md); onto =
# base + a log line; HEAD = onto + pick 1, detached, rebase-merge naming picks 2-4; log.md written
# in place since. The caller then edits <file> in place.
stuck() {
  local R="$1" F="${2:-bulletin.md}"
  git init -q -b main "$R"
  printf 'top\n\n\n\nbottom\n' > "$R/$F"; echo log > "$R/log.md"
  git -C "$R" add -A; git -C "$R" commit -qm base
  local p
  for p in 1 2 3 4; do
    printf 'pick %s\n' "$p" >> "$R/$F"; git -C "$R" commit -qam "Vault: $F (pick $p)"
  done
  git -C "$R" branch onto main~4
  git -C "$R" checkout -q onto; echo "upstream" >> "$R/log.md"; git -C "$R" commit -qam upstream
  git -C "$R" checkout -q --detach onto
  git -C "$R" cherry-pick main~3 >/dev/null
  local G; G=$(git -C "$R" rev-parse --absolute-git-dir); mkdir -p "$G/rebase-merge"
  echo refs/heads/main > "$G/rebase-merge/head-name"; git -C "$R" rev-parse main > "$G/rebase-merge/orig-head"
  for p in 2 1 0; do echo "pick $(git -C "$R" rev-parse "main~$p") # Vault: $F" >> "$G/rebase-merge/git-rebase-todo"; done
  echo "in place" >> "$R/log.md"
}
state() { [ -d "$(git -C "$1" rev-parse --absolute-git-dir)/rebase-merge" ] && echo left || echo gone; }

echo "the real shape: bulletin.md appended in place after the same line the picks append to"
R="$T/ok"; stuck "$R"; old=$(git -C "$R" rev-parse main)
echo "a post written in place" >> "$R/bulletin.md"
out=$("$B/finish-stuck-rebase" "$R" 2>&1); check "$?" 0 "exits 0 (a union merge for the append-only records)"
check "$(git -C "$R" symbolic-ref HEAD)" "refs/heads/main" "  HEAD is on main again"
check "$(state "$R")" "gone" "  the rebase state is gone"
check "$(git -C "$R" log --format=%s main | head -5 | tr '\n' '|')" "Vault: bulletin.md (pick 4)|Vault: bulletin.md (pick 3)|Vault: bulletin.md (pick 2)|Vault: bulletin.md (pick 1)|upstream|" "  main: the four picks on top of upstream"
check "$(git -C "$R" show main:bulletin.md | grep -c '^pick')" "4" "  every pick's line is on main"
check "$(grep -c '^pick' "$R/bulletin.md")" "4" "  …and on disk"
check "$(grep -c '^a post written in place$' "$R/bulletin.md")" "1" "  the post written in place stays"
check "$(tail -1 "$R/log.md")" "in place" "  a file the picks never touched is not rewritten"
check "$(git -C "$R" status --short | sort | tr '\n' '|')" " M bulletin.md| M log.md|" "  both show as uncommitted, nothing staged"
check "$(git -C "$R" merge-base --is-ancestor "$old" main && echo kept || echo rewritten)" "rewritten" "  main moved off the old tip"

echo "a path with a space"
R="$T/space"; stuck "$R" "a b.md"
# -i.bak, then the backup removed: BSD sed wants `-i ''` and GNU sed reads that '' as the script,
# so this is the one spelling both take (regatta's CI runs on ubuntu since B6 moved the suite).
sed -i.bak '1s/^top$/top, written in place/' "$R/a b.md" && rm -f "$R/a b.md.bak"
out=$("$B/finish-stuck-rebase" "$R" 2>&1); check "$?" 0 "exits 0"
check "$(grep -c '^pick' "$R/a b.md")" "4" "  every pick's line on disk"
check "$(head -1 "$R/a b.md")" "top, written in place" "  the in-place edit stays"
check "$(git -C "$R" status --short --untracked-files=all | grep -c '??')" "0" "  no stray files"

echo "an in-place edit that overlaps a replayed line, in a file that is no append-only record: stopped, nothing changed"
R="$T/clash"; stuck "$R" notes.md; old=$(git -C "$R" rev-parse main); head=$(git -C "$R" rev-parse HEAD)
echo "pick 2, edited in place" >> "$R/notes.md"
before=$(cat "$R/notes.md")
out=$("$B/finish-stuck-rebase" "$R" 2>&1); check "$?" 1 "exits 1"
check "$(echo "$out" | grep -c 'stopped, nothing changed')" "1" "  says it changed nothing"
check "$(git -C "$R" rev-parse main)" "$old" "  main where it was"
check "$(git -C "$R" rev-parse HEAD)" "$head" "  HEAD where it was"
check "$(state "$R")" "left" "  the rebase state left for a person"
check "$(cat "$R/notes.md")" "$before" "  the live file untouched"

# stuck_upstream <dir> <file>...: upstream appended to every <file> too, and the hand-resolved pick 1
# put its line before upstream's, so pick 2 conflicts in the replay itself (the other Mac's vault,
# 2026-10-15). With NUL=1 the first file's pick 2 line carries a NUL byte, so git calls it binary.
stuck_upstream() {
  local R="$1" F p G
  shift
  git init -q -b main "$R"
  for F in "$@"; do printf 'top\n\nbottom\n' > "$R/$F"; done; git -C "$R" add -A; git -C "$R" commit -qm base
  for p in 1 2 3; do
    for F in "$@"; do printf 'pick %s\n' "$p" >> "$R/$F"; done
    [ "${NUL:-0}" = 1 ] && [ "$p" = 2 ] && printf '\0' >> "$R/$1"
    git -C "$R" commit -qam "Vault: $* (pick $p)"
  done
  git -C "$R" checkout -q --detach main~3
  for F in "$@"; do echo upstream >> "$R/$F"; done; git -C "$R" commit -qam upstream
  for F in "$@"; do printf 'top\n\nbottom\npick 1\nupstream\n' > "$R/$F"; done; git -C "$R" commit -qam "Vault: $* (pick 1)"
  G=$(git -C "$R" rev-parse --absolute-git-dir); mkdir -p "$G/rebase-merge"
  echo refs/heads/main > "$G/rebase-merge/head-name"; git -C "$R" rev-parse main > "$G/rebase-merge/orig-head"
  for p in 1 0; do echo "pick $(git -C "$R" rev-parse "main~$p") # Vault: $*" >> "$G/rebase-merge/git-rebase-todo"; done
}

echo "a pick that conflicts in the replay, in bulletin.md only: union-merged"
R="$T/replay"; stuck_upstream "$R" bulletin.md
out=$("$B/finish-stuck-rebase" "$R" 2>&1); check "$?" 0 "exits 0"
check "$(echo "$out" | grep -c '^union-merged .*bulletin.md')" "1" "  says which pick it union-merged"
check "$(state "$R")" "gone" "  the rebase state is gone"
check "$(git -C "$R" show main:bulletin.md | grep -cE '^(pick [123]|upstream)$')" "4" "  every pick's line and upstream's are on main"
check "$(git -C "$R" show main:bulletin.md | grep -c '^[<=>]\{7\}')" "0" "  no conflict markers"

echo "a pick that conflicts in the replay, in a file that is no append-only record: stopped, nothing changed"
R="$T/replay-clash"; stuck_upstream "$R" notes.md; old=$(git -C "$R" rev-parse main); head=$(git -C "$R" rev-parse HEAD)
out=$("$B/finish-stuck-rebase" "$R" 2>&1); check "$?" 1 "exits 1"
check "$(echo "$out" | grep -c 'in notes.md — stopped, nothing changed')" "1" "  names the file, says it changed nothing"
check "$(git -C "$R" rev-parse main)" "$old" "  main where it was"
check "$(git -C "$R" rev-parse HEAD)" "$head" "  HEAD where it was"
check "$(state "$R")" "left" "  the rebase state left for a person"

echo "a pick that conflicts in bulletin.md AND in a file that is no append-only record: stopped, nothing changed"
R="$T/replay-both"; stuck_upstream "$R" bulletin.md notes.md; old=$(git -C "$R" rev-parse main); head=$(git -C "$R" rev-parse HEAD)
st=$(git -C "$R" status --short)
out=$("$B/finish-stuck-rebase" "$R" 2>&1); check "$?" 1 "exits 1"
check "$(echo "$out" | grep -c 'in notes.md — stopped, nothing changed')" "1" "  names the non-union file"
check "$(git -C "$R" rev-parse main)" "$old" "  main where it was"
check "$(git -C "$R" rev-parse HEAD)" "$head" "  HEAD where it was"
check "$(state "$R")" "left" "  the rebase state left for a person"
check "$(git -C "$R" status --short)" "$st" "  the working tree as it was"

echo "a pick that conflicts in bulletin.md, which holds a NUL byte (binary): stopped, nothing changed"
R="$T/replay-bin"; NUL=1 stuck_upstream "$R" bulletin.md; old=$(git -C "$R" rev-parse main); head=$(git -C "$R" rev-parse HEAD)
st=$(git -C "$R" status --short)
out=$("$B/finish-stuck-rebase" "$R" 2>&1); check "$?" 1 "exits 1"
check "$(echo "$out" | grep -c 'in bulletin.md: union merge failed — stopped, nothing changed')" "1" "  says the union merge failed, nothing changed"
check "$(git -C "$R" rev-parse main)" "$old" "  main where it was"
check "$(git -C "$R" rev-parse HEAD)" "$head" "  HEAD where it was"
check "$(state "$R")" "left" "  the rebase state left for a person"
check "$(git -C "$R" status --short)" "$st" "  the working tree as it was"

echo "a pick that adds a file in a folder the live tree lacks (memory/books/ on the other Mac, 2026-10-16)"
R="$T/newdir"; stuck "$R"; G=$(git -C "$R" rev-parse --absolute-git-dir)
blob=$(echo "a new memory" | git -C "$R" hash-object -w --stdin)
idx="$T/newdir.index"; GIT_INDEX_FILE="$idx" git -C "$R" read-tree main
GIT_INDEX_FILE="$idx" git -C "$R" update-index --add --cacheinfo "100644,$blob,books/new.md"
c=$(git -C "$R" commit-tree "$(GIT_INDEX_FILE="$idx" git -C "$R" write-tree)" -p main -m "Vault: memory (books)")
git -C "$R" update-ref refs/heads/main "$c"; echo "$c" > "$G/rebase-merge/orig-head"; echo "pick $c # books" >> "$G/rebase-merge/git-rebase-todo"
check "$([ -e "$R/books" ] && echo there || echo absent)" "absent" "  books/ not on disk before the run"
out=$("$B/finish-stuck-rebase" "$R" 2>&1); check "$?" 0 "exits 0"
check "$(state "$R")" "gone" "  the rebase state is gone"
check "$(cat "$R/books/new.md" 2>/dev/null)" "a new memory" "  the new file is on disk in its new folder"

check "$(echo "$out" | grep -c 'failed after main moved')" "0" "  the after-move trap stays silent on a good run"

echo "a file standing where the new folder goes: stopped before main moves"
R="$T/fileparent"; stuck "$R"; G=$(git -C "$R" rev-parse --absolute-git-dir)
blob=$(echo "a new memory" | git -C "$R" hash-object -w --stdin)
idx="$T/fileparent.index"; GIT_INDEX_FILE="$idx" git -C "$R" read-tree main
GIT_INDEX_FILE="$idx" git -C "$R" update-index --add --cacheinfo "100644,$blob,books/new.md"
c=$(git -C "$R" commit-tree "$(GIT_INDEX_FILE="$idx" git -C "$R" write-tree)" -p main -m "Vault: memory (books)")
git -C "$R" update-ref refs/heads/main "$c"; echo "$c" > "$G/rebase-merge/orig-head"; echo "pick $c # books" >> "$G/rebase-merge/git-rebase-todo"
echo x > "$R/books"
out=$("$B/finish-stuck-rebase" "$R" 2>&1); check "$?" 1 "exits 1"
check "$(echo "$out" | grep -c 'books is a file in the live tree — stopped, nothing changed')" "1" "  says why, nothing changed"
check "$(git -C "$R" rev-parse main)" "$c" "  main where it was"
check "$(state "$R")" "left" "  the rebase state left"

echo "a todo with more than picks: stopped, nothing changed"
R="$T/verbs"; stuck "$R"; echo "exec true" >> "$(git -C "$R" rev-parse --absolute-git-dir)/rebase-merge/git-rebase-todo"
out=$("$B/finish-stuck-rebase" "$R" 2>&1); check "$?" 1 "exits 1"
check "$(state "$R")" "left" "  the rebase state left"

echo "no rebase in progress: nothing to do"
R="$T/none"; git init -q -b main "$R"; git -C "$R" commit -q --allow-empty -m one
check "$("$B/finish-stuck-rebase" "$R" | grep -c 'nothing to do')" "1" "says so, exits 0"

[ "$fails" -eq 0 ] && echo "all finish-stuck-rebase tests passed" || { echo "$fails finish-stuck-rebase test(s) failed"; exit 1; }
