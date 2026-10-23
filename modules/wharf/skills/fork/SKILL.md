---
name: fork
description: Fork this session — a copy of the conversation so far under a new session id, ready to open from the Claude Code side panel's session list; this session carries on untouched
disable-model-invocation: true
allowed-tools: Bash(python3 *wharf/*bin/fork_claude_session.py*)
---

The fork has already been written — the shell line below ran before this prompt reached
you, using this session's own id, so there is nothing to pick and nothing to run:

!`python3 "${CLAUDE_SKILL_DIR}/../../bin/fork_claude_session.py" --session "$CLAUDE_CODE_SESSION_ID" $ARGUMENTS`

Reply with **one line**: the fork's title (from the output above) and that it is in the
Claude Code session list now (search for `fork ·` if live sessions crowd it out — the list
sorts by file time). If the line above failed, give the error verbatim; the most likely
cause is an empty `CLAUDE_CODE_SESSION_ID`, in which case run
`python3 <this skill's base directory>/../../bin/fork_claude_session.py` yourself (one path,
never through `cd`, so a linked skill still reaches its module) — with no `--session` it
forks the session the owner last typed in.

Then carry on with whatever you were doing before `/fork` — do not start new work, and do
not summarize the session for the fork; it already has the full transcript.

The fork is a transcript file, not a process: nothing runs until it is opened. In a project
on the git workflow it starts in the main checkout, where the checkpoint hook denies writes,
so it creates its own worktree — by design (one writer per worktree). `/fork --terminal`
opens it in a new Terminal window instead of leaving it for the side panel.
