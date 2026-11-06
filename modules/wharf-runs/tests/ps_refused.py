#!/usr/bin/env python3
"""Run a Python tool as a sandboxed session on a Mac runs it: every `ps` it starts is refused at the exec,
PermissionError [Errno 1] Operation not permitted: 'ps' (the laptop's sandbox, 2026-11-04; /bin/ps is
setuid root). A PATH shim cannot stand in: a file there that cannot be exec'd makes Python try the next
PATH entry, and a real /bin/ps answers. So subprocess.Popen is wrapped in this process alone; the tool's
own children run as they would.
  python3 ps_refused.py <tool> [args…]
PS_REFUSED_LOG, when set, gets one line per refused call (its argv), so a case can show the walk was
reached rather than skipped (sandboxed-seed, docs/sandboxed-seed-2026-11-04.md). PS_REFUSED_BLANK, when set,
runs `true` in ps's place instead: a ps that answers nothing, as a loaded Mac's may for a live pid;
PS_REFUSED_BLANK=gone runs `false`: nothing and exit 1, ps's answer for no such process."""
import errno
import os
import runpy
import subprocess
import sys

_Popen = subprocess.Popen


def _argv(args):
    """ARGS as a list of strings: one str, bytes or path is one command line, as Popen reads it."""
    if isinstance(args, (str, bytes, os.PathLike)):
        return os.fsdecode(args).split()
    return [os.fsdecode(a) if isinstance(a, (str, bytes, os.PathLike)) else str(a) for a in args]


class _Refused(_Popen):
    def __init__(self, args, *a, **kw):
        argv = _argv(args)
        if argv and os.path.basename(argv[0]) == "ps":
            log = os.environ.get("PS_REFUSED_LOG")
            if log:
                with open(log, "a") as f:
                    f.write(" ".join(argv) + "\n")
            blank = os.environ.get("PS_REFUSED_BLANK")
            if blank:   # `gone`: a ps that answers nothing and exits 1, as for no such process
                return super().__init__(["false" if blank == "gone" else "true"], *a, **kw)
            raise PermissionError(errno.EPERM, os.strerror(errno.EPERM), "ps")
        super().__init__(args, *a, **kw)


subprocess.Popen = _Refused
tool = sys.argv[1]
sys.argv = sys.argv[1:]
sys.path[0] = os.path.dirname(os.path.abspath(tool))   # as `python3 <tool>` has it: its own folder, never tests/
runpy.run_path(tool, run_name="__main__")
