# wharf — one session, one worktree, a clean landing

Every Claude Code session that writes works in its own git worktree on its own `claude/*` branch;
the checkpoint hook commits each turn there, pushes it, and keeps the primary checkout on `main`;
`/finish` turns the branch into clean commits and lands it through a pull request.

| Piece | What it does |
| --- | --- |
| `hooks/checkpoint.py` | the checkpoint commit per turn, the one-writer lock per worktree, and the denies: no write on a primary's `main`, no bare push, no branch or worktree deletion by an agent. Opt-in per repo (`.claude/workflow.json`); a deny hook, so with no core it refuses rather than passes |
| `hooks/sync.py` | at session start: `main` fast-forwarded from origin, dead sessions' worktrees committed and pushed, landed branches archived, one note |
| `hooks/branches.py`, `hooks/carried.py` | the branch survey and the proof a branch's content is on `main`; what one branch carries from another |
| `hooks/worktree_allow.py` | EnterWorktree and ExitWorktree into any repo's `.claude/worktrees/` never ask |
| `libexec/pr` | the branch's pull request without `gh`: `regatta pr status | ready | strays | merge | carried` — outside `bin/`, since `/usr/bin/pr` wins on a stock PATH |
| `bin/review-gate` | `/finish`'s review step: which two reviews a branch gets (by inserted lines and the week), and one merged list from their reports |
| `skills/finish`, `skills/evacuate`, `skills/todo` | land a branch; park a session's open items; keep `TODO.md` short |
| `templates/code/` | what a new project starts with: `AGENTS.md`'s session contract, the CI and automerge workflows, the pre-push guard |
| `bin/repos` | the registry (`repos.json`, read through the core) against this machine: what is cloned, pushed, behind; `--clone`, `--github`, `--branches`, `--hooks` |
| `bin/scopes` | the registry's scopes: groups of repos worked on together, each written as a VS Code workspace file; which are confidential and on which login (`set`, `configure`) |
| `bin/github-repo` | a local repo onto GitHub, private, with the merge policy and CI settings, then registered |
| `bin/ci-provider` | which CI runs a repo's check — Actions on ubuntu, Actions on a self-hosted runner on a Mac of one's own (`self-hosted`, or the name `wharf/ci-runner-kind` gives it), or CircleCI — switched in one command; `--protect` swaps main's required check, `--runner` installs the repo's runner over ssh and sets the runs-on variable; the self-hosted kind keeps a job's `git config --global` in its own file and refuses a check that writes the runner login's own (`npm install -g`, `sudo`). Writes live state: lands by `/finish` only |
| `bin/ci-circleci` | a repo's CircleCI runs through the API: `trigger` a pipeline on a branch with parameters, `wait` for it, a job's `steps` output and `artifacts`, or all four as `run`; the token from the main checkout's `.env`, never printed |
| `templates/ci/` | the CircleCI part `ci-provider` writes; its Actions file is `templates/code/`'s check.yml |
| `bin/tend` | `sync.py`'s worktree pass over every registered repo cloned here |
| `bin/finish-stuck-rebase` | finishes a rebase a session-end commit left stuck in a records repo, keeping both sides of the append-only files |
| `bin/fork_claude_session.py`, `skills/fork` | a session forked into another Claude Code session with its transcript |
| `bin/session_status.py` | whether an idle session is done, waiting, blocked or running, from its transcript alone; a guarded repo's session is never read |
| `skills/new-project` | a new repo from `templates/code/`, registered and on GitHub |
| `agents/` | seven agents: `architect` and `sr-architect` (one body, which sextant's `sounder` shares), `worker`, `sr-worker`, `reviewer` and `reviewer-high` (one body), `code-reviewer` |
| `tests/check.sh` | the suites and the bin/ name rule; scratch repos, a scratch registry and config, a fake `gh` and `ssh`, no network |

Needs the core (`regatta`) and git. `gh` for `ci-provider`, which drives GitHub through it, and for
`repos --hooks`, which opens its pull requests with `gh pr create`; elsewhere `repos` and `pr` call
GitHub's API with a token (`GH_TOKEN`, `~/.git-credentials`, else `gh auth token`). Optional peers, each found through the
core's `common.tool()` and skipped with the loss named when absent (`install.sh --check` lists
them): keel (the D-list page and the hand-over-line block), wharf-runs' `autofinish` and `pickup`,
plumb's `usage-report` and `tier_check`, lighthouse's `claude-settings` and `trust-projects`,
wharf-runs' `rc-hosts`, atlas's `knowledge-commit`. `repos` reads a CircleCI repo through this
module's own `ci-provider`, its sibling in `bin/`, loaded directly (missing or broken, its CI line
says `ci-provider unloadable`). The registry is the core's `repos_json()`:
`$CLAUDE_REPOS_JSON`, else `wharf/repos.json` in the regatta config dir.

Install it from the marketplace (`claude plugin install wharf@regatta`), or from a clone, where the
module runs in place. The hooks are not in the plugin yet: `sh modules/wharf/install.sh --hooks` prints the settings
block to merge into your Claude Code settings, with this clone's paths.

## Private values

Nothing new here names a host, a login or an account. What is private reaches the module as files
in the regatta config dir (`$REGATTA_CONFIG`, else `.config/regatta` in the home folder), under
`wharf/`, written by whoever installs the modules (on the owner's Macs, the overlay's
`bootstrap.sh --config`). The keys that refuse when absent are in `config-keys`, so `regatta
check` names a missing one where an overlay is installed.

| Key | What | Read by | Absent |
| --- | --- | --- | --- |
| `wharf/ci-runner-ssh` | the ssh alias that logs in to the runner Mac as the runner's user | `ci-provider --runner` | `--runner` refuses, naming the file |
| `wharf/ci-runner-labels` | runs-on's labels for the runner Mac, one per line: `self-hosted`, `macOS` and at least one of its own; the first of its own names the runner on GitHub | `ci-provider --to <self-hosted kind>`, `--runner` | both refuse, naming the file; status reads the labels from the repo's check.yml or its variable instead |
| `wharf/ci-runner-user` | the runner's macOS user, named in the trust warning | `ci-provider --to <self-hosted kind>`, `--runner install` | the warning says "the runner's user" |
| `wharf/ci-runner-kind` | the self-hosted kind's name in every repo's `.github/ci.json` and `--to`: an installer whose repos already name it after a Mac writes that name | `ci-provider`, `repos` (through `provider_from`) | `self-hosted` |
| `wharf/hosts` | the Macs a repo clones on, each one's short name, one per line; every one but `regatta/laptop`'s clones as the registry's `machine_account` | `github-repo` (a new repo's `hosts`), `repos --github` (which repos invite the machine account) | `github-repo` registers this host alone, saying so where an overlay is installed; `repos` checks no invitation |

The registry (`wharf/repos.json`) is the core's `repos_json()`, above. The two knowledge repos are
atlas's keys, `atlas/layer` and `atlas/vault` (atlas's README), read by `lib/knowledge.py` without
the core: the checkpoint hook gives a write that reaches one from another session knowledge-commit's
recipe, `sync.py` fast-forwards both at every start, and `finish-stuck-rebase` defaults to the
vault. Absent, there is no knowledge repo (no guessed folder), and `sync.py` says so in one line
where an overlay is installed.
