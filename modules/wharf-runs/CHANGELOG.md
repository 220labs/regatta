# Changelog — wharf-runs

## Unreleased

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
- A host session rc-hosts closes (`--reap`, a broken host's restart, `--end`, `--restart`) is no
  longer logged as a bare fault: rc-hosts writes a note into the host's log first, and the new
  SessionEnd hook `close_reason.py` makes the session's own last line the reason, which the host
  quotes as "Session failed: …" (2026-10-24).
- The dispatch host's run cap is 8, from 10 (the owner, 2026-10-23): at 10 the build Mac sat at load
  110–130 for hours (uptime that evening) beside its CI runner, and every check there took twice its
  quiet time. The copies in `bin/wharf` and helm's `stalls_tick.py` follow, as
  test_dispatch checks. The same evening the build Mac got a second CI runner instance for this
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
