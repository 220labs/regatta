# Changelog — sextant

## Unreleased

- New agent: `agents/sounder.md` (the Sounding's S1) — the architects' method on an idea outside any
  repo; its body is the architects' shared one, byte for byte (wharf's `tests/test_agents.sh`), so it
  stays off the allowlist until that body is scrubbed.
- New verb: `sparks related "<words>"` — the ideas pool grepped for a brief's words, dropped notes
  and friends' notes included, the `sparks` peer's `off` honoured (the Sounding's S3, carried from
  the overlay, 2026-10-21).
- Carried from the overlay (the wharf rename's S5, 2026-10-20): the launch word in `sparks` and
  `tests/sparks.sh` — `launch_git`, `CFG["launch"]` (the config's `land` key and `SPARKS_LAND` still
  read), a note that "goes to" the inbox rather than lands there.
- Sparks: a routed config with `"written": true` takes written notes from its inbox too — shaped
  by its own prompt, routed and filed like a recording, with the config's `"source"` on the note
  and `"notify"`'s `filed` text. Without the key a routed inbox stays audio-only, as before.

## 0.1.0 — 2026-10-19

- First cut: Sparks, the ideas intake, moved in from the overlay's `bin/sparks`, `bin/redactions`,
  `test_sparks.sh` (now `tests/sparks.sh`) and `bench/redaction/`. Verbs unchanged. The private
  defaults moved to the config dir: the config (`sextant/sparks.json`, `$SPARKS_CONFIG` still
  wins), the log path (`sextant/log`), the guarded source for redaction (`sextant/source`); the
  repos registry through the core's `repos_json()` (`SPARKS_REPOS` still wins), the projects
  folder from the core. `knowledge-commit` and `publish` are optional peers through
  `common.tool()`, each with a one-line fallback. New: `launcher.c.in` and `install.sh`
  (`--launcher`, `--check`, `--remove`) for a stranger's Mac.
