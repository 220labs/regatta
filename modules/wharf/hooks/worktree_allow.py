#!/usr/bin/env python3
"""PermissionRequest hook: EnterWorktree and ExitWorktree never ask the owner.

The owner, 2026-10-06, rejecting the prompt for about the dozenth time: "I want to always
enterworktree when you need to, and I want you to never ask again. No session on any of my
devices and accounts. Ever." And on 2026-10-10, when it asked again because this hook had
never been merged: "EnterWorkTree should never ask, ever. I thought we had that as an enforcement,
what's wrong? Fix it!"

Why a hook and not the allow rule (read in Claude Code 2.1.292's source, then probed headless,
lessons/claude-code.md): EnterWorktree's own checkPermissions allows a `path` only when it lies
under the *current* repo's `.claude/worktrees/`. Anything else — a sibling repo's worktree, or
entry from ~/projects, which is no repo — returns `ask` as a safety check with
`classifierApprovable: false`. That outranks `permissions.allow: ["EnterWorktree"]`, auto mode
and a PreToolUse `allow` (all three probed: still asked). A PermissionRequest hook's `allow` is
the one answer it takes.

What it approves, and nothing else: EnterWorktree with no `path` (a new worktree by name, which
the tool allows anyway), ExitWorktree unless it removes with discard_changes, and EnterWorktree
into a directory that resolves inside some git repo's `.claude/worktrees/` — this repo's or a
sibling's. The tool's "current repo" follows the shell's cwd, so re-entering by path the very
worktree a session is isolated in asks too once a `cd` has taken the shell into another repo's
worktree (seen 2026-10-10); this rule never reads the cwd, so that case gets no prompt either —
the tool then refuses it as an error, and `cd` back is the way (probed, lessons/claude-code.md).
Anything else gets no answer,
so Claude Code asks as before: the safety check exists because entering moves write access and
loads that project's CLAUDE.md and settings, and a worktree under `.claude/worktrees/` is a place
one of the owner's sessions made. Whether the tool then accepts the path (it must be a registered
worktree of the session's repo, or of one nested in the start directory) stays its own check.

Installed by bootstrap.sh --hooks on every account dir; --check and `account doctor` fail
without it. Python 3.9, stdlib only, never exits non-zero, silent unless it approves.
"""
import json
import os
import sys

TOOLS = ("EnterWorktree", "ExitWorktree")
MARK = os.sep + os.path.join(".claude", "worktrees") + os.sep


def approvable(tool, tool_input, cwd=None):
    if tool not in TOOLS or not isinstance(tool_input, dict):
        return False
    if tool == "ExitWorktree":
        # remove with discard_changes deletes uncommitted files and unmerged commits; that one
        # is left to auto mode or a prompt (rules/git-workflow.md: never a deletion; review 2026-10-07)
        return not (tool_input.get("action") == "remove" and tool_input.get("discard_changes"))
    path = tool_input.get("path")
    if not path:
        return True
    path = os.path.expanduser(str(path))
    if not os.path.isabs(path) and cwd:  # as the session resolves it, not this process
        path = os.path.join(str(cwd), path)
    real = os.path.realpath(path)
    i = real.find(MARK)
    rest = real[i + len(MARK):] if i > 0 else ""
    if not rest or os.sep in rest:
        return False
    # the repo that owns .claude/worktrees/ is a real checkout, and the target is one of its
    # worktrees (a `.git` file), not a plain directory or a subdirectory of one (review 2026-10-10)
    return os.path.exists(os.path.join(real[:i], ".git")) and os.path.isfile(os.path.join(real, ".git"))


def main():
    try:
        data = json.load(sys.stdin)
        if approvable(data.get("tool_name"), data.get("tool_input"), data.get("cwd")):
            print(json.dumps({"hookSpecificOutput": {
                "hookEventName": "PermissionRequest",
                "decision": {"behavior": "allow"},
            }}))
    except Exception:
        pass


if __name__ == "__main__":
    main()
    sys.exit(0)
