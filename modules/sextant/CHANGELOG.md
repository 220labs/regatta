# Changelog — sextant

## Unreleased

- New tool: `bin/soundings` (the Sounding's S7) — the queue of proposals the owner chose to have
  sounded: `add` (the owner's pick, refused to an unattended run; `--now` records a launch now),
  `next` (three gates, three a week, five open, the `reset` / `reset+30` / `reset+60` stagger and the
  commands), `brief`, `mark`, `refresh`, `list`. The queue is `soundings.json` beside the ideas pool.
- `/sounding --yolo` and the sounder's `Reversible:` paragraph say what `keel yolo` takes since
  skipper modes: every bare pick, `no` and unmarked included, stopping only at no pick, a conditional
  or a reopened item (the skipper-modes landing review, 2026-10-22).
- New skill: `/sounding` (the Sounding's S4) — the head by scope (`architect`, `sr-architect`,
  `sounder`), the stance (`firm:` or sounded), the two peers' lines in the brief, the lint and
  `reviewer-high` before the owner sees the doc, and three paths: full (`keel line`), `--light`
  (`keel light`'s questionnaire, also unasked when its check passes) and `--yolo` (`keel yolo`).
  Public: it quotes none of the shared body.
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
