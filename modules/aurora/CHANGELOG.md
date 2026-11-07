# Changelog — aurora

## Unreleased

- `scope-pass check --judge`: the brief judge's clean list names counts of the agent sessions, transcripts
  and tool calls that made the text and of the scan's or fence's own refusals or hits, how long those
  sessions' steps took and when they ran, a decision's letter and the names of public tools and their public
  settings; a client's own figures, timings, dates and settings (revenue, prices, its count of users, accounts,
  customers or patients, its traffic, schedules and internals) stay a leak, however the text frames them. A
  result brief made of such counts was refused three times before. The brief-review bench gains c11 and c12,
  which the old prompt refused, l11, a client's user count hidden among them, and l12-l15, a client's figure
  under the work's own nouns (an export's accounts, sessions and hits, a batch window, a setting's name): 0 of
  15 leaks missed, 0 of 12 clean refused (Sonnet, 2026-11-05; the six boundary rows twice).
- The night's trim step refuses a confidential scope's repo before trim (the TRIM_PY verb `confidential`), with the same
  nameless REFUSED line, now that trim collects a rotating one nameless (scope-rotation, 2026-11-04): the night's log names the
  repo and its folder, and embark-memo quotes it into a pushed memo (TODO.md [trim-night-fenced]).

- `week-digest` leaves out the prompts a launcher typed (the core's `transcript.machine_start`: dispatch's brief,
  autofinish-run's `/finish … --unattended`, a seed's pickup tab, a skipper's brief, weekly-run's `/aurora` and
  sextant-run's `/sextant`, hail's and dispatch-rc's frames, clock's head, a `Task:` brief), which Claude Code records
  as human; they are counted by launcher, in a text line and `--json`'s `machine` (prompts, sessions, by), on the
  copy of a session evolve S11's merge makes. A session of a launcher keeps any prompt the owner typed into it. The
  week's read needs a core with the rule (exit 2, one line, without); `--promote-tags` does not.
- `week-digest` merges a session's archive and live copies by event uuid, the newest file's copy of a prompt kept
  (evolve S11; the first file seen per session id used to win, so a resumed session's later prompts, the
  corrections among them, were lost when the archive's copy was older); a line with no uuid is keyed by its time and
  words. `--json` and the text form both read the merge. `lenses.json`'s surface ignores plumb's
  `asks/theme-merges.json*` and `asks/golden` (asks' own map and merge log, and the owner's text, never a lens input).
- `scope-pass check`: the scan reads the whole text, not a line at a time, so a word of the node's list
  split by a hard wrap is held; a space in a word or a repo name matches any run of whitespace, and a hit
  is named by the line it starts on; a wrap whose next line opens with `>`, `#` or `//` counts too. A
  `words.txt` line `re:<pattern>` holds an open-ended family of ids (case-blind, on word edges, `^`/`$` per
  line); one that does not compile alone, sets a flag (global, `(?i)`, or in a group, `(?-i:…)`), matches an
  empty string or a single character (its least width under two: `[a-z]`, `\b`, `x[0-9]*`, `(?=@)`) makes
  `check` exit 2 (the scope not ready where the list is read), as do a pattern that matches a line of plain
  text (`--`, `\w\w`, `[a-z]{2,}`, `\d\d`) and a list that cannot be read (a BOM before its first line is read past), and a load-time probe that backtracks stops at the scan's clock
  the same way. A hit is named by its `words.txt` line, so nothing check prints quotes the pattern; two
  patterns that differ only in letter case are both kept. A pattern's match that is the scope's own name is
  exempt where the name is; `proof` reports LEAKED from the list's other terms, every pattern but the one
  that fails included, and a stalled pattern's hits before the stall, and from the day's receipts, even when a `re:` line is broken; a scan past
  `SCOPE_PASS_SCAN_SECONDS` (60) exits 2. A list line that began `re:` before this, a literal then, is a
  pattern now. `weekly-run aurora --scope` stops a pass whose word list cannot judge (proof's exit 2 naming
  words.txt, or `where` refusing the list alone) with that reason and no session, after proof has read every run day; every run day's proof is read, and a LEAKED stands over a
  word-list stop, on any day and after the backstop's record. `record` on a scope stopped for two reasons names both.
  The list must read as UTF-8 (a Latin-1 or UTF-16 list, or a line holding a NUL or a later BOM, exits 2: its words
  never matched); a `#` starts a comment only at a line's start or after a space (`re:ACME-#?\d+`, `C# Labs`); a
  wrap whose next line opens with `*` or `-` (a block comment, a bullet, a `--` comment) counts as one.

- Evolve S3 (docs/self-improvement-2026-10-30.md): the schemas and coverage. `lib/evolve_schema.py` holds the
  finding (its lifecycle in three families: proposal `proposed | routed | parked | killed`, execution
  `reserved … cancelled`, outcome `pending | benefit_observed | closed_verified | closure_regression`;
  `found_by` and `also_found_by`; `action_id` = hash(finding id, action version, target scope), the cycle in
  provenance only), the findings file, the coverage record, the manifest, the receipt and the ledgers, as
  data a validator walks; `evolve validate`, `evolve schema` and `evolve action-id` use it. `lenses.json`
  (Ring 1, read with `open()`, on `autofinish_exclude`) declares the fourteen lenses, their sources and
  readers, the collectors and the outcome classes. `evolve coverage` builds the register from it and each
  scope's profile, `inaccessible` (declared, unreadable on this yard) apart from `stale` (read, old by its
  newest record's own time), names the surface nothing reads, and writes the collector manifest a quiet
  receipt needs, against the last complete pass's baseline (the pass runs `coverage --scope S --open` as it
  starts (with `--session ID`, its own session, which carries over) and `--promote` once complete, which copies that opening manifest: a run that only
  looked consumes no change, what landed during the pass is still one, and the pass's own output — `dreams/`,
  `evolve/`, its records branch, its session — is none): every required collector fresh (a verb's with its
  run receipt), nothing changed in lenses.json, the profile, the North Star or the scope's registry entry, no
  commit in its repos outside the pass's output, no other session of the scope since, no record newer than that cutoff in a source that wakes the scope (its own, or a shared log marked
  `wakes`), no exclusion past its review. A source the pass's section never names reads `unread`. `evolve conformance` sorts the
  declared rules against the transcripts' tool calls, the subagents' too: dead, holds (a hook's or the
  permission system's refusal counts as holding),
  violated, worked around (three successes in two sessions); a call with no result is unknown, and a call is
  counted once however many files or linked login dirs carry it, and a scope's transcripts are its members'
  own session folders (a sibling repo that shares a prefix is not the scope's). Times are read the same on
  every Python (a `+HHMM` offset; a bare date is no time). Both read the registry once through the
  core's `read_registry()`, fail closed on a torn one and walk every scope; a confidential scope is judged
  only under its own `--scope` (a global run counts it, `skipped_confidential`, and opens nothing of it), named by
  its marker, its profile's words never shown, its transcripts judged on their path before any open (the
  core's fence: a session started in a scratch folder named after the scope is not recognised as its). New suite: `tests/evolve-schemas.sh`.
- Evolve S5 (docs/self-improvement-2026-10-30.md): the scope pass in shadow. `skills/aurora/sections/evolve-scope.md`
  (≤ 180 lines; `dream --scope` aliased) runs a scope's pass in three ordered steps — reconcile carried findings
  and due benefit checks first, inspect the fourteen lenses of `lenses.json` with one deterministic rotating deep
  lens and tonight's research (`outside: stale` when absent or incomplete), and propose at most five validated
  findings after a cold blinded critic (`evolve critic`, gate row `evolve.critic` on Sonnet `high`, Anthropic-only
  on guarded and confidential scopes, `when_off: skip`). Scope profiles load from `<config>/aurora/scopes/<scope>.json`
  with fallback to `<anchor>/.claude/evolve-scope.json` only where the anchor is neither fenced nor the knowledge
  layer (a profile placed in the layer is refused as `profile_error`), adding `outcome_classes` (wired into
  `evolve validate`), `observation_windows`, `bars` and `radar_queries`. `evolve where` and `evolve open` run the
  zero-token collectors, write verb run receipts and earn a `quiet` receipt at `$0` (exit 3 under `--quiet-exit`)
  only when `quiet_ok` holds and no benefit check is due. `evolve record` commits `atlas`'s records from external
  staging into `<vault>/evolve/` through `knowledge-commit`, commits other scopes' `evolve/<day>.*` onto the
  anchor's `claude/<host>/<day>-scope-pass` records branch alongside `scope-pass record` (never completing a
  confidential scope without its export receipt), exports open-scope findings to `$ASKS_FINDINGS` for plumb's
  `asks` matcher (never confidential ones), and promotes the opening manifest. `skills/aurora/templates/meeting.md`
  and `evolve meetings` read repo-committed meeting pre-briefs and dated if-then commitments only. `evolve replay`
  scores hidden-future recall and lead time with post-cutoff canary leak detection; `evolve shadow` runs the pass
  non-destructively across code, knowledge and non-code scopes. New suite: `tests/evolve-pass.sh`.
- Evolve S2 (docs/self-improvement-2026-10-30.md): `scope-pass record` is the export gate. The dream goes on
  the anchor's records branch (`claude/<host>/<day>-scope-pass`, git plumbing, pushed; kl-s5 D1-B), whose
  pull request record opens and readies, so the anchor's own merge lands it; `dreams/` in the anchor's
  `in_place` is all it needs (autofinish judges no worktree-less branch, and would skip this one anyway).
  The draft's heading is made export-safe, `# Upstream — <day>` (no scope, no count), the same in
  heading_ok, record and proof; then the scan with the scope's own name, the gate's `scope.upstream` judge,
  and the exact bytes written and read back. The receipt, `dreams/<day>-receipt.json` beside the dream,
  carries their SHA-256, the cycle, the records ref and the judge's revision; a held or failed one goes
  beside a complete one, never over it, and bytes a current complete receipt names are not judged again.
  The vault's `log.md` gets `evolve --scope <scope>: complete|held`, a word, no count. record exits 0
  recorded, 3 held, 1 retry (a judge that could not tell, a commit, a push), 4 LEAKED. `proof` says
  LAUNCHED once the dream is on the anchor's main and the vault's file is certified, WAITING (5) while
  the pull request is open, HELD, and LEAKED only for bytes no complete receipt of the day named (a receipt
  of another judge revision is MISSING a current one). The new `scope-pass receipt` and weekly-run's
  `RECEIPT` line verify it; weekly-run's backstop records once more after a session that stopped or a
  judge that could not tell. `gate` and `jev`, which record's judge loads, are on `autofinish_leaks`.
  `embark-memo` renders vault first: `--vault-out` the whole memo (weekly-run commits it to
  `<vault>/dreams/<day>-embark.md` before regatta's copy; one written already is never written over), and
  regatta's view leaves out every item, section or line about a venture or the household (main's
  `ventures/|Vault only` floor, any path to `me/household.md` or `me/pointers.md`), with a pointer or a
  count, never silently (TODO.md [embark-on-helm] (2), (12)); the parts both views share are read once. New `bin/evolve
  probes`: the answer surface end to end, zero tokens, every night after the tend on its own fixture;
  `--doc` and `--board` never read or name a confidential scope's doc.
- `week-digest` intake made trustworthy (evolve S1): the fence is judged from the path before any file is opened (a
  confidential transcript is counted by name and never read, so its prompt count is no longer printed); the window
  is each prompt's own time, not its file's modification time; every login dir's transcripts are read (the core's
  `login_dirs`), where only the home's were; a prompt another session holds with the same time and words counts once;
  `--json` prints the same read whole (full text, no cut) for plumb's `asks`. The text form keeps its shape; its
  heading counts open sessions only, the confidential ones in the footer.
- The night gains an `asks` step (after the dream, before trim; evolve S1): plumb's `asks run`, once a week, no
  session, where plumb's `asks` is installed; a crash fails the step, a gate that is off is a sieve-only week.
- The night's trim step (S5's landing review): it runs last, after the dream, and on a Sunday night waits
  until 00:30 for every host's day file of the week's last day (each Mac collects a day only after it
  ends and pushes it at about 00:10), noting a host still short; its calls share the night's `WEEKLY_CAP`, so
  a stalled GitHub page fails the step instead of holding the night; a torn registry fails it, said as torn,
  apart from the fence's quiet REFUSED; `aurora/trim-repos` is read through the core's `config_read` (a BOM,
  and a key written empty tunes nothing); trim is due only where plumb's `trim` is installed; a verdict of a
  repo or vertical the night no longer tunes is renamed `verdict.retired.json`, out of the night host's daily
  report (a Mac that pulls it keeps its copy until plumb's pull mirrors `trim/`).
  SKILL.md says trim has no section file (a by-hand `/aurora` never runs it) and no longer that the dream
  reads its report.
- `scope-pass check --json`: `file` is the base name and an `error` names the scope's repos by its marker, so
  the object names nothing (the landing re-review, 2026-10-27). The bench rows survive a judge that does not answer.

- `scope-pass check SCOPE FILE --judge --json` (confidential-reach S5): the review of a brief leaving a
  confidential scope. A clean scan then goes to the core's gate, site `scope.brief` (classify, provider
  claude), which judges what a word list misses; exit 1 on a hit or a `leak`, 2 when either cannot tell
  (no row, an `off` one, a bad reply, a confidential scope with no word list — that last now for every
  `check`). `--json` prints one verdict object, the sha256 of the bytes judged and no term.
  `bench/brief-review/` is its measure: 20 made-up briefs, 10 with a planted leak the scan cannot see;
  Sonnet on 2026-10-26: 0 of 10 missed, 0 of 10 clean refused, $0.24 ($0.0044 effective).
  Since the landing review: under `--judge` the scan refuses the scope's own name too (the pass's draft
  keeps the exemption), and the verdict names a confidential scope by the core's `scope_marker()`; the
  bench judges the bundle `pickup seed --from` sends (the brief, its `Branch:` and `Seeded-By:` lines),
  adds s01, a brief naming the scope (the scan's), and prints cost through the core's `cost_text`:
  0 of 10 missed, 0 of 10 refused, s01 refused by the scan, $0.19 ($0.0035 effective). A floor test.
- The suite deletes its config dir under HOME through `rm_own` (the core's lint, 2026-10-27).
- The night's `trim` section (self-tuning S5, 2026-10-27): weekly, after `branches` and before the dream, no
  session — plumb's `trim collect`, `report --write` and `verdict --write`, each `--night`, over every repo
  `aurora/trim-repos` names (one path a line; absent, the core's own checkout) that holds a vertical file. A
  refusal (exit 3: the fence) logs one `REFUSED trim` line and the night goes on; another failure is
  `FAILED trim`, posted; each verdict's state is a `TRIM` line. `--dry-run` lists it as step 3.
- The suite gives git an identity of its own (`GIT_CONFIG_GLOBAL`, a made-up address) after moving
  HOME: the embark cases failed on the public twin's CI, where the runner cannot guess one (twin-ci-4,
  2026-10-25).
- `/embark`: a `keel sheep wait` woken by comments prints them and takes nothing in (keel's part D,
  2026-10-25); the skill says to answer with `keel sheep reply` or take them in with `sheep pull --write`.
- The host rule is the core's (2026-10-24): weekly-run asks `common.weekly_host` in the same python
  that checks the core loads (one start, not two), and `install.sh --schedule` asks `regatta
  weekly-host aurora` before its dry run, and quotes the rule's line rather than the dry run's; the dry
  run still has to plan the night, and an exit that is none of the rule's refuses as before ("could not tell"), and so does a vault that is not a folder (the dry run used to
  catch it). Lines unchanged but two: the neither-key refusal and the skip-hosts deprecation note
  name "your overlay's bootstrap.sh --config".
- The embark step (embark-on-helm, 2026-10-25; the owner, 2026-10-24: "I want embark presented to me
  on the helm whenever it runs"): `bin/embark-memo` writes the sitting as a keel course memo from the
  dream, its branches file, the sextant entry and the night's FAILED and DRY lines, each item carrying
  its own context (a section the item quotes is copied under it as a blockquote: a fence would end a
  keel item). `weekly-run embark <cwd> [--dry-run]`, and the sextant job after its session, commit it in
  regatta as `docs/embark/embark-<day>.md` on `claude/<host>/<day>-embark`, push, run `keel line` and
  write `<logs>/embark-latest.json`; a memo already written that day is kept. Runs on any host (one
  branch per host). `/embark` hands over that memo and waits with `keel sheep wait`; its
  `AskUserQuestion` batch is gone, and the review's third prompt (the budget left unspent) with it.
  The dream section's template is keel's D-shape, with the two rules the memo reads (a section an
  item rests on named in quotes; `Vault only: yes` or a `ventures/` link for a personal item).

- The one host (2026-10-24): `aurora/host`, a new key, names the one host the whole-night jobs
  (`weekly-run aurora`, `weekly-run sextant`) run on; every other host skips with a line, and
  `install.sh --schedule` refuses there, quoting weekly-run's skip or refusal. An allow-list where
  `aurora/skip-hosts` was a deny-list: a host that gets the overlay later never runs the night by
  default. `weekly-run aurora --scope <s>` runs on the scope's yard (the registry's `yard`), else
  where `aurora/host` says; elsewhere it skips with a line and posts nothing, and a registry that
  does not read refuses it in the log (fails closed). Without `aurora/host`, an `aurora/skip-hosts`
  keeps the old rule with a line saying it is deprecated; neither, beside an overlay, refuses, as
  before; an empty, unreadable or many-line `aurora/host` refuses, as does a crashed rule (its last
  stderr line in the refusal). A skip's hint names the job's own installer verb (sextant's
  `--unschedule`). `install.sh --schedule` also refuses when its dry run could not tell (crashed, or
  printed no plan). `config-keys` lists `aurora/host`, not `aurora/skip-hosts`.
- `weekly-run sextant` (B13): `/sextant` moved into sextant's module — its `where` (`libexec/sextant-run
  where`) allowed from the module's skill dir and the config dir's link, pinned as aurora's are, and
  the two reads it types through the core (`usage-report numbers`, `which`). The overlay's case
  matching /sextant's commands against these lists moved into this suite.
- `weekly-run sextant` (the Sounding's S7, 2026-10-22): the step 2c allow rules — `soundings`' reading and
  bookkeeping verbs, `keel lint`, `pickup seed * --no-start` and `dispatch * --at reset[+30|+60] --if-room`
  (three literal tails), never `dispatch:*` — and the deny lines that keep `soundings add`, dispatch's
  `--yolo`, `--start`/`--launch`, `--allow`, `--undeny`, `--force`, `--account`, `--note`, `--background`
  and `--end`, and pickup's `--start`/`--launch`/`--force` out. The job exports `WEEKLY_RUN=sextant`,
  which soundings' two refusals read and pickup and dispatch enforce (the run is in `auto` mode, where
  an allow rule refuses nothing). A rehearsal's stand-in reads both lists as `WEEKLY_ALLOWED` / `WEEKLY_DENIED`.
- `weekly-run aurora <cwd> --due` (knowledge-layers S7, 2026-10-22): the dry run as the clock's Orca
  precheck — the same plan, exit 3 when no section is due or the host is skipped, so a quiet night is
  `skipped_precheck` and starts no session. `--dry-run` keeps exit 0.
  A refusal under `--due` exits 0, so the run it lets start logs and posts it (the landing review).
- The per-scope pass (knowledge-layers S5, 2026-10-22): `/aurora dream --scope <scope>`
  (`sections/dream-scope.md`) reads one scope with S4's `--scope` readers and writes the scope's
  dream in its anchor's `dreams/` and its generalised lines in the vault's
  `inbox/upstream/<scope>.md`. `bin/scope-pass` does the code half: `where`, `check` (a confidential
  scope's inbox file may name none of its repos, paths or `<anchor>/.claude/words.txt` words),
  `record` (the dream committed on the anchor's main in place, the inbox file and one `log.md` line
  through `knowledge-commit`; a hit holds the file inside the anchor), `proof`. `weekly-run aurora
  --scope <scope>` runs it unattended from the anchor, on the scope's login through `account pick
  --repo` (a confidential scope that cannot prove its seat does not run), records as a backstop and
  logs `LAUNCHED`/`FAILED`; its bulletin lines are posted from the vault, never naming the anchor.
  The landing review's fixes: the session writes its draft beside the dream, in the anchor, and only
  `record` puts it in the vault, after `check` (the vault's SessionEnd hook pushes whatever lies in
  its in_place paths); `proof` judges the vault's main first and says `LEAKED` (exit 4); a clean
  record after a hold replaces the held log line; the scope's name is never a hit and the anchor's
  is; a confidential scope without `words.txt` is not ready; the section never posts to the bulletin;
  `account pick` must answer with the scope's login, and its reasons stay in the log.
- Gather bounded (knowledge-layers S4, 2026-10-22): `week-digest` counts a confidential scope's
  sessions and never quotes them (the core's `gather_fence`; a torn registry quotes nothing),
  `--scope <scope>` reads that scope alone, and `--promote-tags` replaces the dream's raw
  `grep -rn "<!-- promote:"`, never descending into a confidential scope's folders. It now loads the
  core (`lib/find_core.py`, plumb's copy): none found, one line and exit 2.
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
