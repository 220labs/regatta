#!/usr/bin/env python3
"""The guard in collect.py (bin/session_status.py), pinned: the two misses of 2026-10-02 and the
shapes around them. Run: python3 bench/sessions/test_collect.py (bin/test_pickup.sh runs it too)."""
import json
import os
import sys
import tempfile

# A registry of its own, read before collect loads session_status (its GUARDED is read at import):
# the guarded repos are the fixture's, never this Mac's.
_reg = os.path.join(tempfile.mkdtemp(), "repos.json")
with open(_reg, "w") as fh:
    json.dump({"guarded": ["_vault", "transcripts", "diary", "taxes"]}, fh)
os.environ["CLAUDE_REPOS_JSON"] = _reg
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import collect  # noqa: E402

H = os.path.expanduser("~")
P = H + "/projects"
S = collect.slug_of(P)  # this machine's root slug (-Users-<login>-projects), so the cases hold on either Mac
CASES = [
    # (project_dir slug, first cwd, last cwd, guarded?)  — why
    (S + "-diary", P + "/diary", P, True),                       # b352b002: ended at the root
    (S + "-harbor", P + "/harbor", P + "/transcripts/household", True),  # 430da882: subfolder of a guarded repo
    (S + "--overlay", H + "/Library/Application Support/Claude/scratch-workspaces/x/y", P + "/_overlay", True),  # outside ~/projects
    (S + "--vault", P + "/_vault", P + "/_vault", True),  # the slug alone must fire
    (S + "--vault-me", None, None, True),                       # a subfolder slug
    (S + "-diary--claude-worktrees-entries", P + "/diary", P + "/diary/.claude/worktrees/entries", True),
    (S, P, P, True),                                               # the root itself
    (S + "-harbor", P + "/harbor", P + "/harbor/.claude/worktrees/x", False),
    (S + "--overlay--claude-worktrees-jev-sessions", P + "/_overlay/.claude/worktrees/jev-sessions", P + "/_overlay", False),
    (S + "-studio-pipeline", P + "/studio/pipeline", P + "/studio/pipeline", False),
    (S + "-taxes", P + "/taxes", P + "/taxes", True),
]
bad = 0
for slug, first, last, want in CASES:
    got = collect.is_guarded(slug, first, last)
    mark = "ok  " if got == want else "FAIL"
    bad += got != want
    print("  %s guarded=%-5s slug=%s first=%s last=%s" % (mark, got, slug, first, last))
assert collect.slug_of("/Users/sam/projects/_vault") == "-Users-sam-projects--vault"
# the cases above build slugs with slug_of itself, so these pin it to folder names Claude Code wrote
# (as Claude Code wrote them on the laptop, 2026-10-05): a worktree, a path with a space
assert collect.slug_of("/Users/sam/projects/_overlay/.claude/worktrees/sessions-status") == \
    "-Users-sam-projects--overlay--claude-worktrees-sessions-status"
assert collect.slug_of("/Users/sam/Library/Application Support/Claude/scratch-workspaces") == \
    "-Users-sam-Library-Application-Support-Claude-scratch-workspaces"
assert collect.repo_of(P + "/harbor/.claude/worktrees/x") == "harbor"
print("all passed" if not bad else "%d FAILED" % bad)
sys.exit(1 if bad else 0)
