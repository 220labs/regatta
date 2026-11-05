# Changelog — wharf-runs

## Unreleased

- The macOS share's scope (free-ci S3's landing review): the suites name the peers they run by name, so a change to
  keel or wharf-runs runs sextant's and one to lighthouse, plumb, aurora, atlas or helloworld runs this module's;
  `share.sh linux-ids` no longer lets an edited `check_scope.py` cut the Linux matrix.
- `check`'s scope (`check_scope.py`): a change under `.github/ci/`, where share.sh, linux-tools.sh and the Linux
  list moved from `.circleci/` (free CI's S2, 2026-11-04), runs the whole line, as `.circleci/` did; a change to
  `.github/workflows/check.yml` or `check-linux.yml` runs wharf's suite, which reads both. `autofinish`'s brief
  hold holds `.github/ci/` beside `.github/workflows/`.
- `autofinish-run`'s detached waiter execs a fresh interpreter (`autofinish-run waiter`, its spec in
  `AUTOFINISH_WAITER_SPEC`) instead of running in the forked image: once the caller had resolved a name, the
  waiter's next getaddrinfo died in Apple's Network framework (fourteen waiters on the laptop, 2026-11-01/03), and a
  local landing ended with an empty dispatch log (waiter-fork-crash, 2026-11-03). `detach()` returns only once the
  waiter says "ok" over a pipe, its spec read and its arguments bound: an exec that fails, or a waiter that dies at
  its start or says nothing in 60 s (the run's own budget, if less, never under 10 s), is the caller's OSError, so
  the lock is given back. An "ok" decides it whatever else the pipe says, the pipe is read once more at the deadline
  and polled (no FD_SETSIZE limit), the spec is ASCII JSON, no descriptor lands on 0-2, and a waiter whose caller
  died mid-wait runs on rather than stop on the broken pipe (the finish review).
- kicklib: the sheep kick road presses over spacesheep's stream socket (kick-socket; TODO.md [sheep-kick], the owner's
  "yes, websockets", 2026-11-02), as the page runtime does: the full key's web session, the socket of the space
  `wharf-runs/kick-space` names (its page declares `kick/*`), `sub` then `send`, ok at the listener's first ack that
  its button began. The POST route S8 guessed (404) is gone. Its client is the `websockets` package's blocking one
  (14.0+), imported inside the road: a python3 without it, or a host with no space or key, writes one line in
  `kicks.jsonl` and the kick goes on to orca, ssh or the poll; `dispatch --roads` notes whether this host can
  press. A refused stream, a space with no press, nothing listening and no ack in time are each a verdict inside the
  road's 15 s, which the mint and the connect share; no press is sent once it is spent. 14.0 is the floor: older
  sync clients hang or wait out the close (the landing review). `tests/test_kick_socket.sh` (on the Linux list): the frame road against a stand-in
  socket, the package missing, the space key, and the whole press against a local stub server where the package
  imports. `kick-roads` names `sheep` nowhere until `kick_probe.py --peer` lands a press from each kicker.
- The builder coin draws 3 in 5 Sonnet 5.5 `high` (was 1 in 5), and plain-Opus briefs join it: a `Tier:` line naming Opus alone, no tier word and no effort but `high` (blueprintlib's `brief_rotates`). Plain Opus is the rules' default line and nothing more (`PLAIN_OPUS_RE`: a reason, another model or effort keeps a brief off). The rotation row's `brief_class` says `specced` or `plain` and its `odds` the draw's; `buildercoin.py rotates` reads a brief's class. The owner, 2026-11-03: more Sonnet rows sooner, fewer credits.

- `wharf apply --yard` refuses a node's peer (`<name>-agent`) it has no alias for by naming it a node's, never a
  `wharf-runs/ssh` row, the key the node fence forbids (2026-11-03).
- `yard-node`'s named-node payload writes `wharf-runs/node/scope`, the scope the node serves (empty on a shared
  node): the core's `nodes_here` reads it to tell the node as its scope's own yard (scopes-node-yard).

- free-ci S3 (the owner's D1 answer, E with A, 2026-11-04): the Macs' PR `check` job is scoped. check.yml's macOS-share
  step runs `.github/ci/share.sh macos --scoped`: `check_scope.py`'s verdicts over what the pull request's merge commit
  adds to its base (HEAD^1..HEAD; the checkout's fetch-depth is 2 on a pull request), a `SKIP <id>` line for each suite
  the change does not reach. A head whose change cannot be read (HEAD no merge, git or `check_scope.py` failing, a verdict
  list that does not match) or that touches `.github/workflows/`, `.github/ci/` or `check_scope.py` runs the whole share. A push, the nightly run and a hand start
  never take the step and run the whole line (a scope miss shows in the nightly run). Cases in `tests/test_check.sh`; `share.sh macos-scope` says the verdicts,
  nothing run.
- The armed sweep's last step runs wharf's `pr restack --all` in each repo (`restack_dirty()`): a ready claude/* PR
  GitHub marks DIRTY on a list file alone is restacked and pushed, anything else gets its finding on the PR; one
  `restack <repo> #<n> <branch>: …` line each, printed and logged (dirty-pr-rebase, 2026-11-04).

- finish-as-task (the owner's D3 of node-lands: "The finish should be handled like any other task"): a `/finish` is
  one fleet entry of kind `finish` under its branch's own key, carrying its tip and its rights (by, rule, merge, hold,
  from, a ship's digest; `finish_bad()` reads each, never a prompt or an allow list). `autofinish-run` puts it through
  `dispatch --queue-finish` and writes nothing of the run on the putting host; the build's claim takes it on any host
  with room (pinned where only that host can judge or run it: `--on here`, the landing ladder, a tip origin lacks), its
  job `dispatch --finish` execs `autofinish-run queued QID`, which reads the entry under its claim (`mine --json`),
  finds or makes the worktree from origin at the tip, and starts the run with `dispatch --start --queued QID --job L`
  (the claim's slot, `mine` again under the start lock, `started`, and `ended` at its end). A finish ranks ahead of a
  build of the same priority. One run per tip from the queue alone: a live finish is busy to any second put, a run's
  end leaves a tombstone (`state: ended`, `ran_on`, and the outcome `autofinish-run`'s record() writes with
  `dispatch-queue finished`) that refuses the same tip (bar a run that died, a person's launch over a cancel, a chain
  relaunch over a no-landing stop), a cancel leaves one too, and the sweep reads it (`queue_holds.ended()`); ENDED_TTL
  7 days. `dispatch-queue raise` replaces `land-raise`. Removed: the Mac-local landing queue (`queue-local/_land`,
  `land`, `land-wait`, `land-raise`, dispatch's `land_queue` and `is_landing`), and autofinish-run's peer road
  (`peer-start`, `peer-sync`, the ticket and the waiter that held a lock for a run on the peer, `wharf-runs/finish-on`).
  The sweep moves each old `_land` entry whose waiting dispatch is gone into the fleet, pinned (`drain_land`). Cases:
  `tests/test_finish_queue.sh` (new), `tests/test_rank.sh`, `tests/test_priority.sh`, `tests/test_after.sh`,
  `tests/test_autofinish_run.sh`, `tests/test_dispatch.sh`. From its finish review: a skipper's put is no person, a
  finish needs a Mac or a `finish-queue` feature line, a pinned finish claimed late takes its clean worktree, a
  `failed` start holds no person's launch, `dispatch-queue finished` is denied to a session, stamps compare as instants.

- `harness` research mode builds the Codex arm's seatbelt with its scratch `config.toml`, `AGENTS.md`, `hooks.json`
  and `auth.json` read-only (the core's `fence.codex_ro`), as council's `arm_home` names them; it named none.
- node-road (2026-11-02): orca-host's fence case names helm send as a reader of a node folder (its
  yard's ssh), beside orca-host and yard-node.
- `yard-node words --node NAME | --all [--check] [--dry-run]` (node-lands D1, carried by node-lands-base): the publish
  gate's word list to a named node over its ssh alias, hash-compared, mode 600, never over a copy edited later there;
  dispatch-queue's sweep runs `words --all` hourly on a host that names a node (`words_tend`), called from
  `cmd_sweep` so a writes-only host's early return tends it too (the node-lands landing review's finding 9).
  `cloud apply`'s hand-steps name it. Each ssh call is bounded (60 s); the copy goes live only when its sha256 is the
  list's; `--check` exits 1 on a `newer there` copy too. Cases: `tests/node.sh` N13, N13b.
- `yard-node`'s live writes (`apply`, `launch`, `snap`, `cloud apply`, `words`) refuse under `REGATTA_UNATTENDED`
  as under `CLAUDE_UNATTENDED`. `install.sh --schedule` and `--remove` off a Mac boot out the
  `<label-prefix-previous>.autofinish` job when the prefix moved. Cases: `tests/node.sh`, `tests/test_autofinish.sh`.
- Off a Mac (the Linux node; node-lands round 1, carried by node-lands-base): the suite's macOS-only lines say they are
  not run on the host and, in regatta, run by the pull request's macOS check, which `pr merge` waits for, and its end
  names every suite so left. `install.sh --schedule` schedules the sweep there through `bin/systemd-launchctl`, beside
  an overlay too (whose `bootstrap.sh --schedule` writes launchd jobs only), under the overlay's
  `<wharf-runs/label-prefix>.autofinish` label. `install.sh --check` names what a `/finish` needs on the host: the
  publish gate's word list and the `finish` skill in each login dir. Cases: `tests/test_autofinish.sh`.
- A build round's real findings are a verifier's word, never the builder's (verified-rounds): `build-review round`
  takes `--verdicts FILE`, the report of a fresh `reviewer-high` given only the round's S1, S2 and WRONG items, and
  counts its `WRONG` blocks that carry evidence (an `[S3]` head left out) as `found`, every block as `raised`;
  `--found` takes 0 alone. A round past the first is granted only when the round before confirmed a finding or its
  check was red (exit 4 otherwise). dispatch's build prompt spawns the verifier before any fix, keeps a pre-existing or
  intended finding out of the loop, and re-runs once a failing case the branch cannot reach before calling the check red.
  The landing review's round: evidence wrapped onto the next lines counts and one that says there is none does not;
  a claim that merely names `[S3]` stays counted; a held loop reopened by the answer is granted its round; a round with
  no `--check` grants none; exit 4 is asked before the cap's 3; an `[S1]` the verifier calls `UNVERIFIABLE` is kept as
  `open_s1` and `covers` will not vouch past it. The verifier reads the brief, writes a block for every item, keeps an
  S3's tag and takes a failed merge's S? items as S2. A build already running when this lands keeps its old prompt, and
  its `round --found N` is refused with the verifier's road named.
- dispatch-rc: past `DISPATCH_MAX_H`, a run whose own `check` still runs on its worktree is spared up to
  `DISPATCH_CHECK_GRACE_H` (2) more, unless its last turn hit a usage limit; an end at the cap records what it
  cut (the check's pid and out folder, the limit line) in the record's `cut` and the log. send-road-start was
  ended with its check waiting on a slot, which then passed 7/7 with no session to read it (2026-11-02). Once
  the check exits the run keeps `DISPATCH_CHECK_READ_S` (900) more inside the grace to read its summary, and an
  end after that names the check in `cut.checks_done`. This is the rc road's watcher only; the headless road's
  watchdog still ends a run at the cap. `last_answer` reads a transcript mid-write without dying on a split
  character.
- autofinish: a root `.gitattributes` that only adds `TODO.md` / `CHANGELOG.md merge=union` lines (and blanks or
  comments) no longer holds a handed landing, and rides with records under rule A: a repo's first `/todo` writes
  one (todo-driver, 2026-11-02). Any other added line, or a removed one, holds as before.
- The hand-over for mode `default` (task-shape S3, docs/task-shape-2026-10-29.md, D1-C): this Mac's landing switch,
  `autofinish arm --landings` (`~/.local/state/autofinish/landings`; off by default, refused unattended, a plain
  `disarm` turns it off with `armed`), read once at a `default` build's prompt. On, the prompt names the hand-over line
  for a done last step and the run's record says `handed=1`; dispatch-rc ends it a minute after a reply of the
  `handed` kind and leaves its slot to the landing (`idle_limit`, `lands_after`), while a WAITING line keeps its hour
  and claims at parking; `yolo_launch` starts `autofinish-run --by handed --rule C` (rule L for a deployed branch),
  needing the switch at the launch, not `armed`, and tries a cap refusal once more after `NEXT_IDLE`. Off, nothing
  changes. dispatch-rc's `last_answer` (the watcher, `ask_guard`, dispatch-queue's requeue quote) and the harness's
  `last_reply` (helm) read past Claude Code's unflagged `<synthetic>` "No response requested.", as `yolo_launch` did;
  any other synthetic entry (an API error, a limit) is the reply they read, its words kept, so a turn that ended on one
  never reads as the turn before's closing line; `yolo_launch` declines on it, naming it. Cases: `tests/test_dispatch.sh`, `tests/test_autofinish.sh`.
- Builders on the coin (S6 of the Trim design, its D2-A): while `wharf-runs/builder-rotation` says `until YYYY-MM-DD`,
  `dispatch` draws the builder of a specced brief (a `Tier:` line naming `worker` and no other model, or Sonnet
  alone; a blueprint block's `tier: worker` only through that line, which `wharf check` warns on when they differ) once where it enqueues or schedules the run, 1 in 5 Sonnet 5.5 `high`, else Opus 5.5 `high`, by
  full id. The draw rides every road as `DISPATCH_ARM` (the queue's entry, which `dispatch-queue` now accepts, the
  peer's ssh line, the one-shot's plist), never into the run's session; the fire path re-reads the brief and runs
  the arm only while it is still specced and no `--model` or `--effort` was given, records it as the run's `arm`
  and `arm_source`, and writes one row to the log dir's `builder-rotation.jsonl`. A typed model or effort, a
  principal tier, `sr-worker`, any other tier, a confidential scope, a repo in no scope and a registry that does
  not read draw nothing; a fence closed at fire time writes no row. No key, a passed day or a garbled line: dispatch
  as before, said nothing. A requeued coin run carries its arm on, not a typed model. `DISPATCH_COIN=0|1` forces the
  coin (the tests). New `bin/buildercoin.py`; `blueprintlib.brief_specced`; cases: `tests/test_builder_coin.sh`
  (portable, on the Linux list).
- `build-review covers <worktree> [--base REF]`: exit 0 when the build's loop ended clean (kept by another session)
  and the commit its last build-phase review read carries the same code change as HEAD (a hash of the diff text,
  whitespace kept; docs/, TODO.md and CHANGELOGs left out), on a clean tree and no principal build, so `/finish` may
  skip its review; never in an `in_place` repo, read at the base. `autofinish-run` allows that verb alone, and
  dispatch gives `round` and `end` to build runs only (TODO.md [second-review]'s D1-B and its landing review).
- `build-review compare` counts a held loop that was reopened once, and keeps a finish's unsorted `S?` findings.
- The build loop's round cap is `build-review cap`: the config key `wharf-runs/build-review-rounds`, 1 to 20, read at
  each round, default 3 (was a fixed 5; D2-B). dispatch's build prompt states the cap it reads.
- `build-review compare [--json]`: per branch, the build loop's rounds and outcomes beside the finish's review lines and
  the review agents' spend, split at the build's end (TODO.md [second-review], `docs/finish-second-review-2026-11-02.md`). dispatch's
  build prompt passes `--phase build` to `review-gate merge`.
- tests: the lanes make stdout and stderr blocking before they print, so a pipe left O_NONBLOCK (CI's, by the claude CLI)
  no longer cuts each lane's printout near 64 KiB; test_queue's stale-retry stand-in fires the other host's write
  when the put enters the outbox, not on the 4th sleep, which a held clone lock moved (runner-interference, 2026-11-02).

- Live limits (live-limits, 2026-11-01): the `limits` file names the run cap, check slots, headroom and the load
  rule for `regatta limit`; `check --slots`, `headroom limits` and `berth --load-key` are their trial reads; `check`
  reads the live layer before the config, as the core's readers do. `dispatch` reads the cap again at each
  judgement (`refresh_cap`): a landing waiting in the queue recounts at the cap of now, never its start's.
- dispatch: a principal tier that runs Fable (principal-architect) takes a login with Fable room (the principal
  tier's S6). The first pick is the plain one; once the fire-time brief read names a Fable tier, auto and bound
  pick again with `--room fable` and refuse when that names no login (no registry, or no `account` tool at all, runs as before). A full
  Fable week, or an unknown Fable room, queues as a full week does. A dry run names the room pick's login.
  `--account bound` scheduled for a Fable tier is refused at once when the primary's cached reading has no Fable
  room (a plan without Fable: no reset lifts it). The `== tier` line names what ran: the login and its Fable room;
  for a named `--account`, its Fable as its cached limits read it ("asked, not what ran" where it has none).
- `wharf apply` starts a claude-code block whose branch is already on origin with its brief — a sent ship's
  pinned branch, or one the block names, whose topic is the block's id — by a plain `dispatch <branch>`, never
  `pickup seed` (send-road-start; the first `helm send --text` ships after the cutover never started on their
  yard, 2026-11-01: pickup refused the topic already open on the sender's branch). Plain, not `--next`: helm
  send commits the blueprint after the seed's brief. The ship's env and the `seed` ledger line as the seed road
  writes them, `seeded_branch` the sent branch, a line a crash cut off judged by dispatch's own mark; a refusal
  that only waits (the cap's words, a queue that does not read) is marked `waited` and spends none of the
  block's starts and keeps one ledger line however long it lasts; a branch there with no brief, or holding
  work past it, is raised to the skipper and never dispatched, no start spent. The lookup and the call fit inside the start's
  400 s, so the yard's tick (at most about 545 s left for wharf) starts it. `WHARF_DISPATCH` and `WHARF_PICKUP` name stand-ins for the suite.
  The block's own `model:` and `effort:` go to dispatch; a brief or a tree that did not read waits a pass, never
  read as absent; a branch this ship dispatched before that a run has since committed on is recorded started, not
  raised; the old road's seeds pickup refused for the open topic spend no start, so a ship they stalled starts.
- `harness`'s research mode (the isolation design's S3): the copy rules (`council_copy_why`, the ~, home-repo,
  other-repo and dot rules) give way to the core's `fence.box_why`, the box a council arm's; the adapter's
  `config_why`, `CODEX_SAFE_KEYS` and `_toml_key` to `managed_why`, which refuses while an `/etc/codex/*.toml` or a
  managed-config key of `com.openai.codex` is set. `--timeout` must be finite; `--deadline` takes the caller's
  clock; the per-council and per-day counts (`research_counts`) read the records by mtime before dispatch's start
  lock; the deadline timer's `ending` is written only while the record has no end. `autofinish-run`'s
  `unattended_caller` is the core's rule. Both headers name the fences F1–F7.
- `harness`'s research mode keeps codex's shell whatever the account holds: the plugin gate and `--text-only`
  are gone. Its proxy withdraws the box's `auth.json` at codex's first request to its vendor (F7), its record's
  `credential` says when and what was on disk at the first command, and `files` names what the turn wrote
  outside the arm's dir, for council's scan.
- `harness`'s research mode starts codex under the core's fence (the council isolation design's S1): the
  seatbelt, a proxy for the turn, the box's scratch CODEX_HOME and an allowlisted environment, its own sandbox
  off (`--dangerously-bypass-approvals-and-sandbox`, which its help reserves for an external sandbox) and every
  feature judged off turned off; refused while a feature on is unjudged, and its shell while the account holds
  a plugin of the owner's. `--text-only` (shell and code mode off too) and `--web` (the proxy opens to the web).
  The permissions profile, its deny roots and the macOS-only probe list are gone with it.
- `harness run --harness codex --mode research` (principal tier S3): one read-only Codex turn over a
  scratch copy, in the foreground with a `--timeout`, under a permissions profile that extends
  `:read-only`, denies ~, the login's own home, every account's home (`/Users`; `/home` and `/root` on
  Linux), `/private/tmp`, macOS's per-user temp folders and `/Volumes` and reads the copy back in (probe 7,
  re-run with `/Users` denied); macOS only, where it was probed. `--ephemeral`, never `--approve-for-me`;
  `--review BASE` runs `codex exec review`. Judged by `--repo` (the contract, the public-repo refusal) and
  by the copy (the confidential rule on both; outside ~, outside the repo and inside no other repo, under a
  0700 run dir the council marked, never a clone); the guarded-source rule on `--repo` and the prompt file
  (`--approved`, the owner's quote for OpenAI, never from an unattended caller); Codex's `config.toml`
  holding only keys known to open nothing (no MCP server, sandbox or approval setting); `--timeout` at most
  a day.
  Unattended (CLAUDE_UNATTENDED or AUTOFINISH_CALLER_UNATTENDED) only with `--timeout` (at most 1800 s),
  `--council RUN:VERB`, at most two Codex runs per council run and twelve a day on the Mac (their counts
  and the cap read from the defaults, bar beside a stand-in codex), and a free slot under `dispatch --cap`,
  the queue's reservations counted, under dispatch's start lock until codex runs; `dispatch-rc`'s cap
  counts a running one (`research_live()`, through `running()`, from the last day's records). A Codex
  run's record now sums `usage` over every `turn.completed` and keeps each `command_execution` it ran; the
  wrapper's deadline thread and its loop write the record under one lock, each with a temp file of its
  own, and a turn that ends as its deadline fires is recorded completed (the landing reviews, 2026-10-28).
- `autofinish-run` never starts a `/finish` on a tip origin's branch has moved past (finish-stale-tip; a run on a
  seed went on though its build sat five commits ahead on origin). An origin gate on both roads, after what no tree
  moves under and before the refusals that read the tip: the branch's warm run is ended, a clean worktree behind
  origin is fast-forwarded, one line, and a person's launch lands that tip and sends it; a dirty one, or a tip apart
  from origin, is refused with the new exit 6, nothing started, where the send used to say "stays on this Mac" and go
  on. Every other caller's gates judged the old tip, so it moves the tree and stops: its next start judges the new
  one, on either road. The commits a fast-forward took in head the run's bundle (the next start's too, after a stop),
  since /finish's own step then finds nothing to take in, with the diff that shows a memo's answers.
  The peer's job, and the send's inline fallback after a peer could not take the run, refuse rather than move the tip
  the sending Mac recorded; so does a re-read once a warm run ended. Origin that cannot be read stays a start, with a
  line, unless a warm run was ended or a push refused first. `cold_prompt` blocks a typed `/finish` on exit 6, and sends a warm session on such a tip to the runner rather
  than ask for a summary commit on it.
- `autofinish-run --by chain` relaunches a landing stopped at `no-landing` on a login's usage limit ("You've
  hit your 5-hour limit · resets …"), as it does a network or sleep stop: `S4_RE` gains the limit's form,
  anchored as before, and only for the windows `account pick` judges (5-hour, weekly; a per-model, credit or
  spend limit stays S5). The relaunch picks its login afresh, a pick no row passes refuses before any session
  and spends none of the tip's two relaunches; a relaunch the peer could not take gives its counted id back
  (`uncount_chain`), so a peer whose own run on the tip had ended (adopt) leaves no relaunch spent
  (queue-followthrough; landings stopped so on 2026-10-31, seven in one Mac's records alone). The bare
  "You've hit your limit", Claude Code's extra-usage-rejected form of any window, stays S5.
- The block rule in `wharf check` (trim S4, 2026-11-02; docs/self-tuning-2026-10-26.md, "Granularity"): a block's
  optional `lines:` key, its expected code lines, shown on its graph line; a warning (never a refusal) for a block past
  1,000 and for two or more work blocks none of which waits on another (by `depends_on`, directly or through a decision). `wharf check <doc.md>` reads a Course doc's Action
  plan: each step's `· lines: <n>`, a warning past 1,000, a step with no size listed and never an error. The window is
  `BLOCK_LINES = (300, 1000)` in `bin/blueprintlib.py`, the pin trim re-reads. Cases: `tests/test_wharf.sh`.
- hail's mailbox road (the charterer design's S2, docs/charterer-2026-11-01.md): `hail REF --host PEER` that no
  ssh reaches writes a row in this Mac's `hail-mailbox.jsonl`; PEER's bell pulls it with `hail mail --pull` over
  its own alias (`--take`, recorded on the sender before any post, then `--settle`), posts it by the socket road
  under its idle and read-back rules, and reads `ended` back for a session gone on PEER. The roads and their
  order follow helm's surfaces.json row `hail.roads`. Cases: `tests/test_hail.sh` (two hosts through a stand-in
  ssh, two logins on one Mac).
- A host's run cap can differ from the default: `wharf-runs/run-cap`, `<host>:<n>`, read by `dispatch` under
  `DISPATCH_MAX_RUNS` and over its default of 3, which stays dispatch's alone (the owner, 2026-10-31: the Linux node
  at 4; 2026-11-01: a Mac at 5 by its own line, which this landing makes live, from 3). The node's 4 was a variable only its user manager held, so a peer's `--slots` over ssh read 3.
  Cases: `tests/test_systemd.sh` (runs on Linux), `tests/test_dispatch.sh`.
- The kick's ssh road can reach a host `wharf-runs/ssh` must not name: `wharf-runs/kick-ssh`, `<host>:<alias>`, read
  by kicklib alone, so a scope's node gets the kick without joining berth's probes, pickup, stalls or `account doctor`
  (docs/node-cap-kick-2026-10-31.md has the reader-by-reader audit). Cases: `tests/test_systemd.sh`, `tests/test_queue.sh`.
- A kick heard on Linux starts the sweep through `systemd-launchctl kickstart`, as on a Mac through launchctl: it no longer
  waits on the unit, and `tests/test_systemd.sh` runs it. kicklib's `<host>:<value>` keys read a value split one word per
  line, and a note after `#` is no text.
- task-shape S2, `--by handed` — the landing side (docs/task-shape-2026-10-29.md, D1-C): `autofinish-run` takes
  `--by handed` (and `peer-start` too) for a done build dispatch hands over; `landing()` judges it by `bin/autofinish`'s
  new `handed_held`, whose slice `HANDED_SLICE` is empty under D1-C (`"exclude"` is D1-A, `"brief"` D1-B), so it
  lands what a typed `/finish` lands, bar a diff or config that will not read, a binary, a `.gitattributes` change,
  the launcher's own gates and a mode that will not read; it reads paths only. Never in `PERSON_BY` or `MERGE_BY`: mode `ask` holds it, `--merge` exits 2, and
  rule M makes it a mode launch, held as one. `CHAIN_KEEPS` keeps it on a chain relaunch; `ladder_stay` keeps it on
  this Mac. dispatch's side is S3.
- Session names (the owner, 2026-11-01): dispatch names a run `build-<topic>`, `design-<topic>` (a brief at an
  architect tier), `probe-<topic>`, or a `--start`'s NAME with its own verb (`finish-<topic>`, else `work-<topic>`),
  never `run-<topic>`; every landing read `run-finish` before. Remote Control is that name plus ` · <machine>`; the
  window keeps `run · <topic> · <repo>`, which dispatch-rc matches. autofinish-run quotes the session name, read by
  dispatch's own call; its NAME to dispatch is unchanged. pickup's `<repo>: <topic>` names stay whole.
- The Engine room's S2 (docs/fleet-page-2026-11-01.md): `dispatch-queue hosts put|get` on `refs/regatta/hosts`, the
  queue ref's lease and tries with `REF` a `Fleet` parameter; a put rewrites its own host's row only, and only when it
  changed or its copy is 9 min old; the sweep's sample puts it whatever it says (`--refresh`). Every claim starts lighthouse's `hosts sample --put` detached, at most once in
  30 s, and the sweep after its claims whatever the gap (`wharf-runs/hosts-sample` off: never; the suites' fixture sets it).
  A run's record gains `login`, the label `account pick` gave it, the default login's included (`config_dir` is
  written only for another login), so the row names every run's login; the harness's Claude adapter reads it as `account`. `queue_live.sh` refuses the hosts ref too.
- task-shape S1, the ledger reads a landing (docs/task-shape-2026-10-29.md): `autofinish-run` writes a
  finisher-rotation row for every finish run, `arm` null when none was drawn (the model and effort dispatch ran),
  counted apart by `rotation`; the record and the row gain `pushed` (the sha the run's own push sent, read from
  the transcript and checked against origin at the end), `base` and `base_tip`. `rotation --settle` settles a
  `no-landing` row to `launched (settled)` only on nine conditions against the PR (a case each); a row from
  before S1 never settles; condition 9 also counts a peer Mac's run by its `autofinished` line and compares repos
  by real path. A push that found origin "Everything up-to-date" still records `pushed` (the worktree at origin's
  head); an arm-less row records the finish skill's effort. `gate_of` reads step 1 as G1r only when the review is
  the stop it names, else G1, and the gate words as words with their forms: "checkpoint" is no check, "alive" no
  live system, while "deployment", "unmerged", "automerge", "redeploy" and "deadlocked" still read. A later run
  that never started is no later run (condition 9).
- The dispatch host's run cap is 3, from 6, the same as every other Mac (the owner, 2026-10-31: "drop dispatch to 3
  actually, the default"). `dispatch --cap` still answers it for wharf and helm, and `--slots` for berth, harness and ops.
- A named node's clone unit links the modules' skills and agents into every login dir (the default `.claude` and
  each `.claude-*` beside it), one link per entry into the core its home file names, on every start of the unit: the first scope
  node had none, so every dispatched `/finish` there ended "Unknown command: /finish" and the review gate found no
  reviewer agents (2026-10-31). A `.claude-*` dir counts only with a `.claude.json`; its missing `skills/` or `agents/`
  becomes a link to the default dir's, as `account add` makes it, and one that is a link already is left alone, as is
  any entry already there bar a dangling link into a core's modules, which is removed (and linked again where a module
  still has the name). A home file naming no core says so in the unit's log. A named node's printed hands say to run
  `yard-node-clone` after a `claude login` made later. Cases: `tests/node.sh`.
- The queue's rank holds on every claim road (queue-rank, 2026-10-31): a live run's own `--next` (a re-dispatch of
  a busy branch, `replaced`) is no longer claimed past an entry ranked ahead of it that found no room. Claimed, it
  was reserved `waiting` and took its run's slot the moment that run parked, ahead of landings queued for hours;
  now it waits like any entry, and the slot goes to the best one. An entry ahead that is itself own (a landing
  whose build run still has a record) now stops the entries behind it too, and so does an `--after` entry the room
  filter sets aside on a full host once its predecessor has landed (judged only when a live run's own `--next` is
  behind it; one still waiting on its predecessor
  stops nothing); judged landed, it takes the locked count like any entry, and its stop names it in `no_room`. Cases: `tests/test_rank.sh`, one per
  road (enqueue --claim, claim, claim --event-at, sweep, poll), and the label a claim through dispatch builds.
- dispatch-queue S12, pins only where required (the owner, 2026-10-31: "making dispatches drop host pin, unless it's
  required"): `dispatch --on HOST|here` is a preference with a queue home — the entry's `prefer`; the preferred host
  claims it first, and any eligible host with room once `PREFER_GRACE` (one sweep) has passed since its put, or at
  once when the preferred host's claim found no room (it marks the entry `prefer_off`, once) or it refused it at fire
  time. `dispatch --pin HOST|here` keeps the hard pin, for a run only that host can do; `--on` with `--pin` is
  refused. An unattended run's `--next` prefers its host instead of pinning it: `running_on` holds the step there
  while the run lives, which is all `after()` needs; a put that replaces a live entry keeps its own pin, or the
  run's own typed `--pin` (`pin_kind`). A
  named login (`--account LABEL`) stays pinned, and an entry pinned before S12 is honoured. One-shots carry
  `DISPATCH_HOST_PREFER` or `DISPATCH_HOST_PIN`; `--queue` and `--status` say `prefers HOST`.
  `dispatch-queue enqueue --prefer HOST`. The run's end pins the next step to its host only when that worktree
  holds what the step needs (commits origin lacks, uncommitted work, pending answers: `held_here`; the sweep's free of a
  dead run's branch alike, and a put preferring this host, so helm's stall retry keeps `--on`), and restarts
  the grace (`freed_at`); a `--pin` run's `--next` keeps the pin; a put beside a live run with no entry is held
  by `running_on`; a preferred host that will not take an entry for its own state releases it; a release kicks
  the peers. The harness adapter's `--on`, `/later`'s named host and a blueprint block's named `host:` pass
  `--pin`; a held pin outlives a re-dispatch and each sweep of its host judges it again.
- An attended dispatch reaches the fleet queue unpinned unless a host or a login is typed (the owner, 2026-10-31:
  "all dispatches go to a shared queue unless there is a strong reason to pin to a specific host"): the login label
  `--next` inherits (`account which`) rides on a queue entry only when this host pins or prefers the entry
  already (an unattended run's `--next`, a typed `--on here` or `--pin here`; the label keeps such a preference a pin, as on main), since enqueue pins any named label to its host, or when the primary
  row may not run the repo (`account limits --all --repo`'s `denied`: a deny list, a scope's login, a tenant's repos;
  a registry that cannot tell, torn, absent or with no primary, counts as may not), which keeps main's pin: another
  host's auto pick there may have no row it may run. On a host whose registry has no primary row (the yard node's)
  the label and its pin stay. Dropped, the fired
  run's pick is `auto`; the one-shot a refusing queue falls back to keeps the label. A typed `--account LABEL` still
  pins, `bound` and `auto` ride as before, and an unattended chain's `--next` is unchanged. A plain dispatch never
  inherited the login. Cases: `tests/test_dispatch.sh` ("an inherited login pins nothing").
- A requeued run goes back to the queue at `force`, whatever its rank was (the owner, 2026-10-30: "we want to get them
  as soon as possible, so they don't block other work"): the verb's `requeue` op (`force`) sets the entry's priority and
  its `--priority` arg, while the sweep's D8-B op keeps the rank (force as high), and a run with no entry gets its put at force (`entry_of_record`). Force's own rules apply at the
  claim (one slot over the cap, a second force entry first in line, the force floor); an unattended caller's own
  `--priority force` stays refused. Cases: `tests/test_dispatch.sh` (S10), `tests/test_priority.sh`.
- confidential-reach S6's seventh review (the landing's, 2026-10-31): dispatch fetches a branch it has not seen into
  its own remote ref and judges that, never `FETCH_HEAD` (two dispatches at once judged each other's tip); every
  launch drops `DISPATCH_SPAWN_HELD`; the queue's claim drops a host-local entry whose branch this host has not got,
  `--origin` or not, rather than hand it back hourly.
- build-review (the owner, 2026-10-30: "Review inside the build"): dispatch's build prompt has every run loop
  review, fix and check in its own session before its last line: merge `origin/<main>` in once (a merge, never a rebase:
  the branch is on origin and the checkpoint push never forces), run the reviewers `/finish` step 1 runs as
  `review-gate plan --base origin/<main>` names them (a prose-only diff skips them, as `/finish` does), fix each real
  S1, S2 and WRONG, run `check <worktree>`, and repeat until a round finds nothing real and the check is green, at
  most 5 rounds; then mark its steps done. A capped or held loop ends on the WAITING line, never the hand-over line,
  in every mode. The new `bin/build-review` keeps the record (`<git dir>/claude/build-review.json`, per session: each
  round's tip, reviewers, found, fixed, left, check), refuses a sixth round (exit 3) and logs the ended loop to
  `build-review.jsonl` beside review-gate.jsonl (project and branch keys), for the later decision on `/finish`'s
  second review (docs/task-shape-2026-10-29.md phase 2, TODO.md [second-review]). A brief's `Review: finish only` line opts its run
  out. `/finish` keeps its own review. On `autofinish_exclude`. Cases: test_dispatch (the loop's text, the opt-out),
  test_build_review (the record, a dead run's rounds, the cap, a clean end borne out, a held one reopened, the log).
- force_mark (the fourth landing review, 2026-10-31): VS Code's `<ide_*>` blocks are cut as not the owner's words,
  a dash before force is the flag named, a determiner beyond the/a, a compound noun ("task force", "in force") or
  code (`force=True`, `force.py`) is talk, and dispatch-queue's refusal and checkpoint's deny no longer grant
  the mark when pasted back.
- confidential-reach S6's sixth landing review (2026-10-31): dispatch refuses for now a branch whose fetch fails
  because origin does not answer, and reads the tip again on the fire path (`spawn_tip`, `spawn_verdict`); a node
  session that dispatches a reviewed spawn is not made its skipper; a torn registry's `--origin` refusal says the
  waiting words; the spawn re-arm uses `dateat`. harness refuses for now a named branch this host has not got.
  The queue's `route()` refuses a caller in two scopes for an open repo; `--kick` and `--requeue --why` judge the
  caller by the core's resolver and `caller_dirs` (`caller_scopes`; `toplevel` and `confidential_scope` gone).
  pickup's `seed --from` refuses a session in more than one scope, and reads the gate's refusal only on a
  `dispatch:` line, before any other reading of dispatch's text, with the `--origin` retry line.
  The loop's later passes: a spawn asked from inside a scope gets no skipper, an inherited one included (a
  node's own run keeps its own); a held `--origin` marker rides into the queue as given; route's final
  refusals say "refused for good"; a `_spawn` entry whose branch this host has not got is dropped with a card;
  wharf judges an Orca block's own branch (refused for now when origin has it and this host has not).
- confidential-reach S6's fifth landing review, on the owner's accident standard (2026-10-30): every ordinary
  road asks the gate. `pickup next` and `pickup open --note` ask `confined_refusal` first, before anything is
  written; `wharf apply`'s Orca block asks the spawn gate; the queue's `route()` refuses a caller in two
  scopes for a repo of one, and a typed `enqueue` reads its session's folder; a fired one-shot's first final
  refusal writes `FAILED: refused for good`; dispatch fetches a branch it has not seen whatever its
  `--origin`; harness judges the worktree's own HEAD, refuses when its core did not import (a peer's stdin
  copy still judges nothing), and a refusal a wait fixes says the cap's waiting words. `topic_of` is the
  core's `branch_topic`. The forges (a brief at another date, an edited blueprint, an empty commit's message)
  are rows 46-48 of the border inventory, for S6b.
- The S8 review's second pass: `kick-listen install` and `remove` refuse a host whose `kick-stream` names a shared
  listener (use `--shared`); `dispatch --roads` never prints `<host>:none` for this host; the watchdog moves a refused
  plist out of LaunchAgents; `REGATTA_UNATTENDED` joins the refusal marks; the mid-pass flush survives a torn ref;
  the hold-back never reads the cached view; `program()` keeps only a completed `rc-hosts --launcher` answer; the receiver kickstarts the previous label prefix's sweep while a label move drains.
- dispatch-queue S8, the kick roads (docs/dispatch-queue-kick-2026-10-25.md; `bin/kicklib.py`): a host that enqueues
  a fleet entry it does not take kicks every eligible peer, in parallel and detached, over the first road
  `wharf-runs/kick-roads` names for it (`sheep`: a press on its spacesheep stream; `orca`: one terminal on its serve,
  `; exit`, waited for and closed; `ssh`: its alias, the core from its own `home` file), else what exists (orca where
  `orca-pairs` pairs this way, ssh where `wharf-runs/ssh` has the alias). The payload is `{kick, from, full}`, host
  names only; each verdict goes to `claude-weekly/kicks.jsonl`. The kick is off where no `kick-roads` file is.
  `dispatch --kick QID` by hand, refused for a node-local entry and from a confidential checkout (and on a torn
  registry). The receiver, `dispatch --claim --full HOSTS --from HOST` (the sheep button: `--claim --from-stream`,
  which parses SS_STREAM_DATA), notes the kick and kickstarts the host's own queue-sweep job; the sweep holds back
  3 s per higher-ranked berth of unknown room, 9 s at most, then claims. `dispatch-rc kick-listen install|remove|status
  [--shared DIR]`: the listener's button, one bounded proving run, the CLI's own `--service` in its own
  SPACESHEEP_CONFIG_DIR (refused unattended; exit 3 names the owner's key step); the sweep's watchdog boots out a
  listener its log shows refused. `dispatch --roads` prints the lines what exists gives. Carried from the S2a review:
  `hash-object --no-filters` (7.5), the sweep claims past a busy clone lock (7.3), rc-hosts asked once per process
  (7.9), `poll_tend` reads no ref when nothing can change (8), the deny list names `--kick` and says its rules are
  habit guards (11), `reached()` stated (12), the git-count label (7.10).
  The landing review's fix round: the hold-back fetches once and counts only berths the entry lets take it; a
  kick heard mid-sweep gets one more hold and claim; the Orca road reads the receiver's exit code and closes with
  `--tab`; kick threads run to their roads' own bounds; `kick-roads` reads a value split one word per line, a
  note after `#` or `(`, a host's first line (the core's check alike), and `--roads` prints notes on `#` lines;
  the confidential fence (`confidential_scope`, so `route()` too) walks every scope; the watchdog counts refused
  starts since the listener last listened and moves the plist aside, and an install starts a fresh log;
  `kick-listen` writes refuse every unattended mark, and a run's deny list names them; a refusal counts as full
  for its hour only; the core's listener row is a note off macOS.
- Every node guest gets sessionpipe (the owner, 2026-10-30: "keep sessionpipe installed, and update the machine
  builders"): `sessionpipe-install` puts Node v22.23.4 (checked against a committed sha256) and sessionpipe 0.5.0
  into `/usr/local` at first boot, and a named node's clone unit installs sessionpipe's hooks with no backfill and
  gates them at once with keel's `sheep gate` (a failed install or gate takes them out again). With no key, no sink
  is written: the node's sessions reach spacesheep once the owner puts `SPACESHEEP_SESSIONS_KEY` in the config dir's
  `regatta/.env` and runs `sheep gate` again, now one of the hands `yard-node` names after a launch or an apply.
- A named node's clone unit writes the core's `home` file, best effort (TODO.md [node-pair] (b)): from a clone the clones list
  carried that holds the core whole, else the marketplace clone `known_marketplaces.json` records; a home that names
  a core is kept, and a node with no core still finishes rather than retrying every minute.
- dispatch-queue S7's Linux half: `bin/systemd-launchctl`, launchctl's verbs over systemd's user manager, is the
  default launcher off macOS for dispatch, dispatch-queue and the core's `regatta check` (a RunAtLoad plist is a
  transient unit, run with `--expand-environment=no`, an interval or calendar plist a unit pair with an enabled
  timer, `Persistent=true` on a calendar one; the plist stays the job's definition, so every reader of it is
  unchanged, and Darwin runs launchctl as before). Its `manager` verb asks whether a user manager answers here. `dispatch-queue jobs`
  installs the sweep as a user timer there. dispatch reads the host name (`local_host`), dates (`dateat`,
  `epochof`) and caffeinate portably; dispatch-rc's watcher holds no caffeinate where there is none. The fleet
  fence on every host: a fleet entry for a confidential scope's repo is never claimed, a torn registry claims
  nothing from the fleet, and the new optional key `wharf-runs/queue-repos` narrows what a host claims
  (`<key> pinned`: only entries pinned to it; an unreadable file claims nothing). Each run is denied Read, Edit
  and Bash on every path `scope_paths()` names for each confidential repo cloned beside it (checkouts, worktrees,
  transcripts, each login dir's auto-memory), and, when the registry does not read or the fence cannot be drawn,
  every other checkout in the projects folder bar the run's own and its tools', at every level. New suite `tests/test_systemd.sh`
  (on LINUX_OK).
- `rc-hosts` reads an optional `wharf-runs/rc-hosts` key, the Macs that run Remote Control hosts (names, lower-case
  compared; absent: every Mac, as before). A Mac it leaves out wants no host and holds none, so the existing converge
  road retires each host once empty, a busy one waiting for its last session; `--check` says the key keeps hosts off
  (not "missing"), and `--agents` shows a host plist unwanted only for this as `--` pending while the hourly reaper is
  scheduled (a FAIL without it).
- `check`'s scope moves to `bin/check_scope.py`, unchanged, so `.circleci/share.sh scope` (the Linux PR check's
  trigger, docs/circleci-oauth-2026-10-30.md) asks the same rules the Macs' check uses.
- `force_mark` takes any wording that asks for force (the owner, 2026-10-30): "use the force", or force or forcing
  as a word ("help force anything", "force it through"). No mark: a refusing word within six words either side, punctuation
  ignored ("no force, high is enough", "Force? No.", "Don't, under any circumstances, force it"), a flag or rank named (`--force`, `--priority force`), a
  description ("forced to rebase", "brute force"), a word inside another, and git's or the OS's force verbs with
  any spacing (force push, force-delete, force restart, force-with-lease…). dispatch-queue's refusal says so.
  The third review: a force verb as a prefix (force-pushed, force quits), the feature's own nouns (the force mark,
  floor, rank, force-ok), a question ("why did you force it?"), a contraction without its apostrophe ("dont force it"),
  "rather than"/"instead of" force, any spelling of `--priority`, and a refusal just before any mention vetoes the
  whole message. checkpoint's deny says any wording.
- `pickup seed --beside`'s wording has its case (routed comments S5, TODO.md [routed-s4] (e)): no "behind origin" for a seed off a
  branch's tip, and a blueprint already on that branch is said to be on it.
- dispatch-queue S10, the requeue (docs/dispatch-queue-requeue-2026-10-25.md): `dispatch --requeue TOPIC|--all
  [--why] [--dry-run]` hands this Mac's busy runs back to the queue with their work saved — each op in the outbox
  first, every run ended at once (`requeued …` its reason, which the fire path, `finish()` and the sweep pass by),
  its turn's files committed through checkpoint's path, a `## Continue from here` section on its brief (its commits,
  its WIP files, its last reply quoted, a `transcript:` pointer) committed as `Requeue: <topic> from <host>`,
  pushed, and the entry queued again once origin holds that tip, else owed in the outbox, whose replay pushes the
  branch first. Refused unattended, and offline by hand (exit 3, nothing ended); warm, waiting, pinned-here,
  confidential and `--start` runs named and left (a warm one by hand gets its normal idle end). The watcher
  registers for the sleep notice (`bin/powerlib.py`): at `kIOMessageSystemWillSleep` the first watcher to take the
  host's lock runs `--requeue --all --why lid`, holding the sleep up to 20 s. The sweep reads a silent host's
  branch tip: its own `Requeue:` commit, newer than the claim, queues the entry again (D8-B). `wharf-runs/queue-mode`
  `writes` gives a sleeping host a home for its own writes; no host claims in a DarkWake. `pickup transcript
  BRANCH` fetches the cut run's log from the local archive, then the origin host's over ssh. Cases:
  `tests/test_dispatch.sh`, `tests/test_queue.sh`, `tests/test_pickup.sh`.

- dispatch hands a run the marked hand-over and queue lines (⏳); the autofinish, pickup and move skills state
  theirs with ✅ (🛑 for move's wait).
- dispatch-queue S9, after-landed and landings in the queue (docs/dispatch-queue-2026-10-25.md, the owner's "add
  after-landed"): `dispatch BRANCH --after BRANCH2` (repeatable, on `--next` too, and a seed brief's `After:` line)
  waits in the queue until `bin/landed.py` proves BRANCH2 on origin/<main> — by its content at some main commit,
  `bin/pr merge`'s record, or GitHub's merged PR, kept in the repo's `claude/after-landed.json`, with every vacuous
  proof refused (no net change, a tip on main with no fork recorded before, a gone ref) — and the fired run
  merges origin/main first (a merge, never a rebase). A predecessor archived or deleted unlanded, or waited on
  past 48 h, files one card naming both branches; the entry holds. With no queue home, `--after` runs only once
  landed. A landing (`dispatch --start`'s /finish) with no room waits in `queue-local/_land` for this Mac's first
  free slot, ranked above every build but force by its kind, its prompt and merge rights never in the entry;
  `autofinish-run` reports it `queued`. Cases: `tests/test_after.sh`.

- `pickup seed --beside` no longer warns that local main is behind origin (its base is the branch's tip), and a
  blueprint already on the base names that branch, not main (routed comments S3's fourth pass, fixed in S4).

- dispatch-queue S5, eligibility (docs/dispatch-queue-2026-10-25.md): `wharf-runs/features` (`<host>:<name>,<name>`),
  `dispatch --needs a,b` and a seed brief's `needs:` line (`pickup seed` passes it on). A host claims an entry only
  if the pin, the scope's `berths` and the repo's clone `hosts` (berth's own filters), and its feature line
  allow it, all in `dispatch-queue`'s one `eligibility()`, which `claimable()` calls; a need no host that may
  take the repo meets is `enqueue` exit 3 (dispatch: exit 2, the waiting words) and never queued, and the
  sweep cards an entry no host's config lets claim (`queue-unclaimed`, each host's reason). With a queue home
  berth's load pick retires for a run now (the queue places it); berth keeps its filters and peer probe for
  `--status` and for a one-shot. Cases: `tests/test_queue.sh`, `test_dispatch.sh`, `test_pickup.sh`.
- A label move (label-move, 2026-10-30): `wharf-runs/label-prefix-previous` names the prefix the jobs had
  before; every reader of `wharf-runs/label-prefix` takes its jobs as ours while they drain. `dispatch`'s
  `jobs()` finds a branch's job under it (`--cancel`, a reschedule, yolo's "a next step is scheduled") and
  hands it to the queue (`--prefix-previous`), whose `jobs` drops that prefix's `queue-sweep` and `queue-poll`
  once the new sweep loads, never while that job runs (launchd asked: python does not read `XPC_SERVICE_NAME` reliably); `dispatch-rc` counts a tidier under it
  as installed (tidy-soon) and `refresh-tidy` relabels it once idle; `rc-hosts` relabels each host under it
  to the new prefix, and the reaper (a plain run and `--reap`'s converge; `--check` and `--reap --dry-run`
  say it), ending a host's sessions as the owner accepted, and reports the count; `--agents` reads its jobs
  as ours. New jobs take the new prefix only. `wharf-runs/launcher-id` sets claude-host's codesign
  identifier (default `<label-prefix>-host`, as before), so a move leaves the build's stamp and its grants
  until the next signing. The run cap counts run records, never labels: a run under the old prefix counts
  as before. clock reads its own `clock-labels` globs (list both prefixes while the old jobs drain).
  The relabel notes each session it ends as a planned close, leaves a host this run is a session of for the
  hourly `--reap`, moves no untrusted host, counts only the hosts that loaded, and drops the old reaper (and
  the old tidier and its tidy-soon) only once the new one is loaded and the old one is not running;
  `--restart NAME` relabels NAME first, and `--agents --fix` never reloads a job under the previous prefix;
  `dispatch-queue jobs` that drops the old poll tends the new one at once.
- "manager" is "skipper" in wharf-runs' words and names (helm-vocabulary H2, 2026-10-29): dispatch's
  `skipper_env`, `skipper_chain`, `skipper_plist` and its `skipper`/`sk*` variables, the prompt's "your skipper",
  dispatch-rc's "failed: ended on … with skipper … live" and its status line, hail's `standing_skipper` call,
  "the tick" for "the chain manager's tick" in autofinish-run. Env names and run-record keys keep theirs.
- dispatch-queue S4, priorities and the force (docs/dispatch-queue-2026-10-25.md, D2-A and D3-A): a `force`
  entry is claimed one slot over the host's cap (at most one run ever above it; a second force entry waits
  first in line) and on headroom's force floor, `headroom check --floor 5` (avail 5 %, swap and rate kept);
  dispatch's fire path counts against the same cap (`dispatch-queue cap`). An unattended caller never
  raises: `--priority force` is refused, `high` passes only when its own run's record is high, and a `--next`
  with no `--priority` inherits its run's rank (force as high) — the record whose claude is an ancestor of
  the dispatch (`dispatch-queue caller-prio`), never a session id; no DISPATCH_LABEL exception (a fired job carries no CLAUDE_UNATTENDED), and the
  unattended refusal runs in dispatch's own bash before any queue verb. An attended session's `--priority force` needs the force mark, which
  the new UserPromptSubmit hook `hooks/force_mark.py` writes when the owner's typed message says "use the
  force" (a quoted, pasted, framed or subagent prompt never does) and dispatch spends on use; outside any
  session the flag is the owner's typing. The hook is to be wired by one line in the overlay's `bootstrap.sh --hooks` (TODO.md [queue-s4]).
- One reader of "does the queue hold this branch", `bin/queue_holds.py`, for autofinish, helm's stalls and
  sextant's soundings (one `list --all --json` each; soundings asked `has` per entry); `list --json` names the
  stores that did not read (`bad_stores`), and a torn store holds only the branches routed to it.
- From S3's reviews: a waiter from another host is live by its `put_at`, never a claim's `event_at`; the sweep
  refreshes `by_seen` each sweep; a fire-time requeue (`enqueue --refused`) is guarded, and a live
  session's queued step is kept ("queued again: … waits in the queue already"); `--if-room`'s refusal of a
  claimed entry is an `if-room-skip` line, not a `queue-failed` card; `watch` follows its step re-put while
  queued whatever its `queued_at`; a `--next`'s watch read from the last fetch is "could not tell"; a typed
  `--on auto` beside `--wait`/`--replace` with a queue home is dropped, not refused; an unattended `--next`'s
  one-shot fallback keeps its host pin. Cases: `tests/test_priority.sh`.

- `autofinish-run` says what dispatch did, not "started" before it knows (autofinish-outcome, night-landings finding 1):
  after the detach it reads the run's dispatch log — `started: …` only once the `== claude … session …` header is
  there and names this run's session, `not started: <FAILED text>` when it refused and the waiter recorded the end
  (never-started at `refused`, the lock given back, the cap's waiting words added for a room refusal), and
  `not confirmed after N s: …` on stdout past `AUTOFINISH_VERDICT_S` (120 s, less what the caller's own wait leaves).
  The peer road reads the same from the peer's job by peer-sync. Exit 5 refused; started and not confirmed exit 0,
  so cold_prompt still blocks a second /finish and dispatch still leaves the slot to the landing.
- `pickup seed --beside BRANCH`, routed comments S3's base off a branch's tip, was `--from BRANCH` until
  confidential-reach S5 took `--from SCOPE`; the two refuse together (scope-pass reviews the brief alone, never
  the commits a base off another branch would carry out). Routed S3's fix round 3.
- `dispatch` refuses the unreviewed (confidential-reach S6): a spawn — an `--origin`, a branch carrying
  `docs/handoff/*.review`, or a caller's directory in a confidential scope the repo is not in — exits 2, in
  its own words (never the cap's waiting words), unless its seed's review vouches for the brief: before
  any write, and again on the tree the run launches. A branch's review supplies its origin, so a `--next`
  or a re-dispatch of a spawn (helm's included) carries it unasked. The run is not confined: it starts
  with no inward `--settings`, for the outward fence's D5 was answered A (the rules file, the sandbox and
  the fence), not E (the seeded run sandboxed inward, which would cost it the ssh its own `dispatch
  --next` pushes over). A torn registry refuses whatever may be a spawn. dispatch-queue's claim judges a
  spawn again on the claiming host (`claim_refusal`) and hands a failing entry back `refused`; an entry
  asked from inside a node for an open repo is `confined` too, a routing flag (node-local) and no more.
- S6's landing review (2026-10-28): a caller inside a confidential scope — by the core's `scope_resolver`,
  so one in an unregistered repo a confidential glob takes counts — is refused unless the newest brief
  dispatch hands the run is the reviewed one, and refused any `--note` or `--start` prompt; an open
  caller is judged by the seed commit's own brief, so a spawned run's same-day `--next`, a re-dispatch and
  the lander's `--start` go on after the run writes its next brief over the reviewed path. A refusal no wait
  fixes fails a queued entry (dropped, with a `queue-failed` card) rather than hand it back for an hourly
  retry; one this host cannot judge yet (a torn registry, a marker its registry lacks, a branch not
  fetched) is handed back. dispatch-queue's `claim_refusal` judges every entry with an `--origin` or a
  `.review` whatever its stored `confined` (entries from before S6), every entry of a node's own queue
  (its `--note` too), and a `_spawn` entry left with neither; `route()` reads scopes through the same
  resolver. One registry read per judgement (the origin's scope comes back with the verdict). The
  `dispatch` header's torn-registry line says what a torn registry refuses and what it lets go on.
- S6's fourth landing review (2026-10-30): a fired one-shot the spawn check cannot judge yet, which the queue
  cannot take back either (its `route()` refuses a torn registry too), is re-armed ten minutes on under a new
  label (`spawn_rearm`: its flags and `DISPATCH_ORIGIN` kept, `DISPATCH_SPAWN_HELD` counted, at most six),
  said `rescheduled`, never FAILED; a final refusal says "refused for good" (helm counts it a spent retry), a
  temporary one the cap's waiting words; `--dry-run` fetches nothing; a typed caller becomes a run's skipper
  only once the spawn gate passed. dispatch-queue's `has_review` reads the run's own topic's review (the
  core's rule), an unknown marker on a `local=` store's entry drops it once, a bad `repos` type is refused at
  enqueue, and a claim never stays claimed on a crash of the check. pickup opens no tab or window on a
  spawn-gate refusal, reads `branch_origin` by the topic rule, and judges a plain `seed` or `brief` caller as
  dispatch does (its session's folder, a confidential glob). harness asks the gate before an Orca worker, a
  Codex run, an Orca retry and a resume's next turn (`spawn_refusal`); claude-code runs go by dispatch's own.
- S6's third landing review (2026-10-29): dispatch judges a claimed job of a node's queue (`local=<scope>:…`)
  as asked from inside that scope, at both judgements, never launchd's `/`; the caller is inside a scope by
  the shell's folder or its session's own (`CLAUDE_CODE_SESSION_ID`'s record, so a node session's `cd <open
  repo> && dispatch …` stays inside), and that folder becomes `DISPATCH_ORIGIN` for the queue and a
  one-shot's plist. A refusal this host cannot judge yet says `queued again` without a `FAILED` beside it
  (`spawn_back`), and a fired one-shot's is handed back through the queue rather than its plist booted out;
  the refusal's words say whether dispatching again helps. dispatch-queue's `route()` reads the caller
  first — a caller in one scope for another scope's repo is refused, a repo in two scopes queues in the
  caller's — and the repo by its checkout, refusing a split; the claim's final drop checks its remove,
  catches a store that does not answer, and cards the entry as the claim holds it. `pickup seed --from
  … --note` is refused at its arguments (a case; seed takes no `--note`).
- S3's third landing review (docs/dispatch-queue-s3-review-2026-10-28.md): a `--next` put back in the queue at
  its start says queued and the closing line, never `started`; only a login refused for a limit that resets
  (the week, the 5-hour window, a cooldown, a lock) stays in the queue at fire time — extra usage on, same login
  as, limits unknown fail plainly, and the walk too when no row would reset; `--replace` refuses every
  unattended caller (`CLAUDE_UNATTENDED`, `AUTOFINISH_CALLER_UNATTENDED`), a `DISPATCH_LABEL` no exemption; a
  caller is handed off on the run's `== started:` line (printed past every refusal), never its header;
  `--wait`/`--replace` with no `--on` keep the run in this Mac's queue past the default host; a `--next`'s entry
  watch that crashes is "could not tell" (exit 2, not handed off); the busy refusal names `--replace` to an
  attended caller only; an outbox put refused at its replay files a `queue-dropped` card; the session registry
  is scanned once per process; autofinish's `queue_hold` ignores the branch's own `running` entry.
- The queue's caller contract (S3 of docs/dispatch-queue-2026-10-25.md; inert until `wharf-runs/queue-repo`
  is set): a queued step is exit 0 and one closing line for a direct run and a `--next` alike
  (`<the pending prefix>queued <branch> (<priority>); the next step waits for a run to end; the skipper
  finishes it`), the caller's own branch handed off (`common.handed_off`, as `--on` does); a branch
  claimed here already is exit 0 too. `--wait REASON` names the waiter in the entry and prints
  `dispatch --watch <entry>`; `dispatch --watch QID [--for MIN]` (dispatch-queue's `watch`) blocks,
  printing each state, 0 at running, 3 gone, 1 past `--for` (2 a refusal), and never writes. `--replace` takes a
  claimed, waiting or running entry (queued behind it, pinned to its host) or another live session's
  queued one, which a dispatch alone now refuses. A one-shot (`--at`) enters the queue at its fire
  time, aged from WHEN. A fire-time refusal the queue keeps says `queued again: <why>` in place of the
  FAILED line; a named `--account` past its limits at fire time is one of them (it was failed and its
  entry removed). A `--next` claimed here with no run header by `DISPATCH_NEXT_WAIT` is confirmed by its
  entry (waiting, running, or held by the queue), never NOT STARTED while the queue holds it. The
  header's Limits and headroom's line name the 2026-10-08 "refused, not queued" rule superseded.
- Readers read the queue first: autofinish holds a branch whose step is an entry, whatever its last reply
  said (`queue_hold`, session or none; one `list --all --json` per sweep); pickup never opens a tab for a step the queue
  holds, and says `queued as <entry>`; wharf's `runs_busy` counts the queue's reservations; `/later`
  schedules `--at reset --priority low`.
- S3's landing review fixes (docs/dispatch-queue-s3-review-2026-10-28.md): a named `--account` past its limits
  at fire time takes the hour's skip here though pinned here (`--skip-hour`), so the host no longer re-claims it
  every pass; autofinish asks the queue of every branch about to start, and holds on any answer but 0 and 3;
  pickup stops on dispatch's "the queue does not read"; `registry_dirs` reads every Orca profile's `sessions/`,
  so `--replace`'s live-session refusal sees them; a typed `--on`'s one-shot carries `DISPATCH_HOST_PIN` and enters
  the queue pinned; `--replace` refuses an unattended caller (dispatch and `enqueue`); `watch` asks `ls-remote`
  and fetches only when the ref moved; the "not queued" line says the real exit; keel's skill and `/later` say
  the queue applies only where `wharf-runs/queue-repo` is set.
- S3's second landing review fixes (the same doc, its second review): a queued run carries `--model`/`--effort`
  only when given, so a claimed job's brief decides its tier; another live session's queued step is refused inside
  the put's CAS round (`apply_op`'s guard), so racing enqueues keep its waiter; `--replace` keeps the put's own
  pin (a typed `--on here`, a host-local `--account`); a waiter put from another host is live by that host's sweep
  (`by_seen`) or for three sweeps, never for good; a one-shot meets the depth, physical and `--if-room` refusals
  before it enters the queue, so they file no queue card; a crashed `refused` or fire-time `enqueue` is FAILED,
  never "queued again" or a run beside the put; the caller's own branch claimed here is handed off once its run's
  header shows; `watch` follows the entry it first read and exits 1 past `--for` (2 a refusal); autofinish reads
  the queue once per sweep (`list --all --json`); `--wait`/`--replace` are refused with `--at` or `--on HOST` and
  said ignored with no queue home; the host pin is `DISPATCH_HOST_PIN`, apart from a bound run's `DISPATCH_PIN`.
- `pickup seed --from`, the landing re-review (2026-10-27): the target judged against one read of the registry,
  an unregistered repo a confidential glob takes, a tenancy file written but unreadable, and a repo dispatch
  does not take are refused before any write; a plain `seed` or `brief` out of a confidential scope is refused
  (it goes by `--from`); every start path reads the origin back from the branch's `.review` and opens no tab
  for one. `dispatch --origin` takes a name only when it is a confidential scope here, refuses a newline,
  and a fired job it refuses removes its own plist.
- `pickup seed TOPIC --from SCOPE --repo PATH --file BRIEF` (confidential-reach S5): the one write out of a
  confidential scope. Refused unless the cwd is in SCOPE, SCOPE is confidential and --repo names an open
  repo (in no confidential scope, not the vault, no tenant's); then aurora's `scope-pass check --judge`
  reviews the brief, the branch name and the Seeded-By line before any write, and the seed commit
  carries `docs/handoff/<date>-<topic>.review` (the brief's sha256, both verdicts, site, provider, model,
  cost, time). Nothing pushed names the scope: Seeded-By and the `.review`'s `origin` carry the core's
  `scope_marker()`, `confidential:<8 hex>`, and a brief or topic naming the scope is refused before the
  bundle is built (the landing review). The run starts by `dispatch --next --origin <marker>`, never a
  tab. A seed's brief is its `.md` alone, so `show` never names the `.review`.
- `dispatch --origin SCOPE|MARKER`: the confidential scope a seed came out of, carried as given to the
  dispatch host and a scheduled job (escaped into the plist); a marker is read back by this host's
  registry and refused when no confidential scope has it or the registry is torn; the run's record keeps
  the name as `origin` and the marker as `origin_mark`; refused given twice, with `--start` and under
  WEEKLY_RUN. Through the queue (dispatch-queue S1, the rebase's review): an entry given `--origin` routes
  node-local to `queue-local/_spawn/` as a `.review` seed does, never the fleet ref; it carries the marker
  alone, never the name it was given (`FLAGS` takes `--origin` only as `confidential:<8 hex>`); a claimed
  job refused on its origin hands the entry back (`refused`) rather than leaving it claimed with no job. The
  origin read judges the tear and the scopes from one `read_registry()` (the core's `confidential_scopes`
  and `scope_of_marker` take `reg=`), and the record keeps `origin_mark` for a name given too.
  WEEKLY_RUN. Through the queue (dispatch-queue S1) the entry carries the marker alone, never the name it
  was given: `FLAGS` takes `--origin` only as `confidential:<8 hex>`, since an entry is pushed to the home.
- The suites delete under HOME through `rm_own` (the core's entry, 2026-10-27).
- `orca-host`: a named yard node's folder carries its Orca pairing, so no overlay table holds a row per node.
  `wharf-runs/nodes/<name>/orca-pair` lists the hosts whose Orca holds the node's guest (`<name>-agent`, the
  hostname yard-node renders) as an environment; `pair`, `check` and `--on` take it beside `orca-pairs`, and
  `--on` reaches the node by the folder's own `ssh`, never `wharf-runs/ssh`, whose every reader would reach it.
  `check` faults a node peer `wharf-runs/ssh` names, or an `orca-pairs` or `finish-on` row (autofinish-run's landing
  peer); `ssh_alias` stays `wharf-runs/ssh` only, so clock never dials a node. A node folder or key that does not read
  (a link whose target moved included), an `orca-pair` line that is no bare host, or two folders giving one peer is
  an error naming it (node pairs, 2026-10-28).
- `pickup seed --beside`: a branch gone from origin that this machine saw there (a tracking ref still here, or
  a local branch whose upstream reads `[gone]`: landed and deleted, most likely) refuses rather than seeding
  off the stale tip (S3's second landing review).

- `pickup seed --beside`: a fetch of the branch that fails (bar the branch missing from origin) refuses,
  "could not fetch … run it again", rather than seeding off a stale tracking ref (S3's landing review).
- `pickup seed --beside <branch>` (routed comments S3): the seed bases on that branch's tip — fetched, the
  local one when ahead, refused when the two diverged — names it in a `Seeded-From:` trailer and writes the
  repo's carries pointer; such a seed is still listed as one.
- `check`: a run that holds its slot but has not yet dropped its queue ticket no longer also counts as
  ahead, which made a third check wait with three slots for three on a slow runner Mac; the slot's pid
  is written right after its start (ci-fleet follow-ups, 2026-10-27).
- The queue's S2, first half (docs/dispatch-queue-2026-10-25.md): what starts a queued entry with nobody
  retrying. A run's watcher (`dispatch-rc`) runs `dispatch --claim` when its run turns parked (its slot then free),
  once each parked stretch, never for a yolo or dnd run (its end hands the slot to its landing); an orphan's end
  claims too. The `queue-sweep` job (`dispatch --sweep` every 10 min) on every Mac with a queue home, installed by
  `dispatch-queue jobs` as each run starts and at each enqueue, removed with the home; `regatta check` says the
  home and fails a Mac without the sweep. The pending poll (`dispatch --poll`, every 60 s) loaded only on a Mac
  no kick road reaches (`wharf-runs/kick-roads`), with room, while the ref holds an entry it may yet take, and
  booted out otherwise; each pass is one `ls-remote` and claims only when the ref moved or an entry turned
  claimable. G3's `event_at`: the claim stamps when the slot freed (`--event-at`, or the last end here), and the
  run's `started` line in `queue.jsonl` carries it with `wait_s`. Carried from S1's reviews: a reservation is
  spent once its job's plist is gone (and a stale job gives it back at once, `dispatch-queue unreserve`); wharf's
  `runs_busy` counts reservations; a queue job's plist carries no year; a put that lost the lease thrice says so
  and is flushed once more; an inherited mode is no raise, and the raise refusal has the cap's waiting words;
  `Fleet.read` and `write` use one git process for all entries; fewer python starts in `qreserved` and
  `queue_dispatch`. The `helm/logbook-repo` fallback stays off until the queue is switched on. Cases:
  `tests/test_queue.sh`.
- The S2 finish review's fixes: the inherited-mode exemption reads the caller's run record, never its
  `DISPATCH_MODE`; a reservation whose claimer still runs is never spent; a slow `launchctl print` is "could not
  tell", never a reload; a raced load keeps its plist, and `job_out` boots out a job with none.
- `tests/queue_live.sh <queue repo url>`: the queue's live case, run by hand against a real home on a scratch
  `refs/regatta/*` ref, `dispatch-queue`'s write path re-done in shell (a hook-less bare clone, an orphan commit
  by `commit-tree`, `push --force-with-lease`). It proves the home takes and serves the ref, a
  stale lease loses (one after the other and racing), and the ref never grows, then deletes the ref. It is not
  part of `check.sh`, because it writes a live repo.
- `dispatch-queue`, and `dispatch` through it (S1 of docs/dispatch-queue-2026-10-25.md): once a queue home is
  configured (`wharf-runs/queue-repo`, set on purpose: no `helm/logbook-repo` fallback until S2), a run now on this Mac and a `--next` are
  enqueued on `refs/regatta/queue` and claimed by compare-and-swap (an orphan commit pushed
  `--force-with-lease`), then started at once by a `RunAtLoad` job (`--from-queue`, its load-to-start
  seconds logged); a full host leaves the entry queued. A fired run refused by the cap, memory or the account
  pick goes back into the queue with the refusing host noted, which skips it an hour. One entry per branch;
  a live run's `--next` is pinned to its host and survives that run's end; a branch live on one host is
  refused on another. A claim reserves its slot until its record exists (`--slots` and the cap count it). A
  write the home refuses waits in the outbox; a claim past its 15-minute lease is the claimer's to return,
  other hosts only card it (`queue-silent`). A confidential scope's runs, and a seed carrying a `.review`,
  queue node-local (`queue-local/<scope>/`); a torn registry refuses the enqueue. `--priority
  low|normal|high|force` rides in the entry and the record (an unattended caller cannot raise it);
  `dispatch --queue [--all] [--json]`, `--sweep`, `--status` rows, `--cancel` of a queued entry. Readers'
  rule: `dispatch-queue has` exits 4 on an unreadable queue, counted as an entry (yolo's launch gate reads
  it). `dispatch-rc unfinished`. No home: nothing changes.
  Its landing review's fix round (docs/dispatch-queue-s1-review-2026-10-26.md): a claim counts only once the
  home took it; the fired job checks the entry is still its claim (`dispatch-queue mine`), so a plist left by a
  reboot never reruns a step; enqueue refuses an unattended raise itself, and a run's denied list names
  `dispatch-queue enqueue` and `claim`; one commit per write (a nonce) and one reservation file per claim; room
  counted per candidate; a reservation spent once its run's record exists; the node-local store writes its
  claims; a key held by another branch is never replaced; a re-dispatch on the branch's host replaces its entry;
  `--cancel` there clears a live entry no run is behind; an entry naming a login is pinned to its host; a
  `--next` replaces the branch's pending one-shot; a one-shot refused at fire time queues by its caller's cwd
  (`DISPATCH_ORIGIN`); what only the queue refuses falls back to the one-shot (exit 1). `dispatch-rc live` and
  `unfinished` match a run's repo by its real path too, so the cap and after() see a run whatever spelling named it.
  Its second landing review's fix round (docs/dispatch-queue-s1-review-2-2026-10-26.md): every step of a write is
  checked and an empty commit never pushed (it was git's delete refspec), a tree that does not list is torn, never
  empty; fetches into the cache clone hold its lock (two at once read as the home being down) and a push moves the
  local ref; offline, the fired job's check accepts its own put and claim still in the outbox, so the offline claim
  runs; a dead claim here (no job, run or reservation) is replaced by a re-dispatch, `--cancel` sends the outbox
  first, a refusal keeps a live one-shot's mark, a reused pid or a live watcher is read as dispatch-rc reads it; a
  queue that does not read refuses `dispatch` (exit 2) rather than scheduling a one-shot; an unattended enqueue
  carries its chain depth and a `DISPATCH_LABEL` counts only for a running job; a run's end claims; a stale job's
  `failed` cards nothing and a card's reason comes from the job's own log bytes; a full host's pass logs one
  `no-room` line; "claimed here" has its own message; a run's denied list names `dispatch-queue sweep`.
  Its third landing review's fix round (docs/dispatch-queue-s1-review-3-2026-10-27.md): a gated flag given twice
  is refused and every mode on the line judged; no unattended caller is exempt by its `DISPATCH_LABEL`; one slot
  accounting (`held()`, the ref doc's Slots), counted under dispatch's start lock: a waiting `--next` keeps its
  reservation, counted once its predecessor's slot is free, and a pinned entry's refusal skips no hour on its
  only host; a home that refuses this host's push sends the run to the one-shot (exit 1), never "queued"; any
  crash exits 5, read by dispatch as "could not tell"; a `mine` that could not read hands the claim back;
  `--cancel` boots a claimed or waiting entry's job out; a torn store fails only its own part; git under
  `LC_ALL=C`; the clone's lock bounded and an offline home remembered per process; a scope's queue has one
  name; the landing peer is autofinish-run's `peer_of()`; a typed `--on here` pins; a one-shot refuses when
  its branch runs on another host through the queue; the claim at a run's end waits for its landing, and a
  `--start`'s end claims.
  Its fourth landing review (docs/dispatch-queue-s1-review-4-2026-10-27.md), fixed at `/finish`: the claim
  counts parked runs past `DISPATCH_MAX_PARKED` as the fire path does (`dispatch-rc counted()`, one function);
  a live run's `--next` is reserved as waiting from its claim; `enqueue --refused` of an entry pinned here
  skips no hour; a disarmed host never claims a yolo or dnd entry, landing peer or not; a `--next` the queue
  cannot take meets the cap and memory before its one-shot; a never-started retry that cannot relock ends
  its entry; `has` answers 4 for any torn scope store; a landed push waits a second, not 75, for the lock.
- dispatch gives a typed skipper with no plan page one at its first run (peer-manager-relay S1, D1-A): its
  `skipper_page` asks helm's `helm page` for the ship's space once every refusal has run (a refused dispatch
  publishes nothing) and carries it as `DISPATCH_PLAN_SPACE`, so the
  run record's `plan_space`, the relay's Talk road and keel's listen reminder have it, on the peer Mac with
  `--on` too. A skipper with a page reuses it; a run passing its skipper on, or a dry run, publishes nothing.
  A refusal (helm's publish budget, no Talk on the account) still starts the run, as before, and says so in
  one line. On 2026-10-26 a build-box run parked 3 h for a laptop skipper with no page.
- Principal tiers (principal tier S5, docs/principal-tier-2026-10-26.md): blueprintlib's TIERS gains
  `principal-architect` and `principal-worker`, with TIER_RUN (fable xhigh, opus xhigh): a block naming the tier
  alone runs at it (`run_of`), one naming a lower effort or another model is refused, and its key and its
  section's Tier: line must agree. `dispatch` reads the brief's Tier: line (early, and again at fire time, which
  decides) and runs a principal tier at its model and effort; a given --model or --effort wins for its half, and
  a job's plist or a peer's command carries only the flags given. From the landing review: a given flag below the
  tier is refused (`--effort max` allowed), a Tier: line is read case-blind and one that says principal unclearly
  refuses, each read starts from the given-or-default pair (a stale early read never outlives the fire-time one),
  WEEKLY_RUN writes opus/high into its job so a principal brief refuses there, a list or map `tier:` is a problem
  line again, and a claude-code block naming a principal tier's model or effort is refused (never shown and dropped).
- `yard-node` gains named nodes and a cloud twin (host-power S6, the Hostinger half). `--node NAME` reads
  `wharf-runs/nodes/<NAME>/*`; its render adds a payload (`node/agent.payload.yaml`): a user unit that clones
  the node's repos once `gh` is signed in, and adds the marketplace. A scope node clones its scope's repos and
  its `carry` list, and its walk knows its scope's login alone; a carry entry or a login in another confidential
  scope is refused, a shared node takes none, and a torn registry refuses the render. The node with no
  `--node` renders byte for byte as before. `render agent --node NAME --post-install` wraps the render in
  `node/post-install.sh` (a NoCloud seed, cloud-init over it, the provider's network left alone; at most 48 KB,
  its instance-id stable per content). `yard-node cloud plan|apply|show --node NAME` drives the new
  `tofu/hostinger/` module (provider 0.1.23, its lock file for four platforms): the token is read in-process
  from the secrets file and reaches tofu only, the state sits at `<config>/wharf-runs/tofu/<NAME>/` with 0600
  files, `apply` refuses under `CLAUDE_UNATTENDED`, without `--yes` (after printing plan, term, data center,
  template and price) and with its state outside a vault's `_secrets`; `show` writes the address. The VPS has
  `prevent_destroy` (destroy cancels the subscription) and ignores plan, template and script after create
  (an upgrade is made in place in the provider's panel). `tests/node.sh` N8–N12.
  Checked against a live account (2026-10-27): the default plan is `hostingercom-vps-kvm4-usd-2y` (a term is
  `-1m`, `-1y` or `-2y`; the guessed `-24m` was refused at plan), `order()` reads a `-Ny` term as months, the
  token is the file's last `HOSTINGER_API_TOKEN` line, as `source` reads it (the first was a note, answered
  401), and a wrong plan lists the account's VPS plans only, not its 2,000 catalogue ids.

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
- `pickup seeds` lists a routed seed again: a doc its `Routed-By:` trailer names counts as the seed's when
  its diff is the `Routed:` line alone (`branches.seed_paths_ok`; routed comments S2's landing review).
- `pickup seed` and `pickup brief` route the paged docs a brief names (routed comments S2): each gets its
  `Routed:` line from keel's `routed line` in the seed's or brief's own commit, before any dispatch,
  with a `Routed-By:` trailer, and the brief ends with the run's own check (`keel routed check`) when it
  fits the caps. A seed runs keel's gate first and is refused while a thread on the page is unreflected,
  or when the gate cannot run; a brief is never gated. `brief --unroute` takes the line out (the
  lookout's released start). `PICKUP_KEEL` names keel (empty: none, the seed as before with a note).
  `seed --routing <thread…>` passes the threads the seed routes past the gate, and `--dry-run` (seed and
  brief) has keel log nothing (S2's finish review, findings 6 and 7).

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
- The suites wait on state, not the clock (docs/wharf-runs-suite-time-2026-10-23.md): test_autofinish_run's
  claude stub writes its reply as compact JSON, so a reply run no longer waits out DISPATCH_START_WAIT and a
  screen snapshot (27 runs × 3 s a pass); test_dispatch and test_autofinish_run poll for a TERM'd stub to go;
  test_harness's hold stub steps 0.2 s. Minutes before → after, on this Mac at load 37–63 → 17–143:
  test_dispatch 7.0 → 5.1, test_autofinish_run 4.4 → 3.0 (an A/B at one load: 4.9 → 4.2), test_harness
  0.8 → 1.2, unchanged suites test_pickup 6.2 → 5.2, test_autofinish 9.5 → 3.9, test_wharf 10.3 → 5.4; about
  12.9 min estimated on the quiet build Mac (was 14.4), short of 7: the rest is process work, D1 there.
- `tests/check.sh` runs the suites in three lanes at once (D1-A of the same doc): test_dispatch alone,
  test_harness + test_pickup + test_autofinish, every other suite (a new one lands there by itself);
  each lane's log printed whole, in lane order, when it ends, with each suite's seconds; the exit fails
  if a lane fails or its log shows `bad substitution` or `command not found` (AGENTS.md Traps).
  `WHARF_RUNS_CHECK_LANES=1` (or 2: test_dispatch alone beside the rest) for fewer. On the build Mac, under
  `bin/check`'s slot, every case kept (4493 ok lines both ways): sequential 1680 s (28.0 min, load
  12–18) → lanes 869 s (14.5 min, load 11–12; lanes 466, 653, 868 s before test_harness moved to
  lane 2) → 830 s (13.8 min, load 8–12; lanes 413, 669, 830 s).
- force-any (the owner, 2026-10-30: "force should also increase priority of a finish if needed. let's not
  discriminate on the kind of task"): a landing takes `--priority` as a build does. `autofinish-run --priority
  high|force` passes it to `dispatch --start --priority` (and through `peer-start` to the peer's job); force is
  judged in autofinish-run's own process (never an unattended caller, else `dispatch-queue force-ok`, the mark
  spent once the run started, queued or was sent), since the detached waiter drops the caller's session.
  `dispatch-queue land --priority`: force ranks the landing above every landing, takes force's one slot over the
  cap and passes on the force's memory floor; high ranks it first among landings. `dispatch-queue land-raise`
  raises a landing already queued in place (one entry, its place and waiter kept, never lowered), reached by
  `dispatch BRANCH --priority high|force` on the Mac the landing waits on and by `autofinish-run --priority`;
  the waiting `--start` recounts at the rank claimed (`land-wait` names it). `dispatch --status` shows a run's
  priority above normal. Cases: `tests/test_priority.sh`, `tests/test_autofinish_run.sh`.
- `dispatch --end` past a loaded Mac's `ps`: an empty start-time read is no evidence, so `end_session` reads
  again while the pid lives (dispatch-rc's `proc_start_settled`: 1 s apart within 4 s, each re-read 2 s at least,
  a mismatch or a timed-out read never again), as `dispatch-queue land` does for its waiter's pid and `pstart` before a record is written.
  regatta#324's CI failed `--end` on a watched, busy run at load 12-35 (inferred: a blank `ps` read makes
  `end_session` refuse; the CI log was not read). force-any's fix rounds also: the
  waiter's no-account fallback keeps an attended high and drops force (re-judged there, it was always refused); a
  peer's raise over ssh is not refused for the sender's defaulted `--at` (`DISPATCH_AT_DEFAULT`), nor any raise for
  the brief's own `After:` predecessors; a raise refuses every flag it would drop (`--account`, `--if-room`,
  `--background`, `--wait`, `--origin`, `--fallback`, `--headless`, `--force`, `--yolo`); a "kept" raise spends no
  force mark, nor a waiting `--start` raised by another; `REGATTA_UNATTENDED` is read beside `CLAUDE_UNATTENDED` at
  autofinish-run's four other marker sites. Cases: `tests/test_dispatch.sh`, `tests/test_priority.sh`,
  `tests/test_autofinish_run.sh`.

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
