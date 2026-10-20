#!/usr/bin/env bash
# Tests for bin/routine — fixture `RemoteTrigger get` responses in a scratch dir. No network.
#   bash modules/atlas/tests/routine.sh
set -u
B="$(cd "$(dirname "$0")/../bin" && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fails=0
check() { if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3: expected [$2] got [$1]"; fails=$((fails+1)); fi; }
has()   { if grep -qF -- "$2" "$1"; then echo "  ok   $3"; else echo "  FAIL $3: missing [$2]"; fails=$((fails+1)); fi; }

# live <file> <prompt>: a get response shaped like the real one (prompt in three places)
live() {
  python3 - "$1" "$2" <<'PY'
import json, sys
p = sys.argv[2]
t = {"id": "trig_X", "name": "Inbox pass — 7:30am PT", "cron_expression": "30 14 * * *",
     "derived_state": {"prompt": p},
     "job_config": {"ccr": {"events": [{"data": {"type": "control_request"}},
                                       {"data": {"message": {"content": p}}}],
                            "session_context": {"custom_system_prompt": "x" * 1000}}},
     "session_request": {"events": [{}, {"payload": {"message": {"content": p}}}]}}
open(sys.argv[1], "w").write("HTTP 200\n" + json.dumps({"trigger": t}, ensure_ascii=False))
PY
}
R() { "$B/routine" "$@" > "$T/out" 2>&1; echo $?; }
D="$T/inbox-pass.md"

echo "adopt"
live "$T/v1.json" $'Step one.\nStep (6): Drive → Projects → «usage».'
"$B/routine" adopt --live "$T/v1.json" > "$D"
has "$D" "id: trig_X" "header carries the id"
has "$D" "cron: 30 14 * * *" "…and the cron"
check "$(R status "$D" --live "$T/v1.json")" "0" "a fresh adopt is in sync"
check "$(python3 -c "import sys;print(open(sys.argv[1]).read().endswith('«usage».\n'))" "$D")" "True" "prompt kept verbatim, Cyrillic-safe quotes included"

echo "file ahead: a session edited the file"
sed -i.bak 's/Projects → «usage»/project_data → monthly-data\/reports/' "$D" && rm -f "$D.bak"   # -i.bak: BSD and GNU sed agree on it
check "$(R status "$D" --live "$T/v1.json")" "3" "exit 3"
has "$T/out" "file ahead: deploy it" "says deploy"
has "$T/out" "+Step (6): Drive → project_data → monthly-data/reports." "shows the diff"
check "$(R pull "$D" --live "$T/v1.json")" "3" "pull refuses to drop the file's change"
"$B/routine" body "$D" > "$T/body.json"
check "$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['prompt'].splitlines()[1])" "$T/body.json")" "Step (6): Drive → project_data → monthly-data/reports." "body is the file's prompt"
check "$(R synced "$D" --live "$T/v1.json")" "1" "synced refuses while live still differs"
has "$T/out" "did not land" "…and says the deploy did not land"
live "$T/v2.json" "$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['prompt'])" "$T/body.json")"
check "$(R synced "$D" --live "$T/v2.json")" "0" "after the deploy, synced records it"
check "$(R status "$D" --live "$T/v2.json")" "0" "…and status is in sync"

echo "live ahead: the routine edited itself"
live "$T/v3.json" $'Step one.\nStep (6): Drive → project_data → monthly-data/reports.\nStep (7): open the board.'
check "$(R status "$D" --live "$T/v3.json")" "4" "exit 4"
has "$T/out" "live ahead: pull it" "says pull"
check "$(R pull "$D" --live "$T/v3.json")" "0" "pull"
has "$D" "Step (7): open the board." "the file has the routine's own edit"
check "$(R status "$D" --live "$T/v3.json")" "0" "in sync after the pull"

echo "both changed"
live "$T/v4.json" $'Step one.\nStep (6): Drive → project_data → monthly-data/reports.\nStep (7): open the board and link it.'
printf '%s\n' 'Step (8): a session added this.' >> "$D"
check "$(R status "$D" --live "$T/v4.json")" "5" "exit 5"
check "$(R pull "$D" --live "$T/v4.json")" "5" "pull refuses without --force"
has "$T/out" "--force" "…and names the way out"

echo "guards"
live "$T/other.json" "x"; python3 - "$T/other.json" <<'PY'
import json, sys
p = sys.argv[1]; d = json.loads(open(p).read().split("\n", 1)[1]); d["trigger"]["id"] = "trig_Y"
open(p, "w").write(json.dumps(d))
PY
check "$(R status "$D" --live "$T/other.json")" "1" "a response for another routine is refused"
printf 'no header\n' > "$T/bad.md"
check "$(R status "$T/bad.md" --live "$T/v1.json")" "1" "a file without a header is refused"

echo
if [ "$fails" = 0 ]; then echo "all green"; else echo "$fails failing"; exit 1; fi
