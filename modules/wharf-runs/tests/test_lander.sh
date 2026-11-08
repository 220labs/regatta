#!/usr/bin/env bash
# Tests for autofinish-run's lander (stuck-ships S1, docs/stuck-ships-2026-10-31.md): the roads `--by lander --road`
# and their refusals, the caps in lander.json, the mode flag, the resets, and the `lander` verbs. A scratch HOME,
# config dir and state dir, a scratch repo under the scratch projects folder with a bare origin; GitHub, the account
# tool, keel and dispatch's verdict are stood in for (lander_cases.py). No launchd or BSD tool; Linux eligibility
# waits for a recorded pass there (AGENTS.md), so this suite stays off check.sh's LINUX_OK list.
#   bash modules/wharf-runs/tests/test_lander.sh
set -u
# a dispatched run's markers would change what is tested (AGENTS.md's attended-behaviour trap): the fixed names,
# then every DISPATCH_*, RUN_SEED_*, SKIPPER_*, HELM_*, AUTOFINISH_* by pattern
unset CLAUDE_UNATTENDED REGATTA_UNATTENDED CLAUDE_CODE_DISABLE_BACKGROUND_TASKS CLAUDE_CODE_SESSION_ID CLAUDE_REPOS_JSON \
      CLAUDE_CODE_OAUTH_TOKEN ACCOUNTS_FILE SURFACES_HOST PLAN_HOST REGATTA_LAPTOP
for v in $(env | sed -nE 's/^((DISPATCH|RUN_SEED|SKIPPER|HELM|AUTOFINISH)_[A-Za-z0-9_]*)=.*/\1/p'); do unset "$v"; done
D="$(cd "$(dirname "$0")" && pwd)"
B="$(cd "$D/../bin" && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fails=0
check() { if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3: expected [$2] got [$1]"; fails=$((fails+1)); fi; }
has()   { if grep -qF -- "$2" "$1" 2>/dev/null; then echo "  ok   $3"; else echo "  FAIL $3: missing [$2]"; sed 's/^/         | /' "$1" 2>/dev/null | tail -8; fails=$((fails+1)); fi; }
. "$D/config_fixture.sh"; fixture_config "$T/config"
export HOME="$T/home"; mkdir -p "$HOME/projects"
export AUTOFINISH_STATE_DIR="$T/state" AUTOFINISH_DAY="$(date +%Y-%m-%d)" ACCOUNTS_FILE="$T/no-accounts.json"
# the moved HOME drops the runner's git identity (AGENTS.md's Linux trap): the suite's own
printf '[user]\n\tname = t\n\temail = t@t\n[init]\n\tdefaultBranch = main\n' > "$T/gitconfig"
export GIT_CONFIG_GLOBAL="$T/gitconfig"

git init -q --bare "$T/origin.git"
R="$HOME/projects/repo"; git init -q -b main "$R"
printf -- '- check: `true`\n' > "$R/AGENTS.md"
git -C "$R" add AGENTS.md; git -C "$R" commit -qm init
git -C "$R" remote add origin https://github.com/test/repo.git
git -C "$R" config url."$T/origin.git".insteadOf https://github.com/test/repo.git
BR=claude/laptop/2026-10-31-lander
W="$R/.claude/worktrees/lander"
git -C "$R" worktree add -q -b $BR "$W" main
echo work > "$W/f"; git -C "$W" add f; git -C "$W" commit -qm "the work"
# published without a push verb in this file's text (the checkpoint hook reads command text)
git -C "$R" send-pack "$T/origin.git" "$BR:refs/heads/$BR" "main:refs/heads/main" >/dev/null 2>&1
git -C "$R" update-ref refs/remotes/origin/main main

echo "== the roads, the caps, the mode flag (lander_cases.py)"
python3 "$D/lander_cases.py" "$B" "$W" "$R" "$T"; check "$?" "0" "every lander case above passed"

echo "== the command line"
AFR="$B/autofinish-run"
"$AFR" "$W" --by lander --dry > "$T/out" 2>&1; check "$?" "2" "a lander start without --road: refused (exit 2)"
has "$T/out" "--by lander names its road" "  saying so"
"$AFR" "$W" --by sweep --road login --dry > "$T/out" 2>&1; check "$?" "2" "--road without --by lander: exit 2"
"$AFR" "$W" --by lander --road login --merge --dry > "$T/out" 2>&1; check "$?" "2" "--merge on a lander start: exit 2 (no person's yes)"
has "$T/out" "--merge needs a person's yes" "  saying why"
"$AFR" "$W" --by lander --road bogus --dry > "$T/out" 2>&1; check "$?" "2" "a road outside the four: exit 2"

echo "== the lander verbs"
L() { "$AFR" lander "$@"; }
# Execute the finish skill's own formatter against the real read-only gate, not a second
# implementation of the skill's choice. The skill must contain exactly one such block.
python3 - "$B/../../wharf/skills/finish/SKILL.md" "$T/machine-closing" <<'PY'
import pathlib, re, sys
blocks = re.findall(r"```bash\n(# finish-machine-closing [\s\S]*?)\n```", pathlib.Path(sys.argv[1]).read_text())
assert len(blocks) == 1, "finish skill must have one machine closing formatter"
pathlib.Path(sys.argv[2]).write_text(blocks[0] + "\n")
PY
check "$?" "0" "the finish skill supplies the machine closing formatter"
machine_closing() {
  machine_closing_all 2>/dev/null | tail -1
}
machine_closing_all() {
  local road="fix round 1 of 3"; [ -n "${FINISH_ROAD_EMPTY:-}" ] && road=""
  AUTOFINISH_RUN="${CLOSING_TOOL:-$AFR}" FINISH_ADDRESS="SAM, " FINISH_ROAD="$road" \
    FINISH_OWNER_MOVE="resolve the review findings, then finish" bash "$T/machine-closing"
}
OWNER_CLOSING="🛑 SAM, THIS SESSION IS WAITING FOR YOU — resolve the review findings, then finish"
LANDER_CLOSING="⏳ SAM, THIS SESSION IS WAITING FOR SOMETHING — the lander's road: fix round 1 of 3"
L spend rounds --worktree "$W" > "$T/out" 2>&1; check "$?" "0" "spend rounds: the first"
L spend rounds --worktree "$W" > "$T/out" 2>&1; check "$?" "9" "  the second: STUCK_RC (rounds 1)"
has "$T/out" "rounds spent on" "  naming the counter"
L spend reruns --repo "$R" --branch "$BR" > /dev/null 2>&1; check "$?" "0" "spend reruns by --repo and --branch: the first"
L spend reruns --worktree "$W" > /dev/null 2>&1; check "$?" "0" "  the second, the same key by --worktree"
L spend reruns --worktree "$W" > /dev/null 2>&1; check "$?" "9" "  the third: STUCK_RC (reruns 2)"
L stuck --repo "$R" --branch "$BR-stuck" > /dev/null 2>&1
for counter in reruns rounds; do
  L spend "$counter" --repo "$R" --branch "$BR-stuck" > "$T/out" 2>&1
  check "$?" "9" "a stuck key refuses spend $counter under the store lock"
done
L show --repo "$R" --branch "$BR-stuck" > "$T/out" 2>&1
check "$(python3 -c 'import json, sys; e = json.load(open(sys.argv[1])); print(e["reruns"], e["rounds"])' "$T/out")" \
      "0 0" "  stuck spends leave both counters untouched"
L spend --worktree "$W" > /dev/null 2>&1; check "$?" "2" "spend with no counter: exit 2"
L hold --worktree "$W" > /dev/null 2>&1; check "$?" "2" "hold with no head or reason: exit 2"
L hold --worktree "$W" --head abc1234 --reason refinish > "$T/out" 2>&1; check "$?" "0" "hold: recorded"
has "$T/out" '"label": "lander-hold"' "  under lander-hold"
L stuck --worktree "$W" > /dev/null 2>&1; check "$?" "0" "stuck: recorded"
CLAUDE_UNATTENDED=1 "$AFR" lander reset --worktree "$W" > "$T/out" 2>&1; check "$?" "2" "reset from an unattended caller: refused (exit 2)"
L reset --worktree "$W" > "$T/out" 2>&1; check "$?" "0" "reset from the tick or a person"
check "$(python3 -c 'import json, sys; e = json.loads(open(sys.argv[1]).read()); print(e["state"], e["rounds"], e["reruns"], e["hold"]["head"])' "$T/out")" \
      "None 0 0 abc1234" "  the counts and the state fresh, the hold kept"
L lift --worktree "$W" > "$T/out" 2>&1; check "$?" "0" "lift: the hold gone"
has "$T/out" '"hold": null' "  read back"
L show > "$T/out" 2>&1; check "$?" "0" "show: the whole store"
has "$T/out" "repo/$BR" "  keyed <repo key>/<branch>"

echo "== lander armed: the relaunch gate and a tick on this Mac"
rm -f "$AUTOFINISH_STATE_DIR/armed"
SURFACES_HOST=laptop L armed > "$T/out" 2>&1; check "$?" "3" "the gate off: not armed (exit 3)"
has "$T/out" "the relaunch gate is off" "  saying why"
check "$(SURFACES_HOST=laptop machine_closing)" "$OWNER_CLOSING" "G1r, gate off: the skill ends on the owner's stop (stuck-ships S7)"
printf '{"by": "Sam", "ts": 1}\n' > "$AUTOFINISH_STATE_DIR/armed"
SURFACES_HOST=elsewhere PLAN_HOST=elsewhere L armed > "$T/out" 2>&1; check "$?" "3" "the gate on and no tick here: not armed"
has "$T/out" "neither the laptop nor a scope's yard" "  saying why"
check "$(SURFACES_HOST=elsewhere PLAN_HOST=elsewhere machine_closing)" "$OWNER_CLOSING" "G1r, gate on but no tick here: still the owner's"
export STALLS_STATE_DIR="$T/stalls"; mkdir -p "$STALLS_STATE_DIR"
SURFACES_HOST=laptop L armed > "$T/out" 2>&1; check "$?" "3" "the gate on, on the laptop, helm's tick disarmed: not armed"
has "$T/out" "helm's tick is disarmed" "  saying why"
check "$(SURFACES_HOST=laptop machine_closing)" "$OWNER_CLOSING" "G1r, tick disarmed: still the owner's"
printf '{"by": "Sam", "ts": "x", "t": %s}\n' "$(( $(date +%s) - 600 ))" > "$STALLS_STATE_DIR/armed"
SURFACES_HOST=laptop L armed > "$T/out" 2>&1; check "$?" "3" "  helm's tick inside its dry hours: not armed (it calls nothing)"
has "$T/out" "helm's tick is dry" "  saying why"
check "$(SURFACES_HOST=laptop machine_closing)" "$OWNER_CLOSING" "G1r, tick inside dry hours: still the owner's"
printf '{"by": "Sam", "ts": "x", "t": %s}\n' "$(( $(date +%s) - 4 * 3600 ))" > "$STALLS_STATE_DIR/armed"
SURFACES_HOST=laptop L armed > "$T/out" 2>&1; check "$?" "3" "the gate on, its tick armed, no lander roads yet (before S3): not armed"
has "$T/out" "no lander roads yet" "  saying why"
check "$(SURFACES_HOST=laptop machine_closing)" "$OWNER_CLOSING" "G1r, gate and tick armed but no roads: still the owner's (S7's landing review)"
# a tick with the lander's roads, as S3 will set it: a stand-in stalls_tick ahead of helm's on the path
mkdir -p "$T/roads"; printf 'LANDER_ROADS = True\ndef mode():\n    return "armed", ""\n' > "$T/roads/stalls_tick.py"
PYTHONPATH="$T/roads" SURFACES_HOST=laptop L armed > "$T/out" 2>&1; check "$?" "0" "the gate on, on the laptop, its tick armed with roads: armed"
check "$(PYTHONPATH="$T/roads" SURFACES_HOST=laptop machine_closing)" "$LANDER_CLOSING" "G1r, gate and tick armed: the skill hands the stop to the lander"
check "$(PYTHONPATH="$T/roads" SURFACES_HOST=laptop FINISH_ROAD_EMPTY=1 machine_closing)" "$OWNER_CLOSING" "an empty road: the owner's, never a line that reads as pending"
check "$(PYTHONPATH="$T/roads" SURFACES_HOST=laptop machine_closing_all | grep -c 'armed')" "0" "  the gate's own word goes to stderr, the formatter prints the line alone"
check "$(CLOSING_TOOL="$T/no-tool" machine_closing 2>/dev/null)" "$OWNER_CLOSING" "a missing gate tool: the owner's, never a machine promise"
cp "$AUTOFINISH_STATE_DIR/lander.json" "$T/lander.keep"; echo '{torn' > "$AUTOFINISH_STATE_DIR/lander.json"
SURFACES_HOST=laptop L armed > "$T/out" 2>&1; check "$?" "3" "a store that does not read: not armed (no start but a person's runs)"
has "$T/out" "does not read" "  saying why"
check "$(SURFACES_HOST=laptop machine_closing)" "$OWNER_CLOSING" "a store that does not read: the skill falls back to the owner's stop"
L reset --worktree "$W" > "$T/out" 2>&1; check "$?" "3" "a plain lander reset on a store that does not read: refused, nothing written (round 2)"
check "$(cat "$AUTOFINISH_STATE_DIR/lander.json")" "{torn" "  the store untouched, every other branch's stuck state still narrowing"
SKIPPER_SCOPE=s L reset --aside --worktree "$W" > "$T/out" 2>&1; check "$?" "2" "reset --aside from a skipper: refused (exit 2)"
L reset --aside --worktree "$W" > "$T/out" 2>&1; check "$?" "0" "lander reset --aside: sets it aside"
has "$T/out" "set aside as" "  saying where"
has "$T/out" "every branch's caps and stuck states" "  and what it clears"
check "$(ls "$AUTOFINISH_STATE_DIR" | grep -c '^lander.json.unreadable-')" "1" "  the torn file kept beside it"
cp "$T/lander.keep" "$AUTOFINISH_STATE_DIR/lander.json"
rm -f "$AUTOFINISH_STATE_DIR"/lander.json.unreadable-*
rm -f "$AUTOFINISH_STATE_DIR/armed"; printf '{"by": "Sam", "ts": 1}\n' > "$AUTOFINISH_STATE_DIR/landings"
PYTHONPATH="$T/roads" SURFACES_HOST=laptop L armed > "$T/out" 2>&1; check "$?" "0" "the landings switch alone opens the gate (task-shape S3's)"
rm -f "$AUTOFINISH_STATE_DIR/landings"

[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
exit $((fails > 0))
