# wharf-runs — runs that start with nobody at the keyboard

Everything that lets an agent execute on more than one Mac: the fleet, the harness, the runs
themselves. Requires the core (`regatta`); the rest of the module moves in piece by piece.

| Piece | What it does |
| --- | --- |
| `bin/orca-host` | Orca on this Mac kept to the registry: the app and its CLI, one project group per scope (anchor first, coloured, worktrees from local `main` in `.claude/worktrees/`), and the pairing to the Macs whose Orca it drives (`check`, `setup`, `scopes`, `pair PEER`, `--on PEER <verb>`); on a Linux peer the same verbs over `orca-ide`, its release `.deb` and the server's systemd user unit |
| `bin/orca-serve-agent` | a Mac's Orca run as a headless server under a LaunchAgent in the login session, so it survives a reboot and reaches the keychain (`HOST\|here [--remove] [--dry-run]`); the agent's label is a config key. On Linux the systemd user unit `orca-serve.service` with linger, the one the agent guest's cloud-init writes |
| `bin/dispatch`, `run-seed` | a seeded `claude/*` branch started with nobody at the keyboard: now, at a time, on another Mac (`--on`), or as the next step of a chain (`--next`); the run's records, its watcher and its window (`dispatch-rc`) |
| `bin/autofinish`, `autofinish-run` | the lander: a sweep that judges each idle `claude/*` worktree by the start rules in its header and, once armed on a Mac, starts a fresh unattended `/finish` on it; `install.sh --schedule` adds the sweep |
| `bin/pickup` | a session's branch picked up, seeded, reviewed or moved between Macs (`/pickup`, `/move`, `/later`) |
| `bin/harness` | one set of verbs over every coding-agent CLI (Claude Code, Codex, Orca), its adapters in `bin/harness_adapters/` |
| `bin/hail` | a pointer delivered to any session `harness` names — Claude Code's inbox socket (only to one idle 60 s or more, read back from the receiver), `codex queue` by thread, Orca's mailbox, a peer Mac over ssh, else helm's Talk and file roads; `--when idle` keeps a subscription that `hail subs --fulfil` sends |
| `bin/wharf`, `blueprintlib.py` | a ship's blueprint checked and applied, block by block (`wharf check`, `wharf apply`); `wharf apply --yard` lays it, pinned, on its scope's yard, and a plain apply of a ship whose scope has a yard is refused |
| `bin/rc-hosts` | one Remote Control host per registry repo on this Mac; `--agents` also judges the clock's automations (what each one's launcher line starts) |
| `bin/clock` | the calendar: every agent-run job as an Orca automation, one launcher line on haiku in a neutral workspace (`schedule`, or `--launchd` for the OS form kept), launchd left the script jobs and `dispatch --at`; `list` both Macs, `check` (G5: an agent-run job on launchd, a confidential pass without its `--account`), `board` one page, `fire` a long job detached through launchd |
| `bin/yard-node`, `node/` | the yard node: a hypervisor host (Ubuntu 24.04 autoinstall, an Incus preseed) and its agent guest's `#cloud-config`, rendered from the config dir and driven over `ssh <alias> incus …` (`render`, `apply`, `launch`, `snap`, `check`) |
| `bin/check` | a checkout's `check:` line run one script at a time under a few slots per Mac login |
| `hooks/cold_prompt.py` | a typed `/finish` in a cold or expensive session handed to a fresh run instead |

The tools after `orca-serve-agent` find the core as wharf does (`lib/core_path.py`) and every peer
through `common.tool()`: wharf (a hard edge: `branches`, `checkpoint`, `session_status`), keel,
plumb's `tier_check`, lighthouse's `account` and the project-management tools `ask`, `helm` and
`helmlib` (absent: a run's prompt drops the ask lines, `wharf check` refuses). Which Mac is which,
who the owner is and where an overlay lives are config, below; the code names none of them.
`yard-node`, its `node/` templates and their suite (the yard node's S2), and `clock` with its suite
(knowledge-layers S7) are private until a scrub of their own (off `.helloworld/allowlist.txt`).

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
  | `wharf-runs/orca-pairs` | `<host>:<peer>` — PEER's Orca is an environment of HOST's; `check` expects exactly these | no Mac pairs |
  | `wharf-runs/ssh` | `<peer>:<ssh alias>` — how `orca-host --on PEER` reaches it, and `wharf apply --yard` a yard | `--on` knows no peer; `--yard` falls back to `bin/harness`'s peers |
  | `wharf-runs/node/*` | the yard node's values, one per line: `ssh`, `name`, `user`, `ssh-keys`, `tailscale` (`<role>:<address>`), `logins`, `size`, `pool`, `orca-release` (`yard-node`'s header; `orca-host setup` on a Linux box without the guest's installer installs that release too) | `yard-node` names the missing key, exit 2; `orca-host setup`, the latest release |
  | `wharf-runs/serve-label` | the LaunchAgent label `orca-serve-agent` installs, first non-blank line; read on the Mac the agent is installed on (not on Linux: the unit is `orca-serve.service`) | `org.regatta.orca-serve` |
  | `wharf-runs/serve-label-previous` | an older label `orca-serve-agent` boots out and removes first, so one agent serves | none |
  | `wharf-runs/dispatch-host` | the Mac a run goes to when `dispatch` names none (`--on`), and the one whose run cap is 8 (3 elsewhere; `DISPATCH_MAX_RUNS` over either) | the first peer of `wharf-runs/ssh`, with one line on stderr; none, this Mac |
  | `wharf-runs/label-prefix` | the reverse-DNS prefix of the launchd jobs `dispatch`, `dispatch-rc`, `rc-hosts` and the sweep write and find (`<prefix>.dispatch.<repo>.<topic>…`, `<prefix>.autofinish`) | `org.regatta.claude` |
  | `wharf-runs/public-repos` | repo folder names a Codex run through `harness` stays out of, beside the overlay's own checkout and anything under `projects/oss/` | those two only, with one line on stderr |
  | `wharf-runs/brake-label` | the launchd job the studio brake stops (SIGSTOP), first non-blank line; a `wharf` start waits while that job's process is stopped, as it does while the brake's sentinel file (`.studio-brake` in the home folder) exists | only the file brakes |
  | `wharf-runs/headroom` | `<host>:avail=<min % free>,swap=<max GB>,rate=<max MB/s swapping>`, `*:` for any other host — the memory `headroom` lets `dispatch` start a run in; the same names on macOS and Linux | 10 % free, 50 MB/s, no swap rule |
  | `wharf-runs/load-max` | `<load per core> [log]` — a host whose 5-minute load per core is at or over it is passed over for the next one its scope allows; `log` records the pick without acting on it | 1.5; log only while `load-margin` is unset or `log` too |
  | `wharf-runs/load-margin` | `<load per core> [log]` — how much lighter a later host must be than the ones passed over | 0.5; log only while `load-max` is unset or `log` too |

  The core's own keys are read too: `regatta/laptop` (the Mac with a screen: a run's window opens
  there only), `regatta/owner` (the name the closing lines and refusals address, and the `by` of a
  marker the owner writes), `regatta/overlay` (the overlay checkout: a run's default repo, and the
  `bin/dispatch` its jobs name). With an overlay installed (that marker) `regatta check` names a missing key
  (bar the two `serve-label` keys, `brake-label` and `headroom`, optional); the tools themselves never refuse over one they did
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
(about 15 minutes, macOS). A suite the checkout lacks is skipped with a line.
