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
  `SKIPPER_GEN` is read, as gens are per ship. Not built here, and S5's: a relay for a leased ship
  still goes to the run's skipper or the standing manager, not the lease holder
  (`asklib.standing_manager(host, scope)`); `wharf apply --watch --launch` sets no `DISPATCH_SHIP`, so
  its launches are not fenced.
- check: `bash modules/helm/tests/check.sh`. No overlay needed: each suite runs on its own config
  dir and finds its peers in `modules/*/`; it passes with `REGATTA_CONFIG=$(mktemp -d)
  REGATTA_LEGACY=/nonexistent` on a Mac (2026-10-22). A Linux runner is untried.
