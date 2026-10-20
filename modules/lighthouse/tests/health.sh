#!/usr/bin/env bash
# Tests for bin/health against scratch repos, a scratch HOME and config dir: the fast-forward of
# the checkouts `lighthouse/ff` names, the check's failure posted once, and every peer absent —
# wharf's tend and sync.py, wharf-runs' rc-hosts, atlas's bulletin.py and knowledge-commit — a
# logged skip, never a failed pass (the design's G16, G17). Nothing is pushed anywhere real.
#   bash modules/lighthouse/tests/health.sh
set -u
HB="$(cd "$(dirname "$0")/../bin" && pwd)/health"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
unset REGATTA_HOME REGATTA_LEGACY CLAUDE_CONFIG_DIR
export HOME="$T/home" REGATTA_CONFIG="$T/config" HEALTH_LOG_DIR="$T/logs" HEALTH_TCC=off
mkdir -p "$HOME" "$REGATTA_CONFIG/lighthouse" "$T/logs"
export GIT_CONFIG_GLOBAL="$T/gitconfig"
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
# The overlay is REGATTA_LEGACY (its bootstrap.sh is the check), the checkouts lighthouse/ff, the
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
hrun() { HEALTH_TCC="${HRUN_TCC:-off}" HEALTH_TEND="${HRUN_TEND:-off}" REGATTA_LEGACY="$HT/c" HEALTH_BULLETIN_CMD="$HT/bulletin.py" HEALTH_LOG_DIR="$HT/log" HEALTH_COMMIT="$HT/commit" "$HB"; }
printf '#!/bin/sh\necho "$*" >> "%s/commits"\n' "$HT" > "$HT/commit"; chmod +x "$HT/commit"
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
HEALTH_TEND_CMD="$HT/tend" hrun; tail -5 "$HT/log/health.log" | grep -q "^tend: off"; check $? 0 "  HEALTH_TEND=off switches it off"
grep -q "app: main" "$HT/log/health.log"; check $? 1 "  and bin/tend is not run"
HRUN_TEND=on HEALTH_TEND_CMD="$HT/tend" hrun; tail -5 "$HT/log/health.log" | grep -q "^  app: main +1 from origin$"; check $? 0 "  on: it runs after the fast-forward, its lines in the log"
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

echo "no core: one line, exit 2"
cp "$HB" "$T/lonely-health"
out=$(HEALTH_LOG_DIR="$T/logs2" "$T/lonely-health"; echo "rc=$?"); check "$out" "rc=2" "a copy with no lib/ and no core beside it exits 2"
check "$(grep -c 'regatta core would not load' "$T/logs2/health.log")" 1 "  saying so in the log"

echo; [ $fails -eq 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
