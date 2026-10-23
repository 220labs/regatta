#!/usr/bin/env python3
"""The labelling sheet, and the labels read back from it.

    sheet.py [--bench DIR]                      write DIR/sheet.md (one D-item per session, pre-labelled)
    sheet.py --labels DIR/sheet.md [--bench DIR] read an answered sheet → DIR/labels.json

The sheet lives OUTSIDE the repo (orchestration D10 said "corrected in a doc"; the first cut put
it in docs/, and the reviewer of 2026-10-02 found children's names, an IP, a device model and a
guarded session's title in it — AGENTS.md: nothing personal in this repo). The doc keeps the
table, the decisions and a pointer. The owner answers in the file (VS Code opens it); `--labels`
reads it with bin/memo's parser and writes labels.json, refusing any answer that is not exactly
one of the four labels (running joined in week two, D5) so a note typed under a line is seen, not silently kept as the pre-label
(what happened on 2026-10-02, F-finding in the doc). Pre-labels below were written by the
session that built this bench after reading every reply, before any arm ran. A sheet that
already exists is never overwritten (the owner's answers would go with it): delete it by hand first.
"""
import argparse
import glob
import importlib.machinery
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import _regatta  # noqa: E402  keel's memo through the core's tool() (G37); needed only to read labels
DEFAULT_BENCH = _regatta.data("sessions")
MEMO = _regatta.find("keel") or _regatta.find("memo")  # memo: the overlay's old name for keel
LABELS = {"done": "done", "waiting on the owner": "waiting_on_owner", "waiting_on_owner": "waiting_on_owner", "blocked": "blocked",
          "running": "running"}  # running: D5, from week two
SHORT = {"done": "done", "waiting_on_owner": "waiting on the owner", "blocked": "blocked", "running": "running"}
# in the order collect.py sorts the judgment set (by time of the last reply), written 2026-10-02 05:10;
# 06:05 the two projects-root sessions left (guard by slug and both cwds); 11:30 the
# transcripts/household session left (guard by path prefix) — 43 remain
PRELABELS = """done waiting_on_owner done done waiting_on_owner done blocked waiting_on_owner done done
waiting_on_owner waiting_on_owner waiting_on_owner waiting_on_owner done waiting_on_owner done done done
waiting_on_owner waiting_on_owner waiting_on_owner blocked done waiting_on_owner done waiting_on_owner waiting_on_owner
waiting_on_owner waiting_on_owner done waiting_on_owner waiting_on_owner done done waiting_on_owner done waiting_on_owner
done done waiting_on_owner blocked waiting_on_owner""".split()


def write_sheet(bench):
    rows = [json.loads(l) for l in open(os.path.join(bench, "sessions.jsonl"))]
    left = [r for r in rows if r["rule"] == "none" and not r["guarded"]]
    out = os.path.join(bench, "sheet.md")
    if os.path.exists(out):
        raise SystemExit("%s exists — it may hold answers; move it away by hand first" % out)
    # pre-labels by session id when a file has them (the set may shrink as the guard learns);
    # the ordered constant only for a first build
    pre_path = os.path.join(bench, "labels-prelabel.json")
    if os.path.exists(pre_path):
        known = {k: v for k, v in json.load(open(pre_path)).items() if not k.startswith("_")}
        missing = [r["session"][:8] for r in left if r["session"] not in known]
        if missing:
            raise SystemExit("no pre-label for %s — label them (read the reply) and add to %s" % (missing, pre_path))
        pre = {r["session"]: known[r["session"]] for r in left}
    else:
        if len(left) != len(PRELABELS):
            raise SystemExit("judgment set has %d sessions, %d pre-labels — re-read before writing" % (len(left), len(PRELABELS)))
        pre = {r["session"]: lab for r, lab in zip(left, PRELABELS)}
    with open(pre_path, "w") as fh:
        json.dump(pre, fh, indent=1)
    votes = {}
    for path in glob.glob(os.path.join(bench, "pred-*.jsonl")):
        for l in open(path):
            p = json.loads(l)
            if "status" in p:
                votes.setdefault(p["session"], []).append(p["status"])
    lines = ["# Sessions sheet — %d judgment calls, one line each (bench/sessions, 2026-10-02)" % len(left), "",
             "Pre-filled with the agent's reading of the last reply. Change the `➤ Answer:` line where it is wrong, "
             "to exactly **done**, **waiting on the owner**, **blocked** or **running** (mid-work, not OK to close); a note goes on its own line under the item "
             "and `sheet.py --labels` will stop on it so it is read. \"go\" accepts every pre-filled line. The quoted "
             "text is the tail of the session's last reply; this file stays outside git.", ""]
    for i, r in enumerate(left, 1):
        tail = (r["text"] or "").strip().replace("\n", " ")[-260:].replace("➤", "›")
        title = r.get("title") or "(no title)"
        lines.append("- **D%d — %s** (%s, %s, session %s; last prompt: %s)" % (
            i, title[:70], r["repo"], (r["ts"] or "")[:10], r["session"][:8],
            ((r.get("last_prompt") or "")[:50] or "—").replace("\n", " ")))
        lines.append("  > …%s" % tail)
        v = votes.get(r["session"], [])
        if len(v) >= 3 and len(set(v)) == 1 and v[0] != pre[r["session"]]:
            lines.append("  *(all %d models read this as %s — look here first)*" % (len(v), SHORT[v[0]]))
        lines.append("  ➤ Answer: %s" % SHORT[pre[r["session"]]])
    lines += ["", "## Feedback from the owner", "", "(anything that does not fit a line above)", ""]
    with open(out, "w") as fh:
        fh.write("\n".join(lines))
    print("wrote %s (%d items); pre-labels: %s" % (out, len(left), {k: list(pre.values()).count(k) for k in SHORT}))


def read_labels(sheet, bench):
    memo = importlib.machinery.SourceFileLoader("memo", MEMO or _regatta.need("keel")).load_module()
    rows = {json.loads(l)["session"]: json.loads(l) for l in open(os.path.join(bench, "sessions.jsonl"))}
    _, items, _ = memo.parse(open(sheet).read())
    labels, problems = {}, []
    for it in items:
        head = it["title"] or ""
        sid = None
        for s in rows:
            if "session %s" % s[:8] in head:
                sid = s
        if not sid:
            problems.append("%s: no session id in the title" % it["id"])
            continue
        ans = (it["answer"] or "").strip()
        key = ans.lower().rstrip(".")
        if key in LABELS:
            labels[sid] = LABELS[key]
        else:
            problems.append("%s (%s): answer is not one of the four labels — %r" % (it["id"], sid[:8], ans[:120]))
    out = os.path.join(bench, "labels.json")
    with open(out, "w") as fh:
        json.dump({"_source": "sheet.py --labels %s" % os.path.basename(sheet), **labels}, fh, indent=1)
    print("labels: %d written to %s" % (len(labels), out))
    if problems:
        print("NOT labelled — read these and decide:", file=sys.stderr)
        for p in problems:
            print("  " + p, file=sys.stderr)
        sys.exit(1)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bench", default=os.environ.get("BENCH", DEFAULT_BENCH))
    ap.add_argument("--labels", metavar="SHEET", help="read an answered sheet into labels.json")
    a = ap.parse_args()
    if a.labels:
        read_labels(a.labels, a.bench)
    else:
        write_sheet(a.bench)


if __name__ == "__main__":
    main()
