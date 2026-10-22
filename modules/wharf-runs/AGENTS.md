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
- The files B7 moved in (everything but `orca-host`, its suite and this module's face) are
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
- check: `bash modules/wharf-runs/tests/check.sh`.
