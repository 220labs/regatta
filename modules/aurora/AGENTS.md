# modules/aurora — Aurora Borealis, the night job

Read `README.md` first: it is the chart. For an agent:

- Nothing here names a path, host or person of the owner's: the core, the peers and the two
  knowledge repos are found at run time (`bin/weekly-run`'s "Where things are"); a private
  value is a config key (`aurora/host`, atlas's `atlas/layer` and `atlas/vault`).
- A peer (atlas, wharf, plumb, wharf-runs) only through `regatta which` / `<regatta> <tool>`,
  never a relative path: the module must work whichever lands first. A missing peer fails its
  own step with one line, and the night goes on.
- A skill reaches this module's tools from its base directory as one path
  (`<base directory>/../../bin/weekly-run where`), never through `cd`.
- The skill sections are read by path by the model, from `skills/aurora/sections/`: a section
  renamed or added is one row in `skills/aurora/SKILL.md`, its place in `weekly-run`'s `ORDER`
  and its cadence in `due`.
- `weekly-run`'s allowlist must hold every command the skills call (`tests/aurora.sh` checks).
- check: `bash modules/aurora/tests/check.sh`.
