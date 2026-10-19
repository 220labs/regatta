#!/usr/bin/env bash
# plumb's check: crew-report's suite (synthetic transcripts under a scratch HOME; no network).
#   bash modules/plumb/tests/check.sh
set -u
D="$(cd "$(dirname "$0")" && pwd)"
rc=0
for s in crew-report; do
  echo "== $s"
  bash "$D/$s.sh" || rc=1
done
exit $rc
