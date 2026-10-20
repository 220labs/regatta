# Changelog — regatta (the core)

## Unreleased

- `regatta check` also reports a module's own private values, listed in its `config-keys`:
  unreadable, or missing where an overlay is installed. The core's import never refuses on them.
- The private values come from the config dir, one file each, with a neutral default where one
  is absent: `regatta/owner` (the closing lines' address, the say-so the gate and Jev ask for,
  `/autofinish`'s `by`), `regatta/guarded` (`jev.GUARDED`), `regatta/orca-deny` (`ORCA_ROW`'s
  deny list), `regatta/log-dir` (jev's and the gate's logs), `regatta/projects` (`secrets`).
  Jev's second key file is `regatta/.env.fallback`. README, "Private values".
- With an overlay installed (`legacy`), a missing key is an ImportError naming each (fail
  closed); with or without one, so is an unreadable key or a relative path key. `regatta check`
  reports them. Jev loads the core under a private name, never `import common`. One reader for the core
  and Jev (`config_read`), one projects folder (`common.PROJECTS`) and log folder (`LOG_DIR`).
- The land→launch rename's readers take both words: `DECLARED_LINES`, `RUN_LAUNCHED` (with
  `RUN_LANDED` kept as its old name: launched and landed lines alike), `LAUNCHED_OUTCOMES`,
  `REFUSED`, `NOT_LAUNCHED`, `REFUSED_GATES`. No writer or message changes in this step.
- The rename's messages: `autofinish_outcome` and `autofinished_phrase` say "launched as #N" for
  either outcome word, and the prose says launch and skipper. `HOLD_NOTE` keeps its text: open PRs
  carry it and are matched as exact text inside the body. No writer changes (`RUN_END`'s outcome is the caller's).
- The rename's writer step (S4, the core's half; the overlay's launcher and skill are the other):
  `DECLARED_LINE` is now `DECLARED_LINES[0]`, "IT LAUNCHES BY ITSELF."; the old line stays second,
  so `CLOSING` still reads it until S8 drops the aliases. Landed after the overlay's half, which accepts either line.

## 0.1.0 — 2026-10-17

- First cut: `common.py`, `gate`, `jev`, `cost`, `secrets` moved in, with discovery (`tool()`,
  `regatta_root()`, `repos_json()`, `guarded_repos()`), the config directory for private files,
  and the `regatta` CLI (`root`, `has`, `which`, `check`, `shim`, `regatta <name>`).
