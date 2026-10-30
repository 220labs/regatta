---
name: evacuate
description: Leave the session so it can be closed now and picked up cold later — test state clean, nothing live that main lacks, what helps other agents merged, the rest written to TODO.md — then a verdict — close, leave open, or nothing here.
disable-model-invocation: true
---

Evacuate this session — rule: git-workflow for the mechanics it reuses. $ARGUMENTS

**Project override first.** If the project has its own `/evacuate`
(`.claude/commands/evacuate.md` or `.claude/skills/evacuate/SKILL.md`), read it and follow it
instead. Otherwise read the project's `## Session contract` (in `AGENTS.md`, else `CLAUDE.md`)
— `/finish` explains its fields.

Lighter than `/finish`: open items are allowed here, they become TODOs; history curation is
done only if the branch is coherent enough to launch. The one hard rule is the same: **a live
system must not be left running something `main` does not have.** Work through every step;
skip none silently. Say what each found in one line.

## 1. Nothing still running

- Background agents: none still working (a pending task notification means wait or note).
- Nothing mid-deploy, nothing half-applied, no test that left something disabled.

## 2. Test and live state is clean

- Run the contract's `check:`. Failures caused by *another* open worktree (its live-only
  leftovers) are noted, not fixed here.
- If the contract names a `live:` system: its error log shows nothing new from what this
  session deployed; every injected or seeded test value is restored.
- Anything real this session moved for a test is back where it was, or the owner is told.

## 3. Git ≠ live — reconcile what was deployed

Skip if the contract says `live: none`. Otherwise list what this session deployed
(checkpoint bodies carry `Deployed:`; or the contract's drift command against `main`'s
tree). Each deployed item must be on `main` by the end of this command, **or** reverted on
the live system, **or** the exact revert is TODO #1.

## 4. Merge what helps others

- Branch coherent (one topic, check passes, docs updated)? Squash to one curated commit
  (`git branch -f <branch>-raw HEAD`, `git reset --soft main`, commit with a real message
  and the Co-Authored-By trailer, `git diff <branch>-raw HEAD` must be empty), rebase onto
  `main` if it moved (set `.git/claude/finishing` for the rewrite, remove it after), then
  `git merge --ff-only` from the primary checkout. Never push.
- Not coherent? Leave a `wip:` commit whose body is the hand-off note (what works, what
  doesn't, what was deployed), and a TODO pointing at the branch.

## 5. Nothing blocks the next agent

- `ls "$(git rev-parse --git-dir)/claude/"` — no `finishing` marker left; the owner lock
  frees on exit.
- `git worktree list` — say which other worktrees are open and whether this branch and any
  of them both touched the project's `CLAUDE.md` / `AGENTS.md` (the files most likely to
  conflict).
- Anything a fresh session would trip on is either fixed or the first TODO. If other live
  sessions need it *this week*, `/share` it too.

## 6. TODOs and learnings

- Run the `/todo` honesty check: add what is left, delete what is done, keep ≤ 5 where
  possible. A decision only the owner can make is `**Decide:**`; a physical check is
  `**Physical:**`. A follow-up that would earn a session of its own is `/todo handoff`, not a
  TODO line: a branch `/pickup` starts fresh, its brief written while the context is here.
- Anything the next session needs to *know* (not do) goes into a doc, the project's
  `CLAUDE.md`, or `/promote` — never only into the TODO or memory. A long session gets a
  digest doc (`docs/<topic>-<date>.md`) the owner can read cold; the TODO then points at it.

## 7. Verdict and hand-off

One of:

- **CLOSE** — everything that helps others is on `main`, live matches, TODOs recorded.
  Print the TODO list verbatim.
- **LEAVE OPEN** — mid-task with context that would be expensive to rebuild from the repo
  alone. Say exactly what that context is; if it can be written down in ten lines, write it
  down and CLOSE instead.
- **NOTHING HERE** — no TODOs, nothing deployed, nothing to merge. Close it.

Then the worktree — **always leave it with `ExitWorktree`**: `remove` if its branch equals
`main` after step 4, `keep` otherwise (and name the branch). Never close a session while it
is still inside a worktree: exiting is what moves the transcript back to the repo's project
directory, and one left inside is invisible to the VS Code sidebar and to `claude -r`
short of `Ctrl+A` (the owner, 2026-09-21). End with the upper-case line from
`/finish`: `REALLY DONE` when every step above is clean, `READ THE NOTE ABOVE` when
anything is owed (each opened by ✅) — or, when only the owner can make the next move, `🛑 <OWNER>, THIS SESSION IS WAITING
FOR YOU — <what, in one line>` (`<OWNER>`: the core's `regatta/owner`, upper-cased; with none
the line starts at `THIS`). LEAVE OPEN takes none: the session is not finished. The Stop
hook blocks any other ending once.
