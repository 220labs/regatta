#!/usr/bin/env bash
# Tests for the queue's S4 (docs/dispatch-queue-2026-10-25.md): priorities and the force — force's one slot
# over the cap and its memory floor at claim (D2-A), who may raise (D3-A: an unattended caller inherits from
# its own run's record, never its word), the force mark (hooks/force_mark.py) and its frame filters, and the
# items carried to S4 from S3's reviews: one shared reader of the queue (queue_holds.py) that holds only the
# branches a torn store routes, the waiter's put_at, the guarded fire-time requeue, --if-room's skip, watch's
# re-put, the stale-read remap. A suite of its own, apart from test_queue.sh and test_dispatch.sh, so no two
# steps edit one file's tail. Scratch HOME, a bare repo as the queue's home, a stand-in launchctl; no launchd
# job, session or network is touched. Every name is synthetic.
#   bash modules/wharf-runs/tests/test_priority.sh
set -u
unset WEEKLY_RUN CLAUDE_UNATTENDED REGATTA_UNATTENDED CLAUDECODE CLAUDE_CODE_DISABLE_BACKGROUND_TASKS CLAUDE_CODE_SESSION_ID CLAUDE_CONFIG_DIR XPC_SERVICE_NAME AUTOFINISH_CALLER_UNATTENDED
unset $(compgen -v | grep '^DISPATCH_')   # every DISPATCH_* a run carries (AGENTS.md: a fixed list goes stale)
B="$(cd "$(dirname "$0")/../bin" && pwd)"
H="$(cd "$(dirname "$0")/../hooks" && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
. "$(cd "$(dirname "$0")" && pwd)/config_fixture.sh"; fixture_config "$T/config"
fails=0
check() { if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3: expected [$2] got [$1]"; fails=$((fails+1)); fi; }
has()   { if grep -qF -- "$2" "$1"; then echo "  ok   $3"; else echo "  FAIL $3: missing [$2]"; sed 's/^/         | /' "$1" | head -20; fails=$((fails+1)); fi; }
hasnt() { if grep -qF -- "$2" "$1"; then echo "  FAIL $3: unexpected [$2]"; sed 's/^/         | /' "$1" | head -20; fails=$((fails+1)); else echo "  ok   $3"; fi; }
export PYTHONUSERBASE="${PYTHONUSERBASE:-$(python3 -m site --user-base)}"
export HOME="$T/home"; HL="$HOME/Library"; mkdir -p "$HL/LaunchAgents"
# a recursive delete under HOME goes through rm_own: only under this suite's own $T (the core's check, home_rm)
rm_own() { local p; for p; do case "$p" in */..|*/../*|*//*) ;; "${T:?}"/?*) rm -rf -- "$p"; continue ;; esac; echo "rm_own: refused $p, outside $T" >&2; return 1; done; }
export ACCOUNTS_FILE="$T/no-accounts.json"
# a moved HOME drops the global git identity (AGENTS.md: a suite that moves HOME and commits)
printf '[user]\n\tname = t\n\temail = t@t\n[init]\n\tdefaultBranch = main\n' > "$T/gitconfig"; export GIT_CONFIG_GLOBAL="$T/gitconfig"
git init -q -b main "$T/repo"; (cd "$T/repo" && echo x > f && git add f && git commit -qm init)
cat > "$T/launchctl" <<EOF
#!/bin/sh
echo "\$*" >> "$T/calls"
exit 0
EOF
chmod +x "$T/launchctl"
export DISPATCH_LAUNCHCTL="$T/launchctl" DISPATCH_DEFAULT_ON= DISPATCH_HOST=laptop
git init -q --bare "$T/queue.git"
echo "$T/queue.git" > "$REGATTA_CONFIG/wharf-runs/queue-repo"
QB="$B/dispatch-queue"; LA="$HL/LaunchAgents"; QL="$HL/Logs/claude-weekly/queue.jsonl"; RUNS="$HL/Logs/claude-weekly/run-seed-runs"
QC=(--cap 3 --launchctl "$T/launchctl" --prefix org.example.claude --jobbin "$B/dispatch")
QGIT=(git --git-dir="$T/queue.git")
cat > "$T/qget.py" <<'PY'
import json, sys
d = json.load(sys.stdin)
print(" ".join(str(d.get(k)) for k in sys.argv[1:]))
PY
qget() { local k=$1; shift; "${QGIT[@]}" show "refs/regatta/queue:queue/$k.json" 2>/dev/null | python3 "$T/qget.py" "$@" 2>/dev/null; }
qreset() {
  "${QGIT[@]}" update-ref -d refs/regatta/queue 2>/dev/null
  rm_own "$HL/Caches/run-seed/queue" "$HL/Caches/run-seed/queue-local" "$RUNS"
  rm_own "$LA"/*.plist; rm -f "$T/calls" "$QL"
}
BR=claude/laptop/2026-10-28
enq() { python3 "$QB" enqueue --repo "$T/repo" --branch "$BR-$1" "${QC[@]}" "${@:2}"; }
# a force put: this suite runs under a Claude session (a claude among its ancestors) or not (CI); either way a
# session id and its force mark let it in (dispatch-queue force_refusal), and the put spends the mark
FM="$HL/Caches/run-seed/force"
fenq() { mkdir -p "$FM"; : > "$FM/s-suite"; CLAUDE_CODE_SESSION_ID=s-suite enq "$@"; }
# a run record whose claude is PID (an ancestor of what the case runs, or not), at rank PRIO
rec() { mkdir -p "$RUNS"; printf '{"session": "%s", "pid": %s, "prio": "%s", "branch": "%s-own", "repo": "%s", "started": %s}\n' \
          "$1" "$2" "$3" "$BR" "$T/repo" "$(date +%s)" > "$RUNS/$1.json"; }

echo "the claim: force one slot over the cap, at most one above it; a second force entry waits first in line (D2-A)"
qreset
fenq sp --priority force > /dev/null
check "$([ -f "$FM/s-suite" ] && echo kept || echo spent)" "spent" "a force put that lands spends the session's mark (enqueue)"
qreset
enq n1 > /dev/null; fenq f1 --priority force > /dev/null; fenq f2 --priority force > /dev/null
python3 "$QB" claim --cap 0 --launchctl "$T/launchctl" --prefix org.example.claude --jobbin "$B/dispatch" > /dev/null
check "$(qget repo--n1 state) $(qget repo--f1 state) $(qget repo--f2 state)" "queued claimed queued" \
  "a full host (cap 0): the first force entry claimed one slot over it, the normal entry and the second force entry wait"
python3 "$QB" list --json "${QC[@]}" > "$T/list"
check "$(python3 -c 'import json,sys; print([e["topic"] for e in json.load(open(sys.argv[1]))["entries"] if e["state"] == "queued"][0])' "$T/list")" "f2" \
  "  the second force entry is first in line"
check "$(python3 "$QB" cap --priority force --cap 6) $(python3 "$QB" cap --priority high --cap 6) $(python3 "$QB" cap --cap 6)" "7 6 6" \
  "dispatch-queue cap: force's cap is the host's plus one, every other rank's the host's"
check "$(grep -c '"$n" -ge "$(pcap)"' "$B/dispatch") $(grep -c '"$n" -lt "$(pcap)"' "$B/dispatch") $(grep -c '"$n" -ge "$scap"' "$B/dispatch") $(grep -c 'c=$(pcap)' "$B/dispatch")" "2 3 3 0" \
  "  dispatch's Claude and vendor fire paths (agy and Codex both run run_vendor), its no-queue refusals and --start count against the priority cap"

echo "a requeued run goes back at force (S10; the owner, 2026-10-30), and force's claim rules apply to it"
qreset
cat > "$T/rqf.py" <<'PY'
import importlib.machinery as m, importlib.util as u, sys, time
l = m.SourceFileLoader("dq", sys.argv[1]); q = u.module_from_spec(u.spec_from_loader("dq", l)); l.exec_module(q)
f = q.Fleet(sys.argv[2]); t = int(time.time())
# runs of this host, running, then handed back by the verb's requeue op (force: the verb's word)
for k in sys.argv[3:]:
    f.do([{"op": "set", "key": k, "fields": {"state": "running", "running_on": "laptop", "claimed_by": "laptop",
                                              "claimed_at": t, "session": "s-" + k}}], "seed")
    f.do([{"op": "requeue", "key": k, "host": "laptop", "at": t, "force": True}], "requeue")
PY
enq n1 > /dev/null; enq r1 > /dev/null; enq r2 > /dev/null
python3 "$T/rqf.py" "$QB" "$T/queue.git" repo--r1 repo--r2
check "$(qget repo--r1 state priority) $(qget repo--r2 state priority) $(qget repo--n1 state priority)" "queued force queued force queued normal" \
  "a normal entry requeued by the op is force; an entry nobody requeued keeps its rank"
python3 "$QB" claim --cap 0 --launchctl "$T/launchctl" --prefix org.example.claude --jobbin "$B/dispatch" > /dev/null
check "$(qget repo--r1 state) $(qget repo--r2 state) $(qget repo--n1 state)" "claimed queued queued" \
  "  claimed on a full host (cap 0): the first requeued entry took force's one slot over it, the second and the normal entry wait"
python3 "$QB" list --json "${QC[@]}" > "$T/list"
check "$(python3 -c 'import json,sys; print([e["topic"] for e in json.load(open(sys.argv[1]))["entries"] if e["state"] == "queued"][0])' "$T/list")" "r2" \
  "  the second requeued entry is first in line, ahead of the normal one"
check "$(qget repo--r1 args)" "['--priority', 'force']" "  its args carry --priority force"
check "$(python3 -c 'import glob, plistlib, sys; print(" ".join(a for f in glob.glob(sys.argv[1] + "/*.plist") for a in plistlib.load(open(f, "rb"))["ProgramArguments"] if a in ("--priority", "force")))' "$LA")" "--priority force" \
  "  …and the claim's job plist hands --priority force to the fired dispatch"

echo "the claim: force's memory floor (headroom --floor 5: avail 5 %, swap and rate kept)"
qreset
printf '%s\n' "*:avail=15,rate=30" > "$REGATTA_CONFIG/wharf-runs/headroom"
enq m1 > /dev/null; fenq mf --priority force > /dev/null
HEADROOM_SAMPLE="7 1 2" python3 "$QB" enqueue --repo "$T/repo" --branch "$BR-m2" --claim "${QC[@]}" > "$T/out"
check "$(qget repo--m1 state) $(qget repo--mf state) $(qget repo--m2 state)" "queued claimed queued" "7 % free: under the host's 15 %, over the force's floor — the force entry alone starts"
has "$T/out" "only a force entry passes the force's floor" "  an enqueue --claim says why the rest wait"
has "$QL" '"floor": 5' "  the normal entry's no-room logged with the floor"
qreset
fenq mf2 --priority force > /dev/null
HEADROOM_SAMPLE="3 1 2" python3 "$QB" claim "${QC[@]}" > /dev/null
check "$(qget repo--mf2 state)" "queued" "3 % free: under the floor too, nothing starts"
HEADROOM_SAMPLE="50 1 90" python3 "$QB" claim "${QC[@]}" > /dev/null
check "$(qget repo--mf2 state)" "queued" "  swapping past the rate line: nothing starts, force or not"
eval "$(sed -n '/^roomy() {/,/^}/p' "$B/dispatch")"
( here="$(dirname "$B")"; Q="$QB"
  prio=force; HEADROOM_SAMPLE="7 1 2" roomy > /dev/null 2>&1; a=$?
  prio=normal; HEADROOM_SAMPLE="7 1 2" roomy > /dev/null 2>&1; echo "$a $?" ) > "$T/roomy"
check "$(cat "$T/roomy")" "0 1" "  dispatch's roomy, at 7 % free: room for a force run (dispatch-queue floor), none for a normal one"
rm -f "$REGATTA_CONFIG/wharf-runs/headroom"

echo "who may raise: an unattended caller by its own run's record, never its word (D3-A)"
qreset
CLAUDE_UNATTENDED=dispatch enq u1 --priority high > /dev/null 2> "$T/err"; check "$?" "2" "unattended, no record of its own: --priority high refused"
has "$T/err" "the next step waits for a run to end" "  in the cap's waiting words"
rec s-high $$ high
CLAUDE_UNATTENDED=dispatch enq u2 --priority high > /dev/null 2> "$T/err"; check "$?" "0" "its own run's record (its claude an ancestor) says high: high passes"
check "$(qget repo--u2 priority)" "high" "  queued high"
CLAUDE_UNATTENDED=dispatch enq u3 --priority force > /dev/null 2> "$T/err"; check "$?" "2" "  force never, record or not"
rec s-high $$ force
check "$(python3 "$QB" caller-prio)" "high" "a force record is inherited as high: one phrase, one run"
rm -f "$RUNS/s-high.json"
sleep 300 & SP=$!
rec s-other "$SP" high
CLAUDE_UNATTENDED=dispatch CLAUDE_CODE_SESSION_ID=s-other enq u4 --priority high > /dev/null 2> "$T/err"; check "$?" "2" \
  "a session id naming another run's high record: refused — the record must be the caller's ancestor's, never by its id"
check "$(CLAUDE_CODE_SESSION_ID=s-other python3 "$QB" caller-prio)" "" "  and inherits nothing"
kill "$SP" 2>/dev/null; wait "$SP" 2>/dev/null
rm -f "$RUNS/s-other.json"

echo "who may raise: dispatch's own checks"
qreset
CLAUDE_UNATTENDED=dispatch "$B/dispatch" "$BR-d1" --repo "$T/repo" --priority force --dry-run > "$T/out" 2> "$T/err"; check "$?" "2" "unattended --priority force: refused"
has "$T/err" "the owner's word for one run" "  saying force is the owner's"
printf '#!/usr/bin/env python3\nimport sys\nprint("high")\n' > "$T/qstand.py"
CLAUDE_UNATTENDED=dispatch DISPATCH_QUEUE_BIN=/dev/null "$B/dispatch" "$BR-d1" --repo "$T/repo" --priority force --dry-run > "$T/out" 2> "$T/err"; check "$?" "2" "unattended force with DISPATCH_QUEUE_BIN=/dev/null: still refused (the final landing review)"
CLAUDE_UNATTENDED=dispatch DISPATCH_QUEUE_BIN="$T/qstand.py" "$B/dispatch" "$BR-d1" --repo "$T/repo" --priority high --dry-run > "$T/out" 2> "$T/err"; check "$?" "2" "unattended high with a stand-in answering high: still refused"
CLAUDE_UNATTENDED=dispatch "$B/dispatch" "$BR-d1" --repo "$T/repo" --priority high --dry-run > "$T/out" 2> "$T/err"; check "$?" "2" "unattended --priority high with no record: refused"
rec s-run $$ high
CLAUDE_UNATTENDED=dispatch "$B/dispatch" "$BR-d1" --repo "$T/repo" --priority high --dry-run > "$T/out" 2> "$T/err"
hasnt "$T/err" "never raises" "  its own run's record high: no raise refusal"
rm -f "$RUNS/s-run.json"
printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0"><dict><key>Label</key><string>org.example.claude.dispatch.repo.d1.202610280900</string><key>ProgramArguments</key><array><string>%s</string><string>%s</string><string>--priority</string><string>force</string></array></dict></plist>\n' \
  "$B/dispatch" "$BR-d1" > "$LA/org.example.claude.dispatch.repo.d1.202610280900.plist"
CLAUDE_UNATTENDED=dispatch DISPATCH_LABEL=org.example.claude.dispatch.repo.d1.202610280900 "$B/dispatch" "$BR-d1" --repo "$T/repo" --priority force --dry-run > "$T/out" 2> "$T/err"
check "$?" "2" "a DISPATCH_LABEL naming a job's plist that carries force: no exemption, an unattended caller is refused (the landing review)"
rm_own "$LA"/*.plist
check "$(sed -n '/^if \[ "$prio_given" = 0 \] && \[ "$next" = 1 \]/,/^fi/p' "$B/dispatch" | grep -c 'caller-prio')" "1" \
  "a --next with no --priority takes its own run's rank (caller-prio), never the environment's"

echo "the force mark: an attended session's force needs the owner's words, spent once the dispatch lands"
# the seeded branch a real --at needs: on origin, a brief, a repo whose contract says physical: none
git init -q --bare "$T/origin.git"; git -C "$T/repo" remote add origin "$T/origin.git" 2>/dev/null
printf -- '- physical: none\n' > "$T/repo/AGENTS.md"; git -C "$T/repo" add AGENTS.md; git -C "$T/repo" commit -qm contract
git -C "$T/repo" checkout -q -b "$BR-d2"; mkdir -p "$T/repo/docs/handoff"; echo brief > "$T/repo/docs/handoff/2026-10-28-d2.md"
git -C "$T/repo" add docs; git -C "$T/repo" commit -qm seed; git -C "$T/repo" push -q origin "$BR-d2" main 2>/dev/null; git -C "$T/repo" checkout -q main
CLAUDECODE=1 CLAUDE_CODE_SESSION_ID=s-att "$B/dispatch" "$BR-d2" --repo "$T/repo" --priority force --dry-run > "$T/out" 2> "$T/err"; check "$?" "2" "an attended session with no force mark: refused"
has "$T/err" "use the force" "  naming the owner's words"
CLAUDECODE=1 "$B/dispatch" "$BR-d2" --repo "$T/repo" --priority force --dry-run > "$T/out" 2> "$T/err"; check "$?" "2" "  a session that dropped its id: refused too (CLAUDECODE)"
# The probe asks ancestry() first: a `ps` that times out on a loaded runner reads as a
# session there (fails closed), while dispatch's own read a moment later finds no claude and passes the call: the
# likely cause, not observed, of the case failing on a self-hosted runner Mac with no session above it (regatta#489's
# check, 2026-11-04; that runner's ancestry, read after, holds no claude). "Could not tell" skips the case; a real
# claude ancestor runs it; a probe that printed none of its three words crashed, and fails.
uc=$(python3 -c 'import importlib.machinery, sys
q = importlib.machinery.SourceFileLoader("dq", sys.argv[1]).load_module()
print("unknown" if q.ancestry() is None else q.under_claude())' "$QB")
if [ "$uc" != True ] && [ "$uc" != False ] && [ "$uc" != unknown ]; then
  check "$uc" "True, False or unknown" "  the ancestry probe ran (a crash would skip the case for good)"
elif [ "$uc" = True ]; then
  env -u CLAUDECODE -u CLAUDE_CODE_SESSION_ID "$B/dispatch" "$BR-d2" --repo "$T/repo" --priority force --dry-run > "$T/out" 2> "$T/err"; check "$?" "2" \
    "  one that dropped both: refused by its ancestry (a claude among dispatch's parents)"
  has "$T/err" "use the force" "  for want of the owner's words, not another refusal"
else
  echo "  --   skipped: no Claude session above this suite, or ps could not tell ($uc; the ancestry case needs one)"
fi
CLAUDECODE=1 python3 "$QB" enqueue --repo "$T/repo" --branch "$BR-d3" --priority force "${QC[@]}" > /dev/null 2> "$T/err"; check "$?" "2" \
  "dispatch-queue enqueue by path: the same force check (it is on the Bash PATH)"
mkdir -p "$FM"; echo x > "$FM/s-att"
CLAUDECODE=1 CLAUDE_CODE_SESSION_ID=s-att "$B/dispatch" "$BR-d2" --repo "$T/repo" --priority force --dry-run > "$T/out" 2> "$T/err"
hasnt "$T/err" "use the force" "  with the mark: passes"
check "$([ -f "$FM/s-att" ] && echo kept)" "kept" "  a dry run spends nothing"
CLAUDECODE=1 CLAUDE_CODE_SESSION_ID=s-att "$B/dispatch" "$BR-d2" --repo "$T/repo" --priority force --on no-such-host --at "@$(( $(date +%s) + 7200 ))" > "$T/out" 2> "$T/err"
check "$?:$([ -f "$FM/s-att" ] && echo kept || echo spent)" "2:kept" "  a dispatch refused after the check spends nothing (AGENTS.md: a write for a newer word goes after every refusal)"
CLAUDECODE=1 CLAUDE_CODE_SESSION_ID=s-att DISPATCH_LABEL=x "$B/dispatch" "$BR-d2" --repo "$T/repo" --priority force --dry-run > "$T/out" 2> "$T/err"
hasnt "$T/err" "this session has none" "  (the mark still held)"
rm -f "$FM/s-att"
CLAUDECODE=1 CLAUDE_CODE_SESSION_ID=s-att DISPATCH_LABEL=x "$B/dispatch" "$BR-d2" --repo "$T/repo" --priority force --dry-run > "$T/out" 2> "$T/err"; check "$?" "2" \
  "  a DISPATCH_LABEL exempts no session from the mark (the landing review)"
echo x > "$FM/s-att"
CLAUDECODE=1 CLAUDE_CODE_SESSION_ID=s-att "$B/dispatch" "$BR-d2" --repo "$T/repo" --priority force --on here --at "@$(( $(date +%s) + 7200 ))" > "$T/out" 2> "$T/err"
check "$?:$([ -f "$FM/s-att" ] && echo kept || echo spent)" "0:spent" "  a dispatch that lands (a one-shot written) spends it: one phrase, one run"
check "$(ls "$LA" | grep -c "d2")" "1" "  the one-shot's plist written"
grep -q "<string>--priority</string><string>force</string>" "$LA"/*d2*.plist; check "$?" "0" "  carrying --priority force"
CLAUDECODE=1 CLAUDE_CODE_SESSION_ID=s-att "$B/dispatch" "$BR-d2" --repo "$T/repo" --priority force --dry-run > "$T/out" 2> "$T/err"; check "$?" "2" "  so the next force is refused"
rm_own "$LA"/*.plist
# the owner's terminal: no session variables and no claude above it — a process reparented away from this
# suite's own parents (the subshell that started it exits at once), so the case holds inside a session too
# A ps that fails or times out on a loaded runner reads as a session (under_claude() fails closed) and refuses this
# call too; one more try lets a refusal stand only when two reads agree (engineering: verify, then retry once).
for try in 1 2; do
  rm -f "$T/term.rc"
  ( ( sleep 1; "$B/dispatch" "$BR-d2" --repo "$T/repo" --priority force --dry-run > "$T/term.out" 2> "$T/term.err"; echo $? > "$T/term.rc" ) & )
  for i in $(seq 1 60); do [ -s "$T/term.rc" ] && break; sleep 0.5; done
  [ "$(cat "$T/term.rc" 2>/dev/null)" = 0 ] && break
done
hasnt "$T/term.err" "use the force" "outside any session (the owner's terminal): the flag is the owner's typing"
check "$(cat "$T/term.rc" 2>/dev/null)" "0" "  that dispatch ran and passed (exit 0)"
mkdir -p "$FM"; echo x > "$FM/s-old"; touch -t 202610280000 "$FM/s-old"
CLAUDECODE=1 CLAUDE_CODE_SESSION_ID=s-old "$B/dispatch" "$BR-d2" --repo "$T/repo" --priority force --dry-run > "$T/out" 2> "$T/err"; check "$?" "2" \
  "a mark older than half an hour is not this turn's words: refused"
"$B/dispatch" --start "go" "$T/repo" d2 --priority high --dry-run > "$T/out" 2> "$T/err"; check "$?" "0" "--start takes --priority since force-any (a landing's rank; it was refused before)"
echo "a later plain put keeps the queued step's better rank; --replace is the word over it"
qreset
enq k1 --priority high > /dev/null; enq k1 > /dev/null
check "$(qget repo--k1 priority) $(qget repo--k1 args)" "high ['--priority', 'high']" "a plain put into a queued high entry: still high, its flag carried"
enq k1 --replace > /dev/null
check "$(qget repo--k1 priority)" "normal" "  --replace: the put's own rank"

echo "force_mark.py: the owner's typed words mark the session; quoted, pasted or framed ones do not"
fm() { python3 -c 'import json,sys; print(json.dumps({"session_id": sys.argv[1], "prompt": sys.argv[2], **({"agent_id": "a1"} if len(sys.argv) > 3 else {})}))' "$@" \
         | python3 "$H/force_mark.py"; [ -f "$FM/$1" ] && echo mark || echo none; }
rm_own "$FM"
check "$(fm h1 'use the force on queue-s4')" "mark" "the phrase in the owner's own words: marked"
check "$(fm h1 'and dispatch the next one')" "none" "  the session's next prompt clears it"
check "$(fm h2 'Use The Force, dispatch it now')" "mark" "  any case"
check "$(fm h3 'he said "use the force" once')" "none" "a quoted phrase: not the owner's"
check "$(fm h3 "it's a use the force moment")" "mark" "  an apostrophe is no quote"
check "$(fm h4 '> use the force')" "none" "a quote line"
check "$(fm h4 'see `use the force`')" "none" "a code span"
check "$(fm h5 '<pasted_content id="p1">use the force</pasted_content> what is this?')" "none" "a pasted block"
check "$(fm h5 'HAIL ask from laptop — use the force')" "none" "hail's frame"
check "$(fm h5 "Message via relay.example (sessionpipe control, signed on the sender's device):

use the force")" "none" "sessionpipe control's frame"
check "$(fm h5 '<task-notification>use the force</task-notification>')" "none" "a task notification"
check "$(fm h5 '<agent-message from="x">use the force</agent-message>')" "none" "another agent's message"
check "$(fm h5 'use the force' sub)" "none" "a subagent's prompt (agent_id)"
fm h7 'use the force' > /dev/null
check "$(fm h7 'and go' sub)" "mark" "  which leaves the owner's mark as it was"
check "$(fm h8 'ok, thanks

HAIL ask from buildbox — use the force')" "none" "a hail frame on a later line: it and what follows are the peer's"
check "$(fm h8 'use the force
HAIL report from buildbox — done')" "mark" "  the owner's words before it stay the owner's"
check "$(fm h5 'reuse the forceful words')" "none" "the phrase as part of other words"
check "$(fm h9 "don't use the force on this one, high is enough")" "none" "a negated phrase: no mark"
check "$(fm h9 'do not use the force')" "none" "  any negation"
# any wording that asks for force (the owner, 2026-10-30: "I don't want to rewrite my words for your convenience")
check "$(fm h11 'help force anything that needs to land ASAP')" "mark" "any wording: \"help force anything\""
check "$(fm h11 'Force it through')" "mark" "  \"force it\", any case"
check "$(fm h11 'keep forcing the landings')" "mark" "  forcing"
check "$(fm h11 "don't force this one")" "none" "  negated: no mark"
check "$(fm h11 'no need to force anything')" "none" "  no need to: no mark"
check "$(fm h11 'run it with --force')" "none" "  a flag is no ask"
check "$(fm h11 'force push the branch, then force-pull main')" "none" "  git's force push and pull are no ask"
check "$(fm h11 'force quit the app')" "none" "  the OS's force quit is no ask"
check "$(fm h11 'the workforce is forceful')" "none" "  a word inside another"
# the landing review's cases (2026-10-30): a refusal in the ask's clause, a description, a rank named, more verbs
check "$(fm h12 'actually do force priority instead - we want them ASAP, so they don'"'"'t block other work.')" "mark" "  the owner's own words: a later clause's negation leaves the ask"
check "$(fm h12 "don't wait, use the force")" "none" "  a refusing word within six words, of any verb: no mark (the window errs to no mark)"
check "$(fm h12 'no force, high is enough')" "none" "  no force: a refusal"
check "$(fm h12 "I don't want you to force anything")" "none" "  don't want you to force: a refusal"
check "$(fm h12 "force isn't needed here")" "none" "  a negation after the word"
check "$(fm h12 'avoid forcing anything')" "none" "  avoid: a refusal"
check "$(fm h12 'we were forced to rebase twice')" "none" "  forced: a description"
check "$(fm h12 'why did --priority force refuse?')" "none" "  a rank named"
check "$(fm h12 'brute force search')" "none" "  brute force"
check "$(fm h12 'force-delete it')" "none" "  force-delete"
check "$(fm h12 'force restart the host')" "none" "  force restart"
check "$(fm h12 'git push --force-with-lease, or force-with-lease it')" "none" "  force-with-lease"
check "$(fm h12 'force  push it')" "none" "  any spacing before the verb"
# the second landing review's refusals (2026-10-30): across a break, before an aside or a list, in a curly quote
check "$(fm h13 'Force? No.')" "none" "  Force? No."
check "$(fm h13 'force, no')" "none" "  force, no"
check "$(fm h13 'Force — not now')" "none" "  Force — not now"
check "$(fm h13 'do we need force? no, high is fine')" "none" "  a question answered no"
check "$(fm h13 "please don't, force is overkill")" "none" "  please don't, force is overkill"
check "$(fm h13 'Never, ever force it')" "none" "  Never, ever"
check "$(fm h13 "Don't, under any circumstances, force it")" "none" "  a refusal before an aside"
check "$(fm h13 'No need for high, force or critical')" "none" "  a refusal before a list"
check "$(fm h13 'I said ‘don’t force it’')" "none" "  a curly-quoted refusal"
check "$(fm h13 'use the force, and also do a quick change to accept any phrase that suggests use of force as allowing it. I don'"'"'t want to rewrite my words for your convenience.')" "mark" "  the owner's own ask, a later don't six words past it"
# the third landing review's false marks (2026-10-30)
check "$(fm h14 'dont force it')" "none" "  a contraction without its apostrophe"
check "$(fm h14 "I said 'don't force it'")" "none" "  a straight-quoted refusal"
check "$(fm h14 'Never use force on these. As I said, the force rank is only for outages.')" "none" "  a refusal vetoes a later mention"
check "$(fm h14 'dispatch it high rather than force')" "none" "  rather than force"
check "$(fm h14 'high is fine, skip force')" "none" "  skip force"
check "$(fm h14 'I force-pushed the branch')" "none" "  an inflected git verb"
check "$(fm h14 'it force quits on launch')" "none" "  an inflected OS verb"
check "$(fm h14 'why did you force it?')" "none" "  a question about a past force"
check "$(fm h14 'review the force mark change')" "none" "  the feature's own noun"
check "$(fm h14 'dispatch-queue force-ok refused')" "none" "  force-ok"
check "$(fm h14 'why did --priority=force refuse')" "none" "  another spelling of the rank"
check "$(fm h14 'force it through, the queue is stuck')" "mark" "  a plain ask still marks"
check "$(fm h14 'instead of waiting, force it')" "mark" "  instead of another word, then force: an ask"
check "$(fm h14 'top priority: force queue-s4')" "mark" "  a priority that is no flag: an ask"
check "$(fm h14 'instead of force use high. force is for outages')" "none" "  force chosen against vetoes a later mention"
check "$(fm h14 'is force needed? I doubt force helps here')" "none" "  a question vetoes a later mention"
fm h10 'use the force' > /dev/null
check "$(fm h10 '<task-notification>done</task-notification>')" "mark" "a notification leaves the owner's mark as it was"
check "$(fm h10 'HAIL report from buildbox — done')" "mark" "  and a peer's frame"
# the fourth landing review (2026-10-31): VS Code's blocks, a dash autocorrected, and the refusals themselves pasted back
check "$(fm h11 '<ide_opened_file>The user opened the file /x/force-phrases/README.md in the IDE.</ide_opened_file>
thanks')" "none" "VS Code's opened-file block: not the owner's words"
check "$(fm h11 '<ide_selection>#  force: the claiming host</ide_selection>
what does this mean')" "none" "  nor its selection"
check "$(fm h11 '<ide_opened_file>x</ide_opened_file> force it')" "mark" "  the owner's words beside it still count"
check "$(fm h11 'rerun dispatch —force for the account override')" "none" "an em dash before force is the flag named"
check "$(fm h11 'rerun dispatch –force')" "none" "  an en dash too"
check "$(fm h11 'it said –priority force')" "none" "  and before priority"
check "$(fm h11 "--priority force is the owner's word: it needs the owner's own message this turn asking for \"force\", in any wording (\"use the force\", \"force it\"; the force mark), and this session has none — dispatch it high, or ask the owner")" "none" "dispatch-queue's refusal pasted back: no mark"
check "$(fm h11 "⛔ \`touch x\` writes the force mark by hand (\`Library/Caches/run-seed/force\` under HOME): it stands for the owner asking for \"force\", in any wording, so only wharf-runs' force_mark hook writes it, from the owner's typed message, and only dispatch spends it. Reading it is fine; to dispatch at the force rank, ask the owner.")" "none" "checkpoint's deny pasted back: no mark"
check "$(fm h12 'that force run failed')" "none" "a determiner beyond the/a: talk about force"
check "$(fm h12 'your force check refused it')" "none" "  your"
check "$(fm h12 'the task force meets at noon')" "none" "a compound noun: task force"
check "$(fm h12 'the policy is in force')" "none" "  in force"
check "$(fm h12 'pass force=True to publish()')" "none" "code: force=True"
check "$(fm h12 'force.py has a bug')" "none" "  force.py"
check "$(fm h12 'that one is stuck, force it')" "mark" "  a determiner elsewhere leaves an ask an ask"
check "$(fm h12 'force it.')" "mark" "  a full stop after force is no code"
check "$(CLAUDE_UNATTENDED=dispatch fm h6 'use the force')" "none" "an unattended session: never marked (its prompt is dispatch's)"
check "$(fm '../x' 'use the force') $(ls "$HL/Caches/run-seed" | grep -c '^x$')" "none 0" "a session id that is no plain name: nothing written"

echo "queue_holds.py: one reader for autofinish, helm and soundings; a torn store holds only its own branches"
cat > "$T/holds.py" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import queue_holds as qh
def holds(bad, entries=()):
    h = qh.Holds("/nonexistent")
    h._got = (list(entries), bad, "dispatch's queue does not read (x)" if bad else None)
    return h
ent = [{"qid": "fleet:open--a", "state": "queued", "repo": "open", "branch": "claude/x/a"},
       {"qid": "fleet:open--r", "state": "running", "repo": "open", "branch": "claude/x/r", "running_on": "laptop"}]
h = holds([], ent)
print(bool(h.why("open", "claude/x/a")), h.why("open", "claude/x/b"), h.why("other", "claude/x/a"),
      h.why("open", "claude/x/r", here="laptop"), bool(h.why("open", "claude/x/r", here="buildbox")))
h = holds([{"store": "local=vault", "keys": ["secret--s"]}])
print(bool(h.why("/p/secret", "claude/x/2026-10-28-s")), h.why("open", "claude/x/o"))
h = holds([{"store": "local=vault"}])
print(bool(h.why("open", "claude/x/o")), bool(holds([{"store": "fleet"}]).why("open", "claude/x/o")))
print(bool(holds([{"store": "*"}]).why("open", "claude/x/o")), qh.Holds("/nonexistent").why("open", "claude/x/o"))
PY
check "$(python3 "$T/holds.py" "$B" 2>&1 | tr '\n' '|')" \
  "True None None None True|True None|True True|True None|" \
  "an entry holds its branch by branch and repo; its own run here does not; a torn local store holds the keys it names, whatever the repo's scope (route's cwd road); one naming none, the fleet or no answer holds all; no dispatch-queue holds none"
check "$(python3 -c '
import importlib.machinery, sys
sys.path.insert(0, sys.argv[2]); import queue_holds as qh
q = importlib.machinery.SourceFileLoader("dq", sys.argv[1]).load_module()
cases = [("/p/a b", "claude/x/2026-10-28-t"), ("open", "claude/h/y"), ("r/", "claude/x/2026-10-28-a b")]
print(all(q.key_of(r, b) == qh.key_of(r, b) for r, b in cases))' "$QB" "$B")" "True" "  queue_holds' key_of is dispatch-queue's"
qreset
mkdir -p "$HL/Caches/run-seed/queue-local/vault"; printf 'torn' > "$HL/Caches/run-seed/queue-local/vault/x.json"
python3 "$QB" list --all --json "${QC[@]}" > "$T/list"
check "$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["unreadable"], [(b["store"], b.get("keys")) for b in d["bad_stores"]])' "$T/list")" "True [('local=vault', ['x'])]" \
  "list --json names the store that did not read (bad_stores), with the keys its file names hold"
rm_own "$HL/Caches/run-seed/queue-local"
for f in "$B/autofinish" "$(dirname "$B")/../helm/bin/stalls.py" "$(dirname "$B")/../sextant/bin/soundings"; do
  [ -f "$f" ] || continue
  check "$(grep -c 'queue_holds' "$f") $(grep -c '"has", "--repo"\|"list", "--all", "--json"' "$f")" "$(grep -c 'queue_holds' "$f" | grep -v '^0$' || echo x) 0" \
    "  $(basename "$f") reads the queue through queue_holds, not a lookup of its own"
done

echo "the waiter: put_at, never event_at; by_seen refreshed each sweep, batched into its one write"
qreset
python3 "$QB" enqueue --repo "$T/repo" --branch "$BR-w1" --by s-gone --host buildbox "${QC[@]}" > /dev/null
check "$(qget repo--w1 put_at | grep -c '^[0-9]')" "1" "a put stamps put_at"
cat > "$T/wl.py" <<'PY'
import importlib.machinery, sys
q = importlib.machinery.SourceFileLoader("dq", sys.argv[1]).load_module()
t = q.now()
old = t - 2 * q.WAITER_S
print(q.waiter_live({"from": "buildbox", "by": "s", "put_at": old, "event_at": t}),
      q.waiter_live({"from": "buildbox", "by": "s", "put_at": t - 60}),
      q.waiter_live({"from": "buildbox", "by": "s", "event_at": t - 60}))
PY
check "$(python3 "$T/wl.py" "$QB")" "False True True" \
  "a claim's fresh event_at keeps no gone waiter live; a fresh put does; an entry from before put_at reads event_at"
check "$(grep -c 'SWEEP // 2 and session_live' "$QB")" "1" "  the sweep refreshes by_seen each sweep (one missed sweep must not read a live waiter gone)"

echo "the fire-time requeue is guarded: a live session's queued step is kept"
qreset
python3 "$QB" enqueue --repo "$T/repo" --branch "$BR-g1" --by s-live --host buildbox "${QC[@]}" > /dev/null
python3 "$QB" enqueue --repo "$T/repo" --branch "$BR-g1" --refused "the run cap (3 of 3 busy on laptop)" "${QC[@]}" > "$T/out"; rc=$?
check "$rc $(qget repo--g1 by)" "3 s-live" "an enqueue --refused meets another host's live waiter: busy (exit 3), its step kept"
has "$T/out" '"result": "busy queued by session' "  answering busy, which queue_refused reads as queued already"
check "$(sed -n '/^queue_refused() {/,/^}/p' "$B/dispatch" | grep -c '"busy queued by"\*)')" "1" "  dispatch's queue_refused: busy is the step queued already, no FAILED"

echo "--if-room's refusal of a claimed entry is a skip, not a queue-failed card"
qreset
enq ir1 --arg=--if-room > /dev/null
python3 "$QB" claim "${QC[@]}" > /dev/null
lbl=$(qget repo--ir1 job)
python3 "$QB" failed fleet:repo--ir1 --label "$lbl" --why "FAILED: --if-room: the week is at 95 %; not starting" "${QC[@]}" > /dev/null
check "$(qget repo--ir1 state)" "" "the entry goes"
hasnt "$QL" '"queue-failed"' "  with no card"
has "$QL" '"event": "if-room-skip"' "  a queue.jsonl line instead"
enq ir2 > /dev/null; python3 "$QB" claim "${QC[@]}" > /dev/null
python3 "$QB" failed fleet:repo--ir2 --label "$(qget repo--ir2 job)" --why "FAILED: no docs/handoff brief" "${QC[@]}" > /dev/null
has "$QL" '"queue-failed"' "  any other failure keeps its card"

echo "watch follows its step re-put while queued, whatever the put's queued_at"
qreset
enq wa > /dev/null
( DISPATCH_WATCH_S=1 python3 "$QB" watch fleet:repo--wa --for 0.08 "${QC[@]}" > "$T/watch" 2>&1; echo "rc=$?" >> "$T/watch" ) &
WP=$!
sleep 1.5
enq wa --queued-at 1000 > /dev/null
wait "$WP"
hasnt "$T/watch" ": gone" "a re-put with an older --queued-at (a fired one-shot's) is followed, never read as gone"
has "$T/watch" "rc=1" "  --for passes with it still queued"

echo "the stale-read remap: watch's last fetch or an unreadable read is could-not-tell, never handed off"
cat > "$T/qstub" <<'PY'
import os, sys
print(os.environ["QSTUB_LINE"]); sys.exit(int(os.environ.get("QSTUB_RC") or 1))
PY
chmod +x "$T/qstub"
eval "$(sed -n '/^queue_unstarted() {/,/^}/p' "$B/dispatch")"
queue_close() { echo "HANDED OFF"; }
Q="$T/qstub"; q_qid=fleet:repo--x; branch="$BR-x"; model=opus; effort=high; log="$T/x.log"; qctx=(--host laptop)
for line in "10:00:00 fleet:repo--x: queued (the home did not answer: the last fetch)" "10:00:00 fleet:repo--x: unreadable: torn"; do
  QSTUB_LINE="$line" queue_unstarted 30 > "$T/out" 2>&1; rc=$?
  check "$rc $(grep -c 'HANDED OFF' "$T/out")" "2 0" "watch exit 1 on \"${line#*: }\": could not tell (2), not handed off"
done
QSTUB_RC=0 QSTUB_LINE="10:00:00 fleet:repo--x: waiting (the home did not answer: the last fetch)" queue_unstarted 30 > "$T/out" 2>&1; rc=$?
check "$rc $(grep -c 'claude is running\|waits for this run' "$T/out")" "2 0" "watch exit 0 read off the last fetch: could not tell too"
QSTUB_LINE="10:00:00 fleet:repo--x: queued" queue_unstarted 30 > "$T/out" 2>&1; rc=$?
check "$rc $(grep -c 'HANDED OFF' "$T/out")" "0 1" "  a fresh read still claimed: the queue holds it, handed off"
unset Q q_qid branch model effort log

echo "--on auto beside --wait or --replace with a queue home: the queue places it, no refusal naming berth's pick"
check "$(grep -c 'on_auto=0; on_default=0' "$B/dispatch")" "1" "a typed --on auto is dropped where --wait or --replace speaks to the queue"
echo "the unattended --next one-shot keeps its preference (S12: its pin before)"
check "$(grep -c '\[ "$next" = 1 \] && \[ -n "${REGATTA_UNATTENDED:-${CLAUDE_UNATTENDED:-}}" \]; }; } && opref=1' "$B/dispatch")" "1" \
  "its fallback plist carries DISPATCH_HOST_PREFER, as the queue road prefers its host (the marker under either name)"

echo "force-any: a finish's --priority, one rule for every kind of task (the owner, 2026-10-30; a fleet entry since finish-as-task)"
order() { python3 "$QB" list --json "${QC[@]}" | python3 -c 'import json,sys; print(" ".join(e["topic"] for e in json.load(sys.stdin)["entries"] if e["state"] == "queued"))'; }
TIP=$(git -C "$T/repo" rev-parse HEAD)
fin() { python3 "$QB" enqueue --kind finish --repo "$T/repo" --branch "$BR-$1" --tip "$TIP" --finish '{"by": "typed", "rule": "C", "from": "laptop"}' "${QC[@]}" "${@:2}"; }
qreset
enq hi --priority high > /dev/null
fin ln > /dev/null
mkdir -p "$FM"; : > "$FM/s-suite"
CLAUDE_CODE_SESSION_ID=s-suite fin lf --priority force > "$T/out"; check "$?" "0" "a finish at --priority force with the session's mark: queued"
check "$(qget repo--lf kind priority)" "finish force" "  a finish entry carrying force"
check "$([ -f "$FM/s-suite" ] && echo kept || echo spent)" "spent" "  the force mark spent once queued, as any put spends it"
check "$(order)" "lf hi ln" "  force first; a normal finish below a high build (a finish leads only its own priority)"
fin lh --priority high > /dev/null
check "$(order)" "lf lh hi ln" "a high finish: ahead of the high build, below the forced one"
python3 "$QB" list "${QC[@]}" > "$T/list"
has "$T/list" "queued force · rank 1 · a finish of ${TIP:0:7}" "the queue's list (and so dispatch --status) shows a finish and its priority"
python3 "$QB" claim --cap 0 --launchctl "$T/launchctl" --prefix org.example.claude --jobbin "$B/dispatch" > /dev/null
check "$(qget repo--lf state) $(qget repo--lh state) $(qget repo--ln state) $(qget repo--hi state)" "claimed queued queued queued" \
  "a full host (cap 0): the forced finish takes force's one slot over the cap, the rest wait"
python3 "$QB" raise --repo "$T/repo" --branch "$BR-lf" --priority high "${QC[@]}" > "$T/out"; check "$?" "0" \
  "raise on a claimed finish (its job starting it): 0, never 3 (a build or a second start beside it)"
has "$T/out" "it is claimed on laptop" "  saying so"
qreset
printf '%s\n' "*:avail=15,rate=30" > "$REGATTA_CONFIG/wharf-runs/headroom"
fin ln > /dev/null
: > "$FM/s-suite"; CLAUDE_CODE_SESSION_ID=s-suite fin lf --priority force > /dev/null
HEADROOM_SAMPLE="7 1 2" python3 "$QB" claim "${QC[@]}" > /dev/null
check "$(qget repo--lf state) $(qget repo--ln state)" "claimed queued" "7 % free: the forced finish passes the force's floor, the plain one waits"
rm -f "$REGATTA_CONFIG/wharf-runs/headroom"
qreset
CLAUDECODE=1 CLAUDE_CODE_SESSION_ID=s-nomark fin lf --priority force > /dev/null 2> "$T/err"; check "$?" "2" "a finish at --priority force without the force mark: refused"
has "$T/err" "use the force" "  with force-ok's words"
has "$T/err" "the next step waits for a run to end" "  in the cap's waiting words"
CLAUDE_UNATTENDED=dispatch fin lf --priority force > /dev/null 2> "$T/err"; check "$?" "2" "unattended: a finish at --priority force refused"
has "$T/err" "an unattended caller never raises to it" "  saying why"
CLAUDE_UNATTENDED=dispatch fin lh --priority high > /dev/null 2> "$T/err"; check "$?" "2" "  unattended, no high record of its own: high refused too"
check "$(qget repo--lf state)$(qget repo--lh state)" "" "  and nothing queued by a refusal"

echo "force-any: a finish already queued is raised in place, never a second entry"
qreset
fin rz > /dev/null
id0=$(qget repo--rz id queued_at)
: > "$FM/s-suite"
CLAUDE_CODE_SESSION_ID=s-suite python3 "$QB" raise --repo "$T/repo" --branch "$BR-rz" --priority force "${QC[@]}" > "$T/out"; check "$?" "0" "raise --priority force: 0"
has "$T/out" "raised fleet:repo--rz to force (was normal)" "  saying what it raised"
check "$(qget repo--rz id queued_at) $(qget repo--rz priority kind)" "$id0 force finish" "  one entry: its id and place kept, its priority force"
check "$([ -f "$FM/s-suite" ] && echo kept || echo spent)" "spent" "  the force mark spent once the raise landed"
python3 "$QB" raise --repo "$T/repo" --branch "$BR-rz" --priority high "${QC[@]}" > "$T/out"; check "$?" "0" "raise --priority high on a forced finish: 0"
has "$T/out" "kept fleet:repo--rz at force" "  never lowered"
CLAUDECODE=1 CLAUDE_CODE_SESSION_ID=s-nomark python3 "$QB" raise --repo "$T/repo" --branch "$BR-rz" --priority force "${QC[@]}" > /dev/null 2> "$T/err"
check "$?" "2" "raise force without the mark: refused (it is on the Bash PATH)"
python3 "$QB" raise --repo "$T/repo" --branch "$BR-none" --priority high "${QC[@]}" > /dev/null; check "$?" "3" "no finish of the branch queued: 3, the caller goes its own way"
enq bd > /dev/null
python3 "$QB" raise --repo "$T/repo" --branch "$BR-bd" --priority high "${QC[@]}" > /dev/null; check "$?" "3" "  a build of the branch is no finish to raise: 3"
qreset
fin rd > /dev/null
python3 "$QB" raise --repo "$T/repo" --branch "$BR-rd" --priority high --dry-run "${QC[@]}" > "$T/out"
check "$(qget repo--rd priority)" "normal" "raise --dry-run: writes nothing"
has "$T/out" "would raise fleet:repo--rd to high" "  says what it would raise"
CLAUDE_UNATTENDED=dispatch python3 "$QB" raise --repo "$T/repo" --branch "$BR-rd" --priority high "${QC[@]}" > /dev/null 2> "$T/err"; check "$?" "2" \
  "unattended, no high record: raise refused"
REGATTA_UNATTENDED=dispatch python3 "$QB" raise --repo "$T/repo" --branch "$BR-rd" --priority high "${QC[@]}" > /dev/null 2> "$T/err"; check "$?" "2" \
  "  the marker under its new name alone: refused too"
"$B/dispatch" "$BR-rd" --repo "$T/repo" --priority high --note later > "$T/out" 2> "$T/err"; check "$?" "2" \
  "dispatch BRANCH --priority high --note on a branch whose finish is queued: refused, never a flag dropped"
has "$T/err" "takes no other flag" "  saying why"
check "$(qget repo--rd priority)" "normal" "  and nothing raised"
DISPATCH_MAX_RUNS=0 "$B/dispatch" "$BR-rd" --repo "$T/repo" --priority high > "$T/out" 2> "$T/err"; check "$?" "0" "dispatch BRANCH --priority high on a branch whose finish is queued: 0"
has "$T/out" "raised fleet:repo--rd to high (was normal)" "  raised in place"
has "$T/out" "no build queued" "  saying no build was queued"
check "$(qget repo--rd priority kind)" "high finish" "  the finish high, and still the branch's one entry"
"$B/dispatch" "$BR-rd" --repo "$T/repo" --priority high --dry-run > "$T/out" 2> "$T/err"; check "$?" "0" "  a dry run of it: 0"
has "$T/out" "kept fleet:repo--rd at high" "  (raise's own line)"
# the peer road always sends --at (its defaulted now), marked DISPATCH_AT_DEFAULT: no flag of the caller's
ATP="@$(( $(date +%s) + 90 ))"
DISPATCH_AT_DEFAULT=1 "$B/dispatch" "$BR-rd" --repo "$T/repo" --at "$ATP" --priority high --dry-run > "$T/out" 2> "$T/err"; check "$?" "0" \
  "a peer's ssh line (--at its defaulted now, DISPATCH_AT_DEFAULT): the raise goes on"
has "$T/out" "kept fleet:repo--rd at high" "  raise's line"
"$B/dispatch" "$BR-rd" --repo "$T/repo" --at "$ATP" --priority high --dry-run > "$T/out" 2> "$T/err"; check "$?" "2" "  an --at the caller typed: refused, never dropped"
"$B/dispatch" "$BR-rd" --repo "$T/repo" --priority high --account acct-b > "$T/out" 2> "$T/err"; check "$?" "2" \
  "--account beside a raise: refused, never dropped (the flags the landing review's list missed)"
has "$T/err" "--account" "  naming it"
"$B/dispatch" "$BR-rd" --repo "$T/repo" --priority high --if-room > "$T/out" 2> "$T/err"; check "$?" "2" "  --if-room too"
"$B/dispatch" "$BR-rd" --repo "$T/repo" --priority high --on auto > "$T/out" 2> "$T/err"; check "$?" "2" "  --on auto too (it clears \$on and sets on_auto alone)"
# a "kept" outcome used no force: the session's mark stays (raise spends it only when it raises)
mkdir -p "$FM"; : > "$FM/s-suite"
CLAUDE_CODE_SESSION_ID=s-suite python3 "$QB" raise --repo "$T/repo" --branch "$BR-rd" --priority force "${QC[@]}" > /dev/null
check "$(qget repo--rd priority) $([ -f "$FM/s-suite" ] && echo kept || echo spent)" "force spent" "the finish raised to force, its mark spent"
: > "$FM/s-suite"
CLAUDE_CODE_SESSION_ID=s-suite "$B/dispatch" "$BR-rd" --repo "$T/repo" --priority force > "$T/out" 2> "$T/err"; check "$?" "0" "dispatch --priority force on a finish at force: 0"
has "$T/out" "kept fleet:repo--rd at force" "  kept, never raised"
check "$([ -f "$FM/s-suite" ] && echo kept || echo spent)" "kept" "  and the mark kept: a kept rank used no force"
rm -f "$FM/s-suite"
python3 "$QB" cancel --repo "$T/repo" --branch "$BR-rd" "${QC[@]}" > /dev/null
"$B/dispatch" "$BR-rd" --repo "$T/repo" --priority high --dry-run > "$T/out" 2> "$T/err"
hasnt "$T/out" "raised fleet:repo--rd" "its finish cancelled (a tombstone): no raise, the build road goes on"
hasnt "$T/out" "kept fleet:repo--rd" "  nor a kept one"
# a brief whose `After:` line names a predecessor: its --after is the branch's own, no flag of the caller's
qreset
git -C "$T/repo" checkout -q -b "$BR-ra" main; mkdir -p "$T/repo/docs/handoff"
printf 'brief\nAfter: %s\n' "$BR-d2" > "$T/repo/docs/handoff/2026-10-28-ra.md"
git -C "$T/repo" add docs; git -C "$T/repo" commit -qm seed; git -C "$T/repo" push -q origin "$BR-ra" 2>/dev/null; git -C "$T/repo" checkout -q main
fin ra > /dev/null
DISPATCH_MAX_RUNS=0 "$B/dispatch" "$BR-ra" --repo "$T/repo" --priority high > "$T/out" 2> "$T/err"; check "$?" "0" \
  "dispatch --priority high on a queued finish whose brief names an After: predecessor: 0, never \"no other flag\""
has "$T/out" "raised fleet:repo--ra to high (was normal)" "  raised in place"
DISPATCH_MAX_RUNS=0 "$B/dispatch" "$BR-ra" --repo "$T/repo" --priority high --after "$BR-rd" > "$T/out" 2> "$T/err"; check "$?" "2" \
  "  an --after the brief does not name: a flag, refused"
has "$T/err" "takes no other flag" "  saying why"

echo "force-any: dispatch --start --priority"
qreset
CLAUDE_UNATTENDED=dispatch "$B/dispatch" --start "/finish x --unattended" "$T/repo" "finish · x" --priority low > /dev/null 2> "$T/err"; check "$?" "2" "--start --priority low: refused"
has "$T/err" "--start takes --priority normal, high or force" "  naming the three a finish's start takes"

rm -f "$REGATTA_CONFIG/wharf-runs/queue-repo"
[ "$fails" = 0 ] && echo "all ok" || { echo "$fails FAILED"; exit 1; }
