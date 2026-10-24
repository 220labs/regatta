# Changelog — regatta (the core)

## Unreleased

- The list's cases moved to `tests/classes.sh`, on `autofinish_exclude` (autofinish-exclude landing review,
  2026-10-24): class 1's walk follows a shell's `$(tool x)` (weekly-run's tend), and a class-2 walk fails on
  any import of a leak gate's that is off `autofinish_leaks`.

- The overlay marker `regatta/overlay` is the only one (B14b, 2026-10-23): `overlay_root()` reads it
  (`legacy_root` is its old name), the `legacy` file and `REGATTA_LEGACY` are read by nothing, and
  `tool()` no longer falls back to the overlay's checkout. `regatta check` fails on a `legacy` file
  with no marker, whose keys would otherwise fail open.
- `regatta check` reports a primary hookwatch pinned (autofinish-exclude S4, 2026-10-23), from
  `lighthouse/hookwatch.json` in the config dir, as a finding.
- The core's check derives class 1 (autofinish-exclude S1, 2026-10-23): it walks what the eleven judges
  import or exec and fails on a file off `autofinish_exclude`, and prints the week's landings the list
  held (G1). The coverage case no longer counts a `libexec/` file live by itself; the class-1 walk does.
- `read_registry(path)` (2026-10-23): the registry and registry_unreadable's verdict from one parse;
  `scope_of_repo(..., reg=)` takes the parsed registry, so a caller judging the tear reads one file once.
- `gather_fence(scope)` and `scope_match(scope)` (knowledge-layers S4, 2026-10-22): what a Gather
  reader may do with an item, by the paths it came from — `quote`, `fenced` (a confidential scope's:
  count it, never quote it) or `outside` (not the scope asked for); a scope's folders matched by
  path or by slug folder name under any `projects/`; an unreadable registry fences everything.
- `scope_yard(name)` and `scope_yards()` (skipper-resilience S2, 2026-10-22): a scope's `yard`, the
  host that drives its ships, `None` for absent or `null`; `regatta check` prints one row per scope,
  its yard or none, and counts a yard `lighthouse/hosts` does not list as a finding.
- `repo_key` and `scope_of_repo` (skipper-modes S1, S6): a path or key to its registry key, and the
  scope that lists it with its data (`mode`, `berths`); `regatta check` names a scope's berth that no
  repo is cloned on, or berths that are no list.
- A third waiting line, `PENDING_PREFIX` (`THIS SESSION IS WAITING FOR SOMETHING — <what>`), a
  `pending` kind in `CLOSING`: the session waits on its own work and carries on by itself, so the
  owner has nothing to do. It is no ask (`unrelayed_ask`, `asks_answers` skip it); keel's Stop lint
  blocks one that asks, and a WAITING FOR YOU line that says there is nothing to do.
- Scopes' one reader (knowledge-layers S1, 2026-10-21): `scope_registry()`, `scope_members()`
  (globs matched), `scope_of_key()`, `confidential_scopes()` (a scope with `"confidential": true`),
  `scope_login()` (the label its runs start on), `confidential_roots()` (each flagged repo's
  checkout, no git call, for hooks), `login_dirs()` and `scope_paths(scope)` — a scope's checkouts,
  their worktrees, transcripts folders and each login's slug folder (transcripts and memory), the
  paths the fence keeps out. Never raise, a malformed scope included; an unreadable registry reads
  as no scopes, and `registry_unreadable()` tells a fence so, to fail closed on it.
- `regatta shim --deny-prompt <path>`: `--deny`'s shim, and with no core a UserPromptSubmit in a
  secondary login dir (`CLAUDE_CONFIG_DIR` set) is blocked too. Made for lighthouse's `account_guard`
  (B9 review: its `--deny` shim let every prompt through where the overlay's old hook blocked); `--deny`
  keeps letting a prompt pass, as checkpoint's B5 choice wants. The deny shims' repair (`git -C <dir>
  fetch` / `pull --ff-only`) no longer takes a word starting with a dash, so `--upload-pack <program>`
  is refused.
- `regatta shim --deny <path>`: a deny hook's source shim. Run as a hook with no core to load
  from, it denies a PreToolUse call in one line and exits 0 instead of dying with exit 1, which
  Claude Code reads as no objection (C4); imported, it raises as the plain shim does. Made for
  wharf's `checkpoint.py` (B5). The plain shim's text is unchanged. Any load failure denies, a
  conflicted pull's SyntaxError or an unreadable file as well as a missing core; a plain
  `git -C <dir> fetch` or `pull --ff-only` passes, so a stale checkout is repaired from the session.
- `regatta shim --hook <path>`: any other hook's shim. Run with no core, one line on stderr and
  exit 0 (C4's quiet exit), where the plain shim's traceback and exit 1 showed at every session
  start. For wharf's `sync.py`, `branches.py`, `carried.py` and `worktree_allow.py` (B5).
- `common.tool()` never raises on a plugin registry of the wrong shape: it reads none.

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
