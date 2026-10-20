# Changelog — aurora

## 0.1.0 — 2026-10-19

- First cut, moved in from the overlay: `bin/weekly-run`, `bin/week-digest`, `/aurora` with its
  three sections (branches, charts, dream) and `/embark`.
- The core, every peer and the two knowledge repos are found, never named: the core's CLI beside
  the module or through the config dir's `home`; atlas, wharf and plumb through `regatta which`
  (`common.tool()`), each missing one failing only its own step; the layer and the vault from
  atlas's config keys. `weekly-run where` prints them for the skills.
- The second Mac's skip is the config key `aurora/skip-hosts`; with the overlay installed and
  the key absent the run refuses.
- The charts section writes no chart for a topic whose code moved into a module: its chart is
  the module's README.
- `install.sh --schedule` writes the nightly launchd job for an install without an overlay.
- The branches verdict that takes a branch back up is now "pick up", as `/pickup` says it.
- From the landing review: a core that is present but does not load (a key missing beside an
  overlay) refuses the night, as does an unknown host when `aurora/skip-hosts` lists any; the
  key's lines are stripped as the core strips them; `config-keys` lists it for `regatta check`;
  `install.sh --schedule` refuses on a listed host; `<regatta> pr ready|merge` is denied like
  `bin/pr`; the `where` allow rule is pinned to the skill dirs; a missing `pr` or `branches.py`
  fails its own step instead of pushing a PR-less branch or reporting a false UNLAUNCHED.
