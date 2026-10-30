#!/usr/bin/env bash
# helm with no peer: a scratch checkout of the core and this module alone (no keel, plumb, wharf,
# wharf-runs; a legacy checkout that holds none of them), so each optional edge takes the fallback
# its README names, never a traceback (the design's C2, G26 and the edges B12 put behind tool()).
# And the shapes that do not depend on a peer: surfaces.schema.json against surfaces.KNOWN.
#   bash modules/helm/tests/peers.sh
set -u
H="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$(cd "$H/../.." && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fails=0
check() { if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3: expected [$2] got [$1]"; fails=$((fails+1)); fi; }
has() { case "$1" in *"$2"*) echo "  ok   $3";; *) echo "  FAIL $3: [$2] not in [${1:0:300}]"; fails=$((fails+1));; esac; }

for v in $(env | sed -n 's/^\(REGATTA[A-Za-z0-9_]*\)=.*/\1/p; s/^\(DISPATCH[A-Za-z0-9_]*\)=.*/\1/p'); do unset "$v"; done
unset CLAUDE_UNATTENDED REGATTA_UNATTENDED SURFACES_FILE ACCOUNTS_FILE PLANS_DIR
S="$T/tree"; mkdir -p "$S/.claude-plugin" "$S/modules" "$T/overlay/bin" "$T/home" "$T/config/regatta"
cp "$ROOT/.claude-plugin/marketplace.json" "$S/.claude-plugin/"
cp -R "$ROOT/modules/regatta" "$H" "$S/modules/"
# the config dir names an empty overlay checkout (since B14b tool() never looks there anyway)
printf '%s\n' "$T/overlay" > "$T/config/regatta/overlay"
export HOME="$T/home" REGATTA_CONFIG="$T/config" PLANS_DIR="$T/plans" PLAN_CACHE_DIR="$T/cache" PLAN_HOST=testhost \
       ASK_CACHE_DIR="$T/askcache" ATTENTION_LOG_DIR="$T/attention" PLAN_NO_DEPLOY=1 PLAN_NO_MEMO=1 PLAN_NO_GH=1
SB="$S/modules/helm/bin"
py() { python3 -c "import sys; sys.path.insert(0, '$SB'); $1" 2>&1; }

echo "no peers: each edge says what it skips"
# the keys the core needs once the overlay's marker exists (B2b, common.OVERLAY_KEYS) — without one the core
# refuses to load, and every peer would read as absent for that reason alone — and the laptop
mkdir -p "$T/config/regatta"; echo Owner > "$T/config/regatta/owner"; echo laptop > "$T/config/regatta/laptop"
echo transcripts > "$T/config/regatta/guarded"; : > "$T/config/regatta/orca-deny"
echo "$T/logs" > "$T/config/regatta/log-dir"; echo "$T/projects" > "$T/config/regatta/projects"
check "$(py 'import helmlib; print(helmlib._common().OWNER_NAME)')" "Owner" "the core loads from this config (so a None below is a peer's absence)"
check "$(py 'import helmlib; print(helmlib.peer("keel"), helmlib.peer("dispatch-rc"), helmlib.harness_adapter("claude_code.py"))')" \
      "None None None" "peer() and harness_adapter(): None for keel, dispatch-rc and the adapter"
check "$(py 'import helmlib; print(helmlib._sheep_gate, helmlib.GUARDED)')" \
      "None ('transcripts',)" "no keel: the guarded list is the core's (regatta/guarded)"
mkdir -p "$T/home/.claude/projects/p"; printf '{"type":"assistant","message":{"model":"m","usage":{"output_tokens":5}}}\n' > "$T/home/.claude/projects/p/s1.jsonl"
check "$(py 'import helmlib; print(helmlib.session_cost("s1"))')" "None" "G26: no usage-report (plumb) — no cost, no crash"
check "$(py 'import helm_render; print(helm_render.week_line())')" "None" "G26: no tier_check (plumb) — no week line"
check "$(py 'import asklib; print(asklib.log_relay("answered", "d", session="s", cwd="/x")); import glob; print(len(glob.glob("'"$T"'/attention/*.jsonl")))')" \
      "True
1" "G26: no attention (plumb) — the relay row is written by hand, to the same file"
check "$(py 'import stalls; j = stalls.judge(peer=False, live_call=False); print(j["stalls"], j["notes"])')" \
      "[] ['stalls: wharf-runs not installed (dispatch-rc, its harness adapter) — no runs to judge']" "no wharf-runs: stalls judges nothing, and says so"
"$S/modules/helm/libexec/helm" ship demo --id d1 --repo /x/demo > /dev/null 2>&1; check "$?" "0" "helm ship with no peer"
check "$(cd "$T" && "$S/modules/helm/libexec/helm" render d1 2>&1 | grep -c 'local:')" "1" "helm render with no peer: the local page"
check "$(py 'import importlib.machinery as m; h = m.SourceFileLoader("h", "'"$S"'/modules/helm/libexec/helm").load_module(); print(h.keel("list")[2]); print(h.wharf_once(True))')" \
      "keel not installed (the keel module): no doc read
['wharf: skipped — not installed (wharf-runs)']" "helm's keel() and wharf pass: one line each"
printf '%s\n' '{"repos": {}, "scopes": {"s": {"repos": [], "yard": "testhost"}}}' > "$T/yard.json"
mkdir -p "$T/cfg-plain"   # a stranger's install: no overlay (`legacy`), so the core's private values keep their defaults
# launchd's tick (no session, not unattended): a caller's session id would answer before the absent peer
check "$(unset CLAUDE_CODE_SESSION_ID CLAUDE_UNATTENDED REGATTA_UNATTENDED; REGATTA_CONFIG="$T/cfg-plain" CLAUDE_REPOS_JSON="$T/yard.json" py 'import helmlib, stalls_tick; print(helmlib.brake_refusal()); print(stalls_tick.deadman_ping(brake="x")); print(stalls_tick.ensure_skippers("armed", "x"))')" \
      "None
['deadman: not pinged — not installed (lighthouse)']
[]" "S11 without wharf-runs or lighthouse: no brake read, the yard's ping is one quiet line, the held skippers pass says nothing"
check "$(REGATTA_CONFIG="$T/cfg-plain" CLAUDE_REPOS_JSON="$T/none.json" py 'import stalls_tick; print(stalls_tick.deadman_ping())')" "[]" "S11: a host that is no yard pings nothing, with or without lighthouse"
out=$("$S/modules/helm/libexec/helm" task d1 t1 --done-when pr_merged 2>&1); check "$?" "1" "--done-when without blueprintlib (wharf-runs): refused …"
has "$out" "blueprintlib.py (wharf-runs), which is not installed" "  … in one line"
git init -q "$T/repo"; printf '# Doc\n\n**D1 — x?** Reversible: yes\n➤ Recommended: A\n➤ Answer:\n' > "$T/repo/doc.md"
out=$(cd "$T/repo" && "$SB/ask" relay doc.md D1 2>&1); has "$out" "keel is not installed" "ask relay without keel: one line"
out=$(SURFACES_HOST=buildbox python3 -c "
import sys, argparse; sys.argv = ['ask']; sys.path.insert(0, '$SB')
from importlib.machinery import SourceFileLoader as L
m = L('ask', '$SB/ask').load_module()
import time; f, r = m.poll_jobs(argparse.Namespace(dry_run=False, repos=None)); m.run_jobs(f + r, time.time() + 600)" 2>&1)
check "$out" "ask poll: hail not installed — the subscriptions' fulfil skipped
ask poll: keel not installed — the lookout skipped" "ask poll without keel or hail (crosstalk S6): one line each, no traceback"
out=$(printf '{"session_id": "abcd1234", "hook_event_name": "SessionStart", "cwd": "%s"}' "$T" | CLAUDE_TALK_HOSTS=testhost python3 "$S/modules/helm/hooks/talk_nudge.py" 2>&1; echo "rc=$?")
check "$out" "rc=0" "talk_nudge without keel's gate: silent, exit 0"
out=$(printf '{"tool_name": "AskUserQuestion", "hook_event_name": "PreToolUse"}' | CLAUDE_UNATTENDED=1 python3 "$S/modules/helm/hooks/ask_guard.py" pretool)
has "$out" '"permissionDecision": "deny"' "ask_guard denies an unattended AskUserQuestion with no peer"
has "$out" "$S/modules/helm/bin/ask relay" "  … naming this module's bin/ask"
out=$(python3 - "$SB" <<'PY' 2>&1
import sys; sys.path.insert(0, sys.argv[1]); import skipperlib
for f, a in ((skipperlib.pick, ("/x",)), (skipperlib.ensure_trusted, ("/x", {}))):
    try:
        f(*a)
    except skipperlib.Refused as e:
        print(e)
print(skipperlib.ensure(True))
PY
)
check "$out" "no login (lighthouse's account is not installed)
no trust check (wharf-runs' dispatch-rc is not installed)
[]" "S5's skipper without lighthouse or wharf-runs: a refusal naming each, no traceback; no lease, no line"

printf -- '---\nship: x\n---\n' > "$T/bp.md"
out=$("$S/modules/helm/libexec/helm" send "$T/bp.md" 2>&1); check "$?" "2" "S7's helm send without wharf-runs: refused, exit 2 …"
check "$out" "helm send: refused: wharf-runs' blueprintlib.py is not here: a blueprint cannot be read (install wharf-runs)" "  … in one line"
out=$("$S/modules/helm/libexec/helm" send --text "a task" --repo "$T/repo" 2>&1); check "$?" "2" "  --text too"
check "$out" "helm send: refused: wharf-runs' blueprintlib.py is not here: a blueprint cannot be read (install wharf-runs)" "    the same line"

echo "the core gone: the libraries raise or step aside, the CLIs say one line"
N="$T/nocore"; mkdir -p "$N"; cp -R "$H" "$N/"; rm -f "$T/config/regatta/overlay"
check "$(python3 -c "import sys; sys.path.insert(0, '$N/helm/bin'); import asklib; print(asklib._common(), asklib._peer('sheep'))" 2>/dev/null)" \
      "None None" "asklib without a core: None, never an exit (keel's Stop lint loads it)"
check "$(python3 -c "import sys; sys.path.insert(0, '$N/helm/bin'); import helmlib; print(helmlib.peer('keel'), helmlib.GUARDED)" 2>/dev/null)" \
      "None ()" "helmlib without a core: imports, no list to guard by"
out=$(python3 "$N/helm/bin/stalls_tick.py" --status 2>&1); has "$out" "the regatta core is missing" "stalls_tick without a core: the line that names it"

echo "install.sh: the ask poll's plist, never the real launchd"
# the main checkout when this is a linked worktree of one that holds helm, else this checkout
MAIN=$(dirname "$(git -C "$ROOT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)")
[ -d "$MAIN/modules/helm" ] || MAIN=$ROOT
printf '#!/bin/sh\necho "$@" >> "%s/lc.log"\n' "$T" > "$T/lc"; chmod +x "$T/lc"
out=$(HELM_LAUNCH_DIR="$T/la" HELM_LAUNCHCTL="$T/lc" HELM_LABEL=test.ask-poll HELM_LOG="$T/poll.log" sh "$H/install.sh" --schedule)
has "$out" "scheduled test.ask-poll" "--schedule writes and loads the job"
check "$(python3 -c "import plistlib,sys; d=plistlib.load(open('$T/la/test.ask-poll.plist','rb')); print(d['ProgramArguments'][1:], d['StartInterval'], d['RunAtLoad'], d['StandardOutPath'] == '$T/poll.log')")" \
      "['$MAIN/modules/helm/bin/ask', 'poll'] 300 True True" "  the module's bin/ask poll every 5 min, from the main checkout, the log it is given"
has "$(cat "$T/lc.log")" "bootstrap gui/$(id -u) $T/la/test.ask-poll.plist" "  loaded through the launchctl it is given"
check "$(HELM_LABEL=test.ask-poll HELM_LOG="$T/poll.log" sh "$H/install.sh" --plist | python3 -c "import plistlib,sys; print(plistlib.loads(sys.stdin.buffer.read())['Label'])")" "test.ask-poll" "--plist prints the same plist"
HELM_LAUNCH_DIR="$T/la" HELM_LAUNCHCTL="$T/lc" HELM_LABEL=test.ask-poll sh "$H/install.sh" --remove > /dev/null
check "$([ -f "$T/la/test.ask-poll.plist" ] && echo kept || echo gone)" "gone" "--remove unloads and deletes it"

echo "surfaces.json's schema"
check "$(python3 - "$H" <<'PY'
import json, sys
sys.path.insert(0, sys.argv[1] + "/bin")
import surfaces
sc = json.load(open(surfaces.SCHEMA))["properties"]
def enum(seam, key):
    v = sc[seam]["properties"][key] if key != "*" else sc[seam]["additionalProperties"]
    v = v.get("items", v)
    return set(v["enum"])
print(all(enum(n.split(".")[0], n.split(".")[1]) == ok for n, ok in surfaces.KNOWN.items()))
print(sorted(set(sc) - {"_", "plan"}) == sorted(surfaces.DEFAULTS))
PY
)" "True
True" "every enum is surfaces.KNOWN's, every seam a DEFAULTS row"
check "$(python3 -c "import sys, json; sys.path.insert(0, '$H/bin'); import surfaces; print(surfaces.validate(json.load(open('$H/tests/surfaces.json'))))")" "[]" "the fixture is valid"
check "$(REGATTA_CONFIG=/cfg python3 -c "import sys; sys.path.insert(0, '$H/bin'); import surfaces; print(surfaces.FILE)")" "/cfg/helm/surfaces.json" "the default is the config dir's helm/surfaces.json (C3)"

echo; [ $fails -eq 0 ] && echo "peers: all passed" || { echo "peers: $fails FAILED"; exit 1; }
