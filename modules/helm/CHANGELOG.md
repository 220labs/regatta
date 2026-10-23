# Changelog — helm

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
