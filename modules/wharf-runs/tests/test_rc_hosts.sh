#!/usr/bin/env bash
# Tests for bin/rc-hosts — a scratch HOME, a copy of the script beside a one-repo repos.json,
# and stand-ins for launchctl, pgrep and scutil that keep the "running" hosts in files. No
# launchd job and no real host is touched.
#   bash modules/wharf-runs/tests/test_rc_hosts.sh
set -u
B="$(cd "$(dirname "$0")/../bin" && pwd)"   # the module's bin/ (B7: the suites moved to tests/)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fails=0
check() { if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3: expected [$2] got [$1]"; fails=$((fails+1)); fi; }
has()   { if grep -qF -- "$2" "$1"; then echo "  ok   $3"; else echo "  FAIL $3: missing [$2]"; sed 's/^/         | /' "$1" | head -20; fails=$((fails+1)); fi; }
hasnt() { if grep -qF -- "$2" "$1"; then echo "  FAIL $3: unexpected [$2]"; fails=$((fails+1)); else echo "  ok   $3"; fi; }

. "$(cd "$(dirname "$0")" && pwd)/config_fixture.sh"; fixture_config "$T/config"   # the suite's own config dir, never the login's (config_fixture.sh)
unset ACCOUNTS_FILE ACCOUNT_ORCA_FILE   # rc-hosts reads the login dirs in every case: never the caller's registry
export HOME="$T/home"
# a recursive delete under HOME goes through rm_own: only under this suite's own $T, so a block of the
# suite run outside it (its HOME the real one; F2, 2026-10-25) deletes nothing (the core's check, home_rm)
rm_own() { local p; for p; do case "$p" in */..|*/../*|*//*) ;; "${T:?}"/?*) rm -rf -- "$p"; continue ;; esac; echo "rm_own: refused $p, outside $T" >&2; return 1; done; }
# a stand-in overlay: the checkout claude-host's allowlist names (rc-hosts primary()), marked in the
# suite's config dir with the core's keys beside it (B14b: the marker is how an overlay is named)
echo "$HOME/projects/overlay" > "$REGATTA_CONFIG/regatta/overlay"
for k in guarded orca-deny; do [ -e "$REGATTA_CONFIG/regatta/$k" ] || : > "$REGATTA_CONFIG/regatta/$k"; done
[ -e "$REGATTA_CONFIG/regatta/log-dir" ] || echo "$T/logs" > "$REGATTA_CONFIG/regatta/log-dir"
[ -e "$REGATTA_CONFIG/regatta/projects" ] || echo "$HOME/projects" > "$REGATTA_CONFIG/regatta/projects"
mkdir -p "$HOME/projects/demo" "$HOME/.local/bin" "$HOME/Library/LaunchAgents" "$HOME/.claude/sessions" "$T/coding/bin" "$T/stub" "$T/pids" "$T/kids"
touch "$HOME/.local/bin/claude"; chmod +x "$HOME/.local/bin/claude"   # claude-host always starts this file: a launcher needs it executable
# Links, not copies (B7): rc-hosts finds the core from its own resolved path (lib/core_path.py), and
# reads the registry and the launcher's source through the overrides below, never the real ones.
ln -s "$B/rc-hosts" "$T/coding/bin/rc-hosts"
mkdir -p "$HOME/projects/overlay/bin"; ln -s "$B/rc-hosts" "$HOME/projects/overlay/bin/rc-hosts"   # the primary's, which the walk's job runs
export CLAUDE_REPOS_JSON="$T/coding/repos.json" RC_HOSTS_SOURCE="$T/coding/bin/claude-host.c" RC_HOSTS_CLOSING="$T/closing"
# claude-host.c is the overlay's (it names the overlay's scripts), in the caller's overlay checkout
# (SUITE_OVERLAY); the launcher cases build it, so without one the suite says so and stops
CH="${SUITE_OVERLAY:+$SUITE_OVERLAY/bin/claude-host.c}"; [ -f "$CH" ] || CH=""
[ -n "$CH" ] || { echo "  --   test_rc_hosts skipped: no claude-host.c here (the overlay's launcher source)"; exit 0; }
echo '{"repos": {"demo": {"hosts": ["laptop"], "rc": true}}}' > "$T/coding/repos.json"
# launchctl: a host is running while $T/pids/<label> holds its pid; every call is logged.
cat > "$T/stub/launchctl" <<EOF
#!/bin/sh
echo "\$*" >> "$T/calls"
label=\${2##*/}
case "\$1" in
  print) if [ -f "$T/down/\$label" ]; then printf '\tstate = spawn scheduled\n'; exit 0; fi   # loaded, process down (KeepAlive)
         [ -f "$T/pids/\$label" ] || exit 113; p=\$(cat "$T/pids/\$label")
         # program = claude-host for a pid marked $T/launcher-PID, as launchctl prints the job's program
         if [ -f "$T/launcher-\$p" ]; then prog="$HOME/.local/bin/claude-host"; else prog="$HOME/.local/bin/claude"; fi
         printf '\tstate = running\n\tprogram = %s\n\tpid = %s\n' "\$prog" "\$p";;
  kickstart) if [ "\$2" = -k ]; then label=\${3##*/}; echo \$(( \$(cat "$T/pids/\$label") + 1 )) > "$T/pids/\$label"
             else label=\${2##*/}; [ -f "$T/pids/\$label" ] || echo \$(( \$(cat "$T/killed-\$label" 2>/dev/null || echo 500) + 1 )) > "$T/pids/\$label"; fi;;
  kill) label=\${3##*/}; [ -f "$T/pids/\$label" ] && { cat "$T/pids/\$label" > "$T/killed-\$label"; rm -f "$T/pids/\$label"; };;
  list) for f in "$T"/pids/*; do [ -f "\$f" ] && printf '%s\t0\t%s\n' "\$(cat "\$f")" "\$(basename "\$f")"; done;;
  bootout) rm -f "$T/pids/\$label";;
  bootstrap) [ -f "$T/bootstrap-fails" ] && exit 5; label=\$(basename "\$3" .plist); echo 500 > "$T/pids/\$label"
             # the Full Disk Access probe: ok once $T/fda exists; $T/fda-next says denied once, then grants
             # the privacy job (--probe-all, the walk): its plist kept for the suite, and $T/tcc.json
             # as its answer, else every service ok; $T/tcc-next once, then ok (a switch turned on)
             if [ "\$label" = org.example.claude.tcc-probe ]; then
               cp "\$3" "$T/tcc-job.plist"; plutil -extract ProgramArguments json -o - "\$3" >> "$T/tcc-jobs"
               if [ -f "$T/tcc-next" ]; then cp "$T/tcc-next" "$HOME/Library/Logs/claude-host/tcc-probe.json"; rm -f "$T/tcc-next"
               elif [ -f "$T/tcc.json" ]; then cp "$T/tcc.json" "$HOME/Library/Logs/claude-host/tcc-probe.json"
               else echo '{"results": {"fda": {"what": "Full Disk Access", "result": "ok"}, "app-management": {"what": "App Management", "result": "ok"}}}' > "$HOME/Library/Logs/claude-host/tcc-probe.json"; fi
             fi
             if [ "\$label" = org.example.claude.fda-probe ]; then
               if [ -f "$T/fda" ]; then echo "probe: ok"; else echo "probe: denied"; [ -f "$T/fda-next" ] && touch "$T/fda"; fi \
                 > "$HOME/Library/Logs/claude-host/fda-probe.log"
             fi;;
esac
EOF
printf '#!/bin/sh\ncat "%s/kids/$2" 2>/dev/null\n' "$T" > "$T/stub/pgrep"
# orca: the clock's automations for --agents (bin/clock), from $T/autos.json; none by default, so no
# case reads this Mac's real Orca
cat > "$T/stub/orca" <<EOF
#!/bin/sh
case "\$*" in
  "automations list"*) printf '{"ok": true, "result": {"automations": %s}}\n' "\$(cat "$T/autos.json" 2>/dev/null || echo '[]')";;
  *) printf '{"ok": true, "result": {"runs": []}}\n';;
esac
EOF
chmod +x "$T/stub/orca"; export ORCA_HOST_CLI="$T/stub/orca"
printf '#!/bin/sh\necho "$*" >> "%s/opened"\n' "$T" > "$T/stub/open"   # never System Settings for real
printf '#!/bin/sh\necho laptop\n' > "$T/stub/scutil"
# ps: a process's start (-o lstart= -p PID, from $T/lstart-PID; none: unreadable) and the table
# (-axo, from $T/ps-ax) — the pids here are the stubs' own numbers, never real processes
cat > "$T/stub/ps" <<PSEOF
#!/bin/sh
case "\$*" in *lstart*) cat "$T/lstart-\$4" 2>/dev/null;; *-axo*) cat "$T/ps-ax" 2>/dev/null;; esac
PSEOF
# lsof: the file a process runs (-d txt -Fn), from $T/exe-PID; none: unreadable, as for a process
# that is not ours (rc-hosts exe_of)
# (the pid is the word after -p, wherever the flags put it); RC_HOSTS_GONE_PIDS keeps every stub pid
# from the real proc_pidpath, where a live process of this Mac could answer for it
printf '#!/bin/sh\nwhile [ $# -gt 0 ] && [ "$1" != -p ]; do shift; done; pid=$2\n[ -f "%s/exe-$pid" ] && printf "p%%s\\nftxt\\nn%%s\\n" "$pid" "$(cat "%s/exe-$pid")"\nexit 0\n' "$T" "$T" > "$T/stub/lsof"
export RC_HOSTS_GONE_PIDS=""
chmod +x "$T/stub/"*
export PATH="$T/stub:$PATH"
L=org.example.claude.host.demo; LOG="$HOME/Library/Logs/claude-host/demo.log"
RC() { python3 "$T/coding/bin/rc-hosts" "$@" > "$T/out" 2>&1; echo $?; }
session() {  # session <pid> <idle|busy> [minutes since]: a host child with Claude Code's record of it
  echo "$1" > "$T/kids/$(cat "$T/pids/$L")"
  echo "{\"pid\":$1,\"sessionId\":\"5e55$1-0000\",\"status\":\"$2\",\"statusUpdatedAt\":$(( ($(date +%s) - ${3:-0} * 60) * 1000 )),\"cwd\":\"$HOME/projects/demo\"}" > "$HOME/.claude/sessions/$1.json"
}
nosession() { rm -f "$T/kids/"*; }
repo() {  # repo <dir> [days ago]: a git repo whose one commit is that old (rc-hosts wants activity)
  mkdir -p "$1"; git -C "$1" init -q
  GIT_COMMITTER_DATE="@$(( $(date +%s) - ${2:-0} * 86400 )) +0000" \
    git -C "$1" -c user.name=t -c user.email=t@t commit -q --allow-empty -m x
}
repo "$HOME/projects/demo"

echo "setup"
check "$(RC)" "0" "a missing host is written and loaded"
has "$T/out" "missing  demo · laptop → writing and loading" "…said"
check "$(cat "$T/pids/$L")" "500" "…and running"
check "$(plutil -extract ProgramArguments json -o - "$HOME/Library/LaunchAgents/$L.plist" | grep -o '"--permission-mode","[a-zA-Z]*"')" '"--permission-mode","auto"' "…in auto mode, as the laptop's sessions (host parity, 2026-10-04)"
printf 'Ready · demo · main\n    Capacity: 0/2\n' >> "$LOG"

echo "--restart restarts, in sync or not (it used to print \"in sync\" and do nothing)"
: > "$T/calls"
check "$(RC --restart demo)" "0" "--restart on an in-sync running host"
has "$T/out" "restart  demo · laptop: running" "…restarts it"
has "$T/calls" "bootout gui/" "…through bootout and bootstrap"
hasnt "$T/out" "in sync" "…and never just reports it in sync"
session 701 busy; : > "$T/calls"
check "$(RC --restart demo)" "1" "--restart with a busy session"
has "$T/out" "busy     demo · laptop: session(s) [701] busy" "…refuses and names it"
hasnt "$T/calls" "bootout" "…ending nothing"
session 701 idle
check "$(RC --restart demo)" "0" "--restart with an idle session"
has "$T/out" "restart  demo · laptop" "…goes ahead"
echo 777 > "$T/kids/$(cat "$T/pids/$L")"; : > "$T/calls"
check "$(RC --restart demo)" "1" "--restart with a child that has no record yet"
has "$T/out" "busy     demo · laptop: session(s) [777] busy" "…counts it as busy, as --end does"
hasnt "$T/calls" "bootout" "…ending nothing"
nosession
check "$(RC --restart nosuch)" "1" "--restart of a name that is no host here"
has "$T/out" "nosuch: no such host here (demo)" "…says so"

echo "revive: an empty host that reconnected since the last run is restarted"
check "$(RC --reap)" "0" "first reaper run"
check "$(grep -c . "$T/out")" "0" "…only takes a baseline, silently"
check "$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["'$L'"]["pid"])' "$HOME/Library/Logs/claude-host/reap-state.json")" "$(cat "$T/pids/$L")" "…pid recorded"
check "$(RC --reap)" "0" "no reconnect since"
check "$(grep -c . "$T/out")" "0" "…nothing to do"
printf '[11:37:36] Reconnected after 1m 7s\n' >> "$LOG"
session 702 idle; : > "$T/calls"
check "$(RC --reap)" "0" "a reconnect, one session on the host"
has "$T/out" "waiting    demo · laptop: reconnected since the last run, 1 session(s)" "…waits, and says so"
hasnt "$T/calls" "kickstart" "…restarting nothing"
check "$(RC --reap)" "0" "still that session"
check "$(grep -c . "$T/out")" "0" "…said once, not every hour"
nosession; before=$(cat "$T/pids/$L")
check "$(RC --reap --dry-run)" "0" "the session gone, --dry-run"
has "$T/out" "would restart demo · laptop" "…would restart"
check "$(cat "$T/pids/$L")" "$before" "…and does not"
check "$(RC --reap)" "0" "the session gone"
has "$T/out" "restarting demo · laptop: reconnected since the last run, no sessions" "…restarts it"
has "$T/calls" "kill SIGTERM gui/" "…with SIGTERM, which claude-host forwards to claude"
hasnt "$T/calls" "kickstart -k" "…never kickstart -k: its SIGKILL left claude running without its claude-host (2026-10-18)"
has "$T/out" "restarted, pid $((before + 1))" "…and reads the new pid back"
check "$(RC --reap)" "0" "the next run"
check "$(grep -c . "$T/out")" "0" "…the old reconnect is not acted on twice"

echo "a terminal's claude rc holds the slot"
rm -f "$T/pids/$L"; mkdir -p "$T/down"; touch "$T/down/$L"   # launchd keeps the job, its process exits every 30 s
check "$(RC --reap)" "0" "host down, nothing in the log"
check "$(grep -c . "$T/out")" "0" "…silent"
printf 'Error: This folder is already served by a terminal `claude remote-control` on this device. Stop it first.\n' >> "$LOG"
check "$(RC --reap)" "0" "host down, served by a terminal"
has "$T/out" "blocked    demo · laptop: another \`claude remote-control\` on this machine serves demo" "…one line for reap.log"
printf 'Error: This folder is already served by a terminal `claude remote-control` on this device. Stop it first.\n' >> "$LOG"
check "$(RC --reap)" "0" "still served"
check "$(grep -c . "$T/out")" "0" "…said once"
rm -f "$T/down/$L"

echo "a host whose claude version was deleted under it (a film repo's host on the build Mac, 2026-10-23)"
V="$HOME/.local/share/claude/versions"; mkdir -p "$V"; touch "$V/2.1.307"
echo 520 > "$T/pids/$L"; echo "$V/2.1.307" > "$T/exe-520"
check "$(RC --check)" "0" "--check, the host's version installed"
hasnt "$T/out" "FAIL" "…no failure"
check "$(RC --broken)" "0" "--broken, the same"
has "$T/out" "ok       every host's claude is still installed" "…says so"
echo "$V/2.1.304" > "$T/exe-520"
session 8071 idle 30; echo "$V/2.1.304" > "$T/exe-8071"
check "$(RC --check)" "1" "--check, the host runs a version gone from versions/"
has "$T/out" "FAIL     demo · laptop: broken: its claude 2.1.304 was removed; new sessions fail" "…prints the failure"
hasnt "$T/out" "in sync" "…never in sync, as it read before"
check "$(RC --broken)" "3" "--broken, what bin/health asks: 3, never a crash's 1"
has "$T/out" "FAIL     demo · laptop: broken: its claude 2.1.304 was removed" "…the same line"
: > "$T/calls"; rm -rf "$RC_HOSTS_CLOSING"   # the --restart cases above left theirs
check "$(RC --reap --dry-run)" "0" "--reap --dry-run, one idle session"
has "$T/out" "would restart demo · laptop: its claude 2.1.304 was removed, new sessions fail" "…plans its restart"
has "$T/out" "would end 1 idle session(s): 8071 idle" "…naming the session it would end"
hasnt "$T/calls" "kill" "…and ends nothing"
check "$(ls -A "$RC_HOSTS_CLOSING" 2>/dev/null | wc -l | tr -d ' ')" "0" "…nor leaves a close reason for a session it did not close"
session 8071 busy
check "$(RC --reap --dry-run)" "0" "--reap --dry-run, the session busy"
has "$T/out" "broken     demo · laptop: its claude 2.1.304 was removed; session(s) [8071] busy" "…refuses, naming it"
hasnt "$T/out" "would restart demo" "…and plans no restart"
session 8071 idle 2
check "$(RC --reap --dry-run)" "0" "--reap --dry-run, the session idle 2 min (between two turns from the phone)"
has "$T/out" "session(s) [8071] busy or idle under 10 min" "…spares it"
hasnt "$T/out" "would restart demo" "…and plans no restart"
session 8071 idle 30; rm -f "$T/exe-520"
check "$(RC --broken)" "3" "the host's file unreadable, its session on a gone version"
check "$(RC_HOSTS_GONE_PIDS=8071 RC --broken)" "3" "…lsof without a name, proc_pidpath's ENOENT: the session record's version"
has "$T/out" "its claude 2.1.304 was removed" "…named"
touch "$V/2.1.304"
check "$(RC_HOSTS_GONE_PIDS=8071 RC --broken)" "0" "…but that version installed again spawns: not broken"
rm -f "$V/2.1.304"
echo "$V/2.1.304" > "$T/exe-520"; : > "$T/calls"
check "$(RC --reap)" "0" "--reap, the session idle"
has "$T/out" "restarting demo · laptop: its claude 2.1.304 was removed" "…restarts the host"
has "$T/out" "ending 1 idle session(s): 8071" "…logging the session it ends"
has "$T/calls" "kill SIGTERM gui/$(id -u)/$L" "…by SIGTERM, as every restart here"
has "$T/out" "restarted, pid 521" "…and reads the new pid back"
has "$LOG" "rc-hosts: closing session 5e558071-0000 (pid 8071, 'demo'), idle 0.5 h: the hourly rc-hosts --reap restarts this host, whose claude 2.1.304 was deleted under it" "…first saying so in the host's own log, so its \"Session failed\" line reads as the close"
check "$(RC --broken)" "0" "the restarted host"
check "$(python3 - "$T/coding/bin/rc-hosts" "$T/note.log" <<'PY'
import importlib.machinery as m, importlib.util as u, sys
l = m.SourceFileLoader("r", sys.argv[1]); s = u.spec_from_loader("r", l); r = u.module_from_spec(s); l.exec_module(r)
rec = {"cwd": str(r.PROJECTS / "film" / "bridge-cse_01RCNV19JH34z6RVab3kzS3o"), "name": "NAS copy failures"}
r.note_close({"StandardOutPath": sys.argv[2]}, 96160, rec, "idle 12.4 h: the hourly rc-hosts --reap ends a session idle 12 h or more")
r.note_close({"StandardOutPath": "/nonexistent/dir/x.log"}, 1, {}, "x")   # an unwritable log: no crash
print(open(sys.argv[2]).read().split("] ", 1)[1].strip())
PY
)" "rc-hosts: closing session cse_01RCNV19JH34z6RVab3kzS3o (pid 96160, 'NAS copy failures'), idle 12.4 h: the hourly rc-hosts --reap ends a session idle 12 h or more — the \"Session failed\" line after this is that close, not a fault" "a bridge session is named by its cse_ id and title, as the host's own lines name it"

echo "close_reason: the session's own last stderr line names the close (2026-10-24)"
check "$(cat "$RC_HOSTS_CLOSING/5e558071-0000" 2>/dev/null)" "closed by rc-hosts — idle 0.5 h: the hourly rc-hosts --reap restarts this host, whose claude 2.1.304 was deleted under it" "the restart above left the reason under the session's id"
H="$B/../hooks/close_reason.py"
out=$(echo '{"session_id": "5e558071-0000", "hook_event_name": "SessionEnd"}' | python3 "$H" 2>&1 >/dev/null); rc=$?
check "$rc:$out" "1:closed by rc-hosts — idle 0.5 h: the hourly rc-hosts --reap restarts this host, whose claude 2.1.304 was deleted under it" "the hook prints it on stderr and exits 1, which Claude Code reports as the session's last line"
out=$(echo '{"session_id": "5e558071-0000"}' | python3 "$H" 2>&1); rc=$?
check "$rc:$out" "0:" "…once: the marker is gone, so the same id resumed later ends silently"
echo "closed by rc-hosts — long ago" > "$RC_HOSTS_CLOSING/old-one"; touch -t 202601010000 "$RC_HOSTS_CLOSING/old-one"
out=$(echo '{"session_id": "old-one"}' | python3 "$H" 2>&1); rc=$?
check "$rc:$out" "0:" "a marker over an hour old is stale: silent"
out=$(echo '{"session_id": "a-session-nobody-closed"}' | python3 "$H" 2>&1); rc=$?
check "$rc:$out" "0:" "a session rc-hosts did not close: silent, exit 0"
out=$(echo 'not json' | python3 "$H" 2>&1); rc=$?
check "$rc:$out" "0:" "unreadable input: silent, exit 0"
out=$(echo '{"session_id": 5}' | python3 "$H" 2>&1); rc=$?
check "$rc:$out" "0:" "a session id that is no string: silent, exit 0, never a traceback"
echo secret > "$T/outside"
out=$(echo '{"session_id": "../outside"}' | python3 "$H" 2>&1); rc=$?
check "$rc:$out" "0:" "a session id that is a path reads nothing (../outside is the real file next to the closing folder)"
check "$(env -u RC_HOSTS_CLOSING python3 - "$T/coding/bin/rc-hosts" "$H" <<'PY'
import importlib.machinery as m, importlib.util as u, sys
def load(name, path):
    l = m.SourceFileLoader(name, path); s = u.spec_from_loader(name, l); r = u.module_from_spec(s); l.exec_module(r); return r
print(load("r", sys.argv[1]).CLOSING == load("h", sys.argv[2]).CLOSING)
PY
)" "True" "rc-hosts writes where the hook reads: the two defaults are one path"
check "$(python3 - "$T/coding/bin/rc-hosts" <<'PY'
import importlib.machinery as m, importlib.util as u, sys
l = m.SourceFileLoader("r", sys.argv[1]); s = u.spec_from_loader("r", l); r = u.module_from_spec(s); l.exec_module(r)
r.exe_of = lambda pid: None   # lsof lost the name of the deleted file, proc_pidpath says ENOENT
r.pidpath_gone = lambda pid: True
r.record = lambda pid: {"version": "2.1.304"} if pid == 8071 else None
print(r.gone_version(520), r.gone_version(8071))
PY
)" "(version unknown) 2.1.304" "lsof without a name: proc_pidpath's ENOENT still reads gone, the version from the session record"
nosession; rm -f "$T/exe-"* "$HOME/.claude/sessions/8071.json"
python3 - "$T/coding/bin/rc-hosts" "$LOG" <<'PY' > "$T/out" 2>&1
import importlib.machinery as m, importlib.util as u, json, sys
l = m.SourceFileLoader("r", sys.argv[1]); s = u.spec_from_loader("r", l); r = u.module_from_spec(s); l.exec_module(r)
r.LOG_CAP, r.LOG_HEAD, r.LOG_TAIL = 1000, 10, 100
log = r.Path(sys.argv[2]); body = b"H" * 10 + b"x" * 4890 + b"T" * 100
def setoff(off, **kw):
    st = r.LOGS / "reap-state.json"; state = json.loads(st.read_text())
    state["org.example.claude.host.demo"] = {**state["org.example.claude.host.demo"], "offset": off, **kw}; st.write_text(json.dumps(state))
def off():
    return json.loads((r.LOGS / "reap-state.json").read_text())["org.example.claude.host.demo"]["offset"]
log.write_bytes(body); setoff(4000)
r.cap_logs(True); print("dry", log.stat().st_size)
r.cap_logs(False); b = log.read_bytes()
print(len(b) < 200, b.startswith(b"H" * 10 + b"\n[rc-hosts cut 4890 bytes"), b.endswith(b"T" * 100), off() == len(b) - 100)
log.write_bytes(body); setoff(4950); r.cap_logs(False); b = log.read_bytes()
print("tail", off() == len(b) - 50, b[off():] == b"T" * 50)
log.write_bytes(body); setoff(4000, waiting=True); r.cap_logs(False)
print("waiting", log.stat().st_size, off())
PY
has "$T/out" "would cap  demo.log" "cap_logs --dry-run names the log"
has "$T/out" "dry 5000" "…and leaves it whole"
has "$T/out" "True True True True" "cap_logs keeps the head and the tail in place; an offset before the tail moves to its start"
has "$T/out" "tail True True" "…one inside the tail keeps its line"
has "$T/out" "waiting 5000 4000" "…and a host revive() waits on is not cut"
printf 'Ready · demo · main\n    Capacity: 0/2\n' > "$LOG"

echo "every repo gets a host unless it says \"rc\": false (2026-10-07)"
repo "$HOME/projects/plain"; repo "$HOME/projects/off"
echo '{"repos": {"plain": {"hosts": ["laptop"]}, "off": {"hosts": ["laptop"], "rc": false}, "elsewhere": {"hosts": ["buildbox"]}}}' > "$T/coding/repos.json"
check "$(RC --check)" "0" "--check over a registry with no rc keys"
has "$T/out" "missing  plain · laptop" "…a repo with no rc key wants a host"
hasnt "$T/out" "off · laptop" "…\"rc\": false wants none"
hasnt "$T/out" "elsewhere" "…nor a repo this host does not clone"
RC >/dev/null
check "$(plutil -extract ProgramArguments json -o - "$HOME/Library/LaunchAgents/org.example.claude.host.plain.plist" | grep -o '"--spawn","[a-z-]*","--capacity","[0-9]*"')" '"--spawn","worktree","--capacity","8"' "…its defaults: a worktree per session, 8 of them"

echo "only repos worked on in the last 30 days, never a public twin (rc-slots D4)"
repo "$HOME/projects/fresh" 2; repo "$HOME/projects/stale" 45; repo "$HOME/projects/twin"; repo "$HOME/projects/unlisted"
echo '{"repos": {"plain": {"hosts": ["laptop"]}, "fresh": {"hosts": ["laptop"]}, "stale": {"hosts": ["laptop"]}, "twin": {"hosts": ["laptop"], "twin_of": "plain"}}}' > "$T/coding/repos.json"
cp "$HOME/Library/LaunchAgents/org.example.claude.host.plain.plist" "$HOME/Library/LaunchAgents/org.example.claude.host.demo.plist"
echo 800 > "$T/pids/org.example.claude.host.demo"   # a host from a branch that never landed
check "$(RC --check)" "0" "--check"
has "$T/out" "missing  fresh · laptop" "…a commit 2 days old wants a host"
hasnt "$T/out" "stale · laptop" "…45 days old wants none"
hasnt "$T/out" "twin · laptop" "…nor a public twin"
has "$T/out" "unregistered  unlisted: no host until repos.json lists it" "…a repo on disk repos.json lacks is named"
has "$T/out" "unwanted org.example.claude.host.demo: retires on the next run" "…a host no repo claims is named"
check "$(plutil -extract ProgramArguments json -o - "$HOME/Library/LaunchAgents/org.example.claude.host.plain.plist" | grep -c no-create-session-in-dir)" "1" "no pre-created session (rc-slots D3)"
echo 900 > "$T/pids/org.example.claude.host.held"; echo 901 > "$T/kids/900"
cp "$HOME/Library/LaunchAgents/org.example.claude.host.plain.plist" "$HOME/Library/LaunchAgents/org.example.claude.host.held.plist"
check "$(RC --check)" "0" "an unwanted host holding a session"
has "$T/out" "unwanted org.example.claude.host.held: holds a session — retires once empty" "…is said to wait"
: > "$T/calls"
check "$(RC)" "0" "a plain run"
has "$T/out" "retiring org.example.claude.host.demo" "…retires the empty unwanted host"
check "$(ls "$HOME/Library/LaunchAgents" | grep -c 'host.demo.plist')" "0" "…its plist gone"
has "$T/calls" "bootout gui/$(id -u)/org.example.claude.host.demo" "…unloaded"
has "$T/out" "waiting  org.example.claude.host.held" "…and leaves the one with a session"
check "$(ls "$HOME/Library/LaunchAgents" | grep -c 'host.held.plist')" "1" "…its plist kept"
echo "{\"pid\":901,\"sessionId\":\"5e55901-0000\",\"status\":\"idle\",\"statusUpdatedAt\":$(( ($(date +%s) - 13 * 3600) * 1000 )),\"cwd\":\"$HOME/projects/plain\"}" > "$HOME/.claude/sessions/901.json"
check "$(RC --reap --dry-run)" "0" "--reap --dry-run with the unwanted host's session idle 13 h"
has "$T/out" "would end  plain · laptop: 901, idle 13" "…the reaper sees it, so the host can empty and retire (review, 2026-10-14)"
check "$(RC --end 5e55901 --dry-run)" "0" "--end finds a session on an unwanted host"
rm -f "$HOME/.claude/sessions/901.json"
: > "$T/calls"
check "$(RC)" "0" "a plain run again"
hasnt "$T/out" "unregistered" "…names no unregistered repo: that is --check's question"
mkdir -p "$HOME/projects/broken"; echo "gitdir: /nowhere" > "$HOME/projects/broken/.git"
echo '{"repos": {"plain": {"hosts": ["laptop"]}, "fresh": {"hosts": ["laptop"]}, "broken": {"hosts": ["laptop"]}}}' > "$T/coding/repos.json"
check "$(RC --check)" "0" "a repo whose commits cannot be read"
has "$T/out" "missing  broken · laptop" "…keeps (here: wants) its host: retiring is the costly side"
rm_own "$HOME/projects/broken"
echo '{"repos": {"plain": {"hosts": ["laptop"]}, "fresh": {"hosts": ["laptop"]}, "stale": {"hosts": ["laptop"]}, "twin": {"hosts": ["laptop"], "twin_of": "plain"}}}' > "$T/coding/repos.json"

echo "the reaper converges: a new host loads, an empty changed one reloads, a busy one waits"
rm -f "$T/pids/org.example.claude.host.fresh" "$HOME/Library/LaunchAgents/org.example.claude.host.fresh.plist"
check "$(RC --reap)" "0" "--reap with fresh's host missing"
has "$T/out" "loading    fresh · laptop: new here" "…loads it"
test -f "$HOME/Library/LaunchAgents/org.example.claude.host.fresh.plist"; check $? 0 "…writes its plist"
echo 600 > "$T/pids/org.example.claude.host.fresh"; echo 700 > "$T/pids/org.example.claude.host.plain"   # the stub gives every host 500
echo '{"repos": {"plain": {"hosts": ["laptop"], "rc": {"capacity": 4}}, "fresh": {"hosts": ["laptop"], "rc": {"capacity": 4}}}}' > "$T/coding/repos.json"
echo 951 > "$T/kids/$(cat "$T/pids/org.example.claude.host.plain")"; rm -f "$T/kids/900"
check "$(RC --reap)" "0" "--reap after a capacity change"
has "$T/out" "loading    fresh · laptop: plist changed, no session" "…reloads the empty host"
hasnt "$T/out" "plain · laptop" "…not the one holding a session"
check "$(plutil -extract ProgramArguments json -o - "$HOME/Library/LaunchAgents/org.example.claude.host.plain.plist" | grep -o '"--capacity","[0-9]*"')" '"--capacity","8"' "…whose plist stays as it was"
has "$T/out" "retiring org.example.claude.host.held" "…and retires held once it is empty"
rm -f "$T/pids/org.example.claude.host.fresh"   # its plist in sync, the job not loaded: a failed bootstrap
check "$(RC --reap)" "0" "--reap with fresh's job not loaded"
has "$T/out" "loading    fresh · laptop: not loaded" "…loads it again"

echo "claude-host: hosts start through it once --grant has seen it hold Full Disk Access (2026-10-17)"
cp "$CH" "$T/coding/bin/claude-host.c"
nosession; rm -f "$T/pids/"*
echo '{"repos": {"fresh": {"hosts": ["laptop"]}}}' > "$T/coding/repos.json"
F="$HOME/Library/LaunchAgents/org.example.claude.host.fresh.plist"
prog() { plutil -extract ProgramArguments.0 raw -o - "$F"; }
check "$(RC --check)" "0" "--check before any grant"
has "$T/out" "claude-host: not built" "…names the launcher as missing"
RC --reap >/dev/null
check "$(prog)" "$HOME/.local/bin/claude" "…and hosts run claude directly, as before"
touch "$T/fda-next"
check "$(RC --grant)" "0" "--grant, switched on while it waits"
has "$T/out" "built    $HOME/.local/bin/claude-host" "…builds the launcher"
check "$(codesign -dv "$HOME/.local/bin/claude-host" 2>&1 | grep '^Identifier=')" "Identifier=org.example.claude-host" "…signed with its own identifier"
"$HOME/.local/bin/claude-host" -p hi > "$T/launcher.out" 2>&1; check $? 2 "the launcher refuses anything but remote-control and --probe"
has "$T/launcher.out" "usage: claude-host remote-control" "…and says what it runs"
has "$T/out" "drag claude-host into the list" "…walks the grant"
has "$T/opened" "Privacy_AllFiles" "…opens System Settings on Full Disk Access"
has "$T/opened" "-R $HOME/.local/bin/claude-host" "…and shows the binary in Finder"
has "$T/out" "claude-host holds Full Disk Access" "…sees the probe pass"
check "$(prog)" "$HOME/.local/bin/claude-host" "…and moves the empty host over"
test -f "$HOME/Library/LaunchAgents/org.example.claude.fda-probe.plist"; check $? 1 "…leaving no probe job behind"
check "$(RC --check)" "0" "--check after the grant"
has "$T/out" "ok       claude-host: held Full Disk Access" "…says so"
: > "$T/opened"
check "$(RC --grant)" "0" "--grant again"
hasnt "$T/out" "built    " "…does not rebuild an unchanged launcher (a rebuild costs the grant)"
check "$(grep -c . "$T/opened")" "0" "…nor opens System Settings"
echo '/* changed */' >> "$T/coding/bin/claude-host.c"
check "$(RC --check)" "0" "--check after claude-host.c changed"
has "$T/out" "built from an older claude-host.c" "…says the grant is needed again"
RC --reap >/dev/null
check "$(prog)" "$HOME/.local/bin/claude-host" "…while the granted build keeps serving"
rm -f "$HOME/.local/bin/claude-host.granted"
RC --reap >/dev/null
check "$(prog)" "$HOME/.local/bin/claude" "no grant on record: back to claude directly"

echo "behind claude-host the host is its child: sessions are the child's children"
echo 610 > "$T/pids/org.example.claude.host.fresh"; touch "$T/launcher-610"; echo 611 > "$T/kids/610"; echo 712 > "$T/kids/611"
echo "{\"pid\":712,\"sessionId\":\"5e55712-0000\",\"status\":\"idle\",\"statusUpdatedAt\":$(( ($(date +%s) - 13 * 3600) * 1000 )),\"cwd\":\"$HOME/projects/fresh\"}" > "$HOME/.claude/sessions/712.json"
check "$(RC --reap --dry-run)" "0" "--reap --dry-run, a session idle 13 h under claude-host"
has "$T/out" "would end  fresh · laptop: 712, idle 13" "…finds the session below claude-host's child"
hasnt "$T/out" "611" "…never takes claude itself for a session"
check "$(RC --idle)" "0" "--idle"
has "$T/out" "712" "…lists that session"

echo "claude-host 2: one identity for every claude not started by an app (docs/tcc-one-identity-2026-10-18.md)"
H="$HOME/.local/bin/claude-host"
cp "$CH" "$T/coding/bin/claude-host.c"; : > "$T/opened"   # back to this source: --grant rebuilds it
check "$(RC --grant)" "0" "--grant on the current source: the sitting"
has "$T/out" "--       org.example.claude.host.fresh: starts claude itself, whose path every update replaces (a host holding a session" "…and ends on --agents --fix, a host holding a session pending, not a failure"
hasnt "$T/out" "BARE " "…nothing counted against the sitting"
# a rebuild under a running host whose plist already names claude-host: the plist compares equal,
# so only the image's age says it runs the old build (review, 2026-10-18)
lstart() { LC_ALL=C date -r "$2" '+%a %b %d %H:%M:%S %Y' > "$T/lstart-$1"; }
built=$(stat -f %m "$HOME/.local/bin/claude-host.source-sha256")
# a host still loaded bare at --grant: its job is claude, started before the build — no old
# claude-host to restart; converge moves it once (review, 2026-10-18)
lstart "$(cat "$T/pids/org.example.claude.host.fresh")" $((built - 3600)); rm -f "$T/kids/"*
check "$(RC --grant)" "0" "--grant with a host still loaded bare"
hasnt "$T/out" "restart  fresh" "…restarts nothing for it (its job is claude, not an old claude-host)"
has "$T/out" "loading    fresh · laptop: plist changed, no session" "…converge moves it, once"
rm -f "$T/kids/"*; RC --reap >/dev/null   # empty now: converge moves it to claude-host
check "$(prog)" "$H" "an empty host moves to claude-host"
FP=$(cat "$T/pids/org.example.claude.host.fresh"); lstart "$FP" $((built + 60))
check "$(RC --reap)" "0" "--reap, the host started after the build"
hasnt "$T/out" "fresh · laptop" "…is left alone"
lstart "$FP" $((built - 3600)); echo 631 > "$T/kids/$FP"
check "$(RC --grant)" "0" "--grant, the host started before the build and holding a session"
has "$T/out" "waiting  fresh · laptop: runs the old claude-host, holds a session" "…waits for it, says so"
check "$(cat "$T/pids/org.example.claude.host.fresh")" "$FP" "…and restarts nothing"
rm -f "$T/kids/$FP"; : > "$T/calls"
check "$(RC --grant)" "0" "--grant once it is empty"
has "$T/out" "restart  fresh · laptop: the old claude-host image" "…restarts it"
has "$T/calls" "kill SIGTERM gui/$(id -u)/org.example.claude.host.fresh" "…by SIGTERM, which claude-host forwards"
FP=$(cat "$T/pids/org.example.claude.host.fresh"); lstart "$FP" $((built - 3600))
check "$(RC --reap)" "0" "the hourly reap meets a host on the old image"
has "$T/out" "loading    fresh · laptop: the old claude-host image, no session" "…and reloads it too"
hasnt "$T/opened" "Privacy_AppBundles" "…App Management already on: its pane is not opened"
check "$("$H" --version)" "claude-host 2" "--version says 2: it runs scripts and claude, not only remote-control"
"$H" --probe > "$T/probe.out" 2>&1
has "$T/probe.out" "responsible: self" "started from this shell, it re-executes itself as its own responsible process"
# the allowlist, on a second build whose claude and overlay/bin are this suite's stubs (the build
# rc-hosts makes never defines them): what it runs, with what arguments, and what it refuses
mkdir -p "$T/cb"; TB="$T/claude-host-test"
for s in dispatch dispatch-rc weekly-run autofinish usage-report rc-hosts; do
  printf '#!/bin/sh\necho "%s $*"\n' "$s" > "$T/cb/$s"; chmod +x "$T/cb/$s"
done
# a compiled stub, not a script: SIP strips DYLD_* from /bin/sh itself, which would hide a leak
cat > "$T/cb-claude.c" <<'CEOF'
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
static void got(int s) { (void)s; printf("got TERM\n"); fflush(stdout); _exit(0); }
int main(int c, char **v) {
    printf("claude");
    for (int i = 1; i < c; i++) printf(" %s", v[i]);
    if (getenv("DYLD_FALLBACK_LIBRARY_PATH")) printf(" DYLD!");
    sigset_t m; sigprocmask(SIG_BLOCK, NULL, &m);
    if (sigismember(&m, SIGTERM)) printf(" TERM-BLOCKED");
    printf("\n"); fflush(stdout);
    if (c > 1 && strcmp(v[1], "wait") == 0) { signal(SIGTERM, got); sleep(10); printf("no TERM\n"); }
    return 0;
}
CEOF
clang -o "$T/cb-claude" "$T/cb-claude.c"
clang -O2 -DCLAUDE_BIN="\"$T/cb-claude\"" -DCODING_BIN="\"$T/cb\"" -o "$TB" "$CH" 2>"$T/cc.err"; check $? 0 "the suite's build compiles"
check "$("$TB" claude -p hi)" "claude -p hi" "claude-host claude <args> runs claude with them"
check "$("$TB" remote-control --name x 2>/dev/null)" "claude remote-control --name x" "remote-control keeps its subcommand"
check "$("$TB" "$T/cb/dispatch" claude/x --repo r)" "dispatch claude/x --repo r" "an allowlisted script, by its exact path, with its arguments"
check "$("$TB" "$T/cb/weekly-run" aurora /tmp)" "weekly-run aurora /tmp" "…weekly-run"
printf 'import sys; print("python", *sys.argv)\n' > "$T/cb/autofinish"
check "$("$TB" /usr/bin/python3 "$T/cb/autofinish" --sweep)" "python $T/cb/autofinish --sweep" "/usr/bin/python3 <script> keeps the interpreter the plist named"
"$TB" "$T/cb/../cb/dispatch" > /dev/null 2>&1; check $? 2 "a path spelt another way is refused"
"$TB" "$T/cb/bash" -c id > /dev/null 2>&1; check $? 2 "a script not on the list is refused"
"$TB" /bin/sh -c id > /dev/null 2>&1; check $? 2 "…and a shell"
c_list=$(python3 -c 'import re,sys; m=re.search(r"SCRIPTS\[\] = \{(.*?)NULL\}", open(sys.argv[1]).read(), re.S); print(",".join(re.findall(r"\"([^\"]+)\"", m.group(1))))' "$CH")
py_list=$(python3 -c 'import importlib.machinery as m, importlib.util as u, sys; l=m.SourceFileLoader("r", sys.argv[1]); s=u.spec_from_loader("r", l); r=u.module_from_spec(s); l.exec_module(r); print(",".join(r.SCRIPTS))' "$T/coding/bin/rc-hosts")
check "$c_list" "$py_list" "claude-host.c's SCRIPTS and rc-hosts' are one list"
check "$(DYLD_FALLBACK_LIBRARY_PATH=/tmp "$T/cb-claude" x)" "claude x DYLD!" "the stub sees DYLD_* when it is passed"
check "$(DYLD_FALLBACK_LIBRARY_PATH=/tmp "$TB" claude x)" "claude x" "…and claude-host never passes it on"
"$TB" claude wait > "$T/term.out" 2>&1 & tbp=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do grep -q '^claude wait' "$T/term.out" && break; sleep 0.2; done
kill -TERM "$tbp"; wait "$tbp"
check "$(cat "$T/term.out")" "claude wait
got TERM" "a SIGTERM to claude-host reaches claude, and claude starts with TERM not held"
# the hardened runtime (review, 2026-10-18): DYLD_INSERT_LIBRARIES loads into an ad-hoc build
# without it, and the re-exec keeps it; the build rc-hosts signs refuses it, still its own responsible
printf '#include <stdio.h>\n__attribute__((constructor)) static void hit(void) { FILE *f = fopen("%s/injected", "w"); if (f) fclose(f); }\n' "$T" > "$T/inj.c"
clang -dynamiclib -o "$T/inj.dylib" "$T/inj.c"
DYLD_INSERT_LIBRARIES="$T/inj.dylib" "$TB" claude x > /dev/null 2>&1
test -f "$T/injected"; check $? 0 "a build signed without the runtime takes an inserted library (the test can see one)"
rm -f "$T/injected"
DYLD_INSERT_LIBRARIES="$T/inj.dylib" "$H" --probe > "$T/probe-inj.out" 2>&1
test -f "$T/injected"; check $? 1 "…the build rc-hosts signs with the runtime does not"
has "$T/probe-inj.out" "responsible: self" "…and still takes responsibility"
codesign -d --verbose=2 "$H" 2>&1 | grep -qE 'flags=0x[0-9a-f]+\([a-z,]*runtime'; check $? 0 "…signed with the hardened runtime"
# tccd denies a hardened process the services whose entitlement it lacks: claude-host carries them
check "$(codesign -d --entitlements - --xml "$H" 2>/dev/null | plutil -convert json -o - - | python3 -c 'import json,sys; print(" ".join(sorted(k.split(".", 3)[3] for k, v in json.load(sys.stdin).items() if v is True)))')" \
  "automation.apple-events device.audio-input device.camera personal-information.addressbook personal-information.calendars personal-information.photos-library" \
  "…with the entitlements for Automation, Contacts, Photos, Calendars, the microphone and the camera"
check "$(python3 - "$T/coding/bin/rc-hosts" <<'PY'
import importlib.machinery as m, importlib.util as u, sys
l = m.SourceFileLoader("r", sys.argv[1]); s = u.spec_from_loader("r", l); r = u.module_from_spec(s); l.exec_module(r)
a = r.source_sha(); r.ENTITLEMENTS = r.ENTITLEMENTS.replace("device.camera", "device.bluetooth"); print(a != r.source_sha())
PY
)" "True" "…and the entitlements are in the build stamp: a change rebuilds"
CLAUDE_HOST_PIDFILE="$T/child.pid" "$TB" claude wait > "$T/pf.out" 2>&1 & tbp=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$T/child.pid" ] && break; sleep 0.2; done
cpid=$(cat "$T/child.pid" 2>/dev/null)
check "$(/bin/ps -o ppid= -p "${cpid:-1}" | tr -d ' ')" "$tbp" "CLAUDE_HOST_PIDFILE: claude-host writes its child's pid there"
kill -TERM "$tbp"; wait "$tbp"
check "$(env | grep -c CLAUDE_HOST_PIDFILE; CLAUDE_HOST_PIDFILE="$T/child2.pid" "$TB" claude x | grep -c PIDFILE)" "0
0" "…and never passes the variable on (a claude-host its child starts writes nothing)"

echo "--launcher: what every plist writer asks, ready only for a granted build that says 2"
P="$HOME/projects/overlay/bin"
check "$(RC --launcher "$P/dispatch") $(cat "$T/out")" "0 $H" "granted, version 2: dispatch goes through claude-host"
check "$(RC --launcher claude) $(cat "$T/out")" "0 $H" "…and claude"
check "$(RC --launcher "$HOME/projects/overlay/.claude/worktrees/x/bin/dispatch")" "1" "…never a worktree's script, which claude-host would refuse"
check "$(RC --launcher /usr/local/bin/other)" "1" "…nor anything off the list"
# a launcher whose claude is missing is no launcher: claude-host always starts the claude binary, and its
# spawn failure reaches only the screen (launcher-clock follow-up, 2026-10-24); a script still goes through
mv "$HOME/.local/bin/claude" "$HOME/.local/bin/claude.keep"
check "$(RC --launcher claude)" "1" "…not for claude when the claude binary is missing"
check "$(RC --launcher "$HOME/.local/bin/claude")" "1" "…nor for its path"
check "$(RC --launcher "$P/dispatch") $(cat "$T/out")" "0 $H" "…but a script does (claude-host starts that file, not claude)"
chmod -x "$HOME/.local/bin/claude.keep"; mv "$HOME/.local/bin/claude.keep" "$HOME/.local/bin/claude"
check "$(RC --launcher claude)" "1" "…nor when it is not executable"
chmod +x "$HOME/.local/bin/claude"
check "$(RC --launcher claude) $(cat "$T/out")" "0 $H" "…and again once it is"

mv "$H" "$H.v2"; printf '#!/bin/sh\necho "usage: claude-host remote-control <args...> | claude-host --probe" >&2; exit 2\n' > "$H"; chmod +x "$H"
check "$(RC --launcher "$P/dispatch")" "1" "a granted build from before 2026-10-18 (no --version) hosts, but starts no script"
mv "$H.v2" "$H"
G="$HOME/.local/bin/claude-host.granted"
cp "$G" "$T/granted.keep"; rm -f "${G:?}"
check "$(RC --launcher "$P/dispatch")" "1" "no grant on record: nothing goes through it"
cp "$T/granted.keep" "$G"

echo "launcherlib: the one rule clock and helm ask through (bin/launcherlib.py)"
ll() { python3 -I -c "import sys; sys.path.insert(0, '$B'); import launcherlib as l; $1"; }
rch() {  # rch <name> <python body>: a stand-in rc-hosts, run by Python as launcherlib runs the real one
  printf 'import sys, time, os\nHOST = %s\n%s\n' "\"$H\"" "$2" > "$T/$1"
}
mkdir -p "$T/ll-dir"
rch rch-ok 'open(os.environ["LL_CALLS"], "a").write(" ".join(sys.argv[1:]) + "\n"); print(HOST)'
rch rch-fail 'print(HOST); sys.exit(1)'
rch rch-empty 'sys.exit(0)'
rch rch-banner 'print("a banner"); print(HOST)'
rch rch-dir 'print(os.path.dirname(HOST))'
rch rch-noexec 'print(HOST + ".granted")'
rch rch-gone 'print("/no/such/claude-host")'
rch rch-slow 'time.sleep(5); print(HOST)'
export LL_CALLS="$T/ll.calls"
rm -f "$T/ll.calls"
check "$(ll "print(l.ask('$T/rch-ok', 'claude'))")" "$H" "ask: the path rc-hosts printed, when it is an executable file"
check "$(cat "$T/ll.calls")" "--launcher claude" "  asked as dispatch asks"
check "$(ll "print(l.ask('$T/rch-fail', 'claude'))")" "None" "ask: a non-zero exit is bare, whatever it printed"
check "$(ll "print(l.ask('$T/rch-empty', 'claude'))")" "None" "ask: an empty answer is bare"
check "$(ll "print(l.ask('$T/rch-banner', 'claude'))")" "$H" "ask: the last line is the answer"
check "$(ll "print(l.ask('$T/rch-dir', 'claude'))")" "None" "ask: a directory is no launcher"
check "$(ll "print(l.ask('$T/rch-noexec', 'claude'))")" "None" "ask: a file that is not executable is no launcher"
check "$(ll "print(l.ask('$T/rch-gone', 'claude'))")" "None" "ask: a path that is not there is no launcher"
check "$(ll "print(l.ask('$T/no-such-script', 'claude'))")" "None" "ask: a script that does not run is bare"
check "$(ll "print(l.ask(None, 'claude'))")" "None" "ask: no rc-hosts is bare"
check "$(ll "l.ASK_TIMEOUT = 1; print(l.ask('$T/rch-slow', 'claude'))")" "None" "ask: no answer within the bound is bare"
check "$(ll "print(l.through(['/p/dispatch', '--x'], '/h/claude-host'))")" "['/h/claude-host', '/p/dispatch', '--x']" "through: the launcher first, argv as it is"
check "$(ll "print(l.through(['claude', 'a'], '/h/claude-host'))")" "['/h/claude-host', 'claude', 'a']" "through: claude stays the word claude"
check "$(ll "print(l.through(['/c/claude', 'a'], '/h/claude-host', ('claude', '/c/claude')))")" "['/h/claude-host', 'claude', 'a']" "through: a claude path of the caller's becomes the word"
check "$(ll "print(l.through(['/p/dispatch'], None))")" "['/p/dispatch']" "through: no launcher, argv as it is"

echo "--agents: nothing that starts claude may skip claude-host (the anti-whack-a-mole check)"
LA="$HOME/Library/LaunchAgents"; mkdir -p "$T/la.keep"; mv "${LA:?}"/*.plist "$T/la.keep/" 2>/dev/null
mkplist() {  # mkplist <label> <arg>...: a LaunchAgent with those ProgramArguments
  python3 -c 'import plistlib,sys; open(sys.argv[1],"wb").write(plistlib.dumps({"Label":sys.argv[2],"ProgramArguments":sys.argv[3:],"StartInterval":600}))' "$LA/$1.plist" "$@"
}
mkplist org.example.claude.dispatch.x.y.202611010900 "$P/dispatch" claude/x --repo r
mkplist org.example.claude.autofinish /usr/bin/python3 "$P/autofinish" --sweep
mkplist org.example.claude.dispatch-tidy-soon /bin/sh -c "sleep 60; '$P/dispatch-rc' tidy; sleep 120; '$P/dispatch-rc' tidy"
mkplist org.example.claude.aurora "$P/weekly-run" aurora "$HOME"
mkplist org.example.claude.host.bare "$HOME/.local/bin/claude" remote-control --name bare
mkplist org.example.claude.ok "$H" "$P/dispatch-rc" tidy; echo 960 > "$T/pids/org.example.claude.ok"   # loaded
mkplist org.example.claude.publish /usr/bin/python3 "$P/publish" --retry
mkplist com.example.other /usr/bin/true
check "$(RC --agents)" "1" "granted: a bare claude-starting job fails the check"
for l in org.example.claude.dispatch.x.y.202611010900 org.example.claude.autofinish org.example.claude.dispatch-tidy-soon org.example.claude.aurora org.example.claude.host.bare; do
  has "$T/out" "BARE     $l:" "…names $l"
done
hasnt "$T/out" "org.example.claude.ok" "…not one through claude-host"
hasnt "$T/out" "publish" "…nor a job that starts no claude"
hasnt "$T/out" "com.example" "…nor anyone else's"
echo 777 > "$T/pids/org.example.claude.aurora"   # running: --fix leaves it to finish
check "$(RC --agents --fix)" "1" "--fix, with an empty bare host and a running job left"
has "$T/out" "fixed    org.example.claude.dispatch.x.y.202611010900" "…rewrites an idle script job"
pargs() { python3 -c 'import plistlib,sys; print(" ".join(plistlib.load(open(sys.argv[1],"rb"))["ProgramArguments"]))' "$LA/$1.plist"; }
check "$(pargs org.example.claude.dispatch.x.y.202611010900)" "$H $P/dispatch claude/x --repo r" "…claude-host first, the rest as it was"
check "$(pargs org.example.claude.autofinish)" "$H /usr/bin/python3 $P/autofinish --sweep" "…the python form keeps its interpreter"
check "$(plutil -extract ProgramArguments.2 raw -o - "$LA/org.example.claude.dispatch-tidy-soon.plist")" "sleep 60; '$H' '$P/dispatch-rc' tidy; sleep 120; '$H' '$P/dispatch-rc' tidy" "…a /bin/sh -c line, each script prefixed"
has "$T/out" "--       org.example.claude.aurora: runs weekly-run, which starts claude, without claude-host (running now" "…a running job is pending: left to finish, not counted"
has "$T/out" "BARE     org.example.claude.host.bare: starts claude itself, whose path every update replaces (an empty host" "…an empty bare host counts"
echo 950 > "$T/pids/org.example.claude.host.bare"; echo 951 > "$T/kids/950"
check "$(RC --agents)" "0" "a bare host holding a session and a running job: pending, the check stays green"
has "$T/out" "--       org.example.claude.host.bare: starts claude itself, whose path every update replaces (a host holding a session" "…the host named as pending"
rm -f "$T/kids/950" "$T/pids/org.example.claude.host.bare"
rm -f "$T/pids/org.example.claude.aurora" "${LA:?}/org.example.claude.host.bare.plist"
check "$(RC --agents --fix)" "0" "once those are through it too"
has "$T/out" "fixed    org.example.claude.aurora" "…the idle job is fixed"
check "$(RC --agents)" "0" "and the check passes"
has "$T/out" "ok       LaunchAgents: every job that starts claude starts through claude-host" "…saying so"
# launchd takes a plist Python's XML parser refuses (a `--` inside a comment: a project's runner on
# the build Mac, 2026-10-19); one such file must be skipped, never crash the check for every job
printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0">\n<dict>\n<!-- run: runner.py install --host <name> -->\n<key>Label</key><string>org.example.shop.odd</string>\n</dict>\n</plist>\n' > "$LA/org.example.shop.odd.plist"
check "$(RC --agents)" "0" "a plist Python cannot parse is no crash"
printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0">\n<dict>\n<!-- run: claude --name x -->\n<key>Label</key><string>org.example.shop.odd</string>\n<key>ProgramArguments</key><array><string>%s/.local/bin/claude</string><string>remote-control</string></array>\n</dict>\n</plist>\n' "$HOME" > "$LA/org.example.shop.odd.plist"
check "$(RC --agents)" "1" "…and is still checked, read through plutil: one starting claude bare counts"
printf 'not a plist at all' > "$LA/org.example.shop.odd.plist"
check "$(RC --agents)" "0" "a file neither Python nor plutil reads is skipped"
has "$T/out" "org.example.shop.odd: not a plist dict Python or plutil can read — not checked" "…and named as not checked"
has "$T/out" "every job it could read that starts claude" "…and the ok line says some were not read"
rm -f "$LA/org.example.shop.odd.plist"
# the parse errors beyond ExpatError (review, 2026-10-19), a root that is no dict, and the
# reaper's quiet run, which names nothing it skips
check "$(python3 - "$T/coding/bin/rc-hosts" "$T" <<'PY'
import contextlib, importlib.machinery as m, importlib.util as u, io, sys
from pathlib import Path
l = m.SourceFileLoader("r", sys.argv[1]); s = u.spec_from_loader("r", l); r = u.module_from_spec(s); l.exec_module(r)
d = Path(sys.argv[2]) / "odd-plists"; d.mkdir(exist_ok=True)
shapes = ['<plist><key>a</key></plist>', '<plist><date>garbage</date></plist>',
          '<?xml version="1.0" encoding="x-bogus-enc"?><plist><dict/></plist>',
          '<plist><array></array><key>x</key></plist>', '<plist><array/></plist>']
out = []
for i, text in enumerate(shapes):
    f = d / f"s{i}.plist"; f.write_text(text)
    out.append(str(r.read_plist(f)))
out.append(str(r.read_plist(d / "missing.plist")))
r.AGENTS = d
buf = io.StringIO()
with contextlib.redirect_stdout(buf):
    r.agents(quiet=True)
out.append(repr(buf.getvalue()))
print(" ".join(out))
PY
)" "None None None None None None ''" "every malformed shape and a missing file read as None, never a crash; the quiet run prints nothing"
mkplist org.example.claude.wt "$HOME/projects/overlay/.claude/worktrees/x/bin/dispatch" claude/x
check "$(RC --agents)" "1" "a claimer from another checkout (a worktree's) counts: claude-host won't start it"
has "$T/out" "OUTSIDE  org.example.claude.wt: runs dispatch from outside $P, which claude-host's allowlist names" "…said to be outside the allowlist"
has "$T/out" "1 job(s) run a script outside $P: claude-host won't start them" "…with its own line"
rm -f "${LA:?}/org.example.claude.wt.plist"
check "$(python3 - "$T/coding/bin/rc-hosts" <<'PY'
import importlib.machinery as m, importlib.util as u, sys
l = m.SourceFileLoader("r", sys.argv[1]); s = u.spec_from_loader("r", l); r = u.module_from_spec(s); l.exec_module(r)
for line in ("sleep 5; ~/projects/overlay/bin/dispatch-rc tidy", "$HOME/projects/overlay/bin/weekly-run aurora",
             "${HOME}/projects/overlay/bin/autofinish --sweep", "cd ~/projects/overlay && bin/dispatch x",
             "cd /elsewhere; ./bin/usage-report tick", "bin/dispatch x", "/usr/bin/true"):
    print(r.claimer(line))
PY
)" "('dispatch-rc', True)
('weekly-run', True)
('autofinish', True)
('dispatch', True)
('usage-report', False)
('dispatch', False)
None" "a claimer spelt with ~, \$HOME, \${HOME} or relative after a cd resolves to the primary's bin/; elsewhere or with no cd is outside"
mkplist org.example.claude.tilde /bin/sh -c "cd ~/projects/overlay && bin/dispatch claude/x"
check "$(RC --agents)" "1" "a /bin/sh -c job that cd's into the primary and runs bin/dispatch bare counts"
has "$T/out" "BARE     org.example.claude.tilde: runs dispatch, which starts claude, without claude-host" "…named"
rm -f "${LA:?}/org.example.claude.tilde.plist"
mkplist org.example.claude.fails "$P/dispatch" claude/f
touch "$T/bootstrap-fails"
check "$(RC --agents --fix)" "1" "--fix whose reload launchd refuses"
has "$T/out" "FAILED   org.example.claude.fails: runs dispatch, which starts claude, without claude-host (rewritten, but launchd did not load it" "…says so and counts it, never \"fixed\""
check "$(RC --agents)" "1" "the run after: the rewritten plist names claude-host, unloaded — never ok"
has "$T/out" "UNLOADED org.example.claude.fails: names claude-host, but launchd has not loaded it" "…said so"
rm -f "$T/bootstrap-fails"
check "$(RC --agents --fix)" "0" "--fix loads it once launchd takes it"
has "$T/out" "loaded   org.example.claude.fails" "…and says so"
rm -f "${LA:?}/org.example.claude.fails.plist" "$T/pids/org.example.claude.fails"
mkplist com.example.bare "$HOME/.local/bin/claude" -p hi
check "$(RC --agents --fix)" "1" "someone else's job starting claude bare counts"
has "$T/out" "BARE     com.example.bare: starts claude itself, whose path every update replaces (not a job under org.example.claude" "…and is left to a hand"
check "$(pargs com.example.bare)" "$HOME/.local/bin/claude -p hi" "…never rewritten"
rm -f "${LA:?}/com.example.bare.plist"
# the clock's Orca automations (knowledge-layers S7): Orca launches the run, never bare; what its one
# launcher line starts must be the primary checkout's script. clock is not yet public: the twin has
# none, so the block runs only beside it, and says so when it skips
if [ -f "$B/clock" ]; then
HEAD=$(python3 -c 'import importlib.machinery as m, importlib.util as u, sys; l=m.SourceFileLoader("c", sys.argv[1]); s=u.spec_from_loader("c", l); c=u.module_from_spec(s); l.exec_module(c); print(c.PROMPT_HEAD)' "$B/clock")
python3 - "$T/autos.json" "$HEAD" "$P" "$HOME" <<'PY'
import json, sys
out, head, p, home = sys.argv[1:]
mk = lambda n, line, pc=None: {"id": n, "name": n, "prompt": head + "\n\n" + line, "precheck": {"command": pc} if pc else None}
json.dump([mk("night", p + "/clock fire aurora -- " + p + "/weekly-run aurora " + home,
              p + "/clock fire aurora --precheck --due -- " + p + "/weekly-run aurora " + home),
           mk("pass", p + "/dispatch claude/x --repo r --account a"),
           mk("canary", p + "/clock canary beat orca", p + "/clock fire canary --precheck -- " + p + "/clock canary beat orca"),
           mk("free", "Tidy the docs")], open(out, "w"))
PY
check "$(RC --agents)" "0" "automations whose lines name the primary's scripts: green"
has "$T/out" "ok       automation night: Orca starts its run; weekly-run is the primary checkout's" "…a fired job named"
has "$T/out" "ok       automation pass: Orca starts its run; dispatch is the primary checkout's" "…a dispatch line named"
hasnt "$T/out" "automation free" "…a prompt not in the clock's shape is clock check's, not this check's"
has "$T/out" "ok       automation canary: a canary beat; its launcher line starts no claude of its own" "…a canary beat starts no claude (clock canary, orca-launcher S5)"
has "$T/out" "note     automation canary: its precheck fires the job through launchd (seam P); only a manual run starts a claude in Orca" "…its precheck fires the beat through launchd, as the note says"
# seam P (orca-launcher S3): which automations start a claude in Orca is a note, never a count
has "$T/out" "note     automation night: its precheck fires the job through launchd (seam P); only a manual run starts a claude in Orca" "…a precheck that fires the job: a note saying so"
has "$T/out" "note     automation pass: Orca starts a claude for each run — no precheck fires its job" "…one without: a note naming the precheck to give it"
hasnt "$T/out" "--       automation" "…both in no line bootstrap.sh --check counts"
python3 - "$T/autos.json" "$HEAD" "$HOME" "$P" <<'PY'
import json, sys
out, head, home, p = sys.argv[1:]
json.dump([{"id": "wt", "name": "wt", "prompt": head + "\n\n" + home + "/projects/overlay-copy/bin/dispatch claude/x"},
           {"id": "bare", "name": "bare", "prompt": head + "\n\ndispatch claude/x"},
           {"id": "fc", "name": "fc", "prompt": head + "\n\n" + home + "/projects/overlay-copy/bin/clock fire aurora -- " + home + "/projects/overlay/bin/weekly-run aurora " + home},
           {"id": "cc", "name": "cc", "prompt": head + "\n\n" + home + "/projects/overlay-copy/bin/clock canary beat orca"},
           {"id": "pc", "name": "pc", "prompt": head + "\n\n" + p + "/dispatch claude/x --repo r --account a",
            "precheck": {"command": home + "/projects/overlay-copy/bin/clock fire pc --precheck -- " + p + "/dispatch claude/x --repo r --account a"}}], open(out, "w"))
PY
check "$(RC --agents)" "1" "an automation launching another copy's dispatch, or firing through another clock, counts, once ready"
has "$T/out" "OUTSIDE  automation wt: launches dispatch from outside $P" "…named OUTSIDE"
has "$T/out" "note     automation bare: dispatch named without a path" "…a pathless line is a note"
has "$T/out" "OUTSIDE  automation fc: fires through" "…a fire through another checkout's clock named OUTSIDE"
has "$T/out" "OUTSIDE  automation pc: its precheck fires through" "…a precheck firing through another checkout's clock named OUTSIDE too"
has "$T/out" "OUTSIDE  automation cc: beats through" "…a canary beating through another checkout's clock named OUTSIDE (orca-launcher S5)"
has "$T/out" "overlay-copy/bin/clock, not the primary checkout's clock" "…naming that clock"
echo '[]' > "$T/autos.json"
printf '#!/bin/sh\nexit 1\n' > "$T/stub/orca.down"; chmod +x "$T/stub/orca.down"
check "$(ORCA_HOST_CLI="$T/stub/orca.down" RC --agents)" "0" "Orca unread: a note, never a failure"
has "$T/out" "note     Orca automations: not read" "…said"
hasnt "$T/out" "--       Orca automations" "…in no line the overlay's bootstrap.sh --check counts as a pending LaunchAgent"
else echo "  --   the clock's Orca automations skipped: no bin/clock beside rc-hosts"
fi
mkplist org.example.claude.dispatch.x.z.202611010900 "$P/dispatch" claude/z
rm -f "${G:?}"
check "$(RC --agents)" "0" "before this Mac's sitting, a bare job is a note, never a failure (the laptop's check must not stop on it)"
has "$T/out" "--       org.example.claude.dispatch.x.z.202611010900" "…named"
has "$T/out" "the sitting is rc-hosts --grant" "…with the sitting"
cp "$T/granted.keep" "$G"
rm_own "${LA:?}"/*.plist "$T/pids/org.example.claude.ok"; mv "$T/la.keep/"*.plist "$LA/" 2>/dev/null

echo "--probe-all: per service, from claude-host's child as launchd starts it"
printf '{"results": {"fda": {"what": "Full Disk Access", "result": "ok"}, "cloud:GoogleDrive-a": {"what": "GoogleDrive-a (File Provider)", "result": "no answer"}, "automation:com.apple.Notes": {"what": "Automation of Notes", "result": "denied (execution error: Not authorized to send Apple events to Notes. (-1743))"}, "photos": {"what": "Photos", "result": "n/a"}}}\n' > "$T/tcc.json"
: > "$T/tcc-jobs"
check "$(RC --probe-all)" "1" "a service unanswered or denied fails it"
has "$T/out" "ok       Full Disk Access: ok" "…lists the ok ones"
has "$T/out" "DENIED   GoogleDrive-a (File Provider): no answer" "…an unanswered prompt reads denied, never ok"
has "$T/out" "DENIED   Automation of Notes: denied" "…a refused one"
has "$T/out" "ok       Photos: n/a" "…n/a where there is nothing to ask"
check "$(python3 -c 'import json,sys; print(json.loads(sys.stdin.readline()))' < "$T/tcc-jobs")" "['$H', '/usr/bin/python3', '$HOME/projects/overlay/bin/rc-hosts', '--tcc-run', 'probe']" "…run as claude-host → the primary's rc-hosts --tcc-run, as a launchd job"
test -f "$HOME/Library/LaunchAgents/org.example.claude.tcc-probe.plist"; check $? 1 "…leaving no job behind"
has "$T/calls" "kill SIGTERM gui/$(id -u)/org.example.claude.tcc-probe" "…ended by stop(): SIGTERM, then bootout"
check "$(RC --check)" "0" "--check"
has "$T/out" "--probe-all " "…reports the last probe-all"
has "$T/out" "denied GoogleDrive-a (File Provider), Automation of Notes" "…and what it found denied"
printf '{"results": {"fda": {"what": "Full Disk Access", "result": "ok"}, "contacts": {"what": "Contacts", "result": "unproven (its folder opens by Full Disk Access; no grant of its own)"}}}\n' > "$T/tcc.json"
check "$(RC --probe-all)" "0" "a library opened only by Full Disk Access is no failure"
has "$T/out" "--       Contacts: unproven" "…but is not called ok"
has "$T/out" "unproven, not denied: Contacts" "…and is named"
check "$(RC --check)" "0" "--check"
has "$T/out" "unproven Contacts" "…says it is unproven"
hasnt "$T/out" "every service ok" "…and never \"every service ok\""
rm -f "$T/tcc.json"
check "$(RC --probe-all)" "0" "every service ok"
RC --check > /dev/null; has "$T/out" "every service ok" "…says so only then"
mv "$H" "$H.v2"; printf '#!/bin/sh\necho "usage: claude-host remote-control <args...> | claude-host --probe" >&2; exit 2\n' > "$H"; chmod +x "$H"
: > "$T/tcc-jobs"
check "$(RC --probe-all)" "1" "--probe-all on a granted build that predates the walk"
has "$T/out" "this build predates the walk" "…says so"
check "$(grep -c . "$T/tcc-jobs")" "0" "…and loads no job it would refuse (no 300 s wait)"
mv "$H.v2" "$H"
mv "$HOME/projects/overlay/bin/rc-hosts" "$T/primary.keep"; printf '#!/usr/bin/env python3\nprint("an rc-hosts from before the walk")\n' > "$HOME/projects/overlay/bin/rc-hosts"
: > "$T/tcc-jobs"
check "$(RC --probe-all)" "2" "--probe-all refuses while the primary's rc-hosts does not know --tcc-run"
has "$T/out" "does not know --tcc-run yet: land this first" "…saying why"
check "$(grep -c . "$T/tcc-jobs")" "0" "…and loads no job that would run it"
check "$(RC --grant)" "2" "--grant too"
mv "$T/primary.keep" "$HOME/projects/overlay/bin/rc-hosts"
check "$(RC --bogus)" "2" "an unknown flag is an error, never a plain run"
has "$T/out" "rc-hosts: unknown --bogus" "…named"

echo "--tcc-run: the job's own half, on this suite's scratch home (no Apple event is ever sent here)"
mkdir -p "$HOME/Desktop"
check "$(python3 - "$T/coding/bin/rc-hosts" "$HOME" <<'PY'
import importlib.machinery as m, importlib.util as u, sys
l = m.SourceFileLoader("r", sys.argv[1]); s = u.spec_from_loader("r", l); r = u.module_from_spec(s); l.exec_module(r)
print(r.tcc_one("dir", sys.argv[2] + "/Desktop", 2), r.tcc_one("dir", sys.argv[2] + "/nope", 2),
      r.tcc_one("file", sys.argv[2] + "/nope", 2).split(" ")[0])
print(r.tcc_one("dir+row", (sys.argv[2] + "/Desktop", "kTCCServiceAddressBook"), 2))
PY
)" "ok n/a denied
unproven (its folder opens by Full Disk Access; no grant of its own)" "a readable folder is ok, a missing one n/a, an unreadable file denied; a library's folder without its own row is unproven"
check "$(python3 - "$T/coding/bin/rc-hosts" <<'PY'
import importlib.machinery as m, importlib.util as u, sys
l = m.SourceFileLoader("r", sys.argv[1]); s = u.spec_from_loader("r", l); r = u.module_from_spec(s); l.exec_module(r)
r.APPS["com.apple.MobileSMS"] = "/nonexistent/Messages.app"
print(r.tcc_one("event", ("com.apple.MobileSMS", "count windows"), 2))
print(sorted(set(r.APPS) - {"com.apple.MobileSMS"}) == sorted(b for b, _, _ in r.AUTOMATION), r.MESSAGES[0] in r.APPS)
PY
)" "denied (/nonexistent/Messages.app not found)
True True" "a missing Automation target reads denied, never n/a (no Spotlight); every target has its path"
check "$(cd "$T" && python3 - "$T/coding/bin/rc-hosts" <<'PY'
import importlib.machinery as m, importlib.util as u, sys
l = m.SourceFileLoader("r", sys.argv[1]); s = u.spec_from_loader("r", l); r = u.module_from_spec(s); l.exec_module(r)
r.tcc_services = lambda: [("desktop", "Desktop folder", "dir", r.HOME / "Desktop")]
r.LOGS.mkdir(parents=True, exist_ok=True); r.tcc_run("probe")
import json; print(json.loads((r.LOGS / "tcc-probe.json").read_text())["results"]["desktop"]["result"],
                   (r.LOGS / "tcc-probe.json.tmp").exists())
PY
)" "ok False" "--tcc-run writes its answer whole: a temp file renamed, none left"

# Messages is required on the owner's two Macs only; any other machine relays its texts to the build Mac
check "$(python3 - "$T/coding/bin/rc-hosts" <<'PY'
import importlib.machinery as m, importlib.util as u, sys
l = m.SourceFileLoader("r", sys.argv[1]); s = u.spec_from_loader("r", l); r = u.module_from_spec(s); l.exec_module(r)
out = []
for name in ("buildbox", "laptop", "thirdmac"):
    r.machine = lambda name=name: name
    out.append(str(any(k == "automation:com.apple.MobileSMS" for k, *_ in r.tcc_services())))
print(" ".join(out))
PY
)" "True True False" "Messages is walked and required on buildbox and laptop, never on another Mac"

# A TCC row counts only for the build it was made for: the build in place must satisfy the row's
# stored requirement, so a row from an older build counts for nothing
dr=$(codesign -d -r- "$H" 2>&1 | sed -n 's/.*designated => //p'); csreq -r="$dr" -b "$T/row.csreq"
check "$(python3 - "$T/coding/bin/rc-hosts" "$T/row.csreq" "$H" "$TB" <<'PY'
import importlib.machinery as m, importlib.util as u, sys
l = m.SourceFileLoader("r", sys.argv[1]); s = u.spec_from_loader("r", l); r = u.module_from_spec(s); l.exec_module(r)
blob = open(sys.argv[2], "rb").read()
print(r.satisfies(blob, sys.argv[3]), r.satisfies(blob, sys.argv[4]), r.satisfies(b"", sys.argv[3]))
PY
)" "True False False" "a TCC row counts for the build it was made for, not another, not an empty one"

# App Management's row lives in the user's TCC.db on both Macs (2026-10-19), and the user's tccd
# decides it: a row there is the answer, a switched-off one is named and never hidden by an allowing
# system row; the system's database counts only when the user's has no row
check "$(python3 - "$T/coding/bin/rc-hosts" "$T/row.csreq" "$H" "$T" <<'PY'
import importlib.machinery as m, importlib.util as u, sqlite3, sys
from pathlib import Path
l = m.SourceFileLoader("r", sys.argv[1]); s = u.spec_from_loader("r", l); r = u.module_from_spec(s); l.exec_module(r)
blob, H, T = open(sys.argv[2], "rb").read(), sys.argv[3], Path(sys.argv[4])
def db(name, value):
    p = T / name
    if p.exists(): p.unlink()
    c = sqlite3.connect(p); c.execute("CREATE TABLE access (service, client, auth_value, csreq)")
    if value is not None:
        c.execute("INSERT INTO access VALUES (?, ?, ?, ?)", ("kTCCServiceSystemPolicyAppBundles", H, value, blob))
    c.commit(); c.close(); return p
r.LAUNCHER = H
out = []
for user, system in ((2, None), (None, 2), (0, None), (None, None), (0, 2)):
    r.USER_TCC, r.SYSTEM_TCC = db("user.db", user), db("system.db", system)
    out.append(r.tcc_one("row", "kTCCServiceSystemPolicyAppBundles", 1))
print("|".join(out))
PY
)" "ok|ok|denied (switched off, or granted to an older build)|denied (not in the list)|denied (switched off, or granted to an older build)" "App Management: the user's row decides, the system's only when the user has none; a refusal is never hidden"

echo "--tcc-survey: refusals charged to a versioned claude, from the unified log"
cat > "$T/tcc.log" <<'LOG'
2026-10-18 13:09:09.600 Df tccd[408:1] [com.apple.TCC:access] AUTHREQ_CTX: msgID=401.1, function=TCCAccessRequest, service=kTCCServiceSystemPolicyAllFiles, preflight=no, query=1
2026-10-18 13:09:09.601 Df tccd[408:1] [com.apple.TCC:access] AUTHREQ_ATTRIBUTION: msgID=401.1, attribution={responsible={TCCDProcess: identifier=com.anthropic.claude-code, pid=28566, auid=502, euid=502, responsible_path=/Users/u/.local/share/claude/versions/2.1.302, binary_path=/Users/u/.local/share/claude/versions/2.1.302}, accessing={TCCDProcess: identifier=bun, pid=28631, auid=502, euid=502, binary_path=/Users/u/.bun/bin/bun}, },
2026-10-18 13:09:09.700 Df tccd[408:1] [com.apple.TCC:access] AUTHREQ_RESULT: msgID=401.1, authValue=0, authReason=5, authVersion=1, desired_auth=0,
2026-10-18 13:09:35.500 Df tccd[408:1] [com.apple.TCC:access] AUTHREQ_CTX: msgID=401.2, function=TCCAccessRequest, service=kTCCServiceFileProviderDomain, preflight=yes, query=1
2026-10-18 13:09:35.549 Df tccd[408:1] [com.apple.TCC:access] AUTHREQ_ATTRIBUTION: msgID=401.2, attribution={accessing={TCCDProcess: identifier=com.anthropic.claude-code, pid=28566, auid=502, euid=502, binary_path=/Users/u/.local/share/claude/versions/2.1.301}, requesting={TCCDProcess: identifier=com.apple.sandboxd, pid=401, auid=0, euid=0, binary_path=/usr/libexec/sandboxd}, },
2026-10-18 13:09:35.600 Df tccd[408:1] [com.apple.TCC:access] AUTHREQ_RESULT: msgID=401.2, authValue=0, authReason=2, authVersion=1,
2026-10-18 13:10:00.000 Df tccd[408:1] [com.apple.TCC:access] AUTHREQ_CTX: msgID=401.3, function=TCCAccessRequest, service=kTCCServiceSystemPolicyAllFiles, preflight=no, query=1
2026-10-18 13:10:00.001 Df tccd[408:1] [com.apple.TCC:access] AUTHREQ_ATTRIBUTION: msgID=401.3, attribution={responsible={TCCDProcess: identifier=org.example.claude-host, pid=1, auid=502, euid=502, binary_path=/Users/u/.local/bin/claude-host}, accessing={TCCDProcess: identifier=bun, pid=2, auid=502, euid=502, binary_path=/Users/u/.bun/bin/bun}, },
2026-10-18 13:10:00.002 Df tccd[408:1] [com.apple.TCC:access] AUTHREQ_RESULT: msgID=401.3, authValue=0, authReason=5, authVersion=1,
2026-10-18 13:11:00.000 Df tccd[408:1] [com.apple.TCC:access] AUTHREQ_CTX: msgID=401.4, function=TCCAccessRequest, service=kTCCServiceSystemPolicyAllFiles, preflight=yes, query=1
2026-10-18 13:11:00.001 Df tccd[408:1] [com.apple.TCC:access] AUTHREQ_ATTRIBUTION: msgID=401.4, attribution={responsible={TCCDProcess: identifier=com.anthropic.claude-code, pid=9, auid=502, euid=502, binary_path=/Users/u/.local/share/claude/versions/2.1.302}, accessing={TCCDProcess: identifier=head, pid=10, auid=502, euid=502, binary_path=/usr/bin/head}, },
2026-10-18 13:11:00.002 Df tccd[408:1] [com.apple.TCC:access] AUTHREQ_RESULT: msgID=401.4, authValue=2, authReason=4, authVersion=1,
2026-10-18 13:12:00.000 Df tccd[408:1] [com.apple.TCC:access] AUTHREQ_CTX: msgID=401.5, function=TCCAccessRequest, service=kTCCServiceMicrophone, preflight=yes, query=1
2026-10-18 13:12:00.001 Df tccd[408:1] [com.apple.TCC:access] AUTHREQ_ATTRIBUTION: msgID=401.5, attribution={responsible={TCCDProcess: identifier=com.anthropic.claude-code, pid=9, auid=502, euid=502, binary_path=/Users/u/.local/share/claude/versions/2.1.302}, accessing={TCCDProcess: identifier=say, pid=11, auid=502, euid=502, binary_path=/usr/bin/say}, },
2026-10-18 13:12:00.002 Df tccd[408:1] [com.apple.TCC:access] AUTHREQ_RESULT: msgID=401.5, authValue=1, authReason=0, authVersion=1,
LOG
check "$(python3 - "$T/coding/bin/rc-hosts" "$T/tcc.log" <<'PY'
import importlib.machinery as m, importlib.util as u, sys
l = m.SourceFileLoader("r", sys.argv[1]); s = u.spec_from_loader("r", l); r = u.module_from_spec(s); l.exec_module(r)
for (svc, res, acc), (n, last, vs) in sorted(r.survey(open(sys.argv[2]).read().splitlines()).items()):
    print(svc, res, acc, n, ",".join(sorted(vs)))
PY
)" "FileProviderDomain denied/user-consent ~/.local/share/claude/versions/<v> 1 2.1.301
SystemPolicyAllFiles denied/no-record REAL ~/.bun/bin/bun 1 2.1.302" "a refusal charged to claude's versioned path is listed, one with no responsible too; claude-host's, an allowed one and a quiet preflight are not"
check "$(python3 - "$T/coding/bin/rc-hosts" "$T/tcc.log" <<'PY'
import importlib.machinery as m, importlib.util as u, sys
l = m.SourceFileLoader("r", sys.argv[1]); s = u.spec_from_loader("r", l); r = u.module_from_spec(s); l.exec_module(r)
lines = open(sys.argv[2]).read().splitlines()
print(len(r.survey(lines, since="2026-10-18 13:09")), len(r.survey(lines, since="2026-10-18 13:10")),
      len(r.survey(lines, skip={28566})))
PY
)" "2 0 0" "--health's rule: only refusals since the sitting, none from a pid --agents calls pending"

echo "--tcc-survey: a job Orca started is counted too (orca-launcher S7)"
# the ATTRIBUTION lines of tonight's evidence, shaped as the log prints them: Orca responsible, a child accessing
orca_req() {   # ID SERVICE PREFLIGHT RESPONSIBLE ACCESSING AUTHVALUE
  printf '%s\n' "2026-10-26 02:10:0${1#*.} Df tccd[408:1] [com.apple.TCC:access] AUTHREQ_CTX: msgID=$1, function=TCCAccessRequest, service=kTCCService$2, preflight=$3, query=1" \
    "2026-10-26 02:10:0${1#*.} Df tccd[408:1] [com.apple.TCC:access] AUTHREQ_ATTRIBUTION: msgID=$1, attribution={$4$5 }," \
    "2026-10-26 02:10:0${1#*.} Df tccd[408:1] [com.apple.TCC:access] AUTHREQ_RESULT: msgID=$1, authValue=$6, authReason=5, authVersion=1,"
}
ORCA_R='responsible={TCCDProcess: identifier=com.stablyai.orca, pid=777, auid=502, euid=502, binary_path=/Applications/Orca.app/Contents/MacOS/Orca}, '
{ orca_req 501.1 FileProviderDomain no "$ORCA_R" 'accessing={TCCDProcess: identifier=com.anthropic.claude-code, pid=778, auid=502, euid=502, binary_path=/Users/u/.local/share/claude/versions/2.1.302}, ' 0
  orca_req 501.2 FileProviderDomain no "$ORCA_R" 'accessing={TCCDProcess: identifier=com.anthropic.claude-code, pid=779, auid=502, euid=502, binary_path=/Users/u/.local/share/claude/versions/2.1.302}, ' 0
  orca_req 501.3 SystemPolicyAllFiles no "$ORCA_R" 'accessing={TCCDProcess: identifier=python3, pid=780, auid=502, euid=502, binary_path=/usr/bin/python3}, ' 0
  orca_req 501.4 DeveloperTool no "$ORCA_R" 'accessing={TCCDProcess: identifier=sh, pid=781, auid=502, euid=502, binary_path=/bin/sh}, ' 0
  orca_req 501.5 SystemPolicyAllFiles no '' 'accessing={TCCDProcess: identifier=com.stablyai.orca, pid=777, auid=502, euid=502, binary_path=/Applications/Orca.app/Contents/MacOS/Orca}, ' 0
  orca_req 501.6 SystemPolicyAllFiles no "$ORCA_R" 'accessing={TCCDProcess: identifier=bun, pid=782, auid=502, euid=502, binary_path=/Users/u/.bun/bin/bun}, ' 2
  orca_req 501.7 SystemPolicyAllFiles no 'responsible={TCCDProcess: identifier=org.example.app, pid=900, auid=502, euid=502, binary_path=/Applications/Example.app/Contents/MacOS/Example}, ' 'accessing={TCCDProcess: identifier=bun, pid=901, auid=502, euid=502, binary_path=/Users/u/.bun/bin/bun}, ' 0
  orca_req 501.8 SystemPolicyAllFiles no 'responsible={TCCDProcess: identifier=org.example.claude-host, pid=1, auid=502, euid=502, binary_path=/Users/u/.local/bin/claude-host}, ' 'accessing={TCCDProcess: identifier=bun, pid=2, auid=502, euid=502, binary_path=/Users/u/.bun/bin/bun}, ' 0
  # no accessing block: the asker is `requesting` (the review's live shape); with neither, no job is named and none is counted
  orca_req 501.9 SystemPolicyAllFiles no "$ORCA_R" 'requesting={TCCDProcess: identifier=bun, pid=783, auid=502, euid=502, binary_path=/Users/u/.bun/bin/bun}, ' 0
  orca_req 502.1 SystemPolicyAllFiles no "$ORCA_R" '' 0
} > "$T/tcc-orca.log"
check "$(python3 - "$T/coding/bin/rc-hosts" "$T/tcc-orca.log" <<'PY'
import importlib.machinery as m, importlib.util as u, sys
l = m.SourceFileLoader("r", sys.argv[1]); s = u.spec_from_loader("r", l); r = u.module_from_spec(s); l.exec_module(r)
for (svc, res, acc), (n, last, vs) in sorted(r.survey(open(sys.argv[2]).read().splitlines()).items()):
    print(svc, res, acc, n, ",".join(sorted(vs)))
PY
)" "FileProviderDomain denied/no-record REAL via Orca: ~/.local/share/claude/versions/<v> 2 Orca
SystemPolicyAllFiles denied/no-record REAL via Orca: /usr/bin/python3 1 Orca
SystemPolicyAllFiles denied/no-record REAL via Orca: ~/.bun/bin/bun 1 Orca" "a refusal charged to Orca while a child of it asks (accessing, else requesting) is listed, one row per accessor; Orca's own requests, one naming no asker, a quiet service, an allowed one, another app's and claude-host's are not"
check "$(python3 - "$T/coding/bin/rc-hosts" "$T/tcc-orca.log" <<'PY'
import importlib.machinery as m, importlib.util as u, sys
l = m.SourceFileLoader("r", sys.argv[1]); s = u.spec_from_loader("r", l); r = u.module_from_spec(s); l.exec_module(r)
lines = open(sys.argv[2]).read().splitlines()
print(len(r.survey(lines, since="2026-10-26 02:11")), len(r.survey(lines, skip={777})), len(r.survey(lines, skip={999})))
PY
)" "0 0 3" "  --health's since and skip rules reach it too (the responsible pid is Orca's)"

echo "--tcc-survey --host: a peer is a line of wharf-runs/ssh, never a name in code"
check "$(RC --tcc-survey --host nosuch)" "1" "--host of a Mac the key does not name"
has "$T/out" "only buildbox (ssh buildbox-ssh)" "…is refused, naming the peers the key holds"

echo "--orphans: a host's claude that no launchd job holds"
printf '%s\n' "  610     1 $HOME/.local/bin/claude-host remote-control --name fresh" "  611   610 $HOME/.local/bin/claude remote-control --name fresh" "999999     1 $HOME/.local/bin/claude remote-control --name fresh" "  913     1 /usr/bin/other" > "$T/ps-ax"
echo 610 > "$T/pids/org.example.claude.host.fresh"
check "$(RC --orphans)" "0" "--orphans"
has "$T/out" "orphan   999999:" "…names the ppid-1 claude remote-control that is no job's"
hasnt "$T/out" "611" "…not the host's own claude under claude-host"
# a pid above xnu's PID_MAX (99999): never a real process, whatever runs on this Mac
check "$(RC --orphans --end)" "0" "--orphans --end on a pid that is gone"
has "$T/out" "999999: gone already" "…says so and goes on"
rm -f "$T/ps-ax"
echo 640 > "$T/pids/org.example.claude.host.fresh"; : > "$T/calls"
python3 - "$T/coding/bin/rc-hosts" <<'PY'
import importlib.machinery as m, importlib.util as u, plistlib, sys
l = m.SourceFileLoader("r", sys.argv[1]); s = u.spec_from_loader("r", l); r = u.module_from_spec(s); l.exec_module(r)
r.load("org.example.claude.host.fresh", plistlib.loads((r.AGENTS / "org.example.claude.host.fresh.plist").read_bytes()))
PY
check "$(grep -n 'kill SIGTERM\|bootout' "$T/calls" | head -2 | cut -d: -f2 | cut -d' ' -f1-2 | tr '\n' ' ')" "kill SIGTERM bootout gui/$(id -u)/org.example.claude.host.fresh " "load() ends a running job by SIGTERM before bootout, which would SIGKILL claude-host"

echo "a confidential scope's host: only on its own login, only with \"rc\": {…} (confidential-reach S10)"
NL=org.example.claude.host.node; NP="$HOME/Library/LaunchAgents/$NL.plist"
# the fixture logins' dirs: acct-own's here, acct-gone's never made, acct-orca's Orca's, acct-main the default
OWN="$HOME/.cfg-own"; ORC="$HOME/.orca-profile"; DEF="$HOME/.claude"; REAL="$(cd "$HOME" && pwd -P)"
repo "$HOME/projects/node"; mkdir -p "$OWN/sessions" "$ORC"
export ACCOUNTS_FILE="$T/accounts.json" ACCOUNT_ORCA_FILE="$T/orca.json"
cat > "$ACCOUNTS_FILE" <<JSON
{"accounts": [{"label": "acct-own", "home": "$OWN"}, {"label": "acct-orca", "via": "orca"},
              {"label": "acct-gone", "home": "$OWN-gone"}, {"label": "acct-main", "home": "$DEF", "primary": true}]}
JSON
echo "{\"acct-orca\": {\"home\": \"$ORC\"}}" > "$ACCOUNT_ORCA_FILE"
reg() {  # reg <the node entry's rc, as JSON, or "" for none> <the scope's login>
  echo "{\"repos\": {\"node\": {\"hosts\": [\"laptop\"]${1:+, \"rc\": $1}}}, \"scopes\": {\"sec\": {\"repos\": [\"node\"], \"confidential\": true, \"login\": \"$2\"}}}" > "$T/coding/repos.json"
}
reg "" acct-own
check "$(RC --check)" "0" "--check: a confidential repo with no rc key"
has "$T/out" "held     node · laptop: confidential scope sec: its entry says no \"rc\": {…}" "…holds its host and says why"
hasnt "$T/out" "missing  node" "…and wants none"
RC >/dev/null; test -f "$NP"; check $? 1 "…a plain run writes no plist"
reg true acct-own
check "$(RC --check)" "0" "\"rc\": true"
has "$T/out" "held     node · laptop: confidential scope sec: its entry says no \"rc\": {…}" "…is no rc object: held"
reg '{}' acct-orca
check "$(RC --check)" "0" "\"rc\": {} on an Orca-held login, its dir read back"
has "$T/out" "held     node · laptop: confidential scope sec: login acct-orca is Orca's" "…held: no home of its own"
reg '{}' acct-gone
check "$(RC --check)" "0" "a login whose home is not on this Mac"
has "$T/out" "login acct-gone has no home on this Mac ($OWN-gone)" "…held, naming the home"
reg '{}' acct-nope
check "$(RC --check)" "0" "a login the account registry lacks"
has "$T/out" "login acct-nope is no Claude row of the account registry" "…held"
reg '{}' acct-own
check "$(RC --check)" "0" "\"rc\": {} and a login with a home here"
has "$T/out" "missing  node · laptop" "…wants the host"
echo '{"projects": {}}' > "$OWN/.claude.json"   # the login's own trust: the node not accepted
check "$(RC --check)" "0" "--check with the repo untrusted in the login's own .claude.json"
has "$T/out" "node · laptop: waits for workspace trust" "…trust is read from the host's config dir, not the default one"
rm -f "$OWN/.claude.json"
check "$(RC)" "0" "a plain run"
check "$(plutil -extract EnvironmentVariables.CLAUDE_CONFIG_DIR raw -o - "$NP")" "$OWN" "…its plist carries the scope's login"
check "$(RC --check)" "0" "--check after"
has "$T/out" "ok       node · laptop: in sync, running" "…in sync"
plutil -remove EnvironmentVariables.CLAUDE_CONFIG_DIR "$NP"   # the stopgap's case: a host on the default login
check "$(RC --check)" "1" "--check: the host's plist names no config dir"
has "$T/out" "FAIL     node · laptop: runs on $REAL/.claude, not $REAL/.cfg-own" "…FAILs, naming both"
check "$(RC)" "1" "a plain run with that host running"
check "$(plutil -extract EnvironmentVariables.CLAUDE_CONFIG_DIR raw -o - "$NP" 2>/dev/null)" "" "…leaves it for --restart (it would end its sessions)"
echo 731 > "$T/kids/$(cat "$T/pids/$NL")"
echo "{\"pid\":731,\"sessionId\":\"5e55731-0000\",\"status\":\"idle\",\"statusUpdatedAt\":$(( ($(date +%s) - 60) * 1000 )),\"cwd\":\"$HOME/projects/node\"}" > "$OWN/sessions/731.json"
echo "{\"pid\":731,\"sessionId\":\"dead0731-0000\",\"status\":\"busy\",\"statusUpdatedAt\":$(( ($(date +%s) - 86400) * 1000 ))}" > "$DEF/sessions/731.json"   # a dead session's leftover, the pid reused
check "$(RC --restart node)" "0" "--restart with an idle session recorded in the scope's login dir"
hasnt "$T/out" "busy" "…the newest record is found there, past a stale one in the default dir: idle, not busy"
check "$(plutil -extract EnvironmentVariables.CLAUDE_CONFIG_DIR raw -o - "$NP")" "$OWN" "…and the host moves to the scope's login"
rm -f "$T/kids/"* "$OWN/sessions/731.json" "$DEF/sessions/731.json"
reg false acct-own
check "$(RC --check)" "1" "\"rc\": false with the host still loaded"
has "$T/out" "FAIL     node · laptop: a confidential scope's host is loaded, held: \"rc\": false" "…FAILs"
check "$(RC)" "0" "a plain run"
has "$T/out" "retiring $NL" "…retires it: \"rc\": false keeps winning"
test -f "$NP"; check $? 1 "…its plist gone"
check "$(RC --check)" "0" "--check after"
hasnt "$T/out" "node · laptop" "…\"rc\": false says nothing once no host is left"
reg '{}' acct-main
check "$(RC)" "0" "a scope on the default login"
check "$(plutil -extract EnvironmentVariables.CLAUDE_CONFIG_DIR raw -o - "$NP" 2>/dev/null)" "" "…no CLAUDE_CONFIG_DIR for the default dir: it would move .claude.json"
check "$(RC --check)" "0" "…and --check"
has "$T/out" "ok       node · laptop: in sync" "…in sync"
echo '{"repos": {"node": {"hosts": ["laptop"], "rc": {}}}, "scopes": [{"repos": ["node"], "confidential": true}]}' > "$T/coding/repos.json"
rm -f "$NP"
check "$(RC)" "1" "a registry whose scopes is no object (torn)"
has "$T/out" "the registry does not read" "…refuses, naming why"
test -f "$NP"; check $? 1 "…and writes no host on the default login"
unset ACCOUNTS_FILE ACCOUNT_ORCA_FILE

echo "a label move: wharf-runs/label-prefix-previous, and claude-host's identifier its own key (2026-10-30)"
LA="$HOME/Library/LaunchAgents"; rm_own "$LA"/*.plist; rm -f "$T/pids/"* "$T/kids/"*
OH="$LA/org.old.jobs.host.demo.plist"; NH="$LA/org.example.claude.host.demo.plist"
echo '{"repos": {"demo": {"hosts": ["laptop"]}}}' > "$T/coding/repos.json"
check "$(RC)" "0" "demo's host written under the current prefix"
mv "$NH" "$OH"; mv "$T/pids/org.example.claude.host.demo" "$T/pids/org.old.jobs.host.demo"   # as if written before the move
: > "$LA/org.old.jobs.host.gone.plist"
check "$(RC --check)" "0" "no previous key: --check"
has "$T/out" "missing  demo · laptop" "…a host under another prefix is not demo's (today's behaviour)"
hasnt "$T/out" "org.old.jobs" "…nor any job of the other prefix"
echo org.old.jobs > "$REGATTA_CONFIG/wharf-runs/label-prefix-previous"
L=org.old.jobs.host.demo session 901 idle 30; : > "$T/calls"
check "$(RC --check)" "0" "with it: --check"
has "$T/out" "would relabel demo · laptop: org.old.jobs.host.demo → org.example.claude.host.demo — ends its sessions" "…names the relabel, and that it ends a session"
has "$T/out" "would relabel 1 host(s) from org.old.jobs to org.example.claude" "…counts it"
hasnt "$T/out" "missing  demo" "…never also as a missing host"
has "$T/out" "unwanted org.old.jobs.host.gone: retires on the next run" "…a previous-prefix host no repo wants is unwanted, as under the current prefix"
hasnt "$T/calls" "bootout" "…and changes nothing"
check "$(RC --reap --dry-run)" "0" "--reap --dry-run"
has "$T/out" "would relabel demo · laptop" "…says the relabel converge would make"
hasnt "$T/out" "would load" "…and no load beside it (the relabel is the load)"
hasnt "$T/out" "would retire org.old.jobs.host.demo" "…nor a retire of the host it moves"
test -f "$OH"; check $? 0 "…and leaves it"
DP=$(cat "$T/pids/org.old.jobs.host.demo"); echo $$ > "$T/pids/org.old.jobs.host.demo"   # this suite's shell: an ancestor of the run
check "$(RC)" "0" "a plain run from one of the old host's own sessions"
has "$T/out" "waiting  demo · laptop: this run is one of its sessions — the hourly --reap relabels it" "…leaves it for a run from outside"
check "$(test -f "$OH" && echo old) $(test -f "$NH" && echo new)" "old " "…old host kept, no second host loaded beside it"
hasnt "$T/out" "org.old.jobs.host.demo:" "…nor retired"
echo "$DP" > "$T/pids/org.old.jobs.host.demo"; : > "$LA/org.old.jobs.host.gone.plist"   # that run retired it
check "$(RC)" "0" "a plain run"
has "$T/out" "relabel   demo · laptop: org.old.jobs.host.demo → org.example.claude.host.demo — ends its sessions" "…relabels the host, session and all (the owner accepted it)"
has "$T/out" "relabelled 1 host(s) from org.old.jobs to org.example.claude" "…and reports the count"
has "$T/calls" "bootout gui/$(id -u)/org.old.jobs.host.demo" "…the old job booted out"
has "$LOG" "rc-hosts relabels this host to org.example.claude.host.demo (label move)" "…each session it ends noted in the host's log as a planned close"
check "$(test -f "$OH" && echo old) $(test -f "$NH" && echo new) $(cat "$T/pids/org.example.claude.host.demo" 2>/dev/null)" " new 500" "…its plist gone, the new one written and running"
has "$T/out" "retiring org.old.jobs.host.gone" "…and the unwanted one retired"
check "$(RC --check)" "0" "--check after"
has "$T/out" "ok       demo · laptop: in sync, running" "…in sync"
hasnt "$T/out" "relabel" "…nothing left to relabel"
rm -f "$T/kids/"*
: > "$LA/org.old.jobs.rc-reap.plist"
check "$(RC --check)" "0" "the reaper under the previous prefix: --check"
has "$T/out" "reaper: hourly, under org.old.jobs.rc-reap (a plain run relabels it)" "…reads it as scheduled"
has "$T/out" "would relabel reaper: org.old.jobs.rc-reap → org.example.claude.rc-reap" "…and says it would move"
echo 777 > "$T/pids/org.old.jobs.rc-reap"   # running: this --reap may be that very job
RC --reap > /dev/null
test -f "$LA/org.old.jobs.rc-reap.plist"; check $? 0 "…never while it runs (a bootout would end the pass it may be)"
rm -f "$T/pids/org.old.jobs.rc-reap"
touch "$T/bootstrap-fails"
RC > /dev/null
has "$T/out" "FAILED   reaper: org.example.claude.rc-reap did not load — org.old.jobs.rc-reap keeps reaping" "a failed load of the new reaper says so"
test -f "$LA/org.old.jobs.rc-reap.plist"; check $? 0 "…and keeps the old one: never no reaper"
rm -f "$T/bootstrap-fails" "$LA/org.example.claude.rc-reap.plist"
check "$(RC)" "0" "a plain run"
check "$(test -f "$LA/org.old.jobs.rc-reap.plist" && echo old) $(plutil -extract Label raw -o - "$LA/org.example.claude.rc-reap.plist" 2>/dev/null)" " org.example.claude.rc-reap" "…relabels the reaper"
: > "$LA/org.old.jobs.rc-reap.plist"
RC --unschedule-reap > /dev/null
check "$(ls "$LA" | grep -c rc-reap)" "0" "--unschedule-reap removes the reaper under either prefix"
rh() { python3 -c 'import importlib.machinery, sys; m = importlib.machinery.SourceFileLoader("rh", sys.argv[1]).load_module(); print(eval(sys.argv[2]))' "$T/coding/bin/rc-hosts" "$1"; }
check "$(rh '(m.ours("org.old.jobs.autofinish"), m.is_host("org.old.jobs.host.x"), m.ours("com.example.other"))')" "(True, True, False)" \
  "--agents and its --fix read a job under the previous prefix as ours"
echo org.example.claude > "$REGATTA_CONFIG/wharf-runs/label-prefix-previous"
check "$(rh '(m.PREV_PREFIX, m.ours("org.old.jobs.autofinish"))')" "('', False)" "a previous key equal to the current one is none"
rm -f "$REGATTA_CONFIG/wharf-runs/label-prefix-previous"
check "$(rh 'm.LAUNCHER_ID')" "org.example.claude-host" "no launcher-id key: claude-host's identifier is the prefix's, as before"
STAMP=$(rh 'm.source_sha()')
echo org.new.claude > "$REGATTA_CONFIG/wharf-runs/label-prefix"
check "$(rh 'm.source_sha()' | grep -c "^$STAMP\$")" "0" "…so a label move alone changes the stamp, which reads as a rebuild owed"
echo org.example.claude-host > "$REGATTA_CONFIG/wharf-runs/launcher-id"
check "$(rh '(m.LAUNCHER_ID, m.SIGN[-1])')" "('org.example.claude-host', 'org.example.claude-host')" "wharf-runs/launcher-id: the identifier codesign is given"
check "$(rh 'm.source_sha()')" "$STAMP" "…and the stamp stays the build's across the move"
echo org.example.claude > "$REGATTA_CONFIG/wharf-runs/label-prefix"; rm -f "$REGATTA_CONFIG/wharf-runs/launcher-id"

echo "wharf-runs/rc-hosts: the Macs that run Remote Control hosts (the key absent: every Mac)"
RK="$REGATTA_CONFIG/wharf-runs/rc-hosts"; rm -f "$RK"
rm_own "$LA"/org.example.claude.host.*.plist; rm -f "$T/pids/"* "$T/kids/"*; : > "$T/calls"
echo '{"repos": {"demo": {"hosts": ["laptop"]}}}' > "$T/coding/repos.json"
check "$(RC)" "0" "no key: a plain run"
test -f "$LA/$L.plist"; check $? 0 "…writes the host, as before the key existed"
check "$(RC --check)" "0" "…and --check"
has "$T/out" "ok       demo · laptop: in sync" "…says in sync"
hasnt "$T/out" "wharf-runs/rc-hosts" "…and says nothing of the key"
echo "buildbox laptop" > "$RK"
check "$(RC --check)" "0" "the key names this Mac among others"
has "$T/out" "ok       demo · laptop: in sync" "…the host stays"
hasnt "$T/out" "wharf-runs/rc-hosts" "…no note of the key"
printf 'Buildbox\nLAPTOP\n' > "$RK"
check "$(RC --check)" "0" "the key names this Mac on a line of its own, in capitals"
has "$T/out" "ok       demo · laptop: in sync" "…lower-case compared, lines joined: the host stays"
check "$(RC)" "0" "a plain run"
hasnt "$T/out" "retiring" "…retires nothing"
echo buildbox > "$RK"
check "$(RC --check)" "0" "the key names another Mac"
has "$T/out" "wharf-runs/rc-hosts keeps Remote Control hosts off on laptop (it names buildbox)" "…--check says the key keeps hosts off here"
hasnt "$T/out" "missing" "…not that a host is missing"
hasnt "$T/out" "differs" "…nor that it differs"
has "$T/out" "unwanted $L: retires on the next run" "…the empty host is named as retiring"
echo 810 > "$T/kids/$(cat "$T/pids/$L")"; : > "$T/calls"
check "$(RC)" "0" "a plain run with a session in the host"
has "$T/out" "waiting  $L: no longer wanted here, holds a session" "…it waits, as for any unwanted host"
test -f "$LA/$L.plist"; check $? 0 "…its plist kept"
hasnt "$T/calls" "bootout gui/$(id -u)/$L" "…and not unloaded"
check "$(RC --check)" "0" "--check with the session still there"
has "$T/out" "unwanted $L: holds a session — retires once empty" "…says it waits"
nosession; : > "$T/calls"
check "$(RC)" "0" "a plain run once the host is empty"
has "$T/out" "retiring $L: no longer wanted here" "…retires it"
has "$T/out" "wharf-runs/rc-hosts leaves this Mac out" "…naming the key among the reasons"
test -f "$LA/$L.plist"; check $? 1 "…its plist gone"
has "$T/calls" "bootout gui/$(id -u)/$L" "…unloaded"
check "$(RC)" "0" "a plain run after"
test -f "$LA/$L.plist"; check $? 1 "…writes no host back"
check "$(RC --check)" "0" "--check after"
hasnt "$T/out" "unwanted" "…nothing left to retire"
printf '' > "$RK"
check "$(RC --check)" "0" "the key written empty names no Mac"
has "$T/out" "keeps Remote Control hosts off on laptop (it names no Mac)" "…hosts stay off"
rm -f "$RK"
check "$(RC)" "0" "the key removed: a plain run"
test -f "$LA/$L.plist"; check $? 0 "…the host is written again"

echo "…the hourly --reap's converge retires an empty host too, and a busy one waits"
echo buildbox > "$RK"
session 811 busy 1; : > "$T/calls"
check "$(RC --reap)" "0" "--reap with a busy session in the host"
test -f "$LA/$L.plist"; check $? 0 "…keeps the host: a busy session is never ended"
hasnt "$T/calls" "bootout" "…and unloads nothing"
check "$(RC --check)" "0" "--check meanwhile"
has "$T/out" "unwanted $L: holds a session — retires once empty" "…says it waits: the key is honoured, not ignored"
nosession
check "$(RC --reap)" "0" "--reap once it is empty"
has "$T/out" "retiring $L" "…retires it"
test -f "$LA/$L.plist"; check $? 1 "…its plist gone"
rm -f "$RK"; RC >/dev/null; printf 'buildbox\n' > "$RK"   # the host is back, the key off again

echo "…--agents: a host plist the key leaves unwanted is pending while the reaper retires it, never a FAIL"
rm_own "$LA"/org.example.claude.host.*.plist; rm -f "$T/pids/"* "$LA/org.example.claude.rc-reap.plist"
mkplist org.example.claude.host.unl "$H" remote-control --name unl           # names claude-host, not loaded
mkplist org.example.claude.host.bare "$HOME/.local/bin/claude" remote-control --name bare   # bare, empty
rm -f "$RK"
check "$(RC --agents)" "1" "no key: an unloaded and a bare empty host both fail the check"
has "$T/out" "UNLOADED org.example.claude.host.unl" "…the unloaded one"
has "$T/out" "BARE     org.example.claude.host.bare" "…the bare one"
echo buildbox > "$RK"
check "$(RC --agents)" "1" "the key naming another Mac, the reaper not scheduled: nothing retires them hourly, so both still fail"
mkplist org.example.claude.rc-reap "$P/rc-hosts" --reap
check "$(RC --agents)" "0" "…scheduled: the check passes"
has "$T/out" "--       org.example.claude.host.unl: " "…the unloaded host is a pending line"
has "$T/out" "--       org.example.claude.host.bare: " "…the bare host too"
has "$T/out" "wharf-runs/rc-hosts keeps off here: the hourly reap retires it" "…saying the key and the reaper"
hasnt "$T/out" "UNLOADED" "…no UNLOADED left"
mkplist org.example.claude.dispatch.q.r.202611010900 "$P/dispatch" claude/q --repo r
check "$(RC --agents)" "1" "…a bare idle job that is no host still fails"
has "$T/out" "BARE     org.example.claude.dispatch.q.r.202611010900" "…named"
rm -f "$LA/org.example.claude.dispatch.q.r.202611010900.plist"
echo "laptop" > "$RK"
check "$(RC --agents)" "1" "the key naming this Mac: a bare empty host fails, as without a key"
has "$T/out" "BARE     org.example.claude.host.bare" "…named"
mkdir -p "$RK.d"; rm -f "$RK"; ln -s "$RK.d" "$RK"; rm -f "$LA/org.example.claude.host.unl.plist"
check "$(RC --agents)" "1" "a key that does not read (a directory) means every Mac"
has "$T/out" "wharf-runs/rc-hosts does not read" "…says so on stderr"
has "$T/out" "BARE     org.example.claude.host.bare" "…the bare host counts"
rm -f "$RK"; rm_own "$RK.d"; echo buildbox > "$RK"
mkplist org.example.claude.host.unl "$H" remote-control --name unl
check "$(RC --agents --fix)" "0" "the key off: --fix too"
test -f "$LA/org.example.claude.host.unl.plist"; check $? 0 "…leaves a host to converge, as it always did"
check "$(RC --reap)" "0" "--reap"
test -f "$LA/org.example.claude.host.unl.plist"; check $? 1 "…converge retires the unloaded host"
test -f "$LA/org.example.claude.host.bare.plist"; check $? 1 "…and the bare one"
check "$(RC --agents)" "0" "…and --agents is ok"
has "$T/out" "ok       LaunchAgents: every job that starts claude starts through claude-host" "…plainly"

echo "…a confidential scope's host loaded against its hold is a FAIL on a Mac the key leaves out too"
repo "$HOME/projects/node"
echo '{"repos": {"node": {"hosts": ["laptop"], "rc": false}}, "scopes": {"sec": {"repos": ["node"], "confidential": true, "login": "acct-own"}}}' > "$T/coding/repos.json"
mkplist org.example.claude.host.node "$H" remote-control --name node; echo 500 > "$T/pids/org.example.claude.host.node"
check "$(RC --check)" "1" "--check, the key naming another Mac, \"rc\": false and the host loaded"
has "$T/out" "FAIL     node · laptop: a confidential scope's host is loaded, held" "…FAILs, as without the key"
has "$T/out" "keeps Remote Control hosts off on laptop" "…and says the key"
check "$(RC)" "0" "a plain run"
has "$T/out" "retiring org.example.claude.host.node" "…retires it"
check "$(RC --restart demo)" "1" "--restart of a host on a Mac the key leaves out"
has "$T/out" "wharf-runs/rc-hosts keeps hosts off on laptop" "…names the key, not an empty list"
rm -f "$RK"

echo
[ "$fails" -eq 0 ] && echo "all rc-hosts tests pass" || { echo "$fails rc-hosts test(s) FAILED"; exit 1; }
