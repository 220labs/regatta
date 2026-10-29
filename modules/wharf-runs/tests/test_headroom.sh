#!/usr/bin/env bash
# Tests for bin/headroom — the per-host limits, the judgement, and both readers: macOS's live (on a
# Mac) and Linux's from a stand-in /proc. Scratch HOME and config dir; nothing outside them is written.
#   bash modules/wharf-runs/tests/test_headroom.sh
set -u
unset HEADROOM_SAMPLE HEADROOM_HOST HEADROOM_OS HEADROOM_PROC DISPATCH_HOST
B="$(cd "$(dirname "$0")/../bin" && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
. "$(cd "$(dirname "$0")" && pwd)/config_fixture.sh"; fixture_config "$T/config"
unset HEADROOM_SAMPLE   # the fixture's calm reading is for the other suites; these cases set their own
export HOME="$T/home"; mkdir -p "$HOME"
fails=0
check() { if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3: expected [$2] got [$1]"; fails=$((fails+1)); fi; }
has()   { if printf '%s' "$1" | grep -qF -- "$2"; then echo "  ok   $3"; else echo "  FAIL $3: missing [$2] in [$1]"; fails=$((fails+1)); fi; }
hr() { "$B/headroom" "$@" 2>&1; }

echo "== limits: none set is the neutral default"
out=$(HEADROOM_HOST=a HEADROOM_SAMPLE="50 3 10" hr); check "$?" "0" "room under the default"
has "$out" "default (no wharf-runs/headroom)" "  naming where the limits came from"
out=$(HEADROOM_HOST=a HEADROOM_SAMPLE="9 0 0" hr); check "$?" "3" "under the default's 10 % free: no room (exit 3, never Python's own 1)"
has "$out" "no room: 9 % free, under 10 %" "  saying which"
out=$(HEADROOM_HOST=a HEADROOM_SAMPLE="50 99 0" hr); check "$?" "0" "the default has no swap rule"

echo "== limits: per host, then *, then the default"
mkdir -p "$T/config/wharf-runs"
printf '%s\n' "Busy :avail=5, swap = 12,rate=60" "calm:avail=25,swap=6,rate=15" "*:avail=15" > "$T/config/wharf-runs/headroom"
out=$(HEADROOM_HOST=busy HEADROOM_SAMPLE="8 11 50" hr); check "$?" "0" "a host loaded to its own line still has room (its name and rules read past case and spaces)"
has "$out" "wharf-runs/headroom busy:" "  read from its own line"
out=$(HEADROOM_HOST=calm HEADROOM_SAMPLE="8 11 50" hr); check "$?" "3" "the same reading on a stricter host: no room"
has "$out" "8 % free, under 25 %; 11 GB swap, over 6 GB; 50 MB/s swapping, over 15 MB/s" "  every rule it breaks, in order"
out=$(HEADROOM_HOST=other HEADROOM_SAMPLE="14 40 900" hr); check "$?" "3" "a host without a line takes *:"
has "$out" "wharf-runs/headroom *:" "  saying so"
out=$(HEADROOM_HOST=other HEADROOM_SAMPLE="16 40 900" hr); check "$?" "0" "  and only the rules * names"
echo "== --floor: the force's line (dispatch-queue S4, D2-A)"
printf '%s\n' "calm:avail=25,swap=6,rate=15" "bare:rate=15" > "$T/config/wharf-runs/headroom"
out=$(HEADROOM_HOST=calm HEADROOM_SAMPLE="7 1 2" hr --floor 5); check "$?" "0" "7 % free passes the force's 5 % floor where the host's line asks 25 %"
has "$out" "floor 5 %" "  saying the floor read it"
out=$(HEADROOM_HOST=calm HEADROOM_SAMPLE="4 1 2" hr --floor 5); check "$?" "3" "under the floor: no room, force or not"
out=$(HEADROOM_HOST=calm HEADROOM_SAMPLE="50 9 2" hr --floor 5); check "$?" "3" "  the swap rule kept"
out=$(HEADROOM_HOST=calm HEADROOM_SAMPLE="50 1 40" hr --floor 5); check "$?" "3" "  the rate rule kept: a force run never passes a host that swaps"
out=$(HEADROOM_HOST=bare HEADROOM_SAMPLE="2 1 2" hr --floor 5); check "$?" "0" "a line with no avail rule gains none: the floor only lowers a limit"
out=$(HEADROOM_HOST=calm HEADROOM_SAMPLE="7 1 2" hr --floor 500); check "$?" "2" "a floor that is no percentage is no reading"
printf '%s\n' "busy:avail=5,swp=12" > "$T/config/wharf-runs/headroom"
out=$(HEADROOM_HOST=busy HEADROOM_SAMPLE="50 0 0" hr); check "$?" "2" "a rule it cannot read is no reading, never a dropped rule"
has "$out" "unknown rule 'swp'" "  naming it"
printf '%s\n' "busy avail=5" > "$T/config/wharf-runs/headroom"
out=$(HEADROOM_HOST=busy HEADROOM_SAMPLE="50 0 0" hr); check "$?" "2" "a line without <host>: is no reading, never skipped"
printf '\377\n' > "$T/config/wharf-runs/headroom"
out=$(HEADROOM_HOST=busy HEADROOM_SAMPLE="50 0 0" hr); check "$?" "2" "a file it cannot read is no reading, never the default"
has "$out" "not UTF-8" "  saying why"
printf '%s\n' "elsewhere:avail=90" > "$T/config/wharf-runs/headroom"
out=$(HEADROOM_HOST=busy HEADROOM_SAMPLE="50 0 0" hr); check "$?" "0" "a file without this host or *: the default"
rm "$T/config/wharf-runs/headroom"

echo "== the log: one row per check, none with --no-log"
L="$HOME/Library/Logs/claude-weekly/headroom.jsonl"; n0=$(wc -l < "$L" | tr -d ' ')
HEADROOM_HOST=a HEADROOM_SAMPLE="9 1 2" "$B/headroom" >/dev/null
check "$(( $(wc -l < "$L") - n0 ))" "1" "a row per check"
check "$(tail -1 "$L" | python3 -c 'import json,sys; r=json.load(sys.stdin); print(r["host"], r["room"], r["sample"]["avail"])')" "a False 9.0" "  holding the host, the verdict and the sample"
HEADROOM_HOST=a HEADROOM_SAMPLE="9 1 2" "$B/headroom" --no-log >/dev/null
check "$(( $(wc -l < "$L") - n0 ))" "1" "  and none with --no-log"

echo "== Linux: /proc/meminfo and /proc/vmstat"
P="$T/proc"; mkdir -p "$P"
printf '%s\n' "MemTotal:       16000000 kB" "MemFree:          500000 kB" "MemAvailable:    2400000 kB" "SwapTotal:       4194304 kB" "SwapFree:        3145728 kB" "HugePages_Total:       0" > "$P/meminfo"
printf '%s\n' "nr_free_pages 125000" "pswpin 1000" "pswpout 2000" > "$P/vmstat"
out=$(HEADROOM_OS=Linux HEADROOM_PROC="$P" HEADROOM_HOST=vm "$B/headroom" --json --no-log)
check "$(printf '%s' "$out" | python3 -c 'import json,sys; s=json.load(sys.stdin)["sample"]; print(s["avail"], s["swap"], s["rate"])')" "15.0 1.0 0.0" \
  "MemAvailable/MemTotal as % free, SwapTotal-SwapFree in GB, an idle swap rate"
# the counters move during the 2 s sample: a writer bumps them halfway
# the counters move during a 6 s sample: a writer bumps them 2 s in, well clear of start-up on a loaded Mac
( sleep 2; printf '%s\n' "nr_free_pages 125000" "pswpin 3560" "pswpout 2000" > "$P/vmstat" ) &
out=$(HEADROOM_SAMPLE_S=6 HEADROOM_OS=Linux HEADROOM_PROC="$P" HEADROOM_HOST=vm "$B/headroom" --json --no-log); wait
check "$(printf '%s' "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["sample"]["rate"])')" \
  "$(python3 -c 'import os; print(round(2560 * os.sysconf("SC_PAGE_SIZE") / 1024**2 / 6, 1))')" "  pages swapped in the sample, as MB/s at the host's page size"
printf '%s\n' "MemTotal:       16000000 kB" > "$P/meminfo"
HEADROOM_OS=Linux HEADROOM_PROC="$P" HEADROOM_HOST=vm "$B/headroom" --no-log >/dev/null 2>&1; check "$?" "2" "  a meminfo without MemAvailable: no reading (exit 2)"
printf '%s\n' "MemTotal:              0 kB" "MemAvailable:          0 kB" > "$P/meminfo"
HEADROOM_OS=Linux HEADROOM_PROC="$P" HEADROOM_HOST=vm "$B/headroom" --no-log >/dev/null 2>&1; check "$?" "2" "  a crash inside the reading (MemTotal 0): no reading, never a refusal (review, 2026-10-22)"

echo "== macOS: the live reading"
if [ "$(uname)" = Darwin ]; then
  out=$(HEADROOM_HOST=mac "$B/headroom" --json --no-log)
  check "$(printf '%s' "$out" | python3 -c 'import json,sys; r=json.load(sys.stdin); s=r["sample"]; print(r["room"] is not None and 0 <= s["avail"] <= 100 and s["swap"] >= 0 and s["rate"] >= 0)')" "True" \
    "kern.memorystatus_level, vm.swapusage and vm_stat's swap counters read as numbers in range"
else
  echo "  --   skipped: not macOS"
fi

[ "$fails" = 0 ] && echo "test_headroom: all passed" || echo "test_headroom: $fails FAILED"
[ "$fails" = 0 ]
