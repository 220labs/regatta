#!/usr/bin/env python3
"""Score every arm's predictions against the owner's answers. Prints a Markdown table.

    score.py [--bench DIR]

Pre-registered (docs/record/jev-pipeline-2026-10-02.md, section 5) before any arm ran:
  primary    AUROC of `touched` against y_touched on known items (39 positives of 139)
  secondary  AUROC of `override` against y_override (14 positives — wide intervals, stated as
             such); Brier and ECE (10 equal-width bins) of `touched`; the share of known items
             that could be auto-applied at >= 95% and >= 90% precision by taking the items with
             the lowest `touched` first, and the number of overruled items that would slip
             through at each; AUROC of `attention` against y_touched; AUROC of `missing_info`
             against kind == accepted+question; cost and latency per decision.
  CI         bootstrap over items, 1000 resamples, seed 20261002, for both AUROCs.
Anything else printed is exploratory. Stdlib only.
"""
import sys
import argparse
import glob
import json
import os
import random

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import _regatta  # noqa: E402  the core: the data folder, the guarded repos
DEFAULT_BENCH = _regatta.data("decisions")


def auroc(pairs):
    """pairs: (score, label). Rank-based (Mann–Whitney), ties count half."""
    pos = [s for s, y in pairs if y]
    neg = [s for s, y in pairs if not y]
    if not pos or not neg:
        return float("nan")
    wins = 0.0
    for p in pos:
        for n in neg:
            wins += 1.0 if p > n else (0.5 if p == n else 0.0)
    return wins / (len(pos) * len(neg))


def brier(pairs):
    return sum((s - y) ** 2 for s, y in pairs) / len(pairs)


def ece(pairs, bins=10):
    total, out = len(pairs), 0.0
    for b in range(bins):
        lo, hi = b / bins, (b + 1) / bins
        inb = [(s, y) for s, y in pairs if lo <= s < hi or (b == bins - 1 and s == 1.0)]
        if inb:
            conf = sum(s for s, _ in inb) / len(inb)
            acc = sum(y for _, y in inb) / len(inb)
            out += len(inb) / total * abs(conf - acc)
    return out


def auto_accept_share(triples, precision):
    """triples: (score, y_touched, y_override). Take items in order of lowest predicted
    `touched`; the largest prefix whose share of untouched items stays >= precision. Returns
    (share of items, n, overruled items inside that prefix)."""
    ordered = sorted(triples, key=lambda t: t[0])
    best, best_slip, ok, slip = 0, 0, 0, 0
    for i, (s, yt, yo) in enumerate(ordered, 1):
        ok += 0 if yt else 1
        slip += yo
        # a prefix may only end where the score changes: items with the same score are one
        # block, or a tie's arbitrary order would decide the share (the rule row showed this)
        if i < len(ordered) and ordered[i][0] == s:
            continue
        if ok / i >= precision:
            best, best_slip = i, slip
    return best / len(triples), best, best_slip


def bootstrap_auroc(pairs, n=1000, seed=20261002):
    rnd = random.Random(seed)
    vals = []
    for _ in range(n):
        sample = [pairs[rnd.randrange(len(pairs))] for _ in pairs]
        v = auroc(sample)
        if v == v:
            vals.append(v)
    vals.sort()
    return vals[int(0.025 * len(vals))], vals[int(0.975 * len(vals))]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bench", default=os.environ.get("BENCH", DEFAULT_BENCH))
    ap.add_argument("--apply", type=lambda v: tuple(x for x in v.split(",") if x), default=(),
                    help="the post-hoc rule's repos, comma-separated: apply these, ask the rest")
    a = ap.parse_args()
    corpus = {json.loads(l)["key"]: json.loads(l) for l in open(os.path.join(a.bench, "corpus.jsonl"))}
    known = {k: v for k, v in corpus.items() if v["known"]}
    base = sum(v["y_override"] for v in known.values()) / max(1, len(known))
    print("known items %d, override base rate %.2f, touched %.2f, questions %d\n" % (
        len(known), base, sum(v["y_touched"] for v in known.values()) / max(1, len(known)),
        sum(1 for v in known.values() if v["kind"] == "accepted+question")))
    print("| arm | n | AUROC touched (95% CI) | AUROC override (95% CI) | Brier touched | ECE touched | auto-apply @95% (overruled slipping) | @90% | AUROC attention→touched | AUROC missing_info→question | $/decision | ms/decision | errors |")
    print("| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |")
    rows = []
    for path in sorted(glob.glob(os.path.join(a.bench, "pred-*.jsonl"))):
        arm = os.path.basename(path)[5:-6]
        preds = [json.loads(l) for l in open(path)]
        errors = sum(1 for p in preds if "error" in p)
        good = [p for p in preds if "error" not in p and p["key"] in known]
        if not good:
            rows.append("| %s | 0 | — | — | — | — | — | — | — | — | — | — | %d |" % (arm, errors))
            continue
        tc = [(float(p["touched"]), known[p["key"]]["y_touched"]) for p in good]
        ov = [(float(p["override"]), known[p["key"]]["y_override"]) for p in good]
        tri = [(float(p["touched"]), known[p["key"]]["y_touched"], known[p["key"]]["y_override"]) for p in good]
        att = [(float(p["attention"]), known[p["key"]]["y_touched"]) for p in good]
        # questions from the doc, the review sheet or chat alike (a deviation from the
        # pre-registration's "accepted+question", which predates the two other sources)
        mi = [(float(p["missing_info"]), int(known[p["key"]]["kind"] in ("accepted+question", "question-review", "question-chat"))) for p in good]
        tlo, thi = bootstrap_auroc(tc)
        olo, ohi = bootstrap_auroc(ov)
        s95, _, slip95 = auto_accept_share(tri, 0.95)
        s90, _, slip90 = auto_accept_share(tri, 0.90)
        costs = [p.get("cost_usd") for p in good if p.get("cost_usd") is not None]
        mss = [p.get("ms") for p in good if p.get("ms") is not None]
        rows.append("| %s | %d | %.2f (%.2f–%.2f) | %.2f (%.2f–%.2f) | %.3f | %.3f | %.0f%% (%d) | %.0f%% (%d) | %.2f | %.2f | $%.5f | %d | %d |" % (
            arm, len(good), auroc(tc), tlo, thi, auroc(ov), olo, ohi, brier(tc), ece(tc),
            100 * s95, slip95, 100 * s90, slip90, auroc(att), auroc(mi),
            sum(costs) / len(costs) if costs else float("nan"), sum(mss) / len(mss) if mss else -1, errors))
    # Post-hoc reference, added after the Claude arms ran (2026-10-02, exploratory): the
    # corpus showed touching is a per-project behaviour (one repo 2 of 58 known items touched,
    # another 0 of 5), so a two-line rule is the honest floor any model must beat. --apply names them.
    rule = [((0.0 if v["repo"] in a.apply else 1.0), v["y_touched"], v["y_override"]) for v in known.values()]
    rt = [(s, yt) for s, yt, _ in rule]
    s95, n95, slip95 = auto_accept_share(rule, 0.95)
    s90, n90, slip90 = auto_accept_share(rule, 0.90)
    rows.append("| rule: apply %s, ask the rest (post-hoc) | %d | %.2f | — | %.3f | — | %.0f%% (%d) | %.0f%% (%d) | — | — | $0 | 0 | 0 |" % (
        "+".join(a.apply) or "none", len(rt), auroc(rt), brier(rt), 100 * s95, slip95, 100 * s90, slip90))
    print("\n".join(rows))
    bt = sum(v["y_touched"] for v in known.values()) / max(1, len(known))
    print("\nReference: a constant prediction has AUROC 0.50; at the base rate its Brier is %.3f (touched) and %.3f "
          "(override); applying everything unread has precision %.2f on touched." % (bt * (1 - bt), base * (1 - base), 1 - bt))


if __name__ == "__main__":
    main()
