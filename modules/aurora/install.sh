#!/bin/sh
# aurora's shell face. The plugin itself needs no install (its skills load while enabled); this
# script adds the one job that is not a plugin file:
#   --check      what the night finds — `weekly-run where`, each peer, tonight's order — and
#                whether the nightly job is loaded
#   --schedule   write and load one launchd agent: `bin/weekly-run aurora <vault>` nightly at 21:00
#                local time (a night with no section due ends before claude starts)
#   --remove     unload that agent and delete its plist
# Nothing here runs by itself: the job exists only after someone runs --schedule. Where an
# overlay is installed (the config dir's `legacy` file) it schedules the night itself — on the
# owner's Macs through its old path, an exec shim into this module — so --schedule refuses there:
# two jobs would dream the week twice.
#
# Environment (the tests use it, so they never touch the real launchd):
#   AURORA_LAUNCH_DIR  where the plist goes        (default ~/Library/LaunchAgents)
#   AURORA_LAUNCHCTL   the launchctl to call      (default launchctl)
#   AURORA_LABEL       the job's label             (default dev.regatta.aurora)
# The plist records the path of the weekly-run it was installed from: from a linked worktree it
# names the main checkout instead (as the core's install.sh does), since /finish removes a worktree.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
job=$here
common=$(git -C "$here" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
[ -n "$common" ] && [ "$(basename "$common")" = .git ] && [ -d "$(dirname "$common")/modules/aurora" ] \
  && job="$(dirname "$common")/modules/aurora"
label=${AURORA_LABEL:-dev.regatta.aurora}
la=${AURORA_LAUNCH_DIR:-$HOME/Library/LaunchAgents}
lc=${AURORA_LAUNCHCTL:-launchctl}
cfg=${REGATTA_CONFIG:-$HOME/.config/regatta}
uid=$(id -u)
plist="$la/$label.plist"
where() { "$here/bin/weekly-run" where 2>/dev/null | sed -n "s/^$1 //p"; }

case "${1:-}" in
  --check)
    rc=0
    "$here/bin/weekly-run" where || rc=1
    reg=$(where regatta)
    for t in bulletin.py knowledge-commit docs-index tend repos pr branches.py rc-hosts knowledge-numbers interruptions; do
      p=$([ -f "$reg" ] && python3 "$reg" which "$t" 2>/dev/null) || p=""  # a miss prints "<t> not installed": the exit code decides
      printf '%-18s %s\n' "$t:" "${p:-not installed}"
    done
    "$here/bin/weekly-run" aurora "$(where vault)" --dry-run || rc=1
    if "$lc" print "gui/$uid/$label" >/dev/null 2>&1; then
      echo "schedule:          loaded ($label, nightly 21:00)"
    elif [ -f "$plist" ]; then
      echo "schedule:          plist written but not loaded ($plist)"
    else
      echo "schedule:          off (sh $here/install.sh --schedule)"
    fi
    exit $rc
    ;;
  --schedule)
    if { [ -e "$cfg/legacy" ] || [ -e "$cfg/regatta/overlay" ]; } && [ -z "${AURORA_SCHEDULE_BESIDE_OVERLAY:-}" ]; then
      echo "aurora: an overlay is installed here ($cfg/legacy or $cfg/regatta/overlay): it schedules the night itself; not loading a second job" >&2
      exit 1
    fi
    vault=$(where vault)
    [ -n "$vault" ] && [ "$vault" != MISSING ] || { echo "aurora: no vault configured (atlas's atlas/vault key) — nothing to schedule" >&2; exit 1; }
    # A host aurora/skip-hosts lists gets no job: weekly-run would only log its skip each night.
    if "$here/bin/weekly-run" aurora "$vault" --dry-run 2>/dev/null | grep -q '^[0-9:]* skipped:'; then
      echo "aurora: this host is in $cfg/aurora/skip-hosts — not loading the job (--remove unloads one loaded before)" >&2
      exit 1
    fi
    logs=$(where logs)
    mkdir -p "$la" "$logs"
    python3 - "$job" "$label" "$plist" "$vault" "$logs" <<'PY'
import os, plistlib, sys
here, label, out, vault, logs = sys.argv[1:6]
env = {"PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"}
# A job does not inherit the installer's shell: carry the overrides that say where things are.
for k in ("REGATTA_CONFIG", "REGATTA_HOME", "ATLAS_LAYER", "ATLAS_VAULT", "WEEKLY_LOG_DIR"):
    if os.environ.get(k):
        env[k] = os.environ[k]
plist = {
    "Label": label,
    "ProgramArguments": [os.path.join(here, "bin", "weekly-run"), "aurora", vault],
    # Nightly 21:00 local; a Mac asleep then runs it at the first wake (launchd coalesces), and
    # weekly-run's `due` decides whether anything is due by then.
    "StartCalendarInterval": {"Hour": 21, "Minute": 0},
    "EnvironmentVariables": env,
    "StandardOutPath": os.path.join(logs, "launchd.log"),
    "StandardErrorPath": os.path.join(logs, "launchd.log"),
}
with open(out, "wb") as f:
    plistlib.dump(plist, f)
PY
    "$lc" bootout "gui/$uid/$label" 2>/dev/null || true
    # bootout returns before the old job is gone ("Bootstrap failed: 5"): one retry.
    "$lc" bootstrap "gui/$uid" "$plist" 2>/dev/null || { sleep 2; "$lc" bootstrap "gui/$uid" "$plist"; }
    echo "aurora: scheduled $label (nightly 21:00) — $plist"
    ;;
  --remove)
    "$lc" bootout "gui/$uid/$label" 2>/dev/null || true
    rm -f "$plist"
    echo "aurora: removed $label"
    ;;
  "") echo "aurora: the plugin needs no install; --schedule adds the nightly job, --check says what is found" ;;
  *) echo "usage: install.sh [--check | --schedule | --remove]" >&2; exit 2 ;;
esac
