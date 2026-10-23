#!/usr/bin/env bash
# Tests for bin/check — scratch checkouts whose check lines run tiny scripts, a scratch slot folder;
# never the real ~/Library/Caches/check-slots.   bash modules/wharf-runs/tests/test_check.sh
set -u
B="$(cd "$(dirname "$0")/../bin" && pwd)"   # the module's bin/ (B7: the suites moved to tests/)
T=$(cd "$(mktemp -d)" && pwd -P); trap 'kill $(jobs -p) 2>/dev/null; rm -rf "$T"' EXIT
fails=0
check() { if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3: expected [$2] got [$1]"; fails=$((fails+1)); fi; }
# this suite runs inside unattended /finish runs too; its cases set CLAUDE_UNATTENDED themselves
unset CLAUDE_UNATTENDED
export CHECK_SLOT_DIR="$T/slots" CHECK_LOGS="$T/logs" CHECK_SLOT_POLL=0.2 CHECK_SLOTS=1
# wait up to 10 s for a condition
until_() { local i; for i in $(seq 1 50); do eval "$1" && return 0; sleep 0.2; done; return 1; }

# a checkout: AGENTS.md's check line, then the scripts it runs
mk() {
  local d="$T/$1"; shift; mkdir -p "$d"
  printf '# x\n\n- check: `%s` — a description after the code\n' "$1" > "$d/AGENTS.md"
  cat > "$d/ok.sh" <<'EOF'
echo "ok ran in $PWD"
EOF
  cat > "$d/fail.sh" <<'EOF'
echo "about to fail" >&2; exit 3
EOF
  cat > "$d/third.sh" <<'EOF'
#!/usr/bin/env bash
echo "third $*"
EOF
  chmod +x "$d/third.sh"
  # turn.sh: records who ran when, in order, then holds for $HOLD seconds
  cat > "$d/turn.sh" <<'EOF'
echo "${WHO:-?} start" >> "$ORDER"; echo $$ > "$ORDER.$WHO.pid"; sleep "${HOLD:-1}"; echo "${WHO:-?} end" >> "$ORDER"
EOF
  echo "$d"
}

echo "summary form and exit codes"
A=$(mk a 'bash ok.sh && bash fail.sh && ./third.sh --flag')
o=$("$B/check" "$A" --out "$T/r1"); rc=$?
check "$rc" "1" "a failed script: exit 1"
check "$(echo "$o" | head -1)" "logs: $T/r1" "the log folder is the first line printed"
check "$(sed -n 1p "$T/r1/summary" | sed -E 's/^[0-2][0-9]:[0-5][0-9] rc=0 [0-9]+s bash ok\.sh$/FORM/')" "FORM" "a line: time, rc, seconds, command"
check "$(sed -n 2p "$T/r1/summary" | sed -E 's/^.* (rc=[0-9]+) [0-9]+s (.*)$/\1 \2/')" "rc=3 bash fail.sh" "the script's own exit code"
check "$(sed -n 3p "$T/r1/summary" | sed -E 's/^.* (rc=[0-9]+) [0-9]+s (.*)$/\1 \2/')" "rc=0 ./third.sh --flag" "a command with arguments, whole"
check "$(tail -1 "$T/r1/summary")" "DONE 2/3" "then DONE passed/total"
check "$(wc -l < "$T/r1/summary" | tr -d ' ')" "4" "one line per script, one DONE"
check "$(ls "$T/r1" | tr '\n' ' ')" "01-ok.sh.log 02-fail.sh.log 03-third.sh.log summary " "one log per script, in order"
check "$(cat "$T/r1/02-fail.sh.log")" "about to fail" "a log holds the script's stderr"
check "$(cat "$T/r1/01-ok.sh.log")" "ok ran in $(cd "$A" && pwd -P)" "scripts run in the checkout"
check "$(ls "$T/slots" | grep -c slot-)" "0" "the slot is given back"
G=$(mk g 'bash ok.sh && ./third.sh')
"$B/check" "$G" > "$T/g.out"; check "$?" "0" "every script passed: exit 0"
check "$(tail -1 "$T/g.out")" "DONE 2/2" "DONE on stdout too"
case "$(head -1 "$T/g.out")" in "logs: $T/logs/g-"*) r=default ;; *) r="$(head -1 "$T/g.out")" ;; esac
check "$r" "default" "default log folder: \$CHECK_LOGS/<checkout>-<stamp>-<pid>"
N=$(mk n 'x'); printf '# no line\n' > "$N/AGENTS.md"
"$B/check" "$N" > /dev/null 2>&1; check "$?" "2" "no check line: exit 2"
"$B/check" "$T/nowhere" > /dev/null 2>&1; check "$?" "2" "no such checkout: exit 2"
"$B/check" "$G" --bogus > /dev/null 2>&1; check "$?" "2" "an unknown option: exit 2"
"$B/check" "$G" --only > /dev/null 2>&1; check "$?" "2" "--only with no script: exit 2"
"$B/check" "$G" --only --out "$T/r0" > /dev/null 2>&1; check "$?" "2" "--only with no script, then --out: exit 2, nothing run"
check "$(cat "$T/r0/summary")" "REFUSED --only needs a script" "…and the summary says why, for a caller polling it"
P=$(mk p 'x'); printf '# x\n\n- check: run the suite by hand, then compare\n' > "$P/AGENTS.md"
"$B/check" "$P" > /dev/null 2>&1; check "$?" "2" "a prose check line: exit 2, never run"

echo "--only"
"$B/check" "$A" --only fail --out "$T/r2" > /dev/null; rc=$?
check "$rc" "1" "--only the failing one: exit 1"
check "$(cut -d' ' -f2,4- "$T/r2/summary" | tr '\n' '|')" "rc=3 bash fail.sh|0/1|" "only that script ran"
"$B/check" "$A" --only third.sh ok.sh --out "$T/r3" > /dev/null; rc=$?
check "$rc" "0" "--only two that pass: exit 0"
check "$(cut -d' ' -f4- "$T/r3/summary" | tr '\n' '|')" "bash ok.sh|./third.sh --flag||" "in the check line's order, not the arguments'"
check "$(tail -1 "$T/r3/summary")" "DONE 2/2" "DONE counts the subset"
"$B/check" "$A" --only ok nope > "$T/r4.out" 2>&1; rc=$?
check "$rc" "2" "--only a name not in the line: exit 2"
check "$(grep -c 'nope: not in the check line' "$T/r4.out")" "1" "…naming it"
check "$(grep -c '^logs:' "$T/r4.out")" "0" "…before anything runs"

echo "a stale slot is reclaimed"
mkdir -p "$T/slots/slot-1"; echo 999999 > "$T/slots/slot-1/pid"; echo "Thu Jan  1 00:00:00 1970" > "$T/slots/slot-1/start"
o=$("$B/check" "$G" 2>&1); rc=$?
check "$rc" "0" "a slot whose pid is dead: the run goes ahead"
check "$(echo "$o" | grep -c 'reclaimed slot-1 from pid 999999, no longer running')" "1" "…and says it reclaimed it"
check "$(echo "$o" | grep -c 'waiting')" "0" "…without waiting"
sleep 60 & lp=$!   # a live process of the test's own, never the runner (AGENTS.md: stub pids)
mkdir -p "$T/slots/slot-1"; echo $lp > "$T/slots/slot-1/pid"; echo "Thu Jan  1 00:00:00 1970" > "$T/slots/slot-1/start"
o=$("$B/check" "$G" 2>&1)
check "$(echo "$o" | grep -c "reclaimed slot-1 from pid $lp, no longer running")" "1" "a live pid that started at another time (reused) is not the holder"
# a ps that fails for the holder: live, not reclaimed (fail closed)
mkdir -p "$T/bin" "$T/slots/slot-1"; echo $lp > "$T/slots/slot-1/pid"; echo "Thu Jan  1 00:00:00 1970" > "$T/slots/slot-1/start"
printf '#!/bin/bash\ncase " $* " in *" %s "*) exit 1 ;; esac\nexec /bin/ps "$@"\n' "$lp" > "$T/bin/ps"; chmod +x "$T/bin/ps"
PATH="$T/bin:$PATH" "$B/check" "$G" > "$T/psfail.out" 2>&1 & pf=$!
until_ "grep -q waiting '$T/psfail.out'"; check "$?" "0" "a holder ps cannot read is waited for, not reclaimed"
kill $lp; wait $lp 2>/dev/null; wait $pf; check "$?" "0" "…and taken once it is gone"
check "$(grep -c 'from pid '"$lp"', no longer running' "$T/psfail.out")" "1" "…saying so once"
mkdir -p "$T/slots/slot-1"; touch -t 202001010000 "$T/slots/slot-1"
o=$("$B/check" "$G" 2>&1)
check "$(echo "$o" | grep -c 'reclaimed slot-1 from a holder that never wrote its pid, no longer running')" "1" "no pid, older than 2 min: a crash between mkdir and the write"
mkdir -p "$T/slots/slot-1"
"$B/check" "$G" > "$T/young.out" 2>&1 & y=$!
until_ "grep -q waiting '$T/young.out'"; check "$?" "0" "no pid, younger than 2 min: a holder still writing, waited for"
rmdir "$T/slots/slot-1"; wait $y; check "$?" "0" "…and taken once it goes"
"$B/check" "$G" > /dev/null; check "$(ls -A "$T/slots/queue" | wc -l | tr -d ' ')" "0" "no ticket left in the queue"

echo "a slot taken, the rest queued in turn"
Q=$(mk q 'bash turn.sh')
export ORDER="$T/order"; : > "$ORDER"
WHO=A HOLD=2 "$B/check" "$Q" > "$T/A.out" 2>&1 & pa=$!
until_ "[ -s '$T/slots/slot-1/pid' ]"
check "$(cat "$T/slots/slot-1/pid")" "$pa" "the slot holds the holder's pid"
check "$(cat "$T/slots/slot-1/checkout")" "$(cd "$Q" && pwd -P)" "…and its checkout"
WHO=B HOLD=0 "$B/check" "$Q" > "$T/B.out" 2>&1 & pb=$!
until_ "grep -q waiting '$T/B.out'"
WHO=C HOLD=0 "$B/check" "$Q" > "$T/C.out" 2>&1 & pc=$!
until_ "grep -q waiting '$T/C.out'"
check "$(grep -c "waiting for a slot — all 1 taken: pid $pa $(cd "$Q" && pwd -P) (since " "$T/B.out")" "1" "a waiter says it waits, and for whom"
check "$(grep -c '1 ahead in the queue' "$T/C.out")" "1" "the next one says how many are ahead"
wait $pa $pb $pc
check "$(tr '\n' ' ' < "$ORDER")" "A start A end B start B end C start C end " "one at a time, in order of arrival"
check "$(grep -c waiting "$T/B.out")" "1" "the wait is printed once"
check "$(tail -1 "$T/C.out")" "DONE 1/1" "the last in the queue still runs"
: > "$ORDER"
CHECK_SLOTS=2 WHO=A HOLD=3 "$B/check" "$Q" > "$T/A2.out" 2>&1 & pa=$!
CHECK_SLOTS=2 WHO=B HOLD=3 "$B/check" "$Q" > "$T/B2.out" 2>&1 & pb=$!
wait $pa $pb
check "$(cat "$T/A2.out" "$T/B2.out" | grep -c waiting)" "0" "two slots: two checks run together"
check "$(head -2 "$ORDER" | grep -c start)" "2" "…both started before either ended"

echo "killed"
: > "$ORDER"
WHO=K HOLD=30 "$B/check" "$Q" --out "$T/rk" > "$T/K.out" 2>&1 & pk=$!
until_ "[ -s '$ORDER.K.pid' ]"; sp=$(cat "$ORDER.K.pid")
kill -TERM $pk; wait $pk; rc=$?
check "$rc" "143" "SIGTERM: exit 143"
check "$(tail -1 "$T/rk/summary")" "INTERRUPTED 0/1 by SIGTERM" "the summary says it was interrupted, not failed"
until_ "! kill -0 $sp 2>/dev/null"; check "$?" "0" "the running script is stopped with it"
check "$(ls "$T/slots" | grep -c slot-)" "0" "the slot is given back"
WHO=K9 HOLD=30 "$B/check" "$Q" > /dev/null 2>&1 & pk=$!
until_ "[ -s '$ORDER.K9.pid' ]"; sp=$(cat "$ORDER.K9.pid")
kill -KILL $pk; wait $pk 2>/dev/null; pkill -P $sp 2>/dev/null; kill $sp 2>/dev/null
check "$(cat "$T/slots/slot-1/pid")" "$pk" "SIGKILL: the slot stays behind"
o=$(WHO=after HOLD=0 "$B/check" "$Q" 2>&1)
check "$(echo "$o" | grep -c "reclaimed slot-1 from pid $pk, no longer running")" "1" "…and the next check takes it over"

echo "unattended: the check line is main's, never the branch's"
P="$T/primary"; mkdir -p "$P"; cp "$G"/*.sh "$P/"
printf -- '- check: `bash ok.sh`\n' > "$P/AGENTS.md"
( cd "$P" && git init -q && git checkout -q -b main && git add -A \
  && git -c user.name=t -c user.email=t@t commit -qm init && git worktree add -q -b claude/x "$T/wtx" main ) > /dev/null 2>&1
printf -- '- check: `bash ok.sh && bash fail.sh`\n' > "$T/wtx/AGENTS.md"
"$B/check" "$T/wtx" --out "$T/u1" > "$T/u1.out" 2>&1; rc=$?
check "$rc:$(tail -1 "$T/u1/summary")" "1:DONE 1/2" "attended: the branch's own line, its new script with it"
check "$(head -1 "$T/u1.out" | cut -c1-6)" "logs: " "…and the log folder first, as before"
CLAUDE_UNATTENDED=dispatch "$B/check" "$T/wtx" --out "$T/u2" > "$T/u2.out" 2>&1; rc=$?
check "$rc:$(tail -1 "$T/u2/summary")" "3:DONE 1/1" "unattended: main's line, the branch's addition not run — exit 3"
check "$(grep '^UNRUN' "$T/u2/summary")" "UNRUN bash fail.sh" "…named UNRUN, before DONE"
check "$(head -1 "$T/u2.out")" "check: unattended — the check line from main, not this branch's" "…said on the first line"
check "$(sed -n 1p "$T/u2/summary" | cut -d' ' -f4-)" "bash ok.sh" "…run in the branch's worktree"
CLAUDE_UNATTENDED=dispatch "$B/check" "$T/wtx" --only fail > /dev/null 2>&1
check "$?" "2" "unattended --only a script main's line lacks: refused"
CLAUDE_UNATTENDED=dispatch "$B/check" "$G" --out "$T/u3" > "$T/u3.out" 2>&1; rc=$?
check "$rc:$(grep -c 'not a git checkout' "$T/u3.out")" "2:1" "unattended outside git: refused, nothing run"
check "$(cut -c1-8 "$T/u3/summary")" "REFUSED " "…written to the summary too"
# main gains a script after the branch forked: absent here, said, not a failure
printf 'echo new\n' > "$P/new.sh"; printf -- '- check: `bash ok.sh && bash new.sh`\n' > "$P/AGENTS.md"
( cd "$P" && git add -A && git -c user.name=t -c user.email=t@t commit -qm more ) > /dev/null 2>&1
CLAUDE_UNATTENDED=dispatch "$B/check" "$T/wtx" --out "$T/u5" > /dev/null 2>&1; rc=$?
check "$rc:$(tail -1 "$T/u5/summary")" "3:DONE 1/1" "a script main added since the fork: not run, not counted"
check "$(grep -c '^ABSENT bash new.sh' "$T/u5/summary")" "1" "…named ABSENT"

echo
[ "$fails" -eq 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
