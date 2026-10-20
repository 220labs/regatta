# Changelog — wharf-runs

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
