"""The regatta core and its peers for the benches (regatta-modules G37), stdlib, Python 3.9.

The benches loaded jev, memo, keel and session_status by `<this file>/../../bin/<name>`, which
holds only while bench/ sits beside bin/ in one checkout. Every such load goes through the core's
`common.tool()` instead, so a bench runs the same from the overlay and from regatta's plumb
module, and a missing peer is one line naming its module, never a FileNotFoundError at the start.
"""
import os
import sys

BENCH = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(BENCH)   # the overlay's checkout, or modules/plumb
MODULE = {"jev": "the regatta core", "memo": "keel", "keel": "keel", "session_status.py": "wharf"}


def common():
    """The core's common module: through lib/find_core.py in the plumb module, else hooks/ beside
    bin/ (the overlay, whose common.py is the core's source shim)."""
    lib = os.path.join(ROOT, "lib")
    if os.path.isfile(os.path.join(lib, "find_core.py")):
        if lib not in sys.path:
            sys.path.insert(0, lib)
        import find_core
        sys.path.insert(0, find_core.hooks())
    else:
        sys.path.insert(0, os.path.join(ROOT, "hooks"))
    import common as c
    return c


def data(name):
    """A bench's data folder, outside git: bench/<name> in the core's log dir (`regatta/log-dir`)."""
    return os.path.join(str(common().LOG_DIR), "bench", name)


def projects():
    """The projects folder repos are named under: the core's `regatta/projects`."""
    return str(common().PROJECTS)


def guarded():
    """The repos whose text never leaves the Mac, in order: jev's list (`regatta/guarded`), then the
    registry's `guarded`. Never a literal here: the names are the owner's (regatta's AGENTS.md)."""
    c = common()
    out = list(c.config_lines("regatta/guarded") or [])
    return tuple(out + [g for g in c.guarded_repos() if g not in out])


def find(name):
    """The peer's path, or None."""
    p = common().tool(name)
    return str(p) if p else None


def need(name):
    """The peer's path, or exit 2 with the one line that names its module."""
    p = find(name)
    if not p:
        print("%s: needs %s (%s), not installed" % (os.path.basename(sys.argv[0] or "bench"), name,
                                                    MODULE.get(name, "its module")), file=sys.stderr)
        sys.exit(2)
    return p
