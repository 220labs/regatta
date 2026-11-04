#!/usr/bin/env python3
"""The builder rotation: dispatch's coin for a build on it, specced or plain Opus (S6 of docs/self-tuning-2026-10-26.md, D2-A).

The finisher rotation's shape (autofinish-run's header), for builders. While the config key
`wharf-runs/builder-rotation` says `until YYYY-MM-DD` and that day has not passed, a run whose brief is
specced — its `Tier:` line names `worker` (and no other model) or Sonnet alone; a blueprint block's `tier: worker`
counts only through the brief's line, and `wharf check` warns when they differ — or plain Opus — the line names
Opus alone, no tier word and no effort but `high`, the rules' default written out (the owner, 2026-11-03) — and
no principal tier, `sr-worker` or other tier, and that no `--model` or `--effort` was given for, draws its
builder once, when dispatch enqueues or schedules it: 3 in 5 Sonnet 5.5 at `high`, else Opus 5.5 at `high`
(today's builder spelled out), both by full id (1 in 5 until 2026-11-03, when the owner raised it for more
Sonnet rows sooner and fewer credits spent; blueprintlib's `brief_rotates` says which class, and the row keeps it as `brief_class`). No key, a passed day or a line that does not parse is
today's dispatch, unchanged. The fence comes first, as the finisher's: a repo in any `confidential: true`
scope, a repo in no scope, or a registry that does not read or walk draws nothing.

The arm rides to the run as one word, DISPATCH_ARM=<name>:<coin>:<until>:<forced> (the queue entry's env,
the ssh line, the one-shot's plist), so both roads run the arm drawn once. Where the run fires, dispatch
re-reads the brief and asks the key's window and the fence again, on that host (so every host that claims runs
needs the key): still on the coin, no flag given, the key on and the fence open, the arm decides the model and effort and goes into the
run record as `arm` ({name, model, effort, coin, until, forced}) with `arm_source` (`coin`, or `pinned` for a
forced coin); and one row goes to <logs>/builder-rotation.jsonl beside finisher-rotation.jsonl, outside git,
private to this Mac — the fence asked again there, so a repo fenced meanwhile writes none. trim's collect
joins the rows by session. DISPATCH_COIN=0|1 forces the coin (the tests), and the row says `forced`.

    buildercoin.py draw REPO            # stdout: the word, or nothing; stderr: why (only with the key file there)
    buildercoin.py arm WORD [--repo R]  # stdout: "<model> <effort> <record json>"; exit 1, why on stdout, for a word
                                        # that does not read, or with R: the key's window closed today, or R fenced
    buildercoin.py row WORD --repo R --branch B --topic T --session S [--account A] [--queue Q] [--brief CLASS]
    buildercoin.py specced              # stdin: a brief; exit 0 when specced, 1 when not
    buildercoin.py rotates              # stdin: a brief; stdout: specced or plain, exit 0; nothing, exit 1

Exit 0, or 1 for a word or brief that does not read (or an arm the window or fence refuses at fire time); dispatch
reads any non-zero, an uncaught error's 1 included, as no arm.
"""
import argparse
import contextlib
import datetime
import fcntl
import json
import os
import random
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "lib"))
sys.path.insert(0, HERE)
import core_path  # noqa: E402 — the regatta core (C2); none: one line, exit 2
core_path.require()
import common  # noqa: E402

LOGS = os.path.join(os.path.expanduser("~"), "Library", "Logs", "claude-weekly")
ROTATION_KEY = "wharf-runs/builder-rotation"
# the arms in coin order, 0 the pin; full ids: an alias floats (the builders bench's harness rules)
ARMS = (("opus-high", "claude-opus-5-5", "high"), ("sonnet-high", "claude-sonnet-5-5", "high"))
ODDS = 5        # SONNET_IN in ODDS draws the challenger (D2-A's coin; 1 in 5 until the owner's 3 in 5, 2026-11-03)
SONNET_IN = 3
# both arms must get rows, or the comparison is gone with no error (the finish review, 2026-11-03)
assert 0 < SONNET_IN < ODDS, "buildercoin: SONNET_IN must be between 0 and ODDS, exclusive"
ROTATION_LOG = "builder-rotation.jsonl"   # in LOGS: private to this Mac, outside git
ROTATION_RE = re.compile(r"^(?:until\s+)?(\d{4}-\d{2}-\d{2})$")
WORD_RE = re.compile(r"^(%s):([01]):(\d{4}-\d{2}-\d{2}):([01])$" % "|".join(a[0] for a in ARMS))


def rotation_window(today=None):
    """(end, why): the last day the rotation runs, or None and why it is off (autofinish-run's, its key)."""
    lines, bad = common.config_read(ROTATION_KEY)
    if bad:
        return None, "builder rotation off: %s unreadable (%s)" % (ROTATION_KEY, bad)
    if not lines:
        return None, "builder rotation off: no %s" % ROTATION_KEY
    # bootstrap.sh's config_values writes each word on its own line: joined, both forms read
    text = " ".join(l.strip() for l in lines if l.strip())
    m = ROTATION_RE.match(text)
    try:
        end = datetime.date.fromisoformat(m.group(1)) if m else None
    except ValueError:
        end = None
    if end is None:
        return None, "builder rotation off: %s says %r, not `until YYYY-MM-DD`" % (ROTATION_KEY, text[:60])
    if (today or datetime.date.today()) > end:
        return None, "builder rotation off: it ended %s" % end
    return end, "builder rotation on until %s" % end


def rotation_fence(primary):
    """None when a build of this repo may rotate and be recorded, else why not: autofinish-run's
    rotation_fence, failing closed the same ways (a torn registry, a scope it cannot walk, no scope, any
    confidential scope that lists the repo)."""
    reg, bad = common.read_registry()
    if bad:
        return "the scope registry does not read"
    try:
        for n, sc in ((reg or {}).get("scopes") or {}).items():
            if isinstance(sc, dict) and sc.get("repos") is not None and not isinstance(sc.get("repos"), list):
                raise TypeError("scope %r: `repos` is no list" % n)
        name, _ = common.scope_of_repo(primary, reg=reg) if reg is not None else (None, {})
        if not name:
            return "%s is in no scope" % os.path.basename(primary)
        for n, sc in (reg.get("scopes") or {}).items():
            if (isinstance(sc, dict) and sc.get("confidential") is True
                    and common.scope_of_repo(primary, reg={"scopes": {n: sc}})[0]):
                return "scope %s is confidential" % n
    except Exception as e:  # noqa: BLE001 — a registry it cannot walk is never known open
        return "the scope registry does not walk (%s)" % type(e).__name__
    return None


def specced(text):
    """blueprintlib's brief_specced: the one reading dispatch's tier_run makes too (imported here alone: the
    draw, arm and row verbs dispatch runs never need it)."""
    import blueprintlib
    return blueprintlib.brief_specced(text)


def coin_of(r):
    """The coin for a roll r in range(ODDS): 1 (the challenger) for SONNET_IN of the ODDS rolls, else 0."""
    return int(r < SONNET_IN)


def rotates(text):
    """blueprintlib's brief_rotates: "specced", "plain", or None."""
    import blueprintlib
    return blueprintlib.brief_rotates(text)


def draw(primary):
    """(word, why): the arm drawn for a build of this repo, as DISPATCH_ARM's word, or None and why not."""
    end, why = rotation_window()
    if end is None:
        return None, why
    fenced = rotation_fence(primary)
    if fenced:
        return None, "builder rotation fenced: %s — today's builder, no row" % fenced
    forced = os.environ.get("DISPATCH_COIN")
    coin = int(forced) if forced in ("0", "1") else coin_of(random.SystemRandom().randrange(ODDS))
    name = ARMS[coin][0]
    return "%s:%d:%s:%d" % (name, coin, end.isoformat(), forced in ("0", "1")), "%s; coin %d: %s%s" % (
        why, coin, name, " (forced)" if forced in ("0", "1") else "")


def arm_of(word):
    """The record's `arm` for a word, or None for one that does not read (its coin must be its arm's)."""
    m = WORD_RE.match(word or "")
    if not m:
        return None
    name, coin, until, forced = m.group(1), int(m.group(2)), m.group(3), m.group(4) == "1"
    if ARMS[coin][0] != name:
        return None
    try:
        datetime.date.fromisoformat(until)
    except ValueError:
        return None
    return {"name": name, "model": ARMS[coin][1], "effort": ARMS[coin][2], "coin": coin, "until": until, "forced": forced}


@contextlib.contextmanager
def rotation_lock():
    os.makedirs(LOGS, exist_ok=True)
    with open(os.path.join(LOGS, ROTATION_LOG + ".lock"), "a") as lk:
        fcntl.flock(lk, fcntl.LOCK_EX)
        try:
            yield os.path.join(LOGS, ROTATION_LOG)
        finally:
            fcntl.flock(lk, fcntl.LOCK_UN)


def write_row(arm, a):
    """One row for the run, or why none: the fence asked again here, as autofinish-run's rotation_row does."""
    fenced = rotation_fence(a.repo)
    if fenced:
        return "no builder row: %s" % fenced
    row = {"ts": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
           "host": os.environ.get("DISPATCH_HOST") or common.host_name(),
           "repo": os.path.basename(a.repo), "primary": a.repo, "branch": a.branch, "topic": a.topic,
           "session": a.session, "account": a.account or None, "queue": a.queue or None,
           "arm": arm["name"], "coin": arm["coin"], "forced": arm["forced"], "model": arm["model"],
           "effort": arm["effort"], "until": arm["until"], "brief_class": a.brief or None,   # never `brief`: a run record's `brief` is a path
           # the odds of the code that wrote the row (the word does not carry the draw's): 1/5 until 2026-11-03, 3/5 since;
           # a word drawn before the landing and fired after it says 3/5, so rows within a day of it may be 1/5 draws
           "odds": "%d/%d" % (SONNET_IN, ODDS)}
    with rotation_lock() as path:
        with open(path, "a") as f:
            f.write(json.dumps(row, ensure_ascii=False) + "\n")
    return None


def main(argv):
    ap = argparse.ArgumentParser(prog="buildercoin.py")
    sub = ap.add_subparsers(dest="cmd", required=True)
    d = sub.add_parser("draw"); d.add_argument("repo")
    w = sub.add_parser("arm"); w.add_argument("word"); w.add_argument("--repo", default="")
    r = sub.add_parser("row"); r.add_argument("word")
    for k in ("--repo", "--branch", "--topic", "--session"):
        r.add_argument(k, required=True)
    r.add_argument("--account", default=""); r.add_argument("--queue", default="")
    r.add_argument("--brief", default="")   # no choices: a class this list lacks must not lose the row (dispatch's || true)
    sub.add_parser("specced"); sub.add_parser("rotates")
    a = ap.parse_args(argv)
    if a.cmd == "specced":
        return 0 if specced(sys.stdin.read()) else 1
    if a.cmd == "rotates":
        c = rotates(sys.stdin.read())
        if c:
            print(c)
        return 0 if c else 1
    if a.cmd == "draw":
        word, why = draw(os.path.realpath(a.repo))
        if word:
            print(word)
        # with no key file the start is unchanged, said nothing (the finisher's `arm=off` rule)
        if word or "no %s" % ROTATION_KEY not in why:
            print(why, file=sys.stderr)
        return 0
    arm = arm_of(a.word)
    if arm is None:
        print("buildercoin.py: %r is no builder arm" % a.word, file=sys.stderr)
        return 1
    if a.cmd == "arm":
        if a.repo:
            # at fire time: the switch and its end stop a word drawn before them, and a repo fenced since the draw
            # runs today's builder with no arm, so its run, record, row and log agree
            end, why = rotation_window()
            fenced = rotation_fence(os.path.realpath(a.repo)) if end else None
            if end is None or fenced:
                print(why if end is None else "fenced: %s" % fenced)
                return 1
            if datetime.date.fromisoformat(arm["until"]) < datetime.date.today():
                print("its window ended %s" % arm["until"])
                return 1
        print(arm["model"], arm["effort"], json.dumps(arm, separators=(",", ":")))
        return 0
    a.repo = os.path.realpath(a.repo)
    why = write_row(arm, a)
    if why:
        print(why, file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
