# Changelog — atlas

## Unreleased

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
