"""pitch's library: the renders' rules, the checker that holds a docs root to them, and the builder
that writes an admiral deck, in one place.

A document has renders: the captain page (`<stem>-memo.html`), read in full, and the admiral deck
(`<stem>-admiral-deck/project/`), spoken: about twenty words a slide, at most three statements, no
type under 60 px, a title that states the message. The method (method.md) gives every number and its
source. Two things enforce the format: the builder (`pitch build`) refuses to write a slide that
breaks a rule, and the checker (`pitch check`) refuses one that arrived by any other route. Both are
this file, and neither keeps its own copy of a number: two copies of the rules drifting apart is the
stale-render trap in miniature (the method, section 6).

Everything that differs between adopters is a parameter in `pitch.json` (the config reference): the
palette, the face and its measured glyph widths, the limits, the exemptions. The numbers below in
DEFAULTS are the method's own; an adopter overrides them knowingly.

Stdlib only, and Python 3.9, so it runs under a stock macOS `python3`. What the Slides runtime does
(its canvas, its margins, its element and note caps, its shrink-to-fit) is taken from that runtime's
own reference pages (`format.md`, `layout.md`, `styles.md`).

It sits in `bin/` beside `pitch`, not in `lib/`: a module's `lib/` counts as live code (the core's
classes.sh), and nothing runs this from a hook. The three parts below were three files in the
export this came from (the rules, the checker, the builder); their order and their comments are
kept, so a change there reads as a change here.
"""
import copy
import json
import re
import subprocess
import sys
from html.parser import HTMLParser
from pathlib import Path

HERE = Path(__file__).resolve().parent


# ================================================================================================
# The rules
# ================================================================================================

# ------------------------------------------------------------------------------------------------
# The parameters
# ------------------------------------------------------------------------------------------------

DEFAULTS = {
    "admiral": {
        "max_words": 25,            # Khosla's undated SlideShare deck: "no more than 25"
        "target_words": 20,         # the five-second rule at 238 words a minute; advisory only
        "max_statements": 3,
        "max_lines": 2,             # per statement and per title: Doumont's visual limit
        "min_font_px": 60,          # Kawasaki's 30 pt, on a 1080 px canvas
        "max_slides": 12,           # Kawasaki's ten for twenty minutes, with slack
        "letter_spacing_px": [-8, 0],
        "text_contrast": 4.5,       # WCAG 2.1 SC 1.4.3
        "large_text_contrast": 3.0,
        "large_text_px": 44,        # the Slides type's threshold for "large", stricter than WCAG's 24 px
        "mark_contrast": 3.0,       # WCAG 2.1 SC 1.4.11, a painted mark that carries meaning
        "headline_exempt": {},      # "<document stem>/<slide id>": "the reason"
        "extra_verbs": [],          # base forms added to the title heuristic's lexicon
        "dangling_words": ["a", "an", "the", "of", "to", "in", "on", "at", "by", "for", "and", "or", "with"],
    },
    "runtime": {                    # the Slides runtime's own numbers
        "canvas_px": [1920, 1080],
        "margin_px": 128,           # 1664 x 824 inside
        "max_note_chars": 4000,
        "max_elements": 200,
        "shrink_floor": 0.6,        # an over-full box sets its text down to 60% of its size
    },
    "palette": {"allowed": []},     # every hex colour an admiral slide may use
    "face": {
        "family": "",               # the first family in the slide's font stack that the glyph table describes
        "stack": "Arial, sans-serif",
        "href": "",                 # the Google Fonts css2 link, for deck.json and the calibrator
        "weights": [400, 600, 700, 800],
        "glyphs": "",               # a glyphs.json written by `pitch calibrate glyphs`, relative to the config
        "fallback_em": 0.6,         # the Slides type's own per-character figure, for any face not measured
        "wrap_margin": 0.005,       # the estimate wraps in a box this much narrower than the real one
    },
    "captain": {
        "min_font_px": 16,
        "allowed_load_hosts": ["https://cdnjs.cloudflare.com/", "https://fonts.googleapis.com/",
                               "https://fonts.gstatic.com/"],
    },
    "furniture": {"caption_floor_px": 40, "caption_min_slides": 3, "caption_max_chars": 120},
    "naming": {
        "documents_glob": "*.md",
        "admiral_suffix": "-admiral-deck",
        "folder_deck_suffixes": ["-deck", "-admiral-deck"],
        "memo_suffix": "-memo.html",
        "single_deck_suffix": "-deck.html",
        "content_file": "slides.json",
        "deck_index_version": 4,
    },
    "claims": {
        "must_appear": {},          # "<document stem>": [phrases every non-admiral render and the document carry]
        "admiral_must_appear": {},  # "<document stem>": [phrases the admiral render and the document carry]
        "retired": [],              # [[phrase, why]]: corrected claims that must not come back anywhere
        "retired_scan": ["**/*.md", "**/*.html"],
        "require_pins": True,       # a render whose stem has no entry is a finding, not a silent pass
    },
    "builder": {"require_content_file": True, "extra_interpreters": []},
    "layout": {                     # the builder's own look; none of it is a rule
        "ink": "#000000", "muted": "#555555", "accent": "#0055cc", "paper": "#ffffff", "raised": "#f5f5f5",
        "head_px": 104, "cover_head_px": 150, "statement_px": 68, "lone_statement_px": 76,
        "cover_statement_px": 60, "leading": 1.25, "text_w": 1500, "head_w": 1560,
        "head_letter_spacing_px": -5, "statement_letter_spacing_px": -1,
        "head_gap_px": 72, "row_gap_px": 48, "transition": "fade",
    },
}


def _merge(base, over):
    out = copy.deepcopy(base)
    for k, v in over.items():
        if isinstance(v, dict) and isinstance(out.get(k), dict):
            out[k] = _merge(out[k], v)
        else:
            out[k] = copy.deepcopy(v)
    return out


class Config:
    """The merged parameters, read once. `extends` in a config file names another config, relative
    to it, that is loaded first, so a variant changes only what differs."""

    def __init__(self, data=None, base_dir=None):
        d = _merge(DEFAULTS, data or {})
        self.raw, self.base_dir, self.path = d, Path(base_dir) if base_dir else None, None
        a, r, f = d["admiral"], d["runtime"], d["face"]
        self.max_words, self.target_words = a["max_words"], a["target_words"]
        self.max_statements, self.max_lines = a["max_statements"], a["max_lines"]
        self.min_font_px, self.max_slides = a["min_font_px"], a["max_slides"]
        self.letter_spacing_px = tuple(a["letter_spacing_px"])
        self.text_contrast, self.large_text_contrast = a["text_contrast"], a["large_text_contrast"]
        self.large_text_px, self.mark_contrast = a["large_text_px"], a["mark_contrast"]
        self.headline_exempt = dict(a["headline_exempt"])
        self.dangling = {w.lower() for w in a["dangling_words"]}   # tokens are lower-cased
        self.canvas_w, self.canvas_h = r["canvas_px"]
        self.margin, self.max_note_chars, self.max_elements = r["margin_px"], r["max_note_chars"], r["max_elements"]
        self.shrink_floor = r["shrink_floor"]
        self.allowed_colours = {parse_colour(c) for c in d["palette"]["allowed"]} - {None}
        self.face_family, self.face_stack, self.face_href = f["family"], f["stack"], f["href"]
        self.face_weights, self.fallback_em, self.wrap_margin = f["weights"], f["fallback_em"], f["wrap_margin"]
        self.glyphs = self._load_glyphs(f["glyphs"])
        self.captain, self.furniture, self.naming = d["captain"], d["furniture"], d["naming"]
        self.claims, self.builder, self.layout = d["claims"], d["builder"], d["layout"]
        self.verbs = VERBS | {w.lower() for w in a["extra_verbs"]}
        self.finite = AUXILIARIES | _inflected(self.verbs)

    def _load_glyphs(self, name):
        """{weight: {char: thousandths of an em}} for the configured face, or {} (the fallback)."""
        if not name:
            return {}
        path = Path(name) if self.base_dir is None else self.base_dir / name
        g = json.loads(path.read_text(encoding="utf-8"))
        if g.get("family") != self.face_family:
            raise ValueError(f"{path} measures {g.get('family')!r}, the config's face is {self.face_family!r}")
        return {int(w): dict(zip(g["chars"], row)) for w, row in g["widths"].items()}

    @classmethod
    def load(cls, path):
        path = Path(path).resolve()
        data = json.loads(path.read_text(encoding="utf-8"))
        parent = data.pop("extends", None)
        if parent:
            base = cls.load(path.parent / parent)
            # The parent's glyph path stays relative to the parent.
            if "face" not in data or "glyphs" not in data.get("face", {}):
                data = _merge({"face": {"glyphs": str((base.base_dir / base.raw["face"]["glyphs"]))
                                        if base.raw["face"]["glyphs"] else ""}}, data)
            data = _merge(base.raw, data)
        cfg = cls(data, path.parent)
        cfg.path = path
        return cfg


CONFIG_NAME = "pitch.json"


def find_config(start, explicit=None):
    """An explicit path, else the nearest pitch.json at or above `start`."""
    if explicit:
        return Config.load(explicit)
    p = Path(start).resolve()
    for d in [p] + list(p.parents):
        if (d / CONFIG_NAME).exists():
            return Config.load(d / CONFIG_NAME)
    raise SystemExit(f"no {CONFIG_NAME} at or above {p}; pass --config")


def admiral_decks(root, cfg, only=None):
    """(document, project dir) for every admiral render under root: the one definition the checker,
    the calibrator and the builder share."""
    out = []
    for md in sorted(Path(root).glob(cfg.naming["documents_glob"])):
        if only is not None and md.stem != only:
            continue
        project = md.with_name(md.stem + cfg.naming["admiral_suffix"]) / "project"
        if (project / "deck.json").exists():
            out.append((md, project))
    return out


def stem_of(deck_dir, cfg):
    """The document stem of an admiral deck folder, for headline_exempt's keys."""
    return Path(deck_dir).name[: -len(cfg.naming["admiral_suffix"])]


# ------------------------------------------------------------------------------------------------
# Reading a slide
# ------------------------------------------------------------------------------------------------

# A bounded tag pattern: a greedy `<[^>]+>` eats whole sentences, and one literal `<` in a note
# (`n < 50`) once swallowed the rest of a slide, so a 60-word slide passed the cap and its figures
# escaped the number check. The admiral checks read a slide with the parser below, which treats a
# bare `<` as text; this pattern serves the furniture checks that scan every folder deck.
TAG = re.compile(r"</?[a-zA-Z][^<>]{0,400}>|<!--[^<>]{0,400}-->")


def strip_tags(html):
    return TAG.sub(" ", html)


VOID = {"br", "img", "hr", "x-icon", "x-shape", "x-connector"}
INLINE = {"b", "i", "u", "a", "span", "br"}
TEXT_TAGS = {"h1", "h2", "h3", "p", "li", "blockquote"}
# What counts towards the statement cap: every text-bearing block, summed. A first version took
# list items *or* paragraphs, so one list item hid six paragraphs.
STATEMENT_TAGS = ("li", "p", "h3", "blockquote")
# The runtime's tag defaults (format.md, "Text"): size px, weight, line-height.
TAG_DEFAULTS = {"h1": (96, 600, 1.1), "h2": (64, 600, 1.15), "h3": (44, 600, 1.2), "p": (32, 400, 1.4)}
NBSP = " "     # a space the line may not break at; words() still counts the two words it joins


def parse_style(style, faults=None):
    """Declarations as a dict. A property declared twice, or marked !important, is recorded in
    faults: CSS lets an earlier !important win where this dict keeps the last value, so the two
    would read different sizes and colours."""
    out = {}
    for part in style.split(";"):
        if ":" in part:
            k, v = part.split(":", 1)
            k, v = k.strip().lower(), v.strip()
            if faults is not None and (k in out or "!" in v):
                faults.append(f"{k}:{v}")
            out[k] = v
    return out


class Node:
    def __init__(self, tag, attrs, parent, closed=False):
        self.tag, self.attrs, self.parent = tag, dict(attrs), parent
        # Where this tree and a browser's could differ, it is recorded and refused rather than
        # guessed: a browser keeps the first of two duplicate attributes (dict keeps the last), and
        # a self-closed <div/> is an open <div> to a browser, not an empty one.
        names = [a for a, _ in attrs]
        self.faults = [f"duplicate attribute {a}" for a in sorted({a for a in names if names.count(a) > 1})]
        if closed and tag not in VOID:
            self.faults.append("self-closed, which a browser reads as left open")
        self.style = parse_style(self.attrs.get("style") or "", self.faults)
        self.children = []      # Node or str

    def iter(self):
        yield self
        for c in self.children:
            if isinstance(c, Node):
                yield from c.iter()

    def text(self):
        """The text a viewer reads, block elements separated by a space and inline ones not."""
        parts = []
        for c in self.children:
            if isinstance(c, str):
                parts.append(c)
            elif c.tag != "aside":
                # A <br> breaks the line, so it separates words too; other inline tags do not.
                sep = "" if c.tag in INLINE and c.tag != "br" else " "
                parts.append(sep + c.text() + sep)
        # ASCII whitespace only: a no-break space is a decision about where a line may break, and
        # Python's \s would quietly turn it back into a break.
        return re.sub(r"[ \t\r\n\f]+", " ", "".join(parts)).strip(" \t\r\n\f")

    def inherited(self, prop):
        n = self
        while n is not None:
            if prop in n.style:
                return n.style[prop]
            n = n.parent
        return None


class _Tree(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)     # entities become characters, as a reader sees them
        self.root = Node("#root", [], None)
        self.cur = self.root

    def handle_starttag(self, tag, attrs):
        node = Node(tag, attrs, self.cur)
        self.cur.children.append(node)
        if tag not in VOID:
            self.cur = node

    def handle_startendtag(self, tag, attrs):
        self.cur.children.append(Node(tag, attrs, self.cur, closed=True))

    def handle_endtag(self, tag):
        n = self.cur
        while n is not self.root and n.tag != tag:
            n = n.parent
        if n is not self.root:
            self.cur = n.parent

    def handle_data(self, data):
        self.cur.children.append(data)


class Slide:
    """One `<section>` file, read the way the runtime and a viewer read it."""

    def __init__(self, html_text, name=""):
        self.name, self.html = name, html_text
        tree = _Tree()
        tree.feed(html_text)
        tree.close()
        sections = [n for n in tree.root.iter() if n.tag == "section"]
        if len(sections) != 1:
            raise ValueError(f"{name}: {len(sections)} <section> elements, the runtime wants one")
        self.section = sections[0]
        self.asides = [n for n in self.section.iter() if n.tag == "aside"]
        self.note = " ".join(a.text() for a in self.asides)
        self.nodes = [n for n in self.section.iter() if not _in_aside(n)]

    @property
    def visible(self):
        return self.section.text()

    @property
    def words(self):
        return words(self.visible)

    @property
    def headings(self):
        return [n for n in self.nodes if n.tag in ("h1", "h2", "h3")]

    @property
    def headline(self):
        return self.headings[0].text() if self.headings else ""

    @property
    def statements(self):
        """Every text block but the title. Graphics are painted `div`s with no text, so they never
        count; a labelled graphic would, which is the point."""
        return [n.text() for n in self.nodes if n.tag in STATEMENT_TAGS]

    @property
    def figures(self):
        """Every number a viewer sees or the speaker is handed: the slide's text and its note,
        each with its magnitude, so `$250M` is not taken for the document's `$250K`."""
        return numbers(self.visible + " " + self.note)


def _in_aside(node):
    n = node
    while n is not None:
        if n.tag == "aside":
            return True
        n = n.parent
    return False


def words(text):
    return [w for w in re.split(r"\s+", text.strip()) if w]


def numbers(text, with_bare=False):
    """Numeric tokens as a reader meets them: 12, 4.5, 2,400, 250K (from $250K). A K, M or B
    stays on its number, since that is the difference between a budget and a typo. with_bare also
    yields each number without its magnitude: the document side, so a slide's plain 250 still
    matches the document's 250K."""
    found = set()
    # The magnitude in any spelling a reader would take as one: 250K, 250k, 250 thousand, 3bn.
    pattern = r"(\d+(?:,\d{3})*(?:\.\d+)?)((?:bn|[kmb])(?![a-z])|\s(?:thousand|million|billion)\b)?"
    for num, mag in re.findall(pattern, text, flags=re.I):
        word = mag.strip().lower()
        found.add(num + {"": "", "k": "K", "thousand": "K", "m": "M", "million": "M",
                         "b": "B", "bn": "B", "billion": "B"}[word])
    if with_bare:
        found |= {re.sub(r"[KMB]$", "", t) for t in found}
    return found


def font_px(node):
    """The node's font size: its own, inherited into p and li, or the tag default. h1-h3 do not
    inherit a size in the Slides runtime (format.md, "Document")."""
    own = node.style.get("font-size")
    if own:
        return _px(own)
    if node.tag in ("h1", "h2", "h3"):
        return TAG_DEFAULTS[node.tag][0]
    inherited = node.parent.inherited("font-size") if node.parent else None
    return _px(inherited) if inherited else TAG_DEFAULTS["p"][0]


def _px(value, base=None):
    value = value.strip()
    m = re.fullmatch(r"(-?(?:\d+(?:\.\d+)?|\.\d+))(px|em)?", value)
    if not m:
        return None
    n = float(m.group(1))
    return n * base if (m.group(2) == "em" and base) else n


# Every problem below is (rule id, message). The rule ids are what the config reference and the method list and
# what the failing fixtures name; a caller that wants text alone takes the second element.

def type_problems(slide, cfg):
    """The floor, in px only, on the size each block actually renders at. `14.5px`, `1.5rem` and
    `24pt` all walked past an earlier whole-px scan, so a size in any other unit is refused rather
    than converted. And a declared size is not the only one: an unstyled <p> renders at the
    runtime's 32 px default, which a scan of declarations never sees."""
    out = []
    for n in slide.nodes:
        if "font-size" in n.style:
            value = n.style["font-size"]
            if not re.fullmatch(r"\d+(?:\.\d+)?px", value):
                out.append(("admiral.type-floor", f"{slide.name}: font-size {value!r} - admiral slides size type in px only"))
        if n.tag in TEXT_TAGS and n.text():
            px = font_px(n)
            if px is not None and px < cfg.min_font_px:
                out.append(("admiral.type-floor", f"{slide.name}: <{n.tag}> “{n.text()[:30]}” renders at {px:g}px "
                                                  f"(floor {cfg.min_font_px}px)"))
    return out


# The admiral render is a closed grammar, per tag, inside the runtime's own subset: the shapes the
# builder emits and the estimate in this file models, and nothing else. Reviews got slides past a
# single global list of allowed properties, because every property it allowed had to be modelled on
# every tag it could appear on, and was not: a sized <b> inside a statement, text in a <b> straight
# inside a <div>, a <p> nested in a <p> (a browser closes the first), a negative gap, a height or a
# border on a paragraph, a width wider than its column, letter-spacing of -40px, line-height 0, the
# `font:` shorthand, a gradient, a grid. So each tag has its own grammar, and a slide is exactly:
#   <section> holds one title, body <div>s and one <aside>, last;
#   a title (<h1> or <h2>) or a statement (<p>) holds text only, sizes its own type, and may set a
#     width no wider than its column, a colour, a weight, a line-height of 1 or more and a
#     letter-spacing inside the configured range;
#   a <div> holding text is layout only: flex, direction, gap, alignment;
#   a <div> holding no text is a mark (a dot, a bar, a week) and alone may be painted, sized,
#     bordered or rounded;
#   lengths are px and never negative, save letter-spacing.
# Widen a grammar only together with the estimate, contrast_problems() and the controls in the suite.
HEX = r"#[0-9a-fA-F]{3}(?:[0-9a-fA-F]{3})?"
LEN = r"\d+(?:\.\d+)?px"
ALIGN = r"start|center|end|stretch|flex-start|flex-end"
SECTION_STYLE = {
    "background": HEX, "color": HEX, "font-family": r"[A-Za-z0-9 ,'\"-]+",
    "padding": rf"{LEN}(?: {LEN}){{0,3}}", "display": r"flex", "flex-direction": r"column",
    "justify-content": r"start|center|flex-start", "gap": LEN,
}
TEXT_STYLE = {
    "font-size": LEN, "font-weight": r"[1-9]00|bold|normal", "line-height": r"\d+(?:\.\d+)?",
    "letter-spacing": r"-?\d+(?:\.\d+)?px", "width": LEN, "color": HEX,
}
LAYOUT_STYLE = {"display": r"flex", "flex-direction": r"row|column", "gap": LEN, "align-items": ALIGN}
MARK_STYLE = dict(LAYOUT_STYLE, **{
    "flex": r"none", "width": LEN, "height": LEN, "background": HEX,
    "border": rf"\d+px solid {HEX}", "border-radius": r"\d+(?:px|%)", "overflow": r"hidden",
})
ATTRIBUTES = {"section": {"id", "style", "data-transition"}}


def _grammar(node):
    if node.tag == "section":
        return SECTION_STYLE
    if node.tag in ("h1", "h2", "p"):
        return TEXT_STYLE
    if node.tag == "div":
        return LAYOUT_STYLE if node.text() else MARK_STYLE
    if node.tag == "aside":
        return {}
    return None


def markup_problems(slide, cfg):
    R = "admiral.markup"
    out = []
    for n in slide.section.iter():
        where = f"{slide.name}: <{n.tag}>"
        out += [(R, f"{where}: {f}") for f in n.faults]
        if n.tag != "aside" and _in_aside(n):
            out.append((R, f"{where} inside the note: a note is plain text"))
            continue
        grammar = _grammar(n)
        if grammar is None:
            out.append((R, f"{where} is outside what an admiral slide may use"))
            continue
        extra = set(n.attrs) - ATTRIBUTES.get(n.tag, {"style"})
        if extra:
            out.append((R, f"{where} carries {sorted(extra)}, which the estimate does not read"))
        for prop, value in n.style.items():
            pattern = grammar.get(prop)
            if pattern is None:
                out.append((R, f"{where}: {prop} is outside this tag's grammar"))
            elif not re.fullmatch(pattern, value):
                out.append((R, f"{where}: {prop}:{value} is not a form the estimate reads"))
        if n.tag in ("h1", "h2", "p"):
            kids = [c.tag for c in n.children if isinstance(c, Node)]
            if kids:
                out.append((R, f"{where} holds {kids}: a title or statement holds text only"))
            if "font-size" not in n.style:
                out.append((R, f"{where} sets no size of its own, so its size would rest on inheritance"))
            ls = _px(n.style.get("letter-spacing", "0px")) or 0
            lo, hi = cfg.letter_spacing_px
            if not lo <= ls <= hi:
                out.append((R, f"{where}: letter-spacing {ls:g}px is outside {cfg.letter_spacing_px}"))
            lh = n.style.get("line-height", "1")
            if re.fullmatch(r"\d+(?:\.\d+)?", lh) and float(lh) < 1:
                out.append((R, f"{where}: line-height {lh} sets lines over each other"))
        elif n.tag in ("section", "div"):
            own = "".join(c for c in n.children if isinstance(c, str)).strip()
            if own:
                out.append((R, f"{where}: text “{own[:30]}” sits outside a paragraph or heading"))
    kids = [c for c in slide.section.children if isinstance(c, Node)]
    if slide.asides and kids and kids[-1].tag != "aside":
        out.append((R, f"{slide.name}: the <aside> is not the section's last child"))
    if len(slide.headings) != 1:
        out.append((R, f"{slide.name}: {len(slide.headings)} headings; an admiral slide has exactly one title"))
    if len(slide.asides) > 1:
        out.append((R, f"{slide.name}: {len(slide.asides)} notes; the runtime takes one <aside>"))
    if "background" not in slide.section.style:
        out.append((R, f"{slide.name}: the section paints no background"))
    pad = _box(slide.section.style, "padding")
    if min(pad) < cfg.margin:
        out.append((R, f"{slide.name}: section padding {pad} is under the {cfg.margin}px margin"))
    return out


def density_problems(slide, cfg):
    out = []
    if len(slide.words) > cfg.max_words:
        out.append(("admiral.words", f"{slide.name}: {len(slide.words)} words on screen (limit {cfg.max_words}) "
                                     "- cut it, or move it to the note"))
    if len(slide.statements) > cfg.max_statements:
        out.append(("admiral.statements", f"{slide.name}: {len(slide.statements)} statements "
                                          f"(limit {cfg.max_statements})"))
    if len(slide.note) > cfg.max_note_chars:
        out.append(("admiral.runtime-limits", f"{slide.name}: a {len(slide.note)}-character note "
                                              f"(the runtime's limit is {cfg.max_note_chars})"))
    elements = sum(1 for n in slide.section.iter() if n is not slide.section and not _in_aside(n))
    if elements > cfg.max_elements:
        out.append(("admiral.runtime-limits", f"{slide.name}: {elements} elements "
                                              f"(the runtime's limit is {cfg.max_elements})"))
    return out


# ------------------------------------------------------------------------------------------------
# Is the headline a message or a topic?
# ------------------------------------------------------------------------------------------------
#
# Khosla, Alley and Doumont agree that a title states the slide's message. In the first deck this
# method was built for, most titles were topics, and nothing caught it. Telling a clause from a label exactly needs a parser, so this is a heuristic, and says
# so. It catches the two shapes a topic title takes in practice:
#   - a bare noun phrase, with no verb at all: "The budget", "Next week", "The shortfall";
#   - a wh-label, which holds a verb but asserts nothing: "Where things stand", "What members get".
# A headline passes when no wh-word comes before its verb (a question, ending "?", is allowed) and
# it holds a verb from the lexicon below where a verb can stand. An auxiliary counts anywhere. An
# -s or -ed form counts after a word, but not first ("Changes", "Measured results" are labels) and
# not after a determiner ("The costs"). A base form counts first only when an object follows, as in
# an imperative ("Fix the queue first", not "Test results"), and otherwise after a subject pronoun,
# a modal or a plural noun ("Members get three things", "Reviews matter"); after "the", "a" or "our" it
# is a noun ("The record"). An assertion whose verb is missing from the lexicon fails with a message
# saying so: add the verb (`extra_verbs` in the config). That false alarm is the price of having no
# dependency, and it fails loud, never silently.

WH = {"what", "where", "when", "why", "how", "who", "which", "whose"}
SUBJECTS = {"i", "we", "you", "they", "nobody", "everyone", "everybody", "nothing", "everything", "people"}
OBJECTS = {"it", "us", "them", "me", "him", "everything", "nothing", "what"}
DETERMINERS = {"the", "a", "an", "this", "that", "these", "those", "our", "your", "their", "its", "my",
               "his", "her", "one", "no", "each", "every", "any", "some"}
AUXILIARIES = {
    "is", "are", "was", "were", "be", "been", "am", "isn't", "aren't", "wasn't", "weren't",
    "has", "have", "had", "hasn't", "haven't", "hadn't",
    "does", "do", "did", "doesn't", "don't", "didn't",
    "can", "could", "will", "would", "shall", "should", "may", "might", "must",
    "can't", "cannot", "won't", "wouldn't", "shouldn't", "mustn't",
}
MODALS = {"can", "could", "will", "would", "shall", "should", "may", "might", "must", "do", "does",
          "did", "don't", "doesn't", "didn't", "can't", "cannot", "won't"}
CONJUNCTIONS = {"and", "or", "but", "nor"}
# A word ending in s that is singular, not a plural subject: "Status check" is a label.
NOT_PLURAL = ("ss", "us", "is")
# Content verbs, base form. Regular -s and -ed forms are derived; irregular ones are listed.
VERBS = {
    "add", "arrive", "ask", "beat", "become", "begin", "block", "build", "buy", "change", "check",
    "come", "cost", "cut", "decide", "deliver", "drop", "end", "fail", "find", "finish", "fit",
    "get", "give", "go", "grow", "guard", "hold", "keep", "know", "land", "last", "lead", "leave",
    "let", "lose", "make", "matter", "mean", "measure", "miss", "move", "need", "order",
    "pass", "pay", "prove", "put", "reach", "read", "record", "remain", "run", "save", "say", "see",
    "sell", "send", "ship", "show", "spend", "stand", "start", "stay", "stop", "take", "test", "tell",
    "think", "turn", "wait", "want", "win", "work", "wreck", "write",
}
IRREGULAR = {
    "beat": ["beaten"], "become": ["became"], "begin": ["began", "begun"], "build": ["built"],
    "buy": ["bought"], "come": ["came"], "find": ["found"], "get": ["got", "gotten"],
    "give": ["gave", "given"], "go": ["goes", "went", "gone"], "grow": ["grew", "grown"],
    "hold": ["held"], "keep": ["kept"], "know": ["knew", "known"], "lead": ["led"], "leave": ["left"],
    "lose": ["lost"], "make": ["made"], "mean": ["meant"], "pay": ["paid"], "run": ["ran"],
    "say": ["said"], "see": ["saw", "seen"], "sell": ["sold"], "send": ["sent"], "show": ["shown"],
    "spend": ["spent"], "stand": ["stood"], "take": ["took", "taken"], "tell": ["told"],
    "think": ["thought"], "win": ["won"], "write": ["wrote", "written"],
    # Past tense the same as the base form: no -ed form at all.
    "cost": [], "cut": [], "let": [], "put": [], "read": [],
}


def _inflected(verbs):
    """The -s form and the past of every verb. An irregular verb takes its listed forms only (a
    first version derived "seed" from see and "cuted" from cut); a short verb ending
    consonant-vowel-consonant doubles its last letter (drop, dropped)."""
    out = set()
    for v in verbs:
        out.add(v + ("es" if v.endswith(("s", "sh", "ch", "x", "o")) else "s"))
        if v in IRREGULAR:
            out.update(IRREGULAR[v])
        elif v.endswith("e"):
            out.add(v + "d")
        elif re.fullmatch(r"[^aeiou]*[aeiou][^aeiouwxy]", v):
            out.add(v + v[-1] + "ed")
        else:
            out.add(v + "ed")
    return out - verbs


_DEFAULT_LEXICON = None


def headline_problem(headline, cfg=None):
    """None when the headline reads as a message; else why it reads as a topic."""
    global _DEFAULT_LEXICON
    if cfg is None:
        _DEFAULT_LEXICON = _DEFAULT_LEXICON or (VERBS, AUXILIARIES | _inflected(VERBS))
        verbs, finite = _DEFAULT_LEXICON
    else:
        verbs, finite = cfg.verbs, cfg.finite
    # A hyphenated compound is one word: "to-do" and "must-have" are not "do" and "have".
    tokens = [t.lower().strip("-") for t in re.findall(r"[A-Za-z][A-Za-z’'-]*", headline)]
    tokens = [t.replace("’", "'") for t in tokens]
    if not tokens:
        return "no headline"
    question = headline.rstrip().endswith("?")
    # Two words with no auxiliary are a label however they parse: "Rent costs", "Test runs",
    # "Money left". A message title is a sentence, and a sentence that short needs its "is".
    short = len(tokens) < 3
    for i, t in enumerate(tokens):
        prev = tokens[i - 1] if i else None
        nxt = tokens[i + 1] if i + 1 < len(tokens) else None
        last = nxt is None
        if t in WH and not question:
            return f"“{headline}” is a wh-label, a topic: say what is true about it"
        if t in AUXILIARIES:
            return None
        if short:
            continue
        # An -s or -ed form after a word, not after a determiner or "and", and not closing the
        # title, where it is a plural noun ("Risks and asks") or a participle ("money left").
        if t in finite and i and not last and prev not in DETERMINERS | CONJUNCTIONS:
            return None
        if t in verbs and (
            (i == 0 and (nxt in DETERMINERS or nxt in OBJECTS))
            or (i and (prev in SUBJECTS or prev in MODALS
                       or (prev.endswith("s") and not prev.endswith(NOT_PLURAL)
                           and prev not in DETERMINERS | AUXILIARIES)))
        ):
            return None
    return (f"“{headline}” has no verb, so it names a topic: state the message "
            "(if it does, add its verb to admiral.extra_verbs in the config)")


def title_problems(slide, key, cfg):
    """The headline rule, unless headline_exempt names this slide. key is "<stem>/<slide id>"."""
    if key in cfg.headline_exempt:
        return []
    why = headline_problem(slide.headline, cfg)
    return [("admiral.title", f"{slide.name}: {why}")] if why else []


# ------------------------------------------------------------------------------------------------
# Contrast
# ------------------------------------------------------------------------------------------------

def parse_colour(value):
    """'#rgb', '#rrggbb' or 'rgb(r, g, b)' as '#rrggbb'; None for anything else."""
    if not value:
        return None
    value = value.strip().lower()
    m = re.fullmatch(r"#([0-9a-f]{3}|[0-9a-f]{6})", value)
    if m:
        h = m.group(1)
        return "#" + ("".join(c * 2 for c in h) if len(h) == 3 else h)
    m = re.fullmatch(r"rgb\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\)", value)
    if m:
        return "#" + "".join(f"{int(x):02x}" for x in m.groups())
    return None


def _channel(c):
    c /= 255
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def luminance(hexval):
    h = parse_colour(hexval)[1:]
    r, g, b = (int(h[i:i + 2], 16) for i in (0, 2, 4))
    return 0.2126 * _channel(r) + 0.7152 * _channel(g) + 0.0722 * _channel(b)


def contrast(a, b):
    hi, lo = sorted((luminance(a), luminance(b)), reverse=True)
    return (hi + 0.05) / (lo + 0.05)


def _paint(node):
    """The colour a node paints behind itself, if any."""
    return parse_colour(node.style.get("background", "").split()[0] if node.style.get("background") else None)


def _ground(node):
    """The colour behind a node: the nearest ancestor that paints one."""
    n = node.parent
    while n is not None:
        p = _paint(n)
        if p:
            return p
        n = n.parent
    return None


def _border_colour(style):
    for key in ("border", "border-top", "border-bottom", "border-left", "border-right"):
        if key in style:
            for part in style[key].split():
                c = parse_colour(part)
                if c:
                    return c
    return None


def _nearest_text_block(node):
    n = node.parent
    while n is not None:
        if n.tag in TEXT_TAGS:
            return n
        n = n.parent
    return None


def contrast_problems(slide, cfg):
    """Membership of the palette is not legibility: two allowed colours can pair at 1.5:1."""
    R = "admiral.contrast"
    out = []
    for n in slide.nodes:
        own_text = "".join(c for c in n.children if isinstance(c, str)).strip()
        if own_text and n.tag not in ("section", "div"):
            fg = parse_colour(n.inherited("color"))
            bg = _paint(n) or _ground(n)
            if fg is None or bg is None:
                out.append((R, f"{slide.name}: cannot read the colours of <{n.tag}> “{own_text[:30]}”"))
                continue
            block = n if n.tag in TEXT_TAGS else _nearest_text_block(n)
            px = font_px(block) if block else TAG_DEFAULTS["p"][0]
            need = cfg.large_text_contrast if px >= cfg.large_text_px else cfg.text_contrast
            ratio = contrast(fg, bg)
            if ratio < need:
                out.append((R, f"{slide.name}: {fg} text on {bg} is {ratio:.2f}:1 at {px:g}px (needs {need}:1)"))
        if n.tag == "div" and not n.text():
            fill, ground = _paint(n), _ground(n)
            if fill and ground and contrast(fill, ground) < cfg.mark_contrast:
                out.append((R, f"{slide.name}: a mark in {fill} on {ground} is {contrast(fill, ground):.2f}:1 "
                               f"(needs {cfg.mark_contrast}:1)"))
            edge = _border_colour(n.style)
            if edge and ground and contrast(edge, ground) < cfg.mark_contrast:
                out.append((R, f"{slide.name}: an outline in {edge} on {ground} is {contrast(edge, ground):.2f}:1 "
                               f"(needs {cfg.mark_contrast}:1)"))
    return out


def colour_problems(slide, cfg):
    """Membership of the palette, in hex only, read from the style values themselves. A colour
    function or a CSS name carries no hex, so a hex scan alone cannot see it: any word in a colour
    property but `solid` is refused, in any case. Scanning style values rather than the raw file
    also keeps `&#160;` from being read as a colour."""
    R = "admiral.palette"
    out = []
    for n in slide.nodes:
        for prop, value in n.style.items():
            out += [(R, f"{slide.name}: colour {h} is not in the palette")
                    for h in re.findall(r"#[0-9a-fA-F]{3,8}\b", value) if parse_colour(h) not in cfg.allowed_colours]
            if prop in ("color", "background", "border") or "color" in prop:
                out += [(R, f"{slide.name}: {prop}:{value} - admiral slides name colours in hex only")
                        for word in re.findall(r"(?<![#\w])[A-Za-z][A-Za-z-]*", value)
                        if word.lower() not in ("solid", "px")][:1]
    return out


# ------------------------------------------------------------------------------------------------
# Does it fit?
# ------------------------------------------------------------------------------------------------
#
# Nothing scrolls on the Slides runtime. An over-full slide squeezes its boxes and each squeezed
# text box shrinks its own text, down to `shrink_floor` (60%) of its size (styles.md, "Rendering
# semantics"). So a slide that overflows does not spill where someone would see it: it quietly sets
# a 68 px statement at about 41 px, under the 60 px floor this format exists to hold. The estimate
# below catches that before the build writes the slide.
#
# Widths come from the face itself when it has been measured (`pitch calibrate glyphs` writes the
# table, in thousandths of an em, from canvas measureText at 1000 px in Chrome). The Slides type's
# own figure, 0.6 em a character, is its check for "the longest word fits"; for wrapping it
# overstates bold lower case by about 10% on the face first measured. Any face not measured falls
# back to it, which over-wraps: safe, never the reverse. Text wraps only at spaces (format.md).
#
# Summed glyph widths ignore kerning. Against Chrome's kerned widths for 400 strings of prose, the
# sums ran from 0.46% narrow to 1.49% wide (median 0.19% wide), so the estimate is held to a box
# `wrap_margin` (0.5%) narrower than the real one: it may wrap a line Chrome would not, never the
# reverse. Checked on 300 random lines at 60-150 px, weights 400-800, spacing 0 to -5 px: of the
# 273 with no over-long word, 248 broke exactly as Chrome did; the other 25 broke a word early
# somewhere, and 12 of those ran to one line more; none ran to fewer lines than Chrome's.


def _family(node):
    fam = node.inherited("font-family") or ""
    return fam.split(",")[0].strip().strip("'\"")


def _weight(node):
    own = node.style.get("font-weight")
    if own is None and node.tag in ("h1", "h2", "h3"):
        return TAG_DEFAULTS[node.tag][1]
    w = own or node.inherited("font-weight") or "400"
    return 700 if w == "bold" else 400 if w == "normal" else int(w)


def text_px(text, px, cfg, weight=400, family="", letter_spacing=0.0):
    """The advance width of a run of text, in px, as the browser would set it on one line."""
    table = None
    if cfg.glyphs and family == cfg.face_family:
        table = cfg.glyphs[min(cfg.glyphs, key=lambda w: abs(w - weight))]
    fallback = cfg.fallback_em * 1000
    total = 0.0
    for ch in text.replace(NBSP, " "):
        em = table.get(ch, fallback) if table else fallback
        total += em / 1000 * px + letter_spacing
    return total


def wrap(text, width, px, cfg, weight=400, family="", letter_spacing=0.0):
    """Greedy wrap at ordinary spaces: (the lines, the widest unbreakable run in px)."""
    width = width * (1 - cfg.wrap_margin)
    space = text_px(" ", px, cfg, weight, family, letter_spacing)
    lines, used, widest = [[]], 0.0, 0.0
    for w in re.split(r"[ \t\r\n\f]+", text.strip()):
        if not w:
            continue
        ww = text_px(w, px, cfg, weight, family, letter_spacing)
        widest = max(widest, ww)
        if used and used + space + ww > width + 0.5:
            lines.append([w])
            used = ww
        else:
            lines[-1].append(w)
            used += (space if used else 0) + ww
    return [" ".join(line) for line in lines], widest


def _box(style, key):
    """padding as (top, right, bottom, left)."""
    vals = [(_px(v) or 0) for v in style.get(key, "0").split()]
    vals = (vals * 4)[:4] if len(vals) == 1 else vals
    if len(vals) == 2:
        vals = [vals[0], vals[1], vals[0], vals[1]]
    elif len(vals) == 3:
        vals = [vals[0], vals[1], vals[2], vals[1]]
    return vals


def _line_height(node, px):
    lh = node.style.get("line-height") or (node.inherited("line-height") if node.tag not in TAG_DEFAULTS else None)
    if lh:
        if lh.endswith("px"):
            return _px(lh)
        try:
            return float(lh) * px
        except ValueError:
            pass
    return TAG_DEFAULTS.get(node.tag, TAG_DEFAULTS["p"])[2] * px


class Fit:
    def __init__(self):
        self.blocks = []        # (tag, text, line count, height_px, width_px, [line texts])
        self.problems = []      # (rule id, message)


def _measure(node, avail_w, fit, cfg):
    """Estimated height of a node laid out in avail_w px, for the subset the builder emits:
    text blocks, flex rows and columns of divs, and painted divs of a set height."""
    # A declared width does not shrink to its column in these layouts: it runs past the edge. So a
    # width over the room is a problem, not something to clamp quietly.
    declared = _px(node.style["width"]) if node.style.get("width") else None
    if declared is not None and declared > avail_w + 0.5:
        fit.problems.append(("admiral.fit.width", f"<{node.tag}> is {declared:.0f}px wide in {avail_w:.0f}px of room"))
    if node.tag in TEXT_TAGS:
        px = font_px(node)
        pad = _box(node.style, "padding")
        width = min(declared, avail_w) if declared is not None else avail_w
        inner = width - pad[1] - pad[3]
        ls = _px(node.style.get("letter-spacing") or node.inherited("letter-spacing") or "0", px) or 0
        text = node.text()
        lines, widest = wrap(text, inner, px, cfg, _weight(node), _family(node), ls)
        if widest > inner + 0.5:
            fit.problems.append(("admiral.fit.width", f"“{text[:40]}”: a word {widest:.0f}px wide in a "
                                                      f"{inner:.0f}px box breaks mid-word"))
        if len(lines) > cfg.max_lines:
            fit.problems.append(("admiral.fit.lines", f"“{text[:40]}” runs to {len(lines)} lines "
                                                      f"(limit {cfg.max_lines}): shorten it"))
        for line in lines[:-1]:
            last = line.split(" ")[-1].lower()
            if last in cfg.dangling:
                fit.problems.append(("admiral.fit.dangling", f"“{line}” ends a line on “{last}”: join it to "
                                                             "the next word with a no-break space"))
        h = len(lines) * _line_height(node, px) + pad[0] + pad[2]
        fit.blocks.append((node.tag, text, len(lines), h, inner, lines))
        return h
    kids = [c for c in node.children if isinstance(c, Node) and c.tag != "aside"
            and c.style.get("position") != "absolute"]
    pad = _box(node.style, "padding")
    gap = _px(node.style.get("gap", "0")) or 0
    inner_w = (_px(node.style["width"]) if node.style.get("width") else avail_w) - pad[1] - pad[3]
    row = node.style.get("display") == "flex" and node.style.get("flex-direction", "row").startswith("row")
    if row:
        fixed = [(_px(k.style["width"]) if k.style.get("width") and k.tag not in TEXT_TAGS else None)
                 for k in kids]
        declared = sum(_px(k.style["width"]) for k in kids if k.style.get("width")) + gap * max(len(kids) - 1, 0)
        if declared > inner_w + 0.5:
            fit.problems.append(("admiral.fit.width", f"a row of {declared:.0f}px declared width in "
                                                      f"{inner_w:.0f}px of room"))
        free = inner_w - sum(f for f in fixed if f) - gap * max(len(kids) - 1, 0)
        share = free / max(sum(1 for f in fixed if f is None), 1)
        heights = [_measure(k, f if f else share, fit, cfg) for k, f in zip(kids, fixed)]
        content = max(heights or [0])
    else:
        heights = [_measure(k, inner_w, fit, cfg) for k in kids]
        content = sum(heights) + gap * max(len(kids) - 1, 0)
    # A set height is a floor, not a lid: content taller than it still takes the room.
    return max(content + pad[0] + pad[2], _px(node.style.get("height", "0")) or 0)


def fit(slide, cfg):
    """(Fit, column height, room, heading top): the estimate of how the slide's column lays out."""
    f = Fit()
    sec = slide.section
    pad = _box(sec.style, "padding")
    room = cfg.canvas_h - pad[0] - pad[2]
    column = _measure(sec, cfg.canvas_w, f, cfg) - pad[0] - pad[2]
    centred = sec.style.get("justify-content") == "center"
    top = pad[0] + (max(room - column, 0) / 2 if centred else 0)
    if column > room + 0.5:
        shrink = round((1 - cfg.shrink_floor) * 100)
        f.problems.append(("admiral.fit.overfull", f"the column is {column:.0f}px in {room:.0f}px of room: the "
                                                   f"runtime would shrink its text by up to {shrink}%, under the "
                                                   f"{cfg.min_font_px}px floor - cut or split the slide"))
    return f, column, room, top


def geometry_problems(slide, cfg):
    f, *_ = fit(slide, cfg)
    return [(rule, f"{slide.name}: {msg}") for rule, msg in f.problems]


def problems(slide, key, cfg):
    """Every rule at once: the builder refuses on any of these, and the checker reports each with
    its rule id. Markup first, and alone when it fails: every later check reads the slide through
    the grammar, and on markup outside it would measure the wrong thing, or crash on a size in rem,
    rather than name the rule."""
    markup = markup_problems(slide, cfg)
    if markup:
        return markup
    return (density_problems(slide, cfg) + type_problems(slide, cfg) + colour_problems(slide, cfg)
            + contrast_problems(slide, cfg) + geometry_problems(slide, cfg) + title_problems(slide, key, cfg))


# ================================================================================================
# The checker
# ================================================================================================

# Every rule id a finding can carry. The method's section 5 explains each; the suite
# (tests/pitch.sh) builds one failing root per id and fails when an id has none.
RULES = (
    "admiral.words", "admiral.statements", "admiral.markup", "admiral.runtime-limits",
    "admiral.type-floor", "admiral.palette", "admiral.contrast", "admiral.fit.overfull",
    "admiral.fit.lines", "admiral.fit.dangling", "admiral.fit.width", "admiral.title",
    "admiral.slide-count", "admiral.invented-number", "admiral.exemption-stale",
    "deck.index", "deck.generator-drift", "deck.page-number", "deck.running-caption", "deck.external",
    "captain.type-floor", "captain.allowlist", "single.external", "single.authoring-marker",
    "claims.must-appear", "claims.retired", "claims.table", "root.orphan", "root.vacuous",
)

# ------------------------------------------------------------------------------------------------
# Finding the renders
# ------------------------------------------------------------------------------------------------


def documents(root, cfg, only=None):
    """The documents under root; `only`, a stem, narrows them to one (`pitch check <doc>`)."""
    return [md for md in sorted(Path(root).glob(cfg.naming["documents_glob"])) if only is None or md.stem == only]


def folder_decks(root, cfg, only=None):
    """(document, suffix, project dir) for every folder deck, admiral or not."""
    out = []
    for md in documents(root, cfg, only):
        for suffix in cfg.naming["folder_deck_suffixes"]:
            project = md.with_name(md.stem + suffix) / "project"
            if (project / "deck.json").exists() or (project / "slides").is_dir():
                out.append((md, suffix, project))
    return out


def memos(root, cfg, only=None):
    return [(md, md.with_name(md.stem + cfg.naming["memo_suffix"])) for md in documents(root, cfg, only)
            if md.with_name(md.stem + cfg.naming["memo_suffix"]).exists()]


def single_decks(root, cfg, only=None):
    return [(md, md.with_name(md.stem + cfg.naming["single_deck_suffix"])) for md in documents(root, cfg, only)
            if md.with_name(md.stem + cfg.naming["single_deck_suffix"]).exists()]


def renders(root, cfg, only=None):
    """(document, render path, kind) for every render; kind is admiral, folder, memo or single."""
    out = [(md, p, "admiral" if s == cfg.naming["admiral_suffix"] else "folder")
           for md, s, p in folder_decks(root, cfg, only)]
    out += [(md, p, "memo") for md, p in memos(root, cfg, only)]
    out += [(md, p, "single") for md, p in single_decks(root, cfg, only)]
    return out


def slide_files(project):
    return sorted((project / "slides").glob("*.html"))


# ------------------------------------------------------------------------------------------------
# Normalised text, for the claim checks
# ------------------------------------------------------------------------------------------------

def normalise(text):
    """Compare meaning, not markup: drop tags and backticks, collapse space, lower-case.

    The tag pattern is deliberately bounded. A greedy `<[^>]+>` eats whole sentences in Markdown
    that contains bare comparison operators (`x > 0.5`, `n < 50`); that once hid two phrases from
    this check. A single-file deck writes punctuation as JavaScript escapes (\\u2014), the document
    as the characters: both are decoded, or a phrase containing one never matches - a silent pass.
    """
    text = re.sub(r"</?[a-zA-Z][^<>]{0,120}>|<!--[^<>]{0,120}-->", " ", text)
    text = text.replace("`", "").replace("**", "").replace("*", "")
    text = re.sub(r"\\u([0-9a-fA-F]{4})", lambda m: chr(int(m[1], 16)), text)
    text = text.replace("’", "'").replace(" ", " ")
    return re.sub(r"\s+", " ", text).lower()


def render_text(path):
    if path.is_dir():
        return "\n".join(p.read_text(encoding="utf-8") for p in slide_files(path))
    return path.read_text(encoding="utf-8")


# ------------------------------------------------------------------------------------------------
# The admiral deck
# ------------------------------------------------------------------------------------------------

def admiral_slides(project, cfg):
    stem = stem_of(project.parent, cfg)
    return [(f"{stem}/{p.stem}", Slide(p.read_text(encoding="utf-8"), p.name)) for p in slide_files(project)]


def check_admiral(md, project, cfg):
    out = []
    slides = admiral_slides(project, cfg)
    if len(slides) > cfg.max_slides:
        out.append(("admiral.slide-count", f"{project.parent.name}: {len(slides)} slides (limit {cfg.max_slides})"))
    for key, s in slides:
        out += problems(s, key, cfg)
    # Every figure on a slide, and in its presenter note, appears in the document. A twenty-word
    # slide is where a wrong number hides best: there is no sentence around it to contradict it,
    # and the pinned phrases cover only a handful of claims. The note counts because a figure the
    # speaker is handed is quoted aloud.
    doc_nums = numbers(md.read_text(encoding="utf-8"), with_bare=True)
    out += [("admiral.invented-number", f"{s.name}: {n} appears nowhere in {md.name}")
            for _, s in slides for n in sorted(s.figures - doc_nums)]
    out += check_builder(project.parent, cfg)
    return out


def check_exemptions(root, cfg, only=None):
    """An exemption outliving its slide would wave through whatever later takes the id."""
    slides = {key for _, project in admiral_decks(root, cfg, only) for key, _ in admiral_slides(project, cfg)}
    exempt = {k: why for k, why in cfg.headline_exempt.items() if only is None or k.startswith(only + "/")}
    out = [("admiral.exemption-stale", f"headline_exempt names a slide that does not exist: {k}")
           for k in sorted(set(exempt) - slides)]
    out += [("admiral.exemption-stale", f"headline_exempt entry without a reason: {k}")
            for k, why in sorted(exempt.items()) if len(why.split()) < 4]
    return out


def check_builder(deck_dir, cfg):
    """The words live once, in the content file. A figure corrected by hand in a slide file passes
    every other check and is silently reverted by the next build: a render corrected without its
    source, the stale-render trap with its two ends swapped. The builder's --check answers it."""
    content = deck_dir / cfg.naming["content_file"]
    if not content.exists():
        if cfg.builder["require_content_file"]:
            return [("deck.generator-drift", f"{deck_dir.name}: no {content.name}, so nothing generates its slides")]
        return []
    out = []
    # A subprocess per deck, as the export ran it: the build under each interpreter named, and the
    # checker's own process never imports a second copy of these rules.
    builder = HERE / "pitch"
    for py in [sys.executable] + [p for p in cfg.builder["extra_interpreters"] if Path(p).exists()]:
        args = [py, "-I", str(builder), "build", str(deck_dir)]
        if cfg.base_dir:
            args += ["--config", str(_config_path(cfg))]
        run = subprocess.run(args + ["--check"], capture_output=True, text=True)
        if run.returncode:
            out.append(("deck.generator-drift", f"{deck_dir.name} under {py}: "
                                                f"{(run.stdout + run.stderr).strip()[:600]}"))
    return out


def _config_path(cfg):
    return getattr(cfg, "path", None) or cfg.base_dir / CONFIG_NAME


# ------------------------------------------------------------------------------------------------
# Every folder deck: the index, the furniture, nothing reaching outside
# ------------------------------------------------------------------------------------------------

# What makes a bare number a page number is not the number - decks are full of legitimate ones, a
# 96 px headline figure among them - but the furniture around it: it sits in a corner, or it is
# set in small print. So the pattern matches an element with its style, and only flags one that
# is positioned absolutely or set below the caption floor. Any tag, either quoting style, and the
# element's text with nested markup removed: ten near-identical page numbers passed a first
# version (`11 / 14`, `11.`, a `<div>` with no inline style, a single-quoted style, the digits
# wrapped in a `<span>`, `position:fixed`).
ELEMENT = re.compile(
    r"<(?P<tag>[a-zA-Z][\w-]*)\b(?P<attrs>[^>]*)>(?P<text>(?:(?!</?(?P=tag)\b)[\s\S]){0,400}?)</(?P=tag)>"
)
STYLE = re.compile(r"style\s*=\s*(\"[^\"]*\"|'[^']*')", re.I)
# A page number as a reader meets it: 11, 11., 11 / 14, 11 of 14, p 11, page 11.
PAGE_NUMBER = re.compile(r"^(?:p\.?|page)?\s*\d{1,3}\s*(?:[./]|of)?\s*\d{0,3}\s*[.)]?$", re.I)

# Network-capable constructs with no business in a deck. The URL scan is the real guard; these
# catch the call even when the URL is built at run time.
NETWORK_APIS = re.compile(
    r"\bfetch\s*\(|XMLHttpRequest|WebSocket|EventSource|sendBeacon|importScripts|@import|\bimport\s*\("
)
# Any `scheme://` or a protocol-relative `//host`. A JS comment is `// text`, with a space, and
# does not match; an unspaced `//comment` would, and should be respelled.
EXTERNAL_URL = re.compile(r"(?i)\b[a-z][a-z0-9+.-]*://|(?<![:/])//(?=[\w.-])")


def _style_of(attrs):
    m = STYLE.search(attrs)
    return (m.group(1)[1:-1] if m else "").replace(" ", "")


def _furniture(style, cfg):
    """Corner-anchored, or small print: the two ways a caption hides on a slide."""
    if "position:absolute" in style or "position:fixed" in style:
        return True
    sizes = [float(px) for px in re.findall(r"font-size:(\d+(?:\.\d+)?)px", style)]
    return any(px < cfg.furniture["caption_floor_px"] for px in sizes)


def furniture_texts(slide_text, cfg):
    """(text, is_furniture) for every element of a slide, notes excluded, markup stripped."""
    body = re.sub(r"<aside\b.*?</aside>", " ", slide_text, flags=re.S | re.I)
    out = []
    # Every element, nested ones included: the scan restarts one character after each match, not
    # after its end. With finditer, a <section> short enough to match whole (under 400 characters)
    # swallowed the page number inside it, and the check passed a numbered slide.
    pos = 0
    while True:
        m = ELEMENT.search(body, pos)
        if not m:
            break
        pos = m.start() + 1
        text = re.sub(r"\s+", " ", strip_tags(m.group("text"))).strip()
        if text:
            out.append((text, _furniture(_style_of(m.group("attrs")), cfg)))
    return out


def check_folder_deck(project, cfg):
    out, label = [], project.parent.name
    index_path = project / "deck.json"
    if not index_path.exists():
        return [("deck.index", f"{label}: slides/ without a deck.json, so no check reads it as a deck")]
    index = json.loads(index_path.read_text(encoding="utf-8"))
    files = {p.stem for p in slide_files(project)}
    if index.get("v") != cfg.naming["deck_index_version"] or not index.get("order"):
        out.append(("deck.index", f"{label}: deck.json needs v {cfg.naming['deck_index_version']} and a non-empty order"))
    order = set(index.get("order") or [])
    if order != files:
        out.append(("deck.index", f"{label}: order and slide files differ: order-only {sorted(order - files)}, "
                                  f"file-only {sorted(files - order)}"))
    # A section pointing at a slide that no longer exists starts the outline nowhere, and comparing
    # only `order` with the file names cannot see it.
    starts = {s.get("start") for s in (index.get("sections") or {}).values()}
    if not starts <= order:
        out.append(("deck.index", f"{label}: sections start at slides the deck does not have: {sorted(starts - order)}"))
    # A face is the one place a deck may name a host: Google Fonts by `href`, or an uploaded or
    # installed file by `src`.
    for key, face in (index.get("faces") or {}).items():
        href, src = face.get("href", ""), face.get("src", "")
        if href and not href.startswith("https://fonts.googleapis.com/css2?"):
            out.append(("deck.external", f"{label}: face {key!r} loads from {href!r}; only a Google Fonts css2 link"))
        if src and not src.startswith(("/_blob/", "project/ds/")):
            out.append(("deck.external", f"{label}: face {key!r} has src {src!r}; only an uploaded asset or an "
                                         "installed system file"))
    seen = {}
    for p in slide_files(project):
        text = p.read_text(encoding="utf-8")
        if text.count("<section ") != 1 or f'<section id="{p.stem}"' not in text:
            out.append(("deck.index", f"{label}/slides/{p.name} must hold exactly one <section id=\"{p.stem}\">"))
        # `/_blob/<id>` (an uploaded asset, served by the deck's own host) is root-relative and passes.
        urls = [m.group(0) for m in EXTERNAL_URL.finditer(text)] + re.findall(r"data:[a-z]+/", text)
        apis = [m.group(0) for m in NETWORK_APIS.finditer(text)]
        if urls or apis or "<script" in text:
            out.append(("deck.external", f"{label}/slides/{p.name} reaches outside the deck: URLs {urls}, APIs {apis}"))
        texts = furniture_texts(text, cfg)
        numbered = [t for t, furn in texts if furn and PAGE_NUMBER.fullmatch(t)]
        if numbered:
            out.append(("deck.page-number", f"{label}/slides/{p.name} carries what reads as a page number: {numbered}"))
        for t, furn in texts:
            if furn and len(t) <= cfg.furniture["caption_max_chars"]:
                seen.setdefault(t, set()).add(p.name)
    # A caption is what repeats, so the rule is structural rather than keyed to a brand word: a
    # first version matched one literal spelling and ten others stayed green. Any short line of
    # small or corner-anchored text on three or more slides of one deck is running furniture
    # whatever it says; a title slide's own line stands once and is content.
    for t, where in sorted(seen.items()):
        if len(where) >= cfg.furniture["caption_min_slides"]:
            out.append(("deck.running-caption", f"{label}: {t!r} repeats on {sorted(where)}"))
    return out


# ------------------------------------------------------------------------------------------------
# Captain renders: the memo page and the single-file deck
# ------------------------------------------------------------------------------------------------

# Read rather than spoken, so a captain render keeps its tables and its density, but not type
# nobody can read. While the rule was only a note, an 11 px declaration passed everything.
MEMO_LOAD = re.compile(r'<(?:script|link|img|iframe|video|audio|source)\b[^>]*?\b(?:src|href)="([^"]+)"', re.I)


def captain_floor(path, cfg):
    floor = cfg.captain["min_font_px"]
    small = []
    for value in re.findall(r"font-size:\s*([^;}\"']+)", path.read_text(encoding="utf-8")):
        value = value.strip()
        m = re.fullmatch(r"(\d+(?:\.\d+)?)px", value)
        if m and float(m.group(1)) < floor:
            small.append(value)
            continue
        # `clamp(min, preferred, max)` sets the floor with its first argument.
        c = re.match(r"clamp\(\s*(\d+(?:\.\d+)?)px", value)
        if c and float(c.group(1)) < floor:
            small.append(value)
        # An em or rem size is relative to a body size this check cannot see: refuse it, so the
        # floor cannot be dodged by changing units (`code { font-size: .9em }` was how it was).
        elif re.fullmatch(r"\.?\d*(?:\.\d+)?r?em", value):
            small.append(f"{value} (relative - size it in px)")
    return [("captain.type-floor", f"{path.name} sets type below the {floor}px floor: {small}")] if small else []


def check_memo(path, cfg):
    out = captain_floor(path, cfg)
    text = path.read_text(encoding="utf-8")
    hosts = tuple(cfg.captain["allowed_load_hosts"])
    bad = [u for u in MEMO_LOAD.findall(text)
           if u.startswith(("http://", "https://", "//", "data:")) and not u.startswith(hosts)]
    apis = [m.group(0) for m in NETWORK_APIS.finditer(text)]
    if bad or apis:
        out.append(("captain.allowlist", f"{path.name} loads from outside the allowlist: {bad}, APIs {apis}"))
    return out


def split_js(src):
    """Split JavaScript source into (template-literal texts, quoted-string contents), or None when
    the scan cannot pair the script's backticks, quotes and braces.

    Slide text reaches the reader from backtick templates and from quoted strings in the data.
    Naive `` `[^`]*` `` pairing breaks on nesting - `${rows.map(r=>`<tr>…</tr>`)}` - and then hands
    real template text to the data-string rules, which say the opposite about markers. So scan
    properly: a template's text excludes its `${…}` expressions, the expressions are scanned as
    code, and `//` and `/* */` comments in code are skipped. Regex literals are not understood.
    """
    templates, strings = [], []
    stack = [{"in": "code", "depth": 0}]
    i, n = 0, len(src)
    while i < n:
        top = stack[-1]
        if top["in"] == "template":
            if src[i] == "\\":
                top["buf"].append(src[i:i + 2])
                i += 2
            elif src[i] == "`":
                templates.append("".join(top["buf"]))
                stack.pop()
                i += 1
            elif src.startswith("${", i):
                stack.append({"in": "code", "depth": 0})
                i += 2
            else:
                top["buf"].append(src[i])
                i += 1
        elif src.startswith("//", i):
            end = src.find("\n", i)
            i = n if end < 0 else end
        elif src.startswith("/*", i):
            end = src.find("*/", i + 2)
            i = n if end < 0 else end + 2
        elif src[i] in "\"'":
            quote, j = src[i], i + 1
            while j < n and src[j] != quote:
                j += 2 if src[j] == "\\" else 1
            strings.append(src[i + 1:j])
            i = j + 1
        elif src[i] == "`":
            stack.append({"in": "template", "buf": []})
            i += 1
        elif src[i] == "{":
            top["depth"] += 1
            i += 1
        elif src[i] == "}":
            if top["depth"] == 0 and len(stack) > 1:
                stack.pop()  # the `${…}` ends; back into the template that opened it
            else:
                top["depth"] -= 1
            i += 1
        else:
            i += 1
    if len(stack) != 1 or stack[0]["depth"] != 0:
        return None
    return templates, strings


# A `//` comment as the first thing on a line, or set off by whitespace on both sides. The second
# form leaves out the `//` of a URL (`https://x`), which the external-request check owns.
SLASH_COMMENT = re.compile(r"(?m)^\s*//|\s//\s")


def check_single_deck(path, cfg):
    """A single-file deck: its slides are template literals assigned through innerHTML. A `//`
    comment is a real comment in the surrounding JavaScript but plain text inside a template
    literal, so a note placed there renders on the slide; an HTML comment is invisible there. In a
    data string (inserted as text) an HTML comment is printed verbatim, so that leaks too."""
    out = captain_floor(path, cfg)
    text = path.read_text(encoding="utf-8")
    urls = [text[m.start():m.start() + 60] for m in EXTERNAL_URL.finditer(text)]
    apis = [m.group(0) for m in NETWORK_APIS.finditer(text)]
    if urls or apis:
        out.append(("single.external", f"{path.name} would reach outside the machine: URLs {urls}, APIs {apis}"))
    scripts = re.findall(r"<script>(.*?)</script>", text, re.S)
    if not scripts:
        return out + [("single.authoring-marker", f"{path.name} has no inline <script>: its text cannot be checked")]
    split = split_js(scripts[-1])
    if split is None:
        return out + [("single.authoring-marker", f"{path.name}: could not pair the script's backticks, quotes "
                                                  "and braces - extend split_js rather than loosen the check")]
    templates, strings = split
    if not templates or not strings:
        return out + [("single.authoring-marker", f"{path.name}: no templates or no data strings - the scan is vacuous")]
    for kind, texts in (("a slide template", templates), ("a data string", strings)):
        for t in texts:
            for m in SLASH_COMMENT.finditer(t):
                out.append(("single.authoring-marker", f"{path.name}: '//' inside {kind}: "
                                                       f"...{t[max(0, m.start() - 40):m.start() + 20]!r}"))
    for t in strings:
        if "<!--" in t:
            out.append(("single.authoring-marker", f"{path.name}: an HTML comment inside a data string prints verbatim"))
    return out


# ------------------------------------------------------------------------------------------------
# Claims: every render carries the pinned phrases, no retired claim comes back
# ------------------------------------------------------------------------------------------------

def check_claims(root, cfg, only=None):
    out = []
    must, adm = cfg.claims["must_appear"], cfg.claims["admiral_must_appear"]
    if only is not None:
        must, adm = ({s: v for s, v in t.items() if s == only} for t in (must, adm))
    by_stem = {}
    found = renders(root, cfg, only)
    for md, path, kind in found:
        by_stem.setdefault(md.stem, []).append(kind)
        table = adm if kind == "admiral" else must
        name = "admiral_must_appear" if kind == "admiral" else "must_appear"
        phrases = table.get(md.stem)
        if not phrases:
            if cfg.claims["require_pins"]:
                out.append(("claims.table", f"{path.name}: no {name} entry for {md.stem}, so nothing is compared"))
            continue
        doc_text, ren_text = normalise(md.read_text(encoding="utf-8")), normalise(render_text(path))
        for phrase in phrases:
            needle = normalise(phrase)
            missing = [w for w, t in (("document", doc_text), (path.name, ren_text)) if needle not in t]
            if missing:
                out.append(("claims.must-appear", f"{phrase!r} missing from: {', '.join(missing)}"))
    # A table entry whose renders are gone is a guard nothing reads.
    full = {s for s, kinds in by_stem.items() if any(k != "admiral" for k in kinds)}
    admiral = {s for s, kinds in by_stem.items() if "admiral" in kinds}
    out += [("claims.table", f"must_appear names {s}, which has no non-admiral render") for s in sorted(set(must) - full)]
    out += [("claims.table", f"admiral_must_appear names {s}, which has no admiral render")
            for s in sorted(set(adm) - admiral)]
    files = sorted({p for pattern in cfg.claims["retired_scan"] for p in Path(root).glob(pattern) if p.is_file()})
    if only is not None:
        # One document's files: itself and its renders, a deck folder whole.
        owned = {p.relative_to(root).parts[0] for p in documents(root, cfg, only)}
        owned |= {p.relative_to(root).parts[0] for _, p, _ in found}
        files = [p for p in files if p.relative_to(root).parts[0] in owned]
    for path in files:
        text = normalise(render_text(path) if path.is_dir() else path.read_text(encoding="utf-8"))
        for claim, why in cfg.claims["retired"]:
            if normalise(claim) in text:
                out.append(("claims.retired", f"{path.relative_to(root)}: {claim!r} - {why}"))
    return out


# ------------------------------------------------------------------------------------------------
# The root: nothing unpaired, something to check
# ------------------------------------------------------------------------------------------------

def check_root(root, cfg, only=None):
    """Every finding under root, as (rule id, message). `only`, a document's stem, narrows the check
    to that document and its renders; another document's orphans belong to the root's own check, and
    this document's own deck folder with no project/ is still an orphan here."""
    root = Path(root).resolve()
    out = []
    found = renders(root, cfg, only)
    if not found:
        what = f"{only} has no render" if only is not None else "no document has any render"
        out.append(("root.vacuous", f"{root}: {what}, so every check would pass by finding nothing"))
    if only is not None:
        # The document's own deck folders still count: one with no project/ is no render, and
        # would otherwise pass this check by never being seen.
        seen_dirs = {p.parent for _, p, k in found if k in ("admiral", "folder")}
        out += [("root.orphan", f"{d.name}: a deck folder no check sees (no project/)")
                for d in (root / (only + s) for s in cfg.naming["folder_deck_suffixes"])
                if d.is_dir() and d not in seen_dirs]
        return out + _check_renders(found, cfg) + check_exemptions(root, cfg, only) + check_claims(root, cfg, only)
    seen_files = {p for _, p, k in found if k in ("memo", "single")}
    orphans = [h.name for h in root.glob("*.html") if h not in seen_files]
    out += [("root.orphan", f"{n}: an HTML render with no document of its name, so nothing checks it") for n in orphans]
    seen_dirs = {p.parent for _, p, k in found if k in ("admiral", "folder")}
    suffixes = tuple(cfg.naming["folder_deck_suffixes"])
    out += [("root.orphan", f"{d.name}: a deck folder no check sees (no document, or no project/)")
            for d in sorted(root.iterdir()) if d.is_dir() and d.name.endswith(suffixes) and d not in seen_dirs]
    out += _check_renders(found, cfg)
    out += check_exemptions(root, cfg)
    out += check_claims(root, cfg)
    return out


def _check_renders(found, cfg):
    out = []
    for md, path, kind in found:
        if kind in ("admiral", "folder"):
            out += check_folder_deck(path, cfg)
        if kind == "admiral":
            out += check_admiral(md, path, cfg)
        elif kind == "memo":
            out += check_memo(path, cfg)
        elif kind == "single":
            out += check_single_deck(path, cfg)
    return out


# ================================================================================================
# The builder
# ================================================================================================
#
# Why a builder and not hand-written slides: the commonest failure of a document with renders is a
# document corrected without its render, and its cause is that a deck duplicates prose by hand. Here
# the words live once, in the deck's content file (`slides.json` by default, in
# `<stem>-admiral-deck/`), and the layout is a few functions. The content file is a JSON list, one
# object per slide, in order:
#
#     {"id": "money", "headline": "The budget is enough",
#      "statements": ["$18K for the pilot", "..."],
#      "note": "what the speaker says; every number in it must be in the document",
#      "graphic": {"kind": "track", "values": [140, 0], "of": 420},      optional
#      "centred": true}                                                   optional
#
# The first slide is the cover. `centred` defaults to true for the first and the last slide (they
# are statements), false for the rest, which hang from the top margin so the title does not hop
# between neighbouring slides. A `graphic` has one entry per statement: `track` fills an outlined
# bar in proportion to value/of (0 reads as an empty track, not a missing bar); `weeks` draws `of`
# slots and fills the span [first, last] given for each statement. Write NBSP ("a small") in a
# headline to keep the article with its noun.

# The markup stays inside the Slides runtime's subset: a statement is a `p`, its dot or its graphic
# painted `div`s. A styled `span` would be dropped on read (the runtime allows `span` for colour
# only, not size), and the slide would silently lose its text.

class Look:
    def __init__(self, cfg):
        L = cfg.layout
        self.cfg = cfg
        self.ink, self.muted, self.accent = L["ink"], L["muted"], L["accent"]
        self.paper, self.raised = L["paper"], L["raised"]
        self.font = (f"'{cfg.face_family}', {cfg.face_stack}" if cfg.face_family else cfg.face_stack)
        self.head_px, self.cover_head_px = L["head_px"], L["cover_head_px"]
        self.stmt_px, self.lone_stmt_px, self.cover_stmt_px = (L["statement_px"], L["lone_statement_px"],
                                                               L["cover_statement_px"])
        self.leading, self.text_w, self.head_w = L["leading"], L["text_w"], L["head_w"]
        self.head_ls, self.stmt_ls = L["head_letter_spacing_px"], L["statement_letter_spacing_px"]
        self.head_gap, self.row_gap, self.transition = L["head_gap_px"], L["row_gap_px"], L["transition"]

    def statement(self, text, px, cover=False):
        if cover:
            return f'<p style="font-size:{px}px;line-height:1.3;color:{self.muted};width:{self.text_w}px">{text}</p>'
        return (f'<p style="font-size:{px}px;line-height:{self.leading};font-weight:700;'
                f'letter-spacing:{self.stmt_ls}px;width:{self.text_w}px">{text}</p>')

    def bullet_row(self, text, px):
        # The dot sits in a box one line tall, so it centres on the first line, not on a wrapped pair.
        line = round(px * self.leading)
        return ('<div style="display:flex;gap:40px;align-items:start">'
                f'<div style="flex:none;width:28px;height:{line}px;display:flex;align-items:center">'
                f'<div style="flex:none;width:28px;height:28px;border-radius:50%;background:{self.accent}"></div></div>'
                f'{self.statement(text, px)}</div>')

    def track(self, value, of):
        border = 3
        fill = round((self.text_w - 2 * border) * value / of)
        bar = f'<div style="flex:none;width:{fill}px;background:{self.accent}"></div>' if fill else ""
        return (f'<div style="display:flex;width:{self.text_w}px;height:32px;border:{border}px solid {self.muted};'
                f'border-radius:16px;overflow:hidden">{bar}</div>')

    def weeks(self, span, of):
        gap = 12
        slot = (self.text_w - gap * (of - 1)) // of
        cells = []
        for w in range(1, of + 1):
            paint = f"background:{self.accent}" if span[0] <= w <= span[1] else f"border:3px solid {self.muted}"
            cells.append(f'<div style="flex:none;width:{slot}px;height:32px;border-radius:8px;{paint}"></div>')
        return f'<div style="display:flex;gap:{gap}px">' + "".join(cells) + "</div>"

    def evidence_row(self, text, px, graphic, i):
        kind, items, of = graphic["kind"], graphic["values"], graphic["of"]
        if kind not in ("track", "weeks"):
            sys.exit(f"graphic kind {kind!r}: the builder draws 'track' and 'weeks'")
        drawn = self.track(items[i], of) if kind == "track" else self.weeks(items[i], of)
        return (f'<div style="display:flex;flex-direction:column;gap:20px">'
                f'{self.statement(text, px)}{drawn}</div>')

    def slide_html(self, s, index, count):
        sid, headline, statements, note = s["id"], s["headline"], s["statements"], s.get("note", "")
        graphic = s.get("graphic")
        cover = index == 0
        bg = self.paper if index % 2 else self.raised
        if cover:
            head_px = self.cover_head_px
            body = "\n".join(self.statement(t, self.cover_stmt_px, cover=True) for t in statements)
        else:
            head_px = self.head_px
            # One statement gets the room of three: the scale is the point of the format.
            px = self.stmt_px if len(statements) > 1 else self.lone_stmt_px
            if graphic and len(graphic["values"]) != len(statements):
                sys.exit(f"{sid}: {len(graphic['values'])} graphic rows for {len(statements)} statements")
            rows = [self.evidence_row(t, px, graphic, i) if graphic else self.bullet_row(t, px)
                    for i, t in enumerate(statements)]
            body = (f'<div style="display:flex;flex-direction:column;gap:{self.row_gap}px">\n'
                    + "\n".join(rows) + "\n</div>")
        centred = s.get("centred", index in (0, count - 1))
        centre = "justify-content:center;" if centred else ""
        return (
            f'<section id="{sid}" data-transition="{self.transition}" style="background:{bg};color:{self.ink};'
            f'font-family:{self.font};padding:{self.cfg.margin}px;display:flex;flex-direction:column;'
            f'{centre}gap:{self.head_gap}px">\n'
            f'<h2 style="font-size:{head_px}px;line-height:1.05;letter-spacing:{self.head_ls}px;font-weight:800;'
            f'width:{self.head_w}px">{headline}</h2>\n'
            f"{body}\n"
            f"<aside>{note}</aside>\n"
            "</section>\n"
        )


def build_all(deck_dir, cfg):
    """Every slide, built and checked in memory. Nothing reaches disk until all of them pass.

    An earlier version checked inside the write loop, so a refusal mid-deck left the earlier
    slides rewritten and the later ones stale: a deck half one version and half another, with every check green on
    the mixture.
    """
    content = deck_dir / cfg.naming["content_file"]
    if not content.exists():
        sys.exit(f"no {content.name} in {deck_dir}")
    slides = json.loads(content.read_text(encoding="utf-8"))
    if len(slides) > cfg.max_slides:
        sys.exit(f"{len(slides)} slides, the limit is {cfg.max_slides}")
    look, stem = Look(cfg), stem_of(deck_dir, cfg)
    built, refused = [], []
    for i, s in enumerate(slides):
        html = look.slide_html(s, i, len(slides))
        slide = Slide(html, f"{s['id']}.html")
        refused += [msg for _, msg in problems(slide, f"{stem}/{s['id']}", cfg)]
        _, column, room, _ = fit(slide, cfg)
        built.append((s["id"], html, f"{s['id']} ({len(slide.words)} words, column {column:.0f} of {room:.0f}px)"))
    if refused:
        sys.exit("refused, nothing written:\n  " + "\n  ".join(refused))
    slide_dir = deck_dir / "project" / "slides"
    stale = {p.stem for p in slide_dir.glob("*.html")} - {b[0] for b in built}
    if stale:
        sys.exit(f"slides on disk that {content.name} no longer defines: {sorted(stale)} — delete them")
    return built
