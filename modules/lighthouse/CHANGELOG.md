# Changelog — lighthouse

## 0.1.0 — 2026-10-19

- First cut, moved in from the overlay: `bin/health`, `claude-settings`, `account` with
  `shell/cc.zsh`, `publish`, `trust-projects`, `tiling`; the hooks `account_guard.py`,
  `secrets_guard.py`, `design_route.py`, `tool_path.py`; their suites. Every private value
  (registry, declared settings, shares, vaults, hosts) comes through the config dir's
  `lighthouse/` keys (README, "Private values"); a missing peer (wharf, atlas, plumb) is a
  printed fallback, never a stack trace.
