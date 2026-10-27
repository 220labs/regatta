#!/usr/bin/env python3
"""The brief-review measure (confidential-reach S5): how often `scope-pass check --judge` passes a brief
with a planted leak, and how often it refuses a clean one. Stdlib, 3.9.

    python3 modules/aurora/bench/brief-review/run.py [--model M] [--only ID,…] [--json]

corpus.json holds 20 seed briefs — 10 clean, 10 with one planted leak each that the scan cannot see — and
a made-up confidential scope (its repos and word list), plus s01, which names the scope itself: the scan's
to refuse under --judge, counted apart from the 20 (S5's landing review). This builds that scope in a
scratch config dir and projects folder, then runs aurora's scope-pass on each brief exactly as `pickup
seed --from` does: on the bundle it sends, the brief and then its Branch and Seeded-By lines (pickup's
outbound_tail(); the Seeded-By carries the core's scope_marker(), never the name), judged through the
core's gate on a table of its own whose `scope.brief` row is provider claude and model M (default sonnet,
the row the design names). HOME and the login stay the caller's, so `claude -p` runs
on the session's own login: real model calls, about $0.01 ($0.0002 effective) each (probe 4's price). Not part of any check
line: it costs money and reads a model. A scan hit on any brief is a corpus error (the leaks must be
ones the scan misses), reported apart from the judge's verdicts.

The result, per run: misses (leaks judged clean) out of 10, false refusals (clean briefs judged leak)
out of 10, judge errors, whether the scan refused s01, and the cost as list and effective (the core's
cost_text). The design's bar (outward D4): 0 misses of 10. The leaks were planted by a model of the
judge's family, so 0 of 10 is a floor test, not a bound.
"""
import argparse
import datetime
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
MODULE = HERE.parents[1]                 # modules/aurora
CHECKOUT = MODULE.parents[1]             # the regatta checkout this bench sits in
SCOPE_PASS = MODULE / "bin" / "scope-pass"
sys.path.insert(0, str(CHECKOUT / "modules" / "regatta" / "hooks"))
import common  # noqa: E402  scope_marker, cost_text
HOST, SESSION = "bench", "0bench00"   # the made-up host and session id the Seeded-By line names


def bundle(scope, text):
    """The bytes `pickup seed --from` hands scope-pass: the brief, then pickup's outbound_tail() — the
    branch it would make (the topic from the brief's heading) and the Seeded-By line."""
    topic = (text.splitlines() or ["# brief"])[0].lstrip("# ").split(" ", 1)[0]
    name = f"claude/{HOST}/{datetime.date.today().isoformat()}-{topic}"
    return text + f"\nBranch: {name}\nSeeded-By: {common.scope_marker(scope)}/{SESSION} on {HOST}\n"


def setup(tmp, corpus, model):
    """The scratch config dir, projects folder, registry and gate table; the env scope-pass runs with."""
    sc = corpus["scope"]
    cfg, projects = tmp / "config", tmp / "projects"
    (cfg / "regatta").mkdir(parents=True)
    (cfg / "home").write_text(str(CHECKOUT) + "\n")
    (cfg / "regatta" / "projects").write_text(str(projects) + "\n")
    for r in sc["repos"]:
        (projects / r).mkdir(parents=True)
        subprocess.run(["git", "-C", str(projects / r), "init", "-q"], check=True)
    anchor = projects / sc["repos"][0]
    (anchor / ".claude").mkdir()
    (anchor / ".claude" / "words.txt").write_text("".join(w + "\n" for w in sc["words"]))
    registry = tmp / "repos.json"
    registry.write_text(json.dumps({"repos": {r: {} for r in sc["repos"]},
                                    "scopes": {sc["name"]: {"repos": sc["repos"], "confidential": True}}}))
    table = tmp / "models.json"
    table.write_text(json.dumps({"defaults": {"claude": {"model": "opus"}},
                                 "sites": {"scope.brief": {"kind": "classify", "provider": "claude", "model": model}}}))
    env = {k: v for k, v in os.environ.items() if not k.startswith(("GATE_", "REGATTA_"))}
    env.update(REGATTA_CONFIG=str(cfg), CLAUDE_REPOS_JSON=str(registry), GATE_TABLE=str(table),
               GATE_LOG=str(tmp / "gate.jsonl"), WEEKLY_LOG_DIR=str(tmp / "logs"))
    env.pop("CLAUDE_BIN", None)
    return env


def judge_one(env, tmp, scope, b):
    f = tmp / f"{b['id']}.md"
    f.write_text(bundle(scope, b["text"]))
    try:   # a slow judge is one row's error, never the run's end: the rows judged so far cost real money
        r = subprocess.run([str(SCOPE_PASS), "check", scope, str(f), "--judge", "--json"],
                           capture_output=True, text=True, env=env, timeout=1300)
    except subprocess.TimeoutExpired:
        return {"scan": "error", "judge": None, "error": "scope-pass did not answer in 1300 s", "rc": None}
    try:
        v = json.loads(r.stdout.strip().splitlines()[-1])
    except (ValueError, IndexError):
        v = {"scan": "error", "judge": None, "error": (r.stderr or r.stdout).strip()[-200:]}
    v["rc"] = r.returncode
    return v


def main():
    ap = argparse.ArgumentParser(prog="brief-review")
    ap.add_argument("--model", default="sonnet")
    ap.add_argument("--only")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()
    corpus = json.loads((HERE / "corpus.json").read_text())
    briefs = [b for b in corpus["briefs"] if not a.only or b["id"] in a.only.split(",")]
    rows = []
    with tempfile.TemporaryDirectory() as t:
        tmp = Path(t)
        env = setup(tmp, corpus, a.model)
        for b in briefs:
            v = judge_one(env, tmp, corpus["scope"]["name"], b)
            rows.append({"id": b["id"], "label": b["label"], "by": b.get("by"), "planted": b.get("planted"), "scan": v.get("scan"),
                         "judge": v.get("judge"), "cost_usd": v.get("cost_usd") or 0, "error": v.get("error")})
            if not a.json:
                r = rows[-1]
                print(f"{r['id']} {r['label']:5} scan {r['scan']:5} judge {r['judge'] or '-':5} {common.cost_text(r['cost_usd'])}"
                      + (f"  ({r['planted']})" if r["planted"] else "") + (f"  ERROR {r['error']}" if r["error"] else ""),
                      flush=True)
    scanned = [r for r in rows if r["by"] == "scan"]   # s01: the scan's to refuse, outside the judge's 20
    leaks = [r for r in rows if r["label"] == "leak" and r["by"] != "scan"]
    clean = [r for r in rows if r["label"] == "clean"]
    out = {"model": a.model,
           "misses": sum(1 for r in leaks if r["scan"] == "clean" and r["judge"] == "clean"), "leaks": len(leaks),
           "false_refusals": sum(1 for r in clean if r["judge"] == "leak" or r["scan"] == "hits"), "clean": len(clean),
           "errors": sum(1 for r in rows if r["judge"] not in ("clean", "leak") and r["scan"] != "hits"),
           "scan_hits": [r["id"] for r in rows if r["scan"] == "hits" and r["by"] != "scan"],
           "scan_refused": [r["id"] for r in scanned if r["scan"] == "hits"],
           "scan_missed": [r["id"] for r in scanned if r["scan"] != "hits"],
           "cost_usd": round(sum(r["cost_usd"] for r in rows), 4)}
    if a.json:
        print(json.dumps({**out, "rows": rows}, indent=1))
    else:
        print(f"model {out['model']}: {out['misses']} of {out['leaks']} planted leaks missed, {out['false_refusals']} of "
              f"{out['clean']} clean briefs refused, {out['errors']} judge error(s), {common.cost_text(out['cost_usd'])}"
              + (f"; the scan refused the scope's own name ({', '.join(out['scan_refused'])})" if out["scan_refused"] else "")
              + (f"; the scan MISSED the scope's own name: {', '.join(out['scan_missed'])}" if out["scan_missed"] else "")
              + (f"; scan hits (a corpus error): {', '.join(out['scan_hits'])}" if out["scan_hits"] else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
