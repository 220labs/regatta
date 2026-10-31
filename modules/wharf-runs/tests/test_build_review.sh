#!/usr/bin/env bash
# Tests for bin/build-review — the record of a build's own review loop (build-review, 2026-10-30): its place
# beside autofinish.json, its shape, the round cap, a fresh record after an ended one, and the durable log line.
# Scratch HOME, repo and log; nothing outside them is written.
#   bash modules/wharf-runs/tests/test_build_review.sh
set -u
B="$(cd "$(dirname "$0")/../bin" && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export HOME="$T/home"; mkdir -p "$HOME"
# a moved HOME drops CI's global identity: the suite's own (AGENTS.md Traps)
printf '[user]\n\tname = t\n\temail = t@t\n[init]\n\tdefaultBranch = main\n' > "$T/gitconfig"; export GIT_CONFIG_GLOBAL="$T/gitconfig"
export BUILD_REVIEW_LOG="$T/log/build-review.jsonl"
export CLAUDE_CODE_SESSION_ID=s0   # the suite's own session, a case names another; never the running one (AGENTS.md Traps)
fails=0
check() { if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3: expected [$2] got [$1]"; fails=$((fails+1)); fi; }
has()   { if printf '%s' "$1" | grep -qF -- "$2"; then echo "  ok   $3"; else echo "  FAIL $3: missing [$2] in [$1]"; fails=$((fails+1)); fi; }
br() { "$B/build-review" "$@" 2>&1; }
js() { python3 -c 'import json, sys; d = json.load(open(sys.argv[1])); print(eval(sys.argv[2]))' "$@"; }

git init -q -b main "$T/repo"; git -C "$T/repo" commit -q --allow-empty -m init
W="$T/wt-demo"
git -C "$T/repo" worktree add -q -b claude/laptop/2026-10-30-demo "$W" main
R="$(git -C "$W" rev-parse --absolute-git-dir)/claude/build-review.json"

echo "== the record: per worktree, beside autofinish.json"
check "$(br show "$W")" "none" "no record yet: show says none"
out=$(br round "$W" --found 3 --fixed 3 --check green --reviewers reviewer-high,code-reviewer); check "$?" "0" "a round is recorded"
has "$out" "round 1 of 5 recorded" "  saying which of the cap"
check "$([ -f "$R" ] && echo yes)" "yes" "  in <git dir>/claude/build-review.json of the worktree"
check "$(js "$R" 'd["branch"], d["repo"] == sys.argv[3], d["project"], d["worktree"] == sys.argv[4], len(d["rounds"])' "$(cd "$T/repo" && pwd -P)" "$(cd "$W" && pwd -P)")" "('claude/laptop/2026-10-30-demo', True, 'repo', True, 1)" "  naming the branch, the main checkout, review-gate's project and repo keys"
check "$(js "$R" 'sorted(d["rounds"][0])')" "['at', 'check', 'fixed', 'found', 'left', 'note', 'reviewers', 'round', 'tip']" "  a round's shape"
check "$(js "$R" 'd["rounds"][0]["tip"] == sys.argv[3], d["rounds"][0]["reviewers"]' "$(git -C "$W" rev-parse HEAD)")" "(True, ['reviewer-high', 'code-reviewer'])" "  the tip read from git at the call; the reviewers a list"
case "$out" in *"end it"*) echo "  FAIL a round that found 3 was told to end"; fails=$((fails+1));; *) echo "  ok   a round that found something is not told to end (its fixes need a review too)";; esac
git -C "$W" commit -q --allow-empty -m fix
out=$(br round "$W" --found 0 --fixed 0 --check green); has "$out" "nothing found and the check green: end it (--outcome clean)" "a round that found nothing with the check green is told to end clean"
check "$(js "$R" 'd["rounds"][1]["tip"] == sys.argv[3]' "$(git -C "$W" rev-parse HEAD)")" "True" "  its tip is the new commit"

echo "== end: the outcome, and one line in the durable log"
out=$(br end "$W" --outcome clean); check "$?" "0" "end clean"
has "$out" "ended clean after 2 round(s)" "  saying how many rounds"
check "$(js "$R" 'd["outcome"], bool(d["ended"]), d["why"]')" "('clean', True, '')" "  the record holds outcome and end"
check "$(wc -l < "$BUILD_REVIEW_LOG" | tr -d ' ')" "1" "  the log has one line"
check "$(python3 -c 'import json, sys; d = json.loads(open(sys.argv[1]).readline()); print(d["branch"], d["outcome"], len(d["rounds"]))' "$BUILD_REVIEW_LOG")" "claude/laptop/2026-10-30-demo clean 2" "  holding the whole record, keyed by repo and branch as review-gate.jsonl is"
out=$(br end "$W" --outcome nope); check "$?" "2" "an outcome it does not know: a usage error"
out=$(br end "$W" --outcome held --why "second thought"); check "$?" "2" "a second end by the same session is refused"
has "$out" "ended the record already (clean): one loop, one end, per session" "  saying so"
out=$(br round "$W" --found 0 --fixed 0 --check green); check "$?" "2" "  so is a new round by that session: a capped run never restarts its own cap"
check "$(wc -l < "$BUILD_REVIEW_LOG" | tr -d ' ')" "1" "  and the log still has one line: no build logged twice"
CLAUDE_CODE_SESSION_ID=later br end "$W" --outcome held --why "held at once" >/dev/null
check "$(python3 -c 'import json, sys; print([(json.loads(l)["outcome"], len(json.loads(l)["rounds"])) for l in open(sys.argv[1])])' "$BUILD_REVIEW_LOG")" "[('clean', 2), ('held', 0)]" \
  "another session's end with no round of its own: a fresh record, the old rounds never logged again"

echo "== a later run starts afresh; the cap is 5"
br round "$W" --found 1 --fixed 1 --check red >/dev/null
check "$(js "$R" 'len(d["rounds"]), "ended" in d')" "(1, False)" "a round after an ended record starts a new one"
for i in 2 3 4; do CLAUDE_CODE_SESSION_ID=dead br round "$W" --found 1 --fixed 1 --check red >/dev/null; done
check "$(js "$R" 'd["session"], len(d["rounds"])')" "('dead', 3)" "a run that died before end: the next session's round starts its own record"
n0=$(wc -l < "$BUILD_REVIEW_LOG" | tr -d ' ')
out=$(br round "$W" --found 1 --fixed 1 --check red); check "$(js "$R" 'd["session"], len(d["rounds"])')" "('s0', 1)" "  and the dead run's unended rounds never count against this one's cap"
check "$(tail -1 "$BUILD_REVIEW_LOG" | python3 -c 'import json, sys; d = json.load(sys.stdin); print(d["session"], d["outcome"], len(d["rounds"]))') $(( $(wc -l < "$BUILD_REVIEW_LOG") - n0 ))" "dead died 3 1" \
  "  the dead run's rounds are logged once, as died, never lost"
check "$(js "$R" 'd["rounds"][0]["left"]')" "0" "  --left unset: found - fixed (1 - 1)"
for i in 2 3 4; do br round "$W" --found 1 --fixed 1 --check red >/dev/null; done
out=$(br round "$W" --found 1 --fixed 1 --check red); has "$out" "round 5 of 5 recorded — the cap: end it (--outcome cap)" "the fifth round says it is the cap, and the end it owes"
out=$(br round "$W" --found 1 --fixed 0 --check red); check "$?" "3" "a sixth round is refused (exit 3)"
has "$out" "5 rounds already, the cap" "  in the cap's words"
has "$out" "--outcome cap" "  naming the end it owes"
check "$(js "$R" 'len(d["rounds"])')" "5" "  and writes nothing"
out=$(br end "$W" --outcome held --why "a live write"); check "$(js "$R" 'd["outcome"], d["why"]')" "('held', 'a live write')" "end held keeps its why"
out=$(br round "$W" --found 0 --fixed 0 --check green); check "$?" "3" "a held loop at the cap, reopened by a round: the cap still refuses it"
out=$(br end "$W" --outcome cap); check "$?" "0" "  and it can still end cap (the finish review)"
check "$(js "$R" 'd["outcome"], len(d["rounds"])')" "('cap', 5)" "  the record says cap, its five rounds kept"

echo "== a clean end must be borne out; a held one reopens"
out=$(CLAUDE_CODE_SESSION_ID=c1 br end "$W" --outcome clean); check "$?" "2" "a clean end with no round: refused"
has "$out" "no round yet" "  saying why"
CLAUDE_CODE_SESSION_ID=c1 br round "$W" --found 2 --fixed 2 --check green >/dev/null
out=$(CLAUDE_CODE_SESSION_ID=c1 br end "$W" --outcome clean); check "$?" "2" "a clean end after a round that found 2: refused"
has "$out" "found 2, check green" "  naming the last round"
CLAUDE_CODE_SESSION_ID=c1 br end "$W" --outcome held --why "D1 open" >/dev/null
out=$(CLAUDE_CODE_SESSION_ID=c1 br round "$W" --found 0 --fixed 0 --check green); check "$?" "0" "the same session's round after a held end reopens the record"
check "$(js "$R" 'len(d["rounds"]), "ended" in d, d["reopened"]')" "(2, False, 1)" "  its rounds kept against the cap, marked reopened"
CLAUDE_CODE_SESSION_ID=c1 br end "$W" --outcome clean >/dev/null; check "$?" "0" "  and it can end clean now"
check "$(tail -2 "$BUILD_REVIEW_LOG" | python3 -c 'import json, sys; print([(json.loads(l)["outcome"], json.loads(l)["started"]) for l in sys.stdin])' | python3 -c 'import ast, sys; v = ast.literal_eval(sys.stdin.read()); print(v[0][0], v[1][0], v[0][1] == v[1][1])')" "held clean True" \
  "  two lines for one (session, started): held, then clean"

echo "== a dead run's record is logged died once, even when the next call is refused"
CLAUDE_CODE_SESSION_ID=gone br round "$W" --found 1 --fixed 1 --check red >/dev/null
n0=$(wc -l < "$BUILD_REVIEW_LOG" | tr -d ' ')
CLAUDE_CODE_SESSION_ID=next br end "$W" --outcome clean >/dev/null 2>&1; check "$?" "2" "a new session's clean end with no round: refused"
CLAUDE_CODE_SESSION_ID=next br round "$W" --found 0 --fixed 0 --check green >/dev/null
check "$(python3 -c 'import json, sys; print(sum(1 for l in list(open(sys.argv[1]))[int(sys.argv[2]):] if json.loads(l)["outcome"] == "died"))' "$BUILD_REVIEW_LOG" "$n0")" "1" \
  "  the dead run's record is logged died once, not again by the call after the refusal"

echo "== gate: yolo_launch's read of this run's loop"
CLAUDE_CODE_SESSION_ID=next br end "$W" --outcome clean >/dev/null
br gate "$W" --session next >/dev/null; check "$?" "0" "a loop ended clean: the gate passes"
br gate "$W" --session other >/dev/null; check "$?" "0" "another session's record: passes (an opted-out run keeps none)"
CLAUDE_CODE_SESSION_ID=g1 br round "$W" --found 2 --fixed 1 --check red >/dev/null
out=$(br gate "$W" --session g1); check "$?" "1" "rounds recorded and never ended: refused"
has "$out" "recorded 1 round(s) and never ended" "  saying so"
CLAUDE_CODE_SESSION_ID=g1 br end "$W" --outcome cap >/dev/null
out=$(br gate "$W" --session g1); check "$?" "1" "a loop ended cap: refused"
has "$out" "ended cap" "  naming the outcome"
CLAUDE_CODE_SESSION_ID=g2 br round "$W" --found 1 --fixed 0 --check green >/dev/null
CLAUDE_CODE_SESSION_ID=g2 br end "$W" --outcome held --why "D2 open" >/dev/null
out=$(br gate "$W" --session g2); check "$?" "1" "a loop ended held: refused"
has "$out" "ended held: D2 open" "  with its why"

echo "== an end whose log line cannot be written leaves the record open"
CLAUDE_CODE_SESSION_ID=lg br round "$W" --found 0 --fixed 0 --check green >/dev/null
mkdir -p "$T/ro"; chmod 500 "$T/ro"
out=$(CLAUDE_CODE_SESSION_ID=lg BUILD_REVIEW_LOG="$T/ro/x/build-review.jsonl" "$B/build-review" end "$W" --outcome clean 2>&1); check "$?" "2" "the log unwritable: the end is refused"
check "$(js "$R" '"ended" in d')" "False" "  and the record stays open"
CLAUDE_CODE_SESSION_ID=lg br end "$W" --outcome clean >/dev/null; check "$?" "0" "  so it can be ended once the log is writable"
chmod 700 "$T/ro"

echo "== the log's default: review-gate.jsonl's folder"
git -C "$W" commit -q --allow-empty -m more
CLAUDE_CODE_SESSION_ID=gate env -u BUILD_REVIEW_LOG REVIEW_GATE_LOG="$T/gate/review-gate.jsonl" "$B/build-review" end "$W" --outcome held >/dev/null 2>&1
check "$([ -s "$T/gate/build-review.jsonl" ] && echo yes)" "yes" "with REVIEW_GATE_LOG set, the line goes beside review-gate's"
CLAUDE_CODE_SESSION_ID=rv br round "$W" --found 3 --fixed 1 --check red --reviewers " reviewer-high , code-reviewer" >/dev/null
check "$(js "$R" 'd["rounds"][0]["reviewers"]')" "['reviewer-high', 'code-reviewer']" "reviewers are comma-separated, spaces stripped"
check "$(js "$R" 'd["rounds"][0]["left"]')" "2" "--left unset: found - fixed (3 - 1)"

echo "== refusals"
out=$(br show "$T/nowhere"); check "$?" "2" "a path that is no checkout: exit 2"
has "$out" "is no git checkout" "  saying so"
out=$(br round "$W" --found -1 --fixed 0); check "$?" "2" "a negative count: a usage error"
out=$(env -u CLAUDE_CODE_SESSION_ID "$B/build-review" round "$W" --found 0 --fixed 0 --check green 2>&1); check "$?" "2" "no session id: refused, never read as one shared session"
has "$out" "no CLAUDE_CODE_SESSION_ID" "  saying so"

echo
[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
