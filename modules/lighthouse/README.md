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
| `bin/ops` | the operations desk's own verbs: `usage` reads CI minutes and credits per budgeted account with the owner's token, in the desk's job only; `pick` runs wharf's `ci-provider --pick` over the repos (lighthouse-ops S1); `sample` appends the desk's metrics row to the log dir's `ops.jsonl` — queue, run and check slots, load, memory, budgets, the token's standing (`token.plan`, `token.project`), token weeks (each reading's age, Orca's agents as report rows; a login here read over 30 minutes before is read again after the row by `account`'s probe, at most once a half hour, no tokens), cost — every 15 minutes on the ops host (`install.sh --schedule`), and `status` prints the last row, which helm's board shows as its ops row (S2); `ingest` appends every fleet repo's new issues and comments, and the configured Projects' items, to the log dir's `intake.jsonl` — a row an event, metadata and the body's hash, never a body — every 10 minutes on the ops host, a confidential scope's repos only on its own yard and nothing on a torn registry, and `intake` lists the open issues, a card each on helm's board (S4); `classify`, in the same job, takes each new open issue through four gate rows (`lighthouse.*`), the ladder and every cap of `lighthouse/ops.json` into the log dir's `ops-verdicts.jsonl`, laying nothing (S5: log-only), and `digest` counts the logged week (S5); after each sample the job files one logbook issue (label `budget`, through helm's `ask`, led by `helm/mention`) per account each time it crosses its week share or into its month reserve, closing it when the account is back under (the log dir's `ci-budget-alarms.json`), and picks `ops.json`'s `pick_repos` (ci-budgets, 2026-10-31) |
| `bin/hosts` | the fleet's hosts for the Engine room page (docs/fleet-page-2026-11-01.md, S2): `sample` builds this host's row — load, memory and headroom's verdict, its limits and slots, its live runs with their login, its stale peer records (what `dispatch-rc settle --stale` ends), its check slots and feature names (S4 of docs/engine-room-2026-11-02.md) — fenced (a torn registry drops every run; a run in a confidential scope is a count), and `--put` hands it to wharf-runs' `dispatch-queue hosts put` for `refs/regatta/hosts`, only when it changed; every claim starts it, and the queue's sweep after its claims with `--refresh`, which puts the row whatever it says. `hosts --json` merges every host's row with the fleet queue (the fleet store, a finish among it, no `confined` entry; a pin's kind, a held pin's why in fixed words and the waiting session's first 8 since S4) and the logins: the page's state |
| `bin/reef` | each host reefs its own sails: the queue's sweep hands `hosts`' row to `reef apply`, which moves this host's `wharf-runs/check-slots`, then its `wharf-runs/run-cap`, one step a turn and at most one change per host every 19 min, judged on at least 3 samples taken since the last change, through `regatta limit set`: down while their median load per core is above `wharf-runs/load-max` (or free memory or swapping crosses headroom's line), up while their median and newest are under 0.6× of it, at most one sample over that and none over it, with free memory over twice headroom's line — check slots while checks fill them, the run cap while every run slot is busy. A limit set by hand is the owner's word: reef records it and holds a cooldown. Within the owner's bounds, `lighthouse/reef` (`regatta limit set reef <host>:mode=on,run=1-3,check=1-3`; no line is advise, never a write); `reef plan` says what it would do, `reef log` what it did, and `reef seed` writes a host's first line from its own cap and slots (a new node's clone unit asks once; its first sweep seeds through `reef apply --seed`). CI runners on a host count in its load, so a host gives its room to CI before its runs |
| `hooks/account_guard.py` | refuses a prompt in a repo the session's login may not open |
| `hooks/secrets_guard.py` | closes the secrets folders, the coding CLIs' own logins and the live settings file to agents, and a confidential scope's paths to a session outside it (the fence) |
| `hooks/vendor_hook.py` | runs the Claude PreToolUse guards unchanged, at once, inside Codex's or Antigravity's own hooks (`<cli> guards`): their payload in, one answer out; and adds the CLI's `Co-Authored-By` to its commits |
| `bin/vendor-hooks` | `apply`, `check`, `homes`: that one named entry and a rules pointer in every Codex and Antigravity home this Mac has (`install.sh --vendor`) |
| `hooks/design_route.py` | a new design artifact is made on the primary login, and shared as it is made |
| `hooks/tool_path.py` | the package managers' bin dirs on every session's Bash PATH |
| `tests/check.sh` | every suite; scratch dirs only, no network |
| `tests/parity.sh` | each guard rule, a deny and an allow case, against Claude Code's, Codex's and Antigravity's payloads (`parity_rules.py`, the table): a rule a CLI cannot meet is a red row |

## Tenants

Work for several organisations from one Mac without mixing their seats. Name each organisation's
repos as a tenant in the registry and mark its login's row:

```json
{"accounts": [{"label": "acme", "home": "<its config dir>", "tenant": "acme"},
              {"label": "me", "home": "<your config dir>", "tenant": "me"}, …],
 "tenants": {"acme": {"repos": ["acme-*"]}, "me": {"repos": ["<your private vault>"]}}}
```

A tenant's repos then run on its own login, and only there. `account pick --repo` takes every
dispatched, picked-up or self-landing run there, and waits when that login has no room instead of
borrowing another seat. A session started by hand on any other login, the default one included, is
stopped at its first prompt by `account_guard`, which names the way in: that login's VS Code
profile (`account vscode acme`) or `cc <letter>`. `account doctor` checks that VS Code opens each
tenant folder, and each workspace holding one, in that profile. A tenant's login may still open
any repo no other tenant holds — so make your private repos a tenant of your own logins, as above,
and they are off an organisation's seat. Nothing bans a repo from a login: there is no deny list
(a row's old `"repos": {"deny": …}` is read by nothing since 2026-11-03, bar an entry naming a vault no tenant holds, which keeps
the vault off that row until one does, and `account doctor` names it), and which login takes free work first is the registry's order. An entry is a repo key or a
glob (`*` spans `/`).

To keep the list apart from the registry (in a private drive, say), write the tenants file
instead, naming each tenant's logins there; once written it is the whole of tenancy, and the
registry's `tenants` and rows' `tenant` are ignored:

```json
{"acme": {"repos": ["acme-*"], "logins": ["acme"]}}
```

`account tenant set acme --repos 'acme-*' --logins acme` writes one entry and `account tenant drop acme`
removes one: through the link, read back, the hooks' copy refreshed at once. They refuse a login already
in another tenant (each login is one tenant's), a repo another tenant holds, a label no claude, codex or antigravity row has, a
file that does not read (writing would drop the rest), and an unattended caller (`CLAUDE_UNATTENDED`).

A tenant's `logins` may also name a Codex row: `account pick --provider codex --repo` then routes the tenant's
repos to it, and refuses every other Codex row. That makes the row `owns` them, the core's vendor fence's yes for
the tenant's confidential and guarded repos, while every Codex road runs on `CODEX_HOME` (or the default Codex home), not on the
row pick names: `tenant set` refuses a Codex label whose home is not that one. Nothing guards a Codex session by hook, so for Codex tenancy
is routing only; a tenant with a Codex login and no Claude one leaves its Claude sessions nowhere to start:
`tenant set` refuses one, and `account doctor` names one written by hand.

An Antigravity row (`"provider": "antigravity"`, its home `$GEMINI_CLI_HOME`, else `~/.gemini`) routes the same
way: `account pick --provider antigravity --repo` answers the tenant's own and says it `owns` the repo. agy keeps
its login in the keychain and picks it itself, so the row sets no environment, is never probed (Orca's card in
`limits --all --orca` is its figure, and `limits --all` leaves the row out) and `tenant set` takes it only while
its home is the one an agy run here uses. That home binds no account, as a Codex home does: the row stands for
whichever agy login the Mac's keychain holds, so confine it (below) and sign in to that agy only where it is meant.

A routing login (Codex or Antigravity) can be confined to part of its tenant: `account tenant set owner --repos
… --logins … --confine agy-x='scope-*'` writes `"confined": {"agy-x": ["scope-*"]}`, and the row then owns
only those of the tenant's repos — the way to admit someone else's login to one scope of a tenant that also holds
your private repos. The label goes in `--confine` alone, never in `--logins`: every Mac reads the one tenants file
at its own lighthouse, and one older than the confine reads `logins` whole, while a label out of it is no tenant's
there and is refused the tenant's repos. It only narrows; a malformed value confines the row to nothing, and a
Claude row is never confined. A bare `--confine` drops every confine.

Your own private repos can be a tenant too: name your vault and its siblings, on your own logins, and
every other seat — an organisation's, one Orca holds that no row names — is refused them. The vault's tenant is the one tenancy also binds where a session starts *above* a repo: your
default config dir's `CLAUDE.md` imports from the vault, so a folder holding the vault's tenant's repos
(the projects folder, the home folder) is off every login but the tenant's, and a row refused the vault
links the work memory. `account doctor` lists each tenant, flags a row still carrying a deny list and a
`regatta/orca-deny` that names a repo (neither widens anything), and flags a vault no tenant holds.

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
`account_guard`, `design_route` — take the copies first (`.tenants.json.last`, `.logins.json.last`,
`.budgets.json.last`), and the link only once, to seed a missing copy (never the budgets file's: with no
copy its overrides wait for `refresh`); doctor, setup and `refresh --force` read the links themselves. A
plain file, or a link elsewhere, is read as it is, so an edit takes effect at once. `account refresh`
re-reads the links; plumb's usage tick runs it every 15 min through claude-host, so a change reaches the
hooks within 15 min. Where the budgets key is neither a file nor a link and the tenants key is a link, it
also links the budgets key to a `budgets.json` beside the tenants file's real target, so a new host needs no
hand-made link; doctor names a key it would link, and one whose link leads nowhere. Where the budgets
source is removed (the key gone, or its link's file gone from a folder that is there), refresh removes its copy,
so no stale cap stays in force; a drive away keeps it.

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
| `lighthouse/accounts.json` | the login registry: labels, config dirs, rules (a link): per row `week_max` (a live `lighthouse/week-max`, `<login>:<pct>` or `*:<pct>`, stands over it, a `*:` line only over a row that sets none: `regatta limit set week-max <login>:<pct> --all --why '…'`; a reserve still judges first, except on a row budgets.json tightens, where a tighter own line caps it), `window_max` (the flat 5-hour limit, less 10 points per exhaustion in 7 days), `pace_headroom` (default 10: a row over that limit still runs while its 5-hour spend is under the window's elapsed share and this many points are left), `free_below` (default 0, off: a 5-hour spend under it runs whatever the limit, margin or pace; the owner's rows are to set 70), `lend_max` (no key, no bar: the week bar for any repo outside the login's own scope or tenant, whose work keeps `week_max`; a key that is present but no number from 0 to 100, here or in budgets.json, lends nothing; the overdraw lifts a lent row last); `pace_headroom` and `free_below`, not a number, read as their default, `reserve`, `overdraw` (true or false: whether `pick --overdraw` may lift the row past its week ceiling when no row is under its own; absent, every row but the primary; any other value, never) | `account`, `account_guard`, `design_route` | `ACCOUNTS_FILE` | one login, the default config dir; where the overlay is installed, an error: `account` stops, the two guards block |
| `lighthouse/tenants.json` | the tenants: `{name: {repos, logins}}` (a link, kept off git) | `account`, `account_guard` | `TENANTS_FILE`; an `ACCOUNTS_FILE` other than the live key reads `<it>.tenants` | its last good copy, else the registry's own `tenants`, else none |
| `lighthouse/budgets.json` | the owner's per-login ceilings, over the registry row's rules: `{label: {week_max, window_max, free_below, lend_max}}` (`lend_max`: the week bar for any repo outside the login's own scope or tenant, whose work keeps `week_max`), each a number from 0 to 100; a key starting `_` is a comment (a link `account refresh` makes beside the tenants link's target, where one sits there; a plain `{}` keeps a host on the registry's rules, as refresh never replaces a file); a `week_max` that tightens the row also caps its `reserve` window where it is lower (the login's own live line, where one stands, in the budget's place), and a label no row has is named by doctor | `account`, `account_guard` | `ACCOUNT_BUDGETS`; an `ACCOUNTS_FILE` other than the live key reads `<it>.budgets` | the registry's own rules; torn, its last good copy, else those; a bad value is skipped, said on stderr |
| `lighthouse/week-max-finish` | a landing's week ceiling: `<login>:<pct>`, else `*:<pct>` (as `week-max`'s: only for a login that sets no week ceiling of its own, never a row kept out of the overdraw), above 0 and at most 100; changed live with `regatta limit set week-max-finish '<login>:97' --all --why '…'`. Only a launcher's `account pick --for finish` with its one-use pipe receipt may use it, and only where higher than the normal effective week ceiling (reserves and budgets included). A bare flag or environment word is still a build. The verdict names `finish ceiling`; cooldown, paid usage and 5-hour checks still apply, and the overdraw never lifts a row this ceiling judged | `account pick`, from wharf-runs' finish launchers | — | the normal week ceiling; unreadable or malformed, that ceiling stands with one stderr warning, never a fallback from a bad own line onto `*:`; any line that is no ceiling turns `*:` off for every login, good own lines standing (a `limit set` of a mistyped login's neighbour can hide a stray line in the config's copy) |
| `lighthouse/overdraw-max` | an overdraw's week ceiling: `<login>:<pct>`, else `*:<pct>`, above 0 and at most 100 (`regatta limit set overdraw-max '<login>:60' --all --why '…'`); read by `account`'s `lift()` in place of 100 for lifted rows alone (finishes keep `lighthouse/week-max-finish`, and an own live `lighthouse/week-max` or finish-ceiling row is still never lifted) | `account pick --overdraw` | — | 100; a value that does not read is no line (said once on stderr) |
| `lighthouse/logins.json` | the logins file: per label the e-mail, plan, payer, Macs; `share.design` (a link, kept off git) | `account setup`/`doctor`/`allowed`/`refresh`, `design_route` | `ACCOUNT_LOGINS` | setup and doctor refuse; no share line |
| `lighthouse/vault` | the owner's private vault, a repo key under the projects folder: a row refused it is an employer's; health commits the bulletin there | `account`, `health` | — | no employer rows, but where the overlay is installed `add` and `orca-sync` stop; the bulletin line posted, not committed |
| `lighthouse/user.json` | the declared settings (a link to a file in git) | `claude-settings` | `CLAUDE_SETTINGS_DECLARED` | no declaration: every verb a no-op |
| `lighthouse/env-keys.json` | the install's own declarable `env` names: `{name: [values]}` | `claude-settings` | — | only CLAUDE_CODE_SUBAGENT_MODEL |
| `lighthouse/hosts` | the Macs' host names, one per line, for a declaration's `hosts` sections | `claude-settings` | `CLAUDE_SETTINGS_HOST` (this host) | any lowercase name |
| `lighthouse/vaults` | the shared drives whose `_secrets`/`_contacts` are closed, by name, for a path behind a variable | `secrets_guard` | `SECRETS_GUARD_DIR` (the folder; `SECRETS_GUARD_SCRATCH_ROOT`, the fence's scratch root, in tests) | the mounted shared drives that hold one |
| `lighthouse/guarded-dirs` | absolute local folders closed to agents like `_secrets`, one per line (`~` the home folder; a relative line is dropped), on every platform, Drive or none: the desk's token dir first | `secrets_guard`; `ops usage` warns when the token dir is not listed | — | none guarded |
| `lighthouse/secrets/ops.env` | the owner's token for the billing read (`GITHUB_TOKEN`, `CIRCLECI_TOKEN`; `GITHUB_TOKEN` also reads each picked repo's fork-PR setting and runner list, admins' reads, passed to ci-provider as `WHARF_READ_TOKEN`): on the ops host only, its dir 0700 and the file 0600, neither a link, written by the owner over ssh | `ops`, in the desk's own job only (`LIGHTHOUSE_DESK=1`, no session); wharf's `ci-provider --pick`, as `WHARF_READ_TOKEN`, for those two reads | — | every account `absent`: the pick holds every hosted lane of a private repo over budget, and refuses the self-hosted lane where the gh login is no admin |
| `lighthouse/ci-lanes.json` | the runner lanes: `{"lanes": [{name, provider, runs_on, runs, account}]}`; a CircleCI lane also takes `projects`, `{"<owner>/<repo>": "<project slug>"}`, the project of that org the Linux share moves to; a hosted Actions lane may take `projects` too, `{"<owner>/<repo>": "actions"}`: the share then runs on GitHub's hosted runners, judged by the lane's minutes (a self-hosted Linux lane may take it as well, its `runs` and `runs_on` naming linux and never macOS, judged by its runner: wharf's ci-provider, The pick), and the CircleCI lanes are never chosen for that repo | wharf's `ci-provider --pick` | — | `--pick` refuses, naming the file |
| `lighthouse/ci-budgets.json` | per account a month cap (`month_minutes` or `month_credits`), `week_share`, `reserve` (default 0.2), `margin`; `user`, `org` or `org_slug` to read it by | `ops usage`, `ops sample`'s budget alarms, `ci-provider --pick` (a CircleCI lane's account also switches the Linux share, `CI_LINUX_ELSEWHERE`, and with several such lanes moves it, `CI_LINUX_TARGET`) | — | every hosted lane of a private repo over budget, the Linux share off, no alarm |
| `lighthouse/ci-queue-max` | a self-hosted lane's queued-seconds p50 the pick still sends work to | `ci-provider --pick` | — | 600 |
| `lighthouse/ops-host` | the one host the desk runs on and the pick writes from | `ci-provider --pick --apply`, `ops sample`, `ops ingest`, `ops is-host`, `install.sh --schedule` | — | the desk is off: `--apply`, `sample`, `ingest` and `--schedule` refuse |
| `lighthouse/ops-projects` | the GitHub Projects the intake reads, one a line: `user/<login>/<number>` or `org/<login>/<number>`; read with the desk's token (`GITHUB_TOKEN`), which needs the Projects read `token.project` probes | `ops ingest` | — | no Project read; the repos' issues still are |
| `lighthouse/ops.json` | the desk's sense (S5): `dry` (true), the caps `max_auto_runs_day` (3), `max_auto_runs_repo_day` (1), `max_open_auto_prs` (3), `week_share` (0.1, the desk's share of the week's list spend), `importance_auto_max` (3), `cost_auto` (`["xs", "s"]`), `labels` (`["bug"]`), `repos` (registry keys, `"*"` all; default none), `pick_repos` (registry keys the 15-minute job picks; default none) and `pick_apply` (false: the job's pick reports only); an unknown key refuses the file | `ops classify`, `ops digest`, `ops sample` | — | the desk is off: `classify` writes nothing |
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
`regatta/projects`, `regatta/log-dir` (where the fence
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
PreToolUse hooks. `bin/vendor-hooks apply` (or `install.sh --vendor`) writes one
entry into each Codex home's `hooks.json` (`$CODEX_HOME`, `~/.codex`, each Codex row of the account registry),
named `regatta guards: secrets, checkpoint, trailer` by its `statusMessage` (what Codex's /hooks lists), and our
`regatta` key into Antigravity's `config/hooks.json`, whose key is its name; `hooks/vendor_hook.py <cli> guards`
translates the payload, runs each guard as it is, both at once, and answers once, the first deny in their order, in the
CLI's own shape. A home holding the older one-entry-per-guard shape is merged in place; `check` calls it stale. Beside them a rules pointer —
`<codex home>/AGENTS.md`, `~/.gemini/GEMINI.md` — names, never copies, what a Claude session of the same tenant
loads that may leave for another vendor: its seat's `rules/`, the `@` files every seat's CLAUDE.md loads (or the
config key `lighthouse/vendor-layer`), and the bulletin; never a file only one seat loads, never the CLAUDE.md. Codex runs a hook only once it is
reviewed (`codex` → /hooks, once per Mac for the one entry); `vendor-hooks check` (and `install.sh --check`) counts the entries waiting for it.
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
