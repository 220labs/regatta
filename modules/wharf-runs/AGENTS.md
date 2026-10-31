# modules/wharf-runs — runs across the fleet

Read `README.md` first: it is the chart. For an agent:

- Public since the scrub (2026-10-22): every file here is on `.helloworld/allowlist.txt`, and both
  scans (the gate, and the overlay's substring grep of its private-names list) must stay clean.
  Owner, host, login and overlay path are config keys (README, "What it reads"); fixtures use
  `laptop`, `buildbox` (alias `buildbox-ssh`), Sam, `shop`, `example.invalid`.
- Which Mac is which is config, never code: a host name, an ssh alias or a Tailscale address is
  a line in `${REGATTA_CONFIG}/wharf-runs/`, read through the core's `config_read`. Tests use
  made-up names (`laptop`, `buildbox`) and documentation addresses (192.0.2.0/24, 198.51.100.0/24).
- `orca-host` is the one file `--on` copies to a peer, so it finds the core itself (an inline
  copy of helloworld's `lib/find_core.py`) and imports nothing else from this module.
- A peer tool (`scopes`, `account`) is reached through `common.tool()`; its absence is the line
  the README names, never a stack trace.
- `orca-host` changes a live Orca: in a session, `check` and `--dry-run` only, unless the owner
  asked for the change.
- `orca-serve-agent` runs on the Mac it installs the agent on (over ssh for a peer), so it reads
  that Mac's `${REGATTA_CONFIG}/wharf-runs/serve-label` itself and imports nothing: no core, no
  module. On Linux it writes the unit `node/agent.user-data.yaml` writes, and its suite diffs the
  two line for line: a change to one is made in the other. Its text is ASCII only (bash under a C locale over ssh read a multibyte character after a
  variable as part of its name, 2026-10-19). In a session, `--dry-run` only: it installs an
  always-on service, which is the owner's to do.
- The tools beside `orca-host` find the core by `lib/core_path.py` (wharf's, byte for byte: the
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
  `tests/node.sh` are off `.helloworld/allowlist.txt` until listed (root AGENTS.md, Rules) and
  written as if public; the suite replays both word scans on them (N6).
- `clock` (knowledge-layers S7) changes a live scheduler with `schedule` and `fire`: in a session,
  `list`, `check`, `board` and `--dry-run` only, unless the owner asked for the job. Like `yard-node`
  it is off the allowlist until listed and written as if public: hosts, labels, the workspace and the
  script-job list are `wharf-runs/clock-*` config keys (its header); without `clock-scripts` the
  modules' own script jobs are the default (`DEFAULT_SCRIPTS`). Its suite, `tests/test_clock.sh`, runs
  against stand-ins for orca, launchctl (here and on the peer), ssh and scutil only, with the
  fixture's `laptop` and `buildbox`.
- Claude Code deletes a claude version that a Remote Control host still runs, and the host then
  fails every new session `spawn error: ENOENT`. Its cleanup (every claude start) keeps the
  cleaner's own version, the symlink's, each locked one and the 2 newest others, and the version
  lock has a single holder: once the first process on a version exits, no other process protects
  it (2.1.309's bundle, read 2026-10-23). `rc-hosts --check` (exit 1) and `--broken` (exit 3) fail on
  such a host, and `--reap` restarts it once every session has been idle 10 minutes (on a Mac the
  `wharf-runs/rc-hosts` key leaves out, its hosts are unwanted: `--check` and `--reap` leave them to retire,
  and `--broken` alone still fails one). The probes and D1
  (answered A: the cleanup is not held off; revisit if `--broken` posts monthly): the private repo's
  `docs/rc-hosts-versions-2026-10-23.md`.
- check: `bash modules/wharf-runs/tests/check.sh`.
