---
name: promote
description: Move one learning up a layer, now — from a project, a memory, a chat or the bulletin into the shared rules, lessons or the owner's profile. Routes it by the one-home table, updates an existing home instead of adding a second copy, shows the diff, commits only after a yes. For the urgent case; Aurora's weekly dream does this in bulk.
disable-model-invocation: true
argument-hint: <the learning, in a sentence> | --sweep
---

Promote a learning: $ARGUMENTS

A line in the layer's `rules/` or the vault's `me/` reaches **every future session in every
project**. That is the point and the risk, so this skill is slow on purpose: classify, search,
draft, show, ask, then write.

The two knowledge repos: the **layer** (rules, lessons, skills) and the **vault** (the owner's
profile in `me/`, memory, the bulletin). Each checkout is the second line of `atlas/layer` and
`atlas/vault` in the regatta config dir (`$REGATTA_CONFIG`, else `.config/regatta` in the home
folder). `knowledge-commit` below is `../../bin/knowledge-commit` from this skill's base
directory, passed as one path (never through `cd`, so a skill linked in by hand still reaches its
module); it takes `layer` and `vault` as the repo's name.

## 1. Classify

Use the layer's rule on where a learning goes (its one-home table). The test for `rules/` is: it
has bitten in two projects, or it is plainly project-independent. The test for `me/` is: it
would be true in a chat with no code in it. When in doubt, it stays in the project — tag it
there with `<!-- promote: coding -->` so Aurora's weekly dream reconsiders it.

| Destination | File |
| --- | --- |
| how sessions talk, decide, pick a model, fan out; git, worktrees, landing; verification and where learnings go | the matching file in the layer's `rules/` (list them: one file per area) |
| a Claude Code / agent finding needed only sometimes | the layer's `lessons/claude-code.md` (or a new topic file) |
| the owner as a collaborator | the vault's `me/about.md` (`core.md` only if it belongs in its 15 lines) |
| the household | the vault's `me/household.md` |

## 2. Search before writing — one home per fact

```bash
grep -rn -i "<two or three key words>" <layer>/rules <layer>/lessons <vault>/me <home>/.claude/CLAUDE.md
```

Also grep the current project's `CLAUDE.md` / `AGENTS.md`. If a home already says it, **edit
that line** (sharpen, date, add the second incident) rather than adding one. If a project file
says it too, the project copy becomes a one-line pointer after promotion — or stays, if it is
the project-specific narrowing of the general rule.

## 3. Draft, within the budget

- One to three lines. Imperative. The *why* in a clause, not a paragraph; incidents go to
  `lessons/`, not `rules/`.
- Timeless, dated (`since: yyyy-mm-dd`), or a pointer — never a bare claim about something
  that will change.
- Check the budget first: the layer's `bootstrap.sh --check`. Over budget means something else
  must go; propose what.
- No pronoun for the owner; use their name.

## 4. Show and ask

Show: destination file, the exact diff, where the fact came from, and what happens to the
source (pointer, delete, keep). Ask with `AskUserQuestion` — *promote as shown*, *edit*,
*keep it in the project*. Nothing is written before a yes.

## 5. Write and commit

**The layer (rules/, lessons/) lands through a branch** — nothing there is live until it
merges. From wherever this session is:

```bash
knowledge-commit layer --open promote-<slug>
```

prints a worktree path. Apply the diff to the files **under that path**, never to the layer's
primary checkout, append the `log.md` line there, then land it — the check, the pull request and
the merge in one call, the path written out in full:

```bash
knowledge-commit layer --in <that path> [--review <report>] -m "Promote: <slug> (from <project>)"
```

Anything but a record (`docs/`, `lessons/`, `sextant/`, `log.md`, `README.md`, `TODO.md`) lands only reviewed (the owner's rule of 2026-09-29). Run it without `--review` first: `NOT launched — unreviewed` (`NOT landed` in older versions) names a diff file. Spawn the `reviewer` agent (`model: "opus"`) on that file, briefed as the refusal says — from another repo the name resolves to that repo's reviewer — fix its WRONGs, save its report to a scratch file, and run the same line again with `--review <report>` after the path. If fixing a WRONG changes the text the owner approved in step 4, show the new diff and ask again before landing.

A `NOT launched` (or `NOT landed`) line means nothing merged: say so and why. **The vault (me/) lands the same
way** (the owner changes `me/` only through PRs):

```bash
knowledge-commit vault --open promote-<slug>
knowledge-commit vault --in <that path> [--review <report>] -m "Promote: <slug> (from <project>)"
```

`me/` is never a record, so the refusal, the reviewer (briefed: the project is the vault) and the
`--review` rerun always follow.

The `log.md` line (`- yyyy-mm-dd promote: <slug> → <file> (from <project>)`): in the layer,
under the worktree path before `--in`. In the vault, on the primary **after** the landing —
its `log.md` is written in place, and `--in` refuses a branch that carries it:
`knowledge-commit vault -m "Promote: <slug> (log)" log.md`. Shrink or delete the source as
agreed; a project file edit rides the project's own checkpoint. A promoted memory file is
deleted from the memory directory and its `MEMORY.md` line removed — in place, since `memory/`
is a record.

Rules load at session start: the change reaches sessions started from now on, not the ones
already running. If running sessions need it this week, `/share` it as well.

## `--sweep`

Walk candidates instead of taking one: every `user`/`feedback` entry in the current project's
auto-memory, and every `<!-- promote: … -->` tag in the project. Classify each, batch them
into one `AskUserQuestion` (at most four per question), then apply the approved ones as one
commit per destination repo.
