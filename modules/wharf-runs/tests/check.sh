#!/usr/bin/env bash
# wharf-runs' check: every tool's suite (the core's check compiles this module's Python).
# Scratch paths only; no Orca, no network.
#   bash modules/wharf-runs/tests/check.sh
set -u
D="$(cd "$(dirname "$0")" && pwd)"
rc=0
for s in orca-host; do
  echo "== $s"
  bash "$D/$s.sh" || rc=1
done
exit $rc
