#!/bin/bash
# The queue's live case (dispatch-queue S1): dispatch-queue's write path, re-done here in shell — a hook-less bare clone,
# an orphan commit by commit-tree, `push --porcelain --force-with-lease` — against a real queue home,
# on a scratch ref, never the queue's. Run by hand from a host whose identity has push on the home:
#   bash modules/wharf-runs/tests/queue_live.sh <queue repo url> [scratch ref]
# What it proves: the home accepts a non-branch ref under refs/regatta/ and serves it to a fresh fetch;
# a second writer on a stale lease is rejected, one after the other and racing; the ref never grows;
# the scratch ref is deleted at the end. Exit 0 when every expectation held, 1 otherwise.
# Not in check.sh: it writes a live repo. Hook-less on purpose, as Fleet.ensure (D6-A).
set -u
URL=${1:?usage: queue_live.sh <queue repo url> [scratch ref]}
REF=${2:-refs/regatta/probe}
case "$REF" in refs/regatta/queue) echo "refuse: that is the queue itself" >&2; exit 2;; refs/regatta/*) ;; *) echo "refuse: a scratch ref under refs/regatta/" >&2; exit 2;; esac
W=$(mktemp -d "${TMPDIR:-/tmp}/queue-live.XXXXXX")
trap 'rm -rf "$W"' EXIT
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY
export LC_ALL=C LANG=C GIT_TERMINAL_PROMPT=0 GIT_AUTHOR_NAME="regatta queue" GIT_AUTHOR_EMAIL=queue@regatta.invalid \
  GIT_COMMITTER_NAME="regatta queue" GIT_COMMITTER_EMAIL=queue@regatta.invalid
FAIL=0
expect() {   # $1 label, $2 got, $3 wanted
  if [ "$2" = "$3" ]; then echo "  ok   $1"; else echo "  FAIL $1: got [$2] wanted [$3]"; FAIL=1; fi
}
now() { python3 -c 'import time; print("%.3f" % time.time())'; }
mk() {
  git init -q --bare "$W/$1" && git --git-dir="$W/$1" config core.hooksPath /dev/null && git --git-dir="$W/$1" config gc.auto 0
}
orphan() {   # $1 clone, $2 text: an orphan commit holding queue/probe.json
  local g="$W/$1" blob sub root
  blob=$(printf '{"probe": "%s"}\n' "$2" | git --git-dir="$g" hash-object -w --stdin)
  sub=$(printf '100644 blob %s\tprobe.json\n' "$blob" | git --git-dir="$g" mktree)
  root=$(printf '040000 tree %s\tqueue\n' "$sub" | git --git-dir="$g" mktree)
  git --git-dir="$g" commit-tree "$root" -m "probe $2"
}
put() {   # $1 clone, $2 commit, $3 lease base ("" = must not exist) -> file $W/out.$1: rc, seconds, text
  local t0 rc out
  t0=$(now)
  out=$(git --git-dir="$W/$1" push --porcelain "--force-with-lease=$REF:$3" "$URL" "$2:$REF" 2>&1); rc=$?
  printf '%s %s\n%s\n' "$rc" "$(python3 -c "print('%.2f' % ($(now) - $t0))")" "$out" > "$W/out.$1"
}
rc() { head -1 "$W/out.$1" | cut -d' ' -f1; }
secs() { head -1 "$W/out.$1" | cut -d' ' -f2; }
remote() { git ls-remote "$URL" "$REF" | cut -f1; }

mk a; mk b; mk c
echo "home: $URL  ref: $REF  at $(date '+%Y-%m-%d %H:%M:%S %Z')"
expect "the scratch ref is absent before" "$(remote)" ""

echo "1. create from nothing (lease: must not exist)"
A=$(orphan a create); put a "$A" ""
echo "   push $(secs a) s"; expect "accepted" "$(rc a)" 0; expect "the home holds it" "$(remote)" "$A"

echo "2. two writers on base A, one after the other"
B=$(orphan a writer-1); C=$(orphan b writer-2)
put a "$B" "$A"; expect "writer 1 accepted" "$(rc a)" 0
put b "$C" "$A"; expect "writer 2 on the stale lease rejected" "$([ "$(rc b)" != 0 ] && echo rejected)" rejected
echo "   writer 1 $(secs a) s; the loser was told:"; sed -n '2,$p' "$W/out.b" | sed 's/^/     | /'
expect "the home holds writer 1's" "$(remote)" "$B"

echo "3. racing, 5 rounds, two clones, one base"
wins=0
for i in 1 2 3 4 5; do
  base=$(remote); x=$(orphan a "race-$i-a"); y=$(orphan b "race-$i-b")
  put a "$x" "$base" & put b "$y" "$base" & wait
  got=$(remote); w=none
  [ "$got" = "$x" ] && [ "$(rc a)" = 0 ] && [ "$(rc b)" != 0 ] && w=a
  [ "$got" = "$y" ] && [ "$(rc b)" = 0 ] && [ "$(rc a)" != 0 ] && w=b
  echo "   round $i: a rc $(rc a) $(secs a) s, b rc $(rc b) $(secs b) s, one winner: $w"
  [ "$w" != none ] && wins=$((wins + 1))
  [ "$i" = 1 ] && [ "$w" != none ] && { l=b; [ "$w" = b ] && l=a; sed -n '2,$p' "$W/out.$l" | sed 's/^/     | /'; }
done
expect "one winner in every round" "$wins" 5

echo "4. a fresh clone fetches it; it never grows"
git --git-dir="$W/c" fetch --no-tags -q "$URL" "+$REF:$REF"; expect "fetch" "$?" 0
expect "the fetch serves the home's sha" "$(git --git-dir="$W/c" rev-parse "$REF")" "$(remote)"
expect "commits on the ref" "$(git --git-dir="$W/c" rev-list --count "$REF")" 1

echo "5. delete the scratch ref"
cur=$(remote)
git --git-dir="$W/a" push --porcelain "--force-with-lease=$REF:$cur" "$URL" ":$REF" >/dev/null 2>&1; expect "delete" "$?" 0
expect "the scratch ref is absent after" "$(remote)" ""

[ "$FAIL" = 0 ] && echo "PASSED" || echo "FAILED"
exit "$FAIL"
