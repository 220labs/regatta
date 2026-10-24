---
name: autofinish
description: "Let this branch launch by itself: `/autofinish` lifts the start rules for this claude/* branch (rule C — any shape, any workflow repo, the week's pause lifted) so the launcher starts `/finish` on it after 40 idle minutes, `/autofinish now` at this turn's end, `/autofinish off` takes it back, `/autofinish <branch>` names another branch of this repo. Never lifts one of /finish's gates (it does let a branch that touches the repo's own gate files launch): /finish still runs every one, and the launcher still never starts a branch that is busy, asks the owner something, or is not pushed with its PR still WIP:."
disable-model-invocation: true
effort: medium
allowed-tools: Bash(autofinish:*), Bash(*wharf-runs/*bin/autofinish *)
---

Autofinish this branch — rule: git-workflow; the design is
the overlay's `docs/autofinish-design-2026-10-02.md` (D7, rule C in section 15). The owner typed: $ARGUMENTS

If this project has its own `/autofinish` (`.claude/skills/autofinish` or
`.claude/commands/autofinish.md`), run that instead and stop here: the project's version wins.

## 1. Run the verb

From this session's worktree, one command — the arguments as typed. `autofinish` is on the Bash
PATH while the wharf-runs plugin is enabled; where this skill is linked in by hand instead, run it
by path, `<base directory>/../../bin/autofinish`, as one path and never through `cd`.

| typed | run |
| --- | --- |
| `/autofinish` | `autofinish override` |
| `/autofinish now` | `autofinish override now` |
| `/autofinish off` | `autofinish override off` |
| `/autofinish <branch>` (and `now`/`off` before it) | `autofinish override [now\|off] <branch>` |

It writes (or removes) the marker `<git dir>/claude/autofinish`, then prints three lines: what it
set, `<repo> <branch> <verdict>`, and this Mac's switch (`armed …` or `disarmed …`). Never write
the marker by hand, and never run `autofinish arm` or `disarm` from here: arming is the owner's call,
made once for the Mac, not per branch. An exit with a message (not a claude/* worktree, no such
branch, two branches match) is the answer: relay it and stop.

A full `claude/*` branch name that no worktree of this repo carries yet is the yes at the brief
(autofinish-exclude S7): typed while the brief is written, it waits in the repo's
`<common git dir>/claude/autofinish-briefs/` and becomes rule C once a worktree carries that branch,
started `--by brief`. The yes predates the diff, so the landing re-judges it: a leak gate (the base's
`autofinish_leaks`), `in_place` or `.claude/workflow.json` in the diff holds it at a ready PR; the
judges and the hooks land. `now` is refused for an unborn branch; `off` removes it, before or after.

Who may run it is checked, not trusted: `override` refuses in an unattended session
(`CLAUDE_UNATTENDED` — a runner, any dispatch session), and inside any Claude session unless the
last prompt queued in this checkout (`<git dir>/claude/prompts.json`) is the owner's typed
`/autofinish`. The marker says `by: <owner>` (the owner's name, lower-cased), so a model never sets it on its own judgement — not
from another skill, not because a branch looks done. `autofinish arm` refuses unattended too; an
interactive session arms only on the owner's word.

## 2. Say it, branch first

Lead with the branch and the verdict exactly as printed (R17: typed in the wrong session, this is
where the owner sees it — `/autofinish off`, then `/autofinish <branch>`). Then what happens next:

- `start (C)` — it launches by itself: `now` at this turn's end; otherwise at the next sweep (every
  10 min) or session end. The runner is a fresh `/finish` in the window `finish · <topic>`, also on
  the phone; its report is the PR body.
- `wait: idle N min` — the sweep starts it once the branch has been idle 40 minutes (`now` skips
  the wait; so does ending a reply with the line in section 3).
- `skip: not pushed …` or `skip: no PR` — the turn's end pushes first (the checkpoint hook, which
  opens the `WIP:` PR on a first push), then judges again.
- any other `skip:` — the override cannot lift it (D7 lifts only the start rules: the repo's
  records list and mode, size, host, the week's pause; a commit saying it deployed needs no override since 2026-10-14: rule L launches it at once). `busy`, `asks` (a
  D-list, `**Decide:**`, a seed), a last reply that asks, moved on origin, a PR that left WIP:,
  GitHub activity since the tip: each stays a veto. Name it and what clears it; the marker stays
  until `/autofinish off`.
- `disarmed` — nothing starts on this Mac whatever the verdict: the launcher only logs it
  (`~/Library/Logs/claude-weekly/autofinish-<date>.log`). Say so in one line.

`off`: one line — the branch is back on its repo's own start rules. When the verb adds that a run
is under way, relay that line too: `off` stops the next start, not a `/finish` already running in
its window.

## 3. The closing line

The declared closing line, `<NAME>, THIS SESSION IS DONE — IT LAUNCHES BY ITSELF.` (the owner's name upper-cased
first; `hooks/common.py`'s `DECLARED_LINES`) is for a branch
the launcher will start now. End with it after `/autofinish now` when the verdict is `start (C)`,
or when its only obstacle is `not pushed` / `no PR`, which the turn's end clears. The Stop hook
judges the branch itself once it has pushed: when its verdict is not `start`, the reply is blocked
once with that verdict — end it again with the line that is true (usually the WAITING line, naming
what the owner must clear). Otherwise no closing line of this skill's: the session simply goes on.
