# Two renders of one document: the captain and the admiral

*A method for turning one source document into two renders that are held to it by checks: a
dense page that is read (the captain render) and a sparse deck that is spoken over (the admiral
render). Everything here was built and enforced for one project's decks first, and is written up
without their content. sextant's `pitch` implements every check named below (`bin/pitch`, its library
`bin/pitchlib.py`); [config.md](config.md), beside this file, lists what a project sets in its
`pitch.json`.*

Sections: 1 why two renders · 2 the admiral render · 3 the captain render · 4 rules for every folder
deck · 5 the checks, by rule id · 6 traps · 7 the Slides runtime · 8 sources · 9 not verified.

---

## 1. Why two renders

A document to be studied and a talk to be listened to are different genres: "readers are not
listeners" (Norman). The authorities that seem to disagree are answering different questions.
Khosla, Kawasaki, Alley, Duarte and Doumont write about the spoken slide, and all of them push it
towards one message and few words. Tufte writes about the document, and his remedy for a talk is
not a better slide but a paper handout that everyone holds. Amazon's six-page memos, read in
silence at the start of a meeting, make the same move.

So the method keeps both and holds each to its own rules:

- **The admiral render is spoken**: about twenty words a slide, three statements, large type, a
  title that states the message, the detail in speaker notes. It is for the room.
- **The captain render is read**: the full document as a page, with its tables and figures, dense
  on purpose. It is handed to everyone in the room, and it is what gets sent when the deck would
  travel without its speaker. The admiral deck is only honest because the captain page exists.

A deck sent on its own to be read is a third genre. DocSend's figures put typical sent decks near
50 words a slide, and Doumont warns that slides do not double as a document sent by e-mail. The
method answers it by sending the captain page and never the admiral deck.

**The one rule over both: one source text, several renders, no prose typed twice.** The document
is the truth and the renders are views of it. A correction goes into the document first, then into
every render in the same change, then the check. The commonest failure (section 6, trap 1) is a
document corrected while its render is left behind.

## 2. The admiral render: rules, numbers, sources

| Rule | Value | Where it comes from |
| --- | --- | --- |
| Words on screen per slide | **25** hard cap; about **20** the target | Khosla's undated SlideShare deck says "no more than 25"; his dated 2019 deck says fewer than 50; Eric Paley, quoted inside it, says about 15. Twenty is Khosla's five-second rule ("flash slide for 5 secs; test takeaway?") at the measured adult silent-reading speed of about 238 words a minute (Brysbaert 2019). Doumont rejects word counts as arbitrary, so the cap is a house rule, held beside his visual limit |
| Statements per slide | at most **3** | the reader the method was first built for asked for three; one message per slide (Khosla, Doumont) is stricter still |
| Lines per statement and per title | at most **2** | Doumont's visual limit (2005, p. 69): at a large enough size, no item longer than two lines |
| Smallest type | **60 px** on a 1080 px canvas, i.e. 30 pt equivalent | Kawasaki's 10/20/30 rule: 30 pt minimum. Above every room rule found: a fiftieth of screen height is 22 px (the 8H rule); one secondary source's 24 pt is 48 px. The Slides runtime's own floor is 24 px and nothing checks it |
| Contrast | text **4.5:1**, or **3:1** from **44 px**; a painted mark **3:1** against what it sits on | the Slides type's own thresholds; WCAG 2.1 SC 1.4.3 (text) and SC 1.4.11 (non-text). The Slides type calls text "large" from 44 px, stricter than WCAG's 24 px |
| Colours | only the configured palette, in hex | membership keeps faint greys out; contrast catches two allowed colours that pair badly |
| The column fits the canvas | within **824 px** of vertical room (1080 minus two 128 px margins), estimated before writing | the runtime does not overflow, it shrinks an over-full box's text to as little as 60% of its size, so a 68 px statement can render near 41 px, under the floor, with nothing visibly wrong |
| Slide count | about 10, at most **12** | Kawasaki's ten slides for twenty minutes, with slack |
| Titles | the message as a short sentence with a verb, never a topic | Khosla (2019 deck, p. 68), Alley's assertion-evidence method, Doumont (p. 68–69: "a short sentence (thus including a verb)") |
| Where the title sits | at the top margin on every content slide; the cover and the closing line, which are statements, centred | the runtime's layout guide. A first build centred every column and its titles moved visibly between neighbours |
| No line ends on an article or a short preposition | "a", "an", "the", "of", "to", "in", "on", "at", "by", "for", "and", "or", "with" | "…for a / small fee" reads as a stumble; join with a no-break space |
| Graphics | only where a number is the message, drawn as painted shapes with no text, so the statement count still holds | the best slides in Garner and Alley 2013 carried a graphic every time (100% against 64%); in 105 medical-education lectures the share of slides with images predicted the rating where text density did not (p = 0.015 against 0.815); decoration costs recall (Rey 2012, g = −0.27 to −0.95) and Mayer's coherence principle (d = 0.86). Built, not tested: no check can tell evidence from decoration |
| A number that must be remembered | on the slide, not only in the notes | Garner et al. 2011: figures printed only on the denser slide set were recalled by **69%** of those who saw them against **39%** of those who only heard them. Judgement, not tested |
| Everything else | speaker notes (`<aside>`, at most 4,000 characters), which anyone who opens the deck can read, so they are published text | Khosla's appendix rule; the runtime |
| Every number on a slide or in its note | appears in the source document | a twenty-word slide is where an invented figure hides best, with no sentence around it to contradict it |
| Page numbers, footer captions, running headers | none | that first reader, explicitly; resolved over the Slides type's own pinned footer row (section 7) |

The evidence behind the format, briefly. Alley's assertion-evidence slides (a claim as the
headline, visual evidence beneath, no bullets) are the only format here with experiments behind
it. In Garner and Alley 2013 (110 students, same narration) they averaged 21.2 words against 41.5
and scored 9.39 against 6.73 out of 15 on an essay (d = 0.81), with fewer misconceptions
(d = 0.47) and a delayed-test effect of d = 0.89 ten days later. Immediate recall of facts did not
differ: the gain is on inference. The conditions differ in words, graphics and headline form at
once, so this is not a clean measurement of words per slide. Mayer's redundancy principle (do not
show on-screen text identical to the narration, d = 0.86) was measured with recorded narration and
weakens for experienced learners. Garner et al. 2011 cuts the other way, and is why the numbers
that must land stay on screen.

## 3. The captain render: rules

- It keeps its tables, its figures and its density: a document being studied is the genre Tufte is
  right about.
- **No type below 16 px**, including sizes written in `clamp()` (the first argument is the floor);
  a size in `em` or `rem` is refused, since it rests on a body size the check cannot see.
- It loads scripts and styles only from the artifact runtime's allowlist (by default
  `cdnjs.cloudflare.com`, `fonts.googleapis.com`, `fonts.gstatic.com`) and calls no network API.
  Links a reader follows (`<a href>`) are fine.
- No footer caption, and no caption whose only content is provenance.
- It carries every phrase pinned for its document (section 5, `claims.must-appear`).
- It is handed out with the talk, not only linked.

A captain render may also be an older single-file deck (`<stem>-deck.html`), whose slides are
JavaScript template literals. It is held to the 16 px floor, to "fetches nothing", and to no
authoring marker reaching the reader (section 6, trap 2).

## 4. Rules for every folder deck, admiral or not

- **No page number**: an element positioned absolutely or set below 40 px whose text reads as one
  (`11`, `11.`, `11 / 14`, `11 of 14`, `p 11`, `page 11`).
- **No running caption**: a short line (up to 120 characters) of small or corner-anchored text
  standing on three or more slides of one deck. The rule is structural, not keyed to a brand word.
  A title slide's own line stands once and is content.
- A well-formed index: `deck.json` at version 4 with a non-empty `order` that equals the slide
  files, every section starting at a slide that exists, one `<section id="<file stem>">` per file.
- Nothing reaches outside the deck: no `scheme://`, no protocol-relative `//host`, no `data:` body,
  no network API, no `<script>`. The one exception is a face: a Google Fonts css2 `href`, or a
  `src` to an uploaded asset (`/_blob/…`) or an installed file (`project/ds/…`).

## 5. The checks, by rule id

`pitch check <root>` runs all of them (`pitch check <document.md>` one document and its renders;
`--json` for a machine), exit 1 on a finding and 2 when it could not run. sextant's suite,
`tests/pitch.sh`, holds every rule to a root built to fail it: its `make_failing.py` writes one per
rule id at run time, and the suite fails when a rule id has none. A project whose check is pytest
runs the same check through the template in [config.md](config.md), section 13.

| Rule id | What it refuses |
| --- | --- |
| `admiral.words` | more than `max_words` words on screen (notes excluded; a no-break space still separates two words) |
| `admiral.statements` | more than `max_statements` text blocks besides the title (`p`, `li`, `h3`, `blockquote`, summed) |
| `admiral.markup` | anything outside the per-tag grammar the estimate models (below) |
| `admiral.runtime-limits` | a note over 4,000 characters; more than 200 elements |
| `admiral.type-floor` | a block that renders under `min_font_px`, including an unstyled `<p>` at the runtime's 32 px default; a size in any unit but px |
| `admiral.palette` | a hex colour outside the palette; a colour named by word or function |
| `admiral.contrast` | text or a painted mark below its WCAG ratio against what is behind it |
| `admiral.fit.overfull` | an estimated column taller than the room (824 px by default) |
| `admiral.fit.lines` | a title or statement running to more than `max_lines` lines |
| `admiral.fit.dangling` | a line ending on one of the dangling words |
| `admiral.fit.width` | a declared width wider than its column; a word wider than its box |
| `admiral.title` | a title that names a topic instead of stating a message (heuristic, below), unless exempted with a reason |
| `admiral.slide-count` | more than `max_slides` slides |
| `admiral.invented-number` | a number on a slide or in its note that the document does not contain, magnitude included (`$250M` does not match `$250K`) |
| `admiral.exemption-stale` | a title exemption naming a slide that no longer exists, or one without a reason |
| `deck.index` | `deck.json` out of step with the slide files, or a slide file without exactly one matching `<section>` |
| `deck.generator-drift` | slide files that differ from what the builder writes from the content file (a hand edit the next build would revert), or no content file |
| `deck.page-number` | a page number on any folder-deck slide |
| `deck.running-caption` | a caption repeating on three or more slides |
| `deck.external` | a slide reaching outside the deck; a face loading from anywhere but Google Fonts or an asset |
| `captain.type-floor` | type under 16 px in a memo or single-file deck |
| `captain.allowlist` | a memo loading from outside the allowlist, or calling a network API |
| `single.external` | a single-file deck with any absolute or protocol-relative URL or network API |
| `single.authoring-marker` | a `//` comment inside a slide template or data string; an HTML comment inside a data string; a script the scan cannot pair |
| `claims.must-appear` | a pinned phrase missing from the document or from one of its renders |
| `claims.retired` | a retired claim reappearing in any Markdown or HTML file under the root |
| `claims.table` | a render whose document has no pinned phrases (when `require_pins`), or a pin entry whose renders are gone |
| `root.orphan` | an HTML file or a deck folder that no document pairs with, so nothing checks it |
| `root.vacuous` | a root where no document has any render, so every check would pass by finding nothing |
| `sidecar.shape` | a sidecar (`<stem>.pitch.json`) that is not the shape [config.md](config.md) section 12 gives, or one beside no document |

**The markup grammar.** Every check after markup reads the slide through the layout estimate, so a
slide may use only what the estimate models, per tag. A `<section>` holds one title, body `div`s
and one `<aside>`, last. A title (`h1`, `h2`) or a statement (`p`) holds text only, sizes its own
type in px, and may set a width, a colour, a weight, a line-height of 1 or more, and a
letter-spacing between −8 and 0 px. A `div` holding text is layout only (flex, direction, gap,
alignment). A `div` holding no text is a mark and alone may be painted, sized, bordered or rounded.
Lengths are px and never negative. Two reviews got about two dozen slides past a single global list
of allowed properties: a sized `<b>`, a nested `<p>`, a duplicate `style` attribute, an
`!important`, a negative gap, a gradient, a grid, `font:` shorthand, letter-spacing of −40 px,
line-height 0. Each is now a control the suite must refuse (the controls group in sextant's
`tests/pitch_cases.py`).

**The title heuristic.** Telling a clause from a label exactly needs a parser, so this is a
heuristic and says so. It fails the two shapes a topic title takes: a noun phrase with no verb
("The budget", "Test results", "Known risks") and a wh-label ("Where things stand", "What members get"). A
title passes when it holds an auxiliary, or a verb from a written lexicon in a position where a
verb can stand. A true statement whose verb is missing fails loudly with a message saying so, and
the verb is added (`extra_verbs`).

**The fit estimate.** Every text block is wrapped greedily at spaces, using advance widths
measured from the deck's own face in Chrome (canvas `measureText` at 1000 px, in thousandths of an
em). Summed widths ignore kerning: against Chrome's kerned widths for 400 strings they ran from
0.46% narrow to 1.49% wide, so the estimate wraps in a box 0.5% narrower than the real one. On 300
random lines (60 to 150 px, weights 400 to 800, letter-spacing 0 to −5 px), 248 of the 273 without
an over-long word broke exactly as Chrome did, and none came out with fewer lines. On the first
project's deck the estimate and Chrome agreed to the pixel on every slide, and so they did on the
suite's own five-slide deck once its face was measured (`pitch calibrate render`, 2026-10-27). A face
that has not been measured falls back to the Slides type's 0.6 em a character, which over-wraps
(safe, never the reverse): on that same deck it predicts a second line Chrome does not set on 2 of 5
slides.

**The builder.** `pitch build <deck>` writes the slides from a content file (`slides.json`),
checks every slide in memory, and writes nothing unless all pass. Its `--check` mode compares the
files on disk with what it would write; `deck.generator-drift` runs it.

**The calibrator.** `pitch calibrate glyphs` measures the face into the table `face.glyphs` names;
`pitch calibrate render` lays every admiral slide out in headless Chrome and compares line counts and
column height with the estimate (`--shots` writes a PNG per slide). It needs Chrome and the network,
so it is not part of the check; run it by hand once per face, and again when the face changes.

## 6. Traps

Each was paid for at least once. The first eleven are from the first project's own trap list,
rewritten without its content; the rest are from the code and from generalising it.

1. **A document corrected without its render.** Twice a document was fixed and its deck left
   behind, so the deck asked for things the corrected document had withdrawn, the second time after
   a test suite was added to prevent exactly that. Cause: the deck duplicated the document's prose
   instead of being generated from it, and the suite compared a short list of phrases, not the
   corrected state. Check: after any edit to a document's decisions or numbers, search every render
   for the same claim before committing; treat the pinned phrases as a floor, never as coverage.
2. **A `//` comment inside a JavaScript template literal renders as slide text.** In a single-file
   deck the slides are template literals, where `//` is content. Use `<!-- … -->` inside a template;
   `//` belongs only in code outside one. In a data string an HTML comment prints verbatim too.
3. **An absolute link passes a local link check and breaks for everyone else.** A check that
   resolves `/Users/…` against the local disk is green on the machine that wrote it. Links in a
   document and its renders are relative; a pointer outside the repo is named, not linked.
4. **A guard can pin a claim that has since been retired.** A pinned phrase once forced both files
   to keep asserting a date the decision had removed, so fixing the content meant editing a test,
   which reads as weakening a check. When a decision retires a claim, retire its guard in the same
   commit and say so in the message.
5. **Publishing a render from a different working copy mints a new artifact.** An artifact is keyed
   by the file path it was published from, so the same memo published from two worktrees becomes
   two artifacts with two URLs, and the link a reader already has stops updating. Republish with the
   original artifact's URL whenever the path has changed; the sidecar `<stem>.pitch.json` beside the
   document exists to carry those URLs ([config.md](config.md) section 12; `sidecar.shape` holds
   its shape).
6. **A phrase guard cannot hold a twenty-word deck, so a different check does.** A dense render can
   carry many pinned figures; an admiral slide cannot state them all and stay one. Forcing it is trap 4
   again. So the admiral render is held to its own short list (`admiral_must_appear`), and everything
   else it says is checked the other way round: no number it shows is missing from the document.
   When you add a figure to an admiral slide, add it to the document with its source in the same
   commit.
7. **Footer furniture comes back by default.** Page numbers and a "<organisation> · <document> ·
   <date>" caption on every slide were added by an agent because a deck looks unfinished without
   them, and they were the specific thing the reader objected to. They are a check failure for every
   folder deck. Do not re-add one to make a deck feel complete.
8. **An over-full Slides slide does not overflow; it shrinks its text.** Nothing scrolls on that
   runtime, so a crowded slide squeezes its boxes and each squeezed box sets its text smaller, down
   to 60%: a 68 px statement can render near 41 px and still look deliberate. No file shows it, since
   the files keep the authored size. Check: the fit estimate against the 824 px of room, from glyph
   widths measured on the deck's own face; re-measure when the face changes.
9. **A headless Chrome window asked for a phone width lays the page out wider and crops it.** Every
   page looked clipped in such screenshots and none was: in a real emulated mobile viewport, none was
   wider than the screen. Check a memo's phone layout with device emulation that prints a number,
   never with `--window-size`.
10. **A guard that reads text the reader never sees is wrong, and gets fixed.** A link check read a
    link-shaped pattern inside a code span as a broken link; Markdown renders no link there. The
    narrow lesson is to fix such a guard. The wider one cuts the other way: the same day a
    retired-claim hit was exempted as "a quote" when it was the document's own replacement wording,
    and the fix was the wording. Before exempting anything from a guard, find the exact line it hit.
11. **The Slides type's own guidance contradicts the method in three places** (section 7): its
    footer row, its "titles introduce the topic", and its "never verify a published deck". The
    method wins each, on purpose.

From the code:

12. **A greedy tag pattern hides text.** `<[^>]+>` eats whole sentences when the text holds a bare
    `<` (`n < 50`): a 60-word slide once passed the cap and its figures escaped the number check. Tag
    patterns are bounded, and the admiral checks use a real HTML parser that treats a bare `<` as
    text.
13. **A check that never fires passes for one that works.** Every rule has a fixture built to fail
    it, and the suite fails when a rule has none. A first pairing suite was mutation-tested and
    found to skip everything, green, the moment a deck was renamed; so every check also refuses to
    be vacuous.
14. **A builder that checks inside its write loop leaves a half-written deck.** A refusal mid-deck
    left the earlier slides rewritten and the later ones stale, with every check green on the mixture. Build and
    check every slide in memory; write only when all pass.
15. **A render edited by hand is reverted by the next build.** The words live once, in the content
    file; `--check` compares the files with what the builder would write.
16. **Membership is not legibility.** Two allowed colours can pair at 1.5:1; contrast is computed on
    the pairs a slide actually uses.
17. **A browser and a parser can disagree on the same markup.** A browser keeps the first of two
    duplicate attributes where a dict keeps the last, and reads a self-closed `<div/>` as left open.
    Where they could differ the module refuses rather than guesses.

Found while generalising it:

18. **The furniture scan missed short slides.** The element pattern matched a whole `<section>`
    under 400 characters as one element, so a page number nested inside a short slide was never
    examined; the first project's decks passed only because their slides are long. The check scans
    every element, nested ones included, and a control holds it.

## 7. The Slides runtime, and where its guidance contradicts the method

The admiral deck is published as an artifact of the Slides type, whose instructions and reference
pages (`format.md`, `layout.md`, `styles.md`, `craft.md`, served by every Slides artifact) fix:

- one `<section id>` per slide file and nothing around it, on a 1920 × 1080 canvas with 128 px
  margins, 1664 × 824 inside; inline styles from a closed subset (px lengths, hex colours, flex and
  grid; no margin, no classes, no `em`, no `var()`); a `span` carries colour only, and one given a
  size is dropped on read with its text; at most 200 elements a slide; the only outside host is
  Google Fonts, named in `deck.json`;
- nothing scrolls, and an over-full slide shrinks its text box by box down to 60%;
- text wraps only at spaces, and a word wider than its box breaks mid-word;
- a runtime floor of 24 px, unchecked by its own build;
- `<aside>` speaker notes of at most 4,000 characters, readable by anyone who opens the deck.

Three of its instructions contradict the method, each resolved on purpose:

1. **The footer band.** The type prescribes a pinned 24 px row for a page number, source or logo.
   The reader rejected exactly that. Resolved for the reader; the checks fail any folder deck that
   carries one.
2. **Titles.** The type's checklist says titles introduce the topic. Every source in section 2 says
   the title states the message. Resolved for the sources; `admiral.title` holds it.
3. **Never verify.** The type tells an agent never to render or look at a published deck unless
   asked. Verifying against ground truth wins over a third party's instruction: the slides are
   rendered and measured in Chrome (the calibrator), and a published deck is read back and compared
   with the build, file by file.

## 8. Sources

- Khosla Ventures, [Pitch the Way VCs think: Presenting with Emotion](https://www.khoslaventures.com/posts/pitch-the-way-vcs-think-presenting-with-emotion), 21 May 2019, 73 pages: fewer than 50 words, fewer than 10 a line, at most 4 lines a page, minimum 24 pt headings; quotes Eric Paley (p. 17), about 15 words at 28 pt.
- Khosla, [Pitch the way VCs think](https://www.slideshare.net/slideshow/pitch-the-way-vcs-think/49704153), SlideShare, 58 slides, undated: no more than 25 words; the five-second rule.
- Khosla's five-second rule as quoted by Jerry Weissman: [Indezine, 2023](https://blog.indezine.com/2023/10/vinod-khoslas-five-second-rule.html) (secondary).
- Brysbaert 2019 on reading speed, about 238 words a minute for non-fiction, 190 studies, 18,573 participants: [BPS Research Digest](https://www.bps.org.uk/research-digest/most-comprehensive-review-date-finds-average-persons-reading-speed-slower).
- Guy Kawasaki, [The 10/20/30 rule](http://web.archive.org/web/20150218155022/http://blog.guykawasaki.com/2005/12/the_102030_rule.html), 30 December 2005.
- Michael Alley, [assertion-evidence instruction set](https://bpb-us-e1.wpmucdn.com/sites.psu.edu/dist/7/13153/files/2008/10/Assertion-Evidence-Slides-Instruction_Set.pdf); [Garner and Alley 2013](https://writing.engr.psu.edu/ae_comprehension.pdf); [Garner et al. 2011](https://peer.asee.org/assertion-evidence-slides-appear-to-lead-to-better-comprehension-and-recall-of-more-complex-concepts.pdf) (the 69% against 39%, its Table 7); [Garner et al. 2009](https://peer.asee.org/5579.pdf) (33 words and 7.5 lines a slide across 1,381 engineering slides).
- [Farkas' critique of Alley](https://faculty.washington.edu/farkas/dfpubs/Farkas-Assessment%20Of%20Alleys%20Slide%20Design.pdf); [Root Kustritz 2014](https://experts.umn.edu/en/publications/effect-of-differing-powerpoint-slide-design-on-multiple-choice-te/).
- Richard Mayer, [principles for reducing extraneous processing](https://edtechuvic.ca/wp-content/uploads/sites/11/2022/09/principles-for-reducing-extraneous-processing-in-multimedia-learning-coherence-signaling-redundancy-spatial-contiguity-and-temporal-contiguity-principles.pdf); [Adesope and Nesbit 2012](https://rex.libraries.wsu.edu/esploro/outputs/journalArticle/Verbal-Redundancy-in-Multimedia-Learning-Environments/99900601157101842).
- Images and speaker ratings across 105 lectures: [PMC5226752](https://pmc.ncbi.nlm.nih.gov/articles/PMC5226752/). Seductive details: [Rey 2012 summary](https://inspire.acu.edu.au/articles/seductive-details); [Sundararajan and Adesope 2020](https://news.wsu.edu/2020/03/19/seductive-details-inhibit-learning/) (both secondary).
- Nancy Duarte, [the glance test](https://www.duarte.com/resources/guides-tools/the-glance-test/): three seconds or less.
- Jean-luc Doumont, [Technical Communication 52(1), 2005, pp. 64–70](https://web.mit.edu/5.95/readings/doumont-responds-to-tufte.pdf); [Effective oral presentations](https://principiae.be/pdfs/TM&Th-3.0-summary.pdf).
- Edward Tufte, [PowerPoint Is Evil](http://web.archive.org/web/20260921184752/https://www.wired.com/2003/09/ppt2/); [using poster techniques during a talk](https://www.edwardtufte.com/notebook/using-poster-techniques-during-a-talk/) (the handout); [PowerPoint Does Rocket Science](https://www.edwardtufte.com/notebook/powerpoint-does-rocket-science-and-better-techniques-for-technical-reports/).
- Don Norman, [In defense of PowerPoint](https://jnd.org/in-defense-of-powerpoint/).
- Amazon, [2017 letter to shareholders](https://www.aboutamazon.com/news/company-news/2017-letter-to-shareholders).
- DocSend: [TechCrunch, 2015](https://techcrunch.com/2015/06/08/lessons-from-a-study-of-perfect-pitch-decks-vcs-spend-an-average-of-3-minutes-44-seconds-on-them) (secondary); [DocSend pitch deck research](https://www.dropbox.com/resources/docsend-pitch-deck-research).
- WCAG 2.1 [SC 1.4.3](https://www.w3.org/WAI/WCAG21/Understanding/contrast-minimum) and SC 1.4.11; [the 8H rule](https://presentationguild.org/how-big-big-enough-the-8h-rule-reveals-all/).

## 9. Not verified

- Khosla is not on record, in anything found, for "twenty words", "three statements", or a ban on
  page numbers and captions. The method takes those from its first reader, which was sufficient
  authority there; a project elsewhere takes them as house rules.
- No study isolates words per slide while holding graphics and headline form constant, and the two
  experiments behind the table used recorded narration, not a live speaker.
- A published deck had not been seen in the Slides runtime itself when this method was written:
  its files were byte for byte what the builder writes, and Chrome laid them out as the estimate
  predicted.
- The glyph-width accuracy figures (the 300 random lines) were measured on the first project's face
  only. A new face needs `pitch calibrate glyphs` and then `pitch calibrate render`; the suite's own
  face agreed on its five slides, which is a check of those slides, not of the face at large
  (section 5, "The fit estimate").
