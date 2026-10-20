#!/usr/bin/env bash
# Tests for bin/publish — a scratch projects folder, a scratch NAS and a scratch Drive, each with
# its two shares (named by the config dir's lighthouse/shares). No network, nothing outside a
# scratch dir.   bash modules/lighthouse/tests/publish.sh
set -u
B="$(cd "$(dirname "$0")/../bin" && pwd)"
T=$(mktemp -d); T=$(cd "$T" && pwd -P); trap 'chmod -R u+w "$T" 2>/dev/null; rm -rf "$T"' EXIT
fails=0
check() { if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3: expected [$2] got [$1]"; fails=$((fails+1)); fi; }
has()   { if grep -qF -- "$2" "$1"; then echo "  ok   $3"; else echo "  FAIL $3: missing [$2]"; fails=$((fails+1)); fi; }
lacks() { if grep -qF -- "$2" "$1"; then echo "  FAIL $3: found [$2]"; fails=$((fails+1)); else echo "  ok   $3"; fi; }
yes_if() { if [ "$1" "$2" ]; then echo yes; else echo no; fi; }

export PUBLISH_PROJECTS="$T/projects" PUBLISH_NAS="$T/nas" PUBLISH_DRIVE="$T/drive" PUBLISH_STATE="$T/state" REGATTA_CONFIG="$T/config"
mkdir -p "$REGATTA_CONFIG/lighthouse"; printf 'data:share_d\nvault:share_v\n' > "$REGATTA_CONFIG/lighthouse/shares"
P="$T/projects"; N="$T/nas"; D="$T/drive"
mkdir -p "$N/share_d" "$N/share_v" "$D/share_d" "$D/share_v"
mkdir -p "$P/repo/docs" "$P/repo/log/2026" "$P/repo/.claude/worktrees/topic/docs" "$P/outside-ok"
echo "alpha" > "$P/repo/docs/a.md"
echo "wt" > "$P/repo/.claude/worktrees/topic/docs/b.md"
echo "one" > "$P/repo/log/2026-08.jsonl"
echo "two" > "$P/repo/log/2026-09.jsonl"
echo "deep" > "$P/repo/log/2026/10.jsonl"
echo "hidden" > "$P/repo/log/.hidden.jsonl"
echo "SECRET=1" > "$P/repo/.env"
echo "elsewhere" > "$T/elsewhere.md"
pub() { "$B/publish" "$@" > "$T/out" 2> "$T/err"; echo $?; }
qcount() { ls "$T/state/queue" 2>/dev/null | grep -c '\.json$' | tr -d ' '; }

echo "the scope"
check "$(pub "$P/repo/docs/a.md")" "2" "no scope: refused"
check "$(pub --data --vault "$P/repo/docs/a.md")" "2" "both scopes: refused"
check "$(yes_if -e "$N/share_d/repo")" "no" "…and nothing copied"

echo "one file, both destinations"
check "$(pub --data "$P/repo/docs/a.md")" "0" "exit 0"
check "$(cat "$N/share_d/repo/docs/a.md")" "alpha" "on the NAS at <repo>/<path>"
check "$(cat "$D/share_d/repo/docs/a.md")" "alpha" "in Drive at the same path"
has "$T/out" "published share_d/repo/docs/a.md → nas, drive" "one line per copy"
check "$(ls -A "$D/share_d/repo/docs" | tr '\n' ' ')" "a.md " "no temp file left behind"
check "$(yes_if -e "$N/share_v/repo")" "no" "--data never writes the vault"
check "$(pub --vault "$P/repo/docs/a.md")" "0" "--vault"
check "$(cat "$D/share_v/repo/docs/a.md")" "alpha" "…goes to share_v"
echo "beta" > "$P/repo/docs/a.md"
pub --data "$P/repo/docs/a.md" > /dev/null
check "$(cat "$D/share_d/repo/docs/a.md")" "beta" "a second call rewrites the copy"
(cd "$P/repo" && "$B/publish" --data docs/a.md > /dev/null)
check "$?" "0" "a relative path is relative to the working folder"

echo "worktrees"
check "$(pub --data "$P/repo/.claude/worktrees/topic/docs/b.md")" "0" "a worktree's file"
check "$(cat "$N/share_d/repo/docs/b.md")" "wt" "…goes where the main checkout's would"
echo "main" > "$P/repo/docs/b.md"
check "$(pub --data "$P/repo/docs/b.md" "$P/repo/.claude/worktrees/topic/docs/b.md")" "2" "a worktree copy and the main copy together: refused"
has "$T/err" "name one" "…asking which"
# a repo in a group folder, as studio/pipeline (2026-09-25: its worktree files landed under .claude/worktrees)
mkdir -p "$P/group/repo/.claude/worktrees/topic/scripts" "$P/group/repo/scripts"
echo "nested" > "$P/group/repo/.claude/worktrees/topic/scripts/a.ps1"
echo "plain" > "$P/group/repo/scripts/c.ps1"
echo "stray" > "$P/group/repo/.claude/worktrees/stray"; echo "stray" > "$P/repo/.claude/worktrees/stray"
check "$(pub --data "$P/group/repo/.claude/worktrees/topic/scripts/a.ps1")" "0" "a worktree's file, repo one folder down"
check "$(cat "$D/share_d/group/repo/scripts/a.ps1")" "nested" "…goes where the main checkout's would"
check "$(yes_if -e "$D/share_d/group/repo/.claude")" "no" "…and nothing under .claude/worktrees"
check "$(pub --data --dry-run "$P/group/repo/scripts/c.ps1")" "0" "a plain file in that repo"
has "$T/out" "$D/share_d/group/repo/scripts/c.ps1" "…keeps its path"
pub --data --dry-run "$P/repo/.claude/worktrees/stray" "$P/group/repo/.claude/worktrees/stray" > /dev/null
has "$T/out" "$N/share_d/repo/.claude/worktrees/stray" "a file with no path after the worktree's name: not collapsed"
has "$T/out" "$N/share_d/group/repo/.claude/worktrees/stray" "…at any depth"
echo "main" > "$P/group/repo/scripts/a.ps1"
check "$(pub --data "$P/group/repo/scripts/a.ps1" "$P/group/repo/.claude/worktrees/topic/scripts/a.ps1")" "2" "nested: the worktree copy and the main copy together: refused"

echo "patterns and lists"
check "$(pub --data "$P/repo/log/*.jsonl")" "0" "a quoted pattern"
check "$(grep -c '^published' "$T/out")" "2" "…matches the two files at that level"
check "$(yes_if -e "$D/share_d/repo/log/.hidden.jsonl")" "no" "…and not a hidden file"
check "$(pub --vault "$P/repo/log/**/*.jsonl")" "0" "** crosses folders"
check "$(cat "$N/share_v/repo/log/2026/10.jsonl")" "deep" "…to the file two levels down"
printf '# the logs\n\nlog/2026-0?.jsonl\ndocs/a.md\n' > "$P/repo/publish.list"
(cd "$T" && "$B/publish" --vault --list "$P/repo/publish.list" > "$T/out" 2> "$T/err"); rc=$?
check "$rc" "0" "--list"
check "$(grep -c '^published' "$T/out")" "3" "…lines relative to the list's folder, comments and blanks skipped"
check "$(pub --data "$P/repo/docs/a.md" "$P/repo/nothing-*.md" "$P/repo/missing.md")" "1" "a pattern that matches nothing: exit 1"
has "$T/err" "no match for $P/repo/nothing-*.md" "…named"
has "$T/err" "no such file: $P/repo/missing.md" "a missing file is named too"
has "$T/out" "published share_d/repo/docs/a.md" "…and the rest still goes"
check "$(pub --data --list "$T/no-list.txt")" "2" "a missing list file: refused"

echo "refused before anything is copied"
rm -rf "$N/share_d/repo/log"
check "$(pub --data "$P/repo/log/2026-08.jsonl" "$P/repo/docs")" "2" "a folder"
has "$T/err" "use '$P/repo/docs/**'" "…with the pattern to use"
check "$(yes_if -e "$N/share_d/repo/log/2026-08.jsonl")" "no" "…and the good file was not copied either"
check "$(pub --data "$T/elsewhere.md")" "2" "a file outside the projects folder"
has "$T/err" "not under" "…says why"
check "$(pub --vault "$P/repo/.env")" "2" "an .env file, even to the vault"
check "$(yes_if -e "$N/share_v/repo/.env")" "no" "…never copied"

echo "a destination down: NAS unmounted"
mv "$N/share_d" "$N/offline"
echo "gamma" > "$P/repo/docs/a.md"
check "$(pub --data "$P/repo/docs/a.md" "$P/repo/docs/b.md")" "0" "one destination is enough: exit 0"
has "$T/err" "share_d/repo/docs/a.md → nas queued:" "one line per miss"
has "$T/err" "not mounted" "…saying why"
check "$(grep -c 'nas queued' "$T/err")" "2" "…per file"
has "$T/out" "→ drive" "Drive still took them"
check "$(yes_if -e "$N/share_d")" "no" "the share's root is never created"
check "$(qcount)" "2" "two copies queued"
check "$(pub --data --strict "$P/repo/docs/a.md")" "1" "--strict: both or fail"
check "$(qcount)" "2" "…the same entry, not a second one"
"$B/publish" --status > "$T/st"; rc=$?
check "$rc" "1" "--status exits 1 while something waits"
has "$T/st" "waiting share_d/repo/docs/a.md → nas" "…and names it"
has "$T/st" "MISSING $N/share_d" "…and the missing destination"
check "$(pub --data --delete "$P/repo/docs/b.md")" "0" "--delete with one destination down"
check "$(yes_if -f "$P/repo/docs/b.md")" "yes" "…keeps the file"
has "$T/err" "kept $P/repo/docs/b.md" "…and says so"

echo "retry"
mv "$N/offline" "$N/share_d"
echo "delta" > "$P/repo/docs/a.md"
"$B/publish" --retry > "$T/out" 2> "$T/err"; rc=$?
check "$rc" "0" "--retry exits 0 once all is delivered"
check "$(qcount)" "0" "the queue is empty"
check "$(cat "$N/share_d/repo/docs/a.md")" "delta" "the retry copies the source as it is now"
has "$T/out" "retry: 2 delivered, 0 dropped, 0 still waiting" "a summary line"
check "$("$B/publish" --status > /dev/null; echo $?)" "0" "--status exits 0 with nothing waiting"

echo "every call retries the queue"
mv "$N/share_v" "$N/offline"
pub --vault "$P/repo/docs/a.md" > /dev/null
check "$(qcount)" "1" "queued"
mv "$N/offline" "$N/share_v"
check "$(pub --data "$P/repo/log/2026-08.jsonl")" "0" "an unrelated call"
check "$(qcount)" "0" "…delivered the queued copy first"
has "$T/out" "(queued since" "…and said so"

echo "a queued source that is gone"
mv "$N/share_d" "$N/offline"
echo "tmp" > "$P/repo/docs/gone.md"
pub --data "$P/repo/docs/gone.md" > /dev/null
rm "$P/repo/docs/gone.md"
mv "$N/offline" "$N/share_d"
"$B/publish" --retry > "$T/out" 2> "$T/err"
has "$T/err" "dropped share_d/repo/docs/gone.md → nas" "dropped, with a line"
check "$(qcount)" "0" "…and out of the queue"

echo "a file the job may not rewrite (My Drive's rule; a read-only folder stands in)"
chmod 555 "$D/share_d/repo/docs"
echo "epsilon" > "$P/repo/docs/a.md"
check "$(pub --data "$P/repo/docs/a.md")" "0" "no crash, NAS still took it"
has "$T/err" "Drive refused rewriting repo/docs/a.md" "the line names the file"
check "$(cat "$N/share_d/repo/docs/a.md")" "epsilon" "NAS has the new copy"
chmod 755 "$D/share_d/repo/docs"
"$B/publish" --retry > /dev/null 2>&1

echo "the NAS refuses writes (macOS keeps a launchd job off network volumes)"
chmod 555 "$N/share_v/repo/docs"
echo "zeta" > "$P/repo/docs/z.md"; echo "eta" > "$P/repo/docs/y.md"
check "$(pub --vault "$P/repo/docs/z.md" "$P/repo/docs/y.md")" "0" "Drive still took them"
has "$T/err" "Network Volumes" "the line says which permission"
lacks "$T/err" "rewriting" "…and does not blame a file"
check "$(grep -c 'nas queued' "$T/err")" "2" "…one line per file"
chmod 755 "$N/share_v/repo/docs"
"$B/publish" --retry > /dev/null 2>&1

echo "both down"
mv "$N/share_d" "$N/off1"; mv "$D/share_d" "$D/off2"
check "$(pub --data "$P/repo/docs/a.md")" "1" "no destination took it: exit 1"
check "$(wc -l < "$T/out" | tr -d ' ')" "0" "nothing claimed as published"
mv "$N/off1" "$N/share_d"; mv "$D/off2" "$D/share_d"
"$B/publish" --retry > /dev/null 2>&1

echo "--delete"
echo "bye" > "$P/repo/docs/c.md"
check "$(pub --vault --delete "$P/repo/docs/c.md")" "0" "both took it"
check "$(yes_if -e "$P/repo/docs/c.md")" "no" "…so the local file is gone"
check "$(cat "$N/share_v/repo/docs/c.md")$(cat "$D/share_v/repo/docs/c.md")" "byebye" "…and both copies are there"
has "$T/out" "deleted $P/repo/docs/c.md" "…said"

echo "--dry-run"
check "$(pub --data --dry-run "$P/repo/docs/b.md")" "0" "exit 0"
has "$T/out" "$D/share_d/repo/docs/b.md" "prints the Drive path"
has "$T/out" "$N/share_d/repo/docs/b.md" "…and the NAS path"
echo "changed" > "$P/repo/docs/b.md"
pub --data --dry-run "$P/repo/docs/b.md" > /dev/null
check "$(cat "$N/share_d/repo/docs/b.md")" "main" "…and copies nothing"

echo "--dest: one destination (usage-report's Drive-only copy, 2026-10-19)"
check "$(pub --data --dry-run --dest drive "$P/repo/docs/b.md")" "0" "--dest drive --dry-run"
has "$T/out" "$D/share_d/repo/docs/b.md" "…names the Drive path"
lacks "$T/out" "$N/share_d" "…and not the NAS"
mv "$N/share_d" "$N/offline"
pub --data "$P/repo/docs/b.md" > /dev/null
check "$(qcount)" "1" "the NAS down: its copy queued"
check "$(pub --data --dest drive "$P/repo/docs/b.md")" "0" "the same file, --dest drive"
has "$T/err" "dropped the queued share_d/repo/docs/b.md → nas: --dest drive" "…drops the NAS copy it no longer wants"
check "$(qcount)" "0" "…so nothing waits forever"
has "$T/out" "published share_d/repo/docs/b.md → drive" "…and Drive takes it"
check "$(pub --data --dest drive --strict "$P/repo/docs/b.md")" "0" "--strict means every destination named"
mv "$N/offline" "$N/share_d"
check "$(pub --retry --dest drive)" "2" "--retry takes no --dest"
check "$(pub --data --delete --dest drive "$P/repo/docs/b.md")" "2" "--delete with --dest: refused, a move keeps two copies"
check "$(cat "$P/repo/docs/b.md")" "changed" "…and the source stays"

echo "never lists a destination"
lacks "$B/publish" "listdir" "no os.listdir"
lacks "$B/publish" "iterdir" "no iterdir"
check "$(grep 'glob(' "$B/publish" | grep -vcE 'glob\.glob\(pat,|QUEUE\.glob\(' | tr -d ' ')" "0" "globbing only on sources and the local queue"

echo "the destinations from the config dir: a value, and a link to a folder with a space in its path"
mkdir -p "$T/a nas/share_d" "$T/a share root/share_d"
echo "$T/a nas" > "$REGATTA_CONFIG/lighthouse/nas"; ln -s "$T/a share root" "$REGATTA_CONFIG/lighthouse/drive"
env -u PUBLISH_NAS -u PUBLISH_DRIVE "$B/publish" --data "$P/repo/docs/a.md" > /dev/null 2>&1
check "$(cat "$T/a nas/share_d/repo/docs/a.md" "$T/a share root/share_d/repo/docs/a.md" 2>&1 | tr '\n' ' ')" "$(cat "$P/repo/docs/a.md") $(cat "$P/repo/docs/a.md") " "both reached through the keys"
rm "$REGATTA_CONFIG/lighthouse/nas" "$REGATTA_CONFIG/lighthouse/drive"

echo "one destination configured: --delete and --strict refused, a queued copy to the other kept (B9 review)"
mkdir -p "$T/one nas/share_d"; echo "$T/one nas" > "$REGATTA_CONFIG/lighthouse/nas"
check "$(env -u PUBLISH_NAS -u PUBLISH_DRIVE "$B/publish" --data --delete "$P/repo/docs/a.md" > /dev/null 2>&1; echo "rc=$? $(yes_if -f "$P/repo/docs/a.md")")" "rc=2 yes" "--delete with only lighthouse/nas: exit 2, the source stays"
check "$(env -u PUBLISH_NAS -u PUBLISH_DRIVE "$B/publish" --data --strict "$P/repo/docs/a.md" > /dev/null 2>&1; echo "rc=$?")" "rc=2" "--strict with only lighthouse/nas: exit 2"
mkdir -p "$T/state/queue"; printf '{"scope":"data","dest":"drive","rel":"repo/docs/a.md","source":"%s","since":"x","tries":1,"reason":"x"}' "$P/repo/docs/a.md" > "$T/state/queue/stale.json"
check "$(env -u PUBLISH_NAS -u PUBLISH_DRIVE "$B/publish" --retry 2>&1 >/dev/null; echo "rc=$?")" "publish: left share_d/repo/docs/a.md → drive queued: lighthouse/drive is not configured
rc=1" "a queued copy to an unconfigured destination: one line, no KeyError, kept"
check "$(qcount)" "1" "…still queued"
rm -f "$T/state/queue/stale.json"
echo "a Drive link that dangles (Drive not running): still a destination, its copy queued, the source kept"
ln -s "$T/no drive" "$REGATTA_CONFIG/lighthouse/drive"
check "$(env -u PUBLISH_NAS -u PUBLISH_DRIVE "$B/publish" --data --delete "$P/repo/docs/a.md" > /dev/null 2>&1; echo "$(qcount) $(yes_if -f "$P/repo/docs/a.md")")" "1 yes" "the Drive copy queued, the file not deleted"
rm -rf "$T/state/queue" "$REGATTA_CONFIG/lighthouse/nas" "$REGATTA_CONFIG/lighthouse/drive"

echo "no destination configured: refused"
check "$(env -u PUBLISH_NAS -u PUBLISH_DRIVE "$B/publish" --data "$P/repo/docs/a.md" 2>&1 >/dev/null; echo "rc=$?")" "publish: no destination — set lighthouse/nas or lighthouse/drive in the regatta config dir
rc=2" "neither key nor variable: exit 2, saying which keys"

echo
if [ "$fails" = 0 ]; then echo "all green"; else echo "$fails failing"; exit 1; fi
