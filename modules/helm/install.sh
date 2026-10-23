#!/bin/sh
# helm's shell face. The plugin itself needs no install (its bin/ is on the Bash PATH while
# enabled; helm itself is `regatta helm`, off PATH); this script adds the one job that is not a
# plugin file, the ask poll — every 5 minutes `ask poll` fetches each repo's claude/* branches into
# a cache mirror, raises a banner per new ask, and runs `helm tick` (the skippers' tick):
#   --check      what helm finds — the core, surfaces.json, each peer and what is lost without it —
#                and whether the poll is loaded
#   --plist      print the poll's launchd plist, for an installer that loads its own jobs (an
#                overlay's --schedule writes it beside its other agents and loads them together)
#   --schedule   write and load that plist
#   --remove     unload it and delete the plist
# Nothing here runs by itself: the job exists only after someone runs --schedule (or the overlay's).
#
# Environment (the tests use it, so they never touch the real launchd):
#   HELM_LAUNCH_DIR  where the plist goes            (default ~/Library/LaunchAgents)
#   HELM_LAUNCHCTL   the launchctl to call          (default launchctl)
#   HELM_LABEL       the job's label                 (default dev.regatta.helm.ask-poll)
#   HELM_LOG         the job's log file              (default ask-poll.log in the core's log dir)
# An overlay that had the job under its own label passes that label and log, so the job is
# replaced in place, never doubled. The plist records the path of the bin/ask it was installed
# from: from a linked worktree it names the main checkout instead (as the core's install.sh
# does), since /finish removes a worktree.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
job=$here
common=$(git -C "$here" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
[ -n "$common" ] && [ "$(basename "$common")" = .git ] && [ -d "$(dirname "$common")/modules/helm" ] \
  && job="$(dirname "$common")/modules/helm"
label=${HELM_LABEL:-dev.regatta.helm.ask-poll}
la=${HELM_LAUNCH_DIR:-$HOME/Library/LaunchAgents}
lc=${HELM_LAUNCHCTL:-launchctl}
uid=$(id -u)
plist="$la/$label.plist"

write_plist() {  # <out>: the plist, to a file or - for stdout
  python3 - "$job" "$label" "${HELM_LOG:-}" "$1" <<'PY'
import os, plistlib, sys
here, label, log, out = sys.argv[1:5]
sys.path.insert(0, os.path.join(here, "lib"))
import find_core
sys.path.insert(0, find_core.hooks())
import common
if not log:
    common.LOG_DIR.mkdir(parents=True, exist_ok=True)
    log = str(common.LOG_DIR / "ask-poll.log")
home = os.path.expanduser("~")
# The poll runs git, the spacesheep CLI and helm tick's ssh: Homebrew's and the user's own bin.
env = {"PATH": "/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:%s/.local/bin" % home}
# A job does not inherit the installer's shell: carry the overrides that name its config.
for k in ("REGATTA_CONFIG", "SURFACES_FILE"):
    if os.environ.get(k):
        env[k] = os.environ[k]
plist = {
    "Label": label,
    # /usr/bin/python3, as the job always ran: a Homebrew python moves under an upgrade
    "ProgramArguments": ["/usr/bin/python3", os.path.join(here, "bin", "ask"), "poll"],
    "StartInterval": 300,
    "RunAtLoad": True,
    "EnvironmentVariables": env,
    "StandardOutPath": log,
    "StandardErrorPath": log,
}
if out == "-":
    sys.stdout.buffer.write(plistlib.dumps(plist))
else:
    with open(out, "wb") as f:
        plistlib.dump(plist, f)
PY
}

case "${1:-}" in
  --check)
    python3 - "$here" <<'PY'
import sys
sys.path.insert(0, sys.argv[1] + "/bin")
import helmlib, surfaces
c = helmlib._common()
print("core:         %s" % c.__file__)
print("surfaces:     %s%s" % (surfaces.FILE, "" if surfaces.FILE.exists() else " (absent: the defaults)"))
for name, lost in (("keel", "ask relay and the board's doc cards (keel)"),
                   ("sheep_gate.py", "the guarded list is the fallback copy (keel)"),
                   ("dispatch-rc", "stalls judges no run; the board shows none (wharf-runs)"),
                   ("harness", "no Orca read, no harness retry (wharf-runs)"),
                   ("wharf", "the tick applies no ship (wharf-runs)"),
                   ("blueprintlib.py", "helm task --done-when (wharf-runs)"),
                   ("usage-report", "no session cost (plumb)"),
                   ("tier_check.py", "no week line on the board (plumb)"),
                   ("attention.py", "a relay row is written by hand (plumb)")):
    p = helmlib.peer(name)
    print("%-13s %s" % (name + ":", p or "not found — " + lost))
PY
    if "$lc" print "gui/$uid/$label" >/dev/null 2>&1; then
      echo "schedule:     loaded ($label, every 5 min)"
    elif [ -f "$plist" ]; then
      echo "schedule:     plist written but not loaded ($plist)"
    else
      echo "schedule:     off (sh $here/install.sh --schedule)"
    fi
    ;;
  --plist) write_plist - ;;
  --schedule)
    mkdir -p "$la"
    write_plist "$plist"
    "$lc" bootout "gui/$uid/$label" 2>/dev/null || true
    # bootout returns before the old job is gone ("Bootstrap failed: 5"): one retry.
    "$lc" bootstrap "gui/$uid" "$plist" 2>/dev/null || { sleep 2; "$lc" bootstrap "gui/$uid" "$plist"; }
    echo "helm: scheduled $label (every 5 min) — $plist"
    ;;
  --remove)
    "$lc" bootout "gui/$uid/$label" 2>/dev/null || true
    rm -f "$plist"
    echo "helm: removed $label"
    ;;
  "") echo "helm: the plugin needs no install; --schedule adds the ask poll, --check says what is found" ;;
  *) echo "usage: install.sh [--check | --plist | --schedule | --remove]" >&2; exit 2 ;;
esac
