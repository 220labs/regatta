#!/usr/bin/env python3
"""cold_prompt: every typed `/finish` in a `claude/*` worktree runs as a fresh unattended run instead.

UserPromptSubmit. The autofinish design's E7 (D14-A, docs/autofinish-design-2026-10-02.md):
44 of 175 typed `/finish` runs in 14 days started on an expired prompt cache or ran on Fable,
$124 above as many fresh runs. A cold `/finish` re-writes the whole context at the 1-hour
write price (2x base) before its first useful token; a fresh session pays only for what it reads.

Since costs S7 (docs/host-power-costs-2026-10-24.md, 2026-10-24) a warm session goes fresh too: its
`/finish` re-reads the whole build context on each of the skill's dozens of turns, where a fresh
run reads the branch and the runner's bundle (the old session's prompts and replies). Two roads:

- cold (the transcript's last call over COLD_S old) or Fable: before any model call the hook starts
  bin/autofinish-run on the worktree (`--by typed`, with this session's id as `--session`) and
  blocks the prompt with the reason. A summary written here would pay the re-write, or Fable's
  rates, that the hand-off exists to save.
- warm, on any other model: the prompt passes with a context line that asks this session for the one
  thing only it knows — the branch's commit summary, written and committed — and then for the same
  runner command, run by the session itself; a runner that refuses leaves the `/finish` to run here.
  The summary goes first because the runner takes the lock, after which this panel writes nothing.

On the laptop (`common.LAPTOP`) the runner gets `--merge` too, on both roads: there the owner's typed
`/finish` is the yes to merge (the finish skill's step 11.4), and the run may land on the peer (D3-A,
the night-landings digest of 2026-10-25: "your typed word stays the yes, wherever the run lands"). The
peer's `--from=<laptop>` (D2-A) already takes the laptop's path for every landing the laptop sends;
`--merge` is the typed word's own, so it holds where `--from` is not honoured (a peer whose
`regatta/laptop` names another host) and the run's state says `merge`. On any other Mac a typed `/finish` merges only on the owner's explicit yes, which a
hand-off cannot ask: no `--merge` there. autofinish-run still refuses `--merge` to an unattended caller
and to any `--by` but a person's.

The runner pre-writes the worktree lock in its own session's name, so this panel is locked out from
then on and checkpoint.py says why at its next prompt. `/finish` with any other argument (`--here`,
`--local`, another branch, a PR) passes untouched: the runner always runs `/finish <branch>
--unattended`, and must not drop what the owner asked for.

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
Tests: modules/wharf-runs/tests/cold_prompt.sh (moved from the overlay's hooks/test_hooks.sh with
S7). Seams: COLD_PROMPT_NOW, CLAUDE_AUTOFINISH_RUN,
COLD_PROMPT_TIMEOUT (seconds, in place of RUN_TIMEOUT_S), COLD_PROMPT_HOST (this Mac, in place of
common.host_name(); REGATTA_LAPTOP names the laptop).
"""
import json
import os
import re
import shlex
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
    import transcript  # noqa: E402 — the core's one last-call reader
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
RUNNER = os.environ.get("CLAUDE_AUTOFINISH_RUN") or str(Path(__file__).resolve().parent.parent / "bin" / "autofinish-run")
RUN_TIMEOUT_S = 45  # autofinish-run returns once dispatch has said whether the run began, within its typed bound (40 + 3 s; not confirmed exits 0), after ending a warm run (30 s cap for --by typed); its account pick is --cached


def now():
    v = os.environ.get("COLD_PROMPT_NOW")
    return float(v) if v else time.time()


def finish_args(prompt):
    """The words after `/finish`, or None when the prompt is not /finish."""
    p = (prompt or "").strip()
    if not re.match(r"^/finish(\s|$)", p):
        return None
    return p.split()[1:]


def last_call(path):
    """(epoch, model, context tokens) of the transcript's last main-chain call (the core's reader:
    sidechains, `<synthetic>` stand-ins and zero totals skipped), or None — also when its time does
    not parse, so no age is guessed."""
    c = transcript.last_call(path)
    return c if c and c[0] is not None else None


def family(model):
    m = model.lower()
    return next((k for k in WRITE_PER_M if k in m), "opus")


def model_name(model):
    """The family for a model the price table knows, else the model as written: never a guess."""
    m = model.lower()
    return next((k.capitalize() for k in WRITE_PER_M if k in m), model or "an unknown model")


def age(s):
    return f"{int(s // 3600)} h" if s >= 3600 else f"{int(s // 60)} min"


def on_laptop():
    """True on the laptop, where a typed /finish is the owner's yes to merge (the header)."""
    here = os.environ.get("COLD_PROMPT_HOST") or common.host_name()
    return bool(here) and here.lower() == str(common.LAPTOP).lower()


def runner_args():
    """What follows the worktree on the runner's line: a typed hand-off, with the yes on the laptop."""
    return ["--rule", "C", "--by", "typed"] + (["--merge"] if on_laptop() else [])


def handover_context(ctx, model, top, sid):
    """The context line for a warm session's /finish: summary first, then the runner, run here."""
    session = f" --session {shlex.quote(sid)}" if sid else ""
    top, runner = shlex.quote(top), shlex.quote(RUNNER)
    return (f"cold_prompt (costs S7): this typed /finish goes to a fresh run, not this session — here every "
            f"turn of the finish skill would re-read this {ctx // 1000}k context on {model_name(model)}. "
            f"Do not follow the finish skill's phases in this turn. Do two things only:\n"
            f"1. Write the branch's commit summary to commit-summary.md in your scratchpad — `Area: what changed` "
            f"lines for the whole branch, what is still open and why, and `Deployed: <what> | no` — then commit "
            f"it: `git -C {top} add -A && git -C {top} commit -q --allow-empty -F <that file>`. The fresh run "
            f"reads the branch's log; this summary is the one thing only this session knows.\n"
            f"2. Hand the branch over: `{runner} {top} {' '.join(runner_args())}{session}`, and tell the owner the "
            f"window its output names; its PR carries the report.\n"
            f"If step 2 is denied or exits non-zero (that tip already tried, a run going, a lock another session's), run "
            f"/finish here as the skill says. The owner's `/finish --here` always runs it in this tab.")


def head(cwd):
    r = subprocess.run(["git", "-C", cwd, "rev-parse", "HEAD"], capture_output=True, text=True, timeout=10)
    return r.stdout.strip() if r.returncode == 0 else None


def last_run_tip(cwd):
    """The tip the branch's last autofinish run started on (its autofinish.json), or None."""
    r = subprocess.run(["git", "-C", cwd, "rev-parse", "--git-dir"], capture_output=True, text=True, timeout=10)
    if r.returncode:
        return None
    try:
        with open(os.path.join(cwd, r.stdout.strip(), "claude", "autofinish.json")) as f:
            return json.load(f).get("tip") or None
    except (OSError, ValueError, AttributeError):
        return None


def decide(data):
    """("block", reason), ("context", text) for a warm session, or None to let the prompt through."""
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
    top = subprocess.run(["git", "-C", cwd, "rev-parse", "--show-toplevel"],
                         capture_output=True, text=True, timeout=10).stdout.strip() or cwd
    if idle <= COLD_S and not fable:
        if last_run_tip(cwd) == head(cwd):
            # a fresh run already stopped on this tip: step 1's commit would move it, and the runner's
            # "no retry on the same tip" would never refuse the same stop again (the finish review)
            return None
        return "context", handover_context(ctx, model, top, data.get("session_id"))
    # priced before the runner starts: nothing may raise once it has detached
    price = common.cost_text(ctx * WRITE_PER_M[family(model)] / 1e6)
    cmd = [RUNNER, top] + runner_args()
    if data.get("session_id"):
        cmd += ["--session", data["session_id"]]  # this panel's own lock is no refusal
    try:
        run = subprocess.run(cmd, capture_output=True, text=True,
                             timeout=float(os.environ.get("COLD_PROMPT_TIMEOUT") or RUN_TIMEOUT_S))
    except subprocess.TimeoutExpired:
        # it may have written its lock and detached already: never a second /finish beside it
        return "block", ("the launcher did not answer in time — it may be starting /finish in its own window "
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
    peer = sent_to(run.stdout)
    if peer:
        on = f" on {peer} (sent there)"
    why = f"cold {ctx // 1000}k ({age(idle)})" if idle > COLD_S else f"on Fable, {ctx // 1000}k"
    return "block", (f"{why} — /finish runs by itself in the window \"{window}\"{on} (the phone shows it on its own login); "
            f"its PR carries the report; /finish --here runs it in this tab at the full "
            f"re-write (~{price})")


def sent_to(out):
    """The peer autofinish-run sent the run to, from its first line (its header, Where), or None: that
    Mac holds the window, so the line must not name it as if it were here (second landing review, 13)."""
    # `queued on <peer>:` too (dispatch-queue S9): a landing queued at the peer's cap waits for a slot there
    m = re.search(r"^(?:started on|sent to|queued on|not confirmed after \d+ s on) ([A-Za-z0-9-]+)[:,]", out or "", re.M)
    return m.group(1) if m else None


def main():
    try:
        data = json.load(sys.stdin)
    except ValueError:
        return
    try:
        out = decide(data)
    except Exception:  # noqa: BLE001 — a hook never costs the owner the prompt
        return
    if not out:
        return
    kind, text = out
    if kind == "block":
        print(json.dumps({"decision": "block", "reason": text}))
    else:
        print(json.dumps({"hookSpecificOutput": {"hookEventName": "UserPromptSubmit", "additionalContext": text}}))


if __name__ == "__main__":
    main()
    sys.exit(0)
