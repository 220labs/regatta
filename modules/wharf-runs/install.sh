#!/bin/sh
# wharf-runs' shell face. The plugin itself needs no install (its bin/ is on the Bash PATH while
# enabled); this script adds the one job that is not a plugin file:
#   --check      what the tools here will find — the core, the registry, orca-host's peer tools
#                and config keys, autofinish's switch — whether the sweep is scheduled, and what a
#                /finish here needs: the publish gate's word list, the finish skill in each login dir
#   --schedule   write and load one launchd agent: `bin/autofinish --sweep` every 10 minutes and at
#                load. The sweep only judges until `autofinish arm` is run on this Mac; armed, it
#                starts an idle branch's /finish by the start rules in its header.
#   --remove     unload that agent and delete its plist
# Nothing here runs by itself: the job exists only after someone runs --schedule. Where an overlay is
# installed (the config dir's `regatta/overlay` marker) it schedules the sweep itself — through its old path, an
# exec shim into this module — so --schedule refuses there: two sweeps would start one branch twice. On a Mac
# only: the overlay's `bootstrap.sh --schedule` writes launchd jobs, so off a Mac (the Linux node) nothing
# schedules the sweep but this, through bin/systemd-launchctl (the plist in the same folder, a user timer), under
# `<wharf-runs/label-prefix>.autofinish` where that key is set — the overlay's own label for the job, and the
# prefix dispatch's jobs take — so a later overlay job there through the same shim would replace this one
# rather than run beside it (node-lands, 2026-10-31). An overlay that wrote its own systemd unit under another
# name would run a second sweep: nothing here can see that, so the overlay's change must remove this job.
#
# Environment (the tests use it, so they never touch the real launchd):
#   WHARF_RUNS_LAUNCH_DIR  where the plist goes   (default ~/Library/LaunchAgents)
#   WHARF_RUNS_LAUNCHCTL   the launchctl to call (default launchctl; off a Mac bin/systemd-launchctl)
#   WHARF_RUNS_LABEL       the job's label        (default dev.regatta.autofinish; off a Mac
#                          <wharf-runs/label-prefix>.autofinish where that key is set)
#   WHARF_RUNS_LOG_DIR     the job's log folder   (default ~/Library/Logs/regatta)
#   WHARF_RUNS_OS          this system's name     (default `uname`; Darwin is a Mac, anything else not)
# The plist records the path of the autofinish it was installed from: from a linked worktree it names
# the main checkout instead (as aurora's install.sh does), since /finish removes a worktree.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
job=$here
common=$(git -C "$here" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
[ -n "$common" ] && [ "$(basename "$common")" = .git ] && [ -d "$(dirname "$common")/modules/wharf-runs" ] \
  && job="$(dirname "$common")/modules/wharf-runs"
os=${WHARF_RUNS_OS:-$(uname)}
cfg=${REGATTA_CONFIG:-$HOME/.config/regatta}
prefix="" prev=""
if [ "$os" != Darwin ]; then
  # the first line with any text, every blank (a CR included) dropped, as the core's config_line reads it
  [ -f "$cfg/wharf-runs/label-prefix" ] && prefix=$(sed -n '/[^[:space:]]/{s/[[:space:]]//g;p;q;}' "$cfg/wharf-runs/label-prefix")
  # a prefix moved (label-prefix-previous, as dispatch's jobs read it): the old job is booted out beside the new one's
  # load, so a move never leaves two sweeps (the build review)
  [ -f "$cfg/wharf-runs/label-prefix-previous" ] && prev=$(sed -n '/[^[:space:]]/{s/[[:space:]]//g;p;q;}' "$cfg/wharf-runs/label-prefix-previous")
fi
label=${WHARF_RUNS_LABEL:-${prefix:-dev.regatta}.autofinish}
# The labels a schedule here may have loaded before: a moved prefix's, and the default's once a prefix is set
# (a first --schedule before the overlay wrote label-prefix; the landing review). A label holds no blank.
old_labels=""
[ -z "${WHARF_RUNS_LABEL:-}" ] && [ -n "$prev" ] && [ "$prev.autofinish" != "$label" ] && old_labels="$prev.autofinish"
[ -z "${WHARF_RUNS_LABEL:-}" ] && [ "$label" != dev.regatta.autofinish ] && old_labels="$old_labels dev.regatta.autofinish"
la=${WHARF_RUNS_LAUNCH_DIR:-$HOME/Library/LaunchAgents}
if [ "$os" = Darwin ]; then lc=${WHARF_RUNS_LAUNCHCTL:-launchctl}; else lc=${WHARF_RUNS_LAUNCHCTL:-$here/bin/systemd-launchctl}; fi
logs=${WHARF_RUNS_LOG_DIR:-$HOME/Library/Logs/regatta}
uid=$(id -u)
plist="$la/$label.plist"

case "${1:-}" in
  --check)
    rc=0
    python3 -B - "$here" <<'PY' || rc=1
import sys
import importlib.machinery as m, importlib.util as u
sp = u.spec_from_loader("orca_host", m.SourceFileLoader("orca_host", sys.argv[1] + "/bin/orca-host"))
oh = u.module_from_spec(sp); sp.loader.exec_module(oh)
c = oh.common
print("core:        %s" % c.__file__)
reg = c.repos_json()
reg = reg if reg and reg.is_file() else None
print("registry:    %s" % (reg or "MISSING — orca-host scopes and check refuse; autofinish and rc-hosts read no repo"))
found = {t: c.tool(t) for t in ("scopes", "account", "branches.py", "keel", "tier_check.py", "helmlib.py")}
for t, why in (("scopes", "scopes and check refuse"), ("account", "setup skips orca-sync; runs keep the one login"),
               ("branches.py", "autofinish and pickup refuse (wharf)"), ("keel", "no D-list gate in the lander"),
               ("tier_check.py", "the week's budget is unread"), ("helmlib.py", "wharf check and apply refuse (helm)")):
    print("%-12s %s" % (t.replace(".py", "") + ":", found[t] or "MISSING — " + why))
ok = bool(reg and found["scopes"] and found["branches.py"])
for key in (oh.PAIRS_KEY, oh.PEERS_KEY):
    try:
        print("%-12s %s" % (key.split("/")[1] + ":", oh.config_map(key) or "none"))
    except oh.OrcaError as e:
        print("%-12s %s" % (key.split("/")[1] + ":", e)); ok = False
sys.exit(0 if ok else 1)
PY
    if [ -f "$here/bin/autofinish" ]; then
      printf '%-12s %s\n' "autofinish:" "$(python3 "$here/bin/autofinish" status 2>/dev/null || echo unreadable)"
    fi
    # One read shared with dispatch-queue: the report and the claim use the same prerequisites.
    # Report only: a host with no public twin may still use the tools without a word list.
    python3 -B - "$here" "$lc" "$label" "$plist" <<'PY_CHECK' || true
import sys
sys.path.insert(0, sys.argv[1] + "/lib")
import core_path
core_path.require()
import common
from finish_capability import capability
report = capability(common, *sys.argv[2:5])
for key in ("schedule", "word list", "finish"):
    print("%-12s %s" % (key + ":", report[key]))
PY_CHECK
    exit $rc
    ;;
  --schedule)
    if [ "$os" = Darwin ] && [ -e "$cfg/regatta/overlay" ] && [ -z "${WHARF_RUNS_SCHEDULE_BESIDE_OVERLAY:-}" ]; then
      echo "wharf-runs: an overlay is installed here ($cfg/regatta/overlay): it schedules the sweep itself; not loading a second job" >&2
      exit 1
    fi
    [ -f "$here/bin/autofinish" ] || { echo "wharf-runs: no bin/autofinish in $here — nothing to schedule" >&2; exit 1; }
    mkdir -p "$la" "$logs"
    python3 - "$job" "$label" "$plist" "$logs" <<'PY'
import os, plistlib, sys
here, label, out, logs = sys.argv[1:5]
env = {"PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:" + os.path.expanduser("~/.local/bin")}
# A job does not inherit the installer's shell: carry the overrides that say where things are.
for k in ("REGATTA_CONFIG", "REGATTA_HOME", "CLAUDE_REPOS_JSON"):
    if os.environ.get(k):
        env[k] = os.environ[k]
plist = {
    "Label": label,
    "ProgramArguments": ["/usr/bin/python3", os.path.join(here, "bin", "autofinish"), "--sweep"],
    # An interval: a Mac asleep skips the tick and runs the next one after waking.
    "StartInterval": 600,
    "RunAtLoad": True,
    "EnvironmentVariables": env,
    "StandardOutPath": os.path.join(logs, "autofinish-launchd.log"),
    "StandardErrorPath": os.path.join(logs, "autofinish-launchd.log"),
}
with open(out, "wb") as f:
    plistlib.dump(plist, f)
PY
    "$lc" bootout "gui/$uid/$label" 2>/dev/null || true
    for old in $old_labels; do "$lc" bootout "gui/$uid/$old" 2>/dev/null || true; rm -f "$la/$old.plist"; done
    # bootout returns before the old job is gone ("Bootstrap failed: 5"): one retry.
    "$lc" bootstrap "gui/$uid" "$plist" 2>/dev/null || { sleep 2; "$lc" bootstrap "gui/$uid" "$plist"; }
    echo "wharf-runs: scheduled $label (autofinish --sweep every 10 min; it starts nothing until \`autofinish arm\`) — $plist"
    ;;
  --remove)
    "$lc" bootout "gui/$uid/$label" 2>/dev/null || true
    rm -f "$plist"
    for old in $old_labels; do "$lc" bootout "gui/$uid/$old" 2>/dev/null || true; rm -f "$la/$old.plist"; done
    echo "wharf-runs: removed $label"
    ;;
  "") echo "wharf-runs: the plugin needs no install; --schedule adds the autofinish sweep, --check says what is found" ;;
  *) echo "usage: install.sh [--check | --schedule | --remove]" >&2; exit 2 ;;
esac
