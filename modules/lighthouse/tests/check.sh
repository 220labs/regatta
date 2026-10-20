#!/usr/bin/env bash
# lighthouse's check: every suite beside this file, each in scratch dirs it makes itself (HOME
# moved, REGATTA_CONFIG pinned), no network. A suite that needs a Mac (zsh, launchd, BSD tools)
# skips itself elsewhere with one printed line, so CI on ubuntu runs the rest.
#   bash modules/lighthouse/tests/check.sh
set -u
D="$(cd "$(dirname "$0")" && pwd)"
rc=0
for s in "$D"/*.sh; do
  [ "$(basename "$s")" = check.sh ] && continue
  echo "== $(basename "$s" .sh)"
  bash "$s" || rc=1
done
exit $rc
