#!/usr/bin/env bash
# keel's check: the D-list suite (alone first: it races under load), then side by side the Stop-hook
# lint's, owed's, the lookout's (crosstalk S3) and sheep_gate's confidential scopes. Scratch paths only; no
# network. On a Mac some cases read the overlay's peers (atlas's docs-index, helm's helm_render
# (plan_render before rename S5), plumb's knowledge-numbers) through the core's tool().
#   bash modules/keel/tests/check.sh
set -u
D="$(cd "$(dirname "$0")" && pwd)"
rc=0
# The module's own validate, beside the repo's (its marketplace row lands with the scrub).
if command -v claude >/dev/null 2>&1; then
  claude plugin validate --strict "$D/.." > /dev/null || { echo "plugin.json: claude plugin validate --strict fails"; rc=1; }
fi
echo "== keel"; bash "$D/keel.sh" || rc=1
# the other four share nothing (each its own mktemp dir and state dirs): side by side once keel.sh
# is done, each printed whole in this order once it ends (suite-time, 2026-10-23)
O=$(mktemp -d); pids=()
# cut short (Ctrl-C, check's TERM, CI's timeout): the suites are ended too — background jobs ignore
# SIGINT — and what each printed so far is shown, not deleted unseen with $O (landing review)
halt() { kill ${pids[@]+"${pids[@]}"} 2>/dev/null
  for f in "$O"/*; do [ -s "$f" ] && { echo "== $(basename "$f") (cut short)"; cat "$f"; }; done; exit "$1"; }
trap 'rm -rf "$O"' EXIT; trap 'halt 130' INT; trap 'halt 143' TERM
for s in paste-paths owed test_lookout sheep_gate; do bash "$D/$s.sh" > "$O/$s" 2>&1 & pids+=($!); done
i=0
for s in paste-paths owed test_lookout sheep_gate; do
  wait "${pids[$i]}" || rc=1; i=$((i+1))
  echo "== $s"; cat "$O/$s"; rm -f "$O/$s"
done
# sheep_control and routed (S2) came after that audit: alone, until someone shows they share nothing with the four
for s in sheep_control routed; do echo "== $s"; bash "$D/$s.sh" || rc=1; done
exit $rc
