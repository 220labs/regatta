#!/bin/sh
# sextant's shell and launchd face: Sparks' launcher (the ideas intake) and the weekly /sextant job.
#
#   install.sh --launcher   build the Sparks launcher from launcher.c.in (only when its stamp
#                           changed), write its launchd job and load it; says which two grants
#                           the build needs (Full Disk Access, Automation for Notes)
#   install.sh --check      what the intake needs, each on one line, and the weekly job's state;
#                           exit 1 when the intake's job cannot run
#   install.sh --remove     unload the intake's job, remove its plist, the launcher and its stamp
#   install.sh --plist      print the weekly /sextant job's plist, for an installer that loads its own
#                           jobs (an overlay's --schedule writes it beside its other agents)
#   install.sh --schedule [--dry-run]
#                           write and load that plist; --dry-run prints it and touches nothing
#   install.sh --unschedule unload the weekly job and delete its plist
#
# The weekly job (the design's G29): with aurora installed it runs aurora's `weekly-run sextant <cwd>`
# (found as every peer is: `regatta which weekly-run`), whose allow and deny lists, launch check and
# retry the unattended run needs; without aurora, the module's own runner, `libexec/sextant-run run
# <cwd>`, narrower by design (it starts no work: its header). Through wharf-runs' rc-hosts, when it
# answers `--launcher` for the program, the job starts behind that launcher (one identity for the
# Mac's privacy grants), as the overlay's other jobs do. Knobs for the weekly job (environment, all
# optional): SEXTANT_LABEL (dev.regatta.sextant), SEXTANT_LOG (sextant-launchd.log in the core's log
# dir), SEXTANT_WEEKLY (the weekly-run the plist names, over the peer lookup: an overlay names its own
# shim, the path its launcher allows), SEXTANT_CWD (the folder /sextant works in, else atlas's layer),
# SEXTANT_WEEKDAY and SEXTANT_HOUR (1 and 2: Monday 02:00), SEXTANT_LAUNCH_DIR and SEXTANT_LAUNCHCTL
# (the tests). An overlay that had the job under its own label passes that label and log, so the job
# is replaced in place, never doubled; an overlay's own installer takes --plist, and --schedule
# refuses where one is installed (the config dir's `regatta/overlay` marker, as aurora's does) unless
# SEXTANT_SCHEDULE_BESIDE_OVERLAY is set. A host `aurora/skip-hosts` lists gets no job either. Like the launcher, the plist names the main checkout's files
# when run from a linked worktree.
#
# Knobs (environment, all optional): SPARKS_LAUNCHER (the binary, ~/.local/bin/sparks-launcher),
# SPARKS_LABEL (the launchd label and codesign identifier, local.sparks.launcher), SPARKS_CONFIG
# (the config the job runs, else sextant/sparks.json in the regatta config dir), WHISPER_BIN,
# WHISPER_MODEL, WHISPER_VAD (passed to the job), SPARKS_LOG_FILE (the job's stdout,
# ~/Library/Logs/sparks.log).
#
# The stamp (the pattern of a launcher that must keep its grants): sha256 of the template, the two
# compiled-in paths and the signing identifier, written beside the binary. TCC keys an ad-hoc
# signature on the code hash, so a rebuild loses both grants: build only when the stamp differs.
#
# The launcher compiles in the path of bin/sparks: from a linked worktree it names the main
# checkout instead (as the core's and plumb's install.sh do), since /finish removes a worktree and
# the rebuild that would repair it costs both grants.
set -eu
here=$(cd "$(dirname "$0")" && pwd -P)  # resolved: the plist's remap compares it with common.tool()'s resolved paths
self=$here  # this copy: what the weekly plist is computed with (its own lib/, libexec/)
common=$(git -C "$here" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
[ -n "$common" ] && [ "$(basename "$common")" = .git ] && [ -d "$(dirname "$common")/modules/sextant" ] \
  && here="$(dirname "$common")/modules/sextant"
cfgdir=${REGATTA_CONFIG:-$HOME/.config/regatta}
bin=${SPARKS_LAUNCHER:-$HOME/.local/bin/sparks-launcher}
label=${SPARKS_LABEL:-local.sparks.launcher}
config=${SPARKS_CONFIG:-$cfgdir/sextant/sparks.json}
script="$here/bin/sparks"
src="$here/launcher.c.in"
plist="$HOME/Library/LaunchAgents/$label.plist"
# the job's log: the knob, else the config dir's sextant/log (what sparks itself reads), else the default
cfglog=$(head -n 1 "$cfgdir/sextant/log" 2>/dev/null | sed "s|^~|$HOME|" || true)
log=${SPARKS_LOG_FILE:-${cfglog:-$HOME/Library/Logs/sparks.log}}

want_stamp() { { cat "$src"; printf '%s\n%s\n%s\n' "$script" "$config" "$label"; } | shasum -a 256 | cut -d' ' -f1; }

build() {
  want=$(want_stamp)
  if [ -x "$bin" ] && [ "$(cat "$bin.source-sha256" 2>/dev/null)" = "$want" ]; then
    echo "launcher: $bin is current (stamp matches) — not rebuilt, the grants hold"; return 0
  fi
  mkdir -p "$(dirname "$bin")"
  cc -O2 -Wall -x c -DSPARKS_SCRIPT="\"$script\"" -DSPARKS_CONFIG_PATH="\"$config\"" -o "$bin" "$src"
  codesign -s - -f -i "$label" "$bin" || { echo "install.sh: codesign failed — $bin is unsigned, nothing loaded" >&2; exit 1; }
  printf '%s\n' "$want" > "$bin.source-sha256"
  echo "launcher: built $bin — it needs two grants (again: an ad-hoc signature is keyed on its hash):"
  echo "  1. System Settings → Privacy & Security → Full Disk Access: remove any old entry for it (−), then + → $bin"
  echo "  2. Automation for Apple Notes (only if a config sets apple_notes): launchctl kickstart gui/$(id -u)/$label,"
  echo "     then Allow on \"$(basename "$bin") wants access to control Notes\""
}

xml() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }

plist_text() {
  w=${WHISPER_BIN:-$(command -v whisper-cli || echo /opt/homebrew/bin/whisper-cli)}
  m=${WHISPER_MODEL:-$HOME/.cache/whisper/ggml-large-v3-turbo.bin}
  v=${WHISPER_VAD:-}
  cat <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$label</string>
  <key>ProgramArguments</key><array><string>$bin</string><string>--chain</string></array>
  <key>EnvironmentVariables</key><dict>  <!-- the launcher sets HOME, PATH and SPARKS_CONFIG itself -->
    <key>WHISPER_BIN</key><string>$w</string>
    <key>WHISPER_MODEL</key><string>$m</string>
    <key>WHISPER_VAD</key><string>$v</string>
  </dict>
  <key>WatchPaths</key><array>
$(printf '%s\n' "$inboxes" | xml | sed 's|.*|    <string>&</string>|')
  </array>
  <key>StartInterval</key><integer>900</integer>
  <key>ThrottleInterval</key><integer>15</integer>
  <key>ProcessType</key><string>Standard</string>
  <key>StandardOutPath</key><string>$log</string>
  <key>StandardErrorPath</key><string>$log</string>
</dict></plist>
EOF
}

wlabel=${SEXTANT_LABEL:-dev.regatta.sextant}
wla=${SEXTANT_LAUNCH_DIR:-$(dirname "$plist")}  # the LaunchAgents folder Sparks' job uses
wlc=${SEXTANT_LAUNCHCTL:-launchctl}
wplist="$wla/$wlabel.plist"

weekly_plist() {  # <out>: the weekly job's plist, to a file or - for stdout; one line and exit 1 when it cannot be written
  python3 - "$self" "$here" "$wlabel" "$1" <<'PY'
import os, plistlib, subprocess, sys
self, here, label, out = sys.argv[1:5]
sys.path.insert(0, os.path.join(self, "lib"))
import find_core
sys.path.insert(0, find_core.hooks())
import common
env = os.environ
cwd = env.get("SEXTANT_CWD") or ""
if not cwd:
    r = subprocess.run([sys.executable, os.path.join(self, "libexec", "sextant-run"), "where"], capture_output=True, text=True)
    cwd = next((l.split(" ", 1)[1] for l in r.stdout.splitlines() if l.startswith("layer ")), "MISSING")
if cwd == "MISSING" or not os.path.isabs(os.path.expanduser(cwd)):
    sys.exit("install.sh: no folder for /sextant to work in — atlas's layer is not configured; set SEXTANT_CWD")
cwd = os.path.expanduser(cwd)
log = env.get("SEXTANT_LOG") or ""
if not log:
    if out != "-":  # a printed plist (--plist, a dry run) writes nothing
        common.LOG_DIR.mkdir(parents=True, exist_ok=True)
    log = str(common.LOG_DIR / "sextant-launchd.log")
weekly = env.get("SEXTANT_WEEKLY") or str(common.tool("weekly-run") or "")
# A peer found in this copy's checkout is named in the job's (the main checkout's, from a worktree)
mine, job = os.path.dirname(os.path.dirname(self)) + os.sep, os.path.dirname(os.path.dirname(here)) + os.sep
if weekly.startswith(mine) and not env.get("SEXTANT_WEEKLY"):
    weekly = job + weekly[len(mine):]
if weekly:
    args = [weekly, "sextant", cwd]
else:  # aurora absent: the module's own runner (G29)
    args = ["/usr/bin/python3", os.path.join(here, "libexec", "sextant-run"), "run", cwd]
rc = common.tool("rc-hosts")
if rc:
    r = subprocess.run([sys.executable, str(rc), "--launcher", args[1] if args[0] == "/usr/bin/python3" else args[0]],
                       capture_output=True, text=True)
    if r.returncode == 0 and r.stdout.strip():
        args = [r.stdout.strip()] + args
plist = {"Label": label, "ProgramArguments": args,
         "StartCalendarInterval": {"Weekday": int(env.get("SEXTANT_WEEKDAY") or 1), "Hour": int(env.get("SEXTANT_HOUR") or 2), "Minute": 0},
         "StandardOutPath": log, "StandardErrorPath": log}
# A job does not inherit the installer's shell: the own runner needs claude on PATH; either carries
# the overrides that decided the core and the layer here, or the job would read another (aurora's
# install.sh carries the same). Aurora's weekly-run sets its own PATH.
e = {}
if not weekly:
    e["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:%s/.local/bin" % os.path.expanduser("~")
for k in ("REGATTA_CONFIG", "REGATTA_HOME", "ATLAS_LAYER", "ATLAS_VAULT"):
    if env.get(k):
        e[k] = env[k]
if e:
    plist["EnvironmentVariables"] = e
if out == "-":
    sys.stdout.buffer.write(plistlib.dumps(plist))
else:
    with open(out, "wb") as f:
        plistlib.dump(plist, f)
PY
}

case "${1:-}" in
  --plist) weekly_plist - ;;
  --schedule)
    if [ "${2:-}" = --dry-run ]; then
      weekly_plist - || exit 1
      echo "install.sh --schedule --dry-run: would write $wplist and load $wlabel — nothing written or loaded"
      exit 0
    fi
    [ -z "${2:-}" ] || { echo "usage: install.sh --schedule [--dry-run]" >&2; exit 2; }
    [ "$(uname)" = Darwin ] || [ -n "${SEXTANT_LAUNCHCTL:-}" ] || { echo "install.sh --schedule: macOS only (launchd)" >&2; exit 2; }
    if [ -e "$cfgdir/regatta/overlay" ] && [ -z "${SEXTANT_SCHEDULE_BESIDE_OVERLAY:-}" ]; then
      echo "install.sh --schedule: an overlay is installed here ($cfgdir/regatta/overlay): it schedules /sextant itself; not loading a second job" >&2
      exit 1
    fi
    # A host aurora/skip-hosts lists gets no job: the run would only log its skip each week
    sk=$(python3 "$self/libexec/sextant-run" run "${SEXTANT_CWD:-/}" --dry-run 2>/dev/null | grep '^skipped:' || true)
    [ -z "$sk" ] || { echo "install.sh --schedule: $sk — not loading the job (--unschedule removes one loaded before)" >&2; exit 1; }
    # A bootout kills a running job, and a /sextant killed mid-run leaves its worktrees half-written
    if "$wlc" print "gui/$(id -u)/$wlabel" 2>/dev/null | grep -q 'pid = '; then
      echo "install.sh --schedule: $wlabel is running right now — rerun when it is done" >&2; exit 1
    fi
    mkdir -p "$wla"
    weekly_plist "$wplist.tmp" || { rm -f "$wplist.tmp"; exit 1; }
    if command -v plutil >/dev/null 2>&1 && ! plutil -lint -s "$wplist.tmp"; then
      rm -f "$wplist.tmp"; echo "install.sh: the plist does not lint — nothing loaded" >&2; exit 1
    fi
    "$wlc" bootout "gui/$(id -u)/$wlabel" 2>/dev/null || true
    mv -f "$wplist.tmp" "$wplist"
    # bootout can return before the old job is gone: one retry, never a loop
    "$wlc" bootstrap "gui/$(id -u)" "$wplist" 2>/dev/null || { sleep 2; "$wlc" bootstrap "gui/$(id -u)" "$wplist"; }
    echo "sextant: scheduled $wlabel (weekly) — $wplist"
    ;;
  --unschedule)
    if "$wlc" print "gui/$(id -u)/$wlabel" 2>/dev/null | grep -q 'pid = '; then
      echo "install.sh --unschedule: $wlabel is running right now — rerun when it is done" >&2; exit 1
    fi
    "$wlc" bootout "gui/$(id -u)/$wlabel" 2>/dev/null || true
    rm -f "$wplist"
    echo "sextant: removed $wlabel"
    ;;
  --launcher)
    [ "$(uname)" = Darwin ] || { echo "install.sh --launcher: macOS only (launchd, TCC)" >&2; exit 2; }
    [ -f "$config" ] || { echo "install.sh --launcher: no config at $config — write one (the README), or set SPARKS_CONFIG" >&2; exit 1; }
    # The launcher passes no REGATTA_CONFIG to the job, so sparks under launchd reads the default dir
    [ "$cfgdir" = "$HOME/.config/regatta" ] || { echo "install.sh --launcher: REGATTA_CONFIG=$cfgdir — the job would read $HOME/.config/regatta instead; install with the default config dir" >&2; exit 2; }
    # Before the build: a failing --inboxes inside the plist's heredoc would escape set -e
    # (sparks' last-resort handler prints "sparks: <error>" and exits 0, so that line counts as a failure)
    inboxes=$(SPARKS_CONFIG="$config" python3 "$script" --inboxes) && [ -n "$inboxes" ] \
      && ! printf '%s\n' "$inboxes" | grep -q '^sparks: ' \
      || { echo "install.sh --launcher: sparks --inboxes failed or named no inbox — nothing built or loaded" >&2; exit 1; }
    build
    mkdir -p "$(dirname "$plist")" "$(dirname "$log")"
    plist_text > "$plist.tmp"
    plutil -lint -s "$plist.tmp" || { rm -f "$plist.tmp"; echo "install.sh: the plist does not lint — nothing loaded" >&2; exit 1; }
    launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
    mv -f "$plist.tmp" "$plist"
    # bootout can return before the old job is gone: one retry, never a loop
    launchctl bootstrap "gui/$(id -u)" "$plist" 2>/dev/null || { sleep 2; launchctl bootstrap "gui/$(id -u)" "$plist"; }
    echo "scheduled $label: an inbox changes, and every 15 min (log: $log)"
    ;;
  --check)
    rc=0
    python3 - "$here" <<'PY' || rc=1
import sys
sys.path.insert(0, sys.argv[1] + "/lib")
import find_core
sys.path.insert(0, find_core.hooks())
import common
print("core:       %s" % common.__file__)
for name, peer in (("knowledge-commit", "atlas: the vault commit"), ("publish", "lighthouse: the copy to Drive")):
    p = common.tool(name)
    print("%-11s %s" % (name.split("-")[0] + ":", p or "absent — %s is skipped, the notes still filed" % peer))
p = common.tool("weekly-run")
print("weekly:     %s" % ("aurora's %s runs /sextant" % p if p else
                          "aurora absent — the module's own runner (libexec/sextant-run) runs /sextant, starting no work"))
gone = [n for n in ("pickup", "dispatch", "keel") if not common.tool(n)]
print("launch:     %s" % ("%s absent — `soundings next` gives the owner's line instead (G27)" % ", ".join(gone) if gone
                          else "pickup, dispatch and keel found"))
PY
    if [ -f "$config" ]; then echo "config:     $config"; else echo "config:     MISSING ($config) — sparks says so and exits"; rc=1; fi
    if command -v "${WHISPER_BIN:-whisper-cli}" >/dev/null 2>&1; then echo "whisper:    $(command -v "${WHISPER_BIN:-whisper-cli}")"
    else echo "whisper:    absent — recordings wait; written notes are still filed"; fi
    if [ "$(uname)" = Darwin ]; then
      if [ -x "$bin" ] && [ "$(cat "$bin.source-sha256" 2>/dev/null)" = "$(want_stamp)" ]; then echo "launcher:   $bin (stamp current)"
      elif [ -x "$bin" ]; then echo "launcher:   $bin is stale — install.sh --launcher rebuilds it (and the grants go)"; rc=1
      else echo "launcher:   not built (install.sh --launcher)"; rc=1; fi
      if launchctl print "gui/$(id -u)/$label" >/dev/null 2>&1; then echo "job:        $label loaded"; else echo "job:        $label not loaded"; rc=1; fi
    fi
    # The weekly job is reported, never a failure: a Mac that does not run /sextant has none
    if "$wlc" print "gui/$(id -u)/$wlabel" >/dev/null 2>&1; then echo "schedule:   $wlabel loaded"
    elif [ -f "$wplist" ]; then echo "schedule:   $wplist written but not loaded"
    else echo "schedule:   off (install.sh --schedule)"; fi
    exit $rc
    ;;
  --remove)
    launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
    rm -f "$plist" "$bin" "$bin.source-sha256"
    echo "removed $label, its plist and $bin (the grants in System Settings are yours to remove)"
    ;;
  *) echo "usage: install.sh [--launcher | --check | --remove | --plist | --schedule [--dry-run] | --unschedule]" >&2; exit 2 ;;
esac
