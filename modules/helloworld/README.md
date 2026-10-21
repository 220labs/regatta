# helloworld — the public door

The first Regatta module to go public, and the door a project goes out of: name it (`/name`,
`name-check`), then publish it (`helloworld`). Was `opensource` until 2026-10-18.

| Piece | What it does |
| --- | --- |
| `bin/helloworld` | puts a private repo's allowlisted files on its public twin, with a privacy scan as the gate |
| `bin/name-check` | is a name free as a domain and as a GitHub, npm and PyPI handle, and what does the domain cost; read-only |
| `skills/name` (`/name`) | takes an idea note to a decided name: probed, priced, trademark-searched, one naming doc |
| `tests/check.sh` | both suites; no network |

Install: `claude plugin marketplace add <this repo>`, then `claude plugin install helloworld@regatta`
(it needs the core, `regatta`). From a clone: `sh modules/helloworld/install.sh --check` says
whether the core, the word list and the pre-push guard are found.

## The publish gate

`helloworld` puts a private repo's allowlisted files on its public twin, its curated commits
replayed one by one (one squash commit only as the fallback), with a privacy scan as the gate. A repo opts in with `.helloworld/allowlist.txt`, `exemptions.txt`,
`remote` and `identities` (the old `.opensource/` is still read, with a note to rename it); the
private word list lives outside every repo: `$HELLOWORLD_WORDLIST`, else `$OPENSOURCE_WORDLIST`,
else `helloworld/wordlist.txt` in the regatta config dir (`$REGATTA_CONFIG`, else `.config/regatta`
in the home folder), else the old default `.config/opensource/wordlist.txt` in the home folder.
How the scan works, line by line: the tool's header. Every pattern has a planted case in
`tests/helloworld.sh`. `publish --pr` pushes from a clone guarded by the wharf module's pre-push
hook (`templates/code/git-hooks/pre-push`, found through the core); without wharf it refuses.

## The verbs

| Verb | Who | What reaches the public repo |
| --- | --- | --- |
| `check <repo> [--ref R]` | any session | nothing: build, scan, diff-stat against the public main, the dry replay, and how many commits wait for a publish |
| `publish --pr <repo> [-m TITLE] [--topic T] [--note TEXT] [--squash]` | an agent (the usual route) | a `claude/publish/<date>-<topic>` branch and a PR, the replayed commits on it; **the owner's merge is the publish**; auto-merge off |
| `check-message --subject S [--body-file F]`, `--message-file F` | any session, at the private commit's making | nothing: one message scanned as the replay would scan it; exit 1 when the replay would refuse its subject or drop its body |
| `check-message --range A..B [--repo R]` | wharf's `/finish`, on the curated branch before its push | nothing: every commit of the range scanned so, checkpoints and commits changing no published file skipped (as the replay skips them), each finding under its commit; nothing to scan without `.helloworld/` |
| `publish <repo>` | the owner, in their own terminal (refuses `CLAUDECODE` and a non-terminal stdin) | the public `main`, after the repo's name is typed back; the first publish, and any later one the owner prefers |

**The replay** (2026-10-19; the design's D1-B, the owner: "I want the 2 repos to be as similar as
possible. We'll squash as a fallback, but will try to avoid it."). The base is the newest private
commit whose allowlisted tree is the public main's. Each commit after it goes up as one public
commit: its allowlisted tree, its subject and body less every `Co-Authored-By`, `Signed-off-by` and
`Claude-Session` line and the workflow's `Deployed:` and `Stood-By:` (by key, any case or value), the publishing identity, its own dates at
`+0000`, the gate's `Signed-off-by`. Each is scanned on its own. A commit that changes no published
file stays private; a `wip:` checkpoint, a commit whose tree fails, or one whose lists hold a file,
exemption or credit the reviewed ref took back folds into the next that passes; a body that fails is dropped and the subject goes alone; a subject that fails refuses the
run until `.helloworld/messages` gives that commit a reviewed subject (`<private sha> <subject>`).
A message meets the whole word list and the tree's patterns, and its own (2026-10-20, the owner's
answer to D2 of the S2 digest): a sha-like token (7-40 hex, word-bounded: a revert's "This reverts
commit …" too), a cross-repo ref (`owner/repo#N`, `repo#N`, `a/b/c#N`, any GitHub link into a repo; a bare
`#N` passes, though on the twin it links to the twin's own number) and a session id (a uuid, `session_<id>`). The owner wants a repo with a
public twin to meet these rules when the private commit is made, not at publish: `check-message`
is that scan on one message (a commit-msg hook's file too: git's `#` comment block is cut first), and `--range` on every commit of a curated branch, which wharf's
`/finish` runs before the push (S7); the replay still runs it. Without a word list on the Mac the
patterns run alone, said in one line. No base — a change merged on GitHub — squashes as before, and the PR body says so; `--squash`
asks for it. `check` prints the plan; its refusals there are printed, not counted, so a work
branch's checkpoints never turn a check line red.

**The log** (2026-10-21; the design's D2-A). A log that names what was redacted leaks, so it is
split. The PR body, public: each replayed subject, oldest first, in a fenced block (a `#N` or
`@name` in a subject neither links nor notifies there), under one line of counts — replayed,
folded, refused (a body dropped, a subject replaced by its reviewed line). Never a path with a
line, a word, a private sha or a fold's reason. The full report, private: indented under the PR's
row in `<git dir>/helloworld/PUBLISHED.md` — the private-to-public sha map (full shas; GitHub's
rebase merge rewrites the public ones, the trees stay), each fold with the commit that carries it
and why, every finding at `file:line`, each reviewed subject beside the one it replaced, the
exemptions' exact strings. Inside an agent's shell it is written masked, as it prints. Every clean
`check` ends on the backlog (the design's G3): `pending: N commit(s) not yet public (C would go up,
F fold into them)`, "publish soon" above 5, never in the exit code.

Publishing goes through a PR (the owner, 2026-10-09: "publishing through a PR is the right way, PRs
from myself can eventually auto-merge after checks, but we can keep it off for now"). Everything a PR
shows is public the moment it is pushed, drafts included, so `--pr` scans the PR's title (the
commit message), its body, its branch name, both commit identities and the gh login that opens it
with the files — against the whole word list, since a credit is consent for the published tree,
not for the tool's own words — and pushes nothing unless all of them pass. A login on the word list
that already authored a merged PR in a public repo of the target owner passes unscanned: it is
public already (`search is:pr is:merged is:public author:<login> org:<owner>`; a failed search
scans it), and the PR body says so. The commit is dated in
UTC, as `publish`'s. The branch carries no host (`claude/publish/…`, not
`claude/<host>/…`): machine names are on the word list. The push goes from a clone kept in the
private repo's git dir (`<git dir>/helloworld/public`; `<git dir>/opensource/` while only that
exists), with the wharf pre-push guard installed, so an agent's push from that
clone reaches `claude/*` only; the clone takes the commit through a ref of the gate's own that is
deleted again in the same run. Auto-merge is off by refusal: `--pr` stops when the public main or
the new tree holds a workflow whose name or content merges PRs, or a Mergify config, since either
would let a ready `claude/*` PR merge itself. A first publish has no `main` for a PR to merge
into: it stays `publish`.

## What the gate cannot see — and which human check covers it

The scan reads text, in the files it is given, at the moment it runs. These it cannot see:

| Blind spot | Why the gate misses it | The human check | When |
| --- | --- | --- | --- |
| **Video frames** — a face, a screen with a notification, a name tag, a house number, a plate | Footage never enters a public tree (a non-UTF-8 file is refused), but a film is published on a video site, outside the gate | A blur pass's contact sheets, read by the agent and once by the owner; the owner watches the final render end to end | Before every upload |
| **Audio** — a name said aloud, a call in the background, a recognisable song | Not text | The owner listens to the final mix at full length; music stand-ins get their own listen | Before every upload or release |
| **A name burned into an image or a caption** — a subtitle from a transcript, a screenshot, a card rendered from a sidecar | The words live in `$WORK` sidecars and in pixels, never in the public tree | Read the edition's `--srt` output start to end against the consent list; a binary image is refused by the gate as not UTF-8, and so is anything embedded as a `data:…;base64,` URI (an image, a sound, a PDF); an SVG is text, scanned as text, so its drawn shapes are not seen | Before every upload |
| **A person without a name** — "the neighbour upstairs", a role, a story told by what was cut | No pattern, no word | Read `helloworld check`'s diff before `publish --pr`: the push is the publish, so the merge is only a second look; the PR body lists added and changed files and counts removed ones | Before every `publish --pr`, again at the merge |
| **A name not yet on the word list** — a new person, account, machine or employer | The list is as current as its last edit; a third-party name passes unless the list has it | Add the word the day the name appears, before the next publish; the gate prints the list's date | Every publish |
| **Edits after the scan** — a PR body or title edited on GitHub, a comment, a contributor's own PR | The gate scanned only what it pushed | The owner's read of anything merged; contributors' credit PRs are reviewed by hand | Every merge |
| **`refs/pull/*`** — a PR's head ref, which GitHub keeps after the PR closes and its branch is deleted | Only branches and tags are fetched; the pull refs are not | The post-mortem's containment step (GitHub Support removes a cached view or a pull ref); read a PR's commits on GitHub before merging | Every merge |
| **A time zone in the history** — an offset that tells where a person is | Printed as a warning, never a finding (the owner's call) | Read the warnings in `check`'s output | Every publish |

**The gate signs its own commits since 2026-10-10**: `publish` and `publish --pr` end the commit's
message with `Signed-off-by: <author>`, the author identity `git var` reads, because the public
repo's DCO step (a public twin's `.github/workflows/public-check.yml`) refuses a commit without one; the
preview shows it, `--pr` scans it as commit metadata, and an unsigned proposal branch of the same
tree is replaced, not pointed at. The next run's history scan passes the address through
`.helloworld/identities`.

**The public history is covered since 2026-10-10** (the 220-film squash merge, whose author GitHub
set to the merging account's private address): `check`, `publish --pr` and `publish` read every
commit reachable from every branch and tag of the public repo, with the fetch they already make
(one ls-remote, one fetch of every public branch and tag, objects only). The objects are parsed raw,
not through a format string: the author and committer lines, the tagger of every annotated tag
(a tag of a tag is peeled one level at a time, by its `object` header) and of any `mergetag`
header, and the **whole message** of each commit and tag. Names and addresses go through the word
list and the address pattern; so does every ref name. A message is read for every address, so a
`Reviewed-by:`, an `Acked-by:`, a `Cc:`, an indented trailer or a private word in a subject is a
finding like a `Co-Authored-By:`. Replace refs are ignored (`GIT_NO_REPLACE_OBJECTS=1`).

**Which addresses may stand in the public history** is `.helloworld/identities`: one address per line
(`#` and blank lines skipped), read from the reviewed ref like the other lists, not published. Besides
those, GitHub's `noreply@github.com` (as committer, and in text) and its made-up addresses pass:
`<id>+<login>@users.noreply.github.com`, the older `<login>@users.noreply.github.com` and a bot's
`<id>+<name>[bot]@users.noreply.github.com`. Everything else is a finding
(`history <sha> author`, `history <sha> message:3`, `history ref <name>`) and fails the run, whoever
made the commit, GitHub included: merges, web edits, and the repository's own creation commit. A
person who consents to a credit is added to the file in the same change, so a credit PR does not
brick the gate. Without the file the gate falls back on the identity this machine's git would publish
as and prints `WARNING: identities from this machine's git config`; with the file, `publish` and
`publish --pr` refuse when git's own author or committer address is not in it, unless it is a person's
GitHub noreply address (`[<id>+]<login>@users.noreply.github.com`; a bot's still needs its line). So a fresh public repo
is created **without** GitHub's README or LICENSE initial commit (an empty repo; the first `publish` is
the first commit), or that commit is a finding. Such a commit can only go by a hard push, which is
the owner's and owes a post-mortem (below).

**Exit codes.** `check` exits 0 clean and 1 with findings. When the public repo cannot be reached it
exits 2 (a history that was not read is not a clean one), or 1 if the tree also has findings.
`publish` and `publish --pr` refuse (2) when the public repo cannot be reached.

**Time zones are a warning only** (the owner's call, 2026-10-10). Any author, committer or tagger offset other
than `+0000` prints `history <sha> <field>: time zone <offset> (warning)`; it is never a finding and
changes no exit code. GitHub writes the merging account's own offset into the committer of a merge it
makes, and the person's time zone is what it tells.

**The public repos merge by rebase only** (squash and merge commits off in each repo's settings,
2026-10-10). Probed fact: a GitHub *squash* commit is authored with the merging account's own
address (the incident, 220-film PR 1); a *rebase* merge keeps the commit's **author** but writes the
merging account's own address as **committer**, with the account's local offset (probed on a private
repo's PR: author the publishing identity, committer the account address, -0700). So rebase-only
keeps the author off the merging account, and what covers the committer and every other commit
GitHub makes is the account's GitHub setting "Keep my email addresses private" (the owner turns it on): GitHub then writes
`<id>+<login>@users.noreply.github.com`, which passes. `publish --pr` checks the setting before it
pushes: `gh api repos/<owner>/<name>` must say `allow_squash_merge` and `allow_merge_commit` are
false, and unreadable counts as on; the refusal names the fix, which a new public repo gets at
creation: `gh api -X PATCH repos/<owner>/<name> -F allow_squash_merge=false -F allow_merge_commit=false`.
That incident's post-mortem lives in its private source repo (resolved).

## Post-mortem: a public repo needed a hard push

Trigger: any force-push, history rewrite, or deletion (branch, tag, file, the repo itself) made on
a public repo to take something back (the owner, 2026-10-09: "Every issue that required a hard push
will get a post mortem and a mandate to fix the privacy gates"). The hard push itself is the owner's:
`main` is protected and every agent push stops at `claude/*`. Forks and clones keep what they
took; GitHub's own "Removing sensitive data from a repository" guide is the containment list,
read at the time.

1. **The post-mortem** — `docs/postmortem-<yyyy-mm-dd>-<topic>.md` in the **source** (private)
   repo, never in the public one. It never quotes what leaked: name the file, line and category.
   **Its first lines carry `Status: open — <what remains, who owes it>`** (2026-10-10). When every
   item is done and verified the line becomes `Status: resolved <yyyy-mm-dd> — <how verified>` and
   the file is `git mv`'d to `docs/record/` in the same commit: that is the archive. Sections:
   - *What went public* — file, category, the commit, how long it was up, what GitHub shows of
     views, forks and clones for that window.
   - *How it passed* — which layer let it through: the allowlist, a pattern, the word list, an
     exemption, the PR's own text, or a blind spot in the table above.
   - *The hard push* — what was rewritten or deleted, by whom, when, and the read-back
     (`git ls-remote`, the GitHub page) that shows it gone.
   - *The gate fix* — the test case's name, its FAIL line from a run before the fix, its `ok`
     line after, the commit. For a blind spot: the row above that changed, and its new check.
2. **A failing-then-passing case** in `tests/helloworld.sh`: plant a stand-in of the same
   shape (never the leaked string: this repo may be published one day; a private word goes in
   the test's scratch word list, the real one stays outside every repo), run the test against the
   gate as it was and keep the FAIL line, fix `bin/helloworld` or the repo's lists, run it green.
   Both outputs go in the post-mortem.
3. **Launch both**: the gate fix in this module, the post-mortem through the source repo's own
   launch; then tell every live session the one-line lesson.

## Not verified

- The PR mode was ported onto the masking scan on 2026-10-09, so `--pr`'s findings print two
  letters of each private word in an agent's shell.
- The tests use local bare repos, `insteadOf` and a fake `gh`; GitHub itself is covered only by
  real runs (220-film's PR 6, 2026-10-11, went through `publish --pr`), not by the suite.
- Which account pushes the branch: the push uses git's own credential (an SSH key or a credential
  helper), not gh's, and GitHub shows that account in the repo's activity. The gate scans the gh
  login, not the pusher; on a Mac where the two differ, the pusher goes unscanned (review
  2026-10-09, from source; not probed).
- A leak spotted in a PR after the push: GitHub keeps `refs/pull/N/head` after the PR is closed
  and its branch deleted, so the post-mortem's containment step may need GitHub Support
  (recollection, not probed).
- A credited name in the commit identity refuses `--pr` while `publish` passes it: the PR's own
  text is scanned against the whole word list. Deliberate; if the owner's own name ends up on the
  word list, the identity needs another spelling or the terminal route.
- `gh pr create --repo … --body-file …`: `--base`, `--head` and `--title` are exercised for real
  elsewhere; `--repo` and `--body-file` are from gh's usage as recalled, not probed here.
- The `.opensource/` and `<git dir>/opensource/` fallbacks are tested on scratch repos only; the
  twins that still carry the old names move when next touched.
