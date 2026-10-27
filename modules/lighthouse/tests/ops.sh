#!/usr/bin/env bash
# lighthouse's bin/ops (lighthouse-ops S1): the desk's token wall — read only in the desk's own job,
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

echo
if [ "$fails" = 0 ]; then echo "ops: all ok"; else echo "ops: $fails FAILED"; exit 1; fi
