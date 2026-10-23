#!/usr/bin/env python3
"""carried: discard a primary checkout's uncommitted edit that a launch already carries.

The owner answers in a doc on the primary checkout (`/keel --on-main`; the rule that put docs
on main to be answered was retired 2026-09-29, but answers typed there still happen). The agent may not commit there, so the session copies the
doc into its branch, replies under each hunk, and launches. The answers then sit on main AND,
uncommitted, in the primary — and `git merge --ff-only` refuses to overwrite them, so the
primary never fast-forwards: knowledge-commit says "did not fast-forward (dirty or
diverged)" and sync.py "left alone — the tree is dirty" at every start, until someone
discards the copy by hand (docs/handoff/2026-09-29-doc-answers-carry.md).

settle(repo, ref) runs before that fast-forward. It looks only at Markdown files (the docs
the owner answers in) under SIZE_CAP, modified plainly — status ` M` or `M ` (index equal to the
worktree); never `MM`, whose staged text the checkout would lose, and never untracked,
deleted, renamed or symlinked ones. For each it compares three texts — base = HEAD's,
ours = the file on disk, theirs = `ref`'s — and discards ours only when `ref` carries it
line for line, or when a commit between HEAD and `ref` holds ours byte for byte (`recorded`):
  - every line of ours appears in theirs, in order (theirs = ours plus inserted lines only:
    the replies), and
  - every base line ours removed is removed in theirs too (a deletion the owner made is not
    silently undone by a main that kept the line).
Lines are split on "\n" only, so a changed line ending or final newline is a change.
Anything else is left exactly as it is. `ref` must be a descendant of HEAD (a diverged
primary is not this case), and nothing is done mid-merge or mid-rebase. Each discarded copy is
saved first under <git-dir>/claude/carried/<stamp>/<path>, and the file is re-read just
before the checkout, so an autosave in between keeps it. `whole=True` (sync.py) discards only
when that leaves the tree clean: otherwise the fast-forward would not happen and the answers
would vanish from the open doc for nothing (review, 2026-09-29).

Why not `git merge-file`: an answer the owner typed and a reply inserted right under it are
adjacent changes, and merge-file reports them as a conflict (tried 2026-09-29). difflib's
alignment of repeated identical lines (blank lines) can differ from git's; the error that
allows is at worst a discarded deletion of a duplicate blank line, with the copy kept.

  carried.py <repo> <ref>     settle, and say what was discarded (silent when nothing was)
  carried.py <repo> --pull    fetch origin, settle against origin/<branch>, pull --ff-only —
                              the primary's pull after a merge (/finish step 11,
                              knowledge-commit); a script run by path, so a session in a
                              worktree may run it where `git -C <primary>` is refused

Stdlib only; never exits non-zero.
"""
import difflib
import hashlib
import subprocess
import sys
import time
from collections import Counter
from pathlib import Path

SIZE_CAP = 256 * 1024  # difflib is quadratic at worst, and this runs at every session start
BUSY = ("MERGE_HEAD", "CHERRY_PICK_HEAD", "REVERT_HEAD", "rebase-merge", "rebase-apply")


def git(repo, *args):
    # --literal-pathspecs: a doc named `why?.md` or `a [draft].md` is that file, not a glob.
    return subprocess.run(["git", "-C", str(repo), "--literal-pathspecs", *args],
                          capture_output=True, timeout=30)


def carries(base, ours, theirs):
    """Whether `theirs` holds every change `ours` made to `base`, line for line."""
    if ours == theirs:
        return True
    if Counter(ours) - Counter(theirs):  # a line of ours main lacks: no alignment can fix it
        return False
    to_theirs = difflib.SequenceMatcher(None, ours, theirs, autojunk=False).get_opcodes()
    if any(tag not in ("equal", "insert") for tag, *_ in to_theirs):
        return False

    def removed(new):
        ops = difflib.SequenceMatcher(None, base, new, autojunk=False).get_opcodes()
        return {i for tag, i1, i2, _, _ in ops if tag in ("delete", "replace") for i in range(i1, i2)}
    return removed(ours) <= removed(theirs)


def status(repo):
    """(xy, path) for every entry, untracked included; a rename's source is not an entry."""
    tokens = git(repo, "status", "--porcelain=v1", "-z").stdout.decode("utf-8", "replace").split("\0")
    out, skip = [], False
    for tok in tokens:
        if skip:
            skip = False
            continue
        if len(tok) > 3:
            out.append((tok[:2], tok[3:]))
            skip = "R" in tok[:2] or "C" in tok[:2]
    return out


def blob(repo, rev, path):
    r = git(repo, "show", f"{rev}:{path}")
    return r.stdout if r.returncode == 0 else None


def lines(data):
    try:
        return data.decode("utf-8").split("\n")
    except UnicodeDecodeError:
        return None


def recorded(repo, ref, path, ours, base, theirs):
    """Whether a commit between HEAD and `ref` holds `path` exactly as `ours`, and `ref` still keeps
    every change ours made to `base` — the commit that recorded the owner's answers verbatim before
    replies and edits went on top. It covers the branch that also changed lines the owner left alone,
    which `carries` rightly refuses (autofinish-everything, 2026-10-12: the primary sat 27
    commits behind on a copy identical to adf29ab); a later commit that undid one of the owner's
    lines or deletions makes it refuse (code review, 2026-10-13). One `git log --raw`; the blob
    id is hashed here."""
    ops = difflib.SequenceMatcher(None, base, ours, autojunk=False).get_opcodes()
    added = Counter(l for tag, _, _, j1, j2 in ops if tag in ("insert", "replace") for l in ours[j1:j2])
    if added - Counter(theirs):
        return False

    def removed(new):
        o = difflib.SequenceMatcher(None, base, new, autojunk=False).get_opcodes()
        return {i for tag, i1, i2, _, _ in o if tag in ("delete", "replace") for i in range(i1, i2)}
    if not removed(ours) <= removed(theirs):
        return False
    data = "\n".join(ours).encode("utf-8")
    want = hashlib.sha1(b"blob %d\0" % len(data) + data).hexdigest()
    raw = git(repo, "log", "--format=", "--raw", "--no-abbrev", "--no-renames", f"HEAD..{ref}", "--", path)
    return any(ln.split()[3] == want for ln in raw.stdout.decode("utf-8", "replace").splitlines()
               if ln.startswith(":") and len(ln.split()) > 4)


def settle(repo, ref, whole=False):
    """Discard what `ref` carries; return the discarded paths."""
    repo = Path(repo)
    gitdir = Path(git(repo, "rev-parse", "--path-format=absolute", "--git-dir").stdout.decode().strip())
    if any((gitdir / m).exists() for m in BUSY):
        return []
    if git(repo, "merge-base", "--is-ancestor", "HEAD", ref).returncode:
        return []
    entries = status(repo)
    if whole and any(xy not in (" M", "M ") or not path.endswith(".md") for xy, path in entries):
        return []
    found = {}
    for xy, path in entries:
        f = repo / path
        if xy not in (" M", "M ") or not path.endswith(".md") or f.is_symlink():
            continue
        try:
            ours = f.read_bytes()
        except OSError:
            continue
        base, theirs = blob(repo, "HEAD", path), blob(repo, ref, path)
        if base is None or theirs is None or max(len(ours), len(base), len(theirs)) > SIZE_CAP:
            continue
        b, o, t = lines(base), lines(ours), lines(theirs)
        if None not in (b, o, t) and (carries(b, o, t) or recorded(repo, ref, path, o, b, t)):
            found[path] = ours
        elif whole:  # one doc not carried: the tree cannot end clean, so stop here
            return []
    if whole and len(found) != len(entries):
        return []
    stash = gitdir / "claude" / "carried" / time.strftime("%Y%m%d-%H%M%S")
    done = []
    for path, ours in found.items():
        keep = stash / path
        keep.parent.mkdir(parents=True, exist_ok=True)
        keep.write_bytes(ours)
        try:
            if (repo / path).read_bytes() != ours:  # edited since it was read
                continue
        except OSError:
            continue
        if git(repo, "checkout", "HEAD", "--", path).returncode == 0:
            done.append(path)
    return done


def said(repo, ref, done):
    return (f"{Path(repo).name}: discarded the primary's copy of {', '.join(done)} — "
            f"{ref} carries it, line for line or recorded verbatim (a copy is kept under .git/claude/carried/)")


def pull(repo):
    branch = git(repo, "symbolic-ref", "--quiet", "--short", "HEAD").stdout.decode().strip()
    if not branch:
        print(f"{Path(repo).name}: the primary is not on a branch — not pulled", file=sys.stderr)
        return
    if git(repo, "fetch", "-q", "origin", branch).returncode == 0:
        done = settle(repo, f"origin/{branch}")
        if done:
            print(said(repo, f"origin/{branch}", done))
    if git(repo, "merge", "-q", "--ff-only", f"origin/{branch}").returncode:
        print(f"{Path(repo).name}: merged, but the primary did not fast-forward (dirty or diverged) "
              "— sync.py retries at the next session start", file=sys.stderr)


def main():
    args = sys.argv[1:]
    if len(args) != 2:
        print(__doc__.split("\n\n")[-2].strip(), file=sys.stderr)
        return 0
    repo, ref = args
    if ref == "--pull":
        pull(repo)
        return 0
    done = settle(repo, ref)
    if done:
        print(said(repo, ref, done))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as e:
        print(f"carried: {e}", file=sys.stderr)
        sys.exit(0)
