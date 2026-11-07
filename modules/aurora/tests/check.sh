#!/usr/bin/env bash
# aurora's check: weekly-run and install.sh, then week-digest's fence, scope-pass (one scope's pass) and evolve's probes and its S3 verbs (coverage, conformance, the schemas), under a scratch HOME and config dir (no network, no claude).
#   bash modules/aurora/tests/check.sh
set -u
D="$(cd "$(dirname "$0")" && pwd)"
rc=0
for s in aurora week-digest scope-pass evolve evolve-schemas evolve-pass; do
  echo "== $s"
  bash "$D/$s.sh" || rc=1
done
exit $rc
