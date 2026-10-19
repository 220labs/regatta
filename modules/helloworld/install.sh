#!/bin/sh
# helloworld's shell face. Nothing to install beyond the plugin (its bin/ is on the Bash PATH
# while enabled): --check says whether what the gate needs is found — the core, the private word
# list and wharf's pre-push guard (publish --pr refuses without it). --remove: nothing to remove.
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
import importlib.machinery as m, importlib.util as u
sp = u.spec_from_loader("helloworld", m.SourceFileLoader("helloworld", sys.argv[1] + "/bin/helloworld"))
hw = u.module_from_spec(sp); sp.loader.exec_module(hw)
wl, guard = hw.wordlist_path(), hw.guard_path()
print("core:       %s" % common.__file__)
print("word list:  %s" % (wl if wl.is_file() else "MISSING (%s) — check and publish refuse" % wl))
print("pre-push:   %s" % (guard or "MISSING — publish --pr refuses (install the wharf module)"))
sys.exit(0 if wl.is_file() and guard else 1)
PY
    ;;
  --remove|"") echo "helloworld: nothing to install or remove outside the plugin" ;;
  *) echo "usage: install.sh [--check | --remove]" >&2; exit 2 ;;
esac
