# atlas — knowledge with three lifecycles

What a team of agent sessions learns, kept where it survives: a learning for this week (the
bulletin), a learning for good (promotion into the rules), and the record of the work itself (the
vault commit, the docs map of charts and records, routines kept in git). Aurora, the weekly
loop that consolidates all three, is a module of its own and builds on this one.

| Piece | What it does |
| --- | --- |
| `hooks/bulletin.py` | the bulletin: dated, expiring one-liners every session sees once (`--post`, `--list`, `--prune`; as a hook on SessionStart and UserPromptSubmit) |
| `skills/share` (`/share`) | posts one learning to the bulletin, with why it matters |
| `skills/promote` (`/promote`) | moves one learning into the layer's rules or lessons, or the owner's profile in the vault: searched, drafted, shown, landed reviewed |
| `hooks/vault_commit.py` | SessionEnd: commits the vault's records and pushes its main |
| `hooks/archive_transcript.py` | SessionEnd: copies the session's transcript out of Claude Code's 30-day sweep |
| `bin/knowledge-commit` | the one door from any session into the two knowledge repos: records in place, everything else through a reviewed branch |
| `bin/docs-index` | the docs map: charts say what is, records say why (`check`, `banner`, `move`, `relink`, `due`, `reads`) |
| `bin/knowledge-home` | where a repo's auto-memory lives by the registry: a confidential scope's in its knowledge repo, the rest in the vault (`where`, `adopt`, `init`, `check`) |
| `bin/routine` + `skills/routine` (`/routine`) | a scheduled cloud routine's prompt kept in git, in step with the live routine |
| `bin/skill-frontmatter` | does each skill's and agent's frontmatter parse |
| `tests/check.sh` | the module's check; no network |

Install: `claude plugin marketplace add <this repo>`, then `claude plugin install atlas@regatta`
(it needs the core, `regatta`). From a clone: `sh modules/atlas/install.sh --check` says what is
found. The plugin ships no `hooks.json` yet: the hooks are wired by whoever installs the shell
face (on the owner's Macs, the overlay's `bootstrap.sh --hooks`), so a Mac that has both never
runs one twice.

## The two knowledge repos

- **The layer**: what every session loads — `rules/`, `lessons/`, skills, agents. It lands
  through reviewed pull requests.
- **The vault**: the records written in place on its main — the bulletin, auto-memory, inbox
  notes, dreams, `log.md` — and the owner's profile in `me/`, which lands reviewed.

Each is one file in the regatta config dir (`$REGATTA_CONFIG`, else `.config/regatta` in the home
folder): `atlas/layer` and `atlas/vault`, the name callers pass to `knowledge-commit` on the first
line, the primary checkout on the second. `knowledge-commit` also takes the role words `layer`
and `vault`. `ATLAS_LAYER` and `ATLAS_VAULT` override the paths for a test suite or one shell, and so does the variable a key names on an optional third line (an installer whose scripts already use one).
Where an overlay is installed (a `legacy` file in the config dir), a missing key is refused,
never guessed; without one, the vault defaults to `atlas` in the XDG data folder.

## A scope's knowledge repo

A scope in the registry flagged `"confidential": true` is a node nothing outside it reads: its
repos' auto-memory lives in the scope's knowledge repo — its anchor, the scope's first repo,
`<scope>-knowledge` by convention — at `memory/<repo>/`, and the scope's docs in that repo's
`docs/`. `knowledge-home init <scope>` gives a new knowledge repo `memory/`, a `docs/` map,
`memory/` in `in_place` and the worktrees ignored (an existing one: it names what is missing, for
a branch to add); `adopt <repo>` moves a repo's memory into its
home and links each login dir's `projects/<slug>/memory` to it; `check` fails where a confidential
repo's memory sits outside its node. Every other repo's home is the vault's `memory/<repo>/`.
It fails closed: a repo in a confidential scope and an open one is confidential, and a registry
that does not read, or a confidential scope with no anchor, is refused — never sent to the vault.
The scope readers are the core's (`common.scope_registry`, `scope_members`); this module never
reads the registry file itself.

## Optional peers

Found through the core's one lookup, `common.tool()`; each is a fallback when absent, never an error.

| Edge | With the peer | Without it |
| --- | --- | --- |
| G19 — `keel` for the bulletin's Open line | `📂 Open: …` once per session | no Open line |
| G19 — `keel` for `docs-index`'s nested sets | a set is one record row | every record needs its own row |
| G20 — wharf's `pr` and `carried.py` for `knowledge-commit --in` | pushed, PR readied and merged, the primary fast-forwarded | landed on the primary's main locally, said so |
