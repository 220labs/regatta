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
  | `regatta/guarded` | the repos whose data goes to a model vendor only on the owner's quote (`jev.GUARDED`, the gate reads it) | none guarded |
  | `regatta/orca-deny` | the repos an Orca login no registry row names may never open (`common.ORCA_ROW`) | none denied |
  | `regatta/log-dir` | where `jev.jsonl` and `gate.jsonl` go; a leading `~` is the home folder of the moment | `.local/state/regatta` in the home folder |
  | `regatta/projects` | the projects folder `secrets` reads repo names under, `~` as above | `projects` in the home folder |
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

## Check

`bash modules/regatta/tests/check.sh` — scratch paths only.
