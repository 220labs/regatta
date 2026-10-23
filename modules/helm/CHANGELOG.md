# Changelog — helm

## Unreleased

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
