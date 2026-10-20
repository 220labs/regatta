#!/usr/bin/env bash
# plumb's check: crew-report's suite (synthetic transcripts under a scratch HOME; no network), then
# the suites of the files B8 moved in — usage-report (with every plumb file's no-peer cases) and
# interruptions — and the benches' own tests and `--help` (G37). The B8 files are private until
# their scrub (not on .helloworld/allowlist.txt), so a published copy has crew-report alone: each
# suite whose file is absent is skipped in one line. Their cases also read peers that are still the
# overlay's (lighthouse's publish, wharf's fork_claude_session.py and session_status.py, aurora's
# week-digest, keel's memo) through the core's tool(), so without an overlay checkout (the config
# dir's `legacy`; CI clones regatta alone) they are skipped in one line too: the Macs run them (the
# check line), and the overlay's CI runs the corpus test alone. A core that refuses to load fails.
#   bash modules/plumb/tests/check.sh
set -u
D="$(cd "$(dirname "$0")" && pwd)"
M="$(cd "$D/.." && pwd)"
rc=0
overlay=$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import find_core; sys.path.insert(0, find_core.hooks()); import common
r = common.legacy_root(); print(r if r and r.is_dir() else "")' "$M/lib") \
  || { echo "FAIL: the core does not load here, so no overlay can be named (its line above)"; rc=1; overlay=""; }
for s in crew-report usage-report interruptions; do
  echo "== $s"
  if [ ! -f "$D/$s.sh" ]; then echo "  skip: $s not in this copy (private until its scrub)"; continue; fi
  if [ "$s" != crew-report ] && [ -z "$overlay" ]; then echo "  skip: $s reads the overlay's peers, and no overlay checkout is named here"; continue; fi
  bash "$D/$s.sh" || rc=1
done
if [ -d "$M/bench" ] && [ -z "$overlay" ]; then
  echo "== bench"; echo "  skip: the benches load the overlay's peers, and no overlay checkout is named here"
elif [ -d "$M/bench" ]; then
  echo "== bench"
  bash "$M/bench/decisions/test_corpus.sh" > "${TMPDIR:-/tmp}/plumb-corpus.$$" 2>&1 \
    && echo "  ok   decisions/test_corpus.sh" || { cat "${TMPDIR:-/tmp}/plumb-corpus.$$"; rc=1; }
  rm -f "${TMPDIR:-/tmp}/plumb-corpus.$$"
  (cd "$M/bench/sessions" && python3 test_collect.py > /dev/null 2>&1) \
    && echo "  ok   sessions/test_collect.py" || { echo "  FAIL sessions/test_collect.py"; rc=1; }
  # G37: each bench with arguments that loads a peer starts and reads them (on a Mac with the
  # overlay; the no-peer lines are tests/usage-report.sh's). jev.py and arms.py load jev lazily,
  # sheet.py on use, so for those three this proves start-up only; docs.py has no --help.
  for b in b2.py decisions/jev.py sessions/arms.py sessions/collect.py sessions/score.py decisions/corpus.py sessions/sheet.py; do
    python3 "$M/bench/$b" --help > /dev/null 2>&1 && echo "  ok   bench/$b --help" || { echo "  FAIL bench/$b --help"; rc=1; }
  done
fi
exit $rc
