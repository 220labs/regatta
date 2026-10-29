# Changelog — keel

## Unreleased

- The keel skill's `seeded` path: a full host queues the step (dispatch-queue S3), so the session ends on
  dispatch's closing line with nothing to relay; paste-paths' suite proves that line passes the Stop
  lint as the pending kind.
- `KEEL_BRIEF_DAY` (YYYY-MM-DD) pins the day `pickup brief`'s same-day guard reads, for suites that cross midnight.
- Codex and Antigravity sessions reach spacesheep through the same privacy gate as Claude Code's:
  `sheep gate` writes sessionpipe's entries, gated, into Codex's `hooks.json` and Antigravity's
  `config/hooks.json` beside Orca's, seeded from Claude Code's command (no
  `sessionpipe install --codex` and its ungated window). `sheep_gate.py` reads Antigravity's
  `workspacePaths` and always answers it with JSON (`{}` when it sends nothing: silence there is a deny).
  `check` counts both files and notes Codex entries not yet trusted in `codex` → /hooks;
  `forget-private` forgets a private session by its harness.
- Every command keel prints for a session to run names keel by its module path (`keel_cmd()`), never
  `memo`, which no PATH holds: `keel line`'s listener hint said `memo sheep wait`, and the session got
  exit 127 (peer-manager-relay, 2026-10-26). The same goes for `sheep pull`, `serve` and `pull` in the
  page-state, stale-page and wait messages. The wait's own lines and usage read `keel sheep`.
- The listen reminder (paste-paths' `manager_findings`) counts a manager's live runs on peer Macs too,
  through helm's `asklib.peer_runs` (one ssh a peer, cached 10 minutes for every session here). A laptop
  manager of a build-box run with a plan page is told to start `ask listen`, as one of a local run is.
- The hand-over line carries both spacesheep links: first the page at the local mirror (`course` with
  D-items, `local` without), last the same page on spacesheep.dev as `space` (the owner, 2026-10-26). With
  no local address `course` is the internet page and stands for `space`. The Stop hooks never read the
  mirror to say what is owed; they refuse `course` and `local` together, a `local` link on the internet and
  a `space` link at localhost, and pass a dead localhost link beside the doc's `space`.
- Mermaid is drawn at build time, not in the reader's browser: a page with a diagram no longer inlines
  mermaid.min.js (3.3 MB of a 3.66 MB page, which would not open through the local mirror, 2026-10-26).
  Each fence is drawn under headless Chrome in Mermaid's light and dark themes with SVG text labels,
  passed through `safe_svg`, and shown as two data: `<img>`s, the CSS picking the theme's one; the
  pictures are cached per diagram in the keel cache's `mermaid-svg/`, so only a new diagram costs a
  browser run (about 4 s). A fence Mermaid cannot parse, or whose labels need HTML, is cached as such
  and shows its source; without Chrome or the pinned build, or for 10 minutes after a browser run that
  returned nothing (`mermaid-svg/render.failed`), every fence does. `keel render`'s PNGs are unchanged.
  A page that went up with a fence as source for such a passing reason (no Chrome, another keel drawing,
  the hook's time spent) is redeployed once drawing can work again (the pin's `mmd_missed`); the hook
  draws only within its own budget, `keel serve`'s startup check draws nothing, and the pages already
  up are redeployed without the library (PAGE_FMT 9).
- Copy browser link: a doc's spacesheep page, opened through the local mirror (a VS Code tab), shows one
  more button that copies the page's address on the site, for a browser where the site's passkey signs.
  Hidden on spacesheep and the phone. The address travels in base64 past the mirror's rewrite; a page
  deployed for the first time has none yet and is redeployed once with it (PAGE_FMT 10, the pin's
  `link_shown`). Where the tab refuses the copy, the status pop-up opens with the address to copy by hand.
- Routed comments, S2's landing review: a `stopped` mark keeps its thread owed; `keel routed check|line
  --routing` refuses an unattended caller; `lookout_release` unroutes only a `Routed:` line its own brief
  wrote, never an earlier routing's.
- Routed comments, S2 (docs/routed-comments-2026-10-26.md): a doc routed for work keeps being read after
  its run starts and after it lands. `keel routed line` (pickup's call) writes a `Routed: <ISO time> ·
  page <space id> · <branch>` line under the doc's `Status:` in the routing commit itself, and `--drop`
  takes it out again (`lookout_release` passes `pickup brief --unroute`). `sheep threads`, `sheep reply`
  and `sheep pull` (`--plumb` too) read the page from the pin, else from that line, so a host that never
  deployed the page reads it. `comment_threads` keeps `owner` (the comment's `author_email` against the
  address of a reply this tool posted, else the overlay's new `keel/owner-email`; the address is never
  kept), `own` (`via == "claude"` or an id in the pin's `sent`) and `shared` (more than one account on the
  page). A mark counts only as this tool's own: one typed by anyone else counts for nothing; a pull's
  marks now go into `sent`. `talking` is derived from the page too: our non-mark reply under an untaken
  thread. Seven marks (ROUTED_MARKS), three of them taken (`routed into`, `closed by`, `settled by`);
  `keel routed mark` posts one. The gate, `keel routed check <doc>` (exit 3), holds new work while an act
  thread is unreflected, an owner thread unjudged (judged on the spot: rules first, then the
  `keel.comment` gate row; with the row absent or off, held) or a Save the doc lacks; `pickup seed`
  runs it. `keel settle <doc> <id|Dn> --why` (attended only, exit 3 under `CLAUDE_UNATTENDED`) posts the
  settled mark and writes `> **Settled.**` into the doc. `keel routed status` reads this host's
  routed.jsonl. The lookout reads every routed page for 14 days on every host (about 5 s a pass for the
  `git log -G` over the repos), its first read counting each open thread new; a host with no key gets
  one card. `not_owners_answer` excuses the routing commit (`Seed:`, `Brief:`, `Routed-By:`) and a
  review stamp.
- Routed comments, S2's finish review: the `Routed:` line's page wins over this host's pin of another
  page (a run's first checkpoint mirrored the doc to a second, empty one): the pin is pointed at the
  line's page and says which it left, and `sheep` deploys a routed doc to that page from the first
  checkpoint on. A host's first read of a routed page wakes only a talking thread
  the owner wrote in after our reply. `keel settle <doc> save:<seq>` settles a Save no pull can take,
  with a `> **Settled.** Save <savedAt>` line the gate reads on every host; the gate's refusal names each
  Save so. On the text form a taken mark counts by its words for taking again (never for the gate). A
  held verb under a `would start` offer is read before go/no. `keel routed line --dry-run` logs nothing,
  `--routing` passes the start's own threads. A line `pickup brief --unroute` took back names no page. A
  `held` judge row is judged again; a key keeps its newest line; `routed mark routed|closed` refuses an
  unattended caller; a brief's `.dir/` path is kept whole; the last step names keel from `~/`.

- Figure palettes, beside the styles: `course` (the default) draws a figure in the course page's dark
  colours, white text and saturated orange-to-violet-to-teal fills; `deck` is white with a modern set for
  outside presentations; `excalidraw` keeps the source's pastels. A doc's `Figure palette:` line picks,
  `render --palette` previews, the render mark names the palette and `lint` calls another one stale (a mark
  without one reads as excalidraw). The source keeps its own colours; the palette applies at render. The
  mark names a palette, not its colours: after a change to FIGURE_PALETTES, `render --force` each figure.
- A conversation on a course page (docs/sheep-listen-2026-10-24.md, part D): `sheep wait` wakes within
  20 s of quiet (polled every 15 s, was 120 and 60) and, on comments, prints each woken thread (its
  link with `?comment=`, its anchor, who said what when, under a header saying the words are data)
  and takes nothing in; a Save is still taken in at once. `sheep reply <doc> <thread id> <text|->
  [--take]` answers in a thread as Claude Code (User-Agent `claude-code/<version>`), with the
  overlay's optional `keel/reply-signature` line; the thread joins the pin's `talking`, which every
  pull names and leaves alone until `--take` (on the reply, or `sheep pull --write --take <id>`).
  The reply's id, when spacesheep's answer names one, is kept in the pin's `sent` and never read as
  the owner's. `sheep threads <doc> [<id>…]` prints the open threads. The lookout's new `talk` event
  hails the doc's session for new words in a talking thread, or, with none live, starts a run whose
  brief quotes the thread (cut to pickup's 60 lines and 4,000 characters) and holds no landing back.
  That run is dispatched to this Mac, whose pin it replies through. A landing or rename carries
  `talking` and `sent`; a woken wait's words are the next wait's base; pages with a talking thread
  are read though their doc asks nothing (the landing review, 2026-10-26).
- `bin/sheep`: `check` and `control` read the control daemon as it runs (`sessionpipe control
  status`, `launchctl print`): a receiver not polling, not running, or its launchd job unloaded
  fails `check` with its fix (the owner's re-pair, a kickstart, a bootstrap, or `sessionpipe control
  run` with no plist); a `last_error` while polling is named, never a failure. On a plan
  without Talk (the core's `sheep_plan`, read live) it is expected and named so; a status this tool
  cannot read is said, never failed. From 23 to 25 Oct the daemon was dead while both said "paired".
- `list` finds memos in `docs/embark/`, on a branch's worktree or landed: aurora's weekly-run writes the
  week's sitting there, and helm's board cards a memo only through this list.
- `stand --sweep` names a doc that does not parse (`unparseable — <why>`) and goes on; one such doc
  ended the whole sweep before (the 2026-10-18 dream's D2, fix c).
- spacesheep plans (spacesheep-tiers, 2026-10-24): every page publish goes in the core's deploy log,
  shared with helm's redeploys; keel never skips one, warns once per crossing at 90 % of this Mac's part of
  the 24-hour cap (by hand on stderr, in the checkpoint's hook as the row's `note`, the plan read from its cache
  only there), and names a refusal for the cap as one, logged so helm pauses on it. The README's "spacesheep plans" says what each
  plan gets.
- A `handed` line that asks the owner for something is blocked as a pending one is (2026-10-25,
  finish review).
- The Stop lint takes the core's `handed` closing kind where it takes a pending line (2026-10-25,
  yolo-launch review D1-B).
- A course page keeps its discussions (docs/sheep-threads-2026-10-24.md): `sheep pull --write`
  replies in each thread it takes or supersedes and no longer resolves it, so the thread and its
  marker stay on the page; a redeploy gives an edited line the id its comments name (the live page's
  ids, matched by row label and a difflib ratio of 0.6 or more), and a thread whose line is gone gets
  one `memo:` reply saying so; a renamed doc and a doc read from `main` after its branch landed deploy
  into the earlier page, whose pin then says `moved_to`. A doc headed `Supersedes:` gets a page of its
  own: that handover was built, reviewed three times and taken out (D3-A, 2026-10-25).
  list_comments' text form reads the `[pinned to block #<id>]` group line.
- The second landing review's fixes to the above (R1–R12, docs/sheep-threads-2026-10-24.md): a thread
  told its line is gone never moves to a neighbour, nor costs a read of the live page; a repeated line's
  copies keep their numbers; every reader counts a thread with this tool's taken-into reply as taken;
  an owner's reply under an open taken thread is taken in; `main` takes a branch's page only on proof
  from the page's own commit and the fork its pin recorded, worktree or not, and its own empty page
  gives way; the hook's budget covers every call.
- The third landing review's fixes (findings 3, 5-15): a thread not yet told its line is gone carries
  only to a block the deploy that dropped its line added; an inherited id is kept from the pin's
  `aliases` with no read of the live page, and a copy inserted above a commented line no longer takes its
  thread; `main`'s page gives way only once its comments read and its room is drained, and drops its own
  cursors when it does; on `main` a landed branch's page wins over a rename; a fork recorded before a
  fast-forward stays; a reply typed between a take's write and its commit is taken in; a pin with no
  `sha` reads cleanly; a timeout cut short by the hook's budget no longer marks the comments route failed.
- The finish review's fixes: a kept-open thread older than the last pull no longer overwrites a newer Save or
  GitHub edit; a resolved thread on a gone line no longer keeps the live read alive on every deploy; only a
  take's reply counts as the ack a later reply is judged against.
- Mermaid is fetched, not vendored: the repo keeps the version and sha256, and the first page with a
  diagram fetches `mermaid.min.js` from jsDelivr (else unpkg) into `~/Library/Caches/keel` (`~/.cache/keel`
  off a Mac), kept only when it matches the pin (`KEEL_CACHE_DIR`, `KEEL_MERMAID_URL`, `KEEL_MERMAID_FETCH=0`).
  A fetch gets 8 s for all sources together; one under way or failed holds every process off for 10 minutes; an HTTP error mid-body shows
  the source instead of a traceback; an unwritable cache still draws the page.
- `sheep` names its main checkout's copy in messages and reaches the account registry's login dirs
  (an Orca profile) besides the default ones (B14b, 2026-10-23); keel, paste-paths and doc_answers name
  module paths, never the overlay's shims.
- `bin/owed`, `hooks/sheep_gate.py` and `tests/owed.sh` are public (keel-held, 2026-10-23): the
  vaults whose `_secrets` stay closed come from the `lighthouse/vaults` key only, and `owed.sh` writes
  its own config dir, with a case for the key and one for the wider net without it.
- The joint test's two lookout findings (crosstalk S12, 2026-10-23), with its finish review's five
  (lookout-echo, 2026-10-23). The echo: an answer a Save's take-in wrote is no GitHub answer — its
  Save's own event hailed already, so the session's checkpoint of a Save it was hailed about raises
  no second hail. An answer counts as taken in when the pin's `sheep pull` mark (`applied`) holds it
  and the mark's new `applied_at` is no older than the doc's last change before the answer, so the
  same words re-typed after a re-ask are a person's while a code commit in between is no re-ask; a
  mark with no time, or a doc time git cannot read, never counts, and a pull stamps only the items
  it changed. A plumbed commit names
  the items it took in in a `Saved-Items:` trailer, and only those are the Save's: a hand-typed
  answer in the same commit still hails, whatever `Saved-By:` says. The miss: an answer is an event
  when the last pass did not see the item answered, so an item opened and answered between two
  passes, or before the first, is judged against the doc at the answer's parent; only answers newer
  than the arm time count, and an item written already answered is skipped (logged). A pass reads
  the docs open now or at the last pass and this Mac's pins on a `claude/*` branch deployed or seen
  within 14 days, so a doc whose only item opened and closed between passes is read too; the state
  keeps a record for every doc read, open items or none. A doc first met looks back over its
  branch's own commits since it forked from main (the last 30 only where no main line is there, and
  past them a card). A doc that does not read at the answer's parent is judged against the
  doc as it last read in the window: an item open at the last pass hails, and only an unseen item
  that state cannot account for is a card, never "came answered". An item still in asks but
  answered at the tip counts as gone, so a poll carrying stale asks never moves the record past the
  answer; an item written answered stays judged, so a hand answer after a reopen hails; the end
  card and a tip's card join under one id.
- Figures (diagram-tools, 2026-10-23; the Excalidraw evaluation's D1 and D2): `keel render <doc>` draws
  every ```` ```mermaid ```` fence to a PNG with the cached, pinned Mermaid under headless Chrome,
  offline, exits 1 on a fence that does not parse (naming its line) or a library off its pin, and never
  writes a PNG into a tracked folder. An Excalidraw source beside the doc (`docs/<stem>/<name>.excalidraw`)
  is drawn by `@excalidraw/utils` 0.1.5, fetched once into the cache and sha-pinned, to its `.svg`, marked
  with the source's sha256 and the style. Styles: soft (the default: Nunito, roughness 1, solid), clean,
  sketch; a doc picks one with `Figure style:`. The form and course page show a figure line's `.svg`,
  sanitised, as an `<img>` of a `data:` URI, so a browser runs nothing in it, fetches nothing and keeps
  its style inside; with no library. A figure link reads only the doc's own `docs/<stem>/`. `lint` fails
  a figure whose `.svg` is missing or stale, and any link the page would show as alt text. A deploy, the
  lookout's redeploy and `sheep check` count the figure folder's commits; `render --style` other than
  the doc's draws a preview PNG and leaves the `.svg`.
  The private `figure` skill draws one from Python; a session sees it once the overlay's skill links
  name `keel/figure`. The architect pair and the sounder render and look before the hand-over.

- The rest of the lookout's fixes before arming (crosstalk S11c, 2026-10-22; items 9–16 and 23–30 of
  `docs/lookout-s5-2026-10-22.md`): a brief whose run did not start is briefed again with its
  `Steps:` hold turned into a `Released:` line, so `keel landing` holds nothing for it; a run takes
  no `wip` step and none placed `in <repo>/<path>`, a component of the older layout is read by its
  own Action plan, one unreadable component no longer empties the set, and a dry pass previews a
  Save's run; the hail names the overlay `~/`-relative; a start's tools inherit no session id, job
  log, year, label or skipper, and a pass never excuses its caller's own lock; a missing core at the
  2 h guard is a gated card; a GitHub answer's brief names the answer's commit; a pass reads
  `lookout.jsonl` once and asks `harness list` once; a start on its way carries no card, a held local
  worktree is gated, a gated card is relogged daily, and a card whose branch only helm's mirror knows
  stays open; an exception after the starts are collected keeps a gated start's event. `keel
  lookout`'s help says a shared course page lets its viewers start runs (item 7: any Save, the page's
  access is the gate). Its finish review: a dispatch that timed out is held, not released (the peer
  may have the job); a release keeps an earlier run's steps held; a same-day brief of another doc is a
  card; a timeout is told without its command line; a placement is read after the agent's name only;
  a start drops dispatch's chain variables too.
- The scrub (2026-10-22): no name, host, repo or overlay path in code, tests, skill or docs. The
  owner's name signs answers and notes from `regatta/owner` (`Owner` without one); the guarded
  repos, the vaults and the knowledge repos come from the core's, lighthouse's and atlas's keys;
  `keel/machines`, `keel/course-site` and `keel/course-mcp` are new. Messages name the overlay's
  shims while there is one, else the module's tools. The form's labels and live regions use
  `title`, visually hidden text and `role="status"`. The suites run on a scratch config dir with
  synthetic fixtures; the mermaid bundle stays private, and a page without it shows the source.

- The course page's counter tallies decisions only (PAGE_FMT 8, 2026-10-22): the owner's notes and the
- The lookout's fixes before arming (crosstalk S11a, 2026-10-22; items 1–6, 17 and 18 of
  `docs/lookout-s5-2026-10-22.md`): the last gate before a start asks every host through `harness
  list --host all` — a live session on the branch on the other Mac is a card, a host that does not
  answer a card tried again; a gate that clears by itself (a tight week, no login free, a missing
  tool, the peer, a pickup refusal that passes) raises a `gated` card, not settled, so the answer
  gets its run once it clears, and a failed start no longer counts as a run on its branch; a start
  runs out of process (`keel lookout --start`, the next pass reads its result), so a pass returns in
  seconds; a nested set's component reads its steps in the entry (`<slug> D2` in an `after:`, the
  brief's `Steps:` naming the entry); `held_by` and the lookout's `held_branch` share checkpoint's
  rule (`holder`: a handed-over lock or the caller's own holds nobody out); a dry or disarmed pass
  runs every gate before its preview; the laptop leaves another host's GitHub answer to that host's
  lookout for the hail as for the run; a card drops from `--status` after 7 days or once its branch
  is gone, and `lookout.jsonl` keeps 30 days. From its finish review: a start collected as dispatched
  still holds its branch; `--start` takes only a request in the starts folder, runs this Mac's tools
  and refuses when disarmed; a run starts only on a `claude/*` branch.
- The skipper-modes landing review (2026-10-22): `status` gives `ask-mode` for a doc on a branch
  whose sent task is in mode `ask` — it never stands, by the sweep or by autofinish's rule D; `yolo
  --dnd` reads a repo with no `physical:` line as physical and holds every item, as held_slice and
  dispatch do.
- The course page's counter tallies decisions only (PAGE_FMT 8, 2026-10-22): the owner's notes and the
  feedback box are one `✎n` beside it, spelled out in its tooltip and for a screen reader;
  `· 1 note · feedback` read as open items.
- The status pill clears the count by a margin, not the bar's bare gap (PAGE_FMT 7, 2026-10-21).
- The lookout's run (crosstalk S5, 2026-10-22): with no live session on a doc whose answers are on
  its branch, `keel lookout` puts a brief on the branch (`pickup brief`) and starts one run
  (`dispatch`) — only when armed, an open session step's `after:` names an answered item, no session
  holds the worktree (`owner.json` under 2 h, not handed over), the repo says `physical: none` and
  `week_tight()` lets autofinish run; else a card. From the laptop dispatch's own Where default
  (no host named here), elsewhere `--on here`; the laptop leaves another host's GitHub answer to
  that host's lookout. The brief is fixed text: the overlay's `keel pull`, `checkin`, a reply under
  every changed hunk, `step … --stamp`, `checkin --done`, commit, the line `bin/ask` prints; never
  `/finish`, push, `gh` or `bin/pr`; its `Steps:` line holds the landing until the steps are done.
  A `dispatching` row before the brief keeps each answer to one start, after a failed dispatch too.
  `--status` lists the runs with dispatch's log line. Every Save is taken in (S3's D1, the owner,
  2026-10-21: "just record who made it"): the `keel/viewer` filter and `KEEL_VIEWER` are gone; each
  plumbed commit carries a `Saved-By:` trailer per viewer, `lookout.jsonl` a `saved_by` field, and
  the brief names who saved. A live session no hail reaches gets a card, never a run beside it.
  The finish review's fixes (2026-10-22): a step is a run's only when every `after:` is met (D-items
  answered, S-steps done) and it is a session's or this repo's `project` step, not blocked;
  `--arm` refuses an unattended caller; a viewer's name is one line, 40 characters, never a session
  id's shape; the brief names the tools as `~/…`; one run a branch within 2 h; a branch's own brief
  from today is never replaced; a missing peer in `bin/autofinish` is a card, not a dead pass. The
  landing review's (2026-10-22): a step is a run's only when its project, wherever it stands in the
  kind, names this repo and no `| human` part is on it; `--disarm` stays open to an unattended run;
  a viewer's name never carries a `-By:` trailer's shape; a run's brief from earlier today keeps
  its `Steps:` hold.
- `keel status`: a `taken` doc says whether it lands under the branch's mode now — `taken_by`,
  `mode`, `lands` beside the verdict (skipper-modes S3b: yolo lands any pick, dnd its own picks,
  default and ask none).
- Skipper modes (S1, S2; docs/skipper-modes-2026-10-21.md, D1: "A, and --yolo goes all the way"):
  `keel yolo` takes every bare pick, `Reversible: no` and unmarked items included, stopping (exit 3,
  nothing written) only at an item with no pick, a conditional or a reopened one; `--dnd` takes the
  same picks as `Taken unattended (<owner>'s dnd, <date>)` except D1-A's held classes (`DND_HOLDS`:
  money in an option, a repo not `physical: none`, a deletion or public publish, a third party's
  answer; and no pick, conditional, unmarked, reopened), printing each as `held Dn` (exit 4).
  `YOLO_ANSWER_RE` reads `yolo|dnd`. The stand sweep skips a branch whose sent task is in mode `ask`.
- The lookout (crosstalk S3, 2026-10-21): `keel lookout` — one pass over the docs helm's ask poll
  lists with open items. Events: a Save the doc lacks (the laptop's pins; drained every pass for
  those docs only, the 14-day drain stays at 6 h), an item answered on origin by a commit that is
  not stand's, yolo's, a dispatched run's or the lookout's own, new comments on the page. A `sheep
  wait` holding the page's lock (read, never taken) leaves the doc alone; the Save goes onto the
  branch by plumbing first; the session — the worktree's owner, the newest `Claude-Session`
  trailer, the run record, then its skipper, live by `harness status` — is hailed with a pointer
  when idle, waited for when working; with none, `would dispatch` and a card (S5 fills the
  dispatch). A host other than the laptop acts on its own branches
  and cards another host's pushed within 2 h. The laptop redeploys a page origin moved past.
  `lookout.jsonl` remembers each event once. Disarmed until `--arm`; `--if-due`, `--dry-run`,
  `--status`. `keel checkin` writes ` · crew: <who> since|done <date>` on the Status line; `lint`
  and `status --stamp` read it. `keel sheep pull --write --plumb` takes a page's Saves onto a branch
  no checkout here has out.
  The landing review (2026-10-21) fixed: hail's indented `--json` record read whole (every delivered
  hail had read as unreachable); a working session is waited for before any plumbing; an answer under
  a held `sheep wait` waits instead of settling; three spacesheep failures in a row end a pass's pages;
  a Save's items are the ones the doc lacks; Save ids carry the space; an unnamed Save is not the
  owner's; the hail names the overlay's `keel`; no state written without `asks.json`; `--plumb` takes
  `--write` and `claude/*` branches only; `checkin --date` is checked.
- `sheep_gate` drops a confidential scope's sessions (knowledge-layers S1, 2026-10-21): a cwd, a
  transcript folder or an event text under the checkout of a repo whose scope is flagged
  `"confidential": true` sends nothing to sessionpipe, through the core's `confidential_roots()`;
  no registry, PRIVATE_REPOS alone as before; a registry that does not read, or a core that does not
  import beside one, drops every event. Also dropped: a folder holding a confidential repo, and an
  event naming one's slug folder under any login dir. `private_part` names a confidential repo by
  its folder, so `never_mirrored` and helm's `guarded()` keep it in; `never_mirrored` mirrors
  nothing while the scopes do not read. Its cases: `tests/sheep_gate.sh`.
- The course page after the owner's test page (PAGE_FMT 6, 2026-10-20): the orange toned down to what
  the reader acts on — the Save, focus, a picked option, links, the state while sending — with
  labels, the arrows and the capsule back to spacesheep's neutrals and card edges a faint warm line (D1: "too loud");
  the status as spacesheep's live pill, sized to its word after the count, so no state sits
  off-centre (D4); its sentence pops up inside the bar's width.
- The course page on spacesheep (PAGE_FMT 5, 2026-10-20): spacesheep's neutrals with every
  control the course owns in fire orange, never purple; the footer a pill-buttoned capsule that
  stops 84 px short of the right edge, clear of the viewer's mic and comment buttons; the status a
  word with its sentence in a pop-up; the count and ↑ ↓ take in the notes and the feedback; ↓ no
  longer re-picks the card it just landed on under the viewer's header inset, and the bar sits
  above spacesheep's comment pins, which took its clicks; and a receipt — a
  pull that takes the page's Save says Taken on every open tab (live_push) and in the next deploy.
- Carried from the overlay (the wharf rename's S5, 2026-10-20): `paste-paths` reads the run's
  skipper as `DISPATCH_SKIPPER` or `DISPATCH_MANAGER`; the launch word in `sheep`, `paste-paths` and
  their suites; `sheep_gate.py` names helmlib; `tests/keel.sh` imports helm's `helm_render`, or
  `plan_render` from a peer older than S5.
- Carried from the overlay after the move (B4's carry, 2026-10-20): `keel light` (light B1), the
  rename's launch word in `paste-paths`, `doc_answers.py` and `/keel` (S3, S4), the Wharf goals'
  case in `tests/keel.sh` (wharf S8, through `peer knowledge-numbers`).
- Suite time (2026-10-23): `tests/keel.sh`'s four headless Chrome runs poll for the dump's closing
  tag and end Chrome there (`chrome_dom`, one profile dir per page, the last three side by side). In
  a dispatched session Chrome writes the whole DOM and never exits (its updater's IPC), so each ran
  into its 90 s alarm and was skipped: now they run, and pass (995 to 999 cases). The two `sheep wait`
  cases poll for the wait's first comment read where 1.5 s sleeps stood; two mtime orderings backdate
  instead of sleeping a second; test_lookout's slow-start stub waits for the case's go, not 6 s.
  `tests/check.sh` runs paste-paths, owed, test_lookout and sheep_gate side by side once keel.sh is
  done. Timed under load 35 to 140 on 10 cores: keel.sh 11.4 min before, 6.3 after; the whole check
  12.4 to 13.3 min after (test_lookout 3.0, paste-paths 1.2, owed and sheep_gate under 0.1 each, alone).
  A quiet Mac where Chrome hangs loses the same 6 min of alarms (not measured there). The landing
  (2026-10-27): `chrome_dom`'s 90 s is wall time, and a Chrome that ignores the end is killed after
  3 s; sheep_control (new on main since) runs alone after the four; cut short, check.sh ends the four
  and prints what each wrote so far.

## 0.1.0 — 2026-10-19

- Moved in from the overlay (regatta-modules B4): `bin/keel`, `paste-paths`, `owed`, `sheep`,
  `hooks/doc_answers.py`, `sheep_gate.py`, `/keel`, `vendor/mermaid`, their suites as `tests/`.
  Every edge into another module goes through the core's `tool()` with a named fallback (G9, G10,
  G11, G24, G33); `sheep` reads the host name and `secrets` from the core.
