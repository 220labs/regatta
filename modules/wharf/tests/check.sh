#!/usr/bin/env bash
# wharf's check: the checkpoint hook's suite (throwaway repos, a bare origin, GitHub and the lander
# stubbed), pr's stray check against a fake GitHub, review-gate's tiers and merge against a fake
# claude and a fake Jev, repos' and github-repo's GitHub side against a fake API, ci-provider against
# a fake gh and a fake ssh, runner-user on a stand-in root, ci-circleci against a fake CircleCI API, scopes, finish-stuck-rebase, the
# agents' pairs, council against stand-in claude, codex and agy, and C1's name rule for this module's
# bin/. Scratch paths only; no network.
# A caller's REGATTA_CONFIG is honoured (an overlay's private values, its keel and plumb); without
# one each suite makes its own and skips the cases whose peer is not installed, saying so.
# test_ci_provider always makes its own: its cases pin the runner Mac's keys.
#   bash modules/wharf/tests/check.sh
set -u
D="$(cd "$(dirname "$0")" && pwd)"
M="$(cd "$D/.." && pwd)"
rc=0

# Validated here as well as by the marketplace check: the module's suite stands on its own.
echo "== the plugin"
claude plugin validate --strict "$M" >/dev/null 2>&1 && echo "  ok   claude plugin validate --strict modules/wharf" \
  || { echo "  FAIL claude plugin validate --strict modules/wharf"; claude plugin validate --strict "$M" 2>&1 </dev/null | cat; rc=1; }
# (through cat on failure: the CLI leaves the pipes it was given O_NONBLOCK, docs/runner-interference-2026-11-02.md)

echo "== C1: every bin/ name is free on a stock PATH (pr sits in libexec/, reached as \`regatta pr\`)"
for f in "$M"/bin/*; do
  n=$(basename "$f")
  if PATH=/usr/bin:/bin:/usr/sbin:/sbin command -v "$n" >/dev/null 2>&1; then
    echo "  FAIL bin/$n is shadowed by $(PATH=/usr/bin:/bin:/usr/sbin:/sbin command -v "$n")"; rc=1
  else echo "  ok   bin/$n"; fi
done
p=$(python3 "$M/../regatta/bin/regatta" which pr)
[ "$p" = "$M/libexec/pr" ] && echo "  ok   regatta which pr: $p" || { echo "  FAIL regatta which pr: $p"; rc=1; }

for s in peers test_pr test_restack test_review_gate test_repos test_ci_provider test_runner_user test_ci_circleci test_scopes test_finish_stuck_rebase test_todo_md test_list_merge test_agents test_council test_checkpoint; do
  echo "== $s"
  # a suite still off the allowlist (test_runner_user) is absent from the public twin, with its subject; any other
  # missing suite still fails through bash
  if [ "$s" = test_runner_user ] && [ ! -f "$D/$s.sh" ] && [ ! -f "$M/bin/runner-user" ]; then
    echo "  --   skipped: not in this checkout"; continue
  fi
  bash "$D/$s.sh" || rc=1
done
exit $rc
