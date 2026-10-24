#!/usr/bin/env bash
# Tests for bin/owed — fixture transcripts and a throwaway repo with origin/claude/* refs, one
# commit before the ask and one after; no network.   bash modules/keel/tests/owed.sh
set -u
B="$(cd "$(dirname "$0")/../bin" && pwd)"
T=$(mktemp -d); T=$(cd "$T" && pwd -P); trap 'rm -rf "$T"' EXIT
fails=0
check() { if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3: expected [$2] got [$1]"; fails=$((fails+1)); fi; }
has()   { if grep -qF -- "$2" "$1"; then echo "  ok   $3"; else echo "  FAIL $3: missing [$2]"; fails=$((fails+1)); fi; }
lacks() { if grep -qF -- "$2" "$1"; then echo "  FAIL $3: found [$2]"; fails=$((fails+1)); else echo "  ok   $3"; fi; }

ASK=2026-10-02T10:00:00Z
export OWED_PROJECTS="$T/projects"
# The suite's own config dir: its vaults are vault-a and vault-b on every machine, never the Mac's.
export REGATTA_CONFIG="$T/cfg"; mkdir -p "$REGATTA_CONFIG/lighthouse"
printf 'vault-a\nvault-b\n' > "$REGATTA_CONFIG/lighthouse/vaults"
mkdir -p "$T/projects/-me" "$T/projects/-other" "$T/projects/-x-scratchpad-bench"
python3 - "$T/projects" <<'PY'
import json, sys
p = sys.argv[1]
def w(f, rows): open(f, "w").write("".join(json.dumps(r) + "\n" for r in rows))
def a(ts, text, **kw): return dict(type="assistant", timestamp=ts, message={"content": [{"type": "text", "text": text}]}, **kw)
w(p + "/-me/SESS.jsonl", [a("2026-10-02T09:00:00Z", "unrelated"),
                          a("2026-10-02T10:00:00Z", "Still owed by you: delete FOO_KEY from conf/app.json")])
w(p + "/-other/OTHER.jsonl", [a("2026-10-02T09:30:00Z", "FOO_KEY early, before the ask", gitBranch="claude/early"),
                              a("2026-10-02T11:00:00Z", "removed FOO_KEY as asked", gitBranch="claude/late"),
                              a("2026-10-02T11:05:00Z", "FOO_KEY in a subagent", gitBranch="claude/late", isSidechain=True)])
w(p + "/-x-scratchpad-bench/BENCH.jsonl", [a("2026-10-02T11:00:00Z", "FOO_KEY in a headless bench run")])
PY
touch "$T/projects"/*/*.jsonl

R="$T/repo"; git init -q "$R"; mkdir -p "$R/conf"
c() { GIT_AUTHOR_DATE="$1" GIT_COMMITTER_DATE="$1" git -C "$R" -c user.name=t -c user.email=t@t commit -qam "$2" --allow-empty; }
echo '{"FOO_KEY": 1}' > "$R/conf/app.json"; git -C "$R" add -A; c 2026-10-02T09:00:00Z "add FOO_KEY"
git -C "$R" update-ref refs/remotes/origin/claude/early HEAD
echo '{}' > "$R/conf/app.json"; c 2026-10-02T11:00:00Z "drop FOO_KEY"
git -C "$R" update-ref refs/remotes/origin/claude/late HEAD

run() { (cd "$R" && python3 "$B/owed" "$@") > "$T/out" 2>&1; echo $?; }

echo "since: this session's first mention"
check "$(run FOO_KEY 'FOO_KEY@conf/app.json' --session SESS)" "0" "exit 0"
has "$T/out" "since: $ASK (this session's first mention)" "since is the ask, not the earlier unrelated line"
has "$T/out" "drop FOO_KEY" "a branch commit after the ask is found"
lacks "$T/out" "add FOO_KEY" "a commit before the ask is not"
has "$T/out" "transcript: OTHER.js -other — 1 entries, first 11:00:00Z, branches claude/late" "another session after the ask, one entry"
lacks "$T/out" "SESS.jso" "this session's own transcript is skipped"
lacks "$T/out" "BENCH" "headless bench runs are skipped"
has "$T/out" "state: FOO_KEY absent in $R/conf/app.json" "the key's state is read"

echo "fallbacks"
run FOO_KEY --session NOSUCH > /dev/null
has "$T/out" "no first mention found — last 24h" "no mention: the window, said so"
run FOO_KEY --since 2026-10-02T08:00:00Z > /dev/null
has "$T/out" "add FOO_KEY" "--since earlier widens to both commits"
run nothing-matches-this --since 2026-10-02T08:00:00Z > /dev/null
has "$T/out" "branch: no hits" "no branch hit, said so"
has "$T/out" "transcript: no hits" "no transcript hit, said so"

echo "review fixes"
mkdir -p "$T/projects/-me-worktree"
python3 - "$T/projects" <<'PY'
import json, sys
open(sys.argv[1] + "/-me-worktree/SESS.jsonl", "w").write(json.dumps(dict(type="assistant",
    timestamp="2026-10-02T09:45:00Z", message={"content": [{"type": "text", "text": "FOO_KEY first said here"}]})) + "\n")
PY
run 'FOO_KEY@conf/app.json' --session SESS > /dev/null
has "$T/out" "since: 2026-10-02T09:45:00Z" "earliest mention across both of a session's files, by the bare key"
rm "$T/projects/-me-worktree/SESS.jsonl"
run FOO_KEY --since 2026-10-02T12:30:00+02:00 > /dev/null
has "$T/out" "since: 2026-10-02T10:30:00Z" "an offset --since is converted to UTC"
run claude/late --since 2026-10-02T08:00:00Z > /dev/null
has "$T/out" "state: branch origin/claude/late exists, not on main" "a branch marker reads as a branch, not a missing path"
run claude/gone --since 2026-10-02T08:00:00Z > /dev/null
has "$T/out" "state: branch origin/claude/gone gone" "a branch no longer on origin is said so, not probed as a path"
run FOO_KEY --session NOSUCH --window 2d > /dev/null
has "$T/out" "last 48h" "--window takes days"

echo "secrets"
mkdir -p "$T/vault-a/_secrets"; echo '{"K": 1}' > "$T/vault-a/_secrets/x.json"
run "K@$T/vault-a/_secrets/x.json" --since 2026-10-02T08:00:00Z > /dev/null
has "$T/out" "under _secrets, not read" "never reads Drive _secrets"
mkdir -p "$T/vault-b/_secrets"; echo '{"K": 1}' > "$T/vault-b/_secrets/x.json"
run "K@$T/vault-b/_secrets/x.json" --since 2026-10-02T08:00:00Z > /dev/null
has "$T/out" "under _secrets, not read" "  nor vault-b's"
mkdir -p "$T/other/_secrets"; echo '{"K": 1}' > "$T/other/_secrets/x.json"
run "K@$T/other/_secrets/x.json" --since 2026-10-02T08:00:00Z > /dev/null
lacks "$T/out" "under _secrets" "  the key names the vaults: another folder's _secrets is read"
mkdir -p "$T/cfg-none"
(cd "$R" && REGATTA_CONFIG="$T/cfg-none" python3 "$B/owed" "K@$T/other/_secrets/x.json" --since 2026-10-02T08:00:00Z) > "$T/out" 2>&1
has "$T/out" "under _secrets, not read" "  no key: any _secrets is closed (the wider net)"

echo
[ "$fails" -eq 0 ] && echo "test_owed: all passed" || echo "test_owed: $fails failed"
[ "$fails" -eq 0 ]
