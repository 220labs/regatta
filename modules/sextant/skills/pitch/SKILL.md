---
name: pitch
description: Render one Markdown document — a proposal, a strategy, a captain review — for the people it is for, from that one text: the captain page, read alone, generated from the document (`pitch memo`), and the admiral deck, spoken over, built from the deck fence at the document's end (`pitch build`); both held to the document by `pitch check` and published as private Artifacts, the page first, their links kept in a sidecar. Use for "make a memo of this", "turn this into a deck", "pitch this to <reader>", or when a document changed and its renders must follow.
argument-hint: <document.md> [captain|admiral|all]
effort: high
allowed-tools: Bash(pitch:*), Bash(*sextant/*bin/pitch *)
---

Pitch it: $ARGUMENTS

If this project has its own `/pitch` (`.claude/skills/pitch` or `.claude/commands/pitch.md`), run
that instead and stop here: the project's version wins.

The tool is `pitch`: on the Bash PATH while the sextant plugin is enabled; where this skill is
linked in by hand, `../../bin/pitch` from this skill's base directory. The method behind every rule
is [method.md](method.md), beside this file; every key of the project's `pitch.json` is in
[config.md](config.md). The renders reach a reader through the Artifact tool; this skill writes no
PPTX or PDF of its own.

**The one rule: one document, several renders, no prose typed twice.** The document is the truth;
the renders are views of it. A correction goes into the document first, then every render is
generated again in the same change, then `pitch check`. Never edit a render: the page is written by
`pitch memo` and the slides by `pitch build`, and `pitch check` refuses a render that differs from
what they write.

The argument after the document picks the renders: `captain` the page, `admiral` the deck, `all`
both (the default).

## 1. The document first

- Read the document whole, and the project's `AGENTS.md` / `CLAUDE.md` for a rule about its
  readers. Name the reader in one line: who, what they decide, what they already know.
- The reader's test, sentence by sentence: could this reader repeat it to their own boss or
  investor? Plain words, a concrete thing at the end of each item, every number kept. Jargon a reader
  would have to look up is rewritten in the document, not softened in a render.
- The first thing the reader meets answers their question. If the document opens with background,
  move the answer up in the document; the renders follow its order.
- **Fact-check it before any render.** Spawn the project's strictest reviewer (`reviewer-high`, else
  `reviewer`, else a fresh agent told to verify and never to edit) on the document alone: every number
  against where it came from, every claim about a product, a person or a date against its ground
  truth. Fix the document from its findings. Every render inherits the document's errors, so this is
  the one fact-check.

## 2. Which render, for which occasion

| The occasion | The render | What the reader gets |
| --- | --- | --- |
| a reader alone, with time: sent, linked, handed over | **captain**: the page, read in full | the whole document, its tables and its figures |
| a room, someone speaking | **admiral**: the deck, about twenty words a slide | the deck on the screen and the captain page in every hand |

The admiral deck is never sent alone: without its speaker it says too little, and the page is what
makes it honest (method.md, section 1). When a reader asks for "the deck" to read by themselves, send
the captain page.

## 3. The brand

The renders take their look from the project's `pitch.json`, never from a page typed by hand: the
deck's colours from `layout` and `palette`, its face from `face`; the page's light colours from
`layout`, its dark ones from `memo.dark`. Where they come from, the first that exists:

1. a Design System artifact named in `publish.design_system`: read its README and tokens, and put
   them into `pitch.json`;
2. the brand doc in `publish.brand`, else the newest `docs/brand-<date>.md`: the tokens read from
   the project's live site (ink, paper, accent, muted, light and dark), the faces, the wordmark;
3. neither: say so in one line and ask whether to read the live site into a `docs/brand-<date>.md`
   first (an unattended run writes it and says so). Never invent a brand for a client.

A new face is measured once, by hand, with Chrome: `pitch calibrate glyphs`, then `pitch calibrate
render` on the deck (method.md, section 5, "The calibrator").

## 4. Build the renders, never type them

- **The captain page:** `pitch memo <document.md>` writes `<stem>-memo.html` beside the document. A
  block it cannot place (raw HTML, an image, a diagram, indented code) is listed by line and nothing
  is written: rewrite that block in the document. A page someone wrote by hand is overwritten only
  with `--replace`, once its words are all in the document.
- **The admiral deck:** its words go into one ```` ```deck ```` fence at the document's end, a JSON
  list with one object per slide (`id`, `headline` stating the message, at most three `statements`,
  the `note` the speaker says, optionally a `graphic`); the builder's comment in `bin/pitchlib.py`
  gives every key. `pitch build <document.md>` writes the slides, and on its first run the deck
  folder and a `deck.json`; it refuses the whole deck, nothing written, when one slide breaks a rule,
  and says which. Fix the fence, never a slide file. Every number a slide or its note shows must be
  in the document's body: the fence itself does not count.
- **The pins:** the claims that were wrong once and must never drift go into `pitch.json`'s
  `claims.must_appear` (the document and the page) and `claims.admiral_must_appear` (the document and
  the deck), keyed by the document's stem.
- `pitch check <document.md>` green before anything is published, every time.

## 5. Publish, the page first

1. **Read the sidecar first**: `<stem>.pitch.json` beside the document (config.md, section 12). An
   artifact is keyed by the file it was published from, so a render published again from another
   working copy becomes a second artifact, and the link the reader has stops updating. Where the
   sidecar records a render's URL, publish to that URL.
2. **The captain page**: the Artifact tool, `file_path` the page; the first time with an `icon` and a
   one-sentence `description`. Record `published.memo`: its `url`, `first_published` (today) and
   `file`.
3. **The admiral deck**: the Slides artifact type. Find it with `Artifact` `list` `scope: "types"`
   (never a remembered link), create the deck once from its `type_url` with the document's title, and
   follow the type's own instructions to publish the deck's files (`project/deck.json` and
   `project/slides/<id>.html`, from the deck folder). Record `published.admiral_deck`: `url`,
   `first_published`, `type_url`, `folder`.
4. **Assets** (the wordmark, an image): uploaded once with the Artifact tool's `asset: true` and
   referenced exactly as the upload returned it; recorded in `assets` as `{"<file>": "<url>"}`.
5. `pitch check <document.md>` again (it holds the sidecar's shape, and refuses one naming a render
   that is gone), then commit the document, its renders and its sidecar together.

## 6. Images

Only where one carries meaning: a cover, a section opener, a product in use. A deck with no images
and good structure is a fine deliverable. `publish.images` picks the route:

| `images` | How |
| --- | --- |
| `none` (default) | the wordmark and drawn figures only |
| `design` | the Design artifact type, for vector covers and openers; no model, no licence question |
| `agy` | an image-generating command-line agent on the project's own login, asked for the file, which comes back to disk |
| `flow` | an image model in a browser on the project's login, a person present |
| `imagen` | an image API on the project's billing account: real money, per image |

Whatever the route: the file is uploaded as an asset, its route and prompt are recorded in the
sidecar's `images`, and a generated image is never presented as a photograph of something real. A
route that is not set up says so in one line; the render goes on without the image.

## 7. Hand over, and keep it held

- `pitch renders <document.md> --links` prints the links as one line; it exits 1 when a render has
  no URL yet. Say once beside them: "private until shared from the page's Share menu; the deck
  downloads as PPTX or PDF from its page". Name what was not verified: a layout at phone width you did
  not look at, an image route that was skipped.
- Wire the check where the project's own check runs: `pitch check <docs-root>` (a project whose check
  is pytest: config.md, section 13).
- When the document changes later: correct the document, `pitch memo`, the fence, `pitch build`,
  `pitch check`, publish again to the sidecar's URLs, one commit.
