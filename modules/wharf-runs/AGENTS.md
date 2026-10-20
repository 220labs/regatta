# modules/wharf-runs — runs across the fleet

Read `README.md` first: it is the chart. For an agent:

- Which Mac is which is config, never code: a host name, an ssh alias or a Tailscale address is
  a line in `${REGATTA_CONFIG}/wharf-runs/`, read through the core's `config_read`. Tests use
  made-up names (`laptop`, `studio`) and documentation addresses (192.0.2.0/24, 198.51.100.0/24).
- `orca-host` is the one file `--on` copies to a peer, so it finds the core itself (an inline
  copy of helloworld's `lib/find_core.py`) and imports nothing else from this module.
- A peer tool (`scopes`, `account`) is reached through `common.tool()`; its absence is the line
  the README names, never a stack trace.
- `orca-host` changes a live Orca: in a session, `check` and `--dry-run` only, unless the owner
  asked for the change.
- check: `bash modules/wharf-runs/tests/check.sh`.
