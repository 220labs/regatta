"""launcherlib — the one home of the claude-host launcher rule.

The rule: ask `rc-hosts --launcher <prog>`; an answer is a launcher only when it is an executable
file, and then the job runs `[claude-host, prog, …argv]`; any other answer (non-zero exit, nothing
printed, a path that is not an executable, no answer in 30 s) means "bare": the program as it is.
rc-hosts decides in-process (`through`), clock's plists and helm's skipper runner ask it over the
command line (`ask`) and build the argv with `through` here, so the three cannot drift apart.

A peer file of wharf-runs, loaded through the core's tool lookup (helm: `helmlib.peer("launcherlib.py")`)
or from beside the caller. Stdlib, Python 3.9; imports nothing of regatta.
"""
import os
import subprocess
import sys
from pathlib import Path

ASK_TIMEOUT = 30   # rc-hosts probes the build in place (claude-host --version, 10 s); a wedged one is bare


def executable(path):
    """True for a path that is an executable file (a directory or a dangling link is not)."""
    try:
        return bool(path) and Path(path).is_file() and os.access(str(path), os.X_OK)
    except (OSError, ValueError):
        return False


def ask(rc_hosts, prog="claude"):
    """claude-host's path when `rc-hosts --launcher <prog>` names one that is an executable file, else
    None. `rc_hosts` is the script's path (run by this Python whatever its shebang); falsy: None."""
    if not rc_hosts:
        return None
    try:
        r = subprocess.run([sys.executable, str(rc_hosts), "--launcher", prog],
                           capture_output=True, text=True, timeout=ASK_TIMEOUT)
    except (OSError, subprocess.TimeoutExpired):
        return None
    lines = r.stdout.strip().splitlines() if r.returncode == 0 else []
    path = lines[-1].strip() if lines else ""
    return path if executable(path) else None


def through(argv, launcher, claude_words=("claude",)):
    """argv as the job should start: through `launcher` when there is one, else as it is. claude-host
    takes the word `claude` and starts the current one, so any of `claude_words` in argv[0] becomes it."""
    if not launcher:
        return list(argv)
    if argv and argv[0] in claude_words:
        return [str(launcher), "claude", *argv[1:]]
    return [str(launcher), *argv]
