---
name: embark
description: The Monday sitting (was /weekly until 2026-10-03) — hands the owner the week's embark memo (the dream, its branches file, the /sextant entry and the night's failures as one course doc, written by weekly-run after the sextant and first on helm's board), waits for the answers, applies what is approved, commits, and leaves a feedback note both loops read next week.
disable-model-invocation: true
---

Embark on the week: the Monday sitting. $ARGUMENTS

The week's voyage starts here: the owner looks over what Aurora prepared overnight, approves the
course, and the week sets off (the layer's docs/record/regatta-2026-10-03.md, D1).

Paths: run `<base directory>/../../bin/weekly-run where` first, as one path from this skill's
base directory; every `<regatta>`, `<layer>`, `<layer-name>`, `<vault>`, `<vault-name>`,
`<logs>` and `<owner>` below is the value it prints, and a tool of another module is run as `<regatta> <tool> …`
(the aurora skill's "Where things are" says why).

Target: **ten minutes of the owner's attention**, not thirty (the layer's DESIGN section 8, D12).
Everything slow already happened overnight: Aurora's dream section (Sunday 21:00) wrote a
proposal, `/sextant` (Monday 02:00) wrote an entry, and `weekly-run`'s embark step turned both into
one memo on its own branch in regatta, whose course is the first card in the owner's column on helm's
board (the owner, 2026-10-24: "I want embark presented to me on the helm whenever it runs"). This
skill only hands it over, waits, and applies. It never asks through `AskUserQuestion`: every question
is a D-item in the memo, answered on its course (the 10-24 memo's D2-A, 2026-10-25).

## 1. The memo

- `<logs>/embark-latest.json` names it: `doc`, `branch`, `line` (its `keel line`) and the `dream` it
  covers. When that dream is the newest `<vault>/dreams/<date>.md` and the doc is there, it is this
  week's memo. On the other Mac the file is not there: the memo is on the branch it names,
  `claude/<host>/<date>-embark` in regatta — fetch it and open its worktree as any branch is picked up.
- None yet (the night did not run, or ran before the sextant): write it the same way the night does,
  `<base directory>/../../bin/weekly-run embark <vault>` — one path from this skill's base directory.
  It prints `EMBARK <the keel line>` or `FAILED embark <why>`. `--dry-run` prints the memo and writes
  nothing. A dream or a sextant entry older than 8 days: say which, and offer to run it first (it takes a
  while) or go on with what exists.
- What code cannot know is added to the memo before it is handed over, as D-items in its shape, in
  its worktree, committed there:
  - the layer's own install check on this Mac, where it has one (`<layer>/bootstrap.sh --check`): each
    `⚠` line is one item. The Mac the owner sits at is checked here and nowhere else on a schedule;
    another Mac checks itself daily (lighthouse's `health`) and posts a failure to the bulletin.
  - first sitting of a month, or whenever a report names two instruction files that disagree:
    `/doctor prompt-audit` (Claude Code 2.1.283+); each finding is one item. Why here and not in
    Aurora: the unattended run has no Skill tool (sextant 2026-09-28 F1).
  Each such item carries its context as the memo's do: the evidence, what each option does.

## 2. Hand over

- One screen: the memo's hand-over line as `keel line <doc>` prints it, then three lines that matter
  most across its items, and how many items are `Reversible: no` (those are worth the minutes).
- The list the stand sweep cannot take is counted in the memo; each of those docs is answered on its
  own course (`keel line <doc>`), never here. A doc in a physical repo stands on the owner's one word:
  `keel stand <doc>` writes its `Stands:` line, and the sweep takes its `Reversible: yes` picks 24 h later.
- Then wait for the answers: `<regatta> keel sheep wait <doc>` as the session's background shell. It
  exits on a Save, taken in, or on new comments, printed and not taken in: answer a question with
  `keel sheep reply`, take answers in with `keel sheep pull <doc> --write`, as the keel skill says
  (`keel pull`), and go on to section 3. The owner may answer later, from the board or GitHub: a later `/embark` finds the memo
  answered and starts at section 3.

## 3. Read the answers

`<regatta> keel parse <doc>` gives each item's answer. The memo keeps the dream's D-numbers, and
each title names its source: the dream's P- or Q-item, the branches file, a sextant D-number, the
charts PR, a FAILED line, or an item section 1 added. An item with no answer stays open: it is
neither applied nor recorded as *not now*. The review prompts' answers sit under the memo's Review
section.

## 4. Apply

- Approved dream items (the answer A, or B with the owner's note): apply the diffs exactly. A diff in the layer, or in the vault outside its
  records (`me/`, `routines/`, `AGENTS.md`, `sparks.json`… — everything not in `in_place` of its
  `.claude/workflow.json`), goes into a worktree: `<regatta> knowledge-commit
  <layer-name|vault-name> --open embark-<date>` prints its path, and every such file is edited
  **under that path**, never at `<layer>/…` or `<vault>/…`. Budget checks, where the layer has
  its install check: `<the layer worktree's path>/bootstrap.sh --check` (that worktree's rules)
  and, for the vault's `me/`, the same check with the vault's override pointed at `<the vault
  worktree's path>` (the variable atlas's `vault` key names). A diff to a vault record
  (`memory/`, `bulletin.md`, `inbox/`…) is applied in place.
- Approved mechanisms: small ones (a check, a rule turned into a hook) are built now if they
  fit in the sitting's remaining budget; the rest become a `TODO.md` item in the project they
  belong to, or a `**Decide:**` if they need the owner.
- The branches item: `pickup archive --confirmed` is the owner's to type, never an agent's (the checkpoint
  hook refuses it, and `pickup archive` refuses a branch not shown to be on main). For each accepted
  `drop` give the owner the line (`<pickup> review <branch>`, then `<pickup> archive <branch> --confirmed`,
  `<pickup>` the absolute path `regatta which pickup` prints: it is not on an interactive shell's PATH);
  one not on main becomes a `TODO.md` item. Each `resume` becomes a `/todo handoff` in its repo; a `B`
  answer's note overrides the branches it names.
- The sextant's items: the owner's answer goes on that decision's `➤ Answer:` line in `<layer>/DESIGN.md`,
  in the layer's embark worktree (below). A FAILED line answered A: one item in regatta's `TODO.md` for
  the module the item names.
- Every `**Decide:**` in any project's `TODO.md` whose `Applies … on <date>` has passed:
  apply the default it names, unless the owner overruled it in the sitting (Q5, 2026-09-29).
- The charts PR (its memo item): *merge*, *merge after my edits* (the owner edits the chart on
  GitHub first, as with any memo), *close*. Merge: `cd
  <layer>/.claude/worktrees/charts-<date> && <regatta> pr merge` — the owner at the keyboard is
  the approval. Close: close it on GitHub with the owner's reason. Either way, one line in the
  layer's `log.md` (with the embark line below): `- <date> charts feedback: merged clean |
  merged, corrected <what> | closed — <reason>`; the next run reads it first. Its "Moves waiting" (records a file outside `docs/` names) and any
  "relink at /embark" move **before** the merge, in the PR's own worktree (it has the new map
  rows): `<regatta> docs-index move <name>… --repo <that path>` and `<regatta> docs-index
  relink --repo <that path>`, then `docs-index check` must print `ok`; commit, and show the
  owner that diff — it rewrites code, and their merge is its review. A vault file naming one is
  fixed after the merge, in the vault's embark worktree. After the third `merged clean` line
  since the map began, ask once whether to flip `mode: dry` → `mode: live` in `docs/README.md`
  (D4: a one-line record commit).
- Write the owner's answers into each report's **Feedback from <owner>** section, verbatim,
  plus the decisions (`P3: never — reason`), and under each answered item of the memo a
  `> **Applied.** …` (or Superseded, Checked) line; commit it on the memo's branch, which lands by
  `/finish` like any doc.
- Append to both `log.md` files — the layer's under its worktree path, the vault's in place
  with the dream's feedback, as `- yyyy-mm-dd embark: …` (atlas's bulletin reads that line to
  stop naming the dream); commit (the first line takes only the vault's records; the vault's
  worktree exists only if a P-item touched `me/` or another gated path):
  ```bash
  <regatta> knowledge-commit <vault-name> -m "Embark: <date> — feedback and log"
  <regatta> knowledge-commit <vault-name> --in <the vault embark worktree path> [--review <report>] -m "Embark: <date> — <n> applied"
  <regatta> knowledge-commit <layer-name> --in <the layer embark worktree path> [--review <report>] -m "Embark: <date> — <n> applied"
  ```
  Anything but a record (`records` and `in_place` in the repo's `.claude/workflow.json`) launches only reviewed (the layer's `docs/record/coding-on-workflow-2026-09-25.md` D1, amended 2026-09-29). Run it without `--review` first: `NOT launched — unreviewed` (`NOT landed` before rename S3) names a diff file. Spawn the `reviewer` agent (`model: "opus"`) on that file, briefed as the refusal says — from another repo the name resolves to that repo's reviewer — fix its WRONGs, save its report in the scratchpad, and run the same line again with `--review <report>` after the path.
  Each `--in` checks, opens the pull request and merges it; a `NOT launched` (or `NOT landed`) line means
  nothing merged — report it. `me/` changes always need the review.
- If `me/core.md` changed: print it in full and remind the owner to paste it into the claude.ai
  account instructions (the layer's DESIGN section 6) — the one copy that lives outside git.

## 5. Close

Three lines: what changed, what was deferred, what next week's loops should look at. Rules
reach sessions started from now on; `/share` anything running sessions need today.
