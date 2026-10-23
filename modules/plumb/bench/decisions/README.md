# bench/decisions — can a model tell which decisions the owner will overrule? (2026-10-02)

Design, pre-registration and results: `docs/record/jev-pipeline-2026-10-02.md`. The corpus is every
D-item ever put to the owner in the repos (`➤ Answer:` lines), labelled from git history with the
recommendation an agent pre-filled and the answer the owner left. Arms: TypeSafe's Jev (a
decision-only model, `jev.py`) against Claude models asked the same question headless
(`baseline.py`). Same state, same three questions (`questions.py`), scored by `score.py`.

Order: `corpus.py` → `jev.py` (needs `TYPESAFE_API_KEY`) and `baseline.py --arm …` → `score.py`.

**Result, 2026-10-02:** Opus 5.5 `medium`, Haiku 4.5, Fable 5.1 `high` and Jev 1.13 all predict
which items the owner writes on at chance — AUROC 0.39–0.50 on the first 139 known items, and still
at chance after the owner's review sheet (`corpus.py --review`, numbers in the doc's F14); Jev's
whole run cost $0.0104. The two-line rule — apply two repos' docs, ask the rest (`score.py --apply`) — and what
it is worth are in the doc; the review sheet changed them. Touching is a per-document, per-project behaviour, so the
item-level question had no item-level answer. Two lessons for the next bench, learned here:
define the label at the level where the behaviour happens, and run the trivial baseline before
any model — three models agreeing (Spearman 0.64) was not three pieces of evidence.

**Data lives outside git**, by default under `bench/decisions/` in the core's log dir
(`--bench DIR` or `BENCH=`): the corpus quotes every repo's docs, guarded ones included, so it is neither
committed nor put in the shared Drive. Every arm writes `pred-<arm>.jsonl` with the measured
cost and latency per item; all scripts pick up where they stopped.

Python 3.9, stdlib only; `corpus.py` imports `bin/memo`'s parser so a decision here is exactly
what `/memo` sees.
