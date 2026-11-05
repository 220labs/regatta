#!/usr/bin/env bash
# asks' suite (evolve S1): the sieve, the gate calls per dimension and repo (a stand-in claude that answers by marker words),
# the ledgers holding no text, themes and the repeat share, the matcher with and without findings, the
# fence through the real week-digest, a gate that is off or failing, the baseline replay over a made-up
# corpus, `numbers`. Scratch HOME and state; no network, no real transcript or prompt read.
#   bash modules/plumb/tests/asks.sh
set -u
D="$(cd "$(dirname "$0")/.." && pwd -P)"
A="$D/bin/asks"
T="$(mktemp -d)"; T="$(cd "$T" && pwd -P)"
trap 'rm -rf "$T"' EXIT
for v in $(env | sed -n 's/^\(REGATTA[A-Za-z0-9_]*\)=.*/\1/p; s/^\(CLAUDE[A-Za-z0-9_]*\)=.*/\1/p; s/^\(GATE[A-Za-z0-9_]*\)=.*/\1/p; s/^\(ASKS[A-Za-z0-9_]*\)=.*/\1/p'); do unset "$v"; done
export HOME="$T/u" REGATTA_CONFIG="$T/config" ACCOUNTS_FILE="$T/no-accounts.json" CLAUDE_REPOS_JSON="$T/repos.json"
export ASKS_STATE="$T/state" ASKS_FINDINGS="$T/findings" GATE_LOG="$T/gate.jsonl" JEV_LOG="$T/jev.jsonl"
mkdir -p "$HOME" "$REGATTA_CONFIG"
fails=0
check() {
  if [ "$1" = "$2" ]; then echo "  ok  $3"; else echo "  FAIL $3"; echo "       got:  $1"; echo "       want: $2"; fails=$((fails + 1)); fi
}
j() { python3 -c "import json,sys; d=json.load(sys.stdin); print($1)"; }

# a stand-in claude -p: reads the gate's prompt, answers per marker word (ASKWORD -> system, QWORD -> question,
# FEATWORD -> feature, EVIDWORD -> E, MATCHWORD -> anticipated), and costs $0.01 a call
cat > "$T/claude" <<'PY'
#!/usr/bin/env python3
import json, os, re, sys
p = sys.stdin.read()
if "Group the slugs that name the SAME need" in p:   # the generate row evolve.theme, the merge pass
    names = [l.split(" (")[0] for l in p.splitlines() if re.match(r"^[a-z0-9-]+ \([0-9]+\)$", l)]
    pairs = [["digest-ledger", "weekly-digest-ledger"], ["empty-page", "blank-page-context"]]
    groups = [names] if os.environ.get("STUB_BROAD") else [g + (["ghost-slug"] if os.environ.get("STUB_GHOST") else []) for g in pairs]
    print(json.dumps({"structured_output": {"groups": "x" if os.environ.get("STUB_NOGROUPS") else groups}, "total_cost_usd": 0.02, "is_error": False}))
    sys.exit(0)
items = {}
on = False
for l in p.splitlines():
    if l.startswith("Items, one per line"):
        on = True
        continue
    if on and ": " in l and not l.startswith("Reply with"):
        i, t = l.split(": ", 1)
        items[i] = t
def slug(t):
    return "digest-ledger" if "digest ledger" in t else "empty-page" if "QWORD" in t else "other-thing"
if "Name each item's THEME" in p:   # the generate row evolve.theme
    print(json.dumps({"structured_output": {i: slug(t) for i, t in items.items()}, "total_cost_usd": 0.02, "is_error": False}))
    sys.exit(0)
task = [l for l in p.splitlines() if l.startswith("Task: ")][0]
def one(t):
    if "owner asked for the change" in task:
        return "anticipated" if "MATCHWORD" in t and "FINDINGS: none" not in t else ("M2" if "MISSWORD" in t else "J")
    if "What does this prompt target" in task:
        return "system" if "ASKWORD" in t else "question" if "QWORD" in t else "none"
    if "What kind" in task:
        return "feature" if "FEATWORD" in t else "bug"
    if "Which level" in task:
        return "KL"
    return "E" if "EVIDWORD" in t and not os.environ.get("STUB_NO_EVID") else "J"
print(json.dumps({"structured_output": {i: one(t) for i, t in items.items()}, "total_cost_usd": 0.01, "is_error": False}))
PY
chmod +x "$T/claude"
export CLAUDE_BIN="$T/claude"

# a digest by hand: the machine's, an answer, two sessions raising one theme, a question, a task
day() { python3 -c "import datetime as d; print((d.date.today()-d.timedelta(days=$1)).isoformat())"; }
mk_digest() {  # mk_digest <file>: sessions on days -3 (s1), -2 (s2), -1 (s3)
  python3 - "$1" "$(day 3)" "$(day 2)" "$(day 1)" <<'PY'
import json, sys
f, d3, d2, d1 = sys.argv[1:]
def p(day, text, h="10"): return {"ts": f"{day}T{h}:00:00.000Z", "text": text, "marked": False}
d = {"generated": "x", "days": 7, "scope": None, "fenced": {"sessions": 2}, "sessions": [
  {"project": "regatta", "session": "s1aaaaaa-1", "title": None, "start": d3 + "T10:00:00.000Z", "source": "live", "prompts": [
     p(d3, "Unattended run for the brief in docs/handoff/x.md, read first"),
     p(d3, "ASKWORD we should make the dream remember corrections about the weekly digest ledger FEATWORD EVIDWORD"),
     p(d3, "yes", "11"), p(d3, "fix the typo in the readme", "12")]},
  {"project": "regatta", "session": "s2bbbbbb-2", "title": None, "start": d2 + "T10:00:00.000Z", "source": "live", "prompts": [
     p(d2, "ASKWORD again, the dream must remember corrections about the weekly digest ledger, I told you")]},
  {"project": "sysrepo", "session": "s3cccccc-3", "title": None, "start": d1 + "T10:00:00.000Z", "source": "archive", "prompts": [
     p(d1, "QWORD why is the page showing zero context for these decisions"), p(d1, "status?", "11")]}]}
json.dump(d, open(f, "w"))
PY
}
mk_digest "$T/digest.json"

echo "the sieve alone (--no-model): machine out, labels from the heuristics, no gate call"
out=$("$A" run --digest "$T/digest.json" --no-model --no-overrules); check $? 0 "exit 0"
check "$(echo "$out" | grep -o '^asks: [0-9]* new owner prompts (1 machine, 2 confidential sessions not opened)')" \
  "asks: 6 new owner prompts (1 machine, 2 confidential sessions not opened)" "five owner prompts, the launcher's prompt not one of them"
check "$(python3 -c 'import json,sys; r=[json.loads(l) for l in open(sys.argv[1])]; print(len(r), sorted({x["by"] for x in r}), sum(x["target"]=="system" for x in r))' "$ASKS_STATE/asks.jsonl")" \
  "6 ['sieve'] 2" "six rows, all by the sieve; two asks (the ask and the correction)"
rm -rf "$ASKS_STATE"

echo "the model path: a call per dimension and repo, themes, ledgers without text"
out=$("$A" run --digest "$T/digest.json" --no-overrules); check $? 0 "exit 0"
check "$(echo "$out" | grep -o 'labelled by model')" "labelled by model" "labelled by the gate"
check "$(python3 - "$ASKS_STATE/asks.jsonl" <<'PY'
import json, sys
r = [json.loads(l) for l in open(sys.argv[1])]
s = [x for x in r if x["target"] == "system"]
print(len(r), len(s), sorted({x["detect"] for x in s}), sorted({x["kind"] for x in s}), len({x["theme"] for x in r if x.get("theme")}),
      [x["target"] for x in r if x["session"] == "s3cccccc"].count("question"))
PY
)" "6 2 ['E', 'J'] ['bug', 'feature'] 2 1" "6 rows; 2 asks; kind and detect from the calls; the asks and the question in two themes; the gap question labelled"
check "$(grep -l 'ASKWORD\|QWORD\|digest ledger\|readme' "$ASKS_STATE"/* 2>/dev/null | wc -l | tr -d ' ')" 0 "no file of the ledger holds a word of the owner's"
check "$(python3 -c 'import json,sys; r=[json.loads(l) for l in open(sys.argv[1])][-1]; print(r["gate_calls"], r["cost_usd"], r["labelled_by"])' "$ASKS_STATE/runs.jsonl")" "9 0.1 model" \
  "the run log: four classify calls for each of the two repos and the theme call, the spend"
check "$(python3 -c 'import json,sys; t=json.load(open(sys.argv[1])); v=[x for x in t.values() if x["count"]==2][0]; print(len(t), v["count"], sorted(v["sessions"]), v["shipped"])' "$ASKS_STATE/themes.json")" \
  "2 2 ['s1aaaaaa', 's2bbbbbb'] None" "the theme ledger: the asks' theme in two sessions, the question's apart"
check "$(python3 -c 'import json,sys; print(sorted(json.load(open(sys.argv[1]))))' "$ASKS_STATE/themes.json")" "['digest-ledger', 'empty-page']" \
  "the themes are the model's slugs, not words"
out=$("$A" run --digest "$T/digest.json" --no-overrules); check "$(echo "$out" | grep -o '^asks: 0 new')" "asks: 0 new" "a second run adds nothing (ids are stable)"
check "$(wc -l < "$GATE_LOG" | tr -d ' ')" 8 "  and calls the gate no more"
n=$("$A" numbers --json)
check "$(echo "$n" | j '(d["asks"], d["themes"], d["owner_prompts"], d["repeat_share"], d["detectable_share"], d["judgement_share"], d["recall"])')" \
  "(2, 1, 6, 50, 50, 50, 'no findings yet')" "numbers: 2 asks in 1 theme of 6 prompts, half repeat, recall says no findings yet"
check "$(echo "$n" | j 'd["asks_per_100"]')" 33.3 "  asks per 100 owner prompts"
"$A" ship $(python3 -c 'import json,sys; print(list(json.load(open(sys.argv[1])))[0])' "$ASKS_STATE/themes.json") "PR 1"; check $? 0 "ship records a mechanism for a theme"
check "$(python3 -c 'import json,sys; print(list(json.load(open(sys.argv[1])).values())[0]["shipped"]["ref"])' "$ASKS_STATE/themes.json")" "PR 1" "  in the theme ledger"
"$A" ship nope "x" > /dev/null 2>&1; check $? 1 "ship of an unknown theme: exit 1"
rm -rf "$ASKS_STATE"; : > "$GATE_LOG"

echo "the matcher: no findings yet, then findings"
out=$("$A" run --digest "$T/digest.json" --no-overrules); check "$(echo "$out" | grep -o 'match: no findings yet')" "match: no findings yet" "no findings: said, and no call spent"
check "$(wc -l < "$GATE_LOG" | tr -d ' ')" 8 "  eight calls, none for the matcher"
rm -rf "$ASKS_STATE"; : > "$GATE_LOG"
mkdir -p "$ASKS_FINDINGS"
printf '[{"id": "F1", "date": "%s", "need": "MATCHWORD the dream should remember corrections about the weekly digest ledger", "intervention": "add a memory check", "status": "routed"},\n {"id": "F9", "date": "%s", "need": "weekly digest ledger corrections", "intervention": "later than the ask", "status": "proposed"}]\n' "$(day 6)" "$(day 0)" > "$ASKS_FINDINGS/f.json"
out=$("$A" run --digest "$T/digest.json" --no-overrules); check "$(echo "$out" | grep -o 'match: [0-9]* matched')" "match: 1 matched" "findings: the one detectable ask is matched"
check "$(python3 -c 'import json,sys; r=[x for x in map(json.loads, open(sys.argv[1])) if x.get("match")]; print(len(r), r[0]["match"]["label"], r[0]["match"].get("finding"), r[0]["match"].get("lead_days"))' "$ASKS_STATE/asks.jsonl")" \
  "1 anticipated F1 -3" "anticipated by F1, lead time -3: the finding's day minus the ask's (the later finding F9 is no candidate)"
check "$("$A" numbers --json | j '(d["recall"], d["lead_days"])')" "(100, -3.0)" "numbers: recall and lead time now measured (negative: the loop was first)"
check "$(wc -l < "$GATE_LOG" | tr -d ' ')" 9 "  one more call, for the matcher"
rm -rf "$ASKS_STATE" "$ASKS_FINDINGS"; : > "$GATE_LOG"

echo "the gate off or failing: the sieve's week, said, never a crash"
out=$(GATE_EVOLVE_ASK_PROVIDER=off "$A" run --digest "$T/digest.json" --no-overrules); check $? 0 "a row that is off: exit 0"
check "$(echo "$out" | grep -o 'labelled by sieve (evolve.ask is off)')" "labelled by sieve (evolve.ask is off)" "  says so"
rm -rf "$ASKS_STATE"
out=$(CLAUDE_BIN=/usr/bin/false "$A" run --digest "$T/digest.json" --no-overrules); check $? 0 "a claude that fails: exit 0"
check "$(echo "$out" | grep -c 'labelled by sieve (evolve.ask:')" 1 "  the sieve's labels, the error named"
check "$("$A" numbers --json | j 'd["labelled_by_sieve"]')" 6 "  and numbers counts the sieve-labelled rows"
rm -rf "$ASKS_STATE"

echo "a guarded repo: refused at the gate per repo, its prompts keep the sieve's labels, the rest go on"
mkdir -p "$REGATTA_CONFIG/regatta"; echo sysrepo > "$REGATTA_CONFIG/regatta/guarded"; : > "$GATE_LOG"
out=$("$A" run --digest "$T/digest.json" --no-overrules); check $? 0 "exit 0"
check "$(python3 -c 'import json,sys; r=[json.loads(l) for l in open(sys.argv[1])]; print(sorted({(x["project"], x["by"]) for x in r}))' "$ASKS_STATE/asks.jsonl")" \
  "[('regatta', 'model'), ('sysrepo', 'sieve')]" "  the guarded repo's rows by the sieve, the other's by the model"
check "$(python3 -c 'import json,sys; print(sorted({json.loads(l)["source"] for l in open(sys.argv[1])}))' "$GATE_LOG")" "['regatta']" \
  "  the gate saw the open repo only, named as the source"
check "$(echo "$out" | grep -c 'refused')" 1 "  the refusal named in the run's line"
rm -f "$REGATTA_CONFIG/regatta/guarded"; rm -rf "$ASKS_STATE"; : > "$GATE_LOG"

echo "--dry-run writes nothing; numbers before any run says so"
"$A" run --digest "$T/digest.json" --no-model --no-overrules --dry-run > /dev/null; check "$(ls "$ASKS_STATE" 2>/dev/null | wc -l | tr -d ' ')" 0 "dry run: no state"
check "$("$A" numbers)" "asks: not measured — no pass has run yet (asks run)" "numbers with no pass: not measured, with the reason"

echo "through the real week-digest: a confidential scope is counted, never opened"
P="$T/u/projects"; L="$T/u/.claude/projects"
mkdir -p "$P/sec" "$P/open" "$P/transcripts"
printf '{"repos": {"sec": {}, "open": {}},\n "scopes": {"node": {"file": "n", "repos": ["sec"], "confidential": true},\n  "pub": {"file": "p", "repos": ["open"]}}}\n' > "$CLAUDE_REPOS_JSON"
slug() { printf '%s' "$1" | sed 's/[^A-Za-z0-9]/-/g'; }
NOW=$(python3 -c 'import datetime as d; print(d.datetime.now(d.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z"))')
mkdir -p "$L/$(slug "$P/sec")" "$L/$(slug "$P/open")"
printf '{"type": "user", "origin": {"kind": "human"}, "sessionId": "sec-1", "timestamp": "%s", "message": {"content": "ASKWORD SECRETWORD in a confidential scope"}}\n' "$NOW" > "$L/$(slug "$P/sec")/a.jsonl"
printf '{"type": "user", "origin": {"kind": "human"}, "sessionId": "open-2", "timestamp": "%s", "message": {"content": "ASKWORD we should add a visible open scope thing"}}\n' "$NOW" > "$L/$(slug "$P/open")/b.jsonl"
out=$("$A" run --no-overrules); check "$(echo "$out" | grep -o '^asks: 1 new owner prompts (0 machine, 1 confidential sessions not opened)')" \
  "asks: 1 new owner prompts (0 machine, 1 confidential sessions not opened)" "one open prompt read, one confidential session counted"
check "$(grep -c SECRETWORD "$ASKS_STATE"/* | grep -vc ':0')" 0 "  nothing of the confidential session in the ledger"
check "$(grep -c SECRETWORD "$GATE_LOG")" 0 "  nor at the gate"
rm -rf "$ASKS_STATE"
out=$(CLAUDE_REPOS_JSON="$T/none.json" "$A" run --no-overrules --no-model); check "$(echo "$out" | grep -o '^asks: 2 new')" "asks: 2 new" "no registry at all: both read (as week-digest does)"
rm -rf "$ASKS_STATE"

echo "the overrule ledger: counts and ids from interruptions, never a question"
out=$("$A" run --digest "$T/digest.json" --no-model); check "$(echo "$out" | grep -o 'overrules: [0-9]*')" "overrules: 0" "no answers in a scratch HOME: zero rows, no error"
check "$([ -f "$ASKS_STATE/overrules.jsonl" ] && echo yes)" yes "  the ledger file exists"
rm -rf "$ASKS_STATE"

echo "baseline: a made-up corpus through the sieve and the stand-in gate"
C="$T/corpus"; mkdir -p "$C"
printf '0\tsysrepo\t10-01\tsa\tASKWORD we should add FEATWORD to the weekly digest ledger EVIDWORD\n1\tsysrepo\t10-02\tsb\tASKWORD we should add FEATWORD to the weekly digest ledger again EVIDWORD\n2\tregatta\t10-02\tsb\tstatus?\n3\tregatta\t10-03\tsc\tQWORD why is the page empty here\n4\tregatta\t10-03\tsc\tfix the typo in the readme\n' > "$C/core.tsv"
printf '# id|class|level|kind|detect|theme|note\n0|I|KL|feat|E|digest-ledger|\n1|I|KL|feat|E|digest-ledger|\n3|Q|UX|||empty-page|\n' > "$C/labels_core.txt"
out=$("$A" baseline --corpus "$C"); check $? 0 "the sieve alone: exit 0"
check "$(echo "$out" | head -1)" "baseline corpus: 5 owner prompts, 2 hand-labelled improvement asks, 1 gap questions (counts only; the text is never printed)" "the corpus counted"
check "$(echo "$out" | grep -c 'ASKWORD\|status?')" 0 "  no prompt text printed"
out=$("$A" baseline --corpus "$C" --model); check $? 0 "with --model: exit 0"
check "$(echo "$out" | grep -o '^  target   3-way [0-9]* % ([0-9]*/[0-9]*)')" "  target   3-way 100 % (5/5)" "the target dimension agrees with the stand-in"
check "$(echo "$out" | grep -o '^  kind     [0-9]* % ([0-9]*/[0-9]*)')" "  kind     100 % (2/2)" "  kind"
check "$(echo "$out" | grep -o '^  detect   [0-9]* % ([0-9]*/[0-9]*)')" "  detect   100 % (2/2)" "  detectability"
check "$(echo "$out" | grep -o 'pairwise same-theme precision [0-9]* %')" "pairwise same-theme precision 100 %" "  the theme signature groups the two asks"
check "$(echo "$out" | grep -o '2 session-theme asks (hand: 2); repeating a theme 50 %')" "2 session-theme asks (hand: 2); repeating a theme 50 %" "  one theme in two sessions: two asks, the later one a repeat"
"$A" baseline --corpus "$T/nowhere" > /dev/null 2>&1; check $? 2 "no corpus: exit 2"

echo "knowledge-numbers reads the ledger (its asks_numbers)"
"$A" run --digest "$T/digest.json" --no-model --no-overrules > /dev/null
check "$(python3 - "$D/bin/knowledge-numbers" <<'PY'
import sys
from importlib.machinery import SourceFileLoader
kn = SourceFileLoader("kn", sys.argv[1]).load_module()
n = kn.asks_numbers(None)
print(n["measured"], n["asks"], n["owner_prompts"])
print(kn.asks_numbers("pub"))
print(kn.asks_numbers(None, "/nowhere/asks"))
PY
)" "True 2 6
{'measured': False, 'why': 'not run under --scope'}
{'measured': False, 'why': 'bin/asks is not installed or did not answer'}" "asks_numbers: the ledger's numbers; under --scope and with no tool, not measured, saying why"
rm -rf "$ASKS_STATE"

echo "evolve S11: the theme ledger's merge pass (one evolve.theme call a month over the slugs)"
cat > "$T/mkledger.py" <<'PY'
import json, os, sys
state, n_extra = sys.argv[1], int(sys.argv[2])
import datetime as d
day = lambda k: (d.date.today() - d.timedelta(days=k)).isoformat()
os.makedirs(state, exist_ok=True)
def th(sessions, first, last):
    return {"sig": ["aaaaaa"], "level": "KL", "kind": "feature", "sessions": sessions, "first": first, "last": last,
            "shipped": None, "count": len(sessions)}
themes = {
  "weekly-digest-ledger": th({"s1": day(9), "s2": day(8), "s3": day(7)}, {"session": "s1", "date": day(9)}, {"session": "s3", "date": day(7)}),
  "digest-ledger": th({"s4": day(3)}, {"session": "s4", "date": day(3)}, {"session": "s4", "date": day(3)}),
  "empty-page": th({"s5": day(5), "s6": day(4)}, {"session": "s5", "date": day(5)}, {"session": "s6", "date": day(4)}),
  "blank-page-context": th({"s7": day(2)}, {"session": "s7", "date": day(2)}, {"session": "s7", "date": day(2)}),
  "other-thing": th({"s8": day(1)}, {"session": "s8", "date": day(1)}, {"session": "s8", "date": day(1)}),
}
themes["digest-ledger"]["shipped"] = {"ref": "PR 9", "on": day(1)}
for i in range(n_extra):
    themes["extra-need-%02d" % i] = th({"x%d" % i: day(6)}, {"session": "x%d" % i, "date": day(6)}, {"session": "x%d" % i, "date": day(6)})
json.dump(themes, open(os.path.join(state, "themes.json"), "w"))
rows = []
for t, v in themes.items():
    for sess, dd in v["sessions"].items():
        rows.append({"id": "i%s%s" % (t[:4], sess), "date": dd, "ts": dd + "T10:00:00.000Z", "week": "2026-W01", "project": "regatta",
                     "session": sess, "target": "system", "kind": "feature", "level": "KL", "detect": "E", "theme": t, "by": "model"})
rows += [{"id": "p%d" % i, "date": day(1), "ts": day(1) + "T09:00:00.000Z", "week": "2026-W01", "project": "regatta", "session": "z%d" % i,
          "target": "none", "by": "model"} for i in range(30)]
open(os.path.join(state, "asks.jsonl"), "w").write("".join(json.dumps(r) + "\n" for r in rows))
PY
rm -rf "$ASKS_STATE"; python3 "$T/mkledger.py" "$ASKS_STATE" 0; : > "$GATE_LOG"
check "$("$A" numbers --days 30 --json | j '(d["asks"], d["themes"], d["repeat_share"])')" "(8, 5, 38)" "before the pass: eight session-themes under five slugs, 38 % repeating (the model's slugs for one need differ)"
out=$("$A" merge --dry-run); check "$(echo "$out" | grep -c '^theme merge: 5 slugs, 5 would be offered to one evolve.theme call \[dry run: no call made, nothing written\]$')" 1 \
  "--dry-run: what one call would be offered; no paid call, so no spend goes unlogged"
check "$(ls "$ASKS_STATE" | tr '\n' ' ')" "asks.jsonl themes.json " "  and no file made"
out=$("$A" merge); check $? 0 "merge: exit 0"
check "$(echo "$out" | grep -c '^theme merge: 5 slugs, 2 groups folded 2 slugs')" 1 "  one line, the slugs and groups counted"
check "$(python3 -c 'import json,sys; t=json.load(open(sys.argv[1])); m=json.load(open(sys.argv[2])); print(sorted(t), sorted(m.items()), sorted(t["weekly-digest-ledger"]["sessions"]), t["weekly-digest-ledger"]["count"], t["weekly-digest-ledger"]["shipped"]["ref"])' "$ASKS_STATE/themes.json" "$ASKS_STATE/theme-merges.json")" \
  "['empty-page', 'other-thing', 'weekly-digest-ledger'] [('blank-page-context', 'empty-page'), ('digest-ledger', 'weekly-digest-ledger')] ['s1', 's2', 's3', 's4'] 4 PR 9" \
  "the keeper is the slug most sessions raised; its record takes the folded one's sessions, count and shipped mark; the map names old -> kept"
cat > "$T/fold.py" <<'PY'
import sys
from importlib.machinery import SourceFileLoader
a = SourceFileLoader("asks", sys.argv[1]).load_module()
keep = {"sessions": {"s1": "2026-11-01"}, "shipped": {"ref": "PR 20", "on": "2026-11-01"}}
a.fold_theme(keep, {"sessions": {"s2": "2026-09-01"}, "shipped": {"ref": "PR 9", "on": "2026-09-10"}})
print(keep["shipped"]["ref"], keep["count"])
PY
check "$(python3 "$T/fold.py" "$A")" "PR 20 2" "  two shipped marks: the newest stands (recurrence counts from the newest mechanism)"
check "$("$A" numbers --days 30 --json | j '(d["asks"], d["themes"], d["repeat_share"], d["theme_merges"])')" "(8, 3, 62, 2)" "numbers follows the map: eight session-themes under three themes, the repeats now 5 of 8"
check "$(python3 -c 'import json,sys; r=[json.loads(l) for l in open(sys.argv[1])]; print(len(r), r[-1]["status"], r[-1]["cost_usd"], r[-1]["folded"])' "$ASKS_STATE/theme-merges.jsonl")" "1 ok 0.02 2" "the merge log: one row, its cost"
check "$("$A" numbers --days 30 --json | j 'd["cost_week_usd"] >= 0.02')" "True" "  numbers counts the merge's spend"
check "$(grep -c 'ASKWORD\|digest ledger' "$ASKS_STATE"/* | grep -vc ':0')" 0 "  no word of the owner's in any file"
out=$("$A" merge); check "$(echo "$out" | grep -o '^theme merge: not due')" "theme merge: not due" "a second pass within the month: not due, no call"
check "$(wc -l < "$GATE_LOG" | tr -d ' ')" 0 "  (the merge call is the generate row's own, not a classify)"
out=$("$A" merge --force); check "$(echo "$out" | grep -c '^theme merge: 3 slugs, 0 groups folded 0 slugs')" 1 "--force asks again: the folded slugs are gone from the list, nothing left to group"
rm -rf "$ASKS_STATE"; python3 "$T/mkledger.py" "$ASKS_STATE" 0
out=$(STUB_GHOST=1 "$A" merge); check "$(echo "$out" | grep -c 'folded 2 slugs')" 1 "a slug the call invented is ignored, the real ones folded"
check "$(python3 -c 'import json,sys; print(sorted(json.load(open(sys.argv[1]))))' "$ASKS_STATE/theme-merges.json")" "['blank-page-context', 'digest-ledger']" "  and the map holds no invented slug"
rm -rf "$ASKS_STATE"; python3 "$T/mkledger.py" "$ASKS_STATE" 34
out=$(STUB_BROAD=1 "$A" merge); check "$(echo "$out" | grep -o '0 groups folded 0 slugs (1 held as too broad)')" "0 groups folded 0 slugs (1 held as too broad)" "one group of every slug is held, never folded"
check "$(ls "$ASKS_STATE" | tr '\n' ' ')" "asks.jsonl theme-merges.json theme-merges.jsonl themes.json " "  a held pass folds nothing: the ledger and an empty map as they were, its log row written"
rm -rf "$ASKS_STATE"; python3 "$T/mkledger.py" "$ASKS_STATE" 0
out=$(GATE_EVOLVE_THEME_PROVIDER=off "$A" merge); check "$(echo "$out" | grep -o 'not run (evolve.theme is off)')" "not run (evolve.theme is off)" "a row that is off: not run, said, no call"
check "$(ls "$ASKS_STATE" | tr '\n' ' ')" "asks.jsonl themes.json " "  and nothing written"
out=$(CLAUDE_BIN=/usr/bin/false "$A" merge); check "$(echo "$out" | grep -c 'the call failed')" 1 "a claude that fails: the pass is said failed"
check "$(python3 -c 'import json,sys; r=[json.loads(l) for l in open(sys.argv[1])]; print(r[-1]["status"])' "$ASKS_STATE/theme-merges.jsonl") $("$A" merge | grep -o 'not due')" "failed not due" "  and tried again in a week, not at once"
rm -f "$ASKS_STATE/theme-merges.jsonl"; CLAUDE_BIN=/usr/bin/false "$A" merge > /dev/null
check "$("$A" merge | grep -c 'not due (the last attempt failed on .*, tried again after 7 days')" 1 "  a first pass that failed: not due says the attempt failed, never that a pass worked"
cat > "$T/order.py" <<'PY'
import sys
from importlib.machinery import SourceFileLoader
a = SourceFileLoader("asks", sys.argv[1]).load_module()
seen = []
a.write_json = lambda path, obj: seen.append(path.name)
a.merge_themes = lambda gate, themes, merges, *rest: (themes, merges, {"called": True, "slugs": 2, "groups": 1, "folded": 1, "held": 0})
a.write_jsonl = lambda path, rows: None
a.do_merge(type("G", (), {"cost": 0.0, "calls": 1})())
print(seen)
PY
check "$(python3 "$T/order.py" "$A")" "['theme-merges.json', 'themes.json']" "the map is written before the folded ledger: a failure between the two leaves slugs the map still folds"
out=$(GATE_EVOLVE_THEME_PROVIDER=codex "$A" merge --force 2>&1); check "$? $(echo "$out" | grep -c 'the call failed') $(echo "$out" | grep -c Traceback)" "0 1 0" "a row naming another provider: the pass is said failed, never a traceback"
rm -rf "$ASKS_STATE"; python3 "$T/mkledger.py" "$ASKS_STATE" 0
"$A" merge > /dev/null
out=$("$A" run --digest "$T/digest.json" --no-overrules)
check "$(python3 -c 'import json,sys; t=json.load(open(sys.argv[1])); print("digest-ledger" in t, "weekly-digest-ledger" in t, t["weekly-digest-ledger"]["count"])' "$ASKS_STATE/themes.json")" "False True 6" \
  "  a new ask the model names with a folded slug lands on the keeper (the stand-in says digest-ledger twice, in two new sessions)"
rm -rf "$ASKS_STATE"; python3 "$T/mkledger.py" "$ASKS_STATE" 20
out=$("$A" run --digest "$T/digest.json" --no-overrules); check "$(echo "$out" | grep -c '; theme merge: 25 slugs, ')" 1 "run makes the pass itself when it is due and the ledger holds twenty slugs"
check "$(python3 -c 'import json,sys; r=[json.loads(l) for l in open(sys.argv[1])]; print(len(r), sum("theme merge" in json.dumps(x) or "folded" in x for x in r))' "$ASKS_STATE/runs.jsonl")" "1 0" \
  "  the run log stays the weekly pass's own: one row, the merge's in its own log (evolve reads runs.jsonl's newest as the week's run)"
out=$("$A" run --digest "$T/digest.json" --no-overrules); check "$(echo "$out" | grep -c 'theme merge')" 0 "  and not again the next week"
rm -rf "$ASKS_STATE"; python3 "$T/mkledger.py" "$ASKS_STATE" 20
printf '{"a-need": "b-need",' > "$ASKS_STATE/theme-merges.json"
sums() { cksum "$ASKS_STATE/theme-merges.json" "$ASKS_STATE/themes.json" | tr '\n' ' '; }
before=$(sums)
out=$("$A" merge --force); check "$? $(echo "$out" | grep -c '^theme merge: not run (theme-merges.json does not read')" "0 1" "a map that is there and does not read: the merge pass is not run, and says why"
check "$(sums)" "$before" "  the map and the ledger as they were (an earlier fold is in no git: read as empty, the pass wrote over it)"
out=$("$A" run --digest "$T/digest.json" --no-overrules); check "$(echo "$out" | grep -c '; theme merge: not run (theme-merges.json does not read')" 1 "  run, due and with twenty slugs, makes no pass over it and says so"
check "$(cksum "$ASKS_STATE/theme-merges.json" | awk '{print $1, $2}')" "$(echo "$before" | awk '{print $1, $2}')" "  and leaves the map as it was"
check "$("$A" numbers --days 30 --json | j 'd["theme_merges"]')" "unreadable" "  numbers says the map is unreadable, never a count that looks merged"
"$A" ship weekly-digest-ledger "PR 7" 2> "$T/ship.err"; check "$? $(grep -c 'theme-merges.json does not read.*nothing shipped' "$T/ship.err")" "1 1" "  ship refuses rather than guess a slug's keeper"
rm -rf "$ASKS_STATE"; python3 "$T/mkledger.py" "$ASKS_STATE" 20
printf '{"weekly-digest-ledger": {' > "$ASKS_STATE/themes.json"
before=$(cksum "$ASKS_STATE/themes.json")
"$A" run --digest "$T/digest.json" --no-overrules > /dev/null 2> "$T/torn.err"; check "$? $(grep -c 'themes.json does not read.*nothing labelled' "$T/torn.err")" "1 1" "a theme ledger that does not read: run refuses (it is in no git; read as empty, the week would be written over it)"
out=$("$A" merge --force); check "$(echo "$out" | grep -c '^theme merge: not run (themes.json does not read')" 1 "  the merge pass refuses it too"
"$A" ship weekly-digest-ledger "PR 7" 2> /dev/null; check $? 1 "  and ship"
check "$(cksum "$ASKS_STATE/themes.json") $(ls "$ASKS_STATE" | tr '\n' ' ')" "$before asks.jsonl themes.json " "  the ledger as it was, and nothing else written"
rm -rf "$ASKS_STATE"; python3 "$T/mkledger.py" "$ASKS_STATE" 0
out=$(STUB_NOGROUPS=1 "$A" merge); check "$(echo "$out" | grep -c 'the call failed (the reply has no groups list)')" 1 "a reply with no groups list is a failed call"
check "$(python3 -c 'import json,sys; print([json.loads(l)["status"] for l in open(sys.argv[1])])' "$ASKS_STATE/theme-merges.jsonl")" "['failed']" "  logged failed, so it is tried again in a week, not a month"
printf '{"a-need": 3}' > "$ASKS_STATE/theme-merges.json"
out=$("$A" merge --force); check "$(echo "$out" | grep -c 'not run (theme-merges.json does not read: not an object of slug to slug)')" 1 "  a value that is no slug is the same: not run"
rm -rf "$ASKS_STATE"; python3 "$T/mkledger.py" "$ASKS_STATE" 20
mkdir -p "$ASKS_FINDINGS"; printf '[{"id": "F1", "date": "%s", "need": "MATCHWORD x", "intervention": "y"}]\n' "$(day 6)" > "$ASKS_FINDINGS/f.json"
out=$(GATE_EVOLVE_MATCH_PROVIDER=off "$A" run --digest "$T/digest.json" --no-overrules); check "$(echo "$out" | grep -c '; theme merge: 25 slugs, ')" 1 \
  "an evolve.match that is off leaves the month's merge pass to evolve.theme's own row: it still runs"
rm -rf "$ASKS_STATE" "$ASKS_FINDINGS"; python3 "$T/mkledger.py" "$ASKS_STATE" 0
for reply in null '[{"type": "error"}]' '{"structured_output": {"groups": []}, "total_cost_usd": [1]}'; do
  printf '#!/bin/sh\ncat > /dev/null\nprintf "%%s\\n" '"'%s'"'\n' "$reply" > "$T/odd-claude"; chmod +x "$T/odd-claude"
  out=$(CLAUDE_BIN="$T/odd-claude" "$A" merge --force 2>&1); check "$? $(echo "$out" | grep -c 'the call failed') $(echo "$out" | grep -c Traceback)" "0 1 0" "a reply of $reply: the pass is said failed, never a traceback"
done
rm -rf "$ASKS_STATE"; python3 "$T/mkledger.py" "$ASKS_STATE" 0
printf '#!/bin/sh\n: > "%s/slow-started"\nn=0\nwhile [ $n -lt 600 ] && ! grep -q "another pass holds the ledger" "%s/ship.err" 2>/dev/null; do sleep 0.1; n=$((n + 1)); done\nexec "%s/claude"\n' "$T" "$T" "$T" > "$T/slow-claude"; chmod +x "$T/slow-claude"
rm -f "$T/slow-started" "$T/ship.err"; CLAUDE_BIN="$T/slow-claude" "$A" merge > "$T/slow.out" &
slow=$!
for _ in $(seq 600); do [ -e "$T/slow-started" ] && break; sleep 0.1; done
"$A" ship weekly-digest-ledger "PR 7" 2> "$T/ship.err"; wait "$slow"
check "$(grep -c 'another pass holds the ledger' "$T/ship.err") $(grep -c 'folded 2 slugs' "$T/slow.out")" "1 1" "a ship made while the merge pass waits on its call waits for the pass's hold"
check "$(python3 -c 'import json,sys; t=json.load(open(sys.argv[1])); print(sorted(t), t["weekly-digest-ledger"]["shipped"]["ref"])' "$ASKS_STATE/themes.json")" \
  "['empty-page', 'other-thing', 'weekly-digest-ledger'] PR 7" "  and both writes stand: the folded ledger, and the ship on it (the pass wrote its old copy over the ship)"
rm -rf "$ASKS_STATE"; python3 "$T/mkledger.py" "$ASKS_STATE" 20
printf '{"sessions": []}\n' > "$T/empty-digest.json"
out=$("$A" run --digest "$T/empty-digest.json" --no-model --no-overrules); check "$(echo "$out" | grep -c 'theme merge') $(ls -A "$ASKS_STATE" | grep -c '^theme-merges')" "0 0" \
  "run --no-model with nothing new to label, due and with twenty slugs: no merge pass, no call (--no-model spends nothing)"
rm -rf "$ASKS_STATE"; python3 "$T/mkledger.py" "$ASKS_STATE" 0
cat > "$T/holder.py" <<'PY'
import fcntl, json, os, sys, time, datetime as dt
state, held, err = sys.argv[1:4]
fd = os.open(os.path.join(state, ".lock"), os.O_RDWR | os.O_CREAT, 0o600)
fcntl.flock(fd, fcntl.LOCK_EX)
open(held, "w").close()
for _ in range(1200):   # until the merge has judged it due and waits on the hold
    if "another pass holds the ledger" in (open(err).read() if os.path.exists(err) else ""):
        break
    time.sleep(0.05)
with open(os.path.join(state, "theme-merges.jsonl"), "a") as f:   # the pass that held the ledger merged meanwhile
    f.write(json.dumps({"ts": dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"), "status": "ok", "cost_usd": 0.02}) + "\n")
PY
rm -f "$T/held" "$T/merge.err"; python3 "$T/holder.py" "$ASKS_STATE" "$T/held" "$T/merge.err" &
holder=$!
for _ in $(seq 600); do [ -e "$T/held" ] && break; sleep 0.1; done
out=$("$A" merge 2> "$T/merge.err"); wait "$holder"
check "$(grep -c 'another pass holds the ledger' "$T/merge.err") $(echo "$out" | grep -c '^theme merge: not due (a pass worked') $(wc -l < "$ASKS_STATE/theme-merges.jsonl" | tr -d ' ')" "1 1 1" \
  "a merge that waited on a pass holding the ledger judges due again under the hold: that pass merged, so no second call"
rm -rf "$ASKS_STATE"; python3 "$T/mkledger.py" "$ASKS_STATE" 0
printf '#!/bin/sh\ncat > /dev/null\nprintf "%%s\\n" '"'"'{"result": "Here are the groups", "total_cost_usd": 0.25, "is_error": false}'"'"'\n' > "$T/prose-claude"; chmod +x "$T/prose-claude"
out=$(CLAUDE_BIN="$T/prose-claude" "$A" merge); check "$(echo "$out" | grep -c 'the call failed') $(python3 -c 'import json,sys; print([json.loads(l) for l in open(sys.argv[1])][-1]["cost_usd"])' "$ASKS_STATE/theme-merges.jsonl")" "1 0.25" \
  "a paid call whose answer is prose: said failed, and its spend in the merge log all the same"
rm -rf "$ASKS_STATE"; : > "$GATE_LOG"

echo "evolve S11: G1's rows apart, E and N, lead time = finding time - ask time"
cat > "$T/mkg1.py" <<'PY'
import datetime as d, json, os, sys
state = sys.argv[1]
day = lambda k: (d.date.today() - d.timedelta(days=k)).isoformat()
os.makedirs(state, exist_ok=True)
def row(i, k, theme, detect, match=None, sess=None):
    r = {"id": i, "date": day(k), "ts": day(k) + "T10:00:00.000Z", "week": "2026-W01", "project": "regatta", "session": sess or i,
         "target": "system", "kind": "feature", "level": "KL", "detect": detect, "theme": theme, "by": "model"}
    if match:
        r["match"] = match
    return r
rows = [row("e1", 3, "ta", "E", {"label": "anticipated", "finding": "F1", "lead_days": -3}),
        row("e2", 3, "tb", "E", {"label": "M2"}),
        row("e3", 2, "tc", "E", {"label": "J"}),
        row("e4", 2, "td", "E"),
        row("n1", 2, "te", "N", {"label": "anticipated", "finding": "F2", "lead_days": -5}),
        row("n2", 2, "tf", "N", {"label": "M1"}),
        row("j1", 1, "tg", "J"),
        row("u1", 1, "th", "unknown")]
rows += [{"id": "p%d" % i, "date": day(1), "ts": day(1) + "T09:00:00.000Z", "week": "2026-W01", "project": "regatta", "session": "z%d" % i,
          "target": "none", "by": "model"} for i in range(12)]
open(os.path.join(state, "asks.jsonl"), "w").write("".join(json.dumps(r) + "\n" for r in rows))
PY
python3 "$T/mkg1.py" "$ASKS_STATE"
n=$("$A" numbers --json)
check "$(echo "$n" | j '(d["recall"], d["lead_days"])')" "('no findings yet', 'no findings yet')" "no findings: recall and lead time say so (an ask is never credited without one)"
mkdir -p "$ASKS_FINDINGS"; printf '[{"id": "F0", "date": "%s", "need": "x", "intervention": "y"}]\n' "$(day 20)" > "$ASKS_FINDINGS/f.json"
n=$("$A" numbers --json)
check "$(echo "$n" | j '(d["g1_E"], d["g1_N"])')" \
  "({'eligible': 2, 'anticipated': 1, 'recall': 50, 'lead_days': -3.0}, {'eligible': 2, 'anticipated': 1, 'recall': 50, 'lead_days': -5.0})" \
  "E and N apart: eligible = matched and not J; E 1 of 2 at -3 days, N 1 of 2 at -5"
check "$(echo "$n" | j '(d["recall"], d["lead_days"])')" "(50, -3.0)" "  the headline recall and lead time are E's alone: an N sensor never moves them"
check "$(echo "$n" | j '(d["residual_asks"], d["residual_per_100"], d["j_asks"], d["unknown_asks"], d["unmatched_eligible"])')" "(6, 30.0, 1, 1, 1)" \
  "  residual asks (no finding anticipated them) per 100 owner prompts, and the J, unknown and not-yet-matched counts printed beside"
check "$("$A" numbers | grep -o 'recall E 50, N 50, residual 30.0 per 100; lead time (days, finding minus ask) E -3.0')" "recall E 50, N 50, residual 30.0 per 100; lead time (days, finding minus ask) E -3.0" "the text line shows the rows"
rm -rf "$ASKS_STATE" "$ASKS_FINDINGS"

echo "evolve S11: the memo-acceptance CUSUM replayed on timestamp-ordered answers"
cat > "$T/cusum.py" <<'PY'
import sys
from importlib.machinery import SourceFileLoader
a = SourceFileLoader("asks", sys.argv[1]).load_module()
import datetime as d
base = d.datetime(2026, 9, 1, 8, 0, tzinfo=d.timezone.utc)
iso = lambda t: t.strftime("%Y-%m-%dT%H:%M:%SZ")
# twenty answers that took the pick, two a day, then one busy day: 36 answers in order, twelve of them overruled
items = [(iso(base + d.timedelta(hours=12 * i)), "a%02d" % i, 1) for i in range(20)]
day = base + d.timedelta(days=12)
pattern = ([0] + [1, 1]) * 12     # an overrule, then two picks taken, twelve times
items += [(iso(day + d.timedelta(minutes=10 * i)), "b%02d" % i, v) for i, v in enumerate(pattern)]
r = a.cusum_replay(items)
print("ts", len(r["fired"]), r["read"], r["max_s"] < a.CUSUM_H)
r2 = a.cusum_replay(items, order="declines-first")
print("declines-first", len(r2["fired"]))
steady = [(iso(base + d.timedelta(hours=6 * i)), "c%03d" % i, 1 if i % 5 else 0) for i in range(120)]
print("steady", len(a.cusum_replay(steady)["fired"]))
slide = [(iso(base + d.timedelta(hours=6 * i)), "s%03d" % i, 1 if i < 40 else 0) for i in range(120)]
print("slide", len(a.cusum_replay(slide)["fired"]) >= 1)
print("short", a.cusum_replay(items[:5]))
shuffled = list(reversed(items))
print("order-free", a.cusum_replay(shuffled) == a.cusum_replay(items))
tie = [(iso(base), "z1", 1), (iso(base), "a1", 0)]
print("ties", [x for x in sorted(tie, key=lambda x: (x[0], x[1]))][0][1])
PY
python3 "$T/cusum.py" "$A" > "$T/cusum.out" 2>&1
check "$(sed -n 1p "$T/cusum.out")" "ts 0 46 True" "twelve overrules among thirty-six answers in a day, in timestamp order: no firing, the deficit under the threshold"
check "$(sed -n 2p "$T/cusum.out")" "declines-first 1" "  the same day with its overrules read first fires (the delta round's replay did that): the order is the whole difference"
check "$(sed -n 3p "$T/cusum.out")" "steady 0" "a steady one in five overruled never fires"
check "$(sed -n 4p "$T/cusum.out")" "slide True" "an owner who stops taking the picks does fire"
check "$(sed -n 5p "$T/cusum.out")" "short {'items': 5, 'read': 0, 'fired': [], 'max_s': 0.0, 'last_s': 0.0}" "fewer than ten answers behind it: warming, nothing read"
check "$(sed -n 6p "$T/cusum.out")" "order-free True" "the input order does not matter: the rows are sorted by their time, ties by id"
cat > "$T/epoch.py" <<'PY'
import sys
from importlib.machinery import SourceFileLoader
a = SourceFileLoader("asks", sys.argv[1]).load_module()
print(a.parse_when(1761900000.5).isoformat(), a.parse_when("1761900000.5") == a.parse_when(1761900000.5), a.parse_when("2026-10-05").isoformat(), a.parse_when("2026-10-05T10:00:00Z").isoformat())
r = a.cusum_replay([(str(1761900000 + 3600 * i), "e%02d" % i, 1) for i in range(30)])
print(r["items"], r["read"], r["fired"])
import json, os
os.makedirs(a.STATE, exist_ok=True)
open(a.STATE / "theme-merges.jsonl", "w").write(json.dumps({"status": "ok"}) + "\n")
print(a.merge_due())
PY
python3 "$T/epoch.py" "$A" > "$T/epoch.out" 2>&1
check "$(sed -n 1p "$T/epoch.out")" "2025-10-31T08:40:00.500000+00:00 True 2026-10-05T00:00:00+00:00 2026-10-05T10:00:00+00:00" "an epoch (what interruptions stamps), a bare day and an ISO second all read, as UTC"
check "$(sed -n 2p "$T/epoch.out")" "30 20 []" "  a replay over epoch-stamped answers runs"
check "$(sed -n 3p "$T/epoch.out")" "True" "a merge-log row that does not read counts as no row: due again, no crash"
cat > "$T/interruptions" <<'PY'
import json
rows = [dict(channel="ask", kind="free-text", recommended="", ts=1761900000, session="s1", question="unranked"),
        dict(channel="ask", kind="free-text", recommended="Keep it (Recommended)", ts=1761900060, session="s1", question="ranked"),
        dict(channel="ask", kind="recommended", recommended="Keep it (Recommended)", ts=1761900120, session="s1", question="took")]
print(json.dumps({"rows": rows}))
PY
cat > "$T/onmain.py" <<'PY'
import argparse, os, subprocess, sys
from pathlib import Path
from importlib.machinery import SourceFileLoader
a = SourceFileLoader("asks", sys.argv[1]).load_module()
a.common.tool = lambda name: sys.argv[3]
print([took for _, _, took in a.answer_rows(30)[0]])
repo = Path(sys.argv[2])
subprocess.run(["git", "init", "-q", str(repo)], check=True)
subprocess.run(["git", "-C", str(repo), "symbolic-ref", "HEAD", "refs/heads/main"], check=True)
golden = repo / "modules" / "plumb" / "golden" / "manifest.json"
print(a.on_main(golden.parent), end=" ")
subprocess.run(["git", "-C", str(repo), "symbolic-ref", "HEAD", "refs/heads/claude/x"], check=True)
print(a.on_main(golden.parent), a.on_main(repo.parent / "no-repo-here"), a.in_git(golden.parent), a.in_git(repo.parent / "no-repo-here"))
subprocess.run(["git", "-C", str(repo), "symbolic-ref", "HEAD", "refs/heads/main"], check=True)
a.GOLDEN = golden
os.environ.pop("ASKS_GOLDEN", None)
rc = a.cmd_golden(argparse.Namespace(what="add", batch=None, id="x", target="system", kind=None, level=None, detect=None))
print(rc, golden.exists())
PY
python3 "$T/onmain.py" "$A" "$T/mainrepo" "$T/interruptions" > "$T/onmain.out" 2>"$T/onmain.err"
check "$(sed -n 1p "$T/onmain.out")" "[0, 1]" "cusum's answers: a free-text answer to a question that marked no pick is no refusal; one that marked a pick is"
check "$(sed -n 2p "$T/onmain.out")" "True False False True False" "on_main: a checkout on main, one on a branch, no checkout; in_git: a checkout, none (an install's folder: golden add refuses it)"
check "$(sed -n 3p "$T/onmain.out") $(grep -c 'run it from a worktree' "$T/onmain.err")" "2 False 1" "golden add refuses to write the manifest of a checkout on main (what the shims run), and writes nothing"
rm -rf "$ASKS_STATE"
out=$("$A" cusum --days 30); check "$(echo "$out" | grep -o '^cusum over 0 answers (0 read')" "cusum over 0 answers (0 read" "asks cusum on a scratch HOME with no answers: counted, no crash"

echo "evolve S11: the golden fixture (ids and labels in git, the text in the state dir)"
export ASKS_GOLDEN="$T/golden/manifest.json"
check "$("$A" golden list)" "golden: 0 verified labels in the manifest, 0 with their text in the state dir (need 30 to judge a change); none yet" "an empty fixture is counted"
cat > "$T/mkgolden.py" <<'PY'
import json, sys
from importlib.machinery import SourceFileLoader
a = SourceFileLoader("asks", sys.argv[1]).load_module()
import datetime as d
day = (d.date.today() - d.timedelta(days=2)).isoformat()
prompts, batch = [], []
for i in range(36):
    ts = "%sT%02d:%02d:00.000Z" % (day, 8 + i // 6, (i % 6) * 10)
    sysask = i < 18
    text = ("ASKWORD GOLDWORD %d the dream must remember this EVIDWORD" % i) if sysask else ("fix the typo %d in the readme GOLDWORD" % i)
    prompts.append({"ts": ts, "text": text, "marked": False})
    e = {"id": a.ask_id("gsess-1", ts, text)}
    e.update({"target": "system", "kind": "bug", "level": "KL", "detect": "E"} if sysask else {"target": "none"})
    batch.append(e)
json.dump({"generated": "x", "days": 7, "scope": None, "fenced": {"sessions": 0}, "sessions": [
    {"project": "regatta", "session": "gsess-1", "title": None, "start": day, "source": "live", "prompts": prompts}]}, open(sys.argv[2], "w"))
json.dump(batch, open(sys.argv[3], "w"))
PY
python3 "$T/mkgolden.py" "$A" "$T/gdigest.json" "$T/gbatch.json"
CLAUDE_UNATTENDED=1 "$A" golden add --batch "$T/gbatch.json" --digest "$T/gdigest.json" > /dev/null 2>&1; check $? 2 "add refuses an unattended run (a verified label is the owner's word)"
REGATTA_UNATTENDED=1 "$A" golden add --batch "$T/gbatch.json" --digest "$T/gdigest.json" > /dev/null 2>&1; check $? 2 "  by the new name too"
AUTOFINISH_CALLER_UNATTENDED=peer "$A" golden add --batch "$T/gbatch.json" --digest "$T/gdigest.json" > /dev/null 2>&1; check $? 2 "  and in a peer's job (the core's unattended_caller)"
printf '[{"id": 123, "target": "none"}]\n' > "$T/gnum.json"
"$A" golden add --batch "$T/gnum.json" --digest "$T/gdigest.json" > /dev/null 2>"$T/gnum.err"; check "$? $(grep -c Traceback "$T/gnum.err")" "2 0" "an id that is no string is refused, not a traceback"
check "$([ -e "$ASKS_GOLDEN" ] && echo written)" "" "  and wrote nothing"
printf '[{"id": "abc", "target": "bogus"}]\n' > "$T/gbad.json"
"$A" golden add --batch "$T/gbad.json" --digest "$T/gdigest.json" > /dev/null 2>&1; check $? 2 "a label the prompt does not have is refused"
printf '[{"id": "nosuchid0000", "target": "none"}]\n' > "$T/gnone.json"
"$A" golden add --batch "$T/gnone.json" --digest "$T/gdigest.json" > /dev/null 2>&1; check $? 1 "an id no prompt in the digest has is refused"
python3 -c 'import json,sys; b=json.load(open(sys.argv[1])); print(json.dumps([dict(b[0], target="question", detect="EE")]))' "$T/gbatch.json" > "$T/gq.json"
"$A" golden add --batch "$T/gq.json" --digest "$T/gdigest.json" > /dev/null 2>&1; check $? 2 "a question's dimension that is no label is refused (any dimension set is checked)"
mkdir -p "$(dirname "$ASKS_GOLDEN")"; printf '{"version": 1, "labels": {"x": {"target": "none"},}}\n' > "$ASKS_GOLDEN"
"$A" golden add --batch "$T/gbatch.json" --digest "$T/gdigest.json" > /dev/null 2>"$T/gbroken.err"; check "$? $(grep -c 'does not read as a manifest' "$T/gbroken.err") $(grep -c '"x"' "$ASKS_GOLDEN")" "2 1 1" "a manifest that does not read: add refuses, names it, and leaves it as it was"
"$A" golden list > /dev/null 2>&1; check $? 2 "  list refuses too"
"$A" golden check > /dev/null 2>&1; check $? 4 "  check cannot tell"
rm -f "$ASKS_GOLDEN"
mkdir -p "$ASKS_STATE/golden"; printf '{"id": "keep", "text": "x"}\nnot json\n' > "$ASKS_STATE/golden/texts.jsonl"
"$A" golden add --batch "$T/gbatch.json" --digest "$T/gdigest.json" > /dev/null 2>"$T/gtexts.err"; check "$? $(grep -c 'line 2 does not read' "$T/gtexts.err") $(wc -l < "$ASKS_STATE/golden/texts.jsonl" | tr -d ' ') $([ -e "$ASKS_GOLDEN" ] && echo written || echo none)" "2 1 2 none" "a text file with a line that does not read: add refuses and leaves it (the owner's text is in no git)"
"$A" golden list > /dev/null 2>&1; check $? 2 "  list refuses too"
rm -f "$ASKS_STATE/golden/texts.jsonl"
out=$("$A" golden add --batch "$T/gbatch.json" --digest "$T/gdigest.json"); check "$(echo "$out" | grep -o '^golden: 36 labels added; 36 in the manifest')" "golden: 36 labels added; 36 in the manifest" "add: thirty-six labels"
check "$(grep -c 'GOLDWORD\|ASKWORD\|readme' "$ASKS_GOLDEN") $(grep -c GOLDWORD "$ASKS_STATE/golden/texts.jsonl")" "0 36" "the manifest (the file for git) holds no word of the owner's; the text is in the state dir"
check "$("$A" golden list | grep -o '36 verified labels in the manifest, 36 with their text')" "36 verified labels in the manifest, 36 with their text" "list counts both"
out=$("$A" golden check); check $? 0 "check: the stand-in labeller meets the bars"
check "$(echo "$out" | grep -o 'meets the bars — detectable (E or N) precision 1.00 (bar 0.80), recall 1.00 (bar 0.85) over 36 verified prompts')" \
  "meets the bars — detectable (E or N) precision 1.00 (bar 0.80), recall 1.00 (bar 0.85) over 36 verified prompts" "  precision and recall of the detectable class, against the bars"
out=$(STUB_NO_EVID=1 "$A" golden check); check $? 3 "a labeller that calls every ask the owner's judgement (J): refused, exit 3"
check "$(echo "$out" | grep -o 'BELOW THE BARS, the change is refused — detectable (E or N) precision 0.00 (bar 0.80), recall 0.00')" "BELOW THE BARS, the change is refused — detectable (E or N) precision 0.00 (bar 0.80), recall 0.00" "  recall 0.00: relabelling misses as J does not raise a score"
out=$(CLAUDE_BIN=/usr/bin/false "$A" golden check); check "$? $(echo "$out" | grep -o 'cannot tell')" "4 cannot tell" "a gate that gives nothing: cannot tell, exit 4, never a pass"
out=$(GATE_EVOLVE_ASK_PROVIDER=off "$A" golden check); check "$? $(echo "$out" | grep -o 'cannot tell')" "4 cannot tell" "  a row that is off the same"
python3 - "$ASKS_GOLDEN" "$ASKS_STATE/golden/texts.jsonl" <<'PY'
import json, sys
m = json.load(open(sys.argv[1]))
m["labels"] = dict(list(m["labels"].items())[:20])
json.dump(m, open(sys.argv[1], "w"))
PY
out=$("$A" golden check); check "$? $(echo "$out" | grep -o 'cannot tell — 20 verified labels have their text here, 30 are needed')" "4 cannot tell — 20 verified labels have their text here, 30 are needed" "fewer than thirty labels with their text: cannot tell, never a pass"
python3 - "$ASKS_GOLDEN" <<'PY'
import json, sys
m = json.load(open(sys.argv[1]))
m["labels"] = {k: {"target": "none"} for k in m["labels"]}
json.dump(m, open(sys.argv[1], "w"))
PY
python3 "$T/mkgolden.py" "$A" "$T/gdigest.json" "$T/gbatch.json"
python3 - "$ASKS_GOLDEN" "$T/gbatch.json" <<'PY'
import json, sys
m = json.load(open(sys.argv[1]))
m["labels"].update({e["id"]: {"target": "none"} for e in json.load(open(sys.argv[2]))})
json.dump(m, open(sys.argv[1], "w"))
PY
out=$(STUB_NO_EVID=1 "$A" golden check); check "$? $(echo "$out" | grep -o 'cannot tell — the fixture holds no detectable')" "4 cannot tell — the fixture holds no detectable" "a fixture with no E or N label and a labeller that finds none: cannot tell (recall is undefined), never a refusal"
"$A" golden check > /dev/null; check $? 3 "  a labeller that calls them detectable anyway: precision 0.00, refused"
rm -rf "$ASKS_STATE" "$T/golden"; unset ASKS_GOLDEN; : > "$GATE_LOG"

echo "the sieve's own cases"
check "$(python3 - "$D/bin/asks" <<'PY'
import sys
from importlib.machinery import SourceFileLoader
a = SourceFileLoader("asks", sys.argv[1]).load_module()
cases = ["/finish --unattended", "<system-reminder> x", "status?", "yes please", "A — the first", "from now on use tabs",
         "never do that again", "rename the file", "hello"]
print([a.sieve(c)[0] for c in cases])
sig = a.signature("the dream must remember corrections about the weekly digest ledger")
print(len(sig) >= 5, a.pick_theme({}, sig, "KL").startswith("t"))
PY
)" "['machine', 'machine', 'status', 'answer', 'answer', 'ask', 'correction', 'ask', 'task']
True True" "machine, status, answer, ask, correction, task; a signature and a theme id"

[ "$fails" -eq 0 ] && echo "asks: all ok" || { echo "asks: $fails failed"; exit 1; }
