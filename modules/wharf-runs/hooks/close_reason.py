#!/usr/bin/env python3
"""close_reason: why rc-hosts closed this session, as a failure line on the session's own stderr.

SessionEnd. A Remote Control host logs a session's exit as `Session failed: <the session's last
stderr line>`, and with nothing else said that line was a warning every session prints at start
("claude.ai MCP server blocked by enterprise policy", a connector the user settings deny), so the
hourly reaper's planned closes read as faults (a film repo's host, 2026-10-23). Before rc-hosts
ends a host session it writes the reason to CLOSING/<session id> (rc-hosts' note_close()); this
hook prints it and exits 1, which Claude Code reports on its own stderr as `SessionEnd hook
[<command>] failed: <reason>` (probed on 2.1.310, 2026-10-24, an idle stream-json session sent
SIGTERM as the reaper sends it).

Claude Code prints the SessionEnd failure lines in the order the hooks are defined, once all have
settled (2.1.310's source), so this line is the session's last only where it is wired last, and
only when the others finish inside the hooks' time budget: the overlay sets
CLAUDE_CODE_SESSIONEND_HOOKS_TIMEOUT_MS to 30 s for every session (the 1.5 s default cut a vault
commit off). Where it cannot be last, the line rc-hosts writes into the host's log still says it.

A marker is read once and removed; one over an hour old is stale (a session resumed later under
the same id) and ignored. No marker, any input it cannot read, any failure: silent, exit 0 — exit 1
is this hook's "reason printed". Stdlib, Python 3.9.
Tests: wharf-runs' tests/test_rc_hosts.sh, "close_reason". Seam: RC_HOSTS_CLOSING.
"""
import json
import os
import sys
import time
from pathlib import Path

CLOSING = Path(os.environ.get("RC_HOSTS_CLOSING") or Path.home() / ".local" / "state" / "rc-hosts" / "closing")
STALE_S = 3600


def main():
    sid = json.loads(sys.stdin.read() or "{}").get("session_id")
    if not isinstance(sid, str) or not sid or "/" in sid or sid.startswith("."):
        return 0
    p = CLOSING / sid
    if time.time() - p.stat().st_mtime > STALE_S:
        return 0
    reason = p.read_text(encoding="utf-8").strip()
    p.unlink()
    if not reason:
        return 0
    print(reason, file=sys.stderr)
    return 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:   # no marker (OSError), bad input, anything: never a traceback as the last line
        sys.exit(0)
