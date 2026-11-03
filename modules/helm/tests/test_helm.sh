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
# The two passes share nothing (each its own mktemp dir, config dir, HOME and stubs), so they run side
# by side and print in order: about half the wall time (suite-time, 2026-10-23).
if [ -z "${HELM_NAMES:-}" ]; then
  O=$(mktemp -d); p1=; p2=
  # cut short: both passes ended and what each printed shown, as helm's check.sh does (landing review)
  trap 'rm -rf "$O"' EXIT
  trap 'kill $p1 $p2 2>/dev/null; cat "$O/old" "$O/new" 2>/dev/null; exit 130' INT
  trap 'kill $p1 $p2 2>/dev/null; cat "$O/old" "$O/new" 2>/dev/null; exit 143' TERM
  HELM_NAMES=old bash "$0" "$@" > "$O/old" 2>&1 & p1=$!
  HELM_NAMES=new bash "$0" "$@" > "$O/new" 2>&1 & p2=$!
  wait $p1; r1=$?; wait $p2; r2=$?
  cat "$O/old" "$O/new"
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
# the first N characters of stdin's first line: `cut -c` counted bytes on CircleCI's ubuntu-2604
# image (uutils 0.8.0), as GNU's does, so a `·` cost a character there (AGENTS.md's Traps)
chars() { python3 -c 'import sys; print(sys.stdin.readline().rstrip("\n")[:int(sys.argv[1])])' "$1"; }
# a recursive delete under HOME goes through rm_own: only under this suite's own $T, so a block of the
# suite run outside it (its HOME the real one; F2, 2026-10-25) deletes nothing (the core's check, home_rm)
rm_own() { local p; for p; do case "$p" in */..|*/../*|*//*) ;; "${T:?}"/?*) rm -rf -- "$p"; continue ;; esac; echo "rm_own: refused $p, outside $T" >&2; return 1; done; }
# a state the code under test reaches by itself: polled every 0.1 s, up to 15 s, never a fixed sleep
until_() { local i; for i in $(seq 1 150); do eval "$1" && return 0; sleep 0.1; done; return 1; }

# a blueprint's front matter is read by PyYAML, installed per user on these Macs: keep its site
# when HOME moves below (bin/blueprintlib.py)
export PYTHONUSERBASE="${PYTHONUSERBASE:-$(python3 -m site --user-base)}"
. "$TD/config_fixture.sh"; fixture_config "$T/config"   # before HOME moves: the suite's own config dir, never the caller's
export PLANS_DIR="$T/plans" PLAN_HOST=testhost PLAN_PROJECTS_DIR="$T/projects" PLAN_CACHE_DIR="$T/cache" HOME="$T/home" \
       SURFACES_FILE="$T/surfaces.json" PLAN_NO_DEPLOY=1 ASK_SESSIONS_DIR="$T/sess" ASK_CACHE_DIR="$T/askcache" \
       COST_RATIO="$T/ratio.json" PLAN_NO_MEMO=1 PLAN_NO_GH=1 PLAN_PROJECTS_ROOT="$T/projects-root" \
       STALLS_PEERS= STALLS_REPOS= STALLS_ORCA=0 STALLS_CANARY=0 PLAN_NO_WHARF=1   # no wharf pass in a tick outside B7's own block, whose stub it reaches; the stall cards: no ssh to buildbox, no real repo's autofinished, no Orca app (B8's block turns its stub on)
unset DISPATCH_PLAN DISPATCH_MANAGER DISPATCH_PLAN_SPACE CLAUDE_UNATTENDED REGATTA_UNATTENDED DISPATCH_REPO DISPATCH_MANAGER_HOST DISPATCH_DEPTH \
      DISPATCH_SHIP DISPATCH_SKIPPER DISPATCH_SKIPPER_HOST DISPATCH_SKIPPER_ACCOUNT DISPATCH_MANAGER_ACCOUNT DISPATCH_TASK DISPATCH_MODE DISPATCH_BRIEF \
      SKIPPER_GEN SKIPPER_SCOPE SKIPPER_ACCOUNT HELM_HOLD_EVERY HELM_HOLD_PARENT \
      CLAUDE_CODE_DISABLE_BACKGROUND_TASKS AUTOFINISH_CALLER_UNATTENDED HELM_LISTEN_PARENT HELM_SEND_DIR HELM_SEND_POLL HELM_SEND_WAIT \
      HELM_SEND_LAY_TIMEOUT HELM_PICKUP HARNESS_SSH HARNESS_HOST SRT_SSH_PROXY_COMMAND GIT_SSH_COMMAND \
      DEADMAN_CONFIG DEADMAN_URL DEADMAN_PING_SECRET DEADMAN_HOST   # the lease's inputs (S4); S7's (a dispatched run sets the first); deadman's (S11)
# SRT_SSH_PROXY_COMMAND and GIT_SSH_COMMAND: a sandboxed caller's, which would send every ssh case by git's ssh (node-road)
# and every other DISPATCH_* a dispatched run carries: a list by name fell behind dispatch's
# DISPATCH_TASK, _MODE and _BRIEF, and "no run variable either" failed only in a dispatched run (2026-10-23)
unset $(env | sed -n 's/^\(DISPATCH_[A-Za-z0-9_]*\)=.*/\1/p')
export CLAUDE_CODE_SESSION_ID=mgr-1
# the account's plan and this Mac's deploy log (the core's sheep_*): Pro, an empty log of the suite's own —
# never the Mac's cache, nor a probe of its CLI (spacesheep-tiers)
export REGATTA_SHEEP_PLAN=pro REGATTA_SHEEP_DIR="$T/sheep-state"
export HELM_DEADMAN="$T/no-deadman"   # an absent peer: no case reaches lighthouse's real deadman (S11's block stubs it)
mkdir -p "$T/home" "$T/sess"
# The scratch commits' identity, in a file of the suite's own that every later HOME move keeps (S8's,
# S11's): with HOME moved the caller's (check.yml's `git config --global`) is gone, and git guesses one
# from the hostname only where it has a dot — a Mac's *.local, never an ubuntu runner's (71 cases, the
# twin's CI, 2026-10-25). GIT_AUTHOR_* would not do: the S7 block sets and unsets its own. The file
# replaces check.yml's, so it carries that one's init.defaultBranch too.
export GIT_CONFIG_GLOBAL="$T/gitconfig"
git config --global user.name t; git config --global user.email t@t; git config --global init.defaultBranch main
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
printf '{"repos": {"rx": ' > "$T/torn-repos.json"
check "$(CLAUDE_REPOS_JSON="$T/torn-repos.json" hl 'helmlib.task_mode(None, None, "rx")')" "('ask', 'the registry is unreadable (repos.json): read as ask')" \
  "a torn registry reads as ask, never default: a scope's ask cannot fail open (follow-ups item 6)"
check "$(CLAUDE_REPOS_JSON="$T/torn-repos.json" hl 'helmlib.task_mode(None, None, "rx", "dnd")[0]')" "dnd" "  a hint still comes first: the registry is read only for the scope"
check "$(CLAUDE_REPOS_JSON="$T/torn-repos.json" CLAUDE_UNATTENDED=x hl 'bool(helmlib.raise_refusal(helmlib.task_mode(None, None, "rx")[0], "default"))')" "True" \
  "  so an unattended caller's default over it is a raise: refused"
check "$(CLAUDE_REPOS_JSON="$T/modes-repos.json" hl 'helmlib.task_mode(None, None, "q")[0]')" "default" "  a scope's word that is no mode: the default"
check "$(CLAUDE_REPOS_JSON="$T/torn-repos.json" hl 'helmlib.torn_read(helmlib.task_mode(None, None, "rx"))')" "True" \
  "  torn_read names that ask, which no writer keeps (the follow-ups' landing review, item 6)"
check "$(CLAUDE_REPOS_JSON="$T/modes-repos.json" hl 'helmlib.torn_read(helmlib.task_mode(None, None, "rx"))')" "False" "  …and no other ask"
reads() { python3 - "$B" "$1" <<'PYREADS'
import pathlib, sys
sys.path.insert(0, sys.argv[1])
import helmlib
n, real = [0], pathlib.Path.read_text
def counted(self, *a, **k):
    n[0] += self.name == sys.argv[2]
    return real(self, *a, **k)
pathlib.Path.read_text = counted
print(helmlib.task_mode(None, None, "rx")[0], n[0])
PYREADS
}
check "$(CLAUDE_REPOS_JSON="$T/modes-repos.json" reads modes-repos.json)" "ask 1" "task_mode reads repos.json once for the tear and the scope (item 9)"
check "$(CLAUDE_REPOS_JSON="$T/torn-repos.json" reads torn-repos.json)" "ask 1" "  once on a torn one too"
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
# every entry names its repo (the follow-ups' landing review, item 7): --repo here, the cwd's checkout by default
HB() { env -u DISPATCH_REPO "$HM" mode --branch "$@"; }
CLAUDE_UNATTENDED=dispatch HB claude/rm --repo /x/rm default > /dev/null 2>&1; check "$?" "0" "a run lowers a shipless branch dnd → default"
check "$(hl 'helmlib.branch_mode("claude/rm", "/x/rm")')" "('default', 'helm mode --branch claude/rm')" "  branch_mode reads it first"
check "$(hl 'helmlib.branch_mode("claude/rm", "/y/rm")[0]')" "None" "  keyed by its repo: a same-named branch of another repo keeps its own (item 7)"
CLAUDE_UNATTENDED=dispatch HB claude/rm --repo /x/rm yolo > /dev/null 2>&1; check "$?" "1" "  a run raising it: refused"
CLAUDE_UNATTENDED=dispatch HB claude/rm --repo /x/rm --clear > /dev/null 2>&1; check "$?" "1" "  a run clearing it (the record's dnd decides) is a raise: refused"
check "$(hl 'helmlib.branch_mode("claude/rm", "/x/rm")[0]')" "default" "    …the lowered mode stands"
HB claude/rm --repo /x/rm --clear > /dev/null; check "$(hl 'helmlib.branch_mode("claude/rm", "/x/rm")[0]')" "dnd" "  the owner's --clear: the run record decides again"
env -u DISPATCH_SHIP -u DISPATCH_PLAN env -u DISPATCH_REPO "$HM" mode --branch claude/rm --repo /x/rm default > /dev/null 2>&1
env -u DISPATCH_SHIP -u DISPATCH_PLAN env -u DISPATCH_REPO "$HM" mode --branch claude/rm --repo /x/rm --clear > "$T/bclear.out" 2>&1
check "$?" "0" "--branch --clear outside a session: no ship asked for (follow-ups item 5)"
check "$(hl 'helmlib.branch_mode("claude/rm", "/x/rm")[0]')" "dnd" "  …and cleared"
(cd "$T" && HB claude/rm dnd > "$T/bnorepo.out" 2>&1); check "$?" "1" "outside any repo with no --repo: refused, no key-less entry (item 7)"
has "$(cat "$T/bnorepo.out")" "name the branch's repo (--repo)" "  saying what to name"
git init -q "$T/rr" && git -C "$T/rr" commit -q --allow-empty -m x && git -C "$T/rr" branch claude/rm
RR=$(cd "$T/rr" && pwd -P)
(cd "$T/rr" && HB claude/rm ask > /dev/null 2>&1)
check "$(python3 -c 'import json, sys; print([k for k in json.load(open(sys.argv[1])) if k.endswith("|claude/rm")])' "$PLANS_DIR/branch-modes.json" | grep -c '|claude/rm')" "1" \
  "  inside a repo with no --repo: keyed by the cwd's checkout"
(cd "$T/rr" && HB claude/rm --clear > /dev/null 2>&1)
# the second landing review: an entry typed in the wrong checkout is refused, a relative --repo is the checkout it names
(cd "$T/rr" && HB claude/not-here ask > "$T/bwrong.out" 2>&1); check "$?" "1" "a branch the cwd's checkout lacks: refused, not keyed where no reader looks"
has "$(cat "$T/bwrong.out")" "no branch claude/not-here in" "  naming the repo it looked in"
(cd "$T/rr" && HB claude/rm --repo . ask > /dev/null 2>&1)
check "$(hl 'helmlib.branch_mode("claude/rm", "'"$RR"'")[0]')" "ask" "  --repo . keys by the checkout's path, so its readers find it"
(cd "$T/rr" && HB claude/rm --repo . --clear > /dev/null 2>&1)
# an entry from before entries named their repo: read, but it can only lower (it may be another repo's)
python3 -c 'import json, sys; json.dump({"|claude/rm": {"mode": "yolo", "ts": 1}}, open(sys.argv[1], "w"))' "$PLANS_DIR/branch-modes.json"
check "$(hl 'helmlib.branch_mode("claude/rm", "/x/rm")[0]')" "dnd" "a key-less yolo entry from before: no raise over the record's dnd (item 7)"
python3 -c 'import json, sys; json.dump({"|claude/rm": {"mode": "ask", "ts": 1}}, open(sys.argv[1], "w"))' "$PLANS_DIR/branch-modes.json"
check "$(hl 'helmlib.branch_mode("claude/rm", "/x/rm")[0]')" "ask" "  a key-less ask entry: it still lowers"
check "$(hl 'helmlib.branch_mode("claude/nosent", "/x/rm")')" "(None, 'no sent task on claude/nosent')" "  (no entry, no sent task: no mode)"
python3 -c 'import json, sys; d = json.load(open(sys.argv[1])); d["|claude/nosent"] = {"mode": "yolo", "ts": 1}; json.dump(d, open(sys.argv[1], "w"))' "$PLANS_DIR/branch-modes.json"
check "$(hl 'helmlib.branch_mode("claude/nosent", "/x/rm")[0]')" "None" \
  "a key-less yolo entry on a branch with no sent task: no mode, never a raise (second landing review)"
CLAUDE_UNATTENDED=dispatch HB claude/rm --repo /x/rm ask > /dev/null 2>&1
check "$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1])).get("|claude/rm"))' "$PLANS_DIR/branch-modes.json")" "{'mode': 'ask', 'ts': 1}" \
  "  an unattended keyed write leaves a key-less entry, which may be another repo's (second landing review)"
check "$(hl 'helmlib.yield_branch_entry("claude/rm", "/x/rm", "ask")["mode"]')" "ask" "yield_branch_entry (a newer dispatch --mode, once scheduled): the entry it replaces is returned"
check "$(hl 'helmlib.branch_override("claude/rm", "/x/rm")')" "('ask', 'helm mode --branch claude/rm')" "  …and the branch reads the new word, keyed by its repo, never the older record's dnd"
check "$(hl 'helmlib.yield_branch_entry("claude/none", "/x/rm", "dnd")')" "None" "  a branch with no entry: None, nothing written"
check "$(hl 'helmlib.branch_override("claude/none", "/x/rm")')" "None" "    (still none)"
HB claude/rm --repo /x/rm --clear > /dev/null 2>&1
check "$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1])).get("|claude/rm"))' "$PLANS_DIR/branch-modes.json")" "None" "  the owner's --clear takes the key-less entry too"
for i in 1 2 3 4 5 6 7 8; do HB "claude/par-$i" --repo /x/rm ask > /dev/null 2>&1 & done; wait
check "$(python3 -c 'import json, sys; print(sum("|claude/par-" in k for k in json.load(open(sys.argv[1]))))' "$PLANS_DIR/branch-modes.json")" "8" \
  "  eight writers at once keep every branch: branch-modes.json is written under its lock"
for i in 1 2 3 4 5 6 7 8; do HB "claude/par-$i" --repo /x/rm --clear > /dev/null 2>&1; done
echo "a ship's mode is a ceiling (landing review 6)"
"$HM" mode mgr-1 yolo --task build > /dev/null
out=$("$HM" mode mgr-1 default)
has "$out" "task build: mode yolo cleared — now default" "helm mode <ship> default clears a task's yolo, and says so"
check "$(hl 'helmlib.branch_mode("claude/x")[0]')" "default" "  the branch now reads default"
# a --branch entry stays under the ship's mode: a ship lowered to ask stays ask whatever an older
# `--branch … yolo` says, at landing (branch_mode) and at dispatch's fire time (fire_mode)
HB claude/x --repo /x/tools yolo > /dev/null; "$HM" mode mgr-1 ask > /dev/null
check "$(hl 'helmlib.branch_mode("claude/x", "/x/tools")[0]')" "ask" "a branch entry above the ship's ask: the ship's ceiling wins (the follow-ups' landing review)"
check "$(hl 'helmlib.fire_mode("mgr-1", "build", "/x/tools", None, "claude/x")[0]')" "ask" "  and at fire time"
check "$(hl 'helmlib.fire_mode(None, None, "/x/tools", None, "claude/x")[0]')" "yolo" "  a run with no ship: the entry, the verb it was made for"
HB claude/x --repo /x/tools --clear > /dev/null
"$HM" mode mgr-1 --clear > /dev/null
rm -f "$HOME/Library/Logs/claude-weekly/run-seed-runs/build.json" "$HOME/Library/Logs/claude-weekly/run-seed-runs/finish.json"

echo "a refused blueprint mode stands until a person's helm mode on the ship (follow-ups item 3)"
refuse() { python3 -c 'import json, sys; p = sys.argv[1]; d = json.load(open(p)); d["mode_refused"] = {"mode": "dnd", "why": "x", "ts": 1}; json.dump(d, open(p, "w"))' "$PLANS_DIR/mgr-1/plan.json"; }
refused() { python3 -c 'import json, sys; print("mode_refused" in json.load(open(sys.argv[1])))' "$PLANS_DIR/mgr-1/plan.json"; }
refuse; CLAUDE_UNATTENDED=dispatch "$HM" mode mgr-1 ask > /dev/null 2>&1
check "$(refused)" "True" "an unattended lower leaves the refusal"
"$HM" mode mgr-1 dnd --task build > /dev/null; check "$(refused)" "True" "  a task's mode leaves it too: it speaks of one task"
out=$("$HM" mode mgr-1 --clear); check "$(refused)" "False" "a person's --clear drops it"
has "$out" "the blueprint's mode dnd, refused " "  …and says so"
refuse; "$HM" mode mgr-1 default > /dev/null; check "$(refused)" "False" "  and so does a person's set"
"$HM" mode mgr-1 --task build --clear > /dev/null; "$HM" mode mgr-1 --clear > /dev/null

echo "the board's deploy only on a change (landing review 10)"
check "$(env -u PLAN_NO_DEPLOY PLAN_CACHE_DIR="$T/bcache" python3 - "$B" <<'PY'
import sys, time
sys.path.insert(0, sys.argv[1])
import helm_render as h
calls, cards = [], ["a"]
h.deploy_dir = lambda d, files, space=None, title=None, message=None, by=None: (calls.append(space), ("u1", "https://x"))[1]
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
echo "the board's ops row (lighthouse-ops S2): lighthouse's ops status, hashed by its sig alone"
cat > "$T/ops-stub" <<'PY'
import json, os, sys
mode = open(os.environ["OPS_STUB_MODE"]).read().strip()
if mode == "none":
    print(json.dumps({"row": None, "why": "no sample yet"})); sys.exit(3)
age, sig = mode.split()
print(json.dumps({"row": {}, "age_s": 60, "stale": sig == "stale", "sig": sig,
                  "line": "ops h: queue 1 · load 0.%s/core · sampled %s min ago" % (age, age)}))
PY
check "$(OPS_STUB_MODE="$T/ops-mode" HELM_OPS="$T/ops-stub" python3 - "$B" "$T/ops-mode" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import helm_render as h
def mode(m):
    open(sys.argv[2], "w").write(m)
mode("3 s1"); a = h.ops_row()
mode("8 s1"); b = h.ops_row()
mode("8 s2"); c = h.ops_row()
mode("none"); d = h.ops_row()
st = lambda r: {"columns": [], "header": {"needs_owner": 0, "ops": r and r["line"], "ops_sig": r and r["sig"]}}
print(a["line"], "|", d, "|", h.board_sig(st(a)) == h.board_sig(st(b)), h.board_sig(st(b)) != h.board_sig(st(c)), h.board_sig(st(a)) != h.board_sig(st(None)))
PY
)" "ops h: queue 1 · load 0.3/core · sampled 3 min ago | None | True True True" \
  "ops_row is ops status' line; no sample is no row; board_sig moves with the row's sig, never with its age or gauges in the line"
check "$(HELM_OPS="$T/no-such-ops" python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import helm_render as h; print(h.ops_row())' "$B")" "None" "an ops that fails: no row, never a traceback"
check "$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import helm_render as h; print(h.ops_row(), h.overview_state()["header"]["ops"])' "$B")" "None None" "no ops.jsonl in this host's log dir: no row, and no ops call"
LD=$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import helmlib; print(helmlib._common().LOG_DIR)' "$B")
mkdir -p "$LD"; python3 -c 'import json,sys,time; print(json.dumps({"as_of": int(time.time()) - 7200, "host": "h", "registry": "ok", "queue": None, "slots": {"busy": 1, "max": 4}, "token": {"plan": "absent", "project": "absent"}, "partial": False, "why": {"queue": "no queue home (wharf-runs/queue-repo): the run slots stand for it"}}))' > "$LD/ops.jsonl"
out=$(python3 -c 'import sys, json; sys.path.insert(0, sys.argv[1]); import helm_render as h; s = h.overview_state(); print(json.dumps([s["header"]["ops"], s["header"]["ops_stale"], bool(s["header"]["ops_sig"])], ensure_ascii=False))' "$B")
check "$out" '["ops h: queue off · runs 1/4 · token plan absent, project absent · unread: load, mem, check, budget, weeks, cost · sampled 2 h ago — stale", true, true]' \
  "lighthouse's own ops on a two-hour-old row: the board's header carries its line, stale, and its sig"
has "$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import helm_render as h; print(h.page(h.overview_state(), "t"))' "$B")" "S.header.ops_stale?'stale':''" "…the page draws it as its own row"
rm -f "$LD/ops.jsonl"
echo "the board's intake cards (lighthouse-ops S4): lighthouse's ops intake, a card per open issue, hashed without its clocks"
cat > "$T/intake-stub" <<'PY'
import os, sys
if sys.argv[1:] != ["intake", "--json"]:
    sys.exit(9)
print(open(os.environ["INTAKE_STUB"]).read())
PY
cat > "$T/intake-case.py" <<'PY'
import json, sys
sys.path.insert(0, sys.argv[1])
import helm_render as h
def give(cards):
    open(sys.argv[2], "w").write(json.dumps({"open": cards, "why": None, "sig": "x"}))
a = {"repo": "alpha", "slug": "acme/alpha", "number": 4, "kind": "deadman", "label": "deadman", "created": 1000, "author": "self",
     "url": "https://github.com/acme/alpha/issues/4", "scope": "lab"}
b = dict(a, number=1, kind="contact", label="contact", author="stranger", url="https://github.com/acme/alpha/issues/1")
give([a, b]); one = h.intake_cards()
print([(c["column"], c["kind"], c["title"], c["label"], c["ref"], c["by"], c["url"].rsplit("/", 1)[1]) for c in one])
st = lambda cs: {"columns": [{"name": "Intake", "cards": cs}], "header": {"needs_owner": 0}}
give([dict(a, created=5000), b]); later = h.intake_cards()
give([a, b, dict(b, number=7, kind="bug", label="bug", url="u7")]); more = h.intake_cards()
give([dict(a, created=None), {"repo": "alpha"}, "junk"]); odd = h.intake_cards()
print(h.board_sig(st(one)) == h.board_sig(st(later)), h.board_sig(st(one)) != h.board_sig(st(more)), len(odd), "Intake" in h.board_columns())
PY
check "$(INTAKE_STUB="$T/intake.json" HELM_OPS="$T/intake-stub" python3 "$T/intake-case.py" "$B" "$T/intake.json" | head -1)" \
  "[('Intake', 'intake', 'deadman #4', 'deadman', 'acme/alpha#4', 'self', '4'), ('Intake', 'intake', 'contact #1', 'contact', 'acme/alpha#1', 'stranger', '1')]" \
  "a card per open issue in the Intake column: its kind and number as the title, never the issue's own, the kind its lane, GitHub's link"
check "$(INTAKE_STUB="$T/intake.json" HELM_OPS="$T/intake-stub" python3 "$T/intake-case.py" "$B" "$T/intake.json" | tail -1)" "True True 1 True" \
  "board_sig: an issue's time moves nothing, a new issue deploys; a row without a number is no card"
printf '%s\n' '{"repos": {"alpha": {"github": "acme/alpha"}, "secret": {"github": "acme/secret"}}, "scopes": {"lab": {"repos": ["alpha"]}, "conf": {"repos": ["secret"], "confidential": true}}}' > "$T/intake-conf.json"
printf '%s\n' '{"open": [{"repo": "secret", "slug": "acme/secret", "number": 7, "kind": "bug", "label": "bug", "url": "u7", "scope": "conf"}, {"repo": "alpha", "slug": "acme/alpha", "number": 2, "kind": "bug", "label": "bug", "url": "u2", "scope": "lab"}], "why": null}' > "$T/intake-conf-cards.json"
check "$(CLAUDE_REPOS_JSON="$T/intake-conf.json" INTAKE_STUB="$T/intake-conf-cards.json" HELM_OPS="$T/intake-stub" python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import helm_render as h; print([(c["repo"], c["guarded"]) for c in h.intake_cards()])' "$B")" \
  "[('secret', True), ('alpha', False)]" "a card of a confidential scope (ops keeps them on the scope's own yard): guarded on the shared page"
check "$(HELM_OPS="$T/no-such-ops" python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import helm_render as h; print(h.intake_cards())' "$B")" "[]" "an ops that fails: no card, never a traceback"
check "$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import helm_render as h; print(h.intake_cards())' "$B")" "[]" "no intake-state.json in this host's log dir: no card, and no ops call"
printf '%s\n' '{"repos": {"alpha": {"github": "acme/alpha"}}, "scopes": {}}' > "$T/intake-repos.json"
printf '%s\n' '{"repos": {"alpha": {"since": "2099-01-01T00:00:00Z", "open": {"2": {"number": 2, "kind": "bug", "label": "bug", "created": 1000, "author": "member", "url": "https://github.com/acme/alpha/issues/2"}}}}}' > "$LD/intake-state.json"
check "$(CLAUDE_REPOS_JSON="$T/intake-repos.json" python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import helm_render as h; s = h.overview_state(); print([(c["title"], c["ref"]) for col in s["columns"] if col["name"] == "Intake" for c in col["cards"]])' "$B")" \
  "[('bug #2', 'acme/alpha#2')]" "lighthouse's own ops intake on this host's state: the overview's Intake column"
rm -f "$LD/intake-state.json"
echo "the publish budget: the board and ship pages pause above helm's share (spacesheep-tiers)"
cat > "$T/budget.py" <<'PY'
import json, os, sys, time
sys.path.insert(0, sys.argv[1])
import helm_render as h
log = os.path.join(os.environ["REGATTA_SHEEP_DIR"], "deploys.jsonl")
def fill(n):
    os.makedirs(os.path.dirname(log), exist_ok=True)
    with open(log, "w") as f:
        for _ in range(n):
            f.write(json.dumps({"ts": time.time(), "by": "keel", "ok": True}) + "\n")
calls, cards = [], ["a"]
def dd(d, files, space=None, title=None, message=None, by=None):
    calls.append(json.load(open(os.path.join(d, "state.json")))["header"].get("sheep"))
    return "u1", "https://x"
h.deploy_dir = dd
h.overview_state = lambda: {"kind": "overview", "as_of": time.time(), "header": {"needs_owner": 0, "owner": "Sam", "sheep": h.paused_note()},
                            "timeline": {}, "columns": [{"name": "Needs Sam", "cards": [{"title": c} for c in cards]}]}
h.page = lambda st, title: "x"
sheep = lambda out: [l[:40] for l in out if l.startswith("sheep")]
st = {"space": "sp-1"}; d = h.cache_root() / "p9"; d.mkdir(parents=True, exist_ok=True)
if sys.argv[2] == "board-first":
    fill(149); h.overview(deploy=True); print("under:", len(calls), calls[-1])
    fill(150); cards.append("b"); out = h.overview(deploy=True)
    print("crossing:", len(calls), (calls[-1] or "")[:40], [l for l in out if "paused" in l][0][-20:])
    cards.append("c"); os.environ["HELM_BOARD_POLL"] = "1"; out = h.overview(deploy=True)
    print("paused, the poll:", len(calls), sheep(out), (h.overview_state()["header"]["sheep"] or "")[:16])
    del os.environ["HELM_BOARD_POLL"]; out = h.overview(deploy=True)
    print("paused, by hand:", len(calls), sheep(out))
    print("ship:", h.sheep_line("p9", st, d, None, {"live": "redeploy"})[:33])
    fill(0); out = h.overview(deploy=True)
    print("resumed, no card moved:", len(calls), calls[-1], (h.cache_root() / h.PAUSED).exists())
    out = h.overview(deploy=True); print("then unchanged:", len(calls), sheep(out)[0][:22])
elif sys.argv[2] == "ship-first":
    h.overview(deploy=True)
    fill(150); print("ship:", h.sheep_line("p9", st, d, None, {"live": "redeploy"})[:33], (h.cache_root() / h.PAUSED).exists())
    cards.append("b"); h.overview(deploy=True)
    print("board:", len(calls), (calls[-1] or "")[:24], (h.cache_root() / h.PAUSED).exists())
else:   # a refusal the server sent: kept with its retry, then helm holds though the count is low
    h.overview(deploy=True)
    import asklib
    asklib._common().sheep_record("helm-board", ok=False, err="deploy refused — rate_limited: 400 publishes per 24h (retry in 900s)")
    cards.append("b"); out = h.overview(deploy=True)
    print("refused:", len(calls), sheep(out)[0][:38], (h.cache_root() / h.PAUSED).exists())
    print("ship:", h.sheep_line("p9", st, d, None, {"live": "redeploy"})[:38])
PY
mkdir -p "$T/budget-cfg/sheep"; echo 2 > "$T/budget-cfg/sheep/machines"
bud() { env -u PLAN_NO_DEPLOY -u HELM_BOARD_POLL REGATTA_SHEEP_PLAN=free REGATTA_CONFIG="$T/budget-cfg" PLAN_CACHE_DIR="$T/budget-cache-$1" \
          REGATTA_SHEEP_DIR="$T/budget-sheep-$1" python3 "$T/budget.py" "$B" "$1" 2>&1 | tr '\n' '|'; }
check "$(bud board-first)" \
  "under: 1 None|crossing: 2 redeploys paused: 150 of this Mac's 150   (after this deploy)|paused, the poll: 2 [] redeploys paused|paused, by hand: 2 ['sheep: redeploys paused: 150 of this Mac']|ship: sheep: redeploys paused: 150 of t|resumed, no card moved: 3 None False|then unchanged: 3 sheep: unchanged since|" \
  "Free on two machines: the 150th deploy carries the note and says so once; the poll then silent, a hand-run says why; the ship page too; back under, the board redeploys though no card moved"
check "$(bud ship-first)" "ship: sheep: redeploys paused: 150 of t False|board: 2 redeploys paused: 150 of True|" \
  "a ship page crossing first holds without writing the marker, so the board's own crossing still deploys the note and writes it"
check "$(bud refused | sed 's/at [0-9:]*/at HH:MM/')" "refused: 1 sheep: redeploys paused: spacesheep re True|ship: sheep: redeploys paused: spacesheep re|" \
  "a cap refusal from the server pauses the board and the ship pages though the count is low"
cat > "$T/stream.py" <<'PY'
import os, sys, time
sys.path.insert(0, sys.argv[1])
import helm_render as h
print(h.stream_taken(sys.argv[2]))
PY
SSB="$T/stream-bin"; mkdir -p "$SSB"
cat > "$SSB/spacesheep" <<'EOF'
#!/bin/sh
case "$2" in
  plans/fresh) printf '[{"path": "plans/fresh", "last_at": %s000}]\n' "$(date +%s)" ;;
  plans/stale) printf '[{"path": "plans/stale", "last_at": %s000}]\n' "$(( $(date +%s) - 600 ))" ;;
  plans/refused) printf '\n  ✗ plan_required\n\n' >&2; exit 1 ;;
  plans/forbidden) printf '\n  ✗ HTTP 403\n\n' >&2; exit 3 ;;
  plans/http500) printf '\n  ✗ HTTP 500\n\n' >&2; exit 1 ;;
  plans/offline) printf '\n  ✗ fetch failed\n\n' >&2; exit 1 ;;
  *) echo '[]' ;;
esac
EOF
chmod +x "$SSB/spacesheep"
st() { env MEMO_SHEEP_BIN="$SSB/spacesheep" PLAN_CACHE_DIR="$T/stream-cache" "$@" python3 "$T/stream.py" "$B" "$PID_"; }
PID_=fresh; check "$(st)" "True" "a stream process whose values the server shows fresh: live"
PID_=stale; check "$(st)" "False" "  silent for 10 min: not live, the page redeploys"
PID_=refused; check "$(st)" "False" "  refused plan_required (the process keeps running: CLI 1.31.0): not live"
PID_=gone; check "$(st)" "False" "  absent from the server's list: not live"
PID_=forbidden; check "$(st)" "False" "  the key refused (exit 3): not live"
PID_=http500; check "$(st)" "False" "  any other refusal the CLI throws (HTTP 500), no plan_required in it: not live"
PID_=offline; check "$(st)" "True" "  only a fetch that never reached the server (fetch failed) trusts the process"
PID_=fresh2; check "$(st REGATTA_SHEEP_PLAN=free)" "False" "  no Pro, so no Max: not live, the CLI not asked"

echo "helm page: a skipper's page, published once (peer-manager-relay S1, D1-A)"
PG="$T/page"; mkdir -p "$PG/bin"
cat > "$PG/bin/spacesheep" <<EOF
#!/bin/sh
echo "\$*" >> "$PG/sheep.calls"
[ -e "$PG/sheep.fail" ] && { echo '{"error": "the service is away"}'; exit 1; }
echo '{"uuid": "sp-page", "url": "https://example.invalid/s/sp-page"}'
EOF
chmod +x "$PG/bin/spacesheep"
# a scratch store, cache and deploy log of the block's own; PLAN_NO_DEPLOY off, a Pro account with Talk
pg() { env -u PLAN_NO_DEPLOY PLANS_DIR="$PG/plans" PLAN_CACHE_DIR="$PG/cache" REGATTA_SHEEP_DIR="$PG/sheep" \
         MEMO_SHEEP_BIN="$PG/bin/spacesheep" SPACESHEEP_KEY=k-test SPACESHEEP_URL=https://talk.invalid REGATTA_SHEEP_PLAN=pro CLAUDE_CODE_SESSION_ID=sk-1 "$@"; }
pgo=$(pg "$LX/helm" page sk-1 2>"$PG/err"); rc=$?
check "$rc $pgo" "0 sp-page" "a skipper with no ship: its ship made, its page published, the space printed"
check "$(python3 -c "import json; p=json.load(open('$PG/plans/sk-1/plan.json')); print(p['space'], p['topic'], p['manager']['session'])")" \
  "sp-page skipper sk-1 sk-1" "  plan.json keeps the space, a topic that names the skipper, and the skipper's session"
check "$(grep -c '^deploy ' "$PG/sheep.calls")" "1" "  one deploy"
check "$(python3 -c "import json; print([json.loads(l)['by'] for l in open('$PG/sheep/deploys.jsonl')])")" "['helm-ship']" "  counted in this Mac's publish log, as a ship page"
pgo=$(pg "$LX/helm" page sk-1 2>&1); rc=$?
check "$rc $pgo" "0 sp-page" "a skipper that has a page: the same space"
check "$(grep -c '^deploy ' "$PG/sheep.calls")" "1" "  and no second publish"
pg "$LX/helm" ship "a ship of its own" --id sk-own >/dev/null
check "$(pg "$LX/helm" page sk-own 2>&1 | tr '\n' '|'; python3 -c "import json; print(json.load(open('$PG/plans/sk-own/plan.json'))['topic'])")" \
  "sp-page|a ship of its own" "a ship with no page yet: published into it, its topic kept"
n0=$(grep -c '^deploy ' "$PG/sheep.calls")
LIM=$(env REGATTA_SHEEP_PLAN=pro python3 -c "import sys; sys.path.insert(0, '$B'); import asklib; print(asklib._common().sheep_budget(asklib.sheep_plan())['helm_limit'])")
mkdir -p "$PG/full"; python3 -c "import json, time; open('$PG/full/deploys.jsonl', 'w').writelines(json.dumps({'ts': time.time(), 'by': 'keel', 'ok': True}) + '\n' for _ in range($LIM))"
pgo=$(pg env REGATTA_SHEEP_DIR="$PG/full" "$LX/helm" page sk-2 2>"$PG/err"); rc=$?
check "$rc [$pgo] $(cut -c1-28 "$PG/err")" "3 [] helm page: redeploys paused:" "helm's publish budget held: exit 3, said in one line, nothing printed"
check "$([ -e "$PG/plans/sk-2" ] && echo made || echo none) $(grep -c '^deploy ' "$PG/sheep.calls")" "none $n0" "  no ship made, no publish tried"
pgo=$(pg env REGATTA_SHEEP_PLAN=free "$LX/helm" page sk-3 2>"$PG/err"); rc=$?
check "$rc $(cat "$PG/err")" "3 helm page: Talk needs spacesheep Pro (spacesheep.dev/plans): a page would carry no ask" \
  "an account without Talk: refused, since a page would carry no ask and cost a publish"
pgo=$(pg env MEMO_SHEEP_BIN= "$LX/helm" page sk-3 2>"$PG/err"); rc=$?
check "$rc $(cat "$PG/err")" "3 helm page: no spacesheep CLI on this Mac" "no CLI: refused"
pgo=$(pg env -u SPACESHEEP_KEY ASK_NO_KEY_FILES=1 "$LX/helm" page sk-3 2>"$PG/err"); rc=$?
check "$rc $(cat "$PG/err") $([ -e "$PG/plans/sk-3" ] && echo made || echo none)" "3 helm page: no SPACESHEEP_KEY on this Mac none" \
  "no key: refused, so a suite's moved HOME never publishes a real page; none of the refusals made a ship"
cp -R "$REGATTA_CONFIG" "$PG/cfg"; rm -f "$PG/cfg/helm/talk-url"   # plain -R: links stay links (AGENTS.md's Traps)
pgo=$(pg env -u SPACESHEEP_URL REGATTA_CONFIG="$PG/cfg" "$LX/helm" page sk-3 2>"$PG/err"); rc=$?
check "$rc $(cut -c1-32 "$PG/err") $([ -e "$PG/plans/sk-3" ] && echo made || echo none)" "3 helm page: no Talk service named none" \
  "no Talk service named: refused, as Talk.available() refuses every relay to it (the landing review)"
pgo=$(pg env PLAN_NO_DEPLOY=1 "$LX/helm" page sk-3 2>"$PG/err"); rc=$?
check "$rc $(cat "$PG/err")" "3 helm page: no deploy here (PLAN_NO_DEPLOY)" "PLAN_NO_DEPLOY: refused, so no suite publishes"
touch "$PG/sheep.fail"
pgo=$(pg "$LX/helm" page sk-4 2>"$PG/err"); rc=$?
check "$rc [$pgo] $(cut -c1-31 "$PG/err")" "3 [] helm page: sheep: deploy failed" "a deploy that fails: exit 3 with the CLI's line"
check "$(python3 -c "import json; print(json.load(open('$PG/plans/sk-4/plan.json')).get('space'))")" "None" "  the ship stays, with no space: the next dispatch tries again"
rm -f "$PG/sheep.fail"
check "$(pg "$LX/helm" page sk-4 2>&1)" "sp-page" "  …and the next one publishes"

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
check "$(PLAN_NO_GH=1 python3 -c "
import sys; sys.path.insert(0, '$B'); import helmlib
print(sorted(helmlib.prefetch_prs(['/x/transcripts', '/x/garden'])))")" \
  "['/x/garden']" "  prefetch_prs never reads a guarded repo's PRs (K6)"
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
check "$("$HM" state | python3 -c "import json,sys; t=[t for t in json.load(sys.stdin)['tasks'] if t['id']=='build'][0]; print(t['est_to_go'], t['est_kind'])")" "2.0 manager" "the skipper's estimate wins when set"
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
  check "$(echo "$ov" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['columns'][0]['name'], len(d['columns']))")" "Needs Sam 7" "seven columns (Intake last, lighthouse-ops S4), Needs Sam first"
  check "$(echo "$ov" | python3 -c "import json,sys; d=json.load(sys.stdin); print(sorted(c['title'] for col in d['columns'] if col['name']=='Blocked' for c in col['cards']))")" "['Sam reviews']" "a human task whose dependency is not done is Blocked"
  "$HM" task mgr-1 sign --kind human $BY alex --title "Alex signs" > /dev/null
  mkdir -p "$T/projects-root/garden"; printf -- '- [porch-bulb] swap the porch bulb @sam\n- [session-item] a session item\n' > "$T/projects-root/garden/TODO.md"
  ov=$("$HM" $BOARD --json)
  check "$(echo "$ov" | python3 -c "import json,sys; d={c['name']:[x['title'] for x in c['cards']] for c in json.load(sys.stdin)['columns']}; print(d['Needs Alex'], d['Needs Sam'])")" "['Alex signs'] ['swap the porch bulb']" "human tasks and @-tagged TODO lines are cards in their owner's column, the item's id off the card"
  check "$(echo "$ov" | python3 -c "import json,sys; d={c['name']:[x['title'] for x in c['cards']] for c in json.load(sys.stdin)['columns']}; print('guarded — open it' in d['Running'])")" "True" "a guarded task keeps its column and nothing else"
  check "$(echo "$ov" | python3 -c "import json,sys; r=json.load(sys.stdin)['timeline'][0]; print(r['plan'], len(r['bars']) > 3, r['milestones'][0]['name'])")" "demo True alpha" "the timeline: a row per plan, bars and milestones (B7)"
  hasnt "$ov" "IBAN" "the board never carries a guarded row's text"
  check "$(echo "$ov" | python3 -c "import json,sys; ids=[b['id'] for r in json.load(sys.stdin)['timeline'] for b in r['bars']]; print('secret' in ids, 'taxes' in ids, sum(i.startswith('guarded-') for i in ids))")" "False False 3" "the timeline's bars carry the guarded tokens, never the ids (second review, finding 8)"
  # crosstalk S6: the lookout's open cards (keel lookout --status --json) are cards in the owner's column
  printf '#!/usr/bin/env python3\nimport json, sys\nassert sys.argv[1:] == ["lookout", "--status", "--json"], sys.argv\nprint(json.dumps({"armed": True, "cards": [\n {"doc": "demo@claude/buildbox/2026-10-21-x:docs/d.md", "id": "e1", "items": ["D1"], "host": "laptop", "ts": 1760000000, "card": "no live session for demo@claude/buildbox/2026-10-21-x:docs/d.md D1 — the run would start here"},\n {"doc": "transcripts@claude/laptop/2026-10-21-y:docs/p.md", "id": "e2", "items": [], "card": "a guarded one"}, {"id": "e3"}]}))\n' > "$T/keelstub"
  printf 'import json, sys\nd = json.load(sys.stdin)\nprint(json.dumps([[c["title"], c.get("repo"), c.get("ref"), c.get("evidence")] for col in d["columns"] if col["name"] == "Needs Sam" for c in col["cards"] if c["kind"] == "lookout"]))\n' > "$T/lc.py"
  lc() { python3 "$T/lc.py"; }
  check "$(PLAN_KEEL="$T/keelstub" "$HM" $BOARD --json | lc)" \
    '[["docs/d.md D1", "demo", "claude/buildbox/2026-10-21-x", "no live session for demo@claude/buildbox/2026-10-21-x:docs/d.md D1 \u2014 the run would start here"], ["guarded \u2014 open it", "guarded", null, null]]' \
    "the lookout's open cards: doc, branch and why in the owner's column; a guarded repo's card keeps its column and nothing else"
  check "$("$HM" $BOARD --json | lc)" "[]" "no lookout cards without keel's status (PLAN_NO_MEMO): none, the board renders"
  printf '#!/usr/bin/env python3\nimport sys\nsys.exit(2)\n' > "$T/keelold"
  check "$(PLAN_KEEL="$T/keelold" "$HM" $BOARD --json | lc)" "[]" "a keel without --json (exit 2, no output): no cards, the board renders"
  # S6 landing review 19: the peer's lookout cards, read over the stall cards' ssh road (STALLS_PEERS,
  # STALLS_SSH), their why led by the host; once the peer answered, this Mac's card that only says the
  # peer's own lookout acts is dropped. The stub prints its JSON with printf %s and spells the
  # apostrophe as JSON's \u0027: an `echo '…\x27…'` is valid JSON only where /bin/sh is bash, whose
  # POSIX-mode echo expands \x27; dash's (ubuntu's sh) keeps it, the peer's answer stops parsing and
  # its cards vanish (twin-ci-2, 2026-10-25)
  printf '#!/usr/bin/env python3\nimport json\nprint(json.dumps({"cards": [{"doc": "demo@claude/buildbox/2026-10-21-z:docs/z.md", "items": ["D2"], "card": "another host\x27s branch: its own lookout starts the run"}, {"doc": "demo@claude/laptop/2026-10-21-w:docs/w.md", "items": [], "card": "here"}]}))\n' > "$T/keelhere"
  printf '#!/bin/sh\nfor a; do last=$a; done\n[ "$last" = "python3 -" ] || exit 9\ngrep -q %s - || exit 8\nprintf "%%s\\n" %s\n' "'common.tool(\"keel\")'" \
    "'{\"armed\": true, \"cards\": [{\"doc\": \"demo@claude/buildbox/2026-10-21-z:docs/z.md\", \"items\": [\"D2\"], \"card\": \"no live session — the run would start here\"}, {\"doc\": \"demo@claude/laptop/2026-10-21-w:docs/w.md\", \"items\": [], \"card\": \"on another host\\u0027s branch, pushed within 24h — its lookout acts\"}]}'" > "$T/ssh-lookout"
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
  # the embark memo (embark-on-helm, 2026-10-25): the newest open one leads the owner's column, labelled
  # Embark — from a lookout card (here another host's branch) or a memo card
  printf '#!/usr/bin/env python3\nimport json\nprint(json.dumps({"armed": True, "cards": [{"doc": "demo@claude/laptop/2026-10-21-w:docs/w.md", "items": ["D1"], "card": "here"}, {"doc": "regatta@claude/buildbox/2026-10-25-embark:docs/embark/embark-2026-10-25.md", "items": ["D1", "D2"], "card": "no live session"}]}))\n' > "$T/keelembark"
  chmod +x "$T/keelembark"
  printf 'import json, sys\nc = [x for col in json.load(sys.stdin)["columns"] if col["name"] == "Needs Sam" for x in col["cards"]][0]\nprint(c["title"], "|", c.get("label"))\n' > "$T/first_card.py"
  check "$(PLAN_KEEL="$T/keelembark" "$HM" $BOARD --json | python3 "$T/first_card.py")" \
    "Embark 2026-10-25 — docs/embark/embark-2026-10-25.md D1 D2 | Embark" "the embark memo's card leads the owner's column, labelled Embark, from another host's branch"
  cat > "$T/embark_first.py" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import helm_render as h
col = h.helmlib.columns()[0]
cards = [h._card("ask", "an ask", col), h._card("memo", "Embark 2026-10-18 - old", col, doc="/p/regatta/docs/embark/embark-2026-10-18.md"),
         h._card("memo", "Embark 2026-10-25 - new", col, doc="/p/regatta/.claude/worktrees/embark-2026-10-25/docs/embark/embark-2026-10-25.md"),
         h._card("memo", "another doc", col, doc="/p/x/docs/embark-notes.md"), h._card("memo", "elsewhere", "Running", doc="/p/docs/embark/embark-2026-10-30.md")]
out = h.embark_first(cards)
print([c["title"] for c in out][:3], out[0].get("label"), len(out), h.embark_first(cards[:1] + cards[3:4]) == cards[:1] + cards[3:4])
PY
  check "$(python3 "$T/embark_first.py" "$B")" "['Embark 2026-10-25 - new', 'an ask', 'Embark 2026-10-18 - old'] Embark 5 True" \
    "  the newest of two embark memos first, the older where it was; one in another column is not the owner's; none: unchanged"
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
  check "$(echo "$s5" | sed -n 1p)" "[('waiting', 't · waiting on Sam', 'regatta', 'testhost', 'vscode://anthropic.claude-code/open?session=s1', 'Needs Sam'), ('waiting', 'u · waiting on Sam', 'regatta', 'buildbox', 'https://github.com/o/regatta/tree/claude/u', 'Needs Sam')]" \
    "a WAITING card is its topic, 'waiting on Sam', the repo and a link: this Mac's session opens in VS Code, a peer's branch on GitHub"
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
        (("link", "/p/r"), ("bold", "/p/r"), ("quoted", "/p/r"), ("guard", "/p/secret/.claude/worktrees/t"), ("other", "/p/r"),
         ("marked", "/p/r"), ("unspaced", "/p/r"))]
texts = {"link": "Done.\nOWNER, " + W + "\n[course](https://x) | [github](https://y) — [d.md](/p/d.md#L1)",
         "bold": "**OWNER, " + W + "**", "quoted": "OWNER, " + W + "\nand then more prose",
         "guard": "OWNER, " + W, "other": "SOMEONE ELSE, " + W, "marked": "Built.\n**\U0001F6D1 OWNER, " + W + "**",
         "unspaced": "Built.\n\U0001F6D1OWNER, " + W}
ad = types.SimpleNamespace(list=lambda: recs, status=lambda *a, **k: None, last_reply=lambda sid: {"text": texts[sid]})
print([w["session_id"] for w in stalls.facts([], ad, lambda st: False, lambda st: True, ("secret",), "OWNER, THIS SESSION IS WAITING FOR YOU — ")["waiting"]],
      [w["session_id"] for w in stalls.facts([], ad, lambda st: False, lambda st: True, (), "THIS SESSION IS WAITING FOR YOU — ")["waiting"]])
PY
)
  check "$fx" "['link', 'bold', 'marked', 'unspaced'] ['link', 'bold', 'guard', 'other', 'marked', 'unspaced']" \
    "  the WAITING line as common.ending reads it: link lines after it, markup and its mark (🛑, spaced or not) around it; a guarded repo's reply unread; the owner's address from config (landing review 15, 16; marks 2026-10-29)"
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
  rm_own "$R"

  echo "B1: stalls — S1–S7 from records, the registry, autofinished, the plan store and the poll cache"
  # Fixtures shaped on the real ones of P1, P2 and P4 (chain-manager section 3), ids changed: a repo
  # with the branches the records name, transcripts, registry files, autofinished lines, a plan, and
  # a stubbed ssh that runs the probe against a second HOME standing in for buildbox.
  now=$(date +%s); R="$HOME/Library/Logs/claude-weekly/run-seed-runs"; mkdir -p "$R" "$HOME/.claude/projects/-t"
  D="$T/repos/demo"; mkdir -p "$D"; git -C "$D" init -q -b main; git -C "$D" commit -q --allow-empty -m x
  for b in gone-step pending-step queued-step cap-step parked-step asked-step done-step relay-step ended-step lifetime-step live-wait live-work unsure-step gate-launch quote-launch; do
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
  # S6 orphaned relay: RELAYED, its skipper not in any registry
  rec 11-relay.json relay-step started=$((now-7200)) ended=$((now-3600)) "end_reason=idle 60 min" manager=mgr-gone
  say sid-relay-step "RELAYED TO mgr-gone — D1 in docs/x.md"
  # S1: ended on WAITING FOR SOMETHING and nothing picked it up again (2026-10-20)
  rec 13-pending.json pending-step started=$((now-7200)) ended=$((now-3600)) "end_reason=idle 60 min"
  say sid-pending-step "SAM, THIS SESSION IS WAITING FOR SOMETHING — the two reviewers"
  # dispatch-queue S3: a run that queued its step and ended on the queue's closing line — dispatch's queue
  # holds its branch (the stand-in below), so it is `queued`, never S1's retry of the step the queue holds
  rec 14-queued.json queued-step started=$((now-7200)) ended=$((now-3600)) "end_reason=idle 60 min"
  say sid-queued-step "Queued.
SAM, THIS SESSION IS WAITING FOR SOMETHING — queued claude/t/2026-10-14-queued-step (normal); the next step waits for a run to end; the skipper finishes it"
  printf '#!/bin/sh\necho %s\n' "'{\"entries\": [{\"repo\": \"$(basename "$D")\", \"branch\": \"claude/t/2026-10-14-queued-step\", \"state\": \"queued\"}], \"unreadable\": false, \"why\": []}'" > "$T/dq-list"
  printf '#!/bin/sh\necho %s\n' "'{\"entries\": [], \"unreadable\": false, \"why\": []}'" > "$T/dq-empty"
  printf '#!/bin/sh\necho %s\n' "'{\"entries\": [], \"unreadable\": true, \"why\": [\"fleet: unreachable\"]}'" > "$T/dq-torn"
  chmod +x "$T/dq-list" "$T/dq-empty" "$T/dq-torn"
  export STALLS_DISPATCH_QUEUE="$T/dq-list"
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
  printf '{"mode":"rc","repo":"%s","topic":"lifetime-step","branch":"claude/t/2026-10-14-lifetime-step","session":"sid-life","started":"%s","ended":"%s","end_reason":"max lifetime 8.0 h","cut":{"checks":[{"pid":4242,"out":"/tmp/ck5"}],"limit":"You have hit a limit"}}' \
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
    echo "2026-10-14T01:15:00-07:00 stopped claude/t/2026-10-14-gate-launch G1r ⚠ step 1 — the review found a defect"
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
  check "$(got "s=[x for x in d['stalls'] if x['class']=='S3'][0]; print([e for e in s['evidence'] if e.startswith('cut ')])")" \
    "['cut its check pid 4242, out /tmp/ck5', 'cut at a usage limit: You have hit a limit']" "  S3: what the cap cut, from the record's cut (yard-followups)"
  check "$(got "s=[x for x in d['stalls'] if x['class']=='S3'][0]; print(s['host'], s['action'], s['column'], s['since'] > 0)")" "buildbox raise Needs Sam True" \
    "  S3: read on buildbox through ssh, its digit-string start typed, raised"
  check "$(got "s=[x for x in d['stalls'] if x['class']=='S4'][0]; print(s['action'], s['key'][1], s['key'][2] == '$tip', s['worktree'].endswith('/net'))")" \
    "relaunch claude/t/2026-10-14-net-launch True True" "  S4: relaunch, keyed (host, branch, tip), the last stop of its branch counts"
  check "$(got "print(sorted(x['rule'] for x in d['stalls'] if x['class']=='S5'))")" "['S4 stop, but the tip moved since (1111111 → ${tip:0:7})', 'WAITING line', 'gate G1r']" "  S5: a gate (the review's G1r too, its branch's last stop); a WAITING line that quotes an API error is no S4 (R4); nor a network stop on a tip that moved"
  check "$(got "print(sorted(x['rule'] for x in d['stalls'] if x['class']=='S6'))")" "['closing line: RELAYED, its skipper gone', 'closing line: WAITING', 'live: waiting']" \
    "  S6: a parked WAITING line, a permission prompt, an orphaned relay"
  check "$(got "s=[x for x in d['stalls'] if x['class']=='S7'][0]; print(s['key'], s['raise_to'], s['column'])")" "['testhost', 's7', 'b'] owner Needs Sam" \
    "  S7: keyed (host, plan, task), to the owner while its skipper is not live"
  check "$(got "print([(u['topic'], u['action'], u['class']) for u in d['unsure']])")" "[('unsure-step', 'classify', None)]" \
    "  no closing line: unsure, shaped for B3's classifier, never a stall"
  hasnt "$sj" "IBAN 5555" "  a guarded run's reply is never read"
  check "$(got "print([(x['topic'], x['why']) for x in d['queued']], any(n.startswith('queued: queued-step on testhost') for n in d['notes']))")" \
    "[('queued-step', \"in dispatch's queue\")] True" "dispatch-queue S3: a run on the queue's closing line, its branch in the queue: a queued card, not a stall"
  qj=$(STALLS_DISPATCH_QUEUE="$T/dq-empty" STALLS_PEERS=buildbox=fake STALLS_SSH="$T/ssh-ok" python3 "$B/stalls.py" --json)
  check "$(echo "$qj" | python3 -c "import json,sys; print([(s['class'], s['action']) for s in json.load(sys.stdin)['stalls'] if s['topic']=='queued-step'])")" "[('S1', 'retry')]" \
    "  its entry gone from the queue (ran and ended, or failed): S1 as before"
  qj=$(STALLS_DISPATCH_QUEUE="$T/dq-torn" STALLS_PEERS=buildbox=fake STALLS_SSH="$T/ssh-ok" python3 "$B/stalls.py" --json)
  check "$(echo "$qj" | python3 -c "import json,sys; d=json.load(sys.stdin); print(sorted(x['topic'] for x in d['queued']), [s['class'] for s in d['stalls'] if s['topic'] in ('queued-step', 'cap-step')], any(n.startswith('queue: unreadable') for n in d['notes']))")" \
    "['queued-step'] ['S2'] True" "  a queue that does not read holds every branch on the pending line (the readers' rule), a note; the cap's words alone are S2, as before the queue"
  # dispatch-queue S4: one confidential scope's node-local store torn holds that scope's branches only (queue_holds)
  printf '#!/bin/sh\necho %s\n' "'{\"entries\": [], \"unreadable\": true, \"why\": [\"local=vault: torn\"], \"bad_stores\": [{\"store\": \"local=vault\", \"why\": \"torn\", \"keys\": [\"vault--other\"]}]}'" > "$T/dq-local-torn"
  chmod +x "$T/dq-local-torn"
  qj=$(STALLS_DISPATCH_QUEUE="$T/dq-local-torn" STALLS_PEERS=buildbox=fake STALLS_SSH="$T/ssh-ok" python3 "$B/stalls.py" --json)
  check "$(echo "$qj" | python3 -c "import json,sys; d=json.load(sys.stdin); print(sorted(x['topic'] for x in d['queued']), [(s['class'], s['action']) for s in d['stalls'] if s['topic']=='queued-step'])")" \
    "[] [('S1', 'retry')]" "  S4: a torn node-local store holds only the keys its files name: this branch's is not among them"
  # dispatch-queue S3's third landing review, item 6: the exact pending line, judged by the branch it names
  say sid-queued-step "Queued.
SAM, THIS SESSION IS WAITING FOR SOMETHING — the two reviewers; the next step waits for a run to end"
  qj=$(STALLS_PEERS=buildbox=fake STALLS_SSH="$T/ssh-ok" python3 "$B/stalls.py" --json)
  check "$(echo "$qj" | python3 -c "import json,sys; print([s['class'] for s in json.load(sys.stdin)['stalls'] if s['topic']=='queued-step'])")" "['S1']" \
    "item 6: the cap's words on another line, its branch in the queue: no pending line, so S1, never queued"
  say sid-queued-step "Queued.
SAM, THIS SESSION IS WAITING FOR SOMETHING — queued claude/t/2026-10-14-queued-step (normal); the next step waits for a run to end; the skipper finishes it
[the doc](https://example.invalid/doc)"
  qj=$(STALLS_PEERS=buildbox=fake STALLS_SSH="$T/ssh-ok" python3 "$B/stalls.py" --json)
  check "$(echo "$qj" | python3 -c "import json,sys; print([x['topic'] for x in json.load(sys.stdin)['queued']])")" "['queued-step']" \
    "  the pending line with a link line after it (the Stop hook's ending): queued"
  say sid-queued-step "Queued.
SAM, THIS SESSION IS WAITING FOR SOMETHING — queued claude/t/2026-10-14-queued-step (normal); the next step waits for a run to end; the skipper finishes it
Then a question came up.
$WAIT — D2 in docs/x.md"
  qj=$(STALLS_PEERS=buildbox=fake STALLS_SSH="$T/ssh-ok" python3 "$B/stalls.py" --json)
  check "$(echo "$qj" | python3 -c "import json,sys; d=json.load(sys.stdin); print([x['topic'] for x in d['queued']], [s['class'] for s in d['stalls'] if s['topic']=='queued-step'])")" "[] ['S6']" \
    "  the pending line quoted above an owner's WAITING line: that line is the closing one, S6, never queued (the in-round review)"
  printf '#!/bin/sh\necho %s\n' "'{\"entries\": [{\"repo\": \"$(basename "$D")\", \"branch\": \"claude/t/2026-10-14-other-step\", \"state\": \"queued\"}], \"unreadable\": false, \"why\": []}'" > "$T/dq-other"; chmod +x "$T/dq-other"
  say sid-queued-step "Queued.
SAM, THIS SESSION IS WAITING FOR SOMETHING — queued claude/t/2026-10-14-other-step (normal); the next step waits for a run to end; the skipper finishes it"
  qj=$(STALLS_DISPATCH_QUEUE="$T/dq-other" STALLS_PEERS=buildbox=fake STALLS_SSH="$T/ssh-ok" python3 "$B/stalls.py" --json)
  check "$(echo "$qj" | python3 -c "import json,sys; d=json.load(sys.stdin); print([(x['topic'], x['branch']) for x in d['queued']], [s['class'] for s in d['stalls'] if s['topic']=='queued-step'])")" \
    "[('queued-step', 'claude/t/2026-10-14-other-step')] []" "  a run that queued another branch, which the queue holds: queued on that branch, never S1's retry of finished work"
  say sid-queued-step "Queued.
SAM, THIS SESSION IS WAITING FOR SOMETHING — queued claude/t/2026-10-14-queued-step (normal); the next step waits for a run to end; the skipper finishes it"
  # skipper-resilience S8: a peer some scope's yard names is read and judged (the board shows its stalls),
  # and acted on only by its own tick; a torn registry: no peer's stall acted on (fail closed)
  echo '{"repos": {}, "scopes": {"dock": {"repos": [], "yard": "buildbox"}}}' > "$T/yard-bb.json"
  printf '{"repos": {}, "scopes": {"dock": ' > "$T/yard-torn.json"
  yj=$(CLAUDE_REPOS_JSON="$T/yard-bb.json" STALLS_PEERS=buildbox=fake STALLS_SSH="$T/ssh-ok" python3 "$B/stalls.py" --json)
  check "$(echo "$yj" | python3 -c "import json,sys; d=json.load(sys.stdin); print([s['topic'] for s in d['stalls'] if s['host']=='buildbox'], d['self_judging'], d['registry_torn'])")" \
    "['lifetime-step'] ['buildbox'] False" "S8: the yard's S3 judged for the board, the yard named as acting on its own"
  check "$(echo "$yj" | python3 -c "import json,sys; print(len(json.load(sys.stdin)['stalls']))")" "$(got "print(len(d['stalls']))")" \
    "  every stall as before"
  yt=$(CLAUDE_REPOS_JSON="$T/yard-bb.json" STALLS_PEERS=buildbox=fake STALLS_SSH="$T/ssh-ok" STALLS_LOG="$T/yard-tick.jsonl" "$HM" tick --dry-run)
  hasnt "$yt" "S3 buildbox" "  the laptop's tick acts on none of the yard's stalls"
  has "$yt" "S8: the stalls of buildbox are left to their own tick (1)" "  and says so"
  # dispatch-queue S10(e): a run its host handed back (dispatch --requeue), its step in the queue, is no stall and
  # reads where it went; one the queue no longer holds is judged as before. An unreachable peer that may sleep (a
  # `sleeps` line) with no fresh queue word reads asleep; a host with no such word stays unreachable
  git -C "$D" branch claude/t/2026-10-14-requeued-step
  rec 9r-requeued.json requeued-step started=$((now-7200)) ended=$((now-3000)) "end_reason=exit 143" "ending=requeued from laptop (lid)"
  printf '#!/bin/sh\necho %s\n' "'{\"entries\": [{\"repo\": \"$(basename "$D")\", \"branch\": \"claude/t/2026-10-14-requeued-step\", \"state\": \"queued\", \"requeued_from\": \"laptop\"}], \"unreadable\": false, \"why\": []}'" > "$T/dq-rq"; chmod +x "$T/dq-rq"
  rj=$(STALLS_DISPATCH_QUEUE="$T/dq-rq" STALLS_PEERS=buildbox=fake STALLS_SSH="$T/ssh-ok" python3 "$B/stalls.py" --json)
  check "$(echo "$rj" | python3 -c "import json,sys; d=json.load(sys.stdin); print([s['class'] for s in d['stalls'] if s['topic']=='requeued-step'], [x['why'] for x in d['queued'] if x['topic']=='requeued-step'], any('requeued-step on testhost' in n and 'requeued from laptop' in n for n in d['notes']))")" \
    "[] ['requeued from laptop'] True" "S10(e): a requeued run its queue holds is no stall; the board's note reads requeued from <host> (its \`ending\` read, a headless exit over it)"
  printf '#!/bin/sh\necho %s\n' "'{\"entries\": [{\"repo\": \"$(basename "$D")\", \"branch\": \"claude/t/2026-10-14-requeued-step\", \"state\": \"running\", \"running_on\": \"testhost\"}], \"unreadable\": false, \"why\": []}'" > "$T/dq-rq-here"; chmod +x "$T/dq-rq-here"
  rj=$(STALLS_DISPATCH_QUEUE="$T/dq-rq-here" STALLS_PEERS=buildbox=fake STALLS_SSH="$T/ssh-ok" python3 "$B/stalls.py" --json)
  check "$(echo "$rj" | python3 -c "import json,sys; d=json.load(sys.stdin); print([x['topic'] for x in d['queued']].count('requeued-step'))")" "0" \
    "  …its entry still running on the host that handed it back (the op lost): not called queued"
  rj=$(STALLS_DISPATCH_QUEUE="$T/dq-empty" STALLS_PEERS=buildbox=fake STALLS_SSH="$T/ssh-ok" python3 "$B/stalls.py" --json)
  check "$(echo "$rj" | python3 -c "import json,sys; d=json.load(sys.stdin); print([x['topic'] for x in d['queued']].count('requeued-step'), any(x.get('topic')=='requeued-step' for x in d['stalls'] + d['unsure']))")" \
    "0 True" "  …the queue no longer holding it (its op lost): judged as any run, never hidden as queued"
  rm -f "$R/9r-requeued.json"
  printf '#!/bin/sh\necho "ssh: connect to host fake port 22: Operation timed out" >&2\nexit 255\n' > "$T/ssh-down"; chmod +x "$T/ssh-down"
  printf '#!/bin/sh\necho %s\n' "'{\"entries\": [{\"repo\": \"x\", \"branch\": \"claude/t/2026-10-14-far\", \"state\": \"running\", \"running_on\": \"buildbox\", \"seen_at\": $((now-1800))}], \"unreadable\": false, \"why\": []}'" > "$T/dq-stale"
  printf '#!/bin/sh\necho %s\n' "'{\"entries\": [{\"repo\": \"x\", \"branch\": \"claude/t/2026-10-14-far\", \"state\": \"running\", \"running_on\": \"buildbox\", \"seen_at\": $((now-60))}], \"unreadable\": false, \"why\": []}'" > "$T/dq-fresh"
  chmod +x "$T/dq-stale" "$T/dq-fresh"
  note() { STALLS_DISPATCH_QUEUE="$T/$1" STALLS_PEERS=buildbox=fake STALLS_SSH="$T/ssh-down" python3 "$B/stalls.py" --json \
           | python3 -c "import json,sys; print([n.split(' (')[0] for n in json.load(sys.stdin)['notes'] if n.startswith('buildbox:')])"; }
  check "$(note dq-stale)" "['buildbox: unreachable']" "  an unreachable peer with no word that it may sleep stays unreachable (a build host down is no sleep)"
  echo "buildbox:sleeps" > "$REGATTA_CONFIG/wharf-runs/power"
  check "$(note dq-stale)" "['buildbox: asleep']" "  …one with a sleeps line, its queue entries unseen past two sweeps: asleep"
  check "$(note dq-empty)" "['buildbox: asleep']" "  …or running none"
  check "$(note dq-fresh)" "['buildbox: unreachable']" "  …its sweep still writing: awake, its ssh down — unreachable"
  printf '#!/bin/sh\nexit 5\n' > "$T/dq-crash"; chmod +x "$T/dq-crash"
  check "$(note dq-crash)" "['buildbox: unreachable']" "  …a queue that gave no answer: could not tell, unreachable"
  rm -f "$REGATTA_CONFIG/wharf-runs/power"
  has "$yt" "S1 testhost demo gone-step" "  its own as before"
  yt=$(CLAUDE_REPOS_JSON="$T/yard-torn.json" STALLS_PEERS=buildbox=fake STALLS_SSH="$T/ssh-ok" STALLS_LOG="$T/yard-tick.jsonl" "$HM" tick --dry-run)
  has "$yt" "S8: the stalls of buildbox are left to nobody this pass — the registry does not read (1)" "a torn registry: no peer's stall acted on"
  has "$yt" "S1 testhost demo gone-step" "  this host's own still are"
  # …and a RELAYED run whose skipper is on a host this one has no road to is unknown, never orphaned
  git -C "$D" branch claude/t/2026-10-14-relay-far-step
  rec 11-relay-far.json relay-far-step started=$((now-7200)) ended=$((now-3600)) "end_reason=idle 60 min" manager=mgr-far manager_host=farhost
  say sid-relay-far-step "RELAYED TO mgr-far — D1 in docs/x.md"
  check "$(STALLS_PEERS=buildbox=fake STALLS_SSH="$T/ssh-ok" python3 "$B/stalls.py" --json | python3 -c "import json,sys; print([s['class'] for s in json.load(sys.stdin)['stalls'] if s['topic']=='relay-far-step'])")" \
    "[]" "S8: RELAYED to a skipper on a host with no road from here (a yard's to the laptop): no stall"
  check "$(STALLS_PEERS=buildbox=fake STALLS_SSH="$T/ssh-ok" python3 "$B/stalls.py" --json | python3 -c "import json,sys; print([s['class'] for s in json.load(sys.stdin)['stalls'] if s['topic']=='relay-step'])")" \
    "['S6']" "  one whose skipper has no host recorded is still orphaned"
  sed -i.bak 's/"manager_host": "farhost"/"manager_host": "buildbox"/' "$R/11-relay-far.json"; rm -f "$R/11-relay-far.json.bak"
  check "$(STALLS_PEERS=buildbox=fake STALLS_SSH="$T/ssh-ok" python3 "$B/stalls.py" --json | python3 -c "import json,sys; print([s['class'] for s in json.load(sys.stdin)['stalls'] if s['topic']=='relay-far-step'])")" \
    "['S6']" "  and one on a peer read here, its skipper not live there, is orphaned as before"
  rm -f "$R/11-relay-far.json" "$HOME/.claude/projects/-t/sid-relay-far-step.jsonl"   # the branch alone judges nothing
  # yolo-launch review D1-B: a run that ended on the hand-over line and whose launch dispatch declined is
  # raised with dispatch's reason, never retried (it read as S1's "nothing woke it"); one whose launch started is no card
  git -C "$D" branch claude/t/2026-10-14-handed-step
  rec 14-handed.json handed-step started=$((now-7200)) ended=$((now-3600)) "end_reason=idle 10 min" \
    "launch=no launch — autofinish is disarmed on this Mac (bin/autofinish arm)"
  say sid-handed-step "Built.
SAM, THIS SESSION IS WAITING FOR SOMETHING — dispatch's launch (autofinish-run)"
  hj=$(STALLS_PEERS=buildbox=fake STALLS_SSH="$T/ssh-ok" python3 "$B/stalls.py" --json)
  check "$(echo "$hj" | python3 -c "import json,sys; s=[x for x in json.load(sys.stdin)['stalls'] if x['topic']=='handed-step']; print([(x['class'], x['action'], x['raise_to'], x['title']) for x in s], [e for x in s for e in x['evidence'] if e.startswith('dispatch: ')])")" \
    "[('S6', 'raise', 'owner', 'handed-step · S6 handed over, its launch never started')] ['dispatch: no launch — autofinish is disarmed on this Mac (bin/autofinish arm)']" \
    "D1-B: the hand-over with its launch declined: raised to the owner with dispatch's reason, never S1's retry"
  rec 14-handed.json handed-step started=$((now-7200)) ended=$((now-3600)) "end_reason=idle 10 min" "launch=started: autofinish-run --rule M --by yolo"
  check "$(STALLS_PEERS=buildbox=fake STALLS_SSH="$T/ssh-ok" python3 "$B/stalls.py" --json | python3 -c "import json,sys; print([s['class'] for s in json.load(sys.stdin)['stalls'] if s['topic']=='handed-step'])")" \
    "[]" "  its launch started: no card here (a launch that stops is S4 or S5)"
  rm -f "$R/14-handed.json" "$HOME/.claude/projects/-t/sid-handed-step.jsonl"
  printf '{"pid": %s, "sessionId": "mgr-1", "status": "busy", "statusUpdatedAt": %s000}' "$$" "$now" > "$T/sess/mgr.json"
  check "$(python3 "$B/stalls.py" --json | python3 -c "import json,sys; s=[x for x in json.load(sys.stdin)['stalls'] if x['class']=='S7'][0]; print(s['raise_to'], s['column'])")" \
    "skipper Blocked" "  S7 goes to its skipper (raise_to, rename S5) while that session is live"
  rm "$T/sess/mgr.json"
  # the fixture's autofinish stops are dated 2026-10-14: past the board's 7 days, they are a count (board-cleanup S1)
  ov=$(STALLS_PEERS=buildbox=fake STALLS_SSH="$T/ssh-ok" "$HM" $BOARD --json)
  check "$(echo "$ov" | python3 -c "import json,sys; d=json.load(sys.stdin); h=d['header']; print(h['stalled'], sum(c['kind']=='stall' for col in d['columns'] for c in col['cards']), h['stalls_old'], h['stalls_oldest'] < __import__('time').time() - 7 * 86400)")" "9 9 4 True" \
    "overview: the four stops past 7 days are a header count with the oldest's start, the rest a card each"
  ov=$(HELM_STALL_DAYS=36500 STALLS_PEERS=buildbox=fake STALLS_SSH="$T/ssh-ok" "$HM" $BOARD --json)
  check "$(echo "$ov" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['header']['stalled'], sum(c['kind']=='stall' for col in d['columns'] for c in col['cards']))")" "13 13" \
    "overview: one card per stall, the count in its header (HELM_STALL_DAYS past the fixture's dates)"
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
  cat > "$T/net_re.py" <<'PY'
import re, sys
src = next(l for l in open(sys.argv[1]) if l.startswith("NET_RE = re.compile"))
NET_RE = eval(src.split("=", 1)[1], {"re": re})
print([bool(NET_RE.match(t)) for t in sys.argv[2:]])
PY
  check "$(python3 "$T/net_re.py" "$B/stalls.py" "You've hit your 5-hour limit · resets 9:20pm (America/Los_Angeles)" \
    "You’ve hit your weekly limit · resets Fri" "⏳ SAM, THIS SESSION IS WAITING FOR SOMETHING — You've hit your 5-hour limit" "You've hit your Opus limit · resets Fri" "You've hit your limit · resets Fri")" \
    "[True, True, False, False, False]" "  NET_RE: a login's usage limit is S4 (queue-followthrough); quoted in a WAITING line it is not (R4), nor a per-model one or the bare extra-usage form no pick judges"
  cat > "$T/no_account.py" <<'PY'
import sys
from importlib.machinery import SourceFileLoader
sys.path.insert(0, sys.argv[2])
m = SourceFileLoader("stalls_tick", sys.argv[1]).load_module()
m.run_tool = lambda argv, env, timeout: (3, "", "autofinish-run: not starting b — no account may run this now — acct-a: 5h 99%")
m.relaunch_cmd = lambda s: (["/x/autofinish-run", "/w", "--by", "chain"], {})
line = m.act({"key": ["h", "b", "t"]}, {"what": "relaunch", "attempt": 1}, 1000)
key = ["h", "b", "t"]
lines = [dict(line, key=key, t=1000 + i, retry_t=1000 + i) for i in range(7)]
lines.append({"action": "refused", "tool": "autofinish-run", "key": key, "t": 2000, "retry_t": 2000, "why": "other"})
peer = "autofinish-run: refused on buildbox: no account may run this now — acct-a: 5h 99%"
m.run_tool = lambda argv, env, timeout: (5, "stays on this Mac — no account may run this now", peer)
pl = m.act({"key": key}, {"what": "relaunch", "attempt": 1}, 1000)
m.run_tool = lambda argv, env, timeout: (3, "earlier: no account may run this now", "autofinish-run: not starting b — its dispatch run could not be ended first")
ol = m.act({"key": key}, {"what": "relaunch", "attempt": 1}, 1000)
print(line["action"], line.get("no_account"), len(m.Memory(lines).refusals(key)), pl.get("no_account"), ol.get("no_account"))
PY
  check "$(python3 "$T/no_account.py" "$B/stalls_tick.py" "$B" 2>&1 | tail -1)" "refused True 1 None None" \
    "  the tick: a relaunch this Mac's pick refused is marked, neither counted toward REFUSALS nor dating the backoff; a peer's relayed no-account, or another refusal that only quotes the words, counts"
  check "$(grep -qF 'print("autofinish-run: not starting %s — %s" % (t.branch, why), file=sys.stderr)' "$(src autofinish-run)" && grep -qF 'why = "no account may run this now — %s" % e' "$(src autofinish-run)" && echo both)" "both" \
    "  and NO_ACCOUNT_RE reads autofinish-run's own words: refuse()'s line and start_here's no-account reason"

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
  # a skippered S1 (its skipper's road on the record), a gone step whose worktree another session's
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
  out=$(scen slow STUB_SLEEP=2 STALLS_TOOL_TIMEOUT=1)   # the stub outlives the 1 s timeout by a second: enough to time out
  has "$out" "timed out after 1 s — counted as spent" "a tool call that times out is a spent retry, not a refusal (it may have started the run)"
  check "$(python3 -c "import json; L=[json.loads(l) for l in open('$X/slow.jsonl')]; g=[l for l in L if l['topic'] == 'gone-step' and l['t'] == $ta]; print([(l['action'], l['why'][:6]) for l in g])")" \
    "[('retry', 'firing'), ('retry', 'dispat')]" "  its retry was on record before the tool ran: a firing line, then the outcome"
  out=$(scen full DISPATCH_MAX_RUNS=0)
  has "$out" "S1 testhost demo gone-step: waits — the run cap is full here (" "the run cap full: a step waits"
  check "$(call "print(sorted(x['tool'] for x in c))" "$X/full.calls")" "['autofinish-run']" "  a relaunch is no run of dispatch's cap: it goes on"
  : > "$HOME/.studio-brake"; out=$(scen brake); rm -f "$HOME/.studio-brake"
  has "$out" "S1 testhost demo gone-step: waits — held — the studio brake holds ($HOME/.studio-brake exists)" \
    "the studio brake holds the tick's own retries too (S11): dispatch and the harness do not read it"
  check "$(ncalls "$X/brake.calls")" "0" "  nothing started, nothing relaunched"

  out=$(tk "$ta")
  has "$out" "helm tick: armed — armed by test-sam" "3 h after arming: armed"
  check "$(call "print(sorted((x['tool'], nm(x)) for x in c))")" \
    "[('autofinish-run', 'wt:net'), ('dispatch', 'cap-step'), ('dispatch', 'gone-step'), ('dispatch', 'unsure-two')]" \
    "the acting tick: S1, S2 and the classified run re-dispatched, S4 relaunched — the locked step not"
  check "$(call "x=[x for x in c if nm(x) == 'gone-step'][0]; e=x['env']; print(e['DISPATCH_DEPTH'], e['DISPATCH_MANAGER'], e['DISPATCH_MANAGER_HOST'], e['DISPATCH_MANAGER_ACCOUNT'], e['DISPATCH_PLAN'], e['DISPATCH_PLAN_SPACE'], 'CLAUDE_CODE_SESSION_ID' in e)")" \
    "0 mgr-b3 testhost /x/acct b3p b3-space False" "  S1: the same step again (depth 1 → DISPATCH_DEPTH 0), its skipper's five values, never the caller's session"
  check "$(call "x=[x for x in c if nm(x) == 'gone-step'][0]; e=x['env']; print(e['DISPATCH_SKIPPER'], e['DISPATCH_SKIPPER_HOST'], e['DISPATCH_SKIPPER_ACCOUNT'], e['DISPATCH_SHIP'])")" \
    "mgr-b3 testhost /x/acct b3p" "    and under the new names too (rename S5: both written until S8)"
  check "$(call "x=[x for x in c if nm(x) == 'gone-step'][0]['argv']; print(x[1:3] == ['--repo', '$D'], x[-2:], x[x.index('--note') + 1].split(' — ')[0])")" \
    "True ['--on', 'here'] stalls: re-dispatched (retry 1 of 2) after S1" "  where it ran (--on here), with a note"
  check "$(call "x=[x for x in c if nm(x) == 'cap-step'][0]; print(x['env']['DISPATCH_DEPTH'], 'DISPATCH_MANAGER' in x['env'], x['argv'][x['argv'].index('--note') + 1][:34])")" \
    "2 False stalls: started (retry 1 of 2) aft" "  S2: the next step, so its depth as recorded (dispatch adds one); no skipper it never had"
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
    "a skippered run's plan hears it: blocked, never failed"
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
  check "$(python3 - "$B" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import stalls_tick as k
arm = {"name": "sonnet-high", "model": "claude-sonnet-5-5", "effort": "high", "coin": 1, "until": "2026-11-30", "forced": False}
s = {"host": "buildbox", "branch": "claude/x", "repo": "demo", "depth": 3, "class": "S1", "run": "x.json",
     "dispatch": {"repo": "/elsewhere", "model": "claude-sonnet-5-5", "effort": "high", "arm": arm}}
argv, env = k.dispatch_cmd(s, "redispatch", 1, 1000)
print("--model" in argv, "--effort" in argv, env.get("DISPATCH_ARM"))
s["dispatch"]["model"] = "claude-opus-5-5"   # a pair other than the arm pair: typed, as before
argv, env = k.dispatch_cmd(s, "redispatch", 1, 1000)
print(argv[argv.index("--model") + 1], env.get("DISPATCH_ARM"))
PY
)" "False False sonnet-high:1:2026-11-30:0
claude-opus-5-5 None" "a stalled builder-rotation run retries on its drawn arm (DISPATCH_ARM), not a typed pair that records it pinned"
  check "$(DISPATCH_ARM=sonnet-high:1:2026-11-30:1 DISPATCH_COIN=1 python3 - "$B" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import stalls_tick as k
s = {"host": "buildbox", "branch": "claude/x", "repo": "demo", "depth": 3, "class": "S1", "run": "x.json",
     "dispatch": {"repo": "/elsewhere", "model": "claude-opus-5-5", "effort": "high"}}
for what in ("redispatch", "start"):
    argv, env = k.dispatch_cmd(s, what, 1, 1000)
    print(env.get("DISPATCH_ARM"), env.get("DISPATCH_COIN"))
PY
)" "None None
None None" "the tick's own DISPATCH_ARM and DISPATCH_COIN never reach a re-dispatch or an S2 start (STRIP_ENV)"
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
  # S6's fourth landing review: a FAILED "refused for good" (dispatch's spawn gate) spends the retry, so the cap
  # stops it; any other FAILED at fire time voids it, as before
  cat > "$T/forgood.py" <<'PY'
import os, sys, tempfile
sys.path.insert(0, sys.argv[1])
import stalls_tick as k
out = []
for text in ("FAILED: refused for good, a run out of a confidential scope with no review that vouches for its brief — x; not running (confidential-reach S6)\n",
             "FAILED: screen did not start\n"):
    fd, log = tempfile.mkstemp(); os.write(fd, text.encode()); os.close(fd)
    r = {"action": "retry", "what": "redispatch", "t": 1000, "repo": "demo", "topic": "s", "key_kind": "step",
         "key": ["h", "demo", "s", "b"], "log": log, "log_offset": 0}
    line = k.follow_up(k.Memory([r]), {"runs": []}, 2000, False, "dry")[0]
    m = k.Memory([r, line])
    out.append("%s %d %d" % (line["action"], len(m.retries(r["key"])), len(m.pending())))
    os.unlink(log)
print(" | ".join(out))
PY
  check "$(python3 "$T/forgood.py" "$B")" "spent 1 0 | refused 0 0" \
    "a fire-time FAILED 'refused for good' spends its retry (counted, followed); any other voids it, as before"
  unset STALLS_LOG STALLS_STATE_DIR STALLS_DISPATCH STALLS_AUTOFINISH_RUN AUTOFINISH_ACCOUNT AUTOFINISH_STATE_DIR GATE_PLAN_STALL_PROVIDER CLAUDE_BIN GATE_LOG DISPATCH_MAX_RUNS
  rm_own "$R" "$T/sess/work.json" "$T/sess/wait.json"

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
  # the plan's skipper, live in the registry: a question naming a D-item is relayed to it
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
  check "$(og "s=[x for x in o if x['class']=='S7'][0]; print(s['key'], s['orca_task'], s['raise_to'])")" "['testhost', 'b8p', 'pb'] p_b skipper" "  S7 from task-list --ready, quiet two hours since its dependency completed; to the live skipper"
  check "$(echo "$oj" | python3 -c "import json,sys; print([s['topic'] for s in json.load(sys.stdin)['stalls'] if s.get('plan') == 'b8p' and not s.get('harness')])")" "[]" \
    "  an Orca-backed plan's own planned tasks are not judged twice (judge_plans leaves them to task-list)"
  hasnt "$(cat "$X8/orca.calls")" "worker-start" "  the judge starts nothing"
  ovo=$(HELM_STALL_DAYS=36500 "$HM" $BOARD --json)
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
    "1 True ['D1', '--task', 'p-ask'] b8p mgr-1 ctx_ask" "  bin/ask relay <doc> <Dn> --task <step>, with the plan's skipper road and the worker as the asker"
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
u0=$(lf ls1 until)   # no wait: until is a float now() + TTL, and the renew below starts a process later
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
# a pass renews ls1 and takes ls4: polled for, where a fixed 3 s once waited out two periods
until_ "[ \"\$(lf ls4 holder)\" = 'skipper · dock' ] && python3 -c 'import sys; sys.exit(not float(sys.argv[2]) > float(sys.argv[1]))' $a1 \"\$(lf ls1 until)\""
check "$(python3 -c "import sys; print(float(sys.argv[2]) > float(sys.argv[1]))" "$a1" "$(lf ls1 until)")" "True" "--hold (HELM_HOLD_EVERY=1): ls1 renewed in the loop"
check "$(lf ls4 holder)/$(lf ls4 session)" "skipper · dock/mgr-1" "  ls4, laid to the yard meanwhile, taken"
# one more pass before the left-alone checks: the fixed 3 s covered several, and a later pass that
# takes what the first left would pass after the first alone (landing review)
a1b=$(lf ls1 until)
until_ "python3 -c 'import sys; sys.exit(not float(sys.argv[2]) > float(sys.argv[1]))' $a1b \"\$(lf ls1 until)\""
check "$(lf ls2 session)/$(lf ls2 gen)" "mgr-2/3" "  another skipper's ship left alone"
check "$(lf ls3 holder)" "yard" "  another scope's ship left alone"
kill $PARENT; wait $PARENT 2>/dev/null
for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do kill -0 $HOLD 2>/dev/null || break; sleep 0.25; done
if kill -0 $HOLD 2>/dev/null; then kill $HOLD; check "alive" "ended" "the sidecar ends within a period of its parent's death"
else wait $HOLD; check "$?" "0" "the sidecar ends within a period of its parent's death, exit 0"; fi
has "$(cat "$T/hold.out")" "has ended — the sidecar ends with it" "  saying so"
# a renewal refused in the loop (the yard took the ship back) ends the sidecar, exit 4: it never takes it back
# the stand-in parent is named claude: stand-down signals only a live claude. Its form is per OS, so
# that `ps -o comm=` names it claude on each (twin-ci-3, 2026-10-25). macOS's comm is argv[0], and a
# script's argv[0] is its interpreter (/bin/sh, probed), so there it is a link to /bin/sleep, as before.
# Linux's comm is the basename of the path exec'd, a #!/bin/sh script's included; and ubuntu's uutils
# coreutils is one multicall binary, and a link or copy of sleep named claude was dead at once
# (twin-ci-2's `exec -a sleep` over the link too; the cause is inferred, no runner log was read). There it is a
# script that calls sleep by its own name, and ends by itself after $1 seconds as sleep would.
mkdir -p "$T/fakeclaude"
if [ "$(uname)" = Darwin ]; then ln -sf /bin/sleep "$T/fakeclaude/claude"
else printf '#!/bin/sh\ni=0\nwhile [ "$i" -lt "${1:-300}" ]; do sleep 1; i=$((i+1)); done\n' > "$T/fakeclaude/claude"; chmod +x "$T/fakeclaude/claude"; fi
"$T/fakeclaude/claude" 300 & PARENT=$!; disown $PARENT   # stand-down ends it below: no job notice from this shell
# polled, not a fixed sleep: until the child execs, ps names bash (code-review, twin-ci-2's finish)
for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do PCOMM=$(/bin/ps -o comm= -p $PARENT 2>/dev/null); [ "${PCOMM##*/}" = claude ] && break; sleep 0.25; done
check "${PCOMM:+${PCOMM##*/}}" "claude" "the stand-in claude lives, and ps names it claude"
a2=$(lf ls1 until)
HELM_HOLD_EVERY=1 HELM_HOLD_PARENT=$PARENT "$LX/helm" skipper --hold --scope dock > "$T/hold.out" 2>&1 & HOLD=$!
# the yard takes ls1 back once the first pass has renewed it (a fixed 1.5 s before): the next pass is refused
until_ "python3 -c 'import sys; sys.exit(not float(sys.argv[2]) > float(sys.argv[1]))' $a2 \"\$(lf ls1 until)\""
ll yard ls1 dock > /dev/null; ll yard ls5 dock > /dev/null
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
# through claude-host the record's pid is the launcher's (a parent that waits), claude its child: the
# session's registry record names the child, which stand-down signals (the launcher's review, 2026-10-24)
printf '#!/bin/bash\n"%s" 300 & c=$!\ntrap '"'"'kill -TERM $c 2>/dev/null'"'"' TERM INT HUP\nwait $c\n' "$T/fakeclaude/claude" > "$T/fakehost"
chmod +x "$T/fakehost"; "$T/fakehost" & HOSTP=$!; disown $HOSTP
for _ in 1 2 3 4 5 6 7 8; do KID=$(pgrep -P $HOSTP); [ -n "$KID" ] && break; sleep 0.25; done
check "$([ -n "$KID" ] && echo found || echo none)" "found" "  the launcher's claude child lives (no child: every case below is vacuous)"
printf '{"session": "mgr-3", "pid": %d, "scope": "dock"}' "$HOSTP" > "$T/mgrdir/testhost-dock.json"
printf '{"pid": %d, "sessionId": "mgr-3", "name": "skipper-x", "status": "idle", "updatedAt": 2}' "$KID" > "$T/sess/mgr-3.json"
out=$(CLAUDE_CODE_SESSION_ID=mgr-3 SKIPPER_SCOPE=dock "$LX/helm" skipper --stand-down 2>&1)
for _ in 1 2 3 4 5 6 7 8; do kill -0 $KID 2>/dev/null || break; sleep 0.25; done
check "$(kill -0 $KID 2>/dev/null && echo alive || echo ended)" "ended" "  through claude-host: the session's claude (its registry pid, the launcher's child) ended"
has "$out" "ended pid $KID" "  signalled by its own pid"
kill $HOSTP $KID 2>/dev/null; rm -f "$T/sess/mgr-3.json"
check "$(env -u CLAUDE_CODE_SESSION_ID "$LX/helm" skipper --stand-down 2>&1; echo "rc=$?")" \
  "helm skipper --stand-down: a skipper session's own verb — no CLAUDE_CODE_SESSION_ID here
rc=1" "  a plain shell has no skipper to stand down"
unset ASK_MANAGER_DIR

echo "the scope skipper (skipper-resilience S5): --start, the runner, the tick's pass, the hand-overs"
# Stubs only: launchctl, screen, claude, account, dispatch-rc, trust-projects and the spacesheep CLI
# record what they were asked; nothing loads a real job, starts a real claude or screen, or leaves
# the Mac. A fresh store, registry and skipper dir, so S4's leases above are not this block's.
S5="$T/s5"; mkdir -p "$S5/bin" "$S5/la" "$S5/mgr" "$S5/st" "$S5/q" "$S5/cfg/acct-a" "$S5/cfg/acct-b" "$S5/cfg/acct-c"
export PLANS_DIR="$S5/plans" ASK_MANAGER_DIR="$S5/mgr" STALLS_STATE_DIR="$S5/st" STALLS_LOG="$S5/stalls.jsonl" \
       ASK_QUEUE_DIR="$S5/q" ASK_NO_KEY_FILES=1 HELM_LAUNCH_DIR="$S5/la" HELM_LAUNCHCTL="$S5/bin/launchctl" \
       HELM_SCREEN="$S5/bin/screen" HELM_CLAUDE="$S5/bin/claude" HELM_ACCOUNT="$S5/bin/account" \
       HELM_DISPATCH_RC="$S5/bin/dispatch-rc" HELM_TRUST="$S5/bin/trust-projects" MEMO_SHEEP_BIN="$S5/bin/spacesheep" \
       CLAUDE_REPOS_JSON="$S5/repos.json" PLAN_PROJECTS_ROOT="$S5/projects" HELM_SCREENDIR="$S5/screens" \
       HELM_RC_HOSTS="$S5/bin/rc-hosts"
# rc-hosts: `--launcher claude` names no claude-host (exit 1, a Mac with no grant) unless rch.on is
# there; then the stand-in claude-host, which forks the stand-in claude, forwards signals and waits,
# as claude-host does (a stand-in that exec'd would hide a record pid that is not claude's)
cat > "$S5/bin/rc-hosts" <<EOF
#!/usr/bin/env python3
import os, sys
open("$S5/rch.calls", "a").write(" ".join(sys.argv[1:]) + "\n")
if sys.argv[1:] != ["--launcher", "claude"] or not os.path.exists("$S5/rch.on"):
    sys.exit(1)
if os.path.exists("$S5/rch.empty"):   # exit 0 and nothing printed: launcherlib reads it as bare
    sys.exit(0)
if os.path.exists("$S5/rch.banner"):   # a line before the path: the last line is the answer
    print("rc-hosts: a note")
print("$S5/bin/claude-host")
EOF
cat > "$S5/bin/claude-host" <<EOF
#!/bin/bash
{ printf '%s\n' "\$@"; } >> "$S5/host.argv"
shift
"$S5/bin/claude" "\$@" & c=\$!
trap 'kill -TERM \$c 2>/dev/null' TERM INT HUP
wait \$c
EOF
chmod +x "$S5/bin/rc-hosts" "$S5/bin/claude-host"
mkdir -p "$S5/projects/dockrepo" "$S5/projects/sib" "$S5/projects/third" "$S5/projects/fourth"
cat > "$CLAUDE_REPOS_JSON" <<'EOF'
{"repos": {"dockrepo": {}, "sib": {}, "third": {}, "fourth": {}},
 "scopes": {"dock": {"repos": ["dockrepo", "sib"], "yard": "testhost"}, "solo": {"repos": ["third"], "yard": "testhost"},
            "four": {"repos": ["fourth"], "yard": "testhost", "confidential": true}}}
EOF
# the screens `screen -ls` lists: dock's, a scope whose name extends dock's, solo's (a quit must name the pid)
printf 'There are screens on:\n\t111.skipper-dock\t(Detached)\n\t222.skipper-dockyard\t(Detached)\n\t333.skipper-solo\t(Detached)\n3 Sockets in /x.\n' > "$S5/screen.ls"
cat > "$S5/bin/launchctl" <<EOF
#!/bin/sh
echo "\$*" >> "$S5/lc.calls"
[ "\$1" = list ] && cat "$S5/lc.list" 2>/dev/null
exit 0
EOF
cat > "$S5/bin/screen" <<EOF
#!/bin/sh
echo "\$* SCREENDIR=\$SCREENDIR" >> "$S5/screen.calls"
echo "screen \$*" >> "$S5/lc.calls"
[ "\$1" = -ls ] && { cat "$S5/screen.ls"; exit 1; }   # screen -ls exits non-zero even when it lists
exit 0
EOF
# claude: `auth status` answers from the config dir (a .out file there: not signed in); a session
# writes its argv, its cwd and the environment the runner gave it, then exits
cat > "$S5/bin/claude" <<EOF
#!/bin/bash
if [ "\$1 \$2" = "auth status" ]; then
  echo "auth \${CLAUDE_CONFIG_DIR:-default}" >> "$S5/claude.calls"
  if [ -e "\${CLAUDE_CONFIG_DIR:-/nonexistent}/.out" ]; then echo '{"loggedIn": false, "authMethod": "none"}'; exit 1; fi
  echo '{"loggedIn": true, "authMethod": "claude.ai"}'; exit 0
fi
echo "session" >> "$S5/claude.calls"
{ printf '%s\n' "\$@"; } > "$S5/claude.argv"
{ echo "cwd=\$PWD"; env | grep -E '^(SKIPPER_|HELM_HOLD_PARENT|CLAUDE_|DISPATCH_|RUN_SEED_)' | sort; echo "pid=\$\$"; } > "$S5/claude.env"
EOF
# account: picks and deny lists from a fixture (repo key → label; label → the keys it denies)
cat > "$S5/bin/account" <<EOF
#!/usr/bin/env python3
import json, os, sys
fx = json.load(open("$S5/acct.json"))
key = lambda p: os.path.relpath(os.path.realpath(p), os.path.realpath("$S5/projects"))
if sys.argv[1] == "pick":
    k = key(sys.argv[3]); open("$S5/acct.calls", "a").write("pick %s\n" % k)
    lab = fx["picks"].get(k)
    if not lab:
        print(json.dumps({"account": None, "skipped": [["acct-a", "its week is full"]]})); sys.exit(3)
    print(json.dumps({"account": lab, "env": {"CLAUDE_CONFIG_DIR": "$S5/cfg/" + lab}})); sys.exit(0)
if sys.argv[1] == "limits":
    rows = [{"label": l, "provider": "claude", "eligible": l not in fx.get("ineligible", []), "env": {"CLAUDE_CONFIG_DIR": "$S5/cfg/" + l}}
            for l in ("acct-a", "acct-b", "acct-c")]
    print(json.dumps(rows)); sys.exit(0)
if sys.argv[1] == "allowed":
    if os.path.exists("$S5/acct.crash"):
        raise RuntimeError("the registry is half-written")   # a traceback, exit 1: no answer at all
    lab = os.path.basename(os.environ.get("CLAUDE_CONFIG_DIR", "default")); k = key(sys.argv[2])
    if k in fx["deny"].get(lab, []):
        print("%s is off %s (accounts.json deny list)" % (k, lab)); sys.exit(1)
    sys.exit(0)
sys.exit(2)
EOF
cat > "$S5/bin/dispatch-rc" <<EOF
#!/usr/bin/env python3
import os, sys
assert sys.argv[1] == "trusted"
if os.path.exists("$S5/rc.crash"):
    raise RuntimeError("dispatch-rc half-written")
open("$S5/trust.calls", "a").write("trusted %s %s\n" % (os.path.basename(sys.argv[2]), os.path.basename(sys.argv[4])))
sys.exit(0 if os.path.exists(os.path.join(sys.argv[4] or "$S5/cfg/default", ".trusted")) else 1)
EOF
cat > "$S5/bin/trust-projects" <<EOF
#!/usr/bin/env python3
import os
d = os.environ.get("CLAUDE_CONFIG_DIR") or "$S5/cfg/default"
open("$S5/trust.calls", "a").write("trust-projects %s\n" % os.path.basename(d))
if not os.path.exists(os.path.join(d, ".untrustable")):
    open(os.path.join(d, ".trusted"), "w").close()
EOF
cat > "$S5/bin/spacesheep" <<EOF
#!/bin/sh
echo "\$* CLAUDE_CODE_SESSION_ID=\$CLAUDE_CODE_SESSION_ID" >> "$S5/sheep.calls"
[ -e "$S5/sheep.fail" ] && { echo '{"error": "the service is away"}'; exit 1; }
echo '{"uuid": "sp-dock", "url": "https://example.invalid/s/sp-dock"}'
EOF
chmod +x "$S5/bin/"*
echo '{"picks": {"dockrepo": "acct-a", "sib": "acct-b", "third": "acct-c"}, "deny": {}}' > "$S5/acct.json"
SK() { env -u CLAUDE_CODE_SESSION_ID python3 - "$B" "$@" <<'PY'
import json, sys
sys.path.insert(0, sys.argv[1])
import skipperlib
fn, args = sys.argv[2], sys.argv[3:]
if fn == "ensure":
    print("\n".join(skipperlib.ensure(args[0] == "act", "the suite")))
elif fn == "fails":
    print(len(skipperlib.consecutive_failures(skipperlib.starts(args[0]))))
elif fn == "needs":
    print(skipperlib.needs(args[0]))
elif fn == "open":
    print(len(skipperlib.open_asks(args[0])))
elif fn == "open_refs":
    print(sorted(a["ref"] for _, a in skipperlib.open_asks(args[0])))
elif fn == "launch":   # a launched line as start() writes it (STALLS_NOW backdates it)
    skipperlib.log_start(args[0], "launched", args[1], job=skipperlib.job_label(args[0], args[1]), by="tick")
elif fn == "log":      # any starts-log line: scope event start [session]
    skipperlib.log_start(args[0], args[1], args[2], **({"session": args[3]} if len(args) > 3 else {}))
elif fn == "deaf":     # deaf() on the ship's lease, now
    import leaselib, time
    print(skipperlib.deaf(args[0], leaselib.read(args[0]), time.time()))
elif fn == "fails_of":  # consecutive_failures over the lines given as JSON
    print(len(skipperlib.consecutive_failures(json.loads(args[0]))))
elif fn == "alive":    # record_alive on a record given as JSON
    print(skipperlib.record_alive(json.loads(args[0])))
elif fn == "stop":     # the tick's stop (by="tick")
    print("\n".join(skipperlib.stop(args[0], "the suite", by="tick")))
PY
}
# an ask's relay event as bin/ask relay writes it since S5: who it went to, by which road, the doc where it is
askev() { python3 - "$B" "$@" <<'PY'
import os, sys, time
sys.path.insert(0, sys.argv[1]); import helmlib
pid, task, ref, to, backend, ago = sys.argv[2:8]
to_host = sys.argv[8] if len(sys.argv) > 8 else None
helmlib.append_event(pid, {"task": task, "status": "relayed" if to else "waiting", "ask": ref, "summary": "which one",
                           "reversible": "yes", "recommended": "A", "backend": backend, "session": "run-9", "repo": "/x/dockrepo",
                           "doc": os.environ.get("ASKEV_DOC") or "/x/dockrepo/.claude/worktrees/q/" + ref.split("#")[0],
                           "to": to or None, "to_host": to_host, "reply_flags": " --to-account /acct/run --space sp-run",
                           "mode": os.environ.get("ASKEV_MODE") or None, "t": time.time() - float(ago), "plan": pid})
PY
}
rec() { python3 -c 'import json, sys; r = json.load(open(sys.argv[1])); print(r.get(sys.argv[2]))' "$S5/mgr/testhost-$1.json" "$2"; }
st5() { grep -c "\"event\": \"$2\"" "$S5/mgr/testhost-$1.starts.jsonl" 2>/dev/null | tr -d ' '; }
LP="$PLANS_DIR"
# a ship of a scope the yard holds, with one open block (needs a skipper unless the block is a person's)
lay() { "$HM" $SHIP "$1" --id "$1" > /dev/null; "$HM" task "$1" "${3:-b1}" ${4:+--kind human $BY sam} > /dev/null; ll yard "$1" "$2" > /dev/null; }
# a registry record for a session, its pid live (a sleep) unless given
regi() { printf '{"pid": %d, "sessionId": "%s", "name": "skipper-x", "status": "%s", "updatedAt": 2}' "$2" "$1" "${3:-busy}" > "$T/sess/$1.json"; }
# a skipper record as the runner writes it, by hand
mkrec() { printf '{"session": "%s", "name": "skipper · %s", "scope": "%s", "account": "acct-a", "host": "testhost", "started": %s, "pid": %d, "space": null, "gen": null, "start": "%s"}' \
            "$2" "$1" "$1" "$4" "$3" "${5:-20260101-000000-abcd}" > "$S5/mgr/testhost-$1.json"; }
now() { python3 -c 'import time; print(int(time.time()))'; }
# a stand-in claude pid (a sleep, disowned: a stop ends some of them, and no job notice follows); all ended at the block's end
SLEEPS=""
nap() { sleep 300 & NAP=$!; disown $NAP; SLEEPS="$SLEEPS $NAP"; }

echo "  no lease, no record: the tick is what it was before S5"
check "$(SK ensure act)" "" "  skipperlib.ensure on an empty store: no line, nothing started"
check "$("$LX/helm" tick --dry-run 2>&1 | grep -c 'skipper')" "0" "  helm tick --dry-run: no skipper line"
check "$([ -e "$S5/lc.calls" ] && echo called || echo none)" "none" "  launchctl never called"
check "$(STALLS_DEADLINE=$(( $(now) + 10 )) python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import stalls_tick; print(stalls_tick.ensure_skippers("armed"))' "$B")" "[]" \
  "  the tick's pass near its kill time on an empty host: not even the deadline's line"

echo "  --start and --stop"
out=$("$LX/helm" skipper --start dock 2>&1); check "$?" "1" "--start inside a session (CLAUDE_CODE_SESSION_ID): refused, exit 1"
has "$out" "refused inside a session" "  saying so"
out=$("$LX/helm" skipper --stop dock 2>&1); check "$?" "1" "--stop inside a session: refused, exit 1"
check "$([ -e "$S5/lc.calls" ] && echo called || echo none)" "none" "  nothing booted out or loaded"
# an unattended caller (a dispatched run, the skipper itself) and a session that dropped its variables: refused too
out=$(env -u CLAUDE_CODE_SESSION_ID CLAUDE_UNATTENDED=skipper "$LX/helm" skipper --start dock 2>&1); check "$?" "1" "--start under CLAUDE_UNATTENDED: refused"
has "$out" "refused in an unattended caller (CLAUDE_UNATTENDED=skipper)" "  saying so"
out=$(env -u CLAUDE_CODE_SESSION_ID CLAUDE_UNATTENDED=dispatch "$LX/helm" skipper --stop dock 2>&1); check "$?" "1" "--stop under CLAUDE_UNATTENDED: refused"
printf '{"pid": %d, "sessionId": "typing-1", "status": "busy"}' $$ > "$T/sess/$$.json"
out=$(env -u CLAUDE_CODE_SESSION_ID "$LX/helm" skipper --start dock 2>&1); check "$?" "1" "--start below a live session whose variables were dropped (env -u): refused"
has "$out" "refused below a live session (pid $$ in the registry)" "  by the process tree, not the environment"
rm -f "$T/sess/$$.json"
check "$([ -e "$S5/lc.calls" ] && echo called || echo none)" "none" "  and nothing loaded by any of them"
out=$(env -u CLAUDE_CODE_SESSION_ID "$LX/helm" skipper --start nosuch 2>&1); check "$?" "1" "--start of a scope the registry lacks: refused"
has "$out" "no scope nosuch in the registry" "  naming it"
out=$(env -u CLAUDE_CODE_SESSION_ID "$LX/helm" skipper --start dock --dry-run); check "$?" "0" "--start --dry-run: exit 0"
has "$out" "<string>-D</string>" "  prints the plist (screen -D -m)"
check "$(ls "$S5/la" | wc -l | tr -d ' ')/$(grep -c -e bootstrap -e bootout -e quit "$S5/lc.calls" 2>/dev/null || :)" "0/0" "  and writes, loads and boots out nothing (launchctl list alone)"
check "$([ -d "$S5/screens" ] && echo made || echo untouched)" "untouched" "  nor makes dispatch's screen dir"
mkdir -p "$S5/screens"; chmod 700 "$S5/screens"
# an older start of the scope: a plist and a label launchd still lists; another scope's left alone
OLD=dev.regatta.helm.skipper-dock-20260101-000000-abcd
touch "$S5/la/$OLD.plist" "$S5/la/dev.regatta.helm.skipper-dockyard-20260101-000000-abcd.plist"
printf -- '-\t0\t%s\n-\t0\tdev.regatta.helm.skipper-dock-20260102-000000-beef\n' "$OLD" > "$S5/lc.list"
out=$(env -u CLAUDE_CODE_SESSION_ID "$LX/helm" skipper --start dock); check "$?" "0" "--start: exit 0"
NEW=$(ls "$S5/la" | sed -n 's/^\(dev.regatta.helm.skipper-dock-[0-9]\{8\}-[0-9]\{6\}-[0-9a-f]\{4\}\)\.plist$/\1/p')
check "$(echo "$NEW" | grep -c .)" "1" "  one per-start plist for the scope"
has "$out" "started skipper · dock: $NEW" "  named by its start id"
pl=$(python3 -c 'import plistlib, sys, json; d = plistlib.load(open(sys.argv[1], "rb")); print(json.dumps([d["Label"], d.get("RunAtLoad"), "KeepAlive" in d, "LaunchOnlyOnce" in d, d["ProgramArguments"][1:6], d["ProgramArguments"][6].endswith("/libexec/skipper-run"), d["ProgramArguments"][7], d["EnvironmentVariables"].get("CLAUDE_REPOS_JSON") == sys.argv[2]]))' "$S5/la/$NEW.plist" "$CLAUDE_REPOS_JSON")
check "$pl" "[\"$NEW\", true, false, false, [\"-D\", \"-m\", \"-S\", \"skipper-dock\", \"/bin/bash\"], true, \"dock\", true]" \
  "  RunAtLoad, no KeepAlive, no LaunchOnlyOnce; screen -D -m -S skipper-dock /bin/bash skipper-run dock <id>; the overrides carried"
calls=$(cat "$S5/lc.calls")
has "$calls" "bootout gui/$(id -u)/$OLD" "  an older label's plist booted out"
has "$calls" "bootout gui/$(id -u)/dev.regatta.helm.skipper-dock-20260102-000000-beef" "  and one launchd still lists"
hasnt "$calls" "skipper-dockyard" "  another scope's label left alone"
check "$([ -e "$S5/la/$OLD.plist" ] && echo kept || echo removed)" "removed" "  its plist removed"
hasnt "$calls" "222.skipper-dockyard -X quit" "  nor its screen, whose name extends dock's (the quit names the pid: -S alone is a prefix)"
q=$(echo "$calls" | grep -n 'screen -S 111.skipper-dock -X quit' | head -1 | cut -d: -f1)
b=$(echo "$calls" | grep -n "bootstrap gui/$(id -u) $S5/la/$NEW.plist" | head -1 | cut -d: -f1)
check "$([ -n "$q" ] && [ -n "$b" ] && [ "$q" -lt "$b" ] && echo before || echo "q=$q b=$b")" "before" "  the screen quit before the new job is bootstrapped"
has "$(cat "$S5/screen.calls")" "SCREENDIR=$S5/screens" "  in the jobs' socket dir (HELM_SCREENDIR here)"
check "$(st5 dock launched)" "1" "  the starts log: one launched"
rm -f "$S5/lc.list" "$S5/la/dev.regatta.helm.skipper-dockyard-"*; : > "$S5/lc.calls"

echo "  the runner (libexec/skipper-run, with /usr/bin/python3): login, sign-in, trust, page, record, claude"
lay rs1 dock
# the runner runs only the start just launched, so each case launches its own first (NOLAUNCH: none)
run5() { [ -n "${NOLAUNCH:-}" ] || SK launch "${1:-dock}" "${2:-20260103-000000-0001}"
         env -u CLAUDE_CODE_SESSION_ID CLAUDE_CODE_ENTRYPOINT=cli DISPATCH_SHIP=leak DISPATCH_REPO=/leak \
             DISPATCH_MODE=leak DISPATCH_SCREEN=leak DISPATCH_BRIEF=leak DISPATCH_HOST=leak RUN_SEED_LEAK=leak bash "$LX/skipper-run" "${1:-dock}" "${2:-20260103-000000-0001}" > "$S5/run.out" 2>&1; echo $?; }
rm -f "$S5/cfg/acct-a/.trusted"
touch "$S5/la/dev.regatta.helm.skipper-dock-20260103-000000-0001.plist"
check "$(run5)" "0" "the runner execs claude (the stub exits 0)"
check "$([ -e "$S5/la/dev.regatta.helm.skipper-dock-20260103-000000-0001.plist" ] && echo kept || echo removed)" "removed" \
  "  its own plist removed first: a RunAtLoad plist left behind would start a skipper at the next login"
check "$(sed -n 1p "$S5/acct.calls")" "pick dockrepo" "  the anchor's pick first"
check "$(cat "$S5/trust.calls" | tr '\n' ',')" "trusted dockrepo acct-a,trust-projects acct-a,trusted dockrepo acct-a," "  the anchor untrusted: trust-projects on the picked login, read back"
check "$(rec dock account)/$(rec dock name)/$(rec dock space)/$(rec dock gen)/$(rec dock start)" "acct-a/skipper · dock/sp-dock/None/20260103-000000-0001" \
  "  the record: the login, the name, the Talk page as space, gen null, the start"
SID=$(rec dock session)
has "$(cat "$S5/sheep.calls")" "CLAUDE_CODE_SESSION_ID=$SID" "  the page deployed stamped with the new session's id"
argv=$(cat "$S5/claude.argv")
check "$(sed -n 1p "$S5/claude.argv" | chars 40)" "You are skipper · dock, the skipper of s" "  claude's first word is the brief"
has "$argv" "--session-id
$SID
--remote-control
skipper · dock
-n
steer-dock
--permission-mode
auto
--model
claude-opus-5-5
--effort
high
--disallowedTools
AskUserQuestion" "  then the session id, Remote Control, the name (steer-<scope>, the core's session_name), auto mode, Opus high, no AskUserQuestion"
has "$argv" "skipper --hold --scope dock --once" "  the brief: --hold --once first"
env5=$(cat "$S5/claude.env")
has "$env5" "cwd=$(cd "$S5/projects/dockrepo" && pwd -P)" "  cwd the anchor's checkout"
has "$env5" "CLAUDE_CONFIG_DIR=$S5/cfg/acct-a" "  on the picked login"
has "$env5" "SKIPPER_ACCOUNT=acct-a
SKIPPER_SCOPE=dock" "  SKIPPER_SCOPE and SKIPPER_ACCOUNT (the lease's account)"
check "$(sed -n 's/^HELM_HOLD_PARENT=//p' "$S5/claude.env")" "$(rec dock pid)" "  HELM_HOLD_PARENT is the record's pid, which exec made claude's"
check "$(sed -n 's/^pid=//p' "$S5/claude.env")" "$(rec dock pid)" "  (the stub claude runs as that very pid)"
hasnt "$env5" "CLAUDE_CODE_" "  no CLAUDE* marker handed down (the entrypoint, the session id)"
has "$env5" "CLAUDE_UNATTENDED=skipper" "  CLAUDE_UNATTENDED=skipper: every guard for a person's yes reads it as unattended"
check "$(grep -c '"event": "recorded"' "$S5/mgr/testhost-dock.starts.jsonl")/$(grep '"event": "recorded"' "$S5/mgr/testhost-dock.starts.jsonl" | grep -c "$SID")" "1/1" \
  "  the starts log names the start's session when the record is written"
# the runner writes its own log: under `screen -D -m` its stdout is the screen's terminal, and the
# plist's StandardOutPath holds only screen's own output
lg=$(cat "$S5/mgr/skipper-dock.log" 2>/dev/null)
has "$lg" "skipper-run dock, start 20260103-000000-0001, on testhost" "  the runner's lines go to skipper-<scope>.log itself"
has "$lg" "record $S5/mgr/testhost-dock.json; claude" "  up to the record and the exec"
hasnt "$env5" "DISPATCH_" "  no run variable either (the runner was handed SHIP, REPO, MODE, SCREEN, BRIEF and HOST: all gone, by prefix)"
hasnt "$env5" "RUN_SEED_" "  nor a seeded run's RUN_SEED_*"
rm -f "$S5/mgr/testhost-dock.json"; : > "$S5/acct.calls"; : > "$S5/trust.calls"; : > "$S5/sheep.calls"
# the anchor's pick is denied by a sibling: the sibling's pick, which every repo allows
echo '{"picks": {"dockrepo": "acct-a", "sib": "acct-b"}, "deny": {"acct-a": ["sib"]}}' > "$S5/acct.json"
touch "$S5/cfg/acct-b/.trusted"
check "$(run5 dock 20260103-000000-0005)" "0" "a sibling denies the anchor's pick: the runner still starts"
check "$(cat "$S5/acct.calls" | tr '\n' ',')" "pick dockrepo,pick sib," "  it picks for the denying repo next"
check "$(rec dock account)" "acct-b" "  and runs on that pick"
has "$(cat "$S5/claude.env")" "CLAUDE_CONFIG_DIR=$S5/cfg/acct-b" "  claude on it"
check "$(cat "$S5/sheep.calls" | grep -c -- '--space sp-dock')" "1" "  the scope's page redeployed, not a new one"
rm -f "$S5/mgr/testhost-dock.json" "$S5/claude.argv"
# nothing fits: the refusal names each denial, a failed start the tick reads at once
echo '{"picks": {"dockrepo": "acct-a", "sib": "acct-b"}, "deny": {"acct-a": ["sib"], "acct-b": ["dockrepo"], "acct-c": ["sib"]}}' > "$S5/acct.json"
touch "$S5/la/dev.regatta.helm.skipper-dock-20260103-000000-0002.plist"
check "$(run5 dock 20260103-000000-0002)" "1" "no login every repo allows: the runner refuses, exit 1"
check "$([ -e "$S5/la/dev.regatta.helm.skipper-dock-20260103-000000-0002.plist" ] && echo kept || echo removed)" "removed" "  a refused start leaves no plist"
has "$(cat "$S5/run.out")" "skipper won't start: no login every repo of dock allows (acct-a denies sib, acct-b denies dockrepo, acct-c denies sib)" "  the spec's line, each denial named"
check "$([ -e "$S5/mgr/testhost-dock.json" ] && echo record || echo none)/$([ -e "$S5/claude.argv" ] && echo claude || echo none)" "none/none" "  no record, no claude"
check "$(python3 -c 'import json, sys; ls = [json.loads(x) for x in open(sys.argv[1])]; r = ls[-1]; print(r["event"], r["start"])' "$S5/mgr/testhost-dock.starts.jsonl")" "refused 20260103-000000-0002" "  the starts log: refused, by its start id"
check "$(lev rs1 "skipper won't start")" "1" "  and a 'skipper won't start' event on the scope's ship"
# signed out: refused at once, nothing else tried
echo '{"picks": {"dockrepo": "acct-a", "sib": "acct-a"}, "deny": {}}' > "$S5/acct.json"
touch "$S5/cfg/acct-a/.out"; : > "$S5/trust.calls"
check "$(run5 dock 20260103-000000-0003)" "1" "a login that is not logged in: refused, exit 1"
has "$(cat "$S5/run.out")" "skipper won't start: acct-a is not logged in" "  the line names the login"
check "$(cat "$S5/trust.calls" | wc -l | tr -d ' ')/$([ -e "$S5/claude.argv" ] && echo claude || echo none)" "0/none" "  no trust step, no claude, no other login tried"
rm -f "$S5/cfg/acct-a/.out" "$S5/cfg/acct-a/.trusted"; touch "$S5/cfg/acct-a/.untrustable"
check "$(run5 dock 20260103-000000-0004)" "1" "still untrusted after trust-projects: refused"
has "$(cat "$S5/run.out")" "skipper won't start: untrusted ($S5/cfg/acct-a)" "  untrusted (<dir>)"
rm -f "$S5/cfg/acct-a/.untrustable"; touch "$S5/cfg/acct-a/.trusted"
check "$(SK fails dock)" "3" "  three refusals in a row counted"
# `account allowed` crashing (a traceback, exit 1) is no denial: "could not tell", naming no login as denying
touch "$S5/acct.crash"
check "$(run5 dock 20260103-000000-0006)" "1" "account allowed crashes: refused, exit 1"
has "$(cat "$S5/run.out")" "skipper won't start: acct-a: could not tell whether the login may work in" "  as could not tell"
hasnt "$(cat "$S5/run.out")" "denies" "  never as a denial"
rm -f "$S5/acct.crash"
# the start must be the one just launched: never one launchd loads again, one already judged, or one never launched
check "$(NOLAUNCH=1 run5 dock 20260103-000000-0009)" "1" "a start id never launched: the runner refuses"
has "$(cat "$S5/run.out")" "won't run: start 20260103-000000-0009 is not in the starts log" "  saying so"
check "$(NOLAUNCH=1 run5 dock 20260103-000000-0002)" "1" "  a start already judged (refused above): refused"
has "$(cat "$S5/run.out")" "judged already (refused)" "  saying so"
STALLS_NOW=$(( $(now) - 400 )) SK launch dock 20260103-000000-0007
touch "$S5/la/dev.regatta.helm.skipper-dock-20260103-000000-0007.plist"
check "$(NOLAUNCH=1 run5 dock 20260103-000000-0007)" "1" "  a start launched 400 s ago (a reload at login): refused"
has "$(cat "$S5/run.out")" "s old — only a start just launched runs" "  saying how old"
check "$([ -e "$S5/la/dev.regatta.helm.skipper-dock-20260103-000000-0007.plist" ] && echo kept || echo removed)/$([ -e "$S5/claude.argv" ] && echo claude || echo none)" \
  "removed/none" "  its plist removed all the same, and no claude"
check "$(SK fails dock)" "4" "  (those three logged nothing: the count is the four refusals)"
# no Talk page: refused — the skipper's only ear is ask listen on Talk, and nothing on the file road wakes it
touch "$S5/sheep.fail"; rm -f "$S5/space.calls"
check "$(run5 dock 20260103-000000-000a)" "1" "the Talk page will not deploy: refused, exit 1"
has "$(cat "$S5/run.out")" "skipper won't start: no Talk page (" "  saying so"
has "$(cat "$S5/run.out")" "a skipper with no Talk page hears nothing" "  and why"
check "$([ -e "$S5/mgr/testhost-dock.json" ] && echo record || echo none)/$([ -e "$S5/claude.argv" ] && echo claude || echo none)" "none/none" "  no record, no claude"
rm -f "$S5/sheep.fail"
check "$(SK fails dock)" "5" "  counted as a failed start"
# a third login every repo allows: the picks run out (the anchor's pick denies sib, sib's denies the
# anchor), and the walk's other rows are tried before refusing
echo '{"picks": {"dockrepo": "acct-a", "sib": "acct-b"}, "deny": {"acct-a": ["sib"], "acct-b": ["dockrepo"]}}' > "$S5/acct.json"
touch "$S5/cfg/acct-c/.trusted"; rm -f "$S5/claude.argv"
check "$(run5 dock 20260103-000000-000b)" "0" "the anchor's pick and sib's pick each deny one repo: a third login is tried"
check "$(rec dock account)" "acct-c" "  and the one every repo allows runs it"
rm -f "$S5/mgr/testhost-dock.json" "$S5/claude.argv"
# the runner's own deadline: a minute inside TAKE_WITHIN, it writes no record that late
STALLS_NOW=$(( $(now) - 250 )) SK launch dock 20260103-000000-000c
check "$(NOLAUNCH=1 run5 dock 20260103-000000-000c)" "1" "a runner 250 s after its launch: refused before the record"
has "$(cat "$S5/run.out")" "past its own 240s" "  saying so"
check "$([ -e "$S5/mgr/testhost-dock.json" ] && echo record || echo none)" "none" "  no record a pass could meet half-judged"
# a crashed `dispatch-rc trusted` is "could not tell", never "untrusted"
touch "$S5/rc.crash"
check "$(run5 dock 20260103-000000-000d)" "1" "dispatch-rc trusted crashes: refused"
has "$(cat "$S5/run.out")" "could not tell whether" "  as could not tell"
hasnt "$(cat "$S5/run.out")" "untrusted (" "  never as untrusted"
rm -f "$S5/rc.crash"
echo '{"picks": {"dockrepo": "acct-a", "sib": "acct-a"}, "deny": {}}' > "$S5/acct.json"
# an exec failure: the record removed, the failure logged, the plist gone
touch "$S5/la/dev.regatta.helm.skipper-dock-20260103-000000-0008.plist"
check "$(HELM_CLAUDE="$S5/bin/no-claude" run5 dock 20260103-000000-0008)" "1" "claude will not exec: refused, exit 1"
has "$(cat "$S5/run.out")" "skipper won't start: claude did not start" "  saying so"
check "$([ -e "$S5/la/dev.regatta.helm.skipper-dock-20260103-000000-0008.plist" ] && echo kept || echo removed)/$([ -e "$S5/mgr/testhost-dock.json" ] && echo record || echo none)" \
  "removed/none" "  no plist, no record left"
# claude-host (skipper-ears S1: a bare claude under launchd hung on the yard, denied Full Disk Access):
# where `rc-hosts --launcher claude` names one (the stubs above, with rch.on), the runner asks it once,
# inside its own deadline, and runs both the sign-in probe and the exec through it, `claude` first;
# the record's pid is then the launcher's, which forks claude and waits
touch "$S5/rch.on"; rm -f "$S5/host.argv" "$S5/rch.calls"
check "$(run5 dock 20260103-000000-000e)" "0" "a granted claude-host: the runner execs it"
check "$(cat "$S5/rch.calls")" "--launcher claude" "  asked once, as dispatch asks: rc-hosts --launcher claude"
has "$(cat "$S5/host.argv")" "claude
auth
status
--json" "  the sign-in probe goes through it too (a bare claude is the binary TCC denied)"
check "$(grep -A1 -x claude "$S5/host.argv" | tail -1 | chars 40)" "You are skipper · dock, the skipper of s" "  the session's argv: claude first, then the brief"
check "$(sed -n 1p "$S5/claude.argv" | chars 40)" "You are skipper · dock, the skipper of s" "  and claude receives the brief first, as a bare claude does"
has "$(cat "$S5/run.out")" "claude through $S5/bin/claude-host" "  the runner names the launcher"
cpid=$(sed -n 's/^pid=//p' "$S5/claude.env")
check "$([ -n "$cpid" ] && [ "$cpid" != "$(rec dock pid)" ] && echo child || echo same)" "child" "  claude runs as the launcher's child, not as the record's pid"
check "$(sed -n 's/^HELM_HOLD_PARENT=//p' "$S5/claude.env")" "$(rec dock pid)" "  HELM_HOLD_PARENT is the record's pid (the launcher, which lives as long as claude)"
rm -f "$S5/rch.on" "$S5/host.argv"
check "$(run5 dock 20260103-000000-000f)" "0" "no grant (rc-hosts --launcher exits 1): a bare claude, as before"
check "$(wc -l < "$S5/rch.calls" | tr -d ' ')" "2" "  rc-hosts was asked"
check "$([ -e "$S5/host.argv" ] && echo launcher || echo bare)" "bare" "  claude-host never run"
has "$(cat "$S5/run.out")" "claude through no claude-host (bare)" "  and the runner says so"
# a launcher that is not executable is none: a bare claude, never a start that fails at exec
touch "$S5/rch.on"; chmod -x "$S5/bin/claude-host"; rm -f "$S5/host.argv"
check "$(run5 dock 20260103-000000-0010)" "0" "a claude-host that is not executable: a bare claude"
check "$([ -e "$S5/host.argv" ] && echo launcher || echo bare)" "bare" "  claude-host never run"
chmod +x "$S5/bin/claude-host"; rm -f "$S5/rch.on"
# the rule is wharf-runs' launcherlib (clock and rc-hosts use it too): an empty answer is bare, the last line the path
touch "$S5/rch.on" "$S5/rch.empty"; rm -f "$S5/host.argv"
check "$(run5 dock 20260103-000000-0021)" "0" "rc-hosts exits 0 and prints nothing: a bare claude"
check "$([ -e "$S5/host.argv" ] && echo launcher || echo bare)" "bare" "  claude-host never run"
rm -f "$S5/rch.empty"; touch "$S5/rch.banner"
check "$(run5 dock 20260103-000000-0022)" "0" "rc-hosts prints a note, then the path: the path is the answer"
has "$(cat "$S5/run.out")" "claude through $S5/bin/claude-host" "  the runner names the launcher"
rm -f "$S5/rch.on" "$S5/rch.banner" "$S5/host.argv"
# stop() through claude-host: the registry names claude, the launcher's child; the record names the
# launcher. The child is signalled (it is the registry's pid and the record's pid is its parent)
cat > "$S5/fakehost" <<'EOF'
#!/bin/bash
/bin/sleep 300 & c=$!
trap 'kill -TERM $c 2>/dev/null' TERM INT HUP
wait $c
EOF
chmod +x "$S5/fakehost"; "$S5/fakehost" & HP=$!; disown $HP
for _ in 1 2 3 4 5 6 7 8; do CP=$(pgrep -P $HP); [ -n "$CP" ] && break; sleep 0.25; done
mkrec dock sk-h $HP "$(now)" 20260103-000000-0011; regi sk-h $CP idle
SK stop dock > /dev/null
for _ in 1 2 3 4 5 6 7 8; do kill -0 $CP 2>/dev/null || break; sleep 0.25; done
check "$(kill -0 $CP 2>/dev/null && echo alive || echo ended)" "ended" "--stop through claude-host: the registry's claude (the launcher's child) ended"
kill $HP $CP 2>/dev/null; rm -f "$T/sess/sk-h.json" "$S5/rch.calls"
# the starts above took no ship: leave the store as the exec-failure case left it (no record, and
# no starts-log lines of theirs), or the stall road below counts them as more failed starts
rm -f "$S5/mgr/testhost-dock.json" "$S5/la/"*20260103-000000-00{0e,0f,10,11}*
grep -v -E '20260103-000000-00(0e|0f|10|11)' "$S5/mgr/testhost-dock.starts.jsonl" > "$S5/starts.tmp"; mv "$S5/starts.tmp" "$S5/mgr/testhost-dock.starts.jsonl"

echo "  the stall road: three failed starts are the class \`skipper won't start\`"
ws=$(env -u CLAUDE_CODE_SESSION_ID python3 - "$B" <<'PY'
import sys; sys.path.insert(0, sys.argv[1]); import stalls, time
s = stalls.judge_skippers("testhost", time.time())
print(len(s), s[0]["class"], s[0]["action"], s[0]["key"], s[0]["repo"], s[0]["guarded"], stalls.column(dict(s[0])), stalls.title(s[0], time.time()))
PY
)
check "$ws" "1 skipper won't start raise ['testhost', 'skipper', 'dock'] dockrepo False Needs Sam skipper · dock · skipper won't start (8 failed starts in a row)" \
  "  one raised stall, for the owner, keyed by scope, its repo the scope's anchor"
out=$(SK ensure act); has "$out" "skipper · dock: won't start: 8 failed starts in a row" "  the tick starts none past the third"
check "$(env -u CLAUDE_CODE_SESSION_ID python3 - "$B" <<'PY'
import sys, time; sys.path.insert(0, sys.argv[1]); import stalls, skipperlib
def broken(host=None):
    raise RuntimeError("the starts log will not read")
skipperlib.wont_start_stalls = broken
notes = []
print(stalls.judge_skippers("testhost", time.time(), notes), "class not judged (RuntimeError" in notes[0])
PY
)" "[] True" "  a read that fails: no stall of the class, and a note that says so (never silent)"
check "$(grep -c bootstrap "$S5/lc.calls")" "0" "  nothing loaded"
# the owner's start by hand: try again (the count restarts), and the class clears once a start takes
: > "$S5/lc.calls"
env -u CLAUDE_CODE_SESSION_ID "$LX/helm" skipper --start dock > /dev/null
check "$(SK fails dock)/$(grep -c bootstrap "$S5/lc.calls")" "0/1" "  --start by hand from a shell: loaded, and the failure count starts over"
# …and the tick then has its three: the hand start's own failure is not one of them
check "$(SK fails_of '[{"event": "failed", "start": "a"}, {"event": "launched", "start": "h", "by": "hand"}, {"event": "failed", "start": "h"}, {"event": "failed", "start": "b"}, {"event": "failed", "start": "c"}]')" \
  "2" "  after a hand start that failed, two tick failures count two (not three)"

echo "  the tick's pass: a start per scope with work, none for a held lease"
rm -rf "$S5/mgr/"*; : > "$S5/lc.calls"; rm -f "$S5/la/"*
lay rs2 solo
rm -rf "$S5/screens"
out=$(SK ensure act)
has "$out" "started skipper · dock" "a ship the yard holds with an open block: its scope's skipper started"
has "$out" "started skipper · solo" "  every scope with work, one each"
check "$(grep -c bootstrap "$S5/lc.calls")" "2" "  two jobs loaded, one per scope"
check "$([ -d "$S5/screens" ] && echo made || echo missing)" "made" "  the jobs' SCREENDIR made by the start (screen cannot make it)"
out=$(SK ensure act)
has "$out" "skipper · dock: waits: start" "  the next pass: no second start while the first has no outcome"
check "$(grep -c bootstrap "$S5/lc.calls")" "2" "  nothing more loaded"
out=$(SK ensure dry); hasnt "$out" "started" "  a dry pass starts nothing"
# the owner stops a tick start by hand before it took a ship: its end, never a failed start later
env -u CLAUDE_CODE_SESSION_ID "$LX/helm" skipper --stop dock --why "the suite" > /dev/null
out=$(STALLS_NOW=$(( $(now) + 400 )) SK ensure dry)
hasnt "$out" "skipper · dock: would record failed start" "a tick start stopped by hand before it took: not judged a failed start"
# one malformed record costs its own scope's pass, never the others'
echo '{"session": "sk-m", "pid": 1, "started": {"at": 1}, "start": "x"}' > "$S5/mgr/testhost-dock.json"
out=$(SK ensure dry)
has "$out" "skipper · dock: the pass failed (TypeError" "a record whose started is no number: that scope's pass fails, one line"
has "$out" "skipper · solo" "  and the next scope is still judged"
rm -f "$S5/mgr/testhost-dock.json"
# a dry pass with no start pending prints the spec's line
rm -f "$S5/mgr/"*
has "$(SK ensure dry)" "would start skipper · dock (rs1)" "  a dry pass: \`would start skipper · <scope>\`"
has "$("$LX/helm" tick --dry-run 2>&1)" "would start skipper · dock" "  helm tick --dry-run prints it too"
# a live skipper that took the ship: no start, and the start's verdict is `took`
nap; SP=$NAP
mkrec dock sk-1 $SP "$(now)" 20260104-000000-0001; regi sk-1 $SP
CLAUDE_CODE_SESSION_ID=sk-1 HELM_HOLD_PARENT=$SP "$LX/helm" skipper --hold --scope dock --once > /dev/null
: > "$S5/lc.calls"
out=$(SK ensure act); hasnt "$out" "skipper · dock: started" "a live skipper holding the scope's ship: no start"
check "$(grep -c bootstrap "$S5/lc.calls")" "1" "  (only solo's skipper is started)"
check "$(grep -c '"event": "took"' "$S5/mgr/testhost-dock.starts.jsonl")" "1" "  the start's verdict: took"
check "$(SK fails dock)" "0" "  and the failure count is zero"
# --stop --dry-run stops nothing and says what it would
: > "$S5/lc.calls"
out=$(env -u CLAUDE_CODE_SESSION_ID "$LX/helm" skipper --stop dock --dry-run); check "$?" "0" "--stop --dry-run: exit 0"
has "$out" "would hand rs1 to the yard" "  says it would hand the ship back"
has "$out" "would quit screen 111.skipper-dock" "  and quit its screen"
has "$out" "would stop skipper · dock (by hand): rs1" "  and stop it"
check "$(lf rs1 holder)/$([ -e "$S5/mgr/testhost-dock.json" ] && echo kept || echo deleted)/$(grep -c -e bootout -e quit "$S5/lc.calls")" \
  "skipper · dock/kept/0" "  and does none of it: the lease held, the record kept, nothing booted out or quit"
# --start while a skipper holds the scope's ships: stopped as --stop stops it, its ships back to the yard first
out=$(env -u CLAUDE_CODE_SESSION_ID "$LX/helm" skipper --start dock); check "$?" "0" "--start over a live skipper: exit 0"
has "$out" "stopped skipper · dock (replaced by start " "  the live one stopped first"
check "$(lf rs1 holder)/$([ -e "$S5/mgr/testhost-dock.json" ] && echo kept || echo deleted)" "yard/deleted" "  its ship back to the yard, its record deleted"
has "$out" "started skipper · dock" "  then the new job"
# one window: a launch 295 s old with no record waits (it is not failed until past 300 s), never relaunched
rm -f "$S5/mgr/testhost-dock.json"; : > "$S5/lc.calls"
STALLS_NOW=$(( $(now) - 295 )) SK launch dock 20260104-000000-00a1
out=$(SK ensure act)
has "$out" "skipper · dock: waits: start 20260104-000000-00a1 launched 29" "a launch 295 s old, no record: waits"
check "$(grep -c -e bootstrap -e bootout "$S5/lc.calls")" "0" "  neither booted out nor relaunched"
# a record whose claude is up but not yet in the registry (it registers after the exec): young, it waits
nap; SY=$NAP
mkrec dock sk-y $SY "$(( $(now) - 60 ))" 20260104-000000-00a1
out=$(SK ensure act); has "$out" "skipper · dock: waits: start 20260104-000000-00a1 is" "a live pid not yet registered, 60 s old: waits"
hasnt "$out" "failed start" "  never a failed start"
# S13a: a brake window by hand (`bwin <dir> <start> <end>`, epoch seconds), the record helmlib reads
bwin() { mkdir -p "$1"; printf '{"windows": [[%s, %s]], "since": null, "seen": null, "pass": null}' "$2" "$3" > "$1/brake-windows.json"; }
bwin "$STALLS_STATE_DIR" $(( $(now) - 400 )) $(( $(now) - 60 ))
mkrec dock sk-y $SY "$(( $(now) - 400 ))" 20260104-000000-00a1
out=$(SK ensure act); has "$out" "skipper · dock: waits: start 20260104-000000-00a1 is" "a start 400 s old, 340 s of them under the studio brake: its own 60 s, it waits (S13a)"
hasnt "$out" "failed start" "  never a failed start"
rm -f "$STALLS_STATE_DIR/brake-windows.json"
mkrec dock sk-y $SY "$(( $(now) - 400 ))" 20260104-000000-00a1
out=$(SK ensure act); has "$out" "stopped skipper · dock (failed start: no ship taken in 6m" "  400 s old and still no ship: a failed start"
# a registry record left over a reboot names a pid another process holds now: its start tells them apart
nap; SPS=$NAP
printf '{"pid": %d, "sessionId": "sk-ps", "status": "busy", "procStart": "%s"}' $SPS "$(TZ=UTC LC_ALL=C ps -o lstart= -p $SPS | xargs)" > "$T/sess/sk-ps.json"
RJ="{\"pid\": $SPS, \"session\": \"sk-ps\"}"   # set apart: bash 3.2 brace-expands a {a, b} nested in "$(…)" (AGENTS.md)
check "$(SK alive "$RJ")" "True" "record_alive: the registry's procStart is this process's start (UTC)"
printf '{"pid": %d, "sessionId": "sk-ps", "status": "busy", "procStart": "Mon Jan  1 00:00:00 2001"}' $SPS > "$T/sess/sk-ps.json"
check "$(SK alive "$RJ")" "False" "  a pid whose start is not the registry's: not the skipper (never signalled)"
rm -f "$T/sess/sk-ps.json"
# the same test for session_ancestor: a record a crash left over a reboot, naming the pid a shell now
# holds, never refuses the verbs from that shell (the fix review of the fifth finish review)
check "$(env -u CLAUDE_CODE_SESSION_ID python3 - "$B" "$T/sess" <<'PY'
import json, os, subprocess, sys
sys.path.insert(0, sys.argv[1])
import skipperlib
p = os.getppid(); f = os.path.join(sys.argv[2], "%d.json" % p)
start = subprocess.run(["ps", "-o", "lstart=", "-p", str(p)], env=dict(os.environ, TZ="UTC", LC_ALL="C"),
                       capture_output=True, text=True).stdout.strip()
out = []
for ps in ("Mon Jan  1 00:00:00 2001", start):
    json.dump(dict(pid=p, sessionId="sk-anc", status="busy", procStart=ps), open(f, "w"))
    out.append(skipperlib.session_ancestor() == p)
os.remove(f)
print(out)
PY
)" "[False, True]" "session_ancestor: a registry record whose procStart is not the pid's start is no session; its own start is"
# the tick's pass under CLAUDE_UNATTENDED, or below a session: `would …`, nothing done
mkdir -p "$STALLS_STATE_DIR"
out=$(env -u CLAUDE_CODE_SESSION_ID CLAUDE_UNATTENDED=skipper python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import stalls_tick; print("\n".join(stalls_tick.ensure_skippers("armed")))' "$B")
has "$out" "would start skipper · dock" "an armed pass in an unattended caller: would start, never starts"
has "$out" "nothing done — helm skipper the tick's pass: refused in an unattended caller" "  saying why"
: > "$S5/lc.calls"

echo "  a failed start: a live pid and a record, no ship taken in 5 minutes"
lay rs3 solo
nap; SQ=$NAP
mkrec solo sk-2 $SQ "$(( $(now) - 400 ))" 20260104-000000-0002; regi sk-2 $SQ
: > "$S5/lc.calls"
out=$(SK ensure act)
has "$out" "stopped skipper · solo (failed start: no ship taken in 6m" "the stuck start is a failed start, and is stopped"
check "$([ -e "$S5/mgr/testhost-solo.json" ] && echo kept || echo deleted)" "deleted" "  its record deleted"
has "$(cat "$S5/lc.calls")" "screen -S 333.skipper-solo -X quit" "  its screen quit, by pid and name"
check "$(python3 -c 'import json, sys; ls = [json.loads(x) for x in open(sys.argv[1])]; print([l["event"] for l in ls if l.get("start") == "20260104-000000-0002"])' "$S5/mgr/testhost-solo.starts.jsonl")" \
  "['failed', 'stopped']" "  the starts log: failed, then stopped"
for _ in 1 2 3 4 5 6 7 8; do kill -0 $SQ 2>/dev/null || break; sleep 0.25; done
check "$(kill -0 $SQ 2>/dev/null && echo alive || echo ended)" "ended" "  the claude its record names ended"
hasnt "$out" "started skipper · solo" "  no start in the pass that stopped it"
# a start that took a ship and stood down before any armed pass saw its record: took, never a failure
nap; SR=$NAP; regi sk-8 $SR
STALLS_NOW=$(( $(now) - 400 )) SK launch solo 20260104-000000-0003
SK log solo recorded 20260104-000000-0003 sk-8
CLAUDE_CODE_SESSION_ID=sk-8 HELM_HOLD_PARENT=$SR "$LX/helm" skipper --hold --scope solo --once > /dev/null
out=$(SK ensure act)
hasnt "$out" "record failed start 20260104-000000-0003" "a start whose record is gone, but whose session took a ship: no failure"
check "$(python3 -c 'import json, sys; print([l["event"] for l in map(json.loads, open(sys.argv[1])) if l.get("start") == "20260104-000000-0003"])' "$S5/mgr/testhost-solo.starts.jsonl")" \
  "['launched', 'recorded', 'took']" "  its verdict: took, read from the session the runner logged"
# the tick replaces only what it started: ships a live session holds with no record (a hold by hand) stay its own
lay rs5 solo
out=$(SK ensure act)
has "$out" "started skipper · solo" "a ship the yard holds beside ships a recordless session holds: a start"
check "$(lf rs2 session)/$(lf rs3 session)" "sk-8/sk-8" "  the recordless holder's ships left to it (the tick's start stops no one)"
# …nor do the tick's stops: they hand back only what the record's session holds
lay rs6 solo
nap; S9=$NAP; mkrec solo sk-9 $S9 "$(now)" 20260104-000000-00b1; regi sk-9 $S9
CLAUDE_CODE_SESSION_ID=sk-9 HELM_HOLD_PARENT=$S9 "$LX/helm" skipper --hold --scope solo --once > /dev/null
out=$(SK stop solo)
has "$out" "rs6 back to the yard" "the tick's stop: the record's session's ship back to the yard"
check "$(lf rs2 session)/$(lf rs3 session)/$(lf rs6 holder)" "sk-8/sk-8/yard" "  the recordless holder's ships left to it"
# a start that takes a ship and then crashes is a failed start, though it took: no endless restarts
sleep 0 & DEADP=$!; wait $DEADP
nap; SC=$NAP
CLAUDE_CODE_SESSION_ID=sk-c HELM_HOLD_PARENT=$SC "$LX/helm" skipper --hold --scope solo --once > /dev/null
mkrec solo sk-c $DEADP "$(( $(now) - 120 ))" 20260104-000000-00c1; regi sk-c $DEADP
SK log solo took 20260104-000000-00c1 sk-c
out=$(SK ensure act)
has "$out" "stopped skipper · solo (its claude has ended (session sk-c))" "a skipper that took a ship and ended 2 minutes in: stopped"
check "$(grep '20260104-000000-00c1' "$S5/mgr/testhost-solo.starts.jsonl" | grep -c '"event": "failed"')" "1" "  and logged a failed start, its took notwithstanding"
check "$(SK fails_of '[{"event": "took", "start": "a"}, {"event": "failed", "start": "a"}, {"event": "took", "start": "b"}, {"event": "failed", "start": "b"}]')" \
  "2" "  two such starts count two: a took the start later failed never ends the run of failures"
# the pass that logs a third failure starts no fourth
lay f1 four
SK log four refused 20260109-000000-000a; SK log four refused 20260109-000000-000b
STALLS_NOW=$(( $(now) - 400 )) SK launch four 20260109-000000-000c
: > "$S5/lc.calls"
out=$(SK ensure act)
has "$out" "skipper · four: record failed start 20260109-000000-000c: the runner wrote no record in 5m" "a launch with no record in 5 minutes: its failure logged"
has "$out" "skipper · four: won't start: 3 failed starts in a row" "  and in the same pass, no fourth start"
check "$(grep -c 'bootstrap.*skipper-four' "$S5/lc.calls")" "0" "  nothing of four's loaded"
# the stall of a guarded or confidential scope is a guarded card (its failure text names repo keys and logins)
check "$(env -u CLAUDE_CODE_SESSION_ID python3 -c 'import sys, time; sys.path.insert(0, sys.argv[1]); import stalls; print([(s["key"][2], s["guarded"]) for s in stalls.judge_skippers("testhost", time.time()) if s["key"][2] == "four"])' "$B")" \
  "[('four', True)]" "four's stall (a confidential scope): guarded"
mv "$LP/f1/skipper.json" "$LP/f1/skipper.json.off"
check "$(env -u CLAUDE_CODE_SESSION_ID python3 -c 'import sys, time; sys.path.insert(0, sys.argv[1]); import stalls; print([s["key"][2] for s in stalls.judge_skippers("testhost", time.time())])' "$B" | grep -c four)" \
  "0" "  no live ship of the scope left: no stall"
mv "$LP/f1/skipper.json.off" "$LP/f1/skipper.json"
has "$(STALLS_NOW=$(( $(now) + 3700 )) SK ensure dry)" "would start skipper · four" "three failures an hour old: the tick tries once more (a week out, a blip pass by themselves)"
"$HM" report f1 --task b1 --status done > /dev/null
check "$(env -u CLAUDE_CODE_SESSION_ID python3 -c 'import sys, time; sys.path.insert(0, sys.argv[1]); import stalls; print([s["key"][2] for s in stalls.judge_skippers("testhost", time.time())])' "$B" | grep -c four)" \
  "0" "  a scope whose ships need no skipper any more: no stall"

echo "  stand-down and the belt: a ship waiting only on the owner needs nobody"
rm -rf "$PLANS_DIR" "$S5/mgr/"*; : > "$S5/lc.calls"; rm -f "$S5/la/"* "$STALLS_STATE_DIR/skippers.json"
lay ow1 dock h1 human
check "$(SK needs ow1)" "(False, ['h1'])" "a ship whose one open block is a person's: needs no skipper"
out=$("$LX/helm" skipper --ships dock)
has "$out" "the owner's alone (h1)" "  --ships says whose it is"
has "$out" "nothing needs skipper · dock" "  and gives the stand-down line"
check "$(SK ensure act)" "" "  the tick starts no skipper for it"
"$HM" task ow1 b2 > /dev/null
hasnt "$("$LX/helm" skipper --ships dock)" "nothing needs skipper" "  with a session block open: no stand-down line"
check "$(SK needs ow1)" "(True, ['h1'])" "  and it needs one"
# --escalate marks one open question as the owner's: by its Dn, checked against the ship's open questions
askev ow1 b2 docs/e.md#D3 "" file 10
out=$(env -u CLAUDE_CODE_SESSION_ID "$LX/helm" skipper --escalate ow1 D9 2>&1); check "$?" "1" "--escalate of a question the ship has not open: refused"
has "$out" "D9 names no open question of ship ow1 — open: docs/e.md#D3" "  listing the open ones"
n0=$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import helmlib; print(sum(len(t["asks"]) for t in helmlib.state("ow1")["tasks"]))' "$B")
check "$n0" "1" "  and no phantom ask made"
out=$(env -u CLAUDE_CODE_SESSION_ID "$LX/helm" skipper --escalate ow1 D3); check "$?" "0" "--escalate D3: exit 0"
has "$out" "ow1 docs/e.md#D3: escalated to the owner (task b2)" "  the ref found from its Dn"
check "$(tail -1 "$LP/ow1/events.jsonl" | python3 -c 'import json, sys; print(sorted(json.load(sys.stdin)))')" \
  "['ask', 'escalated', 'plan', 't', 'task', 'via']" "  its event stamps no session, host, repo, status or progress on the run's task"
check "$(SK needs ow1)" "(False, ['b2', 'h1'])" "  a block whose only open question is escalated is the owner's too"
# the old progress text sticks to the task: a later question on it is still the skipper's
"$HM" report ow1 --task b2 --status waiting --progress "escalated D3 to the owner" > /dev/null
askev ow1 b2 docs/e.md#D4 "" file 5
check "$(SK needs ow1)" "(True, ['h1'])" "  a later question D4 on the same block: it needs a skipper again (no sticky progress)"
"$HM" report ow1 --task b2 --status done > /dev/null
# the 30-minute belt: a healthy skipper, nothing to hold
nap; SP=$NAP
mkrec dock sk-3 $SP "$(now)" 20260105-000000-0001; regi sk-3 $SP
printf '{"t": 1, "event": "took", "start": "20260105-000000-0001"}\n' > "$S5/mgr/testhost-dock.starts.jsonl"
"$HM" $SHIP done1 --id done1 > /dev/null; ll yard done1 dock > /dev/null
CLAUDE_CODE_SESSION_ID=sk-3 HELM_HOLD_PARENT=$SP "$LX/helm" skipper --hold --scope dock --once > /dev/null
T0=$(now)
# an idle mark an earlier skipper left when it stood down by itself (2 h ago): never this start's
mkdir -p "$STALLS_STATE_DIR"; printf '{"dock": {"idle_since": %d, "start": "20260104-000000-0001"}}' $((T0 - 7200)) > "$STALLS_STATE_DIR/skippers.json"
out=$(STALLS_NOW=$T0 SK ensure act); hasnt "$out" "stopped" "the belt: idle for less than 30 minutes, kept (an earlier start's idle mark not inherited)"
check "$(python3 -c 'import json, sys; print("idle_since" in json.load(open(sys.argv[1]))["dock"])' "$STALLS_STATE_DIR/skippers.json")" "True" "  its idle time noted"
out=$(STALLS_NOW=$((T0 + 1860)) SK ensure act)
has "$out" "stopped skipper · dock (no ship has needed it for 31m)" "  31 minutes on: --stop by the tick"
check "$(lf ow1 holder)/$(lf done1 holder)" "yard/yard" "  its ships back to the yard first"
check "$([ -e "$S5/mgr/testhost-dock.json" ] && echo kept || echo deleted)" "deleted" "  its record deleted"
# the daily hand-over: older than 24 h at the 04:00 pass
"$HM" task done1 b9 > /dev/null
nap; SP=$NAP
# tomorrow's 04:10 and 02:10, local: the record 27 h old now, so past 24 h at both
T4=$(python3 -c 'import time; t = time.localtime(time.time() + 86400); print(int(time.mktime((t.tm_year, t.tm_mon, t.tm_mday, 4, 10, 0, 0, 0, -1))))')
T2=$(python3 -c 'import time; t = time.localtime(time.time() + 86400); print(int(time.mktime((t.tm_year, t.tm_mon, t.tm_mday, 2, 10, 0, 0, 0, -1))))')
# busy at every pass: never quiet, so the rotation waits and only the ceiling ends it
mkrec dock sk-4 $SP "$(( $(now) - 97200 ))" 20260106-000000-0001; regi sk-4 $SP busy
CLAUDE_CODE_SESSION_ID=sk-4 HELM_HOLD_PARENT=$SP "$LX/helm" skipper --hold --scope dock --once > /dev/null
out=$(STALLS_NOW=$T2 SK ensure act); hasnt "$out" "stopped" "the daily hand-over: past 24 h at 02:10, kept"
out=$(STALLS_NOW=$T4 SK ensure act); has "$out" "stopped skipper · dock (the daily hand-over (" "  past 24 h at the 04:00 pass: stopped"
has "$out" "h old at the 04:00 pass)" "  saying when"
check "$(lf done1 holder)" "yard" "  its ship back to the yard"

echo "  the rotation: 8 h old or 200k tokens of context, at the first quiet pass"
rm -rf "$PLANS_DIR" "$S5/mgr/"*; : > "$S5/lc.calls"; rm -f "$S5/la/"* "$STALLS_STATE_DIR/skippers.json"
lay ro1 dock
nap; SP=$NAP
mkrec dock sk-r $SP "$(( $(now) - 25200 ))" 20260110-000000-0001; regi sk-r $SP idle
CLAUDE_CODE_SESSION_ID=sk-r HELM_HOLD_PARENT=$SP "$LX/helm" skipper --hold --scope dock --once > /dev/null
out=$(SK ensure act); hasnt "$out" "stopped" "7 h old, idle, nothing open: kept"
T9=$(( $(now) + 7200 ))
regi sk-r $SP busy
out=$(STALLS_NOW=$T9 SK ensure act); hasnt "$out" "stopped" "  9 h old, working a turn: kept (not quiet)"
regi sk-r $SP waiting
out=$(STALLS_NOW=$T9 SK ensure act); hasnt "$out" "rotated" "  9 h old, stopped at a dialog: not the rotation's (the deaf rule's)"
regi sk-r $SP idle
askev ro1 b1 docs/r.md#D1 sk-r talk 60
out=$(STALLS_NOW=$T9 SK ensure act); hasnt "$out" "stopped" "  9 h old, idle, a question of its own open: kept, never cut off mid-question"
python3 - "$B" <<'PY'
import sys; sys.path.insert(0, sys.argv[1]); import helmlib
helmlib.append_event("ro1", {"task": "b1", "answered": "docs/r.md#D1", "from": "skipper-dock", "plan": "ro1"})
PY
# idle a minute by its status stamp: between two Remote Control messages, never quiet
printf '{"pid": %d, "sessionId": "sk-r", "name": "skipper-x", "status": "idle", "updatedAt": 2, "statusUpdatedAt": %d}' $SP "$(( $(now) * 1000 - 60000 ))" > "$T/sess/sk-r.json"
out=$(STALLS_NOW=$T9 SK ensure act); hasnt "$out" "stopped" "  9 h old, idle for a minute only: kept (mid-conversation)"
regi sk-r $SP idle
# a question relayed to another live session is that one's: no hold on the rotation
nap; OR=$NAP; regi other-r $OR busy
askev ro1 b1 docs/r.md#D2 other-r talk 60
out=$(STALLS_NOW=$T9 SK ensure act)
has "$out" "stopped skipper · dock (rotated: 9h old, quiet)" "  answered, idle 10 minutes, another session's question open: rotated, saying why"
check "$(lf ro1 holder)" "yard" "  its ship back to the yard, for the next start"
check "$(grep '20260110-000000-0001' "$S5/mgr/testhost-dock.starts.jsonl" | grep -c '"event": "failed"')" "0" "  a rotation is no failed start"
has "$(SK ensure dry)" "would start skipper · dock (ro1)" "  and the next pass starts a fresh one"
# the context rule: the last main-thread call's input, cache read and cache write; a synthetic entry after it is no call
rm -rf "$PLANS_DIR" "$S5/mgr/"*; : > "$S5/lc.calls"; rm -f "$S5/la/"* "$STALLS_STATE_DIR/skippers.json"
lay ro2 dock
nap; SP=$NAP
mkrec dock sk-c $SP "$(( $(now) - 3600 ))" 20260110-000000-0002; regi sk-c $SP idle
CLAUDE_CODE_SESSION_ID=sk-c HELM_HOLD_PARENT=$SP "$LX/helm" skipper --hold --scope dock --once > /dev/null
out=$(SK ensure act); hasnt "$out" "stopped" "1 h old, no transcript on this host: kept (age alone decides)"
mkdir -p "$T/projects/-x-dockrepo"
ctxline() { printf '{"type": "assistant", "isSidechain": %s, "message": {"model": "claude-opus-5-5", "usage": {"input_tokens": 5, "cache_read_input_tokens": %d, "cache_creation_input_tokens": 995}}}\n' "$1" "$2"; }
{ ctxline false 149000; ctxline true 300000; } > "$T/projects/-x-dockrepo/sk-c.jsonl"
out=$(SK ensure act); hasnt "$out" "stopped" "  150k tokens (a 300k sidechain after it): kept"
ctxline false 209000 >> "$T/projects/-x-dockrepo/sk-c.jsonl"
printf '{"type": "assistant", "message": {"model": "<synthetic>", "usage": {"input_tokens": 0, "output_tokens": 0}}}\n' >> "$T/projects/-x-dockrepo/sk-c.jsonl"
out=$(STALLS_NOW=$(( $(now) - 1200 )) SK ensure act); hasnt "$out" "stopped" "  210k tokens 40 minutes after its start: kept (under an hour: a fast-filling scope rotates at most hourly)"
out=$(SK ensure act)
has "$out" "stopped skipper · dock (rotated: its context 210k tokens, quiet)" "  210k tokens an hour in, a synthetic entry after it, idle: rotated"
check "$(lf ro2 holder)" "yard" "  its ship back to the yard"
check "$(grep '20260110-000000-0002' "$S5/mgr/testhost-dock.starts.jsonl" | grep -c '"event": "failed"')" "0" "  no failed start either"

echo "  deaf: a relay unanswered 15 minutes while the session sits idle"
rm -rf "$PLANS_DIR" "$S5/mgr/"*; : > "$S5/lc.calls"; rm -f "$S5/la/"* "$STALLS_STATE_DIR/skippers.json" "$S5/q/"*
lay df1 dock
nap; SP=$NAP
mkrec dock sk-5 $SP "$(now)" 20260107-000000-0001; regi sk-5 $SP idle
CLAUDE_CODE_SESSION_ID=sk-5 HELM_HOLD_PARENT=$SP "$LX/helm" skipper --hold --scope dock --once > /dev/null
g5=$(lf df1 gen)
# the holder took the ship 20 minutes ago
python3 - "$LP/df1" <<'PY'
import json, sys, time
d = sys.argv[1]; r = json.load(open(d + "/skipper.json")); r["since"] = time.time() - 1200
open(d + "/skipper.json", "w").write(json.dumps(r))
PY
# questions that never woke this holder are never its deafness: one relayed to another live session,
# one to a session on another Mac (its registry is not readable here: it may be live), and one this
# holder got only by the file road (it waits for a prompt an idle session never gets) — that one is
# re-hailed instead, and its queued re-hail is a try, never heard
nap; OT=$NAP; regi other-1 $OT busy
askev df1 b1 docs/q.md#D2 other-1 talk 960
askev df1 b1 docs/q.md#D5 far-1 talk 960 otherhost
askev df1 b1 docs/q.md#D3 sk-5 file 960
# nor the owner's: one answered already in its doc (keel's form or GitHub reach the doc, not the
# ship's events), one held in mode dnd (the board's owner column)
printf '# Doc\n\n**D6 — which?** Reversible: yes\n➤ Recommended: A\n➤ Answer:\nA, thanks\n' > "$S5/q6.md"
ASKEV_DOC="$S5/q6.md" askev df1 b1 docs/q6.md#D6 sk-5 talk 960
ASKEV_MODE=dnd askev df1 b1 docs/q.md#D8 sk-5 talk 960
check "$(SK open_refs df1)" "['docs/q.md#D2', 'docs/q.md#D3', 'docs/q.md#D5']" "the questions a skipper may answer: never one answered in its doc, nor one held in mode dnd"
out=$(SK ensure act); hasnt "$out" "deaf" "16 minutes idle on questions relayed elsewhere, queued, answered in the doc or held: not deaf"
hasnt "$out" "re-hailed df1 docs/q6.md#D6" "  the answered one is not re-hailed"
hasnt "$out" "re-hailed df1 docs/q.md#D2" "  the other live session's question is not re-hailed here"
hasnt "$out" "re-hailed df1 docs/q.md#D5" "  nor one relayed to a session on another Mac"
has "$out" "re-hailed df1 docs/q.md#D3 to skipper · dock at gen $g5: queued" "  the one it got only by the file road: re-hailed"
has "$(SK ensure act)" "re-hailed df1 docs/q.md#D3 to skipper · dock at gen $g5: queued" "  and again next pass: a queued re-hail is a try, not a delivery"
check "$(SK deaf df1)" "None" "  still not deaf: a queued line wakes nobody"
python3 - "$B" <<'PY'
import sys; sys.path.insert(0, sys.argv[1]); import helmlib
for d in ("D3", "D5"):
    helmlib.append_event("df1", {"task": "b1", "answered": "docs/q.md#" + d, "from": "skipper-dock", "plan": "df1"})
PY
# a question relayed by Talk in mode ask (the brief leaves it carded), the ship raised to default since:
# heard in an owner mode is not heard now — never deaf on it, re-hailed in the mode it is judged in
ASKEV_MODE=ask askev df1 b1 docs/q.md#D9 sk-5 talk 960
hasnt "$(SK open_refs df1)" "docs/q.md#D9" "a relay in mode ask: the owner's, not the skipper's"
"$HM" mode df1 default > /dev/null
has "$(SK open_refs df1)" "docs/q.md#D9" "  the ship raised to default: the skipper's"
check "$(SK deaf df1)" "None" "  never deaf on it: the holder heard it in mode ask, as one to leave carded"
has "$(SK ensure act)" "re-hailed df1 docs/q.md#D9 to skipper · dock at gen $g5" "  re-hailed instead"
has "$(grep 'q.md#D9\|D9 — ' "$S5/q/sk-5.jsonl")" "mode: default" "  tagged with the mode it is judged in"
python3 - "$B" "$LP/df1/plan.json" <<'PY'
import json, sys; sys.path.insert(0, sys.argv[1]); import helmlib
helmlib.append_event("df1", {"task": "b1", "answered": "docs/q.md#D9", "from": "skipper-dock", "plan": "df1"})
d = json.load(open(sys.argv[2])); d.pop("mode", None); open(sys.argv[2], "w").write(json.dumps(d))
PY
askev df1 b1 docs/q.md#D1 sk-5 talk 0
out=$(SK ensure act); hasnt "$out" "deaf" "a relay to the holder by Talk just sent: not deaf yet"
# the relay 16 minutes old
python3 - "$LP/df1" <<'PY'
import json, sys, time
d = sys.argv[1]; ls = [json.loads(x) for x in open(d + "/events.jsonl")]
for l in ls:
    if l.get("ask") == "docs/q.md#D1":
        l["t"] = time.time() - 960
open(d + "/events.jsonl", "w").write("".join(json.dumps(l) + "\n" for l in ls))
PY
regi sk-5 $SP busy
check "$(SK deaf df1)" "None" "  16 minutes, the session busy (working a turn): not deaf"
out=$(SK ensure act); hasnt "$out" "deaf" "  …and the pass hands nothing over"
regi sk-5 $SP idle
check "$(SK deaf df1)" "df1 docs/q.md#D1 unanswered 16m, the session idle" "  16 minutes, the session idle: deaf"
regi sk-5 $SP waiting
out=$(SK ensure act)
has "$out" "hand df1 to the yard: lapsed: deaf (df1 docs/q.md#D1 unanswered 16m, the session waiting)" \
  "  16 minutes stopped at a dialog (the registry's waiting): deaf too, never kept till 04:00"
check "$(lf df1 holder)/$(lf df1 gen)" "yard/$((g5 + 1))" "  the ship the yard's, gen + 1"
check "$(lev df1 'lease lapsed')" "1" "  one 'lease lapsed' event"
has "$out" "stopped skipper · dock (its lease was handed over)" "  and the deaf skipper stopped"
check "$(grep '20260107-000000-0001' "$S5/mgr/testhost-dock.starts.jsonl" | grep '"event": "failed"' | grep -c 'its lease was handed over, ')" "1" \
  "  a hand-over within 30 minutes of the start is a failed start: a skipper that never works its ships is no endless restart"

echo "  failover: a lapse handed to the yard, the next skipper re-hailed once per (question, gen)"
rm -rf "$S5/mgr/"*; : > "$S5/lc.calls"
nap; SP=$NAP
mkrec dock sk-6 $SP "$(now)" 20260108-000000-0001; regi sk-6 $SP busy
CLAUDE_CODE_SESSION_ID=sk-6 HELM_HOLD_PARENT=$SP "$LX/helm" skipper --hold --scope dock --once > /dev/null
g6=$(lf df1 gen)
check "$(lev df1 'taken by')" "1" "the next skipper takes it from the yard: 'taken by'"
out=$(SK ensure act)
has "$out" "re-hailed df1 docs/q.md#D1 to skipper · dock at gen $g6: queued" "  the open question, asked of the holder before, re-hailed to it"
has "$(cat "$S5/q/sk-6.jsonl")" "\"text\": \"ASK " "  as an ASK line (ask listen wakes on it)"
has "$(cat "$S5/q/sk-6.jsonl")" "D1 — which one — Reversible: yes — Recommended: A" "  the question as relay carries it"
has "$(cat "$S5/q/sk-6.jsonl")" "--task b1 --to-account /acct/run --space sp-run --plan df1" "  its reply keeps the relay's road back, fenced by the ship's lease (--plan)"
has "$(cat "$S5/q/sk-6.jsonl")" "answer /x/dockrepo/.claude/worktrees/q/docs/q.md D1" "  its reply names the doc where it is (the run's worktree, the relay's doc)"
hasnt "$out" "re-hailed df1 docs/q.md#D2" "  the question another live session holds: not re-hailed"
check "$(python3 -c 'import json, sys; print([(r["question"], r["gen"]) for r in json.load(open(sys.argv[1]))["relayed"] if r["gen"] == int(sys.argv[2])])' "$LP/df1/plan.json" "$g6")" \
  "[('docs/q.md#D1', $g6)]" "  keyed (question, gen) in the plan's relayed list"
has "$(SK ensure act)" "re-hailed df1 docs/q.md#D1" "  queued is a try: the next pass hails again (try 2)"
has "$(SK ensure act)" "re-hailed df1 docs/q.md#D1" "  (try 3)"
out=$(SK ensure act); hasnt "$out" "re-hailed" "  three tries per (question, gen), then nothing more"
# the lease lapses (its sidecar gone): handed to the yard, the skipper stopped
python3 - "$LP/df1/skipper.json" <<'PY'
import json, sys, time
p = sys.argv[1]; r = json.load(open(p)); r["until"] = time.time() - 5
open(p, "w").write(json.dumps(r))
PY
out=$(SK ensure act)
has "$out" "hand df1 to the yard: lease lapsed (gen $g6, sk-6)" "a lapsed lease: the pass hands it to the yard"
check "$(lf df1 holder)/$(lf df1 gen)" "yard/$((g6 + 1))" "  gen + 1, the yard's"
check "$(lev df1 'lease lapsed')" "2" "  one more 'lease lapsed' event"
has "$out" "stopped skipper · dock (its lease was handed over)" "  its skipper stopped"
nap; SP=$NAP
mkrec dock sk-7 $SP "$(now)" 20260108-000000-0002; regi sk-7 $SP busy
CLAUDE_CODE_SESSION_ID=sk-7 HELM_HOLD_PARENT=$SP "$LX/helm" skipper --hold --scope dock --once > /dev/null
check "$(lf df1 gen)" "$((g6 + 2))" "  the next skipper holds it at gen + 2"
out=$(SK ensure act)
has "$out" "re-hailed df1 docs/q.md#D1 to skipper · dock at gen $((g6 + 2))" "  and hears the open question again, at its own gen"
# S13a: a ship the yard holds that this healthy skipper's sidecar has not taken in 16 minutes — unless the brake froze it
lay df9 dock
python3 -c 'import json, sys, time; p = sys.argv[1]; r = json.load(open(p)); r["since"] = time.time() - 1000; open(p, "w").write(json.dumps(r))' "$LP/df9/skipper.json"
mkrec dock sk-7 $SP "$(( $(now) - 1000 ))" 20260108-000000-0002
has "$(SK ensure dry)" "would stop: its sidecar has taken df9 in 15m" "a yard-held ship its sidecar left 16 minutes: the skipper would be stopped"
bwin "$STALLS_STATE_DIR" $(( $(now) - 990 )) $(( $(now) - 30 ))
hasnt "$(SK ensure dry)" "its sidecar has taken" "  the same 16 minutes, all but 40 s of them under the studio brake: not stopped (S13a)"
rm -f "$STALLS_STATE_DIR/brake-windows.json"; rm -rf "$LP/df9"
mkrec dock sk-7 $SP "$(now)" 20260108-000000-0002
check "$(SK open df1)" "2" "the open questions a skipper may answer: listed (D1, D2)"
# an escalation is marked on the ask: a later report of the block's status never un-escalates it
out=$(CLAUDE_CODE_SESSION_ID=other-9 "$LX/helm" skipper --escalate df1 D1 2>&1); check "$?" "4" "--escalate from a session that holds no lease of the ship: fenced, exit 4"
CLAUDE_CODE_SESSION_ID=sk-7 "$LX/helm" skipper --escalate df1 docs/q.md#D1 > /dev/null; check "$?" "0" "  from the holder, by its full ref: exit 0"
"$HM" report df1 --task b1 --status running --progress "building on" > /dev/null
check "$(SK open df1)" "1" "  D1 escalated, then the block reported running: D1 stays the owner's"
# the tick's hand-backs are compare-and-swap: a ship moved since the pass read it is left as it is
check "$(python3 - "$B" <<'PY'
import sys; sys.path.insert(0, sys.argv[1]); import leaselib
r = leaselib.read("df1")
out = []
for args, kw in (((r["gen"] - 1, r["session"]), {}), ((r["gen"], "someone-else"), {}), ((r["gen"], r["session"]), {"only_lapsed": True})):
    try:
        leaselib.hand_back("df1", *args, why="the suite", **kw)
        out.append("moved")
    except leaselib.Refused:
        out.append("left")
print(out, leaselib.read("df1")["holder"])
PY
)" "['left', 'left', 'left'] skipper · dock" "hand_back: a stale gen, another session, a renewed lease asked as lapsed — each left as it is"
# skipper-modes S1: a task in mode ask is the owner's to answer — never re-hailed to a skipper, never its deafness
python3 - "$LP/df1/plan.json" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p)); d["tasks"]["b1"]["mode"] = "ask"; open(p, "w").write(json.dumps(d))
PY
check "$(SK open df1)" "0" "  its task in mode ask: not the skipper's (no re-hail, no deaf clock)"
kill $SLEEPS 2>/dev/null
unset PLANS_DIR ASK_MANAGER_DIR STALLS_STATE_DIR STALLS_LOG ASK_QUEUE_DIR ASK_NO_KEY_FILES HELM_LAUNCH_DIR HELM_LAUNCHCTL \
      HELM_SCREEN HELM_CLAUDE HELM_ACCOUNT HELM_DISPATCH_RC HELM_TRUST MEMO_SHEEP_BIN CLAUDE_REPOS_JSON HELM_SCREENDIR HELM_RC_HOSTS
export PLANS_DIR="$T/plans" PLAN_PROJECTS_ROOT="$T/projects-root"

echo "helm send (skipper-resilience S7): three ways in, the lay over ssh, the pickup, the listener, --line"
# A stub ssh (HARNESS_SSH) records its argv and runs the command here as the yard — `yardhost`, none of
# the caller's session environment (ssh carries none), its own config dir, whose `home` is a stand-in
# checkout: its wharf lays the ship into the scratch store as --yard would (the real lay is
# test_wharf.sh's), its helm is this module's. The origin is a bare repo; the scratch store is the
# yard's, read by the caller only through the stub. No real ssh, no real yard, no claude.
S7="$T/s7"; mkdir -p "$S7/bin" "$S7/yhome/modules/wharf-runs/bin" "$S7/yhome/modules/helm/libexec" "$S7/ycfg" "$S7/mgr" "$S7/send"
echo "$S7/yhome" > "$S7/ycfg/home"
echo yardhost:yard-alias >> "$REGATTA_CONFIG/wharf-runs/ssh"   # the yard's alias, as wharf apply --yard reads it
LP="$S7/plans"
export PLANS_DIR="$S7/plans" ASK_MANAGER_DIR="$S7/mgr" CLAUDE_REPOS_JSON="$S7/repos.json" HARNESS_SSH="$S7/bin/ssh" \
       HELM_SEND_DIR="$S7/send" HELM_SEND_POLL=0.2 HELM_SEND_WAIT=30 PICKUP_HOST=testhost \
       GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
cat > "$CLAUDE_REPOS_JSON" <<'EOF'
{"repos": {"sendrepo": {}, "nullrepo": {}, "loose": {}, "farrepo": {}},
 "scopes": {"dock": {"repos": ["sendrepo"], "yard": "yardhost"}, "nul": {"repos": ["nullrepo"], "yard": null},
            "far": {"repos": ["farrepo"], "yard": "farhost"}}}
EOF
cat > "$S7/bin/ssh" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >> "$S7/ssh.calls"
while [ \$# -gt 0 ]; do case "\$1" in -o) shift 2;; -*) shift;; *) break;; esac; done
shift   # the alias
exec env -u CLAUDE_CODE_SESSION_ID -u CLAUDE_UNATTENDED -u CLAUDE_CODE_DISABLE_BACKGROUND_TASKS -u DISPATCH_DEPTH -u SKIPPER_GEN \\
  REGATTA_CONFIG="$S7/ycfg" HARNESS_HOST=yardhost PLAN_HOST=yardhost sh -c "\$*"
EOF
printf '#!/bin/sh\n[ -n "${STUB_OLD_HELM:-}" ] && [ "$1" = send ] && { echo "helm: invalid choice: send" >&2; exit 2; }\nexec python3 "%s/helm" "$@"\n' "$LX" > "$S7/yhome/modules/helm/libexec/helm"
# the yard's wharf, standing in: its argv kept; the pin read from origin and its digest checked (as
# yard_compile does), the plan made with a task per block and the yard's lease at gen 0
cat > "$S7/yhome/modules/wharf-runs/bin/wharf" <<EOF
#!/usr/bin/env python3
import json, os, re, subprocess, sys
sys.path.insert(0, "$B")
a = sys.argv[1:]
open("$S7/wharf.calls", "a").write(json.dumps(a) + "\n")
if os.environ.get("STUB_LAY_RC"):
    print("wharf apply --yard: refused: the stub", file=sys.stderr); sys.exit(int(os.environ["STUB_LAY_RC"]))
pin, pid = json.loads(a[a.index("--pinned") + 1]), a[a.index("--plan") + 1]
text = subprocess.run(["git", "-C", "$S7/origin.git", "show", "%s:%s" % (pin["branch"], pin["rel"])], capture_output=True, text=True).stdout
import helmlib, leaselib
bl = str(helmlib.peer("blueprintlib.py").parent); sys.path.insert(0, bl)
import blueprintlib
bp = blueprintlib.load(pin["rel"], text=text, key=pin["repo"])
if blueprintlib.digest(bp) != pin["digest"]:
    print("wharf apply --yard: refused: digest", file=sys.stderr); sys.exit(2)
if helmlib.load_plan(pid) is None:
    subprocess.run(["$LX/helm", "ship", bp["name"], "--id", pid], check=True, stdout=subprocess.DEVNULL)
have = set(t["id"] for t in helmlib.state(pid)["tasks"])   # a rejoin adds the ship's new blocks
for s in bp["blocks"]:
    if s["id"] not in have:
        subprocess.run(["$LX/helm", "task", pid, s["id"], "--block", s["id"]], check=True, stdout=subprocess.DEVNULL)
if leaselib.read(pid) is None:
    leaselib.write_yard(pid, "dock", "yardhost", "laid by wharf apply --yard")
print("wharf apply --yard: %s pinned at %s into plan %s on yardhost" % (pin["rel"], pin["digest"][:12], pid))
if os.environ.get("STUB_APPLY_RC"):
    print("wharf apply: Orca is not running here", file=sys.stderr); sys.exit(int(os.environ["STUB_APPLY_RC"]))
EOF
chmod +x "$S7/bin/ssh" "$S7/yhome/modules/wharf-runs/bin/wharf" "$S7/yhome/modules/helm/libexec/helm"
gt() { git -C "$1" "${@:2}"; }
mkdir -p "$S7/seed/.claude"; git init -q -b main "$S7/seed"
echo '{"checkpoint": true}' > "$S7/seed/.claude/workflow.json"; printf '# sendrepo\n\n- physical: none\n' > "$S7/seed/AGENTS.md"
gt "$S7/seed" add -A; gt "$S7/seed" commit -qm init
git clone -q --bare "$S7/seed" "$S7/origin.git"
SR="$HOME/projects/sendrepo"; mkdir -p "$HOME/projects"; git clone -q "$S7/origin.git" "$SR" 2>/dev/null
BR=claude/testhost/2026-10-22-sendbp; WT="$SR/.claude/worktrees/sendbp"
gt "$SR" worktree add -q "$WT" -b "$BR"; mkdir -p "$WT/docs/blueprints"
brief7() { printf '## %s\nTask: build %s\nTier: worker\nWhy: the suite\nStart here: here\nDone means: done\nNot this: a landing\n' "$1" "$1"; }
sbp() { { printf -- '---\nship: %s\nrepo: %s\ncreated: 2026-10-22\n%bblocks:\n  - id: %s\n    depends_on: []\n    provider: claude-code\n---\n' "$1" "$2" "${3:-}" "${4:-work}"
          brief7 "${4:-work}"; } > "$WT/docs/blueprints/2026-10-22-$1.md"; echo "$WT/docs/blueprints/2026-10-22-$1.md"; }
P1=$(sbp sendone sendrepo 'skipper: sess-x\n'); P2=$(sbp sendtwo sendrepo); PL=$(sbp sendloose loose); PN=$(sbp sendnull nullrepo)
gt "$WT" add -A; gt "$WT" commit -qm blueprints; gt "$WT" push -q -u origin "$BR" 2>/dev/null
calls() { cat "$S7/ssh.calls" 2>/dev/null; }
pidof7() { python3 -c 'import json, sys; print(json.loads(sys.argv[1].splitlines()[-1])["plan"])' "$1"; }
sf() { python3 - "$B" "$@" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import helmlib
pid, task, key = sys.argv[2:5]
t = next(x for x in helmlib.state(pid)["tasks"] if x["id"] == task)
print(t.get(key))
PY
}

echo "  refused before anything is laid"
echo "local edit" >> "$P2"; gt "$WT" commit -qam "not pushed" > /dev/null
out=$("$LX/helm" send "$P2" 2>&1); check "$?" "2" "a committed blueprint not pushed: exit 2"
has "$out" "push it first: the yard reads origin/$BR:docs/blueprints/2026-10-22-sendtwo.md" "  push it first"
gt "$WT" reset -q --hard HEAD~1
out=$("$LX/helm" send "$PL" 2>&1); check "$?" "2" "a repo in no scope: exit 2"
has "$out" "loose is in no scope (scopes check)" "  says so"
out=$("$LX/helm" send "$PN" 2>&1); check "$?" "2" "a scope with yard null: exit 2"
has "$out" "scope nul has no yard (scopes set nul --yard HOST names one)" "  naming scopes set <s> --yard"
out=$("$LX/helm" send "$BR" --repo "$SR" 2>&1); check "$?" "2" "a branch with four blueprints: exit 2"
has "$out" "adds 4 blueprints (" "  counts them"
has "$out" "name the blueprint (--blueprint <path>)" "  name the blueprint"
mkdir -p "$S7/nullseed/.claude"; git init -q -b main "$S7/nullseed"; echo '{"checkpoint": true}' > "$S7/nullseed/.claude/workflow.json"
gt "$S7/nullseed" add -A; gt "$S7/nullseed" commit -qm init; git clone -q --bare "$S7/nullseed" "$S7/null.git"
git clone -q "$S7/null.git" "$HOME/projects/nullrepo" 2>/dev/null
out=$("$LX/helm" send --text "a task with nowhere to go" --repo "$HOME/projects/nullrepo" 2>&1); check "$?" "2" "--text into a scope with no yard: exit 2"
has "$out" "scope nul has no yard" "  refused"
check "$(gt "$HOME/projects/nullrepo" branch --list 'claude/*' | wc -l | tr -d ' ')" "0" "  before pickup seeds a branch"
check "$(calls | wc -l | tr -d ' ')" "0" "  no refusal reached the yard"
echo "  --text with a principal tier (principal tier S5): accepted, and never below its model or effort"
out=$("$LX/helm" send --text "a principal task" --repo "$SR" --tier principal-worker --effort high 2>&1); check "$?" "2" "--tier principal-worker --effort high: exit 2"
has "$out" "--tier principal-worker runs at xhigh (max only after a named miss): --effort high is below it" "  says the tier's effort"
out=$("$LX/helm" send --text "a principal task" --repo "$SR" --tier principal-architect --model opus 2>&1); check "$?" "2" "--tier principal-architect --model opus: exit 2"
has "$out" "--tier principal-architect runs on fable: --model opus would run it elsewhere" "  says the tier's model"
out=$("$LX/helm" send --text "a principal task" --repo "$SR" --tier principal-worker --effort max 2>&1); check "$?" "2" "--tier principal-worker --effort max on --text: exit 2"
has "$out" "--tier principal-worker runs at opus xhigh from its brief's Tier: line: give no --model or --effort" "  a --text run never carries the flag to its run, so it is refused, not dropped"
cat > "$S7/pickup-stub" <<'PY'
import sys
a = sys.argv
open(a[0] + ".brief", "w").write(open(a[a.index("--file") + 1]).read())
sys.exit(1)
PY
out=$(HELM_PICKUP="$S7/pickup-stub" "$LX/helm" send --text "a principal task" --repo "$SR" --tier principal-worker 2>&1)
has "$out" "pickup seed a-principal-task" "--tier principal-worker passes the tier check, on to pickup seed"
check "$(grep -c '^Tier: principal-worker$' "$S7/pickup-stub.brief")" "1" "  the brief's Tier: line names it, which dispatch reads"
check "$(gt "$SR" branch --list '*a-principal-task*' | wc -l | tr -d ' ')" "0" "  no branch was seeded by any of the three"
echo "  --text past pickup's brief cap (send-road-start): refused before anything is seeded"
rm -f "$S7/pickup-stub.brief"
long=$(python3 -c 'print("design " * 600)')
out=$(HELM_PICKUP="$S7/pickup-stub" "$LX/helm" send --text "$long" --topic too-long-brief --repo "$SR" 2>&1); check "$?" "2" "a --text brief over 4,000 characters: exit 2"
has "$out" "over pickup's cap of 60 lines or 4,000 characters, so no ship was laid" "  says the cap"
has "$out" "put the design in docs/ on a branch, and send a short --text that points at it" "  and where the design goes"
check "$([ -e "$S7/pickup-stub.brief" ] && echo called || echo none)" "none" "  pickup was never run"
check "$(gt "$SR" branch --list '*too-long-brief*' | wc -l | tr -d ' ')/$(calls | grep -c too-long-brief)" "0/0" "  no branch seeded, nothing reached the yard"
check "$(python3 - "$B" "$(peer pickup)" <<'PY'
import re, sys
sys.path.insert(0, sys.argv[1])
import sendlib
m = re.search(r"^BRIEF_LINES, BRIEF_CHARS = (\d+), (\d+)", open(sys.argv[2]).read(), re.M)
print(m and (int(m.group(1)), int(m.group(2))) == (sendlib.BRIEF_LINES, sendlib.BRIEF_CHARS))
PY
)" "True" "  sendlib's caps are pickup's own"

echo "  --text: pickup seed --no-start, the blueprint as sent, the lay over the alias"
out=$("$LX/helm" send --text "Fix the widget's frobnicator" --repo "$SR" --tier sr-worker --model opus --effort high --detach --json 2>"$S7/err"); rc=$?
check "$rc" "0" "--text --detach: exit 0"
TB="claude/testhost/$(date +%Y-%m-%d)-fix-the-widget-s-frobnicator"
has "$(cat "$S7/err")" "seeded $TB in sendrepo" "  seeded through pickup, the topic from the text"
TBP="docs/blueprints/$(date +%Y-%m-%d)-fix-the-widget-s-frobnicator.md"
check "$(gt "$S7/origin.git" show "$TB:docs/handoff/$(date +%Y-%m-%d)-fix-the-widget-s-frobnicator.md" | grep -c "^Task: Fix the widget's frobnicator$")" "1" "  the brief on origin has the Task line"
sent=$(gt "$S7/origin.git" show "$TB:$TBP")
has "$sent" $'\nskipper: scope\n' "  the blueprint on origin: skipper: scope"
has "$sent" 'sent_by: "mgr-1"' "  sent_by: this session"
has "$sent" $'    provider: claude-code\n    tier: sr-worker\n    model: opus\n    effort: high\n' "  the block's tier, model and effort from the flags"
check "$(gt "$S7/origin.git" log -1 --format=%s "$TB")" "Send: fix-the-widget-s-frobnicator to skipper · dock (helm send)" "  one Send: commit, pushed"
check "$(gt "$SR" rev-parse "$TB")" "$(gt "$S7/origin.git" rev-parse "$TB")" "  this Mac's branch moved with it"
has "$(calls)" "-o BatchMode=yes -o ConnectTimeout=10 yard-alias sh -s -- wharf apply --yard --pinned " "  wharf apply --yard over the yard's alias, with --pinned"
has "$(calls)" " --laid-by " "  and --laid-by"
TP=$(pidof7 "$out")
check "$(python3 -c 'import json, sys; print(json.loads(sys.argv[1].splitlines()[-1])["state"])' "$out")" "laid" "  --json: state laid"
check "$(python3 -c 'import json, sys; a = json.loads(open(sys.argv[1]).readline()); l = json.loads(a[a.index("--laid-by") + 1]); print(l["mode"], l["session"], l["host"])' "$S7/wharf.calls")" \
  "attended mgr-1 testhost" "  laid_by computed on the sender's Mac: attended, its session, its host"
has "$(python3 -c 'import json, sys; print(json.loads(sys.argv[1].splitlines()[-1])["line"])' "$out")" "LAID on yardhost, plan $TP, block fix-the-widget-s-frobnicator — pickup by the tick" "  the LAID line"
check "$(sf "$TP" fix-the-widget-s-frobnicator send)/$(sf "$TP" fix-the-widget-s-frobnicator sent_by)" "sent/mgr-1" "  the yard marked the task sent, by this session (helm send --mark over ssh)"
has "$(calls)" "sh -s -- helm send --mark $TP --by mgr-1 --from testhost" "  the mark ran over the alias"
has "$("$LX/helm" skipper --ships dock)" "sent, not picked up (fix-the-widget-s-frobnicator)" "  --ships: sent, not picked up"
check "$(SK needs "$TP")" "(True, [])" "  a ship with a task sent and not picked up needs a skipper"

echo "  a blueprint file: skipper rewritten, --no-merge through, the pickup"
: > "$S7/ssh.calls"
sleep 300 & SKP=$!; disown $SKP
regi sk-s7 $SKP busy
"$LX/helm" send "$P1" --no-merge --listen > "$S7/send1.out" 2>&1 & SEND=$!
for _ in $(seq 1 100); do grep -q "skipper --status" "$S7/ssh.calls" 2>/dev/null && break; sleep 0.1; done
CLAUDE_CODE_SESSION_ID=sk-s7 HELM_HOLD_PARENT=$SKP "$LX/helm" skipper --hold --scope dock --once > /dev/null
wait $SEND; check "$?" "0" "picked up: exit 0"
out=$(cat "$S7/send1.out")
has "$out" "skipper: sess-x rewritten to scope" "  a skipper naming a session is rewritten, said"
P1P=$(ls "$S7/send" | sed -n 's/^send-\(.*\)\.json$/\1/p' | while read -r p; do grep -q '"ship": "sendone"' "$S7/send/send-$p.json" && echo "$p"; done)
has "$out" "PICKED UP by skipper · dock on yardhost, plan $P1P, block work — this session may close" "  the PICKED UP line"
has "$out" "listen: run \`" "  --listen: the listener's line for the session"
has "$out" "send --listen $P1P work\` as a background shell" "    naming the plan and the block"
has "$(calls)" " --no-merge" "  --no-merge passed through to the lay"
check "$(grep -c '^skipper: scope$' "$P1")" "1" "  the worktree's file moved with the branch (ff)"
check "$(sf "$P1P" work send)/$(sf "$P1P" work picked_up_by)" "picked up/skipper · dock" "  the take wrote picked_up_at (leaselib.picked_up)"
check "$(sf "$TP" fix-the-widget-s-frobnicator send)" "picked up" "  the --text ship too: the skipper took every yard-held ship of dock"
check "$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["state"])' "$S7/send/send-$P1P.json")" "picked up" "  the send's record: picked up"

echo "  NOT PICKED UP, forced detach, a handoff branch"
P3=$(sbp sendthree sendrepo); gt "$WT" add -A; gt "$WT" commit -qm three; gt "$WT" push -q origin "$BR" 2>/dev/null
out=$(HELM_SEND_WAIT=1 "$LX/helm" send "$P3" 2>&1); rc=$?
check "$rc" "3" "no skipper in the wait: exit 3, never 1 (a crash's)"
has "$out" "NOT PICKED UP in 0 min — the yard holds it (gen 0); helm board on yardhost" "  the NOT PICKED UP line"
P3P=$(ls "$S7/send" | sed -n 's/^send-\(.*\)\.json$/\1/p' | while read -r p; do grep -q '"ship": "sendthree"' "$S7/send/send-$p.json" && echo "$p"; done)
check "$(lf "$P3P" holder)/$(lf "$P3P" gen)" "yard/0" "  the ship kept: the yard's, gen 0"
# (a heredoc, not -c "…": bash 3.2 brace-expands the dict literals' {a, b} inside "$(…)", AGENTS.md's trap)
check "$(python3 - "$B" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import sendlib
ship = dict(plan="p", gen=1, session="s", session_alive=False)
st = dict(scopes=[dict(holders=[dict(holder="skipper · dock", ships=[ship])])])
print(sendlib.picked(st, "p", "dock"), sendlib.picked(dict(scopes=[dict(holders=[dict(holder="skipper · dock", ships=[dict(ship, session_alive=True)])])]), "p", "dock"))
PY
)" "None s" "  a lease at gen 1 whose session is dead on the yard is no pickup; alive, it is"
P4=$(sbp sendfour sendrepo); gt "$WT" add -A; gt "$WT" commit -qm four; gt "$WT" push -q origin "$BR" 2>/dev/null
: > "$S7/wharf.calls"
out=$(CLAUDE_UNATTENDED=1 "$LX/helm" send "$P4" --listen 2>&1); check "$?" "0" "--listen under CLAUDE_UNATTENDED: --detach taken, exit 0"
has "$out" "a dispatched run cannot listen (CLAUDE_UNATTENDED is set); sent with --detach" "  saying so"
has "$out" "LAID on yardhost" "  returned at the first safe point"
check "$(python3 -c 'import json, sys; a = json.loads(open(sys.argv[1]).readline()); print(json.loads(a[a.index("--laid-by") + 1])["mode"])' "$S7/wharf.calls")" "unattended" "  laid_by unattended: the ship never merges by its word"
out=$(CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1 "$LX/helm" send --listen "$P1P" work 2>&1); check "$?" "2" "the listener with background tasks off: refused, exit 2"
has "$out" "a dispatched run cannot listen" "  saying so"
printf 'Task: a handoff\nTier: worker\nWhy: w\nStart here: s\nDone means: d\nNot this: n\n' > "$S7/hb.md"
( cd "$SR" && env -u CLAUDE_CODE_SESSION_ID python3 "$(peer pickup)" seed handed-off --file "$S7/hb.md" --no-start > /dev/null 2>&1 )
HB="claude/testhost/$(date +%Y-%m-%d)-handed-off"
out=$( cd "$SR" && "$LX/helm" send "$HB" --detach 2>&1 ); check "$?" "0" "a handoff branch (/todo handoff --send): exit 0"
has "$out" "LAID on yardhost" "  laid"
has "$(gt "$S7/origin.git" show "$HB:docs/blueprints/$(date +%Y-%m-%d)-handed-off.md")" $'\nskipper: scope\n' "  its one blueprint found and sent"
out=$(STUB_LAY_RC=4 "$LX/helm" send "$HB" --repo "$SR" --detach 2>&1); check "$?" "5" "a lay that left nothing on the yard: exit 5, never 1 or 4"
has "$out" "NOT LAID on yardhost: wharf apply --yard exit 4" "  NOT LAID"
has "$out" "rejoins it if it went through after all" "  naming the plan to rejoin"
P5=$(sbp sendfive sendrepo); gt "$WT" add -A; gt "$WT" commit -qm five; gt "$WT" push -q origin "$BR" 2>/dev/null
out=$(STUB_APPLY_RC=3 "$LX/helm" send "$P5" --detach 2>&1); check "$?" "0" "a lay whose first apply fails after the plan is saved: laid, exit 0"
has "$out" "LAID on yardhost" "  LAID"
has "$out" "(its first apply exited 3)" "  saying how its first apply ended"
P5P=$(ls "$S7/send" | sed -n 's/^send-\(.*\)\.json$/\1/p' | while read -r p; do grep -q '"ship": "sendfive"' "$S7/send/send-$p.json" && echo "$p"; done)
check "$(sf "$P5P" work send)" "sent" "  recorded and marked as any laid send"
P6=$(sbp sendsix sendrepo); gt "$WT" add -A; gt "$WT" commit -qm six; gt "$WT" push -q origin "$BR" 2>/dev/null
out=$(STUB_OLD_HELM=1 "$LX/helm" send "$P6" --detach 2>&1); check "$?" "5" "a yard whose helm has no send: refused, exit 5"
has "$out" "the yard yardhost's helm has no \`helm send\`" "  saying so"
has "$out" "pull regatta there first" "  and the fix"
check "$(gt "$S7/origin.git" show "$BR:docs/blueprints/2026-10-22-sendsix.md" | grep -c '^skipper: scope$')" "0" "  before the blueprint is rewritten or pushed"
git init -q -b main "$HOME/projects/farrepo"
out=$("$LX/helm" send --text "a task for a yard with no alias" --repo "$HOME/projects/farrepo" 2>&1); check "$?" "2" "--text to a yard this Mac has no alias for: exit 2"
has "$out" "scope far's yard farhost has no ssh alias here" "  refused"
check "$(gt "$HOME/projects/farrepo" branch --list 'claude/*' | wc -l | tr -d ' ')" "0" "  before pickup seeds a branch"
"$HM" task "$P3P" extra > /dev/null
u0=$(sf "$P3P" work updated)
out=$(CLAUDE_CODE_SESSION_ID= "$LX/helm" send --mark "$P3P" --by s-9 --block work); check "$?" "0" "--mark --block: exit 0"
check "$(sf "$P3P" work sent_by)/$(sf "$P3P" extra sent_by)" "s-9/None" "  only the sent ship's block is marked"
check "$(sf "$P3P" work updated)" "$u0" "  a mark is no news of the task's own (its updated stays)"
out=$(CLAUDE_CODE_SESSION_ID= "$LX/helm" send --mark "$P3P" --by s-9 --block nosuch 2>&1); check "$?" "3" "--mark with no open block to mark: exit 3, so the sender warns"
has "$out" "no open block to mark named nosuch" "  saying so"
out=$(STUB_APPLY_RC=3 "$LX/helm" send "$P5" --plan "$P5P" --detach 2>&1); check "$?" "5" "a failed lay into a rejoined plan: NOT LAID, exit 5 (the plan was there before)"
has "$out" "NOT LAID on yardhost: wharf apply --yard exit 3" "  NOT LAID"
P8=$(sbp sendeight sendrepo '' eight); gt "$WT" add -A; gt "$WT" commit -qm eight; gt "$WT" push -q origin "$BR" 2>/dev/null
out=$(STUB_APPLY_RC=3 "$LX/helm" send "$P8" --plan "$P5P" --detach --lay-timeout 30 2>&1); check "$?" "0" "a rejoin that adds a new ship, its first apply failed: LAID, exit 0 (its blocks are new there)"
has "$out" "LAID on yardhost, plan $P5P, block eight" "  LAID, its block named"
has "$(tail -1 "$S7/wharf.calls")" "--plan" "  the lay ran (--lay-timeout taken)"
out=$("$LX/helm" send "$P5" --plan 'a b' --detach 2>&1); check "$?" "2" "a bad --plan: refused, exit 2, before anything is committed"
check "$(python3 - "$B" "$P1P" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import helmlib
t = helmlib.public(helmlib.state(sys.argv[2]))["tasks"][0]
print(sorted(k for k in ("sent_by", "sent_from", "picked_up_by") if k in t), t["send"], bool(t["picked_up_at"]))
PY
)" "[] picked up True" "K6: the public copy drops the sender, its host and the lease holder; keeps send and its times"

echo "  the line (helm skipper --line), the listener, --release"
L=$("$LX/helm" skipper --line "$P1P" work)
check "$L" "sendone/work: planned, worker not started; 0 questions open; lease gen 1 held by skipper · dock" "--line: a block not started"
check "$("$LX/helm" skipper --line "$P3P" work)" "sendthree/work: planned, sent, not picked up, worker not started; 0 questions open; lease gen 0 held by yard" "  sent, not picked up, the yard's"
nap; WK=$NAP; regi wk-1 $WK busy
"$HM" report "$P1P" --task work --status running --session wk-1 > /dev/null
check "$("$LX/helm" skipper --line "$P1P" work)" "sendone/work: running, worker alive 0 min; 0 questions open; lease gen 1 held by skipper · dock" "  building: the worker alive"
"$HM" report "$P1P" --task work --status relayed --ask docs/q.md#D1 --summary "which" --session wk-1 > /dev/null   # the worker asks
has "$("$LX/helm" skipper --line "$P1P" work)" "relayed, worker alive 0 min; 1 question open, with skipper · dock;" "  a question open, with the holder"
check "$("$LX/helm" skipper --line nosuch 2>&1; echo "rc=$?")" "helm skipper --line: no ship nosuch here
rc=1" "  no such ship: exit 1"
sleep 300 & LPAR=$!; disown $LPAR
out=$(HELM_LISTEN_PARENT=$LPAR "$LX/helm" send --listen "$P1P" work --every 0.005); check "$?" "0" "the listener: one pull, exit 0"
has "$out" "sendone/work: relayed, worker alive" "  prints the yard's line"
has "$(calls)" "sh -s -- helm skipper --line $P1P work" "  pulled over the alias"
out=$(HELM_LISTEN_PARENT=$LPAR "$LX/helm" send --listen "$P1P" nosuch --every 0.005); check "$?" "0" "the listener on a block the yard lacks: exit 0"
has "$out" "ended: helm skipper --line: ship $P1P has no block nosuch" "  ended, not 'the next pull'"
check "$(ls "$S7/send" | grep -c '\.pid$')" "0" "  its pid file gone with it"
python3 - "$B" "$P1P" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import helmlib
helmlib.append_event(sys.argv[2], {"task": "work", "status": "launched", "pr": "https://example.invalid/o/r/pull/12"})
PY
out=$(HELM_LISTEN_PARENT=$LPAR "$LX/helm" send --listen "$P1P" work --every 0.005)
has "$out" "sendone/work: ended: launched #12" "  ended: launched #N"
has "$out" "listener: ended — nothing more to pull" "  the listener says it stops"
check "$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["state"])' "$S7/send/send-$P1P.json")" "ended" "  the record: ended"
"$HM" report "$P3P" --task work --status waiting --ask docs/q.md#D2 --summary "which" --session wk-1 > /dev/null
CLAUDE_CODE_SESSION_ID= "$LX/helm" skipper --escalate "$P3P" D2 > /dev/null   # the yard holds it: a plain shell passes the fence
has "$("$LX/helm" skipper --line "$P3P")" "sendthree/work: ended: raised to " "  raised to the owner"
has "$("$LX/helm" skipper --line "$P3P")" " (holds docs/q.md#D2)" "    with its class: the question the owner holds (helm skipper --escalate)"
HELM_LISTEN_PARENT=$LPAR "$LX/helm" send --listen "$TP" --every 5 > "$S7/l.out" 2>&1 & LIS=$!
for _ in $(seq 1 50); do [ -e "$S7/send/send-$TP-fix-the-widget-s-frobnicator.pid" ] && break; sleep 0.1; done
check "$(head -1 "$S7/send/send-$TP-fix-the-widget-s-frobnicator.pid")" "$LIS" "a listener writes its pid file, send-<plan>-<block>.pid"
out=$("$LX/helm" send --status); has "$out" "$TP  fix-the-widget-s-frobnicator/fix-the-widget-s-frobnicator  laid  on yardhost (skipper · dock)  listener $LIS" "--status: this session's sends, the listener's pid"
out=$("$LX/helm" send --release "$TP"); has "$out" "released $TP-fix-the-widget-s-frobnicator (pid $LIS)" "--release: killed by its pid file"
for _ in $(seq 1 20); do kill -0 $LIS 2>/dev/null || break; sleep 0.1; done
check "$(kill -0 $LIS 2>/dev/null && echo alive || echo gone)" "gone" "  the listener is gone"
check "$([ -e "$S7/send/send-$TP-fix-the-widget-s-frobnicator.pid" ] && echo kept || echo removed)" "removed" "  and its pid file"
sleep 300 & LP2=$!; disown $LP2
HELM_LISTEN_PARENT=$LP2 "$LX/helm" send --listen "$TP" --every 5 > "$S7/l2.out" 2>&1 & LIS=$!
until_ "[ \"\$(head -1 '$S7/send/send-$TP-fix-the-widget-s-frobnicator.pid' 2>/dev/null)\" = $LIS ]"; kill $LP2   # the listener up (its pid file) before its parent ends
for _ in $(seq 1 30); do kill -0 $LIS 2>/dev/null || break; sleep 0.1; done
check "$(kill -0 $LIS 2>/dev/null && echo alive || echo gone)" "gone" "a listener ends with its session's claude"
has "$(cat "$S7/l2.out")" "has ended — the listener with it" "  saying so"
kill $LIS 2>/dev/null

echo "  the fence: --mark on the yard by a session that does not hold the lease"
out=$(CLAUDE_CODE_SESSION_ID=other-7 "$LX/helm" send --mark "$P1P" --by x 2>&1); check "$?" "4" "--mark from another session: exit 4"
has "$out" "refused: lease at gen 1 held by skipper · dock — you are gen none" "  the lease's refusal line"
check "$(lev "$P1P" refused | tr -d ' ')" "1" "  one 'refused' event, verb helm send"
P7=$(sbp sendseven sendrepo); gt "$WT" add -A; gt "$WT" commit -qm seven; gt "$WT" push -q origin "$BR" 2>/dev/null
w0=$(gt "$WT" rev-parse HEAD)
out=$( cd "$SR" && "$LX/helm" send "$BR" --blueprint "${P7#"$WT/"}" --detach 2>&1 ); check "$?" "0" "a branch another worktree holds, sent by name from elsewhere: exit 0"
has "$out" "/.claude/worktrees/sendbp pull --ff-only\` there brings" "  its worktree named, never moved (git's own path: /private on macOS)"
check "$(gt "$WT" rev-parse HEAD)" "$w0" "  that worktree's HEAD untouched (one writer per worktree)"
echo "  a confidential scope's yard (node-road): its node folder's own ssh, never wharf-runs/ssh"
# vaultbox's node folder names its alias; wharf-runs/ssh names the node too (orca-host's check faults that
# row on a real Mac), so a case that took it would dial wrong-alias. The stub ssh records which alias it got.
cat > "$S7/reg.py" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["repos"].update({"vaultrepo": {}, "vault2repo": {}, "openrepo": {}})
d["scopes"].update({"vault": {"repos": ["vaultrepo"], "yard": "vaultbox-agent", "confidential": True},
                    "vault2": {"repos": ["vault2repo"], "yard": "yardhost", "confidential": True},
                    "opennode": {"repos": ["openrepo"], "yard": "vaultbox-agent"},
                    "vault3": {"repos": ["secret*", sys.argv[2]], "confidential": True},
                    "opencase": {"repos": ["caserepo"], "yard": "vaultbox-Agent"}})
json.dump(d, open(sys.argv[1], "w"))
PY
cp "$CLAUDE_REPOS_JSON" "$S7/repos.keep"; python3 "$S7/reg.py" "$CLAUDE_REPOS_JSON" "$S7/absrepo"
NF="$REGATTA_CONFIG/wharf-runs/nodes"; mkdir -p "$NF/vaultbox"; echo vault-alias > "$NF/vaultbox/ssh"
cp "$REGATTA_CONFIG/wharf-runs/ssh" "$S7/ssh.keep"; echo vaultbox-agent:wrong-alias >> "$REGATTA_CONFIG/wharf-runs/ssh"
cat > "$S7/dest.py" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import sendlib
bl = sendlib.blueprintlib()
try:
    print("ok", sendlib.destination(bl, sys.argv[2])[3])
except sendlib.Refused as e:
    print("refused", e)
PY
cat > "$S7/argv.py" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import sendlib
print(" ".join(sendlib.ssh_argv("a", "c")))
PY
dest() { python3 "$S7/dest.py" "$B" "$1" 2>&1; }
: > "$S7/ssh.calls"
check "$(dest vaultrepo)" "ok vault-alias" "a confidential scope's yard: the node folder's ssh"
has "$(calls)" "vault-alias sh -s -- helm send --status --json" "  the yard's check went over it"
check "$(calls | grep -c wrong-alias)" "0" "  never over the wharf-runs/ssh row that names the node"
check "$(dest openrepo)" "ok vault-alias" "an open scope whose yard is a node's peer: the node folder's ssh too (orca-host's reach)"
: > "$S7/ssh.calls"
out=$(dest vault2repo); has "$out" "refused scope vault2 is confidential: its yard yardhost is reached only by a node folder's own ssh" "a confidential yard no node folder names: refused"
has "$out" "never wharf-runs/ssh" "  though wharf-runs/ssh names that yard"
check "$(calls | wc -l | tr -d ' ')" "0" "  nothing reached any yard"
rm "$NF/vaultbox/ssh"
out=$(dest vaultrepo); has "$out" "is the node vaultbox, whose folder names no ssh (wharf-runs/nodes/vaultbox/ssh" "a node folder with no ssh: refused, naming the key"
echo vault-alias > "$NF/vaultbox/ssh"; echo not-a-folder > "$NF/torn"
out=$(dest vaultrepo); has "$out" "refused scope vault's yard vaultbox-agent: the node folders do not read (" "a torn nodes folder: a confidential yard is refused"
check "$(dest sendrepo)" "ok yard-alias" "  an open scope's Mac yard keeps wharf-runs/ssh"
rm "$NF/torn"
cat > "$S7/ya.py" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import sendlib
scope, yard, key, absent = sys.argv[2], sys.argv[3], sys.argv[4] or None, sys.argv[5] == "absent"
if absent:
    sendlib.orca_host = lambda: None
try:
    print("ok", sendlib.yard_alias(scope, yard, key))
except sendlib.Refused as e:
    print("refused", e)
PY
ya() { python3 "$S7/ya.py" "$B" "$1" "$2" "${3:-}" "${4:-}" 2>&1; }
has "$(ya vault2 yardhost)" "refused scope vault2 is confidential" "yard_alias, one registry read: a confidential scope by name"
has "$(ya dock yardhost vault2repo)" "refused scope dock's send of vault2repo (a confidential scope holds it) is confidential" "  a repo a confidential scope holds, sent under an open scope's name: confidential too (every scope walked)"
check "$(ya dock yardhost sendrepo)" "ok yard-alias" "  an open repo under an open scope: as before"
has "$(ya vault otherhost)" "refused scope vault's yard read otherhost, and the registry now says vaultbox-agent: it moved under the send" \
    "  a yard the registry no longer names for the scope: refused, never judged against another read"
has "$(ya opennode vaultbox-agent '' absent)" "could be a node's, and wharf-runs' orca-host is not here" "  orca-host absent: an -agent yard is refused, even an open scope's"
check "$(ya dock yardhost '' absent)" "ok yard-alias" "  orca-host absent: a Mac yard is not a node's, and never loads it"
has "$(ya dock yardhost secretx)" "(a confidential scope holds it) is confidential" "  a confidential scope's glob over a key the registry lacks: confidential (the core's entry_takes)"
has "$(ya dock yardhost "$S7/absrepo")" "(a confidential scope holds it) is confidential" "  a confidential scope's absolute entry: confidential (the core's entry_takes)"
check "$(ya opencase vaultbox-Agent)" "ok vault-alias" "  an -Agent yard in another case: still a node's peer, the node folder's ssh (never wharf-runs/ssh's row)"
out=$(HELM_SEND_DIR=/dev/null/send dest sendrepo); has "$out" "refused the send dir /dev/null/send takes no file" "a send dir that takes no file: refused before anything is seeded"
: > "$S7/ssh.calls"
printf '{"plan": "plan-rec", "ship": "s", "blocks": ["b"], "scope": "vault", "yard": "vaultbox-agent", "alias": "stale-alias"}\n' > "$S7/send/send-plan-rec.json"
"$LX/helm" send --listen plan-rec --every 0 > /dev/null 2>&1
check "$(calls | grep -c 'vault-alias sh -s -- helm skipper --line plan-rec')/$(calls | grep -c stale-alias)" "1/0" \
      "--listen judges a recorded send's alias again: the node folder's, never the one the record kept"
printf '{"plan": "plan-rk", "ship": "s", "blocks": ["b"], "scope": "dock", "yard": "yardhost", "alias": "yard-alias", "repo": "vault2repo"}\n' > "$S7/send/send-plan-rk.json"
out=$("$LX/helm" send --listen plan-rk --every 0 2>&1); check "$?" "2" "--listen of a recorded send whose repo a confidential scope holds: refused (the record's repo judged)"
has "$out" "vault2repo (a confidential scope holds it) is confidential" "  saying why"
check "$(calls | grep -c plan-rk)" "0" "  and never dialed the alias the record kept"
printf '{"plan": "plan-mv", "ship": "s", "blocks": ["b"], "scope": "vault", "yard": "oldbox-agent", "alias": "x", "repo": "vaultrepo"}\n' > "$S7/send/send-plan-mv.json"
mkdir -p "$NF/oldbox"; echo old-alias > "$NF/oldbox/ssh"
"$LX/helm" send --listen plan-mv --every 0 > /dev/null 2>&1; check "$?" "0" "--listen of a ship laid before its scope's yard moved: still pulled"
check "$(calls | grep -c 'old-alias sh -s -- helm skipper --line plan-mv')" "1" "  from the yard it was laid on, by that node's folder"
printf '{"plan": "plan-na", "ship": "s", "blocks": ["b"], "alias": "hand-alias"}\n' > "$S7/send/send-plan-na.json"
"$LX/helm" send --listen plan-na --scope vault --every 0 > /dev/null 2>&1
check "$(calls | grep -c hand-alias)/$(calls | grep -c 'vault-alias sh -s -- helm skipper --line plan-na')" "0/1" "  a record's alias with no scope or yard: judged by --scope, never dialed as written"
printf '{"plan": "plan-rn", "ship": "s", "blocks": ["b"], "repo": "vault2repo"}\n' > "$S7/send/send-plan-rn.json"
out=$("$LX/helm" send --listen plan-rn --scope dock --every 0 2>&1); check "$?" "2" "  a record with its repo and no scope or yard, judged by an open --scope: the record's repo still judged, refused"
check "$(calls | grep -c plan-rn)" "0" "  and nothing dialed"
printf '{"plan": "plan-ns", "ship": "s", "blocks": ["b"], "scope": {}, "yard": ["x"], "alias": "ns-alias"}\n' > "$S7/send/send-plan-ns.json"
out=$("$LX/helm" send --listen plan-ns --every 0 2>&1); check "$?" "2" "  a record whose scope or yard is no string: no crash, judged as one with none (refused: no --scope)"
has "$out" "name its scope with --scope" "    saying what to do"
printf '{\n' > "$S7/torn-reg.json"
out=$(CLAUDE_REPOS_JSON="$S7/torn-reg.json" "$LX/helm" send --listen plan-na --scope vault --every 0 2>&1); check "$?" "2" "  --scope on a torn registry: refused"
has "$out" "does not read: no scope's yard can be told" "    as torn, never \"scope vault has no yard\""
echo "  the sandboxed sender: \$GIT_SSH_COMMAND, run as git runs it, when SRT_SSH_PROXY_COMMAND is set"
: > "$S7/ssh.calls"
out=$(env -u HARNESS_SSH SRT_SSH_PROXY_COMMAND="the-proxy %h %p" GIT_SSH_COMMAND="$S7/bin/ssh -o ProxyCommand=\"\$SRT_SSH_PROXY_COMMAND\"" \
      "$LX/helm" send --listen plan-vault --scope vault --every 0 2>&1); check "$?" "0" "--listen to the confidential yard from a sandbox: exit 0"
has "$(calls)" "-o ProxyCommand=the-proxy %h %p -o BatchMode=yes -o ConnectTimeout=10 vault-alias sh -s -- helm skipper --line plan-vault" \
    "  the pull went by git's ssh, its ProxyCommand through the sandbox's proxy, to the node folder's alias"
has "$out" "plan-vault: ended: " "  and the yard answered (no such ship there)"
check "$(SRT_SSH_PROXY_COMMAND=x GIT_SSH_COMMAND=gitssh python3 "$S7/argv.py" "$B" | cut -d' ' -f1)" "$S7/bin/ssh" "  HARNESS_SSH still stands in first, sandbox or not"
out=$(env -u HARNESS_SSH -u GIT_SSH_COMMAND SRT_SSH_PROXY_COMMAND="the-proxy %h %p" "$LX/helm" send --listen plan-vault --scope vault --every 0 2>&1)
has "$out" "with no GIT_SSH_COMMAND: plain ssh is refused there" "  a sandbox with no GIT_SSH_COMMAND: refused, and plain ssh never tried"
check "$(env -u HARNESS_SSH -u GIT_SSH_COMMAND SRT_SSH_PROXY_COMMAND=x HELM_LISTEN_PARENT=$$ "$LX/helm" send --listen plan-vault --scope vault --every 5 > /dev/null 2>&1; echo $?)" "2" \
      "  at once, exit 2, never a pull that waits --every minutes and comes back for ever"
check "$(env -u HARNESS_SSH GIT_SSH_COMMAND=gitssh python3 "$S7/argv.py" "$B")" "ssh -o BatchMode=yes -o ConnectTimeout=10 a c" \
      "  no sandbox (SRT_SSH_PROXY_COMMAND unset): plain ssh, GIT_SSH_COMMAND or not"
check "$(grep -c '<<' "$B/sendlib.py")" "0" "  sendlib runs no shell heredoc on the send path"
cp "$S7/ssh.keep" "$REGATTA_CONFIG/wharf-runs/ssh"; cp "$S7/repos.keep" "$CLAUDE_REPOS_JSON"; rm_own "$NF"
echo "  the yard's launcher on a Linux node (node-road): the skipper and the ask poll load by systemd-launchctl"
cat > "$S7/lc.py" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import skipperlib
lc = skipperlib.launchctl()
print("launchctl" if lc == "launchctl" else lc.rsplit("/", 1)[-1])
PY
want=systemd-launchctl; [ "$(uname -s)" = Darwin ] && want=launchctl   # never `$(case …)`: bash 3.2 cuts it at `)`
check "$(env -u HELM_LAUNCHCTL python3 "$S7/lc.py" "$B")" "$want" \
      "skipperlib's launchctl: launchd's on a Mac, wharf-runs' systemd-launchctl elsewhere"
check "$(HELM_LAUNCHCTL=/x/stub python3 "$S7/lc.py" "$B")" "stub" "  HELM_LAUNCHCTL first"
check "$(grep -c 'Darwin) dlc=launchctl' "$B/../install.sh")" "1" "  install.sh picks the same way for the ask poll"
kill $SKP $WK $LPAR $SLEEPS 2>/dev/null
unset PLANS_DIR ASK_MANAGER_DIR CLAUDE_REPOS_JSON HARNESS_SSH HELM_SEND_DIR HELM_SEND_POLL HELM_SEND_WAIT \
      PICKUP_HOST GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
export PLANS_DIR="$T/plans"

echo "the stall road (skipper-resilience S8): the yard's tick, escalations.jsonl, the github-issue road"
# A stub GitHub API (ASK_GH_API, called as \`gh api\` is) records each call and numbers the issues from
# 100; the yard is this host (testhost) by the registry's one scope; the config dir is two copies of
# the suite's own, one with synthetic helm/logbook-repo and helm/mention values. A fresh store, HOME
# (no run records) and logs. No network, no real issue, no skipper or wharf pass.
S8="$T/s8"; mkdir -p "$S8/home" "$S8/st"
cp -R "$REGATTA_CONFIG" "$S8/cfg"; cp -R "$REGATTA_CONFIG" "$S8/cfg0"; mkdir -p "$S8/cfg/helm"
# the fixture's one peer, as the suite began: S7's block above adds its yard's alias to the suite's copy
for c in cfg cfg0; do echo buildbox:buildbox-ssh > "$S8/$c/wharf-runs/ssh"; done
echo "owner-x/logbook-x" > "$S8/cfg/helm/logbook-repo"; echo "@someone-x" > "$S8/cfg/helm/mention"
cat > "$S8/gh" <<'PY'
#!/usr/bin/env python3
import json, os, sys
i = sys.argv.index("--method")
method, path = sys.argv[i + 1], sys.argv[i + 2]
body = json.load(sys.stdin)
calls = os.environ["GH_CALLS"]
n = sum(1 for _ in open(calls)) if os.path.exists(calls) else 0
open(calls, "a").write(json.dumps({"method": method, "path": path, "body": body}) + "\n")
import re
if os.environ.get("GH_FAIL") or (os.environ.get("GH_FAIL_MATCH") and re.search(os.environ["GH_FAIL_MATCH"], method + " " + path)):
    print("gh: HTTP 401: Bad credentials", file=sys.stderr); sys.exit(1)
print(json.dumps({"number": 100 + n} if method == "POST" and path.endswith("/issues") else {}))
PY
chmod +x "$S8/gh"
echo '{"notify": {"testhost": ["github-issue"]}, "ask": {"parked": true}}' > "$S8/surfaces.json"
cat > "$S8/repos.json" <<'EOF'
{"repos": {"dockrepo": {}}, "scopes": {"dock": {"repos": ["dockrepo"], "yard": "testhost"}}}
EOF
echo '{"repos": {"dockrepo": {}}, "scopes": {"dock": {"repos": ["dockrepo"]}}}' > "$S8/noyard.json"
printf '{"repos": {"dockrepo": {}}, "scopes": {"dock": ' > "$S8/torn.json"   # a write cut off mid-object
export PLANS_DIR="$S8/plans" STALLS_LOG="$S8/stalls.jsonl" STALLS_STATE_DIR="$S8/st" CLAUDE_REPOS_JSON="$S8/repos.json" \
       ASK_GH_API="$S8/gh" GH_CALLS="$S8/gh.calls" SURFACES_FILE="$S8/surfaces.json" SURFACES_HOST=testhost \
       STALLS_PEERS= STALLS_REPOS= PLAN_NO_SKIPPERS=1 PLAN_NO_WHARF=1
LP="$PLANS_DIR"; E8="$S8/escalations.jsonl"
# launchd's tick, armed past its dry hours: no session, nothing unattended (the road acts only so)
mkdir -p "$S8/st"; echo '{"by": "suite", "ts": "x", "t": 0}' > "$S8/st/armed"
TK() { local at=$1; shift; env -u CLAUDE_CODE_SESSION_ID -u CLAUDE_UNATTENDED HOME="$S8/home" REGATTA_CONFIG="${CFG8:-$S8/cfg}" STALLS_NOW="$at" "$LX/helm" tick "$@" 2>&1; }
ncalls() { [ -e "$GH_CALLS" ] && wc -l < "$GH_CALLS" | tr -d ' ' || echo 0; }
call8() { python3 - "$GH_CALLS" "$1" "$2" <<'PY'
import json, sys
c = [json.loads(x) for x in open(sys.argv[1])][int(sys.argv[2])]
print(eval(sys.argv[3], {"c": c, "b": c["body"]}))
PY
}
erow() { python3 - "$E8" "$1" "$2" <<'PY'
import json, sys
r = [json.loads(x) for x in open(sys.argv[1])][int(sys.argv[2])]
print(eval(sys.argv[3], {"r": r}))
PY
}
nrows() { [ -e "$E8" ] && wc -l < "$E8" | tr -d ' ' || echo 0; }
# an S7 (raised to the owner: its skipper is not live): b waits on a, done two hours ago, nobody started b
s7ship() { "$HM" $SHIP "$1" --id "$1" ${2:+--repo "$2"} > /dev/null; "$HM" task "$1" a > /dev/null; "$HM" task "$1" b > /dev/null
           "$HM" dep "$1" b --on a > /dev/null; PLAN_NO_RENDER=1 "$HM" report "$1" --task a --status done > /dev/null
           python3 - "$LP/$1/events.jsonl" <<'PY'
import json, sys, time
p = sys.argv[1]; ls = [dict(json.loads(l), t=time.time() - 7200) for l in open(p) if l.strip()]
open(p, "w").write("".join(json.dumps(e) + "\n" for e in ls))
PY
}
N0=$(now)
# the call after the C-th so far (0-based in gh.calls): `cn` keeps C before a step
cn() { C=$(ncalls); }
posts() { python3 -c 'import json, sys; print(sum(1 for x in open(sys.argv[1]) if json.loads(x)["method"] == "POST" and json.loads(x)["path"].endswith("/issues")))' "$GH_CALLS" 2>/dev/null || echo 0; }

echo "  the yard's own host only"
pe() { env -u STALLS_PEERS CLAUDE_REPOS_JSON="$1" REGATTA_CONFIG="$S8/cfg" python3 -c "import sys; sys.path.insert(0, '$B'); import stalls; h, torn = stalls.self_judging(); print(stalls.peers(), sorted(h), torn)"; }
echo '{"repos": {}, "scopes": {"dock": {"repos": [], "yard": "buildbox"}}}' > "$S8/yard-bb.json"
check "$(pe "$S8/noyard.json")" "{'buildbox': 'buildbox-ssh'} [] False" "no scope's yard: the laptop reads and judges its peer's store as before S8 (wharf-runs/ssh)"
check "$(pe "$S8/yard-bb.json")" "{'buildbox': 'buildbox-ssh'} ['buildbox'] False" "a peer some scope's yard names: still read (the shared facts), judged by its own tick"
check "$(pe "$S8/torn.json")" "{'buildbox': 'buildbox-ssh'} [] True" "  a torn registry: read, and said to be torn (the tick then acts on no peer's stall)"
check "$(PLAN_HOST=buildbox pe "$S8/yard-bb.json")" "{} [] False" "  and the yard reads no peer of its own (itself left out)"

echo "  a raised stall: one issue after 10 minutes, the mention and the key, never a second"
s7ship r1
out=$(TK "$N0"); has "$out" "S7 testhost" "the tick judges the S7"
check "$(nrows)/$(ncalls)" "0/0" "  first seen now: no escalation yet"
out=$(TK $((N0 + 300)) --dry-run); has "$out" "would escalate stall on testhost: b · S7 ready, nobody started it (due " "  --dry-run before it is due: would escalate, and when"
out=$(TK $((N0 + 300))); check "$(nrows)/$(ncalls)" "0/0" "  5 minutes: none"
out=$(TK $((N0 + 660)) --dry-run); has "$out" "would escalate stall on testhost: b · S7 ready, nobody started it" "  --dry-run at 11 minutes: would escalate"
check "$(nrows)/$(ncalls)" "0/0" "  …and writes and calls nothing"
out=$(TK $((N0 + 660)))
has "$out" "escalated stall on testhost: b · S7 ready, nobody started it: github-issue #100" "  11 minutes: one issue"
check "$(call8 0 'c["method"] + " " + c["path"]')" "POST /repos/owner-x/logbook-x/issues" "  POSTed to the config's logbook repo"
check "$(call8 0 'b["body"].split(chr(10))[0]')" "@someone-x" "  the body starts with the config's mention"
has "$(call8 0 'b["body"]')" '- key: `["testhost", "r1", "b"]`' "  and names the stall's key"
has "$(call8 0 'b["body"]')" "- class: S7 — rule: ready, nobody started it" "  its class and rule"
check "$(call8 0 'b["labels"]')" "['stall']" "  labelled stall"
check "$(erow 0 '(r["state"], r["road"], r["issue"], r["class"], r["yard"], r["plan"], r["key"])')" \
  "('open', 'github-issue', 100, 'S7', 'testhost', 'r1', ['testhost', 'r1', 'b'])" "  one escalations.jsonl row: open, the road, the issue number kept"
out=$(TK $((N0 + 960))); check "$(nrows)/$(ncalls)" "1/1" "  the next tick: the same key, no second"
PLAN_NO_RENDER=1 "$HM" report r1 --task b --status running > /dev/null
out=$(TK $((N0 + 1260))); check "$(nrows)/$(ncalls)" "1/1" "the stall gone one pass: not closed (a glitch never closes and reopens it)"
printf '#!/bin/sh\necho "ssh: connect to host buildbox port 22: Operation timed out" >&2; exit 255\n' > "$S8/ssh-down"; chmod +x "$S8/ssh-down"
out=$(STALLS_PEERS=buildbox=nowhere STALLS_SSH="$S8/ssh-down" TK $((N0 + 1560)))
has "$out" "buildbox: unreachable" "  a pass with a store unread…"
check "$(nrows)/$(ncalls)" "1/1" "  …closes no stall's issue, however long it has been gone"
out=$(TK $((N0 + 1860)))
has "$out" "escalation closed (#100): stall on testhost: b · S7 ready, nobody started it — no longer judged a stall here" "gone 10 minutes, every store read: closed"
check "$(call8 1 'c["method"] + " " + c["path"]')/$(call8 2 'c["method"] + " " + c["path"] + " " + b["state"]')" \
  "POST /repos/owner-x/logbook-x/issues/100/comments/PATCH /repos/owner-x/logbook-x/issues/100 closed" "  a comment, then the issue closed"
has "$(call8 1 'b["body"]')" "Cleared on testhost: no longer judged a stall here." "  the comment names what cleared it"
check "$(erow 1 '(r["state"], r["issue"], r["why"])')" "('closed', 100, 'no longer judged a stall here')" "  a closed row"
out=$(TK $((N0 + 2160))); check "$(nrows)/$(ncalls)" "2/3" "  and nothing more"

echo "  a block the yard holds that waits on the owner: escalated only"
"$HM" $SHIP r2 --id r2 > /dev/null; "$HM" task r2 g1 > /dev/null; ll yard r2 dock > /dev/null
PLAN_NO_RENDER=1 "$HM" report r2 --task g1 --status waiting --progress "gated on docs/d.md (D1 open)" > /dev/null
N0=$(now)   # each section's clock from its own events (the store stamps them with the real one)
out=$(TK $((N0 + 300))); check "$(nrows)" "2" "a gated block quiet 5 minutes: not yet"
cn; out=$(TK $((N0 + 700)))
has "$out" "escalated r2/g1 on testhost: waits on the owner (gated): github-issue #$((100 + C))" "  quiet 10 minutes: one issue"
has "$(call8 $C 'b["body"]')" "waits on you: gated on docs/d.md (D1 open)" "  saying what it waits on"
cn; out=$(TK $((N0 + 1000))); check "$(ncalls)" "$C" "  the next tick: nothing new"
PLAN_NO_RENDER=1 "$HM" report r2 --task g1 --status done > /dev/null
out=$(TK $((N0 + 1300))); out=$(TK $((N0 + 1600)))
has "$out" "r2/g1 on testhost: waits on the owner (gated) — the block ended (done)" "  the block done: settled on two passes in a row, closed, saying so"

echo "  a question on a yard's ship: unanswered 15 minutes, a failed open tried once more, --escalate a class change"
"$HM" $SHIP r3 --id r3 > /dev/null; "$HM" task r3 q1 > /dev/null; ll yard r3 dock > /dev/null
PLAN_NO_RENDER=1 "$HM" report r3 --task q1 --status relayed --ask docs/q.md#D2 --summary "which one" --reversible yes --recommended A > /dev/null
N0=$(now); cn
out=$(TK $((N0 + 700))); check "$(ncalls)" "$C" "a relay 11 minutes old: not yet"
# S13a: as the deaf rule, the skipper's 15 minutes are its own: a 10-minute brake window inside them is not charged
printf '{"windows": [[%s, %s]], "since": null, "seen": null, "pass": null}' "$N0" "$((N0 + 600))" > "$STALLS_STATE_DIR/brake-windows.json"
out=$(TK $((N0 + 960))); check "$(ncalls)" "$C" "a relay 16 minutes old, 10 of them under the studio brake: not yet"
rm -f "$STALLS_STATE_DIR/brake-windows.json"
out=$(GH_FAIL=1 TK $((N0 + 960)))
has "$out" "escalated r3/q1 on testhost: docs/q.md#D2 unanswered: none — github-issue: gh: HTTP 401: Bad credentials" "  16 minutes, the API refusing: road none, said"
check "$(erow -1 '(r["road"], r["issue"], r.get("transient"))')" "('none', None, True)" "  the row kept as a transient failure"
cn; out=$(TK $((N0 + 1260))); Q1=$((100 + C))
has "$out" "docs/q.md#D2 unanswered: github-issue #$Q1" "  the next tick tries once more, and opens it"
check "$(erow -1 '(r["state"], r["road"], r.get("retried"), r["class"])')" "('open', 'github-issue', True, 'unanswered')" "  a retried open row"
has "$(call8 $C 'b["body"]')" "which one — Reversible: yes — Recommended: A" "  the question as the relay carries it"
cn; out=$(GH_FAIL=1 TK $((N0 + 1560))); check "$(ncalls)" "$C" "  once open, never sent again"
# S5's owner rule: the skipper hands the question to the owner with --escalate (a plain shell passes the yard's fence)
env -u CLAUDE_CODE_SESSION_ID "$LX/helm" skipper --escalate r3 D2 > /dev/null
cn; out=$(GH_FAIL_MATCH='^POST .*/issues$' TK $((N0 + 1860)))
check "$(erow -1 '(r["state"], r["road"], r.get("was"), r["class"], r.get("transient"))')" \
  "('class-changed', 'none', $Q1, \"owner's (escalated)\", True)" "escalated by --escalate: the class moved; its new issue refused"
check "$(ncalls)" "$((C + 1))" "  …and the first left open (no comment, no close): never a stall with none"
cn; out=$(TK $((N0 + 2160))); Q2=$((100 + C))
has "$out" "escalated r3/q1 on testhost: docs/q.md#D2 for the owner: github-issue #$Q2" "  the next tick: the second issue"
has "$(call8 $C 'b["body"]')" "The class moved from unanswered to owner's (escalated): this follows #$Q1." "  noting the first"
check "$(call8 $((C + 1)) 'c["path"]')/$(call8 $((C + 2)) 'c["path"] + " " + b["state"]')" \
  "/repos/owner-x/logbook-x/issues/$Q1/comments//repos/owner-x/logbook-x/issues/$Q1 closed" "  and only then the first closed"
has "$(call8 $((C + 1)) 'b["body"]')" "followed in #$Q2" "  pointing at the second"
check "$(erow -1 '(r["state"], r["issue"], r["was"], r["class"])')" "('class-changed', $Q2, $Q1, \"owner's (escalated)\")" "  one class-changed row"
PLAN_NO_RENDER=1 "$HM" report r3 --task q1 --answered docs/q.md#D2 > /dev/null
# withdraw on answer (charterer S3): read answered on two passes in a row, closed then (one misread never closes it)
cn; out=$(TK $((N0 + 2460))); check "$(ncalls)" "$C" "answered: the first pass that reads it so closes nothing"
out=$(GH_FAIL_MATCH='^PATCH' TK $((N0 + 2760)))
has "$out" "not closed — tried once more next pass" "  the second withdraws it; a failed close said"
check "$(erow -1 '(r["state"], r.get("close_tries"))')" "('class-changed', 1)" "  the row kept open, the close to be tried once more"
out=$(TK $((N0 + 3060))); has "$out" "escalation closed (#$Q2)" "  the next pass closes it"
has "$out" "— answered" "  answered, it says"

echo "  no logbook-repo value: unrouted, no call; opened once the value is there"
s7ship r4; N0=$(now); cn
out=$(CFG8="$S8/cfg0" TK "$N0"); out=$(CFG8="$S8/cfg0" TK $((N0 + 700)))
has "$out" "b · S7 ready, nobody started it: none — github-issue: no helm/logbook-repo value in the config dir" "no key: road none, said"
check "$(ncalls)/$(erow -1 '(r["state"], r["road"], r["issue"])')" "$C/('unrouted', 'none', None)" "  nothing called, an unrouted row"
n4=$(nrows); out=$(CFG8="$S8/cfg0" TK $((N0 + 1000))); check "$(nrows)/$(ncalls)" "$n4/$C" "  re-checked each pass without a row or a call"
out=$(TK $((N0 + 1300)))
has "$out" "b · S7 ready, nobody started it: github-issue #" "  the value written: the next pass opens it"
check "$(erow -1 '(r["state"], r["road"])')" "('open', 'github-issue')" "  an open row"
PLAN_NO_RENDER=1 "$HM" report r4 --task b --status running > /dev/null
out=$(TK $((N0 + 1600))); out=$(TK $((N0 + 1900))); has "$out" "escalation closed" "  and closed once it clears"

echo "  a guarded stall keeps its text home"
mkdir -p "$S8/projects/transcripts"; s7ship r5 "$S8/projects/transcripts"; N0=$(now)
out=$(TK "$N0"); cn; out=$(TK $((N0 + 700)))
has "$out" "escalated stall on testhost: S7 in a guarded repo: github-issue" "a guarded stall: its class and host only"
hasnt "$(call8 $C 'b["title"] + b["body"]')" "r5" "  no ship, task or topic in the issue"
hasnt "$(call8 $C 'b["body"]')" '["testhost"' "  nor its key"
hasnt "$(call8 $C 'b["body"]')" "- key:" "  no key line at all (escalations.jsonl on the yard keeps it)"
PLAN_NO_RENDER=1 "$HM" report r5 --task b --status running > /dev/null
out=$(TK $((N0 + 1000))); out=$(TK $((N0 + 1300))); has "$out" "escalation closed" "  closed once it clears"

echo "  at most 5 issues a pass"
for i in 1 2 3 4 5 6; do s7ship "m$i"; done; N0=$(now)
out=$(TK "$N0"); p0=$(posts); out=$(TK $((N0 + 700)))
check "$(( $(posts) - p0 ))" "5" "six due at once: five opened"
has "$out" "escalations: 1 more wait for the next pass" "  the sixth said"
p0=$(posts); out=$(TK $((N0 + 1000))); check "$(( $(posts) - p0 ))" "1" "  and opened on the next"
for i in 1 2 3 4 5 6; do PLAN_NO_RENDER=1 "$HM" report "m$i" --task b --status running > /dev/null; done
out=$(TK $((N0 + 1300))); out=$(TK $((N0 + 1600)))

echo "  who may call GitHub: an armed tick of launchd's, one at a time"
s7ship r7; N0=$(now); cn
out=$(TK "$N0"); mv "$S8/st/armed" "$S8/st/armed.off"
out=$(TK $((N0 + 700)))
has "$out" "would escalate stall on testhost: b · S7 ready, nobody started it" "a disarmed yard's tick: would escalate"
has "$out" "escalations: nothing called — the tick is disarmed" "  and says it called nothing"
check "$(ncalls)" "$C" "  nothing called"
mv "$S8/st/armed.off" "$S8/st/armed"
out=$(env CLAUDE_CODE_SESSION_ID=typed-1 HOME="$S8/home" REGATTA_CONFIG="$S8/cfg" STALLS_NOW=$((N0 + 700)) "$LX/helm" tick 2>&1)
has "$out" "escalations: nothing called — the tick runs inside session typed-1" "  a session's tick beside the poll's: nothing called"
out=$(env -u CLAUDE_CODE_SESSION_ID CLAUDE_UNATTENDED=1 HOME="$S8/home" REGATTA_CONFIG="$S8/cfg" STALLS_NOW=$((N0 + 700)) "$LX/helm" tick 2>&1)
has "$out" "escalations: nothing called — an unattended caller" "  an unattended caller's: nothing called"
check "$(ncalls)" "$C" "  still nothing called"
python3 -c 'import fcntl, os, sys, time; fd = os.open(sys.argv[1], os.O_WRONLY | os.O_CREAT); fcntl.flock(fd, fcntl.LOCK_EX); open(sys.argv[2], "w").close(); time.sleep(20)' \
  "$S8/.escalations.lock" "$S8/locked" & LOCKER=$!
for _ in $(seq 1 50); do [ -e "$S8/locked" ] && break; sleep 0.1; done
out=$(TK $((N0 + 700))); kill $LOCKER 2>/dev/null; wait $LOCKER 2>/dev/null
has "$out" "escalations: another tick holds the stall road — none this pass" "  another tick holding the road: this one calls nothing"
check "$(ncalls)" "$C" "  …nothing"
out=$(TK $((N0 + 1000))); has "$out" "escalated stall on testhost: b · S7" "  the lock free, armed, launchd's: it opens"
PLAN_NO_RENDER=1 "$HM" report r7 --task b --status running > /dev/null
out=$(TK $((N0 + 1300))); out=$(TK $((N0 + 1600)))

echo "  K6: a guarded block's issue and its closing comment name nothing of it"
"$HM" $SHIP gb --id gb --repo "$S8/projects/transcripts" > /dev/null; "$HM" task gb g9 > /dev/null; ll yard gb dock > /dev/null
PLAN_NO_RENDER=1 "$HM" report gb --task g9 --status waiting --progress "gated on docs/secret-plan.md (D4 open)" > /dev/null
N0=$(now); cn; out=$(TK $((N0 + 700)))
has "$out" "escalated a guarded block on testhost: waits on the owner (gated): github-issue" "a guarded block: its class and host"
for w in gb g9 secret-plan "helm show" "skipper ·"; do hasnt "$(call8 $C 'b["title"] + b["body"]')" "$w" "  no $w in the issue"; done
PLAN_NO_RENDER=1 "$HM" report gb --task g9 --status done > /dev/null
cn; out=$(TK $((N0 + 1000))); out=$(TK $((N0 + 1300)))
check "$(call8 $C 'b["body"]')" "Cleared on testhost: cleared." "  its closing comment: cleared, nothing more"
check "$(erow -1 'r["guarded"]')" "True" "  the row says it is guarded"

echo "  the road's faults are board cards"
s7ship r8; N0=$(now); out=$(TK "$N0")
out=$(GH_FAIL=1 TK $((N0 + 700))); out=$(GH_FAIL=1 TK $((N0 + 1000)))
check "$(erow -1 '(r["road"], r.get("retried"), r.get("transient"))')" "('none', True, True)" "an open that failed, and failed once more"
c8=$(ncalls); out=$(GH_FAIL=1 TK $((N0 + 1300))); check "$(ncalls)" "$c8" "  never tried a third time"
bd=$(env HOME="$S8/home" REGATTA_CONFIG="$S8/cfg" "$LX/helm" board --json 2>/dev/null)
has "$bd" "stall road: stall on testhost: b · S7 ready, nobody started it — not opened: github-issue: gh: HTTP 401: Bad credentials" "  …a card in the owner's column"
check "$(echo "$bd" | python3 -c "import json,sys; d=json.load(sys.stdin); print([c['kind'] for c in d['columns'][0]['cards'] if c['kind'] == 'road'])")" "['road']" "  one, kind road"
PLAN_NO_RENDER=1 "$HM" report r8 --task b --status running > /dev/null
out=$(TK $((N0 + 1600))); out=$(TK $((N0 + 1900))); has "$out" "escalation closed" "  closed once it clears (no issue: no call)"

echo "  the road's rules, one pass at a time (a stub GitHub in-process)"
# the python goes to a file first: bash 3.2 misparses an apostrophe in a heredoc inside "$(…)" and skips the case
cat > "$S8/unit.py" <<'PY'
import sys, types
sys.path.insert(0, sys.argv[1])
import stalls_tick as st, helmlib
calls, fail, failnums = [], set(), set()
n = [200]
def notice(title, body, kind="stall", host=None, labels=("stall",)):
    calls.append(("open", title, body))
    if "open" in fail:
        return {"road": "none", "issue": None, "said": "github-issue: down"}
    n[0] += 1
    return {"road": "github-issue", "issue": n[0], "said": "issue #%d" % n[0]}
def issue_state(num, state, comment):
    calls.append((state, num, comment))
    return (False, "down") if state in fail or num in failnums else (True, None)
road = [True]
def rung_road(via):   # as bin/ask's: a github-issue road alone here (no osascript, the rest unbuilt)
    if via != "github-issue":
        return (False, "%s: no road in this stub" % via)
    return (road[0], None if road[0] else "github-issue: no helm/logbook-repo value in the config dir")
def push(via, title, body, labels=("stall",)):   # the ladder's github-issue rung (charterer S3): as bin/ask's push, one channel
    ok, why = rung_road(via)
    if not ok:
        return {"road": "none", "issue": None, "said": why}
    assert via == "github-issue", via   # bin/ask's push opens an issue for github-issue only
    return notice(title, body, labels=labels)
st._ASK = types.SimpleNamespace(notice=notice, issue_state=issue_state, push=push, rung_road=rung_road,
                                withdraw=lambda via, row: None, stall_road=lambda h=None: rung_road("github-issue"))
me = helmlib.host()
def stall(cls, key="k1", **kw):
    return dict({"class": cls, "host": me, "key": [me, key], "key_kind": "step", "run": "r", "title": "%s %s" % (key, cls),
                 "evidence": [], "action": "raise", "column": "Blocked", "rule": "r"}, **kw)
def run(stalls_, t, res=None, mem_t=1):
    mem = st.Memory([dict(key_kind="step", key=s["key"], run="r", t=mem_t) for s in stalls_])
    return st.escalate(res or {"hosts": [me]}, [(s, {"action": "raise"}, True) for s in stalls_], mem, t, mode_now="armed")
out = []
def last_of(k):   # a key's newest row: a pass writes other keys' clears after it
    return [r for r in st.read_escalations() if r.get("key") == [me, k]][-1]
# a second class move names the class it moved from, never the one before
run([stall("S3")], 1000); run([stall("S5")], 1300); run([stall("S6")], 1600)
bodies = [c[2] for c in calls if c[0] == "open"]
out.append("from:%s" % ("The class moved from S5 to S6" in bodies[-1]))
# a failed close of the followed issue: tried once more, then carded
del calls[:]; fail.add("closed")
run([stall("S7", "k2")], 1000); run([stall("S1", "k2")], 1300); run([stall("S1", "k2")], 1600); run([stall("S1", "k2")], 1900)
out.append("was:%d" % sum(1 for c in calls if c[0] == "closed"))
out.append("card:%s" % any(r.get("was_open") and r.get("was_tries") for r in st.road_faults()))
fail.discard("closed")
# no time left: no call, and no try spent
import os, time
os.environ["STALLS_DEADLINE"] = str(time.time() + 10)
del calls[:]
r = run([], 5000)
out.append("late:%d:%s" % (len(calls), not any(x.get("close_tries") for x in st.read_escalations())))
del os.environ["STALLS_DEADLINE"]
# a config with no road: unrouted keys, none called; once routed, at most ESCALATE_MAX in one pass
road[0] = False; del calls[:]
keys = [stall("S3", "u%d" % i) for i in range(7)]
run(keys, 9000)
out.append("unrouted:%d" % sum(1 for c in calls if c[0] == "open"))
road[0] = True
lines = run(keys, 9300)
out.append("routed:%d:%s" % (sum(1 for c in calls if c[0] == "open"), any("2 more wait" in l for l in lines)))
# a key whose source was unread this pass is not closed; one whose source was read is
run([stall("S3", "o1", harness="orca")], 20000); run([stall("S3", "h1")], 20000)
del calls[:]
run([], 21000, res={"hosts": [me], "unread": {"orca": True}}); run([], 21700, res={"hosts": [me], "unread": {"orca": True}})
closed = [c[1] for c in calls if c[0] == "closed"]
out.append("unread:%d" % len(closed))
# a class move whose new open fails, and fails again on its retry: the first issue stays the stall's and
# is closed with its clear (the second review's driver)
run([stall("S3", "m1")], 30000)
first = [c for c in calls if c[0] == "open"][-1]
first_n = n[0]
fail.add("open"); run([stall("S5", "m1")], 30300); run([stall("S5", "m1")], 30600); fail.discard("open")
del calls[:]
run([], 31300); run([], 32000)
out.append("moved-clear:%s" % (first_n in [c[1] for c in calls if c[0] == "closed"]))
# a block guarded since its issue opened: its closing comment says nothing of it
real_state = st.helmlib.state
st.helmlib.state = lambda pid, at=None: {"tasks": [{"id": "b", "guarded": True, "status": "running", "progress": "a secret", "asks": []}]}
out.append("guarded-since:%s" % st.cleared({"kind": "block", "plan": "p", "block": "b"}))
st.helmlib.state = real_state
# a second move after the followed issue's close failed twice: the older issue is carried, closed at the clear
del calls[:]; fail.add("closed")
run([stall("S7", "x1")], 50000)
older = last_of("x1")["issue"]
run([stall("S1", "x1")], 50300); run([stall("S1", "x1")], 50600)
fail.discard("closed"); del calls[:]
run([stall("S5", "x1")], 50900)
out.append("older:%s:%s" % (older in [c[1] for c in calls if c[0] == "closed"], st.followed(last_of("x1")) == []))
# a retry delivered by banner is no card; a closed row's card names the issue left open, and ages out
rows = [{"ekey": "b1", "state": "open", "road": "banner", "issue": None, "retried": True},
        {"ekey": "c1", "state": "closed", "issue": 7, "close_failed": "#6: down", "close_failed_issues": [6], "t": st.clock()},
        {"ekey": "c2", "state": "closed", "issue": 8, "close_failed": "#8: down", "t": st.clock() - 8 * 86400}]
out.append("faults:%s" % [r["ekey"] for r in st.road_faults(rows)])
# refused passes keep the absence clock: an acting pass that misses a key once closes nothing
del calls[:]
run([stall("S3", "y1")], 60000)
yi = last_of("y1")["issue"]
for t_ in (60300, 60600, 60900):
    st.escalate({"hosts": [me]}, [(stall("S3", "y1"), {"action": "raise"}, True)], st.Memory([]), t_, mode_now="disarmed")
run([], 61200)
c1 = sum(1 for c in calls if c[:2] == ("closed", yi))
run([], 61900)
out.append("absent:%d:%d" % (c1, sum(1 for c in calls if c[:2] == ("closed", yi))))
# a partial close: the retry closes only the issue that failed
del calls[:]; fail.add("closed")
run([stall("S3", "z1")], 70000); run([stall("S5", "z1")], 70300)
fail.discard("closed")
row = st.read_escalations()[-1]
del calls[:]; failnums.add(row["was"])
run([], 70400); run([], 71100)
failnums.clear()
run([], 71400)
cl = [c[1] for c in calls if c[0] == "closed"]
out.append("partial:%d:%d" % (cl.count(row["issue"]), cl.count(row["was"])))
# back before a partial close's retry: its own issue (closed) reopened, the followed one (left open) closed
del calls[:]; fail.add("closed")
run([stall("S3", "w1")], 80000); run([stall("S5", "w1")], 80300)
fail.discard("closed")
wrow = last_of("w1")
failnums.add(wrow["was"]); run([], 80400); run([], 81100); failnums.clear()
del calls[:]
run([stall("S5", "w1")], 81400)
wl = last_of("w1")
out.append("back-partial:%s:%s:%s" % (("open", wrow["issue"]) in [c[:2] for c in calls],
                                      ("closed", wrow["was"]) in [c[:2] for c in calls], st.followed(wl) == []))
# back after a clear whose close left a followed issue open: reopened, that issue carried and still carded
del calls[:]; fail.add("closed")
run([stall("S3", "v1")], 90000); run([stall("S5", "v1")], 90300)
fail.discard("closed")
vrow = last_of("v1")
failnums.add(vrow["was"]); run([], 90400); run([], 91100); run([], 91400); failnums.clear()
run([stall("S5", "v1")], 92000)
vl = last_of("v1")
out.append("back-carded:%s:%s" % (vl.get("reopened"), st.followed(vl) == [vrow["was"]] and vl in st.road_faults()))
# one ship that raises costs its own keys, never the pass
st.helmlib.state = lambda pid, at=None: {}["tasks"]
out.append("ship:%s" % st._ship_wanted({}, "p", {}, me, 0, None))
st.helmlib.state = real_state
# a ship that raises half-way opens none of its keys, and the pass names the error's class
real_sw1 = st._ship_wanted1
def half(out_, *a):
    out_["block:p:a"] = {}
    raise KeyError("a secret")
st._ship_wanted1 = half
got, errs = {}, []
out.append("half:%s:%s:%s" % (st._ship_wanted(got, "p", {}, me, 0, None, errs), got, errs))
st._ship_wanted1 = real_sw1
# a yard acts on its own store only, whatever peers it read
real_yh = helmlib.yard_hosts
helmlib.yard_hosts = lambda: ({me}, False)
out.append("yard:%s" % sorted(st.acted_elsewhere({"stalls": [{"host": me}, {"host": "laptop-x"}], "self_judging": []})))
helmlib.yard_hosts = real_yh
# no osascript: the banner fails, never raises
import os
os.environ["ASK_OSASCRIPT"] = "/nonexistent/osascript"
out.append("banner:%s" % st._load("ask_probe", st.HERE / "ask").banner("t", "b"))   # the real bin/ask: st._ASK is the stub above
del os.environ["ASK_OSASCRIPT"]
# the judge with no wharf-runs: every source unread, so no issue closes on its absences
import stalls
real_lb = stalls._load_bin; stalls._load_bin = lambda name: None
out.append("noruns:%s" % sorted(k for k, v in stalls.judge(peer=False)["unread"].items() if v))
stalls._load_bin = real_lb
print(" ".join(out))
PY
check "$(env -u CLAUDE_CODE_SESSION_ID HOME="$S8/home" REGATTA_CONFIG="$S8/cfg" STALLS_ESCALATIONS="$S8/unit.jsonl" STALLS_STATE_DIR="$S8/unit-st" PLANS_DIR="$S8/empty" python3 "$S8/unit.py" "$B"
)" "from:True was:2 card:True late:0:True unrouted:0 routed:5:True unread:1 moved-clear:True guarded-since:cleared older:True:True faults:['c1'] absent:0:1 partial:1:2 back-partial:True:True:True back-carded:True:True ship:False half:False:{}:['KeyError'] yard:['laptop-x'] banner:banner failed: FileNotFoundError noruns:['canary', 'launches', 'orca', 'skippers']" \
  "a second move's from-class; a followed issue closed once more then carded; no call near the kill time; unrouted calls nothing, then 5 a pass; an unread source keeps its keys; a move whose new issue never opened closes the first at its clear; a block guarded since says nothing; a second move carries the older open issue and its clear closes it; a banner retry is no card, a closed card names the issue left open and ages out; refused passes keep the absence clock; a close retry closes only what failed; back before that retry reopens its own and closes the followed; back after a carded close carries it; a ship that raises costs its keys, all of them, and names its error's class; a yard acts on its own store; no osascript fails the banner; no wharf-runs reads as nothing read"

echo "  the notify ladder (charterer S3): rungs per kind, quiet hours, the cap, withdraw on answer"
# In-process, over synthetic messages (wanted() stubbed): the real bin/ask with the stub GitHub ($S8/gh) and a
# stub osascript, each case its own surfaces.json, log and state. UTC, so the quiet hours read as written.
# one line per call, whatever the body holds (notice()'s body is three lines)
printf '#!/bin/sh\necho call >> "%s/osa.ladder"\n' "$S8" > "$S8/osa-l"; chmod +x "$S8/osa-l"
printf '#!/bin/sh\necho call >> "%s/osa.ladder"\necho "osascript: down" >&2; exit 1\n' "$S8" > "$S8/osa-fail"; chmod +x "$S8/osa-fail"
cat > "$S8/ladder.py" <<'PY'
import json, os, sys, time
from pathlib import Path
sys.path.insert(0, sys.argv[1]); S8 = Path(sys.argv[2])
os.environ["TZ"] = "UTC"; time.tzset()
import stalls_tick as st, surfaces, helmlib
me = helmlib.host()
DAY = 20000 * 86400
out = []
def case(name, notify):
    for v, f in (("STALLS_ESCALATIONS", "%s.jsonl"), ("GH_CALLS", "%s.calls")):
        os.environ[v] = str(S8 / ("ladder-" + f % name))
    os.environ["STALLS_STATE_DIR"] = str(S8 / ("ladder-st-" + name))
    p = S8 / ("ladder-%s.json" % name)
    p.write_text(json.dumps({"notify": notify, "ask": {"parked": True}}))
    surfaces.FILE = p
    (S8 / "osa.ladder").write_text("")
def msg(key, ladder="question", kind="ask", since=DAY, cls="owner's (escalated)", floor=0, ready=False, src="ships"):
    k = [me, "p", key]
    return st._k([kind, k]), {"kind": kind, "key": k, "key_kind": kind, "src": src, "class": cls, "rule": "r",
                              "plan": "p", "block": "b", "since": since, "after": 600, "ready": ready, "guarded": False,
                              "title": "q %s" % key, "body": ["b"], "ladder": ladder, "floor": floor, "frozen": 0}
def run(msgs, t, answered=(), dry=False, res=None):
    st.wanted = lambda res, d, mem, t_: (dict(msgs), {"ships": True, "plans": set(), "answered": set(answered)})
    return st.escalate(res or {"hosts": [me]}, [], st.Memory([]), t, dry=dry, mode_now="armed")
def gh():
    f = Path(os.environ["GH_CALLS"])
    return [json.loads(x) for x in f.read_text().splitlines()] if f.exists() else []
def opened():
    return [c["body"]["title"] for c in gh() if c["method"] == "POST" and c["path"].endswith("/issues")]
def rows():
    return st.read_escalations(rungs=True)
def osa():
    return len((S8 / "osa.ladder").read_text().splitlines())

# a rung's after in place of the fixed 10 minutes
case("after", {"question": [{"via": "github-issue", "after": "2m"}]})
a = dict([msg("a")])
run(a, DAY + 60); n1 = len(opened()); run(a, DAY + 130)
r = rows()[-1]
out.append("after:%d:%d:%s" % (n1, len(opened()), (r["state"], r["rung"], r["via"], r["ladder"], r["pushed"] == DAY + 130)))
# a skipper's question waits its 15 minutes, whatever the rung's after
case("floor", {"question": [{"via": "github-issue", "after": "2m"}]})
f = dict([msg("f", cls="unanswered", floor=900)])
run(f, DAY + 300); n1 = len(opened()); run(f, DAY + 910)
out.append("floor:%d:%d" % (n1, len(opened())))
# no ladder in the file: the old row is the stall ladder, a question charterer then the same rungs
case("legacy", {me: ["github-issue"]})
out.append("legacy:%s:%s" % ([r["via"] for r in surfaces.ladder("stall", me)], [(r["via"], r["after"]) for r in surfaces.ladder("question", me)]))
q = dict([msg("q")])
l1 = run(q, DAY); l2 = run(q, DAY + 300); run(q, DAY + 610)
said = [l for l in l1 + l2 if l.startswith("escalation: q q — rung charterer: no road yet")]
out.append("charterer:%d:%d:%d" % (len(said), len([x for x in rows() if x.get("via") == "charterer"]), len(opened())))
# one row per rung: a banner at once, the issue at 10 minutes; neither twice
case("rows", {"stall": [{"via": "banner"}, {"via": "github-issue", "after": "10m"}]})
s = dict([msg("s", ladder="stall", kind="stall", cls="S7")])
run(s, DAY); run(s, DAY + 300); run(s, DAY + 610); run(s, DAY + 900)
out.append("rows:%d:%s:%d" % (osa(), [(x["state"], x["rung"], x["via"]) for x in rows()], len(opened())))
# quiet hours hold a phone rung, the excepted kind passes, the held one fires when they end
case("quiet", {"question": [{"via": "github-issue"}], "stall": [{"via": "github-issue"}],
               "quiet": {"hours": "22:00-07:00", "except": ["stall"]}})
night = DAY + 23 * 3600
qq = dict([msg("n", since=night), msg("s2", ladder="stall", kind="stall", cls="S7", since=night)])
dl = run(qq, night + 60, dry=True); run(qq, night + 60); n1 = opened()
run(qq, DAY + 86400 + 7 * 3600 + 60)
out.append("quiet:%s:%s:%s" % (any(l.endswith("q n — held: quiet hours") for l in dl), n1, opened()[len(n1):]))
# the cap: the newest message first, the rest the next hour
case("cap", {"question": [{"via": "github-issue"}], "cap": {"per_hour": 1}})
cc = dict([msg("old", since=DAY), msg("new", since=DAY + 100)])
run(cc, DAY + 200); n1 = opened(); run(cc, DAY + 1000); n2 = opened(); run(cc, DAY + 3800)
out.append("cap:%s:%d:%s" % (n1, len(n2), opened()[len(n2):]))
# a rung that waits for the owner's presence holds (read from S5); orca-app and spacesheep-app say why, once
case("roads", {"question": [{"via": "banner", "when": "present"}, {"via": "orca-app"}, {"via": "spacesheep-app"}]})
rr = dict([msg("r")])
dl = run(rr, DAY, dry=True); l1 = run(rr, DAY); l2 = run(rr, DAY + 300)
out.append("present:%s:%d" % (any("via banner — held: until the owner is at the Mac" in l for l in dl), osa()))
out.append("roads:%s:%d:%d" % (sorted(l.split(" — rung ")[1].split(":")[0] for l in l1 if " — rung " in l),
                               len([l for l in l2 if " — rung " in l]), len(rows())))
# withdraw on answer: an answered question's issue closes the next pass, and its rungs are forgotten
case("answer", {"question": [{"via": "banner"}, {"via": "github-issue"}]})
w = dict([msg("w")])
run(w, DAY); ek = list(w)[0]
had = ek in json.loads((S8 / "ladder-st-answer" / "escalations-rungs.json").read_text())
run({}, DAY + 60, answered=[ek])
kept1, calls1 = ek in json.loads((S8 / "ladder-st-answer" / "escalations-rungs.json").read_text()), len(gh())
run({}, DAY + 360, answered=[ek])
kept = ek in json.loads((S8 / "ladder-st-answer" / "escalations-rungs.json").read_text())
out.append("answer:%s:%s:%d:%s:%s:%s" % (had, kept1, calls1, kept, [c["method"] for c in gh()][1:], rows()[-1]["state"]))
# one pass that misreads it answered, then raised again: nothing closed, nothing rung twice
case("flap", {"question": [{"via": "banner"}, {"via": "github-issue"}]})
fl = dict([msg("fl")]); fk = list(fl)[0]
run(fl, DAY); run({}, DAY + 300, answered=[fk]); run(fl, DAY + 600); run(fl, DAY + 900)
out.append("flap:%s:%d" % ([c["method"] for c in gh()], osa()))
# an empty ladder for its kind: unrouted once due, as a host with no row was
case("empty", {"stall": []})
e = dict([msg("e", ladder="stall", kind="stall", cls="S7", ready=True)])
run(e, DAY + 700)
out.append("empty:%s" % [(x["state"], x["why"]) for x in rows()])
# only a rung with no road (the charterer, until S4): unrouted, so the poll's log still names it
case("nowhere", {"question": [{"via": "charterer"}]})
run(dict([msg("c", ready=True)]), DAY + 700)
out.append("nowhere:%s" % [(x["state"], x["why"].split(" (")[0]) for x in rows()])
# an old row of banner then github-issue: the first with a road alone, as notice() did
case("both", {me: ["banner", "github-issue"]})
bb = dict([msg("bb", ladder="stall", kind="stall", cls="S7", src="runs")])
run(bb, DAY + 610); run(bb, DAY + 900)
out.append("both:%d:%d" % (osa(), len(opened())))
# a class that flips back never rings again; a new one does
case("flip", {"stall": [{"via": "banner"}]})
for c_, t_ in (("S5", 0), ("S7", 300), ("S5", 600), ("S7", 900)):
    run(dict([msg("fl", ladder="stall", kind="stall", cls=c_, src="runs")]), DAY + t_)
out.append("flip:%d" % osa())
# a failed push: tried once more next pass, then not again
case("fail", {"stall": [{"via": "banner"}]})
os.environ["ASK_OSASCRIPT"] = sys.argv[2] + "/osa-fail"
ff = dict([msg("ff", ladder="stall", kind="stall", cls="S7", src="runs")])
l1 = run(ff, DAY); run(ff, DAY + 300); run(ff, DAY + 600)
os.environ["ASK_OSASCRIPT"] = sys.argv[2] + "/osa-l"
out.append("fail:%d:%s:%s:%s" % (osa(), any("push via banner failed" in l and "tried once more" in l for l in l1),
                                 [x.get("retried", False) for x in rows()], [r.get("via") for r in st.road_faults()]))
# a source unread 15 minutes keeps the message's rungs: back, its banner does not ring again
case("gap", {"stall": [{"via": "banner"}]})
gp = dict([msg("gp", ladder="stall", kind="stall", cls="S7", src="runs")])
run(gp, DAY)
for t_ in (300, 600, 900):
    run({}, DAY + t_, res={"hosts": [me], "unread": {"hosts": True}})
run(gp, DAY + 1200)
out.append("gap:%d" % osa())
# …and back after one read miss that follows the gap: still no second ring (a miss is never a clear by itself)
case("gap2", {"stall": [{"via": "banner"}]})
run(gp, DAY)
for t_ in (300, 600, 900):
    run({}, DAY + t_, res={"hosts": [me], "unread": {"hosts": True}})
run({}, DAY + 1200); run(gp, DAY + 1500)
out.append("gap2:%d" % osa())
# an old row of banner then github-issue whose banner fails: the issue in the same call, as notice() did, no card
case("fallback", {me: ["banner", "github-issue"]})
os.environ["ASK_OSASCRIPT"] = sys.argv[2] + "/osa-fail"
fb = dict([msg("fb", ladder="stall", kind="stall", cls="S7", src="runs")])
run(fb, DAY + 610); run(fb, DAY + 900)
card = [r.get("via") for r in st.road_faults()]
run(fb, DAY + 1200)
os.environ["ASK_OSASCRIPT"] = sys.argv[2] + "/osa-l"
out.append("fallback:%d:%d:%s" % (osa(), len(opened()), card))
# a host row with no road at first sight is re-checked each pass: a road written later is taken
case("late", {me: ["banner", "github-issue"]})
am = st.ask_mod(); real_lb = am.logbook
am.logbook = lambda: (None, "no helm/logbook-repo value in the config dir")
os.environ["ASK_OSASCRIPT"] = "/nonexistent/osascript"
lt_ = dict([msg("lt", ladder="stall", kind="stall", cls="S7", src="runs", ready=True)])
run(lt_, DAY); run(lt_, DAY + 700)
am.logbook = real_lb
run(lt_, DAY + 1000)
os.environ["ASK_OSASCRIPT"] = sys.argv[2] + "/osa-l"
out.append("late:%s:%d" % ([x["state"] for x in rows()], len(opened())))
# a host row's issue open: a pass whose logbook glitches rings no banner on top of it
case("glitch", {me: ["github-issue", "banner"]})
gl = dict([msg("gl", ladder="stall", kind="stall", cls="S7", src="runs")])
run(gl, DAY + 610)
am.logbook = lambda: (None, "no helm/logbook-repo value in the config dir")
run(gl, DAY + 900)
am.logbook = real_lb
run(gl, DAY + 1200)
out.append("glitch:%d:%d" % (len(opened()), osa()))
# a plain miss, then an answer: the issue closes on the next answered pass, not on the first
case("miss", {"question": [{"via": "github-issue"}]})
mm = dict([msg("mm")]); mk = list(mm)[0]
run(mm, DAY); run({}, DAY + 200); run({}, DAY + 400, answered=[mk]); c3 = len(gh()); run({}, DAY + 550, answered=[mk])
out.append("miss:%d:%d" % (c3, len(gh())))
# a ladder that is there and no list: no rung (unrouted), never the host row instead
case("notlist", {me: ["github-issue"], "stall": {"via": "github-issue", "after": "1h"}})
run(dict([msg("nl", ladder="stall", kind="stall", cls="S7", src="runs", ready=True)]), DAY + 700)
out.append("notlist:%s:%d" % ([x["state"] for x in rows()], len(opened())))
# a torn surfaces.json: every phone rung held, the tick says so
case("torn", {"question": [{"via": "github-issue"}]})
surfaces.FILE.write_text('{"notify": {"question": [')
lt = run(dict([msg("tq", ready=True)]), DAY + 700)
out.append("torn:%d:%s:%d" % (len(opened()), any(l.startswith("escalations: ladder-torn.json is no JSON") for l in lt), len(rows())))
# an ended task: its block and its escalated question are both settled
real_state = st.helmlib.state
st.helmlib.state = lambda pid, at=None: {"tasks": [{"id": "b", "status": "done", "kind": "build", "deps": [], "progress": "",
                                                   "asks": [{"ref": "docs/x.md#D1", "open": True}]}]}
got = set()
st._ship_wanted1({}, "p", {}, me, DAY, None, got)
st.helmlib.state = real_state
out.append("ended:%s" % sorted("%s:%s" % (json.loads(k)[0], json.loads(k)[1][2]) for k in got))
# the host row's default wait is the stall road's own, kept equal here (the tick passes its own besides)
out.append("same:%s" % (st.ESCALATE_AFTER == surfaces.LEGACY_AFTER))
# a malformed ladder and an unreadable quiet: no crash, every phone rung held, the tick says so
case("bad", {"stall": [{"via": ["github-issue"]}, {"via": "banner", "when": {}}], "question": [{"via": "github-issue"}],
             "quiet": {"hours": "22-07"}})
lb = run(dict([msg("bq")]), DAY + 700)
out.append("bad:%d:%s" % (len(opened()), any(l.startswith("escalations: notify.quiet does not read") for l in lb)))
# an old row of banner alone on a host with no osascript yet: unrouted, re-checked each pass, rung once one is
# there, as before the ladder
case("later", {me: ["banner"]})
os.environ["ASK_OSASCRIPT"] = "/nonexistent/osascript"
la = dict([msg("la", ladder="stall", kind="stall", cls="S7", src="runs", ready=True)])
l1 = run(la, DAY + 610)
os.environ["ASK_OSASCRIPT"] = sys.argv[2] + "/osa-l"
run(la, DAY + 900); run(la, DAY + 1200)
out.append("later:%d:%s:%s" % (osa(), any(" — rung banner" in l for l in l1), [x["state"] for x in rows()]))
# an explicit banner then an issue that never opens: the banner delivered, the issue still carded
case("mixed", {"stall": [{"via": "banner"}, {"via": "github-issue", "after": "10m"}]})
os.environ["GH_FAIL"] = "1"
mx = dict([msg("mx", ladder="stall", kind="stall", cls="S7", src="runs")])
run(mx, DAY); run(mx, DAY + 610); run(mx, DAY + 900)
del os.environ["GH_FAIL"]
out.append("mixed:%d:%s" % (osa(), [(r["state"], r.get("via")) for r in st.road_faults()]))
# a delivered rung that is no legacy pick beside a legacy row that failed: the issue's card still shows
case("through", {"stall": []})
sd = S8 / "ladder-st-through"; sd.mkdir(exist_ok=True)
(sd / "escalations-rungs.json").write_text(json.dumps({"x": {"first": DAY}}))
rws = [{"ekey": "x", "state": "rung", "via": "claude-app", "road": "claude-app", "pushed": DAY + 1, "t": DAY + 1},
       {"ekey": "x", "state": "rung", "via": "banner", "legacy": True, "road": "none", "retried": True, "t": DAY + 2},
       {"ekey": "x", "state": "open", "road": "none", "issue": None, "retried": True, "t": DAY + 3}]
out.append("through:%s" % [r["state"] for r in st.road_faults(rws)])
# an explicit ladder's rung with a key it does not know (a misspelt when, a reader's own mark) is dropped, never fired unheld
case("marks", {"stall": [{"via": "banner", "legacy": True}, {"via": "github-issue", "When": "present"}, {"via": "orca-app", "after": "1m"}]})
out.append("marks:%s" % [(r["via"], r["at"], r["legacy"], r["implicit"]) for r in surfaces.ladder("stall", me)])
# refused passes keep a gone message's rungs: back before an acting pass, its banner does not ring again
case("refused", {"stall": [{"via": "banner"}]})
rf = dict([msg("rf", ladder="stall", kind="stall", cls="S7", src="runs")])
run(rf, DAY)
st.wanted = lambda res, d, mem, t_: ({}, {"ships": True, "plans": set(), "answered": set()})
for t_ in (300, 600, 900, 1200):
    st._escalate({"hosts": [me]}, [], st.Memory([]), DAY + t_, True, keep=True)
run(rf, DAY + 1500)
out.append("refused:%d" % osa())
# a host with no osascript whose old row is banner, github-issue, and an issue that fails its open and retry:
# the issue stays the pick (no road elsewhere), never tried a third time, carded; no pass raises
case("noosa", {me: ["banner", "github-issue"]})
os.environ["ASK_OSASCRIPT"] = "/nonexistent/osascript"; os.environ["GH_FAIL"] = "1"
no = dict([msg("no", ladder="stall", kind="stall", cls="S7", src="runs", ready=True)])
for t_ in (610, 910, 1210, 1510):
    run(no, DAY + t_)
del os.environ["GH_FAIL"]; os.environ["ASK_OSASCRIPT"] = sys.argv[2] + "/osa-l"
out.append("noosa:%d:%s" % (len(opened()), [r["state"] for r in st.road_faults()]))
# an old open row of the pick's road from before the ladder: the banner it rang is never rung again at the upgrade
case("upg", {me: ["banner", "github-issue"]})
uk, uw = msg("up", ladder="stall", kind="stall", cls="S7", src="runs", ready=True)
st.append_escalation({"t": DAY, "yard": me, "ekey": uk, "key": uw["key"], "kind": "stall", "src": "runs", "class": "S7",
                      "road": "banner", "issue": None, "state": "open", "title": "q up"})
run({uk: uw}, DAY + 610); run({uk: uw}, DAY + 910)
fresh = dict([msg("fr", ladder="stall", kind="stall", cls="S7", src="runs", ready=True)])
u1 = osa(); run(fresh, DAY + 1210)
# notice() fell past a failed banner to an issue before the ladder; with osascript now, the banner is never rung on top
gk, gw = msg("gi", ladder="stall", kind="stall", cls="S7", src="runs", ready=True)
st.append_escalation({"t": DAY, "yard": me, "ekey": gk, "key": gw["key"], "kind": "stall", "src": "runs", "class": "S7",
                      "road": "github-issue", "issue": 7, "state": "open", "title": "q gi"})
u2 = osa(); run({gk: gw}, DAY + 1510)
out.append("upg:%d:%d:%d:%d" % (u1, u2, osa() - u2, len(opened())))
# a rungs entry whose times will not read (a hand edit) is forgotten, never a pass that raises
case("badt", {"stall": [{"via": "banner"}]})
sd = S8 / "ladder-st-badt"; sd.mkdir(exist_ok=True)
(sd / "escalations-rungs.json").write_text(json.dumps({"gone": {"t": "yesterday", "missed": 1}, "g2": {"first": True},
    "g3": {"first": 1, "tries": {"S7": {"banner": "1"}}}, "g4": {"first": 1, "noroad": {"S7": [{}]}},
    "g5": {"first": 1, "t": 1, "src": ["runs"], "missed": 1}}))
run(dict([msg("bt", ladder="stall", kind="stall", cls="S7", src="runs")]), DAY + 10)
out.append("badt:%d:%s" % (osa(), len(json.loads((sd / "escalations-rungs.json").read_text()))))
# a rung that does not read is dropped, and the unrouted reason names its problem, not only `ask backends`
case("typo", {"stall": [{"via": "github-issue", "after": "10 min"}]})
run(dict([msg("ty", ladder="stall", kind="stall", cls="S7", src="runs", ready=True)]), DAY + 700)
out.append("typo:%d:%s" % (len(opened()), [("10 min" in (r.get("why") or "")) for r in rows()]))
# --set refuses a seam that is no object, never a traceback
pr = S8 / "ladder-setrow.json"; pr.write_text(json.dumps({"notify": ["banner"]}))
try:
    surfaces.set_row("notify.yard=github-issue", pr); sr = "written"
except ValueError as e:
    sr = "fix it by hand" in str(e)
out.append("setrow:%s:%s" % (sr, json.loads(pr.read_text())))
# a problem with the key written still refuses (a string parked never written over by another string), and a
# seam that is not there is a refusal, never a KeyError
pr.write_text(json.dumps({"ask": {"parked": "yes"}}))
surfaces.set_row("parked=no", pr)
try:
    surfaces.set_row("foo.bar=x", pr); fs = "written"
except ValueError as e:
    fs = "no seam" in str(e)
out.append("setkey:%r:%s" % (json.loads(pr.read_text())["ask"]["parked"], fs))
# a host row an older --set wrote as a string is that one backend, as `ask backends` reads it
case("strrow", {me: "github-issue"})
out.append("strrow:%s:%s" % (surfaces.host_row(surfaces.load()["notify"], me), st.ask_mod().notify_row("stall", me)[1]))
# a reader from before the ladder over the new log: a rung row never reads as its key's state (no ekey)
def old_reader(path):
    last = {}
    for d in st.read_log(path):
        if d.get("ekey"):
            last[d["ekey"]] = d
    return last
case("oldreader", {"stall": [{"via": "banner"}, {"via": "github-issue"}]})
ok_ = dict([msg("ol", ladder="stall", kind="stall", cls="S7", src="runs")])
os.environ["ASK_OSASCRIPT"] = sys.argv[2] + "/osa-fail"
run(ok_, DAY); run(ok_, DAY + 300)   # the issue opens on the first pass, the failed banner's retry after it
os.environ["ASK_OSASCRIPT"] = sys.argv[2] + "/osa-l"
ol = old_reader(os.environ["STALLS_ESCALATIONS"])
out.append("oldreader:%s:%d" % ([v["state"] for v in ol.values()], len([x for x in rows() if x["state"] == "rung"])))
# quiet hours hold a close's comment too: answered at night, closed when the hours end
case("qclose", {"question": [{"via": "github-issue"}], "quiet": {"hours": "22:00-07:00"}})
qc = dict([msg("qc")]); qk = list(qc)[0]
run(qc, DAY + 12 * 3600)
night = DAY + 23 * 3600
dq = run({}, night, answered=[qk]); run({}, night + 300, answered=[qk]); n1 = [c["method"] for c in gh()]
run({}, DAY + 86400 + 7 * 3600 + 60, answered=[qk])
out.append("qclose:%s:%s:%s" % (n1, [c["method"] for c in gh()][len(n1):], rows()[-1]["state"]))
# a rung that does not read is named every pass, beside a rung that has a road too
case("typo2", {"stall": [{"via": "banner"}, {"via": "github-issue", "after": "10 min"}]})
t2 = run(dict([msg("t2", ladder="stall", kind="stall", cls="S7", src="runs")]), DAY + 700)
out.append("typo2:%d:%s" % (osa(), any("notify.stall[1]: after '10 min' is no duration" in l for l in t2)))
# a ladder whose rungs have no road is unrouted once its first rung is due, not at the fixed wait
case("unrdue", {"stall": [{"via": "charterer", "after": "1h"}]})
ud = dict([msg("ud", ladder="stall", kind="stall", cls="S7", src="runs", ready=True)])
run(ud, DAY + 700); u1 = len(rows()); run(ud, DAY + 3700)
out.append("unrdue:%d:%s" % (u1, [x["state"] for x in rows()]))
# an open banner row from before the ladder: an explicit github-issue rung opens the issue the owner asked for
case("bannerup", {"stall": [{"via": "github-issue"}]})
bk, bw = msg("bu", ladder="stall", kind="stall", cls="S7", src="runs", ready=True)
st.append_escalation({"t": DAY, "yard": me, "ekey": bk, "key": bw["key"], "kind": "stall", "src": "runs", "class": "S7",
                      "road": "banner", "issue": None, "state": "open", "title": "q bu"})
run({bk: bw}, DAY + 610); run({bk: bw}, DAY + 910)
out.append("bannerup:%d" % len(opened()))
# an after past a year does not read (dropped, named); a far due on a dry pass prints, never a raise
case("far", {"stall": [{"via": "github-issue", "after": "8760h"}]})
fd = run(dict([msg("fd", ladder="stall", kind="stall", cls="S7", src="runs")]), DAY + 700, dry=True)
out.append("far:%s:%s:%s:%s" % (surfaces.duration("99999999h"), surfaces.duration(1e12), any("(due " in l for l in fd), st.hm_due(1e18)))
# a seam other than notify that is no object reads as its defaults (main's rule since hail's S2) and holds no
# rung; a notify seam that is no object is named, holds every phone rung and is carded
case("seam", {"question": [{"via": "github-issue"}]})
surfaces.FILE.write_text(json.dumps({"ask": ["file"], "notify": {"question": [{"via": "github-issue"}]}}))
sl = surfaces.load()["ask"] == surfaces.DEFAULTS["ask"] and surfaces.notify_unreadable() is None
run(dict([msg("se", ready=True)]), DAY + 700)
n_ask = len(opened())
surfaces.FILE.write_text(json.dumps({"notify": ["github-issue"]}))
ls_ = run(dict([msg("se2", ready=True)]), DAY + 1400)
out.append("seam:%s:%d:%s:%d:%s" % (sl, n_ask, any("notify is no object" in l and "every rung held" in l for l in ls_),
                                    len(opened()), [r["state"] for r in st.road_faults()]))
# a file that will not read is named so, never "no JSON"
dd = S8 / "ladder-dir.json"; dd.mkdir(exist_ok=True)
out.append("unread:%s" % surfaces.notify_unreadable(dd, text=surfaces.snapshot(dd)))
# an empty seam (null, []) reads as the defaults, as before; an empty file is named, and holds
ef = S8 / "ladder-empty.json"; ef.write_text(json.dumps({"notify": None, "plan": []}))
e1 = surfaces.load(ef)["helm"]["render"] == surfaces.DEFAULTS["helm"]["render"] and surfaces.notify_unreadable(ef) is None
ef.write_text("")
out.append("emptyseam:%s:%s" % (e1, surfaces.notify_unreadable(ef).split(" (")[0]))
# a banner row from before the ladder that follows an issue: the explicit rung's new issue carries it and closes it
case("carry", {"stall": [{"via": "github-issue"}]})
ck, cw = msg("cy", ladder="stall", kind="stall", cls="S7", src="runs", ready=True)
st.append_escalation({"t": DAY, "yard": me, "ekey": ck, "key": cw["key"], "kind": "stall", "src": "runs", "class": "S7",
                      "road": "banner", "issue": None, "state": "class-changed", "was": 5, "was_open": True, "title": "q cy"})
run({ck: cw}, DAY + 610)
out.append("carry:%d:%s:%s" % (len(opened()), any(c["method"] == "PATCH" and c["path"].rstrip("/").endswith("/5") for c in gh()),
                               rows()[-1].get("was_open"), ))
# a rungs entry whose fired is null in the file: an empty map, never a pass that raises
case("nullf", {"stall": [{"via": "banner"}]})
nk, nw = msg("nf", ladder="stall", kind="stall", cls="S7", src="runs")
sd = S8 / "ladder-st-nullf"; sd.mkdir(exist_ok=True)
(sd / "escalations-rungs.json").write_text(json.dumps({nk: {"first": DAY, "fired": None, "tries": None}}))
nl = run({nk: nw}, DAY + 10)
out.append("nullf:%d:%s" % (osa(), any("the pass failed" in l for l in nl)))
# a close held by quiet hours keeps the message's rungs: back before the issue closes, its banner never rings twice
case("heldr", {"stall": [{"via": "banner"}, {"via": "github-issue"}], "quiet": {"hours": "22:00-07:00"}})
hk, hw = msg("hr", ladder="stall", kind="stall", cls="S7", src="runs", since=DAY + 12 * 3600)
run({hk: hw}, DAY + 12 * 3600)
for t_ in (23 * 3600, 23 * 3600 + 900, 23 * 3600 + 1800):
    run({}, DAY + t_)
run({hk: hw}, DAY + 86400 + 3600)
out.append("heldr:%d:%d:%s" % (osa(), len(opened()), [c["method"] for c in gh()]))
# a rung row with no via beside one with a via: road_faults sorts them, never a TypeError
case("novia", {"stall": []})
sd = S8 / "ladder-st-novia"; sd.mkdir(exist_ok=True)
(sd / "escalations-rungs.json").write_text(json.dumps({"x": {"first": DAY}}))
out.append("novia:%d" % len(st.road_faults([
    {"ekey": "x", "state": "rung", "road": "none", "retried": True, "t": DAY + 1},
    {"ekey": "x", "state": "rung", "via": "banner", "road": "none", "retried": True, "t": DAY + 2}])))
# an answered question whose close quiet hours hold keeps its rungs: raised again before it closes, no second banner
case("ansheld", {"question": [{"via": "banner"}, {"via": "github-issue"}], "quiet": {"hours": "22:00-07:00"}})
ak, aw = msg("ah", since=DAY + 12 * 3600)
run({ak: aw}, DAY + 12 * 3600)
run({}, DAY + 23 * 3600, answered=[ak]); run({}, DAY + 23 * 3600 + 300, answered=[ak]); run({ak: aw}, DAY + 23 * 3600 + 600)
out.append("ansheld:%d:%s" % (osa(), [c["method"] for c in gh()]))
# back after it cleared on a host row with no github-issue: the old issue's reopen is held by quiet hours as well
case("backq", {me: ["banner"], "quiet": {"hours": "22:00-07:00"}})
bk2, bw2 = msg("bq", ladder="stall", kind="stall", cls="S7", src="runs", ready=True)
st.append_escalation({"t": DAY, "yard": me, "ekey": bk2, "key": bw2["key"], "kind": "stall", "src": "runs", "class": "S7",
                      "road": "github-issue", "issue": 7, "state": "closed", "title": "q bq"})
bl = run({bk2: bw2}, DAY + 23 * 3600, dry=True); run({bk2: bw2}, DAY + 23 * 3600)
out.append("backq:%s:%s" % (any("held: quiet hours" in l for l in bl), [c["method"] for c in gh()]))
# an old banner row that follows an issue, an explicit issue rung with no road yet: the row kept, nothing dropped
case("carrynr", {"stall": [{"via": "github-issue"}]})
cn_k, cn_w = msg("cn", ladder="stall", kind="stall", cls="S7", src="runs", ready=True)
st.append_escalation({"t": DAY, "yard": me, "ekey": cn_k, "key": cn_w["key"], "kind": "stall", "src": "runs", "class": "S7",
                      "road": "banner", "issue": None, "state": "class-changed", "was": 5, "was_open": True, "title": "q cn"})
am.logbook = lambda: (None, "no helm/logbook-repo value in the config dir")
run({cn_k: cn_w}, DAY + 610)
am.logbook = real_lb
out.append("carrynr:%s" % [(r["state"], r.get("was")) for r in rows()])
# a message whose plan is no string: its rungs entry still reads, its banner rings once
case("intplan", {"stall": [{"via": "banner"}]})
ip = dict([msg("ip", ladder="stall", kind="stall", cls="S7", src="runs")]); list(ip.values())[0]["plan"] = 7
for t_ in (0, 300, 600):
    run(ip, DAY + t_)
out.append("intplan:%d" % osa())
# a presence-only ladder whose rungs have a road (an issue, a banner): unrouted and said, never held mute
case("presonly", {"question": [{"via": "github-issue", "when": "present"}], "stall": [{"via": "banner", "when": "present"}]})
po = dict([msg("pq", ready=True), msg("ps", ladder="stall", kind="stall", cls="S7", src="runs", ready=True)])
run(po, DAY + 700); run(po, DAY + 1000)
out.append("presonly:%d:%d:%s:%s" % (len(opened()), osa(), [r["state"] for r in rows()],
                                     all("held until the owner is at the Mac" in r["why"] for r in rows())))
# a rung that does not read is carded on the board, as a held seam is
case("typocard", {"stall": [{"via": "github-issue", "after": "10 min"}]})
run(dict([msg("tc", ladder="stall", kind="stall", cls="S7", src="runs")]), DAY + 10)
out.append("typocard:%s" % [(r["state"], r["why"].split(":")[0]) for r in st.road_faults()])
# --set over an empty file writes it, as over no file
pe = S8 / "ladder-setempty.json"; pe.write_text("")
surfaces.set_row("ask.relay=file", pe)
out.append("setempty:%s" % json.loads(pe.read_text()))
print(" ".join(out))
PY
check "$(env -u CLAUDE_CODE_SESSION_ID HOME="$S8/home" REGATTA_CONFIG="$S8/cfg" ASK_GH_API="$S8/gh" ASK_OSASCRIPT="$S8/osa-l" \
         PLANS_DIR="$S8/empty" python3 "$S8/ladder.py" "$B" "$S8")" \
  "after:0:1:('open', 0, 'github-issue', 'question', True) floor:0:1 legacy:['host-row']:[('charterer', 0.0), ('host-row', 600.0)] charterer:0:0:1 rows:1:[('rung', 0, 'banner'), ('open', 1, 'github-issue')]:1 quiet:True:['q s2']:['q n'] cap:['q new']:1:['q old'] present:True:0 roads:['orca-app', 'spacesheep-app']:0:1 answer:True:True:1:False:['POST', 'PATCH']:closed flap:['POST']:1 empty:[('unrouted', 'no rung with a road in notify.stall')] nowhere:[('unrouted', 'no rung with a road in notify.question')] both:1:0 flip:2 fail:2:True:[False, True]:['banner'] gap:1 gap2:1 fallback:1:1:[] late:['unrouted', 'open']:1 glitch:1:0 miss:1:3 notlist:['unrouted']:0 torn:0:True:0 ended:['ask:docs/x.md#D1', 'block:b'] same:True bad:0:True later:1:False:['unrouted', 'open'] mixed:1:[('open', 'github-issue')] through:['open'] marks:[('orca-app', 2, False, False)] refused:1 noosa:2:['open'] upg:0:1:0:0 badt:1:1 typo:0:[True] setrow:True:{'notify': ['banner']} setkey:False:True strrow:['github-issue']:['github-issue'] oldreader:['open']:2 qclose:['POST']:['POST', 'PATCH']:closed typo2:1:True unrdue:0:['unrouted'] bannerup:1 far:None:None:True:never seam:True:1:True:1:['held'] unread:ladder-dir.json does not read (IsADirectoryError) emptyseam:True:ladder-empty.json is empty carry:1:True:None nullf:1:False heldr:1:1:['POST'] novia:2 ansheld:1:['POST'] backq:True:[] carrynr:[('class-changed', 5)] intplan:1 presonly:0:0:['unrouted', 'unrouted']:True typocard:[('held', 'notify.stall[0]')] setempty:{'ask': {'relay': ['file']}}" \
  "a rung's after replaces the fixed 10 minutes; a skipper's question still waits 15; the old row is the stall ladder, a question's the charterer then it; that implicit charterer silent, no row; one row per rung, none twice; quiet hours hold the question and not the excepted stall, which fire when they end; the cap opens the newest first, the older the next hour; presence holds; orca-app and spacesheep-app say why once; an answer read on two passes in a row closes its issue and forgets its rungs, one misread closes nothing; an empty ladder is unrouted (its reason never names the host row it overrides), and so is one whose only rungs have no road; an old row of banner, github-issue takes the first with a road alone; a class flipping back never rings twice; a failed push is tried once more, then not; a source gap, and one read miss after it, keep what fired; a banner rung that fails twice is carded, and an old row's banner that fails falls to its issue in the same call, as notice() did, no card; an old row with no road is re-checked until one is written; its open issue holds through a glitch; a plain miss then an answer closes on the next answered pass; a ladder that is no list narrows to no rung; a torn file holds every phone rung and writes no unrouted row; an ended task settles its block and its questions; the host row's wait is the road's own; a malformed ladder costs no pass and an unreadable quiet holds every phone rung; an old banner row with no osascript yet is unrouted, then rings once it has one; a delivered banner never hides an issue rung that failed to open, nor does a banner hide any failed rung; an explicit rung with a key it does not know is dropped; refused passes never forget a gone message's rungs; with no osascript, an old row's issue that failed twice is carded, and no pass raises; an open row from before the ladder, of its banner or of the issue notice() fell to, is never rung again, a new message is; a rungs entry whose times, tries or lists will not read is forgotten, no raise; a rung that does not read is named in the unrouted reason; --set refuses a seam that is no object or not there, and writes a bool row as a bool; a string host row is its one backend, to host_row and to bin/ask's notify_row alike; a reader from before the ladder never takes a rung row as its key's state; quiet hours hold a close's comment until they end; a rung that does not read is named every pass beside a roaded one; a ladder with no road is unrouted once its first rung is due; a banner row from before the ladder never stands in for the issue rung the owner wrote; an after past a year does not read and a far due prints; a seam that is no object reads as its defaults, a notify one holds every rung and is carded; a file that will not read is named so; an empty seam reads as the defaults and an empty file is named; an explicit issue rung carries and closes what an old banner row followed; a null rungs field is an empty map; a close held by quiet hours keeps the message's rungs, an answered one's too; a rung row with no via sorts; a reopen of a host row's old issue is held by quiet hours; a banner row an issue rung with no road meets is kept whole; a plan that is no string never re-rings; --set writes over an empty file; a presence-only ladder, of an issue or a banner, is unrouted, said; a rung that does not read is carded"

echo "  a ship the yard could not read keeps its keys"
"$HM" $SHIP r9 --id r9 > /dev/null; "$HM" task r9 g2 > /dev/null; ll yard r9 dock > /dev/null
PLAN_NO_RENDER=1 "$HM" report r9 --task g2 --status waiting --progress "gated on docs/e.md (D1 open)" > /dev/null
N0=$(now); out=$(TK $((N0 + 700))); has "$out" "escalated r9/g2" "a gated block opened"
cp "$LP/r9/skipper.json" "$S8/r9-lease.json"; echo '{"holder": ' > "$LP/r9/skipper.json"
cn; out="$(TK $((N0 + 1300)))$(TK $((N0 + 1600)))"
hasnt "$out" "r9/g2 on testhost: waits on the owner (gated) —" "  its lease torn 15 minutes: not closed"
check "$(ncalls)" "$C" "  nothing called"
cp "$S8/r9-lease.json" "$LP/r9/skipper.json"; PLAN_NO_RENDER=1 "$HM" report r9 --task g2 --status done > /dev/null
out="$(TK $((N0 + 1900)))$(TK $((N0 + 2200)))"; has "$out" "r9/g2 on testhost: waits on the owner (gated) — the block ended (done)" "  read again and done: closed"

echo "  keel's gate unable to name every guarded repo: nothing leaves"
check "$(env -u CLAUDE_CODE_SESSION_ID HOME="$S8/home" REGATTA_CONFIG="$S8/cfg" python3 - "$B" <<'PY'
import sys, types
sys.path.insert(0, sys.argv[1])
import helmlib, stalls_tick as st
real = helmlib._sheep_gate
out = [str(helmlib.guard_unread())]
helmlib._sheep_gate = types.SimpleNamespace(PRIVATE_UNREAD=True); out.append(str(helmlib.guard_unread()))
helmlib._sheep_gate = types.SimpleNamespace(PRIVATE_UNREAD=False, confidential_roots=lambda: None); out.append(str(helmlib.guard_unread()))
helmlib._sheep_gate = None; out.append(str(helmlib.guard_unread()))
helmlib._sheep_gate = types.SimpleNamespace(PRIVATE_UNREAD=False, _GUARDED=None, confidential_roots=lambda: ()); out.append(str(helmlib.guard_unread()))
out.append(st.escalate({"hosts": []}, [], st.Memory([]), 0, mode_now="armed")[0])
helmlib._sheep_gate = real
print(" | ".join(out))
PY
)" "False | True | True | True | True | escalations: none this pass — the guarded list did not read (keel's gate, its regatta/guarded or the registry's confidential scopes)" \
  "PRIVATE_UNREAD, unread confidential roots, no gate or no regatta/guarded at all: the road sends nothing"

echo "  no yard here, or a torn registry: nothing escalated, both Macs as before"
s7ship r6; N0=$(now); c3=$(ncalls); n3=$(nrows)
out=$(CLAUDE_REPOS_JSON="$S8/noyard.json" TK "$N0"); out=$(CLAUDE_REPOS_JSON="$S8/noyard.json" TK $((N0 + 700)))
has "$out" "S7 testhost" "a host that is no scope's yard judges the stall"
check "$(ncalls)/$(nrows)" "$c3/$n3" "  and escalates nothing"
hasnt "$out" "escalat" "  not a line of it"
out=$(CLAUDE_REPOS_JSON="$S8/torn.json" TK $((N0 + 800))); check "$(ncalls)/$(nrows)" "$c3/$n3" "a torn registry: nothing escalated"
mkdir -p "$S8/empty"
check "$(PLANS_DIR="$S8/empty" python3 - "$B" <<'PY'
import sys; sys.path.insert(0, sys.argv[1]); import stalls_tick
s = {"class": "braked", "host": "testhost", "key": ["testhost", "x"], "key_kind": "step", "run": "r", "title": "x", "evidence": [],
     "action": "raise", "column": "Needs Sam"}
w = stalls_tick.wanted({}, [(s, {"action": "raise", "why": "x"}, True)], stalls_tick.Memory([]), 10 ** 10)[0]
s2 = dict(s, **{"class": "S3"})
w2 = stalls_tick.wanted({}, [(s2, {"action": "raise", "why": "x"}, True), (dict(s2, raise_to="skipper", key=["y"]), {"action": "raise"}, True)],
                        stalls_tick.Memory([]), 10 ** 10)[0]
print(len(w), len(w2))
PY
)" "0 1" "the class braked is never escalated, nor a raise to a live skipper"
unset PLANS_DIR STALLS_LOG STALLS_STATE_DIR CLAUDE_REPOS_JSON ASK_GH_API GH_CALLS SURFACES_HOST STALLS_REPOS PLAN_NO_SKIPPERS
export PLANS_DIR="$T/plans" SURFACES_FILE="$T/surfaces.json"

echo "the yard's tick pings the dead-man's switch, and holds Orca and the skippers under the studio brake (skipper-resilience S11)"
# Stubs only: `deadman` (a python script the tick runs as lighthouse's is) and the harness (the Orca read)
# both append to one sequence file, so their order is read, not assumed; launchctl records any call. The
# yard is this host (testhost) by the S8 registry; the brake is the file wharf's brake_refusal() reads in
# HOME. A fresh store and HOME. No Worker, no Orca app, no real job.
S11="$T/s11"; mkdir -p "$S11/hd" "$S11/st" "$S11/plans"
cat > "$S11/harness" <<EOF
#!/bin/sh
echo "orca \$*" >> "$S11/seq"
echo '[]'
EOF
cat > "$S11/deadman" <<EOF
#!/usr/bin/env python3
import os, sys
open("$S11/seq", "a").write("ping " + " ".join(sys.argv[2:]) + "\n")   # argv[1] is the verb
if os.environ.get("DM_EXIT"):
    print("deadman: the Worker answered HTTP 503", file=sys.stderr); sys.exit(int(os.environ["DM_EXIT"]))
if os.environ.get("DM_WARN"):
    print("deadman: the secret file is mode 644", file=sys.stderr)
print("pinged for " + sys.argv[2] + (" (braked)" if "--braked" in sys.argv else ""))
EOF
cat > "$S11/launchctl" <<EOF
#!/bin/sh
echo "\$*" >> "$S11/lc.calls"
EOF
cat > "$S11/false-launchctl" <<'EOF'
#!/bin/sh
exit 1
EOF
chmod +x "$S11/harness" "$S11/deadman" "$S11/launchctl" "$S11/false-launchctl"
export PLANS_DIR="$S11/plans" STALLS_LOG="$S11/stalls.jsonl" STALLS_STATE_DIR="$S11/st" CLAUDE_REPOS_JSON="$S8/repos.json" \
       SURFACES_FILE="$S8/surfaces.json" SURFACES_HOST=testhost STALLS_PEERS= STALLS_REPOS= PLAN_NO_SKIPPERS=1 PLAN_NO_WHARF=1 \
       STALLS_ORCA=1 STALLS_HARNESS="$S11/harness" HELM_DEADMAN="$S11/deadman" HELM_LAUNCHCTL="$S11/launchctl" \
       WHARF_LAUNCHCTL="$S11/false-launchctl"   # a brake label in the caller's config dir must not reach the suite
unset DM_EXIT
T11() { env -u CLAUDE_CODE_SESSION_ID -u CLAUDE_UNATTENDED HOME="$S11/hd" "$LX/helm" tick "$@" 2>&1; }   # launchd's tick: no session, not unattended
seq11() { [ -e "$S11/seq" ] && tr '\n' '|' < "$S11/seq" | sed 's/|$//' || true; }
rm -f "$S11/seq" "$S11/lc.calls"

echo "  a yard's tick: the Orca read, then the ping"
out=$(T11); rc=$?
check "$rc" "0" "the tick ends cleanly"
check "$(seq11)" "orca list --harness orca --unsettled --json|ping testhost" "the Orca read comes first, then the ping for this host (no --fail, no --braked)"
has "$out" "deadman: pinged for testhost" "  the ping's line is printed"
rm -f "$S11/seq"
out=$(T11 --json); json=$(printf '%s' "$out" | tail -1)
check "$(printf '%s' "$json" | python3 -c 'import json, sys; d = json.load(sys.stdin); print(d["deadman"], d["brake"])')" "['deadman: pinged for testhost'] None" "--json carries the ping's lines and no brake"
rm -f "$S11/seq"
out=$(T11 --dry-run); check "$(seq11)" "orca list --harness orca --unsettled --json" "--dry-run reads Orca and pings nothing"
hasnt "$out" "deadman" "  nor prints a deadman line"
rm -f "$S11/seq"
T11 --status > /dev/null; check "$(seq11)" "" "--status pings nothing"

echo "  a loud failure of the pass: --fail with a one-line why, the tick's exit unchanged"
rm -f "$S11/seq"
out=$(STALLS_NOW=notanumber T11); rc=$?
check "$rc" "1" "the tick still exits 1 (ask poll logs its failure as before)"
check "$(seq11)" "ping testhost --fail --why helm tick: ValueError in clock" "  the switch is told once, with the exception class and the function it came from, never its message (K6)"
has "$out" "helm tick: could not convert string to float: 'notanumber'" "  and helm's own failure line is still printed"
rm -f "$S11/seq"
out=$(STALLS_NOW=notanumber DM_EXIT=1 T11); rc=$?
check "$rc/$(seq11)" "1/ping testhost --fail --why helm tick: ValueError in clock" "  a --fail the switch refuses does not loop and does not change the exit"
rm -f "$S11/seq"

echo "  only launchd's tick pings: a session's and an unattended run's say so in one line"
out=$(env CLAUDE_CODE_SESSION_ID=sess-abcdefgh HOME="$S11/hd" "$LX/helm" tick 2>&1)
check "$(seq11)" "orca list --harness orca --unsettled --json" "a tick inside a session: no ping (a plain one would hide a dead poll)"
has "$out" "deadman: not pinged — the tick runs inside session sess-abc: the ping is launchd's tick's" "  said in one line"
rm -f "$S11/seq"
out=$(env -u CLAUDE_CODE_SESSION_ID CLAUDE_UNATTENDED=1 HOME="$S11/hd" "$LX/helm" tick 2>&1)
check "$(seq11)" "orca list --harness orca --unsettled --json" "an unattended caller: no ping"
has "$out" "deadman: not pinged — an unattended caller (CLAUDE_UNATTENDED=1)" "  said in one line"
rm -f "$S11/seq"
out=$(env CLAUDE_CODE_SESSION_ID=sess-abcdefgh STALLS_NOW=notanumber HOME="$S11/hd" "$LX/helm" tick 2>&1); rc=$?
check "$rc/$(seq11)" "1/" "  nor a --fail from a session's failing tick (it would open an issue)"
rm -f "$S11/seq"
out=$(DM_WARN=1 T11)
has "$out" "deadman: pinged for testhost" "a ping that went with a warning on stderr: the ping's line is kept"
has "$out" "deadman: the secret file is mode 644" "  and the warning is its own line"
rm -f "$S11/seq"

echo "  deadman failing or absent: one line, never the tick's failure, never a --fail"
out=$(DM_EXIT=1 T11); rc=$?
check "$rc/$(seq11)" "0/orca list --harness orca --unsettled --json|ping testhost" "a ping that fails: the tick exits 0, one ping"
has "$out" "deadman: ping failed (exit 1): the Worker answered HTTP 503" "  said in one line"
rm -f "$S11/seq"
out=$(HELM_DEADMAN="$S11/not-installed" T11); rc=$?
check "$rc/$(seq11)" "0/orca list --harness orca --unsettled --json" "deadman absent: the tick exits 0 and pings nothing"
has "$out" "deadman: not pinged — not installed (lighthouse)" "  one quiet line"
check "$(printf '%s\n' "$out" | grep -c deadman)" "1" "  and only that line"
rm -f "$S11/seq"

echo "  only a host some scope's yard names pings"
out=$(CLAUDE_REPOS_JSON="$S8/noyard.json" T11); rc=$?
check "$rc/$(seq11)" "0/orca list --harness orca --unsettled --json" "no scope has a yard (every scope today): no ping"
hasnt "$out" "deadman" "  and not a line of it"
rm -f "$S11/seq"
out=$(CLAUDE_REPOS_JSON="$S8/torn.json" T11); check "$(seq11)" "orca list --harness orca --unsettled --json" "a torn registry reads no yard here: no ping"
hasnt "$out" "deadman" "  and not a line of it"
rm -f "$S11/seq"
out=$(PLAN_HOST=otherhost SURFACES_HOST=otherhost T11); check "$(seq11)" "orca list --harness orca --unsettled --json" "a host the yard is not (the laptop): no ping"
hasnt "$out" "deadman" "  and not a line of it"
rm -f "$S11/seq"
out=$(HELM_DEADMAN="$S11/not-installed" PLAN_HOST=otherhost T11)
hasnt "$out" "deadman" "a host that is no yard with deadman absent: silent too"
rm -f "$S11/seq"

echo "  under the studio brake: no Orca read, no wharf pass, no skipper start or stop, and --braked"
: > "$S11/hd/.studio-brake"
out=$(T11); rc=$?
check "$rc/$(seq11)" "0/ping testhost --braked" "no Orca read; the ping is --braked"
has "$out" "helm tick: the studio brake holds ($S11/hd/.studio-brake exists)" "  the tick says so"
has "$out" "orca: not read — the studio brake holds" "  and so does the card for the Orca read"
has "$out" "deadman: pinged for testhost (braked)" "  the ping's line"
rm -f "$S11/seq"
out=$(PLAN_NO_WHARF= T11)
has "$out" "wharf: skipped — the studio brake holds ($S11/hd/.studio-brake exists): its pass reads Orca" "wharf's pass reads Orca: held, and said"
check "$(seq11)" "ping testhost --braked" "  (no Orca read there either)"
rm -f "$S11/seq"
out=$(CLAUDE_REPOS_JSON="$S8/noyard.json" T11)
check "$(seq11)" "" "a host that is no yard under the brake: no Orca read, and no ping"
has "$out" "orca: not read — the studio brake holds" "  the brake holds Orca reads on any host"
rm -f "$S11/seq"
out=$(STALLS_NOW=notanumber T11)
check "$(seq11)" "ping testhost --fail --why helm tick: ValueError in clock" "a loud failure with the brake file present is still --fail, never --braked (raised before the brake is read; the in-tick brake is the cases above)"
rm -f "$S11/seq"
out=$(T11 --json); json=$(printf '%s' "$out" | tail -1)
check "$(printf '%s' "$json" | python3 -c 'import json, sys; d = json.load(sys.stdin); print(d["brake"] == sys.argv[1], d["deadman"])' "$S11/hd/.studio-brake exists")" "True ['deadman: pinged for testhost (braked)']" "--json: the brake's reason and the ping"
rm -f "$S11/hd/.studio-brake" "$S11/seq"
out=$(T11); check "$(seq11)" "orca list --harness orca --unsettled --json|ping testhost" "the brake lifted: the Orca read and a plain ping again"
hasnt "$out" "studio brake" "  and no line of the brake"
rm -f "$S11/seq"

echo "  the skipper pass: held under the brake, armed or not, and silent where no scope is held"
SK11() { env -u CLAUDE_CODE_SESSION_ID HOME="$S11/hd" python3 - "$B" "$1" "$2" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import skipperlib, stalls_tick
calls = []
skipperlib.ensure = lambda act, why=None: calls.append(act) or ["would act"]
brake = sys.argv[3] or None
print(stalls_tick.ensure_skippers(sys.argv[2], brake), calls)
PY
}
unset PLAN_NO_SKIPPERS
check "$(SK11 armed 'brake file exists')" "[] []" "the brake, no scope held here: no line, ensure not reached"
check "$(SK11 armed '')" "[] []" "  and no brake, no scope held: nothing either (the tick as before S5)"
LP="$PLANS_DIR"
"$HM" $SHIP s11a --id s11a > /dev/null; "$HM" task s11a b1 > /dev/null; ll yard s11a dock > /dev/null
check "$(SK11 armed '')" "['would act'] [True]" "no brake: an armed pass with a scope held reaches skipperlib.ensure, acting"
check "$(SK11 armed 'brake file exists')" "['skippers: held — the studio brake holds (brake file exists): none started or stopped'] []" "a scope held here: one line, ensure not reached (no start, no stop, no lease written)"
check "$(SK11 dry 'brake file exists')" "['skippers: held — the studio brake holds (brake file exists): none started or stopped'] []" "  a dry pass too"
: > "$S11/hd/.studio-brake"; : > "$S11/lc.calls"
out=$(T11)
has "$out" "skippers: held — the studio brake holds" "the tick prints it with a scope held"
check "$(cat "$S11/lc.calls")" "" "  and no launchctl call was made"
check "$(lf s11a holder)" "yard" "  the lease untouched"
rm -f "$S11/hd/.studio-brake" "$S11/seq"
out=$(CLAUDE_REPOS_JSON="$S8/noyard.json" T11)
hasnt "$out" "skippers: held" "no brake: no held line"
export PLAN_NO_SKIPPERS=1

echo "  brake_refusal() is wharf-runs' own"
check "$(HOME="$S11/hd" python3 -c "import sys; sys.path.insert(0, '$B'); import helmlib; print(helmlib.brake_refusal())")" "None" "no brake file, no label: None"
: > "$S11/hd/.studio-brake"
check "$(HOME="$S11/hd" python3 -c "import sys; sys.path.insert(0, '$B'); import helmlib; print(helmlib.brake_refusal())")" "$S11/hd/.studio-brake exists" "the brake file: its reason, from wharf's own text"
check "$(HOME="$S11/hd" python3 -c "
import sys; sys.path.insert(0, '$B'); import helmlib; n = list(sys.path); helmlib.brake_refusal(); print(sys.path == n)")" "True" "  and it leaves sys.path as it found it (wharf puts its folders first)"
rm -f "$S11/hd/.studio-brake"

echo "  the stall road under the brake: Orca is unread, so no escalation of an Orca stall is closed"
: > "$S11/hd/.studio-brake"
check "$(HOME="$S11/hd" python3 -c "
import sys; sys.path.insert(0, '$B'); import stalls
r = stalls.judge(peer=False, live_call=False, orca_held='held'); print(r['unread']['orca'], [n for n in r['notes'] if 'studio brake' in n][:1] != [])")" \
  "True True" "judge(orca_held=): the Orca source is unread, and a card says so"
rm -f "$S11/hd/.studio-brake"
check "$(HOME="$S11/hd" python3 -c "
import sys; sys.path.insert(0, '$B'); import stalls
r = stalls.judge(peer=False, live_call=False); print(r['unread']['orca'])")" "False" "  with no brake it is read, as before"
printf '%s\n' '{"t": 1, "yard": "testhost", "ekey": "k-orca", "kind": "stall", "key": ["o"], "src": "orca", "class": "S1", "state": "open", "road": "none", "title": "an Orca stall"}' > "$S11/esc.jsonl"
mkdir -p "$S11/escst"; printf '%s\n' '{"k-orca": [1, 2]}' > "$S11/escst/escalations-seen.json"   # missing for two passes already: only the unread Orca source holds it
cat > "$S11/esc.py" <<'PY'
import os, sys
sys.path.insert(0, sys.argv[1])
import stalls_tick
unread = {"orca": True} if sys.argv[2] == "held" else {}
print(stalls_tick._escalate({"hosts": ["testhost"], "unread": unread, "stalls": [], "unsure": []}, [], stalls_tick.Memory([]), 10 ** 9, True))
PY
check "$(STALLS_STATE_DIR="$S11/escst" STALLS_ESCALATIONS="$S11/esc.jsonl" python3 "$S11/esc.py" "$B" held)" "[]" "  an open Orca escalation, Orca unread: nothing would be closed"
has "$(STALLS_STATE_DIR="$S11/escst" STALLS_ESCALATIONS="$S11/esc.jsonl" python3 "$S11/esc.py" "$B" read)" "would close the escalation of an Orca stall" "  the same row with Orca read and the stall gone: it would close (so the first is the brake's doing)"
unset STALLS_NOW DM_EXIT HELM_DEADMAN HELM_LAUNCHCTL WHARF_LAUNCHCTL STALLS_HARNESS SURFACES_HOST CLAUDE_REPOS_JSON STALLS_LOG STALLS_STATE_DIR PLAN_NO_SKIPPERS
export PLANS_DIR="$T/plans" SURFACES_FILE="$T/surfaces.json" STALLS_ORCA=0 PLAN_NO_WHARF=1 STALLS_PEERS= STALLS_REPOS=


echo "before sitting A (skipper-resilience S13a): an Orca that does not answer, the skipper clocks through a brake, the ping's reserved time"
# Stubs only, as S11's: the harness and orca (the Orca read; down while orca.down exists) and deadman append
# to one sequence file; the yard is this host by S8's registry; the brake is the file in HOME. Every Python
# harness is a file, never a heredoc inside $(…) (bash 3.2).
S13="$T/s13"; mkdir -p "$S13/hd" "$S13/st" "$S13/plans" "$S13/sess"
cat > "$S13/harness" <<EOF
#!/bin/sh
echo "orca \$*" >> "$S13/seq"
[ -e "$S13/orca.down" ] && { echo "orca is not answering"; exit 1; }
[ -e "$S13/orca.warn" ] && echo "adapter claude-code: its sessions unread" >&2
echo '[]'
EOF
cat > "$S13/orca" <<EOF
#!/bin/sh
[ -e "$S13/orca.down" ] && { echo "the app is not answering" >&2; exit 1; }
case "\$2" in
  task-list) echo '{"ok": true, "result": {"tasks": []}}';;
  run-show) echo '{"ok": true, "result": {"run": {"coordinator_handle": "term-1"}}}';;
  *) echo '{"ok": true, "result": {"messages": []}}';;
esac
EOF
cat > "$S13/deadman" <<EOF
#!/usr/bin/env python3
import os, sys, time
open("$S13/seq", "a").write("ping " + " ".join(sys.argv[2:]) + "\n")
if os.environ.get("DM_SLEEP"):
    time.sleep(float(os.environ["DM_SLEEP"]))
print("pinged for " + sys.argv[2])
EOF
chmod +x "$S13/harness" "$S13/orca" "$S13/deadman"
export PLANS_DIR="$S13/plans" STALLS_LOG="$S13/stalls.jsonl" STALLS_STATE_DIR="$S13/st" CLAUDE_REPOS_JSON="$S8/repos.json" \
       SURFACES_FILE="$S8/surfaces.json" SURFACES_HOST=testhost STALLS_PEERS= STALLS_REPOS= PLAN_NO_SKIPPERS=1 PLAN_NO_WHARF=1 \
       STALLS_ORCA=1 STALLS_HARNESS="$S13/harness" HARNESS_ORCA="$S13/orca" HELM_DEADMAN="$S13/deadman" \
       HELM_LAUNCHCTL="$S11/launchctl" WHARF_LAUNCHCTL="$S11/false-launchctl" ASK_SESSIONS_DIR="$S13/sess"
unset DM_SLEEP STALLS_DEADLINE STALLS_NOW
T13() { env -u CLAUDE_CODE_SESSION_ID -u CLAUDE_UNATTENDED -u CLAUDE_CODE_DISABLE_BACKGROUND_TASKS HOME="$S13/hd" "$LX/helm" tick "$@" 2>&1; }
pings13() { [ -e "$S13/seq" ] && grep '^ping' "$S13/seq" | tr '\n' '|' | sed 's/|$//' || true; }
n13() { python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["n"])' "$S13/st/orca-unread.json" 2>/dev/null || echo none; }
rm -f "$S13/seq"

echo "  an Orca that does not answer: plain twice, then --fail on the third unread pass in a row"
: > "$S13/orca.down"
T13 > /dev/null; T13 > /dev/null; out=$(T13)
check "$(pings13)" "ping testhost|ping testhost|ping testhost" "no ship here has an Orca Run: three unread passes stay plain"
has "$out" "deadman: Orca unread 3 passes in a row, no ship here has an Orca Run — the ping stays plain" "  and the tick says why"
check "$(n13)" "3" "  the count is kept in the tick's state dir"
rm -f "$S13/seq" "$S13/st/orca-unread.json"
LP="$PLANS_DIR"
"$HM" $SHIP s13o --id s13o > /dev/null; "$HM" task s13o b1 > /dev/null
cat > "$S13/orca_run.py" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p)); d.setdefault("blueprints", {})["dock"] = {"orca_run": "run-s13"}
open(p, "w").write(json.dumps(d))
PY
python3 "$S13/orca_run.py" "$LP/s13o/plan.json"
out=$(T13); check "$(pings13)" "ping testhost" "a ship with an Orca Run, Orca unread once: plain"
hasnt "$out" "Orca unread" "  and no line of the count"
out=$(T13); check "$(pings13)" "ping testhost|ping testhost" "  twice: plain"
out=$(T13)
check "$(pings13)" "ping testhost|ping testhost|ping testhost --fail --why orca unread: harness list printed no JSON" \
  "  the third unread pass in a row: --fail, the why the Orca note in one line"
has "$out" "deadman: Orca unread 3 passes in a row — the ping is a --fail" "  said in the tick's lines"
rm -f "$S13/seq"
T13 > /dev/null; check "$(pings13)" "ping testhost --fail --why orca unread: harness list printed no JSON" "  a fourth: --fail still"
rm -f "$S13/seq" "$S13/orca.down"
out=$(T13); check "$(pings13)/$(n13)" "ping testhost/0" "Orca read again: a plain ping, the count reset"
hasnt "$out" "Orca unread" "  and no line of it"
rm -f "$S13/seq"
: > "$S13/orca.down"; T13 > /dev/null; T13 > /dev/null
: > "$S13/hd/.studio-brake"; out=$(T13)
check "$(n13)" "0" "two unread passes, then a braked one: the count reset (no read is made under the brake)"
rm -f "$S13/hd/.studio-brake"; T13 > /dev/null
check "$(pings13)" "ping testhost|ping testhost|ping testhost --braked|ping testhost" "  so the next unread pass is the first again: plain"
rm -f "$S13/seq"; T13 > /dev/null; T13 > /dev/null; rm -f "$S13/seq"
: > "$S13/hd/.studio-brake"; out=$(T13)
check "$(pings13)" "ping testhost --braked" "past three unread, the brake on: --braked, never --fail"
rm -f "$S13/hd/.studio-brake" "$S13/seq" "$S13/st/orca-unread.json"
out=$(T13 --dry-run); out=$(T13 --dry-run); out=$(T13 --dry-run)
check "$(pings13)/$(n13)" "/none" "--dry-run pings nothing and counts nothing"
T13 > /dev/null; T13 > /dev/null; rm -f "$S13/seq"
out=$(STALLS_NOW=notanumber T13)
check "$(pings13)/$(n13)" "ping testhost --fail --why helm tick: ValueError in clock/2" "a pass that raises: its own --fail, the count kept as it was"
rm -f "$S13/seq" "$S13/st/orca-unread.json"
for i in 1 2 3; do out=$(env -u CLAUDE_UNATTENDED -u CLAUDE_CODE_DISABLE_BACKGROUND_TASKS CLAUDE_CODE_SESSION_ID=sess-s13 HOME="$S13/hd" "$LX/helm" tick 2>&1); done
check "$(pings13)/$(n13)" "/none" "a session's tick neither pings nor counts (only launchd's tick pings)"
has "$out" "deadman: not pinged — the tick runs inside session sess-s13" "  for the session's refusal"
rm -f "$S13/orca.down"; : > "$S13/orca.warn"
out=$(T13); out=$(T13); out=$(T13)
check "$(pings13)/$(n13)" "ping testhost|ping testhost|ping testhost/0" "a warning Orca answered with (the board's unread flag): never counted, three passes plain"
rm -f "$S13/orca.warn" "$S13/seq"
cat > "$S13/dead.py" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import stalls
for n in sys.argv[2:]:
    print(stalls.orca_dead([n]))
PY
check "$(python3 "$S13/dead.py" "$B" "orca: harness list did not answer (TimeoutExpired)" "orca: task-list --run run-transcripts-1 unread: its workers are not judged this tick" \
        "orca: no Run's task-list answered (2 asked)" "orca: the judge failed (KeyError: 'transcripts at /x/y')" "orca: adapter claude-code: its sessions unread" "orca: run r1 names no coordinator: its questions are unread")" \
  "harness list did not answer
None
no Run's task-list answered
the judge failed (KeyError)
None
None" "the --fail's words are fixed (K6: no run id, path or message leaves); one Run unread, a warning or a Run with no coordinator is no dead Orca"

echo "  no yard set: both Macs as today — no count, no brake record, the deadline untouched"
rm -rf "$S13/st"; mkdir -p "$S13/st"; rm -f "$S13/seq"; : > "$S13/orca.down"
"$HM" $SHIP s13n --id s13n > /dev/null; "$HM" task s13n b1 > /dev/null; ll yard s13n dock > /dev/null   # a lease held here: the brake record is the yard's, not the lease's
for i in 1 2 3; do CLAUDE_REPOS_JSON="$S8/noyard.json" T13 > /dev/null; done
: > "$S13/hd/.studio-brake"; CLAUDE_REPOS_JSON="$S8/noyard.json" T13 > /dev/null; rm -f "$S13/hd/.studio-brake"
CLAUDE_REPOS_JSON="$S8/noyard.json" T13 > /dev/null
check "$(pings13)/$(ls "$S13/st" | grep -c 'orca-unread\|brake-windows' | tr -d ' ')" "/0" "no ping, and neither new record written"
rm -f "$S13/orca.down"
cat > "$S13/reserve.py" <<'PY'
import os, sys
sys.path.insert(0, sys.argv[1])
import stalls_tick
before = os.environ.get("STALLS_DEADLINE")
with stalls_tick.ping_reserved():
    inside = os.environ.get("STALLS_DEADLINE")
print(before, inside, os.environ.get("STALLS_DEADLINE"))
PY
check "$(env -u CLAUDE_CODE_SESSION_ID -u CLAUDE_UNATTENDED CLAUDE_REPOS_JSON="$S8/noyard.json" STALLS_DEADLINE=5000 python3 "$S13/reserve.py" "$B")" \
  "5000 5000 5000" "no yard: the passes keep ask poll's deadline as it is"
check "$(env -u CLAUDE_CODE_SESSION_ID -u CLAUDE_UNATTENDED STALLS_DEADLINE=5000 python3 "$S13/reserve.py" "$B")" \
  "5000 4960 5000" "a yard: the passes see it 40 s sooner, and it is restored for the ping"
check "$(env -u CLAUDE_UNATTENDED CLAUDE_CODE_SESSION_ID=sess-s13 STALLS_DEADLINE=5000 python3 "$S13/reserve.py" "$B")" \
  "5000 5000 5000" "  a session's tick on a yard (it pings nothing): as it is"
check "$(env -u CLAUDE_CODE_SESSION_ID -u CLAUDE_UNATTENDED -u STALLS_DEADLINE python3 "$S13/reserve.py" "$B")" \
  "None None None" "  no deadline given (an attended tick): none made up"

echo "  the ping's reserved time: every pass ends 40 s before the kill, the ping gets the rest"
cat > "$S13/plumb.py" <<'PY'
import os, sys, types
from importlib.machinery import SourceFileLoader
from importlib.util import module_from_spec, spec_from_loader
sys.path.insert(0, sys.argv[1])
loader = SourceFileLoader("helm_cli_s13", sys.argv[2])
helm = module_from_spec(spec_from_loader(loader.name, loader)); loader.exec_module(helm)
import stalls_tick
seen = []
dl = lambda what: seen.append("%s=%s" % (what, os.environ.get("STALLS_DEADLINE")))
def tick(**kw):
    dl("stalls")
    return {"mode": "armed", "mode_why": "suite", "followups": [], "decisions": [], "notes": [], "hosts": [], "log": "-",
            "wrote": True, "brake": None, "orca_dead": None}
stalls_tick.tick = tick
helm.wharf_once = lambda dry: dl("wharf") or []
stalls_tick.ensure_skippers = lambda mode, brake: dl("skippers") or []
stalls_tick.deadman_ping = lambda **kw: dl("ping") or []
helm.cmd_tick(types.SimpleNamespace(arm=False, disarm=False, status=False, dry_run=False, json=False, by=None))
print(" ".join(seen))
PY
check "$(env -u CLAUDE_CODE_SESSION_ID -u CLAUDE_UNATTENDED HOME="$S13/hd" STALLS_DEADLINE=5000 python3 "$S13/plumb.py" "$B" "$LX/helm" | tail -1)" \
  "stalls=4960 wharf=4960 skippers=4960 ping=5000" "the stalls', wharf's and the skippers' passes under kill - 40 s, the ping under the kill itself"
check "$(env -u CLAUDE_CODE_SESSION_ID -u CLAUDE_UNATTENDED HOME="$S13/hd" CLAUDE_REPOS_JSON="$S8/noyard.json" STALLS_DEADLINE=5000 python3 "$S13/plumb.py" "$B" "$LX/helm" | tail -1)" \
  "stalls=5000 wharf=5000 skippers=5000 ping=5000" "  no yard: every pass keeps the kill time, as before"
rm -f "$S13/seq"
t0=$(now)
out=$(DM_SLEEP=30 STALLS_DEADLINE=$((t0 + 4)) T13)
el=$(( $(now) - t0 ))
check "$(pings13)" "ping testhost" "less than the reserve left: the ping still goes"
has "$out" "deadman: ping failed (TimeoutExpired)" "  with what is left, not its full 40 s"
check "$([ "$el" -lt 20 ] && echo quick || echo "slow: ${el}s")" "quick" "  so the tick ends near the kill time, not 40 s past it"
rm -f "$S13/seq"

echo "  the brake's window: opened by the pass before it, closed by the first pass after, bounded both ways"
cat > "$S13/bw.py" <<'PY'
import json, sys
sys.path.insert(0, sys.argv[1])
import helmlib
t0, step = 10 ** 9, 300
helmlib.note_brake_pass(False, t0)
for i in range(1, 10):
    helmlib.note_brake_pass(True, t0 + i * step)
mid = helmlib.braked_within(t0, t0 + 9 * step)
helmlib.note_brake_pass(False, t0 + 10 * step)
d = json.load(open(helmlib.brake_windows_path()))
print(d["windows"] == [[t0, t0 + 10 * step]], d["since"], mid == 9 * step,
      helmlib.braked_within(t0 - 600, t0 + 20 * step) == 10 * step, helmlib.braked_within(t0 + 20 * step, t0 + 30 * step))
# a tick that goes quiet under the brake: the open window credits BRAKE_LEAD past its last braked pass, no more
helmlib.note_brake_pass(False, t0 + 100 * step)
helmlib.note_brake_pass(True, t0 + 101 * step)
print(helmlib.braked_within(t0 + 100 * step, t0 + 200 * step) == step + helmlib.BRAKE_LEAD)
# a braked pass after the quiet gap: the gap past BRAKE_LEAD is no braked time, a new window opens BRAKE_LEAD back
helmlib.note_brake_pass(True, t0 + 141 * step)
print(helmlib.braked_within(t0 + 101 * step, t0 + 141 * step) == 2 * helmlib.BRAKE_LEAD)
# the first pass ever braked (no record): BRAKE_LEAD back from it
helmlib.brake_windows_path().unlink()
helmlib.note_brake_pass(True, t0)
print(helmlib.brake_windows(t0) == [(t0 - helmlib.BRAKE_LEAD, t0)])
helmlib.brake_windows_path().write_text("{not json")
print(helmlib.braked_within(0, t0))
PY
rm -rf "$S13/bw"; check "$(STALLS_STATE_DIR="$S13/bw" python3 "$S13/bw.py" "$B")" "True None True True 0.0
True
True
True
0.0" "nine braked passes between two plain ones: one window from the pass before to the pass after; an open one bounded, across a quiet tick too; a torn record credits nothing"
rm -rf "$S13/st"; mkdir -p "$S13/st"
"$HM" $SHIP s13b --id s13b > /dev/null; "$HM" task s13b b1 > /dev/null; ll yard s13b dock > /dev/null
: > "$S13/hd/.studio-brake"; T13 > /dev/null
check "$(python3 -c 'import json, sys; d = json.load(open(sys.argv[1])); print(d["since"] is not None, d["windows"])' "$S13/st/brake-windows.json")" \
  "True []" "the tick under the brake, a scope held here: a window opens"
rm -f "$S13/hd/.studio-brake"; T13 > /dev/null
check "$(python3 -c 'import json, sys; d = json.load(open(sys.argv[1])); print(d["since"], len(d["windows"]))' "$S13/st/brake-windows.json")" \
  "None 1" "  the first tick after release closes it"
T13 --dry-run > /dev/null; : > "$S13/hd/.studio-brake"; T13 --dry-run > /dev/null; rm -f "$S13/hd/.studio-brake"
check "$(python3 -c 'import json, sys; d = json.load(open(sys.argv[1])); print(d["since"], len(d["windows"]))' "$S13/st/brake-windows.json")" \
  "None 1" "  a --dry-run tick writes none"

echo "  the skipper's clocks through a brake: frozen time is never charged"
# the lease, an open question re-hailed to the holder by Talk, the holder's registry record idle: all by hand
cat > "$S13/clocks.py" <<'PY'
import json, os, sys, time
sys.path.insert(0, sys.argv[1])
import helmlib, leaselib, skipperlib
pid, case = "s13c", sys.argv[2]
N = time.time()
m = lambda x: N - x * 60
renewed, hailed = {"frozen": (45, 44), "after": (5, 20), "before": (60, 60), "lapse": (50, 50), "none": (45, 44)}[case]
lease = {"holder": "skipper · dock", "scope": "dock", "host": "testhost", "account": None, "gen": 1, "since": m(renewed),
         "until": m(renewed) + leaselib.TTL, "session": "sk-s13", "pid": None, "why": "taken by the suite"}
leaselib._save(pid, lease)
helmlib.append_event(pid, {"task": "b1", "status": "waiting", "ask": "docs/q.md#D1", "summary": "which one", "reversible": "yes",
                           "recommended": "A", "session": "run-9", "repo": "/x/dockrepo", "to": None, "t": m(hailed), "plan": pid})
with helmlib.locked(pid):
    p = helmlib.load_plan(pid)
    p["relayed"] = [{"question": "docs/q.md#D1", "gen": 1, "t": m(hailed), "to": "sk-s13", "backend": "talk", "verdict": "sent", "task": "b1"}]
    helmlib.save_plan(p)
open(os.path.join(os.environ["ASK_SESSIONS_DIR"], "sk-s13.json"), "w").write(json.dumps({"pid": 1, "sessionId": "sk-s13", "status": "idle", "updatedAt": 2}))
# the passes a tick made, five minutes apart: plain before the brake, braked through it, plain after
spans = {"frozen": (45, 0), "after": (80, 20), "before": (55, 35), "lapse": (48, 30), "none": None}[case]
try:
    helmlib.brake_windows_path().unlink()
except OSError:
    pass
if spans:
    a, b = spans
    helmlib.note_brake_pass(False, m(a))
    for k in range(a - 5, b, -5):
        helmlib.note_brake_pass(True, m(k))
    helmlib.note_brake_pass(False, m(b))
# a second on: N less a minute count is not always a whole number of seconds in floats
print(leaselib.lapsed(pid, now=N + 1), skipperlib.deaf(pid, leaselib.read(pid), N + 1))
PY
"$HM" $SHIP s13c --id s13c > /dev/null; "$HM" task s13c b1 > /dev/null
C13() { env -u CLAUDE_CODE_SESSION_ID python3 "$S13/clocks.py" "$B" "$1" 2>&1; }
check "$(C13 none)" "True s13c docs/q.md#D1 unanswered 44m, the session idle" "no brake: 45 minutes since the renewal is lapsed, 44 idle minutes deaf (the clocks as before)"
check "$(C13 frozen)" "False None" "the same skipper frozen 40 minutes under the brake (its passes 40 to 5 minutes ago): on the first pass after release neither lapsed nor deaf"
check "$(C13 after)" "False s13c docs/q.md#D1 unanswered 20m, the session idle" "idle 20 minutes after the release: deaf as before (its lease, renewed since, not lapsed)"
check "$(C13 before)" "True s13c docs/q.md#D1 unanswered 40m, the session idle" "a 20-minute brake inside an hour's silence: only the 40 minutes outside it are charged"
check "$(C13 lapse)" "True s13c docs/q.md#D1 unanswered 32m, the session idle" "a sidecar 50 minutes quiet, 18 of them braked: lapsed on the 32 that were its own"
unset STALLS_DEADLINE DM_SLEEP HELM_DEADMAN HELM_LAUNCHCTL WHARF_LAUNCHCTL STALLS_HARNESS HARNESS_ORCA SURFACES_HOST CLAUDE_REPOS_JSON STALLS_LOG STALLS_STATE_DIR PLAN_NO_SKIPPERS
export PLANS_DIR="$T/plans" SURFACES_FILE="$T/surfaces.json" STALLS_ORCA=0 PLAN_NO_WHARF=1 STALLS_PEERS= STALLS_REPOS= ASK_SESSIONS_DIR="$T/sess"
echo "board-cleanup S1: dead cards drop off, every open PR, Done today, by (repo, branch)"
BC="$T/bc"; mkdir -p "$BC/projects"
for r in alpha beta gamma; do git init -q -b main "$BC/projects/$r"; git -C "$BC/projects/$r" commit -q --allow-empty -m init; done
# gamma: one branch whose change landed through another commit (no PR), one with nothing of its own, one live
G="$BC/projects/gamma"; echo v1 > "$G/f.txt"; git -C "$G" add f.txt; git -C "$G" commit -qm v1
git -C "$G" branch claude/g/empty
git -C "$G" checkout -q -b claude/g/landed; echo v2 > "$G/f.txt"; git -C "$G" commit -qam "v2 on the branch"
git -C "$G" checkout -q -b claude/g/live main; echo mine > "$G/g.txt"; git -C "$G" add g.txt; git -C "$G" commit -qm live
git -C "$G" checkout -q main; echo v2 > "$G/f.txt"; git -C "$G" commit -qam "v2 landed by another branch"
mkdir -p "$BC/projects/alpha/.git/claude"
NOWISO=$(python3 -c 'import datetime; print(datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"))')
OLDISO=$(python3 -c 'import datetime; print((datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=2)).isoformat(timespec="seconds"))')
printf '%s launched claude/a/t #6\n%s launched claude/a/l #9\n%s launched claude/a/m #11\n%s launched claude/a/y #4\n%s stopped claude/a/s held held (x): y\n' \
  "$NOWISO" "$NOWISO" "$NOWISO" "$OLDISO" "$NOWISO" > "$BC/projects/alpha/.git/claude/autofinished"
printf '#!/usr/bin/env python3\nimport json\nprint(json.dumps({"armed": True, "cards": [{"doc": "alpha@claude/x:docs/a.md", "items": ["D1"], "card": "merged one"}, {"doc": "beta@claude/x:docs/b.md", "items": ["D1"], "card": "live one"}]}))\n' > "$BC/keel"
chmod +x "$BC/keel"
cat > "$BC/bc.py" <<'PY'
import datetime as dt, json, os, sys, time
sys.path.insert(0, sys.argv[1])
import helmlib, helm_render as r, stalls
root = sys.argv[2]
top = lambda n: os.path.join(root, n)
helmlib.repo_tops = lambda: {n: [helmlib.Path(top(n))] for n in ("alpha", "beta", "gamma")}
now = time.time()
iso = lambda t: dt.datetime.fromtimestamp(t, dt.timezone.utc).isoformat().replace("+00:00", "Z")
states = {top("alpha"): [
    {"number": 9, "state": "OPEN", "headRefName": "claude/w2", "title": "WIP: idle", "url": "u/a9"},
    {"number": 8, "state": "OPEN", "headRefName": "claude/w1", "title": "held by a session", "isDraft": True, "url": "u/a8"},
    {"number": 7, "state": "OPEN", "headRefName": "claude/o", "title": "ready", "url": "u/a7", "updatedAt": iso(now)},
    {"number": 6, "state": "MERGED", "headRefName": "claude/a/t", "title": "landed today", "url": "u/a6", "mergedAt": iso(now - 60)},
    {"number": 5, "state": "MERGED", "headRefName": "claude/a/y", "title": "landed before", "url": "u/a5", "mergedAt": iso(now - 3 * 86400)},
    {"number": 3, "state": "CLOSED", "headRefName": "claude/c", "title": "closed", "url": "u/a3", "closedAt": iso(now - 86400)},
    {"number": 2, "state": "MERGED", "headRefName": "claude/x", "title": "merged", "url": "u/a2", "headRefOid": "a" * 40,
     "mergedAt": "2026-01-01T00:00:00Z"}],
    top("beta"): [{"number": 4, "state": "OPEN", "headRefName": "claude/x", "title": "same name, open", "url": "u/b4"}],
    top("gamma"): []}
case = sys.argv[3]
if case == "state":
    print(helmlib.branch_ended(states, "alpha", "claude/x"), helmlib.branch_ended(states, "beta", "claude/x"),
          helmlib.branch_ended(states, "alpha", "claude/c"), helmlib.branch_ended(states, "alpha", "claude/o"),
          helmlib.branch_ended(states, "gamma", "claude/x"),
          helmlib.pr_state(states[top("alpha")], "claude/x", "b" * 40, now)[0],
          helmlib.pr_state(states[top("alpha")], "claude/x", "a" * 40, now)[0])
elif case == "stalls":
    def rec(repo, branch, since=None):
        return {"class": "S5", "title": "%s %s" % (repo, branch), "column": helmlib.columns()[0], "repo": repo, "branch": branch,
                "action": "raise", "rule": "r", "evidence": [], "since": since or now - 3600, "host": "testhost"}
    recs = [rec("alpha", "claude/x"), rec("beta", "claude/x"), rec("alpha", "claude/c"), rec("alpha", "claude/o"),
            rec("gamma", "claude/g/landed"), rec("gamma", "claude/g/empty"), rec("gamma", "claude/g/live"),
            rec("beta", "claude/old", now - 8 * 86400), rec("beta", "claude/older", now - 10 * 86400)]
    stalls.judge = lambda **k: {"stalls": recs, "notes": []}
    cards, judged = r.stall_cards(states)
    h = judged["hidden"]
    print([c["title"] for c in cards], h["landed"], h["old"], round((now - h["oldest"]) / 86400), len(judged["stalls"]))
elif case == "asks":
    rows = [{"repo": "alpha", "branch": "claude/x", "rel": "docs/a.md", "item": "D1", "title": "merged"},
            {"repo": "beta", "branch": "claude/x", "rel": "docs/b.md", "item": "D1", "title": "same name, open"},
            {"repo": "alpha", "branch": "claude/c", "rel": "docs/c.md", "item": "D1", "title": "closed"},
            {"repo": "alpha", "branch": "claude/o", "rel": "docs/o.md", "item": "D1", "title": "open"},
            {"repo": "alpha", "branch": "claude/o", "rel": "modules/s/tests/fixtures/p.md", "item": "D1", "title": "fixture"},
            {"repo": "alpha", "branch": "claude/o", "rel": "modules/s/skills/c/TEMPLATE.md", "item": "D1", "title": "template"},
            {"repo": "alpha", "branch": "claude/o", "rel": "docs/shared.md", "item": "D2", "title": "shared, older", "t": 100},
            {"repo": "alpha", "branch": "claude/w1", "rel": "docs/shared.md", "item": "D2", "title": "shared, newer", "t": 200}]
    os.makedirs(os.environ["ASK_CACHE_DIR"], exist_ok=True)
    open(os.path.join(os.environ["ASK_CACHE_DIR"], "asks.json"), "w").write(json.dumps({"asks": rows}))
    print([(c["repo"], c["title"]) for c in r.poll_cards(states)])
elif case == "prs":
    cards, idle = r.pr_cards(states, {("alpha", "claude/w1"), ("beta", "claude/w2")})
    print([(c["repo"], c["title"], c["column"]) for c in cards], idle)
elif case == "done":
    print([(c["repo"], c["title"], c["column"]) for c in r.done_cards(states, root)])
elif case == "lookout":
    print([(c["repo"], c["ref"]) for c in r.lookout_cards(states)])
elif case == "topic":
    print(r.session_topic({"branch": "claude/laptop/2026-10-25-board-cleanup"}), r.session_topic({"cwd": "/p/r/.claude/worktrees/tidy"}),
          r.session_topic({"session_id": "0123456789"}))
PY
BCP() { PLAN_NO_MEMO=1 PLAN_NO_PEER=1 ASK_CACHE_DIR="$BC/askcache" PLAN_KEEL="$BC/keel" python3 "$BC/bc.py" "$B" "$BC/projects" "$1" 2>&1; }
check "$(BCP state)" "merged None closed None None None merged" \
  "(repo, branch): alpha's claude/x merged, beta's open of the same name live; closed; open; no PR; a tip that moved past a merged PR is live, the PR's own head is not"
check "$(BCP stalls)" "['beta claude/x', 'alpha claude/o', 'gamma claude/g/empty', 'gamma claude/g/live'] 3 2 10 9" \
  "stall cards: a merged, a closed and a landed-without-PR branch drop off; the open one, the same name in another repo, a branch with nothing of its own and live work stay; two over 7 days are a count with the oldest's age; judged keeps all 9"
check "$(BCP asks)" "[('beta', 'same name, open'), ('alpha', 'open'), ('alpha', 'shared, newer')]" \
  "ask cards: no merged or closed branch (beta's same name stays), no fixture or template, one card per doc item — the newest branch's"
check "$(BCP prs)" "[('alpha', '#8 held by a session', 'Running'), ('alpha', '#7 ready', 'Needs Sam'), ('beta', '#4 same name, open', 'Needs Sam')] 1" \
  "PR cards: every open PR; a WIP one held by a session (alpha's, not beta's of another branch) Running, the idle one a count; none merged or closed"
check "$(BCP done)" "[('alpha', '#6 landed today', 'Done today'), ('alpha', 'claude/a/m launched as #11', 'Done today')]" \
  "Done today: today's merge, and a launched line of today whose PR is not carded; neither an older merge or launch, a stop, nor a launch whose PR is still open (#9, readied for a tap)"
check "$(BCP lookout)" "[('beta', 'claude/x')]" "lookout cards: one on a merged branch drops off; the same branch name in another repo stays"
hdr=$("$HM" $BOARD --json | python3 -c 'import json,sys; h=json.load(sys.stdin)["header"]; print(sorted(k for k in h if k.startswith(("stalls_", "wip"))))')
check "$hdr" "['stalls_landed', 'stalls_note', 'stalls_old', 'stalls_oldest', 'wip_idle']" "the header counts what the board leaves off"
check "$(BCP topic)" "board-cleanup tidy 01234567" "a waiting card names its topic: the branch's, else the worktree's, else the session"

echo "the canary class (orca-launcher S7): a failing canary beat is the stall \`start path dead\`"
# STALLS_CANARY stands in for `clock canary check --json` (the real one reads this Mac's Orca): its mode file picks the answer
SC="$T/s7c"; mkdir -p "$SC/home" "$SC/st" "$SC/plans"
echo '{"by": "suite", "ts": "x", "t": 0}' > "$SC/st/armed"
cat > "$SC/canary" <<'CANARY_STUB'
#!/bin/sh
d=$(dirname "$0"); echo x >> "$d/calls"
case "$(cat "$d/mode")" in
  bad) cat "$d/bad.json"; exit 1;;
  badexit2) cat "$d/bad.json"; exit 2;;
  ok) echo '{"fails": 0, "host": "testhost", "findings": [{"level": "ok", "text": "canary orca: last beat now"}]}'; exit 0;;
  unread) echo '{"fails": 0, "host": "testhost", "findings": [{"level": "NOTE", "text": "canary: testhost Orca not read (boom): every beat is judged, no automation is"}]}'; exit 0;;
  unreadfail) echo '{"fails": 1, "host": "testhost", "findings": [{"level": "NOTE", "text": "canary: testhost Orca not read (boom): every beat is judged, no automation is"}, {"level": "FAIL", "text": "canary orca: its beat file cannot be read (x)"}]}'; exit 1;;
  garbled) echo "not json"; exit 1;;
  hang) exec sleep 5;;
esac
CANARY_STUB
chmod +x "$SC/canary"
printf '%s' '{"fails": 2, "host": "testhost", "findings": [{"level": "FAIL", "text": "canary orca: no beat in its window — the last was 2026-10-26 01:00, 130 min ago (window 90 min)"}, {"level": "FAIL", "text": "canary orca@acct-a: no beat at all in /x, and its automation canary has run"}, {"level": "ok", "text": "canary other: fine"}]}' > "$SC/bad.json"
echo bad > "$SC/mode"
TKC() { local at=$1; shift; env -u CLAUDE_CODE_SESSION_ID -u CLAUDE_UNATTENDED HOME="$SC/home" REGATTA_CONFIG="$S8/cfg" PLANS_DIR="$SC/plans" STALLS_LOG="$SC/stalls.jsonl" STALLS_STATE_DIR="$SC/st" CLAUDE_REPOS_JSON="$S8/repos.json" ASK_GH_API="$S8/gh" GH_CALLS="$SC/gh.calls" SURFACES_FILE="$S8/surfaces.json" SURFACES_HOST=testhost PLAN_HOST=testhost STALLS_PEERS= STALLS_REPOS= STALLS_ORCA=0 PLAN_NO_SKIPPERS=1 PLAN_NO_WHARF=1 STALLS_CANARY="$SC/canary" STALLS_NOW="$at" "$LX/helm" tick "$@" 2>&1; }
cgh() { [ -e "$SC/gh.calls" ] && wc -l < "$SC/gh.calls" | tr -d ' ' || echo 0; }
ccall() { python3 - "$SC/gh.calls" "$1" "$2" <<'PY'
import json, sys
c = [json.loads(x) for x in open(sys.argv[1])][int(sys.argv[2])]
print(eval(sys.argv[3], {"c": c, "b": c["body"]}))
PY
}
N0=$(now)
out=$(TKC "$N0")
has "$out" "start path dead testhost  canary orca: raised" "a failing canary beat is a raised stall of the class, one per beat"
has "$out" 'key ["testhost", "canary", "orca"]' "  keyed by host and beat"
has "$out" "2 stalls, 0 unsure — 2 raise" "  the ok finding is none"
check "$(cgh)" "0" "  first seen now: no issue yet"
out=$(TKC $((N0 + 700)))
has "$out" "escalated stall on testhost: canary orca · start path dead (the canary fails): github-issue #100" "11 minutes: one issue per beat, through the stall road"
check "$(cgh)" "2" "  two beats, two issues"
check "$(ccall 0 'b["body"].split(chr(10))[0]')" "@someone-x" "  the body starts with the config's mention (a stall alert mentions the owner)"
has "$(ccall 0 'b["body"]')" '- key: `["testhost", "canary", "orca"]`' "  and names the beat's key"
has "$(ccall 0 'b["body"]')" "- class: start path dead" "  its class"
out=$(TKC $((N0 + 1000))); check "$(cgh)" "2" "  the next tick: no second issue"
echo unread > "$SC/mode"
out=$(TKC $((N0 + 1500))); out=$(TKC $((N0 + 2100)))
check "$(cgh)" "2" "an Orca the check could not read, two passes: no issue closed on an absence it cannot vouch for"
echo ok > "$SC/mode"
out=$(TKC $((N0 + 2700))); check "$(cgh)" "2" "every beat inside its window, read: gone one pass is no clear"
out=$(TKC $((N0 + 3400)))
has "$out" "escalation closed (#100): stall on testhost: canary orca · start path dead (the canary fails) — no longer judged a stall here" "  gone 10 minutes, read: closed"
check "$(cgh)" "6" "  a comment and a close for each of the two"
echo bad > "$SC/mode"
check "$(env HOME="$SC/home" REGATTA_CONFIG="$S8/cfg" PLANS_DIR="$SC/plans" STALLS_LOG="$SC/stalls.jsonl" STALLS_STATE_DIR="$SC/st" PLAN_HOST=testhost STALLS_PEERS= STALLS_REPOS= STALLS_ORCA=0 PLAN_NO_WHARF=1 PLAN_NO_PEER=1 STALLS_CANARY="$SC/canary" "$HM" $BOARD --json | python3 -c '
import json, sys
found = []
def walk(x):
    if isinstance(x, dict):
        if x.get("stall") == "start path dead": found.append((x["title"], x["column"], x["action"], x["by"]))
        for v in x.values(): walk(v)
    elif isinstance(x, list):
        for v in x: walk(v)
walk(json.load(sys.stdin)); print(sorted(found))')" \
  "[('canary orca · start path dead (the canary fails)', 'Needs Sam', 'raise', 'testhost'), ('canary orca@acct-a · start path dead (the canary fails)', 'Needs Sam', 'raise', 'testhost')]" \
  "the board: a card per beat, in the owner's column, raised"
cat > "$SC/unit.py" <<'PY'
import os, sys, time
sys.path.insert(0, sys.argv[1])
import stalls
sc = sys.argv[2]
def mode(m): open(sc + "/mode", "w").write(m)
def calls(): return len(open(sc + "/calls").read().split()) if os.path.exists(sc + "/calls") else 0
out = []
def case(name, held=None, dead=None):
    notes = []
    before = calls()
    s, read = stalls.judge_canary("testhost", time.time(), notes, held, dead)
    out.append("%s:%d:%s:%d:%s" % (name, len(s), read, calls() - before, "|".join(n[:48] for n in notes)))
    return s
mode("ok"); case("ok")
mode("bad"); s = case("bad")
m = [(x["class"], x["action"], x["raise_to"], x["key"], x["key_kind"], x["guarded"], x["column"] if "column" in x else None) for x in s]
out.append(str(m[0]))
mode("badexit2"); case("exit2")
mode("unreadfail"); case("unreadfail")
mode("garbled"); case("garbled")
mode("bad"); case("brake", held="the brake file")
os.environ["STALLS_CANARY"] = "0"; case("off")
del os.environ["STALLS_CANARY"]; os.environ["STALLS_ORCA"] = "0"; case("orca-off")
os.environ["STALLS_CANARY"] = sc + "/canary"; stalls.CANARY_TIMEOUT = 1; mode("hang"); case("hang")
print(" ".join(out))
PY
cat > "$SC/unit2.py" <<'PY'
import os, sys, time
sys.path.insert(0, sys.argv[1])
import stalls
sc = sys.argv[2]
def mode(m): open(sc + "/mode", "w").write(m)
def calls(): return len(open(sc + "/calls").read().split()) if os.path.exists(sc + "/calls") else 0
out = []
def case(name, dead=None):
    notes = []
    before = calls()
    s, read = stalls.judge_canary("testhost", time.time(), notes, None, dead)
    out.append("%s:%d:%s:%d:%s" % (name, len(s), read, calls() - before, "|".join(n[:44] for n in notes)))
    return s
mode("bad")
case("dead", dead="Orca did not answer")
real = stalls.helmlib.brake_windows
stalls.helmlib.brake_windows = lambda t=None: [(time.time() - 3600, time.time() - 600)]
case("brake-ended")
stalls.helmlib.brake_windows = lambda t=None: [(time.time() - 3 * 3600, time.time() - 2 * 3600)]
case("brake-long-ago")
stalls.helmlib.brake_windows = real
class Conf:
    def registry_unreadable(self): return False
    def confidential_scopes(self): return {"work": {"login": "acct-a", "confidential": True}}
stalls.helmlib._common = lambda: Conf()
s = case("guarded")
out.append(",".join("%s=%s" % (x["beat"], x["guarded"]) for x in s))
class Torn(Conf):
    def registry_unreadable(self): return True
stalls.helmlib._common = lambda: Torn()
out.append(",".join("%s=%s" % (x["beat"], x["guarded"]) for x in case("torn")))
# the episode: the same stale beat a pass later is the same instance, a new last beat a new one
a = stalls.CANARY_AGO_RE.sub("", "canary orca: no beat in its window, the last was 2026-10-26 01:00, 130 min ago")
b = stalls.CANARY_AGO_RE.sub("", "canary orca: no beat in its window, the last was 2026-10-26 01:00, 135 min ago")
c = stalls.CANARY_AGO_RE.sub("", "canary orca: no beat in its window, the last was 2026-10-26 04:00, 95 min ago")
out.append("episode:%s:%s:%s" % (s[0]["run"].startswith("episode "), a == b, a != c))
os.environ["STALLS_CANARY"] = "1"; os.environ["STALLS_ORCA"] = "0"; case("one")
print(" ".join(out))
PY
check "$(env HOME="$SC/home" STALLS_CANARY="$SC/canary" python3 "$SC/unit2.py" "$B" "$SC")" \
  "dead:0:False:0:canary: not read — Orca did not answer this  brake-ended:0:False:0:canary: not judged — the studio brake ended  brake-long-ago:2:True:1: guarded:2:True:1: orca=False,orca@acct-a=True torn:2:True:1: orca=False,orca@acct-a=True episode:True:True:True one:0:False:0:" \
  "judge_canary: an Orca dead this pass, or a brake ended under a beat's window ago, reads nothing and calls nothing; a confidential scope's login, or a torn registry, guards its beat; the run is the episode, its minutes aside; STALLS_CANARY=1 is the default read, never a command"
check "$(env HOME="$SC/home" STALLS_CANARY="$SC/canary" python3 "$SC/unit.py" "$B" "$SC")" \
  "ok:0:True:1: bad:2:True:1: ('start path dead', 'raise', 'owner', ['testhost', 'canary', 'orca'], 'canary', False, None) exit2:2:False:1:canary: clock canary check exit 2 — its failures unreadfail:1:False:1: garbled:0:False:1:canary: the \`start path dead\` class not judged ( brake:0:False:0:canary: not read — the studio brake holds (the b off:0:False:0: orca-off:0:False:0: hang:0:False:1:canary: the \`start path dead\` class not judged (" \
  "judge_canary: a pass is read with no stall; a failing beat raised to the owner; a check that exits 2 still raises but reads nothing; an Orca it could not read raises what it did read and closes nothing; unreadable or hung output costs the class, said in a note; the brake, STALLS_CANARY=0 and the Orca read off call nothing"

echo "dispatch-queue S9: a build step's dependency met at landed, not at done; compile's after map; the queue's after cards"
AF="$T/s9"; mkdir -p "$AF"
G=(git -c user.name=t -c user.email=t@t)
git init -q --bare "$AF/origin.git"; git clone -q "$AF/origin.git" "$AF/repo" 2>/dev/null
(cd "$AF/repo" && echo x > f && "${G[@]}" add f && "${G[@]}" commit -qm init && git push -q origin HEAD:main 2>/dev/null)
(cd "$AF/repo" && git checkout -q -b claude/laptop/2026-10-29-sa && echo a > a && "${G[@]}" add a && "${G[@]}" commit -qm build && git push -q origin claude/laptop/2026-10-29-sa 2>/dev/null)
cat > "$AF/dep.py" <<'PY'
import json, sys, time
sys.path.insert(0, sys.argv[1])
import helmlib
repo, branch = sys.argv[2], "claude/laptop/2026-10-29-sa"
helmlib.load_plan = lambda pid: {"id": pid, "repo": repo, "tasks": {
    "a": {"branch": branch}, "b": {"deps": ["a"]}, "h": {"kind": "human", "deps": ["a"]},
    "x": {}, "c": {"deps": ["x"]}, "l": {"branch": "claude/laptop/2026-10-29-sl"}, "m": {"deps": ["l"]}}}
now = time.time()
helmlib.events = lambda pid: [{"task": "a", "status": "done", "t": now}, {"task": "x", "status": "done", "t": now},
                              {"task": "l", "status": "launched", "t": now}]
t = {x["id"]: x for x in helmlib.state("s9")["tasks"]}
print(t["b"]["blockers"], t["h"]["blockers"], t["c"]["blockers"], t["m"]["blockers"])
PY
check "$(python3 "$AF/dep.py" "$B" "$AF/repo")" "['waits on a to land'] [] [] []" \
  "a build step waits on a built (done) build step to land; a human task, a dep with no branch and a launched one keep today's meaning"
(cd "$AF/repo" && { git checkout -q main 2>/dev/null || git checkout -q -b main origin/main; } && "${G[@]}" merge -q --no-ff -m land claude/laptop/2026-10-29-sa && git push -q origin main 2>/dev/null && git fetch -q origin)
check "$(python3 "$AF/dep.py" "$B" "$AF/repo")" "[] [] [] []" \
  "  its branch merged on origin/main (read without a fetch, its own commits seen in the reflog): met — wharf-runs' landed.py, dispatch's reader"
cat > "$AF/pub.py" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import helmlib
helmlib.load_plan = lambda pid: {"id": pid, "tasks": {"a": {"branch": "claude/x/2026-10-29-a"}, "b": {"deps": ["a"], "after_branches": ["claude/x/2026-10-29-a"]}}}
helmlib.events = lambda pid: []
st = helmlib.state("s9p")
print([t["after_branches"] for t in st["tasks"] if t["id"] == "b"], [("after_branches" in t) for t in helmlib.public(st)["tasks"]])
PY
check "$(python3 "$AF/pub.py" "$B")" "[['claude/x/2026-10-29-a']] [False, False]" "state carries a task's after_branches; the public copy drops them (another task's branch, a guarded one's among them)"
cat > "$AF/course.md" <<'EOF'
# Course

## Action plan

- **S1 — the base** · session `sr-worker` · status: done 2026-10-29 claude/laptop/2026-10-29-cs1
- **S2 — on top** · session `worker` · after: S1 · status: not started
- **S3 — dropped** · session `worker` · status: superseded 2026-10-29 by S1, claude/laptop/2026-10-29-cs3
- **S4 — after the dropped** · session `worker` · after: S3 · status: not started
EOF
"$HM" $SHIP s9course --id s9c > /dev/null
"$HM" compile s9c "$AF/course.md" > /dev/null
check "$("$HM" state s9c | python3 -c 'import json,sys; d={t["id"]: t for t in json.load(sys.stdin)["tasks"]}; print(d["S1"]["branch"], d["S2"]["after_branches"], d["S2"]["blockers"])')" \
  "claude/laptop/2026-10-29-cs1 ['claude/laptop/2026-10-29-cs1'] ['waits on S1 to land']" \
  "compile: a step's branch from its status line, after: S1 mapped to that branch, and S2 waits on S1 to land"
check "$("$HM" state s9c | python3 -c 'import json,sys; d={t["id"]: t for t in json.load(sys.stdin)["tasks"]}; print(d["S3"]["superseded"], d["S4"]["blockers"])')" \
  "True []" "  a superseded step never lands: its dependant waits on no landing (code review, pass 2)"
sed -i.bak 's|status: done 2026-10-29 claude/laptop/2026-10-29-cs1$|status: done 2026-10-30 claude/laptop/2026-10-30-cs1b, after claude/laptop/2026-10-29-cs1|' "$AF/course.md" && rm -f "$AF/course.md.bak"
"$HM" compile s9c "$AF/course.md" > /dev/null
check "$("$HM" state s9c | python3 -c 'import json,sys; d={t["id"]: t for t in json.load(sys.stdin)["tasks"]}; print(d["S1"]["branch"], d["S2"]["after_branches"])')" \
  "claude/laptop/2026-10-30-cs1b ['claude/laptop/2026-10-30-cs1b']" \
  "  re-compiled after a re-seed: the branch after the status word and its date, read again (code review, pass 3)"
mkdir -p "$AF/home/Library/Logs/claude-weekly"
python3 - "$AF/home/Library/Logs/claude-weekly/queue.jsonl" <<'PY'
import json, sys, time
now = time.time()
rows = [{"at": now - 600, "event": "card", "card": "after-gone", "key": "fleet:repo--step", "branch": "claude/laptop/2026-10-29-step",
         "after": "claude/laptop/2026-10-29-pre", "repo": "demo", "why": "step waits on pre, which is deleted from origin"},
        {"at": now - 9 * 86400, "event": "card", "card": "after-overdue", "key": "fleet:repo--old", "branch": "claude/laptop/2026-10-29-old",
         "after": "claude/laptop/2026-10-29-pre", "repo": "demo", "why": "old"},
        {"at": now - 60, "event": "card", "card": "queue-stuck", "key": "fleet:repo--x", "branch": "claude/laptop/2026-10-29-x"}]
open(sys.argv[1], "w").write("".join(json.dumps(r) + "\n" for r in rows))
PY
cat > "$AF/cards.py" <<'PY'
import sys, time
sys.path.insert(0, sys.argv[1])
import stalls
held = stalls.judge_after_cards("testhost", time.time(), lambda repo, br: True)
gone = stalls.judge_after_cards("testhost", time.time(), lambda repo, br: False)
s = held[0]
print(len(held), s["class"], s["action"], s["key"], s["evidence"][:2], len(gone))
PY
check "$(HOME="$AF/home" python3 "$AF/cards.py" "$B")" \
  "1 S6 raise ['testhost', 'fleet:repo--step', 'claude/laptop/2026-10-29-pre'] ['step claude/laptop/2026-10-29-step', 'after claude/laptop/2026-10-29-pre'] 0" \
  "stalls: the queue's after card is one raised S6 naming both branches, while the queue holds the step; a week-old card and other cards none"

check "$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import helmlib; t = {"tax return": "guarded-1", "tax": "guarded-2"}
print([helmlib._tokened(b, t) for b in ("waits on tax return", "waits on tax return to land", "waits on tax", "waits on taxes")])' "$B")" \
  "['waits on guarded-1', 'waits on guarded-1 to land', 'waits on guarded-2', 'waits on taxes']" \
  "public: a guarded id is swapped whole, a space in it included, in both blocker forms (the S9 review: a first-word match leaked it)"

echo "helm yard-on: name a host a scope's yard once its tick drives and no blueprint ship of the scope is in flight here (TODO.md [arm-yard] (b))"
YO="$T/yo"; mkdir -p "$YO/bin" "$YO/plans" "$REGATTA_CONFIG/lighthouse"
printf 'laptop\nyardbox\n' > "$REGATTA_CONFIG/lighthouse/hosts"
echo '{"repos": {"demo": {}, "other": {}}, "scopes": {"s1": {"repos": ["demo"]}, "s2": {"repos": ["other"]}}}' > "$YO/repos.json"
# ssh answers `helm tick --status` as YO_TICK says; the rest is the real helm store and wharf's real scopes
printf '#!/bin/sh\n[ "$YO_TICK" = down ] && { echo "ssh: connect refused" >&2; exit 255; }\necho "helm tick: $YO_TICK — stub"\n' > "$YO/bin/ssh"
chmod +x "$YO/bin/ssh"
cat > "$YO/age.py" <<'PY'
import json, sys, time
from pathlib import Path
d = Path(sys.argv[1]); p = json.loads((d / "plan.json").read_text()); p["repo"] = sys.argv[2]
if sys.argv[3] == "1":
    p["tasks"]["a"]["provider"] = "claude-code"
at = time.time() - 60 * int(sys.argv[4])
p["updated"] = at   # the ship's updated is the newest of its events and the plan's own save
(d / "plan.json").write_text(json.dumps(p))
ev = d / "events.jsonl"
ev.write_text("".join(json.dumps(dict(json.loads(l), t=at)) + "\n" for l in ev.read_text().splitlines() if l.strip()))
PY
yo() { env -u CLAUDE_UNATTENDED -u REGATTA_UNATTENDED PLANS_DIR="$YO/plans" CLAUDE_REPOS_JSON="$YO/repos.json" \
         HARNESS_SSH="$YO/bin/ssh" HARNESS_HOST=laptop HARNESS_PEER_YARDBOX=yard-stub "$@" > "$YO/out" 2>&1; echo $?; }
# yship <id> <repo> <blueprint 0|1> <status> <minutes ago>: one task, laid by wharf (a blueprint field) or not
yship() {
  PLANS_DIR="$YO/plans" "$HM" ship "t-$1" --id "$1" > /dev/null; PLANS_DIR="$YO/plans" "$HM" task "$1" a > /dev/null
  PLANS_DIR="$YO/plans" PLAN_NO_RENDER=1 "$HM" report "$1" --task a --status "$4" > /dev/null
  python3 "$YO/age.py" "$YO/plans/$1" "$2" "$3" "$5"
}
check "$(yo env YO_TICK=armed "$HM" yard-on yardbox s1 --dry-run) $(grep -c 'scopes set s1 --yard yardbox' "$YO/out")" "0 1" "--dry-run: the command printed, both checks pass, nothing written"
check "$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["scopes"]["s1"].get("yard"))' "$YO/repos.json")" "None" "  the registry untouched"
check "$(yo env YO_TICK=disarmed "$HM" yard-on yardbox s1)" "1" "a disarmed yard tick: refused"
has "$(cat "$YO/out")" "yardbox's tick is not armed" "  and says why"
check "$(yo env YO_TICK=down "$HM" yard-on yardbox s1)" "1" "an unreachable yard: refused, never read as armed"
yship skip1 demo 0 running 5
check "$(yo env YO_TICK=armed "$HM" yard-on yardbox s1 --dry-run)" "0" "a typed session's ship running here (no blueprint task): not in flight for the fence (the laptop's refusals, 2026-11-01)"
yship bp1 other 1 running 5
check "$(yo env YO_TICK=armed "$HM" yard-on yardbox s1 --dry-run)" "0" "  a blueprint ship of another scope: not this arming's"
yship bp2 demo 1 running 3000
check "$(yo env YO_TICK=armed "$HM" yard-on yardbox s1 --dry-run)" "1" "a blueprint ship of the scope with a task running, however old: in flight, refused"
has "$(cat "$YO/out")" "blueprint ships of these scopes in flight here: t-bp2 (bp2" "  naming the ship"
rm -rf "$YO/plans/bp2"; yship bp3 demo 1 planned 30
check "$(yo env YO_TICK=armed "$HM" yard-on yardbox s1 --dry-run)" "1" "  one updated 30 minutes ago with a task to do: refused"
check "$(yo env YO_TICK=armed "$HM" yard-on yardbox s1 --dry-run --within 0.1)" "0" "  --within with fewer hours clears a parked one"
rm -rf "$YO/plans/bp3"
# a task's repo is the path wharf writes, looked up by its registry key as the fence does: a nested key
# (`org/sub`) of another scope is not this arming's, one of this scope is (the landing review, 2026-11-02)
P="$(hl "helmlib._common().PROJECTS")"
echo '{"repos": {"demo": {}, "other": {}, "org/sub": {}, "org/mine": {}, "loose": {}}, "scopes": {"s1": {"repos": ["demo", "org/mine"]}, "s2": {"repos": ["other", "org/sub"]}}}' > "$YO/repos.json"
yship nest1 "$P/org/sub" 1 running 5
check "$(yo env YO_TICK=armed "$HM" yard-on yardbox s1 --dry-run)" "0" "a blueprint ship of a nested key in another scope: not this arming's"
yship nest2 "$P/org/mine" 1 running 5
check "$(yo env YO_TICK=armed "$HM" yard-on yardbox s1 --dry-run)" "1" "  one of a nested key in this scope: in flight, refused"
rm -rf "$YO/plans/nest1" "$YO/plans/nest2"; yship loose1 "$P/loose" 1 running 5
check "$(yo env YO_TICK=armed "$HM" yard-on yardbox s1 --dry-run)" "0" "a blueprint ship of a repo in no scope: the fence refuses nothing there, not in flight"
rm -rf "$YO/plans/loose1"; yship out1 /nowhere/else 1 running 5
check "$(yo env YO_TICK=armed "$HM" yard-on yardbox s1 --dry-run)" "1" "  one outside the projects folder: its scope cannot be told, counts"
rm -rf "$YO/plans/out1"
echo '{"repos": {"demo": {}, "other": {}}, "scopes": {"s1": {"repos": ["demo"]}, "s2": {"repos": ["other"]}}}' > "$YO/repos.json"
check "$(yo env YO_TICK=armed CLAUDE_UNATTENDED=dispatch "$HM" yard-on yardbox s1)" "2" "an unattended caller: refused before anything is written"
check "$(yo env YO_TICK=armed CLAUDE_UNATTENDED=dispatch "$HM" yard-on yardbox s1 --dry-run)" "0" "  a dry run is open to it"
check "$(yo env YO_TICK=armed HARNESS_HOST=yardbox "$HM" yard-on yardbox s1)" "1" "run on the yard itself: refused"
check "$(yo env YO_TICK=dry "$HM" yard-on yardbox s1) $(python3 -c 'import json, sys; d = json.load(open(sys.argv[1]))["scopes"]; print(d["s1"].get("yard"), d["s2"].get("yard"))' "$YO/repos.json")" \
  "0 yardbox None" "the tick in its dry hours, nothing in flight: written through scopes, read back, the other scope untouched"
has "$(cat "$YO/out")" "1 scope(s) read back as yard yardbox" "  and it says so"
check "$(yo env YO_TICK=armed "$HM" yard-on yardbox nope)" "3" "a scope the registry lacks: scopes refuses, exit 3"

echo "charterer S1: the charter events in the store, state()'s charterers with the Talk road's lapse, the yard's helm charter"
# docs/charterer-2026-11-01.md S1. The verb runs on the yard over ssh, where the shell carries no session id:
# every case passes --by, as S5's charterer side will, with CLAUDE_CODE_SESSION_ID cleared
CH="$LX/helm"
"$CH" ship chartered-demo --id ch1 >/dev/null; "$CH" task ch1 build >/dev/null; "$CH" task ch1 docs >/dev/null
out=$(CLAUDE_CODE_SESSION_ID= "$CH" charter --join ch1 --by sess-a --from laptop --road talk); check "$?" "0" "charter --join: exit 0"
check "$out" "ship ch1: chartered-demo chartered by sess-a@laptop (talk)" "  it names the ship, the charterer, its Mac and its road"
check "$(python3 -c 'import json, sys; e = [json.loads(x) for x in open(sys.argv[1])][-1]; print(e.get("charter"), e.get("charterer"), e.get("charterer_host"), e.get("road"), "task" in e)' "$PLANS_DIR/ch1/events.jsonl")" \
  "chartered sess-a laptop talk False" "  one ship-level event in the store: charter, charterer, its host, its road, no task"
CLAUDE_CODE_SESSION_ID= "$CH" charter --join ch1 --by sess-b --from yard-1 >/dev/null
CLAUDE_CODE_SESSION_ID=sess-c "$CH" charter --join ch1 >/dev/null
chst() { "$CH" state ch1 | python3 -c "import json, sys; d = json.load(sys.stdin); print($1)"; }
check "$(chst '[(r["session"], r["host"], r["road"]) for r in d["charterers"]]')" \
  "[('sess-a', 'laptop', 'talk'), ('sess-b', 'yard-1', None), ('sess-c', 'testhost', None)]" \
  "state(): charterers in join order; --by and --from default to this session and this Mac"
check "$(chst '[t["updated"] for t in d["tasks"]]')" "[None, None]" "  a charter is no task's news (no task's updated moves)"
has "$("$CH" show ch1)" "charterers: sess-a@laptop by talk, renewed" "helm show names the charterers"
check "$("$CH" state ch1 --public | python3 -c 'import json, sys; d = json.load(sys.stdin); print(sorted({k for r in d["charterers"] for k in r}))')" \
  "['renewed', 'road', 'since']" "public(): a charterer's session id and host never leave the Mac"
hasnt "$("$CH" state ch1 --public)" "sess-a" "  no charterer's session id anywhere in the public copy"
out=$(CLAUDE_CODE_SESSION_ID= "$CH" charter --join ch1 --by sess-b --from yard-1); check "$out" "ship ch1: chartered-demo renewed by sess-b@yard-1" "a second --join of a live charterer renews it"
check "$(chst 'len(d["charterers"])')" "3" "  still one row per session"
CLAUDE_CODE_SESSION_ID= "$CH" charter --renew ch1 --by sess-a --road socket >/dev/null; check "$?" "0" "charter --renew of a charterer: exit 0"
check "$(chst '[(r["road"], r["host"]) for r in d["charterers"] if r["session"] == "sess-a"]')" "[('socket', 'laptop')]" \
  "  a renewal may name a new road; one with no --from keeps the Mac it joined from (never the yard's own name)"
CLAUDE_CODE_SESSION_ID= "$CH" charter --renew ch1 --by sess-a --from laptop-2 >/dev/null
check "$(chst '[r["host"] for r in d["charterers"] if r["session"] == "sess-a"]')" "['laptop-2']" "  one with --from moves it"
out=$(CLAUDE_CODE_SESSION_ID= "$CH" charter --renew ch1 --by sess-z 2>&1); check "$?" "7" "charter --renew of a session not chartering: exit 7"
has "$out" "sess-z is not chartering ship ch1 — join it again (--join)" "  it says to join again"
check "$(chst '[r["session"] for r in d["charterers"]]')" "['sess-a', 'sess-b', 'sess-c']" "  and adds no charterer"
out=$(CLAUDE_CODE_SESSION_ID= "$CH" charter --leave ch1 --by sess-b); check "$?/$out" "0/ship ch1: sess-b left" "charter --leave: exit 0"
check "$(chst '[(r["session"], r["why"]) for r in d["charterers_gone"]]')" "[('sess-b', 'left')]" "  the session moves to charterers_gone, why left"
out=$(CLAUDE_CODE_SESSION_ID= "$CH" charter --leave ch1 --by sess-b); check "$?/$out" "0/ship ch1: sess-b was not chartering it (left)" "  a second leave: exit 0, said with why it is none, nothing written"
out=$(CLAUDE_CODE_SESSION_ID= "$CH" charter --renew ch1 --by sess-b 2>&1); check "$?" "7" "  a renewal after the leave: exit 7"
has "$out" "(left)" "  naming why it is no charter"
CLAUDE_CODE_SESSION_ID= "$CH" charter --join ch1 --by sess-b --from yard-1 >/dev/null
check "$(chst '[r["session"] for r in d["charterers"]]')" "['sess-a', 'sess-c', 'sess-b']" "a join after the leave is a new charter, last in join order"
# every unattended marker refuses a join and a renewal, and writes nothing; a leave stays any caller's
n0=$(wc -l < "$PLANS_DIR/ch1/events.jsonl")
for m in REGATTA_UNATTENDED CLAUDE_UNATTENDED AUTOFINISH_CALLER_UNATTENDED DISPATCH_LABEL CLAUDE_CODE_DISABLE_BACKGROUND_TASKS \
         DISPATCH_DEPTH DISPATCH_SHIP DISPATCH_PLAN; do
  out=$(env "$m=dispatch" CLAUDE_CODE_SESSION_ID= "$CH" charter --join ch1 --by sess-u 2>&1); check "$?" "6" "charter --join under $m: refused, exit 6"
  has "$out" "refused in an unattended caller ($m=dispatch)" "  naming the marker"
  out=$(env "$m=dispatch" CLAUDE_CODE_SESSION_ID= "$CH" charter --renew ch1 --by sess-a 2>&1); check "$?" "6" "  --renew under $m: refused too"
done
check "$(wc -l < "$PLANS_DIR/ch1/events.jsonl")" "$n0" "  no refused call wrote an event"
out=$(DISPATCH_DEPTH=0 CLAUDE_CODE_SESSION_ID= "$CH" charter --join ch1 --by sess-d --from laptop); check "$?" "0" "  a DISPATCH_DEPTH of 0 is a typed session's: chartered"
CLAUDE_CODE_SESSION_ID= "$CH" charter --leave ch1 --by sess-d >/dev/null
out=$(CLAUDE_UNATTENDED=tick CLAUDE_CODE_SESSION_ID= "$CH" charter --leave ch1 --by sess-c --why "hail: the session has ended"); check "$?" "0" "a leave under an unattended marker goes (the charter pass's, S4)"
check "$(chst '[r["why"] for r in d["charterers_gone"] if r["session"] == "sess-c"]')" "['hail: the session has ended']" "  its why is kept"
check "$(python3 -c 'import json, sys; e = [json.loads(x) for x in open(sys.argv[1])][-1]; print(e["charter"], "charterer_host" in e)' "$PLANS_DIR/ch1/events.jsonl")" \
  "charter left False" "  a leave writes no host"
out=$(CLAUDE_CODE_SESSION_ID= "$CH" charter --renew ch1 --by sess-c --json 2>/dev/null); check "$?" "7" "  a renewal after it: exit 7"
check "$(printf '%s' "$out" | python3 -c 'import json, sys; r = json.load(sys.stdin)[0]; print(r["cause"])')" "left" \
  "  its cause is left, never the leave's free text (which stays in why)"
check "$(HARNESS_HOST='bad:host name' CLAUDE_CODE_SESSION_ID= "$CH" charter --leave ch1 --by sess-c)" "ship ch1: sess-c was not chartering it (left)" \
  "  a leave reads no host of this Mac's: one that is no host name never refuses it"
check "$("$CH" state ch1 --public | python3 -c 'import json, sys; print(sorted({r.get("why") for r in json.load(sys.stdin)["charterers_gone"]}))')" "['left']" \
  "  public(): a free-text why leaves as left (only left, lapsed, ended leave as they are)"
out=$(CLAUDE_CODE_SESSION_ID= "$CH" charter --join ch1 --by 'bad id' 2>&1); check "$?" "2" "a --by that is no session id: a usage error, exit 2"
out=$(CLAUDE_CODE_SESSION_ID= "$CH" charter --join ch1 --by "$(printf 'sess-a\nx')" 2>&1); check "$?" "2" "  one with a newline in it too"
out=$(CLAUDE_CODE_SESSION_ID= "$CH" charter --join ch1 --by $'sess-a\n' 2>&1); check "$?" "2" "  one ending in a newline (fullmatch, never \$)"
out=$(CLAUDE_CODE_SESSION_ID= "$CH" charter --join ch1 --by sess-a --from "laptop
" 2>&1); check "$?" "2" "  a --from with a trailing newline too (fullmatch, never \$)"
out=$(CLAUDE_CODE_SESSION_ID= "$CH" charter --join ch1 2>&1); check "$?" "2" "no --by and no session: refused"
has "$out" "pass --by <session id>" "  it says what to pass"
out=$(CLAUDE_CODE_SESSION_ID= "$CH" charter --join ch1 --by sess-a --why x 2>&1); check "$?" "2" "--why on a join: refused (a leave's)"
out=$(CLAUDE_CODE_SESSION_ID= "$CH" charter --join nosuch --by sess-a 2>&1); check "$?" "6" "no such ship: refused, exit 6"
# a Talk REPORT is a task's news: charter keys in one are dropped, so no REPORT charters past the verb's refusals
cat > "$T/report.py" <<'PY'
import importlib.machinery, importlib.util, json, sys
sys.path.insert(0, sys.argv[1])
spec = importlib.util.spec_from_loader("askcli", importlib.machinery.SourceFileLoader("askcli", sys.argv[1] + "/ask"))
ask = importlib.util.module_from_spec(spec); spec.loader.exec_module(ask)
import helmlib
ok, _ = ask.append_report(json.dumps({"plan": "ch1", "progress": "p", "charter": "chartered", "charterer": "sess-r", "charterer_host": "x"}))
e = helmlib.events("ch1")[-1]
again, _ = ask.append_report(json.dumps({"plan": "ch1", "progress": "p"}))
print(ok, "charter" in e, "charterer" in e, e.get("progress"), [r["session"] for r in helmlib.state("ch1")["charterers"] if r["session"] == "sess-r"], again)
PY
check "$(python3 "$T/report.py" "$B" 2>&1)" "True False False p [] False" \
  "ask's REPORT intake drops a charter's keys from a ship-level REPORT: no charterer; the same body without them is its replay"
# several ships in one call (one ssh call per yard, S5): each answered, the first refusal's code returned
"$CH" ship other-demo --id ch2 >/dev/null; "$CH" task ch2 work >/dev/null
out=$(CLAUDE_CODE_SESSION_ID= "$CH" charter --join ch2 nosuch ch1 --by sess-m --from laptop 2>&1); check "$?" "6" "--join of several ships: the refusal's exit"
has "$out" "ship ch2: other-demo chartered by sess-m@laptop" "  the open ship before it chartered"
has "$out" "ship ch1: chartered-demo chartered by sess-m@laptop" "  and the one after it too"
check "$(CLAUDE_CODE_SESSION_ID= "$CH" charter --renew ch1 nosuch ch2 --by sess-m --json 2>/dev/null | python3 -c 'import json, sys; print([(r["plan"], r["verdict"], r["cause"]) for r in json.load(sys.stdin)])')" \
  "[('ch1', 'renewed', None), ('nosuch', 'refused', 'no-ship'), ('ch2', 'renewed', None)]" "--json: one verdict per ship, with its cause, for a caller with several"
# one ship's torn read (an event whose time is no number) costs the others nothing: its row says error, exit 1
"$CH" ship torn-demo --id ch6 >/dev/null; "$CH" task ch6 work >/dev/null
echo '{"t": "noon", "task": "work", "status": "running"}' >> "$PLANS_DIR/ch6/events.jsonl"
out=$(CLAUDE_CODE_SESSION_ID= "$CH" charter --renew ch6 ch1 --by sess-m --json 2>/dev/null); check "$?" "1" "a ship whose state() raises: exit 1, could not tell"
check "$(printf '%s' "$out" | python3 -c 'import json, sys; print([(r["plan"], r["verdict"]) for r in json.load(sys.stdin)])')" \
  "[('ch6', 'error'), ('ch1', 'renewed')]" "  the ship after it renewed, and every ship has its row"
CLAUDE_CODE_SESSION_ID= "$CH" charter --renew ch6 ch1 --by sess-zz >/dev/null 2>&1; check "$?" "1" "  a crash (1) and a not-chartering (7): 1, the graver"
CLAUDE_CODE_SESSION_ID= "$CH" charter --renew ch1 ch6 --by sess-zz >/dev/null 2>&1; check "$?" "1" "  in either order"
CLAUDE_CODE_SESSION_ID= "$CH" charter --renew ch1 nosuch --by sess-zz >/dev/null 2>&1; check "$?" "6" "  a not-chartering (7) and a refusal (6) in one call: 6"
CLAUDE_CODE_SESSION_ID= "$CH" charter --renew nosuch ch1 --by sess-zz >/dev/null 2>&1; check "$?" "6" "  in either order"
# a failed block may be started again, a built one with a branch is not landed yet: neither ends the ship
"$CH" report ch2 --task work --status failed --progress "the build broke" >/dev/null
check "$(CLAUDE_CODE_SESSION_ID= "$CH" charter --join ch2 --by sess-f --from laptop)" "ship ch2: other-demo chartered by sess-f@laptop" "a ship whose block failed has not ended (a retry may come): chartered"
"$CH" task ch2 work --branch claude/x/2026-11-01-work >/dev/null
"$CH" report ch2 --task work --status done >/dev/null
check "$(CLAUDE_CODE_SESSION_ID= "$CH" charter --join ch2 --by sess-g --from laptop)" "ship ch2: other-demo chartered by sess-g@laptop" "  nor one whose block with a branch is done, not landed"
# an ended ship refuses a join and a renewal, naming its end; a leave still goes
"$CH" report ch2 --task work --status launched >/dev/null
out=$(CLAUDE_CODE_SESSION_ID= "$CH" charter --join ch2 --by sess-n 2>&1); check "$?" "6" "charter --join of an ended ship: refused, exit 6"
has "$out" "ship ch2 has ended (every block ended: work launched)" "  naming its end"
out=$(CLAUDE_CODE_SESSION_ID= "$CH" charter --renew ch2 --by sess-m 2>&1); check "$?" "6" "  a renewal of an ended ship: refused, so the charterer stops"
out=$(CLAUDE_CODE_SESSION_ID= "$CH" charter --leave ch2 --by sess-m); check "$?/$out" "0/ship ch2: sess-m left" "  a leave of an ended ship goes"
"$CH" ship landed-demo --id ch3 >/dev/null; "$CH" task ch3 work >/dev/null
"$CH" report ch3 --task work --status launched >/dev/null
python3 - "$PLANS_DIR/ch3/plan.json" <<'PY'
import json, sys
p = json.load(open(sys.argv[1])); p["tasks"]["work"]["pr"] = "https://example.invalid/pull/12"; json.dump(p, open(sys.argv[1], "w"))
PY
has "$(CLAUDE_CODE_SESSION_ID= "$CH" charter --join ch3 --by sess-n 2>&1)" "every block ended: work launched https://example.invalid/pull/12" "  a launched block's end names its PR"
# wharf closes a ship's record once every block is done (its ENDED), before a branch lands: its close is the
# end only where the blocks have ended too
"$CH" ship closed-demo --id ch4 >/dev/null; "$CH" task ch4 work --branch claude/x/2026-11-01-closed >/dev/null
"$CH" report ch4 --task work --status done >/dev/null
python3 - "$PLANS_DIR/ch4/plan.json" <<'PY'
import json, sys
p = json.load(open(sys.argv[1])); p["blueprints"] = {"bp": {"ended": 1, "orca_run": "r1"}}; json.dump(p, open(sys.argv[1], "w"))
PY
check "$(CLAUDE_CODE_SESSION_ID= "$CH" charter --join ch4 --by sess-n --from laptop 2>&1)" "ship ch4: closed-demo chartered by sess-n@laptop" \
  "  a ship wharf closed at done, its branch not landed: not ended, chartered (the charterer waits to hear the landing)"
"$CH" report ch4 --task work --status launched >/dev/null
has "$(CLAUDE_CODE_SESSION_ID= "$CH" charter --join ch4 --by sess-o 2>&1)" "ship ch4 has ended (wharf closed its blueprint record)" "  once launched too, wharf's close is named as the end"
# block_ended's roads, one block each (landed.py's verdict stood in for: the suite has no clone to prove from)
cat > "$T/ended.py" <<'PY'
import importlib.machinery, importlib.util, sys
sys.path.insert(0, sys.argv[1])
spec = importlib.util.spec_from_loader("helmcli", importlib.machinery.SourceFileLoader("helmcli", sys.argv[2]))
h = importlib.util.module_from_spec(spec); spec.loader.exec_module(h)
import helmlib
said = {}
helmlib.dep_landed = lambda t, plan: (said.get(t["branch"], "unknown"), "")
B = lambda status, **k: dict({"status": status, "kind": "session", "branch": None, "superseded": False, "blueprint": None}, **k)
said["claude/x/landed"] = "landed"
rows = [("launched", B("launched")), ("failed", B("failed")), ("planned superseded", B("planned", superseded=True)),
        ("done human", B("done", kind="human")), ("done shell", B("done", blueprint={"provider": "shell"})),
        ("done no branch", B("done")), ("done branch held", B("done", branch="claude/x/held")),
        ("done branch landed", B("done", branch="claude/x/landed")), ("running", B("running", branch="claude/x/landed"))]
print("; ".join("%s %s" % (n, h.block_ended(t, {})) for n, t in rows))
PY
check "$(python3 "$T/ended.py" "$B" "$LX/helm" 2>&1)" \
  "launched True; failed False; planned superseded True; done human True; done shell True; done no branch False; done branch held False; done branch landed True; running False" \
  "block_ended: launched, superseded, or done where done is its end or its branch landed; never failed, nor a session block done with no branch or one not landed"
"$CH" ship bare-demo --id ch7 >/dev/null
python3 - "$PLANS_DIR/ch7/plan.json" <<'PY'
import json, sys
p = json.load(open(sys.argv[1])); p["blueprints"] = {"bp": {"ended": 1}}; json.dump(p, open(sys.argv[1], "w"))
PY
check "$(CLAUDE_CODE_SESSION_ID= "$CH" charter --join ch7 --by sess-n --from laptop 2>&1)" "ship ch7: bare-demo chartered by sess-n@laptop" \
  "a ship wharf closed with no block: not ended, as ship_end reads it"
# the end is read again under the lock: a last block launched (and wharf's close) between the first read and the
# lock refuses the join, and writes nothing
"$CH" ship racing-demo --id ch8 >/dev/null; "$CH" task ch8 work >/dev/null; "$CH" report ch8 --task work --status running >/dev/null
cat > "$T/inlock.py" <<'PY'
import contextlib, importlib.machinery, importlib.util, json, sys
sys.path.insert(0, sys.argv[1])
spec = importlib.util.spec_from_loader("helmcli", importlib.machinery.SourceFileLoader("helmcli", sys.argv[2]))
h = importlib.util.module_from_spec(spec); spec.loader.exec_module(h)
import helmlib
real = helmlib.locked


@contextlib.contextmanager
def racing(pid):
    helmlib.append_event(pid, {"task": "work", "status": "launched"})
    with real(pid):
        yield


helmlib.locked = racing
code, verdict, cause, _ = h.charter_one("--join", "ch8", "sess-l", "laptop", None, None, "laptop")
print(code, verdict, cause, [e for e in helmlib.events("ch8") if e.get("charter")])
PY
check "$(python3 "$T/inlock.py" "$B" "$LX/helm" 2>&1)" "6 refused ended []" "  a block launched between the first read and the lock: refused under the lock, nothing written"
"$CH" ship fresh-demo --id ch5 >/dev/null
check "$(CLAUDE_CODE_SESSION_ID= "$CH" charter --join ch5 --by sess-n --from laptop)" "ship ch5: fresh-demo chartered by sess-n@laptop" "a ship with no block yet has not ended: chartered"
printf '[]\nnull\n"x"\n' >> "$PLANS_DIR/ch5/events.jsonl"
out=$(CLAUDE_CODE_SESSION_ID= "$CH" charter --leave ch5 --by sess-n); check "$?/$out" "0/ship ch5: sess-n left" \
  "  valid JSON that is no object breaks no charter read: the leave still goes (the landing review)"
# the lapse, from events at fixed times (CHARTER_LAPSE, 900 s): every road but socket and mailbox lapses
cat > "$T/lapse.py" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import helmlib
E = lambda t, kind, sid, **k: dict({"t": t, "charter": kind, "charterer": sid}, **k)
evs = [E(1000, "chartered", "talk-1", road="talk"), E(1000, "chartered", "sock-1", road="socket"),
       E(1000, "chartered", "mail-1", road="mailbox"), E(1600, "charter renewed", "talk-1")]
# today no road reads an end back (hail's verdicts carry no `ended`): every charter lapses, socket and mailbox too
print(helmlib.CHARTER_SEES_END, [(r["session"], r["gone"]) for r in helmlib.charterers(evs, 99999)[1]])
# the roads a later step names (S2's mailbox, S4's socket read) stop lapsing: the rest below runs as if both were
helmlib.CHARTER_SEES_END = ("socket", "mailbox")
for at in (1600 + 899, 1600 + 901, 99999):
    live, gone = helmlib.charterers(evs, at)
    print(at - 1600, [r["session"] for r in live], [(r["session"], r["why"], r["gone"]) for r in gone])
# a renewal that comes after the lapse is no charter: the session joins again
live, gone = helmlib.charterers(evs + [E(1600 + 1000, "charter renewed", "talk-1")], 1600 + 1001)
print([r["session"] for r in live], [(r["session"], r["why"]) for r in gone])
live, _ = helmlib.charterers(evs + [E(1600 + 1000, "chartered", "talk-1", road="talk")], 1600 + 1001)
print([(r["session"], r["since"]) for r in live if r["session"] == "talk-1"])
# a road that changes to talk lapses from then on; one that changes away stops lapsing
live, gone = helmlib.charterers([E(0, "chartered", "x", road="talk"), E(100, "charter renewed", "x", road="socket")], 5000)
print([r["session"] for r in live], len(gone))
live, gone = helmlib.charterers([E(0, "chartered", "x", road="socket"), E(100, "charter renewed", "x", road="talk")], 1001)
print([r["session"] for r in live], [(r["why"], r["gone"]) for r in gone])
# no road named, and a road hail reads no end on (codex), lapse as talk does; a road hail has not is ignored
live, gone = helmlib.charterers([E(0, "chartered", "n"), E(0, "chartered", "c", road="codex"), E(0, "chartered", "s", road="socket"),
                                 E(0, "chartered", "b", road="bogus", charterer_host=7)], 10 ** 7)
print([(r["session"], r["road"], r["host"]) for r in live], [(r["session"], r["why"]) for r in gone])
# a stray renewal or leave (no join before it), an unknown kind, a charterer that is no string, a task's line, a
# line a wire intake wrote (via, wire): nothing; a task line whose time is no number breaks nothing
print(helmlib.charterers([E(0, "charter renewed", "y"), E(0, "charter left", "z"), E(0, "charter joined", "w"),
                          {"t": 0, "charter": "chartered", "charterer": 7}, E(0, "chartered", "v", task="build"),
                          E(0, "chartered", "u", via="talk"), E(0, "chartered", "q", wire="k1"),
                          {"t": "noon", "task": "x", "status": "running"}], 10))
print([r["session"] for r in helmlib.charterers([{"t": "noon", "task": "x"}, E(5, "chartered", "ok")], 10)[0]])
# the file's order, never the stamps (the closing review): a rejoin written after a leave stamped ahead of it is live;
# a renewal stamped behind its join counts from its own stamp; a leave whose time is no number still leaves
live, gone = helmlib.charterers([E(0, "chartered", "k"), E(5000, "charter left", "k"), E(100, "chartered", "k")], 200)
print([(r["session"], r["since"]) for r in live], gone)
live, gone = helmlib.charterers([E(1000, "chartered", "x"), E(500, "charter renewed", "x")], 1450)
print([r["session"] for r in live], [(r["session"], r["why"], r["gone"]) for r in gone])
live, gone = helmlib.charterers([E(1000, "chartered", "k"), {"t": "noon", "charter": "charter left", "charterer": "k"}], 1200)
print([r["session"] for r in live], [(r["session"], r["why"]) for r in gone])
PY
check "$(python3 "$T/lapse.py" "$B")" "() [('talk-1', 2500), ('sock-1', 1900), ('mail-1', 1900)]
899 ['talk-1', 'sock-1', 'mail-1'] []
901 ['sock-1', 'mail-1'] [('talk-1', 'lapsed', 2500)]
98399 ['sock-1', 'mail-1'] [('talk-1', 'lapsed', 2500)]
['sock-1', 'mail-1'] [('talk-1', 'lapsed')]
[('talk-1', 2600)]
['x'] 0
[] [('lapsed', 1000)]
[('s', 'socket', None)] [('n', 'lapsed'), ('c', 'lapsed'), ('b', 'lapsed')]
([], [])
['ok']
[('k', 100)] []
[] [('x', 'lapsed', 1400)]
[] [('k', 'left')]" "charterers(): every charter lapses 15 min after its last renewal, at that time, today; a road CHARTER_SEES_END names never does; a late renewal is no charter, a join a new one; only the verb's own lines count"
python3 - "$PLANS_DIR/ch1/events.jsonl" <<'PY'
import json, sys, time
open(sys.argv[1], "a").write(json.dumps({"t": time.time() - 3600, "charter": "chartered", "charterer": "sess-old", "charterer_host": "laptop", "road": "talk"}) + "\n")
PY
check "$(chst '[r["session"] for r in d["charterers"] if r["session"] == "sess-old"], [r["why"] for r in d["charterers_gone"] if r["session"] == "sess-old"]')" \
  "[] ['lapsed']" "state(): a Talk charterer an hour unrenewed reads lapsed"
out=$(CLAUDE_CODE_SESSION_ID= "$CH" charter --renew ch1 --by sess-old 2>&1); check "$?" "7" "  its renewal: exit 7"
has "$out" "(lapsed)" "  naming the lapse"
check "$(CLAUDE_CODE_SESSION_ID= "$CH" charter --leave ch1 --by sess-old --json 2>/dev/null | python3 -c 'import json, sys; r = json.load(sys.stdin)[0]; print(r["verdict"], r["cause"])')" \
  "not-chartering lapsed" "  its leave: not chartering, cause lapsed (as the renewal reads it)"
check "$(CLAUDE_CODE_SESSION_ID= "$CH" charter --leave ch1 --by sess-never --json 2>/dev/null | python3 -c 'import json, sys; r = json.load(sys.stdin)[0]; print(r["verdict"], r["cause"])')" \
  "not-chartering never" "  a leave of a session that never joined: cause never"
# a usage error under --json still gives a row per ship; this Mac's name, when it is no host name, is said as such
out=$(CLAUDE_CODE_SESSION_ID= "$CH" charter --join ch1 ch5 --json 2>/dev/null); check "$?" "2" "--json with no --by: a usage error, exit 2"
check "$(printf '%s' "$out" | python3 -c 'import json, sys; print([(r["plan"], r["verdict"], r["cause"]) for r in json.load(sys.stdin)])')" \
  "[('ch1', 'error', 'usage'), ('ch5', 'error', 'usage')]" "  and a row per ship on stdout, for a caller that reads the rows"
out=$(HARNESS_HOST='bad host' CLAUDE_CODE_SESSION_ID= "$CH" charter --join ch1 --by sess-h 2>&1); check "$?" "2" "a join with no --from where this Mac's name is no host name: exit 2"
has "$out" "this Mac's name 'bad host'" "  naming this Mac's name, never a --from it was not given"
out=$(HARNESS_HOST='bad host' CLAUDE_CODE_SESSION_ID= "$CH" charter --renew ch1 --by sess-a 2>&1); check "$?" "0" "  a bare renewal there goes: it writes no host (the closing review)"
check "$(chst '[r["host"] for r in d["charterers"] if r["session"] == "sess-a"]')" "['laptop-2']" "  and keeps the Mac it had"
# a clock that stepped back (a Linux yard's can): a rejoin after a leave stamped later still reads as after it
"$CH" ship clock-demo --id ch9 >/dev/null; "$CH" task ch9 work >/dev/null
CLAUDE_CODE_SESSION_ID= "$CH" charter --join ch9 --by sess-k --from laptop >/dev/null
CLAUDE_CODE_SESSION_ID= "$CH" charter --join ch9 --by sess-x --from laptop >/dev/null
python3 -c 'import json, sys, time; open(sys.argv[1], "a").write(json.dumps({"t": time.time() + 2000, "charter": "charter left", "charterer": "sess-k", "why": "left"}) + "\n")' "$PLANS_DIR/ch9/events.jsonl"
out=$(CLAUDE_CODE_SESSION_ID= "$CH" charter --join ch9 --by sess-k --from laptop); check "$?/$out" "0/ship ch9: clock-demo chartered by sess-k@laptop" \
  "a join after a leave stamped ahead of this clock: chartered (the closing review)"
check "$("$CH" state ch9 | python3 -c 'import json, sys; d = json.load(sys.stdin); print([r["session"] for r in d["charterers"]], [r["session"] for r in d["charterers_gone"]])')" \
  "['sess-x', 'sess-k'] []" "  and state() reads it live: the file's order, never the stamps', orders a session's lines"
out=$(CLAUDE_CODE_SESSION_ID= "$CH" charter --renew ch9 --by sess-x); check "$?/$out" "0/ship ch9: clock-demo renewed by sess-x@laptop" \
  "  another charterer's renewal goes: one session's line ahead of the clock lapses nobody else"
check "$("$CH" state ch9 | python3 -c 'import json, sys; d = json.load(sys.stdin); print([r["session"] for r in d["charterers"]])')" \
  "['sess-x', 'sess-k']" "  and state() still reads both live"

echo "helm-board S2: the Decide feed's state — the fields, the queue, Later, the guard, the deploy check"
S2B="$T/s2board"; mkdir -p "$S2B/ask" "$S2B/plan"
cat > "$S2B/s2.py" <<'PY'
import sys, os, json, time
sys.path.insert(0, sys.argv[1])
import helm_render as r, helmlib
r._KEEL[:] = [None]   # no keel pins here: no course link, no frame
own = helmlib.columns()[0]
sec = lambda w: {"crumb": "The road", "above": w, "table": None, "item": "- **D1 — x**"}
rows = [{"repo": "alpha", "branch": "claude/a", "rel": "docs/a.md", "item": "D1", "title": "waits", "t": 300, "hash": "h-a1",
         "section": sec("why a"), "options": [["A", "fast"]], "line": 12, "step_waits": ["S2"], "worktree": "projects/alpha",
         "summary": "the doc a", "doc_title": "Doc A", "recommended": "A", "reversible": "yes", "sha": "abc"},
        {"repo": "alpha", "branch": "claude/a", "rel": "docs/a.md", "item": "D2", "title": "second", "t": 300, "hash": "h-a2",
         "section": sec("why a2"), "line": 30, "summary": "the doc a", "doc_title": "Doc A"},
        {"repo": "beta", "branch": "claude/b", "rel": "docs/b.md", "item": "D1", "title": "one way", "t": 200, "hash": "h-b1",
         "section": sec("why b"), "line": 5, "reversible": "no", "doc_title": "Doc B"},
        {"repo": "gamma", "branch": "claude/g", "rel": "docs/g.md", "item": "D4", "title": "old", "t": 100, "hash": "h-g4",
         "section": sec("why g"), "line": 9, "doc_title": "Doc G"},
        {"repo": "gamma", "branch": "claude/g", "rel": "docs/s.md", "item": "D1", "title": "snoozed", "t": 50, "hash": "h-s1", "line": 3},
        {"repo": "gamma", "branch": "claude/g", "rel": "docs/c.md", "item": "D1", "title": "changed since", "t": 60, "hash": "h-new", "line": 3},
        {"repo": "gamma", "branch": "claude/g", "rel": "docs/w.md", "item": "D1", "title": "woke", "t": 70, "hash": "h-w1", "line": 3}]
open(os.path.join(os.environ["ASK_CACHE_DIR"], "asks.json"), "w").write(json.dumps({"asks": rows}))
cards = r.poll_cards({})
a = cards[0]
print(a["key"], a["rel"], a["item"], a["hash"], a["line"], a["step_waits"], a["worktree"], a["summary"], a["doc_title"], a["sha"], "frame" in a, a["updated"])
cards += [r._card("pr", "#7 ready", own, repo="alpha", url="https://github.com/o/alpha/pull/7"),
          r._card("stall", "S6 deaf 3h", own, repo="beta", session="s-1"),
          r._card("human", "call the bank", own, repo="alpha", by="sam"),
          r._card("task", "Pick the look", own, plan_id="p1", repo="alpha"),
          r._card("lookout", "docs/x.md D9", own, repo="alpha", doc="alpha@claude/x:docs/x.md"),
          r._card("lookout", "docs/x.md D10", own, repo="alpha", doc="alpha@claude/x:docs/x.md"),
          r._card("ask", "secret", own, repo="vault", ref="docs/v.md#D1", branch="claude/v", guarded=True, key="vault@claude/v:docs/v.md#D1",
                  section=sec("private words"), summary="private", hash="h-v", worktree="projects/vault", rel="docs/v.md")]
r.key_cards([c for c in cards if c["column"] == own])
r.strip_guarded(cards)
g = cards[-1]
print(sorted(g), g["key"].startswith("guarded:"), "private" in json.dumps(g) or "docs/v.md" in json.dumps(g))
print([c["key"] for c in cards if c["kind"] == "lookout"])
now = time.time()
later = [{"key": "gamma@claude/g:docs/s.md#D1", "hash": "h-s1", "kind": "snooze", "until": None, "at": "t"},
         {"key": "gamma@claude/g:docs/c.md#D1", "hash": "h-old", "kind": "snooze", "until": None, "at": "t"},
         {"key": "gamma@claude/g:docs/w.md#D1", "hash": "h-w1", "kind": "snooze", "until": helmlib.iso(now - 60), "at": "t"},
         {"key": "pr:https://github.com/o/alpha/pull/7", "hash": r.card_hash(cards[7]), "kind": "done", "at": "t"},
         {"key": "stall:beta/s-1", "hash": r.card_hash(dict(cards[8], title="S2 quiet 1h")), "kind": "done", "at": "t"},
         {"kind": "snooze"}, "junk"]
open(r.board_state_file(), "w").write(json.dumps({"later": later}))
q, lat = r.decide_queue(cards, r.read_later())
print([(d["key"], d["open"], d["why"]) for d in q["docs"]])
print(q["docs"][0]["items"], q["docs"][0]["summary"], q["docs"][0]["title"], q["docs"][0]["worktree"],
      [(k, ["GUARDED" if x == g["key"] else x for x in v]) for k, v in q["groups"]])
print([(x["key"], x["kind"]) for x in lat])
st = lambda cs, lt=(): {"columns": [{"name": own, "cards": cs}], "header": {}, "later": list(lt)}
base = [dict(a)]
moved = [dict(a, hash="h-a1b")]
pick = [dict(a, recommended="B")]
lock = [dict(a, reversible="no")]
print(r.board_sig(st(base)) == r.board_sig(st([dict(a, updated="later")])), r.board_sig(st(base)) != r.board_sig(st(moved)),
      r.board_sig(st(base)) != r.board_sig(st(pick)), r.board_sig(st(base)) != r.board_sig(st(lock)),
      r.board_sig(st(base)) != r.board_sig(st(base, [{"key": "k"}])))
# a ship's ask (its task names a worktree's folder, or no repo) and the poll's card of the same item: one card
ship = [r._card("ask", "D1", own, plan_id="p1", task="t1", ref="docs/a.md#D1", repo=r.repo_name("/x/alpha/.claude/worktrees/wt")),
        r._card("ask", "D2", own, plan_id="p2", task="t2", ref="docs/g.md#D4"),
        r._card("task", "Review", own, plan_id="p1", task="t3"), r._card("task", "Review", own, plan_id="p2", task="t3"),
        r._card("task", "Review", own, plan_id="p2", title2="x")]
merged = r.absorb_polled(ship, r.poll_cards({}))
r.key_cards([c for c in merged if c["column"] == own])
keys = [c["key"] for c in merged]
print(len(merged), len(keys) == len(set(keys)), merged[0]["key"], merged[0]["repo"], merged[0].get("section", {}).get("above"),
      merged[1]["key"], merged[1]["repo"], keys[2:5])
PY
check "$(ASK_CACHE_DIR="$S2B/ask" PLAN_CACHE_DIR="$S2B/plan" python3 "$S2B/s2.py" "$B" 2>&1)" \
  "alpha@claude/a:docs/a.md#D1 docs/a.md D1 h-a1 12 ['S2'] projects/alpha the doc a Doc A abc False 300
['column', 'guarded', 'hash', 'key', 'kind', 'repo', 'title'] True False
['lookout:alpha@claude/x:docs/x.md|docs/x.md D9', 'lookout:alpha@claude/x:docs/x.md|docs/x.md D10']
[('alpha@claude/a:docs/a.md', 2, '↑ first: S2 waits on D1'), ('beta@claude/b:docs/b.md', 1, 'holds 1 irreversible'), ('gamma@claude/g:docs/c.md', 1, 'oldest first'), ('gamma@claude/g:docs/w.md', 1, 'oldest first'), ('gamma@claude/g:docs/g.md', 1, 'oldest first')]
['alpha@claude/a:docs/a.md#D1', 'alpha@claude/a:docs/a.md#D2'] the doc a Doc A projects/alpha [('unstick', ['stall:beta/s-1', 'lookout:alpha@claude/x:docs/x.md|docs/x.md D9', 'lookout:alpha@claude/x:docs/x.md|docs/x.md D10']), ('people', ['human:alpha/call the bank']), ('tasks', ['task:p1/Pick the look']), ('other', ['GUARDED'])]
[('gamma@claude/g:docs/s.md#D1', 'snooze'), ('pr:https://github.com/o/alpha/pull/7', 'done')]
True True True True True
10 True alpha@claude/a:docs/a.md#D1 alpha why a gamma@claude/g:docs/g.md#D4 gamma ['task:p1/t3', 'task:p2/t3', 'task:p2/Review']" \
  "an ask card carries the poll's fields and its key; a guarded card keeps its column and repo, a digest key, and none of its doc's words; two lookout cards of one doc keep two keys; the queue's docs in order (an S-step waits, one way, then oldest) with their reason, the doc's items by line under its title and Summary, the other cards by what they need; Later holds a snooze while its hash stands and a done, never a changed item or a woken one; the deploy check moves with the hash, the pick, the lock and Later, never an age; a done stall that changed comes back; a ship's ask and the poll's card of its item are one card with the poll's key and repo (a worktree's folder, no repo at all), and every key in the column is its own"

echo "helm-board S2: the ship ladder's data — due, the projected ETA and its slip, the hill, where the money comes from"
LAD="$T/s2ladder"; mkdir -p "$LAD"
# the doc a ship compiled from: two D-items, one answered (the hill's uphill)
printf '# Doc\n\n## Decisions\n\n- **D1 — one?**\n  - A — a\n  - B — b\n\n  Reversible: yes\n\n  ➤ Recommended: A\n\n  ➤ Answer:\n  A\n\n- **D2 — two?**\n  - A — a\n  - B — b\n\n  Reversible: yes\n\n  ➤ Recommended: A\n\n  ➤ Answer:\n\n' > "$LAD/d.md"
cat > "$LAD/lad.py" <<'PY'
import sys, json
sys.path.insert(0, sys.argv[1])
import helmlib, helm_render as r
H = 3600.0
at = 1_800_000_000.0
def task(i, status="planned", **kw):
    return dict({"id": i, "title": i, "status": status, "deps": [], "eta": None, "started": None, "updated": None,
                 "cost": None, "est_to_go": None, "est_kind": None, "asks": [], "blockers": []}, **kw)
# a built (4 h), b built (2 h): the step length is their median, 3 h
built = [task("a", "done", started=at - 10 * H, updated=at - 6 * H, cost=1.0),
         task("b", "landed", started=at - 6 * H, updated=at - 4 * H, cost=0.5)]
st = {"id": "s", "due": at + 24 * H, "started": at - 10 * H, "cost": None, "totals": {"cost": 2.0, "est_to_go": 3.0},
      "tasks": built + [
          task("c", "running", deps=["b"], eta=at + 2 * H, started=at - H, cost=0.5, est_to_go=1.0, est_kind="manager"),
          task("d", deps=["c"]),                                   # no ETA: one step after c
          task("e", deps=["d"], eta=at + 3 * H,                    # its ETA is before d ends: pushed
               asks=[{"ref": "docs/d.md#D2", "open": True}]),
          task("f", eta=at - H, status="running", started=at - 5 * H),   # past its ETA: now
          task("g", "failed", started=at - 3 * H, updated=at - 2 * H),   # a fix round owed: projected from now
          task("x", superseded=True)]}
ends, step, src = helmlib.task_ends(st, at)
print(int(step / H), src, {k: (round((v[0] - at) / H, 1), v[1]) for k, v in sorted(ends.items()) if k not in ("a", "b")})
lad = helmlib.ladder(st, at, (1, 2))
print(round((lad["eta"] - at) / H, 1), lad["slip_days"], lad["late"], lad["shipped"], lad["eta_from"], lad["assumes_answered"])
print(lad["hill"], lad["spent"], lad["est_to_go"], lad["est"], lad["est_from"], lad["to_go_from"], lad["cost_from"])
# late: due an hour from now; the ship's own cost to deliver stands for the estimate
late = helmlib.ladder(dict(st, due=at + H, cost=9.0), at)
print(late["slip_days"], late["late"], late["est"], late["est_from"], late["hill"]["decisions"])
# shipped: every step built — no ETA, the slip is the last step's against due
done = helmlib.ladder({"id": "s", "due": at - 24 * H, "totals": {}, "tasks": built}, at)
print(done["eta"], round((done["shipped"] - at) / H, 1), done["slip_days"], done["late"], done["hill"]["steps"])
# no due, no steps, no ETA anywhere: nothing guessed but the default step length
none = helmlib.ladder({"id": "s", "totals": {}, "tasks": []}, at)
print(none["due"], none["eta"], none["slip_days"], none["shipped"], none["step_len_from"], none["hill"])
lone = helmlib.ladder({"id": "s", "totals": {}, "tasks": [task("only")]}, at)
print(round((lone["eta"] - at) / H, 1), lone["step_len_from"], lone["eta_from"])
# a cycle is cut where it closes; a dependency the ship does not hold adds nothing
cyc = helmlib.task_ends({"tasks": [task("p", deps=["q"]), task("q", deps=["p", "zz"])]}, at)[0]
print(sorted((k, round((v[0] - at) / H, 1)) for k, v in cyc.items()))
# the docs' decision counts: keel's parse of the ship's docs; one that does not read counts nothing
print(r.doc_decision_counts([sys.argv[2], sys.argv[2] + ".gone"]), r.doc_decision_counts([sys.argv[2] + ".gone"]), r.doc_decision_counts([]))
# timeline() carries the ladder and each bar's projected end
row = r.timeline([dict(st, ladder=lad, milestones=[])], at)[0]
bars = {b["id"]: (round((b["end"] - at) / H, 1), b["projected"]) for b in row["bars"]}
print(row["ladder"]["slip_days"], bars["a"], bars["c"], bars["d"], bars["e"], bars["f"], bars["g"])
PY
check "$(python3 "$LAD/lad.py" "$B" "$LAD/d.md" 2>&1)" \
"3 the median of 2 built steps {'c': (2.0, 'eta'), 'd': (5.0, 'projected'), 'e': (8.0, 'pushed'), 'f': (0.0, 'overrun'), 'g': (3.0, 'projected')}
8.0 -0.7 False None {'eta': 1, 'overrun': 1, 'projected': 2, 'pushed': 1} ['D2']
{'decisions': [1, 2], 'steps': [2, 7]} 2.0 3.0 5.0 its steps {'none': 4, 'skipper': 1} {'reported': 3, 'unreported': 2}
0.3 True 9.0 the ship (helm ship --cost) None
None -4.0 0.8 True [2, 2]
None None None None the default {'decisions': None, 'steps': [0, 0]}
3.0 the default {'projected': 1}
[('p', 6.0), ('q', 3.0)]
(1, 2) None None
-0.7 (-6.0, None) (2.0, None) (5.0, 'projected') (8.0, 'pushed') (0.0, 'overrun') (3.0, 'projected')" \
  "the step length is the built steps' median; each open step ends along the dependency order — its ETA, now when that passed, one step after a dependency that ends past it, one step after it may start with none (a failed step's fix round too); the ship's ETA is the last, its slip in days against due, the open decisions it takes as answered; the hill: answered of all decisions from the docs, built of all steps, a superseded one in neither; the money: spent, to go and the estimate, each with its source, and the steps begun with no cost reported; late, shipped and empty ships; a cycle is cut where it closes; the timeline's row carries the ladder and each bar its projected end"
echo "  helm show and the ship's page carry the ladder"
"$HM" $SHIP ladder --id lad-1 --due 2099-01-01 > /dev/null
"$HM" task lad-1 one --title One > /dev/null
python3 -c "
import json, sys; p = sys.argv[1]; d = json.load(open(p)); d['tasks']['one']['doc'] = sys.argv[2]; json.dump(d, open(p, 'w'))" "$PLANS_DIR/lad-1/plan.json" "$LAD/d.md"
out=$("$HM" show lad-1)
has "$out" "(1 projected) " "  the ETA and how it was reached"
has "$out" "hill 1/2 decided, 0/1 built" "  the hill, its decisions read from the ship's doc"
has "$out" "from its steps; 0 steps report cost" "  where the money comes from"
"$HM" render lad-1 > /dev/null 2>&1
check "$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d['ladder']['hill'], d['ladder']['due'] is not None, 'docs' in d)" "$T/cache/lad-1/state.json")" \
  "{'decisions': [1, 2], 'steps': [0, 1]} True False" "  the ship's page carries the ladder, the hill read from its doc, never the doc's path"
hasnt "$(cat "$T/cache/lad-1/state.json")" "$LAD" "  no path of the doc in the page's state"

echo "helm-board S2, review round 1: the projection's floors, the built time, the stream's copy, the guard, the keys"
cat > "$LAD/r1.py" <<'PY'
import sys, json, os
sys.path.insert(0, sys.argv[1])
import helmlib, helm_render as r
H = 3600.0
at = 1_800_000_000.0
def task(i, status="planned", **kw):
    return dict({"id": i, "title": i, "status": status, "deps": [], "eta": None, "started": None, "updated": None,
                 "cost": None, "est_to_go": None, "est_kind": None, "asks": [], "blockers": []}, **kw)
# built 3 h each (built_at); a's landing 20 h later never lengthens the step nor moves its end
a = task("a", "landed", started=at - 30 * H, built_at=at - 27 * H, updated=at - 7 * H)
b = task("b", "done", started=at - 12 * H, built_at=at - 9 * H, updated=at - 9 * H)
ends, step, _ = helmlib.task_ends({"tasks": [a, b,
    task("late", deps=["b"], eta=at - 10 * H),                  # its dependency ended past its ETA, but in the past: now
    task("run", "running", deps=["a"], started=at - 2.5 * H)]}, at)  # under way 2.5 h, its dependency built: 0.5 h to go
print(int(step / H), round((ends["a"][0] - at) / H, 1), ends["late"][1], round((ends["late"][0] - at) / H, 1),
      ends["run"][1], round((ends["run"][0] - at) / H, 1))
# state() keeps the first DONE time; a reopened step is built again later
helmlib.load_plan = lambda pid: {"id": pid, "tasks": {"s": {}}}
helmlib.events = lambda pid: [{"task": "s", "status": "running", "t": 100}, {"task": "s", "status": "done", "t": 200},
                              {"task": "s", "status": "landed", "t": 900}, {"task": "s", "cost": 1.0, "t": 950}]
print(helmlib.state("p")["tasks"][0]["built_at"])
helmlib.events = lambda pid: [{"task": "s", "status": "done", "t": 200}, {"task": "s", "status": "running", "t": 300},
                              {"task": "s", "status": "done", "t": 400}]
print(helmlib.state("p")["tasks"][0]["built_at"])
# stalls' minute ages leave the key and the hash
print(r.AGE_RE.sub("", "gone 37m").strip(), r.card_hash({"kind": "stall", "title": "gone 37m"}) == r.card_hash({"kind": "stall", "title": "gone 52m"}))
PY
check "$(PLAN_CACHE_DIR="$LAD/c" python3 "$LAD/r1.py" "$B" 2>&1)" "3 -27.0 overrun 0.0 projected 0.5
200
400
gone True" \
  "a built step's time is its first done (never its landing); a dependency that ended in the past pushes nothing; a running step counts from its own start with its dependency built; a reopened step is built again; a minute age moves no hash"
cat > "$LAD/r2.py" <<'PY'
import sys, json, os
sys.path.insert(0, sys.argv[1])
import helmlib, helm_render as r
r._KEEL[:] = [None]
own = helmlib.columns()[0]
rows = [{"repo": "alpha", "branch": "claude/a", "rel": "docs/a.md", "item": "D1", "title": "pick one", "t": 300, "hash": "h1",
         "section": {"crumb": "c", "above": "the doc's words", "table": None, "item": "- **D1**"}, "summary": "the summary",
         "doc_title": "Doc A", "options": [["A", "x"]], "line": 4}]
open(os.path.join(os.environ["ASK_CACHE_DIR"], "asks.json"), "w").write(json.dumps({"asks": rows}))
# a guard list that does not read: the card as main showed it, its title kept, the doc's words home
helmlib.guard_unread = lambda fresh=False: True
c = r.poll_cards({})[0]
print(c["title"], c.get("guarded"), [f for f in ("section", "summary", "doc_title", "options") if f in c], c["hash"], c["line"])
# a guarded card: its repo reads "guarded", its key a digest salted per host, stable across renders
g = lambda: r.strip_guarded([r._card("ask", "x", own, repo="vault", key="vault@claude/v:docs/v.md#D1", item="D1", guarded=True)])[0]
k1, k2 = g(), g()
import hashlib
print(k1["repo"], "item" in k1, k1["key"] == k2["key"], k1["key"] != "guarded:" + hashlib.sha256(b"vault@claude/v:docs/v.md#D1").hexdigest()[:12],
      os.path.exists(os.path.join(os.environ["PLAN_CACHE_DIR"], "guard-salt")))
# a ship's ask on an older branch of the doc still meets the poll's card of its item: one card
helmlib.guard_unread = lambda fresh=False: False
ship = [r._card("ask", "D1", own, plan_id="p1", task="t1", ref="docs/a.md#D1", repo="alpha", branch="claude/old")]
merged = r.absorb_polled(ship, r.poll_cards({}))
print(len(merged), merged[0]["key"])
PY
check "$(ASK_CACHE_DIR="$LAD" PLAN_CACHE_DIR="$LAD/c2" python3 "$LAD/r2.py" "$B" 2>&1)" "pick one None [] h1 4
guarded False True True True
1 alpha@claude/a:docs/a.md#D1" \
  "a guard list that does not read keeps the doc's words home and the card as main showed it; a guarded card's repo reads guarded and its key is a per-host salted digest; a ship's ask on an older branch is the poll's card"
ov=$("$HM" $BOARD --json)
check "$(echo "$ov" | python3 -c "
import json, sys; d = json.load(sys.stdin); own = d['columns'][0]['cards']
print(all(c.get('hash') for c in own), all('ladder' in r for r in d['timeline']), len({c['key'] for c in own}) == len(own))")" "True True True" \
  "  the board: every owner card carries the hash a snooze names and its own key, every ship row its ladder"
check "$(ls "$PLANS_DIR" | grep -c '^ch6$')/$("$HM" $BOARD --json 2>&1 >/dev/null | grep -c 'ship ch6 skipped (TypeError')" "1/1" \
  "  a torn ship (ch6, an event time that is no number) is skipped with one line; the board renders the rest"
check "$("$HM" render lad-1 --json | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['kind'], d['ladder']['hill']['decisions'], 'docs' in d)")" \
  "plan [1, 2] False" "  render --json, the live stream's value, carries the ladder and no doc path"

echo "helm-board S2, review round 2: a D-list run's shared section, the guarded hash, the relayed ask, the exact branch first, the long-running step"
printf '# Doc\n\n## Q\n\nThe trade-off, shared.\n\n| Option | Cost |\n| --- | --- |\n| A | 1 |\n\n- **D1 — one?**\n  - A — a\n\n  ➤ Answer:\n  A\n\n- **D2 — two?**\n  - A — a\n\n  ➤ Answer:\n\n- **D3 — three?**\n  - A — a\n\n  ➤ Answer:\n\n## R\n\n- **D4 — four?**\n  - A — a\n\n  ➤ Answer:\n\n' > "$LAD/run.md"
cat > "$LAD/r3.py" <<'PY'
import sys, json, os
sys.path.insert(0, sys.argv[1])
import helmlib, helm_render as r
k = r._keel()
text = open(sys.argv[2]).read()
_, d = helmlib.doc_decisions(k, text)
print(sorted(d), d["D2"]["section"]["above"], d["D3"]["section"]["table"]["rows"], d["D4"]["section"]["above"] == "" and d["D4"]["section"]["table"] is None)
_, e = helmlib.doc_decisions(k, text.replace("| A | 1 |", "| A | 2 |"))
print(d["D2"]["hash"] != e["D2"]["hash"], d["D3"]["hash"] != e["D3"]["hash"], d["D4"]["hash"] == e["D4"]["hash"])
own = helmlib.columns()[0]
# a guarded card's hash moves when its item does, and is neither the item's hash nor constant
g = lambda h: r.strip_guarded([r._card("ask", "x", own, repo="vault", key="vault@claude/v:docs/v.md#D1", hash=h, guarded=True)])[0]["hash"]
print(g("h-1") != g("h-2"), g("h-1") == g("h-1"), g("h-1") != "h-1")
# a relayed ship ask leaves the owner's poll card in Decide; the exact branch takes the card before an older one
polled = lambda: [r._card("ask", "t", own, repo="alpha", branch="claude/new", rel="docs/a.md", item="D1", hash="h",
                          key="alpha@claude/new:docs/a.md#D1", updated=500)]
relayed = [r._card("ask", "D1", "Parked / Relayed", plan_id="p", task="t", ref="docs/a.md#D1", repo="alpha", branch="claude/new")]
m = r.absorb_polled(relayed, polled())
print(len(m), [c["column"] for c in m])
ships = [r._card("ask", "D1", own, plan_id="p1", task="t", ref="docs/a.md#D1", repo="alpha", branch="claude/old", updated=100),
         r._card("ask", "D1", own, plan_id="p2", task="t", ref="docs/a.md#D1", repo="alpha", branch="claude/new", updated=200)]
m = r.absorb_polled(ships, polled())
print(len(m), m[0].get("key"), m[1]["key"], m[1]["updated"])
# a running step past a step's length reads overrun, ending now
H = 3600.0; at = 1_800_000_000.0
t = lambda i, s, **kw: dict({"id": i, "title": i, "status": s, "deps": [], "eta": None, "asks": []}, **kw)
e = helmlib.task_ends({"tasks": [t("long", "running", started=at - 9 * H)]}, at)[0]
print(e["long"][1], e["long"][0] == at)
# the hill counts no guarded step's doc
helmlib.load_plan = lambda pid: {"id": pid, "tasks": {"open": {"doc": "/o.md"}, "hid": {"doc": "/h.md", "repo": "/x/vault"}}}
helmlib.events = lambda pid: []
helmlib._guarded_repo = lambda repo: str(repo or "").endswith("vault")
print(helmlib.state("p")["docs"])
PY
check "$(PLAN_CACHE_DIR="$LAD/c3" python3 "$LAD/r3.py" "$B" "$LAD/run.md" 2>&1)" "['D2', 'D3', 'D4'] The trade-off, shared. [['A', '1']] True
True True True
True True True
2 ['Parked / Relayed', 'Needs Sam']
2 None alpha@claude/new:docs/a.md#D1 200
overrun True
['/o.md']" \
  "a D-list run carries its shared prose and table to each item, an answered first one included, and an edit of the table moves each hash, never another heading's; a guarded card's hash is salted and moves with its item; a relayed ship ask leaves the poll card in Decide; the exact branch takes the poll card first and keeps its opening time; a step running past a step's length reads overrun; the hill counts no guarded step's doc"

echo "helm-board S2, review round 3: a retry's own start, a torn salt healed, a bad due, the waits reason, a thematic break"
cat > "$LAD/r4.py" <<'PY'
import sys, json, os
sys.path.insert(0, sys.argv[1])
import helmlib, helm_render as r
H = 3600.0
now = helmlib.now()
# a retry a minute old after a stall counts from itself; a fix round after done measures its own round
helmlib.load_plan = lambda pid: {"id": pid, "tasks": {"s": {}, "f": {}}}
helmlib.events = lambda pid: [{"task": "s", "status": "running", "t": now - 6 * H}, {"task": "s", "status": "blocked", "t": now - 5 * H},
                              {"task": "s", "status": "running", "t": now - 60},
                              {"task": "f", "status": "running", "t": now - 50 * H}, {"task": "f", "status": "done", "t": now - 48 * H},
                              {"task": "f", "status": "running", "t": now - 2 * H}, {"task": "f", "status": "done", "t": now - H}]
st = helmlib.state("p", now)
ends, step, src = helmlib.task_ends(st, now)
print(ends["s"][1], round((ends["s"][0] - now) / H, 1), round(step / H, 1), src)
# a torn (short) salt is replaced once and then stands
p = os.path.join(os.environ["PLAN_CACHE_DIR"], "guard-salt")
os.makedirs(os.environ["PLAN_CACHE_DIR"], exist_ok=True)
open(p, "w").write("")
a, b = r.guard_salt(), r.guard_salt()
print(a == b, len(a) >= 16, open(p).read().strip() == a, [f for f in os.listdir(os.environ["PLAN_CACHE_DIR"]) if f.endswith(".tmp")])
# a due that will not read: the ship keeps its page, without a ladder
v = r.plan_view(dict(st, due="soon", docs=[], guard_salt="x"), now)
print(v["ladder"], len(v["tasks"]))
# the waits reason names the item, whatever suffix the key took
own = helmlib.columns()[0]
c = r._card("ask", "t", own, repo="a", branch="b", rel="docs/x.md", item="D3", step_waits=["S1"], key="ask:p/t#D3|Which road")
print(r.decide_queue([c])[0]["docs"][0]["why"])
# a thematic break above a run is no one's trade-off
text = "# D\n\n## Q\n\n---\n\n- **D1 — one?**\n  - A — a\n\n  ➤ Answer:\n\n- **D2 — two?**\n  - A — a\n\n  ➤ Answer:\n\n"
_, d = helmlib.doc_decisions(r._keel(), text)
print(repr(d["D1"]["section"]["above"]), repr(d["D2"]["section"]["above"]))
PY
check "$(PLAN_CACHE_DIR="$LAD/c4" python3 "$LAD/r4.py" "$B" 2>/dev/null)" "projected 1.0 1.0 the median of 1 built step
True True True []
None 2
↑ first: S1 waits on D3
'' ''" \
  "a retry counts from its own round and a fix round measures itself; a torn salt is replaced once and stands, no tmp left; a due that will not read leaves the ship without a ladder; the waits reason names the item; a thematic break is no prose"

echo "helm-board S2, the finish review: a resume is one round, a failed step's bad ETA, a later item's own prose, guarded asks apart, held cards' fields, the doc's order, the salt's mode"
cat > "$LAD/r5.py" <<'PY'
import sys, json, os
sys.path.insert(0, sys.argv[1])
import helmlib, helm_render as r
H = 3600.0
now = helmlib.now()
# a run resuming after an ask is the same round: its start stands, and 10 h in it reads overrun
helmlib.load_plan = lambda pid: {"id": pid, "tasks": {"w": {}}}
helmlib.events = lambda pid: [{"task": "w", "status": "running", "t": now - 10 * H}, {"task": "w", "status": "waiting", "t": now - 9 * H},
                              {"task": "w", "status": "running", "t": now - H}]
st = helmlib.state("p", now)
print(st["tasks"][0]["run_started"] == now - 10 * H, helmlib.task_ends(st, now)[0]["w"][1])
# a failed step whose ETA will not read: task_ends and the timeline go on
bad = {"id": "b", "tasks": [{"id": "f", "title": "f", "status": "failed", "deps": [], "eta": "soon", "asks": [], "blockers": []}],
       "milestones": [], "totals": {}, "ladder": None}
print(helmlib.task_ends(bad, now)[0]["f"][1], len(r.timeline([bad], now)[0]["bars"]))
# a later item's own prose stays its own; the run's prose rides only the items with none
text = ("# D\n\n## H\n\nSection prose P0.\n\n- **D1 — one?**\n  - A — a\n\n  ➤ Answer:\n\nOnly about D2: P2.\n\n"
        "- **D2 — two?**\n  - A — a\n\n  ➤ Answer:\n\n- **D3 — three?**\n  - A — a\n\n  ➤ Answer:\n\n")
_, d = helmlib.doc_decisions(r._keel(), text)
print([d[k]["section"]["above"] for k in ("D1", "D2", "D3")])
# two asks of one guarded task are told apart, by key and by hash
own = helmlib.columns()[0]
ga = lambda opened: r._card("ask", "an ask in a guarded session", own, plan_id="p", task="guarded-1", ref="guarded",
                            repo="guarded", guarded=True, updated=opened)
cs = [ga(100), ga(200)]
r.key_cards(cs)
r.strip_guarded(cs)
print(cs[0]["key"] != cs[1]["key"], cs[0]["hash"] != cs[1]["hash"])
# a held memo comes back when its open count moves; a stall's class is read
m = lambda n: r._card("memo", "m", own, doc="/d.md", open=n)
s = lambda c: r._card("stall", "s", own, session="x", stall=c)
print(r.card_hash(m(3)) != r.card_hash(m(5)), r.card_hash(s("S2")) != r.card_hash(s("S6")))
# the doc's order: by line, a card with none after them, D2 before D10
cards = [r._card("ask", "a", own, repo="a", branch="b", rel="docs/x.md", item=i, key="k#" + i, line=l)
         for i, l in (("D10", None), ("D2", None), ("D1", 5))]
print(r.decide_queue(cards)[0]["docs"][0]["items"])
# the salt is the owner's alone
r.guard_salt()
print(oct(os.stat(os.path.join(os.environ["PLAN_CACHE_DIR"], "guard-salt")).st_mode & 0o777))
PY
check "$(PLAN_CACHE_DIR="$LAD/c5" python3 "$LAD/r5.py" "$B" 2>/dev/null)" "True overrun
projected 1
['Section prose P0.', 'Only about D2: P2.', 'Section prose P0.']
True True
True True
['k#D1', 'k#D2', 'k#D10']
0o600" \
  "a resume after an ask is the same round; a failed step's unreadable ETA spares the timeline; a later item's own prose is never the next one's; two asks of a guarded task differ in key and hash; a memo's open count and a stall's class move the hash; the doc's order puts lineless cards last, by number; the salt file is 0600"

echo
[ "$fails" = 0 ] && echo "test_helm ($HELM_NAMES names): all passed" || { echo "test_helm ($HELM_NAMES names): $fails failed"; exit 1; }
