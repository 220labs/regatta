#!/usr/bin/env bash
# helm's check: the no-peer cases and the schema (peers.sh, a scratch checkout of the core and
# helm alone), the two hooks as wired (hooks.sh), then the two suites B12 moved in — test_ask.sh (ask, asklib, surfaces) and
# test_helm.sh (helm, helmlib, helm_render, stalls, stalls_tick), each under the old names and the
# new (rename S5). Every suite runs on its own config dir (tests/config_fixture.sh: a synthetic
# owner, people and hosts) and finds its peers in modules/*/, so none needs an overlay checkout
# (the scrub, 2026-10-22). A core that refuses to load fails.
#   bash modules/helm/tests/check.sh
set -u
D="$(cd "$(dirname "$0")" && pwd)"
M="$(cd "$D/.." && pwd)"
rc=0
python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import find_core; sys.path.insert(0, find_core.hooks()); import common' "$M/lib" \
  || { echo "FAIL: the core does not load here (its line above)"; rc=1; }
echo "== peers"; bash "$D/peers.sh" || rc=1
echo "== hooks"; bash "$D/hooks.sh" || rc=1
for s in test_ask test_helm; do
  echo "== $s"
  bash "$D/$s.sh" || rc=1
done
exit $rc
