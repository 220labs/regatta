---
name: todo
description: Show, add, finish or defer items in TODO.md — the project's small, honest list of what a fresh session must pick up. Keeps it short (5 comfortable, 10 hard cap) and every item actionable from cold. Use it too the moment a session finds follow-up work that belongs to another session (another repo, its own design, context that would drag along) — `/todo handoff` hands it over as a branch dispatch starts at once.
effort: medium
---

Manage `TODO.md` at the repo root. $ARGUMENTS

If the project has its own `/todo` (`.claude/commands/todo.md` or
`.claude/skills/todo/SKILL.md`), read it and follow it instead of this one.

`TODO.md` is the hand-off list between sessions: what a session that starts cold, with no
transcript, needs to know is still owed. It is not a backlog, not a roadmap and not a place
for learnings — those go in `docs/`, the project's `CLAUDE.md`, or `/promote`. Read it at the
start of any session the owner opens with "pick up", "continue" or "what's left". A project with
no `TODO.md` gets one on the first `add`.

## Forms

- `/todo` — print the list, then the honesty check below.
- `/todo add <text>` — append one item. Refuse if the list is at 10; warn at 6+. An item only a
  person can do carries its owner, `@<person>` (a name helm's board knows): it is then a card in that person's column
  of Helm's board (`bin/helm board`, docs/session-asks-2026-10-09.md section 3); an item
  with no tag is a session's and stays off the board.
- `/todo done <n>` — **delete** the item (git history is the record; no ticked ghosts).
- `/todo defer <n> <doc path>` — move the item's substance into that doc (create a section
  if needed) and replace the item with nothing. Use this when an item has grown past one
  session's work or is really a design question.
- `/todo handoff <topic> — <task>` — a follow-up that earns a session of its own, handed over
  as a branch the next session starts from (below).

## A follow-up found mid-session: here, handoff, or a line

Ask in this order, the moment the work turns up (docs/record/followup-handoff-2026-09-29.md):

1. **Does this branch need it before it can finish?** Then it is not a follow-up: do it here,
   or fan it out (the rules on working with the owner, "Parallel agents"). The only case for a subagent:
   a subagent ends with this session and cannot write outside this worktree.
2. **Would it earn a session name?** Another repo; its own design or more than about an hour;
   context that would have to be explained again; or it would drag this session's along.
   → **hand it off now**, while the evidence is fresh.
3. Otherwise a **TODO line** (`add`), which any later session does in passing.

Never a promise in chat ("I'll report when the ceiling is in"): nothing wakes this session to
keep it. Work that waits on something later is one of the three above (D6, A3, 2026-10-04).

**Handing off.** Write the brief into the scratchpad — at most 60 lines, 4,000 characters, these
headings, absolute paths:

```
# <topic> — handoff from <repo>: <this session's topic>, <date>
Task: <one sentence; becomes the branch's first prompt>
Tier: <Opus 5.5 high | Fable 5.1 high | Opus 5.5 medium>, per the rules' tier table
Why: <the finding, with evidence — file:line, commit, command and what it printed>
Start here: <≤ 5 files or commands>
Done means: <the check that proves it — a test, a diff, a printed line>
Not this: <what it must leave alone, and why>
Steps: <S3, S4> of <docs/<course doc>.md>   (only when it builds steps of a Course doc's Action plan)
```

The `Steps:` line is what `/finish` and autofinish read (`keel landing`, entry D6-A): the branch
does not launch while one of those steps is open, so the build marks each one done itself.

A handoff started from a session that keeps a ship (`bin/helm ship`) is a task in it: add it with
`bin/helm task <ship> <topic> --branch <branch> --owns <path>…` before `dispatch`, so the run's
reports (`bin/helm report`) go to that task and its asks relay to this session.

**Where the tools are.** A bare tool name in a command below is a path: where the regatta
config dir holds a `legacy` file (an overlay is installed), `<its first line>/bin/<name>` —
the shims the overlay's allow rules name, so an unattended run is never denied its own step
— else the module's file, which `regatta which <name>` prints (`regatta` is the core's
`bin/regatta`, on PATH in a plugin install).

Then `pickup seed <topic> --file <brief> --no-start` (`--repo
~/projects/<repo>` for another repo). It commits the brief to a new `claude/*` branch from local
`main` and pushes it — with the handoff as a one-block ship beside it, `docs/blueprints/<date>-<topic>.md`
(`provider: claude-code`, the brief as its section; wharf-on-orca S5): the brief is still what
`pickup` and `dispatch` read, the blueprint is what `bin/wharf check` and a later `wharf apply` read, and
the seed says so when a brief does not make a valid one (it keeps going without). Then start it yourself — nobody pastes it (the owner, 2026-10-04: "I don't have
time to copy-paste prompts for you"):

```
dispatch '<branch>' --next [--repo ~/projects/<repo>] [--model <the Tier line's> --effort <its>]
```

with a Bash timeout of 300000: a visible session (Remote Control, screen run-<repo>-<topic>, never
headless) **on the Mac dispatch picks for unattended runs** within two minutes — from the laptop too; the laptop only when that Mac does
not answer — confirmed from its log over ssh (dispatch's header, Where; the owner, 2026-10-13). Never a
pre-filled VS Code tab: dispatch is the default. dispatch refuses a chain past five runs, a full run
cap, and an unattended run's `--next` on the brief it started from: then end naming what it waits
on. The only other exceptions: the brief names a precondition — an answer from the owner, the owner's
identity, something to wait for — or dispatch refuses the repo (its contract is not `physical:
none`). A precondition: nothing starts, and the reply says what it waits on. A refused repo: `pickup
open '<branch>' --fresh` opens the pre-filled tab, the one place one is left. End the turn with one line:
`Follow-up handed off: <topic> — <branch> (<repo>); dispatch started it on <host>, log <path>` or
`… not dispatched, waits on <what>; start it with dispatch '<branch>' --next
--repo ~/projects/<repo>` (in a refused repo: `/pickup '<branch>' --fresh` in a <repo> window) — the
full name: a bare topic can match another branch.
A `--next` from a run that is a block of a ship (its `DISPATCH_SHIP` (or `DISPATCH_PLAN`) and `DISPATCH_TASK` name a block
with a successor in the plan's blueprint) starts nothing: it names the blueprint's next block and
leaves the start to `wharf apply`. Any other `--next` — a handoff's seed, the ship's last block — runs as before.
Only a repo on the worktree workflow takes a handoff; elsewhere it is a TODO line or a doc. A handoff is recorded; never a TODO line for it as well.

## Shape of an item

One numbered line, at most two: **what**, then *where the context lives* (a doc section, a
commit, a branch, a file:line). It must be actionable by a session with no memory of this
one. Bad: "fix the dimmer". Good: "**Dimmer turn-on floor** — pick the floor, then two
lines in `counter_dim.yaml` + a test. Context: `docs/audit-2026-09-16.md` section 3.1."

A TODO line is work under about an hour in this repo; anything that would earn a session
name is a handoff (above).

An item that is a *decision only the owner can make* says so up front (`**Decide:**`) and ends
with its default and a date: `Applies <recommendation> on <the Sunday after next> unless
overruled.` `/embark` applies every one whose date has passed and that the owner left standing
(weekly 2026-09-29, Q5: two Decide items waited 15 days with a recommendation attached).
An item that is a *physical check* says so (`**Physical:**`); one only the owner's hands can
do, `**the owner:**`. Anything else is work.

## The honesty check (run on every `/todo`)

1. **Length.** ≤ 5: fine. 6–10: say so, and propose which items to defer into a doc or
   merge into one. > 10: refuse to add; something must be finished or deferred first.
2. **Staleness.** For each item, is it still true? A TODO to deploy something the
   project's drift command (session contract, `live:`) now reports in sync is done — delete
   it. A TODO for a file that no longer exists is stale — say so.
3. **Actionability.** Would a cold session know where to start? If not, add the pointer
   or defer it.
4. **Duplication.** If the substance is already a rule in `CLAUDE.md` or a section in a
   doc, the TODO is at most a one-line pointer to it.

Report the list and the check's findings in under 15 lines. Do not restate the file's
rules back to the user.
