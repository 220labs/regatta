"""A vendor review round: planned prompts, two fresh reviews, a fresh verifier,
and review-gate's deterministic merge. The caller records fixes and the check.
"""
import importlib.machinery
import json
import re
import subprocess
import sys
from pathlib import Path

import vendorlib as v


REFORMAT = ("You reformat a review; do not review anything and use no tools. If the report below names no defect, "
            "answer exactly NO_FINDINGS and nothing else. Otherwise give one block per defect: a line "
            "`file:line — [S1|S2|S3] claim`, then `verdict: WRONG`, `evidence: ...` and `fix: ...`.\n\n")


def clean(text):
    return text.strip().split("\n")[0].strip() == "NO_FINDINGS"


def review(wt, cli, out, base="origin/main", origin="", model=v.MODEL, effort="high",
           on_pid=None, on_usage=None, timeout=7200):
    wt, out = Path(wt).resolve(), Path(out).resolve()
    v.fence(wt, cli, origin)
    why = v.preflight(cli, model, effort)
    if why:
        raise (v.Held if why.startswith("held") else v.Refused)(why)
    gate = v.common.tool("review-gate")
    if not gate:
        raise v.Refused("review-gate is absent")
    out.mkdir(parents=True, exist_ok=True)
    cmd = [sys.executable, str(gate)]
    plan = subprocess.run(cmd + ["plan", "--repo", str(wt), "--base", base, "--json"],
                          capture_output=True, text=True)
    if plan.returncode:
        raise v.Refused("review-gate plan failed")
    p = json.loads(plan.stdout)
    # run-vendor refuses a principal tier in the build's own brief; a principal flag here can only be a next step's
    # brief the builder wrote, which is no reason to fail this build (the plan's efforts still apply)
    mod = importlib.machinery.SourceFileLoader("vendor_review_gate", str(gate)).load_module()
    cost, reports = {}, []
    for key, default in (("reviewer", "reviewer-high"), ("code_review", "code-reviewer")):
        agent = (p.get(key) or {}).get("agent") or default
        if agent not in ("reviewer", "reviewer-high", "code-reviewer"):
            raise v.Refused("unknown planned reviewer")
        source = Path(gate).parent.parent / "agents" / (agent + ".md")
        prompt = (source.read_text() + "\nReview git diff %s...HEAD in %s. Read AGENTS.md and its Traps. "
                  "Do not edit or run any git write. No network or other agents. "
                  "Keep the agent's output format. %s"
                  "The template's Skill tool describes Claude's interface. Here, perform that review "
                  "directly with your native tools, read-only; use no Skill tool or Claude process.\n"
                  % (base, wt, "If you find no defects, answer NO_FINDINGS. " if key == "reviewer"
                     else "Return your JSON findings list, [] when clean. "))
        result = v.turn(cli, wt, prompt, review=True, origin=origin, model=model,
                        on_pid=on_pid, on_usage=on_usage, timeout=timeout,
                        effort=((p.get(key) or {}).get("effort") if (p.get(key) or {}).get("effort") in ("high", "xhigh")
                                else (p.get(key) or {}).get("level") or effort))
        text = result["last_answer"]
        v.fence(wt, cli, origin, text)
        v.add_cost(cost, result["cost"])
        if key == "reviewer":
            findings, seen = mod.parse_reviewer(text)
            # A clean report in prose is the common shape, not a fault (25 of 35 clean reports on a sibling prompt
            # missed a word they were told to give exactly): one short turn asks for it again, rather than a phrase
            # matcher deciding a report is clean (the Traps). The template's trailer after the word stays allowed.
            if not seen and not clean(text):
                again = v.turn(cli, wt, REFORMAT + text, review=True, origin=origin, model=model, effort="high",
                               on_pid=on_pid, on_usage=on_usage, timeout=timeout)
                text = again["last_answer"]
                v.fence(wt, cli, origin, text)
                v.add_cost(cost, again["cost"])
                findings, seen = mod.parse_reviewer(text)
            if not seen and not clean(text):
                raise v.Refused("reviewer report has no verdict or NO_FINDINGS")
        else:
            findings = mod.parse_code_review(text)
            if findings is None and clean(text):   # the reviewer's clean word, read as the empty list it means
                text, findings = "[]", []
            if findings is None:
                raise v.Refused("code reviewer report is not a findings list")
        path = out / (key + ".md")
        path.write_text(text)
        reports.append(path)
    merged = subprocess.run(cmd + ["merge", "--repo", str(wt), "--base", base, "--phase", "build",
                                   "--no-model", "--no-shadow", "--reviewer", str(reports[0]),
                                   "--code-review", str(reports[1])], capture_output=True, text=True)
    if merged.returncode:
        raise v.Refused("review-gate merge failed")
    (out / "merged.md").write_text(merged.stdout)
    # The deterministic merge has no severity model: S? is sent as S2. Include
    # only findings that can require work; notes and S3 never drive another round.
    blocks = re.split(r"(?m)(?=^\d+\. S[123?] ·)", merged.stdout)
    items = "\n".join(b for b in blocks if re.match(r"^\d+\. S[12?] ·", b) or "[WRONG]" in b)
    verdict = out / "verdicts.md"
    found = open_s1 = raised = 0
    if items.strip():
        prompt = ((Path(gate).parent.parent / "agents" / "reviewer-high.md").read_text() +
                  "\nYou are a fresh verifier; you raised none of these items. Verify only these findings "
                  "against %s...HEAD and the build brief in docs/handoff. S? means S2. "
                  "Return one block per item, including refuted items: file:line — [S1|S2|S3] claim, "
                  "then verdict: WRONG|OK-BUT|UNVERIFIABLE, evidence:, fix:. WRONG requires a concrete "
                  "failure introduced by this diff; intended behavior and defects on the base are OK-BUT. "
                  "Do not fix or edit.\n\n%s" % (base, items))
        result = v.turn(cli, wt, prompt, review=True, origin=origin, model=model, effort="high",
                        on_pid=on_pid, on_usage=on_usage, timeout=timeout)
        v.add_cost(cost, result["cost"])
        v.fence(wt, cli, origin, result["last_answer"])
        verdict.write_text(result["last_answer"])
        br = importlib.machinery.SourceFileLoader("vendor_build_review", str(v.HERE / "build-review")).load_module()
        raised, found, open_s1 = br.verdicts(result["last_answer"])
        expected = len(re.findall(r"(?m)^\d+\. S[123?] ·", items))
        if raised < expected:
            raise v.Refused("verifier report omits finding blocks")
    else:
        verdict.write_text("")
    return {"verdicts": str(verdict), "raised": raised, "found": found, "open_s1": open_s1,
            "cost": cost, "cli": cli}
