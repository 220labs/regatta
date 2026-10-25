"""The core check's G4 harness (docs/orca-launcher-2026-10-24.md, S4): on PYTHONPATH, every python a
case starts loads it, and it logs each open() of a file under DRIVE_AUDIT_ROOT — the fixture's stand-in
for a shared drive — with the first frame outside the standard library, so a failure names the line.

Python's own audit event (`open`, 3.8+) is the ground truth: Path.read_text, open() and os.open all
raise it, in the hook and in every python the hook starts (they inherit PYTHONPATH). A stat that
follows a link is no open and is not seen. A python started with -I ignores PYTHONPATH and is not
seen either; none of the readers G4 lists is. Inert without both variables.
"""
import os
import sys

ROOT, LOG = os.environ.get("DRIVE_AUDIT_ROOT"), os.environ.get("DRIVE_AUDIT_LOG")

if ROOT and LOG:
    _root = os.path.realpath(ROOT)
    _stdlib = os.path.dirname(os.__file__)

    def _audit(event, args):
        if event != "open" or not args or isinstance(args[0], int):
            return
        try:
            real = os.path.realpath(os.fsdecode(args[0]))
        except (TypeError, ValueError):
            return
        if real != _root and not real.startswith(_root + os.sep):
            return   # the log's own open lands here too: it is outside the root
        f = sys._getframe(1)
        while f is not None and (f.f_code.co_filename.startswith(_stdlib) or f.f_code.co_filename == __file__):
            f = f.f_back
        where = f"{f.f_code.co_filename}:{f.f_lineno}" if f is not None else "?"
        with open(LOG, "a", encoding="utf-8") as out:
            out.write(f"{real} at {where}\n")

    sys.addaudithook(_audit)
