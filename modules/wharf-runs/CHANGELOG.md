# Changelog — wharf-runs

## Unreleased

- `rc-hosts --tcc-survey` counts a job Orca started (orca-launcher S7): a not-allowed privacy request whose
  responsible process is Orca while a child of it asks is listed as `via Orca: <accessing path>` beside the
  versioned-claude rows (Orca's own requests, the quiet services and allowed ones are not), so the Drive
  requests that stopped tonight's session name their accessor. dispatch-rc's screen capture reads a
  never-busy run's window with `hardcopy -h` (a plain `hardcopy` of a detached screen holding claude's UI wrote an
  empty file on the build Mac), takes the window's screen as it goes (`DISPATCH_SNAP_EVERY`, 60 s) so a window
  that closes before the end still leaves its last screen, and says why a read failed instead of
  `(no screen contents)`. A capture is read once two polls agree and renamed onto `<record>.screen.txt` only when it read, so a
  failed read keeps the last good file; a claude that ends before it is busy logs its last screen too. The survey
  takes the `requesting` process as the asker when a line has no `accessing` one, and counts none that names no
  asker. `clock canary check` says when Orca's run history did not read (`Orca not read (its run history: …)`),
  so helm's stall road closes no run-only failure on that pass.
- `rc-hosts`: a confidential scope's Remote Control host runs on its own login (confidential-reach
  S10). A repo of a `"confidential": true` scope gets a host only when its entry says `"rc": {…}` and
  the scope's `login` has a home of its own on this Mac; its plist then sets that login's
  `CLAUDE_CONFIG_DIR` (none for the default dir, where it would move `.claude.json`). Otherwise the
  host is held and `held  <name>: <why>` says why: no `rc` object, no login, a login the account
  registry lacks, one with no home here, or an Orca-held one (`via: orca`, until a launchd host is
  known to keep its sign-in). `"rc": false` still wins. `--check` FAILs a host whose plist names
  another login than its wanted one, and a held confidential host still loaded; a plain run leaves a
  running wrong-login host for `--restart`. A session's record is read from every login dir, so a
  host on another login has sessions the reaper and `--restart` can see. Its workspace trust is read
  from that login's own `.claude.json`, and a registry the core reads as torn (a `scopes` that is no
  object) stops every run before a host is written. Of two records for one pid, the newest is read: a
  dead session's leftover under a reused pid no longer hides a busy one from the reaper.
- `clock canary beat|check` and the hourly canary (S5 of docs/orca-launcher-2026-10-24.md): the system
  finds a start path that stopped working before the owner does. `canary beat PATH [--login L] [--every
  MIN]` rewrites one beat file per PATH[@login] in a `canary/` folder of the weekly-log dir
  (`CLOCK_CANARY_DIR` names another; `CLOCK_LOG_DIR` does not move it): {at, path, login, host, via, fired, every} for the newest beat and
  `last`, the newest of each via. A beat under `clock fire`'s one-shot, whose plist names its fire in
  `CLOCK_FIRED` (for a `canary beat` alone: other jobs' children would inherit it), is via `launchd`;
  any other is via `session`. The canary automation's precheck is seam
  P's, `CLOCK fire canary --precheck -- CLOCK canary beat PATH`, so a scheduled run walks the road
  aurora's does and launchd's one-shot beats; a manual "Run now" beats at its session's first turn.
  `canary check` (and `clock check`, which carries the same lines) fails a beat older than its window
  (the cadence it declared, 60 min, plus the hourly grace; counted from this Mac's last wake when it woke
  since, so a laptop asleep is a note), one from the future, an unreadable or malformed file (a NaN,
  Infinity or overflowing time included), an enabled canary automation with no beat once it has run for
  over a window or is that overdue, the newest scheduled run whose fire the fire log lacks or whose
  one-shot never beat under that fire's name, and the newest session run with no session beat since it
  began, past the window, until a Run now reaches its first turn. A disabled canary's runs are not judged either. A beat no enabled canary automation on
  this Mac beats (a hand-run one, a disabled canary's) is a note while that Orca is read. `schedule`
  takes the canary line on `--trigger hourly` only, never `--launchd`, and asks the clock both the
  fire's and `canary beat`'s dry run; `rc-hosts --agents` reads the line as one that starts no claude,
  and names a canary beating through another checkout's clock OUTSIDE. The hourly automation is
  installed after this lands (`docs/orca-launcher-s5-2026-10-25.md`).

- `cold_prompt` hands a typed `/finish` to the runner with `--by typed --merge` on the laptop
  (`common.LAPTOP`), on the cold road and in the warm road's runner line: the owner's typed word is the
  yes there, and a run `autofinish-run` sends to the peer now carries it into that Mac's `/finish`
  (the night-landings digest's D3-A, 2026-10-25). On any other Mac no `--merge`. `peer-start` also
  refuses `--merge` beside `--unattended-caller`. Seam: `COLD_PROMPT_HOST`.
- `autofinish-run`'s day-named logs take `AUTOFINISH_DAY` when set (`log_day()`), and
  `test_autofinish_run.sh` pins it: five day-log cases failed when a CI run crossed local midnight (2026-10-26 00:00 PDT).
  `cold_prompt.sh` resets the run's inputs by pattern (`CLAUDE_UNATTENDED`, the background switch,
  every `DISPATCH_*`).
- `test_wharf.sh` gives git an identity of its own (`GIT_CONFIG_GLOBAL`, a made-up address) after
  moving HOME: its pinned-doc block committed without one, which only a Mac's hostname supplied
  (twin-ci-4, 2026-10-25; the suite is macOS-only on the twin, so the twin never saw it).
- `clock`'s seam P (S3 of docs/orca-launcher-2026-10-24.md, picked by its S1 findings): an automation's
  precheck fires its job and exits non-zero, so a scheduled run starts no claude in Orca, whose app holds
  no Drive grant. `clock fire NAME --precheck [--due] -- ARGV…` is that precheck: `--due` runs the job's
  own `weekly-run JOB CWD --due` first (exit 3 is "not due", anything else fires), then the fire, the
  outcome on stdout's first line, exit 1 (4 when nothing fired). Every fire appends a JSON line to
  `fire.log` in the log dir. `check` fails an automation whose precheck does not fire the job its
  launcher line names, through the line's own clock, and reads this Mac's last skipped run against
  `fire.log` (a manual run, which skips the precheck, is a note). `schedule` refuses the same, prints
  the precheck to give, and asks the clock the precheck names for that form's dry run, so a primary
  checkout older than this change cannot be wired in (every run would skip with nothing fired).
  `rc-hosts --agents` notes which automations start a claude in Orca, and counts a precheck firing
  through another checkout's clock OUTSIDE, as a line's is.

- `autofinish-run` sends a landing to the Mac's peer (`wharf-runs/finish-on`, else `orca-pairs`; ssh by
  `wharf-runs/ssh`), as `dispatch` sends a seeded run; `--on here` keeps it, and so does anything its
  `/finish` needs from this Mac (a caller's OAuth token, uncommitted files, a held or moded landing, a
  peer that cannot be reached), each said in one line. The peer starts it from a one-shot LaunchAgent
  (`peer-start`), this Mac's waiter asks it for the end (`peer-sync`) and writes it here as a run of its
  own would, and the laptop's approval travels with the run (`--from`, step 11.4). The second landing
  review's sixteen findings are in (2026-10-24): a chain relaunch is sent and judged where its stop
  happened; a peer's refusal for a run of its own on the tip records that run here, where it used to be
  re-sent every sweep; a silent peer is counted from the first unanswered ask, not from the start, so a
  Mac waking offline after a night buries nothing; the sweep refreshes this Mac's lock while the peer
  answers, and asks a hanging peer once a pass; a job starting late refuses at half the write-off time;
  ticket writes take a lock. Cases in `test_autofinish_run.sh` (its "Where" cases). The third landing
  review (2026-10-25): a sent chain is judged on the peer only by a stop its own run made there, never
  by one it refused or that died; a run passed over for a peer found down this pass counts as asked;
  `dead()` takes `apply`, and bin/autofinish's verdicts and `--dry-run` call it read-only (no ssh, no
  write). A `--by brief` launch stays on this Mac. The fourth (2026-10-25): `peer-start` refuses `--from`
  and `--merge` under `SKIPPER_SCOPE` as well, and `--run-session` is judged as a sent run only in the
  peer's job (`AUTOFINISH_JOB`); an unended run on the peer refuses the fast-forward of its tree, and
  the job's markers stay out of the `/finish` session's env.

- `cold_prompt` hands every typed `/finish` to a fresh run (costs S7, 2026-10-24), not only a cold or
  Fable one. Cold or Fable, as before: the hook starts the runner and blocks the prompt. Warm, on any
  other model: the prompt passes with a context line asking the session to write and commit the
  branch's commit summary, then run the same runner command itself; a refusal leaves the `/finish`
  to run there, and `/finish --here` always does. Why: a warm `/finish` re-reads the whole build
  context on every turn of the skill (docs/host-power-costs-2026-10-24.md). Its cases moved here
  from the overlay's `hooks/test_hooks.sh`, as `tests/cold_prompt.sh`. From the landing review: a
  `<synthetic>` or all-zero entry is no call; a tip the last fresh run started on stays in the session
  (the summary commit would dodge the runner's same-tip refusal); a model the price table lacks is
  named as written. `dispatch --account LABEL --force` past paid overage is refused under
  CLAUDE_UNATTENDED: that `--force` is a person's yes to money.
- The finisher rotation (S2 of docs/bench-continuous-2026-10-24.md; the owner's builders D1: A,
  2026-10-24). While the private value `wharf-runs/finisher-rotation` says `until YYYY-MM-DD` and the
  day has not passed, `autofinish-run` draws each finisher by a fair coin: Opus 5.5 or Sonnet 5.5, both
  at `medium`, by full model id. The one key is the switch and its end. A repo that is confidential in
  any of its scopes, in no scope, or behind a registry that does not read or walk keeps today's
  finisher and writes no row. Each run that drew an arm leaves one row in the log dir's
  `finisher-rotation.jsonl`: host, coin, arm, the models the transcript returned (a session that never
  answered in its arm's model is `voided: fallback`, one that returned none `voided: no-reply`),
  outcome, gate, PR and cost. `autofinish-run rotation [--json] [--settle]` reads the rows back, with
  each host's share, forced coins counted apart; `--settle` reads the commits within 48 h of a launch
  that touch its files, once origin/main has moved past the 48 h. The key reads in one line or as
  bootstrap.sh writes it, a word per line; set but off, the start line says `arm=off` and why. The
  suite's environment reset unsets DISPATCH_*, RUN_SEED_*, SKIPPER_*, HELM_* and AUTOFINISH_* by
  pattern. 42 cases.

- `cold_prompt`, `pickup` and the harness adapter read a transcript's last call through the core's `hooks/transcript.py` (needs a core that has it); the adapter reads a peer session's model from it.
- dispatch records `no launch — autofinish-run exit N` when the launcher refuses, instead of leaving
  `started`, so helm shows the hand-over (2026-10-25, finish review).
- A yolo or dnd run hands its landing to dispatch by one line (2026-10-25). The two prompts end the
  run, once its work is committed, on the core's `HANDOVER_LINE` (`<owner>, THIS SESSION IS WAITING FOR
  SOMETHING — dispatch's launch (autofinish-run)`), and `yolo_launch` launches on the core's `handed`
  kind: that line, or the two free forms the stuck runs wrote. A WAITING FOR SOMETHING line naming
  something else first still waits. Why: two yolo runs on 2026-10-24 ended naming dispatch's launch,
  dispatch read that as a wait, and neither landed until found by hand.
- The yolo launch's review fixes (2026-10-25, docs/yolo-launch-review-2026-10-25.md). Every outcome
  of `yolo_launch` goes into the run record as `launch`, which helm's card reads (D1). A dnd rc run ends
  10 minutes idle, as a yolo one does, and either ends at once on the hand-over line (D2). The launch
  gate failing (a crash) is a reason not to launch; it used to pass every gate (D3). The prompts no
  longer tell a yolo or dnd run to ask about landing. A yolo run hands over only when keel yolo stopped
  at nothing, and a dnd step with a next one scheduled ends on WAITING FOR SOMETHING naming that step
  (D4). The gate's transcript reader skips Claude Code's `<synthetic>` entries. `autofinish`'s sweep
  vetoes a hand-over while its session is live, as it does a pending line.
- One home for the claude-host launcher rule (2026-10-25): `bin/launcherlib.py` holds it (ask
  `rc-hosts --launcher <prog>`; an executable file means `[claude-host, prog, …argv]`, a non-zero or
  empty answer, a path that is no executable or no answer in 30 s means bare). `rc-hosts`' `through`,
  `clock`'s plist writer and helm's skipper runner each wrote it; they load it now (helm through the
  core's tool lookup). `rc-hosts --launcher claude` also exits 1 when the claude binary claude-host starts is missing
  or not executable: claude-host always starts that file, and its spawn failure reached only the screen.
- `clock check` (and `schedule`) judges a scope pass's host: `weekly-run aurora --scope S` on a host
  that is neither the scope's yard nor, with no yard, the one `aurora/host` names is a FAIL, as
  weekly-run would skip it every night. A peer's yardless pass is that Mac's own check's to judge.
- `check` is scoped and remembers (2026-10-23). A module's suite runs only when the checkout changed
  that module, or one it uses (its plugin.json `dependencies`, or a module its code names by path),
  since the fork from origin/main; every other command runs each time, and the whole line runs on a
  change outside modules/ that is not Markdown, docs/ or .github/, on no change at all, or with
  `--full`. Each suite left out is a `SKIP <command> — <why>` summary line, not counted in DONE. A
  script that passed is remembered per tree (`$CHECK_LOGS/passed/<tree>`, a day; `--fresh` runs it
  again, CHECK_PASS_TTL=0 turns the memory off) and a later run of the same tree reports it `PASSED
  <when> <command>`, counted as passed. Why: a full check took 58–80 min on the laptop and every
  landing ran it three or four times (docs/check-load-2026-10-23.md); CI still runs the whole line on
  the pull request, and the merge waits for it (the run on a push to main is skipped where the
  repository variable `CI_SKIP_MAIN_PUSH` says so; a nightly run on main remains). The dispatch run
  prompt names `check` for the project's check, as /finish does. After the landing review: a record
  carries the mode and HEAD, a rename counts on both sides, a change to a module's tests or prose
  runs its own suite alone, the core's suite runs on any module change, and what is remembered is
  said before any slot is taken; a skill or an agent file counts as behaviour, a module's other
  Markdown as its own.
- `bin/check`'s `script_of()` expands a `~/` path, or one led by the HOME variable, and skips a leading
  `NAME=value`; such a path, like a `/` one, is outside the branch: unattended, the command
  (`python3 ~/…/regatta check`) is run and counted when the file exists on the Mac, and fails with
  `rc=127 … this Mac has no …` when not, as the attended run would — before, it was looked up inside
  the worktree, always ABSENT, and the run still ended `DONE n/n` (B14b's prerequisites, 2026-10-24).
  `--only` matches its `~/` spelling too. Effect beyond regatta: the vault's check line
  (`~/…/bootstrap.sh --check`) now really runs on an unattended landing, where it was skipped.
  test_check's four cases.

- A host session rc-hosts closes (`--reap`, a broken host's restart, `--end`, `--restart`) is no
  longer logged as a bare fault: rc-hosts writes a note into the host's log first, and the new
  SessionEnd hook `close_reason.py` makes the session's own last line the reason, which the host
  quotes as "Session failed: …" (2026-10-24).
- The dispatch host's run cap is 6, from 10: 8 first (the owner, 2026-10-23), then 6 (2026-10-25: "it's
  too slow" at 8; runs already going finish, the cap only refuses new ones). At 10 the build Mac sat at load
  110–130 for hours (uptime that evening) beside its CI runner, and every check there took twice its
  quiet time. `dispatch --cap` prints this Mac's cap, and `bin/wharf` and helm's `stalls_tick.py` ask it
  instead of carrying their own copy, which went stale at every change (test_dispatch checks that neither
  holds a number). The 2026-10-23 evening the build Mac got a second CI runner instance for this
  repo, installed by hand with ci-provider's recipe (a verb for a second instance is owed): the one
  runner was the queue every landing waited in.
- `clock`, `yard-node`, `node/` and their suites are scrubbed, ready to list when they are (the
  shareable run, 2026-10-23). `clock`'s
  `clock-scripts` defaults to the modules' own script jobs (`dev.regatta.autofinish`, `.helm.ask-poll`,
  `.plumb.crew-report`), so a Mac with no overlay no longer fails check on its own upkeep; a peer's
  `launchctl` honours `CLOCK_LAUNCHCTL`, and the suite's fixture is `buildbox`.
- The yes at the brief after its landing review (autofinish-exclude, 2026-10-24): `brief_held` holds a
  binary, an unreadable or empty diff and `.github/workflows/`; the brief is used up when its run ends; a
  full name off the `claude/<host>/<date>-<topic>` shape, or whose topic a worktree carries, is refused,
  and in a session the typed `/autofinish` must name it; `runner_by` starts `override` only while the
  worktree's marker reads, else `brief`. A chain relaunch stays a brief or ship launch and keeps its hold.

- The second landing review of skipper-modes-followups-2 (2026-10-24): `dispatch --mode` replaces a
  `helm mode --branch` entry once its job is scheduled (`yield_branch_entry`), never drops it before a
  refusal; `read_mode` keeps the fallbacks for a helmlib without `fire_mode` or `torn_read`; a torn read
  writes no `DISPATCH_MODE` (the hint branches that never fired are gone); `yolo_launch` judges a taken doc
  by autofinish's `mode_asks`, the run's own seed aside. autofinish-run's `landing()` holds a mode it cannot
  read. `wharf apply` judges a blueprint's mode refusal and the tear from one read (`bp_mode_judge`).
- An unattended `/finish` is allowed one rule per tool the finish skill names in the regatta main
  checkout (`FINISH_TOOLS`), and dispatch denies `regatta pr ready` and `regatta pr merge` beside
  `bin/pr` and `libexec/pr` (B14b, 2026-10-23). rc-hosts finds `claude-host.c` in the overlay's
  `bin/`; blueprint specs made under the overlay's `bin/check` are no drift.
- A finished run is ended though it reads `shell` or sits in another login's registry (S13 of the crosstalk
  design, from S8's joint test: trial B's run finished at 04:23 and stayed `running (rc)` for 5 h). Its
  record said `last_status: no record`: the run was on an Orca login, whose `sessions/` is Orca's own dir,
  not a link to the default config dir's, and `dispatch-rc` read only that one. Now `dispatch` records the
  run's `config_dir` and `dispatch-rc` reads a record from it first, then the default dir's, then every login's
  (the core's `login_dirs`), each by pid with the session id checked; the nudge posts through that registry,
  and `sessions_live` reads them all. And a `shell` session whose only open background tasks are listeners
  (`sessionpipe wait`, `spacesheep talk listen`; read from its transcript: a `run_in_background` tool use,
  or a call moved to the background at its timeout, with no `<task-notification>` for it) reads `idle`;
  another shell, a background agent, `ask listen` (a relayed run waits on its answer), a chained command, a
  task that ended after the status was set, or no open task found keeps it busy. Cases in `test_dispatch.sh`.
- The on-main reads (skipper-resilience S9, 2026-10-23): wharf never rebuilds work already on main. Before a
  worker block starts, and before a retry of one, after one `git fetch origin <main>` a pass, `Ship.on_main`
  reads cheapest first: (1) done_when's `file` or `marker` on `origin/<main>` (`git cat-file -e`, then the
  blob; `check` and `memo_answered` need a worktree and are skipped); (2) a merged PR whose head is the
  block's branch (`common.api` on the closed pulls of that head, `merged_at` set; `PLAN_NO_GH` skips it);
  (3) every file the block's branch changed identical on main (`branches.prove`, the proof `bin/pr` carries
  a branch by; not for a branch never written to, nor while its worktree holds uncommitted work). A hit
  ends the block `launched via <sha>` or `launched via #N` and releases its builder. (4), before the first
  start only: an owned path (`owns:`, else the files its predecessors' branches changed) moved on main
  since the plan was made by a commit of no block of this ship (a session trailer naming one of its
  sessions, or the patch of one of its own branches' commits, makes it the ship's) raises `a sibling may
  have built this (<sha>)` to the skipper: a `waiting` report, held until the block's next report
  (`helm report --status planned` clears it, `--status launched` closes it). A fetch or API failure is no
  hit, with one line on stderr. A repo with no `origin` reads nothing. Read (1) is no evidence when the
  file or marker already held on main when the plan was made; read (3) counts a branch as written to only
  by a `commit` entry in its local reflog (a reset, rebase or rename onto main is none) and, for a
  file or marker done_when, only where it holds at one of the branch's tips. A `launch: finish` block whose
  predecessors the reads ended is launched too (its one branch proved on main also ends it), not raised
  as the skipper's. Cases in `test_wharf.sh`.
  From the landing review: a branch whose commits net to nothing, or whose commit a reset took away, is
  not proved (nothing was built); a marker counts only against its doc as main held it when the plan was
  made (first parents); a merged PR counts only when its head is the branch's newest tip; the launch
  block reads the task's `on_main` flag (while that report is still the latest), never the progress text a launch's own landing shares; a hit
  before any start releases no lock; the uncommitted veto is `branches.uncommitted`; read (4) leaves
  `AGENTS.md`, `CLAUDE.md`, `TODO.md`, `CHANGELOG.md` and `.helloworld/` out of its default paths, reads
  a landed predecessor from sync's `refs/archive/…`, stops at the first stranger and reports before it
  saves; the fetch keeps a caller's ssh command; and a new block branch starts from the origin/<main> the
  pass fetched when local main is behind it, tracking nothing.
- The yes at the brief (autofinish-exclude S7, D2-C, 2026-10-23): `autofinish override <claude/* branch>`
  for a branch no worktree carries yet writes `<common git dir>/claude/autofinish-briefs/<branch>.json`
  (refused unattended and outside a typed `/autofinish`, as the override; `now` refused). A worktree on
  that branch is judged by rule C and started `--by brief`; `autofinish-run`'s `landing()` holds it at a
  ready PR on `brief_held`: the launcher's gates, `in_place`, `.claude/workflow.json` and the base's
  `autofinish_leaks` (class 2; absent, every listed path). `override off` removes it.
- The follow-ups' landing review, its smaller findings (2026-10-23): a deployed dnd or yolo build with no
  taken doc launches `--rule L --by sweep`, as the sweep's start; `effective_mode` (bin/autofinish) is the
  one rule `landing()` and `pr`'s re-check read, and autofinish.json records `land_mode` beside `eff_mode`;
  dispatch reads the mode through one `read_mode` (helmlib.fire_mode) at fire time and at launch, keeps a
  torn registry's `ask` out of DISPATCH_MODE and the record (`mode_unread`), and a `--mode`/`--yolo` drops
  the branch's older `helm mode --branch` entry; wharf's apply keeps no `mode_refused` judged while torn.
- The yard's relays and landing call (skipper-resilience S6, 2026-10-22). A `skipper: scope` ship's
  Orca question is hailed to the scope's skipper while it holds the ship's lease (`hail <session> --kind
  ask --when idle --no-file`, its Talk page as `HAIL_SPACE`), in place of S5's Talk relay: a pointer naming
  the plan, the block and the question id, with the read and reply commands, under hail's 400 characters;
  the question's own words stay in Orca. A hail no road takes, or a ship the yard holds, is carded on the
  board, never the file queue a scope skipper never reads; a ship with a named skipper keeps its file
  relay. `hail --no-file` skips the file road, and a `--when idle` subscription keeps it and the page it
  was made under, so the tick's `hail subs --fulfil` posts there. On a
  scope's yard, the tick's `wharf apply --once --all` launches a `launch: finish` block whose predecessor
  ended: `autofinish-run <wt> --merge --by ship --digest <pin>` when the keel said merge, else `--by ship --hold`;
  off a yard, or from a session, a dispatched run, a skipper or a ship's block, the block is raised as
  before. `autofinish-run --by ship` takes the keel's yes only from the tick (refused under a session id,
  `CLAUDE_UNATTENDED`, `SKIPPER_SCOPE`, a dispatch depth or a ship's env) and only when the pinned copy at
  `--digest` does not say `merge: no`, the ship was laid attended, the keel did not say no and the worktree is
  in the pin's repo on one of the ship's block branches; `--hold` holds any launch at a ready PR (`/finish …
  --unattended --hold`), and the keel's hold sticks to the worktree's later launches (a sweep retry of a run
  that died); a held launch carries no `--merge`, and `--merge` is refused under `SKIPPER_SCOPE` as under
  `CLAUDE_UNATTENDED`. A `--by ship` launch is judged by the lander's `held_slice` (under `yolo` when the ship
  has no landing mode), so the launcher's gates and the repo's `autofinish_exclude`/`in_place` still hold it,
  and the keel's hold is its own state key (`keel_hold`), so a launch another rule held first keeps it.
  A hail that becomes a `--when idle` subscription is carded on the board as well. Cases in `test_wharf.sh`,
  `test_autofinish_run.sh` and `test_hail.sh`.
- The skipper-modes follow-ups (2026-10-23): autofinish's rule M takes a deployed dnd or yolo branch only
  when it holds a `taken` doc, else rule L launches it at once; `autofinish-run` writes `eff_mode`, the
  mode `landing()` judged a mode launch by, into autofinish.json; dispatch's fire-time and launch reads of
  the mode ask a `helm mode --branch` first; an attended `wharf apply` (and its dry run) says a standing
  `mode_refused` again with the `helm mode` line that lifts it; a pinned ship's doc taken under dnd reads
  `physical:` from the ship's main even where the doc's folder is not there yet.
- `orca-host` and `orca-serve-agent` run on Linux (the yard node's guest, or a cloud VM booted from
  `yard-node render agent`). `orca-host` there calls `orca-ide` only (GNOME's screen reader owns
  `/usr/bin/orca`), reads `~/.config/orca`, installs the release `.deb` through the guest's own
  installer or apt, restarts the server's systemd user unit, takes a pairing link only on stdin, and
  `--on` puts Homebrew on a peer's PATH only where the peer has it. `orca-serve-agent` there writes
  `orca-serve.service` with linger, the guest's `orca-serve-node` wrapper where it exists; both it and
  the guest's cloud-init now send the unit's output to null, as the LaunchAgent does, so the journal
  keeps no pairing link. Cases in `tests/orca-host.sh` and `tests/orca-serve-agent.sh`, run on macOS
  against stand-ins.
- `dispatch-rc watch` nudges a run whose last turn ended on an API error (2026-10-22: an unattended
  `/finish` ended on `API Error: Connection dropped (ECONNRESET)`, sat idle, and was ended 11 minutes
  later with its work committed and its check still running). A session idle a minute on a `server_error`
  stand-in (the `isApiErrorMessage` flag or the `<synthetic>` model, never a text alone; not a rate limit, an
  authentication failure or a safeguards flag) gets one post through the Claude Code adapter's `send()` (hail's
  socket road, read back from the receiver) saying who sent it and why: one a turn, two a run (`nudges` in
  the run record), a post that was refused or could not reach the session spends none. An end on any flagged
  API-error turn (a rate limit and the others too, though never nudged) reads `idle N min, its last turn ended on an API error`, which the harness reports `failed` and `--yolo`
  does not launch from. Cases in `test_dispatch.sh` and `test_harness.sh`.
- `wharf apply --yard` (skipper-resilience S2, 2026-10-22): a ship is laid on its scope's yard
  (`common.scope_yard`), pinned `{repo, branch, rel, digest}` from the committed and pushed blueprint
  (`push it first` otherwise), compiled on the yard or re-run there over its ssh alias with `--pinned`
  and `--laid-by` (who laid it, read on the caller: ssh carries no environment); those two flags are
  refused under a local session or `CLAUDE_UNATTENDED`, and a `laid_by.depth` past dispatch's cap. The
  pinned text is kept as the plan's `blueprint-<ship>.md`, so the tick drives it with no checkout; a pin
  another plan still drives is refused, naming it, and the tick drives one plan per pin. The fence: a
  plain apply (and `--watch`) of a ship whose scope has a yard is refused, off the yard and on it; a
  scope with no yard is refused nothing. Where the repo's scope has a yard, a block's `host:` must be
  some scope's yard. Blueprints take `merge: yes|no` and `sent_by`, and `skipper: scope` names no
  session until the lease; the keel's merge is recorded as plan.json's `merge: {value, why}`. `--gen` is
  taken for S4. Cases in `test_wharf.sh` with a stub ssh and a scratch origin.
- `bin/clock` (knowledge-layers S7, 2026-10-22): the calendar moves to Orca's scheduler. `schedule NAME
  --run LINE --trigger …` writes one Orca automation whose prompt is LINE under clock's fixed head, on
  `--model haiku`, in the neutral workspace (`wharf-runs/clock-workspace`), its grace the job's window
  (daily 180 min, weekly 1440), never Orca's 720; `--launchd` writes the plist instead (the OS form kept).
  A launcher line is `dispatch …`, or `clock fire NAME -- weekly-run …` for a job longer than a Bash call
  (`fire`: a RunAtLoad job in the user's `Caches/clock/fire` folder, never `LaunchAgents`, launchd owning it, through claude-host where
  allowed). `check` fails an agent-run calendar job still on launchd (the script jobs listed in
  `wharf-runs/clock-scripts`, a dated one-shot excepted), an automation off that shape, a confidential
  scope's pass without `--account <its login>`, a repo or scope the registry lacks, a declared job
  (`wharf-runs/clock-jobs`) with no automation, and a torn registry; `list` reads both Macs (the paired
  Orca, the peer's launchd over ssh); `board` writes one page, helm's model. `rc-hosts --agents` judges
  each automation's launcher line (OUTSIDE when it names a script outside the primary checkout).
  `tests/test_clock.sh`, stand-ins only. Private until a scrub of its own.
  The landing review (2026-10-23): a `#`, a gated flag given twice, `--start DIR` and weekly-run's cwd
  no longer pass the confidential gate, and weekly-run `--scope` of a confidential scope is refused; the
  reload waits out bootout; a peer's rows are notes and `--environment` needs `--workspace`; `check
  --json` is one document; `--replace` creates first; rc-hosts' automation notes are tagged `note`.
- `wharf` start fixes (skipper-resilience S1, 2026-10-22), found by the yard probe: `start_orca` trusts the
  picked login's config dir first, as dispatch does (`dispatch-rc trusted`, then lighthouse's
  `trust-projects`, read back; still untrusted is one failed start); a worktree git just made that Orca's
  list does not show yet defers the start one pass without counting it; a start waits for the studio brake
  (the brake's sentinel file in the home folder, or the stopped process of the job `wharf-runs/brake-label` names); and
  `wharf status --orphans` lists the Orca repos and Runs no plan here accounts for (paged; Orca's legacy row
  and `bin/harness run`'s Runs left out). A block on another host is not braked by this Mac's brake. Cases in
  `test_wharf.sh`.
- The scrub (2026-10-22): every file public. Hosts come from `wharf-runs/ssh` and the new
  `wharf-runs/dispatch-host` (`dispatch --on` takes any peer the key names, or `here`; an unknown one
  is refused naming the known ones; the run cap is 10 on the dispatch host), launchd labels from the
  new `wharf-runs/label-prefix`, the owner from the core's `regatta/owner`, the overlay from `legacy`,
  Codex's off-limits repos from the new `wharf-runs/public-repos`. The harness reads its launcher checkout from `HARNESS_LAUNCHER`. The suites use synthetic names only (`laptop`, `buildbox`, Sam, `shop`).
- `dispatch --if-room` (the Sounding's S7, 2026-10-22): at fire time, after the account pick, a run
  refuses to start when autofinish's `week_tight` says `tight` or `none`, or when reading it raises — for
  the sounding queue's runs at the weekly reset, which spend the week they fire in. No reading (no
  registry, no sample, last week's figure) is room, so at the reset `none` is what refuses in practice.
- `dispatch --at` given twice is refused (exit 2): the last one won, so a rule pinned to `--at reset`
  passed `--at reset --at <clock>` (S7's /finish review, R5).
- Under `WEEKLY_RUN` (aurora's weekly Sextant, in `auto` mode): `dispatch` takes only
  `<branch> --repo R --at reset|reset+30|reset+60 --if-room`, and `pickup seed` only with `--no-start`;
  anything else exits refused (S7's /finish review, F1).
- `bin/headroom` (2026-10-22): whether this host has the memory for one more run — % free, GB of swap
  in use and MB/s swapped over a 2 s sample, read from sysctl and vm_stat on macOS, /proc on Linux —
  against its line in `wharf-runs/headroom`. `dispatch` asks it beside the run cap at all four gates
  and refuses a run past it, refused not queued; a reading it cannot take goes ahead, said. One row
  per check in `headroom.jsonl`. Six runs had left a 16 GB host thrashing with four slots still free.
  `tests/test_headroom.sh`, Linux from a stand-in /proc. Private until the scrub.
- The skipper-modes landing review (2026-10-22): yolo holds `autofinish_exclude` and `in_place`
  too — it lands all the way bar what judges a landing and what every session's hooks run; a deployed
  dnd or yolo branch starts by rule M, not L (its taken docs and its held slice read); in mode `ask`
  rule D never stands a due doc; a `"merge": "auto"` repo's standing yes covers a yolo launch with no
  mode, from a caller without CLAUDE_UNATTENDED, only. dispatch: the unattended raise check bars on
  the target branch's mode (and the ship's task before it writes), `--yolo` is written to plan.json
  as `--mode yolo` is, a dry run asks berth with `--no-log`, and a cancel never sshes the Mac to
  itself. `wharf apply`: a refused blueprint mode stays refused (`mode_refused` in plan.json), and
  the helm tick's `--once` apply counts as unattended. berth: a torn registry is refused (exit 3);
  one load key set without `log` beside an unset one is enforced; the landing starts its log-only
  week, a dated TODO item ends it. Under `WEEKLY_RUN`, `--mode` is refused like every other flag.
- Default-path changes, intended (skipper-modes S6b, S1): berth's pick is the default host of a
  plain `dispatch` (one more ssh to a peer and a `dispatch: berth —` line on stderr).
- Every run record and launchd plist carries the mode: `DISPATCH_MODE` and `task_mode`, `default`
  when nobody set one.
- `autofinish-run --dry` prints a `mode …:` line before the account line.
- `bin/hail` and `hail subs` (Lookout and Hail, S2, 2026-10-21): one verb that delivers a pointer to any
  session `harness` names — Claude Code's inbox socket (S1's wire: an `auth` line with the key file's
  `peerToken`, then the `user` line; only to a session idle 60 s or more, re-read before the post;
  `delivered` read back from the receiver's transcript or status, `held` when nothing shows), `codex
  queue` by an explicit thread, Orca's mailbox or an idle worker's terminal, the adapter roads on a peer
  over ssh, else helm's Talk and file roads. A `send()` in each adapter. `--when idle` keeps a row in
  `hail-subs.jsonl` that `hail subs --fulfil` sends once the target is idle or gone (72 h, then dropped).
  The frame never carries an answer's words. `tests/test_hail.sh`, stubs only.
- `pickup brief BRANCH --text T|-` (Lookout and Hail, S4, 2026-10-21): commits
  `docs/handoff/<date>-<topic>.md` onto an existing `claude/*` branch by plumbing (no checkout), so a
  launchd job with no worktree can hand `dispatch` a run; fast-forwards from origin first, refuses a
  diverged branch, a dirty worktree and one held by another session, then pushes.
- `autofinish-run --merge` (Lookout and Hail, S10, 2026-10-21): the owner's up-front `/finish --merge`
  carried into the unattended run (`--by override|typed` only; sweep, chain and yolo refused);
  `autofinish.json` records `merge: true`.
- `orca-serve-agent` moves in from the overlay (D2-B, 2026-10-21): a Mac's Orca as a headless server
  under a LaunchAgent. The label is read from `wharf-runs/serve-label` on the Mac it installs on
  (default `org.regatta.orca-serve`), an older one from `wharf-runs/serve-label-previous`; the owner's
  own labels live in the overlay's config. New `--dry-run` prints the label, the plist and the commands.

- Landing on the mode's ladder (skipper-modes S3b; the owner: "dnd: I want to automerge as well"):
  autofinish's rule M starts a branch whose sent task is in `dnd` or `yolo` whatever its shape,
  `taken` docs included; `held_slice` names what a dnd landing holds at a ready PR (money in the prose,
  a physical repo, `autofinish_exclude`, a path the public twin publishes, a deleted data file, a
  yolo-taken answer) and what every mode holds (the launcher's own gates). `autofinish-run` reads the
  mode from plan.json itself — `--by` grants nothing — gains `--by dnd`, `--rule M`, `--hold`, the
  state's `hold` and gate `held`; mode `ask` holds every launch but a person's. dispatch launches a
  dnd run too (`--by dnd`), reads the mode again at launch, and refuses an unattended `--mode` or
  `--yolo` that raises the caller's mode; `wharf apply` records no raised blueprint mode unattended.
- Skipper modes (S1, S3, S6b; docs/skipper-modes-2026-10-21.md): `dispatch --mode
  default|ask|dnd|yolo` (the plist's DISPATCH_MODE, the record's `task_mode`, read again at fire time
  with plan.json first; `--yolo` is mode yolo) and its prompt gate per mode; a blueprint's `mode:`,
  recorded once by `wharf apply`, which resolves a decision gate as taken in dnd or yolo where
  nothing is held. `berth` (private-first): the host by the scope's `berths`, slots and load,
  log-only while a key ends `log`, a row in berth.jsonl; `dispatch --on auto` the default,
  `--slots`, peers by their `wharf-runs/ssh` alias; `host: auto` on a claude-code block; config-keys
  gain `wharf-runs/load-max` and `load-margin`.
- The wharf rename's S6 (2026-10-20), carried from the overlay: the launch word in `/later`, `/move`
  ("the arrival" for a move's own landing) and `/pickup`.
- `test_wharf` finds helm's console and the old `bin/plan` each where it lives: `libexec/helm` in helm's
  module (B12), the overlay's S5 shim for `plan`; without that shim the old names are skipped, said.

## 0.2.0 — 2026-10-20

- The unattended runs move in (B7): `dispatch`, `dispatch-rc`, `run-seed`, `harness` and its adapters,
  `rc-hosts`, `autofinish`, `autofinish-run`, `pickup`, `blueprintlib`, `wharf`, `check`,
  `hooks/cold_prompt.py`, the skills `/autofinish`, `/later`, `/move`, `/pickup`, and their suites.
- They find the core by `lib/core_path.py` and their peers through `common.tool()`; the registry is
  the core's `repos_json()` (`autofinish` keeps `AUTOFINISH_REPOS`). Without lighthouse's `account`
  a run starts on the one login (G12); without helm's `ask` and `helm` a run's prompt drops their
  lines (G22). `install.sh --schedule` writes the autofinish sweep's agent; `bin/check` with no
  checkout named checks the caller's.

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
