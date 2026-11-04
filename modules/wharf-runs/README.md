# wharf-runs — runs that start with nobody at the keyboard

Everything that lets an agent execute on more than one Mac: the fleet, the harness, the runs
themselves. Requires the core (`regatta`); the rest of the module moves in piece by piece.

| Piece | What it does |
| --- | --- |
| `bin/orca-host` | Orca on this Mac kept to the registry: the app and its CLI, one project group per scope (anchor first, coloured, worktrees from local `main` in `.claude/worktrees/`), and the pairing to the Macs whose Orca it drives (`check`, `setup`, `scopes`, `pair PEER`, `--on PEER <verb>`); on a Linux peer the same verbs over `orca-ide`, its release `.deb` and the server's systemd user unit |
| `bin/orca-serve-agent` | a Mac's Orca run as a headless server under a LaunchAgent in the login session, so it survives a reboot and reaches the keychain (`HOST\|here [--remove] [--dry-run]`); the agent's label is a config key. On Linux the systemd user unit `orca-serve.service` with linger, the one the agent guest's cloud-init writes |
| `bin/dispatch`, `run-seed` | a seeded `claude/*` branch started with nobody at the keyboard: now, at a time, on another Mac (`--on`), or as the next step of a chain (`--next`); the run's records, its watcher and its window (`dispatch-rc`). With a queue home `--on` (a host, or `here`) is a preference — that host claims the entry first, any eligible host once it has waited a sweep or that host finds no room — and `--pin` the hard pin, for a run only that host can do (dispatch-queue S12) |
| `bin/dispatch-queue` | `dispatch`'s fleet queue: one git ref every host claims from by compare-and-swap, a node-local queue per confidential scope, the outbox and the sweep; `dispatch --queue`, `--sweep`, `--priority` are its faces. A finish is an entry like a build (finish-as-task): one rank rule for every kind of task, a finish ahead of a build of the same priority, `--priority` taken as a build takes it (`autofinish-run --priority`, or `dispatch BRANCH --priority` raising one already queued), and a tombstone per finished tip, so no host runs a tip twice. `hosts put` writes a host's row for the Engine room page to `refs/regatta/hosts` (the queue's lease, the one other ref under the owner's D6-A exception), `hosts get` reads them |
| `bin/systemd-launchctl` | launchctl's verbs (`bootstrap`, `bootout`, `print`, `kickstart`) over systemd's user manager: the launcher dispatch, dispatch-queue and `regatta check` use off macOS, so a Linux node runs the same plists — a RunAtLoad job as a transient unit, an interval or calendar job as a unit pair with an enabled timer |
| `bin/autofinish`, `autofinish-run` | the lander: a sweep that judges each idle `claude/*` worktree by the start rules in its header and, once armed on a Mac, starts a fresh unattended `/finish` on it; `install.sh --schedule` adds the sweep. `autofinish arm --landings`, the landing switch apart from the sweep's, has a done `default` build hand its landing to dispatch, `--by handed` (task-shape S3) |
| `bin/pickup` | a session's branch picked up, seeded, reviewed or moved between Macs (`/pickup`, `/move`, `/later`) |
| `bin/harness` | one set of verbs over every coding-agent CLI (Claude Code, Codex, Orca), its adapters in `bin/harness_adapters/` |
| `bin/hail` | a pointer delivered to any session `harness` names — Claude Code's inbox socket (only to one idle 60 s or more, read back from the receiver), `codex queue` by thread, Orca's mailbox, a peer Mac over ssh, else helm's Talk, the mailbox (a row the peer's bell pulls, where ssh runs only the other way) and the file road; `--when idle` keeps a subscription that `hail subs --fulfil` sends |
| `bin/wharf`, `blueprintlib.py` | a ship's blueprint checked and applied, block by block (`wharf check`, `wharf apply`); `wharf check <doc.md>` lists a Course doc's step sizes and warns past the block rule's window (`BLOCK_LINES`); `wharf apply --yard` lays it, pinned, on its scope's yard, and a plain apply of a ship whose scope has a yard is refused |
| `bin/rc-hosts` | one Remote Control host per registry repo on this Mac; `--agents` also judges the clock's automations (what each one's launcher line starts, and whether its precheck fires it) |
| `bin/launcherlib.py` | the one rule for starting a job through claude-host (ask `rc-hosts --launcher`, executable or bare); `rc-hosts`, `clock` and helm load it |
| `bin/clock` | the calendar: every agent-run job as an Orca automation, one launcher line on haiku in a neutral workspace (`schedule`, or `--launchd` for the OS form kept), launchd left the script jobs and `dispatch --at`; `list` both Macs, `check` (G5: an agent-run job on launchd, a confidential pass without its `--account`), `board` one page, `fire` a long job detached through launchd, or as an automation's precheck (seam P: a scheduled run starts no claude in Orca); `canary beat|check` a start path's heartbeat (the hourly `canary` automation's precheck fires the beat through launchd, `check` fails a beat past its window and a run that never beat) |
| `bin/yard-node`, `node/` | the yard node: a hypervisor host (Ubuntu 24.04 autoinstall, an Incus preseed) and its agent guest's `#cloud-config`, rendered from the config dir and driven over `ssh <alias> incus …` (`render`, `apply`, `launch`, `snap`, `check`; `words`, the publish gate's word list to a named node, which every host's queue sweep runs `--all` hourly); a named node (`--node NAME`) is the same guest as a cloud VPS, its scope's repos in it, bought and booted through OpenTofu (`cloud plan|apply|show`; `tofu/hostinger/`, the guest's render as a post-install script); every guest gets Node and sessionpipe in `/usr/local`, and a named node's clone unit gates sessionpipe's hooks with keel's `sheep` and writes no sink until the owner adds the sessions key |
| `bin/check` | a checkout's `check:` line run one script at a time under a few slots per Mac login |
| `bin/build-review` | the record of a build's own review loop: each dispatched build merges main in, runs `/finish`'s two reviewers, has a fresh reviewer verify each S1 and S2, fixes the confirmed ones, checks and repeats in its own session only while a round confirms a finding or its check is red (at most `wharf-runs/build-review-rounds`, 3), and records each round beside `autofinish.json` and the ended loop in the log dir's `build-review.jsonl`; a brief's `Review: finish only` line opts a doc-only run out. `covers` tells `/finish` its review may be skipped (the loop ended clean on the same code); `compare` sets the builds' review beside the finishes' |
| `hooks/cold_prompt.py` | every typed `/finish` in a `claude/*` worktree handed to a fresh run: cold or Fable at once, warm after the session commits its summary |
| `hooks/force_mark.py` | the owner's typed message asking for "force", in any wording ("use the force", "force it"; never one with a refusing word within six words, a flag or rank named, a description or a git or OS force verb), marks the session for one `dispatch --priority force` (UserPromptSubmit; quoted, pasted, framed and subagent prompts never do) |
| `bin/check_scope.py` | which commands of the check line a change reaches: `check`'s scope, and what `.circleci/share.sh scope` asks for the Linux PR check |
| `bin/queue_holds.py` | whether dispatch's queue holds a branch's next step: the one reader autofinish, helm's stalls and sextant's soundings share |
| `hooks/close_reason.py` | a host session rc-hosts closed says why in its own last line (SessionEnd; wire it last, and give SessionEnd hooks 30 s) |

The tools after `orca-serve-agent` find the core as wharf does (`lib/core_path.py`) and every peer
through `common.tool()`: wharf (a hard edge: `branches`, `checkpoint`, `session_status`), keel,
plumb's `tier_check`, lighthouse's `account` and the project-management tools `ask`, `helm` and
`helmlib` (absent: a run's prompt drops the ask lines, `wharf check` refuses). Which Mac is which,
who the owner is and where an overlay lives are config, below; the code names none of them.

## Install

As a plugin: `claude plugin install wharf-runs@regatta` (after the core). Its `bin/` is on the
Bash PATH while it is enabled. From a clone, `sh modules/wharf-runs/install.sh --check` says what
the tools here will find.

## What it reads

- **The registry**: the core's `repos_json()` — `CLAUDE_REPOS_JSON`, else
  `${REGATTA_CONFIG:-~/.config/regatta}/wharf/repos.json`. Its `repos` and `scopes` decide what
  each Mac's Orca holds.
  To preview a branch's edit of the registry, point `CLAUDE_REPOS_JSON` at that copy.
- **Peers**, through the core's `common.tool()`: `scopes` (the scope order, the anchor, twins
  last; not yet in any published module — the wharf module will carry it, the overlay's
  checkout does until then) — without it `scopes` refuses and `check` names it as a fault;
  `account` (`orca-sync`, the logins Orca holds) — without it `setup`
  skips the sync and says so.
- **Private values**, one item per line in the config dir:

  | File | What it holds | Without it |
  | --- | --- | --- |
  | `wharf-runs/orca-pairs` | `<host>:<peer>` — PEER's Orca is an environment of HOST's; `check` expects exactly these and each node folder's `orca-pair` | no Mac pairs |
  | `wharf-runs/ssh` | `<peer>:<ssh alias>` — how `orca-host --on PEER` reaches it, and `wharf apply --yard` a yard | `--on` knows no peer; `--yard` falls back to `bin/harness`'s peers |
  | `wharf-runs/node/*` | the yard node's values, one per line: `ssh`, `name`, `user`, `ssh-keys`, `tailscale` (`<role>:<address>`), `logins`, `size`, `pool`, `orca-release` (`yard-node`'s header; `orca-host setup` on a Linux box without the guest's installer installs that release too) | `yard-node` names the missing key, exit 2; `orca-host setup`, the latest release |
  | `wharf-runs/nodes/<NAME>/*` | a named node's values (`yard-node --node NAME`): the keys above, `name` defaulting to NAME, plus `orca-pair` (`<host>` per line: each HOST's Orca holds the node's guest, `<name>-agent`, as an environment; `orca-host` reads it beside `orca-pairs`, and its `--on` reaches the node by the folder's own `ssh`, never `wharf-runs/ssh`), `provider` (`hostinger`), `scope` (the registry scope it serves; none: a shared node), `carry` (`<repo key> [<sparse path>]` per line, cloned beside the scope's), `marketplace` (`owner/repo`), `plan`, `price`, `data-center`, `template`, `secrets` (the env file under the secrets folder holding `HOSTINGER_API_TOKEN`; default: the scope's first repo's), and `address`, `vps-id` that `cloud show` writes | `yard-node` names the missing key, exit 2; no token: the file and the key, exit 2; no folder or no `orca-pair`: the node pairs with no Mac; a folder or key that does not read: `orca-host` names it, as a missing `orca-pairs` with an overlay |
  | `wharf-runs/tofu/<NAME>/` | written, not read by hand: the node's OpenTofu state, 0600; `cloud apply` refuses unless this path resolves into a vault's `_secrets` (the state holds the VPS's root password) | `cloud plan` and `show` make it; `apply` refuses |
  | `wharf-runs/serve-label` | the LaunchAgent label `orca-serve-agent` installs, first non-blank line; read on the Mac the agent is installed on (not on Linux: the unit is `orca-serve.service`) | `org.regatta.orca-serve` |
  | `wharf-runs/serve-label-previous` | an older label `orca-serve-agent` boots out and removes first, so one agent serves | none |
  | `wharf-runs/dispatch-host` | the Mac a run goes to when `dispatch` names none (`--on`); it has no larger run cap since 2026-10-31 (`wharf-runs/run-cap` below) | the first peer of `wharf-runs/ssh`, with one line on stderr; none, this Mac |
  | `wharf-runs/label-prefix` | the reverse-DNS prefix of the launchd jobs `dispatch`, `dispatch-rc`, `rc-hosts` and the sweep write and find (`<prefix>.dispatch.<repo>.<topic>…`, `<prefix>.autofinish`) | `org.regatta.claude` |
  | `wharf-runs/label-prefix-previous` | the prefix the jobs had before a label move, one word: its jobs are still ours while they drain. `dispatch` finds and clears a branch's job under it (`--cancel`, a reschedule), and the queue drops its `queue-sweep` and `queue-poll` once the new sweep loads; `dispatch-rc refresh-tidy` relabels its tidier; `rc-hosts` relabels its hosts and reaper (a plain run, or `--reap`'s converge; a host's sessions end with it) and reports the count, and `--agents` reads its jobs as ours; the core's check reads its `queue-sweep` while the new one is absent. New jobs take `label-prefix` only. Equal to it: none | none: no job under another prefix is ours |
  | `wharf-runs/launcher-id` | claude-host's codesign identifier, which `rc-hosts --grant` signs it with and its build stamp holds; set it to the old `<prefix>-host` before a label move, so the move leaves the build and its grants as they are until the next signing | `<label-prefix>-host` |
  | `wharf-runs/rc-hosts` | the Macs that run Remote Control hosts (`rc-hosts`): host names, separated by spaces, commas or lines, compared lower-case. A Mac the key leaves out wants no host, and the plain run and the hourly `--reap` retire each one once its last session is gone; `--check` says the key keeps hosts off there. A key written empty names no Mac | absent: every Mac whose registry entry names it runs its hosts |
  | `wharf-runs/public-repos` | repo folder names a Codex run through `harness` stays out of, beside the overlay's own checkout and anything under `projects/oss/` | those two only, with one line on stderr |
  | `wharf-runs/brake-label` | the launchd job the studio brake stops (SIGSTOP), first non-blank line; a `wharf` start waits while that job's process is stopped, as it does while the brake's sentinel file (`.studio-brake` in the home folder) exists | only the file brakes |
  | `wharf-runs/headroom` | `<host>:avail=<min % free>,swap=<max GB>,rate=<max MB/s swapping>`, `*:` for any other host — the memory `headroom` lets `dispatch` start a run in; the same names on macOS and Linux | 10 % free, 50 MB/s, no swap rule |
  | `wharf-runs/run-cap` | optional; changed live with `regatta limit set run-cap <host>:<n>` (as `check-slots`, `headroom`, `load-max` and `load-margin`: this module's `limits` file; the core's README, Limits). `<host>:<n>`, a whole number from 1 to 999: the runs that host holds at once, its first line winning, a value split one word per line reading as one and a note after `#` or `(` as nothing; `DISPATCH_MAX_RUNS` over it. `dispatch --cap` answers it for wharf and helm, and `--slots` for berth, so a peer reads what the host starts by. No `*` line: the default is `dispatch`'s own. A line that is no cap reads as none, said on stderr | 3 |
  | `wharf-runs/load-max` | `<load per core> [log]` — a host whose 5-minute load per core is at or over it is passed over for the next one its scope allows; `log` records the pick without acting on it | 1.5; log only while `load-margin` is unset or `log` too |
  | `wharf-runs/finisher-rotation` | `until YYYY-MM-DD`: the finisher rotation's switch and its last day. `autofinish-run` draws each finisher by coin, Opus 5.5 or Sonnet 5.5 at `medium`, and records the run in the log dir's `finisher-rotation.jsonl`; with the rotation off every finish run still writes its row, `arm` null (task-shape S1). A confidential scope's repo, or one in no scope, keeps today's finisher (`autofinish-run`'s header; `autofinish-run rotation` reads the rows back) | today's finisher, dispatch's default model |
  | `wharf-runs/builder-rotation` | `until YYYY-MM-DD`: the builder rotation's switch and its last day (S6 of the Trim design). A run whose brief is specced — its `Tier:` line names `worker` or Sonnet — or plain Opus — Opus alone, no tier word, no effort but `high` (since 2026-11-03) — and that no `--model` or `--effort` was given for draws its builder once where `dispatch` enqueues or schedules it, 3 in 5 Sonnet 5.5 `high`, else Opus 5.5 `high` (1 in 5 until 2026-11-03); the row's `brief_class` says which class (trim does not split by it yet: TODO.md [trim-brief-class]); every road carries the draw (`DISPATCH_ARM`), and the run's record and one row in the log dir's `builder-rotation.jsonl` keep it, which trim reads as `arm_source: coin`. A confidential scope's repo, one in no scope or a registry that does not read draws nothing. The fire path asks the key again on the host the run fires on, so every host that claims runs needs it (the overlay's config line on each, the Linux node included): a host without it drops the arm, said in the run's log (`bin/buildercoin.py`'s header) | today's builder: opus/high, or a principal tier's |
  | `wharf-runs/load-margin` | `<load per core> [log]` — how much lighter a later host must be than the ones passed over | 0.5; log only while `load-max` is unset or `log` too |
  | `wharf-runs/build-review-rounds` | optional. The build loop's round cap, a whole number from 1 to 20 (`build-review cap`), read at each round, so a change holds from the next one; a value split one word per line reads as one, a note after `#` or `(` as nothing. A value that does not read is the default, said on stderr | 3 |
  | `wharf-runs/queue-repo` | the home of `dispatch`'s fleet queue (`dispatch-queue`'s header): `owner/name` on GitHub, or a path or URL; `off` turns the queue off. Every host that claims needs write on it; set the URL that host's git reaches | none: no queue, and `dispatch` runs as before it (`helm/logbook-repo` stands in once S2 lands) |
  | `wharf-runs/queue-repos` | the repos this host claims from the fleet queue, one repo key per line; `<key> pinned` takes that repo's entries only when pinned here (`--pin`, a named login; a preference is no pin: dispatch-queue's `fleet_fence`) | every repo cloned here |
  | `wharf-runs/queue-mode` | optional (dispatch-queue S10(g)). `writes`, or `<host>:writes` for one host: that host's queue home is for its own writes alone — `dispatch --requeue`'s ops, replayed from the outbox by its sweep at wake. It enqueues none of its own runs and claims nothing; `claim`, the default, as before. No host claims in a DarkWake (`pmset -g systemstate` without Graphics) | `claim` |
  | `wharf-runs/hosts-sample` | optional (the Engine room's S2). `off`: the sweep and the claims never start lighthouse's `hosts sample --put`, so this host puts no row on `refs/regatta/hosts` (`dispatch-queue hosts`); the suites' fixtures write it | on wherever a queue home and lighthouse are |
  | `wharf-runs/kick-roads` | optional (dispatch-queue S8, `bin/kicklib.py`): the kick's switch and its roads, `<host>:<road>[,<road>…]` (`sheep`, `orca`, `ssh`, tried in the order the line names them) or `<host>:none`; a value split one word per line, and a note after `#` or `(`, read as one line, a host's first line winning. The file's presence turns the kick on: a host that enqueued what it does not take kicks every eligible peer over the first road that takes it. A host with no line gets what exists: `orca` where `orca-pairs` names the pair this way, `ssh` where `wharf-runs/ssh` or `wharf-runs/kick-ssh` has its alias; `sheep` only where a line names it (a kicker cannot see a peer's listener; `dispatch --roads` prints what exists here, this host's listener included) | absent: no kick, and the pending poll is every host's way to hear |
  | `wharf-runs/kick-ssh` | optional (`bin/kicklib.py`): `<host>:<ssh alias>`, read by the kick alone, after `wharf-runs/ssh`. For a host the ssh road may reach that no other reader of `wharf-runs/ssh` may: a scope's node, which berth would otherwise probe and place one-shots on, and pickup, stalls and `account doctor` would read. A line here is a road for `reached()`, as an alias in `wharf-runs/ssh` is; it reaches a host the entry's scope `berths` or a `wharf-runs/features` line name, since a repo with no berths takes its peers from `wharf-runs/ssh` alone | none: the ssh road reaches only what `wharf-runs/ssh` names |
  | `wharf-runs/kick-stream` | optional (S8): `<host>:<stream>`, the spacesheep stream a host's kick listener hears on, for a listener shared through `--on-dir` (`dispatch-rc kick-listen install --shared DIR`) | `kick/<host>` |
  | `wharf-runs/power` | optional (S10(e), read by helm's stalls). `<host>:sleeps` for a host that may sleep, beside the core's laptop, which may unless its line says otherwise: unreachable, with no queue word of its own younger than two sweeps, it reads `asleep`; any other host stays `unreachable` | only the laptop may sleep |
  | `wharf-runs/features` | optional. One `<host>:<name>,<name>` line per host: the features that host has, lower-case opaque names a run asks for with `dispatch --needs a,b` or a `needs:` line in a seed brief. A host claims a queued run only if its line names every need; a host with no line meets none, and a need no host that may take the repo meets is refused at enqueue (exit 3), never queued. Example: `host-a:feat-a,feat-b` | none: nothing meets a need |

  The core's own keys are read too: `regatta/laptop` (the Mac with a screen: a run's window opens
  there only), `regatta/owner` (the name the closing lines and refusals address, and the `by` of a
  marker the owner writes), `regatta/overlay` (the overlay checkout: a run's default repo, and the
  `bin/dispatch` its jobs name). With an overlay installed (that marker) `regatta check` names a missing key
  (bar the two `serve-label` keys, `brake-label`, `headroom`, `finisher-rotation` and `builder-rotation`, optional); the tools themselves never refuse over one they did
  not refuse over before: they take the default and say so on stderr. Host names are compared lower-case.
- **On a peer** (`--on PEER`): the copied script finds that Mac's own core (its `home` file or
  plugin) and reads that Mac's registry and config, so the peer needs the core installed, and
  the two keys where it has an overlay.

## Hail

`hail REF (--text T | --file F) [--kind event|report|ask] [--about REPO:BRANCH:DOC[#Dn]] [--thread ID]
[--host here|<peer>] [--when now|idle] [--dry-run] [--json]` prints one record, `{road, verdict, target, at}`,
the verdict `delivered`, `queued`, `held`, `unreachable` or `refused`. The frame is fixed text,
`HAIL <kind> from <sender> — <text> — about <repo>:<branch>:<doc>#<Dn> @<sha>`: a pointer, never an
answer's words (a text carrying one is refused). A hail is data to its receiver; it approves nothing.
It keeps `hail.jsonl` and the `--when idle` rows, `hail-subs.jsonl`, in keel's state dir
(`MEMO_STATE_DIR` moves it). Without helm's `asklib.py` the Talk and file roads
are skipped, said in the record.

**The roads, in order:** socket (any Claude Code login on the target's Mac whose sessions share its
registry, as the login dirs do by link; idle only, read back from the receiver; a session whose record sits
in another registry, an unlinked login's or an Orca profile's, is unreachable by it), codex, orca, talk, mailbox, file. The target's own road goes first; the rest follow helm's
`surfaces.json` row `hail.roads` (missing: that order), and a road left out of it is never taken.

**The mailbox** is the Claude-only road between Macs where ssh runs one way (a yard reaches no laptop).
`hail REF --host PEER` that no ssh reaches writes a row, `hail-mailbox.jsonl` in the sending Mac's state
dir, addressed to the session on PEER. PEER's bell (`ask poll`, every 5 minutes on every host) runs
`hail mail --pull`: over its own alias to each peer it takes its rows (recorded there first, so two pulls
never take one row at once), posts each by the socket road under the same idle and read-back rules, records
the verdict in its own ledger and settles it there (a lost settle is settled from the ledger at the next take,
never posted twice). A row is written only for a host whose pull the sender saw within a day; otherwise the
record says `unreachable`.
A row whose session has ended on PEER comes back `ended`, a line in the sender's `hail.jsonl`; a busy
session's row, or one for a session PEER never ran, waits for the next bell, and expires unsent after
72 hours. `hail mail` lists a Mac's rows. Known limitation: a receiver with no ssh alias to the sender's
host and no Talk (a claude.ai/code cloud session) gets nothing; the record says `unreachable`.

## Schedule

`sh modules/wharf-runs/install.sh --schedule` writes and loads one launchd agent, `bin/autofinish
--sweep` every 10 minutes (it starts nothing until `autofinish arm` on that Mac); `--remove` takes it
away. Where an overlay is installed (its `regatta/overlay` marker in the config dir) it refuses on a Mac: the
overlay schedules the sweep itself. Off a Mac (the Linux node) the overlay schedules nothing, so the job goes
through `bin/systemd-launchctl` as a user timer, beside an overlay too, under `<wharf-runs/label-prefix>.autofinish`
where that key is set; a prefix moved (`label-prefix-previous`) boots the old job out. `--check` also names what a
`/finish` needs on the host: the publish gate's word list and the `finish` skill in each login dir.

## Check

`bash modules/wharf-runs/tests/check.sh` — scratch paths only; no Orca, no network, no real launchd
(macOS). The suites run in three lanes at once, test_dispatch alone in one, each lane printed whole, in lane order,
when it ends; `WHARF_RUNS_CHECK_LANES=1` runs them one after another. A suite the checkout lacks is
skipped with a line.
