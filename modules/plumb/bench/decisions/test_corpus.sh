#!/usr/bin/env bash
# Tests for corpus.py on D10's shape: the Recommended line is the recommendation, the Answer
# block is the owner's (empty = unanswered), and an answer in the doc's own commit is still the owner's (F12).
# A fixture repo under a temporary root stands in for ~/projects. No network, no model.
#                                              bash modules/plumb/bench/decisions/test_corpus.sh
set -u
H="$(cd "$(dirname "$0")" && pwd)"
# left unresolved on purpose: /var is /private/var to git, and corpus.py must cope
T=$(mktemp -d) || exit 1; trap 'rm -rf "$T"' EXIT
fails=0
check() { if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3: expected [$2] got [$1]"; fails=$((fails+1)); fi; }

R="$T/root/overlay"; mkdir -p "$R/docs"
g() { git -C "$R" -c user.name=t -c user.email=t@t "$@"; }
g init -q
D="$R/docs/answers-2026-10-04.md"
cat > "$D" <<'EOF'
# Fixture — design

## Decisions

- **D1 — Pick the format.** Two ways to go.
  A — answer on the arrow line
  B — answer in the block under it
  ➤ Recommended: B
  ➤ Answer:

- **D2 — Ship this week?** Plain yes or no.
  ➤ Recommended: yes, Friday.
  ➤ Answer:

- **D3 — Which store?** Answered in the doc's own commit.
  A — the file
  B — the database
  ➤ Recommended: B
  ➤ Answer:
  A - mine, typed before the first commit
  and kept on two lines

- **D4 — Take the button?**
  ➤ Recommended: keep both
  ➤ Answer:

- **D5 — Left alone.**
  ➤ Recommended: wait
  ➤ Answer:

- **D6 — Old shape still reads.**
  ➤ Answer: yes, pre-filled.

- **D7 — Take the button on a no?**
  ➤ Recommended: no, skip it
  ➤ Answer:
  = recommended

- **D8 — A letter typed lowercase.**
  A — the file
  B — the database
  ➤ Recommended: B — the database
  ➤ Answer:
  b

- **D9 — An ok to a no.**
  ➤ Recommended: not this week
  ➤ Answer:
  ok

- **D10 — Yes, then the other letter.**
  A — the file
  B — the database
  ➤ Recommended: A
  ➤ Answer:
  Yes, B

- **D11 — A word that starts with the letter.**
  A — the file
  B — the database
  ➤ Recommended: B
  ➤ Answer:
  But I would rather keep the file

- **D12 — Agreement in other words.**
  ➤ Recommended: ship Friday
  ➤ Answer:
  lgtm

- **D13 — The letter, a note below it.**
  A — the file
  B — the database
  ➤ Recommended: B (D1). D later
  ➤ Answer:
  B
  with a note on naming

- **D14 — A yes to a no.**
  ➤ Recommended: no, skip it
  ➤ Answer:
  yes

- **D15 — Accepted in bulk.**
  ➤ Recommended: B
  ➤ Answer:

## Open feedback
EOF
cat > "$R/docs/runon-2026-10-04.md" <<'EOF'
# Fixture — a D-list that runs into prose

- **D20 — No heading after the list.**
  ➤ Recommended: B
  ➤ Answer:

That is all for now; the next step is the build.
EOF
g add -A; g commit -qm doc
perl -0pi -e 's/(➤ Recommended: B\n  ➤ Answer:\n)(\n- \*\*D2)/$1  B\n$2/; s/(yes, Friday\.\n  ➤ Answer:\n)/$1  yes, but Monday?\n/; s/(keep both\n  ➤ Answer:\n)/$1  = recommended\n/; s/(Accepted in bulk\.\*\*\n  ➤ Recommended: B\n  ➤ Answer:\n)/$1  = recommended (accept all)\n/' "$D"
g commit -qam answers

CORPUS_ROOT="$T/root" python3 "$H/corpus.py" --bench "$T/bench" > "$T/out" 2>&1
rc=$?; [ "$rc" = 0 ] || tail -5 "$T/out"
check "$rc" "0" "corpus.py runs on the fixture"
py() { python3 -c "import json,sys; d={json.loads(l)['id']: json.loads(l) for l in open('$T/bench/corpus.jsonl')}; $1"; }
check "$(py 'print(sorted(d, key=lambda k: int(k[1:])))')" "['D1', 'D2', 'D3', 'D4', 'D5', 'D6', 'D7', 'D8', 'D9', 'D10', 'D11', 'D12', 'D13', 'D14', 'D15']" "every item, the new shape included, the run-on one left out"
check "$(grep -c "answer-runs-on': 1" "$T/out")" "1" "D20: prose below an unclosed list is not read as the owner's answer, and the skip is counted"
check "$(py 'print(d["D10"]["kind"], d["D11"]["kind"], d["D12"]["kind"], d["D13"]["kind"], d["D14"]["kind"])')" "overruled overruled accepted-answered accepted+note overruled" "D10–D14: yes-then-B overrules A, a word starting with B is no pick, lgtm agrees, B with a note, a yes to a no"
check "$(py 'print(d["D1"]["y_touched"], d["D5"]["y_touched"], d["D1"]["shape"], "shape" in d["D6"])')" "1 0 new False" "touched = the owner wrote anything; D10 rows carry shape, old rows do not"
check "$(cd "$H" && python3 -c "import json,questions; print(questions.state_for(json.loads(open('$T/bench/corpus.jsonl').readline()))['context']['how_answers_work'][:60])")" "an agent wrote the decision and recorded its recommendation " "questions.py words a D10 row's state as an empty box"
check "$(py 'print(d["D7"]["kind"], d["D8"]["kind"], d["D9"]["kind"])')" "accepted-answered accepted-answered accepted-answered" "D7–D9: the button on a no, a lowercase letter, an ok to a no all agree"
check "$(py 'print(d["D1"]["recommendation"], "|", d["D1"]["final"], "|", d["D1"]["kind"], d["D1"]["known"])')" "B | B | accepted-answered 1" "D1: the recommended letter alone — answered, agreed"
check "$(py 'print(d["D2"]["kind"], d["D2"]["y_touched"], d["D2"]["y_override"])')" "accepted+question 1 0" "D2: a yes with a question"
check "$(py 'print(d["D3"]["recommendation"], "|", d["D3"]["final"].replace(chr(10), "/"))')" "B | A - mine, typed before the first commit/and kept on two lines" "D3: recommendation and answer apart, both lines kept"
check "$(py 'print(d["D3"]["kind"], d["D3"]["y_override"], d["D3"]["wait_hours"])')" "overruled 1 0.0" "D3: an answer in the doc's own commit is the owner's (F12), another letter overrules"
check "$(py 'print(d["D4"]["kind"], d["D4"]["bulk"])')" "accepted-answered 0" "D4: the form's = recommended"
check "$(py 'print(d["D15"]["kind"], d["D15"]["y_override"], d["D15"]["bulk"])')" "accepted-answered 0 1" "D15: Accept all's marker agrees, and reads as bulk (2026-10-04)"
check "$(py 'print(d["D5"]["final"] == "", d["D5"]["kind"], d["D5"]["known"])')" "True accepted-silent 0" "D5: an empty block is unanswered"
check "$(py 'print(d["D6"]["recommendation"], "|", d["D6"]["kind"])')" "yes, pre-filled. | accepted-silent" "D6: the old shape as before"

# rename S2 (M25): a reply marked `**Launched**` settles an item like an old doc's `**Landed**`
check "$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import corpus; print(bool(corpus.DONE_RE.match("  > **Landed** in #5")), bool(corpus.DONE_RE.match("  > **Launched** in #6")))' "$H")" \
  "True True" "DONE_RE: Landed and Launched both mark a reply"
echo
if [ "$fails" = 0 ]; then echo "all green"; else echo "$fails failing"; exit 1; fi
