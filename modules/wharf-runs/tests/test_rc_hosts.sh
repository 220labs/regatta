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
export HOME="$T/home"
export REGATTA_LEGACY="$HOME/projects/overlay"   # a stand-in overlay: the checkout claude-host's allowlist names (rc-hosts primary())
mkdir -p "$HOME/projects/demo" "$HOME/.local/bin" "$HOME/Library/LaunchAgents" "$HOME/.claude/sessions" "$T/coding/bin" "$T/stub" "$T/pids" "$T/kids"
touch "$HOME/.local/bin/claude"
# Links, not copies (B7): rc-hosts finds the core from its own resolved path (lib/core_path.py), and
# reads the registry and the launcher's source through the overrides below, never the real ones.
ln -s "$B/rc-hosts" "$T/coding/bin/rc-hosts"
mkdir -p "$HOME/projects/overlay/bin"; ln -s "$B/rc-hosts" "$HOME/projects/overlay/bin/rc-hosts"   # the primary's, which the walk's job runs
export CLAUDE_REPOS_JSON="$T/coding/repos.json" RC_HOSTS_SOURCE="$T/coding/bin/claude-host.c"
# claude-host.c is the overlay's (it names the overlay's scripts), found through the core; the
# launcher cases build it, so without one the suite says so and stops
CH=$(REGATTA_LEGACY="$SUITE_OVERLAY" python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import core_path; core_path.add(); import common; print(common.tool("claude-host.c") or "")' "$B/../lib" 2>/dev/null)
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
chmod +x "$T/stub/"*
export PATH="$T/stub:$PATH"
L=org.example.claude.host.demo; LOG="$HOME/Library/Logs/claude-host/demo.log"
RC() { python3 "$T/coding/bin/rc-hosts" "$@" > "$T/out" 2>&1; echo $?; }
session() {  # session <pid> <idle|busy>: a host child with Claude Code's record of it
  echo "$1" > "$T/kids/$(cat "$T/pids/$L")"
  echo "{\"pid\":$1,\"sessionId\":\"5e55$1-0000\",\"status\":\"$2\",\"statusUpdatedAt\":$(( $(date +%s) * 1000 )),\"cwd\":\"$HOME/projects/demo\"}" > "$HOME/.claude/sessions/$1.json"
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
rm -rf "$HOME/projects/broken"
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
mv "$H" "$H.v2"; printf '#!/bin/sh\necho "usage: claude-host remote-control <args...> | claude-host --probe" >&2; exit 2\n' > "$H"; chmod +x "$H"
check "$(RC --launcher "$P/dispatch")" "1" "a granted build from before 2026-10-18 (no --version) hosts, but starts no script"
mv "$H.v2" "$H"
G="$HOME/.local/bin/claude-host.granted"
cp "$G" "$T/granted.keep"; rm -f "${G:?}"
check "$(RC --launcher "$P/dispatch")" "1" "no grant on record: nothing goes through it"
cp "$T/granted.keep" "$G"

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
# launcher line starts must be the primary checkout's script. clock is private-first: the public twin
# has none, so the block runs only beside it
if [ -f "$B/clock" ]; then
HEAD=$(python3 -c 'import importlib.machinery as m, importlib.util as u, sys; l=m.SourceFileLoader("c", sys.argv[1]); s=u.spec_from_loader("c", l); c=u.module_from_spec(s); l.exec_module(c); print(c.PROMPT_HEAD)' "$B/clock")
python3 - "$T/autos.json" "$HEAD" "$P" "$HOME" <<'PY'
import json, sys
out, head, p, home = sys.argv[1:]
mk = lambda n, line: {"id": n, "name": n, "prompt": head + "\n\n" + line}
json.dump([mk("night", p + "/clock fire aurora -- " + p + "/weekly-run aurora " + home),
           mk("pass", p + "/dispatch claude/x --repo r --account a"),
           mk("free", "Tidy the docs")], open(out, "w"))
PY
check "$(RC --agents)" "0" "automations whose lines name the primary's scripts: green"
has "$T/out" "ok       automation night: Orca starts its run; weekly-run is the primary checkout's" "…a fired job named"
has "$T/out" "ok       automation pass: Orca starts its run; dispatch is the primary checkout's" "…a dispatch line named"
hasnt "$T/out" "automation free" "…a prompt not in the clock's shape is clock check's, not this check's"
python3 - "$T/autos.json" "$HEAD" "$HOME" <<'PY'
import json, sys
out, head, home = sys.argv[1:]
json.dump([{"id": "wt", "name": "wt", "prompt": head + "\n\n" + home + "/projects/overlay-copy/bin/dispatch claude/x"},
           {"id": "bare", "name": "bare", "prompt": head + "\n\ndispatch claude/x"},
           {"id": "fc", "name": "fc", "prompt": head + "\n\n" + home + "/projects/overlay-copy/bin/clock fire aurora -- " + home + "/projects/overlay/bin/weekly-run aurora " + home}], open(out, "w"))
PY
check "$(RC --agents)" "1" "an automation launching another copy's dispatch, or firing through another clock, counts, once ready"
has "$T/out" "OUTSIDE  automation wt: launches dispatch from outside $P" "…named OUTSIDE"
has "$T/out" "note     automation bare: dispatch named without a path" "…a pathless line is a note"
has "$T/out" "OUTSIDE  automation fc: fires through" "…a fire through another checkout's clock named OUTSIDE"
echo '[]' > "$T/autos.json"
printf '#!/bin/sh\nexit 1\n' > "$T/stub/orca.down"; chmod +x "$T/stub/orca.down"
check "$(ORCA_HOST_CLI="$T/stub/orca.down" RC --agents)" "0" "Orca unread: a note, never a failure"
has "$T/out" "note     Orca automations: not read" "…said"
hasnt "$T/out" "--       Orca automations" "…in no line the overlay's bootstrap.sh --check counts as a pending LaunchAgent"
fi
mkplist org.example.claude.dispatch.x.z.202611010900 "$P/dispatch" claude/z
rm -f "${G:?}"
check "$(RC --agents)" "0" "before this Mac's sitting, a bare job is a note, never a failure (the laptop's check must not stop on it)"
has "$T/out" "--       org.example.claude.dispatch.x.z.202611010900" "…named"
has "$T/out" "the sitting is rc-hosts --grant" "…with the sitting"
cp "$T/granted.keep" "$G"
rm -f "${LA:?}"/*.plist "$T/pids/org.example.claude.ok"; mv "$T/la.keep/"*.plist "$LA/" 2>/dev/null

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

echo
[ "$fails" -eq 0 ] && echo "all rc-hosts tests pass" || { echo "$fails rc-hosts test(s) FAILED"; exit 1; }
