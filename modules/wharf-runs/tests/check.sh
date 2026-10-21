#!/usr/bin/env bash
# wharf-runs' check: every tool's suite (the core's check compiles this module's Python).
# Scratch paths only; no Orca, no network, no real launchd. A suite this checkout lacks is skipped
# with a line: the B7 files are private until their scrub, so the public twin holds orca-host's alone.
#   bash modules/wharf-runs/tests/check.sh     (about 15 minutes; test_autofinish and test_dispatch most of it)
set -u
D="$(cd "$(dirname "$0")" && pwd)"
M="$(dirname "$D")"
rc=0
echo "== C1: every bin/ name is free on a stock PATH"
for f in "$M"/bin/*; do
  [ -f "$f" ] || continue
  n=$(basename "$f")
  case "$n" in *.py) continue;; esac
  if PATH=/usr/bin:/bin:/usr/sbin:/sbin command -v "$n" >/dev/null 2>&1; then
    echo "  FAIL bin/$n is shadowed by $(PATH=/usr/bin:/bin:/usr/sbin:/sbin command -v "$n")"; rc=1
  fi
done
echo "== lib/core_path.py is wharf's, byte for byte (one finder, two copies: a process loads both modules)"
if [ -f "$M/lib/core_path.py" ] && [ -f "$M/../wharf/lib/core_path.py" ]; then
  cmp -s "$M/lib/core_path.py" "$M/../wharf/lib/core_path.py" && echo "  ok   identical" || { echo "  FAIL lib/core_path.py differs from wharf's"; rc=1; }
else
  echo "  --   skipped: no lib/core_path.py here, or no wharf beside it"
fi
# Off macOS (CI's ubuntu) only the suites proven there run: orca-host's, orca-serve-agent's (a dry run), and test_autofinish (made
# portable and run on ubuntu in the overlay's CI since 2026-10-07). The rest read launchd, plutil,
# caffeinate or BSD date; a suite joins the Linux list once it passes there, never by skipping
# what it checks.
LINUX_OK=" orca-host orca-serve-agent test_autofinish "
for s in orca-host orca-serve-agent peers test_check test_harness test_hail test_rc_hosts test_autofinish_run test_pickup test_autofinish test_dispatch test_wharf; do
  echo "== $s"
  if [ ! -f "$D/$s.sh" ]; then echo "  --   skipped: not in this checkout"; continue; fi
  if [ "$(uname)" != Darwin ] && [ "${LINUX_OK#* $s }" = "$LINUX_OK" ]; then echo "  --   skipped: macOS only (runs in /finish)"; continue; fi
  bash "$D/$s.sh" || rc=1
done
exit $rc
