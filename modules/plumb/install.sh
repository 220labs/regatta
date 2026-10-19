#!/bin/sh
# plumb's shell face. The plugin itself needs no install (its bin/ is on the Bash PATH while
# enabled); this script adds the one job that is not a plugin file:
#   --check      what crew-report will read — the core, its config, the login dirs, whether
#                usage-report (the cost column) and the publish tool are found — and whether the
#                weekly job is loaded
#   --schedule   write and load one launchd agent: `crew-report week --write --publish` on Mondays at 07:30
#                local time (after usage-report's morning render, so the cost CSVs are complete)
#   --remove     unload that agent and delete its plist
# Nothing here runs by itself: the job exists only after someone runs --schedule.
#
# Environment (the tests use it, so they never touch the real launchd):
#   PLUMB_LAUNCH_DIR  where the plist goes        (default ~/Library/LaunchAgents)
#   PLUMB_LAUNCHCTL   the launchctl to call      (default launchctl)
#   PLUMB_LABEL       the job's label             (default dev.regatta.plumb.crew-report)
# The plist records the path of the crew-report it was installed from: from a linked worktree it
# names the main checkout instead (as the core's install.sh does), since /finish removes a worktree.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
job=$here
common=$(git -C "$here" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
[ -n "$common" ] && [ "$(basename "$common")" = .git ] && [ -d "$(dirname "$common")/modules/plumb" ] \
  && job="$(dirname "$common")/modules/plumb"
label=${PLUMB_LABEL:-dev.regatta.plumb.crew-report}
la=${PLUMB_LAUNCH_DIR:-$HOME/Library/LaunchAgents}
lc=${PLUMB_LAUNCHCTL:-launchctl}
uid=$(id -u)
plist="$la/$label.plist"

case "${1:-}" in
  --check)
    python3 - "$here" <<'PY'
import sys
import importlib.machinery as m, importlib.util as u
sp = u.spec_from_loader("crew_report", m.SourceFileLoader("crew_report", sys.argv[1] + "/bin/crew-report"))
cr = u.module_from_spec(sp); sp.loader.exec_module(cr)
c = cr.load_config()
print("core:         %s" % cr.common.__file__)
print("config:       %s" % (c.get("_file") or "none (%s): defaults" % cr.config_path()))
print("login dirs:   %s" % (", ".join(str(p) for p in cr.login_dirs()) or "none"))
print("usage-report: %s" % (cr.common.tool("usage-report") or "not found — no cost column"))
print("publish:      %s" % (("%s via %s" % (c["publish"], cr.common.tool("publish") or "no tool found — local only")) if c.get("publish") else "off (local only)"))
print("cache:        %s" % (c.get("cache") or "off"))
PY
    if "$lc" print "gui/$uid/$label" >/dev/null 2>&1; then
      echo "schedule:     loaded ($label, Mondays 07:30)"
    elif [ -f "$plist" ]; then
      echo "schedule:     plist written but not loaded ($plist)"
    else
      echo "schedule:     off (sh $here/install.sh --schedule)"
    fi
    ;;
  --schedule)
    mkdir -p "$la"
    python3 - "$job" "$label" "$plist" <<'PY'
import os, plistlib, sys
here, label, out = sys.argv[1:4]
sys.path.insert(0, os.path.join(here, "lib"))
import find_core
sys.path.insert(0, find_core.hooks())
import common
log = common.LOG_DIR
log.mkdir(parents=True, exist_ok=True)
env = {"PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"}
# A job does not inherit the installer's shell: carry the two overrides that name its config.
for k in ("REGATTA_CONFIG", "CREW_REPORT_CONFIG"):
    if os.environ.get(k):
        env[k] = os.environ[k]
plist = {
    "Label": label,
    # --publish only here: a published file has one publisher, the job, never a hand run.
    "ProgramArguments": [sys.executable, os.path.join(here, "bin", "crew-report"), "week", "--write", "--publish"],
    # Mondays 07:30 local; a Mac asleep then runs it at the first wake (launchd coalesces).
    "StartCalendarInterval": {"Weekday": 1, "Hour": 7, "Minute": 30},
    "EnvironmentVariables": env,
    "StandardOutPath": str(log / "crew-report.log"),
    "StandardErrorPath": str(log / "crew-report.log"),
}
with open(out, "wb") as f:
    plistlib.dump(plist, f)
PY
    "$lc" bootout "gui/$uid/$label" 2>/dev/null || true
    # bootout returns before the old job is gone ("Bootstrap failed: 5"): one retry.
    "$lc" bootstrap "gui/$uid" "$plist" 2>/dev/null || { sleep 2; "$lc" bootstrap "gui/$uid" "$plist"; }
    echo "plumb: scheduled $label (Mondays 07:30) — $plist"
    ;;
  --remove)
    "$lc" bootout "gui/$uid/$label" 2>/dev/null || true
    rm -f "$plist"
    echo "plumb: removed $label"
    ;;
  "") echo "plumb: the plugin needs no install; --schedule adds the weekly job, --check says what is set" ;;
  *) echo "usage: install.sh [--check | --schedule | --remove]" >&2; exit 2 ;;
esac
