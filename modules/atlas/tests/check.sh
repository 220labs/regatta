#!/usr/bin/env bash
# atlas's check: the docs map (docs-index), routines kept in git (routine), and the module's own
# cases — the core and peers found from a module path (G19, G20), the bulletin, knowledge-commit's
# refusals and its landing without wharf. Scratch paths only; no network.
#   bash modules/atlas/tests/check.sh
set -u
D="$(cd "$(dirname "$0")" && pwd)"
rc=0
for s in docs-index routine atlas; do
  echo "== $s"
  bash "$D/$s.sh" || rc=1
done
exit $rc
