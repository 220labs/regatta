#!/usr/bin/env bash
# Tests for bin/health against scratch repos, a scratch HOME and config dir: the fast-forward of
# the checkouts `lighthouse/ff` names, the check's failure posted once, and every peer absent —
# wharf's tend and sync.py, wharf-runs' rc-hosts, atlas's bulletin.py and knowledge-commit — a
# logged skip, never a failed pass (the design's G16, G17). Nothing is pushed anywhere real.
#   bash modules/lighthouse/tests/health.sh
set -u
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
# health runs from a scratch checkout holding only the core and this module: the core's
# regatta_root() is the checkout above the running file, so in the real one wharf's tend and
# sync.py (B5, B6) sit beside it and no peer would read as absent.
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
mkdir -p "$T/rg/.claude-plugin" "$T/rg/modules"
cp "$ROOT/.claude-plugin/marketplace.json" "$T/rg/.claude-plugin/"
cp -R "$ROOT/modules/regatta" "$ROOT/modules/lighthouse" "$T/rg/modules/"
HB="$T/rg/modules/lighthouse/bin/health"
unset REGATTA_HOME REGATTA_LEGACY CLAUDE_CONFIG_DIR
export HOME="$T/home" REGATTA_CONFIG="$T/config" HEALTH_LOG_DIR="$T/logs" HEALTH_TCC=off HEALTH_RCB=off HEALTH_DISK=off
mkdir -p "$HOME" "$REGATTA_CONFIG/lighthouse" "$T/logs"
export GIT_CONFIG_GLOBAL="$T/gitconfig"
export HEALTH_CANARY=off   # the real clock would read this Mac's Orca: the cases below name a stand-in
git config --global user.name t; git config --global user.email t@example.invalid; git config --global init.defaultBranch main
fails=0
check() { if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3: expected [$2] got [$1]"; fails=$((fails+1)); fi; }
log() { cat "$T/logs/health.log"; }
run() { : > "$T/logs/health.log" 2>/dev/null; "$HB" "$@"; echo "rc=$?" >> "$T/logs/health.log"; }

# a checkout one commit behind its origin
git init -q --bare "$T/origin.git"
git clone -q "$T/origin.git" "$T/kr" 2>/dev/null
git -C "$T/kr" commit -q --allow-empty -m one && git -C "$T/kr" push -q origin main
git clone -q "$T/origin.git" "$T/up"
git -C "$T/up" commit -q --allow-empty -m two && git -C "$T/up" push -q origin main
echo "$T/kr" > "$REGATTA_CONFIG/lighthouse/ff"

echo "no peer installed: each step skips in one line, the check still runs"
HEALTH_CHECK_CMD=true run
check "$(log | grep -c 'ff kr: [0-9a-f]* → [0-9a-f]*')" 1 "the checkout lighthouse/ff names is fast-forwarded"
check "$(git -C "$T/kr" log -1 --format=%s)" two "  to origin's main"
CORE_ROOT=$(python3 -c "import sys; sys.path.insert(0, '$(dirname "$HB")/../lib'); import find_core; sys.path.insert(0, find_core.hooks()); import common; print(common.regatta_root() or '')")
check "$(log | grep -c "^ff $(basename "$CORE_ROOT"):")" 1 "  the core's own checkout too, beside the key's (B9 review)"
check "$(log | grep -c "tend: wharf's bin/tend not installed — skipped")" 1 "tend absent: skipped (G16)"
check "$(log | tail -2 | tr '\n' ' ')" "ok rc=0 " "a passing check: ok, exit 0"
HEALTH_TCC=on HEALTH_CHECK_CMD=true run
check "$(log | grep -c "privacy: wharf-runs' rc-hosts not installed — skipped")" 1 "rc-hosts absent: the survey skipped"
HEALTH_RCB=on HEALTH_CHECK_CMD=true run
check "$(log | grep -c "rc hosts: wharf-runs' rc-hosts not installed — skipped")" 1 "rc-hosts absent: the hosts' line skipped"

echo "a failing check, with no bulletin to post to (G17)"
HEALTH_CHECK_CMD=false run
check "$(log | grep -c "failing — not posted: atlas's bulletin.py not installed")" 1 "bulletin.py absent: said, not raised"
check "$(log | tail -1)" "rc=1" "  the check's exit code is the pass's"

echo "a failing check, posted once and committed in the bulletin-repo"
printf 'import sys\nprint("- posted: " + " ".join(sys.argv[1:]))\n' > "$T/bulletin.py"   # run as python3 <it>, as bulletin.py is
printf '#!/bin/sh\necho "$*" >> "%s/commits"\n' "$T" > "$T/kc"; chmod +x "$T/kc"
HEALTH_BULLETIN_CMD="$T/bulletin.py" HEALTH_COMMIT="$T/kc" HEALTH_CHECK_CMD=false run
check "$(log | grep -c 'bulletin line not committed: no lighthouse/vault key')" 1 "no vault key: posted, not committed"
rm -f "$T/logs/health.last"
echo vault > "$REGATTA_CONFIG/lighthouse/vault"
HEALTH_BULLETIN_CMD="$T/bulletin.py" HEALTH_COMMIT="$T/kc" HEALTH_CHECK_CMD=false run
check "$(sed 's/ on [^ ]* (bin/ on <host> (bin/' "$T/commits" 2>/dev/null)" "vault -m Bulletin: false fails on <host> (bin/health) bulletin.md" \
  "committed through knowledge-commit in the named repo"
HEALTH_BULLETIN_CMD="$T/bulletin.py" HEALTH_COMMIT="$T/kc" HEALTH_CHECK_CMD=false run
check "$(log | grep -c 'false: failing, already posted')" 1 "the same failure again: not posted twice"
check "$(grep -c . "$T/commits")" 1 "  and not committed twice"

# BSD date has -v, GNU date -d; each form fails cleanly on the other, so try BSD first.
dateoff() { date -v"$1" "$2" 2>/dev/null || date -d "${1%d} day" "$2"; }   # dateoff +1d +%F
echo "the overlay's case (ported from its test_hooks.sh at B9): two checkouts, its check, a bulletin"
# bin/health on scratch repos: a clean main fast-forwards, a dirty one is left; a failing check
# posts one bulletin line and commits it, the same failure again posts nothing, green clears it.
# The overlay is a config dir's regatta/overlay marker (its bootstrap.sh is the check; the core then
# wants its five keys, neutral here), the checkouts lighthouse/ff, the
# bulletin a stub that writes CLAUDE_BULLETIN as bulletin.py would.
HT="$T/health"; mkdir -p "$HT"
git init -q --bare "$HT/origin.git"
git clone -q "$HT/origin.git" "$HT/c" 2>/dev/null; git -C "$HT/c" checkout -q -b main
printf '#!/bin/sh\n[ -f "$(dirname "$0")/fail" ] && { echo "⚠ pre-push · differs" >&2; exit 1; }; echo ok\n' > "$HT/c/bootstrap.sh"
chmod +x "$HT/c/bootstrap.sh"; printf 'fail\n' > "$HT/c/.gitignore"
git -C "$HT/c" add -A && git -C "$HT/c" commit -qm one && git -C "$HT/c" push -q origin main 2>/dev/null
git clone -q "$HT/origin.git" "$HT/up" 2>/dev/null; echo x > "$HT/up/x"; git -C "$HT/up" add x && git -C "$HT/up" commit -qm two && git -C "$HT/up" push -q origin main 2>/dev/null
cp -R "$HT/c" "$HT/p"; echo dirty > "$HT/p/dirt"
printf '%s\n%s\n' "$HT/c" "$HT/p" > "$REGATTA_CONFIG/lighthouse/ff"; echo vault > "$REGATTA_CONFIG/lighthouse/vault"
export CLAUDE_BULLETIN="$HT/bulletin.md"
printf 'import os, sys\nline = "- " + " · ".join(sys.argv[2:])\nopen(os.environ["CLAUDE_BULLETIN"], "a").write(line + "\\n")\nprint(line)\n' > "$HT/bulletin.py"
HTC="$T/hconfig"; cp -R "$REGATTA_CONFIG" "$HTC"; mkdir -p "$HTC/regatta"; echo "$HT/c" > "$HTC/regatta/overlay"
echo Owner > "$HTC/regatta/owner"; : > "$HTC/regatta/guarded"; : > "$HTC/regatta/orca-deny"; echo "$T/usage" > "$HTC/regatta/log-dir"; echo "$HOME/projects" > "$HTC/regatta/projects"
hrun() { HEALTH_CANARY="${HRUN_CANARY:-off}" HEALTH_RCB="${HRUN_RCB:-off}" HEALTH_TCC="${HRUN_TCC:-off}" HEALTH_TEND="${HRUN_TEND:-off}" REGATTA_CONFIG="$HTC" HEALTH_BULLETIN_CMD="$HT/bulletin.py" HEALTH_LOG_DIR="$HT/log" HEALTH_COMMIT="$HT/commit" "$HB"; }
printf '#!/bin/sh\necho "$*" >> "%s/commits"\n' "$HT" > "$HT/commit"; chmod +x "$HT/commit"
lastrun() { awk '/^== /{b=""} {b=b $0 "\n"} END{printf "%s", b}' "$HT/log/health.log"; }   # the last pass's lines, however many steps it logs
nb=$(grep -c '^- ' "$CLAUDE_BULLETIN" 2>/dev/null || echo 0)
hrun; check $? 0 "a green check exits 0"
check "$(git -C "$HT/c" log -1 --format=%s)" two "  a clean main is fast-forwarded to origin"
check "$(git -C "$HT/p" log -1 --format=%s)" one "  a dirty one is left where it was"
check "$(grep -c '^- ' "$CLAUDE_BULLETIN" 2>/dev/null || echo 0)" "$nb" "  and nothing is posted"
touch "$HT/c/fail"; hrun; check $? 1 "a failing check exits 1"
check "$(grep -c 'bin/health' "$CLAUDE_BULLETIN")" 1 "  posts one bulletin line"
grep -q 'pre-push - differs' "$CLAUDE_BULLETIN"; check $? 0 "  naming the failure, its · made safe"
check "$(wc -l < "$HT/commits" | tr -d ' ')" 1 "  and commits the bulletin once"
hrun; check "$(grep -c 'bin/health' "$CLAUDE_BULLETIN")" 1 "the same failure again posts nothing"
rm "$HT/c/fail"; hrun; [ -f "$HT/log/health.last" ]; check $? 1 "green again clears what was posted"
touch "$HT/c/fail"; hrun; check "$(grep -c 'bin/health' "$CLAUDE_BULLETIN")" 2 "  so the next failure posts again"
touch -t "$(dateoff -8d +%Y%m%d%H%M)" "$HT/log/health.last"; hrun
check "$(grep -c 'bin/health' "$CLAUDE_BULLETIN")" 3 "a failure older than the bulletin's week is posted again"
printf '#!/bin/sh\n[ -n "$BOOTSTRAP_UNATTENDED" ] && echo ok || exit 1\n' > "$HT/c/bootstrap.sh"
rm "$HT/c/fail"; hrun; check $? 0 "  the check runs unattended (it skips what launchd cannot read)"
printf '#!/bin/sh\necho "app: main +1 from origin"\n' > "$HT/tend"; chmod +x "$HT/tend"
# hrun passes HEALTH_TEND=off whatever the shell exports (HRUN_TEND=on to test it): the suite never runs the real bin/tend, which would tend the real repos.
grep -qF 'TEND="${HEALTH_TEND:-on}"' "$HB"; check $? 0 "the tend is on by default (E2, R5 clean on the always-on Mac, 2026-10-05)"
HEALTH_TEND_CMD="$HT/tend" hrun; lastrun | grep -q "^tend: off"; check $? 0 "  HEALTH_TEND=off switches it off"
grep -q "app: main" "$HT/log/health.log"; check $? 1 "  and bin/tend is not run"
HRUN_TEND=on HEALTH_TEND_CMD="$HT/tend" hrun; lastrun | grep -q "^  app: main +1 from origin$"; check $? 0 "  on: it runs after the fast-forward, its lines in the log"
printf '#!/bin/sh\necho "FAILED app: exit 1: boom"\necho "FAILED tend: app"\nexit 1\n' > "$HT/tend-bad"; chmod +x "$HT/tend-bad"
nb=$(grep -c 'bin/tend fails' "$CLAUDE_BULLETIN" 2>/dev/null); nb=${nb:-0}; : > "$HT/commits"  # grep -c prints 0 and exits 1: never `|| echo 0`
HRUN_TEND=on HEALTH_TEND_CMD="$HT/tend-bad" hrun
check "$(grep -c 'bin/tend fails' "$CLAUDE_BULLETIN")" "$((nb + 1))" "  a tend that fails is posted, not only logged"
grep -q 'bin/tend fails.*not tended: app' "$CLAUDE_BULLETIN"; check $? 0 "  naming the repo"
check "$(wc -l < "$HT/commits" | tr -d ' ')" 1 "  and the bulletin committed"
HRUN_TEND=on HEALTH_TEND_CMD="$HT/tend-bad" hrun
check "$(grep -c 'bin/tend fails' "$CLAUDE_BULLETIN")" "$((nb + 1))" "  the same failure the next day posts nothing"
HRUN_TEND=on HEALTH_TEND_CMD="$HT/tend" hrun; [ -f "$HT/log/health.last.tend" ]; check $? 1 "  a clean tend clears it"
# the privacy survey (docs/tcc-one-identity-2026-10-18.md): hrun keeps it off, as the tend, unless
# HRUN_TCC=on with HEALTH_TCC_CMD standing in for `rc-hosts --tcc-survey --health` (the real one reads this Mac's log)
grep -qF 'TCC="${HEALTH_TCC:-on}"' "$HB"; check $? 0 "the privacy survey is on by default"
printf '#!/bin/sh\necho "  REFUSED  privacy: refused to a versioned claude in 24 h (here):"\necho "              13 FileProviderDomain denied/user-consent REAL  <home>/.local/share/claude/versions/<v>  last x  2.1.302"\necho "               2 SystemPolicyAllFiles denied/no-record REAL  <home>/.bun/bin/bun  last x  2.1.302"\nexit 1\n' > "$HT/tcc-bad"; chmod +x "$HT/tcc-bad"
printf '#!/bin/sh\necho "  ok       privacy: nothing refused"\n' > "$HT/tcc-ok"; chmod +x "$HT/tcc-ok"
nb=$(grep -c 'a claude without claude-host fails' "$CLAUDE_BULLETIN" 2>/dev/null); nb=${nb:-0}; : > "$HT/commits"
HRUN_TCC=on HEALTH_TCC_CMD="$HT/tcc-bad" hrun
check "$(grep -c 'a claude without claude-host fails' "$CLAUDE_BULLETIN")" "$((nb + 1))" "a privacy refusal to a versioned claude is posted"
grep -q 'refused to a versioned claude: FileProviderDomain, SystemPolicyAllFiles' "$CLAUDE_BULLETIN"; check $? 0 "  naming the services, without counts"
HRUN_TCC=on HEALTH_TCC_CMD="$HT/tcc-bad" hrun
check "$(grep -c 'a claude without claude-host fails' "$CLAUDE_BULLETIN")" "$((nb + 1))" "  the same services the next day post nothing"
HRUN_TCC=on HEALTH_TCC_CMD="$HT/tcc-ok" hrun; [ -f "$HT/log/health.last.tcc" ]; check $? 1 "  a clean survey clears it"
printf '#!/bin/sh\necho "  REFUSED  privacy: refused to a versioned claude or a job Orca started in 24 h (here):"\necho "               9 FileProviderDomain denied/no-record REAL  via Orca: <home>/.local/share/claude/versions/<v>  last x  Orca"\nexit 1\n' > "$HT/tcc-orca"; chmod +x "$HT/tcc-orca"
HRUN_TCC=on HEALTH_TCC_CMD="$HT/tcc-ok" hrun
nb=$(grep -c 'a claude without claude-host fails' "$CLAUDE_BULLETIN" 2>/dev/null); nb=${nb:-0}
HRUN_TCC=on HEALTH_TCC_CMD="$HT/tcc-orca" hrun
check "$(grep -c 'a claude without claude-host fails' "$CLAUDE_BULLETIN")" "$((nb + 1))" "a refusal charged to Orca for a job it started is posted"
grep -q 'refused to a versioned claude: FileProviderDomain (some charged to Orca: a job it started without claude-host)' "$CLAUDE_BULLETIN"; check $? 0 "  saying it was Orca's, so the fix is the Orca road (S3), not claude-host"
HRUN_TCC=on HEALTH_TCC_CMD="$HT/tcc-ok" hrun
# the Remote Control hosts (2026-10-23): HEALTH_RCB_CMD stands in for `rc-hosts --broken` (the real one reads this Mac's hosts)
grep -qF 'RCB="${HEALTH_RCB:-on}"' "$HB"; check $? 0 "the Remote Control hosts' line is on by default"
printf '#!/bin/sh\necho "  FAIL     film · buildbox: broken: its claude 2.1.304 was removed; new sessions fail — the hourly --reap restarts it once no session is busy; now: rc-hosts --reap --only film"\nexit 3\n' > "$HT/rcb-bad"; chmod +x "$HT/rcb-bad"
printf '#!/bin/sh\necho "  FAIL     film · buildbox: broken: its claude (version unknown) was removed; new sessions fail"\nexit 3\n' > "$HT/rcb-unknown"; chmod +x "$HT/rcb-unknown"
printf '#!/bin/sh\necho "Traceback (most recent call last):" >&2\nexit 1\n' > "$HT/rcb-crash"; chmod +x "$HT/rcb-crash"
printf '#!/bin/sh\necho "  ok       every host'"'"'s claude is still installed"\n' > "$HT/rcb-ok"; chmod +x "$HT/rcb-ok"
nb=$(grep -c 'a Remote Control host fails' "$CLAUDE_BULLETIN" 2>/dev/null); nb=${nb:-0}; : > "$HT/commits"
HRUN_RCB=on HEALTH_RCB_CMD="$HT/rcb-bad" hrun
check "$(grep -c 'a Remote Control host fails' "$CLAUDE_BULLETIN")" "$((nb + 1))" "a host whose claude was deleted under it is posted"
grep -q 'new sessions fail: film - buildbox (2.1.304)' "$CLAUDE_BULLETIN"; check $? 0 "  naming the host and its version, its · made safe"
HRUN_RCB=on HEALTH_RCB_CMD="$HT/rcb-bad" hrun
check "$(grep -c 'a Remote Control host fails' "$CLAUDE_BULLETIN")" "$((nb + 1))" "  the same host the next day posts nothing"
HRUN_RCB=on HEALTH_RCB_CMD="$HT/rcb-ok" hrun; [ -f "$HT/log/health.last.rc" ]; check $? 1 "  every host healthy clears it"
HRUN_RCB=on HEALTH_RCB_CMD="$HT/rcb-unknown" hrun
grep -q 'new sessions fail: film - buildbox (version unknown) ' "$CLAUDE_BULLETIN"; check $? 0 "  an unknown version reads (version unknown), parentheses balanced"
HRUN_RCB=on HEALTH_RCB_CMD="$HT/rcb-ok" hrun
nd=$(grep -c 'deleted under it' "$CLAUDE_BULLETIN")
HRUN_RCB=on HEALTH_RCB_CMD="$HT/rcb-crash" hrun
grep -q 'rc-hosts --broken could not tell (exit 1)' "$CLAUDE_BULLETIN"; check $? 0 "a crash (exit 1) is posted as could not tell"
check "$(grep -c 'deleted under it' "$CLAUDE_BULLETIN")" "$nd" "  never as a deleted claude"

echo "the start-path canary's line (orca-launcher S7, 2026-10-26)"
# HEALTH_CANARY_CMD stands in for `clock canary check --json` (the real one reads this Mac's Orca and its beat files)
grep -qF 'CANARY="${HEALTH_CANARY:-on}"' "$HB"; check $? 0 "the canary's line is on by default"
printf '%s' '{"fails": 2, "host": "h", "findings": [{"level": "FAIL", "text": "canary orca: no beat in its window \u2014 the last was 2026-10-26 01:00, 130 min ago (window 90 min)"}, {"level": "FAIL", "text": "canary orca@acct-a: its beat file cannot be read (boom)"}, {"level": "ok", "text": "canary other: last beat 2026-10-26 02:00, 10 min ago (window 90 min)"}, {"level": "NOTE", "text": "canary: no more"}]}' > "$HT/canary-bad.json"
printf '#!/bin/sh\ncat "%s"\nexit 1\n' "$HT/canary-bad.json" > "$HT/canary-bad"; chmod +x "$HT/canary-bad"
printf '#!/bin/sh\necho %s\nexit 0\n' "'"'{"fails": 0, "host": "h", "findings": [{"level": "ok", "text": "canary orca: last beat now"}]}'"'" > "$HT/canary-ok"; chmod +x "$HT/canary-ok"
printf '#!/bin/sh\necho "clock: boom" >&2\nexit 2\n' > "$HT/canary-crash"; chmod +x "$HT/canary-crash"
printf '#!/bin/sh\necho "not json"\nexit 1\n' > "$HT/canary-garbled"; chmod +x "$HT/canary-garbled"
nb=$(grep -c "canary fails on" "$CLAUDE_BULLETIN" 2>/dev/null); nb=${nb:-0}; : > "$HT/commits"
HRUN_CANARY=on HEALTH_CANARY_CMD="$HT/canary-bad" hrun
check "$(grep -c "canary fails on" "$CLAUDE_BULLETIN")" "$((nb + 1))" "a canary beat outside its window is posted"
grep -q 'first turn: orca, orca@acct-a ' "$CLAUDE_BULLETIN"; check $? 0 "  naming the beats"
grep -q '130 min' "$CLAUDE_BULLETIN"; check $? 1 "  without the minutes, which move daily"
lastrun | grep -q '^  FAIL canary orca: no beat in its window'; check $? 0 "  and the check's own lines are in the log"
check "$(wc -l < "$HT/commits" | tr -d ' ')" 1 "  the bulletin committed once"
HRUN_CANARY=on HEALTH_CANARY_CMD="$HT/canary-bad" hrun
check "$(grep -c "canary fails on" "$CLAUDE_BULLETIN")" "$((nb + 1))" "  the same beats the next day post nothing"
HRUN_CANARY=on HEALTH_CANARY_CMD="$HT/canary-ok" hrun; [ -f "$HT/log/health.last.canary" ]; check $? 1 "  every beat inside its window clears it"
HRUN_CANARY=on HEALTH_CANARY_CMD="$HT/canary-crash" hrun
grep -q 'clock canary check could not tell (exit 2)' "$CLAUDE_BULLETIN"; check $? 0 "a crash (exit 2) is posted as could not tell"
lastrun | grep -q '^  clock: boom'; check $? 0 "  its stderr in the log"
HRUN_CANARY=on HEALTH_CANARY_CMD="$HT/canary-garbled" hrun
grep -q 'clock canary check could not tell (exit 1)' "$CLAUDE_BULLETIN"; check $? 0 "a failing exit with no readable finding is could not tell, never a silent pass"
printf '#!/bin/sh\necho "a banner"\nexit 0\n' > "$HT/canary-garbled0"; chmod +x "$HT/canary-garbled0"
HRUN_CANARY=on HEALTH_CANARY_CMD="$HT/canary-garbled0" hrun
grep -q 'clock canary check could not tell (exit 0)' "$CLAUDE_BULLETIN"; check $? 0 "  so is exit 0 with no findings: it clears nothing"
[ -f "$HT/log/health.last.canary" ]; check $? 0 "  the posted state kept"
touch "$HOME/.studio-brake"
HRUN_CANARY=on HEALTH_CANARY_CMD="$HT/canary-bad" hrun; lastrun | grep -q '^canary: not read — the studio brake holds'; check $? 0 "the studio brake: the canary is not read (no beat fires under it)"
rm -f "$HOME/.studio-brake"
HRUN_CANARY=on hrun; lastrun | grep -q "^canary: wharf-runs' clock not installed"; check $? 0 "a Mac without wharf-runs' clock: one line, skipped"
hrun; lastrun | grep -q '^canary: off'; check $? 0 "HEALTH_CANARY=off switches it off"

echo "the serve agent's line (skipper-resilience, the watch, 2026-10-22)"
HEALTH_CHECK_CMD=true run
check "$(log | grep -c '^orca: no serve agent here (org.regatta.orca-serve) — skipped$')" 1 "no serve agent's plist here: one line, skipped"
LA="$T/home"; LA="$LA/Library/LaunchAgents"   # the moved HOME's: the real one is never read
mkdir -p "$LA" "$REGATTA_CONFIG/wharf-runs"
echo serve.example > "$REGATTA_CONFIG/wharf-runs/serve-label"
touch "$LA/serve.example.plist"
# launchctl print's shape: a running service has a `pid = N` line, a stopped one none
cat > "$T/lctl-up" <<STUB
#!/bin/sh
echo "\$*" >> "$T/lctl.args"
printf 'gui/501/serve.example = {\n\tactive count = 1\n\tstate = running\n\tpid = 4242\n}\n'
STUB
cat > "$T/lctl-down" <<STUB
#!/bin/sh
printf 'gui/501/serve.example = {\n\tstate = not running\n\tlast exit code = 1\n}\n'
STUB
cat > "$T/orca-ok" <<STUB
#!/bin/sh
echo "\$*" >> "$T/orca.args"
echo '{"ok": true, "result": {"runs": []}}'
STUB
cat > "$T/orca-bad" <<STUB
#!/bin/sh
echo "\$*" >> "$T/orca.args"
echo '{"ok": false, "error": {"message": "no runtime"}}'; exit 1
STUB
chmod +x "$T/lctl-up" "$T/lctl-down" "$T/orca-ok" "$T/orca-bad"
: > "$T/commits"; : > "$T/orca.args"
orun() { HEALTH_LAUNCHCTL_CMD="$T/$1" HEALTH_ORCA_CMD="$T/$2" HEALTH_BULLETIN_CMD="$T/bulletin.py" HEALTH_COMMIT="$T/kc" HEALTH_CHECK_CMD=true run; }
orun lctl-up orca-ok
check "$(log | grep -c '^orca: serve.example pid 4242, run-list answers$')" 1 "a live pid and a run-list that answers: one line"
check "$(cat "$T/lctl.args")" "print gui/$(id -u)/serve.example" "  launchd asked for the label wharf-runs/serve-label names"
check "$(cat "$T/orca.args")" "orchestration run-list --limit 1 --json" "  and Orca only for a list"
check "$(grep -c . "$T/commits")" 0 "  nothing posted"
: > "$T/orca.args"
orun lctl-down orca-ok
check "$(log | grep -c '^orca: the serve agent serve.example has no process')" 1 "no pid: said in the log"
check "$(log | grep -c "^- posted: --post Orca's serve agent fails on")" 1 "  and posted"
check "$(grep -c . "$T/commits")" 1 "  and committed"
check "$(grep -c . "$T/orca.args")" 0 "  Orca is not asked while the agent has no process"
orun lctl-down orca-ok
check "$(log | grep -c "Orca's serve agent: failing, already posted")" 1 "the same the next day: posted once"
check "$(grep -c . "$T/commits")" 1 "  not committed twice"
orun lctl-up orca-bad
check "$(log | grep -c '^orca: the serve agent serve.example runs but orca run-list does not answer (pid 4242)$')" 1 "a pid with no answer from run-list is a failure too"
check "$(grep -c . "$T/commits")" 2 "  posted as a new one"
orun lctl-up orca-ok
[ -f "$T/logs/health.last.orca" ]; check $? 1 "serving again clears what was posted"
check "$(log | tail -2 | tr '\n' ' ')" "ok rc=0 " "the agent's line never changes the pass's exit"
HEALTH_ORCA=off HEALTH_CHECK_CMD=true run
check "$(log | grep -c '^orca: off')" 1 "HEALTH_ORCA=off switches it off"
grep -qF 'ORCA="${HEALTH_ORCA:-on}"' "$HB"; check $? 0 "  it is on by default"
rm -f "$REGATTA_CONFIG/wharf-runs/serve-label" "$LA/serve.example.plist"

echo "free disk (2026-10-25): df stubbed at 200, 80 and 30 GB free; du at a tree holding Chrome's clones"
# df -Pk's two lines with DF_FREE GB available; du's "<KiB>\t<path>" lines for a volume /V shaped as
# the always-on Mac's was: the sample library, the Drive cache and Movies, beside 1.4 TB of clones that free nothing.
printf '#!/bin/sh\necho "Filesystem 1024-blocks Used Available Capacity Mounted on"\necho "/dev/disk9 2000000000 1 $((DF_FREE * 1048576)) 99%% /V"\n' > "$T/df"
printf '#!/bin/sh\necho "Filesystem Size Used Avail"\necho "/dev/disk9 2T 2T -"\n' > "$T/df-odd"
cat > "$T/du" <<'SH'
#!/bin/sh
G=1048576
for e in "576 /V/Library/Application Support/Superior Drummer" "580 /V/Library/Application Support" "600 /V/Library" \
         "417 /V/people/u/Movies" "500 /V/people/u/Library/SyncCache" "520 /V/people/u/Library" "950 /V/people/u" "960 /V/people" \
         "1400 /V/private/var/folders/ab/cd/X" "1401 /V/private/var/folders/ab/cd" "1401 /V/private/var/folders/ab" \
         "1402 /V/private/var/folders" "1405 /V/private/var" "1406 /V/private" "2966 /V"; do
  printf '%s\t%s\n' "$(( ${e%% *} * G ))" "${e#* }"
done
[ -z "${DU_DENY:-}" ] || { echo "du: /V/people/u/Library/Sealed: Operation not permitted" >&2; exit 1; }
SH
chmod +x "$T/df" "$T/df-odd" "$T/du"
drun() { DF_FREE=$1 HEALTH_DISK=on HEALTH_DISK_VOL=/V HEALTH_DF_CMD="${DRUN_DF:-$T/df}" HEALTH_DU_CMD="$T/du" HEALTH_ORCA=off \
  HEALTH_BULLETIN_CMD="$T/bulletin.py" HEALTH_COMMIT="$T/kc" HEALTH_CHECK_CMD=true run; }
grep -qF 'DISK="${HEALTH_DISK:-on}"' "$HB"; check $? 0 "the free-disk line is on by default"
rm -f "$T/logs/health.last.disk"; : > "$T/commits"
drun 200
check "$(log | grep '^disk:')" "disk: 200 GB free on /V" "200 GB free: ok"
drun 80
check "$(log | grep '^disk:')" "disk: warn 80 GB free on /V (warn under 100 GB)" "80 GB free: a warn"
check "$(log | grep -c '^- posted:')" 0 "  logged, not posted"
drun 30
check "$(log | grep '^disk:')" "disk: FAIL 30 GB free on /V (fail under 50 GB, warn under 100)" "30 GB free: a fail"
check "$(log | grep '^  [0-9]* GB  ' | tr '\n' '|')" "  576 GB  /V/Library/Application Support/Superior Drummer|  500 GB  /V/people/u/Library/SyncCache|  417 GB  /V/people/u/Movies|" \
  "  the three biggest folders, drilled past /people and /Library"
check "$(log | grep -c '/V/private')" 0 "  the clones left out, and taken out of their parents' totals"
check "$(log | grep -c '^- posted: --post free disk fails on .* under 50 GB free on /V; biggest folders: /V/Library/Application Support/Superior Drummer; /V/people/u/Library/SyncCache; /V/people/u/Movies')" 1 \
  "  posted to the bulletin, naming them"
check "$(grep -c . "$T/commits")" 1 "  and committed"
check "$(log | tail -2 | tr '\n' ' ')" "ok rc=0 " "  the disk never changes the pass's exit"
drun 29
check "$(log | grep -c 'free disk: failing, already posted')" 1 "a day later at 29 GB: the same post, not repeated"
drun 80
check "$(log | grep -c '^- posted:')" 0 "back over 50 GB, a warn keeps what was posted"
drun 30
check "$(log | grep -c 'free disk: failing, already posted')" 1 "  so a disk hovering at 50 GB posts once"
drun 200
[ -f "$T/logs/health.last.disk" ]; check $? 1 "room again clears what was posted"
DU_DENY=1 drun 30
check "$(log | grep -c '^  du could not read 1 folders (first: /V/people/u/Library/Sealed)')" 1 "du denied a folder (launchd, no Full Disk Access): said in one line"
check "$(log | grep -c '^- posted: .*(du could not read some folders)')" 1 "  and in the post"
rm -f "$T/logs/health.last.disk"
grep -qF '["du", "-x", "-k", "-d", "6"]' "$HB"; check $? 0 "the real du: -x (one volume), -k (KiB), -d 6 (reaches the clones' X folders)"
HEALTH_DU_CMD=/nonexistent/du DF_FREE=30 HEALTH_DISK=on HEALTH_DISK_VOL=/V HEALTH_DF_CMD="$T/df" HEALTH_ORCA=off \
  HEALTH_BULLETIN_CMD="$T/bulletin.py" HEALTH_COMMIT="$T/kc" HEALTH_CHECK_CMD=true run
check "$(log | grep -c '^  du could not run:')" 1 "a du that cannot run: one line, no traceback"
check "$(log | grep -c Traceback)" 0 "  none"
rm -f "$T/logs/health.last.disk"
DRUN_DF="$T/df-odd" drun 0
check "$(log | grep '^disk:')" "disk: df -Pk /V could not tell — skipped" "a df line it cannot read: skipped in one line"
HEALTH_CHECK_CMD=true run
check "$(log | grep '^disk:')" "disk: off (DISK in bin/health)" "HEALTH_DISK=off switches it off"

echo "hookwatch's pin (autofinish-exclude landing review, finding 14): printed and posted, whichever check runs"
printf '{"pinned": {"root": "/x/regatta", "to": "0123456789abcdef", "from": "f", "why": "crash: h.py (x)", "pr": "https://github.invalid/p/1"}}\n' > "$REGATTA_CONFIG/lighthouse/hookwatch.json"
rm -f "$T/logs/health.last.pin"
HEALTH_BULLETIN_CMD="$T/bulletin.py" HEALTH_COMMIT="$T/kc" HEALTH_CHECK_CMD=true run
check "$(log | grep -c '^hookwatch: regatta pinned at 0123456789ab by hookwatch (crash: h.py (x)); revert PR https://github.invalid/p/1')" 1 "a pin in hookwatch's state: health names it"
check "$(log | grep -c "^- posted: --post hookwatch.s pin fails")" 1 "  and posts it to the bulletin"
HEALTH_BULLETIN_CMD="$T/bulletin.py" HEALTH_COMMIT="$T/kc" HEALTH_CHECK_CMD=true run
check "$(log | grep -c "hookwatch's pin: failing, already posted")" 1 "  once: the next pass posts nothing"
rm -f "$REGATTA_CONFIG/lighthouse/hookwatch.json"
HEALTH_CHECK_CMD=true run
check "$(log | grep -c '^hookwatch:'):$([ -e "$T/logs/health.last.pin" ] && echo kept || echo gone)" "0:gone" "  no pin: no line, and the posted mark goes"

echo "no core: one line, exit 2"
cp "$HB" "$T/lonely-health"
out=$(HEALTH_LOG_DIR="$T/logs2" "$T/lonely-health"; echo "rc=$?"); check "$out" "rc=2" "a copy with no lib/ and no core beside it exits 2"
check "$(grep -c 'regatta core would not load' "$T/logs2/health.log")" 1 "  saying so in the log"

echo; [ $fails -eq 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
