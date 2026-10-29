# modules/keel — the D-list

Read `README.md` first: it is the chart. For an agent:

- Public since its scrub (2026-10-22): every file is on `.helloworld/allowlist.txt`. Mermaid is
  fetched into the cache, never committed (`vendor/mermaid/README.md`: the gate's word list matches
  inside the minified code). A name, host, repo or overlay path is a config key (README, "Private
  values"), never a literal; a suite's fixture is synthetic (`tests/config.sh`).
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
  macOS, which sees a flock; /proc/locks on Linux; lsof elsewhere). Its run (S5, `lookout_gone`) writes a `dispatching`
  row before `pickup seed`, so a pass that dies mid-start or a failed dispatch never starts the
  same answer twice. Since routed comments S3 no host is special (`run_where`): a branch is acted on
  where its run is (harness list, the queue's `running_on`), left to the host its run is on, and with
  none in sight claimed, then a pass later seeded off its tip (`pickup seed --beside`), never written;
  dispatch places the run (no `--on`). A rule-3 start therefore takes two passes in a case: the claim's,
  then the start's (`LOOKOUT_CLAIM_PASS=0` drops only the wait between them). `tests/test_lookout.sh`
  stubs hail, harness, pickup, dispatch, dispatch-queue, autofinish and spacesheep; nothing there may
  reach a real one, and a suite that runs the lookout without `LOOKOUT_DISPATCH_QUEUE` set asks the
  Mac's real queue.
- `skills/figure/` is private-first, off the allowlist until its scrub: its example names a host and a
  person. `bin/keel`'s figures section (render, safe_svg, restyle) is public; the skill loads keel as a
  module for the style table and the text measure, so the two never disagree.
- `keel render`'s cases (tests/keel.sh, "figures") run Chrome on a Mac outside CI only; the
  Excalidraw half also needs the library in keel's cache folder (the first render fetches it) and says
  so when it skips. Chrome is started without `--user-data-dir`: with a fresh one it did not exit
  on one of the Macs (2026-10-23).
- check: `bash modules/keel/tests/check.sh` (on a Mac: some cases read the overlay's peers).
