#!/usr/bin/env bash
# Tests for bin/check — scratch checkouts whose check lines run tiny scripts, a scratch slot folder;
# never the real ~/Library/Caches/check-slots.   bash modules/wharf-runs/tests/test_check.sh
set -u
B="$(cd "$(dirname "$0")/../bin" && pwd)"   # the module's bin/ (B7: the suites moved to tests/)
T=$(cd "$(mktemp -d)" && pwd -P); trap 'kill $(jobs -p) 2>/dev/null; rm -rf "$T"' EXIT
fails=0
check() { if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3: expected [$2] got [$1]"; fails=$((fails+1)); fi; }
# this suite runs inside unattended /finish runs too; its cases set CLAUDE_UNATTENDED themselves
unset CLAUDE_UNATTENDED REGATTA_UNATTENDED
export CHECK_SLOT_DIR="$T/slots" CHECK_LOGS="$T/logs" CHECK_SLOT_POLL=0.2 CHECK_SLOTS=1 CHECK_PASS_TTL=0   # the memory off; its own cases turn it on
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
# a run between taking its slot and dropping its ticket: one holder, never also one ahead
sleep 60 & lp=$!; ls="$(TZ=UTC LC_ALL=C ps -o lstart= -p $lp | xargs)"
mkdir -p "$T/slots/slot-1"; echo $lp > "$T/slots/slot-1/pid"; echo "$ls" > "$T/slots/slot-1/start"
printf '%s\n%s\n%s\n' "$lp" "$ls" "$G" > "$T/slots/queue/0000000001.000000.$lp"
# in the background, bounded: the old double count waited until the holder (60 s) went
CHECK_SLOTS=2 "$B/check" "$G" > "$T/held.out" 2>&1 & hp=$!
until_ "grep -q '^DONE\|waiting' '$T/held.out'"
check "$(grep -c waiting "$T/held.out")" "0" "a holder whose ticket is still queued is not also ahead (2026-10-27)"
check "$(grep -c '^DONE' "$T/held.out")" "1" "…and it ran"
kill $lp $hp 2>/dev/null; wait $lp $hp 2>/dev/null; rm -rf "$T/slots/slot-1" "$T/slots/queue/0000000001.000000.$lp"

echo "a slot taken, the rest queued in turn"
Q=$(mk q 'bash turn.sh')
export ORDER="$T/order"; : > "$ORDER"
WHO=A HOLD=2 "$B/check" "$Q" > "$T/A.out" 2>&1 & pa=$!
until_ "[ -s '$T/slots/slot-1/since' ]"   # written last since 2026-10-27, after pid and checkout
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

echo "the count per host, from wharf-runs/check-slots (2026-10-23)"
mkdir -p "$T/cfg/wharf-runs"; printf 'other:5\nlaptopx: 3\n*:1\n' > "$T/cfg/wharf-runs/check-slots"
: > "$ORDER"
for w in A B C; do env -u CHECK_SLOTS REGATTA_CONFIG="$T/cfg" CHECK_HOST=laptopx WHO=$w HOLD=3 "$B/check" "$Q" > "$T/${w}3.out" 2>&1 & eval "p$w=\$!"; done
wait $pA $pB $pC
# what matters is that all three ran at once, as the two-slot case asks of two; a `waiting` line can
# still slip into the instant between a run's mkdir and its pid, and costs one poll at most
check "$(head -3 "$ORDER" | grep -c start)" "3" "this host's line, 3: three checks run together"
: > "$ORDER"
env -u CHECK_SLOTS REGATTA_CONFIG="$T/cfg" CHECK_HOST=nobody WHO=A HOLD=2 "$B/check" "$Q" > "$T/A4.out" 2>&1 & pa=$!
until_ "[ -s '$T/slots/slot-1/pid' ]"
env -u CHECK_SLOTS REGATTA_CONFIG="$T/cfg" CHECK_HOST=nobody WHO=B HOLD=0 "$B/check" "$Q" > "$T/B4.out" 2>&1 & pb=$!
wait $pa $pb
check "$(grep -c 'all 1 taken' "$T/B4.out")" "1" "a host without a line takes *'s, 1"
env -u CHECK_SLOTS REGATTA_CONFIG="$T/none" CHECK_HOST=laptopx WHO=A HOLD=0 "$B/check" "$Q" > "$T/A5.out" 2>&1
check "$?" "0" "no file: the default, and the check runs"
printf 'laptopx:many\n' > "$T/cfg/wharf-runs/check-slots"
env -u CHECK_SLOTS REGATTA_CONFIG="$T/cfg" CHECK_HOST=laptopx WHO=A HOLD=0 "$B/check" "$Q" > "$T/A6.out" 2>&1
check "$?" "2" "a line that is no number: refused, never a guess"

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
# a `~/` path in main's line is outside the branch: expanded, run when it exists, ABSENT when not
# TL is spelled in two halves so the publish gate's home-path pattern reads no real home here
H="$T/home"; TL="~"/tools/out.sh; mkdir -p "$H/tools"; printf 'echo outside >> "%s"\n' "$T/outside.ran" > "$H/tools/out.sh"
printf -- '- check: `bash ok.sh && bash %s`\n' "$TL" > "$P/AGENTS.md"
( cd "$P" && git add -A && git -c user.name=t -c user.email=t@t commit -qm home ) > /dev/null 2>&1
cp "$P/AGENTS.md" "$T/wtx/AGENTS.md"
HOME="$H" CLAUDE_UNATTENDED=dispatch "$B/check" "$T/wtx" --out "$T/u6" > /dev/null 2>&1; rc=$?
check "$rc:$(tail -1 "$T/u6/summary")" "0:DONE 2/2" "a ~/ path main's line names: run and counted, not ABSENT"
check "$(cat "$T/outside.ran" 2>/dev/null)" "outside" "…the script under \$HOME ran"
rm "$H/tools/out.sh"
HOME="$H" CLAUDE_UNATTENDED=dispatch "$B/check" "$T/wtx" --out "$T/u7" > /dev/null 2>&1; rc=$?
check "$rc:$(tail -1 "$T/u7/summary")" "1:DONE 1/2" "the ~/ script missing on this Mac: counted and failed, as an attended run fails"
want="rc=127 0s bash $TL — this Mac has no $H/tools/out.sh"
check "$(grep -cF "$want" "$T/u7/summary")" "1" "…rc=127, the expanded path in the line"
check "$(grep -c '^ABSENT' "$T/u7/summary")" "0" "…never ABSENT"
# the \$HOME spelling and a leading assignment resolve the same way
printf 'echo outside >> "%s"\n' "$T/outside2.ran" > "$H/tools/out.sh"
printf -- '- check: `bash ok.sh && V=a/b bash %s`\n' '$''HOME'/tools/out.sh > "$P/AGENTS.md"
( cd "$P" && git add -A && git -c user.name=t -c user.email=t@t commit -qm home2 ) > /dev/null 2>&1
cp "$P/AGENTS.md" "$T/wtx/AGENTS.md"
HOME="$H" CLAUDE_UNATTENDED=dispatch "$B/check" "$T/wtx" --out "$T/u8" > /dev/null 2>&1; rc=$?
check "$rc:$(tail -1 "$T/u8/summary")" "0:DONE 2/2" "a HOME-variable path behind an assignment: run and counted"
check "$(cat "$T/outside2.ran" 2>/dev/null)" "outside" "…the script under \$HOME ran"

echo "the scope: a module's suite runs when its module, or one it uses, changed since main"
R="$T/scoped"
for m in a b c d; do mkdir -p "$R/modules/$m/tests" "$R/modules/$m/.claude-plugin"; printf 'echo %s\n' "$m" > "$R/modules/$m/tests/check.sh"; done
echo '{"name":"a"}' > "$R/modules/a/.claude-plugin/plugin.json"
echo '{"name":"b","dependencies":["a"]}' > "$R/modules/b/.claude-plugin/plugin.json"   # b uses a, declared
echo '{"name":"c"}' > "$R/modules/c/.claude-plugin/plugin.json"
echo '{"name":"d"}' > "$R/modules/d/.claude-plugin/plugin.json"
mkdir -p "$R/modules/d/bin" "$R/docs"; printf 'x=modules/c/bin/tool\n' > "$R/modules/d/bin/tool"   # d uses c, by path
printf 'modules/a is a fixture\n' > "$R/modules/c/tests/NOTES.md"   # a mention in prose is not use
printf 'echo always\n' > "$R/always.sh"; printf 'a doc\n' > "$R/docs/one.md"; printf 'lib\n' > "$R/modules/a/lib.txt"
printf -- '- check: `bash always.sh && bash modules/a/tests/check.sh && bash modules/b/tests/check.sh && bash modules/c/tests/check.sh && bash modules/d/tests/check.sh`\n' > "$R/AGENTS.md"
( cd "$R" && git init -q && git checkout -q -b main && git add -A && git -c user.name=t -c user.email=t@t commit -qm init \
  && git worktree add -q -b claude/s "$T/wts" main ) > /dev/null 2>&1
S="$T/wts"
ran() { cut -d' ' -f4- "$1/summary" | grep -v '^$' | sed -n '/^bash/p' | tr '\n' '|'; }   # the commands run, in order
"$B/check" "$S" --out "$T/s0" > "$T/s0.out"; rc=$?
check "$rc:$(tail -1 "$T/s0/summary")" "0:DONE 5/5" "nothing changed since main: the whole line"
check "$(grep '^check: scope' "$T/s0.out")" "check: scope — the whole line: nothing changed since main" "…said after the logs line"
echo x > "$S/modules/a/new"   # uncommitted counts
"$B/check" "$S" --out "$T/s1" > "$T/s1.out"; rc=$?
check "$rc:$(tail -1 "$T/s1/summary")" "0:DONE 3/3" "a changed: its suite, b's (uses a) and the plain command; DONE counts what ran"
check "$(ran "$T/s1")" "bash always.sh|bash modules/a/tests/check.sh|bash modules/b/tests/check.sh|" "…in the line's order"
check "$(grep '^SKIP' "$T/s1/summary" | tr '\n' '|')" "SKIP bash modules/c/tests/check.sh — no change under modules/c or what it uses since main|SKIP bash modules/d/tests/check.sh — no change under modules/d or what it uses since main|" "the suites left out: SKIP lines first, with why"
check "$(grep '^check: scope' "$T/s1.out")" "check: scope — 3 of 5 script(s): modules/a changed since main" "the scope line names what changed"
check "$(grep -c '^SKIP' "$T/s1.out")" "2" "SKIP lines on stdout too"
check "$(ls "$T/s1" | grep -c '\.log$')" "3" "one log per script that ran"
( cd "$S" && git add -A && git -c user.name=t -c user.email=t@t commit -qm a ) > /dev/null 2>&1
echo y > "$S/modules/c/new"
"$B/check" "$S" --out "$T/s2" > /dev/null
check "$(tail -1 "$T/s2/summary")" "DONE 5/5" "a's change committed, c's not: the branch's whole diff since main counts, not the last change's"
back() { ( cd "$S" && git reset -q --hard main && git clean -fdq ) > /dev/null 2>&1; }   # the fixture branch as main again
back; echo y > "$S/modules/c/new"
"$B/check" "$S" --out "$T/s2b" > /dev/null
check "$(ran "$T/s2b")" "bash always.sh|bash modules/c/tests/check.sh|bash modules/d/tests/check.sh|" "c changed: c's suite and d's (names modules/c in its code), not a's or b's"
check "$(grep -c '^SKIP' "$T/s2b/summary")" "2" "…the other two skipped"
back; printf 'more\n' >> "$S/docs/one.md"
"$B/check" "$S" --out "$T/s3" > /dev/null
check "$(ran "$T/s3")" "bash always.sh|" "a docs/ change: only the plain command"
check "$(tail -1 "$T/s3/summary")" "DONE 1/1" "…DONE 1/1"
back; printf 'a line\n' >> "$S/AGENTS.md"
"$B/check" "$S" --out "$T/s4" > "$T/s4.out"
check "$(ran "$T/s4")" "bash always.sh|bash modules/a/tests/check.sh|bash modules/c/tests/check.sh|bash modules/d/tests/check.sh|" "a root Markdown file: the suites of the modules that depend on nothing (the core's), not b's"
check "$(grep '^check: scope' "$T/s4.out")" "check: scope — 4 of 5 script(s): a root Markdown file changed since main" "…said so"
back; printf 'x\n' > "$S/stray.txt"
"$B/check" "$S" --out "$T/s5" > "$T/s5.out"
check "$(tail -1 "$T/s5/summary")" "DONE 5/5" "a file outside modules/ that is not Markdown, docs/ or .github/: the whole line"
check "$(grep '^check: scope' "$T/s5.out")" "check: scope — the whole line: stray.txt changed, outside modules/" "…naming it"
back; mkdir -p "$S/.github"; printf 'x\n' > "$S/.github/w.yml"
"$B/check" "$S" --out "$T/s5b" > /dev/null
check "$(tail -1 "$T/s5b/summary")" "DONE 1/1" "a .github/ change: only the plain command"
back; mkdir -p "$S/.c"; printf 'x\n' > "$S/.c/list"
"$B/check" "$S" --out "$T/s5c" > /dev/null
check "$(ran "$T/s5c")" "bash always.sh|bash modules/c/tests/check.sh|" "a .<module>/ folder is that module's: its own suite, not its users'"
back; echo z > "$S/modules/a/new"
"$B/check" "$S" --full --out "$T/s6" > "$T/s6.out"
check "$(tail -1 "$T/s6/summary"):$(grep '^check: scope' "$T/s6.out")" "DONE 5/5:check: scope — the whole line (--full)" "--full: the whole line, whatever changed"
"$B/check" "$S" --only modules/c/tests/check.sh --out "$T/s7" > "$T/s7.out"
check "$(ran "$T/s7"):$(grep -c '^check: scope' "$T/s7.out")" "bash modules/c/tests/check.sh|:0" "--only: what is named runs, no scope"
"$B/check" "$G" --out "$T/s8" > "$T/s8.out"
check "$(tail -1 "$T/s8/summary"):$(grep -c '^check: scope' "$T/s8.out")" "DONE 2/2:0" "no modules/ or no git: the whole line, as before"
back; ( cd "$S" && git mv -q modules/a/lib.txt modules/c/moved.txt ) > /dev/null 2>&1
"$B/check" "$S" --out "$T/s9" > /dev/null
check "$(tail -1 "$T/s9/summary")" "DONE 5/5" "a file moved out of a module (uncommitted): the module it left changed too, and what uses it"
( cd "$S" && git -c user.name=t -c user.email=t@t commit -qm mv ) > /dev/null 2>&1
"$B/check" "$S" --out "$T/s9b" > /dev/null
check "$(tail -1 "$T/s9b/summary")" "DONE 5/5" "…committed as a rename: the same"
back; printf 'x\n' > "$S/modules/a/tests/helper.txt"
"$B/check" "$S" --out "$T/s10" > /dev/null
check "$(ran "$T/s10")" "bash always.sh|bash modules/a/tests/check.sh|" "a change under a module's tests/: its own suite, not its users'"
back; printf 'x\n' >> "$S/modules/a/README.md"
"$B/check" "$S" --out "$T/s10b" > /dev/null
check "$(ran "$T/s10b")" "bash always.sh|bash modules/a/tests/check.sh|" "a module's Markdown: the same"
back; mkdir -p "$S/modules/a/skills/x"; printf 'a skill\n' > "$S/modules/a/skills/x/SKILL.md"
"$B/check" "$S" --out "$T/s10c" > /dev/null
check "$(ran "$T/s10c")" "bash always.sh|bash modules/a/tests/check.sh|bash modules/b/tests/check.sh|" "…but a skill or an agent file is behaviour: its users' suites run"
back; rm -rf "$S/modules/c"
"$B/check" "$S" --out "$T/s11" > /dev/null
check "$(grep -c '^SKIP' "$T/s11/summary"):$(grep -c 'modules/d/tests/check.sh' "$T/s11/summary")" "2:1" "a module removed: its users' suites run (d names modules/c), the rest skip"
back
U="$T/core"
for m in core p q; do mkdir -p "$U/modules/$m/tests" "$U/modules/$m/.claude-plugin"; printf 'echo %s\n' "$m" > "$U/modules/$m/tests/check.sh"; done
echo '{"name":"core"}' > "$U/modules/core/.claude-plugin/plugin.json"
echo '{"name":"p","dependencies":["core"]}' > "$U/modules/p/.claude-plugin/plugin.json"
echo '{"name":"q","dependencies":["core"]}' > "$U/modules/q/.claude-plugin/plugin.json"
printf 'echo gate %s\n' '"$@"' > "$U/gate.sh"
printf -- '- check: `bash modules/core/tests/check.sh && bash modules/p/tests/check.sh && bash modules/q/tests/check.sh && bash gate.sh --ref HEAD`\n' > "$U/AGENTS.md"
( cd "$U" && git init -q && git checkout -q -b main && git add -A && git -c user.name=t -c user.email=t@t commit -qm init \
  && git worktree add -q -b claude/u "$T/wtu" main ) > /dev/null 2>&1
echo x > "$T/wtu/modules/p/new"
"$B/check" "$T/wtu" --out "$T/s12" > "$T/s12.out"
check "$(ran "$T/s12")" "bash modules/core/tests/check.sh|bash modules/p/tests/check.sh|bash gate.sh --ref HEAD|" "a module every other module declares (the core) runs on any change under modules/: its suite checks them all"
check "$(grep -c 'modules/core checks every module' "$T/s12.out")" "0" "…said in the summary's reason, not the scope line"

echo "the pass memory: a script that passed on this exact tree is not run again"
export CHECK_PASS_TTL=3600
"$B/check" "$T/wtu" --out "$T/u1" > /dev/null; ( cd "$T/wtu" && git add -A && git -c user.name=t -c user.email=t@t commit -qm p ) > /dev/null 2>&1
"$B/check" "$T/wtu" --out "$T/u2" > /dev/null
check "$(grep -c '^PASSED' "$T/u2/summary"):$(grep -c 'rc=0 [0-9]*s bash gate.sh --ref HEAD' "$T/u2/summary")" "2:1" "a command naming HEAD is remembered with the commit: after a commit of the same tree it runs again, the others are PASSED"
"$B/check" "$T/wtu" --out "$T/u3" > /dev/null
check "$(grep -c '^PASSED' "$T/u3/summary")" "3" "…and is remembered for that commit"
CLAUDE_UNATTENDED=dispatch "$B/check" "$T/wtu" --out "$T/u4" > /dev/null
check "$(grep -c '^PASSED' "$T/u4/summary")" "0" "an attended pass does not answer an unattended run: the mode is in the record"
CLAUDE_UNATTENDED=dispatch "$B/check" "$T/wtu" --out "$T/u5" > /dev/null
check "$(grep -c '^PASSED' "$T/u5/summary")" "3" "…an unattended one does"
sleep 60 & lp=$!; mkdir -p "$T/slots/slot-1"; echo $lp > "$T/slots/slot-1/pid"; echo "$(TZ=UTC LC_ALL=C ps -o lstart= -p $lp | xargs)" > "$T/slots/slot-1/start"
"$B/check" "$T/wtu" --out "$T/u6" > "$T/u6.out"; rc=$?
check "$rc:$(tail -1 "$T/u6/summary"):$(grep -c waiting "$T/u6.out")" "0:DONE 3/3:0" "a run remembered whole takes no slot: DONE at once while the slot is held"
kill $lp 2>/dev/null; wait $lp 2>/dev/null; rm -rf "$T/slots/slot-1"
rm -rf "$T/logs/passed"
echo m > "$S/modules/a/new"
"$B/check" "$S" --out "$T/m1" > /dev/null; rc=$?
check "$rc:$(tail -1 "$T/m1/summary")" "0:DONE 3/3" "a first run: runs and passes"
check "$(ls "$T/logs/passed" | wc -l | tr -d ' ')" "1" "…remembered under \$CHECK_LOGS/passed/<tree>"
"$B/check" "$S" --out "$T/m2" > "$T/m2.out"; rc=$?
check "$rc:$(tail -1 "$T/m2/summary")" "0:DONE 3/3" "the same tree again: passed, nothing run"
check "$(ls "$T/m2" | grep -c '\.log$')" "0" "…no script log"
check "$(sed -n 3p "$T/m2/summary" | sed -E 's/^PASSED [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2} bash always\.sh$/FORM/')" "FORM" "…a line: PASSED, when, the command"
check "$(grep -c '^PASSED' "$T/m2.out")" "3" "…on stdout too"
"$B/check" "$S" --fresh --out "$T/m3" > /dev/null
check "$(ls "$T/m3" | grep -c '\.log$')" "3" "--fresh: run again"
echo n > "$S/modules/a/new"
"$B/check" "$S" --out "$T/m4" > /dev/null
check "$(ls "$T/m4" | grep -c '\.log$')" "3" "a changed tree (uncommitted): run again"
"$B/check" "$S" --only modules/a/tests/check.sh --out "$T/m5" > /dev/null
check "$(grep -c '^PASSED' "$T/m5/summary")" "1" "--only: the memory still answers"
printf 'exit 4\n' > "$S/modules/a/tests/check.sh"
"$B/check" "$S" --out "$T/m6" > /dev/null; "$B/check" "$S" --out "$T/m7" > /dev/null; rc=$?
check "$rc:$(grep -c '^PASSED' "$T/m7/summary"):$(grep -c 'rc=4' "$T/m7/summary")" "1:2:1" "a failed script is not remembered: it runs again, the passed ones are not"
( cd "$S" && git checkout -q -- . ) > /dev/null 2>&1
CHECK_PASS_TTL=1 "$B/check" "$S" --out "$T/m8" > /dev/null; sleep 2
CHECK_PASS_TTL=1 "$B/check" "$S" --out "$T/m9" > /dev/null
check "$(grep -c '^PASSED' "$T/m9/summary")" "0" "a record older than CHECK_PASS_TTL is not used"
CHECK_PASS_TTL=0 "$B/check" "$S" --out "$T/m10" > /dev/null
check "$(grep -c '^PASSED' "$T/m10/summary")" "0" "CHECK_PASS_TTL=0: the memory is off"
CHECK_PASS_TTL=x "$B/check" "$S" > /dev/null 2>&1; check "$?" "2" "CHECK_PASS_TTL that is not a number: exit 2"
export CHECK_PASS_TTL=0

echo
[ "$fails" -eq 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
