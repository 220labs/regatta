#!/usr/bin/env bash
# aurora's suite: weekly-run under a scratch HOME and config dir, every name made up. `where` from
# atlas's keys and their overrides; the refusals (no core, no vault, no aurora/host beside an
# overlay); how weekly-run treats the core's host-rule verdicts; tonight's plan; a night whose wharf is missing (the tend and
# the classify fail their own steps, the dream still runs and lands); the unattended skills'
# commands held to the allowlist; the embark step's memo (it parses, carries its context, lands on
# a branch of its own); a plain launchd environment; install.sh against a scratch launchd.
# No network, no `claude` (WEEKLY_CLAUDE stands in), no real repo touched.
#   bash modules/aurora/tests/aurora.sh
set -u
D="$(cd "$(dirname "$0")/.." && pwd -P)"
R="$(cd "$D/../.." && pwd -P)"
W="$D/bin/weekly-run"
T="$(mktemp -d)"; T="$(cd "$T" && pwd -P)"
trap 'rm -rf "$T"' EXIT
export HOME="$T/home" REGATTA_CONFIG="$T/config" WEEKLY_LOG_DIR="$T/logs"
# a recursive delete under HOME goes through rm_own: only under this suite's own $T, so a block of the
# suite run outside it (its HOME the real one; F2, 2026-10-25) deletes nothing (the core's check, home_rm)
rm_own() { local p; for p; do case "$p" in */..|*/../*|*//*) ;; "${T:?}"/?*) rm -rf -- "$p"; continue ;; esac; echo "rm_own: refused $p, outside $T" >&2; return 1; done; }
# The moved HOME drops check.yml's git identity, and the code under test commits (the embark memo,
# the dream): an ubuntu runner cannot guess one from its hostname as a Mac does (the twin's CI,
# 2026-10-25). The file replaces check.yml's, so it carries that one's init.defaultBranch too.
export GIT_CONFIG_GLOBAL="$T/gitconfig"
git config --global user.name t; git config --global user.email t@example.invalid; git config --global init.defaultBranch main
# The embark step ends every sextant job: a scratch checkout, `keel embark` and `keel line` stood in,
# so no rehearsal adds a worktree to this repo or deploys a page (the embark block sets its own)
export WEEKLY_EMBARK_REPO="$T/no-embark-repo" WEEKLY_KEEL_EMBARK="$T/no-keel-embark.json" WEEKLY_KEEL_LINE=echo
unset REGATTA_HOME REGATTA_LEGACY ATLAS_LAYER ATLAS_VAULT CLAUDE_CONFIG_DIR WEEKLY_ANY_HOST AURORA_SECTIONS \
      WEEKLY_TEND WEEKLY_CLASSIFY WEEKLY_COMMIT WEEKLY_PR WEEKLY_CLAUDE AURORA_TODAY AURORA_HOUR CLAUDE_BULLETIN \
      WEEKLY_TRIM TRIM_NOW CLAUDE_REPOS_JSON WEEKLY_CLOCK WEEKLY_SLEEP STUB_TRIM_COLLECT STUB_TRIM_VERDICT STUB_TRIM_SLEEP STUB_TRIM_TORN LANDS WEEKLY_CAP WEEKLY_CAP_GRACE
fails=0
check() {
  if [ "$1" = "$2" ]; then echo "  ok  $3"; else echo "  FAIL $3"; echo "       got:  $1"; echo "       want: $2"; fails=$((fails + 1)); fi
}
mkdir -p "$HOME" "$REGATTA_CONFIG/atlas" "$REGATTA_CONFIG/aurora"
L="$T/layer"; V="$T/vault"
for r in "$L" "$V"; do
  mkdir -p "$r"; git -C "$r" init -q -b main; git -C "$r" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m init
done
printf 'lay\n%s\n' "$L" > "$REGATTA_CONFIG/atlas/layer"
printf 'vlt\n%s\nSUITE_VAULT\n' "$V" > "$REGATTA_CONFIG/atlas/vault"
# The host the weekly jobs run on: this one, as the core names it (aurora/host; the host rule below).
host=$(python3 -c "import sys; sys.path.insert(0, sys.argv[1]); import common; print(common.host_name())" "$R/modules/regatta/hooks")
echo "$host" > "$REGATTA_CONFIG/aurora/host"
wh() { "$W" where | sed -n "s/^$1 //p"; }

echo "where: atlas's keys, their overrides, the core beside the module"
check "$(wh regatta)" "$R/modules/regatta/bin/regatta" "the core's CLI is the checkout's own"
check "$(wh layer) $(wh layer-name)" "$L lay" "the layer and its name from atlas/layer"
check "$(wh vault) $(wh vault-name)" "$V vlt" "the vault and its name from atlas/vault"
check "$(SUITE_VAULT=/x/v wh vault)" "/x/v" "  the variable the key's third line names overrides the path"
check "$(SUITE_VAULT=/x/v ATLAS_VAULT=/y/v wh vault)" "/y/v" "  ATLAS_VAULT over both"
check "$(wh module)" "$D" "the module, physically"
check "$(wh logs)" "$T/logs" "the logs from WEEKLY_LOG_DIR"
check "$(wh owner)" "the owner" "no regatta/owner: the feedback heading's name is \"the owner\""
mkdir -p "$REGATTA_CONFIG/regatta"; echo Sam > "$REGATTA_CONFIG/regatta/owner"
check "$(wh owner)" "Sam" "  the core's regatta/owner when set"
rm "$REGATTA_CONFIG/regatta/owner"
"$W" where >/dev/null; check $? 0 "  exit 0 when the core and the vault are found"
mv "$REGATTA_CONFIG/atlas" "$REGATTA_CONFIG/atlas.off"
check "$(wh vault)" "$HOME/.local/share/atlas" "no key and no overlay: atlas's default vault"
check "$(wh layer)" "MISSING" "  and no layer"
mkdir -p "$REGATTA_CONFIG/regatta"; touch "$REGATTA_CONFIG/regatta/overlay"
# Beside an overlay the core loads only with its five keys (common.OVERLAY_KEYS), made up here.
for k in owner guarded orca-deny log-dir projects; do echo "$T/$k" > "$REGATTA_CONFIG/regatta/$k"; done
check "$(wh vault)" "MISSING" "no key beside an overlay: no vault, never a guess"
"$W" where >/dev/null; check $? 1 "  exit 1"
out=$("$W" aurora "$T" --dry-run); check $? 1 "a run then refuses"
echo "$out" | grep -q "refused: atlas's vault is not configured"; check $? 0 "  and says which key"
mv "$REGATTA_CONFIG/atlas.off" "$REGATTA_CONFIG/atlas"

echo "the core present but not loading (a core key missing beside an overlay)"
mv "$REGATTA_CONFIG/regatta/owner" "$T/owner.off"
out=$("$W" aurora "$T" --dry-run); check $? 1 "refused, never a night without its peers (B10 review)"
echo "$out" | grep -q "refused: the regatta core does not load — .*regatta/owner missing"; check $? 0 "  naming the missing key"
mv "$T/owner.off" "$REGATTA_CONFIG/regatta/owner"

echo "the host rule: weekly-run asks the core's (common.weekly_host; its branches are the core's suite's)"
# The overlay is installed here (its marker and five keys, above). Each case writes the keys it reads.
AH="$REGATTA_CONFIG/aurora/host"; SKH="$REGATTA_CONFIG/aurora/skip-hosts"
posts() { local n; n=$(grep -c -- "$1" "$V/bulletin.md" 2>/dev/null); echo "${n:-0}"; }  # bulletin lines matching $1
"$W" aurora "$T" --dry-run | grep -q "the night's order"; check $? 0 "aurora/host names this host: the night plans"
echo host-a > "$AH"
out=$("$W" aurora "$T" --dry-run); check $? 0 "a skip: exit 0"
check "$(echo "$out" | grep -c "^..:.. skipped: aurora does not run on $host (aurora/host names host-a; aurora install.sh --schedule refuses here, --remove unloads")" 1 "  the core's line, said once after the time"
check "$(echo "$out" | grep -c "the night's order")" 0 "  and nothing planned"
"$W" aurora "$T" --due >/dev/null; check $? 3 "  --due on a skipped host: exit 3, the clock's precheck starts no session"
"$W" sextant "$T" --dry-run | grep -q "skipped: sextant does not run on $host (aurora/host names host-a; sextant install.sh"; check $? 0 "  weekly-run sextant asks for its own job (its hint)"
check "$("$W" embark --dry-run 2>&1 | grep -c 'skipped:')" 0 "  weekly-run embark runs on any host: the rule is not asked"
"$W" aurora "$T"; check "$(grep -c "skipped: aurora does not run on $host" "$T/logs/$(date +%F)-aurora.log")" 1 "  a real run logs it and starts nothing"
check "$(posts 'refused to run')" 0 "  and posts nothing (a skip is no failure)"
rm "$AH"; echo host-a > "$SKH"
out=$("$W" aurora "$T" --dry-run)
check "$(echo "$out" | grep -c '^..:.. note: aurora/skip-hosts is deprecated: write aurora/host')" 1 "a note from the core: said in its own line"
echo "$out" | grep -q "the night's order"; check $? 0 "  and the night plans"
rm "$SKH"
out=$("$W" aurora "$T" --dry-run); check $? 1 "a refusal (neither key beside an overlay): exit 1"
echo "$out" | grep -q "^..:.. refused: no .*aurora/host"; check $? 0 "  the core's line"
"$W" aurora "$T" --due >/dev/null; check $? 0 "  --due on a refusal: exit 0, so the run Orca starts logs and posts it (a failed precheck is a silent skip)"
"$W" aurora "$T"; check "$? $(posts 'the unattended aurora refused to run')" "1 1" "  a real run: exit 1, one bulletin line"
check "$(WEEKLY_ANY_HOST=1 "$W" aurora "$T" --dry-run | head -1 | cut -c1-6)" "aurora" "  WEEKLY_ANY_HOST runs anyway"
rm "$REGATTA_CONFIG/regatta/overlay"
"$W" aurora "$T" --dry-run | grep -q "the night's order"; check $? 0 "neither key and no overlay: the night plans (an install on one machine)"

echo "the host rule for a scope's pass: weekly-run passes the scope"
# A registry of its own; the pass stops at scope-pass where (no anchor cloned here), which is after the rule.
export CLAUDE_REPOS_JSON="$T/hr-repos.json"
printf '{"repos": {"y-knowledge": {}, "n-knowledge": {}},\n "scopes": {"yd": {"file": "y", "repos": ["y-knowledge"], "yard": "%s"},\n  "far": {"file": "f", "repos": ["y-knowledge"], "yard": "host-b"},\n  "ny": {"file": "n", "repos": ["n-knowledge"]}}}\n' "$host" > "$CLAUDE_REPOS_JSON"
echo host-a > "$AH"
out=$("$W" aurora --scope yd --dry-run); check "$(echo "$out" | grep -c 'skipped:')" 0 "a scope whose yard is this host: not skipped, though aurora/host names another"
echo "$out" | grep -q "scope yd is not ready"; check $? 0 "  it reaches the pass (here: not ready, no anchor cloned)"
lg="$T/logs/$(date +%F)-aurora-far.log"; rm -f "$lg"
"$W" aurora --scope far; check "$? $(grep -c '^..:.. skipped: scope far runs on its yard host-b' "$lg")" "0 1" "a yard on another host: skipped, logged in the scope's log, exit 0"
check "$(posts 'did not run')" 0 "  no failure post"
rm "$AH"; touch "$REGATTA_CONFIG/regatta/overlay"
"$W" aurora --scope ny; check "$? $(posts "Aurora's scope pass did not run")" "1 1" "no yard, neither key beside an overlay: exit 1, the scope's bulletin line"
echo "$host" > "$AH"; rm "$REGATTA_CONFIG/regatta/overlay"
printf '{"repos": {"y-knowledge": {}},\n<<<<<<< ours\n' > "$CLAUDE_REPOS_JSON"
lg="$T/logs/$(date +%F)-aurora-yd.log"; rm -f "$lg"
"$W" aurora --scope yd; check "$? $(grep -c 'refused: the registry .* cannot be read, so scope yd has no known yard' "$lg")" "1 1" "a torn registry (closed): logged, exit 1"
check "$(posts 'did not run')" 1 "  in the log alone, as scope-pass where's own refusal (no second line)"
"$W" aurora "$T" --dry-run | grep -q "the night's order"; check $? 0 "  the whole night reads no registry: it still plans"
unset CLAUDE_REPOS_JSON

echo "the host rule crashed: no verdict is a refusal, with the rule's last stderr line"
# A copy of the core whose weekly_host raises: the one way to reach the empty verdict
CC="$T/crashcore"; mkdir -p "$CC/modules"; cp -R "$R/modules/regatta" "$CC/modules/"
python3 - "$CC/modules/regatta/hooks/common.py" <<'PY'
import sys
s = open(sys.argv[1]).read()
a = "def weekly_host(job, scope=None):\n"
assert s.count(a) == 1
open(sys.argv[1], "w").write(s.replace(a, a + "    raise RuntimeError(\"boom: the rule crashed\")\n"))
PY
mkdir -p "$T/crash/bin"; cp "$W" "$T/crash/bin/weekly-run"
out=$(REGATTA_HOME="$CC" "$T/crash/bin/weekly-run" aurora "$T" --dry-run); check $? 1 "refused, exit 1"
echo "$out" | grep -q "refused: the host rule could not be read (the core gave no verdict: RuntimeError: boom: the rule crashed)"; check $? 0 "  naming the crash"
check "$(echo "$out" | grep -c "the night's order")" 0 "  and nothing planned"
check "$(REGATTA_HOME="$CC" WEEKLY_ANY_HOST=1 "$T/crash/bin/weekly-run" aurora "$T" --dry-run | grep -c "the night's order")" 1 "  WEEKLY_ANY_HOST asks no rule: it plans"
echo "a core that stops at import: does not load, whatever it raises"
EC="$T/exitcore/modules/regatta/hooks"; mkdir -p "$EC" "$T/exitcore/modules/regatta/bin"; cp "$R/modules/regatta/bin/regatta" "$T/exitcore/modules/regatta/bin/"
printf 'import sys\nsys.exit("regatta: core refuses")\n' > "$EC/common.py"
out=$(REGATTA_HOME="$T/exitcore" "$T/crash/bin/weekly-run" aurora "$T" --dry-run); check $? 1 "sys.exit at import: refused"
echo "$out" | grep -q "refused: the regatta core does not load — SystemExit: regatta: core refuses"; check $? 0 "  as a core that does not load, never as no verdict"
printf 'raise ImportError("regatta: config broken\\n\\n")\n' > "$EC/common.py"
out=$(REGATTA_HOME="$T/exitcore" "$T/crash/bin/weekly-run" aurora "$T" --dry-run); check $? 1 "an import error whose message ends in blank lines: refused"
echo "$out" | grep -q "refused: the regatta core does not load — ImportError: regatta: config broken"; check $? 0 "  its last non-blank line kept"
check "$(REGATTA_HOME="$T/exitcore" WEEKLY_ANY_HOST=1 "$T/crash/bin/weekly-run" aurora "$T" --dry-run | grep -c 'core does not load')" 1 "  WEEKLY_ANY_HOST skips the rule, never the import"

echo "the core missing"
mkdir -p "$T/lone/bin"; cp "$W" "$T/lone/bin/weekly-run"
out=$("$T/lone/bin/weekly-run" aurora "$T" --dry-run); check $? 1 "no core beside it, no REGATTA_HOME, no home file: refused"
echo "$out" | grep -q "refused: the regatta core is missing"; check $? 0 "  in one line"
echo "$R" > "$REGATTA_CONFIG/home"
check "$("$T/lone/bin/weekly-run" where | sed -n 's/^regatta //p')" "$R/modules/regatta/bin/regatta" "  the config dir's home file finds it"
rm "$REGATTA_CONFIG/home"
check "$(REGATTA_HOME="$R" "$T/lone/bin/weekly-run" where | sed -n 's/^regatta //p')" "$R/modules/regatta/bin/regatta" "  and REGATTA_HOME"

echo "tonight's plan (--dry-run)"
out=$(AURORA_TODAY=2026-10-18 AURORA_HOUR=21 "$W" aurora "$V" --dry-run)
echo "$out" | head -1 | grep -q "^aurora 2026-10-18 21h — the night's order"; check $? 0 "a Sunday night: the header"
check "$(echo "$out" | grep -cE '^  [0-9] ')" 6 "  six steps, in order"
echo "$out" | grep -qE '^  2 classify +due '; check $? 0 "  classify due"
echo "$out" | grep -qE '^  5 dream +due .* must be on vlt main'; check $? 0 "  dream due, its proof named by the vault's name"
out=$(AURORA_TODAY=2026-10-18 AURORA_HOUR=12 "$W" aurora "$V" --dry-run)
echo "$out" | grep -q "nothing due tonight"; check $? 0 "a Sunday before 20:00: nothing due"
check "$(ls "$T/logs" | grep -c tried)" 0 "  a dry run records nothing"
echo "the clock's precheck (--due, knowledge-layers S7)"
AURORA_TODAY=2026-10-18 AURORA_HOUR=21 "$W" aurora "$V" --due >/dev/null; check $? 0 "a night with a section due: exit 0, the run starts"
AURORA_TODAY=2026-10-18 AURORA_HOUR=12 "$W" aurora "$V" --due >/dev/null; check $? 3 "nothing due: exit 3, Orca records skipped_precheck"
check "$(ls "$T/logs" | grep -c tried)" 0 "  the precheck records nothing"
"$W" sextant "$V" --due >/dev/null; check $? 0 "sextant: no plan of its own, always due when it fires"

echo "a night without wharf: the tend and the classify fail their steps, the dream lands"
# The stand-in session writes the dream and commits it, as the section would.
cat > "$T/fake-claude" <<EOF
#!/usr/bin/env bash
mkdir -p "$V/dreams" && echo "# Dream" > "$V/dreams/\$(date +%F).md"
git -C "$V" add -A && git -C "$V" -c user.name=t -c user.email=t@example.invalid commit -qm "Dream: \$(date +%F)"
EOF
chmod +x "$T/fake-claude"
day=$(date +%F); rm -f "$T/logs/$day-aurora.log"
AURORA_SECTIONS=dream WEEKLY_CLAUDE="$T/fake-claude" "$W" aurora "$V"; check $? 0 "the run exits 0"
lg="$T/logs/$day-aurora.log"
if ! python3 "$R/modules/regatta/bin/regatta" which tend >/dev/null 2>&1; then
  grep -q "^FAILED tend $day: wharf's tend is not installed" "$lg"; check $? 0 "  FAILED tend, naming wharf"
else
  echo "  skip  wharf's tend is in this checkout: the missing-wharf case needs a checkout without it"
fi
grep -q "^LAUNCHED [0-9a-f]* dreams/$day.md" "$lg"; check $? 0 "  the dream LAUNCHED on the vault's main"
check "$(cat "$T/logs/aurora-dream-tried")" "$day" "  its attempt recorded"
rm -f "$lg"
AURORA_SECTIONS=dream WEEKLY_CLAUDE=true "$W" aurora "$V"
check "$(grep -c '^LAUNCHED' "$lg")" 1 "  a second run that day finds the first one's dream on main"

echo "the trim section (self-tuning S5): plumb's trim, zero tokens, last"
# A tuned repo of the suite's own (the key names it, so the checkout's own trim/ is never run), and a
# stand-in trim that logs each call and exits as STUB_TRIM_<verb> says.
# where the core puts things under the suite's config: its projects folder (the fence keys a repo by it), its log dir
core() { python3 -c "import sys; sys.path.insert(0, sys.argv[1]); import common; print(common.$1)" "$R/modules/regatta/hooks"; }
TR="$(core PROJECTS)/harbor"; mkdir -p "$TR/trim" && git -C "$TR" init -q && echo '[]' > "$T/no-prs.json"
printf '{"vertical": "coding", "repo": "harbor", "since": "2026-10-01", "sources": {"prs": "%s"}, "jobs": {"builder": {"incumbent": "opus:high"}}}\n' "$T/no-prs.json" > "$TR/trim/coding.json"
echo "$TR" > "$REGATTA_CONFIG/aurora/trim-repos"
cat > "$T/stub-trim" <<STUB
#!/usr/bin/env bash
echo "\$*" >> "$T/trim-calls"
case "\$1" in collect) rc=\${STUB_TRIM_COLLECT:-0} ;; verdict) rc=\${STUB_TRIM_VERDICT:-0} ;; *) rc=0 ;; esac
case "\$1" in
  collect) [ -n "\${STUB_TRIM_SLEEP:-}" ] && sleep "\$STUB_TRIM_SLEEP"
           [ "\$rc" = 3 ] && [ -n "\${STUB_TRIM_TORN:-}" ] && { echo "trim collect: refused — the repo registry cannot be read (a torn write?): nothing collected, nothing written" >&2; exit 3; }
           [ "\$rc" = 3 ] && { echo "trim collect: refused — scope vault is confidential: its rows never leave it" >&2; exit 3; }
           [ "\$rc" = 4 ] && { echo "trim collect: could not tell — GitHub did not answer the PR search (status 0)" >&2; exit 4; }
           echo "trim collect: 0 rows ({})" ;;
  verdict) if [ "\$rc" = 3 ]; then echo "trim verdict: wrote $T/verdict.json — refused — floor breached by 1 outcome(s): harbor#5"
           else echo "trim verdict: wrote $T/verdict.json — builder sonnet:high no move"; fi ;;
esac
exit "\$rc"
STUB
chmod +x "$T/stub-trim"
# the plan's trim line is due only where trim is installed: the stand-in counts as installed
sun() { AURORA_TODAY=2026-10-18 AURORA_HOUR=21 WEEKLY_TRIM="$T/stub-trim" "$W" aurora "$V" --dry-run; }
out=$(sun)
echo "$out" | grep -qE '^  6 trim +due .*in 1 repo\(s\), no session'; check $? 0 "a Sunday night: trim due, last (sixth), in the one tuned repo"
echo "$T/elsewhere" > "$REGATTA_CONFIG/aurora/trim-repos"
out=$(sun)
echo "$out" | grep -qE '^  6 trim +not due '; check $? 0 "  no repo with a vertical file: not due"
printf '\357\273\277%s\r\n' "$TR" > "$REGATTA_CONFIG/aurora/trim-repos"
out=$(sun)
echo "$out" | grep -qE '^  6 trim +due .*in 1 repo\(s\)'; check $? 0 "  the key read as the core reads it: a BOM and CRLF still name the repo"
: > "$REGATTA_CONFIG/aurora/trim-repos"
out=$(sun)
echo "$out" | grep -qE '^  6 trim +not due '; check $? 0 "  the key written empty: no repo, never the default"
echo "$TR" > "$REGATTA_CONFIG/aurora/trim-repos"
echo "$day" > "$T/logs/aurora-trim-tried"
out=$(AURORA_TODAY="$day" AURORA_HOUR=21 WEEKLY_TRIM="$T/stub-trim" "$W" aurora "$V" --dry-run)
echo "$out" | grep -qE '^  6 trim +not due '; check $? 0 "  tried this week: not due again"
rm -f "$T/logs/aurora-trim-tried"
# without plumb (a copy of the core and aurora alone, as on a stranger's install): never due, the plan says why
NP="$T/notrim"; mkdir -p "$NP/modules"; cp -R "$R/modules/regatta" "$R/modules/aurora" "$NP/modules/"
out=$(AURORA_TODAY=2026-10-18 AURORA_HOUR=21 "$NP/modules/aurora/bin/weekly-run" aurora "$V" --dry-run)
echo "$out" | grep -qE "^  6 trim +not due +plumb's trim is not installed"; check $? 0 "  plumb's trim not installed: not due, though a repo is tuned"
rm_own "$NP"

trimnight() { rm -f "$lg" "$T/trim-calls"; AURORA_SECTIONS="trim dream" WEEKLY_TRIM="$T/stub-trim" WEEKLY_CLAUDE=true "$W" aurora "$V"; }
p0=$(posts "trim step failed")
trimnight; check $? 0 "a night with trim: exit 0"
check "$(cut -d' ' -f1 "$T/trim-calls" | tr '\n' ' ')" "collect report verdict " "  collect, then report, then verdict"
check "$(grep -c -- "--repo $TR --vertical coding --night" "$T/trim-calls")" 3 "  each over the tuned repo's vertical, on the night's ledger"
grep -q -- "^report .*--write" "$T/trim-calls" && grep -q -- "^verdict .*--write" "$T/trim-calls"; check $? 0 "  report and verdict written (--write)"
grep -q "^TRIM harbor coding $day: builder sonnet:high no move$" "$lg"; check $? 0 "  the verdict's state in the log"
check "$(cat "$T/logs/aurora-trim-tried")" "$day" "  its attempt recorded"
awk '/^== dream in /{d=NR} /^== trim at /{t=NR} /^LAUNCHED .*dreams/{l=NR} END{exit !(d && t && l && d < t && t < l)}' "$lg" < /dev/null; check $? 0 "  after the dream's session, before its proof, which still lands"
STUB_TRIM_COLLECT=3 trimnight; check $? 0 "a refusal (exit 3): the night still exits 0"
check "$(cut -d' ' -f1 "$T/trim-calls" | tr '\n' ' ')" "collect " "  nothing reported or judged after it"
grep -q "^REFUSED trim coding $day: trim's fence (a confidential scope's repo)$" "$lg"; check $? 0 "  one REFUSED line with its reason, the fence's alone"
check "$(grep -c '^FAILED trim' "$lg")$(posts "trim step failed")" "0$p0" "  never a FAILED line, never a bulletin post"
grep -q "^LAUNCHED .*dreams/$day.md" "$lg"; check $? 0 "  and the dream still runs"
STUB_TRIM_VERDICT=3 trimnight
grep -q "^TRIM harbor coding $day: refused — floor breached" "$lg" && ! grep -q '^FAILED trim' "$lg"; check $? 0 "the verdict's own exit 3 (a floor breach) is its state, refused kept, not a failure"
! grep -q "vault is confidential\|harbor" <(grep '^REFUSED trim' "$lg"); check $? 0 "  a REFUSED line names neither the scope nor the repo (embark-memo quotes the log)"
STUB_TRIM_COLLECT=4 trimnight
grep -q "^FAILED trim $day: trim collect in harbor (coding) exit 4: .*GitHub did not answer" "$lg"; check $? 0 "could not tell (exit 4): the step fails, saying why"
check "$(posts "trim step failed")" "$((p0 + 1))" "  and posts one bulletin line (so the refusal's none above is a real none)"
grep -q "^LAUNCHED .*dreams/$day.md" "$lg"; check $? 0 "  and the dream still runs"

# A torn registry is not the fence: every repo would refuse. Said as torn, failed and posted, the step stopped.
echo '{"repos": {"harbor": ' > "$T/torn-repos.json"
p1=$(posts "trim step failed")
CLAUDE_REPOS_JSON="$T/torn-repos.json" STUB_TRIM_COLLECT=3 trimnight; check $? 0 "a torn registry: the night still exits 0"
grep -q "^FAILED trim $day: the repo registry cannot be read (a torn write?)" "$lg" && ! grep -q '^REFUSED trim' "$lg"; check $? 0 "  FAILED, said as torn, never the fence's REFUSED"
check "$(posts "trim step failed")" "$((p1 + 1))" "  one bulletin line"
STUB_TRIM_COLLECT=3 STUB_TRIM_TORN=1 trimnight
grep -q "^FAILED trim $day: the repo registry cannot be read" "$lg"; check $? 0 "  trim's own word for it counts too (torn while it read, whole again after)"
# The cap: trim's calls share WEEKLY_CAP, so a stalled GitHub page fails the step, never holds the night.
t0=$SECONDS
WEEKLY_CAP=3 WEEKLY_CAP_GRACE=1 STUB_TRIM_SLEEP=60 trimnight; check $? 0 "a collect that hangs: the night exits 0"
check "$([ $((SECONDS - t0)) -lt 30 ] && echo bounded || echo "$((SECONDS - t0)) s")" bounded "  killed at the cap, not after the stall"
grep -q "^FAILED trim $day: trim collect in harbor (coding) killed at the step's .*cap (WEEKLY_CAP)" "$lg"; check $? 0 "  FAILED, naming the cap"
check "$(cut -d' ' -f1 "$T/trim-calls" | tr '\n' ' ')" "collect " "  nothing reported or judged after it"
grep -q "^LAUNCHED .*dreams/$day.md" "$lg"; check $? 0 "  and the dream still lands"
# A dropped repo's verdict leaves the daily report: renamed verdict.retired.json; a tuned one stays.
NV="$(core LOG_DIR)/$(core 'host_name()')/trim"
mkdir -p "$NV/gone/coding" "$NV/harbor/coding"
echo '{"key": "gone", "repo": "/x/gone", "vertical": "coding", "at": "2026-10-01T00:00", "refused": []}' > "$NV/gone/coding/verdict.json"
echo '{"key": "harbor", "repo": "/x/harbor", "vertical": "other", "at": "2026-10-01T00:00", "refused": []}' > "$NV/harbor/coding/old.json"
python3 -c 'import json, sys; json.dump({"key": sys.argv[1], "repo": sys.argv[2], "vertical": "coding", "refused": []}, open(sys.argv[3], "w"))' \
  "$(core "repo_key('$TR')")" "$TR" "$NV/harbor/coding/verdict.json"
mkdir "$REGATTA_CONFIG/aurora/trim-repos.d" && mv "$REGATTA_CONFIG/aurora/trim-repos" "$REGATTA_CONFIG/aurora/trim-repos.keep" \
  && mv "$REGATTA_CONFIG/aurora/trim-repos.d" "$REGATTA_CONFIG/aurora/trim-repos"
trimnight
check "$(ls "$NV/gone/coding" | tr '\n' ' ')" "verdict.json " "an unreadable key (a folder here): no repo tuned, and nothing retired"
rmdir "$REGATTA_CONFIG/aurora/trim-repos"; mv "$REGATTA_CONFIG/aurora/trim-repos.keep" "$REGATTA_CONFIG/aurora/trim-repos"
trimnight
check "$(ls "$NV/gone/coding" | tr '\n' ' ')" "verdict.retired.json " "a verdict of a repo the night no longer tunes: retired"
check "$(ls "$NV/harbor/coding" | tr '\n' ' ')" "old.json verdict.json " "  the tuned repo's verdict kept"
grep -q "^RETIRED trim $day: 1 verdict(s) of a repo or vertical the night no longer tunes" "$lg" && ! grep -q "^RETIRED.*gone" "$lg"; check $? 0 "  one RETIRED line, counting, naming no repo"
# The vertical as trim names it: a file whose own "vertical" differs from its name keeps that night's verdict.
cp "$TR/trim/coding.json" "$T/coding.json.keep"
python3 -c 'import json, sys; json.dump({"vertical": "code"}, open(sys.argv[1], "w"))' "$TR/trim/coding.json"
mkdir -p "$NV/harbor/code"
python3 -c 'import json, sys; json.dump({"key": sys.argv[1], "repo": sys.argv[2], "vertical": "code", "refused": []}, open(sys.argv[3], "w"))' \
  "$(core "repo_key('$TR')")" "$TR" "$NV/harbor/code/verdict.json"
trimnight
check "$(ls "$NV/harbor/code" | tr '\n' ' ')" "verdict.json " "  a vertical file naming its own vertical: its verdict kept"
cp "$T/coding.json.keep" "$TR/trim/coding.json"
# A listed repo not there tonight (an unmounted disk): nothing retired.
printf '%s\n%s\n' "$TR" "$T/unmounted" > "$REGATTA_CONFIG/aurora/trim-repos"
rm -f "$NV/gone/coding/verdict.retired.json"; echo '{"key": "gone", "vertical": "coding"}' > "$NV/gone/coding/verdict.json"
trimnight
check "$(ls "$NV/gone/coding" | tr '\n' ' ')" "verdict.json " "  a listed repo missing tonight: nothing retired"
printf '%s\n' "$TR" > "$REGATTA_CONFIG/aurora/trim-repos"
rm_own "$NV/gone" "$NV/harbor"
# A dotfile in trim/ (an AppleDouble copy) is no vertical: a repo holding only one is not tuned.
DR="$T/dotrepo"; mkdir -p "$DR/trim"; echo '{}' > "$DR/trim/._web.json"
printf '%s\n' "$DR" > "$REGATTA_CONFIG/aurora/trim-repos"
out=$(sun)
echo "$out" | grep -qE '^  6 trim +not due '; check $? 0 "  a repo whose only vertical file is a dotfile: not due"
printf '%s\n' "$TR" > "$REGATTA_CONFIG/aurora/trim-repos"; rm_own "$DR"
# Another Mac's push: each Mac collects a day after it ends (about 00:10). A Sunday night waits until 00:30
# for every host's collect after Sunday; a host whose files were all written before then is not in.
# WEEKLY_CLOCK, WEEKLY_SLEEP.
FH="$(core LOG_DIR)/far/calls"; mkdir -p "$FH"
echo day > "$FH/2026-10-24.csv"; echo day > "$FH/2026-10-25.csv"
touch -t 202610250010 "$FH/2026-10-24.csv"; touch -t 202610251800 "$FH/2026-10-25.csv"
cat > "$T/rec-sleep" <<STUB
#!/usr/bin/env bash
echo "\$1" >> "$T/slept"
[ -n "\${LANDS:-}" ] && touch -t 202610260010 "$FH/2026-10-25.csv"
true
STUB
chmod +x "$T/rec-sleep"
rm -f "$T/slept"; LANDS=1 WEEKLY_CLOCK=2026-10-25T22:00:00 WEEKLY_SLEEP="$T/rec-sleep" trimnight
check "$(cat "$T/slept" 2>/dev/null)" 9000 "a Sunday at 22:00 with a host's Sunday file collected before midnight: waits until 00:30"
grep -q "^== trim waits 150 min, until 00:30: 1 host(s)' day file of 2026-10-25 not in yet" "$lg" && ! grep -q '^NOTE trim' "$lg"; check $? 0 "  says so; the file landed meanwhile: no note"
awk '/^== trim waits/{w=NR} /^== dream in /{d=NR} END{exit !(d && w && d < w)}' "$lg" < /dev/null; check $? 0 "  the wait after the dream's session: nothing before it waits"
check "$(head -1 "$T/trim-calls" | cut -d' ' -f1)" collect "  then trim runs"
touch -t 202610251800 "$FH/2026-10-25.csv"
rm -f "$T/slept"; WEEKLY_CLOCK=2026-10-25T22:00:00 WEEKLY_SLEEP="$T/rec-sleep" trimnight
grep -q "^NOTE trim $day: 1 host(s)' day file of 2026-10-25 not in at " "$lg" && ! grep -q "far" <(grep '^NOTE trim' "$lg"); check $? 0 "  still short at 00:30: one NOTE, naming no host, and trim runs"
check "$(cut -d' ' -f1 "$T/trim-calls" | tr '\n' ' ')" "collect report verdict " "  the whole step all the same"
rm -f "$T/slept"; WEEKLY_CLOCK=2026-10-26T00:10:00 WEEKLY_SLEEP="$T/rec-sleep" trimnight
check "$(cat "$T/slept" 2>/dev/null)" 1200 "  past midnight, before 00:30: waits the rest"
touch -t 202610260010 "$FH/2026-10-25.csv"
rm -f "$T/slept"; WEEKLY_CLOCK=2026-10-25T22:00:00 WEEKLY_SLEEP="$T/rec-sleep" trimnight
check "$(cat "$T/slept" 2>/dev/null)$(grep -c '^== trim waits' "$lg")" 0 "every host's file in already: no wait"
rm -f "$T/slept"; WEEKLY_CLOCK=2026-10-25T15:00:00 WEEKLY_SLEEP="$T/rec-sleep" trimnight
check "$(cat "$T/slept" 2>/dev/null)$(grep -c '^== trim waits' "$lg")" 0 "a hand run on a Sunday afternoon: no wait (the last Sunday is the target)"
# A host idle on Sunday has no Sunday file: its collect after midnight rewrote Saturday's, so it is in.
rm -f "$FH/2026-10-25.csv"; touch -t 202610260010 "$FH/2026-10-24.csv"
rm -f "$T/slept"; WEEKLY_CLOCK=2026-10-25T22:00:00 WEEKLY_SLEEP="$T/rec-sleep" trimnight
check "$(cat "$T/slept" 2>/dev/null)$(grep -c '^== trim waits' "$lg")" 0 "  a host with no calls on Sunday, collected after it: no wait"
# A catch-up night (the Mac slept through Sunday) judges the week's Sunday, not yesterday.
touch -t 202610251800 "$FH/2026-10-24.csv"
check "$(WEEKLY_CLOCK=2026-10-27T21:00:00 python3 -c "$(sed -n "/^TRIM_PY='/,/^'$/p" "$W" | sed '1s/^TRIM_PY=.//;$d')" "$R/modules/regatta/hooks" wait)" "2026-10-25 0 1" "  a Tuesday catch-up: the target is Sunday, the short host counted, no wait"
rm_own "$(dirname "$FH")"

echo "  the real trim, through the night (no stand-in): the ledger outside the repo, the fence held"
if [ -f "$R/modules/plumb/bin/trim" ]; then
rm -f "$lg"; NT="$(core LOG_DIR)/$(core 'host_name()')/trim"; ND="$NT/harbor/coding"
AURORA_SECTIONS=trim CLAUDE_REPOS_JSON="$T/no-repos.json" TRIM_NOW=2026-10-20T00:00:00Z "$W" aurora "$V"; check $? 0 "a night with trim alone: exit 0, no session"
[ -s "$ND/verdict.json" ] && ls "$ND"/report-*.md >/dev/null 2>&1; check $? 0 "  the report and the verdict filed in the core's log dir, this host's folder"
check "$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["repo"], d["vertical"], d["refused"])' "$ND/verdict.json" 2>&1)" "$TR coding []" "  the verdict names its repo, for the reader's fence"
check "$(ls "$TR" | tr '\n' ' ')" "trim " "  nothing written in the tuned repo"
grep -q "^TRIM harbor coding $day: no challenger on record$" "$lg"; check $? 0 "  its state in the log"
rm -rf "$NT"; rm -f "$lg"
echo '{"repos": {"harbor": {}}, "scopes": {"vault": {"repos": ["harbor"], "confidential": true}}}' > "$T/conf-repos.json"
AURORA_SECTIONS=trim CLAUDE_REPOS_JSON="$T/conf-repos.json" "$W" aurora "$V"; check $? 0 "a confidential scope's repo: the night exits 0"
grep -q "^REFUSED trim coding $day: trim's fence" "$lg"; check $? 0 "  REFUSED by trim's own fence"
check "$([ -e "$NT" ] && echo written || echo none)" "none" "  nothing collected, nothing written"
else echo "  skip  plumb's trim is not in this checkout (the public twin, until trim S8)"; fi
rm -f "$REGATTA_CONFIG/aurora/trim-repos" "$T/logs/aurora-trim-tried" "$lg"

echo "the unattended skills' commands are on weekly-run's allowlist"
# What /aurora and its sections run unattended: `<regatta> <tool>`, `<module>/bin/<tool>`, the
# where call. /embark is the owner's sitting, interactive: not checked.
allow=$(sed -n 's/^for t in \(.*\); do$/\1/p' "$W")
missing=""
for c in $(cat "$D"/skills/aurora/SKILL.md "$D"/skills/aurora/sections/*.md \
           | grep -oE '<regatta> [a-z][a-z.-]*( (step|parse|show))?' | sed 's/^<regatta> //; s/ /_/' | sort -u); do
  t=${c/_/ }
  case " $allow " in *" $t "*|*" \"$t\" "*) ;; *) missing="$missing $t" ;; esac
done
check "${missing:-none}" "none" "every <regatta> tool the unattended sections call"
for c in $(cat "$D"/skills/aurora/SKILL.md "$D"/skills/aurora/sections/*.md | grep -oE '<module>/bin/[a-z-]+' | sort -u); do
  grep -qF "Bash(\$MOD/bin/${c#<module>/bin/}:*)" "$W" || missing="$missing $c"
done
check "${missing:-none}" "none" "every <module>/bin tool"
grep -qF '"Bash($sb/../../bin/weekly-run where)"' "$W"; check $? 0 "the where call as a skill writes it"
grep -qF '*/../../bin/weekly-run' "$W"; check $? 1 "  pinned to the skill dirs, never a wildcard"
grep -qF '"Bash(*regatta pr ready*)" "Bash(*regatta pr merge*)"' "$W"; check $? 0 "the core's pr ready/merge form denied"
grep -qE '"\$\{cl\[@\]\}" -p .*--permission-mode auto .*--disallowedTools' "$W"; check $? 0 "claude runs in auto mode with a deny list"

echo "Sextant's step 2c: the queue's verbs and dispatch at the reset, nothing wider (the Sounding's S7)"
# The stand-in writes the two lists weekly-run hands claude (WEEKLY_ALLOWED / WEEKLY_DENIED, one per line).
lists() { printf 'printf "%%s\\n" "$WEEKLY_ALLOWED" > %s; printf "%%s\\n" "$WEEKLY_DENIED" > %s' "$T/$1-allow" "$T/$1-deny"; }
WEEKLY_CLAUDE="$(lists sx)" "$W" sextant "$L" >/dev/null 2>&1
AURORA_SECTIONS=dream WEEKLY_CLAUDE="$(lists au)" "$W" aurora "$V" >/dev/null 2>&1
for s in reset reset+30 reset+60; do
  check "$(grep -cxE "Bash\(.*(/bin/dispatch|regatta dispatch) \* --at ${s/+/\\+} --if-room\)" "$T/sx-allow")" 2 "sextant: dispatch allowed as \`dispatch * --at $s --if-room\`, the core's form and the layer's"
done
check "$(grep 'dispatch' "$T/sx-allow" | grep -vE 'dispatch \* --at reset(\+30|\+60)? --if-room\)$')" "" "  and in no other shape: the tail literal, --if-room required, never dispatch:* (R5)"
check "$(grep -cxE 'Bash\(.*(/bin/pickup|regatta pickup) seed \* --no-start\)' "$T/sx-allow")" 2 "pickup seed allowed only ending --no-start, the core's form and the layer's (R1)"
check "$(grep 'pickup' "$T/sx-allow" | grep -vE 'pickup (seed \* --no-start|show:\*)\)$')" "" "  and in no other shape (seed without --no-start starts the run at once)"
check "$(grep -E -- '--(yolo|start|launch|allow|undeny|force)' "$T/sx-allow" | grep -v -- '--no-start)$')" "" "  no allow rule names --yolo, --start, --undeny or their kin"
for f in '*soundings add*' '*dispatch*--yolo*' '*dispatch*--start*' '*dispatch*--launch*' '*dispatch*--undeny*' '*dispatch*--allow*' '*dispatch*--force*' \
         '*dispatch*--account*' '*dispatch*--note*' '*dispatch*--background*' '*dispatch*--end*' '*pickup*--start*' '*pickup*--launch*' '*pickup*--force*'; do
  grep -qxF "Bash($f)" "$T/sx-deny"; check $? 0 "  denied: $f"
done
grep -q '^export WEEKLY_RUN="\$job"$' "$W"; check $? 0 "the job exports WEEKLY_RUN, which soundings' two refusals read (R2), never CLAUDE_UNATTENDED"
check "$(grep -c 'CLAUDE_UNATTENDED=' "$W")" 0 "  weekly-run sets no CLAUDE_UNATTENDED"
for v in next list brief mark refresh; do grep -qF "soundings $v:*)" "$T/sx-allow"; check $? 0 "  allowed: soundings $v"; done
check "$(grep -E 'soundings (add|\*)|soundings:' "$T/sx-allow")" "" "  never soundings add, nor soundings:*"
grep -qF 'keel lint:*)' "$T/sx-allow"; check $? 0 "  allowed: keel lint"
check "$(grep -cE 'dispatch|soundings|pickup seed|keel lint' "$T/au-allow")" 0 "aurora's run gets none of them"
check "$(grep -c 'dispatch' "$T/au-deny")" 0 "  nor the sextant's deny lines"

echo "/sextant's commands against the sextant job's lists (moved from the overlay's suite with B13)"
# What sextant's skill types (`<regatta> <tool> …`) matched against the lists the rehearsal above read,
# the way a permission rule reads: `X:*` a prefix, else `*` any run of characters. A model of Claude
# Code's matcher, not the matcher itself; the text checks above pin the lists. Under `auto`, `ask` means
# the classifier decides; what refuses is a deny rule and dispatch's and pickup's own WEEKLY_RUN guards.
perm() {  # perm <command> → allow | deny | ask, deny first as Claude Code orders them
  python3 - "$T/sx-allow" "$T/sx-deny" "$1" <<'PY'
import re, sys
def rules(f):
    return [l[5:-1] for l in open(f).read().splitlines() if l.startswith("Bash(") and l.endswith(")")]
def hit(rule, cmd):
    if rule.endswith(":*"):
        return cmd == rule[:-2] or cmd.startswith(rule[:-2] + " ")
    return re.fullmatch(".*".join(map(re.escape, rule.split("*"))), cmd, flags=re.S) is not None
allow, deny, cmd = rules(sys.argv[1]), rules(sys.argv[2]), sys.argv[3]
print("deny" if any(hit(r, cmd) for r in deny) else "allow" if any(hit(r, cmd) for r in allow) else "ask")
PY
}
RG=$(wh regatta); BRS=claude/h/2026-10-25-sounding-x; PJ="$HOME/projects/x"
check "$(perm "$RG dispatch $BRS --repo $PJ --at reset+30 --if-room")" allow "sextant 2c: the queue's dispatch, as /sextant types it, is allowed"
check "$(perm "$L/bin/dispatch $BRS --repo $PJ --at reset --if-room")" allow "  and in the layer's form"
check "$(perm "$RG dispatch $BRS --repo $PJ --at reset --if-room --yolo")" deny "  --yolo stays out (denied by name)"
check "$(perm "$RG dispatch $BRS --yolo --at reset")" deny "  --yolo before --at too"
check "$(perm "$RG dispatch --start go $PJ n --at reset")" deny "  --start stays out"
check "$(perm "$RG dispatch $BRS --at reset --undeny Bash(gh:*)")" deny "  --undeny stays out"
check "$(perm "$RG dispatch $BRS --repo $PJ")" ask "  a dispatch without --at reset is not pre-approved (no dispatch:*)"
check "$(perm "$RG dispatch $BRS --at '2026-11-01 04:00'")" ask "  nor one at a clock time"
check "$(perm "$RG dispatch $BRS --repo $PJ --at reset")" ask "  nor one without --if-room (R5)"
check "$(perm "$RG dispatch $BRS --repo $PJ --at reset --at '2026-11-01 04:00' --if-room")" ask "  nor a second --at after the slot (dispatch refuses one before it)"
check "$(perm "$RG dispatch $BRS --repo $PJ --at reset --if-room --headless")" ask "  nor anything after --if-room"
check "$(perm "$RG dispatch $BRS --repo $PJ --account claude-x --at reset --if-room")" deny "  --account stays out"
check "$(perm "$RG dispatch $BRS --repo $PJ --note hi --at reset --if-room")" deny "  --note stays out"
check "$(perm "$RG dispatch $BRS --repo $PJ --background allow --at reset --if-room")" deny "  --background stays out"
check "$(perm "$RG pickup seed sounding-x --file /tmp/b.md --repo $PJ --no-start")" allow "  pickup seed"
check "$(perm "$RG pickup seed sounding-x --file /tmp/b.md --repo $PJ")" ask "  but not without --no-start (pickup refuses it under WEEKLY_RUN, F1)"
check "$(perm "$RG pickup seed sounding-x --file /tmp/b.md --start --no-start")" deny "  --start stays out of pickup"
check "$(perm "$RG pickup seed sounding-x --file /tmp/b.md --force --no-start")" deny "  --force too"
check "$(perm "$RG pickup next")" ask "  …and no other pickup verb"
check "$(perm "$RG keel lint --strict docs/x.md")" allow "  keel lint"
check "$(perm "$RG soundings add x")" deny "  never soundings add (the owner's pick)"
SK="$R/modules/sextant/skills/sextant/SKILL.md"
if [ -f "$SK" ]; then
  SXM=$(python3 "$RG" has sextant)
  check "$(perm "$SXM/skills/sextant/../../libexec/sextant-run where")" allow "/sextant's where, from the module's skill dir"
  check "$(perm "$HOME/.claude/skills/sextant/../../libexec/sextant-run where")" allow "  and from a config dir's link"
  check "$(perm "$T/x/skills/sextant/../../libexec/sextant-run where")" ask "  never from another dir (pinned, as aurora's)"
  # every `<regatta> <tool> [verb]` the skill types, filled out to the shape step 2c gives it
  missing=""
  while read -r c; do
    case "$c" in
      "pickup seed") cmd="$RG pickup seed sounding-x --file /tmp/b.md --repo $PJ --no-start" ;;
      dispatch*) cmd="$RG dispatch $BRS --repo $PJ --at reset --if-room" ;;
      *) cmd="$RG $c x" ;;
    esac
    [ "$(perm "$cmd")" = allow ] || missing="$missing [$c]"
  done < <(grep -oE '<regatta> [a-z][a-z.-]*( [a-z][a-z-]*)?' "$SK" | sed 's/^<regatta> //' | sort -u)  # fenced lines too
  check "${missing:-none}" none "every <regatta> call /sextant types is allowed"
  check "$(grep -cE '~/|/bin/[a-z]' "$SK")" 0 "  and it types no path of its own (the core's CLI only)"
else
  echo "  skip  sextant's skill is not in this checkout"
fi

echo "a plain launchd environment (no REGATTA_HOME, no PATH but /usr/bin:/bin)"
# launchd passes no REGATTA_CONFIG: the config dir is the default one under HOME.
mkdir -p "$HOME/.config"; cp -R "$REGATTA_CONFIG" "$HOME/.config/regatta"
out=$(env -i HOME="$HOME" PATH=/usr/bin:/bin "$W" where); check $? 0 "where: exit 0"
check "$(echo "$out" | sed -n 's/^vault //p')" "$V" "  the vault from the config dir under HOME"
env -i HOME="$HOME" PATH=/usr/bin:/bin "$W" aurora "$V" --dry-run | grep -q "the night's order"; check $? 0 "  --dry-run plans the night"
rm_own "$HOME/.config/regatta"

echo "install.sh against a scratch launchd"
cat > "$T/launchctl" <<EOF
#!/bin/sh
echo "\$*" >> "$T/launchctl.log"
case "\$1" in print) exit 1 ;; esac
EOF
chmod +x "$T/launchctl"
export AURORA_LAUNCH_DIR="$T/agents" AURORA_LAUNCHCTL="$T/launchctl" AURORA_LABEL=test.aurora
touch "$REGATTA_CONFIG/regatta/overlay"
out=$(sh "$D/install.sh" --schedule 2>&1); check $? 1 "--schedule beside an overlay: refused"
echo "$out" | grep -q "schedules the night itself"; check $? 0 "  and says why"
check "$(ls "$T/agents" 2>/dev/null | wc -l | tr -d ' ')" 0 "  no plist written"
rm "$REGATTA_CONFIG/regatta/overlay"
echo host-a > "$REGATTA_CONFIG/aurora/host"
out=$(sh "$D/install.sh" --schedule 2>&1); check $? 1 "--schedule on a host aurora/host does not name: refused"
echo "$out" | grep -q "not loading the job on this host — skipped: aurora does not run on $host (aurora/host names host-a"; check $? 0 "  and says why"
check "$(ls "$T/agents" 2>/dev/null | wc -l | tr -d ' ')" 0 "  no plist written"
: > "$REGATTA_CONFIG/aurora/host"
out=$(sh "$D/install.sh" --schedule 2>&1); check $? 1 "--schedule with aurora/host empty: refused"
echo "$out" | grep -q "refused: aurora/host is empty"; check $? 0 "  quoting the refusal"
# A core whose rule could not tell (it crashed, or no core is found): a stub weekly-run beside a copy of the installer
mkdir -p "$T/stubmod/bin"; cp "$D/install.sh" "$T/stubmod/"
printf 'import sys\nsys.exit("boom: the core died")\n' > "$T/stubmod/regatta"; chmod +x "$T/stubmod/regatta"
printf '#!/bin/sh\n[ "$1" = where ] && { echo "vault %s"; echo "logs %s"; echo "regatta %s"; exit 0; }\nexit 1\n' "$V" "$T/logs" "$T/stubmod/regatta" > "$T/stubmod/bin/weekly-run"
chmod +x "$T/stubmod/bin/weekly-run"
out=$(sh "$T/stubmod/install.sh" --schedule 2>&1); check $? 1 "--schedule whose core crashed: refused (a probe that could not tell never passes)"
echo "$out" | grep -q "could not tell whether this host runs it (exit 1: boom: the core died)"; check $? 0 "  with its exit code and last stderr line"
printf '#!/bin/sh\n[ "$1" = where ] && { echo "vault %s"; echo "regatta MISSING"; exit 1; }\nexit 1\n' "$V" > "$T/stubmod/bin/weekly-run"
out=$(sh "$T/stubmod/install.sh" --schedule 2>&1); check $? 1 "  no core found: refused too"
echo "$out" | grep -q "the regatta core is missing"; check $? 0 "    saying so"
printf '#!/bin/sh\n[ "$1" = where ] && { echo "vault %s"; echo "regatta %s"; exit 0; }\nexit 1\n' "$T/no-such-vault" "$R/modules/regatta/bin/regatta" > "$T/stubmod/bin/weekly-run"
out=$(sh "$T/stubmod/install.sh" --schedule 2>&1); check $? 1 "  a vault that is not a folder: refused (the dry run it replaced refused it)"
echo "$out" | grep -q "the vault $T/no-such-vault is not a folder"; check $? 0 "    saying so"
# Past the rule, the job's own dry run must plan the night: a stub that dies, or prints nothing
echo "$host" > "$REGATTA_CONFIG/aurora/host"
printf '#!/bin/sh\n[ "$1" = where ] && { echo "vault %s"; echo "regatta %s"; exit 0; }\necho "boom: the dry run died" >&2\nexit 1\n' "$V" "$R/modules/regatta/bin/regatta" > "$T/stubmod/bin/weekly-run"
out=$(sh "$T/stubmod/install.sh" --schedule 2>&1); check $? 1 "--schedule whose dry run crashed past the rule: refused (the AGENTS.md trap)"
echo "$out" | grep -q "its dry run planned no night (exit 1: boom: the dry run died)"; check $? 0 "  with its exit code and last stderr line"
printf '#!/bin/sh\n[ "$1" = where ] && { echo "vault %s"; echo "regatta %s"; exit 0; }\nexit 0\n' "$V" "$R/modules/regatta/bin/regatta" > "$T/stubmod/bin/weekly-run"
out=$(sh "$T/stubmod/install.sh" --schedule 2>&1); check $? 1 "  a dry run that printed nothing, exit 0: refused too"
echo "$out" | grep -q "its dry run planned no night (exit 0)"; check $? 0 "    saying so"
check "$(ls "$T/agents" 2>/dev/null | wc -l | tr -d ' ')" 0 "  no plist written"
echo "$host" > "$REGATTA_CONFIG/aurora/host"
sh "$D/install.sh" --schedule >/dev/null; check $? 0 "--schedule without an overlay"
check "$(python3 -c "import plistlib,sys; p=plistlib.load(open(sys.argv[1],'rb')); print(p['ProgramArguments'][1:], p['StartCalendarInterval'])" "$T/agents/test.aurora.plist")" \
  "['aurora', '$V'] {'Hour': 21, 'Minute': 0}" "  aurora in the vault, nightly 21:00"
python3 -c "import plistlib,sys,os; p=plistlib.load(open(sys.argv[1],'rb')); a=p['ProgramArguments'][0]; sys.exit(0 if a.endswith('/modules/aurora/bin/weekly-run') and os.access(a, os.X_OK) else 1)" "$T/agents/test.aurora.plist"
check $? 0 "  running this module's weekly-run"
grep -q "^bootstrap gui/$(id -u) $T/agents/test.aurora.plist" "$T/launchctl.log"; check $? 0 "  loaded"
sh "$D/install.sh" --check > "$T/check.out"; check $? 0 "--check: exit 0"
grep -q "^schedule: *plist written but not loaded" "$T/check.out"; check $? 0 "  names the plist (the scratch launchctl loads nothing)"
grep -q "^vault $V" "$T/check.out"; check $? 0 "  and where things are"
sh "$D/install.sh" --remove >/dev/null; check "$(ls "$T/agents" | wc -l | tr -d ' ')" 0 "--remove deletes the plist"

echo; echo "embark: the sitting's memo, written by code after the sextant"
# A made-up week: a D-shaped dream (an item quoting a section, a venture item, a question), a branches
# file, a sextant entry naming a PROPOSE item, the night's FAILED line; a scratch checkout with an origin.
EV="$T/ev"; EL="$T/el"; EG="$T/eg"; ED="$T/elogs"
mkdir -p "$EV/dreams" "$EV/ventures" "$EL/sextant" "$ED"
cat > "$EV/dreams/2026-10-18.md" <<'MD'
# Dream — 2026-10-18 (3 sessions)

## Do this now

Nothing.

## Numbers

| | Value (last week) |
| --- | --- |
| commits on main | 128 (208) |
| open branches | 151 (110) |

## P — proposed changes

- **D1 — P1. One rules diff** — see [the rules](../rules/x.md).
  The exact text is the subsection "D1's diff" below.
  - A — apply as written
  - B — not now

  Reversible: no

  ➤ Recommended: A

  ➤ Answer:

- **D2 — P2. The venture file catches up** — [ventures/x.md](../ventures/x.md).
  - A — apply
  - B — not now

  Reversible: yes

  ➤ Recommended: A

  ➤ Answer:

### D1's diff

```diff
-- old line
+- D9 — a new line that would read as an item
```

## Q — questions

- **D3 — Q1. Where does the lab live?**
  - A — a file
  - B — no file

  Reversible: yes

  ➤ Recommended: B

  ➤ Answer:

## Feedback from the owner
MD
cat > "$EV/dreams/2026-10-18-branches.md" <<'MD'
# Branches — 2026-10-18

P1. demo · `claude/h/2026-10-01-a` — C3 carried: carried by b; 99 % on main.
    ➤ Answer: drop

P2. demo · `claude/h/2026-10-02-c` — C6 abandoned; 0 % on main, idle 20 d; 2026-10-11 P3.
    ➤ Answer: resume (/pickup c)

## B would have archived

- demo · `claude/h/2026-10-01-a` · probably landed (P1)
MD
printf '# Sextant — 2026-10-19\n\nA finding → **PROPOSE D5** (the guard).\n' > "$EL/sextant/2026-10-19.md"
printf '## 13. Decisions\n\n- **D5 The guards fail\n  closed** (sextant F1): a hook that cannot start blocks.\n  ➤ Recommended: yes\n  ➤ Answer:\n' > "$EL/DESIGN.md"
printf '== tend\nFAILED tend 2026-10-18: bin/tend exit 1 — not tended: demo\nDRY https://github.com/o/layer/pull/7\n' > "$ED/2026-10-18-aurora.log"
echo '[{"reason": "Reversible: no", "doc": "/d/a.md", "age_h": 100}]' > "$T/ke.json"
mkdir -p "$EG"; git -C "$EG" init -q -b main; git -C "$EG" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m init
git init -q --bare "$T/eg-origin.git"; git -C "$EG" remote add origin "$T/eg-origin.git"
em() { WEEKLY_ANY_HOST=1 ATLAS_VAULT="$EV" ATLAS_LAYER="$EL" WEEKLY_LOG_DIR="$ED" WEEKLY_KEEL_EMBARK="$T/ke.json" WEEKLY_EMBARK_REPO="$EG" "$W" embark "$EV" "$@"; }
em --dry-run > "$T/memo.md"; check $? 0 "--dry-run: exit 0"
KP="$R/modules/keel/bin/keel"
check "$(python3 "$KP" parse "$T/memo.md" | python3 -c 'import json,sys; print(" ".join(i["id"] for i in json.load(sys.stdin)["items"]))')" \
  "D1 D3 D4 D5 D6 D7" "  the memo parses: the dream's D1 and D3 (its numbers kept), the branches item, the PROPOSE item, the charts PR, the FAILED line"
check "$(python3 "$KP" lint "$T/memo.md" 2>&1 | grep -c 'warning\|error')" 0 "  keel lint: no findings"
check "$(python3 "$KP" parse "$T/memo.md" | python3 -c 'import json,sys; print([len(i["options"]) for i in json.load(sys.stdin)["items"]])')" \
  "[2, 2, 3, 3, 3, 2]" "  every item keeps its options: a copied section (a fence, a D9 line) ends none early"
grep -q '^  \*\*From the dream.s section "D1.s diff", as written:\*\*$' "$T/memo.md"; check $? 0 "  the section D1 quotes is copied under it"
grep -q '^  > +- D9 — a new line' "$T/memo.md"; check $? 0 "    as a blockquote, which keel reads as prose"
grep -q "^- The dream's D2 (P2): The venture file catches up — answered in the vault: \[dreams/2026-10-18.md#L" "$T/memo.md"; check $? 0 "  the venture item: one pointer line, no D-item"
grep -qF "]($EV/rules/x.md)" "$T/memo.md"; check $? 0 "  a relative link made absolute"
check "$(grep -c '^| commits on main | 128 (208) | ↓ |$' "$T/memo.md")" 1 "  the numbers carry an arrow against last week"
check "$(grep -cE '^  \*\*C3 carried — 1\*\*$|^  \*\*C6 abandoned — 1\*\*$' "$T/memo.md")" 2 "  the branches item: a table per class"
grep -qE '^  \| P1 \| demo \| `claude/h/2026-10-01-a` \| drop \| .* \| B \|$' "$T/memo.md"; check $? 0 "    every branch with its verdict, B where the B list names it"
grep -q '^- \*\*D5 — The guards fail closed\*\* (sextant D5' "$T/memo.md"; check $? 0 "  the PROPOSE item, its wrapped title read whole"
grep -q '^  > FAILED tend 2026-10-18: bin/tend exit 1' "$T/memo.md"; check $? 0 "  the FAILED line, quoted"
grep -qF -- '- **D6 — The charts dry run: [layer#7](https://github.com/o/layer/pull/7)**' "$T/memo.md"; check $? 0 "  the charts dry run's PR, from the log's DRY line"
grep -q '^1 Reversible: no\|1 item in 1 doc' "$T/memo.md"; check $? 0 "  keel embark's count"
grep -q '^## Open feedback$' "$T/memo.md"; check $? 0 "  Open feedback last"
check "$(git -C "$EG" worktree list | wc -l | tr -d ' ')" 1 "  a dry run makes no worktree"
host=$(python3 -c "import sys; sys.path.insert(0, sys.argv[1]); import common; print(common.host_name())" "$R/modules/regatta/hooks")
day=$(date +%F); br="claude/$host/$day-embark"; edoc="$EG/.claude/worktrees/embark-$day/docs/embark/embark-$day.md"
out=$(em); check "$? $out" "0 EMBARK $edoc" "a real run: the memo committed and handed to keel line (echo here)"
check "$(git -C "$T/eg-origin.git" log -1 --format=%s "$br" 2>&1)" "Embark: $day — the sitting's memo, written by weekly-run" "  pushed on $br"
check "$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["dream"], d["branch"], d["line"])' "$ED/embark-latest.json")" \
  "2026-10-18 $br $edoc" "  embark-latest.json names the dream, the branch and the line (atlas's bulletin reads it)"
echo "an answer" >> "$edoc"
out=$(em); check "$? $(tail -1 "$edoc")" "0 an answer" "  a second run that day keeps the memo as it is"
ewt="$EG/.claude/worktrees/embark-$day"
git -C "$T/eg-origin.git" branch -q -D "$br"
out=$(em); check "$? $(git -C "$T/eg-origin.git" log -1 --format=%s "$br" 2>&1)" "0 Embark: $day — the sitting's memo, written by weekly-run" "  a re-run pushes a branch the first run's push never reached"
check "$(git -C "$ewt" status --porcelain -- "docs/embark/embark-$day.md")" " M docs/embark/embark-$day.md" "  …and still commits none of the owner's answers"
git -C "$ewt" rm -q --cached -- "docs/embark/embark-$day.md" && git -C "$ewt" -c user.name=t -c user.email=t@example.invalid commit -q -m untrack
out=$(em); check "$? $(git -C "$ewt" ls-files -- "docs/embark/embark-$day.md")" "0 docs/embark/embark-$day.md" "  a memo the first run never committed is committed on a re-run"
rm -rf "$EV/dreams" "$edoc"; mkdir "$EV/dreams"
out=$(em); check "$?" 1 "no dream: exit 1"
check "$(echo "$out" | grep -c '^FAILED embark ')" 1 "  one FAILED embark line"

echo; echo "capped: the session's group, its cap and a passed signal"
# The wrapper's python, lifted from weekly-run: the night itself needs claude. The early-TERM race
# and the zombie-only EPERM are timing, not cases; the overlay's kill cases load them (2026-10-21).
python3 - "$W" > "$T/capped.py" <<'EOF'
import re, sys
print(re.search(r"python3 -c '\n(.*?)\n' \"\$CAP\"", open(sys.argv[1]).read(), re.S).group(1))
EOF
export WEEKLY_CAP_MARK="$T/capmark"
python3 "$T/capped.py" 5 sh -c 'exit 3'; check $? 3 "the session's exit code"
python3 "$T/capped.py" 1 sleep 30; check $? 124 "at the cap: 124"
check "$([ -e "$T/capmark" ] && echo marked)" marked "  and the mark"
python3 "$T/capped.py" 60 sh -c "trap '' TERM; echo \$\$ > '$T/grp'; sleep 100" & w=$!
sleep 1; t0=$(date +%s); kill -TERM $w; sleep 3; kill -TERM $w 2>/dev/null; wait $w
check $? 143 "a TERM to the wrapper is re-raised: 143"
s=$(( $(date +%s) - t0 )); check "$([ $s -ge 14 ] && [ $s -le 17 ] && echo one)" one "  after one 15 s grace, a second TERM ignored (${s}s)"
check "$(kill -0 -- -"$(cat "$T/grp")" 2>/dev/null && echo alive || echo gone)" gone "  and the group, TERM-deaf, is gone"

echo; [ $fails -eq 0 ] && echo "all passed" || { echo "$fails FAILED"; exit 1; }
