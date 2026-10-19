# Changelog — plumb

## 0.4.2 — 2026-10-19

- `reports` defaults to `~/.local/state/regatta/crew-report` (was a folder under the projects
  folder that named one owner's layout). A deployment that publishes sets `reports` under the
  publish tool's root, which refuses a file outside it; without that, the weekly publish fails
  with one `publish FAILED` log line and the report stays local.

## 0.4.1 — 2026-10-19

The /finish review's fixes.
- The zone is the system's named zone (or `tz`, or `$TZ`), not today's fixed offset: weeks across
  a DST change meet with no hour lost or doubled.
- A fork (/fork, pickup's move) gives its inherited rows back to the source session, so the
  person's own lines after the move count; the default pickup pattern matches the prefill only.
- Cost: usage-report's keys go through crew's own project mapping (a subfolder's cost joins its
  repo); `--this-host` keeps this Mac's rows. A path in another user's home under the same root
  maps as this one's.
- Measured reading: a run across Sunday midnight keeps Sunday's side at any gap; `ts` as epoch
  seconds is read; `read_gap_minutes: 0` is applied; `drained: <time>` after a good drain and the
  stale line only without one; `Opened without a heartbeat (docs)` per project from keel's
  `opens.jsonl`. The drain runs in an empty folder with 300 s.
- `--write` writes latest.md only for the last complete week, refuses `--until`, and publishes only
  with `--publish`, which the job's plist carries. `install.sh --schedule` names the main checkout
  from a worktree and retries a bootstrap once.
- Not-counted tallies and first prompts are over the week alone; a text first prompt shows as a
  digest of its first 40 characters. The prompt-rule warning looks at prompts, not rows.
- Estimated reading: `reading.include`; two repos adding one path are two docs; the static HTML
  reading survives an unclosed `<head>` or `<tr>`; a Chrome render cannot abort the report (90 s).
- Recordings: est. and unresolved counts follow the kept files; unreadable note folders are said;
  an audio root matches whole path segments. Login dirs: the default one is read when the registry
  names none of its own.
- Peers can be pinned with `CREW_REPORT_KEEL`, `CREW_REPORT_PUBLISH`, `CREW_REPORT_USAGE_REPORT`.

## 0.4.0 — 2026-10-19

- `crew-report week`: measured reading. The heartbeats keel files for a doc's course page
  (`reads`, rows of `reads.jsonl`: doc, repo, branch, path, ts in UTC, who) are joined per project
  and doc at gaps up to `read_gap_minutes` (default 5) into runs spanning `[first - 1 min, last]`;
  tabs and docs of a project in one minute are one minute. The `reading` column is the project's
  measured minutes; the total is prompts, recordings and measured reading as one union, overlap
  counted once. The 10 / 30 columns move the prompt gap only. `est. reading` is unchanged and still
  never added.
- New config keys: `reads` (a list of files, default `["~/.local/state/memo/reads.jsonl"]`), `viewer`
  (the `who` to charge, `""` = every viewer, the distinct count printed) and `read_gap_minutes`.
  Another viewer's minutes print as `other viewers: n min` and are never charged.
- Under the table: `reading raw: n min` before overlap removal, `docs added: n; … with a course: m`
  per project, `last drain: <time>` (and a line when it is over 6 h old), and what is not measured.
- `week` first runs `keel sheep drain` once (120 s at most) and says in one line if keel is missing
  or the drain failed, then goes on; `CREW_REPORT_NO_DRAIN=1` skips it. keel's subcommand is built
  in another step: until it lands, the report carries `drain: failed — exit …`.
- G6 (the first week of heartbeats against opens) is checked by hand the Monday after this lands and
  its figures written here.

## 0.3.0 — 2026-10-19

- `crew-report week --write` publishes. New config key `publish`: `""` (local only, the default),
  `"vault"` or `"data"`, the scope of lighthouse's `publish` tool, found through `common.tool()`.
  The tool absent: the report says "local only"; a failure is one log line and never fatal.
- `install.sh --schedule` writes and loads one launchd agent running `crew-report week --write`
  on Mondays at 07:30 local; `--remove` unloads and deletes it; `--check` also says whether it is
  loaded. `PLUMB_LAUNCH_DIR`, `PLUMB_LAUNCHCTL` and `PLUMB_LABEL` override the plist folder, the
  launchctl and the label. Nothing is scheduled until `--schedule` is run.
- A weekly pass fits the 2-minute goal (G5). A cache folder (`cache`, default
  `~/.cache/regatta/plumb`, `""` = off): rendered HTML docs' word counts by text hash, and each
  transcript file's prompt candidates by path, size and mtime (digests where text would be, no
  prompt text). Docs are read with two git calls per repo, not two per doc, and Chrome renders four
  at a time. The 2026-W42 report printed the same table before and after. On a loaded Mac the
  pass took 1:43 before (2:54 on an earlier day), 1:28 with an empty cache and 0:06 with a warm one.
  An AskUserQuestion answer is now matched to its question within one transcript file only.

## 0.2.0 — 2026-10-19

- `crew-report week`: recordings. Notes (`notes`, `audio_roots`) selected by a project's `terms`,
  one recording per audio file, length from afinfo, ffprobe or the note's size, joined with the
  prompts as one union per project; the total column is that union.
- `crew-report week`: estimated reading, reference only and never in the total. The docs a
  project's repos added in the week (by author date, all refs, content at the newest ref),
  `exclude` and `reading.exclude`, 200 words a minute, HTML rendered by headless Chrome when found,
  else stripped statically; "docs added: n" per project under the table.
- New config keys: `notes`, `audio_roots`, `chrome`, `words_per_minute`, `exclude`,
  `projects.<name>.terms`, `.repos`, `.reading.exclude`.

## 0.1.0 — 2026-10-19

- First cut: `crew-report week`. Typed prompts per project from every login dir and the
  archive, deduped by uuid, with launchers' prompts dropped. One timeline, a 20-minute gap,
  10/30 beside it, ISO weeks in the local zone. The week's cost from usage-report when found.
- Replay of 2026-W42 cut at 2026-10-18 15:17 against this Mac's transcripts: the project of
  the hand run of that day reads 18 prompts and 52 min at gap 20 (the hand run: 52 min).
