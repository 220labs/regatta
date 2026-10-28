#!/bin/sh
# lighthouse's shell face. Nothing to install beyond the plugin (its bin/ is on the Bash PATH
# while enabled, its hooks in hooks/hooks.json); `cc` is one line in the shell's rc file, which
# this prints. --check: the core, each private value lighthouse reads (README, "Private values")
# and each optional peer, found or not, and the desk's job. The daily `health` job is the
# overlay's own schedule (its launchd plist).
#   --schedule   the desk's sampler (lighthouse-ops S2): `ops sample` every 15 minutes with
#                LIGHTHOUSE_DESK=1, on `lighthouse/ops-host` only — `ops is-host` decides, and any
#                other host, or a key that names none, is refused. On a Mac one LaunchAgent; on
#                Linux (the yard node's agent guest) the systemd timer is yard-node S5's: this prints
#                the unit's lines and writes nothing (the seam: the same command and environment).
#                Beside it the intake (S4): `ops ingest` every 10 minutes, the same host rule and
#                environment, its own agent (`<label>.ingest`) or, on Linux, its own unit's lines.
#   --remove     unload both agents and delete their plists
# Nothing here runs by itself: the job exists only after someone runs --schedule on the ops host.
# Environment (the tests use it, so they never touch the real launchd):
#   LIGHTHOUSE_LAUNCH_DIR  where the plist goes   (default ~/Library/LaunchAgents)
#   LIGHTHOUSE_LAUNCHCTL   the launchctl to call  (default launchctl)
#   LIGHTHOUSE_LABEL       the job's label        (default dev.regatta.lighthouse.ops)
#   LIGHTHOUSE_UNAME       the OS, as uname says  (default `uname`)
# The plist names the main checkout's bin/ops even from a linked worktree (as plumb's does): /finish
# removes a worktree, and a job pointing into one would die with it.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
job=$here
common=$(git -C "$here" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
[ -n "$common" ] && [ "$(basename "$common")" = .git ] && [ -d "$(dirname "$common")/modules/lighthouse" ] \
  && job="$(dirname "$common")/modules/lighthouse"
label=${LIGHTHOUSE_LABEL:-dev.regatta.lighthouse.ops}
la=${LIGHTHOUSE_LAUNCH_DIR:-$HOME/Library/LaunchAgents}
lc=${LIGHTHOUSE_LAUNCHCTL:-launchctl}
os=${LIGHTHOUSE_UNAME:-$(uname)}
uid=$(id -u)
plist="$la/$label.plist"
iplist="$la/$label.ingest.plist"

case "${1:-}" in
  --check)
    python3 - "$here" <<'PY'
import sys
sys.path.insert(0, sys.argv[1] + "/lib")
import find_core
sys.path.insert(0, find_core.hooks())
import common
print("core:     %s" % common.__file__)
for k in ("accounts.json", "tenants.json", "logins.json", "user.json", "env-keys.json", "hosts", "vault", "vaults",
          "gated-tools", "ff", "design-host", "cc-prefix", "shares", "nas", "drive", "yabairc", "ops-host", "ops-projects"):
    p = common.CONFIG / "lighthouse" / k
    print("%-9s %s" % ("ok" if p.exists() else "--", "lighthouse/" + k + ("" if p.exists() else
          " (a link that reads nothing)" if p.is_symlink() else " (absent: its default)")))
for t in ("fork_claude_session.py", "worktree_allow.py", "tend", "sync.py", "rc-hosts", "bulletin.py",
          "knowledge-commit", "usage-report", "headroom", "dispatch", "dispatch-queue"):
    print("%-9s %s" % ("peer" if common.tool(t) else "--", t + ("" if common.tool(t) else " not installed: its verb says so")))
PY
    for j in "$label|$plist|15|ops job" "$label.ingest|$iplist|10|ingest"; do
      l=${j%%|*}; r=${j#*|}; p=${r%%|*}; r=${r#*|}; m=${r%%|*}; n=${r#*|}
      if [ "$os" = Darwin ] && "$lc" print "gui/$uid/$l" >/dev/null 2>&1; then
        echo "$n:  loaded ($l, every $m min)"
      elif [ -f "$p" ]; then
        echo "$n:  plist written but not loaded ($p)"
      else
        echo "$n:  off ($(python3 "$here/bin/ops" is-host 2>&1 || true))"
      fi
    done
    ;;
  --schedule)
    # the host rule first: only the ops host gets the job (two samplers would write two desks' rows)
    # (the job's own ops, the code the plist runs: a main checkout that predates is-host exits 2, which is refused below)
    rc=0; out=$(python3 "$job/bin/ops" is-host 2>&1) || rc=$?
    case "$rc" in
      0) ;;
      3|4) echo "lighthouse: not scheduling the desk's sampler — $out" >&2; exit 1 ;;
      *) echo "lighthouse: not scheduling the desk's sampler — ops is-host could not tell (exit $rc: $(printf '%s\n' "$out" | tail -n 1))" >&2; exit 1 ;;
    esac
    # the dry run: a job whose ops has no sample verb would fail at argparse every 15 minutes, seen only in its log
    python3 "$job/bin/ops" sample --help >/dev/null 2>&1 \
      || { echo "lighthouse: not scheduling the desk's sampler — $job/bin/ops has no sample verb" >&2; exit 1; }
    python3 "$job/bin/ops" ingest --help >/dev/null 2>&1 \
      || { echo "lighthouse: not scheduling the desk's intake — $job/bin/ops has no ingest verb" >&2; exit 1; }
    if [ "$os" != Darwin ]; then
      # yard-node S5's seam: the unit it writes runs this, under this environment, every 15 minutes
      echo "lighthouse: a systemd timer is yard-node S5's, not written here; its unit's lines:" >&2
      echo "  ExecStart=$(command -v python3) $job/bin/ops sample" >&2
      echo "  Environment=LIGHTHOUSE_DESK=1${REGATTA_CONFIG:+ REGATTA_CONFIG=$REGATTA_CONFIG}" >&2
      echo "  OnBootSec=2min, OnUnitActiveSec=15min (the timer)" >&2
      echo "lighthouse: the intake's unit beside it (S4):" >&2
      echo "  ExecStart=$(command -v python3) $job/bin/ops ingest" >&2
      echo "  Environment=LIGHTHOUSE_DESK=1${REGATTA_CONFIG:+ REGATTA_CONFIG=$REGATTA_CONFIG}" >&2
      echo "  OnBootSec=3min, OnUnitActiveSec=10min (the timer)" >&2
      exit 1
    fi
    mkdir -p "$la"
    write_plist() {
    python3 - "$job" "$1" "$2" "$3" "$4" <<'PY'
import os, plistlib, sys
here, label, out, verb, every = sys.argv[1:6]
sys.path.insert(0, os.path.join(here, "lib"))
import find_core
sys.path.insert(0, find_core.hooks())
import common
log = common.LOG_DIR
log.mkdir(parents=True, exist_ok=True)
# LIGHTHOUSE_DESK=1 makes it the desk's job, the one reader of the owner's token (bin/ops' header);
# a job does not inherit the installer's shell, so the config dir's override is carried
env = {"PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin", "LIGHTHOUSE_DESK": "1"}
if os.environ.get("REGATTA_CONFIG"):
    env["REGATTA_CONFIG"] = os.environ["REGATTA_CONFIG"]
plist = {
    "Label": label,
    "ProgramArguments": [sys.executable, os.path.join(here, "bin", "ops"), verb],
    "StartInterval": int(every),
    "RunAtLoad": True,
    "EnvironmentVariables": env,
    "StandardOutPath": str(log / ("ops-%s.log" % verb)),
    "StandardErrorPath": str(log / ("ops-%s.log" % verb)),
}
with open(out, "wb") as f:
    plistlib.dump(plist, f)
PY
    }
    load() {
      "$lc" bootout "gui/$uid/$1" 2>/dev/null || true
      # bootout returns before the old job is gone ("Bootstrap failed: 5"): one retry
      "$lc" bootstrap "gui/$uid" "$2" 2>/dev/null || { sleep 2; "$lc" bootstrap "gui/$uid" "$2"; }
    }
    write_plist "$label" "$plist" sample 900
    write_plist "$label.ingest" "$iplist" ingest 600
    # each job loads on its own: a sampler that will not bootstrap never leaves the intake unloaded (set -e)
    failed=""
    if load "$label" "$plist"; then echo "lighthouse: scheduled $label (ops sample every 15 min) — $plist"
    else failed="$label"; fi
    if load "$label.ingest" "$iplist"; then echo "lighthouse: scheduled $label.ingest (ops ingest every 10 min) — $iplist"
    else failed="${failed:+$failed and }$label.ingest"; fi
    [ -z "$failed" ] || { echo "lighthouse: launchctl would not bootstrap $failed (install.sh --check says which runs)" >&2; exit 1; }
    ;;
  --remove)
    if [ "$os" = Darwin ]; then
      "$lc" bootout "gui/$uid/$label" 2>/dev/null || true
      "$lc" bootout "gui/$uid/$label.ingest" 2>/dev/null || true
    fi
    rm -f "$plist" "$iplist"
    echo "lighthouse: removed $label and $label.ingest"
    ;;
  "") echo "lighthouse: nothing to install outside the plugin; for cc, add to the shell's rc file: . '$here/shell/cc.zsh'; --schedule adds the desk's sampler and intake on the ops host" ;;
  *) echo "usage: install.sh [--check | --schedule | --remove]" >&2; exit 2 ;;
esac
