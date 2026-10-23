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
- `orca-serve-agent` runs on the Mac it installs the agent on (over ssh for a peer), so it reads
  that Mac's `${REGATTA_CONFIG}/wharf-runs/serve-label` itself and imports nothing: no core, no
  module. Its text is ASCII only (bash under a C locale over ssh read a multibyte character after a
  variable as part of its name, 2026-10-19). In a session, `--dry-run` only: it installs an
  always-on service, which is the owner's to do. It is private until the wharf-runs scrub (off
  `.helloworld/allowlist.txt`, with its suite), though written as if public.
- The files B7 moved in (everything but `orca-host`, `orca-serve-agent`, their suites and this
  module's face) are
  private until a wharf-runs scrub: off `.helloworld/allowlist.txt`. New text in them is written
  as if public already. They find the core by `lib/core_path.py` (wharf's, byte for byte: the
  check compares them) and each peer through `common.tool()`; a hard peer missing (wharf) is one
  line and exit 2, an optional one the fallback `tests/peers.sh` pins.
- `dispatch`, `dispatch-rc` and `autofinish-run` run every unattended session, this one included:
  a change to them runs `tests/test_dispatch.sh` and `tests/test_autofinish_run.sh` before it is
  saved in the main checkout. Their launchd jobs name the overlay's shim path where an overlay is
  installed, else this module in the main checkout — never a worktree's copy.
- An embedded Python heredoc inside `"$(…)"` in a bash file holds no apostrophe, not even in a
  comment: bash 3.2 parses quotes there and the whole substitution goes wrong.
- `hail` reaches live sessions: in a session, `--dry-run` only, unless the owner asked for the hail.
  Its socket road posts only to a session idle 60 s or more, re-read just before the post (a post
  mid-turn lands at the receiver's next tool boundary), and `delivered` is read back from the
  receiver, never from the socket, which answers nothing. Its suite, `tests/test_hail.sh`, posts to
  fake inboxes only. The peer bundle embeds sources with `ascii()`: Python 3.9 reading a long
  non-ASCII line from stdin fails "Non-UTF-8 code".
- `yard-node` and `node/` (the yard node's design, S2, 2026-10-22) drive a live host over
  `ssh <alias> incus …`: in a session `render`, `check` and `--dry-run` only, unless the owner asked.
  Every private value is a line under `${REGATTA_CONFIG}/wharf-runs/node/`; a template placeholder
  is `@@NAME@@`, and one alone on its line becomes one line per value. `agent.user-data.yaml` names
  nothing of Incus (its suite greps for it): the same file boots a cloud instance. All four files and
  `tests/node.sh` are private-first until the wharf-runs scrub, off `.helloworld/allowlist.txt`,
  though written as if public; the suite replays both word scans on them.
- check: `bash modules/wharf-runs/tests/check.sh`.
