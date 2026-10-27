# Changelog — aurora

## Unreleased

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
