"""transcript: a session transcript's last main-chain call — the shared reader of it (skipperlib still keeps its own, until its switch).

A Claude Code transcript (`<config dir>/projects/<slug>/<session>.jsonl`) holds one JSON record
per line. A *call* is an assistant record on the main chain that carries real usage: not a
sidechain (`isSidechain`, a subagent's), not Claude Code's own `<synthetic>` stand-in (an API
error, "No response requested.", written with all-zero usage), and not a zero total. Its context
is input + cache read + cache write: what the request carried, so a compaction shows as a drop
and the last call wins. Four readers had their own rules for each of these (cold_prompt, pickup, the harness adapter,
skipperlib); the first three use this since 2026-10-24. The AGENTS.md `<synthetic>` trap is why.

    call(record)       -> (epoch, model, context) of one parsed record, or None
    call_line(line)    -> the same of one raw line, or None (a cut or foreign line too)
    last_call(path)    -> the last call in the file's last TAIL_BYTES, walking back, or None
    machine_start(text) -> the launcher that wrote this user prompt ("dispatch", "autofinish", ...), or None

`epoch` is None when the record's timestamp does not parse; the caller decides what that means.
Only the tail is read: a long session is many MB and its last call is near the end. A tail that
starts mid-line drops that line rather than parse half a record.

call() is self-contained (stdlib only) and call_line() needs only call(), because
pickup ships both sources to the peer Mac with inspect.getsource, as it does its own step reader.
call_line() parses JSON only for a line that names an assistant and a usage: tool output, the
megabyte lines, never reaches json.loads (0.43 s for the 86 MB of assistant lines in 614 MB of
transcripts, 2026-10-24). Stdlib, Python 3.9; no hook loads it as a hook, so it has no main.

machine_start() is the one rule for a prompt a launcher typed, not a person: Claude Code records it
with origin kind "human" all the same. plumb's `asks` and aurora's `week-digest` read the owner's
prompts through it (evolve-readers, 2026-11-03: the asks sieve matched `You are (a|the) `, never
dispatch's "You are an …", and week-digest had no rule at all). Each pattern is one launcher's own
words, anchored at the prompt's start, so an owner's prompt that merely opens alike ("You are a
great help", a typed `/finish`) stays the owner's. A launcher that changes its words changes its row
here: the core's check renders the templates it can import (autofinish-run's finish_prompt,
skipperlib's brief, pickup's orientation and cloud brief, hail's frame, dispatch-rc's nudge, clock's
head) and fails on one this reads as a person's. Two known costs, both the owner's own text: a
`/pickup '<branch>' --fresh` typed by hand (pickup prints that line for the other Mac) reads as
pickup's, and a prompt that opens by pasting a launcher's words is dropped whole. asks' sieve keeps
its own list of what the owner types that is no ask (`/autofinish`, a bare `/finish`, `dispatch …`);
those stay the owner's prompts in week-digest.
"""
import os
import re

TAIL_BYTES = 2_000_000

# launcher -> the words its prompt starts with. A slash command appears raw in a transcript
# (`<command-message>…</command-message><command-name>/finish</command-name><command-args>…`, in either
# order) and flattened by a reader (`/finish <branch> --unattended`): machine_start flattens the raw form
# itself, so each launcher is listed once, flattened.
MACHINE_STARTS = (
    ("dispatch", r"You are an unattended session started by dispatch on "),   # wharf-runs' dispatch, a run's brief
    ("dispatch", r"reply with the single word ok\s*$"),                       # dispatch --probe's whole prompt
    ("dispatch-rc", r"dispatch-rc watcher: your last turn ended on an API error \("),   # its NUDGE_FRAME
    ("hail", r"HAIL (event|report|ask) from [^\n]{1,120}? — "),               # hail's frame (KINDS)
    ("clock", r"Run this one command with the Bash tool, in the foreground, and do nothing else; "),   # PROMPT_HEAD
    ("autofinish", r"/finish\s+[^-\s]\S*\s+--unattended\b"),                  # autofinish-run's finish_prompt: a branch first
    ("pickup", r"/pickup\s+'[^'\s]+'"),                                      # a pickup tab's prefill: the quoted branch
    # pickup's orientation, but not one that carries the owner's `--note`, which it appends as `. Then: <note>`
    ("pickup", r"(Picked up with /pickup|Moved from [^\n]{1,80} with /move) \(\d{4}-\d\d-\d\d \d\d:\d\d\): (?![\s\S]*\. Then: )"),
    ("pickup", r"Continue the work on branch \S+ of \S+: check it out, read its last commits"),   # its cloud brief
    ("skipper", r"You are skipper · (\S+), the skipper of scope \1 on "),     # helm's skipper brief (leaselib's holder)
    ("council", r"You are one arm of a council "),                            # wharf's council arms
    # weekly-run's and sextant-run's `claude -p /<job>`; /embark has no launcher today, the owner types it, and the
    # brief (evolve-readers, 2026-11-05) has both readers agree on it as asks' sieve always read it: not the owner's ask
    ("weekly", r"/(aurora|sextant|embark)(\s|$)"),
    # a brief's or a labeller's frame as a whole first prompt, as its writer types it (case and space exact): helm
    # send's and keel's `Task:` briefs, the gate's `Task: … Labels:` prompt. The asks sieve's older corpus frames
    # (`Read first:`, `Unattended run`, …) stay its own: no launcher writes them, and an owner's sentence opens so
    ("brief", r"# [^\n]{1,120} — sent with helm send from |Context:\n[\s\S]{0,4000}?\nTask: |Task: "),
)
_MACHINE_RE = [(who, re.compile(p)) for who, p in MACHINE_STARTS]
_CMD_NAME = re.compile(r"<command-name>\s*(/[^<\s]+)\s*</command-name>")
_CMD_ARGS = re.compile(r"<command-args>(.*?)</command-args>", re.S)


def machine_start(text):
    """The launcher whose words open this user prompt, or None when a person may have typed it."""
    if not isinstance(text, str):
        return None
    t = text.lstrip()
    if t.startswith("<command-"):   # a raw slash command, its tags in any order: read as `/name args`
        name = _CMD_NAME.search(t)
        if not name:
            return None
        args = _CMD_ARGS.search(t)
        t = name.group(1) + (" " + args.group(1).strip() if args and args.group(1).strip() else "")
    for who, rx in _MACHINE_RE:
        if rx.match(t):
            return who
    return None


def call(record):
    """(epoch, model, context tokens) of one transcript record when it is a main-chain call, else None."""
    import datetime
    if not isinstance(record, dict) or record.get("type") != "assistant" or record.get("isSidechain"):
        return None
    msg = record.get("message")
    if not isinstance(msg, dict) or msg.get("model") == "<synthetic>":
        return None
    u = msg.get("usage")
    if not isinstance(u, dict):
        return None
    ctx = sum(v for v in (u.get("input_tokens"), u.get("cache_read_input_tokens"),
                          u.get("cache_creation_input_tokens"))
              if isinstance(v, int) and not isinstance(v, bool))
    if not ctx:
        return None
    try:
        ts = datetime.datetime.fromisoformat(str(record["timestamp"]).replace("Z", "+00:00"))
        if ts.tzinfo is None:
            ts = ts.replace(tzinfo=datetime.timezone.utc)
        epoch = ts.timestamp()
    except (KeyError, ValueError):
        epoch = None
    return epoch, str(msg.get("model") or ""), ctx


def call_line(line):
    """call() of one raw transcript line; None for any line that is not a call or not JSON."""
    import json
    if '"assistant"' not in line or '"usage"' not in line:
        return None
    try:
        return call(json.loads(line))
    except ValueError:
        return None


def last_call(path, tail=TAIL_BYTES):
    """(epoch, model, context tokens) of the last main-chain call in the transcript at PATH, read
    from its last TAIL bytes; None when it is unreadable or holds no call there."""
    try:
        with open(path, "rb") as f:
            f.seek(0, os.SEEK_END)
            start = max(0, f.tell() - tail)
            # one byte before the tail says whether its first line is whole
            f.seek(max(0, start - 1))
            raw = f.read()
    except (OSError, TypeError, ValueError):
        return None
    if start:
        whole = raw[:1] == b"\n"
        raw = raw[1:]
        if not whole:
            raw = raw.split(b"\n", 1)[1] if b"\n" in raw else b""
    # split on b"\n" only: str.splitlines() also breaks on U+2028/2029/0085, which JSON leaves raw
    for line in reversed(raw.split(b"\n")):
        c = call_line(line.decode("utf-8", "replace"))
        if c:
            return c
    return None
