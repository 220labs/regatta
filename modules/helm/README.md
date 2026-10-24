# helm — project management

Helm breaks a large idea into **ships** (a piece of work with a due date and a cost), their
**blocks** and **tasks**, and keeps one record of who is doing what: the agent sessions working
unattended, the **skipper** (the session that manages a ship's runs), and the people a task waits
on. It is the console, the tick that keeps unattended runs moving, the road an unattended run's
question takes instead of a prompt nobody would answer, and the board that shows it all.

| Piece | What it does |
| --- | --- |
| `regatta helm …` (`libexec/helm`) | the console: `ship`, `task`, `report`, `eta`, `show`, `state`, `board`, `render`, `digest`, `tick`. Off PATH: an installed Kubernetes `helm` would win a bare call, so the core's CLI runs it |
| `bin/helmlib.py` | the store: one directory per ship (`plan.json`, written by the skipper; `events.jsonl`, append-only), and `state()`, the merged view every page reads |
| `bin/leaselib.py` | the lease on a ship laid with `wharf apply --yard`: `plans/<id>/skipper.json` says whether the yard or the scope's skipper holds it, at which generation; every acting verb (`ask answer --plan`, `ask relay --plan`, `ask apply --plan`, `wharf apply --yard --plan`, `helm send --mark`, `autofinish-run` under `DISPATCH_SHIP`) refuses a caller at another one, exit 4. `regatta helm skipper --hold|--renew|--ships|--status|--stand-down` are the skipper session's verbs on it |
| `bin/skipperlib.py`, `libexec/skipper-run` | the scope's skipper: one Claude session per scope on the yard host, started by the tick as a one-shot launchd job (`regatta helm skipper --start`, refused inside a session) when a ship the yard holds needs one, on a login every repo of the scope allows; run on Opus `high`; ended by `--stop` when no ship has needed it for 30 minutes, while a ship needs it, at its first quiet pass (idle 10 minutes, no question of its own open) once 8 h old or past 200k tokens of context after its first hour, at the 04:00 pass once 24 h old whether quiet or not, or when its lease lapses or it goes deaf — its ships back to the yard, its open questions re-hailed to the next one. Three failed starts in a row are the stall `skipper won't start` |
| `bin/helm_render.py` | the ship's page and the board (six columns, the timeline), served locally or deployed |
| `bin/sendlib.py` | `regatta helm send`: a blueprint, a handoff branch or a `--text` task handed to its scope's skipper — pinned on a pushed `claude/*` branch with `skipper: scope`, laid on the scope's yard over ssh (`wharf apply --yard`), then a wait for the pickup (`PICKED UP … this session may close`); `--listen` pulls `helm skipper --line` every 5 minutes into the sending session, `--detach` returns once laid |
| `bin/stalls.py`, `bin/stalls_tick.py` | the tick: finds unattended runs that stopped without their closing line (S1–S7), retries a step at most twice, raises the rest to the skipper or the owner. It runs on the laptop and on each scope's yard, every host judging its own runs; on a yard a raised stall, a block waiting on the owner and a question unanswered 15 minutes go out by the stall road — one row in `escalations.jsonl` and one issue in the config's `helm/inbox-repo` mentioning `helm/mention` (`notify.<host>: ["github-issue"]`), closed when it clears. A yard's tick ends by pinging the dead-man's switch (`deadman ping`, lighthouse), `--braked` while the studio brake holds, `--fail` after three passes in a row Orca did not answer where a ship has an Orca Run; its passes leave the ping 40 s of the kill time; under the brake it reads no Orca and starts or stops no skipper, and the time the brake held is never charged to a skipper's clocks |
| `bin/ask`, `bin/asklib.py` | asks: an unattended run never prompts; it writes the question as a D-item and `ask relay` sends it to its skipper (Talk, SendMessage or a file); `ask answer`, `listen`, `apply`, and `ask poll`, the 5-minute bell |
| `bin/surfaces.py`, `surfaces.schema.json` | which backend each seam takes (relay, render, live, notify), from `surfaces.json` |
| `hooks/ask_guard.py` | PreToolUse: denies AskUserQuestion in an unattended run, with the relay instruction; UserPromptSubmit: prints relays queued for the session; Notification: a banner for an ask nobody relays |
| `hooks/talk_nudge.py` | SessionStart: tells a session on a Talk host how to listen for the owner's Session-tab messages |

## Install

```bash
sh modules/helm/install.sh --check      # the core, surfaces.json, each peer and what is lost without it
sh modules/helm/install.sh --schedule   # the ask poll, every 5 min (launchd)
sh modules/helm/install.sh --remove
```

Or `claude plugin install helm@regatta` for the session face.

## Private values

- `surfaces.json`: `$SURFACES_FILE`, else `helm/surfaces.json` in the regatta config dir
  (`${REGATTA_CONFIG:-~/.config/regatta}`); absent, the defaults in `bin/surfaces.py`. The shape
  is `surfaces.schema.json`. A row is switched with `ask backends --set relay=file` on a copy in a
  worktree, never through the config dir's link to a primary checkout (refused: a switch is
  reviewed and dated).
- The login registry (`ask`'s account labels): `$ACCOUNTS_FILE`, else `lighthouse/accounts.json`
  in the config dir, as lighthouse reads it.
- People: the core's `regatta/owner` names the owner (the WAITING line, the routes an answer of the
  owner's arrives on, the board's first column); `helm/people`, one name per line with the owner
  first, names everyone a human task may wait on (`--by`, `@name` in a TODO line, the board's second
  column). Absent, the owner alone.
- Hosts: the core's `regatta/laptop` (the ask poll's bell and its sweep run there; the default
  banner row) and `wharf-runs/ssh` (`<host>:<ssh alias>`: the peers stalls reads, and the hosts
  given a build box's run cap).
- The Talk service: `helm/talk-url` (else `$SPACESHEEP_URL`; absent, the talk relay is off and says
  so) and `helm/talk-hosts`, the Macs whose sessions are told to listen (`$CLAUDE_TALK_HOSTS` wins;
  absent, none).
- The guarded repos come from keel's gate; without keel, from the core's registry `guarded` and
  `regatta/guarded`.
- The stall road (a yard's tick, skipper-resilience S8): `helm/inbox-repo` (`owner/name`, the repo
  the issues open in) and `helm/mention` (the line each issue's body starts with). Optional: absent,
  an escalation is written with road `none` and nothing is opened.

`config-keys` lists the three keys of helm's own that must be there, which `regatta check` reports
where missing; the stall road's two are optional and not listed.

## Peers

Every edge goes through the core's `common.tool()`, and an absent peer is a line, never a stack
trace (`tests/peers.sh` runs helm with none):

| Peer | Used for | Without it |
| --- | --- | --- |
| keel (`keel`, `sheep`, `hooks/sheep_gate.py`) | reading and writing a doc's D-items; the spacesheep key; the guarded-repo list; the lookout's pass and cards (`lookout --if-due`, `lookout --status --json`) | `ask relay` refuses in one line; the board has no doc or lookout cards; the poll skips the lookout in one line; the guarded list is helmlib's fallback copy |
| wharf-runs (`dispatch`, `dispatch-rc`, `harness` and its adapters, `autofinish`, `autofinish-run`, `wharf`, `blueprintlib.py`, `hail`) | the runs the tick judges and retries; a ship's blocks; the poll's `hail subs --fulfil` | stalls judges nothing and says so; the tick applies no ship; `--done-when` refuses; the poll skips the fulfil in one line |
| plumb (`usage-report`, `tier_check.py`, `attention.py`) | a session's cost, the week line, the relay row | no cost, no week line, the row written by hand (G26) |
| wharf (`session_status.py`) | the Stop hook's reading of a closing line | an unread line counts as no line |
| the core's `gate` | the tick's classifier for an unsure stall | no label; the stall carries the load error |

## Tests

`bash modules/helm/tests/check.sh`: `peers.sh` (no peer, the schema, `install.sh` against a stub
launchctl), `hooks.sh` (both hooks fed their events), then `test_ask.sh` and `test_helm.sh`, each under rename S5's old and new names.
