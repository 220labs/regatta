#!/usr/bin/env bash
# Tests for bin/account — a scratch HOME with two config dirs, a fixture registry and a stub
# `claude` that answers the get_usage control request and `auth status` from per-dir fixtures and
# logs every probe. No network, no real login touched.
# Every name is made up: labels, hosts, repos. The config dir is a scratch one that plays an
# overlay (a `legacy` checkout holding wharf's worktree_allow.py and a bootstrap.sh stub), with the
# private values the core asks for there; the peers-absent cases point REGATTA_LEGACY at nothing.
#   bash modules/lighthouse/tests/account.sh
set -u
B="$(cd "$(dirname "$0")/../bin" && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fails=0
check() { if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3: expected [$2] got [$1]"; fails=$((fails+1)); fi; }
has()   { if grep -qF -- "$2" "$1"; then echo "  ok   $3"; else echo "  FAIL $3: missing [$2]"; sed 's/^/         | /' "$1" | head -20; fails=$((fails+1)); fi; }

unset REGATTA_HOME REGATTA_LEGACY
# account reads these (doctor's `blind`, orca-sync's VS Code step): a run over ssh, as dispatch's
# are, would otherwise fail seven cases (B9 review)
unset SSH_CONNECTION SSH_CLIENT SSH_TTY
export HOME="$T/home" TZ=America/Los_Angeles REGATTA_CONFIG="$T/config"
OV="$T/overlay"; mkdir -p "$REGATTA_CONFIG/regatta" "$REGATTA_CONFIG/lighthouse" "$REGATTA_CONFIG/wharf-runs" "$OV/hooks"
echo "$OV" > "$REGATTA_CONFIG/legacy"; : > "$OV/hooks/worktree_allow.py"; printf '#!/bin/sh
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

echo "peers absent: wharf's window and worktree hook, plumb's usage column (G16, G18)"
peer() { REGATTA_LEGACY="$1" python3 -c 'import sys, importlib.machinery as m, importlib.util as u
sp = u.spec_from_loader("acct", m.SourceFileLoader("acct", sys.argv[1])); a = u.module_from_spec(sp); sp.loader.exec_module(a)
print(a.worktree_allow_present(), a.attribution("main"))
a.open_in_terminal(["claude", "auth", "login"], {"CLAUDE_CONFIG_DIR": "/x"})' "${2:-$B/account}" 2>&1; }
# wharf is in this repo since B5, so the absent case runs from a copy of the core and lighthouse
# without it: hiding the legacy checkout alone finds wharf's real worktree_allow.py.
NW="$T/nowharf"; mkdir -p "$NW/modules" "$T/nothing"
cp -R "$B/../../regatta" "$NW/modules/regatta"; cp -R "$B/.." "$NW/modules/lighthouse"
check "$(peer "$T/nothing" "$NW/modules/lighthouse/bin/account" | tr '\n' '|')" "False None|  (wharf's fork_claude_session.py not installed: no window opened — run it yourself:) CLAUDE_CONFIG_DIR=/x claude auth login|" \
  "no wharf, no plumb: the worktree check skipped, no usage column, the window's command printed"
# From the same wharf-less copy: from this repo the core finds wharf's own worktree_allow.py
# before the overlay's, and wharf's open_in_terminal ran osascript on a Mac and exited on Linux.
check "$(peer "$OV" "$NW/modules/lighthouse/bin/account" | tr '\n' '|')" "True None|  (wharf's fork_claude_session.py not installed: no window opened — run it yourself:) CLAUDE_CONFIG_DIR=/x claude auth login|" \
  "  the overlay's worktree_allow.py found through the core"

echo
[ "$fails" -eq 0 ] && echo "all account tests pass" || { echo "$fails account test(s) FAILED"; exit 1; }
