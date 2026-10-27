#!/usr/bin/env python3
"""SessionEnd hook: commit whatever changed in the vault, then push its main to GitHub. (Until
2026-09-26 it pushed the layer's main too; the layer launches through pull requests, so an agent
hook never pushes its main.) Where the vault is: lib/atlaslib.py; none configured, it does nothing.

The vault collects episodic material all week without anyone deciding to commit it: Claude's
auto-memory for every adopted project (`memory/<project>/`), the bulletin, `inbox/` notes
from the phone. A hook versions it, because a session working in some other repo's worktree
cannot run git against the vault at all — Claude Code's worktree isolation refuses any git
command aimed outside the worktree. Hooks run outside that guard.

Since 2026-09-22 it also SENDS: the vault has no branch flow for its records — main is the
working branch on every machine — and its job is to be identical everywhere, so after the
commit it is `pull --rebase`d onto origin and pushed. A rebase that conflicts is aborted and
posted to the bulletin for the next session to resolve by hand — a hook never resolves a
conflict. The vault's pre-push guard allows main only as a fast-forward.

Since the vault joined the worktree workflow (2026-09-29), only the records listed in its
.claude/workflow.json `in_place` are meant to change on main; the rest launches through reviewed
PRs (knowledge-commit --open/--in). This hook still commits everything — leaving a gated file
dirty would stop the push below, and with it the sync between the machines — but a sweep that
took a gated path posts one bulletin line naming it (the owner's decision, 2026-09-29), before
the commit, so the line rides in it to the other machine. The owner changes gated files only
through PRs, so such a line means a write got past the gate: an edit by sed or a heredoc, or a
tool without Claude Code's hooks.

Only on the default branch, never while a merge or rebase is in progress. Concurrent
SessionEnds race on git's index lock; the loser simply leaves its changes for the next one.
Stdlib only. Never blocks a session from ending; offline is a quiet no-op.
"""
import json
import os
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "lib"))
import atlaslib  # noqa: E402

VAULT = atlaslib.repo("vault")   # None: the overlay wrote none — main() says so and does nothing
BULLETIN = Path(__file__).resolve().parent / "bulletin.py"
KNOWLEDGE_COMMIT = Path(__file__).resolve().parent.parent / "bin" / "knowledge-commit"
BUSY = ("rebase-merge", "rebase-apply", "MERGE_HEAD", "CHERRY_PICK_HEAD")


def git(repo, *args, timeout=20):
    return subprocess.run(["git", "-C", str(repo), *args], capture_output=True, text=True, timeout=timeout)


def usable(repo):
    return (repo is not None and (repo / ".git").is_dir() and not any((repo / ".git" / m).exists() for m in BUSY)
            and git(repo, "symbolic-ref", "--quiet", "--short", "HEAD").stdout.strip() == "main")


def in_place_entries():
    """The vault's records written on main (workflow.json `in_place`), or [] — no opt-in yet,
    or the no-workflow marker: then every path is a record, as before."""
    if (VAULT / ".claude" / "no-workflow").exists():
        return []
    try:
        v = json.loads((VAULT / ".claude" / "workflow.json").read_text()).get("in_place")
    except (OSError, ValueError, AttributeError):
        return []
    return [e.strip("/") for e in v if isinstance(e, str) and e.strip("/")] if isinstance(v, list) else []


def gated_dirt():
    """Dirty paths outside in_place, read before the commit so the bulletin line can ride in it."""
    entries = in_place_entries()
    if not entries or not usable(VAULT):
        return []
    items, out, skip = git(VAULT, "status", "--porcelain", "-z").stdout.split("\0"), [], False
    for item in items:
        if skip:
            skip = False
            continue
        if len(item) > 3:
            out.append(item[3:].rstrip("/"))
            skip = item[0] in "RC" or item[1] in "RC"
    return [p for p in out if not any(p == e or p.startswith(e + "/") for e in entries)]


def commit_vault():
    """Commit everything on main (gated_dirt() already named what the gate would have stopped)."""
    if not usable(VAULT) or not git(VAULT, "status", "--porcelain").stdout.strip():
        return
    if git(VAULT, "add", "-A").returncode != 0:
        return
    changed = [p for p in git(VAULT, "-c", "core.quotePath=false", "diff", "--cached", "--name-only").stdout.split("\n") if p]
    areas = sorted({p.split("/", 1)[0] for p in changed})
    subject = f"Vault: {', '.join(areas)} ({len(changed)} file{'s' if len(changed) != 1 else ''})"
    git(VAULT, "commit", "-q", "-m", subject, "-m", "Auto-committed at session end by hooks/vault_commit.py.")


def push_main(repo):
    """pull --rebase then push, for a clean main with an origin. Returns a note or None.

    A refused push is tried once more from the fetch, but only if origin moved meanwhile: SessionEnds
    on two Macs push the same main, and one that lands between this fetch and this push makes it a
    non-fast-forward. Before 2026-10-26 that was the end of it: a bulletin line, whose own commit put
    main further from origin, with nothing left to retry. A refusal with origin unmoved is lasting
    (a guard, a credential) and a second push would fail the same way."""
    name = repo.name
    if os.environ.get("CLAUDE_HOOK_NO_PUSH"):
        return None
    refused = f"{name}: push of main refused — see the repo's pre-push"
    try:
        for attempt in (0, 1):
            # Rechecked per attempt: a parallel session may have dirtied the tree or started a rebase
            # while the first push ran, and a rebase then fails for a reason that is not a conflict.
            if not usable(repo):
                return None
            if git(repo, "remote", "get-url", "origin").returncode or git(repo, "status", "--porcelain").stdout.strip():
                return None
            if git(repo, "fetch", "-q", "origin", timeout=40).returncode:
                return refused if attempt else None  # offline
            if git(repo, "rev-parse", "--verify", "-q", "origin/main").returncode:
                ahead, behind = 1, 0  # origin has no main yet: the first push creates it
            else:
                counts = git(repo, "rev-list", "--left-right", "--count", "main...origin/main").stdout.split()
                ahead, behind = (int(x) for x in counts) if len(counts) == 2 else (0, 0)
            if attempt and not behind:
                return refused
            if behind:
                if git(repo, "rebase", "-q", "origin/main", timeout=60).returncode:
                    git(repo, "rebase", "--abort")
                    return f"{name}: main diverged from origin and the rebase conflicts — resolve by hand"
            if not ahead or not git(repo, "push", "-q", "origin", "main", timeout=60).returncode:
                return None
        return f"{name}: push of main refused twice — see the repo's pre-push"
    except subprocess.TimeoutExpired:
        return None


def post(note, why="a knowledge repo needs a hand"):
    try:
        subprocess.run([sys.executable, str(BULLETIN), "--post", why, note],
                       capture_output=True, text=True, timeout=10)
    except Exception:
        pass


def main() -> int:
    try:
        sys.stdin.read()  # the event payload; nothing in it changes what we do
    except Exception:
        pass
    if VAULT is None:
        print(atlaslib.missing("vault"), file=sys.stderr)
        return 0
    gated = gated_dirt()
    if gated:  # before the commit, so the line rides in it and reaches the other Mac (review)
        more = f" +{len(gated) - 4}" if len(gated) > 4 else ""
        post(f"Vault: {', '.join(gated[:4])}{more} committed on main without review at session end "
             f"(outside in_place, .claude/workflow.json) — if not the owner's own edit, read the latest "
             f"'Vault:' commit; launch the next one with {KNOWLEDGE_COMMIT} "
             f"{(atlaslib.key('vault') or ('vault',))[0]} --open/--in",
             why="a gated vault file changed without review")
    commit_vault()
    for repo in (VAULT,):  # the layer launches through its PRs; its main is never pushed from here
        note = push_main(repo)
        if note:
            post(note)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as e:
        print(f"vault_commit: {e}", file=sys.stderr)
        sys.exit(0)
