#!/usr/bin/env bash
# pitch: the renders' checker and builder (renders S1). make_failing.py writes one failing root per
# rule into a temp dir (never committed), then pitch_cases.py runs every case: the passing root rule
# by rule, each failing root firing exactly its rule, the rules module's controls, and the CLI.
# Stdlib Python 3.9 and bash only; no network, no pytest. Any OS.
#   bash modules/sextant/tests/pitch.sh
set -u
D="$(cd "$(dirname "$0")/.." && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export PYTHONDONTWRITEBYTECODE=1
python3 -I "$D/tests/fixtures/pitch/make_failing.py" "$T/failing" >/dev/null || { echo "  FAIL make_failing.py wrote no failing roots"; exit 1; }
python3 -I "$D/tests/pitch_cases.py" "$T/failing"
