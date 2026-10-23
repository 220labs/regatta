# Dream — Aurora's weekly section (Sundays)

Weekly consolidation: read the week's prompts, memory, bulletin and inbox; propose ONE
reviewed change to the always-loaded layer (me/, rules/) plus memory clean-up, and a
mechanism for every correction the owner had to repeat. Was the `/dream` skill until 2026-10-03
(the layer's docs/record/regatta-2026-10-03.md); `/aurora dream` runs it on its own, `--days N`
widens the window. `<regatta>`, `<vault>` and the rest: the aurora skill's "Where things are".

**With `--scope <scope>`** this file is not the one: read `sections/dream-scope.md` beside it and
follow that instead — one scope's pass, its dream in the scope's anchor and its generalised lines
in the vault's `inbox/upstream/<scope>.md` (knowledge-layers S5).

The shape is Anthropic's "dreaming" for Managed Agents (the layer's DESIGN.md F2): read past sessions
and the current memory, write a *reorganised* version for human approval, never edit the
live layer directly. Here that means: **this section writes one proposal file and its
records (step 4: the log line, the bulletin prune), nothing else.** `/embark` walks the owner through it and applies what is approved. Scheduled for Sunday
night (DESIGN section 8); safe to run by hand any time.

## 1. Gather — bounded, in this order

```bash
<module>/bin/week-digest --days 7                 # 7, or the --days Aurora was given; what the owner typed, per project; ✱ = maybe a correction; a confidential scope's sessions counted, not quoted
<regatta> knowledge-numbers                       # the numbers (plumb)
<regatta> interruptions --days 7 --list all       # every question put to the owner this week, and the answer
<regatta> bulletin.py --list                      # live bulletin entries
<regatta> repos --branches --fetch                # every repo's idle claude/* branches: launched (archived at session start), probably launched (review line), not on main, and the live archives
<regatta> repos --github                          # every repo rebase-only with delete-on-merge; a DIFFERS line becomes a P-item
```

Then read:
- `<vault>/me/*.md` and `<layer>/rules/*.md` — the always-loaded layer under review.
- Every `<vault>/memory/<project>/MEMORY.md`, and the memory files changed this
  week: `ls -t <vault>/memory/*/*.md | head -40` (read those whose mtime is
  within the window).
- `<vault>/inbox/`. **Never touch `~/Library/Mobile Documents` (iCloud Drive)**
  — not even `ls`: macOS raises a permission dialog, and an unattended run stalls on it
  until someone clicks (2026-09-16). A phone inbox is read only if
  `<vault>/inbox/.icloud-inbox` exists and names its path, which the owner creates
  after granting Claude Code iCloud access once, by hand.
- `<module>/bin/week-digest --promote-tags` — tagged candidates (the `<!-- promote:` lines, as
  `grep -rn` prints them, stopping at a confidential scope's folders; never grep `<projects>` yourself:
  nothing reads down into a confidential node, knowledge-layers S4).
- The last two entries of `<vault>/log.md` and the previous
  `<vault>/dreams/*.md` — what was already proposed, approved or rejected.
  A rejected proposal is not re-proposed unless something new supports it; say what.

## 2. Think — six questions, each answered with evidence

1. **Repeated corrections.** Which ✱ prompts correct the same behaviour twice or more
   (same week, or this week and a memory already on file)? For each: the quotes, the
   sessions, and the **mechanism** that would make the correction unnecessary — a hook, a
   test, a check in a skill, a template change. A third line of prose is not a mechanism
   (DESIGN F7).
2. **Promote.** Which memory entries, tags or bulletin items pass the test in rule:
   engineering (true in two projects or plainly project-independent; for `me/`, true in a
   chat with no code)? Draft each as the exact line and its destination.
3. **Retire and merge.** Which lines in `me/`, `rules/` or a `MEMORY.md` are duplicated,
   contradicted by a newer fact, or dated and unexercised for 90 days (grep the digest for
   their key words)? Apply the prune test to every always-loaded line: *would removing this
   cause a mistake?* Propose the cut when the answer is no.
4. **Inbox.** For each inbox item: where it goes (a `me/` line, a project TODO, a venture
   note, a project doc, the bin) — one line each. A memo stub with `filed:` is already in its
   project (D18): only say so if the home looks wrong; one with `route: … not filed:` carries
   the runner's proposal — confirm or correct it. An empty inbox (the phone one included,
   test files aside) is not reported at all — no section, no line (weekly 2026-09-29, Q4).
5. **What is the owner waiting on, and why?** Every open decision (`**Decide:**` items, open
   D-items, Q-items from last week): its age, and what the waiting ones have in common (a
   missing fact, a physical check, a question that could have had a default). Branches not on
   main are the branches section's, which ran before this one: count them and point at its
   file — the newest `dreams/*-branches.md` of this week, whose date may be yesterday's when
   the night crossed midnight (`ls`, never a date you compute); do not judge them again. Propose the change that would have
   avoided the wait. Then the usage-limit hits
   from `knowledge-numbers`: when they happened (the digest has the times), what was running,
   and whether a model or effort choice would have spread the load.
   Then the interruptions (number 6, the owner 2026-10-10: "continuously think how we can minimize
   unnecessary interruptions — where the outcome could have been predicted"). From the
   `interruptions --list all` rows, group the `recommended` ones by what was asked (a launch,
   a model switch, a merge of carried work, a naming pick…) and read the `free-text` answers for
   "don't ask" and for an answer that was the same last time. For the two or three biggest
   clusters, propose the mechanism that answers them without the owner — a default in a skill, a
   standing yes in a `workflow.json`, a hook that refuses the question — as a P-item with the
   rows it would have spared. Name the questions asked with no pick (`unranked`) by session:
   each broke the one-recommendation rule. A cluster the owner overrules as often as accepts is
   not predictable; leave it. The rest of the class counts too ("they're all attention
   grabbers"): the permission dialogs by tool and command (an allowlist rule or a verb in
   `bin/` would end the cluster), the hand-offs (a paste a session could have run, a log-in a
   machine could keep, a WAITING line repeated turn after turn), and the trust dialogs waiting.
6. **Ventures.** For each file in `<vault>/ventures/`: which gate is it at, how
   long has it sat there, what does this week's digest say about it?

## 3. Write the proposal — one file, nothing else

`<vault>/dreams/<yyyy-mm-dd>.md`:

```markdown
# Dream — <date> (<N> sessions, <M> prompts)

Numbering: P-items are proposed changes (P1…), Q-items are questions for the owner (Q1…).
How to answer: each P- and Q-item ends in a `➤ Answer:` line pre-filled with the
recommendation — leave it to accept, overwrite it to change. Open feedback at the bottom.
Every file mentioned is a markdown link (with line numbers where useful).

## Do this now
<anything the owner must run or paste — usually empty. Never a branch deletion: launched branches are
archived by the session-start hook (coding-on-workflow D4–D6, 2026-09-26)>

## Numbers
<knowledge-numbers table> · corrections repeated this week: <n>

## Branches
<per repo, from `repos --branches`: launched — count and the proof each rests on; **launched but
not finished** — its own list: each branch whose docs on main still hold open items (the
"open items: docs/x.md (N)" suffix), with the files, so the owner decides whether the work is done
or only merged; probably launched — the hint each rests on, with its `pickup review` line: the owner's
call, pick up or `pickup archive --confirmed`, which no agent runs; not on main — the count and
a link to the branches section's file (question 5 says which), where each has its verdict; archived — what the hook and
the classifier archived this week>

## P — proposed changes
P1. <one-line title> — <destination file>
    why: <evidence: quotes + session ids>
    ```diff
    <exact diff>
    ```
    ➤ Answer: apply
...

## Repeated corrections → mechanisms
<one block per correction: quotes, sessions, the mechanism, where it would live, effort>

## Memory clean-up
<per project: merge / retire / move-to-rules, one line each>

## Inbox
<item → destination>

## Ventures
<venture: gate, days at gate, this week>

## Q — questions
Q1. <question> — why it matters, the options
    ➤ Answer: <the recommendation>

## Feedback from <owner>
```

Budget check in the Numbers line (`me/` ≤ 100, `rules/` ≤ 250); a proposal that would break
it must include the cut that pays for it.

## 4. Record

- Prune expired bulletin entries: `<regatta> bulletin.py --prune`.
- Append to `<vault>/log.md`:
  `- yyyy-mm-dd dream: <N> P-items, <n> repeated corrections, <the one that matters most>`
- Commit: `<regatta> knowledge-commit <vault-name> -m "Dream: <date>"`. Everything
  the dream writes is a vault record (`dreams/`, `log.md`, `bulletin.md`), written
  in place in the primary; the straight form commits only records and names anything else it
  left (the layer's docs/record/personal-on-workflow-2026-09-29.md). A proposal that changes `me/` is applied by
  `/embark`, through a reviewed PR — never here.

## 5. Report

Unattended: nothing else. Interactive: the three proposals that matter most, one line each,
and "run `/embark` to review".
