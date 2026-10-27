#!/usr/bin/env bash
# bin/sheep's read of the control daemon as it runs (docs/sheep-listen-2026-10-24.md, section 4):
# `sheep check` fails on a dead daemon and names the fix, `sheep control` says the same, and a plan
# without Talk makes it expected, not a failure. A stub sessionpipe (its `control status` prints
# $T/status) and a stub launchctl (`print` exits with $T/lc-rc); HOME and every config dir scratch,
# so no real settings file, control.json or daemon is read. The rest of bin/sheep's cases are
# the overlay's own suite.
#                                                          bash modules/keel/tests/sheep_control.sh
set -u
B="$(cd "$(dirname "$0")/../bin" && pwd)"
T=$(mktemp -d)
T=$(cd "$T" && pwd -P)
trap 'rm -rf "$T"' EXIT
. "$(dirname "$0")/config.sh"; keel_config "$T/config"   # before HOME moves: the core through its `home` file
fails=0
check() { if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3: expected [$2] got [$1]"; fails=$((fails+1)); fi; }
has()   { if grep -qF -- "$2" "$1"; then echo "  ok   $3"; else echo "  FAIL $3: missing [$2]"; fails=$((fails+1)); fi; }
lacks() { if grep -qF -- "$2" "$1"; then echo "  FAIL $3: found [$2]"; fails=$((fails+1)); else echo "  ok   $3"; fi; }

H="$T/home"   # the scratch home
export HOME="$H" XDG_CONFIG_HOME="$H/.config" XDG_STATE_HOME="$H/.local/state"
export SHEEP_SESSIONPIPE="$T/bin/sessionpipe" SHEEP_LAUNCHCTL="$T/bin/launchctl" SHEEP_SPACESHEEP="$T/bin/spacesheep"
export SHEEP_LAUNCH_AGENTS="$T/LaunchAgents" SHEEP_PROJECTS="$H/projects" SHEEP_ENV_FILE="$T/none.env"
export REGATTA_SHEEP_DIR="$T/sheep-dir"
unset SESSIONPIPE_CONFIG SPACESHEEP_KEY REGATTA_SHEEP_PLAN
unset BASH_ENV   # a CI job's PATH, re-read by every bash stub (keel.sh says why)
mkdir -p "$T/bin" "$H/.config/sessionpipe" "$H/projects" "$SHEEP_LAUNCH_AGENTS"
cat > "$T/bin/sessionpipe" <<EOF
#!/bin/sh
echo "\$*" >> "$T/sp.log"
[ "\$1 \$2" = "control status" ] && cat "$T/status"
exit 0
EOF
cat > "$T/bin/launchctl" <<EOF
#!/bin/sh
echo "\$*" >> "$T/lc.log"
[ "\$1" = print ] && exit "\$(cat "$T/lc-rc" 2>/dev/null || echo 0)"
exit 0
EOF
printf '#!/bin/sh\nexit 1\n' > "$T/bin/spacesheep"   # a CLI that reads no plan, never the Mac's real one
chmod +x "$T/bin/"*
echo '{"machine": "TestMac", "sinks": [], "update_check": false}' > "$H/.config/sessionpipe/config.json"
cat > "$H/.config/sessionpipe/control.json" <<'EOF'
{"name": "TestMac", "mode": "auto", "folders": [],
 "receivers": [{"url": "https://spacesheep.dev", "machine": "m_x", "token": "tok", "keys": []}]}
EOF
status() {  # status up|401|down — what `sessionpipe control status` prints
  case "$1" in
    up)   printf '{\n  "version": "0.5.0",\n  "receivers": [{"url": "https://spacesheep.dev", "machine": "m_x", "polling": true, "last_error": null}]\n}\n' ;;
    401)  printf '{\n  "version": "0.5.0",\n  "receivers": [{"url": "https://spacesheep.dev", "machine": "m_x", "polling": false, "last_error": "the receiver no longer knows this machine (401)"}]\n}\n' ;;
    down) printf '  the control daemon isn'"'"'t running\n' ;;
    *)    printf '%s\n' "$1" ;;
  esac > "$T/status"
}
sc() { python3 "$B/sheep" check > "$T/out" 2>&1; echo $?; }

echo "sheep check — the control daemon as it runs"
status up
check "$(sc)" "0" "a daemon polling its receiver: check passes"
has "$T/out" "control daemon: up, polling spacesheep.dev" "…and says so"
status 401
check "$(sc)" "1" "the receiver's 401, polling false: check fails (23 to 25 Oct, read as paired)"
has "$T/out" "control: 1 problem" "…counted in the summary line"
has "$T/out" "control daemon DEAD: spacesheep.dev: the receiver no longer knows this machine (401)" "…naming the receiver's error"
has "$T/out" "re-pair in the owner's terminal (a passkey tap): sessionpipe control pair spacesheep.dev --mode auto --name TestMac" "…and the fix: the owner's re-pair"
lacks "$T/out" "control daemon: up" "…never up"
status '{"receivers": [{"url": "https://spacesheep.dev", "polling": true, "last_error": "fetch failed: the session is not running"}]}'
check "$(sc)" "0" "polling, with a last_error left by a blip: up, never a re-pair (sessionpipe clears it on the next good poll)"
has "$T/out" "control daemon: up, polling spacesheep.dev; last error from spacesheep.dev: fetch failed" "…the error named beside it"
lacks "$T/out" "re-pair" "…and no passkey tap asked for"
status '{"receivers": [{"url": "https://spacesheep.dev", "polling": true, "last_error": "HTTP 403"}]}'
check "$(sc)" "1" "polling, but every answer a 403: stuck for good, check fails"
status down; echo 113 > "$T/lc-rc"
check "$(sc)" "1" "not running, no plist and no job (pair --no-service): check fails"
has "$T/out" "start it by hand: sessionpipe control run" "…the fix: run it by hand, never a kickstart or a bootstrap of a file that is not there"
echo '<plist/>' > "$SHEEP_LAUNCH_AGENTS/org.sessionpipe.control.plist"
echo 0 > "$T/lc-rc"
check "$(sc)" "1" "not running, its launchd job loaded: check fails"
has "$T/out" "control daemon DEAD: the control daemon isn't running — " "…saying so"
has "$T/out" 'launchctl kickstart -k gui/$(id -u)/org.sessionpipe.control' "…the fix: kickstart the job"
echo 113 > "$T/lc-rc"
check "$(sc)" "1" "not running, its launchd job unloaded (after the owner's re-pair): check fails"
has "$T/out" "its launchd job org.sessionpipe.control is not loaded" "…saying the job is not loaded"
has "$T/out" "launchctl bootstrap gui/\$(id -u) $SHEEP_LAUNCH_AGENTS/org.sessionpipe.control.plist" "…the fix: bootstrap the plist"
has "$T/lc.log" "print gui/$(id -u)/org.sessionpipe.control" "…read from launchctl print"
rm -f "$SHEEP_LAUNCH_AGENTS/org.sessionpipe.control.plist"
status "  ✓ spacesheep.dev: asked to delete"
check "$(sc)" "0" "a status this tool cannot read: said, never a failure (the overlay suite's stub prints nothing of the kind)"
has "$T/out" "control daemon: not read (sessionpipe control status said '✓ spacesheep.dev: asked to delete')" "…as not read"
: > "$T/status"
check "$(sc)" "0" "an empty status: the same"

echo "sheep check — a plan without Talk: a dead daemon is expected"
status 401
check "$(REGATTA_SHEEP_PLAN=free sc)" "0" "Free: the dead daemon passes"
has "$T/out" "control daemon: spacesheep.dev: the receiver no longer knows this machine (401) — expected: Talk needs spacesheep Pro" "…and the line names the plan"
check "$(REGATTA_SHEEP_PLAN=pro-off sc)" "0" "Pro with Talk off: the same"
has "$T/out" "expected: Talk is off for this account" "…named so"
check "$(REGATTA_SHEEP_PLAN=pro sc)" "1" "Pro: a failure"
check "$(sc)" "1" "no plan read (spacesheep answers nothing): counted as having Talk, a failure (spacesheep-tiers' rule)"

echo "sheep control — reports the daemon, not only control.json"
status 401
python3 "$B/sheep" control --dry-run > "$T/out" 2>&1
has "$T/out" "control: paired with spacesheep.dev (machine m_x), mode auto" "control still says what control.json holds"
has "$T/out" "  daemon DEAD: spacesheep.dev: the receiver no longer knows this machine (401)" "…and then what runs"
status up
python3 "$B/sheep" control --dry-run > "$T/out" 2>&1
has "$T/out" "  daemon: up, polling spacesheep.dev" "…up when it is"
rm "$H/.config/sessionpipe/control.json"; : > "$T/sp.log"
sc > /dev/null
lacks "$T/sp.log" "control status" "unpaired: the daemon is never asked"

echo
[ "$fails" = 0 ] && echo "sheep_control: all passed" || echo "sheep_control: $fails FAILED"
[ "$fails" = 0 ]
