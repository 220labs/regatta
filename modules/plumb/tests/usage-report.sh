#!/usr/bin/env bash
# Tests for plumb's bin/usage-report, and the no-peer cases of every plumb file (G13, G15, G25, G35,
# G36, G37) — fixture transcripts, a fixture usage cache and app history, a pinned clock. No network,
# no model, nothing outside a scratch dir. Some cases read peers through the core's tool(): lighthouse's
# publish, wharf's fork_claude_session.py, aurora's week-digest (the fork section skips without them).   bash modules/plumb/tests/usage-report.sh
set -u
B="$(cd "$(dirname "$0")/../bin" && pwd)"   # the module's bin/; the cases below name tools beside it
peer() { python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import find_core; sys.path.insert(0, find_core.hooks()); import common; print(common.tool(sys.argv[2]) or "")' "$B/../lib" "$1"; }
PUBLISH=$(peer publish); FORK=$(peer fork_claude_session.py); WD=$(peer week-digest)
T=$(mktemp -d); trap 'chmod -R u+w "$T" 2>/dev/null; rm -rf "$T"' EXIT
# A config dir of its own, naming no overlay: the core and every peer come from this checkout
# (the public twin runs it the same), and no private value of this Mac reaches a case.
export REGATTA_CONFIG="$T/config"; mkdir -p "$T/config/lighthouse"
printf 'data:project_data\n' > "$T/config/lighthouse/shares"   # bin/publish's data share, as the cases name it
fails=0
check() { if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3: expected [$2] got [$1]"; fails=$((fails+1)); fi; }
has()   { if grep -qF -- "$2" "$1"; then echo "  ok   $3"; else echo "  FAIL $3: missing [$2]"; fails=$((fails+1)); fi; }
lacks() { if grep -qF -- "$2" "$1"; then echo "  FAIL $3: found [$2]"; fails=$((fails+1)); else echo "  ok   $3"; fi; }

export TZ=America/Los_Angeles
export USAGE_HOST=testmac USAGE_DATA="$T/data" USAGE_RENDER=1
export ACCOUNTS_FILE="$T/no-registry.json"   # the readers default to the live config dir's registry since 2026-10-22: never read it here
# the weekly ratio: a scratch file, committed by a stub that records its argv
export COST_RATIO="$T/cost-ratio.json" USAGE_KNOWLEDGE_COMMIT="$T/kc.sh"
printf '#!/bin/sh\necho "$@" >> "$(dirname "$0")/kc.txt"\n' > "$T/kc.sh"; chmod +x "$T/kc.sh"
# the tick's `account refresh` (S4): a stub the tick runs with python, recording its argv, never the real login tooling
export USAGE_ACCOUNT="$T/acct.py"; printf 'import sys\nprint("refresh: stub", sys.argv[1:])\n' > "$T/acct.py"
export USAGE_CONFIG="$T/none.json" USAGE_CC="$T/cc" USAGE_ARCHIVE="$T/archive" USAGE_CLAUDE_JSON="$T/claude.json" USAGE_APP="$T/app"
export USAGE_NOW="2026-09-20T07:10:00-07:00"
# The report is written under a scratch ~/projects and published by bin/publish to a scratch NAS and Drive
export USAGE_LOCAL_REPORTS="$T/projects/usage/reports" USAGE_PUBLISH=data
export PUBLISH_PROJECTS="$T/projects" PUBLISH_NAS="$T/nas" PUBLISH_DRIVE="$T/drive" PUBLISH_STATE="$T/pstate"
mkdir -p "$T/nas/project_data" "$T/drive/project_data"
RP="$T/projects/usage/reports"; SH="usage/reports"
mkdir -p "$T/cc/-proj/sess1/subagents" "$T/archive/proj" "$T/app"

python3 - "$T" <<'PY'
import json, sys
T = sys.argv[1]
def a(ts, req, sid, model, inp, out, cr, cw1, **kw):
    d = {"type": "assistant", "timestamp": ts, "requestId": req, "sessionId": sid, "uuid": req + "u",
         "cwd": "/Users/x/projects/harbor/.claude/worktrees/topic", "entrypoint": "claude-vscode", "effort": "high",
         "message": {"model": model, "usage": {"input_tokens": inp, "output_tokens": out, "cache_read_input_tokens": cr,
                     "cache_creation_input_tokens": cw1, "cache_creation": {"ephemeral_1h_input_tokens": cw1, "ephemeral_5m_input_tokens": 0}}}}
    d.update(kw); return json.dumps(d)
L = [
  json.dumps({"type": "ai-title", "sessionId": "sess1", "aiTitle": "Kids wake tuning"}),
  # 2026-09-19 local (UTC 19th 17:00 = 10:00 PDT): one call streamed as three blocks, the last carries the full output
  a("2026-09-19T17:00:00Z", "r1", "sess1", "claude-fable-5-1", 2, 10, 300000, 1000),
  a("2026-09-19T17:00:00Z", "r1", "sess1", "claude-fable-5-1", 2, 10, 300000, 1000),
  a("2026-09-19T17:00:00Z", "r1", "sess1", "claude-fable-5-1", 2, 2000, 300000, 1000),
  a("2026-09-19T18:00:00Z", "r2", "sess1", "claude-opus-5", 0, 1000, 500000, 0, attributionSkill="finish"),
  # 2026-09-20 03:00 UTC = 09-19 20:00 local: same local day
  a("2026-09-20T03:00:00Z", "r3", "sess1", "claude-opus-5", 0, 100, 100000, 0),
  # 2026-09-20 local: not yesterday
  a("2026-09-20T15:00:00Z", "r4", "sess1", "claude-opus-5", 0, 100, 100000, 0),
  a("2026-09-19T17:30:00Z", "r5", "sess1", "claude-mystery-9", 0, 1000, 0, 0),
  json.dumps({"type": "assistant", "timestamp": "2026-09-19T17:31:00Z", "requestId": "r6", "sessionId": "sess1",
              "message": {"model": "<synthetic>", "usage": {"input_tokens": 0, "output_tokens": 0}}}),
  json.dumps({"type": "cost-state", "sessionId": "sess1", "totalCostUSD": 1.0, "modelUsage": {
      "claude-fable-5-1": {"inputTokens": 1000000, "outputTokens": 0, "cacheReadInputTokens": 0, "cacheCreationInputTokens": 0, "costUSD": 10.0}}}),
]
open(f"{T}/cc/-proj/sess1.jsonl", "w").write("\n".join(L) + "\n")
# the archive holds a copy of the same session: nothing may count twice
open(f"{T}/archive/proj/2026-09-19-sess1.jsonl", "w").write("\n".join(L) + "\n")
sub = [a("2026-09-19T17:10:00Z", "r9", "sess1", "claude-opus-5", 0, 50, 10000, 0, agentId="ag1", isSidechain=True)]
open(f"{T}/cc/-proj/sess1/subagents/agent-ag1.jsonl", "w").write("\n".join(sub) + "\n")
json.dump({"agentType": "reviewer"}, open(f"{T}/cc/-proj/sess1/subagents/agent-ag1.meta.json", "w"))
# plan cache, as Claude Code writes it
json.dump({"cachedUsageUtilization": {"fetchedAtMs": 1790000000000, "utilization": {
  "limits": [{"kind": "session", "percent": 11, "resets_at": "x"}, {"kind": "weekly_all", "percent": 64},
             {"kind": "weekly_scoped", "percent": 80, "scope": {"model": {"display_name": "Fable"}}}],
  "extra_usage": {"is_enabled": False, "user_disabled": True, "spend_limit_reached": False},
  "spend": {"used": {"amount_minor": 0, "exponent": 2}},
  "seven_day_breakdown": {"rows": [{"key": "claude_code", "percent": 42}, {"key": "cowork", "percent": 58}]}}}},
  open(f"{T}/claude.json", "w"))
# the app's 15-minute history: weekly at 100 from 18:00 to 19:00 local on 09-19, then extra usage capped
ms = lambda s: int(__import__("datetime").datetime.fromisoformat(s).timestamp() * 1000)
samples = [{"t": ms("2026-09-19T17:45:00-07:00"), "u": {"fh": 40, "sd": 99}},
           {"t": ms("2026-09-19T18:00:00-07:00"), "u": {"fh": 50, "sd": 100}},
           {"t": ms("2026-09-19T19:00:00-07:00"), "u": {"fh": 60, "sd": 100}},
           {"t": ms("2026-09-19T19:15:00-07:00"), "u": {"fh": 60, "sd": 99, "xu": 100}},
           {"t": ms("2026-09-19T19:30:00-07:00"), "u": {"fh": 0, "sd": 0, "xu": 100}}]
json.dump({"version": 2, "samples": samples}, open(f"{T}/app/plan-usage-history.json", "w"))
PY

echo "collect"
"$B/usage-report" collect --days 3 > "$T/collect.out"
F="$T/data/testmac/calls/2026-09-19.csv"
check "$(test -f "$F" && echo yes)" "yes" "a CSV per local day"
py() { python3 -c "import csv,sys; rows=list(csv.DictReader(open('$F'))); $1"; }
# work-account E6: a session hooks/sync.py recorded on the work login gets that account; the rest none
S1=$(py "print(rows[0]['session'])")
echo "{\"session\": \"$S1\", \"account\": \"work\", \"t\": 1}" > "$T/data/testmac/accounts.jsonl"
"$B/usage-report" collect --days 3 > /dev/null
check "$(py "print(sorted(set((r['session'] == '$S1', r['account']) for r in rows)))")" "[(True, 'work')]" "collect: the account column from accounts.jsonl (E6)"
rm "$T/data/testmac/accounts.jsonl"; "$B/usage-report" collect --days 3 > /dev/null
check "$(py "print(sorted(set(r['account'] for r in rows)))")" "['']" "  …and empty where none was recorded"
check "$(py 'print(sum(int(r["calls"]) for r in rows))')" "5" "09-19 has 5 calls: stream de-duplicated, archive copy ignored, synthetic dropped, 20:00 local kept"
check "$(py 'print([r["output"] for r in rows if r["model"]=="claude-fable-5-1"][0])')" "2000" "the streamed call keeps its final output count"
check "$(py 'print([r["title"] for r in rows][0])')" "Kids wake tuning" "title from ai-title"
check "$(py 'print(rows[0]["project"])')" "harbor" "worktree calls file with the main checkout"
check "$(py 'print(sorted({r["agent"] for r in rows}))')" "['main', 'reviewer']" "subagent typed from its meta file"
check "$(py 'print([r["skill"] for r in rows if r["skill"]])')" "['finish']" "skill attribution kept"
check "$(py 'print(rows[0]["host"])')" "testmac" "host is a column"
check "$(py 'print(round(sum(float(r["cost"]) for r in rows if r["model"]=="claude-fable-5-1"),4))')" "0.195" "fable priced: 300k read + 1k 1h-write + 2k out"
check "$(py 'print(sum(int(r["calls_over_400k"]) for r in rows))')" "1" "context above 400k counted"
check "$(test -f "$T/data/testmac/calls/2026-09-20.csv" && echo yes)" "yes" "today's calls land in today's file"
check "$(python3 -c "import json;d=json.load(open('$T/data/testmac/calibration.json'));print(d['table'],d['claude_code'],d['unknown_models'])")" "10.0 10.0 ['claude-mystery-9']" "calibration prices Claude Code's own tokens; unknown model named"

echo "sample"
"$B/usage-report" sample > /dev/null
check "$(wc -l < "$T/data/testmac/limits.jsonl" | tr -d ' ')" "6" "one cache sample + five app samples"
"$B/usage-report" sample > /dev/null
check "$(wc -l < "$T/data/testmac/limits.jsonl" | tr -d ' ')" "6" "sampling again adds nothing"

echo "render"
"$B/usage-report" render > "$T/r1.out"
R="$RP/2026-09-19.md"
has "$R" "# Claude usage — 2026-09-19" "yesterday by default"
has "$R" "weekly at 100% from 18:00 to 19:00" "the weekly hit, from the app's samples"
has "$R" "extra-usage cap at 100% from 19:15 to 19:30" "the extra-usage cap, too"
has "$R" "5-hour 11%, weekly 64%, weekly Fable 80%; extra usage off (you switched it off)" "plan state from the cache"
has "$R" "Claude Code 42%, Cowork 58%" "surface split"
has "$R" "Kids wake tuning (testmac)" "sessions carry the host"
has "$R" "| reviewer |" "agent table"
has "$R" "| finish |" "skill table"
has "$R" "priced at Opus rates, model not in the table: claude-mystery-9" "unknown model surfaced"
has "$R" "+0.0%" "calibration line"
check "$(wc -l < "$RP/latest-line.txt" | tr -d ' ')" "1" "one line"
has "$RP/latest-line.txt" "Hit: extra-usage cap, weekly." "the line names the hits"
has "$RP/latest-line.txt" "weekly Fable 80%" "the line carries the Fable limit"
cmp -s "$R" "$RP/latest.md" && echo "  ok   latest.md is the same report" || { echo "  FAIL latest.md"; fails=$((fails+1)); }

echo "render — published through bin/publish, to Drive only (TODO 1 (2), 2026-10-19)"
for f in 2026-09-19.md latest.md latest-line.txt; do
  cmp -s "$RP/$f" "$T/drive/project_data/$SH/$f" && ! test -e "$T/nas/project_data/$SH/$f" \
    && echo "  ok   $f in Drive at its place under ~/projects, not on the NAS" || { echo "  FAIL $f not published to Drive alone"; fails=$((fails+1)); }
done
has "$T/r1.out" "published project_data/$SH/latest-line.txt → drive" "the log says where it went"
lacks "$T/r1.out" "→ nas" "…and the NAS is not tried"
USAGE_PUBLISH= "$B/usage-report" render --day 2026-09-19 > "$T/r0.out"
lacks "$T/r0.out" "publish" "no scope configured: not published"
USAGE_PUBLISH=everyone "$B/usage-report" render --day 2026-09-19 > "$T/r0.out"
has "$T/r0.out" "not a scope" "a wrong scope is named, not guessed"

echo "render — Drive not there"
mv "$T/drive/project_data" "$T/drive/away"
"$B/usage-report" render > "$T/r2.out" 2>&1; rc=$?
check "$rc" "0" "the run goes on"
has "$T/r2.out" "$SH/latest.md → drive queued:" "the log names what is queued"
check "$(test -e "$T/drive/project_data" && echo yes || echo no)" "no" "the shared drive is not created in its place"
mv "$T/drive/away" "$T/drive/project_data"
"$PUBLISH" --retry > "$T/r2b.out"
has "$T/r2b.out" "retry: 3 delivered" "publish --retry delivers them once Drive is back"

echo "render — a Drive file the job may not rewrite"
chmod 555 "$T/drive/project_data/$SH"
"$B/usage-report" render > "$T/r3.out" 2>&1; rc=$?
check "$rc" "0" "does not crash the run"
has "$T/r3.out" "Drive refused rewriting $SH/latest.md" "…and the log names the file"
chmod 755 "$T/drive/project_data/$SH"
"$PUBLISH" --retry > /dev/null

echo "tick"
rm -f "$T/data/testmac/.rendered-"* "$RP/"*
cat > "$T/notify.sh" <<'SH'
#!/bin/sh
echo "$@" > "$(dirname "$0")/sent.txt"
SH
chmod +x "$T/notify.sh"
printf '{"hosts": {"testmac": {"render": true, "notify": ["%s"]}}}' "$T/notify.sh" > "$T/cfg.json"
USAGE_CONFIG="$T/cfg.json" USAGE_NOW="2026-09-20T06:50:00-07:00" "$B/usage-report" tick > "$T/tick1.out"
check "$(ls "$RP" 2>/dev/null | wc -l | tr -d ' ')" "0" "before 07:05 the tick only samples"
has "$T/tick1.out" "refresh: stub ['refresh']" "every tick first refreshes the hooks' local copies of the Drive-backed files (account refresh, S4)"
USAGE_CONFIG="$T/cfg.json" USAGE_NOW="2026-09-20T07:10:00-07:00" "$B/usage-report" tick > "$T/tick2.out"
has "$T/tick2.out" "notify: sent" "after 07:05 it renders and sends"
has "$T/tick2.out" "published project_data/$SH/2026-09-19.md → drive" "the log says where the report went"
has "$T/sent.txt" "Claude 09-19:" "the line is what gets sent"
USAGE_CONFIG="$T/cfg.json" USAGE_NOW="2026-09-20T07:25:00-07:00" "$B/usage-report" tick > "$T/tick3.out"
lacks "$T/tick3.out" "notify" "once a day, not every tick"
USAGE_RENDER=0 USAGE_NOW="2026-09-21T09:00:00-07:00" "$B/usage-report" tick > "$T/tick4.out"
has "$T/tick4.out" "does not render" "a collector-only host never renders"
# two failed days in a row post one bulletin line (dream 2026-09-27 P5)
printf '{"hosts": {"testmac": {"render": true, "notify": ["/usr/bin/false"]}}}' > "$T/cfg-fail.json"
export CLAUDE_BULLETIN="$T/bulletin.md"
USAGE_CONFIG="$T/cfg-fail.json" USAGE_NOW="2026-09-21T07:10:00-07:00" "$B/usage-report" tick > /dev/null
check "$(test -f "$T/bulletin.md" && echo yes || echo no)" "no" "one failed day posts nothing"
USAGE_CONFIG="$T/cfg-fail.json" USAGE_NOW="2026-09-22T07:10:00-07:00" "$B/usage-report" tick > /dev/null
check "$(grep -c 'notify FAILED two days running' "$T/bulletin.md" 2>/dev/null)" "1" "the second posts one bulletin line"
unset CLAUDE_BULLETIN

echo "numbers"
check "$(USAGE_NOW=2026-09-20T09:00:00-07:00 "$B/usage-report" numbers --json | python3 -c 'import json,sys;d=json.load(sys.stdin);print(sorted(d["limit_hits"].items()))')" "[('extra-usage cap', 1), ('weekly', 1)]" "weekly numbers count hits by limit"

echo "numbers — tier mix and WRONG per 100 lines (model routing section 7, S-E)"
# the review gate's log, as bin/review-gate writes it beside the usage data: a line from before S-E,
# a worker-built branch merged twice (the later run counts), two branches without a worker
python3 - "$T/data/review-gate.jsonl" <<'PY'
import json, sys
def rec(ts, branch, added, removed, wrong, agents):
    return {"ts": ts, "repo": "/r/proj", "project": "proj", "branch": branch, "diff": {"added": added, "removed": removed},
            "findings": wrong, "wrong": wrong, "models": {"main": {"claude-opus-5-5": 9}, "agents": agents}}
w = [{"type": "worker", "model": "claude-sonnet-5-5", "agents": 1, "calls": 40}]
r = [{"type": "reviewer-high", "model": "claude-opus-5-5", "agents": 1, "calls": 20}]
L = [{"ts": "2026-10-04T10:00:00-0700", "repo": "/r/proj", "branch": "claude/old", "reviewer": 3},
     rec("2026-10-05T10:00:00-0700", "claude/a", 150, 50, {"S1": 1, "S2": 1, "S3": 0, "S?": 0}, w),
     rec("2026-10-05T11:00:00-0700", "claude/a", 150, 50, {"S1": 0, "S2": 1, "S3": 0, "S?": 0}, w),
     rec("2026-10-05T12:00:00-0700", "claude/b", 300, 100, {"S1": 0, "S2": 1, "S3": 0, "S?": 0}, r),
     rec("2026-10-05T13:00:00-0700", "claude/c", 100, 0, {"S1": 0, "S2": 0, "S3": 0, "S?": 0}, []),
     rec("2026-10-05T14:00:00-0700", "claude/d", 0, 0, {"S1": 0, "S2": 2, "S3": 0, "S?": 0}, w),  # skills-only: 0 non-doc lines
     dict(rec("2026-10-05T15:00:00-0700", "claude/e", 50, 0, {"S1": 0, "S2": 1, "S3": 0, "S?": 0}, []), models={"error": "x"})]
open(sys.argv[1], "w").write("\n".join(json.dumps(x) for x in L) + "\n")
PY
USAGE_NOW=2026-09-20T09:00:00-07:00 "$B/usage-report" numbers --json > "$T/n.json"
nj() { python3 -c "import json; d=json.load(open('$T/n.json')); $1"; }
check "$(nj 'print(sorted(t["tier"] for t in d["tier_mix"]["tiers"]))')" "['main · fable-5-1', 'main · mystery-9', 'main · opus-5', 'reviewer']" "tiers: main by model, the reviewer agent as reviewer"
check "$(nj 'print(round(sum(t["share"] for t in d["tier_mix"]["tiers"])))')" "100" "the shares add up"
check "$(nj 'f=d["tier_mix"]["fable_main"]; print(f["usd"] > 0, f["usd"] == f["outside_weekly_usd"])')" "True True" "Fable in main: no weekly skill ran, so all of it is outside"
check "$(nj 'q=d["branch_quality"]; print(q["with_worker"])')" "{'n': 1, 'doc_only': 1, 'changed_lines': 200, 'wrong': 1, 'wrong_per_100': 0.5}" "worker-built: the later run of a branch counts, the pre-S-E line is skipped, a 0-line branch stays out of the rate"
check "$(nj 'q=d["branch_quality"]; print(q["without_worker"])')" "{'n': 2, 'doc_only': 0, 'changed_lines': 500, 'wrong': 1, 'wrong_per_100': 0.2}" "without a worker: pooled over branches, with n; an unreadable-transcripts line joins neither"
USAGE_NOW=2026-09-20T09:00:00-07:00 "$B/usage-report" numbers > "$T/n.txt"
has "$T/n.txt" "| main · fable-5-1 |" "the text form prints the tier table"
has "$T/n.txt" "Fable in main sessions:" "…the Fable line"
has "$T/n.txt" "with worker 0.50 (n=1, 1 WRONG in 200 lines); without 0.20 (n=2, 1 WRONG in 500 lines)" "…and WRONG per 100 lines with n"
python3 - "$B/usage-report" > "$T/mix.txt" <<'PY'
import sys
from importlib.machinery import SourceFileLoader
u = SourceFileLoader("usage_report", sys.argv[1]).load_module()
row = lambda sess, agent, model, skill, cost: {"session": sess, "agent": agent, "model": model, "skill": skill, "cost": cost}
m = u.tier_mix([row("s1", "main", "claude-fable-5-1", "sextant", 10), row("s1", "main", "claude-fable-5-1", "", 5),
                row("s2", "main", "claude-fable-5-1", "", 15), row("s2", "worker", "claude-sonnet-5-5", "", 20),
                row("s2", "sr-architect", "claude-fable-5-1", "", 30), row("s3", "general-purpose", "claude-opus-5-5", "", 20)])
print(sorted((t["tier"], t["share"]) for t in m["tiers"]))
print(m["fable_main"])
print(u.tier_of(row("s4", "general-purpose", "claude-opus-5-5", "code-review", 1)))
PY
check "$(sed -n 1p "$T/mix.txt")" "[('architect', 30.0), ('main · fable-5-1', 30.0), ('other agents', 20.0), ('worker', 20.0)]" "sr-architect counts as architect, an unnamed agent as other"
check "$(sed -n 2p "$T/mix.txt")" "{'usd': 30, 'share': 30.0, 'outside_weekly_usd': 15, 'outside_weekly_share': 15.0}" "a weekly skill's whole session is inside the weekly skills"
check "$(sed -n 3p "$T/mix.txt")" "reviewer" "the forked /code-review (general-purpose) counts as reviewer"
has "$RP/2026-09-19.md" "### Tier mix, last 7 days" "the daily report carries the tier mix"

echo "two logins — the app on a spent Max, Claude Code on a Pro backup (2026-09-26)"
mkdir -p "$T/app2" "$T/rp2"
python3 - "$T" <<'PY'
import json, sys, datetime
T = sys.argv[1]
ms = lambda s: int(datetime.datetime.fromisoformat(s).timestamp() * 1000)
def cj(name, uuid, oa, at, session, weekly):
    json.dump({"oauthAccount": dict(accountUuid=uuid, **oa), "cachedUsageUtilization": {"fetchedAtMs": ms(at), "accountUuid": uuid,
      "utilization": {"limits": [{"kind": "session", "percent": session}, {"kind": "weekly_all", "percent": weekly}],
                      "extra_usage": {"is_enabled": False}}}}, open(f"{T}/{name}", "w"))
cj("max.json", "aaaaaaaa-1111", {"organizationType": "claude_max", "organizationRateLimitTier": "default_claude_max_20x"}, "2026-09-26T08:15:00-07:00", 40, 100)
cj("pro1.json", "bbbbbbbb-2222", {"organizationType": "claude_pro", "organizationRateLimitTier": "default_claude_ai"}, "2026-09-26T09:00:00-07:00", 0, 31)
cj("pro2.json", "bbbbbbbb-2222", {"organizationType": "claude_pro", "organizationRateLimitTier": "default_claude_ai"}, "2026-09-27T09:00:00-07:00", 0, 33)
# a stale login: the cache still holds the old account while the profile is the new one — no plan claimed
cj("stale.json", "cccccccc-3333", {}, "2026-09-26T09:10:00-07:00", 0, 5)
d = json.load(open(f"{T}/stale.json")); d["oauthAccount"]["accountUuid"] = "dddddddd-4444"; json.dump(d, open(f"{T}/stale.json", "w"))
app = [{"t": ms(f"2026-09-26T{h}-07:00"), "u": {"fh": 3, "sd": 100}} for h in ("08:10:00", "08:25:00", "08:40:00", "09:10:00", "10:00:00")]
app.append({"t": ms("2026-09-27T09:00:00-07:00"), "u": {"fh": 3, "sd": 100}})
json.dump({"version": 2, "samples": app}, open(f"{T}/app2/plan-usage-history.json", "w"))
PY
two() { USAGE_DATA="$T/d2" USAGE_APP="$T/app2" USAGE_LOCAL_REPORTS="$T/rp2" USAGE_PUBLISH= "$@"; }
for f in max pro1 stale; do USAGE_CLAUDE_JSON="$T/$f.json" two "$B/usage-report" sample > /dev/null; done
check "$(python3 -c "import json;r=[json.loads(l) for l in open('$T/d2/testmac/limits.jsonl') if '\"cache\"' in l];print([(x['account'],x['plan']) for x in r])")" \
  "[('aaaaaaaa', 'Max 20x'), ('bbbbbbbb', 'Pro'), ('cccccccc', None)]" "each Claude Code sample names its account and plan; a stale cache claims no plan"
USAGE_CLAUDE_JSON="$T/pro1.json" USAGE_NOW="2026-09-27T07:10:00-07:00" two "$B/usage-report" render > /dev/null
R2="$T/rp2/2026-09-26.md"
has "$R2" "weekly (Max 20x) at 100% from Sat 09-26 08:10 to Sun 09-27 09:00" "the app's run and the Max account's sample are one hit, named for the account"
lacks "$R2" "weekly at 100%" "the Pro percentages no longer break the Max run into pieces"
has "$R2" "**Plan now, cccccccc** (09-26 09:10): 5-hour 0%, weekly 5%" "an account with no plan goes by its id"
has "$R2" "**Plan now, Pro** (09-26 09:00): 5-hour 0%, weekly 31%" "Plan now per account, newest first"
has "$R2" "**Plan now, Max 20x** (09-26 08:15): 5-hour 40%, weekly 100%" "…the Max account too"
lacks "$R2" "Plan now, Claude app" "the app agrees with an account shown: no line of its own"
has "$T/rp2/latest-line.txt" "cccccccc: 5h 0%, weekly 5%; Pro: 5h 0%, weekly 31%; Max 20x: 5h 40%, weekly 100%." "the line carries every login"
USAGE_CLAUDE_JSON="$T/pro2.json" two "$B/usage-report" sample > /dev/null
USAGE_CLAUDE_JSON="$T/pro2.json" USAGE_NOW="2026-09-28T07:10:00-07:00" two "$B/usage-report" render > /dev/null
R3="$T/rp2/2026-09-27.md"
lacks "$R3" "Plan now, Max 20x" "a day-old account is not shown as current"
has "$R3" "**Plan now, Claude app** (09-27 09:00): 5-hour 3%, weekly 100% (the app's own login)." "the app on another login gets its own line"
has "$R3" "**Plan now, Pro** (09-27 09:00): 5-hour 0%, weekly 33%" "…beside the Pro account"

echo "a stale cache beside the app's fresh sample of the same organisation (TODO 2, 2026-09-29)"
mkdir -p "$T/app3" "$T/rp3"
python3 - "$T" <<'PY'
import json, sys, datetime
T = sys.argv[1]
ms = lambda s: int(datetime.datetime.fromisoformat(s).timestamp() * 1000)
json.dump({"oauthAccount": {"accountUuid": "eeeeeeee-5555", "organizationUuid": "11111111-aaaa", "organizationType": "claude_max",
                            "organizationRateLimitTier": "default_claude_max_20x"},
           "cachedUsageUtilization": {"fetchedAtMs": ms("2026-09-27T16:00:00-07:00"), "accountUuid": "eeeeeeee-5555",
             "utilization": {"limits": [{"kind": "session", "percent": 0}, {"kind": "weekly_all", "percent": 0}]}}},
          open(f"{T}/stale-max.json", "w"))
app = [{"t": ms("2026-09-29T08:55:00-07:00"), "org": "11111111-aaaa", "u": {"fh": 4, "sd": 22}},
       {"t": ms("2026-09-29T08:50:00-07:00"), "org": "22222222-bbbb", "u": {"fh": 9, "sd": 70}}]
json.dump({"version": 2, "samples": app}, open(f"{T}/app3/plan-usage-history.json", "w"))
PY
three() { USAGE_DATA="$T/d3" USAGE_APP="$T/app3" USAGE_LOCAL_REPORTS="$T/rp3" USAGE_PUBLISH= USAGE_CLAUDE_JSON="$T/stale-max.json" "$@"; }
three "$B/usage-report" sample > /dev/null
check "$(python3 -c "import json;print(sorted({json.loads(l)['org'] for l in open('$T/d3/testmac/limits.jsonl')}))")" \
  "['11111111', '22222222']" "samples record the organisation, an id prefix only"
USAGE_NOW="2026-09-29T09:00:00-07:00" three "$B/usage-report" numbers --json > "$T/n3.json"
check "$(python3 -c "import json;print(json.load(open('$T/n3.json'))['limits_now'])")" \
  "Max 20x: 5-hour 4%, weekly 22% (5 min old)" \
  "plan now: the app's fresher sample of the same organisation stands in for the 41 h old cache, with its age (the app's older sample of another login is not current)"
USAGE_NOW="2026-09-30T07:10:00-07:00" three "$B/usage-report" render > /dev/null
has "$T/rp3/2026-09-29.md" "**Plan now, Max 20x** (09-29 08:55): 5-hour 4%, weekly 22% (the app's sample, fresher than Claude Code's)." "…and the report says whose sample it is"
lacks "$T/rp3/2026-09-29.md" "weekly 0%" "…the stale 0% is not shown as current"
check "$(python3 - "$B" <<'PY'
import sys
from importlib.machinery import SourceFileLoader as L
ur = L("ur", sys.argv[1] + "/usage-report").load_module()
lim = lambda w: {"weekly_all": {"percent": w}, "session": {"percent": 1}}
S = [{"src": "cache", "t": 1000, "host": "h", "account": "aaaaaaaa", "plan": "Max 20x", "org": "11111111", "limits": lim(0)},
     {"src": "cache", "t": 2000, "host": "h", "account": "bbbbbbbb", "plan": "Max 5x", "org": "11111111", "limits": lim(5)},
     {"src": "app", "t": 9000, "host": "h", "org": "11111111", "five_hour": 4, "weekly": 22}]
print(sorted(x["src"] for _, x in ur.plan_now(S)))
PY
)" "['cache', 'cache']" "two logins in one organisation: the app's sample stands in for neither (usage is per login)"

echo "accounts — a second config dir's cache and its exhaustion log (multi-account design E5)"
AD="$T/acct-t"; mkdir -p "$AD"
python3 - "$T" <<'PY'
import datetime as d, json, sys
T = sys.argv[1]
ms = lambda s: int(d.datetime.fromisoformat(s).timestamp() * 1000)
json.dump({"oauthAccount": {"accountUuid": "dddddddd-1", "organizationType": "claude_pro"},
           "cachedUsageUtilization": {"accountUuid": "dddddddd-1", "fetchedAtMs": ms("2026-09-26T11:00:00-07:00"),
                                      "utilization": {"limits": [{"kind": "session", "percent": 20}, {"kind": "weekly_all", "percent": 60}]}}},
          open(f"{T}/acct-t/.claude.json", "w"))
open(f"{T}/acct-t/exhaustion.jsonl", "w").write(json.dumps(
    {"at": ms("2026-09-26T10:30:00-07:00") / 1000, "window": "five_hour", "resets_at": 0, "account": "dddddddd"}) + "\n")
PY
USAGE_ACCOUNT_DIRS="$AD" USAGE_CLAUDE_JSON="$T/pro1.json" two "$B/usage-report" sample > /dev/null
USAGE_ACCOUNT_DIRS="$AD" USAGE_CLAUDE_JSON="$T/pro1.json" two "$B/usage-report" sample > /dev/null
check "$(grep -c '"account": "dddddddd"' "$T/d2/testmac/limits.jsonl")" 2 "the other dir's cache and its exhaustion are sampled, once each"
USAGE_CLAUDE_JSON="$T/pro1.json" USAGE_NOW="2026-09-27T07:10:00-07:00" two "$B/usage-report" render > /dev/null
has "$T/rp2/2026-09-26.md" "5-hour (Pro) at 100% from 10:30 to 10:30" "an exhaustion is a limit episode, named for its login"

echo
echo "forks — what a fork inherited counts once (teleport design E1, 2026-10-02)"
# the fork maker is wharf's and the digest aurora's: a copy without either (the public twin while
# wharf is private) skips the section in one line
if [ -z "$FORK" ] || [ -z "$WD" ]; then echo "  skip: fork_claude_session.py (wharf) or week-digest (aurora) not in this copy"; else
FK="$T/fork"; mkdir -p "$FK/cc/-proj" "$FK/cc/-other"
python3 - "$FK" "$FORK" > "$FK/made.out" 2> "$FK/made.err" <<'PY'
import importlib.util as u, json, sys
from pathlib import Path
FK, fork = Path(sys.argv[1]), sys.argv[2]
spec = u.spec_from_file_location("f", fork); m = u.module_from_spec(spec); spec.loader.exec_module(m)
def a(ts, req, sid, out):
    return json.dumps({"type": "assistant", "timestamp": ts, "requestId": req, "sessionId": sid, "uuid": req + "u",
                       "cwd": "/Users/x/projects/harbor", "message": {"model": "claude-opus-5", "usage": {"input_tokens": 0, "output_tokens": out}}})
src = FK / "cc/-proj/src.jsonl"
src.write_text("\n".join([a("2026-09-19T17:00:00.000Z", "q1", "src", 100), a("2026-09-19T18:00:00.000Z", "q2", "src", 100),
    json.dumps({"type": "bridge-session", "sessionId": "src"}),
    a("2026-09-19T19:00:00.000Z", "q3", "src", 100),
    json.dumps({"type": "cost-state", "sessionId": "src", "startTime": 1790000000000}),   # after the cut: stays behind
    json.dumps({"type": "ai-title", "sessionId": "src", "aiTitle": "t"})]) + "\n")           # a title always goes
# a fork cut after q2, made on another host and carried here: that host counts q1 and q2
m.fork_transcript(src, FK / "cc/-other", "fk", cutoff="2026-09-19T18:00:00.000Z", origin="peer")
f = FK / "cc/-other/fk.jsonl"
with f.open("a") as fh:
    fh.write(a("2026-09-19T20:00:00.000Z", "q4", "fk", 100) + "\n")
src.rename(FK / "src.jsonl.away")   # the source lives on the other host
# an old fork, made before the record existed: the same requestId under a new session id
# — read first and titled as a fork, so the tie goes to its source
(FK / "cc/-proj/old.jsonl").write_text(json.dumps({"type": "ai-title", "sessionId": "oldfork", "aiTitle": "\U0001f500 fork · x"}) + "\n"
                                       + a("2026-09-19T21:00:00.000Z", "q5", "oldfork", 100) + "\n"
                                       + a("2026-09-19T21:00:00.000Z", "q5", "home", 100) + "\n")
recs = [json.loads(l) for l in f.read_text().splitlines()]
ff = [r for r in recs if r["type"] == "forked-from"][0]
try:
    m.fork_transcript(FK / "src.jsonl.away", FK / "x", "bad", cutoff="2026-09-19T18:00:00+00:00")
except ValueError:
    print("refused", file=sys.stderr)
print(" ".join(r["type"] + ":" + r.get("requestId", "-") for r in recs))
print(ff["sessionId"], ff["from"]["sessionId"], ff["from"]["host"], ff["cutoff"], ff["records"])
PY
check "$(sed -n 1p "$FK/made.out")" "assistant:q1 assistant:q2 ai-title:- forked-from:- assistant:q4" \
  "fork_transcript cuts at the first record past the cutoff (titles still go), drops bridge-session, ends with forked-from"
check "$(cat "$FK/made.err")" "refused" "  a cutoff in another ISO spelling is refused, not misordered"
check "$(sed -n 2p "$FK/made.out")" "fk src peer 2026-09-19T18:00:00.000Z 3" "  the record names both ids, the host, the cutoff and the count"
USAGE_CC="$FK/cc" USAGE_ARCHIVE="$FK/none" USAGE_DATA="$FK/data" "$B/usage-report" collect --days 3 > /dev/null
FF="$FK/data/testmac/calls/2026-09-19.csv"
check "$(python3 -c "import csv; print(sum(int(r['calls']) for r in csv.DictReader(open('$FF'))))")" "2" \
  "a fork's inherited calls are skipped, its own call counts, an old fork's copy counts once"
check "$(python3 -c "import csv; print(sorted({r['session'][:8] for r in csv.DictReader(open('$FF'))}))")" "['fk', 'home']" \
  "  each call stays with the session that made it"
mkdir -p "$FK/wd/proj"; cp "$FK/cc/-other/fk.jsonl" "$FK/wd/proj/"
check "$(HOME="$FK/wd-home" python3 - "$WD" "$FK/wd/proj/fk.jsonl" <<'PY'
import importlib.machinery as im, importlib.util as u, json, sys
loader = im.SourceFileLoader("wd", sys.argv[1]); m = u.module_from_spec(u.spec_from_loader("wd", loader)); loader.exec_module(m)
from pathlib import Path
p = Path(sys.argv[2]); lines = p.read_text().splitlines()
def h(ts, text): return json.dumps({"type": "user", "timestamp": ts, "sessionId": "fk", "origin": {"kind": "human"}, "message": {"content": text}})
lines.insert(0, h("2026-09-19T16:59:00.000Z", "inherited")); lines.append(h("2026-09-19T20:01:00.000Z", "mine"))
p.write_text("\n".join(lines) + "\n")
print([t for _, t in m.prompts(p)[2]])
PY
)" "['mine']" "week-digest skips the prompts a fork inherited"
fi

echo
echo "ratio — list to effective, weekly (the owner, 2026-10-04 and 2026-10-05)"
RD="$T/rdata/testmac/calls"; mkdir -p "$RD"
hdr="day,host,source,session,title,project,model,effort,skill,agent,entry,calls,input,output,cache_read,cache_write_5m,cache_write_1h,calls_over_200k,calls_over_400k,cost,first,last"
for d in 2026-09-10:900 2026-09-22:1000 2026-09-27:1000 2026-09-29:1500 2026-10-04:500 2026-10-05:7777; do
  printf '%s\n%s,testmac,cc,s,t,p,m,high,,,,1,0,0,0,0,0,0,0,%s,%sT18:00:00Z,%sT19:00:00Z\n' "$hdr" "${d%%:*}" "${d##*:}" "${d%%:*}" "${d%%:*}" >"$RD/${d%%:*}.csv"
done
rm -f "$COST_RATIO" "$T/kc.txt"
USAGE_DATA="$T/rdata" USAGE_NOW="2026-10-05T09:00:00-07:00" "$B/usage-report" ratio > "$T/ratio1.out"
has "$T/ratio1.out" 'ratio: list × 0.0230 — $46.00 a week over an average $2,000 of list spend (2 weeks to 2026-10-04)' "two complete Mon–Sun weeks on the plan; the Pro week and today left out"
# work-account E6: a work-login session on the second Mac is not this plan's week
mkdir -p "$T/rdata/buildbox/calls"
printf '%s,account\n2026-09-29,buildbox,cc,sf,t,p,m,high,,,,1,0,0,0,0,0,0,0,3000,2026-09-29T18:00:00Z,2026-09-29T19:00:00Z,work\n2026-09-29,buildbox,cc,s4,t,p,m,high,,,,1,0,0,0,0,0,0,0,0,2026-09-29T18:00:00Z,2026-09-29T19:00:00Z,main\n' "$hdr" > "$T/rdata/buildbox/calls/2026-09-29.csv"
printf '{"accounts": [{"label": "work", "home": "~/.claude-work"}, {"label": "main", "home": "~/.claude", "primary": true}]}' > "$T/racc.json"
ACCOUNT_ORCA_FILE="$T/no-orca.json" ACCOUNTS_FILE="$T/racc.json" USAGE_DATA="$T/rdata" USAGE_NOW="2026-10-05T09:00:00-07:00" "$B/usage-report" ratio > "$T/ratio2.out"
has "$T/ratio2.out" 'ratio: list × 0.0230 — $46.00 a week over an average $2,000 of list spend (2 weeks to 2026-10-04)' "a work row (employer-paid) leaves the ratio as it was"
has "$T/ratio2.out" 'ratio: excluded $3,000 of list spend on other accounts (43% of the weeks' "…and the excluded share is named"
ACCOUNT_ORCA_FILE="$T/no-orca.json" ACCOUNTS_FILE="$T/no-registry.json" USAGE_DATA="$T/rdata" USAGE_NOW="2026-10-05T09:00:00-07:00" "$B/usage-report" ratio > "$T/ratio3.out"
check "$(grep -c 'excluded' "$T/ratio3.out")" "0" "an unreadable registry excludes nothing: a label it cannot place counts as the plan's"
rm -rf "$T/rdata/buildbox"
check "$([ -e "$COST_RATIO" ] && echo yes || echo no)" "no" "without --write nothing is written"
cat > "$COST_RATIO" <<'EOF'
{"providers": {"other": {"ratio": 0.5}, "anthropic": {"ratio": 1, "week_ending": "2026-09-27"}}}
EOF
printf '{"hosts": {"testmac": {"render": true}}}' > "$T/rcfg.json"
mkdir -p "$T/rdata/testmac"; touch "$T/rdata/testmac/.collected-2026-10-05" "$T/rdata/testmac/.collected-2026-10-06"
USAGE_CONFIG="$T/rcfg.json" USAGE_DATA="$T/rdata" USAGE_PUBLISH= USAGE_NOW="2026-10-05T07:10:00-07:00" "$B/usage-report" tick > "$T/rtick1.out"
has "$T/rtick1.out" "ratio: commit done" "the first render after a week ends commits the ratio"
# the core resolves COST_RATIO (its default is a link into the vault), so on macOS $T reads /private/var/…
has "$T/kc.txt" "-m Cost ratio: list × 0.0230, week ending 2026-10-04 $(cd "$(dirname "$COST_RATIO")" && pwd -P)/cost-ratio.json" "…through knowledge-commit, with the file's path"
check "$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1]))["providers"]; print(d["anthropic"]["week_ending"], d["other"]["ratio"])' "$COST_RATIO")" "2026-10-04 0.5" "the new week is written; other providers are kept"
has "$RP/2026-10-04.md" "list × 0.0230, week ending 2026-10-04" "the report says which ratio it used"
has "$RP/2026-10-04.md" '$500 ($12 effective)' "…and shows effective beside list"
has "$RP/latest-line.txt" '$500 ($12 effective)' "…and so does the daily line"
USAGE_CONFIG="$T/rcfg.json" USAGE_DATA="$T/rdata" USAGE_PUBLISH= USAGE_NOW="2026-10-06T07:10:00-07:00" "$B/usage-report" tick > "$T/rtick2.out"
lacks "$T/rtick2.out" "ratio:" "once a week, not every render"
# a week's ratio written but never committed (a failed commit, a `ratio --write` by hand): the next render commits it
mkdir -p "$T/rgit"; git -C "$T/rgit" init -q; cp "$COST_RATIO" "$T/rgit/cost-ratio.json"
git -C "$T/rgit" add cost-ratio.json; git -C "$T/rgit" -c user.name=t -c user.email=t@t commit -qm init
echo ' ' >> "$T/rgit/cost-ratio.json"; rm -f "$T/kc.txt"
COST_RATIO="$T/rgit/cost-ratio.json" USAGE_CONFIG="$T/rcfg.json" USAGE_DATA="$T/rdata" USAGE_PUBLISH= USAGE_NOW="2026-10-07T07:10:00-07:00" "$B/usage-report" tick > "$T/rtick3.out"
has "$T/rtick3.out" "ratio: commit done" "an uncommitted ratio is committed at the next render"
has "$T/kc.txt" "week ending 2026-10-04" "…with its own week in the message"
# a ratio file nobody can merge into: the daily report still goes out, and other providers are never dropped
echo '[]' > "$T/list.json"
COST_RATIO="$T/list.json" USAGE_CONFIG="$T/rcfg.json" USAGE_DATA="$T/rdata" USAGE_PUBLISH= USAGE_NOW="2026-10-08T07:10:00-07:00" "$B/usage-report" tick > "$T/rtick4.out"
has "$T/rtick4.out" "ratio: FAILED" "a ratio file of the wrong shape fails the ratio step, loudly"
has "$T/rtick4.out" "render 2026-10-07" "…and the day's report is rendered all the same"
check "$(cat "$T/list.json")" "[]" "…and the file is left as it was"


echo "no peers: plumb with the regatta core alone (regatta-modules G13, G15, G25, G35, G36, G37)"
# A scratch checkout holding a copy of the core and of plumb's files, nothing else: tool() finds no
# lighthouse, atlas, keel or wharf there, whatever this Mac has installed. PR is plumb's root (this
# checkout's, or modules/plumb), so the same cases run from the overlay and from the module.
PR="$(cd "$B/.." && pwd)"
core=$(python3 - "$PR" <<'PYC'
import os, sys
lib = os.path.join(sys.argv[1], "lib")
if os.path.isfile(os.path.join(lib, "find_core.py")):
    sys.path.insert(0, lib); import find_core; sys.path.insert(0, find_core.hooks())
else:
    sys.path.insert(0, os.path.join(sys.argv[1], "hooks"))
import common; print(os.path.dirname(os.path.dirname(os.path.realpath(common.__file__))))
PYC
)
fc="$PR/lib/find_core.py"; [ -f "$fc" ] || fc="$core/../plumb/lib/find_core.py"
PL="$T/peerless"; PM="$PL/modules/plumb"
mkdir -p "$PL/.claude-plugin" "$PM/bin" "$PM/hooks" "$PM/lib" "$T/no-plugins"
echo '{"name":"peerless","owner":{"name":"t"},"plugins":[]}' > "$PL/.claude-plugin/marketplace.json"
cp -R "$core" "$PL/modules/regatta"; cp "$fc" "$PM/lib/"
for f in usage-report knowledge-numbers statusline interruptions; do cp "$PR/bin/$f" "$PM/bin/"; done
cp "$PR/hooks/tier_check.py" "$PR/hooks/attention.py" "$PM/hooks/"; cp -R "$PR/bench" "$PM/bench"
peerless() { env REGATTA_HOME="$PL" CLAUDE_CONFIG_DIR="$T/no-plugins" "$@"; }
load() {  # load(file, name, expr): the file as a module, then print expr
  python3 -c "import sys; from importlib.machinery import SourceFileLoader as L; from pathlib import Path
$2 = L('$2', '$1').load_module(); print($3)"
}
check "$(peerless env -u USAGE_CLAUDE_JSON HOME="$T/h" bash -c "$(declare -f load); load '$PM/bin/usage-report' ur 'ur.account_dirs() == [Path.home() / \".claude\"]'")" "True" \
  "G13: no account (lighthouse): ~/.claude alone, quiet"
peerless "$PM/bin/usage-report" render --day 2026-09-19 > "$T/pl-render.out" 2>&1
has "$T/pl-render.out" "publish: lighthouse not installed — local only" "G35: no publish (lighthouse): the report stays local, said"
check "$(peerless env -u USAGE_KNOWLEDGE_COMMIT bash -c "$(declare -f load); load '$PM/bin/usage-report' ur 'ur._knowledge_commit()'")" "None" \
  "G35: no knowledge-commit (atlas): nothing to commit with"
check "$(peerless bash -c "$(declare -f load); load '$PM/bin/usage-report' ur 'ur.commit_ratio({\"knowledge_commit\": None}, {}) or \"\"'" | grep -c '^ratio: written, not committed — atlas (knowledge-commit) not installed')" \
  "1" "  …the ratio is written, not committed, said"
mkdir -p "$T/nw/h"
check "$(peerless bash -c "$(declare -f load); load '$PM/bin/usage-report' ur '[ur.notify_watch({\"data\": Path(\"$T/nw\"), \"host\": \"h\"}, False) for _ in (1, 2)] and Path(\"$T/nw/h/.notify-failed\").read_text()'")" "2" \
  "G15: no bulletin.py (atlas): two failed days count, nothing raises"
check "$(peerless bash -c "$(declare -f load); load '$PM/bin/knowledge-numbers' kn '(kn.KEEL, kn.course_goals(0)[0][\"why\"])'")" "(None, 'not installed (keel)')" \
  "G36: no keel: the course rows say not installed"
check "$(peerless bash -c "$(declare -f load); load '$PM/bin/knowledge-numbers' kn 'kn.common.tool(\"claude-settings\")'")" "None" \
  "G36: no claude-settings (lighthouse) found"
check "$(printf '{"workspace":{"current_dir":"/tmp/da"}}' | peerless env ASK_CACHE_DIR="$T/no-ask" python3 "$PM/bin/statusline")" "da" \
  "G25: no ask cache (helm): the line without asks, quiet"
mkdir -p "$T/slc"
check "$(printf '{"workspace":{"current_dir":"/tmp/da"},"session_id":"s","rate_limits":{"seven_day":{"used_percentage":100,"resets_at":1}}}' \
  | peerless env CLAUDE_CONFIG_DIR="$T/slc" ASK_CACHE_DIR="$T/no-ask" python3 "$PM/bin/statusline"; ls "$T/slc/exhaustion-marks" 2>/dev/null | wc -l | tr -d ' ')" \
  "$(printf 'da · week 100%% · limit!\n0')" "G13: no account: limit! still shows, nothing recorded"
check "$(peerless bash -c "$(declare -f load); load '$PM/hooks/tier_check.py' tc 'tc.account_lines()'")" "[]" \
  "G13: tier_check without account: no account lines"
peerless env BENCH="$T/bench-docs" python3 "$PM/bench/docs/docs.py" > /dev/null 2> "$T/pl-docs.err"; rc=$?
check "$rc|$(cat "$T/pl-docs.err")" "2|docs.py: needs keel (keel), not installed" "G37: a bench whose peer is absent: one line naming the module"
peerless python3 "$PM/bench/sessions/score.py" --help > /dev/null 2> "$T/pl-score.err"; rc=$?
check "$rc|$(cat "$T/pl-score.err")" "2|score.py: needs session_status.py (wharf), not installed" "  …wharf's session_status the same"
check "$(peerless python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import _regatta; print(bool(_regatta.find("jev")))' "$PM/bench")" "True" "  …and jev, the core's, is found in the core alone"

echo "the config dir's defaults: plumb/usage.json and lighthouse/accounts.json (2026-10-22, out of the vault)"
cp -R "$REGATTA_CONFIG" "$T/rc" && rm -f "$T/rc/plumb/usage.json" "$T/rc/lighthouse/accounts.json" && mkdir -p "$T/rc/plumb" "$T/rc/lighthouse"
printf '{"hosts": {}}' > "$T/rc/plumb/usage.json"
printf '{"accounts": [{"label": "seat-a", "home": "~/.seat-a"}, {"label": "own", "home": "~/.claude", "primary": true}]}' > "$T/rc/lighthouse/accounts.json"
check "$(env -u USAGE_CONFIG -u ACCOUNTS_FILE REGATTA_CONFIG="$T/rc" python3 - "$B/usage-report" <<'PY2'
import sys
from importlib.machinery import SourceFileLoader
u = SourceFileLoader("usage_report", sys.argv[1]).load_module()
s = u.secondary_labels()   # account_rows adds the Orca seats of this Mac too: ask about the fixture rows only
print(u.CONFIG.name, u.CONFIG.parent.name, "seat-a" in s, "own" in s)
PY2
)" "usage.json plumb True False" "no USAGE_CONFIG, no ACCOUNTS_FILE: both read from the config dir"

echo "knowledge-numbers: memory unlinked, each repo against its home (knowledge-layers S3)"
KH="$T/kh"; PJ="$KH/projects"; mkdir -p "$PJ/acme-knowledge/memory/app" "$PJ/app" "$PJ/tools" "$KH/vault/memory/app" "$KH/vault/memory/tools"
printf '{"repos": {"acme-knowledge": {}, "app": {}, "tools": {}}, "scopes": {"acme": {"repos": ["acme-knowledge", "app"], "confidential": true}, "o": {"repos": ["tools"]}}}' > "$KH/repos.json"
for r in app tools; do
  s=$(python3 -c "import re,sys;print(re.sub('[^A-Za-z0-9]','-',sys.argv[1]))" "$PJ/$r"); mkdir -p "$KH/login/projects/$s"
  echo '{}' > "$KH/login/projects/$s/t.jsonl"; ln -s "$KH/vault/memory/$r" "$KH/login/projects/$s/memory"
done
mu() { CLAUDE_REPOS_JSON="$KH/repos.json" bash -c "$(declare -f load); load '$B/knowledge-numbers' kn \"(setattr(kn, 'PROJECTS', Path('$PJ')), setattr(kn, 'VAULT', Path('$KH/vault')), kn.memory_unlinked(__import__('time').time(), dirs=[Path('$KH/login')]))[2]\""; }
check "$(mu)" "['app']" "a confidential scope's repo linked into the vault is unlinked; an open one there is linked"
s=$(python3 -c "import re,sys;print(re.sub('[^A-Za-z0-9]','-',sys.argv[1]))" "$PJ/app"); ln -sfn "$PJ/acme-knowledge/memory/app" "$KH/login/projects/$s/memory"
check "$(mu)" "[]" "  linked into its knowledge repo: linked"

echo "knowledge-numbers: the fence (knowledge-layers S4)"
ln -sfn "$KH/vault/memory/app" "$KH/login/projects/$s/memory"; rm "$KH/login/projects/$(python3 -c "import re,sys;print(re.sub('[^A-Za-z0-9]','-',sys.argv[1]))" "$PJ/tools")/memory"
muf() { KS="${1:-}" CLAUDE_REPOS_JSON="$KH/repos.json" bash -c "$(declare -f load); load '$B/knowledge-numbers' kn \"(setattr(kn, 'PROJECTS', Path('$PJ')), setattr(kn.common, 'PROJECTS', Path('$PJ')), setattr(kn, 'VAULT', Path('$KH/vault')), kn.memory_unlinked(__import__('time').time(), dirs=[Path('$KH/login')], fence=kn.scoped(kn.common.gather_fence(__import__('os').environ['KS'] or None), __import__('os').environ['KS'])))[3]\""; }
check "$(muf)" "['tools', '(confidential)']" "unlinked: the open repo by name, the confidential one counted as (confidential)"
check "$(muf acme)" "['app']" "  --scope of the confidential scope: its own, by name"
check "$(muf o)" "['tools']" "  --scope of the open one: its own; the confidential one not even counted"
check "$(load "$B/knowledge-numbers" kn 'kn.fold_fenced([{"project": "a", "n": 1}], [{"project": "s", "n": 2}, {"project": "t", "n": 3}])')" \
  "[{'project': 'a', 'n': 1}, {'project': '(confidential)', 'n': 5}]" "  the project rows: a confidential scope's summed into one row, its names gone"
CLAUDE_REPOS_JSON="$KH/repos.json" "$B/knowledge-numbers" --scope nope > /dev/null 2> "$T/kn.err"
check "$? $(cat "$T/kn.err")" "2 knowledge-numbers: no scope 'nope' in the registry" "  an unknown scope: exit 2, one line"

echo "numbers: each scope pass's cost (knowledge-layers S5)"
check "$(load "$B/usage-report" u 'u.scope_passes([{"title": "“/aurora dream --scope pub”", "session": "a", "cost": 1.5}, {"title": "“/aurora dream --scope pub”", "session": "a", "cost": 0.5}, {"title": "“/aurora dream --days 7 --scope node”", "session": "b", "cost": 2.0}, {"title": "“/aurora dream”", "session": "c", "cost": 9.0}, {"title": "Kids wake tuning", "session": "d", "cost": 1.0}])')" \
  "{'node': {'sessions': 1, 'usd': 2.0}, 'pub': {'sessions': 1, 'usd': 2.0}}" "by the session's prompt: one per scope, the night's own dream and other sessions left out"
check "$(nj 'print(d["scope_passes"])')" "{}" "  numbers --json carries them (none in the fixture week)"

if [ "$fails" = 0 ]; then echo "all green"; else echo "$fails failing"; exit 1; fi
