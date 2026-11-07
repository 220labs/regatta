#!/usr/bin/env python3
"""stuck-ships S1's cases for autofinish-run's lander: the roads and their refusals, the caps in lander.json, the mode
flag, the resets. test_lander.sh builds the scratch repo, HOME and config dir, then runs this:

    python3 lander_cases.py <bin dir> <worktree> <primary> <scratch dir>

GitHub, the account tool, keel and dispatch's verdict are stood in for in-process; git and the store are real.
Prints one `ok`/`FAIL` line per case and exits with the failures' count (capped at 1)."""
import argparse
import datetime
import importlib.machinery
import io
import json
import os
import subprocess
import sys
import time
import uuid
from contextlib import redirect_stderr, redirect_stdout

B, W, R, T = sys.argv[1:5]
# a case run outside test_lander.sh would delete this Mac's lander.json and write its day log (AGENTS.md's trap)
for _v in ("HOME", "AUTOFINISH_STATE_DIR"):
    if not os.path.realpath(os.environ.get(_v) or "/").startswith(os.path.realpath(T) + os.sep):
        sys.exit("lander_cases.py: %s is not under the suite's scratch %s — run it through test_lander.sh" % (_v, T))
m = importlib.machinery.SourceFileLoader("afr_lander", os.path.join(B, "autofinish-run")).load_module()
fails = 0


def check(got, want, label):
    global fails
    if got == want:
        print("  ok   %s" % label)
    else:
        print("  FAIL %s: expected [%s] got [%s]" % (label, want, got))
        fails += 1


def git(where, *a):
    return subprocess.run(["git", "-C", where] + list(a), capture_output=True, text=True, check=True).stdout.strip()


def head():
    return git(W, "rev-parse", "HEAD")


def origin_main():
    return git(R, "ls-remote", "origin", "refs/heads/main").split()[0]


def advance_main(msg):
    """A commit on main, published to origin as a merge elsewhere would leave it (no push verb in the suite's text)."""
    git(R, "commit", "-q", "--allow-empty", "-m", msg)
    subprocess.run(["git", "-C", R, "send-pack", os.path.join(T, "origin.git"), "main:refs/heads/main"],
                   capture_output=True, check=True)
    git(R, "update-ref", "refs/remotes/origin/main", "main")


def iso(ago=0):
    return datetime.datetime.fromtimestamp(time.time() - ago).astimezone().isoformat(timespec="seconds")


def tree():
    return m.Tree(W)


def set_prev(**kw):
    """The worktree's last run, ended unless a case says otherwise."""
    st = {"started": iso(3600), "session": str(uuid.uuid4()), "tip": head(), "by": "sweep", "rule": "A",
          "window": "finish · lander", "account": "acct-pro", "ended": iso(60), "outcome": "stopped", "pr": 7,
          "gate": "G4", "base": "main", "base_tip": origin_main()}
    st.update(kw)
    m.write_state(tree(), st)
    return st


def set_last(gate, text, ts=None):
    """The stop's own `autofinished` line, stamped with the worktree's last run's `ended` (as record() writes it), or
    TS: a road reads its stop's own line only (stop_line)."""
    t = tree()
    os.makedirs(os.path.join(t.common, "claude"), exist_ok=True)
    ts = ts or (m.read_state(t) or {}).get("ended") or "2000-01-01T00:00:00+00:00"
    with open(os.path.join(t.common, "claude", "autofinished"), "a") as f:
        f.write("%s stopped %s %s %s\n" % (ts, t.branch, gate, text))


def store():
    try:
        with open(m.lander_path()) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def entry():
    t = tree()
    return store().get(m.lander_key(t.primary, t.branch)) or {}


def clear_store():
    for p in (str(m.lander_path()),):
        try:
            os.remove(p)
        except OSError:
            pass


def judge(by, road=None):
    """(rc, text) of refusal() for the worktree as it stands: rc 0 when it would start."""
    t = tree()
    why = m.refusal(t, m.read_state(t), by, road=road)
    return (getattr(why, "rc", 3), str(why)) if why else (0, "")


# GitHub: one open PR, #7, whose fields a case sets
PR = {}


def api(method, path, body=None, tok=None, timeout=15):
    if method == "GET" and path.endswith("/pulls/7") and PR:
        return 200, dict(PR, number=7)
    return 404, None


m.common.api = api
m.common.find_pr = lambda slug, branch, tok=None: dict(PR, number=7) if PR else None   # the list's row carries auto_merge


def pr(state="dirty", sha=None, draft=False, auto_merge=None, labels=()):
    PR.clear()
    PR.update(mergeable_state=state, head={"sha": sha or head()}, draft=draft, auto_merge=auto_merge,
              labels=[{"name": n} for n in labels] if labels is not None else None)


class FakeAf:
    """bin/autofinish's ladder, stood in: a mode, and a held slice that holds whatever it is asked."""

    def __init__(self, mode=None, unread=False, handed=None):
        self.mode, self.unread, self.handed = mode, unread, handed
        self.asked = []

    def landing_mode(self, branch, primary=None):
        return self.mode, ("helm did not load" if self.unread else None)

    def mode_unreadable(self, why):
        return self.unread

    def effective_mode(self, by, mode, **kw):
        return mode or by

    def held_slice(self, *a):
        return "a held path (.claude/workflow.json; the autofinish_exclude list)"

    def brief_held(self, *a):
        return None

    def handed_held(self, *a, **kw):
        self.asked.append("handed_held")
        return self.handed

    def memo_status(self, *a):
        return None   # keel could not say: the stand road waits


REAL_LANDER = m._lander
m._lander = lambda: FakeAf()
CALLS = []
real_start_cmd = m.start_cmd


def start_cmd(*a, **kw):
    cmd = real_start_cmd(*a, **kw)
    CALLS.append(cmd)
    return cmd


m.start_cmd = start_cmd
m.account_pick = lambda t, cached=False: ("acct-new", None, "the stub's pick")
m.end_warm = lambda t, args, cap=None: None
m.draw_arm = lambda t: (None, "rotation off: no %s" % m.ROTATION_KEY)
m.open_sessions = lambda *a, **k: []
# Main's exec'd waiter passes (waiter, t, args, out_path); this pre-rebase copy passes (fn, out_path).
# Keep both call shapes harmless while these cases travel through the landing's rebase.
m.detach = lambda waiter, t, args=None, out_path=None: None
VERDICT = ["started"]
m.await_verdict = lambda t, sid, log_from, bound: (VERDICT[0], "the stub's verdict")


def start(by, road=None, verdict="started", merge=False, run_session=None):
    """start() as run_main calls it, dispatch's verdict stood in: (rc, stderr)."""
    VERDICT[0] = verdict
    args = argparse.Namespace(by=by, road=road, rule="C", merge=merge, hold=False, digest=None, session=None, on="here",
                              priority=None, run_session=run_session, bundle=None, ticket=None, sent_from=None, dry=False,
                              queue=None, job=None, sent=False)
    t = tree()
    t.shipped, t.stay, t.budget, t.deadline, t.reserve = None, None, 100, time.time() + 100, 5
    try:
        os.remove(os.path.join(t.state_dir, "owner.json"))
    except OSError:
        pass
    err = io.StringIO()
    with redirect_stdout(io.StringIO()), redirect_stderr(err):
        rc = m.start(t, args)
    return rc, err.getvalue()


def state():
    return m.read_state(tree())


def end_run(**kw):
    """The run start() wrote, ended as its waiter would: a stop on that tip."""
    st = state()
    st.update(dict({"ended": iso(), "outcome": "stopped", "gate": "no-landing", "base": "main",
                    "base_tip": st.get("base_tip") or origin_main()}, **kw))
    m.write_state(tree(), st)


def day_log():
    try:
        with open(os.path.join(m.LOGS, "autofinish-%s.log" % m.log_day())) as f:
            return f.read()
    except OSError:
        return ""


print("the refinish road (a): a DIRTY PR after main moved, on this worktree's HEAD")
clear_store()
base = origin_main()
set_prev(outcome="launched", gate=None, base_tip=base)
pr("dirty")
check(judge("lander", "refinish")[0], 3, "main unmoved since the run: the road waits (exit 3)")
check("has not moved" in judge("lander", "refinish")[1], True, "  saying main has not moved")
for by in ("sweep", "override", "typed", "chain"):
    check(judge(by)[0], 3, "  and every other by is refused on that tip (%s)" % by)
advance_main("main moves")
check(judge("lander", "refinish"), (0, ""), "main moved: the refinish road starts on the same tip")
check(judge("sweep")[0], 3, "  while the same-tip rule still refuses a sweep")
check(getattr(m.refusal(tree(), state(), "sweep"), "same_tip", False), True, "  a refusal marked same-tip")
set_prev(outcome="stopped", gate="no-landing", base_tip=base)
check(judge("lander", "refinish")[0], 0, "a no-landing stop with a ready PR: taken")
pr("dirty", draft=True)
check(judge("lander", "refinish")[0], 3, "  a draft PR: not")
pr("dirty")
set_prev(outcome="stopped", gate="G11", base_tip=base)
check(judge("lander", "refinish")[0], 0, "a G11 stop: taken")
for g in ("G1r", "G4", "held", "G1"):
    set_prev(outcome="stopped", gate=g, base_tip=base)
    check(judge("lander", "refinish")[0], 3, "a %s stop: not the refinish road's" % g)
set_prev(outcome="launched", gate=None, base_tip=None)
check(judge("lander", "refinish")[0], 0, "a record with no base_tip (a failed ls-remote, a pre-S1 run): main read from git")
set_prev(outcome="launched", gate=None, base_tip=origin_main())
check(judge("lander", "refinish")[0], 0, "a base_tip equal to main now (a conflict landed mid-run): main is past HEAD")
pr("dirty", labels=["hold"])
r = judge("lander", "refinish")
check(r[0], m.DEAD_ROAD_RC, "a PR labelled hold: never re-finished, the owner's (DEAD_ROAD_RC)")
check("labelled `hold`" in r[1], True, "  saying so")
pr("dirty", labels=["lander-hold"])
check(judge("lander", "refinish")[0], 0, "  the lander's own lander-hold label is no such hold")
pr("dirty", labels=None)
check(judge("lander", "refinish")[0], 3, "labels that do not read: the road waits")
set_prev(outcome="stopped", gate="G11", base_tip=base)
pr("dirty", draft=True)
check(judge("lander", "refinish")[0], 3, "a G11 stop's draft PR: not re-finished")
pr("dirty", draft=None)
check(judge("lander", "refinish")[0], 3, "  nor one whose draft flag did not read")
pr("dirty")
set_prev(outcome="launched", gate=None, base_tip=base, pushed="1" * 40)
r = judge("lander", "refinish")
check(r[0], 3, "HEAD past the tip its run pushed: not the refinish road's")
check("the work since is the sweep's" in r[1], True, "  saying whose it is")
set_prev(outcome="launched", gate=None, base_tip=base, pushed=head())
check(judge("lander", "refinish")[0], 0, "HEAD the tip its run pushed: taken")
set_prev(outcome="launched", gate=None, base_tip=base)
pr("dirty", sha="0" * 40)
r = judge("lander", "refinish")
check(r[0], 3, "a DIRTY PR whose head is not this worktree's HEAD: skipped")
check("another Mac's" in r[1], True, "  as another Mac's")
pr("clean")
check(judge("lander", "refinish")[0], 3, "a PR that is not DIRTY: not re-finished")
pr("dirty")
prev_tip = head()
git(W, "commit", "-q", "--allow-empty", "-m", "a curation rewrote HEAD")
set_prev(outcome="stopped", gate="G1r", tip=prev_tip)
check(judge("sweep"), (0, ""), "a rewritten HEAD is not refused by the same-tip test")

print("a DIRTY re-finish spends a re-finish whatever HEAD did; the third is refused STUCK_RC")
clear_store()
set_prev(outcome="launched", gate=None, base_tip=base)
pr("dirty")
check(start("lander", "refinish")[0], 0, "the first re-finish starts")
check(entry().get("refinishes"), 1, "  and spends one")
check(state().get("by"), "lander", "  recorded by lander")
git(W, "merge", "-q", "--no-edit", "refs/remotes/origin/main")   # the re-finish's rebase: main is in HEAD now
pr("dirty")
end_run(gate="G11", pushed=head())   # the tip its push sent, read back at its end (landing_fields)
check(judge("lander", "refinish")[0], 3, "  the next waits until main moves past HEAD again")
advance_main("main moves under the re-finished PR")
pr("dirty")
check(start("lander", "refinish")[0], 0, "a second on a moved HEAD starts")
check(entry().get("refinishes"), 2, "  and spends the second")
end_run(gate="G11", pushed=head())
advance_main("and again")
pr("dirty")
rc, err = start("lander", "refinish")
check(rc, m.STUCK_RC, "the third is refused STUCK_RC")
check("refinish road is spent" in err, True, "  naming the spent road")
check(entry().get("refinishes"), 2, "  spending nothing")
has = day_log()
check(" road=refinish stopped_on=" in has, True, "the start line names the road and the stopped run's login")
check(" account=acct-new " in has, True, "  beside account=, the new pick")
check(" by=lander via=" in has, True, "  by=lander, via the stopped run's by")

print("a start dispatch refused spends nothing; an unconfirmed one spends")
clear_store()
advance_main("main moves again")
set_prev(outcome="launched", gate=None, base_tip=base)
pr("dirty")
check(start("lander", "refinish", verdict="refused")[0], m.REFUSED_RC, "dispatch refused the start (no room): exit 5")
check(entry().get("refinishes", 0), 0, "  no re-finish spent")
# the waiter's record of a refused start, as record() writes it: no base_tip, the new pick's account, its own start
real_read_outcome = m.read_outcome
m.read_outcome = lambda t, sid, log_from: ("never-started", None, "refused", ["FAILED: no room on this host"])
with redirect_stdout(io.StringIO()):
    m.record(tree(), dict(state()), 0, 5, None, [])
m.read_outcome = real_read_outcome
check((state().get("gate"), state().get("base_tip"), state().get("account")), ("refused", None, "acct-new"),
      "  the waiter recorded the refused start (no base_tip, the new pick)")
check(judge("lander", "refinish"), (0, ""), "  and the road judges the stop it passed on, not that record: it starts")
check(start("lander", "refinish")[0], 0, "  the retry starts")
has = day_log().splitlines()[-1]
check("road=refinish stopped_on=acct-pro" in has, True, "  stopped_on names the stop's login, never the refused pick's")
check(" via=launched" in has or " via=sweep" in has, True, "  via the stop's by")
check(entry().get("refinishes"), 1, "  one re-finish spent")
end_run(gate="G11")
clear_store()
advance_main("main moves for the no-account case")
set_prev(outcome="launched", gate=None, base_tip=base)
real_pick = m.account_pick


NOACC = [40]


def no_account(t, cached=False):
    NOACC[0] += 1   # pick's reasons quote a pace that moves every tick
    raise m.NoAccount("acct-pro: cooling down; 5h %d%% > 80%%, over pace %d%%" % (NOACC[0] + 40, NOACC[0]))


m.account_pick = no_account
check(start("lander", "refinish")[0], 3, "no account for it: refused before any write (exit 3)")
check(entry().get("refinishes", 0), 0, "  no re-finish spent")
m.account_pick = real_pick


class Killed(BaseException):
    pass


def killed(*a):
    raise Killed()


m.await_verdict = killed
try:
    start("lander", "refinish")
except Killed:
    pass
m.await_verdict = lambda t, sid, log_from, bound: (VERDICT[0], "the stub's verdict")
check(entry().get("refinishes"), 1, "a caller killed during the verdict wait leaves the road spent (spent before the detach)")
end_run(gate="G11")
clear_store()
advance_main("main moves for the queued case")
set_prev(outcome="launched", gate=None, base_tip=base)
# finish-as-task: a finish queued in the fleet writes nothing here and spends at its claim's start (test_finish_queue.sh's
# lander cases); dispatch --start says no `queued` any more, so the verdicts left are started, refused and unconfirmed
check(start("lander", "refinish", verdict="unconfirmed")[0], 0, "an unconfirmed re-finish (exit 0: it may be going)…")
check(entry().get("refinishes"), 1, "  spends its road: the run may be going")
r = judge("lander", "refinish")
check(r[0], 3, "  the next tick's road waits (exit 3) while that run has not ended…")
check("has not ended" in r[1], True, "  …never answered by the cap")
end_run(gate="G11")
advance_main("main moves once more")
check(start("lander", "refinish")[0], 0, "a started one…")
check(entry().get("refinishes"), 2, "  spends its road too")
r = judge("lander", "refinish")
check(r[0], 3, "  and a run not ended waits before the spent cap is read")
end_run(gate="G11")
advance_main("main moves past it")
check(judge("lander", "refinish")[0], m.STUCK_RC, "  once it ended, the spent cap: STUCK_RC")

print("the login road (b): the stop's class, never the logged-out row")
clear_store()
acct_home = os.path.join(T, "acct-pro-home")
os.makedirs(acct_home, exist_ok=True)
lo_calls = os.path.join(T, "logged-out.calls")
stub = os.path.join(T, "account-stub")
with open(stub, "w") as f:
    f.write("#!/bin/sh\n"
            "if [ \"$*\" = 'limits --all --parked --json --cached' ]; then\n"
            "  printf '%%s\\n' '[{\"label\": \"acct-pro\", \"home\": \"%s\"}, "
            "{\"label\": \"acct spaced\", \"home\": \"%s\"}]'\n"
            "  exit 0\n"
            "fi\n"
            "if [ \"$1\" = 'logged-out' ] && [ \"$2\" = '--set' ] && [ $# -eq 3 ] && [ -n \"$3\" ]; then\n"
            "  printf '%%s\\n' \"$3\" >> '%s'\n"
            "  exit 0\n"
            "fi\n"
            "echo \"account: bad call: $*\" >&2; exit 2\n" % (acct_home, acct_home, lo_calls))
os.chmod(stub, 0o755)
m.ACCOUNT = stub
real_ro, real_comment = m.read_outcome, m.comment
try:
    m.comment = lambda *a: (None, "")
    m.read_outcome = lambda t, sid, lf: ("stopped", None, "no-landing", ["Not logged in · Please run /login"])
    st_rec = set_prev(outcome=None, ended=None, gate=None, account="acct-pro")
    with redirect_stdout(io.StringIO()):
        m.record(tree(), st_rec, 0, 0, None, [])
    check(open(lo_calls).read().splitlines() if os.path.exists(lo_calls) else [], ["acct-pro"],
          "record() marks a login stop's registry login logged-out (account logged-out --set)")
    st_tok = set_prev(outcome=None, ended=None, gate=None, account="oauth-token")
    with redirect_stdout(io.StringIO()):
        m.record(tree(), st_tok, 0, 0, None, [])
    m.read_outcome = lambda t, sid, lf: ("stopped", None, "no-landing", ["API Error: 500 Internal server error"])
    st_net = set_prev(outcome=None, ended=None, gate=None, account="acct-pro")
    with redirect_stdout(io.StringIO()):
        m.record(tree(), st_net, 0, 0, None, [])
    check(open(lo_calls).read().splitlines(), ["acct-pro"],
          "  oauth-token and non-login stops leave logged-out untouched")
finally:
    m.read_outcome, m.comment = real_ro, real_comment
clear_store()
set_prev(outcome="stopped", gate="no-landing")
set_last("no-landing", "Not logged in · Please run /login")
check(judge("lander", "login"), (0, ""), "a login stop is lifted on the same tip (its row already cleared: no row read)")
check(start("lander", "login")[0], 0, "  started")
check(entry().get("relaunches", {}).get("login"), 1, "  one login relaunch spent")
end_run(gate="no-landing")
set_last("no-landing", "Not logged in · Please run /login")
check(judge("lander", "login")[0], m.STUCK_RC, "  a second: STUCK_RC")
clear_store()
set_last("no-landing", "API Error: 500 the server")
check(judge("lander", "login")[0], 3, "a network stop is no login road's")
set_last("G1", "⚠ step 1 — the /login route's test failed")
check(judge("lander", "login")[0], 3, "a G1 stop naming /login is no login road's (a no-landing stop only)")
check(judge("lander", "stand")[0], 3, "  nor the stand road's")

print("the limit road (c): any login with room (revision 10), one per login per 5h window (S2)")
clear_store()
ex = os.path.join(acct_home, "exhaustion.jsonl")
try:
    os.remove(ex)
except OSError:
    pass
# Revision 10(a): with another login (`acct-new`) having room, a limit stop migrates at once even with no exhaustion
# row, before the stopped login's reset, on a weekly limit, or from oauth-token / an unknown login; an Opus limit never does.
set_prev(outcome="stopped", gate="no-landing", account="acct-pro", started=iso(3600))
set_last("no-landing", "You've hit your 5-hour limit · resets 9pm")
check(judge("lander", "limit"), (0, ""), "another login (`acct-new`) has room: migrates with no exhaustion row")
set_last("no-landing", "You've hit your weekly limit · resets Mon 9am")
check(judge("lander", "limit"), (0, ""), "  weekly limit migrates to another login with room too")
set_prev(outcome="stopped", gate="no-landing", account="oauth-token", started=iso(3600))
set_last("no-landing", "You've hit your 5-hour limit · resets 9pm")
check(judge("lander", "limit"), (0, ""), "  a caller's token migrates to a registry login with room")
set_last("no-landing", "You've hit your Opus limit · resets 9pm")
check(judge("lander", "limit")[0], 3, "an Opus model limit is outside the limit road (exit 3, never DEAD_ROAD_RC)")

# When NO other login has room, the stopped login is eligible only once its recorded `resets_at` has passed;
# no login with room (or no exhaustion row) is always a plain wait (exit 3), never DEAD_ROAD_RC.
POOL = []


def pool_pick(t, cached=False, skip=()):
    sk = {m._norm_acct(s) for s in (skip or ())}
    for cand in POOL:
        if m._norm_acct(cand) not in sk:
            return cand, None, "pool picked %s" % cand
    raise m.NoAccount("no eligible login with room")


real_pick_stub = m.account_pick
real_limit_now = m.limit_now
m.account_pick = pool_pick
try:
    POOL[:] = ["acct-pro"]
    set_prev(outcome="stopped", gate="no-landing", account="acct-pro", started=iso(3600))
    set_last("no-landing", "You've hit your 5-hour limit · resets 9pm")
    r = judge("lander", "limit")
    check(r[0], 3, "no other login has room and acct-pro has no exhaustion row: plain wait (exit 3, never DEAD_ROAD_RC)")
    with open(ex, "w") as f:   # an older window's row (before the run) is not its own
        f.write(json.dumps({"at": time.time() - 9000, "window": "five_hour", "resets_at": time.time() - 5400}) + "\n")
    check(judge("lander", "limit")[0], 3, "  a row written before the run started is not its window's (exit 3)")
    with open(ex, "a") as f:
        f.write(json.dumps({"at": time.time() - 1800, "window": "five_hour", "resets_at": time.time() + 600}) + "\n")
    r = judge("lander", "limit")
    check((r[0], "resets at" in r[1]), (3, True), "  refused before its reset (exit 3, saying when)")
    with open(ex, "a") as f:
        f.write(json.dumps({"at": time.time() - 900, "window": "seven_day", "resets_at": time.time() + 86400}) + "\n")
        f.write(json.dumps({"at": time.time() - 600, "window": "five_hour", "resets_at": time.time() - 60}) + "\n")
    check(judge("lander", "limit"), (0, ""), "once acct-pro's newest five_hour row's reset passed: its own login is eligible")
    set_last("no-landing", "You've hit your weekly limit · resets Mon 9am")
    check(judge("lander", "limit")[0], 3, "  on a weekly limit, acct-pro waits for its seven_day reset even after five_hour passed")
    with open(ex, "a") as f:
        f.write(json.dumps({"at": time.time() - 300, "window": "seven_day", "resets_at": time.time() - 30}) + "\n")
    check(judge("lander", "limit"), (0, ""), "  once seven_day's reset passed, acct-pro is eligible on a weekly limit too")
    with open(ex, "w") as f:   # the window's one row, written by a probe before the run started; reset since
        f.write(json.dumps({"at": time.time() - 5400, "window": "five_hour", "resets_at": time.time() - 60}) + "\n")
    set_last("no-landing", "You've hit your 5-hour limit · resets 9pm")
    check(judge("lander", "limit"), (0, ""), "  a row written before the run, for the window it ran in, counts too")
    POOL[:] = []
    set_prev(outcome="stopped", gate="no-landing", account="acct-gone", started=iso(3600))
    set_last("no-landing", "You've hit your 5-hour limit · resets 9pm")
    check(judge("lander", "limit")[0], 3, "an unknown login with no other login having room: plain wait (exit 3)")
    set_prev(outcome="stopped", gate="no-landing", account="oauth-token", started=iso(3600))
    set_last("no-landing", "You've hit your 5-hour limit · resets 9pm")
    check(judge("lander", "limit")[0], 3, "  and a caller's token with no registry login having room: plain wait (exit 3)")
    POOL[:] = ["acct spaced"]
    with open(ex, "a") as f:
        f.write(json.dumps({"at": time.time() - 600, "window": "five_hour", "resets_at": time.time() - 60}) + "\n")
    set_prev(outcome="stopped", gate="no-landing", account="acct_spaced", started=iso(3600))
    set_last("no-landing", "You've hit your 5-hour limit · resets 9pm")
    check(judge("lander", "limit"), (0, ""), "a label with a space, as pick records it, is read")
    # an Orca profile's log holds another seat's rows copied in: only the login's own seat's rows judge (round 3)
    POOL[:] = ["acct-pro"]
    with open(os.path.join(acct_home, ".claude.json"), "w") as f:
        json.dump({"oauthAccount": {"accountUuid": "aaaaaaaa-1111", "organizationUuid": "oooooooo-2222"}}, f)
    with open(ex, "w") as f:
        f.write(json.dumps({"at": time.time() - 1200, "window": "five_hour", "resets_at": time.time() + 7200,
                            "account": "aaaaaaaa"}) + "\n")
        f.write(json.dumps({"at": time.time() - 600, "window": "five_hour", "resets_at": time.time() - 60,
                            "account": "bbbbbbbb"}) + "\n")
    set_prev(outcome="stopped", gate="no-landing", account="acct-pro", started=iso(3600))
    set_last("no-landing", "You've hit your 5-hour limit · resets 9pm")
    r = judge("lander", "limit")
    check((r[0], "resets at" in r[1]), (3, True), "a newer row of another seat (copied into the profile) never lifts the road: its own reset waits")
    os.remove(os.path.join(acct_home, ".claude.json"))

    # S2 & Revision 10(b): at most one road=limit relaunch per target login (`account=`) per 5-hour window.
    POOL[:] = ["acct-new", "acct-third"]
    clear_store()
    set_prev(outcome="stopped", gate="no-landing", account="acct-pro", started=iso(3600))
    set_last("no-landing", "You've hit your 5-hour limit · resets 9pm")
    check(start("lander", "limit")[0], 0, "first limit stop migrates onto acct-new")
    check(state().get("account"), "acct-new", "  recorded on acct-new")
    end_run(gate="no-landing", account="acct-new")
    set_last("no-landing", "You've hit your 5-hour limit · resets 2am")
    check(judge("lander", "limit")[0], m.STUCK_RC, "  a second limit relaunch on the same branch: STUCK_RC")
    clear_store()   # simulate a second stopped branch in the same 5-hour window, also stopped_on=acct-pro
    set_prev(outcome="stopped", gate="no-landing", account="acct-pro", started=iso(3600))
    set_last("no-landing", "You've hit your 5-hour limit · resets 9pm")
    check(start("lander", "limit")[0], 0, "second branch in the window skips spent acct-new and migrates onto acct-third")
    check(state().get("account"), "acct-third", "  landed on acct-third (read on account=, not stopped_on=acct-pro)")
    clear_store()   # a third stopped branch in the same window finds both acct-new and acct-third spent
    set_prev(outcome="stopped", gate="no-landing", account="acct-pro", started=iso(3600))
    set_last("no-landing", "You've hit your 5-hour limit · resets 9pm")
    r = judge("lander", "limit")
    check(r[0], 3, "third branch waits (exit 3) when every login with room already took one limit relaunch in this window")

    # Revision 10(b) explicit check: stopped_on=acct-new does NOT spend acct-new; never-started does NOT spend acct-new;
    # and the 5-hour window spans midnight across two autofinish-<date>.log files.
    for fn in os.listdir(m.LOGS):
        if fn.startswith("autofinish-") and fn.endswith(".log"):
            os.remove(os.path.join(m.LOGS, fn))
    POOL[:] = ["acct-new"]
    d1 = datetime.datetime(2026, 11, 1, 23, 30, 0).astimezone()
    d2 = datetime.datetime(2026, 11, 2, 1, 30, 0).astimezone()
    m.limit_now = lambda: d2.timestamp()
    log_d1 = os.path.join(m.LOGS, "autofinish-2026-11-01.log")
    log_d2 = os.path.join(m.LOGS, "autofinish-2026-11-02.log")
    with open(log_d1, "w") as f:
        # stopped_on=acct-new landing on acct-other does not spend acct-new
        f.write("%s run repo b1 started session=11111111 tip=abc1234 rule=C by=lander via=sweep road=limit "
                "stopped_on=acct-new account=acct-other window=\"w\" — picked\n" % d1.isoformat(timespec="seconds"))
        # never-started session on acct-new does not spend acct-new
        f.write("%s run repo b2 started session=22222222 tip=abc1234 rule=C by=lander via=sweep road=limit "
                "stopped_on=acct-pro account=acct-new window=\"w\" — picked\n" % d1.isoformat(timespec="seconds"))
    with open(log_d2, "w") as f:
        f.write("%s run repo b2 never-started gate=refused session=22222222 tip=abc1234 rule=C by=lander — refused\n"
                % d2.isoformat(timespec="seconds"))
    check(judge("lander", "limit"), (0, ""),
          "stopped_on=acct-new (account=acct-other) and never-started leave acct-new's window unspent")
    with open(log_d1, "a") as f:
        f.write("%s run repo b3 started session=33333333 tip=abc1234 rule=C by=lander via=sweep road=limit "
                "stopped_on=acct-pro account=acct-new window=\"w\" — picked\n" % d1.isoformat(timespec="seconds"))
    check(judge("lander", "limit")[0], 3,
          "a started road=limit line at 23:30 in yesterday's log spends acct-new's window at 01:30 across midnight")
finally:
    m.account_pick = real_pick_stub
    m.limit_now = real_limit_now
    for fn in os.listdir(m.LOGS) if os.path.isdir(m.LOGS) else ():
        if fn.startswith("autofinish-") and fn.endswith(".log"):
            os.remove(os.path.join(m.LOGS, fn))

print("the stand road (d): a G4 stop whose items stood")
clear_store()
doc = os.path.join(W, "docs", "design.md")
os.makedirs(os.path.dirname(doc), exist_ok=True)
with open(doc, "w") as f:
    f.write("# A design\n\n1. **D1 — which way**\n  - A — this\n\n  Reversible: yes\n\n  ➤ Answer:\n")
git(W, "add", "docs/design.md")
git(W, "commit", "-q", "-m", "the design")
memo = os.path.join(T, "memo-stub")
open_n = os.path.join(T, "memo-open")
verdict_f = os.path.join(T, "memo-verdict")
with open(verdict_f, "w") as f:
    f.write("due")
with open(memo, "w") as f:
    f.write("#!/bin/sh\n[ \"$1 $2 $3\" = 'status --json --no-fetch' ] && [ $# -eq 4 ] && [ -f \"$4\" ] "
            "|| { echo \"keel: bad call: $*\" >&2; exit 2; }\n"
            "printf '{\"verdict\": \"%%s\", \"items\": 1, \"unanswered\": %%s}\\n' \"$(cat %s)\" \"$(cat %s)\"\n"
            % (verdict_f, open_n))
os.chmod(memo, 0o755)
os.environ["AUTOFINISH_MEMO"] = memo
m._lander = REAL_LANDER
with open(open_n, "w") as f:
    f.write("1")
set_prev(outcome="stopped", gate="G4")
set_last("G4", "⚠ step 4 — 1 open item before this branch can be finished")
r = judge("lander", "stand")
check(r[0], 3, "an unstood G4 stop is refused")
check("docs/design.md (1 open)" in r[1], True, "  naming the open doc (a numbered D-list, as keel reads one)")
with open(open_n, "w") as f:
    f.write("0")
check(judge("lander", "stand"), (0, ""), "a stood one is lifted on the same tip")
with open(verdict_f, "w") as f:
    f.write("taken")
check(judge("lander", "stand")[0], m.DEAD_ROAD_RC, "a doc keel yolo took: never stood (yolo-veto D1), DEAD_ROAD_RC")
with open(verdict_f, "w") as f:
    f.write("too-big")
with open(open_n, "w") as f:
    f.write("1")
check(judge("lander", "stand")[0], m.DEAD_ROAD_RC, "a doc keel never stands (too-big) with items open: DEAD_ROAD_RC")
with open(verdict_f, "w") as f:
    f.write("ask-mode")
check(judge("lander", "stand")[0], m.DEAD_ROAD_RC, "  and one in mode ask (keel's ask-mode): DEAD_ROAD_RC")
with open(open_n, "w") as f:
    f.write("0")
with open(verdict_f, "w") as f:
    f.write("answered")
note = os.path.join(W, "docs", "design", "reviews", "round1.md")
os.makedirs(os.path.dirname(note), exist_ok=True)
with open(note, "w") as f:
    f.write("**D1:** a finding that quotes the item\n")
git(W, "add", "docs/design/reviews/round1.md")
git(W, "commit", "-q", "-m", "the review notes")
r = judge("lander", "stand")
check(r[0], 3, "  an unmarked Markdown commit since the stop: new work, not the stand road's")
check("more than a stand's answers" in r[1], True, "    saying so")
set_prev(outcome="stopped", gate="G4")   # the note was there at the stop
set_last("G4", "⚠ step 4 — 1 open item before this branch can be finished")
check(judge("lander", "stand"), (0, ""), "  an answered nested doc already present at the stop: judged too")
with open(open_n, "w") as f:
    f.write("1")
check("docs/design/reviews/round1.md (1 open)" in judge("lander", "stand")[1], True,
      "  a nested doc with open items is never skipped")
with open(open_n, "w") as f:
    f.write("0")
stop_tip = head()
with open(os.path.join(W, "docs", "design.md"), "a") as f:
    f.write("\n> **Stood.** the stand's answer\n")
git(W, "commit", "-q", "-am", "keel stand: the answers", "-m", "Stood-By: autofinish")
check(judge("lander", "stand"), (0, ""), "  the stand's commit on a memo doc since the stop: taken")
git(W, "reset", "-q", "--hard", stop_tip)
with open(os.path.join(W, "AGENTS.md"), "a") as f:
    f.write("\n- a rule added after the stop\n")
git(W, "commit", "-q", "-am", "a contract edit")
r = judge("lander", "stand")
check((r[0], "not a keel stand commit" in r[1]), (3, True), "  an unmarked contract edit since the stop: refused")
git(W, "reset", "-q", "--hard", stop_tip)

# Keel sweep_docs stands nested docs, and stand_apply stamps the whole set, including an entry without D-items.
nested = "docs/topic/choices.md"
os.makedirs(os.path.join(W, "docs/topic"), exist_ok=True)
with open(os.path.join(W, nested), "w") as f:
    f.write(open(doc).read())
entry_doc = "docs/topic/entry.md"
with open(os.path.join(W, entry_doc), "w") as f:
    f.write("# The set\n\nStatus: proposed\n")
git(W, "add", nested, entry_doc)
git(W, "commit", "-qm", "the nested design set")
set_prev(outcome="stopped", gate="G4")
set_last("G4", "⚠ step 4 — open items")
nested_tip = head()
with open(os.path.join(W, nested), "a") as f:
    f.write("\n> **Applied.** Stood today: the recommendation stands\n")
with open(os.path.join(W, entry_doc), "w") as f:
    f.write("# The set\n\nStatus: answered\n")
git(W, "commit", "-q", "-am", "Memo: choices stood", "-m", "Stood-By: autofinish")
check(judge("lander", "stand"), (0, ""), "  a nested stand plus a set entry stamp without D-items: taken")
with open(os.path.join(W, nested), "a") as f:
    f.write("\n> **Applied.** A second stand\n")
git(W, "commit", "-q", "-am", "Memo: another stand", "-m", "Stood-By: autofinish")
check(judge("lander", "stand"), (0, ""), "  several consecutive keel stand commits: taken")
git(W, "reset", "-q", "--hard", nested_tip)
with open(os.path.join(W, "f"), "a") as f:
    f.write("\nunjudged work\n")
git(W, "commit", "-q", "-am", "a stand trailer cannot excuse code", "-m", "Stood-By: autofinish")
check(judge("lander", "stand")[0], 3, "  a marked commit that changes code: refused")
git(W, "revert", "--no-edit", "HEAD")
git(W, "commit", "-q", "--allow-empty", "-m", "a later stand", "-m", "Stood-By: autofinish")
check(judge("lander", "stand")[0], 3, "  reverted intervening code is still unjudged: every commit is checked")
git(W, "reset", "-q", "--hard", nested_tip)
with open(os.path.join(W, nested), "a") as f:
    f.write("\nnew work after the stop\n")
git(W, "commit", "-q", "-am", "unmarked doc edit")
check(judge("lander", "stand")[0], 3, "  an unmarked edit even to a standable doc: refused")
git(W, "reset", "-q", "--hard", stop_tip)
set_prev(outcome="stopped", gate="G4")
set_last("G4", "⚠ step 4 — open items")
with open(memo) as f:
    memo_text = f.read()
with open(memo, "w") as f:
    f.write("#!/bin/sh\nexit 3\n")
check(judge("lander", "stand")[0], 3, "  keel failing (exit 3): a wait, never a dead road (round 1)")
with open(memo, "w") as f:
    f.write("#!/bin/sh\necho 'memo: docs/design.md has no link' >&2\nexit 1\n")
check(judge("lander", "stand")[0], m.DEAD_ROAD_RC, "  keel's own refusal (exit 1, a memo: line): DEAD_ROAD_RC (round 2)")
with open(memo, "w") as f:
    f.write("#!/bin/sh\necho 'Traceback (most recent call last):' >&2\necho 'memo: x' >&2\nexit 1\n")
check(judge("lander", "stand")[0], 3, "  a crash, though its last line says memo: : a wait")
with open(memo, "w") as f:
    f.write(memo_text)
with open(open_n, "w") as f:
    f.write("0")
with open(memo, "w") as f:
    f.write("#!/bin/sh\nprintf '{\"verdict\": \"answered\", \"items\": 0, \"unanswered\": 0}\\n'\n")
r = judge("lander", "stand")
with open(memo, "w") as f:
    f.write(memo_text)
check(r[0], m.DEAD_ROAD_RC, "  a doc whose D-list keel reads no items in: no stand road (round 3)")
with open(memo, "w") as f:
    f.write(memo_text)
set_last("G1r", "⚠ step 1 — the review found 2 S1s")
check(judge("lander", "stand")[0], 3, "a G1r stop is no stand road's")
m._lander = lambda: FakeAf()

print("a died held lander run: the sweep's retry stays held, a person's typed --merge does not (round 3)")
clear_store()
set_prev(by="lander", outcome="died", gate=None, hold="the held slice holds it", hold_from="s-lander", tip=head())
start("typed", merge=True)
check((state().get("hold"), state().get("merge")), (None, True), "a person's typed --merge keeps its merge, unheld")
set_prev(by="lander", outcome="died", gate=None, hold="the held slice holds it", hold_from="s-lander", tip=head())
start("sweep")
check(state().get("hold"), "the held slice holds it", "  the sweep's retry carries the died run's hold")
end_run(gate="no-landing")

print("a died lander that committed before dying still requires the owner's tap")
m._lander = lambda: FakeAf("default")
held_tip = head()
git(W, "commit", "-q", "--allow-empty", "-m", "the lander commits before dying")
inherited_hold = "mode ask — nothing lands by itself"
set_prev(by="lander", outcome=m.DIED, gate=None, hold=inherited_hold, hold_from="s-stop", keel_hold=False, land_by=None, tip=held_tip)
CALLS.clear()
check(start("sweep")[0], 0, "  the sweep retries a descendant of the died run's start tip")
check(state().get("hold"), inherited_hold, "  mode default does not erase the inherited ask hold")
check("--hold" in CALLS[-1][2], True, "  its finish prompt still requires the tap")
for retry in (2, 3):
    end_run(outcome=m.DIED, gate=None)
    git(W, "commit", "-q", "--allow-empty", "-m", "sweep retry %d commits before dying" % (retry - 1))
    check(start("sweep")[0], 0, "  sweep retry %d starts after the previous retry moved HEAD and died" % retry)
    check(state().get("by"), "sweep", "  retry %d records its own caller" % retry)
    check(state().get("hold"), inherited_hold, "  retry %d keeps the inherited hold" % retry)
    check(bool(state().get("keel_hold")), False, "  retry %d carries the hold without the keel's no" % retry)
    check("--hold" in CALLS[-1][2], True, "  retry %d still requires the tap in its finish prompt" % retry)
end_run(outcome=m.DIED, gate=None)
check(start("override")[0], 0, "  a bare override retries without giving the owner's tap")
check(state().get("hold"), inherited_hold, "  an override without --merge keeps the hold")
end_run(outcome=m.DIED, gate=None)
os.environ["CLAUDE_UNATTENDED"] = "1"
try:
    check(start("typed")[0], 0, "  an unattended caller can retry with the typed label")
    check(state().get("hold"), inherited_hold, "  the label alone gives no tap: the hold stays")
finally:
    del os.environ["CLAUDE_UNATTENDED"]
end_run(outcome=m.DIED, gate=None)
check(start("typed", merge=True)[0], 0, "  a person's typed --merge can give the tap on that descendant")
check((state().get("hold"), state().get("merge")), (None, True), "  keeping the person's launch unheld")
git(W, "reset", "-q", "--hard", held_tip)
end_run(gate="no-landing")
m._lander = lambda: FakeAf()

print("a refused retry keeps the died run's inherited hold until a person's tap")
clear_store()
m._lander = lambda: FakeAf("default")
real_read_outcome = m.read_outcome
try:
    for gate in sorted(m.REFUSED_GATES):
        set_prev(by="lander", outcome=m.DIED, gate=None, hold=inherited_hold, hold_from="s-stop", keel_hold=False, land_by=None)
        m.read_outcome = lambda *a: ("never-started", None, gate, ["dispatch refused the retry"])
        for retry in (1, 2):
            check(start("sweep", verdict="refused")[0], m.REFUSED_RC,
                  "%s retry %d: dispatch's refusal is reported" % (gate, retry))
            with redirect_stdout(io.StringIO()):
                m.record(tree(), state(), 0, 1, None, [])
            check((state().get("outcome"), state().get("gate"), state().get("hold"), bool(state().get("keel_hold"))),
                  ("never-started", gate, inherited_hold, False), "  the refused record still holds it without keel_hold")
        CALLS.clear()
        check(start("sweep")[0], 0, "  the next sweep retry starts")
        check(state().get("hold"), inherited_hold, "  the inherited hold survives both refused starts")
        check("--hold" in CALLS[-1][2], True, "  its finish prompt still requires the owner's tap")
        end_run(outcome="never-started", gate=gate)
        os.environ["CLAUDE_UNATTENDED"] = "1"
        try:
            check(start("typed")[0], 0, "  an unattended typed retry starts after the refusal")
            check(state().get("hold"), inherited_hold, "  the typed label alone still releases no hold")
        finally:
            del os.environ["CLAUDE_UNATTENDED"]
        end_run(outcome="never-started", gate=gate)
        check(start("typed", merge=True)[0], 0, "  an attended typed merge can release the refused retry's hold")
        check((state().get("hold"), state().get("merge")), (None, True), "  that person's launch stays unheld")
finally:
    m.read_outcome = real_read_outcome

print("a refused or died run's own hold is judged again, never carried: a mode raised since is read (the S1 landing's review)")
clear_store()
own_hold = "mode ask — nothing lands by itself"
real_landing = m.landing
m.landing = lambda t, by, rule: (None, None, None)   # the mode raised since: this start's own judgement holds nothing
try:
    for outcome, gate in ((None, sorted(m.REFUSED_GATES)[0]), (m.DIED, None)):
        set_prev(by="sweep", outcome=outcome or "never-started", gate=gate, hold=own_hold, keel_hold=False)
        CALLS.clear()
        check(start("sweep")[0], 0, "  a sweep retry of a %s sweep run held by its own mode ask" % (outcome or gate))
        check(state().get("hold"), None, "  …is unheld: the hold was that run's own judgement, not a carried one")
        check("--hold" in CALLS[-1][2], False, "  …and its prompt asks no tap")
        end_run(gate="no-landing")
    set_prev(by="sweep", outcome="never-started", gate=sorted(m.REFUSED_GATES)[0], hold=own_hold, keel_hold=False,
             hold_from="s-carried")
    check(start("sweep")[0], 0, "  a refused retry whose hold it carried (hold_from)")
    check((state().get("hold"), state().get("hold_from")), (own_hold, "s-carried"), "  …carries it on, naming whose")
    end_run(gate="no-landing")
finally:
    m.landing = real_landing

print("a carried hold rides past a retry held by its own judgement, a mode raised before the next (round 2)")
real_landing = m.landing
m.landing = lambda t, by, rule: ("mode ask — nothing lands by itself", "ask", None)   # R1 runs under mode ask
try:
    set_prev(by="lander", outcome=m.DIED, gate=None, hold=inherited_hold, hold_from="s-stop", keel_hold=False)
    check(start("sweep", verdict="refused")[0], m.REFUSED_RC, "  R1, the sweep's retry under mode ask: refused by dispatch")
    with redirect_stdout(io.StringIO()):
        m.record(tree(), state(), 0, 1, None, [])
    check((state().get("hold"), state().get("hold_from")), (inherited_hold, "s-stop"),
          "  R1's refused record names the carried hold, though its own landing() held too")
    m.landing = lambda t, by, rule: (None, "default", None)   # the mode raised before R2
    CALLS.clear()
    check(start("sweep")[0], 0, "  R2 starts under mode default")
    check((state().get("hold"), "--hold" in CALLS[-1][2]), (inherited_hold, True), "  …still held for the owner's tap")
    end_run(gate="no-landing")
    # a chain relaunch records whose hold it carries; so does a lander start that carries its stop's
    set_prev(by="sweep", hold="the held slice holds it", hold_from=None, gate="no-landing")
    set_last("no-landing", "API Error: 500 Internal server error")   # a stop a chain relaunch takes
    sess = state()["session"]
    check(start("chain")[0], 0, "  a chain relaunch of a held run")
    check(state().get("hold_from"), sess, "  …records the run whose hold it carries")
    end_run(gate="no-landing")
    # a lander start's own hold (a re-finish of a launched PR gone DIRTY): marked carried, from this run, unless it
    # is the mode's ask, which a later retry judges again
    for own, mode, marked in (("the handed slice holds it", "default", True), ("mode ask — nothing lands by itself", "ask", False)):
        m.landing = lambda t, by, rule, own=own, mode=mode: (own, mode, None)
        clear_store()
        set_prev(outcome="launched", gate=None, base_tip=origin_main())
        pr("dirty")
        check(start("lander", "refinish")[0], 0, "  a lander re-finish held by its own %s judgement starts" % mode)
        check(state().get("hold_from") == state().get("session"), marked,
              "  …%s" % ("its hold marked carried, from this run" if marked else "its mode-ask hold left to be judged again"))
        end_run(gate="no-landing")
finally:
    m.landing = real_landing

print("a retry whose waiter cannot detach also keeps the inherited hold")
set_prev(by="lander", outcome=m.DIED, gate=None, hold=inherited_hold, hold_from="s-stop", keel_hold=False, land_by=None)
real_detach = m.detach


def refuse_detach(*a):
    raise OSError("the retry waiter could not start")


m.detach = refuse_detach
try:
    for retry in (1, 2):
        check(start("sweep")[0], 1, "detach retry %d: nothing started" % retry)
        check((state().get("outcome"), state().get("gate"), state().get("hold")),
              ("never-started", m.REFUSED, inherited_hold), "  give_back preserves the inherited hold")
finally:
    m.detach = real_detach
check(start("sweep")[0], 0, "  the next retry starts once detach works")
check(state().get("hold"), inherited_hold, "  and still requires the owner's tap")
end_run(gate="no-landing")
m._lander = lambda: FakeAf()

print("a stuck key: refused STUCK_RC for every by that is not a person's")
clear_store()
set_prev(outcome="stopped", gate="no-landing")
set_last("no-landing", "API Error: 500")
t0 = tree()
m.lander_update(m.lander_key(t0.primary, t0.branch), lambda e: e.update(state="stuck"))
for by in ("lander", "chain", "sweep", "handed", "yolo", "dnd", "brief", "ship"):
    check(judge(by, "login" if by == "lander" else None)[0], m.STUCK_RC, "stuck refuses --by %s" % by)
check(judge("typed")[0], 3, "  a person's typed start meets today's rule, not the stuck key")
# a claim of another host's put (sent) reads no store here: that host's store is the branch's, judged at its put (round 1)
for by in ("sweep", "chain", "brief"):
    why = m.refusal(t0, state(), by, sent=True)
    check(getattr(why, "rc", 3) != m.STUCK_RC, True, "  a claim of another host's --by %s put: this host's stuck key never refuses it" % by)
# …through tree_refusal too, where this host's own last run has not ended (its second leg; round 2)
set_prev(outcome=None, gate=None, ended=None)
for by in ("sweep", "handed", "brief"):
    why = m.tree_refusal(t0, state(), by, True)
    check(getattr(why, "rc", 3) != m.STUCK_RC, True, "  tree_refusal of a claimed --by %s put: never this host's stuck key" % by)
check(getattr(m.tree_refusal(t0, state(), "sweep", False), "rc", 3), m.STUCK_RC, "  while this host's own sweep start still meets it")
# a claim this host put, refused by its stuck key: final (failed) only for a lander's road; another launch hands
# its tip back (refused), so a later `lander reset` lets the sweep put it again (the S1 landing's review)
check(m.claim_final(m.STUCK_RC, False, "lander", "stuck"), True, "  a claimed lander start of this host's put, stuck: its tip held (failed)")
check(m.claim_final(m.DEAD_ROAD_RC, False, "lander", "dead"), True, "  …a dead road too")
for by in ("sweep", "handed", "ship", "yolo"):
    check(m.claim_final(m.STUCK_RC, False, by, "stuck"), False, "  a claimed --by %s start, stuck: handed back (refused), never failed" % by)
check(m.claim_final(m.STUCK_RC, True, "lander", "stuck"), False, "  a claim of another host's lander put: never final here")
set_prev(outcome="stopped", gate="no-landing")
os.environ["CLAUDE_UNATTENDED"] = "1"
check(judge("typed")[0], m.STUCK_RC, "  a --by typed start under CLAUDE_UNATTENDED is no person: STUCK_RC")
check(judge("override")[0], m.STUCK_RC, "  nor a bare override under it")
args = argparse.Namespace(by="typed", road=None, merge=False)
m.lander_after_start(tree(), args, state())
check(entry().get("state"), "stuck", "  and such a start resets nothing")
del os.environ["CLAUDE_UNATTENDED"]

print("the resets: a person's start, `lander reset`; the hold kept")
m.lander_update(m.lander_key(t0.primary, t0.branch), lambda e: e.update(
    refinishes=2, hold={"label": "lander-hold", "head": "abc", "reason": "refinish", "started": True}))
m.lander_after_start(tree(), argparse.Namespace(by="override", road=None, merge=False), state())
check((entry().get("state"), entry().get("refinishes")), ("stuck", 2), "an override start (an unnamed caller) resets nothing")
m.lander_after_start(tree(), argparse.Namespace(by="typed", road=None, merge=False), state())
check((entry().get("state"), entry().get("refinishes")), (None, 0), "a typed start resets the counts and the state")
check((entry().get("hold") or {}).get("head"), "abc", "  keeping the hold until lift")
for verb in ("lift", "reset"):
    r = subprocess.run([os.path.join(B, "autofinish-run"), "lander", verb, "--worktree", W], capture_output=True,
                       text=True, env=dict(os.environ, CLAUDE_UNATTENDED="1"))
    check(r.returncode, 2, "  `lander %s` under CLAUDE_UNATTENDED refused (exit 2): %s" % (verb, r.stderr.strip()))
check((entry().get("hold") or {}).get("head"), "abc", "  the hold still there after both")
m.lander_update(m.lander_key(t0.primary, t0.branch), lambda e: e.update(state="stuck", refinishes=1))
m.lander_after_start(tree(), argparse.Namespace(by="override", road=None, merge=True), state())
check(entry().get("state"), None, "a person's --merge start resets too")

print("the mode flag, the hold and the ladder")
m._lander = lambda: FakeAf("dnd")
clear_store()
set_prev(outcome="stopped", gate="no-landing", by="dnd")
set_last("no-landing", "Not logged in")
CALLS.clear()
check(start("lander", "login")[0], 0, "a lander start of a dnd run")
check(state().get("land_by"), "dnd", "  records land_by dnd")
check("--dnd" in CALLS[-1][2], True, "  and its prompt keeps --dnd: %s" % CALLS[-1][2])
end_run(gate="no-landing")
clear_store()
set_last("no-landing", "Not logged in")
CALLS.clear()
start("lander", "login")
check((state().get("by"), state().get("land_by")), ("lander", "dnd"), "a second lander start keeps land_by from the lander run")
check("--dnd" in CALLS[-1][2], True, "  and --dnd in its prompt")
end_run(gate="no-landing")
clear_store()
set_prev(outcome="stopped", gate="no-landing", by="dnd", hold="the held slice: a public publish")
set_last("no-landing", "Not logged in")
CALLS.clear()
start("lander", "login")
check(state().get("hold"), "the held slice: a public publish", "a held dnd relaunch is held again, the hold verbatim")
check("--hold" in CALLS[-1][2], True, "  its prompt says --hold")
m._lander = lambda: FakeAf()
t1 = tree()
check(m.landing(t1, "lander", "C")[0], None, "an unheld lander relaunch lands though the held slice would hold it (D1-C)")
check(m.landing(t1, "dnd", "C")[0] is not None, True, "  where a dnd launch is held by it")
m._lander = lambda: FakeAf("ask")
check(m.landing(t1, "lander", "C")[0], "mode ask — nothing lands by itself", "a lander start under mode ask is held")
m._lander = lambda: FakeAf(unread=True)
check((m.landing(t1, "lander", "C")[0] or "").startswith("the mode is unreadable"), True,
      "a lander start whose mode cannot be read is held")
m._lander = lambda: None
check(m.landing(t1, "lander", "C")[0], "the lander's judge did not load (bin/autofinish)", "  and one whose ladder did not load")
m._lander = lambda: FakeAf("dnd")
end_run(gate="no-landing")
clear_store()
set_prev(outcome="stopped", gate="no-landing", by="dnd")
set_last("no-landing", "Not logged in")
CALLS.clear()
start("lander", "login")
check((state().get("land_by"), "--dnd" in CALLS[-1][2]), ("dnd", True), "the mode still dnd: --dnd carried")
m._lander = lambda: FakeAf("default")
end_run(gate="no-landing")
clear_store()
set_prev(outcome="stopped", gate="no-landing", by="dnd")
set_last("no-landing", "Not logged in")
CALLS.clear()
start("lander", "login")
check((state().get("land_by"), "--dnd" in CALLS[-1][2]), (None, False),
      "the mode lowered to default since: no --dnd (a chain relaunch's held_slice would hold it)")
m._lander = lambda: FakeAf()
why = m.ladder_stay(t1, argparse.Namespace(rule="C"), "lander")
check(why is not None, True, "ladder_stay pins a lander finish to this host (finish-as-task's pin, as handed)")
check("lander.json" in (why or ""), True, "  for the lander's own reason, its caps in this host's store: %s" % why)

print("a lander run's chain relaunch stays a lander run")
m._lander = lambda: FakeAf("dnd")
clear_store()
end_run(gate="no-landing")
st = state()
st.update(by="lander", land_by="dnd", hold=None)
m.write_state(tree(), st)
set_last("no-landing", "API Error: 500 Internal server error")
CALLS.clear()
check(start("chain")[0], 0, "the chain relaunch starts")
check((state().get("by"), state().get("land_by")), ("lander", "dnd"), "  recorded lander, land_by carried")
check("--dnd" in CALLS[-1][2], True, "  --dnd in its prompt")
check(entry().get("starts", 0), 0, "  and it spends no road (the chain's cap is CHAIN_RELAUNCHES)")
check(state().get("hold"), "a held path (.claude/workflow.json; the autofinish_exclude list)",
      "  judged by held_slice as a dnd launch, held as a chain of a plain dnd run is (round 1)")
check("--hold" in CALLS[-1][2], True, "  --hold in its prompt")
end_run(gate="no-landing")
st = state()
st.update(by="lander", land_by="dnd", hold=None)
m.write_state(tree(), st)
set_last("no-landing", "API Error: 500 Internal server error")
m._lander = lambda: FakeAf("default")
CALLS.clear()
os.remove(os.path.join(tree().state_dir, m.CHAIN))
check(start("chain")[0], 0, "a chain relaunch of a lander run after the mode was lowered to default")
check((state().get("by"), state().get("land_by"), "--dnd" in CALLS[-1][2]), ("lander", None, False),
      "  drops the flag: no --dnd (review 2)")
print("a chain relaunch of a plain chain record carries no flag (the /finish review, 2026-11-03)")
m._lander = lambda: FakeAf("dnd")
end_run(gate="no-landing")
st = state()
st.update(by="chain", land_by="dnd", hold=None)
m.write_state(tree(), st)
set_last("no-landing", "API Error: 500 Internal server error")
CALLS.clear()
try:
    os.remove(os.path.join(tree().state_dir, m.CHAIN))
except OSError:
    pass
rc, err = start("chain")
check(rc, 0, "a chain relaunch of a `chain` record holding a land_by starts: %s" % err.strip()[-200:])
check((state().get("by"), state().get("land_by"), "--dnd" in (CALLS[-1][2] if CALLS else "")), ("chain", None, False),
      "  recorded chain, no land_by, no --dnd: landing() judges `chain` by no slice")
m._lander = lambda: FakeAf()

print("a refused record of another start: no kept stop is judged for it")
clear_store()
advance_main("main moves for the stale-stop case")
set_prev(outcome="launched", gate=None, base_tip=origin_main())
advance_main("and moves on")
pr("dirty")
check(start("lander", "refinish")[0], 0, "a re-finish starts, keeping the stop it passed on")
end_run(gate="G1r", outcome="stopped")
git(W, "commit", "-q", "--allow-empty", "-m", "the fix round's commit")
set_prev(by="sweep", outcome="never-started", gate="refused", base_tip=None, account="acct-new", tip=head())
advance_main("main moves again under it")
pr("dirty")
r = judge("lander", "refinish")
check(r[0], 3, "a sweep dispatch refused after a G1r stop: the refinish road never judges the older kept stop")
check("not kept here" in r[1], True, "  a wait, saying the stop before it is not kept")
clear_store()
set_prev(outcome="stopped", gate="no-landing", account="acct-new", by="sweep")
set_last("no-landing", "You've hit your 5-hour limit · resets 9pm")
set_prev(by="sweep", outcome="never-started", gate="refused", base_tip=None, account="acct-new")
check(judge("lander", "limit")[0], 3, "  nor does the limit road read the refused pick's login (exit 3, never DEAD)")

print("an unconfirmed start that dispatch refused after all gives its road back once")
clear_store()
set_prev(outcome="stopped", gate="no-landing")
set_last("no-landing", "Not logged in")
check(start("lander", "login", verdict="unconfirmed")[0], 0, "an unconfirmed login relaunch")
check(entry().get("relaunches", {}).get("login"), 1, "  spends the road")
end_run(outcome="never-started", gate="refused")
check(judge("lander", "login"), (0, ""), "its refused record: the road given back and the kept stop judged")
check((entry().get("relaunches", {}).get("login"), "spent" in entry()), (0, False), "  refunded once, the spend forgotten")
check(judge("lander", "login"), (0, ""), "  a second judgement refunds nothing more")
check(entry().get("relaunches", {}).get("login"), 0, "  still 0")

print("an unconfirmed start dispatch refused is given back where its record is written, before another start replaces it")
clear_store()
set_prev(outcome="stopped", gate="no-landing")
set_last("no-landing", "Not logged in")
check(start("lander", "login", verdict="unconfirmed")[0], 0, "an unconfirmed login relaunch spends the road")
real_read_outcome = m.read_outcome
m.read_outcome = lambda t, sid, log_from: ("never-started", None, "refused", ["FAILED: no room on this host"])
with redirect_stdout(io.StringIO()):
    m.record(tree(), dict(state()), 0, 5, None, [])
m.read_outcome = real_read_outcome
check((entry().get("relaunches", {}).get("login"), "spent" in entry()), (0, False), "  record() gave it back")
set_prev(outcome="stopped", gate="no-landing", by="sweep")   # the sweep's run replaced the refused record, and stopped
set_last("no-landing", "Not logged in")
check(judge("lander", "login"), (0, ""), "  the next login road is open, not STUCK")

print("a reset keeps the kept stop; --dry writes no refund")
clear_store()
set_prev(outcome="stopped", gate="no-landing")
set_last("no-landing", "Not logged in")
start("lander", "login", verdict="unconfirmed")
subprocess.run([os.path.join(B, "autofinish-run"), "lander", "reset", "--worktree", W], capture_output=True, check=True)
end_run(outcome="never-started", gate="refused")
check(judge("lander", "login"), (0, ""), "a lander start refused after a reset still judges its kept stop")
clear_store()
set_prev(outcome="stopped", gate="no-landing")
set_last("no-landing", "Not logged in")
start("lander", "login", verdict="unconfirmed")
end_run(outcome="never-started", gate="refused")
t2 = tree()
check(m.refusal(t2, m.read_state(t2), "lander", road="login", dry=True), None, "a dry judgement reads the refund owed")
check(entry().get("relaunches", {}).get("login"), 1, "  and writes nothing")

print("a lander start's refusals made outside refusal() are logged once an hour per text too")
m.account_pick = no_account
n0 = day_log().count("cooling down")
for _ in range(3):
    start("lander", "login")
check(day_log().count("cooling down") - n0, 1, "three no-account refusals: one line")
m.account_pick = real_pick

print("round 4: a lander start that never replied, a failed state write, another start's refund")
clear_store()
advance_main("main moves for the never-replied case")
set_prev(outcome="launched", gate=None, base_tip=base)
pr("dirty")
check(start("lander", "refinish")[0], 0, "a re-finish starts")
end_run(outcome="never-started", gate="never-started")
check(judge("lander", "refinish"), (0, ""), "  its session never replied: the road re-judges the stop it passed on")
check(start("lander", "refinish")[0], 0, "  the second re-finish starts")
end_run(outcome="never-started", gate="never-started")
check(judge("lander", "refinish")[0], m.STUCK_RC, "  and the cap of 2 bounds it: STUCK_RC, raised")
clear_store()
set_prev(outcome="stopped", gate="no-landing")
set_last("no-landing", "Not logged in")
start("lander", "login", verdict="refused")
with redirect_stdout(io.StringIO()):
    real_read_outcome = m.read_outcome
    m.read_outcome = lambda t, sid, log_from: ("never-started", None, "refused", ["FAILED: no room"])
    m.record(tree(), dict(state()), 0, 5, None, [])
    m.read_outcome = real_read_outcome
a_sid = state().get("session")
check(entry().get("stop_for"), a_sid, "A, refused: the kept stop is A's")
real_write_state = m.write_state


def full_disk(t, st):
    raise OSError(28, "No space left on device")


m.write_state = full_disk
try:
    start("lander", "login")
except OSError:
    pass
m.write_state = real_write_state
check((entry().get("stop_for"), entry().get("relaunches", {}).get("login"), "spent" in entry()), (a_sid, 0, False),
      "B's state write failed: its spend and stop_for given back")
check(judge("lander", "login"), (0, ""), "  A's refused record still judges the kept stop")
t3 = tree()
m.lander_update(m.lander_key(t3.primary, t3.branch), lambda e: e.update(spent={"session": "B-later", "road": "login"},
                                                                         relaunches={"login": 1}))
m.lander_spend(t3, argparse.Namespace(road="login"), -1, "A-earlier")
check(entry().get("relaunches", {}).get("login"), 1, "a late refund of A never gives back B's spend")
m.lander_update(m.lander_key(t3.primary, t3.branch), lambda e: e.update(relaunches={"login": m.ROAD_CAPS["login"]}))
got = m.lander_spend(t3, argparse.Namespace(road="login"), 1, "C-racing")
check((isinstance(got, m.Refusal), getattr(got, "rc", None), entry().get("relaunches", {}).get("login")),
      (True, m.STUCK_RC, m.ROAD_CAPS["login"]),
      "a spend past the cap under the lock refuses as stuck and spends nothing (a stale start lock's race)")
clear_store()
set_prev(outcome="stopped", gate="G11")
set_last("no-landing", "Not logged in")
check(judge("lander", "login")[0], 3, "a G11 stop whose last line is an older login failure: no login road")
print("E12's standing yes never carries a lander's --yolo where the branch has no mode (round 3: the tick is no person)")
real_merge_auto = m.merge_auto
for label, env, auto in (("a caller with no marker (the tick's launchd job)", {}, True),
                         ("an unattended caller", {"CLAUDE_UNATTENDED": "1"}, True),
                         ("a repo that is not merge: auto", {}, False)):
    clear_store()
    set_prev(outcome="stopped", gate="no-landing", by="yolo", eff_mode="yolo")
    set_last("no-landing", "Not logged in")
    m.merge_auto = lambda t, auto=auto: auto
    os.environ.update(env)
    CALLS.clear()
    start("lander", "login")
    for k in env:
        del os.environ[k]
    check((state().get("land_by"), "--yolo" in CALLS[-1][2]), (None, False), "  %s: the flag stays behind" % label)
    end_run(gate="no-landing")
m.merge_auto = real_merge_auto

print("round 5: the flag over two hops (the mode still yolo), a reset after a start that never replied, a peer's stop, a torn entry")
m._lander = lambda: FakeAf("yolo")
clear_store()
set_prev(outcome="stopped", gate="no-landing", by="yolo", eff_mode="yolo")
set_last("no-landing", "Not logged in")
start("lander", "login")
check(state().get("eff_mode"), "yolo", "a lander hop that keeps --yolo records the mode it stands for")
end_run(gate="no-landing")
set_last("no-landing", "You've hit your 5-hour limit · resets 9pm")
st = state()
st.update(started=iso(3600), account="acct-pro")   # the login the hop ran on, whose window it waits for
m.write_state(tree(), st)
with open(ex, "w") as f:
    f.write(json.dumps({"at": time.time() - 600, "window": "five_hour", "resets_at": time.time() - 60}) + "\n")
CALLS.clear()
check(start("lander", "limit")[0], 0, "  the second hop (a limit relaunch of the lander run) starts")
check((state().get("land_by"), "--yolo" in CALLS[-1][2]), ("yolo", True), "  and keeps --yolo")
m._lander = lambda: FakeAf()
clear_store()
stop = set_prev(outcome="stopped", gate="no-landing", by="sweep")
with open(os.path.join(tree().common, "claude", "autofinished"), "a") as f:
    f.write("%s stopped %s no-landing Not logged in\n" % (stop["ended"], tree().branch))
start("lander", "login")
end_run(outcome="never-started", gate="never-started", ended=iso())
with open(os.path.join(tree().common, "claude", "autofinished"), "a") as f:
    f.write("%s never-started %s the screen's last line\n" % (state()["ended"], tree().branch))
check(judge("lander", "login")[0], m.STUCK_RC, "a login start that never replied: the cap of 1 answers")
subprocess.run([os.path.join(B, "autofinish-run"), "lander", "reset", "--worktree", W], capture_output=True, check=True)
check(judge("lander", "login"), (0, ""), "  after a reset, the road reads the kept stop's own autofinished line: open")
clear_store()
set_prev(outcome="stopped", gate="no-landing", host="some-peer")
set_last("no-landing", "Not logged in")
r = judge("lander", "login")
check((r[0], "that host's tick" in r[1]), (3, True), "a stop that ran on another host (a finish it claimed) is that host's to road")
clear_store()
set_prev(outcome="stopped", gate="no-landing")
t4 = tree()
with open(m.lander_path(), "w") as f:
    json.dump({m.lander_key(t4.primary, t4.branch): ["stuck"]}, f)
check(judge("lander", "login")[0], 3, "an entry that is not an object: a lander start refused")
check(judge("sweep")[0], 3, "  and a sweep too (a narrowing that cannot be read narrows)")
check(start("sweep")[0], 3, "  a sweep's start refused, its refusal counted nowhere")
check(start("sweep")[0], 3, "  and the next one too: the refusal's own write never replaced the entry")
check(store().get(m.lander_key(t4.primary, t4.branch)), ["stuck"], "  the entry left as it was")
subprocess.run([os.path.join(B, "autofinish-run"), "lander", "reset", "--worktree", W], capture_output=True, check=True)
check(isinstance(store().get(m.lander_key(t4.primary, t4.branch)), dict), True, "  a reset writes a fresh entry over it")
clear_store()

print("a store that does not write refuses the start")
clear_store()
set_prev(outcome="stopped", gate="no-landing")
set_last("no-landing", "Not logged in")
lock = str(m.lander_path()) + ".lock"
open(lock, "a").close()
os.chmod(lock, 0o444)
if os.access(lock, os.W_OK):
    print("  --   skipped: this user writes a 0444 file (root)")
else:
    ended = []
    m.end_warm = lambda t, args, cap=None: ended.append(t.branch)
    rc, err = start("lander", "login")
    m.end_warm = lambda t, args, cap=None: None
    check(rc, 3, "the spend cannot be written: refused (exit 3)")
    check("does not write" in err, True, "  saying so")
    check(ended, [], "  before any warm run was ended for it (round 1)")
os.chmod(lock, 0o644)

print("each refusal text a lander start meets is logged; a repeat only after an hour")
clear_store()
set_last("G4", "⚠ step 4 — open items")
n0 = day_log().count("refused tip=")
start("lander", "login")
start("lander", "stand")
start("lander", "login")
check(day_log().count("refused tip=") - n0, 2, "two texts, three refusals: two lines")
m._lander = lambda: FakeAf()

print("the road's own waits are logged once an hour, uncounted")
clear_store()
end_run(gate="no-landing")
set_last("G4", "⚠ step 4 — open items")
n0 = day_log().count("road=login")
start("lander", "login")
start("lander", "login")
check(day_log().count("road=login") - n0, 1, "two waits on the login road: one log line")
check(entry().get("refusals"), None, "  and no same-tip refusal counted")

print("the sweep's retry of a died lander run keeps its mode flag")
st = state()
st.update(by="lander", land_by="yolo", outcome="died", gate=None)
m.write_state(tree(), st)
check(REAL_LANDER().runner_by(W, "A"), "yolo", "runner_by reads land_by")

print("a same-tip refusal goes to lander.json, never autofinish.json, and is logged once an hour")
clear_store()
set_prev(outcome="stopped", gate="G4")
before = open(os.path.join(tree().state_dir, "autofinish.json")).read()
n0 = day_log().count("— its run on this tip")
check(start("sweep")[0], 3, "a sweep on the same tip: refused")
check(start("sweep")[0], 3, "  twice")
r = entry().get("refusals") or {}
check((r.get("tip"), r.get("n"), r.get("by")), (head(), 2, "sweep"), "  counted per tip in lander.json, naming the caller")
check(open(os.path.join(tree().state_dir, "autofinish.json")).read(), before, "  autofinish.json untouched")
check(day_log().count("— its run on this tip") - n0, 1, "  logged once in the hour")
start("typed")
start("typed")
check(day_log().count("— its run on this tip") - n0, 3, "  a person's typed refusal is logged every time")
check((entry().get("refusals") or {}).get("n"), 4, "  and counted")

print("automerge: the PR's request at the run's end")
pr("clean", auto_merge={"merge_method": "rebase", "enabled_by": {"login": "the-bot"}})
check(m.automerge_at_end(tree()), {"merge_method": "rebase", "enabled_by": "the-bot"}, "read from the open PR")
m.read_outcome = lambda t, sid, log_from: ("stopped", 7, "no-landing", ["DONE — waiting for automerge"])
m.comment = lambda *a: (7, "")
m.rotation_row = lambda *a: None
st = set_prev(ended=None, outcome=None, gate=None)
with redirect_stdout(io.StringIO()):
    m.record(tree(), dict(st), 0, 0, None, [])
check(state().get("automerge"), {"merge_method": "rebase", "enabled_by": "the-bot"}, "record() writes it at the end")
pr("clean")
st = set_prev(ended=None, outcome=None, gate=None)
with redirect_stdout(io.StringIO()):
    m.record(tree(), dict(st), 0, 0, None, [])
check("automerge" in state(), False, "  and none when the PR has no request")

print("an unreadable store: no road starts, the plain rule is untouched")
with open(m.lander_path(), "w") as f:
    f.write("{torn")
set_prev(outcome="stopped", gate="no-landing")
set_last("no-landing", "Not logged in")
r = judge("lander", "login")
check(r[0], 3, "a lander start is refused while lander.json does not read")
check("does not read" in r[1], True, "  saying so")
git(W, "commit", "-q", "--allow-empty", "-m", "a new tip")
check(judge("sweep")[0], 3, "  a sweep is refused too: a stuck key it might hold narrows (AGENTS.md's trap)")
check(judge("typed"), (0, ""), "  a person's typed start on a new tip still starts")
clear_store()

print("the landing review of 2026-11-02 (the merge of main)")
m._lander = lambda: FakeAf()
clear_store()
check(m.STUCK_RC != m.ORIGIN_RC, True, "STUCK_RC is not the origin gate's ORIGIN_RC (cold_prompt blocks on that)")
check(m.judged_stop.__code__.co_varnames[:2], ("t", "args"), "judged_stop is main's origin-gate rule; the road's is road_stop")
advance_main("main moves for the tree_refusal case")
set_prev(outcome="launched", gate=None)
pr("dirty")
t3 = tree()
check(bool(m.tree_refusal(t3, state(), "sweep")), True, "tree_refusal refuses a sweep on a launched tip (main's rule)")
check(m.tree_refusal(t3, state(), "lander", road="refinish"), None,
      "  and judges a lander start whole: the refinish road lifts a launched run's same-tip refusal")
set_prev(outcome="launched", gate=None)
check(start("lander", "refinish")[0], 0, "  so a lander re-finish of a launched run starts through start()")
end_run(gate="no-landing")
clear_store()
FAKE = FakeAf(handed="the launcher's own gate (a binary: x.png)")
m._lander = lambda: FAKE
t4 = tree()
t4.stop = {}
check(m.landing(t4, "lander", "C")[0], "the launcher's own gate (a binary: x.png)",
      "a lander start is judged by handed_held: a binary holds it")
check(FAKE.asked, ["handed_held"], "  asked of handed_held")
check(m.landing(t4, "lander", "M")[0], "a held path (.claude/workflow.json; the autofinish_exclude list)",
      "a rule-M lander start is a mode launch, judged by held_slice")
m._lander = lambda: FakeAf("dnd")
t4.stop = {"by": "dnd"}
check(m.landing(t4, "lander", "C")[0], "a held path (.claude/workflow.json; the autofinish_exclude list)",
      "a lander start carrying the stop's --dnd (the mode still dnd) is that mode's launch: held_slice")
FAKE = FakeAf("dnd", handed="the launcher's own gate (a binary: x.png)")
m._lander = lambda: FAKE
t4.flag_word = (None,)
check(m.landing(t4, "lander", "C"), ("the launcher's own gate (a binary: x.png)", "dnd", None),
      "a claimed lander start whose put judged no flag: judged by handed_held though the mode is dnd now (round 1)")
t4.flag_word = ("dnd",)
check(m.landing(t4, "lander", "C")[0], "a held path (.claude/workflow.json; the autofinish_exclude list)",
      "  one whose put judged the same --dnd: that mode's launch, as before")
t4.flag_word = None
m._lander = lambda: FakeAf()

print("no road starts on work the stop never saw")
clear_store()
set_prev(outcome="stopped", gate="no-landing")
set_last("no-landing", "Not logged in")
check(judge("lander", "login"), (0, ""), "a login stop on its own tip: taken")
stop_tip = head()
git(W, "commit", "-q", "--allow-empty", "-m", "work after the stop")
r = judge("lander", "login")
check(r[0], 3, "  a commit since: refused (the sweep judges the new tip)")
check("past the stop's tip" in r[1], True, "  saying so")
git(W, "reset", "-q", "--hard", stop_tip)

print("a road reads its own stop's autofinished line only")
clear_store()
set_last("no-landing", "Not logged in", ts="2001-01-01T00:00:00+00:00")   # an older run's line
set_prev(outcome="stopped", gate="no-landing", ended=iso(7777))   # a stamp no other case's line holds
r = judge("lander", "login")
check(r[0], 3, "an older run's login text is no road for this stop")
set_last("no-landing", "Not logged in")
check(judge("lander", "login"), (0, ""), "  its own line is")

print("a chain relaunch of a lander run that never started: the road judges the kept stop")
clear_store()
set_prev(outcome="stopped", gate="no-landing")
set_last("no-landing", "Not logged in")
check(start("lander", "login", verdict="unconfirmed")[0], 0, "a lander login start")
kept = entry().get("stop") or {}
st = state()
st.update(session=str(uuid.uuid4()), ended=iso(), outcome="never-started", gate="no-landing", by="lander")
m.write_state(tree(), st)   # the chain's relaunch of it, under its own session, never started
check(m.road_stop(state(), entry()).get("session"), kept.get("session"),
      "  its never-started chain relaunch is judged as the kept stop, not as a stop of its own")
check(judge("lander", "login")[0], m.STUCK_RC, "  so the login road's spent cap answers, never a wedge")

print("a store key in a shape no writer makes refuses as an unreadable store")
t5 = tree()
key = m.lander_key(t5.primary, t5.branch)
for bad, label in (({"relaunches": [1]}, "a relaunches list"), ({"state": "Stuck"}, "a state no writer writes"),
                   ({"refinishes": "2"}, "a counter that is text"), ({"relaunches": {"login": "x"}}, "a relaunch that is text")):
    clear_store()
    with open(m.lander_path(), "w") as f:
        json.dump({key: dict(m.fresh_entry(), **bad)}, f)
    r = judge("lander", "login")
    check((r[0], "does not read" in r[1]), (3, True), "%s: no road starts, saying the store does not read" % label)
    check(judge("sweep")[0], 3, "  nor a sweep")
    rc = subprocess.run([os.path.join(B, "autofinish-run"), "lander", "spend", "reruns", "--worktree", W],
                        capture_output=True).returncode
    check(rc, 3, "  `lander spend` refuses it (exit 3, never a crash)")
clear_store()
with open(m.lander_path(), "w") as f:
    json.dump({key: dict(m.fresh_entry(), relaunches=[1], hold={"head": "abc"})}, f)
subprocess.run([os.path.join(B, "autofinish-run"), "lander", "reset", "--worktree", W], capture_output=True, check=True)
check((entry().get("relaunches"), (entry().get("hold") or {}).get("head")), (m.fresh_entry()["relaunches"], "abc"),
      "a reset writes over it, the hold kept")
clear_store()

print("a null branch entry is unreadable, even when HEAD moved past the last stop")
set_prev(outcome="stopped", gate="no-landing")
null_prev = state()
null_tip = head()
git(W, "commit", "-q", "--allow-empty", "-m", "work past a stop with a null lander entry")
t_null = tree()
null_key = m.lander_key(t_null.primary, t_null.branch)
check(m.lander_entry(t_null), {}, "an absent branch entry still reads as empty")
with open(m.lander_path(), "w") as f:
    json.dump({null_key: None}, f)
os.environ["CLAUDE_UNATTENDED"] = "1"
try:
    for gate in (m.tree_refusal, m.refusal):
        for by in ("sweep", "chain", "lander", "handed", "yolo", "dnd", "brief", "ship", "typed", "override"):
            why = gate(t_null, null_prev, by)
            check((getattr(why, "rc", None), "is not an object" in str(why)), (3, True),
                  "%s --by %s: a null entry refuses before any start or tree move" % (gate.__name__, by))
finally:
    del os.environ["CLAUDE_UNATTENDED"]
for gate in (m.tree_refusal, m.refusal):
    check(gate(t_null, null_prev, "typed"), None, "%s: a person's start still passes" % gate.__name__)
    check(gate(t_null, null_prev, "sweep", sent=True), None,
          "%s: another host's claimed put still reads only its own store" % gate.__name__)
check(store(), {null_key: None}, "the malformed entry is kept for an explicit reset")
clear_store()
git(W, "reset", "-q", "--hard", null_tip)

print("round 1 of the build review")
m._lander = lambda: FakeAf()
clear_store()
set_prev(outcome="launched", gate=None, pushed=head())
advance_main("main moves for the kept-pushed case")
pr("dirty")
check(start("lander", "refinish", verdict="unconfirmed")[0], 0, "a lander re-finish start, never replied")
check(entry().get("stop", {}).get("pushed"), head(), "  the kept stop keeps the tip its run pushed")
end_run(outcome="never-started", gate="no-landing", by="lander")
git(W, "commit", "-q", "--allow-empty", "-m", "a hand push after the stop")
pr("dirty")
r = judge("lander", "refinish")
check((r[0], "its last run pushed" in r[1]), (3, True), "  the next re-finish on a HEAD past it: refused")
git(W, "reset", "-q", "--hard", "HEAD~1")
pr("dirty")
check(judge("lander", "refinish"), (0, ""), "  on that tip: the kept stop's road, not a wedge (fix 9 through refinish)")

FAKE = FakeAf(None)
m._lander = lambda: FAKE
t6 = tree()
t6.stop = {"by": "yolo", "eff_mode": "yolo"}
m.merge_auto = lambda t: True
check(m.landing(t6, "lander", "C")[0], None,
      "a lander start with no mode, the stop's eff_mode yolo, merge: auto: no E12 yes, judged as handed (round 3)")
check(FAKE.asked, ["handed_held"], "  by handed_held")
t6.stop = {"by": "dnd", "eff_mode": "dnd"}
check(m.landing(t6, "lander", "C")[0], None, "  a dnd flag with no mode never rides either")
m.merge_auto = real_merge_auto
m._lander = lambda: FakeAf()

print("account limits with no rows yet is a wait, never a dead road")
real_account, real_run_group = m.ACCOUNT, m.common.run_group
m.ACCOUNT = "/bin/true"
m.common.run_group = lambda cmd, timeout: subprocess.CompletedProcess(cmd, 0, "[]", "")
home, why = m.account_home("acct-pro")
check((home, getattr(why, "rc", None)), (None, 3), "an empty --cached reading: exit 3")
m.ACCOUNT, m.common.run_group = real_account, real_run_group

print("old refusal-only entries are pruned at the next write")
clear_store()
t7 = tree()
old = (datetime.datetime.now().astimezone() - datetime.timedelta(days=8)).isoformat(timespec="seconds")
with open(m.lander_path(), "w") as f:
    json.dump({"x/old": dict(m.fresh_entry(), refusals={"tip": "a", "n": 3, "last": old}),
               "x/new": dict(m.fresh_entry(), refusals={"tip": "a", "n": 1, "last": iso()}),
               "x/held": dict(m.fresh_entry(), hold={"head": "a"}, refusals={"tip": "a", "n": 1, "last": old})}, f)
m.lander_update(m.lander_key(t7.primary, t7.branch), lambda e: None)
check(sorted(k for k in store() if k.startswith("x/")), ["x/held", "x/new"], "a week-old count alone goes; a hold or a fresh count stays")
clear_store()

print("a start lock's refusal of a lander start is logged once an hour")
lockf = os.path.join(tree().state_dir, m.START_LOCK)
open(lockf, "w").close()
n0 = day_log().count("another start on this worktree")
for _ in range(2):
    with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
        rc = m.main([W, "--by", "lander", "--road", "login"])
check(rc, 3, "refused while another start holds the lock")
check(day_log().count("another start on this worktree") - n0, 1, "  two refusals: one line")
os.remove(lockf)
clear_store()

print("round 2 of the build review")
m._lander = lambda: FakeAf()
clear_store()
t8 = tree()
check(m.count_refusal(t8, "lander", counted=False, text="a wait"), True, "a road's wait on branch A: logged")
check(m.count_refusal(t8, "lander", counted=False, text="a wait"), False, "  again within the hour: not")
m.lander_update("other-repo/branch-b", lambda e: e.update(road_logged={"x": time.time()}))
check(m.count_refusal(t8, "lander", counted=False, text="a wait"), False,
      "  a write for branch B prunes not A's hour record (round 2)")
clear_store()

set_prev(outcome="stopped", gate="no-landing", by="lander")   # L1: a lander run, stopped on the network
set_last("no-landing", "API Error: 500")
l1 = state()
check(start("chain")[0], 0, "a chain relaunch of a lander run starts")
check((entry().get("stop") or {}).get("session"), l1["session"], "  keeping that lander run as the stop, no road spent")
check(entry().get("stop_for"), state()["session"], "  stop_for the chain's own session")
check(entry().get("starts", 0), 0, "  spending nothing")
end_run(outcome="never-started", gate="no-landing", by="lander")
check(m.road_stop(state(), entry()).get("session"), l1["session"], "  dead, the road judges that lander run (round 2)")
clear_store()

set_prev(outcome="stopped", gate="no-landing")
set_last("no-landing", "Not logged in")
with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
    m.lander_update(m.lander_key(tree().primary, tree().branch), lambda e: e.update(state="stuck"))
os.environ["SKIPPER_SCOPE"] = "s"
check(judge("typed")[0], m.STUCK_RC, "a skipper's --by typed is no person: the stuck key refuses it (round 2)")
del os.environ["SKIPPER_SCOPE"]
clear_store()

set_prev(outcome="launched", gate=None, pushed=None, tip=head())
advance_main("main moves for the no-pushed case")
pr("dirty")
check(judge("lander", "refinish")[0], 0, "a launched record with no pushed, on its start tip: taken")
git(W, "commit", "-q", "--allow-empty", "-m", "a rewrite or new work, nobody can tell")
pr("dirty")
check(judge("lander", "refinish")[0], m.DEAD_ROAD_RC, "  on any other HEAD: DEAD_ROAD_RC, the owner's (round 2)")
git(W, "reset", "-q", "--hard", "HEAD~1")
clear_store()

check(m.stand_doc("docs/handoff/brief.md"), False, "keel's stand sweep excludes handoff briefs")
check(m.stand_doc("docs/topic/choices.md"), True, "  and includes nested Markdown docs")

check(m.lander_key("/var/tmp-x-nowhere/../tmp", "b"), m.lander_key(os.path.realpath("/var/tmp"), "b"),
      "a repo outside the projects folder: one key whatever its spelling (round 2)")

print("round 3 of the build review")
m._lander = lambda: FakeAf()
clear_store()
set_prev(outcome="stopped", gate="no-landing")
set_last("no-landing", "Not logged in")
here = head()
git(W, "commit", "-q", "--allow-empty", "-m", "a commit only origin has")
br = git(W, "rev-parse", "--abbrev-ref", "HEAD")
subprocess.run(["git", "-C", W, "send-pack", os.path.join(T, "origin.git"), "+HEAD:refs/heads/" + br], capture_output=True, check=True)
git(W, "reset", "-q", "--hard", here)
ended = []
m.end_warm = lambda t, args, cap=None: ended.append(t.branch)
rc, err = start("lander", "login")
m.end_warm = lambda t, args, cap=None: None
check((rc, head(), ended), (m.ORIGIN_RC, here, []),
      "origin ahead of a lander start: refused at the origin gate, the tree unmoved and no warm run ended")

print("every automatic start checks the cap store before ending a run or following origin")
for bad_store in ("stuck", "unreadable"):
    for by in ("sweep", "handed", "ship", "yolo", "dnd", "brief"):
        git(W, "reset", "-q", "--hard", here)
        clear_store()
        set_prev(outcome="stopped", gate="no-landing")
        before = state()
        if bad_store == "stuck":
            m.lander_update(m.lander_key(tree().primary, tree().branch), lambda e: e.update(state="stuck"))
        else:
            with open(m.lander_path(), "w") as f:
                f.write("{torn")
        ended = []
        m.end_warm = lambda t, args, cap=None: ended.append(t.branch)
        rc, err = start(by)
        m.end_warm = lambda t, args, cap=None: None
        check((rc, head(), ended, state()), (m.STUCK_RC if bad_store == "stuck" else 3, here, [], before),
              "  %s store: --by %s refuses before a warm run ends, HEAD or its record moves" % (bad_store, by))
clear_store()
subprocess.run(["git", "-C", W, "send-pack", os.path.join(T, "origin.git"), "+HEAD:refs/heads/" + br], capture_output=True, check=True)
clear_store()

set_prev(outcome="stopped", gate="no-landing", pushed=None)
set_last("no-landing", "Not logged in")
st = state()
git(W, "commit", "-q", "--allow-empty", "-m", "the finish's curation, pushed, then the login failed")
m.write_state(tree(), dict(st, pushed=head()))
check(judge("lander", "login"), (0, ""), "a login stop after its run pushed a curated tip: HEAD is that tip, taken")
git(W, "reset", "-q", "--hard", "HEAD~1")
clear_store()

set_prev(outcome="stopped", gate="no-landing", hold="mode ask — nothing lands by itself", keel_hold=True)
set_last("no-landing", "Not logged in")
check(start("lander", "login", verdict="unconfirmed")[0], 0, "a lander start of a keel-held stop")
check(entry().get("stop", {}).get("keel_hold"), True, "  the kept stop keeps the keel's no")
end_run(outcome="never-started", gate="refused")
start("lander", "login")
check(state().get("keel_hold"), True, "  the next lander start, judging the kept stop, records it (round 3)")
clear_store()

class NoSlice(FakeAf):
    def held_slice(self, *a):
        return None


m._lander = lambda: NoSlice("dnd")
set_prev(outcome=m.DIED, gate=None, by="lander", land_by="dnd", hold="the launcher's own gate (a binary: x.png)", hold_from="s-lander")
st = state()
check(start("dnd")[0], 0, "the sweep's retry of a died lander run (--by dnd from its land_by)")
check(state().get("hold"), "the launcher's own gate (a binary: x.png)", "  carries the hold that run carried (round 3)")
m._lander = lambda: FakeAf()
clear_store()

print("every writer under the lock")


def bump(n):
    t = tree()
    for _ in range(n):
        m.lander_update(m.lander_key(t.primary, t.branch), lambda e: e.update(starts=int(e.get("starts") or 0) + 1))


pids = []
for _ in range(6):
    pid = os.fork()
    if pid == 0:
        try:
            bump(20)
        finally:
            os._exit(0)
    pids.append(pid)
for pid in pids:
    os.waitpid(pid, 0)
check(entry().get("starts"), 120, "six writers at once, 20 writes each: none lost")
sys.exit(1 if fails else 0)
