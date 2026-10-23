# Sourced by the suites before HOME moves: `fixture_config <dir>` makes <dir> the suite's own regatta
# config dir. Never the caller's: a Mac's ~/.config/regatta is that login's live state (its laptop key,
# owner, overlay checkout), and a CI job hands an empty one (REGATTA_CONFIG=$(mktemp -d)). On the build
# Mac's runner the empty dir made `regatta/laptop` its default, so the suites' laptop was no longer
# the laptop and the owner went unnamed — 136 cases across four suites (suites-host, 2026-10-20); in
# a plain shell they passed only because the real file happened to agree.
# The cases assume one Mac pair (`laptop` the laptop, `buildbox` the other, where runs are dispatched;
# each suite's own *_HOST pin says which one is "here") and one owner, Sam. Every name is synthetic:
# the module is public, and a suite pinning a real host or person would publish it. `home` is this checkout, the code under test (pickup's
# peer side finds wharf's checkpoint.py through it), never the main checkout the real file names.
# No `legacy` (nor REGATTA_LEGACY): a peer is found in modules/*/ alone, as in CI; a case about an
# installed overlay names a stand-in through REGATTA_LEGACY (test_dispatch's real lookup).
# SUITE_OVERLAY is the caller's overlay checkout, read before the switch, for the cases whose input
# is a file of the overlay's source (claude-host.c, bootstrap.sh): the suite reads it, a tool under
# test never does; "" where the caller has none (CI), and those cases say they are skipped.
# GIT_CONFIG_GLOBAL goes too: set, it would outlive the HOME move and every suite would write the
# caller's file; unset, `git config --global` is the scratch HOME's .gitconfig.
fixture_config() {
  SUITE_OVERLAY="${REGATTA_LEGACY:-$(head -1 "${REGATTA_CONFIG:-$HOME/.config/regatta}/legacy" 2>/dev/null)}"
  case "$SUITE_OVERLAY" in "~"*) SUITE_OVERLAY="$HOME${SUITE_OVERLAY#\~}";; esac
  [ -d "$SUITE_OVERLAY" ] || SUITE_OVERLAY=""
  export SUITE_OVERLAY REGATTA_CONFIG="$1"
  mkdir -p "$1/regatta"
  (cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P) > "$1/home"
  echo laptop > "$1/regatta/laptop"
  echo Sam > "$1/regatta/owner"
  mkdir -p "$1/wharf-runs"
  echo buildbox:buildbox-ssh > "$1/wharf-runs/ssh"
  echo buildbox > "$1/wharf-runs/dispatch-host"
  echo org.example.claude > "$1/wharf-runs/label-prefix"
  unset REGATTA_LAPTOP REGATTA_HOME REGATTA_LEGACY GIT_CONFIG_GLOBAL
  # This Mac's real memory never decides a case: every dispatch start asks bin/headroom, so each suite
  # gets a calm reading, and a case about memory sets its own (headroom, 2026-10-22)
  unset HEADROOM_HOST HEADROOM_OS HEADROOM_PROC HEADROOM_SAMPLE_S
  export HEADROOM_SAMPLE="60 0 0"
}
