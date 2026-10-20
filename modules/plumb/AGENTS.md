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
  (this module is public). The files B8 moved in (all of `bin/` and `hooks/` but crew-report,
  `widgets/`, `bench/`, `tests/usage-report.sh`, `tests/interruptions.sh`) are private until a
  plumb scrub step: off `.helloworld/allowlist.txt`, and the rule binds them from then on. Private names, terms and paths come through the config file.
- The core is found by `lib/find_core.py`; a peer (usage-report, keel, publish) through
  `common.tool()`, and its absence is a line in the report, never a stack trace. The suite pins
  each peer with `CREW_REPORT_<NAME>` (a stub, or `none`), never through the lookup.
- check: `bash modules/plumb/tests/check.sh`.
