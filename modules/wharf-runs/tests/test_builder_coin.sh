#!/usr/bin/env bash
# Tests for the builder rotation (bin/buildercoin.py; dispatch's header; S6 of docs/self-tuning-2026-10-26.md):
# a specced brief's run draws its builder once where it is enqueued or scheduled, every road carries the draw
# (the one-shot's plist, the peer's ssh line, the queue's entry), and the fire path runs it, records it and
# writes its row. Scratch HOME, a scratch origin and queue home, stand-ins for launchctl, claude and ssh; no
# launchd job, session or network is touched. Every name is synthetic. Portable: it runs on Linux too.
#   bash modules/wharf-runs/tests/test_builder_coin.sh
set -u
unset WEEKLY_RUN REGATTA_UNATTENDED CLAUDE_UNATTENDED AUTOFINISH_CALLER_UNATTENDED CLAUDE_CODE_DISABLE_BACKGROUND_TASKS CLAUDE_CODE_SESSION_ID CLAUDE_CONFIG_DIR
unset $(compgen -v | grep '^DISPATCH_')   # every DISPATCH_* a run carries (AGENTS.md: a fixed list goes stale)
B="$(cd "$(dirname "$0")/../bin" && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
. "$(cd "$(dirname "$0")" && pwd)/config_fixture.sh"; fixture_config "$T/config"
fails=0
check() { if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3: expected [$2] got [$1]"; fails=$((fails+1)); fi; }
has()   { if grep -qF -- "$2" "$1"; then echo "  ok   $3"; else echo "  FAIL $3: missing [$2]"; sed 's/^/         | /' "$1" | head -20; fails=$((fails+1)); fi; }
hasnt() { if [ ! -f "$1" ]; then echo "  FAIL $3: no file $1 to read"; fails=$((fails+1)); elif grep -qF -- "$2" "$1"; then echo "  FAIL $3: unexpected [$2]"; sed 's/^/         | /' "$1" | head -20; fails=$((fails+1)); else echo "  ok   $3"; fi; }
export PYTHONUSERBASE="${PYTHONUSERBASE:-$(python3 -m site --user-base)}"
export HOME="$T/home"; H="$HOME"; HL="$H/Library"; LA="$HL/LaunchAgents"; mkdir -p "$LA"   # H: one spelling of the scratch home
# a recursive delete under HOME goes through rm_own: only under this suite's own $T (the core's check, home_rm)
rm_own() { local p; for p; do case "$p" in */..|*/../*|*//*) ;; "${T:?}"/?*) rm -rf -- "$p"; continue ;; esac; echo "rm_own: refused $p, outside $T" >&2; return 1; done; }
export ACCOUNTS_FILE="$T/no-accounts.json"
# a moved HOME drops the global git identity (AGENTS.md: a suite that moves HOME and commits)
printf '[user]\n\tname = t\n\temail = t@t\n[init]\n\tdefaultBranch = main\n' > "$T/gitconfig"; export GIT_CONFIG_GLOBAL="$T/gitconfig"
ROWS="$HL/Logs/claude-weekly/builder-rotation.jsonl"; RUNS="$HL/Logs/claude-weekly/run-seed-runs"
KEY="$REGATTA_CONFIG/wharf-runs/builder-rotation"
UNTIL=$(python3 -c 'import datetime; print(datetime.date.today() + datetime.timedelta(days=20))')
PAST=$(python3 -c 'import datetime; print(datetime.date.today() - datetime.timedelta(days=1))')
# a fire time a few days out, in launchd's "YYYY-MM-DD HH:MM" (portable: no BSD date -v)
FUT=$(python3 -c 'import datetime; print(datetime.date.today() + datetime.timedelta(days=3))')
# the registry: the repo in an open scope (the fence's one passing case), a confidential one, and a torn file
export CLAUDE_REPOS_JSON="$T/repos.json"
echo '{"repos": {}, "scopes": {"open": {"repos": ["*"]}}}' > "$T/open.json"
echo '{"repos": {}, "scopes": {"open": {"repos": ["*"]}, "vault": {"repos": ["*"], "confidential": true}}}' > "$T/conf.json"
echo '{"repos": {}, "scopes": {"open": ' > "$T/torn.json"
cp "$T/open.json" "$T/repos.json"

# the repo under the projects folder (the peer road names it there), seeded branches on a bare origin
R="$H/projects/repo"; mkdir -p "$H/projects"
git init -q --bare "$T/origin.git"
git init -q -b main "$R"; git -C "$R" remote add origin "$T/origin.git"
(cd "$R" && echo x > f && git add f && git commit -qm init)
seed() {   # TOPIC TIER-LINE: a seeded branch whose brief has that Tier: line, on origin and here
  local br="claude/laptop/2026-11-02-$1" blob tree
  blob=$(printf '# %s\nTask: build it\n%s\n' "$1" "$2" | git -C "$R" hash-object -w --stdin)
  GIT_INDEX_FILE="$T/seed.idx" git -C "$R" read-tree main
  GIT_INDEX_FILE="$T/seed.idx" git -C "$R" update-index --add --cacheinfo "100644,$blob,docs/handoff/2026-11-02-$1.md"
  tree=$(GIT_INDEX_FILE="$T/seed.idx" git -C "$R" write-tree); rm -f "$T/seed.idx"
  git -C "$R" update-ref "refs/heads/$br" "$(git -C "$R" commit-tree "$tree" -p main -m "seed: $1")"
  git --git-dir="$R/.git" send-pack "$T/origin.git" "$br:refs/heads/$br" >/dev/null 2>&1
}
seed worker "Tier: worker"
seed sonnet "Tier: Sonnet 5.5 high"
seed block "tier: worker"
seed sr "Tier: Opus 5.5 high (sr-worker; not Sonnet)"
seed prin "Tier: principal-worker"
seed plain "Tier: Opus 5.5 high"
printf -- '- physical: none\n' > "$R/AGENTS.md"   # the contract dispatch requires, untracked on main

cat > "$T/launchctl" <<EOF
#!/bin/sh
echo "\$*" >> "$T/calls"
exit 0
EOF
cat > "$T/claude" <<EOF
#!/bin/sh
env >> "$T/env.calls"; echo "claude \$*" >> "$T/claude.calls"; echo ok
EOF
cat > "$T/ssh" <<EOF
#!/bin/sh
echo "ssh \$*" >> "$T/ssh.calls"
exit 0
EOF
chmod +x "$T/launchctl" "$T/claude" "$T/ssh"
export DISPATCH_LAUNCHCTL="$T/launchctl" DISPATCH_CLAUDE="$T/claude" DISPATCH_SSH="$T/ssh" DISPATCH_DEFAULT_ON= DISPATCH_HOST=laptop
pl() { ls "$LA"/org.example.claude.dispatch.repo."$1".[0-9]*.plist 2>/dev/null | head -1; }
armof() { sed -n 's/.*<key>DISPATCH_ARM<\/key><string>\([^<]*\)<\/string>.*/\1/p' "$1" 2>/dev/null; }
clean() { rm_own "$LA"/*.plist "$T"/*.calls "$ROWS" "$RUNS" 2>/dev/null; return 0; }
sched() {   # TOPIC [env…] [-- flags…]: a one-shot of the topic's branch; prints the plist's DISPATCH_ARM
  local t=$1; shift; local e=() f=()
  while [ $# -gt 0 ] && [ "$1" != -- ]; do e+=("$1"); shift; done
  [ "${1:-}" = -- ] && shift; f=("$@")
  rm_own "$LA"/org.example.claude.dispatch.repo."$t".*.plist 2>/dev/null
  env ${e[@]+"${e[@]}"} "$B/dispatch" "claude/laptop/2026-11-02-$t" --repo "$R" --at "$FUT 04:10" ${f[@]+"${f[@]}"} > "$T/out" 2>&1
  armof "$(pl "$t")"
}
# a fire as launchd would start the one-shot: its label, its plist's DISPATCH_ARM, the branch from origin
fire() {   # TOPIC WORD [flags…]
  local t=$1 w=$2; shift 2
  : > "$T/claude.calls"
  env DISPATCH_LOG="$H/fire-$t.log" DISPATCH_LABEL="org.example.claude.dispatch.repo.$t.000000000000" ${w:+DISPATCH_ARM=$w} \
    "$B/dispatch" "claude/laptop/2026-11-02-$t" --repo "$R" --headless "$@" > "$T/fire.out" 2>&1
}
recof() { python3 -c 'import glob, json, sys
for p in sorted(glob.glob(sys.argv[1] + "/*." + sys.argv[2] + ".*.json")):
    d = json.load(open(p))
print(json.dumps(d.get("arm"), sort_keys=True), d.get("arm_source"), d.get("model"), d.get("effort"))' "$RUNS" "$1" 2>/dev/null; }
rowsof() { python3 -c 'import json, sys
rows = [json.loads(l) for l in open(sys.argv[1])]
print(len(rows), *[(r["topic"], r["arm"], r["coin"], r["forced"], r["model"], r["effort"], bool(r["session"])) for r in rows])' "$ROWS" 2>/dev/null || echo 0; }

echo "the key: absent, past or garbled is today's dispatch, said nothing when absent"
clean; rm -f "$KEY"
check "$(sched worker)" "" "no key: the one-shot carries no arm"
check "$(grep -c 'builder rotation' "$T/out")" "0" "  and says nothing"
echo "until $PAST" > "$KEY"
check "$(sched worker)" "" "a passed day: no arm"
has "$T/out" "builder rotation off: it ended $PAST" "  said, the key being there"
echo "until next week" > "$KEY"
check "$(sched worker)" "" "a line that does not parse: no arm"
has "$T/out" "not \`until YYYY-MM-DD\`" "  said"
printf 'until\n%s\n' "$UNTIL" > "$KEY"   # bootstrap.sh's one word per line reads as the line
check "$(sched worker DISPATCH_COIN=1)" "sonnet-high:1:$UNTIL:1" "the key on (split one word per line): a specced brief draws"

echo "what reads as specced (blueprintlib.brief_specced)"
r=""; for line in "Tier: worker" "Tier: Sonnet 5.5 high" "Tier: claude-sonnet-5-5 high" "tier: worker" "Tier: sr-worker (Sonnet)" "Tier: principal-worker" "Tier: architect" "Tier: Opus 5.5 high" "Task: no tier" "Tier: Opus 5.5 high (not Sonnet)" "Tier: Haiku, Sonnet if it fails" "Tier: Opus 5.5 high (worker)"; do
  printf '%s\n' "$line" | python3 "$B/buildercoin.py" specced; r="$r$?"
done
check "$r" "000011111111" "worker, Sonnet and its full id are specced; sr-worker, a principal tier, another tier, Opus, none, Sonnet beside another model, or worker beside Opus are not"
# a claude-code block's tier: worker key over a Tier: line that is not specced: dispatch reads the line, so wharf check warns
cat > "$T/bp.md" <<'MD'
---
ship: "bpx"
repo: "repo"
created: 2026-11-02
blocks:
  - id: "bpx"
    depends_on: []
    provider: claude-code
    tier: worker
---
## bpx
Task: build it
Tier: TIERLINE
Why: a case
Start here: here
Done means: done
Not this: that
MD
cat > "$T/bp.py" <<'PY'
import sys
sys.path.insert(0, sys.argv[1]); import blueprintlib as b
src = open(sys.argv[2]).read()
for line in ("Opus 5.5 high", "worker (Sonnet 5.5 high)"):
    try:
        print(len([w for w in b.load(sys.argv[2], text=src.replace("TIERLINE", line))["warnings"] if "tier: worker" in w]))
    except b.BlueprintError as e:
        print("ERR", e.problems)
PY
check "$(python3 "$T/bp.py" "$B" "$T/bp.md" 2>&1 | tr '\n' ' ')" "1 0 " "a claude-code block's tier: worker over an Opus Tier: line warns; over a worker line it does not"

echo "the draw, on the one-shot road"
echo "until $UNTIL" > "$KEY"
check "$(sched worker DISPATCH_COIN=1)" "sonnet-high:1:$UNTIL:1" "Tier: worker, a forced coin of 1: Sonnet, forced"
has "$T/out" "builder rotation on until $UNTIL; coin 1: sonnet-high (forced)" "  the caller is told"
check "$(sched worker DISPATCH_COIN=0)" "opus-high:0:$UNTIL:1" "a forced coin of 0: Opus"
check "$(sched sonnet DISPATCH_COIN=1)" "sonnet-high:1:$UNTIL:1" "Tier: Sonnet …: specced"
check "$(sched block DISPATCH_COIN=1)" "sonnet-high:1:$UNTIL:1" "a lower-case tier: worker line (a blueprint block's key carried into its brief): specced"
check "$(sched worker)" "$(armof "$(pl worker)")" "an unforced draw is carried as drawn"
case "$(armof "$(pl worker)")" in opus-high:0:$UNTIL:0|sonnet-high:1:$UNTIL:0) r=ok;; *) r="$(armof "$(pl worker)")";; esac
check "$r" "ok" "  an unforced word: either arm, coin and arm agreeing, not forced"
check "$(sched worker DISPATCH_COIN=1 -- --model claude-opus-5-5)" "" "a typed --model draws nothing"
check "$(sched worker DISPATCH_COIN=1 -- --effort medium)" "" "a typed --effort draws nothing"
check "$(sched sr DISPATCH_COIN=1)" "" "sr-worker draws nothing (Sonnet on its line or not)"
check "$(sched prin DISPATCH_COIN=1)" "" "a principal tier draws nothing"
check "$(sched plain DISPATCH_COIN=1)" "" "a brief that is not specced draws nothing"
cp "$T/conf.json" "$T/repos.json"
check "$(sched worker DISPATCH_COIN=1)" "" "a confidential scope draws nothing"
has "$T/out" "builder rotation fenced: scope vault is confidential" "  said"
cp "$T/torn.json" "$T/repos.json"
check "$(sched worker DISPATCH_COIN=1)" "" "a torn registry draws nothing"
echo '{"repos": {}, "scopes": {"other": {"repos": ["elsewhere"]}}}' > "$T/repos.json"
check "$(sched worker DISPATCH_COIN=1)" "" "a repo in no scope draws nothing"
cp "$T/open.json" "$T/repos.json"
DISPATCH_ARM=bogus "$B/dispatch" claude/laptop/2026-11-02-plain --repo "$R" --at "$FUT 04:20" > "$T/out" 2>&1
check "$(armof "$(pl plain)")" "" "a carried word that does not read is no arm"

echo "the fire path: the arm runs, the record keeps it, one row"
clean
fire worker "sonnet-high:1:$UNTIL:0"
has "$T/claude.calls" "--model claude-sonnet-5-5 --effort high --permission-mode auto" "the Sonnet arm fires at its full id, high"
has "$H/fire-worker.log" "== builder coin: sonnet-high:1:$UNTIL:0 — claude-sonnet-5-5 high" "  the log names the arm"
check "$(recof worker)" "{\"coin\": 1, \"effort\": \"high\", \"forced\": false, \"model\": \"claude-sonnet-5-5\", \"name\": \"sonnet-high\", \"until\": \"$UNTIL\"} coin claude-sonnet-5-5 high" \
  "  the record's arm, arm_source coin, its model and effort"
check "$(rowsof)" "1 ('worker', 'sonnet-high', 1, False, 'claude-sonnet-5-5', 'high', True)" "  one row, by session"
check "$(grep -c '^DISPATCH_ARM=' "$T/env.calls")" "0" "  the session never sees DISPATCH_ARM (its own --next draws afresh)"
clean
fire worker "opus-high:0:$UNTIL:1"
has "$T/claude.calls" "--model claude-opus-5-5 --effort high --permission-mode auto" "the Opus arm fires at its full id, high"
check "$(recof worker | awk '{print $(NF-2)}')" "pinned" "  a forced coin's record says pinned"
check "$(rowsof)" "1 ('worker', 'opus-high', 0, True, 'claude-opus-5-5', 'high', True)" "  its row says forced"
clean
fire worker "sonnet-high:1:$UNTIL:0" --model claude-opus-5-5
has "$T/claude.calls" "--model claude-opus-5-5 --effort high" "a --model given at fire time wins"
has "$H/fire-worker.log" "dropped — a --model or --effort was given" "  the arm is dropped, said"
check "$(rowsof)" "0" "  and no row"
clean
fire sr "sonnet-high:1:$UNTIL:0"
has "$T/claude.calls" "--model opus --effort high" "a brief no longer specced at fire time: today's builder"
has "$H/fire-sr.log" "dropped — the brief as it fires is not specced (tier sr-worker)" "  said"
check "$(rowsof)" "0" "  no row"
clean
cp "$T/conf.json" "$T/repos.json"
fire worker "sonnet-high:1:$UNTIL:0"
check "$(rowsof)" "0" "a repo fenced at fire time (confidential): no row"
has "$H/fire-worker.log" "dropped — fenced: scope vault is confidential" "  the arm is dropped, said in the log"
clean
cp "$T/torn.json" "$T/repos.json"
fire worker "sonnet-high:1:$UNTIL:0"
check "$(rowsof)" "0" "a torn registry at fire time: no row"
cp "$T/open.json" "$T/repos.json"
clean
fire plain ""
has "$T/claude.calls" "--model opus --effort high" "no word: today's builder, unchanged"
check "$(recof plain | cut -d' ' -f1,2)" "null None" "  the record has no arm"
check "$(rowsof)" "0" "  and no row"

clean
fire worker "sonnet-high:1:$PAST:0"
has "$T/claude.calls" "--model opus --effort high" "a word whose window ended before it fired: today's builder"
has "$H/fire-worker.log" "dropped — its window ended $PAST" "  said"
check "$(rowsof)|$(recof worker | cut -d' ' -f1)" "0|null" "  no row, no arm on the record"
clean
mv "$KEY" "$KEY.off"
fire worker "sonnet-high:1:$UNTIL:0"
has "$T/claude.calls" "--model opus --effort high" "the key removed after the draw (the owner's switch): today's builder"
has "$H/fire-worker.log" "dropped — builder rotation off: no wharf-runs/builder-rotation" "  said"
check "$(rowsof)" "0" "  no row"
mv "$KEY.off" "$KEY"
clean
cp "$T/conf.json" "$T/repos.json"
fire worker "sonnet-high:1:$UNTIL:0"
has "$T/claude.calls" "--model opus --effort high" "a repo fenced since the draw runs today's builder, so run, record and row agree"
check "$(recof worker | cut -d' ' -f1)" "null" "  no arm on its record"
cp "$T/open.json" "$T/repos.json"
clean
env DISPATCH_COIN=1 DISPATCH_LOG="$H/fire-coin.log" DISPATCH_LABEL="org.example.claude.dispatch.repo.worker.000000000000" DISPATCH_ARM="sonnet-high:1:$UNTIL:1" \
  "$B/dispatch" claude/laptop/2026-11-02-worker --repo "$R" --headless > "$T/fire.out" 2>&1
check "$(grep -c '^DISPATCH_COIN=' "$T/env.calls")" "0" "DISPATCH_COIN never reaches the session (its --next would draw forced)"

echo "the dry run names the arm"
out=$(DISPATCH_COIN=1 env -u DISPATCH_LABEL "$B/dispatch" claude/laptop/2026-11-02-worker --repo "$R" --headless --dry-run 2>&1)
case "$out" in *"--model claude-sonnet-5-5 --effort high (builder coin sonnet-high:1:$UNTIL:1)"*) r=ok;; *) r="$out";; esac
check "$r" "ok" "a dry run draws and shows the arm it would run"

echo "the peer road: the ssh line carries the word"
clean
DISPATCH_COIN=1 "$B/dispatch" claude/laptop/2026-11-02-worker --repo "$R" --on buildbox > "$T/out" 2>&1
has "$T/ssh.calls" "DISPATCH_ARM=sonnet-high:1:$UNTIL:1 DISPATCH_DEPTH=" "the peer's dispatch is handed the arm"
clean
DISPATCH_COIN=1 "$B/dispatch" claude/laptop/2026-11-02-worker --repo "$R" --on buildbox --model claude-opus-5-5 > "$T/out" 2>&1
has "$T/ssh.calls" "DISPATCH_ARM=- DISPATCH_DEPTH=" "  a typed --model hands none: the peer is told none was drawn"
clean
# the peer's side: a call carrying the word schedules its one-shot with it, and draws nothing of its own
DISPATCH_ARM="opus-high:0:$UNTIL:0" DISPATCH_COIN=1 "$B/dispatch" claude/laptop/2026-11-02-worker --repo "$R" --at "$FUT 04:30" > "$T/out" 2>&1
check "$(armof "$(pl worker)")" "opus-high:0:$UNTIL:0" "a carried word rides into the one-shot as given, no second draw"
DISPATCH_ARM=- DISPATCH_COIN=1 "$B/dispatch" claude/laptop/2026-11-02-worker --repo "$R" --at "$FUT 04:40" > "$T/out" 2>&1
check "$(armof "$(ls "$LA"/org.example.claude.dispatch.repo.worker.*0440.plist 2>/dev/null | head -1)")" "" "  a sender that drew none: the peer draws none of its own (the sender's key decides)"

echo "the queue road: the entry carries the word, the claimed job too"
clean
git init -q --bare "$T/queue.git"
echo "$T/queue.git" > "$REGATTA_CONFIG/wharf-runs/queue-repo"
DISPATCH_COIN=1 env -u DISPATCH_LABEL "$B/dispatch" claude/laptop/2026-11-02-worker --repo "$R" > "$T/out" 2>&1
qent=$(git --git-dir="$T/queue.git" ls-tree -r --name-only refs/regatta/queue 2>/dev/null | grep '^queue/' | head -1)
check "$(git --git-dir="$T/queue.git" show "refs/regatta/queue:$qent" 2>/dev/null | python3 -c 'import json, sys; print(json.load(sys.stdin).get("env", {}).get("DISPATCH_ARM"))' 2>/dev/null)" \
  "sonnet-high:1:$UNTIL:1" "the queue's entry carries the arm drawn at enqueue"
qp=$(ls "$LA"/org.example.claude.dispatch.repo.worker.q[0-9]*.plist 2>/dev/null | head -1)
check "$([ -n "$qp" ] && python3 -c 'import plistlib, sys; print(plistlib.load(open(sys.argv[1], "rb")).get("EnvironmentVariables", {}).get("DISPATCH_ARM"))' "$qp")" \
  "sonnet-high:1:${UNTIL}:1" "  the claimed job's environment carries it to the fire path"
clean
git --git-dir="$T/queue.git" update-ref -d refs/regatta/queue 2>/dev/null
rm_own "$HL/Caches/run-seed/queue" 2>/dev/null
DISPATCH_COIN=1 env -u DISPATCH_LABEL "$B/dispatch" claude/laptop/2026-11-02-worker --repo "$R" --model claude-opus-5-5 > "$T/out" 2>&1
qent=$(git --git-dir="$T/queue.git" ls-tree -r --name-only refs/regatta/queue 2>/dev/null | grep '^queue/' | head -1)
check "$(git --git-dir="$T/queue.git" show "refs/regatta/queue:$qent" 2>/dev/null | python3 -c 'import json, sys; print(json.load(sys.stdin).get("env", {}).get("DISPATCH_ARM"))' 2>/dev/null)" \
  "None" "  a typed --model: the entry carries none"
rm -f "$REGATTA_CONFIG/wharf-runs/queue-repo"

cat > "$T/bad.py" <<'PY'
import importlib.machinery, sys
q = importlib.machinery.SourceFileLoader("dq", sys.argv[1]).load_module()
for w in ("sonnet-high:1:2026-11-30:0", "sonnet-high:1:garbage:0", "haiku-low:1:2026-11-30:0"):
    print(q.bad_args({"args": [], "env": {"DISPATCH_ARM": w}}))
PY
check "$(python3 "$T/bad.py" "$B/dispatch-queue" 2>&1)" "None
env DISPATCH_ARM 'sonnet-high:1:garbage:0' is no builder arm
env DISPATCH_ARM 'haiku-low:1:2026-11-30:0' is no builder arm" "the queue holds an entry's DISPATCH_ARM to the word's pattern"

echo "a requeued coin run keeps its arm, never a typed model"
cat > "$T/rq.py" <<'PY'
import importlib.machinery, sys
q = importlib.machinery.SourceFileLoader("dq", sys.argv[1]).load_module()
w = sys.argv[2]
st = {"repo": sys.argv[3], "branch": "claude/laptop/2026-11-02-worker", "model": "claude-sonnet-5-5", "effort": "high",
      "arm": {"name": "sonnet-high", "model": "claude-sonnet-5-5", "effort": "high", "coin": 1, "until": w, "forced": False}}
e = q.entry_of_record(st, "laptop", 0)
print(e["env"].get("DISPATCH_ARM"), "--model" in e["args"])
print(q.run_flags(["--note", "x"], st, "sonnet-high:1:%s:0" % w), q.run_flags(["--note", "x"], st, None))
st["model"] = "claude-opus-5-5"   # a run whose record ran another model than its arm: no arm to carry
print(q.entry_of_record(st, "laptop", 0)["env"].get("DISPATCH_ARM"))
PY
out=$(python3 "$T/rq.py" "$B/dispatch-queue" "$UNTIL" "$R" 2>&1)
check "$out" "sonnet-high:1:$UNTIL:0 False
['--note', 'x'] ['--note', 'x', '--model', 'claude-sonnet-5-5', '--effort', 'high']
None" "a record's arm rides as DISPATCH_ARM, its model untyped; an entry without it keeps the typed pair"

echo
[ "$fails" = 0 ] && echo "test_builder_coin: all passed" || echo "test_builder_coin: $fails failed"
[ "$fails" = 0 ]
