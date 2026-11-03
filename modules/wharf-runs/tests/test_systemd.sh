#!/usr/bin/env bash
# Tests for the Linux launcher (dispatch-queue S7's Linux half, the linux-queue-node brief): bin/systemd-launchctl,
# launchctl's verbs over systemd's user manager, and the queue's two Linux roads through it — `jobs` installing
# the sweep as a user timer, a claim starting its job as a transient unit — plus the fleet fence a node keeps
# (wharf-runs/queue-repos, a confidential scope's repo, a torn registry). systemctl and systemd-run are stood in
# by one script that keeps each unit's state in files; no user manager, launchd job or network is touched, so
# the suite runs alike on a Mac and on Linux. Every name is synthetic.
#   bash modules/wharf-runs/tests/test_systemd.sh
set -u
unset WEEKLY_RUN CLAUDE_UNATTENDED REGATTA_UNATTENDED CLAUDE_CODE_DISABLE_BACKGROUND_TASKS CLAUDE_CODE_SESSION_ID CLAUDE_CONFIG_DIR XPC_SERVICE_NAME
unset $(compgen -v | grep '^DISPATCH_')   # every DISPATCH_* a run carries (AGENTS.md: a fixed list goes stale)
B="$(cd "$(dirname "$0")/../bin" && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
. "$(cd "$(dirname "$0")" && pwd)/config_fixture.sh"; fixture_config "$T/config"
fails=0
check() { if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3: expected [$2] got [$1]"; fails=$((fails+1)); fi; }
has()   { if grep -qF -- "$2" "$1"; then echo "  ok   $3"; else echo "  FAIL $3: missing [$2]"; sed 's/^/         | /' "$1" | head -20; fails=$((fails+1)); fi; }
hasnt() { if grep -qF -- "$2" "$1"; then echo "  FAIL $3: unexpected [$2]"; sed 's/^/         | /' "$1" | head -20; fails=$((fails+1)); else echo "  ok   $3"; fi; }
export PYTHONUSERBASE="${PYTHONUSERBASE:-$(python3 -m site --user-base)}"
export HOME="$T/home"; HL="$HOME"/Library; mkdir -p "$HL/LaunchAgents"   # every home path through $HL or $PJ (the publish gate)
rm_own() { local p; for p; do case "$p" in */..|*/../*|*//*) ;; "${T:?}"/?*) rm -rf -- "$p"; continue ;; esac; echo "rm_own: refused $p, outside $T" >&2; return 1; done; }
export ACCOUNTS_FILE="$T/no-accounts.json"
printf '[user]\n\tname = t\n\temail = t@t\n[init]\n\tdefaultBranch = main\n' > "$T/gitconfig"; export GIT_CONFIG_GLOBAL="$T/gitconfig"

# The stand-in user manager: `systemd-run` and `systemctl --user` in one script, chosen by its name. A unit
# is loaded while $SD/<unit>.loaded exists (a transient one) or its file is in the unit folder; active while
# $SD/<unit>.active exists. Each call is one line in $T/sd.calls.
SD="$T/sd"; UN="$T/units"; mkdir -p "$SD" "$T/stub"
cat > "$T/stub/sdstub.py" <<'PY'
import os, sys
from pathlib import Path
sd, un, calls = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]
me, a = sys.argv[4], sys.argv[5:]
with open(calls, "a") as f:
    f.write("%s %s\n" % (me, " ".join(a)))
def mark(u, kind, on=True):
    p = sd / ("%s.%s" % (u, kind))
    p.write_text("") if on else p.unlink(missing_ok=True)
def loaded(u):
    return (sd / (u + ".loaded")).exists() or (un / u).exists()
if me == "systemd-run":
    i = a.index("--unit")
    u = a[i + 1] + ".service"
    if loaded(u):
        print("Failed to start transient service unit: Unit %s was already loaded" % u, file=sys.stderr); sys.exit(1)
    if os.environ.get("STUB_RUN_RC"):
        sys.exit(int(os.environ["STUB_RUN_RC"]))
    mark(u, "loaded"); mark(u, "active")
    sys.exit(0)
a = [x for x in a if x != "--user"]
verb, rest = a[0], [x for x in a[1:] if not x.startswith("-")]
if verb == "show":
    units = []
    for x in a[1:]:
        if x in ("-p",) or x.startswith("-"):
            continue
        if x in ("Id", "LoadState", "ActiveState", "MainPID"):
            continue
        units.append(x)
    blocks = []
    for u in units:
        st = "active" if (sd / (u + ".active")).exists() else "inactive"
        # systemd's own order, not the order asked: Id last on purpose
        blocks.append("MainPID=%s\nLoadState=%s\nActiveState=%s\nId=%s" % ("4242" if st == "active" and u.endswith(".service") else "0",
                      "loaded" if loaded(u) else "not-found", st, u))
    print("\n\n".join(blocks))
elif verb == "stop":
    for u in rest:
        mark(u, "active", False)
        if u.endswith(".service"):
            mark(u, "loaded", False)   # --collect: a transient unit goes once it stops
elif verb == "enable":
    for u in rest:
        mark(u, "active")
elif verb == "disable":
    for u in rest:
        mark(u, "active", False)
elif verb == "start" or verb == "restart":
    for u in rest:
        mark(u, "active")
elif verb in ("daemon-reload", "reset-failed", "clean"):
    pass
elif verb == "is-system-running":
    v = os.environ.get("STUB_MANAGER") or "running"
    print(v); sys.exit(0 if v == "running" else 1)
else:
    print("stub: unknown verb %s" % verb, file=sys.stderr); sys.exit(1)
PY
for n in systemd-run systemctl; do
  printf '#!/bin/sh\nexec python3 "%s" "%s" "%s" "%s" %s "$@"\n' "$T/stub/sdstub.py" "$SD" "$UN" "$T/sd.calls" "$n" > "$T/stub/$n"
  chmod +x "$T/stub/$n"
done
export SYSTEMD_LAUNCHCTL_SYSTEMCTL="$T/stub/systemctl" SYSTEMD_LAUNCHCTL_RUN="$T/stub/systemd-run" SYSTEMD_LAUNCHCTL_UNITS="$UN"
SL="$B/systemd-launchctl"; U=$(id -u)
mkplist() {   # <file> <python dict literal>
  python3 -c 'import plistlib, sys; plistlib.dump(eval(sys.argv[2]), open(sys.argv[1], "wb"))' "$1" "$2"
}

echo "systemd-launchctl: a RunAtLoad job is a transient unit"
mkplist "$T/once.plist" "{'Label': 'org.example.claude.dispatch.repo.t.q20261030120000', 'ProgramArguments': ['/x/dispatch', 'claude/laptop/2026-10-30-t', '--from-queue', 'fleet:repo--t'], 'EnvironmentVariables': {'DISPATCH_LOG': '$T/run.log', 'DISPATCH_LABEL': 'org.example.claude.dispatch.repo.t.q20261030120000'}, 'RunAtLoad': True, 'StandardOutPath': '$T/run.log', 'StandardErrorPath': '$T/run.log'}"
L1=org.example.claude.dispatch.repo.t.q20261030120000
"$SL" bootstrap "gui/$U" "$T/once.plist"; check "$?" 0 "  bootstrap: exit 0"
has "$T/sd.calls" "systemd-run --user --unit $L1 --collect --quiet --service-type=exec --expand-environment=no -p KillMode=process" "  systemd-run, collected once it exits, no \${VAR} expanded in its argv, its detached children left alone (KillMode=process)"
has "$T/sd.calls" "-p StandardOutput=append:$T/run.log -p StandardError=append:$T/run.log" "  the plist's log, appended"
has "$T/sd.calls" "--setenv=DISPATCH_LOG=$T/run.log" "  the plist's variables"
has "$T/sd.calls" "--setenv=XPC_SERVICE_NAME=$L1" "  and launchd's own: the job's label"
has "$T/sd.calls" "-- /x/dispatch claude/laptop/2026-10-30-t --from-queue fleet:repo--t" "  the plist's program, after --"
check "$(ls "$UN" 2>/dev/null | wc -l | tr -d ' ')" 0 "  no unit file for a transient job"
out=$("$SL" print "gui/$U/$L1"); check "$?" 0 "  print while it runs: exit 0"
check "$(echo "$out" | grep -c "$(printf '\tstate = running')")" 1 "  and launchd's running line (the line dispatch-queue's job_running reads)"
"$SL" bootstrap "gui/$U" "$T/once.plist" 2>"$T/err"; check "$?" 5 "  a second bootstrap while loaded: exit 5, as launchd's"
"$SL" bootout "gui/$U/$L1"; check "$?" 0 "  bootout: exit 0"
"$SL" print "gui/$U/$L1" >/dev/null 2>&1; check "$?" 113 "  print once gone: 113, launchd's not-found"
"$SL" bootout "gui/$U/$L1" 2>/dev/null; check "$?" 3 "  bootout of nothing: 3, launchd's no-such-process"
# XPC_SERVICE_NAME set by hand kills any process on macOS (SIGTRAP, exit 133: libxpc takes it for a launchd
# job's), so the inside case runs off macOS only, where the shim sets it in every unit
if [ "$(uname)" != Darwin ]; then
  "$SL" bootstrap "gui/$U" "$T/once.plist"; : > "$T/sd.calls"
  XPC_SERVICE_NAME=$L1 "$SL" bootout "gui/$U/$L1"
  has "$T/sd.calls" "systemctl --user stop --no-block $L1.timer $L1.service" "  from inside the job (its cleanup): a stop that does not wait on its own caller"
else
  echo "  --   skipped on macOS: from inside the job (XPC_SERVICE_NAME is launchd's there)"
fi
: > "$T/sd.calls"
"$SL" bootstrap "gui/$U" "$T/once.plist" >/dev/null 2>&1; "$SL" bootout "gui/$U/$L1" >/dev/null 2>&1
has "$T/sd.calls" "systemctl --user stop $L1.timer $L1.service" "  from anywhere else: a stop that waits"
STUB_RUN_RC=1 "$SL" bootstrap "gui/$U" "$T/once.plist" 2>/dev/null; check "$?" 5 "  systemd-run refusing: bootstrap fails, as launchctl's does (the callers retry once, then refuse)"
"$SL" print "gui/$U/bad/label!" >/dev/null 2>&1; check "$([ $? -ne 0 ] && echo refused)" refused "  a label with no unit name's characters is refused"

echo "systemd-launchctl: a StartInterval job is a unit pair and an enabled timer"
L2=org.example.claude.queue-sweep
mkplist "$T/sweep.plist" "{'Label': '$L2', 'ProgramArguments': ['/x/dispatch', '--sweep', '50% \$HOME \"q\"'], 'EnvironmentVariables': {'PATH': '/usr/bin:/bin', 'DISPATCH_ORIGIN': '/p/a\$b 5%'}, 'WorkingDirectory': '$T/w d', 'StartInterval': 600, 'ProcessType': 'Background', 'StandardOutPath': '$T/q.log', 'StandardErrorPath': '$T/q.log'}"
: > "$T/sd.calls"
"$SL" bootstrap "gui/$U" "$T/sweep.plist"; check "$?" 0 "  bootstrap: exit 0"
has "$UN/$L2.service" 'ExecStart="/x/dispatch" "--sweep" "50%% $$HOME \"q\""' "  ExecStart quoted as systemd unquotes it (%, \$ and a quote)"
has "$UN/$L2.service" 'Environment="PATH=/usr/bin:/bin"' "  its variables"
has "$UN/$L2.service" 'Environment="DISPATCH_ORIGIN=/p/a$b 5%%"' "  a variable's \$ as it is (no expansion in Environment=), its % doubled"
has "$UN/$L2.service" "WorkingDirectory=$T/w d" "  WorkingDirectory= unquoted (a path setting is not unquoted)"
hasnt "$UN/$L2.service" 'WorkingDirectory="' "    never in quotes"
hasnt "$UN/$L2.timer" "Persistent=" "  an interval timer: no Persistent= (OnCalendar only)"
has "$UN/$L2.service" "KillMode=process" "  its children left alone"
has "$UN/$L2.service" "StandardOutput=append:$T/q.log" "  its log"
has "$UN/$L2.timer" "OnActiveSec=600" "  first run one interval after load, as launchd's"
has "$UN/$L2.timer" "OnUnitActiveSec=600" "  then every interval"
has "$UN/$L2.timer" "WantedBy=timers.target" "  enabled: it outlives a reboot, as a plist outlives a login"
has "$T/sd.calls" "systemctl --user daemon-reload" "  the manager reloaded"
has "$T/sd.calls" "systemctl --user enable --now $L2.timer" "  the timer enabled and started"
hasnt "$T/sd.calls" "start --no-block $L2.service" "  no RunAtLoad: the service is not started at once"
out=$("$SL" print "gui/$U/$L2"); check "$?" 0 "  print: loaded"
echo "$out" | grep -q "state = not running"; check "$?" 0 "  and not running between passes"
"$SL" bootout "gui/$U/$L2"; check "$?:$(ls "$UN" | wc -l | tr -d ' ')" "0:0" "  bootout: both unit files gone"
mkplist "$T/cal.plist" "{'Label': 'org.example.claude.dispatch.repo.t.202610310905', 'ProgramArguments': ['/x/dispatch', 'b'], 'StartCalendarInterval': {'Month': 10, 'Day': 31, 'Hour': 9, 'Minute': 5}}"
"$SL" bootstrap "gui/$U" "$T/cal.plist"
has "$UN/org.example.claude.dispatch.repo.t.202610310905.timer" "OnCalendar=*-10-31 09:05:00" "  a one-shot's calendar: no year, as launchd's"
has "$UN/org.example.claude.dispatch.repo.t.202610310905.timer" "Persistent=true" "  a minute missed while the host was down fires at boot, as launchd's at wake"
: > "$T/sd.calls"
"$SL" bootout "gui/$U/org.example.claude.dispatch.repo.t.202610310905" >/dev/null
has "$T/sd.calls" "systemctl --user clean --what=state org.example.claude.dispatch.repo.t.202610310905.timer" "  bootout cleans its stamp: a label loaded again never fires on an old one"

echo "systemd-launchctl: kickstart and the manager probe"
"$SL" kickstart -k 2>/dev/null; check "$?" 2 "  kickstart with flags alone: usage, exit 2 (never a traceback)"
"$SL" manager; check "$?" 0 "  manager: a user manager that answers running: exit 0"
STUB_MANAGER=degraded "$SL" manager >/dev/null; check "$?" 0 "  degraded is up (a failed unit is no dead manager)"
STUB_MANAGER=offline "$SL" manager >/dev/null; check "$?" 1 "  offline: exit 1"
SYSTEMD_LAUNCHCTL_SYSTEMCTL="$T/no-systemctl" "$SL" manager; check "$?" 1 "  no systemctl at all: exit 1"

echo "dispatch-queue on Linux: the sweep installed and removed through systemd-launchctl"
git init -q -b main "$T/repo"; (cd "$T/repo" && echo x > f && git add f && git commit -qm init)
git init -q --bare "$T/queue.git"
echo "$T/queue.git" > "$REGATTA_CONFIG/wharf-runs/queue-repo"
QB="$B/dispatch-queue"; LA="$HL/LaunchAgents"; QL="$HL/Logs/claude-weekly/queue.jsonl"
QC=(--cap 3 --launchctl "$SL" --prefix org.example.claude --jobbin "$B/dispatch" --host node1)
export DISPATCH_HOST=node1 HEADROOM_SAMPLE="60 0 0"
: > "$T/sd.calls"
out=$(python3 "$QB" jobs "${QC[@]}"); check "$?" 0 "  jobs: exit 0"
echo "$out" | grep -q "queue jobs: org.example.claude.queue-sweep loaded, every 10 min"; check "$?" 0 "  the sweep said loaded"
check "$([ -f "$LA/org.example.claude.queue-sweep.plist" ] && echo y)" y "  its plist, the job's definition, where every reader looks"
has "$UN/org.example.claude.queue-sweep.timer" "OnUnitActiveSec=600" "  and a user timer every 10 min"
has "$UN/org.example.claude.queue-sweep.service" "\"--sweep\"" "  running dispatch --sweep"
: > "$T/sd.calls"
out=$(python3 "$QB" jobs "${QC[@]}"); check "$out" "" "  again: the plist the same and the timer loaded, nothing reloaded"
hasnt "$T/sd.calls" "enable" "    (no enable call)"
echo off > "$REGATTA_CONFIG/wharf-runs/queue-repo"
out=$(python3 "$QB" jobs "${QC[@]}")
echo "$out" | grep -q "no queue home here — removed org.example.claude.queue-sweep"; check "$?" 0 "  home off: the sweep removed"
check "$(ls "$UN" | wc -l | tr -d ' '):$([ -f "$LA/org.example.claude.queue-sweep.plist" ] && echo plist)" "0:" "    its unit files and plist gone"
echo "$T/queue.git" > "$REGATTA_CONFIG/wharf-runs/queue-repo"
if [ "$(uname)" != Darwin ]; then
  out=$(STUB_MANAGER=offline python3 "$QB" jobs "${QC[@]}")
  check "$out" "queue jobs: no launchd or systemd user manager here; no sweep" "  no user manager answering: no sweep (a systemctl on PATH is no manager)"
else
  echo "  --   skipped on macOS: no user manager (launchd is always there)"
fi

echo "dispatch-queue on Linux: a claim starts its job as a transient unit"
enq() { python3 "$QB" enqueue --repo "$T/repo" --branch "claude/laptop/2026-10-30-$1" "${QC[@]}" "${@:2}"; }
: > "$T/sd.calls"
out=$(enq one --claim); check "$?" 0 "  enqueue --claim: exit 0"
has "$T/sd.calls" "systemd-run --user --unit org.example.claude.dispatch.repo.one.q" "  the claimed job: a transient unit named by its label"
has "$T/sd.calls" "claude/laptop/2026-10-30-one --repo $(cd "$T/repo" && pwd -P) --from-queue fleet:repo--one" "  running the fired dispatch on its entry"
has "$T/sd.calls" "--setenv=DISPATCH_LABEL=org.example.claude.dispatch.repo.one.q" "  its label in its environment, as the plist's"
check "$(ls "$LA"/org.example.claude.dispatch.repo.one.q*.plist 2>/dev/null | wc -l | tr -d ' ')" 1 "  its plist written beside it (the reservation reads it)"
lab=$(basename "$(ls "$LA"/org.example.claude.dispatch.repo.one.q*.plist)" .plist)
check "$(python3 "$QB" reserved "${QC[@]}")" 1 "  the reservation holds a slot while the unit runs"
grep -q '"event": "claimed".*"host": "node1"' "$QL"; check "$?" 0 "  queue.jsonl's claimed line"

echo "the fleet fence: what a node claims from the fleet ref"
# room for every entry below, so a "not claimed" is the fence's and never a full host's (at --cap 3 the three
# claims above filled it, and each such case passed whatever the fence said)
QC=(--cap 9 --launchctl "$SL" --prefix org.example.claude --jobbin "$B/dispatch" --host node1)
# wharf-runs/queue-repos narrows the claim to the repos it lists
PJ="$HOME"/projects   # the projects folder, one definition (the publish gate reads every home path)
mkdir -p "$PJ"; git init -q -b main "$PJ/open"; (cd "$PJ/open" && echo x > f && git add f && git commit -qm init)
git init -q -b main "$PJ/vault"; (cd "$PJ/vault" && echo x > f && git add f && git commit -qm init)
echo other > "$REGATTA_CONFIG/wharf-runs/queue-repos"
: > "$T/sd.calls"
python3 "$QB" enqueue --repo "$PJ/open" --branch claude/laptop/2026-10-30-two "${QC[@]}" --claim >/dev/null
hasnt "$T/sd.calls" "systemd-run" "  a repo queue-repos does not list: not claimed"
python3 "$QB" list "${QC[@]}" > "$T/list" 2>&1
has "$T/list" "not here: open is not one wharf-runs/queue-repos lets this host claim" "  list says why"
echo open > "$REGATTA_CONFIG/wharf-runs/queue-repos"
python3 "$QB" claim "${QC[@]}" >/dev/null
has "$T/sd.calls" "--unit org.example.claude.dispatch.open.two.q" "  listed: claimed"
# `<key> pinned`: only an entry pinned to this host
echo "open pinned" > "$REGATTA_CONFIG/wharf-runs/queue-repos"
python3 "$QB" enqueue --repo "$PJ/open" --branch claude/laptop/2026-10-30-four "${QC[@]}" >/dev/null
: > "$T/sd.calls"
python3 "$QB" claim "${QC[@]}" >/dev/null
hasnt "$T/sd.calls" "systemd-run" "  a pinned-only repo's unpinned entry: not claimed"
python3 "$QB" list "${QC[@]}" > "$T/list" 2>&1
has "$T/list" "lets this host claim open only when pinned here" "  list says why"
python3 "$QB" enqueue --repo "$PJ/open" --branch claude/laptop/2026-10-30-four --pin node1 "${QC[@]}" >/dev/null
python3 "$QB" claim "${QC[@]}" >/dev/null
has "$T/sd.calls" "--unit org.example.claude.dispatch.open.four.q" "  pinned to this host: claimed"
# the overlay's bootstrap writes a value one word per line (AGENTS.md's trap): `pinned` alone is the key's before it
printf 'open\npinned\n' > "$REGATTA_CONFIG/wharf-runs/queue-repos"
python3 "$QB" enqueue --repo "$PJ/open" --branch claude/laptop/2026-10-30-five "${QC[@]}" >/dev/null
: > "$T/sd.calls"
python3 "$QB" claim "${QC[@]}" >/dev/null
hasnt "$T/sd.calls" "systemd-run" "  \`pinned\` on a line of its own still pins the key before it: the unpinned entry not claimed"
python3 "$QB" list "${QC[@]}" > "$T/list" 2>&1
has "$T/list" "lets this host claim open only when pinned here" "  list says why"
hasnt "$T/list" "pinned is not one" "  and \`pinned\` is no key of its own"
# a file that is there but will not read refuses every entry (read as absent it would open every repo)
printf 'open\n\377\376\n' > "$REGATTA_CONFIG/wharf-runs/queue-repos"
python3 "$QB" claim "${QC[@]}" >/dev/null
hasnt "$T/sd.calls" "systemd-run" "  an unreadable queue-repos: nothing claimed"
python3 "$QB" list "${QC[@]}" > "$T/list" 2>&1
has "$T/list" "wharf-runs/queue-repos does not read here (not UTF-8): this host claims nothing from the fleet" "  list says why"
echo open > "$REGATTA_CONFIG/wharf-runs/queue-repos"; python3 "$QB" claim "${QC[@]}" >/dev/null
has "$T/sd.calls" "--unit org.example.claude.dispatch.open.five.q" "  readable again, unpinned: claimed (the entry out of the cases below)"
# a confidential scope's repo on the fleet ref is never claimed, whatever lists it
printf 'open\nvault\n' > "$REGATTA_CONFIG/wharf-runs/queue-repos"
printf '{"repos": {"open": {}, "vault": {}}, "scopes": {"wide": {"repos": ["*"]}, "secret": {"confidential": true, "repos": ["vault"]}}}\n' > "$T/reg.json"
export CLAUDE_REPOS_JSON="$T/reg.json"
# the put itself would be routed to the scope's local queue; this one stands for a put no registry here made
CLAUDE_REPOS_JSON="$T/no-reg.json" python3 "$QB" enqueue --repo "$PJ/vault" --branch claude/laptop/2026-10-30-three "${QC[@]}" >/dev/null
: > "$T/sd.calls"
python3 "$QB" claim "${QC[@]}" >/dev/null
hasnt "$T/sd.calls" "systemd-run" "  a confidential scope's repo (behind an umbrella scope listed first): not claimed"
python3 "$QB" list "${QC[@]}" > "$T/list" 2>&1
has "$T/list" "its repo is in a confidential scope: a fleet entry never runs one" "  list says why"
# a glob member matches a key the registry's repos lack (scope_of_repo per scope, as route() judges it)
printf '{"repos": {"open": {}}, "scopes": {"wide": {"repos": ["*"]}, "secret": {"confidential": true, "repos": ["vau*"]}}}\n' > "$T/reg-glob.json"
: > "$T/sd.calls"
CLAUDE_REPOS_JSON="$T/reg-glob.json" python3 "$QB" claim "${QC[@]}" >/dev/null
hasnt "$T/sd.calls" "systemd-run" "  a glob member the registry's repos lack: not claimed"
CLAUDE_REPOS_JSON="$T/reg-glob.json" python3 "$QB" list "${QC[@]}" > "$T/list" 2>&1
has "$T/list" "its repo is in a confidential scope: a fleet entry never runs one" "  list says why"
head -c 20 "$T/reg.json" > "$T/torn.json"
CLAUDE_REPOS_JSON="$T/torn.json" python3 "$QB" list "${QC[@]}" > "$T/list" 2>&1
has "$T/list" "not here: the registry" "  a torn registry: nothing claimed from the fleet (S5's eligibility says it first, the fence after)"
rm -f "$REGATTA_CONFIG/wharf-runs/queue-repos"; unset CLAUDE_REPOS_JSON

echo "the node's cap and kick (node-cap-kick): a host's run-cap, and an ssh road only the kick reads"
RC="$REGATTA_CONFIG/wharf-runs"
printf 'node1:4\nother:5\n' > "$RC/run-cap"
check "$(DISPATCH_HOST=node1 "$B/dispatch" --cap) $(DISPATCH_HOST=mac1 "$B/dispatch" --cap)" "4 3" "dispatch --cap: this host's line in wharf-runs/run-cap, the default elsewhere"
check "$(DISPATCH_HOST=node1 DISPATCH_MAX_RUNS=2 "$B/dispatch" --cap)" "2" "  DISPATCH_MAX_RUNS over it"
check "$(DISPATCH_HOST=node1 "$B/dispatch" --slots | cut -d' ' -f2)" "4" "  --slots, berth's read over ssh, says the same"
for bad in node1:0 node1:many node1: node1:-1 node1:99999999999999999999; do
  echo "$bad" > "$RC/run-cap"
  check "$(DISPATCH_HOST=node1 "$B/dispatch" --cap 2> "$T/err")" "3" "  $bad is no cap: the default…"
  has "$T/err" "wharf-runs/run-cap" "  …said on stderr"
done
printf 'node1:\n4\n' > "$RC/run-cap"
check "$(DISPATCH_HOST=node1 "$B/dispatch" --cap 2>&1)" "4" "  a value split one word per line, as the overlay writes it, reads as one line"
printf '# node1:9\nnode1:4  # the owner\n' > "$RC/run-cap"
check "$(DISPATCH_HOST=node1 "$B/dispatch" --cap 2>&1)" "4" "  a commented line is no line, and a note after the value is no value"
for spelt in 'node1:4\n5\n' 'node1:4 5\n' 'node1:4 (the owner)\n' 'node1: 4\n' 'node1 : 4\n' 'other:\nnode1:4\n' '(node1:9 was too many)\nnode1:4\n'; do
  printf "$spelt" > "$RC/run-cap"
  check "$(DISPATCH_HOST=node1 "$B/dispatch" --cap 2>&1)" "4" "  [$spelt] reads 4: one value per host, whatever stands beside it"
done
printf 'node1:\nother:5\n' > "$RC/run-cap"
check "$(DISPATCH_HOST=other "$B/dispatch" --cap 2>&1)" "5" "  a bare host: takes no other host's line"
check "$(DISPATCH_HOST=node1 "$B/dispatch" --cap 2>&1 | tail -1)" "3" "  …and is no cap itself"
rm -f "$RC/run-cap"; mkdir "$RC/run-cap"
check "$(DISPATCH_HOST=node1 "$B/dispatch" --cap 2>/dev/null)" "3" "  a key that will not read: the default…"
DISPATCH_HOST=node1 "$B/dispatch" --cap 2> "$T/err" > /dev/null; has "$T/err" "wharf-runs/run-cap" "  …said on stderr"
rmdir "$RC/run-cap"
printf 'srv_01:6\n*:9\n' > "$RC/run-cap"
check "$(DISPATCH_HOST=srv-01 "$B/dispatch" --cap 2>&1) $(DISPATCH_HOST=node1 "$B/dispatch" --cap 2>&1)" "6 3" "  a host spelled as the kernel does matches as local_host spells it; a * line is no line: the default stays dispatch's"
check "$(DISPATCH_HOST=srv_01 "$B/dispatch" --cap 2>&1)" "6" "  DISPATCH_HOST spelled with an underscore reads its own line too, spelled as local_host spells it"
rm -f "$RC/run-cap"
check "$(DISPATCH_HOST=node1 "$B/dispatch" --cap 2> "$T/err") $(wc -c < "$T/err" | tr -d ' ')" "3 0" "  no key: the default, nothing said"

# The node in kick-ssh and not in wharf-runs/ssh: the kick reaches it, and berth and dispatch --on do not.
RGY="$T/reg-kick.json"
printf '{"repos": {"open": {"hosts": ["mac1", "node1"]}, "plain": {"hosts": ["mac1", "node1"]}}, "scopes": {"s": {"repos": ["open"], "berths": ["mac1", "node1"]}}}\n' > "$RGY"
SSHKEPT="$(cat "$RC/ssh" 2>/dev/null)"; echo "mac2:mac2-alias" > "$RC/ssh"
echo "node1:node1-alias" > "$RC/kick-ssh"; echo "node1:ssh" > "$RC/kick-roads"
printf '#!/bin/sh\necho "$*" >> "$T/kick.calls"\n' | sed "s|\$T|$T|" > "$T/stub/kickssh"; chmod +x "$T/stub/kickssh"
kl() { CLAUDE_REPOS_JSON="$RGY" python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import kicklib as k; exec(sys.argv[2])' "$B" "$1"; }
check "$(kl 'print(k.roads_for("node1", "mac1"), k.reached("node1"), k.reached("mac9"))')" "(['ssh'], 'kick-roads') True False" "the kick's roads: the node's line, reached"
check "$(DISPATCH_SSH="$T/stub/kickssh" kl 'print(k.road_ssh("node1", k.payload("mac1", ["mac1"]))[1])')" "ssh node1-alias" "  the ssh road takes the alias from kick-ssh"
has "$T/kick.calls" "--claim --full mac1 --from mac1" "  host names only, to the peer's own dispatch"
hasnt "$T/kick.calls" "fleet:" "  no entry crosses"
check "$(kl 'print(sorted(ln for ln in k.roads_lines("mac1", "/nonexistent") if not ln.startswith("#")))')" "['mac2:ssh', 'node1:ssh']" "  dispatch --roads names both"
: > "$RC/kick-roads"
check "$(kl 'print(k.derived("node1", "mac1"), k.reached("node1"))')" "['ssh'] True" "  no line: ssh derived from kick-ssh, as from wharf-runs/ssh"
printf 'node1:\nnode1-alias\n# none\nmac3:mac3-alias # a note\nmac4:mac4-alias (a note)\n' > "$RC/kick-ssh"
check "$(kl 'print(k.ssh_alias("node1"), k.ssh_alias("mac3"), k.ssh_alias("mac4"))')" "node1-alias mac3-alias mac4-alias" "  a value split one word per line reads as one, and a note is no alias"
echo "node1:node1-alias" > "$RC/kick-ssh"
berthc() { CLAUDE_REPOS_JSON="$RGY" BERTH_HOST=mac1 python3 -c 'import sys, importlib.machinery as m, importlib.util as u
l = m.SourceFileLoader("berth", sys.argv[1] + "/berth"); b = u.module_from_spec(u.spec_from_loader("berth", l)); l.exec_module(b)
print(b.sample_peer("node1").get("answered"), sorted(b.ssh_aliases()))' "$B"; }
check "$(berthc)" "False ['mac2']" "  berth holds no alias for it: never probed, so never placed on"
check "$(DISPATCH_HOST=mac1 "$B/dispatch" claude/mac1/2026-10-31-x --on node1 --dry-run 2>&1 | grep -c 'unknown host node1')" "1" "  dispatch --on does not know it"
# the receiver: on Linux through systemd-launchctl, whose kickstart never waits on the unit, the road's bound being 15 s
: > "$T/sd.calls"
python3 "$QB" kicked --full mac1 --from mac1 "${QC[@]}" > "$T/out" 2>&1
has "$T/sd.calls" "systemctl --user start --no-block org.example.claude.queue-sweep.service" "the kick heard here starts this host's sweep through the launcher"
has "$T/out" "kick heard from mac1" "  said"
# the same on the road's own line, through dispatch's choice of launcher (its own on Linux; a Mac has no OSTYPE road to it)
: > "$T/sd.calls"; DL=""; [ "$(uname)" = Darwin ] && DL="$SL"
DISPATCH_LAUNCHCTL="$DL" "$B/dispatch" --claim --full mac1 --from mac1 > "$T/out" 2>&1; check "$?" 0 "  the ssh road's command line, on dispatch itself: exit 0"
has "$T/sd.calls" "--no-block" "  …the launcher's kickstart, which never waits on the unit"
has "$T/sd.calls" "queue-sweep.service" "  …of this host's sweep"
cat > "$T/stub/xdgctl" <<'SH'
#!/bin/sh
echo "[$XDG_RUNTIME_DIR]" >> "$XDGLOG"
SH
chmod +x "$T/stub/xdgctl"
( unset XDG_RUNTIME_DIR; XDGLOG="$T/xdg" SYSTEMD_LAUNCHCTL_SYSTEMCTL="$T/stub/xdgctl" "$SL" kickstart "gui/$(id -u)/org.example.x" )
has "$T/xdg" "[/run/user/$(id -u)]" "  a session with no XDG_RUNTIME_DIR, an ssh command's: the user manager is found all the same"
rm -f "$RC/kick-ssh" "$RC/kick-roads"; if [ -n "$SSHKEPT" ]; then echo "$SSHKEPT" > "$RC/ssh"; else rm -f "$RC/ssh"; fi

[ "$fails" = 0 ] && echo "all ok" || { echo "$fails FAILED"; exit 1; }
