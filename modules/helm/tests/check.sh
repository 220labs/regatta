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
# test_ask and test_helm share nothing (each its own mktemp dir, config dir and HOME): side by side,
# each printed whole in this order once it ends (suite-time, 2026-10-23)
O=$(mktemp -d); pids=()
# cut short (Ctrl-C, check's TERM, CI's timeout): the suites are ended too — background jobs ignore
# SIGINT — and what each printed so far is shown, not deleted unseen with $O (landing review)
halt() { kill ${pids[@]+"${pids[@]}"} 2>/dev/null
  for f in "$O"/*; do [ -s "$f" ] && { echo "== $(basename "$f") (cut short)"; cat "$f"; }; done; exit "$1"; }
trap 'rm -rf "$O"' EXIT; trap 'halt 130' INT; trap 'halt 143' TERM
for s in test_ask test_helm; do bash "$D/$s.sh" > "$O/$s" 2>&1 & pids+=($!); done
i=0
for s in test_ask test_helm; do
  wait "${pids[$i]}" || rc=1; i=$((i+1))
  echo "== $s"; cat "$O/$s"; rm -f "$O/$s"
done
exit $rc
