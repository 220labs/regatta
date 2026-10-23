# TODO — what a fresh session must pick up

Managed by `/todo`. Short by design: 5 is comfortable, 10 is the cap. Done items are
deleted, not ticked. Learnings never live here.

1. **Fill in `AGENTS.md`** — the one-paragraph description, the `check` command and the
   session contract. Until `check` exists, no session can prove its work. With the check in
   (here and in `.github/workflows/check.yml`), set `"autofinish": "all"` in
   `.claude/workflow.json` and the contract's autofinish line to match; that file is in its own
   `autofinish_exclude`, so the branch lands by `/finish`.
