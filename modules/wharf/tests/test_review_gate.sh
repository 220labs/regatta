#!/usr/bin/env bash
# Tests for wharf's review-gate — a fake `claude` on PATH, a localhost fake of Jev, scratch repos
# and a scratch week; no network, no model call, no real key. (The reviewer agents' pair cases
# stay with the agents until they join this module.)
#   bash modules/wharf/tests/test_review_gate.sh
set -u
M="$(cd "$(dirname "$0")/.." && pwd)"   # the wharf module
B="$M/bin"
GATE="$M/../regatta/bin/gate"            # the core's
T=$(mktemp -d); T=$(cd "$T" && pwd -P)
for v in $(env | sed -n 's/^\(GATE_[A-Z0-9_]*\)=.*/\1/p'); do unset "$v"; done   # the caller's overrides
# The config dir: the caller's when it names one (an overlay's private values and its legacy
# checkout, where usage-report and tier_check are found until plumb moves), else a scratch one
# naming a guarded repo of its own. The core is the one beside this module.
if [ -z "${REGATTA_CONFIG:-}" ]; then
  export REGATTA_CONFIG="$T/regatta-config"; mkdir -p "$REGATTA_CONFIG/regatta"; echo notes-vault > "$REGATTA_CONFIG/regatta/guarded"
fi
export REGATTA_CONFIG; unset REGATTA_HOME REGATTA_LEGACY
export CLAUDE_CONFIG_DIR="$T/claude-config"   # no plugin registry but the suite's own
core() { python3 -c "import sys; sys.path.insert(0, sys.argv[1]); import common; $1" "$M/../regatta/hooks"; }
GUARD=$(core 'print((common.guarded_repos() + ("",))[0])')
[ -n "$GUARD" ] || { GUARD=$(core 'from pathlib import Path; print(Path(common.config_line("regatta/guarded") or "").name)'); }
# a caller's config that names no guarded repo (a CI job's empty one, REGATTA_CONFIG=$(mktemp -d)):
# a copy of it naming one of its own, as without a config — else the guarded cases ran on "" and
# failed on a CI runner (suites-host, 2026-10-20). An overlay's always names one (OVERLAY_KEYS).
# cp -R keeps links: drop the copy's `guarded` first, so the write never lands in a link's target.
if [ -z "$GUARD" ]; then
  mkdir -p "$T/regatta-config"; cp -R "$REGATTA_CONFIG/." "$T/regatta-config/" 2>/dev/null
  mkdir -p "$T/regatta-config/regatta"; rm -f "$T/regatta-config/regatta/guarded"
  echo notes-vault > "$T/regatta-config/regatta/guarded"
  export REGATTA_CONFIG="$T/regatta-config"; GUARD=notes-vault
fi
TC=$(core 'print(common.tool("tier_check.py") or "")')   # plumb's (G7): the week cases need it
UR=$(core 'print(common.tool("usage-report") or "")')    # …and the data-folder case
# The table: the four review-gate rows, as an overlay's table carries them (the core ships none).
cat > "$T/table.json" <<'EOF'
{"defaults": {"claude": {"model": "opus"}, "jev": {"model": "jev-latest", "threshold": 0.5}},
 "sites": {"review-gate.merge": {"kind": "generate", "provider": "claude", "effort": "medium", "when_off": "skip", "model": "claude-opus-5-5"},
           "review-gate.same-shadow": {"kind": "classify", "provider": "jev", "batch": 1, "when_off": "skip"},
           "review-gate.reviewer": {"kind": "review", "provider": "claude"},
           "review-gate.code-review": {"kind": "review", "provider": "claude"}}}
EOF
export GATE_TABLE="$T/table.json"   # bin/gate reads this, except where a case names a scratch copy
fails=0
# BSD and GNU sed disagree on `-i ''` (GNU takes '' as the script and the real script as a file name); `-i.bak` and a rm work on both.
sedi() { local f="${!#}"; sed -i.bak "$@" && rm -f "$f.bak"; }
check() { if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3: expected [$2] got [$1]"; fails=$((fails+1)); fi; }
has()   { if grep -qF -- "$2" "$1"; then echo "  ok   $3"; else echo "  FAIL $3: missing [$2]"; fails=$((fails+1)); fi; }
lacks() { if grep -qF -- "$2" "$1"; then echo "  FAIL $3: found [$2]"; fails=$((fails+1)); else echo "  ok   $3"; fi; }

# ---------- plan ----------
mkrepo() {  # mkrepo DIR LINES — main holds old.py (300 lines); HEAD deletes it and adds LINES lines
  git init -q -b main "$1"
  python3 -c "import sys; open(sys.argv[1]+'/old.py','w').write('y = 2\n' * 300)" "$1"
  git -C "$1" add -A && git -C "$1" -c user.email=t@t -c user.name=t commit -q -m init
  git -C "$1" checkout -q -b claude/x
  git -C "$1" rm -q old.py
  python3 -c "import sys; open(sys.argv[1]+'/f.py','w').write('x = 1\n' * int(sys.argv[2]))" "$1" "$2"
  git -C "$1" add -A && git -C "$1" -c user.email=t@t -c user.name=t commit -q -m add
}
week() {  # week PERCENT [RESET_IN_DAYS=1 [SAMPLED_DAYS_AGO=0]] — reset in 1 day: pace 85.7% (hour 144)
  python3 - "$1" "${2:-1}" "${3:-0}" > "$T/claude.json" <<'EOF'
import json, sys, datetime as dt
r = dt.datetime.fromtimestamp(1_800_000_000 + 86400 * float(sys.argv[2]), dt.timezone.utc).isoformat()
print(json.dumps({"cachedUsageUtilization": {"fetchedAtMs": int((1_800_000_000 - 86400 * float(sys.argv[3])) * 1000), "utilization": {"limits": [
    {"kind": "weekly_all", "percent": float(sys.argv[1]), "resets_at": r}]}}}))
EOF
}
export CLAUDE_TIER_CLAUDE_JSON="$T/claude.json" CLAUDE_TIER_APP_HISTORY="$T/none.json" CLAUDE_TIER_NOW=1800000000
plan() { python3 "$B/review-gate" plan --repo "$1" --json | python3 -c "import json,sys; p=json.load(sys.stdin); print(p['tier'], p['budget'], p['reviewer']['agent'], p['code_review']['args'])"; }
for n in 50 99 100 1000 1001; do mkrepo "$T/r$n" $n; done
if [ -z "$TC" ]; then
echo "the week cases: skipped, tier_check not installed (G7) — the absent case is below"
else
week 50
check "$(plan "$T/r50")"   "small normal reviewer-high high main...HEAD"    "50 lines: high + CR high"
check "$(plan "$T/r99")"   "small normal reviewer-high high main...HEAD"    "99 lines: still small"
check "$(plan "$T/r100")"  "medium normal reviewer-high xhigh main...HEAD"  "100 lines: high + CR xhigh"
check "$(plan "$T/r1000")" "medium normal reviewer-high xhigh main...HEAD"  "1,000 lines: still medium"
check "$(plan "$T/r1001")" "large normal reviewer xhigh main...HEAD"        "1,001 lines: xhigh + CR xhigh"
week 85
check "$(plan "$T/r1001")" "large tight reviewer high main...HEAD"          "tight week: top tier xhigh + CR high"
check "$(plan "$T/r100")"  "medium tight reviewer-high xhigh main...HEAD"   "tight week: middle tier unchanged"
week 92
check "$(plan "$T/r1001")" "large lowest reviewer-high high main...HEAD"    "lowest week: high + CR high on top"
check "$(plan "$T/r100")"  "medium lowest reviewer-high high main...HEAD"   "lowest week: high + CR high in the middle"
python3 -c "import json; print(json.dumps({'cachedUsageUtilization': {'fetchedAtMs': 1800000000000, 'utilization': {'limits': [{'kind': 'weekly_all', 'percent': 85.0}]}}}))" > "$T/claude.json"
check "$(plan "$T/r1001")" "large tight reviewer high main...HEAD"          "no reset time: the 80% rule still holds"
rm -f "$T/claude.json"
check "$(plan "$T/r1001")" "large normal reviewer xhigh main...HEAD"        "no week reading: normal tiers"
check "$(git -C "$T/r50" diff --shortstat main...HEAD | grep -c '300 deletions')" "1" "fixture: 300 lines deleted on the branch"
check "$(plan "$T/r50")" "small normal reviewer-high high main...HEAD"       "deletions do not count (D7): +50 −300 is small"
week 45 5
check "$(plan "$T/r1001")" "large tight reviewer high main...HEAD"          "10 points over pace (45% at 28.6%): tight"
week 92 5 3
check "$(plan "$T/r1001")" "large normal reviewer xhigh main...HEAD"        "a reading from before this week's reset is ignored"
week 50
python3 "$B/review-gate" plan --repo "$T/r50" > "$T/plan.txt" 2>&1
has "$T/plan.txt" "sampled 0.0 h ago" "plan prints the reading's age"
fi
python3 "$B/review-gate" plan --repo "$T/r50" > "$T/plan.txt" 2>&1
python3 "$B/review-gate" plan --repo "$T/r50" --base nosuchbase > "$T/plan2.txt" 2>&1
has "$T/plan2.txt" "⚠ git diff nosuchbase...HEAD failed" "a failed diff is said, not read as 0 lines"
mkrepo "$T/own" 150 >/dev/null; mkdir -p "$T/own/.claude/agents" && : > "$T/own/.claude/agents/reviewer.md"
[ -n "$TC" ] && week 50
check "$(plan "$T/own")" "medium normal reviewer xhigh main...HEAD"         "project's own reviewer, no -high twin: its own"

# ---------- merge ----------
cat > "$T/fake.py" <<'EOF'
import json, sys, http.server
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        # bin/gate's classify: state {items: {pair id: {a, b}}}, one question per item (batch: 1)
        it = body["state"]["items"]  # the same defect: the dereference and its null check, nothing else
        ans = {k: {"type": "noul", "noul": 0.95 if "null" in it[k]["b"]["claim"] and "dereferences" in it[k]["a"]["claim"] else 0.02}
               for k in body["questions"]}
        out = json.dumps({"model": "jev-1.13.0", "answers": ans,
                          "usage": {"input_tokens": 300, "output_tokens": 1}}).encode()
        self.send_response(200); self.send_header("Content-Type", "application/json"); self.end_headers()
        self.wfile.write(out)
s = http.server.HTTPServer(("127.0.0.1", 0), H)
open(sys.argv[1], "w").write(str(s.server_address[1]))
s.serve_forever()
EOF
python3 "$T/fake.py" "$T/port" & FAKE=$!
trap 'kill $FAKE 2>/dev/null; rm -rf "$T"' EXIT
for i in 1 2 3 4 5 6 7 8 9 10; do [ -s "$T/port" ] && break; sleep 0.2; done
export TYPESAFE_BASE_URL="http://127.0.0.1:$(cat "$T/port")" TYPESAFE_API_KEY=sk-test JEV_LOG="$T/jev.jsonl" \
       REVIEW_GATE_LOG="$T/gate.jsonl" GATE_LOG="$T/gate-calls.jsonl"
export USAGE_CC="$T/cc" USAGE_ARCHIVE="$T/archive"   # the log line's transcripts: fixtures, never the owner's

mkdir -p "$T/bin"
cat > "$T/bin/claude" <<'EOF'
#!/usr/bin/env python3
import json, os, re, sys
prompt = sys.stdin.read()
open(os.environ["FAKE_CLAUDE_SEEN"], "w").write(" ".join(sys.argv[1:]) + "\n" + prompt)
if os.environ.get("FAKE_CLAUDE_FAIL"):
    print(json.dumps({"is_error": True, "result": "API Error: overloaded"})); sys.exit(1)
ids = re.findall(r'"id": "([RC]\d+)"', prompt)
sev = {i: (2 if i == "C2" else 1) for i in ids}
same = {p: (0.9 if p == "R1~C1" and not os.environ.get("FAKE_CLAUDE_LOW") else 0.1) for p in re.findall(r"^(R\d+~C\d+):", prompt, re.M)}
print(json.dumps({"result": "```json\n%s\n```" % json.dumps({"severity": sev, "same": same}), "total_cost_usd": 0.21}))
EOF
chmod +x "$T/bin/claude"
export PATH="$T/bin:$PATH" FAKE_CLAUDE_SEEN="$T/seen.txt"

R="$T/r1000"
cat > "$T/rev.txt" <<'EOF'
Read AGENTS.md first.

f.py:12 — the loop dereferences `cfg` before the null check
verdict: WRONG
evidence: sed -n 10,14p f.py shows cfg.x on line 12, the check on 13
  and a second evidence line
fix: move the check above line 12

`f.py:4000` — docstring claims a retry that does not exist
verdict: STALE-REASON
evidence: grep -n retry f.py: nothing
fix: none, note only

Cleared: g.py, h.py. 3 files read, 2 probes.
EOF
cat > "$T/cr.txt" <<'EOF'
xhigh main...HEAD
```json
[{"file": "f.py", "line": 13, "summary": "null check comes after the dereference", "failure_scenario": "cfg is None → AttributeError", "category": "correctness"},
 {"file": "./f.py", "line": 30, "summary": "deletes the live table", "failure_scenario": "run twice → rows gone", "category": "correctness"},
 {"file": "gone.py", "line": 1, "summary": "imports a removed module", "failure_scenario": "ImportError"}]
```
EOF
python3 "$B/review-gate" merge --reviewer "$T/rev.txt" --code-review "$T/cr.txt" --repo "$R" > "$T/out.txt" 2>"$T/err.txt"
check "$(head -1 "$T/out.txt")" "Merged review — 4 finding(s): 2 from the reviewer, 3 from /code-review, 1 merged · Opus medium \$0.210 · Jev decided 4 of 4 pair(s)" "header counts, with the pairs Jev decided (D4, adopted 2026-10-19)"
check "$(sed -n 2p "$T/out.txt")" "" "no ⚠ when nothing failed (the shadow stays off the output)"
has "$T/out.txt" "fix: move the check above line 12" "a field after a continuation still parsed"
has "$T/out.txt" "on 13 and a second evidence line" "a field's continuation line kept"
check "$(sed -n 3p "$T/out.txt")" "1. S1 · f.py:30 · code-review" "S1 first, ./ stripped"
has "$T/out.txt" "S2 · f.py:12 · reviewer + code-review" "R1 and C1 merged into one item"
has "$T/out.txt" "reviewer [WRONG]: the loop dereferences" "reviewer verdict carried"
has "$T/out.txt" "code-review (f.py:13): null check comes after the dereference — cfg is None" "merged member keeps its own line"
has "$T/out.txt" "evidence: sed -n 10,14p f.py" "evidence carried"
has "$T/out.txt" "cited line 4000 is past the end (1000 lines)" "file:line check: past the end"
has "$T/out.txt" "cited file not in the worktree" "file:line check: missing file"
has "$T/out.txt" "no evidence line: check it against the code" "CR-only items flagged for checking"
has "$T/seen.txt" "--model claude-opus-5-5 --effort medium" "merge model is Opus medium"
has "$T/seen.txt" "--tools  --setting-sources" "merge model has no tools, no settings"
check "$(python3 -c "import json,sys; r=[json.loads(l) for l in open(sys.argv[1])][-1]; print(len(r['pairs']), sorted((p['id'], p['opus'], p['jev'], p['jev_model']) for p in r['pairs'])[0])" "$T/gate.jsonl")" \
      "4 ('R1~C1', 0.9, 0.95, 'jev-1.13.0')" "shadow: every same-file pair logged with both answers"
has "$T/jev.jsonl" '"caller": "review-gate"' "Jev went through bin/jev, logged there"
lacks "$T/out.txt" "jev" "Jev's raw answers never reach the output"
check "$(python3 -c "import json,sys; r=[json.loads(l) for l in open(sys.argv[1])][-1]; print(r['jev_took'], sorted({p['took'] for p in r['pairs']}))" "$T/gate.jsonl")" \
      "4 ['jev']" "the log says who decided each pair"
FAKE_CLAUDE_LOW=1 python3 "$B/review-gate" merge --reviewer "$T/rev.txt" --code-review "$T/cr.txt" --repo "$R" > "$T/out-low.txt" 2>&1
has "$T/out-low.txt" "1 merged · Opus medium" "Opus says no where Jev is confident yes: Jev decides, R1 and C1 still merged"
cat > "$T/took.py" <<'EOF'
import sys
from importlib.machinery import SourceFileLoader
g = SourceFileLoader("rg", sys.argv[1]).load_module()
print(sorted(g.took({"a": {"p": 0.95, "model": "jev-1.13.0"}, "b": {"p": 0.5, "model": "jev-1.13.0"},
                     "c": {"p": 0.02, "model": "jev-1.14.0"}, "d": {"error": "deadline"},
                     "e": {"p": 0.1, "model": "jev-1.13.0"}}).items()))
EOF
check "$(python3 "$T/took.py" "$B/review-gate")" "[('a', 0.95)]" \
      "took(): only a measured version, only outside the band (0.1 itself is Opus's), never an error"

echo "the log line per branch: size, confirmed findings, who built it (model routing section 7, S-E)"
mkrepo "$T/rse" 40 >/dev/null
mkdir -p "$T/rse/docs" && printf 'a\nb\nc\nd\ne\nf\ng\n' > "$T/rse/docs/x.md" && printf 'n\n' > "$T/rse/NOTES.md"
git -C "$T/rse" add -A && git -C "$T/rse" -c user.email=t@t -c user.name=t commit -q -m docs
python3 - "$T" <<'PY'
import json, os, sys
T = sys.argv[1]
def a(ts, req, sid, branch, model, cwd=None, **kw):
    d = {"type": "assistant", "timestamp": ts, "requestId": req, "sessionId": sid, "gitBranch": branch, "uuid": req + "u",
         "cwd": cwd or f"{T}/rse", "message": {"model": model, "usage": {"output_tokens": 1}}}
    d.update(kw); return json.dumps(d)
def put(path, lines, meta=None):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, "w").write("\n".join(lines) + "\n")
    if meta: json.dump(meta, open(path[:-len(".jsonl")] + ".meta.json", "w"))
s1 = [a("2026-10-05T09:00:00Z", "m0", "s1", "main", "claude-fable-5-1"),          # before the branch: not counted
      a("2026-10-05T10:00:00Z", "m1", "s1", "claude/x", "claude-opus-5-5"),
      a("2026-10-05T10:00:00Z", "m1", "s1", "claude/x", "claude-opus-5-5"),       # a streamed call's second block
      a("2026-10-05T10:30:00Z", "m9", "s1", "claude/y", "claude-opus-5-5"),       # a detour to another branch
      a("2026-10-05T10:50:00Z", "m3", "s1", "claude/x", "claude-opus-5-5", cwd=f"{T}/rse/.claude/worktrees/x"),  # its worktree
      a("2026-10-05T12:00:00Z", "m2", "s1", "claude/x", "claude-opus-5-5")]
put(f"{T}/cc/-p/s1.jsonl", s1)
put(f"{T}/archive/p/2026-10-05-s1.jsonl", s1)                                         # the archive's copy counts once
put(f"{T}/cc/-p/s1/subagents/agent-w1.jsonl",                                         # a worker in its own worktree
    [a("2026-10-05T11:00:00Z", "w1", "s1", "worktree-agent-w1", "claude-sonnet-5-5", cwd=f"{T}/rse/.claude/worktrees/agent-w1", agentId="w1", isSidechain=True),
     a("2026-10-05T11:05:00Z", "w2", "s1", "worktree-agent-w1", "claude-sonnet-5-5", cwd=f"{T}/rse/.claude/worktrees/agent-w1", agentId="w1", isSidechain=True)],
    {"agentType": "worker", "model": "sonnet"})
put(f"{T}/cc/-p/s1/subagents/agent-x1.jsonl",                                         # spawned before s1 was on the branch
    [a("2026-10-05T08:00:00Z", "x1", "s1", "main", "claude-fable-5-1", agentId="x1", isSidechain=True)],
    {"agentType": "architect"})
put(f"{T}/cc/-p/s1/subagents/agent-d1.jsonl",                                         # spawned during the detour
    [a("2026-10-05T10:40:00Z", "d1", "s1", "claude/y", "claude-sonnet-5-5", agentId="d1", isSidechain=True)],
    {"agentType": "worker"})
put(f"{T}/cc/-p/s1/subagents/agent-f1.jsonl",                                         # /finish's own reviewer
    [a("2026-10-05T12:10:00Z", "f1", "s1", "claude/x", "claude-opus-5-5", agentId="f1", isSidechain=True, attributionSkill="finish")],
    {"agentType": "reviewer-high"})
put(f"{T}/cc/-o/s3.jsonl",                                                             # another repo, same branch name
    [a("2026-10-05T10:00:00Z", "o1", "s3", "claude/x", "claude-fable-5-1", cwd=f"{T}/other")])
put(f"{T}/cc/-o/s3/subagents/agent-o2.jsonl",
    [a("2026-10-05T10:10:00Z", "o2", "s3", "claude/x", "claude-sonnet-5-5", cwd=f"{T}/other", agentId="o2", isSidechain=True)],
    {"agentType": "worker"})
put(f"{T}/cc/-q/s2/subagents/agent-r1.jsonl",                                         # another session's agent on the branch
    [a("2026-10-05T13:00:00Z", "r1", "s2", "claude/x", "claude-opus-5-5", agentId="r1", isSidechain=True)],
    {"agentType": "reviewer-high", "model": "opus"})
PY
python3 "$B/review-gate" merge --reviewer "$T/rev.txt" --code-review "$T/cr.txt" --repo "$T/rse" --no-shadow > "$T/out11.txt" 2>&1
last() { python3 -c "import json,sys; r=[json.loads(l) for l in open('$T/gate.jsonl')][-1]; $1"; }
check "$(last 'print(r["branch"], r["project"])')" "claude/x rse" "branch and project"
check "$(last 'print(r["diff"])')" "{'added': 40, 'removed': 300, 'base': 'main'}" "diff: non-doc lines added and removed (docs/ and .md left out)"
check "$(last 'print(r["findings"])')" "{'S1': 1, 'S2': 3, 'S3': 0, 'S?': 0}" "the merged list by severity"
check "$(last 'print(r["wrong"])')" "{'S1': 0, 'S2': 1, 'S3': 0, 'S?': 0}" "confirmed: the item holding the reviewer's WRONG"
check "$(last 'print(r["models"]["main"])')" "{'claude-opus-5-5': 3}" "main: on-branch calls only, de-duplicated, its worktree too, never another repo's"
check "$(last 'print([(x["type"], x["model"], x["calls"]) for x in r["models"]["agents"]])')" \
      "[('reviewer-high', 'claude-opus-5-5', 1), ('worker', 'claude-sonnet-5-5', 2)]" "agents: type from meta, model from records; left out: the earlier one, one from a detour, /finish's reviewer, another repo's"
rm -rf "$T/ud"
if [ -n "$UR" ]; then
(unset REVIEW_GATE_LOG; USAGE_DATA="$T/ud" python3 "$B/review-gate" merge --reviewer "$T/rev.txt" --code-review "$T/cr.txt" --repo "$T/rse" --no-model --no-shadow >/dev/null 2>&1)
check "$(wc -l < "$T/ud/review-gate.jsonl" 2>/dev/null | tr -d ' ')" "1" "no REVIEW_GATE_LOG: the line goes to usage-report's data folder"
else echo "  skip: usage-report not installed (G7) — the absent case is below"; fi

echo "fallbacks"
FAKE_CLAUDE_FAIL=1 python3 "$B/review-gate" merge --reviewer "$T/rev.txt" --code-review "$T/cr.txt" --repo "$R" > "$T/out2.txt" 2>&1
check "$?" "0" "a failed merge model still exits 0"
has "$T/out2.txt" "merge model failed" "and says so"
has "$T/out2.txt" "4 finding(s)" "and lists the findings, merged only where Jev was confident"
has "$T/out2.txt" "Jev's confident pairs merged all the same (4 of 4)" "…said so"
has "$T/out2.txt" "lists unmerged but for Jev's confident pairs, severity unknown" "…and the fallback line does not claim nothing merged"
echo "no json here" > "$T/cr-bad.txt"
python3 "$B/review-gate" merge --reviewer "$T/rev.txt" --code-review "$T/cr-bad.txt" --repo "$R" --no-model --no-shadow > "$T/out3.txt" 2>&1
has "$T/out3.txt" "has no JSON list; read it in full" "unparseable /code-review report is named"
echo "reviewer prose only" > "$T/rev-bad.txt"
python3 "$B/review-gate" merge --reviewer "$T/rev-bad.txt" --code-review "$T/cr.txt" --repo "$R" --no-model --no-shadow > "$T/out4.txt" 2>&1
has "$T/out4.txt" "no reviewer finding parsed" "unparseable reviewer report is named"
mkrepo "$T/$GUARD" 5 >/dev/null
: > "$T/jev.jsonl"
python3 "$B/review-gate" merge --reviewer "$T/rev.txt" --code-review "$T/cr.txt" --repo "$T/$GUARD" > "$T/out5.txt" 2>&1
has "$T/out5.txt" "review-gate: Jev shadow skipped: $GUARD is not sent to TypeSafe" "guarded repo: shadow skipped, on stderr"
check "$(wc -l < "$T/jev.jsonl" | tr -d ' ')" "0" "guarded repo: no Jev call made"

echo "the table (settings/models.json through bin/gate)"
has "$T/plan.txt" "subagent_type reviewer-high (effort: high), provider claude" "plan prints the reviewer row's provider"
has "$T/plan.txt" "code-review: subagent_type code-reviewer, provider claude" "…and the code-review row's"
cp "$T/table.json" "$T/models.json"
G() { GATE_TABLE="$T/models.json" "$GATE" "$@" >/dev/null; }
G set review-gate.same-shadow provider=off
: > "$T/jev.jsonl"
GATE_TABLE="$T/models.json" python3 "$B/review-gate" merge --reviewer "$T/rev.txt" --code-review "$T/cr.txt" --repo "$R" > "$T/out8.txt" 2>"$T/err8.txt"
has "$T/err8.txt" "review-gate: shadow off (settings/models.json review-gate.same-shadow)" "shadow row off: the note on stderr"
check "$(wc -l < "$T/jev.jsonl" | tr -d ' ')" "0" "…and no call"
has "$T/out8.txt" "1 merged · Opus medium" "…the merge itself unchanged"
G set review-gate.merge provider=off
rm -f "$T/seen.txt"
GATE_TABLE="$T/models.json" python3 "$B/review-gate" merge --reviewer "$T/rev.txt" --code-review "$T/cr.txt" --repo "$R" > "$T/out9.txt" 2>&1
has "$T/out9.txt" "⚠ merge model off in settings/models.json: lists unmerged" "merge row off: lists unmerged, said so"
check "$([ -f "$T/seen.txt" ] && echo called || echo none)" "none" "…and no claude call"
G set review-gate.merge provider=claude model=sonnet effort=low
GATE_TABLE="$T/models.json" python3 "$B/review-gate" merge --reviewer "$T/rev.txt" --code-review "$T/cr.txt" --repo "$R" > "$T/out10.txt" 2>&1
has "$T/seen.txt" "--model sonnet --effort low" "a flipped merge row is the model called"
has "$T/out10.txt" "· Sonnet low \$0.210" "…and the header names it"
G set review-gate.reviewer provider=codex
GATE_TABLE="$T/models.json" python3 "$B/review-gate" plan --repo "$T/r50" > "$T/plan3.txt" 2>&1
check "$?" "1" "plan refuses a review row it has no agent for"
has "$T/plan3.txt" "review-gate.reviewer: provider codex has no review agent here" "…saying which"
G set review-gate.reviewer provider=claude
G set review-gate.code-review provider=off when_off=skip
GATE_TABLE="$T/models.json" python3 "$B/review-gate" plan --repo "$T/r50" > "$T/plan4.txt" 2>&1
has "$T/plan4.txt" "code-review: off in settings/models.json — not spawned" "a review row off + skip: plan names no agent"

echo "real reviewer head shapes (a 2026-10-02 sweep of 9 reports lost 21 of 74 blocks)"
cat > "$T/rev2.txt" <<'EOF'
scripts/templates.py:241-257, 294 — a range then a second place
verdict: WRONG
evidence: probe

scripts/deploy.py:280 + home-assistant/tests.yaml:19 — two files
**Verdict:** WRONG

scripts/ha.py (this branch) — a parenthetical after the path
verdict: **STALE-REASON**

home-assistant/automations/living_dimmers/*.yaml — a glob
Verdict: OK-BUT

The whole approach is unverified, no path at all
verdict: UNVERIFIABLE

.claude/workflow.json:3 — a dotfile
verdict: OK-BUT

ABSPATH/f.py:7 — an absolute path
verdict: WRONG
EOF
sedi "s#ABSPATH#$T/r1000#" "$T/rev2.txt"
echo '[{"file": ".claude/workflow.json", "line": 3, "summary": "dot", "failure_scenario": "x"}]' > "$T/cr2.txt"
mkdir -p "$T/r1000/.claude" && printf 'a\nb\nc\n' > "$T/r1000/.claude/workflow.json"
python3 "$B/review-gate" merge --reviewer "$T/rev2.txt" --code-review "$T/cr2.txt" --repo "$T/r1000" --no-model --no-shadow > "$T/out6.txt" 2>&1
has "$T/out6.txt" "7 from the reviewer" "every verdict block kept, whatever its head"
has "$T/out6.txt" "scripts/templates.py:241 · reviewer" "range: file and first line"
has "$T/out6.txt" "(cites scripts/templates.py:241-257, 294)" "range: the head kept as written"
has "$T/out6.txt" "(cites scripts/deploy.py:280 + home-assistant/tests.yaml:19)" "two files: both kept"
has "$T/out6.txt" "reviewer [STALE-REASON] (cites scripts/ha.py (this branch))" "bold verdict and a parenthetical"
has "$T/out6.txt" "home-assistant/automations/living_dimmers/*.yaml · reviewer" "glob path"
has "$T/out6.txt" "S? · ? · reviewer" "no path: kept, file ?"
has "$T/out6.txt" "S? · .claude/workflow.json:3 · reviewer" "dotfile keeps its dot"
has "$T/out6.txt" "S? · f.py:7 · reviewer" "absolute path made relative"
check "$(grep -c 'cited file not in the worktree' "$T/out6.txt")" "4" "only the four fixture paths absent from the repo are flagged"
python3 "$B/review-gate" merge --reviewer "$T/nonexistent" --code-review "$T/cr2.txt" > "$T/out7.txt" 2>&1
check "$?" "0" "an unreadable report still exits 0"
has "$T/out7.txt" "⚠ cannot read" "and says so"

echo "plumb absent (G7): usage-report and tier_check not found — the default tier, the log in the core's log dir"
# A tree with the core and wharf only, and a config naming no legacy checkout.
mkdir -p "$T/tree/.claude-plugin" "$T/tree/modules" "$T/g7-cfg/regatta"; : > "$T/tree/.claude-plugin/marketplace.json"
cp -R "$M/../regatta" "$T/tree/modules/regatta"; cp -R "$M" "$T/tree/modules/wharf"
echo "$T/g7-logs" > "$T/g7-cfg/regatta/log-dir"
[ -n "$TC" ] && week 85   # a tight week tier_check would read: absent, the tiers stay normal
g7() { REGATTA_CONFIG="$T/g7-cfg" python3 "$T/tree/modules/wharf/bin/review-gate" "$@"; }
check "$(g7 plan --repo "$T/r1001" --json 2>/dev/null | python3 -c "import json,sys; p=json.load(sys.stdin); print(p['tier'], p['budget'], p['reviewer']['agent'])")" \
      "large normal reviewer" "plan with no tier_check: the default tier"
g7 plan --repo "$T/r50" > "$T/g7-plan.txt" 2>&1
has "$T/g7-plan.txt" "week not read (tier_check.py not installed)" "  and says why the week is unread"
rm -rf "$T/g7-logs"
(unset REVIEW_GATE_LOG; g7 merge --reviewer "$T/rev.txt" --code-review "$T/cr.txt" --repo "$T/rse" --no-model --no-shadow > "$T/g7-merge.txt" 2>&1)
check "$(wc -l < "$T/g7-logs/review-gate.jsonl" 2>/dev/null | tr -d ' ')" "1" "merge with no usage-report: the log line in the core's log dir"
has "$T/g7-merge.txt" "usage data folder not read (usage-report not installed)" "  said once"

echo
[ $fails = 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
