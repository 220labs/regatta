#!/usr/bin/env bash
# The nightly reader and the workflow, offline and with no caller HOME or config.
set -eu
D="$(cd "$(dirname "$0")" && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/home" "$T/config/regatta" "$T/config/helm"
printf 'Sam\n' > "$T/config/regatta/owner"
printf 'laptop\n' > "$T/config/regatta/laptop"
printf 'transcripts\n' > "$T/config/regatta/guarded"
printf 'acme/logbook\n' > "$T/config/helm/logbook-repo"
printf '@should-not-be-mentioned\n' > "$T/config/helm/mention"
printf '{"repos": {}, "scopes": {}}\n' > "$T/repos.json"
env -i PATH="$PATH" HOME="$T/home" TMPDIR="$T" REGATTA_CONFIG="$T/config" \
  CLAUDE_REPOS_JSON="$T/repos.json" PYTHONDONTWRITEBYTECODE=1 \
  python3 "$D/main_check_cases.py"
