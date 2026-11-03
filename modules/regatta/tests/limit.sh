#!/usr/bin/env bash
# `regatta limit` and the live layer it writes (live-limits, 2026-11-01): set, get and list on this host
# and a peer; the layer read in front of the config by every reader (the core's config_read, check's slots,
# dispatch's cap, headroom, berth, account's week ceiling); a value that outlives the overlay rewriting the
# config; a value the key's reader would refuse; a peer that cannot be reached; unset back to the config.
# Scratch HOME and config dirs; every host and login name made up (host-a, peer-b, peer-c, acct-x).
#   bash modules/regatta/tests/limit.sh
set -u
M="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$(cd "$M/../.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
for v in $(env | sed -n 's/^\(REGATTA[A-Za-z0-9_]*\)=.*/\1/p; s/^\(CLAUDE[A-Za-z0-9_]*\)=.*/\1/p; s/^\(DISPATCH_[A-Za-z0-9_]*\)=.*/\1/p'); do unset "$v"; done
unset CHECK_SLOTS CHECK_HOST HEADROOM_HOST ACCOUNT_HOST
export HOME="$T/home" REGATTA_CONFIG="$T/config" LIMIT_HOST=host-a
mkdir -p "$HOME" "$REGATTA_CONFIG/wharf-runs" "$T/peer-b/wharf-runs" "$T/peer-c"
C="$REGATTA_CONFIG"
L="$M/bin/regatta"
W="$ROOT/modules/wharf-runs"

# the ssh stand-in: alias-b runs the command on peer-b's config dir, any other alias is unreachable
cat > "$T/ssh" <<'EOF'
#!/bin/sh
while [ "$1" = -o ]; do shift 2; done
[ "$1" = -- ] && shift
alias="$1"; shift
case "$alias" in
  alias-b) REGATTA_CONFIG="$PEER_B" exec /bin/sh -c "$1" ;;
  *) echo "ssh: connect to host $alias port 22: Connection refused" >&2; exit 255 ;;
esac
EOF
chmod +x "$T/ssh"
export REGATTA_SSH="$T/ssh" PEER_B="$T/peer-b"
printf 'peer-b:alias-b\npeer-c:alias-c\n' > "$C/wharf-runs/ssh"

fails=0
rm_own() { local p; for p; do case "$p" in */..|*/../*|*//*) ;; "${T:?}"/?*) rm -rf -- "$p"; continue ;; esac; echo "rm_own: refused $p, outside $T" >&2; return 1; done; }
check() { if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3: expected [$2] got [$1]"; fails=$((fails+1)); fi; }
# what this host's readers read, each in a fresh process
cap() { DISPATCH_HOST="${1:-host-a}" "$W/bin/dispatch" --cap 2>/dev/null; }
slots() { CHECK_HOST="${1:-host-a}" "$W/bin/check" --slots 2>/dev/null; }
lines() { python3 -I -c "
import sys; sys.path.insert(0, '$M/hooks'); import common
print(' '.join(common.config_lines(sys.argv[1]) or []))" "$1"; }

echo "limit: the merge"
mrg() { python3 -I -c "
import sys, json; sys.path.insert(0, '$M/hooks'); import common
print(' '.join(common.live_merge(json.loads(sys.argv[1]), json.loads(sys.argv[2])) or []))" "$1" "$2"; }
check "$(mrg '["host-a:5"]' '["host-a:3","host-b:4","*:2"]')" "host-a:5 host-b:4 *:2" "a layer line for a host replaces the config's line for it, and stands first"
check "$(mrg '["HOST-A:5"]' '["host-a:3"]')" "HOST-A:5" "  words compare lower-case"
check "$(mrg '["2"]' '["1.5","log"]')" "2" "a plain layer line replaces every plain line"
check "$(mrg '["2"]' '["host-a:3","1.5"]')" "2 host-a:3" "  and keeps the config's host lines"
check "$(mrg '[]' '["1.5"]')" "1.5" "an empty layer is no layer"
check "$(mrg '["*:90"]' 'null')" "*:90" "a layer over no config file"

echo "limit: set and get on this host"
printf 'host-a:3\n' > "$C/wharf-runs/run-cap"
check "$(cap)" 3 "before: dispatch --cap reads the config's 3"
out=$("$L" limit set run-cap host-a:5 2>&1); rc=$?
check "$rc" 0 "set run-cap host-a:5"
check "$(cat "$C/live/wharf-runs/run-cap")" "host-a:5" "  the line is in this host's live layer"
check "$(cat "$C/wharf-runs/run-cap")" "host-a:3" "  and the config file is untouched"
check "$(cap)" 5 "  dispatch --cap reads 5 on its next call"
check "$("$L" limit get run-cap --on host-a | awk '{print $3, $4}')" "5 live" "  get: 5, from the live layer"
check "$(grep -c '"key": "wharf-runs/run-cap"' "$HOME/.local/state/regatta/limits.jsonl")" 1 "  a log row"

echo "limit: it outlives the overlay's --config"
# the overlay rewrites every key it holds, through a temporary file and a rename (bootstrap.sh's cmd_config)
printf 'host-a:3\n' > "$C/wharf-runs/run-cap.tmp" && mv -f "$C/wharf-runs/run-cap.tmp" "$C/wharf-runs/run-cap"
printf 'host-a:3\n*:2\n' > "$C/wharf-runs/check-slots"
check "$(cap)" 5 "a run-cap rewritten by --config: dispatch still reads 5"
"$L" limit set check-slots host-a:4 > /dev/null 2>&1
printf 'host-a:3\n*:2\n' > "$C/wharf-runs/check-slots"
check "$(slots)" 4 "check --slots reads the layer's 4 over the config's 3"
check "$(slots other-host)" 2 "  and another host still reads the config's *:2"
check "$(lines wharf-runs/check-slots)" "host-a:4 *:2" "  the core's config_lines merges the same"

echo "limit: the other readers"
printf 'host-a:avail=10,rate=40\n*:avail=15,rate=30\n' > "$C/wharf-runs/headroom"
"$L" limit set headroom host-a:avail=20,rate=30 > /dev/null 2>&1
check "$(HEADROOM_HOST=host-a "$W/bin/headroom" limits 2>/dev/null)" "avail=20,rate=30" "headroom reads the layer's line"
printf '1.5\nlog\n' > "$C/wharf-runs/load-max"
"$L" limit set load-max host-a:2 > /dev/null 2>&1
check "$("$W/bin/berth" --load-key wharf-runs/load-max)" 2 "berth's load key: the plain layer replaces 1.5 log"
check "$("$L" limit set week-max 'acct-x:95' 2>&1 | head -1)" "regatta limit: lighthouse/week-max is a login's: name the hosts it is set on (--on H[,H…] or --all)" \
  "a login's limit names its hosts"
"$L" limit set week-max 'acct-x:95' '*:88' --on host-a > /dev/null 2>&1
check "$("$ROOT/modules/lighthouse/bin/account" week-max acct-x 2>/dev/null)" "95 (lighthouse/week-max acct-x:)" "account's week ceiling: the login's own line"
check "$("$ROOT/modules/lighthouse/bin/account" week-max acct-other 2>/dev/null)" "88 (lighthouse/week-max *:)" "  else the * line"

echo "limit: a value the reader refuses"
before=$(cd "$C/live" && find . -type f -exec cat {} + | sort | tr '\n' ' ')
for bad in "run-cap host-a:0" "run-cap host-a:abc" "run-cap host-a:1000" "check-slots host-a:0" "check-slots host-a:x" \
           "headroom host-a:avail=x" "headroom host-a:free=10" "load-max host-a:fast" "check-slots host-a:00"; do
  out=$("$L" limit set $bad 2>&1); rc=$?
  check "$rc" 2 "refused: $bad"
  case "$out" in *"refused"*"nothing written"*) ;; *) echo "  FAIL   says so: $out"; fails=$((fails+1));; esac
done
out=$("$L" limit set week-max 'acct-x:150' --on host-a 2>&1); rc=$?
check "$rc" 2 "refused: week-max acct-x:150"
check "$(cd "$C/live" && find . -type f -exec cat {} + | sort | tr '\n' ' ')" "$before" "  no layer changed by any refusal"
out=$("$L" limit set run-cap host-a:4 host-a:zero 2>&1); rc=$?
check "$rc:$(cap)" "2:5" "one bad value refuses the whole set: the good one is not written either"
check "$("$L" limit set run-cap nohost:4 2>&1)" "regatta limit: no road to nohost: not this host, nor a peer regatta/fleet-ssh (else wharf-runs/ssh) names" \
  "a host with no road is refused, named"
check "$("$L" limit set run-cap 4 2>&1)" "regatta limit: wharf-runs/run-cap takes HOST:VALUE (or VALUE --all)" "a bare value needs --all"

echo "limit: a peer, and one that cannot be reached"
printf 'peer-b:3\n' > "$T/peer-b/wharf-runs/run-cap"
out=$("$L" limit set run-cap peer-b:6 2>&1); rc=$?
check "$rc" 0 "set run-cap peer-b:6 over ssh"
check "$(cat "$T/peer-b/live/wharf-runs/run-cap")" "peer-b:6" "  written in peer-b's own layer"
check "$(cat "$C/live/wharf-runs/run-cap")" "host-a:5" "  and this host's layer untouched"
check "$(REGATTA_CONFIG="$T/peer-b" DISPATCH_HOST=peer-b "$W/bin/dispatch" --cap 2>/dev/null)" 6 "  peer-b's dispatch --cap reads 6"
out=$("$L" limit set run-cap 4 --all 2>&1); rc=$?
check "$rc" 3 "set --all with peer-c unreachable: exit 3"
case "$out" in *"could not reach peer-c (alias-c)"*"unchanged"*) echo "  ok     names peer-c and says it is unchanged";;
  *) echo "  FAIL   names peer-c: $out"; fails=$((fails+1));; esac
check "$(cap):$(cat "$T/peer-b/live/wharf-runs/run-cap")" "4:peer-b:4" "  the hosts it reached have each their own line"
out=$("$L" limit get run-cap --all 2>&1); rc=$?
check "$rc" 3 "get --all with peer-c unreachable: exit 3"
check "$(printf '%s\n' "$out" | awk '$2=="peer-b"{print $3, $4} $2=="peer-c"{print $3, $4, $5, $6, $7}' | tr '\n' ';')" \
  "4 live;;? could not reach peer-c:;" "  each host's value and source; the unreachable one named"
check "$("$L" limit get check-slots --on peer-b | awk '{print $3, $4, $5}')" "2 default; not" "a peer with no line and no file: the default"
printf '*:3\n' > "$T/peer-b/wharf-runs/check-slots"
check "$("$L" limit get check-slots --on peer-b | awk '{print $3, $4, $5}')" "3 config (*:);" "  a * line serves it, said"

echo "limit: unset"
"$L" limit unset run-cap host-a > /dev/null 2>&1
check "$(cap):$([ -e "$C/live/wharf-runs/run-cap" ] && echo there || echo gone)" "3:gone" "unset run-cap host-a: back to the config's 3"
"$L" limit unset week-max acct-x --on host-a > /dev/null 2>&1
check "$(cat "$C/live/lighthouse/week-max")" "*:88" "unset of a login keeps the other logins' lines"
"$L" limit unset load-max host-a > /dev/null 2>&1
check "$("$W/bin/berth" --load-key wharf-runs/load-max)" "1.5 log" "unset load-max: the config's 1.5 log again"

echo "limit: the review's cases (round 1)"
mkdir -p "$C/live/regatta" "$C/regatta"; printf 'repo-x\n' > "$C/regatta/orca-deny"; printf 'nothing\n' > "$C/live/regatta/orca-deny"
check "$(lines regatta/orca-deny)" "repo-x" "a file under live/ for a key no module's limits declares is read by nobody"
rm_own "$C/live/regatta"
printf 'host-a:\xff\n' > "$C/wharf-runs/headroom"
check "$(python3 -I -c "
import sys; sys.path.insert(0, '$M/hooks'); import common
print(common.config_read('wharf-runs/headroom'))")" "(['host-a:avail=20,rate=30'], 'not UTF-8')" "an unreadable config under a live line: the lines, and the config's trouble still said"
check "$(HEADROOM_HOST=host-a "$W/bin/headroom" limits > /dev/null 2>&1; echo $?)" 2 "  so headroom still reads no limits there, as before the layer"
printf 'host-a:avail=10,rate=40\n' > "$C/wharf-runs/headroom"
for bad in "headroom host-a:avail=nan" "headroom host-a:rate=inf" "headroom host-a:avail=-5" "load-max host-a:nan" "headroom host-a:,"; do
  "$L" limit set $bad > /dev/null 2>&1; check "$?" 2 "refused: $bad (a rule nan, inf or negative would be off unsaid)"
done
out=$(DISPATCH_MAX_RUNS=7 "$L" limit set run-cap host-a:6 2>&1); rc=$?
check "$rc" 3 "set under DISPATCH_MAX_RUNS: written, but exit 3"
case "$out" in *"its reader reads 7, not 6"*) echo "  ok     naming what the reader reads";; *) echo "  FAIL   names the override: $out"; fails=$((fails+1));; esac
"$L" limit unset run-cap host-a > /dev/null 2>&1
check "$("$L" limit unset run-cap host-a 2>&1 | head -1)" "regatta limit: wharf-runs/run-cap on host-a has no live line for host-a to unset" "an unset with nothing there says so"
printf 'host-a:0\n' > "$C/wharf-runs/run-cap"
check "$("$L" limit get run-cap --on host-a | awk '{print $3, $4, $5, $6, $7, $8}')" "3 config; its reader reads 3" "get on this host: what its reader reads, not a line it ignores"
printf 'host-a:3\n' > "$C/wharf-runs/run-cap"
printf 'host-a:7' > "$C/live/wharf-runs/check-slots"
check "$(slots)" 7 "check reads a live line with no newline at its end, alone"
printf 'host-a:4\n' > "$C/live/wharf-runs/check-slots"
mkdir -p "$C/lighthouse"; printf 'host-a\npeer-b\nhost-z\n' > "$C/lighthouse/hosts"
check "$("$L" limit get load-margin --all 2>&1 >/dev/null | head -1)" "regatta limit: --all is host-a, peer-b, peer-c; no road to host-z (regatta/fleet-ssh names none)" \
  "--all names the hosts it reaches, and each known host with no road"
rm_own "$C/lighthouse/hosts"
cat > "$T/ceil.py" <<'EOF'
import importlib.machinery, importlib.util, sys
l = importlib.machinery.SourceFileLoader("acct_lim", sys.argv[1]); m = importlib.util.module_from_spec(importlib.util.spec_from_loader("acct_lim", l)); l.exec_module(m)
rows = [{"label": "acct-x", "rules": {"week_max": 50}}, {"label": "acct-y", "rules": {"week_max": 50}}, {"label": "acct-z", "rules": {}}]
print(" ".join("%s=%s" % (a["label"], m.ceiling(a, None, 0)[0]) for a in rows))
EOF
"$L" limit set week-max acct-x:60 '*:95' --on host-a > /dev/null 2>&1
check "$(python3 "$T/ceil.py" "$ROOT/modules/lighthouse/bin/account" 2>&1)" "acct-x=60 acct-y=50 acct-z=95" \
  "the week ceiling: a login's own live line stands; * only over a row that sets none"

echo "limit: the review's cases (round 2)"
check "$(REGATTA_UNATTENDED=dispatch "$L" limit set run-cap host-a:4 2>&1; echo "rc=$?")" \
  "regatta limit: set writes a host's live limits — refused under REGATTA_UNATTENDED=dispatch; the owner's session runs it
rc=2" "an unattended caller may not set"
check "$(CLAUDE_UNATTENDED=1 "$L" limit unset check-slots host-a > /dev/null 2>&1; echo $?):$(cat "$C/live/wharf-runs/check-slots")" "2:host-a:4" \
  "  nor unset (the old marker too), and nothing is written"
check "$(REGATTA_UNATTENDED=dispatch "$L" limit get check-slots --on host-a | awk '{print $3}')" 4 "  get still reads"
printf '1.5\nlog\n' > "$C/wharf-runs/load-max"
check "$("$L" limit set load-max host-a:2 2>&1 >/dev/null | head -1)" "regatta limit: wharf-runs/load-max on host-a: 2 stands over the config's 1.5 log, whole" \
  "a set says what config value it stands over, whole (log is not kept)"
"$L" limit unset load-max host-a > /dev/null 2>&1
check "$("$L" limit set week-max '*:90' --on host-a 2>&1 >/dev/null | grep -c 'serves only a login whose registry row sets no week ceiling')" 1 \
  "a * week line says whom it serves"
printf 'host-a:6\n' > "$C/wharf-runs/run-cap"
check "$("$L" limit set run-cap 6 --all 2>&1 >/dev/null | grep -c 'no road to')" 0 "--all: no roadless note while every host the key names has a road"
printf 'host-a:6\nhost-q:4\n' > "$C/wharf-runs/run-cap"
check "$("$L" limit get run-cap --all 2>&1 >/dev/null | head -1)" "regatta limit: --all is host-a, peer-b, peer-c" "  get names no road (it reads; the key's hosts are a set's)"
check "$("$L" limit set run-cap 6 --all 2>&1 >/dev/null | head -1)" "regatta limit: --all is host-a, peer-b, peer-c; no road to host-q (regatta/fleet-ssh names none)" \
  "  a set names a host the key's config names that has no road"
printf 'host-a:3\n' > "$C/wharf-runs/run-cap"; "$L" limit unset run-cap --all > /dev/null 2>&1
mkdir -p "$C/live/regatta"; printf 'nothing\n' > "$C/live/regatta/orca-deny"
check "$("$L" check 2>/dev/null | grep -c 'live/regatta/orca-deny: read by nobody')" 1 "regatta check: an undeclared live file is read by nobody, said"
rm_own "$C/live/regatta"
check "$(CHECK_HOST=host_a "$W/bin/check" --slots 2>/dev/null)" 2 "check takes CHECK_HOST as given (the stand-in)"

echo "limit: the review's cases (round 3)"
check "$(mrg '["host-a:5"]' '["host-a:3 host-b:6","*:2"]')" "host-a:5 host-b:6 *:2" "a config line holding two hosts keeps the other one's value"
check "$(mrg '["host-a:avail=5"]' '["host-a: avail=15,rate=30","*:avail=12"]')" "host-a:avail=5 *:avail=12" "  a spaced entry goes whole, value and all (round 4)"
check "$(mrg '["host-a:avail=5"]' '["host-a:avail=15, rate=30"]')" "host-a:avail=5" "  and one spaced after a comma"
check "$(mrg '["host-a:5"]' '["host-a: 3 host-b: 6"]')" "host-a:5 host-b: 6" "  the next word's entry stays"
check "$(mrg '["host-a:5"]' '["host-a:3 # was 4"]')" "host-a:5" "  a note alone is no line"
check "$(mrg '["host-a:7"]' '["host-a:","5","host-c:","4"]')" "host-a:7 host-c: 4" "  an entry split one word per line goes whole (round 5)"
check "$(mrg '["2"]' '["host-a:3","1.5"]')" "2 host-a:3" "  a plain layer still judges each line alone"
printf 'host-a:avail=15, rate=30\n*:avail=12\n' > "$C/wharf-runs/headroom"; mkdir -p "$C/live/wharf-runs"; printf 'host-a:avail=20\n' > "$C/live/wharf-runs/headroom"
check "$(HEADROOM_HOST=host-a "$W/bin/headroom" limits 2>/dev/null; HEADROOM_HOST=host-b "$W/bin/headroom" limits 2>/dev/null)" "avail=20
avail=12" "  so headroom reads the layer here and the * line elsewhere"
rm_own "$C/live/wharf-runs/headroom"
printf 'host-a:3 host-b:6\n' > "$C/wharf-runs/run-cap"
check "$(LIMIT_HOST=host-b "$L" limit set run-cap host-b:7 2>&1 >/dev/null | head -1)" "regatta limit: wharf-runs/run-cap on host-b: host-b:7 stands over the config's host-b:6, whole" \
  "  a set names the entry it stands over on a line of two"
check "$(LIMIT_HOST=host-b "$L" limit get run-cap --on host-b | awk '{print $3, $4}')" "7 live" "  and get reads it"
LIMIT_HOST=host-b "$L" limit unset run-cap host-b > /dev/null 2>&1
check "$(LIMIT_HOST=host-b "$L" limit get run-cap --on host-b | awk '{print $3, $4}')" "6 config" "  back to the config's entry on that line"
check "$("$L" check 2>/dev/null | grep -c 'live/.lock')" 0 "regatta check never lists the lock file"
printf 'host-a:5\n' > "$C/wharf-runs/run-cap"
check "$("$L" limit set run-cap host-a:5 2>&1 >/dev/null | grep -c 'stands over')" 0 "a set of the config's own value says nothing over it (round 5)"
"$L" limit unset run-cap host-a > /dev/null 2>&1; printf 'host-a:3\n' > "$C/wharf-runs/run-cap"
printf 'host-a:3 host-b:6\n' > "$C/wharf-runs/run-cap"; mkdir -p "$C/live/wharf-runs"; printf 'host-a:5\n' > "$C/live/wharf-runs/run-cap"
check "$(cap host-b)" 6 "  so host-b's dispatch still reads 6"
rm_own "$C/live/wharf-runs/run-cap"; printf 'host-a:3\n' > "$C/wharf-runs/run-cap"
printf '*:avail=15,rate=30\n' > "$C/wharf-runs/headroom"; rm_own "$C/live/wharf-runs/headroom"
check "$("$L" limit set headroom host-a:avail=20 2>&1 >/dev/null | head -1)" "regatta limit: wharf-runs/headroom on host-a: host-a:avail=20 stands over the config's *:avail=15,rate=30, whole" \
  "a host on the * line is told what it stands over"
rm_own "$C/live/wharf-runs/headroom"

echo "limit: the review's cases (the laptop run's round 1)"
out=$("$L" limit set run-cap host-a:03 2>&1); rc=$?
check "$rc:$(printf '%s\n' "$out" | grep -c 'only by its default')" "2:1" "a cap its reader meets with its default (03) is refused"
"$L" limit set headroom host-a:rate=50,avail=20 > /dev/null 2>&1; rc=$?
check "$rc:$(cat "$C/live/wharf-runs/headroom" 2>/dev/null)" "0:host-a:rate=50,avail=20" "  a headroom value in another order is no default: set (round 2)"
rm_own "$C/live/wharf-runs/headroom"
printf 'host-a :avail=20\n' > "$C/wharf-runs/headroom"; mkdir -p "$C/live/wharf-runs"; printf 'host-a:avail=5\n' > "$C/live/wharf-runs/headroom"
check "$(HEADROOM_HOST=host-a "$W/bin/headroom" limits 2>/dev/null)" "avail=5" "headroom: the layer's line wins over a config line the merge could not take out"
rm_own "$C/live/wharf-runs/headroom"; rm -f "$C/wharf-runs/headroom"
mkdir -p "$C/live/lighthouse"; printf 'acct-y:\n80\n' > "$C/live/lighthouse/week-max"
check "$("$ROOT/modules/lighthouse/bin/account" week-max acct-y 2>/dev/null)" "80 (lighthouse/week-max acct-y:)" "account's week ceiling reads an entry split one word per line"
rm_own "$C/live/lighthouse/week-max"
printf 'acct-y:\n70\n#\nwas\n4\n' > "$C/lighthouse/week-max"; printf 'acct-y:80\n' > "$C/live/lighthouse/week-max"
check "$("$ROOT/modules/lighthouse/bin/account" week-max acct-y 2>/dev/null | awk '{print $1}')" "80" "a config entry split one word per line with a note: the note's words go with the dropped entry (the landing review)"
rm_own "$C/live/lighthouse/week-max"; rm -f "$C/lighthouse/week-max"
printf 'host-b:abc\n' > "$C/wharf-runs/check-slots"
out=$(LIMIT_HOST=host-b "$L" limit get check-slots --on host-b 2>/dev/null); rc=$?
check "$rc:$(printf '%s\n' "$out" | grep -c 'refuses')" "3:1" "get shows a reader that refuses the config as refused (exit 3)"
printf 'host-a:3\n*:2\n' > "$C/wharf-runs/check-slots"
printf 'peer-b:3\n' > "$T/peer-b/wharf-runs/run-cap"; rm_own "$T/peer-b/live"
out=$("$L" limit set run-cap peer-b:7 2>&1); rc=$?
check "$rc:$(printf '%s\n' "$out" | grep -c 'no regatta checkout there')" "0:1" "a peer with no regatta home: written, and said it was not read back"
printf '%s\n' "$ROOT" > "$T/peer-b/home"
out=$("$L" limit set run-cap peer-b:8 2>&1); rc=$?
check "$rc:$(printf '%s\n' "$out" | grep -c 'written, but')" "0:0" "a peer's own reader reads the value back through its home file"
check "$("$L" limit get run-cap --on peer-b | awk '{print $3, $4}')" "8 live" "  and get shows it"
mkdir -p "$T/old/modules/wharf-runs/bin"; printf '#!/bin/sh\necho 3\n' > "$T/old/modules/wharf-runs/bin/dispatch"; chmod +x "$T/old/modules/wharf-runs/bin/dispatch"
printf '%s\n' "$T/old" > "$T/peer-b/home"
out=$("$L" limit set run-cap peer-b:9 2>&1); rc=$?
check "$rc:$(printf '%s\n' "$out" | grep -c 'predates the live layer')" "3:1" "a peer whose checkout has no limits file predates the layer: written, said, exit 3 (round 2)"
out=$("$L" limit get run-cap --on peer-b 2>/dev/null); rc=$?
check "$rc:$(printf '%s\n' "$out" | grep -c 'predates the live layer')" "0:1" "  get says it, and is no failure"
check "$("$L" limit get run-cap --on peer-b 2>/dev/null | awk '{print $3}')" "3" "  and its value column is the config's, which that host reads (the landing review)"
cp "$W/limits" "$T/old/modules/wharf-runs/limits"
out=$("$L" limit set run-cap peer-b:9 2>&1); rc=$?
check "$rc:$(printf '%s\n' "$out" | grep -c 'its reader reads 3, not 9')" "3:1" "a peer whose reader reads another value: written, but its reader reads 3 (exit 3)"
check "$("$L" limit get run-cap --on peer-b | awk '{print $3}')" "3" "  and get shows what that reader reads"
printf '#!/bin/sh\nexit 1\n' > "$T/old/modules/wharf-runs/bin/dispatch"
out=$("$L" limit get run-cap --on peer-b 2>/dev/null); rc=$?
check "$rc:$(printf '%s\n' "$out" | grep -c 'could not tell (exit 1)'):$(printf '%s\n' "$out" | grep -c 'refuses')" "3:1:0" "a reader that crashes (exit 1) could not tell; it is no refusal (the landing review)"
rm -f "$T/peer-b/home"
check "$("$L" limit get run-cap --on peer-b | grep -c 'not read back (no regatta checkout there)')" 1 "  get says a peer with no checkout was not read back"
rm -f "$T/peer-b/home"; rm_own "$T/peer-b/live" "$T/old"

echo "limit: regatta check names the live layer"
check "$("$L" check 2>/dev/null | grep -c 'live/wharf-runs/check-slots: host-a:4 (regatta limit')" 1 "a note per live key"

echo
[ "$fails" = 0 ] && echo "limit: all passed" || echo "limit: $fails failed"
[ "$fails" = 0 ]
