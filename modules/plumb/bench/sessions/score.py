#!/usr/bin/env python3
"""Score every arm against the owner's labels. Prints a Markdown table.

    score.py [--bench DIR] [--labels DIR/labels.json]

labels.json: {"<session>": "done|waiting_on_owner|blocked|running"} — the owner's corrected labels, typed
from the sheet in docs/record/jev-sessions-bench-2026-10-02.md. Pre-registered there before any arm
ran: primary = accuracy over the labels (3 in week one; 4 from week two, with `running`, D5) with a bootstrap interval (1,000 resamples, seed 20261002) and
the paired difference Jev − Haiku; secondary = macro-F1, AUROC and ECE of p_waiting against
"owner must act" (waiting_on_owner or blocked), the keyword rule's row, cost and latency per
session. Everything else is exploratory. Python 3.9, stdlib.
"""
import argparse
import collections
import glob
import json
import os
import random
import sys

# the pre-registered pattern lives in bin/session_status.py, which `bin/pickup list` runs too
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import _regatta  # noqa: E402  wharf's session_status.py through the core's tool() (G37)
DEFAULT_BENCH = _regatta.data("sessions")
sys.path.insert(0, os.path.dirname(_regatta.need("session_status.py")))
from session_status import ASK_RE  # noqa: E402
# D5 (2026-10-02): `running` joins the labels from week two; a week without it scores as before
LABELS = ("done", "waiting_on_owner", "blocked", "running")


def rule(row):
    """The keyword baseline, fixed before labelling: ask-words in the last 600 characters → waiting;
    else done. Blocked is never predicted (too rare to guess)."""
    tail = (row.get("text") or "")[-600:]
    if ASK_RE.search(tail):
        return "waiting_on_owner", 0.8
    return "done", 0.2


def must_act(gold):
    """Owner must act: waiting or blocked. A running session is not the owner's to act on (D5)."""
    return int(gold in ("waiting_on_owner", "blocked"))


def auroc(pairs):
    pos = [s for s, y in pairs if y]
    neg = [s for s, y in pairs if not y]
    if not pos or not neg:
        return float("nan")
    w = sum(1.0 if p > n else 0.5 if p == n else 0.0 for p in pos for n in neg)
    return w / (len(pos) * len(neg))


def ece(pairs, bins=10):
    out, total = 0.0, len(pairs)
    for b in range(bins):
        lo, hi = b / bins, (b + 1) / bins
        inb = [(s, y) for s, y in pairs if lo <= s < hi or (b == bins - 1 and s == 1.0)]
        if inb:
            out += len(inb) / total * abs(sum(s for s, _ in inb) / len(inb) - sum(y for _, y in inb) / len(inb))
    return out


def macro_f1(pred, gold, labels):
    f1s = []
    for lab in labels:
        tp = sum(1 for p, g in zip(pred, gold) if p == lab and g == lab)
        fp = sum(1 for p, g in zip(pred, gold) if p == lab and g != lab)
        fn = sum(1 for p, g in zip(pred, gold) if p != lab and g == lab)
        if tp + fp + fn == 0:
            continue
        pr = tp / (tp + fp) if tp + fp else 0.0
        rc = tp / (tp + fn) if tp + fn else 0.0
        f1s.append(2 * pr * rc / (pr + rc) if pr + rc else 0.0)
    return sum(f1s) / len(f1s) if f1s else float("nan")


def boot(vals, n=1000, seed=20261002):
    rnd = random.Random(seed)
    means = sorted(sum(rnd.choice(vals) for _ in vals) / len(vals) for _ in range(n))
    return means[int(0.025 * n)], means[int(0.975 * n)]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bench", default=os.environ.get("BENCH", DEFAULT_BENCH))
    ap.add_argument("--labels", default=None)
    a = ap.parse_args()
    rows = {json.loads(l)["session"]: json.loads(l) for l in open(os.path.join(a.bench, "sessions.jsonl"))}
    labels = json.load(open(a.labels or os.path.join(a.bench, "labels.json")))
    gold = {s: lab for s, lab in labels.items() if s in rows}
    print("labelled sessions: %d; by label: %s\n" % (len(gold), dict(collections.Counter(gold.values()))))
    print("| arm | n | accuracy (95% CI) | macro-F1 | AUROC p_waiting → must act | ECE p_waiting | $/session | ms/session | errors |")
    print("| --- | --- | --- | --- | --- | --- | --- | --- | --- |")
    per_arm = {}
    for path in sorted(glob.glob(os.path.join(a.bench, "pred-*.jsonl"))):
        arm = os.path.basename(path)[5:-6]
        preds = [json.loads(l) for l in open(path)]
        errors = sum(1 for p in preds if "error" in p)
        good = [p for p in preds if "error" not in p and p["session"] in gold]
        if not good:
            print("| %s | 0 | — | — | — | — | — | — | %d |" % (arm, errors))
            continue
        hits = [1 if p["status"] == gold[p["session"]] else 0 for p in good]
        per_arm[arm] = {p["session"]: h for p, h in zip(good, hits)}
        lo, hi = boot(hits)
        pw = [(float(p["p_waiting"]), must_act(gold[p["session"]])) for p in good]
        costs = [p["cost_usd"] for p in good if p.get("cost_usd") is not None]
        mss = [p["ms"] for p in good if p.get("ms") is not None]
        print("| %s | %d | %.2f (%.2f–%.2f) | %.2f | %.2f | %.3f | $%.5f | %d | %d |" % (
            arm, len(good), sum(hits) / len(hits), lo, hi,
            macro_f1([p["status"] for p in good], [gold[p["session"]] for p in good], LABELS),
            auroc(pw), ece(pw), sum(costs) / len(costs) if costs else float("nan"), sum(mss) / len(mss) if mss else -1, errors))
    # the keyword rule, fixed before labelling
    rp = [(rule(rows[s]), lab) for s, lab in gold.items()]
    hits = [1 if r[0] == lab else 0 for r, lab in rp]
    lo, hi = boot(hits)
    pw = [(r[1], must_act(lab)) for r, lab in rp]
    print("| rule: ask-words in the tail → waiting, else done (pre-registered) | %d | %.2f (%.2f–%.2f) | %.2f | %.2f | %.3f | $0 | 0 | 0 |" % (
        len(hits), sum(hits) / len(hits), lo, hi, macro_f1([r[0] for r, _ in rp], [lab for _, lab in rp], LABELS), auroc(pw), ece(pw)))
    maj = collections.Counter(gold.values()).most_common(1)[0]
    print("\nReference: always answering %r is right %.2f of the time." % (maj[0], maj[1] / len(gold)))
    if "jev" in per_arm and "haiku" in per_arm:
        common = sorted(set(per_arm["jev"]) & set(per_arm["haiku"]))
        diffs = [per_arm["jev"][s] - per_arm["haiku"][s] for s in common]
        lo, hi = boot(diffs)
        print("Paired Jev − Haiku accuracy on %d sessions: %+.2f (95%% CI %+.2f … %+.2f)." % (len(common), sum(diffs) / len(diffs), lo, hi))
    if "jev" in per_arm and "opus-medium" in per_arm:
        common = sorted(set(per_arm["jev"]) & set(per_arm["opus-medium"]))
        diffs = [per_arm["jev"][s] - per_arm["opus-medium"][s] for s in common]
        lo, hi = boot(diffs)
        print("Paired Jev − Opus medium on %d sessions: %+.2f (95%% CI %+.2f … %+.2f)." % (len(common), sum(diffs) / len(diffs), lo, hi))


if __name__ == "__main__":
    main()
