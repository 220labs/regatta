#!/usr/bin/env python3
"""force_mark: "use the force" in the owner's typed message marks the session for one force run.

UserPromptSubmit. dispatch-queue S4 (docs/dispatch-queue-2026-10-25.md, D3-A; the contract's
"Priorities and the force"): `dispatch --priority force` from an attended session passes only on the
owner's words, and this hook is how dispatch hears them. A prompt whose own words match
`\\buse the force\\b` (any case) writes the mark, `force/<session_id>` in run-seed's cache folder (dispatch's
$cache); every other prompt the owner types in that session removes it, so the mark lives for the turn the owner said it in. dispatch spends
it on use: one phrase, one run. A --next inherits force as high, never as force.

Not the owner's words, so no mark (the frame filters):
- a prompt carrying `agent_id` (a subagent's), which neither writes nor clears the session's mark, or
  starting `<task-notification` or `<agent-message`;
- hail's frame (`HAIL event|report|ask from … — `) and sessionpipe control's (`Message via <host>
  (sessionpipe control, …):`), on any line: a peer's or a device's message relayed into the prompt, and
  every line after the frame is that message, never the owner's;
- the phrase inside quotes ("…", '…', “…”, ‘…’, `…`), a fenced block, a `>` quote line, a
  `<pasted_content>` block or a `<system-reminder>` block: text the owner pasted or quoted, never said.

An unattended session (CLAUDE_UNATTENDED) is never marked: its prompt is dispatch's, not the owner's.
checkpoint.py denies every session a hand write of the mark's folder (FORCE_DIR) and a run of this hook
by hand, so no session writes one by accident (checkpoint guards accidents: a path spelled through `cd` or a
variable passes). A negated phrase ("don't use the force") is no mark. A prompt that is
not the owner's (a notification, an agent message, a frame from its first line) leaves the mark as it is.
Wiring: one line in the overlay's `bootstrap.sh --hooks` (S4), on every host.

Never exits non-zero (exit 2 on UserPromptSubmit erases the prompt), stdlib, Python 3.9.
Tests: modules/wharf-runs/tests/test_priority.sh. No seam: the folder is under HOME, as dispatch reads it.
"""
import json
import os
import re
import sys
from pathlib import Path

PHRASE = re.compile(r"\buse the force\b", re.I)
HAIL_FRAME = re.compile(r"^[ \t]*HAIL (event|report|ask) from .+ — ", re.M)   # bin/hail's FRAME_RE
PIPE_FRAME = re.compile(r"^[ \t]*Message via \S+ \(sessionpipe control\b", re.M)   # sessionpipe's frame(), 0.x
NOT_OWNERS = ("<task-notification", "<agent-message")
# what the owner quoted or pasted rather than said: cut before the phrase is looked for
QUOTED = [re.compile(p, re.S) for p in (
    r"<pasted_content\b.*?</pasted_content>", r"<system-reminder>.*?</system-reminder>",
    r"```.*?```", r"`[^`\n]*`", r"(?m)^[ \t]*>.*$",
    r'"[^"\n]*"', r"“[^”\n]*”", r"‘[^’\n]*’", r"(?<!\w)'[^'\n]*'(?!\w)")]


def mark_dir():
    return Path.home() / "Library" / "Caches" / "run-seed" / "force"   # dispatch's $cache/force


def owners_words(prompt):
    """The prompt's own words with every quoted, pasted or framed part cut, or "" when the whole prompt is
    a frame or a notification (not the owner's message at all)."""
    p = prompt or ""
    if p.lstrip().startswith(NOT_OWNERS):
        return ""
    for rx in (HAIL_FRAME, PIPE_FRAME):   # a frame on any line: it and all after it are the relayed message
        m = rx.search(p)
        if m:
            p = p[:m.start()]
    for rx in QUOTED:
        p = rx.sub(" ", p)
    return p


NEGATED = re.compile(r"(?:\bnot|n't|\bnever|\bno need to|\bwithout)\s+(?:\w+\s+){0,2}$", re.I)


def says_force(data):
    words = owners_words(data.get("prompt"))
    return any(not NEGATED.search(words[:m.start()]) for m in PHRASE.finditer(words))


def not_owners(prompt):
    """The whole prompt is someone else's: a notification, an agent message, a frame on its first line."""
    s = (prompt or "").lstrip()
    return s.startswith(NOT_OWNERS) or bool(HAIL_FRAME.match(s) or PIPE_FRAME.match(s))


def main():
    try:
        data = json.load(sys.stdin)
    except ValueError:
        return
    if os.environ.get("CLAUDE_UNATTENDED") or data.get("agent_id") or not_owners(data.get("prompt")):
        return   # dispatch's prompt, a subagent's, a notification or a frame: not the owner typing, no turn of theirs to end
    sid = str(data.get("session_id") or "")
    if not re.fullmatch(r"[A-Za-z0-9_-]{1,100}", sid):
        return
    try:
        d = mark_dir()
        f = d / sid
        if says_force(data):
            d.mkdir(parents=True, exist_ok=True)
            f.write_text("%s\n" % (data.get("cwd") or ""))
        elif f.exists():
            f.unlink()
    except OSError:
        pass   # a hook never costs the owner the prompt


if __name__ == "__main__":
    try:
        main()
    except Exception:  # noqa: BLE001
        pass
    sys.exit(0)
