#!/usr/bin/env bash
# The core's check: where the core, a peer and the private config are found (C2, C3), the private
# values with and without their keys (neutral stand-ins only), the regatta
# CLI, the gate's table order and its write through a config symlink, jev's key files, and the
# shim `regatta shim` makes, under every way a caller loads a file (the design's P5).
# Scratch paths only (a copy of the module where a test writes); nothing under ~/.config or ~/.claude is read or written.
#   bash modules/regatta/tests/check.sh
set -u
M="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$(cd "$M/../.." && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
for v in $(env | sed -n 's/^\(REGATTA[A-Za-z0-9_]*\)=.*/\1/p; s/^\(CLAUDE[A-Za-z0-9_]*\)=.*/\1/p; s/^\(GATE_[A-Za-z0-9_]*\)=.*/\1/p'); do unset "$v"; done
unset GATE_TABLE JEV_ENV_FILE JEV_LOG TYPESAFE_API_KEY TYPESAFE_BASE_URL COST_RATIO SECRETS_DIR SECRETS_REPOS SECRETS_PROJECTS SECRETS_HOST
export HOME="$T/home" REGATTA_CONFIG="$T/config"; mkdir -p "$HOME" "$REGATTA_CONFIG"
fails=0
check() { if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3: expected [$2] got [$1]"; fails=$((fails+1)); fi; }
py() { python3 -I -c "import sys; sys.path.insert(0, '$M/hooks'); import common; $1"; }
RG="$M/bin/regatta"

echo "discovery"
check "$(py 'print(common.regatta_root())')" "$ROOT" "the root is the checkout above the core"
check "$(py 'print(common.CONFIG)')" "$T/config" "REGATTA_CONFIG names the config dir"
check "$(py 'print(common.repos_json())')" "None" "no registry anywhere: repos_json() is None"
check "$(py 'print(common.cloned_repos())')" "[]" "  and cloned_repos() is empty, not an error"
mkdir -p "$T/config/wharf" "$T/home/projects/a/.git"; printf '{"repos": {"a": {}, "b": {}}, "guarded": ["a", 3]}\n' > "$T/reg.json"
ln -s "$T/reg.json" "$T/config/wharf/repos.json"
check "$(py 'print(common.repos_json())')" "$T/config/wharf/repos.json" "the config dir's registry"
check "$(py 'print([p.name for p in common.cloned_repos()])')" "['a']" "  cloned_repos() reads it, no argument"
check "$(py 'print(common.guarded_repos())')" "('a',)" "  guarded_repos() takes its strings"
check "$(CLAUDE_REPOS_JSON=/x py 'print(common.repos_json(), common.REPOS_JSON)')" "/x /x" "CLAUDE_REPOS_JSON wins"
check "$(py 'print(common.LAPTOP)')" "laptop" "LAPTOP without config: a word, no host name"
mkdir -p "$T/config/regatta"; echo mybook > "$T/config/regatta/laptop"
check "$(py 'print(common.LAPTOP)')" "mybook" "  the config file names it"
check "$(REGATTA_LAPTOP=x py 'print(common.LAPTOP)')" "x" "  REGATTA_LAPTOP wins"
check "$(py 'print(common.COST_RATIO)')" "$(cd "$T" && pwd -P)/config/regatta/cost-ratio.json" "COST_RATIO's default is in the config dir, resolved"
check "$(py 'print(common.tool("regatta"))')" "$M/bin/regatta" "tool() finds a module's bin/"
check "$(py 'print(common.tool("common.py"))')" "$M/hooks/common.py" "  and its hooks/"
check "$(py 'print(common.tool("nope"))')" "None" "  an absent tool is None"
check "$(py 'print(common.tool("c*"), common.tool(""), common.tool("../bin"))')" "None None None" "  a pattern, an empty name or a path: None"

echo "the private values (one file each; neutral without the overlay, refused when it left one out)"
J="$M/bin/jev"; G="$M/bin/gate"; H="$HOME"; KEYS="owner guarded orca-deny log-dir projects"
jp() { python3 -I -c "from importlib.machinery import SourceFileLoader as L; j = L('jev', '$J').load_module()
$1"; }
gp() { python3 -I -c "from importlib.machinery import SourceFileLoader as L; g = L('gate', '$G').load_module()
$1"; }
sp() { python3 -I -c "from importlib.machinery import SourceFileLoader as L; s = L('sc', '$M/bin/secrets').load_module()
$1"; }
# A guarded source's refusal, as a caller sees it: jev's before any key is read, the gate's for a
# classify row (the shipped example, turned to jev for the shell).
jref() { jp 'try: j.ask("s", {"q": {"type": "noul", "instructions": "x"}}, source="notes")
except j.JevError as e: print(e)'; }
gref() { GATE_EXAMPLE_CLASSIFY_PROVIDER=jev gp 'try: g.classify("example.classify", {"s1": "a"}, "Q?", {"yes": "y", "no": "n"}, source="notes", approved={"anthropic": "x"})
except g.GateError as e: print(e)'; }
refusal() { "$@" 2>&1 | tail -1; }   # an importer's last line: the ImportError, when there is one
check "$(py 'print(repr(common.ADDRESS), common.DECLARED_LINE)')" "'' THIS SESSION IS DONE — IT LANDS BY ITSELF." "no overlay, no keys: the closing lines address no one"
check "$(py 'print(common.closing_kind(common.FINISH_LINES[0]), common.closing_kind(common.WAITING_PREFIX + "D1"))')" "done waiting" "  and still read as closing lines"
check "$(py 'print(common.OVERRIDE_BY, common.ORCA_ROW["repos"]["deny"])')" "owner []" "  the override marker is owner's, no repo denied an Orca login"
check "$(jp 'print(j.GUARDED, j.WHO)')" "() the owner" "  jev guards nothing and asks the owner"
check "$(jp 'print(j.log_dir())')" "$H/.local/state/regatta" "  the logs go to .local/state/regatta in the home folder"
check "$(sp 'print(s.PROJECTS)') $(py 'print(common.PROJECTS)')" "$H/projects $H/projects" "  secrets and cloned_repos() read repos under projects in the home folder"

echo "$T/legacy" > "$T/config/legacy"   # the overlay installed: the keys are its to write
missing="regatta/owner missing; regatta/guarded missing; regatta/orca-deny missing; regatta/log-dir missing; regatta/projects missing"
check "$(refusal py 'pass')" "ImportError: regatta: config incomplete in $T/config: $missing — run your overlay's bootstrap.sh --config" \
  "the overlay installed, its keys not written: the core refuses to load, naming each"
check "$(refusal jp 'pass')" "ImportError: regatta: config incomplete in $T/config: $missing — run your overlay's bootstrap.sh --config" "  jev too, by the same rule"
out=$("$RG" check 2>&1); check "$?" 1 "  regatta check still runs, exit 1"
check "$(echo "$out" | grep -c -- "^  --  regatta/[a-z-]* missing (your overlay's bootstrap.sh --config)$")" 5 "  one line per missing key"
for k in $KEYS; do : > "$T/config/regatta/$k"; done
check "$(py 'print(common.CONFIG_PROBLEMS, repr(common.ADDRESS), common.ORCA_ROW["repos"]["deny"])')" "[] '' []" "every key written empty: the core loads, each value empty"
chmod 000 "$T/config/regatta/guarded"
check "$(refusal jp 'pass')" "ImportError: regatta: config incomplete in $T/config: regatta/guarded unreadable (Permission denied) — run your overlay's bootstrap.sh --config" \
  "an unreadable key is refused, never read as absent"
chmod 600 "$T/config/regatta/guarded"; printf 'caf\xe9\n' > "$T/config/regatta/owner"
check "$(refusal py 'pass' | grep -o 'regatta/owner [^—]*')" "regatta/owner unreadable (not UTF-8) " "  so is one that is not UTF-8"
: > "$T/config/regatta/owner"; printf 'work\n' > "$T/config/regatta/projects"
check "$(refusal py 'pass' | grep -o 'regatta/projects [^—]*')" "regatta/projects is not an absolute path: work " "a relative path key is refused, never resolved against the cwd"
out=$("$RG" check 2>&1)
check "$(echo "$out" | grep -c -- '^  --  regatta/projects is not an absolute path: work')$(echo "$out" | grep -c '^  ok  regatta/projects$')" "10" "  regatta check says it once, as a problem, and never also ok"
rm "$T/config/legacy"
check "$(refusal py 'pass' | grep -o 'regatta/projects [^—]*')" "regatta/projects is not an absolute path: work " "  with or without the overlay"

printf '\xef\xbb\xbf\n  Kapitän\n' > "$T/config/regatta/owner"; printf 'notes\n\nlogbook\n' > "$T/config/regatta/guarded"
printf 'logbook\n' > "$T/config/regatta/orca-deny"; printf '~%s\n' /logs > "$T/config/regatta/log-dir"; printf '~%s\n' /work > "$T/config/regatta/projects"
check "$(py 'print(common.config_line("regatta/owner"))') $(jp 'print(j.WHO)')" "Kapitän Kapitän" "one reader: the first non-blank line, the BOM dropped, for the core and jev alike"
check "$(py 'print(common.DECLARED_LINE)')" "KAPITÄN, THIS SESSION IS DONE — IT LANDS BY ITSELF." "regatta/owner: the closing lines address it, upper-cased"
check "$(py 'print(common.closing_kind("KAPITÄN, THIS WAS ONLY THE PICKUP — CLOSE THIS SESSION. THE WORK CONTINUES IN THE NEW TAB."), common.closing_kind("THIS SESSION IS DONE — IT LANDS BY ITSELF."))')" "done None" "  every pattern opens with it; the unaddressed line is none"
check "$(py 'print(common.ending("x\nKAPITÄN, THIS SESSION IS DUN")[2])')" "('unknown', 'KAPITÄN, THIS SESSION IS DUN')" "  an addressed line that is no closing line: unknown"
check "$(py 'print(bool(common.ASK_EXEMPT_RE.search("the next step waits for kapitän to start it")))')" "True" "  the chain-depth line names it, any case"
mkdir -p "$T/af"; printf '{"by": "kapitän"}' > "$T/af/autofinish"
check "$(py 'print(common.autofinish_override("'"$T/af"'"))')" "{'by': 'kapitän'}" "  /autofinish's marker by it, lower-cased: an override"
printf '{"by": "owner"}' > "$T/af/autofinish"
check "$(py 'print(common.autofinish_override("'"$T/af"'"))')" "None" "  by anyone else: none"
check "$(py 'print(common.ORCA_ROW["repos"]["deny"], common.orca_row("x")["repos"]["deny"])')" "['logbook'] ['logbook']" "regatta/orca-deny: an unnamed Orca login's deny list"
check "$(jp 'print(j.GUARDED, j.WHO)')" "('notes', 'logbook') Kapitän" "regatta/guarded: jev's guarded sources, blank lines skipped"
check "$(jref)" 'refused: data from notes goes to TypeSafe only with Kapitän'"'"'s say-so — ask, then pass approved="Kapitän, <date>: <what>"' "  jev refuses one without a quote, naming the owner"
check "$(gref)" "example.classify: refused: data from notes goes to typesafe only with Kapitän's say-so — approved has no 'typesafe' quote (it has: anthropic)" "  and so does the gate"
check "$(jp 'print(j.log_dir())')" "$H/logs" "regatta/log-dir: the logs' folder, ~ the home folder"
JEV_LOG= jp 'j._log({"t": "jev"})'; GATE_LOG= gp 'g._log({"t": "gate"})'
check "$(cat "$H/logs/jev.jsonl" "$H/logs/gate.jsonl" 2>&1 | tr '\n' ' ')" '{"t": "jev"} {"t": "gate"} ' "  jev's and the gate's lines land there, an empty JEV_LOG or GATE_LOG no override"
check "$(sp 'print(s.PROJECTS)') $(py 'print(common.PROJECTS)')" "$H/work $H/work" "regatta/projects: one projects folder, ~ the home folder"
printf 'O’Hara\n' > "$T/config/regatta/owner"; printf '100%%\n' > "$T/config/regatta/guarded"
check "$(py 'print(common.ADDRESS, common.closing_kind("O’HARA, THIS SESSION IS DONE — IT LANDS BY ITSELF."))')" "O'HARA,  done" "a typographic apostrophe in the name: straight, as bare() reads a line"
"$J" ask --help > "$T/help.out" 2>&1; check "$?:$(grep -c '100%' "$T/help.out")" "0:1" "  jev's --approved help survives a % in a configured name"
# jev loads the core under a private name: a caller's own `common` is never replaced, nor found by jev.
mkdir -p "$T/own"; printf 'MINE = 1\n' > "$T/own/common.py"
cat > "$T/own/run.py" <<PY
import sys; sys.path.insert(0, "$T/own")
from importlib.machinery import SourceFileLoader as L
j = L("jev", "$J").load_module()      # jev first: it must not take the name
import common
first = common.MINE
j2 = L("jev2", "$J").load_module()    # and after: it must not replace it
print(first, sys.modules["common"].MINE, j.WHO, j2.GUARDED, "_regatta_jev_common" in sys.modules)
PY
check "$(python3 -I "$T/own/run.py" 2>&1)" "1 1 O’Hara ('100%',) False" "  jev beside a caller's own common.py: each keeps its own"
# Clean up: from here on the suite's overlay wrote every key, empty — the neutral values.
for k in $KEYS; do : > "$T/config/regatta/$k"; done; rm -rf "$T/af" "$H/logs" "$T/help.out" "$T/own"

mkdir -p "$T/legacy/bin"; printf '#!/bin/sh\necho legacy "$@"\n' > "$T/legacy/bin/pr"; chmod +x "$T/legacy/bin/pr"
echo "$T/legacy" > "$T/config/legacy"
check "$(py 'print(common.tool("pr"))')" "$T/legacy/bin/pr" "  the legacy file reaches a file not moved yet"
CC="$T/claude"; mkdir -p "$CC/plugins" "$T/cache/wharf/1/bin" "$T/proj/sub"; : > "$T/cache/wharf/1/bin/finish-x"
printf '{"plugins": {"wharf@regatta": [{"scope": "project", "projectPath": "%s", "installPath": "%s"}]}}\n' "$T/proj" "$T/cache/wharf/1" > "$CC/plugins/installed_plugins.json"
cp -R "$M" "$T/cache-core"   # a core outside any checkout, as in a plugin cache
cpy() { (cd "$1" && CLAUDE_CONFIG_DIR="$CC" python3 -I -c "import sys; sys.path.insert(0, '$T/cache-core/hooks'); import common; $2"); }
check "$(cpy "$T/proj/sub" 'print(common.tool("finish-x"))')" "$T/cache/wharf/1/bin/finish-x" "from a cache: a project row's installPath, cwd inside it"
check "$(cpy "$T" 'print(common.tool("finish-x"))')" "None" "  cwd outside the project: not found"
check "$(cpy "$T/proj" 'print(common.module_path("wharf"))')" "$T/cache/wharf/1" "  module_path() reads the same row"
mkdir "$T/gonecwd"
check "$(cd "$T/gonecwd" && rmdir "$T/gonecwd" && CLAUDE_CONFIG_DIR="$CC" python3 -I -c "import sys; sys.path.insert(0, '$T/cache-core/hooks'); import common; print(common.tool('nope'))" 2>&1)" "None" "  a removed cwd: None, no traceback"

echo "the CLI"
check "$("$RG" root)" "$ROOT" "regatta root"
check "$("$RG" has regatta)" "$M" "regatta has regatta"
out=$("$RG" has helm); check "$?:$out" "1:helm not installed" "regatta has helm: not installed, exit 1"
out=$("$RG" helm board 2>&1); check "$?:$out" "2:regatta: helm not installed" "regatta helm …: one line, exit 2 (G28)"
check "$("$RG" pr ready 7)" "legacy ready 7" "regatta pr …: runs the tool where it is, args passed"
out=$("$RG" which 2>&1); check "$?:$out" "2:regatta which: wrong arguments — \`regatta help\`" "regatta which, no name: a usage error, exit 2"
rm "$T/config/legacy"
out=$("$RG" check); check "$?" 1 "regatta check without a home: exit 1"
echo "$out" | grep -q -- "--  home: none"; check $? 0 "  it says so"
out=$(REGATTA_HOME="$ROOT" "$RG" check); check "$?" 1 "  REGATTA_HOME set, still no home file: exit 1"
echo "$ROOT" > "$T/config/home"; ln -s "$T/gone" "$T/config/regatta/broken"
out=$("$RG" check); check "$?" 1 "  a dangling link: exit 1"
echo "$out" | grep -q -- "--  regatta/broken → $T/gone (missing)"; check $? 0 "  it names the link and its target"
rm "$T/config/regatta/broken"; out=$("$RG" check); check "$?" 0 "  all well: exit 0"

echo "the gate's table"
G="$M/bin/gate"
gp() { python3 -I -c "from importlib.machinery import SourceFileLoader as L; g = L('gate', '$G').load_module(); $1"; }
check "$(gp 'print(g._path())')" "$M/settings/models.json" "no config table: the defaults beside the gate"
check "$("$G" check >/dev/null 2>&1; echo $?)" 0 "  which validate"
R2="$T/ov"; mkdir -p "$R2/settings"; cp "$M/settings/models.json" "$R2/settings/models.json"
python3 - "$R2/settings/models.json" <<'PY'
import json, sys
p = sys.argv[1]; t = json.load(open(p)); t["sites"]["x.y"] = {"kind": "generate", "provider": "claude", "when_off": "fail"}
open(p, "w").write(json.dumps(t, indent=2) + "\n")
PY
git -C "$R2" init -q -b main && git -C "$R2" add -A && git -C "$R2" -c user.name=t -c user.email=t@t commit -qm t
ln -s "$R2/settings/models.json" "$T/config/regatta/models.json"
check "$(gp 'print(g._path())')" "$T/config/regatta/models.json" "a config table wins over the defaults"
check "$(GATE_TABLE=/z gp 'print(g._path())')" "/z" "  GATE_TABLE over both"
check "$(gp 'print(g._rel(g._path()))')" "settings/models.json" "  named as its repo names it, through the link"
out=$("$G" set x.y model=haiku 2>&1); check "$?" 1 "set through the link onto a main checkout: refused"
echo "$out" | grep -q "settings/models.json is on main"; check $? 0 "  the refusal names the real file"
git -C "$R2" checkout -q -b claude/flip
"$G" set x.y model=haiku >/dev/null 2>&1; check $? 0 "  on a branch: written"
[ -L "$T/config/regatta/models.json" ]; check $? 0 "  the link is still a link"
check "$(python3 -c "import json; print(json.load(open('$R2/settings/models.json'))['sites']['x.y']['model'])")" "haiku" "  and the real table changed"
"$G" show 2>/dev/null | grep -q "table: settings/models.json @ "; check $? 0 "  show names it with its commit, git run where it is"
mv "$T/config/regatta/models.json" "$T/models.link"; ln -s "$T/gone.json" "$T/config/regatta/models.json"
"$G" check >/dev/null 2>&1; check $? 1 "  a dangling config link: check fails, never the defaults"
rm "$T/config/regatta/models.json"; mv "$T/models.link" "$T/config/regatta/models.json"
cp -R "$M" "$T/gcopy"
out=$(REGATTA_CONFIG="$T/none" "$T/gcopy/bin/gate" set example.classify provider=off 2>&1); check "$?" 1 "  outside git, no config table: set refuses the shipped defaults"

echo "jev's key"
J="$M/bin/jev"
jk() { python3 -I -c "from importlib.machinery import SourceFileLoader as L; j = L('jev', '$J').load_module()
try: print(j._key())
except Exception as e: print('ERR', type(e).__name__)"; }
check "$(jk | cut -c1-3)" "ERR" "no key anywhere: an error, never another file"
printf 'TYPESAFE_API_KEY=alt\n' > "$T/config/regatta/.env.fallback"
check "$(jk)" "alt" "only .env.fallback in the config dir: it is read"
printf 'TYPESAFE_API_KEY=own\n' > "$T/config/regatta/.env"
check "$(jk)" "own" "  an own .env there: it wins, .env.fallback unread"
printf 'TYPESAFE_API_KEY=env\n' > "$T/k.env"
check "$(JEV_ENV_FILE=$T/k.env jk)" "env" "  JEV_ENV_FILE first"

echo "the shim (P5: one shape for every Python file)"
mkdir -p "$T/old/hooks" "$T/old/bin"
"$RG" shim modules/regatta/hooks/common.py > "$T/old/hooks/common.py"; check $? 0 "regatta shim writes a source shim"
"$RG" shim modules/regatta/bin/cost > "$T/old/bin/cost"; chmod +x "$T/old/bin/cost"
cat > "$T/t.py" <<'PY'
import importlib.util, os, sys
from importlib.machinery import SourceFileLoader
case, shim = sys.argv[1], sys.argv[2]
if case == "imp":
    sys.path.insert(0, os.path.dirname(shim)); import common as m
elif case == "lm":
    m = SourceFileLoader("common", shim).load_module()
else:
    spec = importlib.util.spec_from_loader("common", SourceFileLoader("common", shim))
    m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
m.config_line = lambda name: "patched"   # a caller's monkeypatch (test_repos.sh patches common.api so)
print(m.__file__, m.legacy_root(), sys.modules.get("common") is m)
PY
core="$M/hooks/common.py"
for c in imp lm em; do
  out=$(python3 -I "$T/t.py" "$c" "$T/old/hooks/common.py" 2>&1)
  case $c in em) want="$core patched False" ;; *) want="$core patched True" ;; esac
  check "$out" "$want" "  $c: the core's __file__, a patch reaches the module's own functions"
done
out=$(env -i HOME="$HOME" PATH=/usr/bin:/bin REGATTA_CONFIG="$T/config" /usr/bin/python3 -I -c "import sys; sys.path.insert(0, '$T/old/hooks'); import common; print(common.__file__, common.tool('regatta'))")
check "$out" "$core $M/bin/regatta" "  env -i: found through the home file; tool() from that root"
out=$(env -i HOME="$HOME" PATH=/usr/bin:/bin REGATTA_CONFIG="$T/config" "$T/old/bin/cost" 1.00)
echo "$out" | grep -q '^\$1.00'; check $? 0 "  a script through its shim runs the module's __main__"
out=$(REGATTA_HOME=/nowhere python3 -I -c "import sys; sys.path.insert(0, '$T/old/hooks'); import common" 2>&1 | tail -1)
check "$out" "ImportError: regatta: core missing at /nowhere/modules/regatta/hooks/common.py" "  a home with no core: one ImportError line"
out=$(REGATTA_CONFIG="$T/empty" python3 -I -c "import sys; sys.path.insert(0, '$T/old/hooks'); import common" 2>&1 | tail -1)
case "$out" in "ImportError: regatta: core not found: no REGATTA_HOME and no $T/empty/home"*) r=0 ;; *) r=1 ;; esac
check "$r" 0 "  no home file: one ImportError line naming it"
mkdir -p "$T/eh"; : > "$T/eh/home"
out=$(REGATTA_CONFIG="$T/eh" python3 -I -c "import sys; sys.path.insert(0, '$T/old/hooks'); import common" 2>&1 | tail -1)
check "$out" "ImportError: regatta: core not found: $T/eh/home is empty" "  an empty home file: one ImportError line saying so"
printf 'Kapitän\n' > "$T/config/regatta/owner"   # its own owner, a non-ASCII one, put back empty after
out=$(LC_ALL=en_US.ISO8859-1 LANG=en_US.ISO8859-1 python3 -I -c "import sys; sys.path.insert(0, '$T/old/hooks'); import common; print(ascii(common.DECLARED_LINE))" 2>&1)
check "$out" "'KAPIT\\xc4N, THIS SESSION IS DONE \\u2014 IT LANDS BY ITSELF.'" "  a non-UTF-8 locale: the core and its config decode as an import would"
: > "$T/config/regatta/owner"
mkdir -p "$T/root/.claude-plugin" "$T/root/modules"; : > "$T/root/.claude-plugin/marketplace.json"; cp -R "$M" "$T/root/modules/regatta"
printf '#!/usr/bin/env bash\necho "bash $*"\n' > "$T/root/modules/regatta/bin/.probe-sh"; chmod +x "$T/root/modules/regatta/bin/.probe-sh"
"$T/root/modules/regatta/bin/regatta" shim modules/regatta/bin/.probe-sh > "$T/old/bin/probe"; chmod +x "$T/old/bin/probe"
head -2 "$T/old/bin/probe" | grep -q "Exec shim"; check $? 0 "a bash file gets an exec shim"
check "$(REGATTA_HOME="$T/root" "$T/old/bin/probe" a b)" "bash a b" "  which runs it, args passed"

mkdir -p "$HOME/.config/regatta"; echo "$ROOT" > "$HOME/.config/regatta/home"
out=$(env -i HOME="$HOME" PATH=/usr/bin:/bin /usr/bin/python3 -I -c "import sys; sys.path.insert(0, '$T/old/hooks'); import common; print(common.__file__)")
check "$out" "$core" "  env -i, no REGATTA_CONFIG: the default ~/.config/regatta/home"

echo "cost lint (effective applies to Claude prices, not real money)"
lintcase() {  # $1 line, $2 expected exit, $3 label
  printf '%s\n' "$1" > "$T/case.md"; "$M/bin/cost" lint "$T/case.md" > "$T/case.out"; check "$?" "$2" "$3"
}
lintcase 'The run was $0.' 0 'a $0 amount needs no effective figure'
lintcase 'The run was $0.05.' 1 'a small non-zero amount still does'
lintcase 'A step costs $10 ($0.19 effective).' 0 'a model cost with its effective figure passes'
lintcase 'The plan is $44 a month (list-only).' 0 'real money written plain passes'
lintcase 'The plan is $44 ($0.84 effective) a month.' 1 'an effective figure on a monthly bill warns'
grep -q 'effective figure on real money' "$T/case.out"; check $? 0 "  and says so"
lintcase 'The domain is $12 ($0.23 effective).' 1 'an effective figure after a domain warns'
lintcase 'No rent; a step is $10 ($0.19 effective) and the plan $44 a month (list-only).' 0 'a plain bill beside a Claude figure passes'
lintcase 'Run `echo $1 ($0.2 effective) a month` here.' 0 'real money inside inline code is not read'

echo "secrets"
SC="$M/bin/secrets"; mkdir -p "$T/vault" "$T/sp/r"; ln -s "$T/vault" "$T/vlink"
printf 'A=\n' > "$T/sp/r/.env.example"; printf 'A=1\n' > "$T/vault/r.env"
out=$(SECRETS_DIR="$T/nofolder" SECRETS_PROJECTS="$T/sp" SECRETS_REPOS=/dev/null "$SC" check r 2>&1); check "$?" 1 "no shared folder, no .env: exit 1"
SECRETS_DIR="$T/vlink" SECRETS_PROJECTS="$T/sp" SECRETS_REPOS=/dev/null SECRETS_HOST=h "$SC" check r --fix >/dev/null 2>&1
check "$(readlink "$T/sp/r/.env")" "$(cd "$T/vault" && pwd -P)/r.env" "  --fix links .env to the shared file itself, not through the folder link"
mkdir -p "$T/sp/q"; printf 'A=\n# per-host\nB=\n' > "$T/sp/q/.env.example"; printf 'A=1\n' > "$T/vault/q.env"
SECRETS_DIR="$T/vlink" SECRETS_PROJECTS="$T/sp" SECRETS_REPOS=/dev/null SECRETS_HOST=h "$SC" check q --fix >/dev/null 2>&1
grep -qx 'B=' "$T/vault/q.h.env" 2>/dev/null; check $? 0 "  the run that links it counts the file as in the folder: this host's file made"
out=$(SECRETS_DIR="$T/nofolder" SECRETS_PROJECTS="$T/sp" SECRETS_REPOS=/dev/null SECRETS_HOST=h "$SC" check q 2>&1); check "$?" 0 "the folder's link missing, a linked repo: read through its link, exit 0"
echo "$out" | grep -qx "ok q: 2 keys"; check $? 0 "  ok, the host file beside it read"
echo "$out" | grep -q "^-- $T/nofolder is missing"; check $? 0 "  the missing link said, as a note"
echo "$out" | grep -q "^-- q: read through its link, in "; check $? 0 "  and where the link reads from"
printf 'A=\nC=\n# per-host\nB=\n' > "$T/sp/q/.env.example"; touch -t 202001010000 "$T/vault/q.env"; cp "$T/vault/q.env" "$T/q.before"
SECRETS_DIR="$T/nofolder" SECRETS_PROJECTS="$T/sp" SECRETS_REPOS=/dev/null SECRETS_HOST=h "$SC" check q --fix >/dev/null 2>&1; check "$?" 1 "  --fix with a key missing: the finding, exit 1"
cmp -s "$T/vault/q.env" "$T/q.before"; check $? 0 "  and nothing written until the link is back"
SECRETS_DIR="$T/vlink" SECRETS_PROJECTS="$T/sp" SECRETS_REPOS=/dev/null SECRETS_HOST=h "$SC" check q --fix >/dev/null 2>&1
grep -qx 'C=' "$T/vault/q.env"; check $? 0 "  with it back, --fix appends"

echo "the plugin"
if command -v claude >/dev/null; then
  claude plugin validate --strict "$ROOT" >/dev/null 2>&1; check $? 0 "claude plugin validate --strict (the marketplace)"
  claude plugin validate --strict "$M" >/dev/null 2>&1; check $? 0 "  and this module"
else
  echo "  skip claude plugin validate: no claude on PATH"
fi

# A newer Python turns an invalid escape into a SyntaxWarning on stderr, which every case that
# reads a tool's output then fails on (CI's ubuntu, 2026-10-18: `\~` in EXEC_SHIM). The Macs' 3.9
# stays quiet, so the compile runs with warnings as errors here.
# Bytes, so compile() decodes as import does (PEP 263), whatever the locale; one interpreter for all.
bad=$(python3 -I -W error - "$ROOT" <<'PY'
import os, sys
root, bad = sys.argv[1], []
files = sorted(os.path.join(d, n) for d, _, ns in os.walk(os.path.join(root, "modules")) for n in ns)
for f in files:
    if not os.path.isfile(f) or os.path.islink(f):
        continue
    with open(f, "rb") as fh:
        src = fh.read()
    if not f.endswith(".py") and b"python" not in src.split(b"\n", 1)[0]:
        continue
    try:
        compile(src, f, "exec")
    except (SyntaxError, SyntaxWarning, DeprecationWarning) as e:
        bad.append("%s (%s)" % (os.path.relpath(f, root), e))
print("; ".join(bad) or "none")
PY
)
check "$bad" none "every module's Python compiles with warnings as errors"

[ "$fails" -eq 0 ] && echo "core: all ok" || echo "core: $fails failed"
[ "$fails" -eq 0 ]
