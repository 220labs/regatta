---
name: flare
description: Fire a flare to Regatta's makers — a bug report, an idea or a question about Regatta itself, filed as an issue on its public repo with the evidence attached, and the issue link handed back as the receipt. Use when the user asks to report a Regatta bug, suggest a feature or send feedback about Regatta. Feedback on a published document goes to its comments instead, and a bug in Claude Code itself to Claude Code's own /bug.
effort: medium
argument-hint: <what went wrong, or the idea>
---

Fire a flare about: $ARGUMENTS

The tool is `../../libexec/flare` from this skill's base directory; run it as
`python3 <base directory>/../../libexec/flare …`, one path, never through `cd`. `--help` lists every
flag. It files a GitHub issue on Regatta's public repo (`regatta/flare-repo` in the config dir names
another), with the modules' versions, Claude Code's and the OS added for you.

**The issue is public.** Anyone can read it, so nothing goes up without the user seeing it first:
your question in step 4, answered yes in the user's own words, is the gate, whatever the permission
mode. The tool scans the whole text for private words, home and machine paths, addresses and
credential shapes before it sends, and under `CLAUDE_UNATTENDED` it sends nothing: an unattended
run dry-runs and leaves the report for a person.

1. **Write the message short and human**: what was run, what was expected, what happened instead,
   and the steps that reproduce it. The first line is the title; keep it under 80 characters and
   make it the finding ("keel line prints nothing for a doc without D-items"), not a label ("keel
   bug"). Pick `--category bug` (the default), `idea` or `question`, and `--tag <module>` for each
   module involved.
2. **Attach the evidence, verbatim.** Write one text file in a temporary folder and pass `--attach
   <file>`: the failing command and its full output, the exact error, the tail of this session's
   exchanges that led here. Paraphrase nothing in it; the message is for that. Name it for what it
   is (`session-tail.md`, `check-output.log`). Before writing it, cut credentials, tokens, the user's
   environment and secrets files, and any conversation that is not about the problem, and replace
   each private path with a placeholder (`<repo>/modules/keel/bin/keel`, not the home folder).
3. **Make one `--client-id`** for this report (8-80 letters, digits, `_` or `-`, e.g.
   `keel-line-empty-001`) and reuse it on every retry: a retry after an uncertain answer returns the
   first receipt, never a second issue.
4. **Dry run, then show it.** `flare --dry-run "<message>" --client-id <id> [--category …] [--tag …]
   [--attach <file>]` prints the issue as it would be filed. Exit 3 means the scan found something
   it prints: rewrite or cut exactly that, and dry-run again. Shas, ids and issue links pass; a
   line on stderr saying the text was not scanned (no helloworld) is said to the user too. Show the user the title and body, the
   attachment's size, and the repo, and ask whether to send.
5. **Send on the user's yes**, the same arguments without `--dry-run`, plus `--json`. Report
   success only on a receipt with `"created": true` and the issue `url`, and give the user that
   link. `"created": false` is a report already filed under this id: give its link and say so.
   `"created": null` means `gh` is missing or signed out: hand the user the `url` to open and
   submit, and the `attachment` file to paste into it (or `gh auth login`, then send again).
   Exit 2 is a failed send or a usage error: say what it printed, and retry once with the same id;
   the retry finds the issue if the first send filed it after all.
