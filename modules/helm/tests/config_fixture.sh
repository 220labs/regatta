# Sourced by helm's suites before HOME moves: `fixture_config <dir>` makes <dir> the suite's own
# regatta config dir (wharf-runs' tests/config_fixture.sh is the pattern). Never the caller's: a
# Mac's ~/.config/regatta is that login's live state, and a CI job hands an empty one
# (REGATTA_CONFIG=$(mktemp -d)). The cases assume one synthetic setup: the owner Sam, a second
# person Alex (`helm/people`), the laptop `laptop` and one peer `buildbox` it reads over ssh
# (`wharf-runs/ssh`), and `transcripts` the guarded repo — the one name keel's gate keeps beside the
# config's list, so the cases hold before and after keel's scrub. `home` is this checkout, the code
# under test. No overlay marker: a peer is found in modules/*/ alone, as in CI.
# SUITE_OVERLAY is the caller's overlay checkout, read before the switch, for a case whose input is
# the overlay's own shim; "" where the caller has none (CI), and such a case says it is skipped.
fixture_config() {
  SUITE_OVERLAY="$(head -1 "${REGATTA_CONFIG:-$HOME/.config/regatta}/regatta/overlay" 2>/dev/null)"
  case "$SUITE_OVERLAY" in "~"*) SUITE_OVERLAY="$HOME${SUITE_OVERLAY#\~}";; esac
  [ -d "$SUITE_OVERLAY" ] || SUITE_OVERLAY=""
  export SUITE_OVERLAY REGATTA_CONFIG="$1"
  mkdir -p "$1/regatta" "$1/helm" "$1/wharf-runs"
  (cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P) > "$1/home"
  echo laptop > "$1/regatta/laptop"
  echo Sam > "$1/regatta/owner"
  echo transcripts > "$1/regatta/guarded"
  printf 'Sam\nAlex\n' > "$1/helm/people"
  echo buildbox:buildbox-ssh > "$1/wharf-runs/ssh"
  unset REGATTA_LAPTOP CLAUDE_REPOS_JSON
  # a dispatched run's own DISPATCH_* (its manager, ship, task) would reach a case that asserts none is
  # handed down (test_helm's skipper start): the suite is run from such runs, so they go here
  for v in $(env | sed -n 's/^\(DISPATCH_[A-Za-z0-9_]*\)=.*/\1/p'); do unset "$v"; done
}
