#!/usr/bin/env bash
# Tests for the queue's S2 first half (docs/dispatch-queue-2026-10-25.md): what starts a queued entry with
# nobody retrying — the watcher's claim (dispatch-rc), the queue-sweep job and the pending poll
# (dispatch-queue jobs, poll), G3's event_at — and the S1 landing reviews' items carried to S2, one case
# each. S1's own cases stay in test_dispatch.sh; this suite is apart so the two halves of S2 and S3 never
# edit one file's tail. Scratch HOME, a bare repo as the queue's home, a stand-in launchctl; no launchd
# job, session or network is touched. Every name is synthetic.
#   bash modules/wharf-runs/tests/test_queue.sh
set -u
unset WEEKLY_RUN CLAUDE_UNATTENDED CLAUDE_CODE_DISABLE_BACKGROUND_TASKS CLAUDE_CODE_SESSION_ID CLAUDE_CONFIG_DIR XPC_SERVICE_NAME
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
  rm -rf "$HL/Caches/run-seed/queue" "$HL/Logs/claude-weekly/run-seed-runs"
  rm -f "$LA"/*.plist "$T/calls" "$QL"
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
check "$(qpy git-count "$T/queue.git")" "4 1 True" "first review's item 7, fourth's item 15: five entries written in 4 git calls, read in one more (cat-file --batch)"
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
rm -rf "$HL/Caches/run-seed/queue/claims"; mkdir -p "$HL/Caches/run-seed/queue/claims"
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
rm -rf "$HL/Caches/run-seed/queue/claims"
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
for v in "--claim" "--poll" "--event-at 1"; do
  WEEKLY_RUN=t "$B/dispatch" claude/laptop/2026-10-27-wk --repo "$T/repo" --at reset --if-room $v > /dev/null 2> "$T/err"
  check "$?:$(grep -c 'under WEEKLY_RUN=t only' "$T/err")" "2:1" "WEEKLY_RUN refuses the one shape with $v"
done
for r in 'dispatch --claim' 'dispatch --poll' 'dispatch-queue poll' 'dispatch-queue jobs' 'dispatch-queue unreserve'; do
  check "$(grep '^denied=(' "$B/dispatch" | grep -cF "\"Bash(*$r*)\"")" "1" "  a run's deny list names $r"
done

rm -f "$REGATTA_CONFIG/wharf-runs/queue-repo"
[ "$fails" = 0 ] && echo "all ok" || { echo "$fails FAILED"; exit 1; }
