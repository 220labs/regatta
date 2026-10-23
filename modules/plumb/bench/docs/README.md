# bench/docs — what predicts whether the owner answers a design doc, how fast, and whether it gets built (2026-10-14)

Written by a `worker` (Sonnet 5.5 `high`) for the design-doc family design,
[docs/design-docs-2026-10-14.md](../../docs/design-docs-2026-10-14.md); its findings and caveats are section 3 of
[docs/design-docs-research-2026-10-14.md](../../docs/design-docs-research-2026-10-14.md). Same conventions as
[bench/decisions](../decisions/README.md): Python 3.9, stdlib only; **data lives outside git**, by default under
`bench/docs/` in the core's log dir (`BENCH=DIR` moves it) — the transcript index quotes the owner's typed turns and
the doc table names every repo's docs, guarded ones included. Not in the repo's check: a measurement, re-run by hand.

Order: `tindex.py` (an index of the owner's typed turns from the transcript archive, about a minute) → `docs.py` (one
row per doc that `bin/memo list` knows, one per D-item; hand-over and first-answer times from git and the index)
→ `analyze.py` (the aggregates, `tables.md`) → `analyze2.py` (chat-vs-doc answers and the review-gate join,
`tables2.md`); `stood.py` shows where `memo stand` has run. `docs.py` imports `bin/memo`'s parser, so a decision
here is exactly what `/memo` sees.

```bash
cd modules/plumb/bench/docs
python3 tindex.py
python3 docs.py
python3 analyze.py
python3 analyze2.py
```

`words/` holds the scripts that mined the owner's own words on docs and decisions (section 4 of the research record):
`extract.py` → `human.py` → `grep.py` / `quotes.py` / `answers.py` / `fb.py` / `counts.py`. They write their
intermediate files beside themselves — run them from a copy outside the repo, never here, and delete the
intermediates after (they hold transcript text).

Approximations that bound every number (section 1 of the report): `/finish` squashes the doc and the answers
into one commit, so answer times exist for 69 of 113 answered docs; the kept/overruled split is a letter/word
heuristic; two populations of docs exist (old shape with a pre-filled `➤ Answer:`, new shape empty), and
anything that depends on "answered" is measured on the new shape only.
