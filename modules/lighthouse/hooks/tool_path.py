#!/usr/bin/env python3
"""SessionStart hook: put the host's package-manager tool directories on every session's Bash PATH.

Why (the overlay's lessons, "A session's PATH is its parent's"): a Claude session's Bash
tool takes PATH from the process that started `claude`, and no dotfile changes it. So a session
started with a bare PATH — bin/rc-hosts' Remote Control hosts until 2026-10-12, sshd's
`claude -p`, any starter yet to come — has /usr/bin:/bin:/usr/sbin:/sbin plus whatever its
parent wrote, and Homebrew's ffmpeg, gh, rclone and node read as "not installed". The
always-on Mac's bridge sessions concluded exactly that on 2026-10-12 and wrote a Swift decoder
instead.

Fixing each starter fixes the ones known; this reaches every one that runs the user hooks
(Claude Desktop's local agent mode does not). A SessionStart hook may
write shell lines to $CLAUDE_ENV_FILE, which Claude Code sources before each Bash command,
after the snapshot. Only the Bash tool's PATH changes; hooks and MCP servers keep the
parent's. Each directory in DIRS that exists here and is missing is APPENDED: a parent's
choice still wins (bin/dispatch prepends Homebrew on purpose; this only fills gaps). The lines
are idempotent (a continued or compacted session re-runs the hook into the same file), and a directory
whose name a shell would read as more than a name is skipped, since a parse error in this file
would fail every Bash command of the session. Prints nothing, always exits 0: a PATH hint must
never cost a session its start.

    TOOL_PATH_DIRS=a:b   replaces DIRS (the tests)
"""
import json
import os
import re
import sys

# Homebrew on Apple silicon, Homebrew on Intel (and most hand installs), Linuxbrew system-wide
# and per user, then per-user installs (claude itself, pip --user scripts, a static ffmpeg).
DIRS = ("/opt/homebrew/bin", "/usr/local/bin", "/home/linuxbrew/.linuxbrew/bin",
        "~/.linuxbrew/bin", "~/.local/bin")
SAFE = re.compile(r"[A-Za-z0-9_@%+=,./-]+")   # written unquoted into a case pattern and an assignment


def missing(path, dirs):
    have = set(path.split(os.pathsep))
    return [d for d in (os.path.expanduser(x) for x in dirs)
            if SAFE.fullmatch(d) and d not in have and os.path.isdir(d)]


def lines(dirs):
    out = [f'case ":$PATH:" in *":{d}:"*) ;; *) PATH="$PATH:{d}" ;; esac' for d in dirs]
    return "\n".join(out + ["export PATH"]) + "\n"


def main():
    try:
        json.load(sys.stdin)   # the event; nothing in it is needed, but read it so the pipe closes cleanly
    except Exception:
        pass
    env_file = os.environ.get("CLAUDE_ENV_FILE")
    if not env_file:
        return
    dirs = os.environ["TOOL_PATH_DIRS"].split(":") if os.environ.get("TOOL_PATH_DIRS") else DIRS
    add = missing(os.environ.get("PATH", ""), dirs)
    if add:
        with open(env_file, "a") as f:
            f.write(lines(add))


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass
    sys.exit(0)
