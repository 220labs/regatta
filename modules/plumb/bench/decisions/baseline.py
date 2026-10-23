#!/usr/bin/env python3
"""Ask a Claude model the same battery, headless, one `claude -p` per decision.

    baseline.py --arm opus-medium|opus-high|haiku|fable-high [--bench DIR] [--limit N] [--workers 4]

Same state and questions as jev.py (questions.prompt_for), no tools, no settings, no session
file, so the prompt carries everything and the cost is the call's alone. Each item records
`total_cost_usd` and `duration_ms` from the CLI's JSON result — measured, not from a price
table. Resumable like jev.py. Runs on the Max plan: the dollars are API list price for the
same tokens, the plan's percentages are what binds (bin/usage-report's convention).
"""
import argparse
import concurrent.futures
import json
import os
import re
import subprocess
import sys
import tempfile

from questions import prompt_for

ARMS = {
    "opus-medium": ("claude-opus-5-5", "medium"),
    "opus-high": ("claude-opus-5-5", "high"),
    "haiku": ("claude-haiku-4-5-20251001", None),
    "fable-high": ("claude-fable-5-1", "high"),
}
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import _regatta  # noqa: E402  the core: the data folder, the guarded repos
DEFAULT_BENCH = _regatta.data("decisions")


def call(prompt, model, effort, cwd):
    cmd = ["claude", "-p", "--model", model, "--output-format", "json", "--tools", "",
           "--setting-sources", "", "--no-session-persistence"]
    if effort:
        cmd += ["--effort", effort]
    env = {k: v for k, v in os.environ.items() if k != "CLAUDECODE"}
    p = subprocess.run(cmd, input=prompt, cwd=cwd, env=env, capture_output=True, text=True, timeout=600)
    try:
        res = json.loads(p.stdout)
    except ValueError:
        raise RuntimeError("no JSON: " + (p.stdout + p.stderr)[-300:])
    if res.get("is_error"):
        raise RuntimeError(str(res.get("result"))[:300])
    text = res["result"]
    m = re.findall(r"\{[^{}]*\}", text, re.S)
    if not m:
        raise RuntimeError("no object in: " + text[-300:])
    ans = json.loads(m[-1])
    return ans, res


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--arm", required=True, choices=sorted(ARMS))
    ap.add_argument("--bench", default=os.environ.get("BENCH", DEFAULT_BENCH))
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--workers", type=int, default=4)
    ap.add_argument("--known-only", action="store_true", help="only items that reached the owner (scored ones)")
    a = ap.parse_args()
    model, effort = ARMS[a.arm]
    items = [json.loads(l) for l in open(os.path.join(a.bench, "corpus.jsonl"))]
    if a.known_only:
        items = [i for i in items if i["known"]]
    out = os.path.join(a.bench, "pred-%s.jsonl" % a.arm)
    done = set()
    if os.path.exists(out):
        done = {json.loads(l)["key"] for l in open(out)}
    todo = [i for i in items if i["key"] not in done]
    if a.limit:
        todo = todo[:a.limit]
    cwd = tempfile.mkdtemp(prefix="decisions-bench-")

    def one(it):
        rec = {"key": it["key"], "arm": a.arm, "model": model, "effort": effort}
        try:
            ans, res = call(prompt_for(it), model, effort, cwd)
            rec.update({
                "touched": float(ans["touched"]), "override": float(ans["override"]),
                "attention": float(ans["attention"]),
                "missing_info": float(ans["missing_info"]),
                "cost_usd": res.get("total_cost_usd"), "ms": res.get("duration_ms"),
                "usage": res.get("usage"), "model_usage": res.get("modelUsage"),
            })
        except Exception as e:  # noqa: BLE001
            rec["error"] = str(e)[:300]
        return rec

    spent, n_err, n = 0.0, 0, 0
    with open(out, "a") as f, concurrent.futures.ThreadPoolExecutor(a.workers) as ex:
        for rec in ex.map(one, todo):
            n += 1
            spent += rec.get("cost_usd") or 0
            n_err += 1 if "error" in rec else 0
            f.write(json.dumps(rec, ensure_ascii=False) + "\n")
            f.flush()
            if n % 10 == 0 or n == len(todo):
                print("%s %d/%d  $%.2f  errors %d" % (a.arm, n, len(todo), spent, n_err), file=sys.stderr)
    print("done: %s, %d items, $%.2f, %d errors → %s" % (a.arm, len(todo), spent, n_err, out))


if __name__ == "__main__":
    main()
