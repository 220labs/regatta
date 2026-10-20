---
name: embark
description: The Monday sitting (was /weekly until 2026-10-03) — the owner's ten-minute review of Aurora's Sunday-night dream proposal and /sextant entry; batches every decision into a few questions, applies what is approved, commits, and leaves a feedback note both loops read next week.
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
proposal, `/sextant` (Monday 02:00) wrote an entry. This skill only presents, asks, and applies.

## 1. Load

- The newest `<vault>/dreams/<date>.md` and, where the sextant runs, `<layer>/sextant/*.md`.
  Either missing or older than 8 days: say which, and offer to run it now (it takes a while) or
  continue with what exists.
- The classifier's report: `<vault>/dreams/<date>-branches.md` of the same night,
  when Aurora's branches section wrote one (a week with nothing waiting writes none; its
  `log.md` line says so). Its P-items join step 3's batch like the dream's. Its "B would have
  archived" list (Aurora D2, the layer's docs/record/aurora-sequence-2026-10-04.md) is walked
  once: one line in step 2, then one question in step 3 — keep the line where it is
  (recommended), or name the branches that show it should move. Nothing in that list is
  archived from here; a branch the owner drops is the owner's `pickup archive` to type.
- A `FAILED` line in `<logs>/<Sunday>-aurora.log` (tend, classify, branches, charts, dream —
  the night's steps, `bin/weekly-run`'s header): each is a P-item, why the step missed. The
  bulletin carries the same line.
- `<regatta> knowledge-numbers`.
- `<regatta> keel embark`: every open item the stand sweep cannot take, in docs handed
  over more than 72 h ago, grouped by block reason (`Reversible: no`, unmarked, conditional,
  reopened, physical repo, on main, over ten items, no link), oldest first in each group. Read-only,
  no model; the sweep itself needs `keel stand --arm` (review D4-A, the layer's
  `docs/design-docs-review-2026-10-14.md`).
- The newest charts PR, while the docs map says `mode: dry` (`<regatta> docs-index mode
  --repo <layer>`): the `DRY <url>` line of `<logs>/<Sunday>-aurora.log` (or `<regatta> repos
  --branches`: `claude/*-charts-<date>`). Read its diff — every chart claim against the file it
  links (R1 of the layer's docs/record/aurora-docs-current-2026-10-03.md) — and its body's
  P-items. A `FAILED charts` line instead is a P-item: why the run missed.
- The layer's own install check on this Mac, where it has one (`<layer>/bootstrap.sh --check`).
  The Mac the owner sits at is checked here and nowhere else on a schedule; another Mac checks
  itself daily (lighthouse's `health`) and posts a failure to the bulletin (D1, 2026-09-29).
  Every `⚠` line is a P-item for step 3.
- First sitting of a month, or whenever a report names two instruction files that disagree:
  `/doctor prompt-audit` (Claude Code 2.1.283+). It lists contradicting instruction files,
  stale paths and stale commands first; each finding is one more P-item for step 3, applied
  in step 4 like the dream's. Why here and not in Aurora: the unattended run has no Skill
  tool (sextant 2026-09-28 F1).

## 2. Present — one screen

- **Numbers**, with the arrow vs last week for each (read last week's entry).
- **Three things that matter**, one line each, picked across both reports.
- Anything in either report's "Do this now".
- **The list the sweep cannot take** (step 1's `keel embark`), printed as it is: one block per
  reason, oldest first, each item a link to its doc and line. No `AskUserQuestion`: each doc is
  answered in its own form (`keel line <doc>`), and a reply that points the owner at the list
  carries that line per doc they open (dream D2). A doc in a physical repo stands on their one
  word here: `keel stand <doc>` writes its `Stands:` line, and the sweep takes its
  `Reversible: yes` picks 24 h later. Say how many are `Reversible: no` — those are the ones
  worth the sitting's minutes.

## 3. Ask — batched

Put every P-item (dream), PROPOSE item (sextant) and Q-item into `AskUserQuestion`, at most
four per question and as few questions as possible; recommended option first. Each P-item
offers *apply*, *apply edited* (the owner says how in notes), *not now*, *never* (recorded so
it is not proposed again). Then the review prompts, as one free-text question:

- What did you spend attention on this week versus what you planned?
- Which recurring manual thing could a session or a routine do?
- How much of the plan's weekly budget was left unspent at the last reset? (Read it off
  Claude's usage screen; no local file records it. Written into the dream's Numbers.)

## 4. Apply

- Approved P-items: apply the diffs exactly. A diff in the layer, or in the vault outside its
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
- Every `**Decide:**` in any project's `TODO.md` whose `Applies … on <date>` has passed:
  apply the default it names, unless the owner overruled it in the sitting (Q5, 2026-09-29).
- The charts PR (step 1), one question in step 3: *merge*, *merge after my edits* (the owner
  edits the chart on GitHub first, as with any memo), *close*. Merge: `cd
  <layer>/.claude/worktrees/charts-<date> && <regatta> pr merge` — the owner at the keyboard is
  the approval. Close: close it on GitHub with the owner's reason. Either way, one line in the
  layer's `log.md` (with the embark line below): `- <date> charts feedback: merged clean |
  merged, corrected <what> | closed — <reason>`; the next run reads it first. Its P-items join
  step 3's like the dream's. Its "Moves waiting" (records a file outside `docs/` names) and any
  "relink at /embark" move **before** the merge, in the PR's own worktree (it has the new map
  rows): `<regatta> docs-index move <name>… --repo <that path>` and `<regatta> docs-index
  relink --repo <that path>`, then `docs-index check` must print `ok`; commit, and show the
  owner that diff — it rewrites code, and their merge is its review. A vault file naming one is
  fixed after the merge, in the vault's embark worktree. After the third `merged clean` line
  since the map began, ask once whether to flip `mode: dry` → `mode: live` in `docs/README.md`
  (D4: a one-line record commit).
- Write the owner's answers into each report's **Feedback from <owner>** section, verbatim,
  plus the decisions (`P3: never — reason`).
- Append to both `log.md` files — the layer's under its worktree path, the vault's in place
  with the dream's feedback, as `- yyyy-mm-dd embark: …` (atlas's bulletin reads that line to
  stop naming the dream); commit (the first line takes only the vault's records; the vault's
  worktree exists only if a P-item touched `me/` or another gated path):
  ```bash
  <regatta> knowledge-commit <vault-name> -m "Embark: <date> — feedback and log"
  <regatta> knowledge-commit <vault-name> --in <the vault embark worktree path> [--review <report>] -m "Embark: <date> — <n> applied"
  <regatta> knowledge-commit <layer-name> --in <the layer embark worktree path> [--review <report>] -m "Embark: <date> — <n> applied"
  ```
  Anything but a record (`records` and `in_place` in the repo's `.claude/workflow.json`) lands only reviewed (the layer's `docs/record/coding-on-workflow-2026-09-25.md` D1, amended 2026-09-29). Run it without `--review` first: `NOT launched — unreviewed` (`NOT landed` before rename S3) names a diff file. Spawn the `reviewer` agent (`model: "opus"`) on that file, briefed as the refusal says — from another repo the name resolves to that repo's reviewer — fix its WRONGs, save its report in the scratchpad, and run the same line again with `--review <report>` after the path.
  Each `--in` checks, opens the pull request and merges it; a `NOT launched` (or `NOT landed`) line means
  nothing merged — report it. `me/` changes always need the review.
- If `me/core.md` changed: print it in full and remind the owner to paste it into the claude.ai
  account instructions (the layer's DESIGN section 6) — the one copy that lives outside git.

## 5. Close

Three lines: what changed, what was deferred, what next week's loops should look at. Rules
reach sessions started from now on; `/share` anything running sessions need today.
