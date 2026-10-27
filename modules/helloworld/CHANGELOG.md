# Changelog — helloworld

## Unreleased

- git's stdin goes through a temporary file, never a pipe: a `cat-file --batch` fed the gate's
  object ids hung for hours on macOS 12 (git 2.37, Python 3.9). A temp dir that will not take the
  file is a refusal (exit 2).
- The replay judges every commit's tree with the reviewed ref's exemptions, and with that commit's
  own allowlist and credits: an exemption is text that goes public with the ref anyway, in the one
  file it names, so commits made before it was exempted no longer fold into the exemption's. A
  string the ref does not exempt, or exempts in another file, folds as before; an exemption an
  older commit had and the ref took back clears nothing.
- The log (S3, the design's D2-A): `publish --pr`'s PR body lists each replayed subject, oldest
  first and fenced, with the counts replayed, folded and refused (bodies dropped, subjects
  replaced by a reviewed line). The full report — the private-to-public sha map, each fold and
  why, every finding at file:line, each replaced subject, the exemptions' strings — goes indented
  under the PR's row in `<git dir>/helloworld/PUBLISHED.md`, also when the push went up but no PR
  opened or the read-back disagreed; in an agent's shell its text is masked as it prints, its shas
  never. `check` prints `pending: N commit(s) not yet public`, "publish soon" above 5 (G3).
- `publish --pr` replays (the design's D1-B): every private commit since the one whose allowlisted
  tree is the public main's goes up as its own public commit — its tree, its subject and body less
  the agent trailers and any Signed-off-by (by key), the publishing identity, its own dates at
  UTC — each scanned; `wip:` checkpoints, commits whose tree fails and commits whose lists hold an
  entry the reviewed ref took back fold into the next that passes, a failing body is dropped, a failing subject refuses until `.helloworld/messages` holds
  its reviewed line. No base squashes as before, said in the PR body; `--squash` asks for it.
  `check` prints the dry replay without counting its refusals.
- A replayed message meets its own patterns beside the word list (the owner's answer to D2 of the
  S2 digest, 2026-10-20): a sha-like token, a cross-repo ref (`owner/repo#N`, `repo#N`, `a/b/c#N`, any
  GitHub link into a repo) and a session id (a uuid, `session_<id>`) drop a body and refuse a
  subject; `publish --pr` scans its title and `--note` for them too. `Deployed:` and `Stood-By:`
  lines are dropped with the agent trailers. New verb `check-message --subject S
  [--body-file F]` / `--message-file F`: the same scan on one message, for the private commit's
  making; exit 1 on a finding, 2 for a file it cannot read; a `--message-file` loses git's `#`
  comment block first.
- `publish --pr` points at an open replay branch instead of pushing only when that branch's trees
  are the ones this run would push, each scanned with today's lists.
- `check-message --range A..B [--repo R]` (S7, publishable at the source): every commit of the
  range (`A..B`, a bare rev refused) meets that scan, each finding under its commit; skipped as the
  replay skips them: checkpoints, and commits whose published files equal their first parent's. A
  repo without `.helloworld/` at HEAD has nothing to scan and its word list is not read; a repo git
  cannot read exits 2. wharf's `/finish` runs it on the curated branch
  before the push, in any repo with a public twin. A Mac without the word list scans the patterns
  alone, says so in one line and in its last; a variable naming a missing list, or a default
  path or helloworld folder that is a broken link, still refuses.

## 0.1.0 — 2026-10-18

- First cut, moved in from the overlay's `bin/opensource`, `bin/name-check` and `/name`, renamed:
  the tool is `helloworld` (verbs unchanged); a repo opts in with `.helloworld/` (`.opensource/`
  still read, with a note); the word list is `$HELLOWORLD_WORDLIST` (`$OPENSOURCE_WORDLIST` still
  honoured), else the config dir's `helloworld/wordlist.txt`, else the old default; the git dir's
  `helloworld/` (`opensource/` read while only it exists); `publish --pr`'s pre-push guard comes
  from the wharf module through the core, and without it `--pr` refuses.
