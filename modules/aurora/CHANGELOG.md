# Changelog — aurora

## Unreleased

- `capped` (2026-10-21): the signal handlers go in before the session's `Popen`, so a TERM in
  between is passed to the group, not lost with the wrapper (under load, 3 of 200 early TERMs left
  the group running before, 0 after), and one held before the session starts stops the wrapper
  without starting it; a group left with one zombie (EPERM on macOS) is polled until the reap,
  or counts as gone at the TERM and the SIGKILL, not a traceback and exit 1 (about 1 loaded run
  in 4 before); a second signal during the 15 s grace no longer restarts it.
- The wharf rename's S6 (2026-10-20): the launch word in `/aurora`'s sections and `/embark`.
- Carried from the overlay (the wharf rename's S5, 2026-10-20): the launch word in `weekly-run`
  (`launched_entry`, `charts_launch`, its log and bulletin lines); `quiet_week` reads only the
  `probably launched` group (M22).

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
