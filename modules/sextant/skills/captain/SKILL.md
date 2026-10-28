---
name: captain
description: Write a captain review — one document for the person who decides (a founder, an owner, a client's executive), in plain words, with the options, what each gets them, costs them and needs from them, the best three and a D-list — then render it for them with /pitch, the page and the deck from that one text. Use for "a captain review of <topic>", "an executive review for <client>", "brief the founders on <topic>", or "turn this into something they can decide from".
argument-hint: <topic | document.md> [--for <reader>]
effort: high
allowed-tools: Bash(pitch:*), Bash(*sextant/*bin/pitch *)
---

Captain review: $ARGUMENTS

If this project has its own `/captain` (`.claude/skills/captain` or `.claude/commands/captain.md`),
run that instead and stop here: the project's version wins.

A **captain review** is a document for the person who decides: the captain, in Regatta's words;
"executive review" in a client's. It is written first, in the template beside this file
([TEMPLATE.md](TEMPLATE.md)), and only then rendered, by `/pitch`, as the captain page and the
admiral deck. The tool is `pitch` (on the Bash PATH while the sextant plugin is enabled; else
`../../bin/pitch` from this skill's base directory): `pitch review <document.md>` holds the document
to the template before any render exists, and `pitch check` holds the same rules once there are
renders.

**The writing rule.** Every term is replaced by ordinary words or explained in the same sentence. The
test for a line: could the captain repeat it to their own investor? That is a judgement, not a lint:
`pitch review` holds the shape, never the words; the fact-check pass and you hold the words.

## 1. The document

- **A topic:** spawn the `architect` agent to write the document in the template: one file, in the
  project's `proposals/` if it has one, else `docs/`, named `<topic-slug>-<yyyy-mm-dd>.md`. Tell it:
  the reader (`--for`, else the project's owner as its `AGENTS.md` names them), the topic, "a captain
  review: the template at <this skill's base>/TEMPLATE.md, its headings word for word, the title
  ending `(captain review, <date>)`", the writing rule above, and that every number carries where it
  came from. Where the reader is a client's (`--for` names someone outside the project's own team),
  the title's kind is `executive review`: that is the name on the deck's cover.
- **A document:** read it as it is. If it is not yet in the template's shape, rewrite it into the
  template in place, keeping every number and every claim; say so in one line.
- `pitch review <document.md>` until clean.

## 2. The fact-check

Spawn `reviewer-high` (else `reviewer`) on the document alone, told to verify and never to edit:
every number against where it came from, every claim about a product, a person or a date against its
ground truth, and one pass for the writing rule (a term the captain would have to look up). Apply the
fixes to the document, then `pitch review` again. Every render inherits the document's errors, so
this is the only fact-check.

## 3. The renders

Run `/pitch <document.md> all`. Its deck fence follows the review's sections: the answer on the
cover, where things stand, the options (one slide each when they fit the deck's twelve), the best
three, and the decisions as the last slide ("what we need from you"); the speaker notes carry the
rest. If the project has its own test of the renders, run it.

## 4. The hand-over

- Commit the document, the renders and the sidecar together.
- Hand the document over the way the project hands over documents to answer (where it uses keel,
  `keel line <document.md>`), and beside it the line `pitch renders <document.md> --links` prints.
  Once: "the page and the deck are private until shared from their Share menu".
- When the captain answers, a pick that changes the text (an option dropped, a number corrected) goes
  into the document first; then `/pitch` renders it again, to the same links, and `pitch check`.
