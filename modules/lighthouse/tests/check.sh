#!/usr/bin/env bash
# lighthouse's check: every suite beside this file, each in scratch dirs it makes itself (HOME
# moved, REGATTA_CONFIG pinned), no network. A suite that needs a Mac (zsh, launchd, BSD tools)
# skips itself elsewhere with one printed line, so CI on ubuntu runs the rest.
#   bash modules/lighthouse/tests/check.sh
set -u
D="$(cd "$(dirname "$0")" && pwd)"
rc=0
for s in "$D"/*.sh; do
  # dev.sh is beacon's opt-in smoke under wrangler dev: it downloads wrangler, so never here
  case "$(basename "$s")" in check.sh|dev.sh) continue;; esac
  echo "== $(basename "$s" .sh)"
  bash "$s" || rc=1
done
# beacon's Worker against stubs: node --test, with node:sqlite (Node 22.13 or later) standing in
# for the Durable Object's storage. beacon is private until its scrub, so the public twin has
# this file but not the suite: absent, it is skipped; present, Node is required.
if [ -f "$D/worker.test.mjs" ]; then
  echo "== worker"
  if ! command -v node >/dev/null 2>&1 || ! node -e 'const [a,b]=process.versions.node.split(".").map(Number); process.exit(a>22||(a===22&&b>=13)?0:1)'; then
    echo "beacon's Worker suite needs Node 22.13 or later; found $(node --version 2>/dev/null || echo none)"
    rc=1
  else
    node --test --no-warnings=ExperimentalWarning "$D/worker.test.mjs" || rc=1
  fi
fi
exit $rc
