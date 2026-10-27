# Changelog — regatta (the core)

## Unreleased

- The gate's confidential stopgap (2026-10-26): `classify` treats a repo of any confidential scope as
  a guarded source for every vendor but Anthropic, so Jev (review-gate's same-shadow) or Codex gets its
  text only on the owner's per-vendor quote; a torn registry guards every source. The rule is
  `jev.confidential()`, and `jev.ask` applies it too, so a bench's direct call is refused alike; it also
  guards an unknown source (none, `?`) while a scope is confidential, a folder holding a confidential
  checkout (the projects folder, a group folder), any case of a name, and reads the registry once.

- `claude_host()` (orca-launcher S4, 2026-10-25): whether this process's responsible process, the one tccd
  charges, is claude-host — read from the kernel, 0.4 ms; `REGATTA_CLAUDE_HOST=0|1` pins it. The core's check
  gains G4: each hook reader runs under an `open` audit against a stand-in drive and fails naming the line
  that opens a Drive-backed file outside claude-host (main's readers: 5 of 5; this branch: 0).
  `drive_backed(p)`: whether a config key is a link into a cloud drive (macOS's File Provider folder, or
  `REGATTA_DRIVE_ROOTS`), judged from the link's text; only such a key is read local-first.
- The weekly jobs' host rule (2026-10-24): `common.weekly_host(job, scope=None)` is the one copy of the
  rule weekly-run's `HOST_RULE` and sextant-run's `host_rule` held, kept in step by two suites until
  now; `regatta weekly-host <job> [--scope <scope>]` is the installers' face (exit 0 run, 3 skip, 4
  refuse, 5 closed). `regatta check` reports an `aurora/host` that names no host or several, or a host
  `lighthouse/hosts` does not list where that key exists, as it checks yards, or one no host name can
  be (outside `[a-z0-9-]`). A dangling `aurora/host` link refuses, never reads as no key. The rule's
  branches are this suite's cases now.
- `regatta flare` and `/regatta:flare` (2026-10-24): a bug report, an idea or a question filed as an issue on
  the public repo, the evidence attached, a `--client-id` retry returning the first receipt, helloworld's
  file scan before the send, a prefilled link without `gh`; the repo's Bug and Idea issue forms beside it.
- spacesheep plans (spacesheep-tiers, 2026-10-24): `sheep_plan()` reads the account's plan through
  `spacesheep talk status`, cached an hour in `LOG_DIR/sheep/plan.json` (no CLI is the plan `none`, an
  unknown plan is budgeted as Free); `sheep_record()` and `sheep_count()` keep this Mac's 24-hour deploy
  log, shared by keel and helm; `sheep_budget()` gives each its line (helm stops at 75 %, keel warns at
  90 % of the cap divided by `sheep/machines`, else the hosts `lighthouse/hosts` lists, else 1); `sheep_talk_refusal()` and `sheep_cap_line()`
  are the words. `REGATTA_SHEEP_DIR` and `REGATTA_SHEEP_PLAN` stand in for a suite; a stand-in CLI
  (`MEMO_SHEEP_BIN`) with no sheep dir of its own reads and writes nothing. A failed plan read keeps the
  last good plan; a cap refusal is logged with its retry (`sheep_refused_until()`); the log keeps 25 h, pruned
  by a rename about once a day; `sheep_plan_words()` says a plan never read as "Free, as far as this Mac knows".

- `extra_usage(xu)`: a usage answer's paid-overage object in one parse, for plumb's usage-report and
  lighthouse's account (costs S8, 2026-10-24).

- `hooks/transcript.py`: one reader of a session transcript's last main-chain call (`call`, `call_line`, `last_call`: epoch, model, context; skips sidechains, `<synthetic>` and zero totals). wharf-runs needs it.
- A closing kind of its own for the hand-over (2026-10-25, yolo-launch review D1-B): `handed`, a
  WAITING FOR SOMETHING line whose what is dispatch's launch, `HANDOVER_LINE` or the two free forms
  of 2026-10-24 (`HANDED_WHAT`). dispatch launches on it, dispatch-rc ends the run on it, and helm
  raises a declined launch instead of retrying the build.
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
