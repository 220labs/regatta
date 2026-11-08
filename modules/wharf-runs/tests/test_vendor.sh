#!/usr/bin/env bash
# Scratch HOME, local git origins, and vendor stand-ins that validate real CLI
# flags. Never starts a real vendor, Claude, launchd, or a network connection.
set -eu
B="$(cd "$(dirname "$0")/../bin" && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export HOME="$T/home" REGATTA_CONFIG="$T/config" CODEX_HOME="$T/codex"
export PYTHONPYCACHEPREFIX="$T/pycache"
mkdir -p "$HOME" "$REGATTA_CONFIG/wharf-runs"
python3 "$(dirname "$0")/test_vendor.py" "$B" "$T" "$@"
