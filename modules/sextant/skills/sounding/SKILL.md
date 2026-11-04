---
name: sounding
description: Sound an idea before anything is built — a change to one project, to how every project runs, or an idea outside any repo (a venture, a pitch, a tool to build or adopt) — through one architect-family agent picked by scope (`architect`, `sr-architect`, `sounder`). Sounded unless the request starts `firm:`; the doc carries a Landscape of what exists and a one-line Verdict, passes the lint and `reviewer-high`, and reaches the owner by one of three paths — full (the hand-over line), `--light` (a chat questionnaire) or `--yolo` (the reversible picks taken unattended); `--principal` adds the council (blind arms from other vendors, a cross-examination, a fresh synthesis, two fact-checks, a Receipt). Use for "sound this out", "is this worth building", "propose …", a kept idea note or a ready proposal, and whenever the owner types /sounding (from a phone, `—light` and `—yolo` are the same flags).
argument-hint: "[firm:] <idea, brief or note path> [--light] [--yolo] [--principal]"
---

Sound it: $ARGUMENTS

If this project has its own `/sounding` (`.claude/skills/sounding`), run that instead and stop here.

A sounding measures the depth before the ship commits: it writes **one doc** that tests the idea
against what already exists, and builds nothing but what tests it (a prototype, a probe, a
measuring script, kept in the doc's folder). The doc is the record whichever path answers it.
The method is the agent's (the architects' shared body: the stance, the Landscape, the options on
fixed axes); this skill picks the agent, writes its brief, checks the doc and hands it over.

**Tools.** `keel` (keel module) and `sparks` (this module) are on the Bash PATH while their plugins
are enabled. Where this skill is linked in by hand, resolve this skill's base directory first
(`cd <base directory> && pwd -P`, since the link's own path leads elsewhere) and run
`../../bin/sparks` and `../../../keel/bin/keel` by absolute path, without leaving the session's
own directory. `keel`, `ask` (the helm module, for the unattended relay), `reviewer-high` and the
three heads are what this skill cannot run without: one that is not installed stops the run before
the spawn, saying which; nothing is substituted for it.

## 1. The head, by scope

| The idea changes … | Agent |
| --- | --- |
| one project: its code, its docs, its workflow | `architect` |
| how every project runs: sessions, repos, machines, models, tools, the workflow itself — or the owner calls it fundamental | `sr-architect` |
| nothing in a repo yet: a venture, a film or content pitch, a marketing project, a tool the owner might build or adopt | `sounder` |

Between two, take the narrower and put the wider question in the brief, for the doc to name. A
project's own agent of the same name wins (its `.claude/agents/`).

## 2. The stance

- The request starts `firm:` → the brief starts `firm:`: the idea is taken as given (probes and
  three options still), and the doc's Verdict reads `firm`.
- Anything else is **sounded**: the brief carries no `firm:`, however sure the request sounds.
  The agent names the idea as a hypothesis, steelmans the other side and writes `Verdict:
  validated | disproved | evolved` under `Status:`.
- Firm by shape, never sounded, and passed on as such: a worker's spec, an answered `➤ Answer:`,
  a `Taken in chat` answer, a `since:` line, the owner's own pushback on a recommendation.

## 3. The peers' two lines

Read the peers file — `$REGATTA_PEERS`, else `regatta/peers.json` in the regatta config dir
(`$REGATTA_CONFIG`, else `.config/regatta` in the home folder); an absent file or key is `auto`.
The brief carries exactly these two lines, one per peer:

```
Peer sparks: <on | off | auto> — <run `<absolute path to sparks> related "<the brief's nouns>"` | off: one line in the Landscape, nothing read | absent: one line in the Landscape>
Peer personal: <on | off | auto> — <one question, `semaphore ask "<q>" --why "<task>"` | off: one line | absent: one line>
```

Found means `sparks` (above) or `semaphore` resolves to a file. An `on` peer that is absent
stops the run before the spawn, naming the peer: the owner declared it, so a missing one is a
broken install, not a thinner Landscape. A repo an employer or another person shares reaches
neither peer: there both lines read `off: a shared repo`. Elsewhere a `personal` question names only
public or open-source work.

## 4. The brief, and the spawn

The brief holds, in this order: the stance (`firm:` or nothing); the idea quoted verbatim, with
where it came from (the chat line, the note's path, the proposal's path and its `## Launch test`
quoted); the kind (`proposal` unless the request names research or design); the doc to write, as
an absolute path, and its folder beside it (`<stem>/`, for what the subject owes: a prototype, the
scripts behind each number, each probe's output — never "one file only"); the path flag (full, light or yolo) and what it asks of the D-items;
the peers' two lines; any constraint the request names.

- **The file.** An idea in a repo: `docs/<slug>-<date>.md` in that repo's worktree on this
  session's `claude/*` branch (make the worktree first if the repo's workflow asks for one). An
  idea outside any repo: the knowledge vault, on a branch of its own — atlas's
  `knowledge-commit <vault> --open <slug>` prints where — outside its `ideas/` and `ventures/`
  folders, which are written in place on `main`, where an answer cannot be told from an agent's.
- **Under `--light`** the brief adds: at most four D-items, two to four options each, no
  conditional pick, and a `Reversible: no` item's options each naming its cost (money, a
  dependency, a deletion) — what the questionnaire can carry.
- **A proposal the strategy pass made ready** (Sextant's queue or *launch now*): the doc's D1 is
  `Build: full · light chain · yolo · no`, `Reversible: no`; a `disproved` Verdict parks the
  proposal instead.

Spawn the head with the brief, in the foreground: the next step reads its doc.

## 5. The checks, before the owner sees it

1. `keel lint --strict <doc>`. Fix what is mechanical yourself (a link, a heading word, a cap);
   a missing Landscape, under three linked candidates, or no `Verdict:` line goes back to the
   agent — the same one within about five minutes, else a fresh one with the doc and the
   finding. The lint does not check those three yet: read the doc for them yourself.
2. `reviewer-high`, model opus, on the doc. Apply its fixes yourself; a finding that changes a
   premise goes to a fresh head with the doc and the finding. Ask it, too, for one verdict on the
   light path: `light-ok`, `redesign` (back to the head, then these checks again) or `promote`
   (the full path).
3. Commit the doc and its folder on its branch (in the vault, atlas's `knowledge-commit … --in`, naming both paths); so too every
   answer a path below writes into it. A `disproved` doc is still handed over: it is the record of why.

## 6. The three paths

- **full** (the default): `keel line <doc>` and relay the line it prints; the owner answers on
  the doc's page or on GitHub, and `keel pull` takes the answers back as commits.
- **`--light`**, attended only: `keel light <doc> --check`. Nothing open (it says so): the full
  path. Passing, with `light-ok` from step 5:
  `keel light <doc> --plan --review light-ok`, make each `AskUserQuestion` call exactly as
  printed, then `keel light <doc> --write --why "<the owner: --light | session: check passed>"
  --review light-ok`, then `keel line <doc>` all the same (the record reaches the phone; it owes
  no form). The check runs unasked after every attended sounding, flag or not — say in chat when
  it went light; `--yolo` skips it. Refused: `keel light <doc> --check --record` writes why. A
  `promote` verdict, a decision a co-maintainer shares (they read it on GitHub), or `--write`
  exiting 3 (an answer missing): `--record` writes only its own refusals, so put the line
  `Gate: memo — light refused: <why>` where it would (the doc's Gate line, else under the
  `Written by` paragraph). Either way the full path follows.
- **`--yolo`**, only when the owner typed it, and over `--light` when both are: `keel yolo <doc>
  --dry-run`, then `keel yolo <doc>`. It goes all the way (skipper modes, D1): every open item's
  bare pick is taken, `Reversible: no` and unmarked items included. It stops (exit 3), writes
  nothing, and the whole list goes the full path only at an item with no pick, a conditional pick
  or a reopened one.

**Unattended** (a dispatched run, `CLAUDE_UNATTENDED` set): never the questionnaire — the check
refuses it (C4). The full path's hand-over is the run's relay (`ask relay <doc> <Dn>`), and the
run ends on the line it prints.

## 6b. `--principal`: the council, the synthesis, the Receipt

Only when the owner typed `--principal` (or the request starts `principal:`): a sounding where an answer that
holds is worth a council's cost (docs/principal-tier-2026-10-26.md, "The council"). `--light` is refused with
it (say so in chat and go the full path); `--yolo` stays the owner's to type. Every step above holds; these
replace step 1's head and step 4's one spawn, and add to step 5.

- **The head.** One project's idea or one that changes how every project runs: `principal-architect`, the
  brief naming its scope (the project's, or the system's as `sr-architect` reads it). A venture (nothing in a
  repo yet): `sounder`, spawned with `effort: "xhigh"`, the brief asking for a header whose `Written by`
  line names `sounder` with `principal` in its parenthesis (`(Fable 5.1, xhigh, principal)`) — that word is
  what `keel lint --strict` reads; `principal-architect`'s own name is enough for the other two.
- **The council's tool.** `principal` (this module's `bin/`, resolved as `sparks` is above; wharf's
  `council` is its peer). Its record goes in the doc's folder, `<stem>/council/`. A council that refuses, an
  arm that fails, a council not installed, all off macOS until the isolation design's S6: `principal` records
  it, prints it and exits 0 — the sounding goes on, and the Receipt says so. Never retry a refused arm by
  another road; a broken arm's way out is `council fences` (the owner's), or row C.
- **The home.** The repo the doc is in, at its committed HEAD (council copies a commit, never the working
  tree: commit the brief first). A venture's is the vault's worktree; a guarded home needs the owner's quote
  per vendor (`--approved google=<quote>`, typed by the owner in this request), never an unattended caller's:
  without it those arms refuse, and the Receipt says so.

1. **The brief**, as step 4 writes it, saved to `<stem>/brief.md` and committed: the council's arms get it as
   it is — each designs in full, on the head's mandate, what the subject owes included (the owner, 2026-10-30:
   "the other 2 models should design as well, not just consult. then they try to agree") — and the head gets it
   with the doc's path. The head's copy also says: write the blind draft to `<scratch>/draft.md`, a path in
   this session's scratch folder (outside the repo), not the doc; no council paper reaches you yet. The brief
   itself holds no D-item, answer box, open checkbox or docs/handoff/ path: `<stem>/` is committed with the
   doc, and autofinish reads each as an open ask the owner never answers.
2. **The draft and the council, side by side.** Bash `<principal> run --doc <doc> --brief <stem>/brief.md
   --home <repo> [--files <named files>] [--research when the brief needs the web] [--approved …]` with
   `run_in_background: true`, then, in the same message after it, spawn the head on the draft (foreground):
   a Bash call that writes never runs beside another tool, so only the background start lets the two overlap.
   Where background work is off (`CLAUDE_CODE_DISABLE_BACKGROUND_TASKS`, a dispatched run), the Agent call
   comes first and `principal run` after it, timeout 1800000. Either way the head stays blind: `principal
   run` leaves the papers in the council's run dir, outside the doc's folder. Wait for the run to end before
   step 3.
3. `<principal> examine --doc <doc> --draft <scratch>/draft.md [--research] [--approved …, as step 2]` (timeout
   1800000): the draft and the papers reach `<stem>/council/` (`draft.md`, `papers/`), each D-item and answer
   box rewritten so none reads as an ask, then the agreement round — each arm that answered reads
   the draft and every design, blind, adopts what is better, and concedes, holds with evidence or compromises
   where they disagree. Each critique opens with a line saying which of its own labels is the draft and which
   `papers/<label>.md`.
4. `<principal> receipt --doc <doc>`: the council's rows and completion line.
5. **The synthesis: a fresh head** (never the drafter, never continued), same agent and effort, briefed with
   the brief, `<stem>/council/draft.md`, `papers/` and `critiques/` (labels only: the key in
   `state.json` is not for it), and receipt 4's text verbatim. It writes up what the arms agreed, settles what
   they did not, and leaves as D-items only what the owner alone decides. It writes the doc whole, its probes in
   `<stem>/`; its `## Receipt` holds the council's rows as given (a refused or failed arm stays so), a row
   for the draft's pen and its own, a line per disagreement settled by source, probe or judgement (a
   judgement `flagged`), and its completion state as `Completion: **<state>** — <why>`: `incomplete`
   while an arm or examine did not answer.
6. **Two `reviewer-high` passes**, model opus, in one message, each on the doc alone (neither sees the
   other's report); merge their findings (one item per claim, the stronger severity) and apply them as
   section 5's check 2 says. Add a Receipt row per reviewer (requested Opus `high`; observed read from its transcript, else
   `unknown`), and one for this session, the parent.
7. `<principal> check --doc <doc>` (the Receipt against the council's record) and `keel lint --strict <doc>`
   (the principal rule: no Receipt, no completion state, or anything but `incomplete` beside an arm that did
   not answer is an error; under three arms and an unsettled or unflagged disagreement warn). `check` also
   refuses a file in `<stem>/` that autofinish would read as an open ask. Fix and re-run until both pass.
8. Commit the doc, `<stem>/` and `<stem>/council/` (draft, papers, critiques, `receipt.md`, `state.json`), then
   the path section 6 names: full, or `--yolo` when typed.

## 7. Go on

Once answered: apply the answers (a pick among the doc's options here; a changed premise to a
fresh head), then build by the doc's Action plan, one step per fresh session, through the
project's own finish. A `disproved` or `Build: no` doc ends here.
