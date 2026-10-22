# wharf-runs — runs that start with nobody at the keyboard

Everything that lets an agent execute on more than one Mac: the fleet, the harness, the runs
themselves. Requires the core (`regatta`); the rest of the module moves in piece by piece.

| Piece | What it does |
| --- | --- |
| `bin/orca-host` | Orca on this Mac kept to the registry: the app and its CLI, one project group per scope (anchor first, coloured, worktrees from local `main` in `.claude/worktrees/`), and the pairing to the Macs whose Orca it drives (`check`, `setup`, `scopes`, `pair PEER`, `--on PEER <verb>`) |
| `bin/orca-serve-agent` | a Mac's Orca run as a headless server under a LaunchAgent in the login session, so it survives a reboot and reaches the keychain (`HOST\|here [--remove] [--dry-run]`); the agent's label is a config key |
| `bin/dispatch`, `run-seed` | a seeded `claude/*` branch started with nobody at the keyboard: now, at a time, on another Mac (`--on`), or as the next step of a chain (`--next`); the run's records, its watcher and its window (`dispatch-rc`) |
| `bin/autofinish`, `autofinish-run` | the lander: a sweep that judges each idle `claude/*` worktree by the start rules in its header and, once armed on a Mac, starts a fresh unattended `/finish` on it; `install.sh --schedule` adds the sweep |
| `bin/pickup` | a session's branch picked up, seeded, reviewed or moved between Macs (`/pickup`, `/move`, `/later`) |
| `bin/harness` | one set of verbs over every coding-agent CLI (Claude Code, Codex, Orca), its adapters in `bin/harness_adapters/` |
| `bin/hail` | a pointer delivered to any session `harness` names — Claude Code's inbox socket (only to one idle 60 s or more, read back from the receiver), `codex queue` by thread, Orca's mailbox, a peer Mac over ssh, else helm's Talk and file roads; `--when idle` keeps a subscription that `hail subs --fulfil` sends |
| `bin/wharf`, `blueprintlib.py` | a ship's blueprint checked and applied, block by block (`wharf check`, `wharf apply`) |
| `bin/rc-hosts` | one Remote Control host per registry repo on this Mac |
| `bin/check` | a checkout's `check:` line run one script at a time under a few slots per Mac login |
| `hooks/cold_prompt.py` | a typed `/finish` in a cold or expensive session handed to a fresh run instead |

`orca-serve-agent` is private until the same scrub (off `.helloworld/allowlist.txt`), though written
as if public. The rows after it moved in with the build's B7 step and stay private until a wharf-runs
scrub: their text still names the owner's own layout. They find the core as wharf does
(`lib/core_path.py`) and every peer through `common.tool()`: wharf (a hard edge: `branches`,
`checkpoint`, `session_status`), keel, plumb's `tier_check`, lighthouse's `account` and the
project-management tools `ask`, `helm` and `helmlib` (absent: a run's prompt drops the ask lines,
`wharf check` refuses).

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
  | `wharf-runs/ssh` | `<peer>:<ssh alias>` — how `orca-host --on PEER` reaches it | `--on` knows no peer |
  | `wharf-runs/serve-label` | the LaunchAgent label `orca-serve-agent` installs, first non-blank line; read on the Mac the agent is installed on | `org.regatta.orca-serve` |
  | `wharf-runs/serve-label-previous` | an older label `orca-serve-agent` boots out and removes first, so one agent serves | none |
  | `wharf-runs/brake-label` | the launchd job the studio brake stops (SIGSTOP), first non-blank line; a `wharf` start waits while that job's process is stopped, as it does while the brake's sentinel file (`.studio-brake` in the home folder) exists | only the file brakes |
  | `wharf-runs/headroom` | `<host>:avail=<min % free>,swap=<max GB>,rate=<max MB/s swapping>`, `*:` for any other host — the memory `headroom` lets `dispatch` start a run in; the same names on macOS and Linux | 10 % free, 50 MB/s, no swap rule |

  With an overlay installed (a `legacy` file in the config dir) a missing key is an error naming
  it, as the core does for its own (bar the two `serve-label` keys, `brake-label` and `headroom`, optional). Host names are compared lower-case.
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
away. Where an overlay is installed (a `legacy` file in the config dir) it refuses: the overlay
schedules the sweep itself.

## Check

`bash modules/wharf-runs/tests/check.sh` — scratch paths only; no Orca, no network, no real launchd
(about 15 minutes, macOS). A suite the checkout lacks is skipped with a line.
