#!/usr/bin/env bash
# helloworld's check: the publish gate's suite (every scan pattern planted once, publish and
# publish --pr against local bare repos and a fake gh) and name-check's (a local stub answers for
# every registry). Scratch paths only; no network.
#   bash modules/helloworld/tests/check.sh
set -u
D="$(cd "$(dirname "$0")" && pwd)"
rc=0
for s in helloworld name-check; do
  echo "== $s"
  bash "$D/$s.sh" || rc=1
done
exit $rc
