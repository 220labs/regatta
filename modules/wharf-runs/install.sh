#!/bin/sh
# wharf-runs' shell face. Nothing to install beyond the plugin (its bin/ is on the Bash PATH while
# enabled): --check says what orca-host will find — the core, the registry, its peer tools and the
# config keys. --remove: nothing to remove.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
case "${1:-}" in
  --check)
    python3 - "$here" <<'PY'
import sys
import importlib.machinery as m, importlib.util as u
sp = u.spec_from_loader("orca_host", m.SourceFileLoader("orca_host", sys.argv[1] + "/bin/orca-host"))
oh = u.module_from_spec(sp); sp.loader.exec_module(oh)
c = oh.common
print("core:        %s" % c.__file__)
reg = c.repos_json()
reg = reg if reg and reg.is_file() else None
print("registry:    %s" % (reg or "MISSING — orca-host scopes and check refuse"))
found = {t: c.tool(t) for t in ("scopes", "account")}
for t, why in (("scopes", "scopes and check refuse"), ("account", "setup skips orca-sync")):
    print("%-12s %s" % (t + ":", found[t] or "MISSING — " + why))
ok = bool(reg and found["scopes"])
for key in (oh.PAIRS_KEY, oh.PEERS_KEY):
    try:
        print("%-12s %s" % (key.split("/")[1] + ":", oh.config_map(key) or "none"))
    except oh.OrcaError as e:
        print("%-12s %s" % (key.split("/")[1] + ":", e)); ok = False
sys.exit(0 if ok else 1)
PY
    ;;
  --remove|"") echo "wharf-runs: nothing to install or remove outside the plugin" ;;
  *) echo "usage: install.sh [--check | --remove]" >&2; exit 2 ;;
esac
