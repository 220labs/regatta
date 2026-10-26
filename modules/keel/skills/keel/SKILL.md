---
name: keel
description: Hand the owner a memo's D-list (the ➤ Answer format every digest and design doc here uses) to answer — always as the one hand-over line `keel line` prints, course (the doc's spacesheep page) | github — file — and take the answers back as commits. Use whenever a doc asks the owner something, and when the owner says the answers are in. Deterministic — bin/memo reads git and does the conversion; this skill runs it and relays the lines.
---

`bin/keel` in this module (the Keel layer's tool: `/memo` and `bin/memo` until 2026-10-14, `bin/memo` kept as a shim; `memo-form` before 2026-09-29; not `/feedback`, which Claude Code reserves). Its messages still begin `memo line:` and `memo:` — the page's reply marker, which past threads carry. Answers
travel as commits on the doc's own branch, never by launching the doc on `main` to be answered
(docs/feedback-2026-09-29.md). Run the command, relay its lines. $ARGUMENTS

A command written `<bin>/<tool>` below runs the tool's own path, as `regatta which <tool>` prints
it (`keel` is this module's; `regatta` is `<home>/modules/regatta/bin/regatta`, `<home>` the first
line of the regatta config dir's `home` file). No overlay keeps a copy since B14b (2026-10-23).

**When a memo channel fails** (a page that will not load, a Save that does not arrive, a mirror
that is down), take the D-answers in chat and copy them verbatim into the doc's `➤ Answer:` blocks
(the owner, 2026-10-04).

## The hand-over line — every doc, every reply that asks (since 2026-10-07)

Every doc shown to the owner in chat is **one line**, in this order (the owner, 2026-10-04/05; enforced in
every repo 2026-10-07: "It should apply to every single message that asks for Dx to be answered"):

`[course](<the doc's page>) | [github](<blob URL>) — [<file name>](<absolute path>#L1)` with D-items;
`[github](<blob URL>) | [space](<the doc's page>) — [<file name>](<absolute path>#L1)` without.

`python3 <bin>/keel line <doc>` does the work and prints exactly that line on
stdout; put it in the reply as it is, never retyped or built by hand. Labels exactly `course`,
`github`, `space` (`course` was `form` until 2026-10-17; the owner: "rename it to course, which is what
it's named now"); no "(read)", no talk of phones. What each part is:

- `course` — the doc's spacesheep page, which `line` creates or updates (`keel sheep`), when the
  doc has D-items: the page *is* the form since 2026-10-14 (option buttons, notes, Accept all, one
  Save), answered in a VS Code tab or on the phone. Where no page can be made (below), the form is
  keel serve's on 127.0.0.1, as before — bar an unattended run or a Remote Control session, where
  127.0.0.1 opens nothing.
- `space` — the same page when the doc has no D-items: its read copy.
- The page is left out only where `never_mirrored` refuses (the vault, the transcripts, `rules/`),
  or on a Mac without the `spacesheep` CLI or a key. The page is a copy of git: commit the doc
  first, or `line` leaves it out (off a `claude/*` branch, where no checkpoint commits it, it is
  then not owed either). While `spacesheep mirror` runs on this Mac (CLI 1.27+), `line` prints the
  page at the mirror's address (`http://localhost:4280/…`, bin/sheep's `local_url`), which VS Code
  opens in a tab (`"localhost:4280": "simpleBrowser.open"` in `workbench.externalUriOpeners`);
  elsewhere, and in a Remote Control or unattended run, the spacesheep.dev address. The hooks take
  the page at either address while that mirror runs; a localhost link with no mirror behind it is
  refused.
- `github` — ONE link, the read (blob) view, never the edit page; only once GitHub holds this
  copy (below).
- the file name links the absolute path with `#L1`, which VS Code opens as text, not preview.
- other formats (a claude.ai artifact) follow the page as more `|` links when they exist.

**A nested set** (a Course entry and its component docs, `docs/<topic>-<component>-<date>.md`) is
one line **per file**, the entry's first, as `python3 <bin>/keel line <entry>`
prints them together (since 2026-10-15, entry S8; `the overlay's rules` "How to talk"): put
all of them in the reply as printed. A file with no D-items gets no `course` part; `keel line
<component>` prints that file's line alone. Each file's form holds its decisions beside their
component; the entry's form lists the set, never repeating a component's items.

A part `line` cannot make is left out, never faked, with `keel line: no <part> — <why>` on
stderr, and exit 1 when the part was owed. Run the fix it names and `line` again; if there is
none, say the reason in the reply. Its `lint:` lines go to stderr too (below).

**Enforced at Stop, in every repo.** `bin/paste-paths --stop-hook` (user-wide) blocks once a
reply that asks D-items — `➤ Answer:` in its prose, or a WAITING line naming a D-item — without
its doc's line: the doc the items come from on this branch, else any `.md` the reply links; the
github link checked against this branch's blob URL, the form or the page against this doc's pin. With no doc at all it blocks for that (**a D-list
never lives only in chat**; the owner, 2026-10-04: "hand me the docs EVERY SINGLE TIME you remind me
of Dx answers"): D-items go into a doc on the branch first. The checkpoint hook asks the same
line of a turn whose commit wrote D-items into a doc and handed it over without asking; when the
reply asks, it stands back, so one Stop never blocks twice. The checkpoint pushes a turn that adds
`➤ Answer:` lines at once and deploys the page right after (`keel sheep`, on a Mac with the CLI
and `SPACESHEEP_KEY`) — so a doc written this turn gets its page only at Stop, and that first
time the block is how the form reaches you: run `keel line` again and end the reply again.
The github link dies when the PR merges (GitHub deletes the branch); `keel line` on `main` gives
a new one.

**The github part proves itself** (since 2026-10-04): `line` fetches and prints it only when
GitHub holds this copy of the doc (or a newer one, with the owner's answers), or on a `claude/*`
branch already on GitHub when this copy is only ahead (`keel line: github pending:` — the hook
pushes it at this Stop and re-checks); otherwise it is left out with the fix — unpushed, or the
two sides split because the owner answered on GitHub while this branch changed the doc (`keel pull`,
then push). The checkpoint hook blocks a reply once whose GitHub link to this branch shows a copy
without this checkout's changes. Three replies on 2026-10-04 sent the owner such a page
(docs/record/memo-links-2026-10-04.md). `keel url` is `line`'s old name: until 2026-10-07 it
printed `local:`, the edit URL and `read:`, the shape the hooks then demanded.

**The form is the standard** (the owner, 2026-10-03: "open in a tab here, that's still the best
interface"). The doc stays the source; GitHub and the page are the other ways in.

- A click on the form opens it in a VS Code tab through the mirror, or anywhere else as the
  spacesheep.dev page. Its Save goes into the space's room (`window.ss.emit`); its comments go to
  spacesheep. Neither reaches the doc by itself: when the session should go on after the owner answers
  (below), run `python3 <bin>/keel sheep wait <doc>` with `run_in_background` and
  `timeout: 7200000` right after `keel line`. It exits on a Save (within a `live_events` call) or
  on new comments once they go quiet, having merged them into the doc — that exit wakes the
  session: read its lines, commit the doc, then act on the answers the `/keel pull` way. A Save
  merge refuses (an answer that would restructure the doc) leaves the doc as it was, with the
  reason in the output (a `refused save` line). The room keeps a Save made while nobody listens: `keel sheep pull <doc>
  --write` takes it later. `wait` stops after 110 minutes with nothing on the page; say so. The
  page is a copy of the commit it was deployed from: after the merge, commit, and the Stop hook
  redeploys it.
- **After Save, go on — no prompt needed** (the owner's D6–D7, docs/subagent-cache-2026-10-04.md).
  Apply the answers (an architect's doc: agents/architect.md's revision rule), then take the next
  stage: `python3 <bin>/pickup next - <<'EOF'` with the next stage's prompt,
  self-contained and ending "then run /finish once the check is green" when it is the last
  stage, then `EOF` (stdin and a quoted heredoc: in double quotes the shell would run its code
  spans). It answers one of three verdicts (D1, 2026-10-05: a stage starts the next itself):
  - `continue` (under 120k context): build it here, run the check, and once it is green run
    `/finish` yourself (the Skill tool; skills/finish, "An agent may run it" — D8), whose
    open-items gate still stops on anything left.
  - `seeded <branch>` (over 120k, in a repo dispatch takes — `physical: none`): the prompt is
    committed as the branch's brief and `dispatch --next` started it unattended; end the turn
    with one line, `Started <branch> unattended (dispatch); its window is titled run · <topic>`, and
    write nothing more there. Its "then run /finish" is the run's to follow. A refusal (a chain
    of five, the run cap reached, a lock handed to a tab) stops with dispatch's reason: relay it.
  - `tab` (only where dispatch refuses): the lock is handed over and a fresh tab holds the
    prompt — end the turn with the WAITING line ("press Enter in the new tab") and write nothing
    more; in that tab the line, pressed Enter on by the owner, is the owner's word for the launch.

  Stop earlier only at a new D-item, a red check, or an answer that rejects the plan.
- **Elsewhere, with `Artifact`**: `--form` steps 1–2 below, then `Artifact` `open`.

## `/keel [<word>]` — pick a recent memo

`python3 <bin>/keel list` (newest first; `docs/*.md` and top-level `*.md`
of every repo under `~/projects`; a worktree copy shows while its checkout lacks the memo).
Show the rows numbered — date, repo, title, decisions, unanswered — and ask which, in one line.
A word filters by title or path; exactly one match goes straight to the link. The CLI takes no
filter (`keel list open` is an argparse error): the session filters the rows it got. `open` is a
subcommand (below), so a title containing "open" is filtered as `/keel list open`.
"Unanswered" is one rule in `list` and `open`: `answered()` — an answer in the box, or a `>` reply under the item.

## `/keel open` — what is still open

`python3 <bin>/keel open [--json]` (2026-10-10; no git, about a second): one list
across every repo up to four levels under `~/projects` — open **post-mortems** first (a
`docs/*.md` named or headed post-mortem, open until its `Status:` line says `resolved`; a resolved
one still outside `docs/record/` is listed as "not archived"), then docs with **unanswered
D-items** (or a D-list that does not parse, e.g. a duplicate id: `unparseable — …`), then any doc
with `Status: open — …` in its first 15 lines. `docs/record/` is the archive and is skipped. Show the rows as printed (kind, repo, title, what is open, path) and ask which to pick up.

The Status convention: a post-mortem's first lines carry `Status: open — <what remains, who owes
it>`. When every item is done and verified it becomes `Status: resolved <yyyy-mm-dd> — <how
verified>`, and the file is `git mv`'d to `docs/record/` in the same commit. Any design doc may use
`Status: open — …` to be tracked the same way. The session start prints
`📂 Open: N post-mortems, M decision docs, K open docs — /keel open` when anything is open
(hooks/bulletin.py).

## `/keel <doc>` — the line, checked

`python3 <bin>/keel link <doc>` prints the title and the decision count, then
the hand-over line (`keel line`, above). A `keel line: no github —` line names the push that
fixes it: run it, then `link` again; `keel line: github GitHub has commits this checkout lacks`
means `pull` first. Reply with the title, the decision count, and the line. Never restate the
decisions in chat.

## `/keel pull <doc>` — answers back (the owner says *answered*, *done*, *pulled*)

`python3 <bin>/keel pull <doc>` fast-forwards, or rebases the session's
own commits onto GitHub's; never merges, stops on a conflict; names the `D<n>` answers that
changed and whether the open feedback did. Relay that, then act on the answers the memo's way
(`> **Done.** …` under each block). A branch's `/finish` takes such commits in at its step 5.

**Recommendations stand** (D11-A, docs/autofinish-design-2026-10-02.md): `keel status <doc>`
says whether an unanswered doc stands at link + 24 h untouched (`stands-at`, `due`, or why not),
and on *stand it* / *stand it at <time>* run `keel stand <doc> [--by <hours>]` — the only way in
where the contract's `physical:` is not none, `--by 0` now — or `keel stand --void <doc>` on
*don't stand it*; `stand --apply`, at the deadline, is the autofinish launcher's step: armed, it
runs it on each `due` doc of a branch just before it starts that branch's `/finish` (rule D),
and never in a repo whose autofinish is off. Since entry S3 (docs/design-docs-2026-10-14.md, D4-A)
a stand takes only `Reversible: yes` items with a bare pick — `no`, unmarked, conditional and
reopened items stay open and the doc reads `part-stood`, which autofinish refuses; a prompt in the
session or an uncommitted edit restarts the 24 h clock, and only a form Save, a GitHub edit, the owner's
commit or `--void` voids. `keel stand --sweep` stands every `due` doc on a `claude/*` worktree and
pushes it, at most hourly from `bin/ask poll` on the laptop once the owner runs `keel stand --arm` —
never arm it for him. A build session marks its step with `keel step <doc> S3 done --branch <b>
--stamp` (entry D6-A). The same line ends with the **review status** (E14)
— `unseen · opened · partial · reviewed`, `stood`/`waits`/`stands <time>` beside it — also in
`keel list`, on the branch in `bin/repos --branches` and the 🌿 note, and stamped into the
record's banner at launch (`keel status --stamp`): quote it when the owner asks whether a doc was seen.

## `/keel sheep <doc>` — the spacesheep page (the owner says *answered on the page*, *commented*)

The page is the form, deployed from the committed memo (docs/memo-on-spacesheep-2026-10-11.md):
the owner answers there with the option buttons, notes and one Save, or comments — on a decision card
to answer it, on any other line to leave a note there, on the page for open feedback. A Save is an
event in the space's room, a comment is on the page; neither reaches the doc until something takes
it in: `keel sheep wait <doc>`, run as the session's background shell, does it and exits, which
wakes the session; `keel sheep pull <doc> --write` does it by hand, later. Nothing else collects
them yet (the sweep that pulls with no session listening is not built). the vault, `rules/` and the
transcripts are never mirrored: their form is keel serve's.

- `keel sheep <doc>` deploys by hand (a memo with uncommitted changes is refused — the page names
  a commit); `keel sheep check <doc>` says `current` or `behind by N commits`.
- On *answered on the page*: `keel sheep pull <doc>` previews what each open thread and each Save
  becomes, and which stay open and why (an older comment on the same D, or one older than a Save
  on it; an answer changed in git after the comment, or since the commit the Save's page showed —
  git wins). A Save `merge` refuses is set aside in the pin's `refused_saves`, named in the
  output, and never blocks the next pull: copy its words from there if they matter. Relay it, then `keel sheep pull <doc> --write`: the memo is rewritten
  through `merge`, each thread taken gets one `memo:` reply and stays open (the owner resolves a thread, never this tool). Commit it on its
  branch, then act the memo's way (`> **Done.** …`). A preview that says no comment was read
  although the page has some means `list_comments` answered in a shape this tool has not seen:
  the raw answer is saved where the line says — teach `comment_threads` that shape, never guess.
- The pin map (doc → space) is per branch and per Mac, in `~/.local/state/memo/sheep.json`: a
  doc first deployed on the other Mac gets a second page here. A doc with no pin takes over an
  earlier page when it is renamed (`git mv`) or read from `main` after its branch landed. The old pin
  says `moved_to`, and a deploy of the old doc prints where its page went. A renamed or landed doc's
  old path that changes again gets a page of its own. A doc that replaces another under a new name
  (a `Supersedes:` line) gets a page of its own too: hand the owner the new one.
- Never fix a memo through the page: a comment starting `@co-shepherd` or `@spacesheep` lets
  spacesheep's own agent answer or edit the deployed page, and the next deploy from git overwrites
  an edit without a word. Its reply carries `via: co-shepherd` (`@Co-shepherd 🐑 (asked by …)` in
  the text form) and is never read as the owner's words.
- A reply the owner types under a thread already taken, while the thread is open, is taken in by
  the next pull (on a D-card, the thread's words again as the answer). A pull names two things it
  does not take in: such a reply under a resolved thread (`late reply:`), and a thread resolved on
  the page that no pull read (`resolved on the page, not read:`); each is named once, so say it
  again as a new comment if it matters.
  `keel sheep prune [--dry-run]` drops, from this Mac's pin map only (no call to spacesheep),
  the pins of branches gone from origin and over 14 days old, with their page folders.
  `keel sheep drain [--if-due]` (`ask poll`, at most every 6 h) empties every recent page's room — opens into `opens.jsonl`, the page's reading heartbeat (`memo-read`, a minute each) into `reads.jsonl` for crew-report; neither wakes a `wait`.

## `/keel --form <doc>` — the claude.ai form (outside VS Code; also on request)

The fallback where there is no spacesheep page: the page is a form with answer boxes, but only a
`/login` session can publish it.

`Artifact` exists only in a session signed in with `/login` to a claude.ai plan — the laptop's
CLI, VS Code panel and `claude -p` all have it (probed 2026-09-30). Not a session on
`CLAUDE_CODE_OAUTH_TOKEN` (`setup-token` makes model requests only — every session of a
headless login over SSH), an API key, or `--bare` (code.claude.com/docs/en/artifacts#availability,
read 2026-09-30; lessons/claude-code.md).

0. `ToolSearch` `select:Artifact,ArtifactData`. No match → no form to publish, and no dead end:
   say why in one line, then reply as `/keel <doc>` does (`keel link`: the hand-over line). On the laptop (`~`) also run step 1 and
   give the built file as a link: it works in a plain browser, keeps a draft there, and its
   "Copy as text" block pasted back merges as in step 3. `SendUserFile` is no way around it:
   it needs a Remote Control client connected.
1. `python3 <bin>/keel build <doc> -o <scratchpad>/<stem>.form.html`;
   zero decisions means nothing to publish — say so.
2. `Artifact` publish: that file, `capabilities` `{"db": {}}`, `icon` `form`, one-sentence
   `description`. Reply with one line and the link: "answer on the page; say *merge* when done".
   Republish after a memo change to the same file path; stored answers survive (keyed by `D<n>`).
3. On *merge*: `ArtifactData` `get` (`collection` `answers`, `doc_id` `current`) → write it as
   returned to `<scratchpad>/answers.json` → `keel merge <doc> <that file> --write` → commit
   the doc on its branch → relay the summary and act. A pasted "Copy as text" block merges too.
   The summary counts **notes**: the owner can tap any paragraph, bullet, table row or heading and
   write under it; `merge` puts each as `**<owner>, <date>:** …` under its source line (inside its
   list item), or under the open feedback when the memo moved too far to tell. Each one is a
   mid-doc comment like those in the doc on GitHub — reply under it.

A D-item in the D10 shape (`➤ Recommended:` on its own line, then `➤ Answer:` above an empty
block, options as `- A — …` bullets; the exact form is in agents/architect.md) shows the
recommendation read-only, the answer box empty, and the options as buttons; plain `A — …`
option lines still read, and an item in the older shape is pre-filled as before. A D-list in
the D10 shape ends with a heading or `---`: `merge` refuses to rewrite an answer block that runs
into prose below the list rather than delete that prose. `keel line` and `keel link`
are the check at hand-over: each prints `lint:` lines when a pick rests on
a claim the doc lists as not verified — fix the doc (probe, or make the pick conditional) before
handing the owner the link — and `lint:   warning:` lines for unbulleted options and for answer text an
architect left in the owner's box (`keel lint <doc>` prints the same).

## `/keel --on-main <doc>` — answers typed into a doc on the primary's `main`

No launch. A plain `diff <primary>/<doc> <worktree>/<doc>` (a worktree session may not point
git into the primary); `cp` the primary's copy over the branch's when the branch never changed
it, else apply its hunks; `cmp`; reply under every hunk. Leave the primary's copy alone:
`hooks/carried.py` discards it once `main` carries it line for line (/finish step 11, sync.py).

## the vault and a memo not on a `claude/*` branch

No automatic link. `dreams/` is a record, answered in `/embark`: it is written and committed in
place (`knowledge-commit the vault -m …`). Any other memo in the vault goes on a `claude/*`
branch like every doc to be answered: `knowledge-commit the vault --open memo-<slug>`, write it
under that path, push the branch with the push `keel line` names (from a session opened in
the vault — another repo's session cannot run git there), then `/keel <doc>`. `keel parse <doc>` shows what the tool sees
when a memo reads oddly — fix the memo, not the tool, unless the shape is one the repos use.
