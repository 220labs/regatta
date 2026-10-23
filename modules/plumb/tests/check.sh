#!/usr/bin/env bash
# plumb's check: crew-report's suite (synthetic transcripts under a scratch HOME; no network), then
# usage-report's (with every plumb file's no-peer cases) and interruptions', then the benches' own
# tests (G37). Every suite writes its own config dir and names no overlay (the plumb scrub,
# 2026-10-22), so the Macs, CI and the public twin run the same cases. A case whose peer is a module
# this copy lacks (wharf and keel are private until their scrubs) is skipped in one line. A core
# that refuses to load fails.
#   bash modules/plumb/tests/check.sh
set -u
D="$(cd "$(dirname "$0")" && pwd)"
M="$(cd "$D/.." && pwd)"
rc=0
# the core loads, and names the peers this copy has (common.tool(): modules/*/ first)
peer() { python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import find_core; sys.path.insert(0, find_core.hooks()); import common
p = common.tool(sys.argv[2]); print(p or "")' "$M/lib" "$1"; }
if ! python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import find_core; sys.path.insert(0, find_core.hooks()); import common' "$M/lib"; then
  echo "FAIL: the core does not load here (its line above)"; rc=1
fi
for s in crew-report usage-report interruptions; do
  echo "== $s"
  if [ ! -f "$D/$s.sh" ]; then echo "  skip: $s not in this copy"; continue; fi
  bash "$D/$s.sh" || rc=1
done
if [ -d "$M/bench" ]; then
  echo "== bench"
  if [ -z "$(peer keel)" ]; then
    echo "  skip: decisions/test_corpus.sh reads keel's parser, not in this copy"
  else
    bash "$M/bench/decisions/test_corpus.sh" > "${TMPDIR:-/tmp}/plumb-corpus.$$" 2>&1 \
      && echo "  ok   decisions/test_corpus.sh" || { cat "${TMPDIR:-/tmp}/plumb-corpus.$$"; rc=1; }
    rm -f "${TMPDIR:-/tmp}/plumb-corpus.$$"
  fi
  if [ -z "$(peer session_status.py)" ]; then
    echo "  skip: sessions/test_collect.py and the sessions benches read wharf's session_status.py, not in this copy"
    benches="decisions/jev.py decisions/corpus.py"
  else
    (cd "$M/bench/sessions" && python3 test_collect.py > /dev/null 2>&1) \
      && echo "  ok   sessions/test_collect.py" || { echo "  FAIL sessions/test_collect.py"; rc=1; }
    benches="decisions/jev.py sessions/arms.py sessions/collect.py sessions/score.py decisions/corpus.py sessions/sheet.py"
  fi
  # G37: each bench with arguments that loads a peer starts and reads them. jev.py and arms.py load
  # jev lazily, sheet.py on use, so for those three this proves start-up only; docs.py has no --help.
  for b in $benches; do
    python3 "$M/bench/$b" --help > /dev/null 2>&1 && echo "  ok   bench/$b --help" || { echo "  FAIL bench/$b --help"; rc=1; }
  done
fi
exit $rc
