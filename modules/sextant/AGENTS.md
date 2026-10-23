# modules/sextant — strategy, and its ideas intake (Sparks)

Read `README.md` first: it is the chart. For an agent:

- Sparks reads private material (recordings, notes); nothing in this module names a person, a
  host, a vault or a path of the owner's. Private values come through the regatta config dir
  (`sextant/sparks.json`, `sextant/sextant.json`, `sextant/log`, `sextant/source`), test
  fixtures are made up (speakers `sam`, `alex`; addresses invented). This module is public.
- One file is private until its scrub: `agents/sounder.md`. Its body below the `<!-- shared:` marker
  is the architects' (wharf's, private), byte for byte, and names the owner; it stays off
  `.helloworld/allowlist.txt` until wharf's scrub cleans that body. Its head is written as if
  public already. Edit the body in wharf's `agents/architect.md` and copy it to all three.
- `bin/sparks --help` prints its calls and an unknown argument exits 2, but a bare `sparks` runs a
  pass on the Mac's own config. Use `sparks --route <note>`, `--inboxes`, `--dry-run`, or the suite.
- `bin/redactions show` refuses inside Claude Code (`CLAUDECODE`): a transcript is read again by
  later sessions. Never work around it.
- The core is found by `lib/find_core.py`; a peer (`knowledge-commit`, `publish`) through
  `common.tool()`, never a path beside this file — and every peer has a one-line fallback with a
  case in `tests/sparks.sh`.
- A rebuilt launcher loses its Full Disk Access and Notes grants: change `launcher.c.in` only
  when the change is worth a person re-granting it.
- `/sextant` (B13) names no path of its own: every value comes from `libexec/sextant-run where`,
  every tool of another module runs as `<regatta> <tool> …`. Aurora's `weekly-run` builds the
  unattended run's allow list from the commands the skill types, and aurora's suite matches them:
  a new `<regatta>` call in the skill needs its rule there (`modules/aurora/bin/weekly-run`).
- A launch peer absent (`pickup`, `dispatch`, `keel`) is `soundings next`'s `by hand` line, never a
  command that fails (G27); its case runs from a copy of the core and this module alone
  (`tests/soundings.sh`, the root AGENTS.md's "peer absent" trap).
- `libexec/` is what a live job runs (the weekly plist without aurora; `where`, which every weekly
  run calls): it is on the root `autofinish_exclude`.
- check: `bash modules/sextant/tests/check.sh`.
