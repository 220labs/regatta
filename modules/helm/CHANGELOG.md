# Changelog — helm

## Unreleased

- The board's ops row (lighthouse-ops S2): one line under the header from lighthouse's `ops status --json`
  where this host has an `ops.jsonl`, amber once the row is an hour old; `board_sig` counts it by the
  row's sig alone, never its line, which carries the sample's age and the gauges.
- `helm page [SHIP]`: the ship's page, published once, its space printed (peer-manager-relay S1, D1-A).
  No ship, it is made first (topic `skipper <id>`, the session as its skipper); a ship that has a page
  publishes nothing. Exit 3, one line on stderr, when no page may go: no sheep render, no CLI, key or Talk service named, an
  account without Talk, or helm's publish budget held; a refusal makes no ship. dispatch asks it for a typed
  skipper's first run, so a run on a peer Mac always has a Talk address.
- A manager on another Mac is judged by that Mac's registry (peer-manager-relay,
  `docs/peer-manager-relay-2026-10-26.md`): where the config dir's `wharf-runs/ssh` names its host, one
  ssh reads the session's record there (`asklib.peer_manager`). Live, `bin/ask relay` relays to it; with
  no plan page, the file road writes its own queue on that Mac, which its prompt hook prints, when the run
  has a page of its own to hear the answer on (else it parks, as before). A dead pid is gone, and the ask
  goes to the Mac's standing manager, else waits for the owner. A host with no alias, one that does not
  answer, or no record there (the probe reads the login's registry and every Orca profile's) stays `remote` as
  before. The build box has no ssh alias for the laptop yet, so board-cleanup's direction (its D2 parked
  for about 3 h) still parks without a plan page: the record's D1. `asklib.peer_runs` gives keel's listen reminder the peers' runs. `ASK_SSH` stands in
  for ssh in the suite.
- `helm send --text --tier principal-architect|principal-worker` (principal tier S5): accepted, through
  wharf-runs' TIERS; a lower `--effort` or another `--model` is refused before any branch is seeded, and so is any
  `--model` or `--effort` with a principal tier, which its run would never carry. The stall tick's S2 start (the
  next step) passes no recorded model or effort: that step's brief decides.

- The stall class `start path dead` (orca-launcher S7, docs/orca-launcher-2026-10-24.md G2): `stalls.py` reads
  wharf-runs' `clock canary check --json` on this Mac (its own Orca and beat files: no peer, nothing on the laptop)
  and raises one stall per failing canary beat, keyed `[host, "canary", beat]`, titled `canary orca · start path
  dead`, in the owner's column. The stall road files it on a yard like any raise, with the mention; a pass that
  could not read the check (the brake, a hung or garbled answer, an Orca it could not read) closes no issue
  (`unread["canary"]`, `STALLS_CANARY`, 0 turns it off). Nor does one in the 90 minutes after the studio brake ends
  (it froze Orca serve, so no beat fired), or one whose Orca read already failed. A beat that fails again after it
  cleared is a new instance and waits the 10 minutes again; a beat whose login a confidential scope runs on is guarded.
  G2: 45 minutes from the missed beat to the issue (the record's arithmetic), up to 105 from the last good one.
- The board drops dead cards (board-cleanup S1, `docs/helm-board-noise-2026-10-25.md`): one cached
  `gh pr list` read per cloned repo (`helmlib.repo_prs`, every open PR and the newest 300 of any state,
  cached 10 minutes, the repos read in parallel) serves every reader, matched by `(repo, branch)`. A stall whose branch's PR is merged or closed,
  or whose content is on main with no PR (wharf's `branches.prove`, its "every changed file identical"
  proof only), is no card, nor one older than 7 days (`HELM_STALL_DAYS`): the header counts the old ones,
  with the oldest's age and the days it was told; `stalls.py --json` and the tick still see every record. Ask and lookout cards on a merged or
  closed branch drop off too, as do a template's and a test fixture's D-items, and one doc item on two
  branches is one card, the newest branch's.
- The ask poll skips a branch whose PR is merged or closed and any `TEMPLATE.md` or `tests/` doc, and
  rings one banner per doc item; `asks.json` rows carry the branch's `t` and `sha`, and keep every live
  branch's row (keel's lookout watches it per branch). `seen.json`'s keys are unchanged. `asks.json`'s
  `ended` lists each branch skipped for its PR, and `stalls.poll_asks` reads it as asked, so a WAITING run
  there raises no new S6 (the landing review). No guarded repo's PRs are read.
- PR cards cover every open PR in every cloned repo (no 8-repo, 10-PR cap); a WIP PR is Running only while
  a live session (`stalls.judge`'s new `live` list) or a running task holds its `(repo, branch)`, else a
  header count. Done today lists today's merged PRs and today's `launched` lines in each repo's
  autofinished log whose PR is not still open (one readied for a tap). The owner's column groups by kind (asks, stalls, sessions waiting, PRs, memos), five
  each with "+N more"; a waiting card names its branch's topic.

- The embark memo leads the owner's column (embark-on-helm, 2026-10-25): `helm_render.embark_first`
  puts the newest open `docs/embark/embark-<date>.md` first, titled and labelled Embark, whether it
  came from this Mac's `keel list` or a lookout card (this Mac's or a peer's).

- A run that ended on the hand-over line, with no launch record after it, is an S6 raised to the owner
  carrying dispatch's reason from the record's `launch`, never S1's retry: a re-dispatched build would
  end on the same line and meet the same gate (2026-10-25, yolo-launch review D1-B). One whose launch
  started is no card here; a launch that stops is S4 or S5 as before.

- The skipper asks for claude-host through wharf-runs' `launcherlib.py`, the one home of the launcher
  rule that `rc-hosts` and `clock` use too; its answers are the same (a non-executable path, an empty
  or a failed answer: a bare `claude`), and the argv it builds is the library's.
- The skipper's `claude` starts through `claude-host` where wharf-runs' `rc-hosts --launcher claude`
  names one, as dispatch's runs do: skipper-ears S1 (2026-10-24) saw a bare `claude` under launchd hang
  before its first turn on the yard, its binary denied Full Disk Access, and every case pass through
  `claude-host`. No grant on the host, or a launcher that is not executable: a bare `claude`, as
  before. The runner asks once, inside its own deadline, and its sign-in probe goes through the same
  launcher; its log names which. The record's pid is then `claude-host`'s, with `claude` its child, so
  `stop()` signals the registry's `claude` when the record's pid is it or its parent, and
  `--stand-down` adds the session's own registry pid.
- The ask poll fetches a mirror only when origin's branches moved (costs S10, 2026-10-24): one
  `ls-remote --heads` per mirror, compared with its own heads, before the fetch it replaces most
  ticks. A failing ls-remote or fetch now raises, so the poll says the repo was skipped and carries
  its last rows; the fetch's failure used to pass unseen.
- spacesheep plans (spacesheep-tiers, 2026-10-24): the Talk backend answers one line where the plan has
  no Talk ("Talk needs spacesheep Pro", or "Talk is off for this account") and the next backend takes the
  ask; a `plan_required` refusal says the same; no CLI and no key is "no spacesheep on this Mac". The
  board and the ship pages log each publish and stop redeploying above helm's share of the account's
  24-hour cap, or on a cap refusal the server sent, until its retry; the board's crossing deploy carries the note
  in its header (a ship page holds without the marker), a resume redeploys though no card moved, and a hand-run
  `helm board --deploy` says the pause; the board's header names a
  plan without Talk; the SessionStart nudge is silent on one read in the last hour. A running `spacesheep stream` is checked
  against the plan and the server's list (CLI 1.31.0 keeps a refused stream running), else the page
  redeploys. The README's "spacesheep plans" says what each plan gets.
- The stall road's repo key is `helm/logbook-repo` (was `helm/inbox-repo`, no longer read): `inbox`
  names strangers' contacts only, and operational issues land in a project's logbook (the owner,
  2026-10-24).
- `stalls_tick.py` asks `dispatch --cap` for the run cap instead of carrying a copy of it (6 on the
  dispatch host since 2026-10-25; wharf-runs' CHANGELOG says why). The copy also gave the dispatch host's
  cap to any `wharf-runs/ssh` peer, where dispatch reads `wharf-runs/dispatch-host`.
- The skipper's rotation: while a ship needs it, a skipper 8 h old, or past 200k tokens of context
  (its last main-thread call, `<synthetic>` entries skipped) once an hour old, hands over at its first
  quiet pass — its session idle 10 minutes by the registry's status stamp, no question of its own open
  — by the daily hand-over's road: ships to the yard, the next start, open questions re-hailed. The
  24 h hand-over at 04:00 stays as the ceiling for a scope that is never quiet. One skipper per scope
  still: a relay finds its skipper by (host, scope), and a skipper runs no builds that would need to
  drain.
- Skippers run Opus 5.5 `high`, not Sonnet 5.5: their work is judgement on unspec'd questions, and
  the rotation keeps their runs short.
- The second landing review of skipper-modes-followups-2 (2026-10-24): `yield_branch_entry` replaces
  `drop_branch_entry`; a key-less entry is never popped by an unattended write, and on a branch with no
  sent task it is no mode; `helm mode --branch` resolves a relative `--repo` to its checkout and refuses a
  branch the checkout lacks; `bin/ask relay` keeps no mode in asks.json or the plan event when the read was
  torn.
- `skipper-run` drops every `DISPATCH_*` and `RUN_SEED_*` variable by prefix: its fixed list had missed
  `DISPATCH_MODE` and `DISPATCH_BRIEF`, so a skipper started from a dispatched run inherited both.
  `test_helm.sh`'s "no run variable either" case caught it when the suite ran inside a dispatched run;
  the case now hands the runner `DISPATCH_MODE`, `_SCREEN`, `_BRIEF`, `_HOST` and a `RUN_SEED_*` and
  sees each gone. `ASK_ACCOUNT`, `ASK_SESSION` and `SKIPPER_GEN` are still unset by name.
- The follow-ups' landing review, its smaller findings (2026-10-23): `helm mode --branch` keys every entry
  by its repo (`--repo`, else the cwd's checkout; outside one, refused); a key-less entry from before is
  read as a lowering only (`helmlib.LEGACY`); `drop_branch_entry` for a newer `dispatch --mode`;
  `branch_mode` ends in `under_ship` as `fire_mode` does; `task_mode` parses repos.json once and names a
  torn read (`TORN_WHERE`, `torn_read`) so no writer keeps it.

skipper-resilience S13a, three fixes before sitting A arms the yard's tick.
- An Orca that does not answer reaches the dead-man's switch: with the brake off, the third pass in a row
  whose Orca read went unanswered, on a host where some ship has an Orca Run, pings `deadman ping <host>
  --fail --why "orca unread: <what>"`, `<what>` in `stalls.ORCA_DEAD`'s fixed words (no run id, path or
  message leaves, K6); one or two such passes, no such ship, a warning Orca answered with, or one Run's
  task-list unread while another answered stay plain. The count is `orca-unread.json` in the tick's state
  dir, reset by a read pass or a braked one, kept by a pass that raises, and written only by a tick that
  pings (deadman installed, launchd's tick).
- The skipper clocks through a brake: the tick records each pass's sight of the studio brake
  (`brake-windows.json`, `helmlib.note_brake_pass`; launchd's tick only, before the stall road) on a yard
  with a lease or a skipper record, and
  `leaselib.lapsed`, `skipperlib.deaf`, the skipper pass's two start clocks (a take within 5 minutes, a
  yard-held ship its sidecar should have taken in 15), the crash-after-start clock and the stall road's unanswered-relay clock
  subtract the time inside a window, so the first pass after a release no longer hands over, stops or
  escalates a skipper that was only frozen. A window runs from the pass before the
  first braked one to the first pass after; one left open credits at most 10 minutes past its last
  braked pass. Recording the window was the smaller change: pushing each lease's `until` on would still
  leave the deaf rule's hail times to rewrite.
- The ping's reserved time: on a host whose tick pings, the stalls', wharf's and the skippers' passes run
  under ask poll's kill time less 40 s (`stalls_tick.ping_reserved`), and the ping's timeout is what is
  left of the kill when a pass overran anyway. The judge's own Orca reads keep their fixed timeouts (TODO.md). No yard set: every host's passes keep the kill time as before.

skipper-resilience S11, the yard's tick pings the dead-man's switch and holds under the studio brake.
- `helm tick` ends with `deadman ping <host>` (lighthouse's `bin/deadman`, through `helmlib.peer`) on a host
  some scope's `yard` names (`helmlib.yard_hosts`; a torn registry reads no yard): after the Orca read, wharf's
  pass and the skippers', so a tick killed at its deadline never pings and the yard goes silent. (An Orca that
  does not answer is a time-limited read, not a hang: the ping still goes, plain, and the Orca source is
  marked unread; S13a above makes the third such pass in a row a `--fail`.) A pass that raises first runs `deadman ping --fail --why "<one line>"`, then fails as before. A ping
  that fails or a deadman that is absent is one line, never the tick's failure; `ask poll` copies every
  deadman line but a plain ping's into the yard's launchd log. A tick run inside a session or by an
  unattended caller pings nothing (the stall road's caller rule), and says so in one line. `--dry-run`, `--status` and the
  switch ping nothing; no yard set (every scope today), nothing changes on any host.
- While wharf's `brake_refusal()` holds (`helmlib.brake_refusal()` loads it, so one rule): no Orca read
  (`stalls.judge(orca_held=)` says so on a card; no stall escalation closes, as an unread stall's absence
  says nothing), no wharf pass (it reads Orca), no skipper start or stop (`ensure_skippers(brake=)`: one
  `skippers: held` line where a scope is held, none otherwise), no retry, relaunch or relay of the tick's own
  (each waits, unspent: dispatch and the harness do not read the brake), and the ping is `--braked`. The brake is
  read at the tick's start, returned in its result (`brake`), and read again before wharf's and the skippers' passes. The brake gates a tick on any host, yard or not.

skipper-resilience S8, the stall road and the yard's tick.
- `ask poll` ticks on a host some scope's `yard` names, as on the laptop (`helmlib.yard_hosts`): wharf's
  pass, the skippers' pass and its own stalls. Off the laptop a torn registry is no tick, one line. With
  no yard set nothing changes on any host.
- Each host acts on its own store: the laptop still reads and judges a yard over ssh (the board shows its
  stalls; its records and live sessions are shared facts), but its tick acts on none of them
  (`stalls.self_judging()`, read in `stalls_tick.acted_elsewhere`), and on no peer's at all while the
  registry does not read (fail closed). A RELAYED run whose manager is on a host with no road from here
  (a yard's to the laptop) is unknown there, never "manager gone"; the laptop's board still judges it.
- The `github-issue` notify backend (`bin/ask`'s `notice()`; `surfaces.KNOWN["notify.*"]` and the schema
  know the word): an issue in the config's `helm/logbook-repo` (named `helm/inbox-repo` until 2026-10-24), its body led by `helm/mention`, labelled
  `stall`, through the core's `api()` and `token()` (`ASK_GH_API` replaces it with a program called as
  `gh api` is). It carries stalls only; an ask's banner is unchanged. Absent values are road `none`.
- `stalls_tick.escalate()` after the decisions, on a yard only: a raised stall first seen 10 minutes ago
  (never one raised to a live skipper, nor `braked`), a block of a ship the yard holds gated on a decision
  doc or a person's task whose deps are done, quiet 10 minutes, and a question on such a ship by S5's owner
  rule — the owner's (`helm skipper --escalate`, mode ask or dnd) after 10 minutes, the skipper's once 15
  minutes pass unanswered, one answered in its doc never — each one row in `escalations.jsonl` (`open`, `class-changed`, `closed`) and one
  issue per key: a class change a second issue naming the first, which is closed once the second is open;
  a key missing 10 minutes with every store read a comment and the issue closed; the same class back
  later its issue reopened. A failed open or close is tried once more; a config that gives no road is
  `unrouted`, re-checked each pass without a call. At most 5 issues a pass, none within a minute of the
  tick's kill time. `--dry-run` prints `would escalate` and when each is due. A guarded repo's issue
  and its comments name its class and host only. GitHub is called only from an armed tick of launchd's
  (no session, not `CLAUDE_UNATTENDED`), one at a time (a lock), while the registry and keel's guarded
  list read (`helmlib.guard_unread`), before the judge and after; any other tick says `would …`. A key is
  closed only where its source (runs, launches, Orca, skippers, the ship) was read. What the road
  could not deliver or settle is a `road` card on the board (`helm_render.road_cards`).
- After the finish review: a key closes only once missing 10 minutes and on two passes in a row, and a
  refused pass keeps that clock; a second class move carries every followed issue still open (`also`)
  and closes it; a close retried closes only what failed; the open's row is written before the issues
  it follows are closed; a card names the issue left open and a failed close's card ages out after 7
  days; a banner without osascript fails and the next backend is tried; one unreadable ship costs its
  own keys; a yard acts on its own store only; no `regatta/guarded` at all is "the guarded list did not
  read"; the judge without wharf-runs reads as nothing read; every road fault reaches the poll's stderr.
- After the second finish review: a stall back before a partial close's retry reopens its own issue
  (closed by the first try) and follows only what is still open; back after a close that left a
  followed issue open carries it, still carded; a refused pass writes the absences' clock under the
  road's lock, or not at all; a ship that raises half-way opens none of its keys and the pass names the
  error's class; a card for a new issue that never opened says so, with the issue still open beside it;
  a successful close is no fault line. The suite's in-process road case ran for the first time (bash 3.2
  had skipped it: an apostrophe in a heredoc inside `"$(…)"`); its expectations follow the two-miss rule.

skipper-resilience S7, `helm send`: a task handed to its scope's skipper.
- `helm send <blueprint.md | claude/branch> | --text "<task>" --repo R` (bin/sendlib.py): a committed,
  pushed blueprint, the one blueprint a handoff branch adds (`--blueprint` names one of several), or a
  brief `pickup seed --no-start` commits with its one-block blueprint; the blueprint rewritten to
  `skipper: scope` and `sent_by: <session>` (a --text block also its tier, model, effort) by one plumbing
  commit, pushed, and read back from origin; then `wharf apply --yard` over the yard's ssh alias with
  `--pinned`, `--laid-by`, and `--no-merge` when given. A repo in no scope, a scope with no yard (`scopes set <s> --yard`)
  and a torn registry are refused before anything is seeded or laid.
- The pickup: the yard's `helm skipper --status --json` polled every 30 s for 10 min — `PICKED UP … this
  session may close` (exit 0) or `NOT PICKED UP` (exit 3, the ship the yard's; 1 is only a crash); `--detach` returns at
  `LAID`. Under `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS` or `CLAUDE_UNATTENDED` --detach is forced and
  `laid_by` is unattended. A yard that does not answer, or whose helm has no `helm send`, is refused
  before anything is seeded or rewritten; a lay that left nothing on the yard is `NOT LAID`, exit 5,
  and one whose first apply failed after the plan was saved goes on as laid, saying so.
- The listener, `helm send --listen PLAN [BLOCK]`: one pull of `helm skipper --line` after `--every` minutes
  (5), then exit; ends with the session's claude; `--release` kills it by its pid file; `--status`.
- `helm skipper --line PLAN [BLOCK]`: `<ship>/<block>: <status>, worker <alive|gone> N min; k questions open,
  with <holder>; lease gen g held by <holder>`, or `ended: launched #N | failed: … | raised to <owner> (…)`.
- The send on the plan: the yard's `helm send --mark` (fenced by the lease) gives each open task `sent_by`,
  `sent_at`; `leaselib.take` writes `picked_up_at`; `state()` derives `send` (`sent` | `picked up`) and
  leaves `status` to wharf; `skipperlib.needs` counts a task sent and not picked up; `--ships` names it.
  `--status --json` gives each ship its session and whether it lives.

skipper-resilience S5, the per-scope skipper.
- `helm skipper --start SCOPE [--dry-run]` and `--stop SCOPE [--why W]`, both refused under
  `CLAUDE_CODE_SESSION_ID`: a one-shot launchd job per start (`dev.regatta.helm.skipper-<scope>-<start id>`,
  RunAtLoad, no KeepAlive) around `screen -D -m -S skipper-<scope>`, every older label booted out and the
  screen quit first; `--stop` hands the ships back to the yard first.
- `libexec/skipper-run` → `bin/skipperlib.py run`: a login every repo of the scope allows (the anchor's
  pick, else a denying repo's), refused at once when not signed in (`claude auth status`) or the anchor
  stays untrusted; the scope's Talk page, the record `<host>-<scope>.json`, then `exec claude` with the fixed brief.
- The tick's pass after wharf's (`ensure_skippers`, armed only): a lapse or a deaf skipper handed to the
  yard, a start with no ship taken in 5 minutes failed, open questions re-hailed once per (question, gen),
  the 30-minute belt, the 04:00 hand-over, at most one start per scope; three failed starts are the stall
  class `skipper won't start`. `helm skipper --ships` says when nothing but the owner's blocks is open.
- `asklib.standing_manager(host, scope)`; `resolve` and `ask_guard` take the run's scope's skipper first.
- The finish review's fixes: `--stop --dry-run` stops nothing; the runner deletes its plist first and
  refuses a stale or judged start; `CLAUDE_UNATTENDED=skipper`; `--start` over a live skipper stops it
  first; screens quit by pid; an `account allowed` crash is "could not tell"; `ask relay`'s ship event
  carries `doc` and `to`, so the re-hail names the doc where it is and the deaf rule charges only a
  question that woke the holder; re-hails go by `talk` or `file` only, retried when no road took them;
  escalation is marked on the ask; a start that took before its record went is `took`; the belt's
  idle mark is per start; the pass that logs a third failure starts no fourth; asklib's scope reader
  matches through the core's `scope_of_repo`.
- Round 2: `--start`/`--stop` and the tick's acting pass refuse `CLAUDE_UNATTENDED` and any process below a
  live session; one TAKE_WITHIN window (no 290 s gap) and a grace for a claude not yet registered; a
  scope is read through a registry key only (a glob took a worktree path); only Talk wakes a skipper —
  no Talk page refuses the start, a queued re-hail is a try, deafness counts Talk alone, a dialog
  (`waiting`) is deafness too; the runner logs to its own file; `helm skipper --escalate PLAN REF`
  (checked, stamps nothing); the stall carries the anchor, is guarded for a guarded or confidential
  scope and goes once no ship is live; the re-hail keeps the relay's reply flags and leaves a question
  relayed to another Mac alone; hand-backs are compare-and-swap (`leaselib.hand_back`); the tick's start
  evicts no recordless holder; a hand start's own failure is not one of the tick's three.
- Round 3: a relay goes to a scope skipper only for a ship its scope leases (read from skipper.json, no
  path), never a skipper's own; the tick's stops hand back only the record's session's ships; a claude
  that ends within 30 minutes of its start is a failed start though it took; questions held by mode
  ask or dnd (the task's or the plan's mode, then the ask's recorded one, as `ask answer` reads it;
  the re-hail tags the same) or answered in the doc are the owner's; a hand stop before the take
  ends that start; the start makes SCREENDIR; one bad record costs one scope; the
  stall class's read failure is a note; wharf relays a `skipper: scope` ship's Orca question by Talk
  to its skipper, else the board, never the file road.
- Its review: any end within 30 minutes of a start (a lapse, deafness, a sidecar that takes nothing,
  a crash) is a failed start; after three the tick tries once an hour; record_alive and --stop check the
  registry's procStart (UTC) against the pid's start; the runner refuses itself a minute inside
  TAKE_WITHIN; the tick's pass re-reads the kill time before each scope; choose_login tries the walk's
  other rows before refusing; a crashed `dispatch-rc trusted` is "could not tell"; the stall needs a ship
  that needs a skipper; `--escalate` checks and marks under the plan's lock.
- The finish review: a relay `resolve()` hands to the scope skipper for a missing manager never takes
  the file road (wharf's yard-held or lapsed scope ship goes to the board); a skipper's own relay
  writes no ship event; the re-hail tags the mode the question is judged in; session_ancestor checks
  the registry's procStart; a torn lease costs that ship's hand-back only, and a holder whose every
  hand-back failed is not stopped.

- The skipper-modes follow-ups (2026-10-23): a person's `helm mode` on a ship, set or clear, drops a
  refused blueprint mode (`mode_refused`); `helm mode --branch … --clear` no longer asks for a ship;
  branch-modes.json is written under `branch-modes.lock`; `helmlib.branch_override` is the branch read
  dispatch asks first; `task_mode` reads a torn registry as `ask`.

crosstalk S11b, the helm side of the lookout's fixes before arming (S7's review; S6's landing review 19–22).
- The tick runs on the laptop only, as the sweep: `poll_tick` returns on any other host.
- The board reads each peer's lookout cards over the stall cards' ssh road (a probe that finds the peer's
  core and runs its `keel lookout --status --json`), their why led by the host; once a peer answers armed, this
  Mac's card that only says that host's own lookout acts, on that host's branch, gives way to it. A
  disarmed peer replaces nothing, and a peer's own such card (about this Mac's branch) is never shown.
- A repo whose scan fails keeps the last poll's rows in `asks.json`, marked `carried`, and the file's
  `partial` names it, so the lookout keeps the keys it watches. A failed mirror clone is now a failed scan
  (one line), not an empty repo; a malformed doc skips that doc alone, and a row is carried by its repo's
  path (`src`), so a public twin's answered item never comes back.
- One deadline bounds the poll (`ASK_POLL_BUDGET`, 20 min, about 75 min before): each job gets what is
  left, capped by its own limit, none starts with under a minute left, and each child is offered its
  own kill time as `ASK_POLL_DEADLINE` (nothing reads it yet). `hail subs --fulfil` runs first, before the repos' scan.
- `sweep()` and `lookout_hail()` are one loop, `run_jobs`, with one absent-peer rule (`peer_tool`): an
  absent keel is one line naming every job it skips.

crosstalk S6, the tick lines.
- `ask poll` runs `keel lookout --if-due` and `hail subs --fulfil` on every host, outside
  `sweep()`'s laptop gate (F7; same scope as the sweep: not on a dry run or with `--repos`). An
  absent keel or hail is one line in the poll log; a failure in one stops neither the other nor the
  poll. helm's tick stays disarmed on the build Mac (`stalls.jsonl` is laptop-local).
- The board shows the lookout's open cards in Needs <owner> (doc's repo, branch, path and items, the
  why), read with `keel lookout --status --json`; none without keel or with a keel that lacks the flag.
- A guarded card drops its `ref` too (K6), and a lookout card's guard fails closed on a doc not in
  `repo@branch:path` form. hail's `(kept)` rows stay out of the poll log.
- keel: `lookout --status` takes `--json` (the one change outside helm): the cards and the runs;
  `--json` without `--status` refuses.

skipper-modes S1, S3b, S5 and its landing review.
- The skipper-modes landing review (2026-10-22): a ship's mode is a ceiling — `helm mode <ship> m`
  clears each task mode above it and says so; `helm mode --branch B [--repo R] [m] [--clear]`, the
  lowering verb for a run with no ship (`branch-modes.json`, read first by `branch_mode`, which with a
  repo skips another repo's same-named branch); `ask answer` takes the owner's route from no unattended
  caller and reads a shipless run's mode from the doc's ask.json; the board deploys only on a change,
  under a 240 s timeout; stalls' WAITING read takes the core's line, link lines after it and markup
  around it, and never a guarded repo's reply.
- Default-path change, intended (skipper-modes S1): every ASK line names the run's mode, ` — mode:
  default` when nobody set one.
- Landing on the mode's ladder (skipper-modes S3b): `helmlib.raise_refusal` — only the owner raises a
  mode, an unattended caller keeps or lowers it — in `helm mode` (`--clear` judged by the next source);
  `branch_mode` skips a run record with no `task_mode` (autofinish's own launch); the board's held
  card names the class of a landing held at a ready PR (`held_cards`, from `autofinished`); stalls'
  tick knows rule M.
- Skipper modes (S1, S5; docs/skipper-modes-2026-10-21.md): `mode` on a sent task —
  `helmlib.task_mode` (plan.json's task, its ship, DISPATCH_MODE a hint, the scope's `mode`, then
  `default`), `run_mode` (none for a session the owner types in), `branch_mode`; `helm mode <ship> [m]
  [--task T] [--clear]`; ask_guard's denial per mode; `ask relay` names the run's mode, `ask answer`
  refuses a skipper's answer in mode `ask`. The board: WAITING cards from both Macs (repo, "waiting
  on <owner>", a link; stalls' probe reads the last line only), a peer's permission prompts, course
  and GitHub links on ask cards, held dnd items in the owner's column; `ask poll` renders and deploys it.
- Suite time (2026-10-23): `tests/test_helm.sh` runs its old-names and new-names passes side by
  side, and `tests/check.sh` runs `test_ask` beside it, each printed whole in order; the `--hold`
  sidecar's two cases and the listener's parent poll for the state (`until_`) where fixed 3, 1.5 and
  0.5 s sleeps stood (the first `--hold` case waits out two passes, as the 3 s did); the `--renew`
  case drops its 1 s sleep (`until` is a float `now + TTL`). Cut short, both check.sh and test_helm's
  two passes end their suites and print what each wrote so far. All 1931 cases kept, plus one. Timed
  under load 20 to 160 on 10 cores (no quiet Mac that day): main's test_helm 15.7 min beside this one's
  12.2 at the same load; the whole check 7.5 min before (sequential, load 20), 7.4 to 8.0 after (load
  50 to 125). On a quiet Mac the check should take about its slower pass, some 1.7 min (from 4;
  not measured).

## 0.2.0 — 2026-10-22

Public: the scrub.
- No owner, host, person or overlay path in the module's text. The owner is the core's
  `regatta/owner`; the people a human task waits on are `helm/people`; the laptop is
  `regatta/laptop`, the peers and the build box's run cap `wharf-runs/ssh`; the Talk service's URL
  and hosts are `helm/talk-url` and `helm/talk-hosts` (`config-keys`).
- `asklib.relayed_by_owner` and `owner_source` replace the owner-named pair; an old
  `relayed_by_*` name still resolves. Relay-log rows go to the core's log dir.
- The board's people columns are `Needs <owner>` and `Needs <second person>` (or `others`); its
  state's header is `needs_owner` and `owner`. Its buttons mark the pressed one with `data-on`.
- Without keel, the guarded list is the core's (registry and `regatta/guarded`), not a copy.
- The suites run on a synthetic config dir (`tests/config_fixture.sh`) and need no overlay.

## 0.1.0 — 2026-10-20

The module, moved in from the overlay (regatta-modules B12), private until its scrub.
- `ask`, `asklib.py`, `helmlib.py`, `helm_render.py`, `stalls.py`, `stalls_tick.py`, `surfaces.py`
  in `bin/`; `helm` in `libexec/`, run as `regatta helm` (C1: an installed Kubernetes `helm` would
  win a bare call); `ask_guard.py` and `talk_nudge.py` in `hooks/`; the two suites in `tests/`.
- The core is found by `lib/find_core.py`, every peer through `common.tool()`; an absent peer is a
  line (`tests/peers.sh`). G26: no usage-report, no session cost; no tier_check, no week line; no
  attention, the relay row by hand. wharf-runs' harness adapters are found beside its `harness`.
- `surfaces.json` defaults to the config dir's `helm/surfaces.json` (C3); its shape is
  `surfaces.schema.json`, held equal to `surfaces.KNOWN` by the check.
- The login registry defaults to the config dir's `lighthouse/accounts.json`.
- `install.sh`: `--check`, `--plist`, `--schedule` (the ask poll, every 5 min), `--remove`.
