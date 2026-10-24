#!/usr/bin/env python3
"""doc_answers: when the owner says the answers are in a doc, put the changed docs in front of the model.

The owner answers anywhere in a doc, not only under `➤ Answer:` (2026-09-26); a session that asked
"which question?" cost two turns, and twelve prompts of the week to 09-27 were of this shape
("Responded", "See my answers in the doc", "Feedback provided"). The rule is in
the overlay's rules; this makes sure the doc is in front of the model when it applies
(dream 2026-09-27 P8, weekly 2026-09-29).

UserPromptSubmit. Silent unless the prompt is a short "responded / answered / see my
answers|notes|comments|feedback / feedback|answers provided / given my feedback / land or launch my
answers / answers on github". Then it adds context naming the Markdown files with uncommitted
changes in the session's repo (and any *.md path in the prompt), with the instruction: diff
each, reply under every changed hunk, then say which.

Since 2026-09-29 answers also arrive as commits made in GitHub's editor on the doc's branch
(`/keel`, docs/feedback-2026-09-29.md D5): on a hit it fetches the current branch (10 s,
silent on failure) and, when GitHub has commits this checkout lacks, names them with the
`memo pull` line. It never rebases — that is `memo pull`'s job.

Stdlib only; never blocks a turn.
"""
import json
import os
import re
import subprocess
import sys
from pathlib import Path

PATTERN = re.compile(
    r"\b(responded|answered|replied"
    r"|see my (answers?|notes?|comments?|feedback|responses?|replies)"
    r"|(feedback|answers?|notes?|comments?) (provided|added|left|given|are in)"
    r"|(answered|responded|commented) (in|on) the (doc|file)"
    r"|given my feedback|(?:land|launch) my answers|answers? (are )?on github)\b", re.I)
IDE_NOISE_RE = re.compile(r"<(ide_[a-z_]+)>.*?</\1>\s*", re.S)  # opened_file, selection, diagnostics


def _config_line(name):
    """The first non-blank line of `<config>/<name>` (the core's config_line, read without it), or ""."""
    cfg = Path(os.environ.get("REGATTA_CONFIG") or Path.home() / ".config" / "regatta").expanduser()
    try:
        return next((l.strip() for l in (cfg / name).read_text(encoding="utf-8-sig").splitlines() if l.strip()), "")
    except (OSError, UnicodeDecodeError):
        return ""


def _keel_cmd():
    """`keel` as the message names it: this module's own bin/keel, under `~` when it is there (the
    overlay's shim came first until B14b, 2026-10-23, which deleted it)."""
    p = Path(__file__).resolve().parent.parent / "bin" / "keel"
    import pwd
    s = str(p)
    for home in (str(Path.home()), pwd.getpwuid(os.getuid()).pw_dir):   # the login's own when HOME moved
        if home and s.startswith(home.rstrip("/") + "/"):
            return "~" + s[len(home.rstrip("/")):]
    return s


MAX_WORDS = 25  # a long prompt that happens to contain "responded" is a real request
FETCH_TIMEOUT = 10


def git(cwd, *args, timeout=5):
    return subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True, timeout=timeout)


def changed_docs(cwd: str):
    try:
        out = git(cwd, "status", "--porcelain", "--", "*.md").stdout
    except Exception:
        return []
    return [l[3:].strip() for l in out.splitlines() if l[:2].strip() in ("M", "MM", "AM", "A", "??")]


def just_committed(cwd: str):
    """.md files in HEAD when HEAD is the checkpoint hook's `wip: changes between turns` — on a
    claude/* branch it commits the owner's tab edits at this same prompt, often before this hook reads
    `git status`, so the docs are clean by the time the model looks (review 2026-09-29)."""
    try:
        if not git(cwd, "log", "-1", "--format=%s").stdout.startswith("wip: changes between turns"):
            return []
        out = git(cwd, "-c", "core.quotePath=false", "show", "--format=", "--name-only", "HEAD", "--", "*.md").stdout
    except Exception:
        return []
    return [l.strip() for l in out.splitlines() if l.strip()]


def github_ahead(cwd: str):
    """(branch, how many commits origin/<branch> has that HEAD lacks), or None — quiet on any failure."""
    try:
        branch = git(cwd, "symbolic-ref", "-q", "--short", "HEAD").stdout.strip()
        if not branch:
            return None
        r = git(cwd, "fetch", "-q", "origin", f"+{branch}:refs/remotes/origin/{branch}", timeout=FETCH_TIMEOUT)
        if r.returncode:
            return None
        n = git(cwd, "rev-list", "--count", f"HEAD..refs/remotes/origin/{branch}").stdout.strip()
        return (branch, int(n)) if n.isdigit() and int(n) else None
    except Exception:
        return None


def main() -> int:
    try:
        data = json.load(sys.stdin)
    except Exception:
        return 0
    # The VS Code extension prefixes which file is open (and any selection or diagnostics): noise, not a doc the owner named — it listed
    # the answered doc twice in the first live /keel run (2026-09-29) and inflates the word count.
    prompt = IDE_NOISE_RE.sub("", str(data.get("prompt", "")))
    if len(prompt.split()) > MAX_WORDS or not PATTERN.search(prompt):
        return 0
    cwd = data.get("cwd") or "."
    docs = changed_docs(cwd)
    committed = [p for p in just_committed(cwd) if p not in docs]
    docs += [p for p in re.findall(r"[\w./~-]+\.md\b", prompt) if p not in docs and p not in committed]
    ahead = github_ahead(cwd)
    owner = _config_line("regatta/owner")   # the core's owner key; the text as before where it is set
    who, whose = (owner, owner + "'s") if owner else ("The owner", "the owner's")
    if committed:
        where = ("The checkpoint just committed " + whose + " edits to " + ", ".join(committed[:10]) +
                 " — read them with `git show HEAD -- <doc>` (`git diff` is empty now).")
        if docs:
            where += " Also changed here: " + ", ".join(docs[:10]) + "."
    elif docs:
        where = "Docs with uncommitted changes here: " + ", ".join(docs[:10]) + "."
    elif ahead:
        where = "No Markdown file has uncommitted changes here."
    else:
        where = ("No Markdown file has uncommitted changes in this checkout — the answers may be in "
                 "the primary checkout, another repo, or a doc on main; look there before asking.")
    if ahead:
        where += (f" GitHub has {ahead[1]} commit(s) on {ahead[0]} this checkout lacks — run "
                  f"`python3 {_keel_cmd()} pull <doc>` first; it names the answers that changed.")
    print(f"📝 {who} says the answers are in a doc. {where} `git diff` each and reply under EVERY changed "
          f"hunk, not only `➤ Answer:` lines — {who} writes questions anywhere (the overlay's rules, 'How to talk'). "
          "Then name which hunks you answered. Answers typed into the primary checkout's copy: "
          "`/keel --on-main <doc>` — reply on your branch, never launch the doc to read them.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as e:
        print(f"doc_answers: {e}", file=sys.stderr)
        sys.exit(0)
