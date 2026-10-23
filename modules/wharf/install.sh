#!/bin/sh
# wharf's shell face. Nothing is installed or removed outside the plugin: its hooks are wired by
# a settings file's `hooks` block, which this prints (--hooks) and never writes — the plugin
# carries no hooks/hooks.json yet, so a Mac whose overlay wires them never runs one twice (C4).
# --check: whether the core and each optional peer are found (keel, autofinish, pickup,
# usage-report, tier_check, claude-settings, sheep, trust-projects, rc-hosts, knowledge-commit,
# helmlib (planlib before rename S5)), and what is lost without each.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
# --hooks names the main checkout's files, never a linked worktree's: /finish removes a worktree,
# and a hook path that no longer exists is exit 2 — on UserPromptSubmit, every prompt erased (R1).
common=$(git -C "$here" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
[ -n "$common" ] && [ "$(basename "$common")" = .git ] && here="$(dirname "$common")/modules/wharf"
case "${1:-}" in
  --check)
    python3 - "$here" <<'PY'
import sys
sys.path.insert(0, sys.argv[1] + "/lib")
import core_path
h = core_path.hooks()
print("core:            %s" % (h or "MISSING — install the regatta plugin, or name a clone in the config dir's home file"))
if not h:
    sys.exit(1)
sys.path.insert(0, h)
import common
for name, lost in (("keel", "no D-list page and no hand-over-line block at Stop (G4); no D-list read per branch (G5)"),
                   ("autofinish", "no launcher child at Stop and SessionEnd (G1)"),
                   ("pickup", "the probably-launched review line names the bare `pickup` (G3)"),
                   ("usage-report", "review-gate logs in the core's log dir; no account record at session start (G7)"),
                   ("tier_check.py", "review-gate plans at the default tier (G7)"),
                   ("claude-settings", "no declared-settings note at session start (G8)"),
                   ("sheep", "no sessionpipe note at session start"),
                   ("trust-projects", "repos --clone trusts no new repo; each asks once (G8)"),
                   ("rc-hosts", "repos --clone loads no Remote Control host (G2)"),
                   ("knowledge-commit", "github-repo prints the registry line to add by hand (G6)"),
                   ("helmlib.py", "session_status reads the guarded list from the registry alone (G32)")):
    p = common.tool(name) or (name == "helmlib.py" and common.tool("planlib.py")) or None   # as session_status reads it
    print("%-16s %s" % (name + ":", p or "not installed — " + lost))
PY
    ;;
  --hooks)
    python3 - "$here" <<'PY'
import json, sys
h = sys.argv[1] + "/hooks/"
c = lambda s: {"type": "command", "command": 'python3 "%s%s"' % (h, s)}
print(json.dumps({"hooks": {
    "SessionStart": [{"hooks": [c("sync.py")]}],
    "UserPromptSubmit": [{"hooks": [c("checkpoint.py")]}],
    "PreToolUse": [{"matcher": "Edit|Write|NotebookEdit|Bash", "hooks": [c("checkpoint.py")]}],
    "PermissionRequest": [{"matcher": "EnterWorktree|ExitWorktree", "hooks": [c("worktree_allow.py")]}],
    "Stop": [{"hooks": [c("checkpoint.py")]}],
    "SessionEnd": [{"hooks": [c("checkpoint.py")]}]}}, indent=2))
PY
    ;;
  --remove|"") echo "wharf: nothing to install or remove outside the plugin (install.sh --hooks prints the settings block to merge)" ;;
  *) echo "usage: install.sh [--check | --hooks | --remove]" >&2; exit 2 ;;
esac
