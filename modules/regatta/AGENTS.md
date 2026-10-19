# modules/regatta — the core

Read `README.md` first: it is the chart. For an agent:

- Everything here is loaded by every other module and, on the overlay's Macs, by every hook
  through a source shim: Python 3.9, stdlib only, nothing at import time that can raise but a
  missing core.
- A new private path is a `${REGATTA_CONFIG}/<module>/<file>` default behind an environment
  override, never a literal; the override is for a suite or one shell, never exported (an
  exported `GATE_TABLE` turns `gate set`'s on-main guard off).
- An optional peer is reached only through `common.tool()`, or `common.module_path()` for a file
  outside a tool dir (helloworld's pre-push guard, a wharf template); its absence is a named fallback.
- Shims are generated (`regatta shim`); a change to their text changes `bin/regatta` and every
  shim is regenerated in the same change.
- check: `bash modules/regatta/tests/check.sh`.
