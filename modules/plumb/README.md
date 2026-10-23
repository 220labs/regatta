# plumb — measure

Plumb measures: model usage and cost, interruptions, the tier hint, and the owner's own time per
project. crew-report and its weekly job are below; usage-report, interruptions, knowledge-numbers,
the statusline, the tier hint (`hooks/tier_check.py`), the attention log (`hooks/attention.py`), the
limits widget and the benches (`bench/`) read their private values as the next section says.

## crew-report

`crew-report week` prints one ISO week: per project, the prompts the owner typed into Claude Code
and the minutes they span, the voice recordings about the project, the time actually spent on the
docs' course pages (measured reading), an estimate of the reading the week's new docs would take,
and the week's model cost when usage-report is found.
Zero tokens and stdlib only. It writes its report and its cache, and its drain (below) writes
keel's `reads.jsonl`; `CREW_REPORT_NO_DRAIN=1 crew-report week` is the pass that changes nothing
else.

```bash
crew-report week                                  # the last complete week, to stdout
crew-report week --week 2026-W42                  # one week
crew-report week --week 2026-W42 --until 2026-10-18T15:17   # a replay cut short; prints only
crew-report week --write                          # <reports>/<week>.md, and latest.md for the last complete week
crew-report week --write --publish                # the weekly job's flags: the files to publish too
crew-report week --this-host                      # the cost column for this Mac's calls only
```

**What counts as typed.** A user event with `origin.kind == "human"`, or a local slash command
(`/model`, `/login`: they carry no origin) typed in VS Code or the CLI. Everything else is
counted separately and shown under the table: relays (the Session-tab message, Talk answers),
interrupts, AskUserQuestion answers, task notifications, hand-backs, and machine starts. A
machine start is a prompt a launcher sent with a human origin. The defaults cover dispatch's
unattended preamble, autofinish's `/finish … --unattended` and a pickup prefill, and config adds
more. A session that opens unattended counts nothing.

**Time.** One timeline per project. Prompts no more than 20 minutes apart count as time, a longer
gap is a break, and nothing is added per burst. The 10- and 30-minute gaps print beside it for
sensitivity. Weeks are ISO weeks in the local zone, so a gap across Sunday midnight splits there.
A session started in a repo's subfolder counts for the repo.

**Sources.** Every Claude login dir in the accounts registry (`$ACCOUNTS_FILE`, else
`lighthouse/accounts.json` in the regatta config dir; Orca's logins through the core), else
`~/.claude`; plus the transcript archive. Each real file is read once, and events are deduped
by `uuid` because the archive copies live files.

**Recordings.** `notes` is a folder of idea notes, each with front matter `recorded: YYYY-MM-DD
HH:MM`, `audio: <path>` and optionally `size:` (bytes, or `39.9 MB` as the notes write it). A project's `terms` (case-blind regexes)
select its notes by title, file name and body. Notes are grouped by audio file: a file counts once
per project, and two different files with the same `recorded:` minute both count (the second is
laid back to back before the first). `audio_roots` maps a prefix to a folder: an `audio:` path that
starts with the prefix is looked up under the folder. A file's length comes from `afinfo`, else
`ffprobe` (also looked up in `/opt/homebrew/bin` and `/usr/local/bin`, which a launchd job's PATH
lacks), else `size` x 8 / 64 kbit/s, marked est. in the report, else 0 and "n files unresolved".
The recording is the interval `[recorded - length, recorded]` in the local zone. Recordings and
prompts are one union per project, so the total counts talk during a session once. The report
names counts and minutes, never a title, term or file name. `CREW_REPORT_AFINFO` names a script
to use in place of `afinfo`, for tests.

**Estimated reading.** The `est. reading` column is for reference and is never added to the total.
For each project the repos in `projects.<name>.repos` (default `<projects_root>/<name>`) are asked,
across all refs, for the `*.md`, `*.html` and `*.htm` files added in the week by author date (the
log is widened by a week because the repo filters on the committer date); each path counts once. The
text is the file at the newest ref that holds it, not the add-commit. Files matching `exclude`
(basename anywhere when the glob has no `/`, a path glob otherwise, `**` allowed) or the project's
`reading.exclude` are skipped. Words: prose 1.0, fenced code and table rows 0.5, link text kept,
URLs and markup dropped, at `words_per_minute`. HTML is rendered by headless Chrome (`--dump-dom`,
5 s of virtual time) from `chrome`, else the standard macOS app path or a Chrome on PATH; with
none, or if it fails, the file is stripped statically. The report counts "docs added: n" per
project, and how many HTML files were rendered or static.

**Measured reading.** keel's course page for a doc emits a heartbeat a minute while it is visible and
touched; keel files each as a row of `reads.jsonl`: `{"doc", "repo", "branch", "path", "ts", "who"}`,
`ts` the event's own time in UTC (ending in Z; epoch seconds are read too, as `opens.jsonl` writes them), `who` the viewer's display name. A row says the
viewer was active on that doc's page in the minute up to `ts`. `reads` is a list of such files
(default `["~/.local/state/memo/reads.jsonl"]`, so a copy pulled from another Mac can join).
Per project and doc, heartbeats no more than `read_gap_minutes` apart (default 5) are one run
spanning `[first - 1 min, last]`; a gap over it is a break. Two tabs, or two docs of one project, in
the same minute are one minute. The project is the row's `repo` mapped as a prompt's working folder
is (a repo outside `projects_root` is the "?" row). A run is split at Sunday midnight like a prompt
gap, and `--until` drops the rows after the cut.

- The `reading` column is the project's measured minutes. The total is prompts, recordings and
  measured reading as one union, so reading a design while its session waits counts once: under
  the table, `reading raw: n min` is the reading before overlap removal (each doc's runs summed) and
  how much of it the prompts and recordings already held. The 10 / 30 columns move the prompt gap
  only; reading stays at `read_gap_minutes`.
- `est. reading` stays a reference column and is never added.
- `viewer` is the `who` to charge. Empty counts every viewer and prints the distinct count; set,
  another name's rows are never charged and print as `other viewers: n min` (minutes only, never a
  name). The filter is the display name, not an account.
- `docs added: n; with a course: m` per project: m is the added docs with a heartbeat row in the
  week, so the gap between the two reading columns can be read.
- `drained: <time>` when this run's drain succeeded; `newest heartbeat: <time>` is the newest row
  in the files, and a line says when there was no drain this run and that row is over 6 h old.
- `Opened without a heartbeat (docs): <project> n`: docs whose page keel logged an open for in the
  week (its `opens.jsonl`, beside each reads file) with no heartbeat: a page deployed before it
  learned to heartbeat, or heartbeats refused. With `viewer` set and no minutes while docs were
  opened, the count of distinct names in the rows is printed (never the names).
- **Drain first.** `week` starts by running `keel sheep drain` once (keel found through
  `common.tool("keel")`, 300 s at most, in an empty scratch folder: a keel without the subcommand
  reads "drain" as a doc to deploy) so the rooms' heartbeats are in the file. Any failure,
  including a keel that has no such subcommand yet, is one line in the report (`drain: failed — …`,
  `drain: keel not found`) and the report goes on with the file as it is.
  `CREW_REPORT_NO_DRAIN=1` skips it; the tests set it.
- **Not measured**, and the estimate does not stand in: reading on GitHub or in an editor, the
  comment box on the page, a doc with no course page (notes, rules, transcripts; a Mac without the
  CLI), a page not redeployed since it learned to heartbeat, and a course re-read after its branch
  landed and keel pruned the pin (about 14 days). The report says so in one line.

**Config.** `$CREW_REPORT_CONFIG`, else `plumb/crew-report.json` in the regatta config dir. Without
it the defaults apply: prompts, and measured reading when `reads` holds rows; gap 20, sensitivity
10/30, read gap 5, every viewer, no recordings.

```json
{"projects_root": "~/projects", "transcripts": "~/projects/transcripts",
 "reports": "~/.local/state/regatta/crew-report", "tz": "",
 "gap_minutes": 20, "sensitivity": [10, 30],
 "machine_prompts": [], "unattended_prompts": [],
 "notes": "", "audio_roots": {}, "chrome": "", "words_per_minute": 200,
 "reads": ["~/.local/state/memo/reads.jsonl"], "viewer": "", "read_gap_minutes": 5,
 "publish": "", "cache": "~/.cache/regatta/plumb",
 "exclude": ["TODO.md", "AGENTS.md", "CLAUDE.md", "README.md", "CHANGELOG.md", "**/sources/**", "docs/handoff/**"],
 "projects": {"<name>": {"terms": [], "repos": [], "reading": {"include": [], "exclude": []}}}}
```

A project with prompts but no entry still gets a row; an entry adds terms, repos, excludes and
includes (`reading.include` brings a doc back over any exclude). A key
set in the file replaces the default whole, so `"exclude": []` removes every default exclude.

**Privacy.** The report holds aggregates only: no prompt text, note title, file name or session
id. The first-prompt line names slash commands, and a text opening by `(text #<digest of its first 40
characters>)`, so a launcher's repeated preamble shows as one count without its text.

**Publishing.** `publish` is `""` (the default: the report stays on this Mac), `"vault"` or `"data"`,
the scope of lighthouse's `publish` tool. With `--write --publish` (the weekly job's flags) and a
scope set, `crew-report` runs that tool (found through the core's `common.tool("publish")`) on the
files it wrote, and its output lines go into the job's log. A hand `--write` never publishes: a
published file has one publisher, the job, and says so in one line. A person's hours per project are private: choose
`data` only for a share whose members may read them. The tool absent: the report's last line
reads "publish: lighthouse not installed — local only" and nothing else happens. The tool failing
or timing out: one `publish FAILED` line in the log, the local files stand, the exit code stays 0.
The tool places a file by its path under the projects folder and refuses one outside it, so a
deployment that publishes sets `reports` to a folder there (the tool's own root: `~/projects`, or
its `PUBLISH_PROJECTS`); the default, in the core's default state folder, keeps an unpublished
report off every share.

**Cache.** `cache` is a folder (default `~/.cache/regatta/plumb`; `""` turns it off) holding two
things a weekly pass would otherwise recompute, so that it stays under two minutes as the transcript
archive grows. `render-v2.json`: the word count of each rendered HTML doc by the hash of its text,
so a doc is rendered once, ever (renders also run four at a time). `transcripts-<digest>.json`: for
each transcript file, by real path, size and mtime, the prompt candidates in it: time, working
folder, kind, a digest of the first 100 characters and whether the launcher patterns match. A file
is read again only when it grew or changed, and the digest in the file name covers the patterns,
so editing `machine_prompts` starts a new file. No prompt text and no doc text or title is stored.
Deleting the folder is always safe. Measured on a week of 1,800 transcript files (6 GB) on a loaded
Mac: about 90 s with an empty cache, 6 s with a warm one.

## Private values

Nothing here names a host, a login, an account or a person. What is private reaches the module as
files in the regatta config dir (`$REGATTA_CONFIG`, else `.config/regatta` in the home folder),
written by whoever installs the modules (on the owner's Macs, the overlay's `bootstrap.sh --config`).
plumb's own keys are under `plumb/`; the rest are the core's or a peer's, read here as their owner
writes them. Each keeps the environment override it had; an override is never exported.

| Key | What | Read by | Override | Absent |
| --- | --- | --- | --- | --- |
| `plumb/usage.json` | usage-report's settings: per host the renderer, its pulls, the notifier, the data folder; the NAS share, the reports folder, the plan (a link) | `usage-report` | `USAGE_CONFIG` | every host collects, none renders, pulls or sends; where the overlay is installed, one line on stderr |
| `plumb/dispatch-host` | `<host>:<ssh alias>`, the Mac dispatch runs on, whose logs G3 reads | `knowledge-numbers` | — | the first line of `wharf-runs/ssh`, said on stderr; neither: G3 not measured |
| `plumb/tier-rules` | where the tier table lives, as the tier hint names it (its words, one per line) | `tier_check.py` | — | "your model-routing rules" |
| `regatta/log-dir` | the core's log folder: usage data, the attention log, the benches' data | every tool | `USAGE_DATA`, `ATTENTION_LOG_DIR`, `BENCH` | `~/.local/state/regatta` |
| `regatta/projects`, `regatta/guarded` | the projects folder; the repos whose text never leaves the Mac (the core's) | `interruptions`, `knowledge-numbers`, the benches | `INTERRUPTIONS_PROJECTS`, `CORPUS_ROOT` | the home folder's `projects`; none guarded |
| `atlas/layer`, `atlas/vault` | the two knowledge repos: name, checkout, the variable that moves it (atlas's) | `knowledge-numbers`, `usage-report` (the ratio's commit), `bench/decisions` | the variable the key names | their numbers say not measured; the ratio is written, not committed |
| `lighthouse/accounts.json` | the login registry (lighthouse's) | `usage-report`, `interruptions`, `knowledge-numbers`, `tier_check.py` | `ACCOUNTS_FILE` | one login: the default config dir |

## How it runs weekly

```bash
sh <this module>/install.sh --check       # what crew-report will read, and whether the job is loaded
sh <this module>/install.sh --schedule    # write and load the weekly job
sh <this module>/install.sh --remove      # unload it and delete the plist
```

`--schedule` writes one launchd agent, `dev.regatta.plumb.crew-report` (`PLUMB_LABEL` names another),
that runs `crew-report week --write --publish` on Mondays at 07:30 local time, after usage-report's morning
render so the cost CSVs are complete. A Mac asleep at 07:30 runs it at the first wake. Its PATH
holds `/opt/homebrew/bin`, `/usr/local/bin` and `/usr/bin`; its log is `crew-report.log` in the
core's log folder (`regatta/log-dir`, default `~/.local/state/regatta`). The plist records the path
of the `crew-report` it was installed from: run the script from the main checkout or the installed
plugin, never from a worktree that will be removed. `PLUMB_LAUNCH_DIR` (default
`~/Library/LaunchAgents`) and `PLUMB_LAUNCHCTL` move the plist and the launchctl it calls; the tests
use both and never touch the real ones. Nothing runs the job until someone runs `--schedule`.
