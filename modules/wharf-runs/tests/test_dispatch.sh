#!/usr/bin/env bash
# Tests for bin/dispatch and bin/dispatch-rc — scratch HOME and a scratch origin; stand-ins for
# launchctl, claude, ssh, screen, open and yabai. No launchd job, screen, window or real
# session is touched.
#   bash modules/wharf-runs/tests/test_dispatch.sh
set -u
# A dispatch session runs this suite inside its own run: its depth, brief and marker would change
# what is tested (re-review 2026-10-05: "a person's run is depth 1" failed under DISPATCH_DEPTH=1).
unset WEEKLY_RUN CLAUDE_UNATTENDED CLAUDE_CODE_DISABLE_BACKGROUND_TASKS DISPATCH_DEPTH DISPATCH_BRIEF DISPATCH_LABEL DISPATCH_LOG DISPATCH_YEAR \
      DISPATCH_MAX_DEPTH DISPATCH_MAX_RUNS DISPATCH_MAX_H \
      RUN_SEED_DEPTH RUN_SEED_BRIEF RUN_SEED_LABEL RUN_SEED_LOG RUN_SEED_YEAR \
      DISPATCH_MANAGER DISPATCH_MANAGER_ACCOUNT DISPATCH_MANAGER_HOST DISPATCH_PLAN DISPATCH_PLAN_SPACE DISPATCH_TASK ASK_ACCOUNT DISPATCH_REPO DISPATCH_PIN CLAUDE_CODE_SESSION_ID \
      DISPATCH_SKIPPER DISPATCH_SKIPPER_ACCOUNT DISPATCH_SKIPPER_HOST DISPATCH_SHIP DISPATCH_MODE \
      DISPATCH_ORIGIN DISPATCH_LOADED_AT DISPATCH_QUEUE_NOW DISPATCH_HOST
# (the last two lines: a run's own manager — session-asks R1 — would name itself the manager of every test run)
# and every other DISPATCH_* a run carries, by pattern: a fixed list goes stale (AGENTS.md's trap; a stray
# DISPATCH_QUEUE_NOW shifted every rank and lease case: the queue's second review, item 19)
unset $(compgen -v | grep '^DISPATCH_')
# The caller's login dir too: from a acct-c session (~/.acct-c) dispatch read the real dir's
# trust, took the headless path, and 26 screen cases failed (2026-10-06). Cases that want one set it.
unset CLAUDE_CONFIG_DIR
B="$(cd "$(dirname "$0")/../bin" && pwd)"   # the module's bin/ (B7: the suites moved to tests/)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
# the fixture before the lookup below: what the cases expect is read from the same config dir the
# tools read, so a Mac's own overlay (its marker) is never the expectation (suites-host, 2026-10-20)
. "$(cd "$(dirname "$0")" && pwd)/config_fixture.sh"; fixture_config "$T/config"   # the suite's own config dir, never the login's (config_fixture.sh)
# peers, found as dispatch finds them (the core's tool()): keel (M4), helm's stalls_tick.py (the
# overlay's until B12), wharf's /finish (module_path); the overlay's checkout (overlay_root), else ""
eval "$(python3 - "$B/../lib" <<'CORE'
import shlex, sys
sys.path.insert(0, sys.argv[1])
import core_path
core_path.require()
import common
w, old = common.module_path("wharf"), common.overlay_root()
for k, v in (("KEEL", common.tool("keel")), ("STALLS_TICK", common.tool("stalls_tick.py")), ("HELMLIB", common.tool("helmlib.py")),
             ("FINISH_SKILL", w / "skills" / "finish" / "SKILL.md" if w else None),
             ("LEGACY", old if old and (old / "bin").is_dir() else None)):
    print("%s=%s" % (k, shlex.quote(str(v) if v else "")))
CORE
)"
fails=0
# helm's ask and helm as the run prompt names them: stand-ins, so the prompt cases do not depend on
# which overlay this Mac has (G22's case sets DISPATCH_HELM empty: helm not installed)
export DISPATCH_ASK="$T/peer/bin/ask" DISPATCH_HELM="$T/peer/bin/helm"
# scheduled times relative to today, inside the year launchd's yearless calendar can hold: a fixed
# date went past and failed 5 cases (2026-10-04); one a year ahead is now refused
FUT=$(date -v+30d +%Y-%m-%d); FY=${FUT%%-*}; FM=$((10#$(date -v+30d +%m))); FD=$((10#$(date -v+30d +%d)))
E2=$(date -v+60d +%Y-%m-%d); EM=$((10#$(date -v+60d +%m))); ED=$((10#$(date -v+60d +%d)))
check() { if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3: expected [$2] got [$1]"; fails=$((fails+1)); fi; }
has()   { if grep -qF -- "$2" "$1"; then echo "  ok   $3"; else echo "  FAIL $3: missing [$2]"; sed 's/^/         | /' "$1" | head -20; fails=$((fails+1)); fi; }
# a blueprint's front matter is read by PyYAML, installed per user on these Macs: keep its site when HOME
# moves below (bin/blueprintlib.py; dispatch --next and pickup seed read blueprints, wharf-on-orca S5)
export PYTHONUSERBASE="${PYTHONUSERBASE:-$(python3 -m site --user-base)}"
export HOME="$T/home"; mkdir -p "$HOME/Library/LaunchAgents"
export ACCOUNTS_FILE="$T/no-accounts.json"   # no registry unless a case names one: the default is the config dir's lighthouse/accounts.json, the real one (B9)
# a repo with a seeded branch on a bare origin
git init -q --bare "$T/origin.git"
git init -q -b main "$T/repo"; cd "$T/repo" || exit 1
git config user.email t@t; git config user.name t
git remote add origin "$T/origin.git"
echo x > f; git add f; git commit -qm init
BR=claude/laptop/2026-10-02-demo
git checkout -q -b $BR
mkdir -p docs/handoff; echo "# demo brief" > docs/handoff/2026-10-02-demo.md
git add .; git commit -qm seed
git checkout -q main
git branch -q $BR.copy $BR
git update-ref refs/heads/claude/laptop/2026-10-02-nobrief main
# publish both branches to the scratch origin without a push verb in this file's text
git --git-dir="$T/repo/.git" send-pack "$T/origin.git" "$BR:refs/heads/$BR" "main:refs/heads/claude/laptop/2026-10-02-nobrief" >/dev/null 2>&1 \
  || cp -R "$T/repo/.git/." "$T/origin.git/"
git branch -q -D $BR $BR.copy
# the contract dispatch requires; untracked on main, so the seed commit above never carries it
printf -- '- physical: none\n' > AGENTS.md
cat > "$T/launchctl" <<EOF
#!/bin/sh
echo "\$*" >> "$T/calls"
case "\$1" in print) [ -f "$T/running.\${2##*/}" ] && printf '\tstate = running\n';; esac
exit 0
EOF
cat > "$T/claude" <<EOF
#!/bin/sh
env >> "$T/env.calls"; echo "claude \$*" >> "$T/claude.calls"; pwd >> "$T/claude.calls"; echo ok
EOF
cat > "$T/ssh" <<EOF
#!/bin/sh
echo "ssh \$*" >> "$T/ssh.calls"
case "\$*" in *ConnectTimeout*) exit \${STUB_PROBE_RC:-0};; esac
exit \${STUB_SSH_RC:-0}
EOF
chmod +x "$T/launchctl" "$T/claude" "$T/ssh"
export DISPATCH_LAUNCHCTL="$T/launchctl" DISPATCH_CLAUDE="$T/claude" DISPATCH_SSH="$T/ssh"
# the runs below stay on this Mac unless a test names a host: the default (the dispatch host) is tested on its own
export DISPATCH_DEFAULT_ON=
# the runs below run here, as launchd would fire them (it sets DISPATCH_LABEL); without a label a run
# goes through launchd a minute out ("a direct run" below)
export DISPATCH_LABEL=org.example.claude.dispatch.repo.test-direct
pst() { TZ=UTC LC_ALL=C ps -o lstart= -p "$1" | xargs; }   # what dispatch records as proc_start
# what a peer is told to run: its own core, the checkout its config dir's `home` names, read there
RBIN='"$(head -1 "${REGATTA_CONFIG:-$HOME/.config/regatta}/home" 2>/dev/null)/modules/wharf-runs/bin/dispatch"'

echo "schedule"
"$B/dispatch" $BR --repo "$T/repo" --at "$FUT 04:10" --note "build only" >/dev/null
# one job per scheduled run: org.example.claude.dispatch.<repo>.<topic>.<fire minute>
pl() { ls "$HOME"/Library/LaunchAgents/org.example.claude.dispatch.repo.demo.[0-9]*.plist 2>/dev/null; }
P=$(pl)
check "$(basename "$P")" "org.example.claude.dispatch.repo.demo.${FUT//-/}0410.plist" "the label carries the fire minute"
has "$P" "<key>Month</key><integer>$FM</integer><key>Day</key><integer>$FD</integer><key>Hour</key><integer>4</integer><key>Minute</key><integer>10</integer>" "calendar keys"
has "$P" "<string>build only</string>" "note travels"
has "$P" "DISPATCH_LABEL" "label for self-removal"
"$B/dispatch" $BR --repo "$T/repo" --at "$FUT 04:10" --if-room >/dev/null
has "$(pl)" "<string>--if-room</string>" "--if-room travels to the fired run (the sounding queue's budget gate)"
env -u DISPATCH_LABEL "$B/dispatch" $BR --repo "$T/repo" --at "$FUT 04:10" >/dev/null
has "$(pl)" "<key>DISPATCH_DEPTH</key><string>1</string>" "a person's run is depth 1 of a chain"
env -u DISPATCH_LABEL DISPATCH_DEPTH=2 "$B/dispatch" $BR --repo "$T/repo" --at "$FUT 04:10" >/dev/null
has "$(pl)" "<key>DISPATCH_DEPTH</key><string>3</string>" "  a run's session schedules one deeper"
env -u DISPATCH_LABEL DISPATCH_DEPTH=5 "$B/dispatch" $BR --repo "$T/repo" --at "$FUT 04:10" > "$T/out" 2>&1; check "$?" "2" "  past depth 5: refused"
has "$T/out" "a person starts the next" "  saying who starts it"
env -u DISPATCH_LABEL RUN_SEED_DEPTH=5 "$B/dispatch" $BR --repo "$T/repo" --at "$FUT 04:10" >/dev/null 2>&1; check "$?" "2" "  RUN_SEED_DEPTH (a session started before the rename) counts too"
has "$T/calls" "bootstrap gui/" "job loaded"
if command -v plutil >/dev/null; then plutil -lint "$P" >/dev/null 2>&1 && echo "  ok   plist lints" || { echo "  FAIL plist lint"; fails=$((fails+1)); }; fi

echo "epoch time"
EP=$(date -j -f '%Y-%m-%d %H:%M' "$E2 07:09" +%s)
# a stand-in for bin/account: STUB_ACCT says what pick answers, STUB_LIMITS what limits LABEL says;
# STUB_NOISE is a line printed to stderr first, ahead of any JSON (a future warning)
cat > "$T/acct" <<EOF
#!/bin/sh
echo "account \$*" >> "$T/acct.calls"
[ -n "\${STUB_NOISE:-}" ] && echo "\$STUB_NOISE" >&2
case "\$1" in
  which) [ -n "\${STUB_WHICH:-}" ] && echo "\$STUB_WHICH"; exit 0;;
  pick) case "\${STUB_ACCT:-none}" in
          f) echo '{"account": "acct-c", "primary": false, "env": {"CLAUDE_CONFIG_DIR": "$HOME/.acct-c"}, "reason": "week 10% < 90%", "skipped": []}';;
          acct-a) echo '{"account": "acct-a", "primary": true, "env": {}, "reason": "week 20% < 95%", "skipped": [["acct-c", "repo is on its deny list"]]}';;
          short) echo '{"account": null, "skipped": [["acct-c", "week 95% ≥ 90%"], ["acct-a", "week 99% ≥ 95%"]]}'; exit 3;;
          none) echo "account: no registry" >&2; exit 4;;
          junk) echo "account: probe timed out" >&2; echo "not json"; exit 1;;
        esac;;
  limits) case "\${STUB_LIMITS:-ok}" in
          ok) echo "[{\"label\": \"\$2\", \"provider\": \"claude\", \"primary\": false, \"here\": true, \"env\": {\"CLAUDE_CONFIG_DIR\": \"$HOME/.\$2\"}, \"limits\": {\"seven_day_resets\": $EP}, \"eligible\": true, \"why\": \"week 10%\"}]";;
          denied) echo "[{\"label\": \"\$2\", \"provider\": \"claude\", \"primary\": false, \"here\": true, \"env\": {\"CLAUDE_CONFIG_DIR\": \"$HOME/.\$2\"}, \"limits\": null, \"eligible\": false, \"why\": \"repo is on its deny list\", \"denied\": \"repo\"}]";;
          overage) echo "[{\"label\": \"\$2\", \"provider\": \"claude\", \"primary\": false, \"here\": true, \"env\": {\"CLAUDE_CONFIG_DIR\": \"$HOME/.\$2\"}, \"limits\": {\"seven_day_resets\": $EP}, \"eligible\": false, \"why\": \"extra usage on\", \"overage\": true}]";;
          fail) echo "account: no such label \$2" >&2; exit 1;;
        esac;;
esac
EOF
chmod +x "$T/acct"
"$B/dispatch" $BR --repo "$T/repo" --at "@$EP" >/dev/null
check "$(pl | wc -l | tr -d ' ')" "1" "rescheduling replaces the pending job"
P=$(pl)
has "$P" "<key>Month</key><integer>$EM</integer><key>Day</key><integer>$ED</integer><key>Hour</key><integer>7</integer><key>Minute</key><integer>9</integer>" "@epoch becomes local clock keys (leading zeros too)"

echo "on another host"
mkdir -p "$HOME/projects"; ln -s "$T/repo" "$HOME/projects/other"
env -u DISPATCH_LABEL DISPATCH_DEPTH=2 "$B/dispatch" $BR --repo "$HOME/projects/other" --on buildbox --at "@$EP" --note "it's a note" >/dev/null
has "$T/ssh.calls" "ssh buildbox-ssh" "goes over ssh"
has "$T/ssh.calls" "DISPATCH_DEPTH=2 $RBIN" "  the chain's depth travels (the peer adds one), to the peer's own core"
has "$T/ssh.calls" "--at @$EP" "epoch, not a clock time, crosses the wire"
has "$T/ssh.calls" "note" "note quoted through"
# scheduled there: the asking session is recorded as handed off, so tidy closes its window once idle
HO="$HOME/Library/Caches/run-seed/handoffs"; rm -rf "$HO"
# the asking session sits on the branch it hands off, in the repo it names: its own repo, on $BR
git clone -q -b "$BR" "$T/origin.git" "$T/caller" && ln -s "$T/caller" "$HOME/projects/caller"
git init -q "$T/elsewhere" && git -C "$T/elsewhere" checkout -q -b "$BR"
hand() { local dir=$1 sid=$2; shift 2; (cd "$dir" && CLAUDE_CODE_SESSION_ID=$sid env -u DISPATCH_LABEL "$B/dispatch" $BR --repo "$HOME/projects/caller" --on buildbox --at "@$EP" "$@" >/dev/null 2>"$T/hand.$sid.err"); }
rec() { [ -f "$HO/$1.json" ] && echo recorded || echo none; }
TP="$HOME/Library/LaunchAgents/org.example.claude.dispatch-tidy.plist"
hand "$T/caller" sess-none
check "$(grep -c dispatch-tidy-soon "$T/calls")" "0" "  a Mac with no tidier installed gets no tidy-soon (opt-in per Mac)"
touch "$TP"   # the tidier installed (schedule-tidy); taken away again below, before any run reads it
hand "$T/caller" sess-on
check "$(python3 -c 'import json,sys; h=json.load(open(sys.argv[1])); print(h["to"], h["what"])' "$HO/sess-on.json" 2>&1)" "buildbox dispatch" "  the asking session is recorded as handed off to buildbox"
has "$T/calls" "org.example.claude.dispatch-tidy-soon.plist" "  and a tidy within minutes is loaded, not the 10-minute pass (tidy-soon)"
rm -f "$TP"
hand "$T/caller" sess-probe --probe; check "$(rec sess-probe)" "none" "  a probe hands nothing off: its window stays"
hand "$T/repo" sess-other; check "$(rec sess-other)" "none" "  another branch than the caller's own (/later): nothing recorded"
hand "$T/elsewhere" sess-else; check "$(rec sess-else)" "none" "  the same branch name in another repo: nothing recorded"
printf '#!/bin/sh\nexit 1\n' > "$T/ssh-fail"; chmod +x "$T/ssh-fail"
DISPATCH_SSH="$T/ssh-fail" hand "$T/caller" sess-fail
check "$? $(rec sess-fail)" "1 none" "  a failed one: its exit code kept, nothing recorded — the window stays"
"$B/dispatch" $BR --repo "$HOME/projects/other" --on buildbox --at "$FUT 04:10" 2>/dev/null; check "$?" "2" "a bare clock time with --on is refused"

: > "$T/ssh.calls"
"$B/dispatch" $BR --repo "$HOME/projects/other" --on buildbox 2>/dev/null; check "$?" "0" "--on without --at: now on the peer, not here"
has "$T/ssh.calls" "--at @" "  an epoch a minute and a half out"
echo "the default host: the dispatch host, the laptop as fallback (the owner, 2026-10-13)"
dflt() { env -u DISPATCH_LABEL DISPATCH_DEFAULT_ON=buildbox DISPATCH_HOST="${DH:-laptop}" "$B/dispatch" $BR --repo "$HOME/projects/other" "$@"; }
plo() { ls "$HOME"/Library/LaunchAgents/org.example.claude.dispatch.other.demo.[0-9]*.plist 2>/dev/null; }
n_here() { plo | wc -l | tr -d ' '; }
rm -f $(plo); : > "$T/ssh.calls"
dflt >/dev/null 2>&1; check "$?" "0" "a run with no host named goes to the dispatch host"
has "$T/ssh.calls" "ConnectTimeout=10" "  probed first (--fallback here)"
has "$T/ssh.calls" "$RBIN" "  then scheduled there"
check "$(n_here)" "0" "  nothing scheduled here"
: > "$T/ssh.calls"
STUB_PROBE_RC=255 dflt >/dev/null 2>"$T/err"; check "$?" "0" "the dispatch host unreachable…"
has "$T/err" "scheduling it on this Mac instead" "  …the laptop takes it, and says so"
check "$(n_here)" "1" "  scheduled here"
rm -f $(plo); : > "$T/ssh.calls"
dflt --on here >/dev/null 2>&1; check "$(wc -l < "$T/ssh.calls" | tr -d ' ') $(n_here)" "0 1" "--on here: this Mac, no ssh"
rm -f $(plo); : > "$T/ssh.calls"
DH=buildbox dflt >/dev/null 2>&1; check "$(wc -l < "$T/ssh.calls" | tr -d ' ') $(n_here)" "0 1" "on the dispatch host itself: there, no ssh"
rm -f $(plo); : > "$T/ssh.calls"
dflt --at "$FUT 04:10" >/dev/null 2>&1; check "$(wc -l < "$T/ssh.calls" | tr -d ' ') $(n_here)" "0 1" "a bare clock time stays here (ambiguous across hosts)"
: > "$T/ssh.calls"
rm -f $(plo)
STUB_PROBE_RC=3 dflt >/dev/null 2>"$T/err"; check "$? $(n_here)" "0 1" "a repo the dispatch host has no clone of: the laptop takes it"
rm -f $(plo); : > "$T/ssh.calls"
dflt --yolo >/dev/null 2>&1; check "$(wc -l < "$T/ssh.calls" | tr -d ' ') $(n_here)" "0 1" "a --yolo build stays here (the build Mac is disarmed: its launch would never start)"
D=$(git -C "$T/repo" rev-parse --path-format=absolute --git-common-dir)/claude/dispatched/demo
has "$D" "$BR" "a scheduled run is recorded for pickup (claude/dispatched/<topic>)"
rm -f $(plo); : > "$T/ssh.calls"
dflt --cancel >/dev/null 2>&1; check "$? $(n_here)" "0 0" "--cancel clears here…"
has "$T/ssh.calls" "--cancel" "  …and asks the dispatch host too"
rm -f $(plo)
: > "$T/ssh.calls"
env -u DISPATCH_LABEL DISPATCH_DEFAULT_ON=auto DISPATCH_HOST=buildbox "$B/dispatch" $BR --repo "$HOME/projects/other" --cancel >/dev/null 2>&1
check "$? $(wc -l < "$T/ssh.calls" | tr -d ' ')" "0 0" "--cancel on the build Mac under auto: no ssh to itself (landing review 23)"

echo "the hosts are config: wharf-runs/ssh, wharf-runs/dispatch-host, wharf-runs/label-prefix"
KEYS="$REGATTA_CONFIG/wharf-runs"
printf 'buildbox:buildbox-ssh\nStudio2:studio2-ssh\n' > "$KEYS/ssh"; : > "$T/ssh.calls"
"$B/dispatch" $BR --repo "$HOME/projects/other" --on STUDIO2 --at "@$EP" >/dev/null 2>"$T/err"; check "$?" "0" "a second host the ssh key names is taken, case-blind"
has "$T/ssh.calls" "ssh studio2-ssh DISPATCH_DEPTH=0 $RBIN" "  over its own alias, to its own core"
has "$T/err" "scheduling on Studio2" "  named as the key spells it"
: > "$T/ssh.calls"
"$B/dispatch" $BR --repo "$HOME/projects/other" --on nowhere --at "@$EP" >/dev/null 2>"$T/err"; check "$?" "2" "a host the key does not name is refused"
has "$T/err" "unknown host nowhere — wharf-runs/ssh names buildbox, Studio2; or here" "  naming the hosts it holds"
check "$(wc -l < "$T/ssh.calls" | tr -d ' ')" "0" "  and nothing goes over ssh"
"$B/dispatch" $BR --repo "$HOME/projects/other" --on nowhere --cancel >/dev/null 2>&1; check "$?" "2" "  --cancel --on an unknown host: refused too"
"$B/dispatch" $BR --repo "$HOME/projects/other" --on HERE --at "$FUT 04:10" >/dev/null 2>&1; check "$? $(wc -l < "$T/ssh.calls" | tr -d ' ')" "0 0" "--on HERE is here, case-blind"
rm -f $(plo)
mv "$KEYS/dispatch-host" "$KEYS/dispatch-host.off"; : > "$T/ssh.calls"
# the default is berth's pick (--on auto); with no berths in the scope it takes the hosts in the ssh
# key's order, then this Mac — here, in the log-only week, the first that answers (a stub peer)
printf '#!/bin/sh\nprintf "1.00 10\\n0 10\\n"\n' > "$T/berth-ssh"; chmod +x "$T/berth-ssh"
env -u DISPATCH_LABEL -u DISPATCH_DEFAULT_ON BERTH_SSH="$T/berth-ssh" DISPATCH_HOST=laptop "$B/dispatch" $BR --repo "$HOME/projects/other" >/dev/null 2>"$T/err"; check "$?" "0" "no dispatch-host key: a run with no host named…"
has "$T/ssh.calls" "ssh buildbox-ssh DISPATCH_DEPTH=0 $RBIN" "  …goes to the first host the ssh key names (berth's order)"
has "$T/err" "dispatch: berth — buildbox" "  and says so on stderr"
check "$(grep -c 'dispatch: berth' "$T/err")" "1" "  once"
: > "$T/ssh.calls"
env -u DISPATCH_LABEL -u DISPATCH_DEFAULT_ON DISPATCH_HOST=BuildBox "$B/dispatch" $BR --repo "$HOME/projects/other" >/dev/null 2>"$T/err"; check "$?" "0" "  on that host itself (case-blind): here…"
check "$(wc -l < "$T/ssh.calls" | tr -d ' ') $(grep -c 'dispatch-host' "$T/err")" "0 0" "  …no ssh, and no line about a default it did not take"
rm -f $(plo); : > "$T/ssh.calls"
rm -f "$KEYS/ssh"
env -u DISPATCH_LABEL -u DISPATCH_DEFAULT_ON DISPATCH_HOST=laptop "$B/dispatch" $BR --repo "$HOME/projects/other" >/dev/null 2>"$T/err"; check "$? $(wc -l < "$T/ssh.calls" | tr -d ' ') $(n_here)" "0 0 1" "  no ssh key either: the run stays here, as before any peer"
"$B/dispatch" $BR --repo "$HOME/projects/other" --on buildbox --at "@$EP" >/dev/null 2>"$T/err"; check "$?" "2" "  and --on any host is refused…"
has "$T/err" "unknown host buildbox — wharf-runs/ssh names no host; or here" "    saying the key names none"
rm -f $(plo)
echo buildbox:buildbox-ssh > "$KEYS/ssh"; mv "$KEYS/dispatch-host.off" "$KEYS/dispatch-host"
echo elsewhere > "$KEYS/dispatch-host"; : > "$T/ssh.calls"
env -u DISPATCH_LABEL DISPATCH_DEFAULT_ON=elsewhere DISPATCH_HOST=laptop "$B/dispatch" $BR --repo "$HOME/projects/other" >/dev/null 2>"$T/err"; check "$? $(wc -l < "$T/ssh.calls" | tr -d ' ') $(n_here)" "0 0 1" "a default host the ssh key gives no alias: the run stays here…"
has "$T/err" "the dispatch host elsewhere has no line in wharf-runs/ssh" "  …and says why"
rm -f $(plo); echo buildbox > "$KEYS/dispatch-host"
echo org.other.jobs > "$KEYS/label-prefix"
"$B/dispatch" $BR --repo "$T/repo" --at "$FUT 04:10" >/dev/null
check "$(ls "$HOME"/Library/LaunchAgents/org.other.jobs.dispatch.repo.demo.[0-9]*.plist 2>/dev/null | wc -l | tr -d ' ')" "1" "the label prefix is the key's"
check "$(python3 -c 'import importlib.machinery, sys; print(importlib.machinery.SourceFileLoader("rc", sys.argv[1]).load_module().TIDIER)' "$B/dispatch-rc")" "org.other.jobs.dispatch-tidy" "  the tidier's too"
"$B/dispatch" $BR --repo "$T/repo" --cancel >/dev/null
rm -f "$KEYS/label-prefix"
"$B/dispatch" $BR --repo "$T/repo" --at "$FUT 04:10" >/dev/null
check "$(ls "$HOME"/Library/LaunchAgents/org.regatta.claude.dispatch.repo.demo.[0-9]*.plist 2>/dev/null | wc -l | tr -d ' ')" "1" "  no key: org.regatta.claude"
check "$(python3 -c 'import importlib.machinery, sys; print(importlib.machinery.SourceFileLoader("rc", sys.argv[1]).load_module().TIDIER)' "$B/dispatch-rc")" "org.regatta.claude.dispatch-tidy" "  for the tidier too"
"$B/dispatch" $BR --repo "$T/repo" --cancel >/dev/null
echo org.example.claude > "$KEYS/label-prefix"

"$B/dispatch" $BR --repo "$T/repo" --at "2020-01-01 00:00" 2>/dev/null; check "$?" "2" "a past time is refused"
"$B/dispatch" $BR --repo "$T/repo" --at "$(date -v+400d +%Y-%m-%d) 04:10" 2>/dev/null; check "$?" "2" "a time a year or more ahead is refused"

"$B/dispatch" $BR --repo "$HOME/projects/other" --on buildbox --at "@$EP" >/dev/null 2>&1
has "$T/ssh.calls" '--repo $HOME/projects/other' "--repo travels as a path under ~/projects"
"$B/dispatch" $BR --repo "$T/repo" --on buildbox --at "@$EP" >/dev/null 2>&1; check "$?" "2" "--on with a repo outside ~/projects is refused"
"$B/dispatch" $BR --repo "$T/repo" --at "$FUT 04:10" --headless >/dev/null
P=$(pl)
has "$P" "<string>--headless</string>" "--headless travels in the plist"
"$B/dispatch" $BR --repo "$HOME/projects/other" --on buildbox --at "@$EP" --headless >/dev/null 2>&1
has "$T/ssh.calls" "--headless" "  and over ssh"
"$B/dispatch" $BR --repo "$T/repo" --at "$FUT 04:10" --background allow >/dev/null
has "$(pl)" "<string>--background</string><string>allow</string>" "--background travels in the plist"
"$B/dispatch" $BR --repo "$HOME/projects/other" --on buildbox --at "@$EP" --background deny >/dev/null 2>&1
has "$T/ssh.calls" "--background deny" "  and over ssh"
"$B/dispatch" $BR --repo "$T/repo" --at "$FUT 04:10" --background maybe >/dev/null 2>&1; check "$?" "2" "  anything but allow or deny is refused"
"$B/dispatch" $BR --repo "$T/repo" --at "$FUT 04:10" >/dev/null
P=$(pl); PL=$(basename "$P" .plist)
has "$P" "<key>DISPATCH_LOG</key>" "log path fixed in the plist"
has "$P" "<key>DISPATCH_YEAR</key><string>$FY</string>" "scheduled year in the plist"
DISPATCH_YEAR=2019 DISPATCH_LABEL=$PL "$B/dispatch" $BR --repo "$T/repo" 2>&1 | grep -q "not running" && echo "  ok   a job a year late refuses to run" || { echo "  FAIL year guard"; fails=$((fails+1)); }

echo "fire (as launchd would), headless"
"$B/dispatch" $BR --repo "$T/repo" --at "$FUT 04:10" >/dev/null; P=$(pl); PL=$(basename "$P" .plist)
DISPATCH_LOG="$HOME/fixed.log" DISPATCH_LABEL=$PL "$B/dispatch" $BR --repo "$T/repo" --note "build only" --headless
L="$HOME/fixed.log"
has "$L" "== exit 0" "claude ran to the end"
has "$T/claude.calls" "--model opus --effort high" "tier passed"
has "$T/claude.calls" "claude -p You are an unattended session" "--headless is claude -p"
has "$T/claude.calls" "build only" "note in the prompt"
has "$T/claude.calls" "in the foreground: never run_in_background, Monitor or a background agent" "checks in the foreground: a -p session ends with its turn (2026-10-04)"
has "$T/claude.calls" "do not push, except through \`dispatch --next --repo $T/repo\`" "the prompt allows the one push dispatch --next makes, naming its repo"
has "$T/claude.calls" "$T/repo/.claude/worktrees/demo" "ran inside the branch's worktree"
has "$T/claude.calls" "--permission-mode auto" "auto mode: a would-prompt call is denied headless (docs/record/run-seed-permissions-2026-10-04.md)"
has "$T/claude.calls" "Bash(*bin/pr merge*)" "bin/pr deny by its launch verb, in the matcher's wildcard form"
has "$T/claude.calls" "Bash(*libexec/pr merge*)" "  and wharf's libexec/pr, the path /finish names with no overlay"
has "$T/claude.calls" "Bash(*regatta pr merge*)" "  and the core's regatta pr, its C1 way into libexec/pr (B14b landing review)"
grep -q 'Bash(python3:\*)\|Bash(bash:\*)' "$T/claude.calls"; check "$?" "1" "no interpreter wildcard on the allowlist"
grep -q 'bin/pr:\*' "$T/claude.calls"; check "$?" "1" "no dead prefix-with-star pattern"
check "$(git -C "$T/repo/.claude/worktrees/demo" rev-parse --abbrev-ref HEAD)" "$BR" "worktree on the branch"
check "$([ -f "$P" ] && echo present || echo gone)" "gone" "one-shot plist removed"
has "$T/calls" "bootout gui/" "job unloaded after the run"

echo "the session never sees the job's variables"
check "$(grep -c "DISPATCH_LABEL" "$T/env.calls" 2>/dev/null)" "0" "claude's environment has no DISPATCH_*"
grep -q "^CLAUDE_UNATTENDED=dispatch$" "$T/env.calls"; check "$?" "0" "but it has CLAUDE_UNATTENDED: checkpoint.py keeps the run read-only on live systems"
grep -q "^CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1$" "$T/env.calls"; check "$?" "0" "no background tasks: -p ends with the reply and a backgrounded check dies unread"
has "$L" "== background deny (default for headless)" "  the log says so"
grep -q "^BASH_DEFAULT_TIMEOUT_MS=1800000$" "$T/env.calls"; check "$?" "0" "a foreground check gets 30 min: with the switch on, a timeout kills it"
grep -q "^DISPATCH_DEPTH=1$" "$T/env.calls"; check "$?" "0" "  and its depth in the chain"
BLOB=$(git -C "$T/repo" rev-parse "origin/$BR:docs/handoff/2026-10-02-demo.md")
grep -q "^DISPATCH_BRIEF=$BLOB$" "$T/env.calls"; check "$?" "0" "  and the blob of the brief it started from"
: > "$T/env.calls"; "$B/dispatch" $BR --repo "$T/repo" --probe --headless >/dev/null 2>&1
grep -q "^CLAUDE_UNATTENDED=dispatch$" "$T/env.calls"; check "$?" "0" "  and so does --probe --headless, which must run in the same environment"
grep -q "^CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1$" "$T/env.calls"; check "$?" "0" "    the switch included"

echo "session-asks R1: the manager travels from the scheduling session to the run"
mkdir -p "$HOME/.claude" "$HOME/.acct-c"; RH=$(cd "$HOME" && pwd -P)
env -u DISPATCH_LABEL CLAUDE_CODE_SESSION_ID=mgr-x DISPATCH_ACCOUNT="$T/acct" STUB_WHICH=acct-a DISPATCH_HOST=laptop "$B/dispatch" $BR --repo "$T/repo" --at "$FUT 04:10" >/dev/null
has "$(pl)" "<key>DISPATCH_MANAGER</key><string>mgr-x</string>" "a watched session that schedules a run is its manager"
has "$(pl)" "<key>DISPATCH_MANAGER_ACCOUNT</key><string>$RH/.claude</string>" "  with its login as the config dir's real path (finding 6: one vocabulary)"
has "$(pl)" "<key>DISPATCH_MANAGER_HOST</key><string>laptop</string>" "  and the Mac it runs on (finding 4: no record there = ended)"
# rename S5 (H1): each value under the new name too, until S8 drops the old as a writer
# the manager family only (the plist also carries DEPTH, LABEL, LOG, YEAR), sorted bytewise: a UTF-8 locale's sort skips the punctuation
check "$(grep -oE '<key>DISPATCH_(MANAGER|SKIPPER|PLAN|SHIP)[A-Z_]*</key>' "$(pl)" | grep -v PLAN_SPACE | LC_ALL=C sort | tr '\n' ' ')" \
  "<key>DISPATCH_MANAGER</key> <key>DISPATCH_MANAGER_ACCOUNT</key> <key>DISPATCH_MANAGER_HOST</key> <key>DISPATCH_PLAN</key> <key>DISPATCH_SHIP</key> <key>DISPATCH_SKIPPER</key> <key>DISPATCH_SKIPPER_ACCOUNT</key> <key>DISPATCH_SKIPPER_HOST</key> " \
  "  the plist exports both names: SKIPPER*, SHIP beside MANAGER*, PLAN"
env -u DISPATCH_LABEL CLAUDE_CODE_SESSION_ID=mgr-x CLAUDE_CONFIG_DIR="$HOME/.acct-c" DISPATCH_ACCOUNT="$T/acct" "$B/dispatch" $BR --repo "$T/repo" --at "$FUT 04:10" >/dev/null
has "$(pl)" "<key>DISPATCH_MANAGER_ACCOUNT</key><string>$RH/.acct-c</string>" "  a manager on ~/.acct-c: that dir"
has "$(pl)" "<key>DISPATCH_PLAN</key><string>mgr-x</string>" "  and its plan, one per manager"
mkdir -p "$HOME/Library/Logs/claude-weekly/plans/mgr-x"; echo '{"space": "sp-1"}' > "$HOME/Library/Logs/claude-weekly/plans/mgr-x/plan.json"
env -u DISPATCH_LABEL CLAUDE_CODE_SESSION_ID=mgr-x DISPATCH_ACCOUNT="$T/acct" "$B/dispatch" $BR --repo "$T/repo" --at "$FUT 04:10" >/dev/null
has "$(pl)" "<key>DISPATCH_PLAN_SPACE</key><string>sp-1</string>" "  and the plan's page, the Talk address"
env -u DISPATCH_LABEL CLAUDE_CODE_SESSION_ID=run-y CLAUDE_UNATTENDED=dispatch "$B/dispatch" $BR --repo "$T/repo" --at "$FUT 04:10" >/dev/null
grep -q DISPATCH_MANAGER "$(pl)"; check "$?" "1" "an unattended caller with no manager (autofinish) names none"
env -u DISPATCH_LABEL CLAUDE_CODE_SESSION_ID=run-y CLAUDE_UNATTENDED=dispatch DISPATCH_MANAGER=mgr-x DISPATCH_PLAN=mgr-x "$B/dispatch" $BR --repo "$T/repo" --at "$FUT 04:10" >/dev/null
has "$(pl)" "<key>DISPATCH_MANAGER</key><string>mgr-x</string>" "a run's --next keeps its manager"
env -u DISPATCH_LABEL DISPATCH_MANAGER=mgr-x DISPATCH_PLAN=mgr-x DISPATCH_DEPTH=1 "$B/dispatch" $BR --repo "$HOME/projects/other" --on buildbox --at "@$EP" >/dev/null 2>&1
has "$T/ssh.calls" "DISPATCH_MANAGER=mgr-x" "  and it crosses to the peer"
has "$T/ssh.calls" "DISPATCH_SKIPPER=mgr-x" "    under the new name too (a peer's older checkout reads the old)"
env -u DISPATCH_LABEL CLAUDE_CODE_SESSION_ID=run-y CLAUDE_UNATTENDED=dispatch DISPATCH_SKIPPER=mgr-n DISPATCH_SHIP=ship-n "$B/dispatch" $BR --repo "$T/repo" --at "$FUT 04:10" >/dev/null
check "$(grep -o '<key>DISPATCH_[A-Z]*</key><string>[a-z-]*-n</string>' "$(pl)" | sort | tr '\n' ' ')" \
  "<key>DISPATCH_MANAGER</key><string>mgr-n</string> <key>DISPATCH_PLAN</key><string>ship-n</string> <key>DISPATCH_SHIP</key><string>ship-n</string> <key>DISPATCH_SKIPPER</key><string>mgr-n</string> " \
  "a run carrying only the new names (DISPATCH_SKIPPER, DISPATCH_SHIP) keeps its skipper and ship, written under both"
"$B/dispatch" $BR --repo "$T/repo" --at "$FUT 04:10" >/dev/null; P=$(pl); PL=$(basename "$P" .plist)
: > "$T/env.calls"; : > "$T/claude.calls"
DISPATCH_MANAGER=mgr-x DISPATCH_PLAN=mgr-x DISPATCH_PLAN_SPACE=sp-1 DISPATCH_MANAGER_HOST=laptop DISPATCH_MANAGER_ACCOUNT=/x/.acct-c DISPATCH_LOG="$HOME/mgr.log" DISPATCH_LABEL=$PL "$B/dispatch" $BR --repo "$T/repo" --headless
grep -q "^DISPATCH_MANAGER=mgr-x$" "$T/env.calls"; check "$?" "0" "the run's session has its manager"
grep -q "^DISPATCH_TASK=demo$" "$T/env.calls"; check "$?" "0" "  and its task name for bin/helm report"
check "$(grep -cE '^(DISPATCH_SKIPPER=mgr-x|DISPATCH_SHIP=mgr-x|DISPATCH_SKIPPER_HOST=laptop|DISPATCH_SKIPPER_ACCOUNT=/x/\.acct-c)$' "$T/env.calls")" "4" \
  "  a plist from before S5 (only the old names): the session gets the new names too"
grep -q "^ASK_ACCOUNT=$RH/.claude$" "$T/env.calls"; check "$?" "0" "  its login in the manager's vocabulary: the default dir's real path (finding 6)"
grep -q "^DISPATCH_REPO=$T/repo$" "$T/env.calls"; check "$?" "0" "  and its repo, which bin/helm report records (K6, finding 5)"
has "$T/claude.calls" "bin/ask apply" "  the prompt applies a pending answer first (finding 2)"
has "$T/claude.calls" "bin/ask relay <doc> <Dn>" "the prompt carries the three steps instead of an ask"
has "$T/claude.calls" "bin/helm report --task demo" "  and the ship's reports (the stand-in helm)"
has "$T/claude.calls" "bin/keel step <doc> <S> done --branch" "  and a brief's Steps: are marked done by the run (entry S7, the done prompt)"
has "$T/claude.calls" "AskUserQuestion" "AskUserQuestion is on the denied list (R2's belt)"
check "$(python3 -c 'import json, sys; d=json.load(open(sys.argv[1])); print(d.get("manager"), d.get("plan"), d.get("plan_space"))' "$(ls -t "$HOME/Library/Logs/claude-weekly/run-seed-runs"/*.json | head -1)")" "mgr-x mgr-x sp-1" "the run's record names its manager, plan and page"
# no stand-ins for the paths: with an overlay installed the prompt still names helm's module paths,
# which tool() finds and the overlay's allow rules name since B14a — never the overlay's shims, as it
# did until then. The overlay is a stand-in a config dir of the case's own marks, so the case runs on
# every Mac and in CI alike, never against whichever overlay the login has (suites-host, 2026-10-20)
OVL="$(cd "$T" && pwd -P)/overlay"; mkdir -p "$OVL/bin"   # resolved, as dispatch resolves a checkout that is no git repo
# a config dir that marks the stand-in overlay: the suite's own, plus the marker and the five keys
# the core then wants (B2b's OVERLAY_KEYS), so the core loads as beside a real overlay (B14b: the
# marker is the only way to name an overlay; REGATTA_LEGACY is read by nothing)
ovl_cfg() { rm -rf "$T/config-ovl"; cp -R "$T/config" "$T/config-ovl"; echo "$OVL" > "$T/config-ovl/regatta/overlay"
  for k in guarded orca-deny; do [ -e "$T/config-ovl/regatta/$k" ] || : > "$T/config-ovl/regatta/$k"; done
  [ -e "$T/config-ovl/regatta/log-dir" ] || echo "$HOME/.local/state/regatta" > "$T/config-ovl/regatta/log-dir"
  [ -e "$T/config-ovl/regatta/projects" ] || echo "$HOME/projects" > "$T/config-ovl/regatta/projects"; }
for t in ask plan; do printf '#!/bin/sh\n' > "$OVL/bin/$t"; chmod +x "$OVL/bin/$t"; done
"$B/dispatch" $BR --repo "$T/repo" --at "$FUT 04:10" >/dev/null; PL2=$(basename "$(pl)" .plist); : > "$T/claude.calls"
# the same environment as the run above: later cases read the newest run record
ovl_cfg; env -u DISPATCH_ASK -u DISPATCH_HELM REGATTA_CONFIG="$T/config-ovl" DISPATCH_MANAGER=mgr-x DISPATCH_PLAN=mgr-x DISPATCH_PLAN_SPACE=sp-1 DISPATCH_MANAGER_HOST=laptop DISPATCH_MANAGER_ACCOUNT=/x/.acct-c DISPATCH_LOG="$HOME/mgr2.log" DISPATCH_LABEL=$PL2 "$B/dispatch" $BR --repo "$T/repo" --headless
has "$T/claude.calls" "modules/helm/bin/ask apply" "  the real lookup: helm's bin/ask, which the allow rules name since B14a"
has "$T/claude.calls" "modules/helm/libexec/helm report --task demo" "  and helm's console for the reports"
grep -q "$OVL/bin/" "$T/claude.calls"; check "$?" "1" "  never the overlay's shims (B14a)"
# orchestration B2: what a retry needs to start the same step again, under the same manager
check "$(python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
print(d.get("depth"), d.get("manager_host"), d.get("manager_account"), d.get("brief"), len(d.get("brief_blob", "")), d.get("model"), d.get("yolo"))
print(" ".join("%s:%s" % (k, type(d.get(k)).__name__) for k in ("depth", "pid", "started", "watcher", "ended")))' "$(ls -t "$HOME/Library/Logs/claude-weekly/run-seed-runs"/*.json | head -1)" | tr '\n' '|')" \
  "1 laptop /x/.acct-c docs/handoff/2026-10-02-demo.md 40 opus 0|depth:int pid:int started:int watcher:int ended:int|" "  its depth, the manager's host and login, the brief's repo path and blob, model and yolo; the numbers as numbers (B2)"

# G22 (regatta-modules B7): helm not installed — its ask and helm leave the prompt, and a decision
# the run cannot make ends it on the WAITING line; the Steps: line stays (keel's)
"$B/dispatch" $BR --repo "$T/repo" --at "$FUT 04:10" >/dev/null; PL22=$(basename "$(pl)" .plist)
: > "$T/claude.calls"
DISPATCH_HELM= DISPATCH_LOG="$HOME/g22.log" DISPATCH_LABEL=$PL22 "$B/dispatch" $BR --repo "$T/repo" --headless >/dev/null 2>&1
grep -q "ask apply" "$T/claude.calls"; check "$?" "1" "G22, no helm: the prompt names no ask apply"
grep -q "helm report" "$T/claude.calls"; check "$?" "1" "  nor a helm report"
has "$T/claude.calls" "end on the WAITING line naming it" "  a decision it cannot make ends it on WAITING"
has "$T/claude.calls" "step <doc> <S> done --branch" "  the Steps: line stays"

echo "a plan with no manager (wharf's tick seeds a block from launchd): the run still reports to it"
"$B/dispatch" $BR --repo "$T/repo" --at "$FUT 04:10" >/dev/null; P=$(pl); PL=$(basename "$P" .plist)
: > "$T/env.calls"
DISPATCH_PLAN=wp DISPATCH_LOG="$HOME/plan.log" DISPATCH_LABEL=$PL "$B/dispatch" $BR --repo "$T/repo" --headless >/dev/null 2>&1
grep -q "^DISPATCH_PLAN=wp$" "$T/env.calls"; check "$?" "0" "the run's session has the plan"
grep -q "^DISPATCH_SHIP=wp$" "$T/env.calls"; check "$?" "0" "  under its new name too"
grep -q "^DISPATCH_TASK=demo$" "$T/env.calls"; check "$?" "0" "  and its task name, so its plan report arrives"
grep -q "^DISPATCH_MANAGER=\|^DISPATCH_SKIPPER=" "$T/env.calls"; check "$?" "1" "  and no skipper, under either name"

echo "--background allow: a headless run without the switch, to compare side by side"
"$B/dispatch" $BR --repo "$T/repo" --at "$FUT 04:10" >/dev/null; P=$(pl); PL=$(basename "$P" .plist)
: > "$T/env.calls"
CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1 DISPATCH_LOG="$HOME/allow.log" DISPATCH_LABEL=$PL "$B/dispatch" $BR --repo "$T/repo" --headless --background allow
has "$HOME/allow.log" "== exit 0" "it ran"
grep -q "^CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=" "$T/env.calls"; check "$?" "1" "  no switch, not even one the caller had (a dispatched run whose check runs this suite)"
grep -q "^BASH_DEFAULT_TIMEOUT_MS=1800000$" "$T/env.calls"; check "$?" "0" "  the same 30-minute Bash default"
has "$HOME/allow.log" "== background allow (--background)" "  the log says which, and that it was forced"
check "$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1])).get("background"))' "$(ls -t "$HOME/Library/Logs/claude-weekly/run-seed-runs"/*.json | head -1)")" "allow" "  so does the run's record"

echo "a direct run goes through launchd (an orphaned watcher, 2026-10-05)"
: > "$T/calls"; : > "$T/claude.calls"
"$B/dispatch" $BR --repo "$T/repo" --at "$FUT 04:10" >/dev/null; LATER=$(pl)
# the clock before the run too: dispatch reads it while scheduling, and the memory probe's 2 s and
# berth's sample can carry the run over a minute boundary on a loaded Mac
T0=$(date +%s)
env -u DISPATCH_LABEL "$B/dispatch" $BR --repo "$T/repo" > "$T/out" 2>&1; check "$?" "0" "a run without a launchd label…"
has "$T/out" "through launchd, in about 2 min" "  …is scheduled --next's margin out (a minute could fire at once, or never)"
has "$T/calls" "bootstrap gui/" "  as a launchd job"
check "$(wc -c < "$T/claude.calls" | tr -d ' ')" "0" "  and starts no claude in this shell"
check "$([ -f "$LATER" ] && echo kept || echo gone)" "kept" "  a pending /later job is left alone…"
has "$T/out" "left $(basename "$LATER" .plist) scheduled: a direct run replaces no /later job" "  …and named"
D=$(( $(date +%s) + 90 )); M0=$(date -r $((T0 + 90)) +%Y%m%d%H%M); M1=$(date -r $D +%Y%m%d%H%M); M2=$(date -r $((D + 60)) +%Y%m%d%H%M)
ls "$HOME"/Library/LaunchAgents/ | grep -qE "demo\.($M0|$M1|$M2)\.plist"; check "$?" "0" "  the fire minute is 90 s out or the one after"
"$B/dispatch" $BR --repo "$T/repo" --cancel >/dev/null

echo "the visible run: interactive claude with Remote Control in screen, a window, an end"
# claude: -p answers and exits; interactive writes its session record as STUB_RUN says, then waits
cat > "$T/claude" <<EOF
#!/bin/bash
env >> "$T/env.calls"; echo "claude \$*" >> "$T/claude.calls"; pwd >> "$T/claude.calls"
case " \$* " in *" -p "*) [ -n "\${STUB_HANG:-}" ] && { trap 'echo "TERM -p" >> "$T/claude.calls"; exit 143' TERM; while :; do sleep 0.2; done; }; echo ok; exit 0;; esac
sid=; prev=; for a in "\$@"; do [ "\$prev" = --session-id ] && sid=\$a; prev=\$a; done
rec="\$HOME/.claude/sessions/\$\$.json"; mkdir -p "\$HOME/.claude/sessions" "\$HOME/.claude/projects/x"
old=\$(( (\$(date +%s) - 700) * 1000 ))
trap 'echo "TERM \$\$" >> "$T/claude.calls"; echo "claude TERM \$\$" >> "$T/order"; rm -f "\$rec"; exit 0' TERM
# the worktree lock checkpoint.py would take for this session
if [ -n "\${STUB_LOCK:-}" ]; then gd=\$(git rev-parse --absolute-git-dir) && mkdir -p "\$gd/claude" && printf '{"session": "%s"}' "\$sid" > "\$gd/claude/owner.json"; fi
case "\${STUB_RUN:-work}" in
  work) printf '{"sessionId":"%s","status":"idle","statusUpdatedAt":%s}' "\$sid" \$old > "\$rec"
        echo '{"type":"assistant","message":{"content":[{"type":"text","text":"ok"}]}}' > "\$HOME/.claude/projects/x/\$sid.jsonl";;
  busy) printf '{"sessionId":"%s","status":"busy","statusUpdatedAt":%s}' "\$sid" \$old > "\$rec"
        echo '{"type":"user","message":{"content":"the brief"},"timestamp":"2026-10-15T00:00:00Z"}' > "\$HOME/.claude/projects/x/\$sid.jsonl";;
  # busy with no prompt in the transcript: stuck in its UserPromptSubmit hooks (the build Mac, 2026-10-15)
  hooked) printf '{"sessionId":"%s","status":"busy","statusUpdatedAt":%s}' "\$sid" \$old > "\$rec"
          ( exec -a "$T/stuck-hook" sleep 30 ) &;;
  # done, but holding background shells, so Claude Code says "shell" (S13): the Session-tab waiter
  # alone (listen), or the waiter and a shell still at work (shelled)
  listen|shelled)
    printf '{"sessionId":"%s","status":"shell","statusUpdatedAt":%s}' "\$sid" \$old > "\$rec"
    t="\$HOME/.claude/projects/x/\$sid.jsonl"
    echo '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"toolu_w","name":"Bash","input":{"command":"sessionpipe wait --session claude-code:'"\$sid"'","run_in_background":true}}]}}' > "\$t"
    echo '{"type":"user","toolUseResult":{"backgroundTaskId":"bw"},"message":{"content":[{"type":"tool_result","tool_use_id":"toolu_w"}]}}' >> "\$t"
    [ "\$STUB_RUN" = shelled ] && echo '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"toolu_s","name":"Bash","input":{"command":"sleep 600","run_in_background":true}}]}}' >> "\$t"
    echo '{"type":"assistant","message":{"content":[{"type":"text","text":"done"}]}}' >> "\$t";;
  # a login whose sessions/ is its own dir, not a link to ~/.claude's (an Orca profile; S13)
  profile) rec="\$CLAUDE_CONFIG_DIR/sessions/\$\$.json"; mkdir -p "\$CLAUDE_CONFIG_DIR/sessions"
           printf '{"sessionId":"%s","status":"idle","statusUpdatedAt":%s}' "\$sid" \$old > "\$rec"
           echo '{"type":"assistant","message":{"content":[{"type":"text","text":"ok"}]}}' > "\$HOME/.claude/projects/x/\$sid.jsonl";;
esac
while :; do sleep 0.2; done
EOF
cat > "$T/screen" <<EOF
#!/bin/bash
echo "screen \$*" >> "$T/screen.calls"
echo "screen \$*" >> "$T/order"
case "\$1" in
  -U) [ "\$2" = -dmS ] || exit 1; name=\$3; shift 3; [ -n "\${STUB_NOSTART:-}" ] && exit 0; "\$@" >/dev/null 2>&1 & exit 0;;
  -ls) cat "$T/screen.ls" 2>/dev/null; exit 1;;
  -wipe) [ -f "$T/screen.ls" ] && sed -i '' '/Dead/d' "$T/screen.ls"; exit 0;;
  -S) case "\$*" in *hardcopy*) for a; do f=\$a; done
                    # blind: a plain hardcopy writes an empty file, only -h returns the screen (the build Mac, 2026-10-26);
                    # gone: the first call reads the window, every later one finds no such screen and writes nothing
                    case "\${STUB_SCREEN:-}" in
                      blind) case " \$* " in *" -h "*) echo "Do you trust the files in this folder?" > "\$f";; *) : > "\$f";; esac;;
                      gone) n=\$(cat "$T/hc.n" 2>/dev/null || echo 0); echo \$((n + 1)) > "$T/hc.n"
                            if [ "\$n" = 0 ]; then echo "Choose the text style that looks best" > "\$f"; else echo "No screen session found." >&2; exit 1; fi;;
                      *) echo "Do you trust the files in this folder?" > "\$f";;
                    esac;;
                    *quit*) pkill -TERM -f "$HOME/Library/Caches/run-seed/\${2#*.}.sh" 2>/dev/null
                            # the window's own SELF_CLOSE, once its screen is gone
                            [ -n "\${STUB_SELFCLOSE:-}" ] && python3 "$T/rmwin" "$T/windows.json" "\$STUB_SELFCLOSE";; esac;;
esac
EOF
cat > "$T/open" <<EOF
#!/bin/sh
echo "open \$*" >> "$T/open.calls"
# Terminal's own title: the user name first (review of 2026-10-05: a '^run · ' match never matched)
printf '[{"id": 41, "app": "Terminal", "title": "sam — run · demo · repo — screen -x run-repo-demo — 80×24", "space": 5}]' > "$T/windows.json"
EOF
printf '[{"index": 1, "type": "float"}, {"index": 5, "type": "bsp"}]' > "$T/spaces.json"
cat > "$T/rmwin" <<'EOF'
#!/usr/bin/env python3
import json, sys
p, wid = sys.argv[1], int(sys.argv[2])
try:
    ws = json.load(open(p))
except Exception:
    ws = []
json.dump([w for w in ws if w.get("id") != wid], open(p, "w"))
EOF
cat > "$T/yabai" <<EOF
#!/bin/sh
echo "\$*" >> "$T/yabai.calls"
echo "yabai \$*" >> "$T/order"
[ -n "\${YABAI_OFF:-}" ] && [ "\$2" != query ] && { echo "yabai-msg: failed to connect to socket.." >&2; exit 1; }
case "\$2 \$4" in "window --close") [ -n "\${YABAI_STUCK:-}" ] || python3 "$T/rmwin" "$T/windows.json" "\$3";; esac
# STUB_RETITLE=<id>:<pid>: once claude <pid> got SIGTERM, window <id> shows its shell, as a real one does
if [ -n "\${STUB_RETITLE:-}" ] && grep -q "claude TERM \${STUB_RETITLE#*:}" "$T/order" 2>/dev/null; then
  python3 "$T/retitle" "$T/windows.json" "\${STUB_RETITLE%%:*}"
fi
case "\$2 \$3" in "query --windows") cat "$T/windows.json" 2>/dev/null || echo '[]';; "query --spaces") cat "$T/spaces.json";; esac
EOF
cat > "$T/retitle" <<'EOF'
#!/usr/bin/env python3
import json, sys
p, wid = sys.argv[1], int(sys.argv[2])
ws = json.load(open(p))
for w in ws:
    if w.get("id") == wid and " — claude" in w.get("title", ""):
        # what a pickup window read once its claude exited, in the first live tidy (2026-10-08):
        # Claude Code's "✳ <name>" title goes with it
        w["title"] = w["title"].split(" — ")[0] + " — 120×30"
json.dump(ws, open(p, "w"))
EOF
chmod +x "$T/claude" "$T/screen" "$T/open" "$T/yabai" "$T/rmwin"
# DISPATCH_IDLE: the default is the prompt cache's hour since 2026-10-06 (D1), and the stub records
# below are idle 700 s — the cases here keep the old 10 min so they still end their run; the default
# itself and the hour's effect are their own cases ("the warm hour", "sweep" below)
export DISPATCH_SCREEN="$T/screen" DISPATCH_OPEN="$T/open" DISPATCH_YABAI="$T/yabai" DISPATCH_POLL=0.2 DISPATCH_START_WAIT=2 DISPATCH_IDLE=600 DISPATCH_CLOSE_WAIT=0.2
RUNS="$HOME/Library/Logs/claude-weekly/run-seed-runs"
latest() { ls -t "$RUNS"/*.json | head -1; }
field() { python3 -c 'import json, sys; print(json.load(open(sys.argv[1])).get(sys.argv[2], ""))' "$(latest)" "$1"; }
# A background run's claude stub is ready a moment after the run starts, and under load that moment
# is not 3 s (2026-10-10: the pid was missing, kill missed, `wait` hung for 2 h). Wait for the
# readiness itself — this run's stub alive with its session record written — on a clock deadline,
# and on a miss reap the run so no `wait` can block. A fixed sleep stays only where it is the test's
# own subject (the watcher's start window), never as a readiness guess.
await_stub() {  # await_stub <status>: prints the latest run's claude pid once alive with its record; 1 after 30 s
  local p sid end=$((SECONDS + 30))
  while [ "$SECONDS" -lt "$end" ]; do
    p=$(field pid 2>/dev/null); sid=$(field session 2>/dev/null)
    # the record names this run's session: a reused pid from an older record never matches
    [ -n "$p" ] && [ -n "$sid" ] && kill -0 "$p" 2>/dev/null \
      && grep -q "\"sessionId\":\"$sid\",\"status\":\"$1\"" "$HOME/.claude/sessions/$p.json" 2>/dev/null \
      && { echo "$p"; return 0; }
    sleep 0.2
  done
  return 1
}
reap_run() {    # reap_run <dispatch pid> [claude pid]: end a background run, its watcher and its stub
  local rs=$1 cp=${2:-}
  [ -n "$cp" ] && kill -TERM "$cp" 2>/dev/null
  # the stub (screen started it, not the run), the runner script and the watcher all name this
  # test's temp dir in their argv; nothing outside it does
  pkill -TERM -f "$T/" 2>/dev/null
  pkill -TERM -P "$rs" 2>/dev/null
  kill -TERM "$rs" 2>/dev/null; sleep 1; kill -KILL "$rs" 2>/dev/null
  return 0
}
# dead_ <pid>: back once the process is gone, or after 2.5 s — the poll that replaced a flat
# `sleep 0.5` before each "its claude ended" check: a TERM'd stub leaves within a tenth or two of a
# second, and on a loaded Mac 0.5 s was a guess either way. The check after it still decides.
dead_() { local i; for i in $(seq 1 25); do kill -0 "$1" 2>/dev/null || return 0; sleep 0.1; done; return 1; }
wait_run() {    # wait_run <dispatch pid> [claude pid] [secs]: wait for the run to end, else reap it (and FAIL)
  local rs=$1 end=$((SECONDS + ${3:-30}))
  while [ "$SECONDS" -lt "$end" ]; do kill -0 "$rs" 2>/dev/null || { wait "$rs"; return 0; }; sleep 0.2; done
  reap_run "$rs" "${2:-}"; wait "$rs" 2>/dev/null; check "hung" "ended" "  the run ended within ${3:-30} s"
}
: > "$T/claude.calls"; : > "$T/env.calls"
STUB_RUN=work STUB_LOCK=1 DISPATCH_HOST=laptop CLAUDE_CODE_CHILD_SESSION=1 CLAUDE_CONFIG_DIR="$HOME/.claude-pro" CLAUDE_CODE_OAUTH_TOKEN=tok \
  YABAI_OFF=1 DISPATCH_LOG="$HOME/rc.log" DISPATCH_LABEL=$PL "$B/dispatch" $BR --repo "$T/repo" --note "build only"
SID=$(field session)
# B2 on run_rc's own record call: the chain fields. The types here prove less than they say: watch()
# has already rewritten the record through typed(); the headless case above is what guards record()
check "$(python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
print(d.get("mode"), d.get("brief"), " ".join("%s:%s" % (k, type(d.get(k)).__name__) for k in ("depth", "pid", "started", "watcher", "screen_pid")))' "$(ls -t "$HOME/Library/Logs/claude-weekly/run-seed-runs"/*.json | head -1)")" \
  "rc docs/handoff/2026-10-02-demo.md depth:int pid:int started:int watcher:int screen_pid:int" "  the rc record carries the chain fields, numbers typed by the time anyone reads it (B2)"
has "$T/claude.calls" "claude You are an unattended session" "interactive, the prompt first (the tool lists take every word after them)"
grep -q -- " -p " "$T/claude.calls"; check "$?" "1" "  no -p"
has "$T/claude.calls" "--remote-control demo · laptop" "Remote Control named <topic> · <machine>"
has "$T/claude.calls" "--session-id $SID" "the session id is dispatch's, recorded in the run's state"
has "$T/claude.calls" "--model opus --effort high --permission-mode auto" "same tier and mode"
has "$T/claude.calls" "Bash(*bin/pr merge*)" "same disallowed tools"
has "$T/claude.calls" "$T/repo/.claude/worktrees/demo" "  in the branch's worktree"
has "$T/screen.calls" "screen -U -dmS run-repo-demo /bin/bash" "started in a detached screen named run-<repo>-<topic>"
has "$HOME/Library/Caches/run-seed/run-repo-demo.sh" "run-repo-demo.$SID.pid" "  its pid file is the run's own (repo, topic, session)"
field proc_start | grep -qE '^[A-Z][a-z]{2} [A-Z][a-z]{2} +[0-9]+ [0-9:]{8} [0-9]{4}$'; check "$?" "0" "  the start time of its claude recorded (proc_start, ps lstart)"
grep -q "^CLAUDE_UNATTENDED=dispatch$" "$T/env.calls"; check "$?" "0" "CLAUDE_UNATTENDED reaches the session"
grep -q "^CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1$" "$T/env.calls"; check "$?" "0" "  the background switch too: foreground is the default in both modes (the owner, 2026-10-05)"
has "$HOME/rc.log" "== background deny (default for rc)" "  and the log says so"
grep -q "^BASH_DEFAULT_TIMEOUT_MS=1800000$" "$T/env.calls"; check "$?" "0" "  the 30-minute Bash default, which the prompt states"
grep -q "^DISPATCH_BRIEF=$BLOB$" "$T/env.calls"; check "$?" "0" "  so do DISPATCH_BRIEF…"
grep -q "^DISPATCH_DEPTH=1$" "$T/env.calls"; check "$?" "0" "  …and DISPATCH_DEPTH"
grep -q "^CLAUDE_CODE_CHILD_SESSION=" "$T/env.calls"; check "$?" "1" "  a calling session's CLAUDE_CODE_* does not (it turns transcripts off)"
grep -q "^CLAUDE_CONFIG_DIR=$HOME/.claude-pro$" "$T/env.calls"; check "$?" "0" "  but CLAUDE_CONFIG_DIR does: it names the account"
grep -q "^CLAUDE_CODE_OAUTH_TOKEN=tok$" "$T/env.calls"; check "$?" "0" "  and CLAUDE_CODE_OAUTH_TOKEN"
grep -q "^DISPATCH_LABEL=" "$T/env.calls"; check "$?" "1" "  nor the plist's"
has "$T/open.calls" "-a Terminal $HOME/Library/Caches/run-seed/run-repo-demo.command" "a Terminal window opened (laptop)"
has "$HOME/Library/Caches/run-seed/run-repo-demo.command" "run · demo · repo" "  titled run · <topic> · <repo>"
grep -qE -- "-x [0-9]+\.run-repo-demo$" "$HOME/Library/Caches/run-seed/run-repo-demo.command"; check "$?" "0" "  attached to the run's screen, by <pid>.<name>"
check "$(wc -l < "$T/open.calls" | tr -d ' ')" "1" "  one open: no bare open -a Terminal first (it switched nothing from launchd, D2)"
has "$T/open.calls" "open -g -a Terminal" "  in the background: Terminal never activated, no desktop switch (the owner, 2026-10-07)"
has "$HOME/Library/Caches/run-seed/run-repo-demo.command" "every window whose visible is true and tty of selected tab" "  the window closes itself when its screen session ends"
CMDF="$HOME/Library/Caches/run-seed/run-repo-demo.command"
check "$([ "$(grep -n "every window whose visible" "$CMDF" | cut -d: -f1)" -lt "$(grep -n '^exec ' "$CMDF" | cut -d: -f1)" ] && tail -1 "$CMDF" | cut -c1-5)" "exec " \
  "    the closer starts first, then screen -x is exec'd: the tab holds only screen, which Terminal closes without a sheet (review 2026-10-08)"
bash -n "$CMDF"; check "$?" "0" "    the .command parses"
python3 -c 'import sys, re; src = open(sys.argv[1]).read(); code = re.search(r"python3 -c (\x27)(.*?)\1", src, re.S).group(2); compile(code, "closer", "exec")' "$CMDF"; check "$?" "0" "    and so does its closer"
has "$CMDF" "and name contains" "    the closer matches the title too, never a tty alone (Terminal reuses ttys)"
has "$HOME/rc.log" "tiled on space 5" "  found on the tiled desktop"
has "$T/yabai.calls" "-m space 5 --balance" "  the tiles evened out"
has "$HOME/rc.log" "yabai space 5: yabai-msg: failed to connect" "  yabai's stderr in the log"
check "$([ "$(grep -c 'failed to connect' "$HOME/rc.log")" -le 2 ] && echo few || echo many)" "few" "  once per process (window, watcher), not per call"
has "$HOME/rc.log" "ended session $SID (idle 11 min)" "idle 10 min after busy: ended, session id logged"
has "$T/claude.calls" "TERM" "  the claude process got SIGTERM"
grep -qE -- "-S [0-9]+\.run-repo-demo -X quit" "$T/screen.calls"; check "$?" "0" "  the screen quit, by <pid>.<name> (a later run's screen has the same name)"
check "$([ -f "$(git -C "$T/repo/.claude/worktrees/demo" rev-parse --absolute-git-dir)/claude/owner.json" ] && echo kept || echo gone)" "gone" "  the run's worktree lock freed"
has "$T/yabai.calls" "-m window 41 --close" "  the window closed"
wclose=$(grep -n -- "--close" "$T/order" | head -1 | cut -d: -f1)
squit=$(grep -n -- "-X quit" "$T/order" | head -1 | cut -d: -f1)
check "$([ -n "$wclose" ] && [ -n "$squit" ] && [ "$wclose" -lt "$squit" ] && echo before || echo after)" "before" \
  "  and before the screen quit: once the shell has exited Terminal keeps the window and the close fails (window 16350, 2026-10-05)"
has "$HOME/rc.log" "would not close" "  a close yabai refuses says a sheet is holding it, and which window"
check "$(field end_reason)" "idle 11 min" "  the end in the run's state"
"$B/dispatch" --status > "$T/out"
has "$T/out" "vscode://anthropic.claude-code/open?session=$SID" "--status: the VS Code link"
has "$T/out" "ended" "  ended"
has "$T/out" "background deny" "  and which background setting it ran with"
has "$T/out" "last activity" "  last activity"

: > "$T/open.calls"; : > "$T/claude.calls"
LOCK="$(git -C "$T/repo/.claude/worktrees/demo" rev-parse --absolute-git-dir)/claude/owner.json"
printf '{"session": "someone-else"}' > "$LOCK"
STUB_RUN=busy DISPATCH_HOST=buildbox DISPATCH_LOG="$HOME/busy.log" "$B/dispatch" $BR --repo "$T/repo" &
RS=$!
CP=$(await_stub busy); check "$?" "0" "the busy run's claude started"
sleep 3   # the subject: past DISPATCH_START_WAIT (2 s) and its polls, the watcher must still leave it alone
kill -0 "$CP" 2>/dev/null; check "$?" "0" "a busy session is never ended, however old its status"
"$B/dispatch" --status > "$T/out"
has "$T/out" "running (busy)" "  --status: running"
has "$T/out" "attach: SCREENDIR=" "  with the attach line"
check "$(wc -c < "$T/open.calls" | tr -d ' ')" "0" "the build Mac: no window"
[ -n "$CP" ] && kill -TERM "$CP" 2>/dev/null
wait_run "$RS" "$CP"
check "$(field end_reason)" "claude exited by itself" "a session that exits is recorded as such"
check "$([ -f "$LOCK" ] && echo kept || echo gone)" "kept" "  another session's worktree lock is left alone"
rm -f "$LOCK"

printf '\t4242.run-repo-demo\t(Detached)\n' > "$T/screen.ls"
DISPATCH_HOST=buildbox DISPATCH_LOG="$HOME/twice.log" "$B/dispatch" $BR --repo "$T/repo"
has "$HOME/twice.log" "FAILED: a run of demo in repo is still going" "a second run of a live topic is refused"
check "$([ -d "$HOME/Library/Caches/run-seed/start.lock" ] && echo held || echo free)" "free" "  and the start lock is released"
printf '\t4242.run-repo-demo\t(Dead ???)\n' > "$T/screen.ls"
mkdir -p "$HOME/Library/Caches/run-seed/start.lock"; touch -t 202001010000 "$HOME/Library/Caches/run-seed/start.lock"
STUB_RUN=work DISPATCH_HOST=buildbox DISPATCH_LOG="$HOME/dead.log" "$B/dispatch" $BR --repo "$T/repo"
has "$T/screen.calls" "screen -wipe" "a dead socket is wiped first"
has "$HOME/dead.log" "ended session" "  and never blocks a new run; a start lock left by a crash is taken over"
# a dead pid: a `sleep &` killed at once can take the SIGTERM before it execs, still holding this
# shell's EXIT trap, and run it — rm -rf "$T" (seen 2026-10-05)
HOLD=$(sh -c 'echo $$')
mkdir -p "$HOME/Library/Caches/run-seed/start.lock"; echo $HOLD > "$HOME/Library/Caches/run-seed/start.lock/pid"
STUB_RUN=work DISPATCH_HOST=buildbox DISPATCH_LOG="$HOME/dead2.log" "$B/dispatch" $BR --repo "$T/repo"
has "$HOME/dead2.log" "ended session" "a start lock whose holder is dead is taken over at once"
: > "$T/env.calls"
STUB_RUN=work DISPATCH_HOST=buildbox DISPATCH_LOG="$HOME/allow-rc.log" "$B/dispatch" $BR --repo "$T/repo" --background allow
grep -q "^CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=" "$T/env.calls"; check "$?" "1" "--background allow lifts the switch on a visible run"
has "$HOME/allow-rc.log" "== background allow (--background)" "  and the log says so"
check "$(field background)" "allow" "  and the run's record"
: > "$T/screen.calls"
STUB_NOSTART=1 DISPATCH_HOST=buildbox DISPATCH_LOG="$HOME/nostart.log" "$B/dispatch" $BR --repo "$T/repo"
has "$HOME/nostart.log" "started no claude" "a screen that starts no claude: FAILED…"
has "$T/screen.calls" "-S run-repo-demo -X quit" "  …and that screen is quit, not left behind"
check "$([ -d "$HOME/Library/Caches/run-seed/start.lock" ] && echo held || echo free)" "free" "  the start lock released"
rm -f "$T/screen.ls"

: > "$T/claude.calls"
STUB_RUN=silent DISPATCH_HOST=buildbox DISPATCH_LOG="$HOME/silent.log" "$B/dispatch" $BR --repo "$T/repo"
has "$HOME/silent.log" "FAILED: never busy" "never busy within the start wait: ended and said so"
has "$HOME/silent.log" "Do you trust the files" "  with what its screen showed"
has "$HOME/silent.log" "never started interactively — retrying once, visible again" "  then retried once, visible (never headless, 2026-10-13)"
has "$HOME/silent.log" "FAILED: never started interactively, twice" "  then FAILED"
check "$(grep -c -- ' -p ' "$T/claude.calls")" "0" "  never as claude -p"

# the screen read (orca-launcher S7): a never-started run's last screen reaches its log, three ways
: > "$T/claude.calls"
STUB_SCREEN=blind STUB_RUN=silent DISPATCH_HOST=buildbox DISPATCH_LOG="$T/blind.log" "$B/dispatch" $BR --repo "$T/repo"
has "$T/blind.log" "Do you trust the files" "a plain hardcopy that writes an empty file: the -h read still shows the screen"
grep -q "no screen contents" "$T/blind.log"; check "$?" "1" "  never the blind line"
has "$T/screen.calls" "hardcopy -h " "  asked with -h first"
rm -f "$T/hc.n"
DISPATCH_SNAP_EVERY=0.5 STUB_SCREEN=gone STUB_RUN=silent DISPATCH_HOST=buildbox DISPATCH_LOG="$T/gone.log" "$B/dispatch" $BR --repo "$T/repo"
has "$T/gone.log" "no screen now — screen exited 1: No screen session found.; its last screen" "a window that closed before the end: the last screen it showed, and why the read failed"
has "$T/gone.log" "Choose the text style that looks best" "  the screen the rolling snapshot kept"
has "$T/gone.log" "(no screen contents: screen exited 1: No screen session found.)" "  and a run that never showed one says why, not a bare blank"

: > "$T/claude.calls"
STUB_RUN=hooked DISPATCH_HOST=buildbox DISPATCH_LOG="$HOME/hooked.log" "$B/dispatch" $BR --repo "$T/repo"
has "$HOME/hooked.log" "FAILED: never busy" "busy with no prompt in its transcript (stuck in its hooks): never started, not a live run"
has "$HOME/hooked.log" "processes under claude:" "  the log lists the processes under claude…"
has "$HOME/hooked.log" " stuck-hook" "  …the stuck hook among them, by base name only (no paths or flags in a log a PR comment may quote)"
grep -q "$T/stuck-hook" "$HOME/hooked.log"; check "$?" "1" "  …and never its full path"
has "$HOME/hooked.log" "FAILED: never started interactively, twice" "  retried once, then FAILED — the run cap freed in minutes, not DISPATCH_MAX_H"
check "$(field end_reason)" "never started" "  its record ended as never started: the slot is free"
pkill -f "$T/stuck-hook" 2>/dev/null

STUB_RUN=busy DISPATCH_MAX_H=0.001 DISPATCH_HOST=buildbox DISPATCH_LOG="$HOME/maxh.log" "$B/dispatch" $BR --repo "$T/repo"
has "$HOME/maxh.log" "still not idle after 0.0 h (DISPATCH_MAX_H)" "a session never idle is ended at DISPATCH_MAX_H"
check "$(field end_reason)" "max lifetime 0.0 h" "  recorded"

: > "$T/claude.calls"
STUB_HANG=1 DISPATCH_MAX_H=0.0005 DISPATCH_LOG="$HOME/maxh2.log" "$B/dispatch" $BR --repo "$T/repo" --headless
has "$HOME/maxh2.log" "still running after 0.0005 h (DISPATCH_MAX_H)" "  a headless one too"
has "$T/claude.calls" "TERM -p" "  its claude -p got SIGTERM"

echo "a finished run that reads shell or sits in another login's registry is ended (S13)"
STUB_RUN=listen DISPATCH_HOST=buildbox DISPATCH_LOG="$HOME/listen.log" "$B/dispatch" $BR --repo "$T/repo" &
RS=$!; wait_run "$RS" "" 30
check "$(field end_reason)" "idle 11 min" "a shell whose only open task is sessionpipe wait is ended after the idle window"
STUB_RUN=shelled DISPATCH_HOST=buildbox DISPATCH_LOG="$HOME/shelled.log" "$B/dispatch" $BR --repo "$T/repo" &
RS=$!
CP=$(await_stub shell); check "$?" "0" "  the shelled run's claude started"
sleep 3   # the subject: past DISPATCH_START_WAIT and its polls, with the record idle-old, it must stay
kill -0 "$CP" 2>/dev/null; check "$?" "0" "  a shell with another background shell open is not ended"
check "$(field ended)" "" "  nor recorded ended"
[ -n "$CP" ] && kill -TERM "$CP" 2>/dev/null
wait_run "$RS" "$CP"
mkdir -p "$HOME/.claude-orca/sessions"
STUB_RUN=profile CLAUDE_CONFIG_DIR="$HOME/.claude-orca" DISPATCH_HOST=buildbox DISPATCH_LOG="$HOME/profile.log" "$B/dispatch" $BR --repo "$T/repo" &
RS=$!; wait_run "$RS" "" 30
check "$(field config_dir)" "$HOME/.claude-orca" "  the rc record names the run's config dir"
check "$(field end_reason)" "idle 11 min" "a run whose login keeps its own sessions/ is found there and ended idle"
rm -rf "$HOME/.claude-orca"   # later cases glob ~/.claude*
python3 - "$B/dispatch-rc" "$HOME" <<'PY' > "$T/out"
import importlib.machinery, importlib.util, json, os, sys
loader = importlib.machinery.SourceFileLoader("drc", sys.argv[1])
m = importlib.util.module_from_spec(importlib.util.spec_from_loader("drc", loader)); loader.exec_module(m)
home = sys.argv[2]
def run(sid, lines):
    with open(os.path.join(home, ".claude", "projects", "x", sid + ".jsonl"), "w") as f:
        for l in lines:
            f.write(json.dumps(l, separators=(",", ":")) + "\n")
    return m.listening_only(sid, since)
since = 1792700000000   # the record's statusUpdatedAt, ms
at = lambda d, ms: dict(d, timestamp=__import__("datetime").datetime.fromtimestamp(ms / 1000, __import__("datetime").timezone.utc).isoformat().replace("+00:00", "Z"))
use = lambda i, cmd, name="Bash": {"type": "assistant", "message": {"content": [{"type": "tool_use", "id": i, "name": name, "input": {"command": cmd, "run_in_background": True}}]}}
note = lambda i: {"type": "queue-operation", "operation": "enqueue", "content": "<task-notification>\n<task-id>b</task-id>\n<tool-use-id>%s</tool-use-id>\n<status>completed</status>" % i}
print("ended", run("u1", [use("t1", "sleep 9"), at(note("t1"), since - 60000), use("t2", "sessionpipe wait --session c:x")]))
print("fresh", run("u1b", [use("t1", "sleep 9"), at(note("t1"), since + 60000), use("t2", "sessionpipe wait --session c:x")]))
print("ask", run("u6", [use("t1", "/x/helm/bin/ask listen")]))
moved = {"type": "user", "toolUseResult": {"backgroundTaskId": "bm", "timedOutAfterMs": 120000}, "message": {"content": [{"type": "tool_result", "tool_use_id": "t2"}]}}
fg = {"type": "assistant", "message": {"content": [{"type": "tool_use", "id": "t2", "name": "Bash", "input": {"command": "bash tests/check.sh"}}]}}
print("moved", run("u7", [use("t1", "sessionpipe wait --session c:x"), fg, moved]))
print("odd", run("u8", [use("t1", "sessionpipe wait --session c:x"), {"type": "system", "message": "x", "data": {"run_in_background": True}}, {"type": "assistant", "message": {"content": ["run_in_background", 1]}, "x": {"run_in_background": True}}]))
rec = {"pid": 1, "session": None}
os.makedirs(os.path.join(home, ".claude", "sessions"), exist_ok=True)
with open(os.path.join(home, ".claude", "sessions", "1.json"), "w") as f:
    json.dump({"pid": 1, "status": "shell"}, f)
print("noid", m.session_record(rec) is not None)
print("agent", run("u2", [use("t1", "sessionpipe wait --session c:x"), use("t2", None, "Agent")]))
print("chain", run("u3", [use("t1", "sessionpipe wait --session c:x; make")]))
print("talk", run("u4", [use("t1", "spacesheep talk listen --session x --once")]))
print("none", run("u5", [{"type": "assistant", "message": {"content": [{"type": "text", "text": "hi"}]}}]))
print("gone", m.listening_only("no-such-session"))
PY
has "$T/out" "ended True" "  a shell whose task-notification came before the status is no longer open"
has "$T/out" "fresh False" "  a task that ended after the status: work about to start, busy"
has "$T/out" "ask False" "  ask listen waits on a manager's answer: busy"
has "$T/out" "moved False" "  a call moved to the background at its timeout: busy"
has "$T/out" "odd True" "  odd transcript shapes are skipped, not raised"
has "$T/out" "noid True" "  a record with no session id is returned, not raised"
has "$T/out" "agent False" "  a background agent beside the waiter: busy"
has "$T/out" "chain False" "  a listener chained to another command: busy"
has "$T/out" "talk True" "  spacesheep talk listen is a listener"
has "$T/out" "none False" "  shell with no open task found: busy (the safe side)"
has "$T/out" "gone False" "  no transcript: busy"

echo "--probe takes the visible path"
: > "$T/claude.calls"; : > "$T/screen.calls"
STUB_RUN=work DISPATCH_HOST=buildbox DISPATCH_LOG="$HOME/probe.log" "$B/dispatch" $BR --repo "$T/repo" --probe
has "$T/claude.calls" "claude reply with the single word ok --session-id" "interactive, the probe prompt"
has "$T/claude.calls" "--remote-control demo-probe · buildbox" "  with Remote Control"
has "$T/screen.calls" "-dmS run-repo-demo-probe" "  in a screen of its own"
has "$HOME/probe.log" "probe answered: ok" "  the answer logged"
has "$HOME/probe.log" "ended session" "  ended by the watcher once idle"

# a stand-in for bin/trust-projects: trusts $T/repo in the config it would write (CLAUDE_CONFIG_DIR's or ~'s)
cat > "$T/trust" <<EOF
#!/bin/sh
f="\${CLAUDE_CONFIG_DIR:-\$HOME}/.claude.json"; echo "trust \$f" >> "$T/trust.calls"
printf '{"projects": {"%s": {"hasTrustDialogAccepted": true}}}' "$T/repo" > "\$f"
EOF
chmod +x "$T/trust"
printf '{"projects": {"%s": {"hasTrustDialogAccepted": false}}}' "$T/repo" > "$HOME/.claude.json"
: > "$T/claude.calls"
DISPATCH_TRUST="$T/trust" STUB_RUN=work DISPATCH_HOST=buildbox DISPATCH_LOG="$HOME/untrusted.log" "$B/dispatch" $BR --repo "$T/repo"
has "$HOME/untrusted.log" "not trusted: $T/repo — trusting it" "an untrusted repo is trusted first, not run headless (2026-10-13)"
has "$T/claude.calls" "--remote-control" "  then runs visible"
check "$(grep -c -- ' -p ' "$T/claude.calls")" "0" "  never as claude -p"
printf '{"projects": {"%s": {"hasTrustDialogAccepted": false}}}' "$T/repo" > "$HOME/.claude.json"
: > "$T/claude.calls"
DISPATCH_TRUST=true DISPATCH_HOST=buildbox DISPATCH_LOG="$HOME/untrusted2.log" "$B/dispatch" $BR --repo "$T/repo"
has "$HOME/untrusted2.log" "FAILED: $T/repo is still not trusted" "  a trust that does not take: FAILED"
check "$(wc -l < "$T/claude.calls" | tr -d ' ')" "0" "  and nothing run"
rm "$HOME/.claude.json"

echo "arrange: yabai's bsp tiles; arrange only evens out the tiled desktop the runs are on"
: > "$T/yabai.calls"
printf '[%s]' '{"id": 54, "app": "Terminal", "title": "run · d", "space": 5},
 {"id": 60, "app": "Terminal", "title": "run · e", "space": 2},
 {"id": 70, "app": "Terminal", "title": "zsh", "space": 3},
 {"id": 71, "app": "Code", "title": "run · in an editor tab", "space": 3}' > "$T/windows.json"
printf '[{"index": 2, "type": "float"}, {"index": 3, "type": "bsp"}, {"index": 5, "type": "bsp"}]' > "$T/spaces.json"
python3 "$B/dispatch-rc" arrange
check "$(grep -- '--balance' "$T/yabai.calls" | tr '\n' ' ')" "-m space 5 --balance " "  only space 5: a run window there, and it tiles"
printf '[{"index": 1, "type": "float"}, {"index": 5, "type": "bsp"}]' > "$T/spaces.json"
printf '[{"id": 41, "app": "Terminal", "title": "sam — run · demo · repo — screen -x run-repo-demo — 80×24", "space": 1}]' > "$T/windows.json"
R=$(python3 -c '
import importlib.machinery as m, importlib.util as u, sys
l = m.SourceFileLoader("r", sys.argv[1]); r = u.module_from_spec(u.spec_from_loader("r", l)); l.exec_module(r)
print(sorted(r.tiled_spaces()), [sp for _, _, sp in r.run_windows()])' "$B/dispatch-rc")
check "$R" "[5] [1]" "  a run window on a floating desktop is seen there (window() logs it)"

echo "cancel"
"$B/dispatch" $BR --repo "$T/repo" --at "$FUT 04:10" >/dev/null
"$B/dispatch" $BR --repo "$T/repo" --cancel >/dev/null
check "$(pl | wc -l | tr -d ' ')" "0" "cancel removes the plist"
"$B/dispatch" $BR --repo "$HOME/projects/other" --on buildbox --cancel >/dev/null
has "$T/ssh.calls" "--cancel" "cancel travels to the peer"

echo "scheduling from inside a running job (model gate S3, 2026-10-04: one label, it booted itself out, exit 137)"
"$B/dispatch" $BR --repo "$T/repo" --at "$FUT 04:10" >/dev/null
OWN=$(pl); OWNL=$(basename "$OWN" .plist); touch "$T/running.$OWNL"; : > "$T/calls"
"$B/dispatch" $BR --repo "$T/repo" --at "@$EP" > "$T/out" 2>&1; check "$?" "0" "the run schedules its successor"
grep -q "bootout gui/[0-9]*/$OWNL$" "$T/calls"; check "$?" "1" "  and never boots out its own job"
check "$(pl | wc -l | tr -d ' ')" "2" "  the successor is a job of its own"
has "$T/out" "left $OWNL: its run is going" "  the running job named as left alone"
: > "$T/calls"; "$B/dispatch" $BR --repo "$T/repo" --cancel > "$T/out" 2>&1
grep -q "bootout gui/[0-9]*/$OWNL$" "$T/calls"; check "$?" "1" "--cancel from inside the run spares its job too"
check "$(pl)" "$OWN" "  and removes the pending one"
"$B/dispatch" $BR --repo "$T/repo" --at "@$EP" >/dev/null 2>&1; NEXTP=$(pl | grep -v "$OWNL")
: > "$T/calls"; DISPATCH_LOG="$HOME/own.log" DISPATCH_LABEL=$OWNL "$B/dispatch" $BR --repo "$T/repo" --headless
check "$([ -f "$OWN" ] && echo present || echo gone)" "gone" "the run's end removes its own job"
check "$([ -f "$NEXTP" ] && echo present || echo gone)" "present" "  and not the successor it scheduled"
grep -q "bootout gui/[0-9]*/$(basename "$NEXTP" .plist)$" "$T/calls"; check "$?" "1" "  nor boots it out"
rm "$T/running.$OWNL"; "$B/dispatch" $BR --repo "$T/repo" --cancel >/dev/null
check "$(pl | wc -l | tr -d ' ')" "0" "a job that is not running (pending, or left by a dead run) is cleared"

echo "a run that fires while the one that scheduled it is alive waits for it"
: > "$T/claude.calls"
STUB_RUN=work DISPATCH_IDLE=100000 DISPATCH_HOST=buildbox DISPATCH_LOG="$HOME/first.log" "$B/dispatch" $BR --repo "$T/repo" &
FP=$!; for _ in $(seq 1 150); do grep -q "== claude" "$HOME/first.log" 2>/dev/null && break; sleep 0.2; done
FIRST=$(latest)
DISPATCH_PREV_WAIT=30 DISPATCH_LOG="$HOME/second.log" "$B/dispatch" $BR --repo "$T/repo" --headless
wait_run "$FP" "" 180   # the first run ends about a minute after the second
has "$HOME/second.log" "waiting for the run of demo" "the second run waited, and said so"
has "$HOME/second.log" "the run before this one has ended (" "  then started, saying why it counts as gone"
has "$HOME/second.log" "== exit 0" "  and ran"
has "$HOME/first.log" "the next run waiting" "the first, idle, ended after 1 min (not 10) once the next waited"
check "$(grep -c 'claude -p You are' "$T/claude.calls")" "1" "  one session of each, never two at once in the worktree"
sleep 30 & LP=$!
printf '{"mode":"headless","repo":"%s","topic":"demo","pid":"%s","session":"prev","started":"%s"}' "$T/repo" $LP "$(date +%s)" > "$RUNS/00000000-000000-repo.demo.json"
: > "$T/claude.calls"
DISPATCH_PREV_WAIT=1 DISPATCH_LOG="$HOME/stuck.log" "$B/dispatch" $BR --repo "$T/repo" --headless
kill $LP 2>/dev/null; wait $LP 2>/dev/null
has "$HOME/stuck.log" "FAILED: the run of demo before this one is still going" "an earlier run that does not end: FAILED, said so"
check "$(wc -c < "$T/claude.calls" | tr -d ' ')" "0" "  and no second session"
rm -f "$RUNS/00000000-000000-repo.demo.json"

echo "identity, orphans, --end, the run cap"
# a pid alive but started at another time is not the run's: a pid reused after a crash
sleep 60 & SP=$!
printf '{"mode":"rc","repo":"%s","topic":"reused","pid":%s,"proc_start":"Thu Jan  1 00:00:00 2020","session":"r","started":%s,"screen":"run-repo-reused","screendir":"%s"}' \
  "$T/repo" $SP "$(date +%s)" "$HOME" > "$RUNS/00000000-000001-repo.reused.json"
"$B/dispatch" --end reused --repo "$T/repo" > "$T/out" 2>&1; check "$?" "1" "--end on a pid reused by another process: no live run"
kill -0 $SP 2>/dev/null; check "$?" "0" "  and that process is never signalled"
"$B/dispatch" --status > "$T/out"; has "$T/out" "gone (no end recorded)" "  --status: gone, not running"
kill $SP 2>/dev/null; wait $SP 2>/dev/null
# an orphan: claude idle, its watcher gone (the shell that ran dispatch ended)
orphan() {  # TOPIC SESSION: a stub claude, idle 700 s, with a dead watcher
  (cd "$T/repo" && STUB_RUN=work exec "$T/claude" x --session-id "$2") >/dev/null 2>&1 & local cp=$!
  sleep 0.5; true & local wp=$!; wait $wp
  printf '{"mode":"rc","repo":"%s","topic":"%s","pid":%s,"proc_start":"%s","session":"%s","started":%s,"screen":"run-repo-%s","screendir":"%s","watcher":%s,"watcher_start":"Thu Jan  1 00:00:00 2020"}' \
    "$T/repo" "$1" $cp "$(pst $cp)" "$2" "$(date +%s)" "$1" "$HOME" $wp > "$RUNS/00000000-00000$3-repo.$1.json"
  echo $cp
}
OP=$(orphan lost sess-lost 2)
"$B/dispatch" --status > "$T/out"
has "$T/out" "ended" "--status: an idle orphan…"
grep -q '"end_reason": "orphaned: its watcher was gone' "$RUNS/00000000-000002-repo.lost.json"; check "$?" "0" "  …is ended, and says why"
dead_ $OP; kill -0 $OP 2>/dev/null; check "$?" "1" "  its claude got SIGTERM"
# --end: busy or not, a person asked
EP2=$(orphan endme sess-endme 3)
python3 - "$RUNS/00000000-000003-repo.endme.json" <<'PY'
import json, os, sys
p = sys.argv[1]; s = json.load(open(p)); s.pop("watcher"); json.dump(s, open(p, "w"))   # watched: no orphan
PY
"$B/dispatch" --end endme > "$T/out" 2>&1; check "$?" "0" "--end ends a live run"
grep -q '"end_reason": "ended by dispatch --end' "$RUNS/00000000-000003-repo.endme.json"; check "$?" "0" "  recorded as such"
dead_ $EP2; kill -0 $EP2 2>/dev/null; check "$?" "1" "  its claude ended"
# a watched run: the watcher sees claude go first, and keeps --end's reason
STUB_RUN=busy DISPATCH_HOST=buildbox DISPATCH_LOG="$HOME/end.log" "$B/dispatch" $BR --repo "$T/repo" &
RS=$!; for _ in $(seq 1 150); do grep -q "== claude" "$HOME/end.log" 2>/dev/null && break; sleep 0.2; done
EP3=$(await_stub busy); check "$?" "0" "  the watched run's claude started"
[ -n "$EP3" ] || reap_run "$RS"
# the watcher has looped (it writes last_status each pass): --end must find a watched run, not race it
end=$((SECONDS + 30)); while [ "$SECONDS" -lt "$end" ] && [ -z "$(field last_status 2>/dev/null)" ]; do sleep 0.2; done
"$B/dispatch" --end demo --repo "$T/repo" > "$T/out" 2>&1; check "$?" "0" "--end on a watched, busy run"
wait_run "$RS" "$EP3"
check "$(field end_reason)" "ended by dispatch --end (was busy)" "  the reason is --end's, not the watcher's"
check "$(grep -c 'ended session' "$HOME/end.log")" "1" "  ended once"
# a record from before proc_start: --end never signals it
sleep 60 & OLDP=$!
printf '{"mode":"headless","repo":"%s","topic":"old","pid":%s,"session":"o","started":%s}' "$T/repo" $OLDP "$(date +%s)" > "$RUNS/00000000-000004-repo.old.json"
"$B/dispatch" --end old --repo "$T/repo" > "$T/out" 2>&1; check "$?" "1" "--end on a record with no start time: refused"
has "$T/out" "not provably this run's claude" "  saying why"
kill -0 $OLDP 2>/dev/null; check "$?" "0" "  and that process is never signalled"
kill $OLDP 2>/dev/null; wait $OLDP 2>/dev/null; rm -f "$RUNS/00000000-000004-repo.old.json"
# live's count with an idle orphan present: the reap's log line stays off stdout
OP2=$(orphan lost2 sess-lost2 5)
check "$(python3 "$B/dispatch-rc" live "$T/repo" demo 2>/dev/null)" "0" "live prints only the count while it reaps an orphan"
kill -0 $OP2 2>/dev/null; check "$?" "1" "  the orphan was reaped"
# after(): a predecessor whose claude has exited is not gone while its watcher still runs
sleep 60 & WP=$!; true & DP=$!; wait $DP
printf '{"mode":"rc","repo":"%s","topic":"demo","pid":%s,"proc_start":"x","session":"w","started":%s,"watcher":%s,"watcher_start":"%s","screen":"run-repo-demo","screendir":"%s"}' \
  "$T/repo" $DP "$(date +%s)" $WP "$(pst $WP)" "$HOME" > "$RUNS/00000000-000006-repo.demo.json"
: > "$T/claude.calls"
DISPATCH_PREV_WAIT=1 DISPATCH_LOG="$HOME/watcher.log" "$B/dispatch" $BR --repo "$T/repo" --headless
has "$HOME/watcher.log" "FAILED: the run of demo before this one is still going" "a predecessor whose watcher still runs is waited for, though its claude exited"
check "$(wc -c < "$T/claude.calls" | tr -d ' ')" "0" "  and no second session"
kill $WP 2>/dev/null; wait $WP 2>/dev/null; rm -f "$RUNS/00000000-000006-repo.demo.json"
# memory past the host's limits refuses a start whatever the count (bin/headroom, 2026-10-22)
: > "$T/claude.calls"
DISPATCH_HOST=studio HEADROOM_SAMPLE="50 1 500" DISPATCH_LOG="$HOME/mem.log" "$B/dispatch" $BR --repo "$T/repo" --headless
has "$HOME/mem.log" "FAILED: studio: no room: 500 MB/s swapping, over 50 MB/s" "a start on a host swapping past its limit is refused, said in the log"
check "$(wc -c < "$T/claude.calls" | tr -d ' ')" "0" "  and starts no session"
# three live runs of other topics: a fourth is refused, not queued (the laptop's cap; the dispatch host's is 6)
for i in 1 2 3; do
  sleep 60 & lp=$!
  printf '{"mode":"headless","repo":"%s","topic":"busy%s","pid":%s,"proc_start":"%s","session":"b%s","started":%s}' "$T/repo" $i $lp "$(pst $lp)" $i "$(date +%s)" > "$RUNS/00000000-00001$i-repo.busy$i.json"
done
check "$(python3 "$B/dispatch-rc" live "$T/repo" demo)" "3" "three live runs counted (identity checked)"
: > "$T/claude.calls"
DISPATCH_HOST=laptop DISPATCH_LOG="$HOME/cap.log" "$B/dispatch" $BR --repo "$T/repo" --headless
has "$HOME/cap.log" "FAILED: 3 other runs are busy" "a fourth run is refused, said in the log"
check "$(wc -c < "$T/claude.calls" | tr -d ' ')" "0" "  and starts no session"
# one of the three goes warm — idle 5 min, its session kept for the cache — and stops counting (D1)
WP3=$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["pid"])' "$RUNS/00000000-000013-repo.busy3.json")
mkdir -p "$HOME/.claude/sessions"
printf '{"pid":%s,"sessionId":"b3","status":"idle","statusUpdatedAt":%s}' "$WP3" "$(( ($(date +%s) - 300) * 1000 ))" > "$HOME/.claude/sessions/$WP3.json"
check "$(python3 "$B/dispatch-rc" live "$T/repo" demo)" "2" "a warm run (idle, kept for its cache) is not counted against the cap (D1, the owner 2026-10-08)"
rm -f "$HOME/.claude/sessions/$WP3.json"
# one waits at a prompt or a question nobody is there to answer: not counted either, from its first second
printf '{"pid":%s,"sessionId":"b3","status":"waiting","waitingFor":"dialog open","statusUpdatedAt":%s}' "$WP3" "$(( $(date +%s) * 1000 ))" > "$HOME/.claude/sessions/$WP3.json"
check "$(python3 "$B/dispatch-rc" live "$T/repo" demo)" "2" "a waiting run (a dialog open) is not counted against the cap (the owner 2026-10-08: don't clog the pipeline)"
# …unless a subagent under it still writes: "waiting" then means one agent's prompt, the rest still spend
mkdir -p "$HOME/.claude/projects/p/b3/subagents"; : > "$HOME/.claude/projects/p/b3/subagents/agent-1.jsonl"
check "$(python3 "$B/dispatch-rc" live "$T/repo" demo)" "3" "  waiting with a subagent writing in the last 30 s: still counted (review 2026-10-10)"
rm -rf "$HOME/.claude/projects/p/b3"
check "$(DISPATCH_MAX_PARKED=0 python3 "$B/dispatch-rc" live "$T/repo" demo)" "3" "  past DISPATCH_MAX_PARKED parked runs count again: a prompt every run hits cannot fill the Mac"
rm -f "$HOME/.claude/sessions/$WP3.json"
reap() { local f p; for f in "$@"; do p=$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["pid"])' "$f"); kill "$p" 2>/dev/null; wait "$p" 2>/dev/null; done; }
reap "$RUNS"/00000000-00001*

echo "end-warm: autofinish ends a branch's warm run before it launches (D2: C)"
ew() {   # PIDVAR TOPIC BRANCH STATUS — a live run of BRANCH whose session reads STATUS, idle 5 min
  sleep 120 & local p=$!
  printf '{"mode":"headless","repo":"%s","topic":"%s","branch":"%s","pid":%s,"proc_start":"%s","session":"%s","started":%s}' \
    "$T/repo" "$2" "$3" $p "$(pst $p)" "s-$2" "$(date +%s)" > "$RUNS/00000000-00002$p-repo.$2.json"
  printf '{"pid":%s,"sessionId":"s-%s","status":"%s","statusUpdatedAt":%s}' $p "$2" "$4" "$(( ($(date +%s) - 300) * 1000 ))" > "$HOME/.claude/sessions/$p.json"
  eval "$1=$p"
}
ew EWA warmone claude/laptop/2026-10-08-launch idle
ew EWB other claude/laptop/2026-10-08-other idle
python3 "$B/dispatch-rc" end-warm claude/laptop/2026-10-08-launch "$T/repo" --dry-run > "$T/out"; rc=$?
check "$rc $(kill -0 $EWA 2>/dev/null && echo alive)" "0 alive" "--dry-run names the warm run and ends nothing"
has "$T/out" "would end the warm run of claude/laptop/2026-10-08-launch" "  said"
python3 "$B/dispatch-rc" end-warm claude/laptop/2026-10-08-launch "$T/repo" > "$T/out"; rc=$?
dead_ $EWA
check "$rc $(kill -0 $EWA 2>/dev/null && echo alive || echo ended) $(kill -0 $EWB 2>/dev/null && echo alive)" "0 ended alive" \
  "the branch's warm run is ended; another branch's is not"
has "$(ls "$RUNS"/00000000-00002$EWA-*.json)" "ended for its landing" "  and its record says why"
ew EWC busyone claude/laptop/2026-10-08-launch busy
python3 "$B/dispatch-rc" end-warm claude/laptop/2026-10-08-launch "$T/repo" > "$T/out"; rc=$?
check "$rc $(kill -0 $EWC 2>/dev/null && echo alive)" "3 alive" "a busy run of the branch: exit 3, left alone — no launch"
kill $EWB $EWC 2>/dev/null; wait $EWB $EWC 2>/dev/null
rm -f "$RUNS"/00000000-00002*; rm -f "$HOME/.claude/sessions/$EWA.json" "$HOME/.claude/sessions/$EWB.json" "$HOME/.claude/sessions/$EWC.json"

echo "find_window: the newest, and never a '-' after the topic"
printf '[%s]' '{"id": 70, "app": "Terminal", "title": "sam — run · demo-b · repo — screen", "space": 5},
 {"id": 41, "app": "Terminal", "title": "sam — run · demo · repo — screen", "space": 5},
 {"id": 45, "app": "Terminal", "title": "sam — run · demo · repo — screen", "space": 5},
 {"id": 80, "app": "Terminal", "title": "sam — run · solo-x — screen", "space": 5}' > "$T/windows.json"
fw() { python3 -c '
import importlib.machinery as m, importlib.util as u, sys
l = m.SourceFileLoader("r", sys.argv[1]); r = u.module_from_spec(u.spec_from_loader("r", l)); l.exec_module(r)
print(r.find_window(sys.argv[2]))' "$B/dispatch-rc" "$1"; }
check "$(fw 'run · demo · repo')" "45" "the newest window of the run"
check "$(fw 'run · solo')" "None" "  'solo' is not 'solo-x'"
R=$(python3 -c '
import importlib.machinery as m, importlib.util as u, sys
l = m.SourceFileLoader("r", sys.argv[1]); r = u.module_from_spec(u.spec_from_loader("r", l)); l.exec_module(r)
print(r.find_window("run · demo · repo", {41, 45}))' "$B/dispatch-rc")
check "$R" "None" "  a window that held the title before the open is never this run's (restored after a reboot, 2026-10-07)"

echo "window: yabai detached from Terminal (after the reboot of 2026-10-06) is restarted once"
# untitled, unmanaged: what yabai listed for every Terminal window until it was restarted — two in
# view, all blind (one lone blind window is as likely a stray sheet: no restart for that)
printf '[{"id": 9, "app": "Terminal", "title": "", "space": 5, "is-visible": true, "has-ax-reference": false},
 {"id": 8, "app": "Terminal", "title": "", "space": 5, "is-visible": true, "has-ax-reference": false}]' > "$T/windows.json"
cat > "$T/yabai-re" <<EOF
#!/bin/sh
echo "\$*" >> "$T/yabai.calls"
[ "\$1" = --restart-service ] && printf '[{"id": 90, "app": "Terminal", "title": "sam — run · re · repo — screen", "space": 5, "is-visible": true, "has-ax-reference": true}]' > "$T/windows.json"
case "\$2 \$3" in "query --windows") cat "$T/windows.json";; "query --spaces") cat "$T/spaces.json";; esac
EOF
chmod +x "$T/yabai-re"
printf '{"runner": "%s/run-repo-re.sh", "screen": "run-repo-re", "screendir": "%s", "title": "run · re · repo"}' "$T" "$T" > "$T/re.json"
: > "$T/yabai.calls"
DISPATCH_YABAI="$T/yabai-re" DISPATCH_OPEN=true DISPATCH_FIND_WAIT=0.5 python3 "$B/dispatch-rc" window "$T/re.json" > "$T/out"
check "$(grep -c -- '--restart-service' "$T/yabai.calls")" "1" "  one restart"
has "$T/out" "not attached to Terminal" "  the log says why"
has "$T/out" "tiled on space 5" "  then the window is found and tiled"
printf '[{"id": 9, "app": "Terminal", "title": "", "space": 1, "is-visible": false, "has-ax-reference": false}]' > "$T/windows.json"
: > "$T/yabai.calls"
DISPATCH_YABAI="$T/yabai" DISPATCH_OPEN=true DISPATCH_FIND_WAIT=0.5 python3 "$B/dispatch-rc" window "$T/re.json" > "$T/out"
check "$(grep -c -- '--restart-service' "$T/yabai.calls")" "0" "  a handle missing on a desktop out of view is normal: no restart"
has "$T/out" "not seen by yabai in 0 s — expected while the claude desktop is out of view" "  just the not-seen line"
printf '[{"id": 9, "app": "Terminal", "title": "", "space": 2, "is-visible": true, "has-ax-reference": false},
 {"id": 10, "app": "Terminal", "title": "zsh", "space": 2, "is-visible": true, "has-ax-reference": true}]' > "$T/windows.json"
: > "$T/yabai.calls"
DISPATCH_YABAI="$T/yabai" DISPATCH_OPEN=true DISPATCH_FIND_WAIT=0.5 python3 "$B/dispatch-rc" window "$T/re.json" > "$T/out"
check "$(grep -c -- '--restart-service' "$T/yabai.calls")" "0" "  one stray window without a handle (a leftover sheet) beside a managed one: no restart (review 2026-10-08)"

echo "finish: a window yabai cannot close (out of view) closes itself once its screen ends"
printf '[{"id": 77, "app": "Terminal", "title": "sam — run · re · repo — screen", "space": 5}]' > "$T/windows.json"
printf '{"runner": "%s/run-repo-re.sh", "screen": "run-repo-re", "screendir": "%s", "title": "run · re · repo", "window": 77, "session": "s-re"}' "$T" "$T" > "$T/re.json"
R=$(YABAI_STUCK=1 STUB_SELFCLOSE=77 python3 -c '
import importlib.machinery as m, importlib.util as u, json, sys
l = m.SourceFileLoader("r", sys.argv[1]); r = u.module_from_spec(u.spec_from_loader("r", l)); l.exec_module(r)
st = json.load(open(sys.argv[2])); r.finish(sys.argv[2], st, "test")
st = json.load(open(sys.argv[2])); print(bool(st.get("window_closed")), st.get("window_stuck"))' "$B/dispatch-rc" "$T/re.json" 2>&1)
check "$(printf '%s' "$R" | tail -1)" "True None" "  recorded closed, not stuck"
has <(printf '%s' "$R") "closed itself once its screen ended" "  and the log says how"

echo "diverged or foreign worktree"
mkdir -p "$T/repo/.claude/worktrees/stray"
"$B/dispatch" claude/laptop/2026-10-02-stray --repo "$T/repo" 2>/dev/null
git -C "$T/repo" send-pack "$T/origin.git" "main:refs/heads/claude/laptop/2026-10-02-stray" >/dev/null 2>&1
"$B/dispatch" claude/laptop/2026-10-02-stray --repo "$T/repo"
has "$(ls "$HOME"/Library/Logs/claude-weekly/*-dispatch-stray.log)" "is not a worktree on" "a leftover directory is refused"

echo "a repo that acts on the real world"
mkdir -p "$T/phys"; printf -- '- physical: python3 test.py --physical\n' > "$T/phys/AGENTS.md"
"$B/dispatch" $BR --repo "$T/phys" --at "$FUT 04:10" 2>/dev/null; check "$?" "2" "scheduling refused unless physical: none"
DISPATCH_LOG="$HOME/phys.log" "$B/dispatch" $BR --repo "$T/phys"
has "$HOME/phys.log" "must say \`physical: none\`" "a direct run refused too, said in the log"

echo "missing brief"
"$B/dispatch" claude/laptop/2026-10-02-nobrief --repo "$T/repo"
has "$(ls "$HOME"/Library/Logs/claude-weekly/*-dispatch-nobrief.log)" "FAILED: no docs/handoff" "no brief is a failure, not a blind run"

echo "next: a finished step starts the next one itself"
NB=claude/laptop/2026-10-04-step
git -C "$T/repo" worktree add -q -b $NB "$T/repo/.claude/worktrees/step" main
W="$T/repo/.claude/worktrees/step"; O="$(git -C "$W" rev-parse --absolute-git-dir)/claude/owner.json"
mkdir -p "$W/docs/handoff" "$(dirname "$O")"; echo "# step 2 brief" > "$W/docs/handoff/2026-10-04-step.md"
git -C "$W" add docs; git -C "$W" commit -qm "step 1 built; step 2 brief"
# the fired run, as far as --next can see it: its header (and maybe a failure) in the log
cat > "$T/launchctl-fire" <<EOF
#!/bin/sh
echo "\$*" >> "$T/calls"
case "\$1" in bootstrap) [ -n "\${FIRE:-}" ] && printf '== now dispatch $NB (opus high) in repo\n%s' "\$FIRE" >> "\$DISPATCH_LOG";; esac
exit 0
EOF
chmod +x "$T/launchctl-fire"
nx() { DISPATCH_LAUNCHCTL="$T/launchctl-fire" DISPATCH_LOG="$HOME/next.log" DISPATCH_NEXT_DELAY=65 DISPATCH_NEXT_SETTLE=0 DISPATCH_NEXT_WAIT=0 \
       CLAUDE_CODE_SESSION_ID=sess-A "$B/dispatch" $NB --repo "$T/repo" --next "$@"; }
own() { printf '{"session": "%s", "branch": "%s", "seen": %s}' "$1" $NB "$(date +%s)" > "$O"; }
echo dirt > "$W/scratch"; own sess-A
nx > "$T/out" 2>&1; check "$?" "2" "a dirty worktree is refused"
check "$([ -f "$O" ] && echo kept || echo gone)" "kept" "  and its lock is left alone"
rm "$W/scratch"; own sess-B
nx > "$T/out" 2>&1; check "$?" "2" "a worktree another live session holds is refused"
has "$T/out" "held by session sess-B" "  naming that session"
own sess-A; rm -f "$HOME/next.log"
FIRE="" nx > "$T/out" 2>&1; check "$?" "1" "no run header in the log is a failure, not a claim"
grep -q "No such file" "$T/out"; check "$?" "1" "  a log not written yet is no error"
has "$T/out" "NOT STARTED" "  said as such"
own sess-A
FIRE="FAILED: worktree" nx > "$T/out" 2>&1; check "$?" "1" "a run that failed at once is reported"
own sess-A
FIRE="17:50:01 waiting for the run of step started 17:40" nx > "$T/out" 2>&1; check "$?" "0" "a step scheduled from inside the run before it…"
has "$T/out" "queued: the next run of $NB" "  …is reported queued behind it, not started"
printf '{"session": "sess-B", "branch": "%s", "seen": %s, "handover": %s}' $NB "$(date +%s)" "$(date +%s)" > "$O"
FIRE=" " nx > "$T/out" 2>&1; check "$?" "0" "a lock handed over (pickup next) is free"
printf '{"session": "sess-A", "branch": "%s", "seen": %s, "handover": %s}' $NB "$(date +%s)" "$(date +%s)" > "$O"
FIRE=" " nx > "$T/out" 2>&1; check "$?" "2" "a lock THIS session handed to a tab: refused"
has "$T/out" "one hand-over per step" "  saying why"
# the next step on the peer: scheduled over ssh, confirmed from the peer's log over ssh
cat > "$T/ssh-next" <<EOF
#!/bin/sh
echo "ssh \$*" >> "$T/ssh.calls"
case "\$*" in *"tail -c"*) printf '== now dispatch $NB (opus high) in repo\n';; *"wc -c"*) echo 0;; esac
exit 0
EOF
chmod +x "$T/ssh-next"
own sess-A; : > "$T/ssh.calls"
DISPATCH_SSH="$T/ssh-next" STUB_WHICH=acct-c DISPATCH_ACCOUNT="$T/acct" nx --repo "$HOME/projects/other" --on buildbox > "$T/out" 2>&1; check "$?" "0" "--next --on buildbox: scheduled there…"
has "$T/ssh.calls" "DISPATCH_LOG=\$HOME/Library/Logs/claude-weekly/" "  its log named for the peer"
has "$T/out" "started on buildbox" "  …and confirmed from the peer's log"
check "$(grep -c -- '--account' "$T/ssh.calls")" "0" "  the peer picks the login at fire time (this session's may not be set up there)"
printf '#!/bin/sh\necho "ssh $*" >> "%s/ssh.calls"\ncase "$*" in *"wc -c"*) echo 0;; esac\nexit 0\n' "$T" > "$T/ssh-quiet"; chmod +x "$T/ssh-quiet"
own sess-A; : > "$T/ssh.calls"
STUB_PROBE_RC=255 DISPATCH_LABEL= DISPATCH_DEFAULT_ON=buildbox FIRE=" " DISPATCH_HOST=laptop nx --repo "$HOME/projects/other" > "$T/out" 2>&1; check "$?" "0" "--next with no host, the dispatch host unreachable…"
has "$T/out" "scheduling it on this Mac instead" "  …runs here"
has "$T/out" "started: claude is running $NB" "  …confirmed from this Mac's log"
own sess-A
DISPATCH_SSH="$T/ssh-quiet" nx --repo "$HOME/projects/other" --on buildbox > "$T/out" 2>&1; check "$?" "1" "  no header in the peer's log: a failure, not a claim"
has "$T/out" "NOT STARTED on buildbox" "  saying where"
own sess-A
FIRE=" " STUB_WHICH=acct-c DISPATCH_ACCOUNT="$T/acct" nx > "$T/out" 2>&1; check "$?" "0" "--next from a session on acct-c…"
grep -l "<string>--account</string><string>acct-c</string>" "$HOME"/Library/LaunchAgents/org.example.claude.dispatch.repo.step.*.plist >/dev/null 2>&1; check "$?" "0" "  …schedules the next step on acct-c (work-account E5)"
own sess-A
FIRE=" " STUB_WHICH=acct-c DISPATCH_PIN=bound DISPATCH_ACCOUNT="$T/acct" nx > "$T/out" 2>&1; check "$?" "0" "--next from a bound run (DISPATCH_PIN)…"
grep -l "<string>--account</string><string>bound</string>" "$HOME"/Library/LaunchAgents/org.example.claude.dispatch.repo.step.*.plist >/dev/null 2>&1; check "$?" "0" "  …stays bound, whatever account which says (design_route)"
own sess-A
FIRE=" " CLAUDE_UNATTENDED=dispatch DISPATCH_BRIEF=$(git -C "$W" rev-parse HEAD:docs/handoff/2026-10-04-step.md) nx > "$T/out" 2>&1
check "$?" "2" "an unattended run's --next on the brief it started from, unchanged: refused"
has "$T/out" "is the brief this run started from" "  saying why"
own sess-A
FIRE=" " CLAUDE_UNATTENDED=run-seed RUN_SEED_BRIEF=$(git -C "$W" rev-parse HEAD:docs/handoff/2026-10-04-step.md) nx > "$T/out" 2>&1
check "$?" "2" "  RUN_SEED_BRIEF (a run started before the rename) is the same guard"
check "$([ -f "$O" ] && echo kept || echo gone)" "kept" "  before anything was pushed or freed"
own sess-A
FIRE=" " DISPATCH_HOST=studio HEADROOM_SAMPLE="3 15 200" nx > "$T/out" 2>&1; check "$?" "2" "--next on a host past its memory limits: refused, with every slot free"
has "$T/out" "no room: 3 % free, under 10 %" "  saying which limit"
has "$T/out" "the next step waits for a run to end and memory to free" "  and what the next step waits on, in the words the Stop lint and helm's S2 read"
check "$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import common; print(common.unrelayed_ask(open(sys.argv[2]).read()))' "$B/../../regatta/hooks" "$T/out")" "None" \
  "    which the core's Stop lint takes for dispatch's own refusal, not an ask to relay"
own sess-A
FIRE=" " DISPATCH_HOST=studio HEADROOM_SAMPLE="not a sample" nx > "$T/out" 2>&1; check "$?" "0" "  memory it cannot read: goes ahead (a broken probe never stops every run)"
has "$T/out" "no memory reading" "    saying so"
for i in 1 2 3; do sleep 60 & lp=$!; printf '{"mode":"headless","repo":"%s","topic":"cap%s","pid":%s,"proc_start":"%s","session":"c%s","started":%s}' "$T/repo" $i $lp "$(pst $lp)" $i "$(date +%s)" > "$RUNS/00000000-00002$i-repo.cap$i.json"; done
FIRE=" " DISPATCH_HOST=laptop nx > "$T/out" 2>&1; check "$?" "2" "--next with three runs live: refused (the laptop)"
has "$T/out" "3 runs are busy already" "  saying so"
own sess-A
FIRE=" " DISPATCH_HOST=buildbox nx > "$T/out" 2>&1; check "$?" "0" "  on the dispatch host three live runs leave room (its cap is 6)"
for i in 4 5; do sleep 60 & lp=$!; printf '{"mode":"headless","repo":"%s","topic":"cap%s","pid":%s,"proc_start":"%s","session":"c%s","started":%s}' "$T/repo" $i $lp "$(pst $lp)" $i "$(date +%s)" > "$RUNS/00000000-00002$i-repo.cap$i.json"; done
own sess-A
FIRE=" " DISPATCH_HOST=buildbox nx > "$T/out" 2>&1; check "$?" "0" "  five: the last free slot is taken, not refused"
for i in 6; do sleep 60 & lp=$!; printf '{"mode":"headless","repo":"%s","topic":"cap%s","pid":%s,"proc_start":"%s","session":"c%s","started":%s}' "$T/repo" $i $lp "$(pst $lp)" $i "$(date +%s)" > "$RUNS/00000000-00002$i-repo.cap$i.json"; done
own sess-A
FIRE=" " DISPATCH_HOST=buildbox nx > "$T/out" 2>&1; check "$?" "2" "  and six are its cap: refused"
has "$T/out" "6 runs are busy already" "    saying so"
reap "$RUNS"/00000000-00002*
# the cap has one home, dispatch's max_runs: wharf and stalls_tick.py ask `--cap` (their own copies
# went stale at 5 -> 8 -> 10, and 8 -> 6 sat unmerged on a conflict; 2026-10-25)
check "$(DISPATCH_HOST=buildbox "$B/dispatch" --cap) $(DISPATCH_HOST=elsewhere "$B/dispatch" --cap) $(DISPATCH_HOST=buildbox DISPATCH_MAX_RUNS=4 "$B/dispatch" --cap)" \
  "6 3 4" "--cap: 6 on the dispatch host, 3 elsewhere, DISPATCH_MAX_RUNS over either"
check "$(grep -c -- '"--cap"' "$B/wharf") $(grep -c -- '"--cap"' "$STALLS_TICK" 2>/dev/null) $(grep -cE 'DISPATCH_MAX_RUNS"\) or \([0-9]' "$B/wharf" "$STALLS_TICK" 2>/dev/null | awk -F: '{n+=$NF} END {print n+0}')" \
  "1 1 0" "  wharf and stalls_tick.py ask dispatch --cap and carry no number of their own"
own sess-A
FIRE=" " CLAUDE_UNATTENDED=dispatch DISPATCH_BRIEF=0000000 nx > "$T/out" 2>&1; check "$?" "0" "a clean, committed step starts the next (an unattended run's, on a new brief)"
has "$T/out" "started: claude is running $NB (opus high) in screen run-repo-step" "  confirmed from the log"
check "$([ -f "$O" ] && echo kept || echo gone)" "gone" "  this session's lock freed"
check "$(git --git-dir="$T/origin.git" rev-parse $NB)" "$(git -C "$W" rev-parse HEAD)" "  the branch on origin at this commit"
has "$(ls "$HOME"/Library/LaunchAgents/org.example.claude.dispatch.repo.step.[0-9]*.plist)" "<string>$NB</string>" "  scheduled through launchd"
echo y > "$W/work"; git -C "$W" add work; git -C "$W" commit -qm "step 2 work"
nx > "$T/out" 2>&1; check "$?" "2" "work committed after the brief: refused, the next run would redo this step"
has "$T/out" "work was committed after docs/handoff/2026-10-04-step.md (work)" "  naming what came after"
"$B/dispatch" $NB --repo "$T/repo" --next --at "$FUT 04:10" 2>/dev/null; check "$?" "2" "--next with --at is refused"
"$B/dispatch" $BR --repo "$T/phys" --next 2>/dev/null; check "$?" "2" "--next refused unless physical: none"
git -C "$T/repo" update-ref refs/heads/claude/laptop/2026-10-04-bare main
"$B/dispatch" claude/laptop/2026-10-04-bare --repo "$T/repo" --next 2>"$T/out"; check "$?" "2" "--next without a committed brief is refused"
has "$T/out" "write the next step's brief there" "  saying what to write"
git -C "$T/repo" worktree add -q -b claude/laptop/2026-10-04-bare2 "$T/repo/.claude/worktrees/bare2" main
mkdir -p "$T/repo/.claude/worktrees/bare2/docs/handoff"; echo b > "$T/repo/.claude/worktrees/bare2/docs/handoff/2026-10-04-x-bare2.md"
git -C "$T/repo/.claude/worktrees/bare2" add docs; git -C "$T/repo/.claude/worktrees/bare2" commit -qm "another topic's brief"
"$B/dispatch" claude/laptop/2026-10-04-bare2 --repo "$T/repo" --next 2>"$T/out"; check "$?" "2" "a brief is <date>-<topic>.md exactly: …-x-bare2.md is not bare2's"

echo "next: a block of a ship leaves the start to wharf apply (wharf-on-orca S5, B9)"
if [ -z "$HELMLIB" ]; then
  echo "  --   skipped: helm's helmlib.py is not installed here (bin/wharf next reads helm's ships; without them no run is a ship's block)"
else
# a plan recording a blueprint of two blocks, kept under this test's own dir: the ship's first block
# is the branch claude/laptop/2026-10-04-bare (no brief anywhere), its successor 'shipnext'
export PLANS_DIR="$T/shipplans"; SP="$PLANS_DIR/shipplan"; mkdir -p "$SP" "$PLANS_DIR/badplan" "$T/repo/docs/blueprints"
printf -- '---\nship: tship\nrepo: %s\ncreated: 2026-10-04\nblocks:\n  - id: shipfirst\n    provider: claude-code\n    branch: claude/laptop/2026-10-04-bare\n  - id: shipnext\n    provider: shell\n    command: "true"\n    depends_on: [shipfirst]\n---\n## shipfirst\nTask: t\nTier: worker\nWhy: w\nStart here: s\nDone means: d\nNot this: n\n' "$T/repo" > "$T/repo/docs/blueprints/2026-10-04-tship.md"
echo "not a blueprint" > "$T/badbp.md"
python3 - "$SP" "$T/repo/docs/blueprints/2026-10-04-tship.md" "$PLANS_DIR/badplan" "$T/badbp.md" <<'PY'
import json, sys
json.dump({"id": "shipplan", "tasks": {"shipfirst": {"ship": "tship", "kind": "session", "provider": "claude-code", "branch": "claude/laptop/2026-10-04-bare"}},
           "blueprints": {"tship": {"file": sys.argv[2]}}}, open(sys.argv[1] + "/plan.json", "w"))
json.dump({"id": "badplan", "tasks": {"gone": {"ship": "gone", "kind": "session", "branch": "claude/laptop/2026-10-04-bare"}},
           "blueprints": {"gone": {"file": sys.argv[4]}}}, open(sys.argv[3] + "/plan.json", "w"))
PY
: > "$T/calls"
NX() { env DISPATCH_PLAN="$1" DISPATCH_TASK="$2" "$B/dispatch" claude/laptop/2026-10-04-bare --repo "$T/repo" --next; }
FIRE=" " NX shipplan shipfirst > "$T/out" 2>&1; check "$?" "0" "--next from a ship's own block, brief or none: exit 0"
has "$T/out" "is block shipfirst of ship tship" "  says which ship and block"
has "$T/out" "next is shipnext" "  names the blueprint's next block"
has "$T/out" "\`wharf apply\`" "  and who starts it"
check "$(cat "$T/calls")" "" "  nothing scheduled: launchd untouched"
check "$(ls "$HOME"/Library/LaunchAgents/*bare.[0-9]*.plist 2>/dev/null | wc -l | tr -d ' ')" "0" "  and no job written"
env DISPATCH_PLAN=shipplan "$B/dispatch" claude/laptop/2026-10-04-bare --repo "$T/repo" --next 2>"$T/out"; check "$?" "2" "wharf's own start (the plan, no block) is not swallowed: it goes on and is refused for want of a brief"
has "$T/out" "write the next step's brief there" "  by the old rule, not by the guard"
NX shipplan shipnext 2>"$T/out"; check "$?" "2" "the last block has no successor: scheduled as before (refused for want of a brief)"
has "$T/out" "write the next step's brief there" "  by the old rule"
env DISPATCH_PLAN=shipplan DISPATCH_TASK=shipfirst "$B/dispatch" claude/laptop/2026-10-04-bare2 --repo "$T/repo" --next 2>"$T/out"; check "$?" "2" "the block's session starting another branch: not swallowed (refused for want of a brief)"
has "$T/out" "write the next step's brief there" "  by the old rule, not by the guard"
NX badplan gone 2>"$T/out"; check "$?" "2" "a plan whose blueprint does not load, no match: stops"
has "$T/out" "could not tell whether" "  saying the check failed, not that it is a seed"
"$B/dispatch" claude/laptop/2026-10-04-bare2 --repo "$T/repo" --next 2>"$T/out"; check "$?" "2" "a seed no plan names, a ship's plan beside it: unchanged (refused for want of a brief)"
has "$T/out" "write the next step's brief there" "  by the old rule"
unset PLANS_DIR
fi

echo "--account: the login is picked at fire time (work-account E5)"
mkdir -p "$HOME/.acct-c"
AR() { DISPATCH_ACCOUNT="$T/acct" DISPATCH_HOST=buildbox "$B/dispatch" $BR --repo "$T/repo" --headless "$@"; }
: > "$T/env.calls"; : > "$T/claude.calls"
STUB_ACCT=f DISPATCH_LOG="$HOME/acct1.log" AR
has "$HOME/acct1.log" "== account acct-c ($HOME/.acct-c): week 10% < 90%" "auto: the pick is logged with its reason"
grep -q "^CLAUDE_CONFIG_DIR=$HOME/.acct-c$" "$T/env.calls"; check "$?" "0" "  and the run's claude gets its config dir"
has "$T/acct.calls" "account pick --repo $T/repo --json" "  the pick names the repo (its deny list)"
: > "$T/env.calls"
STUB_ACCT=acct-a CLAUDE_CONFIG_DIR="$HOME/.claude-pro" DISPATCH_LOG="$HOME/acct2.log" AR
has "$HOME/acct2.log" "== account acct-a: week 20% < 95%" "a repo acct-c denies: the pick says acct-a"
grep -q "^CLAUDE_CONFIG_DIR=" "$T/env.calls"; check "$?" "1" "  and the run is on the default dir, whatever the caller had"
: > "$T/env.calls"; : > "$T/claude.calls"
STUB_ACCT=short DISPATCH_LOG="$HOME/acct3.log" AR
has "$HOME/acct3.log" "FAILED: no account may run this now — acct-c: week 95% ≥ 90%; acct-a: week 99% ≥ 95%; not running" "exit 3: FAILED, each row's reason"
check "$(wc -l < "$T/claude.calls" | tr -d ' ')" "0" "  and no claude started"
: > "$T/env.calls"
STUB_ACCT=none CLAUDE_CONFIG_DIR="$HOME/.claude-pro" DISPATCH_LOG="$HOME/acct4.log" AR
has "$HOME/acct4.log" "== account: no account registry here — the login this run was started with" "exit 4 (no registry): as before"
grep -q "^CLAUDE_CONFIG_DIR=$HOME/.claude-pro$" "$T/env.calls"; check "$?" "0" "  the caller's login kept"
: > "$T/env.calls"
DISPATCH_LOG="$HOME/acct5.log" AR --account acct-c
has "$HOME/acct5.log" "== account acct-c ($HOME/.acct-c): as asked" "--account LABEL: that row"
grep -q "^CLAUDE_CONFIG_DIR=$HOME/.acct-c$" "$T/env.calls"; check "$?" "0" "  its config dir"
has "$T/acct.calls" "account limits acct-c --repo $T/repo --json" "  read with the repo, so its deny list counts"
: > "$T/claude.calls"
STUB_LIMITS=denied DISPATCH_LOG="$HOME/acct6.log" AR --account acct-c
has "$HOME/acct6.log" "FAILED: --account acct-c: repo is on its deny list — run it on the default login (no --account); not running" "a named account in a denied repo: refused"
check "$(wc -l < "$T/claude.calls" | tr -d ' ')" "0" "  nothing started"
STUB_LIMITS=denied DISPATCH_LOG="$HOME/acct7.log" AR --account acct-c --force
has "$HOME/acct7.log" "FAILED: --account acct-c: repo is on its deny list" "  --force never crosses a deny list (the guard would block every prompt)"
STUB_LIMITS=overage CLAUDE_UNATTENDED=dispatch DISPATCH_LOG="$HOME/acct8.log" AR --account acct-c --force
has "$HOME/acct8.log" "FAILED: --account acct-c: extra usage on — --force past paid overage is a yes only a person gives, refused to an unattended caller; not running" \
  "  --force past paid overage, unattended: refused (costs S8, the finish review)"
STUB_LIMITS=overage DISPATCH_LOG="$HOME/acct9.log" AR --account acct-c --force
has "$HOME/acct9.log" "== account acct-c ($HOME/.acct-c): as asked, forced past: extra usage on" "  …a person's --force runs it"
# a line on the account's stderr is never parsed: before 2026-10-22 it failed json.loads at char 0,
# and auto and bound fell to the caller's login, --account to FAILED (tenants review, regatta#82)
: > "$T/env.calls"
STUB_NOISE="account: a warning" STUB_ACCT=f DISPATCH_LOG="$HOME/acctn1.log" AR
has "$HOME/acctn1.log" "== account acct-c ($HOME/.acct-c): week 10% < 90%" "stderr before the JSON: auto still picks the row"
grep -q "^CLAUDE_CONFIG_DIR=$HOME/.acct-c$" "$T/env.calls"; check "$?" "0" "  and its config dir"
: > "$T/env.calls"
STUB_NOISE="account: a warning" STUB_ACCT=acct-a CLAUDE_CONFIG_DIR="$HOME/.claude-pro" DISPATCH_LOG="$HOME/acctn2.log" AR --account bound
has "$HOME/acctn2.log" "== account acct-a: week 20% < 95%" "  bound still picks the row"
grep -q "^CLAUDE_CONFIG_DIR=" "$T/env.calls"; check "$?" "1" "  on the default dir, not the caller's"
: > "$T/env.calls"
STUB_NOISE="account: a warning" DISPATCH_LOG="$HOME/acctn3.log" AR --account acct-c
has "$HOME/acctn3.log" "== account acct-c ($HOME/.acct-c): as asked" "  --account LABEL still runs there"
grep -q "^CLAUDE_CONFIG_DIR=$HOME/.acct-c$" "$T/env.calls"; check "$?" "0" "  with its config dir"
STUB_ACCT=junk DISPATCH_LOG="$HOME/acctn4.log" AR
has "$HOME/acctn4.log" "== account: account pick failed (account: probe timed out; not json) — the login this run was started with" "a failed pick quotes its stderr, then its stdout"
: > "$T/claude.calls"
STUB_LIMITS=fail DISPATCH_LOG="$HOME/acctn5.log" AR --account claude-x
has "$HOME/acctn5.log" "FAILED: --account claude-x: account: no such label claude-x; not running" "a failed --account quotes its stderr"
check "$(wc -l < "$T/claude.calls" | tr -d ' ')" "0" "  nothing started"
"$B/dispatch" $BR --repo "$T/repo" --at "$FUT 04:10" --force >/dev/null 2>&1; check "$?" "2" "--force without --account LABEL is refused"
"$B/dispatch" $BR --repo "$T/repo" --at "$FUT 04:10" --account acct-c >/dev/null
has "$(pl)" "<string>--account</string><string>acct-c</string>" "--account travels in the plist"
: > "$T/ssh.calls"
DISPATCH_ACCOUNT="$T/acct" "$B/dispatch" $BR --repo "$HOME/projects/other" --on buildbox --at reset+5 --account acct-c --dry-run >/dev/null 2>&1
has "$T/ssh.calls" "--at @$((EP + 300)) " "--at reset with a label: that row's weekly reset"
has "$T/ssh.calls" "--account acct-c --dry-run" "  and --account crosses to the peer"
# trust is the picked dir's: trusted in ~/.claude.json, not in ~/.acct-c's
printf '{"projects": {"%s": {"hasTrustDialogAccepted": true}}}' "$T/repo" > "$HOME/.claude.json"
printf '{"projects": {}}' > "$HOME/.acct-c/.claude.json"
: > "$T/claude.calls"
: > "$T/trust.calls"
DISPATCH_TRUST="$T/trust" STUB_RUN=work STUB_ACCT=f DISPATCH_ACCOUNT="$T/acct" DISPATCH_HOST=buildbox DISPATCH_LOG="$HOME/acct8.log" "$B/dispatch" $BR --repo "$T/repo"
has "$HOME/acct8.log" "not trusted: $T/repo — trusting it" "a repo trusted under ~/.claude but not under the picked dir → trusted there"
has "$T/trust.calls" "trust $HOME/.acct-c/.claude.json" "  in the picked dir"
rm "$HOME/.claude.json"
STUB_ACCT=f DISPATCH_ACCOUNT="$T/acct" "$B/dispatch" $BR --repo "$T/repo" --dry-run | grep -qF "account acct-c" && echo "  ok   a dry run names the account" || { echo "  FAIL dry run account"; fails=$((fails+1)); }

echo "--account bound: the primary, for work the account owns (hooks/design_route.py, 2026-10-10)"
: > "$T/env.calls"; : > "$T/acct.calls"
STUB_ACCT=acct-a DISPATCH_LOG="$HOME/acct9.log" AR --account bound
has "$HOME/acct9.log" "== account acct-a: week 20% < 95%" "bound: the pick's row is logged"
has "$T/acct.calls" "account pick --bound --repo $T/repo --json" "  asked as pick --bound, with the repo"
grep -q "^DISPATCH_PIN=bound$" "$T/env.calls"; check "$?" "0" "  and the run carries DISPATCH_PIN=bound, for its --next"
: > "$T/env.calls"
STUB_ACCT=f DISPATCH_LOG="$HOME/acct10.log" AR
grep -q "^DISPATCH_PIN=" "$T/env.calls"; check "$?" "1" "an auto run carries no pin"
: > "$T/claude.calls"
STUB_ACCT=short DISPATCH_LOG="$HOME/acct11.log" AR --account bound
has "$HOME/acct11.log" "FAILED: no account may run this now" "bound with no room this week: FAILED, as auto"
check "$(wc -l < "$T/claude.calls" | tr -d ' ')" "0" "  nothing started"
"$B/dispatch" $BR --repo "$T/repo" --at "$FUT 04:10" --account bound --force >/dev/null 2>&1; check "$?" "2" "--force with bound is refused"
STUB_ACCT=acct-a DISPATCH_ACCOUNT="$T/acct" "$B/dispatch" $BR --repo "$T/repo" --at "$FUT 04:10" --account bound >/dev/null
has "$(pl)" "<string>--account</string><string>bound</string>" "bound travels in the plist"
STUB_NOISE="account: a warning" STUB_ACCT=short DISPATCH_ACCOUNT="$T/acct" "$B/dispatch" $BR --repo "$T/repo" --at "$FUT 04:10" --account bound > "$T/out" 2>&1; check "$?" "1" "bound scheduled with no room: refused now"
has "$T/out" "the primary has no room now (account: a warning {\"account\": null" "  quoting the account's stderr, then its answer"

echo "--fallback here: the peer first, this Mac when it cannot take it (2026-10-10)"
export DISPATCH_ACCOUNT="$T/acct"   # never the real bin/account: bound picks --cached when scheduling
plo() { ls "$HOME"/Library/LaunchAgents/org.example.claude.dispatch.other.demo.[0-9]*.plist 2>/dev/null; }
OB() { "$B/dispatch" $BR --repo "$HOME/projects/other" --on buildbox "$@"; }
"$B/dispatch" $BR --repo "$T/repo" --at "@$EP" --fallback here >/dev/null 2>&1; check "$?" "2" "--fallback without --on is refused"
OB --at "@$EP" --fallback there >/dev/null 2>&1; check "$?" "2" "--fallback takes only here"
OB --cancel --fallback here >/dev/null 2>&1; check "$?" "2" "--fallback with --cancel is refused"
: > "$T/ssh.calls"
OB --at "@$EP" --fallback here --account bound >/dev/null 2>&1; check "$?" "0" "reachable: scheduled on the peer"
has "$T/ssh.calls" "-o ConnectTimeout=10 -o BatchMode=yes buildbox-ssh" "  after a 10-second probe"
has "$T/ssh.calls" 'grep -qs -- "pick --bound" "$(head -1 "${REGATTA_CONFIG:-$HOME/.config/regatta}/home" 2>/dev/null)/modules/wharf-runs/bin/dispatch"' "  the peer's dispatch checked for bound (its core's module)"
has "$T/ssh.calls" "--account bound" "  bound crosses to the peer"
check "$(plo | wc -l | tr -d ' ')" "0" "  and nothing here"
STUB_PROBE_RC=255 OB --at "@$EP" --fallback here --account bound > "$T/out" 2>&1; check "$?" "0" "unreachable (probe 255): scheduled here instead"
has "$T/out" "buildbox is unreachable (ssh exit 255); scheduling it on this Mac instead" "  saying so"
has "$(plo)" "<string>--account</string><string>bound</string>" "  with the same account"
rm -f $(plo)
STUB_PROBE_RC=3 OB --at "@$EP" --fallback here --account bound > "$T/out" 2>&1; check "$?" "0" "a peer whose dispatch predates bound (3): here instead"
check "$(plo | wc -l | tr -d ' ')" "1" "  scheduled here"
rm -f $(plo)
NOW1=$(( $(date +%s) + 30 ))
STUB_PROBE_RC=255 OB --at "@$NOW1" --fallback here >/dev/null 2>&1; check "$?" "0" "an epoch 30 s out, fallen back: moved to 90 s, not refused as past"
rm -f $(plo)
STUB_PROBE_RC=1 OB --at "@$EP" --fallback here >/dev/null 2>&1; check "$?" "1" "any other probe failure: not scheduled anywhere"
check "$(plo | wc -l | tr -d ' ')" "0" "  nothing here"
STUB_SSH_RC=1 OB --at "@$EP" --fallback here >/dev/null 2>&1; check "$?" "1" "probe ok, then the peer's own refusal: stands, no fallback"
check "$(plo | wc -l | tr -d ' ')" "0" "  nothing here"
mkdir -p "$HOME/projects/live"; git -C "$HOME/projects/live" init -q; printf -- '- physical: a sweep\n' > "$HOME/projects/live/AGENTS.md"
git -C "$HOME/projects/live" remote add origin "$T/origin.git" 2>/dev/null
STUB_PROBE_RC=255 "$B/dispatch" $BR --repo "$HOME/projects/live" --on buildbox --at "@$EP" --fallback here > "$T/out" 2>&1; check "$?" "2" "fallen back for a repo not physical: none: refused here, as a local schedule is"
STUB_SSH_RC=255 OB --at "@$EP" >/dev/null 2>&1; check "$?" "255" "without --fallback: no probe, the ssh failure as before"
: > "$T/ssh.calls"
OB --at "@$EP" --account acct-c >/dev/null 2>&1
grep -q "pick --bound" "$T/ssh.calls"; check "$?" "1" "a label crosses without the bound guard"
STUB_ACCT=short "$B/dispatch" $BR --repo "$T/repo" --at "$FUT 04:10" --account bound > "$T/out" 2>&1; check "$?" "1" "bound, the primary out of room now: refused when scheduling"
has "$T/out" "the primary has no room now" "  saying so, with --at reset as the way"
STUB_ACCT=short "$B/dispatch" $BR --repo "$T/repo" --at reset+5 --account bound > "$T/out" 2>&1
check "$(grep -c 'no room now' "$T/out")" "0" "  but --at reset waits for it: no room check"
: > "$T/claude.calls"; STUB_ACCT=acct-a DISPATCH_LOG="$HOME/acct12.log" AR --account bound
has "$T/claude.calls" "Artifact mcp__claude-in-chrome" "a bound run may publish Artifacts and use Chrome"
unset DISPATCH_ACCOUNT

echo "--yolo: the unattended one-pass run (E12) — the gate in the prompt, the launch after"
: > "$T/claude.calls"
"$B/dispatch" $BR --repo "$T/repo" --at "$FUT 04:10" --yolo >/dev/null
has "$(pl)" "<string>--yolo</string>" "a scheduled run carries --yolo to its fire"
"$B/dispatch" $BR --repo "$T/repo" --cancel >/dev/null
: > "$T/ssh.calls"
env -u DISPATCH_LABEL "$B/dispatch" $BR --repo "$HOME/projects/other" --at @$(( $(date +%s) + 86400 )) --on buildbox --yolo >/dev/null 2>&1
grep -q -- "--yolo" "$T/ssh.calls"; check "$?" "0" "…and so does one scheduled on the peer"
"$B/dispatch" $BR --repo "$T/repo" --probe --yolo >/dev/null 2>&1; check "$?" "2" "--yolo with --probe: refused"
"$B/dispatch" --start "/x" "$T/repo" "n" --yolo >/dev/null 2>&1; check "$?" "2" "--yolo with --start: refused (autofinish-run's own)"
"$B/dispatch" --launch "/x" "$T/repo" "n" --yolo > "$T/out" 2>&1; check "$?" "2" "  …and with --launch, its old name kept as an alias for a week (S1 of docs/wharf-rename-2026-10-16.md)"
has "$T/out" "dispatch: --start takes no BRANCH" "  …refused as --start: the alias is the same flag"
"$B/dispatch" $BR --repo "$T/repo" --yolo --dry-run | grep -qF -- "--yolo: memo yolo's gate in the prompt, then autofinish-run --by yolo" \
  && echo "  ok   a dry run says the gate and the launch" || { echo "  FAIL yolo dry run"; fails=$((fails+1)); }
# the build session, standing in: writes an architect doc with one D-item marked $YMARK, puts it
# through the gate the prompt names, and commits, as a real session's checkpoint would
cat > "$T/yclaude" <<EOF
#!/bin/bash
echo "claude \$*" >> "$T/claude.calls"
mkdir -p docs
{ echo "# D"; echo; echo 'Written by \`architect\` (Fable 5.1, \`high\`) on 2026-10-08 for "t".'; echo; echo "## Decisions"; echo
  echo "- **D1 — Pick.** Context."; echo "  - A — one"; echo "  - B — two"; echo; echo "  Reversible: \$YMARK"; echo
  [ -n "\${YREC-B}" ] && { echo "  ➤ Recommended: \${YREC-B}"; echo; }; echo "  ➤ Answer:"; echo
  [ -n "\${YDUP:-}" ] && { echo "- **D1 — Again.** Twice."; echo; echo "  ➤ Answer:"; echo; }
  echo "---"; echo; echo "## Open feedback"; } > docs/d.md
python3 "$KEEL" \${YCMD:-yolo} docs/d.md >> "$T/claude.calls" 2>&1; echo "memo exit \$?" >> "$T/claude.calls"
if [ -n "\${YNODOC:-}" ]; then git rm -q --cached --ignore-unmatch docs/d.md; rm -f docs/d.md; echo x > note.txt; git add note.txt; else git add docs/d.md; fi
git -c user.email=t@t -c user.name=t commit -qm "doc" \${YDEPLOY:+-m "Deployed: \$YDEPLOY"} >/dev/null
[ -n "\${YLOWER:-}" ] && sh -c "\$YLOWER"   # S3b: the owner lowers the mode while the run builds
# its transcript, where yolo_launch reads the last reply (\$YREPLY)
sid=""; prev=""; for a in "\$@"; do [ "\$prev" = --session-id ] && sid="\$a"; prev="\$a"; done
mkdir -p "\$HOME/.claude/projects/t"
if [ -n "\${YRAW:-}" ]; then printf '%s\n' "\$YRAW" > "\$HOME/.claude/projects/t/\$sid.jsonl"; else
python3 -c 'import json, sys; print(json.dumps({"type": "assistant", "message": {"content": [{"type": "text", "text": sys.argv[1]}]}}, separators=(",", ":")))' "\${YREPLY:-Built.}" > "\$HOME/.claude/projects/t/\$sid.jsonl"; fi
EOF
cat > "$T/afrun" <<EOF
#!/bin/sh
echo "afrun \$*" >> "$T/af.calls"; echo "login \${CLAUDE_CONFIG_DIR:-unset} \${CLAUDE_CODE_OAUTH_TOKEN:-unset}" >> "$T/af.calls"; echo "autofinish-run: started"
EOF
chmod +x "$T/yclaude" "$T/afrun"
# origin/main, which the open-items test diffs against
git --git-dir="$T/repo/.git" send-pack "$T/origin.git" "main:refs/heads/main" >/dev/null 2>&1 || git --git-dir="$T/origin.git" update-ref refs/heads/main "$(git -C "$T/repo" rev-parse main)"
: > "$T/af.calls"
# the sweep's switch: armed on this Mac (yolo_launch skips the launch on a disarmed one)
export AUTOFINISH_STATE_DIR="$T/afstate"; mkdir -p "$AUTOFINISH_STATE_DIR"; echo '{"by": "t", "ts": 1}' > "$AUTOFINISH_STATE_DIR/armed"
YREC= YMARK=no DISPATCH_CLAUDE="$T/yclaude" DISPATCH_AUTOFINISH_RUN="$T/afrun" DISPATCH_LOG="$HOME/yolo-no.log" "$B/dispatch" $BR --repo "$T/repo" --headless --yolo
has "$T/claude.calls" "keel yolo <the doc>" "the brief carries the gate: the prompt names keel yolo"
has "$T/claude.calls" "Never write a 'Taken unattended' answer, or an item's Reversible: mark, by hand" "  and forbids writing its answers by hand"
has "$T/claude.calls" "Bash(git push:*)" "the build run keeps the denials: git push…"
has "$T/claude.calls" "Bash(*bin/pr merge*)" "  …bin/pr merge…"
has "$T/claude.calls" "never merge into main or launch" "  …and the prompt's never-launch line"
has "$T/claude.calls" "memo exit 3" "an item with no pick: keel yolo stops (exit 3)"
has "$HOME/yolo-no.log" "== yolo: no launch — open for Sam: docs/d.md D1" "  …and no launch starts: the log names the open item"
check "$(wc -c < "$T/af.calls" | tr -d ' ')" "0" "  autofinish-run never called"
: > "$T/claude.calls"
CLAUDE_CODE_OAUTH_TOKEN=build-login YMARK=yes DISPATCH_CLAUDE="$T/yclaude" DISPATCH_AUTOFINISH_RUN="$T/afrun" DISPATCH_LOG="$HOME/yolo-yes.log" "$B/dispatch" $BR --repo "$T/repo" --headless --yolo
has "$T/claude.calls" "memo exit 0" "every item Reversible: yes: memo yolo goes on"
# keel writes the yolo answer with its own name for the owner: only its fixed head is read here
grep -q "Taken unattended (" "$T/repo/.claude/worktrees/demo/docs/d.md"; check "$?" "0" "  the answer block holds the Taken unattended line"
has "$HOME/yolo-yes.log" "starting the launch: autofinish-run $T/repo/.claude/worktrees/demo --by yolo" "the build run ended clean: the launch starts"
has "$T/af.calls" "afrun $T/repo/.claude/worktrees/demo --rule M --by yolo" "  through autofinish-run --rule M --by yolo (S3b: the mode's start)"
has "$T/af.calls" "login unset unset" "  without the build's login: autofinish-run picks its own"
: > "$T/claude.calls"
YMARK=no DISPATCH_CLAUDE="$T/yclaude" DISPATCH_AUTOFINISH_RUN="$T/afrun" DISPATCH_LOG="$HOME/yolo-allway.log" "$B/dispatch" $BR --repo "$T/repo" --headless --yolo >/dev/null 2>&1
has "$T/claude.calls" "memo exit 0" "a Reversible: no item with a pick: keel yolo takes it too (skipper-modes D1, all the way)"
has "$HOME/yolo-allway.log" "starting the launch" "  …and the launch starts: it stops at a ready PR on /finish's side"
: > "$T/af.calls"
# the account pool: no row may run now (5h 90 % over window_max 50) — the gate stops, as the sweep's does
mkdir -p "$HOME/.claude-nr"
python3 - "$T/noacct.json" "$HOME/.claude-nr" "$(date +%s)" <<'PY'
import json, sys
f, home, now = sys.argv[1], sys.argv[2], float(sys.argv[3])
json.dump({"accounts": [{"label": "claude-nr", "home": home, "primary": True, "rules": {"window_max": 50}}]}, open(f, "w"))
json.dump({"at": now, "limits": {"five_hour": 90, "seven_day": 10, "five_hour_resets": now + 3600,
                                 "seven_day_resets": now + 3 * 86400, "locked": []}}, open(home + "/usage-probe.json", "w"))
PY
DISPATCH_ACCOUNT="$T/acct" ACCOUNTS_FILE="$T/noacct.json" ACCOUNT_CLAUDE=false YMARK=yes DISPATCH_CLAUDE="$T/yclaude" DISPATCH_AUTOFINISH_RUN="$T/afrun" DISPATCH_LOG="$HOME/yolo-noacct.log" "$B/dispatch" $BR --repo "$T/repo" --headless --yolo >/dev/null 2>&1
has "$HOME/yolo-noacct.log" "== yolo: no launch — no account may run it (claude-nr: " "no account in the pool may run it: no launch"
check "$(wc -c < "$T/af.calls" | tr -d ' ')" "0" "  autofinish-run never called"
: > "$T/af.calls"
echo dirt > "$T/repo/.claude/worktrees/demo/scratch-yolo"
YMARK=yes DISPATCH_CLAUDE="$T/yclaude" DISPATCH_AUTOFINISH_RUN="$T/afrun" DISPATCH_LOG="$HOME/yolo-dirty.log" "$B/dispatch" $BR --repo "$T/repo" --headless --yolo >/dev/null 2>&1
has "$HOME/yolo-dirty.log" "no launch" "a worktree left dirty: no launch"
check "$(wc -c < "$T/af.calls" | tr -d ' ')" "0" "  autofinish-run never called"
rm -f "$T/repo/.claude/worktrees/demo/scratch-yolo"
# the gates that fail closed (review of 2026-10-08)
YREPLY="Check fails on X.
SAM, THIS SESSION IS WAITING FOR YOU — the check fails on X" YMARK=yes DISPATCH_CLAUDE="$T/yclaude" DISPATCH_AUTOFINISH_RUN="$T/afrun" DISPATCH_LOG="$HOME/yolo-wait.log" "$B/dispatch" $BR --repo "$T/repo" --headless --yolo >/dev/null 2>&1
has "$HOME/yolo-wait.log" "== yolo: no launch — its last reply stops for Sam" "a build that ends WAITING: no launch"
mv "$AUTOFINISH_STATE_DIR/armed" "$T/armed.off"
YMARK=yes DISPATCH_CLAUDE="$T/yclaude" DISPATCH_AUTOFINISH_RUN="$T/afrun" DISPATCH_LOG="$HOME/yolo-disarmed.log" "$B/dispatch" $BR --repo "$T/repo" --headless --yolo >/dev/null 2>&1
has "$HOME/yolo-disarmed.log" "== yolo: no launch — autofinish is disarmed on this Mac" "autofinish disarmed here (the build Mac): no launch"
mv "$T/armed.off" "$AUTOFINISH_STATE_DIR/armed"
YDUP=1 YMARK=yes DISPATCH_CLAUDE="$T/yclaude" DISPATCH_AUTOFINISH_RUN="$T/afrun" DISPATCH_LOG="$HOME/yolo-dup.log" "$B/dispatch" $BR --repo "$T/repo" --headless --yolo >/dev/null 2>&1
has "$HOME/yolo-dup.log" "open for Sam: docs/d.md (memo could not parse it)" "a doc memo cannot parse counts as open"
"$B/dispatch" $BR --repo "$T/repo" --at "$FUT 04:10" >/dev/null
YMARK=yes DISPATCH_CLAUDE="$T/yclaude" DISPATCH_AUTOFINISH_RUN="$T/afrun" DISPATCH_LOG="$HOME/yolo-next.log" "$B/dispatch" $BR --repo "$T/repo" --headless --yolo >/dev/null 2>&1
has "$HOME/yolo-next.log" "== yolo: no launch — a next step is scheduled on this branch" "a next step waiting on the branch: no launch"
"$B/dispatch" $BR --repo "$T/repo" --cancel >/dev/null
YREPLY="Reviewers started.
SAM, THIS SESSION IS WAITING FOR SOMETHING — the two reviewers, then dispatch's launch" YMARK=yes DISPATCH_CLAUDE="$T/yclaude" DISPATCH_AUTOFINISH_RUN="$T/afrun" DISPATCH_LOG="$HOME/yolo-pend.log" "$B/dispatch" $BR --repo "$T/repo" --headless --yolo >/dev/null 2>&1
has "$HOME/yolo-pend.log" "== yolo: no launch — its last reply waits on its own work" "a build that ends WAITING FOR SOMETHING on its own work: no launch"
newest_launch() { python3 -c 'import glob, json, os, sys; f = max(glob.glob(sys.argv[1] + "/*.json"), key=os.path.getmtime); print(json.load(open(f)).get("launch"))' "$HOME/Library/Logs/claude-weekly/run-seed-runs"; }
check "$(newest_launch | grep -cF 'no launch — its last reply waits on its own work: ')" "1" "  the run record keeps why, for helm's card (review D1)"
# review D3: the gate's reader crashing (a transcript entry whose message is no object) is a reason, never an empty pass
YRAW='{"type":"assistant","message":"x"}' YMARK=yes DISPATCH_CLAUDE="$T/yclaude" DISPATCH_AUTOFINISH_RUN="$T/afrun" DISPATCH_LOG="$HOME/yolo-crash.log" "$B/dispatch" $BR --repo "$T/repo" --headless --yolo >/dev/null 2>&1
has "$HOME/yolo-crash.log" "== yolo: no launch — its launch gate failed (exit 1)" "a gate that crashes: no launch (review D3, it failed open)"
# Claude Code's own <synthetic> entry after the run's last reply is not its reply (the rotation's finish review)
YRAW='{"type":"assistant","message":{"content":[{"type":"text","text":"SAM, THIS SESSION IS WAITING FOR YOU — the check fails on X"}]}}
{"type":"assistant","message":{"model":"<synthetic>","content":[{"type":"text","text":"No response requested."}]}}' YMARK=yes DISPATCH_CLAUDE="$T/yclaude" DISPATCH_AUTOFINISH_RUN="$T/afrun" DISPATCH_LOG="$HOME/yolo-synth.log" "$B/dispatch" $BR --repo "$T/repo" --headless --yolo >/dev/null 2>&1
has "$HOME/yolo-synth.log" "== yolo: no launch — its last reply stops for Sam" "  a <synthetic> entry after a WAITING line: the WAITING line is read"
check "$(wc -c < "$T/af.calls" | tr -d ' ')" "0" "  autofinish-run never called by any of them"
# the hand-over (yolo-launch, 2026-10-25): the prompt names one WAITING FOR SOMETHING line, and a run
# ending on it, or on a free form naming dispatch's launch first (the two runs of 2026-10-24), is handed
: > "$T/claude.calls"
YREPLY="Built.
SAM, THIS SESSION IS WAITING FOR SOMETHING — dispatch's launch (autofinish-run)" YMARK=yes DISPATCH_CLAUDE="$T/yclaude" DISPATCH_AUTOFINISH_RUN="$T/afrun" DISPATCH_LOG="$HOME/yolo-hand.log" "$B/dispatch" $BR --repo "$T/repo" --headless --yolo >/dev/null 2>&1
has "$T/claude.calls" "end on exactly \`SAM, THIS SESSION IS WAITING FOR SOMETHING — dispatch's launch (autofinish-run)\`" "the yolo prompt names the hand-over line"
has "$T/claude.calls" "and keel yolo took every item it met (exit 0, or no D-list at all), end on exactly" "  only when keel yolo stopped at nothing (review D4)"
has "$T/claude.calls" "no WAITING line asks it — this run's mode hands the landing to dispatch" "  and the base text no longer tells it to ask about landing (review D4)"
has "$HOME/yolo-hand.log" "starting the launch: autofinish-run $T/repo/.claude/worktrees/demo --by yolo" "  a build ending on it: the launch starts"
check "$(newest_launch)" "started: autofinish-run --rule M --by yolo" "  and the run record says it started"
: > "$T/af.calls"
YREPLY="Built.
**SAM, THIS SESSION IS WAITING FOR SOMETHING — dispatch to start the yolo launch of B14b ([x#1](https://example.com/x/pull/1))**" YMARK=yes DISPATCH_CLAUDE="$T/yclaude" DISPATCH_AUTOFINISH_RUN="$T/afrun" DISPATCH_LOG="$HOME/yolo-hand2.log" "$B/dispatch" $BR --repo "$T/repo" --headless --yolo >/dev/null 2>&1
has "$T/af.calls" "afrun $T/repo/.claude/worktrees/demo --rule M --by yolo" "  and on a free form naming dispatch's launch first (b14b-shrink's words)"
: > "$T/af.calls"
YREPLY="Built.
SAM, THIS SESSION IS WAITING FOR SOMETHING — dispatch's yolo launch (autofinish-run --by yolo), which starts once this run ends with the tree clean" YMARK=yes DISPATCH_CLAUDE="$T/yclaude" DISPATCH_AUTOFINISH_RUN="$T/afrun" DISPATCH_LOG="$HOME/yolo-hand3.log" "$B/dispatch" $BR --repo "$T/repo" --headless --yolo >/dev/null 2>&1
has "$T/af.calls" "afrun $T/repo/.claude/worktrees/demo --rule M --by yolo" "  and on hookwatch-date's words (review D5)"
: > "$T/claude.calls"
DISPATCH_CLAUDE="$T/yclaude" YMARK=yes DISPATCH_AUTOFINISH_RUN="$T/afrun" DISPATCH_LOG="$HOME/yolo-off.log" "$B/dispatch" $BR --repo "$T/repo" --headless
grep -q "keel yolo <the doc>" "$T/claude.calls"; check "$?" "1" "without --yolo: no gate in the prompt"
has "$T/claude.calls" "no D-item for it — end with the WAITING line asking it" "  and the landing is asked on the WAITING line, as before"
grep -q "== yolo" "$HOME/yolo-off.log"; check "$?" "1" "  and no launch"
# the launch's side: autofinish-run --by yolo asks /finish for --yolo, which follows the repo's key
grep -q '\*\*Without `--hold`\*\* — the mode is the' "$FINISH_SKILL"; check "$?" "0" "/finish --yolo|--dnd: without --hold the mode is the yes (S3b)…"
grep -q 'no step 11.4 — `bin/pr merge` is denied to this run' "$FINISH_SKILL"; check "$?" "0" "  …with --hold, a ready PR held from automerge"

echo "--mode (skipper-modes S1, S3): the hint in the plist, the mode read again at fire time, the gate per mode"
"$B/dispatch" $BR --repo "$T/repo" --mode bogus >/dev/null 2>&1; check "$?" "2" "--mode takes default, ask, dnd or yolo"
"$B/dispatch" $BR --repo "$T/repo" --mode dnd --yolo >/dev/null 2>&1; check "$?" "2" "--yolo is mode yolo: beside --mode dnd, refused"
"$B/dispatch" --start "/x" "$T/repo" "n" --mode ask >/dev/null 2>&1; check "$?" "2" "--mode with --start: refused (a launch has no mode)"
"$B/dispatch" $BR --repo "$T/repo" --probe --mode ask >/dev/null 2>&1; check "$?" "2" "--mode with --probe: refused"
"$B/dispatch" $BR --repo "$T/repo" --at "$FUT 04:10" --mode dnd >/dev/null
has "$(pl)" "<key>DISPATCH_MODE</key><string>dnd</string>" "a scheduled run carries its mode in the plist (the hint)"
"$B/dispatch" $BR --repo "$T/repo" --cancel >/dev/null
"$B/dispatch" $BR --repo "$T/repo" --at "$FUT 04:10" --mode yolo >/dev/null
has "$(pl)" "<string>--yolo</string>" "mode yolo is --yolo"
"$B/dispatch" $BR --repo "$T/repo" --cancel >/dev/null
env -u DISPATCH_LABEL DISPATCH_MODE=ask "$B/dispatch" $BR --repo "$T/repo" --at "$FUT 04:10" >/dev/null
grep -q "DISPATCH_MODE" "$(pl)"; check "$?" "1" "a session's own DISPATCH_MODE is no --mode for what it schedules (only a --next keeps it)"
"$B/dispatch" $BR --repo "$T/repo" --cancel >/dev/null
: > "$T/ssh.calls"
env -u DISPATCH_LABEL "$B/dispatch" $BR --repo "$HOME/projects/other" --at @$(( $(date +%s) + 86400 )) --on buildbox --mode ask >/dev/null 2>&1
grep -q -- "--mode ask" "$T/ssh.calls"; check "$?" "0" "one scheduled on the build Mac carries --mode"
# the ship on this Mac: `--mode` writes its task's mode (plan.json is the authority)
export PLANS_DIR="$T/modeplans"; mkdir -p "$PLANS_DIR/mship"
echo '{"id": "mship", "tasks": {}}' > "$PLANS_DIR/mship/plan.json"
env -u DISPATCH_LABEL DISPATCH_SHIP=mship "$B/dispatch" $BR --repo "$T/repo" --at "$FUT 04:10" --mode dnd >/dev/null 2>&1
check "$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["tasks"]["demo"]["mode"])' "$PLANS_DIR/mship/plan.json")" "dnd" \
  "--mode with a ship on this Mac: written to plan.json's task"
"$B/dispatch" $BR --repo "$T/repo" --cancel >/dev/null
# the run: mode dnd (the plist's hint), the gate in the prompt, keel yolo --dnd taking a Reversible: no pick
: > "$T/claude.calls"; : > "$T/af.calls"
YMARK=no YCMD="yolo --dnd" DISPATCH_MODE=dnd DISPATCH_CLAUDE="$T/yclaude" DISPATCH_AUTOFINISH_RUN="$T/afrun" DISPATCH_LOG="$HOME/mode-dnd.log" \
  "$B/dispatch" $BR --repo "$T/repo" --headless >/dev/null 2>&1
has "$HOME/mode-dnd.log" "== mode dnd" "mode dnd from the plist: read at fire time, logged"
has "$T/claude.calls" "keel yolo --dnd <the doc>" "  the prompt's gate is keel yolo --dnd"
has "$T/claude.calls" "relay each one as above (ask relay <doc> <Dn>)" "  …and its held items are relayed"
has "$T/claude.calls" "when this is the branch's last step (no dispatch --next scheduled), nothing was relayed and the work is committed, end on exactly \`SAM, THIS SESSION IS WAITING FOR SOMETHING — dispatch's launch (autofinish-run)\`" "  …and, as the last step with nothing relayed, it ends on the hand-over line"
has "$T/claude.calls" "A step that scheduled the next one waits for no launch: it ends on \`SAM, THIS SESSION IS WAITING FOR SOMETHING — <the next step, in one line>\`" "  …a step with a next one scheduled does not (review D4)"
grep -q "Taken unattended (Sam's dnd, " "$T/repo/.claude/worktrees/demo/docs/d.md"; check "$?" "0" "  a Reversible: no pick taken as the owner's dnd"
grep -q "== yolo" "$HOME/mode-dnd.log"; check "$?" "1" "  …no yolo launch: dnd is not yolo"
has "$HOME/mode-dnd.log" "== dnd: the build run ended clean — starting the launch: autofinish-run $T/repo/.claude/worktrees/demo --by dnd" \
  "  …but a dnd launch (S3b, the owner: \"dnd: I want to automerge as well\")"
has "$T/af.calls" "afrun $T/repo/.claude/worktrees/demo --rule M --by dnd" "  through autofinish-run --rule M --by dnd, which holds the slice itself"
: > "$T/af.calls"
YREPLY="Built.
SAM, THIS SESSION IS WAITING FOR SOMETHING — dispatch's launch (autofinish-run)" YMARK=yes YCMD="yolo --dnd" DISPATCH_MODE=dnd DISPATCH_CLAUDE="$T/yclaude" DISPATCH_AUTOFINISH_RUN="$T/afrun" \
  DISPATCH_LOG="$HOME/mode-dnd-hand.log" "$B/dispatch" $BR --repo "$T/repo" --headless >/dev/null 2>&1
has "$T/af.calls" "afrun $T/repo/.claude/worktrees/demo --rule M --by dnd" "a dnd build ending on the hand-over line: the launch starts (review D5)"
: > "$T/af.calls"
# the follow-ups' landing review, item 1: a deployed build is the sweep's rule L unless it holds a taken doc
DW="$T/repo/.claude/worktrees/demo"; pre=$(git -C "$DW" rev-parse HEAD)
YNODOC=1 YDEPLOY="the service" YMARK=yes YCMD="yolo --dnd" DISPATCH_MODE=dnd DISPATCH_CLAUDE="$T/yclaude" DISPATCH_AUTOFINISH_RUN="$T/afrun" \
  DISPATCH_LOG="$HOME/mode-dnd-live.log" "$B/dispatch" $BR --repo "$T/repo" --headless >/dev/null 2>&1
has "$HOME/mode-dnd-live.log" "== dnd: deployed (the service) with no taken doc — rule L's start, as the sweep's" \
  "a deployed dnd build with no taken doc: rule L's start (the follow-ups' landing review, item 1)"
has "$T/af.calls" "afrun $DW --rule L --by sweep" "  through autofinish-run --rule L --by sweep: at once, no held slice"
git -C "$DW" reset -q --hard "$pre"; : > "$T/af.calls"
YDEPLOY="the service" YMARK=yes YCMD="yolo --dnd" DISPATCH_MODE=dnd DISPATCH_CLAUDE="$T/yclaude" DISPATCH_AUTOFINISH_RUN="$T/afrun" \
  DISPATCH_LOG="$HOME/mode-dnd-taken.log" "$B/dispatch" $BR --repo "$T/repo" --headless >/dev/null 2>&1
has "$T/af.calls" "afrun $DW --rule M --by dnd" "  deployed with a taken doc: rule M, which applies the held slice (as the sweep's start)"
git -C "$DW" reset -q --hard "$pre"; : > "$T/af.calls"
mkdir -p "$PLANS_DIR/lship"; echo '{"id": "lship", "mode": "dnd", "tasks": {}}' > "$PLANS_DIR/lship/plan.json"
YLOWER="echo '{\"id\": \"lship\", \"mode\": \"default\", \"tasks\": {}}' > $PLANS_DIR/lship/plan.json" YMARK=yes YCMD="yolo --dnd" DISPATCH_SHIP=lship \
  DISPATCH_CLAUDE="$T/yclaude" DISPATCH_AUTOFINISH_RUN="$T/afrun" DISPATCH_LOG="$HOME/mode-lowered.log" "$B/dispatch" $BR --repo "$T/repo" --headless >/dev/null 2>&1
has "$HOME/mode-lowered.log" "== mode dnd" "a ship in dnd at the start…"
has "$HOME/mode-lowered.log" "== dnd: no launch — the mode is now default (plan.json)" "  …lowered while the run built: no launch (the mode is read again at launch)"
check "$(wc -c < "$T/af.calls" | tr -d ' ')" "0" "  autofinish-run never called"
rm -rf "$PLANS_DIR/lship"
echo "  raising a mode (S3b): only the owner raises it — an unattended caller is refused"
env -u DISPATCH_LABEL -u DISPATCH_SHIP CLAUDE_UNATTENDED=dispatch DISPATCH_MODE=default "$B/dispatch" claude/h/2026-10-21-fresh --repo "$T/repo" --mode dnd --dry-run > "$T/raise.out" 2>&1
check "$?" "2" "--mode dnd from a default run, for a branch with no mode of its own: refused (the caller's mode is the bar)"
has "$T/raise.out" "only the owner raises a mode" "  saying why"
env -u DISPATCH_LABEL -u DISPATCH_SHIP CLAUDE_UNATTENDED=dispatch DISPATCH_MODE=dnd "$B/dispatch" $BR --repo "$T/repo" --yolo --dry-run > /dev/null 2>&1
check "$?" "2" "--yolo from a dnd run: refused"
env -u DISPATCH_LABEL -u DISPATCH_SHIP CLAUDE_UNATTENDED=dispatch DISPATCH_MODE=dnd "$B/dispatch" $BR --repo "$T/repo" --mode dnd --dry-run > /dev/null 2>&1
check "$?" "0" "--mode dnd from a dnd run: kept, no raise"
env -u DISPATCH_LABEL -u DISPATCH_SHIP CLAUDE_UNATTENDED=dispatch DISPATCH_MODE=yolo "$B/dispatch" $BR --repo "$T/repo" --mode ask --dry-run > /dev/null 2>&1
check "$?" "0" "--mode ask from a yolo run: lowering is free"
env -u DISPATCH_LABEL -u DISPATCH_SHIP -u CLAUDE_UNATTENDED -u DISPATCH_MODE "$B/dispatch" $BR --repo "$T/repo" --mode yolo --dry-run > /dev/null 2>&1
check "$?" "0" "the owner's own --mode yolo (no CLAUDE_UNATTENDED): allowed"
mkdir -p "$PLANS_DIR/sship"
echo '{"id": "sship", "tasks": {"sib": {"branch": "claude/h/2026-10-21-sib", "mode": "ask"}}}' > "$PLANS_DIR/sship/plan.json"
env -u DISPATCH_LABEL -u DISPATCH_SHIP CLAUDE_UNATTENDED=dispatch DISPATCH_MODE=dnd "$B/dispatch" claude/h/2026-10-21-sib --repo "$T/repo" --mode dnd --dry-run > "$T/raise.out" 2>&1
check "$?" "2" "--mode dnd from a dnd run on a sibling the owner left in ask: refused, the target's mode is the bar (landing review 5)"
python3 -c 'import json, sys; json.dump({"id": "sship", "tasks": {"other": {"mode": "ask"}}}, open(sys.argv[1], "w"))' "$PLANS_DIR/sship/plan.json"
env -u DISPATCH_LABEL CLAUDE_UNATTENDED=dispatch DISPATCH_MODE=dnd DISPATCH_SHIP=sship "$B/dispatch" claude/h/2026-10-21-other --repo "$T/repo" --at "$FUT 04:10" --mode dnd > "$T/raise.out" 2>&1
check "$?" "2" "  the ship's task in ask, no branch on it: ship_mode refuses before it writes"
check "$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["tasks"]["other"]["mode"])' "$PLANS_DIR/sship/plan.json")" "ask" "  …the task keeps ask"
python3 -c 'import json, sys; json.dump({"id": "sship", "tasks": {}}, open(sys.argv[1], "w"))' "$PLANS_DIR/sship/plan.json"
env -u DISPATCH_LABEL -u CLAUDE_UNATTENDED -u DISPATCH_MODE DISPATCH_SHIP=sship "$B/dispatch" $BR --repo "$T/repo" --at "$FUT 04:10" --yolo >/dev/null 2>&1
check "$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["tasks"]["demo"].get("mode"))' "$PLANS_DIR/sship/plan.json")" "yolo" \
  "--yolo with a ship on this Mac: written to plan.json as --mode yolo is (landing review 11)"
"$B/dispatch" $BR --repo "$T/repo" --cancel >/dev/null
rm -rf "$PLANS_DIR/sship"
newest_rec() { python3 -c 'import glob, json, os, sys; f = max(glob.glob(sys.argv[1] + "/*.json"), key=os.path.getmtime); print(json.load(open(f)).get(sys.argv[2]))' "$HOME/Library/Logs/claude-weekly/run-seed-runs" "$1"; }
check "$(newest_rec task_mode) $(newest_rec mode)" "dnd headless" "  the record: task_mode beside mode (rc or headless)"
: > "$T/claude.calls"; : > "$T/env.calls"
DISPATCH_MODE=ask DISPATCH_LOG="$HOME/mode-ask.log" "$B/dispatch" $BR --repo "$T/repo" --headless >/dev/null 2>&1
has "$T/claude.calls" "The owner's ask mode (mode ask" "mode ask: the prompt says nothing answers but the owner"
grep -qE "keel yolo (--dnd )?<the doc>" "$T/claude.calls"; check "$?" "1" "  …and carries no keel yolo gate"
has "$T/env.calls" "DISPATCH_MODE=ask" "  the session's environment carries the mode (helmlib.run_mode reads it)"
# plan.json wins over the hint, at fire time: the task's mode, else the ship's
python3 -c 'import json, sys; json.dump({"id": "mship", "mode": "ask", "tasks": {"demo": {"mode": "default"}}}, open(sys.argv[1], "w"))' "$PLANS_DIR/mship/plan.json"
: > "$T/claude.calls"
DISPATCH_SHIP=mship DISPATCH_MODE=dnd DISPATCH_LOG="$HOME/mode-plan.log" "$B/dispatch" $BR --repo "$T/repo" --headless >/dev/null 2>&1
has "$HOME/mode-plan.log" "== mode default" "a ship's task mode beats the plist's hint (helm mode mid-flight)"
grep -q "keel yolo --dnd" "$T/claude.calls"; check "$?" "1" "  …so the dnd gate is gone from the prompt"
python3 -c 'import json, sys; json.dump({"id": "mship", "mode": "ask", "tasks": {}}, open(sys.argv[1], "w"))' "$PLANS_DIR/mship/plan.json"
DISPATCH_SHIP=mship DISPATCH_MODE=yolo DISPATCH_LOG="$HOME/mode-ship.log" "$B/dispatch" $BR --repo "$T/repo" --headless >/dev/null 2>&1
has "$HOME/mode-ship.log" "== mode ask" "no task mode: the ship's mode beats the hint"
grep -q "== yolo" "$HOME/mode-ship.log"; check "$?" "1" "  …a yolo hint overruled by the ship is no yolo run: no launch"
# follow-ups item 5: a `helm mode --branch` lowering is read at fire time and at launch, before plan.json;
# every entry names its repo (the follow-ups' landing review, item 7), keyed as helmlib keys it
BK=$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import helmlib; print(helmlib.branch_key(sys.argv[2], sys.argv[3]))' "$B/../../helm/bin" "$BR" "$T/repo")
# — under the ship's mode, a ceiling since the follow-ups' code review: the ship in dnd, the entry lowers it
printf '{"%s": {"mode": "default", "ts": 1}}\n' "$BK" > "$PLANS_DIR/branch-modes.json"
python3 -c 'import json, sys; json.dump({"id": "mship", "mode": "dnd", "tasks": {}}, open(sys.argv[1], "w"))' "$PLANS_DIR/mship/plan.json"
DISPATCH_SHIP=mship DISPATCH_MODE=dnd DISPATCH_LOG="$HOME/mode-branch-dnd.log" "$B/dispatch" $BR --repo "$T/repo" --headless >/dev/null 2>&1
has "$HOME/mode-branch-dnd.log" "== mode default" "a helm mode --branch on the run's branch lowers the ship's dnd and the hint at fire time (follow-ups item 5)"
python3 -c 'import json, sys; json.dump({"id": "mship", "mode": "ask", "tasks": {}}, open(sys.argv[1], "w"))' "$PLANS_DIR/mship/plan.json"
DISPATCH_SHIP=mship DISPATCH_MODE=dnd DISPATCH_LOG="$HOME/mode-branch.log" "$B/dispatch" $BR --repo "$T/repo" --headless >/dev/null 2>&1
has "$HOME/mode-branch.log" "== mode ask" "  the same entry over a ship in ask: the ship's ceiling (the follow-ups' code review)"
rm -f "$PLANS_DIR/branch-modes.json"; : > "$T/af.calls"
YLOWER="printf '{\"%s\": {\"mode\": \"default\", \"ts\": 1}}' '$BK' > $PLANS_DIR/branch-modes.json" YMARK=yes YCMD="yolo --dnd" DISPATCH_MODE=dnd \
  DISPATCH_CLAUDE="$T/yclaude" DISPATCH_AUTOFINISH_RUN="$T/afrun" DISPATCH_LOG="$HOME/mode-branch-low.log" "$B/dispatch" $BR --repo "$T/repo" --headless >/dev/null 2>&1
has "$HOME/mode-branch-low.log" "== dnd: no launch — the mode is now default" "  …and a lowering while the run built stops its launch (mode_now)"
check "$(wc -c < "$T/af.calls" | tr -d ' ')" "0" "    autofinish-run never called"
printf '{"%s": {"mode": "default", "ts": 1}, "%s|%s": {"mode": "ask", "ts": 1}}\n' "$BK" "/elsewhere/repo" "$BR" > "$PLANS_DIR/branch-modes.json"
env -u DISPATCH_LABEL "$B/dispatch" $BR --repo "$T/repo" --at "$FUT 04:10" --mode dnd > /dev/null 2> "$T/yield.err"
has "$T/yield.err" "the helm mode --branch entry on $BR (default) gives way to --mode dnd, the newer word" \
  "a newer dispatch --mode on the branch replaces its older helm mode --branch entry (item 7)"
check "$(python3 -c 'import json, sys; d = json.load(open(sys.argv[1])); print(d[sys.argv[2]]["mode"], d["/elsewhere/repo|" + sys.argv[3]]["mode"])' "$PLANS_DIR/branch-modes.json" "$BK" "$BR")" "dnd ask" \
  "  replaced by the new word, not dropped (the second landing review); a same-named branch of another repo keeps its entry"
"$B/dispatch" $BR --repo "$T/repo" --cancel >/dev/null
# the second landing review: the entry changes only once the job is scheduled — a refusal after the raise
# check (here the depth cap) leaves it, so the branch's older record never reads through
printf '{"%s": {"mode": "default", "ts": 1}}\n' "$BK" > "$PLANS_DIR/branch-modes.json"
env -u DISPATCH_LABEL DISPATCH_DEPTH=9 "$B/dispatch" $BR --repo "$T/repo" --at "$FUT 04:10" --mode ask > /dev/null 2> "$T/yield-deep.err"
check "$?" "2" "a --mode dispatch refused at the depth cap…"
check "$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))[sys.argv[2]]["mode"])' "$PLANS_DIR/branch-modes.json" "$BK")" "default" \
  "  …leaves the helm mode --branch entry as it was"
rm -f "$PLANS_DIR/branch-modes.json"
# the follow-ups' landing review, item 6: a mode read while repos.json is torn is ask for this run only
printf '{"repos": {"x": ' > "$T/torn-repos.json"; : > "$T/env.calls"; rm -rf "$PLANS_DIR/mship"
CLAUDE_REPOS_JSON="$T/torn-repos.json" DISPATCH_LOG="$HOME/mode-torn.log" "$B/dispatch" $BR --repo "$T/repo" --headless >/dev/null 2>&1
has "$HOME/mode-torn.log" "== mode ask (repos.json is unreadable: ask for this run only, kept nowhere)" "a torn registry at fire time: ask for this run (item 6)"
grep -q "DISPATCH_MODE=" "$T/env.calls"; check "$?" "1" "  …not into the session's DISPATCH_MODE, which would outlive the tear"
check "$(newest_rec task_mode) $(newest_rec mode_unread)" "None 1" "  …nor the record's task_mode: mode_unread marks a sent task with no mode"
CLAUDE_REPOS_JSON="$T/torn-repos.json" DISPATCH_MODE=dnd DISPATCH_LOG="$HOME/mode-torn-hint.log" "$B/dispatch" $BR --repo "$T/repo" --headless >/dev/null 2>&1
has "$HOME/mode-torn-hint.log" "== mode dnd" "  a plist's hint comes before the scope: read whole, kept as before"
# the second landing review: read_mode's own python over a helmlib from before fire_mode and torn_read
# (a peer's, an older checkout's) reads the ship as item 5 did, not the bare hint of a crash
mkdir -p "$T/oldhelm"
printf 'import os\nfrom pathlib import Path\ndef tool(name):\n    return Path(os.environ["OLDHELM"]) / name\n' > "$T/oldhelm/common.py"
printf 'def branch_override(b, r):\n    return None\ndef task_mode(pid, task, repo, hint):\n    return ("ask", "ship %%s" %% pid)\n' > "$T/oldhelm/helmlib.py"
awk '/^read_mode\(\) \{/ {a=1} a && !on && /<<.PY./ {on=1; next} on && /^PY$/ {exit} on' "$B/dispatch" > "$T/read_mode.py"
check "$(OLDHELM="$T/oldhelm" python3 "$T/read_mode.py" "$T/oldhelm" s1 t /r dnd b 2>&1)" "0 ask" \
  "  read_mode over a helmlib without fire_mode or torn_read: the ship's ask, not the plist's dnd"
unset PLANS_DIR
: > "$T/claude.calls"
DISPATCH_LOG="$HOME/mode-none.log" "$B/dispatch" $BR --repo "$T/repo" --headless >/dev/null 2>&1
has "$HOME/mode-none.log" "== mode default" "no mode anywhere: default"
"$B/dispatch" $BR --repo "$T/repo" --dry-run --mode ask 2>/dev/null | grep -qF ", mode ask" \
  && echo "  ok   a dry run names the mode" || { echo "  FAIL mode dry run"; fails=$((fails+1)); }

echo "help"
"$B/dispatch" --help | tail -1 | grep -q "DISPATCH_CLAUDE" && echo "  ok   --help prints the whole header" || { echo "  FAIL --help cut short"; fails=$((fails+1)); }

echo "old name"
# a job scheduled as run-seed before 2026-10-05: its plist calls bin/run-seed with RUN_SEED_*
OP="$HOME/Library/LaunchAgents/org.example.claude.run-seed.repo.demo.plist"
mkdir -p "$(dirname "$OP")"; echo old > "$OP"
env -u DISPATCH_LABEL RUN_SEED_LOG="$HOME/old.log" RUN_SEED_LABEL=org.example.claude.run-seed.repo.demo RUN_SEED_YEAR="$(date +%Y)" \
  "$B/run-seed" $BR --repo "$T/repo" --dry-run >/dev/null
has "$HOME/old.log" "dispatch $BR" "the shim runs dispatch, logging where the old job said"
check "$([ -f "$OP" ] && echo present || echo gone)" "gone" "the old-named plist removes itself"
OP="$HOME/Library/LaunchAgents/org.example.claude.run-seed.repo.demo.202610050352.plist"; echo old > "$OP"
"$B/dispatch" $BR --repo "$T/repo" --cancel >/dev/null
check "$([ -f "$OP" ] && echo present || echo gone)" "gone" "--cancel finds a job scheduled under the old name"

echo "dry run"
"$B/dispatch" $BR --repo "$T/repo" --dry-run | grep -q "DRY RUN" && echo "  ok   dry run prints" || { echo "  FAIL dry run"; fails=$((fails+1)); }
# the default repo: the overlay's checkout where one is installed, else the main checkout of this clone
PRIM="$(cd "$(git -C "${LEGACY:-$B}" rev-parse --path-format=absolute --git-common-dir)/.." && pwd -P)"
# The primary is the live checkout: its contract may refuse the run (physical: not none, since
# bin/domains, 2026-10-06), so the proof is that the dry run or the refusal names the primary.
"$B/dispatch" $BR --dry-run 2>&1 | grep -qE "use $PRIM/\.claude/worktrees/demo|$PRIM's contract must say" && echo "  ok   no --repo: the primary checkout, not this script's worktree" || { echo "  FAIL default repo"; fails=$((fails+1)); }
echo "--if-room (the sounding queue: the week read at fire time)"
# the pick passes (the stub); the week is the pool's, read through the real bin/account as yolo_launch's gate reads it
STUB_ACCT=acct-a DISPATCH_ACCOUNT="$T/acct" ACCOUNTS_FILE="$T/noacct.json" ACCOUNT_CLAUDE=false \
  "$B/dispatch" $BR --repo "$T/repo" --headless --if-room --dry-run > "$T/out" 2>/dev/null
has "$T/out" "DRY RUN: refused — --if-room: no account may run it (claude-nr: " "no account in the pool may run it: refused, the verdict named"
"$B/dispatch" $BR --repo "$T/repo" --headless --if-room --dry-run > "$T/out" 2>/dev/null
has "$T/out" "DRY RUN: would fetch" "no registry and no week reading: the week has room, the run goes on"
"$B/dispatch" --start go "$T/repo" "x" --if-room --dry-run > "$T/out" 2>&1; check "$?" "2" "--start refuses --if-room (a caller with its own trigger owns its budget)"
"$B/dispatch" $BR --repo "$T/repo" --at reset --at "$FUT 04:10" --if-room --dry-run > "$T/out" 2>&1; check "$?" "2" "--at given twice is refused: the last would win past a rule pinned to --at reset (S7 review, R5)"
has "$T/out" "dispatch: --at given twice" "  and said"
# the weekly Sextant runs in auto mode, so dispatch holds it to the queue's one shape (S7 /finish review, F1/F5)
WEEKLY_RUN=sextant "$B/dispatch" $BR --repo "$T/repo" --at "$FUT 04:10" --if-room --dry-run > "$T/out" 2>&1; check "$?" "2" "WEEKLY_RUN: a clock time is refused"
has "$T/out" "under WEEKLY_RUN=sextant only" "  and said"
WEEKLY_RUN=sextant "$B/dispatch" $BR --repo "$T/repo" --at reset --dry-run > "$T/out" 2>&1; check "$?" "2" "WEEKLY_RUN: --at reset without --if-room is refused"
WEEKLY_RUN=sextant "$B/dispatch" $BR --repo "$T/repo" --cancel --at reset --if-room --dry-run > "$T/out" 2>&1; check "$?" "2" "WEEKLY_RUN: --cancel is refused"
WEEKLY_RUN=sextant "$B/dispatch" $BR --repo "$T/repo" --at reset --if-room --model fable --dry-run > "$T/out" 2>&1; check "$?" "2" "WEEKLY_RUN: another model is refused"
WEEKLY_RUN=sextant "$B/dispatch" $BR --repo "$T/repo" --at reset+30 --if-room --dry-run > "$T/out" 2>&1
grep -q "under WEEKLY_RUN" "$T/out"; check "$?" "1" "WEEKLY_RUN: the queue's own shape passes the guard"
echo "the warm hour"
"$B/dispatch" --start "/finish x --unattended" "$T/repo" "finish · idle-check" --dry-run > "$T/out" 2>&1
env -u DISPATCH_IDLE python3 - "$B/dispatch" <<'PY' > "$T/idle.out" 2>&1
import re, sys
# the record a --start run writes carries its own idle: autofinish-run waits for the watcher
src = open(sys.argv[1]).read()
print("has-idle-for" if 'idle_for=600' in src else "no-idle-for")
print("recorded" if '${idle_for:+idle="$idle_for"}' in src else "not-recorded")
print("dnd-idle" if '[ "$mode" = dnd ]; } && idle_for=600' in src else "dnd-warm")
PY
has "$T/idle.out" "has-idle-for" "a --start run (autofinish's /finish) keeps the 10 minutes its caller waits on…"
has "$T/idle.out" "recorded" "  …written into the run's record, which the watcher reads"
has "$T/idle.out" "dnd-idle" "  a dnd step keeps the 10 minutes too: its owner is not there to pick it up (review D2)"
check "$(env -u DISPATCH_IDLE python3 -c "
import importlib.machinery as m, importlib.util as u
l = m.SourceFileLoader('d', '$B/dispatch-rc'); s = u.spec_from_loader('d', l)
mod = u.module_from_spec(s); l.exec_module(mod); print(int(mod.IDLE))")" "3600" \
  "a session that goes idle is kept the prompt cache's hour, not 10 min (D1, the owner 2026-10-06)"
# the rule itself, for the watcher and the orphan reaper alike (review 2026-10-08: the grep above
# stays green if the watcher ignores the record's idle)
: > "$T/lim.json"; : > "$T/limn.json"; : > "$T/limn.json.next"
check "$(env -u DISPATCH_IDLE python3 -c '
import importlib.machinery as m, importlib.util as u, sys
l = m.SourceFileLoader("d", sys.argv[1]); d = u.module_from_spec(u.spec_from_loader("d", l)); l.exec_module(d)
a, n = sys.argv[2], sys.argv[3]
print(int(d.idle_limit(a, {})), int(d.idle_limit(a, {"idle": "600"})), int(d.idle_limit(n, {})), int(d.idle_limit(a, {"probe": 1})))' \
  "$B/dispatch-rc" "$T/lim.json" "$T/limn.json")" "3600 600 60 60" \
  "  idle_limit: the hour; a --start run's own 600; 1 min when the next run waits, or for a probe"
sleep 300 & ENDP=$!
check "$(env -u DISPATCH_IDLE python3 - "$B/dispatch-rc" "$T/lim.json" "$ENDP" <<'PY2'
import importlib.machinery as m, importlib.util as u, json, os, sys
l = m.SourceFileLoader("d", sys.argv[1]); d = u.module_from_spec(u.spec_from_loader("d", l)); l.exec_module(d)
a, pid, sid = sys.argv[2], int(sys.argv[3]), "e0d00000-0000-4000-8000-000000000000"
home = os.environ["HOME"]; os.makedirs(home + "/.claude/sessions", exist_ok=True); os.makedirs(home + "/.claude/projects/x", exist_ok=True)
def reg(status):
    json.dump({"pid": pid, "sessionId": sid, "status": status}, open("%s/.claude/sessions/%d.json" % (home, pid), "w"))
def said(text):
    with open("%s/.claude/projects/x/%s.jsonl" % (home, sid), "a") as f:
        f.write(json.dumps({"type": "assistant", "message": {"content": [{"type": "text", "text": text}]}}, separators=(",", ":")) + "\n")   # compact, as Claude Code writes it
st = {"idle": "600", "pid": pid, "session": sid}
out = []
reg("idle"); said("Working on the review.")
out.append(int(d.idle_limit(a, st)))
said("⚠ step 4 — 2 open items\n\n" + d.common.FINISH_LINES[1])
out.append(int(d.idle_limit(a, st)))
reg("busy"); out.append(int(d.idle_limit(a, st)))
reg("idle"); out.append(int(d.idle_limit(a, dict(st, idle=None))))
said("RELAYED TO coding-7 — D1, the cadence"); out.append(int(d.idle_limit(a, st)))
said(d.common.PENDING_PREFIX + "the two reviewers"); out.append(int(d.idle_limit(a, st)))
said(d.common.HANDOVER_LINE); out.append(int(d.idle_limit(a, st)))
print(*out)
PY2
)" "600 60 600 3600 600 600 60" "  a --start run idle on its closing line (a stopped /finish): 1 min, not 10; busy, a run someone may pick up again, or one waiting on its manager (RELAYED) or its own work, as before (skipper, 2026-10-19); the hand-over line: 1 min (review D2)"
kill $ENDP 2>/dev/null

echo "an API-error end is nudged once, not ended as idle (the dropped connection of 2026-10-22)"
# watch_loop in-process, an rc-mode run (same() matches the registry's session id), with stand-ins for
# the process, its registry record and its inbox socket (a unix socket this script serves): the real
# send() of the claude-code adapter posts to it, and the "receiver" answers as a live session does — a
# queue-operation in its transcript, its registry busy. Nothing is posted to a real session: HOME is the
# scratch one. ASK_SESSIONS_DIR is unset (the adapter would read another registry); one case sets it.
env -u DISPATCH_NEXT_IDLE -u ASK_SESSIONS_DIR HAIL_READBACK_S=1 python3 - "$B/dispatch-rc" "$T" <<'PY' > "$T/nudge.out" 2>&1
import importlib.machinery as m, importlib.util as u, json, os, signal, socket, subprocess, sys, threading, time
l = m.SourceFileLoader("d", sys.argv[1]); d = u.module_from_spec(u.spec_from_loader("d", l)); l.exec_module(d)
T, home = sys.argv[2], os.environ["HOME"]
d.POLL = 0.05
d.hold_awake = lambda want: None
d.close_window = lambda st: None
ended, reasons = [], []
d.end_session = lambda st: ended.append(1) or True
d.finish = lambda path, st, reason: reasons.append(reason) or 0
os.makedirs(home + "/.claude/sessions", exist_ok=True); os.makedirs(home + "/.claude/projects/x", exist_ok=True)
class Alarm(BaseException):   # not TimeoutError: an OSError, which the loop's own handlers swallow
    pass
def alarm(*a):
    raise Alarm
signal.signal(signal.SIGALRM, alarm)
def iso():
    return time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime()) + ".%03dZ" % (int(time.time() * 1000) % 1000)
n = [0]
def tick():   # a timestamp no other entry has: a turn is named by it
    n[0] += 1
    return time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(1792692000 + n[0])) + ".000Z"
def run(name, tail, *, st_extra=None, post=None, nudges=None, stamp=True, sock=True, ago=700, hold=False):
    """One watch of a run idle AGO s (700: past DISPATCH_IDLE=600 and NEXT_IDLE) on TAIL, a list of
    transcript entries. POST(write, set_registry, k, frame) is the receiver's answer to its k-th post;
    None: ignores it. STAMP False: the registry has no statusUpdatedAt (send() reads it as not known
    quiet); SOCK False: no inbox. HOLD: the run is expected to be still watched after 8 s (the nudge reads back for 1 s; a loaded Mac is slower)."""
    proc = subprocess.Popen(["sleep", "60"])
    sid = (name + "00000000")[:8] + "-0000-4000-8000-000000000000"
    tp = "%s/.claude/projects/x/%s.jsonl" % (home, sid); rp = "%s/.claude/sessions/%d.json" % (home, proc.pid)
    sock_path = "%s/%d.sock" % (T, proc.pid)
    assert len(sock_path) < 100, sock_path
    def write(entry):
        with open(tp, "a") as f:
            f.write(json.dumps(entry, separators=(",", ":")) + "\n")
    def reg(status, ago):
        rec = {"pid": proc.pid, "sessionId": sid, "status": status}
        if sock:
            rec["messagingSocketPath"] = sock_path
        rec["statusUpdatedAt" if stamp else "startedAt"] = int((time.time() - ago) * 1000)
        json.dump(rec, open(rp + ".t", "w"))
        os.replace(rp + ".t", rp)
    for e in tail:
        write(e)
    reg("idle", ago)
    posts = []
    srv = socket.socket(socket.AF_UNIX); srv.bind(sock_path); srv.listen(5)
    def serve():
        while True:
            try:
                c, _ = srv.accept()
            except OSError:
                return
            data = b""
            c.settimeout(1)
            try:
                while not data.endswith(b"\n"):
                    chunk = c.recv(4096)
                    if not chunk:
                        break
                    data += chunk
            except OSError:
                pass
            c.close()
            for line in data.decode().splitlines():
                e = json.loads(line)
                if e.get("type") == "user":
                    posts.append(e["message"]["content"])
                    if post:
                        post(write, reg, len(posts), e["message"]["content"])
    threading.Thread(target=serve, daemon=True).start()
    path = "%s/%s.run.json" % (T, name)
    st = dict({"mode": "rc", "pid": proc.pid, "session": sid, "topic": name}, **(st_extra or {}))
    if nudges:
        st["nudges"] = nudges
    json.dump(st, open(path, "w"))
    del ended[:]; del reasons[:]
    signal.alarm(8 if hold else 20)
    try:
        d.watch_loop(path, d.load(path), time.time(), True, time.time())
    except Alarm:
        if not hold:
            print("HUNG", name)
    signal.alarm(0)
    srv.close(); proc.kill(); proc.wait()
    return posts, list(reasons), d.load(path).get("nudges") or []
def err(ts, kind="server_error", flag=True, model="<synthetic>", text="API Error: Connection dropped (ECONNRESET)", side=False):
    e = {"type": "assistant", "timestamp": ts, "message": {"model": model, "role": "assistant", "content": [{"type": "text", "text": text}]}}
    if flag:
        e.update(isApiErrorMessage=True, error=kind)
    if side:
        e["isSidechain"] = True
    return e
def said(text, ts=None):
    return {"type": "assistant", "timestamp": ts or tick(), "message": {"model": "claude-opus-5-5", "role": "assistant", "content": [{"type": "text", "text": text}]}}
def took(write, reg, frame):   # the receiver takes the post: queue-operation, the prompt, busy
    write({"type": "queue-operation", "operation": "enqueue", "timestamp": iso(), "content": frame})
    write({"type": "user", "timestamp": iso(), "message": {"role": "user", "content": frame}})
    reg("busy", 0)
def taken(write, reg, k, frame):   # …then works, and goes idle again on its normal reply
    took(write, reg, frame)
    def later():
        time.sleep(0.4)
        write(said("The check passed; landing.")); reg("idle", 700)
    threading.Thread(target=later).start()
def taken_error_again(write, reg, k, frame):   # …and the next call fails again
    took(write, reg, frame)
    def later():
        time.sleep(0.4)
        write(err(tick())); reg("idle", 700)
    threading.Thread(target=later).start()
user = lambda text: {"type": "user", "timestamp": tick(), "message": {"role": "user", "content": text}}
SFX = "idle 11 min, " + d.API_ERROR_END
want = d.NUDGE_FRAME % ("server_error", "API Error: Connection dropped (ECONNRESET)")
E1 = tick()
r = run("s1", [user("go"), said("polling"), err(E1), {"type": "system", "subtype": "turn_duration", "timestamp": tick()}], post=taken)
print("S1", len(r[0]), r[0] == [want], r[1], r[2] == [E1])
r = run("s2", [user("go"), err(tick(), flag=False, model="claude-opus-5-5")], post=taken)
print("S2", len(r[0]), r[1])
r = run("s2b", [user("go"), err(tick(), flag=False)], post=taken)
print("S2b", len(r[0]), r[1])
r = run("s3", [user("go"), err(tick())], post=None)
print("S3", len(r[0]), r[1] == [SFX], len(r[2]))
E4 = tick()
r = run("s4", [user("go"), err(E4)], post=taken, nudges=[E4])
print("S4", len(r[0]), r[1] == [SFX])
r = run("s5", [user("go"), err(tick())], post=taken_error_again)
print("S5", len(r[0]), r[1] == [SFX], len(r[2]))
for k in ("rate_limit", "invalid_request", "authentication_failed"):
    r = run("k" + k[:3], [user("go"), said("fine"), err(tick(), kind=k, text="not a server error")], post=taken)
    print("S6", k, len(r[0]), r[1] == [SFX])
r = run("s7", [user("go"), err(tick()), user("carry on")], post=taken)
print("S7", len(r[0]), r[1])
r = run("s8", [user("go"), said("Working on the review.")], post=taken)
print("S8", len(r[0]), r[1])
r = run("s9", [user("go"), said("⚠ step 4 - 2 open items\n\n" + d.common.FINISH_LINES[1])], post=taken, st_extra={"idle": 600})
print("S9", len(r[0]), r[1])
r = run("s10", [user("go"), err(tick())], post=taken, st_extra={"probe": 1})
print("S10", len(r[0]), r[1] == [SFX])
r = run("s11", [user("go"), said("fine"), err(tick(), side=True)], post=taken)
print("S11", len(r[0]), r[1])
r = run("s12", [user("go"), err(tick())], post=taken, stamp=False)
print("S12", len(r[0]), r[1] == [SFX], len(r[2]))
r = run("s13", [user("go"), err(tick())], post=taken, sock=False)
print("S13", len(r[0]), r[1] == [SFX], len(r[2]))
r = run("s14", [user("go"), err(tick())], post=None, ago=120, st_extra={"idle": 600}, hold=True)
print("S14", len(r[0]), r[1], len(r[2]))
r = run("s15", [user("go"), err(tick())], post=taken, st_extra={"ending": "ended by dispatch --end"})
print("S15", len(r[0]), r[1] == [SFX], len(r[2]))
keep = d.left_behind
d.left_behind = lambda rec: {"to": "studio", "what": "move", "target": "x"}
r = run("s16", [user("go"), err(tick())], post=taken)
d.left_behind = keep
print("S16", len(r[0]), r[1] == [SFX])
os.environ["ASK_SESSIONS_DIR"] = home + "/no-such-registry"
r = run("s17", [user("go"), err(tick())], post=taken)
del os.environ["ASK_SESSIONS_DIR"]
print("S17", len(r[0]), r[1])
PY
has "$T/nudge.out" "S1 1 True ['idle 11 min'] True" "a last turn that ended on a server_error is nudged once, with the frame that says who and why; the session works again and ends on its normal reply (the nudge recorded by the error's timestamp)"
has "$T/nudge.out" "S2 0 ['idle 11 min']" "a text that says \"API Error\" alone, from a real model with no flag, is no error: not nudged, not named"
has "$T/nudge.out" "S2b 0 ['idle 11 min']" "  nor a <synthetic> entry that names no error kind"
has "$T/nudge.out" "S3 1 True 1" "a nudge whose effect never shows (held): the slot is spent, logged, and the run is ended as before, the reason naming the error"
has "$T/nudge.out" "S4 0 True" "the same turn is not nudged twice"
has "$T/nudge.out" "S5 2 True 2" "two nudges a run, each for its own turn; the third error ends it"
has "$T/nudge.out" "S6 rate_limit 0 True" "a rate limit is not nudged…"
has "$T/nudge.out" "S6 invalid_request 0 True" "  …nor the safeguards flag (a person's call)…"
has "$T/nudge.out" "S6 authentication_failed 0 True" "  …nor a login that failed: only a server_error is"
has "$T/nudge.out" "S7 0 ['idle 11 min']" "a prompt typed after the error: it is no longer the last turn"
has "$T/nudge.out" "S8 0 ['idle 11 min']" "a normal idle end: not nudged, ended as before"
has "$T/nudge.out" "S9 0 ['idle 11 min']" "a closing line is an end: not nudged"
has "$T/nudge.out" "S10 0 True" "a probe is not nudged"
has "$T/nudge.out" "S11 0 ['idle 11 min']" "a sidechain error after a normal reply is no last turn"
has "$T/nudge.out" "S12 0 True 0" "a post send() refuses (no status time on the record) spends no slot…"
has "$T/nudge.out" "S13 0 True 0" "  nor one it cannot reach (no inbox)"
has "$T/nudge.out" "S14 1 [] 1" "idle 2 min of a 10 min limit: nudged at once (the minute), and the run is still watched"
has "$T/nudge.out" "S15 0 True 0" "a run that is being ended (\`ending\` in its record) is not nudged"
has "$T/nudge.out" "S16 0 True" "a run that handed its work to another machine is not nudged"
has "$T/nudge.out" "S17 1 ['idle 11 min']" "ASK_SESSIONS_DIR does not move the registry the post reads (the watcher's own)"
has "$T/nudge.out" "nudge not delivered: held" "  the undelivered nudge is said in the log"
has "$T/nudge.out" "nudge not delivered: refused" "  a refused one too"
has "$T/nudge.out" "nudged session " "  and a delivered one"
grep -q HUNG "$T/nudge.out"; check "$?" "1" "  no case hung"
# the end of such a run is no completion: yolo_launch refuses it, and the harness reports it failed
# (the same words as dispatch-rc's API_ERROR_END)
sed -n "/why=\$(python3 - \"\$state\"/,/^PY\$/p" "$B/dispatch" | sed '1d;$d' > "$T/yolo_why.py"
printf '{"mode":"rc","session":"x","end_reason":"idle 11 min, its last turn ended on an API error"}' > "$T/yolo.json"
check "$(python3 "$T/yolo_why.py" "$T/yolo.json" "$B/.." main /nonexistent "$B/../lib" 2>&1)" "it ended idle on an API error, half done: idle 11 min, its last turn ended on an API error" \
  "yolo_launch: a build run that ended idle on an API error is not launched from"
printf '{"mode":"rc","session":"x","end_reason":"idle 11 min"}' > "$T/yolo.json"
check "$(python3 "$T/yolo_why.py" "$T/yolo.json" "$B/.." main /nonexistent "$B/../lib" 2>&1 | grep -c "API error")" "0" "  and an ordinary idle end is not refused for it"

echo "--start --resume [--fork] (bin/harness V2; option A of the orchestration doc's D9)"
OLD=11111111-2222-4333-8444-555555555555; NEW=99999999-8888-4777-8666-555555555555
"$B/dispatch" --start go "$T/repo" "again · demo" --resume $OLD --headless --dry-run > "$T/out" 2>/dev/null
has "$T/out" " -p go --resume $OLD --model opus" "a plain --resume: claude --resume ID, the id kept"
check "$(grep -c -- '--session-id' "$T/out")" "0" "  and no --session-id beside it (claude refuses the pair without a fork)"
"$B/dispatch" --start go "$T/repo" "again · demo" --resume $OLD --fork --session-id $NEW --headless --dry-run > "$T/out" 2>/dev/null
has "$T/out" " -p go --session-id $NEW --resume $OLD --fork-session --model" "a fork: the caller's new id, --resume and --fork-session"
"$B/dispatch" --start go "$T/repo" "again · demo" --resume $OLD --dry-run > "$T/out" 2>/dev/null
has "$T/out" " go --resume $OLD --remote-control" "the visible path takes --resume the same way, in its screen's runner"
"$B/dispatch" --start go "$T/repo" "n" --resume $OLD --session-id $NEW --dry-run >/dev/null 2>&1; check "$?" "2" "--session-id with a plain --resume: refused"
"$B/dispatch" --start go "$T/repo" "n" --fork --dry-run >/dev/null 2>&1; check "$?" "2" "--fork without --resume: refused"
"$B/dispatch" $BR --repo "$T/repo" --resume $OLD --dry-run >/dev/null 2>&1; check "$?" "2" "--resume without --start: refused"
: > "$T/claude.calls"
DISPATCH_LOG="$HOME/again.log" "$B/dispatch" --start go "$T/repo" "again · demo" --resume $OLD --headless >/dev/null 2>&1
has "$T/claude.calls" "claude -p go --resume $OLD --model" "a headless --resume runs claude --resume"
RR=$(ls "$HOME"/Library/Logs/claude-weekly/run-seed-runs/*.again-demo.11111111.json 2>/dev/null | head -1)
check "$(python3 -c 'import json, sys; s = json.load(open(sys.argv[1])); print(s.get("session"), s.get("resumed_from"))' "$RR" 2>&1)" "$OLD $OLD" \
  "  its record: the session it continued, and resumed_from naming it"

echo "tidy: the ancient windows, and only those"
: > "$T/order"; : > "$T/yabai.calls"; : > "$T/claude.calls"
SW="$HOME/.claude/sessions"; mkdir -p "$SW"
(exec "$T/claude" x --session-id sweep-warm) >/dev/null 2>&1 & WARM=$!
(exec "$T/claude" x --session-id sweep-cold) >/dev/null 2>&1 & COLD=$!
(sleep 0.1) & DEADPID=$!; wait $DEADPID 2>/dev/null   # a pid that is gone: a run whose claude died
sleep 0.6
srec() {   # PID NAME IDLE_SECONDS — a session record as Claude Code writes it
  printf '{"pid":%s,"procStart":"%s","sessionId":"s-%s","name":"%s","status":"idle","statusUpdatedAt":%s}' \
    "$1" "$(pst "$1")" "$1" "$2" "$(( ($(date +%s) - $3) * 1000 ))" > "$SW/$1.json"
}
srec $WARM "coding: warm · acct-b" 120
srec $COLD "coding: cold · acct-b" 7200
# a visible run of its own, with its window recorded, whose claude is gone and no end written
printf '{"mode":"rc","repo":"%s","topic":"ancient","pid":%s,"proc_start":"Thu Jan  1 00:00:00 2020","session":"s-ancient","started":%s,"screen":"run-repo-ancient","screendir":"%s","title":"run · ancient · repo","window":51}' \
  "$T/repo" "$DEADPID" "$(date +%s)" "$HOME" > "$RUNS/00000000-000009-repo.ancient.json"
python3 - "$T/windows.json" <<'PY'
import json, sys
def w(i, title, space=5, sub="AXStandardWindow"):
    return {"id": i, "app": "Terminal", "space": space, "subrole": sub, "title": title}
json.dump([
    w(50, "sam — run · ghost · repo — screen -x run-repo-ghost — 80×24"),
    w(51, "sam — run · ancient · repo — screen -x run-repo-ancient — 80×24"),
    w(60, "sam — ✳ coding: warm · acct-b — claude --name coding: warm · acct-b /pickup x — 80×24"),
    w(61, "sam — ✳ coding: cold · acct-b — claude --name coding: cold · acct-b /pickup x — 80×24"),
    # an exited session's window shows its shell, as windows 177-192 did on 2026-10-07
    w(62, "sam — ✳ coding: dead · acct-b — -zsh — 80×24"),
    # a claude no record names (started by hand): running, so left alone (review 2026-10-08)
    w(63, "sam — ✳ coding: by hand — claude — 80×24"),
    # "coding: cold · acct-b" must not claim a longer name (review 2026-10-08)
    w(64, "sam — ✳ coding: cold · acct-b2 — claude --name coding: cold · acct-b2 — 80×24"),
    w(70, "", space=1, sub=""),
], open(sys.argv[1], "w"))
PY
env -u YABAI_OFF -u DISPATCH_IDLE python3 "$B/dispatch-rc" tidy --dry-run > "$T/out" 2>&1
has "$T/out" "would close" "--dry-run says what it would close…"
grep -q -- "--close" "$T/yabai.calls"; check "$?" "1" "  …and closes nothing"
kill -0 $COLD 2>/dev/null; check "$?" "0" "  …and signals nobody"
STUB_RETITLE="61:$COLD" env -u YABAI_OFF -u DISPATCH_IDLE python3 "$B/dispatch-rc" tidy > "$T/out" 2>&1
has "$T/yabai.calls" "-m window 50 --close" "a run · window with no run behind it: closed"
has "$T/yabai.calls" "-m window 51 --close" "a run whose claude is gone: its window closed"
check "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("end_reason",""))' "$RUNS/00000000-000009-repo.ancient.json")" \
  "tidied: its claude was gone" "  and the record says so, where --status reads it (D3)"
grep -q -- "-m window 60 --close" "$T/yabai.calls"; check "$?" "1" "a pickup session idle 2 min: left alone — the claude desktop is for these (D2)"
kill -0 $WARM 2>/dev/null; check "$?" "0" "  and still running"
has "$T/yabai.calls" "-m window 61 --close" "a pickup session idle past the hour: its window closed"
dead_ $COLD; kill -0 $COLD 2>/dev/null; check "$?" "1" "  and its claude got SIGTERM first"
cterm=$(grep -n "claude TERM $COLD" "$T/order" | head -1 | cut -d: -f1)
c61=$(grep -n -- "window 61 --close" "$T/order" | head -1 | cut -d: -f1)
check "$([ -n "$cterm" ] && [ -n "$c61" ] && [ "$cterm" -lt "$c61" ] && echo signal-first || echo close-first)" "signal-first" \
  "  in that order: Terminal answers a close on a window running claude with a sheet instead (probed 2026-10-06)"
has "$T/yabai.calls" "-m window 62 --close" "a pickup window whose session has exited (a shell in its title): closed"
grep -q -- "-m window 63 --close" "$T/yabai.calls"; check "$?" "1" "  one still running claude that no record names: left alone — its close would raise the sheet whose default kills it"
grep -q -- "-m window 64 --close" "$T/yabai.calls"; check "$?" "1" "  a name another session's name starts with is not that session's window"
has "$T/out" "window 70 on desktop 1" "a sheet is named, never clicked: nothing can close one"
grep -q "is no longer" "$T/out"; check "$?" "1" "  the cold window, its title now '<user> — 120×30', is still this pass's to close (fresh)"
has "$T/out" "closed 4 window(s)" "  and the count is of windows gone: 50, 51, 61, 62"
grep -q "still open" "$T/out"; check "$?" "1" "    none left open"
kill $WARM 2>/dev/null; wait $WARM 2>/dev/null

echo "tidy: a session whose work went to another machine is closed once idle, not after the hour"
: > "$T/order"; : > "$T/yabai.calls"
(exec "$T/claude" x --session-id hand-moved) >/dev/null 2>&1 & HAND=$!
(exec "$T/claude" x --session-id hand-reused) >/dev/null 2>&1 & REUSED=$!
(exec "$T/claude" x --session-id hand-typed) >/dev/null 2>&1 & TYPED=$!
sleep 0.6
srec $HAND "coding: moved" 120
srec $REUSED "coding: reused" 120
srec $TYPED "coding: typed" 120
mkdir -p "$HOME/Library/Caches/run-seed/handoffs"
# a transcript whose last typed prompt was N seconds ago (a tool result after it is no prompt)
tx() { mkdir -p "$HOME/.claude-x/projects/p"; python3 -c '
import json, sys, time
t = lambda s: time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime(time.time() - int(s)))
print(json.dumps({"type": "user", "timestamp": t(sys.argv[1]), "message": {"content": "go"}}, separators=(",", ":")))
print(json.dumps({"type": "user", "timestamp": t(0), "toolUseResult": {}, "message": {"content": [{"type": "tool_result"}]}}, separators=(",", ":")))' "$2" > "$HOME/.claude-x/projects/p/$1.jsonl"; }
# moved 2.5 min ago, idle since 2 min: the turn that moved it is the one that ended
printf '{"to":"buildbox","what":"move","target":"n-1","at":%s}' "$(( $(date +%s) - 150 ))" > "$HOME/Library/Caches/run-seed/handoffs/s-$HAND.json"
tx "s-$HAND" 200
# handed off 2 h ago, idle only 2 min: it was used again since — the hour applies as before
printf '{"to":"buildbox","what":"dispatch","target":"b","at":%s}' "$(( $(date +%s) - 7200 ))" > "$HOME/Library/Caches/run-seed/handoffs/s-$REUSED.json"
tx "s-$REUSED" 7300
# moved 5 min ago, the owner typed into it 3 min ago, idle again since 2: used again, inside HANDOFF_TURN
printf '{"to":"buildbox","what":"move","target":"n-2","at":%s}' "$(( $(date +%s) - 300 ))" > "$HOME/Library/Caches/run-seed/handoffs/s-$TYPED.json"
tx "s-$TYPED" 180
python3 - "$T/windows.json" <<'PY'
import json, sys
w = lambda i, t: {"id": i, "app": "Terminal", "space": 5, "subrole": "AXStandardWindow", "title": t}
json.dump([w(65, "sam — ✳ coding: moved — claude --name coding: moved — 80×24"),
           w(66, "sam — ✳ coding: reused — claude --name coding: reused — 80×24"),
           w(67, "sam — ✳ coding: typed — claude --name coding: typed — 80×24")], open(sys.argv[1], "w"))
PY
STUB_RETITLE="65:$HAND" env -u YABAI_OFF -u DISPATCH_IDLE python3 "$B/dispatch-rc" tidy > "$T/out" 2>&1
has "$T/yabai.calls" "-m window 65 --close" "moved to buildbox, idle 2 min: its window closed (the owner 2026-10-08: I don't need to see it)"
has "$T/out" "its work went to buildbox (move" "  and the log says why"
dead_ $HAND; kill -0 $HAND 2>/dev/null; check "$?" "1" "  its claude ended first"
grep -q -- "-m window 66 --close" "$T/yabai.calls"; check "$?" "1" "handed off 2 h before it went idle: used since, so left for the hour"
grep -q -- "-m window 67 --close" "$T/yabai.calls"; check "$?" "1" "typed into 2 min after the move, idle again within 10 min: used again, left for the hour (review 2026-10-10)"
kill $REUSED $TYPED 2>/dev/null; wait $REUSED $TYPED 2>/dev/null
python3 -c '
import importlib.machinery, importlib.util, json, os, sys, time
l = importlib.machinery.SourceFileLoader("d", sys.argv[1]); d = importlib.util.module_from_spec(importlib.util.spec_from_loader("d", l)); l.exec_module(d)
now = time.time()
rec = lambda idle: {"sessionId": "s-lim", "status": "idle", "statusUpdatedAt": int((now - idle) * 1000)}
open(os.path.join(d.common.HANDOFFS, "s-lim.json"), "w").write(json.dumps({"to": "buildbox", "what": "move", "at": int(now - 100)}))
d.last_prompt = lambda sid: now - 120
d.session_record = lambda st: rec(st["idle_s"])
print(int(d.idle_limit("/nonexistent", {"idle_s": 90})), "idle" if d.idle_limit("/nonexistent", {"idle_s": 30}) == d.IDLE else "?")' "$B/dispatch-rc" > "$T/out" 2>&1
check "$(cat "$T/out")" "60 idle" "  a run's watcher: 1 min once its session handed off and went idle; the hour while it has not yet"

echo "tidy: what yabai cannot close (out of view), Terminal closes from inside — no focus, no grant"
printf '[{"id": 81, "app": "Terminal", "title": "sam — run · lost · repo — 120×30", "space": 5, "is-visible": false}]' > "$T/windows.json"
cat > "$T/open-tc" <<EOF
#!/bin/sh
echo "open \$*" >> "$T/open.calls"
bash -n "\$4" && echo parses >> "$T/open.calls"
grep -q '{81}' "\$4" && python3 "$T/rmwin" "$T/windows.json" 81
EOF
chmod +x "$T/open-tc"; : > "$T/open.calls"
YABAI_STUCK=1 DISPATCH_OPEN="$T/open-tc" env -u YABAI_OFF python3 "$B/dispatch-rc" tidy > "$T/out" 2>&1
has "$T/open.calls" "open -g -a Terminal $HOME/Library/Caches/run-seed/tidy-close.command" "a window yabai would not close: a closing window opened in the background"
has "$T/open.calls" "parses" "  its .command parses"
has "$HOME/Library/Caches/run-seed/tidy-close.command" "close (every window whose id is (contents of i))" "  it closes by Terminal's own window id"
grep -q "and name contains .*tidy · closing" "$HOME/Library/Caches/run-seed/tidy-close.command"; check "$?" "0" "  and then itself, by tty and title"
has "$T/out" "closed 1 window(s)" "  and tidy counts it once it is gone"
python3 -c 'import sys, re; src = open(sys.argv[1]).read(); code = re.search(r"python3 -c (\x27)(.*?)\1", src, re.S).group(2); compile(code, "closer", "exec")' "$HOME/Library/Caches/run-seed/tidy-close.command"; check "$?" "0" "  its closer compiles"
# a recorded id never confirmed this pass — yabai down, or the window untitled out of view (after
# a reboot the id may be another window's): never handed to Terminal (re-review 2026-10-08)
for how in down blind; do
  rm -f "$HOME/Library/Caches/run-seed/tidy-close.command"; : > "$T/open.calls"
  # a pid that is gone — never `sleep & kill $!`: a child killed before it execs is still this
  # shell, and runs its EXIT trap (rm -rf "$T"); the suite lost $T that way once
  true & GP=$!; wait $GP
  printf '{"mode":"rc","repo":"%s","topic":"stale","pid":%s,"proc_start":"x","session":"st","started":%s,"window":16350,"screen":"run-repo-stale","screendir":"%s"}' \
    "$T/repo" $GP "$(date +%s)" "$HOME" > "$RUNS/00000000-000031-repo.stale.json"
  printf '[{"id": 16350, "app": "Terminal", "title": "", "space": 1, "is-visible": false, "has-ax-reference": false}]' > "$T/windows.json"
  if [ $how = down ]; then YABAI_OFF=1 YABAI_STUCK=1 DISPATCH_OPEN="$T/open-tc" python3 "$B/dispatch-rc" tidy > "$T/out" 2>&1
  else YABAI_STUCK=1 DISPATCH_OPEN="$T/open-tc" env -u YABAI_OFF python3 "$B/dispatch-rc" tidy > "$T/out" 2>&1; fi
  check "$([ -f "$HOME/Library/Caches/run-seed/tidy-close.command" ] && echo written || echo none)" "none" \
    "  a recorded id not confirmed this pass ($how) is never closed through Terminal"
  rm -f "$RUNS/00000000-000031-repo.stale.json"
done

echo "tidy: the 10-minute job"
mkdir -p "$T/stub"
cat > "$T/stub/launchctl" <<EOF
#!/bin/sh
echo "launchctl \$*" >> "$T/launchctl.calls"
case "\$1" in print) exit 1;; esac
exit 0
EOF
chmod +x "$T/stub/launchctl"
SP2="$HOME/Library/LaunchAgents/org.example.claude.dispatch-tidy.plist"
PATH="$T/stub:$PATH" python3 "$B/dispatch-rc" schedule-tidy > "$T/out" 2>&1
check "$([ -f "$SP2" ] && echo written || echo missing)" "written" "schedule-tidy writes the plist"
check "$(python3 -c 'import plistlib,sys; d=plistlib.load(open(sys.argv[1],"rb")); print(d["StartInterval"], d["ProgramArguments"][-1])' "$SP2")" \
  "600 tidy" "  every 10 min, running dispatch-rc tidy"
grep -q -- "sweep" "$SP2"; check "$?" "1" "  and never called sweep: autofinish --sweep is the launch pass"
has "$T/launchctl.calls" "bootstrap" "  and loaded into launchd"
python3 -c 'import plistlib,sys; print(plistlib.load(open(sys.argv[1],"rb"))["ProgramArguments"][0])' "$SP2" | grep -q "/.claude/worktrees/"
check "$?" "1" "  calling the primary checkout, not the worktree it was installed from (which is removed once it launches)"
# refresh-tidy: an installed tidier on an older plist is brought up to this code; an up-to-date one, or none, is left
: > "$T/launchctl.calls"
PATH="$T/stub:$PATH" python3 "$B/dispatch-rc" refresh-tidy > "$T/out" 2>&1
grep -q bootstrap "$T/launchctl.calls"; check "$?" "1" "refresh-tidy: an up-to-date tidier is left alone"
python3 -c 'import plistlib,sys; d=plistlib.load(open(sys.argv[1],"rb")); d["StartInterval"]=3600; plistlib.dump(d, open(sys.argv[1],"wb"))' "$SP2"
PATH="$T/stub:$PATH" python3 "$B/dispatch-rc" refresh-tidy > "$T/out" 2>&1
check "$(python3 -c 'import plistlib,sys; print(plistlib.load(open(sys.argv[1],"rb"))["StartInterval"])' "$SP2")" "600" "  the hourly one of before 2026-10-08 is rewritten every 10 min"
has "$T/launchctl.calls" "bootstrap" "  and reloaded"
PATH="$T/stub:$PATH" python3 "$B/dispatch-rc" unschedule-tidy > "$T/out" 2>&1
check "$([ -f "$SP2" ] && echo present || echo gone)" "gone" "unschedule-tidy removes it"
: > "$T/launchctl.calls"
PATH="$T/stub:$PATH" python3 "$B/dispatch-rc" refresh-tidy > "$T/out" 2>&1
check "$([ -f "$SP2" ] && echo present || echo absent) $(wc -c < "$T/launchctl.calls" | tr -d ' ')" "absent 0" "  refresh-tidy where none is installed: nothing (opt-in per Mac)"

echo "session-asks R2: a managed run that ends on the WAITING line without bin/ask is failed"
GW="$T/gw"; mkdir -p "$GW" "$HOME/.claude/projects/-g"; git -C "$GW" init -q
wl() { printf '{"type":"assistant","message":{"content":[{"type":"text","text":"done.\\n\\n%s"}]}}\n' "$1" > "$HOME/.claude/projects/-g/$2.jsonl"; }
wl "SAM, THIS SESSION IS WAITING FOR YOU — D1, the cadence" g1
guard() { python3 -c "import importlib.machinery as m, sys; rc=m.SourceFileLoader('rc', '$B/dispatch-rc').load_module(); print(rc.ask_guard(dict(session=sys.argv[1], manager=sys.argv[2], wt='$GW')))" "$@"; }
has <(guard g1 mgr-12345678) "failed: ended on the WAITING line with manager mgr-1234 live" "no ask.json: failed"
check "$(guard g1 '')" "None" "  a run with no manager may end on it (R6)"
mkdir -p "$GW/.git/claude"; echo '{"verdict": "none", "session": "g1"}' > "$GW/.git/claude/ask.json"
check "$(guard g1 mgr-1)" "None" "  bin/ask said nobody was there, for this session: allowed"
echo '{"verdict": "none", "session": "an-earlier-run"}' > "$GW/.git/claude/ask.json"
has <(guard g1 mgr-1) "failed:" "  finding 9: an earlier run's verdict is stale — failed"
wl "RELAYED TO coding-7 — D1, the cadence" g2
check "$(guard g2 mgr-1)" "None" "  the RELAYED line is not a WAITING line"
wl "SAM, THIS SESSION IS WAITING FOR YOU — the next step waits for a run to end (dispatch --next once one has)" g3
check "$(guard g3 mgr-1)" "None" "  finding 7: dispatch's own run-cap refusal is no ask"
wl "SAM, THIS SESSION IS WAITING FOR YOU — log in to gh on buildbox" g4
has <(guard g4 mgr-12345678) "failed: ended on the WAITING line" "  a manual step is"
wl "SAM, THIS SESSION IS WAITING FOR YOU — pick option A or B" g5
has <(guard g5 mgr-12345678) "failed: ended on the WAITING line" "  second review: any other WAITING line is an ask (the default flipped)"
wl "SAM, THIS SESSION IS WAITING FOR YOU — nothing to do yet; the reviewers are running" g6
check "$(guard g6 mgr-1)" "None" "  'nothing to do' is not"
echo "session-asks R2, finding 10: a headless run's guard is stored on its record"
# a claude that ends its turn on STUB_LAST: written as the session's transcript, which the guard reads
cat > "$T/askclaude" <<EOF
#!/bin/sh
sid=""; prev=""; for a in "\$@"; do [ "\$prev" = --session-id ] && sid="\$a"; prev="\$a"; done
mkdir -p "\$HOME/.claude/projects/-stub"
printf '{"type":"assistant","message":{"content":[{"type":"text","text":"done.\\\\n\\\\n%s"}]}}\n' "\$STUB_LAST" > "\$HOME/.claude/projects/-stub/\$sid.jsonl"
echo ok
EOF
chmod +x "$T/askclaude"
"$B/dispatch" $BR --repo "$T/repo" --at "$FUT 04:10" >/dev/null; P=$(pl); PL=$(basename "$P" .plist)
DISPATCH_CLAUDE="$T/askclaude" STUB_LAST="SAM, THIS SESSION IS WAITING FOR YOU — D2, the region" DISPATCH_MANAGER=mgr-x DISPATCH_PLAN=mgr-x DISPATCH_LOG="$HOME/hl.log" DISPATCH_LABEL=$PL "$B/dispatch" $BR --repo "$T/repo" --headless
check "$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1])).get("ask_guard", "none")[:46])' "$(ls -t "$HOME/Library/Logs/claude-weekly/run-seed-runs"/*.json | head -1)")" "failed: ended on the WAITING line with manager" "  a managed headless run that asked the owner: failed, on its record"
"$B/dispatch" $BR --repo "$T/repo" --at "$FUT 04:10" >/dev/null; P=$(pl); PL=$(basename "$P" .plist)
DISPATCH_CLAUDE="$T/askclaude" STUB_LAST="RELAYED TO coding-7 — D2, the region" DISPATCH_MANAGER=mgr-x DISPATCH_PLAN=mgr-x DISPATCH_LOG="$HOME/hl2.log" DISPATCH_LABEL=$PL "$B/dispatch" $BR --repo "$T/repo" --headless
check "$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1])).get("ask_guard", "none"))' "$(ls -t "$HOME/Library/Logs/claude-weekly/run-seed-runs"/*.json | head -1)")" "none" "  one that relayed: nothing stored"

echo "claude-host (docs/tcc-one-identity-2026-10-18.md): once rc-hosts says so, the job and its claude go through it"
# rc-hosts --launcher's answer once this Mac's sitting is done; a stand-in claude-host that runs
# claude as its child and says which pids it and that child had
printf '#!/bin/sh\n[ "$1" = --launcher ] && echo "%s/fakehost"\n' "$T" > "$T/rch"; chmod +x "$T/rch"
cat > "$T/fakehost" <<EOF
#!/bin/sh
[ "\$1" = claude ] && shift
sleep 3 &   # a decoy child first, as the runner's \$(env | sed …) subshell was: a pgrep -P would take it
sh -c '"\$0" "\$@"; sleep 2' "$T/claude" "\$@" & c=\$!   # a child that lives a moment, as claude does
[ -n "\$CLAUDE_HOST_PIDFILE" ] && echo \$c > "\$CLAUDE_HOST_PIDFILE"   # what claude-host publishes
echo "\$\$ \$c" > "$T/fakehost.pids"; wait \$c
EOF
chmod +x "$T/fakehost"
DISPATCH_RCHOSTS="$T/rch" "$B/dispatch" $BR --repo "$T/repo" --at "$FUT 04:10" >/dev/null; P=$(pl); PL=$(basename "$P" .plist)
has "$P" "<array><string>$T/fakehost</string><string>$PRIM/modules/wharf-runs/bin/dispatch</string>" "the one-shot job starts dispatch through claude-host"
# …and names the overlay's shim where one is installed, the path its jobs always named (the stand-in)
: > "$OVL/bin/dispatch"
ovl_cfg; REGATTA_CONFIG="$T/config-ovl" DISPATCH_RCHOSTS="$T/rch" "$B/dispatch" $BR --repo "$T/repo" --at "$FUT 04:10" >/dev/null; P=$(pl)
has "$P" "<array><string>$T/fakehost</string><string>$OVL/bin/dispatch</string>" "  the overlay's shim, where an overlay is installed"
rm -f "$OVL/bin/dispatch"
"$B/dispatch" $BR --repo "$T/repo" --at "$FUT 04:10" >/dev/null; P=$(pl)
grep -q fakehost "$P"; check $? 1 "  and not before this Mac's sitting (rc-hosts says nothing)"
env -u DISPATCH_CLAUDE DISPATCH_RCHOSTS="$T/rch" "$B/dispatch" $BR --repo "$T/repo" --dry-run | grep -qF "run $T/fakehost claude "; check $? 0 "the run's claude is claude-host's claude mode"
PL=$(basename "$P" .plist); : > "$T/claude.calls"
env -u DISPATCH_CLAUDE DISPATCH_RCHOSTS="$T/rch" DISPATCH_LOG="$HOME/ch.log" DISPATCH_LABEL=$PL "$B/dispatch" $BR --repo "$T/repo" --headless
has "$HOME/ch.log" "== exit 0" "  a headless run through it runs to the end"
has "$T/claude.calls" "claude -p You are an unattended session" "  claude got the prompt"
read -r hpid kpid < "$T/fakehost.pids"
check "$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["pid"])' "$(ls -t "$HOME/Library/Logs/claude-weekly/run-seed-runs"/*.json | head -1)")" "$kpid" "  the record's pid is claude's, claude-host's child, not claude-host's ($hpid): sessions/<pid>.json is claude's"
env -u DISPATCH_CLAUDE DISPATCH_RCHOSTS="$T/rch" "$B/dispatch" --start "/finish x --unattended" "$T/repo" "finish · idle-check" --dry-run > "$T/out" 2>&1
hpfile=$(grep -o "CLAUDE_HOST_PIDFILE=[^ ]*" "$T/out" | head -1 | cut -d= -f2-)
check "${hpfile:+named}" "named" "a --start --dry-run prints the pid file claude-host would write"
mkdir -p "$(dirname "$hpfile")"; echo keep > "$hpfile"
env -u DISPATCH_CLAUDE DISPATCH_RCHOSTS="$T/rch" "$B/dispatch" --start "/finish x --unattended" "$T/repo" "finish · idle-check" --dry-run > /dev/null 2>&1
check "$(cat "$hpfile" 2>/dev/null)" "keep" "  and removes nothing: a dry run prints, it never deletes"
rm -f "$hpfile"

echo "the queue (docs/dispatch-queue-2026-10-25.md S1): one ref every host claims from by compare-and-swap"
# The home is a bare repo here, the logbook repo on the Macs; a second host is a second HOME (its own
# cache clone, reservations, records and LaunchAgents) beside the same home. Every name is synthetic.
git init -q --bare "$T/queue.git"
echo "$T/queue.git" > "$REGATTA_CONFIG/wharf-runs/queue-repo"
export DISPATCH_HOST=laptop
QB="$B/dispatch-queue"; HA="$T/home"; HB="$T/home-b"; mkdir -p "$HB/Library/LaunchAgents"   # HA is HOME
QC=(--cap 3 --launchctl "$T/launchctl" --prefix org.example.claude --jobbin "$B/dispatch")
QGIT=(env GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t git --git-dir="$T/queue.git")
qtree() { "${QGIT[@]}" ls-tree -r --name-only refs/regatta/queue 2>/dev/null | tr '\n' ' ' | sed 's/ $//'; }
cat > "$T/qget.py" <<'PY'
import json, sys
d = json.load(sys.stdin)
print(" ".join(",".join(sorted(d[k])) if isinstance(d.get(k), dict) else str(d.get(k)) for k in sys.argv[1:]))
PY
qget() { local k=$1; shift; "${QGIT[@]}" show "refs/regatta/queue:queue/$k.json" 2>/dev/null | python3 "$T/qget.py" "$@" 2>/dev/null; }
qplists() { ls "$1"/Library/LaunchAgents/org.example.claude.dispatch.*.q[0-9]*.plist 2>/dev/null; }
qreset() {
  "${QGIT[@]}" update-ref -d refs/regatta/queue 2>/dev/null
  rm -rf "$HA/Library/Caches/run-seed/queue" "$HA/Library/Caches/run-seed/queue-local" "$HB/Library/Caches/run-seed"
  rm -f $(qplists "$HA") $(qplists "$HB")
}
# a claimed entry's job run as launchd would: its environment, this checkout's dispatch with its arguments
cat > "$T/qfire.py" <<'PY'
import plistlib, shlex, sys
d = plistlib.load(open(sys.argv[1], "rb"))
env = " ".join("%s=%s" % (k, shlex.quote(v)) for k, v in d["EnvironmentVariables"].items())
a = d["ProgramArguments"]
a = a[next(i for i, x in enumerate(a) if x.endswith("/dispatch")) + 1:]   # past a launcher, if one went first
print("env %s %s %s" % (env, shlex.quote(sys.argv[2]), " ".join(shlex.quote(x) for x in a)))
PY
qfire() { python3 "$T/qfire.py" "$1" "$B/dispatch" > "$T/qfire.sh"; bash "$T/qfire.sh"; }
qenv() { python3 -c 'import plistlib, sys; print(plistlib.load(open(sys.argv[1], "rb"))["EnvironmentVariables"][sys.argv[2]])' "$@"; }
qreset

# a run now, here: enqueued, claimed with room, started by a job that runs at load
env -u DISPATCH_LABEL DISPATCH_MAX_RUNS=5 "$B/dispatch" $BR --repo "$T/repo" --on here --headless > "$T/out" 2>&1
check "$?" "0" "a run now, with a queue home: through the queue"
has "$T/out" "started from the queue: fleet:repo--demo (normal) on this Mac, at once" "  claimed here at once, with room"
QP=$(qplists "$HA" | head -1)
has "$QP" "<key>RunAtLoad</key>" "  its job runs at load: no calendar minute to wait for"
has "$QP" "<string>--from-queue</string>" "  as dispatch --from-queue…"
has "$QP" "<string>fleet:repo--demo</string>" "  …naming its entry"
has "$QP" "<string>--headless</string>" "  the run's flags travel in the entry"
has "$QP" "<key>DISPATCH_LOADED_AT</key>" "  its load time travels, for the load-to-start seconds"
check "$(qget repo--demo state claimed_by running_on priority)" "claimed laptop laptop normal" "  the entry in the ref: claimed by this host"
check "$("${QGIT[@]}" rev-list --count refs/regatta/queue)" "1" "  the ref is one orphan commit, however many writes (it never grows)"
check "$(python3 "$QB" reserved "${QC[@]}")" "1" "  the claim holds a slot until its record exists"
check "$(DISPATCH_MAX_RUNS=5 "$B/dispatch" --slots)" "1 5" "  --slots counts it beside the records"
: > "$T/claude.calls"
QLOG=$(qenv "$QP" DISPATCH_LOG)   # read first: the job removes its own plist at its end
DISPATCH_MAX_RUNS=5 qfire "$QP"
check "$([ -f "$QP" ] && echo kept || echo gone)" "gone" "  its plist went with it, as a one-shot's does"
has "$QLOG" "== from the queue: fleet:repo--demo (normal), " "the job's run says where it came from…"
has "$QLOG" "s from its job's load" "  …and its load-to-start seconds"
has "$QLOG" "== exit 0" "  it ran to its end"
check "$(grep -c '^DISPATCH_LOADED_AT=' "$T/env.calls")" "0" "  its session never sees the job's DISPATCH_LOADED_AT (the env -u lists)"
check "$(qtree)" "" "  its end removed the entry, by compare-and-swap (its session was the entry's)"
check "$(python3 "$QB" reserved "${QC[@]}")" "0" "  and its reservation went once its record existed"
check "$(python3 -c 'import json, sys; d = json.load(open(sys.argv[1])); print(d.get("queue"), d.get("prio"))' "$(ls -t "$RUNS"/*.json | head -1)")" \
  "fleet:repo--demo normal" "  the record names its entry and its rank"

echo "  the compare-and-swap: two writers from one fetched base, one wins"
cat > "$T/cas.py" <<'PY'
import importlib.machinery, os, sys
q = importlib.machinery.SourceFileLoader("dq", sys.argv[1]).load_module()
a, b = q.Fleet(sys.argv[2]), q.Fleet(sys.argv[2])
b.clone = a.clone.parent / "clone-b.git"
base_a, base_b = a.fetch(), b.fetch()
ea, eb = a.read(base_a), b.read(base_b)
ea["x"] = {"state": "queued", "by": "a"}
eb["x"] = {"state": "queued", "by": "b"}
print(a.push(a.write(ea, "a"), base_a)[0], b.push(b.write(eb, "b"), base_b)[0])
PY
check "$(python3 "$T/cas.py" "$QB" "$T/queue.git")" "ok lost" "  the second push from the same base is refused (--force-with-lease), never a silent overwrite"
qreset

echo "  two drains on one slot"
for b in q1 q2; do DISPATCH_QUEUE_NOW=$(( $(date +%s) - ${#b} )) python3 "$QB" enqueue --repo "$T/repo" --branch claude/laptop/2026-10-26-$b "${QC[@]}" >/dev/null; done
QC1=(--cap 1 --launchctl "$T/launchctl" --prefix org.example.claude --jobbin "$B/dispatch")
python3 "$QB" sweep "${QC1[@]}" > "$T/s1" 2>&1 & python3 "$QB" claim "${QC1[@]}" > "$T/s2" 2>&1 & wait
check "$(qplists "$HA" | wc -l | tr -d ' ')" "1" "the sweep and a claim at once on one free slot: one start (the reservation)"
check "$(qget repo--q1 state) $(qget repo--q2 state)" "claimed queued" "  the first in line claimed, the other left queued"
qreset

echo "  two hosts, one entry"
python3 "$QB" enqueue --repo "$T/repo" --branch claude/laptop/2026-10-26-q3 "${QC[@]}" >/dev/null
(HOME="$HB" python3 "$QB" claim --host buildbox "${QC[@]}" > "$T/c-b" 2>&1) & python3 "$QB" claim "${QC[@]}" > "$T/c-a" 2>&1 & wait
check "$(( $(qplists "$HA" | wc -l) + $(qplists "$HB" | wc -l) ))" "1" "two hosts claim one entry at once: one start in all"
check "$(qget repo--q3 claimed_by)" "$(grep -q claimed "$T/c-b" && echo buildbox || echo laptop)" "  the ref names the host that started it"
qreset

echo "  one branch, one host; the pin from a live run's --next"
python3 "$QB" enqueue --repo "$T/repo" --branch $BR "${QC[@]}" >/dev/null
HOME="$HB" python3 "$QB" claim --host buildbox "${QC[@]}" >/dev/null
env -u DISPATCH_LABEL "$B/dispatch" $BR --repo "$T/repo" --on here --headless > "$T/out" 2>&1
check "$?" "2" "a run of a branch claimed on another host is refused here"
has "$T/out" "claimed on buildbox" "  naming where it runs"
HOME="$HB" python3 "$QB" started fleet:repo--demo --session sess-q --host buildbox "${QC[@]}" >/dev/null
check "$(qget repo--demo state session)" "running sess-q" "the job's record exists: running, with its session"
HOME="$HB" python3 "$QB" enqueue --repo "$T/repo" --branch $BR --host buildbox --pin buildbox --by sess-q "${QC[@]}" > "$T/out"
has "$T/out" '"result": "replaced"' "a live run's --next (its session, its host) replaces that run's entry…"
check "$(qget repo--demo state host running_on)" "queued buildbox buildbox" "  …queued, pinned to the run's host, the branch live there"
python3 "$QB" claim "${QC[@]}" >/dev/null; check "$(qget repo--demo state)" "queued" "  another host never claims it"
python3 "$QB" list --all > "$T/out"; has "$T/out" "not here: pinned to buildbox" "  --queue says why not here"
HOME="$HB" python3 "$QB" ended --repo "$T/repo" --branch $BR --session sess-q --host buildbox "${QC[@]}" >/dev/null
check "$(qget repo--demo state host running_on)" "queued buildbox None" "the run it follows ends: the pinned --next survives, its branch free"
qreset
NB=claude/laptop/2026-10-04-step
# a fresh brief, committed last: the suite's earlier --next cases left work after the old one
rm -f "$W/scratch"; echo "# step 3 brief" > "$W/docs/handoff/2026-10-04-step.md"
git -C "$W" add docs; git -C "$W" commit -qm "step 3 brief"; own sess-A
FIRE=" " CLAUDE_UNATTENDED=dispatch nx > "$T/out" 2>&1; check "$?" "0" "an unattended run's --next, the queue on: enqueued, claimed here, confirmed from its log"
has "$T/out" "started: claude is running $NB" "  said as before"
check "$(qget repo--step state host by)" "claimed laptop sess-A" "  its entry pinned to this host, by the run's session"
qreset; own sess-A
FIRE=" " DISPATCH_MAX_RUNS=0 nx > "$T/out" 2>&1; check "$?" "2" "--next on a full host, the queue on: exit 2 as before…"
has "$T/out" "queued as fleet:repo--step (normal)" "  …queued, not refused"
has "$T/out" "the next step waits for a run to end" "  the cap's waiting words kept (CAP_RE, ASK_EXEMPT_RE key on them)"
check "$(qget repo--step state)" "queued" "  the entry waits in the ref"
qreset

echo "  a claim whose running write fails, past the lease: never re-claimed"
python3 "$QB" enqueue --repo "$T/repo" --branch claude/laptop/2026-10-26-lease "${QC[@]}" >/dev/null
OLD=$(( $(date +%s) - 1500 ))
HOME="$HB" DISPATCH_QUEUE_NOW=$OLD python3 "$QB" claim --host buildbox "${QC[@]}" >/dev/null
sleep 300 & LP=$!
mkdir -p "$HB/Library/Logs/claude-weekly/run-seed-runs"
printf '{"repo": "%s", "topic": "lease", "branch": "claude/laptop/2026-10-26-lease", "session": "sess-l", "pid": %s, "started": %s, "queue": "fleet:repo--lease"}' \
  "$T/repo" "$LP" $((OLD + 5)) > "$HB/Library/Logs/claude-weekly/run-seed-runs/lease.json"
echo "$T/no-such.git" > "$REGATTA_CONFIG/wharf-runs/queue-repo"
HOME="$HB" python3 "$QB" started fleet:repo--lease --session sess-l --host buildbox "${QC[@]}" > "$T/out"
has "$T/out" "(outbox)" "the claimer's running write cannot reach the home: its outbox holds it"
echo "$T/queue.git" > "$REGATTA_CONFIG/wharf-runs/queue-repo"
check "$(qget repo--lease state claimed_by)" "claimed buildbox" "  the ref says claimed, 25 min ago"
python3 "$QB" sweep "${QC[@]}" > "$T/out" 2>&1
check "$(qget repo--lease state claimed_by)" "claimed buildbox" "  another host's sweep past the 15-min lease never re-claims it…"
has "$T/out" "card queue-silent: fleet:repo--lease" "  …it cards it (queue-silent)"
has "$HA/Library/Logs/claude-weekly/queue.jsonl" '"card": "queue-silent"' "  the card in queue.jsonl"
HOME="$HB" python3 "$QB" sweep --host buildbox "${QC[@]}" >/dev/null 2>&1
check "$(qget repo--lease state session)" "running sess-l" "  the claimer's own sweep sends its outbox: running"
kill "$LP" 2>/dev/null; wait "$LP" 2>/dev/null
HOME="$HB" python3 "$QB" sweep --host buildbox "${QC[@]}" > "$T/out" 2>&1
check "$(qtree)" "" "  its run gone with no end recorded: the claimer's sweep takes the entry off, never requeues it…"
has "$T/out" "card queue-gone: fleet:repo--lease" "  …with a card (a requeue would start the step again over its work)"
qreset

echo "  the readers' rule: an unreadable queue is an entry"
echo "$T/no-such.git" > "$REGATTA_CONFIG/wharf-runs/queue-repo"
python3 "$QB" has --repo "$T/repo" --branch $BR > /dev/null; check "$?" "4" "the home unreachable: exit 4, which a reader counts as has-an-entry"
echo "$T/queue.git" > "$REGATTA_CONFIG/wharf-runs/queue-repo"
python3 "$QB" has --repo "$T/repo" --branch $BR > /dev/null; check "$?" "0" "  a read that saw none: 0"
blob=$(echo "{not json" | "${QGIT[@]}" hash-object -w --stdin)
sub=$(printf '100644 blob %s\tx.json\n' "$blob" | "${QGIT[@]}" mktree)
root=$(printf '040000 tree %s\tqueue\n' "$sub" | "${QGIT[@]}" mktree)
"${QGIT[@]}" update-ref refs/regatta/queue "$("${QGIT[@]}" commit-tree "$root" -m torn)"
python3 "$QB" has --repo "$T/repo" --branch $BR > /dev/null; check "$?" "4" "  a torn entry in the ref: 4 as well, never none"
check "$(python3 "$QB" list --json | python3 -c 'import json, sys; print(json.load(sys.stdin)["unreadable"])')" "True" "  --queue --json says unreadable"
qreset

echo "  confidential scopes: node-local, never the fleet ref"
printf '{"repos": {}, "scopes": {"vault": {"confidential": true, "repos": ["%s"]}}}' "$(cd "$T/repo" && pwd -P)" > "$T/reg-conf.json"
CLAUDE_REPOS_JSON="$T/reg-conf.json" python3 "$QB" enqueue --repo "$T/repo" --branch claude/laptop/2026-10-26-conf "${QC[@]}" > "$T/out"
has "$T/out" '"store": "local=vault"' "a confidential scope's branch queues in its node-local queue…"
check "$(qtree)" "" "  …never on the fleet ref"
check "$(ls "$HA/Library/Caches/run-seed/queue-local/vault")" "repo--conf.json" "  its entry a file in queue-local/<scope>/"
git init -q "$T/vaultrepo"
printf '{"repos": {}, "scopes": {"vault": {"confidential": true, "repos": ["%s"]}}}' "$(cd "$T/vaultrepo" && pwd -P)" > "$T/reg-cwd.json"
CLAUDE_REPOS_JSON="$T/reg-cwd.json" python3 "$QB" enqueue --repo "$T/repo" --branch claude/laptop/2026-10-26-conf2 --cwd "$T/vaultrepo" "${QC[@]}" > "$T/out"
has "$T/out" '"store": "local=vault"' "  so does an open repo's branch sent from a confidential scope's checkout (the caller's cwd)"
echo '{"repos": ' > "$T/reg-torn.json"
CLAUDE_REPOS_JSON="$T/reg-torn.json" env -u DISPATCH_LABEL "$B/dispatch" $BR --repo "$T/repo" --on here --headless > "$T/out" 2>&1
check "$?" "2" "a torn registry refuses the enqueue (torn reads as no scopes: the fence trap)"
has "$T/out" "registry (repos.json) is unreadable" "  saying why"
check "$(qtree)" "" "  nothing on the fleet ref"
git -C "$T/repo" checkout -q -b claude/laptop/2026-10-26-spawn main
mkdir -p docs/handoff; echo "# brief" > docs/handoff/2026-10-26-spawn.md; echo "deadbeef" > docs/handoff/2026-10-26-spawn.review
git add docs; git commit -qm "a reviewed spawn"; git checkout -q main
python3 "$QB" enqueue --repo "$T/repo" --branch claude/laptop/2026-10-26-spawn "${QC[@]}" > "$T/out"
has "$T/out" '"store": "local=_spawn"' "an unreviewed-at-claim seed (a .review: a spawn out of a node) waits node-local…"
has "$T/out" '"confined": true' "  …confined, until spawn_review_ok() checks it at claim (confidential-reach S6)"
check "$(qtree)" "" "  never the fleet ref"
qreset

echo "  a fire-time refusal goes back into the queue (G1)"
"$B/dispatch" $BR --repo "$T/repo" --at "$FUT 04:10" >/dev/null; P=$(pl); PL=$(basename "$P" .plist)
DISPATCH_MAX_RUNS=0 DISPATCH_LOG="$HA/qcap.log" DISPATCH_LABEL=$PL "$B/dispatch" $BR --repo "$T/repo" --headless
has "$HA/qcap.log" "FAILED: 0 other runs are busy" "a one-shot refused at its fire time by the cap…"
has "$HA/qcap.log" "== queued: this Mac skips it for an hour" "  …is queued, not lost"
check "$(qget repo--demo state refused_by)" "queued laptop" "  its entry names the host that refused it"
python3 "$QB" claim "${QC[@]}" >/dev/null; check "$(qget repo--demo state)" "queued" "  that host skips it for the hour"
HOME="$HB" python3 "$QB" claim --host buildbox "${QC[@]}" >/dev/null; check "$(qget repo--demo state claimed_by)" "claimed buildbox" "  a host with room claims it"
QPB=$(qplists "$HB" | head -1); QLB=$(qenv "$QPB" DISPATCH_LOG)
(export HOME="$HB" DISPATCH_HOST=buildbox DISPATCH_MAX_RUNS=0; qfire "$QPB")
check "$(qget repo--demo state refused_by)" "queued buildbox,laptop" "a claimed job refused at fire time: back to queued, that host noted too"
has "$QLB" "== queued again" "  said in its log"

echo "  --queue, --status, --cancel; the priority"
env -u DISPATCH_LABEL "$B/dispatch" --queue --all > "$T/out"; has "$T/out" "fleet:repo--demo" "dispatch --queue lists it"
"$B/dispatch" --status > "$T/out" 2>&1; has "$T/out" "queue fleet · queued normal" "--status shows the queue's rows"
env -u DISPATCH_LABEL "$B/dispatch" $BR --repo "$T/repo" --cancel > "$T/out" 2>&1
has "$T/out" "cancelled the queue entry fleet:repo--demo" "--cancel takes a queued entry off"
check "$(qtree)" "" "  gone from the ref"
python3 "$QB" enqueue --repo "$T/repo" --branch claude/laptop/2026-10-26-p1 --priority low "${QC[@]}" >/dev/null
DISPATCH_QUEUE_NOW=$(( $(date +%s) + 60 )) python3 "$QB" enqueue --repo "$T/repo" --branch claude/laptop/2026-10-26-p2 --priority high "${QC[@]}" >/dev/null
python3 "$QB" claim "${QC1[@]}" >/dev/null
check "$(qget repo--p2 state) $(qget repo--p1 state)" "claimed queued" "high before an older low"
CLAUDE_UNATTENDED=dispatch env -u DISPATCH_LABEL "$B/dispatch" $BR --repo "$T/repo" --on here --priority high > "$T/out" 2>&1
check "$?" "2" "an unattended caller raising --priority is refused"
qreset

echo "  the home unreachable: the run still starts here, its entry in the outbox"
echo "$T/no-such.git" > "$REGATTA_CONFIG/wharf-runs/queue-repo"
env -u DISPATCH_LABEL DISPATCH_MAX_RUNS=5 "$B/dispatch" $BR --repo "$T/repo" --on here --headless > "$T/out" 2>&1
check "$?" "0" "a run now with the home unreachable…"
has "$T/out" "waits in this Mac's outbox" "  its entry waits in the outbox"
has "$T/out" "started from the queue: fleet:repo--demo" "  and it is claimed here: nobody else can have seen it"
QPO=$(qplists "$HA" | head -1); QLO=$(qenv "$QPO" DISPATCH_LOG)
check "$(python3 "$QB" mine fleet:repo--demo --label "$(qenv "$QPO" DISPATCH_LABEL)" "${QC[@]}")" "mine" \
  "items 4 and 15: offline, its job's check says yes: its own put and claim in the outbox, the key never fetched"
python3 "$QB" mine fleet:repo--demo --label org.example.claude.dispatch.repo.demo.q0 "${QC[@]}" > /dev/null
check "$?" "4" "  another job's label offline: unreadable (4), never a yes"
DISPATCH_MAX_RUNS=5 qfire "$QPO"
has "$QLO" "== exit 0" "  the job fires with the home still down and runs to its end (it never did: the case never fired it)"
echo "$T/queue.git" > "$REGATTA_CONFIG/wharf-runs/queue-repo"
python3 "$QB" claim "${QC[@]}" >/dev/null 2>&1
check "$(qtree)" "" "  once the home answers, the outbox lands its put, claim, start and end in one round: gone"
check "$(ls "$HA/Library/Caches/run-seed/queue/outbox" | wc -l | tr -d ' ')" "0" "  and the outbox is empty"
qreset
echo "  the landing review's fixes (docs/dispatch-queue-s1-review-2026-10-26.md), one case each"
QC2=(--cap 2 --launchctl "$T/launchctl" --prefix org.example.claude --jobbin "$B/dispatch")
qload() { python3 -c 'import importlib.machinery, sys; q = importlib.machinery.SourceFileLoader("dq", sys.argv[1]).load_module(); print(eval(sys.argv[2]))' "$QB" "$1"; }
qlocal() { python3 "$T/qget.py" "${@:2}" < "$HA/Library/Caches/run-seed/queue-local/vault/$1.json" 2>/dev/null; }
# item 15: S1 stays dark until the key is set on purpose — helm/logbook-repo alone, which every Mac has, is no home
rm -f "$REGATTA_CONFIG/wharf-runs/queue-repo"; mkdir -p "$REGATTA_CONFIG/helm"; echo "$T/queue.git" > "$REGATTA_CONFIG/helm/logbook-repo"
python3 "$QB" home > /dev/null; check "$?" "1" "item 15: helm/logbook-repo alone turns no queue on (until S2)"
env -u DISPATCH_LABEL DISPATCH_MAX_RUNS=5 "$B/dispatch" $BR --repo "$T/repo" --on here --headless > "$T/out" 2>&1
has "$T/out" "through launchd, in about" "  a run now is a one-shot, as before the queue"
check "$(qtree)" "" "  and nothing reaches the ref"
env -u DISPATCH_LABEL "$B/dispatch" $BR --repo "$T/repo" --cancel > /dev/null 2>&1
rm -f "$REGATTA_CONFIG/helm/logbook-repo"; echo "$T/queue.git" > "$REGATTA_CONFIG/wharf-runs/queue-repo"
# item 1: an unattended caller cannot raise through the queue's own verb either
# (DISPATCH_LABEL unset: the suite exports one, and a fired job — a guarded dispatch's — passes)
CLAUDE_UNATTENDED=dispatch env -u DISPATCH_LABEL python3 "$QB" enqueue --repo "$T/repo" --branch claude/laptop/2026-10-26-raise --priority force "${QC[@]}" > /dev/null 2>"$T/err"
check "$?" "2" "item 1: an unattended dispatch-queue enqueue --priority force is refused"
has "$T/err" "never raises a run's priority" "  saying why"
CLAUDE_UNATTENDED=dispatch env -u DISPATCH_LABEL python3 "$QB" enqueue --repo "$T/repo" --branch claude/laptop/2026-10-26-raise --arg=--priority --arg=high "${QC[@]}" > /dev/null 2>&1
check "$?" "2" "  so is a priority carried as the entry's flag"
CLAUDE_UNATTENDED=dispatch env -u DISPATCH_LABEL python3 "$QB" enqueue --repo "$T/repo" --branch claude/laptop/2026-10-26-raise --arg=--yolo "${QC[@]}" > /dev/null 2>&1
check "$?" "2" "  and --yolo above the branch's mode"
check "$(qtree)" "" "  nothing reaches the ref"
check "$(grep -c 'Bash(\*dispatch-queue enqueue\*)' "$B/dispatch") $(grep -c 'Bash(\*dispatch-queue claim\*)' "$B/dispatch") $(grep -c 'Bash(\*dispatch-queue sweep\*)' "$B/dispatch")" "1 1 1" \
  "  a run's denied list names enqueue, claim and sweep, which claims too (the habit guard; the second review's item 22)"
# item 10: what the queue alone refuses exits 1, so dispatch takes the one-shot
python3 "$QB" enqueue --repo "$T/repo" --branch feature/x "${QC[@]}" > /dev/null 2>&1; check "$?" "1" "item 10: a branch that is not claude/*: exit 1, the one-shot as before"
python3 "$QB" enqueue --repo "$T/repo" --branch claude/laptop/2026-10-26-long --arg=--note "--arg=$(printf '%4001s' x)" "${QC[@]}" > /dev/null 2>&1
check "$?" "1" "  a note past its pattern: exit 1 too"
# item 11: a claim holds only for the entry it looked at
check "$(qload 'q.apply_op({"k": {"state": "queued", "id": "B"}}, {"op": "claim", "key": "k", "host": "laptop", "at": 1, "cond": {"id": "A"}})[1]')" "taken" \
  "item 11: a claim of an entry a put replaced meanwhile (another id) takes nothing"
# item 12: a landing peer counts only with the ssh alias autofinish-run's launch needs
echo "laptop:elsewhere" > "$REGATTA_CONFIG/wharf-runs/finish-on"
check "$(qload 'q.landing_peer("laptop")')" "False" "item 12: a finish-on peer with no ssh alias is no landing peer"
echo "laptop:buildbox" > "$REGATTA_CONFIG/wharf-runs/finish-on"
check "$(qload 'q.landing_peer("laptop")')" "True" "  one with an alias is"
check "$(qload '(setattr(q.common, "autofinish_armed", lambda: None), q.claimable({"state": "queued", "branch": "claude/laptop/2026-10-27-y4", "repo": q.repo_word("'"$T/repo"'"), "mode": "yolo"}, "laptop"))[1]')" \
  "a yolo run's launch cannot run here (autofinish disarmed here)" \
  "fourth review: a disarmed host with a landing peer still may not claim a yolo entry (autofinish-run keeps mode launches here)"
rm -f "$REGATTA_CONFIG/wharf-runs/finish-on"
# item 20: an entry naming a login is this host's, where that login is
python3 "$QB" enqueue --repo "$T/repo" --branch claude/laptop/2026-10-26-acct --arg=--account --arg=acct-x "${QC[@]}" > /dev/null
check "$(qget repo--acct host)" "laptop" "item 20: an entry with --account LABEL is pinned to the host that named it"
python3 "$QB" enqueue --repo "$T/repo" --branch claude/laptop/2026-10-26-auto --arg=--account --arg=auto "${QC[@]}" > /dev/null
check "$(qget repo--auto host)" "" "  --account auto is no pin"
python3 "$QB" enqueue --repo "$T/repo" --branch claude/laptop/2026-10-27-acr --arg=--account --arg=acct-x --refused "the run cap (3 of 3 busy on laptop)" "${QC[@]}" > /dev/null
check "$(qget repo--acr host refused_by attempts)" "laptop None 1" \
  "fourth review: a one-shot refused at fire time and pinned here by its login skips no hour here (item 15's rule on enqueue --refused)"
qreset

echo "  item 2: a claim the home did not take is no claim"
python3 "$QB" enqueue --repo "$T/repo" --branch claude/laptop/2026-10-26-down "${QC[@]}" > /dev/null
printf '#!/bin/sh\nexit 1\n' > "$T/queue.git/hooks/pre-receive"; chmod +x "$T/queue.git/hooks/pre-receive"
python3 "$QB" claim "${QC[@]}" > "$T/out" 2>&1
check "$(qplists "$HA" | wc -l | tr -d ' ')" "0" "a home that refuses the push (fetch still works): no job starts"
check "$(qget repo--down state)" "queued" "  the entry is still queued"
check "$(ls "$HA/Library/Caches/run-seed/queue/outbox" 2>/dev/null | wc -l | tr -d ' ')" "0" "  and no claim waits in the outbox"
check "$(python3 "$QB" reserved "${QC[@]}")" "0" "  its slot is given back"
rm -f "$T/queue.git/hooks/pre-receive"
python3 "$QB" claim "${QC[@]}" > /dev/null 2>&1
check "$(qget repo--down state)" "claimed" "  once the home takes pushes, a claim lands"
qreset

echo "  item 6: two claims of one entry on one host, in one second"
python3 "$QB" enqueue --repo "$T/repo" --branch claude/laptop/2026-10-26-twice "${QC[@]}" > /dev/null
python3 "$QB" claim "${QC2[@]}" > "$T/s1" 2>&1 & python3 "$QB" claim "${QC2[@]}" > "$T/s2" 2>&1 & wait
check "$(qplists "$HA" | wc -l | tr -d ' ')" "1" "one host, cap 2, two claims at once: one job"
check "$(cat "$T/s1" "$T/s2" | grep -c '^claimed')" "1" "  one claimer says claimed"
check "$(qget repo--twice attempts)" "1" "  one attempt in the entry"
check "$(python3 "$QB" reserved "${QC[@]}")" "1" "  the winner's reservation stands (the loser drops only its own)"
qreset

echo "  items 7 and 5: a live run's --next on a full host; its reservation and its record"
sleep 120 & C7=$!
printf '{"mode":"headless","repo":"%s","topic":"chain7","branch":"claude/laptop/2026-10-26-chain7","pid":%s,"proc_start":"%s","session":"s-c7","started":%s}' \
  "$T/repo" $C7 "$(pst $C7)" "$(date +%s)" > "$RUNS/00000000-000071-repo.chain7.json"
check "$(python3 "$B/dispatch-rc" unfinished "$(cd "$T/repo" && pwd -P)" chain7)" "1" "a run recorded under one spelling of its repo is found by its real path (after(): the queue's job names it resolved)"
python3 "$QB" enqueue --repo "$T/repo" --branch claude/laptop/2026-10-26-other7 --claim "${QC1[@]}" > "$T/out"
has "$T/out" '"claimed": []' "cap 1, a run of another topic live: no room for this one"
python3 "$QB" enqueue --repo "$T/repo" --branch claude/laptop/2026-10-26-chain7 --pin laptop --by s-c7 --claim "${QC1[@]}" > "$T/out"
has "$T/out" '"claimed": ["fleet:repo--chain7"]' "item 7: the live run's own --next is claimed: the run it waits for is not counted"
check "$(python3 "$QB" reserved "${QC[@]}")" "0" "  its claim is reserved waiting: the live run it follows holds the one slot, never both (the fourth review)…"
printf '{"repo": "%s", "topic": "chain7", "session": "s-c7b", "pid": 4000000, "started": %s, "queue": "fleet:repo--chain7"}' "$T/repo" "$(( $(date +%s) + 1 ))" \
  > "$RUNS/00000000-000072-repo.chain7.json"
check "$(python3 "$QB" reserved "${QC[@]}")" "0" "item 5: …until its run's record exists: then live() counts it, never both"
kill $C7 2>/dev/null; wait $C7 2>/dev/null; rm -f "$RUNS"/00000000-00007*
qreset

echo "  items 19 and 3: a re-dispatch on the branch's host; a stale job"
python3 "$QB" enqueue --repo "$T/repo" --branch claude/laptop/2026-10-26-re19 "${QC[@]}" > /dev/null
python3 "$QB" claim "${QC[@]}" > /dev/null; QP19=$(qplists "$HA" | head -1)
python3 "$QB" started fleet:repo--re19 --session s19 "${QC[@]}" > /dev/null
python3 "$QB" enqueue --repo "$T/repo" --branch claude/laptop/2026-10-26-re19 "${QC[@]}" > "$T/out"; rc=$?
check "$rc" "0" "item 19: a re-dispatch on the host the branch runs on is taken, not refused busy"
has "$T/out" '"result": "replaced"' "  it replaces the live entry"
check "$(qget repo--re19 state host running_on)" "queued laptop laptop" "  queued, pinned to that host, so after() waits for the earlier run"
: > "$T/claude.calls"; QL19=$(qenv "$QP19" DISPATCH_LOG)
qfire "$QP19"
has "$QL19" "== a stale queue job: fleet:repo--re19 is not this job's claim now (it is queued); not running" "item 3: the replaced entry's job fires: not its claim, not run"
check "$(wc -c < "$T/claude.calls" | tr -d ' ')" "0" "  no session"
check "$(qget repo--re19 state)" "queued" "  and the new entry is left as it is (no failed sent)"
qreset
python3 "$QB" enqueue --repo "$T/repo" --branch claude/laptop/2026-10-26-boot3 "${QC[@]}" > /dev/null
python3 "$QB" claim "${QC[@]}" > /dev/null; QP3=$(qplists "$HA" | head -1); QL3=$(qenv "$QP3" DISPATCH_LOG)
python3 "$QB" started fleet:repo--boot3 --session s3 "${QC[@]}" > /dev/null
qfire "$QP3"
has "$QL3" "== a stale queue job: fleet:repo--boot3 is not this job's claim now (it is running)" "  a plist left by a reboot fires at login while its run is recorded: not run again"
check "$(qget repo--boot3 state session)" "running s3" "  its entry kept"
check "$([ -f "$QP3" ] && echo kept || echo gone)" "gone" "  and the stale plist removed"
qreset

echo "  items 9 and 13: the put landed, its claim failed"
mkdir -p "$HA/Library/Caches/run-seed/queue-local/vault"; echo "{not json" > "$HA/Library/Caches/run-seed/queue-local/vault/other.json"
python3 "$QB" enqueue --repo "$T/repo" --branch claude/laptop/2026-10-26-torn9 --claim "${QC[@]}" > "$T/out"; rc=$?
check "$rc" "0" "item 9: a torn local queue during the claim: the enqueue still exits 0…"
has "$T/out" '"claimed": ["fleet:repo--torn9"]' "  …and the torn store skips only itself: the fleet entry is claimed (second review)"
python3 "$QB" has --repo "$T/repo" --branch claude/laptop/2026-10-27-open12 "${QC[@]}" > /dev/null
check "$?" "4" "fourth review: has of an open branch with a scope's store torn: 4, never none (enqueue routed by a cwd has cannot see)"
env -u DISPATCH_LABEL DISPATCH_MAX_RUNS=5 "$B/dispatch" $BR --repo "$T/repo" --on here --headless > "$T/out" 2>&1
has "$T/out" "started from the queue: fleet:repo--demo" "item 13: through dispatch, the run goes through the queue…"
check "$(pl | wc -l | tr -d ' ')" "0" "  …and no one-shot beside it"
check "$(qget repo--demo state)" "claimed" "  the entry claimed in the ref"
qreset

echo "  item 14: a --next through the queue replaces the branch's pending one-shot"
own sess-A; "$B/dispatch" $NB --repo "$T/repo" --at "$FUT 04:10" > /dev/null 2>&1
check "$(ls "$HOME"/Library/LaunchAgents/org.example.claude.dispatch.repo.step.[0-9]*.plist 2>/dev/null | wc -l | tr -d ' ')" "1" "a pending one-shot of the step's branch"
FIRE=" " DISPATCH_MAX_RUNS=0 nx > "$T/out" 2>&1
has "$T/out" "replaced the pending" "  a --next, queued: it replaces the pending one-shot…"
check "$(ls "$HOME"/Library/LaunchAgents/org.example.claude.dispatch.repo.step.[0-9]*.plist 2>/dev/null | wc -l | tr -d ' ')" "0" "  …which is gone"
qreset

echo "  item 4: a one-shot refused at fire time queues where its caller's cwd says"
(cd "$T/vaultrepo" && env -u DISPATCH_LABEL "$B/dispatch" $BR --repo "$T/repo" --at "$FUT 04:10" > /dev/null 2>&1); P=$(pl); PL=$(basename "$P" .plist)
has "$P" "<key>DISPATCH_ORIGIN</key>" "the one-shot records its caller's cwd"
DISPATCH_ORIGIN="$(qenv "$P" DISPATCH_ORIGIN)" CLAUDE_REPOS_JSON="$T/reg-cwd.json" DISPATCH_MAX_RUNS=0 DISPATCH_LOG="$HA/q4.log" DISPATCH_LABEL=$PL \
  "$B/dispatch" $BR --repo "$T/repo" --headless
has "$HA/q4.log" "== queued: this Mac skips it" "  refused by the cap at fire time, it is queued…"
check "$(qlocal repo--demo state)" "queued" "  …in the caller's confidential scope"
check "$(qtree)" "" "  never on the fleet ref"
env -u DISPATCH_LABEL "$B/dispatch" $BR --repo "$T/repo" --cancel > /dev/null 2>&1
qreset

echo "  item 18: a node-local queue writes its claims"
CLAUDE_REPOS_JSON="$T/reg-conf.json" python3 "$QB" enqueue --repo "$T/repo" --branch claude/laptop/2026-10-26-conf18 --claim "${QC[@]}" > "$T/out"
has "$T/out" '"claimed": ["local=vault:repo--conf18"]' "a confidential entry is claimed here…"
check "$(qlocal repo--conf18 state claimed_by)" "claimed laptop" "item 18: …and the claim is on disk"
CLAUDE_REPOS_JSON="$T/reg-conf.json" python3 "$QB" started local=vault:repo--conf18 --session s18 "${QC[@]}" > /dev/null
check "$(qlocal repo--conf18 state session)" "running s18" "  so is its start"
CLAUDE_REPOS_JSON="$T/reg-conf.json" python3 "$QB" claim "${QC[@]}" > /dev/null
check "$(qplists "$HA" | wc -l | tr -d ' ')" "1" "  and a later claim pass never starts it again"
CLAUDE_REPOS_JSON="$T/reg-conf.json" python3 "$QB" ended --repo "$T/repo" --branch claude/laptop/2026-10-26-conf18 --session s18 "${QC[@]}" > /dev/null
check "$(ls "$HA/Library/Caches/run-seed/queue-local/vault" | grep -c conf18)" "0" "  its end removes it"
qreset

echo "  item 17: one key, two branches"
python3 "$QB" enqueue --repo "$T/repo" --branch claude/laptop/2026-10-26-same "${QC[@]}" > /dev/null
python3 "$QB" enqueue --repo "$T/repo" --branch claude/buildbox/2026-10-27-same "${QC[@]}" > /dev/null 2>"$T/err"
check "$?" "1" "a second branch of the same topic never replaces the first's entry (exit 1: a one-shot)"
check "$(qget repo--same branch)" "claude/laptop/2026-10-26-same" "  the first branch's entry stands"
python3 "$QB" has --repo "$T/repo" --branch claude/buildbox/2026-10-27-same > /dev/null; check "$?" "0" "  has: no entry for the other branch"
python3 "$QB" cancel --repo "$T/repo" --branch claude/buildbox/2026-10-27-same > /dev/null; check "$?" "1" "  cancel of the other branch takes nothing"
check "$(qtree)" "queue/repo--same.json" "  the entry is still there"
qreset

echo "  items 22 and 23: a running entry with no record; a live entry nobody runs"
OLD=$(( $(date +%s) - 1500 ))
python3 "$QB" enqueue --repo "$T/repo" --branch claude/laptop/2026-10-26-norec "${QC[@]}" > /dev/null
HOME="$HB" DISPATCH_QUEUE_NOW=$OLD python3 "$QB" claim --host buildbox "${QC[@]}" > /dev/null
HOME="$HB" DISPATCH_QUEUE_NOW=$OLD python3 "$QB" started fleet:repo--norec --session s22 --host buildbox "${QC[@]}" > /dev/null
HOME="$HB" python3 "$QB" sweep --host buildbox "${QC[@]}" > "$T/out" 2>&1
check "$(qget repo--norec state session)" "running s22" "item 22: a running entry whose record does not read is never requeued past the lease"
has "$T/out" "card queue-gone: fleet:repo--norec" "  it is carded"
python3 "$QB" cancel --repo "$T/repo" --branch claude/laptop/2026-10-26-norec "${QC[@]}" > "$T/out"
has "$T/out" "dispatch claude/laptop/2026-10-26-norec --cancel there once its run is gone" "item 23: --cancel elsewhere names the host that can clear it"
HOME="$HB" python3 "$QB" cancel --repo "$T/repo" --branch claude/laptop/2026-10-26-norec --host buildbox "${QC[@]}" > "$T/out"
has "$T/out" "running here with no run behind it" "  --cancel on that host clears a live entry no run is behind"
check "$(qtree)" "" "  gone from the ref"
qreset

echo "  the second review: a claimed entry is its job's; mine offline; a fresh put; a stale job's word"
python3 "$QB" enqueue --repo "$T/repo" --branch claude/laptop/2026-10-26-held "${QC[@]}" > /dev/null
python3 "$QB" claim "${QC[@]}" > /dev/null; HJ=$(qget repo--held job)
python3 "$QB" enqueue --repo "$T/repo" --branch claude/laptop/2026-10-26-held "${QC[@]}" > "$T/out"; rc=$?
check "$rc" "0" "a re-dispatch here while its entry is claimed here (its job fired, past its check): exit 0…"
has "$T/out" '"result": "claimed here"' "  …the step is in hand: nothing replaced"
check "$(qget repo--held state job)" "claimed $HJ" "  the claim and its job stand"
python3 "$QB" failed fleet:repo--held --label org.example.claude.dispatch.repo.held.q0 "${QC[@]}" > /dev/null
check "$(qget repo--held state)" "claimed" "  a word from another job of the entry (its label) moves nothing"
check "$(grep '"card": "queue-failed"' "$HA/Library/Logs/claude-weekly/queue.jsonl" 2>/dev/null | grep -c 'repo--held')" "0" \
  "  …and cards nothing: a card about the newer claim would hide its own (the second review's item 16)"
echo "$T/no-such.git" > "$REGATTA_CONFIG/wharf-runs/queue-repo"
python3 "$QB" mine fleet:repo--held --label "$HJ" "${QC[@]}" > /dev/null; check "$?" "4" "mine with the home unreachable: 4, never a yes from the stale cache"
echo "$T/queue.git" > "$REGATTA_CONFIG/wharf-runs/queue-repo"
python3 "$QB" mine fleet:repo--held --label "$HJ" "${QC[@]}" > /dev/null; check "$?" "0" "  and 0 once the home answers"
# item 10: past the lease the reservation is gone; the stand-in launchctl runs no job, and no record exists
DISPATCH_QUEUE_NOW=$(( $(date +%s) + 1000 )) python3 "$QB" enqueue --repo "$T/repo" --branch claude/laptop/2026-10-26-held "${QC[@]}" > "$T/out"
has "$T/out" '"result": "replaced"' "item 10: a claim here with no job, no run and no reservation is dead: a re-dispatch replaces it"
check "$(qget repo--held state running_on)" "queued laptop" "  queued again, its branch still this host's"
python3 "$QB" enqueue --repo "$T/repo" --branch claude/laptop/2026-10-26-fresh --refused "the run cap" "${QC[@]}" > /dev/null
check "$(qget repo--fresh refused_by)" "laptop" "a fire-time refusal notes this host…"
python3 "$QB" enqueue --repo "$T/repo" --branch claude/laptop/2026-10-26-fresh "${QC[@]}" > /dev/null
check "$(qget repo--fresh refused_by)" "" "  …and a fresh dispatch from this host clears it (a person freed a slot)"
qreset

echo "  the second landing review (docs/dispatch-queue-s1-review-2-2026-10-26.md): the git plumbing"
QCL="$HA/Library/Caches/run-seed/queue/clone.git"
for b in w1 w2; do python3 "$QB" enqueue --repo "$T/repo" --branch claude/laptop/2026-10-26-$b "${QC[@]}" > /dev/null; done
check "$(git --git-dir="$QCL" rev-parse refs/regatta/queue)" "$("${QGIT[@]}" rev-parse refs/regatta/queue)" \
  "item 9: a push moves this host's own ref to what it wrote (offline views start from it)"
chmod -R a-w "$QCL/objects"
python3 "$QB" enqueue --repo "$T/repo" --branch claude/laptop/2026-10-26-w3 "${QC[@]}" > "$T/out" 2>&1
chmod -R u+w "$QCL/objects"
check "$(qtree)" "queue/repo--w1.json queue/repo--w2.json" "item 1: a write the cache clone cannot make deletes nothing in the ref (an empty push was git's delete)…"
has "$T/out" '"offline": "the cache clone could not write' "  …the put waits in the outbox, the reason said"
cat > "$T/q2.py" <<'PY'
import importlib.machinery, sys
q = importlib.machinery.SourceFileLoader("dq", sys.argv[1]).load_module()
f = q.Fleet(sys.argv[2])
f.ensure()
try:
    print(f.read("1" * 40))
except q.Torn as x:
    print("torn")
PY
check "$(python3 "$T/q2.py" "$QB" "$T/queue.git" 2>&1)" "torn" "item 2: a tree that does not list is torn, never an empty queue"
qreset
cat > "$T/qfetch.py" <<'PY'
import importlib.machinery, sys
q = importlib.machinery.SourceFileLoader("dq", sys.argv[1]).load_module()
try:
    q.Fleet(sys.argv[2]).fetch()
    print("ok")
except q.Unreachable as x:
    print("unreachable: %s" % x)
PY
QET=$("${QGIT[@]}" mktree < /dev/null); : > "$T/fetches"
for i in 1 2 3 4 5; do
  "${QGIT[@]}" update-ref refs/regatta/queue "$("${QGIT[@]}" commit-tree "$QET" -m "round $i")"
  for j in 1 2 3 4; do python3 "$T/qfetch.py" "$QB" "$T/queue.git" >> "$T/fetches" 2>&1 & done; wait
done
check "$(grep -c '^ok$' "$T/fetches") $(grep -c unreachable "$T/fetches")" "20 0" \
  "items 3 and 8: four fetches at once into the one clone, the home moved each round: none reads as unreachable"
qreset

echo "  the offline claim, a dead claim, --cancel of an outbox put, a refusal beside a live run"
echo "$T/no-such.git" > "$REGATTA_CONFIG/wharf-runs/queue-repo"
python3 "$QB" enqueue --repo "$T/repo" --branch claude/laptop/2026-10-26-c14 "${QC[@]}" > /dev/null
echo "$T/queue.git" > "$REGATTA_CONFIG/wharf-runs/queue-repo"
python3 "$QB" cancel --repo "$T/repo" --branch claude/laptop/2026-10-26-c14 "${QC[@]}" > "$T/out"
has "$T/out" "cancelled the queue entry fleet:repo--c14" "item 14: a put still in the outbox once the home is back: --cancel sends it, then takes it off"
python3 "$QB" claim "${QC[@]}" > /dev/null
check "$(qtree) $(ls "$HA/Library/Caches/run-seed/queue/outbox" 2>/dev/null | wc -l | tr -d ' ')" " 0" "  no later flush brings the cancelled run back"
qreset
QR="$HA/Library/Logs/claude-weekly/run-seed-runs"; mkdir -p "$QR"
sleep 300 & LP11=$!
printf '{"repo": "%s", "topic": "k11", "branch": "claude/laptop/2026-10-26-k11", "session": "s-one", "pid": %s, "started": %s}' \
  "$T/repo" "$LP11" "$(date +%s)" > "$QR/k11-oneshot.json"
python3 "$QB" enqueue --repo "$T/repo" --branch claude/laptop/2026-10-26-k11 "${QC[@]}" > /dev/null
python3 "$QB" started --repo "$T/repo" --branch claude/laptop/2026-10-26-k11 --session s-one "${QC[@]}" > /dev/null
python3 "$QB" claim "${QC[@]}" > /dev/null
python3 "$QB" refused fleet:repo--k11 --label "$(qget repo--k11 job)" --why "no account" "${QC[@]}" > /dev/null
check "$(qget repo--k11 state running_on)" "queued laptop" "item 11: a refusal beside a live one-shot of the branch here keeps its mark (one branch, one host)"
kill "$LP11" 2>/dev/null; wait "$LP11" 2>/dev/null; rm -f "$QR/k11-oneshot.json"
sleep 300 & LP13=$!
check "$(qload 'q.rec_alive({"pid": '"$LP13"', "proc_start": "Mon Jan  1 00:00:00 2001"})') $(qload 'q.rec_alive({"pid": 999999999, "watcher": '"$LP13"', "watcher_start": q.rc_mod().proc_start('"$LP13"')})')" \
  "False True" "item 13: a reused pid (another start time) is no run; a live watcher is one, its end not yet written"
kill "$LP13" 2>/dev/null; wait "$LP13" 2>/dev/null
qreset

echo "  the depth, a torn queue through dispatch, the job's own FAILED line, a claim at a run's end"
CLAUDE_UNATTENDED=dispatch DISPATCH_DEPTH=3 env -u DISPATCH_LABEL python3 "$QB" enqueue --repo "$T/repo" --branch claude/laptop/2026-10-26-d12 --env DISPATCH_DEPTH=1 "${QC[@]}" > /dev/null
check "$("${QGIT[@]}" show refs/regatta/queue:queue/repo--d12.json | python3 -c 'import json, sys; print(json.load(sys.stdin)["env"]["DISPATCH_DEPTH"])')" "4" \
  "item 12: an unattended caller's --env DISPATCH_DEPTH=1 cannot reset the chain: one deeper than its own"
CLAUDE_UNATTENDED=dispatch DISPATCH_LABEL=org.example.claude.dispatch.repo.x.q1 python3 "$QB" enqueue --repo "$T/repo" --branch claude/laptop/2026-10-26-l12 --priority force "${QC[@]}" > /dev/null 2>&1
check "$?" "2" "  a DISPATCH_LABEL no running job has is no fired job's: its raise is refused"
qreset
blob=$(echo "{not json" | "${QGIT[@]}" hash-object -w --stdin)
"${QGIT[@]}" update-ref refs/regatta/queue "$("${QGIT[@]}" commit-tree "$(printf '040000 tree %s\tqueue\n' "$(printf '100644 blob %s\tx.json\n' "$blob" | "${QGIT[@]}" mktree)" | "${QGIT[@]}" mktree)" -m torn)"
n5=$(ls "$HA/Library/LaunchAgents" | wc -l)
env -u DISPATCH_LABEL DISPATCH_MAX_RUNS=5 "$B/dispatch" $BR --repo "$T/repo" --on here --headless > "$T/out" 2>&1
check "$?" "2" "item 5: a queue that does not read: dispatch refuses, exit 2…"
has "$T/out" "the queue does not read" "  …saying so, with the waiting words"
check "$(ls "$HA/Library/LaunchAgents" | wc -l)" "$n5" "  and schedules no one-shot beside an entry it cannot see"
qreset
python3 "$QB" enqueue --repo "$T/repo" --branch claude/laptop/2026-10-26-y7 --claim "${QC[@]}" > /dev/null
P7=$(qplists "$HA" | head -1); L7=$(qenv "$P7" DISPATCH_LOG)
echo "FAILED: an earlier run of the day" >> "$L7"
python3 -c 'import plistlib, sys; d = plistlib.load(open(sys.argv[1], "rb")); d["EnvironmentVariables"]["DISPATCH_YEAR"] = "1999"; plistlib.dump(d, open(sys.argv[1], "wb"))' "$P7"
qfire "$P7" > /dev/null 2>&1
check "$(grep '"card": "queue-failed"' "$HA/Library/Logs/claude-weekly/queue.jsonl" | grep 'repo--y7' | tail -1 | python3 -c 'import json, sys; print(json.loads(sys.stdin.read())["why"])')" \
  "the run failed before it started" "item 7: a job that ends with no FAILED line of its own: its card never takes an earlier run's"
qreset
DISPATCH_QUEUE_NOW=$(( $(date +%s) + 60 )) python3 "$QB" enqueue --repo "$T/repo" --branch claude/laptop/2026-10-26-wait6 "${QC[@]}" > /dev/null
env -u DISPATCH_LABEL DISPATCH_MAX_RUNS=1 "$B/dispatch" $BR --repo "$T/repo" --on here --headless > "$T/out" 2>&1
check "$(qget repo--demo state) $(qget repo--wait6 state)" "claimed queued" "item 6: one slot: the run claimed, the other entry waits"
DISPATCH_MAX_RUNS=1 qfire "$(qplists "$HA" | head -1)"
check "$(qget repo--wait6 state)" "claimed" "  the run's end claims what waited for its slot"
qreset

echo "  a full host's pass, the flag lists, a dispatch of a branch claimed here"
for b in f1 f2 f3; do python3 "$QB" enqueue --repo "$T/repo" --branch claude/laptop/2026-10-26-$b "${QC[@]}" > /dev/null; done
nr=$(grep -c '"event": "no-room"' "$HA/Library/Logs/claude-weekly/queue.jsonl")
python3 "$QB" claim --cap 0 --launchctl "$T/launchctl" --prefix org.example.claude --jobbin "$B/dispatch" > /dev/null
check "$(( $(grep -c '"event": "no-room"' "$HA/Library/Logs/claude-weekly/queue.jsonl") - nr )) $(grep '"event": "no-room"' "$HA/Library/Logs/claude-weekly/queue.jsonl" | tail -1 | python3 -c 'import json, sys; print(len(json.loads(sys.stdin.read())["keys"]))')" \
  "1 3" "item 18: a full host's pass: one no-room line naming the three entries, not one each"
check "$(sed -n '/^queue_args() {/,/^}/p' "$B/dispatch" | grep -o -- '--arg=--[a-z-]*' | sed 's/^--arg=//' | LC_ALL=C sort -u | tr '\n' ' ' | sed 's/ $//')" \
  "$(qload '" ".join(sorted(q.FLAGS))')" "item 17: every flag queue_args carries is one FLAGS lets a claimed entry hand on, and every one FLAGS names is carried"
# the other two roads of the same flags: the --on command and the one-shot's plist (which carries the mode
# as DISPATCH_MODE in its environment); a flag FLAGS names that one of them drops is dropped silently there
cat > "$T/roads.py" <<'PY'
import importlib.machinery, re, sys
q = importlib.machinery.SourceFileLoader("dq", sys.argv[1]).load_module()
src = open(sys.argv[2]).read()
def road(start, end):
    m = re.search(start + r".*?" + end, src, re.S)
    return set(re.findall(r"--[a-z][a-z-]*", m.group(0))) if m else set()
on = road(r'cmd="\$\{menv# \}', r'cmd="\$cmd --dry-run"')
pl = road(r'args="<string>\$jobbin</string>', r'<string>--priority</string>')
print("on: %s; plist: %s" % (" ".join(sorted(set(q.FLAGS) - on)) or "-", " ".join(sorted(set(q.FLAGS) - {"--mode"} - pl)) or "-"))
PY
check "$(python3 "$T/roads.py" "$QB" "$B/dispatch")" "on: -; plist: -" "  …and the --on command and the plist carry every one too (the plist's mode in its environment)"
qreset
python3 "$QB" enqueue --repo "$T/repo" --branch $BR "${QC[@]}" > /dev/null; python3 "$QB" claim "${QC[@]}" > /dev/null
env -u DISPATCH_LABEL DISPATCH_MAX_RUNS=5 "$B/dispatch" $BR --repo "$T/repo" --on here --headless > "$T/out" 2>&1
check "$?" "0" "item 20: a dispatch of a branch whose entry is claimed here: exit 0…"
has "$T/out" "is claimed here already (queue entry fleet:repo--demo)" "  …said as such, never 'no room … queued'"
qreset

echo "  the third landing review (docs/dispatch-queue-s1-review-3-2026-10-27.md), one case each"
# a harness for the cases that stand a function in: the module loaded, a ctx as dispatch passes it
cat > "$T/q3.py" <<'PY'
import argparse, functools, importlib.machinery, json, sys, time
q = importlib.machinery.SourceFileLoader("dq", sys.argv[1]).load_module()
launchctl, jobbin, case = sys.argv[2], sys.argv[3], sys.argv[4]
ctx = argparse.Namespace(host=None, cap=3, launchctl=launchctl, prefix="org.example.claude", jobbin=jobbin, rch="")
def boom(*a, **k):
    raise q.Torn("torn between the view and the CAS")
def crash(*a, **k):
    raise RuntimeError("a crash")
if case == "torn-do":
    q.Fleet.do = boom
    got = q.claim(ctx)
    print(len(got), len(q.reservations(launchctl)))
elif case == "start-lock":
    q.start_lock = functools.partial(q.start_lock, wait=1)
    got = q.claim(ctx)
    print(len(got), ctx.no_room)
elif case == "headroom":
    n = []
    q.headroom_refuses = lambda: n.append(1)
    q.claim(ctx)
    print(len(n))
elif case == "crash":
    q.cmd_list = crash
    print(q.main(["list"]))
elif case == "dead-crash":
    q.claim_dead = crash
    print(q.main(["enqueue", "--repo", sys.argv[5], "--branch", sys.argv[6], "--cap", "3", "--launchctl", launchctl,
                  "--prefix", "org.example.claude", "--jobbin", jobbin]))
elif case == "down-memo":
    calls = []
    real = q.Fleet.git
    def git(self, *a, **k):
        calls.append(a[0])
        return real(self, *a, **k)
    q.Fleet.git = git
    try:
        q.Fleet(sys.argv[5]).fetch()
    except q.Unreachable:
        pass
    n = len([c for c in calls if c == "fetch"])
    t0 = time.monotonic()
    try:
        q.Fleet(sys.argv[5]).fetch()
        print("fetched")
    except q.Unreachable:
        print(n, len([c for c in calls if c == "fetch"]) - n, "fast" if time.monotonic() - t0 < 1 else "slow")
elif case == "lock-wait":
    f = q.Fleet(sys.argv[5])
    t0 = time.monotonic()
    try:
        with f.locked(wait=1):
            print("taken")
    except q.Unreachable as x:
        print("unreachable", "bounded" if time.monotonic() - t0 < 5 else "unbounded")
PY
q3() { python3 "$T/q3.py" "$QB" "$T/launchctl" "$B/dispatch" "$@"; }
qreset

echo "  item 1: a gated flag twice"
CLAUDE_UNATTENDED=dispatch env -u DISPATCH_LABEL python3 "$QB" enqueue --repo "$T/repo" --branch claude/laptop/2026-10-27-twice1 \
  --arg=--mode --arg=default --arg=--mode --arg=yolo "${QC[@]}" > /dev/null 2>"$T/err"
check "$?" "2" "item 1: --mode default --mode yolo is refused: the gate read the first, the run the last…"
has "$T/err" "--mode given twice" "  …saying which flag"
check "$(qtree)" "" "  and nothing is queued"
python3 "$QB" enqueue --repo "$T/repo" --branch claude/laptop/2026-10-27-twice1 --arg=--account --arg=auto --arg=--account --arg=acct-x "${QC[@]}" > /dev/null 2>&1
check "$?" "2" "  --account auto --account LABEL too, from anyone: the entry would be unpinned, the run on one host's login"
python3 "$QB" enqueue --repo "$T/repo" --branch claude/laptop/2026-10-27-twice1 --arg=--priority --arg=force "${QC[@]}" > /dev/null 2>&1
check "$?" "2" "  a carried --priority unlike the entry's: refused (the rank and the run would differ)"
check "$(qload 'q.bad_args({"args": ["--mode", "default", "--mode", "yolo"]})')" "flag --mode given twice" "  an entry written with a flag twice is never claimable (bad_args)"
CLAUDE_UNATTENDED=dispatch env -u DISPATCH_LABEL -u DISPATCH_MODE python3 "$QB" enqueue --repo "$T/repo" --branch claude/laptop/2026-10-27-envmode \
  --arg=--mode --arg=default --env DISPATCH_MODE=yolo "${QC[@]}" > /dev/null 2>&1
check "$?" "2" "  every mode the line names is judged: --mode default beside DISPATCH_MODE=yolo is refused"
qreset

echo "  items 3 and 20: no caller is the fired job by its label"
QL3R=org.example.claude.dispatch.repo.parent.q20261027000000; touch "$T/running.$QL3R"
CLAUDE_UNATTENDED=dispatch DISPATCH_LABEL=$QL3R python3 "$QB" enqueue --repo "$T/repo" --branch claude/laptop/2026-10-27-l3 --priority force "${QC[@]}" > /dev/null 2>&1
check "$?" "2" "item 3: a label launchd reports running (the session's own parent job) still raises nothing: --priority force refused"
CLAUDE_UNATTENDED=dispatch DISPATCH_DEPTH=5 DISPATCH_LABEL=$QL3R python3 "$QB" enqueue --repo "$T/repo" --branch claude/laptop/2026-10-27-l3 --env DISPATCH_DEPTH=1 "${QC[@]}" > /dev/null
check "$("${QGIT[@]}" show refs/regatta/queue:queue/repo--l3.json | python3 -c 'import json, sys; print(json.load(sys.stdin)["env"]["DISPATCH_DEPTH"])')" "6" \
  "item 20: …and the depth is one deeper than the caller's, the label notwithstanding"
rm -f "$T/running.$QL3R"
qreset

echo "  item 2: --cancel of a claimed or waiting entry"
python3 "$QB" enqueue --repo "$T/repo" --branch claude/laptop/2026-10-27-can2 "${QC[@]}" > /dev/null
python3 "$QB" claim "${QC[@]}" > /dev/null; QJ2=$(qget repo--can2 job)
python3 "$QB" waiting fleet:repo--can2 --label "$QJ2" "${QC[@]}" > /dev/null
check "$(qget repo--can2 state)" "waiting" "a claimed entry whose job waits in after()"
HOME="$HB" python3 "$QB" cancel --repo "$T/repo" --branch claude/laptop/2026-10-27-can2 --host buildbox "${QC[@]}" > "$T/out"
has "$T/out" "dispatch claude/laptop/2026-10-27-can2 --cancel there boots its job out" "item 2: --cancel elsewhere names --cancel there, never --end (which ends the run the step waits for)"
: > "$T/calls"
python3 "$QB" cancel --repo "$T/repo" --branch claude/laptop/2026-10-27-can2 "${QC[@]}" > "$T/out"
has "$T/out" "its job $QJ2 booted out before its run started" "  --cancel here takes the entry off and boots its job out"
has "$T/calls" "bootout gui/$(id -u)/$QJ2" "  (launchctl bootout of that job)"
check "$(qtree) $(qplists "$HA" | wc -l | tr -d ' ') $(python3 "$QB" reserved "${QC[@]}")" " 0 0" "  the entry, its plist and its reservation gone"
qreset

echo "  items 4, 7, 15, 19: the slots"
sleep 120 & C4=$!
printf '{"mode":"headless","repo":"%s","topic":"chain4","branch":"claude/laptop/2026-10-27-chain4","pid":%s,"proc_start":"%s","session":"s-c4","started":%s}' \
  "$T/repo" $C4 "$(pst $C4)" "$(date +%s)" > "$RUNS/00000000-000041-repo.chain4.json"
python3 "$QB" enqueue --repo "$T/repo" --branch claude/laptop/2026-10-27-chain4 --pin laptop --by s-c4 --claim "${QC1[@]}" > "$T/out"
has "$T/out" '"claimed": ["fleet:repo--chain4"]' "cap 1: a live run's pinned --next is claimed"
check "$(python3 "$QB" reserved "${QC[@]}")" "0" \
  "fourth review: its reservation is waiting from the claim, before its job's waiting word: never both counted"
python3 "$QB" waiting fleet:repo--chain4 --label "$(qget repo--chain4 job)" "${QC[@]}" > /dev/null
check "$(python3 "$QB" reserved "${QC[@]}")" "0" "item 4: waiting, its reservation holds no slot while the run it waits for holds one…"
kill $C4 2>/dev/null; wait $C4 2>/dev/null
check "$(python3 "$QB" reserved "${QC[@]}")" "1" "  …and holds it once that run ends"
python3 "$QB" enqueue --repo "$T/repo" --branch claude/laptop/2026-10-27-other4 --claim "${QC1[@]}" > "$T/out"
has "$T/out" '"claimed": []' "  so the ended run's claim takes nothing: the slot is the waiter's"
check "$(python3 "$QB" reserved --except fleet:repo--chain4 "${QC[@]}")" "0" "  and the waiter's own cap check finds the slot free"
rm -f "$RUNS"/00000000-00004*
check "$(qload '(lambda m: (setattr(m, "live", lambda a, b, c: [("p%d" % i, {"topic": "t%d" % i, "repo": "/r"}) for i in range(8)]), setattr(m, "parked", lambda st: True), setattr(m, "MAX_PARKED", 6), q.busy("'"$T/launchctl"'") - len(q.held("'"$T/launchctl"'")))[3])(q.rc_mod())')" "2" \
  "fourth review: the claim counts parked runs past DISPATCH_MAX_PARKED, as the fire path's dispatch-rc live does"
check "$(qload '(lambda m: (setattr(m, "parked", lambda st: True), setattr(m, "MAX_PARKED", 6), m.counted([("p%d" % i, {}) for i in range(8)]))[2])(q.rc_mod())')" "2" \
  "  one function, dispatch-rc's counted(), for both"
check "$(qload '(lambda e: (q.apply_op(e, {"op": "refuse", "key": "k", "host": "laptop", "at": 9, "why": "cap"}), sorted(e["k"]["refused_by"]))[1])({"k": {"state": "claimed", "host": "laptop", "running_on": "laptop"}})')" "[]" \
  "item 15: a refusal of an entry pinned to this host skips no hour here: no other host may take it"
check "$(qload '(lambda e: (q.apply_op(e, {"op": "refuse", "key": "k", "host": "laptop", "at": 9, "why": "cap"}), sorted(e["k"]["refused_by"]))[1])({"k": {"state": "claimed", "running_on": "laptop"}})')" "['laptop']" \
  "  an unpinned one is skipped here for the hour, as before"
qreset
python3 "$QB" enqueue --repo "$T/repo" --branch claude/laptop/2026-10-27-t7 "${QC[@]}" > /dev/null
check "$(q3 torn-do)" "0 0" "item 7: a Torn from the claim's own CAS: no claim, and its reservation is given back"
check "$(qget repo--t7 state)" "queued" "  the entry left queued"
sleep 120 & L19=$!
mkdir -p "$HA/Library/Caches/run-seed/start.lock"; echo $L19 > "$HA/Library/Caches/run-seed/start.lock/pid"
check "$(q3 start-lock)" "0 the start lock is held" "item 19: a claim counts under dispatch's start lock: held by a starting run, it claims nothing"
kill $L19 2>/dev/null; wait $L19 2>/dev/null
python3 "$QB" claim "${QC[@]}" > /dev/null
check "$(qget repo--t7 state)" "claimed" "  a dead holder's lock is taken over, as take_lock does"
check "$([ -d "$HA/Library/Caches/run-seed/start.lock" ] && echo held || echo free)" "free" "  and dropped after the claim"
qreset

echo "  items 5, 6, 8, 9, 10: torn, refused, the locale, a crash, a mine that could not tell"
CLAUDE_REPOS_JSON="$T/reg-conf.json" python3 "$QB" enqueue --repo "$T/repo" --branch claude/laptop/2026-10-27-conf5 --claim "${QC[@]}" > /dev/null
CLAUDE_REPOS_JSON="$T/reg-conf.json" python3 "$QB" started local=vault:repo--conf5 --session s5 "${QC[@]}" > /dev/null
blob=$(echo "{not json" | "${QGIT[@]}" hash-object -w --stdin)
"${QGIT[@]}" update-ref refs/regatta/queue "$("${QGIT[@]}" commit-tree "$(printf '040000 tree %s\tqueue\n' "$(printf '100644 blob %s\tx.json\n' "$blob" | "${QGIT[@]}" mktree)" | "${QGIT[@]}" mktree)" -m torn)"
CLAUDE_REPOS_JSON="$T/reg-conf.json" python3 "$QB" has --repo "$T/repo" --branch claude/laptop/2026-10-27-conf5 "${QC[@]}" > /dev/null
check "$?" "3" "item 5: a torn fleet ref: has of a confidential branch still reads its own store (3: its entry)"
CLAUDE_REPOS_JSON="$T/reg-conf.json" python3 "$QB" ended --repo "$T/repo" --branch claude/laptop/2026-10-27-conf5 --session s5 "${QC[@]}" > /dev/null 2>&1
check "$(ls "$HA/Library/Caches/run-seed/queue-local/vault" 2>/dev/null | grep -c conf5)" "0" "  and its run's end removes its node-local entry"
python3 "$QB" has --repo "$T/repo" --branch claude/laptop/2026-10-27-open5 "${QC[@]}" > /dev/null
check "$?" "4" "  an open branch's has, whose store is the torn one: 4"
qreset
printf '#!/bin/sh\nexit 1\n' > "$T/queue.git/hooks/pre-receive"; chmod +x "$T/queue.git/hooks/pre-receive"
python3 "$QB" enqueue --repo "$T/repo" --branch claude/laptop/2026-10-27-ref6 --claim "${QC[@]}" > /dev/null 2>"$T/err"
check "$?" "1" "item 6: a home that serves fetches and refuses this host's push: exit 1, the one-shot's road…"
has "$T/err" "the home refused this host's write" "  …said as a refusal, not as no answer"
check "$(ls "$HA/Library/Caches/run-seed/queue/outbox" 2>/dev/null | wc -l | tr -d ' ')" "0" "  the put is taken back out of the outbox"
env -u DISPATCH_LABEL DISPATCH_MAX_RUNS=5 "$B/dispatch" $BR --repo "$T/repo" --on here --headless > "$T/out" 2>&1
has "$T/out" "the queue could not take it — scheduling it as before, a one-shot" "  through dispatch: the run is scheduled as a one-shot…"
check "$(pl | wc -l | tr -d ' ')" "1" "  …one plist"
grep -qF "no room on this Mac now" "$T/out"; check "$?" "1" "  never 'queued … no room'"
rm -f $(pl); own sess-A
FIRE=" " DISPATCH_MAX_RUNS=0 nx > "$T/out" 2>&1; check "$?" "2" "fourth review: a --next the queue cannot take, on a full host: refused…"
has "$T/out" "and the queue could not take it — refused, not queued" "  …at the cap it skipped for the claim's, with the waiting words"
check "$(pl | wc -l | tr -d ' ')" "0" "  no one-shot the fire time would refuse and lose"
rm -f "$T/queue.git/hooks/pre-receive" $(pl)
check "$(qload 'q._env()["LC_ALL"]')" "C" "item 8: git runs under LC_ALL=C: its words are classed in English"
qreset
check "$(q3 crash 2>/dev/null)" "5" "item 9: a crash in any verb exits 5, never Python's 1 (dispatch's 'the queue refused it')"
python3 "$QB" enqueue --repo "$T/repo" --branch claude/laptop/2026-10-27-cd9 "${QC[@]}" > /dev/null; python3 "$QB" claim "${QC[@]}" > /dev/null
check "$(q3 dead-crash "$T/repo" claude/laptop/2026-10-27-cd9 | tail -1)" "0" "  a crash judging a claim dead reads as 'claimed here', exit 0"
qreset
DISPATCH_QUEUE_NOW=never env -u DISPATCH_LABEL DISPATCH_MAX_RUNS=5 "$B/dispatch" $BR --repo "$T/repo" --on here --headless > "$T/out" 2>&1
check "$?" "2" "  through dispatch, a crashed enqueue is refused, exit 2…"
has "$T/out" "the queue does not read (dispatch-queue exit 5)" "  …saying so"
check "$(pl | wc -l | tr -d ' ')" "0" "  and no one-shot beside a put it cannot see"
qreset
python3 "$QB" enqueue --repo "$T/repo" --branch claude/laptop/2026-10-27-m10 --claim "${QC[@]}" > /dev/null
P10=$(qplists "$HA" | head -1); L10=$(qenv "$P10" DISPATCH_LOG)
echo "$T/no-such.git" > "$REGATTA_CONFIG/wharf-runs/queue-repo"
qfire "$P10" > /dev/null 2>&1
has "$L10" "FAILED: the queue did not say whether fleet:repo--m10 is still this job's claim" "item 10: mine could not read at fire time: not run, said…"
check "$(ls "$HA/Library/Caches/run-seed/queue/outbox" 2>/dev/null | wc -l | tr -d ' ')" "1" "  …and its claim handed back, waiting in the outbox"
echo "$T/queue.git" > "$REGATTA_CONFIG/wharf-runs/queue-repo"
python3 "$QB" claim "${QC[@]}" > /dev/null
check "$(qget repo--m10 state refused_by)" "queued laptop" "  once the home answers, the entry is queued again, never left claimed with no job"
qreset

echo "  items 11, 12, 13, 14, 16, 17, 18: order, bounds, names, the peer, the reason"
check "$(sed -n '/^  echo "== exit \$rc at \$(date)"$/,/^} >> "\$log" 2>&1$/p' "$B/dispatch" | grep -E '^  (queue_ended|yolo_launch|queue_claim)' | tr -d ' ' | tr '\n' ' ')" \
  'queue_ended yolo_launch"$rc" queue_claim ' "item 11: a run's end writes its word, then hands its landing on, then claims"
grep -q '\[ "\$arc" = 0 \] && launched=1' "$B/dispatch"; check "$?" "0" "  and a landing started leaves the slot to it (queue_claim skips)"
sed -n '/^  if \[ "\$start" = 1 \]; then$/,/^  fi$/p' "$B/dispatch" | grep -q queue_claim
check "$?" "0" "item 17: a --start's end claims too: a slot it held had no end that claimed"
python3 "$QB" enqueue --repo "$T/repo" --branch claude/laptop/2026-10-27-lk12 "${QC[@]}" > /dev/null
python3 -c 'import fcntl, sys, time; f = open(sys.argv[1], "w"); fcntl.flock(f, fcntl.LOCK_EX); time.sleep(8)' "$HA/Library/Caches/run-seed/queue/clone.lock" & LK=$!
sleep 1
check "$(q3 lock-wait "$T/queue.git")" "unreachable bounded" "item 12: the clone's lock is waited for a bound, then reads as offline"
kill $LK 2>/dev/null; wait $LK 2>/dev/null
check "$(q3 down-memo "$T/no-such.git")" "1 0 fast" "item 13: a home that did not answer is not fetched again in the same process"
check "$(qload 'q.Local("acme corp").name')" "local=acme_corp" "item 14: a scope's queue has one name, its folder's"
echo "laptop:laptop" > "$REGATTA_CONFIG/wharf-runs/finish-on"; echo "laptop:buildbox" > "$REGATTA_CONFIG/wharf-runs/orca-pairs"
check "$(qload 'q.landing_peer("laptop")')" "False" "item 16: the landing peer is autofinish-run's peer_of(): its first line names this host, so none"
rm -f "$REGATTA_CONFIG/wharf-runs/finish-on" "$REGATTA_CONFIG/wharf-runs/orca-pairs"
python3 "$QB" enqueue --repo "$T/repo" --branch claude/laptop/2026-10-27-nr17 --claim --cap 0 --launchctl "$T/launchctl" --prefix org.example.claude --jobbin "$B/dispatch" > "$T/out"
has "$T/out" '"no_room": "the run cap (0 of 0 busy on laptop)"' "item 17: an enqueue left queued says why (the cap, or memory)"
qreset
check "$(q3 headroom)" "0" "item 18: an empty queue samples no memory"
qreset

echo "  items 21 and 22: --on here pins; a run the queue did not start asks it"
env -u DISPATCH_LABEL DISPATCH_MAX_RUNS=0 "$B/dispatch" $BR --repo "$T/repo" --on here --headless > "$T/out" 2>&1
check "$(qget repo--demo state host)" "queued laptop" "item 21: a typed --on here is pinned here: no other host's claim takes it"
qreset
env -u DISPATCH_LABEL "$B/dispatch" $BR --repo "$T/repo" --at "$FUT 04:10" > /dev/null 2>&1; P22=$(pl); PL22=$(basename "$P22" .plist)
HOME="$HB" python3 "$QB" enqueue --repo "$T/repo" --branch $BR --host buildbox "${QC[@]}" > /dev/null
HOME="$HB" python3 "$QB" claim --host buildbox "${QC[@]}" > /dev/null
HOME="$HB" python3 "$QB" started fleet:repo--demo --session s22 --host buildbox "${QC[@]}" > /dev/null
: > "$T/claude.calls"
DISPATCH_LOG="$HA/q22.log" DISPATCH_LABEL=$PL22 "$B/dispatch" $BR --repo "$T/repo" --headless
has "$HA/q22.log" "FAILED: $BR is live on another host through the queue" "item 22: a one-shot fired while its branch runs on another host through the queue: refused"
check "$(wc -c < "$T/claude.calls" | tr -d ' ')" "0" "  no session"
rm -f "$P22"
qreset

rm -f "$REGATTA_CONFIG/wharf-runs/queue-repo"
unset DISPATCH_HOST

[ "$fails" = 0 ] && echo "all ok" || { echo "$fails FAILED"; exit 1; }
