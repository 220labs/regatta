# Changelog — regatta (the core)

## Unreleased

- The private values come from the config dir, one file each, with a neutral default where one
  is absent: `regatta/owner` (the closing lines' address, the say-so the gate and Jev ask for,
  `/autofinish`'s `by`), `regatta/guarded` (`jev.GUARDED`), `regatta/orca-deny` (`ORCA_ROW`'s
  deny list), `regatta/log-dir` (jev's and the gate's logs), `regatta/projects` (`secrets`).
  Jev's second key file is `regatta/.env.fallback`. README, "Private values".
- With an overlay installed (`legacy`), a missing key is an ImportError naming each (fail
  closed); with or without one, so is an unreadable key or a relative path key. `regatta check`
  reports them. Jev loads the core under a private name, never `import common`. One reader for the core
  and Jev (`config_read`), one projects folder (`common.PROJECTS`) and log folder (`LOG_DIR`).

## 0.1.0 — 2026-10-17

- First cut: `common.py`, `gate`, `jev`, `cost`, `secrets` moved in, with discovery (`tool()`,
  `regatta_root()`, `repos_json()`, `guarded_repos()`), the config directory for private files,
  and the `regatta` CLI (`root`, `has`, `which`, `check`, `shim`, `regatta <name>`).
