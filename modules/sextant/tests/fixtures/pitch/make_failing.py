#!/usr/bin/env python3
"""Write <out>/<rule id>/: a copy of passing/ with one mutation that breaks exactly that rule, and
an expect.json naming the rule and anything that must fire beside it; and <out>/pitch.json, the
shared config each root finds above itself (a root that changes one setting extends it).

    python3 -I make_failing.py <out>          # tests/pitch.sh: <out> is a temp dir, never committed

`also` is honest about side effects, never a tolerance: a slide edited by hand is also a slide its
content file no longer generates, so a slide-level mutation lists `deck.generator-drift` beside its
own rule. tests/pitch_cases.py asserts each root fires exactly {rule} plus `also`.
"""
import json
import shutil
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.dont_write_bytecode = True
sys.path.insert(0, str(HERE.parents[2] / "bin"))      # modules/sextant/bin
import pitchlib as rf  # noqa: E402

PASSING = HERE / "passing"
STEM = "evening-hours-2026-01-12"
DRIFT = ["deck.generator-drift"]
CFG = rf.Config.load(HERE / rf.CONFIG_NAME)


def deck(root):
    return root / f"{STEM}-admiral-deck"


def slide_path(root, sid):
    return deck(root) / "project" / "slides" / f"{sid}.html"


def content(root):
    return json.loads((deck(root) / "slides.json").read_text(encoding="utf-8"))


def rewrite_slide(root, sid, **changes):
    """Render one slide from changed content and write the slide file only, as a hand edit would."""
    slides = content(root)
    i = next(k for k, s in enumerate(slides) if s["id"] == sid)
    slides[i] = dict(slides[i], **changes)
    slide_path(root, sid).write_text(rf.Look(CFG).slide_html(slides[i], i, len(slides)), encoding="utf-8")


def edit(path, old, new, count=1):
    text = path.read_text(encoding="utf-8")
    assert old in text, f"{old!r} not in {path}"
    path.write_text(text.replace(old, new, count), encoding="utf-8")


def config(root, data):
    (root / rf.CONFIG_NAME).write_text(json.dumps(dict({"extends": "../" + rf.CONFIG_NAME}, **data), indent=2)
                                       + "\n", encoding="utf-8")


def plain_folder_deck(root, furniture):
    """A non-admiral folder deck carrying the document's pinned phrases, with furniture(i) on slide i."""
    project = root / f"{STEM}-deck" / "project"
    (project / "slides").mkdir(parents=True)
    bodies = ["<h2>Evening hours for 12 weeks</h2><p>Open three evenings a week on $18K.</p>",
              "<h2>Members asked</h2><p>140 of 420 members asked for evenings.</p>",
              "<h2>The hire</h2><p>One coordinator at 20 hours a week.</p>"]
    ids = ["one", "two", "three"]
    for i, (sid, body) in enumerate(zip(ids, bodies)):
        (project / "slides" / f"{sid}.html").write_text(
            f'<section id="{sid}" style="background:#FFFFFF;color:#1F2430;padding:128px">{body}'
            f'{furniture(i)}<aside>n</aside></section>\n', encoding="utf-8")
    (project / "deck.json").write_text(json.dumps({"v": 4, "title": "Evening Hours", "order": ids}) + "\n",
                                       encoding="utf-8")


MONEY = "Most of it pays the coordinator"


def m_words(r):
    rewrite_slide(r, "money", statements=["$18K covers every single cost it brings",
                                          "Most of it pays our coordinator, hour by hour",
                                          "The rest covers lighting, keys, printed rotas"])


def m_statements(r):
    rewrite_slide(r, "money", statements=["$18K for the pilot", "Mostly the coordinator",
                                          "Then lighting", "Then the rota"])


def m_markup(r):
    edit(slide_path(r, "money"), "</h2>", "</h2>\n<table><tr><td>cell</td></tr></table>")


def m_note(r):
    rewrite_slide(r, "money", note="more " * 820)


def m_type(r):
    edit(slide_path(r, "money"), "font-size:68px", "font-size:48px")


def m_palette(r):
    edit(slide_path(r, "money"), "font-weight:700;letter-spacing", "color:#1A2B3C;font-weight:700;letter-spacing")


def m_contrast(r):
    edit(slide_path(r, "money"), "font-weight:700;letter-spacing", "color:#C9CED8;font-weight:700;letter-spacing")


def m_overfull(r):
    edit(slide_path(r, "money"), "</h2>", '</h2>\n<div style="width:120px;height:700px;background:#2F6FDB"></div>')


def m_lines(r):
    rewrite_slide(r, "money", statements=["$18K for the pilot",
                                          "Most of it pays our coordinator; remaining money buys lighting, "
                                          "keyholders, signage"])


def m_dangling(r):
    rewrite_slide(r, "money", statements=["$18K for the pilot", "Most of the money pays for the coordinator"])


def m_width(r):
    edit(slide_path(r, "money"), "width:1500px", "width:1700px")


def m_title(r):
    rewrite_slide(r, "money", headline="The opening hours")


def m_slide_count(r):
    slides = content(r)
    base = next(s for s in slides if s["id"] == "money")
    extra = [dict(base, id=f"more{i}") for i in range(1, 9)]
    slides = slides[:-1] + extra + slides[-1:]
    (deck(r) / "slides.json").write_text(json.dumps(slides, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    look = rf.Look(CFG)
    for i, s in enumerate(slides):
        slide_path(r, s["id"]).write_text(look.slide_html(s, i, len(slides)), encoding="utf-8")
    index_path = deck(r) / "project" / "deck.json"
    index = json.loads(index_path.read_text(encoding="utf-8"))
    index["order"] = [s["id"] for s in slides]
    index_path.write_text(json.dumps(index, indent=2) + "\n", encoding="utf-8")


def m_number(r):
    rewrite_slide(r, "money", note="About $15K pays the coordinator.")


def m_exemption(r):
    config(r, {"admiral": {"headline_exempt": {f"{STEM}/gone": "a slide that was cut, its exemption left behind"}}})


def m_index(r):
    index_path = deck(r) / "project" / "deck.json"
    index = json.loads(index_path.read_text(encoding="utf-8"))
    index["order"].append("ghost")
    index_path.write_text(json.dumps(index, indent=2) + "\n", encoding="utf-8")


def m_drift(r):
    edit(slide_path(r, "money"), MONEY, "Most of it pays our coordinator")


def m_page_number(r):
    plain_folder_deck(r, lambda i: f'<p style="position:absolute;font-size:24px">{i + 1} / 3</p>')


def m_caption(r):
    plain_folder_deck(r, lambda i: '<p style="font-size:24px">Evening hours · pilot</p>')


def m_deck_external(r):
    index_path = deck(r) / "project" / "deck.json"
    index = json.loads(index_path.read_text(encoding="utf-8"))
    index["faces"]["body"]["href"] = "https://example.com/face.css"
    index_path.write_text(json.dumps(index, indent=2) + "\n", encoding="utf-8")


def memo(r):
    return r / f"{STEM}-memo.html"


def single(r):
    return r / f"{STEM}-deck.html"


def m_captain_floor(r):
    edit(memo(r), ".muted { color: var(--muted); font-size: 16px; }", ".muted { color: var(--muted); font-size: 12px; }")


def m_allowlist(r):
    edit(memo(r), "</body>", '<script src="https://example.com/a.js"></script>\n</body>')


def m_single_external(r):
    edit(single(r), 'document.getElementById("deck")', 'fetch("facts.json");\ndocument.getElementById("deck")')


def m_marker(r):
    edit(single(r), "<!-- the cover: the answer first -->", "// the cover: the answer first")


def m_must_appear(r):
    edit(memo(r), "140 of 420", "a third of the", count=-1)


def m_retired(r):
    edit(r / f"{STEM}.md", "## Where things stand", "The library opens every evening from week 1.\n\n## Where things stand")


def m_table(r):
    config(r, {"claims": {"must_appear": {"ghost-2026-01-01": ["a phrase nothing carries"]}}})


def m_orphan(r):
    (r / "stray-memo.html").write_text("<!doctype html><title>Stray</title><p>No document names me.</p>\n",
                                       encoding="utf-8")


def m_vacuous(r):
    for p in sorted(r.iterdir()):
        if p.suffix != ".md":
            shutil.rmtree(p) if p.is_dir() else p.unlink()
    # Its own config: the shared one pins phrases and an exemption for renders this root no longer has.
    (r / rf.CONFIG_NAME).write_text(json.dumps({"palette": {"allowed": ["#FFFFFF", "#1F2430"]}}) + "\n",
                                    encoding="utf-8")


def m_sidecar(r):
    # A deck recorded with no type_url and a date that is no date: the next publish could not find
    # the artifact to update. One setting, as every fixture here: the sidecar's shape.
    sidecar = r / f"{STEM}.pitch.json"
    data = json.loads(sidecar.read_text(encoding="utf-8"))
    del data["published"]["admiral_deck"]["type_url"]
    data["published"]["memo"]["first_published"] = "last Tuesday"
    sidecar.write_text(json.dumps(data, indent=1) + "\n", encoding="utf-8")


CASES = [
    ("admiral.words", m_words, DRIFT),
    ("admiral.statements", m_statements, DRIFT),
    ("admiral.markup", m_markup, DRIFT),
    ("admiral.runtime-limits", m_note, DRIFT),
    ("admiral.type-floor", m_type, DRIFT),
    ("admiral.palette", m_palette, DRIFT),
    ("admiral.contrast", m_contrast, DRIFT),
    ("admiral.fit.overfull", m_overfull, DRIFT),
    ("admiral.fit.lines", m_lines, DRIFT),
    ("admiral.fit.dangling", m_dangling, DRIFT),
    ("admiral.fit.width", m_width, DRIFT),
    ("admiral.title", m_title, DRIFT),
    ("admiral.slide-count", m_slide_count, DRIFT),
    ("admiral.invented-number", m_number, DRIFT),
    ("admiral.exemption-stale", m_exemption, []),
    ("deck.index", m_index, []),
    ("deck.generator-drift", m_drift, []),
    ("deck.page-number", m_page_number, []),
    ("deck.running-caption", m_caption, []),
    ("deck.external", m_deck_external, []),
    ("captain.type-floor", m_captain_floor, []),
    ("captain.allowlist", m_allowlist, []),
    ("single.external", m_single_external, []),
    ("single.authoring-marker", m_marker, []),
    ("claims.must-appear", m_must_appear, []),
    ("claims.retired", m_retired, []),
    ("claims.table", m_table, []),
    ("root.orphan", m_orphan, []),
    ("root.vacuous", m_vacuous, []),
    ("sidecar.shape", m_sidecar, []),
]


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: make_failing.py <out>   (a new or empty folder outside the repo)")
    out = Path(sys.argv[1]).resolve()
    if out.exists() and any(out.iterdir()):
        sys.exit(f"{out} is not empty")
    out.mkdir(parents=True, exist_ok=True)
    shutil.copy(HERE / rf.CONFIG_NAME, out / rf.CONFIG_NAME)
    for rule, mutate, also in CASES:
        root = out / rule
        shutil.copytree(PASSING, root)
        mutate(root)
        (root / "expect.json").write_text(json.dumps({"rule": rule, "also": also}) + "\n", encoding="utf-8")
    print(f"{len(CASES)} failing fixtures written under {out}")


if __name__ == "__main__":
    main()
