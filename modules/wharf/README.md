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
| `libexec/pr` | the branch's pull request without `gh`: `regatta pr status | ready | strays | merge | carried | restack | carry | stuck` — outside `bin/`, since `/usr/bin/pr` wins on a stock PATH |
| `bin/council` | the principal tier's council: blind complete designs from an Opus, a Codex and a Gemini arm, each on its own copy of the home repo (git writes it from a pack of the commit's trees) behind its fence, a blind cross-examination (each arm adopts, concedes or holds with evidence), the build path's `codex exec review`, the Receipt read from what the arms recorded, and `council fences`, the monthly re-probe: the H probes' nine commands and a denied tool per arm as a table, an arm a case broke refused until one holds; its model rows in `settings/models.json` |
| `bin/review-gate` | `/finish`'s review step: which two reviews a branch gets (by inserted lines and the week), and one merged list from their reports |
| `skills/finish`, `skills/evacuate`, `skills/todo` | land a branch; park a session's open items; keep `TODO.md` short |
| `templates/code/` | what a new project starts with: `AGENTS.md`'s session contract, the CI and automerge workflows, the pre-push guard |
| `bin/repos` | the registry (`repos.json`, read through the core) against this machine: what is cloned, pushed, behind; `--clone`, `--github`, `--branches`, `--hooks` |
| `bin/scopes` | the registry's scopes: groups of repos worked on together, each written as a VS Code workspace file; which are confidential and on which login (`set`, `configure`) |
| `bin/github-repo` | a local repo onto GitHub, private, with the merge policy and CI settings, then registered |
| `bin/ci-provider` | which CI runs a repo's check — Actions on ubuntu, Actions on a self-hosted runner on a Mac of one's own (`self-hosted`, which ci.json and `--to` may still call by an older name `wharf/ci-runner-kind` lists), or CircleCI — switched in one command; `--protect` swaps main's required check, `--runner` installs the repo's runner over ssh (the Mac's arm64 or x64 build; `--host`, `--name` and `--labels` for a further runner Mac of a fleet, `--instance N` for a further runner on one Mac) and sets the runs-on variable unless the fleet's other runners already serve it, or on a Linux host (`--labels self-hosted,Linux`: the linux-x64 or -arm64 build in a rootless Podman container, a fresh one a job, under a quadlet user unit below the host's sessions, no sudo, one runner a host unless `wharf/linux-runner-slots` names it, registered by its capabilities alone) for the Linux share's suites; `--pick [--apply]` chooses the lane by lighthouse's lanes, budgets and queue and flips that variable, and moves a Linux share between CircleCI orgs by theirs, or onto a self-hosted Linux lane while its runner is online (`CI_LINUX_RUNS_ON`), off when none can run it, each flip logged with its undo (lighthouse-ops S1, ci-two-orgs); the self-hosted kind keeps a job's `git config --global` in its own file and refuses a check that writes the runner login's own (`npm install -g`, `sudo`). Writes live state: lands by `/finish` only |
| `bin/runner-user` | a Linux fleet node's CI runner login, made or repaired as root in one idempotent run: what `ci-provider --runner install` refuses the host for lacking, all but a user namespace (podman, uidmap, slirp4netns; subordinate ranges past every existing line; linger; a user slice at CPUWeight 20, below the node's sessions), one ssh key, and the wall checked — no sudo, no group or home shared with the node user (`--node-user`), each a failed run. Then `ci-provider <repo> --runner install --host <node>-ci --name <node> --labels self-hosted,Linux`: the runner is named after its node. Off the allowlist until its publish review |
| `bin/ci-circleci` | a repo's CircleCI runs through the API: `trigger` a pipeline on a branch with parameters, `wait` for it, a job's `steps` output and `artifacts`, or all four as `run`; `rerun` a failed job's workflow from failed, once (one caller after another, not two at the same moment) and only on the checkout's branch unless `--branch` says otherwise; the token from the main checkout's `.env`, never printed |
| `templates/ci/` | the CircleCI part `ci-provider` writes; its Actions file is `templates/code/`'s check.yml |
| `bin/list-merge` | git's merge driver for `TODO.md` and `CHANGELOG.md` (by item: a done stands, a line stays under its item, a CHANGELOG line stays under `## Unreleased`), any other union file as union; `install <repo>` makes it that repo's `merge.union.driver`, never over one the repo set (sync.py runs it for each repo it tends) |
| `bin/todo-md` | a repo's `TODO.md` items by id (`/todo`'s shape): `lint` (an item without an id, a duplicate, a numbered citation, a cited id `TODO.md` lacks, the `merge=union` line; `--base <ref>`: an item done there that a union merge brought back), `list`, `done <id>`, `migrate` from a numbered list |
| `bin/tend` | `sync.py`'s worktree pass over every registered repo cloned here |
| `bin/finish-stuck-rebase` | finishes a rebase a session-end commit left stuck in a records repo, keeping both sides of the append-only files |
| `bin/fork_claude_session.py`, `skills/fork` | a session forked into another Claude Code session with its transcript |
| `bin/session_status.py` | whether an idle session is done, waiting, blocked or running, from its transcript alone; a guarded repo's session is never read |
| `skills/new-project` | a new repo from `templates/code/`, registered and on GitHub |
| `agents/` | nine agents: `architect`, `sr-architect` and `principal-architect` (one body, which sextant's `sounder` shares), `worker`, `sr-worker` and `principal-worker` (one body), `reviewer` and `reviewer-high` (one body), `code-reviewer` |
| `tests/check.sh` | the suites and the bin/ name rule; scratch repos, a scratch registry and config, a fake `gh` and `ssh`, no network |

Needs the core (`regatta`) and git. `gh` for `ci-provider`, which drives GitHub through it, and for
`repos --hooks`, which opens its pull requests with `gh pr create`; elsewhere `repos` and `pr` call
GitHub's API with a token (`GH_TOKEN`, `~/.git-credentials`, else `gh auth token`). Optional peers, each found through the
core's `common.tool()` and skipped with the loss named when absent (`install.sh --check` lists
them): keel (the D-list page and the hand-over-line block), wharf-runs' `autofinish` and `pickup`,
plumb's `usage-report` and `tier_check`, lighthouse's `claude-settings` and `trust-projects`,
wharf-runs' `rc-hosts`, wharf-runs' `harness` (council's Codex arm, its sibling checkout's first), atlas's `knowledge-commit`. `repos` reads a CircleCI repo through this
module's own `ci-provider`, its sibling in `bin/`, loaded directly (missing or broken, its CI line
says `ci-provider unloadable`). The registry is the core's `repos_json()`:
`$CLAUDE_REPOS_JSON`, else `wharf/repos.json` in the regatta config dir.

`regatta pr stuck [--json] [--dry-run]` reads ready `claude/*` PRs on one host per repo: its scope's yard,
else the configured laptop. It reports required reds by source, holds and live runs, and requests re-finish
for a DIRTY PR restack refuses only at this host's worktree head under S1's stop predicate. List conflicts stay
with `pr restack`. An unarmed PR can rerun its newest non-skipped `automerge.yml` run at that head, through
`autofinish-run lander spend reruns` first (two per branch, the existing lander store). Required checks come
from the repo's `.github/main-protection.json`, both `checks[].context` and `contexts`. The Linux context
keeps its name on Actions too; when absent, its pending trigger or a trigger successful within an hour
counts as pending. Nothing arms automerge directly. JSON's `prs` rows carry `kind`, `red`, `pending` and
an optional `request: {road, worktree, head}` for the tick to re-judge; exit 2 and `error` mean an incomplete
read. A non-owner returns no rows and spends nothing; `--dry-run` previews reruns without spending.

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
| `wharf/ci-runner-ssh` | the ssh alias that logs in to the runner Mac as the runner's user (`--runner --host` and `--labels` stand in for this key and the next, for another Mac of a fleet) | `ci-provider --runner` | `--runner` refuses, naming the file |
| `wharf/ci-runner-labels` | the runner Mac's labels, one per line: `self-hosted`, `macOS` and at least one of its own. The first of its own names the runner on GitHub; a runner in `wharf/ci-runner-caps.json` also takes the automatic labels from here, and an own label only while a runs-on asks for it. No check.yml is written from it | `ci-provider --to self-hosted`, `--runner` | both refuse, naming the file; status reads the labels from the repo's check.yml or its variable instead |
| `wharf/ci-runner-user` | the runner's macOS user, named in the trust warning | `ci-provider --to self-hosted`, `--runner install` | the warning says "the runner's user" |
| `wharf/ci-runner-kind` | older names of the self-hosted kind, one per line: an installer whose repos' `.github/ci.json` still name it after a Mac lists that name, and ci.json and `--to` read it as `self-hosted`, which is what `--to` writes back | `ci-provider`, `repos` (through `provider_from`) | no older names |
| `wharf/ci-runner-caps.json` | `{"<runner name>": ["<capability>", …]}`: what each self-hosted runner can do (Capabilities, below) | `ci-provider --runner caps` (sets the custom labels), `--runner install` (registers with them) | `caps` refuses, naming the file; `install` takes the labels key's |
| `wharf/linux-runner-slots` | `<ssh alias>:<N>` lines, the alias as `--host` or `wharf/ci-runner-ssh` gives it: a dedicated Linux runner host (no sessions beside it) that may hold N runners, `--instance 2..N` and other repos' runners beside them | `ci-provider --runner install` on a Linux runner | one runner a Linux host |
| `wharf/ci-runner-limits` | a Linux runner's container cap, one line `cpus=<cores>,memory=<n>g` (a live limit: `regatta limit set ci-runner-limits … --all --why …`; free CI S6) | `ci-provider --runner install` on a Linux host (the unit's `--cpus` and `--memory`, fitted to the host's cores), `--runner limits` (prints it) | `cpus=3,memory=12g`; a value it cannot read refuses, never the default |
| `wharf/hosts` | the Macs a repo clones on, each one's short name, one per line; every one but `regatta/laptop`'s clones as the registry's `machine_account` | `github-repo` (a new repo's `hosts`), `repos --github` (which repos invite the machine account) | `github-repo` registers this host alone, saying so where an overlay is installed; `repos` checks no invitation |

The registry (`wharf/repos.json`) is the core's `repos_json()`, above. The two knowledge repos are
atlas's keys, `atlas/layer` and `atlas/vault` (atlas's README), read by `lib/knowledge.py` without
the core: the checkpoint hook gives a write that reaches one from another session knowledge-commit's
recipe, `sync.py` fast-forwards both at every start, and `finish-stuck-rebase` defaults to the
vault. Absent, there is no knowledge repo (no guessed folder), and `sync.py` says so in one line
where an overlay is installed.

## Capabilities

CI routes on what a runner can do, never on which machine it is (the owner, 2026-10-31). A job's
runs-on lists the capabilities it needs, beside `self-hosted` and `macOS`: through a variable
(`CI_RUNS_ON`, `CI_RUNS_ON_FULL`, `CI_RUNS_ON_AUTOMERGE`), or on the line itself for a repo with no
public twin, where `.github/ci.json`'s `needs` says what the check needs (`["macos", "browser"]`;
with no OS named, or absent: macOS; another OS takes the variable form) and `ci-provider <repo> --to self-hosted` writes `runs-on: [self-hosted, macOS,
browser]` from it. A runner's custom labels are its capabilities; GitHub gives the job to a runner
carrying every label it asks for. The lanes' pick reads the same `needs`: a capability there is met
only by a self-hosted lane whose label list names it. The capabilities live in
`wharf/ci-runner-caps.json`, and `ci-provider <repo> --runner caps` makes GitHub's labels equal to it
with one PUT per runner: a change in the file reaches the queue as soon as it runs, with no
re-registration and no workflow edit. It fetches and reads the workflows of origin's default branch beside
this checkout's, as GitHub runs those until a branch lands, and refuses a change that would leave a runs-on, a variable or a literal list
(flow, the label alone, or block), with no runner, so a move goes: add the new capability,
point the variable at it (GitHub's variables API, `gh api -X PATCH
repos/<owner>/<repo>/actions/variables/<NAME> -f value='<JSON list>'`: `caps` writes labels only) or the
literal (add it to `needs`, then `--to self-hosted`, which also replaces a literal it wrote naming the
Mac), and once that is on main drop the old label. A runs-on it cannot read (a matrix's expression, a
runner group, an anchor, a variable mixed with labels: anything but plain labels) refuses the change when its
text names a label leaving every runner, and is otherwise said and not judged. `--runner install` reads the
same, fetching for a listed runner alone, and registers it with its capabilities, plus any own label a runs-on or a variable still asks for, which `--runner caps` then
refuses to drop until none asks for it: list it in the table meanwhile. Both read repository variables
only: an organization's or an environment's reads as unset, so `caps` does not judge it. `--to self-hosted` warns of a `needs` label no runner in the file lists, as `needs` is
open to any label and a typo reads as a capability.

| Capability | The runner… | Why a job asks for it |
| --- | --- | --- |
| `browser` | has a desktop login session, where headless Chrome runs | keel's in-Chrome cases; Chrome under a daemon with no session dumps the DOM and segfaults on exit |
| `git-2.43` | has git 2.43 or newer | `merge-tree --write-tree` (2.38), `--merge-base` (2.40), `merge_adds`' `-X` (2.43): wharf's rebase cases and plumb's trim cases |
| `whole-line` | runs the whole check line inside the `check` job's limit in check.yml (its `timeout-minutes`) | a push, the nightly run, a hand start, and a pull request while the Linux share is off |
| `linux-share` | is a Linux host's runner, the only one on its host, for the Linux share | check-linux.yml's `suite` jobs, where `CI_LINUX_RUNS_ON` names it (the pick's self-hosted Linux lane; the name is an example: the lane's list is what counts) |
| `automerge` | is kept for automerge.yml's short job alone | so that job never queues behind hour-long checks (docs/ci-queue-health-2026-10-27.md); give it nothing else |

The OS and the architecture are GitHub's own labels (`macOS`, `Linux`, `ARM64`, `X64`), read-only,
and a job names them directly. A runner's name stays an identity for people: no variable names one.
A repo may use a capability of its own; the table above is wharf's vocabulary, not a closed list.
A capability is what a job needs from the machine, never whether the machine is there: being awake
or on the network is availability, which no label routes on (the owner, 2026-10-31).
