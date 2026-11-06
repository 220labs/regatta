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
# the round cap is a config key (TODO.md [second-review]'s D2-B): the cases below the cap section were written at 5, so they keep it
export REGATTA_CONFIG="$T/cfg"; mkdir -p "$REGATTA_CONFIG/wharf-runs"
printf '5\n' > "$REGATTA_CONFIG/wharf-runs/build-review-rounds"
export CLAUDE_CODE_SESSION_ID=s0   # the suite's own session, a case names another; never the running one (AGENTS.md Traps)
fails=0
check() { if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3: expected [$2] got [$1]"; fails=$((fails+1)); fi; }
has()   { if printf '%s' "$1" | grep -qF -- "$2"; then echo "  ok   $3"; else echo "  FAIL $3: missing [$2] in [$1]"; fails=$((fails+1)); fi; }
br() { "$B/build-review" "$@" 2>&1; }
js() { python3 -c 'import json, sys; d = json.load(open(sys.argv[1])); print(eval(sys.argv[2]))' "$@"; }
# a verifier's report with N confirmed blocks (verified-rounds): the only road to a count above 0
vf() { f="$T/vf-$1-$RANDOM"; i=0; : > "$f"
  while [ "$i" -lt "$1" ]; do printf 'a.py:%d — [S2] a defect\nverdict: WRONG\nevidence: traced, x=1 gives 2\n\n' "$i" >> "$f"; i=$((i+1)); done
  [ "$1" -gt 0 ] || printf 'a.py:1 — [S2] a theory\nverdict: UNVERIFIABLE\nevidence: none shown\n' > "$f"
  printf '%s' "$f"; }

git init -q -b main "$T/repo"; git -C "$T/repo" commit -q --allow-empty -m init
# the runner covers' tests-only rule asks for: a suite it runs (its glob) is vouched past, one nobody runs is not
mkdir -p "$T/repo/tests"; printf 'for f in "$(dirname "$0")"/*.sh; do bash "$f"; done\n' > "$T/repo/tests/check.sh"
git -C "$T/repo" add tests; git -C "$T/repo" commit -q -m runner
W="$T/wt-demo"
git -C "$T/repo" worktree add -q -b claude/laptop/2026-10-30-demo "$W" main
R="$(git -C "$W" rev-parse --absolute-git-dir)/claude/build-review.json"

echo "== the record: per worktree, beside autofinish.json"
check "$(br show "$W")" "none" "no record yet: show says none"
out=$(br round "$W" --verdicts "$(vf 3)" --fixed 3 --check green --reviewers reviewer-high,code-reviewer); check "$?" "0" "a round is recorded"
has "$out" "round 1 of 5 recorded" "  saying which of the cap"
check "$([ -f "$R" ] && echo yes)" "yes" "  in <git dir>/claude/build-review.json of the worktree"
check "$(js "$R" 'd["branch"], d["repo"] == sys.argv[3], d["project"], d["worktree"] == sys.argv[4], len(d["rounds"])' "$(cd "$T/repo" && pwd -P)" "$(cd "$W" && pwd -P)")" "('claude/laptop/2026-10-30-demo', True, 'repo', True, 1)" "  naming the branch, the main checkout, review-gate's project and repo keys"
check "$(js "$R" 'sorted(d["rounds"][0])')" "['at', 'check', 'fixed', 'found', 'left', 'note', 'open_s1', 'raised', 'reviewed', 'reviewers', 'round', 'tip']" "  a round's shape"
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
br round "$W" --verdicts "$(vf 1)" --fixed 1 --check red >/dev/null
check "$(js "$R" 'len(d["rounds"]), "ended" in d')" "(1, False)" "a round after an ended record starts a new one"
for i in 2 3 4; do CLAUDE_CODE_SESSION_ID=dead br round "$W" --verdicts "$(vf 1)" --fixed 1 --check red >/dev/null; done
check "$(js "$R" 'd["session"], len(d["rounds"])')" "('dead', 3)" "a run that died before end: the next session's round starts its own record"
n0=$(wc -l < "$BUILD_REVIEW_LOG" | tr -d ' ')
out=$(br round "$W" --verdicts "$(vf 1)" --fixed 1 --check red); check "$(js "$R" 'd["session"], len(d["rounds"])')" "('s0', 1)" "  and the dead run's unended rounds never count against this one's cap"
check "$(tail -1 "$BUILD_REVIEW_LOG" | python3 -c 'import json, sys; d = json.load(sys.stdin); print(d["session"], d["outcome"], len(d["rounds"]))') $(( $(wc -l < "$BUILD_REVIEW_LOG") - n0 ))" "dead died 3 1" \
  "  the dead run's rounds are logged once, as died, never lost"
check "$(js "$R" 'd["rounds"][0]["left"]')" "0" "  --left unset: found - fixed (1 - 1)"
for i in 2 3 4; do br round "$W" --verdicts "$(vf 1)" --fixed 1 --check red >/dev/null; done
out=$(br round "$W" --verdicts "$(vf 1)" --fixed 1 --check red); has "$out" "round 5 of 5 recorded — the cap: end it (--outcome cap)" "the fifth round says it is the cap, and the end it owes"
out=$(br round "$W" --verdicts "$(vf 1)" --fixed 0 --check red); check "$?" "3" "a sixth round is refused (exit 3)"
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
CLAUDE_CODE_SESSION_ID=c1 br round "$W" --verdicts "$(vf 2)" --fixed 2 --check green >/dev/null
out=$(CLAUDE_CODE_SESSION_ID=c1 br end "$W" --outcome clean); check "$?" "2" "a clean end after a round that found 2: refused"
has "$out" "found 2, check green" "  naming the last round"
CLAUDE_CODE_SESSION_ID=c1 br end "$W" --outcome held --why "D1 open" >/dev/null
out=$(CLAUDE_CODE_SESSION_ID=c1 br round "$W" --found 0 --fixed 0 --check green); check "$?" "0" "the same session's round after a held end reopens the record"
check "$(js "$R" 'len(d["rounds"]), "ended" in d, d["reopened"]')" "(2, False, 1)" "  its rounds kept against the cap, marked reopened"
CLAUDE_CODE_SESSION_ID=c1 br end "$W" --outcome clean >/dev/null; check "$?" "0" "  and it can end clean now"
check "$(tail -2 "$BUILD_REVIEW_LOG" | python3 -c 'import json, sys; print([(json.loads(l)["outcome"], json.loads(l)["started"]) for l in sys.stdin])' | python3 -c 'import ast, sys; v = ast.literal_eval(sys.stdin.read()); print(v[0][0], v[1][0], v[0][1] == v[1][1])')" "held clean True" \
  "  two lines for one (session, started): held, then clean"

echo "== a dead run's record is logged died once, even when the next call is refused"
CLAUDE_CODE_SESSION_ID=gone br round "$W" --verdicts "$(vf 1)" --fixed 1 --check red >/dev/null
n0=$(wc -l < "$BUILD_REVIEW_LOG" | tr -d ' ')
CLAUDE_CODE_SESSION_ID=next br end "$W" --outcome clean >/dev/null 2>&1; check "$?" "2" "a new session's clean end with no round: refused"
CLAUDE_CODE_SESSION_ID=next br round "$W" --found 0 --fixed 0 --check green >/dev/null
check "$(python3 -c 'import json, sys; print(sum(1 for l in list(open(sys.argv[1]))[int(sys.argv[2]):] if json.loads(l)["outcome"] == "died"))' "$BUILD_REVIEW_LOG" "$n0")" "1" \
  "  the dead run's record is logged died once, not again by the call after the refusal"

echo "== gate: yolo_launch's read of this run's loop"
CLAUDE_CODE_SESSION_ID=next br end "$W" --outcome clean >/dev/null
br gate "$W" --session next >/dev/null; check "$?" "0" "a loop ended clean: the gate passes"
br gate "$W" --session other >/dev/null; check "$?" "0" "another session's record: passes (an opted-out run keeps none)"
CLAUDE_CODE_SESSION_ID=g1 br round "$W" --verdicts "$(vf 2)" --fixed 1 --check red >/dev/null
out=$(br gate "$W" --session g1); check "$?" "1" "rounds recorded and never ended: refused"
has "$out" "recorded 1 round(s) and never ended" "  saying so"
CLAUDE_CODE_SESSION_ID=g1 br end "$W" --outcome cap >/dev/null
out=$(br gate "$W" --session g1); check "$?" "1" "a loop ended cap: refused"
has "$out" "ended cap" "  naming the outcome"
CLAUDE_CODE_SESSION_ID=g2 br round "$W" --verdicts "$(vf 1)" --fixed 0 --check green >/dev/null
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
CLAUDE_CODE_SESSION_ID=rv br round "$W" --verdicts "$(vf 3)" --fixed 1 --check red --reviewers " reviewer-high , code-reviewer" >/dev/null
check "$(js "$R" 'd["rounds"][0]["reviewers"]')" "['reviewer-high', 'code-reviewer']" "reviewers are comma-separated, spaces stripped"
check "$(js "$R" 'd["rounds"][0]["left"]')" "2" "--left unset: found - fixed (3 - 1)"

echo "== compare: the build's rounds beside the finish's review and the spend (TODO.md [second-review])"
C="$T/cmp"; mkdir -p "$C/h1/calls"
cat > "$T/cmp.py" <<'PY'
import csv, json, sys, time
C = sys.argv[1]
ts = lambda t: time.strftime("%Y-%m-%dT%H:%M:%S+0000", time.gmtime(t))
iso = lambda t: time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime(t))
rnd = lambda f, x: {"found": f, "fixed": x}
with open(C + "/build-review.jsonl", "w") as f:
    for d in ({"project": "p", "branch": "b1", "ended": 1000, "outcome": "died", "rounds": [rnd(2, 2)]},
              {"project": "p", "branch": "b1", "ended": 2000, "outcome": "clean", "rounds": [rnd(3, 3), rnd(0, 0)]},
              {"project": "p", "branch": "b2", "ended": 5000, "outcome": "cap", "rounds": [rnd(1, 1)]},
              {"project": "p", "branch": "b3", "outcome": "clean", "rounds": []}):   # never ended: no row
        f.write(json.dumps(d) + "\n")
g = lambda t, b, s1=0, s2=0, wrong=None, **k: dict({"ts": ts(t), "project": "p", "branch": b,
    "findings": {"S1": s1, "S2": s2, "S3": 0}, "wrong": wrong or {}}, **k)
with open(C + "/review-gate.jsonl", "w") as f:
    for d in (g(1500, "b1", s1=5),                            # before the last end, no phase: a build round's
              g(2500, "b1", s1=1),                            # after it, no phase: the finish's (an old line)
              g(2600, "b1", s2=2, wrong={"S2": 1}, phase="finish"),
              g(3000, "b1", s1=9, phase="build"),             # after the end, yet marked a build round's
              g(900, "b1", s2=4, phase="finish"),             # marked the finish's: the mark wins over the time
              g(4000, "b2", s1=7)):
        f.write(json.dumps(d) + "\n")
with open(C + "/h1/calls/2026-11-01.csv", "w", newline="") as f:
    w = csv.DictWriter(f, ["project", "branch", "agent", "first", "cost"])
    w.writeheader()
    for r in (("p", "b1", "reviewer-high", 1800, "3"), ("p", "b1", "code-reviewer", 2700, "1.5"),
              ("p", "b1", "worker", 2700, "9"), ("q", "b1", "reviewer", 2700, "7"), ("p", "b2", "reviewer", 4500, "2")):
        w.writerow(dict(zip(["project", "branch", "agent", "first", "cost"], [*r[:3], iso(r[3]), r[4]])))
PY
python3 "$T/cmp.py" "$C"
cmp() { BUILD_REVIEW_LOG="$C/build-review.jsonl" "$B/build-review" compare "$@" 2>&1; }
cmp --json > "$T/cmp.json"; check "$?" "0" "compare --json reads the logs"
cj() { python3 -c 'import json, sys; d = {r["branch"]: r for r in json.load(open(sys.argv[1]))}; print(eval(sys.argv[2]))' "$T/cmp.json" "$1"; }
check "$(cj 'sorted(d)')" "['b1', 'b2']" "one row per branch with an ended record; an unended one has none"
check "$(cj 'd["b1"]["rounds"], d["b1"]["found"], d["b1"]["fixed"], d["b1"]["outcomes"]')" "(3, 5, 5, ['died', 'clean'])" "  a branch's records summed, each outcome kept"
check "$(cj '[(f["S1"], f["S2"], f["wrong"]) for f in d["b1"]["finish"]]')" "[(0, 4, 0), (1, 0, 0), (0, 2, 1)]" \
  "  the finish's lines: marked finish whatever the time, unmarked after the last end; a build round's never"
check "$(cj 'd["b2"]["finish"]')" "[]" "  an unmarked line before the end is the build's"
check "$(cj 'd["b1"]["spend"], d["b2"]["spend"]')" "({'build': 3.0, 'finish': 1.5}, {'build': 2.0, 'finish': 0.0})" \
  "  review agents' spend split at the end; a worker's and another project's left out"
out=$(cmp); has "$out" "2 build(s), 1 with a finish review" "the text form ends on a summary"
has "$out" "review spend \$5.00 in the builds, \$1.50 in the finishes" "  with the spend on each side"
printf '{"ts": "1970-01-01T02:00:00+0000", "project": "p", "branch": "b2", "phase": "finish", "skipped": "build-reviewed clean"}\n' \
  >> "$C/review-gate.jsonl"
out=$(cmp); has "$out" "2 build(s), 2 with a finish review (1 skipped)" "a landing whose review was skipped (review-gate skipped) counts, named skipped"
has "$out" " skipped " "  its row says skipped, not 0/0/0"
check "$(BUILD_REVIEW_LOG="$T/none/build-review.jsonl" "$B/build-review" compare 2>&1 | head -1 | cut -c1-28)" "no ended build-review record" "no log: says so, exit 0"

echo "== the round cap, read live from the config key"
K="$REGATTA_CONFIG/wharf-runs/build-review-rounds"
check "$(br cap)" "5" "cap: the key's value"
rm -f "$K"; check "$(br cap)" "3" "  no key: the default, 3 (D2-B)"
printf '4  # the owner, a note\n' > "$K"; check "$(br cap)" "4" "  a note after # is no text"
printf '1\n2\n' > "$K"; out=$(br cap); check "$out" "$(printf 'build-review: wharf-runs/build-review-rounds is no whole number from 1 to 20 — the default, 3\n3')" \
  "  a value that is no one number: the default, said on stderr"
for v in 0 00 21 -1 x; do printf '%s\n' "$v" > "$K"; check "$("$B/build-review" cap 2>/dev/null)" "3" "  $v is refused: the default"; done
printf '2\n' > "$K"
W2="$T/wt-cap"; git -C "$T/repo" worktree add -q -b claude/laptop/2026-11-02-cap "$W2" main
for i in 1 2; do br round "$W2" --verdicts "$(vf 1)" --fixed 1 --check red >/dev/null; done
out=$(br round "$W2" --verdicts "$(vf 1)" --fixed 1 --check red); check "$?" "3" "  a key lowered to 2: the third round is refused at once"
has "$out" "2 rounds already, the cap" "    in the cap's words"
printf '5\n' > "$K"

echo "== covers: may /finish skip its review? (TODO.md [second-review]'s D1-B, and its landing review)"
export REVIEW_GATE_LOG="$T/log/review-gate.jsonl"
GS="$T/gate-stub"; printf '#!/bin/sh\necho "{\\"principal\\": null}"\n' > "$GS"; chmod +x "$GS"; export BUILD_REVIEW_GATE="$GS"
git init -q -b main "$T/cv"; printf 'a = 1\n' > "$T/cv/a.py"; mkdir -p "$T/cv/tests"
printf 'for f in "$(dirname "$0")"/*.sh; do bash "$f"; done\n' > "$T/cv/tests/check.sh"   # a runner: its suites are vouchable
git -C "$T/cv" add a.py tests; git -C "$T/cv" commit -q -m init
V="$T/wt-cv"; CVB=claude/laptop/2026-11-02-cv; git -C "$T/cv" worktree add -q -b "$CVB" "$V" main
printf 'if x:\n    b = 2\nc = 1\n' > "$V/b.py"; git -C "$V" add b.py; git -C "$V" commit -q -m b
gate_line() {   # a build round's review-gate line: what review-gate merge --phase build writes, head included
  python3 -c 'import json, sys, time; print(json.dumps({"ts": time.strftime("%Y-%m-%dT%H:%M:%S%z"), "project": "cv", "branch": sys.argv[1], "phase": sys.argv[3], "head": sys.argv[2]}))' \
    "$CVB" "$(git -C "$V" rev-parse HEAD)" "${1:-build}" >> "$REVIEW_GATE_LOG"; }
fin() { CLAUDE_CODE_SESSION_ID=fin "$B/build-review" covers "$V" --base "${1:-main}" 2>&1; }
out=$(fin); check "$?" "1" "no record: not covered"
has "$out" "not covered: no build-review record" "  saying so"
gate_line finish
CLAUDE_CODE_SESSION_ID=cv1 br round "$V" --found 0 --fixed 0 --check green >/dev/null; CLAUDE_CODE_SESSION_ID=cv1 br end "$V" --outcome clean >/dev/null
out=$(fin); check "$?" "1" "a clean end with no build-phase review line (round --found 0 alone): not covered"
has "$out" "no build-phase review-gate line" "  saying nothing shows a review ran"
gate_line
out=$(fin); check "$?" "0" "the loop's last review read this very code, the loop ended clean: covered"
has "$out" "covered: the build's loop ended clean after 1 round(s), its last review read" "  saying which commit"
out=$(CLAUDE_CODE_SESSION_ID=cv1 "$B/build-review" covers "$V" --base main 2>&1); check "$?" "1" "the session that kept the record asks: not covered"
has "$out" "a finish never vouches for itself" "  saying so"
out=$(fin nosuchref); check "$?" "1" "  a base git cannot read: not covered"
has "$out" "git could not diff against nosuchref" "    saying so"
mkdir -p "$V/docs"; printf 'x\n' > "$V/docs/x.md"; printf 'y\n' > "$V/TODO.md"; git -C "$V" add docs TODO.md; git -C "$V" commit -q -m docs
out=$(fin); check "$?" "0" "  docs/ and TODO.md after the review (a step's done stamp): still covered"
mkdir -p "$V/skills" "$V/.helloworld"; printf 's\n' > "$V/skills/SKILL.md"; git -C "$V" add skills; git -C "$V" commit -q -m skill
out=$(fin); check "$?" "1" "a skill's SKILL.md after the review: behaviour, not covered"
git -C "$V" reset -q --hard HEAD~1
printf 'w\n' > "$V/.helloworld/exemptions.txt"; git -C "$V" add .helloworld; git -C "$V" commit -q -m ex
out=$(fin); check "$?" "1" "the publish gate's exemptions after the review: not covered"
git -C "$V" reset -q --hard HEAD~1
printf 'c = 3\n' > "$T/cv/c.py"; git -C "$T/cv" add c.py; git -C "$T/cv" commit -q -m c
git -C "$V" rebase -q main
out=$(fin); check "$?" "0" "  main moved and the branch rebased cleanly: the same code change, still covered"
printf 'z\n' >> "$V/b.py"
out=$(fin); check "$?" "1" "an uncommitted change (a fix the finish has not committed): not covered"
has "$out" "uncommitted changes" "  saying so"
git -C "$V" checkout -q -- b.py
printf 'if x:\n    b = 2\n    c = 1\n' > "$V/b.py"; git -C "$V" commit -qam indent
out=$(fin); check "$?" "1" "a re-indent after the review (the meaning changes, patch-id --stable would call it the same): not covered"
has "$out" "the code changed since the build's last review read it" "  saying so"
git -C "$V" reset -q --hard HEAD~1
printf 'if x:\n    b = 2\nc = 1\n# a check fix\n' > "$V/b.py"; git -C "$V" commit -qam checkfix
RV="$(git -C "$V" rev-parse --absolute-git-dir)/claude/build-review.json"
python3 - "$RV" "$(git -C "$V" rev-parse HEAD)" <<'PY2'
import json, sys
d = json.load(open(sys.argv[1])); d["tip"] = sys.argv[2]; json.dump(d, open(sys.argv[1], "w"))
PY2
out=$(fin); check "$?" "1" "a check fix committed after the last review, the loop's end tip on it: not covered (the review's head counts)"
git -C "$V" reset -q --hard HEAD~1
printf 'q\n' > "$V/é.py"; git -C "$V" add "é.py"; git -C "$V" commit -q -m nonascii
out=$(fin); check "$?" "1" "a non-ASCII code file after the review: counted, not covered"
git -C "$V" reset -q --hard HEAD~1
out=$(fin); check "$?" "0" "  back on the reviewed code: covered again"
mkdir -p "$V/tests"; printf 'echo ok\n' > "$V/tests/test_b.sh"; git -C "$V" add tests; git -C "$V" commit -q -m "a check fix"
out=$(fin); check "$?" "0" "a landing's check fix, only tests/ moved since the review: still covered (landing-fixes-in-run)"
has "$out" "the same bar tests/ (a check fix since)" "  saying the tests moved"
printf 'z = 1\n' >> "$V/b.py"; git -C "$V" commit -qam "code beside the tests"
out=$(fin); check "$?" "1" "  a code change beside the test fix: not covered"
git -C "$V" reset -q --hard HEAD~1
printf 'exit 0\n' > "$V/tests/check.sh"; git -C "$V" add tests; git -C "$V" commit -q -m "the runner"
out=$(fin); check "$?" "1" "  a suite runner (tests/check.sh) after the review: not covered, it decides which suites run"
git -C "$V" reset -q --hard HEAD~2
out=$(fin); check "$?" "0" "  back on the reviewed code: covered"
mkdir -p "$T/cv/.claude"; printf '{"autofinish_exclude": ["tests/gate.sh"]}\n' > "$T/cv/.claude/workflow.json"
git -C "$T/cv" add .claude/workflow.json; git -C "$T/cv" commit -q -m "the gated list"; git -C "$V" rebase -q main
mkdir -p "$V/tests"; printf 'exit 0\n' > "$V/tests/gate.sh"; git -C "$V" add tests; git -C "$V" commit -q -m "a gate script"
out=$(fin); check "$?" "1" "  a tests/ file on the base's autofinish_exclude (classes.sh's kind) after the review: not covered"
git -C "$V" reset -q --hard HEAD~1
out=$(fin); check "$?" "0" "  back on the reviewed code: covered"
python3 - "$RV" 1 <<'PY2'
import json, sys
d = json.load(open(sys.argv[1])); d["rounds"][-1]["open_s1"] = int(sys.argv[2]); json.dump(d, open(sys.argv[1], "w"))
PY2
out=$(fin); check "$?" "1" "the last round left an S1 its verifier called UNVERIFIABLE: not covered, /finish reviews (verified-rounds landing review)"
has "$out" "left 1 S1 its verifier called UNVERIFIABLE" "  saying so"
python3 - "$RV" 0 <<'PY2'
import json, sys
d = json.load(open(sys.argv[1])); d["rounds"][-1]["open_s1"] = int(sys.argv[2]); json.dump(d, open(sys.argv[1], "w"))
PY2
mv "$RV" "$T/rv.json"
out=$(fin); check "$?" "0" "no record in the worktree (lost on this host): the log's newest ended line serves"
mv "$T/rv.json" "$RV"
printf '#!/bin/sh\necho "{\\"principal\\": \\"brief\\"}"\n' > "$GS"
out=$(fin); check "$?" "1" "a principal build: not covered, its top-tier review runs"
printf '#!/bin/sh\nexit 2\n' > "$GS"
out=$(fin); check "$?" "1" "  a plan that does not read: not covered"
printf '#!/bin/sh\necho "{\\"principal\\": null}"\n' > "$GS"
for oc in cap held died; do
  python3 - "$RV" "$oc" <<'PY2'
import json, sys
d = json.load(open(sys.argv[1])); d["outcome"] = sys.argv[2]; json.dump(d, open(sys.argv[1], "w"))
PY2
  out=$(fin); check "$?" "1" "a loop that ended $oc: not covered, the finish reviews"
done
python3 - "$RV" <<'PY2'
import json, sys
d = json.load(open(sys.argv[1])); d.pop("ended"); json.dump(d, open(sys.argv[1], "w"))
PY2
out=$(fin); check "$?" "1" "a loop that never ended: not covered, and the log is not asked over it"
has "$out" "never ended" "  saying so"
mkdir -p "$V/.claude"; printf '{"checkpoint": true}\n' > "$V/.claude/workflow.json"
mkdir -p "$T/cv/.claude"; printf '{"checkpoint": true, "in_place": ["memory/"]}\n' > "$T/cv/.claude/workflow.json"
out=$(fin); check "$?" "1" "in_place in the main checkout's workflow.json, the branch's copy without it: never covered"
has "$out" "a repo with in_place" "  saying so, before the record is read"
unset REVIEW_GATE_LOG BUILD_REVIEW_GATE

echo "== compare: a held loop reopened logs twice, counted once; S? kept"
C2="$T/cmp2"; mkdir -p "$C2"
python3 - "$C2" <<'PY2'
import json, sys
C = sys.argv[1]
with open(C + "/build-review.jsonl", "w") as f:
    for d in ({"project": "p", "branch": "h", "session": "s", "started": 1, "ended": 100, "outcome": "held",
               "rounds": [{"found": 2, "fixed": 1}]},
              {"project": "p", "branch": "h", "session": "s", "started": 1, "ended": 200, "outcome": "clean",
               "rounds": [{"found": 2, "fixed": 1}, {"found": 0, "fixed": 0}]}):
        f.write(json.dumps(d) + "\n")
with open(C + "/review-gate.jsonl", "w") as f:
    f.write(json.dumps({"ts": "1970-01-01T01:00:00+0000", "project": "p", "branch": "h", "phase": "finish",
                        "findings": {"S?": 9}}) + "\n")
PY2
BUILD_REVIEW_LOG="$C2/build-review.jsonl" "$B/build-review" compare --json > "$T/cmp2.json" 2>&1
check "$(python3 -c 'import json, sys; r = json.load(open(sys.argv[1]))[0]; print(r["rounds"], r["found"], r["fixed"], r["outcomes"], r["finish"][0]["S?"])' "$T/cmp2.json")" \
  "2 2 1 ['clean'] 9" "the last line of a (session, started) counts; a finish's unsorted S? is kept"

echo "== real is the verifier's word: a round is granted only on a confirmed finding or a red check (verified-rounds)"
export CLAUDE_CODE_SESSION_ID=vr1
W3="$T/wt-vr"; git -C "$T/repo" worktree add -q -b claude/laptop/2026-11-02-vr "$W3" main
R3="$(git -C "$W3" rev-parse --absolute-git-dir)/claude/build-review.json"
out=$(br round "$W3" --found 2 --fixed 2 --check green); check "$?" "2" "a count above 0 from the builder: refused"
has "$out" "a real finding is the verifier's word, never the builder's" "  saying whose word it is"
check "$([ -f "$R3" ] && echo yes || echo no)" "no" "  and nothing written"
out=$(br round "$W3" --found 0 --verdicts "$(vf 1)" --fixed 0); check "$?" "2" "--found and --verdicts together: refused"
out=$(br round "$W3" --fixed 0 --check green); check "$?" "2" "neither: refused, naming both roads"
has "$out" "--verdicts <the verifier's report>, or --found 0" "  saying so"
printf 'all fine, nothing to report\n' > "$T/vf-empty"
out=$(br round "$W3" --verdicts "$T/vf-empty" --fixed 0 --check green); check "$?" "2" "a verdict file with no verdict line: refused"
has "$out" "no \`verdict:\` line" "  saying so"
out=$(br round "$W3" --verdicts "$T/nofile" --fixed 0 --check green); check "$?" "2" "a verdict file that does not read: refused"
check "$([ -f "$R3" ] && echo yes || echo no)" "no" "  and still nothing written"
cat > "$T/vf-mixed" <<'VF'
a.py:10 — [S1] the lock is never released on the error path
verdict: WRONG
evidence: raise at a.py:12 skips the release; probe left the lock file behind

`b.py:3` — [S2] off by one at the cap
verdict: WRONG
evidence: n == cap passes the check; traced with cap=3, n=3
fix: >=

c.py:4 — [S2] might race under load
verdict: WRONG
fix: a lock

d.py:9 — [S3] a clearer name
verdict: WRONG
evidence: the name reads wrong

e.py:1 — [S2] the default differs from main's
verdict: OK-BUT
evidence: the brief names the new default

f.py:2 — [S1] could leak a temp file
verdict: UNVERIFIABLE
evidence: no input found that reaches it
VF
out=$(br round "$W3" --verdicts "$T/vf-mixed" --fixed 2 --check green); check "$?" "0" "a verifier's report is a round's count"
check "$(js "$R3" 'd["rounds"][0]["raised"], d["rounds"][0]["found"], d["rounds"][0]["left"]')" "(6, 2, 0)" \
  "  six raised, two real: WRONG without evidence, an [S3] head, OK-BUT and UNVERIFIABLE are not"
check "$(js "$R3" 'd["rounds"][0]["open_s1"]')" "1" "  the [S1] its verifier called UNVERIFIABLE is kept, for covers"
case "$out" in *"end it"*) echo "  FAIL a round that confirmed 2 was told to end"; fails=$((fails+1));; *) echo "  ok   a round that confirmed 2 is not told to end";; esac
git -C "$W3" commit -q --allow-empty -m fixes
out=$(br round "$W3" --verdicts "$(vf 0)" --fixed 0 --check red); check "$?" "0" "round 2, granted by round 1's real findings: all refuted, the check red"
check "$(js "$R3" 'd["rounds"][1]["raised"], d["rounds"][1]["found"]')" "(1, 0)" "  one raised, none real"
out=$(br round "$W3" --found 0 --fixed 0 --check green); check "$?" "0" "round 3, granted by round 2's red check"
out=$(br round "$W3" --found 0 --fixed 0 --check green); check "$?" "4" "a round after one that confirmed nothing with the check green: not granted (exit 4)"
has "$out" "round 3 confirmed no real finding and its check was green: no further round is granted" "  in the grant's words"
has "$out" "--outcome clean" "  naming the end it owes"
check "$(js "$R3" 'len(d["rounds"])')" "3" "  and writes nothing"
out=$(br end "$W3" --outcome clean); check "$?" "0" "  so the loop ends clean"
W4="$T/wt-vr2"; git -C "$T/repo" worktree add -q -b claude/laptop/2026-11-02-vr2 "$W4" main
br round "$W4" --verdicts "$(vf 0)" --fixed 0 --check green >/dev/null
out=$(br end "$W4" --outcome clean); check "$?" "0" "every S1 and S2 refuted in round 1, the check green: a clean end after one round"
cat > "$T/vf-shapes" <<'VF'
a.py:1 — [S2] evidence wrapped onto the next line
verdict: WRONG
evidence:
  ran f(3), got 4

b.py:2 — [S2] unlike the [S3] note, real
verdict: WRONG
evidence: x=1 gives 2

c.py:3 — [S2] a theory
verdict: WRONG
evidence: none, a theory not probed

d.py:4 — [S3] a long claim whose head
  wraps onto a second line
verdict: WRONG
evidence: x

e.py:5 — [S2] no evidence of its own
verdict: WRONG

f.py:6 — [S2] its evidence comes first
evidence: belongs to f, not e
verdict: OK-BUT
VF
W5="$T/wt-vr3"; git -C "$T/repo" worktree add -q -b claude/laptop/2026-11-02-vr3 "$W5" main
R5="$(git -C "$W5" rev-parse --absolute-git-dir)/claude/build-review.json"
br round "$W5" --verdicts "$T/vf-shapes" --fixed 2 --check green >/dev/null
check "$(js "$R5" 'd["rounds"][0]["raised"], d["rounds"][0]["found"]')" "(6, 2)" \
  "the parser: wrapped evidence and a claim naming [S3] count; 'none', a wrapped [S3] head and a borrowed evidence do not"
W6="$T/wt-vr4"; git -C "$T/repo" worktree add -q -b claude/laptop/2026-11-02-vr4 "$W6" main
CLAUDE_CODE_SESSION_ID=vr4 br round "$W6" --verdicts "$(vf 0)" --fixed 0 --left 1 --check green >/dev/null
CLAUDE_CODE_SESSION_ID=vr4 br end "$W6" --outcome held --why "D1 open" >/dev/null
git -C "$W6" commit -q --allow-empty -m answer
out=$(CLAUDE_CODE_SESSION_ID=vr4 br round "$W6" --found 0 --fixed 0 --check green); check "$?" "0" "a held loop reopened by the answer's session: granted, though its round confirmed nothing (the D-item road)"
W7="$T/wt-vr5"; git -C "$T/repo" worktree add -q -b claude/laptop/2026-11-02-vr5 "$W7" main
CLAUDE_CODE_SESSION_ID=vr5 br round "$W7" --found 0 --fixed 0 >/dev/null
out=$(CLAUDE_CODE_SESSION_ID=vr5 br round "$W7" --found 0 --fixed 0); check "$?" "4" "a round after one with no --check and nothing confirmed: not granted"
has "$out" "its check was not recorded" "  saying so"
printf '1\n' > "$K"
W8="$T/wt-vr6"; git -C "$T/repo" worktree add -q -b claude/laptop/2026-11-02-vr6 "$W8" main
CLAUDE_CODE_SESSION_ID=vr6 br round "$W8" --found 0 --fixed 0 --check green >/dev/null
out=$(CLAUDE_CODE_SESSION_ID=vr6 br round "$W8" --found 0 --fixed 0 --check green); check "$?" "4" "at the cap after a clean round: told to end clean (exit 4), not cap"
printf '5\n' > "$K"
export CLAUDE_CODE_SESSION_ID=s0

echo "== the final-tip rule: the loop's last review reads the tip it hands over (landing-fixes-in-run)"
export REVIEW_GATE_LOG="$T/log/rg-tip.jsonl"
rg() {   # a review-gate line of a phase for branch $1 in worktree $2, head its tip: what review-gate merge writes
  python3 -c 'import json, sys, time; print(json.dumps({"ts": time.strftime("%Y-%m-%dT%H:%M:%S%z"), "project": "repo", "branch": sys.argv[1], "phase": sys.argv[3], "head": sys.argv[2]}))' \
    "$1" "$(git -C "$2" rev-parse HEAD)" "${3:-build}" >> "$REVIEW_GATE_LOG"; }
W9="$T/wt-tip"; TB=claude/laptop/2026-11-04-tip; git -C "$T/repo" worktree add -q -b "$TB" "$W9" main
R9="$(git -C "$W9" rev-parse --absolute-git-dir)/claude/build-review.json"
export CLAUDE_CODE_SESSION_ID=tip1
printf 'a = 1\n' > "$W9/a.py"; git -C "$W9" add a.py; git -C "$W9" commit -q -m code; H1=$(git -C "$W9" rev-parse HEAD)
rg "$TB" "$W9"
printf 'a = 2\n' > "$W9/a.py"; git -C "$W9" commit -qam "round 1's fix"
br round "$W9" --verdicts "$(vf 1)" --fixed 1 --check green >/dev/null
check "$(js "$R9" 'd["rounds"][0]["reviewed"] == sys.argv[3]' "$H1")" "True" "a round keeps the head its review read (the newest build-phase line), not its tip"
rg "$TB" "$W9"; H2=$(git -C "$W9" rev-parse HEAD)
printf 'a = 2  # clearer\n' > "$W9/a.py"; git -C "$W9" commit -qam "an S3 fixed in passing, after round 2's review"
out=$(br round "$W9" --found 0 --fixed 0 --check green); check "$?" "0" "round 2 confirmed nothing, but a fix came after its review"
has "$out" "nothing found, but the code moved since its review read ${H2:0:9}: one more round reviews the tip" "  told so, never to end clean"
out=$(br end "$W9" --outcome clean); check "$?" "2" "  a clean end now: refused (claim-after-failed-start's 'clean in 2 rounds' on an unreviewed tip)"
has "$out" "not clean: the last round's build review read ${H2:0:9}, and the code at HEAD differs from it" "    saying which head the review read"
rg "$TB" "$W9"
out=$(br round "$W9" --found 0 --fixed 0 --check green); check "$?" "0" "round 3 is granted: the code moved past round 2's review"
has "$out" "nothing found and the check green: end it (--outcome clean)" "  its review read the tip: told to end clean"
mkdir -p "$W9/docs"; printf 'done\n' > "$W9/docs/x.md"; printf -- '- a line\n' > "$W9/CHANGELOG.md"; git -C "$W9" add docs CHANGELOG.md; git -C "$W9" commit -q -m "the step's stamp"
out=$(br round "$W9" --found 0 --fixed 0 --check green); check "$?" "4" "  docs and a CHANGELOG after the last review grant no round"
out=$(br end "$W9" --outcome clean); check "$?" "0" "  and the loop ends clean on them"
# a clean merge of main (check --ci keeps a build's PR mergeable) leaves the branch's own change as its review read it
W10="$T/wt-merge"; TB3=claude/laptop/2026-11-05-merge; git -C "$T/repo" worktree add -q -b "$TB3" "$W10" main
printf 'b = 1\n' > "$W10/b.py"; git -C "$W10" add b.py; git -C "$W10" commit -q -m code; rg "$TB3" "$W10"
MB=$(git -C "$T/repo" rev-parse main); MW="$T/wt-main-moves"; git -C "$T/repo" worktree add -q --detach "$MW" main
printf 'c = 1\n' > "$MW/c.py"; git -C "$MW" add c.py; git -C "$MW" commit -q -m "main moves"; git -C "$T/repo" update-ref refs/heads/main "$(git -C "$MW" rev-parse HEAD)" "$MB"
git -C "$W10" merge -q --no-edit main
out=$(br round "$W10" --found 0 --fixed 0 --check green); check "$?" "0" "a clean round after a clean merge of main"
has "$out" "nothing found and the check green: end it (--outcome clean)" "  the merge is no new code: told to end clean"
out=$(br end "$W10" --outcome clean); check "$?" "0" "  and the loop ends clean"
W9b="$T/wt-tip2"; TB2=claude/laptop/2026-11-04-tip2; git -C "$T/repo" worktree add -q -b "$TB2" "$W9b" main
printf 'b = 1\n' > "$W9b/b.py"; git -C "$W9b" add b.py; git -C "$W9b" commit -q -m code
CLAUDE_CODE_SESSION_ID=tip2 br round "$W9b" --found 0 --fixed 0 --check green >/dev/null
out=$(CLAUDE_CODE_SESSION_ID=tip2 br end "$W9b" --outcome clean); check "$?" "0" "a round with no review-gate line behind it (prose-only): ends clean as before"

echo "== --phase finish: the landing's own loop, beside the build's record (landing-fixes-in-run)"
WF="$T/wt-fin"; FB=claude/laptop/2026-11-04-fin; git -C "$T/repo" worktree add -q -b "$FB" "$WF" main
RB="$(git -C "$WF" rev-parse --absolute-git-dir)/claude/build-review.json"; RF="${RB%/*}/build-review-finish.json"
printf 'c = 1\n' > "$WF/c.py"; git -C "$WF" add c.py; git -C "$WF" commit -q -m code
rg "$FB" "$WF"
CLAUDE_CODE_SESSION_ID=fb1 br round "$WF" --found 0 --fixed 0 --check green >/dev/null; CLAUDE_CODE_SESSION_ID=fb1 br end "$WF" --outcome clean >/dev/null
export CLAUDE_CODE_SESSION_ID=ff1
rg "$FB" "$WF" finish
out=$(br round "$WF" --phase finish --verdicts "$(vf 1)" --fixed 1 --check green); check "$?" "0" "a finish round is recorded"
check "$(js "$RF" 'd["phase"], d["session"], len(d["rounds"]), d["rounds"][0]["reviewed"] == sys.argv[3]' "$(git -C "$WF" rev-parse HEAD)")" "('finish', 'ff1', 1, True)" \
  "  in build-review-finish.json, marked finish, its head read from a phase-finish review line"
check "$(js "$RB" 'd["session"], d["outcome"]')" "('fb1', 'clean')" "  the build's record left as it was: covers and gate read it"
check "$(br show "$WF" --phase finish | js /dev/stdin 'd["phase"]')" "finish" "  show --phase finish prints it"
br gate "$WF" --session ff1 >/dev/null; check "$?" "0" "  gate reads the build's record alone"
rg "$FB" "$WF" finish
out=$(br round "$WF" --phase finish --found 0 --fixed 0 --check green); check "$?" "0" "  round 2, granted by round 1's confirmed finding"
out=$(br round "$WF" --phase finish --found 0 --fixed 0 --check green); check "$?" "4" "  the grant's rule holds for the finish's loop too"
for twice in "--phase finish --phase build" "--phase finish --ph build" "--phase=finish --phase=build"; do
  out=$(br end "$WF" $twice --outcome clean); check "$?" "2" "  --phase given twice ($twice): refused, the landing's allow rule names it once"
  has "$out" "--phase given twice: once only" "    in those words, before any record is read"
done
out=$(br end "$WF" --phase finish --outcome clean); check "$?" "0" "  and it ends clean"
check "$(tail -1 "$BUILD_REVIEW_LOG" | js /dev/stdin 'd["phase"], d["outcome"], len(d["rounds"])')" "('finish', 'clean', 2)" "  its log line marked finish"
mv "$RB" "$T/rb.json"
GS="$T/gate-stub"; printf '#!/bin/sh\necho "{\\"principal\\": null}"\n' > "$GS"; chmod +x "$GS"
out=$(CLAUDE_CODE_SESSION_ID=other BUILD_REVIEW_GATE="$GS" "$B/build-review" covers "$WF" --base main 2>&1); check "$?" "0" "covers' fallback to the log takes the build's line, never the finish's"
has "$out" "after 1 round(s)" "  the build's one round, not the finish's two"
mv "$T/rb.json" "$RB"
BUILD_REVIEW_LOG="$BUILD_REVIEW_LOG" "$B/build-review" compare --json > "$T/cmp-fin.json" 2>&1
check "$(python3 -c 'import json, sys; r = [x for x in json.load(open(sys.argv[1])) if x["branch"] == sys.argv[2]][0]; print(r["outcomes"], r["rounds"], r["finish_rounds"], r["finish_found"], r["finish_fixed"])' "$T/cmp-fin.json" "$FB")" \
  "['clean'] 1 2 1 1" "compare: a finish loop is no build row; its rounds counted on the build's"

echo "== the final-tip rule at the cap: no round is left to review a move (the round-1 verifier's finding)"
printf '2\n' > "$K"
WC="$T/wt-capt"; CB=claude/laptop/2026-11-04-capt; git -C "$T/repo" worktree add -q -b "$CB" "$WC" main
printf 'x = 1\n' > "$WC/x.py"; git -C "$WC" add x.py; git -C "$WC" commit -q -m code
export CLAUDE_CODE_SESSION_ID=capt1
rg "$CB" "$WC"; br round "$WC" --verdicts "$(vf 1)" --fixed 1 --check green >/dev/null
rg "$CB" "$WC"; mkdir -p "$WC/tests"; printf 'ok\n' > "$WC/tests/t.sh"; git -C "$WC" add tests; git -C "$WC" commit -q -m "a check fix after round 2's review"
out=$(br round "$WC" --found 0 --fixed 0 --check green); has "$out" "round 2 of 2 recorded — nothing found and the check green: end it (--outcome clean)" "a build at the cap, the code moved since its review: told to end clean"
out=$(br end "$WC" --outcome clean); check "$?" "0" "  and it ends clean, as on main"
has "$out" "at the cap: ended clean, and /finish reviews the move (covers says no)" "  saying /finish reviews the move"
export CLAUDE_CODE_SESSION_ID=capt2
rg "$CB" "$WC" finish; br round "$WC" --phase finish --verdicts "$(vf 1)" --fixed 1 --check green >/dev/null
rg "$CB" "$WC" finish; printf 'x = 2\n' > "$WC/x.py"; git -C "$WC" commit -qam "a code fix after the finish's round 2 review"
out=$(br round "$WC" --phase finish --found 0 --fixed 0 --check green); has "$out" "at the cap: end it clean only on a tests-only move, else cap" "a finish at the cap, code moved since its review: told so"
out=$(br end "$WC" --phase finish --outcome clean); check "$?" "2" "  a clean end is refused: no later review would read the move"
has "$out" "end cap: no round is left under the cap to review it" "    saying the way out, never that a round is granted"
out=$(br round "$WC" --phase finish --found 0 --fixed 0 --check green); check "$?" "3" "  a round past the cap that only the move would grant: refused"
has "$out" "no round is left to review the move since" "    saying the end's own verdict"
has "$out" "cap (--phase finish --outcome cap): no later review reads it" "    a code move in a finish: cap"
git -C "$WC" reset -q --hard HEAD~1; printf 'ok2\n' > "$WC/tests/t.sh"; git -C "$WC" commit -qam "a test fix instead"
out=$(br end "$WC" --phase finish --outcome clean); check "$?" "0" "  a tests-only move at the cap (a check fix): the finish ends clean"
WS="$T/wt-s1"; SB=claude/laptop/2026-11-04-s1; git -C "$T/repo" worktree add -q -b "$SB" "$WS" main
printf 's = 1\n' > "$WS/s.py"; git -C "$WS" add s.py; git -C "$WS" commit -q -m code
printf 'a.py:1 — [S1] the lock may leak\nverdict: UNVERIFIABLE\nevidence: no input found that reaches it\n' > "$T/vf-s1"
export CLAUDE_CODE_SESSION_ID=s1fin
rg "$SB" "$WS" finish; br round "$WS" --phase finish --verdicts "$T/vf-s1" --fixed 0 --check green >/dev/null
out=$(br end "$WS" --phase finish --outcome clean); check "$?" "2" "a finish whose last round left an UNVERIFIABLE S1: no clean end, no later review reads it (round 2's verifier)"
has "$out" "end held (--phase finish --outcome held --why '<the S1>')" "  told to hold, naming it"
out=$(br end "$WS" --phase finish --outcome held --why "the S1 at a.py:1"); check "$?" "0" "  and it ends held"
printf '5\n' > "$K"
unset REVIEW_GATE_LOG
export CLAUDE_CODE_SESSION_ID=s0

echo "== picks: which choices a landing takes itself, which stop it (landing-fixes-in-run)"
cat > "$T/vf-picks" <<'VF'
a.py:1 — [S2] the cap is off by one
verdict: WRONG
evidence: traced with cap=3, n=3: passes
fix: >= in place of >

b.py:2 — [S1] two claims run one chain at once
verdict: WRONG
evidence: probe: two claims on one tip both start
fix: A) one claim per chain; B) a lock per branch
➤ Recommended: A — one claim per chain. Reversible: yes

c.py:3 — [S2] the record's shape changes for every reader
verdict: WRONG
evidence: helm's reader drops the new key, traced
fix: A) a new key; B) a new file
➤ Recommended: B
Reversible: no

d.py:4 — [S2] the default differs
verdict: WRONG
evidence: x=1 gives 2
fix: A) keep main's; B) the new one
➤ Recommended: A

e.py:5 — [S2] stale rows pile up
verdict: WRONG
evidence: 40 rows after a week, read
fix: A) delete the old rows; B) skip them on read
➤ Recommended: A, delete them
Reversible: yes

f.py:6 — [S2] the race needs a probe
verdict: WRONG
evidence: two runs read the file at once, traced
fix: A) a lock; B) nothing
➤ Recommended: if the probe shows a race, A, else B
Reversible: yes

g.py:7 — [S2] a wish, with a pick
verdict: OK-BUT
evidence: the brief asks for it
➤ Recommended: A
Reversible: yes

h.py:8 — [S2] a deletion the defect makes, fixed by a pick that deletes nothing
verdict: WRONG
evidence: the sweep deletes the live lock, traced
fix: A) skip a live lock; B) ask the owner
➤ Recommended: A — skip a live lock
Reversible: yes
VF
printf -- '- check: `true`\n- physical: none\n' > "$T/repo/AGENTS.md"
out=$(br picks "$T/vf-picks" "$W"); check "$?" "5" "a report with a choice it may not take: exit 5"
check "$(printf '%s\n' "$out" | cut -d' ' -f1-2 | tr '\n' ' ')" "fix a.py:1 take b.py:2 stop c.py:3 stop d.py:4 stop e.py:5 stop f.py:6 take h.py:8 " \
  "  one line per real finding, an OK-BUT none: fix, take or stop"
has "$out" "take b.py:2 — [S1] two claims run one chain at once — A — one claim per chain" "  a reversible recommended pick is taken, the pick named (claim-after-failed-start's S1)"
has "$out" "stop c.py:3 — [S2] the record's shape changes for every reader — Reversible: no" "  Reversible: no stops"
has "$out" "stop d.py:4 — [S2] the default differs — not marked Reversible: yes|no" "  an unmarked pick stops"
has "$out" "stop e.py:5 — [S2] stale rows pile up — a deletion (delete)" "  a held class in the pick stops (keel's dnd_held)"
has "$out" "a conditional pick (if the probe shows a race, A, else B)" "  a conditional pick stops"
python3 - "$T/vf-picks" "$T/vf-take" <<'PY2'
import re, sys
blocks = open(sys.argv[1]).read().split("\n\n")
open(sys.argv[2], "w").write("\n\n".join(b for b in blocks if not re.match(r"[cdef]\.py", b)))
PY2
out=$(br picks "$T/vf-take" "$W"); check "$?" "0" "only mechanical fixes and picks it may take: exit 0, the landing goes on"
printf -- '- check: `true`\n- physical: the yard, by hand\n' > "$T/repo/AGENTS.md"
out=$(br picks "$T/vf-take" "$W"); check "$?" "5" "  a physical repo: every pick stops"
has "$out" "the repo acts on the real world (physical: the yard" "    saying so"
rm -f "$T/repo/AGENTS.md"
out=$(br picks "$T/vf-take" "$W"); check "$?" "5" "  no physical: line: read as physical"
cat > "$T/vf-shapes2" <<'VF'
a.py:1 — [S2] an option's mark is not the pick's
verdict: WRONG
evidence: traced
fix: A) a lock (Reversible: yes); B) a new file layout (Reversible: no)
➤ Recommended: B
Reversible: no

b.py:2 — [S2] a hedged yes
verdict: WRONG
evidence: traced
fix: A) a cache; B) none
➤ Recommended: A
Reversible: yes, as long as no reader has cached the old value

c.py:3 — [S2] a mark only the evidence quotes
verdict: WRONG
evidence: the flag's doc says Reversible: yes for the flag
fix: A) one; B) two
➤ Recommended: B

d.py:4 — [S2] options and no pick
verdict: WRONG
evidence: traced
fix: A) a lock per branch; B) one claim per chain

e.py:5 — [S2] a Recommended line holding only the mark
verdict: WRONG
evidence: traced
fix: A) x; B) y
➤ Recommended: Reversible: yes

f.py:6 — [S2] options a blank line parts from the fix
verdict: WRONG
evidence: traced
fix: two options:

A) a lock per branch
B) one claim per chain, deleting the old claim files
➤ Recommended: B
Reversible: yes

g.py:7 — [S2] a pick whose block costs a model run
verdict: WRONG
evidence: traced
fix: A) a reviewer at $2.10 ($0.40 effective); B) none
➤ Recommended: A — one more review. Reversible: yes
VF
printf -- '- check: `true`\n- physical: none\n' > "$T/repo/AGENTS.md"
out=$(br picks "$T/vf-shapes2" "$W")
check "$(printf '%s\n' "$out" | cut -d' ' -f1-2 | tr '\n' ' ')" "stop a.py:1 stop b.py:2 stop c.py:3 stop d.py:4 stop e.py:5 stop f.py:6 take g.py:7 " \
  "the round-1 verifier's shapes: an option's mark, a hedged yes, an evidence mark, no pick, a mark for a pick, a parted option all stop; a model cost is no money"
has "$out" "stop a.py:1 — [S2] an option's mark is not the pick's — Reversible: no" "  the mark after the Recommended line is the pick's"
has "$out" "stop d.py:4 — [S2] options and no pick — a choice with no ➤ Recommended: pick" "  options with no pick named stop"
has "$out" "stop e.py:5 — [S2] a Recommended line holding only the mark — no pick named" "  a mark is no pick"
has "$out" "stop f.py:6 — [S2] options a blank line parts from the fix — a deletion (deleting)" "  an option past a blank line is scanned for the held classes"
python3 - "$T/vf-shapes3" <<'PY2'
import sys
def blk(name, fix, rest=""):
    return "%s — [S2] x\nverdict: WRONG\nevidence: traced\n%s%s\n\n" % (name, fix, "\n" + rest if rest else "")
open(sys.argv[1], "w").write("".join([
    blk("a.py:1", "fix: A) foo; B) bar", "➤ **Recommended:**\nReversible: yes"),
    blk("b.py:2", "fix: A) foo; B) bar", "➤ **Recommended:** depends on the owner\nReversible: yes"),
    blk("c.py:3", "fix: A) foo; B) bar", "**➤ Recommended:** none\nReversible: yes"),
    blk("d.py:4", "fix: A) foo; B) bar", "➤ **Recommended:** if the queue is empty, A\nReversible: yes"),
    blk("e.py:5", "fix: A) foo; B) bar", "➤ Recommended: none\nReversible: yes"),
    blk("f.py:6", "fix: Option A — foo; Option B — bar"),
    blk("g.py:7", "fix: A. foo; B. bar"),
    blk("h.py:8", "fix: either (a) foo or (b) bar"),
    blk("i.py:9", "fix: two ways:\n- A — foo\n- B — bar"),
    blk("j.py:10", "fix: 1) add x; 2) add y"),
    blk("k.py:11", "fix: A) skip it in the reader; B) filter in the writer — ➤ Recommended: A. Reversible: yes"),
    blk("l.py:12", "fix: A) foo; B) bar", "➤ **Recommended:** A — foo\n**Reversible:** yes"),
]))
PY2
printf -- '- check: `true`\n- physical: none\n' > "$T/repo/AGENTS.md"
out=$(br picks "$T/vf-shapes3" "$W")
check "$(printf '%s\n' "$out" | cut -d' ' -f1-2 | tr '\n' ' ')" "stop a.py:1 stop b.py:2 stop c.py:3 stop d.py:4 stop e.py:5 stop f.py:6 stop g.py:7 stop h.py:8 stop i.py:9 fix j.py:10 take k.py:11 take l.py:12 " \
  "round 2's shapes: a bold label with no pick, a bold conditional, none, and options as Option A, A., (a) or keel's - A — stop; numbered steps are a fix; an inline or bold pick is taken"
printf 'a.py:1 — [S2] x\nverdict: WRONG\nevidence: traced\nfix: A) a; B) b\n➤ Recommended: A\nReversible: yes\nb.py:2 — [S3] y\nverdict: WRONG\nevidence: traced\n' > "$T/vf-noblank"
WNB="$T/wt-nb"; git -C "$T/repo" worktree add -q -b claude/laptop/2026-11-04-nb "$WNB" main
CLAUDE_CODE_SESSION_ID=nb br round "$WNB" --verdicts "$T/vf-noblank" --fixed 1 --check green >/dev/null
check "$(js "$(git -C "$WNB" rev-parse --absolute-git-dir)/claude/build-review.json" 'd["rounds"][0]["raised"], d["rounds"][0]["found"]')" "(2, 1)" \
  "  no blank line between blocks: a Recommended line ends its block, the [S3] after it is no finding"
rm -f "$T/repo/AGENTS.md"
out=$(br picks "$T/vf-empty" "$W"); check "$?" "2" "a file with no verdict block: refused"
printf 'a.py:1 — [S2] refuted\nverdict: OK-BUT\nevidence: intended\n' > "$T/vf-none"
out=$(br picks "$T/vf-none" "$W"); check "$?:$out" "0:none: no real finding" "every item refuted: nothing to fix"
K_BIN="$(cd "$B/../../keel/bin" 2>/dev/null && pwd)/keel"
if [ -f "$K_BIN" ]; then
  check "$(python3 - "$K_BIN" "$B/build-review" <<'PY2'
import sys
from importlib.machinery import SourceFileLoader
k = SourceFileLoader("keel", sys.argv[1]).load_module()
b = SourceFileLoader("br", sys.argv[2]).load_module()
print([(w, r.pattern, r.flags) for w, r in k.DND_HOLDS] == [(w, r.pattern, r.flags) for w, r in b.HELD])
PY2
)" "True" "HELD is keel's DND_HOLDS, verbatim (one rule for every unattended pick)"
else
  echo "  FAIL keel is missing beside wharf-runs: HELD cannot be compared with DND_HOLDS"; fails=$((fails+1))
fi

echo "== the landing review's findings: hedged picks, missed option shapes, a dirty tip, the finish's own session"
cat > "$T/vf-hedge" <<'VF'
a.py:1 — [S2] x
verdict: WRONG
evidence: traced
fix: A) a lock; B) a queue
➤ Recommended: A if the queue is shared
Reversible: yes

b.py:2 — [S2] x
verdict: WRONG
evidence: traced
fix: A) a lock; B) a queue
➤ Recommended: A unless the owner objects
Reversible: yes

c.py:3 — [S2] x
verdict: WRONG
evidence: traced
fix: A) a lock; B) a queue
➤ Recommended: A, once the owner confirms
Reversible: yes

d.py:4 — [S2] x
verdict: WRONG
evidence: traced
fix: A) a lock; B) a queue
➤ Recommended: (none)
Reversible: yes

e.py:5 — [S2] x
verdict: WRONG
evidence: traced
fix: A) a lock; B) a queue
➤ Recommended: neither — ask the owner
Reversible: yes

f.py:6 — [S2] x
verdict: WRONG
evidence: traced
fix: A) a lock; B) a queue
➤ Recommended: the owner's call
Reversible: yes

g.py:7 — [S2] x
verdict: WRONG
evidence: traced
fix: A) a lock; B) a queue
➤ Recommended: C
Reversible: yes

h.py:8 — [S2] x
verdict: WRONG
evidence: traced
fix: A) a lock; B) a queue
➤ Recommended: A. Reversible: yes
Reversible: no — A rewrites the record every reader keeps

i.py:9 — [S2] x
verdict: WRONG
evidence: traced; options: A) delete the live lock; B) skip it
➤ Recommended: B
Reversible: yes

j.py:10 — [S2] x
verdict: WRONG
evidence: traced
fix: Option 1 — refuse the lock; Option 2 — warn

k.py:11 — [S2] x
verdict: WRONG
evidence: traced
fix: a) refuse; b) warn

l.py:12 — [S2] x
verdict: WRONG
evidence: traced
fix: A: refuse; B: warn

m.py:13 — [S2] x
verdict: WRONG
evidence: traced
fix: either refuse the stale lock or warn about it

n.py:14 — [S2] x
verdict: WRONG
evidence: traced
fix: A) a lock; B) a queue
➤ Recommended: A — even if the queue grows, a lock
Reversible: yes

o.py:15 — [S2] x
verdict: WRONG
evidence: traced
fix: Option 1 — a lock; Option 2 — a queue
➤ Recommended: Option 2
Reversible: yes
VF
printf -- '- check: `true`\n- physical: none\n' > "$T/repo/AGENTS.md"
out=$(br picks "$T/vf-hedge" "$W")
check "$(printf '%s\n' "$out" | cut -d' ' -f1-2 | tr '\n' ' ')" "stop a.py:1 stop b.py:2 stop c.py:3 stop d.py:4 stop e.py:5 stop f.py:6 stop g.py:7 stop h.py:8 stop i.py:9 stop j.py:10 stop k.py:11 stop l.py:12 stop m.py:13 take n.py:14 take o.py:15 " \
  "a hedge after the letter, no letter, an unlisted letter, contradictory marks, options in the evidence and four more option shapes all stop; even if and Option 2 are taken"
has "$out" "stop a.py:1 — [S2] x — a conditional pick (A if the queue is shared)" "  a hedge after the pick's letter is a conditional pick"
has "$out" "stop f.py:6 — [S2] x — the pick names no listed option (the owner's call)" "  free text names no option"
has "$out" "stop h.py:8 — [S2] x — contradictory Reversible: marks" "  an inline yes and a no line after it"
has "$out" "stop i.py:9 — [S2] x — a deletion (delete)" "  options in the evidence are read for the held classes"
printf -- '- check: `true`\n  - physical: none\n- physical:\n  none\n' > "$T/repo/AGENTS.md"
out=$(br picks "$T/vf-hedge" "$W")
check "$(printf '%s\n' "$out" | grep -c '^take')" "0" "keel's physical: rule: an indented line is none, and a bare one's value is empty, read as physical"
rm -f "$T/repo/AGENTS.md"

export REVIEW_GATE_LOG="$T/log/rg-land.jsonl"
WD="$T/wt-dirty"; DB=claude/laptop/2026-11-05-dirty; git -C "$T/repo" worktree add -q -b "$DB" "$WD" main
printf 'd = 1\n' > "$WD/d.py"; git -C "$WD" add d.py; git -C "$WD" commit -q -m code
export CLAUDE_CODE_SESSION_ID=dirty1
rg "$DB" "$WD" finish
out=$(br round "$WD" --phase finish --found 0 --fixed 0 --check green); check "$?" "0" "a finish round on a reviewed tip"
printf 'd = 2\n' > "$WD/d.py"
out=$(br end "$WD" --phase finish --outcome clean); check "$?" "2" "  an uncommitted code edit: no clean end"
has "$out" "the worktree holds uncommitted changes no review read (d.py)" "    naming the path"
git -C "$WD" checkout -q -- d.py; printf 'n\n' > "$WD/new.py"
out=$(br end "$WD" --phase finish --outcome clean); check "$?" "2" "  an untracked file too"
rm -f "$WD/new.py"; mkdir -p "$WD/docs"; printf 'n\n' > "$WD/docs/n.md"
out=$(br end "$WD" --phase finish --outcome clean); check "$?" "0" "  an uncommitted doc is no code: it ends clean"
rm -rf "$WD/docs"

WR="$T/wt-later"; LB=claude/laptop/2026-11-05-later; git -C "$T/repo" worktree add -q -b "$LB" "$WR" main
printf 'l = 1\n' > "$WR/l.py"; git -C "$WR" add l.py; git -C "$WR" commit -q -m code
export CLAUDE_CODE_SESSION_ID=later1
rg "$LB" "$WR" finish
out=$(br round "$WR" --phase finish --found 0 --fixed 0 --check green); check "$?" "0" "a finish round, then a fix commit"
printf 'l = 2\n' > "$WR/l.py"; git -C "$WR" commit -q -am fix
rg "$LB" "$WR" finish
out=$(br end "$WR" --phase finish --outcome clean); check "$?" "2" "  a review logged after the last round, never recorded: no clean end"
has "$out" "the last round's finish review read" "    the last round's head is the one judged"

WS="$T/wt-s1b"; SB=claude/laptop/2026-11-05-s1b; git -C "$T/repo" worktree add -q -b "$SB" "$WS" main
printf 's = 1\n' > "$WS/s.py"; git -C "$WS" add s.py; git -C "$WS" commit -q -m code
export CLAUDE_CODE_SESSION_ID=s1two
printf 'a.py:1 — [S2] x\nverdict: WRONG\nevidence: traced\n\nb.py:2 — [S1] y\nverdict: UNVERIFIABLE\nevidence: none shown\n' > "$T/vf-s1two"
rg "$SB" "$WS" finish
out=$(br round "$WS" --phase finish --verdicts "$T/vf-s1two" --fixed 1 --check green); check "$?" "0" "round 1 leaves an UNVERIFIABLE S1"
printf 's = 2\n' > "$WS/s.py"; git -C "$WS" commit -q -am fix; rg "$SB" "$WS" finish
out=$(br round "$WS" --phase finish --found 0 --fixed 0 --check green); check "$?" "0" "  round 2 finds nothing"
out=$(br end "$WS" --phase finish --outcome clean); check "$?" "2" "  an earlier round's open S1 still holds the finish"

WA="$T/wt-af"; AB=claude/laptop/2026-11-05-af; git -C "$T/repo" worktree add -q -b "$AB" "$WA" main
export CLAUDE_CODE_SESSION_ID=afrun
mkdir -p "$(git -C "$WA" rev-parse --absolute-git-dir)/claude"
printf '{"session": "afrun", "ended": null}\n' > "$(git -C "$WA" rev-parse --absolute-git-dir)/claude/autofinish.json"
out=$(br round "$WA" --found 0 --fixed 0 --check green --note '--phase finish'); check "$?" "2" "the landing's own session never writes the build's record"
has "$out" "its loop is --phase finish" "  saying so"
check "$([ -f "$(git -C "$WA" rev-parse --absolute-git-dir)/claude/build-review.json" ] && echo written || echo none)" "none" "  and nothing is written"
out=$(br round "$WA" --phase finish --found 0 --fixed 0 --check green); check "$?" "0" "  its --phase finish round is recorded"

WV="$T/wt-vouch"; VB=claude/laptop/2026-11-05-vouch; git -C "$T/repo" worktree add -q -b "$VB" "$WV" main
mkdir -p "$WV/m/tests/fixtures"
printf 'echo fixture\n' > "$WV/m/tests/config_fixture.sh"
printf '. "$(dirname "$0")/config_fixture.sh"\necho a\n' > "$WV/m/tests/a.sh"
printf 'print(1)\n' > "$WV/m/tests/home_rm.py"
printf 'print(1)\n' > "$WV/m/tests/test_b.py"
printf 'x\n' > "$WV/m/tests/fixtures/f.txt"
printf 'for f in "$D"/*.sh; do bash "$f"; done\npython3 "$D/test_b.py"\npython3 "$D/home_rm.py" x\n' > "$WV/m/tests/check.sh"
mkdir -p "$WV/n/tests"; printf 'bash "$D/x.sh"\n' > "$WV/n/tests/check.sh"
printf 'echo x\n' > "$WV/n/tests/x.sh"; printf 'echo by hand\n' > "$WV/n/tests/y.sh"
printf '# a comment: from y import nothing; . y.sh\necho z\n' > "$WV/n/tests/z.sh"
git -C "$WV" add -A; git -C "$WV" commit -q -m tests
check "$(python3 - "$B/build-review" "$WV" <<'PY2'
import sys
from importlib.machinery import SourceFileLoader
b = SourceFileLoader("br", sys.argv[1]).load_module()
w = sys.argv[2]
print([b.vouchable(w, n, ()) for n in ("m/tests/a.sh", "m/tests/test_b.py", "m/tests/config_fixture.sh",
                                        "m/tests/home_rm.py", "m/tests/fixtures/f.txt", "m/tests/check.sh")],
      b.vouchable(w, "m/tests/a.sh", None), b.gated_paths(w, "no-such-ref"),
      [b.vouchable(w, n, ()) for n in ("n/tests/x.sh", "n/tests/y.sh", "m/tests/gone.sh")])
PY2
)" "[True, True, False, False, False, False] False None [True, False, False]" \
  "covers vouches past a suite its runner runs alone: never a sourced fixture, a helper, a fixtures/ file, a runner, a script run by hand, a deleted suite, nor anything when the gated list does not read"
unset CLAUDE_CODE_SESSION_ID


echo "== the fix review's findings: a finish round with no head, an earlier S1 in covers, hedges and shapes"
WN="$T/wt-nohead"; NB=claude/laptop/2026-11-05-nohead; git -C "$T/repo" worktree add -q -b "$NB" "$WN" main
printf 'n = 1\n' > "$WN/n.py"; git -C "$WN" add n.py; git -C "$WN" commit -q -m code
export CLAUDE_CODE_SESSION_ID=nohead1
out=$(br round "$WN" --phase finish --found 0 --fixed 0 --check green); check "$?" "0" "a finish round with no logged review head"
out=$(br end "$WN" --phase finish --outcome clean); check "$?" "2" "  no clean end: no review is known to have read it"
out=$(br round "$WN" --phase finish --found 0 --fixed 0 --check green); check "$?" "0" "  and the round it names is granted: the loop moves"
cat > "$T/vf-shapes4" <<'VF'
a.py:1 — [S2] x
verdict: WRONG
evidence: traced
fix: A) a lock; B) a queue
➤ Recommended: A — S1 is built and green; nothing else waits
Reversible: yes

b.py:2 — [S2] x
verdict: WRONG
evidence: traced
fix: A) a lock; B) a queue
➤ Recommended: A — a lock, which holds when two runs race
Reversible: yes

c.py:3 — [S2] x
verdict: WRONG
evidence: traced
fix: a) refuse; b) warn
➤ Recommended: a) refuse
Reversible: yes

d.py:4 — [S2] x
verdict: WRONG
evidence: traced
fix: two ways:
- **A** — a lock
- **B** — a queue
➤ Recommended: **A** — a lock
Reversible: yes

e.py:5 — [S2] x
verdict: WRONG
evidence: traced
fix: Option 1 — a lock; Option 2 — a queue
➤ Recommended: 1
Reversible: yes

f.py:6 — [S2] x
verdict: WRONG
evidence: traced
fix: A) a lock; B) a queue
➤ Recommended: B only if the queue is shared
Reversible: yes

g.py:7 — [S2] x
verdict: WRONG
evidence: traced
fix: quote the path
➤ Recommended: A: quote the path. Reversible: yes

h.py:8 — [S2] x
verdict: WRONG
evidence: traced
fix: change `for (k, e) in rows` to `for (a, b) in rows`

i.py:9 — [S2] x
verdict: WRONG
evidence: traced
fix: return None when either git call fails or the file does not parse
VF
printf -- '- check: `true`\n- physical: none\n' > "$T/repo/AGENTS.md"
out=$(br picks "$T/vf-shapes4" "$W")
check "$(printf '%s\n' "$out" | cut -d' ' -f1-2 | tr '\n' ' ')" "take a.py:1 take b.py:2 take c.py:3 take d.py:4 take e.py:5 stop f.py:6 stop g.py:7 fix h.py:8 fix i.py:9 " \
  "a hedge word deep in the reason, a bare a), a bold A and Option 1's digit are taken; only if stops; the Recommended line lists no option; (k, e) and a condition's either are fixes"
rm -f "$T/repo/AGENTS.md"

echo "== refusals"
out=$(br show "$T/nowhere"); check "$?" "2" "a path that is no checkout: exit 2"
has "$out" "is no git checkout" "  saying so"
out=$(br round "$W" --found -1 --fixed 0); check "$?" "2" "a negative count: a usage error"
out=$(env -u CLAUDE_CODE_SESSION_ID "$B/build-review" round "$W" --found 0 --fixed 0 --check green 2>&1); check "$?" "2" "no session id: refused, never read as one shared session"
has "$out" "no CLAUDE_CODE_SESSION_ID" "  saying so"

echo
[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
