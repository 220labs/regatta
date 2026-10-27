# Changelog — sextant

## Unreleased

- New tool: `bin/pitch` (renders S1) — `check <root|doc> [--json]` holds a document's renders to
  the method (the captain page, the admiral deck, every folder and single-file deck; 29 rule ids,
  exit 1 on a finding, 2 when it could not run), `build <deck|doc> [--check]` writes an admiral deck from its `slides.json`,
  refusing the whole deck when a slide breaks a rule. Its rules, checker and builder are
  `bin/pitchlib.py`, stdlib Python 3.9; its config `pitch.json`, found at or above the root,
  `extends` kept. `tests/pitch.sh` builds one failing root per rule at run time and runs 170 cases.
- The host rule is the core's (2026-10-24): `sextant-run run` asks `common.weekly_host("sextant")`,
  so its skip line says `sextant`, as weekly-run's does, where it said `/sextant`; `install.sh
  --schedule` asks `regatta weekly-host sextant` (the core found through `lib/find_core.py`) before the
  runner's dry run, which still has to plan a run. A real run's refusal (the rule's, no folder, no claude) posts one bulletin line
  through atlas, as weekly-run's does; atlas absent, the log line alone says it. A core older than
  the rule, or one that crashes in it, is such a refusal, never a traceback; `--schedule` refuses a
  folder that does not exist, as the dry run did.
- `sextant-run run` (2026-10-24): runs only on the host `aurora/host` names, weekly-run's host rule
  (`host_rule`), skipping elsewhere with a line; the deprecated `aurora/skip-hosts` keeps its old
  meaning while `aurora/host` is absent, with a line saying so; neither beside an overlay, or an
  empty, unreadable or many-line `aurora/host`, refuses (exit 1). `install.sh --schedule` refuses on
  a skip or that refusal, quoting it, and when the runner's dry run could not tell. A new
  `config-keys` lists `aurora/host`, so `regatta check` asks for it with aurora absent too.
- New skill: `/sextant` (B13), moved in from the overlay and scrubbed as it moved — no owner,
  host or folder: its paths come from `libexec/sextant-run where`, every peer runs as `<regatta>
  <tool> …`. Step 2c's calls (`soundings`, `pickup seed`, `dispatch`) go through the core's CLI.
- New tool: `libexec/sextant-run` (B13) — `where`, the skill's placeholders, and `run`, the weekly
  job's own runner when aurora is absent (G29): claude with the queue's reading verbs, every writer
  that starts work denied, capped at three hours.
- `install.sh --plist`, `--schedule [--dry-run]`, `--unschedule` (B13, G29): the weekly `/sextant`
  job — aurora's `weekly-run sextant` when it is installed, else the own runner; behind wharf-runs'
  launcher when it answers for the program. `--check` names the runner and the launch's peers.
- `soundings next` (G27): with `pickup`, `dispatch` or `keel` not installed, or SOUNDINGS_BY_HAND
  set, one `by hand` line per candidate — the `/sounding` the owner would type and its `mark …
  launched` — instead of commands.
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
