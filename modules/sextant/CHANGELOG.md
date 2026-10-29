# Changelog — sextant

## Unreleased

- `pitch` (renders S6): the commodore, the deck that is sent and read alone, built from the same
  ```` ```deck ```` fence as the admiral: a slide may add `detail`, `links` (`{"text", "url"}`) and
  `"admiral": false`, which the admiral never shows. `build <doc> --deck admiral|commodore|all` (a
  document's default: the admiral, and the commodore once its folder exists) writes
  `<stem>-commodore-deck/`; every deck named is built in memory before any is written. A `commodore`
  section in `pitch.json` holds its limits (50 words, link text counted; 6 blocks; 3 lines; a 40 px
  floor; `link_prefixes`, https by default), `layout.commodore` its sizes, `claims.commodore_must_appear`
  its pins, `naming.commodore_suffix` its folder, which joins `folder_deck_suffixes` and is read as a
  member of any list. 15 new rule ids (59): every admiral slide rule as `commodore.*`, and
  `commodore.links` (a link outside the prefixes, or a URL neither the document's body nor its sidecar
  names). Three rules widen for the commodore alone: `deck.external` passes its own `<a href="https://…">`,
  the pins read its own list, and the markup grammar admits an `<a href>` in a `p` (the fit estimate
  reads it as its paragraph's text). The sidecar takes `published.commodore_deck`; `renders` lists it;
  `calibrate render` lays its slides out too. This interpreter's `deck.generator-drift` build now runs
  in the checker's process (an `extra_interpreters` entry still runs as a subprocess): the suite went
  from 12 s to 4 s with 19 more failing roots. The review fixture gains a sidecar and a commodore deck.
  The suite runs 338 cases.
- `soundings refresh` leaves a scheduled entry whose branch dispatch's queue holds (`dispatch-queue
  has`: queued at fire time, dispatch-queue S3); only one in no queue goes back to `queued`. Any answer
  but 0 holds it, a crash's exit 5 included (S3's landing review, item 5).
- `pitch` (renders S3): the document holds every render's words (D2-A). The admiral deck's slides live
  in one ```` ```deck ```` fence at the document's end, which `build <doc>` reads (a first build makes
  the deck folder and a `deck.json`); a `slides.json` deck still builds, and one with both is refused.
  The fence is cut from what `admiral.invented-number` and the pins read, so a stale fence and a pin
  only the fence carries both fail. `memo <doc> [--check] [--replace]` writes the captain page from the
  document, refusing a block it cannot place by line; `review <doc>` holds a captain review to
  `skills/captain/TEMPLATE.md` with no config; `renders <doc> [--links]` lists the renders and their
  published links. 14 new rule ids (44): `captain.contract.*` (title, tokens, dark-scheme, dark-theme,
  background, script-version, css-load: the artifact page contract), `captain.generator-drift`,
  `captain.unplaced`, `review.title|sections|options|decisions`, `sidecar.stale`; a sidecar's asset may
  be the upload's `/_blob/<id>`. `pitch.json` gains `naming.deck_fence` and `memo.dark`. New skills
  `/pitch` and `/captain` with the review template; a second passing root (an invented captain review
  holding every shape the converter places). The suite runs 285 cases.
- `pitch` (renders S2): `calibrate glyphs|render [<root>] [--shots DIR]`, the export's calibrator,
  by hand only (Chrome and the network; no check calls it). `glyphs` no longer reads the table it is
  about to write, so a first measurement and a changed face run; `render` refuses a root with no
  admiral deck (exit 2) rather than passing it. `pitch.json` gains `publish` (`design_system`,
  `brand`, `images`, `asset_host`; a memo may load from `asset_host`) and `naming.sidecar_suffix`; a
  value outside its set stops the check (exit 2). The sidecar `<stem>.pitch.json` is checked when
  present: a 30th rule id, `sidecar.shape`, with a passing sidecar and a failing root. The method and
  the config reference are public as `skills/pitch/method.md` and `config.md`, the latter with a
  15-line pytest template. The suite runs 206 cases.
- New tool: `bin/pitch` (renders S1) — `check <root|doc> [--json]` holds a document's renders to
  the method (the captain page, the admiral deck, every folder and single-file deck; 29 rule ids,
  exit 1 on a finding, 2 when it could not run), `build <deck|doc> [--check]` writes an admiral deck from its `slides.json`,
  refusing the whole deck when a slide breaks a rule. Its rules, checker and builder are
  `bin/pitchlib.py`, stdlib Python 3.9; its config `pitch.json`, found at or above the root,
  `extends` kept. `tests/pitch.sh` builds one failing root per rule at run time and runs 170 cases.
- `agents/sounder.md`'s shared marker and head name wharf's `principal-architect` as the body's fourth
  head (principal tier S2, 2026-10-26); the body itself is unchanged.


- `/sextant` step 1, item 8 (self-tuning S5, 2026-10-27): models, prices and published evals bearing on a
  pin plumb's `trim` judges, each with a `- trim: <job> — <metric> — <arm>` line, the tag `trim` reads as
  its intake; the check proves the skill's example parses as that intake.
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
