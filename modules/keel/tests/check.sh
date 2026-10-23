#!/usr/bin/env bash
# keel's check: the D-list suite (alone first: it races under load), then the Stop-hook lint's,
# owed's, the lookout's (crosstalk S3) and sheep_gate's confidential scopes. Scratch paths only; no
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
for s in keel paste-paths owed test_lookout sheep_gate; do
  echo "== $s"
  bash "$D/$s.sh" || rc=1
done
exit $rc
