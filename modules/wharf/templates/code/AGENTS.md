# {{PROJECT}}

<!-- Instructions for any coding agent working in this repo (AGENTS.md is the cross-tool
standard; CLAUDE.md imports this file). Keep it under 200 lines: only what an agent would
get wrong without it. How sessions run, git workflow and verification habits are NOT
repeated here — they load from the shared rules folder in every session. -->

{{ONE_PARAGRAPH: what this project is, for whom, and what "working" means.}}

## Session contract

<!-- Read by /finish, /evacuate and /todo. Fill in every line; "none" is a valid answer. -->

- check: `{{COMMAND}}` — the read-only command every session must see pass before calling
  work done. Safe at any hour; touches nothing live.
- live: none — git is the only state. <!-- or: what runs deployed code, and the drift command -->
- physical: none <!-- or: a heavier sweep that acts on the real world; the owner runs it -->
- learnings: project rules and traps → this file; long-form reasoning → `docs/`;
  anything true beyond this project → `/promote`.
- open-items: `TODO.md`

## Commands

```bash
{{COMMAND}}          # the check
```

## Layout

{{Only what an agent can't infer from the tree.}}

## Traps

<!-- Things that fail silently here. Each: the symptom, the cause, the check. Add one the
first time a session loses time to it. -->
