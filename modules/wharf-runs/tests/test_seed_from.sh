#!/usr/bin/env bash
# Tests for `pickup seed --from SCOPE` (confidential-reach S5): the one write out of a confidential scope,
# reviewed first by aurora's scope-pass (its scan, then the gate's scope.brief judge). A scratch HOME,
# config dir and registry, every name made up: `node` is confidential (node-knowledge, its word list
# naming PLUMWORD, and sec), `else` another confidential scope (other-conf), `pub` open (demo, the target);
# vlt is the vault and tenantrepo a tenant's. `claude` and `dispatch` are stand-ins. No network.
#   bash modules/wharf-runs/tests/test_seed_from.sh
set -u
B="$(cd "$(dirname "$0")/../bin" && pwd)"
T=$(mktemp -d); T="$(cd "$T" && pwd -P)"; trap '[ -n "${KEEP:-}" ] || rm -rf "$T"' EXIT; [ -n "${KEEP:-}" ] && echo "scratch $T"
fails=0
check() { if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3: expected [$2] got [$1]"; fails=$((fails+1)); fi; }
has()   { if grep -qF -- "$2" "$1"; then echo "  ok   $3"; else echo "  FAIL $3: missing [$2]"; sed 's/^/         | /' "$1" | head -30; fails=$((fails+1)); fi; }
hasnt() { if [ ! -f "$1" ]; then echo "  FAIL $3: no file $1 to read"; fails=$((fails+1)); elif grep -qF -- "$2" "$1"; then echo "  FAIL $3: unexpected [$2]"; sed 's/^/         | /' "$1" | head -30; fails=$((fails+1)); else echo "  ok   $3"; fi; }

export PYTHONUSERBASE="${PYTHONUSERBASE:-$(python3 -m site --user-base)}"   # PyYAML for the blueprint, as test_pickup
. "$(cd "$(dirname "$0")" && pwd)/config_fixture.sh"; fixture_config "$T/config"
for v in $(env | sed -n 's/^\(CLAUDE[A-Za-z0-9_]*\)=.*/\1/p; s/^\(DISPATCH_[A-Za-z0-9_]*\)=.*/\1/p; s/^\(GATE_[A-Za-z0-9_]*\)=.*/\1/p; s/^\(WEEKLY[A-Za-z0-9_]*\)=.*/\1/p'); do unset "$v"; done
unset PICKUP_NO_START PICKUP_NO_LAUNCH GH_TOKEN GITHUB_TOKEN VSCODE_PID TENANTS_FILE
export HOME="$T/u" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$T/gitconfig"
printf '[user]\n\tname = Test\n\temail = test\n[init]\n\tdefaultBranch = main\n' > "$GIT_CONFIG_GLOBAL"   # an address-free identity: the publish gate
export PICKUP_HOST=laptop PICKUP_SSH=/usr/bin/false PICKUP_PRS="$T/prs.json" PICKUP_VSCODE_WINDOW=1 PICKUP_VSCODE_CLI="$T/no-code"
export CLAUDE_CODE_ENTRYPOINT=cli CLAUDE_CODE_SESSION_ID=abcdef12-0000-4000-8000-000000000001
export CLAUDE_REPOS_JSON="$T/repos.json" ACCOUNTS_FILE="$T/accounts.json"
export GATE_TABLE="$T/models.json" GATE_LOG="$T/gate.jsonl" JEV_LOG="$T/jev.jsonl" CLAUDE_BIN="$T/claude" PICKUP_DISPATCH="$T/dispatch"
echo '[]' > "$PICKUP_PRS"
P="$T/u/projects"; mkdir -p "$P" "$T/u/.claude/projects" "$T/u/.claude/sessions"
repo() {  # repo <name> [workflow]: a git repo on main; with workflow, on the worktree workflow
  mkdir -p "$P/$1"; git -C "$P/$1" init -q
  [ -n "${2:-}" ] && { mkdir -p "$P/$1/.claude"; echo '{"checkpoint": true, "main": "main"}' > "$P/$1/.claude/workflow.json"; }
  git -C "$P/$1" add -A; git -C "$P/$1" commit -q --allow-empty -m init
}
repo node-knowledge workflow; repo sec workflow; repo other-conf workflow; repo vlt workflow; repo tenantrepo workflow
repo demo workflow
printf -- '- physical: none\n' > "$P/demo/AGENTS.md"; git -C "$P/demo" add -A; git -C "$P/demo" commit -qm contract
git init -q --bare "$T/origin.git"; git -C "$P/demo" remote add origin "$T/origin.git"; git -C "$P/demo" push -q origin main
printf '# the node'"'"'s own names\nPLUMWORD\n' > "$P/node-knowledge/.claude/words.txt"
cat > "$CLAUDE_REPOS_JSON" <<'EOF'
{"repos": {"node-knowledge": {}, "sec": {}, "other-conf": {}, "demo": {}, "vlt": {}, "tenantrepo": {}},
 "scopes": {"node": {"repos": ["node-knowledge", "sec"], "confidential": true},
            "else": {"repos": ["other-conf"], "confidential": true},
            "pub": {"repos": ["demo"]}}}
EOF
mkdir -p "$REGATTA_CONFIG/lighthouse"; echo vlt > "$REGATTA_CONFIG/lighthouse/vault"
printf '{"accounts": [{"label": "main", "home": "%s/.claude", "primary": true}], "tenants": {"own": {"repos": ["tenantrepo"]}}}\n' "$HOME" > "$ACCOUNTS_FILE"
cat > "$GATE_TABLE" <<'EOF'
{"defaults": {"claude": {"model": "opus"}},
 "sites": {"scope.brief": {"kind": "classify", "provider": "claude", "model": "sonnet"}}}
EOF
# the judge's stand-in: leak when the text says Larkspur (a made-up client's city), else clean
cat > "$T/claude" <<'EOF'
#!/bin/sh
in=$(cat); echo call >> "$(dirname "$0")/claude.calls"; printf '%s\n' "$in" > "$(dirname "$0")/claude.last"
case "$in" in *Larkspur*) v=leak;; *) v=clean;; esac
printf '{"type": "result", "is_error": false, "total_cost_usd": 0.004, "structured_output": {"text": "%s"}}\n' "$v"
EOF
cat > "$T/dispatch" <<'EOF'
#!/bin/sh
echo "dispatch $*" >> "$(dirname "$0")/dispatch.calls"
echo "started: run · demo"
EOF
chmod +x "$T/claude" "$T/dispatch"
TODAY=$(date +%F)
NM="confidential:$(printf node | shasum -a 256 | cut -c1-8)"   # the core's scope_marker("node")
S() { (cd "${CWD:-$P/node-knowledge}" && python3 "$B/pickup" seed "$@" --no-fetch) > "$T/out" 2>&1; echo $?; }
nothing() {  # nothing <topic>: no branch, no loose object added since the mark, no review
  local n; n=$(git -C "$P/demo" count-objects | cut -d' ' -f1)
  [ "$n" = "$OBJ" ] && ! git -C "$P/demo" show-ref -q --verify "refs/heads/claude/laptop/$TODAY-$1" && echo none || echo "written ($n objects, was $OBJ)"
}
mark() { OBJ=$(git -C "$P/demo" count-objects | cut -d' ' -f1); : > "$T/claude.calls"; : > "$T/dispatch.calls"; }
brief() { printf '# %s — handoff\nTask: add a retry to the uploader\nTier: Opus 5.5 high\nWhy: %s\nStart here: bin/upload\nDone means: a test\nNot this: c\n' "$1" "$2" > "$T/$1.md"; }
brief clean "the nightly job drops a file now and then"

echo "refusals before anything is read or written"
mark
check "$(CWD="$P/demo" S alpha --from node --repo "$P/demo" --file "$T/clean.md")" 1 "a cwd outside the scope: refused"
has "$T/out" "is not in scope node: --from names the scope it runs in" "  naming why"
check "$(S alpha --from pub --repo "$P/demo" --file "$T/clean.md")" 1 "an open scope: refused"
has "$T/out" "scope pub is not confidential" "  an open scope's seed needs no --from"
check "$(S alpha --from nope --repo "$P/demo" --file "$T/clean.md")" 1 "an unknown scope: refused"
check "$(S alpha --from node --file "$T/clean.md")" 1 "no --repo: refused"
has "$T/out" "--from takes --repo" "  the target is named, never the cwd's repo"
check "$(S alpha --from node --repo "$P/sec" --file "$T/clean.md")" 1 "a target in the same confidential scope: refused"
has "$T/out" "sec is in confidential scope node" "  naming it"
check "$(S alpha --from node --repo "$P/other-conf" --file "$T/clean.md")" 1 "a target in another confidential scope: refused"
has "$T/out" "other-conf is in confidential scope else" "  naming it"
check "$(S alpha --from node --repo "$P/vlt" --file "$T/clean.md")" 1 "the owner's vault: refused"
has "$T/out" "vlt is the owner's vault" "  naming it"
check "$(S alpha --from node --repo "$P/tenantrepo" --file "$T/clean.md")" 1 "a tenant's repo: refused"
has "$T/out" "tenantrepo is tenant own's repo" "  naming the tenant"
check "$(S alpha --from node --repo "$P/demo" --file "$T/clean.md" --start)" 1 "--start: refused (dispatch or nothing)"
# S6's third landing review, item 5: a --note would ride with the run unreviewed, and dispatch refuses it for
# good; seed takes none, so it is refused before the seed is written or pushed (the check below: nothing)
check "$(S alpha --from node --repo "$P/demo" --file "$T/clean.md" --note "context")" 2 "--note: refused at the arguments, before anything is written"
has "$T/out" "unrecognized arguments: --note" "  seed takes no --note"
echo '{"accounts": [' > "$T/torn-accounts.json"
check "$(ACCOUNTS_FILE="$T/torn-accounts.json" S alpha --from node --repo "$P/demo" --file "$T/clean.md")" 1 "tenancy that will not read: refused (fails closed)"
has "$T/out" "could not say whether demo is a tenant's" "  saying so"
head -c 40 "$CLAUDE_REPOS_JSON" > "$T/torn.json"
check "$(CLAUDE_REPOS_JSON="$T/torn.json" S alpha --from node --repo "$P/demo" --file "$T/clean.md")" 1 "a torn registry: refused"
check "$(wc -l < "$T/claude.calls" | tr -d ' ') $(nothing alpha)" "0 none" "  no judge called, nothing written"

echo "the review: the scan, then the judge, before any write"
brief named "PLUMWORD asked for it"
mark; check "$(S beta --from node --repo "$P/demo" --file "$T/named.md")" 1 "a brief naming the node's word: refused"
has "$T/out" "the brief names confidential scope node" "  by the scan"
check "$(wc -l < "$T/claude.calls" | tr -d ' ') $(nothing beta)" "0 none" "  no judge, nothing written"
mark; check "$(S plumword-fix --from node --repo "$P/demo" --file "$T/clean.md")" 1 "a topic naming the node's word: refused (the branch name leaves too)"
check "$(nothing plumword-fix)" "none" "  nothing written"
brief own "the node asked for it"
mark; check "$(S theta --from node --repo "$P/demo" --file "$T/own.md")" 1 "a brief naming the scope itself: refused (S5's landing review)"
has "$T/out" "its own name, in the brief or the topic" "  before the bundle is built"
check "$(wc -l < "$T/claude.calls" | tr -d ' ') $(nothing theta)" "0 none" "  no judge, nothing written"
mark; check "$(S node-fix --from node --repo "$P/demo" --file "$T/clean.md")" 1 "a topic naming the scope: refused"
check "$(wc -l < "$T/claude.calls" | tr -d ' ') $(nothing node-fix)" "0 none" "  no judge, nothing written"
brief leaky "the Larkspur depot drops a file now and then"
mark; check "$(S gamma --from node --repo "$P/demo" --file "$T/leaky.md")" 1 "a brief the scan passes and the judge calls a leak: refused"
has "$T/out" "judged a leak by the gate's scope.brief judge" "  by the judge"
check "$(wc -l < "$T/claude.calls" | tr -d ' ') $(nothing gamma)" "1 none" "  one judge call, nothing written"
printf '{"sites": {"other.site": {"kind": "classify", "provider": "off"}}}\n' > "$T/no-row.json"
mark; check "$(GATE_TABLE="$T/no-row.json" S delta --from node --repo "$P/demo" --file "$T/clean.md")" 1 "no scope.brief row: refused, never a pass"
has "$T/out" "could not be judged" "  saying the judge could not tell"
check "$(nothing delta)" "none" "  nothing written"

echo "a clean brief: seeded with its review, started with its origin"
mark; check "$(S epsilon --from node --repo "$P/demo" --file "$T/clean.md" --dry-run)" 0 "--dry-run: reviewed, then says what it would do"
has "$T/out" "and docs/handoff/$TODAY-epsilon.review" "  naming the review"
has "$T/out" "a seed out of a confidential scope routes nothing" "  and routing nothing: keel would read the brief before its review (routed comments S2 beside S5)"
check "$(nothing epsilon)" "none" "  nothing written"
SN=claude/laptop/$TODAY-epsilon
mark; check "$(S epsilon --from node --repo "$P/demo" --file "$T/clean.md")" 0 "seed --from: exit 0"
has "$T/out" "reviewed: the brief leaving node is clean" "  reviewed first"
check "$(git -C "$P/demo" diff --name-only main $SN | tr '\n' ' ')" "docs/blueprints/$TODAY-epsilon.md docs/handoff/$TODAY-epsilon.md docs/handoff/$TODAY-epsilon.review " \
  "  one commit: the brief, its review and its blueprint"
git -C "$P/demo" show "$SN:docs/handoff/$TODAY-epsilon.review" > "$T/review.json"
check "$(python3 -c 'import json, sys; d = json.load(open(sys.argv[1])); print(d["origin"], d["scan"], d["judge"], d["site"], d["provider"], d["model"], d["cost_usd"], bool(d["time"]))' "$T/review.json")" \
  "$NM clean clean scope.brief claude sonnet 0.004 True" "  the review: origin as the scope's marker, both verdicts, site, provider, model, cost, time"
check "$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["sha256"])' "$T/review.json")" \
  "$(git -C "$P/demo" show "$SN:docs/handoff/$TODAY-epsilon.md" | shasum -a 256 | cut -d' ' -f1)" "  its sha256 is the committed brief's"
git -C "$P/demo" log -1 --format=%B $SN > "$T/msg"
has "$T/msg" "Seeded-By: $NM/abcdef12 on laptop" "  Seeded-By carries the scope's marker"
hasnt "$T/msg" "node" "  never the scope's name, nor the node's repo"
check "$(git -C "$P/demo" grep -i -l node $SN -- docs | wc -l | tr -d ' ') $(git -C "$P/demo" grep -l retry $SN -- docs | wc -l | tr -d ' ')" "0 2" \
  "  no file of the seed names it either (the brief and blueprint found by a word they hold)"
has "$T/claude.last" "Branch: $SN" "  the judge read the branch name"
has "$T/claude.last" "Seeded-By: $NM/abcdef12 on laptop" "  and the Seeded-By line as sent"
check "$(git -C "$P/demo" rev-parse origin/$SN)" "$(git -C "$P/demo" rev-parse $SN)" "  pushed"
has "$T/dispatch.calls" "dispatch $SN --repo $P/demo --next --origin $NM" "  started by dispatch --next with the marker as --origin"
hasnt "$T/out" "vscode://" "  no tab"
(cd "$P/demo" && python3 "$B/pickup" show epsilon --no-fetch) > "$T/show" 2>&1
has "$T/show" "brief docs/handoff/$TODAY-epsilon.md" "  pickup reads the .md as the seed's brief, never the .review"
# confidential-reach S6: the review the verb wrote is the one dispatch's gate reads (the core's spawn_gate,
# spawn_review_ok), judged from the caller's directory as dispatch judges it
cat > "$T/gate.py" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import core_path
core_path.require()
import common
repo, ref, cwd, origin = sys.argv[2:6]
why, mark = common.spawn_gate(repo, ref, cwd, origin or None)[:2]
print("refused: %s" % why if why else "ok %s" % mark)
PY
gate() { python3 "$T/gate.py" "$B/../lib" "$P/demo" "$1" "${2:-$P/node-knowledge}" "${3:-}"; }
check "$(gate "$SN")" "ok $NM" "S6: the seed the verb wrote passes dispatch's gate from inside the node, its origin the review's marker"
check "$(gate "$SN" "$P/demo")" "ok $NM" "  and from an open caller (a --next of the spawned run)"
EM="confidential:$(printf else | shasum -a 256 | cut -c1-8)"
check "$(gate "$SN" "" "$EM")" "refused: its review's origin $NM is not the origin given ($EM)" "  an --origin other than its review's: refused"
check "$(gate main)" "refused: its seed carries no docs/handoff/*.review of its own topic: the brief was never reviewed on its way out" \
  "  an unreviewed branch asked from inside the node: refused (G2)"
check "$(gate main "$P/demo")" "ok None" "  the same branch from an open caller is an open run"
check "$(gate main "$P/sec")" "refused: its seed carries no docs/handoff/*.review of its own topic: the brief was never reviewed on its way out" \
  "  from the scope's other repo too: every checkout of the scope is inside it"
mark; check "$(S zeta --from node --repo "$P/demo" --file "$T/clean.md" --no-start)" 0 "--no-start: seeded"
has "$T/out" "--next --repo $P/demo --origin $NM" "  the start line carries the marker"
check "$(wc -l < "$T/dispatch.calls" | tr -d ' ')" 0 "  and nothing started"
check "$(cd "$P/demo" && python3 -c 'import sys; from importlib.machinery import SourceFileLoader as L; m = L("pk", sys.argv[1]).load_module(); from pathlib import Path; print(m.branch_origin(Path(sys.argv[2]), {"name": sys.argv[3], "local": True}))' "$B/pickup" "$P/demo" "$SN")" "$NM" \
  "every start path reads the origin back from the branch's .review (S5's landing re-review)"
check "$(cd "$P/demo" && python3 -c 'import sys; from importlib.machinery import SourceFileLoader as L; m = L("pk", sys.argv[1]).load_module(); from pathlib import Path; print(m.branch_origin(Path(sys.argv[2]), {"name": "main", "local": True}))' "$B/pickup" "$P/demo")" "None" \
  "  a branch with no .review has none"
rm "$P/demo/AGENTS.md"; git -C "$P/demo" commit -qam "no contract"
mark; check "$(S eta --from node --repo "$P/demo" --file "$T/clean.md")" 1 "a repo dispatch does not take: refused before any write (its seed could never start)"
has "$T/out" "dispatch does not take demo" "  saying so"
check "$(wc -l < "$T/claude.calls" | tr -d ' ') $(nothing eta)" "0 none" "  no judge, nothing written"
printf -- '- physical: none\n' > "$P/demo/AGENTS.md"; git -C "$P/demo" add -A; git -C "$P/demo" commit -qm contract

echo "the landing re-review's refusals"
repo acme-portal workflow; printf -- '- physical: none\n' > "$P/acme-portal/AGENTS.md"
sed 's/"else": {"repos": \["other-conf"\]/"else": {"repos": ["other-conf", "acme-*"]/' "$CLAUDE_REPOS_JSON" > "$T/glob.json"
mark; check "$(CLAUDE_REPOS_JSON="$T/glob.json" S iota --from node --repo "$P/acme-portal" --file "$T/clean.md")" 1 "an unregistered repo a confidential glob takes: refused"
has "$T/out" "acme-portal is in confidential scope else" "  naming the scope"
ln -s "$T/drive-away/tenants.json" "$T/tenants-link.json"
mark; check "$(TENANTS_FILE="$T/tenants-link.json" S kappa --from node --repo "$P/demo" --file "$T/clean.md")" 1 "a tenancy file written that does not read, no copy: refused (fails closed)"
has "$T/out" "tenancy file is written but does not read" "  saying so"
check "$(wc -l < "$T/claude.calls" | tr -d ' ') $(nothing kappa)" "0 none" "  no judge, nothing written"
mark; check "$(S plain --repo "$P/demo" --file "$T/clean.md" --no-start)" 1 "a plain seed out of a confidential scope: refused (it goes by --from)"
has "$T/out" "a seed out of it goes by --from" "  saying so"
check "$(nothing plain)" "none" "  nothing written"
check "$(CLAUDE_REPOS_JSON="$T/torn.json" S plain --repo "$P/demo" --file "$T/clean.md" --no-start)" 1 "  a torn registry: refused too"

echo "keel's lookout seed, --beside a branch, under the same scope checks (routed comments S3 beside S5)"
RB=claude/laptop/2026-10-27-run
git -C "$P/demo" checkout -q -b "$RB"; echo work > "$P/demo/work.txt"; git -C "$P/demo" add work.txt
git -C "$P/demo" commit -qm "the run's work"; git -C "$P/demo" checkout -q main
brief look "an answer on the run's page"
# the lookout's own form (keel's lookout_start), run in the doc's repo as it is: an open repo, a plain seed
mark; check "$(CWD="$P/demo" S lookseed --file "$T/look.md" --beside "$RB" --repo "$P/demo" --no-start)" 0 "the lookout's seed in its open repo: seeded"
LN=claude/laptop/$TODAY-lookseed
check "$(git -C "$P/demo" rev-parse "$LN^") $(wc -l < "$T/claude.calls" | tr -d ' ')" "$(git -C "$P/demo" rev-parse "$RB") 0" \
  "  off the run's tip, and no review: nothing leaves a scope"
git -C "$P/demo" log -1 --format=%B "$LN" > "$T/msg"
has "$T/msg" "Seeded-From: $RB" "  Seeded-From: names the run's branch"
has "$T/msg" "Seeded-By: demo/" "  Seeded-By names the repo it runs in, no marker"
# a confidential repo's own page: the lookout seeds beside its branch in that repo, in its scope
git -C "$P/sec" checkout -q -b "$RB"; echo work > "$P/sec/work.txt"; git -C "$P/sec" add work.txt
git -C "$P/sec" commit -qm "the run's work"; git -C "$P/sec" checkout -q main
printf -- '- physical: none\n' > "$P/sec/AGENTS.md"; git -C "$P/sec" add -A; git -C "$P/sec" commit -qm contract
check "$(CWD="$P/sec" S lookin --file "$T/look.md" --beside "$RB" --repo "$P/sec" --no-start)" 0 "the lookout's seed in a confidential repo, run there: seeded within its scope"
check "$(git -C "$P/sec" rev-parse "claude/laptop/$TODAY-lookin^")" "$(git -C "$P/sec" rev-parse "$RB")" "  off that run's tip"
# the cwd keel no longer inherits: a pass started inside a confidential scope, seeding an open repo
mark; check "$(S lookout2 --file "$T/look.md" --beside "$RB" --repo "$P/demo" --no-start)" 1 "a --beside seed from a cwd in a confidential scope into an open repo: refused (why the lookout runs pickup in the doc's repo)"
has "$T/out" "a seed out of it goes by --from" "  by confined_refusal"
check "$(nothing lookout2)" "none" "  nothing written"
# item 7 of S6's fourth landing review: pickup judges the caller as dispatch does — its session's own folder
# by record, and a repo the registry lists nowhere that a confidential glob takes
SDIR="$T/u/.claude/sessions"
printf '{"pid": 99998, "sessionId": "node-sess-7", "cwd": "%s", "updatedAt": 1}\n' "$P/demo" > "$SDIR/99998.json"
printf '{"pid": 99999, "sessionId": "node-sess-7", "cwd": "%s", "updatedAt": 99}\n' "$P/node-knowledge" > "$SDIR/99999.json"
mark; check "$(CWD="$P/demo" CLAUDE_CODE_SESSION_ID=node-sess-7 S look7 --file "$T/look.md" --repo "$P/demo" --no-start)" 1 \
  "item 7: a node session's \`cd <open repo> && pickup seed\`: refused by its session's folder (its newest record)"
has "$T/out" "a seed out of it goes by --from" "  by confined_refusal"
check "$(nothing look7)" "none" "  nothing written"
(cd "$P/demo" && CLAUDE_CODE_SESSION_ID=node-sess-7 python3 "$B/pickup" brief "$RB" --text 'Task: the step after' --no-fetch) > "$T/out" 2>&1
check "$?" "1" "  its \`pickup brief\` from the open repo: refused too"
has "$T/out" "a seed out of it goes by --from" "  saying so"
rm -f "$SDIR/99999.json"
mark; check "$(CWD="$P/demo" CLAUDE_CODE_SESSION_ID=node-sess-7 S look7b --file "$T/look.md" --repo "$P/demo" --no-start)" 0 \
  "  the same session whose newest record is the open repo: seeded (a resumed session is judged by its newest record)"
rm -f "$SDIR/99998.json"
repo glob-node workflow
sed 's/"node": {"repos": \["node-knowledge", "sec"\]/"node": {"repos": ["node-knowledge", "sec", "glob-*"]/' "$CLAUDE_REPOS_JSON" > "$T/glob7.json"
mark; check "$(CWD="$P/glob-node" CLAUDE_REPOS_JSON="$T/glob7.json" S look7c --file "$T/look.md" --repo "$P/demo" --no-start)" 1 \
  "  a caller in an unregistered repo a confidential glob takes: refused, as dispatch refuses it"
check "$(nothing look7c)" "none" "  nothing written"
mark; check "$(S lookout3 --from node --beside "$RB" --repo "$P/demo" --file "$T/clean.md")" 1 "--from SCOPE with --beside: refused (the review reads the brief alone, never a branch's commits)"
has "$T/out" "--from takes no --beside" "  saying so"
check "$(wc -l < "$T/claude.calls" | tr -d ' ') $(nothing lookout3)" "0 none" "  no judge, nothing written"

# a seed beside a spawn inherits its source's `.review` under the source's topic: by the core's one rule of
# which review counts (its own topic's: the fourth landing review, item 1) it is an open run, for the queue,
# the gate and pickup's branch_origin alike
Q="$(cd "$(dirname "$0")/.." && pwd)/bin/dispatch-queue"
git -C "$P/demo" checkout -q -b claude/laptop/2026-10-28-childtopic main
mkdir -p "$P/demo/docs/handoff"; echo '{"origin":"confidential:x"}' > "$P/demo/docs/handoff/2026-10-28-spawntopic.review"
git -C "$P/demo" add -A; git -C "$P/demo" commit -qm "a seed beside a spawn"; git -C "$P/demo" checkout -q main
cat > "$T/hasrev.py" <<'PY'
import sys, importlib.machinery, importlib.util
l = importlib.machinery.SourceFileLoader("dq", sys.argv[1]); sp = importlib.util.spec_from_loader("dq", l)
m = importlib.util.module_from_spec(sp); l.exec_module(m)
print(m.has_review(sys.argv[2], sys.argv[3]))
PY
check "$(python3 "$T/hasrev.py" "$Q" "$P/demo" claude/laptop/2026-10-28-childtopic)" "False" "dispatch-queue's has_review: a .review under another topic marks no spawn (item 1)"
check "$(python3 "$T/hasrev.py" "$Q" "$P/demo" "$RB")" "False" "  and a branch with none is not"
check "$(python3 "$T/hasrev.py" "$Q" "$P/demo" "$SN")" "True" "  a branch with its own topic's review is"
check "$(cd "$P/demo" && python3 -c 'import sys; from importlib.machinery import SourceFileLoader as L; m = L("pk", sys.argv[1]).load_module(); from pathlib import Path; print(m.branch_origin(Path(sys.argv[2]), {"name": sys.argv[3], "local": True}))' "$B/pickup" "$P/demo" claude/laptop/2026-10-28-childtopic)" "None" \
  "  pickup's branch_origin reads it so: no --origin for a seed beside a spawn"

echo "S6's fifth landing review: two scopes that share a repo; pickup next and open --note ask the gate first"
# item 2: a caller in two scopes is one scope's own run only where every scope it is in takes the repo — main's
# confined_refusal refused a caller in a repo two scopes share writing a repo of only one (the narrowed-guard trap)
repo shared workflow
sed 's/"node": {"repos": \["node-knowledge", "sec"\]/"node": {"repos": ["node-knowledge", "sec", "shared"]/; s/"else": {"repos": \["other-conf"\]/"else": {"repos": ["other-conf", "shared"]/' \
  "$CLAUDE_REPOS_JSON" > "$T/two5.json"
mark; check "$(CWD="$P/shared" CLAUDE_REPOS_JSON="$T/two5.json" S two5 --file "$T/look.md" --repo "$P/sec" --no-start)" 1 \
  "item 2: a caller in a repo node and else share, seeding a repo of node alone: refused, as main refused it"
has "$T/out" "a seed out of it goes by --from" "  by confined_refusal"
CWD="$P/shared" CLAUDE_REPOS_JSON="$T/two5.json" S two5own --file "$T/look.md" --repo "$P/shared" --no-start --dry-run > /dev/null
hasnt "$T/out" "a seed out of it goes by --from" "  the shared repo's own seed from inside it: no confined refusal (both scopes take it)"
printf '{"pid": 99997, "sessionId": "node-sess-5", "cwd": "%s", "updatedAt": 5}\n' "$P/other-conf" > "$SDIR/99997.json"
mark; check "$(CWD="$P/sec" CLAUDE_CODE_SESSION_ID=node-sess-5 S two5b --file "$T/look.md" --repo "$P/sec" --no-start)" 1 \
  "  a shell in node's repo whose session folder is in else, seeding node's repo: refused (else is not node's)"
rm -f "$SDIR/99997.json"
# the sixth landing review: `seed --from node` from a repo node and else share — the review vouches for node, and
# the session is in else too, whose text it may carry. Refused before scope-pass is asked
mark; check "$(CWD="$P/shared" CLAUDE_REPOS_JSON="$T/two5.json" S two6 --from node --repo "$P/demo" --file "$T/clean.md")" 1 \
  "sixth review: seed --from node from a repo node and else share: refused"
has "$T/out" "not node alone" "  saying the session is in two scopes"
check "$(nothing two6) $(wc -l < "$T/claude.calls" | tr -d ' ')" "none 0" "  nothing written, no judge asked"
printf '{"pid": 99995, "sessionId": "node-sess-6", "cwd": "%s", "updatedAt": 6}\n' "$P/other-conf" > "$SDIR/99995.json"
mark; check "$(CLAUDE_CODE_SESSION_ID=node-sess-6 S two6b --from node --repo "$P/demo" --file "$T/clean.md")" 1 \
  "  a shell in node whose session folder is in else: refused"
rm -f "$SDIR/99995.json"
# item 3: `pickup next` commits its prompt as a brief (seed_next) or hands it to a tab as --note; `pickup open
# --note` hands the note to a new session in the repo. From inside a node into an open repo no review read it
printf '{"pid": 99996, "sessionId": "node-sess-3", "cwd": "%s", "updatedAt": 3}\n' "$P/node-knowledge" > "$SDIR/99996.json"
git -C "$P/demo" checkout -q "$LN"; H0=$(git -C "$P/demo" rev-parse HEAD)
(cd "$P/demo" && CLAUDE_CODE_SESSION_ID=node-sess-3 python3 "$B/pickup" next "the next step, from the node" --no-fetch) > "$T/out" 2>&1
check "$?" "1" "item 3: a node session's \`cd <open repo> && pickup next\`: refused"
has "$T/out" "next: this session runs in a confidential scope" "  by confined_refusal, before anything is read"
check "$(git -C "$P/demo" rev-parse HEAD) $(git -C "$P/demo" status --porcelain | wc -l | tr -d ' ') $(wc -l < "$T/dispatch.calls" | tr -d ' ')" "$H0 0 0" \
  "  no brief committed or written, no dispatch"
git -C "$P/demo" checkout -q main; rm -f "$SDIR/99996.json"
(cd "$P/node-knowledge" && python3 "$B/pickup" open "$LN" --repo "$P/demo" --note "a note from the node" --fresh --dry-run --no-fetch) > "$T/out" 2>&1
check "$?" "1" "  \`pickup open --note\` from inside the node on an open repo's branch: refused"
has "$T/out" "open --note: this session runs in a confidential scope" "  by confined_refusal, before any road opens"
(cd "$P/node-knowledge" && python3 "$B/pickup" open "$LN" --repo "$P/demo" --fresh --dry-run --no-fetch) > "$T/out" 2>&1
hasnt "$T/out" "open --note:" "  the same open without a note: not refused by the gate (it hands on no text of the node's)"

echo "sandboxed-seed: every fence still refuses with ps refused, and the roads it lets by lay (docs/sandboxed-seed-2026-11-04.md)"
# a sandboxed Mac session is refused the exec of ps (EPERM): ps_refused.py stands in, each refusal a line of
# $T/ps.refused; a live registry entry with a start to check makes collect's walk reach ps (no other session's id)
PSR_PY="$(cd "$(dirname "$0")" && pwd)/ps_refused.py"
SX() { : > "$T/ps.refused"; (cd "${CWD:-$P/node-knowledge}" && PS_REFUSED_LOG="$T/ps.refused" python3 "$PSR_PY" "$B/pickup" seed "$@" --no-fetch) > "$T/out" 2>&1; echo $?; }
printf '{"pid": %s, "sessionId": "live-sbx-1", "cwd": "%s", "procStart": "Mon Jan  1 00:00:00 2001", "updatedAt": 1}\n' "$$" "$P/demo" > "$SDIR/$$.json"
mark; check "$(SX sbxplain --repo "$P/demo" --file "$T/clean.md" --no-start)" 1 "ps refused: a plain seed out of a confidential scope: refused"
has "$T/out" "a seed out of it goes by --from" "  by confined_refusal"
check "$(nothing sbxplain) $(wc -l < "$T/ps.refused" | tr -d ' ')" "none 0" "  nothing written, and ps never asked: the fence is before collect()"
printf '{"pid": 99999, "sessionId": "node-sess-sbx", "cwd": "%s", "updatedAt": 99}\n' "$P/node-knowledge" > "$SDIR/99999.json"
mark; check "$(CWD="$P/demo" CLAUDE_CODE_SESSION_ID=node-sess-sbx SX sbx7 --file "$T/look.md" --repo "$P/demo" --no-start)" 1 \
  "  a node session's \`cd <open repo> && pickup seed\`: refused by its session's folder (the registry, never ps)"
has "$T/out" "a seed out of it goes by --from" "  by confined_refusal"
check "$(nothing sbx7) $(wc -l < "$T/ps.refused" | tr -d ' ')" "none 0" "  nothing written, ps never asked"
rm -f "$SDIR/99999.json"
mark; check "$(CWD="$P/demo" SX sbxout --from node --repo "$P/demo" --file "$T/clean.md")" 1 "  seed --from node from a cwd outside it: refused"
has "$T/out" "is not in scope node" "  by from_scope_refusal"
check "$(wc -l < "$T/claude.calls" | tr -d ' ') $(nothing sbxout) $(wc -l < "$T/ps.refused" | tr -d ' ')" "0 none 0" "  no judge, nothing written, ps never asked"
mark; check "$(CLAUDE_REPOS_JSON="$T/torn.json" SX sbxtorn --from node --repo "$P/demo" --file "$T/clean.md")" 1 "  a torn registry: refused"
check "$(nothing sbxtorn) $(wc -l < "$T/ps.refused" | tr -d ' ')" "none 0" "  nothing written, ps never asked"
# a fence after collect(): the scope-pass judge, which reads the brief once ps was asked and refused
mark; check "$(SX sbxleak --from node --repo "$P/demo" --file "$T/leaky.md")" 1 "  a brief the judge calls a leak, past the refused ps: refused"
has "$T/out" "judged a leak by the gate's scope.brief judge" "  by the judge"
check "$(nothing sbxleak) $(grep -c -- '-o lstart=' "$T/ps.refused")" "none 1" "  nothing written, the live registry asked and refused first"
SXN=claude/laptop/$TODAY-sbxfrom
mark; check "$(SX sbxfrom --from node --repo "$P/demo" --file "$T/clean.md")" 0 "ps refused: seed --from node, reviewed: seeded"
has "$T/out" "reviewed: the brief leaving node is clean" "  reviewed first"
check "$(git -C "$P/demo" diff --name-only main $SXN | tr '\n' ' ')" "docs/blueprints/$TODAY-sbxfrom.md docs/handoff/$TODAY-sbxfrom.md docs/handoff/$TODAY-sbxfrom.review " \
  "  the brief, its review and its blueprint"
has "$T/dispatch.calls" "dispatch $SXN --repo $P/demo --next --origin $NM" "  started by dispatch with the marker as --origin"
check "$(grep -c -- '-o lstart=' "$T/ps.refused")" "2" "  the live registry asked, and refused, before the seed and after"
hasnt "$T/out" "PermissionError" "  never the sandbox's refusal"
mark; check "$(CWD="$P/demo" SX sbxopen --repo "$P/demo" --file "$T/clean.md" --no-start)" 0 "ps refused: an open repo's own plain seed: seeded"
has "$T/out" "seeded claude/laptop/$TODAY-sbxopen in demo" "  laid"
rm -f "$SDIR/$$.json"

echo
[ "$fails" -eq 0 ] && echo "all seed --from tests pass" || { echo "$fails seed --from test(s) FAILED"; exit 1; }
