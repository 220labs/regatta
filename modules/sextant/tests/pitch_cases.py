#!/usr/bin/env python3
"""pitch's cases, stdlib only: tests/pitch.sh runs this after make_failing.py has written the failing
roots into a temp dir.

    python3 -I pitch_cases.py <failing-dir>

Three groups, as the export's pytest suite had them (152 tests there, the same substance here):
  renders   the passing root holds every rule, every finding names a known rule, there is something
            to check;
  fixtures  the passing root is clean, every rule id has a failing root, and each failing root fires
            exactly its rule plus what its expect.json names;
  controls  the rules module alone, each rule against a slide made in place to fail it (the 90
            parametrised cases, as loops).
Then the CLI: `pitch check` on a root and on one document, `--json`, `pitch build` writing, refusing
and comparing. One line per case, `ok` or `FAIL`; exit 1 on any failure.
"""
import contextlib
import importlib.machinery
import importlib.util
import io
import json
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
BIN = HERE.parent / "bin"
sys.path.insert(0, str(BIN))
import pitchlib as pl  # noqa: E402

PITCH = BIN / "pitch"
FIXTURES = HERE / "fixtures" / "pitch"
PASSING = FIXTURES / "passing"
STEM = "evening-hours-2026-01-12"
FAILED, RAN = [], []


def case(name, fn, *args):
    RAN.append(name)
    try:
        fn(*args)
        print(f"  ok   {name}")
    except AssertionError as e:
        FAILED.append(name)
        print(f"  FAIL {name}: {e}")
    except Exception as e:      # a crash is a failure of its case, never of the run
        FAILED.append(name)
        print(f"  FAIL {name}: {type(e).__name__}: {e}")


def rules(problems):
    return {r for r, _ in problems}


_CHECKED = {}


def checked(root):
    """check_root once per root: each admiral root runs the builder as a subprocess, about half a
    second on a loaded Mac, and three groups read the same roots."""
    if root not in _CHECKED:
        _CHECKED[root] = pl.check_root(root, pl.find_config(root))
    return _CHECKED[root]


def pitch(*args):
    """`pitch` as a person runs it: its own process, its shebang's interpreter flags."""
    return subprocess.run([sys.executable, "-I", str(PITCH), *map(str, args)], capture_output=True, text=True)


_CLI = None


def run(*args):
    """`pitch` in this process, through its own main(): the same parsing and exits, without a
    second interpreter start per case (a quarter of a second each on a loaded Mac)."""
    global _CLI
    if _CLI is None:
        loader = importlib.machinery.SourceFileLoader("pitch_cli", str(PITCH))
        _CLI = importlib.util.module_from_spec(importlib.util.spec_from_loader("pitch_cli", loader))
        loader.exec_module(_CLI)
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        try:
            code = _CLI.main([str(a) for a in args])
        except SystemExit as e:     # argparse's 2, or sys.exit("message"): Python prints it, exits 1
            code = e.code if isinstance(e.code, int) else 1
            if isinstance(e.code, str):
                print(e.code, file=sys.stderr)
    return subprocess.CompletedProcess(args, code, out.getvalue(), err.getvalue())


# ------------------------------------------------------------------------------------------------
# renders: the passing root holds the method, one case per rule
# ------------------------------------------------------------------------------------------------

def group_renders():
    print("renders — the passing root, one case per rule")
    findings = checked(PASSING)

    def holds(rule):
        hits = [m for r, m in findings if r == rule]
        assert not hits, f"{rule}: " + "; ".join(hits)
    for rule in pl.RULES:
        case(f"{rule} holds", holds, rule)

    def known():
        unknown = sorted(rules(findings) - set(pl.RULES))
        assert not unknown, f"findings with no entry in RULES: {unknown}"
    case("every finding carries a known rule", known)

    def something():
        # Without this the suite would pass by finding nothing: renaming a deck once made every
        # case skip with exit 0.
        assert {k for _, _, k in pl.renders(PASSING, pl.find_config(PASSING))}, f"no renders under {PASSING}"
    case("there is something to check", something)


# ------------------------------------------------------------------------------------------------
# fixtures: every rule has a root built to fail it, and fires exactly there
# ------------------------------------------------------------------------------------------------

def uncovered(rule_ids, failing):
    covered = {json.loads((p / "expect.json").read_text())["rule"] for p in failing}
    return sorted(set(rule_ids) - covered)


def group_fixtures(failing_dir):
    print("fixtures — each failing root fires exactly its rule")
    failing = sorted(p for p in failing_dir.iterdir() if p.is_dir())

    def clean():
        found = checked(PASSING)
        assert not found, "; ".join(f"{r} {m}" for r, m in found)
    case("the passing fixtures are clean", clean)

    def every_rule():
        missing = uncovered(pl.RULES, failing)
        assert not missing, f"rules with no failing fixture: {missing}"
    case("every rule has a failing fixture", every_rule)

    def the_gap_is_seen():
        # The case above is itself checked: a rule id added to RULES with no fixture must fail it.
        assert uncovered(pl.RULES + ("admiral.unfixtured",), failing) == ["admiral.unfixtured"]
        assert uncovered(pl.RULES, failing[1:]) == [json.loads((failing[0] / "expect.json").read_text())["rule"]]
    case("  …and fails on a rule id with no fixture", the_gap_is_seen)

    def fires_exactly(root):
        expect = json.loads((root / "expect.json").read_text())
        got = rules(checked(root))
        assert got == {expect["rule"], *expect["also"]}, f"expected {expect}, fired {sorted(got)}"
    for root in failing:
        case(f"failing/{root.name} fires exactly its rule", fires_exactly, root)

    def all_known():
        unknown = set()
        for root in failing:
            unknown |= rules(checked(root)) - set(pl.RULES)
        assert not unknown, f"findings with no entry in RULES: {sorted(unknown)}"
    case("every failing root's findings carry known rules", all_known)


# ------------------------------------------------------------------------------------------------
# controls: the rules module alone, against slides made in place
# ------------------------------------------------------------------------------------------------

H2 = '<h2 style="font-size:104px;line-height:1.05;font-weight:800;width:1560px">{}</h2>'
P = '<p style="font-size:68px;line-height:1.25;font-weight:700;width:1500px{}">{}</p>'

TOPICS = [
    # Topic titles: a noun phrase with no verb, or a wh-label.
    "Where things stand", "The shortfall", "What members get", "Next week", "The schedule", "The budget",
    "What this cannot show", "The first month", "Our history",
    # Shapes that got past earlier versions of the heuristic.
    "The costs", "Changes", "Test results", "Known risks", "Status: where things stand", "Booking status",
    "Test runs", "Rota changes", "Rent costs", "Open bookings", "Shift swaps", "Key needs",
    "Risks and asks", "Status check", "Progress check", "Decisions to make", "To-do list",
    "Must-have features", "Money left", "Venue costs", "Budget changes", "Project needs",
]
MESSAGES = [
    "The coordinator starts in week 1", "Two evenings cost less than three", "Is the rota fair to volunteers?",
    "Members want the doors open later", "Nobody has kept an evening count", "Saturday visits beat Sunday visits",
    "Make the sign-up sheet the first step", "Volunteers will cover the weekends", "Survey results matter",
    "Members need a second key-safe", "Prices dropped by half", "The keys shipped last week",
    "Shipping stopped in week 3", "No visitor has come in the evening yet",
]
UNMODELLED = [
    '<p style="font:700 24px Arial">shorthand</p>',
    '<p style="font-size:68px;transform:scale(0.5)">scaled</p>',
    '<div style="background:linear-gradient(180deg, #000000, #000000)"><p style="font-size:68px">x</p></div>',
    '<p style="font-size:68px;opacity:0.15">faded</p>',
    '<p style="font-size:68px">two<br>lines</p>',
    '<div style="display:grid"><p style="font-size:68px">x</p></div>',
    '<p style="font-size:68px;position:absolute">pinned</p>',
    '<div style="max-width:600px"><p style="font-size:68px">x</p></div>',
    '<div>bare text in a div</div>',
    H2.format("A second title states it"),
    '<table><tr><td>cell</td></tr></table>',
    '<p style="font-size:68px;color:Pink">named</p>',
    '<p style="font-size:68px">big <b style="font-size:20px">small print</b></p>',
    '<p style="font-size:68px">big<p style="font-size:68px">nested</p></p>',
    '<div><b>text in a b straight inside a div</b></div>',
    '<p style="font-size:12px" style="font-size:68px">duplicate style</p>',
    '<p style="font-size:12px !important;font-size:68px">important</p>',
    '<div style="display:flex;flex-direction:column;gap:-300px"><p style="font-size:68px">x</p></div>',
    '<p style="font-size:68px;width:4000px">too wide</p>',
    '<p style="font-size:68px;height:20px">clipped</p>',
    '<p style="font-size:68px;flex:0">squeezed</p>',
    '<p style="font-size:68px;letter-spacing:-40px">crushed</p>',
    '<p style="font-size:68px;line-height:0">stacked</p>',
    '<p style="font-size:68px;border:300px solid #000000">bordered</p>',
    '<div style="font-size:20px"/><p style="font-size:68px">self-closed</p>',
    '<p>no size of its own</p>',
    '<p style="font-size:1.5rem">rem</p>',
    '<p style="font-size:68px;width:50%">percent</p>',
]


def group_controls(cfg):
    print("controls — each rule against a slide made to fail it")
    ink, paper = cfg.layout["ink"], cfg.layout["paper"]

    def made(body, section_style=None):
        style = section_style or (f"background:{paper};color:{ink};font-family:'{cfg.face_family}', Arial;"
                                  f"padding:{cfg.margin}px;display:flex;flex-direction:column;gap:72px")
        return pl.Slide(f'<section id="t" style="{style}">{body}<aside>n</aside></section>', "made.html")

    def topic(title):
        assert pl.headline_problem(title), f"{title!r} passed as a message"
    for t in TOPICS:
        case(f"the title rule refuses a topic: {t!r}", topic, t)

    def message(title):
        assert pl.headline_problem(title) is None, pl.headline_problem(title)
    for t in MESSAGES:
        case(f"the title rule passes a message: {t!r}", message, t)

    def extra_verbs():
        assert pl.headline_problem("Hire the coordinator this week") is not None
        assert "hire" in cfg.verbs, "the fixture config's extra_verbs should add hire"
        assert pl.headline_problem("Hire the coordinator this week", cfg) is None
    case("extra_verbs extend the lexicon", extra_verbs)

    def wcag():
        assert round(pl.contrast("#000000", "#ffffff"), 2) == 21.0
        assert round(pl.contrast("#767676", "#ffffff"), 2) == 4.54     # the familiar AA grey
        assert round(pl.contrast("#ffffff", "#ffffff"), 2) == 1.0
    case("contrast is WCAG arithmetic", wcag)

    def faint():
        faint_text = made(H2.format("The budget is enough") + P.format(";color:#E8E8E8", "faint"))
        faint_mark = made(H2.format("The budget is enough")
                          + '<div style="width:40px;height:40px;background:#F4F4F4"></div>')
        assert "admiral.contrast" in rules(pl.contrast_problems(faint_text, cfg))
        assert pl.contrast_problems(faint_mark, cfg)
        assert not pl.contrast_problems(made(H2.format("The budget is enough")), cfg)
    case("the contrast check refuses faint text and faint marks", faint)

    def overfull():
        rows = "".join(P.format("", "A rota takes about a fortnight") for _ in range(7))
        assert "admiral.fit.overfull" in rules(pl.geometry_problems(made(H2.format("The budget is enough") + rows), cfg))
        long = P.format("", "This statement goes on and on well past the two lines that any statement "
                            "may take on one slide at all")
        assert "admiral.fit.lines" in rules(pl.geometry_problems(made(H2.format("The budget is enough") + long), cfg))
    case("the geometry check refuses an overfull slide and a three-line statement", overfull)

    def dangling():
        # A 720 px box puts "a" at the end of a line with room to spare either side under the 0.6 em
        # fallback; with a measured face, re-pick the width so the case does not rest on the margin.
        narrow = '<h2 style="font-size:104px;line-height:1.05;font-weight:800;width:720px">{}</h2>'
        loose = made(narrow.format("Keep a small fee"))
        tied = made(narrow.format(f"Keep a{pl.NBSP}small fee"))
        assert "admiral.fit.dangling" in rules(pl.geometry_problems(loose, cfg))
        assert "admiral.fit.dangling" not in rules(pl.geometry_problems(tied, cfg))
        assert len(tied.words) == 4, "a no-break space still separates two words for the count"
    case("the geometry check refuses an article at a line end and honours a no-break space", dangling)

    def statement_count():
        # One list item once hid six paragraphs, because the count took items *or* paragraphs.
        s = made(H2.format("Members need a second key-safe") + "<ul><li>one</li></ul>" + "<p>x</p>" * 6)
        assert len(s.statements) == 7, len(s.statements)
    case("the statement count sums every kind of block", statement_count)

    def less_than():
        # `n < 50` in a note once swallowed the rest of a slide for a greedy tag pattern.
        s = made(H2.format("The budget is enough") + P.format("", "spent n < 50 of 7 and 2,400"))
        assert {"50", "7", "2,400"} <= s.figures, s.figures
    case("a bare less-than sign hides nothing", less_than)

    def unit(size):
        assert pl.type_problems(made(f'<p style="font-size:{size}">x</p>'), cfg), f"font-size {size} passed"
    for size in ("1.5rem", "24pt", "59.5px", "4vh"):
        case(f"type in any unit but px is refused: {size}", unit, size)

    def unstyled():
        # It renders at the runtime's 32 px default, which a scan of declared sizes never saw.
        found = pl.type_problems(made(H2.format("The rota needs one more name") + "<p>small</p>"), cfg)
        assert any("32px" in m for _, m in found), found
    case("an unstyled paragraph is held to the floor", unstyled)

    def unmodelled(markup):
        assert pl.problems(made(H2.format("The rota needs one more name") + markup), "k/t", cfg), f"passed: {markup}"
    for i, markup in enumerate(UNMODELLED, 1):
        case(f"markup the estimate does not model is refused ({i}): {markup[:48]}", unmodelled, markup)

    def margin():
        s = made(H2.format("The rota needs one more name"), section_style="background:#FFFFFF;color:#000000;padding:0")
        assert any("margin" in m for _, m in pl.markup_problems(s, cfg))
    case("a section without the margin is refused", margin)

    def magnitude():
        doc = pl.numbers("The budget is $250K and 12 rooms.", with_bare=True)
        assert "250M" not in doc and "250K" in doc and "250" in doc
        for spelled in ("$250M", "$250m", "$250 million", "$0.25bn"):
            figures = made(H2.format("The budget is enough") + P.format("", spelled)).figures
            assert figures - doc, f"{spelled} matched the document's $250K"
        assert pl.numbers("$250 thousand") == pl.numbers("$250k") == {"250K"}
    case("a number keeps its magnitude", magnitude)

    def entity():
        s = made(H2.format("The rota needs one more name") + P.format("", "a&#160;b &#8217;"))
        assert not pl.colour_problems(s, cfg)
    case("an entity is not read as a colour", entity)

    def short_slide():
        # A <section> under 400 characters once matched whole and hid the furniture inside it.
        short = ('<section id="a" style="background:#FFFFFF"><h2>Hi</h2>'
                 '<p style="position:absolute;font-size:24px">3 / 9</p><aside>n</aside></section>')
        assert ("3 / 9", True) in pl.furniture_texts(short, cfg)
    case("a short slide still shows its page number", short_slide)

    def js_scan():
        assert pl.split_js("const a = `unclosed") is None
        templates, strings = pl.split_js('const s = ["x"]; const t = `<p>${s.map(v => `<b>${v}</b>`)}</p>`;')
        assert "x" in strings and any("<p>" in t for t in templates)
    case("the JS scan reports what it cannot pair", js_scan)


# ------------------------------------------------------------------------------------------------
# the CLI: check a root and a document, build, refuse
# ------------------------------------------------------------------------------------------------

def group_cli(failing_dir, scratch):
    print("cli — pitch check and pitch build")
    # Copies of a fixture root live under work/, beside the shared config they find above them;
    # scratch/ itself holds none, for the case that proves the old config name is not read.
    work = scratch / "work"
    work.mkdir()
    shutil.copy(FIXTURES / "pitch.json", work / "pitch.json")

    def root_clean():
        r = pitch("check", PASSING)
        assert r.returncode == 0 and r.stdout.strip().endswith("0 finding(s)"), r.stdout + r.stderr
        r = pitch("check", PASSING, "--json")
        assert r.returncode == 0 and json.loads(r.stdout) == [], r.stdout + r.stderr
    case("check <root>: a clean root exits 0, --json prints []", root_clean)

    def doc_clean():
        r = run("check", PASSING / f"{STEM}.md")
        assert r.returncode == 0, r.stdout + r.stderr
    case("check <doc>: a clean document exits 0", doc_clean)

    def root_finding():
        r = run("check", failing_dir / "admiral.words", "--json")
        got = {f["rule"] for f in json.loads(r.stdout)}
        assert r.returncode == 1 and got == {"admiral.words", "deck.generator-drift"}, (r.returncode, got)
    case("check <root>: a finding exits 1 and names its rule", root_finding)

    def doc_finding():
        r = run("check", failing_dir / "captain.allowlist" / f"{STEM}.md", "--json")
        got = {f["rule"] for f in json.loads(r.stdout)}
        assert r.returncode == 1 and got == {"captain.allowlist"}, (r.returncode, got)
    case("check <doc>: a finding in the document's render exits 1", doc_finding)

    def doc_scoped():
        # An orphan belongs to the root, not to any one document: the document's check passes it.
        root = failing_dir / "root.orphan"
        assert run("check", root).returncode == 1
        r = run("check", root / f"{STEM}.md")
        assert r.returncode == 0, r.stdout + r.stderr
    case("check <doc>: what belongs to the root alone is left to the root's check", doc_scoped)

    def doc_alone():
        # Two documents in one root: one's broken render is not the other's finding.
        root = work / "two"
        shutil.copytree(failing_dir / "captain.type-floor", root)
        (root / "other-2026-01-13.md").write_text("# Other\n\nNothing rendered yet.\n", encoding="utf-8")
        assert run("check", root / f"{STEM}.md").returncode == 1
        r = run("check", root / "other-2026-01-13.md", "--json")
        got = {f["rule"] for f in json.loads(r.stdout)}
        assert r.returncode == 1 and got == {"root.vacuous"}, (r.returncode, got)
    case("check <doc>: another document's finding is not this one's; a document with no render is vacuous", doc_alone)

    def not_a_doc():
        r = run("check", PASSING / f"{STEM}-memo.html")
        assert r.returncode == 2 and "not a document" in r.stderr, r.stderr
        r = run("check", scratch / "nowhere")
        assert r.returncode == 2 and "no such" in r.stderr, r.stderr
    case("check exits 2, never a finding's 1, on a file that is not a document or a path not there", not_a_doc)

    def doc_own_orphan():
        # The document's own admiral folder with no project/ is no render: its check must not pass.
        root = work / "unbuilt"
        shutil.copytree(PASSING, root)
        shutil.copy(FIXTURES / "pitch.json", root / "pitch.json")
        cfg = json.loads((root / "pitch.json").read_text(encoding="utf-8"))
        cfg.get("admiral", {}).pop("headline_exempt", None)
        cfg.get("claims", {}).pop("admiral_must_appear", None)
        (root / "pitch.json").write_text(json.dumps(cfg), encoding="utf-8")
        shutil.rmtree(root / f"{STEM}-admiral-deck" / "project")
        r = run("check", root / f"{STEM}.md", "--json")
        got = {f["rule"] for f in json.loads(r.stdout)}
        assert r.returncode == 1 and "root.orphan" in got, (r.returncode, got, r.stderr)
    case("check <doc>: the document's own deck folder with no project/ is an orphan", doc_own_orphan)

    def crash_exits_2():
        root = work / "crash"
        shutil.copytree(PASSING, root)
        money = root / f"{STEM}-admiral-deck" / "project" / "slides" / "money.html"
        money.write_text(money.read_text(encoding="utf-8") + "<section></section>\n", encoding="utf-8")
        r = run("check", root)
        assert r.returncode == 2, (r.returncode, r.stdout[-300:], r.stderr[-300:])
        (work / "plan-deck").mkdir()
        r = run("build", work / "plan-deck")
        assert r.returncode == 2 and "not an admiral deck" in r.stderr, (r.returncode, r.stderr)
    case("check exits 2 when it crashes on a render; build exits 2 on a folder that is not an admiral deck", crash_exits_2)

    def config_name():
        # The config is pitch.json; the export's old name is not read.
        root = scratch / "renamed"
        shutil.copytree(PASSING, root)
        shutil.copy(FIXTURES / "pitch.json", root / "render.config.json")
        r = run("check", root)
        assert r.returncode == 2 and "no pitch.json" in r.stderr, r.stdout + r.stderr
        r = run("check", root, "--config", FIXTURES / "pitch.json")
        assert r.returncode == 0, r.stdout + r.stderr
    case("check finds pitch.json, never render.config.json; --config names one", config_name)

    def build_check():
        r = run("build", PASSING / f"{STEM}-admiral-deck", "--check")
        assert r.returncode == 0 and "5 slides match" in r.stdout, r.stdout + r.stderr
        r = run("build", PASSING / f"{STEM}.md", "--check")
        assert r.returncode == 0, r.stdout + r.stderr
    case("build --check: the passing deck matches its content file, by deck or by document", build_check)

    def build_drift():
        r = run("build", failing_dir / "deck.generator-drift" / f"{STEM}-admiral-deck", "--check")
        assert r.returncode == 1 and "money" in r.stderr, r.stdout + r.stderr
    case("build --check: a slide edited by hand exits 1 and names it", build_drift)

    def build_writes():
        root = work / "write"
        shutil.copytree(PASSING, root)
        slides = root / f"{STEM}-admiral-deck" / "project" / "slides"
        want = (slides / "money.html").read_text(encoding="utf-8")
        (slides / "money.html").unlink()
        r = run("build", root / f"{STEM}-admiral-deck")
        assert r.returncode == 0 and "5 slides written" in r.stdout, r.stdout + r.stderr
        assert (slides / "money.html").read_text(encoding="utf-8") == want, "the rebuilt slide differs"
    case("build: writes the deck's slides from its content file", build_writes)

    def build_refuses():
        root = work / "refuse"
        shutil.copytree(PASSING, root)
        deck = root / f"{STEM}-admiral-deck"
        content = json.loads((deck / "slides.json").read_text(encoding="utf-8"))
        money = next(s for s in content if s["id"] == "money")
        money["statements"] = ["$18K covers every single cost it brings",
                                    "Most of it pays our coordinator, hour by hour",
                                    "The rest covers lighting, keys, printed rotas"]
        (deck / "slides.json").write_text(json.dumps(content), encoding="utf-8")
        before = {p.name: p.read_text(encoding="utf-8") for p in (deck / "project" / "slides").glob("*.html")}
        r = run("build", deck)
        assert r.returncode == 1 and "refused, nothing written" in r.stderr and "words on screen" in r.stderr, r.stderr
        after = {p.name: p.read_text(encoding="utf-8") for p in (deck / "project" / "slides").glob("*.html")}
        assert after == before, "a refused build changed a slide"
    case("build: a slide that breaks a rule refuses the whole deck, nothing written", build_refuses)

    def build_stale():
        root = work / "stale"
        shutil.copytree(PASSING, root)
        slides = root / f"{STEM}-admiral-deck" / "project" / "slides"
        shutil.copy(slides / "money.html", slides / "gone.html")
        r = run("build", root / f"{STEM}-admiral-deck")
        assert r.returncode == 1 and "gone" in r.stderr, r.stderr
    case("build: a slide file the content no longer defines is refused", build_stale)

    def usage():
        assert pitch().returncode == 2
        assert pitch("bogus").returncode == 2
        r = pitch("--help")
        assert r.returncode == 0 and "check" in r.stdout and "build" in r.stdout, r.stdout
    case("usage: no verb or an unknown one exits 2; --help names both verbs", usage)


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: pitch_cases.py <failing-dir>")
    failing_dir = Path(sys.argv[1]).resolve()
    started = time.monotonic()
    cfg = pl.find_config(PASSING)
    with tempfile.TemporaryDirectory() as scratch:
        for group, args in ((group_renders, ()), (group_fixtures, (failing_dir,)), (group_controls, (cfg,)),
                            (group_cli, (failing_dir, Path(scratch)))):
            t = time.monotonic()
            group(*args)
            print(f"  ({time.monotonic() - t:.1f}s)")
    took = time.monotonic() - started
    print(f"{len(FAILED)} of {len(RAN)} failed in {took:.1f}s" if FAILED else f"all {len(RAN)} passed in {took:.1f}s")
    return 1 if FAILED else 0


if __name__ == "__main__":
    sys.exit(main())
