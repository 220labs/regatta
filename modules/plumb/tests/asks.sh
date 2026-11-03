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
import json, sys
p = sys.stdin.read()
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
    return "E" if "EVIDWORD" in t else "J"
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
  "1 anticipated F1 3" "anticipated by F1, three days ahead (the later finding F9 is no candidate)"
check "$("$A" numbers --json | j '(d["recall"], d["lead_days"])')" "(100, 3.0)" "numbers: recall and lead time now measured"
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
