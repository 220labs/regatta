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
hasnt() { if grep -qF -- "$2" "$1"; then echo "  FAIL $3: unexpected [$2]"; sed 's/^/         | /' "$1" | head -30; fails=$((fails+1)); else echo "  ok   $3"; fi; }

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

echo
[ "$fails" -eq 0 ] && echo "all seed --from tests pass" || { echo "$fails seed --from test(s) FAILED"; exit 1; }
