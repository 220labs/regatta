#!/usr/bin/env bash
# Tests for bin/trust-projects, against a scratch HOME and config dir — the real .claude.json is
# never read.
#   bash modules/lighthouse/tests/trust-projects.sh
set -u
unset CLAUDE_CONFIG_DIR   # a session on another account's dir must not test against it (review 2026-10-03)
B="$(cd "$(dirname "$0")/../bin" && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export REGATTA_CONFIG="$T/config"; mkdir -p "$REGATTA_CONFIG"   # the projects folder: the default, under HOME
fails=0
check() { if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3: expected [$2] got [$1]"; fails=$((fails+1)); fi; }
run() { HOME="$T" TRUST_PROJECTS_SETTLE=0 python3 "$B/trust-projects" "$@"; }
has() { python3 -c "import json,sys; p=json.load(open(sys.argv[1])).get('projects',{}); print((p.get(sys.argv[2]) or {}).get('hasTrustDialogAccepted') is True)" "$T/.claude.json" "$1"; }

P="$T/projects"
mkdir -p "$P/app/.git" "$P/studio/books/.git" "$P/studio/productions/kids/start/.git" \
         "$P/studio/plain" "$P/app/.claude/worktrees/w" "$P/.hidden/x/.git" "$P/app/sub/.git"
echo "gitdir: elsewhere" > "$P/app/.claude/worktrees/w/.git"
ln -s "$P/studio/books" "$P/books-link"
cat > "$T/.claude.json" <<EOF
{"oauthAccount": {"emailAddress": "x"}, "numStartups": 7,
 "projects": {"$P/app": {"allowedTools": ["Bash"], "hasTrustDialogAccepted": true},
              "$P/studio/books": {"hasTrustDialogAccepted": false}}}
EOF
chmod 600 "$T/.claude.json"

run --check > "$T/out"; rc=$?
check "$rc" 1 "--check exits 1 while anything is untrusted"
check "$(grep -c untrusted "$T/out")" 3 "--check lists projects, books and start"
check "$(grep -c 'app' "$T/out")" 0 "an already-trusted repo is not listed"

run > "$T/out"; rc=$?
check "$rc" 0 "a run exits 0"
check "$(has "$P")" True "the projects folder itself is trusted"
check "$(has "$P/studio/books")" True "an explicit false becomes true"
check "$(has "$P/studio/productions/kids/start")" True "a repo four levels down is found"
check "$(has "$P/studio/plain")" False "a plain folder gets no entry (the projects folder covers it)"
check "$(has "$P/app/.claude/worktrees/w")" False "a worktree gets no entry"
check "$(has "$P/app/sub")" False "nothing below a repo root"
check "$(has "$P/.hidden/x")" False "no dot-folders"
check "$(has "$P/books-link")" False "no symlinks"
check "$(python3 -c "import json;c=json.load(open('$T/.claude.json'));print(c['numStartups'], c['oauthAccount']['emailAddress'], c['projects']['$P/app']['allowedTools'])")" \
      "7 x ['Bash']" "every other key survives"
check "$(stat -f '%Lp' "$T/.claude.json" 2>/dev/null || stat -c '%a' "$T/.claude.json")" 600 "the file stays mode 600"
check "$(ls "$T" | grep -c trust-)" 0 "no temp file left behind"

run --check > /dev/null; check "$?" 0 "--check exits 0 afterwards"
check "$(run)" "  ok  all 4 trusted (~/projects and every repo under it)" "a second run changes nothing"

# --no-external-imports (an employer login's dir, 2026-10-18): the dialog's No, ahead, for home and every project
python3 -c "import json,sys; f=sys.argv[1]; c=json.load(open(f)); c['projects']['$T/elsewhere']={'hasClaudeMdExternalIncludesApproved': True}; json.dump(c, open(f,'w'))" "$T/.claude.json"
run --check --no-external-imports > /dev/null; check "$?" 1 "--no-external-imports: --check exits 1 while any entry lacks the No"
run --no-external-imports > /dev/null; check "$?" 0 "…a run exits 0"
noext() { python3 -c "import json,sys; e=(json.load(open(sys.argv[1])).get('projects',{}).get(sys.argv[2]) or {}); print(e.get('hasClaudeMdExternalIncludesWarningShown'), e.get('hasClaudeMdExternalIncludesApproved'), e.get('hasTrustDialogAccepted'))" "$T/.claude.json" "$1"; }
check "$(noext "$P/app")" "True False True" "…a repo: trusted, and the No"
check "$(noext "$T")" "True False None" "…home itself: the No, never trust"
check "$(noext "$T/elsewhere")" "True False None" "…an approval elsewhere is answered No"
run --check --no-external-imports > /dev/null; check "$?" 0 "…--check exits 0 afterwards"
check "$(noext "$P/studio/books")" "True False True" "…every repo here gets it"

echo; [ $fails -eq 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
