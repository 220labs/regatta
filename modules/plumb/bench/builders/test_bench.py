#!/usr/bin/env python3
"""bench's pure parts: case labels, the isolation rule, cost from a transcript, the ledger.
Exit 0 when every case passes; one line per case."""
import importlib.machinery
import importlib.util
import json
import os
import sys
import time
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

# --- the tether ----------------------------------------------------------------------------------
# the running session's own ids would leak into every case below (AGENTS.md's trap)
for k in ("CLAUDE_CODE_SESSION_ID", "CLAUDE_PID"):
    os.environ.pop(k, None)
real_ps = b.ps_row
me = real_ps(os.getpid())
check((me is not None and me[0] == os.getppid(), len((me or (0, ""))[1].split())), (True, 5),
      "ps_row reads a live process: its parent and a five-word start time")
check(real_ps(2 ** 22 + 12345), None, "…and None for a pid nobody holds")
_lc = os.environ.get("LC_ALL")
os.environ["LC_ALL"] = "ja_JP.UTF-8"
check(len((real_ps(os.getpid()) or (0, ""))[1].split()), 5, "…in any locale: ps is read under LC_ALL=C")
if _lc is None:
    os.environ.pop("LC_ALL")
else:
    os.environ["LC_ALL"] = _lc
PS = {}
b.ps_row = lambda pid: PS.get(pid)
S1, S2 = "Mon Oct 26 09:00:00 2026", "Tue Oct 27 03:00:00 2026"
PS.update({500: (400, S1, "python3"), 400: (300, S1, "/bin/zsh"), 300: (200, S1, "/opt/tools/bin/claude"),
           200: (1, S1, "claude-host")})
check(b.claude_above(500), (300, S1), "the walk up finds the first claude above")
PS[300] = (200, S1, "/bin/sh")
check(b.claude_above(500), (None, None), "…and none when no claude is above")
PS[300] = (200, S1, "/opt/tools/bin/claude")
os.environ["CLAUDE_PID"], os.environ["CLAUDE_CODE_SESSION_ID"] = "300", "s-test"
t = b.tether(None)
check((t["session"], t["pid"], t["start"]), ("s-test", 300, S1), "CLAUDE_PID names the session's claude, walk or not")
os.environ["CLAUDE_PID"] = "400"
PS[os.getpid()] = (500, S1, "python3")
check(b.tether(None)["pid"], 300, "…a CLAUDE_PID that is no claude falls back to the walk")
for k in ("CLAUDE_CODE_SESSION_ID", "CLAUDE_PID"):
    os.environ.pop(k, None)
del PS[300]
check(b.tether(None), {"session": None, "pid": None, "start": None, "until": None},
      "run by hand: no session, no claude, no deadline")
check(b.tether_stop({"pid": None, "until": None}), None, "…and so no session stop: today's behaviour")
PS[300] = (200, S1, "/opt/tools/bin/claude")
t = {"session": "s-test", "pid": 300, "start": S1, "until": None}
check(b.tether_stop(t), None, "the session's claude alive: keep going")
del PS[300]
check(b.tether_stop(t), "session s-test is gone (its claude, pid 300, ended)", "its claude gone: stop")
PS[300] = (1, S2, "/opt/tools/bin/claude")
check((b.tether_stop(t) or "").startswith("session s-test is gone"), True, "…a pid reused since (another start): stop")
check((b.tether_stop({"pid": None, "until": 1000.0}, now=1000.0) or "").startswith("the deadline"), True,
      "--until reached: stop")
check(b.tether_stop({"pid": None, "until": 1000.0}, now=999.0), None, "…not yet: keep going")
check(b.until_arg("1767225600"), 1767225600.0, "--until takes an epoch")
check(b.until_arg("2026-01-01T00:00:00Z"), 1767225600.0, "…or an ISO time")
bad = []
for v in ("nan", "inf", "1e20", "1767225600000", "-5", "tomorrow"):
    try:
        b.until_arg(v)
    except b.argparse.ArgumentTypeError:
        bad.append(v)
check(bad, ["nan", "inf", "1e20", "1767225600000", "-5", "tomorrow"],
      "…and refuses nan, inf, a millisecond epoch, a negative one and words")

# --- the login's ceiling -------------------------------------------------------------------------
HOME_A, HOME_B = os.path.join(T, "home-a"), os.path.join(T, "home-b")
os.makedirs(HOME_A)
os.makedirs(HOME_B)


NOW = time.time()


def row(home, label, why, enabled=True, locked=(), lim=True, eligible=None, sampled=None):
    # the shape `account limits --json` prints: eligible and sampled beside why
    return {"label": label, "home": home, "enabled": enabled, "why": why,
            "eligible": why.startswith("week ") and "≥" not in why if eligible is None else eligible,
            "sampled": NOW - 60 if sampled is None else sampled,
            "limits": {"locked": list(locked), "seven_day": 50} if lim else None}


ok_b = row(HOME_B, "acct-b", "week 13% < 70% (week ceiling), 5h 20% ≤ 50%")
past_a = row(HOME_A, "acct-a", "week 98% ≥ 70% (week ceiling); resets Fri 01:00")
check(b.login_verdict([past_a, ok_b], HOME_B), (None, None), "the login matched by home, not the first row past its ceiling")
check(b.login_verdict([ok_b, past_a], HOME_A + "/"),
      ("login acct-a is past its week ceiling: week 98% ≥ 70% (week ceiling); resets Fri 01:00", None),
      "past its week ceiling: stop")
check(b.login_verdict([row(HOME_A, "acct-a", "parked (enabled: false)", enabled=False)], HOME_A),
      ("login acct-a is parked", None), "parked: stop")
check(b.login_verdict([row(HOME_A, "acct-a", "cooling down until Fri 01:00 (a window locked)", locked=["seven_day"])], HOME_A),
      ("login acct-a is locked (seven_day)", None), "locked: stop")
check(b.login_verdict([row(HOME_A, "acct-a", "5h 60% > 50%; resets 04:00")], HOME_A), (None, None),
      "a 5-hour window over its line is no stop: it resets within hours")
check(b.login_verdict([ok_b], HOME_A), (None, "no account row has the home %s" % HOME_A), "no row for the login: could not tell")
check(b.login_verdict([row(HOME_A, "acct-a", "limits unknown (no probe answered, none cached)", lim=False)], HOME_A),
      (None, "login acct-a has no cached limits"), "…nor a row with no limits")
over = "extra usage on: work here may bill past the plan (account pick --allow-overage, attended only)"
check(b.login_verdict([row(HOME_A, "acct-a", over)], HOME_A), ("login acct-a may not run: " + over, None),
      "paid overage on: stop, though why never states the week")
same = "same login as acct-b, so its limits are acct-b's"
check(b.login_verdict([row(HOME_A, "acct-a", same)], HOME_A)[0], "login acct-a may not run: " + same,
      "…a same_as login too")
check(b.login_verdict([row(HOME_A, "acct-a", "limits unknown (no window figures)")], HOME_A),
      (None, "login acct-a: limits unknown (no window figures)"), "no window figures: could not tell, said so")
check(b.login_verdict([row(HOME_A, "acct-a", "week 13% < 70% (week ceiling), 5h 20% ≤ 50%",
                           sampled=NOW - 7 * 3600)], HOME_A),
      (None, "login acct-a: its reading is 7 h old"), "a reading hours old: could not tell")
check(b.login_verdict([row(HOME_A, "acct-a", "week 13% < 70% (week ceiling), 5h 20% ≤ 50%"),
                       row(HOME_A, "acct-a2", "parked (enabled: false)", enabled=False)], HOME_A),
      ("login acct-a2 is parked", None), "two rows on one home: a stop in either stops")
fake = os.path.join(T, "account")
with open(fake, "w") as f:
    f.write("#!/bin/sh\n[ \"$*\" = 'limits --all --parked --json --cached' ] || exit 9\nprintf '%%s\\n' '%s'\n"
            % json.dumps([ok_b, past_a]))
os.chmod(fake, 0o755)
b.account_tool = lambda: fake
check(b.account_rows(), ([ok_b, past_a], None), "account_rows asks the cached limits of every row, parked too")
with open(fake, "w") as f:
    f.write("#!/bin/sh\necho 'no registry' >&2\nexit 1\n")
check(b.account_rows(), (None, "account limits exited 1: no registry"), "…a failing tool: could not tell")
b.account_tool = lambda: None
check(b.account_rows(), (None, "lighthouse's account tool is absent"), "…an absent tool too")

# --- the driver stops on each, and says why ------------------------------------------------------
plan = os.path.join(T, "plan.json")
with open(plan, "w") as f:
    json.dump([["tasks/x.json", "sonnet:high", 1], ["tasks/x.json", "sonnet:high", 2]], f)


def drive(name, *extra):
    work = os.path.join(T, name)
    os.makedirs(work)
    rc = b.main(["drive", plan, "--work", work, "--out", os.path.join(work, "results.jsonl"), "--stagger", "0"]
                + list(extra))
    lines = [x.split(" ", 1)[1].rstrip("\n") for x in open(os.path.join(work, "drive.log"))]
    return rc, [x for x in lines if not x.startswith("tethered") and not x.startswith("untethered")]


calls = []
b.login_stop = lambda: (calls.append(1), (None, None))[1]
gone = iter([(200, S1, "/opt/tools/bin/claude")])   # alive at start, gone at the first start
b.ps_row = lambda pid: next(gone, None) if pid == 300 else None
os.environ["CLAUDE_PID"], os.environ["CLAUDE_CODE_SESSION_ID"] = "300", "s-test"
check(drive("d1"), (0, ["STOP: session s-test is gone (its claude, pid 300, ended); 2 not started",
                        "DONE 0 rows; stopped: session s-test is gone (its claude, pid 300, ended)"]),
      "drive: the session gone, nothing starts, exit 0, one line naming why")
check(calls, [], "…and the login is not asked once the session stopped it")
for k in ("CLAUDE_CODE_SESSION_ID", "CLAUDE_PID"):
    os.environ.pop(k, None)
b.login_stop = lambda: ("login acct-a is past its week ceiling: week 98% ≥ 70%", None)
check(drive("d2"), (0, ["STOP: login acct-a is past its week ceiling: week 98% ≥ 70%; 2 not started",
                        "DONE 0 rows; stopped: login acct-a is past its week ceiling: week 98% ≥ 70%"]),
      "drive: the login past its ceiling stops it")
b.login_stop = lambda: (None, "lighthouse's account tool is absent")
rc, lines = drive("d3", "--stop", "0")
check((rc, lines[0], lines[1].startswith("STOP: ledger $0.00 past the stop line")),
      (0, "login: could not tell (lighthouse's account tool is absent); the ledger's --stop still holds", True),
      "drive: a login it cannot tell is logged, and the ledger still stops it")
rc, lines = drive("d4", "--until", "2000-01-01T00:00:00")
check((rc, lines[0][:32]), (0, "STOP: the deadline 2000-01-01 00"), "drive: --until passed stops it")
# a row already running finishes after a stop: the first start goes ahead, the login stops the second
verdicts = iter([(None, None)])
b.login_stop = lambda: next(verdicts, ("login acct-a is parked", None))
real_popen = b.subprocess.Popen
b.subprocess.Popen = lambda *a, **k: real_popen(["sleep", "1"])
try:
    rc, lines = drive("d5", "--parallel", "1")
finally:
    b.subprocess.Popen = real_popen
check((rc, [x for x in lines if x.startswith("STOP:")], any(x.startswith("ended ") for x in lines)),
      (0, ["STOP: login acct-a is parked; 1 not started"], True),
      "drive: a stop lets the running row end, starts no other, exit 0")
sys.exit(1 if fails else 0)
