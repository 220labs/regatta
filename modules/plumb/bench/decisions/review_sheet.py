#!/usr/bin/env python3
"""The review sheet for the unknown decisions: one D-item per doc, for the owner's memory.

    review_sheet.py [--bench DIR] [--out docs/jev-corpus-review-<date>.md]

The transcripts could not recover chat answers (chat_evidence.py: the archive lacks the
sessions that wrote several docs, and a "go" typed in a fresh session names no doc), so the
remaining source is the owner. Per doc: the items with no edit and no reply, title and pre-filled
answer only (no bodies — the sheet lives in a repo that may be published), and one
`➤ Answer:` pre-filled from what the corpus already shows: the --apply repos' docs were applied
as recommended, everything else is unknown. Where chat_evidence.py found a doc-level approval
it is quoted. The guarded repos stay off the sheet. The owner's answers come back through
`corpus.py --review <json>` once typed into that shape by the session that reads them.
"""
import sys
import argparse
import collections
import datetime as dt
import json
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import _regatta  # noqa: E402  the core: the data folder, the guarded repos
DEFAULT_BENCH = _regatta.data("decisions")
HERE = os.path.dirname(os.path.abspath(__file__))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bench", default=os.environ.get("BENCH", DEFAULT_BENCH))
    # outside git by default: titles and recommendations carry household and network detail
    # (reviewer, 2026-10-02) and AGENTS.md keeps this repo free of anything personal
    ap.add_argument("--out", default=os.path.join(
        os.environ.get("BENCH", DEFAULT_BENCH), "review-sheet-%s.md" % dt.date.today().isoformat()))
    # the repos whose docs the corpus showed applied with a go in chat (2026-10-02: two of them)
    ap.add_argument("--apply", type=lambda v: tuple(x for x in v.split(",") if x), default=(),
                    help="repos, comma-separated, whose silent items are pre-filled as applied")
    a = ap.parse_args()
    items = [json.loads(l) for l in open(os.path.join(a.bench, "corpus.jsonl"))]
    ev_path = os.path.join(a.bench, "chat-evidence.json")
    evidence = json.load(open(ev_path)) if os.path.exists(ev_path) else {}
    docs = collections.defaultdict(list)
    for i in items:
        if i["kind"] == "accepted-silent" and i["repo"] not in _regatta.guarded():
            docs[i["file"]].append(i)
    total = sum(len(v) for v in docs.values())
    out = []
    out.append("# The %d decisions nobody recorded an answer to — your memory, one line per doc (%s)\n" % (
        total, dt.date.today().isoformat()))
    out.append("Companion to [jev-pipeline-2026-10-02.md](../../docs/record/jev-pipeline-2026-10-02.md) (D4, \"re-decide after "
               "data clean-up\"). Each item below is one document; under it, the decisions whose pre-filled answer "
               "was never edited and never got a `> **Done.**` reply. The transcripts could not say what you did "
               "with them (section 6 there, F10). Answer per document: **applied** (you said go, in any form), "
               "**not reached** (you never looked), or name the items you overruled and how. The pre-filled answer "
               "follows what the corpus already shows for the project. \"go\" accepts every pre-filled line. "
               "Where a line below already carries your own words (the hook committed your edit together with "
               "the doc, so the diff cannot see it — feedback-2026-09-29 D6 is one), write **mine** and name the "
               "item: it then counts as answered by you.\n")
    out.append("Legend: **D***n* one document · the lines under it are its unanswered decisions, "
               "`id` title → pre-filled answer.\n")
    n = 0
    for f in sorted(docs, key=lambda f: (docs[f][0]["repo"], f)):
        its = docs[f]
        n += 1
        repo = its[0]["repo"]
        out.append("- **D%d — %s** (%s, %s): %d unanswered of its D-items." % (
            n, os.path.basename(f), repo, its[0]["doc_date"], len(its)))
        for i in its:
            rec = (i["recommendation"] or "").replace("\n", " ")
            # the id in backticks: a bare `- D3 — …` would read as a D-item of this sheet to bin/memo
            out.append("  - `%s` %s → %s" % (i["id"], (i["title"] or "").rstrip(".:")[:90], rec[:100]))
        r = (evidence.get(f) or {}).get("reading") or {}
        dl = r.get("doc_level") or {}
        if dl.get("status") == "approved":
            out.append("  Chat: Opus read an approval — [%s] \"%s\"." % (str(dl.get("ts", ""))[:16], str(dl.get("quote", ""))[:120]))
            out.append("  ➤ Answer: applied (recommended)")
        elif repo in a.apply:
            out.append("  ➤ Answer: applied — a go in chat, as with the rest of %s (recommended)" % repo)
        else:
            out.append("  ➤ Answer: not reached (recommended)")
    out.append("\n## Feedback from the owner\n\n(anything that does not fit a line above)\n")
    with open(a.out, "w") as fh:
        fh.write("\n".join(out))
    print("wrote %s: %d docs, %d items" % (a.out, n, total))


if __name__ == "__main__":
    main()
