# wharf-runs — runs that start with nobody at the keyboard

Everything that lets an agent execute on more than one Mac: the fleet, the harness, the runs
themselves. Requires the core (`regatta`); the rest of the module moves in piece by piece.

| Piece | What it does |
| --- | --- |
| `bin/orca-host` | Orca on this Mac kept to the registry: the app and its CLI, one project group per scope (anchor first, coloured, worktrees from local `main` in `.claude/worktrees/`), and the pairing to the Macs whose Orca it drives (`check`, `setup`, `scopes`, `pair PEER`, `--on PEER <verb>`); on a Linux peer the same verbs over `orca-ide`, its release `.deb` and the server's systemd user unit |
| `bin/orca-serve-agent` | a Mac's Orca run as a headless server under a LaunchAgent in the login session, so it survives a reboot and reaches the keychain (`HOST\|here [--remove] [--dry-run]`); the agent's label is a config key. On Linux the systemd user unit `orca-serve.service` with linger, the one the agent guest's cloud-init writes |
| `bin/dispatch`, `run-seed` | a seeded `claude/*` branch started with nobody at the keyboard: now, at a time, on another Mac (`--on`), or as the next step of a chain (`--next`); the run's records, its watcher and its window (`dispatch-rc`) |
| `bin/dispatch-queue` | `dispatch`'s fleet queue: one git ref every host claims from by compare-and-swap, a node-local queue per confidential scope, the outbox and the sweep; `dispatch --queue`, `--sweep`, `--priority` are its faces |
| `bin/systemd-launchctl` | launchctl's verbs (`bootstrap`, `bootout`, `print`, `kickstart`) over systemd's user manager: the launcher dispatch, dispatch-queue and `regatta check` use off macOS, so a Linux node runs the same plists — a RunAtLoad job as a transient unit, an interval or calendar job as a unit pair with an enabled timer |
| `bin/autofinish`, `autofinish-run` | the lander: a sweep that judges each idle `claude/*` worktree by the start rules in its header and, once armed on a Mac, starts a fresh unattended `/finish` on it; `install.sh --schedule` adds the sweep |
| `bin/pickup` | a session's branch picked up, seeded, reviewed or moved between Macs (`/pickup`, `/move`, `/later`) |
| `bin/harness` | one set of verbs over every coding-agent CLI (Claude Code, Codex, Orca), its adapters in `bin/harness_adapters/` |
| `bin/hail` | a pointer delivered to any session `harness` names — Claude Code's inbox socket (only to one idle 60 s or more, read back from the receiver), `codex queue` by thread, Orca's mailbox, a peer Mac over ssh, else helm's Talk and file roads; `--when idle` keeps a subscription that `hail subs --fulfil` sends |
| `bin/wharf`, `blueprintlib.py` | a ship's blueprint checked and applied, block by block (`wharf check`, `wharf apply`); `wharf apply --yard` lays it, pinned, on its scope's yard, and a plain apply of a ship whose scope has a yard is refused |
| `bin/rc-hosts` | one Remote Control host per registry repo on this Mac; `--agents` also judges the clock's automations (what each one's launcher line starts, and whether its precheck fires it) |
| `bin/launcherlib.py` | the one rule for starting a job through claude-host (ask `rc-hosts --launcher`, executable or bare); `rc-hosts`, `clock` and helm load it |
| `bin/clock` | the calendar: every agent-run job as an Orca automation, one launcher line on haiku in a neutral workspace (`schedule`, or `--launchd` for the OS form kept), launchd left the script jobs and `dispatch --at`; `list` both Macs, `check` (G5: an agent-run job on launchd, a confidential pass without its `--account`), `board` one page, `fire` a long job detached through launchd, or as an automation's precheck (seam P: a scheduled run starts no claude in Orca); `canary beat|check` a start path's heartbeat (the hourly `canary` automation's precheck fires the beat through launchd, `check` fails a beat past its window and a run that never beat) |
| `bin/yard-node`, `node/` | the yard node: a hypervisor host (Ubuntu 24.04 autoinstall, an Incus preseed) and its agent guest's `#cloud-config`, rendered from the config dir and driven over `ssh <alias> incus …` (`render`, `apply`, `launch`, `snap`, `check`); a named node (`--node NAME`) is the same guest as a cloud VPS, its scope's repos in it, bought and booted through OpenTofu (`cloud plan|apply|show`; `tofu/hostinger/`, the guest's render as a post-install script) |
| `bin/check` | a checkout's `check:` line run one script at a time under a few slots per Mac login |
| `hooks/cold_prompt.py` | every typed `/finish` in a `claude/*` worktree handed to a fresh run: cold or Fable at once, warm after the session commits its summary |
| `hooks/force_mark.py` | "use the force" in the owner's typed message marks the session for one `dispatch --priority force` (UserPromptSubmit; quoted, pasted, framed and subagent prompts never do) |
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
  | `wharf-runs/ssh` | `<peer>:<ssh alias>` — how `orca-host --on PEER` reaches it, `autofinish-run` its peer, and `wharf apply --yard` a yard | `--on` knows no peer; `--yard` falls back to `bin/harness`'s peers |
  | `wharf-runs/finish-on` | `<host>:<peer>` — where `autofinish-run` started on HOST sends the run (its header, Where); optional | HOST's line in `orca-pairs`, else the run stays on HOST |
  | `wharf-runs/node/*` | the yard node's values, one per line: `ssh`, `name`, `user`, `ssh-keys`, `tailscale` (`<role>:<address>`), `logins`, `size`, `pool`, `orca-release` (`yard-node`'s header; `orca-host setup` on a Linux box without the guest's installer installs that release too) | `yard-node` names the missing key, exit 2; `orca-host setup`, the latest release |
  | `wharf-runs/nodes/<NAME>/*` | a named node's values (`yard-node --node NAME`): the keys above, `name` defaulting to NAME, plus `orca-pair` (`<host>` per line: each HOST's Orca holds the node's guest, `<name>-agent`, as an environment; `orca-host` reads it beside `orca-pairs`, and its `--on` reaches the node by the folder's own `ssh`, never `wharf-runs/ssh`), `provider` (`hostinger`), `scope` (the registry scope it serves; none: a shared node), `carry` (`<repo key> [<sparse path>]` per line, cloned beside the scope's), `marketplace` (`owner/repo`), `plan`, `price`, `data-center`, `template`, `secrets` (the env file under the secrets folder holding `HOSTINGER_API_TOKEN`; default: the scope's first repo's), and `address`, `vps-id` that `cloud show` writes | `yard-node` names the missing key, exit 2; no token: the file and the key, exit 2; no folder or no `orca-pair`: the node pairs with no Mac; a folder or key that does not read: `orca-host` names it, as a missing `orca-pairs` with an overlay |
  | `wharf-runs/tofu/<NAME>/` | written, not read by hand: the node's OpenTofu state, 0600; `cloud apply` refuses unless this path resolves into a vault's `_secrets` (the state holds the VPS's root password) | `cloud plan` and `show` make it; `apply` refuses |
  | `wharf-runs/serve-label` | the LaunchAgent label `orca-serve-agent` installs, first non-blank line; read on the Mac the agent is installed on (not on Linux: the unit is `orca-serve.service`) | `org.regatta.orca-serve` |
  | `wharf-runs/serve-label-previous` | an older label `orca-serve-agent` boots out and removes first, so one agent serves | none |
  | `wharf-runs/dispatch-host` | the Mac a run goes to when `dispatch` names none (`--on`), and the one whose run cap is 6 (3 elsewhere; `DISPATCH_MAX_RUNS` over either) | the first peer of `wharf-runs/ssh`, with one line on stderr; none, this Mac |
  | `wharf-runs/label-prefix` | the reverse-DNS prefix of the launchd jobs `dispatch`, `dispatch-rc`, `rc-hosts` and the sweep write and find (`<prefix>.dispatch.<repo>.<topic>…`, `<prefix>.autofinish`) | `org.regatta.claude` |
  | `wharf-runs/label-prefix-previous` | the prefix the jobs had before a label move, one word: its jobs are still ours while they drain. `dispatch` finds and clears a branch's job under it (`--cancel`, a reschedule), and the queue drops its `queue-sweep` and `queue-poll` once the new sweep loads; `dispatch-rc refresh-tidy` relabels its tidier; `rc-hosts` relabels its hosts and reaper (a plain run, or `--reap`'s converge; a host's sessions end with it) and reports the count, and `--agents` reads its jobs as ours; the core's check reads its `queue-sweep` while the new one is absent. New jobs take `label-prefix` only. Equal to it: none | none: no job under another prefix is ours |
  | `wharf-runs/launcher-id` | claude-host's codesign identifier, which `rc-hosts --grant` signs it with and its build stamp holds; set it to the old `<prefix>-host` before a label move, so the move leaves the build and its grants as they are until the next signing | `<label-prefix>-host` |
  | `wharf-runs/public-repos` | repo folder names a Codex run through `harness` stays out of, beside the overlay's own checkout and anything under `projects/oss/` | those two only, with one line on stderr |
  | `wharf-runs/brake-label` | the launchd job the studio brake stops (SIGSTOP), first non-blank line; a `wharf` start waits while that job's process is stopped, as it does while the brake's sentinel file (`.studio-brake` in the home folder) exists | only the file brakes |
  | `wharf-runs/headroom` | `<host>:avail=<min % free>,swap=<max GB>,rate=<max MB/s swapping>`, `*:` for any other host — the memory `headroom` lets `dispatch` start a run in; the same names on macOS and Linux | 10 % free, 50 MB/s, no swap rule |
  | `wharf-runs/load-max` | `<load per core> [log]` — a host whose 5-minute load per core is at or over it is passed over for the next one its scope allows; `log` records the pick without acting on it | 1.5; log only while `load-margin` is unset or `log` too |
  | `wharf-runs/finisher-rotation` | `until YYYY-MM-DD`: the finisher rotation's switch and its last day. `autofinish-run` draws each finisher by coin, Opus 5.5 or Sonnet 5.5 at `medium`, and records the run in the log dir's `finisher-rotation.jsonl`. A confidential scope's repo, or one in no scope, keeps today's finisher (`autofinish-run`'s header; `autofinish-run rotation` reads the rows back) | today's finisher, dispatch's default model |
  | `wharf-runs/load-margin` | `<load per core> [log]` — how much lighter a later host must be than the ones passed over | 0.5; log only while `load-max` is unset or `log` too |
  | `wharf-runs/queue-repo` | the home of `dispatch`'s fleet queue (`dispatch-queue`'s header): `owner/name` on GitHub, or a path or URL; `off` turns the queue off. Every host that claims needs write on it; set the URL that host's git reaches | none: no queue, and `dispatch` runs as before it (`helm/logbook-repo` stands in once S2 lands) |
  | `wharf-runs/queue-repos` | the repos this host claims from the fleet queue, one repo key per line; `<key> pinned` takes that repo's entries only when pinned here (dispatch-queue's `fleet_fence`) | every repo cloned here |
  | `wharf-runs/queue-mode` | optional (dispatch-queue S10(g)). `writes`, or `<host>:writes` for one host: that host's queue home is for its own writes alone — `dispatch --requeue`'s ops, replayed from the outbox by its sweep at wake. It enqueues none of its own runs and claims nothing; `claim`, the default, as before. No host claims in a DarkWake (`pmset -g systemstate` without Graphics) | `claim` |
  | `wharf-runs/power` | optional (S10(e), read by helm's stalls). `<host>:sleeps` for a host that may sleep, beside the core's laptop, which may unless its line says otherwise: unreachable, with no queue word of its own younger than two sweeps, it reads `asleep`; any other host stays `unreachable` | only the laptop may sleep |
  | `wharf-runs/features` | optional. One `<host>:<name>,<name>` line per host: the features that host has, lower-case opaque names a run asks for with `dispatch --needs a,b` or a `needs:` line in a seed brief. A host claims a queued run only if its line names every need; a host with no line meets none, and a need no host that may take the repo meets is refused at enqueue (exit 3), never queued. Example: `host-a:feat-a,feat-b` | none: nothing meets a need |

  The core's own keys are read too: `regatta/laptop` (the Mac with a screen: a run's window opens
  there only), `regatta/owner` (the name the closing lines and refusals address, and the `by` of a
  marker the owner writes), `regatta/overlay` (the overlay checkout: a run's default repo, and the
  `bin/dispatch` its jobs name). With an overlay installed (that marker) `regatta check` names a missing key
  (bar the two `serve-label` keys, `brake-label`, `headroom` and `finisher-rotation`, optional); the tools themselves never refuse over one they did
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

## Schedule

`sh modules/wharf-runs/install.sh --schedule` writes and loads one launchd agent, `bin/autofinish
--sweep` every 10 minutes (it starts nothing until `autofinish arm` on that Mac); `--remove` takes it
away. Where an overlay is installed (its `regatta/overlay` marker in the config dir) it refuses: the overlay
schedules the sweep itself.

## Check

`bash modules/wharf-runs/tests/check.sh` — scratch paths only; no Orca, no network, no real launchd
(macOS). The suites run in three lanes at once, test_dispatch alone in one, each lane printed whole, in lane order,
when it ends; `WHARF_RUNS_CHECK_LANES=1` runs them one after another. A suite the checkout lacks is
skipped with a line.
