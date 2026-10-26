#!/usr/bin/env python3
"""bench's pure parts: case labels, the isolation rule, cost from a transcript, the ledger.
Exit 0 when every case passes; one line per case."""
import importlib.machinery
import importlib.util
import json
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
loader = importlib.machinery.SourceFileLoader("bench", os.path.join(HERE, "bench"))
spec = importlib.util.spec_from_loader("bench", loader)
b = importlib.util.module_from_spec(spec)
loader.exec_module(b)
fails = 0
T = tempfile.mkdtemp()


def check(got, want, name):
    global fails
    if got == want:
        print("  ok   " + name)
    else:
        print("  FAIL %s: expected [%s] got [%s]" % (name, want, got))
        fails += 1


def transcript(blocks, name="t.jsonl"):
    p = os.path.join(T, name)
    with open(p, "w") as f:
        for x in blocks:
            f.write(json.dumps(x) + "\n")
    return p


def bash(cmd):
    return {"type": "assistant", "message": {"content": [{"type": "tool_use", "name": "Bash", "input": {"command": cmd}}]}}


def judged(cmd):
    v, lg = b.isolation([transcript([bash(cmd)])], ["/src/repo", "SRCHOME/repo"], ["repo"])
    return ",".join(x[0] for x in v) + "|" + ",".join(x[0] for x in lg)


check(b.label("a1b2c3d → Tool: x"), "<sha> → Tool: x", "a label masks a sha")
check(b.label("the run in /tmp/tmp.Xy12Ab/home ok"), "the run in <tmp> ok", "…and a temp path")
check(b.label("claude's pid (46086) at 17:06"), "claude's pid (<n>) at <time>", "…and a pid and a clock time")
check(judged("cat > x.py <<'EOF'\nprint('open it with: gh pr create')\nEOF\npython3 x.py"), "|",
      "gh inside a heredoc body is code being written, no call")
check(judged("cd x && gh pr view 53"), "gh|", "gh at command position voids")
check(judged("cat SRCHOME/repo/bin/tool | head"), "source-read|", "a reader naming the source checkout voids")
check(judged("git -C /src/repo log -3"), "source-read|", "…a git read there too")
check(judged("python3 - <<'EOF'\nprint(open('/src/repo/x').read())\nEOF"), "source-read|", "…and a heredoc that opens a file there")
check(judged("python3 bin/tool check SRCHOME/repo > o.txt; grep -c x o.txt"), "|source-tool",
      "a tool run over the source checkout is logged")
check(judged("git push -u origin x; git ls-remote origin"), "|git-net", "a git call with no remote to reach is logged")
check(judged("git clone https://github.com/o/repo.git /tmp/r"), "git-net|", "a clone of the source repo voids")
check(judged("git fetch -q https://github.com/o/other.git main"), "|git-net", "…another repo's fetch is logged")
check(judged("curl -s https://api.github.com/repos/o/repo"), "net|", "…a curl naming the source repo voids")
a = {"type": "assistant", "requestId": "r1",
     "message": {"model": "claude-sonnet-5-5", "usage": {"input_tokens": 2, "output_tokens": 4, "cache_read_input_tokens": 10925,
                 "cache_creation": {"ephemeral_1h_input_tokens": 28877}}}}
early = json.loads(json.dumps(a))
early["message"]["usage"]["output_tokens"] = 1
synth = {"type": "assistant", "requestId": "r2", "message": {"model": "<synthetic>", "usage": {"output_tokens": 0}}}
p = transcript([early, a, synth], "c.jsonl")
check(b.cost([p]), (0.1166, 1), "cost: one call per request, its fullest copy, synthetic skipped")
aware, blind, models = b.cost_detail([p])
check((blind, models), (0.0796, {"claude-sonnet-5-5": 1}), "…cache-blind prices every input token as input")
res = os.path.join(T, "results.jsonl")
with open(res, "w") as f:
    f.write(json.dumps({"session": "s1", "cost_list": 2.5}) + "\n")
with open(res + ".started", "w") as f:
    f.write("s1\nno-such-session\n")
check(b.ledger(res, [p])["total"], 2.62, "the ledger: rows, a started run without a row, the caller")
sys.exit(1 if fails else 0)
