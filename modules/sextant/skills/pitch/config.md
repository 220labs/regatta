# pitch.json: every parameter

*Every value that differs between projects, with its meaning, its default and a neutral example;
then the sidecar each document's publishes leave beside it, and a pytest template for a project whose
check is pytest. `pitch` reads one JSON file, `pitch.json`, found at or above the folder being
checked or named with `--config`. Anything left out takes the default in sextant's `bin/pitchlib.py`
(`DEFAULTS`). Why each rule is what it is: [method.md](method.md), beside this file.*

A config may start with `"extends": "<path to another config>"`, relative to itself: the other one
loads first and this one overrides it, dicts merged key by key, lists replaced whole. The failing
fixtures use it to change one setting each.

The worked example is sextant's `tests/fixtures/pitch/pitch.json`, with a passing document, its
renders and its sidecar in `tests/fixtures/pitch/passing/`. A config `pitch` cannot read as written
(a `publish` value outside its set, a glyph table measuring another face) stops the check with
exit 2, never a finding.

## 1. `admiral`: the spoken render's rules

| Key | Default | Meaning | Neutral example |
| --- | --- | --- | --- |
| `max_words` | `25` | words on screen per slide, notes excluded; the refusal | `25` |
| `target_words` | `20` | the aim; advisory, no check reads it | `20` |
| `max_statements` | `3` | text blocks besides the title (`p`, `li`, `h3`, `blockquote`) | `3` |
| `max_lines` | `2` | lines a title or statement may run to | `2` |
| `min_font_px` | `60` | the smallest type any block may render at, in px on a 1080 px canvas | `60` |
| `max_slides` | `12` | slides in one admiral deck | `12` |
| `letter_spacing_px` | `[-8, 0]` | the range a title or statement may set | `[-8, 0]` |
| `text_contrast` | `4.5` | WCAG ratio for text | `4.5` |
| `large_text_contrast` | `3.0` | the ratio for text at `large_text_px` and above | `3.0` |
| `large_text_px` | `44` | where "large" starts (the Slides type's threshold) | `44` |
| `mark_contrast` | `3.0` | the ratio a painted mark needs against what it sits on | `3.0` |
| `headline_exempt` | `{}` | `"<document stem>/<slide id>": "<reason, four words or more>"`: slides whose title may name rather than assert | `{"spring-plan-2026-03-01/cover": "a cover names the deck it opens"}` |
| `extra_verbs` | `[]` | base-form verbs added to the title heuristic's lexicon, when a true message fails for want of its verb | `["hire", "rent"]` |
| `dangling_words` | `["a", "an", "the", "of", "to", "in", "on", "at", "by", "for", "and", "or", "with"]` | words a wrapped line may not end on | as default |

## 2. `runtime`: the Slides runtime's own numbers

Change these only when the runtime changes; they are its facts, not the method's choices.

| Key | Default | Meaning |
| --- | --- | --- |
| `canvas_px` | `[1920, 1080]` | the slide canvas |
| `margin_px` | `128` | the standard margin; the section's padding may not be smaller. 1664 × 824 inside |
| `max_note_chars` | `4000` | one `<aside>` |
| `max_elements` | `200` | elements a slide, notes excluded |
| `shrink_floor` | `0.6` | how far an over-full box shrinks its text; used in the message only |

## 3. `palette`

| Key | Default | Meaning | Neutral example |
| --- | --- | --- | --- |
| `allowed` | `[]` | every hex colour an admiral slide may use: the brand's tokens plus any tints the decks add. Empty means every colour fails, on purpose | `["#1F2430", "#5A6170", "#2F6FDB", "#FFFFFF", "#F6F7F9", "#C9CED8"]` |

## 4. `face`: the type face and its measured widths

| Key | Default | Meaning | Neutral example |
| --- | --- | --- | --- |
| `family` | `""` | the face the slides name first in their stack; the glyph table must describe this family | `"Source Sans 3"` |
| `stack` | `"Arial, sans-serif"` | the fallbacks after it | `"Arial, sans-serif"` |
| `href` | `""` | its Google Fonts css2 link, for `deck.json` and the calibrator | `"https://fonts.googleapis.com/css2?family=Source+Sans+3:wght@400;600;700;800&display=swap"` |
| `weights` | `[400, 600, 700, 800]` | the weights to measure | as default |
| `glyphs` | `""` | the glyph table `pitch calibrate glyphs` writes, relative to the config. Empty: the estimate uses `fallback_em`. Named but absent, or measuring another family: the check stops (exit 2) until it is measured | `"glyphs-source-sans-3.json"` |
| `fallback_em` | `0.6` | width of one character, in em, for a face not measured (the Slides type's figure; it over-wraps) | `0.6` |
| `wrap_margin` | `0.005` | the estimate wraps in a box this much narrower than the real one, for kerning | `0.005` |

The glyph table's shape: `{"family": "<name>", "chars": "<every character measured>", "widths":
{"400": [<thousandths of an em, one per character>], "700": […]}}`. It is never written by hand:
run `pitch calibrate glyphs <docs-root>` (headless Chrome and the network; `CHROME` names the browser
when it is not at the macOS default), then `pitch calibrate render <docs-root>` to see the estimate
agree with Chrome slide by slide (exit 1 on a line-count difference; `--shots DIR` writes a PNG per
slide). Neither is part of any check.

## 5. `captain`: the read render

| Key | Default | Meaning | Neutral example |
| --- | --- | --- | --- |
| `min_font_px` | `16` | the floor for a memo page and a single-file deck | `16` |
| `allowed_load_hosts` | `["https://cdnjs.cloudflare.com/", "https://fonts.googleapis.com/", "https://fonts.gstatic.com/"]` | URL prefixes a memo may load scripts, styles and media from (the artifact runtime's allowlist); `publish.asset_host` joins them when set | as default |

## 6. `furniture`: page numbers and captions

| Key | Default | Meaning |
| --- | --- | --- |
| `caption_floor_px` | `40` | text below this size, or positioned absolutely, counts as furniture |
| `caption_min_slides` | `3` | a furniture line on this many slides of one deck is a running caption |
| `caption_max_chars` | `120` | longer furniture text is not treated as a caption |

## 7. `naming`: how renders pair with their document

| Key | Default | Meaning | Neutral example |
| --- | --- | --- | --- |
| `documents_glob` | `"*.md"` | the source documents, relative to the root | `"*.md"` |
| `admiral_suffix` | `"-admiral-deck"` | `<stem><suffix>/project/` is the admiral render | as default |
| `folder_deck_suffixes` | `["-deck", "-admiral-deck"]` | every folder-deck suffix; the furniture and index rules bind all of them | as default |
| `memo_suffix` | `"-memo.html"` | the captain page | as default |
| `single_deck_suffix` | `"-deck.html"` | the older single-file deck | as default |
| `content_file` | `"slides.json"` | the builder's content file, in `<stem><admiral_suffix>/` | as default |
| `deck_index_version` | `4` | the `v` a Slides `deck.json` must carry | `4` |
| `sidecar_suffix` | `".pitch.json"` | `<stem><suffix>` beside the document is its sidecar (section 12) | as default |

## 8. `claims`: what every render must and must not say

| Key | Default | Meaning | Neutral example |
| --- | --- | --- | --- |
| `must_appear` | `{}` | `"<document stem>": [phrases]` that the document and every non-admiral render carry, matched on normalised text (tags, backticks and case dropped). The figures that were wrong once and had to be corrected in two places | `{"spring-plan-2026-03-01": ["$18K", "12 weeks"]}` |
| `admiral_must_appear` | `{}` | the same for the admiral render: the few claims that must survive simplification | `{"spring-plan-2026-03-01": ["$18K"]}` |
| `retired` | `[]` | `[[phrase, why]]`: corrected claims that must not come back in any file under the root. When a decision retires a claim, retire its pinned phrase in the same change | `[["opens every evening", "it opens three evenings a week"]]` |
| `retired_scan` | `["**/*.md", "**/*.html"]` | globs, relative to the root, that the retired check reads | as default |
| `require_pins` | `true` | a render whose document has no entry is a finding, rather than a render nothing compares | `true` |

## 9. `builder`

| Key | Default | Meaning | Neutral example |
| --- | --- | --- | --- |
| `require_content_file` | `true` | an admiral deck with no content file is a finding (nothing generates its slides) | `true` |
| `extra_interpreters` | `[]` | other Pythons the builder's `--check` must also pass under, when people run it by hand with an older one; skipped where absent | `["/usr/bin/python3"]` |

## 10. `layout`: the builder's look

None of these is a rule; the rules above hold whatever they produce. Colours must be in the palette.

| Key | Default | Meaning |
| --- | --- | --- |
| `ink`, `muted`, `accent`, `paper`, `raised` | black, grey, blue, white, light grey | text, secondary text and outlines, dots and bars, the background of even and odd slides |
| `head_px`, `cover_head_px` | `104`, `150` | title size on content slides and on the cover |
| `statement_px`, `lone_statement_px`, `cover_statement_px` | `68`, `76`, `60` | statement size; one statement alone gets more |
| `leading` | `1.25` | statement line-height |
| `text_w`, `head_w` | `1500`, `1560` | statement and title widths, px |
| `head_letter_spacing_px`, `statement_letter_spacing_px` | `-5`, `-1` | tracking |
| `head_gap_px`, `row_gap_px` | `72`, `48` | space under the title, and between statements |
| `transition` | `"fade"` | the slide's `data-transition` |

## 11. `publish`: how the renders reach a reader

Read by the skill when it publishes; of the check, only `asset_host` changes what passes. Every key
is optional.

| Key | Default | Meaning | Neutral example |
| --- | --- | --- | --- |
| `design_system` | `""` | a Design System artifact's https URL; its tokens win over `brand` | `"https://example.com/artifact/design-system"` |
| `brand` | `""` | the brand doc, relative to the config: ink, paper, accent, muted, the faces, the wordmark | `"docs/brand-2026-01-05.md"` |
| `images` | `"none"` | the image route: `none` (the wordmark and drawn figures only), `design` (the Design artifact type), `agy` (an image CLI on the project's own login), `flow` (an image model in a browser, a person present), `imagen` (a paid image API, real money per image) | `"design"` |
| `asset_host` | `""` | a host name alone, no scheme or path: a memo may also load from `https://<host>/`, for an artifact store that returns uploads as absolute URLs | `"assets.example.com"` |

## 12. The sidecar: where each render was published

An artifact is keyed by the file path it was published from, so a render published again from
another working copy becomes a second artifact with a second URL ([method.md](method.md), trap 5).
The sidecar `<stem>.pitch.json`, beside the document and committed with it, carries each render's
URL so the next publish updates the same artifact. The skill writes it at each publish; `pitch
check` holds its shape (`sidecar.shape`) whenever one is there.

```json
{"document": "spring-plan-2026-03-01.md",
 "published": {
   "memo":         {"url": "https://…", "first_published": "2026-03-02", "file": "spring-plan-2026-03-01-memo.html"},
   "admiral_deck": {"url": "https://…", "first_published": "2026-03-03", "type_url": "https://…",
                    "folder": "spring-plan-2026-03-01-admiral-deck", "slides": 9}},
 "assets": {"cover.png": "https://…"},
 "images": [{"file": "cover.png", "route": "design", "prompt": "…"}]}
```

| Key | Required | Holds |
| --- | --- | --- |
| `document` | no | the document's file name; when present it must be the one the sidecar sits beside |
| `published` | yes, one render or more | one entry per published render, keyed by the render: `memo` (the captain page) or `admiral_deck` |
| `published.<render>.url` | yes | the artifact's https URL, the one every later publish updates |
| `published.<render>.first_published` | yes | the date of the first publish, `YYYY-MM-DD` |
| `published.admiral_deck.type_url` | yes, for a deck | the https URL of the artifact type the deck was created from |
| `assets` | no | `{"<file>": "<https URL>"}`: each uploaded file and the URL the upload returned |
| `images` | no | `[{"file", "route", "prompt"}]`: each generated image, its route (any `publish.images` route but `none`) and its prompt |

Any other key, at the top or inside a render's entry (`file`, `folder`, `slides` above, or a note
saying which working copy published it), is a free-form note and passes. `sidecar.shape` fires on a
sidecar that is not JSON, lacks a required key, names a render key it does not know, holds a URL that
is not https or a date that is not one, or sits beside no document (the document renamed and its
sidecar left behind: the root's finding, not a document's). Whether every render it names still exists
is a later rule's question.

## 13. A pytest template, for a project whose check is pytest

`pitch check` is the check; a project whose check is `pytest` runs it through one test per rule id,
so a finding fails the case that names its rule. Save as `tests/test_pitch.py`, point `ROOT` at the
docs root (where `pitch.json` is, or above it), and set `PITCH` when the module is not at the path
shown:

```python
# pitch's check as pytest cases, one per rule id (sextant's skills/pitch/config.md, section 13).
import json, os, subprocess, sys, pytest
from pathlib import Path
PITCH = Path(os.environ.get("PITCH", Path.home() / "projects/regatta/modules/sextant/bin/pitch"))
ROOT = Path(__file__).resolve().parents[1] / "docs"     # the docs root: its documents and their renders
sys.path.insert(0, str(PITCH.parent)); sys.dont_write_bytecode = True   # no __pycache__ in the module
from pitchlib import RULES  # noqa: E402

@pytest.fixture(scope="module")
def findings():
    r = subprocess.run([sys.executable, str(PITCH), "check", str(ROOT), "--json"], capture_output=True, text=True)
    assert r.returncode in (0, 1), r.stderr     # 2: the check could not run, which is no pass
    return json.loads(r.stdout)

@pytest.mark.parametrize("rule", RULES)
def test_rule(findings, rule):
    assert not [f["message"] for f in findings if f["rule"] == rule]
```

Exit 2 (no config, a render it cannot parse) fails every case at the fixture, never passes one. The
rule ids come from the library, so a rule added there is a case here at the next run.

## What is deliberately not a parameter

- **The markup grammar** ([method.md](method.md) section 5): it is what the fit estimate models. Widening it
  without widening the estimate lets a slide past every later check.
- **The title heuristic's base lexicon and its rules**: extend with `extra_verbs`, never replace.
- **The contrast arithmetic**: WCAG 2.1's formula.
- **The page-number pattern**: what a page number looks like to a reader does not vary by brand.
