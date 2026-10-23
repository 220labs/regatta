#!/usr/bin/env python3
"""Did the owner answer a D-list in chat rather than in the doc? Evidence from the transcripts.

    chat_evidence.py [--bench DIR] [--transcripts ~/projects/transcripts] [--no-llm] [--limit N]

The corpus (corpus.py) reads answers from the docs. Earlier docs were often answered in chat
("go", "D3 no, use iMessage") and the agent wrote the Done reply, or nothing. For every doc
with items of unknown status this script:

1. finds the sessions that wrote or edited the doc (a tool call carrying its path) or where
   the owner named it in a prompt, and the moment that happened in each;
2. takes the owner's own prompts in those sessions from that moment on (not hook text, not tool
   results, not sidechains);
3. asks Opus 5.5 `medium`, headless, to read those prompts against the doc's D-list and say
   per item whether the owner accepted, overruled, questioned or never mentioned it, with the
   quote and its timestamp — an LLM because the mapping needs reading, not matching;
4. prints a review sheet in memo format, one D-item per doc, for the owner to confirm.

Writes DIR/chat-evidence.json (prompts and readings, every repo). The guarded repos (`regatta/guarded`) are
read but left off the printed sheet. Nothing here changes a label by itself: the confirmed
readings go to corpus.py via --chat. Transcripts are read, never written. Python 3.9, stdlib.
"""
import argparse
import collections
import glob
import json
import os
import sys

from baseline import call

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import _regatta  # noqa: E402  the core: the data folder, the guarded repos
DEFAULT_BENCH = _regatta.data("decisions")
DEFAULT_TRANSCRIPTS = os.path.expanduser("~/projects/transcripts")
MAX_PROMPTS, MAX_CHARS = 40, 500
NOISE = ("<local-command", "<command-", "[Request interrupted", "Caveat:", "<ide_", "<system-reminder",
         "<task-notification", "[SYSTEM NOTIFICATION")


def first_json_object(text):
    """The first complete JSON object in a model's reply, nested braces included.
    baseline.call's own parser takes the innermost `{…}`, which flattens a nested reading."""
    i = text.find("{")
    while i >= 0:
        try:
            obj, _ = json.JSONDecoder().raw_decode(text[i:])
            if isinstance(obj, dict) and "items" in obj:
                return obj
        except ValueError:
            pass
        i = text.find("{", i + 1)
    raise ValueError("no reading object in: " + text[-200:])


def latest_per_session(files):
    """`YYYY-MM-DD-<sess8>.jsonl` is written daily for a live session; keep the newest per session."""
    best = {}
    for f in files:
        b = os.path.basename(f)[:-6]
        sess = b[11:]
        if sess not in best or b > os.path.basename(best[sess])[:-6]:
            best[sess] = f
    return list(best.values())


def scan(path, basenames):
    """One pass. Returns ({basename: ts first written or named here}, [(ts, prompt)])."""
    tied, prompts = {}, []
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            hit = [b for b in basenames if b in line]
            is_user = '"type":"user"' in line or '"type": "user"' in line
            if not hit and not is_user:
                continue
            try:
                d = json.loads(line)
            except ValueError:
                continue
            ts = d.get("timestamp", "")
            if hit:
                # any mention ties the session to the doc from that moment: the session that
                # wrote it, one that read it to act, one where the owner named it. Docs cited by
                # always-loaded rules are excluded by the caller (every session mentions them).
                for b in hit:
                    tied.setdefault(b, ts)
            if d.get("type") != "user" or d.get("isMeta") or d.get("isSidechain"):
                continue
            c = d.get("message", {}).get("content")
            # a typed prompt is a string, or — most of the time — a list of text blocks (the
            # IDE attaches context as extra blocks); the first version kept only strings and
            # dropped about 90% of the owner's prompts (reviewer, 2026-10-02). Tool results are
            # blocks of another type and fall out here.
            if isinstance(c, list):
                parts = [b.get("text", "") for b in c if b.get("type") == "text"]
                parts = [p.strip() for p in parts if p.strip() and not any(p.strip().startswith(n) for n in NOISE)]
                c = "\n".join(parts)
            if not isinstance(c, str):
                continue
            c = c.strip()
            if not c or any(c.startswith(n) for n in NOISE):
                continue
            prompts.append((ts, c))
            for b in hit:
                tied.setdefault(b, ts)
    return tied, prompts


def read_with_llm(doc, its, lines):
    dlist = "\n".join("- %s — %s\n  pre-filled answer: %s" % (i["id"], i["title"], (i["recommendation"] or "")[:200]) for i in its)
    chat = "\n".join("[%s] %s" % (ts[:16].replace("T", " "), text[:MAX_CHARS].replace("\n", " ")) for ts, text in lines)
    prompt = (
        "A design document put a numbered list of decisions to its owner, each with a pre-filled "
        "recommendation. Below are the decisions and then the owner's own chat messages, in time "
        "order, from the sessions that wrote or discussed the document, starting when it was written. "
        "Decide for each decision whether the owner answered it IN CHAT: `accepted` (a go, yes, "
        "approved, or agreement that covers it — a bare \"go\" after the document was presented "
        "covers every item unless a message singles one out), `overruled` (a different answer, a "
        "correction, a no), `question` (asked something about it, no answer), or `not_mentioned`. "
        "Quote the message fragment you rely on and its timestamp. Be strict: a \"go\" that plainly "
        "belongs to other work in the same session is not an answer. Return only one JSON object: "
        '{"doc_level": {"status": "approved|none", "quote": "", "ts": ""}, '
        '"items": {"D1": {"status": "accepted|overruled|question|not_mentioned", "quote": "", "ts": ""}, ...}}'
        "\n\nDOCUMENT: %s\n\nDECISIONS:\n%s\n\nOWNER'S CHAT MESSAGES:\n%s" % (doc, dlist, chat or "(none)")
    )
    _, res = call(prompt, "claude-opus-5-5", "medium", os.environ.get("TMPDIR", "/tmp"))
    return first_json_object(res["result"]), res.get("total_cost_usd") or 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bench", default=os.environ.get("BENCH", DEFAULT_BENCH))
    ap.add_argument("--transcripts", default=DEFAULT_TRANSCRIPTS)
    ap.add_argument("--no-llm", action="store_true", help="only gather the prompts")
    ap.add_argument("--limit", type=int, default=0)
    a = ap.parse_args()
    items = [json.loads(l) for l in open(os.path.join(a.bench, "corpus.jsonl"))]
    docs = collections.defaultdict(list)
    for i in items:
        docs[i["file"]].append(i)
    todo = {f: its for f, its in docs.items() if any(i["kind"] == "accepted-silent" for i in its)}
    always = ""
    # the always-loaded files: the layer's rules/ and the vault's me/ (atlas's keys, as knowledge-numbers reads them)
    known = [(_regatta.common().config_lines(k) or [None, None])[1] for k in ("atlas/layer", "atlas/vault")]
    pats = [os.path.join(os.path.expanduser(r), d, "*.md") for r, d in zip(known, ("rules", "me")) if r]
    for p in [f for pat in pats for f in glob.glob(pat)]:
        always += open(p, encoding="utf-8", errors="replace").read()
    cited = {os.path.basename(f) for f in todo if os.path.basename(f) in always}
    if cited:
        print("cited by always-loaded files, tied to no session: %s" % ", ".join(sorted(cited)), file=sys.stderr)
    # every transcript folder, not only the doc's repo: a studio doc was named in 108 files
    # under four other repos and in none under its own (reviewer, 2026-10-02)
    names = {os.path.basename(f): f for f in todo if os.path.basename(f) not in cited}
    evidence = {f: {"repo": its[0]["repo"], "sessions": [], "lines": []} for f, its in todo.items()}
    if names:
        files = latest_per_session(glob.glob(os.path.join(a.transcripts, "*", "*.jsonl")))
        for path in sorted(files):
            tied, prompts = scan(path, list(names))
            sess = os.path.basename(path)[11:-6]
            for b, t0 in tied.items():
                ev = evidence[names[b]]
                after = [(ts, t) for ts, t in prompts if ts >= t0][:MAX_PROMPTS]
                ev["sessions"].append({"session": sess, "from": t0[:16], "prompts": len(after)})
                ev["lines"] += [{"ts": ts, "session": sess, "text": t[:MAX_CHARS]} for ts, t in after]
    out = os.path.join(a.bench, "chat-evidence.json")
    old = json.load(open(out)) if os.path.exists(out) else {}
    spent, n = 0.0, 0
    for f in sorted(evidence, key=lambda f: (evidence[f]["repo"], f)):
        ev = evidence[f]
        ev["lines"].sort(key=lambda l: l["ts"])
        if old.get(f, {}).get("reading"):
            ev["reading"] = old[f]["reading"]
            continue
        if a.no_llm or not ev["lines"] or (a.limit and n >= a.limit):
            continue
        n += 1
        try:
            ev["reading"], cost = read_with_llm(os.path.basename(f), todo[f], [(l["ts"], l["text"]) for l in ev["lines"]])
            spent += cost
        except Exception as e:  # noqa: BLE001
            ev["reading_error"] = str(e)[:300]
        print("read %s ($%.2f so far)" % (os.path.basename(f), spent), file=sys.stderr)
    with open(out, "w") as fh:
        json.dump(evidence, fh, ensure_ascii=False, indent=1)
    print("docs with unknown items: %d; with chat lines: %d; LLM readings this run: %d, $%.2f\n" % (
        len(todo), sum(1 for e in evidence.values() if e["lines"]), n, spent))
    k = 0
    for f in sorted(todo, key=lambda f: (todo[f][0]["repo"], f)):
        its, ev = todo[f], evidence[f]
        if its[0]["repo"] in _regatta.guarded():
            continue
        unknown = [i["id"] for i in its if i["kind"] == "accepted-silent"]
        k += 1
        print("- **D%d — %s** (%s): unknown %s of %d; %d session(s), %d prompts after the doc." % (
            k, os.path.basename(f), its[0]["repo"], ", ".join(unknown), len(its), len(ev["sessions"]), len(ev["lines"])))
        r = ev.get("reading")
        if not ev["lines"]:
            print("  No session wrote or named this doc in the transcripts kept.\n  ➤ Answer: not reached — leave unknown (recommended)")
            continue
        if not r:
            print("  (not read: %s)\n  ➤ Answer: unclear — leave unknown (recommended)" % ev.get("reading_error", "no LLM pass"))
            continue
        dl = r.get("doc_level", {})
        if dl.get("status") == "approved":
            print("  Doc-level: approved — [%s] \"%s\"" % (str(dl.get("ts", ""))[:16], str(dl.get("quote", ""))[:160]))
        parts = []
        for d in unknown:
            x = r.get("items", {}).get(d, {})
            st = x.get("status", "not_mentioned")
            if st != "not_mentioned":
                parts.append("%s %s ([%s] \"%s\")" % (d, st, str(x.get("ts", ""))[:16], str(x.get("quote", ""))[:120]))
        for p in parts:
            print("  - " + p)
        statuses = {d: r.get("items", {}).get(d, {}).get("status", "not_mentioned") for d in unknown}
        if dl.get("status") == "approved":
            over = [d for d, s in statuses.items() if s == "overruled"]
            print("  ➤ Answer: accepted in chat%s (recommended)" % (", except %s overruled" % ", ".join(over) if over else ""))
        elif any(s != "not_mentioned" for s in statuses.values()):
            print("  ➤ Answer: as read above; items not mentioned stay unknown (recommended)")
        else:
            print("  ➤ Answer: not reached — leave unknown (recommended)")


if __name__ == "__main__":
    main()
