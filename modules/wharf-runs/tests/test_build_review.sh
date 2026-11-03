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
W="$T/wt-demo"
git -C "$T/repo" worktree add -q -b claude/laptop/2026-10-30-demo "$W" main
R="$(git -C "$W" rev-parse --absolute-git-dir)/claude/build-review.json"

echo "== the record: per worktree, beside autofinish.json"
check "$(br show "$W")" "none" "no record yet: show says none"
out=$(br round "$W" --verdicts "$(vf 3)" --fixed 3 --check green --reviewers reviewer-high,code-reviewer); check "$?" "0" "a round is recorded"
has "$out" "round 1 of 5 recorded" "  saying which of the cap"
check "$([ -f "$R" ] && echo yes)" "yes" "  in <git dir>/claude/build-review.json of the worktree"
check "$(js "$R" 'd["branch"], d["repo"] == sys.argv[3], d["project"], d["worktree"] == sys.argv[4], len(d["rounds"])' "$(cd "$T/repo" && pwd -P)" "$(cd "$W" && pwd -P)")" "('claude/laptop/2026-10-30-demo', True, 'repo', True, 1)" "  naming the branch, the main checkout, review-gate's project and repo keys"
check "$(js "$R" 'sorted(d["rounds"][0])')" "['at', 'check', 'fixed', 'found', 'left', 'note', 'open_s1', 'raised', 'reviewers', 'round', 'tip']" "  a round's shape"
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
git init -q -b main "$T/cv"; printf 'a = 1\n' > "$T/cv/a.py"; git -C "$T/cv" add a.py; git -C "$T/cv" commit -q -m init
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

echo "== refusals"
out=$(br show "$T/nowhere"); check "$?" "2" "a path that is no checkout: exit 2"
has "$out" "is no git checkout" "  saying so"
out=$(br round "$W" --found -1 --fixed 0); check "$?" "2" "a negative count: a usage error"
out=$(env -u CLAUDE_CODE_SESSION_ID "$B/build-review" round "$W" --found 0 --fixed 0 --check green 2>&1); check "$?" "2" "no session id: refused, never read as one shared session"
has "$out" "no CLAUDE_CODE_SESSION_ID" "  saying so"

echo
[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
