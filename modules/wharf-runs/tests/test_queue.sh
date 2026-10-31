#!/usr/bin/env bash
# Tests for the queue's S2 first half (docs/dispatch-queue-2026-10-25.md): what starts a queued entry with
# nobody retrying — the watcher's claim (dispatch-rc), the queue-sweep job and the pending poll
# (dispatch-queue jobs, poll), G3's event_at — and the S1 landing reviews' items carried to S2, one case
# each. S1's own cases stay in test_dispatch.sh; this suite is apart so the two halves of S2 and S3 never
# edit one file's tail. Scratch HOME, a bare repo as the queue's home, a stand-in launchctl; no launchd
# job, session or network is touched. Every name is synthetic.
#   bash modules/wharf-runs/tests/test_queue.sh
set -u
unset WEEKLY_RUN REGATTA_UNATTENDED CLAUDE_UNATTENDED AUTOFINISH_CALLER_UNATTENDED CLAUDE_CODE_DISABLE_BACKGROUND_TASKS CLAUDE_CODE_SESSION_ID CLAUDE_CONFIG_DIR XPC_SERVICE_NAME
unset $(compgen -v | grep '^DISPATCH_')   # every DISPATCH_* a run carries (AGENTS.md: a fixed list goes stale)
B="$(cd "$(dirname "$0")/../bin" && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
. "$(cd "$(dirname "$0")" && pwd)/config_fixture.sh"; fixture_config "$T/config"
fails=0
check() { if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3: expected [$2] got [$1]"; fails=$((fails+1)); fi; }
has()   { if grep -qF -- "$2" "$1"; then echo "  ok   $3"; else echo "  FAIL $3: missing [$2]"; sed 's/^/         | /' "$1" | head -20; fails=$((fails+1)); fi; }
export PYTHONUSERBASE="${PYTHONUSERBASE:-$(python3 -m site --user-base)}"
# every home path through $HL, one definition (S2a's landing review, item 2: the publish gate)
export HOME="$T/home"; HL="$HOME/Library"; mkdir -p "$HL/LaunchAgents"
# a recursive delete under HOME goes through rm_own: only under this suite's own $T, so a block of the
# suite run outside it (its HOME the real one; F2, 2026-10-25) deletes nothing (the core's check, home_rm)
rm_own() { local p; for p; do case "$p" in */..|*/../*|*//*) ;; "${T:?}"/?*) rm -rf -- "$p"; continue ;; esac; echo "rm_own: refused $p, outside $T" >&2; return 1; done; }
export ACCOUNTS_FILE="$T/no-accounts.json"
# a moved HOME drops the global git identity (AGENTS.md: a suite that moves HOME and commits)
printf '[user]\n\tname = t\n\temail = t@t\n[init]\n\tdefaultBranch = main\n' > "$T/gitconfig"; export GIT_CONFIG_GLOBAL="$T/gitconfig"
git init -q -b main "$T/repo"; (cd "$T/repo" && echo x > f && git add f && git commit -qm init)
cat > "$T/launchctl" <<EOF
#!/bin/sh
echo "\$*" >> "$T/calls"
case "\$1" in print) [ -f "$T/running.\${2##*/}" ] && printf '\tstate = running\n';; esac
exit 0
EOF
chmod +x "$T/launchctl"
export DISPATCH_LAUNCHCTL="$T/launchctl" DISPATCH_DEFAULT_ON= DISPATCH_HOST=laptop
git init -q --bare "$T/queue.git"
echo "$T/queue.git" > "$REGATTA_CONFIG/wharf-runs/queue-repo"
QB="$B/dispatch-queue"; LA="$HL/LaunchAgents"; QL="$HL/Logs/claude-weekly/queue.jsonl"
QC=(--cap 3 --launchctl "$T/launchctl" --prefix org.example.claude --jobbin "$B/dispatch")
QGIT=(git --git-dir="$T/queue.git")
cat > "$T/qget.py" <<'PY'
import json, sys
d = json.load(sys.stdin)
print(" ".join(",".join(sorted(d[k])) if isinstance(d.get(k), dict) else str(d.get(k)) for k in sys.argv[1:]))
PY
qget() { local k=$1; shift; "${QGIT[@]}" show "refs/regatta/queue:queue/$k.json" 2>/dev/null | python3 "$T/qget.py" "$@" 2>/dev/null; }
qplists() { ls "$LA"/org.example.claude.dispatch.*.q[0-9]*.plist 2>/dev/null; }
qreset() {
  "${QGIT[@]}" update-ref -d refs/regatta/queue 2>/dev/null
  rm_own "$HL/Caches/run-seed/queue" "$HL/Logs/claude-weekly/run-seed-runs"
  rm_own "$LA"/*.plist "$T/calls" "$QL"
}
enq() { python3 "$QB" enqueue --repo "$T/repo" --branch "claude/laptop/2026-10-27-$1" "${QC[@]}" "${@:2}" > /dev/null; }
pkey() { python3 -c 'import plistlib, sys; d = plistlib.load(open(sys.argv[1], "rb")); v = d
for k in sys.argv[2:]:
    v = v.get(k) if isinstance(v, dict) else None
print(" ".join(v) if isinstance(v, list) else v)' "$@"; }
# the module loaded, a ctx as dispatch passes it: for the cases that stand a function in
cat > "$T/q.py" <<'PY'
import argparse, importlib.machinery, json, os, sys, time
q = importlib.machinery.SourceFileLoader("dq", sys.argv[1]).load_module()
launchctl, jobbin, case = sys.argv[2], sys.argv[3], sys.argv[4]
ctx = argparse.Namespace(host=None, cap=3, launchctl=launchctl, prefix="org.example.claude", jobbin=jobbin, rch="", event_at=None)
url = sys.argv[5] if len(sys.argv) > 5 else ""
if case == "git-count":
    # read: one ls-tree and one cat-file --batch; write: one hash-object, two mktree, one commit-tree
    calls = []
    real = q.Fleet.git
    def git(self, *a, **k):
        calls.append(a[0])
        return real(self, *a, **k)
    q.Fleet.git = git
    f = q.Fleet(url)
    f.ensure()
    del calls[:]
    entries = {"k%d" % i: {"state": "queued", "n": i} for i in range(5)}
    c = f.write(entries, "five")
    w = len(calls)
    del calls[:]
    back = f.read(c)
    print(w, len(calls), back == entries)
elif case == "contended":
    # every push loses the lease (another host writing) for N rounds, then lands
    n = [int(sys.argv[6])]
    real = q.Fleet.push
    def push(self, commit, base):
        if n[0] > 0:
            n[0] -= 1
            return "lost", "! [rejected] refs/regatta/queue (stale info)"
        return real(self, commit, base)
    q.Fleet.push = push
    q.time.sleep = lambda s: None
    sys.argv = ["dispatch-queue", "enqueue", "--repo", sys.argv[7], "--branch", sys.argv[8], "--cap", "3",
                "--launchctl", launchctl, "--prefix", "org.example.claude", "--jobbin", jobbin]
    sys.exit(q.main(sys.argv[1:]))
elif case == "stale-retry":
    # S2a's landing review, item 5: the lease lost thrice, and before the retry's flush another host's branch
    # of the same key lands; the flush drops the put as stale, and enqueue must not say "queued"
    repo, branch = sys.argv[6], sys.argv[7]
    n, sleeps = [3], []
    real = q.Fleet.push
    def push(self, commit, base):
        if n[0] > 0:
            n[0] -= 1
            return "lost", "! [rejected] refs/regatta/queue (stale info)"
        return real(self, commit, base)
    q.Fleet.push = push
    def sleep(s):
        # three between the lost rounds, then enqueue's pause before its retry: the other host writes then,
        # once the put waits in the outbox (earlier, this process's cache clone would show it the clash)
        sleeps.append(s)
        if len(sleeps) == 4:
            other = "claude/studio/" + branch.rsplit("/", 1)[1]
            k = q.key_of(str(q.Path(repo).resolve()), branch)
            e = {"id": "other", "key": k, "repo": q.repo_word(str(q.Path(repo).resolve())), "branch": other,
                 "topic": q.topic_of(other), "state": "queued", "queued_at": q.now(), "priority": "normal", "host": ""}
            q.Fleet(url).do([{"op": "put", "key": k, "entry": e}], "another host")
    q.time.sleep = sleep
    sys.argv = ["dispatch-queue", "enqueue", "--repo", repo, "--branch", branch, "--cap", "3",
                "--launchctl", launchctl, "--prefix", "org.example.claude", "--jobbin", jobbin]
    sys.exit(q.main(sys.argv[1:]))
elif case == "spent":
    # a reservation whose job's plist is gone, SPENT after its claim: given back; with its plist, kept
    q.claims_dir().mkdir(parents=True, exist_ok=True)
    t = q.now() - q.SPENT - 5
    q._reswrite("fleet:x", "a", {"qid": "fleet:x", "at": t, "label": "org.example.claude.dispatch.x.gone"})
    q._reswrite("fleet:y", "a", {"qid": "fleet:y", "at": t, "label": "org.example.claude.dispatch.y.kept"})
    q._reswrite("fleet:z", "a", {"qid": "fleet:z", "at": q.now(), "label": "org.example.claude.dispatch.z.young"})
    # S2a's finish review: a claim still in its CAS round (its claimer alive, no plist yet) is held past SPENT
    q._reswrite("fleet:w", "a", {"qid": "fleet:w", "at": t, "label": "org.example.claude.dispatch.w.inflight", "pid": os.getpid()})
    q.agents().mkdir(parents=True, exist_ok=True)
    (q.agents() / "org.example.claude.dispatch.y.kept.plist").write_text("x")
    print(" ".join(sorted(r["qid"] for r in q.reservations(launchctl).values())))
elif case == "raise":
    # the caller's own run: a record of its session on that branch, at the mode dispatch judged (argv 6,
    # which is also the env's DISPATCH_MODE, the caller's own word)
    os.environ.update(CLAUDE_UNATTENDED="dispatch", DISPATCH_MODE=sys.argv[6], CLAUDE_CODE_SESSION_ID="s-r12")
    d = q.logdir() / "run-seed-runs"
    d.mkdir(parents=True, exist_ok=True)
    (d / "r12.json").write_text(json.dumps({"session": "s-r12", "branch": "claude/laptop/2026-10-27-r12", "repo": url,
                                            "topic": "r12", "task_mode": sys.argv[6]}))
    print(q.raise_refusal([], {"DISPATCH_MODE": sys.argv[7]}, "normal", url, "claude/laptop/2026-10-27-r12") or "none")
elif case == "lowered":
    # S2a's landing review, item 4: the owner lowered the target to default (helm stood in), and a dnd caller's
    # inherited hint is dnd. Onto the caller's own branch (its record, by its session id): no raise (the fourth
    # review's item 12). Onto a sibling: judged, and refused, as main did
    import types
    rank = {"ask": 0, "default": 1, "dnd": 2, "yolo": 3}
    h = types.ModuleType("helmlib")
    h.branch_mode = lambda b, r: ("default", "a helm mode --branch")
    h.run_mode = lambda: ("dnd", "the run")
    h.raise_refusal = lambda old, new: "mode %s over %s is a raise" % (new, old) if rank[new] > rank[old] else ""
    sys.modules["helmlib"] = h
    os.environ.update(CLAUDE_UNATTENDED="dispatch", DISPATCH_MODE="dnd", CLAUDE_CODE_SESSION_ID="s-own")
    own, sib = "claude/laptop/2026-10-27-own", "claude/laptop/2026-10-27-sib"
    d = q.logdir() / "run-seed-runs"
    d.mkdir(parents=True, exist_ok=True)
    (d / "own.json").write_text(json.dumps({"session": "s-own", "branch": own, "repo": url, "topic": "own", "task_mode": "dnd"}))
    say = lambda b: q.raise_refusal([], {"DISPATCH_MODE": "dnd"}, "normal", url, b) or "none"
    if sys.argv[6:7] == ["forged"]:
        # the caller's run was started at default; it set DISPATCH_MODE=dnd itself
        (d / "own.json").write_text(json.dumps({"session": "s-own", "branch": own, "repo": url, "topic": "own", "task_mode": "default"}))
        print(say(own))
    else:
        print(say(own) + " | " + say(sib))
elif case == "reached":
    print(q.reached("laptop"))
elif case == "noreap":
    # S2a's review, item 1: claim() asks unfinished() without reaping (a reap ends the orphan, and its end
    # claimed: a nested claim waiting 150 s on the start lock its parent holds), and dispatch-rc loaded in
    # this process never starts dispatch --claim from finish()
    m = q.rc_mod()
    reaps, spawned = [], []
    real = m.live
    def live(a=None, b=None, reap=True):
        reaps.append(reap)
        return real(a, b, False)
    m.live = live
    run = m.subprocess.run   # one subprocess module for both: stood in only for the claim from finish()
    m.subprocess.run = lambda *a, **k: spawned.append(a)
    m.queue_claim("a test", 1)
    m.subprocess.run = run
    branch = "claude/laptop/2026-10-27-n1"
    sys.argv = ["dispatch-queue", "enqueue", "--repo", url, "--branch", branch, "--cap", "3", "--launchctl", launchctl,
                "--prefix", "org.example.claude", "--jobbin", jobbin]
    q.main(sys.argv[1:])
    d = q.logdir() / "run-seed-runs"
    d.mkdir(parents=True, exist_ok=True)
    (d / "n1.json").write_text(json.dumps({"topic": q.topic_of(branch), "repo": url, "session": "s-n1"}))
    q.claim(ctx)
    print(m.CLAIM_AT_END, len(spawned), True in reaps)
elif case == "reached-of":
    print(q.reached(sys.argv[5]))
elif case == "hold":
    # S8's hold-back: the berths' order stood in (alpha, beta above this host), the kicks' full sets as given;
    # the sleep recorded, never slept
    q.berth_candidates = lambda repo, h: (sys.argv[5].split(","), {"berths": sys.argv[5].split(",")})
    q.eligibility = lambda e, h, feats=None: "barred" if h in os.environ.get("HOLD_INELIG", "").split(",") else None
    slept = []
    # the hold's own sleeps only (whole seconds): a clone lock a detached kicker holds adds its backoff's steps
    q.time.sleep = lambda s: slept.append(s) if s >= 1 else None
    q.kicks_dir().mkdir(parents=True, exist_ok=True)
    for i, full in enumerate(sys.argv[6:]):
        (q.kicks_dir() / ("%d-k%d.json" % (q.now(), i))).write_text(json.dumps({"at": q.now(), "from": "x", "full": [f for f in full.split(",") if f]}))
    print(q.kick_hold(ctx, "laptop"), slept, len(list(q.kicks_dir().glob("*.json"))))
elif case == "midpass":
    # the S8 review: a kick heard while the sweep ran (its kickstart started nothing) gets one more hold and claim
    calls, held = [], []
    def claim(c, out=None):
        calls.append(1)
        if len(calls) == 1:
            q.kicks_dir().mkdir(parents=True, exist_ok=True)
            (q.kicks_dir() / ("%d-late.json" % q.now())).write_text(json.dumps({"at": q.now(), "from": "x", "full": ["x"]}))
        return []
    q.claim = claim
    q.kick_hold = lambda c, h: held.append(h) or 0
    q.poll_tend = lambda c: None
    q.cmd_sweep(ctx, ctx)
    print(len(calls), len(held))
elif case == "midpass-torn":
    # the S8 review, pass 2: a torn ref at the mid-pass flush skips that flush, never the claim or poll_tend
    calls, tended = [], []
    def claim(c, out=None):
        calls.append(1)
        if len(calls) == 1:
            q.kicks_dir().mkdir(parents=True, exist_ok=True)
            (q.kicks_dir() / ("%d-late.json" % q.now())).write_text(json.dumps({"at": q.now(), "from": "x", "full": ["x"]}))
            def torn(*a, **k):
                raise q.Torn("a torn ref (a test)")
            q.flush = torn
        return []
    q.claim = claim
    q.kick_hold = lambda c, h: 0
    q.poll_tend = lambda c: tended.append(1)
    print(q.cmd_sweep(ctx, ctx), len(calls), len(tended))
elif case == "hold-fresh":
    # the S8 review, pass 2: the hold never reads the 5 s cached view, which may predate the kicked entry
    q.berth_candidates = lambda repo, h: (["alpha", "laptop"], {"berths": ["alpha", "laptop"]})
    q.eligibility = lambda e, h, feats=None: None
    q.time.sleep = lambda s: None
    q._FRESH[q.home()] = (q.time.monotonic(), json.dumps({}))
    q.kicks_dir().mkdir(parents=True, exist_ok=True)
    (q.kicks_dir() / ("%d-k.json" % q.now())).write_text(json.dumps({"at": q.now(), "from": "x", "full": []}))
    print(q.kick_hold(ctx, "laptop"))
elif case == "rch-retry":
    # the S8 review, pass 2: an rc-hosts that timed out is asked again, never cached as no launcher
    ctx.rch = sys.argv[5]
    real = q.subprocess.run
    n = []
    def run(cmd, *a, **k):
        if cmd and cmd[0] == ctx.rch and not n:
            n.append(1)
            raise q.subprocess.TimeoutExpired(cmd, 20)
        return real(cmd, *a, **k)
    q.subprocess.run = run
    print(q.program(ctx, "x")[0] == ctx.jobbin, q.program(ctx, "x")[0])
elif case == "sweep-busy":
    # S2a review, item 7.3: a clone lock held past its wait skips the flush and the collection, never the claim
    def locked(self, wait=75):
        raise q.Unreachable("this host's queue clone is busy (a test)")
    q.Fleet.locked = locked
    claimed = []
    q.claim = lambda c, out=None: claimed.append(1) or []
    q.poll_tend = lambda c: None
    print(q.cmd_sweep(ctx, ctx), len(claimed))
elif case == "rch-once":
    # S2a review, item 7.9: rc-hosts asked once per process, not at every plist compare
    ctx.rch = sys.argv[5]
    q.job_plist(ctx, "a", "sweep", 600); q.job_plist(ctx, "b", "poll", 60)
    print(open(sys.argv[6]).read().count("x"))
elif case == "tend-quiet":
    # S2a's finish review, item 8: a host a road reaches, no poll loaded: poll_tend reads no ref
    reads = []
    q.Fleet.cached = lambda self: reads.append(1) or ""
    print(q.poll_tend(ctx), len(reads))
PY
qpy() { python3 "$T/q.py" "$QB" "$T/launchctl" "$B/dispatch" "$@"; }
# dispatch-rc loaded, for the watcher's cases
cat > "$T/rc.py" <<'PY'
import importlib.machinery, json, os, sys, time
rc = importlib.machinery.SourceFileLoader("drc", sys.argv[1]).load_module()
case = sys.argv[2]
if case == "claim":
    rc.queue_claim("a test", int(sys.argv[3]))
elif case == "home":
    print(rc.queue_home_set())
elif case == "loop":
    # watch_loop driven by a script of the session's status: busy, then idle (parked), busy, idle; a claim
    # per parked stretch. Stand-ins for everything that reads a real session
    seq = sys.argv[3].split(",")
    st = dict(json.loads(sys.argv[4]), session="s1", pid=1)
    i = [0]
    claims = []
    rc.POLL = 0
    def same(s):   # once at the top of each pass: the pass's status is seq's next
        i[0] += 1
        return i[0] <= len(seq)
    rc.same = same
    rc.session_record = lambda s: {"status": seq[min(i[0], len(seq)) - 1], "sessionId": "s1"}
    rc.parked = lambda s: seq[min(i[0], len(seq)) - 1] in ("idle", "waiting")
    rc.RC.idle_hours = lambda r: 0.0
    rc.replied = lambda sid: True
    rc.last_prompt = lambda sid: "x"
    rc.hold_awake = lambda want: None
    rc.nudge_api_error = lambda *a: False
    rc.finish = lambda *a: None
    rc.load = lambda p: {}
    rc.save = lambda p, s: None
    rc.queue_claim = lambda why, t=None: claims.append(why)
    rc.watch_loop("/nonexistent", st, time.time(), False, time.time())
    print(len(claims))
elif case == "finish":
    # an orphan's end (its watcher gone) claims; a watched run's end leaves it to its fire path
    calls = []
    rc.queue_claim = lambda why, t=None: calls.append(why)
    rc.close_window = lambda st: None
    rc.free_lock = lambda st: None
    rc.ask_guard = lambda st: None
    rc.watcher_gone = lambda st: sys.argv[3] == "gone"
    p = os.path.join(os.environ["HOME"], "rec.json")
    st = {"session": "s9", "pid": 1, "watcher": 2}
    rc.save(p, st)
    rc.finish(p, st, "a test")
    print(len(calls))
elif case == "alive":
    # a live pid whose start time is not the record's: someone else's process (a reused pid)
    q = importlib.machinery.SourceFileLoader("dq", sys.argv[3]).load_module()
    pid = os.getpid()
    print(q.rec_alive({"pid": pid, "proc_start": "Thu Jan  1 00:00:00 1970"}), q.rec_alive({"pid": pid, "proc_start": rc.proc_start(pid)}))
PY
rcpy() { python3 "$T/rc.py" "$B/dispatch-rc" "$@"; }

echo "the queue-sweep job (S2): on every host with a home, none without"
qreset
python3 "$QB" jobs "${QC[@]}" > "$T/out"
SW="$LA/org.example.claude.queue-sweep.plist"
check "$([ -f "$SW" ] && echo yes)" "yes" "a home: the queue-sweep job is installed"
check "$(pkey "$SW" StartInterval)" "600" "  every 10 min"
check "$(pkey "$SW" ProgramArguments)" "$B/dispatch --sweep" "  running dispatch --sweep (dispatch holds the queue's context)"
has "$T/calls" "bootstrap gui/$(id -u) $SW" "  loaded"
: > "$T/calls"; python3 "$QB" jobs "${QC[@]}" > /dev/null
check "$(grep -c bootstrap "$T/calls")" "0" "  a second pass with the plist unchanged loads nothing"
check "$([ -f "$LA/org.example.claude.queue-poll.plist" ] && echo yes || echo no)" "no" "  and the poll is not loaded by it"
# S2a's landing review, item 3: a load that fails leaves no plist, so the next pass retries; an unchanged
# plist launchd does not hold is loaded again
cat > "$T/lc-fail" <<EOF
#!/bin/sh
echo "\$*" >> "$T/calls"
case "\$1" in bootstrap) exit 5;; print) exit 113;; esac
exit 0
EOF
chmod +x "$T/lc-fail"
rm -f "$SW"; : > "$T/calls"
python3 "$QB" jobs --cap 3 --launchctl "$T/lc-fail" --prefix org.example.claude --jobbin "$B/dispatch" > "$T/out"
check "$(grep -c bootstrap "$T/calls") $([ -f "$SW" ] && echo kept || echo gone)" "2 gone" "a bootstrap that fails twice: its plist removed"
has "$T/out" "did not load (launchctl bootstrap failed twice); the next dispatch here tries again" "  said so"
has "$QL" '"event": "job-unloaded"' "  and carded"
: > "$T/calls"; python3 "$QB" jobs "${QC[@]}" > /dev/null
check "$([ -f "$SW" ] && echo yes) $(grep -c bootstrap "$T/calls")" "yes 1" "  the next pass loads it"
sed 's/print) exit 113;;/print) exit 113;; bootstrap) exit 0;;/; s/bootstrap) exit 5;;//' "$T/lc-fail" > "$T/lc-gone"; chmod +x "$T/lc-gone"
: > "$T/calls"; python3 "$QB" jobs --cap 3 --launchctl "$T/lc-gone" --prefix org.example.claude --jobbin "$B/dispatch" > /dev/null
check "$(grep -c bootstrap "$T/calls")" "1" "  its plist unchanged but launchd not holding it: loaded again"
# S2a's finish review: a bootstrap refused because a racing pass loaded the job keeps its plist; a launchctl
# print past its timeout is "could not tell", never a reload of a running sweep
sed 's/print) exit 113;;/print) exit 0;;/' "$T/lc-fail" > "$T/lc-raced"; chmod +x "$T/lc-raced"
rm -f "$SW"; : > "$T/calls"
python3 "$QB" jobs --cap 3 --launchctl "$T/lc-raced" --prefix org.example.claude --jobbin "$B/dispatch" > /dev/null
check "$([ -f "$SW" ] && echo kept || echo gone)" "kept" "a bootstrap refused while launchd holds the job (another pass loaded it): its plist kept"
sed 's/print) exit 113;;/print) sleep 11; exit 113;;/' "$T/lc-fail" > "$T/lc-slow"; chmod +x "$T/lc-slow"
: > "$T/calls"
python3 "$QB" jobs --cap 3 --launchctl "$T/lc-slow" --prefix org.example.claude --jobbin "$B/dispatch" > /dev/null
check "$(grep -c 'bootout\|bootstrap' "$T/calls")" "0" "  a launchctl print past its timeout: the unchanged job is left alone"
echo off > "$REGATTA_CONFIG/wharf-runs/queue-repo"
touch "$LA/org.example.claude.queue-poll.plist"
python3 "$QB" jobs "${QC[@]}" > "$T/out"
check "$(ls "$LA" | grep -c queue-)" "0" "a home set off: both jobs removed"
has "$T/out" "no queue home here — removed" "  said"
: > "$T/calls"; python3 "$QB" jobs "${QC[@]}" > /dev/null
has "$T/calls" "bootout gui/$(id -u)/org.example.claude.queue-poll" "  a job with no plist is booted out still (S2a's finish review: a raced load left one running)"
echo "$T/queue.git" > "$REGATTA_CONFIG/wharf-runs/queue-repo"
check "$(sed -n '/^queue_jobs() {/,/^}/p' "$B/dispatch" | grep -c 'python3 "$Q" jobs')" "1" "dispatch runs it (queue_jobs)…"
check "$(grep -c '\[ "$dry" = 1 \] || queue_jobs' "$B/dispatch") $(sed -n '/^queue_dispatch() {/,/^}/p' "$B/dispatch" | grep -c 'queue_jobs')" "1 1" \
  "  …as each run starts, beside the tidier's refresh, and at each enqueue here"
check "$(sed -n '/^queue_jobs() {/,/^}/p' "$B/dispatch" | grep -c 'qkeys')" "1" "  and starts no python where no key and no job is"
echo "a label move (wharf-runs/label-prefix-previous): the previous prefix's sweep and poll go once the new sweep loads"
OSW="$LA/org.old.jobs.queue-sweep.plist"; OPO="$LA/org.old.jobs.queue-poll.plist"
python3 "$QB" jobs "${QC[@]}" > /dev/null
: > "$OSW"; : > "$OPO"; : > "$T/calls"
python3 "$QB" jobs "${QC[@]}" > "$T/out"
check "$([ -f "$OSW" ] && [ -f "$OPO" ] && echo kept)" "kept" "  no --prefix-previous: another prefix's jobs are not the queue's (today's behaviour)"
python3 "$QB" jobs "${QC[@]}" --prefix-previous org.old.jobs > "$T/out"
check "$(ls "$OSW" "$OPO" 2>/dev/null | wc -l | tr -d ' ') $([ -f "$SW" ] && echo new)" "0 new" "  with it: both removed, the new sweep in place"
has "$T/out" "removed org.old.jobs.queue-sweep, org.old.jobs.queue-poll (the previous label prefix; org.example.claude.queue-sweep sweeps)" "  said"
has "$T/calls" "bootout gui/$(id -u)/org.old.jobs.queue-sweep" "  and booted out"
: > "$OSW"
touch "$T/running.org.old.jobs.queue-sweep"
python3 "$QB" jobs "${QC[@]}" --prefix-previous org.old.jobs > /dev/null
check "$([ -f "$OSW" ] && echo kept)" "kept" "  never while it runs: this pass may be that job (its bootout would end it)"
rm -f "$T/running.org.old.jobs.queue-sweep"
python3 "$QB" jobs "${QC[@]}" --prefix-previous org.example.claude > /dev/null
check "$([ -f "$OSW" ] && [ -f "$SW" ] && echo kept)" "kept" "  a previous prefix equal to the current one is none"
rm -f "$SW"; : > "$T/calls"
python3 "$QB" jobs --cap 3 --launchctl "$T/lc-fail" --prefix org.example.claude --prefix-previous org.old.jobs --jobbin "$B/dispatch" > /dev/null
check "$([ -f "$OSW" ] && echo kept)" "kept" "  a new sweep that did not load: the old one keeps sweeping"
python3 "$QB" jobs "${QC[@]}" --prefix-previous org.old.jobs > /dev/null
check "$([ -f "$OSW" ] && echo kept || echo gone) $([ -f "$SW" ] && echo new)" "gone new" "  the next pass that loads the new one drops it"
echo off > "$REGATTA_CONFIG/wharf-runs/queue-repo"; : > "$OSW"
python3 "$QB" jobs "${QC[@]}" --prefix-previous org.old.jobs > "$T/out"
check "$(ls "$LA" | grep -c queue-)" "0" "  a home set off: the previous prefix's jobs removed too"
echo "$T/queue.git" > "$REGATTA_CONFIG/wharf-runs/queue-repo"
check "$(grep -c 'qctx+=(--prefix-previous "$lprev")' "$B/dispatch")" "1" "  dispatch hands the queue the previous prefix (wharf-runs/label-prefix-previous)"

echo "the sweep claims what nothing else would (the third review's item 17, the fourth's item 9)"
qreset
HEADROOM_SAMPLE="3 15 200" python3 "$QB" enqueue --repo "$T/repo" --branch claude/laptop/2026-10-27-mem --claim "${QC[@]}" > "$T/out"
has "$T/out" '"no_room": "memory: ' "memory refuses the claim, no run live here: left queued"
check "$(qget repo--mem state)" "queued" "  queued"
"$B/dispatch" --sweep > "$T/out" 2>&1
check "$(qget repo--mem state claimed_by)" "claimed laptop" "  memory back: the sweep job's pass (dispatch --sweep) claims it"

echo "the pending poll: loaded on a host no road reaches, with room, while an entry pends"
qreset
PO="$LA/org.example.claude.queue-poll.plist"
enq pin1 --pin buildbox
python3 "$QB" claim "${QC[@]}" > /dev/null
check "$([ -f "$PO" ] && echo yes || echo no)" "no" "an entry pinned to another host: no poll (it never becomes this host's)"
DISPATCH_QUEUE_NOW=$(date +%s) python3 "$QB" enqueue --repo "$T/repo" --branch claude/laptop/2026-10-27-p1 --refused "the run cap (3 of 3 busy on laptop)" "${QC[@]}" > /dev/null
python3 "$QB" claim "${QC[@]}" > /dev/null
check "$(qget repo--p1 state)" "queued" "an entry refused here within the hour: not claimed…"
check "$([ -f "$PO" ] && echo yes || echo no)" "yes" "  …and the poll loaded: room here, and it may become claimable"
check "$(pkey "$PO" StartInterval) $(pkey "$PO" ProgramArguments)" "60 $B/dispatch --poll" "  every 60 s, dispatch --poll"
has "$QL" '"event": "poll-loaded"' "  logged"
SWHAD=$([ -f "$SW" ] && echo 1); rm -f "$PO"; : > "$LA/org.old.jobs.queue-poll.plist"
python3 "$QB" jobs "${QC[@]}" --prefix-previous org.old.jobs > /dev/null
check "$([ -f "$LA/org.old.jobs.queue-poll.plist" ] && echo old) $([ -f "$PO" ] && echo new)" " new" \
  "a label move drops the old poll while an entry pends: the new poll loaded at once, not at the sweep's next pass"
[ -n "$SWHAD" ] || rm -f "$SW"
echo "laptop:sheep" > "$REGATTA_CONFIG/wharf-runs/kick-roads"
check "$(qpy reached)" "True" "a kick-roads line naming this host with a road: reached"
python3 "$QB" claim "${QC[@]}" > /dev/null
check "$([ -f "$PO" ] && echo yes || echo no)" "no" "  a host a road reaches: the poll booted out (the kick claims)"
echo "laptop:none" > "$REGATTA_CONFIG/wharf-runs/kick-roads"
check "$(qpy reached)" "False" "  laptop:none: not reached"
rm -f "$REGATTA_CONFIG/wharf-runs/kick-roads"
python3 "$QB" claim "${QC[@]}" > /dev/null
python3 "$QB" claim --cap 0 --launchctl "$T/launchctl" --prefix org.example.claude --jobbin "$B/dispatch" > /dev/null
check "$([ -f "$PO" ] && echo yes || echo no)" "no" "  a full host: booted out (its runs' ends claim)"
python3 "$QB" claim "${QC[@]}" > /dev/null
check "$([ -f "$PO" ] && echo yes || echo no)" "yes" "  room again: loaded again"
python3 "$QB" cancel --repo "$T/repo" --branch claude/laptop/2026-10-27-p1 "${QC[@]}" > /dev/null
python3 "$QB" cancel --repo "$T/repo" --branch claude/laptop/2026-10-27-pin1 "${QC[@]}" > /dev/null
"$B/dispatch" --poll > "$T/out" 2>&1
check "$([ -f "$PO" ] && echo yes || echo no)" "no" "the queue empty: the poll's own pass boots it out"
has "$QL" '"event": "poll-out"' "  logged before the bootout (from its own pass, the bootout ends it)"

echo "  the poll's pass: one ls-remote; a claim only when the ref moved or an entry is claimable here"
qreset
DISPATCH_QUEUE_NOW=$(date +%s) python3 "$QB" enqueue --repo "$T/repo" --branch claude/laptop/2026-10-27-p2 --refused "the cap" "${QC[@]}" > /dev/null
python3 "$QB" claim "${QC[@]}" > /dev/null
before=$(grep -c '"event": "no-room"\|"event": "claimed"' "$QL")
"$B/dispatch" --poll > "$T/out" 2>&1
check "$(grep -c '"event": "no-room"\|"event": "claimed"' "$QL")" "$before" "the ref unmoved, nothing claimable here: no claim pass"
mkdir -p "$T/home-b"
HOME="$T/home-b" python3 "$QB" enqueue --repo "$T/repo" --branch claude/laptop/2026-10-27-new --host buildbox "${QC[@]}" > /dev/null
"$B/dispatch" --poll > "$T/out" 2>&1
check "$(qget repo--new state claimed_by)" "claimed laptop" "another host's put moved the ref: the pass claims it here"
has "$T/out" "claimed fleet:repo--new" "  said"
DISPATCH_QUEUE_NOW=$(( $(date +%s) + 3700 )) "$B/dispatch" --poll > "$T/out" 2>&1
check "$(qget repo--p2 state)" "claimed" "the hour's skip over, the ref unmoved: the pass claims it"
echo "$T/no-such.git" > "$REGATTA_CONFIG/wharf-runs/queue-repo"
"$B/dispatch" --poll > "$T/out" 2>&1; check "$?" "0" "a home that does not answer: the pass exits 0…"
has "$T/out" "queue unreachable" "  …saying so (the sweep is the bound)"
echo "$T/queue.git" > "$REGATTA_CONFIG/wharf-runs/queue-repo"
echo off > "$REGATTA_CONFIG/wharf-runs/queue-repo"
"$B/dispatch" --claim > "$T/out" 2>&1; check "$?:$(wc -c < "$T/out" | tr -d ' ')" "0:0" "dispatch --claim with no home: exit 0, nothing said"
echo "$T/queue.git" > "$REGATTA_CONFIG/wharf-runs/queue-repo"
"$B/dispatch" --claim --event-at soon > /dev/null 2>&1; check "$?" "2" "--event-at takes an epoch"

echo "the watcher's claim (dispatch-rc): when its run turns parked, once a stretch; an orphan's end"
qreset
check "$(rcpy home)" "True" "a queue home: the watcher claims"
echo off > "$REGATTA_CONFIG/wharf-runs/queue-repo"; check "$(rcpy home)" "False" "  off: it never starts dispatch"
echo "$T/queue.git" > "$REGATTA_CONFIG/wharf-runs/queue-repo"
EV=$(( $(date +%s) - 30 ))
DISPATCH_QUEUE_NOW=$(( EV - 60 )) enq w1   # queued before the slot freed: the freeing is its event
DISPATCH_MAX_RUNS=3 rcpy claim "$EV" > "$T/out"
has "$T/out" "queue: claimed as a test: claimed fleet:repo--w1" "rc's queue_claim runs dispatch --claim and logs what it took"
check "$(qget repo--w1 state event_at)" "claimed $EV" "  the entry's event_at is the watcher's word (when the slot freed)"
check "$(grep '"event": "claimed"' "$QL" | tail -1 | python3 -c 'import json, sys; d = json.loads(sys.stdin.read()); print(d["event_at"], d["claim_s"] >= 30)')" \
  "$EV True" "  queue.jsonl's claimed line carries it, and the seconds to the claim"
check "$(rcpy loop busy,idle,idle,busy,waiting,busy '{}' | tail -1)" "2" "watch_loop: one claim per parked stretch (idle, then waiting)"
check "$(rcpy loop busy,idle,idle '{"yolo": 1}' | tail -1)" "0" "  never for a yolo run: its end hands the slot to its landing"
check "$(rcpy loop busy,idle '{"task_mode": "dnd"}' | tail -1)" "0" "  nor a dnd run"
check "$(rcpy loop busy,idle '{"probe": 1}' | tail -1)" "0" "  nor a probe"
check "$(rcpy finish gone | tail -1)" "1" "an orphan's end (its watcher gone): claimed, nothing else would"
check "$(rcpy finish here | tail -1)" "0" "  a watched run's end: its fire path claims, after its launch"

echo "G3's event_at: the claim stamps it, the run's started line carries it"
qreset
EV=$(( $(date +%s) - 12 ))
DISPATCH_QUEUE_NOW=$(( EV - 60 )) enq g3
python3 "$QB" claim --event-at "$EV" "${QC[@]}" > /dev/null
P=$(qplists | head -1)
check "$(pkey "$P" EnvironmentVariables DISPATCH_EVENT_AT)" "$EV" "the claimed job carries DISPATCH_EVENT_AT"
check "$(pkey "$P" EnvironmentVariables DISPATCH_YEAR)" "None" "  and no DISPATCH_YEAR: a claim in a year's last seconds is no stale job (the first review's item 6)"
DISPATCH_EVENT_AT=$EV python3 "$QB" started fleet:repo--g3 --session s-g3 --label "$(basename "$P" .plist)" "${QC[@]}" > /dev/null
check "$(grep '"event": "started"' "$QL" | tail -1 | python3 -c 'import json, sys; d = json.loads(sys.stdin.read()); print(d["event_at"], d["wait_s"] >= 12)')" \
  "$EV True" "  the started line: event_at and wait_s, G3 in one line"
EV2=$(( $(date +%s) + 5 ))
DISPATCH_QUEUE_NOW=$EV2 enq g3b
python3 "$QB" claim --event-at "$EV" "${QC[@]}" > /dev/null
check "$(qget repo--g3b event_at)" "$EV2" "  an entry queued after the slot freed: its own queueing is the event"
grep -q -- '-u DISPATCH_LOADED_AT -u DISPATCH_EVENT_AT' "$B/dispatch"; check "$?" "0" "  the session never sees DISPATCH_EVENT_AT (the env -u lists)"
check "$(grep -E -- '-u DISPATCH_LOADED_AT|unset DISPATCH_LABEL ' "$B/dispatch" | grep -vc DISPATCH_EVENT_AT)" "0" \
  "    in every list that drops DISPATCH_LOADED_AT"

echo "the S1 reviews' items carried to S2 (docs/dispatch-queue-s1-review-*.md)"
qreset
check "$(qpy noreap "$T/repo" | tail -1)" "False 0 False" "S2a review item 1: the queue's claim reaps nothing, and its process never claims from finish()"
qreset
check "$(rcpy alive "$QB")" "False True" "first review's item 2: a live pid with another start time is not the run (a reused pid)"
check "$(qpy git-count "$T/queue.git")" "4 1 True" "first review's item 7, fourth's item 15: five entries written in 4 git calls; read in two, ls-tree counted here and cat-file --batch run apart (S2a review, item 7.10)"
qreset
qpy contended "$T/queue.git" 9 "$T/repo" claude/laptop/2026-10-27-c5 > "$T/out" 2>/dev/null
has "$T/out" '"offline": "the lease lost 3 times' "fourth review's item 11: a put that lost the lease thrice says so (the outbox), never 'online'"
check "$(ls "$HL/Caches/run-seed/queue/outbox" | wc -l | tr -d ' ')" "1" "  it waits in the outbox"
"$B/dispatch" --sweep > /dev/null 2>&1
check "$(qget repo--c5 state) $(ls "$HL/Caches/run-seed/queue/outbox" | wc -l | tr -d ' ')" "claimed 0" "first review's item 5: the sweep job's pass lands it (and claims it: room here)"
qreset
qpy contended "$T/queue.git" 3 "$T/repo" claude/laptop/2026-10-27-c6 > "$T/out" 2>/dev/null
check "$(qget repo--c6 state) $(ls "$HL/Caches/run-seed/queue/outbox" 2>/dev/null | wc -l | tr -d ' ')" "queued 0" \
  "  a lease lost thrice, then free: enqueue flushes once more at once, and the put lands"
has "$T/out" '"offline": null' "  and nothing waits"
qreset
qpy stale-retry "$T/queue.git" "$T/repo" claude/laptop/2026-10-27-c7 > "$T/out" 2> "$T/err"
check "$?:$(grep -c '"result": "queued"' "$T/out")" "1:0" "S2a review item 5: the retry's flush finds the key another branch's: exit 1 (a one-shot), never 'queued'"
has "$T/err" "is another branch's" "  said why"
check "$(qget repo--c7 branch) $(ls "$HL/Caches/run-seed/queue/outbox" 2>/dev/null | wc -l | tr -d ' ')" "claude/studio/2026-10-27-c7 0" "  the other host's entry stands, and nothing waits"
check "$(grep -c 'waits in this Mac.s outbox (\$q_off)' "$B/dispatch")" "1" "  dispatch says why it waits there, not 'did not answer' alone"
qreset
check "$(qpy spent)" "fleet:w fleet:y fleet:z" "first review's item 10: a reservation whose job exited (its plist gone) is spent; its plist kept, young or its claimer alive, held"
rm_own "$HL/Caches/run-seed/queue/claims"; mkdir -p "$HL/Caches/run-seed/queue/claims"
printf '{"qid": "fleet:u", "at": %s, "label": "L1"}' "$(date +%s)" > "$HL/Caches/run-seed/queue/claims/fleet_u.a.json"
printf '{"qid": "fleet:u", "at": %s, "label": "L2"}' "$(date +%s)" > "$HL/Caches/run-seed/queue/claims/fleet_u.b.json"
python3 "$QB" unreserve fleet:u --label L1 "${QC[@]}"
check "$(ls "$HL/Caches/run-seed/queue/claims" | tr '\n' ' ')" "fleet_u.b.json " "  a stale job gives its own reservation back at once (unreserve, by its label)"
python3 "$QB" unreserve fleet:u "${QC[@]}" 2>/dev/null; check "$?" "2" "  never without a label (a newer claim's slot)"
check "$(grep -c 'queue_unreserve; exit 0' "$B/dispatch")" "2" "  dispatch's two stale exits call it"
# wharf's runs_busy counts the reservations beside the runs (the first review's item 10)
printf '#!/bin/sh\necho 1\n' > "$T/rc-stub"; printf '#!/bin/sh\necho 2\n' > "$T/q-stub"; chmod +x "$T/rc-stub" "$T/q-stub"
check "$(WHARF_DISPATCH_RC="$T/rc-stub" WHARF_DISPATCH_QUEUE="$T/q-stub" DISPATCH_MAX_RUNS=5 python3 -c '
import importlib.machinery, sys
w = importlib.machinery.SourceFileLoader("w", sys.argv[1]).load_module()
s = w.Ship.__new__(w.Ship); s.repo = sys.argv[2]
print(s.runs_busy(sys.argv[2] + "/2026-10-27-x"))' "$B/wharf" "$T/repo")" "(3, 5)" "  wharf's runs_busy: 1 run and 2 reservations, against the cap"
rm_own "$HL/Caches/run-seed/queue/claims"
check "$(WHARF_DISPATCH_RC="$T/rc-stub" WHARF_DISPATCH_QUEUE="$T/q-stub" DISPATCH_MAX_RUNS=5 python3 -c '
import importlib.machinery, sys
w = importlib.machinery.SourceFileLoader("w", sys.argv[1]).load_module()
s = w.Ship.__new__(w.Ship); s.repo = sys.argv[2]
print(s.runs_busy(sys.argv[2] + "/2026-10-27-x"))' "$B/wharf" "$T/repo")" "(1, 5)" "    no claims folder: no queue call"
check "$(qpy raise "$T/repo" dnd dnd)" "none" "fourth review's item 12: an unattended caller's own mode, inherited as the hint, is no raise"
check "$(qpy lowered "$T/repo" | tail -1)" "none | mode dnd over default is a raise" \
  "S2a review item 4: a dnd caller's own mode onto its own branch is no raise; onto a sibling the owner lowered, refused (main's refusal)"
qpy raise "$T/repo" default yolo > "$T/out"; grep -q "raise" "$T/out"; check "$?" "0" "  a yolo hint is judged (never inherited)"
check "$(qpy lowered "$T/repo" forged | tail -1)" "mode dnd over default is a raise" \
  "S2a finish review S1: a run started at default that sets DISPATCH_MODE=dnd itself is judged on its own branch (its record's mode, never its word)"
env -u DISPATCH_LABEL CLAUDE_UNATTENDED=dispatch DISPATCH_MODE=default python3 "$QB" enqueue --repo "$T/repo" --branch claude/laptop/2026-10-27-r12 --env DISPATCH_MODE=yolo "${QC[@]}" > /dev/null 2> "$T/err"
check "$?" "2" "  refused, exit 2…"
has "$T/err" "the next step waits for a run to end" "  …with the cap's waiting words (AGENTS.md: a new refusal reuses them)"
check "$(sed -n '/^queue_args() {/,/^}/p' "$B/dispatch" | grep -c '\[ "\$mode_given" = 1 \] && \[ -n "\$mode" \]')" "1" "  dispatch passes --mode only when one was given"
check "$(sed -n '/^qreserved() {/,/^}/p' "$B/dispatch" | grep -c 'queue_on')" "0" "fourth review's item 14: qreserved starts one python, not queue_on's too"
check "$(sed -n '/^queue_dispatch() {/,/^}/p' "$B/dispatch" | grep -c 'python3 -c')" "0" "  and queue_dispatch reads the enqueue's answer in qparse's one start"
qreset

echo "S2a's landing review, item 6: the new verbs meet the old guards"
for v in "--claim" "--poll" "--event-at 1" "--kick fleet:x" "--claim --full laptop --from laptop" "--claim --from-stream"; do
  WEEKLY_RUN=t "$B/dispatch" claude/laptop/2026-10-27-wk --repo "$T/repo" --at reset --if-room $v > /dev/null 2> "$T/err"
  check "$?:$(grep -c 'under WEEKLY_RUN=t only' "$T/err")" "2:1" "WEEKLY_RUN refuses the one shape with $v"
done
for r in 'dispatch --claim' 'dispatch --poll' 'dispatch-queue poll' 'dispatch-queue jobs' 'dispatch-queue unreserve' 'dispatch --kick' 'dispatch-queue kick' 'dispatch-rc kick-listen'; do
  check "$(grep '^denied=(' "$B/dispatch" | grep -cF "\"Bash(*$r*)\"")" "1" "  a run's deny list names $r"
done


echo "S5: eligibility — a host claims by its feature line, the pin and the scope's berths (docs/dispatch-queue-contract-2026-10-25.md)"
qreset
FEAT="$REGATTA_CONFIG/wharf-runs/features"
printf 'laptop:feat-a\nbuildbox:feat-b,Feat-C\n' > "$FEAT"
RK="$(cd "$T/repo" && pwd -P)"
Q5=(python3 "$QB" enqueue --repo "$T/repo" "${QC[@]}")
claim_as() { DISPATCH_HOST=$1 python3 "$QB" claim "${QC[@]}" > /dev/null 2>&1; }
"${Q5[@]}" --branch claude/laptop/2026-10-29-n5a --needs feat-b > "$T/out" 2>&1; check "$?" "0" "an entry with a need only the other host meets is queued"
check "$(qget repo--n5a state needs)" "queued ['feat-b']" "  carrying its needs"
claim_as laptop
check "$(qget repo--n5a state claimed_by)" "queued None" "  the host without the feature skips it…"
DISPATCH_HOST=laptop python3 "$QB" list --all "${QC[@]}" > "$T/out" 2>&1
has "$T/out" "not here: laptop lacks feat-b" "  …and says why in the listing"
has "$T/out" "needs feat-b" "  …with the need named"
claim_as buildbox
check "$(qget repo--n5a state claimed_by)" "claimed buildbox" "  the host whose line names it claims it"
qreset
echo "  a need is met by every name on the line, and names are case-folded"
"${Q5[@]}" --branch claude/laptop/2026-10-29-n5b --needs feat-b,feat-c > /dev/null 2>&1; claim_as buildbox
check "$(qget repo--n5b state claimed_by)" "claimed buildbox" "  two needs, both on the line (the line's Feat-C folds)"
qreset
"${Q5[@]}" --branch claude/laptop/2026-10-29-n5c --needs feat-b,feat-a > "$T/out" 2>&1
check "$?" "3" "needs no single host meets together (feat-a is laptop's, feat-b buildbox's): exit 3"
qreset
echo "  at enqueue: a need no host meets is exit 3, and never queued"
"${Q5[@]}" --branch claude/laptop/2026-10-29-n5d --needs feat-z > "$T/out" 2> "$T/err"; check "$?" "3" "a need nobody meets: exit 3"
has "$T/err" "no host meets this run" "  …naming it"
has "$T/err" "laptop lacks feat-z" "  …and each host's reason"
check "$(qget repo--n5d state)" "" "  nothing reached the queue"
check "$(wc -c < "$T/out" | tr -d ' ')" "0" "  and stdout is empty, so dispatch reads no entry"
"${Q5[@]}" --branch claude/laptop/2026-10-29-n5d --needs 'Feat Z' > /dev/null 2>&1; check "$?" "2" "a malformed name is a usage error, exit 2"
"${Q5[@]}" --branch claude/laptop/2026-10-29-n5e --needs feat-b --pin laptop > "$T/out" 2> "$T/err"; check "$?" "3" "a need met only off the pin: exit 3 too"
has "$T/err" "buildbox: pinned to laptop" "  the pin is a reason like any"
printf 'buildbox:feat-b\n' > "$FEAT"
"${Q5[@]}" --branch claude/laptop/2026-10-29-n5f --needs feat-a > /dev/null 2>&1; check "$?" "3" "a host with no line meets no need (laptop's line is gone)"
rm -f "$FEAT"
"${Q5[@]}" --branch claude/laptop/2026-10-29-n5g --needs feat-a > /dev/null 2>&1; check "$?" "3" "no features file at all: no host meets a need"
"${Q5[@]}" --branch claude/laptop/2026-10-29-n5h > /dev/null 2>&1; check "$?" "0" "an entry with no needs asks for no line"
qreset
echo "  the pin"
printf 'laptop:feat-a\nbuildbox:feat-b\n' > "$FEAT"
"${Q5[@]}" --branch claude/laptop/2026-10-29-n5i --pin buildbox > /dev/null 2>&1
claim_as laptop
check "$(qget repo--n5i state claimed_by)" "queued None" "a pinned entry is not claimed off its pin"
claim_as buildbox
check "$(qget repo--n5i state claimed_by)" "claimed buildbox" "  and is claimed on it"
qreset
echo "  the scope's berths and the repo's clone hosts (berth's filters)"
printf '{"repos": {"%s": {"hosts": ["buildbox"]}}}\n' "$RK" > "$T/repos.json"
export CLAUDE_REPOS_JSON="$T/repos.json"
"${Q5[@]}" --branch claude/laptop/2026-10-29-n5j > /dev/null 2>&1; check "$?" "0" "a repo cloned on one host only: queued"
claim_as laptop
check "$(qget repo--n5j state claimed_by)" "queued None" "  the other host, left out by the clone hosts, skips it"
claim_as buildbox
check "$(qget repo--n5j state claimed_by)" "claimed buildbox" "  the named host claims it"
qreset
printf '{"repos": {"%s": {"hosts": ["elsewhere"]}}}\n' "$RK" > "$T/repos.json"
"${Q5[@]}" --branch claude/laptop/2026-10-29-n5k > "$T/out" 2> "$T/err"; check "$?" "3" "berths and clone hosts that share none with the fleet: exit 3, never queued"
printf '{"repos": {"%s": {"hosts": ["laptop", "buildbox"]}}, "scopes": {"s": {"repos": ["%s"], "berths": ["buildbox"]}}}\n' "$RK" "$RK" > "$T/repos.json"
"${Q5[@]}" --branch claude/laptop/2026-10-29-n5l > /dev/null 2>&1; claim_as laptop
check "$(qget repo--n5l state claimed_by)" "queued None" "a scope whose berths leave a host out: that host skips the entry"
claim_as buildbox
check "$(qget repo--n5l state claimed_by)" "claimed buildbox" "  the berth claims it"
qreset
printf '{"repos": {' > "$T/repos.json"
"${Q5[@]}" --branch claude/laptop/2026-10-29-n5m > /dev/null 2>&1; check "$?" "2" "a torn registry refuses the enqueue (the fence's rule)"
unset CLAUDE_REPOS_JSON; qreset
echo "  the sweep cards an entry no host may claim, naming each host's reason — each host's own word, never a peer's file"
printf 'laptop:feat-a\nbuildbox:feat-b\n' > "$FEAT"
"${Q5[@]}" --branch claude/laptop/2026-10-29-n5n --needs feat-b > /dev/null 2>&1
printf 'laptop:feat-a\n' > "$FEAT"
LATE=$(( $(date +%s) + 1500 ))
DISPATCH_QUEUE_NOW=$LATE python3 "$QB" sweep "${QC[@]}" > "$T/out" 2>&1
check "$(grep -c 'queue-unclaimed' "$T/out")" "0" "one host's sweep alone: no card (its config says the peer lacks it, but the peer's own word is the proof)"
check "$(qget repo--n5n inelig_laptop)" "$LATE" "  …it writes its own word on the entry"
DISPATCH_HOST=buildbox DISPATCH_QUEUE_NOW=$LATE python3 "$QB" sweep "${QC[@]}" > "$T/out" 2>&1
has "$T/out" "card queue-unclaimed: fleet:repo--n5n — no host may claim it (" "the other host's sweep, past two sweeps: a card…"
has "$T/out" "laptop lacks feat-b" "  …with the reasons"
DISPATCH_HOST=buildbox DISPATCH_QUEUE_NOW=$LATE python3 "$QB" sweep "${QC[@]}" > "$T/out" 2>&1
check "$(grep -c 'queue-unclaimed' "$T/out")" "0" "  once per entry"
printf 'laptop:feat-a\nbuildbox:feat-b\n' > "$FEAT"
DISPATCH_HOST=buildbox DISPATCH_QUEUE_NOW=$LATE python3 "$QB" sweep "${QC[@]}" > /dev/null 2>&1
check "$(qget repo--n5n state claimed_by)" "claimed buildbox" "a host whose line is back claims it (the entry was never stuck)"
qreset
echo "  a named host that never sweeps blocks no card: past six sweeps it counts by this host's config (S5's landing review)"
printf 'laptop:feat-a\nbuildbox:feat-b\n' > "$FEAT"
"${Q5[@]}" --branch claude/laptop/2026-10-29-n5v --needs feat-b > /dev/null 2>&1
printf 'laptop:feat-a\n' > "$FEAT"
DISPATCH_QUEUE_NOW=$(( $(date +%s) + 3900 )) python3 "$QB" sweep "${QC[@]}" > "$T/out" 2>&1
has "$T/out" "card queue-unclaimed: fleet:repo--n5v — no host may claim it (" "one host's sweep, the peer silent an hour: a card…"
has "$T/out" "buildbox: no word from its sweep in 65 min (by laptop's config:" "  …naming the silence and whose config judged it"
qreset
echo "  a torn registry writes no word on the entries for that sweep"
"${Q5[@]}" --branch claude/laptop/2026-10-29-n5w --needs feat-a > /dev/null 2>&1
printf '{"repos": {' > "$T/repos-torn.json"
CLAUDE_REPOS_JSON="$T/repos-torn.json" DISPATCH_QUEUE_NOW=$(( $(date +%s) + 3900 )) python3 "$QB" sweep "${QC[@]}" > "$T/out" 2>&1
check "$(qget repo--n5w inelig_laptop):$(grep -c 'queue-unclaimed' "$T/out")" "None:0" "  …and fires no card"
qreset
echo "  two cards of one entry fire once each (the review: one mark per entry overwrote the other)"
printf 'laptop:feat-a\nbuildbox:feat-b\n' > "$FEAT"
"${Q5[@]}" --branch claude/laptop/2026-10-29-n5o --needs feat-b > /dev/null 2>&1
cat > "$T/cards.py" <<'PY2'
import contextlib, importlib.machinery, io, os
q = importlib.machinery.SourceFileLoader("dq", os.environ["QB"]).load_module()
q.card("queue-unclaimed", "fleet:k", {"id": "1"}, "a", mark="1", say=False)
q.card("queue-stuck", "fleet:k", {"claimed_at": 1, "attempts": 4}, "b", say=False)
b = io.StringIO()
with contextlib.redirect_stdout(b):
    q.card("queue-unclaimed", "fleet:k", {"id": "1"}, "a", mark="1")
    q.card("queue-stuck", "fleet:k", {"claimed_at": 1, "attempts": 4}, "b")
print("refired" if b.getvalue() else "once each")
PY2
check "$(QB="$QB" python3 "$T/cards.py")" "once each" "an unclaimed card and a stuck card of one entry, written again: neither fires twice"
qreset
echo "  a node-local queue is claimed by this host alone: the peers' lines cannot help it (the review's WRONG 1)"
printf '{"repos": {}, "scopes": {"vault": {"confidential": true, "repos": ["%s"]}}}' "$RK" > "$T/repos.json"
export CLAUDE_REPOS_JSON="$T/repos.json"
printf 'buildbox:feat-b\n' > "$FEAT"
"${Q5[@]}" --branch claude/laptop/2026-10-29-n5p --needs feat-b > "$T/out" 2> "$T/err"; check "$?" "3" "a need only a peer meets, for a run that never leaves this host: exit 3"
has "$T/err" "laptop has no feature line, so lacks feat-b" "  naming this host alone"
unset CLAUDE_REPOS_JSON; qreset
echo "  a host with a feature line and no ssh alias here is a host (a VM): its need is met"
printf 'laptop:feat-a\nvm1:feat-v\n' > "$FEAT"
"${Q5[@]}" --branch claude/laptop/2026-10-29-n5q --needs feat-v > /dev/null 2>&1; check "$?" "0" "enqueue judges every host the config names, not only this Mac's ssh peers"
qreset
echo "  a feature line split one word per line (the overlay's bootstrap) keeps its host (S5's landing review)"
printf 'laptop:feat-a,\nfeat-b\nbuildbox:feat-c\n' > "$FEAT"
cat > "$T/featsplit.py" <<'PY2'
import importlib.machinery, os
q = importlib.machinery.SourceFileLoader("dq", os.environ["QB"]).load_module()
print(sorted((h, sorted(v)) for h, v in q.features().items()))
PY2
check "$(QB="$QB" python3 "$T/featsplit.py")" "[('buildbox', ['feat-c']), ('laptop', ['feat-a', 'feat-b'])]" "  …a line with no colon continues the host before it, never a host of its own"
echo "  an entry is data: a needs that is no list of names is skipped, and breaks neither the claim nor the listing"
"${Q5[@]}" --branch claude/laptop/2026-10-29-n5r > /dev/null 2>&1
cat > "$T/badneeds.py" <<'PY2'
import importlib.machinery, os
q = importlib.machinery.SourceFileLoader("dq", os.environ["QB"]).load_module()
print(q.Fleet(q.home()).do([{"op": "set", "key": "repo--n5r", "fields": {"needs": True}, "cond": {"state": "queued"}}], "t")[0])
PY2
QB="$QB" python3 "$T/badneeds.py" > /dev/null
claim_as laptop; DISPATCH_HOST=laptop python3 "$QB" list --all "${QC[@]}" > "$T/out" 2>&1; check "$?" "0" "a needs of true: the claim and the listing survive"
has "$T/out" "needs is not a list of feature names" "  …the listing says why it is not claimed"
qreset
echo "  a mixed-version fleet: the entry carries --needs as a flag too, which a host that predates S5 does not know"
printf 'laptop:feat-a\nbuildbox:feat-b\n' > "$FEAT"
"${Q5[@]}" --branch claude/laptop/2026-10-29-n5s --needs feat-b > /dev/null 2>&1
check "$("${QGIT[@]}" show refs/regatta/queue:queue/repo--n5s.json | python3 -c 'import json, sys; print(json.load(sys.stdin)["args"])')" "['--needs', 'feat-b']" "the entry's args hold it"
printf 'laptop:feat-a,feat-b\nbuildbox:feat-b\n' > "$FEAT"
"${Q5[@]}" --branch claude/laptop/2026-10-29-n5t --needs feat-b,feat-a --arg=--needs --arg=feat-b,feat-a > "$T/out" 2>&1
check "$?" "0" "a carried --needs in another order than the entry's sorted needs is the same set: queued (S5's landing review)"
"${Q5[@]}" --branch claude/laptop/2026-10-29-n5u --needs feat-a --arg=--needs --arg=feat-b > "$T/out" 2>&1
check "$?:$(grep -c "needs differ" "$T/out")" "1:1" "  a carried --needs naming other features is still refused"
echo "  claimable stays one function: the claim, the listing and the poll ask it, and it asks eligibility"
check "$(sed -n '/^def claimable(/,/^def bad_args(/p' "$B/dispatch-queue" | grep -c 'eligibility(e, h)')" "1" "claimable calls eligibility once"
echo "S5: dispatch — --needs, the berth pick retired, no home"
check "$(sed -n '/^queue_dispatch() {/,/^}/p' "$B/dispatch" | grep -c 'needs:+--needs')" "1" "queue_dispatch passes --needs to the enqueue"
check "$(grep -c 'needs:+--needs' "$B/dispatch")" "3" "  as do the fire-time enqueues (a one-shot's, a refusal's)"
check "$(grep -c '<string>--needs</string>' "$B/dispatch")" "1" "  and a one-shot's plist carries it to its fire time"
BRN=claude/laptop/2026-10-29-dn
"$B/dispatch" $BRN --repo "$T/repo" --needs 'Feat Z' --dry-run > /dev/null 2> "$T/err"; check "$?" "2" "dispatch refuses a malformed need"
has "$T/err" "--needs takes lower-case feature names" "  saying how"
rm -f "$REGATTA_CONFIG/wharf-runs/queue-repo"
"$B/dispatch" $BRN --repo "$T/repo" --needs feat-a --dry-run > /dev/null 2> "$T/err"
has "$T/err" "--needs ignored — no queue home here" "no queue home: the need is said and dropped"
echo "$T/queue.git" > "$REGATTA_CONFIG/wharf-runs/queue-repo"
WEEKLY_RUN=t "$B/dispatch" claude/laptop/2026-10-27-wk --repo "$T/repo" --at reset --if-room --needs feat-a > /dev/null 2> "$T/err"
check "$?:$(grep -c 'under WEEKLY_RUN=t only' "$T/err")" "2:1" "WEEKLY_RUN refuses the one shape with --needs"
rm -f "$FEAT"

# ---- S10(c): the watcher's sleep notice — powerlib's stand-in (DISPATCH_POWER_FAKE) for the OS ----------------
# Two watchers of one Mac: each loads dispatch-rc and runs watch() with its loop stood in; the loop says it is
# ready, then "its run ends" once its watcher has acknowledged the sleep. The requeue is a stand-in that notes its
# words and environment and takes 2 s, past the 0.5 s hold, so a watcher that returned at its run's end would
# return before it.
qreset
mkdir -p "$T/pw"; rm -f "$T/pw"/*
cat > "$T/rqstub" <<EOF
#!/bin/sh
echo "\$* locked=\${DISPATCH_REQUEUE_LOCKED:-} unattended=\${CLAUDE_UNATTENDED:-none}" >> "$T/pw/calls"
sleep 2
echo done >> "$T/pw/done"
EOF
chmod +x "$T/rqstub"
cat > "$T/pw.py" <<'PYPW'
import importlib.machinery as m, importlib.util as u, os, sys, time
l = m.SourceFileLoader("rc", sys.argv[1]); rc = u.module_from_spec(u.spec_from_loader("rc", l)); l.exec_module(rc)
d = sys.argv[2]
rc.load = lambda p: {"session": "s-pw"}
rc.save = lambda p, st: None
rc.hold_awake = lambda want: None
def loop(path, st, start, busy, started):
    open(os.path.join(d, "ready.%d" % os.getpid()), "w").close()
    while not os.path.exists(os.path.join(d, "ack.%d" % os.getpid())):
        time.sleep(0.1)
    return 0   # its run ended: the requeue ended it
rc.watch_loop = loop
rc.watch("x")
print("returned done=%s" % os.path.exists(os.path.join(d, "done")))
PYPW
pw() { DISPATCH_POWER_FAKE="$T/pw" DISPATCH_REQUEUE_BIN="$T/rqstub" DISPATCH_REQUEUE_ACK_S=0.5 CLAUDE_UNATTENDED=dispatch \
       python3 "$T/pw.py" "$B/dispatch-rc" "$T/pw" > "$T/pw/out.$1" 2>&1; }
echo "$T/queue.git" > "$REGATTA_CONFIG/wharf-runs/queue-repo"
pw a & pa=$!; pw b & pb=$!
for _ in $(seq 1 100); do [ "$(ls "$T/pw"/ready.* 2>/dev/null | wc -l | tr -d ' ')" = 2 ] && break; sleep 0.1; done
touch "$T/pw/willsleep.1"
wait $pa $pb
check "$(wc -l < "$T/pw/calls" | tr -d ' ')" "1" "S10(c) a sleep notice: one watcher of the Mac runs the requeue…"
check "$(cat "$T/pw/calls")" "--requeue --all --why lid locked=1 unattended=none" "  …--requeue --all --why lid, the lock its own, no unattended mark carried"
check "$(ls "$T/pw"/ack.* | wc -l | tr -d ' ')" "2" "  …both watchers acknowledge the sleep (the other at once)"
check "$(grep -l 'going to sleep: --requeue' "$T/pw"/out.a "$T/pw"/out.b | xargs grep -h '^returned')" "returned done=True" \
  "  …and the one that runs it does not return before it ends, though its own run ended at the acknowledgement"
grep -q 'still going after 0 s: acknowledging the sleep' "$T/pw"/out.a "$T/pw"/out.b && r=ok || r="$(cat "$T/pw"/out.a "$T/pw"/out.b)"
check "$r" ok "  …a requeue past the hold: the sleep is acknowledged, the requeue goes on"
rm -f "$REGATTA_CONFIG/wharf-runs/queue-repo"; rm -f "$T/pw"/*; pw c & pc=$!
for _ in $(seq 1 50); do ls "$T/pw"/ready.* > /dev/null 2>&1 && break; sleep 0.1; done
touch "$T/pw/willsleep.2"; sleep 1
for r in "$T/pw"/ready.*; do touch "$T/pw/ack.${r##*.}"; done   # the watcher's own pid (its ready file's): no notice acknowledged it
wait $pc
check "$([ -f "$T/pw/calls" ] && echo ran || echo none)" "none" "  with no queue home, no sleep notice is taken: nothing to hand a run to"

# ---- S10(g): a writes-only queue home, and no claim in a DarkWake ----------------------------------------------
qreset
echo "$T/queue.git" > "$REGATTA_CONFIG/wharf-runs/queue-repo"
printf 'studio:claim\nlaptop:writes\n' > "$REGATTA_CONFIG/wharf-runs/queue-mode"
DISPATCH_HOST=laptop python3 "$QB" home > /dev/null; check "$?" "1" "S10(g) queue-mode writes: \`home\` says none, so dispatch enqueues nothing of this host's own"
DISPATCH_HOST=studio python3 "$QB" home > /dev/null; check "$?" "0" "  …another host's line keeps its home"
DISPATCH_HOST=laptop python3 "$QB" claim "${QC[@]}" > "$T/out" 2>&1
check "$(grep -c '"claim-skipped".*writes' "$QL")" "1" "  …it claims nothing"
DISPATCH_HOST=laptop python3 "$QB" sweep "${QC[@]}" > "$T/out" 2>&1
has "$T/out" "(queue-mode writes): 0 op(s) from the outbox written" "  …its sweep replays its outbox and judges no entry"
DISPATCH_HOST=laptop python3 "$QB" jobs "${QC[@]}" > /dev/null 2>&1
check "$([ -f "$LA/org.example.claude.queue-sweep.plist" ] && echo yes)" "yes" "  …and it still gets the sweep job, which replays a requeue owed since the sleep"
rm -f "$REGATTA_CONFIG/wharf-runs/queue-mode"
printf '#!/bin/sh\necho "Current System Capabilities are: CPU Network "\necho "Current Power State: 4"\n' > "$T/pmset-dark"
printf '#!/bin/sh\necho "Current System Capabilities are: CPU Graphics Audio Network "\n' > "$T/pmset-awake"
chmod +x "$T/pmset-dark" "$T/pmset-awake"
: > "$QL"; DISPATCH_PMSET="$T/pmset-dark" python3 "$QB" claim "${QC[@]}" > /dev/null 2>&1
check "$(grep -c '"claim-skipped".*DarkWake' "$QL")" "1" "  no host claims in a DarkWake (pmset's capabilities lack Graphics)"
: > "$QL"; DISPATCH_PMSET="$T/pmset-awake" python3 "$QB" claim "${QC[@]}" > /dev/null 2>&1
check "$(grep -c '"claim-skipped"' "$QL")" "0" "  …and claims as before once fully awake"
rm -f "$REGATTA_CONFIG/wharf-runs/queue-repo"
# ---- S8: the kick roads (docs/dispatch-queue-kick-2026-10-25.md) -------------------------------------------------
# Every road is a stand-in: ssh, orca and the spacesheep press record their words and touch no host. The kick runs
# in this process (DISPATCH_KICK_SYNC) so its verdicts are read at once; kicks.jsonl is the record.
qreset
echo "$T/queue.git" > "$REGATTA_CONFIG/wharf-runs/queue-repo"
KJ="$HL/Logs/claude-weekly/kicks.jsonl"; KR="$REGATTA_CONFIG/wharf-runs/kick-roads"; KD="$HL/Caches/run-seed/queue/kicks"
cat > "$T/ssh" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$T/ssh.calls"
exit 0
EOF
CN="$(basename "$(head -1 "$REGATTA_CONFIG/home")")"
cat > "$T/orca" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$T/orca.calls"
case "\$1 \$2" in
  "repo list") printf '{"ok":true,"result":{"repos":[{"path":"/peer/$CN"}]}}\n';;
  "terminal create") printf '{"ok":true,"result":{"terminal":{"handle":"term-1"}}}\n';;
  "terminal wait") printf '{"ok":true,"result":{"wait":{"satisfied":true,"exitCode":%s}}}\n' "\${ORCA_EXIT:-0}";;
  *) printf '{"ok":true,"result":{}}\n';;
esac
EOF
cat > "$T/press" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$T/press.calls"
exit \${PRESS_RC:-0}
EOF
chmod +x "$T/ssh" "$T/orca" "$T/press"
export DISPATCH_SSH="$T/ssh" DISPATCH_ORCA="$T/orca" DISPATCH_SHEEP_PRESS="$T/press" DISPATCH_KICK_SYNC=1
kreset() { rm -f "$T/ssh.calls" "$T/orca.calls" "$T/press.calls" "$KJ" "$REGATTA_CONFIG/wharf-runs/orca-pairs"; }

kreset; rm -f "$KR"
DISPATCH_HOST=laptop python3 "$QB" enqueue --repo "$T/repo" --branch claude/laptop/2026-10-30-k0 "${QC[@]}" > /dev/null 2>&1
check "$([ -f "$T/ssh.calls" ] && echo kicked || echo none)" "none" "S8: no kick-roads file, no kick (the switch, as queue-repo is the queue's)"
check "$(qpy reached-of buildbox)" "False" "  …and no host reads as reached"
python3 "$QB" kick fleet:repo--k0 "${QC[@]}" > "$T/out" 2>&1; has "$T/out" "kick: off" "  dispatch-queue kick says the kick is off"

echo "buildbox:ssh" > "$KR"; kreset
python3 "$QB" enqueue --repo "$T/repo" --branch claude/laptop/2026-10-30-k1 "${QC[@]}" > "$T/out" 2>&1
check "$(wc -l < "$T/ssh.calls" | tr -d ' ')" "1" "an enqueue this host did not take kicks the peer once, over the road its line names"
has "$T/ssh.calls" "BatchMode=yes -o ConnectTimeout=10 buildbox-ssh" "  ssh through the peer's wharf-runs/ssh alias, batch mode"
has "$T/ssh.calls" '/modules/wharf-runs/bin/dispatch" --claim --full laptop --from laptop' "  the peer's core from its own home file; the receiver's --claim --full --from"
check "$(sed 's/.*bin\/dispatch"//' "$T/ssh.calls" | grep -c '[/]')" "0" "  the payload names hosts only: no path, branch, repo or scope after the receiver's own path"
check "$(grep -c 'claude/\|k1\|repo' "$T/ssh.calls")" "0" "  …nor the entry's branch, topic or repo anywhere on the line"
has "$KJ" '"ok": true, "road": "ssh"' "  the verdict in kicks.jsonl"
check "$(qget repo--k1 state)" "queued" "  the entry stays queued: a kick carries nothing, the peer's sweep claims"

echo "buildbox:sheep,ssh" > "$KR"; kreset
PRESS_RC=1 python3 "$QB" kick fleet:repo--k1 "${QC[@]}" > "$T/out" 2>&1
check "$(grep -c '"road": "sheep"' "$KJ") $(grep -c '"ok": true, "road": "ssh"' "$KJ")" "1 1" "a road that fails passes the kick to the next its line names (sheep, then ssh)"
has "$T/press.calls" 'kick/buildbox kick {"from": "laptop", "full": ["laptop"], "kick": 1}' "  the press: kick on kick/buildbox, its data {from, full} and nothing else"
kreset; python3 "$QB" kick fleet:repo--k1 "${QC[@]}" > "$T/out" 2>&1
check "$([ -f "$T/ssh.calls" ] && echo ssh || echo first)" "first" "  the first road that takes it ends the kick"
printf 'buildbox:kick/shared-one\n' > "$REGATTA_CONFIG/wharf-runs/kick-stream"; kreset
python3 "$QB" kick fleet:repo--k1 "${QC[@]}" > /dev/null 2>&1
has "$T/press.calls" "kick/shared-one kick" "  a shared listener's stream, as wharf-runs/kick-stream names it"
rm -f "$REGATTA_CONFIG/wharf-runs/kick-stream"

echo "buildbox:none" > "$KR"; kreset
python3 "$QB" kick fleet:repo--k1 "${QC[@]}" > /dev/null 2>&1
check "$([ -f "$T/ssh.calls" ] && echo kicked || echo none)" "none" "buildbox:none: no road is tried"
has "$KJ" '"why": "no road (kick-roads)"' "  said in kicks.jsonl"
check "$(qpy reached-of buildbox)" "False" "  …and the host is not reached (the poll is its way)"

echo "elsewhere:none" > "$KR"; kreset
python3 "$QB" kick fleet:repo--k1 "${QC[@]}" > /dev/null 2>&1
has "$KJ" '"source": "derived"' "no line for the peer: its roads derived from what exists (S2a review, item 12)"
check "$(wc -l < "$T/ssh.calls" | tr -d ' ')" "1" "  ssh, where wharf-runs/ssh has its alias"
check "$(qpy reached-of buildbox)" "True" "  …and reached() reads the same: an alias for it, the kick on"
check "$(qpy reached-of nohost)" "False" "  a host nothing reaches is not"

kl_line() { python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import kicklib; print(kicklib.line_of(sys.argv[2]))' "$B" "$1"; }
printf 'buildbox:\nsheep,\nssh\n' > "$KR"
check "$(kl_line buildbox)" "['sheep', 'ssh']" "the S8 review: a value the overlay wrote one word per line reads as one line"
printf 'buildbox:orca,ssh   (derived from laptop)\n' > "$KR"
check "$(kl_line buildbox)" "['orca', 'ssh']" "  a note after the roads swallows none of them"
printf '# derived from laptop\nbuildbox:ssh\nbuildbox:sheep\n' > "$KR"
check "$(kl_line buildbox)" "['ssh']" "  a # line is no road; a host's first line wins"
printf 'buildbox: sheep, ssh\n' > "$KR"
check "$(kl_line buildbox)" "['sheep', 'ssh']" "  spaces after the colon and commas"
printf 'laptop:buildbox\n' > "$REGATTA_CONFIG/wharf-runs/orca-pairs"; echo "elsewhere:none" > "$KR"
python3 "$QB" roads "${QC[@]}" > "$T/roads"; grep -v '^#' "$T/roads" > "$KR"
check "$(kl_line buildbox)" "['orca', 'ssh']" "  dispatch --roads' output, written as it is, reads back as printed"
check "$(grep -c '^laptop:sheep' "$T/roads")" "1" "  this host's listener loaded: its own line, laptop:sheep"
printf '#!/bin/sh\ncase "$1" in print) exit 1;; esac\n' > "$T/launchctl-none"; chmod +x "$T/launchctl-none"
python3 "$QB" roads --cap 3 --launchctl "$T/launchctl-none" --prefix org.example.claude --jobbin "$B/dispatch" > "$T/roads2"
check "$(grep -c '^laptop:' "$T/roads2"):$(grep -c "^# this host's listener on kick/laptop: not loaded" "$T/roads2")" "0:1" "  pass 2: not loaded, no laptop: line at all, only its note (a laptop:none written first would switch off the peers' roads here)"
echo "buildbox:orca" > "$KR"; kreset; echo "laptop:buildbox" > "$REGATTA_CONFIG/wharf-runs/orca-pairs"
python3 "$QB" kick fleet:repo--k1 "${QC[@]}" > /dev/null 2>&1
check "$(grep -c '^terminal create --environment buildbox --worktree path:/peer/'"$CN"' --command ' "$T/orca.calls")" "1" "the orca road: one terminal on the peer's serve, at its core's checkout"
has "$T/orca.calls" '/modules/wharf-runs/bin/dispatch" --claim --full laptop --from laptop; exit --json' "  its command ends in ; exit (a login shell would outlive it)"
has "$T/orca.calls" "terminal wait --environment buildbox --terminal term-1 --for exit --timeout-ms 10000" "  waited for, with --environment (a handle is its server's)"
check "$(grep -c '^terminal create' "$T/orca.calls") $(grep -c '^terminal close --environment buildbox --terminal term-1 --tab' "$T/orca.calls")" "1 1" "  …and closed with --tab: no tab is left on the peer"
has "$KJ" '"ok": true, "road": "orca"' "  the verdict"
echo "buildbox:orca,ssh" > "$KR"; kreset; echo "laptop:buildbox" > "$REGATTA_CONFIG/wharf-runs/orca-pairs"
ORCA_EXIT=127 python3 "$QB" kick fleet:repo--k1 "${QC[@]}" > /dev/null 2>&1
has "$KJ" '"ok": false, "road": "orca"' "the S8 review: a receiver that exited 127 on the peer (no home file) is no kick taken"
has "$KJ" 'the receiver on buildbox exited 127' "  its exit said"
check "$(wc -l < "$T/ssh.calls" | tr -d ' ')" "1" "  and the next road is tried"
echo "buildbox:orca" > "$KR"
rm -f "$REGATTA_CONFIG/wharf-runs/orca-pairs"; kreset
python3 "$QB" kick fleet:repo--k1 "${QC[@]}" > /dev/null 2>&1
check "$([ -f "$T/orca.calls" ] && echo ran || echo none)" "ran" "  a named road is tried as named, whatever exists (the overlay's word wins)"
check "$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import kicklib; print(kicklib.derived("buildbox", "laptop"))' "$B")" "['ssh']" "  derived: no orca where orca-pairs names no pair this way"

echo "  the refusals: a node-local entry, a confidential checkout, a torn registry"
echo "buildbox:ssh" > "$KR"; kreset
python3 "$QB" kick local=vault:repo--k9 "${QC[@]}" > /dev/null 2> "$T/err"; check "$?" "2" "--kick refuses a node-local entry: a node's queue never kicks out"
has "$T/err" "node-local entry" "  saying why"
mkdir -p "$T/vaultrepo"; git init -q "$T/vaultrepo"
printf '{"repos": {}, "scopes": {"vault": {"confidential": true, "repos": ["%s"]}}}' "$(cd "$T/vaultrepo" && pwd -P)" > "$T/reg-k.json"
CLAUDE_REPOS_JSON="$T/reg-k.json" python3 "$QB" kick fleet:repo--k1 --cwd "$T/vaultrepo" "${QC[@]}" > /dev/null 2> "$T/err"; check "$?" "2" "--kick refuses a caller in a confidential scope's checkout"
check "$([ -f "$T/ssh.calls" ] && echo kicked || echo none)" "none" "  and kicks nobody"
printf '{"repos": {}, "scopes": {"all": {"repos": ["*"]}, "vault": {"confidential": true, "repos": ["%s"]}}}' "$(cd "$T/vaultrepo" && pwd -P)" > "$T/reg-um.json"
CLAUDE_REPOS_JSON="$T/reg-um.json" python3 "$QB" kick fleet:repo--k1 --cwd "$T/vaultrepo" "${QC[@]}" > /dev/null 2> "$T/err"; check "$?" "2" "  an umbrella scope listed before the confidential one hides nothing: every scope walked (the S8 review)"
echo '{"repos": ' > "$T/reg-torn.json"
CLAUDE_REPOS_JSON="$T/reg-torn.json" python3 "$QB" kick fleet:repo--k1 "${QC[@]}" > /dev/null 2> "$T/err"; check "$?" "2" "  a registry that will not read: refused (fails closed)"
(cd "$T/vaultrepo" && CLAUDE_REPOS_JSON="$T/reg-k.json" "$B/dispatch" --kick fleet:repo--k1 > /dev/null 2> "$T/err"); check "$?" "2" "  dispatch --kick from that checkout: the same refusal"

echo "  the receiver: noted, the sweep kickstarted, nothing claimed in the caller's process"
rm -f "$T/calls"; rm_own "$KD"
python3 "$QB" kicked --from buildbox --full buildbox "${QC[@]}" > "$T/out" 2>&1; check "$?" "0" "kicked: exit 0"
check "$(ls "$KD" | wc -l | tr -d ' ')" "1" "  the kick noted in queue/kicks/"
has "$T/calls" "kickstart gui/$(id -u)/org.example.claude.queue-sweep" "  and this host's own queue-sweep job kickstarted"
check "$(grep -c '^bootstrap\|^bootout' "$T/calls")" "0" "  no job loaded or booted out by the receiver"
has "$KJ" '"event": "heard"' "  heard, in kicks.jsonl"
check "$(qget repo--k1 state)" "queued" "  nothing claimed by the receiver itself"
printf '#!/bin/sh\necho "$*" >> "%s/calls"\ncase "$1 $2" in "kickstart gui/"*/org.example.claude.queue-sweep) exit 1;; esac\nexit 0\n' "$T" > "$T/launchctl-moved"; chmod +x "$T/launchctl-moved"
rm -f "$T/calls"; python3 "$QB" kicked --from buildbox --full buildbox --cap 3 --launchctl "$T/launchctl-moved" --prefix org.example.claude --prefix-previous org.old.jobs --jobbin "$B/dispatch" > "$T/out" 2>&1
has "$T/calls" "kickstart gui/$(id -u)/org.old.jobs.queue-sweep" "  pass 2: mid label move, the new sweep not loaded: the previous prefix's sweep is kickstarted"
has "$T/out" "the sweep started" "    and said started"
python3 "$QB" kicked --from 'a/b' --full laptop "${QC[@]}" > /dev/null 2>&1; check "$?" "2" "a payload naming more than a host: refused"
SS_STREAM_DATA='{"from":"buildbox","full":["buildbox"],"kick":1,"repo":"x"}' python3 "$QB" kicked --from-stream "${QC[@]}" > /dev/null 2>&1; check "$?" "2" "  a press whose data holds more than kick, from and full: refused"
rm_own "$KD"; SS_STREAM_DATA='{"from":"buildbox","full":["buildbox"],"kick":1}' python3 "$QB" kicked --from-stream "${QC[@]}" > "$T/out" 2>&1
check "$?" "0" "  a good press (--from-stream): heard"; has "$T/out" "(sheep)" "  …by the sheep road"
rm_own "$KD"; "$B/dispatch" --claim --full buildbox --from buildbox > "$T/out" 2>&1; check "$?" "0" "dispatch --claim --full --from: the receiver"
check "$(ls "$KD" | wc -l | tr -d ' ')" "1" "  noted"
"$B/dispatch" --full buildbox > /dev/null 2>&1; check "$?" "2" "  --full without --claim: refused"
rm_own "$KD"

echo "  the hold-back in the sweep: 3 s per higher-ranked berth of unknown room, 9 s at most"
qreset; enq kh
check "$(qpy hold alpha,beta,laptop alpha)" "3 [3] 0" "S8: a kick naming alpha full; beta ranks above this host, room unknown: 3 s"
check "$(qpy hold alpha,beta,laptop alpha,beta)" "0 [] 0" "  every higher berth known full: no hold"
check "$(qpy hold alpha,beta,laptop '')" "6 [6] 0" "  two unknown: 6 s"
check "$(qpy hold a,b,c,d,e,laptop '')" "9 [9] 0" "  five unknown: the 9 s cap"
check "$(qpy hold laptop,alpha '')" "0 [] 0" "  this host first in the berths: no hold"
check "$(HOLD_INELIG=beta qpy hold alpha,beta,laptop alpha)" "0 [] 0" "  a higher berth the entry's needs or pin bar is not waited for (the S8 review)"
qreset; mkdir -p "$T/hA"; HOME="$T/hA" enq kh2
check "$(qpy hold alpha,beta,laptop alpha)" "3 [3] 0" "  the entry put on another host a second ago: the hold fetches, and sees it (the S8 review: 0 from the cached view)"
check "$(qpy midpass)" "2 2" "a kick heard while the sweep ran: one more hold and claim before the pass ends"
check "$(qpy midpass-torn)" "0 2 1" "  pass 2: a torn ref at that flush skips it, never the second claim or poll_tend"
qreset; enq kh3
check "$(qpy hold-fresh)" "3" "  pass 2: the hold fetches past a cached view a CAS round left 5 s fresh"
echo "laptop:ssh" > "$KR"
check "$(qpy tend-quiet)" "None 0" "S2a's finish review, item 8: a host a road reaches, no poll loaded: poll_tend reads no ref"
rm -f "$KR"

echo "  the sheep listener: kick-listen, its proving run, the watchdog"
LD="$T/kick-listen"; export DISPATCH_KICK_LISTEN_DIR="$LD" DISPATCH_KICK_PROVE_S=1
cat > "$T/spacesheep" <<EOF
#!/bin/sh
printf '%s|%s\n' "\$*" "\$SPACESHEEP_CONFIG_DIR" >> "$T/sheep.calls"
case "\$*" in *--service*|*--remove-service*) exit 0;; esac
[ -n "\$SHEEP_REFUSE" ] && { echo "  ✗ the server refused the key (HTTP 401)"; exit 3; }
echo "  listening for kick"; sleep 5
EOF
chmod +x "$T/spacesheep"; export DISPATCH_SPACESHEEP="$T/spacesheep"
rm -f "$T/sheep.calls"
python3 "$B/dispatch-rc" kick-listen install > "$T/out" 2>&1; check "$?" "3" "kick-listen install with no streams-only key saved: exit 3"
has "$T/out" "keys create --scope stream --name laptop | SPACESHEEP_CONFIG_DIR=$LD spacesheep keys save" "  naming the owner's step, a local pipe (minted signed in, never here)"
check "$([ -f "$T/sheep.calls" ] && echo ran || echo none)" "none" "  and nothing run"
mkdir -p "$LD"; echo '{}' > "$LD/config.json"; echo old > "$LD/stream-kick-laptop.log"
CLAUDE_UNATTENDED=dispatch python3 "$B/dispatch-rc" kick-listen install > "$T/out" 2>&1; check "$?" "2" "  refused under CLAUDE_UNATTENDED: an unattended run installs no service"
SHEEP_REFUSE=1 python3 "$B/dispatch-rc" kick-listen install > "$T/out" 2>&1; check "$?" "3" "  a proving run the server refuses: exit 3"
check "$(grep -c -- '--service' "$T/sheep.calls")" "0" "  …and no service installed"
rm -f "$T/sheep.calls"; python3 "$B/dispatch-rc" kick-listen install > "$T/out" 2>&1; check "$?" "0" "  a proving run that listens: the CLI's own --service"
has "$T/sheep.calls" "stream kick/laptop --on-dir $LD/buttons --service|$LD" "  on this host's kick stream, its on-dir, in the listener's own SPACESHEEP_CONFIG_DIR"
check "$(grep -c "stream kick/laptop --on-dir $LD/buttons|$LD" "$T/sheep.calls")" "1" "  one bounded proving run before it"
check "$([ -x "$LD/buttons/kick" ] && grep -c -- '--claim --from-stream' "$LD/buttons/kick")" "1" "  the kick button: the receiver, reading the press's own data"
check "$([ -f "$LD/stream-kick-laptop.log" ] && echo kept || echo fresh)" "fresh" "  a fresh service log: refusals from before the install never count (the S8 review)"
CLAUDE_UNATTENDED=dispatch python3 "$B/dispatch-rc" kick-listen remove > /dev/null 2>&1; check "$?" "2" "  remove refused under an unattended caller (the S8 review)"
REGATTA_UNATTENDED=1 python3 "$B/dispatch-rc" kick-listen remove > /dev/null 2>&1; check "$?" "2" "  and under REGATTA_UNATTENDED, the rename's new mark (pass 2)"
DISPATCH_LABEL=org.example.x python3 "$B/dispatch-rc" kick-listen install --shared "$T" > /dev/null 2>&1; check "$?" "2" "  --shared refused in a fired job too: no button in a live listener"
printf 'laptop:nav/laptop\n' > "$REGATTA_CONFIG/wharf-runs/kick-stream"; rm -f "$T/sheep.calls"
python3 "$B/dispatch-rc" kick-listen remove > "$T/out" 2>&1; check "$?" "2" "the S8 review, pass 2: kick-stream names this host a shared listener's stream, plain remove refused"
has "$T/out" "use --shared DIR" "  naming --shared"
python3 "$B/dispatch-rc" kick-listen install > /dev/null 2>&1; check "$?" "2" "  plain install refused too (the CLI finds the other listener's service by its label)"
check "$([ -f "$T/sheep.calls" ] && echo ran || echo none)" "none" "  and the CLI never called"
rm -f "$REGATTA_CONFIG/wharf-runs/kick-stream"
python3 "$B/dispatch-rc" kick-listen remove > /dev/null 2>&1; check "$?" "0" "kick-listen remove"
has "$T/sheep.calls" "stream kick/laptop --remove-service|$LD" "  through the CLI's --remove-service"
mkdir -p "$T/shared-on"; python3 "$B/dispatch-rc" kick-listen install --shared "$T/shared-on" > "$T/out" 2>&1
check "$? $([ -x "$T/shared-on/kick" ] && echo button)" "0 button" "  --shared: the button in a running listener's on-dir, no process added"
printf 'x\n  ✗ the server refused the key (HTTP 401)\n  ✗ the server refused the key (HTTP 401)\n' > "$LD/stream-kick-laptop.log"
rm -f "$T/calls"; python3 "$QB" sweep "${QC[@]}" > "$T/out" 2>&1
has "$T/calls" "bootout gui/$(id -u)/dev.spacesheep.stream.kick-laptop" "the watchdog: a listener its log shows refused twice is booted out by the sweep"
has "$KJ" '"event": "listener-refused"' "  said in kicks.jsonl"
printf 'streaming to\n  ✗ invalid key\nstreaming to\n  ✗ invalid key\nstreaming to\n  listening for kick\n' > "$LD/stream-kick-laptop.log"; rm -f "$T/calls"
python3 "$QB" sweep "${QC[@]}" > /dev/null 2>&1
check "$(grep -c 'bootout gui/[0-9]*/dev.spacesheep' "$T/calls")" "0" "the S8 review: refusals followed by a healthy start are no loop (the reinstalled listener stays)"
touch "$LA/dev.spacesheep.stream.kick-laptop.plist"
printf 'streaming to\n  listening for kick\nstreaming to\n  ✗ invalid key\nstreaming to\n  ✗ invalid key\n' > "$LD/stream-kick-laptop.log"; rm -f "$T/calls"
python3 "$QB" sweep "${QC[@]}" > /dev/null 2>&1
has "$T/calls" "bootout gui/$(id -u)/dev.spacesheep.stream.kick-laptop" "  two refused starts since it listened, whatever the server's error text: booted out"
check "$([ -f "$LD/dev.spacesheep.stream.kick-laptop.plist.refused" ] && [ -z "$(ls "$LA" | grep kick-laptop)" ] && echo aside)" "aside" "  its plist moved out of LaunchAgents, so the next login loads no loop (pass 2: not renamed in place)"
rm_own "$LA"/dev.spacesheep.stream.* "$LD"/dev.spacesheep.stream.*
printf 'x\n  ✗ the server refused the key (HTTP 401)\n' > "$LD/stream-kick-laptop.log"; rm -f "$T/calls"
python3 "$QB" sweep "${QC[@]}" > /dev/null 2>&1
check "$(grep -c 'dev.spacesheep.stream' "$T/calls")" "0" "  one refusal is no loop: nothing booted out"
printf 'x\n  ✗ the server refused the key (HTTP 401)\n  ✗ the server refused the key (HTTP 401)\n' > "$LD/stream-nav-laptop.log"
printf 'laptop:nav/laptop\n' > "$REGATTA_CONFIG/wharf-runs/kick-stream"; rm -f "$T/calls"
python3 "$QB" sweep "${QC[@]}" > /dev/null 2>&1
check "$(grep -c 'bootout' "$T/calls")" "0" "  pass 2: a host on a shared listener: the watchdog never boots out that listener's service"
rm -f "$REGATTA_CONFIG/wharf-runs/kick-stream"
unset DISPATCH_KICK_LISTEN_DIR DISPATCH_KICK_PROVE_S DISPATCH_SPACESHEEP

echo "  the S2a review's item 7, carried"
check "$(qpy sweep-busy | tail -1)" "0 1" "item 7.3: a clone lock held past its wait skips the flush, never the sweep's claim"
printf '#!/bin/sh\nprintf x >> "%s"\necho\n' "$T/rch.count" > "$T/rch"; chmod +x "$T/rch"; rm -f "$T/rch.count"
check "$(qpy rch-once "$T/rch" "$T/rch.count")" "1" "item 7.9: rc-hosts asked once per process, not at every plist compare"
printf '#!/bin/sh\necho /opt/stand-in/launcher\n' > "$T/rch2"; chmod +x "$T/rch2"
check "$(qpy rch-retry "$T/rch2")" "True /opt/stand-in/launcher" "  pass 2: an ask that timed out is not cached; the next start asks again and gets its launcher"
printf '*.json filter=up\n' > "$T/attrs"
check "$(GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0=core.attributesFile GIT_CONFIG_VALUE_0="$T/attrs" GIT_CONFIG_KEY_1=filter.up.clean GIT_CONFIG_VALUE_1='tr a-z A-Z' qpy git-count "$T/queue.git" | cut -d' ' -f3)" "True" "item 7.5: an entry written with a host's clean filter set reads back as written (--no-filters)"
unset DISPATCH_SSH DISPATCH_ORCA DISPATCH_SHEEP_PRESS DISPATCH_KICK_SYNC
qreset; rm -f "$REGATTA_CONFIG/wharf-runs/queue-repo"
[ "$fails" = 0 ] && echo "all ok" || { echo "$fails FAILED"; exit 1; }
