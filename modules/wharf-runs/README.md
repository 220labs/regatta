# wharf-runs — runs that start with nobody at the keyboard

Everything that lets an agent execute on more than one Mac: the fleet, the harness, the runs
themselves. Requires the core (`regatta`); the rest of the module moves in piece by piece.

| Piece | What it does |
| --- | --- |
| `bin/orca-host` | Orca on this Mac kept to the registry: the app and its CLI, one project group per scope (anchor first, coloured, worktrees from local `main` in `.claude/worktrees/`), and the pairing to the Macs whose Orca it drives (`check`, `setup`, `scopes`, `pair PEER`, `--on PEER <verb>`) |
| `bin/dispatch`, `run-seed` | a seeded `claude/*` branch started with nobody at the keyboard: now, at a time, on another Mac (`--on`), or as the next step of a chain (`--next`); the run's records, its watcher and its window (`dispatch-rc`) |
| `bin/autofinish`, `autofinish-run` | the lander: a sweep that judges each idle `claude/*` worktree by the start rules in its header and, once armed on a Mac, starts a fresh unattended `/finish` on it; `install.sh --schedule` adds the sweep |
| `bin/pickup` | a session's branch picked up, seeded, reviewed or moved between Macs (`/pickup`, `/move`, `/later`) |
| `bin/harness` | one set of verbs over every coding-agent CLI (Claude Code, Codex, Orca), its adapters in `bin/harness_adapters/` |
| `bin/wharf`, `blueprintlib.py` | a ship's blueprint checked and applied, block by block (`wharf check`, `wharf apply`) |
| `bin/rc-hosts` | one Remote Control host per registry repo on this Mac |
| `bin/check` | a checkout's `check:` line run one script at a time under a few slots per Mac login |
| `hooks/cold_prompt.py` | a typed `/finish` in a cold or expensive session handed to a fresh run instead |

The rows after `orca-host` moved in with the build's B7 step and stay private until a wharf-runs
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

  With an overlay installed (a `legacy` file in the config dir) a missing key is an error naming
  it, as the core does for its own. Host names are compared lower-case.
- **On a peer** (`--on PEER`): the copied script finds that Mac's own core (its `home` file or
  plugin) and reads that Mac's registry and config, so the peer needs the core installed, and
  the two keys where it has an overlay.

## Schedule

`sh modules/wharf-runs/install.sh --schedule` writes and loads one launchd agent, `bin/autofinish
--sweep` every 10 minutes (it starts nothing until `autofinish arm` on that Mac); `--remove` takes it
away. Where an overlay is installed (a `legacy` file in the config dir) it refuses: the overlay
schedules the sweep itself.

## Check

`bash modules/wharf-runs/tests/check.sh` — scratch paths only; no Orca, no network, no real launchd
(about 15 minutes, macOS). A suite the checkout lacks is skipped with a line.
