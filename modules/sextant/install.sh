#!/bin/sh
# sextant's shell and launchd face. Today the module is Sparks, its ideas intake (the README);
# the strategy half adds its own schedule here later.
#
#   install.sh --launcher   build the Sparks launcher from launcher.c.in (only when its stamp
#                           changed), write its launchd job and load it; says which two grants
#                           the build needs (Full Disk Access, Automation for Notes)
#   install.sh --check      what the intake needs, each on one line; exit 1 when the job cannot run
#   install.sh --remove     unload the job, remove its plist, the launcher and its stamp
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
here=$(cd "$(dirname "$0")" && pwd)
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

case "${1:-}" in
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
    exit $rc
    ;;
  --remove)
    launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
    rm -f "$plist" "$bin" "$bin.source-sha256"
    echo "removed $label, its plist and $bin (the grants in System Settings are yours to remove)"
    ;;
  *) echo "usage: install.sh [--launcher | --check | --remove]" >&2; exit 2 ;;
esac
