#!/bin/sh
# atlas's shell face. Nothing to install beyond the plugin (its bin/ is on the Bash PATH while
# enabled; its hooks are wired by whoever installs the shell face). --check says what atlas finds:
# the core, the vault and the layer, and its two optional peers. --remove: nothing to remove.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
case "${1:-}" in
  --check)
    python3 - "$here" <<'PY'
import sys
sys.path.insert(0, sys.argv[1] + "/lib")
import atlaslib
core = atlaslib.core()
print("core:   %s" % (core.__file__ if core else "MISSING — install regatta (or `regatta check`: it may refuse to load)"))
bad = core is None
for role in ("vault", "layer"):
    p, k = atlaslib.repo(role), atlaslib.key(role)
    if p is None:
        print("%s:  MISSING — %s" % (role, atlaslib.missing(role)))
        bad = True
    else:
        print("%s:  %s%s" % (role, p, " (as %s)" % k[0] if k else ""))
for name, why in (("keel", "no Open line, no sets in docs-index"), ("pr", "knowledge-commit --in lands locally, no PR")):
    print("%-7s %s" % (name + ":", atlaslib.tool(name) or "absent — " + why))
sys.exit(1 if bad else 0)
PY
    ;;
  --remove|"") echo "atlas: nothing to install or remove outside the plugin" ;;
  *) echo "usage: install.sh [--check | --remove]" >&2; exit 2 ;;
esac
