#!/usr/bin/env bash
# Tests for bin/helm (bin/plan before rename S5, now its shim) and bin/helmlib.py (docs/session-asks-2026-10-09.md B2) and its renderings
# (B6–B8, bin/helm_render.py): the store, two concurrent reporters (K7), the estimate, the guarded
# copy that may leave the Mac (K6), the digest, the tail and the cost from a fixture transcript, the
# page, the board and the timeline from a golden state. No network, no model.
#   bash modules/helm/tests/test_helm.sh
set -u
B="$(cd "$(dirname "$0")/../bin" && pwd)"   # the module's bin/; helm itself is in libexec/, off PATH (C1)
LX="$(cd "$B/../libexec" && pwd)"
TD="$(cd "$(dirname "$0")" && pwd)"
# This checkout's core and modules, whatever the caller's REGATTA_HOME: the overlay's shims (its
# bin/plan runs its bin/helm, a source shim) load from it, so they run the module under test.
export REGATTA_HOME="$(cd "$B/../../.." && pwd)"
# A peer's path through the core's tool() (wharf-runs' dispatch, plumb's statusline, the overlay's bin/plan)
peer() { python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import find_core; sys.path.insert(0, find_core.hooks()); import common; print(common.tool(sys.argv[2]) or "")' "$B/../lib" "$1"; }
# The file a peer's text is read from: an overlay's source or exec shim names the module file it runs
# (wharf-runs' tools are shims there once B7 lands), so its own second line says where that is.
src() { local f; f=$(peer "$1"); local rel; rel=$(sed -nE 's/^# (Source|Exec) shim: this file moved to the regatta checkout, at (.*)\.$/\2/p' "$f" 2>/dev/null)
        if [ -n "$rel" ]; then echo "$REGATTA_HOME/$rel"; else echo "$f"; fi; }
# Rename S5 (helm-vocabulary H1): every case below runs twice — under the old names (the bin/plan
# shim, `new`, `overview`, `--owner`, `plan chain|apply`, DISPATCH_PLAN and DISPATCH_MANAGER*) and
# under the new (bin/helm, `ship`, `board`, `--by`, `wharf check|apply`, DISPATCH_SHIP and
# DISPATCH_SKIPPER*): a run dispatched before S5 types and carries the old ones until S8, and the
# readers take both forever. HELM_NAMES=old|new runs one of the two.
if [ -z "${HELM_NAMES:-}" ]; then
  HELM_NAMES=old bash "$0" "$@"; r1=$?
  HELM_NAMES=new bash "$0" "$@"; r2=$?
  [ "$r1" = 0 ] && [ "$r2" = 0 ]; exit $?
fi
echo "== the $HELM_NAMES names"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
# The old names run through the overlay's bin/plan (rename S5's shim, kept until S8); an overlay
# without it gets a stand-in with the shim's pass-through (`plan <verb>` → `helm <verb>`), which is
# all these cases type — never `plan chain|apply`, which are wharf's.
PLAN=$(peer plan)
if ! grep -q 'kept as a shim until S8' "$PLAN" 2>/dev/null; then
  printf '#!/bin/sh\nexec python3 "%s/helm" "$@"\n' "$LX" > "$T/plan"; chmod +x "$T/plan"; PLAN="$T/plan"
  [ "$HELM_NAMES" = old ] && echo "  (bin/plan: a stand-in — the overlay has no rename-S5 shim here)"
fi
if [ "$HELM_NAMES" = old ]; then
  HM="$PLAN" SHIP=new BOARD=overview BY=--owner E_SHIP=DISPATCH_PLAN E_SKIP=DISPATCH_MANAGER
  E_SKIP_HOST=DISPATCH_MANAGER_HOST E_SKIP_ACCOUNT=DISPATCH_MANAGER_ACCOUNT
else
  HM="$LX/helm" SHIP=ship BOARD=board BY=--by E_SHIP=DISPATCH_SHIP E_SKIP=DISPATCH_SKIPPER
  E_SKIP_HOST=DISPATCH_SKIPPER_HOST E_SKIP_ACCOUNT=DISPATCH_SKIPPER_ACCOUNT
fi
fails=0
check() { if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3: expected [$2] got [$1]"; fails=$((fails+1)); fi; }
has() { case "$1" in *"$2"*) echo "  ok   $3";; *) echo "  FAIL $3: [$2] not in [${1:0:300}]"; fails=$((fails+1));; esac; }
hasnt() { case "$1" in *"$2"*) echo "  FAIL $3: [$2] found"; fails=$((fails+1));; *) echo "  ok   $3";; esac; }

# a blueprint's front matter is read by PyYAML, installed per user on these Macs: keep its site
# when HOME moves below (bin/blueprintlib.py)
export PYTHONUSERBASE="${PYTHONUSERBASE:-$(python3 -m site --user-base)}"
. "$TD/config_fixture.sh"; fixture_config "$T/config"   # before HOME moves: the suite's own config dir, never the caller's
export PLANS_DIR="$T/plans" PLAN_HOST=testhost PLAN_PROJECTS_DIR="$T/projects" PLAN_CACHE_DIR="$T/cache" HOME="$T/home" \
       SURFACES_FILE="$T/surfaces.json" PLAN_NO_DEPLOY=1 ASK_SESSIONS_DIR="$T/sess" ASK_CACHE_DIR="$T/askcache" \
       COST_RATIO="$T/ratio.json" PLAN_NO_MEMO=1 PLAN_NO_GH=1 PLAN_PROJECTS_ROOT="$T/projects-root" \
       STALLS_PEERS= STALLS_REPOS= STALLS_ORCA=0 PLAN_NO_WHARF=1   # no wharf pass in a tick outside B7's own block, whose stub it reaches; the stall cards: no ssh to buildbox, no real repo's autofinished, no Orca app (B8's block turns its stub on)
unset DISPATCH_PLAN DISPATCH_MANAGER DISPATCH_PLAN_SPACE CLAUDE_UNATTENDED DISPATCH_REPO DISPATCH_MANAGER_HOST DISPATCH_DEPTH \
      DISPATCH_SHIP DISPATCH_SKIPPER DISPATCH_SKIPPER_HOST DISPATCH_SKIPPER_ACCOUNT DISPATCH_MANAGER_ACCOUNT \
      SKIPPER_GEN SKIPPER_SCOPE SKIPPER_ACCOUNT HELM_HOLD_EVERY HELM_HOLD_PARENT   # the lease's inputs (S4)
export CLAUDE_CODE_SESSION_ID=mgr-1
mkdir -p "$T/home" "$T/sess"
cp "$TD/surfaces.json" "$T/surfaces.json"
echo '{"providers": {"anthropic": {"ratio": 0.02, "week_ending": "2026-01-04"}}}' > "$COST_RATIO"

echo "store"
check "$("$HM" $SHIP demo --repo /x/tools)" "mgr-1" "the plan id defaults to this session's"
"$HM" $SHIP demo > /dev/null 2>&1; check "$?" "1" "a second plan under one id is refused"
"$HM" task mgr-1 build --title "Build it" --owns bin/x --branch claude/x > /dev/null
"$HM" task mgr-1 review --kind human $BY sam --title "Sam reviews" --milestone alpha > /dev/null
"$HM" task mgr-1 bad --kind human > /dev/null 2>&1; check "$?" "1" "a human task needs an owner"
"$HM" dep mgr-1 review --on build > /dev/null
"$HM" milestone mgr-1 alpha --on 2030-01-01 > /dev/null
"$HM" report mgr-1 --task build --status sideways > /dev/null 2>&1; check "$?" "1" "an unknown status is refused"
check "$("$HM" list | cut -d' ' -f1)" "mgr-1" "list"

echo "mode (skipper-modes S1): plan.json the authority, then the hint, the scope, the default"
check "$("$HM" mode mgr-1)" "mgr-1: default (the default)" "no mode anywhere: default"
"$HM" mode mgr-1 dnd > /dev/null
check "$("$HM" mode mgr-1)" "mgr-1: dnd (ship mgr-1)" "helm mode writes the ship's mode"
"$HM" mode mgr-1 ask --task build > /dev/null
check "$("$HM" mode mgr-1 --task build)" "mgr-1 task build: ask (ship mgr-1, task build)" "--task: one task's mode beats the ship's"
"$HM" mode mgr-1 loud > /dev/null 2>&1; check "$?" "2" "a mode that is none of the four: refused"
hl() { python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import helmlib; print(eval(sys.argv[2]))' "$B" "$1"; }
check "$(hl 'helmlib.run_mode({})[0]')" "None" "a session the owner types in has no mode (stated, was D2)"
check "$(hl 'helmlib.run_mode({"CLAUDE_UNATTENDED": "dispatch", "DISPATCH_MODE": "yolo"})')" "('yolo', \"the run's DISPATCH_MODE\")" "a run with no ship: its DISPATCH_MODE"
check "$(hl 'helmlib.run_mode({"CLAUDE_UNATTENDED": "dispatch", "DISPATCH_SHIP": "mgr-1", "DISPATCH_MODE": "yolo"})[0]')" "dnd" "  …a ship's mode beats it: DISPATCH_MODE is a hint"
check "$(hl 'helmlib.branch_mode("claude/x")[0]')" "ask" "branch_mode: the plan task naming the branch (the stand sweep's reader)"
check "$(hl 'helmlib.branch_mode("claude/nobody")[0]')" "None" "  a branch no sent task names: no mode"
printf '{"repos": {"rx": {}}, "scopes": {"s1": {"repos": ["r*"], "mode": "ask"}, "s2": {"repos": ["q"], "mode": "loud"}}}\n' > "$T/modes-repos.json"
check "$(CLAUDE_REPOS_JSON="$T/modes-repos.json" hl 'helmlib.task_mode(None, None, "rx")')" "('ask', 'scope s1')" "a task with no ship and no hint: its repo's scope mode (a glob)"
check "$(CLAUDE_REPOS_JSON="$T/modes-repos.json" hl 'helmlib.task_mode(None, None, "q")[0]')" "default" "  a scope's word that is no mode: the default"
"$HM" mode mgr-1 --task build --clear > /dev/null; "$HM" mode mgr-1 --clear > /dev/null
check "$("$HM" mode mgr-1 --task build)" "mgr-1 task build: default (the default)" "--clear drops both"
echo "mode raises (skipper-modes S3b): landing follows the mode, so only the owner raises one"
CLAUDE_UNATTENDED=dispatch "$HM" mode mgr-1 dnd > "$T/raise.out" 2>&1; check "$?" "1" "an unattended caller raising default → dnd: refused"
has "$(cat "$T/raise.out")" "only the owner raises a mode" "  saying why"
check "$("$HM" mode mgr-1)" "mgr-1: default (the default)" "  plan.json unchanged"
"$HM" mode mgr-1 yolo > /dev/null; check "$("$HM" mode mgr-1)" "mgr-1: yolo (ship mgr-1)" "the owner raises it (no CLAUDE_UNATTENDED)"
CLAUDE_UNATTENDED=dispatch "$HM" mode mgr-1 dnd > /dev/null 2>&1; check "$?" "0" "an unattended caller lowering yolo → dnd: free"
CLAUDE_UNATTENDED=dispatch "$HM" mode mgr-1 yolo > /dev/null 2>&1; check "$?" "1" "  and raising it back: refused"
CLAUDE_UNATTENDED=dispatch "$HM" mode mgr-1 ask --task build > /dev/null 2>&1; check "$?" "0" "  a task lowered to ask: free"
CLAUDE_UNATTENDED=dispatch "$HM" mode mgr-1 --task build --clear > /dev/null 2>&1; check "$?" "1" "  clearing it (the ship's dnd decides) is a raise: refused"
"$HM" mode mgr-1 --task build --clear > /dev/null; "$HM" mode mgr-1 --clear > /dev/null
check "$(hl 'helmlib.raise_refusal("ask", "default", {"CLAUDE_UNATTENDED": "x"}) is not None')" "True" "raise_refusal: ask → default is a raise too"
check "$(hl 'helmlib.raise_refusal(None, "default", {"CLAUDE_UNATTENDED": "x"})')" "None" "  no mode reads as default: no raise"
mkdir -p "$HOME/Library/Logs/claude-weekly/run-seed-runs"
printf '{"branch": "claude/rm", "started": 100, "task_mode": "dnd", "repo": "/x/rm"}\n' > "$HOME/Library/Logs/claude-weekly/run-seed-runs/build.json"
printf '{"branch": "claude/rm", "started": 200, "repo": "/x/rm"}\n' > "$HOME/Library/Logs/claude-weekly/run-seed-runs/finish.json"
check "$(hl 'helmlib.branch_mode("claude/rm")[0]')" "dnd" "branch_mode: a later --start record (no task_mode) does not hide the build run's mode"
check "$(hl 'helmlib.branch_mode("claude/rm", "/y/rm")[0]')" "None" "  a same-named branch of another repo: not this one's mode (landing review 14)"
check "$(hl 'helmlib.branch_mode("claude/rm", "/x/rm/.claude/worktrees/t")[0]')" "dnd" "  its own repo, named by a worktree path: its mode"
echo "helm mode --branch (landing review 4b): the lowering verb for a run with no ship"
CLAUDE_UNATTENDED=dispatch "$HM" mode --branch claude/rm default > /dev/null 2>&1; check "$?" "0" "a run lowers a shipless branch dnd → default"
check "$(hl 'helmlib.branch_mode("claude/rm")')" "('default', 'helm mode --branch claude/rm')" "  branch_mode reads it first"
CLAUDE_UNATTENDED=dispatch "$HM" mode --branch claude/rm yolo > /dev/null 2>&1; check "$?" "1" "  a run raising it: refused"
CLAUDE_UNATTENDED=dispatch "$HM" mode --branch claude/rm --clear > /dev/null 2>&1; check "$?" "1" "  a run clearing it (the record's dnd decides) is a raise: refused"
check "$(hl 'helmlib.branch_mode("claude/rm")[0]')" "default" "    …the lowered mode stands"
"$HM" mode --branch claude/rm --clear > /dev/null; check "$(hl 'helmlib.branch_mode("claude/rm")[0]')" "dnd" "  the owner's --clear: the run record decides again"
echo "a ship's mode is a ceiling (landing review 6)"
"$HM" mode mgr-1 yolo --task build > /dev/null
out=$("$HM" mode mgr-1 default)
has "$out" "task build: mode yolo cleared — now default" "helm mode <ship> default clears a task's yolo, and says so"
check "$(hl 'helmlib.branch_mode("claude/x")[0]')" "default" "  the branch now reads default"
"$HM" mode mgr-1 --clear > /dev/null
rm -f "$HOME/Library/Logs/claude-weekly/run-seed-runs/build.json" "$HOME/Library/Logs/claude-weekly/run-seed-runs/finish.json"

echo "the board's deploy only on a change (landing review 10)"
check "$(env -u PLAN_NO_DEPLOY PLAN_CACHE_DIR="$T/bcache" python3 - "$B" <<'PY'
import sys, time
sys.path.insert(0, sys.argv[1])
import helm_render as h
calls, cards = [], ["a"]
h.deploy_dir = lambda d, files, space=None, title=None, message=None: (calls.append(space), ("u1", "https://x"))[1]
age = ["3 min"]
h.overview_state = lambda: {"kind": "overview", "as_of": time.time(),
                            "header": {"needs_owner": 0, "owner": "Sam", "week": "Week: 53%%, sampled %s ago" % age[0]},
                            "timeline": {"now": time.time()},
                            "columns": [{"name": "Needs Sam", "cards": [{"kind": "stall", "repo": "r", "title": "%s gone %s" % (c, age[0])}
                                                                         for c in cards]}]}
h.page = lambda st, title: "x"
h.overview(deploy=True); time.sleep(0.01); age[0] = "8 min"; out = h.overview(deploy=True)
cards.append("b"); h.overview(deploy=True)
print(len(calls), out[-1])
PY
)" "2 sheep: unchanged since the last deploy (u1)" \
  "a second pass where only as_of, the week line's sample age, the timeline and a card's age moved: not deployed; a new card: deployed"
echo "K7: two reporters at once"
PLAN_NO_RENDER=1
export PLAN_NO_RENDER
for w in a b; do ( for i in $(seq 1 40); do "$HM" report mgr-1 --task "w$w" --status running --progress "$w $i" --session "s$w" > /dev/null; done ) & done; wait
check "$(wc -l < "$T/plans/mgr-1/events.jsonl" | tr -d ' ')" "80" "80 lines from two writers"
check "$(python3 -c "import json; [json.loads(l) for l in open('$T/plans/mgr-1/events.jsonl')]; print('parsed')")" "parsed" "every line parses: none interleaved"
check "$("$HM" state | python3 -c "import json,sys; d={t['id']:t['progress'] for t in json.load(sys.stdin)['tasks']}; print(d['wa'], d['wb'])")" "a 40 b 40" "the last event per task wins"

echo "finding 1: a long report shrinks its text, never its JSON"
long=$(python3 -c "print('é' * 3000)")
"$HM" report mgr-1 --task long --status running --progress "$long" --summary "$long" --recommended "$long" --session sl > /dev/null
check "$(python3 - "$T/plans/mgr-1/events.jsonl" <<'PY'
import json, sys
bad = [l for l in open(sys.argv[1], encoding="utf-8") if len(l.rstrip("\n").encode()) > 4000]
last = json.loads(open(sys.argv[1], encoding="utf-8").read().splitlines()[-1])
print(len(bad), last["task"], last["status"], last["progress"].endswith("…"), len(last["progress"]) > 100)
PY
)" "0 long running True True" "every line under 4000 bytes, valid JSON, the text cut with a mark (UTF-8 bytes, no torn character)"
check "$(python3 - "$B" <<'PY'
import sys; sys.path.insert(0, sys.argv[1]); import helmlib
ev, line = helmlib.fit({'task': 't', 'status': 'running', 'owns': ['p' * 50] * 200})
print(len(line.encode()) <= helmlib.MAX_LINE, ev.get('truncated'), 'owns' in ev, ev['task'])
PY
)" "True True False t" "  a line the text alone cannot fit keeps its essentials and says so"
check "$("$HM" state | python3 -c "import json,sys; print([t['status'] for t in json.load(sys.stdin)['tasks'] if t['id']=='long'])")" "['running']" "  state() reads it (a torn line was skipped)"
check "$(python3 - "$B" <<'PY'
import sys; sys.path.insert(0, sys.argv[1]); import helmlib
ev, line = helmlib.fit({'task': 't', 'status': 'running', 'progress': chr(1) * 900})
print(len(line.encode()) <= helmlib.MAX_LINE, len(ev['progress']) > 600, ev['progress'].endswith('…'))
PY
)" "True True True" "  second review, finding 7: a text heavy in escapes keeps what fits (cut by its JSON length, not to …)"
check "$(python3 - "$B" <<'PY'
import sys; sys.path.insert(0, sys.argv[1]); import helmlib
ev, line = helmlib.fit({'task': 't', 'status': 'running', 'progress': 'é\"' * 1400})
print(len(line.encode()) <= helmlib.MAX_LINE, len(line.encode()) > helmlib.MAX_LINE - 10)
PY
)" "True True" "  non-ASCII and quotes mixed: cut to within a few bytes of the limit"
# the guarded list is hooks/sheep_gate.py's, case-folded; a gate that will not load falls back to
# the core's lists, the registry's and `regatta/guarded` (never raises)
check "$(python3 -c "
import sys; sys.path.insert(0, '$B'); import helmlib
print('transcripts' in helmlib.GUARDED, helmlib.guarded('Transcripts'), helmlib.guarded('/x/transcripts/.claude/worktrees/y'), helmlib.guarded('garden'))")" \
  "True True True False" "guarded: the gate's list, case-folded, any path part"
# a scratch checkout: the core, helm's helmlib, and a keel whose gate raises (tool() finds it first)
BG="$T/brokengate"; mkdir -p "$BG/.claude-plugin" "$BG/modules/helm/bin" "$BG/modules/helm/lib" "$BG/modules/keel/hooks"
cp "$REGATTA_HOME/.claude-plugin/marketplace.json" "$BG/.claude-plugin/"; cp -R "$REGATTA_HOME/modules/regatta" "$BG/modules/"
cp "$B/helmlib.py" "$BG/modules/helm/bin/"; cp "$B/../lib/find_core.py" "$BG/modules/helm/lib/"
echo 'raise RuntimeError("half-edited")' > "$BG/modules/keel/hooks/sheep_gate.py"
check "$(python3 -c "
import sys; sys.path.insert(0, '$BG/modules/helm/bin'); import helmlib
print(helmlib._sheep_gate, helmlib.GUARDED, helmlib.guarded('Transcripts/x'), helmlib.guarded('garden'))" 2>&1)" \
  "None ('transcripts',) True False" "  a gate that raises at load: helmlib still imports, with the core's list"

echo "state: blockers, parked, asks, the estimate"
now=$(date +%s)
"$HM" report --task build --status running --cost 1 --eta 1h --session s1 > /dev/null
python3 - "$T/plans/mgr-1/events.jsonl" "$now" <<'EOF'
import json, sys
# the run started an hour ago: back-date its first running event so the burn rate is $1 an hour
p, now = sys.argv[1], float(sys.argv[2])
ls = [json.loads(l) for l in open(p)]
for e in ls:
    if e.get("task") == "build":
        e["t"] = now - 3600
open(p, "w").write("".join(json.dumps(e) + "\n" for e in ls))
EOF
"$HM" report --task build --status running --cost 1 --eta 1h --session s1 > /dev/null
st=$("$HM" state)
check "$(echo "$st" | python3 -c "import json,sys; t=[t for t in json.load(sys.stdin)['tasks'] if t['id']=='build'][0]; print(round(t['est_to_go'],1), t['est_kind'])")" "1.0 est." "burn rate × time left, marked est."
"$HM" eta mgr-1 build 2h --cost 3 > /dev/null
check "$("$HM" state | python3 -c "import json,sys; t=[t for t in json.load(sys.stdin)['tasks'] if t['id']=='build'][0]; print(t['est_to_go'], t['est_kind'])")" "2.0 manager" "the manager's estimate wins when set"
"$HM" report --task build --status relayed --ask docs/x.md#D1 --summary "which cadence" --parked D1 > /dev/null
st=$("$HM" state)
check "$(echo "$st" | python3 -c "import json,sys; t=[t for t in json.load(sys.stdin)['tasks'] if t['id']=='build'][0]; print(t['parked'], t['blockers'])")" "['D1'] ['open ask docs/x.md#D1']" "parked and the open ask block it"
check "$(echo "$st" | python3 -c "import json,sys; t=[t for t in json.load(sys.stdin)['tasks'] if t['id']=='review'][0]; print(t['blockers'], t['kind'], t['owner'])")" "['waits on build'] human sam" "a human task waits on its dependency"
check "$(echo "$st" | python3 -c "import json,sys; print(json.load(sys.stdin)['milestones'][0]['open'])")" "1" "a milestone counts its open tasks"
"$HM" report --task build --answered docs/x.md#D1 > /dev/null
check "$("$HM" state | python3 -c "import json,sys; t=[t for t in json.load(sys.stdin)['tasks'] if t['id']=='build'][0]; print(t['parked'], t['asks'][0]['open'])")" "[] False" "an answer unparks and closes the ask"
out=$("$HM" show)
has "$out" "- build [relayed] Build it" "show: the task line"
has "$out" 'cost $1.00 ($0.020 effective)' "show: cost as list and effective"
has "$out" "◆ alpha" "show: the milestone"

echo "K6: the guarded copy"
"$HM" task mgr-1 secret --repo /x/projects/transcripts --title "Pay the tax" > /dev/null
"$HM" report --task secret --status running --progress "IBAN 1234" > /dev/null
pub=$("$HM" state --public)
hasnt "$pub" "IBAN" "a guarded task's progress never leaves"
hasnt "$pub" "Pay the tax" "…nor its title"
has "$pub" "a task in a guarded repo" "it shows as a guarded row"
echo "K6, finding 5: an undeclared task reporting from a guarded repo's worktree"
PG="$T/projects-root/transcripts"; mkdir -p "$PG"; git -C "$PG" init -q; git -C "$PG" commit -q --allow-empty -m x
git -C "$PG" worktree add -q "$PG/.claude/worktrees/tax" -b claude/x 2>/dev/null
(cd "$PG/.claude/worktrees/tax" && env -u DISPATCH_REPO "$HM" report mgr-1 --task taxes --status relayed --progress "IBAN 999" \
  --ask docs/tax-secret.md#D1 --summary "which bank" --recommended "pay Sam's tax" --reversible no --branch claude/tax-secret > /dev/null)
check "$(python3 -c "import json; e=[json.loads(l) for l in open('$T/plans/mgr-1/events.jsonl')][-1]; print(e['repo'].endswith('/transcripts'))")" "True" "  the report records the main checkout, not the worktree"
pub=$("$HM" state --public)
for leak in "IBAN 999" "which bank" "pay Sam" "tax-secret" "claude/tax-secret"; do hasnt "$pub" "$leak" "  no '$leak' leaves"; done
check "$(echo "$pub" | python3 -c "import json,sys; t=[t for t in json.load(sys.stdin)['tasks'] if t['guarded'] and t['asks']][0]; print(t['guarded'], t['asks'][0]['ref'], t['asks'][0]['reversible'], t['blockers'])")" "True guarded None ['guarded']" "  guarded by its event: the ask's ref, Reversible: and the blocker's text gone"
DISPATCH_REPO=/x/projects/transcripts "$HM" report mgr-1 --task cv --status running --progress "salary 1" > /dev/null
hasnt "$("$HM" state --public)" "salary 1" "  DISPATCH_REPO, which dispatch passes, names the repo too"
echo "second review, finding 8: a guarded task's id, check and owner"
"$HM" $SHIP guards --id pg > /dev/null
"$HM" task pg tax-return --repo /x/projects/transcripts --title "Tax" > /dev/null
"$HM" task pg sign --kind human $BY sam --repo /x/projects/transcripts > /dev/null
"$HM" task pg build > /dev/null; "$HM" dep pg build --on tax-return > /dev/null
DISPATCH_REPO=/x/projects/transcripts "$HM" report pg --task tax-return --status running $BY transcripts-3 > /dev/null
python3 - "$T/plans/pg/events.jsonl" <<'PY'
import json, sys
# a check state, as the check-runs reader would add it
open(sys.argv[1], "a").write(json.dumps({"task": "tax-return", "check": "fail: tax-return.test", "t": 2e9}) + "\n")
PY
pub=$("$HM" state pg --public)
hasnt "$pub" "tax-return" "  the id never leaves: not as a task, a dep, a blocker or a check"
hasnt "$pub" "transcripts-3" "  a session owner named for its cwd never leaves"
hasnt "$pub" "guard_salt" "  nor the salt that keys the tokens"
# the guarded tasks, picked by what they still show: the human one keeps its person owner
tok() { echo "$1" | python3 -c "
import json, sys
ts = json.load(sys.stdin)['tasks']
g = [t for t in ts if t['guarded']]
tax = [t for t in g if t['kind'] != 'human'][0]; sign = [t for t in g if t['kind'] == 'human'][0]
b = [t for t in ts if t['id'] == 'build'][0]
print(tax['id'][:8], len(tax['id']), b['deps'] == [tax['id']], b['blockers'] == ['waits on ' + tax['id']], sign['owner'], tax['check'], tax['owner'])"; }
check "$(tok "$pub")" "guarded- 16 True True sam None None" "  the id is a token; a sibling's dep and blocker take it; a person owner stays, a session's goes; check is null"
first=$(echo "$pub" | python3 -c "import json,sys; print(sorted(t['id'] for t in json.load(sys.stdin)['tasks'] if t['guarded']))")
"$HM" task pg aaa-first --repo /x/projects/transcripts > /dev/null   # sorts before every other task
check "$("$HM" state pg --public | python3 -c "import json,sys; ts=json.load(sys.stdin)['tasks']; print(sorted(t['id'] for t in ts if t['guarded'] and t['kind'] != 'human' and t['owner'] is None and t['check'] is None and t['status'] == 'running') + sorted(t['id'] for t in ts if t['guarded'] and t['kind'] == 'human'))")" \
  "$(echo "$pub" | python3 -c "import json,sys; ts=json.load(sys.stdin)['tasks']; print(sorted(t['id'] for t in ts if t['guarded'] and t['kind'] != 'human') + sorted(t['id'] for t in ts if t['guarded'] and t['kind'] == 'human'))")" \
  "  stable: a new guarded task that sorts first leaves the old tokens as they were"
rm -rf "$T/plans/pg"   # the board's tests below count every plan's cards

echo "digest"
printf '# Doc\n\nText.\n\n## Later\n\nMore.\n' > "$T/doc.md"
"$HM" digest "$T/doc.md" > /dev/null; "$HM" digest "$T/doc.md" > /dev/null
check "$(grep -c '^## Plan' "$T/doc.md")" "1" "twice is one Plan section"
has "$(cat "$T/doc.md")" "| build | relayed |" "the table carries the tasks"

echo "compile and digest: the Action plan is the chain (entry S4, layer D4-A)"
cat > "$T/course.md" <<'EOF'
# Course — a test (entry doc, 2026-10-15)

Status: answered — 1 of 1 decision answered · action plan: 0 of 4 steps done · handed over 2026-10-15

## Decisions

- **D1 — Go?**
  - A — yes

  Reversible: yes

  ➤ Recommended: A

  ➤ Answer:
  A

## Action plan

- **S1 — the base** · session `sr-worker` · after: D1 · status: not started
- **S2 — on top** · session `worker` · after: S1, D1 · gate: `bin/keel` · status: not started
- **S3 — in another repo** · project `acme/pipeline` · after: S1 · status: not started
- **S4 — Sam looks** · human (only Sam sees it) · after: S2, S3 · status: not started

## Risks
EOF
"$HM" $SHIP course --id cp > /dev/null
out=$("$HM" compile cp "$T/course.md")
has "$out" "compiled 4 steps of course.md into ship cp: 2 human, 2 session; 4 deps" "compile: four steps, their kinds, the deps from after:"
cpf() { "$HM" state cp | python3 -c 'import json,sys; d={t["id"]: t for t in json.load(sys.stdin)["tasks"]}; print(" ".join(str(tuple(d[i][k] for k in sys.argv[2].split(","))) for i in sys.argv[1].split(",")))' "$1" "$2"; }
check "$(cpf S2,S3,S4 kind,owner,deps)" \
      "('session', None, ['S1']) ('human', 'sam', ['S1']) ('human', 'sam', ['S2', 'S3'])" "…a D in after: is no dep; a project step is a human one for sam; a human step has its owner"
check "$(cpf S3 title,repo)" \
      "('project acme/pipeline: in another repo', 'acme/pipeline')" "…the project step names the project, its repo the project's"
"$HM" compile cp "$T/course.md" > /dev/null
check "$(cpf S4 deps)" "(['S2', 'S3'],)" "…twice is the same plan"
"$HM" report cp --task S1 --status done --branch claude/laptop/2026-10-15-x --session s1 > /dev/null
"$HM" report cp --task S2 --status running --session s2 > /dev/null
"$HM" report cp --task S3 --status failed --session s3 > /dev/null
cp "$T/course.md" "$T/course.before"
out=$("$HM" digest cp "$T/course.md")
day=$(date +%F)  # plan digest writes local dates (helmlib.iso): UTC failed 17:00–24:00 PDT
has "$(grep '^- \*\*S1 ' "$T/course.md")" "· status: done $day claude/laptop/2026-10-15-x" "digest: done → done with the date and branch"
has "$(grep '^- \*\*S2 ' "$T/course.md")" "· gate: \`bin/keel\` · status: wip" "…running → wip, the gate field kept"
has "$(grep '^- \*\*S3 ' "$T/course.md")" "· status: blocked — failed $day" "…failed → blocked with the note"
has "$(grep '^- \*\*S4 ' "$T/course.md")" "· status: not started" "…a task that reported nothing is left alone"
check "$(sed -n 3p "$T/course.md")" "Status: blocked — 1 of 1 decision answered · action plan: 1 of 4 steps done · handed over 2026-10-15" "…then the Status line is stamped (a blocked step blocks the doc)"
check "$(grep -c '^## Plan' "$T/course.md")" "0" "…and no Plan section is written into a Course doc"
check "$(diff <(grep -v '^- \*\*S\|^Status:' "$T/course.before") <(grep -v '^- \*\*S\|^Status:' "$T/course.md") && echo same)" "same" "…nothing but S-lines and the Status line changed"
"$HM" report cp --task S1 --status running --session s1b > /dev/null
out=$("$HM" digest cp "$T/course.md")
has "$out" "kept S1 done" "a done step never moves back on a later plan status"
has "$(grep '^- \*\*S1 ' "$T/course.md")" "· status: done $day" "…its line is unchanged"
# The entry's risk: an action plan under a `## Plan` heading (not "Action plan") is no Course plan for
# keel, and the old digest replaced the first `## Plan` section it found — the steps gone.
cat > "$T/planhead.md" <<'EOF'
# Old shape

## Plan

- **S1 — keep me** · session `worker` · after: — · status: not started
- **S2 — and me** · session `worker` · after: S1 · status: not started

## Later
EOF
"$HM" digest cp "$T/planhead.md" > /dev/null; "$HM" digest cp "$T/planhead.md" > /dev/null
has "$(cat "$T/planhead.md")" "- **S1 — keep me** · session \`worker\` · after: — · status: not started" "digest never overwrites an action plan under a ## Plan heading"
has "$(cat "$T/planhead.md")" "- **S2 — and me**" "…both steps kept"
check "$(grep -c '(bin/helm digest;' "$T/planhead.md")" "1" "…its own digest added once, and replaced on the next run"
"$HM" compile cp "$T/planhead.md" > /dev/null 2>&1; check "$?" "1" "compile refuses a doc with no Action plan heading"
rm -rf "$T/plans/cp"   # the board's tests below count every plan's cards

echo "cost auto and tail from a transcript"
mkdir -p "$T/projects/-x"
cat > "$T/projects/-x/s9.jsonl" <<'EOF'
{"type":"assistant","requestId":"r1","message":{"model":"claude-opus-5-5","usage":{"input_tokens":1000,"output_tokens":10,"cache_read_input_tokens":0},"content":[{"type":"text","text":"first"}]}}
{"type":"assistant","requestId":"r1","message":{"model":"claude-opus-5-5","usage":{"input_tokens":1000,"output_tokens":1000,"cache_read_input_tokens":0},"content":[{"type":"text","text":"line one\nline two"}]}}
EOF
"$HM" report --task t9 --status running --session s9 --cost auto > /dev/null
check "$("$HM" state | python3 -c "import json,sys; t=[t for t in json.load(sys.stdin)['tasks'] if t['id']=='t9'][0]; print(t['cost'])")" "0.024" "a streamed reply counts once, priced by usage-report's table"
check "$("$HM" tail t9 -n 2 | tr '\n' '|')" "line one|line two|" "tail: the last assistant lines"
check "$("$HM" tail secret)" "guarded — open it" "a guarded task's tail is never printed"


echo "report off this Mac with no road"
env "$E_SHIP=elsewhere" ASK_NO_KEY_FILES=1 SPACESHEEP_KEY= "$HM" report --task x --status running > /dev/null 2>&1; check "$?" "1" "no plan here and no road: said, exit 1"

echo "rename S5 (H1): a plan made before the change, through the bin/plan shim and bin/helm"
H() { PLANS_DIR="$T/h1" "$@"; }
mkdir -p "$T/h1/old1"
# plan.json as bin/plan wrote it before S5: `owner`, no `block`, no started, due or cost; a `landed` report
python3 - "$T/h1/old1" <<'PY2'
import json, sys, time
d = sys.argv[1]; now = time.time()
json.dump({"id": "old1", "topic": "before", "created": now - 7200, "manager": {"session": "mgr-0", "host": "testhost"},
           "space": None, "repo": None, "tasks": {"build": {"title": "Build", "owner": "alex"}, "rev": {"kind": "human", "owner": "sam"}},
           "milestones": [], "salt": "ab12", "updated": now - 7200}, open(d + "/plan.json", "w"))
with open(d + "/events.jsonl", "w") as f:
    f.write(json.dumps({"task": "build", "status": "running", "t": now - 3600, "owner": "alex"}) + "\n")
    f.write(json.dumps({"task": "old", "status": "landed", "t": now - 1800}) + "\n")
PY2
check "$(H "$PLAN" new after --id old2)" "old2" "plan new answers through the shim (helm ship)"
check "$(H python3 -c "import json; print(sorted(json.load(open('$T/h1/old2/plan.json'))))")" \
  "['created', 'id', 'manager', 'milestones', 'repo', 'salt', 'space', 'tasks', 'topic', 'updated']" "  a ship with no --due or --cost writes neither"
H "$PLAN" task old1 human2 --kind human --owner alex > /dev/null; check "$?" "0" "plan task --owner on the old plan"
check "$(python3 -c "import json; print(json.load(open('$T/h1/old1/plan.json'))['tasks']['human2'])")" "{'by': 'alex', 'kind': 'human'}" "  --owner is written as by (D3-A)"
H "$LX/helm" task old1 human3 --kind human --by sam --block b3 > /dev/null; check "$?" "0" "helm task --by --block"
H "$PLAN" report old1 --task build --status done --owner sam > /dev/null; check "$?" "0" "plan report through the shim"
st=$(H "$LX/helm" state old1)
check "$(echo "$st" | python3 -c "import json,sys; d=json.load(sys.stdin); t={x['id']: x for x in d['tasks']}; print(t['build']['by'], t['build']['owner'], t['rev']['by'], t['human3']['block'], t['old']['status'], d['due'], d['cost'], d['started'] is not None)")" \
  "sam sam sam b3 landed None None True" "  state: by read from by or owner (owner kept beside it), the block, an old landed task, no due or cost, started from its first running task"
# the clock aside: "as of" and "updated Ns ago" move between the two calls
pshow=$(H "$PLAN" show old1 | sed 's/; as of .*//; s/updated [0-9]*s ago/updated now/')
hshow=$(H "$LX/helm" show old1 | sed 's/; as of .*//; s/updated [0-9]*s ago/updated now/')
check "$pshow" "$hshow" "plan show and helm show print the same state"
has "$hshow" "ship old1 — before (skipper mgr-0 on testhost)" "  the persisted manager key printed as skipper"
has "$hshow" "· due none · cost none" "  a ship from before S5: no due date, no cost"
check "$(H "$PLAN" tick --status)" "$(H "$LX/helm" tick --status)" "plan tick --status and helm tick --status say the same"
H "$LX/helm" ship before --id old1 --due 2026-10-20 --cost 20 > /dev/null; check "$?" "0" "helm ship on an existing ship sets its due date and cost"
has "$(H "$LX/helm" show old1)" "due 2026-10-20 · cost \$" "  the card says them"
has "$(H "$LX/helm" show old1)" "of \$20" "  cost so far of the estimate"
H "$LX/helm" ship before --id old1 > /dev/null 2>&1; check "$?" "1" "  with neither, an existing ship is refused as before"
check "$(H "$LX/helm" ship new3 --id new3 --due 2d --cost 5 > /dev/null; python3 -c "import json,time; p=json.load(open('$T/h1/new3/plan.json')); print(p['cost'], p['due'] > time.time(), 'started' in p)")" "5.0 True False" "helm ship --due --cost: written; started waits for the first apply"
H "$LX/helm" eta old1 build 2h --cost 4 > /dev/null; H "$LX/helm" report old1 --task build --status running > /dev/null
has "$(H "$LX/helm" show old1)" " skipper" "the estimate kind \"manager\" (on disk) printed as skipper"
check "$(H "$LX/helm" board --json | python3 -c "import json,sys; print(json.load(sys.stdin)['kind'])")" \
      "$(H "$LX/helm" overview --json | python3 -c "import json,sys; print(json.load(sys.stdin)['kind'])")" "overview answers as board's alias"
echo "  the run's environment: the ship under DISPATCH_SHIP or DISPATCH_PLAN"
for e in "DISPATCH_PLAN=old1" "DISPATCH_SHIP=old1" "DISPATCH_SHIP=old1 DISPATCH_PLAN=old2"; do
  H env -u DISPATCH_SHIP -u DISPATCH_PLAN $e "$LX/helm" report --task "env-$(echo "$e" | wc -w | tr -d ' ')-${e%%=*}" --status running > /dev/null
done
check "$(python3 -c "
import json
ids = [json.loads(l)['task'] for l in open('$T/h1/old1/events.jsonl') if json.loads(l)['task'].startswith('env-')]
print(ids, [json.loads(l)['task'] for l in open('$T/h1/old2/events.jsonl') if json.loads(l)['task'].startswith('env-')])")" \
  "['env-1-DISPATCH_PLAN', 'env-1-DISPATCH_SHIP', 'env-2-DISPATCH_SHIP'] []" "DISPATCH_PLAN alone, DISPATCH_SHIP alone, both (the new name wins): the report lands on the ship named"
check "$(env -u DISPATCH_SKIPPER -u DISPATCH_MANAGER python3 - "$B" <<'PY'
import sys; sys.path.insert(0, sys.argv[1]); import helmlib
print(helmlib.env('skipper', {'DISPATCH_MANAGER': 'm'}), helmlib.env('skipper', {'DISPATCH_SKIPPER': 's'}),
      helmlib.env('skipper', {'DISPATCH_SKIPPER': 's', 'DISPATCH_MANAGER': 'm'}), helmlib.env('skipper', {}),
      helmlib.env('skipper_host', {'DISPATCH_MANAGER_HOST': 'h'}), helmlib.env('skipper_account', {'DISPATCH_SKIPPER_ACCOUNT': 'a'}),
      helmlib.env_pairs('ship', 'x'))
PY
)" \
  "m s s None h a [('DISPATCH_SHIP', 'x'), ('DISPATCH_PLAN', 'x')]" "helmlib.env: the old name alone, the new alone, both (new wins), neither; env_pairs writes both"
echo "  the surfaces row: helm, and a file that still says plan"
printf '{"plan": {"live": "redeploy"}}' > "$T/h1/surf-old.json"; printf '{"plan": {"live": "redeploy"}, "helm": {"live": "stream"}}' > "$T/h1/surf-both.json"
check "$(python3 -c "
import sys; sys.path.insert(0, '$B'); import surfaces
print(surfaces.row('helm.live', '$T/h1/surf-old.json'), surfaces.row('plan.live', '$T/h1/surf-old.json'), surfaces.row('helm.live', '$T/h1/surf-both.json'),
      surfaces.row('helm.render', '$T/h1/surf-old.json'), [x for x in surfaces.validate({'plan': {'live': 'nonsense'}}) if 'nonsense' in x])")" \
  "redeploy redeploy stream ['local', 'sheep', 'artifact'] [\"helm.live: unknown backend 'nonsense' (known: local-sse, records, redeploy, stream)\"]" \
  "a plan row reads as helm's, helm wins where both are set, the defaults fill the rest, a bad old row is still caught"
cp "$T/surfaces.json" "$T/h1/surf-set.json"; python3 -c "
import sys; sys.path.insert(0, '$B'); import surfaces; surfaces.set_row('plan.live=redeploy', '$T/h1/surf-set.json')"
check "$(python3 -c "import json; d=json.load(open('$T/h1/surf-set.json')); print(d['helm']['live'], 'plan' in d)")" "redeploy False" "  --set plan.live writes helm.live"
echo "  the old digest mark is still this tool's own"
printf '# Doc\n\n## Plan\n\nDigest of plan `old1` as of then (bin/plan digest; the live state is the plan page).\n\n| old |\n\n## After\n' > "$T/h1/olddigest.md"
H "$LX/helm" digest old1 "$T/h1/olddigest.md" > /dev/null
check "$(grep -c '(bin/plan digest;' "$T/h1/olddigest.md") $(grep -c '(bin/helm digest;' "$T/h1/olddigest.md") $(grep -c '^## Plan' "$T/h1/olddigest.md")" "0 1 1" \
  "a digest written by bin/plan is replaced, not doubled"
unset -f H

if [ -f "$B/helm_render.py" ]; then
  unset PLAN_NO_RENDER
  echo "render (B6)"
  out=$("$HM" render)
  has "$out" "local:" "render writes the local page"
  page="$T/cache/mgr-1/index.html"; sj="$T/cache/mgr-1/state.json"
  check "$([ -s "$page" ] && [ -s "$sj" ] && echo yes)" "yes" "index.html and state.json beside it"
  has "$(cat "$page")" "fetch('state.json'" "the page reads its own state (one file for every target)"
  hasnt "$(cat "$sj")" "IBAN" "state.json is the public copy (K6)"
  has "$out" "sheep: off (PLAN_NO_DEPLOY)" "no deploy in tests"
  has "$(cat "$page")" "landed:'var(--done)',launched:'var(--done)'" "the page colours a launched task as a landed one (rename S2, M11)"
  echo "rename S2 (M11): an old plan.json's landed task and a new launched one both end, free their dependants, are done today"
  check "$(python3 - "$B" <<'PY'
import importlib.machinery, importlib.util, sys, time
sys.path.insert(0, sys.argv[1])
import helmlib, helm_render
helmlib.load_plan = lambda pid: {"id": pid, "tasks": {"a": {}, "b": {}, "c": {"deps": ["a", "b"]}}}
now = time.time()
helmlib.events = lambda pid: [{"task": "a", "status": "landed", "t": now}, {"task": "b", "status": "launched", "t": now}]
st = helmlib.state("s2")
t = {x["id"]: x for x in st["tasks"]}
loader = importlib.machinery.SourceFileLoader("planmod", sys.argv[1] + "/../libexec/helm")
spec = importlib.util.spec_from_loader("planmod", loader); plan = importlib.util.module_from_spec(spec); loader.exec_module(plan)
print(all(s in helmlib.STATUSES and s in helmlib.ENDED for s in ("landed", "launched")), t["c"]["blockers"],
      sorted(c["title"] for c in helm_render.plan_cards(st) if c["column"] == "Done today"),
      plan.STEP_OF["landed"], plan.STEP_OF["launched"])
PY
)" "True [] ['a', 'b'] done done" "  both words in STATUSES and ENDED, neither blocks c, both cards Done today, both a done step"
  echo "overview (B6)"
  ov=$("$HM" $BOARD --json)
  check "$(echo "$ov" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['columns'][0]['name'], len(d['columns']))")" "Needs Sam 6" "six columns, Needs Sam first"
  check "$(echo "$ov" | python3 -c "import json,sys; d=json.load(sys.stdin); print(sorted(c['title'] for col in d['columns'] if col['name']=='Blocked' for c in col['cards']))")" "['Sam reviews']" "a human task whose dependency is not done is Blocked"
  "$HM" task mgr-1 sign --kind human $BY alex --title "Alex signs" > /dev/null
  mkdir -p "$T/projects-root/garden"; printf -- '- swap the porch bulb @sam\n- a session item\n' > "$T/projects-root/garden/TODO.md"
  ov=$("$HM" $BOARD --json)
  check "$(echo "$ov" | python3 -c "import json,sys; d={c['name']:[x['title'] for x in c['cards']] for c in json.load(sys.stdin)['columns']}; print(d['Needs Alex'], d['Needs Sam'])")" "['Alex signs'] ['swap the porch bulb']" "human tasks and @-tagged TODO lines are cards in their owner's column"
  check "$(echo "$ov" | python3 -c "import json,sys; d={c['name']:[x['title'] for x in c['cards']] for c in json.load(sys.stdin)['columns']}; print('guarded — open it' in d['Running'])")" "True" "a guarded task keeps its column and nothing else"
  check "$(echo "$ov" | python3 -c "import json,sys; r=json.load(sys.stdin)['timeline'][0]; print(r['plan'], len(r['bars']) > 3, r['milestones'][0]['name'])")" "demo True alpha" "the timeline: a row per plan, bars and milestones (B7)"
  hasnt "$ov" "IBAN" "the board never carries a guarded row's text"
  check "$(echo "$ov" | python3 -c "import json,sys; ids=[b['id'] for r in json.load(sys.stdin)['timeline'] for b in r['bars']]; print('secret' in ids, 'taxes' in ids, sum(i.startswith('guarded-') for i in ids))")" "False False 3" "the timeline's bars carry the guarded tokens, never the ids (second review, finding 8)"
  # crosstalk S6: the lookout's open cards (keel lookout --status --json) are cards in the owner's column
  printf '#!/usr/bin/env python3\nimport json, sys\nassert sys.argv[1:] == ["lookout", "--status", "--json"], sys.argv\nprint(json.dumps({"armed": True, "cards": [\n {"doc": "demo@claude/buildbox/2026-10-21-x:docs/d.md", "id": "e1", "items": ["D1"], "host": "laptop", "ts": 1760000000, "card": "no live session for demo@claude/buildbox/2026-10-21-x:docs/d.md D1 — the run would start here"},\n {"doc": "transcripts@claude/laptop/2026-10-21-y:docs/p.md", "id": "e2", "items": [], "card": "a guarded one"}, {"id": "e3"}]}))\n' > "$T/keelstub"
  printf 'import json, sys\nd = json.load(sys.stdin)\nprint(json.dumps([[c["title"], c.get("repo"), c.get("ref"), c.get("evidence")] for col in d["columns"] if col["name"] == "Needs Sam" for c in col["cards"] if c["kind"] == "lookout"]))\n' > "$T/lc.py"
  lc() { python3 "$T/lc.py"; }
  check "$(PLAN_KEEL="$T/keelstub" "$HM" $BOARD --json | lc)" \
    '[["docs/d.md D1", "demo", "claude/buildbox/2026-10-21-x", "no live session for demo@claude/buildbox/2026-10-21-x:docs/d.md D1 \u2014 the run would start here"], ["guarded \u2014 open it", "transcripts", null, null]]' \
    "the lookout's open cards: doc, branch and why in the owner's column; a guarded repo's card keeps its column and nothing else"
  check "$("$HM" $BOARD --json | lc)" "[]" "no lookout cards without keel's status (PLAN_NO_MEMO): none, the board renders"
  printf '#!/usr/bin/env python3\nimport sys\nsys.exit(2)\n' > "$T/keelold"
  check "$(PLAN_KEEL="$T/keelold" "$HM" $BOARD --json | lc)" "[]" "a keel without --json (exit 2, no output): no cards, the board renders"
  # S6 landing review 19: the peer's lookout cards, read over the stall cards' ssh road (STALLS_PEERS,
  # STALLS_SSH), their why led by the host; once the peer answered, this Mac's card that only says the
  # peer's own lookout acts is dropped
  printf '#!/usr/bin/env python3\nimport json\nprint(json.dumps({"cards": [{"doc": "demo@claude/buildbox/2026-10-21-z:docs/z.md", "items": ["D2"], "card": "another host\x27s branch: its own lookout starts the run"}, {"doc": "demo@claude/laptop/2026-10-21-w:docs/w.md", "items": [], "card": "here"}]}))\n' > "$T/keelhere"
  printf '#!/bin/sh\nfor a; do last=$a; done\n[ "$last" = "python3 -" ] || exit 9\ngrep -q %s - || exit 8\necho %s\n' "'common.tool(\"keel\")'" \
    "'{\"armed\": true, \"cards\": [{\"doc\": \"demo@claude/buildbox/2026-10-21-z:docs/z.md\", \"items\": [\"D2\"], \"card\": \"no live session — the run would start here\"}, {\"doc\": \"demo@claude/laptop/2026-10-21-w:docs/w.md\", \"items\": [], \"card\": \"on another host\x27s branch, pushed within 24h — its lookout acts\"}]}'" > "$T/ssh-lookout"
  printf '#!/bin/sh\necho %s\n' "'{\"armed\": false, \"cards\": [], \"last_pass\": null}'" > "$T/ssh-lookout-off"
  printf '#!/bin/sh\nexit 255\n' > "$T/ssh-lookout-down"
  printf '#!/bin/sh\nfor a; do last=$a; done\nexec sh -c "$last"\n' > "$T/ssh-lookout-run"
  chmod +x "$T/keelhere" "$T"/ssh-lookout*
  check "$(STALLS_PEERS=buildbox=fake STALLS_SSH="$T/ssh-lookout" PLAN_KEEL="$T/keelhere" "$HM" $BOARD --json | lc)" \
    '[["docs/w.md", "demo", "claude/laptop/2026-10-21-w", "here"], ["docs/z.md D2", "demo", "claude/buildbox/2026-10-21-z", "buildbox: no live session \u2014 the run would start here"]]' \
    "the peer's lookout cards on the board, led by its host; this Mac's 'its own lookout' card for that branch gives way"
  check "$(STALLS_PEERS=buildbox=fake STALLS_SSH="$T/ssh-lookout-off" PLAN_KEEL="$T/keelhere" "$HM" $BOARD --json | lc | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))')" "2" \
    "  S11b finish review: a disarmed peer answers with no cards and replaces none of this Mac's"
  check "$(STALLS_PEERS=buildbox=fake STALLS_SSH="$T/ssh-lookout" PLAN_KEEL="$T/keelhere" "$HM" $BOARD --json | grep -c 'its lookout acts')" "0" \
    "  …and the peer's own 'its lookout acts' card, about this Mac's branch, is never shown"
  check "$(STALLS_PEERS=buildbox=fake STALLS_SSH="$T/ssh-lookout-down" PLAN_KEEL="$T/keelhere" "$HM" $BOARD --json | lc | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))')" "2" \
    "  a peer that does not answer: this Mac's cards, both kept, and the board renders"
  check "$(STALLS_PEERS=buildbox=fake STALLS_SSH="$T/ssh-lookout" PLAN_NO_PEER=1 PLAN_KEEL="$T/keelhere" "$HM" $BOARD --json | lc | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))')" "2" \
    "  PLAN_NO_PEER: no ssh"
  check "$(STALLS_PEERS=buildbox=fake STALLS_SSH="$T/ssh-lookout-run" PLAN_HOST=laptop python3 -c "import sys; sys.path.insert(0, '$B'); import helm_render as h; print(h.peer_lookout_rows())")" \
    "{'buildbox': {'cards': [], 'armed': False}}" "  the probe itself, run here as the peer would: it finds keel through the core and reads its (empty) status"
  out=$("$HM" $BOARD); has "$out" "overview:" "overview renders a page"
  echo "skipper-modes S5: WAITING cards from both Macs, a peer's prompts, links on ask cards, held dnd items"
  printf '{"repos": {"regatta": {"github": "o/regatta"}}}\n' > "$T/s5-repos.json"
  mkdir -p "$T/s5-sheep"; printf '{"regatta@claude/t:docs/d.md": {"url": "https://spacesheep.dev/s/abc"}}\n' > "$T/s5-sheep/sheep.json"
  s5=$(CLAUDE_REPOS_JSON="$T/s5-repos.json" MEMO_SHEEP_STATE="$T/s5-sheep" python3 - "$B" <<'PY'
import json, sys
sys.path.insert(0, sys.argv[1])
import helm_render as r
judged = {"waiting": [{"host": "testhost", "session_id": "s1", "cwd": "/x/projects/regatta/.claude/worktrees/t", "branch": "claude/t", "since": 5},
                      {"host": "buildbox", "session_id": "s2", "cwd": "/y/projects/regatta", "branch": "claude/u"},
                      {"host": "buildbox", "session_id": "s4", "cwd": "/y/projects/transcripts", "branch": "claude/p"}],
          "prompts": [{"host": "buildbox", "session_id": "s3", "cwd": "/y/projects/regatta", "state": "input-required"}]}
cs = r.waiting_cards(judged, here="testhost")
print([(c["kind"], c["title"], c.get("repo"), c.get("by"), c.get("url"), c["column"]) for c in cs[:2]])
print(cs[2].get("guarded"), cs[3]["kind"], cs[3]["title"], cs[3].get("by"))
print(r.ask_links("regatta", "claude/t", "docs/d.md"), r.ask_links("regatta", None, "docs/d.md"))
PY
)
  check "$(echo "$s5" | sed -n 1p)" "[('waiting', 'waiting on Sam', 'regatta', 'testhost', 'vscode://anthropic.claude-code/open?session=s1', 'Needs Sam'), ('waiting', 'waiting on Sam', 'regatta', 'buildbox', 'https://github.com/o/regatta/tree/claude/u', 'Needs Sam')]" \
    "a WAITING card is the repo, 'waiting on Sam' and a link: this Mac's session opens in VS Code, a peer's branch on GitHub"
  check "$(echo "$s5" | sed -n 2p)" "True permission waits at a prompt buildbox" "  a guarded session's card is guarded; a peer's permission prompt is a card"
  check "$(echo "$s5" | sed -n 3p)" "('https://spacesheep.dev/s/abc', 'https://github.com/o/regatta/blob/claude/t/docs/d.md') (None, None)" \
    "an ask card's links: the course page its pin holds, GitHub's read view; none guessed without a branch"
  echo "skipper-modes S3b: a held landing is a card naming its class"
  HR="$T/held-projects"; mkdir -p "$HR"; git init -q -b main "$HR/regatta"; git -C "$HR/regatta" commit -q --allow-empty -m i
  git -C "$HR/regatta" branch claude/h1; git -C "$HR/regatta" branch claude/h2
  mkdir -p "$HR/regatta/.git/claude"; NOWISO=$(python3 -c 'import datetime; print(datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"))')
  printf '%s stopped claude/h1 held held (money in the diff (docs/x.md: $40)): ⚠ step 11 — held: PR #12 waits for Sam'"'"'s tap\n%s stopped claude/h2 held held (mode ask — nothing lands by itself): ⚠ step 11 — held\n%s launched claude/h2 #13\n%s stopped claude/gone held held (a physical repo): x\n' \
    "$NOWISO" "$NOWISO" "$NOWISO" "$NOWISO" > "$HR/regatta/.git/claude/autofinished"
  hc=$(CLAUDE_REPOS_JSON="$T/s5-repos.json" python3 - "$B" "$HR" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import helm_render as r
print([(c["kind"], c["title"], c["column"], c.get("held"), c.get("url")) for c in r.held_cards(sys.argv[2])])
PY
)
  check "$hc" "[('held', 'held at a ready PR — claude/h1', 'Needs Sam', 'money in the diff (docs/x.md: \$40)', 'https://github.com/o/regatta/pull/12')]" \
    "  one card per held branch, its class and its PR; a branch launched since, or gone, has none"
  fx=$(python3 - "$B" <<'PY'
import sys, types
sys.path.insert(0, sys.argv[1])
import stalls
recs = [{"session_id": "a1", "state": "idle", "cwd": "/p/r", "branch": "claude/a", "native": {}},
        {"session_id": "r1", "state": "idle", "cwd": "/p/r", "native": {"run": "x.json"}},
        {"session_id": "b1", "state": "input-required", "cwd": "/p/s", "native": {}}]
texts = {"a1": "Done.\nSAM, THIS SESSION IS WAITING FOR YOU — D2 in docs/x.md", "r1": "SAM, THIS SESSION IS WAITING FOR YOU — x", "b1": "Working."}
ad = types.SimpleNamespace(list=lambda: recs, status=lambda *a, **k: None, last_reply=lambda sid: {"text": texts[sid]})
d = stalls.facts([], ad, lambda st: False, lambda st: True, ())
print([w["session_id"] for w in d["waiting"]], [x["state"] for x in d["live"]])
PY
)
  check "$fx" "['a1'] ['idle', 'idle', 'input-required']" "stalls' facts: a session no run owns, ending on the WAITING line, is waiting; a run's is its stall's (S6)"
  fx=$(python3 - "$B" <<'PY'
import sys, types
sys.path.insert(0, sys.argv[1])
import stalls
W = "THIS SESSION IS WAITING FOR YOU — D2"
recs = [{"session_id": s, "state": "idle", "cwd": c, "native": {}} for s, c in
        (("link", "/p/r"), ("bold", "/p/r"), ("quoted", "/p/r"), ("guard", "/p/secret/.claude/worktrees/t"), ("other", "/p/r"))]
texts = {"link": "Done.\nOWNER, " + W + "\n[course](https://x) | [github](https://y) — [d.md](/p/d.md#L1)",
         "bold": "**OWNER, " + W + "**", "quoted": "OWNER, " + W + "\nand then more prose",
         "guard": "OWNER, " + W, "other": "SOMEONE ELSE, " + W}
ad = types.SimpleNamespace(list=lambda: recs, status=lambda *a, **k: None, last_reply=lambda sid: {"text": texts[sid]})
print([w["session_id"] for w in stalls.facts([], ad, lambda st: False, lambda st: True, ("secret",), "OWNER, THIS SESSION IS WAITING FOR YOU — ")["waiting"]],
      [w["session_id"] for w in stalls.facts([], ad, lambda st: False, lambda st: True, (), "THIS SESSION IS WAITING FOR YOU — ")["waiting"]])
PY
)
  check "$fx" "['link', 'bold'] ['link', 'bold', 'guard', 'other']" \
    "  the WAITING line as common.ending reads it: link lines after it, markup around it; a guarded repo's reply unread; the owner's address from config (landing review 15, 16)"
  pb=$(ASK_BOARD_CMD="echo overview: /x/index.html — 3 need Sam" python3 -c 'import sys; from importlib.machinery import SourceFileLoader; SourceFileLoader("ask_mod", sys.argv[1]).load_module().poll_board()' "$B/ask" 2>&1)
  check "$pb" "ask poll: board — overview: /x/index.html — 3 need Sam" "ask poll renders and deploys the board (its 5-minute job)"
  pb=$(ASK_BOARD_CMD="false" python3 -c 'import sys; from importlib.machinery import SourceFileLoader; SourceFileLoader("ask_mod", sys.argv[1]).load_module().poll_board()' "$B/ask" 2>&1); check "$?" "0" "  a board that fails is one line, never the poll's"
  has "$pb" "ask poll: board failed" "  …which says so"
  echo "finding 15: the week's line from tier_check.weekly(parsed .claude.json)"
  echo "{\"cachedUsageUtilization\": {\"fetchedAtMs\": $(( $(date +%s) * 1000 )), \"utilization\": {\"limits\": [{\"kind\": \"weekly_all\", \"percent\": 41, \"resets_at\": \"2030-01-06T12:00:00+00:00\"}]}}}" > "$T/cj.json"
  wk=$(CLAUDE_TIER_CLAUDE_JSON="$T/cj.json" CLAUDE_TIER_APP_HISTORY="$T/none.json" "$HM" $BOARD --json | python3 -c "import json,sys; print(json.load(sys.stdin)['header']['week'])")
  has "$wk" "week 41% used" "the header carries the week's percent"
  has "$wk" "sampled" "  and how old it is"
  has "$(cat "$T/cache/overview/index.html")" "<svg" "the timeline is drawn (B7)"
  echo "B0: run records as dispatch wrote them before 2026-10-11, every value a string"
  R="$HOME/Library/Logs/claude-weekly/run-seed-runs"; mkdir -p "$R"
  printf '{"mode":"headless","repo":"/x/demo","topic":"strstart","pid":"%s","started":"%s"}' "$$" "$(date +%s)" > "$R/a.json"
  printf '{"mode":"headless","repo":"/x/demo","topic":"intstart","pid":%s,"started":%s}' "$$" "$(date +%s)" > "$R/b.json"
  printf '{"mode":"rc","repo":"/x/demo","topic":"oldstr","started":"1000"}' > "$R/c.json"
  printf '{"mode":"rc","repo":"/x/demo","topic":"nostart"}' > "$R/d.json"
  printf '{"mode":"rc","repo":"/x/demo","topic":"badstart","started":"soon"}' > "$R/e.json"
  printf '[]' > "$R/f.json"
  # no end written, but its pid is gone (a crash, a reboot): not running, so no card
  printf '{"mode":"headless","repo":"/x/demo","topic":"crashed","pid":99999999,"started":%s}' "$(date +%s)" > "$R/g.json"
  # a pid past 2**31: os.kill raises OverflowError inside same(), which must not take the board down
  printf '{"mode":"headless","repo":"/x/demo","topic":"hugepid","pid":99999999999,"started":%s}' "$(date +%s)" > "$R/h.json"
  # the ask guard's card in a guarded repo is redacted like every other guarded card
  printf '{"mode":"rc","repo":"/x/transcripts","topic":"secret","ask_guard":"failed: x","started":%s}' "$(date +%s)" > "$R/i.json"
  ov=$("$HM" $BOARD --json 2>"$T/ov.err"); check "$?" "0" "overview runs over a record whose start is a digit string (it crashed: 13 of 82 on the laptop)"
  check "$(echo "$ov" | python3 -c "import json,sys; print(sorted(c['title'] for col in json.load(sys.stdin)['columns'] for c in col['cards'] if c['title'].endswith('(no skipper)')))" 2>&1)" \
    "['intstart (no skipper)', 'strstart (no skipper)']" "  a string start reads as the number it is; an old, missing or unreadable one is no card, nor a run whose pid is gone"
  check "$(echo "$ov" | python3 -c "import json,sys; print([c['title'] for col in json.load(sys.stdin)['columns'] for c in col['cards'] if 'secret' in c['title']])" 2>&1)" \
    "[]" "  an ask-guard card from a guarded repo carries no topic"
  check "$(grep -o 'INTS = (.*)' "$(src dispatch)")" "$(grep -o 'INTS = (.*)' "$(src dispatch-rc)")" "dispatch's record() and dispatch-rc's typed() type the same fields"
  rm -rf "$R"

  echo "B1: stalls — S1–S7 from records, the registry, autofinished, the plan store and the poll cache"
  # Fixtures shaped on the real ones of P1, P2 and P4 (chain-manager section 3), ids changed: a repo
  # with the branches the records name, transcripts, registry files, autofinished lines, a plan, and
  # a stubbed ssh that runs the probe against a second HOME standing in for buildbox.
  now=$(date +%s); R="$HOME/Library/Logs/claude-weekly/run-seed-runs"; mkdir -p "$R" "$HOME/.claude/projects/-t"
  D="$T/repos/demo"; mkdir -p "$D"; git -C "$D" init -q -b main; git -C "$D" commit -q --allow-empty -m x
  for b in gone-step pending-step cap-step parked-step asked-step done-step relay-step ended-step lifetime-step live-wait live-work unsure-step gate-launch quote-launch; do
    git -C "$D" branch "claude/t/2026-10-14-$b"; done
  git -C "$D" worktree add -q "$D/.claude/worktrees/net" -b claude/t/2026-10-14-net-launch 2>/dev/null
  git -C "$D" worktree add -q "$D/.claude/worktrees/moved" -b claude/t/2026-10-14-moved-launch 2>/dev/null
  P="$T/repos/transcripts"; mkdir -p "$P"; git -C "$P" init -q -b main; git -C "$P" commit -q --allow-empty -m x; git -C "$P" branch claude/t/2026-10-14-taxes-step
  say() {  # say SESSION TEXT: a transcript whose last assistant entry is TEXT
    python3 - "$HOME/.claude/projects/-t/$1.jsonl" "$2" "${3:-}" <<'PY'
import json, sys
import time; e = {"type": "assistant", "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() - 7200)), "message": {"content": [{"type": "text", "text": sys.argv[2]}]}}
if sys.argv[3:] and sys.argv[3] == "api":
    e["isApiErrorMessage"] = True
open(sys.argv[1], "w").write(json.dumps(e) + "\n")
PY
  }
  rec() {  # rec FILE TOPIC KEY=VALUE...: a run record (values JSON, else strings)
    python3 - "$R/$1" "$2" "$D" "${@:3}" <<'PY'
import json, sys
path, topic, repo = sys.argv[1:4]
st = {"mode": "rc", "repo": repo, "topic": topic, "branch": "claude/t/2026-10-14-" + topic, "session": "sid-" + topic}
for kv in sys.argv[4:]:
    k, v = kv.split("=", 1)
    try:
        st[k] = json.loads(v)
    except ValueError:
        st[k] = v
open(path, "w").write(json.dumps(st))
PY
  }
  WAIT="SAM, THIS SESSION IS WAITING FOR YOU"
  # S1: gone without an end — the newer of two records of one topic (the older one is superseded)
  rec 1-gone-old.json gone-step started=$((now-90000)) ended=$((now-80000)) "end_reason=tidied: its claude was gone"
  rec 2-gone.json gone-step started=$((now-7200)) pid=99999999 proc_start=x depth=1 brief_blob='"b10b"'
  say sid-gone-step "Passed on rerun, so something is flaky. Looping it a few times to catch which test."
  # S2: ended on dispatch's run-cap WAITING line
  rec 3-cap.json cap-step started=$((now-7200)) ended=$((now-3600)) "end_reason=idle 60 min" depth=2
  say sid-cap-step "Step done.
$WAIT — the next step waits for a run to end (dispatch --next once one has)"
  # S6: a parked WAITING line nobody polls; the same line on a branch with an open D-item is an ask, not a stall
  rec 4-parked.json parked-step started=$((now-7200)) ended=$((now-3600)) "end_reason=idle 60 min"
  say sid-parked-step "$WAIT — add the env value, then /finish this branch."
  rec 5-asked.json asked-step started=$((now-7200)) ended=$((now-3600)) "end_reason=idle 60 min"
  say sid-asked-step "$WAIT — D1 in docs/x.md"
  mkdir -p "$T/askcache"
  printf '{"t": %s, "asks": [{"repo": "demo", "branch": "claude/t/2026-10-14-asked-step", "rel": "docs/x.md", "item": "D1", "title": "x"}]}' "$now" > "$T/askcache/asks.json"
  # not stalls: a done closing line, a person's --end, a branch that launched, a live working run
  rec 6-done.json done-step started=$((now-7200)) ended=$((now-3600)) "end_reason=tidied: its claude was gone"
  say sid-done-step "Launched.
SAM, IT'S FINE — THIS SESSION IS REALLY DONE. YOU HAVEN'T FORGOTTEN ANYTHING."
  rec 7-ended.json ended-step started=$((now-7200)) ended=$((now-3600)) "end_reason=ended by dispatch --end (was idle)"
  rec 8-launched.json launched-step started=$((now-7200)) pid=99999999 proc_start=x
  rec 9-work.json live-work mode=headless pid=$$ started=$((now-600))
  printf '{"pid": %s, "sessionId": "sid-live-work", "status": "busy", "statusUpdatedAt": %s000}' "$$" "$now" > "$T/sess/work.json"
  # S6 live: a run at a permission prompt (the registry's `waiting`) — its permission card gives way to the stall's
  rec 10-wait.json live-wait mode=headless pid=$$ started=$((now-600))
  printf '{"pid": %s, "sessionId": "sid-live-wait", "status": "waiting", "waitingFor": "permission to run Bash", "statusUpdatedAt": %s000}' "$$" "$now" > "$T/sess/wait.json"
  # S6 orphaned relay: RELAYED, its manager not in any registry
  rec 11-relay.json relay-step started=$((now-7200)) ended=$((now-3600)) "end_reason=idle 60 min" manager=mgr-gone
  say sid-relay-step "RELAYED TO mgr-gone — D1 in docs/x.md"
  # S1: ended on WAITING FOR SOMETHING and nothing picked it up again (2026-10-20)
  rec 13-pending.json pending-step started=$((now-7200)) ended=$((now-3600)) "end_reason=idle 60 min"
  say sid-pending-step "SAM, THIS SESSION IS WAITING FOR SOMETHING — the two reviewers"
  # unsure: ended idle, no closing line — B3's classifier's input, never a card
  rec 12-unsure.json unsure-step started=$((now-7200)) ended=$((now-3600)) "end_reason=idle 60 min"
  say sid-unsure-step "- I didn't run dispatch --next, because the brief names no next step."
  # guarded (K6): gone in transcripts, its text never read and never on the board
  python3 - "$R/13-taxes.json" "$P" "$now" <<'PY'
import json, sys
open(sys.argv[1], "w").write(json.dumps({"mode": "rc", "repo": sys.argv[2], "topic": "taxes-step", "branch": "claude/t/2026-10-14-taxes-step",
    "session": "sid-taxes", "started": int(sys.argv[3]) - 7200, "pid": 99999999, "proc_start": "x"}))
PY
  say sid-taxes "IBAN 5555 is the account."
  # S3 on "buildbox": its own HOME, read through the stubbed ssh; `started` a digit string, as dispatch wrote before B2
  IS="$T/buildbox"; mkdir -p "$IS/Library/Logs/claude-weekly/run-seed-runs"
  printf '{"mode":"rc","repo":"%s","topic":"lifetime-step","branch":"claude/t/2026-10-14-lifetime-step","session":"sid-life","started":"%s","ended":"%s","end_reason":"max lifetime 8.0 h"}' \
    "$D" "$((now-40000))" "$((now-10000))" > "$IS/Library/Logs/claude-weekly/run-seed-runs/x.json"
  printf '#!/bin/sh\nfor a; do last=$a; done\nHOME="%s" exec sh -c "$last"\n' "$IS" > "$T/ssh-ok"
  printf '#!/bin/sh\necho "ssh: connect to host buildbox port 22: Operation timed out" >&2; exit 255\n' > "$T/ssh-down"
  chmod +x "$T/ssh-ok" "$T/ssh-down"
  # S4 and S5: autofinished — a network stop with its worktree on the stopped tip; a G4 stop; a WAITING line quoting an API error (R4)
  tip=$(git -C "$D" rev-parse claude/t/2026-10-14-net-launch); mkdir -p "$D/.git/worktrees/net/claude" "$D/.git/claude"
  printf '{"tip": "%s", "ended": "2026-10-14T01:00:00-07:00", "outcome": "stopped", "gate": "no-landing", "by": "sweep"}' "$tip" > "$D/.git/worktrees/net/claude/autofinish.json"
  # a network stop whose branch moved on since: no relaunch on a tip nobody stopped at (it is raised, S5)
  mkdir -p "$D/.git/worktrees/moved/claude"
  printf '{"tip": "%s", "ended": "2026-10-14T01:00:00-07:00", "outcome": "stopped", "gate": "no-landing", "by": "sweep"}' "1111111111111111111111111111111111111111" > "$D/.git/worktrees/moved/claude/autofinish.json"
  { echo "2026-10-13T00:00:00-07:00 stopped claude/t/2026-10-14-net-launch G1 ⚠ an earlier stop"
    echo "2026-10-14T01:00:00-07:00 stopped claude/t/2026-10-14-net-launch no-landing API Error: Connection refused — a firewall or proxy may be blocking it (ECONNREFUSED)"
    echo "2026-10-14T01:10:00-07:00 stopped claude/t/2026-10-14-gate-launch G4 ⚠ step 4: I stopped before launching."
    echo "2026-10-14T01:20:00-07:00 stopped claude/t/2026-10-14-quote-launch no-landing $WAIT — API Error: retry it by hand"
    echo "2026-10-14T01:30:00-07:00 stopped claude/t/2026-10-14-gone-launch no-landing API Error: Your computer went to sleep mid-response."
    echo "2026-10-14T01:40:00-07:00 stopped claude/t/2026-10-14-moved-launch no-landing API Error: Your computer went to sleep mid-response."
  } > "$D/.git/claude/autofinished"
  # S7: a plan whose task b waits on a, done two hours ago, and nobody started b
  "$HM" $SHIP s7plan --id s7 > /dev/null; "$HM" task s7 a > /dev/null; "$HM" task s7 b --title "Step b" > /dev/null
  "$HM" dep s7 b --on a > /dev/null; PLAN_NO_RENDER=1 "$HM" report s7 --task a --status done > /dev/null
  python3 - "$T/plans/s7/events.jsonl" "$now" <<'PY'
import json, sys
p, now = sys.argv[1], float(sys.argv[2])
ls = [dict(json.loads(l), t=now - 7200) for l in open(p) if l.strip()]
open(p, "w").write("".join(json.dumps(e) + "\n" for e in ls))
PY
  export STALLS_REPOS="$D"
  sj=$(STALLS_PEERS=buildbox=fake STALLS_SSH="$T/ssh-ok" python3 "$B/stalls.py" --json)
  got() { echo "$sj" | python3 -c "import json,sys; d=json.load(sys.stdin); $1"; }
  check "$(got "print(sorted((s['class'], s['topic']) for s in d['stalls']))")" \
    "[('S1', 'gone-step'), ('S1', 'pending-step'), ('S1', 'taxes-step'), ('S2', 'cap-step'), ('S3', 'lifetime-step'), ('S4', 'net-launch'), ('S5', 'gate-launch'), ('S5', 'moved-launch'), ('S5', 'quote-launch'), ('S6', 'live-wait'), ('S6', 'parked-step'), ('S6', 'relay-step'), ('S7', 'b')]" \
    "one stall per class's fixture; done, --end, launched, working, asked, unsure and the sleeping branch that is gone are none"
  check "$(got "s=[x for x in d['stalls'] if x['topic']=='gone-step'][0]; print(s['run'], s['action'], s['key'], s['column'], s['depth'])")" \
    "2-gone.json retry ['testhost', 'demo', 'gone-step', 'b10b'] Blocked 1" "  S1: the newer record, A1, keyed (host, repo, topic, brief blob), Blocked"
  has "$(got "print([x['title'] for x in d['stalls'] if x['topic']=='gone-step'][0])")" "gone-step · S1 gone 2h" "  its title says how long"
  check "$(got "s=[x for x in d['stalls'] if x['class']=='S2'][0]; print(s['action'], any(e.startswith('runs busy now: ') for e in s['evidence']))")" "start True" \
    "  S2: start, with dispatch-rc live --no-reap's count"
  check "$(got "s=[x for x in d['stalls'] if x['class']=='S3'][0]; print(s['host'], s['action'], s['column'], s['since'] > 0)")" "buildbox raise Needs Sam True" \
    "  S3: read on buildbox through ssh, its digit-string start typed, raised"
  check "$(got "s=[x for x in d['stalls'] if x['class']=='S4'][0]; print(s['action'], s['key'][1], s['key'][2] == '$tip', s['worktree'].endswith('/net'))")" \
    "relaunch claude/t/2026-10-14-net-launch True True" "  S4: relaunch, keyed (host, branch, tip), the last stop of its branch counts"
  check "$(got "print(sorted(x['rule'] for x in d['stalls'] if x['class']=='S5'))")" "['S4 stop, but the tip moved since (1111111 → ${tip:0:7})', 'WAITING line', 'gate G4']" "  S5: a gate; a WAITING line that quotes an API error is no S4 (R4); nor a network stop on a tip that moved"
  check "$(got "print(sorted(x['rule'] for x in d['stalls'] if x['class']=='S6'))")" "['closing line: RELAYED, its manager gone', 'closing line: WAITING', 'live: waiting']" \
    "  S6: a parked WAITING line, a permission prompt, an orphaned relay"
  check "$(got "s=[x for x in d['stalls'] if x['class']=='S7'][0]; print(s['key'], s['raise_to'], s['column'])")" "['testhost', 's7', 'b'] owner Needs Sam" \
    "  S7: keyed (host, plan, task), to the owner while its manager is not live"
  check "$(got "print([(u['topic'], u['action'], u['class']) for u in d['unsure']])")" "[('unsure-step', 'classify', None)]" \
    "  no closing line: unsure, shaped for B3's classifier, never a stall"
  hasnt "$sj" "IBAN 5555" "  a guarded run's reply is never read"
  printf '{"pid": %s, "sessionId": "mgr-1", "status": "busy", "statusUpdatedAt": %s000}' "$$" "$now" > "$T/sess/mgr.json"
  check "$(python3 "$B/stalls.py" --json | python3 -c "import json,sys; s=[x for x in json.load(sys.stdin)['stalls'] if x['class']=='S7'][0]; print(s['raise_to'], s['column'])")" \
    "skipper Blocked" "  S7 goes to its skipper (raise_to, rename S5) while that session is live"
  rm "$T/sess/mgr.json"
  ov=$(STALLS_PEERS=buildbox=fake STALLS_SSH="$T/ssh-ok" "$HM" $BOARD --json)
  check "$(echo "$ov" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['header']['stalled'], sum(c['kind']=='stall' for col in d['columns'] for c in col['cards']))")" "13 13" \
    "overview: one card per stall, the count in its header"
  check "$(echo "$ov" | python3 -c "import json,sys; d=json.load(sys.stdin); print(sorted((c['stall'], col['name']) for col in d['columns'] for c in col['cards'] if c['kind']=='stall' and c['stall'] in ('S1','S4','S5')))")" \
    "[('S1', 'Blocked'), ('S1', 'Blocked'), ('S1', 'Blocked'), ('S4', 'Blocked'), ('S5', 'Needs Sam'), ('S5', 'Needs Sam'), ('S5', 'Needs Sam')]" "  Blocked for what the tick acts on, Needs Sam for a raise"
  check "$(echo "$ov" | python3 -c "import json,sys; d=json.load(sys.stdin); print([c['kind'] for col in d['columns'] for c in col['cards'] if c.get('session')=='sid-live-wait'])")" \
    "['stall']" "  a permission prompt's card gives way to its stall's: one card per run"
  hasnt "$ov" "IBAN 5555" "  a guarded stall carries no text (K6)"
  hasnt "$ov" "taxes-step" "  nor its topic"
  check "$(echo "$ov" | python3 -c "import json,sys; d=json.load(sys.stdin); print(sum(c['title']=='guarded — open it' and c['kind']=='stall' for col in d['columns'] for c in col['cards']))")" "1" \
    "  it keeps its column"
  snap() { python3 - "$T" <<'PY'
import os, sys
out = []
for root, dirs, files in os.walk(sys.argv[1]):
    # Apple's python3 writes its bytecode cache under $HOME/Library/Caches/com.apple.python (HOME is
    # the test's root): the interpreter's, not the tick's, and written on any first import of a module
    dirs[:] = [d for d in dirs if d != "com.apple.python"]
    for f in files:
        p = os.path.join(root, f)
        try:
            s = os.stat(p)
        except OSError:
            continue
        out.append("%s %d %d" % (p, s.st_mtime_ns, s.st_size))
print("\n".join(sorted(out)))
PY
  }
  before=$(snap)
  tick=$(STALLS_PEERS=buildbox=fake STALLS_SSH="$T/ssh-ok" "$HM" tick --dry-run)
  has "$tick" "helm tick: dry-run — --dry-run: nothing called, nothing written" "tick --dry-run says it is dry"
  has "$tick" "S1 testhost demo gone-step: would wait — redispatch 1 of 2 due" "  and what it would do per stall: a first sight waits out the backoff"
  has "$tick" "S4 testhost demo net-launch: would wait — relaunch 1 of 2 due" "  a launch's relaunch"
  has "$tick" "? testhost demo unsure-step: would raise — no depth recorded" "  an unsure run with no depth is raised before any classifier"
  has "$tick" "13 stalls, 1 unsure — 14 dry (would: 11 raise, 3 wait); hosts buildbox, testhost;" "  a count line"
  has "$tick" "(not written)" "  that says nothing was written"
  check "$(STALLS_PEERS=buildbox=fake STALLS_SSH="$T/ssh-ok" "$HM" tick --dry-run --json | python3 -c "import json,sys; r=json.load(sys.stdin); print(len(r['stalls']), len(r['unsure']), r['dry'], sorted(r['stalls'][0]))")" \
    "13 1 True ['branch', 'class', 'host', 'repo', 'topic']" "  --json carries what ask poll's cache reads: stalls, unsure, dry (B4)"
  check "$(snap)" "$before" "  and changes nothing: no file under the test's root written or touched"
  check "$(STALLS_PEERS=buildbox=fake STALLS_SSH="$T/ssh-down" STALLS_LOG="$T/ssh-down.jsonl" "$HM" tick | grep -c '^buildbox: unreachable')" "1" \
    "an unreachable buildbox is one line, and the tick goes on"
  check "$(grep 'NET_RE = re.compile' "$B/stalls.py" | sed 's/^NET_RE/X/')" "$(grep 'S4_RE = re.compile' "$(src autofinish-run)" | sed 's/^S4_RE/X/')" \
    "B3: autofinish-run's S4_RE is stalls.py's NET_RE, character for character"
  check "$(grep 'LOGIN_RE = re.compile' "$B/stalls.py")" "$(grep 'LOGIN_RE = re.compile' "$(src autofinish-run)")" \
    "  and its LOGIN_RE is stalls.py's"

  echo "B3: the tick's actions — the switch, the dry hours, the gates, two retries with their backoff, the classifier"
  # Stubs: dispatch and autofinish-run record their argv and the chain's env; bin/account answers
  # ok, none or tight; the classifier is bin/gate's claude adapter on a stub claude (no model call).
  # The clock is STALLS_NOW, stepped; stalls.py judges on the real one (records dated by it).
  S="$T/stubs"; X="$T/b3"; mkdir -p "$S" "$X/dlogs" "$X/af" "$HOME/projects/demo"
  cat > "$S/tool" <<'PY'
#!/usr/bin/env python3
import json, os, sys
calls = os.environ["STUB_CALLS"]
env = {k: v for k, v in os.environ.items() if k.startswith("DISPATCH_") or k in ("CLAUDE_CODE_SESSION_ID", "CLAUDECODE")}
with open(calls, "a") as f:
    f.write(json.dumps({"tool": os.path.basename(sys.argv[0]), "argv": sys.argv[1:], "env": env}) + "\n")
n = sum(1 for _ in open(calls))
log = os.path.join(os.environ["STUB_LOGDIR"], "d%d.log" % n)
open(log, "a").close()
print("started here: claude is running %s (opus high) in screen run-x; dispatch --status; log %s" % (sys.argv[1], log))
sys.stdout.flush()
import time; time.sleep(float(os.environ.get("STUB_SLEEP") or 0))
sys.exit(int(os.environ.get("STUB_RC") or 0))
PY
  cp "$S/tool" "$S/dispatch"; cp "$S/tool" "$S/autofinish-run"
  cat > "$S/account" <<'PY'
#!/usr/bin/env python3
import json, os, sys
try:
    mode = open(os.environ["STUB_ACCT"]).read().strip()
except OSError:
    mode = "ok"
if sys.argv[1] == "pick":
    if mode == "none":
        print(json.dumps({"skipped": [["claude-a", "its week is at the ceiling"]]})); sys.exit(3)
    print(json.dumps({"account": "claude-a", "primary": mode == "tight", "reason": "first in the walk"})); sys.exit(0)
if sys.argv[1] == "limits":
    print(json.dumps([{"limits": {"seven_day": 99}}])); sys.exit(0)
sys.exit(2)
PY
  cat > "$S/claude" <<'PY'
#!/usr/bin/env python3
import json, os, re, sys
prompt = sys.stdin.read()
with open(os.environ["STUB_CLAUDE_CALLS"], "a") as f:
    f.write(json.dumps({"prompt": prompt}) + "\n")
ids = re.findall(r"^(u\d+): ", prompt, re.M)
print(json.dumps({"structured_output": {i: os.environ.get("STUB_CLAUDE_ANSWER") or "yes" for i in ids}, "total_cost_usd": 0.0, "is_error": False}))
PY
  chmod +x "$S"/*
  # the gate's table: the core's defaults plus the tick's site (the overlay's table carries it on the
  # owner's Macs), in the suite's own config dir — the classifier must not hinge on the caller's
  python3 - "$REGATTA_HOME/modules/regatta/settings/models.json" "$REGATTA_CONFIG/regatta/models.json" <<'PY'
import json, sys
t = json.load(open(sys.argv[1]))
t["sites"]["plan.stall"] = {"kind": "classify", "provider": "jev", "threshold": 0.7, "when_off": "skip",
                            "note": "the tick's classifier (bin/stalls_tick.py), as the overlay's table has it"}
json.dump(t, open(sys.argv[2], "w"), indent=1)
PY
  export STALLS_LOG="$X/stalls.jsonl" STALLS_STATE_DIR="$X/state" STALLS_DISPATCH="$S/dispatch" STALLS_AUTOFINISH_RUN="$S/autofinish-run" \
         AUTOFINISH_ACCOUNT="$S/account" STUB_ACCT="$X/acct" STUB_CALLS="$X/calls" STUB_LOGDIR="$X/dlogs" AUTOFINISH_STATE_DIR="$X/af" \
         GATE_PLAN_STALL_PROVIDER=claude CLAUDE_BIN="$S/claude" STUB_CLAUDE_CALLS="$X/claude-calls" GATE_LOG="$X/gate.jsonl" \
         DISPATCH_MAX_RUNS=9 STALLS_PEERS=buildbox=fake STALLS_SSH="$T/ssh-ok" PLAN_NO_RENDER=1
  # a managed S1 (its manager's road on the record), a gone step whose worktree another session's
  # lock holds, and a second unsure run, this one with a depth: the classifier's one item
  "$HM" $SHIP b3 --id b3p > /dev/null
  rec 2-gone.json gone-step started=$((now-7200)) pid=99999999 proc_start=x depth=1 brief_blob='"b10b"' \
    manager=mgr-b3 manager_host=testhost manager_account=/x/acct plan=b3p plan_space=b3-space
  git -C "$D" worktree add -q "$D/.claude/worktrees/locked" -b claude/t/2026-10-14-locked-step 2>/dev/null
  rec 14-locked.json locked-step started=$((now-7200)) pid=99999999 proc_start=x depth=1 wt="$D/.claude/worktrees/locked"
  mkdir -p "$D/.git/worktrees/locked/claude"
  printf '{"session": "other-session", "branch": "claude/t/2026-10-14-locked-step", "seen": %s}' "$((now+10800))" > "$D/.git/worktrees/locked/claude/owner.json"
  git -C "$D" branch claude/t/2026-10-14-unsure-two
  rec 15-unsure2.json unsure-two started=$((now-7200)) ended=$((now-3600)) "end_reason=idle 60 min" depth=1
  say sid-unsure-two "Tests pass locally; the full check is still running in the background."
  lines() { [ -f "$STALLS_LOG" ] && wc -l < "$STALLS_LOG" | tr -d ' ' || echo 0; }
  ncalls() { [ -f "${1:-$STUB_CALLS}" ] && wc -l < "${1:-$STUB_CALLS}" | tr -d ' ' || echo 0; }
  tk() { STALLS_NOW=$1 "$HM" tick "${@:2}"; }
  call() { python3 - "${2:-$STUB_CALLS}" "$1" <<'PY'
import json, sys
c = [json.loads(l) for l in open(sys.argv[1])]
# a call's name: the topic dispatch was given, the worktree autofinish-run was
nm = lambda x: x['argv'][0].split('2026-10-14-')[-1] if x['tool'] == 'dispatch' else 'wt:' + x['argv'][0].rsplit('/', 1)[-1]
exec(sys.argv[2])
PY
  }
  logq() { python3 - "$STALLS_LOG" "$1" <<'PY'
import json, sys
L = [json.loads(l) for l in open(sys.argv[1])]
exec(sys.argv[2])
PY
  }

  out=$(tk "$now")
  has "$out" "helm tick: disarmed — not armed (helm tick --arm)" "disarmed: says so"
  check "$(lines)" "16" "  a dry line per verdict, written (14 stalls with the locked step, 2 unsure)"
  check "$(ncalls) $(ncalls "$X/claude-calls")" "0 0" "  nothing called: no dispatch, no autofinish-run, no classifier"
  out=$(tk "$((now+60))")
  check "$(lines)" "16" "the same tick again writes nothing new (R6: a line per changed verdict)"
  has "$out" "(unchanged)" "  and says which verdicts stood"
  CLAUDE_UNATTENDED=dispatch "$HM" tick --arm > "$X/arm.out" 2>&1; check "$? $([ -f "$X/state/armed" ] && echo armed || echo none)" "1 none" \
    "--arm under CLAUDE_UNATTENDED is refused: nothing unattended arms the tick"
  has "$(cat "$X/arm.out")" "arming is the owner's" "  and says whose it is"
  st=$(STALLS_NOW=$now "$HM" tick --arm --by test-sam)
  has "$st" "helm tick: dry — armed by test-sam at" "--arm: armed, and dry for its first 3 h"
  has "$st" "16 lines" "  --status shows the log"
  STALLS_NOW=$((now+600)) "$HM" tick --arm --by later > /dev/null
  has "$(STALLS_NOW=$((now+600)) "$HM" tick --status)" "armed by test-sam at" "  re-arming keeps the first arming (its dry hours never restart)"
  out=$(tk "$((now+1200))")
  has "$out" "helm tick: dry — armed by test-sam" "20 min after arming: dry"
  has "$out" "S1 testhost demo gone-step: would redispatch (retry 1 of 2)" "  the backoff has passed: it would re-dispatch"
  has "$out" "S4 testhost demo net-launch: would be refused — autofinish is disarmed on this Mac" "  a relaunch waits for autofinish armed here"
  check "$(ncalls) $(ncalls "$X/claude-calls")" "0 0" "  still nothing called"

  ta=$((now+10860))   # 3 h 1 min after arming: the first acting tick
  # the gates that refuse an armed tick, each on a copy of the memory, before the real one acts
  scen() {  # scen NAME VAR=VALUE…: the acting tick on a copy of the log, its own call files
    cp "$STALLS_LOG" "$X/$1.jsonl"
    env STALLS_LOG="$X/$1.jsonl" STUB_CALLS="$X/$1.calls" STUB_CLAUDE_CALLS="$X/$1.claude" "${@:2}" STALLS_NOW=$ta "$HM" tick
  }
  echo tight > "$X/acct"; out=$(scen tight)
  has "$out" "S1 testhost demo gone-step: refused — the week is tight (claude-a 99% used)" "the week tight: refused"
  check "$(ncalls "$X/tight.calls")" "0" "  nothing started"
  echo none > "$X/acct"; out=$(scen none)
  has "$out" "S1 testhost demo gone-step: refused — account pick: no login may run it now (claude-a: its week is at the ceiling)" "no login with room (account pick): refused"
  check "$(ncalls "$X/none.calls")" "0" "  nothing started"
  echo ok > "$X/acct"; printf '{"by": "test", "ts": "2026-10-14T00:00:00-07:00"}' > "$X/af/armed"
  out=$(scen late STALLS_DEADLINE=$(( $(date +%s) + 10 )))
  has "$out" "S1 testhost demo gone-step: waits — no time left in this tick for redispatch (ask poll's timeout)" \
    "a tick past ask poll's deadline starts no tool call it cannot finish"
  check "$(ncalls "$X/late.calls")" "0" "  nothing started"
  out=$(scen slow STUB_SLEEP=5 STALLS_TOOL_TIMEOUT=1)
  has "$out" "timed out after 1 s — counted as spent" "a tool call that times out is a spent retry, not a refusal (it may have started the run)"
  check "$(python3 -c "import json; L=[json.loads(l) for l in open('$X/slow.jsonl')]; g=[l for l in L if l['topic'] == 'gone-step' and l['t'] == $ta]; print([(l['action'], l['why'][:6]) for l in g])")" \
    "[('retry', 'firing'), ('retry', 'dispat')]" "  its retry was on record before the tool ran: a firing line, then the outcome"
  out=$(scen full DISPATCH_MAX_RUNS=0)
  has "$out" "S1 testhost demo gone-step: waits — the run cap is full here (" "the run cap full: a step waits"
  check "$(call "print(sorted(x['tool'] for x in c))" "$X/full.calls")" "['autofinish-run']" "  a relaunch is no run of dispatch's cap: it goes on"

  out=$(tk "$ta")
  has "$out" "helm tick: armed — armed by test-sam" "3 h after arming: armed"
  check "$(call "print(sorted((x['tool'], nm(x)) for x in c))")" \
    "[('autofinish-run', 'wt:net'), ('dispatch', 'cap-step'), ('dispatch', 'gone-step'), ('dispatch', 'unsure-two')]" \
    "the acting tick: S1, S2 and the classified run re-dispatched, S4 relaunched — the locked step not"
  check "$(call "x=[x for x in c if nm(x) == 'gone-step'][0]; e=x['env']; print(e['DISPATCH_DEPTH'], e['DISPATCH_MANAGER'], e['DISPATCH_MANAGER_HOST'], e['DISPATCH_MANAGER_ACCOUNT'], e['DISPATCH_PLAN'], e['DISPATCH_PLAN_SPACE'], 'CLAUDE_CODE_SESSION_ID' in e)")" \
    "0 mgr-b3 testhost /x/acct b3p b3-space False" "  S1: the same step again (depth 1 → DISPATCH_DEPTH 0), its manager's five values, never the caller's session"
  check "$(call "x=[x for x in c if nm(x) == 'gone-step'][0]; e=x['env']; print(e['DISPATCH_SKIPPER'], e['DISPATCH_SKIPPER_HOST'], e['DISPATCH_SKIPPER_ACCOUNT'], e['DISPATCH_SHIP'])")" \
    "mgr-b3 testhost /x/acct b3p" "    and under the new names too (rename S5: both written until S8)"
  check "$(call "x=[x for x in c if nm(x) == 'gone-step'][0]['argv']; print(x[1:3] == ['--repo', '$D'], x[-2:], x[x.index('--note') + 1].split(' — ')[0])")" \
    "True ['--on', 'here'] stalls: re-dispatched (retry 1 of 2) after S1" "  where it ran (--on here), with a note"
  check "$(call "x=[x for x in c if nm(x) == 'cap-step'][0]; print(x['env']['DISPATCH_DEPTH'], 'DISPATCH_MANAGER' in x['env'], x['argv'][x['argv'].index('--note') + 1][:34])")" \
    "2 False stalls: started (retry 1 of 2) aft" "  S2: the next step, so its depth as recorded (dispatch adds one); no manager it never had"
  check "$(call "print([x['argv'][1:] for x in c if x['tool'] == 'autofinish-run'][0])")" "['--by', 'chain', '--rule', 'C']" \
    "  S4: autofinish-run --by chain, the stopped run's rule"
  check "$(call "x=[x for x in c if nm(x) == 'unsure-two'][0]; print(x['env']['DISPATCH_DEPTH'], 'an unsure end the classifier said to retry' in x['argv'][x['argv'].index('--note') + 1])")" \
    "0 True" "  the unsure run the classifier said yes to: re-dispatched as an S1"
  check "$(ncalls "$X/claude-calls")" "1" "the classifier: one call through bin/gate"
  check "$(python3 -c "import json; p=json.loads(open('$X/claude-calls').readline())['prompt']; print('u0: Topic unsure-two' in p, 'u1:' in p, 'unsure-step' in p)")" "True False False" \
    "  one item: the unsure run with no depth was raised without one"
  check "$(python3 -c "import json; r=[json.loads(l) for l in open('$X/gate.jsonl')][-1]; print(r['site'], r['provider'], r['status'], r['items'])")" "plan.stall claude ok 1" \
    "  logged by the gate as site plan.stall"
  has "$out" "S1 testhost demo locked-step: refused — its worktree's lock is held by session other-se, inside OWNER_TTL (2 h)" \
    "the strict lock rule: a lock not handed over, inside OWNER_TTL, refuses"
  has "$out" "classifier: retry" "  the classifier's answer is on the line"
  check "$("$HM" state b3p | python3 -c "import json,sys; print([(t['id'], t['status']) for t in json.load(sys.stdin)['tasks']])")" "[('gone-step', 'blocked')]" \
    "a managed run's plan hears it: blocked, never failed"
  check "$(logq "print(sorted(set((l['topic'], l['action']) for l in L if l['t'] == $ta and l['action'] in ('retry', 'refused'))))")" \
    "[('cap-step', 'retry'), ('gone-step', 'retry'), ('locked-step', 'refused'), ('net-launch', 'retry'), ('unsure-two', 'retry')]" \
    "  every action and refusal is a line in stalls.jsonl"

  git -C "$D" branch -f claude/t/2026-10-14-unsure-two "$(git -C "$D" commit-tree -m moved "$(git -C "$D" rev-parse 'main^{tree}')" -p main)"
  out=$(tk "$((ta+300))")
  check "$(ncalls) $(ncalls "$X/claude-calls")" "4 1" "5 min later: nothing again, and no second classifier call though its tip moved"
  has "$out" "S1 testhost demo gone-step: waits — redispatch 2 of 2 due" "  the second retry waits out its 40 min"

  # the retry FAILED at fire time (dispatch's own refusal in its log): not a spent retry
  logq "import sys; l=[l for l in L if l['topic'] == 'gone-step' and l['action'] == 'retry' and 'log' in l][0]; open(l['log'], 'a').write('FAILED: screen did not start\n')"
  out=$(tk "$((ta+600))")
  has "$out" "follow-up testhost demo gone-step: at fire time: FAILED: screen did not start" "a retry FAILED at fire time is read from its dispatch log"
  has "$out" "S1 testhost demo gone-step: waits — redispatch 1 of 2 due" "  and not counted: retry 1 again, after a fresh 10 min"
  out=$(tk "$((ta+1260))")
  check "$(call "print([nm(x) for x in c[4:]], c[4]['argv'][c[4]['argv'].index('--note') + 1][:34])")" "['gone-step'] stalls: re-dispatched (retry 1 of " \
    "  then re-dispatched once more, still retry 1 of 2; nothing else is due"

  # its run appears (and dies): the plan hears `running`, and the retry is spent
  rec 16-gone-r1.json gone-step started=$((ta+1300)) pid=99999999 proc_start=x depth=1 brief_blob='"b10b"' session=sid-gone-r1 \
    manager=mgr-b3 manager_host=testhost manager_account=/x/acct plan=b3p plan_space=b3-space
  out=$(tk "$((ta+1500))")
  has "$out" "follow-up testhost demo gone-step: its retry's run 16-gone-r1.json started" "the retry's record appears: a started line"
  check "$("$HM" state b3p | python3 -c "import json,sys; print([(t['id'], t['status']) for t in json.load(sys.stdin)['tasks']])")" "[('gone-step', 'running')]" \
    "  and its plan hears running"
  has "$out" "S1 testhost demo gone-step: waits — redispatch 2 of 2 due" "  its run gone too: retry 2 waits 40 min after retry 1"
  out=$(tk "$((ta+3700))")
  check "$(call "print(sorted(nm(x) for x in c[5:]))")" "['cap-step', 'gone-step', 'unsure-two', 'wt:net']" \
    "40 min on: the second retry of each, the relaunch included"
  check "$(call "g=[x for x in c[5:] if nm(x) == 'gone-step'][0]['argv']; print(g[g.index('--note') + 1][:34])")" "stalls: re-dispatched (retry 2 of " "  retry 2 of 2"
  rec 17-gone-r2.json gone-step started=$((ta+3750)) pid=99999999 proc_start=x depth=1 brief_blob='"b10b"' session=sid-gone-r2 \
    manager=mgr-b3 manager_host=testhost manager_account=/x/acct plan=b3p plan_space=b3-space
  out=$(tk "$((ta+6200))")
  has "$out" "S1 testhost demo gone-step: raised — 2 retries spent on this step" "two retries spent: raised"
  has "$out" "S4 testhost demo net-launch: raised — 2 retries spent on this launch's tip" "  a launch's tip too"
  check "$(ncalls)" "9" "  and nothing called"
  check "$("$HM" state b3p | python3 -c "import json,sys; t=json.load(sys.stdin)['tasks'][0]; print(t['status'], t['progress'][:28])")" "blocked stalled S1 — raised: 2 retri" \
    "  its plan hears blocked, with why"

  check "$(CLAUDE_UNATTENDED=dispatch "$HM" tick --disarm | head -1)" "helm tick: disarmed — not armed (helm tick --arm) — verdicts and the log only, nothing called" "--disarm"
  rm -f "$X"/dlogs/*; out=$(tk "$((ta+9000))")
  check "$(ncalls)" "9" "  disarmed: nothing called"
  check "$(python3 - "$B" "$HOME" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import stalls_tick as k
s = {"host": "buildbox", "branch": "claude/x", "repo": "demo", "depth": 3, "class": "S1", "run": "x.json",
     "dispatch": {"repo": "/elsewhere", "yolo": 1, "pin": "bound", "model": "sonnet", "effort": "high"}}
argv, env = k.dispatch_cmd(s, "redispatch", 1, 1000)
print(argv[3] == sys.argv[2] + "/projects/demo", argv[6:], env["DISPATCH_DEPTH"])
PY
)" \
    "True ['--model', 'sonnet', '--effort', 'high', '--yolo', '--account', 'bound', '--on', 'buildbox', '--at', '@1120', '--fallback', 'here'] 2" \
    "an buildbox run retries on buildbox (--at @now+120, --fallback here), its mode and bound pin kept"
  L="$T/launches"; git init -q -b main "$L"; git -C "$L" commit -q --allow-empty -m x
  for b in ns nl died ol nw; do git -C "$L" branch "claude/t/2026-10-14-$b"; done; mkdir -p "$L/.git/claude"
  # ol and nw stopped, then merged: the old word and rename S4's (M7) both end the stall
  { echo "2026-10-14T01:00:00-07:00 stopped claude/t/2026-10-14-ol G4 ⚠ open items"
    echo "2026-10-14T01:30:00-07:00 landed claude/t/2026-10-14-ol #5"
    echo "2026-10-14T01:00:00-07:00 stopped claude/t/2026-10-14-nw G4 ⚠ open items"
    echo "2026-10-14T01:30:00-07:00 launched claude/t/2026-10-14-nw #6"
    echo "2026-10-14T01:00:00-07:00 never-started claude/t/2026-10-14-ns never-started (no reply)"
    echo "2026-10-14T01:00:00-07:00 never-started claude/t/2026-10-14-nl not-launched dispatch refused"
    echo "2026-10-14T01:00:00-07:00 died claude/t/2026-10-14-died abc1234 killed"; } > "$L/.git/claude/autofinished"
  # rename guard: a map run keeps this line (both words) and would turn ol's old-word line into a launched one
  check "$(grep -c ' landed claude/t/2026-10-14-ol ' "$TD/test_helm.sh")" 2 "rename guard: ol's fixture keeps landed, nw's says launched"
  check "$(STALLS_REPOS="$L" python3 - "$B" <<'PY'
import sys, time
sys.path.insert(0, sys.argv[1])
import stalls
print(sorted((s["topic"], s["class"]) for s in stalls.judge_launches("h", set(), time.time())[0]))
PY
)" "[('died', 'S5'), ('ns', 'S5')]" "a landing that never started or whose runner died is an S5; a not-launched one the sweep starts again is none, nor a stop that later landed or launched"
  check "$(python3 - "$B" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import stalls_tick as k
retry = lambda what: {"action": "retry", "what": what, "t": 1000, "repo": "demo", "topic": "s", "key_kind": "step",
                      "key": ["h", "demo", "s", "old-blob"]}
runs = {"runs": [{"repo": "demo", "topic": "s", "brief_blob": "next-blob", "started": 1100, "run": "n.json"}]}
print([len(k.follow_up(k.Memory([retry(w)]), runs, 2000, False, "dry")) for w in ("start", "redispatch")])
PY
)" "[1, 0]" "a follow-up: an S2 start's run is the next step's brief (any blob); a re-dispatch's must be its own"
  unset STALLS_LOG STALLS_STATE_DIR STALLS_DISPATCH STALLS_AUTOFINISH_RUN AUTOFINISH_ACCOUNT AUTOFINISH_STATE_DIR GATE_PLAN_STALL_PROVIDER CLAUDE_BIN GATE_LOG DISPATCH_MAX_RUNS
  rm -rf "$R" "$T/sess/work.json" "$T/sess/wait.json"

  echo "B8: Orca workers — S1, S6, S7 through harness list --harness orca, the registry over Orca's liveness"
  # A stub `orca` answering from a fixture state in the shapes of Orca 1.4.225 (B5's probe, P3's
  # task rows; the mailbox rows are unprobed and shaped on its guides), real git worktrees, and
  # Claude Code registry files in the worktrees; the real bin/harness and orca adapter read them.
  # Run run_h holds harness-run steps (each Task titled with its branch: ours); run_p a plan's Run.
  X8="$T/b8"; O="$X8/repos/orcademo"; mkdir -p "$O" "$X8/ws"
  git -C "$O" init -q -b main; printf -- '- physical: none\n' > "$O/AGENTS.md"; git -C "$O" add AGENTS.md; git -C "$O" commit -q -m x
  for w in gone fx cb ext unv busy late rep stop old retried ask scratch; do
    git -C "$O" worktree add -q "$X8/ws/$w" -b "claude/laptop/2026-10-16-$w-step"; done
  mkdir -p "$X8/ws/ask/docs"; printf '# q\n\n- **D1 — which port**\n\n  ➤ Answer:\n' > "$X8/ws/ask/docs/q.md"
  git -C "$X8/ws/ask" add docs/q.md; git -C "$X8/ws/ask" commit -q -m q
  python3 - "$X8" "$now" <<'PY'
import json, sys, time
x8, now = sys.argv[1], int(sys.argv[2])
utc = lambda t: time.strftime("%Y-%m-%d %H:%M:%S", time.gmtime(t))
def w(did, name, run, task, disp="dispatched", outcome="in_progress", live="unverifiable", reason="missing_status", worker="ready",
      term="active", source=None, why=None, nxt=None, path=None, stage="input_accepted", handle=None, own=None, agent="claude"):
    lv = {"verdict": live, "reason": reason}
    if source:
        lv["source"] = source
    return {"dispatchId": did, "taskId": task, "runId": run, "workerState": worker, "dispatchStatus": disp,
            "agentTerminalHandle": handle or "structworker_" + did, "terminalState": term,
            "resource": dict({"worktreeId": "repo-1::" + (path or "%s/ws/%s" % (x8, name)), "releaseState": "not_requested"},
                             **({"ownershipState": own} if own else {})),
            "projection": {"stage": {"worker": worker, "dispatch": disp, "detail": stage}, "outcome": outcome,
                           "liveness": lv, "nextAction": {"kind": "retry" if nxt else "none", "argv": nxt or []}},
            "_why": why, "_agent": agent}
br = lambda n: "claude/laptop/2026-10-16-%s-step" % n
workers = [   # newest first, as Orca lists them
    w("ctx_r2", "retried", "run_h", "t_retried"),
    # a worker's exit, as Orca 1.4.225 records it (its source): Dispatch failed, stage process_exited,
    # the Task back to ready (a plain start) — or failed (a --retry-of); the third in a row circuit_broken
    w("ctx_gone", "gone", "run_h", "t_gone", disp="failed", outcome="failed", live="exited", reason="process_exited",
      worker="failed", term="exited", stage="process_exited", nxt=["orchestration", "worker-start", "--task", "t_gone"]),
    w("ctx_fx", "fx", "run_h", "t_fx", disp="failed", outcome="failed", live="exited", worker="failed", stage="process_exited"),
    w("ctx_cb", "cb", "run_h", "t_cb", disp="circuit_broken", outcome="failed", live="exited", worker="failed", stage="process_exited"),
    # main's own-terminal start (--account): a term_ handle Orca marks external, no agent of Orca's launch
    w("ctx_ext", "ext", "run_h", "t_ext", disp="failed", outcome="failed", live="exited", reason="process_exited",
      worker="failed", term="exited", stage="process_exited", handle="term_ext", own="external", agent=None),
    w("ctx_unv", "unv", "run_h", "t_unv"),
    w("ctx_busy", "busy", "run_h", "t_busy"),
    w("ctx_late", "late", "run_h", "t_late", disp="failed", outcome="failed", live="exited", reason="process_exited"),
    w("ctx_rep", "rep", "run_h", "t_rep", disp="failed", outcome="failed", live="exited", why="Task marked failed"),
    w("ctx_stop", "stop", "run_h", "t_stop", disp="failed", outcome="failed", worker="stopped", live="exited", source="worker_stop"),
    w("ctx_old", "old", "run_h", "t_old", disp="failed", outcome="failed", live="exited"),
    w("ctx_r1", "retried", "run_h", "t_retried", live="exited", reason="process_exited"),
    w("ctx_lost", "lost", "run_h", "t_lost", live="exited", path=x8 + "/ws/removed-long-ago"),
    w("ctx_scr", "scratch", "run_x", "t_scr", live="exited"),
    w("ctx_ask", "ask", "run_p", "p_ask"),
]
t = lambda tid, run, title, status, deps=(), created=now - 3 * 3600, completed=None: {
    "id": tid, "run_id": run, "task_title": title, "display_name": title, "status": status, "deps": json.dumps(list(deps)),
    "created_at": utc(created), "completed_at": utc(completed) if completed else None}
tasks = {"run_h": [t("t_" + n, "run_h", br(n), s) for n, s in (("gone", "ready"), ("fx", "failed"), ("cb", "failed"), ("ext", "ready"), ("unv", "dispatched"), ("busy", "dispatched"),
                    ("late", "failed"), ("rep", "failed"), ("stop", "failed"), ("old", "completed"), ("retried", "dispatched"), ("lost", "dispatched"))],
         "run_x": [t("t_scr", "run_x", "probe", "dispatched")],
         "run_p": [t("p_a", "run_p", "pa", "completed", completed=now - 7200), t("p_b", "run_p", "pb", "ready", deps=["p_a"]),
                   t("p_c", "run_p", "pc", "ready"), t("p_ask", "run_p", "p-ask", "dispatched")]}
# Orca's messages table rows (its source): the sender is from_handle, payload a JSON string
q = lambda mid, body, sender="dispatch:ctx_ask", ago=600: {"id": mid, "run_id": "run_p", "type": "question", "from_handle": sender,
                                                           "to_handle": "run:run_p", "body": body, "payload": "{}", "created_at": utc(now - ago)}
msgs = {"run_p": [q("msg_q1", "Need a call on docs/q.md D1 before I go on"), q("msg_q2", "Which port does the probe use?", ago=300),
                  q("msg_q3", "And ../../../outside.md D1?", ago=200), q("msg_q4", "stale: docs/q.md D1", sender="dispatch:ctx_gone_long_ago")]}
json.dump({"workers": workers, "tasks": tasks, "msgs": msgs, "coord": {"run_h": "term_h", "run_p": "term_p", "run_x": "term_x"}, "n": 0},
          open(x8 + "/orca.json", "w"))
PY
  cat > "$X8/orca" <<'PY'
#!/usr/bin/env python3
import json, os, sys
args = [a for a in sys.argv[1:] if a != "--json"]
open(os.environ["STUB_ORCA_CALLS"], "a").write(" ".join(args) + "\n")
p = os.environ["STUB_ORCA_STATE"]; st = json.load(open(p))
opt = lambda k: args[args.index(k) + 1] if k in args else None
def out(res, ok=True):
    json.dump(st, open(p, "w"))
    print(json.dumps({"ok": ok, "result": res} if ok else {"ok": False, "error": res})); sys.exit(0 if ok else 1)
cmd = " ".join(args[:2])
if cmd == "orchestration worker-list":
    out({"workers": [{k: v for k, v in x.items() if not k.startswith("_")} for x in st["workers"] if not opt("--run") or x["runId"] == opt("--run")],
         "page": {"hasMore": False}})
if cmd == "orchestration worker-show":
    x = next(x for x in st["workers"] if x["dispatchId"] == opt("--dispatch"))
    out({"dispatch": {"id": x["dispatchId"], "status": x["dispatchStatus"], "createdAt": "2026-10-16 05:00:00",
                      "terminationReason": x.get("_why")},
         "worker": {"updatedAt": "2026-10-16 06:00:00", "startOptions": {"agent": x["_agent"], "launch": {"effective": {"agent": x["_agent"]}}}},
         "projection": x["projection"], "observation": {"status": "unverifiable"}})
if cmd == "orchestration task-list":
    rows = st["tasks"].get(opt("--run"), [])
    out({"tasks": [r for r in rows if "--ready" not in args or r["status"] == "ready"]})
if cmd == "orchestration run-show":
    out({"run": {"id": opt("--id"), "coordinator_handle": st["coord"].get(opt("--id"))}})
if cmd == "orchestration check":
    assert "--peek" in args, "a consuming check from a script"
    out({"messages": st["msgs"].get(opt("--run"), [])})
if cmd == "orchestration worker-start":
    # Orca's rule (its source): --retry-of takes a failed or blocked Task, a plain start a ready one
    task = next(t for t in st["tasks"][opt("--run")] if t["id"] == opt("--task"))
    if task["status"] not in (("failed", "blocked") if "--retry-of" in args else ("ready",)):
        out({"code": "task_not_startable", "message": "Task %s is %s" % (task["id"], task["status"])}, ok=False)
    task["status"] = "dispatched"
    old = next(x for x in st["workers"] if x["taskId"] == opt("--task"))
    st["n"] += 1; new = dict(json.loads(json.dumps(old)), dispatchId="ctx_new%d" % st["n"], dispatchStatus="dispatched", terminalState="active",
                             workerState="ready")
    new["projection"].update(stage={"worker": "ready", "dispatch": "dispatched", "detail": "input_accepted"}, outcome="in_progress", liveness={"verdict": "unverifiable", "reason": "missing_status"}, nextAction={"kind": "none", "argv": []})
    st["workers"].insert(0, new)
    out({"dispatch": {"id": new["dispatchId"]}, "stage": "ready"})
out({"code": "stub", "message": "the stub has no %s" % cmd}, ok=False)
PY
  cat > "$X8/ask" <<'PY'
#!/usr/bin/env python3
import json, os, sys
env = {k: v for k, v in os.environ.items() if k.startswith("DISPATCH_") or k == "ASK_SESSION"}
open(os.environ["STUB_ASK_CALLS"], "a").write(json.dumps({"argv": sys.argv[1:], "env": env}) + "\n")
print("backend: talk · verdict: delivered · stub")
PY
  chmod +x "$X8/orca" "$X8/ask"
  # the registry: wt unv's claude waits on a permission prompt (Orca says unverifiable — D2-B's fixture),
  # wt busy's works, wt late's still waits though Orca settled its Dispatch failed
  for w in unv:waiting busy:busy late:waiting; do
    printf '{"pid": %s, "sessionId": "sid-orca-%s", "cwd": "%s", "status": "%s", "waitingFor": "permission to run Bash", "statusUpdatedAt": %s000}' \
      "$$" "${w%%:*}" "$X8/ws/${w%%:*}" "${w##*:}" "$now" > "$T/sess/orca-${w%%:*}.json"; done
  # the plan's manager, live in the registry: a question naming a D-item is relayed to it
  printf '{"pid": %s, "sessionId": "mgr-1", "cwd": "%s", "status": "busy", "statusUpdatedAt": %s000}' "$$" "$T" "$now" > "$T/sess/orca-mgr.json"
  "$HM" $SHIP b8 --id b8p > /dev/null
  "$HM" task b8p x > /dev/null; "$HM" task b8p y > /dev/null; "$HM" dep b8p y --on x > /dev/null
  PLAN_NO_RENDER=1 "$HM" report b8p --task x --status done > /dev/null
  python3 - "$T/plans/b8p" "$now" <<'PY'
import json, sys
d, now = sys.argv[1], float(sys.argv[2])
p = json.load(open(d + "/plan.json")); p["orca_run"] = "run_p"; json.dump(p, open(d + "/plan.json", "w"))
ls = [dict(json.loads(l), t=now - 7200) for l in open(d + "/events.jsonl") if l.strip()]
open(d + "/events.jsonl", "w").write("".join(json.dumps(e) + "\n" for e in ls))
PY
  export STALLS_ORCA=1 HARNESS_ORCA="$X8/orca" STUB_ORCA_STATE="$X8/orca.json" STUB_ORCA_CALLS="$X8/orca.calls" HARNESS_HOST=testhost \
         STALLS_REPOS= STUB_ASK_CALLS="$X8/ask.calls" STALLS_ASK="$X8/ask"
  oj=$(python3 "$B/stalls.py" --json --no-peer)
  og() { echo "$oj" | python3 -c "import json,sys; d=json.load(sys.stdin); o=[s for s in d['stalls'] if s.get('harness') == 'orca']; $1"; }
  check "$(og "print(sorted((s['class'], s['topic'], s['action']) for s in o))")" \
    "[('S1', 'cb-step', 'raise'), ('S1', 'ext-step', 'raise'), ('S1', 'fx-step', 'retry'), ('S1', 'gone-step', 'retry'), ('S1', 'rep-step', 'raise'), ('S6', 'late-step', 'raise'), ('S6', 'p-ask', 'raise'), ('S6', 'p-ask', 'raise'), ('S6', 'p-ask', 'relay'), ('S6', 'unv-step', 'raise'), ('S7', 'pb', 'raise')]" \
    "one stall per fixture; busy, stopped, completed, superseded, worktree gone, a scratch Run, a first ready step and a stale question are none"
  check "$(og "s=[x for x in o if x['topic']=='unv-step'][0]; print(s['rule'], s['session'], s['orca_dispatch'])")" "live: waiting sid-orca-unv ctx_unv" \
    "  D2-B: Orca says unverifiable, the registry waiting — judged waiting, on the registry's session (its permission card gives way)"
  check "$(og "s=[x for x in o if x['topic']=='late-step'][0]; print(s['rule'], s['session'])")" "live: waiting sid-orca-late" \
    "  Orca settled it failed, its claude still waits in the registry: waiting, never an S1"
  check "$(og "s=[x for x in o if x['topic']=='gone-step'][0]; print(s['key'], s['key_kind'], s['depth'], s['column'], __import__('os').path.realpath(s['dispatch']['repo']) == __import__('os').path.realpath('$O'))")" \
    "['testhost', 'orcademo', 'gone-step', 'orca:t_gone'] step 0 Blocked True" "  S1: exited with no worker_done — retry, keyed by its Task, a flat plan's depth 0"
  check "$(og "s=[x for x in o if x['topic']=='gone-step'][0]; print(s['evidence'][:2], s['next_action'])")" \
    "['orca ctx_gone (run run_h, task t_gone)', \"Orca's next: orchestration worker-start --task t_gone\"] orchestration worker-start --task t_gone" \
    "  the card's evidence: the dispatch id and Orca's nextAction"
  check "$(og "s=[x for x in o if x['topic']=='rep-step'][0]; print(s['rule'], s['title'].split(' · ')[1][:9])")" "its Task failed with no process exit: a reported failure, or failed by hand S1 failed" "  a failure with no process exit: raised, never retried"
  check "$(og "print([x['rule'][:15] for x in o if x['topic']=='cb-step'])")" "[\"Orca's breaker:\"]" "  Orca's breaker (circuit_broken): raised, never retried (R4)"
  check "$(og "print([x['rule'][:40] for x in o if x['topic']=='ext-step'])")" "['ran in a terminal Orca did not launch (a']" \
    "  a worker in a terminal Orca did not launch (a picked login): raised at once, never retried on Orca's login"
  check "$(og "print(sorted((s['rule'], s['key'][2], s['action']) for s in o if s['topic']=='p-ask'))")" \
    "[(\"question in the Run's mailbox\", 'msg_q2', 'raise'), (\"question in the Run's mailbox\", 'msg_q3', 'raise'), ('question: docs/q.md D1', 'msg_q1', 'relay')]" \
    "  S6 from the mailbox (from_handle dispatch:<id>): a D-item in its worktree relayed, a path outside it or none raised, one from a gone attempt dropped"
  check "$(og "s=[x for x in o if x['class']=='S7'][0]; print(s['key'], s['orca_task'], s['raise_to'])")" "['testhost', 'b8p', 'pb'] p_b skipper" "  S7 from task-list --ready, quiet two hours since its dependency completed; to the live manager"
  check "$(echo "$oj" | python3 -c "import json,sys; print([s['topic'] for s in json.load(sys.stdin)['stalls'] if s.get('plan') == 'b8p' and not s.get('harness')])")" "[]" \
    "  an Orca-backed plan's own planned tasks are not judged twice (judge_plans leaves them to task-list)"
  hasnt "$(cat "$X8/orca.calls")" "worker-start" "  the judge starts nothing"
  ovo=$("$HM" $BOARD --json)
  check "$(echo "$ovo" | python3 -c "import json,sys; d=json.load(sys.stdin); c=[c for col in d['columns'] for c in col['cards']]; print([x.get('next_action') for x in c if x.get('orca_dispatch') == 'ctx_gone'], sum(1 for x in c if x['kind']=='permission' and 'orca-unv' in (x.get('session') or '')))")" \
    "['orchestration worker-start --task t_gone'] 0" "  overview: the card carries Orca's nextAction; no second card for the waiting worker"

  # the tick: armed four hours ago (past its dry hours), clock stepped; account and dispatch stubs from B3
  X9="$X8/tick"; mkdir -p "$X9"
  export STALLS_LOG="$X9/stalls.jsonl" STALLS_STATE_DIR="$X9/state" AUTOFINISH_ACCOUNT="$T/stubs/account" STUB_ACCT="$X9/acct" \
         AUTOFINISH_STATE_DIR="$X9/af" DISPATCH_MAX_RUNS=9 PLAN_NO_RENDER=1 STALLS_DISPATCH="$T/stubs/dispatch" STUB_CALLS="$X9/dcalls" STUB_LOGDIR="$X9"
  STALLS_NOW=$((now-4*3600)) "$HM" tick --arm --by test-sam > /dev/null
  orca_tick() { STALLS_NOW=$1 PLAN_NO_PEER=1 "$HM" tick; }
  out=$(orca_tick "$now")
  has "$out" "S1 testhost orcademo gone-step: waits — redispatch 1 of 2 due" "tick: an Orca S1 waits out the backoff as any S1"
  has "$out" "S6 testhost orcademo p-ask: relayed: backend: talk" "  a question naming docs/q.md D1 is relayed at once"
  check "$(python3 -c "import json,os; c=[json.loads(l) for l in open('$X8/ask.calls')]; print(len(c), c[0]['argv'][1] == os.path.realpath('$X8/ws/ask/docs/q.md'), c[0]['argv'][2:], c[0]['env'].get('DISPATCH_PLAN'), c[0]['env'].get('DISPATCH_MANAGER'), c[0]['env'].get('ASK_SESSION'))")" \
    "1 True ['D1', '--task', 'p-ask'] b8p mgr-1 ctx_ask" "  bin/ask relay <doc> <Dn> --task <step>, with the plan's manager road and the worker as the asker"
  out=$(orca_tick "$((now+700))")
  has "$out" "S6 testhost orcademo p-ask: waits — relayed at" "  relayed once: then it waits on the answer (orchestration reply --id)"
  check "$(wc -l < "$X8/ask.calls" | tr -d ' ')" "1" "  never relayed twice"
  has "$out" "S1 testhost orcademo gone-step: re-dispatched (retry 1 of 2): worker-start: dispatch ctx_new" "  past the backoff: retried through harness retry"
  has "$(cat "$X8/orca.calls")" "orchestration worker-start --task t_gone --worktree id:repo-1::$X8/ws/gone --agent claude --run run_h --from term_h" \
    "  the Task Orca reopened as ready: a plain start, its placement repeated, from the Run's coordinator"
  has "$(cat "$X8/orca.calls")" "orchestration worker-start --task t_fx --retry-of ctx_fx --worktree id:repo-1::$X8/ws/fx --agent claude" \
    "  a failed Task: --retry-of its latest Dispatch"
  hasnt "$out" "refused" "  Orca's own start rules (the stub's) accepted both"
  check "$([ -f "$X9/dcalls" ] && grep -c gone-step "$X9/dcalls" || echo 0)" "0" "  never bin/dispatch for an Orca step"
  out=$(orca_tick "$((now+1400))")
  has "$out" "follow-up testhost orcademo gone-step: its retry's run ctx_new" "  the next tick records the retry started"
  hasnt "$out" "gone-step: re-dispatched" "  and the old Dispatch is superseded by its Task's newer one: no second retry"
  H="$(peer harness)"
  "$H" retry ctx_busy --harness orca > /dev/null 2>&1; check "$?" 2 "harness retry: a live worker is refused"
  "$H" retry ctx_stop --harness orca > /dev/null 2>&1; check "$?" 2 "  and a stopped one (a stop is a person's)"
  "$H" retry ctx_cb --harness orca > /dev/null 2>&1; check "$?" 2 "  and a circuit-broken one (Orca's breaker, R4)"
  printf '["structworker_ctx_fx"]' > "$X8/own.json"; n0=$(grep -c 'worker-start --task t_fx' "$X8/orca.calls")
  HARNESS_ORCA_OWN="$X8/own.json" "$H" retry ctx_fx --harness orca > /dev/null 2>"$X8/err"
  check "$?" 2 "  and one that ran on a picked login in a terminal of ours (the login is not Orca's to repeat)"
  has "$(cat "$X8/err")" "ran in a terminal Orca did not launch" "    refused for that reason, before its Task is read"
  "$H" retry ctx_ext --harness orca > /dev/null 2>"$X8/err"; check "$?" 2 "  and one Orca marks external, though stop has emptied our list (no agent named: refused before that check)"
  has "$(cat "$X8/err")" "ran in a terminal Orca did not launch" "    for that reason"
  d2b=$(python3 - "$(dirname "$(peer harness)")/harness_adapters/orca.py" <<'PY'
import sys
from importlib.machinery import SourceFileLoader
m = SourceFileLoader("o", sys.argv[1]).load_module()
row = lambda own: {"dispatchStatus": "failed", "workerState": "failed", "projection": {"outcome": "failed"},
                   "resource": {"ownershipState": own}}
print(m._state(row("external"), {}, {"state": "idle"})[0], m._state(row("owned"), {}, {"state": "idle"})[0],
      m._state(row("external"), {}, {"state": "working"})[0])
PY
)
  check "$d2b" "failed idle working" "  D2-B: an idle claude left in an external terminal does not hide Orca's failed; a working one still outranks it"
  check "$(grep -c 'worker-start --task t_fx' "$X8/orca.calls")" "$n0" "    and Orca was never asked to start it"
  check "$("$H" list --harness orca --json | python3 -c "import json,sys; print(sorted(r['session_id'] for r in json.load(sys.stdin)))")" \
    "['ctx_ask', 'ctx_busy', 'ctx_late', 'ctx_new1', 'ctx_new2', 'ctx_r2', 'ctx_unv']" "harness list: the live workers, ctx_late too — Orca settled it failed, its claude still waits (D2-B, one rule for every reader)"
  check "$("$H" list --harness orca --unsettled --json | python3 -c "import json,sys; print(len(json.load(sys.stdin)))")" "17" \
    "  --unsettled: every Dispatch that did not complete as well"
  unset STALLS_ORCA HARNESS_ORCA STUB_ORCA_STATE STUB_ORCA_CALLS HARNESS_HOST STUB_ASK_CALLS STALLS_ASK STALLS_LOG STALLS_STATE_DIR \
        AUTOFINISH_ACCOUNT STUB_ACCT AUTOFINISH_STATE_DIR DISPATCH_MAX_RUNS STALLS_DISPATCH STUB_CALLS STUB_LOGDIR
  export STALLS_ORCA=0
  rm -f "$T/sess"/orca-*.json
fi

echo "the lease (skipper-resilience S4): skipper.json, leaselib, helm skipper's session verbs"
# Every --hold here lives by a stand-in parent (HELM_HOLD_PARENT, a `sleep`): without it the sidecar
# would find the nearest `claude` above this suite — the session running it — and live by that one.
LP="$T/plans"
ll() { python3 - "$B" "$@" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import leaselib
fn, args = sys.argv[2], sys.argv[3:]
if fn == "yard":
    print(leaselib.write_yard(args[0], args[1], "yardhost", "laid by the suite")["gen"])
elif fn == "check":
    print(leaselib.check(args[0], int(args[1])) or "ok")
elif fn == "fence":
    print(leaselib.fence(args[0], "suite") or "ok")
elif fn == "lapsed":
    print(leaselib.lapsed(args[0], now=float(args[1])))
PY
}
lf() { python3 -c 'import json, sys; r = json.load(open(sys.argv[1] + "/" + sys.argv[2] + "/skipper.json")); print(r[sys.argv[3]])' "$LP" "$1" "$2"; }
lev() { grep -c "\"lease\": \"$2\"" "$LP/$1/events.jsonl" | tr -d ' '; }
for p in ls1 ls2 ls3 ls4 ls5; do "$HM" $SHIP lease --id "$p" > /dev/null; done
check "$(ll fence ls4)" "ok" "a ship with no skipper.json: no lease, nothing fenced (every ship before S4)"
check "$(env -u CLAUDE_CODE_SESSION_ID "$LX/helm" skipper --renew ls4 2>&1; echo "rc=$?")" \
  "helm skipper --renew: ship ls4 has no lease here (only a ship laid with wharf apply --yard has one)
rc=1" "  and --renew on it says so"
check "$(ll yard ls1 dock)/$(lf ls1 holder)/$(lf ls1 scope)" "0/yard/dock" "the yard's hold: gen 0, holder yard (wharf apply --yard writes it: test_wharf.sh)"
check "$(lev ls1 'held by yard')" "1" "  one 'held by yard' event"
ll yard ls2 dock > /dev/null; ll yard ls3 other > /dev/null
sleep 300 & PARENT=$!
out=$(HELM_HOLD_PARENT=$PARENT "$LX/helm" skipper --hold --scope dock --once); check "$?" "0" "--hold --once: exit 0"
has "$out" "taken ls1 by skipper · dock at gen 1" "  take: gen 1, named for the scope"
check "$(lf ls1 holder)/$(lf ls1 gen)/$(lf ls1 session)/$(lf ls1 pid)" "skipper · dock/1/mgr-1/$PARENT" "  the file: holder, gen, this session, the parent's pid"
check "$(lf ls2 gen)/$(lf ls3 holder)" "1/yard" "  every yard-held ship of its scope taken, another scope's left"
check "$(lev ls1 'picked up by')" "1" "  the first take from the yard's gen 0 is 'picked up by'"
check "$(ll check ls1 0)" "refused: lease at gen 1 held by skipper · dock — you are gen 0; stand down (helm skipper --stand-down)" "check: gen N-1 refused, with the spec's line"
check "$(ll check ls1 1)" "ok" "  gen N accepted"
check "$(ll fence ls1)" "ok" "fence: the session the file names passes with no --gen"
check "$(env -u CLAUDE_CODE_SESSION_ID python3 - "$B" <<'PY'
import sys; sys.path.insert(0, sys.argv[1]); import leaselib; print(leaselib.fence("ls1", "suite") or "ok")
PY
)" "ok" "  a plain shell (no session id) passes"
check "$(CLAUDE_CODE_SESSION_ID=other-9 ll fence ls1)" "refused: lease at gen 1 held by skipper · dock — you are gen none; stand down (helm skipper --stand-down)" "  another session is refused"
has "$(SKIPPER_GEN=0 CLAUDE_CODE_SESSION_ID=other-9 ll fence ls1)" "refused: lease at gen 1 held by skipper · dock — you are gen 0" "  SKIPPER_GEN stale: refused for any session but the holder's"
check "$(SKIPPER_GEN=1 CLAUDE_CODE_SESSION_ID=other-9 ll fence ls1)" "ok" "  SKIPPER_GEN at the gen: accepted"
check "$(SKIPPER_GEN=0 ll fence ls1)" "ok" "  the holder's own session passes whatever SKIPPER_GEN says (gens are per ship; finish review)"
check "$(lev ls1 refused)" "2" "  one 'refused' event per refusal"
out=$("$LX/helm" skipper --renew ls1 --gen 0 2>&1); check "$?" "4" "--renew at a stale gen: exit 4"
has "$out" "refused: lease at gen 1 held by skipper · dock — you are gen 0" "  the refusal line"
check "$(lev ls1 'renewal refused')" "1" "  one 'renewal refused' event"
u0=$(lf ls1 until); sleep 1
out=$("$LX/helm" skipper --renew ls1); check "$?" "0" "--renew by the holder, no --gen: exit 0"
check "$(python3 -c "import sys; print(float(sys.argv[2]) > float(sys.argv[1]))" "$u0" "$(lf ls1 until)")" "True" "  until moved"
check "$(lev ls1 'renewal refused')" "1" "  a renewal writes no event"
check "$(ll lapsed ls1 "$(python3 -c "import sys; print(float(sys.argv[1]) - 1)" "$(lf ls1 until)")")/$(ll lapsed ls1 "$(python3 -c "import sys; print(float(sys.argv[1]) + 1)" "$(lf ls1 until)")")" \
  "False/True" "lapsed: not before until, past it after the TTL"
check "$(ll lapsed ls3 9999999999)" "False" "  the yard's hold never lapses"
# a former holder: ls2 handed back to the yard and taken by another session
ll yard ls2 dock > /dev/null
out=$(CLAUDE_CODE_SESSION_ID=mgr-2 HELM_HOLD_PARENT=$PARENT "$LX/helm" skipper --hold --scope dock --once)
has "$out" "taken ls2 by skipper · dock at gen 3" "a hand-back to the yard (gen 2) taken by the next skipper: gen 3"
check "$(lev ls2 'taken by')" "1" "  after a hand-back it is 'taken by'"
check "$(ll fence ls2)" "refused: lease at gen 3 held by skipper · dock — you are gen 1; stand down (helm skipper --stand-down)" "  the former holder's id is refused, told the gen it last held"
out=$("$LX/helm" skipper --ships dock); check "$?" "0" "--ships: exit 0"
has "$out" "ls1  skipper · dock  gen 1" "  each ship, its holder and gen"
hasnt "$out" "ls3" "  of that scope only"
check "$("$LX/helm" skipper --ships dock --json | python3 -c 'import json, sys; print(sorted((r["plan"], r["gen"], r["open"]) for r in json.load(sys.stdin)))')" \
  "[('ls1', 1, 0), ('ls2', 3, 0)]" "  --json: plan, gen, blocks open"
out=$("$LX/helm" skipper --status); has "$out" "scope dock — 2 ships; record: none" "--status: per scope, its record (none before S5)"
has "$out" "scope other — 1 ship" "  every scope"
echo '{"holder": "yard"' > "$LP/ls4/skipper.json"
out=$("$LX/helm" skipper --renew ls4 2>&1); check "$?" "4" "a torn skipper.json: --renew refused, exit 4"
has "$out" "the lease does not read" "  fails closed, saying so"
check "$(ll fence ls4 | cut -c1-34)" "refused: the lease does not read (" "  fence refuses it too: never read as no lease"
has "$("$LX/helm" skipper --status)" "ls4: " "  --status names it"
for bad in '"until": "soon"' '"pid": -1' '"session": 7' '"until": NaN'; do
  printf '{"holder": "yard", "gen": 0, "scope": "dock", %s}' "$bad" > "$LP/ls4/skipper.json"
  check "$(ll fence ls4 | cut -c1-34)" "refused: the lease does not read (" "  a lease with $bad does not read: refused, never crashes a reader"
done
printf '\xff\xfe{}' > "$LP/ls4/skipper.json"
check "$(ll fence ls4 | cut -c1-34)" "refused: the lease does not read (" "  nor does one that is not UTF-8"
rm -f "$LP/ls4/skipper.json"
check "$(HELM_HOLD_EVERY=0 HELM_HOLD_PARENT=$PARENT "$LX/helm" skipper --hold --scope dock 2>&1; echo "rc=$?")" \
  "helm skipper --hold: HELM_HOLD_EVERY='0' is no period from 1 to 450 seconds
rc=1" "--hold: a zero period refused (it would rewrite skipper.json in a loop)"
# the sidecar loop: renews every ship it holds each period, takes a newly yard-held one, ends with its parent
ll yard ls4 dock > /dev/null
a1=$(lf ls1 until)
HELM_HOLD_EVERY=1 HELM_HOLD_PARENT=$PARENT "$LX/helm" skipper --hold --scope dock > "$T/hold.out" 2>&1 & HOLD=$!
sleep 3
check "$(python3 -c "import sys; print(float(sys.argv[2]) > float(sys.argv[1]))" "$a1" "$(lf ls1 until)")" "True" "--hold (HELM_HOLD_EVERY=1): ls1 renewed in the loop"
check "$(lf ls4 holder)/$(lf ls4 session)" "skipper · dock/mgr-1" "  ls4, laid to the yard meanwhile, taken"
check "$(lf ls2 session)/$(lf ls2 gen)" "mgr-2/3" "  another skipper's ship left alone"
check "$(lf ls3 holder)" "yard" "  another scope's ship left alone"
kill $PARENT; wait $PARENT 2>/dev/null
for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do kill -0 $HOLD 2>/dev/null || break; sleep 0.25; done
if kill -0 $HOLD 2>/dev/null; then kill $HOLD; check "alive" "ended" "the sidecar ends within a period of its parent's death"
else wait $HOLD; check "$?" "0" "the sidecar ends within a period of its parent's death, exit 0"; fi
has "$(cat "$T/hold.out")" "has ended — the sidecar ends with it" "  saying so"
# a renewal refused in the loop (the yard took the ship back) ends the sidecar, exit 4: it never takes it back
# the stand-in parent is named claude (a link to sleep): stand-down signals only a live claude
mkdir -p "$T/fakeclaude"; ln -sf /bin/sleep "$T/fakeclaude/claude"
"$T/fakeclaude/claude" 300 & PARENT=$!; disown $PARENT   # stand-down ends it below: no job notice from this shell
HELM_HOLD_EVERY=1 HELM_HOLD_PARENT=$PARENT "$LX/helm" skipper --hold --scope dock > "$T/hold.out" 2>&1 & HOLD=$!
sleep 1.5; ll yard ls1 dock > /dev/null; ll yard ls5 dock > /dev/null
for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do kill -0 $HOLD 2>/dev/null || break; sleep 0.25; done
if kill -0 $HOLD 2>/dev/null; then kill $HOLD; check "alive" "4" "a sidecar whose renewal is refused ends"
else wait $HOLD; check "$?" "4" "a sidecar whose renewal is refused ends, exit 4"; fi
has "$(cat "$T/hold.out")" "this skipper stands down" "  told to stand down"
check "$(lf ls1 holder)" "yard" "  and the ship stays the yard's"
check "$(lf ls5 holder)" "yard" "  a pass whose renewal is refused takes nothing: no ship stranded on a skipper that leaves (finish review)"
# stand-down: every ship this session holds back to the yard, its record deleted, its claude ended
mkdir -p "$T/mgrdir"; export ASK_MANAGER_DIR="$T/mgrdir"
printf '{"session": "mgr-1", "pid": %d, "scope": "dock"}' "$PARENT" > "$T/mgrdir/testhost-dock.json"
printf '{"session": "mgr-2", "pid": 1}' > "$T/mgrdir/testhost-other.json"
g4=$(lf ls4 gen)
out=$(SKIPPER_SCOPE=other "$LX/helm" skipper --stand-down); check "$?" "0" "--stand-down: exit 0"
has "$out" "stood down: ls4 back to the yard" "  the ships it holds, by name"
check "$(lf ls4 holder)/$(lf ls4 gen)" "yard/$((g4+1))" "  each one the yard's at gen + 1"
check "$(lev ls4 'stood down')" "1" "  one 'stood down' event"
check "$(lf ls2 session)" "mgr-2" "  another skipper's ship untouched"
check "$([ -e "$T/mgrdir/testhost-dock.json" ] && echo kept || echo deleted)" "deleted" "  its record deleted"
check "$([ -e "$T/mgrdir/testhost-other.json" ] && echo kept || echo deleted)" "kept" "  another session's record kept"
for _ in 1 2 3 4 5 6 7 8; do kill -0 $PARENT 2>/dev/null || break; sleep 0.25; done
check "$(kill -0 $PARENT 2>/dev/null && echo alive || echo ended)" "ended" "  its claude (the pid its lease and record name) ended"
kill $PARENT 2>/dev/null
check "$(env -u CLAUDE_CODE_SESSION_ID "$LX/helm" skipper --stand-down 2>&1; echo "rc=$?")" \
  "helm skipper --stand-down: a skipper session's own verb — no CLAUDE_CODE_SESSION_ID here
rc=1" "  a plain shell has no skipper to stand down"
"$LX/helm" skipper --start dock > /dev/null 2>&1; check "$?" "2" "--start is not S4's (S5 adds it)"
unset ASK_MANAGER_DIR

echo
[ "$fails" = 0 ] && echo "test_helm ($HELM_NAMES names): all passed" || { echo "test_helm ($HELM_NAMES names): $fails failed"; exit 1; }
