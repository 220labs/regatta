#!/usr/bin/env bash
# schedule: the weekly /sextant job (the design's G29) and the module's own runner. install.sh's
# --plist with aurora present (its weekly-run) and absent (libexec/sextant-run, from a copy of the
# core and this module alone), --schedule against a stub launchctl, and sextant-run's where and run
# with a stand-in claude. Scratch HOME and config dir, any OS; no launchd, no network, no model.
#   bash modules/sextant/tests/schedule.sh
set -u
D="$(cd "$(dirname "$0")/.." && pwd -P)"
R="$(cd "$D/../.." && pwd -P)"
T=$(mktemp -d); T="$(cd "$T" && pwd -P)"; trap 'rm -rf "$T"' EXIT
export HOME="$T/h" REGATTA_CONFIG="$T/cfg" CLAUDE_CONFIG_DIR="$T/cc"
unset REGATTA_HOME REGATTA_LEGACY SEXTANT_LABEL SEXTANT_LOG SEXTANT_WEEKLY SEXTANT_CWD SEXTANT_WEEKDAY SEXTANT_HOUR \
      SEXTANT_LAUNCH_DIR SEXTANT_LAUNCHCTL SEXTANT_CLAUDE SEXTANT_CAP SEXTANT_LOG_DIR SOUNDINGS_BY_HAND WEEKLY_RUN \
      ATLAS_LAYER ATLAS_VAULT SPARKS_CONFIG CLAUDE_BULLETIN
fails=0
check() { if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3: expected [$2] got [$1]"; fails=$((fails+1)); fi; }
has() { case "$1" in *"$2"*) echo "  ok   $3";; *) echo "  FAIL $3: missing [$2] in [$1]"; fails=$((fails+1));; esac; }
mkdir -p "$HOME" "$REGATTA_CONFIG/atlas" "$CLAUDE_CONFIG_DIR" "$T/layer" "$T/vault"
printf 'lay\n%s\n' "$T/layer" > "$REGATTA_CONFIG/atlas/layer"; printf 'vlt\n%s\n' "$T/vault" > "$REGATTA_CONFIG/atlas/vault"
pl() { python3 -c 'import plistlib, sys; p = plistlib.load(open(sys.argv[1], "rb")); print(eval(sys.argv[2]))' "$1" "$2"; }
I() { sh "$D/install.sh" "$@"; }
SR="$D/libexec/sextant-run"
# A copy of the core and this module alone: aurora, atlas and every other peer absent (AGENTS.md's trap)
NP="$T/np"; mkdir -p "$NP/.claude-plugin" "$NP/modules"
cp "$R/.claude-plugin/marketplace.json" "$NP/.claude-plugin/"; cp -R "$R/modules/regatta" "$D" "$NP/modules/"

echo "sextant-run where — the skill's placeholders"
wh() { python3 "$SR" where | sed -n "s/^$1 //p"; }
check "$(wh layer) $(wh layer-name)" "$T/layer lay" "the layer and its name, through atlas's reader"
check "$(wh vault) $(wh vault-name)" "$T/vault vlt" "the vault and its name"
check "$(wh module)" "$D" "the module"
check "$(wh regatta)" "$R/modules/regatta/bin/regatta" "the core's CLI beside it"
check "$(wh owner)" "the owner" "no regatta/owner: \"the owner\""
mkdir -p "$REGATTA_CONFIG/regatta"; echo Sam > "$REGATTA_CONFIG/regatta/owner"
check "$(wh owner)" "Sam" "  the core's key when set"; rm "$REGATTA_CONFIG/regatta/owner"
check "$(wh ideas)" "MISSING" "no Sparks config: the ideas pool is MISSING"
python3 "$SR" where >/dev/null; check $? 0 "  exit 0: the layer and the vault are found"
out=$(python3 "$NP/modules/sextant/libexec/sextant-run" where 2>&1); check $? 3 "atlas absent: exit 3 (a refusal, never 1: a crash's code)"
check "$(printf '%s\n' "$out" | sed -n 's/^layer //p') $(printf '%s\n' "$out" | grep -c Traceback)" "MISSING 0" "  the layer MISSING, said in its line, no stack trace"
check "$(printf '%s\n' "$out" | sed -n 's/^reports //p')" "MISSING" "  plumb absent too: the usage reports MISSING"
check "$(wh reports | sed "s|^$T/h/.*/reports\$|plumb's default, under HOME|")" "plumb's default, under HOME" "plumb's usage reports, through its own config reader"
SEXTANT_CAP=3h python3 "$SR" where >/dev/null 2>&1; check $? 0 "a stray SEXTANT_CAP does not crash where"
python3 "$SR" bogus >/dev/null 2>&1; check $? 2 "an unknown verb exits 2"

echo "install.sh --plist — aurora's weekly-run when it is installed (G29)"
# From a linked worktree the plist names the main checkout's files (install.sh's rule): expect those.
JR=$R; gc=$(git -C "$D" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
[ -n "$gc" ] && [ "$(basename "$gc")" = .git ] && [ -d "$(dirname "$gc")/modules/sextant" ] && JR=$(dirname "$gc")
I --plist > "$T/a.plist"; check $? 0 "--plist exits 0"
check "$(pl "$T/a.plist" 'p["ProgramArguments"]')" "['$JR/modules/aurora/bin/weekly-run', 'sextant', '$T/layer']" "  runs weekly-run sextant <the layer>"
check "$(pl "$T/a.plist" 'p["Label"], sorted(p["StartCalendarInterval"].items())')" "('dev.regatta.sextant', [('Hour', 2), ('Minute', 0), ('Weekday', 1)])" "  its label, Monday 02:00"
check "$(pl "$T/a.plist" 'p["StandardOutPath"] == p["StandardErrorPath"], p["StandardOutPath"]')" "(True, '$T/h/.local/state/regatta/sextant-launchd.log')" "  one log, in the core's log dir"
check "$(pl "$T/a.plist" 'sorted(p.get("EnvironmentVariables", {}))')" "['REGATTA_CONFIG']" "  the config dir carried, no PATH (weekly-run sets its own)"
SEXTANT_LABEL=org.example.sextant SEXTANT_LOG="$T/w.log" SEXTANT_WEEKLY="$T/ov/bin/weekly-run" SEXTANT_CWD="$T/ov" SEXTANT_WEEKDAY=3 SEXTANT_HOUR=4 \
  I --plist > "$T/k.plist"
check "$(pl "$T/k.plist" 'p["Label"], p["ProgramArguments"], p["StandardOutPath"], p["StartCalendarInterval"]["Weekday"], p["StartCalendarInterval"]["Hour"]')" \
  "('org.example.sextant', ['$T/ov/bin/weekly-run', 'sextant', '$T/ov'], '$T/w.log', 3, 4)" "  an overlay's knobs: its label, log, weekly-run shim, folder and slot"
mv "$REGATTA_CONFIG/atlas/layer" "$T/layer.off"
out=$(I --plist 2>&1); check $? 1 "no layer and no SEXTANT_CWD: refused"
check "$(printf '%s\n' "$out" | wc -l | tr -d ' ') $(printf '%s\n' "$out" | grep -c 'no folder for /sextant')" "1 1" "  in one line"
mv "$T/layer.off" "$REGATTA_CONFIG/atlas/layer"

echo "install.sh --plist — aurora absent: the module's own runner (G29)"
SEXTANT_CWD="$T/layer" sh "$NP/modules/sextant/install.sh" --plist > "$T/o.plist"; check $? 0 "--plist exits 0 without aurora"
check "$(pl "$T/o.plist" 'p["ProgramArguments"]')" "['/usr/bin/python3', '$NP/modules/sextant/libexec/sextant-run', 'run', '$T/layer']" "  runs libexec/sextant-run run <folder>"
has "$(pl "$T/o.plist" 'p["EnvironmentVariables"]["PATH"]')" "$T/h/.local/bin" "  with a PATH that finds claude"
out=$(sh "$NP/modules/sextant/install.sh" --check 2>&1)
has "$out" "weekly:     aurora absent — the module's own runner" "--check names the runner"
has "$out" "launch:     pickup, dispatch, keel absent" "  and the launch's absent peers (G27)"

echo "install.sh --schedule against a stub launchctl"
LC="$T/lc"; printf '#!/bin/sh\necho "$*" >> "%s"\n[ "$1" = print ] && { [ -f "%s" ] && echo "pid = 7"; exit 1; }\nexit 0\n' "$T/lc.log" "$T/running" > "$LC"; chmod +x "$LC"
export SEXTANT_LAUNCHCTL="$LC" SEXTANT_LAUNCH_DIR="$T/la"
out=$(I --schedule --dry-run); check $? 0 "--schedule --dry-run exits 0"
has "$out" "<string>dev.regatta.sextant</string>" "  prints the plist"
has "$out" "nothing written or loaded" "  says it touched nothing"
check "$(ls "$T/la" 2>/dev/null | wc -l | tr -d ' ') $(cat "$T/lc.log" 2>/dev/null | wc -l | tr -d ' ')" "0 0" "  no plist written, launchctl never called"
[ ! -e "$T/h/.local/state" ]; check $? 0 "  and no log folder made"
I --schedule >/dev/null; check $? 0 "--schedule exits 0"
check "$(pl "$T/la/dev.regatta.sextant.plist" 'p["ProgramArguments"][1]')" "sextant" "  the plist written"
check "$(grep -cE '^(bootout|bootstrap) ' "$T/lc.log")" 2 "  bootout, then bootstrap"
touch "$T/running"; : > "$T/lc.log"; rm "$T/la/dev.regatta.sextant.plist"
out=$(I --schedule 2>&1); check $? 1 "the job running right now: refused"
has "$out" "is running right now" "  said so"
check "$(ls "$T/la" | wc -l | tr -d ' ') $(grep -c '^bootout' "$T/lc.log")" "0 0" "  nothing written, nothing booted out"
rm "$T/running"; I --schedule >/dev/null; touch "$T/running"
I --unschedule >/dev/null 2>&1; check $? 1 "--unschedule while the job runs: refused"
[ -e "$T/la/dev.regatta.sextant.plist" ]; check $? 0 "  the plist kept"
rm "$T/running"; I --unschedule >/dev/null; check $? 0 "--unschedule exits 0"
[ ! -e "$T/la/dev.regatta.sextant.plist" ]; check $? 0 "  the plist removed"
I --schedule --bogus >/dev/null 2>&1; check $? 2 "--schedule with anything but --dry-run: a usage error"
mkdir -p "$REGATTA_CONFIG/regatta"; touch "$REGATTA_CONFIG/regatta/overlay"; out=$(I --schedule 2>&1); check $? 1 "an overlay installed (its marker): --schedule refused"
has "$out" "schedules /sextant itself" "  said so"; rm "$REGATTA_CONFIG/regatta/overlay"
unset SEXTANT_LAUNCHCTL SEXTANT_LAUNCH_DIR

echo "sextant-run run — the own runner, with a stand-in claude"
export SEXTANT_LOG_DIR="$T/logs"; lg="$T/logs/$(date +%Y-%m-%d)-sextant.log"
out=$(python3 "$SR" run "$T/layer" --dry-run); check $? 0 "--dry-run exits 0"
has "$out" "Bash(*regatta dispatch*)" "  dispatch denied"
has "$out" "Bash(*bin/pickup*)" "  pickup denied"
has "$out" "Bash(git * push*)" "  a push in any git form denied"
check "$(printf '%s\n' "$out" | grep -cE 'Bash\(git (-C|branch):')" 0 "  no git -C or git branch prefix: either would pass a push or a delete"
check "$(printf '%s\n' "$out" | grep -cxF '  Bash(*dispatch*)')" 0 "  a read naming dispatch (its logs, G3) is not denied by the word"
has "$out" "regatta which:*)" "  which allowed (the skill's jev recheck)"
has "$out" "soundings next:*)" "  the queue's reading verbs allowed"
check "$(printf '%s\n' "$out" | sed -n '/^allowed:/,/^denied:/p' | grep -cE 'dispatch|pickup|soundings (add|mark)')" 0 "  and no writer that starts work"
[ ! -e "$lg" ]; check $? 0 "  nothing logged, nothing run"
SEXTANT_CLAUDE="printf '%s\n' \"\$SEXTANT_DENIED\" > $T/d; echo \"\$WEEKLY_RUN|\$SOUNDINGS_BY_HAND|\$PWD\" > $T/e" python3 "$SR" run "$T/layer"
check $? 0 "a run that ends well exits 0"
check "$(cut -d'|' -f1,3 "$T/e")" "sextant|$T/layer" "  in the folder, WEEKLY_RUN=sextant (soundings' refusals read it)"
has "$(cut -d'|' -f2 "$T/e")" "schedules nothing" "  SOUNDINGS_BY_HAND set: next gives the owner's lines (G27)"
grep -qxF 'Bash(*soundings add*)' "$T/d"; check $? 0 "  soundings add denied"
check "$(tail -1 "$lg" | cut -d' ' -f2-)" "ENDED rc=0" "  the log ends ENDED rc=0"
SEXTANT_CLAUDE="exit 3" python3 "$SR" run "$T/layer"; check $? 1 "a run that fails exits 1"
check "$(tail -1 "$lg" | cut -d' ' -f2-)" "ENDED rc=3" "  with its code logged"
s=$(date +%s); SEXTANT_CAP=1 SEXTANT_CLAUDE="sleep 30" python3 "$SR" run "$T/layer"; check $? 1 "a run past its cap is ended, exit 1"
check "$([ $(( $(date +%s) - s )) -lt 20 ] && echo soon)" soon "  within the grace, not after the sleep"
check "$(tail -1 "$lg" | cut -d' ' -f2-)" "FAILED: capped at 1 s, the run ended" "  and logged"
SEXTANT_CAP=1 SEXTANT_CAP_GRACE=2 SEXTANT_CLAUDE="(trap '' TERM; exec sleep 41.5) & sleep 30" python3 "$SR" run "$T/layer"
sleep 1; check "$(pgrep -f 'sleep 41.5' | wc -l | tr -d ' ')" 0 "  a child that ignores TERM is killed with the group, not left running"
echo "sextant-run run — the host rule: it asks the core's (common.weekly_host; its branches are the core's suite's)"
mkdir -p "$REGATTA_CONFIG/aurora"; AH="$REGATTA_CONFIG/aurora/host"; SKH="$REGATTA_CONFIG/aurora/skip-hosts"
host=$(python3 -c "import sys; sys.path.insert(0, sys.argv[1]); import common; print(common.host_name())" "$R/modules/regatta/hooks")
posts() { local n; n=$(grep -c -- "$1" "$T/vault/bulletin.md" 2>/dev/null); echo "${n:-0}"; }  # bulletin lines matching $1
echo "$host" > "$AH"
rm -f "$T/ran"; : > "$lg"; out=$(SEXTANT_CLAUDE="touch $T/ran" python3 "$SR" run "$T/layer"); check $? 0 "aurora/host names this host: exit 0"
[ -e "$T/ran" ]; check $? 0 "  the run ran"
echo host-a > "$AH"
rm -f "$T/ran"; : > "$lg"; out=$(SEXTANT_CLAUDE="touch $T/ran" python3 "$SR" run "$T/layer"); check $? 0 "a skip: exit 0"
[ ! -e "$T/ran" ]; check $? 0 "  nothing run"
has "$(cat "$lg")" "skipped: sextant does not run on $host (aurora/host names host-a; sextant install.sh --schedule refuses here, --unschedule removes" "  the core's line logged, sextant's own hint"
check "$(posts 'refused to run')" 0 "  and posts nothing (a skip is no failure)"
out=$(SEXTANT_LAUNCHCTL="$LC" SEXTANT_LAUNCH_DIR="$T/la2" I --schedule 2>&1); check $? 1 "  install.sh --schedule there: refused"
has "$out" "install.sh --schedule: skipped: sextant does not run on $host" "    quoting the core's skip"
[ ! -e "$T/la2" ]; check $? 0 "    no plist written"
: > "$AH"
rm -f "$T/ran"; out=$(SEXTANT_CLAUDE="touch $T/ran" python3 "$SR" run "$T/layer" --dry-run); check $? 1 "a refusal (aurora/host empty), dry run: exit 1"
check "$(posts 'the unattended sextant refused to run')" 0 "  a dry run posts nothing"
rm -f "$T/ran"; : > "$lg"; out=$(SEXTANT_CLAUDE="touch $T/ran" python3 "$SR" run "$T/layer"); check $? 1 "  a real run: exit 1"
[ ! -e "$T/ran" ]; check $? 0 "    nothing run"
has "$out" "refused: aurora/host is empty" "    the core's line"
check "$(posts 'the unattended sextant refused to run')" 1 "    one bulletin line, as weekly-run posts its refusal"
has "$(grep 'the unattended sextant refused to run' "$T/vault/bulletin.md")" "aurora/host is empty: it names no host to run on. Log: $lg" "    naming the reason and the log"
out=$(SEXTANT_LAUNCHCTL="$LC" SEXTANT_LAUNCH_DIR="$T/la2" I --schedule 2>&1); check $? 1 "  install.sh --schedule: refused"
has "$out" "refused: aurora/host is empty" "    quoting the refusal"
rm -f "$T/ran"; : > "$lg"; out=$(SEXTANT_CLAUDE="touch $T/ran" python3 "$NP/modules/sextant/libexec/sextant-run" run "$T/layer"); check $? 1 "  atlas absent: exit 1"
check "$(grep -c 'refused: aurora/host is empty' "$lg") $(posts 'the unattended sextant refused to run')" "1 1" "    the log line alone, said once (no second post)"
rm "$AH"; echo nohost > "$SKH"
rm -f "$T/ran"; : > "$lg"; out=$(SEXTANT_CLAUDE="touch $T/ran" python3 "$SR" run "$T/layer"); check $? 0 "a note from the core (skip-hosts deprecated): the run runs"
check "$(printf '%s\n' "$out" | grep -c '^note: aurora/skip-hosts is deprecated') $(grep -c 'note: aurora/skip-hosts is deprecated' "$lg")" "1 1" "  the note said once, and logged"
rm "$SKH"
# A probe that could not tell: no core found from a copy of the module alone, or a core that crashed
SXC="$T/sxcopy"; cp -R "$D" "$SXC"
out=$(SEXTANT_LAUNCHCTL="$LC" SEXTANT_LAUNCH_DIR="$T/la2" sh "$SXC/install.sh" --schedule 2>&1); check $? 1 "install.sh --schedule with no core found: refused (a probe that could not tell never passes)"
has "$out" "could not tell whether this host runs /sextant (exit 2: " "  with its exit code and last stderr line"
FK="$T/fakecore/modules/regatta"; mkdir -p "$FK/hooks" "$FK/bin"; : > "$FK/hooks/common.py"
printf 'import sys\nsys.exit("boom: the core died")\n' > "$FK/bin/regatta"
out=$(REGATTA_HOME="$T/fakecore" SEXTANT_LAUNCHCTL="$LC" SEXTANT_LAUNCH_DIR="$T/la2" sh "$SXC/install.sh" --schedule 2>&1); check $? 1 "  a core that crashed: refused too"
has "$out" "could not tell whether this host runs /sextant (exit 1: boom: the core died)" "    saying so"
[ ! -e "$T/la2" ]; check $? 0 "  no plist written"
echo "$host" > "$AH"
out=$(SEXTANT_CWD="$T/no-such-dir" SEXTANT_LAUNCHCTL="$LC" SEXTANT_LAUNCH_DIR="$T/la2" I --schedule 2>&1); check $? 1 "install.sh --schedule, SEXTANT_CWD not a folder: refused (the dry run it replaced refused it)"
has "$out" "$T/no-such-dir is not a folder" "  saying so"
[ ! -e "$T/la2/dev.regatta.sextant.plist" ]; check $? 0 "  no plist written"
OC="$T/oldcore"; mkdir -p "$OC/modules"; cp -R "$R/modules/regatta" "$R/modules/atlas" "$OC/modules/"
sed -i.bak 's/^def weekly_host(/def gone_weekly_host(/' "$OC/modules/regatta/hooks/common.py" && rm -f "$OC/modules/regatta/hooks/common.py.bak"
rm -f "$T/ran"; : > "$lg"; out=$(REGATTA_HOME="$OC" SEXTANT_CLAUDE="touch $T/ran" python3 "$SXC/libexec/sextant-run" run "$T/layer" 2>&1); check $? 1 "sextant-run on a core older than the rule: refused, exit 1 (never a traceback)"
[ ! -e "$T/ran" ]; check $? 0 "  nothing run"
has "$(cat "$lg")" "refused: the host rule could not be read (AttributeError:" "  logged"
check "$(posts 'the unattended sextant refused to run')" 2 "  and posted (the second line of the suite)"
rm "$AH"
rm -f "$T/ran"; SEXTANT_CLAUDE="touch $T/ran" python3 "$SR" run "$T/layer" >/dev/null; check $? 0 "neither key and no overlay: it runs (an install on one machine)"
[ -e "$T/ran" ]; check $? 0 "  the run ran"
python3 "$SR" run "$T/nowhere" 2>/dev/null; check $? 1 "a folder that does not exist: refused"

echo; [ "$fails" = 0 ] && echo "schedule: all passed" || { echo "schedule: $fails FAILED"; exit 1; }
