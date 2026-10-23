---
name: sextant
description: The weekly feedback loop — research what changed in the world (Claude Code releases, agentic knowledge and memory practice, personal productivity, side income), review the layer's design and implementation against it, implement the small improvements, log the rest with verdicts. Run once a week; reads the previous entry first so findings compound instead of repeating.
disable-model-invocation: true
model: fable
effort: high
---

Run the weekly sextant pass. $ARGUMENTS

## Where things are

Run this first, as one path from this skill's base directory (never through `cd`, so a skill
linked in by hand still reaches its module):

```bash
<base directory>/../../libexec/sextant-run where
```

It prints one `<name> <value>` line each; every `<module>`, `<regatta>`, `<layer>`,
`<layer-name>`, `<vault>`, `<vault-name>`, `<ideas>`, `<reports>`, `<projects>` and `<owner>` below is that
value. `<layer>` and `<vault>` are atlas's two knowledge repos — the layer every session loads
(rules, lessons, skills, docs, `DESIGN.md`, this pass's entries in `sextant/`) and the vault of
records written in place (`log.md`, the ideas) — and `<layer-name>`, `<vault-name>` the names
`knowledge-commit` takes. `<ideas>` is Sparks' ideas pool, where the proposals and the sounding queue
live. `<regatta>` is the core's command line: **every tool of another module is run as `<regatta>
<tool> …`** (`<regatta> knowledge-commit …`, `<regatta> pickup seed …`), never by a path of its own,
written out in full as `where` printed it (the unattended run's allow rules match the text as typed).
A tool not installed answers `regatta: <tool> not installed` in one line: say so where its result
would go and go on without it. `layer` or `vault` MISSING: stop, and say which.

Why it exists: the layer's `DESIGN.md` (its section on this loop). Every previous run: `<layer>/sextant/`.
It works in two layer worktrees and launches through pull requests like any change to the layer
(the layer's docs/record/coding-on-workflow-2026-09-25.md) — from an interactive session or
unattended (aurora's `weekly-run sextant`, else this module's own runner) alike.

You are auditing a design against the world, not admiring it. Every finding gets a verdict and a
cost; every recommendation says what adopting it costs and what ignoring it costs. Cite primary
sources (docs, specs, the author's own post) over secondary ones, with links.

## 0. Setup

- **Before writing anything, open and enter the worktree:**
  ```bash
  <regatta> knowledge-commit <layer-name> --open sextant-<yyyy-mm-dd>
  ```
  prints its absolute path; call `EnterWorktree` with that path. The entry and `log.md` are
  written **relative to that worktree**. ADOPT edits and PROPOSE's DESIGN.md lines go in a
  second one, `--open sextant-<yyyy-mm-dd>-changes`, written by absolute path: they launch only
  reviewed, and the entry must not wait on that. Never write to `<layer>` itself, which is the
  primary checkout on `main` and denied. Reads of the previous entries may use either.
- Never deploy anything. Never push by hand: step 4's `--in` pushes the branch and merges it.
- Read, in this order: the **latest** `sextant/<date>.md` (its Numbers, its "Feedback from
  <owner>", every WATCH / PROPOSE item), then `DESIGN.md`, then the last week of
  `<layer>/log.md` and `<vault>/log.md`.
- Note the previous run's date. Everything below is "what changed since then"; do not restate a
  finding the last entry already carries unless its verdict should change.

## 1. Research — the fixed checklist, then whatever it misses

For each line, search and fetch; one paragraph per genuinely new item. Skip items with nothing
new and say so in one line, so the reader knows they were checked.

1. **Claude Code**: the changelog since the last run (`code.claude.com/docs/en/changelog`), only
   rows about CLAUDE.md/rules/memory, skills, plugins, hooks, routines/scheduled tasks,
   sessions/worktrees, subagents, cross-session messaging, `/doctor`; the `memory`, `skills`,
   `plugins` and `best-practices` doc pages for changed guidance.
2. **Anthropic engineering** posts on context engineering, memory, agents; Managed Agents
   memory/dreaming docs; claude.ai memory, Projects and Cowork changes (reach beyond Claude Code,
   as the layer's DESIGN.md asks).
3. **Open standards**: the Agent Skills spec and AGENTS.md; anything the Agentic AI Foundation
   published.
4. **Agentic knowledge practice**: the LLM-wiki pattern and its implementations; agent-memory
   surveys and tooling (claude-mem, Mem0, Letta, Zep, the Obsidian mirror plugins) — has anything
   crossed a revisit trigger in the layer's DESIGN.md?
5. **Personal productivity with agents**: cadences, review practices, measurement — only what a
   practitioner reports, not listicles.
6. **Side income**: validation practice, and traction in the niches the layer's DESIGN.md names.
7. **Free slot**: one thing the checklist would never find. Say why it matters or drop it.

## 2. Review — the design against the findings

For each finding, one verdict:

- **ADOPT** — clearly better, fits in about an hour, touches no live system: implement it now
  in the layer (docs, skills, hooks, tests — tests green before saving a hook). At most three
  per run; the fourth becomes PROPOSE. Make these edits, and PROPOSE's DESIGN.md lines, in a
  second worktree (`<regatta> knowledge-commit <layer-name> --open sextant-<date>-changes`): they
  launch only reviewed, and the entry must not wait on that.
- **PROPOSE** — needs <owner> (a decision, a cost, a change of habit): a numbered decision,
  appended to DESIGN.md's decisions section, ending in a `➤ Answer:` line pre-filled with the
  recommendation so <owner> answers in place.
- **WATCH** — real but not yet actionable: one line, with the trigger that would make it ADOPT.
- **REJECT** — why, in one sentence; a rejection with a reason is worth more than silence.

Then review the layer itself, independent of the findings:

- Is any part built but unused? (`/share` never posted, Aurora never run, a skill no
  transcript invoked — `grep -l` the archive.)
- Is the always-loaded budget growing? Is a rule doing a hook's job?
- Did last entry's "Feedback from <owner>" get acted on?
- Did `lessons/` change since the last entry? From inside the entry worktree (same history;
  `git -C` another checkout is refused there), `git log --since=<its date> -p -- lessons/`: per
  changed lesson, one verdict — does its claim still hold against the source it cites? Lessons
  launch without a review because this step reads them (the layer's coding-on-workflow record, D1).
- On or after the `recheck:` date in the header of the core's `jev` (`<regatta> which jev` prints
  its path): compare its Facts block with `docs.typesafe.ai/models.md`, `docs.typesafe.ai/api.md`
  and the `model-jaggedness/` pages. Fixing what moved and bumping the date is an ADOPT when that
  path is inside the layer, made in the `-changes` worktree; otherwise a PROPOSE naming the file.
- Has a venture experiment sat at one gate longer than planned?

## 2b. Ideas — what to do with what <owner> kept

`<ideas>` holds one note per topic from recorded conversations, filed by Sparks (this module's
`sparks`; the layer's docs/record/ideas-pipeline-2026-10-02.md, D4). <owner> triages them in
ordinary sessions: `status:` is `new`, `kept` or `dropped`. This step is the backstop for when
<owner> is behind. No notes, or nothing changed since the last run: say so in one line and move on.

- Read `<ideas>/README.md` (the formats), every `kept` and `new` note, and `<ideas>/proposals/`.
- From the `kept` notes, old and new together: refine the proposal a note applies to, or start
  `proposals/<slug>.md` when none does, and add a line to its `## Log`. Never edit or delete a note.
- `new` notes older than seven days go into `<ideas>/triage.md`, rewritten each run: one line each
  with keep or drop, the reason, and the proposal it would feed.
- Commit those files in place: `<regatta> knowledge-commit <vault-name> -m "Sextant: ideas <date>"
  <the files>` when `<ideas>` is inside `<vault>` (the vault's in-place records); otherwise name the
  files in the entry and leave them for <owner>. No `publish`: proposals live in git only — a launchd
  run cannot rewrite a cloud-drive file another process made, so the drive holds the notes as filed,
  not the proposals.
- The entry gets **one** line under For <owner>: counts (kept, new, waiting more than a week,
  proposals touched) and the folder's name. Never a title or a word of an idea: the layer holds
  nothing personal.

## 2c. Soundings — the queue <owner> filled

A `ready` proposal is sounded where <owner> puts it, every time (the layer's
docs/record/proposer-2026-10-16.md section 5, D2): *launch now* — `/sounding` at once, in <owner>'s
session — or Sextant's queue. Nothing is queued unasked: `soundings add` is <owner>'s verb, denied to
this run. The queue is this module's `soundings` (its `--help` lists the verbs).

- `<regatta> soundings refresh`, then `<regatta> soundings next`. It names what may start (at most
  three in seven days, never more than five still with <owner>, earlier weeks' counted), each with
  its `--at` slot, and what is held and why. Nothing to start: one line, move on.
- Per candidate, in order, the commands `next` prints, a scratch file for the brief:
  `<regatta> soundings brief <slug> --out <file>`;
  `<regatta> pickup seed sounding-<slug> --file <file> --repo <repo> --no-start` (read the branch from
  its `seeded <branch>` line, never predicted);
  `<regatta> dispatch <branch> --repo <repo> --at <slot> --if-room` — the shape this run is allowed,
  nothing wider, `--if-room` last: no `--yolo`, no second `--at`, no other flag; `--if-room` reads the
  week when it fires; pickup seed is allowed only ending `--no-start`;
  `<regatta> soundings mark <slug> scheduled --branch <branch> --at <slot> --repo <repo>`.
  An entry `refresh` put back in line (scheduled over a week ago, its branch still a seed: the run was
  refused at fire time) keeps its branch, and `next` prints only its dispatch and mark — never seed it again.
  A step that fails: stop that candidate and say why in triage.md (below); it stays queued for next week — but a seed made and not dispatched: name its branch there, since the queue cannot record it yet and `next` would seed it again (S8).
- A candidate `next` prints as `by hand <slug>: …` (a peer the launch runs is not installed, or this is
  the module's own runner, which starts no work): run none of its commands; its line is what <owner>
  would type — carry it to triage.md as that candidate's line, as it is.
- In `<ideas>/triage.md`, under `## Ready to sound`: one line per `ready` proposal not yet in the
  queue, with <owner>'s two choices — *queue* (`soundings add <slug>`, said in any session) or *launch
  now* (`/sounding` on it, then `soundings add <slug> --now --branch <its branch> --repo <repo>`, or `refresh` never closes it) — and one per held entry with `next`'s why.
  Commit it and `<ideas>/soundings.json` with step 2b's files, or in their own `<regatta>
  knowledge-commit <vault-name> -m` when 2b committed already or had nothing.
- The entry's For <owner> gets **one** line, counts only (2b's rule: no word of an idea in the layer):
  started this run, queued, held, ready and waiting for a pick, open of five — and the triage file's name.

## 3. Measure — computed, never estimated

```bash
<regatta> knowledge-numbers          # the table, ready to paste
```

The table ends with the **Course goals**, one row each for G1–G6 of the layer's
`docs/design-docs-2026-10-14.md` (baseline, target, now), read through `keel parse`, `keel list
--json` and `keel open --json` (entry S10). Copy the rows into Numbers as printed. A goal it cannot
measure yet prints `not measured — <why>`: carry that line, never an estimate. G1 and G5 count the docs
handed over in the last 28 days, a window the baselines did not record, so read the trend over two
runs, not the first difference. When two goals move the wrong way for two weeks running, that is a
PROPOSE item to revisit the Course (the entry's Goals section says so).

Below the Course rows come the **Wharf goals**, G1–G5 of the layer's `docs/wharf-on-orca-2026-10-17.md`
(the ids repeat the Course's, so carry the table's name with them), each a number followed by its source:

- G1 ships built end to end by `wharf apply` — `plan.json` blueprints with an `orca_run` that wharf
  marked `ended` (every block ended), counted since the first ship as the target is, this week's beside it.
- G2 ship workers' asks that reached <owner> past a live skipper — the attention log's `Relay` rows
  `escalated`, tied to a ship by a worker's session (the skipper's and a launcher's are left out); the
  log has no liveness field, so "live" is read as the ship being open, from its Run's creation.
- G3 starts on the dispatch host that never reach a first prompt — dispatch logs cut into starts at
  their `== exit` lines, a start failed when it says `FAILED: never busy` and exits 3, read on the host
  that runs the dispatched sessions (over ssh when it is another Mac), this Mac's beside it.
- G4 live lines of the layer — `wc -l` over the evidence doc's section 2 files.
- G5 old words in live files — the rename doc's S8 grep, counted, until `bin/test_vocabulary.sh`
  exists (the line says it is the interim read).

A read that cannot be made prints `not measured — <why>` (the host unreachable, no worker session on
record, a file list missing): carry that line, never a 0. Judge the build by them: when G1 does not grow
or G3 stays above 0 for two runs, say so in the entry's For <owner>.

Say plainly whether each number moved since the last run. If a month of runs moved none of
them, say that the layer is the wrong lever.

The usage rows come from plumb's usage-report; the last seven daily reports are in `<reports>`
(`where` names it; MISSING: say so in the finding and go on) on the Mac that renders (a cloud-drive
copy is for <owner>, and a launchd job cannot read the drive). Read their headlines and the "Levers" table of the latest one, and give the
week's usage one finding: where the budget went, whether a limit or the extra-usage cap was reached and
what was running when, and which lever moved. Numbers from the reports, never recomputed (the layer's
usage-report record, D2).

Then the model routing (the layer's docs/record/model-routing-2026-09-30.md section 7, D8):
`<regatta> usage-report numbers` prints the week's tier mix — $ and share for main sessions by model,
`worker`, `sr-worker`, `architect`, `reviewer`, other agents — the Fable-in-main line, and WRONG per 100
changed lines for branches built with a `worker` against the rest, each with its n. Copy them
into Numbers. A **bench trigger** is a PROPOSE item naming the bench (B1, or B2 once B1 has
passed) with its budget from section 7, raised when any of these holds:
- a new Claude model or a price change shipped since the last run (step 1's changelog and
  pricing pages);
- worker-built WRONG per 100 lines exceeds the rest by more than 0.21 (the bench's noise
  figure) — say the n on both sides; under 5 branches a side, WATCH instead;
- Fable in main sessions outside the weekly skills exceeds 10% of the week's spend — judged only on
  a week that starts on or after 2026-10-05, when the routing took effect; an earlier week is a
  WATCH line (the 2026-09-28 week read 17.8%, nearly all from before the change).

The 0.21 margin, its unit (it was the reviewer bench's recall spread, not a WRONG-per-100 figure),
the 5-branch floor and "outside the weekly skills" are S-E's readings of D8, open for <owner> in the
design record's open items.

None fired: one line saying so. Reading these costs nothing; the bench itself runs only on
<owner>'s answer, never in this pass.

## 4. Write the entry

`sextant/<yyyy-mm-dd>.md` in the worktree, in exactly this shape: title with the date; a
one-line numbering legend; **Numbers**; **Findings** (F1…, each: what, source links, verdict
with reason); **Implemented this run** (what went into `-changes`, marked *launching reviewed*: the entry
launches first); **For <owner>** (a "Do this now" list first — anything
to paste or run — then open decisions); an empty **Feedback from <owner>** heading for <owner> to
fill in. Under 200 lines; detail lives in the sources.

Append one line to the worktree's `log.md`
(`- yyyy-mm-dd sextant: N findings, K adopted, <the one thing that matters>`), then launch it —
the check, the pull request and the merge are one call; write the worktree path out in full:

```bash
<regatta> knowledge-commit <layer-name> --in <the path --open printed> -m "Sextant: <date> — <the one thing that matters>"
<regatta> knowledge-commit <layer-name> --in <the -changes path> [--review <report>] -m "Sextant: <date> — adopted: <what>"
```

The entry's worktree holds records only and launches on the check. The second one does not.
Anything but a record (`docs/`, `lessons/`, `sextant/`, `log.md`, `README.md`, `TODO.md`) launches only reviewed (the layer's coding-on-workflow record, D1). Run it without `--review` first: `NOT launched — unreviewed` (`NOT landed` before rename S3) names a diff file. Spawn the `reviewer` agent (`model: "opus"`) on that file, briefed as the refusal says — from another repo the name resolves to that repo's reviewer — fix its WRONGs, save its report in a scratch file, and run the same line again with `--review <report>` after the path.

A `NOT launched` (or `NOT landed`) line means nothing merged: report it in step 5 with its reason. Under
aurora's `weekly-run`, the launcher launches an entry the run left behind and names a `-changes`
worktree still unlaunched, which waits for a reviewed `--in` or `/finish`.

## 5. Report

In chat: the three most consequential findings in one line each; what was implemented; what
is waiting on <owner>. Then stop — the entry is the deliverable, not the chat.
