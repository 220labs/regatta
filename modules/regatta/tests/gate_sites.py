#!/usr/bin/env python3
"""Every gate call site the modules name, found by an AST walk, and whether each has a row in the module's table
under an empty config (a stranger's install). tests/gate_sites.sh runs it; it reads a checkout, writes nothing.

    python3 -I gate_sites.py scan <root>       one `<site>\\t<file>:<line>` per site found, sorted by site
    python3 -I gate_sites.py rows <root>       the same, then each site's row: `<site>\\t<kind/provider | off ... | no row | error>`

The walk (Evolve S11; the first cut was a regex probe, docs/self-improvement-2026-10-30/tools/gate_sites.py): a site
is a string constant in code, so a name in a comment or a docstring is none, and either quote reads alike. Found:
  - the first argument of a call to `resolve`, `classify`, `model_flags`, `review_provider`, `generate` or `label`
    (a plain name or an attribute: `gate.classify(...)`; `label` is the wrapper plumb's asks puts round classify);
  - a constant named with SITE or SHADOW (`CLASSIFY_SITE = "plan.stall"`), plain or annotated;
  - in a file that loads the core's gate (`SourceFileLoader("gate", ...)`, `import gate`, `tool("gate")`,
    `peer("gate")`, or a path ending `/ "bin" / "gate"`), the first string of a tuple (lighthouse's ops keeps
    its four rows in a dict of tuples).
A name is `<word>.<word>` in lowercase, dashes and dots allowed; a file name (`x.json`) and the gate's own
`example.` rows are no site. Python files only (a file whose first line names python, or `.py`); one that does not
parse is an error, never skipped, so a site cannot hide behind a syntax this Python lacks. Skipped: tests/,
__pycache__, the gate itself (its docstring and its example site are no caller). Out of the walk: a site built at
run time (wharf's council makes `council.<arm>` from its arms and reads it from wharf's own table; its suite,
test_council.sh, resolves all four). Python 3.9, stdlib.
"""
import ast
import json
import os
import re
import sys
import tempfile
from importlib.machinery import SourceFileLoader
from pathlib import Path

sys.dont_write_bytecode = True  # loading the gate must leave no __pycache__ in the checkout (AGENTS.md's trap)

NAME = re.compile(r"[a-z][a-z0-9-]*\.[a-z][a-z0-9.-]*")
CALLS = {"resolve", "classify", "model_flags", "review_provider", "generate", "label"}
CONST = re.compile(r"(?:[A-Z]+_)*(?:SITE|SHADOW)(?:_[A-Z]+)*")   # SITE_UP, CLASSIFY_SITE, SHADOW; not WEBSITE
FILE_EXT = re.compile(r"\.(?:json|jsonl|md|py|sh|txt|log|env|ya?ml|plist|toml|html|csv|lock"
                      r"|css|m?js|svg|png|jpe?g|gif|webp|ico|woff2?|pdf|xml|zip|gz|tar)$")   # keel's UI_FILES


def is_site(value):
    return isinstance(value, str) and NAME.fullmatch(value) and not FILE_EXT.search(value) and not value.startswith("example.")


def callee(node):
    f = node.func
    return f.id if isinstance(f, ast.Name) else f.attr if isinstance(f, ast.Attribute) else None


def str_arg(node, i=0):
    return node.args[i].value if len(node.args) > i and isinstance(node.args[i], ast.Constant) else None


def loads_gate(tree):
    for n in ast.walk(tree):
        if isinstance(n, ast.Call):
            c = callee(n)
            if c == "SourceFileLoader" and str_arg(n) == "gate":
                return True
            if c in ("tool", "peer") and str_arg(n) == "gate":
                return True
        elif isinstance(n, ast.Import) and any(a.name == "gate" for a in n.names):
            return True
        elif isinstance(n, ast.BinOp) and isinstance(n.op, ast.Div) and isinstance(n.right, ast.Constant) \
                and n.right.value == "gate" and isinstance(n.left, ast.BinOp) and isinstance(n.left.op, ast.Div) \
                and isinstance(n.left.right, ast.Constant) and n.left.right.value == "bin":
            return True
    return False


def sites_in(tree):
    """[(site, line)] in one parsed file."""
    out = []
    tuples = loads_gate(tree)
    for n in ast.walk(tree):
        if isinstance(n, ast.Call) and callee(n) in CALLS and is_site(str_arg(n)):
            out.append((str_arg(n), n.args[0].lineno))
        elif isinstance(n, (ast.Assign, ast.AnnAssign)):
            targets = n.targets if isinstance(n, ast.Assign) else [n.target]
            v = n.value
            if isinstance(v, ast.Constant) and is_site(v.value) \
                    and any(isinstance(t, ast.Name) and CONST.fullmatch(t.id) for t in targets):
                out.append((v.value, v.lineno))
        elif tuples and isinstance(n, ast.Tuple) and n.elts and isinstance(n.elts[0], ast.Constant) \
                and is_site(n.elts[0].value):
            out.append((n.elts[0].value, n.elts[0].lineno))
    return out


def py_files(root):
    gate = root / "modules/regatta/bin/gate"
    for d in sorted(root.glob("modules/*/*")):
        if d.name not in ("bin", "libexec", "hooks", "lib") or not d.is_dir():
            continue
        for f in sorted(d.rglob("*")):
            rel = f.relative_to(root)   # judged inside the checkout: one under a folder named tests skips nothing
            if not f.is_file() or "tests" in rel.parts or "__pycache__" in rel.parts or f == gate:
                continue
            try:
                text = f.read_text(encoding="utf-8")
            except (UnicodeDecodeError, OSError) as e:
                if f.suffix == ".py":   # a python file that does not read is an error, as one that does not parse
                    yield f, rel, e
                continue
            if f.suffix == ".py" or "python" in (text.split("\n", 1)[0] if text.startswith("#!") else ""):
                yield f, rel, text


def scan(root):
    """({site: 'file:line' of its first call, in file order}, [errors])."""
    found, errors = {}, []
    for f, rel, text in py_files(root):
        if isinstance(text, Exception):
            errors.append("%s: does not decode (%s)" % (rel, str(text).splitlines()[0][:80]))
            continue
        try:
            tree = ast.parse(text, filename=str(rel))
        except (SyntaxError, ValueError) as e:
            errors.append("%s: does not parse (%s)" % (rel, str(e).splitlines()[0][:80]))
            continue
        for site, line in sorted(sites_in(tree), key=lambda x: x[1]):
            found.setdefault(site, "%s:%d" % (rel, line))
    return found, errors


def rows(root, sites):
    """{site: 'kind/provider' | 'off (…)' | 'no row' | 'error: …'} under an empty config, every GATE_* cleared."""
    with tempfile.TemporaryDirectory() as cfg:
        os.environ["REGATTA_CONFIG"] = cfg
        for k in [k for k in os.environ if k.startswith("GATE_")]:   # GATE_TABLE and every GATE_<SITE>_<KEY>
            os.environ.pop(k)
        sys.path.insert(0, str(root / "modules/regatta/lib"))
        sys.path.insert(0, str(root / "modules/regatta/hooks"))
        gate = SourceFileLoader("gate", str(root / "modules/regatta/bin/gate")).load_module()
        out = {}
        for s in sorted(sites):
            try:
                r = gate.resolve(s)
                out[s] = "off (when_off skip)" if r is None else "%s/%s" % (r.get("kind"), r.get("provider"))
            except gate.GateOff:   # a row that is off with when_off fail: it exists
                out[s] = "off (when_off fail)"
            except gate.GateError as e:
                first = str(e).splitlines()[0]
                out[s] = "no row" if "no row for" in first else "error: " + first[:100]
            except Exception as e:  # noqa: BLE001 a crash is no missing row
                out[s] = "error: %s %s" % (type(e).__name__, str(e).splitlines()[0][:80] if str(e) else "")
        return out


def main(argv):
    if len(argv) != 3 or argv[1] not in ("scan", "rows"):
        print(__doc__.split("\n\n")[0], file=sys.stderr)
        return 2
    root = Path(argv[2]).resolve()
    found, errors = scan(root)
    for e in errors:
        print("ERROR\t" + e)
    if argv[1] == "scan":
        for s in sorted(found):
            print("%s\t%s" % (s, found[s]))
        return 1 if errors else 0
    for s, r in rows(root, found).items():
        print("%s\t%s\t%s" % (s, r, found[s]))
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
