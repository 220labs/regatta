#!/usr/bin/env python3
"""The council's PreToolUse hook for agy: allow the tool steps of "Equal terms", deny every other
(docs/principal-council-isolation-2026-10-29.md, S1). agy has no flag that takes a tool away, so this
hook is the list: fence.py's agy_home() copies it into the arm's box, read-only to the arm, and names
it in the scratch HOME's hooks.json as the only hook.

The list is of step names as the hook sees them, collected from the runs: the hook sees `read_file`
where agy's init event lists `view_file` (H5), so both are here. A name outside it is denied, and
fence.record() reads the denial back by REASON in the step's error; a step outside the list that ran,
or ended in another error, fails the arm. Input: the event JSON on stdin, the step's name in `tool_name`
(1.4.10) or `toolCall.name` (1.4.11); output: one decision line. Anything that does not parse is denied.
"""
import json
import sys

# read, search, shell, writes in the copy, the web (the Gemini column of "Equal terms"); the shell's
# own companions (a running command's status and input, as Codex's write_stdin) and the waits
ALLOW = ("run_command", "command_status", "send_command_input", "view_file", "read_file", "grep_search",
         "find_by_name", "list_dir", "write_to_file", "replace_file_content", "multi_replace_file_content",
         "sed_file", "search_web", "read_url_content", "wait", "wait_5_seconds")
REASON = "not in the council arm's tool set"
# the web tools run on Google's side, past the proxy: allowed only when the brief asked for the web (`--research`, which
# fence.py's agy home writes into hooks.json's command, read-only to the arm), as Claude's WebSearch and Codex's
# web_search are dropped without it (round 6's second review; the fourth landing review's finding 10)
WEB = ("search_web", "read_url_content")


def decide(raw, research=False):
    # agy 1.4.10 sent `tool_name`; 1.4.11 sends `toolCall.name` (record Q3b), and a hook that read only the first
    # denied every tool of 1.4.11's arm
    try:
        j = json.loads(raw)
        call = j.get("toolCall")
        name = j.get("tool_name") or (call.get("name") if isinstance(call, dict) else None)
    except (ValueError, AttributeError):
        name = None
    if isinstance(name, str) and name in ALLOW and (research or name not in WEB):
        return {"decision": "allow"}
    return {"decision": "deny", "reason": REASON}


if __name__ == "__main__":
    print(json.dumps(decide(sys.stdin.read(), research="--research" in sys.argv[1:])))
