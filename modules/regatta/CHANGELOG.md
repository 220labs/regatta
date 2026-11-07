# Changelog — regatta (the core)

## Unreleased

- `regatta limit` supports lighthouse's `overdraw-max` login limit and notes its overdraw-only effect.
- `ready_pr` releases build CI's owned hold as well as the draft fallback's, spending either
  ownership note once so later manual holds remain in place.

- Plain live limit values retain colons through their trial read and `--all`/`--on` targeting, so five positional builder weights can override named base weights.
- `regatta limit` supports lighthouse's `week-max-finish` login limit and reports its finish-only
  effect. The core carries one-use finish receipts between launchers and account picks without
  passing them to sessions; `run_group` can pass the receipt descriptor through a timed probe.

- `scope_rotates(primary, reg)` (scope-rotation, 2026-11-04): the coins' one scope rule, which both rotation fences ask — a repo
  rotates when some scope lists it and every scope that lists it, each judged alone, has no `rotation` key or `rotation: true`;
  `rotation: false`, a `rotation` that is no bool, no scope or a registry it cannot walk fences. `confidential` alone no
  longer fences. `rotation_problem` names a `rotation` that does not read, and `regatta check` lists it as a finding.

- `launchd_session_keys()` supplies Background session keys beside `launchd_domain()` for jobs bootstrapped into a user domain.
- `hooks/transcript.py`: `machine_start(text)`, the one rule for a user prompt a launcher typed (dispatch's brief,
  autofinish-run's `/finish … --unattended`, a pickup tab's prefill and orientation, helm's skipper brief, a council
  arm, weekly-run's and sextant-run's `/aurora`, `/sextant` and `/embark`, a `Task:` brief or the gate's labelling
  prompt, hail's frame, dispatch-rc's nudge, clock's head, dispatch's `--probe`), anchored at the prompt's start so an
  owner's look-alike stays the owner's; a raw slash command is read as `/name args` whatever its tags' order. plumb's
  `asks` and aurora's `week-digest` read it. The core's check renders the launcher templates it can import or read (where
  their modules are in the tree: ten today) and fails on one the rule reads as a person's. An orientation that carries the owner's
  `--note` (`. Then: <note>`) stays the owner's.
- `host_name()` reads `wharf-runs/host` first (a builder host's row; absent everywhere else). `launchd_domain()`: `gui/<uid>`, or `user/<uid>` where `DISPATCH_LAUNCHD_DOMAIN` (else
  `wharf-runs/launchd-domain`) says `user` — a builder user's jobs (the Argon arm's S2). fence.py's builder keychain:
  `builder_signin_put` / `builder_signin_read` (a keychain file in a builder's home holding agy's item, its random
  password in a 0600 file beside it, every password and secret on `security -i`'s stdin), and `agy_secret()`, which
  `_home_agy`'s per-run keychain now reads: the builder keychain where the home has one, else the login's item.
- `regatta limit` carries each limit's history (limit-history): `set` and `unset` take `--why` (required, one line,
  in the row with the value before and after and the session id), print each host's last change before writing (the
  fleet's `limits.jsonl` rows and the overlay's last commit to the key's row), and refuse to undo a change under
  24 h old from another session unless `--over`; `get` and `list` show each value's last change on its line.
  The guard judges another session's newest change past this session's own, holds a host whose history will not
  read, and reads the overlay's upstream too (the finish review).

- `scope_yard_hosts(scope)` and `nodes_here(reg)` (scopes-node-yard): the hosts a scope may name as its yard —
  `lighthouse/hosts`, the fleet's Macs, plus, for a confidential scope, its own node: the peer of a
  `wharf-runs/nodes/<name>/` folder here whose `scope` names it and whose `ssh` is set, or this host itself where its
  payload's `wharf-runs/node/scope` names it (a node rendered before that key: its `wharf-runs/node/clones` on the
  registry's own flags, and its name `<scope>-agent`). Never another scope's node, never an open scope's, never the
  shared node; a folder or key that will not read tells no node. `regatta check`'s yard rows read through it: a confidential scope's
  own node is `ok`, a node no folder here gives is a note (another Mac), another scope's node a finding. A node
  `lighthouse/hosts` lists too is still its own scope's only.

- deny-drift (2026-11-03): `ORCA_ROW`'s deny list is always empty (`repos.deny`, kept read by nothing while the overlay's
  suite still prints it), and `regatta/orca-deny` leaves `OVERLAY_KEYS`: an unnamed Orca login is still a secondary
  seat, kept off the vault by lighthouse's tenancy (it is no tenant's). The overlay keeps writing the key empty until
  no older core runs (an older core still requires it); `regatta check` notes it as read by nothing.
- `hooks/fence.py`'s seatbelt narrowed by the council's landing reviews: `/dev` to Apple's pty shape (an arm opens its
  own ptys, never the owner's terminals), the OS's db folder to its timezone, the pasteboard's mach service and
  Homebrew's `var` and `etc` denied; F4's probe asks for each.

- The gate's module table (`settings/models.json`) carries a row for every site the modules name as a constant (evolve S11): `scope.brief`,
  `plan.stall` (classify, Sonnet 5.5, fail), `review-gate.reviewer` and `review-gate.code-review` (review, Claude),
  `review-gate.merge` (generate, Opus 5.5 `medium`, skip), `review-gate.same-shadow` (off, skip), `sparks.shape` (generate, fail),
  `sparks.route` (generate, skip) and `sparks.redact` (off, fail until a vendor is approved); nine of eighteen had none, and
  a stranger's install met "no row for" at each. New `tests/gate_sites.sh` (run by `check.sh`; `tests/gate_sites.py` is its AST walk)
  finds every site by the syntax tree, never a regex (a name in a comment or a docstring is no site), and resolves each under an
  empty config with every `GATE_*` variable cleared; an `off` row is a row.
- `hooks/fence.py` (the isolation design's S5): `outcomes(cli, log)`, the shell commands a CLI's own log shows run
  with their output and exit; `offered(cli, log)`, the tools its init event offers; `features_diff(listing)`,
  `codex features list` against the pinned `CODEX_FEATURES` (new, gone), which `codex_features` now reads through.
  F5: a Claude call outside the start's tools that claude refused itself ("No such tool available") is recorded as
  denied, not as a tool that ran; one with any other result, or none, still fails the arm. An agy step outside our
  hook's list still running when the log ends fails the arm. F4's probe also asks, inside the box only, to submit a
  launchd job and (in a GUI session) to open an app through LaunchServices: each would run outside the seatbelt.
  `codex_ro()`: the Codex arm's scratch configs and `auth.json`, read-only to it.
- `common.autofinish_landings()`: this Mac's landing switch (task-shape S3), beside `autofinish_armed()`.
- `regatta limit list|get|set|unset` (live-limits, 2026-11-01): a fleet limit changed on one host or every host,
  read on its next call. `config_read` merges the config dir's live layer (`live/<key>`, which only the verb writes)
  in front of the config, so a value outlives the overlay's `--config`; each value is tried on the key's own reader
  first and refused when it reads otherwise; an unreachable host is named (exit 3). `regatta check` notes each live key.
  After a write, and in `get`/`list`, each host's own reader is asked, a peer's through its `home` file (a set exits 3
  when it reads another value, refuses, or runs a checkout that predates the layer; `get` shows what it reads).
- Session names (the owner, 2026-11-01): `common.session_name(verb, topic)` and `regatta session-name
  [--lead] VERB TOPIC…` name a launched session `<verb>-<topic>`, fitted to `regatta/session-name-max` (27 by default; the verb and
  the first word stay whole); `SESSION_VERBS` lists the verbs, and `--lead` keeps the verb of a `<verb> · <topic>`
  NAME. `autofinish_window`'s fallback is the landing's session name, `finish-<topic>`, by dispatch's own call.
- `hooks/fence.py` (the isolation design's S4, from its live turns): the seatbelt reads none of `/Library` but
  the developer dir git and python3 run from (`/Library/Developer/CommandLineTools`, or what `xcode-select -p`
  names: `developer_dir()`), and F4's probe refuses an arm whose profile reads `/Library/Preferences`. agy 1.4.12's
  `antigravity-oauth-token`, which it wrote beside its state in the scratch HOME once F7 had deleted its
  per-run keychain, is read-only to the arm and one of agy's login files, so F7 withdraws and names it.
- `hooks/fence.py`'s `CODEX_FEATURES` judges codex-cli 0.166.0's nine new stable features (the isolation design's
  S4: its live turn was refused on them): five off, four kept.
- `hooks/common.py` holds `unattended_caller()` and `COUNCIL_MARKER` (the isolation design's S3, finding
  24): council, harness, autofinish-run and keel's sheep_gate read them, never a copy. `hooks/fence.py`'s `box_why`
  is harness's one rule over a research run's cwd. `bin/gate set` writes the table that holds the site, a module's
  included; `kind=` on a module's site no longer makes a dead row in the core's table. `tests/classes.sh` checks
  every module table a leak gate reads is on both autofinish lists.
- F7 in `hooks/fence.py` (the isolation design's S1, amended 2026-10-30): an arm's login leaves the disk once its
  CLI has signed in — the proxy's `on_vendor` runs `Credential.withdraw()` at the first request for a vendor host,
  before it resolves or answers (Codex's `auth.json`, agy's per-run keychain); Claude's never enters the box, its
  access token handed on a pipe (`CLAUDE_CODE_OAUTH_TOKEN_FILE_DESCRIPTOR`, or the API-key one), and a token that
  expires before the run's end refuses the arm. `FirstTool` reads what is on disk at the first tool call, `f7()`
  judges it with a scan of every file the arm leaves for the login's strings (counted, never shown).
  `codex_plugins` and the text-only flags are gone. `agy_hook.py` reads agy 1.4.11's `toolCall.name` beside
  1.4.10's `tool_name`: the hook denied every tool of 1.4.11's arm.
- `hooks/fence.py` and `hooks/agy_hook.py` (the council isolation design's S1,
  docs/principal-council-isolation-2026-10-29.md): where a council arm runs — one macOS seatbelt over the arm's
  box (`profile`, `wrap`) with `probe()`, its no-model check, run before every start; one proxy per arm as its
  only door (the CLI's vendor hosts by exact name, any public host with research on, never loopback, the LAN or
  the tailnet); a scratch home per CLI holding its login alone (agy's with a per-run keychain); an environment
  from an allowlist; the plugin, MCP and feature gates read from each CLI's own listing; the record (F5) from
  each CLI's own log; and what may not leave (a vault folder, an env file, a credential's shape in a paper).
  `tests/fence.sh`, run by `tests/check.sh`: the seatbelt and keychain cases on macOS only.
- The gate: an `antigravity` provider (Google's `agy`, VENDOR `google`) for generate and review rows;
  `vet(row, source, approved)`, the guarded-source rule alone, which `classify` now calls; and a
  module's own table, `module_table(<module>)` — the config dir's `<module>/models.json`, else the
  module's `settings/models.json`, the module found as the core's `module_path` finds it (an installed
  plugin's own folder too) — which `check` and `show` cover beside the core's, an override of a
  module's site left to that table's load (principal tier S3; the owner, 2026-10-27: no new regatta
  dependency in the overlay).
- confidential-reach S6's sixth landing review (2026-10-31): `spawn_gate` refuses a caller in two confidential
  scopes whose review vouches for one, and a node queue's entry whose scope no longer reads confidential (for good);
  `entry_takes` lets an absolute entry under the projects folder take its relative key; `scope_of_repo` raises
  only for a confidential scope; `_same_repo` needs both checkouts; `caller_dirs` adds the folder the session
  started in, read from its transcript's first `cwd` (`session_start_dirs`): a persisted `cd` moves the cwd
  Claude Code writes, never the transcript's start. The loop's later passes: `target()` splits only where the
  folder names a scope the checkout is not in; `scope_of_repo` raises only for a registry handed to it;
  `primary_branch()` (the workflow's "main", else origin's HEAD) names the branch in the unpushed refusal,
  which stays final.
- confidential-reach S6's fifth landing review, on the owner's accident standard (2026-10-30): `read_registry`
  reads a confidential scope whose `repos` is no list as torn, so every fence asking `registry_unreadable()`
  fails closed on it, not only S6's gates; `scope_of_repo` raises on a string as on `5`. `spawn_gate`: a
  caller in two scopes is a scope's own run only where every scope it is in takes the repo (main refused the
  rest); a node queue's claim runs the unpushed check; `unpushed_beyond` reads a merge by `--cc`, so a local
  merge of origin's work is no unpushed path while an evil merge's own text is; a review that arrived inside
  a merge is judged at the tip by the newest-brief rule. `_same_repo` uses `git_checkout`: one checkout rule.
- Gate rows `evolve.ask`, `evolve.theme` and `evolve.match` in `settings/models.json` (evolve S1): plumb's `asks`
  classifies the owner's prompts, names themes and matches asks to findings through them. Their prompts and label
  set are the owner's (Ring 0).
- `ORCA_ROW`, an Orca login no registry row names, takes `free_below` 70: under 70% of its 5-hour window it
  runs whatever the limit or pace, as every registry row (the owner, 2026-10-30; lighthouse's pace-window).
- `regatta check`'s kick listener row (dispatch-queue S8): where this host's `wharf-runs/kick-roads` line names
  sheep, launchd must hold the spacesheep listener service on its kick stream; a finding when it does not.
- `cost ratio` lists every provider's entry with the date it was measured (subscription-bags D3-B,
  2026-10-29); `--json` gains `others`. An entry `cost --provider` would not apply reads "no usable ratio",
  a hand-written field that is no number `$?`. With Anthropic's entry alone the output is the one line as before.
  `cost <amount> --provider P` names a hand-measured entry's date on stderr.

- A mark before every closing line (the owner, 2026-10-29): `MARKS` (✅ done and idle, ⏳ pending, handed and
  relayed, 🛑 waiting), `marked(kind, line)` for a producer, `mark_of()` and `ending_mark()` for the lint.
  `bare()` drops a leading pictograph run, so `ending()` and every comparison read a marked line as before.
  A mark with no space after it still strips, and the lint names the space; `mark_for(line)` gives 🛑 to a
  done line that leaves the owner a step (a move not proved running, a prepared move, a teleport).

- A fourth waiting line, `IDLE_PREFIX` (`THIS SESSION IS WAITING FOR NOTHING — <what was settled>`), an
  `idle` kind in `CLOSING` (the owner, 2026-10-29): a plain answer, nothing owed and nothing running. No ask
  (`unrelayed_ask`, `asks_answers` skip it); dispatch-rc reads it as an end, autofinish as no veto.

- The gate's module rows hold a `keel.comment` row (routed comments S4): Sonnet 5.5, `when_off: skip`, keel's
  lookout's one call on an owner's free-text page comments; a Mac whose table lacks the site runs it as a
  module default.

- A label move (label-move, 2026-10-30): `regatta check`'s queue-sweep row reads the job under
  `wharf-runs/label-prefix-previous` while none is under `wharf-runs/label-prefix`, and says the next
  dispatch relabels it (wharf-runs' README, the key).
- The gate's module rows (gate-module-rows, 2026-10-29): a site the config table lacks runs the row in
  `settings/models.json` beside the gate, filled from that table's own defaults, so a module ships its call
  sites' rows and the owner's table names only what it changes. A site in both runs the config row whole; a
  site in neither is refused as before. `show` marks such a row `(module default)`, `resolve()` gives it a
  `table` key and classify logs it; a `GATE_<SITE>_<KEY>` override reaches it; `set` copies it into the
  config table before changing it, `GATE_TABLE`'s copy too; `check` validates both tables. A broken module
  row, or one whose override variables clash with a config site's, refuses fallback sites, `show` and
  `check`, never a config site. `GATE_TABLE` resolves as one file, no fallback. `settings/` joins
  `autofinish_exclude`: every gate call on the Macs now reads it. Lighthouse's four `lighthouse.*` rows met "no row" on the Macs, whose config table links to the overlay's.

- `spawn_review_ok(seed_commit, repo)` and `spawn_gate(repo, commit, cwd, origin)`
  (confidential-reach S6): whether a seed leaving a confidential scope carries a `.review` whose sha256 is
  its brief's, both verdicts clean, its origin a marker this host's registry reads back (one
  `read_registry()`, a torn one refusing); whether a run is such a spawn at all, judged by the caller's
  directory, the origin and the branch. No `--settings` for a spawned run: the outward fence's D5 was
  answered A, not E, so a spawn starts unconfined and keeps its ssh.
- S6's landing review (2026-10-28): `spawn_gate` returns a `Spawn(why, mark, scope, final)` from one
  registry read (the origin's scope with it; `final` when no wait fixes the refusal), and judges whose
  brief by who asks — a caller inside a confidential scope needs the newest brief (`newest_brief`, the one
  dispatch hands the run) reviewed and may send no `--note` or `--start` prompt; an open caller needs the
  seed's own brief reviewed (`seed_commit`: the commit that brought the branch's review, its blob judged,
  never the tip's file of that path), so a spawned run's same-day `--next`, a re-dispatch and the lander
  pass. `scope_resolver(reg)` is the one answer to "which confidential scope is this path in" for the gate
  and the queue's `route()`: the fence's paths, then the repo key of the path and its checkout against
  every confidential scope's entries and globs, so a caller in an unregistered repo a confidential glob
  takes is inside it. `spawn_reviews` and `spawn_review_ok` take a `topic`.
- S6's fourth landing review (2026-10-30): one rule of which `.review` counts — its run's own topic's
  (`branch_topic(branch)`), for `spawn_gate`, the queue's `has_review` and pickup's `branch_origin` alike: a
  seed beside a spawn is an open run. `spawn_gate` refuses an open caller's seed whose newest brief is not
  the reviewed one, and a caller inside a node whose branch holds anything origin lacks beyond the seed's own
  files (`unpushed_beyond`); takes `here_only` (a host-local queue's entry: an unknown marker is final); reads
  a confidential scope whose `repos` is no list as torn (`registry_malformed`) and judges a missing registry
  from its one read. `caller_dirs(here, sid)` and `caller_and_target(at, cwds, repo)` are the caller rule
  dispatch, pickup and harness share; `session_dir` takes the newest record (`updatedAt`) and reads the
  caller's own `CLAUDE_CONFIG_DIR` first; `entry_takes` matches an absolute key by real path. `scope_paths` and
  `scope_match` take `reg` again (S8's removal took it out with the bridge; the resolver reads one parse). The `.review`
  stays unsigned: a guard against accidents, not intent (S6b, later).
- S6's third landing review (2026-10-29): `scope_resolver(reg)` gains `scopes(p)` (every confidential scope a
  path is in: a repo may be in two) and `target(p)`, a run's repo judged by the checkout its git names
  (`git_checkout()`), with a refusal where its folder says other scopes — a worktree or a clone of an open
  repo inside a node's folder read as the node's own run and pushed to the open repo. `spawn_gate` judges
  every run's target so, takes several caller directories (any one inside a scope places the caller),
  compares scopes by membership, refuses a review whose origin is not the caller's scope, and returns the
  caller's directory inside a scope (`Spawn.caller`); `Spawn` is a namedtuple. `session_dir(sid)` and
  `session_dirs()` read a session's folder from its record in every login's and Orca profile's
  `sessions/`. `entry_takes()` is the one entry-or-glob rule (`scope_of_repo` uses it); the resolver
  passes `reg` to `scope_match`, and `_registry_file` is gone.
- `scope_marker(name)` and `scope_of_marker(marker)` (confidential-reach S5's landing review, 2026-10-26):
  what text bound for an open repo says in place of a confidential scope's name, `confidential:<first 8
  hex of sha256(name)>`, and its reading back by this host's registry (None for an open scope, an unknown
  marker or two scopes sharing it). Unkeyed: it hides the name, not one already guessed.
- The check lints every module's suites (`tests/home_rm.py`): a recursive `rm` (the flag anywhere in its
  flags), an `rm` of a glob or a `find -delete` of a path under `$HOME` (directly, by `~/`, or through
  variables built from it) goes through the suite's `rm_own`, which deletes only under the suite's own `$T`,
  refuses `..` and `//`, and does not exist in a block run outside the suite. On 2026-10-25 a session ran a
  sed range of helm's suite in a shell whose HOME was the real one, and its `rm -rf "$R"` emptied the build
  Mac's run records; every such delete, in nine suites, now goes through it. A single named file is not
  linted.
- `scope_match` (so `gather_fence`) matches a scope's slug in any path part, whatever folder holds it, no
  longer only one under a `projects/` folder: a session's scratch folder (`<tmp>/claude-<uid>/<slug>/…`)
  is the scope's (trim-cross-host D2, 2026-10-28: 11 of a confidential scope's rows were quoted by the global
  usage report for it).
- `common.landed_pr(slug, branch, base=, timeout=5)`: the merged pull request from a head branch at
  any sha (into `base` when given, head.ref checked), while none from it is open (`merged_pr` matches
  one sha); wharf's checkpoint asks it before every push.
- Attribution (attribution, 2026-10-27): a session, or every session under a folder glob, is
  counted to another project in every report of time or cost by project. `common.attribution(session,
  cwd, root=None)` is the one reader (the project or `None`; `attribution_match` gives the row) of
  `~/.local/state/regatta/attribution.jsonl`, whatever `regatta/log-dir` says (`regatta/attribution` in the
  config dir moves it, written empty turns it off; a relative or unreadable value turns it off with one
  stderr line, never an import error in a hook), rows `{"ts", "project", "session" | "path",
  "why"}`: a session row beats a path row, the newest `ts` wins among rows of a kind, a bad line is skipped
  with one stderr warning, read once per process. `regatta attribution add PROJECT [--session ID | --path
  GLOB] [--why T]` and `regatta attribution list` are the verb; suite `tests/attribution.sh`. The helpers
  `under_projects` and `projects_rel` (a path under the projects folder, another home's prefix read as this
  one's) moved in from crew-report. `hooks/common.py` is in `autofinish_exclude`: this lands by `/finish`.
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
