#!/usr/bin/env python3
"""Fork a Claude Code session into a new, independent one — same conversation so far,
new session id — without touching the original.

The fork is a *file*: Claude Code keeps one transcript per session at
~/.claude/projects/<cwd-slug>/<session-id>.jsonl (the slug is the cwd with every
non-alphanumeric character turned into a dash), and a session *is* its transcript —
`claude -r <id>` and the VS Code extension's session picker both just load that
file. So forking writes a copy under a fresh id into this workspace's slug, and the fork
then shows up in the picker (Claude Code side panel → past sessions, at the top: newest
first) with the title `fork · <original title>`. Opening it there is the whole workflow: no
process is started, no model call is made, and the original session is untouched.
Confirmed 2026-09-16: the CLI's own `-r <file>.jsonl` does the same thing
(loads the file, mints a new id), so this is the format's supported use, not a hack.

Not copied verbatim — each is per-session state that must not follow the fork:
  worktree-state / relocated   the original's EnterWorktree bookkeeping; a fork that
                               inherits it thinks it owns that worktree and offers to
                               *remove* it on exit
  file-history-*               /rewind backups, keyed by the original's id
  queue-operation              prompts queued in the original
  bridge-session               the original process's claude.ai Remote Control bridge

What the fork inherited is recorded, never guessed: one `forked-from` record after the copied
ones — `{"type":"forked-from","sessionId":<new>,"from":{"sessionId":<old>,"host":<host>},
"cutoff":<timestamp of the last copied record>,"records":<n>}`. The copied API calls keep
their requestIds but carry the fork's sessionId, so a reader counting per session would count
them twice; `usage-report` and `week-digest` skip a fork's records at or before its cutoff
(teleport design E1, docs/record/teleport-design-2026-10-02.md). `cutoff=` (used by `pickup move`)
copies the file up to the first record stamped after it; titles always go.

Two callers:

  /fork (wharf's skills/fork/SKILL.md) — typed inside a session, it runs this with
  `--session $CLAUDE_CODE_SESSION_ID` (the Bash tool's environment names the session
  exactly), replies with the fork's title, and carries on with what it was doing.

  Cmd+Alt+N in VS Code (task "Claude: Fork latest session", user keybinding) — no
  session in hand, so it forks the one *you last typed in*. Why not the newest
  transcript: agent-driven sessions (loops, routines, subagents) are chatty and keep
  their files the freshest, so "most recently modified" picks them over the session
  a human is actually in. Each transcript is ranked by its last *human-typed* prompt
  instead — a `user` record whose `origin` is `{"kind": "human"}` (hook output, tool
  results, task notifications and injected agent prompts all carry a different origin
  or none at all; checked 2026-09-16 across ~2,500 records). Transcripts with no
  such record are agent sessions and are never candidates.

`--terminal` opens the fork in a new Terminal.app window instead of leaving it for
the picker (via osascript, because a `claude` started inside another one refuses to
run and the Bash tool has no TTY). The fork then starts in this workspace's main
checkout; the checkpoint hook keeps it off `main` and it creates its own worktree
(rule: git-workflow). Two sessions never share a working copy. Born in
the home-automation repo (scripts/fork_claude_session.py); in the layer's bin/ since 2026-09-16.

    fork_claude_session.py                      # fork the session you last typed in
    fork_claude_session.py --session <id>       # fork this exact session (what /fork does)
    fork_claude_session.py ... --terminal       # ...and open it in a new Terminal window
    fork_claude_session.py ... --dry-run        # print what would be forked
    fork_claude_session.py --list               # the ranked candidates
"""
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import time
import uuid
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "lib"))
import core_path  # noqa: E402 — the regatta core (C2); as a library none is the ImportError below,
(core_path.require if __name__ == "__main__" else core_path.add)()  # as the /fork CLI one line, exit 2
from common import host_name  # noqa: E402

SCAN_NEWEST = 30  # transcripts to scan, by mtime — a human session is never older than this many agent runs
IDE_BLOCK = re.compile(r"<(ide_\w+)>.*?</\1>", re.S)
PROJECTS = Path.home() / ".claude" / "projects"
DROP = {"worktree-state", "relocated", "queue-operation", "file-history-snapshot", "file-history-delta",
        "bridge-session", "forked-from"}
KEEP_UNSTAMPED = {"ai-title", "custom-title", "agent-name"}  # names, true whatever the cut
CUTOFF_FORMAT = re.compile(r"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z")  # what transcripts write
PREFIX = "🔀 fork · "


def repo_root() -> Path:
    try:
        common = subprocess.check_output(["git", "rev-parse", "--git-common-dir"], text=True,
                                         stderr=subprocess.DEVNULL).strip()
    except (subprocess.CalledProcessError, OSError):
        return Path.cwd().resolve()  # not a repo: the folder the session runs in
    return (Path(common) / "..").resolve()  # main checkout, even from a worktree


def slug(path) -> str:
    # Every non-alphanumeric character becomes a dash — `_notes` → `--notes`, not
    # `-_notes`. Verified 2026-09-17 against the real directories in ~/.claude/projects.
    # Replacing only `/` and `.` left `_` alone, so in a project whose path has an
    # underscore the glob below matched nothing and /fork reported no transcript.
    return re.sub(r"[^A-Za-z0-9]", "-", str(path))


def transcripts(root: Path):
    return sorted(PROJECTS.glob(f"{slug(root)}*/*.jsonl"), key=os.path.getmtime, reverse=True)


def records(path: Path):
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            try:
                yield json.loads(line)
            except ValueError:
                continue


def last_human_prompt(path: Path):
    """(timestamp, prompt) of the last human-typed prompt in a transcript, or None."""
    ts = prompt = None
    for r in records(path):
        if r.get("type") != "user" or (r.get("origin") or {}).get("kind") != "human":
            continue
        c = r.get("message", {}).get("content")
        text = c if isinstance(c, str) else " ".join(b.get("text", "") for b in c or [] if b.get("type") == "text")
        # The IDE prepends <ide_opened_file>/<ide_selection> blocks; a record that is
        # *only* those (a file opened, nothing typed) still says origin=human, but
        # nobody spoke — strip them and skip the record if nothing is left.
        text = IDE_BLOCK.sub("", text).strip()
        if text:
            ts, prompt = r.get("timestamp"), text
    return (ts, prompt) if ts else None


def candidates(root: Path):
    found = []
    for f in transcripts(root)[:SCAN_NEWEST]:
        hit = last_human_prompt(f)
        if hit:
            found.append((hit[0], f, hit[1]))
    return sorted(found, reverse=True)


def pick(root: Path, session_id):
    """(transcript path, last prompt) — the named session, or the one last typed in."""
    if session_id:
        matches = [f for f in transcripts(root) if f.stem == session_id]
        if not matches:
            sys.exit(f"no transcript for session {session_id} under {PROJECTS}/{slug(root)}*")
        hit = last_human_prompt(matches[0])
        return matches[0], (hit[1] if hit else "")
    ranked = candidates(root)
    if not ranked:
        sys.exit(f"no human-driven Claude Code session found for {root}")
    return ranked[0][1], ranked[0][2]


def fork_transcript(src: Path, dest_dir: Path, new_id: str, cutoff=None, origin=None):
    """Write src as a new session: id rewritten everywhere, title prefixed, per-session state dropped.

    `cutoff` (ISO timestamp, as the transcript writes them): copy only records stamped at or
    before it. `origin`: the host the source lives on (default: this one). A fork of a fork
    drops the parent's `forked-from`: its own cutoff covers everything the parent inherited."""
    if cutoff and not CUTOFF_FORMAT.fullmatch(cutoff):
        # The cut compares strings; another ISO spelling (`+00:00`, no millis) misorders silently
        raise ValueError(f"cutoff must look like 2026-10-02T18:00:00.000Z, got {cutoff!r}")
    old_id, title, n, last, past = src.stem, None, 0, None, False
    dest_dir.mkdir(parents=True, exist_ok=True)
    dest = dest_dir / f"{new_id}.jsonl"
    with open(dest, "w", encoding="utf-8") as out:
        def write(r):
            # Compact separators are load-bearing: the VS Code extension classifies a
            # transcript for its session list by raw substring probes on the file's head
            # and tail (`"parentUuid":`, `"entrypoint":"…"`), never by parsing. A copy
            # written with `", "` / `": "` fails every probe and is dropped from the list
            # as if empty — cost an hour on 2026-09-16.
            out.write(json.dumps(r, ensure_ascii=False, separators=(",", ":")) + "\n")
        for r in records(src):
            if r.get("type") in DROP:
                continue
            ts = r.get("timestamp")
            # A prefix cut: everything from the first record past the cutoff stays behind but
            # names. File order is not timestamp order (655 of 60 transcripts' assistant records sit
            # below a later one, code review 2026-10-02), and a record-by-record filter left
            # replies whose parent was dropped — a session picked up again follows parents from the last leaf.
            if cutoff and ts and ts > cutoff:  # same writer, same ISO format: string order is time order
                past = True
            if past and r.get("type") not in KEEP_UNSTAMPED:
                continue
            if r.get("type") == "ai-title":
                # Emoji first so a fork stands out in the session list next to the live
                # sessions' status dots (2026-09-16); the word keeps it searchable.
                title = r["aiTitle"] if r["aiTitle"].startswith(PREFIX) else f"{PREFIX}{r['aiTitle']}"
                r["aiTitle"] = title
            if r.get("sessionId") == old_id:
                r["sessionId"] = new_id
            write(r)
            n += 1
            if ts and (last is None or ts > last):
                last = ts
        write({"type": "forked-from", "sessionId": new_id, "from": {"sessionId": old_id, "host": origin or host_name()},
               "cutoff": last, "records": n})
    return dest, title, n


def announce(root: Path, session_id: str, title: str, hold_s: float = 4.0):
    """Make the VS Code sidebar notice the new transcript.

    The extension reads its session list only when a list webview connects, then
    never re-reads it on file changes — except for one trigger: a *live* session it
    does not know yet. It watches ~/.claude/sessions/<pid>.json (the registry every
    running `claude` writes itself into), and when an entry appears whose entrypoint
    is `cli`, whose pid is alive and whose cwd is a workspace folder, the sidebar
    re-fetches the list within a second (webview: `live_elsewhere_sync`; verified
    2026-09-16 — it is why a fork opened in Terminal shows up at once and a bare
    file never does). So: register the fork under this script's pid, hold for a
    few seconds, remove the entry. The transcript stays listed; the live marker goes.
    """
    reg = Path.home() / ".claude" / "sessions"
    if not reg.is_dir():
        return
    now = int(time.time() * 1000)
    entry = reg / f"{os.getpid()}.json"
    entry.write_text(json.dumps({
        "pid": os.getpid(), "sessionId": session_id, "cwd": str(root), "startedAt": now,
        "kind": "interactive", "entrypoint": "cli", "pidDomain": sys.platform,
        "name": title, "nameSource": "user", "status": "idle",
        "updatedAt": now, "statusUpdatedAt": now, "version": "fork_claude_session.py",
    }))
    try:
        time.sleep(hold_s)
    finally:
        entry.unlink(missing_ok=True)


def open_in_terminal(cwd: Path, argv: list, env: dict = None):
    """Run argv in a new Terminal.app window — a clean login shell, no CLAUDECODE=1 inherited.
    env (bin/account's start env, e.g. CLAUDE_CONFIG_DIR) goes in front of the command."""
    if sys.platform != "darwin":
        sys.exit("--terminal needs macOS (Terminal.app via osascript)")
    pre = "env " + "".join(f"{shlex.quote(f'{k}={v}')} " for k, v in env.items()) if env else ""
    script = f"cd {shlex.quote(str(cwd))} && exec {pre}{shlex.join(argv)}"   # what the shell runs
    literal = script.replace("\\", "\\\\").replace('"', '\\"')            # as an AppleScript string
    # A new window opens on the desktop in view, so the view moves first: activating Terminal
    # switches to the desktop its windows are on (Desktop 5, bin/tiling), and the delay lets the
    # switch finish — without it the window landed on the old desktop (probed 2026-10-05).
    osa = f'tell application "Terminal"\n  activate\n  delay 1\n  do script "{literal}"\nend tell'
    subprocess.run(["osascript", "-e", osa], check=True, capture_output=True)


def main(argv):
    root = repo_root()
    if "--list" in argv:
        for ts, f, prompt in candidates(root)[:10]:
            print(f"{ts}  {f.stem}  {prompt[:60]!r}")
        return
    session_id = argv[argv.index("--session") + 1] if "--session" in argv else None
    src, prompt = pick(root, session_id)
    new_id = str(uuid.uuid4())
    dest_dir = PROJECTS / slug(root)   # the workspace's own slug — where the VS Code picker looks
    if "--dry-run" in argv:
        print(f"session:   {src.stem}")
        print(f"you said:  {prompt[:80]!r}")
        print(f"fork:      {dest_dir / (new_id + '.jsonl')}")
        return
    dest, title, n = fork_transcript(src, dest_dir, new_id)
    label = title or f"{PREFIX}{src.stem[:8]}"
    print(f"forked {src.stem} → {new_id}  ({n} records)")
    print(f"title:  {label}")
    if "--terminal" in argv:
        claude = shutil.which("claude") or "claude"
        open_in_terminal(root, [claude, "-r", new_id, "--name", label])
        print("opened in a new Terminal window")
    else:
        announce(root, new_id, label)
        # The list sorts by file mtime, so sessions still writing sit above the fork —
        # search by title. Verified 2026-09-16 by running the extension's own lister
        # under Electron: the file is returned; only the sidebar's refresh was missing.
        print("it is in the Claude Code session list now — search for 'fork ·' if live sessions crowd it out")


if __name__ == "__main__":
    main(sys.argv[1:])
