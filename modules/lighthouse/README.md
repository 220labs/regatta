# lighthouse — upkeep of the machines

The module that keeps the Macs a Regatta install runs on in order: a daily health pass, Claude
Code settings declared in git and applied to every config dir, several logins on one Mac, files
published to shared drives, folder trust, tiled windows — and the guards that keep an agent away
from the secrets folders, the live settings file and the repos a login may not open.

| Piece | What it does |
| --- | --- |
| `bin/health` | the unattended daily pass: fast-forward the checkouts `lighthouse/ff` names, wharf's tend, the privacy survey, the Orca serve agent's process and answer, free disk (fail under 50 GB, naming the three biggest folders; warn under 100), the overlay's check (else `regatta check`); a failure posted once to the bulletin |
| `bin/claude-settings` | the declared settings (`check`, `apply`, `declare`): one declaration in git, applied to each config dir, drift reported |
| `bin/account` | several Claude Code (and Codex) logins on one Mac: the registry, `pick`, `limits`, `run`, `setup`, `check` |
| `shell/cc.zsh` | `cc <label> [claude args]`: start Claude Code on a chosen login |
| `bin/publish` | copy a file from a project to a shared drive (and a NAS), queued when a destination is away |
| `bin/trust-projects` | accept Claude Code's folder-trust dialog for every repo under the projects folder |
| `bin/tiling` | yabai's window layout, applied at every yabai start |
| `bin/ops` | the operations desk's own verbs: `usage` reads CI minutes and credits per budgeted account with the owner's token, in the desk's job only; `pick` runs wharf's `ci-provider --pick` over the repos (lighthouse-ops S1); `sample` appends the desk's metrics row to the log dir's `ops.jsonl` — queue, run and check slots, load, memory, budgets, the token's standing (`token.plan`, `token.project`), token weeks, cost — every 15 minutes on the ops host (`install.sh --schedule`), and `status` prints the last row, which helm's board shows as its ops row (S2); `ingest` appends every fleet repo's new issues and comments, and the configured Projects' items, to the log dir's `intake.jsonl` — a row an event, metadata and the body's hash, never a body — every 10 minutes on the ops host, a confidential scope's repos only on its own yard and nothing on a torn registry, and `intake` lists the open issues, a card each on helm's board (S4); `classify`, in the same job, takes each new open issue through four gate rows (`lighthouse.*`), the ladder and every cap of `lighthouse/ops.json` into the log dir's `ops-verdicts.jsonl`, laying nothing (S5: log-only), and `digest` counts the logged week (S5) |
| `hooks/account_guard.py` | refuses a prompt in a repo the session's login may not open |
| `hooks/secrets_guard.py` | closes the secrets folders, the coding CLIs' own logins and the live settings file to agents, and a confidential scope's paths to a session outside it (the fence) |
| `hooks/vendor_hook.py` | runs a Claude PreToolUse guard unchanged inside Codex's or Antigravity's own hooks: their payload in, their answer out; and adds the CLI's `Co-Authored-By` to its commits |
| `bin/vendor-hooks` | `apply`, `check`, `homes`: those entries and a rules pointer in every Codex and Antigravity home this Mac has (`install.sh --vendor`) |
| `hooks/design_route.py` | a new design artifact is made on the primary login, and shared as it is made |
| `hooks/tool_path.py` | the package managers' bin dirs on every session's Bash PATH |
| `tests/check.sh` | every suite; scratch dirs only, no network |
| `tests/parity.sh` | each guard rule, a deny and an allow case, against Claude Code's, Codex's and Antigravity's payloads (`parity_rules.py`, the table): a rule a CLI cannot meet is a red row |

## Tenants

Work for several organisations from one Mac without mixing their seats. Name each organisation's
repos as a tenant in the registry and mark its login's row:

```json
{"accounts": [{"label": "acme", "home": "<its config dir>", "tenant": "acme",
               "repos": {"deny": ["<your private vault>"]}}, …],
 "tenants": {"acme": {"repos": ["acme-*"]}}}
```

A tenant's repos then run on its own login, and only there. `account pick --repo` takes every
dispatched, picked-up or self-landing run there, and waits when that login has no room instead of
borrowing another seat. A session started by hand on any other login, the default one included, is
stopped at its first prompt by `account_guard`, which names the way in: that login's VS Code
profile (`account vscode acme`) or `cc <letter>`. `account doctor` checks that VS Code opens each
tenant folder, and each workspace holding one, in that profile. A tenant's login may still open
other repos unless its own deny list says otherwise — so give an organisation's seat the deny list
that keeps your private repos off it, as above. An entry is a repo key or a glob (`*` spans `/`).

To keep the list apart from the registry (in a private drive, say), write the tenants file
instead, naming each tenant's logins there; once written it is the whole of tenancy, and the
registry's `tenants` and rows' `tenant` are ignored:

```json
{"acme": {"repos": ["acme-*"], "logins": ["acme"]}}
```

`account tenant set acme --repos 'acme-*' --logins acme` writes one entry and `account tenant drop acme`
removes one: through the link, read back, the hooks' copy refreshed at once. They refuse a login already
in another tenant (each login is one tenant's), a repo another tenant holds, a label no claude or codex row has, a
file that does not read (writing would drop the rest), and an unattended caller (`CLAUDE_UNATTENDED`).

A tenant's `logins` may also name a Codex row: `account pick --provider codex --repo` then routes the tenant's
repos to it, and refuses every other Codex row. That makes the row `owns` them, the core's vendor fence's yes for
the tenant's confidential and guarded repos, while every Codex road runs on `CODEX_HOME` (or the default Codex home), not on the
row pick names: `tenant set` refuses a Codex label whose home is not that one. Nothing guards a Codex session by hook, so for Codex tenancy
is routing only; a tenant with a Codex login and no Claude one leaves its Claude sessions nowhere to start:
`tenant set` refuses one, and `account doctor` names one written by hand.

Your own private repos can be a tenant too: name your vault and its siblings, on your own logins, and
every other seat — an organisation's, one Orca holds that no row names — is refused them without a deny
list. The vault's tenant is the one tenancy also binds where a session starts *above* a repo: your
default config dir's `CLAUDE.md` imports from the vault, so a folder holding the vault's tenant's repos
(the projects folder, the home folder) is off every login but the tenant's, as a deny list's repo makes it,
and a row refused the vault links the work memory. `account doctor` lists each tenant, flags a deny-list
entry a tenant already refuses (kept by hand, derived by tenancy), and flags a vault no tenant and no deny
list holds. Write the tenant before taking the deny lists off.

Each good read is copied beside the key (`.tenants.json.last`), and while the link reads nothing or
is gone (the drive behind it away) that copy holds: tenancy never fails open onto another seat. A Mac
whose link has never read has no copy either, and there tenancy is closed: every repo is refused to every
login, the default dir's included, until the link reads (`account setup` seeds the copy on a new Mac, and the
usage tick's `refresh` or any reader allowed to open the link does it unasked). That is said on stderr, in
each refusal and by `account doctor`, which also names a copy in force, a file that does not parse, a tenant
left with no login, and a repo two tenants both take (it runs on neither). To end tenancy, write `{}`;
removing the key ends it only where no copy is left. `tenant drop` of the vault's tenant warns: it is
what keeps the vault off every other seat.

Where the key is a link into a cloud drive (the core's `drive_backed()`: macOS's File Provider folder, or
`REGATTA_DRIVE_ROOTS`), a hook's reader opens it only under claude-host (the core's `claude_host()`): a hook
runs in whatever app started the session, and one with no grant for the drive waits on a privacy prompt
nobody sees. So outside claude-host the readers a hook reaches — `account allowed`, `account limits`,
`account_guard`, `design_route` — take the copies first (`.tenants.json.last`, `.logins.json.last`), and the
link only once, to seed a missing copy; doctor, setup and `refresh --force` read the links themselves. A
plain file, or a link elsewhere, is read as it is, so an edit takes effect at once. `account refresh`
re-reads both links; plumb's usage tick runs it every 15 min through claude-host, so a change reaches the
hooks within 15 min.

Install: `claude plugin marketplace add <this repo>`, then `claude plugin install lighthouse@regatta`
(it needs the core, `regatta`, and `helloworld`, which beacon's build scan uses). From a clone: `sh modules/lighthouse/install.sh --check`.

## Private values

Nothing here names a host, a login, an account or a person. What is private reaches the module
as files in the regatta config dir (`$REGATTA_CONFIG`, else `.config/regatta` in the home folder),
under `lighthouse/`, written by whoever installs the modules (on the owner's Macs, the overlay's
`bootstrap.sh --config`). Each keeps the environment override it had, for a suite or one shell;
an override is never exported.

| Key | What | Read by | Override | Absent |
| --- | --- | --- | --- | --- |
| `lighthouse/accounts.json` | the login registry: labels, config dirs, rules (a link): per row `week_max`, `window_max` (the flat 5-hour limit, less 10 points per exhaustion in 7 days), `pace_headroom` (default 10: a row over that limit still runs while its 5-hour spend is under the window's elapsed share and this many points are left), `free_below` (default 0, off: a 5-hour spend under it runs whatever the limit, margin or pace; the owner's rows are to set 70); either, not a number, reads as its default, `reserve` | `account`, `account_guard`, `design_route` | `ACCOUNTS_FILE` | one login, the default config dir; where the overlay is installed, an error: `account` stops, the two guards block |
| `lighthouse/tenants.json` | the tenants: `{name: {repos, logins}}` (a link, kept off git) | `account`, `account_guard` | `TENANTS_FILE`; an `ACCOUNTS_FILE` other than the live key reads `<it>.tenants` | its last good copy, else the registry's own `tenants`, else none |
| `lighthouse/logins.json` | the logins file: per label the e-mail, plan, payer, Macs; `share.design` (a link, kept off git) | `account setup`/`doctor`/`allowed`/`refresh`, `design_route` | `ACCOUNT_LOGINS` | setup and doctor refuse; no share line |
| `lighthouse/vault` | the owner's private vault, a repo key under the projects folder: a row refused it is an employer's; health commits the bulletin there | `account`, `health` | — | no employer rows, but where the overlay is installed `add` and `orca-sync` stop; the bulletin line posted, not committed |
| `lighthouse/user.json` | the declared settings (a link to a file in git) | `claude-settings` | `CLAUDE_SETTINGS_DECLARED` | no declaration: every verb a no-op |
| `lighthouse/env-keys.json` | the install's own declarable `env` names: `{name: [values]}` | `claude-settings` | — | only CLAUDE_CODE_SUBAGENT_MODEL |
| `lighthouse/hosts` | the Macs' host names, one per line, for a declaration's `hosts` sections | `claude-settings` | `CLAUDE_SETTINGS_HOST` (this host) | any lowercase name |
| `lighthouse/vaults` | the shared drives whose `_secrets`/`_contacts` are closed, by name, for a path behind a variable | `secrets_guard` | `SECRETS_GUARD_DIR` (the folder; `SECRETS_GUARD_SCRATCH_ROOT`, the fence's scratch root, in tests) | the mounted shared drives that hold one |
| `lighthouse/guarded-dirs` | absolute local folders closed to agents like `_secrets`, one per line (`~` the home folder; a relative line is dropped), on every platform, Drive or none: the desk's token dir first | `secrets_guard`; `ops usage` warns when the token dir is not listed | — | none guarded |
| `lighthouse/secrets/ops.env` | the owner's token for the billing read (`GITHUB_TOKEN`, `CIRCLECI_TOKEN`): on the ops host only, its dir 0700 and the file 0600, neither a link, written by the owner over ssh | `ops`, in the desk's own job only (`LIGHTHOUSE_DESK=1`, no session) | — | every account `absent`: the pick holds every hosted lane of a private repo over budget |
| `lighthouse/ci-lanes.json` | the runner lanes: `{"lanes": [{name, provider, runs_on, runs, account}]}` | wharf's `ci-provider --pick` | — | `--pick` refuses, naming the file |
| `lighthouse/ci-budgets.json` | per account a month cap (`month_minutes` or `month_credits`), `week_share`, `reserve` (default 0.2), `margin`; `user`, `org` or `org_slug` to read it by | `ops usage`, `ci-provider --pick` | — | every hosted lane of a private repo over budget |
| `lighthouse/ci-queue-max` | a self-hosted lane's queued-seconds p50 the pick still sends work to | `ci-provider --pick` | — | 600 |
| `lighthouse/ops-host` | the one host the desk runs on and the pick writes from | `ci-provider --pick --apply`, `ops sample`, `ops ingest`, `ops is-host`, `install.sh --schedule` | — | the desk is off: `--apply`, `sample`, `ingest` and `--schedule` refuse |
| `lighthouse/ops-projects` | the GitHub Projects the intake reads, one a line: `user/<login>/<number>` or `org/<login>/<number>`; read with the desk's token (`GITHUB_TOKEN`), which needs the Projects read `token.project` probes | `ops ingest` | — | no Project read; the repos' issues still are |
| `lighthouse/ops.json` | the desk's sense (S5): `dry` (true), the caps `max_auto_runs_day` (3), `max_auto_runs_repo_day` (1), `max_open_auto_prs` (3), `week_share` (0.1, the desk's share of the week's list spend), `importance_auto_max` (3), `cost_auto` (`["xs", "s"]`), `labels` (`["bug"]`), `repos` (registry keys, `"*"` all; default none); an unknown key refuses the file | `ops classify`, `ops digest` | — | the desk is off: `classify` writes nothing |
| `lighthouse/ops-bots` | the GitHub Apps that file for the issue road (beacon's, deadman's), one login a line as GitHub prints it (`<app>[bot]`) | `ops ingest` | — | their issues read as a stranger's |
| `lighthouse/gated-tools` | the session-sync tool, then its front end, one per line: the tools whose ungating verbs are refused | `secrets_guard` | — | `sessionpipe`, no front end |
| `lighthouse/ff` | the checkouts health fast-forwards, one path per line | `health` | — | none, and the log says so |
| `lighthouse/design-host` | where a design start is dispatched | `design_route` | — | the hand-off stays on this Mac |
| `lighthouse/cc-prefix` | what `cc X` puts before X to make a label | `cc.zsh` | — | none: X is the label |
| `lighthouse/shares` | each scope's share, `data:<name>`, `vault:<name>` | `publish` | — | `data`, `vault` |
| `lighthouse/nas`, `lighthouse/drive` | publish's two roots: the NAS mount, the Drive's folder of shares | `publish` | `PUBLISH_NAS`, `PUBLISH_DRIVE` | that destination left out; none: refused |
| `lighthouse/yabairc` | the yabai rc `.yabairc` links to (a link) | `tiling` | — | this module's `settings/yabairc` |
| `wharf-runs/ssh` | `<host>:<ssh alias>` per peer Mac (wharf-runs' key, read here) | `account` | — | no peer: doctor and setup stay local |
| `wharf-runs/serve-label` | the Orca serve agent's launchd label (wharf-runs' key, read here) | `health` | — | `org.regatta.orca-serve`; no such LaunchAgent on the Mac: the line is skipped |

The core's own keys are read as the core reads them: `regatta/owner` (the name in a refusal),
`regatta/projects`, `regatta/orca-deny` (ORCA_ROW's list), `regatta/log-dir` (where the fence
writes `fence.log`); and wharf's `wharf/repos.json` (`CLAUDE_REPOS_JSON`), whose scopes' `confidential`
flag the fence reads. `install.sh --check` lists each key
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

**The fence** (`secrets_guard`, since 2026-10-21): a scope the registry flags `"confidential": true`
(wharf's `scopes set <scope> --confidential`) is closed to every session whose cwd — and start
directory — is outside it: its checkouts and worktrees, its transcripts folder and each login's
session folder for them (`projects/<slug>/`: the session logs and the memory dir), and Claude Code's scratch
folder of each (`<tmp>/claude-<uid>/<slug>/`, a removed worktree's included), by Read, Edit,
Write, NotebookEdit, Grep, Glob and Bash. A session inside the scope reads all
of it, open scopes stay open, and each refusal adds one line (time, scope, tool, cwd, session; never
the path) to `<log-dir>/fence.log`. The paths are the core's `scope_paths()`, mirrored in the stdlib, plus removed worktrees' session
and scratch folders; a scratch folder walls the scope but never makes a session inside it. A walker over
the temp folder (`find /tmp`) is refused while such a scratch folder exists, as one over the projects folder is;
`tests/hooks.sh` proves the two agree.

**Every CLI, one rule set** (since 2026-10-29, the owner's D2-A in docs/codex-agy-gaps-2026-10-29.md): a Codex
or Antigravity session, hand-started or Orca's, meets `secrets_guard` and wharf's checkpoint through its own
PreToolUse hooks. `bin/vendor-hooks apply` (or `install.sh --vendor`, once the branch is on main) writes one
entry per guard into each Codex home's `hooks.json` (`$CODEX_HOME`, `~/.codex`, each Codex row of the account
registry) and our `regatta` key into Antigravity's `config/hooks.json`; `hooks/vendor_hook.py` translates the
payload, runs the guard as it is, and answers in the CLI's own shape. Beside them a rules pointer —
`<codex home>/AGENTS.md`, `~/.gemini/GEMINI.md` — names, never copies, what a Claude session of the same tenant
loads that may leave for another vendor: its seat's `rules/`, the `@` files every seat's CLAUDE.md loads (or the
config key `lighthouse/vendor-layer`), and the bulletin; never a file only one seat loads, never the CLAUDE.md. Codex runs a hook only once it is
reviewed (`codex` → /hooks); `vendor-hooks check` (and `install.sh --check`) counts the entries waiting for it.
What differs, and why: wharf's worktree lock is Claude's alone (a vendor session reports no end that would free
it; checkpoint's VENDOR), and dispatch's launch-time deny list (pushes, GitHub, ssh, deploys, the queue's verbs)
is checkpoint's rule for an unattended vendor run, where Claude's own permission rules carry it for a Claude run.
Antigravity keeps its login in the macOS keychain first, which no file guard reaches; its fallback files are walled. `tests/parity.sh` runs each rule on each CLI.

## beacon — support: a site's contact form and its bot

Lighthouse's second job is the people who meet a business from outside: beacon answers a site's
visitors from the site's own pages (Claude Haiku, one Cloudflare Worker on the free plan) and
hands what it cannot answer to the people behind the site: the contact form files each message
as a GitHub issue, and with the `telegram` sink each form send, chat hand-off or mail to the
site's address opens a topic in the people's Telegram group (a chat hand-off files the issue only
when the visitor left an address), where their reply goes back to the visitor in the chat or by
mail. A visitor who asks the bot for a person is handed over the same way. `bin/beacon` builds, deploys and reads it; it needs `helloworld`,
whose word list scans what it builds. Its chart is `beacon/README.md`: read "What it cannot do"
and "Before the first deploy" there first. beacon's files stay in the private repo until its home
is decided: it is no Claude Code plugin, and may move to a repo of its own.

## deadman — the switch for the Macs nobody watches

A Mac that runs unattended work cannot report its own death. deadman is one Cloudflare Worker on
the free plan that each such Mac pings every few minutes; one that goes quiet past a grace becomes
a GitHub issue that mentions its owner, opened by the switch's own GitHub App and closed again by
its next ping, with a mail through Resend as the fallback when GitHub refuses. Its state is one
SQLite-backed Durable Object, a row a Mac. Its chart is `deadman/README.md`.
