# Changelog — helloworld

## 0.1.0 — 2026-10-18

- First cut, moved in from the overlay's `bin/opensource`, `bin/name-check` and `/name`, renamed:
  the tool is `helloworld` (verbs unchanged); a repo opts in with `.helloworld/` (`.opensource/`
  still read, with a note); the word list is `$HELLOWORLD_WORDLIST` (`$OPENSOURCE_WORDLIST` still
  honoured), else the config dir's `helloworld/wordlist.txt`, else the old default; the git dir's
  `helloworld/` (`opensource/` read while only it exists); `publish --pr`'s pre-push guard comes
  from the wharf module through the core, and without it `--pr` refuses.
