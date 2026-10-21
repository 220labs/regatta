# Changelog — wharf-runs

## Unreleased

- The wharf rename's S6 (2026-10-20), carried from the overlay: the launch word in `/later`, `/move`
  ("the arrival" for a move's own landing) and `/pickup`.
- `test_wharf` finds helm's console and the old `bin/plan` each where it lives: `libexec/helm` in helm's
  module (B12), the overlay's S5 shim for `plan`; without that shim the old names are skipped, said.

## 0.2.0 — 2026-10-20

- The unattended runs move in (B7): `dispatch`, `dispatch-rc`, `run-seed`, `harness` and its adapters,
  `rc-hosts`, `autofinish`, `autofinish-run`, `pickup`, `blueprintlib`, `wharf`, `check`,
  `hooks/cold_prompt.py`, the skills `/autofinish`, `/later`, `/move`, `/pickup`, and their suites.
  Private until the module's scrub.
- They find the core by `lib/core_path.py` and their peers through `common.tool()`; the registry is
  the core's `repos_json()` (`autofinish` keeps `AUTOFINISH_REPOS`). Without lighthouse's `account`
  a run starts on the one login (G12); without helm's `ask` and `helm` a run's prompt drops their
  lines (G22). `install.sh --schedule` writes the autofinish sweep's agent; `bin/check` with no
  checkout named checks the caller's.

## 0.1.0 — 2026-10-19

- First piece, moved in from the overlay's history: `orca-host` and its suite. The pairs and the
  ssh aliases come from the config dir (`wharf-runs/orca-pairs`, `wharf-runs/ssh`), the registry
  from the core's `repos_json()`, `scopes` and `account` through `common.tool()`; `setup` without
  `account` skips the sync and says so.
- Against the original: `check` and `setup` print their whole report when a peer tool, the
  registry or a key is missing; host names compare lower-case; the app's bundled CLI is preferred
  to any `orca` on PATH; `--on … pair --link -` checks the link here before ssh; a dry `--on`
  pair keeps the clipboard; a pairing code or registry of the wrong shape is an error, never a
  traceback; the projects folder is resolved as Orca records it; `config-keys` names both keys
  for `regatta check`.
