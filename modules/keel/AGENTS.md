# modules/keel — the D-list

Read `README.md` first: it is the chart. For an agent:

- Public since its scrub (2026-10-22): every file is on `.helloworld/allowlist.txt` but
  `vendor/mermaid/mermaid.min.js` (helloworld's word list matches inside the minified code; its
  README says what a public install sees). A name, host, repo or overlay path is a config key
  (README, "Private values"), never a literal; a suite's fixture is synthetic (`tests/config.sh`).
  The vaults whose secrets folder `sheep_gate.py` and `owed` keep closed come from the
  `lighthouse/vaults` key only; `tests/owed.sh` uses `vault-a` and `vault-b` (the owner's hand edit,
  2026-10-23: the secrets guard refuses an agent's edit of a line naming a real vault's secrets path).
- The core is found by `lib/find_core.py`; a peer in another module through `common.tool(name)`,
  never a path beside this file, and each such call takes the fallback the README names on None.
  Same-module loads (`sheep`, `hooks/sheep_gate.py`, `vendor/mermaid`) stay beside the file.
- The overlay keeps source shims at its old paths (`bin/keel`, `bin/memo`, `bin/paste-paths`,
  `bin/owed`, `bin/sheep`, `hooks/doc_answers.py`, `hooks/sheep_gate.py`): every caller that
  loads one as a module or runs it keeps working. Edit here, never the shim.
- `tests/keel.sh` runs alone: it races under load ("a wait wakes on a Save a pull drained" is a
  known flake). Its headless-Chrome case is bounded at 90 s and skips when Chrome never returns.
- The lookout (crosstalk S3, `docs/crosstalk-2026-10-20.md`) never takes a `sheep wait` lock to test
  it: a `LOCK_EX|LOCK_NB` take ends a wait starting that instant. `lock_held` reads it (F_GETLK on
  macOS, which sees a flock; lsof elsewhere). Its run (S5, `lookout_gone`) writes a `dispatching`
  row before `pickup brief`, so a pass that dies mid-start or a failed dispatch never starts the
  same answer twice; from the laptop it names no host (dispatch's own Where default), and it leaves
  another host's GitHub answer to that host's lookout. `tests/test_lookout.sh` stubs hail, harness,
  pickup, dispatch, autofinish and spacesheep; nothing there may reach a real one.
- check: `bash modules/keel/tests/check.sh` (on a Mac: some cases read the overlay's peers).
