# sextant — head towards your North Star

Sextant is Regatta's strategy module: what you are aiming at, which ideas get you there, and which
of them get built. Today it holds its **ideas intake, Sparks** — ideas in, one note per idea out,
filed where the strategy reads them — **`/sounding`**, which tests an idea before anything is
built, and **`/sextant`**, the weekly pass that audits the layer against the world and starts the
soundings the owner queued. The rest of the strategy half (goals, priorities and budgets in a North
Star, candidates) joins this same plugin later; there is never a separate Sparks plugin.

| Piece | What it does |
| --- | --- |
| `bin/sparks` | a recording, a written note or an Apple Note → one Markdown note per idea, filed into a folder or a project |
| `bin/redactions` | what Sparks' redaction step hid, per recording, and putting it back on the owner's word |
| `launcher.c.in`, `install.sh` | the launchd job that runs Sparks on a Mac, and the small launcher Full Disk Access is granted to |
| `bin/soundings` | the sounding queue: the proposals the owner chose to have sounded, three a week and five open at most, each started by Sextant at the weekly reset with the week read when it fires |
| `bench/redaction/` | can a classifier find what a memo should not put in git? Five arms over an invented corpus |
| `skills/sounding/` | `/sounding <idea> [--light] [--yolo]`: one architect-family agent picked by scope (`architect`, `sr-architect`, `sounder`) sounds the idea — a Landscape of what exists, a one-line Verdict — and the doc reaches the owner in full, as a chat questionnaire or with its reversible picks taken unattended |
| `agents/sounder.md` | the sounder: an architect for an idea outside any repo — a venture, a pitch, a tool to build or adopt — held to the ventures README's four gates, with a money flow and a smallest test; private until the architects' shared body is scrubbed |
| `skills/sextant/` | `/sextant`: the weekly pass — research what changed, review the layer against it, adopt the small things, log the rest with verdicts, measure, and start the queued soundings (step 2c); unattended once a week |
| `libexec/sextant-run` | `where` (the paths `/sextant` uses: the core's CLI, atlas's layer and vault, the ideas pool, plumb's usage reports, the owner's name) and `run` (the weekly job's own runner when aurora is not installed); off PATH, `regatta sextant-run …` |
| `tests/check.sh` | the suite (macOS: it records real audio with `say`), the bench's `--help`, the launcher compiled, the queue's and the weekly job's suites |

Install, from a clone (the shell and launchd face): `sh modules/sextant/install.sh --check` says
what is found, `--launcher` builds and schedules Sparks' job, `--remove` takes it out;
`--schedule` loads the weekly `/sextant` job (`--dry-run` prints its plist first, `--unschedule`
takes it out). As a plugin:
`claude plugin marketplace add <this repo>`, then `claude plugin install sextant@regatta` (it
needs the core, `regatta`); the plugin puts `sparks`, `redactions` and `soundings` on the Bash PATH.

## Sparks, the ideas intake

An idea arrives any of three ways, and each ends as a note:

1. **Spoken** — a recording lands in an inbox folder: an iCloud Drive folder a Shortcut copies
   Voice Memos into, or the Mac's own Voice Memos library (`"voice_memos"` in the config; an
   Action Button set to Voice Memo is then the whole capture). `whisper.cpp` transcribes it on
   the Mac, verbatim, in whatever language was spoken (`brew install whisper-cpp`, one model in
   `.cache/whisper` in the home folder). Optional: without whisper, recordings wait and written notes still file.
2. **Written** — a `.txt`, `.md`, `.rtf` or `.html` dropped into the inbox takes the same path
   minus whisper: in a `"split"` config, or a routed one that says `"written": true` (an inbox
   another tool writes notes into, a meeting's say; the note carries the config's `"source"`). That
   tool writes each note as a dot-file and renames it when whole: a dot-file waits.
3. **Apple Notes** — with `"apple_notes"`, each settled note in one folder (say `_ideas`) is
   exported into the inbox and moved to a second folder, so an idea is typed on any device.

Then one `claude -p` call, no tools, shapes the words into a note (a title, a summary, one
section per topic, translated as the prompt asks); with `"split": "topics"` each topic becomes
its own note with `status: new`. With `"route": true` a second, read-only call picks the project
and folder from the repos registry, and the note lands there through a pull request; otherwise it
lands in the config's `notes` folder. Nothing is deleted: the audio moves to an archive outside
every repo (audio is not text), and what a note proposes binning waits for a person.

**The config** is a JSON file in your own private place, never in this repo:
`$SPARKS_CONFIG`, else `sextant/sparks.json` in the regatta config dir (`$REGATTA_CONFIG`, else
`.config/regatta` in the home folder) — a link to wherever you keep it. The keys, with an example, are in
`bin/sparks`'s header: `inbox`, `notes`, `archive`, `prompt` (a file beside the config),
`language`, `split`, `route`, `written`, `source`, `host` (the one Mac that runs it), `also` (more configs the same
job runs after this one), `redact_approved`, `apple_notes`, `voice_memos`, `notify`, `publish`.

**Private values** come through the config dir, one file each, written by whoever installs the
modules: `sextant/sparks.json` (the default config), `sextant/sextant.json` (a second root
config `redactions` reads), `sextant/log` (the log file's path, one line; else
`Library/Logs/sparks.log` in the home folder) and `sextant/source` (the guarded source a recording counts as for
the core's model gate; where an overlay is installed it is required, and without it redaction
refuses rather than send under a name the gate does not guard).

**Redaction**: a split config with `"redact_approved": {"<vendor>": "<the owner's quote>"}` sends
the verbatim transcript, sentence by sentence, through the core's gate row `sparks.redact` before
Claude sees a word; flagged sentences become markers, the originals stay in a sidecar beside the
audio, and `redactions show / release / done` is the review. A missing quote, a row that is off or
a classifier that fails: nothing is shaped, the audio waits.

**The launcher** (`install.sh --launcher`): macOS keeps a launchd job out of iCloud Drive and
Google Drive unless the job has Full Disk Access, which TCC grants to the program the job starts.
`launcher.c.in` is that program, built with the script's and the config's paths compiled in, and
signed ad hoc. It needs two grants, which `--launcher` names after every build: Full Disk Access,
and Automation for Notes (only if a config reads Apple Notes). A rebuild loses both, so the build
runs only when its stamp — the template, both paths and the signing identifier — changes. The job
runs `sparks --chain` when an inbox changes and every 15 minutes.

**Messages**: want a text when a recording arrives and when it is filed? Point the config's
`notify` at any command that texts you (a messenger with its own `install.sh` and Messages grant).

**What was already said**: `sparks related "<words>"` lists every note and proposal in the ideas
pool — the notes folder of each topic-split config, its `proposals/` and `research/` — that mentions one of
the words, whole words with a plural, most words matched first, then newest. A grep, no model;
dropped notes and a friend's count like the owner's. An architect agent runs it before it designs.
With `"sparks": "off"` in an optional `regatta/peers.json` in the config dir (`$REGATTA_PEERS`) it reads nothing and
says so in one line.

## The weekly pass, `/sextant`

Once a week (Monday 02:00 unless the installer says otherwise) launchd starts `/sextant`
unattended in atlas's layer. It reads the previous entry first, so findings compound: research
along a fixed checklist, a verdict per finding (ADOPT, at most three, made in a worktree of their
own and launched reviewed; PROPOSE for the owner; WATCH; REJECT), the ideas backstop (2b), the
sounding queue (2c), the numbers, then one entry, `sextant/<date>.md`, launched through a pull
request. Every path it uses comes from `libexec/sextant-run where`: nothing in the skill names an
owner, a host or a folder.

Who runs it (the design's G29): **with aurora installed**, its `weekly-run sextant <layer>` — the
allow and deny lists the unattended session runs under, the check that the entry launched, the
retry on an unreachable API. **Without aurora**, this module's own runner, `sextant-run run`:
narrower on purpose, since it carries none of weekly-run's writer guards — it allows the queue's
reading verbs, the numbers and `knowledge-commit`, and denies every writer that starts work.
`install.sh --plist` prints the job for an installer that loads its own agents; its knobs (label,
log, the weekly-run path, the folder, the slot) are in the script's header.

Step 2c starts a queued sounding through three peers: wharf-runs' `pickup seed` and `dispatch
--at reset --if-room`, and keel (the sounding's own hand-over). **With any of them absent** — or
under the own runner — `soundings next` gives each candidate one `by hand` line instead of
commands: the `/sounding` the owner would type, and the `soundings mark … launched` that records
it (the design's G27). The pass carries that line to the triage file; nothing is started.

## Optional peers

Each is found through the core's `common.tool()`; absent, the pass says so in one line and the
note is still filed.

| Peer | What Sparks uses | Without it |
| --- | --- | --- |
| atlas (`knowledge-commit`) | commits the notes in the vault they were written to | "vault commit: atlas not installed" |
| lighthouse (`publish`) | `"publish": "vault"` copies what the pass wrote to a shared drive | "publish: lighthouse not installed" |
| a messenger (any command) | `notify`: a text to the owner | no texts |
| aurora (`weekly-run`) | runs the weekly `/sextant` with its lists, launch check and retry | the module's own runner, which starts no work |
| wharf-runs (`pickup`, `dispatch`), keel | step 2c seeds and schedules a queued sounding | `soundings next` prints the owner's line instead |
| atlas (`knowledge-commit`, its layer and vault keys) | `/sextant`'s worktrees, its launch, where it works | `where` says MISSING and the pass stops |

The model for each call is a row in the core's gate table (`sparks.shape`, `sparks.route`,
`sparks.redact`). The core's default table has none of them, so a pass waits ("no row for
sparks.shape") until your own table — `regatta/models.json` in the config dir, which replaces the
default whole — carries them, for example:

```json
"sparks.shape":  {"kind": "generate", "provider": "claude", "when_off": "fail"},
"sparks.route":  {"kind": "generate", "provider": "claude", "when_off": "skip"},
"sparks.redact": {"kind": "classify", "provider": "off", "when_off": "fail"}
```

`sparks.redact` off with `when_off: fail` refuses every pass of a config that asks for
redaction; give it a classifier (and the config its `redact_approved` quote) to turn it on.
