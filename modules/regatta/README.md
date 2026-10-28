# regatta — the core

What every Regatta module builds on. Install it first; every other module lists it as a
dependency by bare name.

| Piece | What it does |
| --- | --- |
| `hooks/common.py` | the shared library: host name, the GitHub client on the token git already holds, the worktree lock, the fixed closing lines and their readers, the money formatter, and discovery (below) |
| `bin/gate` | which provider and model each call site uses, read from one table (`show`, `set`, `check`) |
| `bin/jev` | the client for TypeSafe's Jev, the gate's classifier |
| `bin/cost` | a model cost as list and effective, `$1.33 ($0.02 effective)`; `cost lint <doc>` |
| `bin/secrets` | each repo's `.env` against its `.env.example`, in a shared folder |
| `bin/regatta` | `root`, `has <module>`, `which <tool>`, `check`, `shim <path>`, and `regatta <name>` for a tool kept off PATH |
| `libexec/flare`, `/regatta:flare` | a bug report, an idea or a question, filed as an issue on Regatta's public repo with the evidence attached (below) |
| `libexec/attribution` | `regatta attribution add\|list`: count a session, or the sessions under a folder, to a project in every report of time or cost (below) |

## Install

From a clone (the shell face):

```bash
sh modules/regatta/install.sh            # writes ~/.config/regatta/home naming this clone
sh modules/regatta/install.sh --check    # regatta check: the config dir, each link and its target
```

As a plugin (the session face): `claude plugin marketplace add <this repo>`, then
`claude plugin install regatta@regatta`.

## Where things are found

- **The core**, from a file that moved out of an older checkout: `$REGATTA_HOME`, else the one
  line in `${REGATTA_CONFIG:-~/.config/regatta}/home`. A file, not the environment: hooks,
  launchd jobs and launchers that whitelist their child's environment never see a variable a
  shell exported.
- **A peer**, by `common.tool(name)` (and `regatta which` / `regatta has` in a shell): the
  checkout above the loaded core, `modules/*/{bin,libexec,hooks}/<name>`; else, from a plugin
  cache, the `installPath` of each `<plugin>@regatta` row in `installed_plugins.json` (user
  scope, and project scope when the cwd is inside it); else None — and the caller takes the
  fallback its README names, never a stack trace. (An overlay's checkout was a third place until
  the shims there went, 2026-10-23.)
- **An overlay**: `common.overlay_installed()` — the config dir's `regatta/overlay` marker, whose
  line `common.overlay_root()` reads: the overlay's checkout, for its own files and the few
  scripts a launcher of its starts, never a module's tool. Where it is true, a key the overlay
  owes and did not write is refused, never read as absent.
- **Private config**: every file keeps its environment override (for a test suite or one shell,
  never exported), and its default is `${REGATTA_CONFIG}/<module>/<file>`. For the core:
  `regatta/models.json` (the gate's table; the defaults beside the gate otherwise),
  `regatta/cost-ratio.json`, `regatta/.env` and `regatta/.env.fallback` (Jev's key; the second read
  only where no first exists), `regatta/laptop` (the host that types every cross-machine leg),
  `regatta/secrets` (the shared `.env` folder), `wharf/repos.json` (the registry, read by
  `common.repos_json()`, `CLAUDE_REPOS_JSON` over it).
- **Private values**: one plain file each, one item per line (blank lines and a UTF-8 BOM
  ignored), read once when the core loads; `common.config_read` is the one reader. Whoever
  installs the modules writes them (on the owner's Macs, the overlay's `bootstrap.sh --config`).
  With an overlay installed (its `regatta/overlay` marker in the config dir), a key it left out is an
  ImportError naming each — the core fails closed rather than send a guarded source unrefused —
  and an empty file is a deliberate empty value. Without one, an absent file is the neutral
  default below. With or without an overlay, a key that exists but cannot be read (any error but
  "no such file", or not UTF-8), and a path value that is not absolute after `~`, are the same
  ImportError. `regatta check` lists each problem.

  | File | What it holds | Without it |
  | --- | --- | --- |
  | `regatta/owner` | the owner's name: the closing lines address it (upper-cased, then `, `), the gate and Jev ask for its say-so, `/autofinish`'s marker carries it lower-cased as `by` | the lines open on their first word; "the owner's say-so"; `by` is `owner` |
  | `regatta/guarded` | the repos whose data goes to a model vendor only on the owner's quote (`jev.GUARDED`, the gate reads it); every repo of a confidential scope is guarded the same way for every vendor but Anthropic (`jev.confidential`) | none guarded |
  | `regatta/orca-deny` | the repos an Orca login no registry row names may never open (`common.ORCA_ROW`) | none denied |
  | `regatta/log-dir` | where `jev.jsonl` and `gate.jsonl` go, and `sheep/`: the account's spacesheep plan as last read (`plan.json`, an hour) and this Mac's 24-hour deploy log keel and helm share (`deploys.jsonl`); a leading `~` is the home folder of the moment | `.local/state/regatta` in the home folder |
  | `regatta/projects` | the projects folder `secrets` reads repo names under, `~` as above | `projects` in the home folder |
  | `regatta/attribution` | where the attribution file is (an absolute path, `~` as above); written empty it turns attribution off (below). Optional even with an overlay, and read only when a report asks: a relative or unreadable value turns attribution off with one stderr line, never an ImportError | `.local/state/regatta/attribution.jsonl` in the home folder, whatever `regatta/log-dir` says |
  | `sheep/machines` | how many machines publish from the spacesheep account: each Mac's part of the 24-hour publish cap is the cap divided by it (`common.sheep_budget`; read when used, never an ImportError) | the hosts `lighthouse/hosts` lists, else 1 |
- **A module's own private values** are listed in its `config-keys` file (one key per line, `#`
  comments); `regatta check` reports each one that is unreadable, or missing where an overlay is
  installed. The core's import never refuses on them: the module refuses when it uses one.
- `gate set` writes the real file behind a config symlink, and refuses one on a `main` checkout.

## Shims

A file that moved keeps a shim at its old path, made by `regatta shim <path>` and never edited:
a Python file gets a **source shim** (the module's source run in the shim's own module with
`__file__` set to the module's path — `import`, `load_module`, `exec_module` and a run as a
script behave as the file itself), any other file an **exec shim**. With the core absent a
shim fails in one line: `ImportError: regatta: core not found: …`.

## Flare: report a bug

In a session, `/regatta:flare <what went wrong>`: the agent writes the report, attaches the failing
output, shows you the issue, and sends it on your yes. From a shell:

```bash
regatta flare --dry-run "keel line prints nothing for a doc without D-items" --client-id keel-line-001 --tag keel --attach out.log
regatta flare "keel line prints nothing for a doc without D-items" --client-id keel-line-001 --tag keel --attach out.log --json
```

It files through `gh` as you; signed out, it prints a prefilled new-issue link instead. The same
`--client-id` again returns the first issue, never a second. The issue is public, so the text meets
helloworld's file scan first (machine and home paths, addresses, credential shapes, a private word
list where there is one) and a finding stops it, exit 3; an unattended run only dry-runs. `regatta/flare-repo` in the config dir sends flares to
another repo, a fork's own. Without Claude Code: the repo's Bug and Idea forms on GitHub.

## Attribution: whose time and money was it

A session in one repo that did work for another project (a lean repo chosen because the other's
context is heavy) is counted to the other in every report of time or cost by project. One file of JSON
lines, `~/.local/state/regatta/attribution.jsonl` (`regatta/attribution` moves it; written empty it
turns attribution off), appended to and never rewritten. The file is the Mac's own: a report counts the
rows of the Mac it runs on, so add a row where the weekly report runs, or point both Macs' key at one
plain file:

```json
{"ts": "2026-10-27T12:00:00Z", "project": "proj-b", "session": "<sessionId>", "why": "…"}
{"ts": "2026-10-27T12:00:00Z", "project": "proj-b", "path": "proj-a/.claude/worktrees/topic", "why": "…"}
```

`project` is a folder under the projects folder, as a report names it. `path` is a glob relative to the
projects folder, a worktree's `.claude/worktrees/<topic>` part kept; it matches that folder and every
folder under it. Per (session, folder) a `session` row wins, else a `path` row, else nothing: the
reader keeps its own project. Among rows of one kind the newest `ts` wins; a row without a readable
`ts` is the oldest. The rows name sessions, so the file is private state: never published.

```bash
regatta attribution add proj-b                                      # this session ($CLAUDE_CODE_SESSION_ID)
regatta attribution add proj-b --path 'proj-a/.claude/worktrees/topic' --why 'lean repo, proj-b work'
regatta attribution list
```

`add` exits 2, with one line, for a PROJECT that is no folder holding `.git` under the projects folder,
for a `--path` given as an absolute, `~` or `./` path outside it (stored relative when inside), for no
session to attribute, and when attribution is off. A `path` row has no time bound: it also counts a
later session in that folder.

A reader asks `common.attribution(session, cwd, root=None)`: the project, or `None`. It reads the
file once per process; a line that is no row is skipped with one warning on stderr. `crew-report`'s
weekly report uses it; a new reader of per-project time or cost goes through it, never its own copy.

## Check

`bash modules/regatta/tests/check.sh` — scratch paths only; it runs `tests/flare.sh` and
`tests/attribution.sh` too (a stand-in `gh`, nothing reaches GitHub).
