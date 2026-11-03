#!/bin/sh
# helloworld's shell face. Nothing to install beyond the plugin (its bin/ is on the Bash PATH
# while enabled), but the one job that is not a plugin file:
#   --check      whether what the gate needs is found — the core, the private word list and wharf's
#                pre-push guard (publish --pr refuses without it) — and whether the nightly is loaded
#   --schedule   write and load one launchd agent: `bin/helloworld nightly` at 03:30 local time, which
#                publishes --pr every checkout the config dir's helloworld/nightly-repos names and
#                merges on green where the repo's .helloworld/nightly says on-green (README, "The nightly")
#   --remove     unload that agent and delete its plist
# --schedule refuses where the nightly could not run: no helloworld/nightly-repos on this host, no
# word list, no pre-push guard, or a dry run (`helloworld nightly --dry-run`) that does not pass —
# a job that would only fail each night is not loaded. Nothing here runs by itself.
#
# Environment (the tests use it, so they never touch the real launchd):
#   HELLOWORLD_LAUNCH_DIR  where the plist goes   (default ~/Library/LaunchAgents)
#   HELLOWORLD_LAUNCHCTL   the launchctl to call (default launchctl)
#   HELLOWORLD_LABEL       the job's label        (default dev.regatta.helloworld-nightly)
#   HELLOWORLD_JOB_DIR     the module the job runs (default: as below)
# The plist records the path of the helloworld it was installed from: from a linked worktree it names
# the main checkout instead (as aurora's install.sh does), since /finish removes a worktree. The dry
# run is that copy's, so a worktree ahead of main never vouches for a main that cannot run the night.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
job=$here
common=$(git -C "$here" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
[ -n "$common" ] && [ "$(basename "$common")" = .git ] && [ -d "$(dirname "$common")/modules/helloworld" ] \
  && job="$(dirname "$common")/modules/helloworld"
job=${HELLOWORLD_JOB_DIR:-$job}
label=${HELLOWORLD_LABEL:-dev.regatta.helloworld-nightly}
la=${HELLOWORLD_LAUNCH_DIR:-$HOME/Library/LaunchAgents}
lc=${HELLOWORLD_LAUNCHCTL:-launchctl}
uid=$(id -u)
plist="$la/$label.plist"

# what the gate needs, one line each; exit 1 when any is missing
needs() {
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
try:
    repos = hw.nightly_repos()
except hw.Refused as e:
    repos = None
    print("nightly:    %s" % e)
print("core:       %s" % common.__file__)
print("word list:  %s" % (wl if wl.is_file() else "MISSING (%s) — check and publish refuse" % wl))
print("pre-push:   %s" % (guard or "MISSING — publish --pr refuses (install the wharf module)"))
if repos is not None:
    print("nightly:    %s" % (", ".join(repos) if repos else "no repo (%s names none)" % (common.CONFIG / hw.NIGHTLY_REPOS)))
print("logs:       %s" % (common.LOG_DIR / "helloworld"))
sys.exit(0 if wl.is_file() and guard and repos is not None else 1)
PY
}

case "${1:-}" in
  --check)
    rc=0
    needs || rc=1
    if "$lc" print "gui/$uid/$label" >/dev/null 2>&1; then
      echo "schedule:   loaded ($label, nightly 03:30)"
    elif [ -f "$plist" ]; then
      echo "schedule:   plist written but not loaded ($plist)"
    else
      echo "schedule:   off (sh $here/install.sh --schedule)"
    fi
    exit $rc
    ;;
  --schedule)
    # Loading a job that merges into a public twin stands for the owner's yes: never an unattended
    # caller's (AGENTS.md's trap on a flag that stands for a person's yes; build review, 2026-11-01).
    if [ -n "${REGATTA_UNATTENDED:-}${CLAUDE_UNATTENDED:-}" ]; then
      echo "helloworld: not loading the nightly from an unattended run (REGATTA_UNATTENDED or CLAUDE_UNATTENDED is set): --schedule is the owner's step" >&2
      exit 2
    fi
    out=$(needs) || { printf '%s\n' "$out" >&2; echo "helloworld: not loading the nightly — the gate is not ready here (above)" >&2; exit 1; }
    logs=$(printf '%s\n' "$out" | sed -n 's/^logs: *//p')
    case "$out" in
      *"nightly:    no repo"*) echo "helloworld: not loading the nightly — no repo to publish on this host (the config dir's helloworld/nightly-repos)" >&2; exit 1 ;;
    esac
    # The job's own dry run, by the copy the plist will run: each repo's mode and check, main's checks
    # and the merge actor printed. It fails on a gate that refuses main, a config that cannot be read,
    # a merge actor whose login or name holds a private word, or a copy with no nightly verb; a red
    # main-check or an actor's rights are printed, not judged.
    err=$(mktemp); rc=0
    dry=$(python3 "$job/bin/helloworld" nightly --dry-run 2>"$err") || rc=$?
    why=$(tail -n 1 "$err"); rm -f "$err"
    if [ "$rc" != 0 ]; then
      printf '%s\n' "$dry" | tail -n 20 >&2
      echo "helloworld: not loading the nightly — its dry run did not pass (exit $rc${why:+: $why})" >&2
      exit 1
    fi
    mkdir -p "$la" "$logs"
    python3 - "$job" "$label" "$plist" "$logs" <<'PY'
import os, plistlib, sys
here, label, out, logs = sys.argv[1:5]
env = {"PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"}
# A job does not inherit the installer's shell: carry the overrides that say where things are.
for k in ("REGATTA_CONFIG", "REGATTA_HOME", "HELLOWORLD_WORDLIST", "OPENSOURCE_WORDLIST"):
    if os.environ.get(k):
        env[k] = os.environ[k]
plist = {
    "Label": label,
    "ProgramArguments": [os.path.join(here, "bin", "helloworld"), "nightly"],
    # 03:30 local, when main is quietest; a Mac asleep then runs it at the first wake (launchd coalesces).
    "StartCalendarInterval": {"Hour": 3, "Minute": 30},
    "EnvironmentVariables": env,
    "StandardOutPath": os.path.join(logs, "nightly.log"),
    "StandardErrorPath": os.path.join(logs, "nightly.log"),
}
with open(out, "wb") as f:
    plistlib.dump(plist, f)
PY
    "$lc" bootout "gui/$uid/$label" 2>/dev/null || true
    # bootout returns before the old job is gone ("Bootstrap failed: 5"): one retry.
    "$lc" bootstrap "gui/$uid" "$plist" 2>/dev/null || { sleep 2; "$lc" bootstrap "gui/$uid" "$plist"; }
    echo "helloworld: scheduled $label (nightly 03:30) — $plist"
    ;;
  --remove)
    "$lc" bootout "gui/$uid/$label" 2>/dev/null || true
    rm -f "$plist"
    echo "helloworld: removed $label"
    ;;
  "") echo "helloworld: nothing to install outside the plugin; --schedule adds the nightly, --check says what is found" ;;
  *) echo "usage: install.sh [--check | --schedule | --remove]" >&2; exit 2 ;;
esac
