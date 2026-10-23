# modules/helm — project management

Read `README.md` first. For an agent:

- **Public since its scrub (2026-10-22)**: every file here is on `.helloworld/allowlist.txt`, so a
  new file is listed in the change that adds it, and names no owner, host, person or overlay path.
  Those are config keys (README, "Private values"): `regatta/owner` and `helm/people` for people,
  `regatta/laptop` and `wharf-runs/ssh` for hosts, `helm/talk-url` and `helm/talk-hosts` for the
  Talk service. Fixtures are synthetic (`tests/config_fixture.sh`: Sam, Alex, laptop, buildbox);
  the guarded repo in a case is `transcripts`, the name keel's gate keeps beside the config's list.
- `asklib.relayed_by_owner` is the predicate keel's taken_answer calls; any `relayed_by_*` name
  still resolves to it (a module `__getattr__`), for a keel from before its own scrub.
- `libexec/helm` is never on PATH (C1); a caller runs `regatta helm …`, or the overlay's
  `bin/helm` shim. Inside the module, its path is `HERE.parent / "libexec" / "helm"`.
- The core through `lib/find_core.py`; a peer through `helmlib.peer()` (`asklib._peer()` in
  asklib, which keel's Stop lint loads alone and which must never exit), a harness adapter through
  `helmlib.harness_adapter()`. A missing peer is a line that names what is skipped, never a stack
  trace; `tests/peers.sh` runs every edge against a checkout of the core and helm alone, and a new
  edge gets its case there.
- `hooks/ask_guard.py` is a deny hook (C4): the overlay wires it at its own path through a
  `regatta shim --deny`, so with no core an unattended AskUserQuestion is still refused.
  `hooks/talk_nudge.py` runs to a quiet exit with no core or no keel.
- `ask poll` runs from launchd every 5 minutes (`install.sh --schedule`, or the overlay's): any
  change to `bin/ask` or what it loads is proven under `env -i HOME=$HOME PATH=/usr/bin:/bin`.
- `ask poll`'s peer jobs are one list and one loop (`poll_jobs`, `run_jobs`): `hail subs --fulfil` first,
  then the scan, then on the laptop only the tick (`poll_tick`), the stand sweep and the drain, and last
  `keel lookout --if-due`; the fulfil and the lookout run on every host (the build Mac too), the tick never off the
  laptop (`stalls.jsonl` is laptop-local; armed on two hosts it would dispatch each stall twice). One
  deadline (`ASK_POLL_BUDGET`, 20 min) bounds them all; each child is offered its own kill time as `ASK_POLL_DEADLINE`, which nothing reads yet. Tests
  stub them with `ASK_KEEL` / `ASK_HAIL` (a path that is no file stands for an absent peer, for every job)
  and the board with `PLAN_KEEL`; the board's peer reads (stall and lookout cards) go through `STALLS_SSH`; a peer's lookout cards replace
  this Mac's "its own lookout acts" cards only when it answers `armed`.
- Rename S5's old names (`plan`, `DISPATCH_PLAN`, `DISPATCH_MANAGER*`, the `plan` seam) are read
  until S8; both suites run under both.
- The lease (`bin/leaselib.py`, skipper-resilience S4) is fenced by its generation in every acting
  verb, and a ship with no `skipper.json` — every ship not laid with `wharf apply --yard` — must stay
  fenced by nothing: a refusal there is a regression in a live path. A test of `helm skipper --hold`
  sets `HELM_HOLD_PARENT`: without it the sidecar finds the nearest `claude` above the suite, the
  session running it, and `--stand-down` would end that session.
- For S5's runner (the S4 finish review, 2026-10-22): `--hold` exiting 4 means stand down, never
  re-arm — `take()` keeps no memory across processes, so a fresh sidecar would take a handed-back
  ship again. `--stand-down` signals only a live process named `claude` (a test's stand-in parent is
  a link named `claude` to `sleep`), and hands each ship back through `leaselib.stand_down()`, which
  re-checks the holder under the plan's lock. The holder's own session passes the fence before
  `SKIPPER_GEN` is read, as gens are per ship. A relay for a leased ship reaches the lease holder
  since S5 (the bullet below); `wharf apply --watch --launch` sets no `DISPATCH_SHIP`, so its
  launches are not fenced.
- The scope skipper (`bin/skipperlib.py`, `libexec/skipper-run`, skipper-resilience S5) loads a
  LaunchAgent and starts a real `claude`: its tests stub every tool (`HELM_LAUNCHCTL`,
  `HELM_LAUNCH_DIR`, `HELM_SCREEN`, `HELM_SCREENDIR`, `HELM_CLAUDE`, `HELM_ACCOUNT`, `HELM_DISPATCH_RC`, `HELM_TRUST`,
  `MEMO_SHEEP_BIN`) and run with no `CLAUDE_CODE_SESSION_ID`, which `--start` and `--stop` refuse.
  The tick's pass (`stalls_tick.ensure_skippers`) acts only armed and outside a session, and a host
  with no lease file and no skipper record must print no line of it: a line there is a regression.
  No scope `login` key is read or written (S3: `account pick` pins one hard); the runner chooses a
  login every repo of the scope allows (`account allowed`). The leases' and events' clock is
  `helmlib.now()`; `STALLS_NOW` pins only the record's age, the belt and the 04:00 hour. A relay
  goes to the scope's skipper (`asklib.standing_manager(host, scope)`) only for a ship that scope
  leases (`asklib.scope_skipper`: the ship's skipper.json, never a path) and only when the run has
  no live skipper of its own; one that names a live `DISPATCH_SKIPPER` keeps it, lease holder or
  not. A scope's skipper never reads the file queue: `asklib.relay` skips that road when `resolve()`
  hands it a relay in place of a missing manager (the ctx's `stand_in`; the re-hail keeps the road,
  as a try). Test a relay rule through `bin/ask relay` too: it passes relay() a ctx already resolved,
  which a raw-ctx case never exercises (the fifth finish review's fix review). A skipper's own relay (`SKIPPER_SCOPE`) goes to no skipper and writes no ship event: its
  escalation is the owner's. The
  brief starts the sidecar once and stands down on its exit 4 (the note above); a task in mode `ask`
  is never re-hailed to the skipper nor counted toward its deafness. The skipper runs with
  `CLAUDE_UNATTENDED=skipper` (every person's-yes guard reads it so); its runner deletes its own
  plist first, runs only the start just launched, writes its own log (inside `screen -D -m` its
  stdout is the screen's) and refuses a start with no Talk page. `--start`/`--stop` and the tick's
  acting pass refuse a session, a direct descendant of one (the registry's `<pid>.json`; a double
  fork re-parents to launchd and is not seen, so this backs the next rule, never replaces it) and any
  `CLAUDE_UNATTENDED` caller. Only Talk wakes a skipper: a re-hail goes by `talk`, else `file` (a try,
  never a delivery; never `sendmessage`), and deafness counts only Talk (a run's relay, a re-hail).
  Escalation is marked on the ask by `helm skipper --escalate PLAN REF`, which checks the ref.
  A screen is quit by `<pid>.<name>`: `-S <name>` is a prefix match. One window: a launch waits up to
  TAKE_WITHIN and fails after it. No S5 road reads a scope from a path — a scope's glob spans `/` and
  would take a worktree path; the mode of a question is read by the scope's anchor key.
- `helm send` (`bin/sendlib.py`, skipper-resilience S7) commits to a `claude/*` branch and pushes it,
  and reaches the yard over ssh: its cases run on a scratch origin and a stub `HARNESS_SSH` that plays the
  yard (its own config dir, a stand-in wharf), never a real alias. The caller reads the yard's store only
  through that ssh. A `sent` lives in the task's `send` field, never in `status`, which wharf drives; a
  listener's tests set `HELM_LISTEN_PARENT`, as the sidecar's set `HELM_HOLD_PARENT`.
- check: `bash modules/helm/tests/check.sh`. No overlay needed: each suite runs on its own config
  dir and finds its peers in `modules/*/`; it passes with `REGATTA_CONFIG=$(mktemp -d)
  REGATTA_LEGACY=/nonexistent` on a Mac (2026-10-22). A Linux runner is untried.
