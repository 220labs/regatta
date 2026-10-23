#!/usr/bin/env bash
# The core's check: where the core, a peer and the private config are found (C2, C3), the private
# values with and without their keys (neutral stand-ins only), the regatta
# CLI, the gate's table order and its write through a config symlink, jev's key files, and the
# shim `regatta shim` makes, under every way a caller loads a file (the design's P5).
# Scratch paths only (a copy of the module where a test writes); nothing under ~/.config or ~/.claude is written,
# and the one read is the autofinish_exclude case's: the caller's config dir's `legacy` file.
#   bash modules/regatta/tests/check.sh
set -u
M="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$(cd "$M/../.." && pwd)"
# the caller's config dir, read before the scratch one replaces it: the autofinish_exclude case names the overlay by it
REAL_RC="${REGATTA_CONFIG:-}" REAL_HOME="$HOME"
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

echo "scopes: the confidential flag and the login (knowledge-layers S1)"
HD="$HOME"; PJ="$HD/projects"; mkdir -p "$PJ/k/memory" "$PJ/z-1" "$HD/.claude" "$HD/.claude-w"
git init -q "$PJ/k"; git -C "$PJ/k" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
git -C "$PJ/k" worktree add -q "$PJ/k-tree" -b w
printf '{"accounts": [{"label": "w", "provider": "claude", "home": "~/.claude-w"}, {"label": "gone", "home": "~/.claude-gone"}]}\n' > "$T/acc.json"
printf '{"repos": {"k": {}, "z-1": {}, "o": {}},\n "scopes": {"node": {"file": "n", "repos": ["k", "z-*"], "confidential": true, "login": "w"},\n  "half": {"file": "h", "repos": ["o"], "confidential": "yes"}}}\n' > "$T/sc.json"
SP() { CLAUDE_REPOS_JSON="$T/sc.json" ACCOUNTS_FILE="$T/acc.json" py "$1"; }
check "$(SP 'print(sorted(common.confidential_scopes()))')" "['node']" "confidential_scopes(): only a real true counts"
check "$(SP 'print(common.scope_members(common.scope_registry()[1]["node"], common.scope_registry()[0]))')" "['k', 'z-1']" \
  "  scope_members(): the named keys, then a glob's"
check "$(SP 'print(common.scope_of_key("z-1"), common.scope_of_key("o"), common.scope_of_key("nope"))')" "node half None" "  scope_of_key()"
check "$(SP 'print(common.scope_login("node"), common.scope_login("half"), common.scope_login("nope"))')" "w None None" "  scope_login()"
check "$(SP 'print([str(p.relative_to(common.PROJECTS)) for p in common.confidential_roots()])')" "['k', 'z-1']" "  confidential_roots(): each repo's checkout"
check "$(SP 'print([p.name for p in common.login_dirs()])')" "['.claude', '.claude-w']" "  login_dirs(): ~/.claude and each row's dir that exists"
out=$(SP 'print("\n".join(str(p) for p in common.scope_paths("node")))')
WT="$(cd "$PJ/k-tree" && pwd -P)"   # git names it by its real path
check "$(printf '%s\n' "$out" | grep -c .)" 11 "  scope_paths(): 2 checkouts + 1 worktree, 2 transcript dirs, a slug folder per login (2) per tree (3)"
printf '%s\n' "$out" | grep -qx "$WT"; check $? 0 "    the worktree, from git worktree list"
printf '%s\n' "$out" | grep -qx "$PJ/k"; check $? 0 "    the checkout by its projects path, once (its real path is no second entry)"
printf '%s\n' "$out" | grep -qx "$PJ/transcripts/z-1"; check $? 0 "    the transcripts folder by the repo's name"
printf '%s\n' "$out" | grep -qx "$HD/.claude-w/projects/$(printf '%s' "$WT" | sed 's/[^A-Za-z0-9]/-/g')"; check $? 0 "    a login's slug folder for the worktree (its transcripts and memory)"
check "$(SP 'print(common.scope_paths("nope"), common.confidential_scopes(path="/no/such"))')" "[] {}" "  an unknown scope, an unreadable registry: empty, no error"
head -c 40 "$T/sc.json" > "$T/torn.json"; printf '{"repos": {"a": {}}, "scopes": {"x": {"repos": 5}, "y": 3}}\n' > "$T/odd.json"
check "$(SP 'print(common.registry_unreadable(), common.registry_unreadable(path="/no/such"), common.registry_unreadable(path="'"$T/torn.json"'"))')" \
  "False False True" "  registry_unreadable(): a torn file is, a good one or none is not (the fence fails closed on it)"
ln -s "$T/moved.json" "$T/dangling.json"
check "$(SP 'print(common.registry_unreadable(path="'"$T/dangling.json"'"))')" "True" "  a registry link whose target moved is unreadable too"
mkdir -p "$T/dcfg/wharf"; ln -s "$T/moved.json" "$T/dcfg/wharf/repos.json"
check "$(REGATTA_CONFIG="$T/dcfg" py 'print(common.registry_unreadable())')" "True" "  the config's own repos.json link, dangling: unreadable, not absent"
check "$(SP 'print(common.scope_of_key("a", path="'"$T/odd.json"'"), common.scope_paths("x", path="'"$T/odd.json"'"))')" "None []" \
  "  a malformed scope: no member, no error"
echo "gather_fence: what a Gather reader may quote (knowledge-layers S4)"
SK=$(printf '%s' "$PJ/k" | sed 's/[^A-Za-z0-9]/-/g')
GF() { SP "f = common.gather_fence($1)
for a in [$2]: print(f(*a) if isinstance(a, tuple) else f(a))" | tr '\n' ' ' | sed 's/ $//'; }
check "$(GF '' "'$PJ/k/docs/x.md', '$WT/a', '$PJ/transcripts/z-1/s.jsonl', '$PJ/o/x', '$PJ/elsewhere'")" "fenced fenced fenced quote quote" \
  "no scope: the confidential scope's checkout, worktree and archive fenced; the rest quoted"
check "$(GF '' "'$HD/.claude/projects/$SK/s.jsonl', '~/.claude-gone/projects/$SK--claude-worktrees-old/m.md', '$HD/.claude/projects/-other/s.jsonl'")" \
  "fenced fenced quote" "  a login's slug folder, a removed worktree's under a login no row lists: fenced by name"
check "$(GF '' "(None, '$PJ/o/x'), ('$PJ/o/x', '$PJ/k'), (), (None,)")" "quote fenced fenced fenced" \
  "  any fenced path fences the item; one with no path is never quoted"
check "$(GF '"half"' "'$PJ/o/x', '$PJ/k/x', '$PJ/elsewhere', ()")" "quote fenced outside outside" \
  "--scope of an open scope: its own quoted, the confidential one still fenced, the rest outside"
check "$(GF '"node"' "'$PJ/k/x', '$HD/.claude-w/projects/$SK/s.jsonl', '$PJ/o/x'")" "quote quote outside" \
  "--scope of the confidential scope: it reads itself, nothing else"
check "$(SP 'f = common.gather_fence(path="'"$T/no-registry.json"'"); print(f(), f("'"$PJ/k/x"'"))')" "quote quote" \
  "  no registry, so no confidential scope: a path-less item is quoted as before S4"
check "$(SP '
try: common.gather_fence("nope")
except ValueError as e: print(e)')" "no scope 'nope' in the registry" "  a scope the registry lacks: ValueError"
check "$(SP 'f = common.gather_fence(path="'"$T/torn.json"'"); print(f("'"$PJ/o/x"'"))')" "fenced" \
  "  a torn registry: everything fenced (fails closed)"
check "$(SP '
try: common.gather_fence("half", path="'"$T/torn.json"'")
except ValueError as e: print("refused")')" "refused" "  and a scope asked of it: ValueError"
printf '{"repos": {"a": {}}, "scopes": {"y": {"repos": ["a"], "yard": "studio"}, "n": {"repos": [], "yard": null}, "x": {"repos": []}, "e": {"repos": [], "yard": ""}}}\n' > "$T/yards.json"
check "$(CLAUDE_REPOS_JSON="$T/yards.json" py 'print(common.scope_yard("y"), common.scope_yard("n"), common.scope_yard("x"), common.scope_yard("e"), common.scope_yard("nope"))')" \
  "studio None None None None" "scope_yard() (skipper-resilience S2): a host; null, absent, empty or no such scope: None"
check "$(CLAUDE_REPOS_JSON="$T/yards.json" py 'print(common.scope_yards(), common.scope_yards(path="/no/such"))')" "{'y': 'studio'} {}" \
  "  scope_yards(): only the scopes with one; an unreadable registry: none"
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
check "$(py 'print(repr(common.ADDRESS), common.DECLARED_LINE)')" "'' THIS SESSION IS DONE — IT LAUNCHES BY ITSELF." "no overlay, no keys: the closing lines address no one"
check "$(py 'print(common.closing_kind(common.FINISH_LINES[0]), common.closing_kind(common.WAITING_PREFIX + "D1"))')" "done waiting" "  and still read as closing lines"
check "$(py 'print(common.closing_kind(common.PENDING_PREFIX + "the reviewers"), common.closing_kind(common.PENDING_PREFIX), common.unrelayed_ask("x\n\n" + common.PENDING_PREFIX + "the check"))')" "pending None None" \
  "  WAITING FOR SOMETHING reads as pending, needs its what, and is no ask to relay"
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
check "$(py 'print(common.DECLARED_LINE)')" "KAPITÄN, THIS SESSION IS DONE — IT LAUNCHES BY ITSELF." "regatta/owner: the closing lines address it, upper-cased"
check "$(py 'print(common.closing_kind("KAPITÄN, THIS WAS ONLY THE PICKUP — CLOSE THIS SESSION. THE WORK CONTINUES IN THE NEW TAB."), common.closing_kind("THIS SESSION IS DONE — IT LANDS BY ITSELF."), common.closing_kind("THIS SESSION IS DONE — IT LAUNCHES BY ITSELF."))')" "done None None" "  every pattern opens with it; an unaddressed line, old or new, is none"
check "$(py 'print(common.ending("x\nKAPITÄN, THIS SESSION IS DUN")[2])')" "('unknown', 'KAPITÄN, THIS SESSION IS DUN')" "  an addressed line that is no closing line: unknown"
check "$(py 'print(common.DECLARED_LINES[0]); print(common.DECLARED_LINE in common.DECLARED_LINES)')" "KAPITÄN, THIS SESSION IS DONE — IT LAUNCHES BY ITSELF.
True" "the rename's declared lines: the new one addressed too, the old one still among them"
check "$(py 'print(common.DECLARED_LINE == common.DECLARED_LINES[0], common.DECLARED_LINES[1])')" "True KAPITÄN, THIS SESSION IS DONE — IT LANDS BY ITSELF." "  the line said is the new one (S4); the old one is still read until S8"
check "$(py 'print(common.closing_kind("KAPITÄN, THIS SESSION IS DONE — IT LAUNCHES BY ITSELF."), common.closing_kind("KAPITÄN, THIS SESSION IS DONE — IT LANDS BY ITSELF."))')" "done done" "  both read as done"
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
check "$(py 'print(common.ADDRESS, common.closing_kind("O’HARA, THIS SESSION IS DONE — IT LANDS BY ITSELF."), common.closing_kind("O’HARA, THIS SESSION IS DONE — IT LAUNCHES BY ITSELF."))')" "O'HARA,  done done" "a typographic apostrophe in the name: straight, as bare() reads a line"
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

# a name no module has (`pr` was this case until wharf took it, B5)
mkdir -p "$T/legacy/bin"; printf '#!/bin/sh\necho legacy "$@"\n' > "$T/legacy/bin/old-tool"; chmod +x "$T/legacy/bin/old-tool"
echo "$T/legacy" > "$T/config/legacy"
check "$(py 'print(common.tool("old-tool"))')" "$T/legacy/bin/old-tool" "  the legacy file reaches a file not moved yet"
CC="$T/claude"; mkdir -p "$CC/plugins" "$T/cache/wharf/1/bin" "$T/proj/sub"; : > "$T/cache/wharf/1/bin/finish-x"
printf '{"plugins": {"wharf@regatta": [{"scope": "project", "projectPath": "%s", "installPath": "%s"}]}}\n' "$T/proj" "$T/cache/wharf/1" > "$CC/plugins/installed_plugins.json"
cp -R "$M" "$T/cache-core"   # a core outside any checkout, as in a plugin cache
cpy() { (cd "$1" && CLAUDE_CONFIG_DIR="$CC" python3 -I -c "import sys; sys.path.insert(0, '$T/cache-core/hooks'); import common; $2"); }
check "$(cpy "$T/proj/sub" 'print(common.tool("finish-x"))')" "$T/cache/wharf/1/bin/finish-x" "from a cache: a project row's installPath, cwd inside it"
check "$(cpy "$T" 'print(common.tool("finish-x"))')" "None" "  cwd outside the project: not found"
check "$(cpy "$T/proj" 'print(common.module_path("wharf"))')" "$T/cache/wharf/1" "  module_path() reads the same row"
mkdir "$T/gonecwd"
check "$(cd "$T/gonecwd" && rmdir "$T/gonecwd" && CLAUDE_CONFIG_DIR="$CC" python3 -I -c "import sys; sys.path.insert(0, '$T/cache-core/hooks'); import common; print(common.tool('nope'))" 2>&1)" "None" "  a removed cwd: None, no traceback"

echo "the rename's readers (both words count)"
old='2026-10-18T10:00:00-07:00 run r claude/x landed pr=#3 session=s tip=t rule=C by=sweep — ok'  # the old word, kept beside launched: the map keeps a line holding both
new='2026-10-18T10:00:00-07:00 run r claude/x launched pr=#3 session=s tip=t rule=C by=sweep account=a — ok'
check "$(py "print(bool(common.RUN_LAUNCHED.match('$old')), bool(common.RUN_LAUNCHED.match('$new')), common.RUN_LANDED is common.RUN_LAUNCHED)")" "True True True" "RUN_LAUNCHED reads an old and a new run line; RUN_LANDED is its old name"
check "$(py 'print(common.autofinish_outcome({"outcome": "landed", "pr": 3})); print(common.autofinish_outcome({"outcome": "launched", "pr": 4}))')" "this branch launched as #3
this branch launched as #4" "autofinish_outcome: both words merged the branch, said in the new word (rename S3)"
mkdir -p "$T/cd/claude"; printf '2026-10-18T10:00 landed claude/a #1\n2026-10-18T11:00 launched claude/b #2\n' > "$T/cd/claude/autofinished"
check "$(py 'print([(e["outcome"], common.autofinished_phrase(e)) for e in common.autofinished("'"$T/cd"'")])')" "[('landed', 'claude/a launched as #1'), ('launched', 'claude/b launched as #2')]" "  autofinished takes both; its phrase says launched for each"
check "$(py 'print(common.REFUSED_GATES)')" "('refused', 'not-launched')" "REFUSED_GATES: the gate word and its old one"

echo "the CLI"
check "$("$RG" root)" "$ROOT" "regatta root"
check "$("$RG" has regatta)" "$M" "regatta has regatta"
# helm absent: a core-only copy of the checkout, since this one holds helm since B12 (AGENTS.md's
# "peer absent" trap); the legacy checkout above holds no helm either
CO="$T/core-only"; mkdir -p "$CO/.claude-plugin" "$CO/modules"; cp "$ROOT/.claude-plugin/marketplace.json" "$CO/.claude-plugin/"
cp -R "$M" "$CO/modules/"
out=$("$CO/modules/regatta/bin/regatta" has helm); check "$?:$out" "1:helm not installed" "regatta has helm: not installed, exit 1"
out=$("$CO/modules/regatta/bin/regatta" helm board 2>&1); check "$?:$out" "2:regatta: helm not installed" "regatta helm …: one line, exit 2 (G28)"
if [ -d "$ROOT/modules/helm" ]; then
  check "$("$RG" which helm)" "$ROOT/modules/helm/libexec/helm" "regatta which helm: libexec/, off PATH (C1)"
fi
check "$("$RG" old-tool ready 7)" "legacy ready 7" "regatta <tool> …: runs the tool where it is, args passed"
out=$("$RG" which 2>&1); check "$?:$out" "2:regatta which: wrong arguments — \`regatta help\`" "regatta which, no name: a usage error, exit 2"
rm "$T/config/legacy"
out=$("$RG" check); check "$?" 1 "regatta check without a home: exit 1"
echo "$out" | grep -q -- "--  home: none"; check $? 0 "  it says so"
out=$(REGATTA_HOME="$ROOT" "$RG" check); check "$?" 1 "  REGATTA_HOME set, still no home file: exit 1"
echo "$ROOT" > "$T/config/home"; ln -s "$T/gone" "$T/config/regatta/broken"
out=$("$RG" check); check "$?" 1 "  a dangling link: exit 1"
echo "$out" | grep -q -- "--  regatta/broken → $T/gone (missing)"; check $? 0 "  it names the link and its target"
rm "$T/config/regatta/broken"; out=$("$RG" check); check "$?" 0 "  all well: exit 0"
# a module's own keys (modules/<m>/config-keys): said by the check, never by the core's import
mkdir -p "$T/config/wharf-runs/ssh"; out=$("$RG" check); check "$?" 1 "  a module's key that cannot be read: exit 1"
echo "$out" | grep -q -- "--  wharf-runs/ssh unreadable"; check $? 0 "  it names the key"
rmdir "$T/config/wharf-runs/ssh"
for k in owner guarded orca-deny; do echo x > "$T/config/regatta/$k"; done
echo "$T/logs" > "$T/config/regatta/log-dir"; echo "$T/repos" > "$T/config/regatta/projects"; echo "$T" > "$T/config/legacy"
out=$("$RG" check); check "$?" 1 "  an overlay without a module's keys: exit 1"
check "$(echo "$out" | grep -c -- '^  --  wharf-runs/\(orca-pairs\|ssh\) missing')" 2 "  each missing key named"
check "$(py 'print(common.CONFIG_PROBLEMS)')" "[]" "  and the core still loads: a module's key is not the core's"
printf 'a:b\n' > "$T/config/wharf-runs/orca-pairs"; printf 'b:c\n' > "$T/config/wharf-runs/ssh"
# every other module's listed keys too (lighthouse's since B9): this case is about wharf-runs'
for k in $(cat "$ROOT"/modules/*/config-keys 2>/dev/null | grep -v '^#'); do
  [ -e "$T/config/$k" ] || { mkdir -p "$(dirname "$T/config/$k")"; echo x > "$T/config/$k"; }
done
out=$("$RG" check); check "$?" 0 "  with them written: exit 0"
rm -r "$T/config/wharf-runs" "$T/config/legacy"; for k in owner guarded orca-deny log-dir projects; do rm "$T/config/regatta/$k"; done
# the yard rows (skipper-resilience S2): one per scope, its yard or none, a host lighthouse/hosts does not list a finding
mkdir -p "$T/config/lighthouse"; printf 'laptop\nstudio\n' > "$T/config/lighthouse/hosts"
printf '{"repos": {"a": {}, "b": {}, "c": {}},\n "scopes": {"one": {"file": "o", "repos": ["a"], "yard": "studio"}, "two": {"file": "t", "repos": ["b"], "yard": null}, "three": {"file": "h", "repos": ["c"]}}}\n' > "$T/yd.json"
out=$("$RG" check); check "$?:$(echo "$out" | grep -c ' yard: ')" "0:0" "  no registry: no yard rows"
out=$(CLAUDE_REPOS_JSON="$T/yd.json" "$RG" check); check "$?" 0 "  every yard a listed host or none: exit 0"
check "$(echo "$out" | grep -c '^  ok  scope [a-z]* yard: ')" 3 "  one row per scope"
echo "$out" | grep -qx "  ok  scope one yard: studio"; check $? 0 "    a yard by its host"
echo "$out" | grep -qx "  ok  scope two yard: none"; check $? 0 "    null: none"
echo "$out" | grep -qx "  ok  scope three yard: none"; check $? 0 "    absent: none"
sed 's/"studio"/"nowhere"/' "$T/yd.json" > "$T/yd2.json"
out=$(CLAUDE_REPOS_JSON="$T/yd2.json" "$RG" check); check "$?" 1 "  a yard lighthouse/hosts does not list: exit 1"
echo "$out" | grep -qx -- "  --  scope one yard: nowhere is not a host lighthouse/hosts lists (laptop, studio)"; check $? 0 "    it names the scope, the host and the list"
head -c 30 "$T/yd.json" > "$T/yd3.json"
out=$(CLAUDE_REPOS_JSON="$T/yd3.json" "$RG" check); check "$?:$(echo "$out" | grep -c ' yard: ')" "1:0" "  a torn registry: exit 1, no row read from it"
rm -r "$T/config/lighthouse"

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
check "$out" "'KAPIT\\xc4N, THIS SESSION IS DONE \\u2014 IT LAUNCHES BY ITSELF.'" "  a non-UTF-8 locale: the core and its config decode as an import would"
: > "$T/config/regatta/owner"
mkdir -p "$T/root/.claude-plugin" "$T/root/modules"; : > "$T/root/.claude-plugin/marketplace.json"; cp -R "$M" "$T/root/modules/regatta"
printf '#!/usr/bin/env bash\necho "bash $*"\n' > "$T/root/modules/regatta/bin/.probe-sh"; chmod +x "$T/root/modules/regatta/bin/.probe-sh"
"$T/root/modules/regatta/bin/regatta" shim modules/regatta/bin/.probe-sh > "$T/old/bin/probe"; chmod +x "$T/old/bin/probe"
head -2 "$T/old/bin/probe" | grep -q "Exec shim"; check $? 0 "a bash file gets an exec shim"
check "$(REGATTA_HOME="$T/root" "$T/old/bin/probe" a b)" "bash a b" "  which runs it, args passed"
# A deny hook's shim (C4): with no core it refuses a PreToolUse call, exit 0, rather than dying
# with exit 1 — which Claude Code reads as no objection. With a core it is the plain shim.
printf 'import sys\nprint("module", __file__)\n' > "$T/root/modules/regatta/hooks/probe_deny.py"
"$T/root/modules/regatta/bin/regatta" shim --deny modules/regatta/hooks/probe_deny.py > "$T/old/hooks/probe_deny.py"; check $? 0 "regatta shim --deny writes a deny hook's shim"
grep -q 'Made by `regatta shim --deny modules/regatta/hooks/probe_deny.py`' "$T/old/hooks/probe_deny.py"; check $? 0 "  saying how it was made"
check "$(echo '{}' | REGATTA_HOME="$T/root" python3 "$T/old/hooks/probe_deny.py")" "module $T/root/modules/regatta/hooks/probe_deny.py" "  with a core: the module runs, its own __file__"
out=$(echo '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"git commit -m x"}}' \
  | env -u REGATTA_HOME REGATTA_CONFIG="$T/empty" python3 "$T/old/hooks/probe_deny.py" 2>"$T/deny.err"; echo "rc=$?")
check "$(echo "$out" | head -1 | python3 -c 'import json,sys; print(json.load(sys.stdin)["hookSpecificOutput"]["permissionDecision"])')" "deny" "  no core, PreToolUse: denied"
check "$(echo "$out" | tail -1) $(grep -c 'a deny hook: refusing' "$T/deny.err")" "rc=0 1" "  exit 0, one line on stderr"
check "$(echo '{"hook_event_name":"Stop"}' | env -u REGATTA_HOME REGATTA_CONFIG="$T/empty" python3 "$T/old/hooks/probe_deny.py" 2>/dev/null; echo "rc=$?")" "rc=0" "  no core, any other event: nothing, exit 0"
pull() { jq -nc --arg c "$1" '{hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$c}}' \
  | env -u REGATTA_HOME REGATTA_CONFIG="$T/empty" python3 "$T/old/hooks/probe_deny.py" 2>/dev/null; }
check "$(pull "git -C $T/root pull --ff-only"; echo "rc=$?")" "rc=0" "  no core: a plain pull --ff-only of a checkout passes, the repair"
check "$(pull 'git -C /x pull --ff-only; rm -rf /x' | grep -c '"deny"')" "1" "  …but not one with a shell operator after it"
check "$(pull 'git -C /x fetch --upload-pack /tmp/e.sh /x' | grep -c '"deny"')" "1" "  …nor one carrying an option that runs a program (B9 review)"
check "$(pull 'git -C /x fetch -u /tmp/e.sh /x' | grep -c '"deny"')" "1" "  …in its short form either"
check "$(pull "git -C $T/root fetch --all --prune"; echo "rc=$?")" "rc=0" "  a fetch --all --prune passes, a usual repair"
prompt() { echo '{"hook_event_name":"UserPromptSubmit"}' | env -u REGATTA_HOME REGATTA_CONFIG="$T/empty" "$@" 2>/dev/null; echo "rc=$?"; }
check "$(prompt env CLAUDE_CONFIG_DIR=/x python3 "$T/old/hooks/probe_deny.py")" "rc=0" "  --deny, no core, a prompt in a secondary login dir: passes (checkpoint's B5 choice)"
# A prompt guard's shim (`--deny-prompt`, B9 review): DENY_TAIL, and a prompt in a secondary
# login dir is blocked with no core, as account_guard blocks when bin/account cannot run.
"$T/root/modules/regatta/bin/regatta" shim --deny-prompt modules/regatta/hooks/probe_deny.py > "$T/old/hooks/probe_prompt.py"; check $? 0 "regatta shim --deny-prompt writes a prompt guard's shim"
check "$(echo '{}' | REGATTA_HOME="$T/root" python3 "$T/old/hooks/probe_prompt.py")" "module $T/root/modules/regatta/hooks/probe_deny.py" "  with a core: the module runs"
out=$(prompt env CLAUDE_CONFIG_DIR=/x python3 "$T/old/hooks/probe_prompt.py")
check "$(echo "$out" | head -1 | python3 -c 'import json,sys; print(json.load(sys.stdin)["decision"])') $(echo "$out" | tail -1)" "block rc=0" "  no core, a prompt in a secondary login dir: blocked, exit 0"
check "$(prompt env -u CLAUDE_CONFIG_DIR python3 "$T/old/hooks/probe_prompt.py")" "rc=0" "  no core, a prompt in the default login: passes, the repair stays reachable"
check "$(echo '{"hook_event_name":"Stop"}' | env -u REGATTA_HOME REGATTA_CONFIG="$T/empty" CLAUDE_CONFIG_DIR=/x python3 "$T/old/hooks/probe_prompt.py" 2>/dev/null; echo "rc=$?")" "rc=0" "  no core, any other event: nothing, exit 0"
check "$(echo '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"git commit -m x"}}' | env -u REGATTA_HOME REGATTA_CONFIG="$T/empty" python3 "$T/old/hooks/probe_prompt.py" 2>/dev/null | grep -c '"deny"')" "1" "  no core, PreToolUse: denied, as --deny"
# A broken module, not a missing one (B5 review): a conflicted pull's SyntaxError still denies.
cp "$T/root/modules/regatta/hooks/probe_deny.py" "$T/probe_deny.ok"; printf '<<<<<<< ours\n' >> "$T/root/modules/regatta/hooks/probe_deny.py"
out=$(echo '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"git commit -m x"}}' \
  | REGATTA_HOME="$T/root" python3 "$T/old/hooks/probe_deny.py" 2>/dev/null; echo "rc=$?")
check "$(echo "$out" | head -1 | grep -c '"deny"') $(echo "$out" | tail -1)" "1 rc=0" "  a module with conflict markers: denied, exit 0 — never exit 1"
cp "$T/probe_deny.ok" "$T/root/modules/regatta/hooks/probe_deny.py"
out=$(env -u REGATTA_HOME REGATTA_CONFIG="$T/empty" python3 -I -c "import sys; sys.path.insert(0, '$T/old/hooks'); import probe_deny" 2>&1 | tail -1 | cut -c1-12)
check "$out" "ImportError:" "  imported with no core: the ImportError reaches the importer"
check "$("$T/root/modules/regatta/bin/regatta" shim --deny modules/regatta/bin/.probe-sh 2>&1 >/dev/null; echo "rc=$?")" "regatta shim --deny: modules/regatta/bin/.probe-sh is no Python hook
rc=2" "  a bash file: refused"
# Any other hook's shim: with no core, one line and exit 0 (exit 1 printed a traceback at every
# session start); with a core, the module.
"$T/root/modules/regatta/bin/regatta" shim --hook modules/regatta/hooks/probe_deny.py > "$T/old/hooks/probe_hook.py"; check $? 0 "regatta shim --hook writes a hook's shim"
check "$(echo '{}' | REGATTA_HOME="$T/root" python3 "$T/old/hooks/probe_hook.py")" "module $T/root/modules/regatta/hooks/probe_deny.py" "  with a core: the module runs"
out=$(echo '{"hook_event_name":"PreToolUse"}' | env -u REGATTA_HOME REGATTA_CONFIG="$T/empty" python3 "$T/old/hooks/probe_hook.py" 2>"$T/hook.err"; echo "rc=$?")
check "$out $(wc -l < "$T/hook.err" | tr -d ' ')" "rc=0 1" "  no core: no output, exit 0, one line on stderr — never a deny"
out=$(env -u REGATTA_HOME REGATTA_CONFIG="$T/empty" python3 -I -c "import sys; sys.path.insert(0, '$T/old/hooks'); import probe_hook" 2>&1 | tail -1 | cut -c1-12)
check "$out" "ImportError:" "  imported with no core: the ImportError reaches the importer"

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

# Each catalogue entry names its module's folder outright: `plugin validate` passes a bare source
# under metadata.pluginRoot, but `plugin install` (2.1.303) ignores pluginRoot, so a stranger's
# install failed on it (2026-10-19).
bad=$(python3 -I - "$ROOT" <<'PY'
import json, os, sys
root = sys.argv[1]
d = json.load(open(os.path.join(root, ".claude-plugin", "marketplace.json")))
bad = [p["name"] for p in d["plugins"]
       if not (isinstance(p.get("source"), str) and p["source"].startswith("./modules/")
               and os.path.isfile(os.path.join(root, p["source"], ".claude-plugin", "plugin.json")))]
print(" ".join(bad) or "none")
PY
)
check "$bad" none "every marketplace source is ./modules/<name> and holds a plugin.json"

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

# `.claude/workflow.json`'s `autofinish_exclude` is hand-kept: a path a live hook or an overlay shim runs from
# this checkout, missing from it, lands through autofinish unreviewed (the B4-fixes review, 2026-10-20: the core's
# `hooks/` since B1, plumb's and atlas's hooks and `lib/` since B8 and B10). Live = every file under
# `modules/*/hooks|lib|libexec|shell`; a shim the overlay made with a flag (`--hook`, `--deny`: wired into the hooks);
# a `bin/<name>` the AGENTS.md autofinish paragraph names. A plain shimmed tool is not live by itself (the
# paragraph's rule: those that gate or write live state are named in it), so it is counted, not failed.
# The overlay is the `legacy` file of the caller's config dir (the suite's HOME and REGATTA_CONFIG are scratch ones);
# absent (CI, whose job sets its own REGATTA_CONFIG, and the public twin): the shim half is skipped.
echo "autofinish_exclude covers every live path"
out=$(python3 -I - "$ROOT" "$REAL_RC" "$REAL_HOME" <<'PY'
import json, os, re, sys
root = sys.argv[1]
wf = os.path.join(root, ".claude", "workflow.json")
if not os.path.isfile(wf):
    print("SKIP no .claude/workflow.json in this tree (the public twin has none)")
    print("RESULT none")
    sys.exit(0)
exclude = tuple(json.load(open(wf)).get("autofinish_exclude") or ())
live = {}
def rel(path): return os.path.relpath(path, root)
for d in sorted(os.listdir(os.path.join(root, "modules"))):
    for sub in ("hooks", "lib", "libexec", "shell"):
        top = os.path.join(root, "modules", d, sub)
        for dp, _, ns in os.walk(top):
            for n in ns:
                live.setdefault(rel(os.path.join(dp, n)), "a hook, lib or shell file")
agents = os.path.join(root, "AGENTS.md")
if os.path.isfile(agents):
    text = open(agents).read()
    m = re.search(r"^- autofinish:.*?(?=^\S|^- |\Z)", text, re.S | re.M)
    for name in sorted(set(re.findall(r"`bin/([A-Za-z0-9_.-]+)`", m.group(0) if m else ""))):
        for d in sorted(os.listdir(os.path.join(root, "modules"))):
            f = "modules/%s/bin/%s" % (d, name)
            if os.path.isfile(os.path.join(root, f)):
                live.setdefault(f, "a tool AGENTS.md names")
config, home = sys.argv[2] or os.path.join(sys.argv[3], ".config", "regatta"), sys.argv[3]
try:
    with open(os.path.join(config, "legacy"), encoding="utf-8-sig") as fh:
        coding = next((l.strip() for l in fh if l.strip()), "")
except OSError:
    coding = ""
if coding == "~" or coding.startswith("~/"):
    coding = home + coding[1:]
plain = []
if not os.path.isdir(coding):
    print("SKIP no overlay is named: the shim half is not checked")
else:
    pat = re.compile(r"Made by `regatta shim ((?:--[a-z-]+ )*)(\S+?)`")
    for sub in ("bin", "hooks", "shell"):
        for dp, _, ns in os.walk(os.path.join(coding, sub)):
            for n in sorted(ns):
                try:
                    head = open(os.path.join(dp, n), errors="replace").read(2000)
                except OSError:
                    continue
                m = pat.search(head)
                if not m or not os.path.isfile(os.path.join(root, m.group(2))):
                    continue
                flags, path = m.group(1).strip(), m.group(2)
                if flags:
                    live.setdefault(path, "a shim wired as a hook (%s)" % flags)
                elif path not in live:
                    plain.append(path)
bad = ["%s (%s)" % (p, why) for p, why in sorted(live.items()) if not p.startswith(exclude)]
plain = [p for p in sorted(set(plain)) if not p.startswith(exclude) and "/tests/" not in p]
if plain:
    print("NOTE %d shimmed tools land through autofinish, by the paragraph's rule: %s"
          % (len(plain), " ".join(os.path.basename(p) for p in plain)))
print("%d live paths read" % len(live))
print("RESULT " + ("; ".join(bad) or "none"))
PY
)
printf '%s\n' "$out" | grep -v '^RESULT ' | sed 's/^/    /'
check "$(printf '%s\n' "$out" | sed -n 's/^RESULT //p')" none "no live path lies outside autofinish_exclude"

[ "$fails" -eq 0 ] && echo "core: all ok" || echo "core: $fails failed"
[ "$fails" -eq 0 ]
