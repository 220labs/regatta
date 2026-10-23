# modules/plumb — measure

Read `README.md` first. For an agent:

- `CREW_REPORT_NO_DRAIN=1 crew-report week` (no `--write`) changes nothing but the cache; run it
  freely. Plain `week` drains keel's rooms first (a write to keel's state), and `--publish` is the
  weekly job's alone (one publisher per published file).
- The typed-prompt rule rests on probes of real transcripts. Change it only with a new probe and
  a fixture in `tests/crew-report.sh` that fails before the change and passes after.
- The transcript cache stores `classify`'s verdict per line. A change to `classify`, `extract_file`
  or the entry format bumps `TranscriptCache.VERSION`, else a warm cache keeps answering with the
  old rule. Same for the word rules and `RenderCache`: a new rule gets a new `CACHE_FILE` name.
- Every fixture is synthetic: never a real name, project, path or prompt, not even in a test
  (this module is public, every file of it on `.helloworld/allowlist.txt` since the plumb scrub,
  2026-10-22). Private names, terms and paths come through the config dir (README, "Private
  values"); a suite writes its own (`REGATTA_CONFIG="$T/config"`), never this Mac's.
- A run bound to its cases and the owner's repos is a record, not a bench: it goes to the private
  repo's `docs/plumb/`, kept as written (the design run of 2026-10-04, the reviewer bench of 2026-09-29).
- The core is found by `lib/find_core.py`; a peer (usage-report, keel, publish) through
  `common.tool()`, and its absence is a line in the report, never a stack trace. The suite pins
  each peer with `CREW_REPORT_<NAME>` (a stub, or `none`), never through the lookup.
- check: `bash modules/plumb/tests/check.sh`.
