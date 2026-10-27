#!/usr/bin/env bash
# lighthouse's hooks and claude-settings: secrets_guard (the secrets folders, the live settings
# file, sessionpipe's ungating verbs), claude-settings, account_guard, design_route, tool_path,
# and design_route with no core. Ported at B9 (2026-10-19) from the overlay's suite, every name
# made up: a scratch HOME and config dir, no network, nothing real read or written.
#   bash modules/lighthouse/tests/hooks.sh
set -u
for v in $(env | sed -n 's/^\(CLAUDE[A-Za-z0-9_]*\)=.*/\1/p; s/^\(DISPATCH[A-Za-z0-9_]*\)=.*/\1/p'); do unset "$v"; done
unset REGATTA_HOME REGATTA_LEGACY
# Outside claude-host unless a case says otherwise: bin/account's Drive-backed reads differ by it (S4), and
# a dispatched session runs this suite under claude-host
export REGATTA_CLAUDE_HOST=0
C="$(cd "$(dirname "$0")/.." && pwd)"; H="$C/hooks"; R="$(cd "$C/../.." && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export REGATTA_DRIVE_ROOTS="$T"   # the stand-in drive: a link under $T is a link into a cloud drive (S4)
export HOME="$T/home" REGATTA_CONFIG="$T/config"
mkdir -p "$HOME" "$REGATTA_CONFIG/regatta" "$REGATTA_CONFIG/lighthouse"
echo Owner > "$REGATTA_CONFIG/regatta/owner"
printf 'alpha_vault\nbeta_vault\n' > "$REGATTA_CONFIG/lighthouse/vaults"
printf 'laptop\nserver\n' > "$REGATTA_CONFIG/lighthouse/hosts"
echo server > "$REGATTA_CONFIG/lighthouse/design-host"
printf 'sessionpipe\nherdctl\n' > "$REGATTA_CONFIG/lighthouse/gated-tools"   # the session-sync tool and its front end
export GIT_CONFIG_GLOBAL="$T/gitconfig"; git config --global init.defaultBranch main
fails=0
check() { if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3: expected [$2] got [$1]"; fails=$((fails+1)); fi; }
# BSD stat takes -f, GNU stat -c; the GNU form fails cleanly on a Mac, so try it first.
fmode() { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"; }

echo "secrets_guard"
SG="$H/secrets_guard.py"; SGV="$T/sg/vault"; SGR="$T/sg/repo"
mkdir -p "$SGV/_secrets" "$SGV/notes" "$SGR/sub" "$T/sg/other"
echo "A=1" > "$SGV/_secrets/app.env"; ln -s "$SGV/_secrets/app.env" "$SGR/.env"; echo "A=" > "$SGR/.env.example"
sg() { python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"PreToolUse","cwd":sys.argv[1],"tool_name":sys.argv[2],"tool_input":json.loads(sys.argv[3])}))' "${SGCWD:-$SGR}" "$1" "$2" \
  | SECRETS_GUARD_DIR="$SGV/_secrets" python3 "$SG" | grep -c '"deny"'; }
sg_path() { sg "$1" "$(python3 -c 'import json,sys; print(json.dumps({sys.argv[1]: sys.argv[2]}))' "$2" "$3")"; }
sg_bash() { sg Bash "$(python3 -c 'import json,sys; print(json.dumps({"command": sys.argv[1]}))' "$1")"; }
check "$(sg_path Read file_path "$SGV/_secrets/app.env")" 1 "Read of a file in _secrets is refused"
check "$(sg_path Read file_path "$T/sg/x/alpha_vault/_contacts/work.txt") $(sg_bash "cat '$T/sg/x/alpha_vault/_contacts/work.txt'")" "1 1" \
  "  and of a contact book in a vault's _contacts, Read and cat alike (work contacts, 2026-10-18)"
check "$(sg_bash 'python3 tools/messenger.py contacts add work "Jane Doe" +15550000006')" 0 \
  "  the messaging tool's own contacts command passes: it reads the books in its own process"
check "$(sg_path Read file_path .env)" 1 "  and of a repo's .env, through its link"
check "$(sg_path Edit file_path .env)" 1 "  Edit too"
check "$(sg_path Write file_path "$SGV/_secrets/new.env")" 1 "  Write of a new file there too"
check "$(sg_path Grep path .env)" 1 "  Grep on the link"
check "$(sg_path Grep path "$SGV")" 1 "  Grep over a folder that holds it"
check "$(sg_path Read file_path "$SGV/notes/notes.md")" 0 "the rest of the vault is open"
check "$(sg_path Edit file_path "$SGV/notes/notes.md")" 0 "  for writes too"
check "$(sg_path Read file_path .env.example)" 0 "  and .env.example"
check "$(sg Grep '{"pattern":"TODO"}')" 0 "  and Grep over the repo (rg skips the link)"
check "$(sg_bash 'cat .env')" 1 "Bash: cat .env"
check "$(sg_bash 'grep A .env')" 1 "  grep"
check "$(sg_bash 'source .env && echo $A')" 1 "  source"
check "$(sg_bash '. ./.env')" 1 "  ."
check "$(sg_bash 'cp .env /tmp/copy')" 1 "  copying it out"
check "$(sg_bash "cp \"$SGV/_secrets/app.env\" .env")" 1 "  copying it in instead of linking"
check "$(SGCWD="$T/sg/other" sg_bash "cd \"$SGR\" && head -1 .env")" 1 "  a cd earlier in the command is followed"
check "$(sg_bash 'xxd < .env')" 1 "  a redirection from it"
check "$(sg_bash 'echo "$(< .env)"')" 1 "  inside \$( )"
check "$(sg_bash 'echo `cat .env`')" 1 "  inside backticks"
check "$(sg_bash "python3 -c \"print(open('.env').read())\"")" 1 "  python -c"
check "$(sg_bash "$(printf "python3 - <<'EOF'\nprint(open('.env').read())\nEOF")")" 1 "  a python heredoc"
check "$(sg_bash "$(printf "bash <<'EOF'\ncat .env\nEOF")")" 1 "  a shell heredoc"
check "$(sg_bash 'sh -c "cat .env"')" 1 "  sh -c"
check "$(sg_bash 'eval "cat .env"')" 1 "  eval"
check "$(sg_bash 'dd if=.env of=/tmp/x')" 1 "  dd if="
check "$(sg_bash 'ln .env hard')" 1 "  a hard link (it reads through)"
check "$(sg_bash "rg KEY \"$SGV\"")" 1 "  rg over a folder that holds it"
check "$(sg_bash "rm -rf \"$SGV\"")" 1 "  rm -rf of a folder that holds it"
check "$(sg_bash 'echo B=2 >> .env')" 1 "  >> into it"
check "$(sg_bash "$(printf 'cat > .env <<EOF\nB=2\nEOF')")" 1 "  a heredoc into it"
check "$(sg_bash "sed -i '' 's/A/B/' .env")" 1 "  sed -i"
check "$(sg_bash 'cp .env.example .env')" 1 "  cp onto the link (writes through it)"
check "$(sg_bash "rm \"$SGV/_secrets/app.env\"")" 1 "  rm of the Drive file"
check "$(sg_bash 'FOO=1 sudo truncate -s 0 .env')" 1 "  behind an assignment and a wrapper"
check "$(sg_bash 'cd /tmp && touch "$V/alpha_vault/_secrets/x"')" 1 "  alpha_vault/_secrets behind a variable"
check "$(sg_bash 'cd /tmp && cat "$V/beta_vault/_secrets/x.env"')" 1 "  beta_vault/_secrets too (the shared vault)"
check "$(sg_bash 'cd /tmp && ls "$V/beta_vault/notes.md" && cat "$V/beta_vault/notes.md"')" 0 "  but not the rest of beta_vault"
check "$(sg_bash 'python3 tools/bin/secrets check app --fix')" 1 "  secrets --fix"
check "$(sg_bash "ln -s \"$SGV/_secrets/app.env\" sub/.env")" 0 "ln -s to a secret passes"
check "$(sg_bash "ln -sfn \"$SGV/_secrets/app.env\" .env")" 0 "  ln -sfn over the link"
check "$(sg_bash "ls -la \"$SGV/_secrets\" && readlink .env && stat .env && [ -e .env ] && test -L .env")" 0 "  ls, readlink, stat, [ ], test"
check "$(sg_bash 'rm .env')" 0 "  rm of the link itself"
check "$(sg_bash 'mv .env .env.old')" 0 "  mv of the link itself"
check "$(sg_bash 'git check-ignore .env && echo .env')" 0 "  git and echo"
check "$(sg_bash 'python3 scripts/app.py --check')" 0 "  an app that reads .env itself"
check "$(sg_bash 'python3 tools/bin/secrets check app')" 0 "  secrets check without --fix"
check "$(sg_bash 'cat .env.example')" 0 "  .env.example"
check "$(sg_bash "git commit -m \"Secrets: .env reads through Drive's _secrets\"")" 0 "  a commit message that mentions them"
check "$(sg_bash "$(printf "git commit -F - <<'EOF'\nSecrets: .env and alpha_vault/_secrets/app.env\nEOF")")" 0 "  a heredoc that is only data"
check "$(sg_bash "$(printf "python3 - <<'EOF'\nprint('\$SGV/_secrets/x')\nEOF")")" 0 "  a heredoc naming a fixture's _secrets"
check "$(sg_bash 'grep -r TODO . && git status 2>&1 > /tmp/x')" 0 "  grep -r over the repo, unrelated redirections"
check "$(sg_bash 'ls -p ~ | grep -v /') $(sg_bash 'grep -n x /dev/null')" "0 0" "  a grep's pattern is no folder, and a grep without -r walks none (review S2, 2026-10-22)"
check "$(echo 'not json' | python3 "$SG"; echo $?)" 0 "garbage stdin: silent, exit 0 (fails open)"

echo "the fence: a confidential scope's paths, closed to a session outside it (knowledge-layers S2)"
FH="$T/home"; FP="$FH/projects"; FL="$T/fence-logs"; FD="$T/fence"
mkdir -p "$FP/node-knowledge/memory" "$FP/node-app/src" "$FP/open/docs" "$FP/dream" "$FP/two-knowledge" "$FP/transcripts/node-app" \
  "$FH/.claude" "$FH/.claude-w" "$FH/.claude-o" "$FD/out"
for r in node-knowledge open two-knowledge; do git init -q "$FP/$r"; git -C "$FP/$r" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init; done
echo "the client's plan" > "$FP/node-knowledge/memory/plan.md"; echo src > "$FP/node-app/src/a.py"; echo notes > "$FP/open/docs/n.md"
echo t > "$FP/transcripts/node-app/s.md"; echo two > "$FP/two-knowledge/x.md"
git -C "$FP/node-knowledge" worktree add -q "$FP/node-knowledge/trees/pass" -b pass
git -C "$FP/node-knowledge" worktree add -q "$FD/out/away" -b away   # outside the checkout: only git worktree list finds it
fslug() { printf '%s' "$1" | sed 's/[^A-Za-z0-9]/-/g'; }
MEM="$FH/.claude-w/projects/$(fslug "$FP/node-knowledge")/memory"; mkdir -p "$MEM"; echo m > "$MEM/MEMORY.md"
SF="$(dirname "$MEM")"; echo '{"said": "the client"}' > "$SF/s-1.jsonl"   # the session folder: its transcripts beside memory (D1-A)
OSF="$FH/.claude-w/projects/$(fslug "$FP/open")"; mkdir -p "$OSF"; echo '{}' > "$OSF/s-2.jsonl"
VM="$FD/vault/memory/node-knowledge"; mkdir -p "$VM" "$FH/.claude-o/projects/$(fslug "$FP/node-knowledge")"; echo v > "$VM/v.md"
ln -s "$VM" "$FH/.claude-o/projects/$(fslug "$FP/node-knowledge")/memory"   # a memory dir linked out (not yet adopted)
ln -s "$FP/node-knowledge/memory/plan.md" "$FP/open/docs/plan-link.md"
printf '{"accounts": [{"label": "w", "provider": "claude", "home": "~/.claude-w"}, {"label": "x", "provider": "codex", "home": "~/.claude"}]}\n' > "$FD/acc.json"
printf '{"o": {"home": "~/.claude-o"}, "_default": {"enabled": true}}\n' > "$FD/orca.json"
printf '{"repos": {"node-knowledge": {}, "node-app": {}, "open": {}, "dream": {}, "two-knowledge": {}},\n "scopes": {"node": {"file": "n", "repos": ["node-knowledge", "node-*"], "confidential": true},\n  "two": {"file": "t", "repos": ["two-knowledge"], "confidential": true},\n  "atlas": {"file": "a", "repos": ["open", "dream"], "confidential": "yes"}}}\n' > "$FD/repos.json"
sed 's/"confidential": true/"confidential": false/g' "$FD/repos.json" > "$FD/open.json"
echo "$FL" > "$REGATTA_CONFIG/regatta/log-dir"
FENV() { env CLAUDE_REPOS_JSON="${FRJ:-$FD/repos.json}" ACCOUNTS_FILE="$FD/acc.json" ACCOUNT_ORCA_FILE="$FD/orca.json" CLAUDE_PROJECT_DIR="${FPD:-}" SECRETS_GUARD_DIR="$T/sg/no-such-vault" "$@"; }
fraw() { python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"PreToolUse","cwd":sys.argv[1],"tool_name":sys.argv[2],"tool_input":json.loads(sys.argv[3]),"session_id":"s-1"}))' "$1" "$2" "$3" | FENV python3 "$SG"; }
fg() { fraw "$@" | python3 -c 'import json,sys; t=sys.stdin.read(); print(json.loads(t)["hookSpecificOutput"]["permissionDecision"] if t.strip() else "pass")'; }
fpath() { fg "$1" "$2" "$(python3 -c 'import json,sys; print(json.dumps({sys.argv[1]: sys.argv[2]}))' "$3" "$4")"; }
fbash() { fg "$1" Bash "$(python3 -c 'import json,sys; print(json.dumps({"command": sys.argv[1]}))' "$2")"; }
fglob() { fg "$1" Glob "$(python3 -c 'import json,sys; print(json.dumps(dict({"pattern": sys.argv[1]}, **({"path": sys.argv[2]} if sys.argv[2] else {}))))' "$2" "${3:-}")"; }
OUT="$FP/open"; IN="$FP/node-knowledge"; DREAM="$FP/dream"
check "$(FENV python3 - "$R/modules/regatta/hooks" "$SG" <<'PY'
import importlib.util as u, sys
sys.path.insert(0, sys.argv[1]); import common
s = u.spec_from_file_location("sg", sys.argv[2]); g = u.module_from_spec(s); s.loader.exec_module(g)
print(" ".join("%s:%d:%s" % (n, len(common.scope_paths(n)), [str(p) for p in common.scope_paths(n)] == g.scope_paths(n))
               for n in ("node", "two", "atlas", "nope")))
PY
)" "node:18:True two:5:True atlas:10:True nope:0:True" \
  "the guard's stdlib scope_paths() agrees with the core's: trees, an outside worktree, a glob member, 3 logins (an Orca one; a codex row skipped)"
check "$(fpath "$OUT" Read file_path "$IN/memory/plan.md") $(fpath "$OUT" Edit file_path "$FP/node-app/src/a.py") $(fpath "$OUT" Write file_path "$IN/new.md")" \
  "deny deny deny" "from an open repo: Read, Edit and Write of the scope's checkouts (a glob's member too)"
check "$(fpath "$OUT" Read file_path "$FD/out/away/x") $(fpath "$OUT" Read file_path "$FP/transcripts/node-app/s.md") $(fpath "$OUT" Read file_path "$MEM/MEMORY.md")" \
  "deny deny deny" "  a worktree outside the checkout, the transcripts folder, a login's memory dir"
check "$(fpath "$OUT" Read file_path "$SF/s-1.jsonl") $(fpath "$OUT" Grep path "$SF") $(fglob "$OUT" '*.jsonl' "$SF") $(fglob "$OUT" '**/*.jsonl' "$FH/.claude-w/projects") $(fbash "$OUT" "cat '$SF'/*.jsonl")" \
  "deny deny deny deny deny" "  a login's session transcripts (projects/<slug>/*.jsonl): Read, Grep, Glob in it and from above, Bash (S2's D1-A)"
check "$(fpath "$OUT" Read file_path "$VM/v.md") $(fpath "$OUT" Read file_path "$FH/.claude-o/projects/$(fslug "$FP/node-knowledge")/memory/v.md") $(fpath "$OUT" Read file_path "$OSF/s-2.jsonl")" \
  "deny deny pass" "  a memory dir linked out, at its target and through the link; the open repo's own session folder passes"
check "$(fpath "$OUT" Read file_path docs/plan-link.md) $(fpath "$OUT" NotebookEdit notebook_path "$IN/n.ipynb")" "deny deny" "  through a link in the open repo; NotebookEdit"
check "$(fpath "$OUT" Grep path "$IN") $(fpath "$OUT" Grep path "$FP") $(fpath "$FP" Grep path "")" "deny deny deny" \
  "  Grep inside it, over a folder that holds it, and from a cwd that holds it"
check "$(fglob "$OUT" '**/*.md' "$IN") $(fglob "$OUT" '**/*.md' "$FP") $(fglob "$OUT" 'node-knowledge/*' "$FP") $(fglob "$OUT" "$IN/**")" \
  "deny deny deny deny" "  Glob in it, a ** from above it, a pattern that names it, an absolute pattern"
check "$(fglob "$OUT" '*' "$FP") $(fglob "$OUT" 'open/**/*.md' "$FP") $(fglob "$OUT" '**/*.md' "") $(fglob "$OUT" '*/x.md' "$FP/two-knowledge/..")" \
  "pass pass pass deny" "  a Glob that stops at the repos' names, stays in the open repo or runs in it passes; one a level into a scope does not"
check "$(fbash "$OUT" "cat '$IN/memory/plan.md'") $(fbash "$OUT" "git -C '$IN' log") $(fbash "$OUT" "cd '$IN' && git log") $(fbash "$OUT" "cd '$IN' && ls")" \
  "deny deny deny deny" "Bash: cat, git -C, git and ls after a cd into it"
check "$(fbash "$OUT" "ls '$IN/memory'") $(fbash "$OUT" "grep -r client '$FP'") $(fbash "$OUT" 'cat "$PJ/node-knowledge/memory/plan.md"') $(fbash "$OUT" "echo x > '$IN/x'")" \
  "deny deny deny deny" "  ls of it, grep -r over ~/projects, a path behind an unseen variable, a redirection into it"
check "$(fbash "$OUT" "cat $FP/*/memory/plan.md") $(fbash "$OUT" "grep -r client $FP/*") $(fbash "$OUT" "cat $OUT/docs/n*.md") $(fbash "$OUT" "cat $OUT/docs/*.md")" "deny deny pass deny" \
  "  a word the shell expands is expanded and judged per match: into the scope refused, within the open repo not, unless a match is a link into it"
check "$(fbash "$OUT" "grep --regexp=client '$IN/memory/plan.md'") $(fbash "$OUT" "grep -eclient '$IN/memory/plan.md'") $(fbash "$OUT" "grep -rne client '$IN/memory/plan.md'") $(fbash "$OUT" "rg --files '$IN'")" \
  "deny deny deny deny" "  a grep whose pattern is attached to its option reads the first word as a file; rg --files lists the tree (review S2, 2026-10-22)"
check "$(fbash "$FP" "grep -r client") $(fbash "$FP" "rg client") $(fbash "$FP" "find . -name '*.md'") $(fbash "$FP" "ls -R") $(fbash "$FP" "du -a") $(fbash "$FP" "tree")" \
  "deny deny deny deny deny deny" "  a walker with no path, from a cwd that holds the scope, as the Grep tool from there"
check "$(fbash "$OUT" "find '$FP' -name '*.md'") $(fbash "$OUT" "ls -R '$FP'") $(fbash "$OUT" "grep -r client") $(fbash "$OUT" "rg client") $(fbash "$OUT" "find . -name '*.md'") $(fbash "$FP" "grep client") $(fbash "$OUT" "ls '$FP'")" \
  "deny deny pass pass pass pass pass" "  find and ls -R over a folder that holds it; the open repo's own walk, a grep of stdin and a plain ls pass"
check "$(fbash "$OUT" "echo $IN/memory/*") $(fbash "$OUT" "printf '%s\n' $IN/memory/*") $(fbash "$OUT" "git diff --no-index /dev/null '$IN/memory/plan.md'") $(fbash "$OUT" "git diff --no-index docs/n.md docs/n.md")" \
  "deny deny deny pass" "  echo and printf of a glob into it print its file names; git diff --no-index reads its paths, not a tree"
check "$(fbash "$FP" "rg -g '*.md' client") $(fbash "$FP" "grep -rn --include '*.md' client") $(fbash "$FP" "grep -r -e client") $(fbash "$FP" "rg -e client") $(fbash "$FP" "grep -r -m 5 client")" \
  "deny deny deny deny deny" "  an option's value is no path: the walker still walks the cwd that holds the scope"
check "$(fbash "$FP" "ps aux | rg claude") $(fbash "$FP" "rg --version") $(fbash "$FP" "rg x -") $(fbash "$OUT" "echo $FP/*") $(fbash "$OUT" "ls -d $FP/*/") $(fbash "$OUT" "for r in $FP/*/; do git -C \$r status -s; done") $(fbash "$OUT" "if [ -d '$IN' ]; then echo y; fi")" \
  "pass pass pass pass pass pass pass" "  a walker reading a pipe or printing its version, and names-only commands over the projects folder, pass"
check "$(fbash "$OUT" "ls $FP/*") $(fbash "$OUT" "git diff /dev/null '$IN/memory/plan.md'") $(fbash "$OUT" "git clone '$IN' /tmp/x") $(fbash "$OUT" "GIT_DIR='$IN/.git' git show HEAD") $(fbash "$OUT" "pushd '$FP' >/dev/null && cat node-knowledge/memory/plan.md")" \
  "deny deny deny deny deny" "  ls of a glob that lists it, a plain git diff and a clone of it, GIT_DIR=, a pushd into its parent"
check "$(fbash "$OUT" "grep --regexp='$IN/memory' docs/n.md") $(fbash "$OUT" "git grep -n '$IN/memory'") $(FPATHS=1 fbash "$OUT" "find '$FP/nowhere-here' '$OUT' -name x")" \
  "pass pass pass" "  a grep pattern that names it, in an option or git grep, is text"
echo top > "$FP/README.md"
check "$(fbash "$OUT" "cp docs/n.md '$FP/'") $(fbash "$OUT" "mv docs/n.md '$FH'") $(fbash "$FH" "rm -f nothere") $(fbash "$FH" "chmod +x nothere") $(fbash "$FP" "find . -maxdepth 1 -type d")" \
  "pass pass pass pass pass" "  a copy into the projects folder or home, a plain rm or chmod, find one level down: no walk of the scope"
check "$(fbash "$OUT" "cp -R '$FP' /tmp/x") $(fbash "$OUT" "cd $FP/node-k* && git log") $(fbash "$OUT" "git -C $FP/node-k* log") $(fbash "$FP" "rg client -g '*.md'") $(fbash "$FP" "grep -rn client --include '*.md'") $(fbash "$FP" "find . -maxdepth 3 -name '*.md'")" \
  "deny deny deny deny deny deny" "  a recursive copy of a folder that holds it, a cd or git -C through a glob, a walker whose option value names a file, find deep enough"
rm -f "$FP/README.md"
MISSING="$T/fence-missing"; mkdir -p "$MISSING/projects/elsewhere"
printf '{"repos": {"gone": {}}, "scopes": {"g": {"file": "g", "repos": ["gone"], "confidential": true}}}\n' > "$FD/gone.json"
check "$(FRJ="$FD/gone.json" fbash "$OUT" "find '$FP' -name x") $(FRJ="$FD/gone.json" fbash "$FP" "du -a")" "pass pass" \
  "  a scope whose checkout this Mac lacks: walkers over the projects folder pass"
printf '{"repos": {"node-knowledge": {}, "open": {}}, "scopes": {"s": {"file": "s", "repos": "node-*", "confidential": true}}}\n' > "$FD/str.json"
check "$(FRJ="$FD/str.json" fpath "$OUT" Read file_path "$FP/open/docs/n.md")" "pass" "  a scope whose repos is a string has no members, as the core reads it"
GONE="$FH/.claude-w/projects/$(fslug "$FP/node-knowledge")--claude-worktrees-old"; mkdir -p "$GONE" "$GONE-x" "$FH/.claude-w/projects/$(fslug "$FP/node-knowledge")-site"
echo '{}' > "$GONE/s-3.jsonl"; echo '{}' > "$FH/.claude-w/projects/$(fslug "$FP/node-knowledge")-site/s-4.jsonl"
check "$(fpath "$OUT" Read file_path "$GONE/s-3.jsonl") $(fbash "$DREAM" "cat '$GONE/s-3.jsonl'") $(fpath "$OUT" Read file_path "$FH/.claude-w/projects/$(fslug "$FP/node-knowledge")-site/s-4.jsonl")" \
  "deny deny pass" "  a removed worktree's session folder (<slug>--claude-worktrees-<topic>) stays fenced; a sibling slug's does not"
check "$(fbash "$OUT" "python3 -c \"print(open('$IN/memory/plan.md').read())\"") $(fbash "$OUT" "$(printf "python3 - <<'X'\nopen('~/projects/node-knowledge/memory/plan.md')\nX")")" \
  "deny deny" "  python -c and a python heredoc naming it"
check "$(fbash "$OUT" "git commit -m 'Moves $IN/memory into the knowledge repo'") $(fbash "$OUT" "grep -n '$IN/memory' docs/n.md") $(fbash "$OUT" "echo '$IN' && ls '$FP' && cat docs/n.md")" \
  "pass pass pass" "  but a commit message, a grep pattern, echo, ls of ~/projects and the open repo's files pass"
check "$(fbash "$OUT" "ln -s '$IN/memory' '$MEM/../memory-link'") $(fbash "$OUT" "test -d '$IN' && realpath '$IN'")" "pass pass" "  ln -s, test and realpath name it without reading"
check "$(fpath "$IN" Read file_path "$FP/node-app/src/a.py") $(fpath "$IN" Read file_path "$MEM/MEMORY.md") $(fbash "$IN" "cat memory/plan.md && git log && ls ../node-app")" \
  "pass pass pass" "the scope's own session (the pass's cwd: its knowledge repo) reads every path of the scope"
check "$(fpath "$IN" Read file_path "$SF/s-1.jsonl") $(fglob "$IN" '*.jsonl' "$SF") $(fpath "$IN" Read file_path "$VM/v.md")" "pass pass pass" \
  "  its session transcripts and its linked-out memory too"
check "$(FPD="$IN/trees/pass" fpath "$IN/trees/pass" Read file_path "$FD/out/away/x") $(fpath "$FD/out/away" Grep path "$IN")" "pass pass" \
  "  from either of its worktrees too"
check "$(fpath "$IN" Read file_path "$FP/two-knowledge/x.md") $(FPD="$OUT" fpath "$IN" Read file_path "$IN/memory/plan.md")" "deny deny" \
  "  but not another confidential scope's, and not a session that started outside and cd'd in (CLAUDE_PROJECT_DIR)"
check "$(fpath "$DREAM" Read file_path "$MEM/MEMORY.md") $(fbash "$DREAM" "cat '$FP/transcripts/node-app/s.md'") $(fpath "$DREAM" Read file_path "$SF/s-1.jsonl") $(fpath "$DREAM" Read file_path "$OUT/docs/n.md")" \
  "deny deny deny pass" "the dream's cwd (an open scope's repo): the scope's memory, transcripts and session logs refused, the open scope read"
check "$(FRJ="$FD/open.json" fpath "$OUT" Read file_path "$IN/memory/plan.md") $(FRJ=/no/such fpath "$OUT" Read file_path "$IN/memory/plan.md")" "pass pass" \
  "no scope flagged (only a real true counts), or no registry: everything passes"
rm -rf "$FL"; fpath "$OUT" Read file_path "$IN/memory/plan.md" >/dev/null; fglob "$DREAM" '**/*.md' "$IN" >/dev/null; fpath "$OUT" Read file_path "$OUT/docs/n.md" >/dev/null
check "$(wc -l < "$FL/fence.log" | tr -d ' ') $(cut -f2,3,5 "$FL/fence.log" | tr '\t\n' ',;') $(grep -c 'plan.md\|memory' "$FL/fence.log")" "2 node,Read,s-1;node,Glob,s-1; 0" \
  "one log line per refusal — scope, tool, cwd, session — and never the path asked for"
check "$(cut -f4 "$FL/fence.log" | tr '\n' ';')" "$OUT;$DREAM;" "  the cwd it came from"
rm -rf "$FL"; FPD="$OUT" fpath "$IN" Read file_path "$IN/memory/plan.md" >/dev/null; fpath "$FP/two-knowledge" Read file_path "$IN/memory/plan.md" >/dev/null
check "$(cut -f2,4 "$FL/fence.log" | tr '\t\n' ',;')" "node,-;node,-;" "  a cwd in a scope's paths (the cd-in case, another scope's tree) is logged as -"
check "$(fraw "$OUT" Read "{\"file_path\": \"$IN/memory/plan.md\"}" | python3 -c 'import json,sys; r=json.load(sys.stdin)["hookSpecificOutput"]["permissionDecisionReason"]; print("`node`" in r, sys.argv[1] in r, "set node --open" in r, "Owner" in r, "plan.md" in r)' "$IN")" \
  "True True True True True" "  the refusal names the scope, its knowledge repo as the way in, the verb that opens it, the owner"

echo "claude-settings (docs/record/machine-settings-2026-09-29.md)"
CS="$C/bin/claude-settings"; CSD="$T/cs"; mkdir -p "$CSD/cfg"
cs() { CLAUDE_CONFIG_DIR="$CSD/cfg" CLAUDE_SETTINGS_DECLARED="$CSD/user.json" CLAUDE_SETTINGS_HOST="${CSH:-laptop}" python3 "$CS" "$@"; }
csq() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(eval(sys.argv[2]))' "$CSD/cfg/settings.json" "$1"; }
csdecl() { printf '%s\n' "$1" > "$CSD/user.json"; }
printf '%s\n' '{"env":{"K":"v"},"deniedMcpServers":[{"serverName":"mine"}],"enabledPlugins":{"a@x":true},"permissions":{"allow":["Bash(ls)"]}}' > "$CSD/cfg/settings.json"
csdecl '{"shared":{"deniedMcpServers":[{"serverName":"Docs"}],"enabledPlugins":{"b@x":false},"permissions.deny":["Bash(rm -rf /)"]},"hosts":{"server":{"enabledPlugins":{"i@x":true}}}}'
check "$(cs session-start)" '{"user": ["settings: 3 declared change(s) applied — deniedMcpServers +{\"serverName\": \"Docs\"}; enabledPlugins.b@x = false; permissions.deny +\"Bash(rm -rf /)\""], "model": ["'"$CSD/cfg/settings.json differs from $CSD/user.json: 2 undeclared, 0 missing — \`$C/bin/claude-settings check\` lists each with the \`declare\` line that records it; record one only if it was meant"'"]}' "session-start applies a list entry, a map key and a nested list, and names the drift"
check "$(csq 'd["deniedMcpServers"]')" "[{'serverName': 'mine'}, {'serverName': 'Docs'}]" "  the machine's own list entry stays beside the declared one"
check "$(csq '(d["env"], d["permissions"]["allow"], d["enabledPlugins"]["a@x"])')" "({'K': 'v'}, ['Bash(ls)'], True)" "  env, permissions.allow and an undeclared plugin untouched"
nb=$(ls "$CSD/cfg" | grep -c 'bak-'); cp "$CSD/cfg/settings.json" "$CSD/before"
cs apply --if-changed >/dev/null
cmp -s "$CSD/before" "$CSD/cfg/settings.json"; check $? 0 "a second apply leaves the file byte-identical"
check "$(ls "$CSD/cfg" | grep -c 'bak-')" "$nb" "  and writes no backup"
check "$(cs apply)" "claude-settings: nothing to apply" "  apply without --if-changed finds nothing either"
csdecl '{"shared":{"enabledPlugins":{"b@x":false},"permissions.deny":["Bash(rm -rf /)"]}}'
cs apply >/dev/null
check "$(csq 'd["deniedMcpServers"]')" "[{'serverName': 'mine'}]" "an entry removed from the declaration leaves live; the machine's own stays"
python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["enabledPlugins"]["b@x"]=True; json.dump(d,open(p,"w"))' "$CSD/cfg/settings.json"
csdecl '{"shared":{"permissions.deny":["Bash(rm -rf /)"]}}'
cs apply >/dev/null
check "$(csq 'd["enabledPlugins"].get("b@x")')" "True" "  a map key changed by hand since is not removed with the declaration"
csdecl '{"shared":{},"hosts":{"server":{"enabledPlugins":{"i@x":true}}}}'
cs apply >/dev/null
check "$(csq '"i@x" in d["enabledPlugins"] or "permissions" in d and "deny" in d["permissions"]')" "False" "a hosts.server entry does not go to laptop; a list emptied goes"
CSH=server cs apply >/dev/null
check "$(csq 'd["enabledPlugins"].get("i@x")')" "True" "  and does go to server"
cp "$CSD/cfg/settings.json" "$CSD/before"
csdecl '{"shared":{"env":{"X":"1"}}}'; cs apply 2>/dev/null; check $? 1 "an env key outside ENV_KEYS in the declaration is refused"
csdecl '{"shared":{"env.CLAUDE_CODE_SUBAGENT_MODEL":"sonnet"}}'; cs apply 2>/dev/null; check $? 1 "  so is a dotted env key"
csdecl '{"shared":{"env":{"CLAUDE_CODE_SUBAGENT_MODEL":"sonet"}}}'; cs apply 2>/dev/null; check $? 1 "  so is an ENV_KEYS name with a value it may not take (a typo'd alias)"
csdecl '{"shared":{"additionalDirectories":["/x"]}}'; cs apply 2>/dev/null; check $? 1 "  so is an undeclarable key (additionalDirectories)"
csdecl '{"shared":{"skillOverrides":["x"]}}'; cs apply 2>/dev/null; check $? 1 "  and a key of the wrong type"
csdecl '{"shared":{"permissions.defaultMode":["auto"]}}'; cs apply 2>/dev/null; check $? 1 "  and a scalar given as a list"
cmp -s "$CSD/before" "$CSD/cfg/settings.json"; check $? 0 "  with nothing written"
csdecl '{"shared":{"deniedMcpServers":[{"serverName":"Docs"}]}}'
printf 'not json' > "$CSD/cfg/settings.json"; cs apply 2>/dev/null; check $? 1 "an invalid live file is refused"
check "$(cat "$CSD/cfg/settings.json")" "not json" "  and left as it was"
cp "$CSD/before" "$CSD/cfg/settings.json"
for i in 1 2 3 4 5 6 7; do csdecl "{\"shared\":{\"deniedMcpServers\":[{\"serverName\":\"s$i\"}]}}"; cs apply >/dev/null; touch -t 20260101000$i "$CSD/cfg/"*bak-* 2>/dev/null; sleep 1; done
check "$(ls "$CSD/cfg" | grep -c 'bak-')" 5 "backups pruned to the newest 5"
out=$(cs check)
check "$(echo "$out" | head -1)" "user settings: 1 declared, 0 missing, 1 undeclared" "check counts declared, missing, undeclared"
check "$(echo "$out" | grep -c "claude-settings declare deniedMcpServers '{\"serverName\": \"mine\"}'")" 1 "  and gives the declare line for a live entry nobody declared — shared, for both Macs"
# The key, not the word: the fix lines print this tool's path, and a checkout named *allow* matched.
check "$(echo "$out" | grep -c 'permissions')" 0 "  and ignores permissions.allow while nobody declares it"
# Host parity (the owner, 2026-10-04): mode and allow rules are declared, so Server runs as the laptop.
cp "$CSD/cfg/settings.json" "$CSD/pre-parity"; cp "$CSD/cfg/settings.declared.json" "$CSD/pre-parity-state"
csdecl '{"shared":{"permissions.defaultMode":"auto","permissions.allow":["ExitWorktree"]}}'
check "$(CSH=server cs apply 2>&1 | grep -c 'must keep EnterWorktree')" 1 "a shared allow list without EnterWorktree is refused (worktrees never ask, 2026-10-06)"
check "$(csq 'sorted(d.get("permissions",{}).get("allow",[]))')" "['Bash(ls)']" "  and nothing reaches the live file"
csdecl '{"shared":{"permissions.defaultMode":"auto","permissions.allow":["EnterWorktree"]}}'
CSH=server cs apply >/dev/null
check "$(csq '(d["permissions"]["defaultMode"], d["permissions"]["allow"])')" "('auto', ['Bash(ls)', 'EnterWorktree'])" "parity: shared defaultMode and allow go to server, beside its own allow entry"
check "$(CSH=server cs check | head -1)" "user settings: 2 declared, 0 missing, 1 undeclared" "  check counts the scalar as one and names the machine's own allow entry"
python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["permissions"]["defaultMode"]="default"; json.dump(d,open(p,"w"))' "$CSD/cfg/settings.json"
check "$(CSH=server cs check | grep -c 'missing  *permissions.defaultMode = "auto"')" 1 "  a mode changed by hand shows as missing"
CSH=server cs apply >/dev/null
check "$(csq 'd["permissions"]["defaultMode"]')" "auto" "  and the next apply sets it back"
csdecl '{"shared":{"permissions.defaultMode":"auto"},"hosts":{"server":{"permissions.defaultMode":"acceptEdits"}}}'
CSH=server cs apply >/dev/null
check "$(csq 'd["permissions"]["defaultMode"]')" "acceptEdits" "  a host section's scalar wins over shared"
csdecl '{"shared":{}}'
CSH=server cs apply >/dev/null
check "$(csq '("defaultMode" in d["permissions"], "EnterWorktree" in d["permissions"]["allow"])')" "(False, True)" "  un-declared, the scalar goes; EnterWorktree stays, a required entry is never taken off (review 2026-10-10)"
csdecl '{"shared":{"effortLevel":"high","modelSettings":{"claude-fable-5-1":{"effortLevel":"high"},"claude-opus-5-5":{"effortLevel":"high"}}}}'
python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["modelSettings"]={"claude-opus-5-5":{"effortLevel":"xhigh","maxEffortLevel":"xhigh"}}; d.pop("effortLevel",None); json.dump(d,open(p,"w"))' "$CSD/cfg/settings.json"
CSH=server cs apply >/dev/null
check "$(csq '(d["effortLevel"], d["modelSettings"])')" "('high', {'claude-opus-5-5': {'effortLevel': 'xhigh', 'maxEffortLevel': 'xhigh'}, 'claude-fable-5-1': {'effortLevel': 'high'}})" "effort is seed-only: an absent model is filled, an /effort choice and its siblings kept"
check "$(CSH=server cs check | grep -c '^  missing')" 0 "  and the kept choice is not reported as drift"
csdecl '{"shared":{"permissions.defaultMode":"bypassPermissions"}}'; cs apply 2>/dev/null; check $? 1 "a mode that switches checks off is refused"
csdecl '{"shared":{"permissions.defaultMode":"Auto"}}'; cs apply 2>/dev/null; check $? 1 "  so is a typo"
csdecl '{"shared":{"remoteControlAtStartup":1}}'; cs apply 2>/dev/null; check $? 1 "  and a 1 for a boolean"
check "$(cs declare effortLevel high 2>&1 | grep -c 'must be JSON')" 1 "declare with an unquoted string says how to quote it, no traceback"
cp "$CSD/pre-parity" "$CSD/cfg/settings.json"; cp "$CSD/pre-parity-state" "$CSD/cfg/settings.declared.json"
check "$(cs declare nope '[]' 2>&1 >/dev/null | grep -c 'not declarable')" 1 "declare refuses an undeclarable key before touching git"
chmod 600 "$CSD/cfg/settings.json"; csdecl '{"shared":{"deniedMcpServers":[{"serverName":"m1"}]}}'; cs apply >/dev/null
check "$(fmode "$CSD/cfg/settings.json") $(fmode "$(ls -t "$CSD/cfg/"*bak-* | head -1)")" "600 600" "a write keeps the live file 0600, and its backup is 0600"
check "$(ls "$CSD/cfg" | grep -c '\.tmp')" 0 "  no tmp file left behind"
csdecl '{"shared":{},"hosts":{"Server":{"enabledPlugins":{"i@x":true}}}}'; cs apply 2>/dev/null; check $? 1 "a host outside laptop/server is refused (Server)"
csdecl '{"shared":{},"host":{}}'; cs apply 2>/dev/null; check $? 1 "  so is an unknown top-level key"
check "$(cs declare --host studio deniedMcpServers '[]' 2>&1 | grep -c 'is one of')" 1 "  and declare --host checks the name"
for i in 1 2 3 4 5 6; do csdecl "{\"shared\":{\"deniedMcpServers\":[{\"serverName\":\"p$i\"}]}}"; done
for i in 1 2 3 4 5 6; do cs session-start > "$CSD/par$i" 2>&1 & done; wait
check "$(cat "$CSD"/par* | grep -c Traceback)" 0 "six session starts at once: no traceback"
python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$CSD/cfg/settings.json"; check $? 0 "  and the live file still parses"
rm "$CSD/user.json"
check "$(cs session-start)" '{"user": [], "model": []}' "no declaration: session-start is silent (keeps the suites off the real file)"
# env: only ENV_KEYS (model routing D3, 2026-10-04) — the secrets beside it are never touched or printed
printf '%s\n' '{"env":{"SECRET_TOKEN":"s3cr3t"}}' > "$CSD/cfg/settings.json"
csdecl '{"shared":{"env":{"CLAUDE_CODE_SUBAGENT_MODEL":"sonnet"}}}'; cs apply >/dev/null
check "$(csq 'sorted(d["env"].items())')" "[('CLAUDE_CODE_SUBAGENT_MODEL', 'sonnet'), ('SECRET_TOKEN', 's3cr3t')]" "env: a declared ENV_KEYS name is set beside the machine's secret"
out=$(cs check)
check "$(echo "$out" | head -1)" "user settings: 1 declared, 0 missing, 0 undeclared" "  check counts it and does not list the secret as undeclared"
check "$(echo "$out" | grep -c s3cr3t)" 0 "  nor prints the secret's value"
csdecl '{"shared":{}}'; cs apply >/dev/null
check "$(csq 'sorted(d["env"].items())')" "[('SECRET_TOKEN', 's3cr3t')]" "  un-declared, it goes; the secret stays"
check "$(cs declare env '{"GITHUB_TOKEN":"x"}' 2>&1 >/dev/null | grep -c 'declared only for')" 1 "  declare refuses a secret's name before touching git"
rm "$CSD/user.json"
sgs() { python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"PreToolUse","cwd":"/tmp","tool_name":sys.argv[1],"tool_input":json.loads(sys.argv[2])}))' "$1" "$2" \
  | CLAUDE_CONFIG_DIR="$CSD/cfg" SECRETS_GUARD_DIR="$T/sg/vault/_secrets" python3 "$H/secrets_guard.py" | grep -c 'claude-settings declare'; }
check "$(sgs Edit "{\"file_path\": \"$CSD/cfg/settings.json\"}")" 1 "secrets_guard: Edit of the live settings file is refused, naming the verb"
check "$(sgs Write "{\"file_path\": \"$CSD/cfg/settings.json\"}")" 1 "  Write too"
check "$(sgs Read "{\"file_path\": \"$CSD/cfg/settings.json\"}")" 0 "  Read passes"
check "$(sgs Edit "{\"file_path\": \"$CSD/cfg/other.json\"}")" 0 "  an Edit elsewhere in the config dir passes"
check "$(sgs Bash "{\"command\": \"python3 $CS apply\"}")" 0 "  Bash passes (bootstrap and apply are Bash)"
# sessionpipe's verbs that ungate its hooks or ship past the gate (2026-10-16), denied with or without Drive.
# Searched, not parsed (the review's dozen missed shapes are each a case); sessionpipe has no help flag.
# The second review (2026-10-16) added the rest: update ignores its arguments in 0.5.0 (S1), the shapes that
# ran one yet passed (S2), and among the passes the false denies on this repo's daily commands (S3).
sgp() { python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"PreToolUse","cwd":"/tmp","tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$1" \
  | SECRETS_GUARD_DIR="$T/sg/no-such-vault" python3 "$H/secrets_guard.py" | python3 -c 'import json,sys; t=sys.stdin.read(); print(json.loads(t)["hookSpecificOutput"]["permissionDecision"] if t.strip() else "pass")'; }
for c in "sessionpipe install --backfill 0" "sessionpipe install --help" "sessionpipe install -h" "sessionpipe update" "sessionpipe uninstall" \
         "sessionpipe connect https://herd.example" "sessionpipe backfill --days 30" "sessionpipe control pair https://x" "sessionpipe replay" \
         "sessionpipe sink add herd.example --tier 3" "/opt/homebrew/bin/sessionpipe install" "npx -y sessionpipe@latest install" \
         "pnpm dlx sessionpipe update" "npm exec -- sessionpipe connect" "node /opt/homebrew/lib/node_modules/sessionpipe/dist/cli.js install" \
         "herdctl machine on --folder /srv/projects" "npx -y herdctl@latest machine on" "herdctl sessions install" "herdctl memory install" \
         "cd /tmp && sessionpipe install" "FOO=1 nohup sessionpipe update &" 'bash -c "sessionpipe install"' 'echo "$(sessionpipe install)"' \
         'echo `sessionpipe install`' "if true; then sessionpipe install; fi" "for x in 1; do sessionpipe install; done" "{ sessionpipe install; }" \
         "! sessionpipe install" "timeout 5 sessionpipe install" "caffeinate -i sessionpipe install" "env -i sessionpipe install" \
         "sudo -u x sessionpipe install" "echo x | xargs -n1 sessionpipe install" 'eval "sessionpipe install"' \
         $'cat <<X | bash\nsessionpipe install\nX' "ssh server-claude sessionpipe install" "ssh server-claude 'sessionpipe update'" \
         "npx -p sessionpipe sessionpipe install" "sessionpipe --config /x install" 'bash -c "sessionpipe install" -h' \
         "echo sessionpipe install | bash" $'bash <<\'EOF\'\nsessionpipe install\nEOF' \
         $'python3 - <<\'EOF\'\nimport subprocess\nsubprocess.run([\'sessionpipe\', \'install\'])\nEOF' \
         "python3 -c \"import os; os.system('sessionpipe update')\"" \
         "sessionpipe update off" "ssh server-claude 'sessionpipe update off'" \
         $'cat > notes.md <<EOF\nRun `sessionpipe install`\nEOF' $'git commit -F - <<EOF\nHooks: `sessionpipe install` first\nEOF' \
         $'git commit -m "$(cat <<EOF\nHooks: $(sessionpipe install)\nEOF\n)"' \
         $'cat > n.md <<END-DOC\nRun `sessionpipe update`\nEND-DOC' $'cat > n.md <<EOF.md\nRun `sessionpipe update`\nEOF.md' \
         $'git commit -m "the owner\'s rule: `sessionpipe install` doesn\'t pass"' \
         $'cat <<\'EOF\' | python3\nimport subprocess\nsubprocess.run([\'sessionpipe\',\'install\'])\nEOF' \
         $'echo "import os; os.system(\'sessionpipe install\')" | python3' $'echo "import os; os.system(\'sessionpipe install\')" |& python3 -' \
         $'python3 -c "import subprocess; subprocess.run([\'sessionpipe\', \'install\'])"' \
         $'python3 2>/dev/null <<\'EOF\'\nimport os; os.system(\'sessionpipe install\')\nEOF' \
         $'printf \'sessionpipe install\\n\' | sh' $'printf \'x\\tsessionpipe update\\n\' | bash' "bash <<< 'sessionpipe install'" \
         "cat <(sessionpipe install)" "diff <(sessionpipe status) >(sessionpipe update)" $'cat <<\\EOF | bash\nsessionpipe install\nEOF' \
         $'git -c alias.x=\'!sessionpipe install\' x' $'gh alias set x \'!sessionpipe install\'' \
         $'sed \'s/x/sessionpipe update/e\' f' "sed '1e sessionpipe install' f" \
         'bin/knowledge-commit -m "`sessionpipe update`"' 'python3 bin/memo $(sessionpipe install)' "sess'ion'pipe install"; do
  check "$(sgp "$c")" deny "secrets_guard: \`$(printf '%s' "$c" | tr '\n' ' ')\` is denied"
done
# Passes call sessionpipe_hit itself and want None: an exception in the hook fails open, and must not read as a pass.
sgh() { python3 -c 'import importlib.util as u,sys; s=u.spec_from_file_location("sg",sys.argv[1]); m=u.module_from_spec(s); s.loader.exec_module(m); print(m.sessionpipe_hit(sys.argv[2]))' "$H/secrets_guard.py" "$1" 2>&1; }
for c in "sessionpipe" "sessionpipe status" "sessionpipe doctor" "sessionpipe wait --session claude-code:x" "sessionpipe control status" \
         "sessionpipe forget claude-code x" "sessionpipe sink list" "herdctl machine status" \
         "herdctl sessions list --limit 100" "herdctl machine on --help" "herdctl sessions install -h" \
         'grep -n "sessionpipe install" bin/sheep' "rg 'sessionpipe install' hooks" "echo sessionpipe install" \
         'git commit -m "never sessionpipe install"' $'git commit -q -F - <<\'EOF\'\nHooks: deny sessionpipe install\nEOF' \
         $'cat > notes.md <<\'EOF\'\nrun sessionpipe install, then sheep gate\nEOF' "sed -n '/sessionpipe install/p' f" \
         "git log --grep 'sessionpipe install'" "gh pr view 3 | grep 'sessionpipe install'" "python3 bin/sheep gate --dry-run" \
         'git -C /srv/x/wt commit -m "Hooks: deny sessionpipe install"' "git -C x log --grep 'sessionpipe install'" \
         "git --git-dir=/x/.git --work-tree /x log --grep 'sessionpipe install'" \
         'gh pr create --title "Hooks: deny sessionpipe install" --body "sessionpipe update ungates privy"' \
         $'gh pr create --title x --body "$(cat <<\'EOF\'\nDenies sessionpipe install and `sessionpipe update`.\nEOF\n)"' \
         'python3 tools/hooks/bulletin.py --post "sheep" "sessionpipe update ungates privy"' \
         'bin/knowledge-commit notes --in /x -m "Hooks: sessionpipe update off is denied"' 'python3 bin/memo line docs/x.md "sessionpipe install"' \
         $'python3 bin/x.py <<\'EOF\'\nsessionpipe install\nEOF' \
         $'python3 -c "print(\'/opt/homebrew/lib/node_modules/sessionpipe/dist/commands/install.js\')"' \
         $'python3 - <<\'EOF\'\nfor l in open(\'f\'):\n    if "sessionpipe" in l and "install" in l:\n        print(l)\nEOF' \
         "sed -i '' 's/sessionpipe install/sessionpipe install --backfill 0/' docs/sheep.md" \
         $'cat > n.md <<"EOF"\nRun `sessionpipe install`\nEOF' $'cat > n.md <<\\EOF\nRun `sessionpipe install`\nEOF' \
         'git commit -m "use \`sessionpipe install\` by hand"' $'git commit -m "the owner\'s rule: sessionpipe install by hand"' \
         "git log --grep 'sessionpipe install' | python3 bin/parse.py"; do
  check "$(sgh "$c")" None "  \`$(printf '%s' "$c" | tr '\n' ' ')\` passes"
done
for c in "sessionpipe status" 'git -C /x commit -m "Hooks: deny sessionpipe install"' "sed -n '/sessionpipe install/p' f"; do
  check "$(sgp "$c")" pass "  and through the hook: \`$c\` passes"
done
check "$(python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"PreToolUse","cwd":"/tmp","tool_name":"Bash","tool_input":{"command":"sessionpipe install"}}))' | SECRETS_GUARD_DIR="$T/sg/no" python3 "$H/secrets_guard.py" | python3 -c 'import json,sys; r=json.load(sys.stdin)["hookSpecificOutput"]["permissionDecisionReason"]; print("sheep gate" in r, "his " in r, "no help flag" in r, "--body-file" in r, "another shape" in r)')" \
  "True False True True False" "  the reason names keel's sheep gate, says sessionpipe has no help flag, points at a file for text, and no pronoun for the owner"

echo "account_guard: a prompt in a repo the session's account denies (work-account E4)"
GH="$T/guardhome"; mkdir -p "$GH/projects/cv" "$GH/.claude-work" "$GH/.claude"
for r in privy app2; do git init -q "$GH/projects/$r"; done
mkdir -p "$GH/projects/privy/memory"
printf '{"accounts":[{"label":"work","home":"~/.claude-work","repos":{"deny":["privy","cv"]}},{"label":"main","home":"~/.claude","primary":true}]}' > "$T/guard-accounts.json"
ag() { echo "{\"session_id\":\"g1\",\"cwd\":\"$2\"}" | HOME="$GH" ACCOUNTS_FILE="$T/guard-accounts.json" CLAUDE_CONFIG_DIR="$1" python3 "$H/account_guard.py"; }
check "$(ag "$GH/.claude-work" "$GH/projects/privy" | python3 -c 'import json,sys;d=json.load(sys.stdin);print(d["decision"])')" "block" "work in privy: the prompt is blocked"
check "$(ag "$GH/.claude-work" "$GH/projects/privy/memory" | grep -c 'privy is off work (accounts.json deny list): open it in the default VS Code profile')" 1 "  …from a folder inside it too, with the way out"
check "$(ag "$GH/.claude-work" "$GH/projects/cv" | grep -c 'cv is off work')" 1 "work in cv (no git repo): blocked by path"
check "$(ag "$GH/.claude-work" "$GH/projects/app2")" "" "work in app2: passes, silent"
check "$(ag "$GH/.claude-work" "$GH/projects" | grep -c '"block"')" "1" "work in ~/projects itself: blocked, since it holds privy (2026-10-18: ~/.claude/CLAUDE.md's imports load there)"
check "$(echo "{\"cwd\":\"$GH/projects/privy\"}" | env -u CLAUDE_CONFIG_DIR HOME="$GH" ACCOUNTS_FILE="$T/guard-accounts.json" python3 "$H/account_guard.py")" "" "no CLAUDE_CONFIG_DIR (the default dir): nothing happens"
check "$(echo "{\"cwd\":\"$GH/projects\"}" | CLAUDE_PROJECT_DIR="$GH/projects/app2" HOME="$GH" ACCOUNTS_FILE="$T/guard-accounts.json" CLAUDE_CONFIG_DIR="$GH/.claude-work" python3 "$H/account_guard.py")" "" \
  "a session started in app2 whose shell moved to ~/projects: passes — \"holds\" binds the start only (2026-10-22)"
check "$(echo "{\"cwd\":\"$GH/projects/privy\"}" | CLAUDE_PROJECT_DIR="$GH/projects/app2" HOME="$GH" ACCOUNTS_FILE="$T/guard-accounts.json" CLAUDE_CONFIG_DIR="$GH/.claude-work" python3 "$H/account_guard.py" | grep -c 'privy is off work')" "1" \
  "  one whose shell moved into a denied repo: still blocked"
check "$(echo "{\"cwd\":\"$GH/projects/app2\"}" | CLAUDE_PROJECT_DIR="$GH/projects" HOME="$GH" ACCOUNTS_FILE="$T/guard-accounts.json" CLAUDE_CONFIG_DIR="$GH/.claude-work" python3 "$H/account_guard.py" | grep -c '"block"')" "1" \
  "  one started in ~/projects is blocked wherever its shell went"
check "$(ag "$GH/.claude-stray" "$GH/projects/privy")" "" "a dir with no row in the registry: nothing happens"
check "$(echo 'not json' | HOME="$GH" CLAUDE_CONFIG_DIR="$GH/.claude-work" ACCOUNTS_FILE="$T/guard-accounts.json" python3 "$H/account_guard.py" >/dev/null 2>&1; echo "rc=$?")" "rc=0" "bad input: exit 0"
check "$(echo "{\"cwd\":\"$GH/projects/privy\"}" | HOME="$GH" ACCOUNTS_FILE=/nonexistent CLAUDE_CONFIG_DIR="$GH/.claude-work" python3 "$H/account_guard.py"; echo "rc=$?")" "rc=0" "no registry: silent, exit 0"
printf '{"accounts": [\n' > "$T/guard-truncated.json"
check "$(echo "{\"cwd\":\"$GH/projects/app2\"}" | HOME="$GH" ACCOUNTS_FILE="$T/guard-truncated.json" CLAUDE_CONFIG_DIR="$GH/.claude-work" python3 "$H/account_guard.py"; echo "rc=$?")" "rc=0" "a malformed registry (a merge in progress): silent, never a block (review 2026-10-06)"
echo "account_guard: a tenant's repo, on every login but the tenant's (2026-10-20)"
mkdir -p "$GH/.claude-lab"; git init -q "$GH/projects/acme-one"
printf '{"accounts":[{"label":"work","home":"~/.claude-work","repos":{"deny":["privy","cv"]}},{"label":"lab","home":"~/.claude-lab","tenant":"acme"},{"label":"main","home":"~/.claude","primary":true}],"tenants":{"acme":{"repos":["acme-*"]}}}' > "$T/guard-tenants.json"
agt() { echo "{\"session_id\":\"g1\",\"cwd\":\"$2\"}" | if [ -n "$1" ]; then HOME="$GH" ACCOUNTS_FILE="$T/guard-tenants.json" CLAUDE_CONFIG_DIR="$1" python3 "$H/account_guard.py"; else env -u CLAUDE_CONFIG_DIR HOME="$GH" ACCOUNTS_FILE="$T/guard-tenants.json" python3 "$H/account_guard.py"; fi; }
out=$(agt "" "$GH/projects/acme-one")
check "$(echo "$out" | python3 -c 'import json,sys;print(json.load(sys.stdin)["decision"])')" "block" "the default dir in a tenant's repo: blocked, though it denies nothing else"
check "$(echo "$out" | python3 -c 'import json,sys;print(json.load(sys.stdin)["reason"])' | grep -c "acme-one is off main: it is acme's, which runs on lab only (accounts.json tenants) — open it in VS Code profile lab")" 1 "  the reason names the tenant's login and its way in"
check "$(echo "$out" | grep -c 'open it in the default VS Code profile')" 0 "  …and not the deny list's way out"
check "$(agt "" "$GH/projects/app2")" "" "the default dir elsewhere: silent"
check "$(agt "" "$GH/projects/privy")" "" "the default dir in a repo another row denies: silent, as before"
check "$(agt "" "$GH/projects")" "" "the default dir in ~/projects, which holds the tenant's repo: silent (holding loads nothing of it)"
check "$(agt "$GH/.claude-lab" "$GH/projects/acme-one")" "" "the tenant's own login in its repo: silent"
check "$(agt "$GH/.claude-lab" "$GH/projects/app2")" "" "  …and in another repo (its own deny list says where else)"
check "$(agt "$GH/.claude-work" "$GH/projects/acme-one" | grep -c "acme-one is off work: it is acme's")" 1 "another secondary in the tenant's repo: blocked"
check "$(echo "{\"cwd\":\"$GH/projects/acme-one\"}" | env -u CLAUDE_CONFIG_DIR CLAUDE_PROJECT_DIR="$GH/projects/app2" HOME="$GH" ACCOUNTS_FILE="$T/guard-tenants.json" python3 "$H/account_guard.py" | grep -c "acme-one is off main: it is acme's")" 1 \
  "the default dir started in app2, its shell moved into the tenant's repo: still blocked (tenancy follows the shell, 2026-10-22)"
check "$(echo "{\"cwd\":\"$GH/projects/acme-one\"}" | CLAUDE_PROJECT_DIR="$GH/projects/app2" HOME="$GH" ACCOUNTS_FILE="$T/guard-tenants.json" CLAUDE_CONFIG_DIR="$GH/.claude-work" python3 "$H/account_guard.py" | grep -c "acme-one is off work: it is acme's")" 1 \
  "  a secondary likewise"
mkdir -p "$GH/projects/clients"; git init -q "$GH/projects/clients/x-acme"
sed 's#"acme-\*"#"*-acme"#' "$T/guard-tenants.json" > "$T/guard-tenants2.json"
out=$(echo "{\"session_id\":\"g1\",\"cwd\":\"$GH/projects/clients/x-acme\"}" | env -u CLAUDE_CONFIG_DIR HOME="$GH" ACCOUNTS_FILE="$T/guard-tenants2.json" python3 "$H/account_guard.py")
check "$(echo "$out" | grep -c '"block"')" 1 "a glob whose * spans / (\"*-acme\" takes clients/x-acme): the default dir is asked, and blocked (review 2026-10-21)"
echo "account_guard: the tenants file, its logins named there (2026-10-22)"
printf '{"accounts":[{"label":"work","home":"~/.claude-work","repos":{"deny":["privy","cv"]}},{"label":"lab","home":"~/.claude-lab"},{"label":"main","home":"~/.claude","primary":true}]}' > "$T/guard-rows.json"
printf '{"acme":{"repos":["acme-*"],"logins":["lab"]}}' > "$T/guard-tenants-file.json"
agf() { echo "{\"session_id\":\"g1\",\"cwd\":\"$2\"}" | if [ -n "$1" ]; then HOME="$GH" TENANTS_FILE="$T/guard-tenants-file.json" ACCOUNTS_FILE="$T/guard-rows.json" CLAUDE_CONFIG_DIR="$1" python3 "$H/account_guard.py"; else env -u CLAUDE_CONFIG_DIR HOME="$GH" TENANTS_FILE="$T/guard-tenants-file.json" ACCOUNTS_FILE="$T/guard-rows.json" python3 "$H/account_guard.py"; fi; }
out=$(agf "" "$GH/projects/acme-one")
check "$(echo "$out" | python3 -c 'import json,sys;print(json.load(sys.stdin)["reason"])' | grep -c "acme-one is off main: it is acme's, which runs on lab only (guard-tenants-file.json) — open it in VS Code profile lab")" 1 "the default dir in the file's tenant's repo: blocked, with the way in"
check "$(agf "$GH/.claude-lab" "$GH/projects/acme-one")" "" "the login the file names, in its repo: silent"
check "$(agf "" "$GH/projects/app2")" "" "the default dir elsewhere: silent"
ln -s "$T/nowhere.json" "$T/guard-tenants-gone.json"
out=$(echo "{\"cwd\":\"$GH/projects/acme-one\"}" | env -u CLAUDE_CONFIG_DIR HOME="$GH" TENANTS_FILE="$T/guard-tenants-gone.json" ACCOUNTS_FILE="$T/guard-tenants.json" python3 "$H/account_guard.py" 2>"$T/ag-err"; echo "rc=$?")
check "$(echo "$out" | grep -c '"block"') $(echo "$out" | tail -1)" "1 rc=0" "a tenants link that reads nothing, no copy: tenancy closed, the default dir blocked (S7b; the registry's tenants not read instead)"
check "$(echo "$out" | head -1 | grep -c 'acme-one is off main: tenancy does not read')" 1 "  …the closed line, passed on as it is"
check "$(grep -c 'tenancy closed' "$T/ag-err")" 1 "  …saying so on stderr"
out=$(echo "{\"cwd\":\"$GH/projects/app2\"}" | env -u CLAUDE_CONFIG_DIR HOME="$GH" TENANTS_FILE="$T/guard-tenants-gone.json" ACCOUNTS_FILE="$T/guard-tenants.json" python3 "$H/account_guard.py" 2>/dev/null)
check "$(echo "$out" | grep -c '"block"')" 1 "  …in a repo no tenant named too: every repo is closed until it reads"
cp "$T/guard-tenants-file.json" "$T/guard-drive.json"; ln -s "$T/guard-drive.json" "$T/guard-tenants-link.json"
agl() { echo "{\"session_id\":\"g1\",\"cwd\":\"$2\"}" | if [ -n "$1" ]; then HOME="$GH" TENANTS_FILE="$T/guard-tenants-link.json" ACCOUNTS_FILE="$T/guard-rows.json" CLAUDE_CONFIG_DIR="$1" python3 "$H/account_guard.py"; else env -u CLAUDE_CONFIG_DIR HOME="$GH" TENANTS_FILE="$T/guard-tenants-link.json" ACCOUNTS_FILE="$T/guard-rows.json" python3 "$H/account_guard.py"; fi; }
check "$(agl "$GH/.claude-work" "$GH/projects/acme-one" | grep -c '"block"')" 1 "a tenants link that reads: another secondary blocked (and bin/account keeps a copy)"
rm "$T/guard-drive.json"
check "$(agl "$GH/.claude-work" "$GH/projects/acme-one" | grep -c "acme-one is off work: it is acme's")" 1 "its drive away: the last good copy holds, the secondary still blocked (review 2026-10-22)"
check "$(agl "" "$GH/projects/acme-one" | grep -c '"block"')" 1 "  …and the default dir too"
echo "account_guard: the copy before the link (S4: the link points into a drive an ungranted process blocks on)"
mkdir -p "$T/gdrive"; echo '{}' > "$T/gdrive/tenants.json"; ln -s "$T/gdrive/tenants.json" "$T/guard-tenants-s4.json"
printf '{"acme":{"repos":["acme-*"],"logins":["lab"]}}' > "$T/.guard-tenants-s4.json.last"
ags() { echo "{\"session_id\":\"g1\",\"cwd\":\"$1\"}" | env -u CLAUDE_CONFIG_DIR HOME="$GH" TENANTS_FILE="$T/guard-tenants-s4.json" ACCOUNTS_FILE="$T/guard-rows.json" python3 "$H/account_guard.py"; }
check "$(ags "$GH/projects/acme-one" | grep -c "acme-one is off main: it is acme's")" 1 "the drive's file says {} and the copy names acme: the copy answers, the default dir blocked"
check "$(REGATTA_CLAUDE_HOST=1 ags "$GH/projects/acme-one")" "" "under claude-host bin/account reads the link ({}, tenancy off): silent"
check "$(cat "$T/.guard-tenants-s4.json.last")" "{}" "  …and its read refreshed the copy the hook reads"
check "$(ags "$GH/projects/acme-one")" "" "outside claude-host again: the refreshed copy, silent"
printf '{}' > "$T/guard-plain.json"; printf '{"acme":{"repos":["acme-*"],"logins":["lab"]}}' > "$T/.guard-plain.json.last"
check "$(echo "{\"session_id\":\"g1\",\"cwd\":\"$GH/projects/acme-one\"}" | env -u CLAUDE_CONFIG_DIR HOME="$GH" TENANTS_FILE="$T/guard-plain.json" ACCOUNTS_FILE="$T/guard-rows.json" python3 "$H/account_guard.py")" "" \
  "a plain tenants file is read before its copy: {} ends tenancy at once (S4 finish review)"
printf '{"acme":{"repos":["acme-*"],"logins":["lab"]}}' > "$T/guard-plain.json"; printf '{}' > "$T/.guard-plain.json.last"
check "$(echo "{\"session_id\":\"g1\",\"cwd\":\"$GH/projects/acme-one\"}" | env -u CLAUDE_CONFIG_DIR HOME="$GH" TENANTS_FILE="$T/guard-plain.json" ACCOUNTS_FILE="$T/guard-rows.json" python3 "$H/account_guard.py" | grep -c '"block"')" 1 \
  "  …and a plain file naming a tenant blocks the default dir though its copy says {} (never the copy's open door)"
out=$(echo "{\"cwd\":\"$GH/projects/acme-one\"}" | CLAUDE_PROJECT_DIR="$GH/projects/app2" HOME="$GH" TENANTS_FILE="$T/guard-tenants-file.json" ACCOUNTS_FILE="$T/guard-rows.json" CLAUDE_CONFIG_DIR="$GH/.claude-work" python3 "$H/account_guard.py")
check "$(echo "$out" | grep -c "acme-one is off work: it is acme's, which runs on lab only")" 1 "a secondary whose shell moved into the file's tenant's repo: blocked with the tenant's way in…"
check "$(echo "$out" | grep -c 'open it in the default VS Code profile')" 0 "  …not the deny list's, which names a login tenancy refuses (review 2026-10-23)"
# A config dir the overlay installed (its regatta/overlay marker) without the private values: a core from B2b on
# refuses to load, bin/account cannot answer, and the deny hook fails closed. Judged by what the
# core does (config_problems), so a core from before B2b skips the case.
if python3 -c "import sys; sys.path.insert(0, '$R/modules/regatta/hooks'); import common; sys.exit(not hasattr(common, 'config_problems'))" 2>/dev/null; then
  AGC="$T/ag-cfg"; mkdir -p "$AGC/regatta"
  python3 -c "import sys; sys.path.insert(0, '$R/modules/regatta/hooks'); import common; print(common.regatta_root())" > "$AGC/home"; echo "$C" > "$AGC/regatta/overlay"
  out=$(echo "{\"cwd\":\"$GH/projects/app2\"}" | HOME="$GH" REGATTA_CONFIG="$AGC" ACCOUNTS_FILE="$T/guard-accounts.json" CLAUDE_CONFIG_DIR="$GH/.claude-work" python3 "$H/account_guard.py"; echo "rc=$?")
  check "$(echo "$out" | head -1 | python3 -c 'import json,sys; print(json.load(sys.stdin)["decision"])' 2>&1) $(echo "$out" | tail -1)" "block rc=0" \
    "the core refusing an incomplete config: a prompt anywhere is blocked, exit 0 (fails closed)"
  check "$(echo "$out" | head -1 | grep -c 'regatta/owner missing.*bootstrap.sh --config')" 1 "  the reason names the missing keys and the repair"
  out=$(echo "{\"cwd\":\"$GH/projects/acme-one\"}" | env -u CLAUDE_CONFIG_DIR HOME="$GH" REGATTA_CONFIG="$AGC" ACCOUNTS_FILE="$T/guard-tenants.json" python3 "$H/account_guard.py" 2>"$T/ag-err"; echo "rc=$?")
  check "$out" "rc=0" "…but on the default dir, in a tenant's repo, it fails open: the seat a broken core is repaired from (review 2026-10-20)"
  check "$(grep -c 'tenancy unchecked on the default dir' "$T/ag-err")" 1 "  …saying so on stderr"
else
  echo "  skip the core predates B2b: an incomplete config dir is no import error there"
fi

echo "design_route: a new Claude Design artifact is made on the primary, and shared as made (2026-10-10)"
DR="$T/design"; mkdir -p "$DR/.claude-work" "$DR/.claude"
printf '{"accounts":[{"label":"work","home":"%s/.claude-work"},{"label":"main","home":"%s/.claude","primary":true}]}' "$DR" "$DR" > "$DR/accounts.json"
printf '{"logins":{},"share":{"design":[{"email":"pat@example.com","access":"edit"},{"email":"me@example.org"}]}}' > "$DR/logins.json"
DTYPE=https://claude.ai/artifact/QKN21svewxgyPb6SYRqWnd
DPUB=$(printf '{"title":"x","type_url":"%s"}' "$DTYPE")   # a publish from the Design type
DUPD=$(printf '{"url":"https://claude.ai/artifact/abc","type_url":"%s","file_path":"x"}' "$DTYPE")   # an update by url
dr() {  # EVENT TOOL_INPUT_JSON [CONFIG_DIR|-] [TOOL_RESPONSE_JSON]
  local dir="${3:--}"
  python3 -c 'import json,sys; print(json.dumps({"hook_event_name": sys.argv[1], "tool_name": "Artifact", "tool_input": json.loads(sys.argv[2]), "tool_response": json.loads(sys.argv[3])}))' "$1" "$2" "${4:-null}" \
    | if [ "$dir" = - ]; then env -u CLAUDE_CONFIG_DIR HOME="$DR" ACCOUNTS_FILE="$DR/accounts.json" ACCOUNT_LOGINS="${DRL:-$DR/logins.json}" python3 "$H/design_route.py"
      else HOME="$DR" CLAUDE_CONFIG_DIR="$dir" ACCOUNTS_FILE="$DR/accounts.json" ACCOUNT_LOGINS="${DRL:-$DR/logins.json}" python3 "$H/design_route.py"; fi
}
dec() { python3 -c 'import json,sys; t=sys.stdin.read(); print(json.loads(t)["hookSpecificOutput"]["permissionDecision"] if t.strip() else "")'; }
check "$(dr PreToolUse '{"action":"quickstart","intent":"design"}' "$DR/.claude-work" | dec)" "deny" "work, quickstart intent=design: denied"
check "$(dr PreToolUse '{"action":"quickstart","intent":"design"}' "$DR/.claude-work" | grep -c 'branch it printed> --repo <that repo> --on server --at @$(( $(date +%s) + 120 )) --fallback here --account bound')" 1 "  the reason is the hand-off: a seed, then dispatch to Server, bound, falling back here"
check "$(dr PreToolUse "$DPUB" "$DR/.claude-work" | dec)" "deny" "work, a publish from the Design type (no action): denied"
check "$(dr PreToolUse '{"type_url":"https://claude.ai/artifact/5M7UeXXcx16TP3vzVFNDzd","title":"x"}' "$DR/.claude-work" | grep -c 'A new Design System artifact')" 1 "  the Design System type too, named"
check "$(dr PreToolUse '{"action":"quickstart","intent":"design"}')" "" "the default dir (main, the primary): passes, wherever it runs"
check "$(dr PreToolUse '{"action":"quickstart","intent":"design"}' "$DR/.claude")" "" "  …and with CLAUDE_CONFIG_DIR set to the primary's dir"
check "$(dr PreToolUse '{"action":"quickstart","intent":"slides"}' "$DR/.claude-work")" "" "work, quickstart intent=slides: passes"
check "$(dr PreToolUse '{"action":"list","type":"Design"}' "$DR/.claude-work")" "" "work, listing the Design type: passes"
check "$(dr PreToolUse "$DUPD" "$DR/.claude-work")" "" "work, an update by url: passes"
check "$(dr PreToolUse '{"type_url":"https://claude.ai/artifact/8jTsAFQMFDb2oA8MsPJ2eL","title":"x"}' "$DR/.claude-work")" "" "work, a publish from another type (Slides): passes"
check "$(dr PreToolUse '{"action":"quickstart","intent":"design"}' "$DR/.claude-stray")" "" "a dir with no row in the registry: passes (fails open)"
check "$(echo '{"hook_event_name":"PreToolUse","tool_name":"Artifact","tool_input":{"action":"quickstart","intent":"design"}}' | HOME="$DR" CLAUDE_CONFIG_DIR="$DR/.claude-work" ACCOUNTS_FILE=/nonexistent python3 "$H/design_route.py"; echo "rc=$?")" "rc=0" "no registry: silent, exit 0"
check "$(echo 'not json' | python3 "$H/design_route.py" 2>/dev/null; echo "rc=$?")" "rc=0" "bad input: exit 0"
ctx() { python3 -c 'import json,sys; t=sys.stdin.read(); print(json.loads(t)["hookSpecificOutput"]["additionalContext"] if t.strip() else "")'; }
OUT=$(dr PostToolUse "$DPUB" - '"Created https://claude.ai/artifact/NewOne123 from type https://claude.ai/artifact/QKN21svewxgyPb6SYRqWnd"' | ctx)
check "$(printf '%s' "$OUT" | grep -c 'Share https://claude.ai/artifact/NewOne123 now')" 1 "primary, after a publish from the Design type: share the new artifact, not the type"
check "$(printf '%s' "$OUT" | grep -c 'pat@example.com (edit), me@example.org (view)')" 1 "  with everyone in share.design, at their access (view when unnamed)"
check "$(printf '%s' "$OUT" | grep -c "Owner's step")" 1 "  and Chrome missing ends as the owner's step"
check "$(dr PostToolUse "$DPUB" "$DR/.claude-work" '"Created https://claude.ai/artifact/NewOne123"')" "" "a secondary's publish (Pre would have denied it): no share line"
check "$(dr PostToolUse '{"action":"quickstart","intent":"design"}' -)" "" "primary, after a quickstart: nothing to share yet"
OUT=$(dr PostToolUse "$DPUB" - '"Design system files: https://claude.ai/artifact/DSfile99 ... Created a new Artifact at https://claude.ai/artifact/Made42 ..."' | ctx)
check "$(printf '%s' "$OUT" | grep -c 'Share https://claude.ai/artifact/Made42 now')" 1 "  the 'Created a new Artifact at' link wins over any other link in the result"
check "$(DRL="$DR/missing.json" dr PostToolUse "$DPUB" - '"Created a new Artifact at https://claude.ai/artifact/Made42"' | ctx | grep -c 'could not be read')" 1 "an unreadable share list is said, never taken as an empty one"
printf '{"logins":{}}' > "$DR/logins.json"
check "$(dr PostToolUse "$DPUB" - '{"url":"https://claude.ai/artifact/NewOne123"}' | ctx | grep -c 'is shared with nobody yet')" 1 "no share.design list: the reply says it is shared with nobody"
mkdir -p "$DR/drive"; printf '{"logins":{},"share":{"design":[{"email":"link@example.com"}]}}' > "$DR/drive/logins.json"; ln -s "$DR/drive/logins.json" "$DR/logins-link.json"
printf '{"logins":{},"share":{"design":[{"email":"copy@example.com"}]}}' > "$DR/.logins-link.json.last"
OUT=$(DRL="$DR/logins-link.json" dr PostToolUse "$DPUB" - '"Created a new Artifact at https://claude.ai/artifact/Made42"' | ctx)
check "$(printf '%s' "$OUT" | grep -c 'copy@example.com (view)') $(printf '%s' "$OUT" | grep -c 'link@example.com')" "1 0" "the share list from the logins file's local copy, never its drive link while the copy reads (S4)"
rm "$DR/.logins-link.json.last"
check "$(DRL="$DR/logins-link.json" dr PostToolUse "$DPUB" - '"Created a new Artifact at https://claude.ai/artifact/Made42"' | ctx | grep -c 'link@example.com (view)')" 1 "  no copy: the link, as before"
echo "tool_path: a parent's bare PATH gets the host's tool dirs, appended (lessons/claude-code.md, 2026-10-12)"
TP="$T/tp"; mkdir -p "$TP/brew/bin" "$TP/local/bin"; printf '#!/bin/sh\necho brewtool\n' > "$TP/brew/bin/tptool"; chmod +x "$TP/brew/bin/tptool"
tp() { echo '{"hook_event_name":"SessionStart"}' | env -i HOME="$T" PATH="$1" CLAUDE_ENV_FILE="$TP/env.sh" TOOL_PATH_DIRS="$TP/brew/bin:$TP/nope/bin:$TP/local/bin" /usr/bin/python3 "$H/tool_path.py"; }
rm -f "$TP/env.sh"; tp /usr/bin:/bin; check "$?" "0" "  exits 0"
check "$(env -i PATH=/usr/bin:/bin sh -c ". '$TP/env.sh'; echo \$PATH")" "/usr/bin:/bin:$TP/brew/bin:$TP/local/bin" "  the existing dirs are appended after the parent's, the missing one skipped"
check "$(env -i PATH=/usr/bin:/bin sh -c ". '$TP/env.sh'; tptool")" "brewtool" "  so a tool in the brew dir is found"
check "$(env -i PATH=/usr/bin:/bin sh -c ". '$TP/env.sh'; . '$TP/env.sh'; echo \$PATH")" "/usr/bin:/bin:$TP/brew/bin:$TP/local/bin" "  sourcing it twice (a continued session) adds nothing twice"
command -v zsh >/dev/null && check "$(env -i PATH=/usr/bin:/bin zsh -c ". '$TP/env.sh'; . '$TP/env.sh'; echo \$PATH")" "/usr/bin:/bin:$TP/brew/bin:$TP/local/bin" "  zsh (Claude Code's shell on a Mac) reads it alike, twice"
rm -f "$TP/env.sh"; check "$(tp /usr/bin:/bin)" "" "  prints nothing (SessionStart stdout would go into the context)"
mkdir -p "$TP/we\"ird/bin"; rm -f "$TP/env.sh"
echo '{}' | env -i HOME="$T" PATH=/usr/bin:/bin CLAUDE_ENV_FILE="$TP/env.sh" TOOL_PATH_DIRS="$TP/we\"ird/bin:$TP/brew/bin" /usr/bin/python3 "$H/tool_path.py"
check "$(env -i PATH=/usr/bin:/bin sh -c ". '$TP/env.sh'; echo \$PATH")" "/usr/bin:/bin:$TP/brew/bin" "  a dir a shell would misread is skipped, the rest still added"
rm -f "$TP/env.sh"; tp "$TP/local/bin:/usr/bin:/bin:$TP/brew/bin"; check "$([ -e "$TP/env.sh" ] && echo written || echo none)" "none" "  a PATH that has them all: nothing written"
check "$(echo '{}' | env -i PATH=/usr/bin:/bin /usr/bin/python3 "$H/tool_path.py"; echo $?)" "0" "  no CLAUDE_ENV_FILE (an old Claude Code): silent, exit 0"
check "$(echo '{}' | env -i PATH=/usr/bin:/bin CLAUDE_ENV_FILE=/no/such/dir/env.sh TOOL_PATH_DIRS="$TP/brew/bin" /usr/bin/python3 "$H/tool_path.py" 2>&1; echo $?)" "0" "  an unwritable env file: silent, exit 0"


echo "claude-settings without atlas: declare refuses, naming the hand route (G17)"
# From a scratch checkout of the core and lighthouse alone: atlas sits in this repo since B10, so
# the checkout's tool() would find its knowledge-commit (the "peer absent" trap, AGENTS.md).
mkdir -p "$T/rg/.claude-plugin" "$T/rg/modules"; cp "$R/.claude-plugin/marketplace.json" "$T/rg/.claude-plugin/"
cp -R "$R/modules/regatta" "$R/modules/lighthouse" "$T/rg/modules/"
printf '%s\n' '{"shared":{}}' > "$CSD/user.json"
check "$(CS="$T/rg/modules/lighthouse/bin/claude-settings" cs declare deniedMcpServers '{"serverName":"x"}' 2>&1 | grep -c "atlas's knowledge-commit is not installed")" 1 "  no knowledge-commit: a refusal, no traceback"
rm "$CSD/user.json"

echo "design_route with no core: a deny hook fails closed (C4)"
NC="$T/nocore"; mkdir -p "$NC" "$T/lonely/hooks" "$T/lonely/lib"
cp "$H/design_route.py" "$T/lonely/hooks/"; cp "$C/lib/find_core.py" "$T/lonely/lib/"
printf '{"accounts": []}\n' > "$T/nc-acc.json"
nch() { printf '%s' "$1" | env -u REGATTA_HOME REGATTA_CONFIG="$NC" ACCOUNTS_FILE="$T/nc-acc.json" "${@:2}" python3 "$T/lonely/hooks/design_route.py" 2>"$T/nc.err"; echo "rc=$?"; }
out=$(nch '{"hook_event_name":"PreToolUse","tool_name":"Artifact","tool_input":{"action":"quickstart","intent":"design"}}')
check "$(echo "$out" | head -1 | python3 -c 'import json,sys; print(json.load(sys.stdin)["hookSpecificOutput"]["permissionDecision"])' 2>/dev/null)" "deny" "a design start with no core: denied"
check "$(echo "$out" | head -1 | grep -c 'regatta core not found')" 1 "  naming the fix"
check "$(echo "$out" | tail -1)" "rc=0" "  exit 0"
check "$(grep -c 'design_route: regatta core not found' "$T/nc.err")" 1 "  the one line on stderr"
check "$(nch '{"hook_event_name":"PostToolUse","tool_name":"Artifact","tool_input":{"action":"quickstart","intent":"design"}}')" "rc=0" "  after the call: no output, exit 0"
mkdir -p "$T/badcore/modules/regatta/hooks"; printf 'def (\n' > "$T/badcore/modules/regatta/hooks/common.py"
out=$(printf '{"hook_event_name":"PreToolUse","tool_name":"Artifact","tool_input":{"action":"quickstart","intent":"design"}}' \
  | REGATTA_HOME="$T/badcore" REGATTA_CONFIG="$NC" ACCOUNTS_FILE="$T/nc-acc.json" python3 "$T/lonely/hooks/design_route.py" 2>/dev/null)
check "$(echo "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["hookSpecificOutput"]["permissionDecision"])' 2>/dev/null)" "deny" "  a broken core (a syntax error): denied too"

echo "the overlay installed, lighthouse's keys not written: the deny hooks fail closed (B9 review)"
HM="$HOME"; AGK="$T/ag-keys"; mkdir -p "$AGK/regatta" "$AGK/lighthouse"
python3 -c "import sys; sys.path.insert(0, '$R/modules/regatta/hooks'); import common; print(common.regatta_root())" > "$AGK/home"; echo "$T/overlay" > "$AGK/regatta/overlay"
echo Owner > "$AGK/regatta/owner"; echo privy > "$AGK/regatta/guarded"; echo privy > "$AGK/regatta/orca-deny"
echo "$T/usage" > "$AGK/regatta/log-dir"; echo "$HM/projects" > "$AGK/regatta/projects"
out=$(echo "{\"cwd\":\"$HM/projects/app2\"}" | env -u ACCOUNTS_FILE REGATTA_CONFIG="$AGK" CLAUDE_CONFIG_DIR="$HM/.claude-work" python3 "$H/account_guard.py")
check "$(echo "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["decision"])' 2>&1)" "block" "account_guard, no lighthouse/accounts.json: a prompt is blocked"
check "$(echo "$out" | grep -c 'lighthouse/accounts.json missing')" 1 "  naming the key"
out=$(printf '{"hook_event_name":"PreToolUse","tool_name":"Artifact","tool_input":{"action":"quickstart","intent":"design"}}' \
  | env -u ACCOUNTS_FILE REGATTA_CONFIG="$AGK" CLAUDE_CONFIG_DIR="$HM/.claude-work" python3 "$H/design_route.py" 2>/dev/null)
check "$(echo "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["hookSpecificOutput"]["permissionDecision"])' 2>/dev/null)" "deny" "design_route, no lighthouse/accounts.json: a design start is denied"
check "$(env -u ACCOUNTS_FILE REGATTA_CONFIG="$AGK" python3 -c "
from importlib.machinery import SourceFileLoader; a = SourceFileLoader('account', '$C/bin/account').load_module()
try: a.employer({'label': 'work'}); print('answered')
except ImportError as e: print(e)" 2>&1)" "lighthouse/vault missing in $AGK — write it with the overlay's bootstrap.sh --config" "account's employer(), no lighthouse/vault: an error, never \"no employer row\""

echo "account_guard with no core: a common.py in the cwd never answers for it (B9 review)"
mkdir -p "$T/alone/bin" "$T/alone/lib" "$T/alone/hooks" "$T/stray"
cp "$C/bin/account" "$T/alone/bin/"; cp "$C/lib/find_core.py" "$T/alone/lib/"; cp "$H/account_guard.py" "$T/alone/hooks/"
printf 'def account_rows(*a, **k):\n    return []\n' > "$T/stray/common.py"
out=$(cd "$T/stray" && echo "{\"cwd\":\"$T/stray\"}" | env -u REGATTA_HOME REGATTA_CONFIG="$NC" ACCOUNTS_FILE="$T/nc-acc.json" CLAUDE_CONFIG_DIR="$HM/.claude-work" python3 "$T/alone/hooks/account_guard.py")
check "$(echo "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["decision"])' 2>&1)" "block" "  blocked: no regatta core, whatever the cwd holds"

echo; [ $fails -eq 0 ] && echo "all passed" || { echo "$fails FAILED"; exit 1; }
