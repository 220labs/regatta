# Dream, one scope — the per-scope pass (`/aurora dream --scope <scope>`)

The dream bounded to one scope of the registry (the layer's knowledge-layers design, D2-A and D4-B,
step S5). A **scope** is a group of repos in the registry; its first repo is its **anchor**, the
scope's knowledge repo. The pass reads that scope alone and writes two files: the scope's own
dream, which stays in the anchor, and its **inbox file**, the only thing that leaves — generalised
lines the global dream reads as inbox. For a confidential scope (`"confidential": true`) that file
is all the global dream ever sees of it: nothing reads down into a confidential node; only
generalised knowledge flows upstream. An open scope's file is the same shape; the global dream
also reads that scope whole, as before.

`<regatta>`, `<module>`, `<vault>`, `<layer>` and the rest: the aurora skill's "Where things are".
`--days N` widens the window (default 7).

## 0. Where — and stop if not ready

```bash
<module>/bin/scope-pass where <scope>
```

It prints `<name> <value>` lines; every `<anchor>`, `<dream>`, `<draft>`, `<inbox>`, `<section>`,
`<words>`, `<memory>` (one line per folder) and `<members>` below is that value. Its last line is
`ready yes` or `ready no — <why>`: on `no`, stop, say the why in one line, and write nothing. Never
post to the bulletin from this pass, here or when a step fails: the bulletin labels a line by its
cwd, which is the anchor, and the why names it; unattended, weekly-run posts for you, from the vault.

The session runs from `<anchor>` (weekly-run starts it there): a confidential scope's paths are
fenced from any other cwd. Read only the scope's repos, the vault and the layer — never another
scope's folders, and never `<projects>` wholesale.

## 1. Gather — the scope alone

```bash
<module>/bin/week-digest --days 7 --scope <scope>              # what the owner typed in this scope's sessions; ✱ = maybe a correction
<module>/bin/week-digest --promote-tags --scope <scope>        # the scope's `<!-- promote:` lines
<regatta> knowledge-numbers --scope <scope>                    # its per-project numbers (plumb)
<regatta> interruptions --days 7 --list all --scope <scope>    # every question put to the owner in it, and the answer
<regatta> repos --branches --scope <scope>                     # its idle claude/* branches
```

Then read:
- Each `<memory>` folder's `MEMORY.md`, and the files in it changed within the window.
- Each member's `AGENTS.md` / `CLAUDE.md` and `TODO.md` — the scope's own layer, where most of what
  this pass proposes lands.
- The anchor's previous `dreams/*.md` (never a `*-upstream-held.md` as a model to copy): what was
  proposed, approved, rejected. A rejected item is not re-proposed without new evidence; say what.
- `<vault>/me/*.md` and `<layer>/rules/*.md` — read only to know what is already upstream, so an
  upstream line is never a copy of a line that exists.
- `<section>`, when it is not `none`: **the scope's own section**, kept in its anchor
  (`.claude/scope-pass.md`). Read it and follow it as step 2b; it writes only inside the scope, and
  anything bound upstream joins the draft, never another file outside the node. A scope folds its own weekly ritual in here —
  a pipeline's generalising pass, a client's review — rather than running a second job.

## 2. Think — five questions, each with evidence

1. **Repeated corrections in the scope.** ✱ prompts that correct the same behaviour twice or more:
   the quotes, the sessions, and the **mechanism** (a hook, a test, a check, a template field) — a
   third line of prose is not one.
2. **The scope's own layer.** Which memory entries, tags or answered decisions belong in a member's
   `AGENTS.md`, `docs/` or `TODO.md`? Draft each as the exact line and its file.
3. **Upstream.** Which learnings are true beyond this scope — in two scopes, or plainly
   project-independent (rule: engineering's test)? Each becomes **one generalised line** for the
   layer's `rules/` or `lessons/`, or the vault's `me/`: stated so it holds for any project, its
   evidence as counts and kinds ("corrected 3 times in 2 sessions"), never as quotes.
4. **Retire and merge.** Memory or `AGENTS.md` lines in the scope duplicated, contradicted or stale
   for 90 days: the cut, with the prune test (*would removing this cause a mistake?*).
5. **What the owner waits on here.** The scope's open D-items and branches, their age, and the
   change that would have avoided the wait.

## 3. Write — two files in the anchor, nothing else

**The scope's dream**, `<dream>` (in the anchor; it may name anything in the scope):

```markdown
# Dream — <scope> — <date> (<N> sessions, <M> prompts)

Numbering: P-items are proposed changes (P1…), Q-items questions (Q1…); each ends in a
`➤ Answer:` line pre-filled with the recommendation. Every file named is a markdown link.

## Numbers
<the scope's knowledge-numbers rows> · corrections repeated this week: <n>

## P — proposed changes
P1. <title> — <destination file in the scope>
    why: <quotes + session ids>
    ```diff
    <exact diff>
    ```
    ➤ Answer: apply

## Repeated corrections → mechanisms
## Memory clean-up
## Sent upstream
<the U-lines exactly as written to the inbox file, so the node keeps what it said>

## Q — questions
## Feedback from <owner>
```

**The draft of the inbox file**, `<draft>` (in the anchor, beside the dream) — written whole every
pass, a week with nothing to send included (its heading is the proof the pass ran). Never write
`<inbox>` itself: the vault's session-end hook commits and pushes what lies there, so only Record,
after its check, puts the draft there:

```markdown
# Upstream — <scope> — <date> (<U> lines)

Generalised lines from the scope's weekly pass, for the global dream to read as inbox.

U1. <the line, as it would read in its destination> — <rules/<file> | lessons/<file> | me/<file>>
    why: <counts and kinds; no repo, path, person, client or product of the scope>
```

For a **confidential** scope, no line of the inbox file may name one of `<members>`, a path of the
scope's, or a word of `<words>`; the scope's name alone is allowed (the file carries it). A
learning that cannot be said without them stays in the scope's dream. `scope-pass check <scope>`
runs the same test on the draft that the Record step will — run it, and rewrite until it says `clean`.

## 4. Record

```bash
<module>/bin/scope-pass record <scope>
```

It checks the draft once more — a hit holds the whole draft back inside the anchor
(`dreams/<date>-upstream-held.md`) and exits 1; then say so, write the draft again without the hits,
and run it again — commits the dream on the anchor's main (in place), moves the draft to `<inbox>`,
appends the vault's `log.md` line and commits both. Never commit either file any other way, and never
copy or `knowledge-commit` the draft yourself: the check is what lets it leave.

## 5. Report

Unattended: nothing else. Interactive: the upstream lines in one line each, the P-item that matters
most, and "the scope's dream is `<dream>`".
