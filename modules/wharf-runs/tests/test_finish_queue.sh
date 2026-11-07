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
fixture_finish_ready "$T/h/.acct-queue"   # a finish claim judges as on a Mac, whatever host runs the suite
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

echo "landing-floor: no host claims a finish below normal (the owner, 2026-11-06)"
qreset
TL=$(mkbranch lo); TN=$(mkbranch nm)
fin lo "$TL" "$RIGHTS" --priority low --prefer laptop "${QL2[@]}" > /dev/null; check "$?" "0" "a low finish: put (the floor is the claim's, not the put's)"
python3 "$QB" enqueue --repo "$T/repo" --branch "$BR-lowbuild" --priority low "${QL2[@]}" > /dev/null
python3 "$QB" claim "${QL2[@]}" > "$T/out" 2>&1
check "$(qget repo--lo state)" "queued" "a low finish is not claimed, with room to spare"
check "$(qget repo--lowbuild state)" "claimed" "  a low build in the same pass still is: builds have no floor"
python3 "$QB" list "${QL2[@]}" > "$T/out" 2>&1
has "$T/out" "a finish below normal is held (priority low): no host claims a landing below normal; raise it with \`autofinish-run <worktree> --priority high\`" "  the listing says why and how to lift it"
hasnt "$T/out" "waits for a run to end" "  in words that are not the cap's (helm's CAP_RE, the core's ASK_EXEMPT_RE)"
TL2=$(mkbranch lo2)
fin lo2 "$TL2" "$RIGHTS" --priority low "${QL2[@]}" > /dev/null   # no preference: nothing but the floor holds it from a peer
python3 "$QB" claim --host buildbox --cap 9 --launchctl "$T/launchctl" --prefix org.example.claude --jobbin "$B/dispatch" > /dev/null   # room to spare: one HOME stands for both hosts
check "$(qget repo--lo2 state)" "queued" "  no other host takes one either (unpreferred, so the floor alone holds it)"
check "$(qget repo--lo prefer prefer_off)" "laptop None" "  and, preferring this host as a real put does, the refusal releases nothing to a peer (no prefer_off)"
fin nm "$TN" "$RIGHTS" "${QL2[@]}" > /dev/null
python3 "$QB" claim --host laptop --cap 4 --launchctl "$T/launchctl" --prefix org.example.claude --jobbin "$B/dispatch" > /dev/null
check "$(qget repo--nm state) $(qget repo--lo state)" "claimed queued" "a finish with no flag (normal) is claimed in the pass that leaves the low one"
cat > "$T/floor.py" <<'PY'
import sys
sys.dont_write_bytecode = True
from importlib.machinery import SourceFileLoader
q = SourceFileLoader("dq", sys.argv[1]).load_module()
base = {"state": "queued", "branch": "claude/x/2026-11-06-t", "repo": sys.argv[2], "kind": "finish"}
for kind in ("finish", None):
    for p in ("low", "normal", "high", "force", None, "", "bogus", [], {}, ["low"]):
        e = dict(base, kind=kind) if kind else {k: v for k, v in base.items() if k != "kind"}
        if p is not None:
            e["priority"] = p
        print("%s %s: %s" % (kind or "build", p, "held" if q.floor_refusal(e) else "free"))
PY
python3 "$T/floor.py" "$QB" "$T/repo" > "$T/out" 2>&1
has "$T/out" "finish low: held" "a low finish is under the floor"
has "$T/out" "finish normal: free" "  a normal one is not"
has "$T/out" "finish high: free" "  a high one is not"
has "$T/out" "finish force: free" "  a force one is not"
has "$T/out" "finish None: free" "  one with no priority reads as normal"
has "$T/out" "finish bogus: free" "  a value no rank knows reads as normal, as rank() reads it"
has "$T/out" "finish []: free" "  an empty list reads as normal, and raises nothing"
has "$T/out" "build low: free" "a low build has no floor"

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
python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import common; print(common.consume_finish_pick(target="dispatch"))' "$B/../../regatta/hooks" > "$T/start.receipt"
sid=; prev=; for a in "\$@"; do [ "\$prev" = --session-id ] && sid=\$a; prev=\$a; done
echo "== claude 4242, session \$sid, screen s, Remote Control \"finish · e\""
EOF
chmod +x "$T/dispatch-start"
cat > "$T/api_stub.py" <<'PY'
def api(method, path, body=None, tok=None, timeout=15):
    return 404, None
PY
mkdir -p "$T/h/.acct-queue" "$REGATTA_CONFIG/lighthouse"
python3 - "$T/finish-accounts.json" "$T/h/.acct-queue" <<'PY'
import json, sys, time
json.dump({"accounts": [{"label": "acct-queue", "home": sys.argv[2], "primary": True,
                         "rules": {"week_max": 90}}]}, open(sys.argv[1], "w"))
json.dump({"at": time.time(), "limits": {"five_hour": 10, "seven_day": 92}},
          open(sys.argv[2] + "/usage-probe.json", "w"))
PY
printf 'acct-queue:97\n' > "$REGATTA_CONFIG/lighthouse/week-max-finish"
export ACCOUNTS_FILE="$T/finish-accounts.json" ACCOUNT_CLAUDE=false
fin e "$TE" '{"by": "typed", "rule": "C", "merge": true, "from": "laptop"}' "${QL2[@]}" > /dev/null
python3 "$QB" claim "${QB2[@]}" > /dev/null
JE=$(qget repo--e job)
DISPATCH_HOST=buildbox AUTOFINISH_HOST=buildbox DISPATCH_LABEL="$JE" AUTOFINISH_DISPATCH="$T/dispatch-start" AUTOFINISH_END_WARM=true \
  AUTOFINISH_API_STUB="$T/api_stub.py" PICKUP_PRS="$T/none.json" AUTOFINISH_VERDICT_S=10 \
  "$B/dispatch" "$BR-e" --repo "$T/repo" --finish --from-queue fleet:repo--e > "$T/out" 2>&1; check "$?" "0" "dispatch --finish: the claim's job runs autofinish-run's queued half"
has "$T/out" "the claimed finish fleet:repo--e: $BR-e at ${TE:0:7}" "  naming the entry and its tip"
has "$T/start.args" "/finish $BR-e --unattended --merge --from=laptop" "  its prompt carries the entry's rights: the merge, and the host whose yes it is"
check "$(cat "$T/start.receipt")" True "the queued finish passes a dispatch receipt too"
check "$(grep -A1 -- '--queued' "$T/start.args" | tr '\n' ' ')" "--queued fleet:repo--e " "  its dispatch --start holds the claim (--queued)…"
check "$(grep -A1 -- '--job' "$T/start.args" | tail -1)" "$JE" "  …under the job's label (--job)"
GE=$(git -C "$T/wt-e" rev-parse --absolute-git-dir)
check "$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["account"])' "$GE/claude/autofinish.json")" acct-queue \
  "the claim picked a login at 92%, past its build ceiling of 90, under its finish ceiling of 97"
export ACCOUNTS_FILE="$T/no-accounts.json"
rm -f "$REGATTA_CONFIG/lighthouse/week-max-finish"
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
# Native Darwin here; test_finish_capable exercises Linux readiness with scheduler stand-ins.
DISPATCH_MAX_RUNS=0 AUTOFINISH_END_WARM=true CLAUDE_CODE_SESSION_ID=s-caller \
  "$B/autofinish-run" "$T/wt-u" --by handed --dry > "$T/out" 2>&1; check "$?" "0" "  a handed landing on a Mac: --dry exit 0"
has "$T/out" "pinned here: a --by handed launch is judged by this host's plans" "  pinned to the Mac that judges it, as before"
echo "laptop:-finish-queue" > "$REGATTA_CONFIG/wharf-runs/features"
DISPATCH_MAX_RUNS=0 AUTOFINISH_END_WARM=true CLAUDE_CODE_SESSION_ID=s-caller \
  "$B/autofinish-run" "$T/wt-u" --by handed --dry > "$T/out" 2>&1; check "$?" "0" "  the same on a disabled Mac: --dry exit 0"
has "$T/out" "not pinned here (a --by handed launch is judged by this host's plans (mode ask holds it)): this host cannot claim a finish" "  said why it is not pinned"
has "$T/out" "any host with room claims it, this one first" "  put for any host, this one preferred"
hasnt "$T/out" "--pin laptop" "  no --pin in the put"
echo "laptop: finish-queue" > "$REGATTA_CONFIG/wharf-runs/features"
DISPATCH_MAX_RUNS=0 AUTOFINISH_END_WARM=true CLAUDE_CODE_SESSION_ID=s-caller \
  "$B/autofinish-run" "$T/wt-u" --by handed --dry > "$T/out" 2>&1
has "$T/out" "pinned here: a --by handed launch" "  with a finish-queue feature line: pinned here"
echo "laptop:finish-queue,-finish-queue" > "$REGATTA_CONFIG/wharf-runs/features"
DISPATCH_MAX_RUNS=0 AUTOFINISH_END_WARM=true CLAUDE_CODE_SESSION_ID=s-caller \
  "$B/autofinish-run" "$T/wt-u" --by handed --on here --dry > "$T/out" 2>&1
has "$T/out" "pinned here: --on here" "  a typed --on here stays pinned even on a disabled host"
rm -f "$REGATTA_CONFIG/wharf-runs/features"
DISPATCH_MAX_RUNS=0 AUTOFINISH_END_WARM=true CLAUDE_CODE_SESSION_ID=s-caller \
  "$B/autofinish-run" "$T/wt-u" --by handed --on here --dry > "$T/out" 2>&1
has "$T/out" "pinned here: --on here" "  …and with no feature line too (the caller's word: it waits unclaimed, as before)"
echo "  a ladder hold on a host that cannot claim a finish rides in the rights: held, never a merge"
echo "laptop:-finish-queue" > "$REGATTA_CONFIG/wharf-runs/features"
mkbranch lh > /dev/null
git -C "$T/repo" checkout -q "$BR-lh"; printf 'a\000b' > "$T/repo/blob.bin"; git -C "$T/repo" add blob.bin
git -C "$T/repo" commit -qm "a binary"; git -C "$T/repo" push -q origin "$BR-lh" 2>/dev/null; git -C "$T/repo" checkout -q main
git -C "$T/repo" worktree add -q "$T/wt-lh" "$BR-lh" 2>/dev/null
DISPATCH_MAX_RUNS=0 AUTOFINISH_END_WARM=true CLAUDE_CODE_SESSION_ID=s-caller \
  "$B/autofinish-run" "$T/wt-lh" --by handed --dry > "$T/out" 2>&1; check "$?" "0" "  a held handed landing on a disabled Mac: --dry exit 0"
has "$T/out" "this host cannot claim a finish (no finish-queue), so any host with room takes it, held at a ready PR" "  said as held, not pinned"
has "$T/out" '"hold": true, "merge": false' "  the put's rights hold it and carry no merge"
hasnt "$T/out" "--pin laptop" "  no --pin in the put"
rm -f "$REGATTA_CONFIG/wharf-runs/features"

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
print(tuple(a.BY_WORDS) == tuple(q.FINISH_BY), set(a.PERSON_BY) == set(q.FINISH_PERSON), tuple(a.ROADS) == tuple(q.FINISH_ROADS))
PY
)" "True True True" "dispatch-queue's FINISH_BY, FINISH_PERSON and FINISH_ROADS are autofinish-run's own words"
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

# An unprepared non-Mac host is still refused (test_finish_capable covers readiness), judging only
# itself; and two hosts' stamps are compared as instants, never as strings
cat > "$T/builtin.py" <<'PY2'
import importlib.machinery, sys
sys.dont_write_bytecode = True   # no __pycache__ beside the tool (AGENTS.md: a tree scan meets CI's bytecode)
m = importlib.machinery.SourceFileLoader("dq", sys.argv[1]).load_module()
# The readiness probe has its own suite with scheduler stand-ins; this case tests
# the OS/peer rule without ever asking the machine's scheduler or word list.
m.capability = lambda common: {"reason": "fixture host is not prepared"}
m.sys.platform = "darwin"   # the Mac half on any host: the suite runs on Linux too (mac-share-speed)
r = [m.builtin_met("finish-queue", "laptop"), m.builtin_met("finish-queue", "buildbox")]
m.sys.platform = "linux"
r += [m.builtin_met("finish-queue", "laptop"), m.builtin_met("finish-queue", "buildbox"), m.builtin_met("other", "buildbox")]
r += [m.iso_before("2026-11-02T20:00:00-08:00", "2026-11-03T03:00:00+00:00"), m.iso_before("2026-11-03T03:30:00+00:00", "2026-11-02T20:00:00-08:00")]
print(" ".join(str(x) for x in r))
PY2
check "$(python3 "$T/builtin.py" "$QB" 2>&1 | tail -1)" "True True False True False False True" \
  "finish-queue: met on a Mac, not on an unprepared Linux host (peers judge themselves); stamps read as instants"

echo "the lander (stuck-ships S1): a --by lander finish names its road, is pinned to its host, its caps that host's lander.json"
qreset
export AUTOFINISH_STATE_DIR="$T/af-state"   # this host's lander.json (the lander's one store)
LR='{"by": "lander", "rule": "C", "road": "login", "from": "laptop"}'
TN=$(mkbranch n)
for bad in '{"by": "lander", "rule": "C", "from": "laptop"}' '{"by": "lander", "rule": "C", "road": "bogus", "from": "laptop"}' \
           '{"by": "sweep", "rule": "C", "road": "login", "from": "laptop"}' '{"by": "sweep", "rule": "C", "land_by": "dnd", "from": "laptop"}' \
           '{"by": "lander", "rule": "C", "road": "login", "land_by": "typed", "from": "laptop"}'; do
  fin n "$TN" "$bad" "${QL2[@]}" > /dev/null 2>&1; check "$?" "2" "refused, never queued: $bad"
done
# the stop: a finish of this tip run here, ended at a login failure — its tombstone holds the tip for every other word
fin n "$TN" "$RIGHTS" "${QL2[@]}" > /dev/null; python3 "$QB" claim "${QL2[@]}" > /dev/null
python3 "$QB" started fleet:repo--n --label "$(qget repo--n job)" --session s-n "${QL2[@]}" > /dev/null
python3 "$QB" ended --repo "$T/repo" --branch "$BR-n" --session s-n "${QL2[@]}" > /dev/null
python3 "$QB" finished fleet:repo--n --session s-n --outcome stopped --gate no-landing "${QL2[@]}" > /dev/null
fin n "$TN" "$RIGHTS" "${QL2[@]}" > /dev/null; check "$?" "3" "a stop's tombstone: the sweep's put of that tip refused"
git -C "$T/repo" worktree add -q "$T/wt-n" "$BR-n" 2>/dev/null
GN=$(git -C "$T/wt-n" rev-parse --absolute-git-dir); GC=$(git -C "$T/wt-n" rev-parse --path-format=absolute --git-common-dir)
mkdir -p "$GN/claude" "$GC/claude"
cat > "$T/stop.py" <<'PY'
import json, sys
st, af, tip, br = sys.argv[1:5]
ended = "2026-11-03T21:00:00-08:00"
json.dump({"started": "2026-11-03T20:40:00-08:00", "session": "s-n", "tip": tip, "by": "sweep", "rule": "C",
           "window": "finish · n", "account": "acct-pro", "ended": ended, "outcome": "stopped", "pr": None,
           "gate": "no-landing", "queue": "fleet:repo--n"}, open(st, "w"))
open(af, "a").write("%s stopped %s no-landing Not logged in · Please run /login\n" % (ended, br))
PY
python3 "$T/stop.py" "$GN/claude/autofinish.json" "$GC/claude/autofinished" "$TN" "$BR-n"
cat > "$T/spend.py" <<'PY'
import sys
from importlib.machinery import SourceFileLoader
m = SourceFileLoader("afr_spend", sys.argv[1]).load_module()
t = m.Tree(sys.argv[2])
key = m.lander_key(t.primary, t.branch)
if sys.argv[3] == "show":
    e = m.lander_read().get(key) or {}
    print(*[x for x in (e.get("relaunches", {}).get("login", 0), e.get("stop_for")) if x is not None], m.lander_path())
else:
    m.lander_update(key, lambda e: m.road_add(e, "login", int(sys.argv[3])))
PY
python3 "$T/spend.py" "$B/autofinish-run" "$T/wt-n" 1
DISPATCH_MAX_RUNS=0 AUTOFINISH_END_WARM=true \
  "$B/autofinish-run" "$T/wt-n" --by lander --road login > "$T/out" 2>&1; check "$?" "9" "the login road spent in this host's lander.json: STUCK_RC, before any put"
has "$T/out" "the login road is spent" "  saying so"
check "$(qget repo--n state outcome)" "ended stopped" "  nothing queued: the tombstone stands"
python3 "$T/spend.py" "$B/autofinish-run" "$T/wt-n" -1
AUTOFINISH_PLATFORM=linux AUTOFINISH_END_WARM=true \
  "$B/autofinish-run" "$T/wt-n" --by lander --road login --dry > "$T/out" 2>&1
check "$?" "0" "a lander put from a host with no finish-queue feature: its road still judged here"
has "$T/out" "pinned here: a --by lander start is this host's road, its caps in this host's lander.json" \
  "  its local cap store keeps it pinned even when this host cannot claim a finish"
has "$T/out" "--pin laptop" "  the put never sends a lander's caps to another host"
DISPATCH_MAX_RUNS=0 AUTOFINISH_END_WARM=true \
  "$B/autofinish-run" "$T/wt-n" --by lander --road login > "$T/out" 2>&1; check "$?" "0" "the road open in this host's store: the lander's put, exit 0"
has "$T/out" "queued: fleet:repo--n (a finish of ${TN:0:7})" "  queued past the stop's tombstone of its own tip"
has "$T/out" "pinned here (a --by lander start is this host's road, its caps in this host's lander.json)" "  pinned here, as a hand-over is"
check "$(qget repo--n kind state host tip)" "finish queued laptop $TN" "  one fleet entry, pinned to the putting host"
check "$(qget repo--n finish)" '{"by": "lander", "from": "laptop", "hold": false, "merge": false, "road": "login", "rule": "C"}' \
  "  its rights: by lander, the road, no merge"
check "$(python3 "$T/spend.py" "$B/autofinish-run" "$T/wt-n" show | cut -d' ' -f1)" "0" "  the put spends nothing: the claim's start does"
python3 "$QB" claim "${QB2[@]}" > /dev/null
check "$(claimed_by n)" "queued None" "another host with room never claims it"
python3 "$QB" claim "${QL2[@]}" > /dev/null
check "$(claimed_by n)" "claimed laptop" "its own host claims it"
JN=$(qget repo--n job); rm -f "$T/start.args"
DISPATCH_LABEL="$JN" AUTOFINISH_DISPATCH="$T/dispatch-start" AUTOFINISH_END_WARM=true \
  AUTOFINISH_API_STUB="$T/api_stub.py" PICKUP_PRS="$T/none.json" AUTOFINISH_VERDICT_S=10 \
  "$B/dispatch" "$BR-n" --repo "$T/repo" --finish --from-queue fleet:repo--n > "$T/out" 2>&1; check "$?" "0" "the claim's job starts it"
has "$T/start.args" "/finish $BR-n --unattended" "  a plain unattended /finish"
hasnt "$T/start.args" "--merge" "  never a merge"
check "$(python3 -c 'import json, sys; d = json.load(open(sys.argv[1])); print(d.get("by"), d.get("road"), d.get("queue"))' "$GN/claude/autofinish.json")" \
  "lander login fleet:repo--n" "  recorded by lander, its road and its entry"
# the stand-in start never replies, so its waiter records it never-started and gives the road back (S1's refund): the
# spend and the refund are this host's store's, which names the claimed session as the one its kept stop is for
SN=$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["session"])' "$GN/claude/autofinish.json")
check "$(python3 "$T/spend.py" "$B/autofinish-run" "$T/wt-n" show)" "0 $SN $AUTOFINISH_STATE_DIR/lander.json" \
  "  the road spent at the claimed start in this host's lander.json (its stop kept for that session), given back there"
has "$HL/Logs/claude-weekly/autofinish-$(date +%Y-%m-%d).log" "by=lander via=sweep road=login stopped_on=acct-pro" "  its start line names the road and the stop's login"
# a lander put on a stop that ran on another host, or on a cancel: refused by the queue (one host roads a stop)
TN2=$(mkbranch n2)
fin n2 "$TN2" "$RIGHTS_B" "${QB2[@]}" > /dev/null; python3 "$QB" claim "${QB2[@]}" > /dev/null
python3 "$QB" started fleet:repo--n2 --label "$(qget repo--n2 job)" --session s-n2 "${QB2[@]}" > /dev/null
python3 "$QB" ended --repo "$T/repo" --branch "$BR-n2" --session s-n2 "${QB2[@]}" > /dev/null
python3 "$QB" finished fleet:repo--n2 --session s-n2 --outcome stopped --gate no-landing "${QB2[@]}" > /dev/null
fin n2 "$TN2" "$LR" "${QL2[@]}" > "$T/out"; check "$?" "3" "a lander put on a stop that ran on another host: refused"
check "$(python3 "$T/jget.py" result < "$T/out")" "ran ${TN2:0:7} on buildbox: stopped no-landing" "  naming where it ran"
TN3=$(mkbranch n3)
fin n3 "$TN3" "$RIGHTS" "${QL2[@]}" > /dev/null; python3 "$QB" cancel --repo "$T/repo" --branch "$BR-n3" "${QL2[@]}" > /dev/null
fin n3 "$TN3" "$LR" "${QL2[@]}" > /dev/null; check "$?" "3" "  and on a cancel: a cancel holds the tip for a person"
unset AUTOFINISH_STATE_DIR

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
TM2=$(mkbranch lm)
git -C "$T/repo" worktree add -q "$T/wt-lm" "$BR-lm" 2>/dev/null
GM=$(git -C "$T/wt-lm" rev-parse --absolute-git-dir)
mkdir -p "$GM/claude" "$HL/Caches/run-seed/queue-local/_land"
cat > "$T/land_lander.py" <<'PY'
import json, os, sys
d, tip, land, br, repo = sys.argv[1:6]
json.dump({"started": "2026-11-02T11:00:00-08:00", "session": "s-lm", "tip": tip, "by": "lander", "rule": "C",
           "road": "refinish", "land_by": "dnd", "ended": None, "outcome": None, "gate": None},
          open(os.path.join(d, "autofinish" + ".json"), "w"))
json.dump({"id": "x3", "key": "repo--lm", "repo": repo, "branch": br + "-lm", "kind": "landing", "priority": "normal",
           "state": "queued", "host": "laptop", "queued_at": 1, "waiter_pid": 999999, "waiter_start": "Sat Oct 31 12:00:00 2026"},
          open(os.path.join(land, "repo--lm.json"), "w"))
PY
python3 "$T/land_lander.py" "$GM/claude" "$TM2" "$HL/Caches/run-seed/queue-local/_land" "$BR" "$(cd "$T/repo" && pwd -P)"
python3 "$QB" sweep "${QL2[@]}" > "$T/out" 2>&1
has "$T/out" "moved repo--lm from this host's landing queue: queued" "a queued lander start in the old landing queue: moved too"
check "$(qget repo--lm finish)" '{"by": "lander", "from": "", "hold": false, "land_by": "dnd", "merge": false, "road": "refinish", "rule": "C"}' \
  "  carrying its road and its mode flag (stuck-ships S1), pinned here as every moved landing"

echo "finish ceiling: direct picks, cached retries and dispatch auto/bound starts"
qreset
echo off > "$REGATTA_CONFIG/wharf-runs/queue-repo"
export ACCOUNTS_FILE="$T/finish-accounts.json" ACCOUNT_CLAUDE=false
printf 'acct-queue:97\n' > "$REGATTA_CONFIG/lighthouse/week-max-finish"
cat > "$T/finish-picks.py" <<'PY'
import subprocess, sys, types
from importlib.machinery import SourceFileLoader
m = SourceFileLoader("finish_ceiling", sys.argv[1]).load_module()
t = types.SimpleNamespace(primary=sys.argv[2], branch="claude/laptop/2026-11-02-pick")
print(m.account_pick(t, cached=True)[2])
run, calls = m.common.run_group, []
def timed_out_once(cmd, timeout, **kwargs):
    result = run(cmd, timeout, **kwargs)
    calls.append("finish ceiling" in result.stdout)
    if len(calls) == 1:
        raise subprocess.TimeoutExpired(cmd, timeout)
    return result
m.common.run_group = timed_out_once
print(m.account_pick(t)[2])
print(calls)
PY
python3 "$T/finish-picks.py" "$B/autofinish-run" "$T/repo" > "$T/out" 2>&1
check "$?" 0 "the direct account pick accepts a finish past its build ceiling"
has "$T/out" "week 92% < 97% (finish ceiling)" "the direct pick names the finish ceiling"
has "$T/out" "[True, True]" "the timed-out attempt and cached retry each receive a fresh receipt"
cat > "$T/finish-dispatch.py" <<'PY'
import subprocess, sys
sys.path.insert(0, sys.argv[1])
import common
with common.finish_pick_env(target="dispatch") as (env, fds):
    result = subprocess.run(sys.argv[2:], env=env, pass_fds=fds)
sys.exit(result.returncode)
PY
cat > "$T/claude-headless" <<EOF
#!/bin/sh
env > "$T/finish-env"
echo ok
EOF
chmod +x "$T/claude-headless"
export DISPATCH_CLAUDE="$T/claude-headless"
for purpose_pick in auto bound; do
  DISPATCH_HOST=buildbox DISPATCH_LOG="$T/finish-$purpose_pick.log" \
    python3 "$T/finish-dispatch.py" "$B/../../regatta/hooks" "$B/dispatch" --start go "$T/repo" finish-test --headless --account "$purpose_pick" > "$T/out" 2>&1
  check "$?" 0 "a receipt-bearing $purpose_pick finish start runs past the build ceiling"
  has "$T/finish-$purpose_pick.log" "week 92% < 97% (finish ceiling)" "the $purpose_pick pick receives the finish marker"
  hasnt "$T/finish-env" "REGATTA_FINISH_PICK_FD=" "the session inherits no receipt from its $purpose_pick start"
done
REGATTA_FINISH_PICK_FD=finish DISPATCH_HOST=buildbox DISPATCH_LOG="$T/finish-fake.log" \
  "$B/dispatch" --start go "$T/repo" finish-test --headless --account auto > "$T/out" 2>&1
check "$?" 1 "a build start naming the marker by hand is refused at its build ceiling"
has "$T/finish-fake.log" "week 92% ≥ 90% (week ceiling)" "its refusal names the normal ceiling"

echo "finish ceiling: the sweep and completed-build preflights"
cat > "$T/finish-preflight.py" <<'PY'
import contextlib, io, json, os, sys
from pathlib import Path
from importlib.machinery import SourceFileLoader

sys.dont_write_bytecode = True
bin, repo, scratch = map(Path, sys.argv[1:4])
registry = json.loads(Path(os.environ["ACCOUNTS_FILE"]).read_text())
registry["accounts"][0]["primary"] = False  # the primary's separate pace gate is not this login's rule
registry["accounts"][0]["rules"]["overdraw"] = False  # a lifted build reads tight, and this asks of the ceiling alone
accounts = scratch / "preflight-accounts.json"
accounts.write_text(json.dumps(registry))
os.environ["ACCOUNTS_FILE"] = str(accounts)
m = SourceFileLoader("preflight", str(bin / "autofinish")).load_module()
for fresh in (False, True):
    # Cached build and finish verdicts must stay distinct in both orders.
    for finish in ((False, True) if not fresh else (True, False)):
        kind, detail = m.week_tight(repo, fresh=fresh, finish=finish)
        print("fresh=%s finish=%s: %s" % (fresh, finish, kind or "allowed"))
        if finish:
            print(detail)

# Run the actual dispatch handover preflight with an ended build's reply, without launching anything.
common = m.common
common.autofinish_landings = lambda: True
common.autofinish_armed = lambda: True
state = scratch / "preflight-state.json"
state.write_text(json.dumps({"session": "preflight", "mode": "headless"}))
transcripts = Path.home() / ".claude/projects/preflight"
transcripts.mkdir(parents=True, exist_ok=True)
(transcripts / "preflight.jsonl").write_text(json.dumps({"type": "assistant", "message": {
    "model": "opus", "content": [{"type": "text", "text": common.HANDOVER_LINE}]}}, separators=(",", ":")) + "\n")
source = (bin / "dispatch").read_text()
gate = source.split('  why=$(python3 - "$state" "$here" "$branch" "$repo" "$core" "$m"', 1)[1]
gate = gate.split("\n", 1)[1].split("\nPY\n", 1)[0]
for by in ("handed", "yolo"):
    # dispatch passes the worktree and keel's path after --by: the handed judge reads the build's facts there
    sys.argv = ["preflight", str(state), str(bin.parent), "branch", str(repo), str(Path(common.__file__).parent), by,
                str(repo), ""]
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        try:
            exec(compile(gate, "dispatch-preflight", "exec"), {})
        except SystemExit:
            pass
    print("%s: %s" % (by, out.getvalue().strip() or "allowed"))

# modules/helm/bin/stalls_tick.py preflights landing retries through the same week reader.
tick = SourceFileLoader("preflight_tick", str(bin.parent.parent / "helm/bin/stalls_tick.py")).load_module()
tick._AF = m
tick.run_cap = lambda s: None
for action in ("relaunch", "retry"):
    stall = {"action": action, "key": ["preflight", action], "worktree": str(repo), "depth": 1,
             "host": tick.helmlib.host(), "dispatch": {"repo": str(repo)}}
    memory = tick.Memory([dict(stall, t=1)])
    print("tick %s: %s" % (action, tick.decide(stall, memory, 10000, "armed")["action"]))
PY
python3 "$T/finish-preflight.py" "$B" "$T/repo" "$T" > "$T/out" 2>&1
check "$?" 0 "the actual preflights read a login at 92%, build ceiling 90%, finish ceiling 97%"
for fresh in False True; do
  has "$T/out" "fresh=$fresh finish=False: none" "the build preflight (fresh=$fresh) keeps the normal ceiling"
  has "$T/out" "fresh=$fresh finish=True: allowed" "the landing preflight (fresh=$fresh) uses its own verdict"
done
has "$T/out" "week 92% < 97% (finish ceiling)" "the preflight verdict names the finish ceiling"
has "$T/out" "handed: allowed" "a completed handover reaches the finish launcher"
has "$T/out" "yolo: allowed" "a completed yolo build reaches the finish launcher too"
has "$T/out" "tick relaunch: go" "Helm's landing retry reaches the finish launcher"
has "$T/out" "tick retry: refused" "Helm's build retry keeps the normal ceiling"

echo "queue-entry-vanish: every departure is audited by the store, including the sweep and outbox replay"
qreset
# The finish ceiling case above turned the queue home off; this case needs it on.
echo "$T/queue.git" > "$REGATTA_CONFIG/wharf-runs/queue-repo"
export ACCOUNTS_FILE="$T/no-accounts.json"; unset ACCOUNT_CLAUDE DISPATCH_CLAUDE
cat > "$T/departures.py" <<'PY'
import argparse, importlib.machinery, json, sys, types
sys.dont_write_bytecode = True
q = importlib.machinery.SourceFileLoader("dq", sys.argv[1]).load_module()
url, repo = sys.argv[2:4]
ctx = argparse.Namespace(host=None, cap=0, launchctl=sys.argv[4], prefix="org.example.claude", jobbin="unused", rch="", event_at=None)
q.kick_hold = lambda *a: None
q.drain_land = lambda *a: []
q.kl = lambda: types.SimpleNamespace(watchdog=lambda *a: None)
q.claim = lambda *a: []
q.poll_tend = q.words_tend = lambda *a: None
q.eligibility = lambda *a, **k: None
q.tomb_line = lambda *a: None
q.tomb_spent = lambda *a: True
q.rec_alive = lambda *a: False
log = q.logdir() / "queue.jsonl"

def events():
    return [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []

def entry(key, **fields):
    return dict(dict(id=key, key=key, branch="claude/laptop/2026-11-05-" + key.split("--")[-1],
                     repo=q.repo_word(repo), topic=key.split("--")[-1], state="queued", queued_at=q.now(),
                     priority="high", session="", host="buildbox", pin_kind="typed", needs=["chrome"],
                     args=["--needs", "chrome"], env={}), **fields)

def put(store, e):
    return store.do([dict(op="put", key=e["key"], entry=e)], "test put", defer=False)[0]

def audited(store, key, action, why):
    rows = [e for e in events() if e.get("key") == store.name + ":" + key and e.get("event") == action]
    assert rows and why in rows[-1]["why"], (action, key, rows)
    assert any(e.get("event") == "removal-prepared" and e.get("key") == rows[-1]["key"]
               and e.get("id") == rows[-1]["id"] and e.get("commit") == rows[-1]["commit"] for e in events())

for store in (q.Fleet(url), q.Local("departures")):
    q.stores = lambda: [store]
    key = "repo--vanish"
    qid = store.name + ":" + key
    old = entry(key, id="old-finish", kind="finish", state="ended", session="s-finish", tip="1" * 40,
                ended_at=q.now() - q.ENDED_TTL - 1, outcome="stopped", gate="G4", ran_on="buildbox")
    put(store, old)
    expired = dict(op="remove", key=key, cond=dict(id=old["id"], state="ended"), why="expired tombstone")
    build = entry(key, id="new-build")
    assert put(store, build) == "queued"
    audited(store, key, "replaced", "test put")
    assert store.do([expired], "stale sweep", defer=False) == ["moved"]
    q.cmd_finished(argparse.Namespace(qid=qid, session="s-finish", outcome="never-started", gate="refused", pr=None, line=None), ctx)
    q.cmd_branch_word(argparse.Namespace(repo=repo, branch=build["branch"], verb="ended", session="s-old-build"), ctx)
    q.records = lambda: [dict(queue=qid, session="s-old-build", repo=repo, branch=build["branch"], started=1, ended=2)]
    q.cmd_sweep(ctx, ctx)
    assert store.entries()[key] == build
    print("  ok   %s: a pinned build replaces a G4 finish tombstone and survives old outcomes, end words and sweeps" % store.name)

    # A cleanup op built from the prior entry and replayed after a replacement must not delete it.
    # Before the fix end_op carried only the host and second, so this op removed the newer entry.
    prior = entry("repo--race", id="prior", state="claimed", claimed_by="laptop", running_on="laptop", claimed_at=q.now())
    cleanup = q.end_op(prior["key"], prior, dict(running_on="laptop", claimed_at=prior["claimed_at"]), why="old claim ended")
    newer = dict(prior, id="newer")
    put(store, newer)
    assert store.do([cleanup], "delayed cleanup", defer=False) == ["moved"]
    assert store.entries()[prior["key"]]["id"] == "newer"
    print("  ok   %s: delayed claim cleanup cannot remove a replacement" % store.name)

    # The silent road: _sweep used to remove an ended build without any event or card.
    for state, ended in (("claimed", True), ("running", False)):
        k = "repo--sweep-" + state
        live = entry(k, state=state, session="s-" + state, running_on="laptop", claimed_by="laptop", claimed_at=q.now())
        put(store, live)
        rec = dict(queue=store.name + ":" + k, session=live["session"], repo=repo, branch=live["branch"], started=q.now())
        if ended:
            rec["ended"] = q.now()
        q.records = lambda: [rec]
        q.cmd_sweep(ctx, ctx)
        assert k not in store.entries()
        audited(store, k, "removed", "its run ended" if ended else "no end recorded")
    print("  ok   %s: ended and crashed builds leave through logged sweep roads" % store.name)

    k = "repo--expire"
    put(store, dict(old, key=k, id=k))
    q.records = lambda: []
    q.cmd_sweep(ctx, ctx)
    assert k not in store.entries()
    audited(store, k, "removed", "tombstone expired")

    # Cancel, failed start and a finish that never launched use the same audit boundary.
    q.cmd_cancel(argparse.Namespace(qid=None, repo=repo, branch=build["branch"], no_fleet=False, fleet_only=False, for_session=None), ctx)
    audited(store, key, "removed", "cancelled")
    k = "repo--failed"
    live = entry(k, state="claimed", claimed_by="laptop", running_on="laptop", job="job-failed")
    put(store, live)
    q.cmd_fire(argparse.Namespace(qid=store.name + ":" + k, label="job-failed", verb="failed", why="test start failure"), ctx)
    audited(store, k, "removed", "test start failure")
    k = "repo--finish"
    live = entry(k, state="running", kind="finish", session="s-never", running_on="laptop")
    put(store, live)
    # The end word can land after finished reads its entry but before it writes the outcome.
    # The id/session guard must allow this state transition, or the outcome is lost for good.
    original_split, original_do = q.split_qid, store.do
    q.split_qid = lambda qid: (store, k)
    def finish_end_race(ops, why, defer=True):
        if why.startswith("finished "):
            original_do([q.end_op(k, live, dict(session="s-never"))], "run ended", defer=False)
        return original_do(ops, why, defer)
    store.do = finish_end_race
    try:
        q.cmd_finished(argparse.Namespace(qid=store.name + ":" + k, session="s-never", outcome="stopped", gate="G4", pr=None, line=None), ctx)
    finally:
        q.split_qid, store.do = original_split, original_do
    assert store.entries()[k]["outcome"] == "stopped"
    audited(store, k, "tombstoned", "its run ended")
    q.cmd_finished(argparse.Namespace(qid=store.name + ":" + k, session="s-never", outcome="never-started", gate="refused", pr=None, line=None), ctx)
    audited(store, k, "removed", "never started")
    print("  ok   %s: tombstone expiry, cancel, failed start and finish outcomes name their removal reason" % store.name)

    # An unavailable queue.jsonl never holds a departure (main's best-effort log): the write lands, the batch's
    # other ops with it, and stderr names the queue id and entry id the log could not.
    import contextlib, io
    k = "repo--unlogged"
    put(store, entry(k))
    other = entry("repo--other")
    put(store, other)
    remove = dict(op="remove", key=k, cond=dict(id=k))   # no why of its own: the write's reason stands
    seen = dict(op="set", key=other["key"], fields=dict(by_seen=7), cond=dict(id=other["id"], state="queued"))
    n = len(events())
    q.apply_all(store.entries(), [remove])
    assert len(events()) == n  # a speculative view never logs a departure
    real_logdir = q.logdir
    blocked = q.qdir() / "not-a-directory"
    blocked.write_text("blocked")
    q.logdir = lambda: blocked
    err = io.StringIO()
    try:
        with contextlib.redirect_stderr(err):
            assert store.do([remove, seen], "explicit removal", defer=False) == ["removed", "set"]
    finally:
        q.logdir = real_logdir
    assert k not in store.entries() and store.entries()[other["key"]]["by_seen"] == 7
    said = err.getvalue()
    assert "preparing removed %s:%s (entry %s, queued, commit " % (store.name, k, k) in said, said
    assert "explicit removal" in said and "done: removed" in said, said
    # and a stderr that will not write either never holds it
    put(store, entry(k))
    class Full:
        def write(self, *a):
            raise OSError(28, "No space left on device")
    q.logdir = lambda: blocked
    real_stderr, sys.stderr = sys.stderr, Full()
    try:
        assert store.do([remove], "explicit removal", defer=False) == ["removed"]
    finally:
        sys.stderr, q.logdir = real_stderr, real_logdir
    assert k not in store.entries()
    assert len(events()) == n
    k2 = "repo--replayed"
    put(store, entry(k2))
    if isinstance(store, q.Fleet):
        q.outbox_add(dict(op="remove", key=k2, cond=dict(id=k2)))  # an old op without any new audit fields
        q.flush(store)
    else:
        store.do([dict(op="remove", key=k2, cond=dict(id=k2))], "outbox of laptop", defer=False)
    assert k2 not in store.entries()
    audited(store, k2, "removed", "outbox of")
    print("  ok   %s: an unwritable log never holds a departure, stderr names it; a replay logs it, views log nothing" % store.name)

# A lost lease is a prepared attempt only. No completion is logged until the write actually lands.
store = q.Fleet(url)
k = "repo--lost"
put(store, entry(k))
real_push, real_sleep = store.push, q.time.sleep
store.push = lambda *a: ("lost", "stale info")
q.time.sleep = lambda *a: None
try:
    store.do([dict(op="remove", key=k, cond=dict(id=k), why="lost lease")], "lost lease", defer=False)
except q.Unreachable:
    pass
else:
    raise AssertionError("a lost lease reported success")
finally:
    store.push, q.time.sleep = real_push, real_sleep
assert k in store.entries()
rows = [e for e in events() if e.get("key") == "fleet:" + k]
assert sum(e["event"] == "removal-prepared" for e in rows) == q.TRIES
assert not any(e["event"] == "removed" for e in rows)
print("  ok   fleet: a lost lease never logs a completed removal")
PY
python3 "$T/departures.py" "$QB" "$T/queue.git" "$T/repo" "$T/launchctl" > "$T/out" 2>&1
check "$?" "0" "departure audit and stale cleanup regressions"
cat "$T/out"

echo
[ "$fails" = 0 ] && echo "test_finish_queue: all passed" || { echo "test_finish_queue: $fails failed"; exit 1; }
