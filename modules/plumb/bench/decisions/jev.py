#!/usr/bin/env python3
"""Ask Jev the battery over the corpus. One request per decision; answers to DIR/pred-jev.jsonl.

    jev.py [--bench DIR] [--model jev-latest] [--limit N] [--dry-run] [--exclude-repos a,b] [--approved TEXT]

Goes through bin/jev (AGENTS.md: "Jev goes through bin/jev"), which owns the key, the request
shape, retries, the cost line per call and the guarded-repo policy; this script only builds
the state and records the answers. Resumable: items already in the output file are skipped.
Cost is what bin/jev computed from the response's `usage`, so the total is measured. One bad
item is recorded with its error and the run goes on. Stdlib only, Python 3.9.
"""
import argparse
import importlib.machinery
import json
import os
import sys

from questions import JEV_QUESTIONS, state_for
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import _regatta  # noqa: E402  the core: the data folder, jev
DEFAULT_BENCH = _regatta.data("decisions")

HERE = os.path.dirname(os.path.abspath(__file__))


def load_client():
    """The core's jev, through common.tool() (G37)."""
    sys.path.insert(0, os.path.dirname(HERE))
    import _regatta
    return importlib.machinery.SourceFileLoader("jev", _regatta.need("jev")).load_module()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bench", default=os.environ.get("BENCH", DEFAULT_BENCH))
    ap.add_argument("--model", default="jev-latest")
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--dry-run", action="store_true", help="print one request body and exit")
    ap.add_argument("--exclude-repos", default=",".join(_regatta.guarded()),
                    help="projects whose decisions stay on this machine (D2 of the pipeline doc)")
    ap.add_argument("--approved", default=None,
                    help="the owner's quoted say-so, needed by bin/jev if a guarded repo is not excluded")
    a = ap.parse_args()
    excluded = set(x for x in a.exclude_repos.split(",") if x)
    items = [json.loads(l) for l in open(os.path.join(a.bench, "corpus.jsonl"))]
    items = [i for i in items if i["repo"] not in excluded]
    if a.dry_run:
        print(json.dumps({"state": state_for(items[0]), "model": a.model, "questions": JEV_QUESTIONS},
                         ensure_ascii=False, indent=1))
        return
    jev = load_client()
    errs, warns = jev.check(JEV_QUESTIONS, state_for(items[0]))
    if errs:
        sys.exit("bin/jev refuses the battery: " + "; ".join(errs))
    for w in warns:
        print("warning:", w, file=sys.stderr)
    out = os.path.join(a.bench, "pred-jev.jsonl")
    done = set()
    if os.path.exists(out):
        done = {json.loads(l)["key"] for l in open(out)}
    todo = [i for i in items if i["key"] not in done]
    if a.limit:
        todo = todo[:a.limit]
    spent, n_err = 0.0, 0
    with open(out, "a") as f:
        for n, it in enumerate(todo, 1):
            rec = {"key": it["key"], "arm": "jev", "model": a.model}
            try:
                r = jev.ask(state_for(it), JEV_QUESTIONS, model=a.model, source=it["repo"],
                            approved=a.approved, caller="bench/decisions/jev.py")
                ans = r["answers"]
                spent += r["cost_usd"]
                rec.update({
                    "model": r.get("model") or a.model, "ms": r["ms"], "usage": r.get("usage"),
                    "cost_usd": r["cost_usd"], "attempts": r.get("attempts"),
                    "touched": ans["touched"]["noul"],
                    "override": ans["override"]["noul"],
                    "attention": ans["attention"]["score"],
                    "attention_probs": ans["attention"].get("probabilities"),
                    "attention_confidence": ans["attention"].get("confidence"),
                    "missing_info": ans["missing_info"]["noul"],
                })
            except Exception as e:  # noqa: BLE001 — one bad item must not end the run
                n_err += 1
                rec["error"] = str(e)[:300]
            f.write(json.dumps(rec, ensure_ascii=False) + "\n")
            f.flush()
            if n % 25 == 0 or n == len(todo):
                print("%d/%d  $%.4f  errors %d" % (n, len(todo), spent, n_err), file=sys.stderr)
    print("done: %d items, $%.4f, %d errors → %s" % (len(todo), spent, n_err, out))


if __name__ == "__main__":
    main()
