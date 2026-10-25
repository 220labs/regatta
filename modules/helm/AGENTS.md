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
  then the scan, then the tick (`poll_tick`) on the laptop and on a host some scope's `yard` names
  (skipper-resilience S8), the stand sweep and the drain on the laptop only, and last
  `keel lookout --if-due`; the fulfil and the lookout run on every host (the build Mac too). Each ticking
  host judges its own store: the laptop still reads a yard over ssh for the shared facts and judges none
  of its runs (`stalls.self_judging()`), so no stall is judged or dispatched twice; off the laptop a torn registry is no tick (`helmlib.yard_hosts`, fail
  closed), and with no yard set every host behaves as before S8 — a test of it names its registry
  (`CLAUDE_REPOS_JSON`), never the caller's, whose yard would otherwise reach the case. One
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
  a link named `claude` to `sleep`) — the lease's and the record's pid, and the session's registry pid,
  since a skipper started through `claude-host` records the launcher's pid with `claude` its child —
  and hands each ship back through `leaselib.stand_down()`, which
  re-checks the holder under the plan's lock. The holder's own session passes the fence before
  `SKIPPER_GEN` is read, as gens are per ship. A relay for a leased ship reaches the lease holder
  since S5 (the bullet below); `wharf apply --watch --launch` sets no `DISPATCH_SHIP`, so its
  launches are not fenced.
- The scope skipper (`bin/skipperlib.py`, `libexec/skipper-run`, skipper-resilience S5) loads a
  LaunchAgent and starts a real `claude`: its tests stub every tool (`HELM_LAUNCHCTL`,
  `HELM_LAUNCH_DIR`, `HELM_SCREEN`, `HELM_SCREENDIR`, `HELM_CLAUDE`, `HELM_ACCOUNT`, `HELM_DISPATCH_RC`, `HELM_TRUST`,
  `MEMO_SHEEP_BIN`, `HELM_RC_HOSTS` — rc-hosts, whose `--launcher claude` names claude-host) and run with no `CLAUDE_CODE_SESSION_ID`, which `--start` and `--stop` refuse.
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
- The stall road (`stalls_tick.escalate`, skipper-resilience S8) acts only on a yard and opens real
  GitHub issues there: its cases stub the API with `ASK_GH_API` (a program called as `gh api` is) and
  write synthetic `helm/inbox-repo` and `helm/mention` values into the suite's own config dir. The
  repo and the mention are config values only: no module file names either. An issue leaves the
  machine, so a guarded repo's escalation carries its class and host alone — no ship, task, key,
  holder, run or what cleared it (K6) — and the road sends nothing while `helmlib.guard_unread()`
  (keel's gate, its guarded key, the confidential roots) or the registry cannot vouch, asked before the
  judge and after. It calls GitHub only from an armed tick of launchd's (no session, not
  `CLAUDE_UNATTENDED`), under a lock beside the log: a case that wants calls arms the suite's tick
  and runs it with `env -u CLAUDE_CODE_SESSION_ID`. What it could not deliver is a `road` card.
- The yard's ping and the studio brake (`stalls_tick.deadman_ping`, `helmlib.brake_refusal`,
  skipper-resilience S11): `helm tick` pings last, after the Orca read and every pass, so a tick killed
  at its deadline (every Orca read is time-limited and returns a note, so a dead Orca is not that: the
  ping still goes, with the Orca source unread — health's Orca line watches it) goes silent; that
  silence is the signal, so nothing may ping earlier in the tick. Every pass before it runs under a
  deadline `PING_RESERVE` (40 s) before ask poll's kill (`stalls_tick.ping_reserved`, S13a), on a host
  whose tick pings only, bar the judge's own Orca reads (`harness list`'s 120 s, 60 s per owned Run), which
  read no deadline yet (TODO.md); the ping takes what is left when a pass overran. The brake is re-read before the wharf
  and skipper passes, since the tick may have run minutes. A `--fail` reason is the exception's class and
  function only (it leaves the machine in an issue, K6); S13a's Orca `--fail` (the third pass in a row
  Orca did not answer, the brake off, some ship here with an Orca Run; the count in `orca-unread.json`)
  carries only `stalls.ORCA_DEAD`'s fixed words, never a note's own text, and a new note that means "no
  answer" is added there with its words. One Run's task-list unread is not one (Orca may have answered an
  error for a Run it no longer knows); only none of the asked Runs answering is. A
  ping failure is a line and never a `--fail` (the switch would report its own unreachability to
  itself); only a pass that raises, or Orca unread so, is. While the brake holds there is no Orca read, no wharf pass,
  no skipper start or stop (a skipper booted out while frozen leaves its claude orphaned and frozen)
  and no retry of the tick's own (a `wait` line: dispatch and the harness do not read the brake), and
  the ping is `--braked`. Only launchd's tick pings: a session's or an unattended run's says
  `not pinged` (the stall road's caller rule; a session's plain ping would hide a dead poll). `helmlib.brake_refusal()` is wharf's own function loaded as a module,
  never a second copy of the rule. Tests stub `deadman` (`HELM_DEADMAN`, set at the suite's head to a path that is no file — an
  absent peer — so no case outside S11's block reaches lighthouse's), the harness (`STALLS_HARNESS`) and `WHARF_LAUNCHCTL`, and move the brake with a file in
  the suite's `HOME`; a real ping or Orca read is a regression.
- The brake's windows (`helmlib.note_brake_pass`, `braked_within`, S13a): the tick records each pass's
  sight of the brake in `brake-windows.json` (the tick's state dir), only on a yard with a lease or a
  skipper record, never from `--dry-run`; `leaselib.lapsed`, `skipperlib.deaf`, `ensure_scope`'s
  TAKE_WITHIN and stale-take clocks and the stall road's RELAY_UNANSWERED subtract the time inside a
  window (`helmlib.braked_within`), so a skipper the brake froze is never handed over, stopped or
  escalated for it; a new skipper clock does the same. Every lease reader goes
  through `lapsed()` (wharf's `skipper()`, `helm send`, the tick), never its own `until` comparison. A
  window's ends are the tick's passes and err towards keeping the skipper; a test pins them by calling
  `note_brake_pass(braked, t)` with its own times, as `helmlib.now()` takes no override.
- check: `bash modules/helm/tests/check.sh`. No overlay needed: each suite runs on its own config
  dir and finds its peers in `modules/*/`; it passes with `REGATTA_CONFIG=$(mktemp -d)` on a
  Mac (2026-10-22; `REGATTA_LEGACY` is read by nothing since B14b, 2026-10-23). A Linux runner is untried.
