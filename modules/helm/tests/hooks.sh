#!/usr/bin/env bash
# helm's two hooks, run as the overlay wires them (a JSON event on stdin): ask_guard.py — an
# unattended run's AskUserQuestion denied with the relay instruction, the queued relays printed at
# the next prompt, a banner for an orphan's ask — and talk_nudge.py, the Session-tab listener's
# line on a Talk host. Moved from the overlay's hooks/test_hooks.sh with B12 (its wiring cases
# stay there). Scratch paths only; no real banner, socket or spacesheep call.
#   bash modules/helm/tests/hooks.sh
set -u
for v in $(env | sed -n 's/^\(CLAUDE[A-Za-z0-9_]*\)=.*/\1/p; s/^\(DISPATCH[A-Za-z0-9_]*\)=.*/\1/p'); do unset "$v"; done
H="$(cd "$(dirname "$0")/../hooks" && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fails=0
check() { if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3: expected [$2] got [$1]"; fails=$((fails+1)); fi; }
export ASK_CACHE_DIR="$T/no-asks" ASK_SESSIONS_DIR="$T/no-sessions"
. "$(dirname "$0")/config_fixture.sh"; fixture_config "$T/config"   # the suite's own config dir, never the caller's
# the core's hooks/ dir, for host_name() below (lib/find_core.py: this checkout's core first)
CORE=$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import find_core; print(find_core.hooks())' "$H/../lib")

echo "ask_guard: an unattended run relays, never asks (session-asks R2, B4)"
AQ="$T/askq"; mkdir -p "$AQ"
deny=$(echo '{"tool_name":"AskUserQuestion","tool_input":{}}' | CLAUDE_UNATTENDED=dispatch DISPATCH_MANAGER=m1 python3 "$H/ask_guard.py" pretool)
check "$(echo "$deny" | python3 -c "import json,sys; d=json.load(sys.stdin)['hookSpecificOutput']; print(d['permissionDecision'], 'bin/ask relay' in d['permissionDecisionReason'], 'your skipper' in d['permissionDecisionReason'])")" "deny True True" "AskUserQuestion denied in a run, with the relay instruction"
# rename S5: the new name alone counts as the run's skipper too (a launchd plist from before S5 has only the old)
deny=$(echo '{"tool_name":"AskUserQuestion","tool_input":{}}' | env -u DISPATCH_MANAGER CLAUDE_UNATTENDED=dispatch DISPATCH_SKIPPER=m1 python3 "$H/ask_guard.py" pretool)
check "$(echo "$deny" | python3 -c "import json,sys; d=json.load(sys.stdin)['hookSpecificOutput']; print('your skipper (DISPATCH_SKIPPER)' in d['permissionDecisionReason'])")" "True" "  DISPATCH_SKIPPER alone: the deny names the run's own skipper"
check "$(echo '{"tool_name":"AskUserQuestion"}' | env -u CLAUDE_UNATTENDED python3 "$H/ask_guard.py" pretool)" "" "an attended session asks as before"
deny=$(echo '{"tool_name":"AskUserQuestion","tool_input":{}}' | CLAUDE_UNATTENDED=dispatch DISPATCH_SKIPPER=m1 DISPATCH_MODE=dnd PLANS_DIR="$T/noplans" python3 "$H/ask_guard.py" pretool)
case "$deny" in *"mode dnd: first run \`keel yolo --dnd <doc>\`"*) echo "  ok   mode dnd: the denial names keel yolo --dnd and relays only what it holds (skipper-modes S1)";; *) echo "  FAIL mode dnd's denial: $deny"; fails=$((fails+1));; esac
deny=$(echo '{"tool_name":"AskUserQuestion","tool_input":{}}' | CLAUDE_UNATTENDED=dispatch DISPATCH_SKIPPER=m1 DISPATCH_MODE=ask PLANS_DIR="$T/noplans" python3 "$H/ask_guard.py" pretool)
case "$deny" in *"mode ask: nobody answers it but the owner"*) echo "  ok   mode ask: the denial says nobody answers but the owner";; *) echo "  FAIL mode ask's denial: $deny"; fails=$((fails+1));; esac
# stray-manager B1 ii: no DISPATCH_MANAGER — the deny names this Mac's standing skipper when its record is live
AGM="$T/agm"; mkdir -p "$AGM/mgr" "$AGM/sess"
printf '{"session": "sm-1", "name": "manager · testmac", "pid": %d}' $$ > "$AGM/mgr/testmac.json"
printf '{"pid": %d, "sessionId": "sm-1", "updatedAt": 2}' $$ > "$AGM/sess/sm-1.json"
agr() { echo '{"tool_name":"AskUserQuestion","tool_input":{}}' | env -u DISPATCH_MANAGER -u DISPATCH_SKIPPER CLAUDE_UNATTENDED=dispatch ASK_SESSIONS_DIR="$AGM/sess" PLAN_HOST=testmac "$@" python3 "$H/ask_guard.py" pretool \
  | python3 -c "import json,sys; r=json.load(sys.stdin)['hookSpecificOutput']['permissionDecisionReason']; print('manager · testmac' in r, 'nobody (no skipper)' in r)"; }
check "$(agr ASK_MANAGER_DIR="$AGM/mgr")" "True False" "  no DISPATCH_MANAGER, a live standing skipper: the deny says the ask goes to it"
check "$(agr ASK_MANAGER_DIR="$AGM/none")" "False True" "  no record: 'nobody', as before"
# skipper-resilience S5: a run whose ship its scope leases, the scope's skipper record live — the deny names that skipper
mkdir -p "$AGM/plans/shp" "$AGM/plans/free"
for p in shp free; do printf '{"id": "%s", "tasks": {}}' "$p" > "$AGM/plans/$p/plan.json"; done
printf '{"holder": "yard", "scope": "dock", "host": "testmac", "account": null, "gen": 0, "since": 1, "until": null, "session": null, "pid": null, "why": "x"}' > "$AGM/plans/shp/skipper.json"
printf '{"session": "sk-1", "name": "skipper · dock", "scope": "dock", "pid": %d}' $$ > "$AGM/mgr/testmac-dock.json"
printf '{"pid": %d, "sessionId": "sk-1", "updatedAt": 2}' $$ > "$AGM/sess/sk-1.json"
ags() { echo '{"tool_name":"AskUserQuestion","tool_input":{}}' | env -u DISPATCH_MANAGER -u DISPATCH_SKIPPER -u DISPATCH_PLAN CLAUDE_UNATTENDED=dispatch ASK_SESSIONS_DIR="$AGM/sess" PLAN_HOST=testmac \
  ASK_MANAGER_DIR="$AGM/mgr" PLANS_DIR="$AGM/plans" "$@" python3 "$H/ask_guard.py" pretool \
  | python3 -c "import json,sys; r=json.load(sys.stdin)['hookSpecificOutput']['permissionDecisionReason']; print('scope\'s skipper (skipper · dock)' in r, 'manager · testmac' in r)"; }
check "$(ags DISPATCH_SHIP=shp)" "True False" "  a run whose ship the scope leases, its skipper live: the deny names skipper · <scope>"
check "$(ags DISPATCH_SHIP=free)" "False True" "  a ship with no lease: this Mac's standing skipper, as before"
check "$(ags DISPATCH_SHIP=shp SKIPPER_SCOPE=dock)" "False False" "  the skipper itself asking: no skipper named (its ask is the owner's)"
rm -f "$AGM/mgr/testmac-dock.json"
check "$(ags DISPATCH_SHIP=shp)" "False True" "  the scope's record gone: the standing one"
check "$(echo '{"tool_name":"Bash"}' | CLAUDE_UNATTENDED=dispatch python3 "$H/ask_guard.py" pretool)" "" "another tool: silent"
printf '{"t": 1, "text": "ASK tools D1 — the cadence"}\n' > "$AQ/mgr-7.jsonl"
out=$(echo '{"session_id":"mgr-7"}' | ASK_QUEUE_DIR="$AQ" python3 "$H/ask_guard.py" prompt)
check "$(echo "$out" | grep -c 'ASK tools D1')" "1" "a queued relay is printed at the skipper's next prompt"
check "$(echo '{"session_id":"mgr-7"}' | ASK_QUEUE_DIR="$AQ" python3 "$H/ask_guard.py" prompt)" "" "  once"
GQ="$T/askgit"; git init -q "$GQ"; mkdir -p "$GQ/.git/claude"
echo '{"verdict":"none","asks":[{"repo":"garden","item":"D2","title":"which light","verdict":"none"}]}' > "$GQ/.git/claude/ask.json"
printf '#!/bin/sh\necho "$@" >> %s/osa.calls\n' "$T" > "$T/osa"; chmod +x "$T/osa"
echo "{\"notification_type\":\"idle_prompt\",\"cwd\":\"$GQ\"}" | CLAUDE_UNATTENDED=dispatch SURFACES_HOST=laptop ASK_OSASCRIPT="$T/osa" python3 "$H/ask_guard.py" notify
check "$(grep -c 'garden D2 — which light' "$T/osa.calls" 2>/dev/null)" "1" "an orphan's ask raises a banner on the laptop (R6)"
echo "{\"notification_type\":\"idle_prompt\",\"cwd\":\"$GQ\"}" | CLAUDE_UNATTENDED=dispatch SURFACES_HOST=laptop ASK_OSASCRIPT="$T/osa" python3 "$H/ask_guard.py" notify
check "$(grep -c 'garden D2' "$T/osa.calls")" "1" "  once per ask"
echo '{"verdict":"none","asks":[{"repo":"garden","item":"D3","title":"x","verdict":"none"}]}' > "$GQ/.git/claude/ask.json"
echo "{\"notification_type\":\"idle_prompt\",\"cwd\":\"$GQ\"}" | CLAUDE_UNATTENDED=dispatch SURFACES_HOST=buildbox ASK_OSASCRIPT="$T/osa" python3 "$H/ask_guard.py" notify
check "$(grep -c 'garden D3' "$T/osa.calls")" "0" "  never on buildbox (D4)"
check "$(echo 'not json' | python3 "$H/ask_guard.py" pretool; echo "rc=$?")" "rc=0" "bad input: silent, exit 0"
echo "ask_guard prompt: every queued line, set aside before it is read (launch review, finding 11)"
python3 -c "
import json
with open('$AQ/mgr-8.jsonl', 'w') as f:
    for i in range(15):
        f.write(json.dumps({'t': 1, 'text': 'ASK tools D%d — item %d' % (i, i)}) + '\n')
    f.write('[1, 2]\n')
    f.write(json.dumps({'t': 1, 'text': 'x' * 700}) + '\n')
"
out=$(echo '{"session_id":"mgr-8"}' | ASK_QUEUE_DIR="$AQ" python3 "$H/ask_guard.py" prompt)
check "$(echo "$out" | grep -c '^- ..:.. ASK tools D')" "15" "all 15 relays printed, not the last 10"
check "$(echo "$out" | grep -c '1 line(s) in the queue were not JSON objects')" "1" "  a line that is no object is counted and said, never dropped silently"
check "$(echo "$out" | grep -c '100 more characters')" "1" "  a long line says how much of it is not shown, and where"
check "$(ls "$AQ" | grep -c '^mgr-8.jsonl$') $(ls "$AQ" | grep -c '^mgr-8.jsonl\..*\.seen$')" "0 1" "  the queue was renamed aside; a new relay starts a fresh file"
grep -q 'p.rename(seen)' "$H/ask_guard.py" && awk '/p.rename\(seen\)/{r=NR} /seen.read_text\(\)/{s=NR} END{exit !(r && s && r < s)}' "$H/ask_guard.py"
check "$?" "0" "  rename first, then read the renamed file (an append during the read is never lost)"
GP="$T/askpend"; git init -q "$GP"; mkdir -p "$GP/.git/claude" "$GP/sub"
# the payload in a single-quoted printf: bash 3.2 brace-expands a {…,…} written inside "$(…)" (AGENTS.md trap)
PAY=$(printf '{"session_id":"s","cwd":"%s"}' "$GP/sub")
check "$(printf '%s' "$PAY" | ASK_QUEUE_DIR="$AQ" python3 "$H/ask_guard.py" prompt)" "" "no pending answer: silent"
echo '{"rel": "docs/x.md", "item": "D1", "line": "A"}' > "$GP/.git/claude/pending-answers.jsonl"
check "$(printf '%s' "$PAY" | ASK_QUEUE_DIR="$AQ" python3 "$H/ask_guard.py" prompt | grep -c 'bin/ask apply')" "1" "a pending answer in this worktree is named, with bin/ask apply"
echo "talk_nudge.py: a Talk host's session is told to start its Session-tab listener"
TN() { (export SPACESHEEP_CONFIG_DIR="$T/tn/ss" SESSIONPIPE_CONFIG="$T/tn/sp/config.json" XDG_CONFIG_HOME="$T/tn/xdg" \
          SESSIONPIPE_SOCKET="${TN_SOCK-$T/tn/sp/control.sock}"; unset SPACESHEEP_KEY CLAUDE_UNATTENDED SESSIONPIPE_CONTROL_JOB CLAUDE_CODE_SESSION_ATTENDED
        unset CLAUDE_CODE_DISABLE_BACKGROUND_TASKS  # a dispatched run sets it, and the nudge then stays silent
        unset REGATTA_SHEEP_PLAN MEMO_SHEEP_BIN; export REGATTA_SHEEP_DIR="${TN_SHEEP-$T/tn/sheep}"  # the plan's cache: the suite's own
        if [ -n "${TN_PROJ+x}" ]; then export CLAUDE_PROJECT_DIR="$TN_PROJ"; else unset CLAUDE_PROJECT_DIR; fi
        if [ -n "${TN_UNATT-}" ]; then export CLAUDE_UNATTENDED=1; fi
        if [ -n "${TN_JOB-}" ]; then export SESSIONPIPE_CONTROL_JOB=1; fi
        if [ -n "${TN_ATT-}" ]; then export CLAUDE_CODE_SESSION_ATTENDED="$TN_ATT"; fi
        if [ -n "${TN_NOBG-}" ]; then export CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1; fi
        echo "$1" | python3 "$H/talk_nudge.py"); }
here=$(python3 -c "import sys; sys.path.insert(0, '$CORE'); from common import host_name; print(host_name())")
mkdir -p "$T/tn/ss" "$T/tn/sp"; echo '{"key":"ss_x","talk":true}' > "$T/tn/ss/config.json"
ev='{"session_id":"abc-123","source":"startup"}'
out=$(CLAUDE_TALK_HOSTS="$here" TN "$ev")
check "$(echo "$out" | grep -c 'spacesheep talk listen --session abc-123 --once')" "1" "  on a Talk host, signed in, talk on: the listen line, in the spelling ask_allow allows"
check "$(CLAUDE_TALK_HOSTS="nosuchhost" TN "$ev")" "" "  another Mac: silent"
mkdir -p "$T/tn/sheep-free" "$T/tn/sheep-stale"
echo "{\"cli\": true, \"pro\": false, \"talk\": false, \"plan\": \"free\", \"cap\": 400, \"at\": $(( $(date +%s) - 60 ))}" > "$T/tn/sheep-free/plan.json"
check "$(TN_SHEEP="$T/tn/sheep-free" CLAUDE_TALK_HOSTS="$here" TN "$ev")" "" "  the plan helm read a minute ago has no Talk (Free): silent"
echo "{\"cli\": true, \"pro\": false, \"talk\": false, \"plan\": \"free\", \"cap\": 400, \"at\": $(( $(date +%s) - 3700 ))}" > "$T/tn/sheep-stale/plan.json"
check "$(TN_SHEEP="$T/tn/sheep-stale" CLAUDE_TALK_HOSTS="$here" TN "$ev" | grep -c 'spacesheep talk listen')" "1" "  a Free cache past its hour reads as no cache (an upgrade since): the nudge as before"
check "$(CLAUDE_TALK_HOSTS="$here" TN '{"session_id":"abc-123","source":"compact"}')" "" "  after a compaction: silent (the listener still runs)"
check "$(CLAUDE_TALK_HOSTS="$here" TN '{"session_id":"a b"}')" "" "  a session id that is not one: silent"
echo '{"key":"ss_x"}' > "$T/tn/ss/config.json"
check "$(CLAUDE_TALK_HOSTS="$here" TN "$ev")" "" "  this machine never ran talk on: silent"
echo '{"talk":true}' > "$T/tn/ss/config.json"
check "$(CLAUDE_TALK_HOSTS="$here" TN "$ev")" "" "  not signed in: silent"
check "$(CLAUDE_TALK_HOSTS="$here" TN '{"session_id":"abc-123","source":"startup","cwd":"'"$HOME/projects/transcripts"'"}')" "" "  unpaired, a private session on a Talk host: silent (review 2026-10-14)"
# a listening socket stands in for the daemon: talk_nudge connects to it (a file alone is no daemon)
mkdir -p "$T/tn/work"
python3 -c 'import socket,sys,time; s=socket.socket(socket.AF_UNIX); s.bind(sys.argv[1]); s.listen(16); time.sleep(600)' "$T/tn/sp/control.sock" & TNPID=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do [ -S "$T/tn/sp/control.sock" ] && break; sleep 0.2; done
python3 -c 'import socket,sys; s=socket.socket(socket.AF_UNIX); s.bind(sys.argv[1])' "$T/tn/sp/stale.sock"   # bound, then the process is gone
echo '{"key":"ss_x","talk":true}' > "$T/tn/ss/config.json"; echo '{"receivers":[{"id":"r"}],"folders":["'"$T"'/tn/work"]}' > "$T/tn/sp/control.json"
evc='{"session_id":"abc-123","source":"startup","cwd":"'"$T"'/tn/work"}'
out=$(CLAUDE_TALK_HOSTS="$here" TN "$evc")
check "$(echo "$out" | grep -c 'sessionpipe wait --session claude-code:abc-123$')" "1" "  daemon paired: the waiter line, in the spelling ask_allow allows"
check "$(echo "$out" | grep -c 'talk listen')" "0" "  daemon paired: never the Talk link as well (two doors answer twice)"
check "$(CLAUDE_TALK_HOSTS="nosuchhost" TN "$evc" | grep -c 'sessionpipe wait')" "1" "  daemon paired: every Mac's sessions, not only the Talk hosts"
check "$(TN_JOB=1 CLAUDE_TALK_HOSTS="$here" TN "$evc")" "" "  a turn the daemon started: silent (it ends with its run)"
check "$(CLAUDE_TALK_HOSTS="$here" TN '{"session_id":"abc-123","source":"compact","cwd":"'"$T"'/tn/work"}')" "" "  daemon paired, after a compaction: silent"
for priv in "$HOME/projects/transcripts" "$HOME/projects/transcripts/x" "$HOME/projects/transcripts/tools" "$HOME/projects" "$HOME"; do
  check "$(CLAUDE_TALK_HOSTS="$here" TN '{"session_id":"abc-123","source":"startup","cwd":"'"$priv"'"}')" "" "  daemon paired, a private session ($priv): silent, never registers a waiter"
done
check "$(TN_PROJ="$HOME/projects/transcripts" CLAUDE_TALK_HOSTS="$here" TN "$evc")" "" "  daemon paired, a transcripts project dir: silent"
check "$(CLAUDE_TALK_HOSTS="$here" TN '{"session_id":"abc-123","source":"startup","cwd":"'"$HOME/Projects/Transcripts/x"'"}')" "" "  daemon paired, Transcripts in another case: silent (APFS is case-insensitive)"
check "$(TN_SOCK="$T/tn/sp/nosock" CLAUDE_TALK_HOSTS="$here" TN "$evc")" "" "  daemon paired but not running (no socket): silent"
check "$([ -S "$T/tn/sp/stale.sock" ] && echo file) $(TN_SOCK="$T/tn/sp/stale.sock" CLAUDE_TALK_HOSTS="$here" TN "$evc"; echo "rc=$?")" "file rc=0" \
  "  a socket file its daemon outlived (nothing listening): silent, exit 0 — connected to, not stat'ed"
check "$(CLAUDE_TALK_HOSTS="$here" TN '{"session_id":"abc-123","source":"startup","cwd":"'"$T"'"}')" "" "  daemon paired, a folder it does not serve: silent"
check "$(TN_UNATT=1 CLAUDE_TALK_HOSTS="$here" TN "$evc")" "" "  an unattended run: silent"
check "$(TN_NOBG=1 CLAUDE_TALK_HOSTS="$here" TN "$evc")" "" "  background tasks off (dispatch): silent"
check "$(TN_ATT=0 CLAUDE_TALK_HOSTS="$here" TN "$evc")" "" "  a claude -p run: silent"
check "$(CLAUDE_TALK_HOSTS="$here" TN '{"session_id":"abc\n","source":"startup","cwd":"'"$T"'/tn/work"}')" "" "  a session id with a trailing newline: silent"
echo '{"key":"ss_x","talk":false}' > "$T/tn/ss/config.json"
check "$(CLAUDE_TALK_HOSTS="$here" TN "$evc")" "" "  daemon paired but spacesheep talk off: silent"
echo '{"key":"ss_x","talk":true}' > "$T/tn/ss/config.json"
rm "$T/tn/sp/control.json"; echo '{}' > "$T/tn/ss/machine.json"
check "$(CLAUDE_TALK_HOSTS="$here" TN "$ev")" "" "  spacesheep's machine listener: silent"
rm -f "$T/tn/ss/machine.json"; echo 'not json' > "$T/tn/ss/config.json"
o=$(CLAUDE_TALK_HOSTS="$here" TN "$ev"; echo "rc=$?")
check "$o" "rc=0" "  a broken config: silent, exit 0"
kill "$TNPID" 2>/dev/null; wait "$TNPID" 2>/dev/null

echo; [ $fails -eq 0 ] && echo "hooks: all passed" || { echo "hooks: $fails FAILED"; exit 1; }
