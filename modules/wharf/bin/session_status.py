"""Is this idle session done, waiting on the owner, blocked or running — decided by code alone.

One home for the rules `bin/pickup list` prints and bench/sessions scores, so the bench measures
exactly what the owner sees (docs/record/jev-sessions-bench-2026-10-02.md, D2, D5, D6). No model is called
here, ever: a model replaces the ask-words rule only after a second week's bench clears H2
(+0.10 over the rule, and an interval against Haiku whose lower bound is above −0.05).

decide() — first match wins; each answer names the rule that gave it:

    live: busy         the session registry says the process is working right now (D5)
    live: task         live but idle, while a background task or subagent of it wrote in the last
                       minute (pickup's busy_files) — its result is still to come (D5)
    live: waiting      the registry says the process waits for input (`waitingFor`) → waiting on the owner
    guarded            the session lives in a guarded repo (the registry's list), transcripts, the ~/projects
                       root or outside it (D3) — its text is not read: "guarded — open it"
    closing line       a fixed upper-case last line: /finish's "BUT READ THE NOTE" → "done — read
                       the note" (D6); the WAITING line (orchestration proposal A1) → waiting on
                       the owner; the RELAYED line (session-asks R4) → waiting on skipper; the WAITING
                       FOR SOMETHING line → waiting on its own work, and its hand-over form
                       (common.HANDOVER_LINE) → handed to its launch; every other fixed line → done
    pending tool call  a tool call with no result after the owner's last prompt: a permission or an
                       interrupted call → waiting on the owner
    api error          the last record is Claude Code's stand-in for an API failure (a limit, an
                       expired login: `isApiErrorMessage`, model `<synthetic>`) → blocked
    memo link          a GitHub edit link or a hand-over line's course link in the tail: an answer is owed → waiting on the owner
    question           the last line ends in "?" → waiting on the owner
    ask-words          ASK_RE in the last 600 characters (the bench's pre-registered rule) → waiting
    (none)             "unsure" — never a guess at done

Python 3.9, stdlib only.
"""
import os
import re
import sys

DONE, NOTE, BLOCKED, RUNNING = "done", "done — read the note", "blocked", "running"
PENDING = "waiting on its own work"   # WAITING FOR SOMETHING: its reviewers, check or poll wake it
HANDED = "handed to its launch"   # the hand-over line (common.HANDOVER_LINE): dispatch's launch takes the landing
RELAYED = "waiting on skipper"   # session-asks R4: the RELAYED line — an ask is out with the run's skipper
RELAYED_BEFORE_S5 = "waiting on manager"   # the same, from a peer's checkout older than rename S5 (stalls reads both)
UNSURE, GUARDED_WORDS = "unsure", "guarded — open it"

# The fixed closing lines are one table, hooks/common.py's CLOSING — what the Stop hook holds every
# reply to (orchestration step 10, A2) — read through its ending(): the reply's last line, links
# allowed after it, or none counts. /finish's "BUT READ THE NOTE" line is kept apart (D6).
# The core by lib/core_path.py (C2): this file's folder is the module's bin/, not the core's hooks/.
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "lib"))
import core_path  # noqa: E402
core_path.add()  # a library: no core is the ImportError below, its caller's to report
import common  # noqa: E402
from common import FINISH_LINES, ending  # noqa: E402
# Waiting on the person the closing lines address: the core's owner key (on the owner's Macs the
# same words as before the scrub, which pickup, helm's stalls and plumb's bench compare), else
# "the owner".
OWNER = common.OWNER_NAME or "the owner"
WAITING = f"waiting on {OWNER}"
# A memo's answer link: GitHub's edit page (until 2026-10-07), or the hand-over line's course part
# (bin/keel `line`: only a doc with D-items gets one, so it means an answer is owed).
MEMO_LINK_RE = re.compile(r"github\.com/[^\s)]+/edit/|\[(?:course|form)\]\(http://127\.0\.0\.1:\d+/")  # `form` until 2026-10-17
# Pre-registered 2026-10-02 before any label was typed (bench/sessions/score.py rule()); moved
# here verbatim so pickup and the bench run the same pattern. Changing it changes the baseline.
ASK_RE = re.compile(r"\b(please|could you|can you|would you|let me know|your call|when you|you need to|"
                    r"run (this|it|the)|paste|say (go|yes|when)|confirm|check that|have a look|tell me|"
                    r"if you want|do you want|up to you|needs? (your%s))\b"
                    % ("|" + re.escape(common.OWNER_NAME.lower()) if common.OWNER_NAME else ""), re.I)
ASK_TAIL = 600

# ---- the guard (D3; the two misses that shaped it: the bench doc's F0) ----------------------
# `transcripts` holds every project's text, the guarded ones' included; a session run there sees it all.
# The list is the registry's `guarded` (common.guarded_repos(), G32), never a literal here, and no
# import of helm's helmlib, which would make wharf and helm require each other. A registry without
# the list yet falls back to helmlib's (planlib's before rename S5) when helm is there, so the guard never holds less meanwhile.


def _guarded_list():
    names = tuple(common.guarded_repos())
    if names:
        return names
    p = common.tool("helmlib.py") or common.tool("planlib.py")
    if not p:
        return ()
    try:
        import importlib.util
        spec = importlib.util.spec_from_file_location("helmlib", str(p))
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        return tuple(mod.GUARDED)
    except Exception:
        return ()


GUARDED = _guarded_list()


def guarded(repo):
    """A repo path or name with a part in GUARDED, case-folded (APFS is case-insensitive): a
    worktree's toplevel (…/<repo>/.claude/worktrees/x) is named for its topic, not its repo."""
    if not repo:
        return False
    names = {g.casefold() for g in GUARDED}
    from pathlib import Path
    return any(part.casefold() in names for part in Path(os.path.expanduser(str(repo))).parts)


def projects_root():
    return os.path.expanduser("~/projects")  # read per call: the tests move HOME


def slug_of(path):
    """Claude Code's folder slug for a cwd: every non-alphanumeric character becomes a dash
    (`~/projects/_notes` → `-Users-sam-projects--notes`). Computed, never parsed."""
    return re.sub(r"[^A-Za-z0-9]", "-", os.path.normpath(path))


def guarded_path(cwd):
    """A cwd is guarded when it is the ~/projects root, anything outside it (home, Library,
    Claude's scratch workspaces — a session there sees whatever it likes), or inside a guarded
    repo's folder at any depth (`~/projects/transcripts/notes` included)."""
    if not cwd:
        return False
    p = os.path.normpath(os.path.realpath(os.path.expanduser(cwd)))
    root = os.path.realpath(projects_root())
    if p == root or not p.startswith(root + "/"):
        return True
    return guarded(os.path.relpath(p, root))


def is_guarded(project_dir, first_cwd, last_cwd):
    """Guarded if ANY of the session's homes is: the slug its file lives under, the cwd of its first
    record, or the cwd of its last reply. Two misses taught the shape (2026-10-02, both recorded in
    docs/record/jev-sessions-bench-2026-10-02.md F0): b352b002 sat under a guarded repo's slug but ended with
    cwd ~/projects and was read as repo "projects"; 430da882 ended in ~/projects/transcripts/notes
    and was read as "notes" because the old test took the cwd's basename. Hence: slugs compared
    against computed slugs, cwds by path prefix, never a basename. The root is slugged both as
    written and resolved (/var → /private/var on macOS), since a transcript's slug is whichever
    path its cwd was."""
    if any(guarded_path(c) for c in (first_cwd, last_cwd)):
        return True
    if not project_dir:
        return False
    roots = {projects_root(), os.path.realpath(projects_root())}
    under = [r for r in roots if project_dir.startswith(slug_of(r) + "-")]
    if not under:
        return True  # the root itself, or a folder outside ~/projects
    pd = project_dir.casefold()  # case-folded, as guarded(): APFS is case-insensitive
    for r in under:
        for g in GUARDED:
            s = slug_of(os.path.join(r, g)).casefold()
            if pd == s or pd.startswith(s + "-"):
                return True
    return False


# ---- the rules ------------------------------------------------------------------------------

def closing(text):
    """The status the reply's closing line gives, or None — the Stop hook's own reading, so the
    same line counts here or none does."""
    kind, line, _ = ending(text)
    if kind == "waiting":
        return WAITING
    if kind == "relayed":
        return RELAYED
    if kind == "handed":   # its own word for helm: an ended run whose launch never started is raised, never retried
        return HANDED
    if kind == "pending":   # never RUNNING, the busy word (D5): the session may be gone and nothing wake it
        return PENDING
    if kind == "done":
        return NOTE if line == FINISH_LINES[1] else DONE
    return None


def code_rule(text, pending=0, api_error=False):
    """(status, rule) from the rules code is sure of — the closing line through the question mark —
    or (None, None): the judgment set the bench is about."""
    text = text or ""
    status = closing(text)
    if status:
        return status, "closing line"
    if pending:
        return WAITING, "pending tool call"
    if api_error:
        return BLOCKED, "api error"
    tail = text.rstrip()
    if MEMO_LINK_RE.search(tail[-1500:]):
        return WAITING, "memo link"
    last_line = tail.splitlines()[-1].strip() if tail else ""
    if last_line.endswith("?"):
        return WAITING, "question"
    return None, None


def ask_words(text):
    return bool(ASK_RE.search((text or "")[-ASK_TAIL:]))


def decide(text, pending=0, api_error=False, live_status=None, guarded=False):
    """(status, rule) for one idle or closed session; rule is None for "unsure" and "guarded"."""
    if live_status in ("busy", "task"):
        return RUNNING, f"live: {live_status}"
    if live_status == "waiting":
        return WAITING, "live: waiting"
    if guarded:
        return GUARDED_WORDS, None
    status, rule = code_rule(text, pending, api_error)
    if status:
        return status, rule
    if ask_words(text):
        return WAITING, "ask-words"
    return UNSURE, None


def label(status, rule):
    """The words a list prints: `waiting on the owner (ask-words)`, `unsure`, `guarded — open it`."""
    return f"{status} ({rule})" if rule else status
