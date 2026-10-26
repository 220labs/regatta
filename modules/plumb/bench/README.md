# bench/ — model benchmarks on this machine's own work

**Which model takes a gate** (the owner, 2026-10-02, D6 of `docs/record/jev-pipeline-2026-10-02.md`):
data-driven, on a benchmark over our own data. A gate goes to Jev — or any cheaper model —
when it beats Opus or Fable on precision and recall, or matches them within the measured
interval and costs less in money or plan tokens; otherwise the Claude model stays. Two
lessons from the first Jev bench (`decisions/README.md`): define the label at the level where
the behaviour happens, run the trivial baseline before any model — and read an answered sheet
line by line, never by its arrow lines: two benches on 2026-10-02 scored the wrong labels
before a reviewer caught it.

- `builders/` — which model and effort builds a specced task: an arm rebuilds a landed task from its brief, graded by the landed tests (2026-10-24)
- `decisions/` — can a model tell which decisions the owner will write on (2026-10-02)
- `sessions/` — can a model tell a session's state from its transcript (2026-10-02)
- `docs/` — how the owner reads and answers docs: a measurement, re-run by hand

Two runs moved out as records (the plumb scrub, 2026-10-22): the design run of 2026-10-04 and the
reviewer model bench of 2026-09-29, both bound to the owner's repos and cases. They are in the
private repo's `docs/plumb/`, never published.

A folder of captured model output is evidence, kept as written: add it to `NOT_LIVE_DIRS` in
`bin/docs-index` (else `relink` rewrites its paths), and save any captured doc with a D-list as
`.md.txt` (else the checkpoint hook mirrors it as a page for the owner to answer and `branches.py`
counts its D-items as open; both happened on 2026-10-04).
