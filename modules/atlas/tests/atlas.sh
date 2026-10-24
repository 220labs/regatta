#!/usr/bin/env bash
# atlas's own cases: where the vault and the layer are (lib/atlaslib.py), the bulletin and the
# vault commit on them, knowledge-commit's names, and the two optional edges out of this module —
# keel for the bulletin's Open line and docs-index's sets (G19), wharf's `pr` and `carried.py` for
# knowledge-commit --in (G20) — each with the peer present and absent.
# A scratch copy of the core and this module stands in for the checkout, so a sibling module
# put beside them never decides a case; HOME and the config dir are scratch too. No network:
# "origin" is a bare repo in the scratch folder.
#   bash modules/atlas/tests/atlas.sh
set -u
M="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$(cd "$M/../.." && pwd)"
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT   # physical: the core reports resolved paths
for v in $(env | sed -n 's/^\(REGATTA[A-Za-z0-9_]*\)=.*/\1/p; s/^\(CLAUDE[A-Za-z0-9_]*\)=.*/\1/p; s/^\(MEMO[A-Za-z0-9_]*\)=.*/\1/p; s/^\(ATLAS[A-Za-z0-9_]*\)=.*/\1/p'); do unset "$v"; done
unset XDG_DATA_HOME KNOWLEDGE_NO_PUSH
RHOME=$HOME   # PyYAML may be a user-site install, found only under the real home folder
export HOME="$T/u" REGATTA_CONFIG="$T/cfg"; mkdir -p "$HOME" "$REGATTA_CONFIG"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0=maintenance.auto GIT_CONFIG_VALUE_0=false GIT_CONFIG_KEY_1=gc.auto GIT_CONFIG_VALUE_1=0
fails=0
check() { if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3: expected [$2] got [$1]"; fails=$((fails+1)); fi; }

# The scratch checkout: the marketplace file, the core and this module, nothing else.
S="$T/root"; mkdir -p "$S/.claude-plugin" "$S/modules"
cp "$ROOT/.claude-plugin/marketplace.json" "$S/.claude-plugin/"
cp -R "$ROOT/modules/regatta" "$ROOT/modules/atlas" "$S/modules/"
A="$S/modules/atlas"
lib() { python3 -c "import sys; sys.path.insert(0, '$A/lib'); import atlaslib; $1"; }

echo "where the vault and the layer are (lib/atlaslib.py)"
check "$(lib 'print(atlaslib.repo("vault"))')" "$T/u/.local/share/atlas" "no overlay, no key: the vault is a plain folder in the XDG data dir"
check "$(lib 'print(atlaslib.repo("layer"))')" "None" "  the layer has no default"
check "$(ATLAS_VAULT="$T/v" lib 'print(atlaslib.repo("vault"))')" "$T/v" "ATLAS_VAULT overrides the path"
mkdir -p "$REGATTA_CONFIG/regatta"; echo "$T/overlay-checkout" > "$REGATTA_CONFIG/regatta/overlay"
check "$(lib 'print(atlaslib.repo("vault"))')" "None" "the overlay installed (its regatta/overlay marker) and no key: None, never a guess"
lib 'print(atlaslib.missing("vault"))' | grep -q "atlas/vault holds no name and path"; check $? 0 "  and the line says which key"
# With the overlay installed the core loads only with its private values (B2b): neutral ones.
mkdir -p "$REGATTA_CONFIG/atlas" "$REGATTA_CONFIG/regatta"
for k in owner guarded orca-deny; do echo x > "$REGATTA_CONFIG/regatta/$k"; done
echo "$T/logs" > "$REGATTA_CONFIG/regatta/log-dir"; echo "$T/u/projects" > "$REGATTA_CONFIG/regatta/projects"
printf 'myvault\n%s\n' "$T/vault" > "$REGATTA_CONFIG/atlas/vault"
printf 'mylayer\n~/layer\n' > "$REGATTA_CONFIG/atlas/layer"
check "$(lib 'print(atlaslib.key("vault"))')" "('myvault', PosixPath('$T/vault'))" "a key: the name, then the path"
check "$(lib 'print(atlaslib.repo("layer"))')" "$T/u/layer" "  a leading ~ is the home folder"
printf 'x\nrelative/path\n' > "$T/rel"; cp "$T/rel" "$REGATTA_CONFIG/atlas/layer"
check "$(lib 'print(atlaslib.repo("layer"))')" "None" "  a relative path is no key"
printf 'mylayer\n%s\nMY_LAYER_DIR\n' "$T/layer" > "$REGATTA_CONFIG/atlas/layer"
check "$(MY_LAYER_DIR="$T/elsewhere" lib 'print(atlaslib.repo("layer"))')" "$T/elsewhere" "a key's third line names the installer's own override variable"
check "$(lib 'print(atlaslib.missing("layer").rsplit(", or ", 1)[-1])')" "MY_LAYER_DIR for this shell)" "  and the refusal names it"
check "$(lib 'print(atlaslib.core().regatta_root())')" "$S" "core(): the core of the checkout this module is in"

echo "the bulletin on the configured vault"
BU="python3 $A/hooks/bulletin.py"
export MEMO_ROOT="$T/no-projects" MEMO_STATE_DIR="$T/memo-state"; mkdir -p "$MEMO_ROOT"
$BU --post "why" "a learning" >/dev/null; check $? 0 "--post into the vault"
check "$(grep -c '· why: why · a learning$' "$T/vault/bulletin.md")" 1 "  one line in <vault>/bulletin.md"
out=$(echo '{"session_id":"s1"}' | $BU 2>"$T/s1.err"); check $? 0 "the hook: exit 0"
echo "$out" | grep -q "a learning$"; check $? 0 "  shows the entry once"
check "$(echo '{"session_id":"s1"}' | $BU | grep -c 'a learning')" 0 "  and not twice"
mv "$REGATTA_CONFIG/atlas/vault" "$T/vault-key"
out=$(echo '{"session_id":"s2"}' | $BU 2>"$T/s2.err"); check $? 0 "no vault configured (overlay): the hook still exits 0"
check "$(grep -c 'atlas/vault' "$T/s2.err")" 1 "  one line on stderr naming the key"
$BU --post "why" "lost" >/dev/null 2>"$T/p.err"; check $? 1 "  a post is refused, never written to a guessed folder"
grep -q "atlas/vault" "$T/p.err"; check $? 0 "  and says which key"
mv "$T/vault-key" "$REGATTA_CONFIG/atlas/vault"

echo "G19: the bulletin's Open line through the core's lookup"
OD="$T/od"; mkdir -p "$OD/r/docs"; printf '# Design\n\nStatus: open\n' > "$OD/r/docs/design.md"
out=$(echo '{"session_id":"g1"}' | MEMO_ROOT="$OD" $BU 2>"$T/g1.err"); rc=$?
check "$rc|$(echo "$out" | grep -c '^📂')|$(wc -c < "$T/g1.err" | tr -d ' ')" "0|0|0" "keel absent: exit 0, no Open line, nothing on stderr"
mkdir -p "$S/modules/keel/bin"
printf 'def open_memos(root):\n    return [{"kind": "open"}]\ndef open_counts(rows):\n    return {"post-mortem": 0, "decisions": 0, "open": len(rows)}\n' > "$S/modules/keel/bin/keel"
check "$(echo '{"session_id":"g2"}' | MEMO_ROOT="$OD" $BU | grep '^📂')" "📂 Open: 1 open doc — /keel open" "keel present beside atlas: found by common.tool, its count shown"
printf 'def open_memos(root):\n    raise RuntimeError("boom")\n' > "$S/modules/keel/bin/keel"
out=$(echo '{"session_id":"g3"}' | MEMO_ROOT="$OD" $BU 2>"$T/g3.err"); rc=$?
check "$rc|$(echo "$out" | grep -c '^📂')|$(wc -c < "$T/g3.err" | tr -d ' ')" "0|0|0" "keel raising: exit 0, no Open line, nothing on stderr"
rm -rf "$S/modules/keel"

echo "G19: docs-index without keel"
DS="$T/setrepo"; git init -q -b main "$DS"; mkdir -p "$DS/docs"
printf '# docs\n\nmode: dry\n\n| Topic | Chart | Records | Code |\n| --- | --- | --- | --- |\n| c | — | [c-2026-10-14.md](c-2026-10-14.md) | x |\n' > "$DS/docs/README.md"
printf '# C\n\n[part](c-part-2026-10-14.md)\n' > "$DS/docs/c-2026-10-14.md"; printf '# Part\n' > "$DS/docs/c-part-2026-10-14.md"
git -C "$DS" add -A; git -C "$DS" commit -qm init
out=$(python3 "$A/bin/docs-index" check --repo "$DS" 2>&1); rc=$?
check "$rc" 0 "no keel: check runs, exit 0"
echo "$out" | grep -q "c-part-2026-10-14.md"; check $? 0 "  a component is a record of its own, as before sets (a note names it)"
(cd "$DS" && python3 "$A/bin/docs-index" mode) | grep -qx dry; check $? 0 "no --repo: the checkout of the current directory"

echo "knowledge-commit: the two names"
KC="$A/bin/knowledge-commit"
L="$T/layer"; mkdir -p "$L/.claude" "$L/docs" "$L/hooks"; RAN="$T/ran"
for s in hooks/test_checkpoint.sh hooks/test_hooks.sh bootstrap.sh; do
  printf '#!/usr/bin/env bash\necho %s >> %s\n' "$s" "$RAN" > "$L/$s"; chmod +x "$L/$s"
done
printf '.claude/worktrees/\n' > "$L/.gitignore"; echo a > "$L/docs/a.md"
printf '{"checkpoint": true, "main": "main", "merge": "auto", "records": ["docs/"]}\n' > "$L/.claude/workflow.json"
git -C "$L" init -q -b main && git -C "$L" add -A && git -C "$L" commit -qm base
"$KC" elsewhere -m x >/dev/null 2>"$T/u.err"; check $? 2 "a name that is neither repo: refused"
grep -q "usage: knowledge-commit <mylayer|myvault>" "$T/u.err"; check $? 0 "  the usage names the configured two"
"$KC" ../mylayer -m x >/dev/null 2>&1; check $? 2 "  a path trick: refused"
wt=$("$KC" mylayer --open probe 2>/dev/null); check "$wt" "$L/.claude/worktrees/probe" "--open by the configured name: the layer's worktree"
check "$("$KC" layer --open probe 2>/dev/null)" "$wt" "  the role word reaches the same repo"
mv "$REGATTA_CONFIG/atlas/layer" "$T/layer-key"
"$KC" mylayer -m x >/dev/null 2>"$T/m.err"; check $? 2 "no layer key (overlay): its old name is unknown"
grep -q "atlas/layer holds no name and path" "$T/m.err"; check $? 0 "  and the refusal names the missing key"
mv "$T/layer-key" "$REGATTA_CONFIG/atlas/layer"

echo "G20: knowledge-commit --in without wharf, then with it"
git clone -q --bare "$L" "$T/origin.git"; git -C "$L" remote add origin "$T/origin.git"; git -C "$L" fetch -q origin
echo b > "$wt/docs/b.md"; : > "$RAN"
out=$("$KC" mylayer --in "$wt" -m "Docs: b" 2>&1); rc=$?
check "$rc" 0 "online, no wharf: it launches"
echo "$out" | grep -q "wharf is not installed (no pr) — launching on main locally"; check $? 0 "  and says why there is no pull request"
check "$(git -C "$L" show main:docs/b.md 2>/dev/null)" b "  the primary's main has it"
echo "$out" | grep -q "main is ahead of origin"; check $? 0 "  ahead of origin, said so"
check "$(tr '\n' ' ' < "$RAN")" "bootstrap.sh " "  after the layer's prose check"
git -C "$L" push -q origin main
mkdir -p "$S/modules/wharf/bin" "$S/modules/wharf/hooks"
printf '#!/usr/bin/env bash\necho "pr $*" >> %s\nexit 0\n' "$RAN" > "$S/modules/wharf/bin/pr"; chmod +x "$S/modules/wharf/bin/pr"
cat > "$S/modules/wharf/hooks/carried.py" <<PY
import subprocess, sys
open("$RAN", "a").write("carried " + " ".join(sys.argv[1:]) + "\\n")
PY
wt2=$("$KC" mylayer --open second 2>/dev/null); echo c > "$wt2/docs/c.md"; : > "$RAN"
out=$("$KC" mylayer --in "$wt2" -m "Docs: c" 2>&1); rc=$?
check "$rc" 0 "wharf present: --in launches through it"
grep -q "^pr ready" "$RAN" && grep -q "^pr merge" "$RAN"; check $? 0 "  pr ready, then pr merge, found by common.tool"
grep -q "^carried $L --pull" "$RAN"; check $? 0 "  then carried.py --pull on the primary"
git -C "$T/origin.git" rev-parse -q --verify "refs/heads/$(git -C "$wt2" symbolic-ref --short HEAD)" >/dev/null; check $? 0 "  the branch was pushed to origin"
echo "$out" | grep -q "wharf is not installed"; check $? 1 "  and no word of a local launch"

echo "the vault commit on the configured vault"
V="$T/vault"; git -C "$V" init -q -b main 2>/dev/null; echo m > "$V/memo.md"
echo '{}' | python3 "$A/hooks/vault_commit.py"; check $? 0 "vault_commit: exit 0"
check "$(git -C "$V" log -1 --format=%s 2>/dev/null)" "Vault: bulletin.md, memo.md (2 files)" "  committed the vault's dirt"
mv "$REGATTA_CONFIG/atlas/vault" "$T/vault-key"; echo n > "$V/n.md"
echo '{}' | python3 "$A/hooks/vault_commit.py" 2>"$T/vc.err"; check $? 0 "no vault configured (overlay): exit 0"
check "$(git -C "$V" status --porcelain | wc -l | tr -d ' ')|$(grep -c 'atlas/vault' "$T/vc.err")" "1|1" "  nothing committed, one line saying why"
mv "$T/vault-key" "$REGATTA_CONFIG/atlas/vault"

echo "the skills' frontmatter"
out=$(HOME="$RHOME" python3 "$A/bin/skill-frontmatter" "$A"/skills/*/SKILL.md 2>&1); rc=$?
if [ $rc = 3 ]; then echo "  skip PyYAML is not installed for this python3 — nothing checked"
else check "$rc|$out" "0|3/3 parse" "every skill of the module parses"; fi

[ "$fails" = 0 ] && echo "all ok" || { echo "$fails FAILED"; exit 1; }
