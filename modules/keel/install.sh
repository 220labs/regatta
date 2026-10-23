#!/bin/sh
# keel's shell face. Nothing to install beyond the plugin (its bin/ is on the Bash PATH while
# enabled): --check says whether the core is found and which optional peers are. The hooks are
# wired by the overlay's bootstrap.sh --hooks until the plugin carries hooks.json (the design's
# D3-B). --remove: nothing to remove.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
case "${1:-}" in
  --check)
    python3 - "$here" <<'PY'
import sys
sys.path.insert(0, sys.argv[1] + "/lib")
import find_core
sys.path.insert(0, find_core.hooks())
import common
print("core:  %s" % common.__file__)
for name, lost in (("asklib.py", "the relay check; a relayed answer reads as the owner's"),
                   ("surfaces.py", "the listener reminder"), ("ask", "the ask line names bin/ask bare"),
                   ("dispatch-rc", "no run told alive"), ("docs-index", "no record banner stamped"),
                   ("claude-settings", "sheep gate refuses to write settings")):
    p = common.tool(name)
    print("peer:  %-16s %s" % (name, p or "absent — " + lost))
PY
    ;;
  --remove|"") echo "keel: nothing to install or remove outside the plugin" ;;
  *) echo "usage: install.sh [--check | --remove]" >&2; exit 2 ;;
esac
