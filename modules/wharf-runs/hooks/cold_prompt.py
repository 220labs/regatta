#!/usr/bin/env python3
"""cold_prompt: a typed `/finish` in a cold or Fable session runs as a fresh unattended run instead.

UserPromptSubmit. The autofinish design's E7 (D14-A, docs/autofinish-design-2026-10-02.md):
44 of 175 typed `/finish` runs in 14 days started on an expired prompt cache or ran on Fable,
$124 above as many fresh runs. A cold `/finish` re-writes the whole context at the 1-hour
write price (2x base) before its first useful token; a fresh session pays only for what it reads.

So, before any model call: a prompt that is a bare `/finish`, or `/finish <this worktree's own
branch>`, in a `claude/*` worktree, in a session whose transcript's last call is over COLD_S old
or whose last model was Fable, starts bin/autofinish-run on the worktree (`--by typed`, with this
session's id as `--session`) and blocks the prompt with the reason. The runner pre-writes the
worktree lock in its own session's name, so this panel is locked out from then on and
checkpoint.py says why at its next prompt. A warm Opus session's `/finish` passes untouched; so
does `/finish` with any other argument (`--here`, `--local`, another branch, a PR): the runner
always runs `/finish <branch> --unattended`, and must not drop what the owner asked for.

Passes untouched, too, when: autofinish is disarmed on this Mac (`bin/autofinish arm`; nothing
starts by itself until the owner's 3-hour dry run was read, 2026-10-05); the session is itself
unattended (CLAUDE_UNATTENDED); the runner refuses (that tip already tried, a run going, the
lock another session's) or fails — then the typed `/finish` runs here as it always did. A runner
that does not answer within RUN_TIMEOUT_S blocks instead: it may be starting, and a `/finish`
here beside it would be two at once; the reason names `/finish --here`.

checkpoint.py runs beside this hook — Claude Code starts a prompt's UserPromptSubmit hooks in
parallel — and its claim() rewrites owner.json for this panel; it re-reads the lock just before
its write, so the runner's lock is lost only when the runner's rename happens in the microseconds
between that read and that write, and then the runner's /finish meets `read-only here` and
stops at its first gate with nothing written: a wasted run, never two writers (review,
2026-10-05; the --session refusal reads the same file and adds no window of its own).

Never exits non-zero (exit 2 on UserPromptSubmit erases the prompt), stdlib, Python 3.9.
Tests: hooks/test_hooks.sh, "cold_prompt". Seams: COLD_PROMPT_NOW, CLAUDE_AUTOFINISH_RUN,
COLD_PROMPT_TIMEOUT (seconds, in place of RUN_TIMEOUT_S).
"""
import datetime
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

# The core is the regatta module beside this one, found by lib/core_path.py (C2); add() never exits,
# so a missing core is the import's error below — one line and a quiet exit (C4).
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "lib"))
import core_path  # noqa: E402
core_path.add()
CORE_MISSING = "regatta core not found — run the overlay's bootstrap.sh --config, or install the regatta core"
try:
    import common  # noqa: E402
except Exception as exc:  # a broken core as well as a missing one: never exit 1
    # No core (docs/regatta-modules-2026-10-16.md C4): one line, a quiet exit — a nudge is never
    # worth a prompt. An importer (a test) gets the error itself.
    if __name__ != "__main__":
        raise
    print(f"cold_prompt: {CORE_MISSING} ({exc})", file=sys.stderr)
    sys.exit(0)

# Five minutes inside the 1-hour cache, as memo notify's constant: a prompt that waits in a
# queue still arrives warm (design section 2b).
COLD_S = 55 * 60
# Price of re-writing the context, per million tokens, at the 1-hour write (2x base): Opus 5.5
# base $4 → $8, Fable 5.1 base $10 → $20 (pricing page, read 2026-10-04; design section 3).
WRITE_PER_M = {"opus": 8.0, "fable": 20.0, "sonnet": 6.0}
TAIL_BYTES = 2_000_000
RUNNER = os.environ.get("CLAUDE_AUTOFINISH_RUN") or str(Path(__file__).resolve().parent.parent / "bin" / "autofinish-run")
RUN_TIMEOUT_S = 45  # autofinish-run returns once it has detached: a second, unless it first ends a warm run (30 s cap for --by typed); its account pick is --cached


def now():
    v = os.environ.get("COLD_PROMPT_NOW")
    return float(v) if v else time.time()


def finish_args(prompt):
    """The words after `/finish`, or None when the prompt is not /finish."""
    p = (prompt or "").strip()
    if not re.match(r"^/finish(\s|$)", p):
        return None
    return p.split()[1:]


def last_call(transcript):
    """(epoch, model, context tokens) of the transcript's last assistant call, or None."""
    try:
        with open(transcript, "rb") as f:
            f.seek(0, 2)
            size = f.tell()
            f.seek(max(0, size - TAIL_BYTES))
            lines = f.read().decode("utf-8", "replace").splitlines()
    except OSError:
        return None
    for raw in reversed(lines):
        if '"assistant"' not in raw:
            continue
        try:
            r = json.loads(raw)
        except ValueError:
            continue
        if r.get("type") != "assistant" or r.get("isSidechain"):
            continue
        msg = r.get("message") or {}
        u = msg.get("usage") or {}
        if not u:
            continue
        ctx = (u.get("input_tokens") or 0) + (u.get("cache_read_input_tokens") or 0) \
            + (u.get("cache_creation_input_tokens") or 0)
        try:
            ts = datetime.datetime.fromisoformat(r["timestamp"].replace("Z", "+00:00")).timestamp()
        except (KeyError, ValueError):
            return None
        return ts, msg.get("model") or "", ctx
    return None


def family(model):
    m = model.lower()
    return next((k for k in WRITE_PER_M if k in m), "opus")


def age(s):
    return f"{int(s // 3600)} h" if s >= 3600 else f"{int(s // 60)} min"


def decide(data):
    """The block reason, or None to let the prompt through."""
    if os.environ.get("CLAUDE_UNATTENDED") or os.environ.get("CLAUDE_HOOK_NO_AUTOFINISH"):
        return None
    args = finish_args(data.get("prompt"))
    if args is None:
        return None
    if not common.autofinish_armed():
        return None
    cwd = data.get("cwd") or os.getcwd()
    r = subprocess.run(["git", "-C", cwd, "rev-parse", "--abbrev-ref", "HEAD"],
                       capture_output=True, text=True, timeout=10)
    branch = r.stdout.strip()
    if r.returncode or not branch.startswith("claude/"):
        return None
    if args and args != [branch]:
        return None  # --here, --local, another branch: what the runner's `/finish <branch> --unattended` is not
    call = last_call(data.get("transcript_path") or "")
    if not call:
        return None
    ts, model, ctx = call
    idle = now() - ts
    fable = family(model) == "fable"
    if idle <= COLD_S and not fable:
        return None
    top = subprocess.run(["git", "-C", cwd, "rev-parse", "--show-toplevel"],
                         capture_output=True, text=True, timeout=10).stdout.strip() or cwd
    # priced before the runner starts: nothing may raise once it has detached
    price = common.cost_text(ctx * WRITE_PER_M[family(model)] / 1e6)
    cmd = [RUNNER, top, "--rule", "C", "--by", "typed"]
    if data.get("session_id"):
        cmd += ["--session", data["session_id"]]  # this panel's own lock is no refusal
    try:
        run = subprocess.run(cmd, capture_output=True, text=True,
                             timeout=float(os.environ.get("COLD_PROMPT_TIMEOUT") or RUN_TIMEOUT_S))
    except subprocess.TimeoutExpired:
        # it may have written its lock and detached already: never a second /finish beside it
        return ("the launcher did not answer in time — it may be starting /finish in its own window "
                "(`bin/dispatch --status`, the autofinish log); give it a minute, or /finish --here "
                "runs it in this tab")
    if run.returncode:
        return None  # refused or failed: the typed /finish runs here, as before
    m = re.search(r'Remote Control "([^"]+)"', run.stdout)
    window = m.group(1) if m else "finish · …"
    # The phone lists Remote Control sessions of its own login only, and the pool may pick the work login
    # (docs/work-account-2026-10-06.md, R4): name the account rather than promise the phone.
    a = re.search(r", account ([^;]+);", run.stdout)
    on = f" on {a.group(1)}" if a and a.group(1) != "None" else ""
    why = f"cold {ctx // 1000}k ({age(idle)})" if idle > COLD_S else f"on Fable, {ctx // 1000}k"
    return (f"{why} — /finish runs by itself in the window \"{window}\"{on} (the phone shows it on its own login); "
            f"its PR carries the report; /finish --here runs it in this tab at the full "
            f"re-write (~{price})")


def main():
    try:
        data = json.load(sys.stdin)
    except ValueError:
        return
    try:
        reason = decide(data)
    except Exception:  # noqa: BLE001 — a hook never costs the owner the prompt
        return
    if reason:
        print(json.dumps({"decision": "block", "reason": reason}))


if __name__ == "__main__":
    main()
    sys.exit(0)
