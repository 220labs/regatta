# modules/wharf — one session, one worktree

Read `README.md` first: it is the chart. For an agent:

- `hooks/checkpoint.py` is live in every session the moment the file a settings file names
  changes: run `tests/test_checkpoint.sh` before saving it. It is a deny hook (C4): with no core it
  refuses writes and pushes, never exits 1 (read as allow) or 2 (on UserPromptSubmit that erases
  the prompt).
- The core is found by `lib/core_path.py`; every peer through `common.tool()`, with the fallback
  the README names on None — never a path beside a file, never a stack trace.
- `pr` stays in `libexec/`: a `bin/` name must be free on a stock PATH (C1); `tests/check.sh`
  checks every `bin/` name.
- `bin/ci-provider` writes live state (main's protection, runners, repository variables): its
  suite stubs `gh` and `ssh`, and pins every runner key in a scratch `REGATTA_CONFIG`, whatever the
  caller's; never run `--protect`, `--runner install|remove` or a variable write against a real
  repo from a session without the owner's say-so. It lands by `/finish` only (`autofinish_exclude`).
  The self-hosted kind's name is a config key (`wharf/ci-runner-kind`, default `self-hosted`): the
  owner's repos' ci.json carry the first runner Mac's name, which the overlay writes there (renaming it would be a
  data migration across repos).
- No hooks/hooks.json until the plugin install is decided (the design's D3-B): the same handler
  wired by a settings file and by the plugin runs twice.
- Public since its scrub (2026-10-22): every file is on the allowlist, so new text names no real
  host, login, account, person or overlay path, not even in a test (fixtures: hosts `laptop` and
  `buildbox`, people `sam` and `alex`, `example.invalid`); a value the code needs is a `wharf/`
  key (README, "Private values"). A new file joins `.helloworld/allowlist.txt` in the change
  that adds it.
- check: `bash modules/wharf/tests/check.sh` (about 7 minutes: 423 s on a laptop, 2026-10-21; `test_checkpoint` is
  most of it, `test_ci_provider` about 2 of them).
