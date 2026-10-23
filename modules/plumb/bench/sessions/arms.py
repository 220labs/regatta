#!/usr/bin/env python3
"""Run one arm over the judgment set. Predictions to DIR/pred-<arm>.jsonl, resumable.

    arms.py --arm jev|haiku|opus-medium [--bench DIR] [--limit N] [--workers 4] [--include-guarded --approved TEXT]

Jev goes through bin/jev (AGENTS.md), `source` = the session's repo on every call, so a
guarded repo (`regatta/guarded`) is refused unless the owner's say-so is quoted in
--approved; by default guarded sessions are not sent at all and are not scored for any arm.
The Claude arms run headless (`claude -p`, no tools, no settings) with the same state rendered
as a prompt; each records its own total_cost_usd and duration_ms. Python 3.9, stdlib.
"""
import argparse
import concurrent.futures
import importlib.machinery
import json
import os
import re
import subprocess
import sys
import tempfile

from questions import JEV_QUESTIONS, LABELS, prompt_for, state_for
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import _regatta  # noqa: E402  the core: the data folder, jev
DEFAULT_BENCH = _regatta.data("sessions")

HERE = os.path.dirname(os.path.abspath(__file__))
LLM = {"haiku": ("claude-haiku-4-5-20251001", None), "opus-medium": ("claude-opus-5-5", "medium"),
       "sonnet-medium": ("claude-sonnet-5-5", "medium")}


def load_jev():
    sys.path.insert(0, os.path.dirname(HERE))
    import _regatta  # the core's tool() finds jev (G37)
    return importlib.machinery.SourceFileLoader("jev", _regatta.need("jev")).load_module()


def llm_call(prompt, model, effort, cwd):
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
    m = re.findall(r"\{[^{}]*\}", res["result"], re.S)
    if not m:
        raise RuntimeError("no object in: " + res["result"][-300:])
    ans = json.loads(m[-1])
    if ans.get("status") not in LABELS:
        raise RuntimeError("bad status %r" % ans.get("status"))
    return ans, res


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--arm", required=True, choices=["jev"] + sorted(LLM))
    ap.add_argument("--bench", default=os.environ.get("BENCH", DEFAULT_BENCH))
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--workers", type=int, default=4)
    ap.add_argument("--include-guarded", action="store_true")
    ap.add_argument("--approved", default=None, help="the owner's quoted say-so for guarded repos")
    a = ap.parse_args()
    rows = [json.loads(l) for l in open(os.path.join(a.bench, "sessions.jsonl"))]
    rows = [r for r in rows if r["rule"] == "none" and r.get("repo")]
    # a guarded session goes to ANY arm only with the owner's quoted say-so — the Claude arms send
    # text off the machine too (to Anthropic, as every session does), and bin/jev's own guard
    # fires on `source` alone, which for a root-cwd session reads "projects" (F0)
    if a.include_guarded and not (a.approved or "").strip():
        sys.exit("--include-guarded needs --approved \"the owner, <date>: <what>\"")
    rows = [r for r in rows if a.include_guarded or not r["guarded"]]
    out = os.path.join(a.bench, "pred-%s.jsonl" % a.arm)
    done = {json.loads(l)["session"] for l in open(out)} if os.path.exists(out) else set()
    todo = [r for r in rows if r["session"] not in done]
    if a.limit:
        todo = todo[:a.limit]
    spent, n_err, n = 0.0, 0, 0

    if a.arm == "jev":
        jev = load_jev()
        errs, _ = jev.check(JEV_QUESTIONS, state_for(todo[0]) if todo else None)
        if errs:
            sys.exit("bin/jev refuses the battery: " + "; ".join(errs))

        def one(r):
            rec = {"session": r["session"], "arm": "jev"}
            try:
                # a guarded session is declared as such to bin/jev whatever its last cwd said
                source = (_regatta.guarded() or ("guarded",))[0] if r["guarded"] else r["repo"]
                res = jev.ask(state_for(r), JEV_QUESTIONS, source=source, approved=a.approved,
                              caller="bench/sessions/arms.py")
                st = res["answers"]["status"]
                rec.update({"model": res.get("model"), "ms": res["ms"], "cost_usd": res["cost_usd"],
                            "status": st["choice"], "probabilities": st["probabilities"],
                            "confidence": st.get("confidence"),
                            "p_waiting": st["probabilities"].get("waiting_on_owner", 0) + st["probabilities"].get("blocked", 0),
                            "needs_owner": res["answers"]["needs_owner"]["noul"],
                            "handoff": res["answers"]["handoff"]["noul"]})
            except Exception as e:  # noqa: BLE001
                rec["error"] = str(e)[:300]
            return rec
        workers = 1
    else:
        model, effort = LLM[a.arm]
        cwd = tempfile.mkdtemp(prefix="sessions-bench-")

        def one(r):
            rec = {"session": r["session"], "arm": a.arm, "model": model, "effort": effort}
            try:
                ans, res = llm_call(prompt_for(r), model, effort, cwd)
                rec.update({"status": ans["status"], "p_waiting": float(ans.get("p_waiting", 0.5)),
                            "handoff": float(ans.get("handoff", 0.5)), "cost_usd": res.get("total_cost_usd"),
                            "ms": res.get("duration_ms")})
            except Exception as e:  # noqa: BLE001
                rec["error"] = str(e)[:300]
            return rec
        workers = a.workers

    with open(out, "a") as f, concurrent.futures.ThreadPoolExecutor(workers) as ex:
        for rec in ex.map(one, todo):
            n += 1
            spent += rec.get("cost_usd") or 0
            n_err += 1 if "error" in rec else 0
            f.write(json.dumps(rec, ensure_ascii=False) + "\n")
            f.flush()
    print("done: %s, %d items, $%.4f, %d errors → %s" % (a.arm, len(todo), spent, n_err, out))


if __name__ == "__main__":
    main()
