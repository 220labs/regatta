# Changelog — plumb

## Unreleased

- trim collects a confidential scope that rotates (scope-rotation, 2026-11-04; `trimlib.collect_fence`): each row is
  redacted to an allowlist (arm, pass, cost, wall and their kin) under an id no one outside the repo can guess (a digest of
  its merge commit or session), and counts in the Scorecard's arm tallies and the verdict alone — never the Size table, the
  goals, the floor list by id or intake; its bench rows, and rotation rows that do not say their scope, are left out. Its
  ledger holds fenced rows alone: a named row from before the scope turned confidential is redacted in place, and an open
  collect drops a named row's fenced twin (a scope open again). `--night` refuses every confidential repo, and aurora's
  night never runs one (TODO.md [trim-night-fenced]). A scope with `rotation: false` is refused as before.

- `asks` (evolve S11, S1's follow-ups): `asks merge`, the theme ledger's merge pass over the model slugs, one
  `evolve.theme` call a month (`run` makes it when due and the ledger holds twenty slugs; a group of more than thirty
  is held; `theme-merges.json` keeps old → kept and `numbers`, `ship` and new runs follow it; its cost is its row in `theme-merges.jsonl`,
  which `numbers` adds to the week's spend; `runs.jsonl` stays the weekly pass's own log);
  `numbers` reports G1's rows apart, E and N (`g1_E`, `g1_N`; the headline `recall` is E's alone), residual asks per 100
  owner prompts and the J, unknown and not-yet-matched counts; lead time is now the finding's day minus the ask's
  (negative when the loop was first; it was the other way round, with no finding yet to carry it); `asks cusum` replays
  the memo-acceptance CUSUM on the owner's answers in timestamp order; `asks golden add|list|check` and
  `golden/manifest.json`: the Ring 0 fixture (ids and verified labels in git, the text in the state dir, refused
  under precision 0.80 or recall 0.85; `add` refuses a checkout on `main`, and every `golden` verb a manifest or a
  text file that does not read). `cusum` skips a free-text answer to a question that
  marked no pick; a merge pass whose row names another provider is said failed, never a traceback. `knowledge-numbers` prints the rows apart.
  A `theme-merges.json` that is there and does not read is refused, never read as empty (`merge` and `run` make no
  pass over it, `ship` refuses, `numbers` says `unreadable`); `run`, `ship` and the merge pass hold one lock on the
  ledger from read to write; an `evolve.match` that is off no longer stops `run`'s merge pass; a reply that is no
  JSON object is the call's failure, never a traceback, its spend counted all the same; `run --no-model` makes no
  merge pass, and `merge` judges the pass due again once it holds the ledger.
  A `themes.json` that does not read is refused the same way (`run`, `ship`, `merge`); folding keeps the newest
  shipped mark; a merge reply whose groups is no list is a failed call; `merge --dry-run` makes no paid call; `golden
  add` refuses a peer's unattended job and a manifest in no git checkout (an install's folder).
- `usage-report tick` keeps the last 6 lines of lighthouse's `account refresh`, not 4 (budgets-edges, 2026-11-02:
  the budgets link and its copy took the room), and its docstring names the budgets file.
- trim reads the builder rotation's rows (S6 of the Trim design): a vertical's `builders` source
  (`builder-rotation.jsonl`, dispatch's draw), joined by session to a landing's last build run, so a coin build is
  `arm_source: coin` with its drawn arm (a forced coin `pinned`, as the finisher's rows read) whether or not its
  run record is still here, and `trim report`'s scorecard shows `builder sonnet:high coin` once rows exist.
  `trim/coding.json` names the file.
- The tier check reads the session's effort at every prompt, from the tail of its transcript (the newest main-thread
  assistant entry; a subagent's and a `<synthetic>` one skipped), or the hook input's `effort.level` once Claude Code
  sends it to a prompt hook (2.1.316 does not), and at `xhigh`
  or `max` puts one line before the model: tell the owner first thing and suggest `/effort high`, unless the owner
  asked for it. Once per stretch at a value; the first prompt flags a settings pin at `xhigh` the same way (a `max` pin never runs: Claude Code keeps none in settings);
  quiet under an unattended run (xhigh-warning, 2026-11-01: `xhigh` was a third of four days' list spend).
- `usage-report numbers`: WRONG per 100 lines skips a build round's review-gate line (`phase: build`), so a branch's
  rate is its landing's gate (TODO.md [second-review]).
- `trim`: a review-gate `skipped` line is no review, so it never grades a branch as its first review.
- The limits widget: a line `<agent>:<family>` in `plumb/widget-hide` hides that bucket family of an agent's card, in the
  widget's call only (`antigravity:Claude/GPT`, account's `--hide`); with one family left its bars read `5h` and `week`,
  and each family's resets take one line, `Gemini: 5h resets … · week resets …` (2026-11-01).
- The limits widget: Antigravity's buckets in the Claude cards' words (`Gemini 5h`, `Claude/GPT week`), no second 5h
  bar beside a 5h bucket; a plan with no 5-hour window
  (account's `no_five_hour`: the primary's, Codex prolite) says "no 5h window" in its footer, not "5h unknown", and the
  tier check's account line says "no 5-hour window"; `plumb/widget-hide` names cards to leave out (2026-11-01).
- `trim verdict` takes the vertical file's `verdict.from_number`: a landing whose pull request is numbered below
  it is out of the join count and the arms (other units stay; a floor breach after `floor_since` still refuses, and a
  value that is not a whole number turns the window off with one stderr line). regatta's `trim/coding.json` sets 161,
  about where run records begin; before it 45 of the 53 unjoined landings refused every verdict, and the ones that
  joined are the dispatched subset only (trim-join-3; the skipper's call, 2026-11-01).
- `trim`: a finisher row's `fin_pass` is unknown for `nothing-to-land` and for a `no-landing` stop until
  `autofinish-run rotation --settle` proves it landed, then a pass (task-shape S1: failing every stop misread the
  arms by 27 points); a finish row with no arm drawn is no draw (no arm, out of the finisher verdict, counted
  apart in the report), and a landing's finisher names its model and effort, `pinned`. A landing's `gate_stops`
  leaves out the stops `fin_pass` reads as unknown (`fin_stop`).
- usage-report's trim line fences a key `repo_key` leaves absolute (outside this Mac's projects folder), where it
  tested `repo_key(key) == key`, which a worktree path from another Mac no longer met (S6's sixth landing review).
- `asks` (new; evolve S1): the owner's typed asks as the weekly loop's miss signal. `asks run` reads
  `week-digest --json`, takes the zero-token sieve as a pre-label, sends every owner prompt through the gate
  (one batched classify call per dimension per 50 prompts, per repo, on the row `evolve.ask`: target, kind, level,
  detectability; `unknown` allowed; a guarded repo's prompts are refused there and keep the sieve's labels), names
  each ask's theme with a slug on `evolve.theme`, matches detectable asks to findings dated before them on `evolve.match`
  (idle until findings exist) and writes ids, labels, counts, model slugs and short word hashes, never a prompt's text, to plumb's state dir (`asks.jsonl`,
  `themes.json`, the overrule ledger from `interruptions`, a run log with the spend). `numbers` prints asks per 100
  owner prompts, the detectable and judgement shares, the 60-day repeat share, recall and lead time, and the loop's
  cost; `baseline` replays the 60-day labelled corpus and prints the agreement per dimension. A gate that is off or
  failing is a sieve-only week the rows say. `knowledge-numbers` gains the row (`asks_7d` in `--json`).
- `trim`: the S1+S2 landing review's leftovers (trim-s1s2-leftovers, 2026-10-29). G1 is the cost per step (a
  landing's `steps` from its brief's `Steps:` line, one without), and G4 reads the Size table's own 300–999 row; `wrong_at_review` is the
  gate's first review of a branch, not the re-review; the PR search runs per 28-day window of merge dates and
  halves one over GitHub's 1,000; a ledger row is stamped `known_at` when it first has an arm and a pass or
  fail, and a look takes each arm's outcomes in that order, so a row that gains its arm or rework later never
  shifts a frozen slice; the diff detects renames (`-M`), so a pure move is no rework; a dispatch header keeps
  its zone, and a headless run joins by its `== started:` line, its topic cut as dispatch cuts it; a finisher row matches by its repo's path;
  helm's plans (the vertical's new `plans` source) name same-plan siblings; a floor check that never read
  (`floor_known`, the check by default) leaves a landing unknown, never a pass; `verdict --write --json` prints
  the JSON; `--night` writes under usage-report's data folder and host name, the folder `pull` carries; the
  intake reads the sextant entries of the 14 days to the look. `bin/trim`, `trimlib.py` and the core's
  `transcript.py` join `autofinish_leaks`: the fence decides whether a confidential scope's rows reach git.
- usage-report: a row's branch is part of its key, so a session that lands one branch and goes on to the next the
  same day files each, each row under its own calls' project. `branches` re-splits past days from the transcripts
  that still hold them under a lock shared with `collect`, and retries a failed or empty run the next day. The push
  keeps a known target's older days, matches a short fence word as a token only, and escapes an rsync name only
  when it holds a wildcard; the global report fences what the push strips. (trim-usage-key)
- trim's G2 line and statusline's and interruptions' prose say "skipper" (helm-vocabulary H2, 2026-10-29); the
  ledger's `driver.manager`, `manager_cost` and `manager_design` keys keep their names.

- `trim collect` joins four more kinds of landing (trim-join-3, 2026-10-29): a run `NOT_BUILD` reads as landing
  nothing (a `bench-` topic) builds its own branch when it was dispatched for it and nothing else built it; a run
  whose CSV rows never name its record's branch landed the branches they name, with the record's arm (never a
  branch another build run's record calls its own); a dispatched run with no record or log here (the other
  Mac's) reads its arm from its CSV's main-chain model and effort; a `<branch>-<digit>` head joins like `-land`.
  Either alias applies only while the head has no run of its own (a typed `/finish` that renamed it is none),
  the base never landed and no other run-less head shares the base; `landed` is read from the 14 days before
  the window too. A typed session's share is its rows in this repo alone (the CSV names the session's day branch
  on its rows in every repo, so a session that crossed into another one was counted whole). A branch only its
  transcript names joins as `seen`, typed only where nothing else ran on it, and the transcript counts a branch
  only on a line whose cwd is this repo's checkout or a worktree of it. A tie goes to the later name in the CSV
  and the transcript alike; a gate row is the newest of a head's names; rework's same-plan read finds a `-land`
  head's plan through its builder.
- trim.sh deletes under HOME through `rm_own` (the core's lint, 2026-10-27).
- `usage-report push` and a per-host `push` list in `plumb/usage.json` (trim-cross-host, 2026-10-27): a
  host the others cannot reach by ssh rsyncs its own `<data>/<host>/` to each target (`user@host:path/<host>/`),
  with pull's flags. The tick runs it after collect, at most once an hour, and only when the folder changed
  since the last push or that push failed; a failure is a `push …: FAILED` line, never the tick's. A target
  whose last folder is not this host's own name is refused (it would overwrite another host's day files).
  `push` by hand runs at once and exits 1 on a failure. A host without the key does nothing.
  It sends a scratch copy of the day CSVs alone (`calls/`; limits, accounts and the review gate's log stay),
  each without a row the global report would fence — a confidential scope's project or its group folder —
  and with an open title naming such a scope blanked; a torn registry sends nothing and fails the push. A dot
  file or a day file that does not parse stays here, named (the D1 relay: a scope's berth may be this host alone).
  The fence widened (the D2 relay, 2026-10-28): a row in a confidential scope's scratch folder is dropped (the core's
  `scope_match`), so is an open row whose project holds a confidential word, and an open row's branch, skill,
  agent or title holding one, as a substring, is blanked. The push is a mirror (`rsync --delete` into the
  target folder alone), so a stale copy there is removed by the first push. Where the overlay is installed and
  no registry file exists, the push refuses, as on a torn one. The third review (2026-10-28): a copy with no
  day file to send (no `calls/`, an empty one, only days that do not parse) is refused, so the mirror never
  empties the target; a day file that does not parse is excluded, so the target keeps its last good copy; and
  rsync compares content (`--checksum`), since a re-fenced day may keep its size and mtime.
  The landing review (2026-10-28): the fence is session-wide, in the push and in the global report alike
  (`fence_rows`): a session with one fenced row is fenced on every row and every day, so a worker's row after a
  `cd` to an open folder no longer carries the session's title and branch out. The push's due check reads
  `calls/` alone, and a push that raises still writes its marker, so it waits its hour.
- `crew-report` reads the core's attribution (attribution, 2026-10-27): a session, or every session
  under a folder glob (relative to `projects_root`, worktree part kept), attributed to another project by a row of
  the core's `attribution.jsonl` (`regatta attribution add|list`) moves its typed-prompt time and its model cost,
  a subagent's included. The rules live in the core's `common.attribution`; crew-report keeps none. The report
  adds `attributed: <n> sessions, <m> path rules — <min> min, <cost> moved`. No verb, file or config key of its
  own. usage-report's keys are unchanged; suite `tests/crew-report-attribution.sh`. Needs the core of the
  same release (`under_projects`, `projects_rel`, `attribution_match`): with an older core every report fails.
- `trim collect` joins a session to every `claude/*` branch its CSV rows name (trim-join-2, 2026-10-27), each
  landing with that branch's own rows' cost, review and first call; the rows naming none go with the branch it
  named most, so the shares sum to the session, and its end context goes with the branch it worked on last. A
  run record's branch is still the run's whole. The CSV names one branch per day and session, so the split serves a session that moved on a day later. A
  `<branch>-land` head, a skipper's hand rename of a seeded branch whose finish stopped on "not pushed", joins its builder under the name without it beside the finish that named it.
- `bench drive` is tethered (bench-tether, 2026-10-27; finding 6 of the night-landings digest): before
  each start it stops once the session that started it is gone (its claude, from `CLAUDE_PID` or the
  walk up `ps`), once `--until` passes, or once the runs' login is parked, locked or past its week
  ceiling by lighthouse's `account limits --cached`, matched by home, or not eligible there (overage on,
  `same_as`); a reading over 2 h old tells nothing; one `STOP:` line says why, exit 0.
  Run by hand with neither a session nor `--until`, the session stop is off as before.
- usage-report's day files gain a last column, `branch` (trim-join, 2026-10-27): the `claude/*` branch a
  session's main-chain calls name most that day, an agent's only where the main chain names none; a file
  from before it reads as empty. `usage-report branches [--days N]` fills it in this host's past files from
  the transcripts and the archive still here, changing no other cell, and the tick runs it once per host
  (`.branches-filled`). `trim collect` joins a session by it between the run record and the transcript
  (join `usage`), so a typed session whose transcript Claude Code pruned still finds its landing. `usage` ranks under
  `transcript` when a re-collect merges, and the verdict counts a landing with no readable arm with the unjoined.

- The week (trim S5, 2026-10-27): `trim … --night` keeps the ledger in the core's log dir,
  `<log dir>/<host>/trim/<repo>/<vertical>`, so Aurora's night never dirties a primary checkout and the host's
  folder `pull` copies carries it to the Mac that renders; `verdict --write` files the verdict as `verdict.json`
  beside it (refused or not) and prints its state in one line. usage-report's daily report carries one `Trim:`
  line in its headline from those files, every host's (`<data>/*/trim/`) and the log dir's: each verdict's state, marked stale
  past 8 days, a confidential scope's (or every one, the registry torn) counted and not named.
- `trim collect|report|verdict` (trim S1–S2, 2026-10-26): one row per outcome joined from the usage CSVs, run
  records, dispatch logs, transcripts, review-gate rows, merged PRs and their diffs, finisher and bench rows, as
  weekly JSONL records; a scorecard; the verdict (one-sided Beta bound over precommitted looks, cost ratio, CUSUM,
  a floor breach or an unjoined ledger refuses, exit 3). Refuses to collect for a confidential scope or a torn registry.
- usage-report's tier mix counts `principal-worker` and `principal-architect` as tiers of their own (principal
  tier S2), not "other agents".
- The reports rule (confidential-reach S3, 2026-10-26): crew-report reads the core's `gather_fence` as
  usage-report does — a confidential scope's project, its group folder's, their recordings and reading
  lines read `(confidential #n)` and still count in every total, a session opening in one counts as
  `(confidential)` among the first prompts, a torn registry fences every project. usage-report's global
  report gains "By scope" (an open scope by name, a confidential one `(confidential scope N)`), and
  `render` writes each confidential scope's own named report to `reports/usage/<day>.md` and `latest.md`
  in its anchor, only where the fence calls the folder confidential; never published. Past reports stay.
  A file there that is a link is replaced, never written through; `reports/usage/` goes into the anchor's
  `info/exclude` (untracked files would stop sync.py fast-forwarding its main); one scope's failure no
  longer costs the later scopes their report; an open-quoted row of a confidential glob names no project, skill or agent, and crew-report fences such an unregistered checkout too; the node report goes through a fresh `mkstemp` file, so a link at its temp name is not written through.

- usage-report's fence (the confidential stopgap, 2026-10-26): a row whose project is a confidential
  scope's (the core's `gather_fence`) counts in every total and is named nowhere — its project and title
  read `(confidential)` (a title numbered per session, `(confidential #1)`), a project's own skill or agent name too — in the report, the line and the log;
  a torn registry fences every row, and so does a session in a folder holding a confidential checkout;
  an open row's title that names a confidential scope or repo reads `(confidential)`. `numbers` keys a confidential scope's pass `(confidential)` unless
  `--scope` names it, which knowledge-numbers now passes. The CSVs and past reports are unchanged.
- usage-report's `extra_usage` sample is the core's `extra_usage()` parse, the one lighthouse's
  `account` reads its probe with (costs S8, 2026-10-24); the sample is unchanged.

- The usage tick runs lighthouse's `account refresh` first (orca-launcher S4, 2026-10-25): launchd starts it
  through claude-host every 15 min, so the hooks' local copies of the tenants and logins files stay fresh.
- `bench/builders/`: the builder bench — `bench run` rebuilds a landed task from its brief with one model
  arm in an isolated clone and grades it with the landed tests through wharf-runs' `check`; `drive` runs a
  plan under a budget ledger (2026-10-24).
- The plumb scrub (2026-10-22): the files B8 moved in are public. Their private values come through
  the config dir (README, "Private values"): `plumb/usage.json`, `plumb/dispatch-host` (G3's Mac, no
  longer the first line of `wharf-runs/ssh`), `plumb/tier-rules`, and the core's, atlas's and
  lighthouse's keys. The limits widget runs `regatta account`, found through the `home` file. The
  suites run on fixtures of their own config dir and need no overlay. Two dated runs left `bench/` as
  records (the design run of 2026-10-04, the reviewer model bench of 2026-09-29); `score.py` and
  `review_sheet.py` take the post-hoc rule's repos as `--apply`.
- Each scope pass's cost (knowledge-layers S5, 2026-10-22): `usage-report numbers` carries
  `scope_passes` — sessions and the API-price proxy per scope, from the sessions whose prompt is
  `/aurora dream --scope <scope>` — and `knowledge-numbers` prints it as one row (`--scope`: that
  scope's alone).
- Gather bounded (knowledge-layers S4, 2026-10-22): `interruptions` keeps a confidential scope's
  rows in every count with their text, file and project blanked (`(confidential)`), leaves them out
  of `--list`, and counts its untrusted repos unnamed; `knowledge-numbers` sums its repos into one
  `(confidential)` row and counts its unlinked memory the same way. Both take `--scope <scope>`
  (that scope's rows alone; knowledge-numbers hands it to interruptions).
- `interruptions` no longer crashes on a multiSelect answer stored as a list: it is joined, then
  judged (it failed on this Mac's week of 2026-10-22, so knowledge-numbers' row read "no output").
- The account registry and usage-report's config are read from the config dir only (2026-10-22):
  `lighthouse/accounts.json` ($ACCOUNTS_FILE over it) in `tier_check`, `usage-report`, `interruptions` and
  `knowledge-numbers`, and `plumb/usage.json` ($USAGE_CONFIG) in `usage-report`. The old fallback was a
  path into the owner's vault, which a work login is refused; the overlay links both into its `settings/`.
- The wharf rename's S6 (2026-10-20): `bench/`'s prose says launch for a merge, and "come in" for a run's
  result arriving.
- Carried from the overlay (the wharf rename's S5, 2026-10-20): `knowledge-numbers`' G4 list follows
  helm's files to their new names (`bin/helm`, `helmlib.py`, `helm_render.py`, `test_helm.sh`,
  `test_wharf.sh`; `bin/plan`, now a shim, printed beside); `interruptions` says launcher. A checkout
  from before S5 (no `bin/helm`, a `planlib.py`) counts the old names instead, so an overlay whose S5 has
  not landed keeps a comparable G4.

## 0.4.2 — 2026-10-19

- `reports` defaults to `~/.local/state/regatta/crew-report` (was a folder under the projects
  folder that named one owner's layout). A deployment that publishes sets `reports` under the
  publish tool's root, which refuses a file outside it; without that, the weekly publish fails
  with one `publish FAILED` log line and the report stays local.

## 0.4.1 — 2026-10-19

The /finish review's fixes.
- The zone is the system's named zone (or `tz`, or `$TZ`), not today's fixed offset: weeks across
  a DST change meet with no hour lost or doubled.
- A fork (/fork, pickup's move) gives its inherited rows back to the source session, so the
  person's own lines after the move count; the default pickup pattern matches the prefill only.
- Cost: usage-report's keys go through crew's own project mapping (a subfolder's cost joins its
  repo); `--this-host` keeps this Mac's rows. A path in another user's home under the same root
  maps as this one's.
- Measured reading: a run across Sunday midnight keeps Sunday's side at any gap; `ts` as epoch
  seconds is read; `read_gap_minutes: 0` is applied; `drained: <time>` after a good drain and the
  stale line only without one; `Opened without a heartbeat (docs)` per project from keel's
  `opens.jsonl`. The drain runs in an empty folder with 300 s.
- `--write` writes latest.md only for the last complete week, refuses `--until`, and publishes only
  with `--publish`, which the job's plist carries. `install.sh --schedule` names the main checkout
  from a worktree and retries a bootstrap once.
- Not-counted tallies and first prompts are over the week alone; a text first prompt shows as a
  digest of its first 40 characters. The prompt-rule warning looks at prompts, not rows.
- Estimated reading: `reading.include`; two repos adding one path are two docs; the static HTML
  reading survives an unclosed `<head>` or `<tr>`; a Chrome render cannot abort the report (90 s).
- Recordings: est. and unresolved counts follow the kept files; unreadable note folders are said;
  an audio root matches whole path segments. Login dirs: the default one is read when the registry
  names none of its own.
- Peers can be pinned with `CREW_REPORT_KEEL`, `CREW_REPORT_PUBLISH`, `CREW_REPORT_USAGE_REPORT`.

## 0.4.0 — 2026-10-19

- `crew-report week`: measured reading. The heartbeats keel files for a doc's course page
  (`reads`, rows of `reads.jsonl`: doc, repo, branch, path, ts in UTC, who) are joined per project
  and doc at gaps up to `read_gap_minutes` (default 5) into runs spanning `[first - 1 min, last]`;
  tabs and docs of a project in one minute are one minute. The `reading` column is the project's
  measured minutes; the total is prompts, recordings and measured reading as one union, overlap
  counted once. The 10 / 30 columns move the prompt gap only. `est. reading` is unchanged and still
  never added.
- New config keys: `reads` (a list of files, default `["~/.local/state/memo/reads.jsonl"]`), `viewer`
  (the `who` to charge, `""` = every viewer, the distinct count printed) and `read_gap_minutes`.
  Another viewer's minutes print as `other viewers: n min` and are never charged.
- Under the table: `reading raw: n min` before overlap removal, `docs added: n; … with a course: m`
  per project, `last drain: <time>` (and a line when it is over 6 h old), and what is not measured.
- `week` first runs `keel sheep drain` once (120 s at most) and says in one line if keel is missing
  or the drain failed, then goes on; `CREW_REPORT_NO_DRAIN=1` skips it. keel's subcommand is built
  in another step: until it lands, the report carries `drain: failed — exit …`.
- G6 (the first week of heartbeats against opens) is checked by hand the Monday after this lands and
  its figures written here.

## 0.3.0 — 2026-10-19

- `crew-report week --write` publishes. New config key `publish`: `""` (local only, the default),
  `"vault"` or `"data"`, the scope of lighthouse's `publish` tool, found through `common.tool()`.
  The tool absent: the report says "local only"; a failure is one log line and never fatal.
- `install.sh --schedule` writes and loads one launchd agent running `crew-report week --write`
  on Mondays at 07:30 local; `--remove` unloads and deletes it; `--check` also says whether it is
  loaded. `PLUMB_LAUNCH_DIR`, `PLUMB_LAUNCHCTL` and `PLUMB_LABEL` override the plist folder, the
  launchctl and the label. Nothing is scheduled until `--schedule` is run.
- A weekly pass fits the 2-minute goal (G5). A cache folder (`cache`, default
  `~/.cache/regatta/plumb`, `""` = off): rendered HTML docs' word counts by text hash, and each
  transcript file's prompt candidates by path, size and mtime (digests where text would be, no
  prompt text). Docs are read with two git calls per repo, not two per doc, and Chrome renders four
  at a time. The 2026-W42 report printed the same table before and after. On a loaded Mac the
  pass took 1:43 before (2:54 on an earlier day), 1:28 with an empty cache and 0:06 with a warm one.
  An AskUserQuestion answer is now matched to its question within one transcript file only.

## 0.2.0 — 2026-10-19

- `crew-report week`: recordings. Notes (`notes`, `audio_roots`) selected by a project's `terms`,
  one recording per audio file, length from afinfo, ffprobe or the note's size, joined with the
  prompts as one union per project; the total column is that union.
- `crew-report week`: estimated reading, reference only and never in the total. The docs a
  project's repos added in the week (by author date, all refs, content at the newest ref),
  `exclude` and `reading.exclude`, 200 words a minute, HTML rendered by headless Chrome when found,
  else stripped statically; "docs added: n" per project under the table.
- New config keys: `notes`, `audio_roots`, `chrome`, `words_per_minute`, `exclude`,
  `projects.<name>.terms`, `.repos`, `.reading.exclude`.

## 0.1.0 — 2026-10-19

- First cut: `crew-report week`. Typed prompts per project from every login dir and the
  archive, deduped by uuid, with launchers' prompts dropped. One timeline, a 20-minute gap,
  10/30 beside it, ISO weeks in the local zone. The week's cost from usage-report when found.
- Replay of 2026-W42 cut at 2026-10-18 15:17 against this Mac's transcripts: the project of
  the hand run of that day reads 18 prompts and 52 min at gap 20 (the hand run: 52 min).
