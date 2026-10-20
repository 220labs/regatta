---
name: share
description: Post a short-lived learning to the bulletin so every other session on this machine — running now or started this week, in any project — sees it once, labeled with why it matters and when it expires. For things worth knowing this week, not rules (/promote) and not project state (/todo).
when_to_use: On your own only for a fact another live session would otherwise learn the hard way this week — a live system you now own, a file moved under everyone, a restart window, a tool that fails in a way others will meet. Never a summary of your own work, never from a subagent (its prompt is the parent's, not the owner's).
effort: medium
argument-hint: <why it matters> — <the learning>
allowed-tools: Bash(python3 */hooks/bulletin.py *)
---

Post to the bulletin (`bulletin.md` in the vault, written by atlas's `hooks/bulletin.py`):
$ARGUMENTS

The script is `../../hooks/bulletin.py` from this skill's base directory; pass it to `python3`
as one path (`<base directory>/../../hooks/bulletin.py`), never through `cd`, so a skill linked in
by hand still reaches its module.

The bulletin is for a fact another session would want *this week* and would otherwise learn
the hard way: "main's `CLAUDE.md` moved under everyone at 33b3387 — take main's copy before
editing"; "the home server restarts until ~15:10, drift checks will lie until then"; "the
`websockets` package is now in `requirements.txt`". It is not for rules (permanent —
`/promote`), not for open items (`/todo`), not for anything a doc already says, and not for
a message to one specific live session (Claude Code's own `@session` messaging does that).

1. Split the argument at ` — ` into *why* and *text*. No ` — `? Typed by the owner: ask for the
   why in one line. Called by a session itself (the owner, 2026-10-16: the skills we install have
   all their features on): write the why yourself from what you know — never stop to ask for it.
   An entry without a reason is noise to every other session.
2. One line each, plain words, no markdown, no ` · ` (the field separator). Default
   lifetime 7 days; `--days N` when the fact expires sooner (a restart window: `--days 0`
   lasts until midnight).
3. Post:
   ```bash
   python3 <base directory>/../../hooks/bulletin.py --post "<why>" "<text>" [--days N]
   ```
   A refusal naming `atlas/vault` means no vault is configured on this machine: say so, post nothing.
4. Show the stored line back. More than ten live entries (`--list`)? Say so — it is meant to
   be short — and run `--prune`.

Every session sees a new entry at its next prompt (or at start), once. The vault commits the
file at session end. Aurora's weekly dream prunes expired entries and asks whether any deserves
promotion to a rule.
