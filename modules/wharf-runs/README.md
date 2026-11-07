# wharf-runs — runs that start with nobody at the keyboard

Everything that lets an agent execute on more than one Mac: the fleet, the harness, the runs
themselves. Requires the core (`regatta`); the rest of the module moves in piece by piece.

| Piece | What it does |
| --- | --- |
| `bin/orca-host` | Orca on this Mac kept to the registry: the app and its CLI, one project group per scope (anchor first, coloured, worktrees from local `main` in `.claude/worktrees/`), and the pairing to the Macs whose Orca it drives (`check`, `setup`, `scopes`, `pair PEER`, `--on PEER <verb>`); on a Linux peer the same verbs over `orca-ide`, its release `.deb` and the server's systemd user unit |
| `bin/orca-serve-agent` | a Mac's Orca run as a headless server under a LaunchAgent in the login session, so it survives a reboot and reaches the keychain (`HOST\|here [--remove] [--dry-run]`); the agent's label is a config key. On Linux the systemd user unit `orca-serve.service` with linger, the one the agent guest's cloud-init writes |
| `bin/dispatch`, `run-seed` | a seeded `claude/*` branch started with nobody at the keyboard: now, at a time, on another Mac (`--on`), or as the next step of a chain (`--next`); the run's records, its watcher and its window (`dispatch-rc`). With a queue home `--on` (a host, or `here`) is a preference — that host claims the entry first, any eligible host once it has waited a sweep or that host finds no room — and `--pin` the hard pin, for a run only that host can do (dispatch-queue S12) |
| `bin/dispatch-queue` | `dispatch`'s fleet queue: one git ref every host claims from by compare-and-swap, a node-local queue per confidential scope, the outbox and the sweep; `dispatch --queue`, `--sweep`, `--priority` are its faces. A finish is an entry like a build (finish-as-task): one rank rule for every kind of task, a finish ahead of a build of the same priority, `--priority` taken as a build takes it (`autofinish-run --priority`, or `dispatch BRANCH --priority` raising one already queued), and a tombstone per finished tip, so no host runs a tip twice. `hosts put` writes a host's row for the Engine room page to `refs/regatta/hosts` (the queue's lease, the one other ref under the owner's D6-A exception), `hosts get` reads them (`--cached` skips the fetch); the page's verbs (the Engine room's S4): `repin QID HOST|any` and `cancel QID`, each refused to an unattended caller, and `features` for the row; `dispatch-rc settle --stale` ends the old peer road's records no run is behind |
| `bin/systemd-launchctl` | launchctl's verbs (`bootstrap`, `bootout`, `print`, `kickstart`) over systemd's user manager: the launcher dispatch, dispatch-queue and `regatta check` use off macOS, so a Linux node runs the same plists — a RunAtLoad job as a transient unit, an interval or calendar job as a unit pair with an enabled timer |
| `bin/autofinish`, `autofinish-run` | the lander: a sweep that judges each idle `claude/*` worktree by the start rules in its header and, once armed on a Mac, starts a fresh unattended `/finish` on it; `install.sh --schedule` adds the sweep. `autofinish arm --landings`, the landing switch apart from the sweep's, has a done `default` build hand its landing to dispatch, `--by handed` (task-shape S3) |
| `bin/pickup` | a session's branch picked up, seeded, reviewed or moved between Macs (`/pickup`, `/move`, `/later`) |
| `bin/harness` | one set of verbs over every coding-agent CLI (Claude Code, Codex, Orca, Antigravity's `agy`), its adapters in `bin/harness_adapters/`; `dispatch BRANCH --harness agy` builds a seeded branch with agy on a builder host (its features line names `agy`) |
| `bin/hail` | a pointer delivered to any session `harness` names — Claude Code's inbox socket (only to one idle 60 s or more, read back from the receiver), `codex queue` by thread, Orca's mailbox, a peer Mac over ssh, else helm's Talk, the mailbox (a row the peer's bell pulls, where ssh runs only the other way) and the file road; `--when idle` keeps a subscription that `hail subs --fulfil` sends |
| `bin/wharf`, `blueprintlib.py` | a ship's blueprint checked and applied, block by block (`wharf check`, `wharf apply`); `wharf check <doc.md>` lists a Course doc's step sizes and warns past the block rule's window (`BLOCK_LINES`); `wharf apply --yard` lays it, pinned, on its scope's yard, and a plain apply of a ship whose scope has a yard is refused |
| `bin/rc-hosts` | one Remote Control host per registry repo on this Mac; `--agents` also judges the clock's automations (what each one's launcher line starts, and whether its precheck fires it) |
| `bin/launcherlib.py` | the one rule for starting a job through claude-host (ask `rc-hosts --launcher`, executable or bare); `rc-hosts`, `clock` and helm load it |
| `bin/clock` | the calendar: every agent-run job as an Orca automation, one launcher line on haiku in a neutral workspace (`schedule`, or `--launchd` for the OS form kept), launchd left the script jobs and `dispatch --at`; `list` both Macs, `check` (G5: an agent-run job on launchd, a confidential pass without its `--account`), `board` one page, `fire` a long job detached through launchd, or as an automation's precheck (seam P: a scheduled run starts no claude in Orca); `canary beat|check` a start path's heartbeat (the hourly `canary` automation's precheck fires the beat through launchd, `check` fails a beat past its window and a run that never beat) |
| `bin/yard-node`, `node/` | the yard node: a hypervisor host (Ubuntu 24.04 autoinstall, an Incus preseed) and its agent guest's `#cloud-config`, rendered from the config dir and driven over `ssh <alias> incus …` (`render`, `apply`, `launch`, `snap`, `check`; `words`, the publish gate's word list to a named node, which every host's queue sweep runs `--all` hourly); a new named node comes up from the scripts alone: `add --node NAME --like OTHER --address IP` writes this host's side (the node folder, its ssh alias, its `regatta/fleet-ssh` line) and prints the post-install and sign-in lines, and after the owner's one sign-in `up --node NAME` sends `node/node-up.py` over ssh (the clones to origin, the overlay's `--config` and `--hooks`, the node's own walk, the first run, the fleet keys, both timers, a verdict), copies the word list and names the registry's hosts and berths still owed; a named node (`--node NAME`) is the same guest as a cloud VPS, its scope's repos in it, bought and booted through OpenTofu (`cloud plan|apply|show`; `tofu/hostinger/`, the guest's render as a post-install script; `tofu/oci/`, one arm64 Oracle A1.Flex with its A1 quota and a budget alert, the render as its user-data); every guest gets Node and sessionpipe in `/usr/local`, and a named node's clone unit gates sessionpipe's hooks with keel's `sheep` and writes no sink until the owner adds the sessions key; once the node's config names a queue home, the same unit joins it to the fleet — the queue's jobs (`dispatch --queue-jobs`) and one request for lighthouse's reef bounds, which the first sweep seeds (`reef apply --seed`), rerun by `yard-join.path` when the key or an overlay's marker lands; with `runner` set, the guest is also a CI runner's berth (`node/runner/`: its login, rootless podman's packages and ids, the nftables fence; the runner is wharf's `ci-provider --runner install`) |
| `bin/check` | a checkout's check through its PR CI by default, with private inputs checked here; `--local` or unavailable CI uses local slots |
| `bin/build-review` | the record of a build's own review loop: each dispatched build merges main in, runs `/finish`'s two reviewers, has a fresh reviewer verify each S1 and S2, fixes the confirmed ones, checks and repeats in its own session only while a round confirms a finding or its check is red (at most `wharf-runs/build-review-rounds`, 3), and records each round beside `autofinish.json` and the ended loop in the log dir's `build-review.jsonl`; a brief's `Review: finish only` line opts a doc-only run out. `covers` tells `/finish` its review may be skipped (the loop ended clean on the same code, its last review on the tip it handed over; a later tests-only check fix kept); `--phase finish` keeps an unattended landing's own loop, and `picks` says which of its verified findings' choices it takes itself; `compare` sets the builds' review beside the finishes' |
| `hooks/cold_prompt.py` | every typed `/finish` in a `claude/*` worktree handed to a fresh run: cold or Fable at once, warm after the session commits its summary |
| `hooks/force_mark.py` | the owner's typed message asking for "force", in any wording ("use the force", "force it"; never one with a refusing word within six words, a flag or rank named, a description or a git or OS force verb), marks the session for one `dispatch --priority force` (UserPromptSubmit; quoted, pasted, framed and subagent prompts never do) |
| `bin/check_scope.py` | which commands of the check line a change reaches: `check`'s scope, and what `.github/ci/share.sh scope` asks for the Linux PR check and `share.sh macos --scoped` or `whole --scoped` for the Macs' (Linux share on or off); `macos-scope` prints its first-parent input, which on a local merge is that merge's delta |
| `bin/queue_holds.py` | whether dispatch's queue holds a branch's next step: the one reader autofinish, helm's stalls and sextant's soundings share |
| `hooks/close_reason.py` | a host session rc-hosts closed says why in its own last line (SessionEnd; wire it last, and give SessionEnd hooks 30 s) |

The tools after `orca-serve-agent` find the core as wharf does (`lib/core_path.py`) and every peer
through `common.tool()`: wharf (a hard edge: `branches`, `checkpoint`, `session_status`), keel,
plumb's `tier_check`, lighthouse's `account` and the project-management tools `ask`, `helm` and
`helmlib` (absent: a run's prompt drops the ask lines, `wharf check` refuses). Which Mac is which,
who the owner is and where an overlay lives are config, below; the code names none of them.

Finish launches ask `account pick --for finish`: lighthouse's live `week-max-finish` may raise their
week ceiling without raising a build's. `autofinish-run` gives each pick attempt a fresh pipe receipt,
including the cached retry and a claimed finish (after the queue's `mine` check). Its detached
`dispatch --start` receives a separate receipt, consumed before its own auto or bound picks and
removed before the session starts. A bare purpose flag or environment word grants no allowance;
subsequent builds use the normal ceiling. No existing purpose marker was present on these roads.
The sweep and dispatch's completed-build handover also use finish receipts for their cached and
fresh landing preflights; a build's `--if-room` check keeps the normal ceiling. Those preflights keep
the primary's pace rule, so a line on the primary clears `autofinish-run`'s pick but not rules A, B, E
and M, dispatch's handover or helm's relaunch. Past a login's line a finish is refused, and the week's
`none` then stops rules C, D and L too: a deployed branch waits there. Landings are Claude sessions: a Codex or agy login's line is judged by `account`, and has no effect
until a landing runs on that provider.

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
  | `wharf-runs/node/*` | the yard node's values, one per line: `ssh`, `name`, `user`, `ssh-keys`, `tailscale` (`<role>:<address>`), `logins`, `size`, `pool`, `orca-release`, `runner` (the CI runner's login, free CI S6) (`yard-node`'s header; `orca-host setup` on a Linux box without the guest's installer installs that release too) | `yard-node` names the missing key, exit 2; `orca-host setup`, the latest release |
  | `wharf-runs/nodes/<NAME>/*` | a named node's values (`yard-node --node NAME`): the keys above, `name` defaulting to NAME, plus `orca-pair` (`<host>` per line: each HOST's Orca holds the node's guest, `<name>-agent`, as an environment; `orca-host` reads it beside `orca-pairs`, and its `--on` reaches the node by the folder's own `ssh`, never `wharf-runs/ssh`), `provider` (`hostinger` or `oci`), `scope` (the registry scope it serves; none: a shared node), `carry` (`<repo key> [<sparse path>]` per line, cloned beside the scope's), `marketplace` (`owner/repo`), `plan`, `price`, `data-center`, `template` (Hostinger's; `price` too for an Oracle size off the defaults), `region`, `ocpus`, `memory`, `boot`, `ubuntu`, `a1-cores`, `a1-memory`, `budget`, `alert-email`, `ssh-from` (Oracle's: `yard-node`'s header), `secrets` (the env file under the secrets folder holding `HOSTINGER_API_TOKEN`, or `OCI_TENANCY_OCID`, `OCI_USER_OCID`, `OCI_FINGERPRINT` and `OCI_PRIVATE_KEY_PATH`; default: the scope's first repo's), and `address`, `vps-id` that `cloud show` writes (`add` writes `address` and `ssh`); for `up`: `overlay` (the overlay's clone on the node; default this host's overlay checkout, where the node carries it), `features` (the names its `wharf-runs/features` line takes; none by default: a capable node meets `finish-queue` by its own readiness, and `add` never copies it) and `queue-repos` (its `wharf-runs/queue-repos`, written whole) | `yard-node` names the missing key, exit 2; no token: the file and the key, exit 2; no folder or no `orca-pair`: the node pairs with no Mac; a folder or key that does not read: `orca-host` names it, as a missing `orca-pairs` with an overlay |
  | `wharf-runs/tofu/<NAME>/` | written, not read by hand: the node's OpenTofu state, 0600; `cloud apply` refuses unless this path resolves into a vault's `_secrets` (the state holds the VPS's root password, or the tenancy's OCIDs) | `cloud plan` and `show` make it; `apply` refuses |
  | `wharf-runs/serve-label` | the LaunchAgent label `orca-serve-agent` installs, first non-blank line; read on the Mac the agent is installed on (not on Linux: the unit is `orca-serve.service`) | `org.regatta.orca-serve` |
  | `wharf-runs/serve-label-previous` | an older label `orca-serve-agent` boots out and removes first, so one agent serves | none |
  | `wharf-runs/dispatch-host` | the Mac a run goes to when `dispatch` names none (`--on`); it has no larger run cap since 2026-10-31 (`wharf-runs/run-cap` below) | the first peer of `wharf-runs/ssh`, with one line on stderr; none, this Mac |
  | `wharf-runs/label-prefix` | the reverse-DNS prefix of the launchd jobs `dispatch`, `dispatch-rc`, `rc-hosts` and the sweep write and find (`<prefix>.dispatch.<repo>.<topic>…`, `<prefix>.autofinish`) | `org.regatta.claude` |
  | `wharf-runs/label-prefix-previous` | the prefix the jobs had before a label move, one word: its jobs are still ours while they drain. `dispatch` finds and clears a branch's job under it (`--cancel`, a reschedule), and the queue drops its `queue-sweep` and `queue-poll` once the new sweep loads; `dispatch-rc refresh-tidy` relabels its tidier; `rc-hosts` relabels its hosts and reaper (a plain run, or `--reap`'s converge; a host's sessions end with it) and reports the count, and `--agents` reads its jobs as ours; the core's check reads its `queue-sweep` while the new one is absent. New jobs take `label-prefix` only. Equal to it: none | none: no job under another prefix is ours |
  | `wharf-runs/launcher-id` | claude-host's codesign identifier, which `rc-hosts --grant` signs it with and its build stamp holds; set it to the old `<prefix>-host` before a label move, so the move leaves the build and its grants as they are until the next signing | `<label-prefix>-host` |
  | `wharf-runs/rc-hosts` | the Macs that run Remote Control hosts (`rc-hosts`): host names, separated by spaces, commas or lines, compared lower-case. A Mac the key leaves out wants no host, and the plain run and the hourly `--reap` retire each one once its last session is gone; `--check` says the key keeps hosts off there. A key written empty names no Mac | absent: every Mac whose registry entry names it runs its hosts |
  | `wharf-runs/public-repos` | repo folder names a Codex or agy run through `harness` stays out of, beside the overlay's own checkout and anything under `projects/oss/` | those two only, with one line on stderr |
  | `wharf-runs/agy-mode` | the permission mode an agy run starts in: `accept-edits` (edits only, every shell command soft-denied) or `auto` (agy's edits-and-safe-commands mode) | `accept-edits` |
  | `wharf-runs/brake-label` | the launchd job the studio brake stops (SIGSTOP), first non-blank line; a `wharf` start waits while that job's process is stopped, as it does while the brake's sentinel file (`.studio-brake` in the home folder) exists | only the file brakes |
  | `wharf-runs/headroom` | `<host>:avail=<min % free>,swap=<max GB>,rate=<max MB/s swapping>`, `*:` for any other host — the memory `headroom` lets `dispatch` start a run in; the same names on macOS and Linux | 10 % free, 50 MB/s, no swap rule |
  | `wharf-runs/run-cap` | optional; changed live with `regatta limit set run-cap <host>:<n> --why '…'` (as `check-slots`, `headroom`, `load-max` and `load-margin`: this module's `limits` file; the core's README, Limits). `<host>:<n>`, a whole number from 1 to 999: the runs that host holds at once, its first line winning, a value split one word per line reading as one and a note after `#` or `(` as nothing; `DISPATCH_MAX_RUNS` over it. `dispatch --cap` answers it for wharf and helm, and `--slots` for berth, so a peer reads what the host starts by. No `*` line: the default is `dispatch`'s own. A line that is no cap reads as none, said on stderr | 3 |
  | `wharf-runs/load-max` | `<load per core> [log]` — a host whose 5-minute load per core is at or over it is passed over for the next one its scope allows; `log` records the pick without acting on it | 1.5; log only while `load-margin` is unset or `log` too |
  | `wharf-runs/finisher-rotation` | `until YYYY-MM-DD`: the finisher rotation's switch and its last day. `autofinish-run` draws each finisher by coin, Opus 5.5 or Sonnet 5.5 at `medium`, and records the run in the log dir's `finisher-rotation.jsonl`; with the rotation off every finish run still writes its row, `arm` null (task-shape S1). A repo any of whose scopes says `"rotation": false` (or a `rotation` that is no bool), or one in no scope, keeps today's finisher; a confidential scope rotates unless it opts out so, its row carrying `scope` and `confidential: true` (the core's `scope_rotates`, since scope-rotation 2026-11-04; `autofinish-run`'s header; `autofinish-run rotation` reads the rows back) | today's finisher, dispatch's default model |
  | `wharf-runs/builder-rotation` | `until YYYY-MM-DD`: the builder rotation's switch and its last day (S6 of the Trim design). A run whose brief is specced — its `Tier:` line names `worker` or Sonnet — or plain Opus — Opus alone, no tier word, no effort but `high` (since 2026-11-03) — and that no `--model` or `--effort` was given for draws its builder once where `dispatch` enqueues or schedules it, by `wharf-runs/builder-odds` (below; Opus 5.5, Sonnet 5.5 and Gemini 4 Argon, each `high`; 3 in 5 Sonnet and no Argon until S3 of the Argon design, 1 in 5 before 2026-11-03); an Argon draw runs only on a builder host (its `wharf-runs/features` line names `agy`, its row on the hosts ref fresh) and adds `--needs agy`, else it falls back to Opus, the row saying `fallback`; while dispatch has no road for agy (its S4) Argon weighs 0 at the draw (`1:2:2` draws as `1:2`); the row's `brief_class` says which class (trim does not split by it yet: TODO.md [trim-brief-class]); every road carries the draw (`DISPATCH_ARM`), and the run's record and one row in the log dir's `builder-rotation.jsonl` keep it, which trim reads as `arm_source: coin`. A repo any of whose scopes says `"rotation": false` (or a `rotation` that is no bool), one in no scope or a registry that does not read draws nothing; a confidential scope draws unless it opts out so (the owner, 2026-11-04: one scope does, the others draw), and its row carries `scope` and `confidential: true`, which trim counts in its arm tallies only (the core's `scope_rotates`, since scope-rotation 2026-11-04); such a scope draws the claude arms only, never Argon (Google), and a vendor word fires there as its Opus fallback. The fire path asks the key again on the host the run fires on, so every host that claims runs needs it (the overlay's config line on each, the Linux node included): a host without it drops the arm, said in the run's log (`bin/buildercoin.py`'s header) | today's builder: opus/high, or a principal tier's |
  | `wharf-runs/builder-odds` | optional; a fleet limit, changed live with `regatta limit set builder-odds 'opus-high=1,sonnet-high=2,argon-high=0' --all --why '…'` (this module's `limits` file). The builder coin's whole weight per arm, by the arm's name, in any order, an arm left out weighing 0; or, as a live value only, positional in the coin's order `opus:sonnet:argon:gpt-big:gpt-mid` (three or five weights, e.g. `0:0:0:1:1`), read ahead of the named base line (a named base, never `1:2:2:1:1`: the config's grammar reads `1:` there as a host's word). A weight of 0 is never drawn; with both Claude weights 0 a worker brief draws `gpt-mid` and an sr-worker brief `gpt-big`, a principal tier stays Claude. Read where a run is drawn and again where it fires: a weight of 0 for the drawn arm there runs today's builder, unrecorded, and a value that does not read draws nothing. The row's `odds` writes the weights as `o:s:a`, which `buildercoin.py`'s `odds_of` reads beside #459's `n/d` (S3 of docs/argon-builder-arm-2026-11-03.md) | `opus-high=1,sonnet-high=2,argon-high=2,gpt-big=1,gpt-mid=1` (1:2:2:1:1; the owner's D2, S8) |
  | `wharf-runs/load-margin` | `<load per core> [log]` — how much lighter a later host must be than the ones passed over | 0.5; log only while `load-max` is unset or `log` too |
  | `wharf-runs/build-review-rounds` | optional. The build loop's round cap, a whole number from 1 to 20 (`build-review cap`), read at each round, so a change holds from the next one; a value split one word per line reads as one, a note after `#` or `(` as nothing. A value that does not read is the default, said on stderr | 3 |
  | `wharf-runs/queue-repo` | the home of `dispatch`'s fleet queue (`dispatch-queue`'s header): `owner/name` on GitHub, or a path or URL; `off` turns the queue off. Every host that claims needs write on it; set the URL that host's git reaches | none: no queue, and `dispatch` runs as before it (`helm/logbook-repo` stands in once S2 lands) |
  | `wharf-runs/queue-repos` | the repos this host claims from the fleet queue, one repo key per line; `<key> pinned` takes that repo's entries only when pinned here (`--pin`, a named login; a preference is no pin: dispatch-queue's `fleet_fence`) | every repo cloned here |
  | `wharf-runs/queue-mode` | optional (dispatch-queue S10(g)). `writes`, or `<host>:writes` for one host: that host's queue home is for its own writes alone — `dispatch --requeue`'s ops, replayed from the outbox by its sweep at wake. It enqueues none of its own runs and claims nothing; `claim`, the default, as before. No host claims in a DarkWake (`pmset -g systemstate` without Graphics) | `claim` |
  | `wharf-runs/hosts-sample` | optional (the Engine room's S2). `off`: the sweep and the claims never start lighthouse's `hosts sample --put`, so this host puts no row on `refs/regatta/hosts` (`dispatch-queue hosts`); the suites' fixtures write it | on wherever a queue home and lighthouse are |
  | `wharf-runs/kick-roads` | optional (dispatch-queue S8, `bin/kicklib.py`): the kick's switch and its roads, `<host>:<road>[,<road>…]` (`sheep`, `orca`, `ssh`, tried in the order the line names them) or `<host>:none`; a value split one word per line, and a note after `#` or `(`, read as one line, a host's first line winning. The file's presence turns the kick on: a host that enqueued what it does not take kicks every eligible peer over the first road that takes it. A host with no line gets what exists: `orca` where `orca-pairs` names the pair this way, `ssh` where `wharf-runs/ssh` or `wharf-runs/kick-ssh` has its alias; `sheep` only where a line names it (a kicker cannot see a peer's listener; `dispatch --roads` prints what exists here, this host's listener included) | absent: no kick, and the pending poll is every host's way to hear |
  | `wharf-runs/kick-ssh` | optional (`bin/kicklib.py`): `<host>:<ssh alias>`, read by the kick and message roads, after `wharf-runs/ssh`. For a host the ssh road may reach that no other reader of `wharf-runs/ssh` may: a scope's node, which berth would otherwise probe and place one-shots on, and pickup, stalls and `account doctor` would read. A line here is a road for `reached()`, as an alias in `wharf-runs/ssh` is; it reaches a host the entry's scope `berths` or a `wharf-runs/features` line name, since a repo with no berths takes its peers from `wharf-runs/ssh` alone | none: the ssh road reaches only what `wharf-runs/ssh` names |
  | `wharf-runs/kick-space` | optional (`bin/kicklib.py`): the space id of the private page that declares `kick/*` (`<meta name="ss-streams">`), published once under the kickers' full key's account. The sheep road presses over that space's stream socket, which presses only the streams its page declares; the kicker's python3 needs the `websockets` package (14.0+), and a host lacking either says so in `kicks.jsonl` and `dispatch --roads` and kicks over the next road | none: the sheep road is unavailable |
  | `wharf-runs/kick-stream` | optional (S8): `<host>:<stream>`, the spacesheep stream a host's kick listener hears on, for a listener shared through `--on-dir` (`dispatch-rc kick-listen install --shared DIR`) | `kick/<host>` |
  | `wharf-runs/power` | optional (S10(e), read by helm's stalls). `<host>:sleeps` for a host that may sleep, beside the core's laptop, which may unless its line says otherwise: unreachable, with no queue word of its own younger than two sweeps, it reads `asleep`; any other host stays `unreachable` | only the laptop may sleep |
  | `wharf-runs/host` | optional: this user's fleet host row; builder users have a row separate from the physical Mac | the machine's host name |
  | `wharf-runs/only` | optional: features every locally claimed build must need; finishes are refused on this user | no extra claim filter |
  | `wharf-runs/launchd-domain` | optional: `user` loads jobs into `user/<uid>` with `LimitLoadToSessionType` Background | `gui/<uid>` |
  | `wharf-runs/slot-share` | optional: absolute shared folder with one owned directory per user. Each publish records live runs, reservations, the raw registry sha256 and this user's cap. Builders refuse claims when the owner's publication is missing, stale or differs from make's registry receipt; their effective cap is the lower of their own row and the owner's published cap. Owners select a peer's cap row through their first `regatta/fleet-ssh` binding of `<host>:<user>@localhost` (make prints it, including custom `--host` names), else `<owner-host>-<user>`; a missing or invalid cap inherits their own cap. A peer's published host or cap never narrows its count | no sharing |
  | `wharf-runs/builder-source` | optional: `builder-host make` receipt naming the owner and the raw and rewritten registry digests; refresh with make after registry changes. `check` reports registry and cap differences | no receipt; a builder configured with `only` and a user domain refuses claims until make |
  | `wharf-runs/features` | optional. One `<host>:<name>,<name>` line per host: the features that host has, lower-case opaque names a run asks for with `dispatch --needs a,b` or a `needs:` line in a seed brief. A host claims a queued run only if every need is met by its feature line or a built-in rule; a need no host that may take the repo meets is refused at enqueue (exit 3), never queued. Example: `host-a:feat-a,feat-b`. `finish-queue` is built in on Darwin and on a non-Mac with a loaded autofinish schedule, a valid publish word list and `/finish` in every enabled Claude login dir (the same probe as `install.sh --check`, once per queue pass). An explicit `finish-queue` grants it; `<host>:-finish-queue` overrides both grants. An unreadable features file holds finishes, and host samples omit negations. A missing prerequisite is named in the claim refusal and the queue row | none: only built-in needs |

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

**Message peers** use the fleet's `refs/regatta/hosts`, read through `dispatch-queue hosts get --cached`
when `wharf-runs/queue-repo` is set. The sampler's `hosts put` refreshes that local ref (each claim and sweep starts it where
lighthouse is present and `wharf-runs/hosts-sample` is not `off`); hail and Stop hooks never fetch it. Fresh samples (at most 24 hours old, or up to 5 minutes ahead of the reader's clock) with bare fleet names become ssh destinations.
Configured aliases win in order: `wharf-runs/ssh`, `wharf-runs/kick-ssh`, then a named node's
`wharf-runs/nodes/<name>/ssh` (for its `<name>-agent` peer). An explicit `hail --host` tries aliases
before reading the fleet cache. No new message list needs maintaining.

Automatic discovery, mailbox pulls and helm's relays skip every name they add (kick aliases,
node folders, fleet rows) that is a confidential scope's yard or its own node (the core's
`nodes_here`, `<scope>-agent`, or a host whose fleet row is torn or whose `scope` marker, lighthouse's
sampler's, is no open scope here, however old the row); a kick alias alone is added only while a fresh,
unmarked row vouches for it; a node folder whose `scope` names no open scope here is blocked too, and a
builder user's row (`builder: true`) is reached only by a configured alias; a `wharf-runs/ssh` peer is
reached as before, a Mac yard included. A registry, a
yard or a node folder that does not read drops every added name. An explicit `hail --host <yard>` may still reach
that yard, under the sender and receiver fences and pointer-only rules. The caller needs ssh access
by its alias or fleet name (or the reverse mailbox road). Placement keeps its own readers of
`wharf-runs/ssh`; discovering a node grants no placement permission.

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
`/finish` needs on the host: the publish gate's word list and the `finish` skill in each enabled Claude login dir.

## Check

`check <worktree> [--ci-wait MIN] --out <dir>` defaults to PR CI (`--ci` is also accepted) when
a PR workflow and required checks exist, gh answers and every matching scope permits it. Commit
before calling it. A PR whose required checks are green on this exact tree counts as `PASSED <when> CI`
on both roads, before any fetch, push or label edit. Otherwise it fetches origin/main and merges it if needed, aborting a conflict and reporting
its files, then pushes only the current `claude/*` branch without force. It finds or opens a non-draft
PR labelled `hold`, keeping automerge off, and waits for this exact head's required contexts from
origin/main's `.github/main-protection.json` (never the branch's own), else the branch protection API. The Linux matrix and scoped macOS share run in parallel, spending
CI minutes; each call may open or ready a PR. Dispatch asks both builders to use it in their
review → fix → check loops; `build-review round --check green|red` records the outcome as before.
`/finish` curates and rebases first, pushes, then runs `check --ci --ci-no-merge` on the tip to land,
with the review gate in parallel; a moved main asks it to rebase again. Its `pr ready` releases
the hold CI added; a hold already present before CI, or an explicit landing `--hold`, stays in place.

A PR already readied by `/finish` cannot receive a merge of main unless `--ci-merge-main` is given;
that flag is the owner's yes, refused unattended. With main moved, a ready landing uses the local
line unless `--ci-no-merge` requires a rebase. Use `/finish` to rebase a landing PR.
New PRs open as drafts, labelled before they are readied; a failed label call leaves a draft.
Once readied, later checkpoint pushes run the PR's CI too. A signal ends the helper with `INTERRUPTED`,
and build-review counts a clean merge of main as no new code.
Commands with inputs CI lacks are in check_ci.py's explicit
`LOCAL_COMMANDS` list: today the contract's private publish gate, `helloworld check . --ref HEAD`.
Unattended checks include listed commands from both main and the branch, so a new gate runs
before it lands and a branch cannot drop main's gate; each runs once.
They run here beside the CI wait, without a slot, including when CI was already green; their result
counts in the summary and a local failure fails the check. CI green ends `DONE n/n`; red or a moved PR head ends `FAILED`
and exits 1, with each failed job and its failing log lines in the summary, full failed-step logs
beside it where GitHub Actions provides them (external jobs retain their log link). Missing gh,
network, a refused push, no PR, a branch already landed or no verdict within `--ci-wait` (whole minutes, default 120) prints
one fallback line and runs the local check. Confidential or guarded repos (the core's `fenced_scopes`), an unreadable scope registry,
uncommitted work, a branch outside `claude/*` and local-only `--only`, `--full` or `--fresh` also
use the local road. `--local` forces it; `--only`, `--full` and `--fresh` also bypass CI reuse.
A required failure returns red immediately, even while another job is pending
or missing, and never falls back locally. When gh reports no checks yet, check keeps polling
until a verdict or the wait limit. CI neither waits for a local slot nor fills its pass memory.
CI's coverage comes from `.github/ci/share.sh line`: contract commands neither it nor the explicit
local list runs remain `UNRUN <command>`, exit 3. Without that CI line to compare, check runs locally.

With the landing switch on, a completed default build hands its landing to dispatch (`--by handed`).
The hand-over reads its changed documents and review result, and requires a clean tree whose exact tip
is on origin. A legacy landing-only question or a wait solely for a step stamp does not ask the owner:
the finish removes the obsolete question and lists owed doc/step stamps in the PR. A stamp is owed only
when its Course doc is not on the branch, or the build's ⏳ line (`Stamp owed: <doc> S<n>`) names that
doc and step and keel reads the step as `wip`; a step not started, blocked, without a status keel knows,
or missing from its doc holds, whatever the closing line says. A landing question counts only where the
branch added it, and one the owner answered hold holds. Real unanswered
decisions, warnings and unfinished waits hold. Every refusal records a `to land:` action in the run's
`launch` field, which helm shows in one S6 card independently of the closing line.

`bash modules/wharf-runs/tests/check.sh` — scratch paths only; no Orca, no network, no real launchd
(macOS). The suites run in three lanes at once, test_dispatch alone in one, each lane printed whole, in lane order,
when it ends; `WHARF_RUNS_CHECK_LANES=1` runs them one after another. A suite the checkout lacks is
skipped with a line.

`bash modules/wharf-runs/tests/check.sh --list-shards` prints a partition of every script;
`--shard NAME` runs one group in one lane; off macOS it runs `LINUX_OK`'s suites only, and
`WHARF_RUNS_LINUX_PROOF=1` runs the group whole, to prove a candidate. The check line names the suite
once (a Mac's whole line runs it in lanes); `share.sh` splits it into one id per shard. The PR's
`check-linux` runs the eight that passed on Linux (#500, 2026-11-05; `pickup` waited a day for the self-hosted runners' `lsof`); the macOS share runs
`wharf-runs-queue` and `wharf-runs-macos`.
`test_harness` needs macOS's research seatbelt, and `test_rc_hosts` compiles and signs the TCC
launcher; both stay in `macos`.
`share.sh` names a command ending in `tests/check.sh --shard NAME` as `<module>-NAME`, and a plain
`bash <module>/tests/check.sh` whose script answers `--list-shards` as one such id per shard. Both Actions matrices
read `share.sh linux-ids`; CircleCI's static matrix must match `.github/ci/linux-ids`.

## Codex builds

`dispatch BRANCH --harness codex` and either GPT coin arm use `run-vendor`.
The launcher owns fetch, the initial merge, explicit branch pushes, checks,
fresh reviews and the verifier, then resumes the builder thread for fixes.
Only a clean review/check end schedules a changed next brief. Landing stays
with `/finish`. `build-review review WORKTREE --cli codex` runs one review
round; `--cli antigravity` is the explicit S4 seam. A row declaring a second
vendor uses that vendor for reviews; an unavailable declared road holds the
loop. Each turn repeats the scope fence and scans its message before sending.

The default `wharf-runs/builder-odds` is `1:2:2:1:1`: Opus, Sonnet, Argon,
GPT big (`gpt-6.1-sol`, xhigh), GPT mid (the same model, high). Named weights
such as `gpt-big=1,gpt-mid=1` also read. Omitted and zero weights never draw.
With both Claude weights zero, worker/Sonnet briefs take GPT mid and
sr-worker/Opus briefs take GPT big; principal tiers stay Claude. At the next draw, any positive
Claude weight restores the earlier specced/plain brief rule. If every arm
eligible for a class weighs zero, the current Claude builder remains the
fallback. Codex entries need the `codex` feature on a fresh builder host.

`sudo builder-user codex --gh-as LOGIN` creates the vendor user and the same
home ACL wall as the other builder user. It uses the readable Homebrew CLI
and shares the sudo user's ChatGPT plan login (`--cli-from USER` selects a
trusted source), as gh access is shared. Login contents are never printed.
The runtime needs `wharf-runs/only` naming `codex`, the scope registry and a
signed-in CLI with the requested model/effort in its local model catalog.
The builder Codex home must hold only the generated Regatta PreToolUse
handler (`vendor-hooks apply`); the launcher checks it before trusting it
headlessly. Reviews grant the worktree read access, keeping the run fence.
Host installation and real-user probes remain the owner's steps; the
builder-host installer includes S9's hardening.
`sudo builder-host make codex` (`check codex`, `probe codex`) wires `<host>-codex` (`codex` feature and `only`), its `CODEX_HOME` hooks and `AGENTS.md`, its own sweep LaunchDaemon, and the Mac's shared slot folder, checking `codex login status` as the builder with no model call.

`check WORKTREE --builder` keeps module suites and TODO lint, leaving
`claude plugin validate` and the private publish gate to the landing. Omitted
commands are reported as skipped and never remembered as passed. A launcher
records its own PID across review gaps, a separate turn PID, the thread,
provider tokens and the final outcome. Pre-flight failure returns a claimed
entry to the fleet as its Claude fallback, keeping its hard pin. If the pinned
host cannot run Claude, the fallback stays queued there. A failure after a vendor starts
belongs to that vendor. Antigravity's build turns are S4; record readers and
the finish hand-over are S5.
