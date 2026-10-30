---
name: move
description: Move this session — its branch and its whole conversation — to the other Mac or to the cloud, or bring one back. `--to-home` (the dispatch host; `--to-<peer>` names a Mac `wharf-runs/ssh` lists), `--to-laptop`, `--from-<peer> <words>` (`--from-home` the dispatch host), `--from-laptop <words>`, `--to-cloud`, `--from-cloud <words | id | link>`, `--cancel`, `--check <id>`. The session left behind is marked so it cannot write; the skill never ends one — only dispatch-rc tidy ends the session in the Terminal window of a move proved running there, and closes that window.
disable-model-invocation: true
effort: medium
allowed-tools: Bash(python3 *wharf-runs/*bin/pickup *)
---

Move a session — rule: git-workflow. The owner typed: $ARGUMENTS

The engine is `move` of `bin/pickup` in this skill's module (its `--help`, section "Move" and
"The cloud"): `../../bin/pickup` from this skill's base directory. Below, `pickup` stands for
`python3 <base directory>/../../bin/pickup`, passed as one path, never through `cd`, so a skill
linked in by hand still reaches its module. The design is `teleport-design-2026-10-02.md` in the
overlay's `docs/record/`. It does
the gates, the commit and push, the fork, the arrival and the marker, and stops with exit 3
and one line when anything is unsafe. Your part: map the flag, name the branch for a
`--from`, put the one question before a `--to`, report, and close.

## 1. The flag

| typed | run | where it runs |
| --- | --- | --- |
| `--to-home`, `--to-<peer>` | `pickup move --to <peer>` (`home` is the dispatch host; `pickup` maps it) | the laptop; on the target itself the script says "this machine" and stops |
| `--to-laptop` | `pickup move --to laptop` | a peer, where it becomes `--prepare` (ssh runs laptop → peer only, D2): commit, push, a pending marker, the line for the laptop |
| `--from-<peer> <words>`, `--from-home <words>` | `pickup move '<branch>' --from <peer>` | the laptop |
| `--from-laptop <words>` | `pickup move '<branch>' --from laptop` | nowhere: on a peer the script names the `--to-home` line for the laptop, or `/pickup '<topic>' --fresh` here for the branch without the conversation; on the laptop it says "this machine" and stops. Relay it |
| `--to-cloud` | `pickup move --to cloud` | either Mac |
| `--from-cloud <words \| id \| link>` | `pickup move '<branch \| session_… \| link>' --from cloud` | either Mac |
| `--cancel` | `pickup move --cancel` | a pending move, or a cloud move `/teleport` never took |
| `--check <id>` | `pickup move --check <id>` | the fork's first reply against the source's model and effort (R2) |

A `--to` acts on this session's own branch: run it from this session's directory, no REF.
Words after the flag that are an instruction rather than a name ("…and finish the deploy")
go along as `--note '<instruction>'`; the target gets them after its orientation. Always
quote what you pass.

**Naming the branch for a `--from`.** A session id, a `session_…` id or a claude.ai/code link
is exact: pass it. Otherwise run `pickup list` and match the
words as the pickup skill's section 1 says (`../pickup/SKILL.md`) — by meaning, one clear
fit or an `AskUserQuestion`, never a guess. For `--from-cloud` the branch is the one a cloud
session pushed to; the script reads the session's id from the commit that carries its link.

## 2. Before a `--to`

If an Agent you spawned or a background task of this session is still running, say so and
wait for it or stop it first: its result would arrive in a tab the owner is about to close. The
script refuses too, when one wrote in the last 30 seconds — that is the backstop, not the check.

## 3. Run it and report

Run every `move` with a Bash `timeout` of 600000: an arrival proof waits up to 60 s and a
headless teleport up to 7 minutes, and a run killed halfway leaves the marker and the
worktree in between.

Report what it printed in two to five lines, every ✓ ⚠ and ↺ kept, the new session id
whole. Exit 3 is a refusal: quote the reason, do what it names if it is yours to do, and stop —
no closing line, this is still the working session. On a `--to HOST` that printed a new id,
add the R2 check for the target's first reply: `pickup move --check <new id>`.

A `--from` that printed a **Do this now** (the session left on the peer, idle) keeps it as a
Do-this-now block: ending a session is the owner's act (D4). Never run the line yourself.

The cloud legs wrap Claude Code's own `/teleport`. Two first-run checks are still open, both
interactive by nature. Say which one this run exercised:
- **`--to-cloud`**: does `/teleport`, typed as a reopened fork's first prompt, send the
  session to the cloud? If it only offers to pull one, the owner runs the printed `claude --cloud
  …` line in that window (a new cloud session from the pushed branch, without the conversation)
  and, if neither works, `/move --cancel` here.
- **`--from-cloud`**: does `claude -p --teleport <id>` write the local copy headless? If it
  does, the copy opens in VS Code with the model pinned. If not, the script opens a Terminal
  window running `claude --teleport <id>`, and the conversation continues there.

## 4. The closing line

Every handoff ends this session's job. The very last thing said, in upper case, so the owner can
tell a finished move from a working session. `<OWNER>, ` opens each line: the owner's name from the
core's `regatta/owner` key, upper-cased, as the core's `ADDRESS` has it (no owner configured: the line
starts at `THIS`); `<PEER>` is the target's name from `wharf-runs/ssh` and `<LAPTOP>` the laptop's from `regatta/laptop`,
upper-cased, one word each (the Stop check matches `\S+` there):

| outcome | line |
| --- | --- |
| `--to`, proved running | `✅ <OWNER>, THIS SESSION MOVED TO <PEER> — CLOSE THIS TAB. THE WORK CONTINUES THERE.` |
| `--to`, not proved | `🛑 <OWNER>, THIS SESSION MOVED TO <PEER> — CLOSE THIS TAB. THE WORK CONTINUES THERE ONCE YOU START IT: <the printed line>` |
| `--prepare` on a peer | `🛑 <OWNER>, THIS SESSION IS READY TO MOVE TO <LAPTOP> — CLOSE THIS TAB. TYPE /MOVE --FROM-<THIS HOST> '<TOPIC>' ON THE LAPTOP.` |
| `--prepare` on the laptop (the peer did not answer) | `🛑 <OWNER>, THIS SESSION WAITS TO MOVE TO <PEER> — TYPE /MOVE --TO-HOME HERE ONCE IT ANSWERS, OR /MOVE --CANCEL.` |
| `--from`, `--from-cloud` into VS Code | `✅ <OWNER>, THIS WAS ONLY THE MOVE — CLOSE THIS SESSION. THE WORK CONTINUES IN THE NEW TAB.` |
| `--from-cloud` into Terminal | `✅ <OWNER>, THIS WAS ONLY THE MOVE — CLOSE THIS SESSION. THE WORK CONTINUES IN TERMINAL.` |
| `--to-cloud` | `🛑 <OWNER>, THIS SESSION GOES TO THE CLOUD FROM THE NEW TERMINAL WINDOW — ANSWER /TELEPORT THERE, THEN CLOSE THIS TAB.` |

`--cancel` and `--check` hand nothing over: no closing line.

## Never

- End, kill or `rc-hosts --end` a session — not the source, not the one on the other Mac (D4). The one exception is not yours: once a `--to` is proved running, `dispatch-rc tidy` ends the source session in a Terminal window and closes the window once it goes idle, unless the owner typed into it since (the owner, 2026-10-08: "as long as it succeeded, I don't need to see it"; `hooks/common.py` HANDOFFS). A VS Code tab stays the owner's to close.
- Route around a refusal: no `claude --resume` of a session the script stopped on, no second
  `--to` after a marker without `--cancel`, no deleting `teleported.json` by hand.
- Edit after a `--to` succeeded: this worktree refuses writes, and the work goes on there.
- Read `.env` or a token: the script reads what it needs; a cloud session's id comes from git.
