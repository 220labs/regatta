# Charts — Aurora's weekly section (Sunday night, before dream)

Keep the layer's docs current: rewrite the charts of the topics that changed this week, map and
move the records that landed, and leave one pull request. A **chart** (`docs/<topic>.md`) says
what exists now; a **record** (`docs/record/<topic>-<date>.md`) is a design with the owner's
answers, kept as it was made; the **map** (`docs/README.md`) lists both per topic. Design and
answers: the layer's docs/record/aurora-docs-current-2026-10-03.md (D1 the name, D2 (b) the
move, D4 dry until three clean PRs, D5 the layer first). `<regatta>`, `<layer>` and the rest:
the aurora skill's "Where things are".

**What this section may write: `docs/` (and, in live mode, `log.md`), in its own worktree,
nothing else** — never DESIGN.md, README.md, AGENTS.md or any file outside `docs/` (a
contradiction there is a P-item in the PR body; a record such a file names moves at /embark),
never the vault, never a live system. `bin/weekly-run` runs this section as its own session
from the layer, before dream. atlas's `docs-index` (`<regatta> docs-index`) does every
mechanical step: the skip set, the pick, the banner, the move. Never write a banner or move a
record by hand.

## 1. Setup

```bash
<regatta> knowledge-commit <layer-name> --open charts-<yyyy-mm-dd>   # today's date, written out; prints <wt>
```

The slug must be `charts-<today>`: `bin/weekly-run` finds the worktree by that name to land a
dry run.

Then `EnterWorktree` with that path (as /sextant does; probed under `claude -p` on 2026-09-26,
bin/weekly-run's header). Every path below is under `<wt>`; never write to `<layer>/…`.

```bash
<regatta> docs-index mode --repo <wt>          # dry | live — decides section 5
<regatta> docs-index check --repo <wt>         # the map as it stands
```

## 2. Inputs

- `<regatta> docs-index due --repo <wt>` — `since:` (the day of the last `Charts: <day>` commit
  on main, from midnight; 7 days before the first), the topics to rewrite (`pick:` — up to
  three that changed, plus the oldest topic with no chart) and the ones left alone (`skip:`): a
  topic whose chart or records an unmerged `claude/*` branch edits is never touched; one over
  the cap waits a week.
- `charts feedback:` lines in `<wt>/log.md` dated on or after `since` — the owner's reason for
  closing or correcting the last PR (the embark skill). Read them first; each one binds this run.
- `<regatta> docs-index skips --repo <wt>` — the skip set itself, for section 3.
- `git -C <wt> log main --since=<since> --name-only --format='%h %s'` — what landed.

## 3. Map and move the new records

1. Every dated `docs/<x>-<yyyy-mm-dd>.md` that `check` reports as `has no row`: add it to the
   row of its topic (by its title and the code it names), or a new row when no topic fits — a
   new topic's Chart cell is `—`. A record in the skip set is still mapped; it only does not move.
2. Move them, and any mapped record a branch held last week, in one call:
   `<regatta> docs-index move <name>… --section --also <vault> --repo <wt>`.
   It refuses a record a branch edits, and one that any file outside `docs/` or the vault
   names (those references are code, rules or skills: the move lands reviewed at /embark). List
   each refusal under "Moves waiting" in the PR body, with the files that name it.
3. Banner every record that has none, and re-banner every one `check` says points elsewhere than
   its row (a record `/finish` stamped "no chart yet" before step 2 mapped it, E14):
   `<regatta> docs-index banner <name> <chart.md|none> --repo <wt>` — the review word the
   banner carries stays. It refuses a record a branch edits (R2); leave that one for next week.
4. Carry each record's review word into its Records cell:
   `<regatta> docs-index reviews --write --repo <wt>` (the `· review: …` that `/finish` stamped
   on the banner becomes ` *unseen → stood*` after the link; E14).

5. **Superseded steps** (entry D6-A of the layer's docs/design-docs-2026-10-14.md: Aurora is the
   one writer of `superseded`). A doc that replaces part of a Course doc's Action plan says so on
   one line, `Supersedes: <docs/old-doc.md> S3, S4`; find them with
   `grep -rn '^Supersedes:' <wt>/docs`. For each named step still open in the old doc
   (`<regatta> keel parse`),
   `<regatta> keel step <wt>/docs/<old-doc>.md S3 superseded --note "superseded by <new-doc>.md" --stamp`
   — the field and the Status line, nothing else; never a step that is `done`, and never by
   hand. List each one in the PR body under "Superseded".

## 4. Rewrite the picked charts

For each picked topic, in `due`'s order:

- **A topic whose code moved into a Regatta module** (every file its Code cell names is now a
  module's — under a regatta checkout's `modules/<name>/`, or a shim the layer keeps for one):
  its chart is that module's `README.md`, kept with the module's own changes (contract C1).
  Write no `docs/<topic>.md` for it: set the row's Chart cell to the module's README, as
  `[<name> README](<the README's path>)`, and re-banner its records with that link. A
  `docs/<topic>.md` already there is not deleted here: a P-item, "retire at /embark". A topic
  only part of whose code moved keeps its chart here, for the part that stayed.
- **Read** the code its row's Code cell names — `bin/*` headers, skill front matter and body,
  hook docstrings: they are the ground truth — then its current chart if any, then its records,
  newest first, only for what the code does not say (what was decided against, a limit).
- **Write** `docs/<topic>.md` in this shape, at most 120 lines, nothing else:
  title; one line that it is a chart and where the map is; `## What exists (as of <date>)` —
  bullets, **every claim naming the file it was read from** as a relative link; `## How it
  runs` — a table of files, commands, tests; `## Limits`; `## Open` — pointers to `TODO.md`
  items and open D-items by doc and number, never restated; then a `Records:` line naming
  every record in its row, newest first, one phrase each. No reasoning, no "why" heading: the
  why is the records' (R6). Shape example: the layer's docs/pickup.md.
- A claim you cannot tie to a file is left out, not hedged. Where the code and a record
  disagree, the code wins and the chart says nothing of the record's version.
- Where the chart contradicts DESIGN.md, README.md or AGENTS.md: a P-item (file, line, the
  sentence, what the code says instead), never an edit.
- Set the row's Chart cell to `[<topic>.md](<topic>.md)` and re-banner its records with the
  chart (section 3, step 3).

Then `<regatta> docs-index check --repo <wt>` must print `ok`; fix what is in `docs/` until it
does. One error is not this run's to fix: "names a record by the path it left" for a file
outside `docs/` (a branch landed an old path) — `relink` would write code, so it is a P-item
("relink at /embark") and the run lands with it.

## 5. Record and land

The run's line: `- <date> charts: <n> topics (<list>), <m> records mapped, <k> moved, mode
<dry|live>, skipped <list>`. Live: append it to `<wt>/log.md`. Dry: put it at the top of the PR
body only — a dry branch that appends to `log.md` conflicts with sextant's Monday 02:00 append
before /embark can merge it (review 2026-10-04).

Write the PR body to `<logs>/charts-<date>.md`: that line, the topics rewritten (one line each:
what the chart now says that the records did not), "Moves waiting", the P-items, and the
skipped topics.

- **mode dry** (until the owner flips it, D4): stop here. `bin/weekly-run` commits the
  worktree, pushes the branch and opens the PR "Aurora charts <date> — dry run" with that body;
  Embark merges or closes it with the owner.
- **mode live**: spawn the `reviewer` agent on `git -C <wt> diff main` — brief: every chart
  claim against the file it links (R1), and one WRONG per paragraph of reasoning (R6). Fix its
  WRONGs, save its report beside the PR body, then
  `<regatta> knowledge-commit <layer-name> --in <wt> --review <report> -m "Charts: <date>"`.
  A `NOT launched` (or `NOT landed`) line is the run's last word: say why; the worktree stays for Embark.
