# keel — decisions batched, answered inline, taken back as commits

A doc asks its owner for decisions as a numbered D-list (`➤ Recommended:`, an empty `➤ Answer:`);
the owner answers in the doc, on its form page or its spacesheep page, and the answers come back
to the session as commits. Was `memo` until 2026-10-14; moved in from the overlay on 2026-10-19
(regatta-modules B4).

| Piece | What it does |
| --- | --- |
| `bin/keel` | the D-list: `lint`, `line` (the one hand-over line), `pull`, `status`, `step`, `list`, `open`, `build` and `serve` (the form), `sheep` (the page) |
| `keel lookout` | the watch over the docs with open items, one pass per 15 min from helm's ask poll: a Save on the page, an answer on GitHub, new comments, new words in a thread a session talks in → the doc's session hailed once (a pointer); no run in sight on any host (the host rule, routed comments S3: a host acts where the branch's run is — a live session harness names here, the queue's `running_on` — and leaves a run elsewhere, a recent checkpoint push no host here reads included, to its host), the answers on the branch and an open step waiting on them, or new words in a talking thread, → a claim, one full pass, then a seed off the branch's tip and one run (`pickup seed --beside`, `dispatch`; the branch never written; a talk run's brief quotes the thread and answers it with `sheep reply`), else a card. Every Save is taken in, its viewer recorded (`Saved-By:`). Ships disarmed (`--arm`); `--status` lists the cards and the runs |
| `keel sheep wait`, `reply`, `threads` | a conversation on a course page: `wait` (the session's background shell) wakes within about 35 s of new words in a thread and prints each thread, taking nothing in; `reply <doc> <thread id> <text\|->` answers in it as Claude Code, after which every pull leaves the thread alone until `--take`; `threads` prints the open ones |
| `keel routed check`, `line`, `mark`, `status`, `bench`; `keel settle` | routed comments (docs/routed-comments-2026-10-26.md, S2): a doc routed for work carries a `Routed:` line naming its page and branch, written by `pickup seed` and `pickup brief` in their own commit (`routed line`), so every host reads the page from the doc. `check` (exit 3) holds new work — `pickup seed` runs it — while an act thread on the page is unreflected, an owner thread unjudged (judged on the spot; held while the `keel.comment` gate row is absent or off) or a Save the doc lacks; `settle <doc> <id|Dn|save:seq> --why` is the attended way past it (a Save: a `> **Settled.** Save <savedAt>` line in the doc); `mark` posts one of the seven `memo:` marks, which count only as this tool's own (`via` claude, or an id in the pin's `sent`); `status` reads this host's routed.jsonl. The lookout reads a routed page on every host for 14 days, until its line is taken back; the line's page wins over a pin's own. The tiers (S4): the lookout judges an owner's new words in a thread (the rules, then one `keel.comment` call a page) and starts a plain ask on an unshared page (T1: a `request`, marked `routed into` once dispatched), offers a held or unclear one with a `would start` mark (T2: `go` starts it, `no` closes it), and ends a run on the owner's `stop` under its `starting:` reply; `bench` runs the judge's ten comments through it (it spends a call). After landing (S5): a routed doc `main` holds is read under `main`'s key — a T1 ask, or an answer committed on `main`, seeds a run off `main`; a question there hails this Mac's standing manager (helm), else a card |
| `keel checkin` | the crew's mark on a Course doc's Status line: ` · crew: <who> since <date>`, then `done` |
| `keel sheep pull --plumb` | a page's Saves onto the doc's branch by plumbing — no checkout; fast-forwarded first, refused on a held or dirty worktree, pushed |
| `bin/paste-paths` | the Stop-hook reply lint: absolute paths in a paste, the hand-over line on a D-list, the closing and WAITING lines, the relay of an unattended run's ask |
| `bin/owed` | is a thing a reply listed as owed already done? read-only |
| `bin/sheep` | sessionpipe on this Mac with the private repos gated out |
| `hooks/doc_answers.py` | UserPromptSubmit: a prompt that says a doc is answered fetches the branch first |
| `hooks/sheep_gate.py` | the gate in front of every sessionpipe hook entry: the private repos and every confidential scope stay on the Mac |
| `skills/keel` (`/keel`) | hand a doc's D-list over and take the answers back |
| `keel render` | a PNG per ```` ```mermaid ```` fence and per Excalidraw figure, offline in headless Chrome, so a session looks at its diagram before the hand-over; a figure's `docs/<stem>/<name>.excalidraw` → its committed `.svg`, in the doc's `Figure style:` (soft, clean, sketch) and `Figure palette:` (course, the page's dark theme; deck, white for outside; excalidraw). The page inlines a linked `.svg`, sanitised, with no library; `lint` fails a stale one. Excalidraw's drawing library, `@excalidraw/utils` (MIT, 19.6 MB), is fetched once into keel's cache folder, beside Mermaid's, and sha-pinned |
| `skills/figure` | draw that figure from Python: the emitter (bound labels, measured text, fixedPoint arrows), the palette and panel grid. Off the allowlist for now |
| `vendor/mermaid/` | the Mermaid pin (version, sha256, MIT license): fetched once into the cache; it draws each fence at build time, in headless Chrome, and the page carries the pictures, never the library |
| `tests/check.sh` | the six suites; no network |

Peers, each optional and found through the core's `tool()` (the design's G9–G11, G24, G33):
helm's `asklib.py`, `surfaces.py` and `ask` (without them no relay check and no listener
reminder; a relayed answer reads as the owner's), wharf-runs' `dispatch-rc` (no run told alive),
atlas's `docs-index` (no record banner stamped), lighthouse's `claude-settings` (`sheep gate`
refuses to write settings), wharf-runs' `hail` and `harness` (the lookout reaches no session and
records the event as if none were live), `pickup`, `dispatch` and `autofinish` (no run starts: a
card; `LOOKOUT_HAIL`, `LOOKOUT_HARNESS`, `LOOKOUT_PICKUP`, `LOOKOUT_DISPATCH` and
`LOOKOUT_AUTOFINISH` stand in for them).

## spacesheep plans

keel's road back is the doc on GitHub; spacesheep adds the page (facts from spacesheep.dev/plans,
read 2026-10-24):

| Plan | What keel does |
| --- | --- |
| none (no CLI) | the hand-over line's GitHub link, and `keel serve`'s form on 127.0.0.1 for answering in a browser tab; `sheep` has nothing to gate |
| Free | the spacesheep page: the form, comments, versions, and its Save (`live_events`, not listed as paid: assumed on Free, unverified). Each publish goes in the core's `sheep/deploys.jsonl`, shared with helm; keel never skips a page, warns at 90 % of this Mac's part of the 400-a-day cap (360 on one machine, 180 on two), once per crossing, and names a refusal for the cap as one. In the checkpoint's hook the warning is the row's `note`, which the turn's 🐑 note shows, and the plan is read from its cache only. helm's redeploys pause first, at 75 %. A conversation in a page's threads (`sheep wait`, `sheep reply`) is the only one on Free: a comment publishes nothing, so it counts against no cap. The Session tab's Talk needs Pro, so `sheep check` reads a dead control daemon here as expected, not a failure |
| Pro | the same with a 2,000-a-day cap; sessionpipe's session reporting (Pro's session hooks), which `sheep gate` keeps the private repos out of |
| Max | nothing more for keel |

## Private values

Nothing here names a host, a login, an account or a person. What is private reaches the module as
files in the regatta config dir (`$REGATTA_CONFIG`, else `.config/regatta` in the home folder),
written by whoever installs the modules (on the owner's Macs, the overlay's `bootstrap.sh --config`).
keel reads its own keys and three of its peers', each without loading the core where a hook needs that.

| Key | What | Read by | Absent |
| --- | --- | --- | --- |
| `regatta/owner` | the name answers, notes and replies are signed with (`**<owner>, <date>:**`, `Taken in chat (<owner>, …)`) and messages address | `keel`, `paste-paths`, `doc_answers` | `Owner` signs; messages say "the owner" |
| `regatta/guarded` | the repos whose sessions never leave the Mac, beside `transcripts` | `sheep_gate`, so `sheep`, `keel sheep`, helm | only `transcripts`; where the overlay is installed, the gate drops every event |
| `lighthouse/vaults` | the vault folders whose `_secrets` never leaves | `sheep_gate`, `owed` | any `_secrets` folder |
| `atlas/layer`, `atlas/vault` | the two knowledge repos (first item: the name) | `keel` (knowledge-commit's hint; the layer's `rules/` never mirrored) | no repo gets either |
| `keel/machines` | `<host>:<board name>` per line, sessionpipe's name for each Mac | `sheep` | the host name itself |
| `keel/reply-signature` | a line under every `keel sheep reply` (its lines joined with a space) | `keel` | no line |
| `keel/owner-email` | the owner's address, where no reply of this tool's on a page carries it: a comment from it is the owner's (routed comments) | `keel` | every comment no agent wrote reads as the owner's, as before |
| `keel/course-site`, `keel/course-mcp` | the course page's web app and MCP endpoint | `keel` | spacesheep's public addresses |
| `regatta/overlay` | the overlay checkout (the core's marker): `sheep` reads a `.env` there last | `sheep` | none |

The suites run on a scratch config dir (`tests/config.sh`: the owner `Sam`), so they pass with no
overlay and an empty `REGATTA_CONFIG`.

Install: `claude plugin install keel@regatta` once it is listed (it needs the core, `regatta`).
From a clone: `sh modules/keel/install.sh --check` says which peers are found.
