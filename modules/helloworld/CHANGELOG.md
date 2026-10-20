# Changelog — helloworld

## Unreleased

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

## 0.1.0 — 2026-10-18

- First cut, moved in from the overlay's `bin/opensource`, `bin/name-check` and `/name`, renamed:
  the tool is `helloworld` (verbs unchanged); a repo opts in with `.helloworld/` (`.opensource/`
  still read, with a note); the word list is `$HELLOWORLD_WORDLIST` (`$OPENSOURCE_WORDLIST` still
  honoured), else the config dir's `helloworld/wordlist.txt`, else the old default; the git dir's
  `helloworld/` (`opensource/` read while only it exists); `publish --pr`'s pre-push guard comes
  from the wharf module through the core, and without it `--pr` refuses.
