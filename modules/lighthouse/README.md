# lighthouse — upkeep of the machines

The module that keeps the Macs a Regatta install runs on in order: a daily health pass, Claude
Code settings declared in git and applied to every config dir, several logins on one Mac, files
published to shared drives, folder trust, tiled windows — and the guards that keep an agent away
from the secrets folders, the live settings file and the repos a login may not open.

| Piece | What it does |
| --- | --- |
| `bin/health` | the unattended daily pass: fast-forward the checkouts `lighthouse/ff` names, wharf's tend, the privacy survey, the overlay's check (else `regatta check`); a failure posted once to the bulletin |
| `bin/claude-settings` | the declared settings (`check`, `apply`, `declare`): one declaration in git, applied to each config dir, drift reported |
| `bin/account` | several Claude Code (and Codex) logins on one Mac: the registry, `pick`, `limits`, `run`, `setup`, `check` |
| `shell/cc.zsh` | `cc <label> [claude args]`: start Claude Code on a chosen login |
| `bin/publish` | copy a file from a project to a shared drive (and a NAS), queued when a destination is away |
| `bin/trust-projects` | accept Claude Code's folder-trust dialog for every repo under the projects folder |
| `bin/tiling` | yabai's window layout, applied at every yabai start |
| `hooks/account_guard.py` | refuses a prompt in a repo the session's login may not open |
| `hooks/secrets_guard.py` | closes the secrets folders and the live settings file to agents |
| `hooks/design_route.py` | a new design artifact is made on the primary login, and shared as it is made |
| `hooks/tool_path.py` | the package managers' bin dirs on every session's Bash PATH |
| `tests/check.sh` | every suite; scratch dirs only, no network |

Install: `claude plugin marketplace add <this repo>`, then `claude plugin install lighthouse@regatta`
(it needs the core, `regatta`). From a clone: `sh modules/lighthouse/install.sh --check`.

## Private values

Nothing here names a host, a login, an account or a person. What is private reaches the module
as files in the regatta config dir (`$REGATTA_CONFIG`, else `.config/regatta` in the home folder),
under `lighthouse/`, written by whoever installs the modules (on the owner's Macs, the overlay's
`bootstrap.sh --config`). Each keeps the environment override it had, for a suite or one shell;
an override is never exported.

| Key | What | Read by | Override | Absent |
| --- | --- | --- | --- | --- |
| `lighthouse/accounts.json` | the login registry: labels, config dirs, rules (a link) | `account`, `account_guard`, `design_route` | `ACCOUNTS_FILE` | one login, the default config dir; where the overlay is installed, an error: `account` stops, the two guards block |
| `lighthouse/logins.json` | the logins file: per label the e-mail, plan, payer, Macs; `share.design` (a link, kept off git) | `account setup`/`doctor`, `design_route` | `ACCOUNT_LOGINS` | setup and doctor refuse; no share line |
| `lighthouse/vault` | the owner's private vault, a repo key under the projects folder: a row refused it is an employer's; health commits the bulletin there | `account`, `health` | — | no employer rows, but where the overlay is installed `add` and `orca-sync` stop; the bulletin line posted, not committed |
| `lighthouse/user.json` | the declared settings (a link to a file in git) | `claude-settings` | `CLAUDE_SETTINGS_DECLARED` | no declaration: every verb a no-op |
| `lighthouse/env-keys.json` | the install's own declarable `env` names: `{name: [values]}` | `claude-settings` | — | only CLAUDE_CODE_SUBAGENT_MODEL |
| `lighthouse/hosts` | the Macs' host names, one per line, for a declaration's `hosts` sections | `claude-settings` | `CLAUDE_SETTINGS_HOST` (this host) | any lowercase name |
| `lighthouse/vaults` | the shared drives whose `_secrets`/`_contacts` are closed, by name, for a path behind a variable | `secrets_guard` | `SECRETS_GUARD_DIR` (the folder) | the mounted shared drives that hold one |
| `lighthouse/gated-tools` | the session-sync tool, then its front end, one per line: the tools whose ungating verbs are refused | `secrets_guard` | — | `sessionpipe`, no front end |
| `lighthouse/ff` | the checkouts health fast-forwards, one path per line | `health` | — | none, and the log says so |
| `lighthouse/design-host` | where a design start is dispatched | `design_route` | — | the hand-off stays on this Mac |
| `lighthouse/cc-prefix` | what `cc X` puts before X to make a label | `cc.zsh` | — | none: X is the label |
| `lighthouse/shares` | each scope's share, `data:<name>`, `vault:<name>` | `publish` | — | `data`, `vault` |
| `lighthouse/nas`, `lighthouse/drive` | publish's two roots: the NAS mount, the Drive's folder of shares | `publish` | `PUBLISH_NAS`, `PUBLISH_DRIVE` | that destination left out; none: refused |
| `lighthouse/yabairc` | the yabai rc `.yabairc` links to (a link) | `tiling` | — | this module's `settings/yabairc` |
| `wharf-runs/ssh` | `<host>:<ssh alias>` per peer Mac (wharf-runs' key, read here) | `account` | — | no peer: doctor and setup stay local |

The core's own keys are read as the core reads them: `regatta/owner` (the name in a refusal),
`regatta/projects`, `regatta/orca-deny` (ORCA_ROW's list). `install.sh --check` lists each key
found or not.

A peer is found through the core (`common.tool()`): wharf's `fork_claude_session.py`,
`worktree_allow.py`, `tend` and `sync.py`, wharf-runs' `rc-hosts`, atlas's `bulletin.py` and
`knowledge-commit`, plumb's `usage-report`, keel's `sheep` (named in a refusal). Without one, the
verb that needs it says so in one line and the rest runs (the design's G16–G18).

## The guards

`account_guard`, `secrets_guard` and `design_route` are deny hooks. `secrets_guard` imports
nothing from the core, so it guards where the core is missing too; `account_guard` and
`design_route` fail closed when the core is missing or broken (a refusal naming the repair). They
stop accidents, not intent: each header says what it does not see.
