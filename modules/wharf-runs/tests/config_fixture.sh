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
# No overlay marker: a peer is found in modules/*/ alone, as in CI; a case about an installed overlay
# writes a stand-in's marker into a config dir of its own (test_dispatch's real lookup).
# SUITE_OVERLAY is the caller's overlay checkout, read before the switch, for the cases whose input
# is a file of the overlay's source (claude-host.c, bootstrap.sh): the suite reads it, a tool under
# test never does; "" where the caller has none (CI), and those cases say they are skipped.
# GIT_CONFIG_GLOBAL is replaced with a file in the fixture: it survives a later HOME move without
# reading or writing the caller's identity (Linux cannot guess an email from its hostname).

dateat() { date -r "$1" "$2" 2>/dev/null || date -d "@$1" "$2"; }
sedi() { local f="${!#}"; sed -i.bak "$@" && rm -f "$f.bak"; }
days_from_now() {
  python3 -c 'import datetime, sys; print((datetime.date.today() + datetime.timedelta(days=int(sys.argv[1]))).isoformat())' "$1"
}
plistget() {   # FILE KEY: JSON, compact so array assertions work identically on both OSes
  python3 -c 'import json, plistlib, sys
with open(sys.argv[1], "rb") as f: d = plistlib.load(f)
print(json.dumps(d[sys.argv[2]], separators=(",", ":")))' "$1" "$2"
}
fixture_gitconfig() {
  printf '[user]\n\tname = Test\n\temail = t@t\n[init]\n\tdefaultBranch = main\n' > "$1"
  export GIT_CONFIG_GLOBAL="$1"
}
require_process_probe() {   # SUITE: process assertions must not compare two empty ps answers
  local start
  if start="$(TZ=UTC LC_ALL=C ps -o lstart= -p "$$" 2>/dev/null)" && [ -n "$start" ]; then return 0; fi
  echo "$1: cannot read this test process with ps; process inspection is required" >&2
  return 2
}
fixture_config() {
  SUITE_OVERLAY="$(head -1 "${REGATTA_CONFIG:-$HOME/.config/regatta}/regatta/overlay" 2>/dev/null)"
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
  # no detached `hosts sample` from a case's claim or sweep (dispatch-queue's sample_soon): it would push a
  # hosts row to the case's queue home and outlive the suite; lighthouse's tests/hosts.sh runs the sampler
  echo off > "$1/wharf-runs/hosts-sample"
  unset REGATTA_LAPTOP REGATTA_HOME REGATTA_LEGACY GIT_CONFIG_GLOBAL
  fixture_gitconfig "$1/gitconfig"
  # This Mac's real memory never decides a case: every dispatch start asks bin/headroom, so each suite
  # gets a calm reading, and a case about memory sets its own (headroom, 2026-10-22)
  unset HEADROOM_HOST HEADROOM_OS HEADROOM_PROC HEADROOM_SAMPLE_S
  export HEADROOM_SAMPLE="60 0 0"
}
fixture_finish_ready() {   # [LOGIN_DIR…]: this host reads as one prepared to land, by stand-ins
  # Off macOS a host claims a finish only once finish_capability.py finds the autofinish schedule loaded, the
  # publish gate's word list and /finish in every login dir (dispatch-queue's builtin_met); a Mac keeps its grant.
  # The queue suites' finish cases would otherwise judge the machine they run on: four failed on GitHub's ubuntu
  # (#500), and dozens on a node with a schedule of its own. A scheduler that says loaded, a one-word list and the
  # skill in the moved HOME's .claude and each LOGIN_DIR a case registers make every host judge as a Mac does (mac-share-speed,
  # 2026-11-06). Call it after HOME moves. Readiness itself is test_finish_capable's, with stand-ins of its own.
  local d="$REGATTA_CONFIG/finish-ready" l
  mkdir -p "$d"
  printf '#!/bin/sh\n[ "$1" = print ] || exit 64\nexit 0\n' > "$d/launchctl"; chmod +x "$d/launchctl"
  printf 'zz-fixture-word\n' > "$d/wordlist.txt"
  for l in "$HOME"/.claude "$@"; do mkdir -p "$l/skills/finish"; : > "$l/skills/finish/SKILL.md"; done
  export WHARF_RUNS_LAUNCHCTL="$d/launchctl" HELLOWORLD_WORDLIST="$d/wordlist.txt"
}
