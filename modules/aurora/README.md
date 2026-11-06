# aurora — Aurora Borealis, the night job

Aurora Borealis is the work that happens while the owner sleeps: the weekly loop that reads the
week back and leaves proposals for the morning. Each job is a **section** with its own cadence;
a night runs the ones that are due, mechanical and cheap first, the judgement last. **Embark**
is the Monday sitting that walks the owner through what the night left and applies what they
approve.

| File | What it is |
| --- | --- |
| `bin/weekly-run` | what launchd runs: `weekly-run aurora <cwd>` picks tonight's sections, runs the tend and the classify (zero tokens), then one `claude -p "/aurora <section>"` per section under a time cap, then the trim section (zero tokens, under the same cap; on a Sunday night it waits until 00:30 for every host's day files), and checks each section's proof; `--dry-run` prints tonight's order, `--due` is the same as a precheck (exit 3 when nothing would run); `weekly-run where` prints where things are; `weekly-run aurora --scope <scope>` runs one scope's pass instead, from the scope's anchor and on its login |
| `bin/embark-memo` | the week's `/embark` sitting as one course memo, by code: the dream's D-items with the sections they quote copied under them, the branches file as one item (a table per class), the sextant's PROPOSE items, the charts dry run, one item per FAILED line; vault first (Evolve S2): the whole memo goes to `<vault>/dreams/<day>-embark.md`, and regatta's view leaves out every item, copied section and Do-this-now line about a venture or the household (a venture's name, a personal path, `Vault only: yes`) with a pointer or a count. `weekly-run embark <cwd>` (and the sextant job, after its session) commits regatta's view as `docs/embark/embark-<day>.md` in regatta on `claude/<host>/<day>-embark`, pushes it and runs `keel line`; helm's board puts it first in the owner's column; `--dry-run` prints it |
| `bin/week-digest` | what the owner typed this week, per project and session — the raw material the dream reads, a launcher's prompts left out and counted — and `--promote-tags`, the tagged lines; a confidential scope's counted, never quoted, `--scope` for one scope; read-only |
| `bin/scope-pass` | the code half of a scope's pass: `where` (what it reads and writes, and whether it may run), `check` (a confidential scope's draft names none of its repos, paths or words — `<anchor>/.claude/words.txt` holds the node's own, a `re:` line a family of ids, read across hard wraps; `--judge` adds the gate's `scope.brief` judge for a brief leaving the node, `pickup seed --from`'s review), `record` (the export gate, Evolve S2: the dream on the anchor's records branch `claude/<host>/<day>-scope-pass`, pushed, its pull request made ready for the anchor's own merge to land; the draft under the export-safe heading `# Upstream — <day>`, scanned and, for a confidential scope, judged on the gate's `scope.upstream` row, written to the vault's inbox as the exact bytes judged; a receipt (cycle, records ref, sha256, the judge's revision) beside the dream; `log.md` gets a word, never a count; a hit or a leak holds the draft inside the anchor), `proof` (LAUNCHED only on a verified receipt and the dream on the anchor's main, WAITING while its pull request is open; `LEAKED` when a confidential file on the vault's main is bytes no complete receipt of the day named; exit 2 when the node's word list cannot judge and the receipts settle nothing), record's exits (0 recorded, 3 held, 1 retry, 2 a word list that cannot judge, 4 leaked), `receipt` (the verified receipt as JSON, for weekly-run's log and the barrier) |
| `bin/evolve` | the code half of Evolve, the self-improvement loop (docs/self-improvement-2026-10-30.md in regatta): `probes` walks the owner's answer surface — board, link, render, saved, ingested, resumed — through keel's own verbs on a synthetic doc in a scratch repo, at zero tokens, and with `--doc`/`--board` the link and render stages of real docs, read-only; one record line a run in `<log dir>/aurora/evolve/probes.jsonl`; aurora's nightly job runs it after the tend, a broken stage a `FAILED probes` line. S3: `coverage` builds the register (each lens × source × scope: `observed`, `stale`, `source_missing`, `unread`, `inaccessible`, `excluded`, `not_applicable` or `fenced`) from `lenses.json` and each scope's profile (`<config>/aurora/scopes/<scope>.json`), names the surface nothing reads (every registry repo, the log dir's and the config dir's entries, minus what a source reads), and writes each scope's collector manifest, which a `quiet` receipt needs, judged against the last complete pass's (`--promote`); `conformance` sorts the declared rules (`<config>/aurora/conformance.json`, a profile's `conformance`) against the transcripts' tool calls into dead, holds, violated and worked around; `validate` and `schema` hold the finding, coverage, receipt and ledger records to their schemas; `action-id` is hash(finding id, action version, target scope). Every verb reads the registry once and walks every scope; a confidential scope is named by its marker, its transcripts never opened outside its own `--scope` |
| `lenses.json` | the fourteen lenses (Ring 1, on `autofinish_exclude`): each lens's question, the sources it reads under `{log}`, `{config}`, `{anchor}` or `{repo}`, a verb or git, who reads each into a lens, how fresh it must be; the collectors a quiet receipt rests on; the outcome classes and their observation windows; the conformance thresholds |
| `lib/evolve_schema.py` | the records as data a validator walks: the finding (its lifecycle in three families — proposal, execution, outcome — `found_by` and `also_found_by` for the knee rule, `action_id`), the findings file (five at most), the coverage record and its cells, the manifest, the receipt, and the ledgers (asks, themes, overrules, reservations, starts, conformance rows) |
| `skills/aurora/` | `/aurora`, and its `sections/`: `branches` (a verdict per idle branch code could not settle), `charts` (the layer's docs map and charts kept current, one PR), `dream` (one reviewed proposal for the always-loaded layer), `dream-scope` (`/aurora dream --scope <scope>`: one scope's pass — its dream in the scope's knowledge repo, its generalised lines in the vault's `inbox/upstream/<scope>.md`, the only thing of a confidential scope the global dream reads) |
| `skills/embark/` | `/embark`, the Monday sitting: hands over the embark memo's course, waits for the answers (`keel sheep wait`), applies them |
| `install.sh` | `--check` what aurora finds; `--schedule` the nightly launchd job (21:00); `--remove` it |

## Where things are

Nothing in the module names a path of the owner's. `weekly-run` finds, and `weekly-run where`
prints for the skills:

| Name | What | From |
| --- | --- | --- |
| `module` | this module | the script's own path |
| `regatta` | the core's CLI; `regatta <tool> …` runs any module's tool | `modules/regatta` beside this module, else `$REGATTA_HOME`, else the config dir's `home` file |
| `layer`, `layer-name` | the knowledge layer every session loads (rules, skills, docs) | atlas's `atlas/layer` key in the config dir (`$REGATTA_CONFIG`, else `.config/regatta` in the home folder); `$ATLAS_LAYER` overrides |
| `vault`, `vault-name` | the vault of records written in place (bulletin, memory, dreams, `log.md`) | atlas's `atlas/vault` key; `$ATLAS_VAULT` overrides; without an overlay, atlas's default |
| `logs` | the night's logs | `$WEEKLY_LOG_DIR`, else `Library/Logs/claude-weekly` in the home folder |
| `projects` | the projects folder | the core's `regatta/projects`, else `projects` in the home folder |

Config of its own (listed in `config-keys`, so `regatta check` reports it): `aurora/host`, the one
host (its name as the core's `host_name()` prints it, case-blind) the whole-night jobs run on —
`weekly-run aurora`, `weekly-run sextant`, and sextant's own runner. Every other host skips with a
line, and `install.sh --schedule` refuses there; a host that gets the overlay later never runs
them by default (two hosts each writing the week's dream in place conflict on push). A scope's pass,
`weekly-run aurora --scope <scope>`, runs on that scope's yard (the registry's `yard`), else on
`aurora/host`; a registry that does not read refuses it. Where an overlay is installed (the config
dir's `regatta/overlay` marker) and `aurora/host` is absent, the run refuses. `aurora/trim-repos`, optional: the repos the night's
`trim` section tunes, one absolute path a line, read as the core reads a key; absent, the core's own checkout; written empty, none; and only a repo holding
`trim/<vertical>.json` counts. `aurora/skip-hosts`, the old
deny-list (the hosts never to run on, one per line), is deprecated: read only while `aurora/host` is
absent, with a line saying so. The rule is the core's (`common.weekly_host`; `regatta weekly-host` in a
shell), so weekly-run, sextant's runner and both installers read it alike.

## Peers

| Peer | Used for | Without it |
| --- | --- | --- |
| the core (`regatta`) | the CLI, `host_name()` | nothing runs: the run refuses in one line |
| atlas | the bulletin, `knowledge-commit`, `docs-index` (charts) | no bulletin lines (the log still says it); the quiet week's line and the dream's commit fail their step; charts is never due |
| wharf | `tend`, `repos` (classify), `pr` (the charts PR), `branches.py` | that step fails with one line; the branches section gathers for itself |
| wharf-runs | `rc-hosts --launcher` (a stable launcher for `claude`) | `claude` runs directly |
| plumb | `knowledge-numbers`, `interruptions` (the dream's numbers); `trim` (the trim section) | the dream says the numbers are missing; trim is never due, and the dry run says why |
| lighthouse | `account pick --repo` (the login a scope's pass runs on, `weekly-run aurora --scope`) | an open scope runs on the login it started on; a confidential one with a login does not run |
| sextant | `weekly-run sextant <cwd>` runs `/sextant` until the sextant module ships its own runner | — |

A peer is found through `regatta which <tool>` (the core's `common.tool()`): a module of the
same checkout, an installed plugin, else an overlay's old path.

## Install

`claude plugin install aurora@regatta` for the skills. For the night: `sh install.sh
--schedule` writes and loads `dev.regatta.aurora` (`AURORA_LABEL` overrides), nightly at 21:00,
running `bin/weekly-run aurora <vault>`; a night with nothing due ends before `claude` starts.
An install with an overlay of its own (the config dir's `regatta/overlay` marker) schedules the night
itself, so `--schedule` refuses there. On other harnesses the skills' text and `bin/` work; the
schedule is launchd's (macOS).

## Check

`bash tests/check.sh` — tonight's plan, the refusals, the peers missing, the skills' commands
held to the allowlist, `--schedule` against a scratch launchd. Scratch paths only; no network,
no `claude`.
