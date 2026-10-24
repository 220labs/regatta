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
echo listed-host > "$REGATTA_CONFIG/aurora/skip-hosts"  # a listed file: the host must be known
out=$("$W" aurora "$T" --dry-run); check $? 1 "refused, never a night without its peers (B10 review)"
echo "$out" | grep -q "refused: the regatta core does not load — .*regatta/owner missing"; check $? 0 "  naming the missing key"
mv "$T/owner.off" "$REGATTA_CONFIG/regatta/owner"; : > "$REGATTA_CONFIG/aurora/skip-hosts"

echo "skip-hosts"
rm "$REGATTA_CONFIG/aurora/skip-hosts"
out=$("$W" aurora "$T" --dry-run); check $? 1 "no aurora/skip-hosts beside an overlay: refused"
echo "$out" | grep -q "refused: no .*aurora/skip-hosts"; check $? 0 "  naming the key"
"$W" aurora "$T" --due >/dev/null; check $? 0 "  --due on a refusal: exit 0, so the run Orca starts logs and posts it (a failed precheck is a silent skip)"
check "$(WEEKLY_ANY_HOST=1 "$W" aurora "$T" --dry-run | head -1 | cut -c1-6)" "aurora" "  WEEKLY_ANY_HOST runs anyway"
rm "$REGATTA_CONFIG/regatta/overlay"
"$W" aurora "$T" --dry-run | grep -q "the night's order"; check $? 0 "no key and no overlay: no host is skipped"
host=$(python3 -c "import sys; sys.path.insert(0, sys.argv[1]); import common; print(common.host_name())" "$R/modules/regatta/hooks")
printf 'elsewhere\n%s\n' "$(printf %s "$host" | tr a-z A-Z)" > "$REGATTA_CONFIG/aurora/skip-hosts"
out=$("$W" aurora "$T" --dry-run); check $? 0 "this host listed (in capitals): exit 0"
check "$(echo "$out" | grep -c "skipped: aurora does not run on $host")" 1 "  skipped, said once"
"$W" aurora "$T" --due >/dev/null; check $? 3 "  --due on a skipped host: exit 3, the clock's precheck starts no session"
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
rm -rf "$HOME/.config/regatta"

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
