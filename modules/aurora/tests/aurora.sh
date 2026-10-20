#!/usr/bin/env bash
# aurora's suite: weekly-run under a scratch HOME and config dir, every name made up. `where` from
# atlas's keys and their overrides; the refusals (no core, no vault, no skip-hosts beside an
# overlay); the skip on a listed host; tonight's plan; a night whose wharf is missing (the tend and
# the classify fail their own steps, the dream still runs and lands); the unattended skills'
# commands held to the allowlist; a plain launchd environment; install.sh against a scratch launchd.
# No network, no `claude` (WEEKLY_CLAUDE stands in), no real repo touched.
#   bash modules/aurora/tests/aurora.sh
set -u
D="$(cd "$(dirname "$0")/.." && pwd -P)"
R="$(cd "$D/../.." && pwd -P)"
W="$D/bin/weekly-run"
T="$(mktemp -d)"; T="$(cd "$T" && pwd -P)"
trap 'rm -rf "$T"' EXIT
export HOME="$T/home" REGATTA_CONFIG="$T/config" WEEKLY_LOG_DIR="$T/logs"
unset REGATTA_HOME REGATTA_LEGACY ATLAS_LAYER ATLAS_VAULT CLAUDE_CONFIG_DIR WEEKLY_ANY_HOST AURORA_SECTIONS \
      WEEKLY_TEND WEEKLY_CLASSIFY WEEKLY_COMMIT WEEKLY_PR WEEKLY_CLAUDE AURORA_TODAY AURORA_HOUR
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
: > "$REGATTA_CONFIG/aurora/skip-hosts"
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
touch "$REGATTA_CONFIG/legacy"
# Beside an overlay the core loads only with its five keys (common.OVERLAY_KEYS), made up here.
for k in owner guarded orca-deny log-dir projects; do echo "$T/$k" > "$REGATTA_CONFIG/regatta/$k"; done
check "$(wh vault)" "MISSING" "no key beside an overlay: no vault, never a guess"
"$W" where >/dev/null; check $? 1 "  exit 1"
out=$("$W" aurora "$T" --dry-run); check $? 1 "a run then refuses"
echo "$out" | grep -q "refused: atlas's vault is not configured"; check $? 0 "  and says which key"
mv "$REGATTA_CONFIG/atlas.off" "$REGATTA_CONFIG/atlas"

echo "the core present but not loading (a core key missing beside an overlay)"
mv "$REGATTA_CONFIG/regatta/owner" "$T/owner.off"
echo listed-host > "$REGATTA_CONFIG/aurora/skip-hosts"  # a listed file: the host must be known
out=$("$W" aurora "$T" --dry-run); check $? 1 "refused, never a night without its peers (B10 review)"
echo "$out" | grep -q "refused: the regatta core does not load — .*regatta/owner missing"; check $? 0 "  naming the missing key"
mv "$T/owner.off" "$REGATTA_CONFIG/regatta/owner"; : > "$REGATTA_CONFIG/aurora/skip-hosts"

echo "skip-hosts"
rm "$REGATTA_CONFIG/aurora/skip-hosts"
out=$("$W" aurora "$T" --dry-run); check $? 1 "no aurora/skip-hosts beside an overlay: refused"
echo "$out" | grep -q "refused: no .*aurora/skip-hosts"; check $? 0 "  naming the key"
check "$(WEEKLY_ANY_HOST=1 "$W" aurora "$T" --dry-run | head -1 | cut -c1-6)" "aurora" "  WEEKLY_ANY_HOST runs anyway"
rm "$REGATTA_CONFIG/legacy"
"$W" aurora "$T" --dry-run | grep -q "the night's order"; check $? 0 "no key and no overlay: no host is skipped"
host=$(python3 -c "import sys; sys.path.insert(0, sys.argv[1]); import common; print(common.host_name())" "$R/modules/regatta/hooks")
printf 'elsewhere\n%s\n' "$(printf %s "$host" | tr a-z A-Z)" > "$REGATTA_CONFIG/aurora/skip-hosts"
out=$("$W" aurora "$T" --dry-run); check $? 0 "this host listed (in capitals): exit 0"
check "$(echo "$out" | grep -c "skipped: aurora does not run on $host")" 1 "  skipped, said once"
"$W" aurora "$T"; check "$(grep -c "skipped: aurora does not run on $host" "$T/logs/$(date +%F)-aurora.log")" 1 "  a real run logs it and starts nothing"
printf '\xEF\xBB\xBF%s \r\n' "$host" > "$REGATTA_CONFIG/aurora/skip-hosts"
"$W" aurora "$T" --dry-run | grep -q "skipped: aurora does not run on $host"; check $? 0 "  a BOM, a trailing space and CRLF still match"
: > "$REGATTA_CONFIG/aurora/skip-hosts"

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
check "$(echo "$out" | grep -cE '^  [0-9] ')" 5 "  five steps, in order"
echo "$out" | grep -qE '^  2 classify +due '; check $? 0 "  classify due"
echo "$out" | grep -qE '^  5 dream +due .* must be on vlt main'; check $? 0 "  dream due, its proof named by the vault's name"
out=$(AURORA_TODAY=2026-10-18 AURORA_HOUR=12 "$W" aurora "$V" --dry-run)
echo "$out" | grep -q "nothing due tonight"; check $? 0 "a Sunday before 20:00: nothing due"
check "$(ls "$T/logs" | grep -c tried)" 0 "  a dry run records nothing"

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

echo "a plain launchd environment (no REGATTA_HOME, no PATH but /usr/bin:/bin)"
# launchd passes no REGATTA_CONFIG: the config dir is the default one under HOME.
mkdir -p "$HOME/.config"; cp -R "$REGATTA_CONFIG" "$HOME/.config/regatta"
out=$(env -i HOME="$HOME" PATH=/usr/bin:/bin "$W" where); check $? 0 "where: exit 0"
check "$(echo "$out" | sed -n 's/^vault //p')" "$V" "  the vault from the config dir under HOME"
env -i HOME="$HOME" PATH=/usr/bin:/bin "$W" aurora "$V" --dry-run | grep -q "the night's order"; check $? 0 "  --dry-run plans the night"
rm -rf "$HOME/.config/regatta"

echo "install.sh against a scratch launchd"
cat > "$T/launchctl" <<EOF
#!/bin/sh
echo "\$*" >> "$T/launchctl.log"
case "\$1" in print) exit 1 ;; esac
EOF
chmod +x "$T/launchctl"
export AURORA_LAUNCH_DIR="$T/agents" AURORA_LAUNCHCTL="$T/launchctl" AURORA_LABEL=test.aurora
touch "$REGATTA_CONFIG/legacy"
out=$(sh "$D/install.sh" --schedule 2>&1); check $? 1 "--schedule beside an overlay: refused"
echo "$out" | grep -q "schedules the night itself"; check $? 0 "  and says why"
check "$(ls "$T/agents" 2>/dev/null | wc -l | tr -d ' ')" 0 "  no plist written"
rm "$REGATTA_CONFIG/legacy"
python3 -c "import sys; sys.path.insert(0, sys.argv[1]); import common; print(common.host_name())" "$R/modules/regatta/hooks" > "$REGATTA_CONFIG/aurora/skip-hosts"
out=$(sh "$D/install.sh" --schedule 2>&1); check $? 1 "--schedule on a host aurora/skip-hosts lists: refused"
echo "$out" | grep -q "this host is in .*aurora/skip-hosts"; check $? 0 "  and says why"
: > "$REGATTA_CONFIG/aurora/skip-hosts"
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

echo; [ $fails -eq 0 ] && echo "all passed" || { echo "$fails FAILED"; exit 1; }
