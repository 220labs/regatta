---
name: finish
description: "End-of-session wrap-up — run the project's check, clean up test state, learnings into the right home — then curate this claude/* branch into clean history and, once no open items remain, launch it automatically through GitHub: pushed and readied as a pull request, merged too on the laptop, left for the owner's tap on the other Mac; --local merges into local main instead (offline). Invoke it yourself only in a main session (never a subagent) when the owner's own message asked to finish, land or launch this work, or when a chain the owner started reaches its end with the check green (memo's After-Save rule) — never because the work merely looks done"
effort: medium
---

Finish the current `claude/*` branch — rule: git-workflow. $ARGUMENTS

**Where the tools are.** A bare tool name in a command below (`pickup`, `keel`, `check`,
`autofinish-run`, `rc-hosts`, `paste-paths`, `owed`, `knowledge-commit`, `pr`, `review-gate`,
`carried.py`) is a path: where the regatta config dir holds a `legacy` file (an overlay is
installed), `<its first line>/bin/<name>` (`<its first line>/hooks/carried.py` for that one)
— the shims the overlay's allow and deny rules name, so an unattended run is never denied its
own step and a yolo run's `pr merge` stays denied — else the peer module's file, which
`regatta which <name>` prints (`regatta` is the core's `bin/regatta`, on PATH in a plugin
install). With no overlay, wharf's own are named from this skill's base directory, as one
path, never through `cd`: `<this skill's base directory>/../../libexec/pr`,
`<this skill's base directory>/../../bin/review-gate`, `<this skill's base directory>/../../hooks/carried.py`. The closing lines below are written `<OWNER>, …`: `<OWNER>` is the
core's `regatta/owner`, upper-cased (`regatta check` shows the key); with none, a line starts
at its second word. "The other Mac" is any host but the laptop the config dir's
`regatta/laptop` names (`scutil --get LocalHostName`, lower-cased, says which this is).

**Why `effort: medium`** (the owner, 2026-09-22): `/finish` was 11% of all spend in its first two
weeks, and nearly all of it is mechanical and checks itself — step 9 proves the rewrite
changed nothing. The one judgement-heavy part, the diff review in step 1, runs in two agents
at the effort the review gate picks (`high` or `xhigh`) instead. On Opus 5.5, Sonnet 5.5 and Fable 5.1 on the subscription the effort switch
keeps the prompt cache; on other models it costs one uncached request
(code.claude.com/docs/en/prompt-caching). Never add `model:` here: a model switch always
rebuilds the cache, and cache reads are most of what a long session costs.

**Queue it behind a running turn** (code.claude.com/docs/en/interactive-mode, 2026-09-25):
`/finish` + Enter while the agent works holds it until the *turn* ends, then runs it. That is
"finish when done" from the keyboard. Turn, not task: a stop to ask a question runs it then, and
step 4's gate sees `TODO.md`, not a question left in chat — queue it once none is pending (Up
takes it back). Never Ctrl+Enter it: that sends now and backgrounds the running work.

**An agent may run it — on the owner's word, never its own** (the owner's D8, 2026-10-05,
docs/subagent-cache-2026-10-04.md: "why are we limiting finish to just myself if we're replicating
the agentic version anyways"; it was `disable-model-invocation` until then). The gates make a
launch safe, not who typed the command: step 4 stops on any open item, step 9 proves the
rewrite, and on the other Mac step 11.4 asks before merging — except in a `merge: auto` repo
(the two knowledge repos), where nothing asks. So a main session calls it when
the owner's message said finish, land or launch, or when a chain the owner started ends green (the keel skill, `modules/keel/skills/keel/`, "After
Save, go on"). Not when the work merely looks done, not on "ship it" (rule: git-workflow — "ship
it" is not merge), and never from a subagent, whose prompt is the parent's, not the owner's. The
sibling repos this `/finish` launches by its own step ("A sibling repo", step 11) are part of it;
starting a `/finish` in another repo is not. Unattended runs stay autofinish E12's. Prose, not a
mechanism: a PreToolUse hook on `Skill(finish)` is the next step if this is ever misread.

**`/finish <branch> [--merge]` — finish work another session left** (D3,
`docs/record/shipping-and-pickup-2026-09-25.md`). The owner's route from the phone for a branch a session
paused on the other Mac: one message in any live session of that repo. `$ARGUMENTS` names a branch
only when, flags aside, it is ONE word — `claude/…`, `#N`/`prN`, or a topic — and
`pickup show '<word>'` resolves it to exactly one open branch;
anything longer is free text, as before (2 of 166 real `/finish` calls carried a sentence).
Name the branch it resolved to in your first line. When it names one this session is not on:

1. `pickup open '<branch>' --here` — the branch's worktree
   (from origin when that is the only copy), `.env` linked, a fast-forward, a stale lock
   released, and the context bundle. It refuses a launched branch. When it prints a ⚠ — the
   branch's session is still running, here or on the other machine; files there are not on
   origin; a divergence — stop, report it with the end-session line it printed, and go no
   further: finishing under a live writer rewrites its history.
2. `EnterWorktree` with the path it printed, and read the bundle: it is the only record of
   what the branch was for.
3. Phase 1–3 below, with two differences. Gate 0 accepts a lock that is free, or expired and
   held by a session step 1 did not report running — this session takes it at its first
   write. And the commits of the session(s) that made the
   branch are the work the owner asked to finish, not "commits from another session" to pause on
   (step 10); a third session's commits still pause.

Already on that branch: the argument changes nothing. `--merge` is the owner's explicit yes to merge
this branch's PR, given in the same message — on the other Mac step 11.4 then merges without asking.
It covers this PR only (never a sibling repo's, never a later `/finish` — bar the one unattended run
`autofinish-run --merge` starts on it, below) and never answers the
open-items gate in step 4, which still stops.

**`--unattended`** (autofinish E1, `docs/autofinish-design-2026-10-02.md`). The launcher
(`bin/autofinish-run`) started this session in the branch's worktree with the lock already yours
(`owner.json` names this session; skip steps 1–2 above) and the bundle at
`<git dir>/claude/autofinish-bundle.md` — read it as the conversation's record: step 3's learnings
and step 4's asks come from it and the commit bodies. **First act, before step 0 or anything else:** run
`autofinish-run notify` and send each `SendMessage to <name>` it prints,
the text word for word — the sessions open on this branch learn it is taken and by which run
(The owner, 2026-10-18). Nothing to send is fine; a send that fails is no stop. A live but idle session on this branch is
expected: its commits are the work to finish, as in step 3 above, not another session's to pause
on. Every ask is a stop — wherever this skill asks, warns or pauses (steps 0, 1, 4, 10, 11.4):
end with the ⚠ block, its first line naming the step (`⚠ step 4 — …`), never a DONE line; the
launcher posts it on the PR, and nothing retries on this tip. The report is the PR body (step
11.3). The owner may be watching from the phone or the window `finish · <topic>` and may type: answer
them as in any session. A launch with `autofinish-run --merge` carries the owner's `--merge` (the prompt ends
`--unattended --merge`): step 11.4 then merges on the other Mac without asking, this branch's PR only.
Nothing else differs.

**`--yolo`, `--dnd`, `--hold`** (with `--unattended` only; autofinish E12 and skipper-modes S3b —
`bin/autofinish-run --by yolo|dnd`, or the sweep's rule M, started this launch). Some of the branch's
answers read `Taken unattended (the owner's yolo, <date>): <pick>` or `Taken unattended (the owner's dnd,
<date>): <pick>`: `bin/keel yolo` wrote them — every bare pick under `yolo`, `Reversible: no`
included, and under `--dnd` all but the held classes (skipper-modes D1). Under `--yolo` or `--dnd`
step 4 counts them as answered, and the report lists them first. Whether this run merges is not
yours to judge: `autofinish-run` read the ship's mode from `plan.json` (only the owner raises it) and the
held slice before it started you, and said so in the prompt. **Without `--hold`** — the mode is the
yes: step 11 takes the laptop's path on any host, `bin/pr merge` included, and the report ends with
the rollback line `pr merge` prints. **With `--hold`** — mode `ask`, the dnd slice (money, a physical
repo, a public publish, a deletion of data, a gated path), or a mode lowered since: step 11.3 as `bin/pr
ready --hold --body-file <report>`, always `--hold` (automerge would otherwise launch what the owner never
saw; harmless where none runs), no step 11.4 — `bin/pr merge` is denied to this run. The reason is
`hold` in `<git dir>/claude/autofinish.json`; put it in the report's first line. Then `rm` the
`finishing` marker, `ExitWorktree` `keep`, and end with the ⚠ block `⚠ step 11 — held: PR #N waits
for the owner's tap` — the launcher records it `held`, with the class, and the board cards it. In modes
`default` and `ask` a taken answer never lands: the sweep's rule D skips a `taken` doc, and a mode
launch whose ship was lowered is held (docs/yolo-veto-2026-10-07.md D1, kept there).

**`--here`** (autofinish E7): runs `/finish` in this session even when it is cold or on Fable.
Without it, `hooks/cold_prompt.py` hands such a typed `/finish` to the launcher (`--by typed`) and
blocks the prompt with where it runs; with it, nothing differs from a plain `/finish`.

**Project override first.** If the project has its own `/finish` —
`.claude/commands/finish.md` or `.claude/skills/finish/SKILL.md` in the project — that file is
authoritative: read it in full now and follow it instead of this one. (A personal skill wins
the name, so this hand-off is how a project keeps a specialised version.)

**The session contract.** Read the `## Session contract` heading in the project's `AGENTS.md`
(else `CLAUDE.md`). It names:

- `check:` the read-only command this wrap-up must see pass — safe at any hour, triggers
  nothing live. None named: say so in the report; the project has no automated check yet,
  which is itself worth an open item.
- `live:` what live system runs *deployed* state and the command that shows drift — or
  `none` (git is the only state).
- `physical:` a heavier sweep that acts on the real world — the owner's to run, never this one's.
- `learnings:` where each kind of finding goes in this project.
- `open-items:` where open items are recorded (default: `TODO.md` plus any heading matching
  `open|still manual`).

Three phases. Phase 1 stops early on a ⚠ gate if open items remain. If it doesn't stop —
i.e. no open items — Phase 3 launches the branch automatically; there is no separate approval
pause. The open-items gate in Phase 1 **is** the approval: getting past it, for a session
working solo on this checkout, means the launch happens without a further check-in. The
launch goes through GitHub (step 11): the pull request is readied on every host, merged too
on the laptop, and on the other Mac merged on the owner's explicit yes to one question — or left for their
tap. A sibling repo this session committed in launches the same way, in the same turn.

**Nothing to finish?** If the current checkout is already on `main`, with no owned
`claude/*` branch or worktree, and `$ARGUMENTS` names no branch (above) — the branch this
session would finish was already curated and merged, this turn or an earlier one — there's
no Phase 1–3 to run. Do this instead, then stop:

- `git branch --list 'claude/*-raw'` — each one is the pre-curation backup step 8 makes,
  right before a merge, meant to be kept only until the plain branch is merged at step 11 and
  pruned at the next session start.
  A `-raw` branch with **no surviving plain counterpart** (`${name%-raw}` isn't a branch)
  **and no worktree** checked out on it is exactly that trail: an already-merged,
  already-cleaned-up branch whose backup nobody swept yet. List each one found this way. This
  is a repo-wide view — not scoped to branches this session itself created — since a `-raw`
  branch meeting both conditions can only have gotten that way via a completed merge, by any
  session.
- Leave alone anything with a living plain branch or a worktree — that's active or
  mid-flight work belonging to some session, not a leftover.
- The checkpoint hook sweeps those itself — on the first prompt in any hour, by the same two
  conditions, once a `-raw` is 2 h untouched, since a merge that went in minutes ago still needs its
  rollback (step 11). No agent deletes a branch by hand, `-raw` included (D1, 2026-09-25):
  report what the hook swept this session and what it will sweep within the hour.
- If nothing matches, say "nothing to clean up".
- Recap what has **shipped**: every branch merged at step 11 (this turn or since the last
  `/finish` in this checkout; its local copy is pruned at the next session start) is a change
  that is fully on `main` — name each one in a line. A merged branch is the definition of
  "done" here, so this is the list the owner can stop thinking about.
  The **Shipped:** label itself is preceded by a few ship emoji — three or four, picked
  at random from 🚢 ⛵ 🛳️ ⛴️ 🛥️ 🚤 🛶 ⚓ — e.g. `🛳️ ⛵ 🚢 **Shipped:**`. That is how the owner
  celebrates a launch; vary the pick, never the same three twice in a row.
- End with the closing line (see "The closing line", below). Then stop.

**The closing line.** Every `/finish` — this no-op path and Phase 3's report alike — ends
with exactly one of these two lines, on its own, in upper case, as the very last thing
said. The owner runs many sessions in parallel and loses track of which ones have really been
finished; a clear, always-identical marker is what tells a truly closed session from one
that still carries a thought worth reading:

- Nothing actionable remains — no open items, no suggestion, no manual step owed:
  `<OWNER>, IT'S FINE — THIS SESSION IS REALLY DONE. YOU HAVEN'T FORGOTTEN ANYTHING.`
- Everything is merged and nothing is *owed*, but there is a suggestion, an idea for later
  or a question left with the owner, written out just above the line:
  `<OWNER>, THIS SESSION IS DONE — BUT READ THE NOTE ABOVE BEFORE YOU CLOSE IT.`

Never use the first line when the second applies — a manual step the owner still owes counts as
a note, so it takes the second line. A Phase 1 ⚠ stop (open items, another session's lock)
is not a finished session and gets neither: when the owner owes the next move it ends with
`<OWNER>, THIS SESSION IS WAITING FOR YOU — <what, in one line>` (the rules on working with the owner). A
turn that ends while its own work runs on — the reviewers, the check — asks the owner nothing and
ends `<OWNER>, THIS SESSION IS WAITING FOR SOMETHING — <what it waits on, in one line>`.
Enforced, not described: `bin/paste-paths --stop-hook` blocks a `/finish` reply once when it
reports a launch (`Shipped:`, or the `finishing` marker touched this turn) and its last line
is not one of these, or when anything but links follows a closing line; the table is
`hooks/common.py`'s `CLOSING`.

**A ⚠ stop hands over its external finish** (the owner, 2026-10-11: "when blocking a finish, don't
forget to give me a line to run in a fresh window to do external finish"). Every ⚠ stop that
ends on the WAITING line opens with a **Do this now** block holding one line: the launcher on this
worktree, for the owner to run in a fresh Terminal window once the WAITING item is settled —
`<autofinish-run's absolute path> <this worktree's absolute path>`; on the other Mac
`ssh <its alias, wharf-runs/ssh> <its autofinish-run> <the worktree's path there>`.
It is the one verb that finishes from outside with this session still open: it picks the login,
opens its own window `finish · <topic>`, takes an idle owner's lock and refuses a busy one, where
`/finish <branch>` in a new session meets this session's lock (`pickup open` stops on a live
writer). It refuses the tip a run already stopped on, so after an `--unattended` stop the line
works once the answers arrive as a commit (`memo pull`); say so beside it. Each such line is an
interruption — `bin/interruptions` counts it as a hand-off of kind `window` — so give it only where
the stop really needs the owner. `bin/paste-paths --stop-hook` blocks a `/finish` reply once when a
`⚠ step` ends on the WAITING line without it.

**A Remote Control host's session keeps its slot until it ends** (D8, 2026-09-25): a host has a
fixed capacity, nothing in Claude Code ends an idle session, and the other Mac's home-repo host sat at
4/4 for two days on finished ones. When `$CLAUDE_CODE_ENTRYPOINT` is `sdk-cli` (how a host
starts its sessions), the line just above the closing line names the slot, with this
session's `$CLAUDE_CODE_SESSION_ID` cut to 8 characters and only the command for the machine
it runs on — the other Mac: `Slot: the hourly reaper ends this session after 12 h idle; to free it
now, from the laptop: ssh <its alias> <its rc-hosts> --end
<id8>`; the laptop: `… to free it now: <rc-hosts' absolute path> --end
<id8>`. That line is information, not a manual step owed, so it does not change which closing
line applies. Never run it from here: the session is still busy until its turn ends, and
ending a session is the owner's act.

## Phase 1 — Wrap up the session

0. **⚠ Gate — this session owns the checkout.** `cat "$(git rev-parse --git-dir)/claude/owner.json"`
   must name this session. If another session holds it, curating would rewrite history under
   that session: warn the owner and stop. Also `git worktree list`: a worktree branched from this
   one shares its history — mention it.

Read the whole branch first — it is the session's record:
`git log --reverse --format='%h %s%n%b' main..HEAD` and `git diff --stat main...HEAD`.
Every `wip(no-summary)` / `wip: changes between turns` commit: `git show` it, the diff is
the summary. Commits whose `Claude-Session:` trailer isn't this session's are another
session's work sharing the branch — note them; they're reported separately.

1. **Run the contract's `check:`** — it must come back all-pass; fix what doesn't. Never
   run the `physical:` sweep here. Run it through `check <this worktree>`
   with the Bash tool's `run_in_background` (any project's line; `--only <script>…` to re-run the
   ones that failed): one script at a time, one log per script, under one of the Mac's
   `CHECK_SLOTS` (2) slots per login, waited for in turn — a killed suite reads as a failed
   one, and five checks at once got suites killed for memory (2026-10-19). Its first line names
   the log folder; the check passed when `summary` ends `DONE <n>/<n>` and it exits 0. A script at
   `rc=137` or `rc=143`, or a summary ending `INTERRUPTED`, was killed, not failed: re-run it with
   `--only`. A `check:` that is not a plain command line (prose, a sweep) is run by hand as before.
   **`--unattended`**: the launcher runs with background tasks off and a cap on each Bash call, so
   `run_in_background` is not there and a foreground check is killed. Start it in one call as
   `mkdir -p <dir> && nohup <check's path> <this worktree> --out <dir> > <dir>.out 2>&1 &`
   (`<dir>` under the scratchpad), then poll `<dir>/summary` in later calls, each under the cap, until
   its last line starts `DONE`, `INTERRUPTED` or `REFUSED`; `<dir>.out` holds what it printed. Keep
   polling in this turn: a turn that ends to wait is a stop. Unattended, bin/check runs the check line
   from `origin/main`, never the branch's (its first line says so; check-slots items 3–4, 2026-10-19).
   An `ABSENT` line is a script main added after this branch forked; step 11.1's rebase brings it, and
   it is not a failure. An `UNRUN <command>` line (exit 3) is one only this branch's line has: run each
   by its own Bash call — `nohup` and poll the same way when it runs long — and the check passed only
   when each exits 0.

   If the contract names a `live:` system:
   - Everything this branch meant to ship is deployed and the drift command shows it in
     sync. `NOT DEPLOYED` for something the branch meant to ship → deploy it; unclear why,
     or destructive (deletes, unlocks, notifies people) → ask. A live-only leftover from a
     file this branch renamed → remove it.
   - The live system's error log shows nothing new from what this branch deployed.
   - Anything this session set to a deliberately wrong value for a test is restored.
   - Surfaces that can't be deployed (UI-only config) that the branch touched: list each
     manual step still owed to the owner.

   Then **have the diff reviewed — the review gate** (docs/record/review-gate-2026-10-02.md, the owner's
   D1–D7, since 2026-10-02). Two reviews in parallel, then one merged list:
   - **Plan.** `review-gate plan` (in the worktree) counts inserted lines
     against `main` and reads the week. It names the reviewer agent (`reviewer-high`, or
     `reviewer` at xhigh for over 1,000 lines or where the project has its own) and the
     arguments for the `code-reviewer` agent's `/code-review` run. A `⚠` line means the size
     is a guess: run it from the branch's worktree. A review its row in `settings/models.json`
     turns off prints `not spawned`: spawn only the other. `plan refused` (a bad table, a stray
     `GATE_*` variable): fix what it names, or run both as above and say so in the report.
   - **Spawn both in one message.** The reviewer with `model: "opus"`, or `"fable"` where the
     project's own rules put an area this branch touched on Fable — never `inherit`, or a
     session that ran on Sonnet reviews its own work at Sonnet. Brief it with the branch, the
     worktree path and the intent in a few lines; its slice is `git diff main...HEAD` and the
     files that diff touches. The code reviewer with `model: "opus"`; brief: the worktree path
     and the plan's arguments, nothing else. Both read the diff, not this conversation, which
     is why this costs less than reviewing here.
   - **Merge.** Write each agent's final report verbatim to a file in the scratchpad, then run
     `review-gate merge --reviewer <file> --code-review <file>` with a
     Bash timeout of 600000 (its model call stops at 7 minutes). It prints one list,
     duplicates merged and sorted by severity, S1 first, with a `⚠` on any cited file:line
     that does not exist. It never fails the step: a `⚠` line at the top says what it could not
     do, and then both reports are read in full instead; so does no output at all. Jev answers
     the same pairs in shadow and only the log sees it (D4, until 2026-10-16). The same log
     line records the branch's non-doc diff size, its confirmed (`WRONG`) findings by severity
     and the models that built it, read from its transcripts — zero tokens, nothing to do here;
     `usage-report numbers` turns it into WRONG per 100 lines (model-routing section 7, S-E).
     Pass `--base <ref>` when the branch is not against `main`.
   - **Check every finding against the code before fixing it**: the merge sorts, it does not
     judge (D5). A `/code-review` finding carries no evidence line, and the skill raised about
     2.4 false findings a run on the bench. Fix every real S1, S2 and `WRONG` now; the rest go
     into the step 10 report, and anything left unresolved is an open item for step 4.

   Skip the review only when the diff changes no code or config (prose only), and say so —
   never in a repo whose `.claude/workflow.json` has `in_place` (the vault): every gated
   path there is reviewed, prose included, and it launches through `knowledge-commit` (step 11).
   There, also match `git diff --name-only main...HEAD` against `in_place` now, and take any
   hit off the branch before step 5: `--in` refuses it at the end.

2. **Did this branch change behaviour the `physical:` sweep covers?** If so, say so in the
   Phase 3 report and recommend the owner run it when it suits — it is theirs to trigger. Every
   new behaviour gets a test case; a new one with no case is an open item for step 4.

3. **Learnings go into the repo** (not just memory — the repo is what survives). Review
   the branch's prompts, diffs and this conversation for anything a future session would
   otherwise re-learn the hard way, and route each by the contract's `learnings:` and the
   "Where a learning goes" table (rule: engineering):
   - project or domain facts → the project's own homes
   - true beyond this project → propose it with `/promote` (it asks before writing)
   - worth other live sessions knowing this week → `/share`
   - a correction that had to be given twice → propose the check or hook that ends it
   Update auto-memory only for cross-session state the repo shouldn't hold. Don't restate
   what the commit log already says.

4. **⚠ Gate — no open items left.** First the **open steps** (entry D6-A of
   the layer's docs/design-docs-2026-10-14.md): `keel landing` (keel's own verb) —
   exit 1 lists each step a brief this branch added names (its `Steps:` line) that the Course doc
   does not mark done or superseded. Then this branch is **refused**: write nothing (no
   `keel step`, no Status line — only the build session, `plan digest` and Aurora write a step's
   status), stop here and list them as open items; the session that built the step marks it, or
   the owner decides. Then build one list, from four sources:
   - **This session's asks.** Go through every prompt in the branch (commit bodies) and
     the conversation: was each request fully done? Anything deferred ("later", "next
     session"), a question put to the owner that was never answered, a verification that was
     skipped, a step 1–2 finding not fixed.
   - **Open sections in the repo** — per the contract's `open-items:`, by default
     `TODO.md` and `grep -rn -iE '^#+ .*(open|still manual)' --include='*.md' .`
     Items this branch resolved → delete them or mark resolved now. Items this branch
     added, or in an area it touched → on the list.
   - **Auto-memory** project notes for the areas touched that say "still open".
   - **Relative paths in paste blocks** — `paste-paths $(git diff
     --name-only main...HEAD -- 'docs/*-20[0-9][0-9]-*.md')`: every line it prints is an open
     item (fix it now: spell the path out absolute). Dated digests only — a README's or
     CLAUDE.md's command reference is repo-relative by convention and is not a paste block
     for the owner. The owner's rule, given twice (2026-09-24, 2026-09-25).
   If the list is empty, say so explicitly ("No open items"). If not, **stop here, before
   Phase 2**, and warn the owner:

   > ⚠ N open items before this branch can be finished:
   > 1. <item> — <where it's recorded, or "not recorded anywhere">

   For each: address it now, carry it forward (make sure it's written in the right doc's
   open section or `TODO.md` — never only in memory or chat — or handed off with `/todo handoff`
   when it would earn a session of its own; a seed counts as recorded, name its branch), or
   drop it. Continue to step 5 once the owner has decided every item.

   **Nothing to launch** (docs/record/branch-reaping-2026-10-04.md E5): when `git rev-list --count
   main..HEAD` is 0, or every commit in it is a `Seed:` commit, and `git status --porcelain`
   is empty, there is nothing to curate or merge — a seed whose task turned out done, a branch
   opened and never written to. Skip steps 5–11 and end with `Nothing to launch: <branch> is
   empty (<nothing committed | seed, nothing committed after it>) — the session-start hook reaps
   it after 7 days idle, kept 7 more as refs/archive; nothing for the owner`, then the fixed closing
   line. Never delete the branch or its worktree yourself: the hook is the only reaper.

5. **Commit the wrap-up** as one checkpoint: write `commit-summary.md` in the scratchpad,
   then `git add -A && git commit -F <scratchpad>/commit-summary.md`. A `docs/handoff/*.md`
   on the branch is the seed brief this session started from: `git rm` it first, or `git mv`
   it to `docs/<topic>-<date>.md` when it became the record — `docs/handoff/` never goes to
   `main`, and doing it here keeps step 9's proof clean.
   Then **take in what GitHub has**: `git fetch -q origin <branch>`, and if
   `git merge-base --is-ancestor origin/<branch> HEAD` fails, someone committed on GitHub —
   the owner answering a memo in the web editor (`/keel`) is the usual one. Run
   `keel pull <memo>` for a memo (it names the answers
   that changed), else `git rebase origin/<branch>`, and act on those answers before step 6:
   step 11 force-pushes, and a commit it never took in is gone (2026-09-25).
   Then **stamp the review status** of each D-list record the branch adds or changes:
   `keel status --stamp <doc>` per record with `➤` lines
   (`docs/<topic>-<date>.md` or `docs/record/…`), and commit (`Docs: review stamp`) — the record keeps whether the owner looked at it
   (`· review: unseen → stood` on its banner line; E14 of docs/autofinish-design-2026-10-02.md).
   It prints "not a record" for any other doc, whose review banner it leaves alone; it does rewrite
   the Keel `Status:` line of the doc and of every file of its set, so commit what it changed.

## Phase 2 — Curate history

6. `touch "$(git rev-parse --git-dir)/claude/finishing"` — the checkpoint hook stands down.

   **If this `/finish` is abandoned from here on — interrupted, or the session ends —
   `rm` that marker.** While it exists checkpoints are off for every session in this
   checkout, not just this one. The hook ages it out after 2 h and reports that it did,
   but until then work goes uncommitted.

7. **Plan the final commits**: one change per commit in the repo's style (`Area: what
   changed` — see `git log main`), docs with the change they document, tooling on its own,
   copy-only changes in their own commit if the project keeps a voice. Checkpoint churn
   disappears (a change made then reverted on the branch isn't in any commit).

8. **Back up, then rebuild.**
   ```bash
   git branch -f "$(git branch --show-current)-raw" HEAD
   git reset --soft "$(git merge-base main HEAD)" && git reset -q
   # per planned commit:
   git add <paths> && git commit -F <msgfile>
   ```
   Hunks of one file split across commits: `git diff <file> > p`, trim, `git apply --cached p`.
   Final messages: subject + why; **no prompts** (they stay in `-raw`, local only); a
   `Deployed: yes|no|<what>` trailer where a live system is involved; the Co-Authored-By
   trailer. To redo, reset to the same merge-base again — `-raw` is the reference.
   **Never reset to `origin/main`** (or any base newer than `-raw`'s): `--soft` keeps `-raw`'s
   tree, so the commit undoes everything main gained since, and step 9 still prints nothing —
   ec782b3 deleted five docs and a lessons section #276 had merged 82 seconds earlier
   (2026-10-11). Moving onto origin is step 11.1's rebase. Step 9's `pr strays` catches it
   before the push, and `bin/pr ready` and `merge` refuse it again (`--drops-ok` only when
   the PR truly means it, never unattended). Redoing a bad rebuild starts from
   `git reset -q --hard <branch>-raw` and skips the backup line: run again, it would save the
   bad tree as `-raw`, and every check here would then pass it.

9. **Prove nothing changed**: `git diff <branch>-raw HEAD` prints nothing. **Then prove nothing
   of main's is undone**: `git fetch -q origin && pr strays` (`--local`
   for `/finish --local`, offline) prints `strays: none` — the diff above cannot see a path
   main gained, so this one judges the PR against `-raw`. A list: redo step 8 as it says.
   **Then, where the repo has a public twin, prove the curated messages publishable** (helloworld
   S7; the owner, 2026-10-20: "any repo that has a public twin applies these rules at private commit
   creation before PR merge … publishing should still check"). The publish replays each commit's
   subject and body, so a private word, a sha, a cross-repo ref (`owner/repo#N`, `repo#N`) or a
   session id written here would reach the twin, or stall its next publish:
   ```bash
   core="$(head -1 "${REGATTA_CONFIG:-$HOME/.config/regatta}/home" 2>/dev/null)"
   if hw="$(python3 "$core/modules/regatta/bin/regatta" which helloworld 2>/dev/null)"; then
     python3 "$hw" check-message --range origin/main..HEAD --repo "$PWD"
   else echo "message scan skipped: no helloworld"; fi
   ```
   (`main..HEAD` for `/finish --local`.) It scans every curated commit that changes a published
   file, checkpoints skipped as the replay skips them, and quotes its last line into step 10's
   report. A repo without `.helloworld/` at HEAD prints "no public twin, nothing to scan" — exit
   0, go on. A Mac without the word list runs the patterns alone and its last line says
   "patterns only": go on, and say so in the report. "message scan skipped: no helloworld": say
   that in the report and go on. **Exit 1 stops
   here**, attended or not — the commits it names and each hit under them: reword that subject or
   body (a sha, a ref or an id said in words, a private word left out; Orca is public and passes).
   The last commit: `git commit --amend -F <msgfile>`; an earlier one: redo step 8 from
   `git reset -q --hard <branch>-raw` (skip the backup line) with the reworded message files. Then
   step 9 and this scan again; the trees are unchanged, so its diff still prints nothing. Exit 2
   (a word list that does not read, a variable naming a missing one, a repo git cannot read):
   `rm` the `finishing` marker and report it — never skip the scan past it. A sibling repo
   (step 11) with a public twin gets the same scan before its push, `--repo <its worktree>`.

## Phase 3 — Report and merge

10. Show the owner:
   - `git log --stat main..HEAD`
   - the `check:` result: all-pass, or exactly what failed and why
   - **evidence per claim**: every "works" / "verified" in this report names how it was
     seen — `trace`, `test`, `the owner confirmed`, or `inferred` (a call returned success, a
     state toggled, nothing in the log). `inferred` items go in their own **Unverified**
     list. A notification, a sound or a physical movement nobody observed is always
     `inferred`, whatever the system's state says.
   - whether the `physical:` sweep is worth the owner's time (step 2)
   - learnings captured (file → one line each), and anything proposed via `/promote` / `/share`
   - manual steps still owed by the owner, and open items carried forward — each with where it is
     recorded **and** `checked: <how> → <result>` or `not checked: <why> — ask?` — or "No open
     items". The owner routinely does these without saying so, or in another running session, on
     another branch, in another shape (four wrong items in one recap, 2026-10-02): check the
     outcome, not the route. The cheap probe is `owed '<path, KEY@file.json,
     branch or command>'`, which reads only what changed after this session first asked (an
     item carried in from `TODO.md` or an earlier session: add `--since <when it was recorded>`);
     an expensive check is a question to the owner, never an assumption. The Stop hook blocks the list without it.
   - **seeds** (the owner's D2 c, 2026-09-29): `pickup seeds --mine
     --open --no-fetch` (Bash timeout 600000: dispatch confirms each start, up to about 4 min a
     seed) starts each seed this session made in this repo that no session has started and
     dispatch has not already sent off — through dispatch, on the other Mac, where the repo takes it;
     else a pre-filled tab, and prints each; paste its lines under open items carried
     forward. A seed this session made in another repo (the conversation shows it): `--repo
     ~/projects/<repo>` instead, which prints its start line and opens nothing
   - commits from another session (`Claude-Session:` ≠ this one), if any
   - what this branch **carries**: `pr carried` prints one
     `Carries: <branch> (<kind>, PR #n | no PR)` line per other `claude/*` branch this session
     took content from — the checkpoint hook recorded each one, pinned to the commit it saw,
     when a `git merge`/`rebase` (a whole branch) or a `checkout <ref> -- …`, `cherry-pick`,
     `cp` from a sibling worktree (a part of one) was allowed to run (D2, 2026-09-24). Paste the
     lines verbatim; they reach the PR body through step 11.3. A record is a pointer, never
     proof: at step 11 the other branch's PR closes only if, after the merge, its content is
     proved on origin/main (an ancestor of it, or every file it changed identical there);
     otherwise it stays "not on main, carried by this branch, not proved" — say in the report
     whether its remainder is still wanted. Leave the record itself alone: `pr merge` proves
     before it closes, so a line you doubt costs nothing
   - what **shipped**: one line per branch this `/finish` launches (and any other plain
     branch merged since the last `/finish` here) — the list the owner can stop tracking.
     Lead the label with a few random ship emoji, as in the no-op path above
     (`⛴️ 🚤 ⛵ **Shipped:**`) — the owner's celebration, not decoration to skip

   Commits from another session are a reason to pause and ask before merging — this
   automatic step is for a session finishing its own solo work, not for folding in
   someone else's commits unreviewed. Everything else above is reporting, not a gate:
   proceed straight to step 11 in the same turn, and after the merge end with the
   closing line — the very last thing said.

    **The vault (a repo with `in_place`) launches through `knowledge-commit`, not 11.1–11.4**
    (docs/record/personal-on-workflow-2026-09-29.md): it refuses a branch carrying an in-place record
    and commits and pushes the primary's in-place dirt before the merge; 11.1–11.4 do neither.
    Keep step 1's report in the session scratchpad, never under the worktree (`--in` commits
    everything there). Then:
    1. `knowledge-commit vault --in <this worktree> -m "<subject>"`
       refuses and writes `review.diff`: the curated, rebased form of what step 1 reviewed.
    2. Give the reviewer that file and step 1's report, asking only what differs; save its
       answer in the scratchpad. A new WRONG: `rm` the `finishing` marker, back to step 5.
    3. Rerun with `--review <answer>` after the path. Launched: copy its `rollback:` line into
       the report, `rm` the marker, `ExitWorktree remove`. The PR body is the commits plus the
       review; the step-10 report stays in chat. Any `NOT launched` (or `NOT landed`) / `NOT merged`: `rm` the
       marker and report it; a refused push means GitHub moved the branch — back to step 5.
    A third repo with `in_place` needs `knowledge-commit` taught its name first.

11. **Launch it — automatic, no approval pause (on the other Mac, one merge question).** Reaching this step already means Phase 1's
    ⚠ gate found no open items, and step 9 proved the curated branch matches `-raw`
    exactly; that is the approval. Since 2026-09-22 (D3, `docs/record/repo-sync-2026-09-22.md`) the
    launch goes **through GitHub on every machine**, and only the last step differs by host:

    1. `git fetch -q origin && git rebase origin/main` (non-interactive) — `main` on one
       machine is routinely behind origin, and a stale base merges the work in the wrong
       place. If the rebase conflicts, resolve it here on the branch; never on `main`.
    2. `git push --force-with-lease -u origin <branch>` — the checkpoint hook already pushed
       the raw checkpoints and opened a `WIP:` pull request; the rewrite replaces them.
       First `git merge-base --is-ancestor origin/<branch> <branch>-raw` (origin as step 11.1
       just fetched it; skip when the branch is not on origin): if it fails, GitHub gained a
       commit after step 5 — stop, `rm` the `finishing` marker, and go back to step 5. The
       lease alone never catches it: the fetch in 11.1 moved the ref it compares against.
    3. `pr ready --body-file <report>` — renames the PR from `WIP: …`
       to the first commit's subject and puts the step-10 report in its body; opens the PR
       when the hook could not. No `gh` needed (a Mac may have none).
    4. **On the laptop (this host is `regatta/laptop`)** — the owner's `/finish` (typed,
       or asked for: "An agent may run it" above) and the gate are the approval: `bin/pr merge` (a rebase merge; GitHub deletes
       the branch on merge), then `carried.py <primary checkout> --pull`
       (fetch, then discard the owner's answers typed on the primary that the branch carried line
       for line — they would block the pull — and nothing else, then `merge --ff-only`; a
       script, so it runs from a worktree where `git -C <primary>` is refused), remove the
       `finishing` marker. **Do not delete the branch** — no agent may (`git branch -D
       claude/*` and `git worktree remove` are denied by the hook; D1, 2026-09-25): GitHub
       deletes the remote head on merge and `sync.py`'s `prune_gone` removes the local copy at
       the next session start, once no worktree holds it — hence `ExitWorktree` with `remove`
       below. `-raw` stays; the hook sweeps it later.
       `pr merge` then handles what this branch **carries** (step 10): it fetches origin and,
       for each carried branch whose content is proved on origin/main right then — an ancestor
       of it, or every file it changed identical there — and whose worktree no live session
       holds, the still-open PR gets the comment `Launched via #N` and is closed (a close, not a
       deletion), the launch is recorded with its commit in `<common git dir>/claude/launched` (`landed`
       before the rename's S4, still read),
       and it prints `Carried branches launched — archived at the next session start: …`; put
       that line in the report (the hook archives them; no agent deletes a branch, D1). A
       carried branch that does not prove — a part was taken, the merge dropped
       something, or it moved on — is reported as "carried by #N but not proved on main — left
       open" and nothing is written for it. On the tap path below nothing closes; the next
       session's start note lists what is proved, or a later `bin/pr carried --launched-via <N>`
       from this worktree does what `merge` would have — it checks first that #N is this
       branch's merged PR.
       **A repo whose `.claude/workflow.json` holds `"merge": "auto"`** is the standing yes:
       the laptop's path on every host, no question. Only the layer (the owner's D9, 2026-09-25: it
       merges once its check passes — docs/record/coding-on-workflow-2026-09-25.md) and the vault
       (the owner's D2, docs/record/personal-on-workflow-2026-09-29.md) carry it. Nothing else grants it, and
       no session adds the key to another repo. Copy the
       `rollback:` line `pr merge` prints into the report, on any repo.
       **On any other host (the other Mac)** — ask, then merge only on an explicit yes (the owner,
       2026-09-24: "enable agents to auto-merge PR from /finish with my explicit approval").
       `/finish … --merge` in the message that started this `/finish` is that yes, given up
       front: skip the question and take the laptop's path (D3, 2026-09-25).
       **A repo whose `origin/main` has `.github/workflows/automerge.yml`** asks nothing: the owner
       chose automerge for it (docs/ci-automerge-rollout-2026-10-06.md, D1 = B), and step 3's
       `pr ready` already armed it, so the question would come after the answer. Run `bin/pr
       merge`, which waits for automerge to launch it, and say `merged by automerge` in the
       report; to stop one, label the PR `hold` before step 3.
       One `AskUserQuestion`, after the step-10 report: *"Merge PR #N (<title>) into main
       now?"* — options **Merge now** / **Leave it for my tap**. **Merge now** → exactly the
       laptop's path above. Anything else, or no answer (a non-interactive session) → stop
       after step 3: remove the `finishing` marker, keep the branch and `-raw`, report the PR
       URL just above the closing line; the merge is the owner's tap on github.com, and `sync.py` brings
       `main` down at the next session start. The yes is for this PR only: never carried to
       another PR, another repo or a later `/finish`, and never inferred from "ship it".
       A repo whose `live:` runs from `main` (household's launchd job) needs its restart
       after the pull — name it in the report, run it only if the contract says to.

    **A sibling repo.** A session opened in one repo may also have committed in another,
    on a `claude/*` branch in that repo's own worktree (reached with `cd <repo> && git …`).
    Launch each such branch too, after this one and the same way: its check, step 9's message
    scan where it has a public twin (`--repo <that worktree>`), then
    `git -C <that worktree> push --force-with-lease -u origin <its branch>` — the push shape
    the checkpoint hook accepts for another repo (`cd <repo> && git push …` is refused) —
    then `cd <that worktree> && pr ready --body-file <report>`, and
    the same merge question, one per PR. Report every PR it produced.

    **`/finish --local` — merge into local `main` instead**, for a machine that is offline:
    `git rebase main`, then `carried.py <primary checkout>
    <branch>` and from the primary checkout `git merge --ff-only <branch>`, remove
    the marker; the branch stays (no agent deletes one). Say so in the report: `main` is then
    ahead of origin until the owner pushes it, and the other machine will not see the work until
    then — and a never-pushed branch has no upstream for `prune_gone`, so the session-start
    hook archives it once it is idle and proved launched (coding-on-workflow D4).

    Then, if this session is in a worktree, **leave it with `ExitWorktree`** — `remove`
    when the branch has just been merged, `keep` if anything stopped short. This tool call is
    the one exception to "no agent removes a worktree or a branch": by its own schema, `remove`
    deletes the worktree directory *and its branch* (not verified against a merged branch in
    practice); if the branch survives, `sync.py` prunes it at the next session start.
    Exiting moves the session's transcript back to the repo's own project directory; a
    session closed while still inside a worktree leaves its transcript under
    `~/.claude/projects/<repo>--claude-worktrees-<name>/`, where the VS Code sidebar never
    looks and `claude -r` shows it only under `Ctrl+A` (the owner, 2026-09-21; five
    sessions had gone missing that way).

    If the owner objects after seeing the report — on the other Mac, unless they said **Merge now**, nothing has merged yet: rewrite
    from `-raw` after `rm`-ing the `finishing` marker and force-with-lease the branch again.
    On the laptop the rebase merge is on GitHub already; `git revert` the range on a new
    branch and launch that the same way — never rewrite `main`.
