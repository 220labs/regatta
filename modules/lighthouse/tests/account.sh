#!/usr/bin/env bash
# Tests for bin/account — a scratch HOME with two config dirs, a fixture registry and a stub
# `claude` that answers the get_usage control request and `auth status` from per-dir fixtures and
# logs every probe. No network, no real login touched.
# Every name is made up: labels, hosts, repos. The config dir is a scratch one that plays an
# overlay (its regatta/overlay marker names a checkout holding a worktree_allow.py and a bootstrap.sh
# stub), with the private values the core asks for there; since B14b the core never looks for a tool there.
#   bash modules/lighthouse/tests/account.sh
set -u
B="$(cd "$(dirname "$0")/../bin" && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fails=0
check() { if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3: expected [$2] got [$1]"; fails=$((fails+1)); fi; }
has()   { if grep -qF -- "$2" "$1"; then echo "  ok   $3"; else echo "  FAIL $3: missing [$2]"; sed 's/^/         | /' "$1" | head -20; fails=$((fails+1)); fi; }
hasnt() { if grep -qF -- "$2" "$1"; then echo "  FAIL $3: found [$2]"; sed 's/^/         | /' "$1" | head -20; fails=$((fails+1)); else echo "  ok   $3"; fi; }

# a dispatched or unattended run's environment (CLAUDE_UNATTENDED refuses `refresh --force`): hooks.sh's reset
for v in $(env | sed -n 's/^\(CLAUDE[A-Za-z0-9_]*\)=.*/\1/p; s/^\(DISPATCH[A-Za-z0-9_]*\)=.*/\1/p'); do unset "$v"; done
unset REGATTA_HOME REGATTA_LEGACY
# account reads these (doctor's `blind`, orca-sync's VS Code step): a run over ssh, as dispatch's
# are, would otherwise fail seven cases (B9 review)
unset SSH_CONNECTION SSH_CLIENT SSH_TTY
# Outside claude-host unless a case says otherwise: a dispatched session runs this suite under claude-host,
# a terminal and the CI runner outside it, and the Drive-backed reads differ by it (S4, the core's claude_host())
export REGATTA_CLAUDE_HOST=0
# the stand-in drive: a link under $T is a link into a cloud drive (the core's drive_backed()); a plain file is not
export REGATTA_DRIVE_ROOTS="$T"
export HOME="$T/home" TZ=America/Los_Angeles REGATTA_CONFIG="$T/config"
# the scratch commits' identity: with HOME moved, check.yml's is gone (AGENTS.md, the HOME-move trap)
export GIT_CONFIG_GLOBAL="$T/gitconfig"
git config --global user.name t; git config --global user.email t@t; git config --global init.defaultBranch main
OV="$T/overlay"; mkdir -p "$REGATTA_CONFIG/regatta" "$REGATTA_CONFIG/lighthouse" "$REGATTA_CONFIG/wharf-runs" "$OV/hooks"
echo "$OV" > "$REGATTA_CONFIG/regatta/overlay"; : > "$OV/hooks/worktree_allow.py"; printf '#!/bin/sh
exit 0
' > "$OV/bootstrap.sh"; chmod +x "$OV/bootstrap.sh"
echo Owner > "$REGATTA_CONFIG/regatta/owner"; printf 'cv
privy
' > "$REGATTA_CONFIG/regatta/guarded"
printf 'privy
cv
' > "$REGATTA_CONFIG/regatta/orca-deny"; echo '~/usage' > "$REGATTA_CONFIG/regatta/log-dir"
echo '~/projects' > "$REGATTA_CONFIG/regatta/projects"; echo privy > "$REGATTA_CONFIG/lighthouse/vault"
echo server:server-claude > "$REGATTA_CONFIG/wharf-runs/ssh"
unset CLAUDE_CONFIG_DIR
P1="$HOME/.claude"; S1="$HOME/.claude-spare"
mkdir -p "$P1" "$S1"
# what a plain bootstrap.sh run leaves in ~/.claude: the full memory file and the employer one
# (bin/account links a dir's CLAUDE.md to them, and never to a file that does not exist)
printf '@~/projects/privy/me/core.md\n' > "$P1/CLAUDE.md"; printf '@~/projects/privy/me/core.md\n' > "$P1/CLAUDE-work.md"
export ACCOUNTS_FILE="$T/accounts.json" ACCOUNT_CLAUDE="$T/claude" ACCOUNT_CODE="$T/no-code"   # never the real VS Code
cat > "$ACCOUNTS_FILE" <<'EOF'
{"accounts": [
  {"label": "spare", "provider": "claude", "home": "~/.claude-spare",
   "rules": {"week_max": 70, "window_max": 50, "reserve": {"day": "Saturday", "week_max": 100}}},
  {"label": "main", "provider": "claude", "home": "~/.claude", "primary": true,
   "rules": {"week_max": 95, "window_max": 80}},
  {"label": "oa", "provider": "codex", "home": "~/.codex-oa", "enabled": false,
   "rules": {"week_max": 90, "window_max": 50}}],
 "capabilities": {"codex": ["review"]}}
EOF
# The stub: usage from <dir>/stub-usage.json as "5h week [locked]", where <dir> is
# CLAUDE_CONFIG_DIR or ~/.claude; one line per probe in $T/probes.
cat > "$T/claude" <<'EOF'
#!/bin/sh
dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
if [ "$1" = auth ]; then
  if [ -f "$dir/stub-login" ]; then echo "{\"loggedIn\": true, \"email\": \"$(cat "$dir/stub-login")\", \"subscriptionType\": \"pro\"}"
  else echo '{"loggedIn": false}'; exit 1; fi
  exit 0
fi
cat > /dev/null
echo "$dir" >> "$T_PROBES"
# what get_usage answers when no login reaches the server: success, every figure null (the always-on Mac, 2026-10-18)
[ -f "$dir/stub-nologin" ] && { echo '{"type":"control_response","response":{"subtype":"success","request_id":"u1","response":{"subscription_type":null,"rate_limits_available":false,"rate_limits":null}}}'; exit 0; }
[ -f "$dir/stub-usage" ] || exit 1
set -- $(cat "$dir/stub-usage")
lock=null; [ "${3:-}" = locked ] && lock='"rate_limited"'
echo '{"type":"system","subtype":"init"}'
lim=''
[ -f "$dir/stub-fable" ] && lim=',"limits":[{"kind":"weekly_all","scope":null},{"kind":"weekly_scoped","percent":37,"resets_at":"2026-10-10T20:00:00+00:00","scope":{"model":{"id":null,"display_name":"Fable"}}}]'
[ -f "$dir/stub-nofable" ] && lim=',"limits":[{"kind":"session","scope":null},{"kind":"weekly_all","scope":null}]'
# paid overage on, in the get_usage answer's shape (probed 2026-10-24: rate_limits.extra_usage)
[ -f "$dir/stub-overage" ] && lim="$lim"',"extra_usage":{"is_enabled":true,"monthly_limit":4000,"used_credits":120,"utilization":3,"currency":"USD","user_disabled":false,"spend_limit_reached":false}'
# on for the org, switched off by the user: it cannot bill (the /usage cache's field; the finish review)
[ -f "$dir/stub-overage-off" ] && lim="$lim"',"extra_usage":{"is_enabled":true,"user_disabled":true}'
echo "{\"type\":\"control_response\",\"response\":{\"subtype\":\"success\",\"request_id\":\"u1\",\"response\":{\"subscription_type\":\"pro\",\"rate_limits\":{\"five_hour\":{\"utilization\":$1,\"resets_at\":\"2026-10-07T22:00:00+00:00\",\"locked_reason\":$lock},\"seven_day\":{\"utilization\":$2,\"resets_at\":\"2026-10-10T20:00:00+00:00\",\"locked_reason\":null}$lim}}}}"
EOF
chmod +x "$T/claude"
export T_PROBES="$T/probes"
at() { python3 -c "import datetime as d,zoneinfo as z;print(d.datetime($1,tzinfo=z.ZoneInfo('America/Los_Angeles')).timestamp())"; }
WED=$(at 2026,10,7,12); SAT=$(at 2026,10,10,10); THU=$(at 2026,10,8,12)
A() { python3 "$B/account" "$@" > "$T/out" 2>&1; echo $?; }
reset() { rm -f "$P1/usage-probe.json" "$S1/usage-probe.json" "$P1/exhaustion.jsonl" "$S1/exhaustion.jsonl" "$T/probes"; }
use() { echo "$2" > "$1/stub-usage"; }
field() { python3 -c "import json,sys;d=json.load(open('$T/out'));print(d$1)"; }

echo "pick — the walk (design section 2c, D2)"
reset; use "$S1" "10 40"; use "$P1" "10 10"
check "$(ACCOUNT_NOW=$WED A pick --json)" 0 "a secondary with room"
check "$(field "['account']") $(field "['env']['CLAUDE_CONFIG_DIR']")" "spare $S1" "…is picked first, with its config dir as the env"
check "$(wc -l < "$T/probes" | tr -d ' ')" 1 "…and the primary is never probed (stops at the first that qualifies)"
check "$(ACCOUNT_NOW=$WED A pick --json; wc -l < "$T/probes" | tr -d ' ')" "0
1" "a second pick within 60 s probes nothing (R4)"
reset; use "$S1" "10 75"
check "$(ACCOUNT_NOW=$WED A pick --json) $(field "['account']") $(field "['env']")" "0 main {}" "75% of the week on a Wednesday → the primary, with an empty env"
has "$T/out" "week 75% ≥ 70% (week ceiling)" "…naming why the secondary was skipped"
reset; use "$S1" "10 75"
check "$(ACCOUNT_NOW=$SAT A pick --json) $(field "['account']")" "0 spare" "75% on a Saturday → the secondary (its reserve day)"
has "$T/out" "Saturday reserve" "…and says so"
reset; use "$S1" "60 10"; use "$P1" "10 10"
check "$(ACCOUNT_NOW=$WED A pick --json) $(field "['account']")" "0 main" "a 5-hour window over 50% → the primary"
reset; use "$S1" "10 10"
check "$(ACCOUNT_NOW=$WED A pick --bound --json) $(field "['account']")" "0 main" "--bound (account-bound work) → the primary, even with room elsewhere"

echo "exhaustion — cooldown and margin (D6)"
reset; use "$S1" "10 10"; use "$P1" "10 10"
mkdir -p "$S1"; echo "{\"at\": $WED, \"window\": \"five_hour\", \"resets_at\": $(python3 -c "print($WED + 3600)")}" > "$S1/exhaustion.jsonl"
check "$(ACCOUNT_NOW=$WED A pick --json) $(field "['account']")" "0 main" "a locked window → skipped until it resets"
has "$T/out" "cooling down until" "…with the reason"
check "$(grep -c "$S1" "$T/probes")" 0 "…and never probed"
rm -f "$T/probes"; use "$S1" "45 10"
check "$(ACCOUNT_NOW=$(python3 -c "print($WED + 7200)") A pick --json) $(field "['account']")" "0 main" "after the reset, 45% is over 50 − 10 points of margin"
has "$T/out" "10 points of margin after an exhaustion" "…and the margin is named"
check "$(ACCOUNT_NOW=$(python3 -c "print($WED + 8 * 86400)") A pick --json) $(field "['account']")" "0 spare" "a week later the margin is gone"
reset; use "$S1" "100 20 locked"; use "$P1" "10 10"
check "$(ACCOUNT_NOW=$WED A pick --json) $(field "['account']")" "0 main" "a probe reading a locked window → the primary"
check "$(python3 -c "import json;print(json.loads(open('$S1/exhaustion.jsonl').readline())['window'])")" "five_hour" "…and the probe wrote the exhaustion record (R11)"
reset
check "$(CLAUDE_CONFIG_DIR="$S1" ACCOUNT_NOW=$WED A exhausted --window seven_day --resets-at 1791000000 --session s1 --used 100)" 0 "exhausted (the statusline's call)"
CLAUDE_CONFIG_DIR="$S1" ACCOUNT_NOW=$WED python3 "$B/account" exhausted --window seven_day --resets-at 1791000000 --session s1
check "$(wc -l < "$S1/exhaustion.jsonl" | tr -d ' ')" 1 "…written once per session and window, into that dir's log"

reset
CLAUDE_CONFIG_DIR="$S1" python3 "$B/account" exhausted --window five_hour --resets-at 1791000000 --session s2
use "$S1" "100 20 locked"
sed -i.bak 's/2026-10-07T22:00:00+00:00/2026-10-07T22:00:00.202144+00:00/' "$T/claude" && rm -f "$T/claude.bak"  # -i.bak: GNU and BSD alike
CLAUDE_CONFIG_DIR="$S1" python3 "$B/account" exhausted --window five_hour --resets-at "$(python3 -c 'import datetime as d;print(int(d.datetime(2026,10,7,22,tzinfo=d.timezone.utc).timestamp()))')" --session s3
ACCOUNT_NOW=$WED python3 "$B/account" limits spare > /dev/null
rm -f "$S1/usage-probe.json"; ACCOUNT_NOW=$(python3 -c "print($WED + 120)") python3 "$B/account" limits spare > /dev/null
check "$(grep -c five_hour "$S1/exhaustion.jsonl")" 2 "one lock read by the status line and twice by probes is one record (microseconds and seconds agree)"
sed -i.bak 's/2026-10-07T22:00:00.202144+00:00/2026-10-07T22:00:00+00:00/' "$T/claude" && rm -f "$T/claude.bak"
reset; use "$S1" "25 10"; use "$P1" "10 10"
for i in 1 2 3 4; do echo "{\"at\": $WED, \"window\": \"five_hour\", \"resets_at\": $(python3 -c "print($WED - $i * 3600)")}" >> "$S1/exhaustion.jsonl"; done
check "$(ACCOUNT_NOW=$WED A pick --json) $(field "['account']")" "0 main" "four exhaustions in a week: margin capped at 30 points"
has "$T/out" "5h 25% > 20%, 30 points of margin" "…50 − 30, not 50 − 40"
reset; use "$S1" "80 10"; rm -f "$P1/stub-usage"
check "$(ACCOUNT_NOW=$WED A pick --json) $(field "['account']")" "0 main" "the primary's probe fails → the primary runs it rather than nothing"
has "$T/out" "limits unknown — the primary runs it rather than nothing" "…and says so"
check "$(ACCOUNT_NOW=$WED A pick --cached --json) $(field "['account']")" "0 main" "…the same with --cached, so a dry run agrees with the real one"
reset; use "$S1" "80 10"; use "$P1" "10 98"
check "$(ACCOUNT_NOW=$WED A limits main)" 0 "a probe of the primary at 98% of its week"
rm "$P1/stub-usage"
check "$(ACCOUNT_NOW=$(python3 -c "print($WED + 600)") A pick --json)" 3 "…then a failed probe uses that stale reading: refused, not guessed"
has "$T/out" "week 98% ≥ 95% (week ceiling)" "…naming the stale figure"

echo "the end of the walk"
reset; use "$S1" "10 80"; use "$P1" "10 96"
check "$(ACCOUNT_NOW=$WED A pick)" 3 "every account short → exit 3, nothing picked"
has "$T/out" "main: week 96% ≥ 95%" "…each row's reason and reset"
check "$(ACCOUNT_NOW=$WED A pick --provider codex)" 3 "provider codex with no enabled Codex row → exit 3"
has "$T/out" "no enabled codex account" "…naming it"
check "$(ACCOUNT_NOW=$WED A pick --kind review)" 3 "a kind listed under capabilities.codex routes to Codex (D7)"
check "$(A limits oa)" 1 "limits of a disabled row: refused, not an empty list"
has "$T/out" "oa is disabled" "…naming it"
reset; use "$S1" "10 10"; use "$P1" "10 10"; mv "$S1" "$T/gone"
check "$(ACCOUNT_NOW=$WED A pick --json) $(field "['account']")" "0 main" "a row not set up on this machine (the always-on Mac) → skipped"
check "$(cat "$T/probes" 2>/dev/null | grep -c gone)" 0 "…without a probe"
mv "$T/gone" "$S1"
check "$(ACCOUNTS_FILE="$T/none.json" A pick)" 4 "no registry → exit 4 (callers start as before)"
python3 - "$ACCOUNTS_FILE" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p))
d["accounts"][0]["rules"]["reserve"] = {"last_hours": 24, "week_max": 100}
json.dump(d, open(p + ".last", "w"))
PY
reset; use "$S1" "10 80"
check "$(ACCOUNTS_FILE="$ACCOUNTS_FILE.last" ACCOUNT_NOW=$(python3 -c "print($SAT)") A pick --json) $(field "['account']")" "0 spare" "reserve.last_hours: inside the last 24 h before the reset → 100%"
reset; use "$S1" "10 80"; use "$P1" "10 10"
check "$(ACCOUNTS_FILE="$ACCOUNTS_FILE.last" ACCOUNT_NOW=$THU A pick --json) $(field "['account']")" "0 main" "…and not before"

echo "paid overage — judge refuses a row whose extra usage is on (costs S8)"
reset; use "$S1" "10 10"; use "$P1" "10 10"; touch "$S1/stub-overage"
check "$(ACCOUNT_NOW=$WED A pick --json) $(field "['account']")" "0 main" "the first row's extra usage on → skipped, the primary picks it"
check "$(field "['skipped']")" "[['spare', 'extra usage on: work here may bill past the plan (account pick --allow-overage, attended only)']]" "…and the skip says why"
check "$(python3 -c "import json;print(json.load(open('$S1/usage-probe.json'))['limits']['extra_usage'])")" \
  "{'enabled': True, 'user_disabled': False, 'spend_limit_reached': False, 'used_credits': 120, 'monthly_limit': 4000, 'utilization': 3}" \
  "the probe's cache carries extra_usage, in the core's parse"
check "$(python3 -c "import json;print(json.load(open('$P1/usage-probe.json'))['limits']['extra_usage'])")" \
  "None" "…an answer without the field caches None (no reading), never a refusal"
check "$(ACCOUNT_NOW=$WED env -u CLAUDE_UNATTENDED python3 "$B/account" pick --allow-overage --json > "$T/out" 2>&1; echo $?) $(field "['account']")" "0 spare" \
  "--allow-overage, attended: the first row runs it after all"
check "$(ACCOUNT_NOW=$WED CLAUDE_UNATTENDED=dispatch python3 "$B/account" pick --allow-overage --json > "$T/out" 2>&1; echo $?)" "2" \
  "--allow-overage from an unattended caller: refused, exit 2"
has "$T/out" "may not pass it" "…said on stderr"
# a later row: pick returns at the first eligible one, so a refusal there is only seen once the rows
# before it are refused (AGENTS.md's \`account pick\` trap)
rm -f "$S1/stub-overage"; touch "$P1/stub-overage"; reset; use "$S1" "10 90"; use "$P1" "10 10"
check "$(ACCOUNT_NOW=$WED A pick --json)" "3" "the first row full, the later primary's extra usage on → nobody runs it (exit 3)"
check "$(field "['skipped'][1]")" "['main', 'extra usage on: work here may bill past the plan (account pick --allow-overage, attended only)']" \
  "…the primary refused for overage, never taken as 'limits unknown'"
check "$(ACCOUNT_NOW=$WED A limits --all --cached --json; field "[1]['eligible']"; field "[1]['why']")" "0
False
extra usage on: work here may bill past the plan (account pick --allow-overage, attended only)" \
  "limits --all --json: the later row's own verdict says overage"
check "$(ACCOUNT_NOW=$WED A limits --all --cached --json; field "[1]['overage']"; field "[0]['overage']")" "0
True
False" "…and its overage flag, which dispatch's --force reads"
check "$(ACCOUNT_NOW=$WED A pick --bound --json)" "3" "--bound: the primary with overage on is refused too"
check "$(ACCOUNT_NOW=$WED env -u CLAUDE_UNATTENDED python3 "$B/account" pick --bound --allow-overage --json > "$T/out" 2>&1; echo $?) $(field "['account']")" "0 main" \
  "…unless a person passes --allow-overage"
rm -f "$P1/stub-overage"; reset
touch "$S1/stub-overage-off"; reset; use "$S1" "10 10"; use "$P1" "10 10"
check "$(ACCOUNT_NOW=$WED A pick --json) $(field "['account']")" "0 spare" "extra usage on but switched off by the user: it cannot bill, the row runs it"
rm -f "$S1/stub-overage-off"; reset

echo "env, limits, check"
check "$(python3 "$B/account" env spare)" "CLAUDE_CONFIG_DIR=$S1" "env of a secondary"
check "$(python3 "$B/account" env main | wc -c | tr -d ' ')" 0 "env of the default dir is empty — CLAUDE_CONFIG_DIR=~/.claude would log it out"
check "$(env -u CLAUDE_CONFIG_DIR python3 "$B/account" which; echo "rc=$?")" "rc=1" "which on the default dir: no label, so dispatch --next stays auto (review 2026-10-06)"
reset; use "$S1" "12 41"
check "$(A limits spare)" 0 "limits"
has "$T/out" "spare: 5h 12% (resets" "…prints the windows"
has "$T/out" "plan pro" "…and the plan the probe reports (R5)"
check "$(A limits --all --cached --json; field "[1]['limits']")" "0
None" "--cached never probes: the primary has no cache"
for n in projects sessions skills plugins agents rules; do ln -s "$P1/$n" "$S1/$n"; done
echo t@example.com > "$S1/stub-login"
check "$(A check)" 1 "check: a logged-out row is a problem"
has "$T/out" "spare: t@example.com (pro)" "…the logged-in row names its login"
has "$T/out" "main (primary): NOT logged in" "…the other says so, with the command"
echo p@example.com > "$P1/stub-login"; rm "$S1/sessions"; mkdir "$S1/sessions"
check "$(A check)" 1 "check: a shared link that became a real directory (R2)"
has "$T/out" "links: sessions is a real directory" "…is named"

echo "two dirs on one login (2026-10-05: spare signed in as the primary's account)"
login() { echo "{\"oauthAccount\": {\"accountUuid\": \"$2\", \"emailAddress\": \"$3\"}}" > "$1"; }
login "$HOME/.claude.json" u-primary p@example.com; login "$S1/.claude.json" u-primary p@example.com
echo p@example.com > "$S1/stub-login"; ln -s "$P1/CLAUDE.md" "$S1/CLAUDE.md"
reset; use "$S1" "10 10"; use "$P1" "10 10"
check "$(ACCOUNT_NOW=$WED A pick --json) $(field "['account']")" "0 main" "a secondary on the primary's login → the primary, never the duplicate"
check "$(grep -c "$S1" "$T/probes")" 0 "…without probing it"
check "$(ACCOUNT_NOW=$WED A limits --all --cached --json; field "[0]['eligible']")" "0
False" "limits: the duplicate is not eligible"
has "$T/out" "same login as main (p@example.com)" "…and says whose login it carries"
rm -rf "$S1/sessions"; ln -s "$P1/sessions" "$S1/sessions"
check "$(A check)" 1 "check: a duplicate login is a problem"
has "$T/out" "⚠   spare" "…marked ⚠"
has "$T/out" "auth login" "…with the re-login line"
login "$S1/.claude.json" u-second t@example.com; echo t@example.com > "$S1/stub-login"
reset; use "$S1" "10 10"; use "$P1" "10 10"
check "$(ACCOUNT_NOW=$WED A pick --json) $(field "['account']")" "0 spare" "its own login again → picked as before"
check "$(A check)" 0 "check: clean once it has its own login"
python3 - "$ACCOUNTS_FILE" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p))
d["accounts"].insert(0, {"label": "old", "provider": "claude", "home": "~/.claude-old", "enabled": False})
json.dump(d, open(p + ".old", "w"))
PY
mkdir -p "$HOME/.claude-old"; login "$HOME/.claude-old/.claude.json" u-second t@example.com
check "$(ACCOUNTS_FILE="$ACCOUNTS_FILE.old" ACCOUNT_NOW=$WED A pick --json) $(field "['account']")" "0 spare" "a disabled row on the same login claims nothing"
check "$(ACCOUNTS_FILE="$ACCOUNTS_FILE.old" A limits --all --parked --cached --json; python3 -c "import json;print(dict((r['label'], r['same_as']) for r in json.load(open('$T/out')) if r['label'] in ('old', 'spare')))")" "0
{'old': 'spare', 'spare': None}" "limits --all --parked: the parked row is the duplicate, never the enabled one (one week, one card)"
echo '[]' > "$S1/.claude.json"
check "$(ACCOUNT_NOW=$WED A pick --json) $(field "['account']")" "0 spare" "an unreadable .claude.json marks nothing and crashes nothing"

echo "setup — a Mac built from the logins file (work-account E1)"
export ACCOUNT_LOGINS="$T/logins.json" ACCOUNT_HOST=laptop
cat > "$ACCOUNTS_FILE.f" <<'J'
{"accounts": [
  {"label": "work", "provider": "claude", "home": "~/.claude-work", "enabled": false,
   "rules": {"week_max": 90, "window_max": 80}, "repos": {"deny": ["privy", "cv"]}},
  {"label": "spare", "provider": "claude", "home": "~/.claude-spare", "enabled": false},
  {"label": "main", "provider": "claude", "home": "~/.claude", "primary": true}]}
J
cat > "$ACCOUNT_LOGINS" <<'J'
{"logins": {"main": {"email": "p@example.com", "plan": "max", "macs": ["laptop", "server"]},
            "work": {"email": null, "paid_by": "employer", "macs": ["laptop", "server"]},
            "spare": {"email": "t@example.com", "macs": [], "note": "parked"}},
 "share": {"design": [{"email": "z@example.com", "access": "edit"}]}}
J
F="$HOME/.claude-work"
login "$HOME/.claude.json" u-primary p@example.com
SA() { ACCOUNTS_FILE="$ACCOUNTS_FILE.f" A setup "$@"; }
check "$(SA)" 1 "setup: a dir the file lists for this Mac and no login → exit 1"
check "$([ -L "$F/projects" ] && [ -L "$F/CLAUDE.md" ] && echo linked)" linked "…the missing dir is made with its links (add --no-login)"
has "$T/out" "work: not signed in on laptop" "…and the login it owes is named"
has "$T/out" "CLAUDE_CONFIG_DIR=$F claude auth login" "…with the line to run"
has "$T/out" "spare: not listed for laptop (parked)" "a parked row (macs: []) is left alone"
has "$T/out" "ok  main: p@example.com (max)" "the primary agrees with the file"
login "$F/.claude.json" u-f f@example.com; echo f@example.com > "$F/stub-login"
check "$(SA --no-record)" 0 "--no-record (the always-on Mac's leg): a login the file lacks is not written"
check "$(python3 -c "import json;print(json.load(open('$ACCOUNT_LOGINS'))['logins']['work']['email'])")" None "…the file is untouched"
check "$(SA)" 0 "a login the file lacks → recorded"
check "$(python3 -c "import json;e=json.load(open('$ACCOUNT_LOGINS'))['logins']['work'];print(e['email'], e['plan'], e['paid_by'])")" "f@example.com pro employer" "…e-mail and plan read back, the rest kept"
check "$(python3 -c "import json;print(json.load(open('$ACCOUNT_LOGINS'))['share']['design'][0]['email'])")" "z@example.com" "…and the file's other keys (share, hooks/design_route.py) kept"
check "$(SA)" 0 "a second run changes nothing"
check "$(grep -c '^  ok  ' "$T/out")" 2 "…and prints ok per row it builds"
check "$(ACCOUNTS_FILE="$ACCOUNTS_FILE.f" A limits --all --cached --json; python3 -c "import json;print([r['label'] for r in json.load(open('$T/out'))])")" "0
['main']" "limits --all: a parked row is not listed (the walk, the tier check)"
check "$(ACCOUNTS_FILE="$ACCOUNTS_FILE.f" A limits --all --parked --cached --json; python3 -c "import json;print([(r['label'], r['enabled'], r['eligible'], r['why']) for r in json.load(open('$T/out'))])")" \
  "0
[('work', False, False, 'parked (enabled: false in accounts.json.f); limits unknown (no probe answered, none cached)'), ('spare', False, False, 'parked (enabled: false in accounts.json.f); week 0% < 100% (week ceiling), 5h 0% ≤ 100%'), ('main', True, False, 'limits unknown (no probe answered, none cached)')]" "limits --all --parked: the parked rows too, never eligible, judge's own reason kept (the widget draws them as off)"
login "$F/.claude.json" u-other x@example.com
check "$(SA)" 1 "a dir signed in as another account than the file says → exit 1"
has "$T/out" "signed in as x@example.com on laptop, the logins file says f@example.com" "…naming both"
check "$(SA --peer server-claude)" 1 "the peer's form of the line"
has "$T/out" "ssh -t server-claude 'CLAUDE_CONFIG_DIR=$F $T/claude auth login'" "…is ssh -t with the binary spelled out"
check "$(ACCOUNT_SSH=false ACCOUNTS_FILE="$ACCOUNTS_FILE.f" A setup --host server)" 1 "setup --host: an unreachable peer is one line"
mkdir -p "$HOME/projects/overlay"; ln -sfn "$B" "$HOME/projects/overlay/bin"; ln -sfn "$B/../hooks" "$HOME/projects/overlay/hooks"
check "$(ACCOUNT_SSH="sh -c" ACCOUNTS_FILE="$ACCOUNTS_FILE.f" A setup --host server)" 1 "setup --host runs on the peer (a stub ssh: sh -c) and passes its exit"
has "$T/out" "ssh -t server-claude" "…its lines in the ssh -t form"
check "$(ACCOUNT_LOGINS="$T/none.json" ACCOUNTS_FILE="$ACCOUNTS_FILE.f" A setup)" 1 "no logins file → says so, exit 1"

echo "the deny list and Fable (work-account E2)"
PR="$HOME/projects"; mkdir -p "$PR/cv" "$PR/studio"
for r in privy overlay app app2 studio/pipeline; do git init -q "$PR/$r"; git -C "$PR/$r" commit -q --allow-empty -m init; done
git -C "$PR/privy" worktree add -q "$PR/privy/.claude/worktrees/x" -b x 2>/dev/null
mkdir -p "$PR/privy/memory"
python3 - "$ACCOUNTS_FILE.f" <<'PY2'
import json, sys
p = sys.argv[1]; d = json.load(open(p))
d["accounts"][0]["enabled"] = True
json.dump(d, open(p + ".on", "w"))
PY2
DA() { ACCOUNTS_FILE="$ACCOUNTS_FILE.f.on" ACCOUNT_NOW=$WED A "$@"; }
login "$F/.claude.json" u-f f@example.com
rm -f "$F/usage-probe.json" "$P1/usage-probe.json" "$T/probes"; use "$F" "10 10"; use "$P1" "10 10"
for r in overlay app app2 studio/pipeline; do
  check "$(DA pick --repo "$PR/$r" --json) $(field "['account']")" "0 work" "pick --repo $r → work (not on the deny list)"
done
check "$(DA pick --repo "$PR/privy" --json) $(field "['account']")" "0 main" "pick --repo privy → main"
has "$T/out" "privy is on its deny list" "…naming why work was skipped"
check "$(DA pick --repo "$PR/privy/memory" --json) $(field "['account']")" "0 main" "…a folder inside it too"
check "$(DA pick --repo "$PR/privy/.claude/worktrees/x" --json) $(field "['account']")" "0 main" "…a worktree of it (git-common-dir)"
check "$(DA pick --repo "$PR/cv" --json) $(field "['account']")" "0 main" "cv, a folder in no git repo → main (by path)"
check "$(DA pick --repo "$PR" --json) $(field "['account']")" "0 work" "~/projects itself is no repo → allowed (fails open, by design)"
check "$(DA pick --json) $(field "['account']")" "0 work" "no --repo → the walk as before"
# --repo takes a registry key as well as a path (found 2026-10-24: a key read as a path in the cwd matched no deny list)
check "$(DA pick --repo privy --json) $(field "['account']")" "0 main" "pick --repo <key>: the key's deny list binds, as the path's does"
has "$T/out" "privy is on its deny list" "…naming why work was skipped"
check "$(cd "$T" && DA pick --repo privy --json) $(field "['account']")" "0 main" "…from any cwd (the key is no path in it)"
check "$(DA pick --repo cv --json) $(field "['account']")" "0 main" "…a key that is a folder in no git repo"
check "$(DA pick --repo studio/pipeline --json) $(field "['account']")" "0 work" "…a nested key, not on the list → work"
check "$(DA pick --repo privy/ --json) $(field "['account']")" "0 main" "…a trailing slash"
check "$(DA pick --repo nosuchrepo --json) $(field "['account']")" "3 None" "an unknown key → refused (exit 3, the callers' stop), never picked as if no rule applied"
has "$T/out" "no repo key or path of that name" "…saying so, in the JSON alone (weekly-run reads stderr merged in)"
check "$(DA pick --repo "" --json)" 3 "an empty --repo → refused"
printf '{"repos": {"ghost": {}}}\n' > "$T/ghost.json"
check "$(CLAUDE_REPOS_JSON="$T/ghost.json" DA pick --repo ghost --json) $(field "['account']")" "0 work" "a key repos.json lists whose clone is absent here → known (allowed, no rule names it)"
check "$(DA limits --all --cached --repo privy --json; field "[0]['eligible']")" "0
False" "limits --repo <key>: work not eligible"
check "$(DA limits --all --cached --repo nosuchrepo --json)" 3 "limits --repo, an unknown key → refused"
# a scope's login (repos.json, knowledge-layers D3): its repos' runs start on that row alone
printf '{"repos": {"app": {}, "app2": {}, "privy": {}},\n "scopes": {"node": {"file": "n.code-workspace", "repos": ["app2"], "confidential": true, "login": "main"},\n  "lab": {"file": "l.code-workspace", "repos": ["app", "privy"]}}}\n' > "$T/scoped.json"
SDA() { CLAUDE_REPOS_JSON="$T/scoped.json" DA "$@"; }
check "$(SDA pick --repo "$PR/app2" --json) $(field "['account']")" "0 main" "pick --repo app2, in a scope whose login is main → main, though work is first and allowed"
has "$T/out" "scope node runs on main" "…naming why work was skipped"
check "$(SDA pick --repo "$PR/app" --json) $(field "['account']")" "0 work" "…a repo in a scope with no login → the walk as before"
check "$(sed 's/"login": "main"/"login": "nobody"/' "$T/scoped.json" > "$T/scoped2.json"; CLAUDE_REPOS_JSON="$T/scoped2.json" DA pick --repo "$PR/app2" --json)" 3 \
  "…a login no enabled row has → exit 3, never another seat"
has "$T/out" "scope node runs on nobody, which is no enabled claude account" "…saying so"
check "$(SDA limits work --cached --repo "$PR/app2" --json; field "[0]['eligible']"; field "[0]['denied']")" "0
False
scope node" "limits --repo app2 on another row: not eligible, and denied (dispatch's --force never crosses it)"
printf '{"repos": {"cv": {}}, "scopes": {"cvs": {"file": "c.code-workspace", "repos": ["cv"], "login": "main"}}}\n' > "$T/scoped4.json"
mkdir -p "$PR/cv/sub"
check "$(CLAUDE_REPOS_JSON="$T/scoped4.json" DA pick --repo "$PR/cv/sub" --json) $(field "['account']")" "0 main" \
  "…a scope member that is a folder in no git repo: its path finds the login"
head -c 50 "$T/scoped.json" > "$T/torn.json"
check "$(CLAUDE_REPOS_JSON="$T/torn.json" DA pick --repo "$PR/app" --json)" 3 "…a registry that does not read: every pick waits (exit 3)"
has "$T/out" "the registry does not read" "…saying so"
check "$(DA limits --all --cached --repo "$PR/privy" --json; field "[0]['eligible']")" "0
False" "limits --repo privy: work not eligible"
check "$(CLAUDE_CONFIG_DIR="$F" DA allowed "$PR/privy")" 1 "allowed: privy under work's dir → exit 1"
has "$T/out" "privy is off work (accounts.json deny list)" "…with the line the guard prints"
check "$(CLAUDE_CONFIG_DIR="$F" DA allowed "$PR/app2")" 0 "allowed: app2 → exit 0"
check "$(CLAUDE_CONFIG_DIR="$F" DA allowed "$PR")" 1 "allowed: ~/projects, which holds privy, is off work (its ~/.claude/CLAUDE.md imports would load there, 2026-10-18)"
has "$T/out" "is off work: it holds privy" "…with the guard's ' is off ' line"
check "$(CLAUDE_CONFIG_DIR="$F" DA allowed "$HOME")" 1 "…and ~ too"
check "$(DA allowed "$PR")" 0 "…while the default dir may start there, as before"
check "$(DA allowed "$PR/privy")" 0 "allowed: the default dir denies nothing"
UO="$T/unsynced-orca"; mkdir -p "$UO/claude-profiles/p1/home"
UA() { CLAUDE_CONFIG_DIR="$UO/claude-profiles/p1/home" ACCOUNT_ORCA_DATA="$UO" ACCOUNT_ORCA_FILE="$T/no-orca.json" DA "$@"; }
check "$(UA allowed "$PR/privy")" 1 "allowed: an Orca login orca-sync has not recorded is refused privy, by ORCA_ROW's list (2026-10-17)"
has "$T/out" "privy is off this Orca login, which no row names yet" "…with a line the guard reads (' is off ')"
check "$(UA allowed "$PR/app")" 0 "…and allowed in any other repo"
check "$(CLAUDE_CONFIG_DIR="$T/elsewhere" DA allowed "$PR/privy")" 0 "allowed: a dir no row names outside Orca's profiles fails open, as before"
mkdir -p "$UO/claude-profiles/p4/home" "$UO/claude-profiles/pi/home"
login "$UO/claude-profiles/p4/home/.claude.json" u-primary p@example.com
login "$UO/claude-profiles/pi/home/.claude.json" u-f f@example.com
UB() { CLAUDE_CONFIG_DIR="$UO/claude-profiles/$1/home" ACCOUNT_ORCA_DATA="$UO" ACCOUNT_ORCA_FILE="$T/no-orca.json" ACCOUNT_LOGINS="$T/no-logins.json" DA "${@:2}"; }
check "$(UB p4 allowed "$PR/privy")" 0 "allowed: an Orca dir signed in as main's own login is main's, so privy is open (orca-sync never records it)"
check "$(UB pi allowed "$PR/privy")" 1 "allowed: an Orca dir signed in as work's login gets work's deny list"
has "$T/out" "privy is off work, whose login this Orca dir is" "…named as work's"
mkdir -p "$UO/claude-profiles/pz/home" "$UO/claude-profiles/pu/home"
login "$UO/claude-profiles/pz/home/.claude.json" u-z z@example.com
login "$UO/claude-profiles/pu/home/.claude.json" u-u nobody@example.com
echo '{"logins": {"work": {"email": "Z@example.com"}}}' > "$T/logins-z.json"
check "$(ACCOUNT_LOGINS="$T/logins-z.json" CLAUDE_CONFIG_DIR="$UO/claude-profiles/pz/home" ACCOUNT_ORCA_DATA="$UO" ACCOUNT_ORCA_FILE="$T/no-orca.json" DA allowed "$PR/privy")" 1 \
  "allowed: an Orca dir signed in as an e-mail only the logins file gives a row (work) gets that row's list"
check "$(UB pu allowed "$PR/privy")" 1 "allowed: an Orca dir signed in as an e-mail no row owns gets ORCA_ROW's list"
has "$T/out" "privy is off this Orca login, which no row names yet" "…said as ORCA_ROW's"
echo '{not json' > "$T/logins-bad.json"
check "$(ACCOUNT_LOGINS="$T/logins-bad.json" CLAUDE_CONFIG_DIR="$UO/claude-profiles/p4/home" ACCOUNT_ORCA_DATA="$UO" ACCOUNT_ORCA_FILE="$T/no-orca.json" DA allowed "$PR/privy")" 0 \
  "allowed: an unreadable logins file is no traceback; main's own login still answers"
echo "allowed: the logins file read from its local copy outside claude-host (S4)"
mkdir -p "$T/ldrive"; echo '{"logins": {"work": {"email": "Z@example.com"}}}' > "$T/ldrive/logins.json"; ln -s "$T/ldrive/logins.json" "$T/logins-link.json"
LZ() { ACCOUNT_LOGINS="$T/logins-link.json" CLAUDE_CONFIG_DIR="$UO/claude-profiles/pz/home" ACCOUNT_ORCA_DATA="$UO" ACCOUNT_ORCA_FILE="$T/no-orca.json" DA allowed "$PR/privy"; }
check "$(LZ)" 1 "no copy yet: the link is read once, to seed it (work's list)"
check "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["logins"]["work"]["email"])' "$T/.logins-link.json.last" 2>&1)" "Z@example.com" "…and the copy is written beside the link"
echo '{"logins": {"main": {"email": "Z@example.com"}}}' > "$T/ldrive/logins.json"
check "$(LZ)" 1 "the drive's file changed: outside claude-host the copy answers, the link unopened (still work's)"
check "$(REGATTA_CLAUDE_HOST=1 LZ)" 0 "under claude-host the link is read: main's login now, privy open"
check "$(python3 -c 'import json,sys; print(sorted(json.load(open(sys.argv[1]))["logins"]))' "$T/.logins-link.json.last")" "['main']" "…and that read refreshes the copy"
check "$(LZ)" 0 "outside claude-host again: the refreshed copy answers"
mem=$(python3 - "$B/account" "$T/mem" <<'PY'
import os, sys
from importlib.machinery import SourceFileLoader
from pathlib import Path
m = SourceFileLoader("acct_mem", sys.argv[1]).load_module()
base = Path(sys.argv[2]); base.mkdir(parents=True, exist_ok=True)
emp = {"label": "x", "provider": "claude", "repos": {"deny": ["privy"]}}
mine = {"label": "y", "provider": "claude"}
work, full = str(m.DEFAULT_DIR / m.WORK_MEMORY), str(m.DEFAULT_DIR / "CLAUDE.md")
z = base / "z"; z.mkdir()   # the work file missing: never a link to nothing
held = Path(work).read_text() if Path(work).exists() else None
if held is not None:
    Path(work).unlink()
miss = m.point_memory(emp, z)
nolink = not (z / "CLAUDE.md").is_symlink()
if held is not None:
    Path(work).write_text(held)
m.DEFAULT_DIR.mkdir(parents=True, exist_ok=True)
for f in (work, full):
    if not Path(f).exists():
        Path(f).write_text("x\n")
out = [str(m.link_target(emp, "CLAUDE.md")) == work, str(m.link_target(mine, "CLAUDE.md")) == full,
       str(m.link_target(emp, "rules")) == str(m.DEFAULT_DIR / "rules")]
a = base / "a"; a.mkdir(); (a / "CLAUDE.md").write_text(m.ORCA_MEMORY_STUB)
m.point_memory(emp, a); out.append(os.readlink(a / "CLAUDE.md") == work)
b = base / "b"; b.mkdir(); (b / "CLAUDE.md").symlink_to(full)
m.point_memory(emp, b); out.append(os.readlink(b / "CLAUDE.md") == work)
c = base / "c"; c.mkdir(); (c / "CLAUDE.md").write_text("mine\n")
line = m.point_memory(emp, c); out.append((c / "CLAUDE.md").read_text() == "mine\n" and "left" in line)
d = base / "d"; d.mkdir(); m.point_memory(mine, d); out.append(os.readlink(d / "CLAUDE.md") == full)
out.append(m.point_memory(mine, d) is None)
out.append("does not exist" in miss and nolink)
e = base / "e"; e.mkdir(); (e / "CLAUDE.md").symlink_to(work)
for n in m.LINKS:
    if n != "CLAUDE.md":
        (e / n).symlink_to(m.DEFAULT_DIR / n)
Path(work).unlink()
out.append(any("does not exist" in x for x in m.link_problems(dict(emp, home=e))))
Path(work).write_text("x\n")
import json
s = base / "s"; s.mkdir(); (s / "settings.json").write_text('{"keep": 1}\n')
line = m.home_memory_excluded(emp, s)
cfg = json.loads((s / "settings.json").read_text())
out.append(bool(line) and cfg.get("keep") == 1 and cfg.get("claudeMdExcludes") == [full])
out.append(m.home_memory_excluded(emp, s) is None)
n = base / "n"; n.mkdir(); (n / "settings.json").write_text("{}\n")
out.append(m.home_memory_excluded(mine, n) is None and json.loads((n / "settings.json").read_text()) == {})
l = base / "l"; l.mkdir(); (l / "settings.json").symlink_to(n / "settings.json")
out.append("left" in (m.home_memory_excluded(emp, l) or "") and json.loads((n / "settings.json").read_text()) == {})
(e / "settings.json").write_text("{}\n")
out.append(any("claudeMdExcludes" in x for x in m.link_problems(dict(emp, home=e))))
print(" ".join("T" if x else "F" for x in out))
PY
)
check "$mem" "T T T T T T T T T T T T T T T" \
  "an employer row's CLAUDE.md links the work file (others keep the full one); Orca's stub and an older link are re-pointed, a file someone wrote is left and named, a second run does nothing (2026-10-18)"
rm -f "$F/usage-probe.json"; touch "$F/stub-fable"
check "$(DA limits work)" 0 "limits work"
has "$T/out" "fable: yes, its week 37%" "…a weekly window scoped to Fable → fable: yes, with its week"
check "$(DA limits work --cached --json; field "[0]['limits']['fable_week']")" "0
37" "…--json carries fable_week for the widget"
check "$(DA limits work --cached --json; field "[0]['limits']['fable_week_resets']")" "0
1791662400.0" "…and when that week resets (2026-10-10 20:00 UTC)"
# A reading cached before fable_week existed: plain "yes", never a week it does not have.
echo '{"at": 1, "limits": {"plan": "pro", "locked": [], "fable": true, "five_hour": 1, "five_hour_resets": 1791504000, "seven_day": 2, "seven_day_resets": 1791662400}}' > "$F/usage-probe.json"
check "$(DA limits work --cached)" 0 "limits work from an older cache"
check "$(grep -o 'fable: [^;]*' "$T/out" | head -1)" "fable: yes" "…→ fable: yes, with no week"
# A reading cached before Fable's week reset: it rolls to 0 % like the 5-hour and the week (review 2026-10-10).
echo '{"at": 1, "limits": {"plan": "max", "locked": [], "fable": true, "five_hour": 1, "five_hour_resets": 1791504000, "seven_day": 2, "seven_day_resets": 1791662400, "fable_week": 37, "fable_week_resets": 2}}' > "$F/usage-probe.json"
check "$(DA limits work --cached)" 0 "limits work from a cache older than Fable's reset"
has "$T/out" "fable: yes, its week 0%" "…→ Fable's week read as rolled over, not the stale 37%"
rm -f "$F/usage-probe.json" "$F/stub-fable"; touch "$F/stub-nofable"
check "$(DA limits work)" 0 "limits work without a Fable row"
has "$T/out" "fable: no" "…→ fable: no"
rm -f "$F/usage-probe.json" "$F/stub-nofable"
check "$(DA limits work)" 0 "limits work with no limits[] at all"
has "$T/out" "fable: unknown" "…→ fable: unknown, never a guess"

echo "doctor — both Macs against the logins file, a fix per problem (work-account E3)"
export ACCOUNT_VSCODE_USER="$T/vsc"; mkdir -p "$T/vsc/globalStorage" "$T/vsc/profiles/p1"
echo '{"userDataProfiles": [], "profileAssociations": {"workspaces": {}}}' > "$T/vsc/globalStorage/storage.json"
IH="$T/ihome"; mkdir -p "$IH/.claude" "$IH/projects/overlay"; ln -sfn "$B" "$IH/projects/overlay/bin"; ln -sfn "$B/../hooks" "$IH/projects/overlay/hooks"
login "$IH/.claude.json" u-primary p@example.com; echo p@example.com > "$IH/.claude/stub-login"; echo "10 10" > "$IH/.claude/stub-usage"; touch "$IH/.claude/stub-fable"
cat > "$T/ssh-peer" <<SH
#!/bin/sh
exec env -u ACCOUNT_VSCODE_USER HOME="$IH" ACCOUNT_HOST=server sh -c "\$1"
SH
chmod +x "$T/ssh-peer"
cat > "$ACCOUNT_LOGINS.d" <<'J'
{"logins": {"main": {"email": "p@example.com", "plan": "max", "macs": ["laptop", "server"]},
            "work": {"email": "f@example.com", "plan": "max", "macs": ["laptop", "server"]},
            "spare": {"email": "t@example.com", "macs": [], "note": "parked"}}}
J
DR() { ACCOUNTS_FILE="$ACCOUNTS_FILE.f.on" ACCOUNT_LOGINS="$ACCOUNT_LOGINS.d" ACCOUNT_HOST=laptop ACCOUNT_SSH="$T/ssh-peer" ACCOUNT_NOW=$WED A doctor "$@"; }
rm -f "$F/usage-probe.json" "$P1/usage-probe.json"; use "$F" "10 10"; use "$P1" "10 10"; touch "$P1/stub-fable" "$F/stub-nofable"
echo f@example.com > "$F/stub-login"; echo p@example.com > "$P1/stub-login"; echo '{}' > "$F/settings.json"
check "$(DR)" 1 "doctor: problems on both Macs → exit 1"
has "$T/out" "laptop:" "…the laptop's block"
has "$T/out" "server:" "…and the peer's, reached over ssh"
has "$T/out" "work: guard: missing (hooks/account_guard.py, E4)" "the guard not wired in work's dir"
has "$T/out" "CLAUDE_CONFIG_DIR=$F " "…its fix names the dir"
has "$T/out" "bootstrap.sh --hooks" "…and bootstrap.sh --hooks"
has "$T/out" "work: worktree hook: missing (hooks/worktree_allow.py), EnterWorktree can ask" "the worktree hook not wired (the owner, 2026-10-06: never ask)"
has "$T/out" "work: trust: 0/" "an untrusted dir"
has "$T/out" "trust-projects" "…with trust-projects as the fix"
has "$T/out" "work: fable: no — not safe for main sessions" "fable: no on an enabled row"
has "$T/out" "\"enabled\": false on work" "…the fix: disable it"
has "$T/out" "work: no VS Code profile work" "no work profile (D2-C)"
has "$T/out" "account vscode work" "…the verb that makes it, not a click"
has "$T/out" "work: $IH/.claude-work missing" "the peer lacks a dir the file lists for it"
has "$T/out" "$B/account setup --host server" "…its fix: the laptop's setup --host (PATH and the ssh -t login lines)"
has "$T/out" "spare: $S1 exists but the logins file lists spare for no Mac (parked)" "a parked dir is informational"
# one fix at a time, each verified by the doctor
CLAUDE_CONFIG_DIR="$F" "$B/trust-projects" --no-external-imports > /dev/null 2>&1
printf '{"hooks": {"UserPromptSubmit": [{"hooks": [{"type": "command", "command": "python3 \\"x/hooks/account_guard.py\\""}]}]}}' > "$F/settings.json"
python3 -c "import json,sys,os; p=sys.argv[1]; c=json.load(open(p)) if os.path.exists(p) else {}; c['claudeMdExcludes']=[sys.argv[2]]; json.dump(c, open(p,'w'))" "$F/settings.json" "$P1/CLAUDE.md"   # what account add / orca-sync write for an employer dir
# the worktree hook in every Claude dir the doctor reads, the peer's included (merged, nothing else touched)
for d in "$F" "$P1" "$IH/.claude"; do python3 - "$d/settings.json" <<'PY2'
import json, os, sys
p = sys.argv[1]
d = json.load(open(p)) if os.path.exists(p) else {}
d.setdefault("hooks", {})["PermissionRequest"] = [{"matcher": "EnterWorktree|ExitWorktree",
    "hooks": [{"type": "command", "command": "python3 \"x/hooks/worktree_allow.py\""}]}]
json.dump(d, open(p, "w"))
PY2
done
rm -f "$F/stub-nofable" "$F/usage-probe.json"; touch "$F/stub-fable"
python3 - "$T/vsc" "$F" <<'PY2'
import json, sys
v, f = sys.argv[1], sys.argv[2]
json.dump({"userDataProfiles": [{"location": "p1", "name": "work"}], "profileAssociations": {"workspaces": {}}}, open(v + "/globalStorage/storage.json", "w"))
json.dump({"claudeCode.environmentVariables": [{"name": "CLAUDE_CONFIG_DIR", "value": f}]}, open(v + "/profiles/p1/settings.json", "w"))
PY2
python3 - "$ACCOUNT_LOGINS.d" <<'PY2'
import json, sys
p = sys.argv[1]; d = json.load(open(p)); d["logins"]["work"]["macs"] = ["laptop"]; json.dump(d, open(p, "w"))
PY2
check "$(DR)" 0 "every fix applied → exit 0"
has "$T/out" "every row ok" "…and says so"
has "$T/out" "ok  work: f@example.com (max); guard wired" "…work with its login and guard"
has "$T/out" "ok  work: VS Code profile work runs its panel on $F" "…the profile carries the entry"
has "$T/out" "ok  main: p@example.com (max)" "…the peer's primary"
echo '{"folders": [{"path": "overlay"}, {"path": "privy"},]}' > "$HOME/projects/atlas.code-workspace"
python3 - "$T/vsc" "$HOME/projects/atlas.code-workspace" <<'PY2'
import json, sys, pathlib
v, ws = sys.argv[1], sys.argv[2]
d = json.load(open(v + "/globalStorage/storage.json"))
d["profileAssociations"]["workspaces"][pathlib.Path(ws).resolve().as_uri()] = "p1"
json.dump(d, open(v + "/globalStorage/storage.json", "w"))
PY2
check "$(DR --local)" 1 "a workspace with privy opened with the work profile → a problem"
has "$T/out" "atlas.code-workspace opens privy — profile work: a denied repo on that account" "…naming the workspace and the profile"
has "$T/out" "open it with the default profile" "…and the way out"
rm "$HOME/projects/atlas.code-workspace"
login "$F/.claude.json" u-x x@example.com
check "$(DR --local)" 1 "a dir signed in as another account than the file says"
has "$T/out" "work: signed in as x@example.com, the logins file says f@example.com" "…naming both"
has "$T/out" "CLAUDE_CONFIG_DIR=$F claude auth login" "…with the login line"
login "$F/.claude.json" u-f f@example.com; CLAUDE_CONFIG_DIR="$F" "$B/trust-projects" --no-external-imports > /dev/null 2>&1  # the helper rewrote the file, trust with it
login "$S1/.claude.json" u-f f@example.com
check "$(DR --local)" 1 "a parked dir signed in to work's seat → a problem (review 2026-10-06)"
has "$T/out" "a second way into work's seat that its deny list does not cover" "…naming the seat"
has "$T/out" "CLAUDE_CONFIG_DIR=$S1 claude auth logout" "…with the logout line"
login "$S1/.claude.json" u-primary p@example.com
mkdir -p "$HOME/.claude-stray"; touch "$F/remote-settings.json"
check "$(DR --local)" 0 "informational findings never fail the doctor"
has "$T/out" "$HOME/.claude-stray is in no registry row" "…a stray ~/.claude-* dir"
has "$T/out" "$F/remote-settings.json exists — managed settings reached this dir" "…a remote-settings file (P5)"
rm -f "$F/remote-settings.json"
python3 -c "import json;json.dump({'claudeAiOauth': {'accessToken': 'SECRET', 'expiresAt': int(($WED + 3600) * 1000)}}, open('$IH/.claude/.credentials.json', 'w'))"
check "$(DR)" 0 "the peer's credentials file: read for its expiry"
has "$T/out" "main: access token expires" "…the expiry said"
check "$(grep -c SECRET "$T/out")" 0 "…the token never printed"
# the always-on Mac's primary: .claude.json and auth status both said signed in over a dead token (TODO, 2026-10-18)
mv "$IH/.claude/stub-usage" "$IH/.claude/stub-usage.off"; rm -f "$IH/.claude/usage-probe.json"
check "$(DR)" 1 "the peer's login answers no live call → a problem, though auth status says logged in"
has "$T/out" "main: no answer to a live call (get_usage, two tries)" "…naming the live call"
has "$T/out" "ssh -t server-claude" "…with the peer's login line"
mv "$IH/.claude/stub-usage.off" "$IH/.claude/stub-usage"; touch "$IH/.claude/stub-nologin"; rm -f "$IH/.claude/usage-probe.json"
check "$(DR)" 1 "…and a \"success\" answer with no plan and no window is no live answer either"
has "$T/out" "main: no answer to a live call" "…named the same way"
rm -f "$IH/.claude/stub-nologin" "$IH/.claude/usage-probe.json"; mv "$IH/.claude/stub-login" "$IH/.claude/stub-login.off"
check "$(DR)" 1 "auth status says logged out while .claude.json keeps the e-mail → a problem"
has "$T/out" "main: p@example.com in $IH/.claude.json, but \`claude auth status\` says logged out" "…naming both readings"
mv "$IH/.claude/stub-login.off" "$IH/.claude/stub-login"
check "$(DR)" 0 "…both restored → clean again"
mv "$IH/.claude/.credentials.json" "$T/creds.off"; touch "$IH/.claude/stub-nologin"; rm -f "$IH/.claude/usage-probe.json"
mv "$IH/.claude/stub-login" "$IH/.claude/stub-login.off"
check "$(DR)" 0 "the peer's login in its keychain (no .credentials.json): ssh cannot read it, so no false alarm"
has "$T/out" "main: its login is in the keychain, which ssh cannot read" "…said, not judged"
check "$(grep -c 'says logged out' "$T/out")" 0 "…auth status's logged-out reading not judged either"
check "$(test -f "$IH/.claude/usage-probe.json"; echo $?)" 1 "…and no probe, so no null answer cached for the hooks"
# the fix line for a failed peer leg runs `doctor --local` over ssh with no --peer: SSH_CONNECTION says it
printf '#!/bin/sh\nexec env -u ACCOUNT_VSCODE_USER HOME="%s" ACCOUNT_HOST=server SSH_CONNECTION="10.0.0.1 1 10.0.0.2 22" sh -c "$(echo "$1" | sed "s/ --peer [^ ]*//")"\n' "$IH" > "$T/ssh-nopeer"; chmod +x "$T/ssh-nopeer"
check "$(ACCOUNTS_FILE="$ACCOUNTS_FILE.f.on" ACCOUNT_LOGINS="$ACCOUNT_LOGINS.d" ACCOUNT_HOST=laptop ACCOUNT_SSH="$T/ssh-nopeer" ACCOUNT_NOW=$WED A doctor)" 0 "…and the same over ssh without --peer"
has "$T/out" "main: its login is in the keychain, which ssh cannot read" "…said the same way"
mv "$IH/.claude/stub-login.off" "$IH/.claude/stub-login"
mv "$T/creds.off" "$IH/.claude/.credentials.json"; rm -f "$IH/.claude/stub-nologin" "$IH/.claude/usage-probe.json"
check "$(DR --local --json; python3 -c "import json;print(len([x for x in json.load(open('$T/out')) if x['mac'] == 'laptop']) > 0)")" "0
True" "--local --json: the peer leg's form"
printf '#!/bin/sh\necho "ssh: connect to host server port 22: Host is down" >&2; exit 255\n' > "$T/ssh-down"; chmod +x "$T/ssh-down"
check "$(ACCOUNTS_FILE="$ACCOUNTS_FILE.f.on" ACCOUNT_LOGINS="$ACCOUNT_LOGINS.d" ACCOUNT_HOST=laptop ACCOUNT_SSH="$T/ssh-down" A doctor)" 1 "the peer unreachable (ssh exit 255) → a problem"
has "$T/out" "/move --to-home" "…naming the way back to the LAN"
printf '#!/bin/sh\necho "account: no logins file here (Drive not mounted)"; exit 1\n' > "$T/ssh-text"; chmod +x "$T/ssh-text"
check "$(ACCOUNTS_FILE="$ACCOUNTS_FILE.f.on" ACCOUNT_LOGINS="$ACCOUNT_LOGINS.d" ACCOUNT_HOST=laptop ACCOUNT_SSH="$T/ssh-text" A doctor)" 1 "the peer reached but its doctor answered in text → a problem"
has "$T/out" "its doctor answered: account: no logins file" "…its own words, not \"unreachable\""
python3 - "$ACCOUNT_LOGINS.d" <<'PY2'
import json, sys
p = sys.argv[1]; d = json.load(open(p)); d["logins"]["work"]["email"] = None; json.dump(d, open(p, "w"))
PY2
check "$(DR)" 0 "doctor: a login the file lacks"
check "$(python3 -c "import json;print(json.load(open('$ACCOUNT_LOGINS.d'))['logins']['work']['email'])")" "f@example.com" "…is recorded in the logins file"
unset ACCOUNT_VSCODE_USER
unset ACCOUNT_LOGINS ACCOUNT_HOST

echo "a login Orca holds (via: orca, docs/orca-accounts-2026-10-16.md) and ships that stay on one login"
OD="$T/orca-data"; G="$OD/claude-profiles/acc-g/home"; X="$HOME/.claude-stray2"; mkdir -p "$G" "$X" "$OD/claude-profiles/acc-z/home"
cat > "$ACCOUNTS_FILE.g" <<'EOF'
{"accounts": [
  {"label": "work2", "provider": "claude", "via": "orca",
   "rules": {"week_max": 70, "window_max": 50}},
  {"label": "stray2", "provider": "claude", "home": "~/.claude-stray2",
   "rules": {"week_max": 70, "window_max": 50}},
  {"label": "main", "provider": "claude", "home": "~/.claude", "primary": true,
   "rules": {"week_max": 95, "window_max": 80}}]}
EOF
cp "$ACCOUNTS_FILE.g" "$T/registry-before"
# Orca's list as 1.4.225 shapes it (summarize(): id, email, auth fields — no dir); STUB_ORCA_EMAIL plays another sign-in
cat > "$T/orca" <<EOF
#!/bin/sh
[ "\$1 \$2" = "account list" ] || exit 9
[ -n "\${ELECTRON_RUN_AS_NODE:-}" ] && { echo "run as node" >&2; exit 8; }
[ -f "$T/orca-empty" ] && { echo '{"ok":true,"result":{"claude":{"accounts":[],"activeAccountId":null}}}'; exit 0; }
echo "{\"ok\":true,\"result\":{\"claude\":{\"accounts\":[{\"id\":\"\${STUB_ORCA_ID:-acc-g}\",\"email\":\"\${STUB_ORCA_EMAIL:-g@example.com}\",\"authMethod\":\"oauth\"}],\"activeAccountId\":null}}}"
EOF
chmod +x "$T/orca"
# VS Code's state and its `code` CLI, stood in for: --profile X --new-window makes profile X (location loc-X)
VS="$T/vscode"; mkdir -p "$VS/globalStorage" "$VS/profiles/d60c2e9"
echo '{"userDataProfiles": [{"name": "work", "location": "d60c2e9"}]}' > "$VS/globalStorage/storage.json"
echo '{"editor.fontSize": 13}' > "$VS/settings.json"
cat > "$T/code" <<EOF
#!/usr/bin/env python3
import json, sys
a = sys.argv[1:]
open("$T/code.calls", "a").write(" ".join(a) + "\\n")
st = "$VS/globalStorage/storage.json"
prof = a[a.index("--profile") + 1] if "--profile" in a else None
if prof and "--new-window" in a:
    d = json.load(open(st)); d["userDataProfiles"].append({"name": prof, "location": "loc-" + prof}); json.dump(d, open(st, "w"))
elif "--list-extensions" in a:
    print("anthropic.claude-code\\nms-python.python" if not prof else open("$T/ext-" + prof).read() if __import__("os").path.exists("$T/ext-" + prof) else "")
elif "--install-extension" in a:
    open("$T/ext-" + prof, "a").write(a[a.index("--install-extension") + 1] + "\\n")
EOF
chmod +x "$T/code"
AG() { ACCOUNTS_FILE="$ACCOUNTS_FILE.g" ACCOUNT_ORCA="$T/orca" ACCOUNT_ORCA_DATA="$OD" ACCOUNT_CODE="$T/code" ACCOUNT_VSCODE_USER="$VS" ELECTRON_RUN_AS_NODE=1 python3 "$B/account" "$@" > "$T/out" 2>&1; echo $?; }
reset; rm -f "$P1/account-ships.json" "$P1/account-orca.json" "$G/usage-probe.json" "$X/usage-probe.json"
use "$X" "10 40"; use "$P1" "10 10"; use "$G" "5 20"
check "$(ACCOUNT_NOW=$WED AG pick --json) $(field "['account']")" "0 stray2" "unsynced, an Orca row is walked past"
has "$T/out" "its login is not in Orca here" "…saying why"
check "$(AG env work2)" 1 "env of an unsynced Orca row: refused (no made-up dir handed out)"
check "$(AG run work2)" 1 "run of it: refused"
check "$(AG add work2 --no-login)" 1 "add on an Orca row, even --no-login: refused — Orca builds that dir"
check "$([ -e "$HOME/.orca-unsynced" ] && echo made || echo none)" "none" "…and no dir of ours made"
touch "$T/orca-empty"
check "$(AG orca-sync)" 1 "orca-sync with no Claude account in Orca → exit 1"
rm "$T/orca-empty"
check "$(AG orca-sync)" 1 "orca-sync: Orca has the account, but no dir there is signed in as it yet"
has "$T/out" "no dir under $OD is signed in as g@example.com yet" "…said, nothing guessed"
echo '{"oauthAccount": {"accountUuid": "u-g", "emailAddress": "g@example.com"}}' > "$G/.claude.json"
echo '{"oauthAccount": {"accountUuid": "u-z", "emailAddress": "z@example.com"}}' > "$OD/claude-profiles/acc-z/home/.claude.json"
check "$(AG orca-sync)" 1 "the dir found, but Claude Code reads no login there → nothing recorded"
check "$([ -f "$P1/account-orca.json" ] && echo written || echo none)" "none" "…ORCA_FILE untouched"
echo g@example.com > "$G/stub-login"
check "$(AG orca-sync)" 0 "orca-sync: the one Orca account, its dir found by e-mail, its login read back"
check "$(python3 -c "import json;d=json.load(open('$P1/account-orca.json'))['work2'];print(d['home'], d['orca_id'], d['email'])")" "$G acc-g g@example.com" "…recorded in this Mac's ORCA_FILE"
check "$(cmp -s "$ACCOUNTS_FILE.g" "$T/registry-before" && echo same || echo changed)" "same" "…the shared registry untouched"
check "$([ -L "$G/projects" ] && readlink "$G/projects") $([ -L "$G/skills" ] && echo linked || echo none)" "$P1/projects none" "…projects linked to ~/.claude (one transcript store); the rest left to Orca"
has "$T/out" "signed in as g@example.com" "…the login read through Claude Code, not assumed"
check "$(python3 -c "import json;print([x['name'] for x in json.load(open('$VS/globalStorage/storage.json'))['userDataProfiles']])")" "['work', 'work2']" "…and a VS Code profile work2 made (orca-accounts D2)"
check "$(python3 -c "import json;print(json.load(open('$VS/profiles/loc-work2/settings.json'))['claudeCode.environmentVariables'])")" "[{'name': 'CLAUDE_CONFIG_DIR', 'value': '$G'}]" "…its panel on work2's Orca dir"
check "$(sort "$T/ext-work2" | tr '\n' ' ')" "anthropic.claude-code ms-python.python " "…with the default profile's extensions"
check "$(cat "$VS/settings.json")" '{"editor.fontSize": 13}' "…the default profile's settings untouched"
check "$(grep -c -- '--new-window' "$T/code.calls")" 1 "…one new window, once"
check "$(ACCOUNTS_FILE="$ACCOUNTS_FILE.g" python3 "$B/account" env work2)" "CLAUDE_CONFIG_DIR=$G" "env of work2: Orca's dir for it"
check "$(ACCOUNT_NOW=$WED AG pick --json) $(field "['account']")" "0 work2" "synced, it is first in the walk"
check "$(AG orca-sync)" 0 "a second sync: idempotent"
has "$T/out" "ok  work2: $G" "…ok, same dir"
check "$(grep -c -- '--new-window' "$T/code.calls") $(grep -c -- '--install-extension' "$T/code.calls")" "1 2" "…no second window, no extension twice"
check "$(grep -c 'VS Code profile' "$T/out")" 0 "…the VS Code step only when a login is first synced (a deleted profile stays deleted)"
check "$(AG vscode main)" 1 "vscode on the default dir: refused (the default profile is it)"
check "$(AG vscode stray2; python3 -c "import json;print(json.load(open('$VS/profiles/loc-stray2/settings.json'))['claudeCode.environmentVariables'][0]['value'])")" "0
$X" "vscode on one of our own dirs: its profile too"
printf '{\n  // a comment\n  "a": 1\n}\n' > "$VS/profiles/loc-stray2/settings.json"; cp "$VS/profiles/loc-stray2/settings.json" "$T/jsonc-before"
check "$(AG vscode stray2; cmp -s "$VS/profiles/loc-stray2/settings.json" "$T/jsonc-before" && echo same)" "1
same" "a settings.json with comments: refused, the file unchanged"
python3 - "$VS/globalStorage/storage.json" <<'PY2'
import json, sys
d = json.load(open(sys.argv[1])); d["userDataProfiles"][-1]["useDefaultFlags"] = {"settings": True}; json.dump(d, open(sys.argv[1], "w"))
PY2
check "$(AG vscode stray2)" 1 "a profile sharing the default profile's settings: refused"
has "$T/out" "shares the default profile's settings" "…saying why"
python3 - "$ACCOUNTS_FILE.g" <<'PY2'
import json, sys
p = sys.argv[1]; d = json.load(open(p)); d["accounts"][1]["enabled"] = False; json.dump(d, open(p, "w"))
PY2
check "$(AG vscode stray2)" 1 "a parked login: no profile for it"
python3 - "$ACCOUNTS_FILE.g" <<'PY2'
import json, sys
p = sys.argv[1]; d = json.load(open(p)); d["accounts"][1]["enabled"] = True; json.dump(d, open(p, "w"))
PY2
cat > "$T/logins.json" <<'EOF'
{"logins": {"work2": {"email": "g@example.com"}}}
EOF
rm "$P1/account-orca.json"
check "$(STUB_ORCA_EMAIL=other@example.com ACCOUNT_LOGINS="$T/logins.json" AG orca-sync)" 1 "the logins file says g@, Orca's one account is another: refused, never bound"
has "$T/out" "none signed in as g@example.com" "…saying which login is wanted"
check "$(ACCOUNT_LOGINS="$T/logins.json" AG orca-sync)" 0 "…and with the right sign-in: bound by e-mail"
echo "ships"
reset; rm -f "$G/usage-probe.json" "$X/usage-probe.json"; use "$X" "10 40"; use "$G" "5 20"
check "$(ACCOUNT_NOW=$WED AG pick --ship overlay/b7 --json) $(field "['account']")" "0 work2" "a new ship gets the walk's pick"
has "$T/out" "ship overlay/b7 pinned" "…and is pinned to it"
rm -f "$G/usage-probe.json"; use "$G" "60 20"
check "$(ACCOUNT_NOW=$WED AG pick --json) $(field "['account']")" "0 stray2" "work2's 5 hours over 50%: a new ship goes elsewhere"
check "$(ACCOUNT_NOW=$WED AG pick --ship overlay/b7)" 3 "…but the pinned ship stays on work2 and waits (exit 3)"
has "$T/out" "ship overlay/b7 stays on work2 and waits" "…saying so"
check "$(ACCOUNT_NOW=$WED AG pick --ship overlay/other --no-pin --json) $(field "['account']")" "0 stray2" "--no-pin: picked, not pinned"
check "$(python3 -c "import json;print('overlay/other' in json.load(open('$P1/account-ships.json')))")" "False" "…nothing written"
check "$(ACCOUNT_NOW=$WED AG ships --pin overlay/other stray2)" 0 "ships --pin: the caller pins once its worker started"
rm -f "$G/usage-probe.json"; use "$G" "10 20"
check "$(ACCOUNT_NOW=$WED AG pick --ship overlay/b7 --json) $(field "['account']")" "0 work2" "room again: the ship carries on on work2"
check "$(ACCOUNT_NOW=$WED AG ships)" 0 "ships lists the pins"
has "$T/out" "overlay/b7: work2" "…b7 on work2"
has "$T/out" "overlay/other: stray2" "…other on stray2"
printf '{"repos": {"app2": {}}, "scopes": {"node": {"file": "n.code-workspace", "repos": ["app2"], "login": "stray2"}}}\n' > "$T/scoped3.json"
check "$(CLAUDE_REPOS_JSON="$T/scoped3.json" ACCOUNT_NOW=$WED AG pick --ship overlay/b7 --repo "$PR/app2" --json) $(field "['account']")" "0 stray2" \
  "a ship pinned to work2, run in a repo whose scope's login is stray2: it moves there"
has "$T/out" "moved: work2 is not scope node's login stray2" "…saying why"
check "$(ACCOUNT_NOW=$WED AG ships --pin overlay/b7 work2)" 0 "…(pinned back for the cases after)"
rm -f "$P1/usage-probe.json"; rm -f "$P1/stub-usage"
check "$(ACCOUNT_NOW=$WED AG ships --pin overlay/p main; ACCOUNT_NOW=$WED AG pick --ship overlay/p --json) $(field "['account']")" "0
0 main" "a ship pinned to the primary whose limits cannot be read: runs, as plain pick has it"
use "$P1" "10 10"
python3 - "$ACCOUNTS_FILE.g" <<'PY2'
import json, sys
p = sys.argv[1]; d = json.load(open(p)); d["accounts"][0]["enabled"] = False; json.dump(d, open(p, "w"))
PY2
check "$(ACCOUNT_NOW=$WED AG pick --ship overlay/b7 --json) $(field "['account']")" "0 stray2" "the owner parks work2: the ship moves (a parked login is no login)"
has "$T/out" "moved: work2 is disabled" "…and says it moved"
check "$(ACCOUNT_NOW=$WED AG pick --ship overlay/new --cached --json; python3 -c "import json;print('overlay/new' in json.load(open('$P1/account-ships.json')))")" "0
False" "--cached (a dry run) pins nothing"
check "$(ACCOUNT_NOW=$WED AG ships --release overlay/b7)" 0 "ships --release"
check "$(python3 -c "import json;print(sorted(json.load(open('$P1/account-ships.json'))))")" "['overlay/other', 'overlay/p']" "…unpins that ship only"
check "$(ACCOUNT_NOW=$(python3 -c "print($WED + 15 * 86400)") AG ships; cat "$T/out" | wc -l | tr -d ' ')" "0
0" "a pin unused for 15 days is gone (PIN_DAYS)"
check "$(AG pick --ship x --bound)" 1 "--ship with --bound: refused"
echo "every Orca login in the walk by default, no registry row needed (the owner, 2026-10-16)"
H2="$OD/claude-profiles/acc-h/home"; mkdir -p "$H2"
echo '{"oauthAccount": {"accountUuid": "u-h", "emailAddress": "h@example.com"}}' > "$H2/.claude.json"
echo h@example.com > "$H2/stub-login"; use "$H2" "5 10"
cat > "$ACCOUNTS_FILE.h" <<'EOF'
{"accounts": [
  {"label": "stray2", "provider": "claude", "home": "~/.claude-stray2", "rules": {"week_max": 70, "window_max": 50}},
  {"label": "main", "provider": "claude", "home": "~/.claude", "primary": true, "rules": {"week_max": 95, "window_max": 80}}]}
EOF
AH() { ACCOUNTS_FILE="$ACCOUNTS_FILE.h" ACCOUNT_ORCA="$T/orca" ACCOUNT_ORCA_DATA="$OD" STUB_ORCA_EMAIL=h@example.com python3 "$B/account" "$@" > "$T/out" 2>&1; echo $?; }
reset; rm -f "$P1/account-orca.json" "$X/usage-probe.json" "$H2/usage-probe.json"; use "$X" "60 40"; use "$P1" "10 10"
check "$(AH orca-sync)" 0 "orca-sync with no row for an Orca login: synced as a row of its own"
has "$T/out" "new orca-h: $H2" "…labelled from its e-mail"
has "$T/out" "in the walk" "…and in the walk by default"
check "$(ACCOUNT_NOW=$WED AH pick --json) $(field "['account']")" "0 orca-h" "pick: the Orca login, before the primary"
check "$(AH limits orca-h --repo "$HOME/projects/privy" --cached --json) $(field "[0]['denied']")" "0 privy" "…with a secondary's deny list"
check "$(AH orca off orca-h; ACCOUNT_NOW=$WED AH pick --json) $(field "['account']")" "0
0 main" "orca off: out of the walk at once, no commit"
check "$(AH limits --all --parked --cached --json; python3 -c "import json;print('orca-h' in [r['label'] for r in json.load(open('$T/out'))])")" "0
False" "orca off: hidden from limits --all --parked too (how a login leaves the widget)"
check "$(AH orca on orca-h; ACCOUNT_NOW=$WED AH pick --json) $(field "['account']")" "0
0 orca-h" "orca on: back in"
check "$(AH orca off nobody)" 1 "orca off on a login never synced: refused"
python3 - "$P1/account-orca.json" <<'PY2'
import json, sys
p = sys.argv[1]; d = json.load(open(p)); d["codex-owner"] = {"home": "/c", "provider": "codex"}; json.dump(d, open(p, "w"))
PY2
check "$(AH orca-sync; python3 -c "import json;print('codex-owner' in json.load(open('$P1/account-orca.json')))"; ACCOUNT_NOW=$WED AH pick --json; field "['account']")" "0
True
0
orca-h" "a Codex login in the read-back: never pruned by a Claude sync, never picked for Claude work"
check "$(AH orca default off; ACCOUNT_NOW=$WED AH pick --json) $(field "['account']")" "0
0 orca-h" "orca default off moves no login already synced"
rm -f "$P1/account-orca.json"
check "$(AH orca default off; AH orca-sync; ACCOUNT_NOW=$WED AH pick --json) $(field "['account']")" "0
0
0 main" "orca default off: a login found later is recorded off"
check "$(python3 -c "import json;print(json.load(open('$P1/account-orca.json'))['orca-h']['enabled'])")" "False" "…its switch in the overlay"
rm -f "$P1/account-orca.json"
check "$(AH orca-sync --off; python3 -c "import json;print(json.load(open('$P1/account-orca.json'))['orca-h'].get('enabled'))")" "0
False" "orca-sync --off: this run's new logins off"
rm -f "$P1/account-orca.json"
check "$(AH orca-sync >/dev/null; AH orca off orca-h >/dev/null; touch "$T/orca-empty"; AH orca-sync; rm -f "$T/orca-empty"; grep -c 'kept as it was' "$T/out"; python3 -c "import json;print(json.load(open('$P1/account-orca.json'))['orca-h']['enabled'])"; AH orca on orca-h >/dev/null)" "0
1
False" "Orca listing no account at all: every login kept, its switch too (Orca not ready)"
check "$(ACCOUNTS_FILE="$ACCOUNTS_FILE.h" ACCOUNT_ORCA="$T/orca" ACCOUNT_ORCA_DATA="$OD" STUB_ORCA_ID=acc-other STUB_ORCA_EMAIL=other@example.com python3 "$B/account" orca-sync > "$T/out" 2>&1; echo $?; grep -c 'gone    orca-h' "$T/out"; ACCOUNT_NOW=$WED AH pick --json; field "['account']")" "1
1
0
main" "a login removed from Orca (another still there) leaves the walk"
rm -f "$P1/account-orca.json"
echo '{"work2": {"home": "'"$G"'", "orca_id": "acc-g", "enabled": false}}' > "$P1/account-orca.json"
check "$(ACCOUNT_NOW=$WED AG pick --json) $(field "['account']")" "0 main" "the overlay's switch also turns off a registry row of Orca's (work2 has room; stray2 is full)"
rm -f "$P1/account-orca.json"
rm -f "$P1/account-ships.json" "$P1/account-orca.json"

echo "Codex logins Orca uses: rows, read by codex app-server (widget, 2026-10-16)"
# The stub app-server: account/read from <CODEX_HOME>/stub-email, rateLimits from stub-limits as "used% window-minutes"
cat > "$T/codex" <<EOF
#!/usr/bin/env python3
import json, os, sys
h = os.environ["CODEX_HOME"]; rd = lambda n: open(os.path.join(h, n)).read().strip() if os.path.exists(os.path.join(h, n)) else ""
open("$T/codex.calls", "a").write(h + "\\n")
while True:
  chunk = os.read(0, 65536)
  if not chunk: break
  out = []
  for line in chunk.decode().splitlines():
    m = json.loads(line)
    if "id" not in m: continue
    if m["method"] == "initialize": r = {"codexHome": h}
    elif m["method"] == "account/read": r = {"account": {"type": "chatgpt", "email": rd("stub-email"), "planType": "prolite"} if rd("stub-email") else None}
    elif m["method"] == "account/rateLimits/read":
        if not rd("stub-email"):  # signed out: the real server's error (probed 2026-10-16)
            out.append(json.dumps({"error": {"code": -32600, "message": "codex account authentication required to read rate limits"}, "id": m["id"]})); continue
        u, w = (rd("stub-limits") or "0 10080").split()
        r = {"rateLimits": {"limitId": "codex", "primary": {"usedPercent": int(u), "windowDurationMins": int(w), "resetsAt": 1792650034}, "secondary": None, "planType": "prolite"}}
        if rd("stub-reached"):  # the server says the limit is reached, with no reset time
            r["rateLimits"].update(rateLimitReachedType="rate_limit_reached"); r["rateLimits"]["primary"]["resetsAt"] = None
    out.append(json.dumps({"id": m["id"], "result": r}))
  # every reply to one read goes out in one write: the burst a buffered readline under select() missed
  sys.stdout.write("".join(l + "\\n" for l in out)); sys.stdout.flush()
EOF
chmod +x "$T/codex"
C1="$HOME/.codex"; CM="$OD/codex-accounts/cx-1/home"; mkdir -p "$C1" "$CM"
echo c@example.com > "$C1/stub-email"; echo "13 10080" > "$C1/stub-limits"; echo m@example.com > "$CM/stub-email"
cat > "$ACCOUNTS_FILE.c" <<'EOF'
{"accounts": [
  {"label": "main", "provider": "claude", "home": "~/.claude", "primary": true,
   "rules": {"week_max": 95, "window_max": 80}}]}
EOF
cat > "$T/orca-c" <<EOF
#!/bin/sh
managed='{"id":"cx-1","email":"m@example.com"}'; [ -f "$T/orca-c-nomanaged" ] && managed=''
auth=true; [ -f "$T/orca-c-empty" ] && { managed=''; auth=false; }
echo "{\"ok\":true,\"result\":{\"claude\":{\"accounts\":[]},\"codex\":{\"accounts\":[\$managed],\"systemDefault\":{\"hasAuth\":\$auth,\"email\":\"c@example.com\"}}}}"
EOF
chmod +x "$T/orca-c"
AC() { ACCOUNTS_FILE="$ACCOUNTS_FILE.c" ACCOUNT_ORCA="$T/orca-c" ACCOUNT_ORCA_DATA="$OD" ACCOUNT_CODEX="$T/codex" python3 "$B/account" "$@" > "$T/out" 2>&1; echo $?; }
reset; rm -f "$P1/account-orca.json" "$C1/usage-probe.json"; use "$P1" "10 10"
check "$(AC orca-sync)" 0 "orca-sync: Orca's Codex system default and its managed login, each read back in its home"
check "$(python3 -c "import json;d=json.load(open('$P1/account-orca.json'));print(sorted((k, v['provider'], v['home']) for k, v in d.items()))")" \
  "[('codex-c', 'codex', '$C1'), ('codex-m', 'codex', '$CM')]" "…recorded as codex rows, labelled from the e-mail"
check "$(ACCOUNT_NOW=$WED AC limits --all --json) $(python3 -c "import json;print([(r['label'], r['provider'], r['limits'] and r['limits']['seven_day'], r['limits'] and r['limits']['five_hour']) for r in json.load(open('$T/out'))])")" \
  "0 [('codex-c', 'codex', 13, None), ('codex-m', 'codex', 0, None), ('main', 'claude', 10, 10)]" "limits --all: the Codex rows' week from app-server, beside Claude's"
check "$(field "[0]['eligible']")" "True" "…a week-only plan's missing 5-hour window is no limit"
check "$(ACCOUNT_NOW=$WED AC pick --json) $(field "['account']")" "0 main" "a Codex row never enters the Claude walk"
check "$(AC orca-sync; python3 -c "import json;print(len(json.load(open('$P1/account-orca.json'))))")" "0
2" "a second sync: idempotent, the Claude half's gone-sweep leaves Codex entries alone"
echo other@example.com > "$CM/stub-email"; rm -f "$P1/account-orca.json"
check "$(AC orca-sync)" 1 "a managed home signed in as another e-mail: not recorded"
has "$T/out" "is signed in as other@example.com, Orca says m@example.com" "…saying why"
echo m@example.com > "$CM/stub-email"; AC orca-sync > /dev/null; touch "$T/orca-c-nomanaged"
check "$(AC orca-sync; grep -c 'gone    codex-m' "$T/out")" "0
1" "a Codex login gone from Orca leaves the rows"
rm -f "$T/orca-c-nomanaged" "$P1/account-orca.json"
AC orca-sync > /dev/null; AC orca off codex-m > /dev/null; touch "$T/orca-c-empty"
check "$(AC orca-sync; python3 -c "import json;d=json.load(open('$P1/account-orca.json'));print(sorted(d), d['codex-m'].get('enabled'))")" "0
['codex-c', 'codex-m'] False" "an empty Codex list is Orca not ready: every entry and its switch kept (review 2026-10-16)"
rm -f "$T/orca-c-empty"; echo other@example.com > "$CM/stub-email"
check "$(AC orca-sync; python3 -c "import json;print(sorted(json.load(open('$P1/account-orca.json'))))")" "1
['codex-c']" "a recorded home signed in as another e-mail leaves the rows, not left probing the wrong quota"
echo m@example.com > "$CM/stub-email"; rm -f "$P1/account-orca.json"; AC orca-sync > /dev/null
echo 1 > "$C1/stub-reached"; rm -f "$C1/usage-probe.json"
check "$(ACCOUNT_NOW=$WED AC limits codex-c --json) $(field "[0]['eligible']")" "0 False" "a limit Codex says is reached, with no reset time: not eligible"
rm -f "$C1/stub-reached" "$C1/usage-probe.json" "$C1/exhaustion.jsonl"
check "$(AC run codex-c)" 1 "run refuses a Codex row: it would start claude on the default login"
rm -f "$C1/stub-email" "$C1/usage-probe.json"; s=$(date +%s)
check "$(ACCOUNT_NOW=$WED AC limits codex-c --json) $(field "[0]['limits']")" "0 None" "a signed-out Codex home: no reading…"
check "$(( $(date +%s) - s < 5 ))" 1 "…at once, not after a timeout (the error reply is an answer)"
echo c@example.com > "$C1/stub-email"
AC orca-sync > /dev/null; AC orca off codex-c > /dev/null
chmod -x "$T/codex"   # the binary will not start: no answer at all
check "$(AC orca-sync; python3 -c "import json;print(json.load(open('$P1/account-orca.json'))['codex-c'].get('enabled'))")" "1
False" "a Codex home that gives no answer: the entry and its off switch are kept"
chmod +x "$T/codex"
cat > "$T/parse.py" <<'PY'
import runpy, sys
m = runpy.run_path(sys.argv[1], run_name="account_test")
l = m["parse_codex"]({"rateLimits": {"primary": {"usedPercent": 10, "windowDurationMins": 10080, "resetsAt": 1}},
                      "rateLimitsByLimitId": {"x": {"primary": {"usedPercent": 60, "windowDurationMins": 300, "resetsAt": 2},
                                                    "spendControlReached": True}}})
print(l["seven_day"], l["five_hour"], l["locked"])
PY
check "$(python3 "$T/parse.py" "$B/account")" "10 None ['seven_day']" \
  "parse_codex: a per-model bucket feeds no window, but its spend control locks the login's"
rm -f "$P1/account-orca.json"
cat > "$ACCOUNTS_FILE.l" <<'EOF'
{"accounts": [
  {"label": "main", "provider": "claude", "home": "~/.claude", "primary": true,
   "rules": {"week_max": 95, "window_max": 80}},
  {"label": "spare", "provider": "claude", "home": "~/.claude-spare",
   "rules": {"week_max": 70, "window_max": 50}}]}
EOF
reset; rm -f "$P1/stub-usage"; use "$S1" "10 10"; login "$S1/.claude.json" u-last t@example.com
check "$(ACCOUNT_NOW=$WED ACCOUNTS_FILE="$ACCOUNTS_FILE.l" A pick --json) $(field "['account']")" "0 main" \
  "a row after the primary (spare, the last resort) never runs ahead of a primary whose limits are unknown"
use "$P1" "10 99"
check "$(ACCOUNT_NOW=$WED ACCOUNTS_FILE="$ACCOUNTS_FILE.l" A pick --json) $(field "['account']")" "0 spare" "…and runs once the primary has no room"
reset

echo "limits --orca: every other agent Orca reads limits for, as report-only rows (2026-10-20)"
# Orca's rateLimits as 1.4.x shapes it: Claude and Codex (probed here per login, so never repeated),
# an agent with quota buckets, one with a month and no buckets, one with no login, one whose
# reading failed, and the non-agent keys beside them. Times are milliseconds.
ms() { python3 -c "print(int(($WED + $1) * 1000))"; }
cat > "$T/orca-r.json" <<EOF
{"ok": true, "result": {"claude": {"accounts": []}, "rateLimits": {
  "claude": {"provider": "claude", "status": "ok", "weekly": {"usedPercent": 99, "windowMinutes": 10080, "resetsAt": $(ms 86400)}},
  "codex": {"provider": "codex", "status": "ok", "weekly": {"usedPercent": 99, "windowMinutes": 10080, "resetsAt": $(ms 86400)}},
  "agy": {"provider": "agy", "status": "ok", "session": null, "updatedAt": $(ms -600),
          "weekly": {"usedPercent": 40, "windowMinutes": 10080, "resetsAt": $(ms 432000)},
          "buckets": [{"name": "Fast Models", "usedPercent": 12, "windowMinutes": 10080, "resetsAt": $(ms 432000)},
                      {"name": "Big models", "usedPercent": 40, "windowMinutes": 10080, "resetsAt": $(ms 432000)}]},
  "monthly-one": {"provider": "mon", "status": "ok", "planType": "free", "updatedAt": $(ms -60),
                  "weekly": {"usedPercent": 7, "windowMinutes": 10080, "resetsAt": $(ms 259200)},
                  "monthly": {"usedPercent": 5, "windowMinutes": 44640, "resetsAt": $(ms 1728000)}},
  "nologin": {"provider": "nologin", "status": "unavailable", "error": "Not signed in"},
  "flaky": {"provider": "flaky", "status": "error", "error": "token expired", "weekly": null},
  "claudeTarget": {"runtime": "host"}, "nologinConfigured": false, "inactiveClaudeAccounts": []}}}
EOF
# the stub logs each call; -down plays an app not running, -empty one not ready (no agent listed),
# -bad an answer whose shape changed (a buckets list that is a number)
cat > "$T/orca-r" <<EOF
#!/bin/sh
[ "\$1 \$2" = "account list" ] || exit 9
echo call >> "$T/orca-r-calls"
[ -f "$T/orca-r-down" ] && { echo "connect ECONNREFUSED" >&2; exit 1; }
[ -f "$T/orca-r-empty" ] && { echo '{"ok": true, "result": {"rateLimits": {}}}'; exit 0; }
[ -f "$T/orca-r-bad" ] && { sed 's/"buckets": \[/"buckets": 5, "x": [/' "$T/orca-r.json"; exit 0; }
cat "$T/orca-r.json"
EOF
chmod +x "$T/orca-r"
AR() { ACCOUNTS_FILE="$ACCOUNTS_FILE.c" ACCOUNT_ORCA="$T/orca-r" ACCOUNT_NOW=${NOW_AT:-$WED} python3 "$B/account" "$@" > "$T/out" 2>&1; echo $?; }
reset; rm -f "$P1/account-orca.json" "$P1/account-orca-limits.json" "$T/orca-r-calls"; use "$P1" "10 10"
rows() { python3 -c "import json;print([$1 for r in json.load(open('$T/out')) if ${2:-True}])"; }
check "$(AR limits --all --orca --json; rows "r['label']")" "0
['main', 'agy', 'mon', 'flaky']" "limits --all --orca: one row per agent Orca reads, bar Claude and Codex (probed here) and one with no login"
check "$(rows "(r['label'], r['provider'], r['eligible'], r.get('report'), r['limits'] and [(b['name'], b['percent']) for b in r['limits']['buckets'] + r['limits']['windows']])" "r.get('via') == 'orca'")" \
  "[('agy', 'agy', False, True, [('Fast Models', 12), ('Big models', 40)]), ('mon', 'mon', False, True, [('month', 5)]), ('flaky', 'flaky', False, True, None)]" \
  "…report only, never eligible: an agent's own buckets and its other windows by name; a failed reading has none"
check "$(rows "(r['limits']['seven_day'], r['limits']['five_hour'], r['limits']['locked'], r['sampled'] == $WED - 600)" "r['label'] == 'agy'")" \
  "[(40, None, [], True)]" "…Orca's week as the week, its time as the sample's"
check "$(rows "(r['limits']['seven_day'], r['limits']['buckets'])" "r['label'] == 'mon'")" "[(7, [])]" \
  "…an agent with a month and no buckets keeps its week beside the month (review 2026-10-21)"
check "$(field "[3]['why']")" "Orca: token expired" "…and a failed one says Orca's error"
check "$(ACCOUNTS_FILE="$ACCOUNTS_FILE.c" ACCOUNT_ORCA="$T/orca-r" python3 "$B/account" limits --all --cached --json 2>/dev/null | python3 -c "import json,sys;print([r['label'] for r in json.load(sys.stdin)])")" \
  "['main']" "without --orca: no such row (the walk, the tier check, usage-report)"
check "$(AR limits --all --orca; grep -c '(Orca)' "$T/out")" "0
3" "the text form: a line per agent"
has "$T/out" "agy (Orca): week 40% (resets Mon 12:00); Fast Models 12% (resets Mon 12:00); Big models 40%" "…its week and buckets"
has "$T/out" "mon (Orca): week 7% (resets Sat 12:00); month 5% (resets Oct 27 12:00)" "…a reset more than a week ahead by its date"
has "$T/out" "flaky (Orca): no reading; Orca: token expired" "…and no figure as 'no reading'"
check "$(wc -l < "$T/orca-r-calls" | tr -d ' '; AR limits --all --orca --cached --json; wc -l < "$T/orca-r-calls" | tr -d ' '; rows "(r['label'], r['why'][:19])" "r.get('via')")" \
  "2
0
2
[('agy', \"Orca's last reading\"), ('mon', \"Orca's last reading\")]" "--cached asks Orca nothing: the last readings (review 2026-10-21)"
touch "$T/orca-r-down"
check "$(AR limits --all --orca --json; rows "(r['label'], r['why'][:16])" "r.get('via')")" \
  "0
[('agy', 'Orca unreadable '), ('mon', 'Orca unreadable ')]" "Orca down: each agent's last reading, said so; no output on stderr (the widget's reply would fail)"
check "$(NOW_AT=$(python3 -c "print($WED + 6 * 86400)") AR limits --all --orca --json; rows "[b['percent'] for b in r['limits']['buckets']]" "r['label'] == 'agy'")" \
  "0
[[0, 0]]" "…a bucket past its reset reads 0, as a window does"
rm -f "$T/orca-r-down"; touch "$T/orca-r-empty"
check "$(AR limits --all --orca --json; rows "(r['label'], r['why'][:20])" "r.get('via')"; python3 -c "import json;print(sorted(json.load(open('$P1/account-orca-limits.json'))))")" \
  "0
[('agy', 'Orca listed no agent'), ('mon', 'Orca listed no agent')]
['agy', 'flaky', 'mon']" "Orca listing no agent is Orca not ready: the last readings, none wiped (review 2026-10-21)"
rm -f "$T/orca-r-empty"; touch "$T/orca-r-bad"
check "$(AR limits --all --orca --json; rows "(r['label'], r['why'][:40])" "r.get('via')")" \
  "0
[('agy', \"Orca's answer unreadable (TypeError); it\"), ('mon', \"Orca's answer unreadable (TypeError); it\")]" \
  "an answer of a changed shape: the last readings, said so, never a traceback on stderr"
rm -f "$T/orca-r-bad"
check "$(AR orca off agy; AR limits --all --orca --json; rows "r['label']")" "0
0
['main', 'mon', 'flaky']" "orca off: an agent's card hidden"
check "$(AR orca on agy; AR limits --all --orca --json; rows "r['label']")" "0
0
['main', 'agy', 'mon', 'flaky']" "…orca on: back"
rm -f "$P1/account-orca-limits.json"
check "$(AR orca off mon; python3 -c "import json;print(json.load(open('$P1/account-orca-limits.json'))['mon'])")" "0
{'enabled': False}" "orca off for an agent not read yet: looked up in Orca, switched (review 2026-10-21)"
check "$(AR orca off nosuch)" 1 "…one Orca has no agent or login by that name: refused"
has "$T/out" "no agent Orca reads limits for" "…saying so"
AR orca on mon > /dev/null
python3 - "$T/run-parse.py" "$B/account" <<'PY'
import sys
open(sys.argv[1], "w").write('''import runpy, sys
m = runpy.run_path(sys.argv[1], run_name="account_test")
w = {"usedPercent": 100, "windowMinutes": 10080, "resetsAt": 1}
print(m["parse_orca"]({"weekly": w, "buckets": [dict(w, name="A"), dict(w, name="B", usedPercent=20)]})["locked"],
      m["parse_orca"]({"weekly": w})["locked"])
mo = dict(w, windowMinutes=44640)
print(m["parse_orca"]({"monthly": mo, "buckets": [dict(mo, name="A")]})["windows"])
''')
PY
check "$(python3 "$T/run-parse.py" "$B/account")" "[] ['seven_day']
[]" \
  "parse_orca: a full week that is an agent's fuller bucket locks nothing; a week alone locks; a month of its buckets' span is their summary, no bar of its own (review 2026-10-21)"
AR limits --all --orca --json > /dev/null   # a good reading of agy first
python3 - "$T/orca-r.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); a = d["result"]["rateLimits"]["agy"]
a.update(status="error", error="auth expired"); json.dump(d, open(sys.argv[1], "w"))
PY
check "$(AR limits --all --orca --json; rows "(r['limits']['seven_day'], r['why'])" "r['label'] == 'agy'")" \
  "0
[(40, 'Orca: auth expired; its last reading')]" "a reading that fails after a good one keeps the good one, said so"
python3 - "$T/orca-r.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); a = d["result"]["rateLimits"]["agy"]
a.update(status="unavailable", error="Update agy", usageMetadata={"failureKind": "usage-unavailable"}); json.dump(d, open(sys.argv[1], "w"))
PY
check "$(AR limits --all --orca --json; rows "(r['limits']['seven_day'], r['why'])" "r['label'] == 'agy'")" \
  "0
[(40, 'Orca: Update agy; its last reading')]" "Orca's unavailable for a CLI too old keeps the card and says why (review 2026-10-21)"
python3 - "$T/orca-r.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); a = d["result"]["rateLimits"]["agy"]
a.update(usageMetadata={"failureKind": "missing-credentials"}); json.dump(d, open(sys.argv[1], "w"))
PY
check "$(AR limits --all --orca --json; rows "r['label']")" "0
['main', 'mon', 'flaky']" "…signed out: no card"
cat > "$ACCOUNTS_FILE.o" <<'EOF'
{"accounts": [
  {"label": "main", "provider": "claude", "home": "~/.claude", "primary": true, "rules": {"week_max": 95, "window_max": 80}},
  {"label": "mon", "provider": "claude", "home": "~/.claude-mon", "enabled": false, "rules": {}},
  {"label": "orca-mon", "provider": "claude", "home": "~/.claude-orca-mon", "enabled": false, "rules": {}}]}
EOF
check "$(ACCOUNTS_FILE="$ACCOUNTS_FILE.o" ACCOUNT_ORCA="$T/orca-r" ACCOUNT_NOW=$WED python3 "$B/account" limits --all --orca --json 2>/dev/null | python3 -c "import json,sys;print([(r['label'], r['provider']) for r in json.load(sys.stdin)])")" \
  "[('main', 'claude'), ('orca-mon-2', 'mon'), ('flaky', 'flaky')]" \
  "an agent named as a row, and its orca- name taken too, gets a unique label, never a shadow; its provider stays Orca's"
rm -f "$P1/account-orca-limits.json" "$T/orca-r-calls"; reset

echo "peers absent: wharf's window and worktree hook, plumb's usage column (G16, G18)"
peer() { python3 -c 'import sys, importlib.machinery as m, importlib.util as u
sp = u.spec_from_loader("acct", m.SourceFileLoader("acct", sys.argv[1])); a = u.module_from_spec(sp); sp.loader.exec_module(a)
print(a.worktree_allow_present(), a.attribution("main"))
a.open_in_terminal(["claude", "auth", "login"], {"CLAUDE_CONFIG_DIR": "/x"})' "$1" 2>&1; }
# wharf is in this repo since B5, so the absent case runs from a copy of the core and lighthouse
# without it (AGENTS.md's "peer absent" trap).
NW="$T/nowharf"; mkdir -p "$NW/modules" "$T/nothing"
cp -R "$B/../../regatta" "$NW/modules/regatta"; cp -R "$B/.." "$NW/modules/lighthouse"
check "$(peer "$NW/modules/lighthouse/bin/account" | tr '\n' '|')" "False None|  (wharf's fork_claude_session.py not installed: no window opened — run it yourself:) CLAUDE_CONFIG_DIR=/x claude auth login|" \
  "no wharf, no plumb: the worktree check skipped, no usage column, the window's command printed"
# The overlay's checkout holds a worktree_allow.py, and the marker names it: since B14b the core
# never finds a tool there, so the wharf-less copy still has none.
check "$(peer "$NW/modules/lighthouse/bin/account" | head -1)" "False None" \
  "  B14b: the overlay's worktree_allow.py is no fallback"

echo "tenants: a tenant's repos run on its own login, routed, not banned (2026-10-20)"
export ACCOUNT_VSCODE_USER="$T/vsc-t"; mkdir -p "$T/vsc-t/globalStorage" "$T/vsc-t/profiles/pl"
L="$HOME/.claude-lab"; mkdir -p "$L"; login "$L/.claude.json" u-lab c@example.com
for r in acme-one acme-two; do git init -q "$PR/$r"; git -C "$PR/$r" commit -q --allow-empty -m init; done
git -C "$PR/acme-one" worktree add -q "$PR/acme-one/.claude/worktrees/y" -b y 2>/dev/null
cat > "$ACCOUNTS_FILE.t" <<'J'
{"accounts": [
  {"label": "work", "provider": "claude", "home": "~/.claude-work", "repos": {"deny": ["privy", "cv"]}},
  {"label": "lab", "provider": "claude", "home": "~/.claude-lab", "tenant": "acme"},
  {"label": "main", "provider": "claude", "home": "~/.claude", "primary": true}],
 "tenants": {"acme": {"repos": ["acme-*"]}, "bad": "not an object"}}
J
TA() { ACCOUNTS_FILE="$ACCOUNTS_FILE.t" ACCOUNT_NOW=$WED A "$@"; }
rm -f "$F/usage-probe.json" "$P1/usage-probe.json" "$L/usage-probe.json"; use "$F" "10 10"; use "$P1" "10 10"; use "$L" "10 10"
check "$(TA pick --repo "$PR/acme-one" --json) $(field "['account']")" "0 lab" "pick --repo a tenant's repo → its login, past the rows before it"
has "$T/out" "acme-one is acme's: it runs on lab only (tenants)" "…naming why work was skipped"
check "$(TA pick --repo "$PR/acme-two" --json) $(field "['account']")" "0 lab" "a glob entry: a second repo is the tenant's too"
check "$(TA pick --repo "$PR/acme-one/.claude/worktrees/y" --json) $(field "['account']")" "0 lab" "…and a worktree of one"
check "$(TA pick --repo "$PR/app" --json) $(field "['account']")" "0 work" "another repo: the walk as before"
check "$(TA pick --repo "$PR/privy" --json) $(field "['account']")" "0 lab" "the tenant's login runs elsewhere by its own deny list (none: privy too)"
use "$L" "100 100"; rm -f "$L/usage-probe.json"
check "$(TA pick --repo "$PR/acme-one" --json)" 3 "the tenant's login out of room → exit 3, never the primary's or another seat"
use "$L" "10 10"; rm -f "$L/usage-probe.json" "$L/exhaustion.jsonl"
check "$(TA limits --all --repo "$PR/acme-one" --json; python3 -c "import json;print([(r['label'], r['eligible']) for r in json.load(open('$T/out'))])")" "0
[('work', False), ('lab', True), ('main', False)]" "limits --repo: only the tenant's login is eligible"
check "$(TA pick --repo acme-one --json) $(field "['account']")" "0 lab" "pick --repo <key> of a tenant's repo (a glob match, no clone here) → its login"
check "$(TA limits --all --repo acme-one --json; python3 -c "import json;print([(r['label'], r['eligible']) for r in json.load(open('$T/out'))])")" "0
[('work', False), ('lab', True), ('main', False)]" "limits --repo <key>: the default dir's row judged as the path's is"
check "$(TA allowed "$PR/acme-one")" 1 "allowed: the default dir in a tenant's repo → exit 1"
has "$T/out" "acme-one is off main: it is acme's, which runs on lab only (accounts.json tenants) — open it in VS Code profile lab, or \`$B/account run lab\` in a Terminal" "…the guard's line, with the way in"
check "$(TA allowed "$PR/privy")" 0 "…the default dir still denies nothing else"
check "$(TA allowed "$PR")" 0 "…nor ~/projects, which holds the tenant's repo (holds_denied ignores tenancy)"
check "$(CLAUDE_CONFIG_DIR="$L" TA allowed "$PR/acme-one")" 0 "allowed: the tenant's own login → exit 0"
check "$(CLAUDE_CONFIG_DIR="$F" TA allowed "$PR/acme-two")" 1 "allowed: another secondary → exit 1"
has "$T/out" "acme-two is off work: it is acme's" "…named as the tenant's"
check "$(CLAUDE_CONFIG_DIR="$F" TA allowed "$PR")" 1 "…while work's own deny list still holds ~/projects (it holds privy)"
echo l > "$REGATTA_CONFIG/lighthouse/cc-prefix"
cat > "$ACCOUNTS_FILE.t2" <<'J'
{"accounts": [{"label": "la", "provider": "claude", "home": "~/.claude-lab", "tenant": "acme"},
  {"label": "main", "provider": "claude", "home": "~/.claude", "primary": true}],
 "tenants": {"acme": {"repos": ["acme-one"]}}}
J
check "$(ACCOUNTS_FILE="$ACCOUNTS_FILE.t2" A allowed "$PR/acme-one")" 1 "a login the cc prefix reaches…"
has "$T/out" "or \`cc a\` in a Terminal" "…is named as its cc letter"
rm -f "$REGATTA_CONFIG/lighthouse/cc-prefix"
check "$(cd "$PR/acme-one" && TA run main --version)" 1 "run: the default dir in a tenant's repo is refused before claude starts"
has "$T/out" "account: acme-one is off main: it is acme's" "…with the same line"
check "$(cd "$PR/acme-one" && TA run work --version)" 1 "run: another secondary too"
has "$T/out" "account: acme-one is off work: it is acme's" "…refused by tenancy, not by a claude that failed to start"
mkdir -p "$PR/acme-nogit"
check "$(TA allowed "$PR/acme-nogit")" 1 "a glob entry matches by path where git has no answer (a folder in no repo)"
rm -f "$L/stub-usage" "$L/usage-probe.json"
check "$(TA pick --repo "$PR/acme-one" --json) $(field "['account']")" "0 lab" "the tenant login's limits unreadable → it runs there rather than nothing (no other row may)"
has "$T/out" "the tenant's own login runs it rather than nothing" "…saying so"
check "$(TA pick --repo "$PR/app" --json) $(field "['account']")" "0 work" "…while elsewhere an unreadable non-primary is skipped, as before"
use "$L" "10 10"; rm -f "$L/usage-probe.json"
echo '{"accounts": [{"label": "lab", "provider": "claude", "home": "~/.claude-lab", "tenant": "acme"},
  {"label": "spare", "provider": "claude", "home": "~/.claude-spare", "primary": true}],
 "tenants": {"acme": {"repos": ["acme-*"]}}}' > "$ACCOUNTS_FILE.t5"
check "$(ACCOUNTS_FILE="$ACCOUNTS_FILE.t5" A allowed "$PR/acme-one")" 1 "a registry with no row for the default dir: the default dir is still refused a tenant's repo"
has "$T/out" "acme-one is off this login (no row): it is acme's" "…named as no row's"
check "$(ACCOUNTS_FILE="$ACCOUNTS_FILE.t5" A allowed "$PR/app")" 0 "…and allowed elsewhere"
echo '{"accounts": [{"label": "main", "provider": "claude", "home": "~/.claude", "primary": true}], "tenants": {"acme": {"repos": "a*"}, "num": {"repos": 5}, "abs": {"repos": ["/x/*", "~/y"]}}}' > "$ACCOUNTS_FILE.t6"
check "$(ACCOUNTS_FILE="$ACCOUNTS_FILE.t6" A allowed "$PR/app")" 0 "a string repos is dropped, never split into letters (a* would route app)"
check "$(ACCOUNTS_FILE="$ACCOUNTS_FILE.t6" ACCOUNT_NOW=$WED A pick --repo "$PR/acme-one" --json) $(field "['account']")" "0 main" "…a number and absolute entries too: no crash, nothing routed"
echo '{"accounts": [{"label": "main", "provider": "claude", "home": "~/.claude", "primary": true}, {"label": "lab", "provider": "claude", "home": "~/.claude-lab", "tenant": "acme"}], "tenants": {"acme": {"repos": ["acme-*/"]}}}' > "$ACCOUNTS_FILE.t7"
check "$(ACCOUNTS_FILE="$ACCOUNTS_FILE.t7" A allowed "$PR/acme-one")" 1 "a glob with a trailing slash is the same glob: the default dir is refused (review 2026-10-21)"
sed 's#"acme-\*/"#"./acme-*"#' "$ACCOUNTS_FILE.t7" > "$ACCOUNTS_FILE.t8"
check "$(ACCOUNTS_FILE="$ACCOUNTS_FILE.t8" A allowed "$PR/acme-one")" 1 "…and one with a leading ./"
echo '{"accounts": [{"label": "main", "provider": "claude", "home": "~/.claude", "primary": true}, {"label": "lab", "provider": "claude", "home": "~/.claude-lab", "tenant": ["acme"]}], "tenants": {"acme": {"repos": ["acme-*"]}}}' > "$ACCOUNTS_FILE.t9"
check "$(ACCOUNTS_FILE="$ACCOUNTS_FILE.t9" ACCOUNT_NOW=$WED A pick --repo "$PR/app" --json >/dev/null; grep -c Traceback "$T/out")" "0" "a row whose tenant is a list is no tenant's: no traceback (review 2026-10-21)"
mkdir -p "$PR/notes[old]"
echo '{"accounts": [{"label": "main", "provider": "claude", "home": "~/.claude", "primary": true}, {"label": "work", "provider": "claude", "home": "~/.claude-work", "repos": {"deny": ["notes[old]"]}}]}' > "$ACCOUNTS_FILE.t10"
check "$(CLAUDE_CONFIG_DIR="$HOME/.claude-work" ACCOUNTS_FILE="$ACCOUNTS_FILE.t10" A allowed "$PR/notes[old]")" 1 "a literal deny entry holding [ still refuses its folder (review 2026-10-21)"
echo '{"accounts": [{"label": "main", "provider": "claude", "home": "~/.claude", "primary": true}], "tenants": {"acme": {"repos": ["acme-one"]}}}' > "$ACCOUNTS_FILE.t3"
check "$(ACCOUNTS_FILE="$ACCOUNTS_FILE.t3" ACCOUNT_NOW=$WED A pick --repo "$PR/acme-one" --json)" 3 "a tenant with no login: its repos run nowhere (exit 3), never on the primary"
has "$T/out" "acme-one is acme's: it runs on no login only (tenants)" "…saying so"

echo "tenants: the tenants file, its logins named there, is the whole of tenancy (2026-10-22)"
cat > "$ACCOUNTS_FILE.tf" <<'J'
{"accounts": [
  {"label": "work", "provider": "claude", "home": "~/.claude-work", "repos": {"deny": ["privy", "cv"]}},
  {"label": "lab", "provider": "claude", "home": "~/.claude-lab", "tenant": "beta"},
  {"label": "main", "provider": "claude", "home": "~/.claude", "primary": true}],
 "tenants": {"beta": {"repos": ["app"]}}}
J
echo '{"acme": {"repos": ["acme-*"], "logins": ["lab"]}, "bad": "not an object"}' > "$T/tenants.json"
TF() { TENANTS_FILE="$T/tenants.json" ACCOUNTS_FILE="$ACCOUNTS_FILE.tf" ACCOUNT_NOW=$WED A "$@"; }
check "$(TF pick --repo "$PR/acme-one" --json) $(field "['account']")" "0 lab" "pick --repo a tenant's repo → the login the file names"
check "$(TF allowed "$PR/acme-one")" 1 "allowed: the default dir in the file's tenant's repo → exit 1"
has "$T/out" "acme-one is off main: it is acme's, which runs on lab only (tenants.json) — open it in VS Code profile lab" "…naming the file"
check "$(TF allowed "$PR/app")" 0 "the registry's own tenants and row marks are ignored beside the file"
check "$(CLAUDE_CONFIG_DIR="$L" TF allowed "$PR/acme-one")" 0 "the file's login in its tenant's repo → exit 0"
echo '{"acme": {"repos": ["acme-one"]}}' > "$T/tenants-nologin.json"
check "$(TENANTS_FILE="$T/tenants-nologin.json" ACCOUNTS_FILE="$ACCOUNTS_FILE.tf" ACCOUNT_NOW=$WED A allowed "$PR/acme-one")" 1 "a file tenant with no logins: its repos run nowhere"
has "$T/out" "no enabled login is acme's in tenants-nologin.json" "…saying where to name one"
ln -s "$T/nowhere.json" "$T/tenants-gone.json"
check "$(TENANTS_FILE="$T/tenants-gone.json" ACCOUNTS_FILE="$ACCOUNTS_FILE.t" A allowed "$PR/acme-one")" 0 "a link that reads nothing: tenancy off, the registry's tenants not read instead"
has "$T/out" "unreadable" "…said on stderr"
check "$(CLAUDE_CONFIG_DIR="$F" TENANTS_FILE="$T/tenants-gone.json" ACCOUNTS_FILE="$ACCOUNTS_FILE.t" A allowed "$PR/privy")" 1 "…while deny lists keep working"
check "$(TENANTS_FILE="$T/tenants-gone.json" ACCOUNTS_FILE="$ACCOUNTS_FILE.tf" ACCOUNT_NOW=$WED A pick --repo "$PR/app" --json) $(field "['account']")" "0 work" "…and --json stays parseable with stderr merged in (dispatch reads it so; review 2026-10-22)"
cp "$T/tenants.json" "$T/tenants-drive.json"; ln -s "$T/tenants-drive.json" "$T/tenants-link.json"
check "$(CLAUDE_CONFIG_DIR="$F" TENANTS_FILE="$T/tenants-link.json" ACCOUNTS_FILE="$ACCOUNTS_FILE.tf" A allowed "$PR/acme-one")" 1 "a link that reads: a secondary is refused the tenant's repo…"
check "$(test -f "$T/.tenants-link.json.last" && echo kept)" "kept" "…and the good read is copied beside the link"
rm "$T/tenants-drive.json"
check "$(CLAUDE_CONFIG_DIR="$F" TENANTS_FILE="$T/tenants-link.json" ACCOUNTS_FILE="$ACCOUNTS_FILE.tf" A allowed "$PR/acme-one")" 1 "the link's drive away: the copy holds, the secondary still refused (never fail open; review 2026-10-22)"
has "$T/out" "acme-one is off work: it is acme's" "…named as the tenant's"
rm "$T/tenants-link.json"
check "$(CLAUDE_CONFIG_DIR="$F" TENANTS_FILE="$T/tenants-link.json" ACCOUNTS_FILE="$ACCOUNTS_FILE.tf" A allowed "$PR/acme-one")" 1 "the link removed (bootstrap.sh --config, its target away): the copy still holds (code review 2026-10-22)"
echo "the tenants file: its local copy first outside claude-host, the link under it, refresh (S4)"
mkdir -p "$T/tdrive"; cp "$T/tenants.json" "$T/tdrive/tenants.json"; ln -s "$T/tdrive/tenants.json" "$T/tenants-s4.json"
TS() { CLAUDE_CONFIG_DIR="$F" TENANTS_FILE="$T/tenants-s4.json" ACCOUNTS_FILE="$ACCOUNTS_FILE.tf" A "$@"; }
check "$(TS allowed "$PR/acme-one")" 1 "no copy yet: the link is read once to seed it (work refused acme's repo)"
check "$(test -f "$T/.tenants-s4.json.last" && echo kept)" "kept" "…the copy written"
echo '{"acme": {"repos": ["acme-*"], "logins": ["work"]}}' > "$T/tdrive/tenants.json"
check "$(TS allowed "$PR/acme-one")" 1 "the drive's file changed: outside claude-host the copy answers, the link unopened"
check "$(grep -c '"lab"' "$T/.tenants-s4.json.last")" 1 "…the copy as it was"
check "$(REGATTA_CLAUDE_HOST=1 TS allowed "$PR/acme-one")" 0 "under claude-host the link is read: acme is work's now"
check "$(grep -c '"work"' "$T/.tenants-s4.json.last")" 1 "…and the read refreshed the copy"
check "$(TS allowed "$PR/acme-one")" 0 "outside claude-host again: the refreshed copy answers"
echo '{"acme": {"repos": ["acme-*"], "logins": ["lab"]}}' > "$T/tdrive/tenants.json"
check "$(TS refresh)" 3 "refresh outside claude-host refuses, exit 3 (a tick without claude-host would prompt every 15 min)"
has "$T/out" "not under claude-host — the local copies stay as they are" "…saying so"
check "$(grep -c '"work"' "$T/.tenants-s4.json.last")" 1 "…the copy untouched"
check "$(TS refresh --force)" 0 "refresh --force reads the links anyway"
has "$T/out" "refresh: tenants-s4.json → .tenants-s4.json.last" "…naming the copy it wrote"
check "$(grep -c '"lab"' "$T/.tenants-s4.json.last")" 1 "…which now holds the drive's file"
echo '{"acme": {"repos": ["acme-*"], "logins": ["work"]}}' > "$T/tdrive/tenants.json"
check "$(REGATTA_CLAUDE_HOST=1 ACCOUNT_LOGINS="$T/logins-link.json" TS refresh)" 0 "refresh under claude-host (the usage tick): exit 0"
has "$T/out" "refresh: logins-link.json → .logins-link.json.last" "…the logins file's copy too"
check "$(grep -c '"work"' "$T/.tenants-s4.json.last")" 1 "…and the tenants copy follows the drive"
rm "$T/tdrive/tenants.json"
check "$(REGATTA_CLAUDE_HOST=1 TS refresh)" 1 "refresh with the drive away: exit 1…"
has "$T/out" "did not read" "…saying so"
has "$T/out" ".tenants-s4.json.last holds as it was" "…and the copy holds"
check "$(TS allowed "$PR/acme-one")" 0 "…which still answers (work's)"
sc() { TENANTS_FILE="$T/tenants-s4.json" ACCOUNTS_FILE="$ACCOUNTS_FILE.tf" ACCOUNT_LOGINS="$T/no-logins.json" python3 -c '
import sys
from importlib.machinery import SourceFileLoader
a = SourceFileLoader("acct_sc", sys.argv[1]).load_module()
for t in a.stale_copies(): print(t[1], t[2])' "$B/account" 2>&1; }
echo '{"acme": {"repos": ["acme-*"], "logins": ["lab"]}}' > "$T/tdrive/tenants.json"
check "$(sc)" "" "doctor: a copy that differs from the file but was refreshed within 30 min: nothing yet (the next tick takes it)"
python3 -c 'import os,sys,time; t=time.time()-2*3600; os.utime(sys.argv[1],(t,t))' "$T/.tenants-s4.json.last"
check "$(sc)" "fix the hooks read .tenants-s4.json.last, which differs from tenants-s4.json (last refreshed 2 h ago)" "…differing and 2 h old: a fix (the tick is not refreshing it through claude-host)"
cp "$T/tdrive/tenants.json" "$T/.tenants-s4.json.last"; python3 -c 'import os,sys,time; t=time.time()-2*3600; os.utime(sys.argv[1],(t,t))' "$T/.tenants-s4.json.last"
check "$(sc)" "" "…the same content however old: nothing (an unchanged file is never refreshed outside claude-host)"
rm "$T/.tenants-s4.json.last"
check "$(sc)" "fix no local copy of tenants-s4.json: the hooks open the link, which an ungranted app blocks on" "…no copy at all: a fix"
echo "a plain tenants file, or a link outside any drive, reads as it is outside claude-host (S4 finish review)"
printf '{"acme": {"repos": ["acme-*"], "logins": ["lab"]}}' > "$T/tenants-plain.json"
TP() { CLAUDE_CONFIG_DIR="$F" TENANTS_FILE="$T/tenants-plain.json" ACCOUNTS_FILE="$ACCOUNTS_FILE.tf" A "$@"; }
check "$(TP allowed "$PR/acme-one")" 1 "a plain file naming acme for lab: work refused"
echo '{}' > "$T/tenants-plain.json"
check "$(TP allowed "$PR/acme-one")" 0 "…the file edited to {} ends tenancy at once, the copy notwithstanding"
check "$(TP refresh)" 0 "refresh over a plain file needs no claude-host: exit 0, not 3"
printf '{"acme": {"repos": ["acme-*"], "logins": ["work"]}}' > "$T/.tenants-s4.json.last"
check "$(TS allowed "$PR/acme-one")" 0 "a link into the drive: the copy answers (work's)"
check "$(REGATTA_DRIVE_ROOTS="$T/elsewhere" TS allowed "$PR/acme-one")" 1 "a link outside every drive root reads the link itself (lab's now, work refused)"
check "$(CLAUDE_UNATTENDED=1 TS refresh --force)" 3 "refresh --force refuses an unattended caller (a person's yes; AGENTS.md Traps)"
has "$T/out" "this run is unattended" "…saying so"
ACCOUNT_LOGINS="$T/logins-link.json" python3 - "$B/account" "$T" > "$T/s4f.out" 2>&1 <<'PY2'
import json, os, sys
from importlib.machinery import SourceFileLoader
a = SourceFileLoader("acct_s4f", sys.argv[1]).load_module()
T = sys.argv[2]
last = os.path.join(T, ".logins-link.json.last")
os.remove(last)
a.load_logins(keep=False)
print("keep=False writes no copy:", not os.path.exists(last))
a.save_logins(a.logins_path(), {"lab": {"email": "q@example.com"}})
print("save_logins keeps the copy:", sorted(json.load(open(last))["logins"]))
PY2
check "$(cat "$T/s4f.out")" "keep=False writes no copy: True
save_logins keeps the copy: ['lab']" "doctor's read leaves the logins copy for stale_copies to judge; setup's write updates it"
mkdir -p "$T/cfg6/lighthouse"; printf '{"logins": {"work": {"email": "y@example.com"}}}' > "$T/cfg6/lighthouse/.logins.json.last"
check "$(env -u ACCOUNT_LOGINS REGATTA_CONFIG="$T/cfg6" python3 -c '
import sys
from importlib.machinery import SourceFileLoader
a = SourceFileLoader("acct_s6", sys.argv[1]).load_module()
print(a.load_logins(local=True)[1], a.load_logins()[1])' "$B/account" 2>&1)" "{'work': {'email': 'y@example.com'}} {}" \
  "the logins link removed (bootstrap.sh --config, the drive away): a hook's reader keeps its copy; a person's read has none"
echo '{"acme": {"repos": ["acme-*"], "logins": ["work"]}}' > "$T/tdrive/tenants.json"
printf '{"acme": {"repos": ["acme-*"], "logins": ["lab"]}}' > "$T/.tenants-s4.json.last"
check "$(TENANTS_FILE="$T/tenants-s4.json" python3 -c '
import sys
from importlib.machinery import SourceFileLoader
a = SourceFileLoader("acct_s8", sys.argv[1]).load_module()
hook = a.read_tenants_file()["acme"]["logins"]
a.READ_LINKS = True
print(hook, a.read_tenants_file()["acme"]["logins"], open(sys.argv[2]).read().count("lab"))' "$B/account" "$T/.tenants-s4.json.last" 2>&1)" "['lab'] ['work'] 1" \
  "doctor and setup read the link (work's), the hooks the copy (lab's), and doctor's read leaves the copy it judges"
rm "$T/ldrive/logins.json"
check "$(REGATTA_CLAUDE_HOST=1 ACCOUNT_LOGINS="$T/logins-link.json" TS refresh)" 1 "a dangling logins link (the drive away): refresh exits 1, as for the tenants file"
has "$T/out" "logins-link.json did not read" "…saying so"
cat > "$ACCOUNTS_FILE.tg" <<'J'
{"accounts": [
  {"label": "work", "provider": "claude", "home": "~/.claude-work", "tenant": "acme"},
  {"label": "lab", "provider": "claude", "home": "~/.claude-lab"},
  {"label": "main", "provider": "claude", "home": "~/.claude", "primary": true}]}
J
echo '{"acme": {"repos": ["acme-*"], "logins": "lab"}}' > "$T/tenants-str.json"
check "$(CLAUDE_CONFIG_DIR="$L" TENANTS_FILE="$T/tenants-str.json" ACCOUNTS_FILE="$ACCOUNTS_FILE.tg" A allowed "$PR/acme-one")" 0 "a string logins is one label: lab runs acme's repo"
check "$(CLAUDE_CONFIG_DIR="$F" TENANTS_FILE="$T/tenants-str.json" ACCOUNTS_FILE="$ACCOUNTS_FILE.tg" A allowed "$PR/acme-one")" 1 "a row the registry marks acme's but the file leaves out is refused it"
check "$(ACCOUNTS_FILE="$ACCOUNTS_FILE.tg" A allowed "$PR/app"; test -e "$ACCOUNTS_FILE.tg.tenants" || echo none)" "0
none" "a fixture registry reads its own tenants file, never the live key"
echo '{"acme": {"repos": ["acme-*"], "logins": ["lab"]}}' > "$REGATTA_CONFIG/lighthouse/tenants.json"
check "$(ACCOUNTS_FILE="$ACCOUNTS_FILE.tg" A allowed "$PR/acme-one")" 0 "…the live key written: a fixture still ignores it (review 2026-10-23: the old case passed with no live file)"
cp "$ACCOUNTS_FILE.tg" "$REGATTA_CONFIG/lighthouse/accounts.json"
check "$(ACCOUNTS_FILE="$REGATTA_CONFIG/lighthouse/accounts.json" A allowed "$PR/acme-one")" 1 "ACCOUNTS_FILE naming the live key (bootstrap.sh's account check) is no fixture: the live tenancy holds"
has "$T/out" "(tenants.json)" "…read from the live tenants file"
rm -f "$REGATTA_CONFIG/lighthouse/tenants.json" "$REGATTA_CONFIG/lighthouse/.tenants.json.last" "$REGATTA_CONFIG/lighthouse/accounts.json"
python3 - "$T/vsc-t" "$PR" <<'PY'
import json, sys
from pathlib import Path
v, pr = sys.argv[1], Path(sys.argv[2]).resolve()
(pr / "acme.code-workspace").write_text(json.dumps({"folders": [{"path": "acme-one"}, {"path": "overlay"}]}))
(pr / "plain.code-workspace").write_text(json.dumps({"folders": [{"path": "app"}]}))
json.dump({"userDataProfiles": [{"location": "pl", "name": "lab"}],
           "profileAssociations": {"workspaces": {(pr / "acme-one").as_uri(): "pl",
                                                  (pr / "acme.code-workspace").as_uri(): "__default__profile__"}}},
          open(v + "/globalStorage/storage.json", "w"))
PY
ties() { ACCOUNTS_FILE="${TIES_FILE:-$ACCOUNTS_FILE.t}" python3 -c '
import sys
from importlib.machinery import SourceFileLoader
a = SourceFileLoader("acct_t", sys.argv[1]).load_module()
for t in a.tenant_ties(a.load_registry()):
    print(t[1], t[2].replace(sys.argv[2], "PR"), "|", (t[3] if len(t) > 3 else "").replace(sys.argv[2], "PR"))' "$B/account" "$(cd "$PR" && pwd -P)"; }
ties > "$T/ties"
has "$T/ties" "fix PR/acme-one is acme's, and no VS Code profile runs its panel on lab's dir" "doctor: a profile named lab with no CLAUDE_CONFIG_DIR is no tie (code --profile makes such a bare one)"
has "$T/ties" "account vscode lab" "…the fix makes the profile first"
printf '{"claudeCode.environmentVariables": [{"name": "CLAUDE_CONFIG_DIR", "value": "%s"}]}\n' "$L" > "$T/vsc-t/profiles/pl/settings.json"
ties > "$T/ties"
has "$T/ties" "ok PR/acme-one opens on VS Code profile lab, acme's login" "doctor: a tenant folder tied to the tenant's profile is ok"
has "$T/ties" "fix PR/acme-two opens on VS Code profile default, which is refused acme's repos" "…an untied one opens on the default profile: a fix"
has "$T/ties" "--profile lab PR/acme-two" "…the fix ties it with code --profile"
has "$T/ties" "fix PR/acme.code-workspace opens on VS Code profile default" "…a workspace that opens a tenant folder, on the default profile: a fix"
check "$(grep -c plain.code-workspace "$T/ties")" 0 "…a workspace with no tenant folder is not listed"
mkdir -p "$PR/acme-zone"; git init -q "$PR/acme-zone/inner"
ties > "$T/ties"
has "$T/ties" "PR/acme-zone/inner opens on VS Code profile default" "doctor: a nested repo the glob takes (\`*\` spans /) is checked too (review 2026-10-21)"
rm -rf "$PR/acme-zone"
echo '{"accounts": [{"label": "far", "provider": "claude", "home": "~/.claude-far", "tenant": "beta"},
  {"label": "main", "provider": "claude", "home": "~/.claude", "primary": true}], "tenants": {"beta": {"repos": ["acme-two"]}}}' > "$ACCOUNTS_FILE.t11"
TIES_FILE="$ACCOUNTS_FILE.t11" ties > "$T/ties"
has "$T/ties" "info PR/acme-two is beta's, and no VS Code profile runs its panel on far's dir" "doctor: a tenant whose login has no dir on this Mac is info, not a fix (review 2026-10-21)"
rm -f "$PR/acme.code-workspace" "$PR/plain.code-workspace"
unset ACCOUNT_VSCODE_USER

echo "an Orca login with no login in its dir: on the other Mac, ssh -t from the laptop, not Orca's screen (2026-10-22)"
OG="$T/orca-p/acc g/home"; mkdir -p "$OG"
# ol <home> <peer alias or ""> <this host>: the line login_line gives an Orca row (the laptop is "lap")
ol() { REGATTA_LAPTOP=lap ACCOUNT_HOST="$3" ACCOUNT_CLAUDE="$T/claude" python3 -c '
import sys
from importlib.machinery import SourceFileLoader
a = SourceFileLoader("acct_o", sys.argv[1]).load_module()
row = {"label": "work2", "provider": "claude", "via": "orca", "home": a.Path(sys.argv[2])}
print(a.login_line(row, sys.argv[3] or None))' "$B/account" "$1" "$2" > "$T/out" 2>&1; }
ol "$OG" server-claude lap
has "$T/out" "\`ssh -t server-claude 'CLAUDE_CONFIG_DIR='\"'\"'$OG'\"'\"' $T/claude auth login'\` from the laptop" "the peer's form: ssh -t, the dir quoted, the binary spelled out"
has "$T/out" "then ssh server-claude '$B/account orca-sync'" "…its orca-sync wrapped for the peer, typed on the laptop too"
hasnt "$T/out" "Accounts screen, or" "…and not Orca's screen as the fix"
ol "$OG" "" box
has "$T/out" "\`CLAUDE_CONFIG_DIR='$OG' $T/claude auth login\` in an \`ssh -t\` session from the laptop" "on the other Mac itself (orca-sync, doctor --local): the local command, under ssh -t"
has "$T/out" "then $B/account orca-sync" "…its orca-sync local"
ol "$OG" "" lap
has "$T/out" "in again in Orca's Accounts screen, or \`orca account add" "on the laptop: Orca's screen, as before"
ol "$T/orca-p/unsynced/home" server-claude lap
has "$T/out" "in again in Orca's Accounts screen" "a dir Orca has not made (unsynced): Orca's screen, even for the peer"

echo "doctor: the tenants file's own state, and the two silent logins mistakes (2026-10-22)"
TN="$T/tn"; mkdir -p "$TN"
tstate() { TENANTS_FILE="$1" ACCOUNTS_FILE="${2:-$ACCOUNTS_FILE.tg}" python3 -c '
import sys
from importlib.machinery import SourceFileLoader
a = SourceFileLoader("acct_s", sys.argv[1]).load_module()
for t in a.tenancy_state(a.load_registry()):
    print(t[1], t[0], t[2].replace(sys.argv[2], "TN"), "|", t[3] if len(t) > 3 and t[3] else "")' "$B/account" "$TN" 2>>"$T/ts.err"; }
: > "$T/ts.err"
ln -s "$TN/away.json" "$TN/dead.json"
tstate "$TN/dead.json" > "$T/ts"
has "$T/ts" "fix - TN/dead.json reads nothing" "a link that reads nothing with no copy: a fix…"
has "$T/ts" "no last good copy — tenancy is off" "…saying tenancy is off"
has "$T/ts" "--config   (relinks it" "…the fix relinks it"
echo '{"acme": {"repos": ["acme-*"], "logins": ["lab"]}}' > "$TN/away2.json"; ln -s "$TN/away2.json" "$TN/held.json"
tstate "$TN/held.json" > "$T/ts"
check "$(cat "$T/ts")" "" "the link reads: nothing to say"
# python, not BSD date/stat: this suite runs on the public twin's ubuntu CI too (review 2026-10-23)
mtime() { python3 -c 'import os,sys; print(int(os.stat(sys.argv[1]).st_mtime))' "$1"; }
rm "$TN/away2.json"; python3 -c 'import os,sys,time; t=time.time()-3*3600; os.utime(sys.argv[1],(t,t))' "$TN/.held.json.last"
before=$(mtime "$TN/.held.json.last")
tstate "$TN/held.json" > "$T/ts"
has "$T/ts" "info - tenancy runs on the last good copy (.held.json.last, last read good 3 h old)" "the drive away, the copy holding: info naming its age"
check "$(mtime "$TN/.held.json.last")" "$before" "…and a failed read leaves the copy's mtime alone"
echo '{"acme": {"repos": ["acme-*"], "logins": ["lab"]},}' > "$TN/bad.json"
tstate "$TN/bad.json" > "$T/ts"
has "$T/ts" "fix - TN/bad.json does not parse" "a file that reads but does not parse: a fix…"
has "$T/ts" "| correct the JSON in " "…to correct the JSON, not to relink"
echo '{"acme": {"repos": "acme-*", "logins": ["lab"]}}' > "$TN/str.json"
tstate "$TN/str.json" > "$T/ts"
has "$T/ts" "fix - acme in str.json: its \"repos\" name nothing tenancy can match" "repos as a string: a fix, since every login may run its repos"
echo '{}' > "$TN/off.json"
tstate "$TN/off.json" > "$T/ts"
has "$T/ts" "info - tenancy is off: off.json is {}" "a file written {}: tenancy off, said as info"
echo '{"acme": {"repos": ["acme-*"], "logins": ["lab"]}, "beta": {"repos": ["app"], "logins": ["lab", "work"]}}' > "$TN/two.json"
tstate "$TN/two.json" > "$T/ts"
has "$T/ts" 'fix lab lab is in the "logins" of acme, beta in two.json: it is beta'"'"'s login only, and is refused acme'"'"'s repos' "a label in two tenants' logins: a fix naming the later as its owner"
has "$T/ts" "fix - acme's repos run nowhere: no enabled claude login is acme's" "…and the tenant it left with no login"
cat > "$ACCOUNTS_FILE.th" <<'J'
{"accounts": [
  {"label": "lab", "provider": "claude", "home": "~/.claude-lab"},
  {"label": "old", "provider": "claude", "home": "~/.claude-old", "enabled": false},
  {"label": "main", "provider": "claude", "home": "~/.claude", "primary": true}]}
J
echo '{"acme": {"repos": ["acme-*"], "logins": ["lba"]}, "beta": {"repos": ["app"], "logins": ["old", "lab"]}, "gamma": {"repos": ["g"], "logins": "old"}}' > "$TN/miss.json"
tstate "$TN/miss.json" "$ACCOUNTS_FILE.th" > "$T/ts"
has "$T/ts" 'info lba lba, in the "logins" of acme in miss.json, is no enabled login: no row in accounts.json has it |' "a logins label no row has: named…"
has "$T/ts" "| correct the label in " "…the fix corrects the label"
has "$T/ts" "fix - acme's repos run nowhere: no enabled claude login is acme's" "…and its tenant, left with none, a fix"
has "$T/ts" "info old old, in the \"logins\" of beta, gamma in miss.json, is no enabled login: its row is parked |" "a parked label: named"
has "$T/ts" "fix - gamma's repos run nowhere" "…a fix for the tenant it was the only login of"
check "$(grep -c "beta's repos run nowhere" "$T/ts")" 0 "…none for beta, which has lab"
TENANTS_FILE="$TN/miss.json" ACCOUNTS_FILE="$ACCOUNTS_FILE.th" A allowed "$PR/acme-one" >/dev/null
has "$T/out" "acme's \"logins\" in miss.json (lba) give it no enabled login" "the refusal names the listed label, never asks to add it again"
has "$T/out" "(account doctor names why)" "…and sends the reader to doctor"
echo '{"beta": {"repos": ["app"], "logins": ["old", "lab"]}}' > "$TN/park.json"
tstate "$TN/park.json" "$ACCOUNTS_FILE.th" > "$T/ts"
has "$T/ts" "info old old, in the \"logins\" of beta in park.json, is no enabled login: its row is parked |" "…info while the tenant has an enabled one (a parked row is info elsewhere too)"
check "$(TENANTS_FILE="$TN/dead.json" ACCOUNTS_FILE="$ACCOUNTS_FILE.f.on" ACCOUNT_LOGINS="$T/logins.json.d" ACCOUNT_HOST=laptop ACCOUNT_NOW=$WED A doctor --local)" 1 "doctor --local: the dead link, no copy → a problem, VS Code or not"
has "$T/out" "⚠   -: $TN/dead.json reads nothing" "…on the doctor's own lines"
check "$(TENANTS_FILE="$TN/dead.json" ACCOUNTS_FILE="$ACCOUNTS_FILE.f.on" ACCOUNT_LOGINS="$T/no-logins.json" ACCOUNT_HOST=laptop A doctor --local)" 1 "doctor with no logins file (the drive away)…"
has "$T/out" "$TN/dead.json reads nothing" "…still names the tenants link's state (review 2026-10-23)"
check "$(grep -c Traceback "$T/ts.err")" 0 "tenancy_state never raised in these cases"

echo
[ "$fails" -eq 0 ] && echo "all account tests pass" || { echo "$fails account test(s) FAILED"; exit 1; }
