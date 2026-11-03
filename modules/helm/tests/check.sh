#!/usr/bin/env bash
# helm's check: the no-peer cases and the schema (peers.sh, a scratch checkout of the core and
# helm alone), the two hooks as wired (hooks.sh), then the two suites B12 moved in — test_ask.sh (ask, asklib, surfaces) and
# test_helm.sh (helm, helmlib, helm_render, stalls, stalls_tick), each under the old names and the
# new (rename S5). Every suite runs on its own config dir (tests/config_fixture.sh: a synthetic
# owner, people and hosts) and finds its peers in modules/*/, so none needs an overlay checkout
# (the scrub, 2026-10-22). A core that refuses to load fails. Beside them, the VS Code extension
# (vscode/: `npm ci && npm run check` compiles, tests and packages it; regatta-vscode, 2026-11-02),
# which needs Node 22+, npm and the npm registry, and fails, never skips, without them. It builds in
# a copy in its own temp dir, never in the tree: node_modules there (130 MB, 9,000 files) would be
# copied by peers.sh and walked by the core's check and the scoped check's scope (round-1 review).
#   bash modules/helm/tests/check.sh
set -u
D="$(cd "$(dirname "$0")" && pwd)"
M="$(cd "$D/.." && pwd)"
rc=0
python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import find_core; sys.path.insert(0, find_core.hooks()); import common' "$M/lib" \
  || { echo "FAIL: the core does not load here (its line above)"; rc=1; }
echo "== peers"; bash "$D/peers.sh" || rc=1
echo "== hooks"; bash "$D/hooks.sh" || rc=1
# test_ask, test_helm and the extension share nothing (each its own mktemp dir; the suites their own config dir
# and HOME, the extension npm's cache in the caller's HOME): side by side,
# each printed whole in this order once it ends (suite-time, 2026-10-23)
O=$(mktemp -d); pids=()
# cut short (Ctrl-C, check's TERM, CI's timeout): the suites are ended too — background jobs ignore
# SIGINT — and what each printed so far is shown, not deleted unseen with $O (landing review)
# each job's children too (the extension's npm, tsc, vsce), by parent pid, never a -f pattern (AGENTS.md Traps)
halt() { for p in ${pids[@]+"${pids[@]}"}; do pkill -TERM -P "$p" 2>/dev/null; done
  kill ${pids[@]+"${pids[@]}"} 2>/dev/null
  for f in "$O"/*; do [ -f "$f" ] && [ -s "$f" ] && { echo "== $(basename "$f") (cut short)"; cat "$f"; }; done; exit "$1"; }
trap 'rm -rf "$O"' EXIT; trap 'halt 130' INT; trap 'halt 143' TERM
vscode() {
  set -o pipefail   # a failing tar -c is the copy failing, not hidden by tar -x (this job's subshell only)
  command -v npm >/dev/null || { echo "FAIL: npm is not on PATH; the extension needs Node 22+ and npm"; return 1; }
  node -e 'process.exit(Number(+process.versions.node.split(".")[0] < 22))' \
    || { echo "FAIL: the extension's build needs Node 22+ (vsce 4); found $(node --version)"; return 1; }
  # a build of the tree's own (a hand `npm ci` there) stays out of the copy; no dependency's install
  # script runs as this login (vsce-sign's postinstall: packaging signs nothing)
  mkdir "$O/vscode-build" && tar -C "$M/vscode" --exclude=./node_modules --exclude=./out --exclude='*.vsix' -cf - . \
    | tar -C "$O/vscode-build" -xf - && cd "$O/vscode-build" && npm ci --no-audit --no-fund --ignore-scripts && npm run check
}
for s in test_ask test_helm; do bash "$D/$s.sh" > "$O/$s" 2>&1 & pids+=($!); done
vscode > "$O/vscode" 2>&1 & pids+=($!)
i=0
for s in test_ask test_helm vscode; do
  wait "${pids[$i]}" || rc=1; i=$((i+1))
  echo "== $s"; cat "$O/$s"; rm -f "$O/$s"
done
exit $rc
