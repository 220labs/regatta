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
| `bin/helm_render.py` | the ship's page and the board (through its shell, below), served locally or deployed |
| `bin/board.html`, `board.css`, `board.js` | the board's shell, read at each render and inlined with keel's foundation (tokens, art, fx) and the first snapshot: the sky strip with a boat per ship, the views (Decide, Fleet, Ships, Skippers, Reports, and the Engine room's slot) with their counts, find, the theme, the `?` keys sheet, the save strip; the 30 s poll reconciles by key and never replaces a focused field or a draft; prices effective only (`$0.07e`, a spend `spent/total`). Without keel it is the plain page |
| `bin/engine_adapter.js`, `engine.js`, `engine.css` | the Engine room, inlined with the shell: the adapter maps `engine.json` (the poll's `hosts --json`, `ops status --json`, `ops intake --json` and the two CI budget files, through the page's field allowlist, each source with its state and `at`) onto the view — the hosts, the fleet queue, the logins and CI, Intake, and what needs a hand — and a source that did not read says unread, never zero |
| `bin/sendlib.py` | `regatta helm send`: a blueprint, a handoff branch or a `--text` task handed to its scope's skipper — pinned on a pushed `claude/*` branch with `skipper: scope`, laid on the scope's yard over ssh (`wharf apply --yard`), then a wait for the pickup (`PICKED UP … this session may close`); `--listen` pulls `helm skipper --line` every 5 minutes into the sending session, `--detach` returns once laid |
| `bin/stalls.py`, `bin/stalls_tick.py` | the tick: finds unattended runs that stopped without their closing line (S1–S7), and a start path whose canary beat fails (`start path dead`), retries a step at most twice, raises the rest to the skipper or the owner. It runs on the laptop and on each scope's yard, every host judging its own runs; on a yard a raised stall, a block waiting on the owner and a question unanswered 15 minutes go out by the stall road — one row in `escalations.jsonl` per rung of the notify ladder (below), the github-issue rung one issue in the config's `helm/logbook-repo` mentioning `helm/mention`, closed when it clears, and with no wait once two passes in a row read its question answered. A yard's tick ends by pinging the dead-man's switch (`deadman ping`, lighthouse), `--braked` while the studio brake holds, `--fail` after three passes in a row Orca did not answer where a ship has an Orca Run; its passes leave the ping 40 s of the kill time; under the brake it reads no Orca and starts or stops no skipper, and the time the brake held is never charged to a skipper's clocks |
| `bin/ask`, `bin/asklib.py` | asks: an unattended run never prompts; it writes the question as a D-item and `ask relay` sends it to its skipper (Talk, SendMessage, a file, or git: an empty commit with `Ask-Skipper:`, which the skipper's host's poll hails); a dispatched run ends a minute after its RELAYED line, and `ask answer --branch` queues a fresh run of the branch that applies the answer (`ask apply --answer`); `ask answer`, `listen`, `apply`, and `ask poll`, the 5-minute bell |
| `bin/main_check.py` | the laptop's ordinary `ask poll` reads each cloned repository with a scheduled `check.yml`: main's newest completed scheduled run, its attempt's jobs and named nightly suite steps. A red or cut run gives one `main-red` Decide card and one `bug` issue in `helm/logbook-repo`, with the failed/unfinished suites and run link, no mention. Later red nights update that issue; success closes it. API faults retain the finding; the first unanswered call ends the pass; an issue write is tried, then retried once per run, and the card says when it stops; a deleted or transferred issue is filed again and a hand-closed one reopened by the next red; a repository the poll no longer reads (gone from its list, or its schedule removed) has its issue closed and its row dropped; a torn cache is one `cache unreadable` card; the board reads only `ASK_CACHE_DIR/main-check.json`, with no GitHub call. Guarded repositories and unread guards are skipped; sessions, unattended builders, dry polls, explicit `--repos` and other hosts never send these issues |
| `bin/surfaces.py`, `surfaces.schema.json` | which backend each seam takes (relay, render, live, notify, and hail's roads, which wharf-runs' `hail` reads), from `surfaces.json`; the notify ladder (below) |
| `hooks/ask_guard.py` | PreToolUse: denies AskUserQuestion in an unattended run, with the relay instruction; UserPromptSubmit: prints relays queued for the session; Notification: a banner for an ask nobody relays |
| `hooks/talk_nudge.py` | SessionStart: tells a session on a Talk host how to listen for the owner's Session-tab messages |
| `vscode/` | the VS Code extension `220labs.regatta`: the board (read from the file helm's poll writes; `helm board` only on its refresh button, or every 30 minutes at most while no board file exists) and the navigator's meetings in their own sidebar; it exports helm's notes on sessions (`RegattaApi`, apiVersion 1) for Sheepfold's rows and reads Sheepfold's session labels, marks and openers when that is installed, each whole without the other. `npm ci && npm run check` there builds the `.vsix`; `tests/check.sh` runs it |

## spacesheep plans

Helm works with no spacesheep at all and uses what a paid plan adds (facts from spacesheep.dev/plans
and the CLI 1.31.0's source, read 2026-10-24; the plan is read by `spacesheep talk status`, cached an
hour in the core's `sheep/plan.json`, which cannot tell Pro from Max):

| Plan | What helm does |
| --- | --- |
| none (no CLI) | the board and each ship's page are local files (`regatta helm board` writes the board's, `regatta helm open` serves a ship's); asks relay by SendMessage or the file backend on this Mac; Talk says "no spacesheep on this Mac" and is skipped |
| Free | the board and ship pages deploy, each publish logged in the core's `sheep/deploys.jsonl` beside keel's; above 75 % of this Mac's part of the 400-a-day cap (300 on one machine, 150 on two; the count is `sheep/machines` in the config dir, else the hosts `lighthouse/hosts` lists, else 1) they stop redeploying, the board's last deploy saying so (a ship page holds without it); a refusal for the cap from the server pauses them the same way until its retry, so keel's answer pages keep the rest; Talk relays answer "Talk needs spacesheep Pro" and the next backend takes the ask; the SessionStart nudge says nothing while the plan read is under an hour old |
| Pro | the same with a 2,000-a-day cap (750 a Mac before the pause); Talk relays to a skipper on any Mac, and sessions on the `helm/talk-hosts` Macs are told to listen |
| Max | Pro plus Streams: `helm.live stream` with a `spacesheep stream plans/<id>` process keeps a ship's page live with no redeploys. A refused stream (`plan_required`) keeps its process running, so helm also checks the server's list and redeploys while the stream is absent or silent for 2 minutes |

The count is this Mac's; the cap is the account's, and deploys from other tools are not counted.

## The notify ladder

Which channel pings when is the owner's, in `surfaces.json`'s `notify` seam: a ladder per kind of message
(`update`, `question`, `stall`), each rung a channel with `after` (from the message's first moment) and an
optional `when: present`, plus quiet hours (in `quiet.tz`, an IANA zone, else the yard's own local time) and an hourly cap on
what reaches a phone. A `quiet` or `cap` that is there and does not read holds every phone rung until it does.

```json
"notify": {
  "question": [{"via": "charterer"}, {"via": "github-issue", "after": "10m"}],
  "stall":    [{"via": "github-issue", "after": "10m"}],
  "quiet":    {"hours": "22:00-07:00", "except": ["stall"]},
  "cap":      {"per_hour": 6}
}
```

A rung fires once per message while it is unanswered, one rung per channel; an answer (or a block that no
longer waits on the owner) withdraws the rest and closes the issue on the second pass in a row that reads it answered (one misread never closes it). Each firing is a row in the yard's `escalations.jsonl`. A kind with no ladder behaves as
before it: the host's `notify.<host>` row is read as one rung, sent as before (its backends in order, the first
that delivers), and a question's is `charterer` then that rung. Quiet hours and the cap hold an issue's comments
too, a close's included; a seam that does not read holds every rung and is carded on the board. A host row
that names `github-issue` is held whole by quiet hours and the cap, its banner too, as `notice()` may fall
through to the issue. Write a ladder, `quiet` or `cap` into the shared file only once every host runs this
version: an older `ask backends` cannot print a ladder (an older stall road reads only the host rows, and is
unaffected). The channels: `github-issue` and `banner` deliver today; `charterer`, `vscode-question`,
`claude-app`, `orca-app`, `telegram` and `spacesheep-app` are accepted and say why they have no road yet.
`ask backends` prints the seam and any problem with it.

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
  given a build box's run cap). Stalls also reads builder users' `regatta/fleet-ssh` rows
  (`antigravity@<host>`, `codex@<host>`, and `@localhost` only for this Mac's own `<host>-<vendor>` rows);
  the launcher record supplies their last reply and end, with no Claude transcript or registry required.
  `helm send` reaches a yard that is a named node's peer, and every
  confidential send's yard, by `wharf-runs/nodes/<name>/ssh` alone (through wharf-runs' orca-host),
  never `wharf-runs/ssh`.
  Talk's peer relays and live-run reminders share hail's message peers through wharf-runs' shared message reader:
  the cached fleet hosts ref (`dispatch-queue hosts get --cached`), with configured aliases taking
  precedence. An added name (a kick alias, a node folder, a fleet row) that is a confidential yard or
  node, and a sample older than 24 hours, is skipped (a configured `wharf-runs/ssh` peer is reached as before); an unavailable
  registry drops every discovered name. Without that reader, they keep configured placement aliases.
  Stop-hook peer reads share one ten-second budget, every peer asked at once with the whole budget
  left, so an unreachable alias cannot starve the rest nor a slow live one be cut short. Stalls and placement keep their existing peer lists.
- The Talk service: `helm/talk-url` (else `$SPACESHEEP_URL`; absent, the talk relay is off and says
  so) and `helm/talk-hosts`, the Macs whose sessions are told to listen (`$CLAUDE_TALK_HOSTS` wins;
  absent, none).
- The guarded repos come from keel's gate; without keel, from the core's registry `guarded` and
  `regatta/guarded`.
- The stall road (a yard's tick, skipper-resilience S8): `helm/logbook-repo` (`owner/name`, the repo
  the issues open in: the logbook, a ship's record of every watch's alarms and stalls) and
  `helm/mention` (the line each issue's body starts with). Optional: absent, an escalation is
  written with road `none` and nothing is opened. The key was `helm/inbox-repo` until 2026-10-24
  and the old file is no longer read: `inbox` names strangers' contacts only. Where that repo is (the issue
  road): an operational issue (a stall, an outage, a bug) goes to the project's own private repo,
  never a public one and never the private inbox that holds strangers' contacts; for a deployment of
  Regatta, a private fork of it or a new private repo. A stall mentions the owner, since only a
  mention pushes to a phone, and so does lighthouse's CI budget alarm, filed through this road (`ask`'s `issue_open`), and a login's first overdraw of a week (lighthouse's `account overdraw-log`, through `ask`'s `issue_note`: one issue a login and week, labels `overdraw` and `budget`, later ones a comment); a bug mentions nobody. One GitHub Project can be the dashboard: a view
  per label (`contact`, `stall`, `deadman`, `budget`, `bug`), fed by one auto-add workflow per repo, each
  filtered by its label, with issues already open added by hand once.

`config-keys` lists the three keys of helm's own that must be there, which `regatta check` reports
where missing; the stall road's two are optional and not listed.

## Peers

Every edge goes through the core's `common.tool()`, and an absent peer is a line, never a stack
trace (`tests/peers.sh` runs helm with none):

| Peer | Used for | Without it |
| --- | --- | --- |
| keel (`keel`, `sheep`, `hooks/sheep_gate.py`) | reading and writing a doc's D-items; the spacesheep key; the guarded-repo list; the lookout's pass and cards (`lookout --if-due`, `lookout --status --json`) | `ask relay` refuses in one line; the board has no doc or lookout cards; the poll skips the lookout in one line; the guarded list is helmlib's fallback copy |
| wharf-runs (`dispatch`, `dispatch-rc`, `harness` and its adapters, `autofinish`, `autofinish-run`, `wharf`, `blueprintlib.py`, `hail`) | the runs the tick judges and retries; a ship's blocks; the poll's `hail subs --fulfil` and `hail mail --pull` | stalls judges nothing and says so; the tick applies no ship; `--done-when` refuses; the poll skips the fulfil and the pull in one line |
| plumb (`usage-report`, `tier_check.py`, `attention.py`) | a session's cost, the week line, the relay row | no cost, no week line, the row written by hand (G26) |
| wharf (`session_status.py`) | the Stop hook's reading of a closing line | an unread line counts as no line |
| the core's `gate` | the tick's classifier for an unsure stall | no label; the stall carries the load error |

## Tests

`bash modules/helm/tests/check.sh`: `peers.sh` (no peer, the schema, `install.sh` against a stub
launchctl), `hooks.sh` (both hooks fed their events), then `test_ask.sh` and `test_helm.sh`, each under rename S5's old and new names.
