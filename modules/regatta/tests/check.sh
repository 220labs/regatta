#!/usr/bin/env bash
# The core's check: where the core, a peer and the private config are found (C2, C3), the private
# values with and without their keys (neutral stand-ins only), the regatta
# CLI, the weekly jobs' host rule (common.weekly_host) and its check row, the gate's table order, its module rows and
# its write through a config symlink, jev's key files, and the shim `regatta shim` makes, under every
# way a caller loads a file (the design's P5), and the transcript reader's last main-chain call.
# Scratch paths only (a copy of the module where a test writes); nothing under ~/.config or ~/.claude is written,
# and the one read is the autofinish_exclude case's: the caller's config dir's `regatta/overlay` marker.
#   bash modules/regatta/tests/check.sh
set -u
M="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$(cd "$M/../.." && pwd)"
# the caller's config dir, read before the scratch one replaces it: the autofinish_exclude case names the overlay by it
REAL_RC="${REGATTA_CONFIG:-}" REAL_HOME="$HOME"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
for v in $(env | sed -n 's/^\(REGATTA[A-Za-z0-9_]*\)=.*/\1/p; s/^\(CLAUDE[A-Za-z0-9_]*\)=.*/\1/p; s/^\(GATE_[A-Za-z0-9_]*\)=.*/\1/p; s/^\(DISPATCH_[A-Za-z0-9_]*\)=.*/\1/p'); do unset "$v"; done
unset GATE_TABLE JEV_ENV_FILE JEV_LOG TYPESAFE_API_KEY TYPESAFE_BASE_URL COST_RATIO SECRETS_DIR SECRETS_REPOS SECRETS_PROJECTS SECRETS_HOST
# The interpreter itself, for the two cases that must not start any other process: python3 may be a
# shim script (pyenv's is bash), and bash started in a removed cwd prints "shell-init: error retrieving
# current directory" and, under an unavailable LC_ALL, "setlocale: LC_ALL: cannot change locale" on
# Linux, into the output the case compares (CircleCI's Ubuntu VM, 2026-10-26). Resolved before HOME moves,
# which a shim reads its versions from.
PYBIN="$(python3 -c 'import sys; print(sys.executable)')"
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
printf '{"accounts": [{"label": "w", "provider": "claude", "home": "~/.claude-w"}, {"label": "gone", "home": "~/.acct-gone"}]}\n' > "$T/acc.json"
printf '{"repos": {"k": {}, "z-1": {}, "o": {}},\n "scopes": {"node": {"file": "n", "repos": ["k", "z-*"], "confidential": true, "login": "w"},\n  "half": {"file": "h", "repos": ["o"], "confidential": "yes"}}}\n' > "$T/sc.json"
SP() { CLAUDE_REPOS_JSON="$T/sc.json" ACCOUNTS_FILE="$T/acc.json" py "$1"; }
check "$(SP 'print(sorted(common.confidential_scopes()))')" "['node']" "confidential_scopes(): only a real true counts"
check "$(SP 'print(common.scope_members(common.scope_registry()[1]["node"], common.scope_registry()[0]))')" "['k', 'z-1']" \
  "  scope_members(): the named keys, then a glob's"
check "$(SP 'print(common.scope_of_key("z-1"), common.scope_of_key("o"), common.scope_of_key("nope"))')" "node half None" "  scope_of_key()"
check "$(SP 'print(common.scope_login("node"), common.scope_login("half"), common.scope_login("nope"))')" "w None None" "  scope_login()"
check "$(SP 'print(common.scope_marker("node"))')" "confidential:$(printf node | shasum -a 256 | cut -c1-8)" "  scope_marker(): the first 8 hex of the name's sha256, no name (S5)"
check "$(SP 'm = common.scope_marker; print(common.scope_of_marker(m("node")), common.scope_of_marker(m("half")), common.scope_of_marker("node"), common.scope_of_marker(None))')" \
  "node None None None" "  scope_of_marker(): a confidential scope by this registry; an open one, a bare name, none: None"
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
check "$(GF '' "'$HD/.claude/projects/$SK/s.jsonl', '~/.acct-gone/projects/$SK--claude-worktrees-old/m.md', '$HD/.claude/projects/-other/s.jsonl'")" \
  "fenced fenced quote" "  a login's slug folder, a removed worktree's under a login no row lists: fenced by name"
check "$(GF '' "'/tmpdir/c-501/$SK/abc/work/x.txt', '/tmpdir/c-501/$SK--claude-worktrees-t/abc/work', '/tmpdir/c-501/-other/abc/work'")" \
  "fenced fenced quote" "  a session's scratch folder, under no projects/ folder: fenced by its slug part (trim-cross-host D2)"
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
echo "a scope's data (skipper-modes S1, S6): repo_key, scope_of_repo, the berths check"
printf '{"repos": {"a": {"hosts": ["h1", "h2"]}, "g/x": {"hosts": ["h1"]}}, "scopes": {"s1": {"repos": ["a"], "berths": ["h2", "h1"], "mode": "dnd"}, "s2": {"repos": ["g/*"], "berths": ["h9"]}, "s3": {"repos": [], "berths": "h1"}}}\n' > "$T/sc.json"
check "$(py "print(common.repo_key(str(common.PROJECTS.joinpath('a', '.claude', 'worktrees', 't'))), common.repo_key('g/x'), common.repo_key('/elsewhere/a'))")" \
  "a g/x /elsewhere/a" "repo_key: a worktree is its checkout's key; a key as given; a path outside the projects folder as given"
check "$(CLAUDE_REPOS_JSON="$T/sc.json" py "n, s = common.scope_of_repo('a'); print(n, s.get('mode'), s.get('berths'), common.scope_of_repo('g/x')[0], common.scope_of_repo('nope'))")" \
  "s1 dnd ['h2', 'h1'] s2 (None, {})" "scope_of_repo: by name or glob, the scope's own data; none for a repo in no scope"
echo "the unattended marker, both names (vendor-fence's stage 1)"
check "$(py 'print(common.unattended({}), common.unattended({"CLAUDE_UNATTENDED": "old"}), common.unattended({"REGATTA_UNATTENDED": "new"}), common.unattended({"REGATTA_UNATTENDED": "new", "CLAUDE_UNATTENDED": "old"}), common.unattended({"CLAUDE_UNATTENDED": ""}))')" \
  "None old new new None" "unattended(): the new name first, the old name alone still honoured, an empty value is none"
check "$(CLAUDE_UNATTENDED=dispatch py 'print(common.unattended(), common.unattended_label())')" "dispatch CLAUDE_UNATTENDED=dispatch" \
  "  from the environment: only the old name set, the run reads unattended and a refusal quotes that name"
check "$(py 'print(sorted(common.unattended_env("dispatch").items()))')" "[('CLAUDE_UNATTENDED', 'dispatch'), ('REGATTA_UNATTENDED', 'dispatch')]" \
  "  unattended_env(): what a launcher sets, both names"
echo "the vendor fence (vendor-fence, docs/codex-agy-gaps-2026-10-29.md F1)"
VF="$T/vf"; mkdir -p "$VF"; git init -q -b main "$VF/conf"; git -C "$VF/conf" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
git -C "$VF/conf" worktree add -q -b w "$VF/conf-side"; VF=$(cd "$VF" && pwd -P); mkdir -p "$VF/open"
# an umbrella scope sorts first and holds every repo: scope_of_repo's first match would call conf open
printf '{"repos": {}, "scopes": {"all": {"repos": ["*"]}, "conf": {"confidential": true, "repos": ["%s"]}, "half": {"confidential": "yes", "repos": ["%s"]}}, "guarded": ["g"]}\n' \
  "$VF/conf" "$VF/open" > "$T/vf.json"
cat > "$T/acct" <<'SH'
#!/bin/sh
echo "$*" >> "$(dirname "$0")/acct.calls"
printf '%s\n' "{\"account\": \"codex-x\", \"provider\": \"codex\", \"owns\": ${OWNS:-false}, \"skipped\": []}"
SH
chmod +x "$T/acct"
VFP() { CLAUDE_REPOS_JSON="$T/vf.json" py "$1"; }
check "$(VFP 'import json; r, _ = common.read_registry(); print(common.fenced_scopes("'"$VF/conf"'", r), common.fenced_scopes("'"$VF/conf-side"'", r), common.fenced_scopes("'"$VF/open"'", r), common.fenced_scopes("g", r))')" \
  "['conf'] ['conf'] [] ['guarded']" "fenced_scopes(): every scope walked; a worktree beside its checkout, found by git; a non-true flag is open; the guarded list"
mkdir -p "$T/vfcfg/regatta"; printf 'Cfg-Only\n' > "$T/vfcfg/regatta/guarded"
check "$(REGATTA_CONFIG="$T/vfcfg" VFP 'r, _ = common.read_registry(); print(common.fenced_scopes("cfg-only", r), common.fenced_scopes("G", r), common.fenced_scopes("transcripts", r))')" \
  "['guarded'] ['guarded'] ['guarded']" "  and the guarded names every other guard reads: the config dir's regatta/guarded, the transcript archive, case-folded (landing review)"
check "$(VFP 'print(common.vendor_refusal("'"$VF/conf"'", "claude", account="'"$T/acct"'"), common.vendor_refusal("'"$VF/open"'", "codex", account="'"$T/acct"'"))')" \
  "None None" "vendor_refusal(): a Claude run's rule unchanged; an open repo passes with no pick"
check "$(test -e "$T/acct.calls" && echo asked || echo none)" "none" "  and no login was asked for either"
out=$(VFP 'print(common.vendor_refusal("'"$VF/conf-side"'", "codex", account="'"$T/acct"'"))')
case "$out" in *"in confidential scope conf: its text goes only to a login its tenant owns, and the codex login account pick names, codex-x, is not one"*) r=refused;; *) r="$out";; esac
check "$r" "refused" "  a confidential repo's worktree, a Codex login no tenant owns: refused, naming the scope and the login"
grep -q -- "pick --provider codex --repo $VF/conf-side --json --cached" "$T/acct.calls"; check $? 0 "  account pick asked for the vendor and the repo, from its cache"
check "$(OWNS=true VFP 'print(common.vendor_refusal("'"$VF/conf"'", "codex", account="'"$T/acct"'"))')" "None" "  a login its tenant owns: passes"
check "$(VFP 'print(common.vendor_refusal("'"$VF/conf"'", "codex", account="/no/such/account") is not None)')" "True" "  bin/account that does not run: refused (fails closed)"
printf '{"repos": {"x": ' > "$T/vf-torn.json"
check "$(CLAUDE_REPOS_JSON="$T/vf-torn.json" py 'print(common.vendor_refusal("'"$VF/open"'", "codex", account="'"$T/acct"'"))')" \
  "the scope registry does not read: no codex run opens a repo until it does" "  a torn registry: every repo refused, an open one too"
out=$(CLAUDE_REPOS_JSON="$T/sc.json" "$RG" check 2>&1)
echo "$out" | grep -q -- "--  registry: scope s2's berths name h9, which no repo is cloned on"; check $? 0 "regatta check: a berth no repo is cloned on is named"
echo "$out" | grep -q -- "--  registry: scope s3's berths is a list of host names"; check $? 0 "  and berths that are no list"
echo "$out" | grep -q -- "scope s1's berths"; check $? 1 "  a scope whose berths are all known hosts is not (its yard row is another line)"
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
check "$(py 'I = common.IDLE_PREFIX; print(common.closing_kind(I + "the answer is above"), common.closing_kind(I), common.unrelayed_ask("x\n\n" + I + "answered"), common.asks_answers("x\n\n" + I + "D2 is answered"))')" "idle None None False" \
  "  WAITING FOR NOTHING reads as idle, needs its what, and is no ask to relay or to answer (2026-10-29)"
check "$(py 'W = common.WAITING_PREFIX + "pick A"; M = common.marked("waiting", W); print(common.closing_kind(M), common.bare("**" + M + "**") == W, repr(common.mark_of(M)), repr(common.mark_of(W)), common.ending_mark("x\n\n" + M)[1] == common.MARKS["waiting"], common.ending_mark("x\n\n\u2705\ufe0f " + common.IDLE_PREFIX + "ok")[1] == common.MARKS["idle"], sorted({k for k, _ in common.CLOSING} ^ set(common.MARKS)))')" \
  "waiting True '🛑' '' True True []" \
  "  a mark before a closing line: bare() drops it, mark_of() and ending_mark() read it (U+FE0F aside), every kind has one"
check "$(py 'A = common.ADDRESS; print(common.bare("\U0001F6D1" + common.WAITING_PREFIX + "x") == common.WAITING_PREFIX + "x", common.mark_of("\U0001F6D1" + common.WAITING_PREFIX + "x"), common.mark_for(A + "THIS SESSION MOVED TO peer — CLOSE THIS TAB. THE WORK CONTINUES THERE ONCE YOU START IT: claude"), common.mark_for(A + "THIS SESSION MOVED TO peer — CLOSE THIS TAB. THE WORK CONTINUES THERE."), common.mark_for(A + "THIS SESSION IS READY TO MOVE TO laptop — CLOSE THIS TAB. TYPE x"))')" \
  "True 🛑| 🛑 ✅ 🛑" \
  "  a mark with no space still strips (and reads as unspaced); a move that leaves the owner a step wants 🛑 (landing review, 2026-10-29)"
check "$(py 'P = common.PENDING_PREFIX; print(common.closing_kind(common.HANDOVER_LINE), common.closing_kind(P + "dispatch\x27s yolo launch (autofinish-run --by yolo), which starts once this run ends"), common.closing_kind(P + "dispatch to start the yolo launch of B14b ([x#1](https://example.com/x/pull/1)) now"), common.closing_kind(P + "the two reviewers, then dispatch\x27s launch"), common.closing_kind(P + "dispatch\x27s tidier"), common.unrelayed_ask("x\n\n" + common.HANDOVER_LINE))')" \
  "handed handed handed pending pending None" \
  "  the hand-over reads as handed (the fixed line and the two free forms of 2026-10-24); a line naming something else first stays pending"
check "$(py 'print(common.OVERRIDE_BY, common.ORCA_ROW["repos"]["deny"])')" "owner []" "  the override marker is owner's, no repo denied an Orca login"
check "$(py 'print(common.orca_row("x")["rules"]["free_below"], common.orca_row("x")["rules"]["window_max"])')" "70 50" "  an unnamed Orca login runs freely under 70% of its 5-hour window, as every registry row (pace-window)"
check "$(jp 'print(j.GUARDED, j.WHO)')" "() the owner" "  jev guards nothing and asks the owner"
check "$(jp 'print(j.log_dir())')" "$H/.local/state/regatta" "  the logs go to .local/state/regatta in the home folder"
check "$(sp 'print(s.PROJECTS)') $(py 'print(common.PROJECTS)')" "$H/projects $H/projects" "  secrets and cloned_repos() read repos under projects in the home folder"

mkdir -p "$T/config/regatta"; echo "$T/legacy" > "$T/config/regatta/overlay"   # the overlay installed: the keys are its to write
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
rm "$T/config/regatta/overlay"
check "$(refusal py 'pass' | grep -o 'regatta/projects [^—]*')" "regatta/projects is not an absolute path: work " "  with or without the overlay"
# B14b: the `legacy` file (and REGATTA_LEGACY) marks nothing any more; the regatta/overlay marker alone does
echo "$T" > "$T/config/legacy"; mv "$T/config/regatta/owner" "$T/owner.kept"
check "$(REGATTA_LEGACY="$T" refusal py 'pass' | grep -c 'regatta/owner')" "0" "B14b: a legacy file or REGATTA_LEGACY alone marks no overlay — an absent key is its default"
echo "$T" > "$T/config/regatta/overlay"
check "$(refusal py 'pass' | grep -o 'regatta/owner missing')" "regatta/owner missing" "  the regatta/overlay marker does: a key it owes is refused"
rm "$T/config/regatta/overlay" "$T/config/legacy"
check "$(refusal py 'pass' | grep -c 'regatta/owner')" "0" "  no marker: an absent key is its default again"
mv "$T/owner.kept" "$T/config/regatta/owner"

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
# The confidential stopgap (2026-10-26): a confidential scope's repo is guarded as `notes` is, for every
# vendor but Anthropic; a torn registry guards every source. Nothing here reaches a vendor: no
# TypeSafe key is set, and claude is /usr/bin/false — an error that is no refusal is the call going ahead.
printf '{"repos": {"lab/vault": {}, "lab/site": {}, "open": {}}, "scopes": {"s1": {"repos": ["lab/*"], "confidential": true}, "s2": {"repos": ["open"]}}}\n' > "$T/conf.json"
cref() { CLAUDE_REPOS_JSON="${3:-$T/conf.json}" GATE_LOG="$T/conf-gate.jsonl" JEV_LOG="$T/conf-jev.jsonl" GATE_EXAMPLE_CLASSIFY_PROVIDER="${2:-jev}" CLAUDE_BIN=/usr/bin/false gp 'try: g.classify("example.classify", {"s1": "a"}, "Q?", {"yes": "y", "no": "n"}, source="'"$1"'", approved={"anthropic": "x"}, timeout=5, attempts=1)
except g.GateError as e: print(e)'; }
check "$(cref vault)" "example.classify: refused: data from vault goes to typesafe only with Kapitän's say-so — approved has no 'typesafe' quote (it has: anthropic)" \
  "the gate: a confidential scope's repo (by its basename, as review-gate names it) goes to Jev only on a quote"
check "$(cref lab/site codex)" "example.classify: refused: data from lab/site goes to openai only with Kapitän's say-so — approved has no 'openai' quote (it has: anthropic)" \
  "  by its registry key, and to any other vendor but Anthropic"
check "$(test -e "$T/conf-gate.jsonl"; echo $?)" "1" "  refused before a line is logged: nothing was sent"
check "$(cref "$H/work/lab/vault/docs")" "example.classify: refused: data from $H/work/lab/vault/docs goes to typesafe only with Kapitän's say-so — approved has no 'typesafe' quote (it has: anthropic)" \
  "  by a path inside its checkout"
check "$(cref "$H/work/lab/vaulted" | grep -c ': refused: ')" "0" "    and not by one beside it"
check "$(cref vault claude | grep -c ': refused: ')" "0" "  Claude needs no quote for it"
check "$(cref open | grep -c ': refused: ')$(cref open | grep -c 'TYPESAFE_API_KEY')" "01" "an open scope's repo goes ahead as before (to the key's read)"
CLAUDE_REPOS_JSON="$T/conf.json" jp 'print(*(j.confidential(x) for x in ("vault", "Vault", "open", None, "?", "lab", "'"$H/work"'", "'"$H/work/lab"'", "'"$H/work/open"'")))' > "$T/conf.out"
check "$(cat "$T/conf.out")" "True True False True True True True True False" \
  "  jev.confidential: the scope's repo in any case, not an open one; no source or '?' (unknown is never sent), its group folder and the projects folder are"
check "$(CLAUDE_REPOS_JSON="$T/no-conf.json" jp 'print(j.confidential(None), j.confidential("?"))')" "False False" "    unknown goes ahead where no scope is confidential"
check "$(CLAUDE_REPOS_JSON="$T/conf.json" jp 'try: j.ask("s", {"q": {"type": "noul", "instructions": "x"}}, source="vault")
except j.JevError as e: print(e)')" 'refused: data from vault goes to TypeSafe only with Kapitän'"'"'s say-so — ask, then pass approved="Kapitän, <date>: <what>"' \
  "  jev.ask itself refuses a confidential repo's data without a quote (a bench's direct call)"
printf '{"repos": {"open": {}}, "scopes": <<<<<<< HEAD\n' > "$T/torn.json"
check "$(cref open jev "$T/torn.json")" "example.classify: refused: data from open goes to typesafe only with Kapitän's say-so — approved has no 'typesafe' quote (it has: anthropic)" \
  "  a torn registry: every source is guarded (fails closed)"
check "$(cref open claude "$T/torn.json" | grep -c ': refused: ')" "0" "    bar Anthropic's"
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
echo "$T/legacy" > "$T/config/regatta/overlay"; echo "$T/legacy" > "$T/config/legacy"
check "$(REGATTA_LEGACY="$T/legacy" py 'print(common.tool("old-tool"))')" "None" "  B14b: the overlay's checkout is no fallback (nor the legacy file, nor REGATTA_LEGACY)"
check "$(py 'print(common.overlay_root(), common.legacy_root is common.overlay_root)')" "$T/legacy True" "  overlay_root() reads the marker's line; legacy_root is its old name"
rm "$T/config/legacy"
CC="$T/claude"; mkdir -p "$CC/plugins" "$T/cache/wharf/1/bin" "$T/proj/sub"; : > "$T/cache/wharf/1/bin/finish-x"
printf '{"plugins": {"wharf@regatta": [{"scope": "project", "projectPath": "%s", "installPath": "%s"}]}}\n' "$T/proj" "$T/cache/wharf/1" > "$CC/plugins/installed_plugins.json"
cp -R "$M" "$T/cache-core"   # a core outside any checkout, as in a plugin cache
cpy() { (cd "$1" && CLAUDE_CONFIG_DIR="$CC" python3 -I -c "import sys; sys.path.insert(0, '$T/cache-core/hooks'); import common; $2"); }
check "$(cpy "$T/proj/sub" 'print(common.tool("finish-x"))')" "$T/cache/wharf/1/bin/finish-x" "from a cache: a project row's installPath, cwd inside it"
check "$(cpy "$T" 'print(common.tool("finish-x"))')" "None" "  cwd outside the project: not found"
check "$(cpy "$T/proj" 'print(common.module_path("wharf"))')" "$T/cache/wharf/1" "  module_path() reads the same row"
mkdir "$T/gonecwd"
check "$(cd "$T/gonecwd" && rmdir "$T/gonecwd" && CLAUDE_CONFIG_DIR="$CC" "$PYBIN" -I -c "import sys; sys.path.insert(0, '$T/cache-core/hooks'); import common; print(common.tool('nope'))" 2>&1)" "None" "  a removed cwd: None, no traceback"

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
# "peer absent" trap); the overlay's checkout above holds no helm either, and is no fallback
CO="$T/core-only"; mkdir -p "$CO/.claude-plugin" "$CO/modules"; cp "$ROOT/.claude-plugin/marketplace.json" "$CO/.claude-plugin/"
cp -R "$M" "$CO/modules/"
out=$("$CO/modules/regatta/bin/regatta" has helm); check "$?:$out" "1:helm not installed" "regatta has helm: not installed, exit 1"
out=$("$CO/modules/regatta/bin/regatta" helm board 2>&1); check "$?:$out" "2:regatta: helm not installed" "regatta helm …: one line, exit 2 (G28)"
if [ -d "$ROOT/modules/helm" ]; then
  check "$("$RG" which helm)" "$ROOT/modules/helm/libexec/helm" "regatta which helm: libexec/, off PATH (C1)"
fi
mkdir -p "$CO/modules/zz-stand-in/bin"; cp "$T/legacy/bin/old-tool" "$CO/modules/zz-stand-in/bin/"
check "$("$CO/modules/regatta/bin/regatta" old-tool ready 7)" "legacy ready 7" "regatta <tool> …: runs the tool where it is, args passed"
check "$("$RG" old-tool ready 7 2>&1 >/dev/null | grep -c .)" 1 "  a tool only the overlay holds: not found, one line"
out=$("$RG" which 2>&1); check "$?:$out" "2:regatta which: wrong arguments — \`regatta help\`" "regatta which, no name: a usage error, exit 2"
rm "$T/config/regatta/overlay"
out=$("$RG" check); check "$?" 1 "regatta check without a home: exit 1"
echo "$out" | grep -q -- "--  home: none"; check $? 0 "  it says so"
out=$(REGATTA_HOME="$ROOT" "$RG" check); check "$?" 1 "  REGATTA_HOME set, still no home file: exit 1"
echo "$ROOT" > "$T/config/home"; ln -s "$T/gone" "$T/config/regatta/broken"
out=$("$RG" check); check "$?" 1 "  a dangling link: exit 1"
echo "$out" | grep -q -- "--  regatta/broken → $T/gone (missing)"; check $? 0 "  it names the link and its target"
rm "$T/config/regatta/broken"; out=$("$RG" check); check "$?" 0 "  all well: exit 0"
# B14b landing review: a `legacy` file with no marker is an overlay from before B14a, read as absent
echo "$T" > "$T/config/legacy"; out=$("$RG" check); check "$?" 1 "  a legacy file without regatta/overlay: exit 1"
echo "$out" | grep -q -- "--  legacy without regatta/overlay"; check $? 0 "  it says the overlay reads as absent"
rm "$T/config/legacy"
# a module's own keys (modules/<m>/config-keys): said by the check, never by the core's import
mkdir -p "$T/config/wharf-runs/ssh"; out=$("$RG" check); check "$?" 1 "  a module's key that cannot be read: exit 1"
echo "$out" | grep -q -- "--  wharf-runs/ssh unreadable"; check $? 0 "  it names the key"
rmdir "$T/config/wharf-runs/ssh"
for k in owner guarded orca-deny; do echo x > "$T/config/regatta/$k"; done
echo "$T/logs" > "$T/config/regatta/log-dir"; echo "$T/repos" > "$T/config/regatta/projects"; echo "$T" > "$T/config/regatta/overlay"
out=$("$RG" check); check "$?" 1 "  an overlay without a module's keys: exit 1"
check "$(echo "$out" | grep -c -- '^  --  wharf-runs/\(orca-pairs\|ssh\) missing')" 2 "  each missing key named"
check "$(py 'print(common.CONFIG_PROBLEMS)')" "[]" "  and the core still loads: a module's key is not the core's"
printf 'a:b\n' > "$T/config/wharf-runs/orca-pairs"; printf 'b:c\n' > "$T/config/wharf-runs/ssh"
# every other module's listed keys too (lighthouse's since B9): this case is about wharf-runs'
for k in $(cat "$ROOT"/modules/*/config-keys 2>/dev/null | grep -v '^#'); do
  [ -e "$T/config/$k" ] || { mkdir -p "$(dirname "$T/config/$k")"; echo x > "$T/config/$k"; }
done
out=$("$RG" check); check "$?" 0 "  with them written: exit 0"
rm -r "$T/config/wharf-runs" "$T/config/regatta/overlay"; for k in owner guarded orca-deny log-dir projects; do rm "$T/config/regatta/$k"; done
rm -rf "$T/config/aurora"   # the x the loop wrote: aurora/host has its own rows below
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
# the fleet queue's two rows (dispatch-queue S2): a home, and the queue-sweep job beside it
mkdir -p "$T/config/wharf-runs"; echo off > "$T/config/wharf-runs/queue-repo"
out=$("$RG" check); check "$?:$(echo "$out" | grep -c '  queue home: \|  queue-sweep: ')" "0:0" "  a queue home off: exit 0, no queue row"
echo "$T/q.git" > "$T/config/wharf-runs/queue-repo"; echo org.example.claude > "$T/config/wharf-runs/label-prefix"
LA="$HOME/Library/LaunchAgents"; SWEEP="$LA/org.example.claude.queue-sweep.plist"   # dispatch's own LA, the job's path once
# Linux reads the same plist through wharf-runs' systemd-launchctl (S7), so the same cases: its user manager
# stood in as up (the shim's `manager` probe asks systemctl is-system-running), and once as down below
printf '#!/bin/sh\ncase "$*" in *is-system-running*) echo "${STUB_MANAGER:-running}"; [ "${STUB_MANAGER:-running}" = running ];; esac\n' > "$T/systemctl"
chmod +x "$T/systemctl"; export SYSTEMD_LAUNCHCTL_SYSTEMCTL="$T/systemctl"
out=$("$RG" check); rc=$?
if [ "$(uname)" != Darwin ]; then
  out2=$(STUB_MANAGER=offline "$RG" check); check "$?" 0 "  a queue home with no user manager answering: exit 0, the sweep a note"
  echo "$out2" | grep -q -- "..  queue-sweep: no launchd or systemd user manager here"; check $? 0 "    its row says so (a systemctl on PATH is no manager)"
fi
check "$rc" 1 "  a queue home and no queue-sweep job: exit 1"
echo "$out" | grep -qx "  ok  queue home: $T/q.git"; check $? 0 "    the home's row"
echo "$out" | grep -q -- "--  queue-sweep: no job here ($SWEEP)"; check $? 0 "    the sweep's row names the job it looked for"
mkdir -p "$LA"; touch "$SWEEP"
# launchd stood in: it holds the job while $T/held exists (S2a's landing review, item 3: the file is not the job)
printf '#!/bin/sh\n[ "$1" = print ] && [ -f "%s/held" ]\n' "$T" > "$T/launchctl"; chmod +x "$T/launchctl"
out=$(DISPATCH_LAUNCHCTL="$T/launchctl" "$RG" check); check "$?" 1 "  the plist but launchd does not hold it: exit 1"
echo "$out" | grep -q -- "--  queue-sweep: its plist is here but launchd does not hold it ($SWEEP)"; check $? 0 "    its row says so"
touch "$T/held"
out=$(DISPATCH_LAUNCHCTL="$T/launchctl" "$RG" check); check "$?" 0 "  with the job loaded: exit 0"
echo "$out" | grep -q "^  ok  queue-sweep: every 10 min"; check $? 0 "    its row ok"
# a label move (wharf-runs/label-prefix-previous): the sweep under the previous prefix is read while the new one is absent
OSW="$LA/org.old.jobs.queue-sweep.plist"; rm -f "$SWEEP"; touch "$OSW"
out=$(DISPATCH_LAUNCHCTL="$T/launchctl" "$RG" check); check "$?" 1 "  no previous key: a sweep under another prefix is not this host's (today's behaviour)"
echo org.old.jobs > "$T/config/wharf-runs/label-prefix-previous"
out=$(DISPATCH_LAUNCHCTL="$T/launchctl" "$RG" check); check "$?" 0 "  with it, the sweep under the previous prefix loaded: exit 0"
echo "$out" | grep -qF "  ok  queue-sweep: every 10 min ($OSW) — under the previous label prefix; the next dispatch here relabels it"; check $? 0 "    its row names it and what moves it"
touch "$SWEEP"
out=$(DISPATCH_LAUNCHCTL="$T/launchctl" "$RG" check)
echo "$out" | grep -qF "  ok  queue-sweep: every 10 min ($SWEEP)"; check $? 0 "    both there: the current prefix's is the one read"
echo "$out" | grep -q "under the previous label prefix"; check $? 1 "    and its row names no move"
echo org.example.claude > "$T/config/wharf-runs/label-prefix-previous"
out=$(DISPATCH_LAUNCHCTL="$T/launchctl" "$RG" check)
echo "$out" | grep -q "under the previous label prefix"; check $? 1 "  a previous key equal to the prefix is none: no move named"
rm -f "$OSW" "$T/config/wharf-runs/label-prefix-previous"
if [ "$(uname)" = Darwin ]; then   # the listener row is a note off macOS
  # S8: a kick-roads line naming sheep for this host wants its listener service held by launchd
  printf '#!/bin/sh\ncase "$2" in *queue-sweep) exit 0;; *dev.spacesheep.stream.*) [ -f "%s/heard" ];; *) exit 1;; esac\n' "$T" > "$T/launchctl"
  out=$(DISPATCH_HOST=hosta DISPATCH_LAUNCHCTL="$T/launchctl" "$RG" check); check "$?:$(echo "$out" | grep -c 'kick listener')" "0:0" "  no kick-roads line: no listener row"
  echo "hosta:sheep,ssh" > "$T/config/wharf-runs/kick-roads"
  out=$(DISPATCH_HOST=hosta DISPATCH_LAUNCHCTL="$T/launchctl" "$RG" check); check "$?" 1 "  a line naming sheep and no listener: exit 1"
  echo "$out" | grep -q -- "--  kick listener: wharf-runs/kick-roads names sheep for hosta, and launchd holds no listener on kick/hosta (dev.spacesheep.stream.kick-hosta)"; check $? 0 "    the row names the stream and the CLI's label"
  printf 'hosta:\nsheep,\nssh\n' > "$T/config/wharf-runs/kick-roads"
  out=$(DISPATCH_HOST=hosta DISPATCH_LAUNCHCTL="$T/launchctl" "$RG" check); check "$?:$(echo "$out" | grep -c -- '--  kick listener')" "1:1" "  the line written one word per line reads the same (S8 review)"
  touch "$T/heard"
  out=$(DISPATCH_HOST=hosta DISPATCH_LAUNCHCTL="$T/launchctl" "$RG" check); check "$?" 0 "  the listener held: exit 0"
  echo "$out" | grep -q "^  ok  kick listener: kick/hosta"; check $? 0 "    its row ok"
  out=$(DISPATCH_HOST=hostb DISPATCH_LAUNCHCTL="$T/launchctl" "$RG" check); check "$(echo "$out" | grep -c 'kick listener')" 0 "  another host's line: no row here"
  rm -f "$T/heard" "$T/config/wharf-runs/kick-roads"
fi
rm -f "$SWEEP" "$T/held" "$T/launchctl"
unset SYSTEMD_LAUNCHCTL_SYSTEMCTL
rm -r "$T/config/wharf-runs"
# aurora/host against lighthouse/hosts (the weekly host rule's row): case-blind, as the rule compares
mkdir -p "$T/config/lighthouse" "$T/config/aurora"; printf 'laptop\nstudio\n' > "$T/config/lighthouse/hosts"; echo Studio > "$T/config/aurora/host"
out=$("$RG" check); check "$?:$(echo "$out" | grep -c -- '--  aurora/host')" "0:0" "  aurora/host a host lighthouse/hosts lists (in capitals): exit 0, no finding"
echo nowhere > "$T/config/aurora/host"
out=$("$RG" check); check "$?" 1 "  aurora/host naming a host lighthouse/hosts does not list: exit 1"
echo "$out" | grep -qx -- "  --  aurora/host names nowhere, which lighthouse/hosts does not list (laptop, studio): no host here runs the weekly jobs (your overlay's bootstrap.sh --config)"; check $? 0 "    it names the host and the list"
check "$(echo "$out" | grep -c '^  ok  aurora/host')" 0 "    and the key is not also ok"
rm "$T/config/lighthouse/hosts"
out=$("$RG" check); check "$?" 0 "  no lighthouse/hosts: nothing to check the host against, exit 0"
echo my_mac > "$T/config/aurora/host"
out=$("$RG" check); check "$?" 1 "  aurora/host naming what no host name can be (an underscore): exit 1"
echo "$out" | grep -q -- "--  aurora/host names my_mac, which no host's name can be"; check $? 0 "    saying so"
printf 'laptop\nstudio\n' > "$T/config/aurora/host"
out=$("$RG" check); check "$?" 1 "  aurora/host with two lines: exit 1"
echo "$out" | grep -q -- "--  aurora/host has 2 lines, and names one host: the weekly jobs refuse"; check $? 0 "    saying so"
rm -r "$T/config/lighthouse" "$T/config/aurora"

echo "the weekly jobs' host rule (common.weekly_host: weekly-run's night, sextant-run, both installers)"
# A config dir of its own; each case writes the keys it reads. Moved from aurora's and sextant's suites
# (2026-10-24): each runner's suite keeps the cases for how it treats a verdict.
WH="$T/wh"; mkdir -p "$WH/aurora"; AH="$WH/aurora/host"; SKH="$WH/aurora/skip-hosts"
H=$(py 'print(common.host_name())'); HU=$(printf %s "$H" | tr a-z A-Z)
wh() { REGATTA_CONFIG="$WH" py "v, l, n = common.weekly_host($1); print(v + '|' + l + '|' + ' / '.join(n))"; }
AHINT="aurora install.sh --schedule refuses here, --remove unloads a job loaded before"
SHINT="sextant install.sh --schedule refuses here, --unschedule removes a job loaded before"
NOTE="note: aurora/skip-hosts is deprecated: write aurora/host, the one host the weekly jobs run on (your overlay's bootstrap.sh --config)"
check "$(wh '"aurora"')" "run||" "neither key and no overlay: run (an install on one machine)"
echo "$H" > "$AH"; check "$(wh '"aurora"')" "run||" "aurora/host names this host: run, no note"
printf '\xEF\xBB\xBF%s \r\n' "$HU" > "$AH"; check "$(wh '"aurora"')" "run||" "  in capitals, with a BOM, a trailing space and CRLF: still this host"
echo host-a > "$AH"
check "$(wh '"aurora"')" "skip|skipped: aurora does not run on $H (aurora/host names host-a; $AHINT)|" "aurora/host names another host: skip, naming it and aurora's --remove"
check "$(wh '"sextant"')" "skip|skipped: sextant does not run on $H (aurora/host names host-a; $SHINT)|" "  sextant's hint names --unschedule, never --remove (which takes the ideas intake with it)"
check "$(wh '"night"')" "skip|skipped: night does not run on $H (aurora/host names host-a)|" "  a job with no installer: no hint"
: > "$AH"; check "$(wh '"aurora"')" "refuse|refused: aurora/host is empty: it names no host to run on|" "aurora/host empty: refuse"
printf '%s\nhost-a\n' "$H" > "$AH"; check "$(wh '"aurora"')" "refuse|refused: aurora/host names one host, and it has 2 lines|" "two lines, this host first: refuse (one host, never a list)"
rm "$AH"; mkdir "$AH"; check "$(wh '"aurora"' | cut -d'(' -f1)" "refuse|refused: aurora/host cannot be read " "aurora/host unreadable (a folder): refuse"
rmdir "$AH"; ln -s "$T/not-mounted/host" "$AH"
check "$(wh '"aurora"')" "refuse|refused: aurora/host cannot be read (a link whose target is missing)|" "aurora/host a dangling link: refuse, never read as no key"
rm "$AH"; echo host-a > "$SKH"
check "$(wh '"aurora"')" "run||$NOTE" "no aurora/host, a skip-hosts not listing this host: the old rule runs it, with the deprecation note"
printf 'elsewhere\n%s\n' "$HU" > "$SKH"
check "$(wh '"aurora"')" "skip|skipped: aurora does not run on $H (aurora/skip-hosts; $AHINT)|$NOTE" "  this host listed (in capitals): skip, the note too"
printf '\xEF\xBB\xBF%s \r\n' "$H" > "$SKH"; check "$(wh '"aurora"' | cut -d'|' -f1)" "skip" "  a BOM, a trailing space and CRLF still match"
echo "$H" > "$AH"; check "$(wh '"aurora"')" "run||" "aurora/host beside a skip-hosts listing this host: aurora/host decides, skip-hosts is not read"
rm "$AH" "$SKH"; mkdir "$SKH"
check "$(wh '"aurora"' | sed 's/cannot be read (.*)|/cannot be read (..)|/')" "refuse|refused: aurora/skip-hosts cannot be read (..)|$NOTE" "no aurora/host, skip-hosts unreadable: refuse, with the note"
rmdir "$SKH"
# Beside an overlay the core loads only with its five keys (common.OVERLAY_KEYS), made up here
mkdir -p "$WH/regatta"; touch "$WH/regatta/overlay"; for k in owner guarded orca-deny log-dir projects; do echo "$T/$k" > "$WH/regatta/$k"; done
check "$(wh '"aurora"')" "refuse|refused: no $WH/aurora/host (your overlay's bootstrap.sh --config writes it)|" "neither key beside an overlay: refuse, naming the key"
echo "a scope's pass: the scope's yard, else aurora/host"
printf '{"repos": {"y": {}, "n": {}},\n "scopes": {"yd": {"file": "y", "repos": ["y"], "yard": "%s"},\n  "far": {"file": "f", "repos": ["y"], "yard": "host-b"},\n  "ny": {"file": "n", "repos": ["n"]}}}\n' "$HU" > "$T/wh-reg.json"
export CLAUDE_REPOS_JSON="$T/wh-reg.json"
check "$(wh '"aurora", "yd"')" "run||" "a yard naming this host (in capitals): run, though no aurora/host beside an overlay (aurora/host is never read)"
echo host-a > "$AH"
check "$(wh '"aurora", "far"')" "skip|skipped: scope far runs on its yard host-b, not on $H (the registry names it)|" "a yard on another host: skip, naming it"
check "$(wh '"aurora", "ny"')" "skip|skipped: aurora does not run on $H (aurora/host names host-a; $AHINT)|" "no yard: aurora/host decides"
printf '{"repos": {"y": {}},\n<<<<<<< ours\n' > "$CLAUDE_REPOS_JSON"
check "$(wh '"aurora", "yd"')" "closed|refused: the registry $T/wh-reg.json cannot be read, so scope yd has no known yard (fails closed)|" "a torn registry: closed (the yard unknown)"
check "$(wh '"aurora"' | cut -d'|' -f1)" "skip" "  the whole night reads no registry: aurora/host decides"
echo "regatta weekly-host: the installers' face"
WR() { REGATTA_CONFIG="$WH" "$RG" weekly-host "$@"; }
echo "$H" > "$AH"; out=$(WR aurora); check "$?:$out" "0:" "run: exit 0, nothing said"
echo host-a > "$AH"; out=$(WR sextant); check "$?:$out" "3:skipped: sextant does not run on $H (aurora/host names host-a; $SHINT)" "skip: exit 3, its line"
: > "$AH"; out=$(WR aurora); check "$?:$out" "4:refused: aurora/host is empty: it names no host to run on" "refuse: exit 4 (never 1, a crash's code)"
out=$(WR aurora --scope yd); check "$?" 5 "closed: exit 5"
rm "$AH"; rm "$WH/regatta/overlay"; echo host-a > "$SKH"
out=$(WR aurora); check "$?:$out" "0:$NOTE" "a note is said before the verdict"
WR >/dev/null 2>&1; check "$?" 2 "no job: a usage error, exit 2"
WR aurora --scope >/dev/null 2>&1; check "$?" 2 "  --scope without a name: exit 2"
unset CLAUDE_REPOS_JSON

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

echo "the gate's module rows: a site the config table lacks runs the module's own"
# A copy of the module, so its table holds synthetic sites; a config table of its own, on a branch for set.
GC="$T/gcopy/bin/gate"; C3="$T/c3"; R3="$T/cfg3"; mkdir -p "$C3/regatta" "$R3"
printf '%s\n' '{"defaults": {"claude": {"model": "mod-model", "effort": "low"}},' \
  ' "sites": {"mod.only": {"kind": "classify", "provider": "claude"}, "both.site": {"kind": "generate", "provider": "claude", "model": "mod-both"}}}' \
  > "$T/gcopy/settings/models.json"
printf '%s\n' '{"defaults": {"claude": {"model": "cfg-model"}},' \
  ' "sites": {"both.site": {"kind": "generate", "provider": "claude", "effort": "high"}, "cfg.only": {"kind": "generate", "provider": "claude"}}}' \
  > "$R3/models.json"
git -C "$R3" init -q -b main && git -C "$R3" add -A && git -C "$R3" -c user.name=t -c user.email=t@t commit -qm t
git -C "$R3" checkout -q -b claude/w
ln -s "$R3/models.json" "$C3/regatta/models.json"
gc() { REGATTA_CONFIG="$C3" python3 -I -c "from importlib.machinery import SourceFileLoader as L; g = L('gate', '$GC').load_module()
$1"; }
check "$(gc 'r = g.resolve("mod.only"); print(r["model"], r["effort"], r["table"])')" \
  "mod-model low settings/models.json (module default)" "a site only in the module's table: its row, its defaults, named"
check "$(gc 'r = g.resolve("both.site"); print(r["model"], r["effort"], "table" in r)')" "cfg-model high False" \
  "  a site in both: the config row whole, the config's defaults"
check "$(gc 'try: g.resolve("nope.site")
except g.GateError as e: print(e)')" "models.json: no row for nope.site — a call site needs its row before it runs" \
  "  a site in neither: refused, as before (the config table, named as its repo names it)"
check "$(GATE_MOD_ONLY_MODEL=haiku gc 'r = g.resolve("mod.only"); print(r["model"], r["env"]["GATE_MOD_ONLY_MODEL"])')" "haiku haiku" \
  "  an override on a module row applies, never 'names no site'"
check "$(GATE_TABLE="$R3/models.json" gc 'try: g.resolve("mod.only")
except g.GateError as e: print(e)')" "models.json: no row for mod.only — a call site needs its row before it runs" \
  "  GATE_TABLE: that file alone, no fallback"
out=$(REGATTA_CONFIG="$C3" "$GC" show 2>&1)
echo "$out" | grep -q '^mod.only .*mod-model.* (module default)$'; check $? 0 "show marks a module row"
echo "$out" | grep -q '^rows marked (module default): settings/models.json @ '; check $? 0 "  and names the table it came from"
echo "$out" | grep -q '^both.site .*(module default)'; check $? 1 "  a site in both is the config's, unmarked"
check "$(REGATTA_CONFIG="$C3" "$GC" check 2>&1 | tail -1)" "gate: settings/models.json (module default) validates, 2 sites, 1 of them the table lacks" \
  "check validates the module's table too"
cp "$T/gcopy/settings/models.json" "$T/mod.keep"; printf '{"sites": {"bad": {"kind": "x"}}}\n' > "$T/gcopy/settings/models.json"
REGATTA_CONFIG="$C3" "$GC" check >/dev/null 2>&1; check $? 1 "  a broken module table fails check, never skipped"
check "$(gc 'print(g.resolve("cfg.only")["model"])')" "cfg-model" "  and a config site still runs: the core's edit never stops the owner's rows"
check "$(gc 'try: g.resolve("mod.only")
except g.GateError as e: print("refused" if "module default" in str(e) else e)')" "refused" "  while a module site is refused, naming the module's table"
printf '%s\n' '{"sites": {"mod.only": {"kind": "classify", "provider": "claude"}, "cfg-only": {"kind": "generate", "provider": "claude"}}}' \
  > "$T/gcopy/settings/models.json"
check "$(gc 'print(g.resolve("cfg.only")["model"])')" "cfg-model" "a module site whose override variables clash with a config site's: the config site runs"
check "$(gc 'try: g.resolve("cfg-only")
except g.GateError as e: print("clash" if "shares its override variables" in str(e) else e)')" "clash" "  the clashing module site is refused, saying why"
REGATTA_CONFIG="$C3" "$GC" check >/dev/null 2>&1; check $? 1 "  and check fails on it"
cp "$T/mod.keep" "$T/gcopy/settings/models.json"
cp "$R3/models.json" "$T/gt.json"
GATE_TABLE="$T/gt.json" REGATTA_CONFIG="$C3" "$GC" set mod.only effort=medium >/dev/null 2>&1; check $? 0 "set with GATE_TABLE (a worktree's copy) on a module row: written"
check "$(python3 -c "import json; r = json.load(open('$T/gt.json'))['sites']['mod.only']; print(r['model'], r['effort'])")" "mod-model medium" \
  "  the module's row copied into that file"
out=$(REGATTA_CONFIG="$C3" "$GC" set mod.only effort=huge 2>/dev/null); check "$?" 1 "a refused set on a module row"
case "$out" in *copied*) check "copied" "" "  says nothing was copied";; *) check "" "" "  says nothing was copied";; esac
printf '%s\n' '{"defaults": {"claude": {"model": "cfg-model", "batch": 3}}, "sites": {"cfg.only": {"kind": "generate", "provider": "claude"}}}' > "$T/gx.json"
out=$(GATE_TABLE="$T/gx.json" REGATTA_CONFIG="$C3" "$GC" set mod.only model=m 2>&1); check "$?" 1 "a copy the config table's defaults would change: refused"
echo "$out" | grep -q "name batch= in this set"; check $? 0 "  naming the key to set"
REGATTA_CONFIG="$C3" "$GC" set mod.only effort=medium >/dev/null 2>&1; check $? 0 "set on a module row: written"
check "$(python3 -c "import json; r = json.load(open('$R3/models.json'))['sites']['mod.only']; print(r['kind'], r['provider'], r['model'], r['effort'])")" \
  "classify claude mod-model medium" "  into the config table: the module's row, its model kept, the key changed"
check "$(python3 -c "import json; print(sorted(json.load(open('$T/gcopy/settings/models.json'))['sites']))")" "['both.site', 'mod.only']" \
  "  the module's table untouched"
check "$(gc 'r = g.resolve("mod.only"); print(r["effort"], "table" in r)')" "medium False" "  and the site now resolves from the config table"

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
print(m.__file__, m.overlay_root(), sys.modules.get("common") is m)
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
out=$(LC_ALL=en_US.ISO8859-1 LANG=en_US.ISO8859-1 "$PYBIN" -I -c "import sys; sys.path.insert(0, '$T/old/hooks'); import common; print(ascii(common.DECLARED_LINE))" 2>&1)
check "$out" "'KAPIT\\xc4N, THIS SESSION IS DONE \\u2014 IT LAUNCHES BY ITSELF.'" "  a non-UTF-8 locale: the core and its config decode as an import would"
# The same under an ASCII locale with Python's UTF-8 mode off (-X utf8=0, which -I leaves in force): a Linux
# image has no en_US.ISO8859-1 (no locale-gen), and an absent locale falls back to C, where Python
# enters UTF-8 mode, so the case above then proves nothing about decoding; here open() with no encoding
# would raise on the owner's "ä", on any OS.
out=$(LC_ALL=C LANG=C "$PYBIN" -I -X utf8=0 -c "import sys; sys.path.insert(0, '$T/old/hooks'); import common; print(ascii(common.DECLARED_LINE))" 2>&1)
check "$out" "'KAPIT\\xc4N, THIS SESSION IS DONE \\u2014 IT LAUNCHES BY ITSELF.'" "  an ASCII locale, UTF-8 mode off: the same line, decoded as UTF-8 by the core"
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

echo "cost ratio lists every provider (a subscription bag measured by hand carries its date)"
printf '%s\n' '{"providers": {"anthropic": {"ratio": 0.02, "week_ending": "2026-10-25", "plan": "Max 20x", "plan_usd_week": 46, "list_usd_week": 2300},' \
  '"codex": {"ratio": 0.084, "measured": "2026-10-29", "plan": "Codex Pro", "plan_usd_week": 23, "list_usd_week": 275}}}' > "$T/ratio.json"
out=$(COST_RATIO="$T/ratio.json" "$M/bin/cost" ratio | sed -n 2p)
check "$out" 'codex: list × 0.084, measured 2026-10-29 (Codex Pro $23.00 a week over a $275 bag at list)' "  a second provider: its own line, with its date"
out=$(COST_RATIO="$T/ratio.json" "$M/bin/cost" 10 --provider codex)
check "$out" '$10 ($0.84 effective)' "  cost --provider codex prices at codex's ratio"
out=$(COST_RATIO="$T/ratio.json" "$M/bin/cost" 10 --provider codex 2>&1 >/dev/null)
check "$out" "cost: codex's ratio was measured by hand on 2026-10-29 — \`cost ratio\` lists it" "  …and names its measured date on stderr"
out=$(COST_RATIO="$T/ratio.json" "$M/bin/cost" ratio --json | python3 -c 'import json,sys; print(sorted(json.load(sys.stdin)["others"]))')
check "$out" "['codex']" "  --json carries the others beside Anthropic's entry"
printf '%s\n' '{"providers": {"anthropic": {"ratio": 0.02, "week_ending": "2026-10-25", "plan": "Max 20x", "plan_usd_week": 46, "list_usd_week": 2300}}}' > "$T/ratio1.json"
out=$(COST_RATIO="$T/ratio1.json" "$M/bin/cost" ratio)
check "$out" 'Anthropic list × 0.0200, week ending 2026-10-25 (Max 20x $46.00 a week over $2,300 of list spend); other providers: pay-per-use, × 1' "  Anthropic alone: the one line as before (the overlay's cost test reads it)"
printf '%s\n' '{"providers": {"anthropic": {"ratio": 0.02, "week_ending": "2026-10-25", "plan": "Max 20x", "plan_usd_week": 46, "list_usd_week": 2300},' \
  '"codex": {"ratio": 0.084, "plan_usd_week": "23x", "list_usd_week": null}, "Gemini": {"ratio": 0.05}}}' > "$T/ratio2.json"
out=$(COST_RATIO="$T/ratio2.json" "$M/bin/cost" ratio 2>&1; echo "rc=$?")
check "$(printf '%s\n' "$out" | grep -c '^codex: list × 0.084, measured ? (? \$? a week over a \$? bag at list)$')" "1" "  a hand-written field that is no number reads \$?, never a traceback"
check "$(printf '%s\n' "$out" | grep -c '^Gemini: no usable ratio')" "1" "  a key --provider would not apply is listed as unusable, not with its ratio"
check "$(printf '%s\n' "$out" | tail -1)" "rc=0" "  …and exits 0"

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

# The list's cases (coverage, class 1, class 2) live in tests/classes.sh, a file on autofinish_exclude, so a
# sweep that lands this suite cannot weaken them (the autofinish-exclude landing review, finding 20). It runs on
# the caller's config dir and HOME, which it reads for the overlay marker only.
REGATTA_CONFIG="$REAL_RC" HOME="$REAL_HOME" bash "$M/tests/classes.sh" | sed 's/^/  /'
check "${PIPESTATUS[0]}" 0 "tests/classes.sh: the list covers every live path, class 1 and class 2"
bash "$M/tests/flare.sh" | sed 's/^/  /'
check "${PIPESTATUS[0]}" 0 "tests/flare.sh: regatta flare files, retries and refuses as it says"
bash "$M/tests/attribution.sh" | sed 's/^/  /'
check "${PIPESTATUS[0]}" 0 "tests/attribution.sh: common.attribution resolves and regatta attribution appends as it says"


# Every module targets going public, and nothing forces it (the owner, 2026-10-23: "target every
# module to go opensource. But not enforce it … swap a failure to a regular message, so that we
# don't forget"). A tracked file under modules/ off `.helloworld/allowlist.txt` stays out of the twin
# unseen otherwise (atlaslib.py was, B10), so this note names each; it never fails the check.
# No `.helloworld/` (the public twin) or no git: skipped.
notpublic() {
  python3 -I - "$1" <<'PY'
import os, subprocess, sys
root = sys.argv[1]
conf = os.path.join(root, ".helloworld", "allowlist.txt")
if not os.path.isfile(conf):
    print("SKIP no .helloworld/allowlist.txt in this tree (the public twin has none)")
    sys.exit(0)
try:
    tracked = subprocess.run(["git", "-C", root, "ls-files", "-z", "--", "modules"], capture_output=True,
                             check=True).stdout.decode("utf-8").split("\0")
except (OSError, subprocess.CalledProcessError):
    print("SKIP not a git checkout")
    sys.exit(0)
with open(conf, encoding="utf-8") as fh:
    allow = {l.strip() for l in fh if l.strip() and not l.lstrip().startswith("#")}
off = sorted({p for p in tracked if p} - allow)
print("COUNT %d of %d module files not yet public" % (len(off), len({p for p in tracked if p})))
for p in off:
    print("OFF " + p)
PY
}
echo "transcript: the last main-chain call (one reader for cold_prompt, pickup, the harness adapter)"
cat > "$T/tx.py" <<'PY'
import json, os, sys
sys.path.insert(0, sys.argv[1])
import transcript as tx
d = sys.argv[2]
def rec(model="claude-opus-5-5", ts="2026-10-24T10:00:00.000Z", side=False, u=None):
    u = {"input_tokens": 3, "cache_read_input_tokens": 100, "cache_creation_input_tokens": 20} if u is None else u
    return {"type": "assistant", "isSidechain": side, "timestamp": ts, "message": {"model": model, "content": [], "usage": u}}
def write(name, rows):
    p = os.path.join(d, name)
    with open(p, "w") as f:
        f.write("".join((r if isinstance(r, str) else json.dumps(r, separators=(",", ":"))) + "\n" for r in rows))
    return p
user = {"type": "user", "timestamp": "2026-10-24T10:05:00Z", "message": {"content": "hi"}}
zero = {"input_tokens": 0, "cache_read_input_tokens": 0, "cache_creation_input_tokens": 0}
case = sys.argv[3]
if case == "real":
    print(tx.last_call(write("a", [rec(model="x"), rec(), user])))
elif case == "sidechain":
    print(tx.last_call(write("b", [rec(), rec(model="claude-sonnet-5-5", side=True, ts="2026-10-24T11:00:00Z")]))[1])
elif case == "synthetic":
    print(tx.last_call(write("c", [rec(), rec(model="<synthetic>", u=zero, ts="2026-10-24T11:00:00Z")]))[1:])
elif case == "zero":
    print(tx.last_call(write("e", [rec(), rec(model="claude-fable-5-1", u=zero, ts="2026-10-24T11:00:00Z")]))[1:])
elif case == "nocall":
    print(tx.last_call(write("f", [user, rec(side=True), rec(model="<synthetic>", u=zero)])), tx.last_call(os.path.join(d, "none")), tx.last_call(""))
elif case == "cut":
    # one line whose second half is a whole call of its own: cut there, the half must not count
    inner = json.dumps(rec(model="half"), separators=(",", ":"))
    p = write("g", [rec(model="whole"), json.dumps(user, separators=(",", ":")) + inner])
    print(tx.last_call(p, tail=len(inner) + 1), tx.last_call(p)[1])
elif case == "edge":
    # the tail starts exactly at a line start: that line is whole and counts
    last = json.dumps(rec(model="edge"), separators=(",", ":"))
    p = write("h", [rec(model="before"), last])
    print(tx.last_call(p, tail=len(last) + 1)[1])
elif case == "time":
    print(tx.last_call(write("i", [rec(ts="nope")]))[0], tx.call(rec(ts="2026-10-24T10:00:00+00:00"))[0])
elif case == "line":
    print(tx.call_line("{not json"), tx.call_line(json.dumps(user)), tx.call_line("{\"type\":\"assistant\",\"usage\":"), tx.call_line(json.dumps(rec()))[1:])
PY
TX() { python3 -I "$T/tx.py" "$M/hooks" "$T" "$1" 2>&1; }
check "$(TX real)" "(1792836000.0, 'claude-opus-5-5', 123)" "a real call: its epoch, model and input + cache read + cache write"
check "$(TX sidechain)" "claude-opus-5-5" "  a later sidechain call is a subagent: the main chain's wins"
check "$(TX synthetic)" "('claude-opus-5-5', 123)" "  a <synthetic> entry after a real call is no call"
check "$(TX zero)" "('claude-opus-5-5', 123)" "  nor is a zero total"
check "$(TX nocall)" "None None None" "  no call, no file, no path: None"
check "$(TX cut)" "None whole" "  a line cut at the tail's start is dropped, even when its rest parses"
check "$(TX edge)" "edge" "  a tail that starts at a line start keeps that line"
check "$(TX time)" "None 1792836000.0" "  a time that does not parse: epoch None; an offset time reads"
check "$(TX line)" "None None None ('claude-opus-5-5', 123)" "  call_line(): foreign, user or cut lines are None"

echo "module files not yet public (a note: every module targets the twin, none is forced)"
out=$(notpublic "$ROOT")
printf '%s\n' "$out" | sed -n 's/^COUNT /  --   /p'
printf '%s\n' "$out" | sed -n 's/^OFF /  --     /p'
L="$T/listed"; mkdir -p "$L/.helloworld" "$L/modules/m/bin"
git init -q "$L"; for f in a b c; do : > "$L/modules/m/bin/$f"; done; : > "$L/top"
git -C "$L" add -A
printf '# a comment\nmodules/m/bin/a\n' > "$L/.helloworld/allowlist.txt"
check "$(notpublic "$L" | sed -n 's/^OFF //p' | tr '\n' ' ')" "modules/m/bin/b modules/m/bin/c " "  the note names each off-list module file, never a listed one or a root file"
check "$(notpublic "$L" | sed -n 's/^COUNT //p')" "2 of 3 module files not yet public" "  and counts them"
rm -rf "$L/.helloworld"
check "$(notpublic "$L" | sed -n 's/^SKIP //p')" "no .helloworld/allowlist.txt in this tree (the public twin has none)" "  no .helloworld/: skipped"

echo "spacesheep plans: the plan read, the deploy log, the budget (spacesheep-tiers, 2026-10-24)"
SD="$T/sheep"; SB="$T/sheep-bin"; mkdir -p "$SB"
cat > "$SB/free" <<'EOF'
#!/bin/sh
echo "$*" >> "$(dirname "$0")/calls"
echo '{"ok": true, "pro": false, "enabled": false}'
EOF
cat > "$SB/off" <<'EOF'
#!/bin/sh
echo '{"ok": true, "pro": true, "enabled": false}'
EOF
cat > "$SB/broken" <<'EOF'
#!/bin/sh
echo "✗ not signed in" >&2; exit 3
EOF
chmod +x "$SB"/*
# its own name and environment: line 121's sp() loads secrets, and a REGATTA_SHEEP_PLAN left set would
# stand in for every read below (SHP_PLAN sets it for one case)
shp() { env -u MEMO_SHEEP_BIN -u REGATTA_SHEEP_PLAN REGATTA_SHEEP_DIR="${SHP_DIR-$SD}" ${SHP_PLAN:+REGATTA_SHEEP_PLAN=$SHP_PLAN} \
          python3 -I -c "import sys; sys.path.insert(0, '$M/hooks'); import common; $1"; }
check "$(shp 'p = common.sheep_plan(None); print(p["plan"], p["cap"], common.sheep_talk_refusal(p))')" "none 400 None" "no CLI: the plan is none, budgeted as Free, and Talk says nothing of a plan"
check "$(shp "p = common.sheep_plan('$SB/free'); print(p['plan'], p['cap'], p['talk'])")" "free 400 False" "Free: pro false is a cap of 400 and no Talk"
check "$(shp "print(common.sheep_talk_refusal(common.sheep_plan('$SB/free')))")" "Talk needs spacesheep Pro (spacesheep.dev/plans) — the file backend still relays on this Mac" "  the one line a relay says"
check "$(wc -l < "$SB/calls" | tr -d ' ')" "1" "  the second read came from the cache, not the CLI"
check "$(shp "print(common.sheep_plan(None, cached_only=True)['plan'])")" "free" "  a hook reads the cache only"
check "$(shp "print(common.sheep_plan('$SB/off', refresh=True)['plan'], common.sheep_talk_refusal(common.sheep_plan('$SB/off'))[:20])")" "pro Talk is off for this" "Pro with Talk switched off: its own line, not the upgrade's"
check "$(shp "p = common.sheep_plan('$SB/broken', refresh=True); print(p['plan'], p['cap'], p['error'])")" "pro 2000 ✗ not signed in" "a failed read after a good one: the plan stands (Pro keeps its cap), the CLI's words kept"
check "$(SHP_DIR="$T/sheep-new" shp "p = common.sheep_plan('$SB/broken'); print(p['plan'], p['cap'], common.sheep_plan_words(p))")" "unknown 400 Free, as far as this Mac knows" "  a failed first read: unknown, budgeted as Free, and worded so"
check "$(env -u REGATTA_SHEEP_DIR MEMO_SHEEP_BIN=/x python3 -I -c "import sys; sys.path.insert(0, '$M/hooks'); import common; print(common.sheep_dir())")" "None" "a stand-in CLI with no sheep dir of its own: nothing is read or written"
check "$(SHP_PLAN=free shp 'print(common.sheep_plan(None)["plan"])')" "free" "REGATTA_SHEEP_PLAN stands in for the read"
shp 'common.sheep_record("keel"); common.sheep_record("helm-board"); common.sheep_record("keel", ok=False, err="rate_limited: publishes per 24h (retry in 600s)")'
printf '{"ts": %s, "by": "keel", "ok": true}\nnot json\n' "$(( $(date +%s) - 90000 ))" >> "$SD/deploys.jsonl"
check "$(shp 'print(common.sheep_count())')" "2" "the count: published deploys of the last 24 h (no refusal, no older row, no junk)"
check "$(shp 'import time; print(590 < common.sheep_refused_until() - time.time() <= 600)')" "True" "  a cap refusal is kept with the retry it named"
printf '{"ts": %s, "by": "keel", "ok": true}\n' "$(( $(date +%s) - 200000 ))" > "$T/sheep-old.jsonl"; cat "$SD/deploys.jsonl" >> "$T/sheep-old.jsonl"; mv "$T/sheep-old.jsonl" "$SD/deploys.jsonl"
before=$(wc -l < "$SD/deploys.jsonl" | tr -d ' ')
shp 'common.sheep_record("keel")'
check "$before $(wc -l < "$SD/deploys.jsonl" | tr -d ' ') $(shp 'print(common.sheep_count())')" "6 4 3" "  an oldest row past twice the kept 25 h prunes the log to 25 h (the 25-hour row stays, the junk goes)"
shp 'common.sheep_record("keel")'
check "$(wc -l < "$SD/deploys.jsonl" | tr -d ' ') $(ls "$SD" | tr '\n' ' ')" "5 deploys.jsonl deploys.lock plan.json " "  the next append only appends; the prune left no temp file"
check "$(shp "b = common.sheep_budget(common.sheep_plan('$SB/free', refresh=True)); print(b['cap'], b['machines'], b['helm_limit'], b['keel_warn'])")" "400 1 300 360" "Free on one machine (no sheep/machines, no lighthouse/hosts): helm stops at 300, keel warns at 360"
mkdir -p "$REGATTA_CONFIG/lighthouse"; printf 'mac-a\nmac-b\n' > "$REGATTA_CONFIG/lighthouse/hosts"
check "$(shp "b = common.sheep_budget(common.sheep_plan('$SB/free')); print(b['machines'], b['helm_limit'], b['keel_warn'])")" "2 150 180" "  two hosts in lighthouse/hosts: two machines, 150 and 180 a Mac"
mkdir -p "$REGATTA_CONFIG/sheep"; echo 1 > "$REGATTA_CONFIG/sheep/machines"
check "$(SHP_PLAN=pro shp 'b = common.sheep_budget(common.sheep_plan(None)); print(b["cap"], b["helm_limit"], b["keel_warn"])')" "2000 1500 1800" "Pro with sheep/machines 1 (over the hosts list): 1,500 and 1,800"
rm -rf "$REGATTA_CONFIG/sheep" "$REGATTA_CONFIG/lighthouse"
check "$(shp 'print(common.sheep_cap_refusal("deploy refused — rate_limited: 400 publishes per 24h (retry in 3600s)"), common.sheep_cap_refusal("space not found"))')" "True False" "a cap refusal is told from another failure"
check "$(shp 'print([common.sheep_cap_refusal(t) for t in ("deploy refused — too many files (retry in 2400s)", "file size limit exceeded", "storage quota exceeded", "deploy refused — rate_limited: slow down (retry in 30s)", "daily limit of 24 hours reached", "too many publishes today")])')" \
  "[False, False, False, False, True, True]" "  a deploy's own limits and a bare rate limit are not the publish cap; publish or 24 h beside the word is"
echo "claude_host(): the kernel's responsible process, pinned for the suites (orca-launcher S4)"
check "$(REGATTA_CLAUDE_HOST=0 py 'print(common.claude_host())') $(REGATTA_CLAUDE_HOST=1 py 'print(common.claude_host())')" "False True" "  REGATTA_CLAUDE_HOST=0|1 pins it"
check "$(py 'print(common.claude_host() in (True, False))')" "True" "  unpinned it answers, never raises (False off macOS)"
DB="$T/db"; mkdir -p "$DB/drive" "$DB/cfg"; : > "$DB/drive/f.json"; : > "$DB/cfg/plain.json"
ln -s "$DB/drive/f.json" "$DB/cfg/in.json"; ln -s "$DB/cfg/plain.json" "$DB/cfg/out.json"; ln -s ../drive/f.json "$DB/cfg/rel.json"
ln -s "$DB/cfg/in.json" "$DB/cfg/chain.json"
check "$(REGATTA_DRIVE_ROOTS="$DB/drive" py "print([common.drive_backed('$DB/cfg/' + n) for n in ('in.json', 'rel.json', 'chain.json', 'out.json', 'plain.json', 'none.json')])")" \
  "[True, True, True, False, False, False]" "drive_backed(): a link into the drive (absolute, relative, through a link) is; a plain file, a link elsewhere, nothing are not"
AGD="$ROOT/modules/lighthouse/hooks/account_guard.py"
if [ -f "$AGD" ]; then
  check "$(REGATTA_DRIVE_ROOTS="$DB/drive" python3 -c 'import sys
from importlib.machinery import SourceFileLoader as L
g = L("ag", sys.argv[1]).load_module()
print([g.drive_backed(sys.argv[2] + n) for n in ("in.json", "rel.json", "chain.json", "out.json", "plain.json", "none.json")])' "$AGD" "$DB/cfg/")" \
    "[True, True, True, False, False, False]" "  account_guard's copy answers the same"
fi
rm "$DB/drive/f.json"
check "$(REGATTA_DRIVE_ROOTS="$DB/drive" py "print(common.drive_backed('$DB/cfg/in.json'))")" "True" "  a dangling link into the drive still is: judged from its text, no stat"

# G4 (docs/orca-launcher-2026-10-24.md): a hook, or a verb a hook runs, that opens a Drive link outside
# claude-host fails, naming the line. Each reader a hook reaches runs against a fixture config whose
# Drive-backed keys (the tenants file, the logins file, the secrets folder) are links into a stand-in
# drive, with their local copies beside them, under tests/drive_audit's audit hook; a module that is
# not here is skipped. The controls under REGATTA_CLAUDE_HOST=1 prove the audit sees an open at all.
echo "G4: Drive-backed files a hook opens outside claude-host"
G4="$T/g4"; GD="$G4/drive"; GHM="$G4/home"; GC="$G4/config"; GL="$G4/opens.log"
mkdir -p "$GD/_secrets" "$GC/regatta" "$GC/lighthouse" "$GHM/.claude" "$GHM/.claude-work" "$GHM/.claude-lab" \
  "$GHM/orca/pz"
echo Owner > "$GC/regatta/owner"
for r in acme-one app privy; do git init -q "$GHM/projects/$r"; done
printf '{"accounts":[{"label":"work","home":"~/.claude-work","repos":{"deny":["privy"]}},{"label":"lab","home":"~/.claude-lab"},{"label":"main","home":"~/.claude","primary":true}]}\n' > "$GC/lighthouse/accounts.json"
printf '{"acme":{"repos":["acme-*"],"logins":["lab"]}}\n' > "$GD/tenants.json"
printf '{"logins":{"work":{"email":"z@example.com"}},"share":{"design":[{"email":"pat@example.com"}]}}\n' > "$GD/logins.json"
for f in tenants logins; do ln -s "$GD/$f.json" "$GC/lighthouse/$f.json"; cp "$GD/$f.json" "$GC/lighthouse/.$f.json.last"; done
printf '{"oauthAccount":{"accountUuid":"u-z","emailAddress":"z@example.com"}}\n' > "$GHM/orca/pz/.claude.json"
ln -s "$GD/_secrets" "$GC/regatta/secrets"; echo 'A=1' > "$GD/_secrets/app.env"; echo 'A=' > "$GHM/projects/app/.env.example"
ln -s "$GD/_secrets/app.env" "$GHM/projects/app/.env"
# g4 HOST CMD…: CMD in the fixture, the audit on; prints CMD's output, the opens go to $GL
g4() { local host=$1; shift; : > "$GL"
  env -u ACCOUNTS_FILE -u TENANTS_FILE -u ACCOUNT_LOGINS -u SECRETS_DIR -u SECRETS_PROJECTS \
    HOME="$GHM" REGATTA_CONFIG="$GC" REGATTA_CLAUDE_HOST="$host" REGATTA_DRIVE_ROOTS="$GD" ACCOUNT_ORCA_DATA="$GHM/orca" ACCOUNT_ORCA_FILE="$G4/no-orca.json" \
    PYTHONPATH="$M/tests/drive_audit" DRIVE_AUDIT_ROOT="$GD" DRIVE_AUDIT_LOG="$GL" "$@" 2>&1; }
GDR=$(cd "$GD" && pwd -P); RTR=$(cd "$ROOT" && pwd -P)   # the audit logs real paths: mktemp's resolve through /private
opened() { sed "s#$GDR/##; s#$RTR/##; s#$ROOT/##" "$GL" | sort -u | tr '\n' ';'; }
g4n=0; g4c=0   # readers run, Drive-backed opens seen
LH="$ROOT/modules/lighthouse"; WH="$ROOT/modules/wharf/hooks/sync.py"; PT="$ROOT/modules/plumb/hooks/tier_check.py"
if [ -f "$LH/hooks/account_guard.py" ]; then
  out=$(echo "{\"cwd\":\"$GHM/projects/acme-one\"}" | g4 0 python3 "$LH/hooks/account_guard.py")
  check "$(echo "$out" | grep -c "acme-one is off main: it is acme's") $(opened)" "1 " "  account_guard, the default dir in a tenant's repo: blocked from the copies, no open"
  g4n=$((g4n+1)); [ -s "$GL" ] && g4c=$((g4c+1))
  out=$(echo "{\"cwd\":\"$GHM/projects/privy\"}" | CLAUDE_CONFIG_DIR="$GHM/orca/pz" g4 0 python3 "$LH/hooks/account_guard.py")
  check "$(echo "$out" | grep -c "privy is off work, whose login this Orca dir is") $(opened)" "1 " "  account_guard on an Orca dir (allowed reads the logins file): work's list from the copy, no open"
  g4n=$((g4n+1)); [ -s "$GL" ] && g4c=$((g4c+1))
  out=$(echo "{\"cwd\":\"$GHM/projects/acme-one\"}" | g4 1 python3 "$LH/hooks/account_guard.py")
  check "$(opened)" "tenants.json at modules/lighthouse/bin/account:$(grep -n 'got = json.loads(TENANTS.read_text())' "$LH/bin/account" | cut -d: -f1);" \
    "  control: under claude-host bin/account opens the link, and the audit names its line"
else echo "  --   lighthouse is not here: its readers skipped"; fi
if [ -f "$LH/hooks/design_route.py" ]; then
  out=$(g4 0 python3 -c 'import sys; from importlib.machinery import SourceFileLoader as L; print(L("dr", sys.argv[1]).load_module().share_list())' "$LH/hooks/design_route.py")
  check "$out $(opened)" "[('pat@example.com', 'view')] " "  design_route's share list: from the logins file's copy, no open"
  g4n=$((g4n+1)); [ -s "$GL" ] && g4c=$((g4c+1))
fi
if [ -f "$PT" ]; then
  out=$(g4 0 python3 -c 'import sys; from importlib.machinery import SourceFileLoader as L; L("tc", sys.argv[1]).load_module().account_lines(); print("ran")' "$PT")
  check "$out $(opened)" "ran " "  tier_check's account lines (account limits --cached): no open"
  g4n=$((g4n+1)); [ -s "$GL" ] && g4c=$((g4c+1))
fi
if [ -f "$WH" ]; then
  sn() { g4 "$1" python3 -c 'import sys; from pathlib import Path; from importlib.machinery import SourceFileLoader as L; print(L("sy", sys.argv[1]).load_module().secrets_notes(Path(sys.argv[2])))' "$WH" "$GHM/projects/app"; }
  out=$(sn 0)
  check "$out $(opened)" "[] " "  sync.py's secrets check, outside claude-host: skipped, no open"
  g4n=$((g4n+1)); [ -s "$GL" ] && g4c=$((g4c+1))
  out=$(sn 1)
  check "$(opened | grep -c '_secrets/app.env at modules/regatta/bin/secrets:')" 1 "  control: under claude-host it runs, and the audit names bin/secrets' line"
fi
check "$g4c" 0 "  G4: of $g4n hook readers, the number that opened a Drive-backed file (target 0)"

# 2026-10-25: a block of test_helm.sh run in a shell whose HOME was the real one emptied the build
# Mac's run records. A suite's recursive or glob delete under HOME goes
# through its rm_own, which deletes only under the suite's own $T and is absent from a block run outside.
echo "a suite deletes under HOME only through its rm_own (F2)"
# (this file holds the lint's own fixture below, so it is not scanned)
out=$(find "$ROOT/modules" -path '*/tests/*' -name '*.sh' ! -path "$M/tests/check.sh" -print0 | xargs -0 python3 "$M/tests/home_rm.py" | sed "s#$ROOT/##")
check "$out" "" "  no suite's recursive or glob delete names a path under HOME (else: <file>:<line>, to go through rm_own)"
hv='$HOME' tl='~'   # the fixture's home paths, spelled apart: the publish gate refuses them whole
printf 'R="%s/Library/Logs/x"\nrm -rf "$R"\nrm -fr %s/y\nrm_own "$R"\nrm -rf "$T/z"\n# rm -rf "%s"\n' "$hv" "$tl" "$hv" > "$T/hr.sh"
check "$(python3 "$M/tests/home_rm.py" "$T/hr.sh" | sed "s#$T/##" | tr '\n' ';')" "hr.sh:2: rm -rf \"\$R\";hr.sh:3: rm -fr $tl/y;" \
  "  the lint: a variable from HOME and a tilde path flagged; rm_own, \$T and a comment not"
# the shapes the landing review found missed: a variable built from another, the flag later in the run, a
# glob, find -delete, a backslash continuation; a single named file, a \${X:?} and a quoted case are not
printf 'P="%s/p"; Q="$P/q"\nrm -rf "$Q/x"\nrm -f -r "$P"\nrm -f "$P"/*.json\nfind "$P" -name y -delete\nrm -rf \\\n  "$Q"\nrm -f "${P:?}/one.json"\nx "rm -rf $P"\n' "$hv" > "$T/hr2.sh"
check "$(python3 "$M/tests/home_rm.py" "$T/hr2.sh" | sed "s#$T/##" | cut -d: -f2 | tr '\n' ' ')" "2 3 4 5 6 " \
  "  …and through a second variable, a later -r, a glob, find -delete and a continued line; not one named file"
defs=$(grep -rh --include='*.sh' '^rm_own() ' "$ROOT/modules" /dev/null < /dev/null | sort -u)
check "$(printf '%s' "$defs" | grep -c '^rm_own() ')" "1" "  every suite's rm_own is the same line"
mkdir -p "$T/own/in" "$T/away"; touch "$T/away/keep" "$T/own/keep"
check "$( (eval "$defs"; T="$T/own"; rm_own "$T/in" && echo deleted; rm_own "$T/../away/keep" 2>/dev/null || echo refused-dots
          rm_own "$T/../away" 2>/dev/null || echo refused-outside) | tr '\n' ' ')" "deleted refused-dots refused-outside " \
  "  rm_own deletes under its \$T and refuses a path outside it or climbing out"
o="$T"; ( eval "$defs"; T=; rm_own "$o/own/keep" ) 2>/dev/null; r=$?
check "$([ "$r" -ne 0 ] && echo refused)|$(ls "$T/own")|$(ls "$T/away")" "refused|keep|keep" \
  "  …and with \$T empty (a block run outside its suite) it deletes nothing"
check "$( (eval "$defs"; T="$T/own"; rm_own "$T//" 2>/dev/null || echo refused-double) )|$(ls "$T/own")" "refused-double|keep" \
  "  …nor \$T itself, spelled with a double slash"

[ "$fails" -eq 0 ] && echo "core: all ok" || echo "core: $fails failed"
[ "$fails" -eq 0 ]
