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

`epoch` is None when the record's timestamp does not parse; the caller decides what that means.
Only the tail is read: a long session is many MB and its last call is near the end. A tail that
starts mid-line drops that line rather than parse half a record.

call() is self-contained (stdlib only) and call_line() needs only call(), because
pickup ships both sources to the peer Mac with inspect.getsource, as it does its own step reader.
call_line() parses JSON only for a line that names an assistant and a usage: tool output, the
megabyte lines, never reaches json.loads (0.43 s for the 86 MB of assistant lines in 614 MB of
transcripts, 2026-10-24). Stdlib, Python 3.9; no hook loads it as a hook, so it has no main.
"""
import os

TAIL_BYTES = 2_000_000


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
