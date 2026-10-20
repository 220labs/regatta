#!/usr/bin/env bash
# aurora's check: weekly-run and install.sh under a scratch HOME and config dir (no network, no claude).
#   bash modules/aurora/tests/check.sh
set -u
D="$(cd "$(dirname "$0")" && pwd)"
rc=0
for s in aurora; do
  echo "== $s"
  bash "$D/$s.sh" || rc=1
done
exit $rc
