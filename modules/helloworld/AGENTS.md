# modules/helloworld — the public door

Read `README.md` first: it is the chart. For an agent:

- `helloworld check <repo>` is the agent's verb and never pushes; `publish --pr` pushes a
  `claude/publish/*` branch and opens a PR, and the owner's merge is the publish; plain `publish`
  is the owner's alone, in their own terminal (it refuses `CLAUDECODE` and a non-terminal stdin).
- Every scan pattern has a planted case in `tests/helloworld.sh`; a pattern without one is not a
  pattern. Planted words are made up: never a real name, house, machine or account, not even in a
  test (this module is public).
- A hard push on a public repo owes a post-mortem and a failing-then-passing case here
  (README, "Post-mortem").
- The core is found by `lib/find_core.py`; a peer (wharf's pre-push guard) through
  `common.module_path()`, never a path beside this file.
- check: `bash modules/helloworld/tests/check.sh`.
