#!/usr/bin/env bash
# Tests for the builder rotation (bin/buildercoin.py; dispatch's header; S6 of docs/self-tuning-2026-10-26.md):
# a specced or plain-Opus brief's run draws its builder once where it is enqueued or scheduled, every road carries the draw
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
# the opted-out shape: a confidential scope that opts out of the coins (scope-rotation, 2026-11-04)
echo '{"repos": {}, "scopes": {"open": {"repos": ["*"]}, "vault": {"repos": ["*"], "confidential": true, "rotation": false}}}' > "$T/conf.json"
# the drawing shape: a confidential scope with no rotation key, which draws and writes its row
echo '{"repos": {}, "scopes": {"open": {"repos": ["*"]}, "ap": {"repos": ["repo", "*/repo"], "confidential": true}}}' > "$T/ap.json"
# a rotation that does not read: fenced, as a narrowing key that does not read narrows to nothing
echo '{"repos": {}, "scopes": {"ap": {"repos": ["repo", "*/repo"], "confidential": true, "rotation": "no"}}}' > "$T/odd.json"
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
seed bullet-sr "- Tier: sr-worker"
seed bullet-worker "- Tier: worker"
seed bullet-prin "- Tier: principal-worker"
seed plain "Tier: Opus 5.5 high, per the rules' tier table"
seed xhigh "Tier: Opus 5.5 xhigh"
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
print(len(rows), *[(r["topic"], r["arm"], r["coin"], r["forced"], r["model"], r["effort"], bool(r["session"])) + ((r["brief_class"],) if r.get("brief_class") != "specced" else ()) for r in rows])' "$ROWS" 2>/dev/null || echo 0; }

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
echo "what the coin draws for (blueprintlib.brief_rotates)"
r=""; for line in "Tier: worker" "Tier: Sonnet 5.5 high" "Tier: Opus 5.5 high" "Tier: Opus 5.5 \`high\`, per the rules' tier table" "Tier: claude-opus-5-5" "Tier: Opus 5.5 xhigh" "Tier: Opus 5.5 medium" "Tier: Opus 5.5 high (not Sonnet)" "Tier: sr-worker (Opus high)" "Tier: Opus 5.5 high, principal" "Tier: Opus 5.5 high (worker)" "Task: no tier" \
    "**Tier:** Opus 5.5 high, per rule engineering" "Tier: Opus 5.5 high, per the rules’ tier table" "tier: opus high" "Tier: Opus 5.5 x-high" \
    "Tier: Opus 5.5 high (hooks are gates; judgement is the work)" "Tier: Opus 5.5 high, per the rules' tier table (sr-worker: Ring 0)" \
    "Tier: Opus 5.5 high (physical: the yard node)" "Tier: Gemini or Opus"; do
  r="$r$(printf '%s\n' "$line" | python3 "$B/buildercoin.py" rotates || echo -)."
done
check "$r" "specced.specced.plain.plain.plain.-.-.-.-.-.-.-.plain.plain.plain.-.-.-.-.-." "specced, then plain Opus (the rules' default line and nothing more, bold or lower-case); any other Opus line, a reason, a tier word or no Tier line draws nothing"
check "$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import buildercoin as c
w = c.read_odds()[0]; print(w, [sum(c.coin_of(r, w) == k for r in range(sum(w))) for k in range(5)])' "$B")" "(1, 2, 2, 1, 1) [1, 2, 2, 1, 1]" \
  "the coin: no builder-odds reads 1:2:2:1:1, and of 7 rolls each of the five arms draws by its weight (the owner's D2, 2026-11-04; S8's two Sol arms)"
check "$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import buildercoin as c
print(c.road_weights((1, 2, 2, 1, 1), True), c.road_weights((1, 2, 2, 1, 1)))' "$B")|$(DISPATCH_COIN_ROADS=antigravity python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import buildercoin as c
print(c.road_weights((1, 2, 2, 1, 1), True), c.road_weights((1, 2, 2, 1, 1)))' "$B")" "(1, 2, 0, 1, 1) (1, 2, 0, 1, 1)|(1, 2, 2, 1, 1) (1, 2, 0, 1, 1)" \
  "  rolled: an arm with no road in dispatch weighs 0 (Argon until S4; Codex has its road), a test's road at the draw only"
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
# a tier: sr-worker key over a plain-Opus line would put a pinned tier on the coin: a problem, not a warning
sed 's/tier: worker/tier: sr-worker/; s/TIERLINE/Opus 5.5 high/' "$T/bp.md" > "$T/bp2.md"
check "$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import blueprintlib as b
try: b.load(sys.argv[2]); print("loaded")
except b.BlueprintError as e: print(len([p for p in e.problems if "tier: sr-worker" in p]))' "$B" "$T/bp2.md" 2>&1)" "1" "a claude-code block's tier: sr-worker over a plain-Opus Tier: line is refused (the coin would draw Sonnet for a pinned tier)"
cat > "$T/bp2.py" <<'PY'
import sys
sys.path.insert(0, sys.argv[1]); import blueprintlib as b
src = open(sys.argv[2]).read().replace("tier: worker", "tier: sr-worker").replace("TIERLINE", "Opus 5.5 high")
print(b.load(sys.argv[2], text=src)["warnings"])
PY
python3 "$T/bp2.py" "$B" "$T/bp.md" > "$T/bp2.out" 2>&1
has "$T/bp2.out" "has tier: sr-worker, but its Tier: line reads as plain" "a tier: sr-worker key over a plain-Opus Tier: line warns: the coin would draw for it"

echo "the draw, on the one-shot road"
echo "until $UNTIL" > "$KEY"
check "$(sched worker DISPATCH_COIN=1)" "sonnet-high:1:$UNTIL:1" "Tier: worker, a forced coin of 1: Sonnet, forced"
has "$T/out" "builder rotation on until $UNTIL; odds opus-high=1,sonnet-high=2,argon-high=2,gpt-big=1,gpt-mid=1; coin 1: sonnet-high (forced)" "  the caller is told"
check "$(sched worker DISPATCH_COIN=0)" "opus-high:0:$UNTIL:1" "a forced coin of 0: Opus"
check "$(sched sonnet DISPATCH_COIN=1)" "sonnet-high:1:$UNTIL:1" "Tier: Sonnet …: specced"
check "$(sched block DISPATCH_COIN=1)" "sonnet-high:1:$UNTIL:1" "a lower-case tier: worker line (a blueprint block's key carried into its brief): specced"
check "$(sched worker)" "$(armof "$(pl worker)")" "an unforced draw is carried as drawn"
case "$(armof "$(pl worker)")" in opus-high:0:$UNTIL:0|sonnet-high:1:$UNTIL:0|opus-high:[234]:$UNTIL:0) r=ok;; *) r="$(armof "$(pl worker)")";; esac
check "$r" "ok" "  an unforced word: any arm, coin and arm agreeing (Argon's coin as its Opus fallback, no road yet), not forced"
check "$(sched worker DISPATCH_COIN=1 -- --model claude-opus-5-5)" "" "a typed --model draws nothing"
check "$(sched worker DISPATCH_COIN=1 -- --effort medium)" "" "a typed --effort draws nothing"
check "$(sched sr DISPATCH_COIN=1)" "" "sr-worker draws nothing (Sonnet on its line or not)"
check "$(sched prin DISPATCH_COIN=1)" "" "a principal tier draws nothing"
check "$(sched plain DISPATCH_COIN=1)" "sonnet-high:1:$UNTIL:1" "a plain-Opus brief (the rules' default written out) draws"
check "$(sched xhigh DISPATCH_COIN=1)" "" "an Opus line at another effort draws nothing"
cp "$T/conf.json" "$T/repos.json"
check "$(sched worker DISPATCH_COIN=1)" "" "a confidential scope with rotation: false draws nothing (the opted-out shape)"
has "$T/out" "builder rotation fenced: scope vault does not rotate (rotation: false)" "  said"
echo '{"repos": {}, "scopes": {"open": {"repos": ["*"]}, "vault": {"repos": ["*"], "rotation": false}}}' > "$T/repos.json"
check "$(sched worker DISPATCH_COIN=1)" "" "  a repo in two scopes, the second rotation: false: fenced, not only the first scope judged"
cp "$T/odd.json" "$T/repos.json"
check "$(sched worker DISPATCH_COIN=1)" "" "a rotation that is no bool draws nothing"
has "$T/out" "builder rotation fenced: scope ap's rotation is 'no', not true or false" "  said"
cp "$T/ap.json" "$T/repos.json"
check "$(sched worker DISPATCH_COIN=1)" "sonnet-high:1:$UNTIL:1" "a confidential scope with no rotation key draws (the drawing shape)"
# the Argon design's G3 wall: a confidential scope's build never goes to another vendor, a road or none
check "$(sched worker DISPATCH_COIN=2 DISPATCH_COIN_ROADS=antigravity)" "opus-high:2:$UNTIL:1" \
  "  a confidential scope's forced vendor coin falls back to Opus, a road there or not"
has "$T/out" "a confidential scope never runs on antigravity" "  said"
check "$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import buildercoin as c
c.ROADS = ("claude", "antigravity")
c.read_odds = lambda: ((1, 2, 2), "odds")
sys.exit(c.main(["arm", sys.argv[2], "--repo", sys.argv[3]]))' "$B" "argon-high:2:$UNTIL:0" "$R" | cut -d' ' -f1-3)" \
  "claude-opus-5-5 high opus-high:2:$UNTIL:0" "  at fire, a vendor word in a confidential scope runs as its Opus fallback, a road here or not"
cp "$T/torn.json" "$T/repos.json"
check "$(sched worker DISPATCH_COIN=1)" "" "a torn registry draws nothing"
echo '{"repos": {}, "scopes": {"other": {"repos": ["elsewhere"]}}}' > "$T/repos.json"
check "$(sched worker DISPATCH_COIN=1)" "" "a repo in no scope draws nothing"
cp "$T/open.json" "$T/repos.json"
DISPATCH_ARM=bogus "$B/dispatch" claude/laptop/2026-11-02-xhigh --repo "$R" --at "$FUT 04:20" > "$T/out" 2>&1
check "$(armof "$(pl xhigh)")" "" "a carried word that does not read is no arm"

echo "the fire path: the arm runs, the record keeps it, one row"
clean
fire worker "sonnet-high:1:$UNTIL:0"
has "$T/claude.calls" "--model claude-sonnet-5-5 --effort high --permission-mode auto" "the Sonnet arm fires at its full id, high"
has "$H/fire-worker.log" "== builder coin: sonnet-high:1:$UNTIL:0 — claude-sonnet-5-5 high" "  the log names the arm"
check "$(recof worker)" "{\"agent\": \"claude\", \"coin\": 1, \"effort\": \"high\", \"forced\": false, \"model\": \"claude-sonnet-5-5\", \"name\": \"sonnet-high\", \"until\": \"$UNTIL\"} coin claude-sonnet-5-5 high" \
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
has "$H/fire-sr.log" "dropped — the brief as it fires is not on the coin (tier sr-worker)" "  said"
check "$(rowsof)" "0" "  no row"
clean
cp "$T/conf.json" "$T/repos.json"
fire worker "sonnet-high:1:$UNTIL:0"
check "$(rowsof)" "0" "a repo fenced at fire time (rotation: false): no row"
has "$H/fire-worker.log" "dropped — fenced: scope vault does not rotate (rotation: false)" "  the arm is dropped, said in the log"
clean
fire worker "gpt-big:3:$UNTIL:0"
check "$?" "0" "a GPT arm fenced since the draw: today's builder runs"
has "$T/claude.calls" "--model claude-opus-5-5 --effort high" "  the cancelled arm falls back to Opus"
has "$H/fire-worker.log" "the vendor arm was disabled before fire — fallback to Opus before any vendor turn" "  skips vendor pre-flight after cancelling the arm"
check "$(rowsof)|$(recof worker | cut -d' ' -f1,2)" "0|null None" "  no arm or sample for the cancelled draw"
cp "$T/open.json" "$T/repos.json"
clean
# a worker brief here and at the draw; on origin, since, it names a principal tier: the fire's fetch reads that one
seed toprin "Tier: worker"
br=claude/laptop/2026-11-02-toprin
blob=$(printf '# toprin\nTask: build it\nTier: principal-worker\n' | git -C "$R" hash-object -w --stdin)
GIT_INDEX_FILE="$T/seed.idx" git -C "$R" read-tree "$br"
GIT_INDEX_FILE="$T/seed.idx" git -C "$R" update-index --add --cacheinfo "100644,$blob,docs/handoff/2026-11-02-toprin.md"
tree=$(GIT_INDEX_FILE="$T/seed.idx" git -C "$R" write-tree); rm -f "$T/seed.idx"
git --git-dir="$R/.git" send-pack "$T/origin.git" "$(git -C "$R" commit-tree "$tree" -p "$br" -m "toprin: principal now"):refs/heads/$br" >/dev/null 2>&1
fire toprin "gpt-big:3:$UNTIL:0"
check "$?" "0" "a GPT arm whose brief names a principal tier at fire: the Claude principal build runs, never FAILED"
has "$H/fire-toprin.log" "the vendor arm was disabled before fire" "  the cancelled-arm road is the one taken"
has "$T/claude.calls" "--model opus --effort xhigh" "  at the tier's own model and effort, never the GPT model or the fallback's high"
check "$(grep -c 'FAILED' "$H/fire-toprin.log")" "0" "  no FAILED line"
cp "$T/conf.json" "$T/repos.json"
clean
cp "$T/open.json" "$T/repos.json"
echo repo > "$REGATTA_CONFIG/wharf-runs/public-repos"
fire worker "gpt-mid:4:$UNTIL:0"
check "$?" "0" "a GPT coin arm on a public repo falls back before any vendor turn"
has "$H/fire-worker.log" "vendor pre-flight fallback: a public repo: no vendor build" "  the vendor fence gives the fallback reason"
has "$T/claude.calls" "--model claude-opus-5-5 --effort high" "  Opus builds the public repo"
check "$(recof worker | awk '{print $(NF-2)}')" "fallback" "  the record identifies the coin fallback"
for flag in --harness --model; do
  clean
  value=codex; [ "$flag" = --model ] && value=gpt-6.1-sol
  fire worker "gpt-mid:4:$UNTIL:0" "$flag" "$value"
  check "$?" "2" "a typed $flag $value on a public repo stays refused, even with a carried coin word"
  has "$H/fire-worker.log" "refused for good: a public repo: no vendor build" "  the typed selection keeps the fence refusal"
  check "$(wc -c < "$T/claude.calls" | tr -d ' ')" "0" "  no Claude fallback for the typed selection"
done
rm -f "$REGATTA_CONFIG/wharf-runs/public-repos"
clean
cp "$T/odd.json" "$T/repos.json"
fire worker "sonnet-high:1:$UNTIL:0"
check "$(rowsof)" "0" "a rotation that is no bool at fire time: no row"
clean
cp "$T/ap.json" "$T/repos.json"
fire worker "sonnet-high:1:$UNTIL:0"
has "$T/claude.calls" "--model claude-sonnet-5-5 --effort high --permission-mode auto" "a confidential scope with no rotation key: the arm fires"
check "$(rowsof)" "1 ('worker', 'sonnet-high', 1, False, 'claude-sonnet-5-5', 'high', True)" "  one row"
check "$(python3 -c 'import json, sys; r = json.loads(open(sys.argv[1]).readline()); print(r["scope"], r["confidential"])' "$ROWS")" "ap True" \
  "  the row carries its scope and confidential: true, so trim can tell"
cp "$T/open.json" "$T/repos.json"
clean
fire worker "sonnet-high:1:$UNTIL:0"
check "$(python3 -c 'import json, sys; r = json.loads(open(sys.argv[1]).readline()); print(r["scope"], r["confidential"])' "$ROWS")" "open False" \
  "  an open scope's row says confidential: false"
clean
cp "$T/torn.json" "$T/repos.json"
fire worker "sonnet-high:1:$UNTIL:0"
check "$(rowsof)" "0" "a torn registry at fire time: no row"
cp "$T/open.json" "$T/repos.json"
clean
fire plain "sonnet-high:1:$UNTIL:0"
has "$T/claude.calls" "--model claude-sonnet-5-5 --effort high --permission-mode auto" "a plain-Opus brief's Sonnet arm fires"
check "$(rowsof)" "1 ('plain', 'sonnet-high', 1, False, 'claude-sonnet-5-5', 'high', True, 'plain')" "  its row says the brief was plain"
clean
fire xhigh ""
has "$T/claude.calls" "--model opus --effort high" "no word: today's builder, unchanged"
check "$(recof xhigh | cut -d' ' -f1,2)" "null None" "  the record has no arm"
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

echo "the third arm: one grammar, held in every copy (S3 of docs/argon-builder-arm-2026-11-03.md)"
G=$(python3 "$B/buildercoin.py" grammar)
check "$G" "(opus-high|sonnet-high|argon-high|gpt-big|gpt-mid):[0-4]:[0-9]{4}-[0-9]{2}-[0-9]{2}:[01]" "buildercoin's grammar names the five arms, its coin 0 to 4"
HB="$(cd "$B/../../helm/bin" && pwd)"
check "$(grep -c -F -- "[[ \"\$arm_word\" =~ ^$G\$ ]]" "$B/dispatch")" "2" "dispatch's two tests (a carried word, the draw's) are the grammar, word for word"
check "$(grep -c -F -- "ARM_WORD = re.compile(r\"$G\")" "$B/dispatch-queue")" "1" "dispatch-queue's ARM_WORD is the grammar"
check "$(grep -c -F -- "ARM_WORD = re.compile(r\"$G\")" "$HB/stalls_tick.py")" "1" "helm's stalls_tick ARM_WORD is the grammar"
check "$(grep -c -F 'opus-high|sonnet-high)' "$B/dispatch" "$B/dispatch-queue" "$HB/stalls_tick.py" | awk -F: '{n+=$2} END {print n}')" "0" \
  "  and no copy still names two arms alone"
# each copy reads an argon-high word, and refuses a coin past the arms or a name off its coin
check "$(python3 "$B/buildercoin.py" arm "argon-high:2:$UNTIL:0" | cut -d' ' -f1-3)" "gemini-4-argon-high high argon-high:2:$UNTIL:0" \
  "buildercoin reads argon-high: Gemini 4 Argon at high"
check "$(python3 "$B/buildercoin.py" arm "argon-high:2:$UNTIL:0" | cut -d' ' -f4- | python3 -c 'import json, sys; print(json.load(sys.stdin)["agent"])')" "antigravity" \
  "  its agent: antigravity (agy-road's provider word)"
check "$(python3 "$B/buildercoin.py" need "argon-high:2:$UNTIL:0")|$(python3 "$B/buildercoin.py" need "opus-high:2:$UNTIL:0")|$(python3 "$B/buildercoin.py" need "sonnet-high:1:$UNTIL:0")" "agy||" \
  "  it needs a host with agy; Opus in its place, or Sonnet, needs none"
r=""; for w in "opus-high:2:$UNTIL:0" "sonnet-high:2:$UNTIL:0" "argon-high:1:$UNTIL:0" "argon-high:3:$UNTIL:0" "argon-high:2:$UNTIL:2" "opus-high:1:$UNTIL:0"; do
  python3 "$B/buildercoin.py" arm "$w" > /dev/null 2>&1; r="$r$?"
done
check "$r" "011111" "opus-high under Argon's coin reads (the fallback); Sonnet under it, Argon under Sonnet's, a coin past the arms, a forced 2 or Opus under Sonnet's do not"
cat > "$T/copies.py" <<'PY'
import importlib.machinery, sys
q = importlib.machinery.SourceFileLoader("dq", sys.argv[1]).load_module()
sys.path.insert(0, sys.argv[2])
import stalls_tick as k
u = sys.argv[3]
for w in ("argon-high:2:%s:0" % u, "opus-high:2:%s:1" % u, "argon-high:5:%s:0" % u):
    print(q.bad_args({"args": [], "env": {"DISPATCH_ARM": w}}))
arm = {"name": "argon-high", "model": "gemini-4-argon-high", "effort": "high", "coin": 2, "until": u, "forced": False, "agent": "antigravity"}
print(k.arm_word({"model": "gemini-4-argon-high", "effort": "high", "arm": arm}))
print(k.arm_word({"model": "claude-opus-5-5", "effort": "high", "arm": dict(arm, name="opus-high", model="claude-opus-5-5", fallback=True)}))
print(q.arm_word({"model": "gemini-4-argon-high", "effort": "high", "arm": arm}))
PY
check "$(python3 "$T/copies.py" "$B/dispatch-queue" "$HB" "$UNTIL" 2>&1)" "None
None
env DISPATCH_ARM 'argon-high:5:$UNTIL:0' is no builder arm
argon-high:2:$UNTIL:0
None
argon-high:2:$UNTIL:0" "the queue holds an argon-high word and a fallback one, refuses a coin past the arms; helm's and the queue's retry rebuild both words"

echo "the odds: a fleet limit, read at the draw"
ODK="$REGATTA_CONFIG/wharf-runs/builder-odds"
check "$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import buildercoin as c
print([c.odds_of(x) for x in ("1:2:2", "3/5", "1/5", " 2 : 3 : 0 ", "3/2", "1:2", "x")])' "$B")" "[(1, 2, 2), (2, 3, 0), (4, 1, 0), (2, 3, 0), None, None, None]" \
  "a row's odds in both forms: o:s:a, and #459's n/d (n Sonnet in d, no Argon)"
echo "opus-high=0,sonnet-high=1,argon-high=0" > "$ODK"
check "$(sched worker)" "sonnet-high:1:$UNTIL:0" "builder-odds with Sonnet's weight alone: an unforced draw is Sonnet"
has "$T/out" "odds opus-high=0,sonnet-high=1,argon-high=0; coin 1: sonnet-high" "  the caller is told the odds it drew by"
printf 'sonnet-high=1\n' > "$ODK"
check "$(sched worker)" "sonnet-high:1:$UNTIL:0" "  an arm left out weighs 0"
echo "argon-high=1" > "$ODK"
# a bare draw, no brief class: with both Claude weights 0 a worker brief would take gpt-mid alone (gpt_class, S8)
check "$(python3 "$B/buildercoin.py" draw "$R" 2> "$T/out")" "" "builder-odds weighing only Argon while it has no road: no arm, never Opus in its place"
has "$T/out" "weighs only arms with no road in dispatch yet" "  said"
printf 'opus-high=0, sonnet-high=1 # the owner, a note\nargon-high=1\n' > "$ODK"
check "$(sched worker)" "sonnet-high:1:$UNTIL:0" "a note after # (on its line and the lines after it) is no text, spaces split arms"
has "$T/out" "odds opus-high=0,sonnet-high=1; coin 1" "  read without it"
echo "opus-high=0,sonnet-high=0,argon-high=0" > "$ODK"
check "$(sched worker)" "" "every weight 0: no arm"
has "$T/out" "gives every arm 0" "  said"
echo "1:2" > "$ODK"
check "$(sched worker)" "" "an invalid positional value draws no arm"
has "$T/out" "not \`opus-high=W,sonnet-high=W,argon-high=W\`" "  said"
rm -f "$ODK"

echo "the fallback: an Argon draw with no builder host, or no road for it"
check "$(sched worker DISPATCH_COIN=2)" "opus-high:2:$UNTIL:1" "an Argon coin while dispatch has no road for antigravity: Opus under Argon's coin"
has "$T/out" "coin 2: argon-high (forced) — fallback to opus-high: no road for antigravity in dispatch yet (run_vendor)" "  said"
check "$(sched worker DISPATCH_COIN=2 DISPATCH_COIN_ROADS=antigravity)" "opus-high:2:$UNTIL:1" "  a road, and no queue home (no hosts ref): Opus too"
has "$T/out" "fallback to opus-high: no queue home here" "  said"
check "$(grep -c 'needs' "$(pl worker)")" "0" "  the fallback's one-shot needs nothing"

# a queue home, its hosts ref, and buildbox declared a builder host (agy) by this host's features line
git init -q --bare "$T/q3.git"
echo "$T/q3.git" > "$REGATTA_CONFIG/wharf-runs/queue-repo"
echo "buildbox:agy" > "$REGATTA_CONFIG/wharf-runs/features"
NOW=$(date +%s)
hostrow() { printf '{"host": "buildbox", "at": %s, "load": null, "mem": null, "limits": {}, "headroom": {}, "slots": {}, "runs": []}\n' "$1" > "$T/row.json"
  DISPATCH_HOST=buildbox python3 "$B/dispatch-queue" hosts put --file "$T/row.json" --refresh > /dev/null 2>&1; }
qreset() { git --git-dir="$T/q3.git" update-ref -d refs/regatta/queue 2>/dev/null; rm_own "$HL/Caches/run-seed/queue" 2>/dev/null; clean; }
qentry() { local k; k=$(git --git-dir="$T/q3.git" ls-tree -r --name-only refs/regatta/queue 2>/dev/null | grep '^queue/' | head -1)
  git --git-dir="$T/q3.git" show "refs/regatta/queue:$k" 2>/dev/null | python3 -c 'import json, sys; e = json.load(sys.stdin)
print(e.get("env", {}).get("DISPATCH_ARM"), e.get("needs"), "--needs" in (e.get("args") or []) and e["args"][e["args"].index("--needs") + 1], e.get("state"))' 2>/dev/null; }
python3 "$B/dispatch-queue" fresh --repo "$R" --needs agy > "$T/fresh.out" 2>&1; rc=$?
check "$rc" "3" "fresh: a builder host with no row on the hosts ref is none (exit 3)"
has "$T/fresh.out" "buildbox: no row on the hosts ref" "  said"
hostrow $((NOW - 3600))
python3 "$B/dispatch-queue" fresh --repo "$R" --needs agy > "$T/fresh.out" 2>&1; rc=$?
check "$rc" "3" "fresh: its row an hour old is none"
has "$T/fresh.out" "buildbox: its row is 60 min old" "  said"
qreset
DISPATCH_COIN=2 DISPATCH_COIN_ROADS=antigravity env -u DISPATCH_LABEL "$B/dispatch" claude/laptop/2026-11-02-worker --repo "$R" > "$T/out" 2>&1
check "$(qentry)" "opus-high:2:$UNTIL:1 [] False claimed" "an Argon draw with only a stale builder row: the entry runs Opus, needing nothing (this host claims it)"
has "$T/out" "fallback to opus-high: buildbox: its row is 60 min old" "  the caller is told why"
hostrow "$NOW"
check "$(python3 "$B/dispatch-queue" fresh --repo "$R" --needs agy 2>&1)" '{"hosts": ["buildbox"], "why": null}' "fresh: a row just sampled is a builder host"
check "$(python3 "$B/dispatch-queue" fresh --repo "$R" --needs agy,gpu > /dev/null 2>&1; echo $?)" "3" "  a need its features line lacks is none"
qreset
DISPATCH_COIN=2 DISPATCH_COIN_ROADS=antigravity env -u DISPATCH_LABEL "$B/dispatch" claude/laptop/2026-11-02-worker --repo "$R" > "$T/out" 2>&1
check "$(qentry)" "argon-high:2:$UNTIL:1 ['agy'] agy queued" "an Argon draw with a fresh builder host: the entry carries argon-high and --needs agy"
has "$T/out" "coin 2: argon-high (forced) — builder host buildbox fresh" "  the caller is told"
check "$(ls "$LA"/org.example.claude.dispatch.repo.worker.q[0-9]*.plist 2>/dev/null | wc -l | tr -d ' ')" "0" "  this host, with no agy, claims none of it"
check "$(git --git-dir="$T/q3.git" show "refs/regatta/queue:$(git --git-dir="$T/q3.git" ls-tree -r --name-only refs/regatta/queue | grep '^queue/' | head -1)" 2>/dev/null | python3 -c 'import json, sys; print(json.load(sys.stdin).get("arm_need"))')" "agy" \
  "  the entry names agy as the arm's need (the re-draw drops that one alone)"
DISPATCH_QUEUE_NOW=$((NOW + 600)) "$B/dispatch" --sweep > "$T/sweep.out" 2>&1
check "$(qentry)" "argon-high:2:$UNTIL:1 ['agy'] agy queued" "  a sweep before REDRAW_AGE leaves it to its builder host"
DISPATCH_QUEUE_NOW=$((NOW + 1900)) "$B/dispatch" --sweep > "$T/sweep.out" 2>&1
check "$(qentry | cut -d' ' -f1-3)" "opus-high:2:$UNTIL:1 [] False" "  a sweep past it: unclaimed, it is drawn again as Opus under Argon's coin, for any host"
has "$T/sweep.out" "re-drew fleet:repo--worker: argon-high:2:$UNTIL:1 unclaimed" "  said"
has "$T/sweep.out" "— opus-high:2:$UNTIL:1, for any host" "  with the word it runs now"
qreset
echo "buildbox:agy,mac" > "$REGATTA_CONFIG/wharf-runs/features"   # a host that meets both, or enqueue refuses the run
DISPATCH_ARM="argon-high:2:$UNTIL:0" env -u DISPATCH_LABEL "$B/dispatch" claude/laptop/2026-11-02-worker --repo "$R" --needs mac > "$T/out" 2>&1
check "$(qentry)" "argon-high:2:$UNTIL:0 ['agy', 'mac'] agy,mac queued" "a carried argon-high word (a peer's, a retry's): --needs agy beside the typed ones"
qreset
DISPATCH_COIN=2 DISPATCH_COIN_ROADS=antigravity env -u DISPATCH_LABEL "$B/dispatch" claude/laptop/2026-11-02-worker --repo "$R" --needs mac > "$T/out" 2>&1
check "$(qentry | cut -d' ' -f1-4)" "argon-high:2:$UNTIL:1 ['agy', 'mac'] agy,mac" "an Argon draw for a run that needs mac: a builder host with agy and mac is fresh, so Argon"
qreset
echo "buildbox:agy" > "$REGATTA_CONFIG/wharf-runs/features"; echo "laptop:mac" >> "$REGATTA_CONFIG/wharf-runs/features"
DISPATCH_COIN=2 DISPATCH_COIN_ROADS=antigravity env -u DISPATCH_LABEL "$B/dispatch" claude/laptop/2026-11-02-worker --repo "$R" --needs mac > "$T/out" 2>&1; rc=$?
check "$rc|$(qentry | cut -d' ' -f1-2)" "0|opus-high:2:$UNTIL:1 ['mac']" "  no builder host meets the run's own needs: Opus, never a run no host may take"
has "$T/out" "fallback to opus-high: no host's features line names agy,mac" "  said"
qreset
DISPATCH_COIN=2 DISPATCH_COIN_ROADS=antigravity env -u DISPATCH_LABEL "$B/dispatch" claude/laptop/2026-11-02-worker --repo "$R" --pin here > "$T/out" 2>&1
check "$(qentry | cut -d' ' -f1-2)" "opus-high:2:$UNTIL:1 []" "  a run pinned to a host with no agy: Opus"
has "$T/out" "fallback to opus-high: buildbox: pinned to laptop" "  said"
qreset
echo "buildbox:agy" > "$REGATTA_CONFIG/wharf-runs/features"
DISPATCH_ARM="argon-high:2:$UNTIL:0" env -u DISPATCH_LABEL "$B/dispatch" claude/laptop/2026-11-02-worker --repo "$R" --model claude-opus-5-5 > "$T/out" 2>&1
check "$(qentry | cut -d' ' -f1-2)" "None []" "a carried argon-high word with a typed --model: dropped, never holding the run for a builder host"
has "$T/out" "builder coin argon-high:2:$UNTIL:0 dropped — a --model or --effort was given" "  said"
qreset
DISPATCH_ARM="argon-high:2:$UNTIL:0" env -u DISPATCH_LABEL "$B/dispatch" claude/laptop/2026-11-02-sr --repo "$R" > "$T/out" 2>&1
check "$(qentry | cut -d' ' -f1-2)" "None []" "  and with a brief no longer on the coin (sr-worker)"
qreset
cat > "$T/qstub" <<QS
import os, sys
if sys.argv[1:2] == ["enqueue"]:
    print("stub: the queue could not take it", file=sys.stderr); sys.exit(1)
os.execvp("python3", ["python3", "$B/dispatch-queue"] + sys.argv[1:])
QS
DISPATCH_QUEUE_BIN="$T/qstub" DISPATCH_COIN=2 DISPATCH_COIN_ROADS=antigravity env -u DISPATCH_LABEL "$B/dispatch" claude/laptop/2026-11-02-worker --repo "$R" > "$T/out" 2>&1; rc=$?
check "$rc|$(armof "$(pl worker)")" "0|opus-high:2:$UNTIL:1" "an Argon draw the queue could not take: its Opus fallback as a one-shot, never a refused step"
has "$T/out" "the queue could not meet its agy, so its fallback opus-high:2:$UNTIL:1" "  said"
has "$T/out" "scheduling it as before, a one-shot" "  and scheduled"
check "$(grep -c '<string>--needs</string>' "$(pl worker)")" "0" "  the one-shot needs nothing"
qreset
qreset
echo "buildbox:agy" > "$REGATTA_CONFIG/wharf-runs/features"
DISPATCH_COIN=2 DISPATCH_COIN_ROADS=antigravity env -u DISPATCH_LABEL "$B/dispatch" claude/laptop/2026-11-02-worker --repo "$R" --account acct-x > "$T/out" 2>&1; rc=$?
check "$rc|$(qentry | cut -d' ' -f1-2)" "0|opus-high:2:$UNTIL:1 []" "an Argon draw the queue pins here by its login (no agy here): put again as its Opus fallback, never refused"
has "$T/out" "the queue could not meet its agy, so its fallback opus-high:2:$UNTIL:1" "  said"
qreset
# a typed --harness codex: its codex need is the harness's (--arm-need), so a pre-flight fallback to Claude drops it and
# a codex-only builder host never takes the Claude build alone; a caller's own --needs codex stays typed (S8's finish review)
echo "buildbox:codex" > "$REGATTA_CONFIG/wharf-runs/features"
env -u DISPATCH_LABEL "$B/dispatch" claude/laptop/2026-11-02-worker --repo "$R" --harness codex > "$T/out" 2>&1; rc=$?
check "$rc|$(git --git-dir="$T/q3.git" show "refs/regatta/queue:$(git --git-dir="$T/q3.git" ls-tree -r --name-only refs/regatta/queue | grep '^queue/' | head -1)" 2>/dev/null | python3 -c 'import json, sys; e = json.load(sys.stdin); print(e.get("needs"), e.get("arm_need"))')" "0|['codex'] codex" \
  "a typed --harness codex: queued needing codex, named the harness's own"
qreset
env -u DISPATCH_LABEL "$B/dispatch" claude/laptop/2026-11-02-worker --repo "$R" --harness codex --needs codex > "$T/out" 2>&1; rc=$?
check "$rc|$(git --git-dir="$T/q3.git" show "refs/regatta/queue:$(git --git-dir="$T/q3.git" ls-tree -r --name-only refs/regatta/queue | grep '^queue/' | head -1)" 2>/dev/null | python3 -c 'import json, sys; e = json.load(sys.stdin); print(e.get("needs"), e.get("arm_need"))')" "0|['codex'] None" \
  "  a typed --needs codex beside it stays the caller's"
qreset
env -u DISPATCH_LABEL "$B/dispatch" claude/laptop/2026-11-02-worker --repo "$R" --harness codex --mode dnd > "$T/out" 2>&1; rc=$?
check "$rc" "2" "  a typed --mode dnd with --harness codex is refused: a vendor build hands no landing"
qreset
echo "buildbox:agy" > "$REGATTA_CONFIG/wharf-runs/features"
# a one-shot carries the word and the typed needs alone; its fire adds the arm's need again
w=$(sched worker DISPATCH_COIN=2 DISPATCH_COIN_ROADS=antigravity)
check "$w|$(grep -c '<string>--needs</string>' "$(pl worker)")" "argon-high:2:$UNTIL:1|0" "an Argon one-shot's plist: the word, and no --needs (the fire adds the arm's)"
fire worker "$w"
check "$(qentry | cut -d' ' -f1-2)" "argon-high:2:$UNTIL:1 ['agy']" "  fired: queued needing agy, its builder host's"
check "$(git --git-dir="$T/q3.git" show "refs/regatta/queue:$(git --git-dir="$T/q3.git" ls-tree -r --name-only refs/regatta/queue | grep '^queue/' | head -1)" 2>/dev/null | python3 -c 'import json, sys; print(json.load(sys.stdin).get("arm_need"))')" "agy" \
  "  and agy named the arm's"
qreset
w=$(sched worker DISPATCH_COIN=2 DISPATCH_COIN_ROADS=antigravity -- --needs agy)
check "$(grep -o '<string>--needs</string><string>[^<]*</string>' "$(pl worker)")" "<string>--needs</string><string>agy</string>" "a one-shot whose own --needs is agy keeps it in its plist"
fire worker "$w" --needs agy
check "$(git --git-dir="$T/q3.git" show "refs/regatta/queue:$(git --git-dir="$T/q3.git" ls-tree -r --name-only refs/regatta/queue | grep '^queue/' | head -1)" 2>/dev/null | python3 -c 'import json, sys; e = json.load(sys.stdin); print(e.get("needs"), e.get("arm_need"))')" "['agy'] None" \
  "  fired: agy is the run's own, never the arm's (no re-draw drops it)"
qreset
w=$(sched worker DISPATCH_COIN=2 DISPATCH_COIN_ROADS=antigravity)
echo "laptop:mac" > "$REGATTA_CONFIG/wharf-runs/features"   # the builder host left the features file before the fire
fire worker "$w"
check "$(qentry | cut -d' ' -f1-2)" "opus-high:2:$UNTIL:1 []" "an Argon one-shot fired when no host has agy: queued as its Opus fallback, never FAILED"
has "$H/fire-worker.log" "the queue could not meet its agy, so its fallback opus-high:2:$UNTIL:1" "  said in its log"
qreset
echo "buildbox:agy" > "$REGATTA_CONFIG/wharf-runs/features"
# a peer that has not fetched the branch: no brief read here, so the carried word stays for the fire-time read
git -C "$R" push -q origin main:refs/heads/claude/laptop/2026-11-02-later 2>/dev/null
DISPATCH_ARM="argon-high:2:$UNTIL:0" "$B/dispatch" claude/laptop/2026-11-02-later --repo "$R" --at "$FUT 05:10" > "$T/out" 2>&1
check "$(armof "$(pl later)")|$(grep -c '<string>--needs</string>' "$(pl later)")" "argon-high:2:$UNTIL:0|0" \
  "a carried argon-high word for a branch not fetched here: kept for the fire-time read, and no --needs of the arm's in the plist"
qreset
rm -f "$REGATTA_CONFIG/wharf-runs/queue-repo"
check "$(sched worker DISPATCH_ARM="argon-high:2:$UNTIL:0")" "" "a carried argon-high word with no queue home: dropped, never a one-shot here"
has "$T/out" "its arm needs a host with agy, and with no queue home here no host claims by its features" "  said"

echo "the sweep draws a vendor entry no host claimed again, as Opus"
cat > "$T/redraw.py" <<'PY'
import importlib.machinery, json, sys
q = importlib.machinery.SourceFileLoader("dq", sys.argv[1]).load_module()
u = sys.argv[2]
e = {"id": "x", "state": "queued", "repo": "repo", "branch": "claude/laptop/2026-11-02-worker", "needs": ["agy", "mac"],
     "args": ["--needs", "agy,mac", "--note", "n"], "env": {"DISPATCH_ARM": "argon-high:2:%s:0" % u, "DISPATCH_DEPTH": "0"},
     "put_at": 1000, "queued_at": 900, "arm_need": "agy"}
print(q.redraw_op("q:k", "k", e, 1000 + q.REDRAW_AGE - 1))
op = q.redraw_op("q:k", "k", e, 1000 + q.REDRAW_AGE)
f = op["fields"]
print(f["env"]["DISPATCH_ARM"], f["needs"], f["args"], f["redrawn_from"])
ents = {"k": dict(e)}
print(q.apply_op(ents, op), q.bad_args(ents["k"]))
print(q.apply_op({"k": dict(e, env={"DISPATCH_ARM": "argon-high:2:%s:1" % u})}, op))   # moved meanwhile: no write
e1 = dict(e, needs=["agy"], args=["--needs", "agy"])
print(q.redraw_op("q:k", "k", e1, 1000 + q.REDRAW_AGE)["fields"]["args"])   # its only need was the vendor's: no --needs left
# agy typed, not the arm's: Opus would still wait for that host, so it waits as typed; an env that is no mapping: none
print(q.redraw_op("q:k", "k", dict(e1, arm_need=None), 1000 + q.REDRAW_AGE), q.redraw_op("q:k", "k", dict(e, env=["x"]), 10 ** 9))
A = q.REDRAW_AGE
ef = dict(e, freed_at=1000 + 10 * A)   # its branch ran elsewhere until then
print(q.redraw_op("q:k", "k", ef, 1000 + 10 * A + 60), bool(q.redraw_op("q:k", "k", ef, 1000 + 11 * A)))
print(q.redraw_op("q:k", "k", dict(e, pinned_why="x"), 10 ** 9), q.redraw_op("q:k", "k", dict(e, running_on="buildbox"), 10 ** 9),
      q.redraw_op("q:k", "k", dict(e, requeued_from="buildbox", requeued_at=2000), 10 ** 9),   # its run started: Argon's
      q.redraw_op("q:k", "k", dict(e, host="buildbox", pin_kind="typed"), 10 ** 9))   # pinned: it waits for its host
op = q.redraw_op("q:k", "k", e, 10 ** 9)
ents = {"k": dict(e, state="queued", requeued_from="buildbox", requeued_at=5000, args=["--needs", "agy,mac", "--priority", "force"])}
print(q.apply_op(ents, op), ents["k"]["env"]["DISPATCH_ARM"])   # replayed from the outbox after a requeue: no write
ea = dict(e, after=[{"branch": "claude/laptop/2026-11-02-pre"}])
q.after_holds = lambda *x, **y: "after claude/laptop/2026-11-02-pre: open"
print(q.redraw_op("q:k", "k", ea, 1000 + 10 * A))
q.after_holds = lambda *x, **y: None
st = q.redraw_op("q:k", "k", ea, 1000 + 10 * A)
print(st["fields"], "redraw" in st)
ea["after_clear_at"] = 1000 + 10 * A
print(q.redraw_op("q:k", "k", ea, 1000 + 11 * A - 1), bool(q.redraw_op("q:k", "k", ea, 1000 + 11 * A)))
for w in ("sonnet-high:1:%s:0" % u, "opus-high:2:%s:0" % u):
    print(q.redraw_op("q:k", "k", dict(e, env={"DISPATCH_ARM": w}), 10 ** 9))
st = {"repo": sys.argv[3], "branch": "claude/laptop/2026-11-02-worker", "model": "gemini-4-argon-high", "effort": "high",
      "arm": {"name": "argon-high", "model": "gemini-4-argon-high", "effort": "high", "coin": 2, "until": u, "forced": False, "agent": "antigravity"}}
r = q.entry_of_record(st, "laptop", 0)
print(r["env"]["DISPATCH_ARM"], r["needs"], q.bad_args(r), r.get("arm_need"))
PY
check "$(python3 "$T/redraw.py" "$B/dispatch-queue" "$UNTIL" "$R" 2>&1)" "None
opus-high:2:$UNTIL:0 ['mac'] ['--needs', 'mac', '--note', 'n'] argon-high:2:$UNTIL:0
(True, 'set') None
(False, 'moved')
[]
None None
None True
None None None None
(False, 'moved') argon-high:2:$UNTIL:0
None
{'after_clear_at': $((1000 + 10 * 1800))} False
None True
None
None
argon-high:2:$UNTIL:0 ['agy'] None agy" \
  "past REDRAW_AGE: Opus under Argon's coin, the arm's agy dropped (a typed one waits for its host, an env that is no mapping is left), the old word kept; aged from its run elsewhere ending and its --after hold clearing (stamped first), never while held, pinned or once its run started (a requeue), nor by an outbox replay after one, never a moved entry, a claude arm or a fallback; a requeued Argon run needs agy again"

echo "the fire path: the odds again, the fallback recorded"
clean
fire worker "argon-high:2:$UNTIL:0"
has "$T/claude.calls" "--model claude-opus-5-5 --effort high --permission-mode auto" "an argon-high word fired by a dispatch with no road for it: Opus, its fallback"
has "$H/fire-worker.log" "== builder coin: argon-high:2:$UNTIL:0 has no road here — its fallback, opus-high:2:$UNTIL:0" "  said in the log"
check "$(recof worker)" "{\"agent\": \"claude\", \"coin\": 2, \"effort\": \"high\", \"fallback\": true, \"forced\": false, \"model\": \"claude-opus-5-5\", \"name\": \"opus-high\", \"until\": \"$UNTIL\"} fallback claude-opus-5-5 high" \
  "  the record's arm: Opus under Argon's coin, fallback"
check "$(python3 -c 'import json, sys
r = [json.loads(l) for l in open(sys.argv[1])]
print(len(r), *[(x["arm"], x["coin"], x["drawn"], x["agent"], x["fallback"], x["odds"]) for x in r])' "$ROWS" 2>&1)" "1 ('opus-high', 2, 'argon-high', 'claude', True, '1:2:0:1:1')" \
  "  its row: drawn argon-high, run by claude, fallback, the odds as rolled (Argon 0 with no road)"
clean
fire worker "opus-high:2:$UNTIL:0"
has "$T/claude.calls" "--model claude-opus-5-5 --effort high" "a fallback word (the draw's, or the sweep's) fires as Opus"
check "$(python3 -c 'import json, sys; r = json.loads(open(sys.argv[1]).readline()); print(r["fallback"], r["drawn"])' "$ROWS" 2>&1)" "True argon-high" "  its row says fallback"
clean
echo "opus-high=1,sonnet-high=0,argon-high=2" > "$ODK"
fire worker "sonnet-high:1:$UNTIL:0"
has "$T/claude.calls" "--model opus --effort high" "the drawn arm's weight 0 when it fires (the owner's kill switch): today's builder"
has "$H/fire-worker.log" "dropped — wharf-runs/builder-odds opus-high=1,sonnet-high=0,argon-high=2 gives sonnet-high 0 now" "  said"
check "$(rowsof)|$(recof worker | cut -d' ' -f1)" "0|null" "  no row, no arm on the record"
clean
echo "opus-high=x" > "$ODK"
fire worker "sonnet-high:1:$UNTIL:0"
has "$T/claude.calls" "--model opus --effort high" "odds that do not read at fire time: today's builder"
check "$(rowsof)" "0" "  no row"
rm -f "$ODK"

echo "Codex: both dispatch roads, both sizes, and zero means never"
echo "$T/q3.git" > "$REGATTA_CONFIG/wharf-runs/queue-repo"
qreset
echo "buildbox:codex" > "$REGATTA_CONFIG/wharf-runs/features"
hostrow "$(date +%s)"
DISPATCH_COIN=3 env -u DISPATCH_LABEL "$B/dispatch" claude/laptop/2026-11-02-worker --repo "$R" > "$T/out" 2>&1
check "$(qentry | cut -d' ' -f1-2)" "gpt-big:3:$UNTIL:1 ['codex']" "a direct queue draw: GPT big needs codex"
qreset
w=$(sched worker DISPATCH_COIN=4)
check "$w" "gpt-mid:4:$UNTIL:1" "a one-shot draws GPT mid"
fire worker "$w"
check "$(qentry | cut -d' ' -f1-2)" "gpt-mid:4:$UNTIL:1 ['codex']" "  fired: queued with its codex need"
qreset
echo "0:0:0:1:1" > "$ODK"
for spec in worker:gpt-mid sr:gpt-big; do
  qreset
  t=${spec%%:*}; arm=${spec#*:}
  env -u DISPATCH_LABEL "$B/dispatch" "claude/laptop/2026-11-02-$t" --repo "$R" --if-room > "$T/out" 2>&1
  check "$?" "2" "a drawn $arm refuses --if-room before enqueue"
  has "$T/out" "$arm — builder host buildbox fresh" "  the coin drew GPT with a fresh Codex host"
  has "$T/out" "takes no --if-room: it judges the Claude week" "  the refusal names the unrelated Claude budget"
  check "$(qentry)" "" "  no GPT entry carrying --if-room was queued"
done
qreset
fire worker "gpt-mid:4:$UNTIL:0" --if-room
check "$?" "2" "a carried GPT word refuses --if-room before the fire path's Claude week check"
has "$T/fire.out" "takes no --if-room: it judges the Claude week" "  the fire uses the same argument refusal"
check "$(qentry)" "" "  the refused fire enqueues nothing"
qreset
# an unattended --next takes its session's login label before the draw (account which); a drawn GPT arm drops it after the
# draw, or enqueue pins the entry to this codex-less host and it always falls back (the finish review, 2026-11-06). The
# --next road needs a live run to reach, so its order is read from the source, as test_priority reads caller-prio's
check "$(awk '/arm_word=\$\(DISPATCH_COIN=/ {d=NR} /if vendor_pending && \[ "\$account_typed" = 0 \]; then case "\$account" in .*login_free && account=""/ {l=NR} END {print (d && l > d) ? "after" : "missing"}' "$B/dispatch")" "after" \
  "a drawn GPT arm drops an inherited login label after the draw where the primary may run the repo (login_free), never a typed one"
DISPATCH_COIN=3 env -u DISPATCH_LABEL "$B/dispatch" claude/laptop/2026-11-02-worker --repo "$R" --account acct-x > "$T/out" 2>&1
check "$(git --git-dir="$T/q3.git" show "refs/regatta/queue:$(git --git-dir="$T/q3.git" ls-tree -r --name-only refs/regatta/queue | grep '^queue/' | head -1)" 2>/dev/null | python3 -c 'import json, sys; e = json.load(sys.stdin); a = e.get("args") or []; print(e.get("env", {}).get("DISPATCH_ARM", "").split(":")[0], "--account" in a and a[a.index("--account") + 1])')" "opus-high acct-x" \
  "  a typed --account on a GPT draw rides as typed: pinned here (no codex), so its Opus fallback"
qreset
check "$(sched sr DISPATCH_COIN=3)" "gpt-big:3:$UNTIL:1" "Claude weights zero: a sr-worker/Opus brief draws GPT big"
check "$(sched worker DISPATCH_COIN=4)" "gpt-mid:4:$UNTIL:1" "  a worker brief draws GPT mid"
check "$(sched bullet-sr DISPATCH_COIN=4)" "gpt-big:3:$UNTIL:0" "  a bulleted sr-worker draws only GPT big, even with a forced mid coin"
check "$(sched bullet-worker DISPATCH_COIN=3)" "gpt-mid:4:$UNTIL:0" "  a bulleted worker draws only GPT mid, even with a forced big coin"
check "$(sched bullet-prin DISPATCH_COIN=3)" "" "  a bulleted principal tier stays Claude"
check "$(sched prin DISPATCH_COIN=3)" "" "  a principal tier stays Claude"
echo "0:0:0:0:1" > "$ODK"
w=$(sched sr)
check "$w" "" "all eligible big arms zero: today's Claude builder, never mid"
check "$(sched worker DISPATCH_COIN=0)" "gpt-mid:4:$UNTIL:0" "even a forced zero-weight Claude arm is never drawn"
echo "1:0:0:1:1" > "$ODK"
check "$(sched sr DISPATCH_COIN=3)" "" "a positive Claude weight restores the old class rule"
rm -f "$ODK"

echo
[ "$fails" = 0 ] && echo "test_builder_coin: all passed" || echo "test_builder_coin: $fails failed"
[ "$fails" = 0 ]
