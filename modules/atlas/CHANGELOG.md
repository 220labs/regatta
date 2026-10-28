# Changelog — atlas

## Unreleased

- `knowledge-commit` never ends a rebase it did not start: a rebase, merge, cherry-pick or revert open
  in the repo or the worktree refuses either form before it commits, and a failed rebase of its own is
  aborted only when its orig-head is the HEAD the run started from. Its push step's `rebase --abort`
  had ended a leftover rebase on the vault's main and dropped the commit it had just made (F6,
  2026-10-25).

- `vault_commit`'s push of the vault's main tries once more, from the fetch, when it is refused and
  origin moved meanwhile (another SessionEnd landing between the fetch and the push makes a
  non-fast-forward). The vault is rechecked clean before each attempt; a refusal with origin unmoved
  is reported at once, never retried.

- The dream line at session start counts keel's D-shaped items (`- **D3 — P3.`) as well as the old
  `P3.` lines, which it read as "0 proposals" for three weeks, and names the embark memo's `keel line`
  when aurora's `embark-latest.json` covers the newest dream (the 2026-10-18 dream's D2, fix a).

- `knowledge-commit`'s code launch no longer runs the layer's `hooks/test_checkpoint.sh`: the
  checkpoint hook's suite is wharf's, which regatta's own `check:` line and CI run, and the layer deletes its copy
  with its shims (B14b's prerequisites, 2026-10-24). Its hooks suite and `bootstrap.sh --check` stay.

- `bin/knowledge-home` (knowledge-layers S3, 2026-10-21): a confidential scope's memory in its
  knowledge repo, the rest in the vault — `where`, `adopt`, `init`, `check`; `tests/knowledge-home.sh`.

- The wharf rename's S6 (2026-10-20): the launch word in `/promote` and `/routine`.
- Carried from the overlay (the wharf rename's S5, 2026-10-20): the launch word in `knowledge-commit`
  (its exit helper is `launched`), `docs-index` and `tests/docs-index.sh`.

## 0.1.0 — 2026-10-19

- First cut, moved in from the overlay: `hooks/bulletin.py`, `vault_commit.py`,
  `archive_transcript.py`, `bin/knowledge-commit`, `docs-index`, `routine`, `skill-frontmatter`,
  `/share`, `/promote`, `/routine` and their suites.
- The two knowledge repos come from the config dir (`atlas/layer`, `atlas/vault`: a name and a
  path each); `knowledge-commit` takes those names or the role words `layer` and `vault`.
- Keel (the bulletin's Open line, docs-index's sets) and wharf (`knowledge-commit --in`'s pull
  request) are optional peers found through the core, each with a fallback (G19, G20).
- `docs-index` without `--repo` acts on the checkout of the current directory.
