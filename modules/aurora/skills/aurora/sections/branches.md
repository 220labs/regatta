# Branches — Aurora's weekly section (Sundays, before dream)

The week's look at every idle `claude/*` branch with real work that is not on `main`: code
classifies it and archives what it proves superseded; this section writes one line of judgement
per branch code could not settle, so Monday's list is short and each line has a verdict
(the layer's docs/record/branch-reaping-2026-10-04.md section 5, E10;
docs/record/aurora-sequence-2026-10-04.md D2). **It writes one file and its log line, nothing
else — never an archive, a deletion or a `pickup` verb that writes** (branch-reaping D3 = B: a
drop verdict waits for the owner). `<regatta>`, `<vault>` and the rest: the aurora skill's
"Where things are".

## 1. Gather

Unattended, `bin/weekly-run`'s classify step ran the classifier minutes ago — fetch, survey,
`--reap` of C1 and C2 — and kept its report: read `<logs>/<today>-branches.txt`, or
yesterday's when the run started before midnight. A quiet week — no C3–C6 line, nothing
probably launched — never reaches this section: `weekly-run` writes its log.md line itself.
Missing (a hand run, or the step failed — its `FAILED classify` line is in the night's log),
run it yourself, without `--reap` — this section never archives; C1/C2 wait for next week's
classify step:

```bash
<regatta> repos --branches --fetch --classify
```

Per repo the report has the survey groups (`probably launched`, `not on main`, `archived`) and
then `classified`: one line per idle branch that is not launched — `empty` (the session start
reaps it; not this section's), or `C1`–`C6` with the facts, a C1/C2 line ending in
`— archived: …` or `— not archived: <why>`. C7 (touched within 7 days) is only counted.

## 2. Judge — one line per C3–C6 branch

For each, read its last prompts — `<regatta> pickup show <branch> --repo <the repo's checkout>
--no-fetch` — and nothing heavier (no transcripts). Write one line: what the branch is, why it
sits in its case (the fact from the report that put it there), and the verdict: **pick up**
(`/pickup <topic>`), **drop**, or **wait** for `<branch>` to launch.

- C3 carried or hinted: where its work lives on ("in `<branch>`, open" or "launched, then
  edited: N % of its lines remain"); default wait or drop.
- C4 PR closed unmerged: the close date and the share of its lines on `main`; default drop.
- C5 doc launched elsewhere: read both docs, name the file that carries it; drop or pick up.
- C6 abandoned real work: what it is, its last prompt, its files; pick up or drop.

## 3. Write — only when something waits

`<vault>/dreams/<yyyy-mm-dd>-branches.md`, beside the dream, which points here.
No C3–C6 branch and nothing under "B would have archived": no file (a quiet week costs the
owner nothing).

```markdown
# Branches — <date> (<n> judged, <a> archived by code, <c> live not listed)

Numbering: P-items, one per branch, in the dream's style. Each ends in `➤ Answer:` pre-filled
with the verdict — leave it to accept, overwrite it to change. Nothing here is archived by this
file: a drop that the owner keeps is applied at /embark.

## Archived by code this week
<per repo, the C1/C2 lines that end "— archived:", with the restore line the report printed;
"none" when none>

## P — one per branch
P1. <repo> · <branch> — C<n> <case name>: <what it is>; <why this case>
    ➤ Answer: <pick up (/pickup <topic>) | drop | wait for <branch>>
...

## B would have archived
Aurora D2 (the owner, 2026-10-04): the night stops at launched, empty and proved superseded; these
are what option B would also have archived — listed so the line can move on evidence, never
acted on. One line each: <repo> · <branch> · probably launched: <the hint> | PR closed <date>,
<share> % of lines on main (P<n>).

## Feedback from <owner>
```

## 4. Record

- Append to `<vault>/log.md`, also in a week with no file:
  `- yyyy-mm-dd branches: <a> archived by code, <n> judged (<drop> drop, <pick up> pick up, <wait> wait), <b> would be archived under B`.
  `bin/weekly-run` reads this line on `main` as the proof the section ran.
- Commit: `<regatta> knowledge-commit <vault-name> -m "Branches: <date>"` — `dreams/` and
  `log.md` are vault records, written in place.
- A step that fails: say so in the output, post one bulletin line —
  `<regatta> bulletin.py --post "Aurora's branches section failed" "<what it left undone>"` —
  and stop; the dream still runs in its own session. Keep that why word for word: `weekly-run`
  finds it and posts no second line of its own.
