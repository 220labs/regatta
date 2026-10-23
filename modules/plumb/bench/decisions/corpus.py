#!/usr/bin/env python3
"""The decision corpus: every D-item the owner was asked, with the recommendation and his answer.

Every memo, design doc and digest in the repos ends its D-items in an `➤ Answer:` line
pre-filled with the agent's recommendation (the owner's rules, How to talk). The owner
answers by editing that line or writing under it. So, walking a file's commits forward, the
first committed answer of a D-item is the model's recommendation and the HEAD answer is the owner's
decision; the commit that first changed it dates the answer. This script reads exactly what
`bin/memo` reads (it imports the parser), so a decision here is a decision there.

    corpus.py [--bench DIR]      writes DIR/corpus.jsonl and prints the breakdown

Labels per item (`kind`):
    accepted-done       answer unchanged and a `> **Done.**`-style reply follows: acted on as recommended
    accepted-silent     answer unchanged, no reply: pending, or accepted without a word (unknown)
    accepted+note       the owner kept the recommendation and added words ("Approved", a remark)
    accepted+question   the owner kept it and asked something
    overruled           the owner's answer differs in substance (another option, a no, a narrower scope)
`y_override` = overruled; `y_touched` = any of the three edited kinds; `known` = done or touched
(the item demonstrably reached the owner). Scoring uses `known` items only.

D10's shape (bin/memo's docstring; docs/record/jev-pipeline-2026-10-02.md) keeps the two apart: the
`➤ Recommended:` line is the agent's pick and the `➤ Answer:` block under it starts empty, so
whatever is in it is the owner's, even when it arrived in the doc's own commit (F12, the case the old
diff misread as the recommendation). A new-shape item is labelled on "the block is non-empty":
    empty               accepted-done / accepted-silent, as above
    accepted-answered   the owner answered and agreed: the recommended option's letter alone, the
                        recommendation's words, "= recommended" (the form's button), its bulk
                        form "= recommended (accept all)" (`bulk` = 1, docs/subagent-cache-2026-10-04.md
                        D5) or a bare
                        yes/ok/agree… (a yes to a negative pick reads as a no to it: overruled)
    accepted+note/+question, overruled   as above; with options, the letter decides (after
                        any "yes,"), and free text with no letter overrules
Any answer is `y_touched` here — the bench's `touched` asks whether the owner writes anything, and in
this shape answering is writing. The recommendation is the first committed non-empty Recommended
line; the wait runs from the item's first commit to the first commit with a non-empty block. An
answer block that runs into prose below the list (no heading or `---` after it) is skipped,
counted as `answer-runs-on`.

Data stays outside git (--bench, default bench/decisions in the core's log dir): the corpus
quotes every repo's docs, guarded ones included. Python 3.9, stdlib only.
"""
import argparse
import collections
import datetime as dt
import importlib.machinery
import importlib.util
import json
import os
import re
import statistics
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import _regatta  # noqa: E402  keel through the core's tool() (G37); `memo` is the overlay's old name for it.
ROOT = os.environ.get("CORPUS_ROOT") or _regatta.projects()  # the env: test_corpus.sh's fixture repo
DEFAULT_BENCH = _regatta.data("decisions")
MEMO = _regatta.find("keel") or _regatta.find("memo")  # None: load_memo raises, and bin/interruptions,
# which imports this file, counts the other channels
# the repos read: every folder under ROOT (bin/interruptions sets its own); CORPUS_DIRS names them for a test
DIRS = tuple(os.environ["CORPUS_DIRS"].split(",")) if os.environ.get("CORPUS_DIRS") else tuple(sorted(
    d for d in (os.listdir(ROOT) if os.path.isdir(ROOT) else []) if not d.startswith(".") and os.path.isdir(os.path.join(ROOT, d))))
# folders whose `➤ Answer` lines describe the format rather than ask anything
EXCLUDE = ("/.claude/worktrees/", "/skills/", "/templates/", "/bin/", "/agents/", "/rules/",
           "/lessons/", "/hooks/", "/bench/", "-corpus-review-")  # the review sheet is about decisions, not one
TEMPLATE_RE = re.compile(r"\{\{|<the recommendation>|^\s*$|pre-filled with|line pre-filled")
OPTIONS_RE = re.compile(r"\((?:a|b|c|i|ii)\)|(?:^|\s)\(?[ABC]\)|\boption\b|\beither\b", re.I)
# a picked option in a D10 answer: `B`, `b`, `**B**`, `B — because…`, `B?`, `B (and…)`, or `B` with
# a note on the next line; a letter that starts a word ("A lot cheaper") is not a pick
LETTER_RE = re.compile(r"^\s*\**([A-Za-z])\**(?=\n|\s*(?:$|[—–\-:.,;?!(]))")
# the form's "take the recommendation" button writes exactly this (bin/memo); it agrees whatever the
# pick. "Accept all recommendations" writes it with "(accept all)", so a bulk click reads apart (`bulk`)
TAKE_RE = re.compile(r"^\s*=\s*recommended(?:\s*\(accept all\))?\s*$", re.I)
BULK_RE = re.compile(r"^\s*=\s*recommended\s*\(accept all\)\s*$", re.I)
AGREE_RE = re.compile(r"^\s*(?:yes|yeah|yep|yup|ok|okay|agree|agreed|approved|sure|fine|lgtm|sounds good|all good)\b"
                      r"[\s.!—–\-:,]*", re.I)
# a bare yes to a negative pick ("no, skip it") reads as a no to the pick; ok, agreed and the rest still agree
YES_RE = re.compile(r"^\s*(?:yes|yeah|yep|yup)\b", re.I)
NEGATIVE_RE = re.compile(r"^\s*(?:no|not|don't|do not|never|skip)\b", re.I)
DONE_RE = re.compile(r"^\s*>\s*\*\*(Done|Built|Designed|Applied|Fixed|Landed|Launched|Not built|Deferred|Shipped|Weekly)", re.I)


def load_memo():
    if not MEMO:
        raise FileNotFoundError("memo (keel) not installed")
    loader = importlib.machinery.SourceFileLoader("memo", MEMO)
    spec = importlib.util.spec_from_loader("memo", loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


def sh(*args, cwd=None):
    return subprocess.run(args, capture_output=True, text=True, cwd=cwd).stdout


def norm(s):
    if s is None:
        return None
    return re.sub(r"\s+", " ", s).strip().rstrip(".").lower()


def kind_of(changed, done, rec, final):
    if not changed:
        return "accepted-done" if done else "accepted-silent"
    r, f = norm(rec), norm(final)
    if f.startswith(r):
        tail = f[len(r):].strip(" —-:,")
        return "accepted+question" if "?" in tail else "accepted+note"
    return "overruled"


def note_or_question(tail):
    return "accepted+question" if "?" in tail else "accepted+note"


def kind_new(done, rec, final, options):
    """A D10 item's label: the Answer block is the owner's alone, so empty = not answered."""
    if not final.strip():
        return "accepted-done" if done else "accepted-silent"
    f = final.strip()
    if TAKE_RE.match(f):
        return "accepted-answered"
    agree = AGREE_RE.match(f)
    pick = LETTER_RE.match(rec) if options else None
    if pick:
        # "B", "Yes, B", "ok — A": the letter decides, after any word of agreement
        body = f[agree.end():] if agree else f
        mf = LETTER_RE.match(body)
        if mf:
            if mf.group(1).upper() != pick.group(1).upper():
                return "overruled"
            tail = body[mf.end():].strip(" —–-:.,;\n")
            return note_or_question(tail) if tail else "accepted-answered"
    if norm(f) == norm(rec):
        return "accepted-answered"
    if agree and not (NEGATIVE_RE.match(rec) and YES_RE.match(f)):
        tail = f[agree.end():].strip()
        return note_or_question(tail) if tail else "accepted-answered"
    if not pick:
        r, nf = norm(rec), norm(f)
        if re.match(re.escape(r) + r"(?=$|[\s—–\-:.,;!?(])", nf):
            return note_or_question(nf[len(r):].strip(" —–-:,"))
    # free text on a choice with no letter in it, or words that are not the recommendation's
    return "overruled"


def row(it, repo, path, m, rec, final, kind, known, touched, wait, has_options):
    """One corpus row; a D10 row also carries `shape: new` (questions.py words its state by it)."""
    rec_date = dt.datetime.utcfromtimestamp(rec[1]).strftime("%Y-%m-%d")
    out = {
        "key": "%s:%s:%s" % (os.path.basename(repo), os.path.basename(path), it["id"]),
        "repo": os.path.basename(repo), "file": os.path.relpath(path, ROOT),
        "doc_date": m.group(1) if m else rec_date, "id": it["id"], "title": it["title"],
        "body": it["body"], "recommendation": rec[0], "final": final, "rec_date": rec_date,
        "kind": kind, "y_override": int(kind == "overruled"), "y_touched": int(touched),
        "known": int(known), "bulk": int(bool(BULK_RE.match(final or ""))),
        "wait_hours": round((wait[0] - rec[1]) / 3600, 1) if wait else None,
        "answered_ts": wait[0] if wait else None,  # bin/interruptions windows D-items on it
        "has_options": has_options,
        "state_chars": len((it["title"] or "") + (it["body"] or "") + rec[0]),
    }
    if it.get("shape") == "new":
        out["shape"] = "new"
    return out


def build(memo):
    files = []
    for d in DIRS:
        out = sh("grep", "-rl", "➤ Answer", "--include=*.md", os.path.join(ROOT, d))
        files += [f for f in out.split("\n") if f]
    files = sorted(set(f for f in files if not any(x in f for x in EXCLUDE)))
    items, skipped = [], collections.Counter()
    for path in files:
        repo = sh("git", "rev-parse", "--show-toplevel", cwd=os.path.dirname(path)).strip()
        if not repo:
            skipped["no-repo"] += 1
            continue
        # both sides resolved: git names the toplevel by its real path, grep by the one it was given
        rel = os.path.relpath(os.path.realpath(path), os.path.realpath(repo))
        log = sh("git", "-C", repo, "log", "--follow", "--format=%H %ct %an", "--reverse", "--", rel)
        commits = [l.split(" ", 2) for l in log.split("\n") if l.strip()]
        if not commits:
            skipped["uncommitted"] += 1
            continue
        first, changed_at = {}, {}
        new_first, answered_at = {}, {}  # D10's shape: first Recommended line, first non-empty block
        for sha, ts, author in commits:
            blob = sh("git", "-C", repo, "show", "%s:%s" % (sha, rel))
            if not blob:
                continue
            try:
                _, its, _ = memo.parse(blob)
            except Exception:
                continue
            for it in its:
                if it.get("shape") == "new":
                    if it["recommended"]:  # a pick filled in later counts from that commit
                        new_first.setdefault(it["id"], (it["recommended"], int(ts), sha))
                    if (it["answer"] or "").strip() and it["id"] not in answered_at:
                        answered_at[it["id"]] = (int(ts), sha, author)
                    continue
                a = it["answer"]
                if a is None:
                    continue
                if it["id"] not in first:
                    first[it["id"]] = (a, int(ts), sha)
                elif it["id"] not in changed_at and norm(a) != norm(first[it["id"]][0]):
                    changed_at[it["id"]] = (int(ts), sha, author)
        try:
            lines, its, _ = memo.parse(open(path, encoding="utf-8", errors="replace").read())
        except Exception:
            skipped["parse-error-head"] += 1
            continue
        m = re.search(r"(\d{4}-\d{2}-\d{2})", os.path.basename(path))
        for k, it in enumerate(its):
            if it.get("shape") == "new":
                r = new_item(memo, it, k, its, lines, new_first, answered_at, path, repo, m, skipped)
                if r:
                    items.append(r)
                continue
            rec = first.get(it["id"], (None, None, None))
            final = it["answer"]
            if final is None or rec[0] is None:
                continue
            if TEMPLATE_RE.search(rec[0]) or TEMPLATE_RE.search(final):
                continue
            nxt = its[k + 1]["start"] if k + 1 < len(its) else len(lines)
            tail = lines[(it["answer_end"] or it["end"]):nxt]
            done = any(DONE_RE.match(l) for l in tail)
            changed = norm(rec[0]) != norm(final)
            kind = kind_of(changed, done, rec[0], final)
            items.append(row(it, repo, path, m, rec, final, kind, done or changed,
                             kind in ("overruled", "accepted+note", "accepted+question"),
                             changed_at.get(it["id"]), bool(OPTIONS_RE.search(it["body"] or ""))))
    return items, skipped


def new_item(memo, it, k, its, lines, new_first, answered_at, path, repo, m, skipped):
    """One D10-shape item as a corpus row, or None: uncommitted, describing the format, or an answer
    block that runs into prose below the D-list (memo's own guard; the agent's text there would
    read as the owner overruling). `touched` is the bench's question as written — the owner wrote anything —
    which in this shape is any answer at all; `known` the same, or a reply that acted on it."""
    rec = new_first.get(it["id"])
    if not rec:
        return None
    if TEMPLATE_RE.search(rec[0]):
        return None
    if it["answer_line"] is not None:
        prefix = lines[it["answer_line"]].split(memo.ANSWER, 1)[0]
        try:
            memo.guard_block(it, lines, re.match(r"\s*", prefix).group(0))
        except memo.Stop:
            skipped["answer-runs-on"] += 1
            return None
    final = it["answer"] or ""
    answered = bool(final.strip())
    nxt = its[k + 1]["start"] if k + 1 < len(its) else len(lines)
    done = any(DONE_RE.match(l) for l in lines[(it["answer_end"] or it["end"]):nxt])
    kind = kind_new(done, rec[0], final, it.get("options"))
    return row(it, repo, path, m, rec, final, kind, done or answered, answered,
               answered_at.get(it["id"]) if answered else None,
               bool(it.get("options")) or bool(OPTIONS_RE.search(it["body"] or "")))


def apply_chat(items, evidence, confirmed):
    """Answers the owner gave in chat, read from the transcripts (chat_evidence.py) and confirmed by
    him on the review sheet, become labels: an item he accepted in chat is known and untouched
    (he did not write on the doc, which is what `touched` measures), one he overruled in chat
    is known, touched and overruled. Items the chat never mentioned stay unknown unless the
    doc as a whole was approved."""
    ok = None if confirmed == "all" else set(x.strip() for x in confirmed.split(","))
    n = 0
    for it in items:
        if it["kind"] != "accepted-silent":
            continue
        ev = evidence.get(it["file"]) or {}
        r = ev.get("reading")
        base = os.path.basename(it["file"])
        if not r or (ok is not None and base not in ok):
            continue
        st = (r.get("items") or {}).get(it["id"], {}).get("status", "not_mentioned")
        if st == "not_mentioned" and (r.get("doc_level") or {}).get("status") == "approved":
            st = "accepted"
        if st == "accepted":
            it.update(kind="accepted-chat", known=1, y_touched=0, y_override=0)
        elif st == "overruled":
            it.update(kind="overruled-chat", known=1, y_touched=1, y_override=1)
        elif st == "question":
            it.update(kind="question-chat", known=1, y_touched=1, y_override=0)
        else:
            continue
        n += 1
    print("chat readings applied to %d items" % n)


def apply_review(items, review):
    """The owner's own answers to the review sheet (docs/jev-corpus-review-<date>.md), typed into
    JSON by the session that reads them. `applied` = he said go in some form: known, untouched;
    an item he names as overruled or questioned: known, touched (and overruled)."""
    n = 0
    for it in items:
        if it["kind"] != "accepted-silent":
            continue
        r = review.get(os.path.basename(it["file"]))
        if not r:
            continue
        st = (r.get("items") or {}).get(it["id"]) or r.get("default", "unknown")
        if st in ("applied", "accepted"):
            it.update(kind="accepted-review", known=1, y_touched=0, y_override=0)
        elif st == "overruled":
            it.update(kind="overruled-review", known=1, y_touched=1, y_override=1)
        elif st == "question":
            it.update(kind="question-review", known=1, y_touched=1, y_override=0)
        elif st == "mine":
            # The owner's words were in the first commit (edit and doc committed together), so the
            # diff read them as the recommendation: touched, not overruled
            it.update(kind="touched-review", known=1, y_touched=1, y_override=0)
        else:
            continue
        n += 1
    print("review answers applied to %d items" % n)


def summary(items, skipped):
    kinds = collections.Counter(i["kind"] for i in items)
    known = [i for i in items if i["known"]]
    print("items: %d in %d docs (skipped %s)" % (len(items), len(set(i["file"] for i in items)), dict(skipped) or "none"))
    print("kinds:", dict(kinds.most_common()))
    print("known (reached the owner): %d; overruled among known: %d (%.0f%%); touched among known: %d (%.0f%%)" % (
        len(known), sum(i["y_override"] for i in known), 100.0 * sum(i["y_override"] for i in known) / max(1, len(known)),
        sum(i["y_touched"] for i in known), 100.0 * sum(i["y_touched"] for i in known) / max(1, len(known))))
    print("per repo (all / known / overruled):")
    for repo in sorted(set(i["repo"] for i in items)):
        s = [i for i in items if i["repo"] == repo]
        print("  %-10s %3d / %3d / %2d" % (repo, len(s), sum(i["known"] for i in s), sum(i["y_override"] for i in s)))
    waits = [i["wait_hours"] for i in items if i["wait_hours"] is not None]
    if waits:
        print("hours from recommendation to the owner's edit: median %.1f, p75 %.1f, max %.1f (n=%d)" % (
            statistics.median(waits), sorted(waits)[int(0.75 * len(waits))], max(waits), len(waits)))
    chars = [i["state_chars"] for i in items]
    print("state chars: median %d, p90 %d, max %d; total %d (about %d tokens)" % (
        statistics.median(chars), sorted(chars)[int(0.9 * len(chars))], max(chars), sum(chars), sum(chars) // 4))
    print("items with enumerated options: %d" % sum(1 for i in items if i["has_options"]))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bench", default=os.environ.get("BENCH", DEFAULT_BENCH))
    ap.add_argument("--examples", type=int, default=0, help="print N overruled examples")
    ap.add_argument("--chat", help="chat-evidence.json from chat_evidence.py: apply its readings")
    ap.add_argument("--confirmed", default="all",
                    help="with --chat: comma-separated doc basenames whose reading the owner confirmed, or 'all'")
    ap.add_argument("--review", help="the owner's answers to the review sheet (review_sheet.py), as JSON: "
                    '{"<doc basename>": {"default": "applied|unknown", "items": {"D3": "overruled|question"}}}')
    a = ap.parse_args()
    memo = load_memo()
    items, skipped = build(memo)
    if a.chat:
        apply_chat(items, json.load(open(a.chat)), a.confirmed)
    if a.review:
        apply_review(items, json.load(open(a.review)))
    os.makedirs(a.bench, exist_ok=True)
    out = os.path.join(a.bench, "corpus.jsonl")
    with open(out, "w") as f:
        for i in items:
            f.write(json.dumps(i, ensure_ascii=False) + "\n")
    summary(items, skipped)
    print("wrote", out)
    for i in [i for i in items if i["kind"] == "overruled"][:a.examples]:
        print("- [%s] %s\n    rec:   %s\n    final: %s" % (i["key"], i["title"][:90], i["recommendation"][:110], i["final"][:160]))


if __name__ == "__main__":
    main()
