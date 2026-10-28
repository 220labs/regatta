"""pitch's library: the renders' rules, the checker that holds a docs root to them, and the builder
that writes the decks, in one place.

A document has renders: the captain page (`<stem>-memo.html`), read in full; the admiral deck
(`<stem>-admiral-deck/project/`), spoken: about twenty words a slide, at most three statements, no
type under 60 px, a title that states the message; and the commodore deck
(`<stem>-commodore-deck/project/`), sent and read alone: fifty words, six blocks, a 40 px floor, and
links (renders S6). The method (skills/pitch/method.md) gives every number and its source. Two things enforce the format: the builder (`pitch build`) refuses to write a slide that
breaks a rule, and the checker (`pitch check`) refuses one that arrived by any other route. Both are
this file, and neither keeps its own copy of a number: two copies of the rules drifting apart is the
stale-render trap in miniature (the method, section 6).

Everything that differs between adopters is a parameter in `pitch.json` (the config reference, skills/pitch/config.md): the
palette, the face and its measured glyph widths, the limits, the exemptions. The numbers below in
DEFAULTS are the method's own; an adopter overrides them knowingly.

Stdlib only, and Python 3.9, so it runs under a stock macOS `python3`. What the Slides runtime does
(its canvas, its margins, its element and note caps, its shrink-to-fit) is taken from that runtime's
own reference pages (`format.md`, `layout.md`, `styles.md`).

It sits in `bin/` beside `pitch`, not in `lib/`: a module's `lib/` counts as live code (the core's
classes.sh), and nothing runs this from a hook. The first four parts below were four files in the
export this came from (the rules, the checker, the builder, the calibrator); their order and their
comments are kept, so a change there reads as a change here. The fifth, the document (its deck
fence, its generated page, the captain review's shape), is this module's own.
"""
import copy
import datetime
import html
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
    # The sent deck (renders S6): the admiral's rules under `commodore.*` ids, with these limits. Its
    # links are https, each URL also in the document's body or its sidecar.
    "commodore": {
        "max_words": 50,            # DocSend's sent decks (the method, section 1); link text counted
        "max_statements": 6,        # text blocks besides the title: statements, details and links
        "max_lines": 3,
        "min_font_px": 40,          # the caption floor, so no body line reads as furniture
        "max_slides": 12,
        "link_prefixes": ["https://"],  # a link must start with one; narrow it to a host, never widen it
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
        "commodore_suffix": "-commodore-deck",
        "folder_deck_suffixes": ["-deck", "-admiral-deck", "-commodore-deck"],
        "memo_suffix": "-memo.html",
        "single_deck_suffix": "-deck.html",
        "content_file": "slides.json",
        "deck_index_version": 4,
        "sidecar_suffix": ".pitch.json",    # <stem><suffix>: where each render was published
        "deck_fence": "deck",       # the info word of the fence at a document's end holding its slides
    },
    "claims": {
        "must_appear": {},          # "<document stem>": [phrases every render but a deck with its own list (the admiral's, the commodore's) and the document carry]
        "admiral_must_appear": {},  # "<document stem>": [phrases the admiral render and the document carry]
        "commodore_must_appear": {},    # the same for the commodore render
        "retired": [],              # [[phrase, why]]: corrected claims that must not come back anywhere
        "retired_scan": ["**/*.md", "**/*.html"],
        "require_pins": True,       # a render whose stem has no entry is a finding, not a silent pass
    },
    "builder": {"require_content_file": True, "extra_interpreters": []},
    "publish": {                    # how the skill publishes; no check reads these bar asset_host
        "design_system": "",        # a Design System artifact's https URL; it wins over `brand`
        "brand": "",                # the brand doc, relative to the config
        "images": "none",           # the image route: one of IMAGE_ROUTES
        "asset_host": "",           # a host a memo may also load from, when uploads come back absolute
    },
    "memo": {                       # `pitch memo`'s page: light colours from `layout`, these for dark
        "dark": {"ink": "#F2F2F2", "muted": "#B4B4B4", "accent": "#8AB4F8", "paper": "#151515",
                 "raised": "#232323"},
    },
    "layout": {                     # the builder's own look; none of it is a rule
        "ink": "#000000", "muted": "#555555", "accent": "#0055cc", "paper": "#ffffff", "raised": "#f5f5f5",
        "head_px": 104, "cover_head_px": 150, "statement_px": 68, "lone_statement_px": 76,
        "cover_statement_px": 60, "leading": 1.25, "text_w": 1500, "head_w": 1560,
        "head_letter_spacing_px": -5, "statement_letter_spacing_px": -1,
        "head_gap_px": 72, "row_gap_px": 48, "transition": "fade",
        # The commodore's sizes: smaller than the admiral's, never under its 40 px floor.
        "commodore": {"head_px": 88, "cover_head_px": 120, "statement_px": 52, "cover_statement_px": 48,
                      "detail_px": 40, "link_px": 40, "head_letter_spacing_px": -4, "head_gap_px": 56,
                      "row_gap_px": 32},
    },
}


# The routes `publish.images` may name, and an image in a sidecar may record (the skill says how each
# one runs). `none` is the default: the wordmark and drawn figures only.
IMAGE_ROUTES = ("none", "design", "agy", "flow", "imagen")


class ConfigError(ValueError):
    """A config that cannot be read as written: `pitch` exits 2 with the message, never a finding."""


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

    def __init__(self, data=None, base_dir=None, load_glyphs=True):
        d = _merge(DEFAULTS, data or {})
        self.raw, self.base_dir, self.path = d, Path(base_dir) if base_dir else None, None
        self.glyphs_from = None     # the config whose table this one inherits, set by load()
        a, r, f = d["admiral"], d["runtime"], d["face"]
        self.max_words, self.target_words = a["max_words"], a["target_words"]
        self.max_statements, self.max_lines = a["max_statements"], a["max_lines"]
        self.min_font_px, self.max_slides = a["min_font_px"], a["max_slides"]
        self.letter_spacing_px = tuple(a["letter_spacing_px"])
        self.text_contrast, self.large_text_contrast = a["text_contrast"], a["large_text_contrast"]
        self.large_text_px, self.mark_contrast = a["large_text_px"], a["mark_contrast"]
        self.headline_exempt = dict(a["headline_exempt"])
        # The rule ids' prefix and the links switch: commodore_view() changes both, with the limits.
        self.rid, self.links, self.a_slide = "admiral", False, "an admiral slide"
        self.commodore = _commodore(d["commodore"])
        self.dangling = {w.lower() for w in a["dangling_words"]}   # tokens are lower-cased
        self.canvas_w, self.canvas_h = r["canvas_px"]
        self.margin, self.max_note_chars, self.max_elements = r["margin_px"], r["max_note_chars"], r["max_elements"]
        self.shrink_floor = r["shrink_floor"]
        self.allowed_colours = {parse_colour(c) for c in d["palette"]["allowed"]} - {None}
        self.face_family, self.face_stack, self.face_href = f["family"], f["stack"], f["href"]
        self.face_weights, self.fallback_em, self.wrap_margin = f["weights"], f["fallback_em"], f["wrap_margin"]
        # The calibrator reads the config without the table it is about to write: the first
        # measurement has no file yet, and a face just changed has one for the old family.
        self.glyphs = self._load_glyphs(f["glyphs"]) if load_glyphs else {}
        self.captain, self.furniture, self.naming = d["captain"], d["furniture"], d["naming"]
        self.claims, self.builder, self.layout = d["claims"], d["builder"], d["layout"]
        self.memo = d["memo"]
        self.publish = _publish(d["publish"])
        suffix = self.naming.get("sidecar_suffix")
        if not (isinstance(suffix, str) and suffix.endswith(".json") and len(suffix) > len(".json")):
            raise ConfigError(f"naming.sidecar_suffix is {suffix!r}: text ending .json, longer than .json")
        self.verbs = VERBS | {w.lower() for w in a["extra_verbs"]}
        self.finite = AUXILIARIES | _inflected(self.verbs)

    def commodore_view(self):
        """This config as the commodore's rules read it: its own limits and `commodore.*` rule ids,
        `<a href>` admitted in a statement, everything else (palette, face, contrast, runtime) shared."""
        view = copy.copy(self)
        c = self.commodore
        view.max_words, view.max_statements, view.max_lines = c["max_words"], c["max_statements"], c["max_lines"]
        view.min_font_px, view.max_slides = c["min_font_px"], c["max_slides"]
        view.link_prefixes = tuple(c["link_prefixes"])
        view.rid, view.links, view.a_slide = "commodore", True, "a commodore slide"
        return view

    def view(self, kind):
        return self.commodore_view() if kind == "commodore" else self

    @property
    def deck_suffixes(self):
        """Every folder-deck suffix, the commodore's always among them: an adopter's own list, written
        before the commodore existed, would otherwise leave a built commodore deck seen by no check."""
        out = list(self.naming["folder_deck_suffixes"])
        return out + [s for s in (self.naming["admiral_suffix"], self.naming["commodore_suffix"]) if s not in out]

    def _load_glyphs(self, name):
        """{weight: {char: thousandths of an em}} for the configured face, or {} (the fallback)."""
        if not name:
            return {}
        path = Path(name) if self.base_dir is None else self.base_dir / name
        if not path.exists():
            raise ConfigError(f"{path}: no glyph table yet; `pitch calibrate glyphs` measures it")
        g = json.loads(path.read_text(encoding="utf-8"))
        if g.get("family") != self.face_family:
            raise ConfigError(f"{path} measures {g.get('family')!r}, the config's face is {self.face_family!r}")
        return {int(w): dict(zip(g["chars"], row)) for w, row in g["widths"].items()}

    @classmethod
    def load(cls, path, load_glyphs=True):
        path = Path(path).resolve()
        data = json.loads(path.read_text(encoding="utf-8"))
        parent = data.pop("extends", None)
        inherited = None
        if parent:
            base = cls.load(path.parent / parent, load_glyphs)
            # The parent's paths stay relative to the parent: its glyph table and its brand doc.
            if "glyphs" not in (data.get("face") or {}) and base.raw["face"]["glyphs"]:
                inherited = base.glyphs_from or base.path
                data = _merge({"face": {"glyphs": str(base.base_dir / base.raw["face"]["glyphs"])}}, data)
            if "brand" not in (data.get("publish") or {}) and (base.raw.get("publish") or {}).get("brand"):
                data = _merge({"publish": {"brand": str(base.base_dir / base.raw["publish"]["brand"])}}, data)
            data = _merge(base.raw, data)
        try:
            cfg = cls(data, path.parent, load_glyphs)
        except ConfigError as e:
            raise ConfigError(f"{path}: {e}") from None
        cfg.path, cfg.glyphs_from = path, inherited
        return cfg


def _publish(p):
    """The `publish` section, refused when a value could not mean what its key says."""
    if not isinstance(p, dict):
        raise ConfigError(f"publish is {p!r}, not an object")
    extra = sorted(set(p) - set(DEFAULTS["publish"]))
    if extra:
        raise ConfigError(f"publish: no key {', '.join(extra)} (it takes {', '.join(DEFAULTS['publish'])})")
    bad = [k for k in ("design_system", "brand", "images", "asset_host") if not isinstance(p.get(k), str)]
    if bad:
        raise ConfigError(f"publish: {', '.join(bad)} must be text")
    if p["images"] not in IMAGE_ROUTES:
        raise ConfigError(f"publish.images is {p['images']!r}, not one of {', '.join(IMAGE_ROUTES)}")
    if p["design_system"] and not p["design_system"].startswith("https://"):
        raise ConfigError(f"publish.design_system is {p['design_system']!r}, not an https URL")
    if p["asset_host"] and not re.fullmatch(r"[A-Za-z0-9.-]+(?::\d+)?", p["asset_host"]):
        raise ConfigError(f"publish.asset_host is {p['asset_host']!r}: a host name alone, no scheme or path")
    return p


def _commodore(c):
    """The `commodore` section, refused when a limit could not mean what its key says."""
    if not isinstance(c, dict):
        raise ConfigError(f"commodore is {c!r}, not an object")
    for k in ("max_words", "max_statements", "max_lines", "min_font_px", "max_slides"):
        if not (isinstance(c.get(k), int) and not isinstance(c.get(k), bool) and c[k] > 0):
            raise ConfigError(f"commodore.{k} is {c.get(k)!r}, not a whole number above 0")
    prefixes = c.get("link_prefixes")
    if not (isinstance(prefixes, list) and prefixes
            and all(isinstance(x, str) and x.startswith("https://") for x in prefixes)):
        raise ConfigError(f"commodore.link_prefixes is {prefixes!r}: a list of https:// prefixes")
    return c


CONFIG_NAME = "pitch.json"


def find_config(start, explicit=None, load_glyphs=True):
    """An explicit path, else the nearest pitch.json at or above `start`."""
    if explicit:
        return Config.load(explicit, load_glyphs)
    p = Path(start).resolve()
    for d in [p] + list(p.parents):
        if (d / CONFIG_NAME).exists():
            return Config.load(d / CONFIG_NAME, load_glyphs)
    raise SystemExit(f"no {CONFIG_NAME} at or above {p}; pass --config")


def admiral_decks(root, cfg, only=None, kind="admiral"):
    """(document, project dir) for every admiral render under root (or every commodore render, by
    `kind`): the one definition the checker, the calibrator and the builder share."""
    out = []
    for md in sorted(Path(root).glob(cfg.naming["documents_glob"])):
        if only is not None and md.stem != only:
            continue
        project = md.with_name(md.stem + cfg.naming[f"{kind}_suffix"]) / "project"
        if (project / "deck.json").exists():
            out.append((md, project))
    return out


def deck_kind(deck_dir, cfg):
    """"admiral" or "commodore" for a built deck's folder by its suffix; None for any other folder."""
    name = Path(deck_dir).name
    for kind in ("commodore", "admiral"):
        suffix = cfg.naming[f"{kind}_suffix"]
        if name.endswith(suffix) and name != suffix:
            return kind
    return None


def stem_of(deck_dir, cfg):
    """The document stem of an admiral or commodore deck folder, for headline_exempt's keys."""
    kind = deck_kind(deck_dir, cfg) or "admiral"
    return Path(deck_dir).name[: -len(cfg.naming[f"{kind}_suffix"])]


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
                out.append((f"{cfg.rid}.type-floor", f"{slide.name}: font-size {value!r} - {cfg.rid} slides size "
                                                     "type in px only"))
        if n.tag in TEXT_TAGS and n.text():
            px = font_px(n)
            if px is not None and px < cfg.min_font_px:
                out.append((f"{cfg.rid}.type-floor", f"{slide.name}: <{n.tag}> “{n.text()[:30]}” renders at {px:g}px "
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
# The commodore widens it by one shape (renders S6): a statement (<p>) may hold links, each an <a> with
# an href and no other attribute, holding text only. The runtime shows one underlined in its
# paragraph's colour (S5's probe), so it inherits everything the estimate and the contrast rule read:
# an inline run of the paragraph's own text, the same face, size and weight.
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
ATTRIBUTES = {"section": {"id", "style", "data-transition"}, "a": {"href"}}


def _grammar(node, cfg):
    if node.tag == "a" and cfg.links and node.parent is not None and node.parent.tag == "p":
        return {}
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
    R = f"{cfg.rid}.markup"
    out = []
    for n in slide.section.iter():
        where = f"{slide.name}: <{n.tag}>"
        out += [(R, f"{where}: {f}") for f in n.faults]
        if n.tag != "aside" and _in_aside(n):
            out.append((R, f"{where} inside the note: a note is plain text"))
            continue
        grammar = _grammar(n, cfg)
        if grammar is None:
            out.append((R, f"{where} is outside what {cfg.a_slide} may use"))
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
        if n.tag == "a":
            if "href" not in n.attrs:
                out.append((R, f"{where} has no href"))
            kids = [c.tag for c in n.children if isinstance(c, Node)]
            if kids:
                out.append((R, f"{where} holds {kids}: a link holds text only"))
        if n.tag in ("h1", "h2", "p"):
            # A link is the one tag a statement may hold, and only where its grammar says (_grammar).
            kids = [c.tag for c in n.children if isinstance(c, Node) and not (c.tag == "a" and n.tag == "p" and cfg.links)]
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
        out.append((R, f"{slide.name}: {len(slide.headings)} headings; {cfg.a_slide} has exactly one title"))
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
        out.append((f"{cfg.rid}.words", f"{slide.name}: {len(slide.words)} words on screen (limit {cfg.max_words}) "
                                        "- cut it, or move it to the note"))
    if len(slide.statements) > cfg.max_statements:
        out.append((f"{cfg.rid}.statements", f"{slide.name}: {len(slide.statements)} statements "
                                             f"(limit {cfg.max_statements})"))
    if len(slide.note) > cfg.max_note_chars:
        out.append((f"{cfg.rid}.runtime-limits", f"{slide.name}: a {len(slide.note)}-character note "
                                                 f"(the runtime's limit is {cfg.max_note_chars})"))
    elements = sum(1 for n in slide.section.iter() if n is not slide.section and not _in_aside(n))
    if elements > cfg.max_elements:
        out.append((f"{cfg.rid}.runtime-limits", f"{slide.name}: {elements} elements "
                                                 f"(the runtime's limit is {cfg.max_elements})"))
    return out


def link_problems(slide, cfg):
    """A commodore's links, as a slide alone can judge them: each starts with a configured prefix
    (https, by default). Whether its URL is the document's or the sidecar's is the checker's question
    (check_commodore), since a slide has neither around it."""
    if not cfg.links:
        return []
    return [(f"{cfg.rid}.links", f"{slide.name}: a link to {n.attrs.get('href')!r}, not one starting "
                                 f"{' or '.join(cfg.link_prefixes)}")
            for n in slide.nodes if n.tag == "a" and not (n.attrs.get("href") or "").startswith(cfg.link_prefixes)]


def slide_links(slide):
    """(text, href) of every link on a slide, in order."""
    return [(n.text(), n.attrs.get("href") or "") for n in slide.nodes if n.tag == "a"]


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
    return [(f"{cfg.rid}.title", f"{slide.name}: {why}")] if why else []


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
    R = f"{cfg.rid}.contrast"
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
    R = f"{cfg.rid}.palette"
    out = []
    for n in slide.nodes:
        for prop, value in n.style.items():
            out += [(R, f"{slide.name}: colour {h} is not in the palette")
                    for h in re.findall(r"#[0-9a-fA-F]{3,8}\b", value) if parse_colour(h) not in cfg.allowed_colours]
            if prop in ("color", "background", "border") or "color" in prop:
                out += [(R, f"{slide.name}: {prop}:{value} - {cfg.rid} slides name colours in hex only")
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
#
# A commodore's link is an <a> inside its statement with no style of its own (the grammar's one
# widening): Node.text() joins an inline tag's text to its paragraph's with no separator, and the
# wrap reads the paragraph's face, size, weight and spacing, which the link inherits. So a link is
# measured as the run of text it is; its underline takes no width.


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
        fit.problems.append((f"{cfg.rid}.fit.width", f"<{node.tag}> is {declared:.0f}px wide in {avail_w:.0f}px of room"))
    if node.tag in TEXT_TAGS:
        px = font_px(node)
        pad = _box(node.style, "padding")
        width = min(declared, avail_w) if declared is not None else avail_w
        inner = width - pad[1] - pad[3]
        ls = _px(node.style.get("letter-spacing") or node.inherited("letter-spacing") or "0", px) or 0
        text = node.text()
        lines, widest = wrap(text, inner, px, cfg, _weight(node), _family(node), ls)
        if widest > inner + 0.5:
            fit.problems.append((f"{cfg.rid}.fit.width", f"“{text[:40]}”: a word {widest:.0f}px wide in a "
                                                      f"{inner:.0f}px box breaks mid-word"))
        if len(lines) > cfg.max_lines:
            fit.problems.append((f"{cfg.rid}.fit.lines", f"“{text[:40]}” runs to {len(lines)} lines "
                                                      f"(limit {cfg.max_lines}): shorten it"))
        for line in lines[:-1]:
            last = line.split(" ")[-1].lower()
            if last in cfg.dangling:
                fit.problems.append((f"{cfg.rid}.fit.dangling", f"“{line}” ends a line on “{last}”: join it to "
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
            fit.problems.append((f"{cfg.rid}.fit.width", f"a row of {declared:.0f}px declared width in "
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
        f.problems.append((f"{cfg.rid}.fit.overfull", f"the column is {column:.0f}px in {room:.0f}px of room: the "
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
            + contrast_problems(slide, cfg) + geometry_problems(slide, cfg) + title_problems(slide, key, cfg)
            + link_problems(slide, cfg))


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
    "sidecar.shape", "sidecar.stale",
    # renders S3: the page contract, the generated page, the captain review's shape
    "captain.contract.title", "captain.contract.tokens", "captain.contract.dark-scheme",
    "captain.contract.dark-theme", "captain.contract.background", "captain.contract.script-version",
    "captain.contract.css-load", "captain.generator-drift", "captain.unplaced",
    "review.title", "review.sections", "review.options", "review.decisions",
    # renders S6: the commodore, the sent deck: the admiral's slide rules under its own limits, and links
    "commodore.words", "commodore.statements", "commodore.markup", "commodore.runtime-limits",
    "commodore.type-floor", "commodore.palette", "commodore.contrast", "commodore.fit.overfull",
    "commodore.fit.lines", "commodore.fit.dangling", "commodore.fit.width", "commodore.title",
    "commodore.slide-count", "commodore.invented-number", "commodore.links",
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
        for suffix in cfg.deck_suffixes:
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


DECK_KINDS = ("admiral", "commodore", "folder")       # the kinds of render that are a deck folder


def renders(root, cfg, only=None):
    """(document, render path, kind) for every render; kind is admiral, commodore, folder, memo or single."""
    kinds = {cfg.naming["admiral_suffix"]: "admiral", cfg.naming["commodore_suffix"]: "commodore"}
    out = [(md, p, kinds.get(s, "folder")) for md, s, p in folder_decks(root, cfg, only)]
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
    # A page escapes `<`, `>` and `&` as entities, the document writes the characters: decode, or a
    # pin holding `n < 50` never matches the page `pitch memo` wrote from it.
    text = html.unescape(text)
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
    """An admiral deck, or a commodore deck when cfg is the commodore's view: the same rules, each
    under its own deck's limits and rule ids."""
    R = cfg.rid
    out = []
    slides = admiral_slides(project, cfg)
    if len(slides) > cfg.max_slides:
        out.append((f"{R}.slide-count", f"{project.parent.name}: {len(slides)} slides (limit {cfg.max_slides})"))
    for key, s in slides:
        out += problems(s, key, cfg)
    # Every figure on a slide, and in its presenter note, appears in the document. A twenty-word
    # slide is where a wrong number hides best: there is no sentence around it to contradict it,
    # and the pinned phrases cover only a handful of claims. The note counts because a figure the
    # speaker is handed is quoted aloud. The document's deck fence is cut first: it holds these
    # very slides, so read with the body it would vouch for every number they show. A commodore's
    # detail and link text are on screen, so they count; a link's URL is no figure a reader sees.
    body = document_body(md, cfg)
    doc_nums = numbers(body, with_bare=True)
    out += [(f"{R}.invented-number", f"{s.name}: {n} appears nowhere in {md.name}")
            for _, s in slides for n in sorted(s.figures - doc_nums)]
    if cfg.links:
        out += link_sources(md, slides, body, cfg)
    out += check_builder(project.parent, cfg)
    return out


def check_commodore(md, project, cfg):
    return check_admiral(md, project, cfg.commodore_view())


# Where a URL found in the document's body ends: whitespace, a bracket or a quote, or a sentence's
# punctuation before whitespace. Without it a link to /a would pass on the body's /abc.
URL_END = r"(?=$|[\s<>()\[\]\"'`]|[.,;:!?](?:\s|$))"


def _strings(data):
    if isinstance(data, str):
        yield data
    elif isinstance(data, dict):
        for v in data.values():
            yield from _strings(v)
    elif isinstance(data, list):
        for v in data:
            yield from _strings(v)


def link_sources(md, slides, body, cfg):
    """Each commodore link's URL is also in the document's body (the fence cut) or in its sidecar: a
    link the document never names is a claim it cannot correct, and one to a page the sidecar never
    recorded is a link nothing updates (the memo's URL lives there once it is published)."""
    sidecar = md.with_name(md.stem + cfg.naming["sidecar_suffix"])
    try:
        recorded = set(_strings(json.loads(sidecar.read_text(encoding="utf-8"))))
    except (OSError, ValueError):
        recorded = set()
    out = []
    for _, s in slides:
        for text, url in slide_links(s):
            if url and url not in recorded and not re.search(re.escape(url) + URL_END, body):
                out.append((f"{cfg.rid}.links", f"{s.name}: “{text[:40]}” links {url}, which neither {md.name}'s "
                                                f"body nor {sidecar.name} names"))
    return out


def check_exemptions(root, cfg, only=None):
    """An exemption outliving its slide would wave through whatever later takes the id. Both decks
    read the same keys, so a slide only the commodore carries keeps its exemption alive."""
    slides = {key for kind in ("admiral", "commodore") for _, project in admiral_decks(root, cfg, only, kind)
              for key, _ in admiral_slides(project, cfg)}
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
    md = deck_dir.parent / (stem_of(deck_dir, cfg) + ".md")
    if not content.exists() and not (md.exists() and deck_fences(md.read_text(encoding="utf-8"), cfg)):
        if cfg.builder["require_content_file"]:
            return [("deck.generator-drift", f"{deck_dir.name}: no deck fence in {md.name} and no {content.name}, "
                                             "so nothing generates its slides")]
        return []
    # This interpreter's build runs here, on the rules already loaded: the same code `pitch build
    # --check` runs, without a second interpreter start per deck (a fifth of a second each on a loaded
    # Mac, and the suite's 65 failing roots hold 92 decks; renders S6 took the suite from 12 s to 20 s
    # with a subprocess for each). Each other interpreter named still runs it as a subprocess, as the
    # export did: whether the builder works under that Python is the question there.
    drift = _drift_here(deck_dir, cfg)
    out = [("deck.generator-drift", f"{deck_dir.name} under {sys.executable}: {drift[:600]}")] if drift else []
    builder = HERE / "pitch"
    for py in [p for p in cfg.builder["extra_interpreters"] if Path(p).exists()]:
        args = [py, "-I", str(builder), "build", str(deck_dir)]
        if cfg.base_dir:
            args += ["--config", str(_config_path(cfg))]
        run = subprocess.run(args + ["--check"], capture_output=True, text=True)
        if run.returncode:
            out.append(("deck.generator-drift", f"{deck_dir.name} under {py}: "
                                                f"{(run.stdout + run.stderr).strip()[:600]}"))
    return out


def _drift_here(deck_dir, cfg):
    """What `pitch build <deck> --check` would say, in this process; None when the slides match. A
    refusal and a crash are drift, as the subprocess's non-zero exit was: nothing generates the deck."""
    try:
        built = build_all(deck_dir, cfg)
    except SystemExit as e:
        return str(e.code)
    except Exception as e:              # the subprocess printed its traceback here; this is its last line
        return f"the builder crashed: {type(e).__name__}: {e}"
    slide_dir = deck_dir / "project" / "slides"
    drifted = [sid for sid, html, _ in built
               if not (slide_dir / f"{sid}.html").exists() or (slide_dir / f"{sid}.html").read_text(encoding="utf-8") != html]
    if drifted:
        return (f"{deck_dir.name}: slides on disk differ from what {deck_source(deck_dir, cfg)[0]} says: {drifted} "
                "— a render was edited by hand, which the next build would silently revert")
    return None


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


def _commodore_links_cut(text, cfg):
    """A commodore slide's text with each of its own links' targets taken out: `<a href="https://…">`
    in the builder's spelling, starting with a configured prefix. That one shape is how the sent deck
    reaches its page (renders S6); any other URL, an http one or one in another attribute, stays in
    the text for deck.external to refuse."""
    prefixes = tuple(cfg.commodore["link_prefixes"])
    return re.sub(r'<a href="(https://[^"<>\s]*)">',
                  lambda m: "<a>" if html.unescape(m.group(1)).startswith(prefixes) else m.group(0), text)


def check_folder_deck(project, cfg):
    out, label = [], project.parent.name
    commodore = deck_kind(project.parent, cfg) == "commodore"
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
        # `/_blob/<id>` (an uploaded asset, served by the deck's own host) is root-relative and passes,
        # and so does a commodore's own link.
        scanned = _commodore_links_cut(text, cfg) if commodore else text
        urls = [m.group(0) for m in EXTERNAL_URL.finditer(scanned)] + re.findall(r"data:[a-z]+/", scanned)
        apis = [m.group(0) for m in NETWORK_APIS.finditer(scanned)]
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


def _load_hosts(cfg):
    """The prefixes a page may load from: the allowlist, the asset store when it returns absolute
    URLs, and each https host's protocol-relative `//host` spelling."""
    hosts = tuple(cfg.captain["allowed_load_hosts"])
    if cfg.publish["asset_host"]:       # the artifact store's uploads, when it returns them absolute
        hosts += (f"https://{cfg.publish['asset_host']}/",)
    return hosts + tuple(h[len("https:"):] for h in hosts if h.startswith("https://"))


def _code_of(text):
    """A page's scripts, styles and tags, without its prose: a memo about `fetch(` calls none."""
    parts = re.findall(r"<(script|style)\b[^>]*>(.*?)</\1\s*>", text, re.S | re.I)
    return "\n".join([body for _, body in parts] + re.findall(r"<[^>]+>", text))


def check_memo(path, cfg, md=None):
    out = captain_floor(path, cfg) + contract_problems(path, cfg)
    if md is not None:
        out += memo_drift(md, path, cfg)
    text = path.read_text(encoding="utf-8")
    hosts = _load_hosts(cfg)
    bad = [u for u in MEMO_LOAD.findall(text)
           if u.startswith(("http://", "https://", "//", "data:")) and not u.startswith(hosts)]
    apis = [m.group(0) for m in NETWORK_APIS.finditer(_code_of(text))]
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
    # Each deck its own short list: a sent deck carries more than a spoken one, never the page's all.
    tables = {"admiral": "admiral_must_appear", "commodore": "commodore_must_appear"}
    pins = {name: dict(cfg.claims.get(name) or {}) for name in ("must_appear", *tables.values())}
    if only is not None:
        pins = {name: {s: v for s, v in t.items() if s == only} for name, t in pins.items()}
    by_stem = {}
    found = renders(root, cfg, only)
    for md, path, kind in found:
        by_stem.setdefault(md.stem, []).append(kind)
        name = tables.get(kind, "must_appear")
        phrases = pins[name].get(md.stem)
        if not phrases:
            if cfg.claims["require_pins"]:
                out.append(("claims.table", f"{path.name}: no {name} entry for {md.stem}, so nothing is compared"))
            continue
        # The deck fence is cut from the document's side: a pin it alone carries is no pin.
        doc_text, ren_text = normalise(document_body(md, cfg)), normalise(render_text(path))
        for phrase in phrases:
            needle = normalise(phrase)
            missing = [w for w, t in (("document", doc_text), (path.name, ren_text)) if needle not in t]
            if missing:
                out.append(("claims.must-appear", f"{phrase!r} missing from: {', '.join(missing)}"))
    # A table entry whose renders are gone is a guard nothing reads.
    full = {s for s, kinds in by_stem.items() if any(k not in tables for k in kinds)}
    out += [("claims.table", f"must_appear names {s}, which has no render but a deck with its own list")
            for s in sorted(set(pins["must_appear"]) - full)]
    for kind, name in tables.items():
        have = {s for s, kinds in by_stem.items() if kind in kinds}
        out += [("claims.table", f"{name} names {s}, which has no {kind} render") for s in sorted(set(pins[name]) - have)]
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
# The sidecar: where each render was published
# ------------------------------------------------------------------------------------------------
#
# An artifact is keyed by the file path it was published from, so the same render published from
# another working copy becomes a second artifact with a second URL (the method, trap 5). The sidecar
# `<stem>.pitch.json` beside the document carries each render's URL, so the next publish updates the
# same artifact. Only its shape is checked here; whether a render it names still exists is
# `sidecar.stale`'s question, not this one's. The shape (the config reference, "The sidecar"):
#
#     {"document": "<stem>.md",                                   optional
#      "published": {"memo": {"url", "first_published"},           one entry or more
#                    "admiral_deck": {"url", "first_published", "type_url"},
#                    "commodore_deck": {"url", "first_published", "type_url"}},
#      "assets": {"<file>": "<url>"},                             optional
#      "images": [{"file", "route", "prompt"}]}                   optional
#
# Any other key, at the top or inside a render's entry, is a free-form note and passes.

# The keys each render's entry must carry, by its key under `published`.
SIDECAR_RENDERS = {
    "memo": ("url", "first_published"),
    "admiral_deck": ("url", "first_published", "type_url"),
    "commodore_deck": ("url", "first_published", "type_url"),
}
DATE = re.compile(r"\d{4}-\d{2}-\d{2}")
BLOB = re.compile(r"/_blob/[A-Za-z0-9_-]+")


def _https(value):
    return isinstance(value, str) and value.startswith("https://") and len(value) > len("https://")


def _date(value):
    if not (isinstance(value, str) and DATE.fullmatch(value)):
        return False
    try:
        datetime.date.fromisoformat(value)
    except ValueError:
        return False
    return True


def sidecar_problems(data, md_name):
    """What is wrong with one sidecar's parsed JSON, as messages; [] when its shape holds."""
    if not isinstance(data, dict):
        return ["is not a JSON object"]
    out = []
    if "document" in data and data["document"] != md_name:
        out.append(f"document is {data['document']!r}, but the sidecar sits beside {md_name}")
    pub = data.get("published")
    if not isinstance(pub, dict) or not pub:
        out.append("has no published entry: a sidecar exists to carry each render's URL")
        pub = {}
    for key, entry in pub.items():
        if key not in SIDECAR_RENDERS:
            out.append(f"published.{key} is no render the sidecar records ({', '.join(SIDECAR_RENDERS)})")
            continue
        if not isinstance(entry, dict):
            out.append(f"published.{key} is not an object")
            continue
        missing = [k for k in SIDECAR_RENDERS[key] if k not in entry]
        if missing:
            out.append(f"published.{key} lacks {', '.join(missing)}")
        out += [f"published.{key}.{k} is {entry[k]!r}, not an https URL"
                for k in ("url", "type_url") if k in entry and not _https(entry[k])]
        if "first_published" in entry and not _date(entry["first_published"]):
            out.append(f"published.{key}.first_published is {entry['first_published']!r}, not a YYYY-MM-DD date")
    assets = data.get("assets", {})
    # An upload's URL as the Artifact tool returns it: https, or the deck's own root-relative /_blob/<id>.
    if not isinstance(assets, dict) or not all(isinstance(k, str) and (_https(v) or (isinstance(v, str) and BLOB.fullmatch(v)))
                                               for k, v in assets.items()):
        out.append("assets is not {file: https URL or /_blob/<id>}")
    images = data.get("images", [])
    if not isinstance(images, list):
        out.append("images is not a list")
        images = []
    for i, img in enumerate(images):
        if not (isinstance(img, dict) and all(isinstance(img.get(k), str) and img.get(k) for k in ("file", "route", "prompt"))):
            out.append(f"images[{i}] lacks one of file, route, prompt")
        elif img["route"] not in IMAGE_ROUTES[1:]:
            out.append(f"images[{i}].route is {img['route']!r}, not one of {', '.join(IMAGE_ROUTES[1:])}")
    return out


def check_sidecars(root, cfg, only=None):
    """Every sidecar's shape, and, for the root, a sidecar whose document is gone."""
    suffix = cfg.naming["sidecar_suffix"]
    docs = documents(root, cfg, only)
    out = []
    for md in docs:
        path = md.with_name(md.stem + suffix)
        if not path.exists():
            continue
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except ValueError as e:
            out.append(("sidecar.shape", f"{path.name}: not JSON ({e})"))
            continue
        out += [("sidecar.shape", f"{path.name}: {m}") for m in sidecar_problems(data, md.name)]
        out += [("sidecar.stale", f"{path.name}: {m}") for m in sidecar_stale(data, md, cfg)]
    if only is None:
        # A sidecar beside no document holds URLs nothing will update: the document was renamed
        # or deleted and its sidecar left behind.
        owned = {md.with_name(md.stem + suffix) for md in docs}
        for folder in sorted({Path(root)} | {md.parent for md in docs}):
            out += [("sidecar.shape", f"{p.name}: no document {p.name[: -len(suffix)]}.md beside it")
                    for p in sorted(folder.glob("*" + suffix))
                    if p not in owned and p.name != suffix and p != cfg.path
                    # a document the glob leaves out still owns its sidecar
                    and not p.with_name(p.name[: -len(suffix)] + ".md").exists()]
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
        seen_dirs = {p.parent for _, p, k in found if k in DECK_KINDS}
        out += [("root.orphan", f"{d.name}: a deck folder no check sees (no project/)")
                for d in (root / (only + s) for s in cfg.deck_suffixes)
                if d.is_dir() and d not in seen_dirs]
        return (out + _check_renders(found, cfg) + check_exemptions(root, cfg, only) + check_claims(root, cfg, only)
                + check_sidecars(root, cfg, only) + check_documents(root, cfg, only))
    seen_files = {p for _, p, k in found if k in ("memo", "single")}
    orphans = [h.name for h in root.glob("*.html") if h not in seen_files]
    out += [("root.orphan", f"{n}: an HTML render with no document of its name, so nothing checks it") for n in orphans]
    seen_dirs = {p.parent for _, p, k in found if k in DECK_KINDS}
    suffixes = tuple(cfg.deck_suffixes)
    out += [("root.orphan", f"{d.name}: a deck folder no check sees (no document, or no project/)")
            for d in sorted(root.iterdir()) if d.is_dir() and d.name.endswith(suffixes) and d not in seen_dirs]
    out += _check_renders(found, cfg)
    out += check_exemptions(root, cfg)
    out += check_claims(root, cfg)
    out += check_sidecars(root, cfg)
    out += check_documents(root, cfg)
    return out


def _check_renders(found, cfg):
    out = []
    for md, path, kind in found:
        if kind in DECK_KINDS:
            out += check_folder_deck(path, cfg)
        if kind == "admiral":
            out += check_admiral(md, path, cfg)
        elif kind == "commodore":
            out += check_commodore(md, path, cfg)
        elif kind == "memo":
            out += check_memo(path, cfg, md)
        elif kind == "single":
            out += check_single_deck(path, cfg)
    return out


# ================================================================================================
# The builder
# ================================================================================================
#
# Why a builder and not hand-written slides: the commonest failure of a document with renders is a
# document corrected without its render, and its cause is that a deck duplicates prose by hand. Here
# the words live once, and the layout is a few functions. Where they live (D2-A, renders S3): a
# ```deck fence at the document's end, so a correction and its slides share one file and one commit;
# or, the export's form, the deck's content file (`slides.json` by default, in `<stem>-admiral-deck/`),
# which still builds so an adopter migrates without a red check. Never both (`deck_source`). Either
# holds a JSON list, one object per slide, in order:
#
#     {"id": "money", "headline": "The budget is enough",
#      "statements": ["$18K for the pilot", "..."],
#      "note": "what the speaker says; every number in it must be in the document",
#      "graphic": {"kind": "track", "values": [140, 0], "of": 420},      optional
#      "centred": true}                                                   optional
#
# The commodore deck, sent and read alone (renders S6), is built from the same list, with three keys
# only it reads:
#
#      "detail": ["a line the reader alone needs", "..."],                 optional, after the statements
#      "links": [{"text": "The whole review", "url": "https://..."}],       optional, after the detail
#      "admiral": false                                                     optional: the commodore's alone
#
# The admiral deck skips a slide marked `"admiral": false` and never shows `detail` or `links`; the
# commodore shows every slide, its statements, its detail and its links, each a block of its own.
#
# In each deck the first slide is the cover. `centred` defaults to true for the first and the last
# slide (they are statements), false for the rest, which hang from the top margin so the title does
# not hop between neighbouring slides. A `graphic` has one entry per statement: `track` fills an outlined
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

    def detail(self, text, px):
        return f'<p style="font-size:{px}px;line-height:1.3;color:{self.muted};width:{self.text_w}px">{text}</p>'

    def link(self, link, px):
        # The runtime underlines a link in its paragraph's colour (S5's probe): it needs no style.
        return (f'<p style="font-size:{px}px;line-height:1.3;width:{self.text_w}px">'
                f'<a href="{_href(link["url"])}">{link["text"]}</a></p>')

    def commodore_html(self, s, index, count):
        """A sent slide: the admiral's layout at the commodore's sizes, then its detail and its links."""
        C = self.cfg.layout["commodore"]
        sid, headline, statements, note = s["id"], s["headline"], s["statements"], s.get("note", "")
        graphic = s.get("graphic")
        cover = index == 0
        bg = self.paper if index % 2 else self.raised
        if cover:
            head_px = C["cover_head_px"]
            rows = [self.statement(t, C["cover_statement_px"], cover=True) for t in statements]
        else:
            head_px, px = C["head_px"], C["statement_px"]
            if graphic and len(graphic["values"]) != len(statements):
                sys.exit(f"{sid}: {len(graphic['values'])} graphic rows for {len(statements)} statements")
            rows = [self.evidence_row(t, px, graphic, i) if graphic else self.bullet_row(t, px)
                    for i, t in enumerate(statements)]
        rows += [self.detail(t, C["detail_px"]) for t in s.get("detail", [])]
        rows += [self.link(link, C["link_px"]) for link in s.get("links", [])]
        body = (f'<div style="display:flex;flex-direction:column;gap:{C["row_gap_px"]}px">\n'
                + "\n".join(rows) + "\n</div>")
        centred = s.get("centred", index in (0, count - 1))
        centre = "justify-content:center;" if centred else ""
        return (
            f'<section id="{sid}" data-transition="{self.transition}" style="background:{bg};color:{self.ink};'
            f'font-family:{self.font};padding:{self.cfg.margin}px;display:flex;flex-direction:column;'
            f'{centre}gap:{C["head_gap_px"]}px">\n'
            f'<h2 style="font-size:{head_px}px;line-height:1.05;letter-spacing:{C["head_letter_spacing_px"]}px;'
            f'font-weight:800;width:{self.head_w}px">{headline}</h2>\n'
            f"{body}\n"
            f"<aside>{note}</aside>\n"
            "</section>\n"
        )

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
    """Every slide of an admiral or a commodore deck, built and checked in memory. Nothing reaches
    disk until all of them pass.

    An earlier version checked inside the write loop, so a refusal mid-deck left the earlier
    slides rewritten and the later ones stale: a deck half one version and half another, with every check green on
    the mixture.
    """
    kind = deck_kind(deck_dir, cfg) or "admiral"
    source, slides = deck_source(deck_dir, cfg)
    cfg = cfg.view(kind)
    if not slides:
        sys.exit(f"{source}: every slide says \"admiral\": false, so the admiral deck has none")
    if len(slides) > cfg.max_slides:
        sys.exit(f"{len(slides)} slides, the limit is {cfg.max_slides}")
    look, stem = Look(cfg), stem_of(deck_dir, cfg)
    write = look.commodore_html if kind == "commodore" else look.slide_html
    built, refused = [], []
    for i, s in enumerate(slides):
        html = write(s, i, len(slides))
        slide = Slide(html, f"{s['id']}.html")
        refused += [msg for _, msg in problems(slide, f"{stem}/{s['id']}", cfg)]
        _, column, room, _ = fit(slide, cfg)
        built.append((s["id"], html, f"{s['id']} ({len(slide.words)} words, column {column:.0f} of {room:.0f}px)"))
    if refused:
        sys.exit("refused, nothing written:\n  " + "\n  ".join(refused))
    slide_dir = deck_dir / "project" / "slides"
    stale = {p.stem for p in slide_dir.glob("*.html")} - {b[0] for b in built}
    if stale:
        sys.exit(f"slides on disk that {source} no longer defines: {sorted(stale)} — delete them")
    return built


# ================================================================================================
# The calibrator
# ================================================================================================
#
# Holds the fit estimate's arithmetic to a real browser. Not part of the check: it needs Chrome and
# the network (the face comes from Google Fonts), and the check must run anywhere, offline. No suite
# calls Chrome either: tests/pitch_cases.py swaps `chrome` for a canned measurement, in-process.
#
# `pitch calibrate glyphs` measures every character in GLYPH_CHARS at each weight the config's face
# lists, with canvas measureText at 1000 px, and writes the table to the config's `face.glyphs` file.
# Run it when a deck's face or weights change; until then the estimate uses `face.fallback_em`,
# which over-wraps.
#
# `pitch calibrate render` lays out every admiral and commodore slide under the root in headless Chrome, with the
# Slides runtime's resets (no margins, border-box, the aside hidden, a 1920 x 1080 section), and
# compares each text block's line count and the column's height with the estimate. It exits 1 on any
# line-count difference. `--shots` also writes one PNG per slide.
#
# A plain browser stands in for the Slides runtime here, which lays out with real CSS flex and the
# browser's own text engine (its `styles.md`, "Rendering semantics"); the published deck is the
# final word. CHROME names the browser binary when it is not at the macOS default.

CHROME_DEFAULT = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
GLYPH_CHARS = (" !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~"
               "—–’‘“”…×→≥≤·•€£")


def reset(cfg):
    return (f"*{{margin:0;padding:0;box-sizing:border-box}}body{{width:{cfg.canvas_w}px}}"
            f"section{{width:{cfg.canvas_w}px;height:{cfg.canvas_h}px;overflow:hidden;position:relative}}"
            "aside{display:none}")


def chrome(page_html, cfg, budget_ms=15000, shot=None):
    """The page's `<pre id="out">` as JSON after headless Chrome ran its script, or None for a shot.
    CHROME is read per call, so a caller (or a test) can point it elsewhere."""
    import html as html_mod
    import os
    import tempfile
    binary = os.environ.get("CHROME", CHROME_DEFAULT)
    with tempfile.TemporaryDirectory() as tmp:
        page = Path(tmp) / "page.html"
        page.write_text(page_html, encoding="utf-8")
        args = [binary, "--headless=new", "--disable-gpu", "--hide-scrollbars",
                f"--virtual-time-budget={budget_ms}", f"--window-size={cfg.canvas_w},{cfg.canvas_h}"]
        args += [f"--screenshot={shot}"] if shot else ["--dump-dom"]
        # Headless Chrome occasionally hangs on exit; a hung run is retried once, never in a loop.
        for attempt in (1, 2):
            try:
                out = subprocess.run(args + [page.as_uri()], capture_output=True, text=True, timeout=90)
                break
            except FileNotFoundError:
                sys.exit(f"no Chrome at {binary}: set CHROME to the browser binary")
            except subprocess.TimeoutExpired:
                if attempt == 2:
                    sys.exit(f"Chrome hung twice on {'a screenshot' if shot else 'a measurement'}")
        if shot:
            return None
        m = re.search(r'<pre id="out">(.*?)</pre>', out.stdout, re.S)
        if not m:
            sys.exit("Chrome returned no measurement; is it installed and online?\n" + out.stderr[-800:])
        body = html_mod.unescape(m.group(1))
        if not body.startswith("{"):
            sys.exit("measurement failed: " + body[:400])
        return json.loads(body)


def glyph_table(cfg, got):
    """The table `face.glyphs` holds, from one measurement: {"loaded": [bool…], "widths": {weight: […]}}."""
    weights = sorted(cfg.face_weights)
    if not all(got["loaded"]):
        sys.exit(f"{cfg.face_family} did not load at every weight: {dict(zip(weights, got['loaded']))}")
    return {"family": cfg.face_family, "measured_with": "canvas measureText at 1000 px, headless Chrome",
            "chars": GLYPH_CHARS, "widths": {str(w): got["widths"][str(w)] for w in weights}}


def measure_glyphs(cfg):
    if not (cfg.face_family and cfg.face_href and cfg.raw["face"]["glyphs"]):
        sys.exit("the config needs face.family, face.href and face.glyphs (the file to write)")
    if cfg.glyphs_from:
        # Writing it would re-measure the parent's table for this face, and stop the parent's check.
        sys.exit(f"face.glyphs is inherited from {cfg.glyphs_from}; name this config's own table")
    fam, weights = cfg.face_family, sorted(cfg.face_weights)
    js = f"""
const chars = {json.dumps(GLYPH_CHARS, ensure_ascii=False)}, weights = {json.dumps(weights)}, fam = {json.dumps(fam)};
(async () => {{
  await Promise.all(weights.map(w => document.fonts.load(`${{w}} 100px "${{fam}}"`)));
  const cv = document.createElement('canvas').getContext('2d'), out = {{loaded: [], widths: {{}}}};
  for (const w of weights) {{
    out.loaded.push(document.fonts.check(`${{w}} 100px "${{fam}}"`));
    cv.font = `${{w}} 1000px "${{fam}}"`;
    out.widths[w] = [...chars].map(c => Math.round(cv.measureText(c).width));
  }}
  document.getElementById('out').textContent = JSON.stringify(out);
}})();"""
    page = (f'<!doctype html><meta charset="utf-8"><link rel="stylesheet" href="{cfg.face_href}">'
            f'<pre id="out">pending</pre><script>{js}</script>')
    table = glyph_table(cfg, chrome(page, cfg))
    target = cfg.base_dir / cfg.raw["face"]["glyphs"]
    new = json.dumps(table, ensure_ascii=False, indent=1)
    old = target.read_text(encoding="utf-8") if target.exists() else ""
    target.write_text(new + "\n", encoding="utf-8")
    print("glyph table unchanged" if old.strip() == new.strip() else f"wrote {target}")


MEASURE_JS = """
(async () => {
  await document.fonts.ready;
  for (const w of WEIGHTS) await document.fonts.load(`${w} 100px "FAMILY"`);
  const out = {slides: {}};
  for (const sec of document.querySelectorAll('section')) {
    const top0 = sec.getBoundingClientRect().top;
    const blocks = [...sec.querySelectorAll('h1,h2,h3,p,li')].filter(e => !e.closest('aside')).map(e => {
      const r = e.getBoundingClientRect(), cs = getComputedStyle(e);
      const range = document.createRange(); range.selectNodeContents(e);
      const tops = new Set([...range.getClientRects()].map(q => Math.round(q.top)));
      return {tag: e.tagName.toLowerCase(), text: e.textContent.trim(), height: r.height,
              lines: tops.size, font: cs.fontFamily, size: parseFloat(cs.fontSize)};
    });
    const flow = [...sec.children].filter(e => e.tagName !== 'ASIDE' && getComputedStyle(e).position !== 'absolute');
    const first = flow[0].getBoundingClientRect(), last = flow[flow.length - 1].getBoundingClientRect();
    out.slides[sec.id] = {blocks, column: last.bottom - first.top, top: first.top - top0};
  }
  document.getElementById('out').textContent = JSON.stringify(out);
})();"""


def calibrate_render(root, cfg, shots=None):
    """Every admiral and commodore slide under root, the estimate against Chrome: 0 when every line
    count agrees."""
    worst, status = 0, 0
    face = f'<link rel="stylesheet" href="{cfg.face_href}">' if cfg.face_href else ""
    js = MEASURE_JS.replace("WEIGHTS", json.dumps(cfg.face_weights)).replace("FAMILY", cfg.face_family or "sans-serif")
    decks = [(md, p, cfg) for md, p in admiral_decks(root, cfg)]
    decks += [(md, p, cfg.commodore_view()) for md, p in admiral_decks(root, cfg, kind="commodore")]
    if not decks:
        sys.exit(f"no admiral deck under {root}: nothing to lay out")
    for md, project, view in decks:
        order = json.loads((project / "deck.json").read_text(encoding="utf-8"))["order"]
        sections = {sid: (project / "slides" / f"{sid}.html").read_text(encoding="utf-8") for sid in order}
        page = (f'<!doctype html><meta charset="utf-8">{face}<style>{reset(cfg)}</style>'
                + "".join(sections.values()) + f'<pre id="out">pending</pre><script>{js}</script>')
        got = chrome(page, cfg)["slides"]
        print(f"{project.parent.name}: estimate against Chrome")
        print(f"  {'slide':10} {'column est':>10} {'chrome':>8} {'diff':>6}   {'top est':>7} {'chrome':>7}   lines (est/chrome)")
        for sid in order:
            slide = Slide(sections[sid], f"{sid}.html")
            if markup_problems(slide, view):
                sys.exit(f"{md.stem}: {sid}.html is outside the markup grammar; `pitch check` names what")
            if sid not in got:
                sys.exit(f"{md.stem}: {sid}.html has no <section id=\"{sid}\">, so Chrome's measure cannot be matched")
            f, column, room, top = fit(slide, view)
            m = got[sid]
            est_lines = [b[2] for b in f.blocks]
            real_lines = [b["lines"] for b in m["blocks"]]
            fonts = {b["font"].split(",")[0].strip("'\" ") for b in m["blocks"]}
            mismatch = est_lines != real_lines
            worst = max(worst, abs(column - m["column"]))
            print(f"  {sid:10} {column:10.1f} {m['column']:8.1f} {column - m['column']:6.1f}   {top:7.1f} {m['top']:7.1f}"
                  f"   {est_lines}/{real_lines}{'  <-- differs' if mismatch else ''}  [{', '.join(sorted(fonts))}]")
            if mismatch:
                print("    blocks:", [(b["text"][:30], b["lines"]) for b in m["blocks"]])
                status = 1
            if shots:
                Path(shots).mkdir(parents=True, exist_ok=True)
                one = f'<!doctype html><meta charset="utf-8">{face}<style>{reset(cfg)}</style>{sections[sid]}'
                deck = "" if view.rid == "admiral" else f"-{view.rid}"     # the admiral's names as before
                chrome(one, cfg, shot=str(Path(shots) / f"{md.stem}{deck}-{sid}.png"))
    print(f"largest column difference: {worst:.1f}px")
    return status


# ================================================================================================
# The document: its deck fence, its page, its captain review (renders S3)
# ================================================================================================
#
# D2-A put every render's words in the document. The admiral deck's slides sit in one fence at the
# document's end (```deck, holding the content file's JSON list); `pitch build` reads it, and every
# check that compares a render with its document reads the document with that fence cut out, or the
# fence would vouch for the very slides it holds. The captain page is generated whole from the
# document by `pitch memo`, a small converter that refuses a block it cannot place rather than drop
# it. A captain review (the document for the person who decides, /captain's template) is a document
# whose title says so; its shape is held by the `review.*` rules wherever `pitch check` reads it.

FENCE = re.compile(r"^ {0,3}(`{3,}|~{3,})\s*([^\s`]*)")


def _closes(line, mark):
    return re.fullmatch(r" {0,3}" + re.escape(mark[0]) + "{%d,}\\s*" % len(mark), line) is not None


def fences(lines):
    """(first index, last index, info word) of every fenced block in a list of lines; an unclosed
    fence runs to the end, as Markdown reads it."""
    out, i = [], 0
    while i < len(lines):
        m = FENCE.match(lines[i])
        if not m:
            i += 1
            continue
        j = i + 1
        while j < len(lines) and not _closes(lines[j], m.group(1)):
            j += 1
        out.append((i, min(j, len(lines) - 1), m.group(2).lower()))
        i = j + 1
    return out


def admiral_wanted(slides):
    """A fence builds the admiral unless every slide is the commodore's alone (`"admiral": false`)."""
    return not slides or any(not (isinstance(x, dict) and x.get("admiral") is False) for x in slides)


def deck_fences(text, cfg):
    """(first line number, JSON text) of each deck fence in a document."""
    lines = text.split("\n")
    return [(a + 1, "\n".join(lines[a + 1:b])) for a, b, info in fences(lines) if info == cfg.naming["deck_fence"]]


def document_body(md, cfg):
    """The document as the number and pin checks read it: the deck fence blanked, line count kept."""
    lines = Path(md).read_text(encoding="utf-8").split("\n")
    for a, b, info in fences(lines):
        if info == cfg.naming["deck_fence"]:
            lines[a:b + 1] = [""] * (b + 1 - a)
    return "\n".join(lines)


COMMODORE_KEYS = ("detail", "links", "admiral")


def _slide_shape(s):
    """What is wrong with one slide's commodore keys, or None."""
    if "detail" in s and not (isinstance(s["detail"], list) and all(isinstance(t, str) for t in s["detail"])):
        return f"{s['id']}: detail is a list of lines"
    if "links" in s and not (isinstance(s["links"], list) and all(
            isinstance(x, dict) and isinstance(x.get("text"), str) and x["text"].strip()
            and isinstance(x.get("url"), str) for x in s["links"])):
        return f"{s['id']}: links is a list of {{\"text\", \"url\"}}, each with its text"
    if "admiral" in s and not isinstance(s["admiral"], bool):
        return f"{s['id']}: admiral is true or false"
    return None


def deck_source(deck_dir, cfg):
    """(where, slides): a deck's words, from the document's deck fence or the content file, never
    both; the admiral's without the slides marked `"admiral": false`, the commodore's all of them. The
    commodore is built from a fence only: the content file is the export's admiral deck, kept so an
    adopter migrates without a red check. A refusal is sys.exit(message): the builder's exit 1."""
    kind = deck_kind(deck_dir, cfg) or "admiral"
    md = deck_dir.parent / (stem_of(deck_dir, cfg) + ".md")
    content = (md.with_name(md.stem + cfg.naming["admiral_suffix"]) if kind == "commodore" else deck_dir) \
        / cfg.naming["content_file"]
    found = deck_fences(md.read_text(encoding="utf-8"), cfg) if md.exists() else []
    if len(found) > 1:
        sys.exit(f"{md.name} has {len(found)} deck fences (lines {', '.join(str(n) for n, _ in found)}); one holds the deck")
    if found and content.exists():
        # Two copies of the words is the root trap itself: say which to keep rather than pick one.
        sys.exit(f"two sources for {deck_dir.name}: the deck fence in {md.name} and {content.name}; "
                 f"keep the fence and delete {content.name}")
    if kind == "commodore" and not found:
        sys.exit(f"no deck fence in {md.name}: the commodore deck is built from the fence alone")
    if found:
        where, raw = f"{md.name}'s deck fence (line {found[0][0]})", found[0][1]
    elif content.exists():
        where, raw = content.name, content.read_text(encoding="utf-8")
    else:
        sys.exit(f"no deck fence in {md.name} and no {content.name} in {deck_dir}")
    try:
        slides = json.loads(raw)
    except ValueError as e:
        sys.exit(f"{where} is not JSON: {e}")
    if not (isinstance(slides, list) and slides and all(
            isinstance(s, dict) and isinstance(s.get("id"), str) and isinstance(s.get("headline"), str)
            and isinstance(s.get("statements"), list) for s in slides)):
        sys.exit(f"{where}: a list of slides, each with an id, a headline and its statements")
    ids = [s["id"] for s in slides]
    twice = sorted({i for i in ids if ids.count(i) > 1})
    if twice:                           # one slide file per id: the second would overwrite the first
        sys.exit(f"{where}: slide ids used twice: {twice}")
    wrong = [w for w in map(_slide_shape, slides) if w]
    if wrong:
        sys.exit(f"{where}: " + "; ".join(wrong))
    if kind == "admiral":
        slides = [s for s in slides if s.get("admiral") is not False]
    return where, slides


def document_title(text):
    """The first `# ` line outside fences and comments, its Markdown dropped; "" when there is none."""
    for _, line in body_lines(text):
        if line.startswith("# "):
            return _plain(line[2:].strip())
    return ""


def deck_index(md, ids, cfg):
    """A first `deck.json` for a deck the fence builds: the Slides type's index, version, title,
    order and the configured face. The builder writes it once; after that it is the person's, and
    `deck.index` holds it to the slide files."""
    index = {"v": cfg.naming["deck_index_version"], "title": document_title(md.read_text(encoding="utf-8")) or md.stem,
             "order": ids}
    if cfg.face_family and cfg.face_href:
        index["faces"] = {cfg.face_family.lower().replace(" ", "-"): {"family": cfg.face_family, "href": cfg.face_href}}
    return index


def check_documents(root, cfg, only=None):
    """What a document owes on its own: a captain review its template's shape, a deck fence a deck."""
    out = []
    for md in documents(root, cfg, only):
        text = md.read_text(encoding="utf-8")
        if is_review(text):
            out += review_problems(text, md.name)
        found = deck_fences(text, cfg)
        if not found:
            continue
        try:
            slides = json.loads(found[0][1])
        except ValueError:
            slides = None                   # the builder's own refusal names it, at `pitch build`
        slides = slides if isinstance(slides, list) else []
        # A fence builds the admiral unless every slide is the commodore's alone, and the commodore
        # once any slide carries what only it shows: words in the fence that no deck shows are the
        # stale-render trap waiting for its first correction.
        want = {"admiral": admiral_wanted(slides),
                "commodore": any(isinstance(x, dict) and (x.get("detail") or x.get("links") or x.get("admiral") is False)
                                 for x in slides)}
        for kind, wanted in want.items():
            deck = md.with_name(md.stem + cfg.naming[f"{kind}_suffix"])
            if wanted and not (deck / "project" / "deck.json").exists():
                flag = "" if kind == "admiral" else " --deck commodore"
                out.append(("deck.generator-drift", f"{md.name}: a deck fence whose {kind} deck nothing has built; "
                                                    f"`pitch build {md.name}{flag}`"))
    return out


def sidecar_stale(data, md, cfg):
    """A render the sidecar records that is gone: its URL now updates nothing the document has."""
    if not isinstance(data, dict) or not isinstance(data.get("published"), dict):
        return []
    where = {"memo": md.with_name(md.stem + cfg.naming["memo_suffix"]),
             "admiral_deck": md.with_name(md.stem + cfg.naming["admiral_suffix"]) / "project" / "deck.json",
             "commodore_deck": md.with_name(md.stem + cfg.naming["commodore_suffix"]) / "project" / "deck.json"}
    return [f"published.{key} names {where[key].relative_to(md.parent).parts[0]}, which is gone: "
            "rebuild it, or drop the entry with the artifact"
            for key in data["published"] if key in where and not where[key].exists()]


# ------------------------------------------------------------------------------------------------
# The page contract: what an artifact page must carry (the artifact runtime's own contract)
# ------------------------------------------------------------------------------------------------
#
# A memo published as an artifact is a page with its own theme: colour tokens on :root, the dark set
# twice (the viewer's scheme, guarded by the light override, and the explicit dark override), a body
# background, a title. A page missing one renders, then reads wrongly in one theme: nothing errors.
# Scripts come from the runtime's CDNs at an exact version (an unpinned one changes under a published
# page). The captain allowlist reads elements; a CSS url() loads too, and is read here.

PINNED_VERSION = re.compile(r"[@/]v?\d+\.\d+\.\d+")


class _PageScan(HTMLParser):
    """A page's <style> text and inline styles, its <title>, and its script sources."""

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.css, self.title, self.scripts, self._in = [], "", [], None

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag in ("style", "title"):
            self._in = tag
        if tag == "script" and a.get("src"):
            self.scripts.append(a["src"])
        if a.get("style"):
            self.css.append(a["style"])

    def handle_endtag(self, tag):
        if tag == self._in:
            self._in = None

    def handle_data(self, data):
        if self._in == "style":
            self.css.append(data)
        elif self._in == "title":
            self.title += data


def _rule_bodies(css, selector):
    return [m.group(1) for m in re.finditer(selector + r"\s*\{([^{}]*)\}", css)]


def _media_bodies(css, condition):
    """The text inside each @media block whose condition matches, nested braces balanced."""
    out = []
    for m in re.finditer(r"@media[^{]*" + condition + r"[^{]*\{", css):
        i, depth = m.end(), 1
        while i < len(css) and depth:
            depth += {"{": 1, "}": -1}.get(css[i], 0)
            i += 1
        out.append(css[m.end():i - 1])
    return out


def contract_problems(path, cfg):
    scan = _PageScan()
    scan.feed(path.read_text(encoding="utf-8"))
    scan.close()
    css = re.sub(r"/\*.*?\*/", "", "\n".join(scan.css), flags=re.S)
    name, out = path.name, []
    if not scan.title.strip():
        out.append(("captain.contract.title", f"{name}: no <title>, so the artifact has no name"))
    if not any("--" in b for b in _rule_bodies(css, r"(?<![\w-]):root")):
        out.append(("captain.contract.tokens", f"{name}: no colour tokens on :root"))
    if not any(re.search(r':root:not\(\[data-theme=["\']?light["\']?\]\)\s*\{[^}]*--', b)
               for b in _media_bodies(css, r"prefers-color-scheme\s*:\s*dark")):
        out.append(("captain.contract.dark-scheme", f"{name}: no dark tokens under @media (prefers-color-scheme: dark) "
                                                    "guarded by :root:not([data-theme=\"light\"])"))
    if not re.search(r':root\[data-theme=["\']?dark["\']?\]\s*\{[^}]*--', css):
        out.append(("captain.contract.dark-theme", f"{name}: no :root[data-theme=\"dark\"] block"))
    if not any(re.search(r"background(-color)?\s*:", b) for b in _rule_bodies(css, r"(?:^|[\s,}])body")):
        out.append(("captain.contract.background", f"{name}: body sets no background"))
    hosts = _load_hosts(cfg)
    # Only a script the allowlist lets through: one from elsewhere is `captain.allowlist`'s finding.
    unpinned = [u for u in scan.scripts if u.startswith(hosts) and not PINNED_VERSION.search(u)]
    if unpinned:
        out.append(("captain.contract.script-version", f"{name}: a script names no exact version: {unpinned}"))
    loads = [u for u in re.findall(r"url\(\s*['\"]?([^'\")\s]+)", css)
             if u.startswith(("http://", "https://", "//", "data:")) and not u.startswith(hosts)]
    if loads:
        out.append(("captain.contract.css-load", f"{name}: CSS loads from outside the allowlist: {loads}"))
    return out


# ------------------------------------------------------------------------------------------------
# `pitch memo`: the captain page, generated from the document
# ------------------------------------------------------------------------------------------------
#
# The shapes it places (the review fixture under tests/fixtures/pitch/review holds every one):
# headings, paragraphs, bulleted and numbered lists nested to any depth with continuation blocks in
# an item, pipe tables, block quotes, fenced code, rules, and inline bold, italic, code spans and
# links. An HTML comment is dropped, a block or inside a line (a template's guidance is never the reader's); the deck fence is
# cut (it is the decks' words). What it will not place is reported by line and nothing is written:
# a raw HTML block, an image (in a paragraph, a heading or a table), a diagram fence (mermaid and the
# like: a page draws nothing from text), indented code, a heading underlined with = or -, a table
# whose rows lack their leading |, a reference-style link, text after a comment's -->. A link the reader can follow from a
# published page (https, mailto) stays a link; any other target, a path in the repo or on a disk,
# keeps only its text, since an artifact has no repo around it and a disk path would leak.

MEMO_MARK = '<meta name="generator" content="pitch memo">'
DIAGRAM_FENCES = {"mermaid", "dot", "graphviz", "plantuml", "d2", "svgbob"}
LIST_ITEM = re.compile(r"^( *)([-*+]|\d{1,9}[.)])( +|$)(.*)$")
TABLE_SEP = re.compile(r"^\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)*\|?\s*$")
RULE_LINE = re.compile(r"^ {0,3}([-*_])(?:\s*\1){2,}\s*$")
HEADING = re.compile(r"^ {0,3}(#{1,6})\s+(.*?)(?:\s+#+)?\s*$")
IMAGE = re.compile(r"!\[[^\]]*\]\([^)]*\)")


def _indent(line):
    return len(line) - len(line.lstrip(" "))


def _esc(text):
    """Escape for HTML text: &, < and > always. A bare & is not safe left raw: a browser decodes the
    old entity names without their `;` (`x&not y` reads `x¬ y`). normalise() decodes them again, so a
    pinned phrase holding one still matches."""
    return html.escape(text, quote=False)


def _href(url):
    return html.escape(url, quote=True)


def _plain(text):
    """A heading's text with its Markdown dropped, for <title>."""
    text = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", text)
    return re.sub(r"[*_`]", "", text).strip()


def _emphasis(text):
    text = re.sub(r"\*\*(?=\S)(.+?)(?<=\S)\*\*", r"<strong>\1</strong>", text)
    text = re.sub(r"(?<![\w])__(?=\S)(.+?)(?<=\S)__(?![\w])", r"<strong>\1</strong>", text)
    text = re.sub(r"(?<![\w*])\*(?=[^\s*])(.+?)(?<=[^\s*])\*(?![\w*])", r"<em>\1</em>", text)
    return re.sub(r"(?<![\w])_(?=[^\s_])(.+?)(?<=[^\s_])_(?![\w])", r"<em>\1</em>", text)


def _inline(text):
    """One block's text as HTML: code spans literal, links kept or reduced to their text, then
    escaping and emphasis; placeholders keep what is done out of what follows."""
    held = []

    def hold(fragment):
        held.append(fragment)
        return f"\x00{len(held) - 1}\x00"

    # A NUL of the document's own would never resolve as a placeholder; it is no character a page wants.
    text = text.replace("\x00", "\ufffd")
    text = re.sub(r"(`+)(.+?)(?<!`)\1(?!`)", lambda m: hold(f"<code>{_esc(m.group(2).strip())}</code>"), text)
    text = re.sub(r"\\([\\`*_\[\]()#+\-.!|>])", lambda m: hold(_esc(m.group(1))), text)
    text = re.sub(r"<!--.*?-->", "", text)         # a comment inside a line is guidance too
    text = re.sub(r"<(https://[^\s<>\"'\x00]+)>", lambda m: hold(f'<a href="{_href(m.group(1))}">{_esc(m.group(1))}</a>'), text)

    def link(m):
        label, url = _emphasis(_esc(m.group(1))), m.group(2).strip().split(" ")[0]
        # A target holding a placeholder (a code span, an escape) would put HTML inside the attribute.
        if url.startswith(("https://", "mailto:")) and "\x00" not in url:
            return hold(f'<a href="{_href(url)}">{label}</a>')
        return hold(label)
    text = re.sub(r"\[([^\]]+)\]\(((?:[^()]|\([^()]*\))*)\)", link, text)
    text = _emphasis(_esc(text))
    while re.search(r"\x00\d+\x00", text):
        text = re.sub(r"\x00(\d+)\x00", lambda m: held[int(m.group(1))], text)
    return text


def _cells(line):
    """A table row's cells: split on pipes outside code spans, the edge pipes dropped."""
    line = line.strip()
    line = line[1:] if line.startswith("|") else line
    line = line[:-1] if line.endswith("|") and not line.endswith("\\|") else line
    cells, cur, code = [], "", False
    for i, ch in enumerate(line):
        if ch == "`":
            code = not code
        if ch == "|" and not code and (i == 0 or line[i - 1] != "\\"):
            cells.append(cur.strip())
            cur = ""
        else:
            cur += ch
    return cells + [cur.strip()]


def _starts_block(line):
    """A line that ends a paragraph: a heading, a fence, a quote, a rule, a list item (a numbered
    one only from 1, as CommonMark has it, so a wrapped `2026.` stays text), a comment."""
    s = line.strip()
    m = LIST_ITEM.match(line)
    return bool(HEADING.match(line) or FENCE.match(line) or s.startswith((">", "<!--")) or RULE_LINE.match(line)
                or (m and m.group(4).strip() and (not m.group(2)[0].isdigit() or int(m.group(2)[:-1]) == 1)))


def _blocks(rows, cfg, unplaced):
    """HTML for a list of (line number, text) rows, recursively for quotes and list items."""
    out, i = [], 0
    while i < len(rows):
        n, line = rows[i]
        s = line.strip()
        if not s:
            i += 1
            continue
        if s.startswith("<!--"):
            while i < len(rows) and "-->" not in rows[i][1]:
                i += 1
            if i < len(rows) and rows[i][1].split("-->", 1)[1].strip():
                unplaced.append((rows[i][0], "text after a comment's `-->`: start it on its own line"))
            i += 1
            continue
        f = FENCE.match(line)
        if f:
            j = i + 1
            while j < len(rows) and not _closes(rows[j][1], f.group(1)):
                j += 1
            info = f.group(2).lower()
            if info in DIAGRAM_FENCES:
                unplaced.append((n, f"a {info} fence: a page draws no diagram from text; draw it as an image, or cut it"))
            elif info != cfg.naming["deck_fence"]:
                body = "\n".join(r[1] for r in rows[i + 1:j])
                out.append(f"<pre><code>{_esc(body)}</code></pre>")
            i = j + 1
            continue
        h = HEADING.match(line)
        if h:
            if IMAGE.search(line):
                unplaced.append((n, "an image in a heading: upload it and place it by hand"))
            level = len(h.group(1))
            out.append(f"<h{level}>{_inline(h.group(2))}</h{level}>")
            i += 1
            continue
        if RULE_LINE.match(line):
            out.append("<hr>")
            i += 1
            continue
        if s.startswith("|") and i + 1 < len(rows) and TABLE_SEP.match(rows[i + 1][1].strip()):
            if IMAGE.search(line):
                unplaced.append((n, "an image in a table: upload it and place it by hand"))
            head = "".join(f"<th>{_inline(c)}</th>" for c in _cells(line))
            body, j = [], i + 2
            while j < len(rows) and rows[j][1].strip().startswith("|"):
                if IMAGE.search(rows[j][1]):
                    unplaced.append((rows[j][0], "an image in a table: upload it and place it by hand"))
                body.append("<tr>" + "".join(f"<td>{_inline(c)}</td>" for c in _cells(rows[j][1])) + "</tr>")
                j += 1
            out.append(f"<table>\n<thead><tr>{head}</tr></thead>\n<tbody>\n" + "\n".join(body) + "\n</tbody>\n</table>")
            i = j
            continue
        if s.startswith(">"):
            quoted, j = [], i
            while j < len(rows) and rows[j][1].strip().startswith(">"):
                q = rows[j][1].strip()[1:]
                quoted.append((rows[j][0], q[1:] if q.startswith(" ") else q))
                j += 1
            out.append("<blockquote>\n" + _blocks(quoted, cfg, unplaced) + "\n</blockquote>")
            i = j
            continue
        if LIST_ITEM.match(line) and LIST_ITEM.match(line).group(4).strip():
            html, i = _list(rows, i, cfg, unplaced)
            out.append(html)
            continue
        if re.match(r"^ {0,3}<(?!https://)[A-Za-z/!?]", line):
            unplaced.append((n, "a raw HTML block: write it as Markdown, or place it by hand"))
            i += 1
            while i < len(rows) and rows[i][1].strip():
                i += 1
            continue
        if line.startswith(("    ", "\t")):
            unplaced.append((n, "indented code: fence it with ```"))
            while i < len(rows) and rows[i][1].startswith(("    ", "\t")):
                i += 1
            continue
        para, j = [s], i + 1
        while j < len(rows) and rows[j][1].strip():
            # before _starts_block, which reads a `---` underline as a rule
            if re.fullmatch(r" {0,3}(=+|-+)\s*", rows[j][1]):
                unplaced.append((n, "a heading underlined with = or -: write it with #"))
                break
            if "|" in rows[j][1] and TABLE_SEP.match(rows[j][1].strip()):
                unplaced.append((n, "a table whose rows do not start with |, or one with no blank line above it"))
                break
            if _starts_block(rows[j][1]):
                break
            para.append(rows[j][1].strip())
            j += 1
        text = "\n".join(para)
        if IMAGE.search(text):
            unplaced.append((n, "an image: upload it as an asset and place it by hand"))
        if re.search(r"^ {0,3}\[[^\]]+\]:\s", text, re.M) or re.search(r"\[[^\]]+\]\[[^\]]*\]", text):
            # printed as it stands, a definition's target (a disk path, say) would reach the page
            unplaced.append((n, "a reference-style link: write it inline, [text](target)"))
        out.append(f"<p>{_inline(text)}</p>")
        i = j
    return "\n".join(out)


def _list(rows, i, cfg, unplaced):
    """One list from rows[i]: each item's rows dedented to its content and read as blocks. An item
    of another marker (`*` after `-`, `1)` after `1.`) starts another list, as CommonMark has it; a
    blank line between or inside items makes the list loose, and its items keep their paragraphs."""
    first = LIST_ITEM.match(rows[i][1])
    indent, marker = len(first.group(1)), re.sub(r"\d", "", first.group(2))

    def same(m):
        return m and len(m.group(1)) == indent and re.sub(r"\d", "", m.group(2)) == marker and m.group(4).strip()
    items, loose = [], False
    while i < len(rows):
        m = LIST_ITEM.match(rows[i][1])
        if not same(m):
            break
        gap = len(m.group(3))
        content = indent + len(m.group(2)) + (gap if 0 < gap <= 4 else 1)
        item = [(rows[i][0], m.group(4))]
        i += 1
        while i < len(rows):
            n, line = rows[i]
            if not line.strip():
                k = i
                while k < len(rows) and not rows[k][1].strip():
                    k += 1
                if k < len(rows) and _indent(rows[k][1]) >= content:
                    item += [(r[0], "") for r in rows[i:k]]
                    loose, i = True, k
                    continue
                break
            sub = LIST_ITEM.match(line)
            if _indent(line) >= content or (sub and len(sub.group(1)) > indent):
                item.append((n, line[min(content, _indent(line)):]))
            elif not sub and not _starts_block(line):
                item.append((n, line.strip()))         # a lazy continuation of the item's paragraph
            else:
                break
            i += 1
        items.append(_blocks(item, cfg, unplaced))
        k = i
        while k < len(rows) and not rows[k][1].strip():
            k += 1
        if k > i and k < len(rows) and same(LIST_ITEM.match(rows[k][1])):
            loose, i = True, k
    if not loose:
        items = [h.replace("<p>", "", 1).replace("</p>", "", 1) if h.startswith("<p>") else h for h in items]
    tag = "ol" if marker not in "-*+" else "ul"
    start = int(first.group(2)[:-1]) if tag == "ol" else 1
    attr = f' start="{start}"' if start != 1 else ""
    return f"<{tag}{attr}>\n" + "\n".join(f"<li>{h}</li>" for h in items) + f"\n</{tag}>", i


def memo_page(md, cfg):
    """(html, unplaced): the captain page for a document, or the blocks it could not place, as
    [(line, what)]; the page is None when any block could not be placed."""
    text = Path(md).read_text(encoding="utf-8")
    rows = list(enumerate(text.split("\n"), 1))
    unplaced = []
    body = _blocks(rows, cfg, unplaced)
    title = document_title(text)
    if not title:
        unplaced.append((1, "no `# ` title: a page needs one, and its <title> is that line"))
    if unplaced:
        return None, sorted(unplaced)
    L, dark = cfg.layout, cfg.memo["dark"]

    def tokens(c):
        return " ".join(f"--{k}: {c[k]};" for k in ("ink", "muted", "accent", "paper", "raised"))
    font = f"'{cfg.face_family}', {cfg.face_stack}" if cfg.face_family else cfg.face_stack
    floor = cfg.captain["min_font_px"]

    def px(n):                          # a raised floor raises every size under it, or the page fails its own check
        return f"{max(n, floor)}px"
    face = f'<link rel="stylesheet" href="{cfg.face_href}">\n' if cfg.face_href else ""
    page = f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
{MEMO_MARK}
<title>{_esc(title)}</title>
{face}<style>
:root {{ {tokens(L)} }}
@media (prefers-color-scheme: dark) {{
  :root:not([data-theme="light"]) {{ {tokens(dark)} }}
}}
:root[data-theme="dark"] {{ {tokens(dark)} }}
body {{ margin: 0; background: var(--paper); color: var(--ink); font-family: {font}; font-size: {px(18)}; line-height: 1.55; }}
main {{ max-width: 760px; margin: 0 auto; padding: 32px 16px 64px; overflow-wrap: break-word; }}
h1 {{ font-size: {px(34)}; line-height: 1.15; margin: 0 0 24px; }}
h2 {{ font-size: {px(24)}; line-height: 1.25; margin: 40px 0 12px; }}
h3 {{ font-size: {px(20)}; margin: 28px 0 8px; }}
h4, h5, h6 {{ font-size: {px(18)}; margin: 24px 0 8px; }}
a {{ color: var(--accent); }}
blockquote {{ margin: 16px 0; padding: 0 0 0 16px; border-left: 4px solid var(--accent); color: var(--muted); }}
table {{ display: block; overflow-x: auto; border-collapse: collapse; font-size: {px(16)}; margin: 16px 0; }}
th, td {{ text-align: left; vertical-align: top; padding: 8px; border-bottom: 1px solid var(--muted); }}
pre {{ background: var(--raised); padding: 12px 16px; overflow-x: auto; }}
code {{ font-family: ui-monospace, Menlo, monospace; font-size: {px(16)}; }}
hr {{ border: 0; border-top: 1px solid var(--muted); margin: 32px 0; }}
</style>
</head>
<body>
<main>
{body}
</main>
</body>
</html>
"""
    return page, []


def memo_drift(md, path, cfg):
    """A page `pitch memo` wrote must still be what it writes: the document corrected and the page
    left behind is the root trap, and a hand edit would be lost at the next run. A hand-written page
    (no generator mark) is the person's until a correction replaces it."""
    if MEMO_MARK not in path.read_text(encoding="utf-8"):
        return []
    page, unplaced = memo_page(md, cfg)
    if unplaced:
        return [("captain.unplaced", f"{md.name}:{n}: {what}") for n, what in unplaced]
    if page != path.read_text(encoding="utf-8"):
        return [("captain.generator-drift", f"{path.name} differs from what `pitch memo` writes from {md.name}: "
                                            "the document changed without its page, or the page was edited by hand")]
    return []


# ------------------------------------------------------------------------------------------------
# The captain review: one document for the person who decides, in /captain's template
# ------------------------------------------------------------------------------------------------
#
# The template is skills/captain/TEMPLATE.md; its headings are the names below, word for word, so
# this check and the reader find the same parts. Checked, and why: the title names the kind and the
# date (the deck's cover reads it); a `For:` line names the reader, whom the plain-words test needs;
# the five sections in order, the answer first; each option's four lines, of which the one most
# often dropped asks something of the captain; the best three, ranked; a D-list in the repo's
# shape. Whether the words are plain is the reader's test, never a lint.

REVIEW_SECTIONS = ("The answer", "Where things stand", "The options", "The best three", "Decisions")
OPTION_LINES = ("You get at the end", "It costs", "It needs from you", "The one risk")
REVIEW_KIND = re.compile(r"\((?:captain|executive) review\b", re.I)
REVIEW_TITLE = re.compile(r"^# .*\((?:captain|executive) review,\s*(\d{4}-\d{2}-\d{2})\)\s*$", re.I)
D_ITEM = re.compile(r"^\s*(?:[-*]|\d+\.)?\s*\*\*(?P<id>D\d+)\s+[—–-]\s")


def body_lines(text):
    """(line number, line) outside fences and HTML comments."""
    lines = text.split("\n")
    hidden = set()
    for a, b, _ in fences(lines):
        hidden |= set(range(a, b + 1))
    out, comment = [], False
    for i, raw in enumerate(lines):
        if i in hidden:
            continue
        if comment:
            comment = "-->" not in raw
            continue
        if raw.lstrip().startswith("<!--"):
            comment = "-->" not in raw
            continue
        out.append((i + 1, raw))
    return out


def is_review(text):
    title = next((raw for _, raw in body_lines(text) if raw.startswith("# ")), "")
    return bool(REVIEW_KIND.search(title))


def review_problems(text, name):
    lines = body_lines(text)
    out = []
    title = next((raw for _, raw in lines if raw.startswith("# ")), "")
    m = REVIEW_TITLE.match(title)
    if not (m and _date(m.group(1))):
        out.append(("review.title", f"{name}: the title ends `(captain review, <yyyy-mm-dd>)` or "
                                    "`(executive review, <yyyy-mm-dd>)`"))
    if not any(re.match(r"^For:\s*\S", raw) for _, raw in lines):
        out.append(("review.title", f"{name}: no `For:` line naming the reader"))
    sections, order, cur = {}, [], None
    for n, raw in lines:
        if raw.startswith("## "):
            cur = raw[3:].strip()
            order.append(cur)
            sections[cur] = []
        elif cur is not None:
            sections[cur].append((n, raw))
    for s in REVIEW_SECTIONS:
        if s not in sections:
            out.append(("review.sections", f"{name}: no `## {s}`"))
    present = [h for h in order if h in REVIEW_SECTIONS]
    if present != [s for s in REVIEW_SECTIONS if s in present]:
        out.append(("review.sections", f"{name}: sections out of order: {', '.join(present)}"))
    options = []
    for n, raw in sections.get("The options", []):
        if raw.startswith("### "):
            options.append((raw[4:].strip(), n, []))
        elif options:
            options[-1][2].append(raw)
    if "The options" in sections and not options:
        out.append(("review.options", f"{name}: The options holds no option (`### A — …`)"))
    for opt, n, body in options:
        joined = "\n".join(body)
        for label in OPTION_LINES:
            if not re.search(r"^\s*[-*]\s*\*\*%s:\*\*\s*\S" % re.escape(label), joined, re.M):
                out.append(("review.options", f"{name}:{n}: option {opt!r} has no `**{label}:**` line"))
    if "The best three" in sections:
        ranked = [raw for _, raw in sections["The best three"] if re.match(r"^\d+\.\s+\S", raw)]
        want = min(3, len(options)) if options else 3
        if len(ranked) != want:
            out.append(("review.options", f"{name}: The best three holds {len(ranked)} numbered items, want {want}"))
    if "Decisions" in sections:
        out += [("review.decisions", f"{name}: {msg}") for msg in _d_list(sections["Decisions"])]
    return out


def _d_list(lines):
    """Each D-item's block runs to the next item or the open-feedback line."""
    items, cur = [], None
    for n, raw in lines:
        m = D_ITEM.match(raw)
        if m:
            cur = (m.group("id"), n, [])
            items.append(cur)
        elif raw.startswith("Open feedback"):
            cur = None
        elif cur is not None:
            cur[2].append(raw)
    if not items:
        return ["no D-item (`- **D1 — …**`): a captain review asks the captain something"]
    out, seen = [], set()
    for did, n, body in items:
        if did in seen:
            out.append(f"{did} (line {n}): the id is used twice")
        seen.add(did)
        rev = [b for b in body if re.match(r"^\s*Reversible:", b)]
        if len(rev) != 1:
            out.append(f"{did} (line {n}): {len(rev)} `Reversible:` lines, want one")
        elif not re.match(r"^\s*Reversible:\s*(yes|no)\b", rev[0]):
            out.append(f"{did} (line {n}): `Reversible:` is yes or no")
        for marker in ("➤ Recommended:", "➤ Answer:"):
            k = sum(1 for b in body if b.strip().startswith(marker))
            if k != 1:
                out.append(f"{did} (line {n}): {k} `{marker}` lines, want one")
    return out


def published_links(md, cfg):
    """(render label, path, url or None, recorded) for each render of a document: the URL its sidecar
    holds, and whether the sidecar records that kind of render at all (a folder deck that is not the
    admiral, and the older single-file deck, are not published by the skill, so it has no key)."""
    sidecar = md.with_name(md.stem + cfg.naming["sidecar_suffix"])
    try:
        published = json.loads(sidecar.read_text(encoding="utf-8")).get("published") or {}
    except (OSError, ValueError, AttributeError):
        published = {}
    keys = {"admiral": "admiral_deck", "commodore": "commodore_deck", "memo": "memo"}
    labels = {"memo": "memo", "admiral": "admiral deck", "commodore": "commodore deck", "folder": "deck",
              "single": "single deck"}
    out = []
    # The memo first, as the skill publishes it; a deck by its folder, which is what a person names.
    for _, path, kind in sorted(renders(md.parent, cfg, md.stem), key=lambda r: list(labels).index(r[2])):
        entry = published.get(keys.get(kind, ""))
        url = entry.get("url") if isinstance(entry, dict) and _https(entry.get("url")) else None
        out.append((labels[kind], path.parent if kind in DECK_KINDS else path, url, kind in keys))
    return out
