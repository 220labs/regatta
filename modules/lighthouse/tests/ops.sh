#!/usr/bin/env bash
# lighthouse's bin/ops (lighthouse-ops S1, S2, S4, S5): the desk's token wall — read only in the desk's own job,
# from a local 0700 dir and a 0600 file, never a link — and `ops usage` against stubbed GitHub and
# CircleCI answers (a driver replaces ops.http_get in-process: no network, no port). The pick's own
# cases are wharf's tests/test_ci_provider.sh. Scratch HOME and config dir; every name made up.
#   bash modules/lighthouse/tests/ops.sh
set -u
for v in $(env | sed -n 's/^\(CLAUDE[A-Za-z0-9_]*\)=.*/\1/p; s/^\(DISPATCH[A-Za-z0-9_]*\)=.*/\1/p'); do unset "$v"; done
unset LIGHTHOUSE_DESK REGATTA_HOME
C="$(cd "$(dirname "$0")/.." && pwd)"; OPS="$C/bin/ops"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export HOME="$T/home" REGATTA_CONFIG="$T/config"
mkdir -p "$HOME" "$REGATTA_CONFIG/regatta" "$REGATTA_CONFIG/lighthouse" "$T/logs"
printf '%s\n' "$T/logs" > "$REGATTA_CONFIG/regatta/log-dir"
fails=0
check() { if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3: expected [$2] got [$1]"; fails=$((fails+1)); fi; }
has() { case "$1" in *"$2"*) echo "  ok   $3";; *) echo "  FAIL $3: [$2] not in [${1:0:300}]"; fails=$((fails+1));; esac; }
TOK="fake-desk-token-0123456789"; CTOK="cci_FAKECIRCLETOKEN987"
SD="$REGATTA_CONFIG/lighthouse/secrets"; TF="$SD/ops.env"
cat > "$REGATTA_CONFIG/lighthouse/ci-budgets.json" <<'EOF'
{"accounts": {"gh-user": {"provider": "github", "user": "acme", "month_minutes": 3000},
 "gh-org": {"provider": "github", "org": "acme-org", "month_minutes": 2000},
 "cci": {"provider": "circleci", "org_slug": "gh/acme", "month_credits": 30000, "week_share": 0.3}}}
EOF
# The driver: ops loaded from its file, http_get answering from $T/answers.json by URL substring and
# logging each URL and its headers to $T/calls; then `ops <args>` through its main.
cat > "$T/drive.py" <<'PY'
import importlib.machinery, importlib.util, json, sys, time
loader = importlib.machinery.SourceFileLoader("ops", sys.argv[1])
spec = importlib.util.spec_from_loader("ops", loader)
ops = importlib.util.module_from_spec(spec)
loader.exec_module(ops)
answers = json.load(open(sys.argv[2]))
def http_get(url, headers):
    with open(sys.argv[3], "a") as f:
        f.write(json.dumps({"url": url, "headers": headers}) + "\n")
    for k, v in answers.items():
        if k in url:
            return v[0], v[1]
    return 404, None
ops.http_get = http_get
if len(sys.argv) > 5 and sys.argv[4] == "--tool":
    ops.common.tool = lambda name: sys.argv[5]
    sys.exit(ops.main(sys.argv[6:]))
sys.exit(ops.main(sys.argv[4:]))
PY
today=$(python3 -c 'import time; print(time.strftime("%Y-%m-%d", time.gmtime()))')
ym=$(python3 -c 'import time; t=time.gmtime(); print("year=%d&month=%d" % (t.tm_year, t.tm_mon))')
# the month the week's first day falls in, when it is not this one: answered empty (a stub for every date)
pym=$(python3 -c 'import time; t=time.gmtime(time.time()-6*86400); print("year=%d&month=%d" % (t.tm_year, t.tm_mon))')
[ "$pym" = "$ym" ] && pym=none
old=$(python3 -c 'import time; print(time.strftime("%Y-%m-%d", time.gmtime(time.time()-20*86400)))')
cat > "$T/answers.json" <<EOF
{"/users/acme/settings/billing/usage?${ym}": [200, {"usageItems": [
   {"date": "${today}T00:00:00Z", "product": "actions", "sku": "actions_linux", "quantity": 100, "unitType": "Minutes", "netAmount": 0},
   {"date": "${old}T00:00:00Z", "product": "actions", "sku": "actions_linux", "quantity": 40, "unitType": "Minutes", "netAmount": 0},
   {"date": "${today}T00:00:00Z", "product": "actions", "sku": "actions_macos", "quantity": 3, "unitType": "Minutes", "netAmount": 0.12},
   {"date": "${today}T00:00:00Z", "product": "packages", "sku": "packages_storage", "quantity": 9, "unitType": "GigabyteHours", "netAmount": 0}]}],
 "/users/acme/settings/billing/usage?${pym}": [200, {"usageItems": []}],
 "/organizations/acme-org/settings/billing/usage": [403, null],
 "reporting-window=last-30-days": [200, {"org_data": {"metrics": {"total_credits_used": 1200}}}],
 "reporting-window=last-7-days": [200, {"org_data": {"metrics": {"total_credits_used": 300}}}]}
EOF
ops() { : > "$T/calls"; python3 "$T/drive.py" "$OPS" "$T/answers.json" "$T/calls" "$@"; }
field() { python3 -c 'import json,sys; d=json.load(sys.stdin)
for k in sys.argv[1].split("."): d=d[k]
print(d)' "$1"; }

echo "ops: the token wall"
ops usage --json > "$T/out" 2>&1; check "$?" "0" "outside the desk's job: usage still prints"
check "$(field accounts.gh-user.state < "$T/out")" "refused" "…every account refused the token"
grep -q "not the desk's job (LIGHTHOUSE_DESK=1 unset)" "$T/out"; check "$?" "0" "…saying the token is read in the desk's job only"
check "$(wc -l < "$T/calls" | tr -d ' ')" "0" "…and nothing is asked of GitHub or CircleCI"
ops usage --write > "$T/out" 2>&1; check "$?" "2" "--write outside the job: refused"
check "$(test -e "$T/logs/ci-usage.json" && echo there || echo absent)" "absent" "…no usage file written"
export LIGHTHOUSE_DESK=1
CLAUDE_CODE_SESSION_ID=s-1 ops usage --json > "$T/out" 2>&1
grep -q "a Claude Code session is never handed the desk's token" "$T/out"; check "$?" "0" "the marker beside a session id: refused"
CLAUDE_UNATTENDED=1 ops usage --json > "$T/out" 2>&1
check "$(field accounts.gh-user.state < "$T/out")" "refused" "…beside CLAUDE_UNATTENDED too"
ops usage --json > "$T/out" 2>&1
check "$(field accounts.gh-user.state < "$T/out") $(field token.github < "$T/out")" "absent absent" "the desk's job, no token file: absent"
mkdir -p "$SD"; chmod 755 "$SD"; printf 'GITHUB_TOKEN=%s\nCIRCLECI_TOKEN=%s\n' "$TOK" "$CTOK" > "$TF"; chmod 600 "$TF"
ops usage --json > "$T/out" 2>&1
grep -q 'must be this user.s and 700, not 755' "$T/out"; check "$?" "0" "the dir open to others: refused"
chmod 700 "$SD"; chmod 644 "$TF"; ops usage --json > "$T/out" 2>&1
grep -q 'must be this user.s and 600, not 644' "$T/out"; check "$?" "0" "the file readable by others: refused"
mv "$TF" "$T/real.env"; chmod 600 "$T/real.env"; ln -s "$T/real.env" "$TF"; ops usage --json > "$T/out" 2>&1
grep -q 'ops.env is a link' "$T/out"; check "$?" "0" "the file a link (into a drive, say): refused"
rm "$TF"; mv "$SD" "$T/sd.real"; mkdir -p "$T/sd.real"; ln -s "$T/sd.real" "$SD"; ops usage --json > "$T/out" 2>&1
grep -q 'secrets is a link\|a folder above it is a link' "$T/out"; check "$?" "0" "the dir a link: refused"
rm "$SD"; mkdir -m 700 "$SD"; mv "$T/real.env" "$TF"; chmod 600 "$TF"
mv "$REGATTA_CONFIG/lighthouse" "$T/lh.real"; ln -s "$T/lh.real" "$REGATTA_CONFIG/lighthouse"; ops usage --json > "$T/out" 2>&1
grep -q 'a folder above it is a link' "$T/out"; check "$?" "0" "a folder above the dir a link (lighthouse/ into a drive): refused (landing review)"
rm "$REGATTA_CONFIG/lighthouse"; mv "$T/lh.real" "$REGATTA_CONFIG/lighthouse"

echo "ops usage: GitHub's billing usage and CircleCI's insights"
ops usage --json > "$T/out" 2>&1; check "$?" "0" "the token in place: usage read"
check "$(field accounts.gh-user.state < "$T/out") $(field accounts.gh-user.month_used < "$T/out") $(field accounts.gh-user.week_used < "$T/out") $(field accounts.gh-user.net_amount < "$T/out")" \
  "ok 170.0 130.0 0.12" "the user's Actions minutes: a macOS minute weighed 10, the week the last seven days, netAmount summed, storage left out"
check "$(field accounts.gh-org.state < "$T/out")" "refused" "the org's endpoint answering 403: refused"
check "$(field token.github < "$T/out")" "ok" "…the token's standing ok while one account reads it"
check "$(field accounts.cci.month_used < "$T/out") $(field accounts.cci.week_used < "$T/out") $(field token.circleci < "$T/out")" "1200.0 300.0 ok" "CircleCI: 30 days and, for a week share, 7"
nu=1; [ "$pym" = none ] || nu=2   # days 1-6 of a month read last month too (the second landing review)
check "$(grep -c "/users/acme/settings/billing/usage?year=" "$T/calls") $(grep -c '/organizations/acme-org/settings/billing/usage?year=' "$T/calls")" "$nu 1" "the user and the org forms of the endpoint"
check "$(python3 -c 'import json,sys; c=[json.loads(l) for l in open(sys.argv[1])]; print(sorted({(x["headers"].get("Authorization") or x["headers"].get("Circle-Token")) for x in c}))' "$T/calls")" \
  "['Bearer $TOK', '$CTOK']" "the tokens go in a request header"
check "$(grep -c "$TOK\|$CTOK" "$T/out")" "0" "…and never into the output"
ops usage --write --json > "$T/out" 2> "$T/err"; check "$(python3 -c 'import json,sys; json.load(open(sys.argv[1])); print("json")' "$T/out" 2>&1)" "json" "--write --json: stdout is the JSON alone, the wrote line on stderr"
ops usage --write > "$T/out" 2>&1; check "$?" "0" "--write in the desk's job"
check "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["accounts"]["gh-user"]["state"])' "$T/logs/ci-usage.json")" "ok" "…the usage file the pick reads"
check "$(grep -c "$TOK\|$CTOK" "$T/logs/ci-usage.json" "$T/out" | awk -F: '{s+=$2} END {print s}')" "0" "…holding no token text, nor the output"
grep -q "lighthouse/guarded-dirs does not list $SD" "$T/out"; check "$?" "0" "the token's dir not guarded: said"
printf '%s\n' "$SD" > "$REGATTA_CONFIG/lighthouse/guarded-dirs"; ops usage > "$T/out" 2>&1
grep -q "guarded-dirs does not list" "$T/out"; check "$?" "1" "…and not once it is listed"
python3 -c 'import json,sys; a=json.load(open(sys.argv[1])); a["/users/acme/settings/billing/usage?"+sys.argv[2]]=[200,{"message":"not on the enhanced billing platform"}]; json.dump(a,open(sys.argv[1],"w"))' "$T/answers.json" "$ym"
ops usage --json > "$T/out" 2>&1
check "$(field accounts.gh-user.state < "$T/out")" "unread" "an answer without usageItems: unread, never a zero"

cat > "$T/month.py" <<'PY'
import importlib.machinery, importlib.util, json, sys
loader = importlib.machinery.SourceFileLoader("ops", sys.argv[1]); spec = importlib.util.spec_from_loader("ops", loader)
ops = importlib.util.module_from_spec(spec); loader.exec_module(ops)
def item(date, q): return {"date": date, "product": "actions", "sku": "actions_linux", "quantity": q, "unitType": "minutes", "netAmount": 0}
ans = {"year=2026&month=11": [item("2026-11-01", 10), item("2026-11-02", 5)], "year=2026&month=10": [item("2026-10-20", 99), item("2026-10-29", 7)]}
ops.http_get = lambda url, h: next(((200, {"usageItems": v}) for k, v in ans.items() if k in url), (404, None))
r = ops.github_usage({"user": "acme"}, "t", 1793664000)   # 2026-11-02, the week from 2026-10-27
print(r["month_used"], r["week_used"])
PY
check "$(python3 "$T/month.py" "$OPS" | head -1)" "15.0 22.0" "a week across the month's start: last month's days in the week, never in the month"
check "$(python3 -c 'import importlib.machinery as m, importlib.util as u, sys; l=m.SourceFileLoader("ops", sys.argv[1]); o=u.module_from_spec(u.spec_from_loader("ops", l)); l.exec_module(o); print(o.http_get("http://example.com/x", {"Authorization": "Bearer t"}))' "$OPS")" \
  "(0, None)" "a plain-http base URL off this host carries no token: refused"
check "$(python3 -c 'import importlib.machinery as m, importlib.util as u, sys; l=m.SourceFileLoader("ops", sys.argv[1]); o=u.module_from_spec(u.spec_from_loader("ops", l)); l.exec_module(o); print([o.http_get(x, {}) for x in sys.argv[2:]])' "$OPS" http://localhost.attacker.example/x http://127.0.0.1.nip.io/x http://localhost@attacker.42/x)" \
  "[(0, None), (0, None), (0, None)]" "…nor to a host that only starts like this one's (the second landing review)"

echo "ops pick: usage first, then ci-provider per repo, the marker stripped"
printf '#!/bin/sh\nprintf "%%s|%%s\\n" "$*" "${LIGHTHOUSE_DESK:-unset}" >> "%s"\n' "$T/cp.calls" > "$T/cp"; chmod +x "$T/cp"
: > "$T/calls"; python3 "$T/drive.py" "$OPS" "$T/answers.json" "$T/calls" --tool "$T/cp" pick --apply "$T/r1" "$T/r2" > "$T/out" 2>&1
check "$?" "0" "ops pick --apply over two repos"
check "$(cat "$T/cp.calls")" "$T/r1 --pick --usage $T/logs/ci-usage.json --apply|unset
$T/r2 --pick --usage $T/logs/ci-usage.json --apply|unset" "…ci-provider --pick per repo with the desk's usage file, LIGHTHOUSE_DESK never passed on"
printf '#!/bin/sh\ncase "$1" in *r2) exit 2;; *r3) exit 3;; esac\n' > "$T/cp2"; chmod +x "$T/cp2"
python3 "$T/drive.py" "$OPS" "$T/answers.json" "$T/calls" --tool "$T/cp2" pick "$T/r1" "$T/r2" > "$T/out" 2>&1; check "$?" "0" "a repo the pick does not handle (exit 2) is reported, not the job's failure"
grep -q '2 repos — 1 picked or unchanged, 1 refused or not handled, 0 on a failing lane' "$T/out"; check "$?" "0" "…counted in the summary"
python3 "$T/drive.py" "$OPS" "$T/answers.json" "$T/calls" --tool "$T/cp2" pick "$T/r1" "$T/r3" > "$T/out" 2>&1; check "$?" "3" "a repo on a lane its pick refused: exit 3, for the desk to card"
unset LIGHTHOUSE_DESK
python3 "$T/drive.py" "$OPS" "$T/answers.json" "$T/calls" --tool "$T/cp" pick "$T/r1" > "$T/out" 2>&1; check "$?" "2" "ops pick outside the desk's job: refused"

# ---- S2: the sampler ----------------------------------------------------------------------------
# Every peer a stub in $T/tools (the core's tool() replaced in-process), each answering from a file
# the case writes, or failing when $T/fail names it; GitHub's two endpoints from answers.json as above.
TL="$T/tools"; mkdir -p "$TL"
stub() { printf '#!/bin/sh\n[ -e "%s/fail/%s" ] && { echo "%s broke" >&2; exit 7; }\n%s\n' "$T" "$1" "$1" "$2" > "$TL/$1"; chmod +x "$TL/$1"; }
mkdir -p "$T/fail"
stub dispatch-queue 'case "$1" in home) exit "$(cat '"$T"'/q.home)";; list) cat '"$T"'/q.json;; esac'
stub dispatch '[ "$1" = --slots ] && echo "4 6"'
stub headroom 'echo "{\"room\": true, \"sample\": {\"avail\": 51.0, \"swap\": 1.65, \"rate\": 0.0}}"; exit 0'
stub account 'printf "%s\n" "[{\"label\": \"acct-a\", \"eligible\": true, \"limits\": {\"seven_day\": 31, \"five_hour\": 3, \"fable_week\": 0, \"locked\": []}}]"'
stub usage-report 'echo "{\"window\": [\"2026-10-20\", \"2026-10-26\"], \"proxy_usd\": 1000.0}"'
echo 0 > "$T/q.home"
cat > "$T/q.json" <<'EOF'
{"entries": [{"state": "queued", "priority": "high"}, {"state": "queued", "priority": "normal"}, {"state": "running", "priority": "normal"}], "unreadable": false, "why": []}
EOF
printf '%s\n' '{"providers": {"anthropic": {"ratio": 0.02}}}' > "$T/ratio.json"; export COST_RATIO="$T/ratio.json"
printf '%s\n' '{"repos": {}, "scopes": {}}' > "$T/repos.json"; export CLAUDE_REPOS_JSON="$T/repos.json"
export CHECK_SLOT_DIR="$T/slots"; mkdir -p "$CHECK_SLOT_DIR/slot-1" "$CHECK_SLOT_DIR/slot-2" "$CHECK_SLOT_DIR/queue"
sleep 300 & LIVE=$!; disown "$LIVE" 2>/dev/null; trap 'kill $LIVE 2>/dev/null; rm -rf "$T"' EXIT
echo "$LIVE" > "$CHECK_SLOT_DIR/slot-1/pid"; echo 999999 > "$CHECK_SLOT_DIR/slot-2/pid"
: > "$CHECK_SLOT_DIR/queue/1793148246.002640.$LIVE"; : > "$CHECK_SLOT_DIR/queue/1793148246.002641.999998"
python3 -c 'import json,sys; a=json.load(open(sys.argv[1])); a["/users/acme/settings/billing/usage?"+sys.argv[2]]=[200,{"usageItems":[{"date":sys.argv[3]+"T00:00:00Z","product":"actions","sku":"actions_linux","quantity":300,"unitType":"Minutes","netAmount":0}]}]; a["/graphql"]=[200,{"data":{"viewer":{"projectsV2":{"totalCount":2}}}}]; json.dump(a,open(sys.argv[1],"w"))' "$T/answers.json" "$ym" "$today"
cat > "$T/sample.py" <<'PY'
import importlib.machinery, importlib.util, json, os, sys
from pathlib import Path
loader = importlib.machinery.SourceFileLoader("ops", sys.argv[1])
spec = importlib.util.spec_from_loader("ops", loader)
ops = importlib.util.module_from_spec(spec)
loader.exec_module(ops)
answers, calls, tools = json.load(open(sys.argv[2])), sys.argv[3], Path(sys.argv[4])
def answer(url, headers, body=None):
    with open(calls, "a") as f:
        f.write(json.dumps({"url": url, "headers": headers, "body": body}) + "\n")
    for k, v in answers.items():
        if k in url:
            return v[0], v[1]
    return 404, None
ops.http_get = answer
ops.http_post = answer
ops.common.tool = lambda name: (tools / name) if (tools / name).is_file() else None
for k in ("TIMEOUT", "SAMPLE_DEADLINE"):
    if os.environ.get("OPS_" + k):
        setattr(ops, k, float(os.environ["OPS_" + k]))
sys.exit(ops.main(sys.argv[5:]))
PY
smp() { : > "$T/calls"; python3 "$T/sample.py" "$OPS" "$T/answers.json" "$T/calls" "$TL" "$@"; }
last() { tail -n 1 "$T/logs/ops.jsonl" | field "$1"; }
HOSTNAME_=$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import find_core; sys.path.insert(0, find_core.hooks()); import common; print(common.host_name())' "$C/lib")
rm -f "$T/logs/ci-usage.json"

echo "ops sample: only the desk's job, only on the ops host"
smp sample > "$T/out" 2>&1; check "$?" "2" "outside the desk's job: refused"
check "$(test -e "$T/logs/ops.jsonl" && echo there || echo absent)" "absent" "…no row written"
export LIGHTHOUSE_DESK=1
smp sample > "$T/out" 2>&1; check "$?" "2" "no lighthouse/ops-host: refused"
grep -q "names no host: the desk is off" "$T/out"; check "$?" "0" "…saying the desk is off"
echo other-host > "$REGATTA_CONFIG/lighthouse/ops-host"
smp sample > "$T/out" 2>&1; check "$?" "2" "a host that is not the ops host: refused"
grep -q "not lighthouse/ops-host's other-host" "$T/out"; check "$?" "0" "…naming the ops host"
check "$(test -e "$T/logs/ops.jsonl" && echo there || echo absent)" "absent" "…no row written"
check "$(smp is-host > /dev/null 2>&1; echo $?) $(: > "$REGATTA_CONFIG/lighthouse/ops-host"; smp is-host > /dev/null 2>&1; echo $?)" "3 4" "ops is-host: 3 on another host, 4 when the key names none"
echo "$HOSTNAME_" > "$REGATTA_CONFIG/lighthouse/ops-host"
check "$(smp is-host > /dev/null 2>&1; echo $?)" "0" "…0 on the ops host"

echo "ops sample: a field per read"
smp sample > "$T/out" 2>&1; check "$?" "0" "the desk's job on the ops host: a row"
check "$(wc -l < "$T/logs/ops.jsonl" | tr -d ' ')" "1" "…one line appended to the log dir's ops.jsonl"
check "$(last host) $(last partial) $(last registry)" "$HOSTNAME_ False ok" "host, partial, registry"
check "$(last queue.pending) $(last queue.by_priority.high) $(last queue.by_priority.normal) $(last queue.live)" "2 1 1 1" "queue: pending by priority, live (dispatch-queue's ref)"
check "$(last slots.busy) $(last slots.max)" "4 6" "slots: dispatch --slots"
check "$(tail -n 1 "$T/logs/ops.jsonl" | python3 -c 'import json,sys,os; l=json.load(sys.stdin)["load"]; print(isinstance(l["per_core"], float), l["cores"] == os.cpu_count())')" "True True" "load: the 5-minute load per core"
check "$(last mem.avail) $(last mem.swap_gb) $(last mem.rate) $(last mem.room)" "51.0 1.65 0.0 True" "mem: headroom's sample"
check "$(last check.slots_busy) $(last check.waiting)" "1 1" "check: a slot and a ticket whose pid runs, the dead ones not"
check "$(last weeks.acct-a.weekly) $(last weeks.acct-a.five_hour) $(last weeks.acct-a.fable) $(last weeks.acct-a.eligible)" "31 3 0 True" "weeks: account limits per login label"
check "$(last cost.week_list) $(last cost.week_effective)" "1000.0 20.0" "cost: the week's list price and its effective figure by the core's ratio"
check "$(last budget.gh-user.state) $(last budget.gh-user.used) $(last budget.gh-user.cap) $(last budget.gh-user.share)" "ok 300.0 3000 0.1" "budget: S1's usage, used of the month's cap"
check "$(last budget.gh-org.state) $(last budget.cci.used) $(last budget.cci.share)" "refused 1200.0 0.04" "…an account its endpoint refused, and CircleCI's credits"
check "$(last token.plan) $(last token.project)" "ok ok" "token: the billing read and the Projects read, ok"
check "$(python3 -c 'import json,sys; c=[json.loads(l) for l in open(sys.argv[1])]; g=[x for x in c if x["url"].endswith("/graphql")]; print(len(g), "projectsV2" in json.dumps(g[0]["body"]), "mutation" in json.dumps(g[0]["body"]))' "$T/calls")" \
  "1 True False" "…the Projects probe one GraphQL query, never a mutation"
check "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["accounts"]["gh-user"]["month_used"])' "$T/logs/ci-usage.json")" "300.0" "ci-usage.json written from the same read, for the pick"
check "$(grep -c "$TOK\|$CTOK" "$T/logs/ops.jsonl" "$T/logs/ci-usage.json" "$T/out" | awk -F: '{s+=$2} END {print s}')" "0" "no token text in the row, the usage file or the job's output"
grep -q "ops $HOSTNAME_: queue 2 (1 high, 1 normal) · runs 4/6 · checks 1 busy, 1 waiting" "$T/out"; check "$?" "0" "the job's one line: the status line"
smp status > "$T/out" 2>&1; check "$?" "0" "ops status: the last row"
grep -q "budget    gh-user: 300.0 of 3000 minutes this month (10%)" "$T/out"; check "$?" "0" "…readable, a line per field"
grep -q 'cost      \$1,000 list (\$20 effective)' "$T/out"; check "$?" "0" "…the cost as list and effective"

echo "ops sample: a read that fails is its field's null, never the row's end"
echo 1 > "$T/q.home"; smp sample > /dev/null 2>&1
check "$(last queue) $(last why.queue)" "None no queue home (wharf-runs/queue-repo): the run slots stand for it" "no queue home: queue null, the slots stand for it"
smp status --json > "$T/out" 2>&1
has "$(field line < "$T/out")" "queue off · runs 4/6" "…the board's line says the queue is off, not unread"
echo 0 > "$T/q.home"
for t in dispatch-queue dispatch headroom account usage-report; do : > "$T/fail/$t"; done
python3 -c 'import json,sys; a=json.load(open(sys.argv[1])); [a.__setitem__(k, [500, None]) for k in list(a)]; json.dump(a,open(sys.argv[1]+".down","w"))' "$T/answers.json"
mv "$T/answers.json" "$T/answers.up"; mv "$T/answers.json.down" "$T/answers.json"
printf 'not json' > "$T/repos.json"
smp sample > "$T/out" 2>&1; check "$?" "0" "every peer and endpoint failing, the registry torn: the row is still written"
check "$(wc -l < "$T/logs/ops.jsonl" | tr -d ' ')" "3" "…appended"
check "$(last queue) $(last slots) $(last mem) $(last weeks) $(last cost)" "None None None None None" "…each peer's field null"
check "$(last why.slots)" "dispatch exited 7: dispatch broke" "…its why the exit and the last stderr line"
check "$(last why.weeks)" "account exited 7: account broke" "…per field"
check "$(last registry)" "unreadable" "…the torn registry: unreadable (registry_unreadable, the fence trap)"
check "$(last budget.gh-user.state) $(last token.plan) $(last token.project)" "unread None None" "…GitHub down: the budget unread, the token's words null, never refused"
check "$(tail -n 1 "$T/logs/ops.jsonl" | python3 -c 'import json,sys; print(json.load(sys.stdin)["why"]["token.project"])')" "GitHub's GraphQL answered 500" "…with the answer as the why"
smp status --json > "$T/out" 2>&1
has "$(field line < "$T/out")" "registry unreadable · unread: queue, slots, mem, weeks, cost" "the board's line names a torn registry and what is unread"
rm -f "$T/fail/"*; mv "$T/answers.up" "$T/answers.json"; printf '%s\n' '{"repos": {}, "scopes": {}}' > "$T/repos.json"
stub headroom 'sleep 3; echo "{}"'
OPS_TIMEOUT=1 smp sample > /dev/null 2>&1
check "$(last why.mem)" "headroom took over 1 s" "a read over its bound: stopped, its field null"
stub headroom 'echo "{\"room\": true, \"sample\": {\"avail\": 51.0, \"swap\": 1.65, \"rate\": 0.0}}"'
stub usage-report 'sleep 3; echo "{}"'
OPS_TIMEOUT=5 OPS_SAMPLE_DEADLINE=1 smp sample > /dev/null 2>&1
check "$(last partial) $(last cost) $(last slots.busy)" "True None 4" "the sample's deadline: the read still out is null, the row partial, the rest kept"
stub usage-report 'echo "{\"window\": [\"2026-10-20\", \"2026-10-26\"], \"proxy_usd\": 1000.0}"'

echo "ops sample: the token's standing (token.plan, token.project)"
python3 -c 'import json,sys; a=json.load(open(sys.argv[1])); a["/graphql"]=[200,{"data":{"viewer":{"projectsV2":None}},"errors":[{"type":"FORBIDDEN","message":"Resource not accessible by personal access token"}]}]; json.dump(a,open(sys.argv[1],"w"))' "$T/answers.json"
smp sample > /dev/null 2>&1
check "$(last token.plan) $(last token.project)" "ok refused" "a token without the Projects permission: project refused (GraphQL's 200 with FORBIDDEN)"
mv "$TF" "$T/tf.away"; smp sample > "$T/out" 2>&1
check "$(last token.plan) $(last token.project)" "absent absent" "no token file: plan and project absent"
check "$(grep -c '/graphql' "$T/calls")" "0" "…and nothing asked of GitHub's GraphQL"
mv "$T/tf.away" "$TF"; chmod 644 "$TF"; smp sample > /dev/null 2>&1
check "$(last token.plan) $(last token.project)" "refused refused" "a token file readable by others: refused, never read"
chmod 600 "$TF"
smp sample --print > "$T/out" 2>&1; n=$(wc -l < "$T/logs/ops.jsonl" | tr -d ' ')
check "$(field token.plan < "$T/out") $(field budget < "$T/out") $(grep -c '/graphql\|billing' "$T/calls")" "None None 0" "--print: no token read, no budget, nothing asked of GitHub"
unset LIGHTHOUSE_DESK; smp sample --print > /dev/null 2>&1; check "$? $(wc -l < "$T/logs/ops.jsonl" | tr -d ' ')" "0 $n" "…outside the desk's job too, and no row written"
export LIGHTHOUSE_DESK=1

echo "ops status: the last row, its line and its signature"
printf '{"as_of": 1, "torn' >> "$T/logs/ops.jsonl"
smp status --json > "$T/out" 2>&1; check "$? $(field row.token.plan < "$T/out")" "0 refused" "a torn last line: the whole row before it"
cat > "$T/sig.py" <<'PY'
import importlib.machinery, importlib.util, copy, sys
loader = importlib.machinery.SourceFileLoader("ops", sys.argv[1]); spec = importlib.util.spec_from_loader("ops", loader)
ops = importlib.util.module_from_spec(spec); loader.exec_module(ops)
r = {"as_of": 1000, "host": "h", "registry": "ok", "queue": {"pending": 1, "by_priority": {"high": 1}, "live": 0},
     "slots": {"busy": 2, "max": 6}, "load": {"per_core": 0.5, "cores": 10}, "mem": {"avail": 40.0},
     "check": {"slots_busy": 1, "waiting": 0}, "budget": {"a": {"state": "ok", "share": 0.1}}, "weeks": {"x": {"weekly": 30}},
     "cost": {"week_list": 10.0}, "token": {"plan": "ok", "project": "refused"}, "partial": False, "why": {}}
base = ops.row_sig(r, 1060)
later = copy.deepcopy(r); later["as_of"] = 1900; later["load"]["per_core"] = 0.9; later["mem"]["avail"] = 12.0
later["budget"]["a"]["share"] = 0.2; later["weeks"]["x"]["weekly"] = 31; later["cost"]["week_list"] = 11.0
more = copy.deepcopy(r); more["queue"]["pending"] = 2
word = copy.deepcopy(r); word["token"]["project"] = "ok"
print(base == ops.row_sig(later, 1960), base == ops.row_sig(r, 1060 + 1800),
      base != ops.row_sig(more, 1060), base != ops.row_sig(word, 1060), base != ops.row_sig(r, 1000 + 3601))
print(ops.status_line(r, 1060))
PY
check "$(python3 "$T/sig.py" "$OPS" | head -1)" "True True True True True" \
  "the sig leaves out the clocks and the gauges (as_of, the age, load, memory, budgets, weeks, cost); a count, a token's word and the stale mark change it"
check "$(python3 "$T/sig.py" "$OPS" | tail -1)" "ops h: queue 1 (1 high) · runs 2/6 · checks 1 busy · load 0.50/core · mem 40% free · CI budget at most 10% used · token plan ok, project refused · sampled 1 min ago" \
  "the board's line"
rm -f "$T/logs/ops.jsonl"; smp status --json > "$T/out" 2>&1
check "$? $(field row < "$T/out")" "3 None" "no row: exit 3, row null (never 1, a crash's code)"

# ---- S4: the intake -----------------------------------------------------------------------------
# `gh` a stub answering from $T/gh.json by path substring (`[rc, [objects]]`, or `[rc, "stderr"]` for a
# failure) and logging each path to $T/gh.calls; never GitHub. Every name made up.
cat > "$T/gh" <<'PY'
#!/usr/bin/env python3
import json, os, sys
T = os.environ["OPS_T"]
path = next((a for a in sys.argv[1:] if a.startswith(("repos/", "search/"))), "")
with open(os.path.join(T, "gh.calls"), "a") as f:
    f.write(path + "\n")
with open(os.path.join(T, "gh.argv"), "a") as f:
    f.write(" ".join(sys.argv[1:]) + "\n")
# the longest key that the path holds wins: `issues/1` never answers for `issues/10`
# an issue's own answer names its repo, as GitHub's does, unless the fixture says otherwise (a transfer)
import re
one = re.match(r"repos/([^/]+/[^/]+)/issues/\d+$", path)
for k, (rc, out) in sorted(json.load(open(os.path.join(T, "gh.json"))).items(), key=lambda kv: -len(kv[0])):
    if k in path:
        if rc:
            sys.stderr.write(out + "\n"); sys.exit(rc)
        for o in out:
            if one and isinstance(o, dict):
                o.setdefault("repository_url", "https://api.github.com/repos/" + one.group(1))
            print(json.dumps(o))
        sys.exit(0)
sys.stderr.write("gh: HTTP 404: Not Found\n"); sys.exit(1)
PY
chmod +x "$T/gh"; export LIGHTHOUSE_OPS_GH="$T/gh" OPS_T="$T"
cat > "$T/repos.json" <<'EOF'
{"machine_account": "acme-bot",
 "repos": {"alpha": {"github": "acme/alpha", "hosts": []}, "beta": {"github": "acme/beta", "hosts": []},
           "secret": {"github": "acme/secret", "hosts": []}, "local": {"hosts": []}},
 "scopes": {"lab": {"repos": ["alpha", "beta"]}, "conf": {"repos": ["secret"], "confidential": true}}}
EOF
ghans() { python3 -c 'import json,sys; json.dump(json.loads(sys.argv[2]), open(sys.argv[1], "w"))' "$T/gh.json" "$1"; }
ing() { : > "$T/gh.calls"; n0=$(cat "$T/logs/intake.jsonl" 2>/dev/null | wc -l | tr -d ' '); smp ingest; }
# the rows the last pass appended, one per line: the fields named, `-` for an absent one
new() { tail -n +"$((n0 + 1))" "$T/logs/intake.jsonl" 2>/dev/null | python3 -c 'import json,sys
for l in sys.stdin:
    r = json.loads(l); print(" ".join(str(r.get(k, "-")) for k in sys.argv[1:]))' "$@"; }
sha() { python3 -c 'import hashlib,sys; print(hashlib.sha256(sys.argv[1].encode()).hexdigest()[:16])' "$1"; }
ST="$T/logs/intake-state.json"
ghans '{"repos/acme/alpha/issues?state=open": [0, [
   {"id": 101, "number": 1, "state": "open", "created_at": "2026-10-20T10:00:00Z", "updated_at": "2026-10-21T10:00:00Z", "html_url": "https://github.com/acme/alpha/issues/1",
    "labels": [{"name": "contact"}], "user": {"login": "someone"}, "author_association": "NONE", "body": "Hi, write to jane@example.com about the order"},
   {"id": 102, "number": 2, "state": "open", "created_at": "2026-10-22T10:00:00Z", "updated_at": "2026-10-22T10:00:00Z", "html_url": "https://github.com/acme/alpha/issues/2",
    "labels": [{"name": "Bug"}, {"name": "p1"}], "user": {"login": "owner1"}, "author_association": "OWNER", "body": "it breaks"},
   {"id": 103, "number": 3, "state": "open", "created_at": "2026-10-22T10:00:00Z", "updated_at": "2026-10-22T10:00:00Z", "pull_request": {"url": "x"},
    "labels": [], "user": {"login": "owner1"}, "author_association": "OWNER", "body": "a PR"}]],
 "repos/acme/alpha/issues?sort=updated&direction=desc": [0, [{"id": 102, "number": 2, "state": "open", "updated_at": "2026-10-22T10:00:00Z"}]],
 "repos/acme/beta/": [1, "gh: HTTP 502: Bad Gateway"]}'

echo "ops ingest: only the desk's job, only on the ops host"
unset LIGHTHOUSE_DESK; ing > "$T/out" 2>&1; check "$? $(test -e "$T/logs/intake.jsonl" && echo there || echo absent)" "2 absent" "outside the desk's job: refused, nothing written"
export LIGHTHOUSE_DESK=1; echo other-host > "$REGATTA_CONFIG/lighthouse/ops-host"
ing > "$T/out" 2>&1; check "$? $(wc -l < "$T/gh.calls" | tr -d ' ')" "2 0" "off the ops host: refused, nothing asked of GitHub"
echo "$HOSTNAME_" > "$REGATTA_CONFIG/lighthouse/ops-host"

echo "ops ingest: a first pass — the open issues, a field per row"
ing > "$T/out" 2>&1; check "$?" "0" "the first pass: exit 0 though one repo failed"
check "$(new event repo slug number kind label state author scope)" "- - - - - - - - conf
seen alpha acme/alpha 1 contact contact open stranger lab
seen alpha acme/alpha 2 bug Bug open member lab
- beta acme/beta - - - - - lab" "a row an open issue: event, repo, slug, number, kind, label, state, author, scope; no pull request; the fenced scope and the failing repo"
check "$(new body_sha | sed -n 2p) $(new created | sed -n 2p) $(new url | sed -n 2p)" "$(sha 'Hi, write to jane@example.com about the order') 1792490400 https://github.com/acme/alpha/issues/1" \
  "body_sha the body's sha256 (16 hex), created in epoch seconds, the issue's url"
check "$(new seen | sed -n 2p | python3 -c 'import sys,time; print(abs(int(sys.stdin.read()) - time.time()) < 120)')" "True" "seen: when the pass saw it"
check "$(grep -c 'jane@example.com\|write to\|it breaks' "$T/logs/intake.jsonl" "$ST" | awk -F: '{s+=$2} END {print s}')" "0" "no body, no email, in the rows or the state"
check "$(new scope skipped | sed -n 1p)" "conf fenced" "a confidential scope whose yard is not this host: scope and skipped: fenced"
check "$(grep -c 'acme/secret' "$T/gh.calls")" "0" "…its repo never read"
check "$(new skipped why | sed -n 4p)" "unread gh exited 1: gh: HTTP 502: Bad Gateway" "a GitHub read failing: its reason in a row, the rest read"
check "$(grep -c 'repos/acme/alpha/issues?state=open' "$T/gh.calls") $(grep -c 'comments' "$T/gh.calls")" "1 0" "a first pass reads the open issues and no comments: never the repo's history"
check "$(grep -c '"local"' "$ST")" "0" "a registry repo with no github is not the fleet's"
has "$(cat "$T/out")" "2 open issues; fenced: conf; unread: beta (gh exited 1" "the job's one line: counts, fenced, unread"

echo "ops ingest: since advances; an unchanged repo writes nothing"
since=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["repos"]["alpha"]["since"])' "$ST")
ghans '{"repos/acme/alpha/issues?state=all": [0, []], "repos/acme/alpha/issues/comments": [0, []], "repos/acme/beta/": [1, "gh: HTTP 502: Bad Gateway"]}'
ing > "$T/out" 2>&1; check "$? $(new event | wc -l | tr -d ' ')" "0 0" "a second pass over nothing new: no row — no repeat of the fenced scope or the same unread reason"
q=$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1]))' "$since")
check "$(grep -c "issues?state=all&.*since=$q" "$T/gh.calls") $(grep -c "issues/comments?.*since=$q" "$T/gh.calls")" "1 1" "…issues and comments read since the cursor the first pass left"
ghans '{"repos/acme/alpha/issues?state=all": [0, [
   {"id": 101, "number": 1, "state": "closed", "created_at": "2026-10-20T10:00:00Z", "updated_at": "2099-01-01T00:00:00Z", "html_url": "https://github.com/acme/alpha/issues/1",
    "labels": [{"name": "contact"}], "user": {"login": "someone"}, "author_association": "NONE", "body": "Hi, write to jane@example.com about the order"},
   {"id": 102, "number": 2, "state": "open", "created_at": "2026-10-22T10:00:00Z", "updated_at": "2099-01-01T00:00:00Z", "html_url": "https://github.com/acme/alpha/issues/2",
    "labels": [{"name": "Bug"}, {"name": "p1"}], "user": {"login": "owner1"}, "author_association": "OWNER", "body": "it breaks"},
   {"id": 104, "number": 4, "state": "open", "created_at": "2099-01-01T00:00:00Z", "updated_at": "2099-01-01T00:00:00Z", "html_url": "https://github.com/acme/alpha/issues/4",
    "labels": [{"name": "deadman"}], "user": {"login": "acme-bot"}, "author_association": "OWNER", "body": "the switch is late"}]],
 "repos/acme/alpha/issues/comments": [0, [
   {"id": 9001, "issue_url": "https://api.github.com/repos/acme/alpha/issues/2", "html_url": "https://github.com/acme/alpha/issues/2#issuecomment-9001",
    "created_at": "2099-01-01T00:00:00Z", "updated_at": "2099-01-01T00:00:00Z", "user": {"login": "passer"}, "author_association": "NONE", "body": "same here"},
   {"id": 9002, "issue_url": "https://api.github.com/repos/acme/alpha/issues/3", "html_url": "https://github.com/acme/alpha/pull/3#issuecomment-9002",
    "created_at": "2099-01-01T00:00:00Z", "updated_at": "2099-01-01T00:00:00Z", "user": {"login": "owner1"}, "author_association": "OWNER", "body": "on the PR"}]],
 "repos/acme/beta/": [0, []]}'
ing > "$T/out" 2>&1
check "$(new event number kind author state)" "closed 1 contact stranger closed
opened 4 deadman self open
comment 2 bug stranger open" "a third pass: a close, an issue opened by the machine account (self), a comment with its issue's kind; #2's only change a comment writes no issue row; a PR's comment none"
check "$(new body_sha | tail -1)" "$(sha 'same here')" "…the comment's own body hash"
check "$(python3 -c 'import json,sys; r=json.load(open(sys.argv[1]))["repos"]; print(r["alpha"]["since"], r["alpha"]["comments_since"], "skip" in r["beta"], r["beta"].get("since"))' "$ST")" \
  "2099-01-01T00:00:00Z 2099-01-01T00:00:00Z False None" "since advanced to the newest update, issues and comments each; beta's reason cleared once it reads, and with no issue read no cursor yet (S5: the first cursor is GitHub's newest updated_at, never this host's clock)"
ing > "$T/out" 2>&1; check "$(new event | wc -l | tr -d ' ')" "0" "the same answers again (GitHub's since answers the edge again): no row"
ghans '{"repos/acme/alpha/issues?state=all": [0, [
   {"id": 102, "number": 2, "state": "open", "created_at": "2026-10-22T10:00:00Z", "updated_at": "2099-01-02T00:00:00Z", "html_url": "https://github.com/acme/alpha/issues/2",
    "labels": [{"name": "stall"}], "user": {"login": "owner1"}, "author_association": "OWNER", "body": "it breaks"},
   {"id": 101, "number": 1, "state": "open", "created_at": "2026-10-20T10:00:00Z", "updated_at": "2099-01-02T00:00:00Z", "html_url": "https://github.com/acme/alpha/issues/1",
    "labels": [{"name": "contact"}], "user": {"login": "someone"}, "author_association": "NONE", "body": "Hi, write to jane@example.com about the order"}]],
 "repos/acme/alpha/issues/comments": [0, []], "repos/acme/beta/": [0, []]}'
ing > "$T/out" 2>&1; check "$(new event number kind label)" "edited 2 stall stall
reopened 1 contact contact" "a relabel is an edit with the new kind; a closed issue open again is reopened"

echo "ops intake: the open issues, for the board"
smp intake --json > "$T/out" 2>&1
check "$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["why"], [(c["kind"], c["repo"], c["number"], c["author"], c["scope"]) for c in d["open"]])' "$T/out")" \
  "None [('deadman', 'alpha', 4, 'self', 'lab'), ('stall', 'alpha', 2, 'member', 'lab'), ('contact', 'alpha', 1, 'stranger', 'lab')]" "one per open issue, by kind: deadman, stall, contact, bug, other"
sig1=$(field sig < "$T/out")
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); d["repos"]["alpha"]["open"]["4"]["created"] += 60; json.dump(d, open(sys.argv[1], "w"))' "$ST"
check "$(smp intake --json | field sig)" "$sig1" "the sig leaves out the clocks"
cp "$ST" "$T/state.keep"
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); d["scopes"]["lab"]["confidential"]=True; json.dump(d, open(sys.argv[1], "w"))' "$T/repos.json"
check "$(smp intake --json | field open)" "[]" "a scope made confidential since the pass: its cards dropped at once"
printf 'not json' > "$T/repos.json"
check "$(smp intake --json | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["open"], d["why"])')" "[] the registry cannot be read: no intake cards (a torn registry is no fence)" "a torn registry: no cards"

echo "ops ingest: a torn registry ingests nothing"
lines=$(wc -l < "$T/logs/intake.jsonl" | tr -d ' ')
ing > "$T/out" 2>&1; check "$? $(wc -l < "$T/logs/intake.jsonl" | tr -d ' ') $(wc -l < "$T/gh.calls" | tr -d ' ')" "3 $lines 0" "exit 3, no row, nothing asked of GitHub"
cmp -s "$ST" "$T/state.keep"; check "$?" "0" "…the state untouched"
cat > "$T/repos.json" <<EOF
{"machine_account": "acme-bot",
 "repos": {"alpha": {"github": "acme/alpha"}, "secret": {"github": "acme/secret"}},
 "scopes": {"lab": {"repos": ["alpha"]}, "conf": {"repos": ["secret"], "confidential": true, "yard": "$HOSTNAME_"}}}
EOF
ghans '{"repos/acme/alpha/": [0, []], "repos/acme/secret/": [0, []]}'
ing > "$T/out" 2>&1; check "$(grep -c 'acme/secret' "$T/gh.calls")" "2" "a confidential scope whose yard is this host: read here, inside its node (its newest update, its open issues)"
check "$(python3 -c 'import json,sys; print(sorted(json.load(open(sys.argv[1]))["repos"]))' "$ST")" "['alpha', 'secret']" "…and a repo gone from the registry (beta) leaves the state"

echo "ops ingest: a Project's items"
printf '%s\n' user/acme/3 'nonsense' > "$REGATTA_CONFIG/lighthouse/ops-projects"
ghans '{"repos/acme/alpha/": [0, []], "repos/acme/secret/": [0, []]}'
ing > "$T/out" 2>&1
check "$(new project skipped why)" "user/acme/3 unread GitHub's GraphQL refused the Project's read (FORBIDDEN)
nonsense unread 'nonsense' is not user/<login>/<number> or org/<login>/<number>" "a Project that does not read and a line that names none: each its reason, the rest read"
python3 -c 'import json,sys; a=json.load(open(sys.argv[1])); a["/graphql"]=[200, {"data": {"user": {"projectV2": {"items": {"pageInfo": {"hasNextPage": False}, "nodes": [
  {"id": "PVTI_1", "type": "ISSUE", "createdAt": "2026-10-25T10:00:00Z", "updatedAt": "2026-10-26T10:00:00Z",
   "content": {"__typename": "Issue", "number": 2, "url": "https://github.com/acme/alpha/issues/2", "issueState": "OPEN", "body": "it breaks", "authorAssociation": "OWNER",
               "author": {"login": "owner1"}, "repository": {"nameWithOwner": "acme/alpha"}, "labels": {"nodes": [{"name": "bug"}]}},
   "fieldValues": {"nodes": [{"__typename": "ProjectV2ItemFieldSingleSelectValue", "name": "Todo", "field": {"name": "Status"}},
                             {"__typename": "ProjectV2ItemFieldTextValue", "text": "the issue title", "field": {"name": "Title"}}]}},
  {"id": "PVTI_2", "type": "ISSUE", "createdAt": "2026-10-25T10:00:00Z", "updatedAt": "2026-10-26T10:00:00Z",
   "content": {"__typename": "Issue", "number": 7, "url": "https://github.com/acme/other/issues/7", "issueState": "OPEN", "body": "x", "authorAssociation": "NONE",
               "author": {"login": "z"}, "repository": {"nameWithOwner": "acme/secret"}, "labels": {"nodes": []}}, "fieldValues": {"nodes": []}}]}}}}}]; json.dump(a, open(sys.argv[1], "w"))' "$T/answers.json"
printf '%s\n' user/acme/3 > "$REGATTA_CONFIG/lighthouse/ops-projects"
sed -i.bak 's/, "yard": "[^"]*"//' "$T/repos.json" && rm -f "$T/repos.json.bak"
ing > "$T/out" 2>&1
check "$(new event project item repo number kind state author fields | grep '^item')" "item user/acme/3 PVTI_1 alpha 2 bug open member {'Status': 'Todo'}" \
  "an item with its fields (no text field), its issue's repo, kind and author; a fenced scope's item skipped"
check "$(grep -c 'the issue title' "$T/logs/intake.jsonl")" "0" "…no text field's value in a row"
check "$(python3 -c 'import json,sys; c=[json.loads(l) for l in open(sys.argv[1])]; g=[x for x in c if x["url"].endswith("/graphql")]; b=json.dumps(g[-1]["body"]); print(g[-1]["headers"]["Authorization"] == "Bearer " + sys.argv[2], "mutation" in b, "projectV2(number" in b)' "$T/calls" "$TOK")" \
  "True False True" "…read with the owner's token in the header, a query, never a mutation"
ing > "$T/out" 2>&1; check "$(new event | wc -l | tr -d ' ')" "0" "the same items again: no row (the Project's own since)"
check "$(python3 -c 'import json,sys; c=[json.loads(l) for l in open(sys.argv[1])]; q=[x for x in c if x["url"].endswith("/graphql")][-1]["body"]["query"]; print("issueState: state" in q and "prState: state" in q)' "$T/calls")" "True" \
  "the query aliases Issue's and PullRequest's state (two enum types under one key fail GraphQL's validation)"
printf '%s\n' user/acme/4 > "$REGATTA_CONFIG/lighthouse/ops-projects"
python3 -c 'import json,sys; a=json.load(open(sys.argv[1])); a["/graphql"]=[200, {"data": {"user": {"projectV2": {"items": {"pageInfo": {"hasNextPage": True, "endCursor": "c"}, "nodes": [
  {"id": "PVTI_8", "type": "ISSUE", "createdAt": "2026-10-25T10:00:00Z", "updatedAt": "2026-10-26T10:00:00Z",
   "content": {"__typename": "Issue", "number": 8, "url": "https://github.com/elsewhere/hidden/issues/8", "issueState": "OPEN", "body": "y", "authorAssociation": "NONE",
               "author": {"login": "z"}, "repository": {"nameWithOwner": "elsewhere/hidden"}, "labels": {"nodes": []}}, "fieldValues": {"nodes": []}},
  {"id": "PVTI_9", "type": "ISSUE", "createdAt": "2026-10-01T10:00:00Z", "updatedAt": "2026-10-02T10:00:00Z",
   "content": {"__typename": "Issue", "number": 9, "url": "https://github.com/acme/alpha/issues/9", "issueState": "CLOSED", "body": "old", "authorAssociation": "OWNER",
               "author": {"login": "owner1"}, "repository": {"nameWithOwner": "acme/alpha"}, "labels": {"nodes": []}}, "fieldValues": {"nodes": []}}]}}}}}]; json.dump(a, open(sys.argv[1], "w"))' "$T/answers.json"
ing > "$T/out" 2>&1
check "$(new event item repo slug url number state | grep '^item' | sort -u)" "item PVTI_8 None None None 8 open" \
  "a first read: an unregistered repo's item without its name or link, a closed item (the history) no row (the stub answers its one page to every cursor)"
has "$(cat "$T/out")" "Projects cut at their first user/acme/4" "…a read the page cap ended is said, never silent"
rm -f "$REGATTA_CONFIG/lighthouse/ops-projects"

echo "ops ingest: a repo in an open scope and a confidential one is fenced"
cp "$T/repos.json" "$T/repos.keep"
cat > "$T/repos.json" <<'EOF'
{"machine_account": "acme-bot",
 "repos": {"alpha": {"github": "acme/alpha"}, "secret": {"github": "acme/secret"}},
 "scopes": {"all": {"repos": ["*"]}, "conf": {"repos": ["secret"], "confidential": true, "yard": "elsewhere"}}}
EOF
ghans '{"repos/acme/alpha/": [0, []], "repos/acme/secret/": [0, []]}'
ing > "$T/out" 2>&1; check "$(grep -c 'acme/secret' "$T/gh.calls") $(python3 -c 'import json,sys; s=json.load(open(sys.argv[1])); print(s["fenced"], "secret" in s["repos"])' "$ST")" "0 ['conf'] False" \
  "an umbrella scope listed first never opens a confidential one's repo: fenced, its state dropped"
python3 -c 'import json,sys; s=json.load(open(sys.argv[1])); s["repos"]["secret"]={"open": {"7": {"number": 7, "kind": "bug"}}}; json.dump(s, open(sys.argv[1], "w"))' "$ST"
check "$(smp intake --json | python3 -c 'import json,sys; r=[c["repo"] for c in json.load(sys.stdin)["open"]]; print("secret" in r, "alpha" in r)')" "False True" "…nor cards it, the umbrella's other repos carded"
cp "$T/repos.keep" "$T/repos.json"

echo "ops ingest: one pass at a time"
python3 -c 'import fcntl,sys,time; f=open(sys.argv[1],"a"); fcntl.flock(f, fcntl.LOCK_EX); open(sys.argv[2],"w").close(); time.sleep(120)' "$T/logs/intake.lock" "$T/locked" &
LK=$!; i=0; while [ ! -e "$T/locked" ] && [ $i -lt 75 ]; do sleep 0.2; i=$((i + 1)); done
ing > "$T/out" 2>&1; check "$? $(wc -l < "$T/gh.calls" | tr -d ' ')" "0 0" "another pass holds the lock: this one skipped, nothing read"
has "$(cat "$T/out")" "another pass holds" "…saying so"
kill "$LK" 2>/dev/null; wait "$LK" 2>/dev/null
# ---- S5: the intake's fixes ---------------------------------------------------------------------
echo "ops ingest (S5): the logbook and beacon's sink beside the registry, bots, the daily re-read, the first cursor"
cat > "$T/repos.json" <<'EOF'
{"machine_account": "acme-bot", "repos": {"alpha": {"github": "acme/alpha"}}, "scopes": {"lab": {"repos": ["alpha"]}}}
EOF
rm -f "$ST" "$T/logs/intake.jsonl"
mkdir -p "$REGATTA_CONFIG/helm"; printf '%s\n' acme/logbook > "$REGATTA_CONFIG/helm/logbook-repo"
mkdir -p "$REGATTA_CONFIG/beacon"; printf '%s\n' '{"sink": {"type": "github", "repo": "acme/inbox"}}' > "$REGATTA_CONFIG/beacon/config.json"
printf '%s\n' 'Beacon-App[bot]' > "$REGATTA_CONFIG/lighthouse/ops-bots"
ghans '{"repos/acme/alpha/issues?state=open": [0, [
   {"id": 201, "number": 1, "state": "open", "created_at": "2026-10-20T10:00:00Z", "updated_at": "2026-10-21T10:00:00Z", "html_url": "https://github.com/acme/alpha/issues/1",
    "labels": [{"name": "bug"}], "user": {"login": "owner1"}, "author_association": "OWNER", "body": "b1"},
   {"id": 202, "number": 2, "state": "open", "created_at": "2026-10-20T10:00:00Z", "updated_at": "2026-10-23T09:00:00Z", "html_url": "https://github.com/acme/alpha/issues/2",
    "labels": [{"name": "bug"}], "user": {"login": "owner1"}, "author_association": "OWNER", "body": "b2"}]],
 "repos/acme/logbook/issues?state=open": [0, [
   {"id": 301, "number": 5, "state": "open", "created_at": "2026-10-22T10:00:00Z", "updated_at": "2026-10-22T10:00:00Z", "html_url": "https://github.com/acme/logbook/issues/5",
    "labels": [{"name": "deadman"}], "user": {"login": "deadman-acme[bot]"}, "author_association": "NONE", "body": "late"}]],
 "repos/acme/inbox/issues?state=open": [0, [
   {"id": 401, "number": 9, "state": "open", "created_at": "2026-10-22T10:00:00Z", "updated_at": "2026-10-22T10:00:00Z", "html_url": "https://github.com/acme/inbox/issues/9",
    "labels": [], "user": {"login": "beacon-app[bot]"}, "author_association": "NONE", "body": "Hi, write to jane@example.com"},
   {"id": 402, "number": 10, "state": "open", "created_at": "2026-10-22T10:00:00Z", "updated_at": "2026-10-22T10:00:00Z", "html_url": "https://github.com/acme/inbox/issues/10",
    "labels": [{"name": "bug"}], "user": {"login": "beacon-app[bot]"}, "author_association": "NONE", "body": "your form is broken, call 555"}]],
 "repos/acme/alpha/issues?sort=updated&direction=desc": [0, [{"id": 299, "number": 7, "state": "closed", "updated_at": "2026-10-25T08:00:00Z"}]],
 "repos/acme/logbook/issues?sort=updated&direction=desc": [0, [{"id": 301, "number": 5, "state": "open", "updated_at": "2026-10-22T10:00:00Z"}]],
 "repos/acme/inbox/issues?sort=updated&direction=desc": [0, [{"id": 402, "number": 10, "state": "open", "updated_at": "2026-10-22T10:00:00Z"}]]}'
ing > "$T/out" 2>&1; check "$?" "0" "a first pass over the registry and the two configured repos"
check "$(new event repo slug number kind author scope | sort)" "seen acme/inbox acme/inbox 10 contact bot None
seen acme/inbox acme/inbox 9 contact bot None
seen acme/logbook acme/logbook 5 deadman stranger None
seen alpha acme/alpha 1 bug member lab
seen alpha acme/alpha 2 bug member lab" "helm/logbook-repo and beacon's sink.repo read, keyed by their slug; every sink issue a contact, its labels whatever they say (a visitor's words never reach a model); a bot ops-bots names is \`bot\`, one it does not a stranger"
check "$(python3 -c 'import json,sys; r=json.load(open(sys.argv[1]))["repos"]; print(r["alpha"]["since"], r["alpha"]["edge"], r["acme/logbook"]["since"])' "$ST")" \
  "2026-10-25T08:00:00Z ['299'] 2026-10-22T10:00:00Z" "the first cursor is the newest update of any issue (a closed one here), its id the edge: GitHub's clock, never this host's, and never the open set's newest, whose history the next pass would replay"
check "$(grep -c 'per_page=1&' "$T/gh.calls") $(grep -c -- '--paginate.*per_page=1&' "$T/gh.argv")" "3 0" "…one unpaginated page a repo"
check "$(smp intake --json | python3 -c 'import json,sys; print(sorted((c["repo"], c["number"]) for c in json.load(sys.stdin)["open"]))')" \
  "[('acme/inbox', 9), ('acme/inbox', 10), ('acme/logbook', 5), ('alpha', 1), ('alpha', 2)]" "…their issues carded beside the registry's"
check "$(grep -c 'jane@example.com' "$T/logs/intake.jsonl" "$ST" | awk -F: '{s+=$2} END {print s}')" "0" "…the contact's words in no row and no state"
ghans '{"repos/acme/alpha/issues?state=all": [0, []], "repos/acme/alpha/issues/comments": [0, []],
 "repos/acme/alpha/issues?state=open": [0, [{"id": 201, "number": 1, "state": "open", "updated_at": "2026-10-21T10:00:00Z", "labels": [{"name": "bug"}], "user": {"login": "owner1"}, "author_association": "OWNER", "body": "b1"}]],
 "repos/acme/logbook/": [0, []], "repos/acme/inbox/": [0, []]}'
ing > "$T/out" 2>&1; check "$(new event | wc -l | tr -d ' ') $(grep -c 'issues?state=open' "$T/gh.calls")" "0 0" "the next pass within a day: no state=open re-read"
check "$(grep -c 'repos/acme/alpha/issues?state=all&.*since=2026-10-25T08%3A00%3A00Z' "$T/gh.calls") $(grep -c 'repos/acme/alpha/issues/comments?.*since=2026-10-25T08%3A00%3A00Z' "$T/gh.calls")" "1 1" \
  "…the second pass reads from the first cursor, the newest update of any issue: no history replayed"
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); [r.update(reconciled=1) for r in d["repos"].values()]; json.dump(d, open(sys.argv[1], "w"))' "$ST"
ing > "$T/out" 2>&1
check "$(new event repo number kind | sort)" "dropped acme/inbox 10 contact
dropped acme/inbox 9 contact
dropped acme/logbook 5 deadman
dropped alpha 2 bug" "a day on: the open set re-read, and a card GitHub no longer lists open is dropped (deleted, transferred, closed unseen)"
check "$(smp intake --json | python3 -c 'import json,sys; print([(c["repo"], c["number"]) for c in json.load(sys.stdin)["open"]])')" "[('alpha', 1)]" "…its card gone from the board"
check "$(python3 -c 'import json,sys,time; r=json.load(open(sys.argv[1]))["repos"]["alpha"]; print(time.time() - r["reconciled"] < 120)' "$ST")" "True" "…the re-read's time kept"
ghans '{"repos/acme/": [1, "gh: HTTP 502: Bad Gateway"]}'
ing > "$T/out" 2>&1; check "$?" "5" "a pass that read no repo at all: exit 5 (never 0, never 1)"
has "$(cat "$T/out")" "no repo read at all" "…saying so"
printf '%s\n' acme/inbox > "$REGATTA_CONFIG/helm/logbook-repo"
cat > "$T/unit.py" <<'PY'
import importlib.machinery, importlib.util, sys
loader = importlib.machinery.SourceFileLoader("ops", sys.argv[1])
spec = importlib.util.spec_from_loader("ops", loader)
ops = importlib.util.module_from_spec(spec)
loader.exec_module(ops)
print(ops.extra_repos({}))
print(ops.named_paths("the crash is in modules/x/bin/tool. See ./modules/x/README.md, and a/b; v1.2 too"))
PY
check "$(python3 "$T/unit.py" "$OPS" | head -1)" "{'acme/inbox': ('acme/inbox', 'contact')}" "the sink and the logbook one repo: its issues contacts (the sink wins the slug)"
check "$(python3 "$T/unit.py" "$OPS" | tail -1)" "['modules/x/bin/tool', 'modules/x/README.md', 'a/b']" "a named path loses a sentence's closing punctuation and a leading ./"
rm -f "$REGATTA_CONFIG/helm/logbook-repo" "$REGATTA_CONFIG/beacon/config.json" "$REGATTA_CONFIG/lighthouse/ops-bots"

# ---- S5: classify, logged -----------------------------------------------------------------------
# The gate a stub (ops.gate_module replaced in-process): each item's labels read from an `L:<importance>,<urgency>,
# <cost>,<clarity>` marker in its title, each call logged to $T/gate.calls with its site, source and text, a site
# named in $T/gate.fail raising. gh answers the issue fetch and the PR search from gh.json, as above; autofinish a
# stub module in $T/tools (MONEY_RE, repo_config, published). Every name made up.
cat > "$T/cls.py" <<'PY'
import importlib.machinery, importlib.util, json, os, re, sys
from pathlib import Path
loader = importlib.machinery.SourceFileLoader("ops", sys.argv[1])
spec = importlib.util.spec_from_loader("ops", loader)
ops = importlib.util.module_from_spec(spec)
loader.exec_module(ops)
T, tools = Path(os.environ["OPS_T"]), Path(sys.argv[2])
ops.common.tool = lambda name: (tools / name) if (tools / name).is_file() else None
class Gate:
    @staticmethod
    def resolve(site):
        off = (T / "gate.off").read_text().split() if (T / "gate.off").exists() else []
        if site in off:
            raise RuntimeError("models.json: no row for %s — a call site needs its row before it runs" % site)
        return {"site": site, "provider": "claude"}
    @staticmethod
    def classify(site, items, ask, labels, context=None, source=None, caller=None, **kw):
        with open(T / "gate.calls", "a") as f:
            f.write(json.dumps({"site": site, "source": source, "items": items}) + "\n")
        fail = (T / "gate.fail").read_text().split() if (T / "gate.fail").exists() else []
        if site in fail:
            raise RuntimeError("%s: Claude's reply, twice: the reply is not JSON: 'ECHO %s'" % (site, list(items.values())[0][:40]))
        dim = list(ops.SITES).index(site.split(".", 1)[1])
        return {"items": {i: {"label": re.search(r"L:(\S+)", t).group(1).split(",")[dim], "p": None} for i, t in items.items()},
                "cost_usd": 0.01, "provider": "claude", "model": "stub", "ms": 1}
if not os.environ.get("OPS_REAL_GATE"):
    ops.gate_module = lambda: Gate
if os.environ.get("OPS_CLASSIFY_MAX"):
    ops.CLASSIFY_MAX = int(os.environ["OPS_CLASSIFY_MAX"])
sys.exit(ops.main(sys.argv[3:]))
PY
cls() { : > "$T/gh.calls"; : > "$T/gh.argv"; : > "$T/gate.calls"; v0=$(cat "$T/logs/ops-verdicts.jsonl" 2>/dev/null | wc -l | tr -d ' '); python3 "$T/cls.py" "$OPS" "$TL" "$@"; }
# the verdicts the last pass appended, one per line: the fields named (a.b for a nested one), `-` for an absent one
verd() { tail -n +"$((v0 + 1))" "$T/logs/ops-verdicts.jsonl" 2>/dev/null | python3 -c 'import json,sys
for l in sys.stdin:
    r = json.loads(l); out = []
    for k in sys.argv[1:]:
        v = r
        for p in k.split("."):
            v = v.get(p, "-") if isinstance(v, dict) else "-"
        out.append(str(v))
    print(" ".join(out))' "$@"; }
cat > "$TL/autofinish" <<'PY'
import re
MONEY_RE = re.compile(r"[$]\s?\d|\binvoice\b", re.I)
class branches:
    main_branch = staticmethod(lambda repo: "main")
def repo_config(repo, main):
    return "all", [], None, ["modules/x/hooks/"]
def published(repo, main):
    return {"modules/x/bin/tool", "modules/x/README.md"}
PY
# a clone of alpha and beta in the scratch HOME's projects folder (common.PROJECTS), where repo_paths() looks
python3 -c 'import os; [os.makedirs(os.path.join(os.environ["HOME"], "projects", n, ".git"), exist_ok=True) for n in ("alpha", "beta")]' 
cat > "$T/repos.json" <<EOF
{"machine_account": "acme-bot",
 "repos": {"alpha": {"github": "acme/alpha"}, "beta": {"github": "acme/beta"}, "secret": {"github": "acme/secret"}},
 "scopes": {"lab": {"repos": ["alpha", "beta"], "yard": "$HOSTNAME_"}, "conf": {"repos": ["secret"], "confidential": true, "yard": "elsewhere"}}}
EOF
# the intake as a pass would have left it: a row an open issue, and the open set (number: kind, author, label)
intake() { python3 - "$T/logs" "$@" <<'PY'
import json, sys
logs, rows, st = sys.argv[1], [], {"repos": {}}
for spec in sys.argv[2:]:
    repo, n, kind, author, sha = spec.split(":")
    rows.append({"seen": 1700000000 + int(n), "event": "seen", "repo": repo, "slug": "acme/" + repo, "scope": "lab", "number": int(n),
                 "kind": kind, "label": kind if kind != "other" else None, "state": "open", "author": author, "body_sha": sha})
    st["repos"].setdefault(repo, {"since": "2026-10-01T00:00:00Z", "open": {}})["open"][n] = {"number": int(n), "kind": kind}
with open(logs + "/intake.jsonl", "a") as f:
    f.write("".join(json.dumps(r) + "\n" for r in rows))
old = json.load(open(logs + "/intake-state.json")) if __import__("os").path.exists(logs + "/intake-state.json") else {"repos": {}}
for k, v in st["repos"].items():
    old["repos"].setdefault(k, {"since": v["since"], "open": {}})["open"].update(v["open"])
json.dump(old, open(logs + "/intake-state.json", "w"))
PY
}
# an issue as GitHub answers the fetch: title (with the marker), labels, body
iss() { printf '"repos/acme/%s/issues/%s": [0, [{"number": %s, "state": "%s", "title": "%s", "labels": [%s], "body": "%s"}]]' "$1" "$2" "$2" "${6:-open}" "$3" "$4" "$5"; }
B='{"name": "bug"}'
ghans "{$(iss alpha 1 'TITLE-ONE L:2,2,xs,clear' "$B" 'a typo in the help'),
 $(iss alpha 2 'L:2,2,s,clear' "$B" 'off by one'),
 $(iss beta 3 'L:3,3,m,clear' "$B" 'the export is slow'),
 $(iss beta 4 'L:2,1,s,unclear' '' 'it does a thing'),
 $(iss beta 5 'L:2,1,xs,unclear' "$B" 'broken'),
 $(iss alpha 6 'L:1,1,xs,clear' '{"name": "contact"}' 'Hi, write to jane@example.com'),
 $(iss beta 7 'L:5,5,s,clear' "$B" 'all data lost'),
 $(iss alpha 8 'L:1,1,xs,clear' '' 'add a flag'),
 $(iss beta 9 'L:2,2,xs,clear' "$B" 'a typo'),
 $(iss alpha 10 'L:2,2,xs,clear' "$B" 'rotate the api key in the config'),
 $(iss alpha 12 'L:2,2,xs,clear' "$B" 'modules/x/bin/tool prints the wrong line'),
 $(iss secret 11 'L:2,2,xs,clear' "$B" 'a secret repo'),
 \"search/issues\": [0, [{\"total_count\": 0}]]}"
mkdir -p "$TL"; rm -f "$T/logs/intake.jsonl" "$T/logs/intake-state.json"
intake alpha:1:bug:member:s1 alpha:2:bug:member:s2 beta:3:bug:member:s3 beta:4:other:member:s4 beta:5:bug:stranger:s5 \
  alpha:6:contact:stranger:s6 beta:7:bug:member:s7 alpha:8:other:member:s8 beta:9:bug:member:s9 alpha:10:bug:member:s10 \
  alpha:12:bug:member:s12 secret:11:bug:member:s11
# a fresh sample: a login eligible, the week's list spend
printf '{"as_of": %s, "host": "%s", "weeks": {"acct-a": {"weekly": 30, "eligible": true}}, "cost": {"week_list": 100.0}}\n' "$(date +%s)" "$HOSTNAME_" > "$T/logs/ops.jsonl"
OJ="$REGATTA_CONFIG/lighthouse/ops.json"; rm -f "$OJ"

echo "ops classify: off, refused, torn"
unset LIGHTHOUSE_DESK; cls classify > "$T/out" 2>&1; check "$?" "2" "outside the desk's job: refused"
export LIGHTHOUSE_DESK=1
cls classify > "$T/out" 2>&1; check "$? $(test -e "$T/logs/ops-verdicts.jsonl" && echo there || echo absent) $(wc -l < "$T/gate.calls" | tr -d ' ')" "0 absent 0" "no lighthouse/ops.json: the desk is off — no verdict, no gate call"
has "$(cat "$T/out")" "off: no" "…saying so"
printf 'not json' > "$OJ"; cls classify > "$T/out" 2>&1; check "$?" "3" "a torn ops.json: exit 3, nothing classified"
printf '%s\n' '{"dry": true, "max_auto_run_day": 9}' > "$OJ"; cls classify > "$T/out" 2>&1
check "$? $(test -e "$T/logs/ops-verdicts.jsonl" && echo there || echo absent)" "3 absent" "an unknown key (a typo): refused whole, never a silent default"
has "$(cat "$T/out")" "unknown key max_auto_run_day" "…naming it"
printf '%s\n' '{"repos": ["alpha"]}' > "$OJ"
printf 'not json' > "$T/repos.keep2"; cp "$T/repos.json" "$T/repos.good"; cp "$T/repos.keep2" "$T/repos.json"
cls classify > "$T/out" 2>&1; check "$? $(wc -l < "$T/gate.calls" | tr -d ' ')" "3 0" "a torn registry: exit 3, nothing sent to the gate"
cp "$T/repos.good" "$T/repos.json"

echo "ops classify: a pass — a verdict per issue, a case per rung"
cls classify > "$T/out" 2>&1; check "$?" "0" "the pass: exit 0"
check "$(verd key rung would | sort -t'#' -k1,1 -k2,2n)" "alpha#1 1 lay
alpha#2 1 none
alpha#6 4 alarm
alpha#8 0 none
alpha#10 1 skipper
alpha#12 1 none
beta#3 2 skipper
beta#4 3 ask
beta#5 3 none
beta#7 4 alarm
beta#9 1 skipper" "rung 1 laid once (dry), a second in the repo held by the day's repo cap, one with a held class and one off the repos list to a skipper; rung 2 a skipper; rung 3 asks a member, never a stranger; rung 4 by kind and by importance 5; rung 0 none"
check "$(verd key labels.importance labels.urgency labels.cost labels.clarity rung_why | grep '^alpha#1 ')" "alpha#1 2 2 xs clear a clear xs bug at importance 2 by a member" "the four labels and the rung's why"
check "$(verd key caps.max_auto_runs_repo_day | grep '^alpha#2')" "alpha#2 1 laid in alpha in the last day, the cap 1" "a count cap counts this pass's lays"
check "$(verd key caps.repos | grep '^beta#9')" "beta#9 beta is not in repos" "the repos cap"
check "$(verd key held caps.held | grep '^alpha#10')" "alpha#10 ['credentials'] held: credentials" "the held-class scan: a credential named in the text"
check "$(verd key caps | grep '^alpha#1 ' | python3 -c 'import sys,ast; d=ast.literal_eval(sys.stdin.read().split(" ",1)[1]); print(sorted(d), set(d.values()))')" \
  "['cost_auto', 'held', 'importance_auto_max', 'labels', 'max_auto_runs_day', 'max_auto_runs_repo_day', 'max_open_auto_prs', 'place', 'repos', 'week_share'] {'ok'}" "every cap judged before a lay, each ok"
check "$(verd key caps | grep '^beta#3 ')" "beta#3 {'week_share': 'ok'}" "rung 2: the week alone"
check "$(verd key published | grep -E '^alpha#(1|12) ')" "alpha#1 unknown
alpha#12 yes" "published: a path the issue names on the allowlist is yes; none named is unknown"
check "$(verd key gate_cost_usd dry laid | grep '^alpha#1 ')" "alpha#1 0.008 True False" "…the gate's share, dry, nothing laid"
check "$(grep -c 'secret' "$T/gh.calls") $(grep -c 'acme/secret\|"secret"' "$T/gate.calls") $(verd key | grep -c secret)" "0 0 0" "a confidential repo whose yard is elsewhere: never fetched, never sent to the gate, no verdict"
check "$(grep -c 'jane@example.com' "$T/gate.calls") $(grep -c 'issues/6' "$T/gh.calls")" "0 0" "a contact never goes to a model, nor is its issue fetched"
check "$(grep -c 'TITLE-ONE\|a typo in the help\|jane@example.com\|modules/x/bin/tool' "$T/logs/ops-verdicts.jsonl" "$T/logs/classify-state.json" | awk -F: '{s+=$2} END {print s}')" "0" "no title, body, path or address in a verdict or the state"
check "$(grep -c 'TITLE-ONE' "$T/gate.calls") $(python3 -c 'import json,sys; print(sorted({json.loads(l)["site"] for l in open(sys.argv[1])}))' "$T/gate.calls")" \
  "4 ['lighthouse.clarity', 'lighthouse.cost', 'lighthouse.importance', 'lighthouse.urgency']" "…the words went to the four gate rows, one call each"
check "$(grep -Evc '^(repos/acme/[a-z]+/issues/[0-9]+|search/issues\?q=.*)$' "$T/gh.calls") $(grep -Ec -- '-X|--method|-f |--field|POST|PATCH' "$T/gh.argv") $(grep -c . "$T/gh.calls")" "0 0 11" "dry: gh only read an issue and searched — nothing commented, labelled or written"
has "$(cat "$T/out")" "11 verdicts" "the job's one line"

echo "ops classify: the next passes"
cls classify > "$T/out" 2>&1; check "$(verd key | wc -l | tr -d ' ') $(wc -l < "$T/gate.calls" | tr -d ' ')" "0 0" "nothing new: no verdict, no gate call"
python3 -c 'import json,sys; r={"seen": 1800000000, "event": "edited", "repo": "alpha", "number": 8, "kind": "bug", "label": "bug", "state": "open", "author": "member", "body_sha": "s8b"}; open(sys.argv[1], "a").write(json.dumps(r) + "\n")' "$T/logs/intake.jsonl"
cls classify > "$T/out" 2>&1; check "$(verd key event | tr '\n' ' ')" "alpha#8 edited " "an edited issue (its body or label changed): classified again"
echo lighthouse.cost > "$T/gate.fail"
intake alpha:13:bug:member:s13 alpha:14:contact:stranger:s14
python3 -c 'import json,sys; a=json.load(open(sys.argv[1])); a["repos/acme/alpha/issues/13"]=[0, [{"number": 13, "state": "open", "title": "L:2,2,xs,clear", "labels": [{"name": "bug"}], "body": "x"}]]; json.dump(a, open(sys.argv[1], "w"))' "$T/gh.json"
cls classify > "$T/out" 2>&1
check "$? $(verd key would tries error | sort)" "0 alpha#13 none 1 gate: cost: lighthouse.cost: Claude's reply, twice
alpha#14 alarm - -" "a gate row that fails: its reason on the item's row (never the reply's echo of the issue), would none, and the rest of the pass goes on"
check "$(grep -c ECHO "$T/logs/ops-verdicts.jsonl")" "0" "…the reply's tail kept out of the log"
rm -f "$T/gate.fail"; cls classify > "$T/out" 2>&1
check "$(verd key rung tries | tr '\n' ' ')" "alpha#13 1 - " "…tried again next pass, and classified"
python3 -c 'import json,sys; s=json.load(open(sys.argv[1])); print(s["pending"])' "$T/logs/classify-state.json" > "$T/pend"
check "$(cat "$T/pend")" "{}" "…nothing left queued"

echo "ops classify: a pass's limit, the week, a closed issue"
intake alpha:15:bug:member:s15 alpha:16:bug:member:s16 alpha:17:bug:member:s17
for n in 15 16 17; do python3 -c 'import json,sys; a=json.load(open(sys.argv[1])); a["repos/acme/alpha/issues/"+sys.argv[2]]=[0, [{"number": int(sys.argv[2]), "state": "open", "title": "L:3,3,m,clear", "labels": [{"name": "bug"}], "body": "x"}]]; json.dump(a, open(sys.argv[1], "w"))' "$T/gh.json" "$n"; done
python3 -c 'import json,sys; a=json.load(open(sys.argv[1])); a["repos/acme/alpha/issues/17"][1][0]["state"]="closed"; json.dump(a, open(sys.argv[1], "w"))' "$T/gh.json"
printf '{"as_of": %s, "host": "%s", "weeks": {"acct-a": {"weekly": 99, "eligible": false}}, "cost": {"week_list": 100.0}}\n' "$(date +%s)" "$HOSTNAME_" >> "$T/logs/ops.jsonl"
OPS_CLASSIFY_MAX=1 cls classify > "$T/out" 2>&1
check "$(verd key would caps.week_share | tr '\n' ' ')" "alpha#15 none the week is over: no login is eligible " "the week over: rung 2 cards (none) instead of a skipper; one issue a pass at a limit of 1"
has "$(cat "$T/out")" "2 queued for the next pass" "…the rest queued, never lost past the intake's offset"
OPS_CLASSIFY_MAX=5 cls classify > "$T/out" 2>&1
check "$(verd key | tr '\n' ' ')" "alpha#16 " "the next pass takes the queue; a closed issue (#17) gets no verdict"
has "$(cat "$T/out")" "1 closed since" "…counted as closed"
printf '{"as_of": %s, "host": "%s", "weeks": {"acct-a": {"eligible": true}}, "cost": {"week_list": 0.05}}\n' "$(date +%s)" "$HOSTNAME_" >> "$T/logs/ops.jsonl"
python3 -c 'import json,sys; r={"seen": 1800000001, "event": "edited", "repo": "alpha", "number": 16, "kind": "bug", "label": "bug", "state": "open", "author": "member", "body_sha": "s16b"}; open(sys.argv[1], "a").write(json.dumps(r) + "\n")' "$T/logs/intake.jsonl"
cls classify > "$T/out" 2>&1
has "$(verd caps.week_share)" "the desk spent" "the desk's own gate spend over week_share of the week's list spend: refused"

echo "ops classify: the core's real gate and its shipped rows, claude a stub"
cat > "$T/claude" <<'PY'
#!/usr/bin/env python3
import json, re, sys
prompt = sys.stdin.read()
ids = re.findall(r"^(i\d+): ", prompt, re.M)
pick = {"How much": "2", "How soon": "1", "How big": "xs", "Could a": "clear"}
lab = next(v for k, v in pick.items() if k in prompt)
print(json.dumps({"structured_output": {i: lab for i in ids}, "total_cost_usd": 0.002}))
PY
chmod +x "$T/claude"
intake alpha:18:bug:member:s18
python3 -c 'import json,sys; a=json.load(open(sys.argv[1])); a["repos/acme/alpha/issues/18"]=[0, [{"number": 18, "state": "open", "title": "the help has a typo", "labels": [{"name": "bug"}], "body": "x"}]]; json.dump(a, open(sys.argv[1], "w"))' "$T/gh.json"
printf '{"as_of": %s, "host": "%s", "weeks": {"acct-a": {"eligible": true}}, "cost": {"week_list": 1000.0}}\n' "$(date +%s)" "$HOSTNAME_" >> "$T/logs/ops.jsonl"
OPS_REAL_GATE=1 GATE_TABLE="$C/../regatta/settings/models.json" GATE_LOG="$T/gate.jsonl" CLAUDE_BIN="$T/claude" cls classify > "$T/out" 2>&1
check "$(verd key labels.importance labels.cost labels.clarity rung gate.model)" "alpha#18 2 xs clear 1 claude-sonnet-5-5" "the four lighthouse.* rows resolve and classify through the gate (Sonnet, as shipped)"
check "$(python3 -c 'import json,sys; print(sorted({json.loads(l)["site"] for l in open(sys.argv[1])}), {json.loads(l)["source"] for l in open(sys.argv[1])})' "$T/gate.jsonl")" \
  "['lighthouse.clarity', 'lighthouse.cost', 'lighthouse.importance', 'lighthouse.urgency'] {'alpha'}" "…the gate's log names each site and the repo as the source"

echo "ops digest: the logged week, counted"
cls digest --json > "$T/out" 2>&1
check "$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["by_rung"], d["by_would"]["lay"], d["rung1_published"], d["errors"], d["refused"]["max_auto_runs_repo_day"], d["gate_usd"] > 0)' "$T/out")" \
  "{'0': 1, '1': 8, '2': 4, '3': 2, '4': 3} 1 {'no': 0, 'unknown': 7, 'yes': 1} 1 6 True" "by rung, the lays, rung-1 candidates on published paths (D4's fact), errors, a cap's refusals, the gate's spend"
cls digest > "$T/out" 2>&1
has "$(cat "$T/out")" "rung 1 on published paths (D4's fact): 1 yes, 0 no, 7 unknown" "…readable"
has "$(cat "$T/out")" "effective)" "…the spend with its effective figure"
cls digest --days 0 --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["verdicts"])' > "$T/out"; check "$(cat "$T/out")" "0" "--days 0: an empty window"

echo "ops classify: a gate that cannot classify, a transferred issue, a reopened one (S5's landing review)"
echo lighthouse.urgency > "$T/gate.off"
intake alpha:19:bug:member:s19
python3 -c 'import json,sys; a=json.load(open(sys.argv[1])); a["repos/acme/alpha/issues/19"]=[0, [{"number": 19, "state": "open", "title": "L:2,2,xs,clear", "labels": [{"name": "bug"}], "body": "x"}]]; json.dump(a, open(sys.argv[1], "w"))' "$T/gh.json"
cls classify > "$T/out" 2>&1
check "$? $(verd key | wc -l | tr -d ' ') $(grep -c . "$T/gh.calls") $(grep -c . "$T/gate.calls")" "3 0 0 0" "a row the gate cannot resolve: exit 3, no verdict, nothing fetched or sent"
check "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["pending"]["alpha#19"]["tries"])' "$T/logs/classify-state.json")" "0" "…the issue kept queued, no try spent"
has "$(cat "$T/out")" "the gate cannot classify, 1 held, no try spent: models.json: no row for lighthouse.urgency" "…saying why"
rm -f "$T/gate.off"; cls classify > "$T/out" 2>&1; check "$? $(verd key | tr '\n' ' ')" "0 alpha#19 " "…classified once the row is there"
intake alpha:20:bug:member:s20
python3 -c 'import json,sys; a=json.load(open(sys.argv[1])); a["repos/acme/alpha/issues/20"]=[0, [{"number": 20, "state": "open", "title": "L:2,2,xs,clear", "labels": [], "body": "x", "repository_url": "https://api.github.com/repos/acme/secret"}]]; json.dump(a, open(sys.argv[1], "w"))' "$T/gh.json"
cls classify > "$T/out" 2>&1
check "$(verd key | wc -l | tr -d ' ') $(grep -c . "$T/gate.calls")" "0 0" "an issue GitHub answers from another repo (transferred, gh following the redirect): no verdict, nothing sent"
intake alpha:17:bug:member:s17
python3 -c 'import json,sys; a=json.load(open(sys.argv[1])); a["repos/acme/alpha/issues/17"][1][0]["state"]="open"; json.dump(a, open(sys.argv[1], "w"))' "$T/gh.json"
cls classify > "$T/out" 2>&1
check "$(verd key | tr '\n' ' ')" "alpha#17 " "an issue found closed at its fetch, open again unchanged: classified (a close never marks it done)"
rm -f "$OJ"
unset LIGHTHOUSE_OPS_GH

echo "install.sh --schedule: the job on the ops host only"
# a copy outside any git tree (the core beside it, as in a checkout): install.sh then runs the job from the copy, not from the main checkout, whose ops
# may predate this branch's sample verb (the plist runs the job's ops, so the job's ops answers the host rule)
mkdir -p "$T/modules" && cp -R "$C" "$T/modules/lighthouse" && ln -s "$C/../regatta" "$T/modules/regatta"; IN="$T/modules/lighthouse/install.sh"; LA="$T/LaunchAgents"
printf '#!/bin/sh\necho "$*" >> "%s"\nexit 0\n' "$T/lc.calls" > "$T/launchctl"; chmod +x "$T/launchctl"
sched() { env LIGHTHOUSE_LAUNCH_DIR="$LA" LIGHTHOUSE_LAUNCHCTL="$T/launchctl" LIGHTHOUSE_LABEL=test.ops sh "$IN" "$@"; }
echo other-host > "$REGATTA_CONFIG/lighthouse/ops-host"
LIGHTHOUSE_UNAME=Darwin sched --schedule > "$T/out" 2>&1; check "$?" "1" "a host that is not the ops host: refused"
grep -q "not scheduling the desk's sampler — this host is $HOSTNAME_, not lighthouse/ops-host's other-host" "$T/out"; check "$?" "0" "…saying why"
check "$(test -e "$LA/test.ops.plist" && echo there || echo absent) $(test -e "$T/lc.calls" && echo called || echo untouched)" "absent untouched" "…no plist, launchctl untouched"
rm -f "$REGATTA_CONFIG/lighthouse/ops-host"; LIGHTHOUSE_UNAME=Darwin sched --schedule > "$T/out" 2>&1
check "$? $(test -e "$LA/test.ops.plist" && echo there || echo absent)" "1 absent" "no lighthouse/ops-host: refused too"
echo "$HOSTNAME_" > "$REGATTA_CONFIG/lighthouse/ops-host"
LIGHTHOUSE_UNAME=Darwin sched --schedule > "$T/out" 2>&1; check "$?" "0" "the ops host, a Mac: scheduled"
check "$(python3 -c 'import plistlib,sys; p=plistlib.load(open(sys.argv[1],"rb")); a=p["ProgramArguments"]; print(a[-2].endswith("modules/lighthouse/bin/ops"), a[-1], p["StartInterval"], p["EnvironmentVariables"]["LIGHTHOUSE_DESK"], p["EnvironmentVariables"]["REGATTA_CONFIG"] == sys.argv[2], p["StandardOutPath"].endswith("ops-sample.log"))' "$LA/test.ops.plist" "$REGATTA_CONFIG")" \
  "True sample 900 1 True True" "…the plist: ops sample every 900 s, LIGHTHOUSE_DESK=1, the config dir carried, logged to ops-sample.log"
check "$(grep -c "bootstrap gui/$(id -u) $LA/test.ops.plist" "$T/lc.calls")" "1" "…loaded with launchctl bootstrap"
check "$(python3 -c 'import plistlib,sys; p=plistlib.load(open(sys.argv[1],"rb")); a=p["ProgramArguments"]; print(a[-2].endswith("modules/lighthouse/bin/ops"), a[-1], p["StartInterval"], p["EnvironmentVariables"]["LIGHTHOUSE_DESK"], p["StandardOutPath"].endswith("ops-ingest.log"))' "$LA/test.ops.ingest.plist") $(grep -c "bootstrap gui/$(id -u) $LA/test.ops.ingest.plist" "$T/lc.calls")" \
  "True ingest 600 1 True 1" "the intake beside it (S4): ops ingest every 600 s, LIGHTHOUSE_DESK=1, its own log, loaded"
sched --remove > /dev/null 2>&1; check "$(test -e "$LA/test.ops.plist" && echo there || echo absent) $(test -e "$LA/test.ops.ingest.plist" && echo there || echo absent)" "absent absent" "--remove: both plists gone"
LIGHTHOUSE_UNAME=Linux sched --schedule > "$T/out" 2>&1; check "$? $(test -e "$LA/test.ops.plist" && echo there || echo absent)" "1 absent" "Linux: no LaunchAgent, nothing written (yard-node S5's timer)"
grep -q "ExecStart=.*bin/ops sample" "$T/out" && grep -q "Environment=LIGHTHOUSE_DESK=1" "$T/out"; check "$?" "0" "…the unit's lines printed: the seam"
grep -q "ExecStart=.*bin/ops ingest" "$T/out" && grep -q "OnUnitActiveSec=10min" "$T/out"; check "$?" "0" "…and the intake's unit, every 10 minutes"
check "$(test -e "$LA/test.ops.ingest.plist" && echo there || echo absent)" "absent" "…no intake plist on Linux either"

echo
if [ "$fails" = 0 ]; then echo "ops: all ok"; else echo "ops: $fails FAILED"; exit 1; fi
