#!/usr/bin/env bash
# knowledge-home's cases: where a repo's memory lives by the registry's flag (`where`), the move
# and the link (`adopt`) for each login dir, the knowledge repo's skeleton (`init`) and G2's check
# (`check`). Everything is a fixture: a scratch copy of the core and this module, a scratch home,
# projects folder, registry, vault and login dirs; no real memory is read or moved. No network.
#   bash modules/atlas/tests/knowledge-home.sh
set -u
M="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$(cd "$M/../.." && pwd)"
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT   # physical: the tool reports resolved paths
for v in $(env | sed -n 's/^\(REGATTA[A-Za-z0-9_]*\)=.*/\1/p; s/^\(CLAUDE[A-Za-z0-9_]*\)=.*/\1/p; s/^\(ATLAS[A-Za-z0-9_]*\)=.*/\1/p'); do unset "$v"; done
unset XDG_DATA_HOME ACCOUNTS_FILE
H="$T/u"; export HOME="$H" REGATTA_CONFIG="$T/cfg"; mkdir -p "$H" "$REGATTA_CONFIG"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0=maintenance.auto GIT_CONFIG_VALUE_0=false GIT_CONFIG_KEY_1=gc.auto GIT_CONFIG_VALUE_1=0
fails=0
check() { if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3: expected [$2] got [$1]"; fails=$((fails+1)); fi; }

S="$T/root"; mkdir -p "$S/modules"
cp -R "$ROOT/modules/regatta" "$ROOT/modules/atlas" "$S/modules/"
KH="python3 $S/modules/atlas/bin/knowledge-home"
P="$H/projects"; mkdir -p "$P"
export CLAUDE_REPOS_JSON="$T/repos.json" ATLAS_VAULT="$T/vault" ACCOUNTS_FILE="$T/accounts.json"
mkdir -p "$T/vault/memory"; echo '{"accounts": []}' > "$ACCOUNTS_FILE"
cat > "$CLAUDE_REPOS_JSON" <<'EOF'
{"repos": {"acme-knowledge": {}, "acme/app": {}, "acme/site": {}, "acme/wiki": {}, "tools": {}, "other/site": {}, "loner": {}},
 "scopes": {"acme": {"file": "acme.code-workspace", "repos": ["acme-knowledge", "acme/*"], "confidential": true},
            "open": {"file": "open.code-workspace", "repos": ["tools", "other/site"]}}}
EOF
repo() { mkdir -p "$P/$1" && git -C "$P/$1" init -q -b main && git -C "$P/$1" commit -q --allow-empty -m init; }
slug() { python3 -c "import re,sys;print(re.sub('[^A-Za-z0-9]','-',sys.argv[1]))" "$1"; }
repo acme/app; repo tools
C1="$T/login1"; mkdir -p "$C1/projects"

echo "where: the registry's flag picks the home"
check "$($KH where "$P/tools" | cut -f1,2)" "$T/vault/memory/tools	vault" "an open scope's repo: the vault's memory/<repo>"
check "$($KH where "$P/acme/app" | cut -f1,2,3)" "$P/acme-knowledge/memory/app	node	acme" "a confidential scope's repo: its anchor's memory/<repo>"
mkdir -p "$T/loose"; git -C "$T/loose" init -q -b main
check "$($KH where "$T/loose" | cut -f2)" "vault" "a repo the registry lacks: the vault, as before"
git -C "$P/acme/app" worktree add -q "$P/acme/app/.claude/worktrees/w" -b w 2>/dev/null
check "$($KH where "$P/acme/app/.claude/worktrees/w" | cut -f1)" "$P/acme-knowledge/memory/app" "  a worktree folds into its repo"
check "$(cd "$T" && $KH where "$P/tools" --vault vault | cut -f1)" "$T/vault/memory/tools" "  a relative --vault is made absolute"
python3 - "$CLAUDE_REPOS_JSON" "$T/pre.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); d["scopes"] = {"pre": {"repos": ["tools", "acme/app"]}, **d["scopes"]}
json.dump(d, open(sys.argv[2], "w"))
PY
check "$(CLAUDE_REPOS_JSON="$T/pre.json" $KH where "$P/acme/app" | cut -f2,3)" "node	acme" "  a repo in an open scope listed first and a confidential one: the node"
printf '{"repos": {"acme/app": {}' > "$T/torn.json"
CLAUDE_REPOS_JSON="$T/torn.json" $KH where "$P/acme/app" >/dev/null 2>"$T/torn.err"; check $? 1 "  a registry that does not read: refused, never the vault"
grep -q "cannot be read" "$T/torn.err"; check $? 0 "  and says so"
CLAUDE_REPOS_JSON="$T/torn.json" $KH check >/dev/null 2>&1; check $? 1 "  check fails on it too"
CLAUDE_REPOS_JSON="$T/gone.json" $KH where "$P/acme/app" >/dev/null 2>&1; check $? 1 "  a registry named but gone: refused too"
python3 - "$CLAUDE_REPOS_JSON" "$T/unlisted.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); d["scopes"]["acme"]["repos"].append("acme/new")
json.dump(d, open(sys.argv[2], "w"))
PY
repo acme/new
check "$(CLAUDE_REPOS_JSON="$T/unlisted.json" $KH where "$P/acme/new" | cut -f2,3)" "node	acme" "  a member the scope names but repos lacks: still the node"

echo "adopt: an open repo, into the vault (bootstrap.sh adopt-memory's old behaviour)"
s=$(slug "$P/tools"); mkdir -p "$C1/projects/$s/memory"; echo m > "$C1/projects/$s/memory/note.md"
$KH adopt "$P/tools" --config-dir "$C1" >/dev/null; check $? 0 "exit 0"
check "$(cat "$T/vault/memory/tools/note.md" 2>/dev/null)" m "  the folder moved into the vault"
check "$(readlink "$C1/projects/$s/memory")" "$T/vault/memory/tools" "  and is linked back"
$KH adopt "$P/tools" --config-dir "$C1" | grep -q '^  ok '; check $? 0 "  a second run: ok, nothing moved"

echo "adopt: a confidential repo needs its knowledge repo"
s=$(slug "$P/acme/app"); mkdir -p "$C1/projects/$s/memory"; echo secret > "$C1/projects/$s/memory/n.md"
$KH adopt "$P/acme/app" --config-dir "$C1" 2>"$T/e1"; check $? 1 "the anchor not on this Mac: refused"
grep -q "not on this Mac" "$T/e1"; check $? 0 "  and says so"
check "$(cat "$C1/projects/$s/memory/n.md")" secret "  nothing moved"

echo "init: the knowledge repo's skeleton"
$KH init acme --dry-run >"$T/dry"; check $? 0 "--dry-run: exit 0"
[ ! -e "$P/acme-knowledge" ]; check $? 0 "  and writes nothing"
$KH init nope 2>/dev/null; check $? 1 "a scope the registry lacks: refused"
$KH init acme >"$T/init"; check $? 0 "a new knowledge repo: exit 0"
for f in memory/README.md docs/README.md .claude/workflow.json .gitignore; do
  [ -f "$P/acme-knowledge/$f" ]; check $? 0 "  $f written"
done
check "$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['in_place'])" "$P/acme-knowledge/.claude/workflow.json")" "['memory/', 'dreams/']" "  memory/ (and dreams/) in place"
check "$(git -C "$P/acme-knowledge" log --oneline | wc -l | tr -d ' ')|$(git -C "$P/acme-knowledge" status --porcelain | wc -l | tr -d ' ')" "1|0" "  committed on main, one commit, clean"
git -C "$P/acme-knowledge" check-ignore -q .claude/worktrees/x; check $? 0 "  worktrees ignored"
check "$(python3 "$S/modules/atlas/bin/docs-index" check --repo "$P/acme-knowledge" 2>&1 | grep -c '^ERROR')" 0 "  docs-index maps its docs/: no problem"
check "$(python3 "$S/modules/atlas/bin/docs-index" mode --repo "$P/acme-knowledge")" dry "  the map starts dry"
$KH init acme | grep -q "already holds"; check $? 0 "a second run writes nothing"
repo tools2; mkdir -p "$P/tools2/.claude"; echo '{"checkpoint": true, "in_place": ["notes/"]}' > "$P/tools2/.claude/workflow.json"
python3 - "$CLAUDE_REPOS_JSON" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); d["repos"]["tools2"] = {}; d["scopes"]["t2"] = {"file": "t2.code-workspace", "repos": ["tools2"]}
json.dump(d, open(sys.argv[1], "w"))
PY
out=$($KH init t2); rc=$?
check "$rc|$(echo "$out" | grep -c 'no memory/ in in_place')" "1|1" "an existing workflow.json without memory/ in place: named, exit 1"
check "$(cat "$P/tools2/.claude/workflow.json")" '{"checkpoint": true, "in_place": ["notes/"]}' "  and never rewritten"
echo "$out" | grep -q "missing — add it on a claude/\* branch of tools2"; check $? 0 "  an existing checkout: each missing file named for a branch"
[ ! -e "$P/tools2/memory" ] && [ ! -e "$P/tools2/docs" ] && [ ! -e "$P/tools2/.gitignore" ]; check $? 0 "  and nothing written on its main"
$KH init t2 --dry-run >/dev/null; check $? 1 "  --dry-run gives the real run's answer"
echo .claude/ > "$P/tools2/.gitignore"
check "$($KH init t2 | grep -c '.gitignore is missing')" 0 "  worktrees ignored in another spelling: not missing"
rm "$P/tools2/.gitignore"

echo "check: G2"
out=$($KH check --config-dir "$C1"); rc=$?
check "$rc" 1 "a confidential repo's memory still a folder outside the node: exit 1"
echo "$out" | grep -q "is a folder outside acme's node"; check $? 0 "  named, with the adopt line"

echo "adopt: a confidential repo into its node"
$KH adopt "$P/acme/app" --config-dir "$C1" >/dev/null; check $? 0 "exit 0"
check "$(cat "$P/acme-knowledge/memory/app/n.md" 2>/dev/null)" secret "  the folder moved into <anchor>/memory/app"
check "$(readlink "$C1/projects/$s/memory")" "$P/acme-knowledge/memory/app" "  and is linked back"
out=$($KH check --config-dir "$C1"); check $? 0 "check: clean"
echo "$out" | head -1 | grep -q '^✓ memory homes: 1 confidential scope,'; check $? 0 "  its first line, for bootstrap.sh"

echo "adopt: one move per real projects folder, a link from the vault rehomed"
C2="$T/login2"; mkdir -p "$C2"; ln -s "$C1/projects" "$C2/projects"
$KH adopt "$P/acme/app" --config-dir "$C1" --config-dir "$C2" | grep -c '^  ok ' | grep -qx 1; check $? 0 "a login dir linking its projects to another's is acted on once"
repo acme/site; s2=$(slug "$P/acme/site")
mkdir -p "$T/vault/memory/site"; echo old > "$T/vault/memory/site/x.md"
mkdir -p "$C1/projects/$s2"; ln -s "$T/vault/memory/site" "$C1/projects/$s2/memory"
out=$($KH check --config-dir "$C1"); rc=$?
check "$rc|$(echo "$out" | grep -c 'outside acme.s node')" "1|1" "check: a link into the vault, outside the node"
check "$(echo "$out" | grep -c 'the vault holds')" 0 "  site is also an open repo's name: the vault's copy is not counted twice"
out=$($KH adopt "$P/acme/site" --config-dir "$C1"); rc=$?
check "$rc|$(echo "$out" | grep -c 'also the memory of repo other/site')" "1|1" "adopt: a vault folder an open repo shares never moves into the node"
check "$(cat "$T/vault/memory/site/x.md")|$(readlink "$C1/projects/$s2/memory")" "old|$T/vault/memory/site" "  nothing moved, the link left"
python3 - "$CLAUDE_REPOS_JSON" "$T/beta.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); del d["repos"]["other/site"]; d["scopes"]["open"]["repos"] = ["tools"]
d["repos"]["beta-knowledge"] = {}; d["repos"]["beta/site"] = {}
d["scopes"]["beta"] = {"repos": ["beta-knowledge", "beta/site"], "confidential": True}
json.dump(d, open(sys.argv[2], "w"))
PY
out=$(CLAUDE_REPOS_JSON="$T/beta.json" $KH adopt "$P/acme/site" --config-dir "$C1"); rc=$?
check "$rc|$(echo "$out" | grep -c 'also the memory of repo beta/site')" "1|1" "  nor one another confidential scope's repo shares"
rm "$C1/projects/$s2/memory"; rm -rf "$T/vault/memory/site"
repo acme/wiki; s5=$(slug "$P/acme/wiki")
mkdir -p "$T/vault/memory/wiki"; echo old > "$T/vault/memory/wiki/x.md"
mkdir -p "$C1/projects/$s5" "$H/.claude/projects/$s5"
ln -s "$T/vault/memory/wiki" "$C1/projects/$s5/memory"; ln -s "$T/vault/memory/wiki" "$H/.claude/projects/$s5/memory"
$KH adopt "$P/acme/wiki" --config-dir "$C1" | grep -q 'rehome'; check $? 0 "adopt: the vault's folder moved to the node"
check "$(cat "$P/acme-knowledge/memory/wiki/x.md")|$(readlink "$C1/projects/$s5/memory")" "old|$P/acme-knowledge/memory/wiki" "  its content in the node, the link re-pointed"
[ ! -e "$T/vault/memory/wiki" ]; check $? 0 "  and gone from the vault"
check "$(readlink "$H/.claude/projects/$s5/memory")" "$P/acme-knowledge/memory/wiki" "  a login dir not named that linked to it: re-pointed too"
rm -rf "$H/.claude/projects/$s5"
mkdir -p "$T/vault/memory/acme-knowledge"
out=$($KH check --config-dir "$C1"); rc=$?
check "$rc|$(echo "$out" | grep -c 'the vault holds')" "1|1" "check: the vault's memory/<repo> of a confidential repo is a fault"
rmdir "$T/vault/memory/acme-knowledge"

echo "adopt: never a merge"
repo acme/extra 2>/dev/null; python3 - "$CLAUDE_REPOS_JSON" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); d["repos"]["acme/extra"] = {}; json.dump(d, open(sys.argv[1], "w"))
PY
s3=$(slug "$P/acme/extra"); mkdir -p "$C1/projects/$s3/memory" "$P/acme-knowledge/memory/extra"; echo a > "$C1/projects/$s3/memory/a.md"; echo b > "$P/acme-knowledge/memory/extra/b.md"
$KH adopt "$P/acme/extra" --config-dir "$C1" | grep -q 'merge by hand'; check $? 0 "a home that exists beside a folder: one line"
$KH adopt "$P/acme/extra" --config-dir "$C1" >/dev/null; check $? 1 "  exit 1"
check "$(cat "$C1/projects/$s3/memory/a.md")" a "  nothing moved"
rm -rf "$C1/projects/$s3"
$KH adopt "$P/acme/extra" --dry-run --config-dir "$C1" | grep -q '^  would create'; check $? 0 "--dry-run says what it would do"
[ ! -e "$C1/projects/$s3/memory" ]; check $? 0 "  and does nothing"

echo "adopt: an empty home is taken over"
repo loner; s6=$(slug "$P/loner"); CA="$T/la"; CB="$T/lb"; mkdir -p "$CA/projects" "$CB/projects/$s6/memory"; echo n > "$CB/projects/$s6/memory/n.md"
$KH adopt "$P/loner" --config-dir "$CA" --config-dir "$CB" >/dev/null; check $? 0 "a login dir with no memory first, one with a folder second: exit 0"
check "$(cat "$T/vault/memory/loner/n.md" 2>/dev/null)|$(readlink "$CA/projects/$s6/memory")|$(readlink "$CB/projects/$s6/memory")" "n|$T/vault/memory/loner|$T/vault/memory/loner" "  the folder moved in, both linked"

echo "adopt: the landing review's cases (2026-10-22)"
repo acme/unreg; su=$(slug "$P/acme/unreg"); mkdir -p "$C1/projects/$su/memory"; echo u > "$C1/projects/$su/memory/u.md"
$KH where "$P/acme/unreg" >/dev/null 2>&1; check $? 1 "a clone under a confidential glob the registry lacks: no home, never the vault"
$KH adopt "$P/acme/unreg" --config-dir "$C1" 2>/dev/null; check $? 1 "  adopt: refused"
[ -d "$C1/projects/$su/memory" ] && [ ! -L "$C1/projects/$su/memory" ] && [ ! -e "$T/vault/memory/unreg" ]; check $? 0 "  nothing moved"
rm -rf "$C1/projects/$su"
python3 - "$CLAUDE_REPOS_JSON" <<'PY2'
import json, sys
d = json.load(open(sys.argv[1])); d["repos"].update({"acme/two": {}, "acme/three": {}, "acme/four": {}}); json.dump(d, open(sys.argv[1], "w"))
PY2
repo acme/two; st=$(slug "$P/acme/two"); CA2="$T/la2"; CB2="$T/lb2"; mkdir -p "$CA2/projects/$st/memory" "$CB2/projects/$st/memory"; echo n > "$CA2/projects/$st/memory/n.md"
$KH adopt "$P/acme/two" --config-dir "$CA2" --config-dir "$CB2" >/dev/null; check $? 0 "a folder first, an empty folder second: exit 0"
check "$(cat "$P/acme-knowledge/memory/two/n.md" 2>/dev/null)|$(readlink "$CB2/projects/$st/memory")" "n|$P/acme-knowledge/memory/two" "  the folder moved in, the empty one linked"
repo acme/three; s8=$(slug "$P/acme/three"); CA3="$T/la3"; CB3="$T/lb3"; mkdir -p "$CA3/projects/$s8/memory" "$CB3/projects/$s8" "$T/vault/memory/three"
echo a > "$CA3/projects/$s8/memory/a.md"; echo v > "$T/vault/memory/three/v.md"; ln -s "$T/vault/memory/three" "$CB3/projects/$s8/memory"
$KH adopt "$P/acme/three" --config-dir "$CA3" --config-dir "$CB3" --dry-run >/dev/null 2>&1; check $? 1 "a folder in one login, a link to a full old home in another: --dry-run refuses"
$KH adopt "$P/acme/three" --config-dir "$CA3" --config-dir "$CB3" >/dev/null 2>&1; check $? 1 "  the real run too, up front"
check "$(cat "$CA3/projects/$s8/memory/a.md")|$(readlink "$CB3/projects/$s8/memory")" "a|$T/vault/memory/three" "  nothing moved"
rm -rf "$CA3" "$CB3" "$T/vault/memory/three"
repo acme/four; s9=$(slug "$P/acme/four"); mkdir -p "$C1/projects/$s9"; ln -s "$P/acme-knowledge/memory/four" "$C1/projects/$s9/memory"
$KH adopt "$P/acme/four" --config-dir "$C1" >/dev/null; check $? 0 "a link to the node's folder, the folder missing (a fresh clone): exit 0"
[ -d "$P/acme-knowledge/memory/four" ]; check $? 0 "  the folder created"
python3 - "$CLAUDE_REPOS_JSON" "$T/twin.json" <<'PY2'
import json, sys
d = json.load(open(sys.argv[1])); d["repos"]["acme/old/app"] = {}; json.dump(d, open(sys.argv[2], "w"))
PY2
repo acme/old/app
CLAUDE_REPOS_JSON="$T/twin.json" $KH adopt "$P/acme/old/app" --config-dir "$C1" 2>/dev/null; check $? 1 "two members of one scope with one folder name: refused"
[ ! -e "$C1/projects/$(slug "$P/acme/old/app")/memory" ]; check $? 0 "  nothing linked"
CLAUDE_REPOS_JSON="$T/twin.json" $KH check --config-dir "$C1" | grep -q "app is the folder name of 2"; check $? 0 "  check names it"

echo "adopt: a confidential scope with no anchor"
python3 - "$CLAUDE_REPOS_JSON" "$T/glob.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); d["repos"]["g/x"] = {}; d["scopes"]["g"] = {"repos": ["g/*"], "confidential": True}
json.dump(d, open(sys.argv[2], "w"))
PY
repo g/x; s7=$(slug "$P/g/x"); mkdir -p "$C1/projects/$s7/memory"; echo s > "$C1/projects/$s7/memory/s.md"
CLAUDE_REPOS_JSON="$T/glob.json" $KH where "$P/g/x" >/dev/null 2>&1; check $? 1 "where: no home, never the vault"
CLAUDE_REPOS_JSON="$T/glob.json" $KH adopt "$P/g/x" --config-dir "$C1" 2>/dev/null; check $? 1 "adopt: refused"
[ -d "$C1/projects/$s7/memory" ] && [ ! -L "$C1/projects/$s7/memory" ] && [ ! -e "$T/vault/memory/x" ]; check $? 0 "  nothing moved"
rm -rf "$C1/projects/$s7"

echo "the login dirs by default"
s4=$(slug "$P/tools2"); mkdir -p "$H/.claude/projects/$s4/memory"
CLAUDE_CONFIG_DIR="$C1" $KH adopt "$P/tools2" >/dev/null
[ -d "$H/.claude/projects/$s4/memory" ] && [ ! -L "$H/.claude/projects/$s4/memory" ]; check $? 0 "\$CLAUDE_CONFIG_DIR set: only that dir is touched"
rm -rf "$T/vault/memory/tools2" "$C1/projects/$s4"
$KH adopt "$P/tools2" >/dev/null
[ -L "$H/.claude/projects/$s4/memory" ]; check $? 0 "unset: every login dir here (the home folder's .claude)"
mkdir -p "$H/.claude/projects/$(slug "$P/acme/app")/memory"
CLAUDE_CONFIG_DIR="$C1" $KH check | grep -q "$H/.claude/projects/.* is a folder outside"; check $? 0 "check reads every login dir, \$CLAUDE_CONFIG_DIR set or not"
rm -rf "$H/.claude/projects/$(slug "$P/acme/app")"

echo "check: the knowledge repo's own state"
mv "$P/acme-knowledge/.claude/workflow.json" "$T/wf"
$KH check --config-dir "$C1" | grep -q 'workflow.json is missing'; check $? 0 "no workflow.json in the node: a fault"
mv "$T/wf" "$P/acme-knowledge/.claude/workflow.json"
mv "$P/acme-knowledge" "$T/away"
out=$($KH check --config-dir "$C1"); rc=$?
check "$rc|$(echo "$out" | grep -c 'not on this Mac')" "0|1" "the anchor not here: a note; links into its path are no fault"
mv "$T/away" "$P/acme-knowledge"
python3 - "$CLAUDE_REPOS_JSON" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); d["scopes"]["acme"]["confidential"] = False; json.dump(d, open(sys.argv[1], "w"))
PY
out=$($KH check --config-dir "$C1"); check $? 0 "no confidential scope: clean"
check "$($KH where "$P/acme/app" | cut -f2)" vault "  the flag off: the vault is the home again"
$KH adopt "$P/acme/app" --config-dir "$C1" | grep -q rehome; check $? 0 "  and adopt moves it back"

echo
[ "$fails" = 0 ] && echo "knowledge-home: all ok" || echo "knowledge-home: $fails FAILED"
[ "$fails" = 0 ]
