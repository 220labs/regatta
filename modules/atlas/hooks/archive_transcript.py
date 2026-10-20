#!/usr/bin/env python3
"""SessionEnd hook: keep a copy of this session's transcript outside Claude Code's 30-day sweep.

Claude Code deletes .claude/projects/<project>/<session>.jsonl in the home folder after
`cleanupPeriodDays` (default 30). The transcript is the only record of a discussion-only turn —
checkpoint commits carry prompts only for turns that changed files — and it is what Aurora's
dream reads weekly. So: copy it, plus the project's auto-summary index, to
transcripts/<repo>/<date>-<session8>.jsonl in the projects folder. Outside git on purpose: 127 MB
in nine days on the first machine, and a transcript can contain a token pasted in passing.

Wire it on SessionEnd with an absolute path, in the user settings so every project gets it
(on the owner's Macs the overlay's `bootstrap.sh --hooks` does).

Stdlib only. Never blocks: any failure is printed and the hook exits 0.
"""
import datetime
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

ARCHIVE = Path(os.environ.get("CLAUDE_TRANSCRIPT_ARCHIVE") or Path.home() / "projects" / "transcripts").expanduser()


def repo_name(cwd: str) -> str:
    """Basename of the *main* checkout, so a worktree's sessions file with its repo."""
    try:
        common = subprocess.run(["git", "rev-parse", "--git-common-dir"], cwd=cwd, capture_output=True,
                                text=True, timeout=5).stdout.strip()
        if common:
            return Path(os.path.join(cwd, common)).resolve().parent.name
    except Exception:
        pass
    return Path(cwd).name or "unknown"


def main() -> int:
    try:
        data = json.load(sys.stdin)
    except Exception:
        return 0
    src = data.get("transcript_path")
    if not src or not os.path.isfile(src) or os.path.getsize(src) == 0:
        return 0
    session = str(data.get("session_id", "session"))[:8]
    dest_dir = ARCHIVE / repo_name(data.get("cwd") or os.getcwd())
    dest_dir.mkdir(parents=True, exist_ok=True)
    day = datetime.date.fromtimestamp(os.path.getmtime(src)).isoformat()
    dest = dest_dir / f"{day}-{session}.jsonl"
    # SessionEnd can fire more than once for one session (after a clear, and again when it is continued); the file only grows.
    if not dest.exists() or dest.stat().st_size < os.path.getsize(src):
        shutil.copy2(src, dest)
    # Subagent transcripts live beside the session file in <session-id>/subagents/ (agent-*.jsonl
    # plus a .meta.json naming the agent type). Without them, which agent spent what is lost at the
    # 30-day sweep; bin/usage-report reads them (usage-report D5, 2026-09-22). Same grow-only rule.
    subs = Path(src).with_suffix("") / "subagents"
    if subs.is_dir():
        sub_dest = dest_dir / f"{day}-{session}" / "subagents"
        sub_dest.mkdir(parents=True, exist_ok=True)
        for f in subs.iterdir():
            t = sub_dest / f.name
            if f.is_file() and (not t.exists() or t.stat().st_size < f.stat().st_size):
                shutil.copy2(f, t)
    index = Path(src).parent / "sessions-index.json"  # Claude Code's own per-session summaries
    if index.is_file():
        shutil.copy2(index, dest_dir / "sessions-index.json")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as e:  # never block a session from ending
        print(f"archive_transcript: {e}", file=sys.stderr)
        sys.exit(0)
