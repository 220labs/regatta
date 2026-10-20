---
name: routine
description: Sync a scheduled cloud routine (the morning inbox pass and any other) with its prompt file in the vault's routines/. Pulls the routine's own self-edits into git, deploys a session's edit of the file, and proves which one happened. Use whenever a change touches something a routine's prompt names (a path, a step, a skill), or to check for drift.
argument-hint: "[<name>]   (default: every file in the vault's routines/)"
---

Keep the live routine and `routines/<name>.md` in the vault identical. Neither side is the
master, because both have an author: sessions edit the file, and the routine rewrites its own
prompt when its owner corrects it in its chat. atlas's `routine` decides which side moved since
the last sync.

The tools, from this skill's base directory, each passed as one path (never through `cd`, so a
skill linked in by hand still reaches its module): `../../bin/routine` and
`../../bin/knowledge-commit`. Below, `routine` and `knowledge-commit` mean those paths. The vault
is `knowledge-commit vault`; its checkout is the second line of `atlas/vault` in the regatta
config dir (`$REGATTA_CONFIG`, else `.config/regatta` in the home folder).

For each definition file (`$ARGUMENTS` names one; default: all of them):

1. `RemoteTrigger get` with the `id` from the file's header. Save the whole response, with its
   `HTTP 200` line, to a scratch file `<name>.live.json`. It runs to about 180 KB.
2. `routine status <file> --live <name>.live.json`:
   - **0, in sync**: nothing to do.
   `routines/` is gated in the vault (not in its `in_place`): every change to a file lands
   through `knowledge-commit vault --open routine-<name>` and `--in <that path> -m …`.
   - **4, live ahead** (the routine edited itself): `routine pull` on the file **under the
     `--open` path**, then `--in` with `-m "Routine <name>: pull the routine's own edit — <what
     changed>"`. It is refused unreviewed; the reviewer reads what the routine did to itself,
     which is already live, then `--in --review` lands it.
   - **3, file ahead** (a session edited the file): land the edit reviewed first (`--open`,
     edit there, `--in`, review, `--in --review`), then deploy what landed, from the primary:
     1. Send `RemoteTrigger update` with the body from `routine body <the vault>/routines/<name>.md`,
        which is the whole of it: `{"prompt": …}`. Never send `job_config` or `session_request`.
        They hold the Cowork system prompt and the connectors, and an update replaces a whole field.
     2. Run `get` again, save it, then `--open routine-<name>-synced` and run `routine synced
        <the file under that path> --live …`. This checks the deploy against what the service
        now holds.
     3. `--in` that path: a diff that only moves the `synced:` line lands without a review.
   - **5, both changed**: show the owner the diff and ask which parts to keep. Never force either way.
3. If `status` reports a changed name or cron, the file records it but can't change it. Say so
   and name the setting in the Claude app.

Before any deploy, save a copy of the full `get` response in
`.local/state/routines/backup/<id>-<date>.json` in the home folder.

**Permission.** A `RemoteTrigger update` that writes a prompt is refused by Claude Code's auto-mode
classifier ("instruction poisoning", 2026-09-23). That's deliberate: a session that rewrites a
scheduled agent's instructions is the attack it guards against. Don't retry the call and don't
route around it. Stop and tell the owner the deploy is ready and waiting for their approval.
