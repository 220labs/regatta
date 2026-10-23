# bench/sessions — is this idle session done, waiting on the owner, or blocked? (2026-10-02)

The bake-off orchestration-landscape D10 asked for. Design, pre-registration, results and the
labelling sheet: `docs/record/jev-sessions-bench-2026-10-02.md`. Every interactive session of the
last 7 days on this Mac, the code rules first (`collect.py`), then Jev through `bin/jev` with
`source` = the session's repo, Haiku 4.5 and Opus 5.5 `medium` headless on the same battery
(`questions.py`, `arms.py`), scored against the owner's corrected labels by `score.py`, which also
carries the pre-registered keyword rule.

Order: `collect.py` → `sheet.py` (writes DIR/sheet.md and the pre-labels) → the owner answers the
sheet → `sheet.py --labels DIR/sheet.md` (stops on any answer that is not one of the labels)
→ `arms.py --arm jev|haiku|opus-medium` → `score.py --labels DIR/labels.json`.

**Result, week of 2026-09-25 (39 labelled sessions):** Opus `medium` 0.77, Haiku 0.74, Jev
0.72, the keyword rule 0.64, majority 0.59. Jev did not clear the pre-registered bar over the
rule (+0.08 against 0.10), so no model gates; `bin/pickup list` gets the rules and the bench
reruns on week two. The rules live once, in [bin/session_status.py](../../bin/session_status.py):
pickup prints them, `collect.py` and `score.py` import them (2026-10-04), so the bench scores
what the owner sees.

**Data and the sheet live outside git** (`bench/sessions/` in the core's log dir, `--bench DIR`
or `BENCH=`): the texts quote every project and the sheet quotes their tails. Sessions from
a guarded repo (the registry's `guarded`), the projects root or anywhere outside it — by
slug or either cwd, by path prefix — are collected but go to no model and no sheet (AGENTS.md's
Jev rule). Two reached the models before the guard was right; the doc's F0 records them.
Python 3.9, stdlib; `bin/jev` logs each call to `jev.jsonl` in the core's log dir.
