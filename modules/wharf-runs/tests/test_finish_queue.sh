#!/usr/bin/env bash
# Tests for finish-as-task (the owner's D3 of node-lands: "The finish should be handled like any other task"): a
# /finish is one fleet entry of kind finish, under its branch's own key, claimed through the build's claim by any
# host with room, pinned only where it must be, ranked ahead of a build of the same priority; one run per tip from
# the queue alone (a live finish is busy, an ended one leaves a tombstone); a cancel that sticks; the claimed job's
# start, which reads its rights from the entry and holds the claim; and the migration of the Mac-local landing
# queue. Two hosts, `laptop` and `buildbox` (config_fixture.sh's pair), share one scratch HOME and queue home: a
# claim names its host with --host, as dispatch passes it. Scratch HOME, bare repos as origin and the queue's home,
# stand-ins for launchctl and dispatch --start; no launchd job, session or network is touched. Every name is synthetic.
#   bash modules/wharf-runs/tests/test_finish_queue.sh
set -u
unset WEEKLY_RUN CLAUDE_UNATTENDED REGATTA_UNATTENDED CLAUDECODE CLAUDE_CODE_DISABLE_BACKGROUND_TASKS CLAUDE_CODE_SESSION_ID CLAUDE_CONFIG_DIR XPC_SERVICE_NAME AUTOFINISH_CALLER_UNATTENDED
for v in $(env | sed -nE 's/^((DISPATCH|RUN_SEED|SKIPPER|HELM|AUTOFINISH)_[A-Za-z0-9_]*)=.*/\1/p'); do unset "$v"; done   # a fixed list goes stale
unset CLAUDE_CODE_OAUTH_TOKEN CLAUDE_REPOS_JSON
B="$(cd "$(dirname "$0")/../bin" && pwd)"
T=$(mktemp -d)
PIDS=()
trap 'for p in "${PIDS[@]+"${PIDS[@]}"}"; do kill "$p" 2>/dev/null; done; rm -rf "$T"' EXIT
. "$(cd "$(dirname "$0")" && pwd)/config_fixture.sh"; fixture_config "$T/config"
fails=0
check() { if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3: expected [$2] got [$1]"; fails=$((fails+1)); fi; }
has()   { if grep -qF -- "$2" "$1" 2>/dev/null; then echo "  ok   $3"; else echo "  FAIL $3: missing [$2]"; sed 's/^/         | /' "$1" 2>/dev/null | head -20; fails=$((fails+1)); fi; }
hasnt() { if grep -qF -- "$2" "$1" 2>/dev/null; then echo "  FAIL $3: unexpected [$2]"; sed 's/^/         | /' "$1" | head -20; fails=$((fails+1)); else echo "  ok   $3"; fi; }
export PYTHONUSERBASE="${PYTHONUSERBASE:-$(python3 -m site --user-base)}"
export HOME="$T/h"; HL="$T/h/Library"; mkdir -p "$HL/LaunchAgents"
# a recursive delete under HOME goes through rm_own: only under this suite's own $T (the core's check, home_rm)
rm_own() { local p; for p; do case "$p" in */..|*/../*|*//*) ;; "${T:?}"/?*) rm -rf -- "$p"; continue ;; esac; echo "rm_own: refused $p, outside $T" >&2; return 1; done; }
export ACCOUNTS_FILE="$T/no-accounts.json"
# a moved HOME drops the global git identity (AGENTS.md: a suite that moves HOME and commits)
printf '[user]\n\tname = t\n\temail = t@t\n[init]\n\tdefaultBranch = main\n' > "$T/gitconfig"; export GIT_CONFIG_GLOBAL="$T/gitconfig"
cat > "$T/launchctl" <<EOF
#!/bin/sh
echo "\$*" >> "$T/calls"
exit 0
EOF
chmod +x "$T/launchctl"
export DISPATCH_LAUNCHCTL="$T/launchctl" DISPATCH_DEFAULT_ON= DISPATCH_HOST=laptop AUTOFINISH_HOST=laptop
git init -q --bare "$T/origin.git"
git clone -q "$T/origin.git" "$T/repo" 2>/dev/null
(cd "$T/repo" && printf -- '- check: `true`\n- physical: none\n' > AGENTS.md && echo x > f && git add . && git commit -qm init && git push -q origin main)
git init -q --bare "$T/queue.git"
echo "$T/queue.git" > "$REGATTA_CONFIG/wharf-runs/queue-repo"
BR=claude/laptop/2026-11-02
QB="$B/dispatch-queue"; LA="$HL/LaunchAgents"; QL="$HL/Logs/claude-weekly/queue.jsonl"
QL2=(--host laptop --cap 2 --launchctl "$T/launchctl" --prefix org.example.claude --jobbin "$B/dispatch")
QB2=(--host buildbox --cap 2 --launchctl "$T/launchctl" --prefix org.example.claude --jobbin "$B/dispatch")
QGIT=(git --git-dir="$T/queue.git")
cat > "$T/qget.py" <<'PY'
import json, sys
d = json.load(sys.stdin)
print(" ".join(json.dumps(d.get(k), sort_keys=True) if isinstance(d.get(k), (list, dict)) else str(d.get(k)) for k in sys.argv[1:]))
PY
cat > "$T/jget.py" <<'PY'
import json, sys
d = json.loads(sys.stdin.read().strip().splitlines()[-1])
print(" ".join(str(d.get(k)) for k in sys.argv[1:]))
PY
qget() { local k=$1; shift; "${QGIT[@]}" show "refs/regatta/queue:queue/$k.json" 2>/dev/null | python3 "$T/qget.py" "$@" 2>/dev/null; }
qreset() {
  { for p in "${PIDS[@]+"${PIDS[@]}"}"; do kill "$p"; wait "$p"; done; } 2>/dev/null; PIDS=()
  "${QGIT[@]}" update-ref -d refs/regatta/queue 2>/dev/null
  rm_own "$HL/Caches/run-seed/queue" "$HL/Caches/run-seed/queue-local" "$HL/Logs/claude-weekly/run-seed-runs"
  rm_own "$LA"/*.plist; rm -f "$T/calls" "$QL"
}
mkbranch() {   # NAME: a claude/* branch with a commit of its own, pushed; its tip on stdout
  git -C "$T/repo" checkout -q -B "$BR-$1" main; echo "$1" > "$T/repo/f-$1"; git -C "$T/repo" add "f-$1"
  git -C "$T/repo" commit -qm "build $1"; git -C "$T/repo" push -q origin "$BR-$1" 2>/dev/null; git -C "$T/repo" checkout -q main
  git -C "$T/repo" rev-parse "$BR-$1"
}
RIGHTS='{"by": "sweep", "rule": "A", "from": "laptop"}'
RIGHTS_B='{"by": "sweep", "rule": "A", "from": "buildbox"}'   # a put on buildbox names buildbox: `from` is the putting host
fin() {   # NAME TIP [RIGHTS] [enqueue flags…]: a finish put, as autofinish-run's dispatch --queue-finish puts one
  local n=$1 tip=$2 r=${3:-$RIGHTS}; shift 3 2>/dev/null || shift $#
  python3 "$QB" enqueue --kind finish --repo "$T/repo" --branch "$BR-$n" --tip "$tip" --finish "$r" "$@"
}
claimed_by() { qget "repo--$1" state claimed_by; }

echo "a finish is one entry of kind finish: its rights read, never a prompt or a list"
qreset
TA=$(mkbranch a)
fin a "$TA" "$RIGHTS" "${QL2[@]}" > "$T/out"; check "$?" "0" "put: exit 0"
check "$(python3 "$T/jget.py" result qid < "$T/out")" "queued fleet:repo--a" "  under the branch's own key, in the fleet store"
check "$(qget repo--a kind tip args env)" "finish $TA [] {}" "  kind finish, its tip, no dispatch flag or environment"
check "$(qget repo--a finish)" '{"by": "sweep", "from": "laptop", "rule": "A"}' "  its rights as given"
for bad in '{"by": "sweep", "rule": "A", "merge": true}' '{"by": "someone", "rule": "A"}' '{"by": "typed", "rule": "Z"}' \
           '{"by": "typed", "rule": "A", "prompt": "/finish x --merge"}' '{"by": "typed", "rule": "A", "from": "Not A Host"}' \
           '{"by": "typed", "rule": "A", "merge": true, "hold": true}' 'not json'; do
  fin bad "$TA" "$bad" "${QL2[@]}" > /dev/null 2> "$T/err"; check "$?" "2" "refused, never queued: $bad"
done
check "$(qget repo--bad state)" "" "  nothing of them queued"
CLAUDE_UNATTENDED=1 fin bad "$TA" '{"by": "typed", "rule": "C", "merge": true, "from": "laptop"}' "${QL2[@]}" > /dev/null 2> "$T/err"
check "$?" "2" "an unattended caller's finish carrying merge: refused (a person's yes)"
has "$T/err" "an unattended caller never puts one" "  saying why"
REGATTA_UNATTENDED=1 fin bad "$TA" '{"by": "override", "rule": "C", "merge": true, "from": "laptop"}' "${QL2[@]}" > /dev/null 2>&1
check "$?" "2" "  under the marker's new name too"
fin bad "$TA" '{"by": "sweep", "rule": "A", "from": "buildbox"}' "${QL2[@]}" > /dev/null 2> "$T/err"; check "$?" "2" "a \`from\` other than the putting host: refused"
CLAUDE_UNATTENDED=1 fin una "$TA" "$RIGHTS" "${QL2[@]}" > /dev/null; check "$?" "0" "an unattended caller's plain finish: queued (no depth env rides on a finish)"
check "$(qget repo--una env unattended)" "{} True" "  marked unattended, carrying no env"
fin bad short "$RIGHTS" "${QL2[@]}" > /dev/null 2>&1; check "$?" "2" "a tip that is no full sha: refused"
fin bad "$TA" "$RIGHTS" "${QL2[@]}" --arg --model --arg opus > /dev/null 2>&1; check "$?" "2" "a dispatch flag on a finish: refused"
python3 "$QB" enqueue --repo "$T/repo" --branch "$BR-bad" --tip "$TA" "${QL2[@]}" > /dev/null 2>&1; check "$?" "2" "--tip without --kind finish: refused"

echo "an unpinned finish is claimed by another host with room"
qreset
TA=$(mkbranch a)
fin a "$TA" "$RIGHTS" --prefer laptop --claim --cap 0 --host laptop --launchctl "$T/launchctl" --prefix org.example.claude --jobbin "$B/dispatch" > "$T/out"
check "$(python3 "$T/jget.py" claimed < "$T/out")" "[]" "the putting host full (cap 0): not claimed there"
check "$(qget repo--a state prefer prefer_off | cut -d' ' -f1-2)" "queued laptop" "  preferring it, and released (prefer_off) at once for want of room"
check "$([ -n "$(qget repo--a prefer_off)" ] && [ "$(qget repo--a prefer_off)" != None ] && echo set)" "set" "  …so no peer waits out the grace"
python3 "$QB" claim "${QB2[@]}" > "$T/out" 2>&1
check "$(claimed_by a)" "claimed buildbox" "buildbox's claim takes it: the build's claim, for a finish"
P=$(ls "$LA"/org.example.claude.dispatch.repo.a.q*.plist 2>/dev/null | head -1)
check "$(python3 -c 'import plistlib, sys; print(" ".join(plistlib.load(open(sys.argv[1], "rb"))["ProgramArguments"][1:]))' "$P" 2>&1)" \
  "$BR-a --repo $(cd "$T/repo" && pwd -P) --finish --from-queue fleet:repo--a" "  its job: dispatch --finish under this claim (the rights stay in the entry)"
check "$(python3 "$QB" mine fleet:repo--a --label "$(qget repo--a job)" --json --host buildbox | python3 "$T/jget.py" kind tip)" "finish $TA" \
  "  mine --json: the job reads its entry under its own claim"
python3 "$QB" mine fleet:repo--a --label "$(qget repo--a job)" --json --host laptop > /dev/null; check "$?" "3" "  and no other host's job does"

echo "a pinned finish is claimed only on its host"
qreset
TP=$(mkbranch p)
fin p "$TP" "$RIGHTS" --pin laptop "${QL2[@]}" > /dev/null
python3 "$QB" claim "${QB2[@]}" > /dev/null
check "$(qget repo--p state host)" "queued laptop" "buildbox's claim passes it over: pinned to laptop"
python3 "$QB" claim "${QL2[@]}" > /dev/null
check "$(claimed_by p)" "claimed laptop" "  laptop's claim takes it"
# a put preferring this host whose worktree here holds what origin lacks: pinned there at the put (held_here)
git -C "$T/repo" worktree add -q "$T/wt-h" -b "$BR-h" main; echo h > "$T/wt-h/f-h"; git -C "$T/wt-h" add -A; git -C "$T/wt-h" commit -qm "unpushed"
fin h "$(git -C "$T/wt-h" rev-parse HEAD)" "$RIGHTS" --prefer laptop "${QL2[@]}" > /dev/null
check "$(qget repo--h host)" "laptop" "a finish whose commits only its worktree here holds: pinned here"
has <(qget repo--h pinned_why) "commits origin lacks" "  saying why"

echo "a finish ranks ahead of a build of the same priority, and is otherwise ranked the same"
qreset
TR=$(mkbranch r)
python3 "$QB" enqueue --repo "$T/repo" --branch "$BR-build" "${QL2[@]}" > /dev/null
sleep 1
fin r "$TR" "$RIGHTS" "${QL2[@]}" > /dev/null
python3 "$QB" enqueue --repo "$T/repo" --branch "$BR-hi" --priority high "${QL2[@]}" > /dev/null
python3 "$QB" list --json "${QL2[@]}" | python3 -c 'import json,sys; print(" ".join(e["topic"] for e in json.load(sys.stdin)["entries"] if e["state"] == "queued"))' > "$T/out"
check "$(cat "$T/out")" "hi r build" "a high build, then the normal finish ahead of the older normal build"
python3 "$QB" claim --host laptop --cap 1 --launchctl "$T/launchctl" --prefix org.example.claude --jobbin "$B/dispatch" > /dev/null
check "$(qget repo--hi state) $(qget repo--r state) $(qget repo--build state)" "claimed queued queued" "one slot: the high build takes it"
# one HOME stands for both hosts here, so buildbox counts laptop's claim too: its cap 2 is one slot
python3 "$QB" claim --host buildbox --cap 2 --launchctl "$T/launchctl" --prefix org.example.claude --jobbin "$B/dispatch" > /dev/null
check "$(qget repo--r state) $(qget repo--build state)" "claimed queued" "  the next slot: the finish, ahead of the build of its priority"

echo "one run per tip, from the queue alone"
qreset
TO=$(mkbranch o)
fin o "$TO" "$RIGHTS_B" "${QB2[@]}" > /dev/null; python3 "$QB" claim "${QB2[@]}" > /dev/null
fin o "$TO" '{"by": "typed", "rule": "C", "from": "laptop"}' "${QL2[@]}" > "$T/out"; check "$?" "3" "a second start of a claimed finish, from any host: busy (exit 3)"
check "$(python3 "$T/jget.py" result < "$T/out")" "busy claimed on buildbox (a finish)" "  saying where it runs"
python3 "$QB" started fleet:repo--o --label "$(qget repo--o job)" --session s-o "${QB2[@]}" > /dev/null
fin o "$TO" "$RIGHTS_B" "${QB2[@]}" > "$T/out"; check "$?" "3" "  running: busy, from its own host too"
check "$(python3 "$T/jget.py" result < "$T/out")" "busy running on buildbox (a finish)" "  never a second finish queued behind it"
python3 "$QB" enqueue --repo "$T/repo" --branch "$BR-o" "${QL2[@]}" > "$T/out"; check "$?" "3" "  a build put on a running finish from another host: busy, as on any live entry"
python3 "$QB" ended --repo "$T/repo" --branch "$BR-o" --session s-o "${QB2[@]}" > /dev/null
check "$(qget repo--o state ran_on tip)" "ended buildbox $TO" "its run's end leaves a tombstone: ended, where, which tip"
python3 "$QB" list "${QL2[@]}" > "$T/out"; hasnt "$T/out" "repo--o" "  which the plain list leaves out"
python3 "$QB" list --all "${QL2[@]}" > "$T/out"; has "$T/out" "ran ${TO:0:7} on buildbox: its end not recorded yet" "  and --all shows"
python3 "$QB" finished fleet:repo--o --session s-o --outcome stopped --gate G4 "${QB2[@]}" > /dev/null
check "$(qget repo--o outcome gate)" "stopped G4" "autofinish-run's record() writes the outcome into it"
python3 "$QB" finished fleet:repo--o --session s-other --outcome launched "${QB2[@]}" > "$T/out"
check "$(qget repo--o outcome)" "stopped" "  another session's word moves nothing"
fin o "$TO" "$RIGHTS" "${QL2[@]}" > "$T/out"; check "$?" "3" "the same tip again, by the sweep of another host: refused"
check "$(python3 "$T/jget.py" result < "$T/out")" "ran ${TO:0:7} on buildbox: stopped G4" "  naming the run that holds it"
python3 "$QB" has --repo "$T/repo" --branch "$BR-o" "${QL2[@]}" > /dev/null; check "$?" "0" "  a tombstone is no entry to \`has\` (yolo_launch, the one-shot's check)"
check "$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import queue_holds as q; h = q.Holds(sys.argv[2]); print(h.why(sys.argv[3], sys.argv[4]), (h.ended(sys.argv[3], sys.argv[4]) or {}).get("tip"))' "$B" "$QB" "$T/repo" "$BR-o")" \
  "None $TO" "queue_holds: no next step, and the tombstone for the sweep to read"
git -C "$T/repo" checkout -q "$BR-o"; git -C "$T/repo" commit -q --allow-empty -m more; git -C "$T/repo" push -q origin "$BR-o" 2>/dev/null; git -C "$T/repo" checkout -q main
TO2=$(git -C "$T/repo" rev-parse "$BR-o")
fin o "$TO2" "$RIGHTS" "${QL2[@]}" > "$T/out"; check "$?" "0" "a new tip takes the tombstone's place"
check "$(qget repo--o state tip)" "queued $TO2" "  queued at that tip"
python3 "$QB" claim "${QL2[@]}" > /dev/null; python3 "$QB" started fleet:repo--o --label "$(qget repo--o job)" --session s-o2 "${QL2[@]}" > /dev/null
python3 "$QB" finished fleet:repo--o --session s-o2 --outcome never-started --gate never-started "${QL2[@]}" > /dev/null
check "$(qget repo--o state outcome)" "ended never-started" "a session that started and never replied holds its tip (as autofinish-run's same-tip rule does)"
fin o "$TO2" "$RIGHTS" "${QL2[@]}" > /dev/null; check "$?" "3" "  the sweep's put of it: refused"
fin o "$TO2" '{"by": "typed", "rule": "C", "from": "laptop"}' "${QL2[@]}" > /dev/null; check "$?" "3" "  a person's too: a new commit starts it, as on the old road"
python3 "$QB" cancel --repo "$T/repo" --branch "$BR-o" "${QL2[@]}" > /dev/null
git -C "$T/repo" checkout -q "$BR-o"; git -C "$T/repo" commit -q --allow-empty -m again; git -C "$T/repo" push -q origin "$BR-o" 2>/dev/null; git -C "$T/repo" checkout -q main
TO3=$(git -C "$T/repo" rev-parse "$BR-o")
fin o "$TO3" "$RIGHTS" "${QL2[@]}" > /dev/null; python3 "$QB" claim "${QL2[@]}" > /dev/null
python3 "$QB" started fleet:repo--o --label "$(qget repo--o job)" --session s-o3 "${QL2[@]}" > /dev/null
python3 "$QB" finished fleet:repo--o --session s-o3 --outcome never-started --gate refused "${QL2[@]}" > /dev/null
check "$(qget repo--o state)" "" "a start dispatch refused before any session takes its tombstone away: the tip may start again"
qreset
TD=$(mkbranch d)
fin d "$TD" "$RIGHTS_B" "${QB2[@]}" > /dev/null; python3 "$QB" claim "${QB2[@]}" > /dev/null
python3 "$QB" started fleet:repo--d --label "$(qget repo--d job)" --session s-d "${QB2[@]}" > /dev/null
python3 "$QB" finished fleet:repo--d --session s-d --outcome died "${QB2[@]}" > /dev/null
check "$(qget repo--d outcome died_n)" "died 1" "a death counted in the tombstone (the putting host keeps no record of a run elsewhere)"
fin d "$TD" "$RIGHTS" "${QL2[@]}" > /dev/null; check "$?" "0" "a run that died: its tip may start again (the sweep's one retry)"
check "$(qget repo--d died_n)" "1" "  the retry carries the count"
python3 "$QB" claim "${QL2[@]}" > /dev/null; python3 "$QB" started fleet:repo--d --label "$(qget repo--d job)" --session s-d2 "${QL2[@]}" > /dev/null
python3 "$QB" finished fleet:repo--d --session s-d2 --outcome died "${QL2[@]}" > /dev/null
fin d "$TD" "$RIGHTS" "${QL2[@]}" > "$T/out"; check "$?" "3" "died twice: the sweep's put is refused"
check "$(python3 "$T/jget.py" result < "$T/out")" "ran ${TD:0:7} on laptop: died 2 times" "  saying so"
fin d "$TD" '{"by": "typed", "rule": "C", "from": "laptop"}' "${QL2[@]}" > /dev/null; check "$?" "0" "  a person's /finish of it still goes"
# a start that never ran (a fetch that failed, origin without the tip) ends `failed`: it holds the sweep, never a person
TF=$(mkbranch fl)
fin fl "$TF" "$RIGHTS_B" "${QB2[@]}" > /dev/null; python3 "$QB" claim "${QB2[@]}" > /dev/null
python3 "$QB" failed fleet:repo--fl --label "$(qget repo--fl job)" --why "fetching origin's branch failed here" "${QB2[@]}" > /dev/null
check "$(qget repo--fl state outcome)" "ended failed" "a claimed finish that failed before its start: its tombstone says failed"
fin fl "$TF" "$RIGHTS" "${QL2[@]}" > /dev/null; check "$?" "3" "  the sweep's put of that tip: refused"
fin fl "$TF" '{"by": "override", "rule": "C", "from": "laptop"}' "${QL2[@]}" > /dev/null; check "$?" "0" \
  "  a person's /finish of it: queued (nothing ran, so the tip is theirs to try again)"

echo "a cancelled finish stays cancelled: nothing queues it again unasked"
qreset
TC=$(mkbranch c)
fin c "$TC" "$RIGHTS" "${QL2[@]}" > /dev/null
python3 "$QB" cancel --repo "$T/repo" --branch "$BR-c" "${QL2[@]}" > "$T/out"; check "$?" "0" "dispatch BRANCH --cancel's verb on a queued finish: 0"
has "$T/out" "cancelled the queue entry fleet:repo--c" "  saying so"
check "$(qget repo--c state outcome)" "ended cancelled" "  its tombstone says cancelled"
fin c "$TC" "$RIGHTS" "${QL2[@]}" > "$T/out"; check "$?" "3" "the sweep's put of that tip: refused"
check "$(python3 "$T/jget.py" result < "$T/out")" "ran ${TC:0:7} on ?: cancelled" "  naming the cancel"
fin c "$TC" '{"by": "chain", "rule": "C", "from": "laptop"}' "${QL2[@]}" > /dev/null; check "$?" "3" "  a chain relaunch: refused too"
CLAUDE_UNATTENDED=1 fin c "$TC" '{"by": "override", "rule": "C", "from": "laptop"}' "${QL2[@]}" > /dev/null; check "$?" "3" \
  "an unattended caller's --by override: no person, the cancel stands"
SKIPPER_SCOPE=s fin c "$TC" '{"by": "override", "rule": "C", "from": "laptop"}' "${QL2[@]}" > /dev/null; check "$?" "3" \
  "a skipper's --by override: no person either, the cancel stands"
fin c "$TC" '{"by": "typed", "rule": "C", "from": "laptop"}' "${QL2[@]}" > /dev/null; check "$?" "0" "a person's /finish of it: queued"
fin c2 "$(mkbranch c2)" "$RIGHTS_B" "${QB2[@]}" > /dev/null; python3 "$QB" claim "${QB2[@]}" > /dev/null
J=$(qget repo--c2 job)
python3 "$QB" cancel --repo "$T/repo" --branch "$BR-c2" "${QB2[@]}" > "$T/out"
check "$(qget repo--c2 state outcome)" "ended cancelled" "a claimed finish cancelled before its run: its tombstone, its job booted out"
has "$T/calls" "bootout gui/$(id -u)/$J" "  the job's bootout"
python3 "$QB" mine fleet:repo--c2 --label "$J" --host buildbox > /dev/null; check "$?" "3" "  and a job that fired anyway finds it no longer its claim"
# a claim's start asks `mine` again under the start lock (node-lands' finding 2): dispatch --start --queued of a cancelled claim
"$B/dispatch" --start "/finish $BR-c2 --unattended" "$T/repo" "finish · c2" --queued fleet:repo--c2 --dry-run > "$T/out" 2>&1; check "$?" "2" \
  "--queued without --job: refused"
"$B/dispatch" "$BR-c2" --repo "$T/repo" --finish > "$T/out" 2>&1; check "$?" "2" "--finish without its claim: refused"

echo "the claimed job's start: its worktree, its rights from the entry, the claim held"
qreset
TE=$(mkbranch e)
git -C "$T/repo" worktree add -q "$T/wt-e" "$BR-e" 2>/dev/null
cat > "$T/dispatch-start" <<EOF
#!/bin/bash
printf '%s\n' "\$@" > "$T/start.args"
sid=; prev=; for a in "\$@"; do [ "\$prev" = --session-id ] && sid=\$a; prev=\$a; done
echo "== claude 4242, session \$sid, screen s, Remote Control \"finish · e\""
EOF
chmod +x "$T/dispatch-start"
cat > "$T/api_stub.py" <<'PY'
def api(method, path, body=None, tok=None, timeout=15):
    return 404, None
PY
fin e "$TE" '{"by": "typed", "rule": "C", "merge": true, "from": "laptop"}' "${QL2[@]}" > /dev/null
python3 "$QB" claim "${QB2[@]}" > /dev/null
JE=$(qget repo--e job)
DISPATCH_HOST=buildbox AUTOFINISH_HOST=buildbox DISPATCH_LABEL="$JE" AUTOFINISH_DISPATCH="$T/dispatch-start" AUTOFINISH_END_WARM=true \
  AUTOFINISH_API_STUB="$T/api_stub.py" PICKUP_PRS="$T/none.json" AUTOFINISH_VERDICT_S=10 \
  "$B/dispatch" "$BR-e" --repo "$T/repo" --finish --from-queue fleet:repo--e > "$T/out" 2>&1; check "$?" "0" "dispatch --finish: the claim's job runs autofinish-run's queued half"
has "$T/out" "the claimed finish fleet:repo--e: $BR-e at ${TE:0:7}" "  naming the entry and its tip"
has "$T/start.args" "/finish $BR-e --unattended --merge --from=laptop" "  its prompt carries the entry's rights: the merge, and the host whose yes it is"
check "$(grep -A1 -- '--queued' "$T/start.args" | tr '\n' ' ')" "--queued fleet:repo--e " "  its dispatch --start holds the claim (--queued)…"
check "$(grep -A1 -- '--job' "$T/start.args" | tail -1)" "$JE" "  …under the job's label (--job)"
GE=$(git -C "$T/wt-e" rev-parse --absolute-git-dir)
check "$(python3 -c 'import json, sys; d = json.load(open(sys.argv[1])); print(d.get("queue"), d.get("from"), d.get("tip"))' "$GE/claude/autofinish.json")" \
  "fleet:repo--e laptop $TE" "  its state there names the queue entry, the putting host and the tip"
check "$(ls "$LA" | grep -c "$JE")" "0" "  its one-shot plist gone: a login never fires it again"
# a stale job (its entry gone) starts nothing
python3 "$QB" cancel --repo "$T/repo" --branch "$BR-e" "${QB2[@]}" > /dev/null
rm -f "$T/start.args"
DISPATCH_HOST=buildbox AUTOFINISH_HOST=buildbox DISPATCH_LABEL="$JE" AUTOFINISH_DISPATCH="$T/dispatch-start" \
  "$B/dispatch" "$BR-e" --repo "$T/repo" --finish --from-queue fleet:repo--e > "$T/out" 2>&1
has "$T/out" "a stale queue job" "a job whose claim is gone: not running"
check "$([ -f "$T/start.args" ] && echo started || echo none)" "none" "  no start"
# a claim whose tip origin has moved past: failed for good, its tombstone holding that tip
TM=$(mkbranch m)
fin m "$TM" "$RIGHTS" "${QL2[@]}" > /dev/null; python3 "$QB" claim "${QB2[@]}" > /dev/null; JM=$(qget repo--m job)
git -C "$T/repo" checkout -q "$BR-m"; git -C "$T/repo" commit -q --allow-empty -m "more since"; git -C "$T/repo" push -q origin "$BR-m" 2>/dev/null; git -C "$T/repo" checkout -q main
DISPATCH_HOST=buildbox AUTOFINISH_HOST=buildbox DISPATCH_LABEL="$JM" AUTOFINISH_DISPATCH="$T/dispatch-start" \
  "$B/dispatch" "$BR-m" --repo "$T/repo" --finish --from-queue fleet:repo--m > "$T/out" 2>&1
has "$T/out" "not the queued tip ${TM:0:7}" "origin moved past the queued tip: said"
check "$(qget repo--m state outcome)" "ended failed" "  failed: its tombstone holds the old tip (the sweep judges the new one)"

echo "autofinish-run's put: no state, lock or waiter on the putting host"
qreset
TU=$(mkbranch u)
git -C "$T/repo" worktree add -q "$T/wt-u" "$BR-u" 2>/dev/null
GU=$(git -C "$T/wt-u" rev-parse --absolute-git-dir)
DISPATCH_MAX_RUNS=0 AUTOFINISH_END_WARM=true CLAUDE_CODE_SESSION_ID=s-caller \
  "$B/autofinish-run" "$T/wt-u" --by typed --merge --session s-caller > "$T/out" 2>&1; check "$?" "0" "a typed /finish with a queue home: exit 0"
has "$T/out" "queued: fleet:repo--u (a finish of ${TU:0:7})" "  said as queued, the window named"
check "$(qget repo--u kind state prefer tip)" "finish queued laptop $TU" "  one fleet entry, preferring this host, at this tip"
check "$(qget repo--u finish)" '{"by": "typed", "from": "laptop", "hold": false, "merge": true, "rule": "C"}' "  carrying the typed yes to merge"
check "$(ls "$GU/claude/" 2>/dev/null | grep -cE '^(autofinish\.json|owner\.json|autofinish-waiter\.json)$')" "0" "  and nothing of a run written here: no state, no lock, no waiter"
DISPATCH_MAX_RUNS=0 AUTOFINISH_END_WARM=true CLAUDE_CODE_SESSION_ID=s-caller \
  "$B/autofinish-run" "$T/wt-u" --by sweep --rule A > "$T/out" 2>&1; check "$?" "0" "a second start of that tip while it waits: the finish in hand (exit 0), never a second"
has "$T/out" "queued already (by typed)" "  its rights kept: a sweep's put never lowers a person's yes"
check "$(qget repo--u finish | python3 -c 'import json,sys; print(json.load(sys.stdin)["merge"])')" "True" "  the entry still carries the merge"
TS=$(mkbranch s)
fin s "$TS" "$RIGHTS" "${QL2[@]}" > /dev/null
fin s "$TS" '{"by": "typed", "rule": "C", "merge": true, "from": "laptop"}' "${QL2[@]}" > "$T/out"; check "$?" "0" "a person's /finish --merge on a tip the sweep queued: taken"
check "$(python3 "$T/jget.py" result < "$T/out") $(qget repo--s finish | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["by"], d["merge"])')" \
  "replaced typed True" "  the entry carries the person's yes now, never dropped"
DISPATCH_MAX_RUNS=0 AUTOFINISH_END_WARM=true CLAUDE_CODE_SESSION_ID=s-caller \
  "$B/autofinish-run" "$T/wt-u" --by typed --on here --dry > "$T/out" 2>&1; check "$?" "0" "--on here --dry: says what it would put"
has "$T/out" "pinned here: --on here" "  pinned to this host"
echo "  a ladder pin on a host that cannot claim a finish goes to the fleet (principal tier S4's handed landing, 2026-11-04)"
DISPATCH_MAX_RUNS=0 AUTOFINISH_END_WARM=true CLAUDE_CODE_SESSION_ID=s-caller AUTOFINISH_PLATFORM=darwin \
  "$B/autofinish-run" "$T/wt-u" --by handed --dry > "$T/out" 2>&1; check "$?" "0" "  a handed landing on a Mac: --dry exit 0"
has "$T/out" "pinned here: a --by handed launch is judged by this host's plans" "  pinned to the Mac that judges it, as before"
DISPATCH_MAX_RUNS=0 AUTOFINISH_END_WARM=true CLAUDE_CODE_SESSION_ID=s-caller AUTOFINISH_PLATFORM=linux \
  "$B/autofinish-run" "$T/wt-u" --by handed --dry > "$T/out" 2>&1; check "$?" "0" "  the same off a Mac with no feature line: --dry exit 0"
has "$T/out" "not pinned here (a --by handed launch is judged by this host's plans (mode ask holds it)): this host cannot claim a finish" "  said why it is not pinned"
has "$T/out" "any host with room claims it, this one first" "  put for any host, this one preferred"
hasnt "$T/out" "--pin laptop" "  no --pin in the put"
echo "laptop: finish-queue" > "$REGATTA_CONFIG/wharf-runs/features"
DISPATCH_MAX_RUNS=0 AUTOFINISH_END_WARM=true CLAUDE_CODE_SESSION_ID=s-caller AUTOFINISH_PLATFORM=linux \
  "$B/autofinish-run" "$T/wt-u" --by handed --dry > "$T/out" 2>&1
has "$T/out" "pinned here: a --by handed launch" "  off a Mac with a finish-queue feature line: pinned here, as on a Mac"
DISPATCH_MAX_RUNS=0 AUTOFINISH_END_WARM=true CLAUDE_CODE_SESSION_ID=s-caller AUTOFINISH_PLATFORM=linux \
  "$B/autofinish-run" "$T/wt-u" --by handed --on here --dry > "$T/out" 2>&1
has "$T/out" "pinned here: --on here" "  a typed --on here stays pinned whatever the host"
rm -f "$REGATTA_CONFIG/wharf-runs/features"
DISPATCH_MAX_RUNS=0 AUTOFINISH_END_WARM=true CLAUDE_CODE_SESSION_ID=s-caller AUTOFINISH_PLATFORM=linux \
  "$B/autofinish-run" "$T/wt-u" --by handed --on here --dry > "$T/out" 2>&1
has "$T/out" "pinned here: --on here" "  …and with no feature line too (the caller's word: it waits unclaimed, as before)"
echo "  a ladder hold off a host that cannot claim a finish rides in the rights: held, never a merge"
mkbranch lh > /dev/null
git -C "$T/repo" checkout -q "$BR-lh"; printf 'a\000b' > "$T/repo/blob.bin"; git -C "$T/repo" add blob.bin
git -C "$T/repo" commit -qm "a binary"; git -C "$T/repo" push -q origin "$BR-lh" 2>/dev/null; git -C "$T/repo" checkout -q main
git -C "$T/repo" worktree add -q "$T/wt-lh" "$BR-lh" 2>/dev/null
DISPATCH_MAX_RUNS=0 AUTOFINISH_END_WARM=true CLAUDE_CODE_SESSION_ID=s-caller AUTOFINISH_PLATFORM=linux \
  "$B/autofinish-run" "$T/wt-lh" --by handed --dry > "$T/out" 2>&1; check "$?" "0" "  a held handed landing off a Mac: --dry exit 0"
has "$T/out" "this host cannot claim a finish (no finish-queue), so any host with room takes it, held at a ready PR" "  said as held, not pinned"
has "$T/out" '"hold": true, "merge": false' "  the put's rights hold it and carry no merge"
hasnt "$T/out" "--pin laptop" "  no --pin in the put"

echo "  claimed on its own host past the handover (OWN_FRESH_S), the panel that typed it holding the lock: its session is no refusal"
python3 - "$GU/claude" <<'PY'
import json, os, sys, time
os.makedirs(sys.argv[1], exist_ok=True)
json.dump({"session": "s-caller", "branch": "x", "seen": int(time.time())}, open(os.path.join(sys.argv[1], "owner.json"), "w"))
PY
python3 "$QB" claim "${QL2[@]}" > /dev/null; JU=$(qget repo--u job)
check "$(qget repo--u state by)" "claimed s-caller" "  claimed here, the entry naming the caller's session"
rm -f "$T/start.args"
AUTOFINISH_OWN_FRESH_S=0 DISPATCH_LABEL="$JU" AUTOFINISH_DISPATCH="$T/dispatch-start" AUTOFINISH_API_STUB="$T/api_stub.py" PICKUP_PRS="$T/none.json" AUTOFINISH_VERDICT_S=10 \
  "$B/dispatch" "$BR-u" --repo "$T/repo" --finish --from-queue fleet:repo--u > "$T/out" 2>&1; check "$?" "0" "  its job runs"
check "$([ -f "$T/start.args" ] && echo started || echo refused)" "started" "  and starts: the lock is the putting caller's own"
hasnt "$T/out" "lock is held" "  no lock refusal"

echo "the landing review (2026-11-03): an unreadable put, another tip's finish held by another session"
cat > "$T/dispatch-crash" <<'SH'
#!/bin/sh
printf '%s\n' '{"result": "queued", "qid": "fleet:repo--u"}'
exit 5
SH
chmod +x "$T/dispatch-crash"
DISPATCH_MAX_RUNS=0 AUTOFINISH_END_WARM=true CLAUDE_CODE_SESSION_ID=s-caller AUTOFINISH_DISPATCH="$T/dispatch-crash" \
  "$B/autofinish-run" "$T/wt-u" --by typed --rule C > "$T/out" 2>&1; check "$?" "0" "a put the queue cannot confirm (exit 5): exit 0, never a refusal cold_prompt reads as not started"
has "$T/out" "not confirmed: the queue could not say whether the finish was put (exit 5)" "  saying so, and where to read it"
qreset
TX=$(mkbranch x); git -C "$T/repo" checkout -q "$BR-x"; echo more > "$T/repo/f-x2"; git -C "$T/repo" add f-x2
git -C "$T/repo" commit -qm "more x"; TX2=$(git -C "$T/repo" rev-parse HEAD); git -C "$T/repo" checkout -q main
fin x "$TX" "$RIGHTS_B" --by s-held --host buildbox --cap 0 --launchctl "$T/launchctl" --prefix org.example.claude --jobbin "$B/dispatch" > /dev/null
fin x "$TX2" "$RIGHTS" --by s-other --host laptop --cap 0 --launchctl "$T/launchctl" --prefix org.example.claude --jobbin "$B/dispatch" > "$T/out"
check "$? $(python3 "$T/jget.py" result < "$T/out")" "3 busy queued by session s-held" \
  "a finish of another tip over one another live session queued: a plain busy, never '(a finish)' (in hand), so the caller is refused"
check "$(qget repo--x tip)" "$TX" "  the held entry kept"

echo "round 2: the words, the end line, a death on an ended entry, a live build, the unattended mark"
check "$(python3 - "$B" <<'PY'
import importlib.util, sys
from importlib.machinery import SourceFileLoader
def load(n, f):
    ld = SourceFileLoader(n, f); m = importlib.util.module_from_spec(importlib.util.spec_from_loader(n, ld)); ld.exec_module(m); return m
a = load("afr", sys.argv[1] + "/autofinish-run"); q = load("dq", sys.argv[1] + "/dispatch-queue")
print(tuple(a.BY_WORDS) == tuple(q.FINISH_BY), set(a.PERSON_BY) == set(q.FINISH_PERSON))
PY
)" "True True" "dispatch-queue's FINISH_BY and FINISH_PERSON are autofinish-run's own words"
qreset
TW=$(mkbranch w)
fin w "$TW" "$RIGHTS" "${QL2[@]}" > /dev/null; python3 "$QB" claim "${QB2[@]}" > /dev/null
python3 "$QB" started fleet:repo--w --label "$(qget repo--w job)" --session s-w "${QB2[@]}" > /dev/null
python3 "$QB" ended --repo "$T/repo" --branch "$BR-w" --session s-w "${QB2[@]}" > /dev/null
python3 "$QB" finished fleet:repo--w --session s-w --outcome died --line "2026-11-02T18:00:00-08:00 died $BR-w ${TW:0:7} the run's last line" "${QB2[@]}" > /dev/null
check "$(qget repo--w state outcome died_n)" "ended died 1" "a death written on an entry its end word ended first: counted too"
AF="$(cd "$T/repo" && git rev-parse --absolute-git-dir)/claude/autofinished"
python3 "$QB" sweep "${QL2[@]}" > /dev/null 2>&1; python3 "$QB" sweep "${QL2[@]}" > /dev/null 2>&1
check "$(grep -c "died $BR-w ${TW:0:7}" "$AF" 2>/dev/null)" "1" "the putting host's sweep writes the end of its finish run elsewhere into its autofinished, once"
python3 "$QB" sweep "${QB2[@]}" > /dev/null 2>&1
check "$(grep -c "died $BR-w" "$AF" 2>/dev/null)" "1" "  the host that ran it writes nothing more (its own record() wrote its file)"
TL2=$(mkbranch lb)
python3 "$QB" enqueue --repo "$T/repo" --branch "$BR-lb" "${QL2[@]}" > /dev/null; python3 "$QB" claim "${QL2[@]}" > /dev/null
fin lb "$TL2" "$RIGHTS" "${QL2[@]}" > "$T/out"; check "$?" "3" "a finish put while a build step of the branch is claimed: busy"
check "$(python3 "$T/jget.py" result < "$T/out")" "busy claimed on laptop: a build step of the branch" "  saying why (never 'claimed here' over nothing queued)"
AUTOFINISH_CALLER_UNATTENDED=1 python3 "$QB" raise --repo "$T/repo" --branch "$BR-w" --priority high "${QL2[@]}" > /dev/null 2>&1; check "$?" "3" \
  "raise: no finish of a tombstoned branch queued (3)"
cat > "$T/unatt.py" <<'PY'
import importlib.util, json, os, sys
from importlib.machinery import SourceFileLoader
ld = SourceFileLoader("afr2", sys.argv[1]); m = importlib.util.module_from_spec(importlib.util.spec_from_loader("afr2", ld)); ld.exec_module(m)
os.environ["DISPATCH_LABEL"] = "lbl"; os.environ.pop("AUTOFINISH_CALLER_UNATTENDED", None)
entry = {"branch": "claude/laptop/2026-11-02-x", "tip": "a" * 40, "unattended": True, "by": "", "put_at": 0,
         "finish": {"by": "override", "rule": "C", "from": m.self_host()}}
m.queue_word = lambda *a: (0, json.dumps(entry), "") if a[0] == "mine" else (0, "", "")
m.queued_worktree = lambda *a, **k: ("/tmp", 0, None)
m.Tree = lambda p: (_ for _ in ()).throw(RuntimeError("no tree"))
seen = {}
def run_main(args):
    seen["env"] = os.environ.get("AUTOFINISH_CALLER_UNATTENDED"); seen["by"] = args.by; return 0
m.run_main = run_main
m.queued_main(["fleet:x", "--repo", "/tmp", "--branch", "claude/laptop/2026-11-02-x"])
print(seen.get("env"), seen.get("by"), m.unattended_caller())
PY
check "$(python3 "$T/unatt.py" "$B/autofinish-run" 2>/dev/null | tail -1)" "1 override True" \
  "an unattended put's claim is an unattended caller too: landing() never reads its --by override as a person"

# the finish review (2026-11-02): an entry pinned to this host, claimed past the put's handover (a full host), takes
# its worktree as it is when clean at the tip: the pin is often for commits origin lacks, which a fetch would fail for good
TP=$(mkbranch pn)
git -C "$T/repo" worktree add -q "$T/wt-pn" "$BR-pn" 2>/dev/null
git -C "$T/wt-pn" commit -q --allow-empty -m "not pushed"; TP2=$(git -C "$T/wt-pn" rev-parse HEAD)
cat > "$T/pinned.py" <<'PY'
import importlib.util, json, os, sys
from importlib.machinery import SourceFileLoader
sys.dont_write_bytecode = True
ld = SourceFileLoader("afr3", sys.argv[1]); m = importlib.util.module_from_spec(importlib.util.spec_from_loader("afr3", ld)); ld.exec_module(m)
repo, br, tip, wt = sys.argv[2:6]
os.environ["DISPATCH_LABEL"] = "lbl"
entry = {"branch": br, "tip": tip, "by": "", "put_at": 0, "host": m.self_host(), "finish": {"by": "sweep", "rule": "A", "from": m.self_host()}}
m.queue_word = lambda *a: (0, json.dumps(entry), "") if a[0] == "mine" else (0, "", "")
real, seen = m.queued_worktree, {}
def qw(*a, **k):
    seen.update(k); return None, 4, "stub"
m.queued_worktree = qw
m.queued_main(["fleet:x", "--repo", repo, "--branch", br])
out = [seen.get("own"), seen.get("pinned")]
out.append(real(repo, br, tip, pinned=True)[1])          # clean at the tip: taken (0), origin never asked
out.append(real(repo, br, tip)[1])                       # not pinned, not own: origin lacks the tip (5)
open(os.path.join(wt, "dirt"), "w").write("x")
out.append(real(repo, br, tip, pinned=True)[1])          # pinned but dirty: never as it is, handed back (3), never origin's 5 (the landing review)
print(" ".join(str(x) for x in out))
PY
check "$(python3 "$T/pinned.py" "$B/autofinish-run" "$T/repo" "$BR-pn" "$TP2" "$T/wt-pn" 2>/dev/null | tail -1)" "False True 0 5 3" \
  "a pinned finish claimed late on its own host: its clean worktree at the tip, never origin's refusal; a dirty one is handed back (3), never failed for good"
rm -f "$T/wt-pn/dirt"

echo "round 3: an old host never claims a finish; the putting worktree learns the end"
qreset
TK=$(mkbranch mk)
git -C "$T/repo" worktree add -q "$T/wt-mk" "$BR-mk" 2>/dev/null
GK=$(git -C "$T/wt-mk" rev-parse --absolute-git-dir); mkdir -p "$GK/claude"; echo '{"by": "sam", "now": true}' > "$GK/claude/autofinish"
fin mk "$TK" "$RIGHTS" "${QL2[@]}" > /dev/null
check "$(qget repo--mk needs)" '["finish-queue"]' "a finish needs finish-queue: every host on this code meets it, one on older code never claims it as a build"
python3 "$QB" claim "${QB2[@]}" > /dev/null
check "$(claimed_by mk)" "claimed buildbox" "  this code's hosts claim it, no feature line asked"
python3 "$QB" started fleet:repo--mk --label "$(qget repo--mk job)" --session s-mk "${QB2[@]}" > /dev/null
python3 "$QB" ended --repo "$T/repo" --branch "$BR-mk" --session s-mk "${QB2[@]}" > /dev/null
python3 "$QB" finished fleet:repo--mk --session s-mk --outcome stopped --gate no-landing \
  --line "2026-11-02T20:00:00-08:00 stopped $BR-mk no-landing API Error: Connection error." "${QB2[@]}" > /dev/null
python3 "$QB" sweep "${QL2[@]}" > /dev/null 2>&1
check "$(python3 -c 'import json, sys; d = json.load(open(sys.argv[1])); print(d["tip"] == sys.argv[2], d["outcome"], d["gate"], d["host"], d["ended"])' "$GK/claude/autofinish.json" "$TK")" \
  "True stopped no-landing buildbox 2026-11-02T20:00:00-08:00" "the putting worktree's state ends on that tip, where it ran (a chain relaunch's prev, the sweep's same-tip stop)"
check "$([ -f "$GK/claude/autofinish" ] && echo kept || echo spent)" "spent" "  and the /autofinish marker is spent: a yes for one run, never the next tip's"

# the finish review (2026-11-02): a host off a Mac meets finish-queue only by a feature line (the node, until
# node-lands-base), judging only itself; and two hosts' stamps compared as instants, never as strings
cat > "$T/builtin.py" <<'PY2'
import importlib.machinery, sys
sys.dont_write_bytecode = True   # no __pycache__ beside the tool (AGENTS.md: a tree scan meets CI's bytecode)
m = importlib.machinery.SourceFileLoader("dq", sys.argv[1]).load_module()
r = [m.builtin_met("finish-queue", "laptop"), m.builtin_met("finish-queue", "buildbox")]
m.sys.platform = "linux"
r += [m.builtin_met("finish-queue", "laptop"), m.builtin_met("finish-queue", "buildbox"), m.builtin_met("other", "buildbox")]
r += [m.iso_before("2026-11-02T20:00:00-08:00", "2026-11-03T03:00:00+00:00"), m.iso_before("2026-11-03T03:30:00+00:00", "2026-11-02T20:00:00-08:00")]
print(" ".join(str(x) for x in r))
PY2
check "$(python3 "$T/builtin.py" "$QB" 2>&1 | tail -1)" "True True False True False False True" \
  "finish-queue: met by code on a Mac, never by this host off one (a peer is judged on its own claim); stamps read as instants"

echo "the migration: the Mac-local landing queue moved into the fleet"
qreset
TL=$(mkbranch l)
git -C "$T/repo" worktree add -q "$T/wt-l" "$BR-l" 2>/dev/null
GL=$(git -C "$T/wt-l" rev-parse --absolute-git-dir)
mkdir -p "$GL/claude" "$HL/Caches/run-seed/queue-local/_land"
python3 - "$GL/claude" "$TL" "$HL/Caches/run-seed/queue-local/_land" "$BR" "$(cd "$T/repo" && pwd -P)" <<'PY'
import json, os, sys
d, tip, land, br, repo = sys.argv[1:6]
json.dump({"started": "2026-11-02T10:00:00-08:00", "session": "s-old", "tip": tip, "by": "typed", "rule": "C", "merge": True,
           "ended": "2026-11-02T10:05:00-08:00", "outcome": "never-started", "gate": "refused"}, open(os.path.join(d, "autofinish" + ".json"), "w"))
gone = {"id": "x1", "key": "repo--l", "repo": repo, "branch": br + "-l", "kind": "landing", "priority": "high", "state": "queued",
        "host": "laptop", "queued_at": 1, "waiter_pid": 999999, "waiter_start": "Sat Oct 31 12:00:00 2026"}
live = dict(gone, id="x2", key="repo--k", branch=br + "-k", waiter_pid=os.getppid(), waiter_start=None)
json.dump(gone, open(os.path.join(land, "repo--l.json"), "w"))
json.dump(live, open(os.path.join(land, "repo--k.json"), "w"))
PY
python3 "$QB" sweep "${QL2[@]}" > "$T/out" 2>&1
has "$T/out" "moved repo--l from this host's landing queue: queued" "the sweep moves each old landing into the fleet"
check "$(qget repo--l kind host priority tip)" "finish laptop high $TL" "  a fleet finish, pinned here (its worktree is), its rank and tip kept"
check "$(qget repo--l finish)" '{"by": "typed", "from": "", "hold": false, "merge": true, "rule": "C"}' "  its rights from its state here: the typed yes to merge"
check "$(ls "$HL/Caches/run-seed/queue-local/_land" 2>/dev/null)" "" "  one whose dispatch still waits is moved too: its file gone, its next land-wait poll fails it"
python3 "$QB" list --json "${QL2[@]}" > "$T/out"
hasnt "$T/out" "local=_land" "  and the old folder is no store any reader lists"

echo
[ "$fails" = 0 ] && echo "test_finish_queue: all passed" || { echo "test_finish_queue: $fails failed"; exit 1; }
