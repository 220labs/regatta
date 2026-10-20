# modules/atlas — knowledge with three lifecycles

Read `README.md` first: it is the chart. For an agent:

- The vault and the layer are found by `lib/atlaslib.py` alone (the config dir's `atlas/vault`
  and `atlas/layer`, their env overrides); never a literal path to either, in code or in a skill.
- A hook here never costs a session: `bulletin.py` and `vault_commit.py` exit 0 with one stderr
  line on any failure, the core missing or a key missing included. The bulletin reads the config
  dir directly so a core that cannot load does not take it down.
- A peer (keel, wharf) only through `atlaslib.tool()` → `common.tool()`, with the fallback
  README's table names, and a case for each side in `tests/atlas.sh`.
- A skill reaches its tools as `../../bin/<tool>` or `../../hooks/<hook>` from its base
  directory, as one path: a skill linked in by hand resolves through the link, `cd` would not.
- check: `bash modules/atlas/tests/check.sh`.
