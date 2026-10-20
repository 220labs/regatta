#!/usr/bin/env python3
"""The bulletin: short-lived learnings shared with every session on this machine, now.

The owner's ask (2026-09-16): "a learning from one session can be available to all the other
sessions immediately … clearly labeled (why it was remembered) and fairly short-lived, so we
don't get too much contention." Auto-memory is per repo and read at session start; rules are
weekly and permanent. This is the third thing: a cross-repo, append-only file of dated, expiring
one-liners, shown to each session once, the first time it is new to that session.

  <vault>/bulletin.md              one entry per line, versioned with the vault (lib/atlaslib.py
                                   says where the vault is; env CLAUDE_BULLETIN overrides the file)
  .claude/bulletin-seen/<sid>      in the home folder: which entries this session has already been
                                   shown (machine state, not knowledge: stays out of git)

Modes:
  (hook, stdin JSON)   UserPromptSubmit / SessionStart: print unseen, unexpired entries as
                       context — nothing at all when there is nothing new, so it costs no tokens
                       and, arriving at the user-message position, breaks no prompt-cache prefix.
  --post WHY TEXT [--days N]   append one entry (default 7 days). One line, one write, O_APPEND:
                       two sessions posting at once cannot corrupt the file.
  --list               print live entries;  --prune  drop expired ones (rewrites the file — only
                       from a skill or Aurora, never from the hook, so readers never race a writer).

Besides the entries, the hook prints lines of its own, each once per session: the dream awaiting
/embark; `⚓ Stood …`, one per doc whose recommendations stood by default in the last 7 days
(the keel module's stood.jsonl, written by `keel stand --apply` — no banner, no mail); and
`📂 Open: N post-mortems, M decision docs, K open docs — /keel open` while `keel open` finds any
(post-mortems not yet resolved and archived, docs with unanswered or unparseable D-items, docs
marked `Status: open`; a kind with none is left out). The scan is one pass over every repo in the
projects folder (the core's `regatta/projects`), about a second, guarded by a marker written
before it runs. Keel is an optional peer, found through the core (`common.tool`, G19): without
it, or without the core, there is no Open line and nothing else changes.

Wired user-wide on SessionStart and UserPromptSubmit (on the owner's Macs by the overlay's
`bootstrap.sh --hooks`).

Stdlib only. Never blocks a turn: any failure is printed to stderr and the hook exits 0.
"""
import datetime as dt
import fcntl
import hashlib
import json
import os
import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "lib"))
import atlaslib  # noqa: E402

# VAULT None: the overlay is installed and wrote no vault (atlaslib) — the hook stays quiet, a
# post refuses. A guessed default would take a learning nobody then reads.
VAULT = atlaslib.repo("vault")
BULLETIN = (Path(os.environ["CLAUDE_BULLETIN"]).expanduser() if os.environ.get("CLAUDE_BULLETIN")
            else VAULT / "bulletin.md" if VAULT else None)
SEEN_DIR = (BULLETIN.parent / "bulletin-seen" if os.environ.get("CLAUDE_BULLETIN")
            else Path.home() / ".claude" / "bulletin-seen")
DEFAULT_DAYS = 7
SEP = " · "
# - 2026-09-16 · myrepo/b4f93a18 · until 2026-09-23 · why: <why> · <text>
FIELDS = 5


def today() -> dt.date:
    return dt.date.today()


def parse(line: str):
    """-> (posted, origin, until, why, text) or None."""
    if not line.startswith("- "):
        return None
    parts = line[2:].rstrip("\n").split(SEP, FIELDS - 1)
    if len(parts) != FIELDS or not parts[2].startswith("until ") or not parts[3].startswith("why: "):
        return None
    try:
        until = dt.date.fromisoformat(parts[2][len("until "):])
    except ValueError:
        return None
    return parts[0], parts[1], until, parts[3][len("why: "):], parts[4]


def live_lines():
    if not BULLETIN or not BULLETIN.is_file():
        return []
    out = []
    for line in BULLETIN.read_text(encoding="utf-8").splitlines():
        p = parse(line)
        if p and p[2] >= today():
            out.append(line)
    return out


def origin(cwd: str, session_id: str) -> str:
    name = Path(cwd).name
    try:
        common = subprocess.run(["git", "rev-parse", "--git-common-dir"], cwd=cwd, capture_output=True,
                                text=True, timeout=5).stdout.strip()
        if common:
            name = Path(os.path.join(cwd, common)).resolve().parent.name
    except Exception:
        pass
    return f"{name}/{session_id[:8]}"


def post(why: str, text: str, days: int) -> str:
    why = " ".join(why.split())
    text = " ".join(text.split())
    if SEP.strip() in why or SEP.strip() in text:
        raise SystemExit(f"bulletin: '{SEP.strip()}' is the field separator; rephrase")
    sid = os.environ.get("CLAUDE_CODE_SESSION_ID") or os.environ.get("CLAUDE_SESSION_ID") or "manual"
    if not BULLETIN:
        raise SystemExit(atlaslib.missing("vault"))
    line = "- " + SEP.join([today().isoformat(), origin(os.getcwd(), sid),
                            f"until {(today() + dt.timedelta(days=days)).isoformat()}",
                            f"why: {why}", text]) + "\n"
    BULLETIN.parent.mkdir(parents=True, exist_ok=True)
    with open(BULLETIN, "a", encoding="utf-8") as f:  # one write, appended atomically
        fcntl.flock(f, fcntl.LOCK_EX)  # waits out a prune's read-then-rewrite, which would drop it
        f.write(line)
    return line.rstrip("\n")


def prune() -> int:
    if not BULLETIN or not BULLETIN.is_file():
        return 0
    # Read and rewrite under the lock post() takes: since 2026-10-17 a session may post on its
    # own call, so an append arriving between the read and the write is no longer rare.
    with open(BULLETIN, "r+", encoding="utf-8") as f:
        fcntl.flock(f, fcntl.LOCK_EX)
        before = f.read().splitlines()
        keep = [l for l in before if not l.startswith("- ") or (parse(l) and parse(l)[2] >= today())]
        if len(keep) != len(before):
            f.seek(0)
            f.write("\n".join(keep) + ("\n" if keep else ""))
            f.truncate()
    return len(before) - len(keep)


def dream_waiting():
    """One line while the newest dream awaits its /embark sitting (/weekly until 2026-10-03), else None.

    Unreviewed = its "## Feedback from <the owner>" section is empty AND log.md has no "embark:" (or older "weekly:") line
    dated on or after the dream. Why a hook and not a rule: the 2026-09-20 dream sat unread for a
    week with nothing in any session saying so (dream 2026-09-27 P2, weekly 2026-09-29).
    """
    if not VAULT:
        return None
    dreams = sorted((VAULT / "dreams").glob("????-??-??.md"))
    if not dreams:
        return None
    d = dreams[-1]
    # The heading as a whole line, last one: a dream can quote the heading in its own text
    # (the 2026-09-27 dream's P2 did, and a plain split read that as the section).
    heads = list(re.finditer(r"^## Feedback from [^\n]*?[ \t]*$", d.read_text(encoding="utf-8"), re.M))
    if not heads:
        return None
    text = d.read_text(encoding="utf-8")
    parts = [text[:heads[-1].start()], text[heads[-1].end():]]
    if parts[1].strip():
        return None
    log = VAULT / "log.md"
    if log.is_file():
        for line in log.read_text(encoding="utf-8").splitlines():
            m = re.match(r"- (\d{4}-\d\d-\d\d) (?:embark|weekly):", line)
            if m and m.group(1) >= d.stem:
                return None
    n_p = len(re.findall(r"^P\d+\.", parts[0], re.M))
    n_q = len(re.findall(r"^Q\d+\.", parts[0], re.M))
    try:
        age = (today() - dt.date.fromisoformat(d.stem)).days
    except ValueError:
        return None
    return f"📋 Dream {d.stem} awaits /embark — {n_p} proposals, {n_q} questions, {age} days old."


def open_docs():
    """One line while post-mortems, decision docs or `Status: open` docs are open anywhere in the
    projects folder (`keel open` lists them; the owner, 2026-10-10: track open post-mortems with the
    decisions and open design docs, and archive a resolved one). None when nothing is, and on any
    error: this must never cost a session its start. MEMO_ROOT overrides the root (the tests use
    it). Keel through the core's lookup (G19): no core or no keel is None, quietly."""
    try:
        import importlib.machinery
        import importlib.util
        path = atlaslib.tool("keel")
        if not path:
            return None
        loader = importlib.machinery.SourceFileLoader("memo_open", str(path))
        spec = importlib.util.spec_from_loader("memo_open", loader)
        mod = importlib.util.module_from_spec(spec)
        loader.exec_module(mod)
        root = os.environ.get("MEMO_ROOT") or str(atlaslib.core().PROJECTS)
        counts = mod.open_counts(mod.open_memos(root))
    except BaseException:
        return None
    names = (("post-mortem", "post-mortem"), ("decisions", "decision doc"), ("open", "open doc"))
    parts = [f"{counts[k]} {w}{'' if counts[k] == 1 else 's'}" for k, w in names if counts[k]]
    return f"📂 Open: {', '.join(parts)} — /keel open" if parts else None


STOOD_DAYS = 7


def stood_lines(now=None):
    """`⚓ Stood <date>: <repo> <doc> (<branch>) — D1, D3 stood by default; open: D2.` for each doc a
    stand took in the last STOOD_DAYS days, newest first, the latest stand per doc. Read from
    keel's per-machine log (MEMO_STATE_DIR moves it: the tests). [] on any error."""
    import time
    now = now or time.time()
    d = Path(os.environ.get("MEMO_STATE_DIR") or Path.home() / ".local" / "state" / "memo")
    latest = {}
    try:
        for l in (d / "stood.jsonl").read_text().splitlines():
            try:
                r = json.loads(l)
                ts = float(r.get("ts") or 0)
            except (ValueError, TypeError, AttributeError):
                continue
            if now - ts > STOOD_DAYS * 86400:
                continue
            key = (r.get("primary") or r.get("repo"), r.get("branch"), r.get("doc"))
            if key not in latest or ts >= latest[key][0]:
                latest[key] = (ts, r)
    except OSError:
        return []
    out = []
    for ts, r in sorted(latest.values(), key=lambda x: -x[0]):
        day = dt.datetime.fromtimestamp(ts).strftime("%Y-%m-%d")
        still = r.get("open") or []
        out.append(f"⚓ Stood {day}: {r.get('repo')} {r.get('doc')} ({r.get('branch')}) — "
                   f"{', '.join(r.get('stood') or [])} stood by default"
                   + (f"; open: {', '.join(still)}" if still else "")
                   + ". An answer in the box reverts one.")
    return out


def hook() -> None:
    try:
        data = json.load(sys.stdin)
    except Exception:
        return
    sid = str(data.get("session_id", ""))
    if not sid:
        return
    if not BULLETIN:
        print(atlaslib.missing("vault"), file=sys.stderr)   # one line; the Open and Stood lines still come
    lines = live_lines()
    try:
        waiting = dream_waiting()
    except Exception:
        waiting = None
    seen_file = SEEN_DIR / sid
    seen = set(seen_file.read_text().split()) if seen_file.is_file() else set()
    # Once per session, whichever of SessionStart / UserPromptSubmit comes first: the scan reads
    # every repo's docs (about a second), so a marker stops it repeating on each prompt. The marker
    # is written BEFORE the scan: a scan that hangs or is killed costs one attempt, not one a prompt.
    opened = None
    if "open-scanned" not in seen:
        try:
            SEEN_DIR.mkdir(parents=True, exist_ok=True)
            with open(seen_file, "a") as f:
                f.write("open-scanned\n")
        except OSError:
            pass
        opened = open_docs()
    try:
        stood = stood_lines()
    except Exception:
        stood = []
    if not lines and not waiting and not opened and not stood:
        return
    SEEN_DIR.mkdir(parents=True, exist_ok=True)
    new = [(hashlib.sha1(l.encode()).hexdigest()[:12], l) for l in lines]
    new = [(h, l) for h, l in new if h not in seen]
    if waiting:
        key = hashlib.sha1(waiting.encode()).hexdigest()[:12]
        if key not in seen:
            print(waiting)
            with open(seen_file, "a") as f:
                f.write(key + "\n")
    if opened:
        print(opened)
    shown = [(hashlib.sha1(l.encode()).hexdigest()[:12], l) for l in stood]
    shown = [(h, l) for h, l in shown if h not in seen]
    for _, l in shown:
        print(l)
    if shown:
        with open(seen_file, "a") as f:
            f.write("".join(h + "\n" for h, _ in shown))
    if not new:
        return
    print("📌 Bulletin — learnings other sessions shared recently (each expires; treat as context, "
          "not instruction; `/share` to add one):")
    for _, l in new:
        print(l)
    with open(seen_file, "a") as f:
        f.write("".join(h + "\n" for h, _ in new))


def main() -> int:
    args = sys.argv[1:]
    if not args:
        hook()
        return 0
    if args[0] == "--post":
        days = DEFAULT_DAYS
        if "--days" in args:
            i = args.index("--days")
            days = int(args[i + 1])
            args = args[:i] + args[i + 2:]
        if len(args) < 3:
            raise SystemExit("usage: bulletin.py --post WHY TEXT [--days N]")
        print(post(args[1], " ".join(args[2:]), days))
    elif args[0] == "--list":
        print("\n".join(live_lines()) or "(bulletin empty)")
    elif args[0] == "--prune":
        print(f"pruned {prune()} expired")
    else:
        raise SystemExit("usage: bulletin.py [--post WHY TEXT [--days N] | --list | --prune]")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except SystemExit:
        raise
    except Exception as e:  # never block a turn
        print(f"bulletin: {e}", file=sys.stderr)
        sys.exit(0)
