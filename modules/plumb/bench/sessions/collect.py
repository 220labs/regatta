#!/usr/bin/env python3
"""Every interactive session of the last N days on this Mac, with its last reply and what code
alone can say about its status (orchestration-landscape D10, 2026-10-01).

    collect.py [--days 7] [--bench DIR]      writes DIR/sessions.jsonl, prints the counts

Source: the live session files under ~/.claude/projects/<cwd-slug>/<session>.jsonl (complete
for the week; the transcript archive is not). Skipped: files under /private/tmp (bench clones
and scratch runs), headless `claude -p` sessions (entrypoint `sdk-cli`), sessions with no
assistant text at all. Per session: the last assistant text, when, cwd → repo (a worktree
counts as its repo), branch, the last prompt, whether a tool call is still pending, and the
title Claude gave it.

Code rules, applied before any model: bin/session_status.py code_rule(), the same rules
`bin/pickup list` prints (closing line, pending tool call, api error, memo link, question).
    rule      done / waiting / blocked from those, none for everything else — the judgment set
              the bake-off is about; `status` keeps "done — read the note" apart (D6)
Data stays outside git (default bench/sessions in the core's log dir): the texts quote every
project. Python 3.9, stdlib.
"""
import argparse
import collections
import glob
import json
import os
import sys
import time

PROJECTS = os.path.expanduser("~/.claude/projects")
# the guard and the code rules live once, in bin/session_status.py, which `bin/pickup list` runs
# too — so the bench scores what the owner sees (docs/record/jev-sessions-bench-2026-10-02.md D2)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import _regatta  # noqa: E402  wharf's session_status.py through the core's tool() (G37)
DEFAULT_BENCH = _regatta.data("sessions")
sys.path.insert(0, os.path.dirname(_regatta.need("session_status.py")))
from session_status import WAITING, code_rule, is_guarded, slug_of  # noqa: E402,F401  (slug_of: test_collect.py)
# WAITING names the owner from the core's config: a literal "waiting on the owner" missed it (review)
RULE_OF = {"done": "done", "done — read the note": "done", WAITING: "waiting", "blocked": "blocked"}


def repo_of(cwd):
    if not cwd:
        return None
    p = cwd.split("/.claude/worktrees/")[0]
    return os.path.basename(p.rstrip("/"))


def read(path):
    """One pass over a session file. Returns the row or None."""
    last_asst = None
    pending = set()
    last_prompt = None
    prompt_at = ""  # the owner's latest prompt, any shape: read as pickup's scan() reads it
    title = custom = None
    n_asst = 0
    entry = None
    first_cwd = None
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            try:
                d = json.loads(line)
            except ValueError:
                continue
            t = d.get("type")
            if first_cwd is None and d.get("cwd"):
                first_cwd = d["cwd"]
            if t == "assistant" and not d.get("isSidechain"):
                entry = entry or d.get("entrypoint")
                c = d.get("message", {}).get("content")
                if not isinstance(c, list):
                    continue
                texts = [b.get("text", "") for b in c if b.get("type") == "text"]
                uses = [b.get("id") for b in c if b.get("type") == "tool_use"]
                for u in uses:
                    pending.add(u)
                if texts or uses:
                    n_asst += 1
                    last_asst = {"text": "\n".join(texts).strip(), "ts": d.get("timestamp"), "cwd": d.get("cwd"),
                                 "branch": d.get("gitBranch"), "entrypoint": d.get("entrypoint"),
                                 "model": d.get("message", {}).get("model"), "tool_uses": len(uses),
                                 "api_error": bool(d.get("isApiErrorMessage"))}
            elif t == "user":
                c = d.get("message", {}).get("content")
                if (d.get("origin") or {}).get("kind") == "human":
                    # any human prompt — a slash command, an IDE block, a list — as in bin/pickup
                    pending.clear()  # a call left open before the owner's next prompt is history, not a wait
                    prompt_at = max(prompt_at, d.get("timestamp") or "")
                if isinstance(c, list):
                    for b in c:
                        if b.get("type") == "tool_result":
                            pending.discard(b.get("tool_use_id"))
                elif isinstance(c, str) and not d.get("isMeta") and not c.startswith("<"):
                    last_prompt = (c.strip()[:200], d.get("timestamp"))
            elif t == "last-prompt":
                last_prompt = (str(d.get("lastPrompt", ""))[:200], last_prompt[1] if last_prompt else None)
            elif t == "ai-title":
                title = d.get("title") or d.get("aiTitle") or title
            elif t == "custom-title":  # /rename or checkpoint.py's A4 title, which the list shows over ai-title
                custom = d.get("customTitle") or custom
    if not last_asst or not last_asst["text"] and not pending:
        return None
    text = last_asst["text"]
    # a prompt after the last reply that never got one: no text rule reads it (pickup's reply_status)
    unanswered = bool(prompt_at) and prompt_at > (last_asst["ts"] or "")
    status, decided_by = code_rule("" if unanswered else text, 0 if unanswered else len(pending), last_asst["api_error"])
    project_dir = os.path.basename(os.path.dirname(path))
    return {
        "session": os.path.basename(path)[:-6], "project_dir": project_dir,
        "repo": repo_of(last_asst["cwd"]), "cwd": last_asst["cwd"], "first_cwd": first_cwd, "branch": last_asst["branch"],
        "entrypoint": entry or last_asst["entrypoint"], "model": last_asst["model"], "title": custom or title,
        "ts": last_asst["ts"], "n_assistant": n_asst, "pending_tool_calls": len(pending),
        "last_prompt": last_prompt[0] if last_prompt else None, "text": text[-3000:],
        # rule: done / waiting / blocked / none (none = the judgment set); status and decided_by
        # are what `bin/pickup list` prints — "done — read the note" kept apart from done (D6)
        "rule": RULE_OF.get(status, "none"), "status": status, "decided_by": decided_by,
        "guarded": is_guarded(project_dir, first_cwd, last_asst["cwd"]),
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--days", type=float, default=7)
    ap.add_argument("--until", default="2026-10-02T12:00:00Z",
                    help="freeze the set: sessions whose last reply is after this UTC instant are left out "
                         "(the live files keep changing while the bench runs; the first collection was 12:00Z)")
    ap.add_argument("--since", default="2026-09-25T00:00:00Z",
                    help="the window's start on the last reply's timestamp (default: the day the first "
                         "collection's 7-day file filter reached back to, so the set stays the same set)")
    ap.add_argument("--bench", default=os.environ.get("BENCH", DEFAULT_BENCH))
    a = ap.parse_args()
    # the window is [until − days, until] on the last reply's own timestamp, so the set is the
    # same whenever it is rebuilt; file mtimes only pre-filter (a file untouched for far longer
    # than the window cannot hold a reply inside it)
    until_ts = time.mktime(time.strptime(a.until, "%Y-%m-%dT%H:%M:%SZ")) - time.timezone if a.until else time.time()
    since = a.since or time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(until_ts - a.days * 86400))
    rows, skipped = [], collections.Counter()
    for path in glob.glob(os.path.join(PROJECTS, "*", "*.jsonl")):
        if "private-tmp" in path or os.path.getmtime(path) < until_ts - (a.days + 3) * 86400:
            continue
        r = read(path)
        if r is None:
            skipped["no assistant text"] += 1
            continue
        if r["entrypoint"] and r["entrypoint"].startswith("sdk"):
            skipped["headless " + r["entrypoint"]] += 1
            continue
        if not r["ts"] or r["ts"] < since:
            skipped["before the window"] += 1
            continue
        if a.until and r["ts"] > a.until:
            skipped["after --until"] += 1
            continue
        rows.append(r)
    rows.sort(key=lambda r: r["ts"] or "")
    os.makedirs(a.bench, exist_ok=True)
    out = os.path.join(a.bench, "sessions.jsonl")
    # a labelled week is frozen: its transcripts age out after 30 days and the rules have moved on
    # since, so it could never be rebuilt — a new week takes its own --bench DIR
    if os.path.exists(os.path.join(a.bench, "labels.json")):
        sys.exit(f"collect.py: {a.bench} holds labels.json, a labelled week — give week two its own --bench DIR")
    with open(out, "w") as fh:
        for r in rows:
            fh.write(json.dumps(r, ensure_ascii=False) + "\n")
    print("interactive sessions, %s to %s: %d (skipped %s)" % (since, a.until or "now", len(rows), dict(skipped)))
    print("by rule:", dict(collections.Counter(r["rule"] for r in rows)))
    print("by entrypoint:", dict(collections.Counter(r["entrypoint"] for r in rows)))
    print("by repo:", dict(collections.Counter(r["repo"] for r in rows).most_common()))
    left = [r for r in rows if r["rule"] == "none"]
    print("judgment set: %d, of which guarded (a guarded repo, or the projects root, by slug or either cwd): %d" % (
        len(left), sum(1 for r in left if r["guarded"])))
    for r in left:
        if r["guarded"]:
            print("  guarded: %s slug=%s first_cwd=%s last_cwd=%s" % (r["session"][:8], r["project_dir"], r["first_cwd"], r["cwd"]))
    print("wrote", out)


if __name__ == "__main__":
    main()
