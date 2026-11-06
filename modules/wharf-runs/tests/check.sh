#!/usr/bin/env bash
# wharf-runs' check: every tool's suite (the core's check compiles this module's Python).
# Scratch paths only; no Orca, no network, no real launchd. A suite this checkout lacks is skipped
# with a line (a trimmed copy; every suite is public since the scrub, 2026-10-22).
#   bash modules/wharf-runs/tests/check.sh     (the suites in three lanes at once; timings in CHANGELOG)
#   WHARF_RUNS_CHECK_LANES=1 bash …            (one after another, as before 2026-10-27: to bisect a
#                                               flake, or on a Mac too loaded for three at once)
#   bash … --list-shards                      (the partition, without running anything)
#   bash … --shard pickup                     (one group: a share's job; off macOS still LINUX_OK's suites only)
#   WHARF_RUNS_LINUX_PROOF=1 bash … --shard queue   (a Linux proof run: the group's every suite, unproven ones too)
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
# The line names this script once (a Mac's whole line runs it in lanes); .github/ci/share.sh reads
# --list-shards and runs each shard as an id of its own: check-linux the eight on the Linux list, the Mac
# share queue and macos (`share.sh whole` runs this script once, in lanes). Off macOS a shard runs LINUX_OK's suites only, as the default does (the twin's
# `check (the rest)` runs queue on ubuntu); WHARF_RUNS_LINUX_PROOF=1 runs the rest too, to prove one.
SUITES="orca-host orca-serve-agent node peers cold_prompt test_check test_check_ci test_build_review test_builder_coin test_builder_host test_orca_runtime test_headroom test_harness test_agy test_vendor test_hail test_clock test_rc_hosts test_berth test_autofinish_run test_lander test_pickup test_seed_from test_autofinish test_dispatch test_handover test_queue test_priority test_after test_rank test_finish_queue test_finish_capable test_systemd test_kick_socket test_wharf test_shards"
SHARDS="core autofinish dispatch pickup jobs landing wharf queue tools macos"
shard_suites() {
  case "$1" in
    core) echo "orca-host orca-serve-agent test_orca_runtime test_headroom test_systemd test_builder_coin test_builder_host test_kick_socket test_agy test_shards" ;;
    autofinish) echo "test_autofinish" ;;
    dispatch) echo "test_dispatch" ;;
    pickup) echo "test_pickup test_seed_from" ;;
    jobs) echo "node test_hail test_clock test_berth" ;;
    landing) echo "test_autofinish_run" ;;
    wharf) echo "test_wharf" ;;
    queue) echo "test_queue test_priority test_after test_rank test_finish_queue test_finish_capable test_lander" ;;
    tools) echo "peers cold_prompt test_check test_build_review" ;;
    macos) echo "test_harness test_rc_hosts test_check_ci test_vendor test_handover" ;;
    *) return 2 ;;
  esac
}
# Fail a misspelled or duplicated entry before it can silently lose coverage in the jobs.
partition=""
for shard in $SHARDS; do partition="$partition $(shard_suites "$shard")"; done
for s in $SUITES $partition; do
  count=0
  for entry in $partition; do [ "$entry" != "$s" ] || count=$((count + 1)); done
  case " $SUITES " in *" $s "*) ;; *) count=0 ;; esac
  [ "$count" = 1 ] || { echo "FAIL shard partition: $s occurs $count times"; exit 2; }
done
selected=""
case "$#:${1:-}" in
  0:) ;;
  1:--list-shards)
    for shard in $SHARDS; do printf '%s\t%s\n' "$shard" "$(shard_suites "$shard")"; done
    exit 0 ;;
  2:--shard)
    selected="$2"
    SUITES="$(shard_suites "$selected")" || { echo "FAIL unknown shard: $selected"; exit 2; } ;;
  *) echo "usage: $0 [--list-shards | --shard NAME]" >&2; exit 2 ;;
esac
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
# check_scope.py reads paths, so it would skip this module's suites on a change to a peer its tools resolve by
# name (common.tool) and no file spells out: modules/lighthouse (account, hosts), modules/plumb (usage-report,
# tier_check.py), modules/aurora (scope-pass), modules/atlas (knowledge-commit), modules/helloworld. Named here
# for the macOS share's scope; test_check.sh holds the list to it.
# Off macOS (CI's ubuntu) only the suites proven there run: the eight Linux shards' (test_kick_socket's
# stub-server cases where python3 has websockets 14.0+, which .github/ci/linux-tools.sh unpacks from
# PyPI's checked wheel; test_agy, written portable, agy-road, and test_orca_runtime, the Orca adapter's road per
# OS, yard-orca-serve, in core). A suite joins this list only after
# a Linux pass (WHARF_RUNS_LINUX_PROOF=1), never by skipping what it checks, and in the change that puts its
# shard on .github/ci/linux-ids: a listed shard whose suite is off this list runs nothing there and passes
# (test_shards holds the two together).
# test_harness stays on macOS: its research cases exercise the real sandbox-exec seatbelt.
# test_rc_hosts stays on macOS: it compiles and codesigns the overlay's TCC launcher.
# test_check_ci (main's, merged after the shard split) waits in `macos` for its Linux proof; then `tools` and this list.
# test_vendor also waits in `macos` until its Linux proof.
# test_handover (landing-no-ask, rebased onto the split) waits in `macos` for its Linux proof the same way.
# Proven on GitHub's ubuntu by #500's check-linux (2026-11-05, run 41984282738): every shard but `queue`, whose
# finish-queue cases read the Mac's claim and memory floors (4 failed); `queue` and `macos` stay on the Macs.
# `pickup` (test_pickup, test_seed_from) passed there too, failed 19 cases on the self-hosted runners' old image
# (no lsof, which pickup's `ide_windows` runs) and is back since the runners were reinstalled (runner-lsof, 2026-11-06).
LINUX_OK=" orca-host orca-serve-agent test_autofinish test_headroom test_systemd test_builder_coin test_kick_socket test_builder_host test_shards test_dispatch node test_hail test_clock test_berth test_autofinish_run test_wharf peers cold_prompt test_check test_build_review test_agy test_orca_runtime test_pickup test_seed_from "
# Off macOS the rest is left to a Mac, said per suite. WHARF_RUNS_SKIP_LINUX_OK=1 runs only the rest on
# a Mac, for a hand run: no share sets it since wharf-runs-linux, which runs shards instead.
LEFT_TO_MAC="not run on this host (a macOS run of this line covers it; where a pull request's check runs on a Mac, pr merge waits for it)"
# Lane 2 is named; lane 3 is every other suite. A suite added to SUITES also goes in one shard, or the
# partition check above refuses every run.
# Balanced on measured passes (the build Mac, load 8–12, 2026-10-27; seconds): test_dispatch 413 alone; lane 2
# 669 (harness 64, pickup 335, autofinish 270); lane 3 830, test_autofinish_run 335 and test_wharf 244
# the most of it (test_clock, 67, is the next to move). Move a suite when a lane runs long.
LANE2="test_harness test_pickup test_autofinish"
for s in $LANE2; do   # a name only here would run in lane 2 and silently drop out of modes 1 and 2
  [ -z "$selected" ] || break
  case " $SUITES " in *" $s "*) ;; *) echo "  FAIL LANE2 names $s, which is not in SUITES"; exit 2;; esac
done

run_suite() {   # <suite>: its header and the suite, or the line saying why it is skipped; its seconds
  local s=$1 t r
  echo "== $s"
  if [ ! -f "$D/$s.sh" ]; then echo "  --   skipped: not in this checkout"; return 0; fi
  if [ "$(uname)" != Darwin ]; then
    case "$s" in
      test_harness) echo "  --   skipped: macOS sandbox-exec research cases"; return 0 ;;
      test_rc_hosts) echo "  --   skipped: macOS codesign and TCC launcher"; return 0 ;;
    esac
    if [ -z "${WHARF_RUNS_LINUX_PROOF:-}" ] && [ "${LINUX_OK#* $s }" = "$LINUX_OK" ]; then echo "  --   skipped: Linux proof pending, $LEFT_TO_MAC"; return 0; fi
  fi
  # a hand run's complement of the Linux list (no share sets it since wharf-runs-linux)
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
[ -z "$selected" ] || n=1   # one shard, one lane: a Linux job has its own VM, and `share.sh whole` runs the plain script
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
# Each lane's log is printed with cat, which stops at the first full pipe when the pipe is O_NONBLOCK (the
# CLI leaves CI's step pipe so): every lane printout of regatta#388's runs stopped near 64 KiB, the failing
# case unprinted, and cat's own EAGAIN line lost with it. Blocking again before the lanes print, whoever set it
# (docs/runner-interference-2026-11-02.md; check.yml's claude wrapper is the other half). Stderr is
# cleared as fd 3, a copy of it: a plain 2>/dev/null would clear /dev/null's flag and leave the pipe's.
python3 -c 'import fcntl, os; [fcntl.fcntl(f, fcntl.F_SETFL, fcntl.fcntl(f, fcntl.F_GETFL) & ~os.O_NONBLOCK) for f in (1, 3)]' 3>&2 2>/dev/null
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
  if grep -q -e 'bad substitution' -e 'command not found' "$log"; then
    echo "  FAIL lane $((i + 1))'s log shows a shell error, so a case may not have run:"
    grep -n -e 'bad substitution' -e 'command not found' "$log" | sed 's/^/    /'
    rc=1
  fi
done
echo "== lanes: all ended in $(( $(date +%s) - t0 )) s"
if [ "$(uname)" != Darwin ] && [ -z "${WHARF_RUNS_LINUX_PROOF:-}" ]; then
  left=""
  for s in $SUITES; do [ -f "$D/$s.sh" ] && [ "${LINUX_OK#* $s }" = "$LINUX_OK" ] && left="$left $s"; done
  [ -z "$left" ] || echo "== macOS only, $LEFT_TO_MAC:$left"
fi
exit $rc
