#!/usr/bin/env python3
"""attention — the one definition of an interruption, and the log of the ones no transcript keeps.

An interruption is anything that takes the owner's attention away from what the owner chose to look at:
a question, a dialog, a step for the owner's hands (the owner, 2026-10-10: "they're all attention grabbers";
"pasting stuff to terminal, and asking me to log in and do something counts too"; "align this with
the interruption definition … they all have the same class"). CHANNELS below is the class —
bin/interruptions counts it, and bin/asklib.py (the session-asks board) imports it (`import attention`
with hooks/ on sys.path) rather than define their own.

As a hook, wired on PermissionRequest and Notification (bootstrap.sh --hooks), it appends one
line per event to <log dir>/attention/<yyyy-mm>.jsonl, the core's log dir (`regatta/log-dir`;
outside git, like the transcripts). Other writers append there through record(); every line has the same shape:

  {"ts": ISO-8601 with offset, "event": str, "type": str, "tool": str, "detail": str ≤ 300,
   "session": first 8 of the session id, "cwd": str, "login": config dir name}

What fires (sessionpipe 0.5.0's parser and its outbox, read 2026-10-10): PermissionRequest for
every permission dialog, AskUserQuestion's included; Notification with `notification_type`
permission_prompt (the same dialog again, when it sits), idle_prompt ("waiting for your input"),
elicitation_dialog, and others (an auto-mode setup proposal). The log keeps all of them; the
reader decides what counts: NOTICE_TYPES below, the ones that ask the owner for something. Claude Code
2.1.296 emits 14 types (strings in the binary, review 2026-10-11); agent_completed,
elicitation_complete/_response and auth_success are reports or repeats, not asks. The trust dialog fires nothing — it shows before any hook can run.

**Never prints** as a hook: a PermissionRequest hook's stdout is a decision, and an empty one
leaves the dialog to the owner. Never exits non-zero: exit 2 there would deny the tool. Python 3.9,
stdlib only.
"""
import datetime as dt
import json
import os
import sys
from pathlib import Path



def _log_dir():
    """$ATTENTION_LOG_DIR, else attention/ in the core's log dir. A core that cannot be found or
    loaded never costs the hook its run (find_core exits 2, and exit 2 here would deny the tool):
    the core's own default stands in, and the event is still logged."""
    if os.environ.get("ATTENTION_LOG_DIR"):
        return Path(os.environ["ATTENTION_LOG_DIR"])
    try:
        sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "lib"))
        import find_core
        sys.path.insert(0, find_core.hooks())
        import common
        return common.LOG_DIR / "attention"
    except (Exception, SystemExit):
        return Path.home() / ".local" / "state" / "regatta" / "attention"


LOG_DIR = _log_dir()

# The class: channel → (where its records come from, its kinds). `predictable` = the owner took the
# pick offered, the waste the weekly dream turns into a default (DESIGN.md, number 6).
CHANNELS = {
    "ask": ("transcripts: AskUserQuestion tool_use + its answers",
            ("recommended", "other-option", "free-text", "declined", "unranked")),
    "memo": ("docs: a `➤ Answer:` D-item that reached the owner (bench/decisions/corpus.py)",
             ("recommended", "overruled", "question")),
    "handoff": ("transcripts: a reply asking for the owner's hands",
                ("paste", "login", "window", "handback")),
    "repeat": ("transcripts: a Stop hook's block that sent the reply round again — one more model run, "
               "and with `whole` the same answer on screen twice (bin/paste-paths' block_reason)",
               ("whole", "lines", "other", "unattended")),
    "permission": ("this log: event PermissionRequest, tool not AskUserQuestion", ("<tool name>",)),
    "notice": ("this log: event Notification, type in NOTICE_TYPES", ("<notification type>",)),
    "relay": ("this log: event Relay, written by bin/asklib.py through record()",
              ("answered", "escalated")),
    "trust": ("state, not events: repos untrusted per login (bin/trust-projects --check)", ("<login>",)),
}
# relay: a run's question sent to its skipper. `answered` — the skipper settled it without the owner:
# an interruption avoided, counted apart from the total; `escalated` — it went on to the owner, who then
# sees it through another channel (ask, handoff), so it is not added to the total a second time.
RELAY_KINDS = CHANNELS["relay"][1]
NOTICE_TYPES = {"elicitation_dialog", "elicitation_url_dialog", "agent_needs_input", "worker_permission_prompt"}


def record(event, type_="", tool="", detail="", session="", cwd="", now=None):
    """Append one line to the log. For writers other than the hook (bin/asklib.py: event "Relay",
    type_ one of RELAY_KINDS, detail the question, session the asking run's). Never raises."""
    try:
        now = now or dt.datetime.now().astimezone()
        row = {"ts": now.isoformat(timespec="seconds"), "event": event, "type": type_ or "", "tool": tool or "",
               "detail": (detail or "")[:300], "session": (session or "")[:8], "cwd": cwd or os.getcwd(),
               "login": Path(os.environ.get("CLAUDE_CONFIG_DIR") or "~/.claude").name}
        LOG_DIR.mkdir(parents=True, exist_ok=True)
        with open(LOG_DIR / ("%s.jsonl" % now.strftime("%Y-%m")), "a", encoding="utf-8") as fh:
            fh.write(json.dumps(row) + "\n")
        return True
    except Exception:
        return False


def detail(inp):
    """What was asked about, short: the command, the path or the URL — enough to name the allowlist rule."""
    if not isinstance(inp, dict):
        return ""
    for k in ("command", "file_path", "path", "url", "pattern", "skill"):
        v = inp.get(k)
        if isinstance(v, str) and v:
            return v
    return ""


def main():
    try:
        data = json.loads(sys.stdin.read() or "{}")
    except ValueError:
        return
    if isinstance(data, dict):
        record(data.get("hook_event_name") or "", data.get("notification_type"), data.get("tool_name"),
               detail(data.get("tool_input")) or data.get("message") or "", data.get("session_id") or "",
               data.get("cwd"))


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass  # a log line lost beats a dialog blocked
    sys.exit(0)
