#!/usr/bin/env bash
# wharf-runs' check: every tool's suite (the core's check compiles this module's Python).
# Scratch paths only; no Orca, no network, no real launchd. A suite this checkout lacks is skipped
# with a line (a trimmed copy; every suite is public since the scrub, 2026-10-22).
#   bash modules/wharf-runs/tests/check.sh     (the suites in three lanes at once; timings in CHANGELOG)
#   WHARF_RUNS_CHECK_LANES=1 bash …            (one after another, as before 2026-10-27: to bisect a
#                                               flake, or on a Mac too loaded for three at once)
# Lanes (docs/wharf-runs-suite-time-2026-10-23.md D1-A): the suites are bound by process and git work,
# not by sleeps, so the wall is cut by running them side by side, each in its own scratch dir (one
# mktemp each; none writes a fixed path another reads). test_dispatch runs alone in lane 1 because it is
# the longest single suite (it still shares the load: its stuck-hook case failed once with three suite
# groups at once, a start-up race the lanes do not remove). Each lane writes to its own log, printed
# whole, in lane order, as each is reached (a lane that ends early waits for the ones before it); the exit fails if any lane
# fails or its log shows a shell error that fails nothing by itself (AGENTS.md Traps). The lanes stay in
# this script's process group, so bin/check's signal to the group stops them too: never `set -m` here.
set -u
D="$(cd "$(dirname "$0")" && pwd)"
M="$(dirname "$D")"
rc=0
echo "== C1: every bin/ name is free on a stock PATH"
for f in "$M"/bin/*; do
  [ -f "$f" ] || continue
  n=$(basename "$f")
  case "$n" in *.py) continue;; esac
  if PATH=/usr/bin:/bin:/usr/sbin:/sbin command -v "$n" >/dev/null 2>&1; then
    echo "  FAIL bin/$n is shadowed by $(PATH=/usr/bin:/bin:/usr/sbin:/sbin command -v "$n")"; rc=1
  fi
done
echo "== lib/core_path.py is wharf's, byte for byte (one finder, two copies: a process loads both modules)"
if [ -f "$M/lib/core_path.py" ] && [ -f "$M/../wharf/lib/core_path.py" ]; then
  cmp -s "$M/lib/core_path.py" "$M/../wharf/lib/core_path.py" && echo "  ok   identical" || { echo "  FAIL lib/core_path.py differs from wharf's"; rc=1; }
else
  echo "  --   skipped: no lib/core_path.py here, or no wharf beside it"
fi
# Off macOS (CI's ubuntu) only the suites proven there run: orca-host's, orca-serve-agent's (a dry run), test_systemd (the
# Linux launcher, stood in), and test_autofinish (made
# portable and run on ubuntu in the overlay's CI since 2026-10-07). The rest read launchd, plutil,
# caffeinate or BSD date; a suite joins the Linux list once it passes there, never by skipping
# what it checks.
LINUX_OK=" orca-host orca-serve-agent test_autofinish test_headroom test_systemd "
SUITES="orca-host orca-serve-agent node peers cold_prompt test_check test_build_review test_headroom test_harness test_hail test_clock test_rc_hosts test_berth test_autofinish_run test_pickup test_seed_from test_autofinish test_dispatch test_queue test_priority test_after test_systemd test_wharf"
# Lane 2 is named; lane 3 is every other suite, so a suite added to SUITES lands there by itself.
# Balanced on measured passes (the build Mac, load 8–12, 2026-10-27; seconds): test_dispatch 413 alone; lane 2
# 669 (harness 64, pickup 335, autofinish 270); lane 3 830, test_autofinish_run 335 and test_wharf 244
# the most of it (test_clock, 67, is the next to move). Move a suite when a lane runs long.
LANE2="test_harness test_pickup test_autofinish"
for s in $LANE2; do   # a name only here would run in lane 2 and silently drop out of modes 1 and 2
  case " $SUITES " in *" $s "*) ;; *) echo "  FAIL LANE2 names $s, which is not in SUITES"; exit 2;; esac
done

run_suite() {   # <suite>: its header and the suite, or the line saying why it is skipped; its seconds
  local s=$1 t r
  echo "== $s"
  if [ ! -f "$D/$s.sh" ]; then echo "  --   skipped: not in this checkout"; return 0; fi
  if [ "$(uname)" != Darwin ] && [ "${LINUX_OK#* $s }" = "$LINUX_OK" ]; then echo "  --   skipped: macOS only (runs in /finish)"; return 0; fi
  # the PR check's macOS share (.circleci/share.sh): CircleCI's Linux job ran these already
  if [ -n "${WHARF_RUNS_SKIP_LINUX_OK:-}" ] && [ "${LINUX_OK#* $s }" != "$LINUX_OK" ]; then echo "  --   skipped: run on Linux (the macOS share)"; return 0; fi
  t=$(date +%s); bash "$D/$s.sh"; r=$?
  echo "  ($s: $(( $(date +%s) - t )) s, exit $r)"
  return $r
}
run_lane() {   # <end file> <suite>…: the suites in the order given, then the lane's end time; fails if any suite does
  local end=$1 s r=0
  shift
  for s in "$@"; do run_suite "$s" || r=1; done
  date +%s > "$end"
  return $r
}
without() {   # <words> <drop>: the words of the first not in the second, in order
  local w out=""
  for w in $1; do case " $2 " in *" $w "*) ;; *) out="$out $w";; esac; done
  echo $out
}

n="${WHARF_RUNS_CHECK_LANES:-3}"
case "$n" in
  1) lanes=("$SUITES") ;;
  2) lanes=("test_dispatch" "$(without "$SUITES" test_dispatch)") ;;
  3) lanes=("test_dispatch" "$LANE2" "$(without "$SUITES" "test_dispatch $LANE2")") ;;
  *) echo "  FAIL WHARF_RUNS_CHECK_LANES must be 1, 2 or 3 (got $n)"; exit 2 ;;
esac
logs=$(mktemp -d "${TMPDIR:-/tmp}/wharf-runs-lanes.XXXXXX")
pids=()
tree() {   # <pid>: it and every descendant, parents first
  local c
  echo "$1"
  for c in $(pgrep -P "$1" 2>/dev/null); do tree "$c"; done
}
stop_lanes() {   # <exit code>: TERM each running lane's whole tree, so no suite outlives the check; show the logs so far
  local i f
  for i in "${!pids[@]}"; do   # an ended lane's pid may be reused by now: its end file says so
    [ -f "$logs/lane-$((i + 1)).end" ] || kill -TERM $(tree "${pids[$i]}") 2>/dev/null
  done
  for f in "$logs"/lane-*.log; do [ -f "$f" ] && { echo "== $(basename "$f") (interrupted)"; cat "$f"; }; done
  exit "$1"
}
trap 'rm -rf "$logs"' EXIT
trap 'stop_lanes 130' INT; trap 'stop_lanes 143' TERM; trap 'stop_lanes 129' HUP
echo "== lanes: ${#lanes[@]} at once, each printed whole, in order"
t0=$(date +%s)
for i in "${!lanes[@]}"; do
  # shellcheck disable=SC2086  # word-split on purpose: a lane is a list of names
  run_lane "$logs/lane-$((i + 1)).end" ${lanes[$i]} > "$logs/lane-$((i + 1)).log" 2>&1 &
  pids+=($!)
done
for i in "${!lanes[@]}"; do
  wait "${pids[$i]}"; lrc=$?
  log="$logs/lane-$((i + 1)).log"
  end=$(cat "$logs/lane-$((i + 1)).end" 2>/dev/null || date +%s)
  echo "== lane $((i + 1)) of ${#lanes[@]}: ${lanes[$i]} — exit $lrc, $(( end - t0 )) s"
  cat "$log"
  [ "$lrc" = 0 ] || rc=1
  # a case that never parsed, or a helper never defined, prints this and fails nothing (AGENTS.md Traps)
  if [ "$(uname)" = Darwin ] && grep -q -e 'bad substitution' -e 'command not found' "$log"; then
    echo "  FAIL lane $((i + 1))'s log shows a shell error, so a case may not have run:"
    grep -n -e 'bad substitution' -e 'command not found' "$log" | sed 's/^/    /'
    rc=1
  fi
done
echo "== lanes: all ended in $(( $(date +%s) - t0 )) s"
exit $rc
