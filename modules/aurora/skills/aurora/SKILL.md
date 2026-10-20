---
name: aurora
description: Aurora Borealis — the night job. Runs the sections due tonight (today the weekly branches, charts and dream, Sundays), each from this skill's sections/; unattended from bin/weekly-run, or by hand with a section name. Writes proposals and records only; /embark applies them with the owner.
disable-model-invocation: true
model: fable
effort: high
argument-hint: "[<section>…] [--days N]"
---

Aurora over: $ARGUMENTS

Aurora Borealis is the work that happens while the owner sleeps (the layer's
docs/record/regatta-2026-10-03.md, D2: named broad on purpose so more jobs fit under it). Each
job is a **section**: one file in `sections/` beside this file, with its own cadence. Aurora
itself only picks the sections and runs them in order; what a section reads and writes is in its file.

## Where things are

Run this first, as one path from this skill's base directory (never through `cd`, so a skill
linked in by hand still reaches its module):

```bash
<base directory>/../../bin/weekly-run where
```

It prints one `<name> <value>` line each; every `<module>`, `<regatta>`, `<layer>`,
`<layer-name>`, `<vault>`, `<vault-name>`, `<logs>`, `<projects>` (the projects folder) and `<owner>` (the name a report's "Feedback from <owner>" heading carries, read back by atlas's bulletin and keel) in this skill and its sections is that
value. `<layer>` and `<vault>` are atlas's two knowledge repos — the layer every session loads
(rules, skills, docs), the vault of records written in place (bulletin, memory, dreams,
`log.md`) — and `<layer-name>`, `<vault-name>` the names `knowledge-commit` takes for them.
`<regatta>` is the core's command line: **every tool of another module is run as `<regatta>
<tool> …`** (`<regatta> knowledge-commit …`, `<regatta> bulletin.py --post …`), never by a path
of its own, so it works whichever module holds it; a tool it calls not installed answers
`<tool> not installed` — say so in the section's output and go on without it. `regatta` or
`vault` MISSING: stop, and say which. `layer` MISSING: a section that reads the layer says so and
goes on without it (charts is never due without one).

## Sections

| Section | Cadence | File | Writes |
| --- | --- | --- | --- |
| branches | weekly, Sunday night, first (`bin/weekly-run`'s `due`); `bin/weekly-run` runs the classifier and its `--reap` before any session | `sections/branches.md` | `<vault>/dreams/<date>-branches.md` when a branch waits — one verdict per C3–C6 branch and "B would have archived"; always its `log.md` line |
| charts | weekly, Sunday night, before dream; only in a repo whose `docs/README.md` holds the map (`bin/weekly-run`'s `due`) | `sections/charts.md` | the layer's `docs/` in its own worktree — a dry-run PR `/embark` merges or closes; in mode live also its `log.md` line, landed reviewed |
| dream | weekly, Sunday night; a missed one runs at the next wake (`bin/weekly-run`'s `due` is the one home for when) | `sections/dream.md` | `<vault>/dreams/<date>.md` — the proposal `/embark` reviews |

**The order of a night is fixed: tend, classify, `branches`, `charts`, review, `dream`** —
mechanical and cheap first, the Fable judgement last, so the dream reads what the others left
(the layer's docs/record/aurora-sequence-2026-10-04.md). The tend (wharf's `tend`: every repo's
dead worktrees committed and pushed, landed and empty ones removed) and the classify (wharf's
`repos --branches --classify --reap`: superseded branches archived) are `bin/weekly-run`'s own
zero-token steps before any session; `charts` then reads the unmerged set that is left, and
`dream` lists what truly waits, the charts PR and the branches file among it. `bin/weekly-run
aurora <cwd> --dry-run` prints tonight's order. Planned (not built): a review of changes that
landed under-reviewed, between charts and dream, and the dailies. A new section is one file
here, one row above, its place in `bin/weekly-run`'s `ORDER` and its cadence in `due`; no new
skill, no new launchd job.

## Run

1. **Which sections.** The arguments name them (`/aurora dream`); otherwise the ones whose
   cadence matches today. `bin/weekly-run` passes the due ones explicitly, so an unattended
   run never guesses. Other arguments (`--days N`) go to every section: a section that takes one uses the value
   given here in place of its default.
2. **Each section in turn**, in the order above (unattended, `bin/weekly-run` gives each section
   a session of its own, `charts` run from the layer): Read its file and follow it to the end
   before starting the next. A section that fails says so in its own output, posts one bulletin
   line naming what it left — `<regatta> bulletin.py --post "Aurora's <section> section failed"
   "<what it left undone>"` — and the next still runs. `bin/weekly-run` also checks each
   section's proof (the charts PR, the branches `log.md` line, the dream on `main`) and posts the
   same kind of line for a miss.
3. **Nothing beyond the sections.** Aurora adds no step of its own; unattended, the sections'
   own Record steps are the whole trace (`log.md`, their files, `bin/weekly-run`'s log).
