#!/usr/bin/env bash
# pr stuck: real scratch git histories, strict REST answers, and the real lander spend parser/store.
# No network, launch, fetch or push. The launcher runs this through wharf's check.
set -eu
unset CLAUDE_CODE_SESSION_ID CLAUDE_UNATTENDED REGATTA_UNATTENDED CLAUDE_CODE_DISABLE_BACKGROUND_TASKS
unset CLAUDE_REPOS_JSON REGATTA_HOME REGATTA_LEGACY
for v in $(env | sed -nE 's/^((DISPATCH|RUN_SEED|SKIPPER|HELM|AUTOFINISH)_[A-Za-z0-9_]*)=.*/\1/p'); do unset "$v"; done
D="$(cd "$(dirname "$0")" && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export REGATTA_CONFIG="$T/config" CLAUDE_CONFIG_DIR="$T/claude-config"
export AUTOFINISH_STATE_DIR="$T/state" GIT_CONFIG_GLOBAL="$T/gitconfig" GIT_CONFIG_NOSYSTEM=1
export PR_RESTACK_WAIT=0 REGATTA_LAPTOP=laptop
printf '[user]\n\tname = t\n\temail = t@t\n[init]\n\tdefaultBranch = main\n' > "$GIT_CONFIG_GLOBAL"
python3 -B "$D/stuck_cases.py"
