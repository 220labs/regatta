#!/usr/bin/env python3
"""Can Jev find what a voice memo should not put in git? Five arms over corpus.json.

    run.py [--arms jev-sent,jev-memo,jev-short,opus,gate-claude] [--out DIR] [--model jev-latest]
    run.py --score [--out DIR]

jev-sent: one Jev request per sentence; state = the sentence and its two neighbours; questions
          `sensitive` (noul) and `category` (choice).
jev-memo: one Jev request per transcript; one noul question per sentence, quoting it (Jev's
          listed weak spot is indirection, so the sentence text is in the question itself).
opus:     one `claude -p` per transcript, hooks off and no session file (sparks' QUIET set),
          asked for the same labels as JSON — the redaction pass the design proposes.
gate-claude: bin/gate's classify() per transcript, with a scratch table whose sparks.redact row is
          provider=claude, model opus — the call sparks makes after a `gate set` flip, so it
          measures the gate's Claude adapter against the opus arm (docs/model-gate-2026-10-04.md
          E9). The only arm through the gate: the Jev arms call bin/jev directly, as a bench must.

The corpus is invented (docs/idea-redaction-2026-10-04.md, "Considered: Jev"), so no guarded
data goes to TypeSafe. Answers go to DIR/<arm>.jsonl; --score prints the table. Stdlib, 3.9.
"""
import argparse
import importlib.machinery
import json
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
# The core, through the module's lib/find_core.py (G37: never a path relative to bin/, which moved).
sys.path.insert(0, os.path.join(HERE, "..", "..", "lib"))
import find_core  # noqa: E402
sys.path.insert(0, find_core.hooks())
import common  # noqa: E402
# Beside jev's and gate's usage logs (the core's LOG_DIR, `regatta/log-dir` in the config dir).
DEFAULT_OUT = str(common.LOG_DIR / "bench" / "redaction")
CATS = {
    "secret": "a credential, password, key, recovery code, or an account, card, passport, ID or case number, a phone number or e-mail",
    "money": "money tied to a person: salary, debts, savings, runway, an equity split, what they paid",
    "health": "anyone's health, illness, treatment, medication or hospital stay",
    "legal": "lawsuits, settlements, visas, immigration, contracts and their enforceability",
    "family": "the speaker's family, children and relationships: names, ages, schools, marital trouble",
    "person": "a third party's private matters: their troubles, health, family, business problems",
    "place": "a home address, a child's school, where someone lives or is treated",
    "work": "an employer's confidential information, or the speaker's private job plans",
    "off-record": "the speaker asks to keep something secret, between us, or out of the notes",
}
DEFINITION = (
    "A voice memo about ideas is summarised into notes stored in a git repository that other services "
    "and AI tools read. A sentence is SENSITIVE if it reveals any of: "
    + "; ".join(f"{k} ({v})" for k, v in CATS.items())
    + ". NOT sensitive: the idea itself, product prices, market sizes, generic business plans, "
      "public figures, children mentioned only as a market. The speakers are the note's owner and his "
      "co-founder Max; everyone else is a third party. Judge each sentence with its neighbours as context.")
SENS_Q = {"type": "noul", "instructions": DEFINITION + " Is `sentence` sensitive?",
          "criteria": {"true": "the sentence reveals something in one of the listed categories",
                       "false": "the sentence is about the idea, the product or generic plans only"}}
CAT_Q = {"type": "choice", "instructions": "Which category best describes what `sentence` reveals? "
                                           "Use the neighbours for context.",
         "criteria": dict(CATS, none="nothing sensitive: the idea, the product, generic plans")}
QUIET = ["--settings", '{"disableAllHooks": true}', "--no-session-persistence", "--strict-mcp-config"]


def corpus():
    return json.load(open(os.path.join(HERE, "corpus.json")))["transcripts"]


def core_tool(name):
    """The core's `name` (jev, gate) through common.tool() (G37); absent, one line and exit 2."""
    p = common.tool(name)
    if not p:
        sys.exit("run.py: %s not found — the regatta module (the core) is not installed" % name)
    return str(p)


def client():
    return importlib.machinery.SourceFileLoader("jev", core_tool("jev")).load_module()


def gate_claude(t, *_):
    """sparks.redact's call (idea-redaction E7) with the row flipped to claude: same ask, labels, context."""
    gate = importlib.machinery.SourceFileLoader("gate", core_tool("gate")).load_module()
    table = os.path.join(tempfile.mkdtemp(prefix="gate-claude-"), "models.json")
    with open(table, "w") as f:
        json.dump({"defaults": {"claude": {"model": "opus"}},
                   "sites": {"sparks.redact": {"kind": "classify", "provider": "claude", "model": "opus"}}}, f)
    s = t["sentences"]
    r = gate.classify("sparks.redact", {f"s{i + 1}": x["text"] for i, x in enumerate(s)},
                      "Is this sentence sensitive?",
                      {"yes": SENS_Q["criteria"]["true"], "no": SENS_Q["criteria"]["false"]},
                      context=DEFINITION, source="bench", caller="bench/redaction/run.py", table=table)
    for i in range(len(s)):
        yield {"t": t["id"], "i": i, "p": 1.0 if r["items"][f"s{i + 1}"]["label"] == "yes" else 0.0,
               "cost": r["cost_usd"] / len(s), "ms": r["ms"], "model": r.get("model")}


def jev_sent(t, jev, model):
    s = t["sentences"]
    for i, x in enumerate(s):
        state = {"previous": s[i - 1]["text"] if i else "", "sentence": x["text"],
                 "next": s[i + 1]["text"] if i + 1 < len(s) else ""}
        r = jev.ask(state, {"sensitive": SENS_Q, "category": CAT_Q}, model=model,
                    source="bench", caller="bench/redaction/run.py")
        a = r["answers"]
        yield {"t": t["id"], "i": i, "p": a["sensitive"]["noul"], "cat": a["category"]["choice"],
               "cost": r["cost_usd"], "ms": r["ms"], "model": r.get("model")}


def jev_memo(t, jev, model):
    s = t["sentences"]
    state = {"transcript": {f"s{i + 1}": x["text"] for i, x in enumerate(s)}}
    qs = {f"s{i + 1}": {"type": "noul", "instructions": DEFINITION + f" Is this sentence sensitive: \"{x['text']}\"",
                        "criteria": SENS_Q["criteria"]} for i, x in enumerate(s)}
    r = jev.ask(state, qs, model=model, source="bench", caller="bench/redaction/run.py")
    for i in range(len(s)):
        yield {"t": t["id"], "i": i, "p": r["answers"][f"s{i + 1}"]["noul"],
               "cost": r["cost_usd"] / len(s), "ms": r["ms"], "model": r.get("model")}


def jev_short(t, jev, model):
    """jev-memo with the definition in the state once: what an hour of speech needs to fit 64k."""
    s = t["sentences"]
    state = {"definition": DEFINITION, "transcript": {f"s{i + 1}": x["text"] for i, x in enumerate(s)}}
    qs = {f"s{i + 1}": {"type": "noul", "instructions": f"Per `definition`, is sentence s{i + 1} sensitive: \"{x['text']}\"",
                        "criteria": SENS_Q["criteria"]} for i, x in enumerate(s)}
    r = jev.ask(state, qs, model=model, source="bench", caller="bench/redaction/run.py")
    for i in range(len(s)):
        yield {"t": t["id"], "i": i, "p": r["answers"][f"s{i + 1}"]["noul"],
               "cost": r["cost_usd"] / len(s), "ms": r["ms"], "model": r.get("model"),
               "tokens": (r.get("usage") or {})}


def opus(t, *_):
    s = t["sentences"]
    lines = "\n".join(f"s{i + 1}: {x['text']}" for i, x in enumerate(s))
    prompt = (DEFINITION + "\n\nReturn only a JSON object mapping each sentence id to a list of the "
              "category names it reveals (" + ", ".join(CATS) + "), or [] if none. When in doubt, "
              "include it.\n\n" + lines)
    out = subprocess.run(["claude", "-p", prompt, "--model", "opus", "--tools", "",
                          "--output-format", "text", *QUIET], capture_output=True, text=True, timeout=300).stdout
    got = json.loads(re.search(r"\{.*\}", out, re.S).group(0))
    for i in range(len(s)):
        cats = got.get(f"s{i + 1}", [])
        yield {"t": t["id"], "i": i, "p": 1.0 if cats else 0.0, "cats": cats}


def auroc(pairs):
    pos = [p for p, y in pairs if y]
    neg = [p for p, y in pairs if not y]
    if not pos or not neg:
        return float("nan")
    wins = sum((p > n) + 0.5 * (p == n) for p in pos for n in neg)
    return wins / (len(pos) * len(neg))


def score(out):
    gold = {(t["id"], i): (x, t["lang"]) for t in corpus() for i, x in enumerate(t["sentences"])}
    print(f"{'arm':11} {'recall':>7} {'prec':>6} {'auroc':>6} {'hard':>6} {'en rec':>7} {'ru rec':>7} {'cat':>5} {'$':>8}")
    for arm in ("jev-sent", "jev-memo", "jev-short", "opus", "gate-claude"):
        path = os.path.join(out, arm + ".jsonl")
        if not os.path.exists(path):
            continue
        recs = [json.loads(l) for l in open(path)]
        rows = [(r, *gold[(r["t"], r["i"])]) for r in recs]
        tp = sum(1 for r, x, _ in rows if r["p"] >= .5 and x["cats"])
        fp = sum(1 for r, x, _ in rows if r["p"] >= .5 and not x["cats"])
        fn = sum(1 for r, x, _ in rows if r["p"] < .5 and x["cats"])
        hard = [(r["p"] >= .5) == bool(x["cats"]) for r, x, _ in rows if x.get("hard")]

        def rec(lang):
            ys = [r["p"] >= .5 for r, x, l in rows if l == lang and x["cats"]]
            return sum(ys) / len(ys)
        catok = [(r["cat"] in x["cats"]) if "cat" in r else bool(set(r["cats"]) & set(x["cats"]))
                 for r, x, _ in rows if x["cats"] and ("cat" in r or "cats" in r)]
        cost = sum(r.get("cost", 0) for r in recs)
        print(f"{arm:11} {tp / (tp + fn):7.2f} {tp / max(tp + fp, 1):6.2f} "
              f"{auroc([(r['p'], bool(x['cats'])) for r, x, _ in rows]):6.2f} "
              f"{sum(hard) / len(hard):6.2f} {rec('en'):7.2f} {rec('ru'):7.2f} "
              f"{(sum(catok) / len(catok)) if catok else float('nan'):5.2f} {cost:8.5f}")
        for r, x, l in rows:
            miss = r["p"] < .5 and x["cats"]
            extra = r["p"] >= .5 and not x["cats"]
            if miss or extra:
                print(f"    {'MISS ' if miss else 'EXTRA'} p={r['p']:.2f} [{l}] {','.join(x['cats']) or '-'}: {x['text'][:90]}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--arms", default="jev-sent,jev-memo,opus")
    ap.add_argument("--out", default=DEFAULT_OUT)
    ap.add_argument("--model", default="jev-latest")
    ap.add_argument("--score", action="store_true")
    a = ap.parse_args()
    if a.score:
        return score(a.out)
    os.makedirs(a.out, exist_ok=True)
    jev = client()
    for arm in a.arms.split(","):
        fn = {"jev-sent": jev_sent, "jev-memo": jev_memo, "jev-short": jev_short, "opus": opus,
              "gate-claude": gate_claude}[arm]
        with open(os.path.join(a.out, arm + ".jsonl"), "w") as f:
            for t in corpus():
                for rec in fn(t, jev, a.model):
                    f.write(json.dumps(rec, ensure_ascii=False) + "\n")
        print(f"{arm}: done", file=sys.stderr)


if __name__ == "__main__":
    main()
