#!/usr/bin/env bash
# Tests for bin/wharf (docs/wharf-on-orca-2026-10-17.md; B6/B7 of docs/orchestration-orca-2026-10-15.md):
# the blueprint's check and dry run, the live apply against a stub Orca, the tick's pass, --watch and
# --launch, `wharf next`. Split out of bin/test_plan.sh (now test_helm.sh) by rename S5 (helm-vocabulary
# H1). No network, no model.
#   bash modules/wharf-runs/tests/test_wharf.sh
set -u
B="$(cd "$(dirname "$0")/../bin" && pwd)"   # the module's bin/ (B7: the suites moved to tests/)
# helm's bin/ (plan, helm, stalls — the overlay's until B12) and the overlay's checkout, found as
# bin/wharf finds helmlib (the core's tool; the overlay's checkout, overlay_root): wharf runs on helm's ships, so without helm
# the suite has nothing to drive and says so
# The console and its old name are found each where it lives (B12): helm's module ships the console
# in libexec/ (regatta helm, G28) and no bin/plan, which stays the overlay's shim until S8; an overlay
# before B12 holds both beside helmlib. An overlay's bin/plan from before S5 is no shim: no old names.
eval "$(python3 - "$B/../lib" <<'CORE'
import shlex, sys
sys.path.insert(0, sys.argv[1])
import core_path
core_path.require()
import common
h, old = common.tool("helmlib.py"), common.overlay_root()
print("HELMBIN=%s" % shlex.quote(str(h.parent) if h else ""))
con = h and next((c for c in (h.parent.parent / "libexec" / "helm", h.parent / "helm") if c.is_file()), None)
plans = [h.parent / "plan"] if h else []
plans += [old / "bin" / "plan"] if old else []
pl = next((c for c in plans if c.is_file() and "kept as a shim until S8" in c.read_text(errors="replace")), None)
print("HELMC=%s" % shlex.quote(str(con) if con else ""))
print("PLAN=%s" % shlex.quote(str(pl) if pl else ""))
print("OVL=%s" % shlex.quote(str(old) if old and (old / "settings").is_dir() else ""))
CORE
)"
[ -n "$HELMBIN" ] || { echo "  --   test_wharf skipped: helm (helmlib.py) is not installed here"; exit 0; }
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
if [ "$HELM_NAMES" = old ] && [ -z "$PLAN" ]; then
  echo "  --   the old names skipped: no bin/plan shim (rename S5's) beside helm or in the overlay"; exit 0
fi
if [ "$HELM_NAMES" = old ]; then
  HM="$PLAN" SHIP=new BOARD=overview BY=--owner E_SHIP=DISPATCH_PLAN E_SKIP=DISPATCH_MANAGER
  E_SKIP_HOST=DISPATCH_MANAGER_HOST E_SKIP_ACCOUNT=DISPATCH_MANAGER_ACCOUNT
else
  HM="$HELMC" SHIP=ship BOARD=board BY=--by E_SHIP=DISPATCH_SHIP E_SKIP=DISPATCH_SKIPPER
  E_SKIP_HOST=DISPATCH_SKIPPER_HOST E_SKIP_ACCOUNT=DISPATCH_SKIPPER_ACCOUNT
fi
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fails=0
check() { if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3: expected [$2] got [$1]"; fails=$((fails+1)); fi; }
has() { case "$1" in *"$2"*) echo "  ok   $3";; *) echo "  FAIL $3: [$2] not in [${1:0:300}]"; fails=$((fails+1));; esac; }
hasnt() { case "$1" in *"$2"*) echo "  FAIL $3: [$2] found"; fails=$((fails+1));; *) echo "  ok   $3";; esac; }

# a blueprint's front matter is read by PyYAML, installed per user on these Macs: keep its site
# when HOME moves below (bin/blueprintlib.py)
export PYTHONUSERBASE="${PYTHONUSERBASE:-$(python3 -m site --user-base)}"
. "$(cd "$(dirname "$0")" && pwd)/config_fixture.sh"; fixture_config "$T/config"   # the suite's own config dir, never the login's (config_fixture.sh)
# the ship's repo and its hosts, which blueprintlib.hosts_of reads: none read, any host would pass
mkdir -p "$T/config/wharf"; echo '{"repos": {"shop": {"hosts": ["laptop", "buildbox"]}}}' > "$T/config/wharf/repos.json"
export PLANS_DIR="$T/plans" PLAN_HOST=testhost PLAN_PROJECTS_DIR="$T/projects" PLAN_CACHE_DIR="$T/cache" HOME="$T/home" \
       SURFACES_FILE="$T/surfaces.json" PLAN_NO_DEPLOY=1 ASK_SESSIONS_DIR="$T/sess" ASK_CACHE_DIR="$T/askcache" \
       COST_RATIO="$T/ratio.json" PLAN_NO_MEMO=1 PLAN_NO_GH=1 PLAN_PROJECTS_ROOT="$T/projects-root" \
       STALLS_PEERS= STALLS_REPOS= STALLS_ORCA=0 PLAN_NO_WHARF=1   # no wharf pass in a tick outside B7's own block, whose stub it reaches; the stall cards: no ssh to the build Mac, no real repo's autofinished, no Orca app (B8's block turns its stub on)
unset DISPATCH_PLAN DISPATCH_MANAGER DISPATCH_PLAN_SPACE CLAUDE_UNATTENDED DISPATCH_REPO DISPATCH_MANAGER_HOST DISPATCH_DEPTH \
      DISPATCH_SHIP DISPATCH_SKIPPER DISPATCH_SKIPPER_HOST DISPATCH_SKIPPER_ACCOUNT DISPATCH_MANAGER_ACCOUNT
unset SKIPPER_GEN SKIPPER_SCOPE SKIPPER_ACCOUNT HELM_HOLD_EVERY HELM_HOLD_PARENT   # the lease's inputs (S4)
export CLAUDE_CODE_SESSION_ID=mgr-1
mkdir -p "$T/home" "$T/sess"
# The moved HOME drops check.yml's git identity, and the pinned-doc block commits without -c: a runner
# cannot guess one from its hostname as a Mac does (twin-ci-4, 2026-10-25). A file of the suite's own,
# never the caller's (config_fixture.sh unset theirs); it carries check.yml's init.defaultBranch too.
export GIT_CONFIG_GLOBAL="$T/gitconfig"
git config --global user.name t; git config --global user.email t@t; git config --global init.defaultBranch main
if [ -n "$OVL" ]; then cp "$OVL/settings/surfaces.json" "$T/surfaces.json"; else echo '{}' > "$T/surfaces.json"; fi
echo '{"providers": {"anthropic": {"ratio": 0.02, "week_ending": "2026-01-04"}}}' > "$COST_RATIO"

PLAN_NO_RENDER=1
export PLAN_NO_RENDER
# The blueprint's verbs, spelled per HELM_NAMES: bin/wharf itself under the new names; under the old,
# `plan chain|apply [<id>] <file>` through the bin/plan shim wherever it had the verb (check or apply with
# --plan, --accept, --json, --dry-run, --once), and wharf itself for what bin/plan never had.
cat > "$T/wharf-old" <<SH
#!/bin/bash
v=\$1; shift; pid=; file=; fl=(); ok=1
for a in "\$@"; do :; done
args=("\$@"); i=0
case "\$v" in check|apply) ;; *) ok=0;; esac
while [ \$ok = 1 ] && [ \$i -lt \${#args[@]} ]; do
  a=\${args[\$i]}
  case "\$a" in
    --plan) pid=\${args[\$((i+1))]}; i=\$((i+2));;
    --accept|--json|--dry-run|--once) fl+=("\$a"); i=\$((i+1));;
    -*) ok=0;;
    *) if [ -z "\$file" ]; then file=\$a; i=\$((i+1)); else ok=0; fi;;
  esac
done
[ -n "\$file" ] || ok=0
if [ \$ok = 1 ]; then
  echo "plan \$( [ "\$v" = check ] && echo chain || echo apply )" >> "$T/wharf-old.routes"
  exec "$PLAN" "\$( [ "\$v" = check ] && echo chain || echo apply )" \${pid:+"\$pid"} "\$file" \${fl[@]+"\${fl[@]}"}
fi
exec "$B/wharf" "\$v" "\$@"
SH
chmod +x "$T/wharf-old"
if [ "$HELM_NAMES" = old ]; then WH="$T/wharf-old"; else WH="$B/wharf"; fi

echo "the blueprint (orchestration-orca B6): plan chain, plan apply --dry-run, plan task's blueprint fields"
# its own plan store: the board and the render below count the plans in PLANS_DIR
P() { PLANS_DIR="$T/ship_plans" "$HM" "$@"; }
SW() { PLANS_DIR="$T/ship_plans" "$WH" "$@"; }
CR="$T/shiprepo"; mkdir -p "$CR/docs/blueprints"; git init -q -b main "$CR"
CF="$CR/docs/blueprints/2026-10-16-demo.md"
cat > "$CF" <<'EOF'
---
ship: demo   # the topic
repo: shop
manager: regatta
created: 2026-10-16
blocks:
  - id: probe
    depends_on: []
    provider: orca
    agent: claude
    host: here
    tier: worker
    model: sonnet
    effort: high
    physical: none
    done_when: {marker: "docs/d.md#B6a"}
    timeout_seconds: 7200
    retries: 2
  - id: pick
    kind: decision
    doc: docs/d.md
    items: [D1, D2]
    depends_on: [probe]
  - id: build
    depends_on:
      - pick
    provider: orca
    agent: codex
    done_when: {check: bash bin/test_plan.sh}
  - id: remote
    depends_on: [probe]
    provider: claude-code
    host: buildbox
    account: auto
  - id: launch
    depends_on: [build, remote]
    provider: shell
    command: "bin/autofinish-run <wt> --by chain"
    launch: autofinish
---
The demo blueprint: a probe, a decision, two builds, a launch.

## probe
Task: probe it
Tier: Sonnet 5.5 high
Why: because
Start here: docs/d.md
Done means: a marker
Not this: no live call

## build
Task: build it
Tier: Opus 5.5 high
Why: D1
Start here: there
Done means: green
Not this: live

## remote
Task: run it on the build Mac
Tier: Opus 5.5 high
Why: a host
Start here: here
Done means: green
Not this: Orca
EOF
cat > "$CR/docs/d.md" <<'EOF'
# A doc

## Decisions

- **D1 — Which way** (why)
  - A — one
  - B — two

  Reversible: yes

  ➤ Recommended: A

  ➤ Answer:
  B

- **D2 — Which other** (why)
  - A — one
  - B — two

  Reversible: yes

  ➤ Recommended: A

  ➤ Answer:

EOF
out=$(SW check "$CF"); check "$?" "0" "a valid blueprint: exit 0"
# rename S5 (H1): a ship's tasks written before it (no `block`, the doer as `owner`) are the file's as they are
check "$(python3 - "$B" "$CF" <<'PY2'
import sys
sys.path.insert(0, sys.argv[1]); sys.path.insert(0, sys.argv[1] + "/../lib")
import core_path; core_path.require()   # the core, as bin/wharf and helm put it on the path, holding the owner name
import blueprintlib
bp = blueprintlib.load(sys.argv[2])
old = {}
for st in bp["blocks"]:
    t = blueprintlib.plan_fields(bp, st, "testhost", bp["meta"]["repo"])
    t.pop("block")
    if "by" in t:
        t["owner"] = t.pop("by")
    old[st["id"]] = t
rows = blueprintlib.diff(bp, "testhost", old, None)["plan"]
new = {st["id"]: blueprintlib.plan_fields(bp, st, "testhost", bp["meta"]["repo"]) for st in bp["blocks"]}
print(sorted(set(r[0] for r in rows)), sorted(set(r[0] for r in blueprintlib.diff(bp, "testhost", new, None)["plan"])),
      new["pick"].get("by"), new["probe"]["block"])
PY2
)" "['ok'] ['ok'] sam probe" "a task from before S5 (owner, no block) is no drift; a new one names its block and its doer by"
# rename S5 (H1): bin/plan's chain and apply are a shim now, and say what wharf says (where a shim is found)
[ -z "$PLAN" ] || check "$(PLANS_DIR="$T/ship_plans" "$PLAN" chain "$CF")" "$(PLANS_DIR="$T/ship_plans" "$B/wharf" check "$CF")" "plan chain and wharf check print the same graph"
has "$out" "ship demo — repo shop, skipper regatta, created 2026-10-16" "  the header: manager: is read as the skipper"
has "$out" "5 blocks in 4 waves" "  the waves: probe; pick and remote; build; launch"
has "$out" "probe   orca/claude worker sonnet·high done when marker docs/d.md#B6a · retries 2, timeout 2h" "  a block's line"
has "$out" "claude/testhost/2026-10-16-probe" "  its branch: claude/<host>/<created>-<id>"
has "$out" "claude/buildbox/2026-10-16-remote" "  a buildbox block's branch names buildbox"
has "$out" "launch  shell \`bin/autofinish-run <wt> --by chain\` · launched by autofinish  ← build, remote" "  a launch, after both"
check "$(SW check "$CF" --json | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['waves'], d['blocks'][1]['items'], d['blocks'][0]['done_when'], d['blocks'][0]['timeout_seconds'])")" \
  "[['probe'], ['pick', 'remote'], ['build'], ['launch']] ['D1', 'D2'] {'marker': 'docs/d.md#B6a'} 7200" "--json: waves, flow lists and maps, numbers"
d1=$(SW check "$CF" --json | python3 -c "import json,sys; print(json.load(sys.stdin)['digest'])")
sed -i.bak 's/^Not this: live$/Not this: live   /' "$CF"
check "$(SW check "$CF" --json | python3 -c "import json,sys; print(json.load(sys.stdin)['digest'])")" "$d1" "  the digest ignores spaces at line ends"
sed -i.bak 's/^Not this: live   $/Not this: live, ever/' "$CF"
hasnt "$(SW check "$CF" --json | python3 -c "import json,sys; print(json.load(sys.stdin)['digest'])")" "$d1" "  and changes with a section's text"
mv "$CF.bak" "$CF"; sed -i.bak 's/^Not this: live   $/Not this: live/' "$CF"; rm -f "$CF.bak"
check "$(SW check "$CF" --json | python3 -c "import json,sys; print(json.load(sys.stdin)['digest'])")" "$d1" "  restored: the same digest"
[ -f "$OVL/docs/orchestration-orca-2026-10-15.md" ] && check "$(sed -n 1,200p "$OVL/docs/orchestration-orca-2026-10-15.md" | python3 -c "
import sys; sys.path.insert(0, '$B'); import blueprintlib
t = sys.stdin.read(); i = t.index('\`\`\`\n---\nship:') + 4; j = t.index('\`\`\`', i)
# Q1's example is the doc's history and keeps its first keys: steps: and lands: (launch: now; wharf-rename section 5)
ex = t[i:j].replace('\nsteps:\n', '\nblocks:\n').replace(' lands: ', ' launch: ')
try:
    blueprintlib.load('docs/blueprints/2026-10-15-orca-ship-build.md', ex)
except blueprintlib.BlueprintError as e:
    print(e.problems)")" "['block b6-parser: no \`## b6-parser\` section — its brief is what the worker is handed']" \
  "the design doc's own example parses; its one problem is the brief it leaves out"

echo "  invalid blueprints: each refused, exit 2, with the line or the block"
bad() {   # bad <label> <expected text> <python that edits the text t>
  python3 - "$CF" "$T/bad.md" "$3" <<'PY'
import sys
t = open(sys.argv[1]).read()
exec(sys.argv[3])
open(sys.argv[2], "w").write(t)
PY
  out=$(SW check "$T/bad.md" 2>&1); rc=$?
  check "$rc" "2" "  $1: exit 2"; has "$out" "$2" "    $1: says so"
}
bad "a cycle" "a cycle in depends_on: probe" "t = t.replace('depends_on: []', 'depends_on: [launch]', 1)"
bad "an unknown dependency" "block launch: depends_on biuld, which is no block" "t = t.replace('[build, remote]', '[biuld, remote]')"
bad "a typo in a key" "block pick: depend_on is not a key of a decision block" "t = t.replace('    depends_on: [probe]\n  - id: build', '    depend_on: [probe]\n  - id: build')"
bad "an orca block with no agent" "block probe: an orca block names its agent" "t = t.replace('    agent: claude\n', '', 1)"
bad "effort with no model" "block build: effort needs a model on an Orca block" "t = t.replace('    agent: codex\n', '    agent: codex\n    effort: high\n')"
bad "a host the repo does not list" "block probe: host is here or one of the repo's hosts in repos.json (buildbox, laptop)" "t = t.replace('    host: here\n', '    host: nowhere\n', 1)"
bad "a remote block's done_when that reads a worktree here" "block probe: done_when's marker reads a worktree here; a block on buildbox ends by pr_merged or memo_answered" "t = t.replace('    host: here\n', '    host: buildbox\n', 1)"
bad "yolo on Orca" "block probe: yolo is not for orca blocks" "t = t.replace('    host: here\n', '    host: here\n    yolo: true\n', 1)"
bad "a missing brief" "block build: no \`## build\` section" "t = t.replace('## build\n', '### build\n')"
bad "a brief without the handoff lines" "\`## remote\` lacks the handoff lines Why, Not this" "t = t.replace('Why: a host\n', '').replace('Not this: Orca', 'Orca')"
bad "a heading for no block" "\`## notes\` is a section for no block" "t = t + '\n## notes\nx\n'"
bad "a heading that is no id" "\`## Notes on it\` — every \`## \` heading names a block" "t = t + '\n## Notes on it\nx\n'"
bad "three retries" "block probe: retries is 0 to 2" "t = t.replace('retries: 2', 'retries: 3')"
bad "a tab" "line 8: found character '\\t' that cannot start any token" "t = t.replace('    depends_on: []', '\t  depends_on: []')"
bad "a key twice" "line 13: key tier twice" "t = t.replace('tier: worker', 'tier: worker\n    tier: sr-worker')"
bad "a second block with one id" "block pick: a second block with this id" "t = t.replace('  - id: remote', '  - id: pick')"
bad "host auto on an Orca block" "block probe: host auto is a claude-code block's (dispatch places it by berth); an Orca block names its host" "t = t.replace('    host: here\\n', '    host: auto\\n', 1)"
bad "a mode that is no mode" "front matter: mode is one of default, ask, dnd, yolo" "t = t.replace('created: ', 'mode: loud\\ncreated: ', 1)"
bad "a decision with no items" "block pick: items is a list like [D2, D3]" "t = t.replace('items: [D1, D2]', 'items: []')"
bad "a done_when of two kinds" "block probe: done_when is one of" "t = t.replace('{marker: \"docs/d.md#B6a\"}', '{marker: x, check: y}')"
bad "a marker with no item" "block probe: done_when's marker is <doc>#<item>" "t = t.replace('{marker: \"docs/d.md#B6a\"}', '{marker: \"docs/d.md\"}')"
bad "a done_when on a claude-code block" "block remote: a claude-code block ends by its own launch" "t = t.replace('    account: auto\n', '    account: auto\n    done_when: {file: x}\n')"
bad "a claude-code id pickup seed refuses" "block rm: a claude-code block's id is its seed topic" "t = t.replace('remote', 'rm')"
bad "pr_merged on a shell block with no branch" "block launch: done_when's pr_merged on a shell block needs its branch:" "t = t.replace('    launch: autofinish\n', '    launch: autofinish\n    done_when: {pr_merged: true}\n')"
bad "a shell block with no command" "block launch: a shell block has a command" "t = t.replace('    command: \"bin/autofinish-run <wt> --by chain\"\n', '')"
bad "no front matter" "a blueprint starts with a \`---\` front matter" "t = t[4:]"
bad "a plain value with a colon" "line 12: mapping values are not allowed here" "t = t.replace('tier: worker', 'tier: a: b')"
bad "an account on Orca (D8: acct-a always)" "block probe: account is not for orca blocks" "t = t.replace('    host: here\n', '    host: here\n    account: acct-c\n', 1)"
bad "yolo on claude-code (pickup seed has no --yolo)" "block remote: yolo is not for claude-code blocks" "t = t.replace('    provider: claude-code\n', '    provider: claude-code\n    yolo: true\n', 1)"
bad "retries on a shell block (it runs once)" "block launch: retries is not for shell blocks" "t = t.replace('    launch: autofinish\n', '    launch: autofinish\n    retries: 1\n')"
bad "a launch whose only worktree is on the build Mac" "block launch: <wt> is a worktree here; remote runs on buildbox, its worktree is there" "t = t.replace('    depends_on: [build, remote]\n', '    depends_on: [remote]\n')"
bad "a shell block on the build Mac" "block launch: host is not for shell blocks" "t = t.replace('    launch: autofinish\n', '    launch: autofinish\n    host: buildbox\n')"
bad "a Q-item memo cannot read" "block pick: items is a list like [D2, D3]" "t = t.replace('items: [D1, D2]', 'items: [Q1]')"
bad "a decision's title that is a list" "block pick: title is a non-empty string" "t = t.replace('    items: [D1, D2]\n', '    items: [D1, D2]\n    title: [a, b]\n')"
bad "a key that is a list" "a key that is a list or map" "t = t.replace('    retries: 2\n', '    retries: 2\n    ? [a, b]\n    : x\n', 1)"
bad "a merge that is neither yes nor no (skipper-resilience S2)" "front matter: merge is yes or no" "t = t.replace('created: 2026-10-16', 'created: 2026-10-16\nmerge: maybe')"
bad "an empty sent_by" "front matter: sent_by is a non-empty string" "t = t.replace('created: 2026-10-16', 'created: 2026-10-16\nsent_by: \"\"')"

echo "  an Orca block on another host: checked, not refused (wharf-on-orca S3; the host from repos.json)"
sed 's/^    host: here$/    host: buildbox/; s/{marker: "docs\/d.md#B6a"}/{pr_merged: true}/' "$CF" > "$T/remote.md"
out=$(SW check "$T/remote.md" 2>&1); check "$?" "0" "  an Orca block on buildbox passes check"
has "$out" "on buildbox" "    and says where it runs"
P $SHIP blueprints --id rm1 > /dev/null
has "$(SW apply "$T/remote.md" --plan rm1 --dry-run)" "worker-start --task <probe> --on buildbox --agent claude" "    the dry run starts it --on the host"
out=$(PLAN_HOST=buildbox SW apply "$T/remote.md" --plan rm1 --dry-run); has "$out" "worker-start --task <probe> --agent claude" "    on buildbox itself the same block is here (review 2026-10-18)"
check "$(printf '%s' "$out" | grep -c -- '--on buildbox')" "0" "      no --on to itself"

echo "  accept, then a changed file is refused"
P $SHIP blueprints --id cp > /dev/null
check "$(SW check "$CF" --plan cp | tail -1)" "plan cp: no digest of demo recorded (wharf check --accept)" "plan chain (now wharf check's shim) with a plan: nothing accepted yet"
out=$(SW apply "$CF" --plan cp --dry-run); check "$?" "0" "dry run before any accept: exit 0"
[ -z "$PLAN" ] || check "$(PLANS_DIR="$T/ship_plans" "$PLAN" apply cp "$CF" --dry-run --json)" "$(PLANS_DIR="$T/ship_plans" "$B/wharf" apply "$CF" --plan cp --dry-run --json)" \
  "  plan apply <id> --dry-run and wharf apply --plan <id> --dry-run: the same diff"
[ -z "$PLAN" ] || check "$(PLANS_DIR="$T/ship_plans" "$PLAN" chain 2>&1; echo "rc=$?")" "plan chain: a blueprint file (wharf check <blueprint.md>)
rc=1" "  the shim with no file says what it wants"
has "$out" "not recorded — the first apply records it" "  the digest is not recorded yet"
has "$out" 'orca: no Run recorded for this blueprint — run-create "shop/demo (wharf apply)" first' "  no Run: nothing read from Orca"
has "$out" "start    probe   ready once created: worker-start --task <probe> --agent claude --model sonnet --effort high" "  the first wave starts once created"
has "$out" "gate     pick    gate-create on its task: docs/d.md#D1, D2" "  the decision gets its gate"
has "$out" "create   launch  task-create --task-title launch --deps build,remote" "  deps by block id"
has "$out" "add      remote  plan task remote (claude-code)" "  the plan side: every block a task to add"
has "$out" "to do: 5 add, 5 create, 1 gate, 1 start" "  the count"
check "$([ -s "$T/orca-plan.calls" ] && echo called || echo none)" "none" "  and Orca was never called"
check "$(SW check "$CF" --plan cp --accept | tail -1 | cut -c1-47)" "accepted demo into plan cp: digest ${d1:0:12}" "--accept records the digest"
check "$(python3 -c "import json; d=json.load(open('$T/ship_plans/cp/plan.json'))['blueprints']['demo']; print(d['digest'] == '$d1', sorted(d['blocks']), d['file'].endswith('2026-10-16-demo.md'))")" \
  "True ['build', 'launch', 'pick', 'probe', 'remote'] True" "  in plan.json: the digest, a digest per block, the file"
has "$(SW check "$CF" --plan cp | tail -1)" "the digest accepted" "  plan chain then says it matches"
cp "$CF" "$T/demo.orig"
python3 - "$CF" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
t = t.replace("Task: run it on the build Mac", "Task: run it on the build Mac, twice").replace("  - id: launch", "  - id: extra\n    provider: shell\n    command: \"true\"\n  - id: launch")
open(p, "w").write(t)
PY
out=$(SW apply "$CF" --plan cp --dry-run); rc=$?
check "$rc" "1" "a changed file: the dry run refuses, exit 1"
has "$out" "wharf apply: refused — changed since accepted" "  says refused"
has "$out" "added extra; changed remote" "  names the blocks that changed"
check "$(SW apply "$CF" --plan cp --dry-run --json | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['refused'], d['accepted'] == '$d1')")" "True True" "  --json says refused too"
cp "$T/demo.orig" "$CF"
# the live compile (B7) is tested against its own stub below: a live apply here would reach the real Orca app

echo "  against a stub orca: run-show, task-list, gate-list, worker-list --run — reads only"
cat > "$T/orca-plan" <<'PY'
#!/usr/bin/env python3
# Orca 1.4.225's read answers, in the shapes probe P3 recorded (2026-10-15): deps a JSON string,
# task_title the block id, gates per task. Every call is logged; a write verb fails the test.
import json, os, sys
args = [a for a in sys.argv[1:] if a != "--json"]
open(os.environ["STUB_CALLS"], "a").write(" ".join(args) + " ELECTRON_RUN_AS_NODE=%s\n" % os.environ.get("ELECTRON_RUN_AS_NODE", "unset"))
st = json.load(open(os.environ["STUB_STATE"]))
out = lambda r: (print(json.dumps({"id": "x", "ok": True, "result": r})), sys.exit(0))
cmd = " ".join(args[:2])
if os.environ.get("STUB_DOWN"):
    print(json.dumps({"id": "x", "ok": False, "error": {"code": "runtime_unavailable", "message": "no runtime"}})); sys.exit(1)
if cmd == "orchestration run-show":
    out({"run": st["run"]})
if cmd == "orchestration task-list":
    out({"tasks": st["tasks"]})
if cmd == "orchestration gate-list":
    out({"gates": st["gates"]})
if cmd == "orchestration worker-list":
    out({"workers": st["workers"], "page": {"hasMore": False, "nextCursor": None}})
print(json.dumps({"id": "x", "ok": False, "error": {"code": "stub", "message": "not a read: %s" % cmd}})); sys.exit(1)
PY
chmod +x "$T/orca-plan"
spec() { python3 -c "
import sys; sys.path.insert(0, '$B'); import blueprintlib
c = blueprintlib.load('$CF'); print(blueprintlib.spec_of(c, c['by_id']['$1']))"; }
python3 - "$T/orca-plan.json" "$(spec probe)" "$(spec pick)" "$(spec build)" <<'PY'
import json, sys
p, sp_probe, sp_pick, sp_build = sys.argv[1:]
t = lambda i, title, status, deps, spec, **k: dict(id=i, run_id="run_1", task_title=title, display_name=title, spec=spec,
                                                status=status, deps=json.dumps(deps), result=k.get("result"))
json.dump({"run": {"id": "run_1", "coordinator_handle": "term_c"},
           "tasks": [t("task_p", "probe", "completed", [], sp_probe),
                     t("task_d", "pick", "blocked", ["task_p"], sp_pick),
                     t("task_b", "build", "dispatched", ["task_d"], sp_build),
                     t("task_r", "remote", "ready", ["task_p"], "an older brief"),
                     t("task_x", "gone-block", "pending", [], "x")],
           "gates": [{"id": "gate_1", "run_id": "run_1", "task_id": "task_d", "question": "docs/d.md#D1, D2",
                      "options": "[\"A\",\"B\"]", "status": "pending", "resolution": None}],
           "workers": [{"dispatchId": "ctx_b1", "taskId": "task_b", "runId": "run_1", "dispatchStatus": "dispatched",
                        "workerState": "ready", "projection": {"outcome": "in_progress", "liveness": {"verdict": "exited"}}}]},
          open(p, "w"))
PY
python3 - "$T/ship_plans/cp/plan.json" <<'PY'
import json, sys
# what B7's first compile will have written: the Run, its coordinator, one task's id
p = sys.argv[1]; d = json.load(open(p))
d["blueprints"]["demo"].update(orca_run="run_1", coordinator="term_c")
d["tasks"] = {"probe": {"orca_task": "task_p", "ship": "demo", "title": "probe", "repo": "shop", "deps": [], "kind": "session",
                        "provider": "orca", "host": "testhost", "branch": "claude/testhost/2026-10-16-probe", "agent": "claude",
                        "done_when": {"marker": "docs/d.md#B6a"}},
              "remote": {"orca_task": "task_gone", "ship": "demo"},
              "old": {"ship": "demo", "title": "old"}}
json.dump(d, open(p, "w"))
PY
O() { HARNESS_ORCA="$T/orca-plan" STUB_STATE="$T/orca-plan.json" STUB_CALLS="$T/orca-plan.calls" ELECTRON_RUN_AS_NODE=1 SW "$@"; }
out=$(cd "$CR" && O apply docs/blueprints/2026-10-16-demo.md --plan cp --dry-run); check "$?" "0" "a dry run against Orca: exit 0"
has "$out" "orca: Run run_1 (coordinator term_c): 5 tasks, 1 gates, 1 dispatches" "  the Run read back"
has "$out" "ok       probe   task_p completed" "  a completed block is ok"
check "$(echo "$out" | grep '^  resolve\|^  ok       pick')" "  ok       pick    gate gate_1 waits on docs/d.md#D1, D2" "  a decision with its gate pending waits while D2 is unanswered"
has "$out" "stalled  build   dispatch ctx_b1 exited with no worker_done (S1: the tick's)" "  a dispatch Orca calls exited, no worker_done: stalled"
has "$out" "changed  remote  spec differ from task_r (ready) — re-spec: fail it cancelled, create it again" "  Orca's spec is not the brief: changed"
has "$out" "start    remote  dispatch claude/buildbox/2026-10-16-remote --on buildbox --account auto" "  a ready claude-code block starts through dispatch --on buildbox"
has "$out" "create   launch  task-create --task-title launch --deps build,remote" "  a block Orca lacks: create"
has "$out" "orphan   —       Orca task task_x (gone-block, pending) is in the Run but no block of the file" "  a Task no block names: orphan"
has "$out" "ok       probe   plan task as the file says" "  the plan side: a task as declared"
has "$out" "add      pick    plan task pick (memo), orca_task task_d (found by its title)" "  a Task found by its title: added with its id"
has "$out" "orphan   old     plan task of this ship, no block of the file" "  a plan task the file dropped"
has "$out" "record   remote  orca_task task_r (found by its title)" "  a recorded id Orca no longer has: the Task found by its title is recorded"
check "$(cut -d' ' -f1-2 "$T/orca-plan.calls" | sort -u | tr '\n' '|')" \
  "orchestration gate-list|orchestration run-show|orchestration task-list|orchestration worker-list|" "  Orca was asked the four reads, nothing else"
check "$(grep -c 'ELECTRON_RUN_AS_NODE=unset' "$T/orca-plan.calls")/$(wc -l < "$T/orca-plan.calls" | tr -d ' ')" "4/4" "  through the orca adapter's call: ELECTRON_RUN_AS_NODE cleared"
has "$(grep task-list "$T/orca-plan.calls")" "--from term_c" "  task-list from the recorded coordinator"
cp "$CR/docs/d.md" "$T/d.md.orig"
printf '\n  > **Proceeding with A** (session, 2026-10-16)\n' >> "$CR/docs/d.md"
check "$(cd "$CR" && O apply docs/blueprints/2026-10-16-demo.md --plan cp --dry-run | grep '^  resolve\|^  ok       pick')" \
  "  ok       pick    gate gate_1 waits on docs/d.md#D1, D2" "a session's own reply under D2 is no answer: the gate still waits"
cp "$T/d.md.orig" "$CR/docs/d.md"
# skipper-modes S3: in mode dnd a gate resolves as taken where nothing is held; the doc is not written here
smode() { python3 -c 'import json, sys; p = sys.argv[1]; d = json.load(open(p)); d.pop("mode", None) if sys.argv[2] == "-" else d.update(mode=sys.argv[2]); json.dump(d, open(p, "w"))' "$T/ship_plans/cp/plan.json" "$1"; }
smode dnd
check "$(cd "$CR" && O apply docs/blueprints/2026-10-16-demo.md --plan cp --dry-run | grep -c '^  resolve')" "0" \
  "mode dnd in a repo whose contract has no physical: line: held, the gate waits (keel reads none as physical)"
printf -- '- physical: none\n' > "$CR/AGENTS.md"   # the contract the dnd cases below need, never committed
check "$(cd "$CR" && O apply docs/blueprints/2026-10-16-demo.md --plan cp --dry-run | grep '^  resolve')" \
  "  resolve  pick    gate gate_1: answered (taken unattended (dnd): D2 A) — gate-resolve, then task-update completed" "mode dnd: D2's bare pick, nothing held — the gate resolves as taken"
check "$(grep -c 'Taken unattended' "$CR/docs/d.md")" "0" "  …and nothing is written to the doc: the next block's dnd run writes it"
python3 - "$CR/docs/d.md" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read(); i = t.index("- **D2")
open(p, "w").write(t[:i] + t[i:].replace("  - B — two\n", "  - B — two, a $12/yr domain\n", 1))
PY
check "$(cd "$CR" && O apply docs/blueprints/2026-10-16-demo.md --plan cp --dry-run | grep '^  resolve\|^  ok       pick')" \
  "  ok       pick    gate gate_1 waits on docs/d.md#D1, D2" "  money in D2's option: held, the gate waits on the owner"
cp "$T/d.md.orig" "$CR/docs/d.md"
smode ask
check "$(cd "$CR" && O apply docs/blueprints/2026-10-16-demo.md --plan cp --dry-run | grep '^  resolve\|^  ok       pick')" \
  "  ok       pick    gate gate_1 waits on docs/d.md#D1, D2" "mode ask: the gate waits on the owner's answer"
smode -
# a pinned ship's doc taken under dnd (follow-ups): memo_answered reads it from the pin's branch on origin,
# and the contract's physical: from the ship's main checkout, which has neither the doc nor its folder
PO="$T/pin-origin.git"; PM="$T/pin-main"; git init -q --bare "$PO"; git init -q -b main "$PM"
printf -- '- physical: none\n' > "$PM/AGENTS.md"; git -C "$PM" add -A; git -C "$PM" commit -qm contract; git -C "$PM" remote add origin "$PO"
git -C "$PM" push -q origin main; git -C "$PM" checkout -q -b claude/pin/doc; mkdir -p "$PM/docs"; cp "$T/d.md.orig" "$PM/docs/d.md"
git -C "$PM" add -A; git -C "$PM" commit -qm doc; git -C "$PM" push -q origin claude/pin/doc; git -C "$PM" checkout -q main; rm -rf "$PM/docs"
pinned() { python3 - "$B/wharf" "$PM" "$1" <<'PY'
import sys
from importlib.machinery import SourceFileLoader
w = SourceFileLoader("wharf_pin", sys.argv[1]).load_module()
rec = {"pin": {"branch": "claude/pin/doc", "repo": sys.argv[2], "rel": "docs/blueprints/x.md"}, "main": sys.argv[2]}
bp = {"path": "/nowhere/x.md", "meta": {"repo": sys.argv[2]}}
print(w.memo_answered(bp, rec, sys.argv[3] or None)("docs/d.md", ["D1", "D2"]))
PY
}
check "$(pinned dnd)" "(True, 'taken unattended (dnd): D2 A')" "a pinned ship's doc in mode dnd: read from its branch on origin, D2 taken (physical: none in the ship's main)"
check "$(pinned '')" "(False, None)" "  with no mode, the same doc waits on the owner"
printf -- '- physical: the box\n' > "$PM/AGENTS.md"
check "$(pinned dnd)" "(False, None)" "  the ship's main says physical: dnd holds the item, the gate waits"
rm -f "$CR/AGENTS.md"
# skipper-modes S3b: a blueprint's mode is a file any run can write, and a raise is a yes to merge
wm() { python3 - "$B/wharf" "$1" <<'PY'
import os, sys
from importlib.machinery import SourceFileLoader
w = SourceFileLoader("wharf_mod", sys.argv[1]).load_module()
bp = {"meta": {"mode": sys.argv[2], "repo": "/x/nowhere"}}
print(w.bp_mode("nosuchplan", bp), bool(w.bp_mode_refusal("nosuchplan", bp)))
PY
}
check "$(env -u CLAUDE_UNATTENDED bash -c "$(declare -f wm); B='$B' wm dnd")" "dnd False" "a blueprint's mode: dnd, applied by the owner — recorded"
check "$(CLAUDE_UNATTENDED=dispatch bash -c "$(declare -f wm); B='$B' wm dnd")" "None True" "  applied by an unattended run: a raise over default, not recorded (S3b)"
check "$(CLAUDE_UNATTENDED=dispatch bash -c "$(declare -f wm); B='$B' wm ask")" "ask False" "  …lowering to ask is free"
wm9() { python3 - "$B/wharf" <<'PY'
import sys
from importlib.machinery import SourceFileLoader
w = SourceFileLoader("wharf_mod9", sys.argv[1]).load_module()
bp = {"meta": {"mode": "dnd", "repo": "/x/nowhere"}}
print(bool(w.bp_mode_refusal("nosuchplan", bp, once=True)), w.bp_mode("mr", bp))
PY
}
mkdir -p "$T/wplans/mr"; echo '{"id": "mr", "tasks": {}, "mode_refused": {"mode": "dnd", "why": "x", "ts": 1}}' > "$T/wplans/mr/plan.json"
check "$(env -u CLAUDE_UNATTENDED PLANS_DIR="$T/wplans" bash -c "$(declare -f wm9); B='$B' wm9")" "True None" \
  "  the helm tick's --once apply (launchd, no CLAUDE_UNATTENDED) is no person: refused; a ship that refused once never records it (landing review 9)"
# a refusal judged while repos.json is torn (the ship reads ask) is kept nowhere: the next apply judges again
wmt() { python3 - "$B/wharf" <<'PY'
import sys
from importlib.machinery import SourceFileLoader
w = SourceFileLoader("wharf_modt", sys.argv[1]).load_module()
bp = {"meta": {"mode": "default", "repo": "/x/nowhere"}}
print(bool(w.bp_mode_refusal("nosuchplan", bp)), w.bp_mode_torn("nosuchplan", bp))
PY
}
printf '{"repos": {"x": ' > "$T/torn-repos.json"; printf '{"repos": {}, "scopes": {}}\n' > "$T/whole-repos.json"
check "$(CLAUDE_UNATTENDED=dispatch CLAUDE_REPOS_JSON="$T/torn-repos.json" bash -c "$(declare -f wmt); B='$B' wmt")" "True True" \
  "a torn registry: the ship reads ask, default over it is refused, and bp_mode_torn says not to keep it (the follow-ups' landing review)"
check "$(CLAUDE_UNATTENDED=dispatch CLAUDE_REPOS_JSON="$T/whole-repos.json" bash -c "$(declare -f wmt); B='$B' wmt")" "False False" \
  "  the registry whole again: no refusal, nothing torn"
# the second landing review: the apply judges both from one read — a registry that heals between two
# reads must not keep a refusal judged against the torn ask
wmj() { python3 - "$B/wharf" <<'PY'
import sys
from importlib.machinery import SourceFileLoader
w = SourceFileLoader("wharf_modj", sys.argv[1]).load_module()
bp = {"meta": {"mode": "default", "repo": "/x/nowhere"}}
reads = iter([("ask", w.helmlib.TORN_WHERE), ("default", "the default")])
w.helmlib.task_mode = lambda *a, **k: next(reads)
why, torn = w.bp_mode_judge("nosuchplan", bp)
print(bool(why), torn)
PY
}
check "$(CLAUDE_UNATTENDED=dispatch bash -c "$(declare -f wmj); B='$B' wmj")" "True True" \
  "  bp_mode_judge reads the ship's mode once: torn then healed, the refusal is still judged torn"
# the refusal an apply writes reaches plan.json: Ship.save reloads the plan and copies back only what it
# names, and dropped mode_refused, so the next tick recorded the run's mode (the follow-ups' landing review)
mkdir -p "$T/wplans/ms"; echo '{"id": "ms", "tasks": {}}' > "$T/wplans/ms/plan.json"
check "$(PLANS_DIR="$T/wplans" python3 - "$B/wharf" <<'PY'
import json, os, sys
from importlib.machinery import SourceFileLoader
w = SourceFileLoader("wharf_save", sys.argv[1]).load_module()
s = w.Ship.__new__(w.Ship)
s.dry, s.pid, s.rec = False, "ms", {}
s.bp = {"name": "b", "by_id": {}}
s.p = {"id": "ms", "tasks": {}}
s.p["mode_refused"] = s.refused_now = {"mode": "dnd", "why": "a raise by a run", "ts": 1}
s.save()
on_disk = json.load(open(os.path.join(os.environ["PLANS_DIR"], "ms", "plan.json")))
print(on_disk.get("mode_refused", {}).get("mode"), s.p.get("mode_refused", {}).get("mode"))
PY
)" "dnd dnd" "an apply's refusal is saved to plan.json and kept in the ship (landing review 9 holds on the next tick)"
# follow-ups item 3: a standing refusal is said again to a person's apply, with the line that lifts it
OA() { HARNESS_ORCA="$T/orca-plan" STUB_STATE="$T/orca-plan.json" STUB_CALLS="$T/orca-plan.calls" ELECTRON_RUN_AS_NODE=1 SW apply docs/blueprints/2026-10-16-demo.md --plan cp --dry-run 2>&1; }
cp "$CF" "$T/cf.orig"; cp "$T/ship_plans/cp/plan.json" "$T/cp-plan.orig"   # both put back byte for byte below
python3 -c 'import sys; p = sys.argv[1]; t = open(p).read(); open(p, "w").write(t.replace("created: ", "mode: dnd\ncreated: ", 1))' "$CF"
SW check "$CF" --plan cp --accept > /dev/null
python3 -c 'import json, sys; p = sys.argv[1]; d = json.load(open(p)); d.pop("mode", None); d["mode_refused"] = {"mode": "dnd", "why": "a raise by a run", "ts": 1}; json.dump(d, open(p, "w"))' "$T/ship_plans/cp/plan.json"
out=$(cd "$CR" && env -u CLAUDE_UNATTENDED bash -c "$(declare -f OA SW); T='$T' WH='$WH' OA")
has "$out" "mode dnd refused " "a person's apply says a standing refusal again (follow-ups item 3)"
has "$out" "(\`helm mode cp dnd\` records it): a raise by a run" "  with the helm mode line that lifts it"
out=$(cd "$CR" && CLAUDE_UNATTENDED=dispatch OA)
hasnt "$out" "refused " "  an unattended apply does not: it was said to that caller once"
cp "$T/cp-plan.orig" "$T/ship_plans/cp/plan.json"; cp "$T/cf.orig" "$CF"
python3 - "$CR/docs/d.md" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
open(p, "w").write(t.rstrip("\n") + "\n  A\n")
PY
check "$(cd "$CR" && O apply docs/blueprints/2026-10-16-demo.md --plan cp --dry-run | grep '^  resolve')" \
  "  resolve  pick    gate gate_1: answered (D1 B; D2 A) — gate-resolve, then task-update completed" "D2 answered in the doc: the gate resolves"
# a run dispatched before S5 still types `landed`: wharf's ENDED reads both (S5 review)
[ "$HELM_NAMES" = old ] && ended=landed || ended=launched
PLANS_DIR="$T/ship_plans" "$HM" report cp --task build --status "$ended" > /dev/null
has "$(cd "$CR" && O apply docs/blueprints/2026-10-16-demo.md --plan cp --dry-run)" "complete build   the plan has it ended, task_b is dispatched: task-update completed" \
  "the plan has a block launched, Orca has it dispatched: complete"
(cd "$CR" && STUB_DOWN=1 O apply docs/blueprints/2026-10-16-demo.md --plan cp --dry-run > /dev/null 2>"$T/err"); check "$?" "3" "Orca unreadable with a Run recorded: exit 3"
has "$(cat "$T/err")" "wharf apply: Orca unread — orca orchestration run-show: no runtime (runtime_unavailable)" "  and why"

echo "  plan task's blueprint fields"
P task cp probe --provider orca --agent claude --host here --done-when "marker:docs/d.md#B6a" --orca-task task_p2 \
  --orca-dispatch ctx_1 --orca-dispatch ctx_2 --orca-dispatch ctx_1 --ship demo > /dev/null
check "$(python3 -c "import json; t=json.load(open('$T/ship_plans/cp/plan.json'))['tasks']['probe']; print(t['provider'], t['agent'], t['host'], t['done_when'], t['orca_task'], t['orca_dispatches'])")" \
  "orca claude testhost {'marker': 'docs/d.md#B6a'} task_p2 ['ctx_1', 'ctx_2']" "plan task takes provider, agent, host (here: this Mac, as plan_fields writes it), done_when, orca_task, orca_dispatches"
P task cp merged --done-when pr_merged > /dev/null
check "$(python3 -c "import json; print(json.load(open('$T/ship_plans/cp/plan.json'))['tasks']['merged']['done_when'])")" "{'pr_merged': True}" "  --done-when pr_merged alone"
P task cp probe --done-when "sometime:soon" > /dev/null 2>&1; check "$?" "1" "  an unknown done_when kind: refused"
err=$(P task cp probe --done-when "sometime:soon" 2>&1); hasnt "$err" "Traceback" "  refused with a message, no traceback"
P task cp probe --done-when "{bad" > /dev/null 2>&1; check "$?" "1" "  --done-when that is broken JSON: refused"
P task cp probe --done-when "marker" > /dev/null 2>&1; check "$?" "1" "  --done-when marker with no value: refused, as a blueprint refuses it"
P task cp probe --provider teleport > /dev/null 2>&1; check "$?" "2" "  an unknown provider: refused"
check "$(P state cp | python3 -c "import json,sys; t=[t for t in json.load(sys.stdin)['tasks'] if t['id']=='probe'][0]; print(t['blueprint']['name'], t['blueprint']['host'], t['host'])")" \
  "demo testhost None" "state(): the blueprint fields nested, its host apart from the reporting host"
has "$(P show cp)" "ship demo: orca/claude on testhost · Orca task_p2 · dispatches ctx_1, ctx_2" "show: the blueprint line"
# a repo of helm's guarded list, read from helmlib so the suite names none
GUARDED1=$(python3 -c "import sys; sys.path.insert(0, sys.argv[1]); import helmlib; print(helmlib.GUARDED[0])" "$HELMBIN")
P task cp hidden --repo "/home/x/projects/$GUARDED1" --ship secret-topic --done-when "file:taxes/2026.md" > /dev/null
hasnt "$(P state cp --public)" "taxes/2026" "  a guarded task's blueprint fields never leave (K6)"
unset -f P SW O spec bad

echo "B7: wharf apply live against a stub orca — the Run, Tasks, gates, starts, done_when, the ledger"
unset PLAN_NO_WHARF
WS="$T/wstub"; WR="$T/wrepo"; mkdir -p "$WS" "$WR/docs/blueprints"
cat > "$WS/orca" <<'PY'
#!/usr/bin/env python3
# A stateful Orca 1.4.227 in the shapes P3 and P6 recorded: a Task is `ready` once its deps
# completed, `pending` before, `blocked` while a gate on it is pending; worker-start takes only a
# ready Task; a mutation needs a live terminal --from. Every call is logged, one line each.
import json, os, sys
args = [a for a in sys.argv[1:] if a != "--json"]
open(os.environ["STUB_CALLS"], "a").write(" ".join(a.replace("\n", "\\n") for a in args) + "\n")
p = os.environ["STUB_STATE"]
st = json.load(open(p)) if os.path.exists(p) else {"seq": 0, "repos": [], "terminals": {}, "runs": {}, "tasks": [], "gates": [], "workers": []}
def opt(k, d=None):
    return args[args.index(k) + 1] if k in args else d
def save():
    json.dump(st, open(p, "w"))
def nid(kind):
    st["seq"] += 1
    return "%s_%d" % (kind, st["seq"])
def ok(r):
    save(); print(json.dumps({"id": "x", "ok": True, "result": r})); sys.exit(0)
def no(code, msg):
    save(); print(json.dumps({"id": "x", "ok": False, "error": {"code": code, "message": msg}})); sys.exit(1)
if os.environ.get("STUB_FAIL") and " ".join(args).startswith(os.environ["STUB_FAIL"]):
    no("stub_fail", "failed on demand (STUB_FAIL)")
def live(h):
    return h in st["terminals"] and st["terminals"][h]["state"] == "live"
def settle():
    done = {t["id"] for t in st["tasks"] if t["status"] == "completed"}
    gated = {g["task_id"] for g in st["gates"] if g["status"] == "pending"}
    for t in st["tasks"]:
        if t["status"] in ("pending", "blocked", "ready"):
            ready = set(json.loads(t["deps"])) <= done
            t["status"] = "blocked" if t["id"] in gated else ("ready" if ready else "pending")
cmd = " ".join(args[:2])
if cmd == "repo list":
    ok({"repos": st["repos"]})
if cmd == "repo add":
    r = {"id": nid("repo"), "path": opt("--path")}; st["repos"].append(r); ok({"repo": r})
if cmd == "terminal create":
    h = nid("term"); st["terminals"][h] = {"state": "live", "title": opt("--title"), "worktree": opt("--worktree"), "command": opt("--command")}
    ok({"terminal": {"handle": h}})
if cmd == "terminal show":
    h = opt("--terminal")
    if h not in st["terminals"]:
        no("terminal_not_found", "no terminal %s" % h)
    gone = st["terminals"][h]["state"] != "live"   # Orca keeps a closed terminal's record (1.4.227, live)
    ok({"terminal": dict({"handle": h, "connected": not gone}, **({"exitCause": {"kind": "operator_close"}} if gone else {}))})
if cmd == "terminal close":
    st["terminals"].get(opt("--terminal"), {})["state"] = "closed"; ok({"closed": True})
if args[0] == "orchestration" and args[1] not in ("run-show", "run-list", "task-list", "gate-list", "worker-list", "worker-show", "check", "worker-stop"):
    if not live(opt("--from")):
        no("no_active_sender_terminal", "no live terminal %s" % opt("--from"))
if cmd == "orchestration run-create":
    r = {"id": nid("run"), "objective": opt("--objective"), "coordinator_handle": opt("--from")}; st["runs"][r["id"]] = r
    ok({"run": r, "mutation": {"requestId": nid("req")}})
if cmd == "orchestration run-use":
    st["runs"][opt("--id")]["coordinator_handle"] = opt("--from"); ok({"run": st["runs"][opt("--id")]})
if cmd == "orchestration run-list":
    ok({"runs": list(st["runs"].values())})
if cmd == "orchestration run-show":
    ok({"run": st["runs"][opt("--id")]})
if cmd == "orchestration task-create":
    t = {"id": nid("task"), "run_id": opt("--run"), "task_title": opt("--task-title"), "display_name": opt("--display-name"),
         "spec": opt("--spec"), "deps": opt("--deps", "[]"), "status": "pending", "result": None}
    st["tasks"].append(t); settle(); ok({"task": t, "mutation": {"requestId": nid("req")}})
if cmd == "orchestration task-list":
    ok({"tasks": [t for t in st["tasks"] if t["run_id"] == opt("--run")]})
if cmd == "orchestration task-update":
    t = [t for t in st["tasks"] if t["id"] == opt("--id")][0]
    if opt("--status") == "dispatched" and not any(w["taskId"] == t["id"] and w["dispatchStatus"] == "dispatched" for w in st["workers"]):
        no("task_not_startable", "Task %s cannot move to dispatched without an active Dispatch" % t["id"])   # 1.4.227, live
    t["status"] = opt("--status"); t["result"] = opt("--result")
    settle(); ok({"task": t})
if cmd == "orchestration gate-create":
    g = {"id": nid("gate"), "task_id": opt("--task"), "question": opt("--question"), "status": "pending", "resolution": None}
    st["gates"].append(g); settle(); ok({"gate": g})
if cmd == "orchestration gate-resolve":
    g = [g for g in st["gates"] if g["id"] == opt("--id")][0]; g.update(status="resolved", resolution=opt("--resolution")); settle(); ok({"gate": g})
if cmd == "orchestration gate-list":
    run = opt("--run"); ids = {t["id"] for t in st["tasks"] if t["run_id"] == run}
    ok({"gates": [g for g in st["gates"] if g["task_id"] in ids]})
if cmd == "orchestration worker-start":
    t = [t for t in st["tasks"] if t["id"] == opt("--task")][0]
    if t["status"] != "ready":
        no("task_not_ready", "task %s is %s" % (t["id"], t["status"]))
    d = {"dispatchId": nid("ctx"), "taskId": t["id"], "runId": opt("--run"), "dispatchStatus": "dispatched",
         "worktree": opt("--worktree"), "terminal": opt("--terminal"), "agent": opt("--agent"),
         "projection": {"outcome": "in_progress", "liveness": {"verdict": "live"}}}
    st["workers"].append(d); t["status"] = "dispatched"; ok({"dispatch": {"id": d["dispatchId"]}, "stage": "ready"})
if cmd == "orchestration worker-list":
    ok({"workers": [w for w in st["workers"] if w["runId"] == opt("--run")], "page": {"hasMore": False}})
if cmd == "orchestration check":   # --peek --types question: the Run's unread questions, nothing consumed
    ok({"messages": [m for m in st.get("messages", []) if m["run_id"] == opt("--run") and not m.get("read")], "count": 0})
if cmd == "orchestration worker-stop":   # what 1.4.227 answers for these terminals (2026-10-19)
    ok({"dispatchId": opt("--dispatch"), "processAction": "none"})
if cmd == "worktree list":   # Orca's registry of worktrees: STUB_WT_LIST (colon-separated paths) when set, else this stub has none
    if "STUB_WT_LIST" not in os.environ:
        no("stub", "the stub has no worktree list")
    ok({"worktrees": [{"path": x} for x in os.environ["STUB_WT_LIST"].split(":") if x], "truncated": False})
if cmd == "environment list":
    ok({"environments": [{"name": n, "id": "env-" + n} for n in os.environ.get("STUB_ENVS", "").split(",") if n]})
no("stub", "the stub has no %s" % cmd)
PY
cat > "$WS/account" <<'PY'
#!/usr/bin/env python3
import json, os, sys
a = sys.argv[1:]
open(os.environ["STUB_ACCT_CALLS"], "a").write(" ".join(a) + "\n")
if a[0] == "pick":
    if os.environ.get("STUB_WEEK") == "none":
        print(json.dumps({"skipped": [["acct-a", "week at 99 %"]]})); sys.exit(3)
    print(json.dumps({"account": "acct-a", "primary": False, "reason": "picked",
                      "env": {"CLAUDE_CONFIG_DIR": os.environ["STUB_ACCT_DIR"]} if os.environ.get("STUB_ACCT_DIR") else {}})); sys.exit(0)
sys.exit(0 if a[0] == "ships" else 4)
PY
chmod +x "$WS/orca" "$WS/account"
printf '# wrepo\n\n- physical: none\n' > "$WR/AGENTS.md"
cat > "$WR/docs/d.md" <<'EOF'
# A doc

## Decisions

- **D1 — Which way** (why)
  - A — one
  - B — two

  Reversible: yes

  ➤ Recommended: A

  ➤ Answer:
  B
EOF
brief() { printf '## %s\nTask: %s\nTier: worker\nWhy: a test\nStart here: here\nDone means: %s\nNot this: live\n' "$1" "$2" "$3"; }
{ printf -- '---\nship: three\nrepo: %s\nskipper: tester\ncreated: 2026-10-17\nblocks:\n' "$WR"
  printf '  - id: probe\n    provider: orca\n    agent: claude\n    model: sonnet\n    effort: high\n    done_when: {file: probe.txt}\n'
  printf '  - id: pick\n    kind: decision\n    doc: docs/d.md\n    items: [D1]\n    depends_on: [probe]\n'
  printf '  - id: launch\n    provider: shell\n    command: "basename <wt> > \\"$WOUT\\""\n    depends_on: [probe, pick]\n    launch: autofinish\n---\n'
  brief probe "write probe.txt" "probe.txt"; } > "$WR/docs/blueprints/2026-10-17-three.md"
{ printf -- '---\nship: solo\nrepo: %s\ncreated: 2026-10-17\nblocks:\n  - id: solo\n    provider: shell\n    command: "echo x >> \\"$WCOUNT\\""\n---\n' "$WR"; } > "$WR/docs/blueprints/2026-10-17-solo.md"
{ printf -- '---\nship: gated\nrepo: %s\ncreated: 2026-10-17\nblocks:\n  - id: o1\n    provider: orca\n    agent: claude\n' "$WR"
  printf '  - id: rem\n    provider: claude-code\n    host: buildbox\n'
  printf '  - id: ro\n    provider: orca\n    agent: claude\n    host: buildbox\n---\n'; brief o1 "o" "o"; brief rem "r" "r"; brief ro "r" "r"; } > "$WR/docs/blueprints/2026-10-17-gated.md"
sed 's/ship: solo/ship: fresh/' "$WR/docs/blueprints/2026-10-17-solo.md" > "$WR/docs/blueprints/2026-10-17-fresh.md"
git -C "$WR" init -q -b main && git -C "$WR" add -A && git -C "$WR" -c user.name=t -c user.email=t@t commit -qm init
export WOUT="$T/wout" WCOUNT="$T/wcount"
W() { env PLANS_DIR="$T/wplans" HARNESS_ORCA="$WS/orca" STUB_STATE="$WS/state.json" STUB_CALLS="$WS/calls" HARNESS_ACCOUNT="$WS/account" \
          AUTOFINISH_ACCOUNT="$WS/account" STUB_ACCT_CALLS="$WS/acct" HARNESS_HOST=testhost HARNESS_ORCA_OWN="$WS/own.json" \
          HARNESS_ORCA_START_WAIT=2 PLAN_NO_RENDER=1 "$@"; }
n() { grep -c "^$1" "$WS/calls" 2>/dev/null || true; }
sq() { python3 -c "import json,sys; st=json.load(open('$WS/state.json')); print($1)"; }
pj() { python3 -c "import json,sys; p=json.load(open('$T/wplans/wp/plan.json')); print($1)"; }
pst() { W "$HM" state wp | python3 -c "import json,sys; print(' '.join('%s=%s' % (t['id'], t['status']) for t in sorted(json.load(sys.stdin)['tasks'], key=lambda t: '$1'.split().index(t['id']) if t['id'] in '$1'.split() else 0) if t['id'] in '$1'.split()))"; }
W "$HM" $SHIP wharf --id wp > /dev/null
BP="$WR/docs/blueprints/2026-10-17-three.md"

out=$(W "$WH" apply "$BP" --plan wp); check "$?" "0" "the first apply compiles the ship: exit 0"
has "$out" "Run run_" "  a Run, said"
check "$(n 'orchestration run-create')/$(n 'terminal create --worktree path:'"$WR"' --title wharf three')" "1/1" "  one run-create, from a coordinator terminal made in the repo's checkout"
check "$(n 'orchestration task-create')/$(n 'orchestration gate-create')" "3/1" "  a Task per block, a gate on the decision"
check "$(sq "[(t['task_title'], t['status'], [[x['task_title'] for x in st['tasks'] if x['id'] == d][0] for d in json.loads(t['deps'])]) for t in st['tasks']]")" \
  "[('probe', 'dispatched', []), ('pick', 'blocked', ['probe']), ('launch', 'pending', ['probe', 'pick'])]" "  Orca's deps are the Tasks' own ids; the ready block started at once"
TP=$(sq "[t['id'] for t in st['tasks'] if t['task_title'] == 'probe'][0]"); RUN=$(sq "list(st['runs'])[0]")
CO=$(sq "list(st['runs'].values())[0]['coordinator_handle']"); DP=$(sq "st['workers'][0]['dispatchId']"); OWN=$(sq "st['workers'][0]['terminal']")
GT=$(sq "st['gates'][0]['id']")
has "$(grep '^orchestration task-create' "$WS/calls" | head -1)" "--task-title probe --display-name claude/testhost/2026-10-17-probe" "  titled by block, shown by branch"
has "$(grep '^orchestration task-create' "$WS/calls" | head -1)" "Task: write probe.txt" "  the spec is the block's brief whole"
has "$(grep '^orchestration task-create' "$WS/calls" | head -1)" "\\n\\n### Yard rules\\n\\n- Read a file's first lines on \`main\`" "  and the Yard rules below it (yard-smooth, 2026-10-19)"
hasnt "$(grep '^orchestration task-create --spec shell:' "$WS/calls")" "Yard rules" "  a shell block's spec carries none"
check "$(n "orchestration worker-start --task $TP --worktree path:$WR/.claude/worktrees/probe --terminal $OWN")" "1" "  the start: worker-start --task in our worktree by path, on a picked login's terminal (orca.start)"
check "$(git -C "$WR/.claude/worktrees/probe" symbolic-ref --short HEAD)" "claude/testhost/2026-10-17-probe" "  the worktree made our way, on the block's branch"
check "$(git -C "$WR/.claude/worktrees/probe" rev-parse HEAD)" "$(git -C "$WR" rev-parse main)" "  from local main"
has "$(sq "st['terminals']['$OWN']['command']")" "env -u CLAUDE_CODE_OAUTH_TOKEN -u CLAUDE_CONFIG_DIR claude --model sonnet --effort high" "  the login terminal runs claude with the block's model and effort"
has "$(cat "$WS/acct")" "ships --pin three acct-a" "  the ship pinned to the login it started on"
check "$(pj "(p['blueprints']['three']['orca_run'], p['blueprints']['three']['coordinator'], p['tasks']['probe']['orca_task'], p['tasks']['probe']['orca_dispatches'], p['tasks']['launch']['provider'])")" \
  "('$RUN', '$CO', '$TP', ['$DP'], 'shell')" "  plan.json: the Run, its coordinator, each block's Task and Dispatch, the plan fields"
check "$(pst 'probe pick launch')" "probe=running pick=waiting launch=planned" "  plan report lines: probe running, pick waiting on its gate"
check "$(pj "len(p['blueprints']['three']['ledger']) == sum(1 for e in p['blueprints']['three']['ledger'] if e['state'] == 'done')")" "True" "  every ledger line settled"

out=$(W "$WH" apply "$BP" --plan wp --once); check "$?" "0" "a second pass (--once): exit 0"
check "$(n 'orchestration task-create')/$(n 'orchestration worker-start')/$(n 'orchestration run-create')" "3/1/1" "  creates nothing twice, starts nothing twice"

python3 - "$WS/state.json" <<'PY'
import json, sys
p = sys.argv[1]; st = json.load(open(p))
# the worker's worker_done, as Orca settles it: the Dispatch and the Task completed
for w in st["workers"]:
    w.update(dispatchStatus="completed", projection={"outcome": "succeeded", "liveness": {"verdict": "exited"}})
for t in st["tasks"]:
    if t["task_title"] == "probe":
        t["status"] = "completed"
    elif t["task_title"] == "launch":
        t["status"] = "pending"
json.dump(st, open(p, "w"))
PY
out=$(W "$WH" apply "$BP" --plan wp --once); check "$?" "0" "the worker done, done_when unmet: exit 0"
has "$out" "plan  unmet    probe   file probe.txt" "  done_when read: the file is not there"
check "$(pst probe)" "probe=blocked" "  so the plan says blocked, not done"
has "$out" "orca  wait     pick    answered; its gate resolves once probe ends" "  and its decision waits, though Orca completed probe's Task"
check "$(n 'orchestration gate-resolve')" "0" "  no gate resolved yet"
PGD=$(git -C "$WR/.claude/worktrees/probe" rev-parse --absolute-git-dir); mkdir -p "$PGD/claude"
printf '{"session": "builder-0000-4000-8000-000000000000", "branch": "claude/testhost/2026-10-17-probe", "seen": %s}' "$(date +%s)" > "$PGD/claude/owner.json"
touch "$WR/.claude/worktrees/probe/probe.txt"
out=$(W "$WH" apply "$BP" --plan wp); check "$?" "0" "the file written: one apply carries the ship to its end"
has "$out" "plan  done     probe   file probe.txt" "  done_when holds: done"
has "$out" "orca  resolve  pick    gate $GT resolved: D1 B" "  the gate resolved from the memo answer"
check "$(python3 -c "import json; l=json.load(open('$PGD/claude/owner.json')); print(l['session'][:8], type(l.get('handover')).__name__)")" "builder- float" "  the settled builder's lock marked handed over, its holder kept (yard-smooth 1)"
has "$out" "probe: lock handed over (session builder-)" "  said"
check "$(n "orchestration worker-stop --dispatch $DP")" "1" "  and Orca asked to stop its worker"
has "$out" "probe: worker-stop $DP: processAction none" "  its answer said"
has "$out" "orca  start    launch  ran \`basename $WR/.claude/worktrees/probe > \"\$WOUT\"\`: exit 0" "  the shell launch ran, <wt> its predecessor's worktree"
check "$(cat "$WOUT")" "probe" "  and it really ran"
check "$(sq "[t['status'] for t in st['tasks']]")" "['completed', 'completed', 'completed']" "  every Task completed in Orca"
check "$(pst 'probe pick launch')" "probe=done pick=done launch=done" "  every block done in the plan"
check "$(n 'orchestration task-create')/$(n 'orchestration gate-resolve')/$(n 'orchestration worker-start')" "3/1/1" "  three creates, one resolve, one start in all"
has "$out" "every block ended: the ship is marked ended, its coordinator $CO closed" "  the ship ended: marked, its coordinator closed"
check "$(sq "st['terminals']['$CO']['state']")" "closed" "  the terminal really closed in Orca"
out=$(W "$WH" status three --plan wp); check "$?" "0" "wharf status: exit 0"
has "$out" "ship three — Run $RUN, coordinator $CO" "  the ship's Run"
has "$out" "probe   done     orca completed  dispatch $DP completed" "  a block: the plan, Orca, the Dispatch"
has "$(W "$WH" apply "$BP" --plan wp --once)" "wharf apply --once: three ended" "plan apply is wharf apply's shim; --once leaves an ended ship alone"
out=$(W "$WH" apply "$BP" --plan wp); check "$?" "0" "an attended apply of the ended ship opens it again"
has "$out" "(the last one is gone)" "  its closed coordinator is replaced (terminal show: connected false), the Run taken by run-use"
check "$(n 'orchestration run-use')/$(n 'orchestration run-create')" "1/1" "  one run-use, still one Run"

echo "  wharf next, dispatch --next's question: a ship's block has its successor in the file (wharf-on-orca S5, B9)"
PB=$(pj "p['tasks']['probe']['branch']")
WN() { W env "$E_SHIP"="$1" DISPATCH_TASK="$2" "$WH" next "$PB" "${@:3}"; }   # a session's own record: its plan and block
out=$(WN wp probe); check "$?" "0" "a ship's block asking from its own plan: exit 0"
has "$out" "is block probe of ship three" "  says the block and the ship"
has "$out" "next is pick (a decision), launch" "  names the blueprint's next blocks, a decision said as one"
has "$out" "nothing is seeded here" "  and that wharf apply starts them"
check "$(WN wp probe --json | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['ship'], d['block'], ','.join(d['next']))")" "three probe pick,launch" "  --json says the same"
out=$(WN wp probe --repo "$WR"); check "$?" "0" "  --repo the blueprint's own: the same"
out=$(WN wp probe --repo "$T/elsewhere"); check "$?/$out" "1/" "  --repo another: not this ship's block, nothing printed"
out=$(W env "$E_SHIP"=wp "$WH" next "$PB"); check "$?/$out" "1/" "wharf's own start (a plan, no block): exit 1, so the seed goes on"
out=$(W "$WH" next "$PB"); check "$?/$out" "1/" "a session with no plan: exit 1 — the branch's name alone names no ship"
out=$(WN wp launch); check "$?/$out" "1/" "the last block, nothing after it: exit 1, nothing printed"
out=$(WN wp nosuchblock); check "$?/$out" "1/" "a block no blueprint of the plan has: exit 1"
out=$(WN nosuchplan probe); check "$?/$out" "1/" "a plan this Mac does not have: exit 1"
mkdir -p "$T/wplans/brokenplan"; echo "{bad" > "$T/wplans/brokenplan/plan.json"
out=$(WN brokenplan probe 2>&1); check "$?" "2" "a plan.json that does not parse: exit 2, never 'not a ship'"
out=$(W env "$E_SHIP"=wp DISPATCH_TASK=probe "$WH" next claude/laptop/2026-10-19-other-handoff); check "$?/$out" "1/" "the block's session starting another branch (a handoff, its next stage): exit 1, it goes on"
cp "$BP" "$T/bp.keep"; echo "not a blueprint" > "$BP"
out=$(WN wp probe 2>&1); check "$?" "2" "the block's own blueprint no longer loads: exit 2…"
has "$out" "does not load" "  …saying so on stderr, never read as 'not a ship'"
rm "$BP"
out=$(WN wp probe 2>&1); check "$?" "2" "the block's own blueprint is gone: exit 2…"
has "$out" "recorded, not found" "  …saying so, never read as 'not a ship'"
cp "$T/bp.keep" "$BP"

echo "  a handoff is a one-block ship: pickup seed writes docs/blueprints/<date>-<topic>.md beside its brief"
HR="$T/home/projects/hdemo"; mkdir -p "$HR/.claude" "$T/hbp" "$T/home/.claude/projects" "$T/home/.claude/sessions"
git -C "$HR" init -q -b main; git -C "$HR" config user.email t@t; git -C "$HR" config user.name t
echo '{"checkpoint": true, "main": "main"}' > "$HR/.claude/workflow.json"; echo x > "$HR/f"; git -C "$HR" add -A; git -C "$HR" commit -qm init
TODAY=$(date +%F)
printf '# hand-topic — handoff from demo: tests, %s\nTask: do the follow-up\nTier: Opus 5.5 high\nWhy: found it\nStart here: /x/a.py\nDone means: a test passes\nNot this: b\n## a heading in the brief\nSteps: S3 of docs/x.md\n' "$TODAY" > "$T/hbrief.md"
PK() { env PICKUP_HOST=laptop PICKUP_NO_START=1 CLAUDE_CODE_SESSION_ID=9aaaaaaa-0000-4000-8000-000000000001 python3 "$B/pickup" "$@"; }
out=$(PK seed hand-topic --file "$T/hbrief.md" --repo "$HR" --no-start --no-fetch 2>&1); check "$?" "0" "seed: exit 0"
HBR="claude/laptop/$TODAY-hand-topic"
check "$(git -C "$HR" diff --name-only main "$HBR" | tr '\n' ' ')" "docs/blueprints/$TODAY-hand-topic.md docs/handoff/$TODAY-hand-topic.md " "the seed commit holds the brief and its blueprint"
has "$out" "and its one-block blueprint docs/blueprints/$TODAY-hand-topic.md" "  and says so"
git -C "$HR" show "$HBR:docs/blueprints/$TODAY-hand-topic.md" > "$T/hbp/$TODAY-hand-topic.md"
out=$(W "$WH" check "$T/hbp/$TODAY-hand-topic.md"); check "$?" "0" "wharf check passes on the handoff's blueprint"
has "$out" "hand-topic  claude-code" "  one block, provider claude-code"
has "$out" "1 blocks in 1 waves" "  a one-block ship"
check "$(python3 - "$T/hbp/$TODAY-hand-topic.md" "$B" <<'PY'
import sys
sys.path.insert(0, sys.argv[2])
import blueprintlib
bp = blueprintlib.load(sys.argv[1])
st = bp["blocks"][0]
print(bp["meta"]["repo"], st["id"], st["raw"]["provider"], "done_when" in st["raw"], "Steps: S3 of docs/x.md" in st["section"], "### a heading in the brief" in st["section"])
PY
)" "hdemo hand-topic claude-code False True True" "  the brief's lines are its section (a heading demoted), the repo a name under ~/projects"
check "$(git -C "$HR" show "$HBR:docs/handoff/$TODAY-hand-topic.md" | cmp - "$T/hbrief.md" && echo same)" "same" "the brief is still there, as written: pickup and dispatch read it"
out=$(PK seed hand-two --file "$T/hbrief.md" --repo "$HR" --no-start --no-fetch --no-blueprint 2>&1)
check "$(git -C "$HR" diff --name-only main "claude/laptop/$TODAY-hand-two")" "docs/handoff/$TODAY-hand-two.md" "--no-blueprint (a ship's own block, wharf's seed): the brief alone"
printf '# t\nTask: only a task\n' > "$T/hshort.md"
out=$(PK seed hand-three --file "$T/hshort.md" --repo "$HR" --no-start --no-fetch 2>&1); check "$?" "0" "a brief that makes no valid blueprint still seeds…"
check "$(git -C "$HR" diff --name-only main "claude/laptop/$TODAY-hand-three")" "docs/handoff/$TODAY-hand-three.md" "  …as the brief alone"
has "$out" "no blueprint beside the brief: " "  and says why"

echo "  a crash between a call and its record replays once"
SB="$WR/docs/blueprints/2026-10-17-solo.md"
W env WHARF_CRASH=task-create:solo "$WH" apply "$SB" --plan wp > /dev/null 2>&1; check "$?" "9" "  the apply dies after task-create, before its record"
check "$(pj "p['tasks'].get('solo', {}).get('orca_task')")" "None" "  nothing recorded"
out=$(W "$WH" apply "$SB" --plan wp); check "$?" "0" "  the next apply: exit 0"
has "$out" "ledger: task-create solo was sent and never recorded — Orca's state decides" "  the dangling line said"
check "$(grep -c 'task-create --spec shell: echo' "$WS/calls")" "1" "  no second task-create: the Task found by its title"
check "$(pj "p['tasks']['solo']['orca_task']")" "$(sq "[t['id'] for t in st['tasks'] if t['task_title'] == 'solo'][0]")" "  and recorded"
check "$(wc -l < "$WCOUNT" | tr -d ' ')" "1" "  the block ran once"
sed 's/ship: solo/ship: solo2/; s/id: solo/id: solo2/' "$SB" > "$WR/docs/blueprints/2026-10-17-solo2.md"; SB="$WR/docs/blueprints/2026-10-17-solo2.md"
W env WHARF_CRASH=shell:solo2 "$WH" apply "$SB" --plan wp > /dev/null 2>&1; check "$?" "9" "  a shell block dies after its command, before its record"
out=$(W "$WH" apply "$SB" --plan wp); check "$(wc -l < "$WCOUNT" | tr -d ' ')" "2" "  the next apply does not run it again"
has "$(sq "[t['result'] for t in st['tasks'] if t['task_title'] == 'solo2']")" "interrupted: the command's result was never recorded" "  its Task failed, said why"
# S5 review: a ship accepted first (`wharf check --accept`) has its digest before its first apply,
# and that apply still sets its start
W "$HM" $SHIP wharf-a --id wa > /dev/null; W "$WH" check "$SB" --plan wa --accept > /dev/null; W "$WH" apply "$SB" --plan wa > /dev/null
check "$(python3 -c "import json; p=json.load(open('$T/wplans/wa/plan.json')); print(bool(p.get('started')))")" "True" "a ship accepted before its first apply: started set by that apply"

echo "  refusals"
calls=$(wc -l < "$WS/calls")
sed -i.bak 's/^Task: write probe.txt$/Task: write probe.txt twice/' "$BP"; rm -f "$BP.bak"
out=$(W "$WH" apply "$BP" --plan wp); check "$?" "1" "a changed digest refuses: exit 1"
has "$out" "refused — changed since accepted" "  says so"
has "$out" "changed probe" "  names the block"
check "$(wc -l < "$WS/calls" | tr -d ' ')" "$(echo $calls | tr -d ' ')" "  and Orca was not called"
out=$(W "$WH" apply "$WR/docs/blueprints/2026-10-17-fresh.md" --plan wp --once); check "$?" "2" "--once on a ship never compiled: exit 2"
has "$out" "its first compile is an attended \`wharf apply\`" "  says whose it is"
GB="$WR/docs/blueprints/2026-10-17-gated.md"
out=$(W env CLAUDE_UNATTENDED=dispatch "$WH" apply "$GB" --plan wp); check "$?" "0" "a ship whose blocks may not start: exit 0"
has "$out" "orca  refuse   o1   refused: a session start is attended only (CLAUDE_UNATTENDED=dispatch)" "  unattended: an Orca start refused"
has "$out" "orca  refuse   rem  refused: host: buildbox — a claude-code block there starts by \`dispatch --on buildbox\`" "  a claude-code block on another host: dispatch's, not apply's"
has "$out" "orca  refuse   ro   refused: host: buildbox — no Orca environment paired as buildbox" "  an Orca block on an unpaired host: refused, naming the pairing"
out=$(W env CLAUDE_UNATTENDED=dispatch STUB_ENVS=buildbox "$WH" apply "$GB" --plan wp --once)
has "$out" "ro   refused: a session start is attended only" "  paired: past the host's gate, to the next one (attended only)"
out=$(W env DISPATCH_DEPTH=1 "$WH" apply "$GB" --plan wp --once); has "$out" "refused: a ship starts its blocks at depth 0 (DISPATCH_DEPTH=1)" "  below depth 0: refused"
out=$(W env STUB_WEEK=none "$WH" apply "$GB" --plan wp --once); has "$out" "refused: the week says none: acct-a: week at 99 %" "  a login with no week left: refused (account pick --cached)"
check "$(n 'orchestration worker-start')" "1" "  and nothing started"
out=$(W python3 - "$T/wplans/wp/wharf-gated.lock" "$WH" "$GB" <<'PY'
import fcntl, subprocess, sys
f = open(sys.argv[1], "w"); fcntl.flock(f, fcntl.LOCK_EX)
r = subprocess.run([sys.argv[2], "apply", sys.argv[3], "--plan", "wp", "--once"], capture_output=True, text=True)
print(r.returncode, r.stdout.strip())
PY
); has "$out" "4 wharf apply: gated is being applied by another run" "the strict lock: a second apply of one ship exits 4"
sed -i.bak 's/^Task: write probe.txt twice$/Task: write probe.txt/' "$BP"; rm -f "$BP.bak"

echo "  an Orca block on a paired host: the house worktree there over ssh, then worker-start --on (wharf-on-orca S3)"
export HARNESS_PEER_BUILDBOX=buildbox-ssh   # the harness seam for a peer alias, whatever PEERS holds
RR="$HOME/projects/rrepo"; mkdir -p "$HOME/projects" "$T/peer/projects"
git clone -q "$WR" "$RR" && git clone -q "$WR" "$T/peer/projects/rrepo"
{ printf -- '---\nship: remote\nrepo: %s\ncreated: 2026-10-18\nblocks:\n  - id: far\n    provider: orca\n    agent: claude\n    host: buildbox\n    model: sonnet\n---\n' "$RR"
  brief far "work on the peer" "a PR"; } > "$RR/docs/blueprints/2026-10-18-remote.md"
git -C "$RR" add -A && git -C "$RR" -c user.name=t -c user.email=t@t commit -qm remote
# ssh: the peer's home is $T/peer; the remote command (its last argument) reads the recipe on stdin
printf '#!/bin/sh\necho "$*" >> "%s"\nfor a; do last=$a; done\nHOME="%s" exec sh -c "$last"\n' "$WS/ssh.calls" "$T/peer" > "$WS/ssh"; chmod +x "$WS/ssh"
RB="$RR/docs/blueprints/2026-10-18-remote.md"; : > "$WS/acct"
out=$(W env WHARF_SSH="$WS/ssh" STUB_ENVS=buildbox "$WH" apply "$RB" --plan wp); check "$?" "0" "  apply: exit 0"
PW="$T/peer/projects/rrepo/.claude/worktrees/far"   # as the host's $PWD prints it
has "$out" "started dispatch ctx_" "  started"
has "$out" "on claude/buildbox/2026-10-18-far on buildbox (login buildbox's Orca's own)" "    on the host's branch, on the login the host's Orca holds"
has "$(cat "$WS/ssh.calls")" "-o BatchMode=yes -o ConnectTimeout=10 buildbox-ssh sh -s -- rrepo far claude/buildbox/2026-10-18-far wp/remote" "    the recipe over ssh, by bin/harness's alias, in the host's clone"
check "$(git -C "$PW" symbolic-ref --short HEAD)" "claude/buildbox/2026-10-18-far" "    the worktree made there, on its branch from local main"
check "$(cat "$(git -C "$PW" rev-parse --absolute-git-dir)/wharf-ship")" "wp/remote" "    and marked this ship's"
has "$(cat "$WS/calls")" "orchestration worker-start --task" "    then worker-start"
check "$(grep 'orchestration worker-start' "$WS/calls" | tail -1 | grep -c -- "--on buildbox --worktree path:$PW --agent claude")" "1" "    --on the host, the exact path: selector, Orca's own launch"
check "$(grep -c -- '--ship remote' "$WS/acct")" "0" "    no login picked on this Mac for it (the week's read is the gate's, not a pick)"
check "$(grep 'orchestration worker-list --run' "$WS/calls" | grep -vc -- '--include-remote')" "0" "    wharf reads its workers with --include-remote, so the remote one is not unverifiable (review 2026-10-18)"
out=$(W env WHARF_SSH="$WS/ssh" STUB_ENVS=buildbox "$WH" apply "$RB" --plan wp --once); check "$(grep -c 'orchestration worker-start' "$WS/calls")" "2" "  a second apply starts nothing more"
git -C "$T/peer/projects/rrepo" worktree add -q "$T/peer/projects/rrepo/.claude/worktrees/gone" -b x-gone main   # someone else's, on another branch
sed 's/id: far/id: gone/; s/^## far/## gone/; s/ship: remote/ship: remote2/' "$RB" > "$RR/docs/blueprints/2026-10-18-remote2.md"
git -C "$RR" add -A && git -C "$RR" -c user.name=t -c user.email=t@t commit -qm remote2
out=$(W env WHARF_SSH="$WS/ssh" STUB_ENVS=buildbox "$WH" apply "$RR/docs/blueprints/2026-10-18-remote2.md" --plan wp)
has "$out" "not started: the worktree on buildbox:" "  a worktree there the recipe refuses: not started, saying why"
check "$(grep -c 'orchestration worker-start' "$WS/calls")" "2" "    and nothing started"
unset HARNESS_PEER_BUILDBOX

echo "  the review's cases (2026-10-17)"
mkbp() { { printf -- '---\nship: %s\nrepo: %s\ncreated: 2026-10-17\nblocks:\n' "$1" "$WR"; printf "$2"; printf -- '---\n'; } > "$WR/docs/blueprints/2026-10-17-$1.md"; echo "$WR/docs/blueprints/2026-10-17-$1.md"; }
DB=$(mkbp dec '  - id: ask\n    kind: decision\n    doc: docs/d.md\n    items: [D1]\n  - id: after\n    provider: shell\n    command: "echo d >> \\"$WCOUNT\\""\n    depends_on: [ask]\n')
W env WHARF_CRASH=gate-resolve:ask "$WH" apply "$DB" --plan wp > /dev/null 2>&1; check "$?" "9" "a crash after gate-resolve, before its record"
out=$(W "$WH" apply "$DB" --plan wp); has "$out" "orca  complete ask" "  the next apply completes the decision's Task"
check "$(pst 'ask after')" "ask=done after=done" "  and the plan ends it, so its dependent runs (it was held for ever)"
EB=$(mkbp respec '  - id: ask2\n    kind: decision\n    doc: docs/d.md\n    items: [D9]\n  - id: after2\n    provider: shell\n    command: "echo one"\n    depends_on: [ask2]\n')
W "$WH" apply "$EB" --plan wp > /dev/null; OLD=$(pj "p['tasks']['after2']['orca_task']")
sed -i.bak 's/echo one/echo two/' "$EB"; rm -f "$EB.bak"; W "$WH" check "$EB" --plan wp --accept > /dev/null
out=$(W "$WH" apply "$EB" --plan wp); has "$out" "re-spec  after2" "a re-spec cancels the pending Task"
check "$(grep -c -- '--task-title after2 ' "$WS/calls")/$([ "$(pj "p['tasks']['after2']['orca_task']")" != "$OLD" ] && echo new)" "2/new" "  and creates it again, recorded (the cancelled one is never found by its title)"
check "$(sq "[t['spec'] for t in st['tasks'] if t['id'] == '$(pj "p['tasks']['after2']['orca_task']")'][0]")" "shell: echo two" "  with the new spec"
FB=$(mkbp lost '  - id: lost\n    provider: shell\n    command: "echo l >> \\"$WCOUNT\\""\n')
before=$(wc -l < "$WCOUNT" | tr -d ' ')
W env STUB_FAIL="orchestration task-update" "$WH" apply "$FB" --plan wp > /dev/null 2>&1
out=$(W "$WH" apply "$FB" --plan wp); has "$out" "sent its end again (the ledger: it ran once): completed" "a shell block whose end Orca never took: sent again, not run again"
check "$(( $(wc -l < "$WCOUNT" | tr -d ' ') - before ))/$(sq "[t['status'] for t in st['tasks'] if t['task_title'] == 'lost'][0]")/$(pst lost)" "1/completed/lost=done" "  ran once; Orca and the plan end it"
CB=$(mkbp clash '  - id: lost\n    provider: shell\n    command: "true"\n')
out=$(W "$WH" apply "$CB" --plan wp); check "$?" "2" "a block id another ship's plan task: refused, exit 2"
has "$out" "lost (ship lost)" "  names it"
SL=$(mkbp slow '  - id: nap\n    provider: shell\n    command: "sleep 3"\n')
W "$WH" apply "$SL" --plan wp > /dev/null 2>&1 &
sleep 1.5; W "$HM" task wp manual --title "made mid-apply" > /dev/null; wait
check "$(pj "sorted(k for k in p['tasks'] if k in ('manual', 'nap'))")" "['manual', 'nap']" "a plan task made during an apply survives its saves"
echo "  the second review's cases (2026-10-18)"
SL2=$(mkbp slow2 '  - id: nap2\n    provider: shell\n    command: "sleep 3"\n')
W "$WH" apply "$SL2" --plan wp > /dev/null 2>&1 &
sleep 1.5; out=$(W "$WH" check "$SL2" --plan wp --accept); rc=$?; W "$HM" eta wp nap2 40m > /dev/null; wait
check "$rc" "4" "check --accept while its ship is applied: exit 4, nothing written under the apply"
has "$out" "is being applied right now" "  says so"
check "$(pj "p['tasks']['nap2'].get('eta') is not None")" "True" "an ETA set during an apply survives its saves (only wharf's keys are written)"
W "$HM" task wp handmade --title "by hand" > /dev/null
HB=$(mkbp hand '  - id: handmade\n    provider: shell\n    command: "true"\n')
out=$(W "$WH" apply "$HB" --plan wp); check "$?" "2" "a block id a hand-made plan task holds: refused, exit 2"
has "$out" "handmade (a plan task of no ship)" "  names it"
RB=$(mkbp rspec '  - id: gate3\n    kind: decision\n    doc: docs/d.md\n    items: [D9]\n  - id: rs\n    provider: shell\n    command: "echo r1 >> \\"$WCOUNT\\""\n')
W env STUB_FAIL="orchestration task-update" "$WH" apply "$RB" --plan wp > /dev/null 2>&1
sed -i.bak 's/echo r1/echo r2/' "$RB"; rm -f "$RB.bak"; W "$WH" check "$RB" --plan wp --accept > /dev/null
out=$(W "$WH" apply "$RB" --plan wp)
check "$(grep -c '^r1$' "$WCOUNT")/$(grep -c '^r2$' "$WCOUNT")" "1/1" "a re-specced shell block runs its new command on its new Task (not the old Task's end sent again)"
SB3=$(mkbp coord '  - id: co1\n    provider: shell\n    command: "true"\n    depends_on: []\n')
W "$WH" apply "$SB3" --plan wp > /dev/null 2>&1
terms=$(sq "len(st['terminals'])")
out=$(W env STUB_FAIL="terminal show" "$WH" apply "$SB3" --plan wp 2>&1); check "$?" "3" "terminal show failing (not terminal_not_found): exit 3"
check "$(sq "len(st['terminals'])")" "$terms" "  and no new coordinator opened over a live one"
check "$(W python3 - "$B" <<'PY'
import importlib.machinery, sys, types
from pathlib import Path
w = importlib.machinery.SourceFileLoader("wharf_t", sys.argv[1] + "/wharf").load_module()
d = Path(sys.argv[1]).parent / "scratch-marker"
import tempfile; d = Path(tempfile.mkdtemp())
(d / "m.md").write_text("""# m
- **S1 — one** (x)
  > **Built 2026-10-17** on its branch
- **S3 — three** · status: not started
  D5 starts S3 and S4 once S1 is built
- **S4 — four** · not yet built
| S5 | the worktree built-ins |
1. **Built 2026-10-16** — the probes ran; **S6 — six**
""")
fake = types.SimpleNamespace(wt_of=lambda sid: None, repo=d, dry=False, checks={})
print(" ".join("%s=%s" % (a, w.Ship.done_when(fake, {"id": "x", "raw": {"done_when": {"marker": "m.md#" + a}}})[0]) for a in ("S1", "S3", "S4", "S5", "S6")))
PY
)" "S1=True S3=False S4=False S5=False S6=True" "the marker: Built under the anchor's own item only — never a mention, \"not yet built\" or \"built-ins\""
check "$(W python3 - "$HELMBIN" <<'PY'
import json, os, sys
sys.path.insert(0, sys.argv[1])
os.environ["STALLS_ORCA"] = "1"
import stalls
r = stalls.plan_runs()
print(sorted((k, v["id"]) for k, v in r.items() if v.get("wharf") == "gated"))
PY
)" "[('$(pj "p['blueprints']['gated']['orca_run']")', 'wp')]" "stalls reads a wharf ship's Run as the plan's (S6 for its workers), marked wharf's"
echo "  the tick: wharf apply --once per ship with a Run"
out=$(W "$WH" apply --once --all --dry-run); check "$?" "0" "apply --once --all: exit 0"
has "$out" "wharf apply --once: gated" "  a ship with rows to act on is said"
hasnt "$out" "wharf apply --once: three" "  a ship with nothing to do is quiet"
out=$(W "$WH" apply --once --all --dry-run); hasnt "$out" "wharf apply --once: gated" "  its refusals said once: quiet the next tick"
rm -f "$T/wplans/wp/wharf-gated.said"
out=$(W "$HM" tick --dry-run 2>&1); has "$out" "wharf apply --once: gated" "plan tick runs it, dry while the tick is not armed"
echo "  yard-smooth (2026-10-19): what needed the skipper by hand that day"
# Orca as it settles a worker: exit = its Dispatch failed, the Task back to ready (no report);
# report = a worker_done --outcome failed, the Task failed with the report as its result
settle_w() { python3 - "$WS/state.json" "$1" "$2" "${3:-}" <<'PY'
import json, sys
p, title, how, subject = sys.argv[1:]; st = json.load(open(p))
tid = [t["id"] for t in st["tasks"] if t["task_title"] == title][-1]
for w in st["workers"]:
    if w["taskId"] == tid:
        w.update(dispatchStatus="failed", projection={"outcome": "failed", "liveness": {"verdict": "exited"}})
for t in st["tasks"]:
    if t["id"] == tid:
        t["status"] = "ready" if how == "exit" else "failed"
        if how == "report":
            t["result"] = json.dumps({"provenance": "worker_report", "outcome": "failed", "subject": subject, "body": "b"})
json.dump(st, open(p, "w"))
PY
}
FA=$(mkbp fails '  - id: fx\n    provider: orca\n    agent: claude\n    retries: 1\n    done_when: {file: fx.txt}\n  - id: fr\n    provider: orca\n    agent: claude\n    retries: 1\n    done_when: {file: fr.txt}\n')
printf '%s\n' "$(brief fx "x" "fx.txt")" "$(brief fr "r" "fr.txt")" >> "$FA"
W "$WH" apply "$FA" --plan wp > /dev/null
ws() { grep -c "orchestration worker-start --task $(pj "p['tasks']['$1']['orca_task']")" "$WS/calls"; }
check "$(ws fx)/$(ws fr)" "1/1" "two builders started"
settle_w fx exit; settle_w fr report "Built and committed; suites killed for low memory"
out=$(W "$WH" apply "$FA" --plan wp)
check "$(ws fx)" "2" "a worker that ended with no report and no fx.txt: today's retry stands (retries 1)"
check "$(ws fr)" "1" "a reported failure with no fr.txt: not retried, as today"
has "$out" "orca  failed   fr" "  its failed row stands for the skipper"
settle_w fx exit; touch "$WR/.claude/worktrees/fx/fx.txt" "$WR/.claude/worktrees/fr/fr.txt"
out=$(W "$WH" apply "$FA" --plan wp)
check "$(ws fx)/$(ws fr)" "2/1" "done_when holding after a failed Dispatch: nothing started again"
has "$out" "orca  done     fx  built: file fx.txt holds — ended, not started again" "  the exited one ended at the retry's door"
has "$out" "plan  done     fr  file fr.txt holds; the worker reported failed: Built and committed; suites killed for low memory" "  the reported one ended by its done_when"
check "$(pst 'fx fr')" "fx=done fr=done" "  both done in the plan"
has "$(W "$HM" state wp | python3 -c "import json,sys; print([t['progress'] for t in json.load(sys.stdin)['tasks'] if t['id'] == 'fr'][0])")" "built; the worker reported failed: Built and committed; suites killed for low memory" "  the progress names the report's subject"
check "$(sq "sorted(t['status'] for t in st['tasks'] if t['task_title'] in ('fx', 'fr'))")" "['completed', 'completed']" "  and Orca's Tasks completed by the next pass"

echo "  a worker's question reaches the skipper once"
export ASK_QUEUE_DIR="$T/asks" ASK_MANAGER_DIR="$T/mgrdir"
sleep 300 & SKP=$!
printf '{"pid": %s, "sessionId": "skipper-0000-4000-8000-000000000000", "status": "idle"}' "$SKP" > "$T/sess/skipper.json"
QA=$(mkbp asks '  - id: qa\n    provider: orca\n    agent: claude\n')
skp() { python3 -c "import sys; p=sys.argv[1]; t=open(p).read(); open(p,'w').write(t.replace('\\nrepo:', '\\nskipper: %s\\nrepo:' % sys.argv[2], 1))" "$1" "$2"; }
skp "$QA" skipper-0000-4000-8000-000000000000
QB=$(mkbp asks2 '  - id: qb\n    provider: orca\n    agent: claude\n')
skp "$QB" gone-0000-4000-8000-000000000000
printf '%s\n' "$(brief qa "a" "a")" >> "$QA"; printf '%s\n' "$(brief qb "b" "b")" >> "$QB"
W "$WH" apply "$QA" --plan wp > /dev/null; W "$WH" apply "$QB" --plan wp > /dev/null
python3 - "$WS/state.json" "$(pj "p['tasks']['qa']['orca_dispatches'][0]")" "$(pj "p['blueprints']['asks']['orca_run']")" \
          "$(pj "p['tasks']['qb']['orca_dispatches'][0]")" "$(pj "p['blueprints']['asks2']['orca_run']")" <<'PY'
import json, sys
p, da, ra, db, rb = sys.argv[1:]; st = json.load(open(p))
st["messages"] = [{"id": "msg_qa1", "run_id": ra, "type": "question", "from_handle": "dispatch:" + da, "subject": "Question",
                   "body": "Restart the killed suites now?", "read": 0, "created_at": "2026-10-19T16:03:21Z"},
                  {"id": "msg_qb1", "run_id": rb, "type": "question", "from_handle": "dispatch:" + db, "subject": "Question",
                   "body": "Which branch?", "read": 0, "created_at": "2026-10-19T16:04:00Z"}]
json.dump(st, open(p, "w"))
PY
out=$(W "$WH" apply "$QA" --plan wp --once)
has "$out" "orca  relay    qa  question msg_qa1 → the skipper's next prompt" "a question in the Run: relayed to the live skipper"
QF="$T/asks/skipper-0000-4000-8000-000000000000.jsonl"
has "$(cat "$QF")" "ASK $WR asks/qa — Orca question msg_qa1 from dispatch" "  its line names the ship, the block and the message"
has "$(cat "$QF")" "Restart the killed suites now? — reply: orca orchestration reply --id msg_qa1" "  with the text and the reply verb"
W "$WH" apply "$QA" --plan wp --once > /dev/null
check "$(wc -l < "$QF" | tr -d ' ')" "1" "  a second pass: not relayed again"
out=$(W "$WH" apply "$QB" --plan wp --once)
has "$out" "question msg_qb1 → the board, as waiting" "a skipper not live here: the plan's waiting report instead"
check "$(pst qb)" "qb=waiting" "  the board shows it waiting"
# skipper-resilience S5: a `skipper: scope` ship's holder is its scope's skipper, which hears only
# Talk — its question goes by Talk on the skipper's page or to the board, never into a file queue
QC=$(mkbp asks3 '  - id: qc\n    provider: orca\n    agent: claude\n')
skp "$QC" scope
printf '%s\n' "$(brief qc "c" "c")" >> "$QC"
W "$WH" apply "$QC" --plan wp > /dev/null
python3 - "$WS/state.json" "$(pj "p['tasks']['qc']['orca_dispatches'][0]")" "$(pj "p['blueprints']['asks3']['orca_run']")" <<'PY'
import json, sys
p, dc, rc = sys.argv[1:]; st = json.load(open(p))
st["messages"].append({"id": "msg_qc1", "run_id": rc, "type": "question", "from_handle": "dispatch:" + dc, "subject": "Question",
                       "body": "Which scope?", "read": 0, "created_at": "2026-10-22T16:05:00Z"})
json.dump(st, open(p, "w"))
PY
python3 - "$T/wplans/wp/skipper.json" "$SKP" <<'PY'
import json, sys, time
json.dump({"holder": "skipper · tdock", "scope": "tdock", "host": "testhost", "account": None, "gen": 1, "since": time.time(),
           "until": time.time() + 900, "session": "skipper-0000-4000-8000-000000000000", "pid": int(sys.argv[2]), "why": "the suite"},
          open(sys.argv[1], "w"))
PY
mkdir -p "$T/mgrdir"
printf '{"session": "skipper-0000-4000-8000-000000000000", "name": "skipper · tdock", "scope": "tdock", "pid": %s, "space": null}' "$SKP" > "$T/mgrdir/testhost-tdock.json"
n0=$(wc -l < "$QF" | tr -d ' ')
out=$(W "$WH" apply "$QC" --plan wp --once)
has "$out" "question msg_qc1 → the board, as waiting" "a scope ship's question with no Talk to its skipper: the board, never the file road"
check "$(wc -l < "$QF" | tr -d ' ')" "$n0" "  nothing queued for a prompt the skipper never gets"
# the yard holds the ship while the scope's skipper lives (the fifth finish review): `who` is None,
# and the file road would still reach that skipper through the relay's own fallback
python3 - "$WS/state.json" "$(pj "p['tasks']['qc']['orca_dispatches'][0]")" "$(pj "p['blueprints']['asks3']['orca_run']")" "$T/wplans/wp/skipper.json" <<'PY'
import json, sys, time
p, dc, rc, sk = sys.argv[1:]; st = json.load(open(p))
st["messages"].append({"id": "msg_qc2", "run_id": rc, "type": "question", "from_handle": "dispatch:" + dc, "subject": "Question",
                       "body": "Which yard?", "read": 0, "created_at": "2026-10-22T16:06:00Z"})
json.dump(st, open(p, "w"))
rec = json.load(open(sk)); rec.update(holder="yard", session=None, pid=None, gen=rec["gen"] + 1)
json.dump(rec, open(sk, "w"))
PY
out=$(W "$WH" apply "$QC" --plan wp --once)
has "$out" "question msg_qc2 → the board, as waiting" "  a yard-held scope ship's question with a live skipper: the board, never the file road"
check "$(wc -l < "$QF" | tr -d ' ')" "$n0" "  still nothing queued"
rm -f "$T/wplans/wp/skipper.json" "$T/mgrdir/testhost-tdock.json"
echo "  S6: a scope ship's question is hailed to the skipper holding its lease, a pointer on its page, never the file road"
cat > "$WS/hail" <<'SH'
#!/bin/sh
# hail REF --kind ask --when idle --no-file --text T --json: records its argv and the page it was handed
printf '%s\n' "$*" >> "$HAIL_CALLS"; printf 'HAIL_SPACE=%s\n' "${HAIL_SPACE:-}" >> "$HAIL_CALLS"
printf '{"road": "%s", "verdict": "%s", "target": "%s"}\n' "${STUB_HAIL_ROAD:-talk}" "${STUB_HAIL_VERDICT:-queued}" "$1"
SH
chmod +x "$WS/hail"; : > "$T/hail.calls"
# qadd <ship> <block> <message id> <body>: a worker's unread question in that ship's Run
qadd() { python3 - "$WS/state.json" "$(pj "p['tasks']['$2']['orca_dispatches'][0]")" "$(pj "p['blueprints']['$1']['orca_run']")" "$3" "$4" <<'PY'
import json, sys
p, d, r, mid, body = sys.argv[1:]; st = json.load(open(p))
st["messages"].append({"id": mid, "run_id": r, "type": "question", "from_handle": "dispatch:" + d, "subject": "Question",
                       "body": body, "read": 0, "created_at": "2026-10-22T16:07:00Z"})
json.dump(st, open(p, "w"))
PY
}
# lease <holder>: the plan's lease held by the scope's skipper (its session and pid) or by the yard
lease() { python3 - "$T/wplans/wp/skipper.json" "$SKP" "$1" <<'PY'
import json, sys, time
sk = sys.argv[3] == "skipper"
json.dump({"holder": "skipper · tdock" if sk else "yard", "scope": "tdock", "host": "testhost", "account": None, "gen": 3 if sk else 4,
           "since": time.time(), "until": time.time() + 900 if sk else None,
           "session": "skipper-0000-4000-8000-000000000000" if sk else None, "pid": int(sys.argv[2]) if sk else None, "why": "the suite"},
          open(sys.argv[1], "w"))
PY
}
lease skipper
printf '{"session": "skipper-0000-4000-8000-000000000000", "name": "skipper · tdock", "scope": "tdock", "pid": %s, "space": "sp-tdock"}' "$SKP" > "$T/mgrdir/testhost-tdock.json"
HW() { W env WHARF_HAIL="$WS/hail" HAIL_CALLS="$T/hail.calls" HAIL_SPACE=sp-stray "$WH" apply "$@"; }
n0=$(wc -l < "$QF" | tr -d ' ')
qadd asks3 qc msg_qc3 "Delete the old branch?"
out=$(HW "$QC" --plan wp --once)
has "$out" "question msg_qc3 → hailed to skipper · tdock (queued via talk)" "the lease holder's skipper: the question is hailed to its session"
has "$(cat "$T/hail.calls")" "skipper-0000-4000-8000-000000000000 --kind ask --when idle --no-file --text Orca question msg_qc3 from asks3/qc in plan wp (dispatch " \
  "  hail <its session> --kind ask --when idle --no-file, naming the question, the ship and block, the plan"
has "$(cat "$T/hail.calls")" " — reply: orca orchestration reply --id msg_qc3 " "  with the reply verb"
has "$(cat "$T/hail.calls")" "HAIL_SPACE=sp-tdock" "  on its record's page, never the caller's HAIL_SPACE"
hasnt "$(cat "$T/hail.calls")" "Delete the old branch" "  the worker's words stay in Orca: a pointer, not the question"
check "$(python3 -c 'import sys; l = open(sys.argv[1]).readline(); print(len(l.split(" --text ", 1)[1].rsplit(" --json", 1)[0]) <= 400)' "$T/hail.calls")" "True" "  under hail's 400 characters"
check "$(wc -l < "$QF" | tr -d ' ')" "$n0" "  no file line"
HW "$QC" --plan wp --once > /dev/null; check "$(grep -c -- '--text' "$T/hail.calls")" "1" "  a second pass: not hailed again"
qadd asks3 qc msg_qc4 "Which suite?"
out=$(STUB_HAIL_VERDICT=unreachable HW "$QC" --plan wp --once)
has "$out" "question msg_qc4 → the board, as waiting (the hail to skipper · tdock was not taken: unreachable via talk)" "a hail no road took: the board, never the file road"
check "$(wc -l < "$QF" | tr -d ' ')" "$n0" "  still no file line"
qadd asks3 qc msg_qc6 "Still there?"
out=$(STUB_HAIL_ROAD=subs HW "$QC" --plan wp --once)
has "$out" "question msg_qc6 → hailed to skipper · tdock (queued via subs)" "a hail that became a --when idle subscription: hailed"
has "$(W "$HM" state wp | python3 -c "import json,sys; print([t['progress'] for t in json.load(sys.stdin)['tasks'] if t['id'] == 'qc'][0])")" \
  "Orca question msg_qc6: hailed once skipper · tdock is idle" "  and carded, so a row the fulfil drops never loses it"
lease yard; qadd asks3 qc msg_qc5 "And then?"
out=$(HW "$QC" --plan wp --once)
check "$(grep -c -- '--text' "$T/hail.calls")" "3" "the yard holds the ship, its skipper live: no hail"
has "$out" "question msg_qc5 → the board, as waiting (no live skipper holds the ship's lease)" "  the board"
qadd asks qa msg_qa2 "Which branch now?"
out=$(HW "$QA" --plan wp --once)
check "$(grep -c -- '--text' "$T/hail.calls")" "3" "a ship with a named skipper: no hail"
has "$out" "question msg_qa2 → the skipper's next prompt" "  its file relay, as before"
rm -f "$T/wplans/wp/skipper.json" "$T/mgrdir/testhost-tdock.json"; unset -f qadd lease HW
kill $SKP 2>/dev/null; unset ASK_QUEUE_DIR ASK_MANAGER_DIR

echo "  the Yard rules ride in the spec, never in the digest"
mkdir -p "$T/pin"; printf -- '---\nship: pin\nrepo: shop\ncreated: 2026-10-19\nblocks:\n  - id: pin\n    provider: orca\n    agent: claude\n---\n## pin\nTask: t\nTier: worker\nWhy: w\nStart here: s\nDone means: d\nNot this: n\n' > "$T/pin/2026-10-19-pin.md"
check "$(W "$WH" check "$T/pin/2026-10-19-pin.md" --json | python3 -c "import json,sys; print(json.load(sys.stdin)['digest'])")" \
  "e98fda3439561d4537e1a3be298652f693f7f0ff672c7a88a9a8f9f06d327c4d" "the digest of an unchanged file is the one main's blueprintlib gave it"
check "$(python3 - "$B" "$T/pin/2026-10-19-pin.md" <<'PY'
import sys; sys.path.insert(0, sys.argv[1]); sys.path.insert(0, sys.argv[1] + "/../lib")
import core_path; core_path.require()
import blueprintlib as b
bp = b.load(sys.argv[2]); st = bp["by_id"]["pin"]
task = lambda spec: {"tasks": [{"id": "t1", "task_title": "pin", "status": "dispatched", "deps": "[]", "spec": spec}],
                     "gates": [], "workers": [], "run": {}}
rows = lambda spec: [r[0] for r in b.diff(bp, "testhost", {"pin": {"orca_task": "t1"}}, task(spec))["orca"]]
print(b.spec_of(bp, st).endswith(b.yard_rules()), rows(b.spec_of(bp, st)), rows(b.spec_of(bp, st, rules=False)), rows("another brief"),
      rows(st["section"] + "\n\n" + b.YARD_RULES_PAST[0]), "bin/check <worktree>" in b.spec_of(bp, st))
PY
)" "True ['ok'] ['ok'] ['changed', 'ok'] ['ok'] True" "  the spec ends in the rules, bin/check's among them; a Task made before them, or under their earlier text, is not drift; another brief is"

echo "  wharf apply --watch --launch: the launches started, capped, and reported launched"
mkdir -p "$WS/bin"
printf '#!/bin/sh\n# gh pr view <branch> --json state,number: merged when STUB_GH_MERGED names the branch\ncase " $STUB_GH_MERGED " in *" $3 "*) echo "{\\"state\\": \\"MERGED\\", \\"number\\": 41}";; *) echo "{\\"state\\": \\"OPEN\\", \\"number\\": 40}";; esac\n' > "$WS/bin/gh"
cat > "$WS/afrun" <<'SH'
#!/bin/sh
# autofinish-run <wt> [--session S]: a launch started — its state as the real one writes it, not ended
echo "$*" >> "$AFRUN_CALLS"
gd=$(git -C "$1" rev-parse --absolute-git-dir); mkdir -p "$gd/claude"
printf '{"started": "%s", "session": "launch-%s", "tip": "%s", "by": "sweep"}' "$(date +%Y-%m-%dT%H:%M:%S%z | sed 's/\(..\)$/:\1/')" "$$" "$(git -C "$1" rev-parse HEAD)" > "$gd/claude/autofinish.json"
SH
chmod +x "$WS/bin/gh" "$WS/afrun"
LB=$(mkbp launch '  - id: lb1\n    provider: orca\n    agent: claude\n    done_when: {file: l1.txt}\n  - id: lb2\n    provider: orca\n    agent: claude\n    done_when: {file: l2.txt}\n  - id: launch-lb1\n    depends_on: [lb1]\n    provider: shell\n    command: "echo the skipper launches <wt>"\n    launch: finish\n    branch: claude/testhost/2026-10-17-lb1\n    done_when: {pr_merged: true}\n  - id: launch-lb2\n    depends_on: [lb2]\n    provider: shell\n    command: "echo the skipper launches <wt>"\n    launch: finish\n    branch: claude/testhost/2026-10-17-lb2\n    done_when: {pr_merged: true}\n')
printf '%s\n' "$(brief lb1 "1" "l1.txt")" "$(brief lb2 "2" "l2.txt")" >> "$LB"
printf '#!/bin/sh\necho "${STUB_BUSY:-0}"\n' > "$WS/drc"; chmod +x "$WS/drc"   # dispatch-rc live --no-reap: the runs busy
L() { W env -u PLAN_NO_GH PATH="$WS/bin:$PATH" WHARF_AUTOFINISH_RUN="$WS/afrun" AFRUN_CALLS="$WS/afrun.calls" WHARF_DISPATCH_RC="$WS/drc" DISPATCH_MAX_RUNS=3 "$@"; }
out=$(L env CLAUDE_UNATTENDED=dispatch "$WH" apply --watch --launch "$LB" --plan wp 2>&1); check "$?" "1" "--watch refuses under CLAUDE_UNATTENDED, as a start does"
has "$out" "attended only" "  saying so"
L "$WH" check "$LB" > /dev/null; check "$?" "0" "  the launch ship is a valid blueprint"
# --landings, the flag's old name, read until rename S8: a --watch started before S5 passes it to each pass
out=$(L env WHARF_WATCH_PASSES=1 "$WH" apply --watch --launch --landings 1 --every 0 "$LB" --plan wp); check "$?" "0" "--watch --launch: one pass, exit 0 (the old --landings flag, launch's alias)"
has "$out" "pass 1, 2026-10-17-launch.md" "  the pass said, stamped"
has "$out" "started dispatch" "  the builders started by the fresh apply"
python3 - "$WS/state.json" <<'PY'
import json, sys
p = sys.argv[1]; st = json.load(open(p))
for t in st["tasks"]:
    if t["task_title"] in ("lb1", "lb2"):
        t["status"] = "completed"
    elif t["task_title"] in ("launch-lb1", "launch-lb2"):
        t["status"] = "ready"   # Orca makes a Task ready once its deps complete
for w in st["workers"]:
    w.update(dispatchStatus="completed", projection={"outcome": "succeeded", "liveness": {"verdict": "exited"}})
json.dump(st, open(p, "w"))
PY
touch "$WR/.claude/worktrees/lb1/l1.txt" "$WR/.claude/worktrees/lb2/l2.txt"
out=$(L env WHARF_WATCH_PASSES=1 CLAUDE_CODE_SESSION_ID=skipper-1 "$WH" apply --watch --launch --launches 1 --every 0 "$LB" --plan wp)
check "$(wc -l < "$WS/afrun.calls" | tr -d ' ')" "1" "both builders done: one launch started"
has "$(cat "$WS/afrun.calls")" "$WR/.claude/worktrees/lb1 --session skipper-1" "  autofinish-run on the predecessor's worktree, with the skipper's session"
has "$out" "raised: 1 launch under way (--launches 1): it waits" "  the second held past --launches 1"
check "$(pst 'launch-lb1 launch-lb2')" "launch-lb1=running launch-lb2=planned" "  the plan: one launch running"
out=$(L env WHARF_WATCH_PASSES=1 STUB_GH_MERGED=claude/testhost/2026-10-17-lb1 "$WH" apply --watch --launch --launches 1 --every 0 "$LB" --plan wp)
has "$out" "launched: claude/testhost/2026-10-17-lb1 merged (#41)" "its PR merged: the launch reported launched by wharf itself"
check "$(pst launch-lb1)" "launch-lb1=launched" "  launched in the plan (rename S5: the writer's new word)"
check "$(wc -l < "$WS/afrun.calls" | tr -d ' ')" "1" "  the second still held: the first launch's state has not ended"
G1=$(git -C "$WR/.claude/worktrees/lb1" rev-parse --absolute-git-dir)
python3 -c "import json; p='$G1/claude/autofinish.json'; d=json.load(open(p)); d.update(ended='x', outcome='launched', pr=41); json.dump(d, open(p, 'w'))"
G2=$(git -C "$WR/.claude/worktrees/lb2" rev-parse --absolute-git-dir); mkdir -p "$G2/claude"
printf '{"session": "busy-0000-4000-8000-000000000000", "branch": "claude/testhost/2026-10-17-lb2", "seen": %s}' "$(date +%s)" > "$G2/claude/owner.json"
sleep 300 & BSY=$!; printf '{"pid": %s, "sessionId": "busy-0000-4000-8000-000000000000", "status": "shell"}' "$BSY" > "$T/sess/busy.json"
out=$(L env WHARF_WATCH_PASSES=1 STUB_GH_MERGED=claude/testhost/2026-10-17-lb1 "$WH" apply --watch --launch --launches 1 --every 0 "$LB" --plan wp)
has "$out" "raised: waits for its lock (session busy-000 holds it, live, not handed over)" "a lock a live session holds and never handed over: the launch waits"
python3 -c "import json, time; p='$G2/claude/owner.json'; d=json.load(open(p)); d['handover']=time.time(); json.dump(d, open(p, 'w'))"
printf '{"pid": %s, "sessionId": "busy-0000-4000-8000-000000000000", "status": "busy"}' "$BSY" > "$T/sess/busy.json"
out=$(L env WHARF_WATCH_PASSES=1 STUB_GH_MERGED=claude/testhost/2026-10-17-lb1 "$WH" apply --watch --launch --launches 1 --every 0 "$LB" --plan wp)
has "$out" "raised: waits for its lock (session busy-000 handed it over, still busy)" "  handed over but busy (its last turn): the launch still waits"
printf '{"pid": %s, "sessionId": "busy-0000-4000-8000-000000000000", "status": "shell"}' "$BSY" > "$T/sess/busy.json"
out=$(L env WHARF_WATCH_PASSES=1 STUB_GH_MERGED=claude/testhost/2026-10-17-lb1 "$WH" apply --watch --launch --launches 1 --every 0 "$LB" --plan wp)
check "$(wc -l < "$WS/afrun.calls" | tr -d ' ')" "2" "  handed over and shell: the second launch starts, the first ended"
kill $BSY 2>/dev/null
python3 -c "import json; p='$G2/claude/autofinish.json'; d=json.load(open(p)); d.update(ended='x', outcome='stopped', gate='G4'); json.dump(d, open(p, 'w'))"
out=$(L env WHARF_WATCH_PASSES=1 STUB_GH_MERGED=claude/testhost/2026-10-17-lb1 "$WH" apply --watch --launch --launches 1 --every 0 "$LB" --plan wp)
has "$out" "raised: launch stopped: stopped at gate G4 on" "a launch that stopped: raised with its gate"
check "$(pst launch-lb2)" "launch-lb2=waiting" "  the plan says waiting"
out=$(L env WHARF_WATCH_PASSES=1 STUB_GH_MERGED=claude/testhost/2026-10-17-lb1 "$WH" apply --watch --launch --launches 1 --every 0 "$LB" --plan wp)
check "$(wc -l < "$WS/afrun.calls" | tr -d ' ')" "2" "  and never started again on that tip"
python3 -c "import json; p='$G2/claude/autofinish.json'; d=json.load(open(p)); d.update(ended='x', outcome='never-started', gate='refused'); json.dump(d, open(p, 'w'))"
out=$(L env WHARF_WATCH_PASSES=1 STUB_BUSY=3 STUB_GH_MERGED=claude/testhost/2026-10-17-lb1 "$WH" apply --watch --launch --every 0 "$LB" --plan wp)
has "$out" "raised: queued — its last start was refused by the run cap; 3 runs busy, dispatch's cap is 3" "a launch the run cap refused (never-started at gate refused): queued, not stopped"
check "$(wc -l < "$WS/afrun.calls" | tr -d ' ')" "2" "  not started while dispatch's runs are all busy"
out=$(L env WHARF_WATCH_PASSES=1 STUB_BUSY=1 STUB_GH_MERGED=claude/testhost/2026-10-17-lb1 "$WH" apply --watch --launch --every 0 "$LB" --plan wp)
check "$(wc -l < "$WS/afrun.calls" | tr -d ' ')" "3" "  started again once a run ended (the skipper's addition, 2026-10-19)"
out=$(L env WHARF_WATCH_PASSES=5 STUB_GH_MERGED="claude/testhost/2026-10-17-lb1 claude/testhost/2026-10-17-lb2" "$WH" apply --watch --launch --every 0 "$LB" --plan wp)
check "$?" "0" "both merged: exit 0"
has "$out" "every ship ended (2026-10-17-launch.md)" "  the watch ends once every ship named has ended"
check "$(pst 'launch-lb1 launch-lb2')" "launch-lb1=launched launch-lb2=launched" "  both launched"

echo "  the yard's start fixes (skipper-resilience S1, 2026-10-22): the trust step, the worktree Orca does not know yet, the brake, --orphans"
# trust-projects, as a stub: records the config dir it ran for and, unless STUB_TRUST=no, writes what the
# dialog would into that dir's .claude.json (the default login's is $HOME/.claude.json)
cat > "$WS/trust" <<'PY'
#!/usr/bin/env python3
import json, os
d = os.environ.get("CLAUDE_CONFIG_DIR")
open(os.environ["STUB_TRUST_CALLS"], "a").write("%s\n" % (d or "default"))
if os.environ.get("STUB_TRUST") != "no":
    f = os.path.join(d, ".claude.json") if d else os.path.join(os.environ["HOME"], ".claude.json")
    j = json.load(open(f)); j.setdefault("projects", {})[os.environ["STUB_TRUST_REPO"]] = {"hasTrustDialogAccepted": True}
    json.dump(j, open(f, "w"))
PY
chmod +x "$WS/trust"
TC="$WS/trust.calls"; : > "$TC"
WT() { W env WHARF_TRUST="$WS/trust" STUB_TRUST_CALLS="$TC" STUB_TRUST_REPO="$WR" "$@"; }
oneblock() { mkbp "$1" "  - id: $2\n    provider: orca\n    agent: claude\n"  > /dev/null; printf '%s\n' "$(brief "$2" "t" "t")" >> "$WR/docs/blueprints/2026-10-17-$1.md"; echo "$WR/docs/blueprints/2026-10-17-$1.md"; }
wstarts() { grep -c "^orchestration worker-start" "$WS/calls"; }
# the ship compiled with nothing started (the brake file holds the start), so the next --once is exactly one pass
compiled() { touch "$HOME/.studio-brake"; WT "$WH" apply "$1" --plan wp > /dev/null; rm -f "$HOME/.studio-brake"; }
ledger() { pj "[e['state'] for e in p['blueprints']['$1']['ledger'] if e['op'] == 'worker-start']"; }
echo '{"projects": {}}' > "$HOME/.claude.json"
S1A=$(oneblock s1a sa); before=$(wstarts)
out=$(WT "$WH" apply "$S1A" --plan wp); check "$?" "0" "an untrusted repo: apply exit 0"
check "$(cat "$TC")/$(( $(wstarts) - before ))" "default/1" "  trust-projects ran once, for the default login's dir, then the start went ahead"
has "$out" "started dispatch ctx_" "  started"
S1B=$(oneblock s1b sb)
WT "$WH" apply "$S1B" --plan wp > /dev/null
check "$(wc -l < "$TC" | tr -d ' ')" "1" "  a trusted repo: not run again"
rm -f "$HOME/.claude.json"; : > "$TC"
S1C=$(oneblock s1c sc); before=$(wstarts)
WT "$WH" apply "$S1C" --plan wp > /dev/null
check "$(wc -l < "$TC" | tr -d ' ')/$(( $(wstarts) - before ))" "0/1" "  no .claude.json to read: the dialog cannot be told, dispatch-rc's own answer is trusted, no trust step"
echo '{"projects": {}}' > "$HOME/.claude.json"
S1D=$(oneblock s1d sd); compiled "$S1D"; : > "$TC"; before=$(wstarts)
out=$(WT env STUB_TRUST=no "$WH" apply "$S1D" --plan wp --once); check "$?" "0" "still untrusted after trust-projects: exit 0"
has "$out" "not started: untrusted after trust-projects (the default login)" "  not started, saying why"
check "$(wc -l < "$TC" | tr -d ' ')/$(( $(wstarts) - before ))/$(ledger s1d)" "1/0/['failed']" "  it counted one failed start, and Orca was not called"
out=$(WT "$WH" apply "$S1D" --plan wp --once)
check "$(( $(wstarts) - before ))/$(ledger s1d)" "1/['failed', 'done']" "  the next pass, trusted this time, starts it"
mkdir -p "$T/acctdir"; echo '{"projects": {}}' > "$T/acctdir/.claude.json"
S1E=$(oneblock s1e se); : > "$TC"
WT env STUB_ACCT_DIR="$T/acctdir" "$WH" apply "$S1E" --plan wp > /dev/null
check "$(cat "$TC")" "$T/acctdir" "a picked login with its own config dir: trusted there (trust is per config dir), not in the default's"
check "$(python3 -c "import json; print(json.load(open('$T/acctdir/.claude.json'))['projects'].get('$WR', {}).get('hasTrustDialogAccepted'))")" "True" "  read back from that dir"

echo "  a worktree Orca does not list yet: deferred one pass, never counted"
S1F=$(oneblock s1f sf); compiled "$S1F"; before=$(wstarts)
out=$(WT env STUB_WT_LIST=/elsewhere "$WH" apply "$S1F" --plan wp --once)
has "$out" "not started: worktree not yet known to Orca (retried next pass)" "the first pass: said, and nothing started"
check "$(( $(wstarts) - before ))/$(ledger s1f)/$(pj "p['tasks']['sf'].get('wt_deferred') is not None")" "0/[]/True" "  no ledger line, so spent() counts nothing"
out=$(WT env STUB_WT_LIST=/elsewhere "$WH" apply "$S1F" --plan wp --once)
check "$(( $(wstarts) - before ))/$(ledger s1f)" "1/['done']" "  the second pass starts it anyway (a registry that never lists it must not hold a block for ever)"
S1G=$(oneblock s1g sg); before=$(wstarts)
out=$(WT env STUB_WT_LIST="/elsewhere:$(cd "$WR" && pwd -P)/.claude/worktrees/sg" "$WH" apply "$S1G" --plan wp)
check "$(( $(wstarts) - before ))/$(pj "p['tasks']['sg'].get('wt_deferred')")" "1/None" "a worktree Orca lists: started at once, nothing deferred"
S1K=$(oneblock s1k sk); compiled "$S1K"; before=$(wstarts)
WT env STUB_WT_LIST=/elsewhere "$WH" apply "$S1K" --plan wp --once > /dev/null
out=$(WT env STUB_WT_LIST="/elsewhere:$(cd "$WR" && pwd -P)/.claude/worktrees/sk" "$WH" apply "$S1K" --plan wp --once)
check "$(( $(wstarts) - before ))/$(pj "p['tasks']['sk'].get('wt_deferred')")" "1/None" "deferred, then listed: started, and the flag is gone from the plan (a later worktree waits again)"
S1H=$(oneblock s1h sh); before=$(wstarts)
out=$(WT "$WH" apply "$S1H" --plan wp)
check "$(( $(wstarts) - before ))" "1" "a list Orca does not answer: never holds a start back"

echo "  the studio brake: ~/.studio-brake, and a launchd job's stopped process"
S1I=$(oneblock s1i si); before=$(wstarts); touch "$HOME/.studio-brake"
out=$(WT "$WH" apply "$S1I" --plan wp)
has "$out" "braked: a start waits for the studio brake" "~/.studio-brake: a start waits, said"
check "$(( $(wstarts) - before ))/$(ledger s1i)" "0/[]" "  nothing started, nothing counted"
rm -f "$HOME/.studio-brake"
sleep 300 & BKP=$!
printf '#!/bin/sh\nif [ "$1 $2" = "list org.test.brake" ]; then printf "{\\n\\t\\"Label\\" = \\"org.test.brake\\";\\n\\t\\"PID\\" = %%s;\\n};\\n" "$(cat "%s")"; fi\n' "$WS/brake.pid" > "$WS/launchctl"
chmod +x "$WS/launchctl"; echo $BKP > "$WS/brake.pid"
mkdir -p "$T/config/wharf-runs"; echo org.test.brake > "$T/config/wharf-runs/brake-label"
out=$(WT env WHARF_LAUNCHCTL="$WS/launchctl" "$WH" apply "$S1I" --plan wp --once)
check "$(( $(wstarts) - before ))" "1" "brake-label set, its job running: not braked"
kill -STOP $BKP; sleep 0.3
S1J=$(oneblock s1j sj); before=$(wstarts)
out=$(WT env WHARF_LAUNCHCTL="$WS/launchctl" "$WH" apply "$S1J" --plan wp)
has "$out" "braked: a start waits for the studio brake" "the job's process stopped (SIGSTOP): a start waits"
check "$(( $(wstarts) - before ))/$(ledger s1j)" "0/[]" "  and counts nothing"
kill -CONT $BKP; sleep 0.3
out=$(WT env WHARF_LAUNCHCTL="$WS/launchctl" "$WH" apply "$S1J" --plan wp --once)
check "$(( $(wstarts) - before ))" "1" "  released: it starts"
rm -f "$T/config/wharf-runs/brake-label"; kill $BKP 2>/dev/null

echo "  wharf status --orphans: Orca's repos and Runs no plan here accounts for"
python3 - "$WS/state.json" "$T/gone-scratch" "$T/pin" <<'PY'
import json, sys
p, gone, there = sys.argv[1:]; st = json.load(open(p))
st["repos"] += [{"id": "repo_x1", "path": gone, "displayName": "gone-scratch"}, {"id": "repo_x2", "path": there, "displayName": "pin-scratch"}]
st["runs"]["run_scratch1"] = {"id": "run_scratch1", "objective": "yard-probe scratch ship", "coordinator_handle": "term_x", "created_at": "2026-10-21T09:00:00Z"}
json.dump(st, open(p, "w"))
PY
out=$(W "$WH" status --orphans); check "$?" "0" "exit 0, no ship needed"
has "$out" "run  run_scratch1 — yard-probe scratch ship" "a Run no plan records: listed"
has "$out" "repo gone-scratch — $T/gone-scratch (its folder is gone)" "a repo whose folder is gone: listed"
has "$out" "repo pin-scratch — $T/pin (no plan and not a registry repo)" "a repo no plan or registry names: listed"
hasnt "$out" "$(pj "p['blueprints']['three']['orca_run']") " "a ship's own Run: not listed"
hasnt "$out" "— $WR (" "a plan's repo: not listed"
check "$(W "$WH" status --orphans --json | python3 -c "import json,sys; d=json.load(sys.stdin); print(sorted(r['run'] for r in d['runs']), [r['repo'] for r in d['repos']])")" \
  "['run_scratch1'] ['gone-scratch', 'pin-scratch']" "--json: the same rows"
echo "  wharf apply --yard (skipper-resilience S2): the pin, where it is laid, the fence, the merge as data"
# Its own registry (a scope with a yard, one with yard null, a repo in none) and plan store; the ssh stub
# records its argv and runs the command here as the yard (HARNESS_HOST yardhost), with none of the
# caller's session environment, as ssh carries none. The origin is a bare repo in the scratch dir.
YD="$T/yard"; mkdir -p "$YD"; YREG="$YD/repos.json"
cat > "$YREG" <<'JSON'
{"repos": {"yardrepo": {"hosts": ["testhost", "yardhost", "farhost"]}, "nullrepo": {"hosts": ["testhost", "farhost"]}, "loose": {}},
 "scopes": {"dock": {"file": "d", "repos": ["yardrepo"], "yard": "yardhost"}, "nul": {"file": "n", "repos": ["nullrepo"], "yard": null}}}
JSON
cat > "$YD/ssh" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >> "$YSSH_CALLS"
while [ $# -gt 0 ]; do case "$1" in -o) shift 2;; -*) shift;; *) break;; esac; done
shift   # the alias
# YARD_HOME: a yard login whose home folder is not the caller's
exec env -u CLAUDE_CODE_SESSION_ID -u CLAUDE_UNATTENDED -u DISPATCH_DEPTH ${YARD_HOME:+HOME=$YARD_HOME} HARNESS_HOST=yardhost PLAN_HOST=yardhost sh -c "$*"
SH
chmod +x "$YD/ssh"; : > "$YD/ssh.calls"
mkdir -p "$T/config/wharf-runs"; echo "yardhost:yard-alias" > "$T/config/wharf-runs/ssh"
Y() { W env PLANS_DIR="$YD/plans" CLAUDE_REPOS_JSON="$YREG" WHARF_SSH="$YD/ssh" YSSH_CALLS="$YD/ssh.calls" YOUT="$YD/yout" "$@"; }
YH() { Y env HARNESS_HOST=yardhost PLAN_HOST=yardhost "$@"; }   # this Mac is the yard
yp() { python3 -c "import json; p=json.load(open('$YD/plans/$1/plan.json')); print($2)"; }
gt() { git -C "$1" -c user.name=t -c user.email=t@t "${@:2}"; }
git init -q --bare -b main "$YD/origin.git"
YR="$HOME/projects/yardrepo"; git clone -q "$YD/origin.git" "$YR" 2>/dev/null
printf '# yardrepo\n\n- physical: none\n' > "$YR/AGENTS.md"; gt "$YR" add -A; gt "$YR" commit -qm init; gt "$YR" push -q origin main 2>/dev/null
YBR=claude/testhost/2026-10-22-yb; YW="$YR/.claude/worktrees/yb"
gt "$YR" worktree add -q "$YW" -b "$YBR"; mkdir -p "$YW/docs/blueprints"
# ybp <ship> <repo> <front matter lines> <blocks>: the last two as printf formats, \n for a newline (mkbp's way)
ybp() { { printf -- '---\nship: %s\nrepo: %s\ncreated: 2026-10-22\n%bblocks:\n' "$1" "$2" "$3"; printf "$4"; printf -- '---\n'; } > "$YW/docs/blueprints/2026-10-22-$1.md"
        echo "$YW/docs/blueprints/2026-10-22-$1.md"; }
shellblock() { printf '%s' '  - id: '"$1"'\n    provider: shell\n    command: "echo '"$1"' >> \\"$YOUT\\""\n'; }
# a decision on a doc that is not there: its gate never opens, so the ship stays un-ended and holds its pin
gateblock() { printf '%s' '  - id: '"$1"'\n    kind: decision\n    doc: docs/none.md\n    items: [D1]\n    depends_on: ['"$2"']\n'; }
pushed() { gt "$YW" add -A; gt "$YW" commit -qm "$1" > /dev/null; gt "$YW" push -q -u origin "$YBR" 2>/dev/null; }
Y1=$(ybp yone yardrepo '' "$(shellblock y1)$(gateblock yg y1)"); Y2=$(ybp ytwo yardrepo '' "$(shellblock y2)")
Y3=$(ybp ythree yardrepo '' "$(shellblock y3)"); Y5=$(ybp yfive yardrepo '' "$(shellblock y5)")
Y6=$(ybp ysix yardrepo '' "$(shellblock y6)"); Y7=$(ybp yseven yardrepo 'merge: no\nsent_by: sender-1\nskipper: scope\n' "$(shellblock y7)")
YL=$(ybp yloose loose '' "$(shellblock yl)"); YN=$(ybp ynull nullrepo '' "$(shellblock yn)")
# its block prints the layer the yard restored from --laid-by (ssh carries no environment)
Y8=$(ybp yeight yardrepo '' '  - id: y8\n    provider: shell\n    command: "echo y8-${CLAUDE_UNATTENDED:-none}-${DISPATCH_DEPTH:-unset} >> \\"$YOUT\\""\n')
Y9=$(ybp ynine yardrepo '' "$(shellblock y9)")
pushed blueprints
check "$(grep -c '^    command: "echo y1 >> \\"$YOUT\\""$' "$Y1")" "1" "(the fixture: a shell block's command quoted as the suite's others)"

out=$(Y "$WH" apply --yard "$Y1" --plan yp1 2>&1); check "$?" "0" "off the yard: --yard exit 0"
has "$(cat "$YD/ssh.calls")" "-o BatchMode=yes -o ConnectTimeout=10 yard-alias sh -s -- --pinned " "  re-run over the yard's alias (wharf-runs/ssh)"
has "$(cat "$YD/ssh.calls")" " --laid-by " "  with --laid-by"
has "$(cat "$YD/ssh.calls")" " --plan yp1" "  and the plan"
has "$out" "wharf apply --yard: yardrepo $YBR:docs/blueprints/2026-10-22-yone.md pinned at " "  the caller says the pin"
has "$out" "into plan yp1 on yardhost (merge yes: default)" "  the yard compiled it, its output relayed"
check "$(yp yp1 "sorted(p['blueprints']['yone']['pin'].items())[:3]")" "[('branch', '$YBR'), ('digest', '$(yp yp1 "p['blueprints']['yone']['digest']")'), ('rel', 'docs/blueprints/2026-10-22-yone.md')]" \
  "  plan.json: the pin {repo, branch, rel, digest}, its digest the accepted one"
check "$(yp yp1 "p['blueprints']['yone']['pin']['repo'], p['blueprints']['yone']['file'] == '$(cd "$YD/plans/yp1" && pwd -P)/blueprint-yone.md'")" "yardrepo True" \
  "  the record's file is the plan's copy, plans/<id>/blueprint-<ship>.md"
check "$(cmp -s "$YD/plans/yp1/blueprint-yone.md" "$Y1" && echo same)" "same" "  the copy is origin's text"
check "$(yp yp1 "p['blueprints']['yone']['main'] == '$YR', p['blueprints']['yone']['rel']")" "True docs/blueprints/2026-10-22-yone.md" "  main and rel from the pin (accept)"
check "$(yp yp1 "[p['blueprints']['yone']['laid_by'][k] for k in ('mode', 'depth', 'session', 'host')]")" "['attended', 0, 'mgr-1', 'testhost']" \
  "  laid_by computed on the caller: attended, depth 0, its session, its host"
check "$(yp yp1 "p['blueprints']['yone']['merge']")" "{'value': 'yes', 'why': 'default'}" "  merge: yes by default, recorded with why"
check "$(cat "$YD/yout")" "y1" "  and the first apply ran its block there"

: > "$YD/ssh.calls"
out=$(YH "$WH" apply --yard "$Y2" --plan yp2 2>&1); check "$?" "0" "on the yard: --yard exit 0"
check "$(wc -c < "$YD/ssh.calls" | tr -d ' ')" "0" "  compiled here, no ssh"
check "$(yp yp2 "p['blueprints']['ytwo']['laid_by']['host'], p['blueprints']['ytwo']['pin']['repo']")" "yardhost yardrepo" "  pinned, laid by the yard itself"

out=$(Y "$WH" apply --yard "$Y1" --plan yp9 2>&1); check "$?" "2" "the second compile of a pin in another plan: exit 2"
has "$out" "refused: yardrepo $YBR:docs/blueprints/2026-10-22-yone.md is ship yone of plan yp1 — rejoin it with --plan yp1" "  naming the plan that holds it"
check "$([ -e "$YD/plans/yp9" ] && echo made || echo none)" "none" "  no plan made for it"
out=$(Y "$WH" apply --yard "$Y1" --plan yp1 2>&1); check "$?" "0" "  rejoined with --plan: exit 0"
check "$(grep -c y1 "$YD/yout")" "1" "    nothing run twice"

out=$(YH "$WH" apply "$Y1" --plan yp1 2>&1); check "$?" "2" "a plain apply on the yard: exit 2"
has "$out" "refused: on the yard a ship is laid with --yard (or --once --all, the tick's)" "  says so"
out=$(Y "$WH" apply "$Y1" --plan yp1 2>&1); check "$?" "2" "a plain apply off the yard, its scope has a yard: exit 2"
has "$out" "refused: yardrepo's scope dock drives on yardhost; lay it with --yard" "  naming the yard and --yard"
out=$(Y "$WH" apply --watch "$Y1" --plan yp1 2>&1); check "$?" "2" "  --watch too, refused once rather than every pass"
has "$out" "wharf apply --watch: refused: yardrepo's scope dock drives on yardhost" "    said"
out=$(Y "$WH" apply "$Y1" --plan yp1 --dry-run 2>&1); check "$?" "0" "  a dry run writes nothing and is not fenced"
sed 's/"yard": "yardhost"/"yard": null/' "$YREG" > "$YD/noyard.json"
out=$(Y env CLAUDE_REPOS_JSON="$YD/noyard.json" "$WH" apply "$Y1" --plan yp1 2>&1); check "$?" "2" "its scope's yard gone, a plain apply of a pinned ship: exit 2"
has "$out" "yone refused — it is pinned (yardrepo $YBR:docs/blueprints/2026-10-22-yone.md): its blueprint is " "  the pin is its key: the plan's copy, never the checkout's file"
before=$(cat "$YD/plans/yp1/plan.json")
out=$(Y "$WH" check "$Y1" --plan yp1 --accept 2>&1); check "$?" "2" "wharf check --accept of the checkout's file on a pinned ship: exit 2"
has "$out" "wharf check --accept: yone refused — it is pinned" "  says so, as apply does"
check "$([ "$(cat "$YD/plans/yp1/plan.json")" = "$before" ] && echo same)" "same" "  plan.json unchanged: the ship stays on its copy"

YNR="$HOME/projects/nullrepo"; git init -q -b main "$YNR"; printf '# n\n\n- physical: none\n' > "$YNR/AGENTS.md"
YNB="$YNR/2026-10-22-ynull.md"; sed 's/^\(    command: "echo \)yn/\1yn-plain/' "$YN" > "$YNB"
Y "$HM" $SHIP wharf --id ypn > /dev/null
out=$(Y "$WH" apply "$YNB" --plan ypn 2>&1); check "$?" "0" "a scope with yard null: the plain apply goes ahead (no yard named yet, nothing refused: until S3)"
has "$(cat "$YD/yout")" "yn-plain" "  and ran"
# a plain-applied ship its gate keeps un-ended, in the scope whose yard is null
YNG="$YNR/2026-10-22-yngate.md"
{ printf -- '---\nship: yngate\nrepo: nullrepo\ncreated: 2026-10-22\nblocks:\n'; printf "$(shellblock yng)$(gateblock yngg yng)"; printf -- '---\n'; } > "$YNG"
Y "$HM" $SHIP wharf --id ypg > /dev/null; Y "$WH" apply "$YNG" --plan ypg > /dev/null 2>&1
sed 's/"yard": null/"yard": "farhost"/' "$YREG" > "$YD/faryard.json"
out=$(Y env CLAUDE_REPOS_JSON="$YD/faryard.json" "$WH" apply --once --all 2>&1)
has "$out" "plan ypg's yngate: its scope nul drives on farhost — not driven here" "the tick: a plain-applied ship whose scope gained another host's yard is left to that yard"
echo '{' > "$YD/torn.json"
out=$(Y env CLAUDE_REPOS_JSON="$YD/torn.json" "$WH" apply --once --all 2>&1)
has "$out" "plan ypg's yngate: the registry $YD/torn.json does not read" "  a torn registry: the unpinned ship is left alone (fails closed)"
{ printf -- '---\nship: far\nrepo: nullrepo\ncreated: 2026-10-22\nblocks:\n  - id: yf\n    provider: orca\n    agent: claude\n    host: farhost\n---\n'; brief yf t t; } > "$YNR/far.md"
out=$(Y "$WH" check "$YNR/far.md" 2>&1); check "$?" "0" "  and host: farhost passes check there: the yard rule holds only where the repo's scope has a yard"

out=$(Y "$WH" apply --yard "$YL" --plan ypl 2>&1); check "$?" "2" "a repo in no scope: exit 2"
has "$out" "refused: loose is in no scope (scopes check)" "  says so"
out=$(Y "$WH" apply --yard "$YN" --plan ypl 2>&1); check "$?" "2" "a scope with yard null: exit 2"
has "$out" "refused: scope nul has no yard (scopes set nul --yard HOST names one)" "  says so"
Y4=$(ybp yfour yardrepo '' "$(shellblock y4)"); gt "$YW" add -A; gt "$YW" commit -qm four
out=$(Y "$WH" apply --yard "$Y4" --plan yp4 2>&1); check "$?" "2" "a blueprint committed, not pushed: exit 2"
has "$out" "refused: push it first: the yard reads origin/$YBR:docs/blueprints/2026-10-22-yfour.md" "  push it first"
pushed four; echo "# an edit" >> "$Y4"
out=$(Y "$WH" apply --yard "$Y4" --plan yp4 2>&1); check "$?" "2" "  pushed, then edited here: refused the same way"
gt "$YW" checkout -q -- "$Y4"; touch "$YW/docs/blueprints/untracked.md"
out=$(Y "$WH" apply --yard "$YW/docs/blueprints/untracked.md" --plan yp4 2>&1); check "$?" "2" "  a file not committed: exit 2"
has "$out" "is not committed: commit it, then push it" "    says so"
rm "$YW/docs/blueprints/untracked.md"
YF="$YW/docs/blueprints/2026-10-22-yfar.md"
{ printf -- '---\nship: yfar\nrepo: yardrepo\ncreated: 2026-10-22\nblocks:\n  - id: yf\n    provider: orca\n    agent: claude\n    host: farhost\n---\n'; brief yf t t; } > "$YF"
pushed far   # the push check comes first: the load, which holds the host rule, reads a pushed file
out=$(Y "$WH" apply --yard "$YF" --plan ypf 2>&1); check "$?" "2" "host: farhost, a host that is no scope's yard: refused at compile, exit 2"
has "$out" "block yf: host: farhost has no launcher from the yard; run that step by hand or as a pickup" "  says so"
sed 's/host: farhost/host: yardhost/' "$YF" > "$YD/near.md"
check "$(Y "$WH" check "$YD/near.md" > /dev/null 2>&1; echo $?)" "0" "  host: yardhost, a yard, passes"

PIN0='{"repo": "yardrepo", "branch": "b", "rel": "r.md", "digest": "0000000000000000000000000000000000000000000000000000000000000000"}'
LAID0='{"mode": "attended", "depth": 0, "session": null, "host": "testhost", "t": 1}'
LAID6='{"mode": "unattended", "depth": 6, "session": null, "host": "testhost", "t": 1}'
out=$(YH "$WH" apply --yard --pinned "$PIN0" --laid-by "$LAID0" --plan ypz 2>&1); check "$?" "2" "--pinned under a local CLAUDE_CODE_SESSION_ID: exit 2"
has "$out" "refused: the yard's flags come over ssh from a caller, never from a session here" "  says so"
out=$(YH env -u CLAUDE_CODE_SESSION_ID CLAUDE_UNATTENDED=1 "$WH" apply --yard --pinned "$PIN0" --laid-by "$LAID0" --plan ypz 2>&1)
check "$?" "2" "  under CLAUDE_UNATTENDED too"
out=$(YH env -u CLAUDE_CODE_SESSION_ID "$WH" apply --yard --pinned "$PIN0" --laid-by "$LAID6" --plan ypz 2>&1); check "$?" "2" "laid_by.depth 6: exit 2"
has "$out" "refused: laid_by.depth 6 is past dispatch's cap (DISPATCH_MAX_DEPTH 5)" "  past dispatch's cap"
out=$(Y env DISPATCH_DEPTH=6 "$WH" apply --yard "$Y5" --plan yp5 2>&1); check "$?" "2" "  a caller at depth 6: refused before the ssh"
out=$(Y env DISPATCH_MAX_DEPTH=x "$WH" apply --yard "$Y5" --plan yp5 2>&1); check "$?" "2" "  DISPATCH_MAX_DEPTH not a number: a refusal, not a traceback"
out=$(YH env -u CLAUDE_CODE_SESSION_ID "$WH" apply --yard --pinned "$PIN0" --laid-by "$LAID0" --plan 'a/b' 2>&1); check "$?" "2" "  a --plan helmlib refuses: exit 2"
hasnt "$out" "Traceback" "    not a traceback"
out=$(Y "$WH" apply "$Y5" --plan yp5 --no-merge 2>&1); check "$?" "1" "--no-merge without --yard: refused"

: > "$YD/ssh.calls"
out=$(Y env CLAUDE_UNATTENDED=1 "$WH" apply --yard "$Y5" --plan yp5 2>&1); check "$?" "0" "CLAUDE_UNATTENDED on the caller: laid"
has "$(cat "$YD/ssh.calls")" '"mode": "unattended"' "  carried across as unattended, in --laid-by"
check "$(yp yp5 "p['blueprints']['yfive']['laid_by']['mode'], p['blueprints']['yfive']['merge']")" "unattended {'value': 'no', 'why': 'unattended'}" \
  "  recorded so on the yard, and its merge is no, why unattended"
out=$(Y env DISPATCH_SHIP=s DISPATCH_PLAN=p "$WH" apply --yard "$Y9" --plan yp9s 2>&1)
check "$(yp yp9s "p['blueprints']['ynine']['laid_by']['mode']" 2>/dev/null || echo "$out" | tail -3)" "unattended" "a lay from inside a ship's block (its env, no CLAUDE_UNATTENDED): unattended"
out=$(Y env CLAUDE_UNATTENDED=1 "$WH" apply --yard "$Y8" --plan yp8 2>&1); check "$?" "0" "an unattended lay through the yard: laid"
check "$(grep y8 "$YD/yout")" "y8-laid_by-0" "  the yard runs it as unattended (CLAUDE_UNATTENDED restored), so start_refusal judges it as here"
: > "$YD/ssh.calls"
out=$(Y "$WH" apply --yard "$Y6" --plan yp6 --no-merge --gen 3 2>&1); check "$?" "0" "--no-merge --gen 3: laid"
has "$(cat "$YD/ssh.calls")" " --no-merge --gen 3" "  both carried"
check "$(yp yp6 "p['blueprints']['ysix']['merge']")" "{'value': 'no', 'why': 'keel'}" "  --no-merge records merge no, why keel"
out=$(Y "$WH" apply --yard "$Y7" --plan yp7 2>&1); check "$?" "0" "a blueprint saying merge: no, sent_by and skipper: scope: laid"
check "$(yp yp7 "p['blueprints']['yseven']['merge']")" "{'value': 'no', 'why': 'blueprint'}" "  merge no, why blueprint"

echo "  the lease (S4): --yard writes plans/<id>/skipper.json at the yard's gen 0; --yard --plan fences a stale --gen"
ylf() { python3 -c 'import json, sys; r = json.load(open(sys.argv[1])); print(" ".join(str(r[k]) for k in sys.argv[2:]))' "$YD/plans/$1/skipper.json" "${@:2}"; }
check "$(ylf yp1 holder gen scope host session)" "yard 0 dock yardhost None" "--yard wrote the lease: the yard holds it at gen 0, for the pin's scope, on the yard"
check "$(grep -c '"lease": "held by yard"' "$YD/plans/yp1/events.jsonl")" "1" "  one 'held by yard' event; the rejoin wrote none"
check "$(ylf yp6 gen)" "0" "  a new ship laid with --gen 3: no lease to fence yet, gen 0 written"
check "$([ -e "$YD/plans/ypn/skipper.json" ] && echo leased || echo none)" "none" "  a plain apply (a scope with yard null) writes no lease: as before S4"
Y python3 - "$HELMBIN" <<'PY'
import sys; sys.path.insert(0, sys.argv[1]); import leaselib
leaselib.take("yp1", "dock", "skp-dock", 99999, None)   # the scope's skipper takes it (gen 1), as its sidecar would
PY
: > "$YD/ssh.calls"
out=$(Y "$WH" apply --yard "$Y1" --plan yp1 --gen 0 2>&1); check "$?" "4" "a rejoin at a stale --gen: exit 4"
has "$out" "wharf apply --yard: refused: lease at gen 1 held by skipper · dock — you are gen 0; stand down (helm skipper --stand-down)" "  the spec's line, from the yard"
check "$(grep -c '"lease": "refused"' "$YD/plans/yp1/events.jsonl")" "1" "  one 'refused' event on the yard"
out=$(Y env SKIPPER_GEN=0 "$WH" apply --yard "$Y1" --plan yp1 2>&1); check "$?" "4" "  the caller's SKIPPER_GEN: refused the same"
has "$(cat "$YD/ssh.calls")" " --gen 0" "    carried across as --gen (ssh sends no environment)"
out=$(Y "$WH" apply --yard "$Y1" --plan yp1 --gen 1 2>&1); check "$?" "0" "  --gen at the lease's gen: rejoined"
out=$(Y "$WH" apply --yard "$Y1" --plan yp1 2>&1); check "$?" "0" "  no --gen from another Mac: the yard's side is a plain shell, a sender's rejoin goes through"
out=$(YH "$WH" apply --yard "$Y1" --plan yp1 2>&1); check "$?" "4" "  on the yard, a session that does not hold the lease: refused"
out=$(YH env CLAUDE_CODE_SESSION_ID=skp-dock "$WH" apply --yard "$Y1" --plan yp1 2>&1); check "$?" "0" "  the holder's own session on the yard: rejoined"
check "$(ylf yp1 holder gen)" "skipper · dock 1" "  a rejoin leaves the lease as it is"
# the module file itself, not $WH: under the old names that is a shell shim
check "$(Y python3 - "$B/wharf" <<'PY'
import sys
from importlib.machinery import SourceFileLoader
w = SourceFileLoader("wharf_mod", sys.argv[1]).load_module()
print(w.skipper({"meta": {"skipper": "scope"}}, "yp1"), w.skipper({"meta": {"skipper": "scope"}}, "yp2"),
      w.skipper({"meta": {"skipper": "scope"}}), w.skipper({"meta": {"skipper": "s-x"}}, "yp1"))
PY
)" "skp-dock None None s-x" "  skipper: scope names the lease's holder session; the yard's hold or no ship names none; a named skipper stays"

# the finish review's item 1: a pinned ship's decision doc, answered on its branch only, is read from origin
cp "$WR/docs/d.md" "$YW/docs/yd.md"   # D1 answered B; yardrepo's main has no docs/yd.md
Y10=$(ybp yten yardrepo '' "$(shellblock ya)"'  - id: yd\n    kind: decision\n    doc: docs/yd.md\n    items: [D1]\n    depends_on: [ya]\n')
pushed decision-doc
check "$(git -C "$YR" cat-file -e main:docs/yd.md 2>/dev/null && echo there || echo absent)" "absent" "(the fixture: the doc is on the pinned branch only)"
out=$(Y "$WH" apply --yard "$Y10" --plan yp10 2>&1); check "$?" "0" "a pinned ship whose decision doc is answered on its branch only: laid"
has "$out" "resolve  yd" "  its gate resolved on the yard, the doc read from origin/<pin.branch>"
has "$out" "resolved: D1 B" "    with the answer"
hasnt "$out" "docs/yd.md not found" "    never \"not found\""

# item 2: the yard's HOME is not the caller's, and the blueprint names its repo by the caller's path:
# the yard keys on the pin's repo, its own clone under its own projects folder
YH2="$YD/yardhome"; mkdir -p "$YH2/projects"; git clone -q "$YD/origin.git" "$YH2/projects/yardrepo" 2>/dev/null
Y11=$(ybp yeleven "$HOME/projects/yardrepo" '' '  - id: y11\n    provider: shell\n    command: "pwd -P >> \\"$YOUT\\""\n')
pushed absolute-repo
out=$(Y env YARD_HOME="$YH2" "$WH" apply --yard "$Y11" --plan yp11 2>&1); check "$?" "0" "a repo: given as the caller's path, laid on a yard whose HOME differs: exit 0"
check "$(yp yp11 "p['blueprints']['yeleven']['pin']['repo'], p['blueprints']['yeleven']['main']")" "yardrepo $YH2/projects/yardrepo" \
  "  keyed on the pin's repo: the yard's own clone, not the caller's path"
check "$(tail -1 "$YD/yout")" "$(cd "$YH2/projects/yardrepo" && pwd -P)" "  and its block ran in that clone"
# the finish review: the plan side of diff() wants the pin's key too, or a path `repo:` reads "differ: repo" every pass
check "$(Y env HOME="$YH2" python3 - "$B" "$YD/plans/yp11" <<'PY'
import json, sys; sys.path.insert(0, sys.argv[1]); import blueprintlib
p = json.load(open(sys.argv[2] + "/plan.json")); rec = p["blueprints"]["yeleven"]
bp = blueprintlib.load(rec["file"], key=rec["pin"]["repo"])
rows = blueprintlib.diff(bp, "yardhost", p.get("tasks") or {}, {}, repo=rec["pin"]["repo"])
print([r for r in rows["plan"] if r[0] == "update"])
PY
)" "[]" "  settled: the plan's tasks match the pin's key, no update row on the next pass"

echo "  the yard's landing call (S6): the tick's --once --all launches a launch: finish block on the yard, --merge --by ship or --hold"
# two launch ships, each naming its own branch's worktree (launch_wt); a stub autofinish-run records the call.
# YWS: the repo's worktree folder, beside the fixture's own (spelled once, where the publish gate has it reviewed)
YWS=$(dirname "$YW")
for x in ym yh; do gt "$YR" worktree add -q "$YWS/$x" -b "claude/testhost/2026-10-22-$x"; done
lblock() { printf '%s' '  - id: launch-'"$1"'\n    depends_on: ['"$1"']\n    provider: shell\n    command: "true"\n    launch: finish\n    branch: claude/testhost/2026-10-22-'"$2"'\n'; }
YM=$(ybp ymerge yardrepo '' "$(shellblock yma)$(lblock yma ym)"); YHD=$(ybp yhold yardrepo '' "$(shellblock yha)$(lblock yha yh)")
pushed launch-ships
Y "$WH" apply --yard "$YM" --plan ypm > /dev/null 2>&1; Y "$WH" apply --yard "$YHD" --plan yph --no-merge > /dev/null 2>&1
check "$(yp ypm "p['blueprints']['ymerge']['merge']['value']") $(yp yph "p['blueprints']['yhold']['merge']['value']")" "yes no" "(the fixture: one ship the keel said merge, one --no-merge)"
check "$(Y "$HM" state ypm | python3 -c "import json,sys; print([t['status'] for t in json.load(sys.stdin)['tasks'] if t['id'] == 'launch-yma'][0])")" "waiting" \
  "  the lay's own passes: the launch raised for the skipper, as before (no launch dict there)"
YT() { YH env -u CLAUDE_CODE_SESSION_ID WHARF_AUTOFINISH_RUN="$WS/afrun" AFRUN_CALLS="$YD/afrun.calls" WHARF_DISPATCH_RC="$WS/drc" "$@"; }
: > "$YD/afrun.calls"
out=$(YT env CLAUDE_UNATTENDED=dispatch "$WH" apply --once --all 2>&1)
check "$(wc -c < "$YD/afrun.calls" | tr -d ' ')" "0" "on the yard, a dispatched run's --once --all (CLAUDE_UNATTENDED): no launch"
out=$(YT env CLAUDE_CODE_SESSION_ID=s-1 "$WH" apply --once --all 2>&1)
check "$(wc -c < "$YD/afrun.calls" | tr -d ' ')" "0" "  a session's: no launch"
out=$(YT env SKIPPER_SCOPE=dock "$WH" apply --once --all 2>&1)
check "$(wc -c < "$YD/afrun.calls" | tr -d ' ')" "0" "  a skipper's: no launch"
out=$(YT env DISPATCH_SHIP=ypm "$WH" apply --once --all 2>&1)
check "$(wc -c < "$YD/afrun.calls" | tr -d ' ')" "0" "  a ship's block (its env): no launch"
out=$(Y env -u CLAUDE_CODE_SESSION_ID WHARF_AUTOFINISH_RUN="$WS/afrun" AFRUN_CALLS="$YD/afrun.calls" WHARF_DISPATCH_RC="$WS/drc" "$WH" apply --once --all 2>&1)
check "$(wc -c < "$YD/afrun.calls" | tr -d ' ')" "0" "  off the yard, from a tick-like shell: no launch"
out=$(YT "$WH" apply --once --all --dry-run 2>&1)
has "$out" "would start the launch: $WS/afrun $YWS/ym --merge --by ship --digest $(yp ypm "p['blueprints']['ymerge']['pin']['digest']")" \
  "the yard's tick, dry: the merge ship's launch with --merge --by ship --digest <its pin>"
has "$out" "would start the launch: $WS/afrun $YWS/yh --by ship --hold" "  the --no-merge ship's with --by ship --hold"
check "$(wc -c < "$YD/afrun.calls" | tr -d ' ')" "0" "  a dry pass starts nothing"
out=$(YT "$WH" apply --once --all 2>&1); check "$?" "0" "the yard's tick: exit 0"
check "$(grep -c . "$YD/afrun.calls")" "2" "  both launches started"
has "$(cat "$YD/afrun.calls")" "$YWS/ym --merge --by ship --digest $(yp ypm "p['blueprints']['ymerge']['pin']['digest']")" "  merge yes: --merge --by ship --digest"
has "$(cat "$YD/afrun.calls")" "$YWS/yh --by ship --hold" "  merge no: --by ship --hold"
hasnt "$(cat "$YD/afrun.calls")" "--session" "  no session: the tick has none"
check "$(Y "$HM" state ypm | python3 -c "import json,sys; print([t['progress'] for t in json.load(sys.stdin)['tasks'] if t['id'] == 'launch-yma'][0])")" \
  "launch started: autofinish-run $YWS/ym --merge --by ship" "  the plan says how it was launched"
check "$(Y python3 - "$B/wharf" <<'PY'
import sys
from importlib.machinery import SourceFileLoader
w = SourceFileLoader("wharf_s6", sys.argv[1]).load_module()
print(w.tick_caller({}), w.tick_caller({"DISPATCH_DEPTH": "0"}), w.tick_caller({"DISPATCH_DEPTH": "1"}),
      w.tick_caller({"CLAUDE_UNATTENDED": "x"}), w.tick_caller({"DISPATCH_PLAN": "p"}))
PY
)" "None None DISPATCH_DEPTH=1 CLAUDE_UNATTENDED is set DISPATCH_PLAN is set" "tick_caller: the tick is the caller with none of the markers"
check "$(Y env CLAUDE_REPOS_JSON="$YD/noyard.json" HARNESS_HOST=yardhost python3 - "$B/wharf" <<'PY'
import sys
from importlib.machinery import SourceFileLoader
w = SourceFileLoader("wharf_s6b", sys.argv[1]).load_module()
print(w.yard_launch("ypm", "ymerge", None))
PY
)" "None" "  a scope with no yard: no launch dict on any host, today's raise"
for x in ym yh; do gt "$YR" worktree remove --force "$YWS/$x"; done
unset -f YT lblock

# the tick on the yard: a pinned ship read from the plan's copy, with its branch on no checkout here
touch "$HOME/.studio-brake";Y "$WH" apply --yard "$Y3" --plan yp3 > /dev/null 2>&1; rm -f "$HOME/.studio-brake"
check "$(grep -c y3 "$YD/yout")" "0" "a ship laid under the brake: compiled, its block not started"
gt "$YR" worktree remove --force "$YW"; gt "$YR" branch -q -D "$YBR"
out=$(YH "$WH" apply --once --all 2>&1); check "$?" "0" "  its branch checked out nowhere, the yard's tick: exit 0"
hasnt "$out" "gone from this Mac" "  the pinned ship is found (its copy in the plan)"
check "$(grep -c y3 "$YD/yout")" "1" "  and its block started by the tick"
python3 - "$YD/plans" <<'PY'
import json, os, sys
root = sys.argv[1]; p = json.load(open(os.path.join(root, "yp1", "plan.json")))
os.makedirs(os.path.join(root, "ypdup"))
json.dump({"id": "ypdup", "topic": "dup", "tasks": {}, "blueprints": {"yone": p["blueprints"]["yone"]}}, open(os.path.join(root, "ypdup", "plan.json"), "w"))
PY
out=$(YH "$WH" apply --once --all --dry-run 2>&1)
has "$out" "plan ypdup's yone is a pin plan yp1 drives already — not driven twice" "the tick keys a pinned ship on its pin: a second plan holding it is said, not driven"
echo "  skipper: scope with no lease names no session: a launch: finish is the skipper's, none named"
{ printf -- '---\nship: scoped\nrepo: %s\nskipper: scope\ncreated: 2026-10-22\nblocks:\n  - id: lf\n    provider: shell\n    command: "true"\n    launch: finish\n---\n' "$WR"; } > "$WR/docs/blueprints/2026-10-22-scoped.md"
out=$(W "$WH" apply "$WR/docs/blueprints/2026-10-22-scoped.md" --plan wp 2>&1)
has "$out" "raised: launch: finish is the skipper's (none named)" "  said"
# item 3: a ship laid before its scope had a yard, with a `host:` the yard rule refuses, goes on
# under the tick with one warning; a new compile of it is refused. Its own plan store.
{ printf -- '---\nship: inflight\nrepo: nullrepo\ncreated: 2026-10-22\nblocks:\n'
  printf '%s\n' '  - id: if1' '    provider: shell' '    command: "echo if1 >> \"$YOUT\""' '  - id: if2' '    provider: orca' '    agent: claude' '    host: farhost' '---'
  brief if2 t t; } > "$YNR/inflight.md"
Y env PLANS_DIR="$YD/plans3" "$HM" $SHIP wharf --id ypi > /dev/null
touch "$HOME/.studio-brake"; Y env PLANS_DIR="$YD/plans3" "$WH" apply "$YNR/inflight.md" --plan ypi > /dev/null 2>&1; rm -f "$HOME/.studio-brake"
check "$(grep -c if1 "$YD/yout")/$(python3 -c "import json; print(bool(json.load(open('$YD/plans3/ypi/plan.json'))['blueprints']['inflight'].get('digest')))")" "0/True" \
  "a ship with host: farhost accepted while its scope has no yard (its shell block held by the brake)"
sed 's/"yard": null/"yard": "testhost"/' "$YREG" > "$YD/inyard.json"
out=$(Y env PLANS_DIR="$YD/plans3" CLAUDE_REPOS_JSON="$YD/inyard.json" "$WH" apply --once --all 2>&1); check "$?" "0" "  its scope gains a yard (this host): the tick exit 0"
has "$out" "inflight: warning — block if2: host: farhost has no launcher from the yard" "  one warning, naming the block"
check "$(grep -c if1 "$YD/yout")" "1" "  and the tick keeps driving it"
out=$(Y env PLANS_DIR="$YD/plans3" CLAUDE_REPOS_JSON="$YD/inyard.json" "$WH" apply --once --all 2>&1)
check "$(printf '%s' "$out" | grep -c 'warning — block if2')" "0" "  the next tick: not said again"
out=$(Y env CLAUDE_REPOS_JSON="$YD/inyard.json" "$WH" check "$YNR/inflight.md" 2>&1); check "$?" "2" "  a new compile of it (no plan that accepted it): refused, exit 2"
has "$out" "block if2: host: farhost has no launcher from the yard" "    says so"
rm -f "$T/config/wharf-runs/ssh"
unset -f Y YH yp gt ybp shellblock pushed
echo "  the on-main reads (skipper-resilience S9): work already on main is never built again"
# a scratch bare origin (reached through insteadOf, so origin's URL still names a GitHub repo: the PR
# read needs a slug), the ship's repo cloned from it, and a second clone that plays the sibling
OM="$T/onmain"; OMO="$OM/origin.git"; OMR="$OM/repo"; OMS="$OM/sibling"; mkdir -p "$OM"
GC=(-c user.name=t -c user.email=t@t)
git init -q --bare -b main "$OMO"
git clone -q "$OMO" "$OMR" 2>/dev/null; git clone -q "$OMO" "$OMS" 2>/dev/null
git -C "$OMR" symbolic-ref HEAD refs/heads/main; git -C "$OMS" symbolic-ref HEAD refs/heads/main
mkdir -p "$OMR/docs/blueprints" "$OMR/old"
printf '# om\n\n- physical: none\n' > "$OMR/AGENTS.md"; echo base > "$OMR/base.txt"; echo old > "$OMR/old/o.txt"
mkdir -p "$OMR/docs"; printf -- '- **M1** — not built yet\n- **M2** — not built yet\n' > "$OMR/docs/om.md"   # the design doc, on main before the plan
git -C "$OMR" add AGENTS.md base.txt old docs/om.md; git -C "$OMR" "${GC[@]}" commit -qm "Init"; git -C "$OMR" push -q origin main 2>/dev/null
git -C "$OMS" pull -q origin main 2>/dev/null
git -C "$OMR" config "url.$OMO.insteadOf" "https://github.com/testowner/demo.git"
git -C "$OMR" remote set-url origin https://github.com/testowner/demo.git
check "$(git -C "$OMR" config --get remote.origin.url)" "https://github.com/testowner/demo.git" "  the scratch repo's origin names a GitHub repo and fetches from the bare one"
omstranger() {   # omstranger <file> <content> [message [trailer]]: a commit by someone else, pushed to origin's main
  git -C "$OMS" pull -q --ff-only origin main 2>/dev/null; mkdir -p "$(dirname "$OMS/$1")"; printf '%s\n' "$2" > "$OMS/$1"
  git -C "$OMS" add -A; git -C "$OMS" "${GC[@]}" commit -q -m "${3:-sibling}" ${4:+-m "$4"}; git -C "$OMS" push -q origin main 2>/dev/null; }
omwt() {   # omwt <block>: the path of the worktree holding the block's branch, asked of git (wharf's house folder is wharf's to name)
  git -C "$OMR" worktree list --porcelain | awk -v b="branch refs/heads/claude/testhost/2026-10-23-$1" '/^worktree /{p=substr($0, 10)} $0 == b {print p}'; }
ombranch() {   # ombranch <block> <file> <content>: the block's branch at wharf's house worktree (OMWD, read from the first one wharf made), one commit on it
  git -C "$OMR" worktree add -q "$OMWD/$1" -b "claude/testhost/2026-10-23-$1" main 2>/dev/null
  mkdir -p "$(dirname "$OMWD/$1/$2")"; printf '%s\n' "$3" > "$OMWD/$1/$2"
  git -C "$OMWD/$1" add -A; git -C "$OMWD/$1" "${GC[@]}" commit -qm "work $1"; }
ombp() {   # ombp <ship> <block> <extra keys, one printf format>: a one-block ship in the scratch repo, briefed
  { printf -- '---\nship: %s\nrepo: %s\ncreated: 2026-10-23\nblocks:\n  - id: %s\n    provider: orca\n    agent: claude\n' "$1" "$OMR" "$2"; printf "${3:-}"
    printf -- '---\n'; brief "$2" "t" "t"; } > "$OMR/docs/blueprints/2026-10-23-$1.md"; echo "$OMR/docs/blueprints/2026-10-23-$1.md"; }
OT() { W env WHARF_TRUST="$WS/trust" STUB_TRUST_CALLS="$TC" STUB_TRUST_REPO="$OMR" "$@"; }
oms() { grep -c "orchestration worker-start --task $(python3 -c "import json; print(json.load(open('$T/wplans/omp/plan.json'))['tasks']['$1']['orca_task'])")" "$WS/calls"; }
omst() { W "$HM" state omp | python3 -c "import json,sys; t=[t for t in json.load(sys.stdin)['tasks'] if t['id'] == '$1'][0]; print(t['status'] + ':' + (t['progress'] or ''))"; }
omq() { python3 -c "import json; st=json.load(open('$WS/state.json')); print([t['status'] for t in st['tasks'] if t['task_title'] == '$1'][-1])"; }
echo '{"projects": {}}' > "$HOME/.claude.json"
W "$HM" $SHIP wharf --id omp > /dev/null; sleep 2   # the plan's `created`: the sibling's commits below come after it, the setup's before
OMMAIN=$(git -C "$OMR" rev-parse main)

# (1) done_when against origin/main
omstranger out/fa.txt "built elsewhere" "Docs: fa landed by a sibling"
FA=$(ombp oma fa '    done_when: {file: out/fa.txt}\n')
out=$(OT "$WH" apply "$FA" --plan omp 2>&1)
has "$out" "launched via $(git -C "$OMR" log -1 --format=%h origin/main -- out/fa.txt)" "(1) a done_when file on origin/main: the block ends, launched via the commit that put it there"
check "$(oms fa)/$(omst fa | cut -d: -f1)" "0/launched" "  no worker started; the plan says launched"
check "$([ -n "$(omwt fa)" ] && echo made || echo none)/$(git -C "$OMR" rev-parse main)" "none/$OMMAIN" "  no worktree made, the local main untouched (a fetch of origin's main only)"
check "$(omq fa)" "completed" "  and Orca's Task completed by the next pass"
omstranger docs/om.md "- **M1** — Built 2026-10-23
- **M2** — not built yet" "Docs: M1 built"
MB=$(ombp omb mb '    done_when: {marker: docs/om.md#M1}\n')
out=$(OT "$WH" apply "$MB" --plan omp 2>&1); has "$out" "launched via" "(1) a done_when marker whose item says Built on origin/main: ended"
MC=$(ombp omc mc '    done_when: {marker: docs/om.md#M2}\n'); before=$(wstarts)
out=$(OT "$WH" apply "$MC" --plan omp 2>&1)
check "$(( $(wstarts) - before ))/$(printf '%s' "$out" | grep -c 'launched via')" "1/0" "  an item that says not built: no hit, the block starts"
NC=$(ombp omn nc '    done_when: {file: out/nc.txt}\n'); before=$(wstarts)
out=$(OT "$WH" apply "$NC" --plan omp 2>"$OM/err"); check "$(( $(wstarts) - before ))" "1" "no hit (the file is not on main): today's start"
check "$(cat "$OM/err")" "" "  and nothing said on stderr"
OMWD=$(dirname "$(omwt nc)")

# (2) a merged PR by head; common.api stubbed (this runner patches it in the wharf process)
cat > "$OM/wharf-api" <<'PY'
#!/usr/bin/env python3
import json, os, sys
from importlib.machinery import SourceFileLoader
b = os.environ["WHARF_BIN"]
sys.path[:0] = [b, b + "/../lib"]
import core_path
core_path.require()
import common
def api(method, path, body=None, tok=None, timeout=15):
    open(os.environ["STUB_API_CALLS"], "a").write("%s %s\n" % (method, path))
    for k, v in json.load(open(os.environ["STUB_API"])).items():
        if path.endswith(k):
            return v[0], v[1]
    return 404, None
common.api = api
sys.exit(SourceFileLoader("wharf_run", b + "/wharf").load_module().main(sys.argv[1:]))
PY
chmod +x "$OM/wharf-api"
prj() { printf '[%s, [{"number": %s, "merged_at": %s, "head": {"ref": "claude/testhost/2026-10-23-%s"}}]]' "$1" "$2" "$3" "$4"; }
{ printf '{"-pa": %s, "-pb": %s, "-pc": [500, null]}' "$(prj 200 7 '"2026-10-23T00:00:00Z"' pa)" "$(prj 200 8 null pb)"; } > "$OM/api.json"
OA() { OT env -u PLAN_NO_GH WHARF_BIN="$B" STUB_API="$OM/api.json" STUB_API_CALLS="$OM/api.calls" "$OM/wharf-api" "$@"; }
PA=$(ombp ompa pa); before=$(wstarts)
out=$(OA apply "$PA" --plan omp 2>&1)
has "$out" "launched via #7" "(2) a merged PR whose head is the block's branch: launched via #N"
check "$(( $(wstarts) - before )) $(head -1 "$OM/api.calls")" "0 GET /repos/testowner/demo/pulls?state=closed&per_page=10&head=testowner:claude%2Ftesthost%2F2026-10-23-pa" "  nothing started; asked for the closed pulls of that head"
PB=$(ombp ompb pb); before=$(wstarts)
out=$(OA apply "$PB" --plan omp 2>&1); check "$(( $(wstarts) - before ))/$(printf '%s' "$out" | grep -c 'launched via')" "1/0" "  a PR closed unmerged (merged_at null): no hit, the block starts"
PC=$(ombp ompc pc); before=$(wstarts)
out=$(OA apply "$PC" --plan omp 2>&1); check "$(( $(wstarts) - before ))" "1" "  GitHub answering 500: no hit, the block starts"
has "$out" "wharf: on-main reads: GitHub's pulls list for claude/testhost/2026-10-23-pc gave 500" "    with one line saying so"
PD=$(ombp ompd pd); n=$(wc -l < "$OM/api.calls"); out=$(OT env WHARF_BIN="$B" STUB_API="$OM/api.json" STUB_API_CALLS="$OM/api.calls" "$OM/wharf-api" apply "$PD" --plan omp 2>&1)
check "$(wc -l < "$OM/api.calls")" "$n" "  PLAN_NO_GH set: GitHub is not asked (through the stub, which counts any call)"
ombranch pe src/pe.txt "later work"
{ printf '{"-pe": [200, [{"number": 9, "merged_at": "2026-10-23T00:00:00Z", "head": {"ref": "claude/testhost/2026-10-23-pe", "sha": "%s"}}]]}' \
    "$(git -C "$OMR" rev-parse main)"; } > "$OM/api.json"
PE=$(ombp ompe pe); before=$(wstarts)
out=$(OA apply "$PE" --plan omp 2>&1); check "$(( $(wstarts) - before ))/$(printf '%s' "$out" | grep -c 'launched via')" "1/0" "  a merged PR whose head is not the branch's tip (it went on committing): no hit, the block starts"

# (3) the content proof
ombranch ea src/ea.txt "x"; omstranger src/ea.txt "x" "Feat: the same file, by a sibling"
EA=$(ombp omea ea); before=$(wstarts)
out=$(OT "$WH" apply "$EA" --plan omp 2>&1)
has "$out" "every changed file identical on main" "(3) every file the branch changed is identical on origin/main: ended, with the proof said"
check "$(( $(wstarts) - before ))/$(omst ea | cut -d: -f1)" "0/launched" "  not started; launched"
ombranch eb src/eb.txt "mine"; omstranger src/eb.txt "different" "Feat: another eb"
EB=$(ombp omeb eb); before=$(wstarts)
out=$(OT "$WH" apply "$EB" --plan omp 2>&1); check "$(( $(wstarts) - before ))/$(printf '%s' "$out" | grep -c 'launched via')" "1/0" "  a changed file that differs on main: no hit, the block starts on its branch"
git -C "$OMR" branch claude/testhost/2026-10-23-ec main; omstranger src/other.txt "o" "Feat: main moves on"
EC=$(ombp omec ec); before=$(wstarts)
out=$(OT "$WH" apply "$EC" --plan omp 2>&1); check "$(( $(wstarts) - before ))/$(printf '%s' "$out" | grep -c 'launched via')" "1/0" "  a branch cut from main and never written to (an ancestor of main): not read as merged"
ombranch ed src/ed.txt "d"; omstranger src/ed.txt "d" "Feat: ed by a sibling"; echo late > "$OMWD/ed/late.txt"
ED=$(ombp omed ed); before=$(wstarts)
out=$(OT "$WH" apply "$ED" --plan omp 2>&1); check "$(( $(wstarts) - before ))/$(printf '%s' "$out" | grep -c 'launched via')" "1/0" "  a worktree with uncommitted work: the proof speaks for commits only, no hit"

git -C "$OMR" branch claude/testhost/2026-10-23-ee main; omstranger src/ee-other.txt "o" "Feat: main moves again"; git -C "$OMR" fetch -q origin
git -C "$OMR" branch -f claude/testhost/2026-10-23-ee origin/main
EE=$(ombp omee ee); before=$(wstarts)
out=$(OT "$WH" apply "$EE" --plan omp 2>&1); check "$(( $(wstarts) - before ))/$(printf '%s' "$out" | grep -c 'launched via')" "1/0" "  a branch fast-forwarded onto main by a reset, no commit of its own in its reflog: not read as merged"
ombranch ef src/ef.txt "x"; git -C "$OMWD/ef" rm -q src/ef.txt; git -C "$OMWD/ef" "${GC[@]}" commit -qm "undo ef"
EF=$(ombp omef ef); before=$(wstarts)
out=$(OT "$WH" apply "$EF" --plan omp 2>&1); check "$(( $(wstarts) - before ))/$(printf '%s' "$out" | grep -c 'launched via')" "1/0" "  a branch whose commits net to nothing: nothing built, not read as merged"
ombranch eg src/eg.txt "g"; git -C "$OMWD/eg" reset -q --hard main
EG=$(ombp omeg eg); before=$(wstarts)
out=$(OT "$WH" apply "$EG" --plan omp 2>&1); check "$(( $(wstarts) - before ))/$(printf '%s' "$out" | grep -c 'launched via')" "1/0" "  a branch whose commit a reset took away (a rebuild forced): not read as merged"
omstranger docs/late.md "- **L1** — Built 2026-10-23" "Docs: a design doc that landed after the plan"
ML=$(ombp omml ml '    done_when: {marker: docs/late.md#L1}\n'); before=$(wstarts)
out=$(OT "$WH" apply "$ML" --plan omp 2>&1); check "$(( $(wstarts) - before ))/$(printf '%s' "$out" | grep -c 'launched via')" "1/0" "(1) a marker in a doc that was not on main when the plan was made: no evidence, the block starts"
BH=$(ombp ombh bh '    done_when: {file: base.txt}\n'); before=$(wstarts)
out=$(OT "$WH" apply "$BH" --plan omp 2>&1); check "$(( $(wstarts) - before ))/$(printf '%s' "$out" | grep -c 'launched via')" "1/0" "(1) a done_when file that was on main before the plan was made: no evidence, the block starts"

# (4) the owned paths moved by a stranger, before the first start
omstranger sib/x.txt "theirs" "Feat: x"; SIBSHA=$(git -C "$OMS" rev-parse --short=7 HEAD)
SA=$(ombp omsa sa '    owns: [sib/]\n'); before=$(wstarts)
out=$(OT "$WH" apply "$SA" --plan omp 2>&1)
has "$out" "raised: a sibling may have built this ($SIBSHA)" "(4) an owned path moved on main by a commit of no block of this ship: raised, naming it"
check "$(( $(wstarts) - before ))/$(omst sa)" "0/waiting:a sibling may have built this ($SIBSHA)" "  not started; a waiting report for the skipper"
OT "$WH" apply "$SA" --plan omp --once > /dev/null 2>&1
check "$(grep -c "a sibling may have built this" "$T/wplans/omp/events.jsonl")" "1" "  the next pass holds it and reports nothing again"
W "$HM" report omp --task sa --status planned --progress "checked: not a sibling" > /dev/null
OT "$WH" apply "$SA" --plan omp --once > /dev/null 2>&1; check "$(( $(wstarts) - before ))" "1" "  cleared by the skipper's report: it starts"
omstranger sib/y.txt "again" "Feat: y"
SA2=$(ombp omsa2 sa2 '    owns: [sib/]\n'); before=$(wstarts)
out=$(OT "$WH" apply "$SA2" --plan omp 2>&1); has "$out" "raised: a sibling may have built this" "  a second block owning the same path: raised again for its own"
omstranger sib2/z.txt "mine" "Feat: z" "Claude-Session: sess1234"
SB=$(ombp omsb sb '    owns: [sib2/]\n'); before=$(wstarts)
W "$HM" report omp --task sb --status planned --session sess1234-0000-aaaa > /dev/null   # before any apply: only the trailer can make the commit this ship's
out=$(OT "$WH" apply "$SB" --plan omp 2>&1)
check "$(( $(wstarts) - before ))/$(printf '%s' "$out" | grep -c 'sibling may')" "1/0" "  a commit with a Claude-Session trailer of this ship's own session: not a stranger's, it starts"
SC=$(ombp omsc sc '    owns: [old/]\n'); before=$(wstarts)
out=$(OT "$WH" apply "$SC" --plan omp 2>&1); check "$(( $(wstarts) - before ))/$(printf '%s' "$out" | grep -c 'sibling may')" "1/0" "  a commit older than the plan: not read, it starts"
# the ship's own landed block: /finish rewrote it and dropped its trailer, the PR was rebased in: new sha, same patch
ombranch sd src/own.txt "own"
git -C "$OMS" pull -q --ff-only origin main 2>/dev/null; git -C "$OMS" fetch -q "$OMR" claude/testhost/2026-10-23-sd 2>/dev/null
git -C "$OMS" "${GC[@]}" cherry-pick FETCH_HEAD > /dev/null 2>&1; git -C "$OMS" push -q origin main 2>/dev/null
{ printf -- '---\nship: chain\nrepo: %s\ncreated: 2026-10-23\nblocks:\n  - id: sd\n    provider: orca\n    agent: claude\n    done_when: {file: src/own.txt}\n' "$OMR"
  printf '  - id: se\n    provider: orca\n    agent: claude\n    depends_on: [sd]\n---\n'; brief sd t t; brief se t t; } > "$OMR/docs/blueprints/2026-10-23-chain.md"
before=$(wstarts); out=$(OT "$WH" apply "$OMR/docs/blueprints/2026-10-23-chain.md" --plan omp 2>&1)
check "$(omst sd | cut -d: -f1)/$(oms se)/$(printf '%s' "$out" | grep -c 'sibling may')" "launched/1/0" "  the predecessor landed as a rebased copy: it ends, and the next block starts (its own patch is no stranger's)"
check "$(git -C "$OMR" merge-base --is-ancestor origin/main claude/testhost/2026-10-23-se && echo on)/$(git -C "$OMR" config --get branch.claude/testhost/2026-10-23-se.merge || echo none)" "on/none" \
  "  and its branch starts from the origin/main that holds the predecessor's work (local main is behind), tracking nothing"
SF=$(ombp omsf sf '    owns: [src/own.txt]\n'); out=$(OT "$WH" apply "$SF" --plan omp 2>&1)
has "$out" "raised: a sibling may have built this" "  the same commit seen by a ship that has no branch of that patch: a stranger's, raised"

# a launch: finish block whose predecessor the reads ended has nothing to land: it ends too
omstranger out/lw.txt "built" "Feat: lw elsewhere"
{ printf -- '---\nship: lship\nrepo: %s\ncreated: 2026-10-23\nblocks:\n  - id: lw\n    provider: orca\n    agent: claude\n    done_when: {file: out/lw.txt}\n' "$OMR"
  printf '  - id: ll\n    provider: shell\n    command: "true"\n    depends_on: [lw]\n    launch: finish\n---\n'; brief lw t t; } > "$OMR/docs/blueprints/2026-10-23-lship.md"
before=$(wstarts); out=$(OT "$WH" apply "$OMR/docs/blueprints/2026-10-23-lship.md" --plan omp 2>&1)
check "$(omst lw | cut -d: -f1)/$(omst ll | cut -d: -f1)/$(( $(wstarts) - before ))" "launched/launched/0" "a launch: finish block after a worker the reads ended: launched too, no skipper to wait for"
check "$(printf '%s' "$out" | grep -c "launch: finish is the skipper's")" "0" "  and not raised as the skipper's"
omstranger out/lx.txt "built" "Feat: lx elsewhere"
{ printf -- '---\nship: lship3\nrepo: %s\ncreated: 2026-10-23\nblocks:\n  - id: lx\n    provider: orca\n    agent: claude\n    done_when: {file: out/lx.txt}\n' "$OMR"
  printf '  - id: ly\n    provider: shell\n    command: "true"\n    depends_on: [lx]\n    launch: finish\n---\n'; brief lx t t; } > "$OMR/docs/blueprints/2026-10-23-lship3.md"
touch "$HOME/.studio-brake"; OT "$WH" apply "$OMR/docs/blueprints/2026-10-23-lship3.md" --plan omp > /dev/null 2>&1; rm -f "$HOME/.studio-brake"
check "$(omst lx | cut -d: -f1)/$(omst ly | cut -d: -f1)" "launched/planned" "  (the reads end a worker under the brake; its launch block waits)"
W "$HM" report omp --task lx --status done --progress "rebuilt by hand" > /dev/null
out=$(OT "$WH" apply "$OMR/docs/blueprints/2026-10-23-lship3.md" --plan omp 2>&1)
check "$(omst ly | cut -d: -f1)" "waiting" "  once the predecessor reports a rebuild since, its on_main flag no longer ends the launch block"
{ printf -- '---\nship: lship2\nrepo: %s\ncreated: 2026-10-23\nblocks:\n  - id: lv\n    provider: orca\n    agent: claude\n' "$OMR"
  printf '  - id: lm\n    provider: shell\n    command: "true"\n    depends_on: [lv]\n    launch: finish\n---\n'; brief lv t t; } > "$OMR/docs/blueprints/2026-10-23-lship2.md"
touch "$HOME/.studio-brake"; OT "$WH" apply "$OMR/docs/blueprints/2026-10-23-lship2.md" --plan omp > /dev/null 2>&1; rm -f "$HOME/.studio-brake"
W "$HM" report omp --task lv --status launched --progress "launched via #12" > /dev/null   # landed by a launch, not by the reads
out=$(OT "$WH" apply "$OMR/docs/blueprints/2026-10-23-lship2.md" --plan omp 2>&1)
check "$(omst lm | cut -d: -f1)" "waiting" "  a predecessor a launch landed (its progress says launched via #N too): the launch block is not ended by it"

# before a retry: (1)-(3) again, (4) not
RA=$(ombp omra ra '    retries: 1\n    owns: [rsib/]\n    done_when: {file: out/ra.txt}\n'); before=$(wstarts)
OT "$WH" apply "$RA" --plan omp > /dev/null 2>&1; check "$(oms ra)" "1" "a retry: the first start went ahead"
settle_w ra exit; omstranger rsib/q.txt "q" "Feat: q"
OT "$WH" apply "$RA" --plan omp --once > /dev/null 2>&1; check "$(oms ra)" "2" "  an owned path moved by a stranger does not hold a retry (the sibling read is for the first start)"
settle_w ra exit; omstranger out/ra.txt "built" "Feat: ra elsewhere"
out=$(OT "$WH" apply "$RA" --plan omp --once 2>&1)
has "$out" "launched via" "  its done_when file reaching main before the retry: ended"
check "$(oms ra)/$(omst ra | cut -d: -f1)" "2/launched" "  no third start, though the starts were used up"

# a dry run fetches nothing
DA=$(ombp omda da '    done_when: {file: out/da.txt}\n')
touch "$HOME/.studio-brake"; OT "$WH" apply "$DA" --plan omp > /dev/null 2>&1; rm -f "$HOME/.studio-brake"
omstranger out/da.txt "d" "Feat: da"; tip=$(git -C "$OMR" rev-parse origin/main)
out=$(OT "$WH" apply "$DA" --plan omp --once --dry-run 2>&1); has "$out" "would start" "a dry run reads the refs as they stand: the block would start"
check "$(git -C "$OMR" rev-parse origin/main)" "$tip" "  and fetched nothing"
out=$(OT "$WH" apply "$DA" --plan omp --once 2>&1); has "$out" "launched via" "  the real pass fetches and ends it"
out=$(OT "$WH" apply "$DA" --plan omp --once --dry-run 2>&1); hasnt "$out" "would start" "  a dry run after: nothing to start"
DB=$(ombp omdb db '    done_when: {file: out/db.txt}\n')
touch "$HOME/.studio-brake"; OT "$WH" apply "$DB" --plan omp > /dev/null 2>&1; rm -f "$HOME/.studio-brake"
omstranger out/db.txt "d" "Feat: db"; git -C "$OMR" fetch -q origin
out=$(OT "$WH" apply "$DB" --plan omp --once --dry-run 2>&1); has "$out" "would end it, not start it" "  a hit in a dry run: said as would, nothing reported"
check "$(omst db | cut -d: -f1)" "planned" "    the plan not touched"
rm -f "$HOME/.claude.json"
unset -f omstranger ombranch omwt ombp OT OA oms omst omq prj
rm -f "$HOME/.claude.json"
unset -f WT oneblock wstarts ledger compiled
unset -f W n sq pj pst brief settle_w ws L skp
export PLAN_NO_WHARF=1

# the old run's blueprint verbs really went through bin/plan (a wrapper that never routed would pass)
[ "$HELM_NAMES" = old ] && check "$(sort -u "$T/wharf-old.routes" 2>/dev/null | tr '\n' '|') $([ "$(wc -l < "$T/wharf-old.routes")" -gt 20 ] && echo many)" \
  "plan apply|plan chain| many" "the old names: wharf check and apply ran as plan chain and plan apply"

echo
[ "$fails" = 0 ] && echo "test_wharf ($HELM_NAMES names): all passed" || { echo "test_wharf ($HELM_NAMES names): $fails failed"; exit 1; }
