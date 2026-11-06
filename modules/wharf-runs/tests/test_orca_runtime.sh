#!/usr/bin/env bash
# Tests for the Orca adapter's road to Orca per OS, run where a node's yard runs (bin/harness_adapters/orca.py's
# _bin, _app_up and not_running_hint; docs/yard-orca-serve-2026-11-05.md). On a Mac the app's process by pgrep;
# on Linux a process table read for `orca-ide` (the app, or its headless `serve`) and the CLI `orca-ide` alone.
# Each road through the adapter (its refusals' whole words: harness run's through run(), wharf apply's through
# not_running_hint("apply"), which apply prints), then through bin/wharf's own gate (`status --orphans`, whose
# `_app_up()` the apply's gate shares). test_harness.sh holds the argv shapes (the app, the server, a CLI call in flight, the
# launcher's bash step, GNOME's orca) and runs on a Mac only; this suite runs on Linux too. Stand-ins for pgrep,
# orca, orca-ide and /proc (HARNESS_ORCA_PROC); HARNESS_ORCA_PLATFORM stands in for sys.platform. Scratch HOME
# and config dir; no Orca, no network.
#   bash modules/wharf-runs/tests/test_orca_runtime.sh
set -u
unset HARNESS_ORCA HARNESS_ORCA_PLATFORM HARNESS_ORCA_PROC CLAUDE_UNATTENDED REGATTA_UNATTENDED CLAUDE_CODE_SESSION_ID
unset $(compgen -v | grep '^DISPATCH_')   # every DISPATCH_* a run carries (AGENTS.md: a fixed list goes stale)
B="$(cd "$(dirname "$0")/../bin" && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
. "$(cd "$(dirname "$0")" && pwd)/config_fixture.sh"; fixture_config "$T/config"
fails=0
check() { if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3: expected [$2] got [$1]"; fails=$((fails+1)); fi; }
has() { case "$1" in *"$2"*) echo "  ok   $3";; *) echo "  FAIL $3: [$2] not in [${1:0:300}]"; fails=$((fails+1));; esac; }
export PYTHONUSERBASE="${PYTHONUSERBASE:-$(python3 -m site --user-base)}"
export PYTHONDONTWRITEBYTECODE=1   # no __pycache__ beside the modules it loads, nor a child's (orca-host.sh's reason)
PY=$(command -v python3)
export HOME="$T/home"; mkdir -p "$HOME"

# The stand-ins log their argv and whether ELECTRON_RUN_AS_NODE reached them to $STUB_CALLS. orca-ide (and
# orca, the Mac's name for it: a copy) answers wharf's orphans reads with empty lists. pgrep exits
# $STUB_PGREP_RC.
S="$T/stubs"; mkdir -p "$S"
cat > "$S/orca-ide" <<'SH'
#!/bin/sh
printf '%s %s ERAN=%s\n' "$(basename "$0")" "$*" "${ELECTRON_RUN_AS_NODE-unset}" >> "$STUB_CALLS"
case "$1" in
  orchestration) printf '%s\n' '{"ok": true, "result": {"runs": []}}' ;;
  repo) printf '%s\n' '{"ok": true, "result": {"repos": []}}' ;;
  *) printf '%s\n' '{"ok": false, "error": {"code": "unknown", "message": "stub"}}'; exit 1 ;;
esac
SH
cat > "$S/pgrep" <<'SH'
#!/bin/sh
printf 'pgrep %s\n' "$*" >> "$STUB_CALLS"
exit "${STUB_PGREP_RC:-1}"
SH
cp "$S/orca-ide" "$S/orca"
chmod +x "$S"/*
export STUB_CALLS="$T/calls"
# procs <dir> <argv>…: a process table of the case's own, one pid per argument (its words split on spaces),
# plus a non-pid entry the reader skips
procs() {
  local root=$1 n=100 line; shift
  mkdir -p "$root/self"
  for line in "$@"; do
    mkdir -p "$root/$n"; printf '%s' "$line" | tr ' ' '\0' > "$root/$n/cmdline"; printf '\0' >> "$root/$n/cmdline"; n=$((n+1))
  done
}
SRV="/opt/Orca/orca-ide /opt/Orca/resources/app.asar.unpacked/out/cli/index.js"
UP="$T/proc-up"; procs "$UP" "/sbin/init" "$SRV serve --pairing-address 192.0.2.7"
DOWN="$T/proc-down"; procs "$DOWN" "/sbin/init" "/bin/bash /opt/Orca/resources/bin/orca-ide serve" "$SRV status --json"
# ask <platform> <PATH> <proc> <expr>: the adapter loaded fresh, EXPR printed (ELECTRON_RUN_AS_NODE set, as
# a session in VS Code has it)
ask() {
  : > "$STUB_CALLS"
  env HARNESS_ORCA_PLATFORM="$1" PATH="$2" HARNESS_ORCA_PROC="$3" ELECTRON_RUN_AS_NODE=1 "$PY" -c '
import importlib.util, sys
s = importlib.util.spec_from_file_location("orca_adapter_case", sys.argv[1])
m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
print(eval(sys.argv[2]))' "$B/harness_adapters/orca.py" "$4" 2>&1
}
calls() { tr '\n' ';' < "$STUB_CALLS"; }
# runfail <platform> <PATH> <proc>: what the adapter's run() (harness run) refuses with, through a ctx whose
# fail() prints the message (a file of its own: no heredoc inside a substitution, AGENTS.md's bash 3.2 traps)
cat > "$T/runfail.py" <<'PY'
import importlib.util, sys
s = importlib.util.spec_from_file_location("orca_adapter_run", sys.argv[1])
m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
class Ctx:
    machine = "testhost"
    def fail(self, msg, code=1):
        print("%s (exit %d)" % (msg, code)); sys.exit(0)
m.run(Ctx(), {"name": "probe", "prompt": "p", "repo": "/nowhere", "agent": "claude"})
print("no refusal")
PY
runfail() { : > "$STUB_CALLS"; env HARNESS_ORCA_PLATFORM="$1" PATH="$2" HARNESS_ORCA_PROC="$3" "$PY" "$T/runfail.py" "$B/harness_adapters/orca.py" 2>&1; }
LINUX_HINT='no orca-ide app or `orca-ide serve` process: start the server (`systemctl --user start orca-serve`); installing it is the owner'"'"'s, from their own terminal (`modules/wharf-runs/bin/orca-serve-agent here`)'
LINUX_HINT_ON='no orca-ide app or `orca-ide serve` process on node1: start the server (`systemctl --user start orca-serve`); installing it is the owner'"'"'s, from their own terminal on node1 (`modules/wharf-runs/bin/orca-serve-agent here`)'
LINUX_HINT_TESTHOST='no orca-ide app or `orca-ide serve` process on testhost: start the server (`systemctl --user start orca-serve`); installing it is the owner'"'"'s, from their own terminal on testhost (`modules/wharf-runs/bin/orca-serve-agent here`)'
MAC_RUN='open the app, with ELECTRON_RUN_AS_NODE cleared from a VS Code session'
P="$S:/usr/bin:/bin"
E="$T/empty"; mkdir -p "$E"

echo "== Linux: orca-ide, and the server's process"
check "$(ask linux "$P" "$UP" 'm._bin()')" "$S/orca-ide" "the CLI is orca-ide, never a bare orca beside it (the screen reader, serve's shim)"
check "$(ask linux "$P" "$UP" 'm._app_up()')" "True" "orca-ide serve in the process table: up"
check "$(calls)" "" "  read from the table alone: no pgrep, no CLI call"
check "$(ask linux "$P" "$DOWN" 'm._app_up()')" "False" "only the launcher's bash step and a CLI call in flight: not up"
check "$(ask linux "$P" "$T/no-proc" 'm._app_up()')" "False" "a process table that will not list: not up"
check "$(ask linux "$E" "$UP" 'm._bin()')" "None" "no orca-ide on PATH: no CLI"
has "$(ask linux "$E" "$UP" 'm._call(None, ["repo", "list"])[1]')" "no orca CLI (HARNESS_ORCA, orca-ide on PATH)" "  the error names orca-ide"
check "$(ask linux "$P" "$DOWN" 'm.not_running_hint()')" "$LINUX_HINT" "the refusal names the headless server: its unit, and its installer"
check "$(ask linux "$P" "$DOWN" 'm.not_running_hint("apply")')" "$LINUX_HINT" "  the same words for wharf apply"
check "$(ask linux "$P" "$DOWN" 'm.not_running_hint("apply", "node1")')" "$LINUX_HINT_ON" "  named for its host, as helm send streams it to the sending Mac"
check "$(runfail linux "$P" "$DOWN")" "Orca is not running here ($LINUX_HINT_TESTHOST) (exit 2)" "harness run, no server: refused with them, its host named"
check "$(runfail linux "$E" "$UP")" "no orca CLI here (HARNESS_ORCA, orca-ide on PATH) (exit 2)" "harness run, a server up and no orca-ide on PATH: the CLI is what is missing"

echo "== a Mac: the app's process, by pgrep"
export STUB_PGREP_RC=0
check "$(ask darwin "$P" "$DOWN" 'm._app_up()')" "True" "the app's process found: up"
has "$(calls)" "pgrep -f ^[^ ]*/Orca\.app/Contents/MacOS/Orca( |$);" "  by pgrep, main's anchored pattern"
export STUB_PGREP_RC=1
check "$(ask darwin "$P" "$UP" 'm._app_up()')" "False" "no app process: not up, whatever a process table holds"
check "$(ask darwin "$P" "$UP" 'm._bin()')" "$S/orca" "the CLI is orca on PATH"
check "$(ask darwin "$P" "$UP" 'm.not_running_hint()')" "$MAC_RUN" "harness run's Mac words, as before"
check "$(ask darwin "$P" "$UP" 'm.not_running_hint("apply")')" "open the app; a session in VS Code clears ELECTRON_RUN_AS_NODE" "wharf apply's Mac words, as before"
check "$(ask darwin "$P" "$UP" 'm.not_running_hint("apply", "node1")')" "open the app; a session in VS Code clears ELECTRON_RUN_AS_NODE" "  a host given changes no Mac word"
check "$(runfail darwin "$P" "$UP")" "Orca is not running here ($MAC_RUN) (exit 2)" "harness run with no app: refused in the Mac's words"
check "$(runfail darwin "$E" "$UP")" "Orca is not running here ($MAC_RUN) (exit 2)" "  and with no CLI either, as before"
unset STUB_PGREP_RC

echo "== a stub (HARNESS_ORCA) stands in for the app on both"
for plat in linux darwin; do
  check "$(HARNESS_ORCA="$S/orca" ask $plat "$P" "$DOWN" '(m._app_up(), m._bin())')" "(True, '$S/orca')" "$plat: up, and the stub is the CLI"
  check "$(calls)" "" "  $plat: no pgrep"
done

echo "== bin/wharf's gate on each road (status --orphans: the read the apply's gate shares)"
export PLANS_DIR="$T/plans" PLAN_HOST=testhost PLAN_NO_RENDER=1; mkdir -p "$PLANS_DIR"
export CLAUDE_REPOS_JSON="$T/repos.json"; echo '{"repos": {}}' > "$CLAUDE_REPOS_JSON"
wh() { : > "$STUB_CALLS"; env HARNESS_ORCA_PLATFORM="$1" HARNESS_ORCA_PROC="$2" PATH="$P" ELECTRON_RUN_AS_NODE=1 "$PY" "$B/wharf" status --orphans --json 2>&1; }   # $PY: PYTHONUSERBASE's own
out=$(wh linux "$UP"); rc=$?
check "$rc" "0" "Linux, orca-ide serve running: the gate passes"
check "$out" '{"repos": [], "runs": []}' "  and Orca's lists are read"
has "$(calls)" "orca-ide orchestration run-list --limit 100 --json ERAN=unset" "  through orca-ide, ELECTRON_RUN_AS_NODE dropped"
out=$(wh linux "$DOWN"); rc=$?
check "$rc" "3" "Linux, no server: refused"
has "$out" "Orca is not running here" "  with the gate's words"
check "$(calls)" "" "  and no CLI call"
export STUB_PGREP_RC=1
out=$(wh darwin "$UP"); rc=$?
check "$rc" "3" "a Mac with no app process: refused"
export STUB_PGREP_RC=0
out=$(wh darwin "$DOWN"); rc=$?
check "$rc" "0" "a Mac with the app: the gate passes"
has "$(calls)" "orca orchestration run-list" "  through orca"
unset STUB_PGREP_RC

[ "$fails" = 0 ] && echo "  all passed" || echo "  $fails failed"
[ "$fails" = 0 ]
