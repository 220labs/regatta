# modules/sextant — strategy, and its ideas intake (Sparks)

Read `README.md` first: it is the chart. For an agent:

- Sparks reads private material (recordings, notes); nothing in this module names a person, a
  host, a vault or a path of the owner's. Private values come through the regatta config dir
  (`sextant/sparks.json`, `sextant/sextant.json`, `sextant/log`, `sextant/source`), test
  fixtures are made up (speakers `sam`, `alex`; addresses invented). This module is public.
- `bin/sparks --help` prints its calls and an unknown argument exits 2, but a bare `sparks` runs a
  pass on the Mac's own config. Use `sparks --route <note>`, `--inboxes`, `--dry-run`, or the suite.
- `bin/redactions show` refuses inside Claude Code (`CLAUDECODE`): a transcript is read again by
  later sessions. Never work around it.
- The core is found by `lib/find_core.py`; a peer (`knowledge-commit`, `publish`) through
  `common.tool()`, never a path beside this file — and every peer has a one-line fallback with a
  case in `tests/sparks.sh`.
- A rebuilt launcher loses its Full Disk Access and Notes grants: change `launcher.c.in` only
  when the change is worth a person re-granting it.
- check: `bash modules/sextant/tests/check.sh`.
