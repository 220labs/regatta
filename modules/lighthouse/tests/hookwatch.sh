#!/usr/bin/env bash
# Tests for bin/hookwatch (autofinish-exclude S3, S4): scratch repos (a bare origin and a primary
# checkout), scratch login dirs holding fixture transcripts, a scratch config dir, a stub gh. No real
# checkout is pinned and no launchd job is loaded: `install` runs --dry-run only, and refused.
#   bash modules/lighthouse/tests/hookwatch.sh
set -u
unset CLAUDE_CONFIG_DIR CLAUDE_UNATTENDED REGATTA_UNATTENDED HOOKWATCH_POST HOOKWATCH_ROOT HOOKWATCH_LOGINS HOOKWATCH_STATE
B="$(cd "$(dirname "$0")/../bin" && pwd)"
M="$(cd "$(dirname "$0")/../.." && pwd)"   # modules/
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
T=$(cd "$T" && pwd -P)
export HOME="$T/h" REGATTA_CONFIG="$T/config"; mkdir -p "$HOME" "$REGATTA_CONFIG"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_CONFIG_GLOBAL=/dev/null
N=$(date +%s); export HOOKWATCH_NOW=$N HOOKWATCH_HOST=test HOOKWATCH_GH="python3 $T/gh.py"
fails=0
check() { if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3: expected [$2] got [$1]"; fails=$((fails+1)); fi; }
has() { if grep -qF -- "$2" "$1"; then echo "  ok   $3"; else echo "  FAIL $3: no [$2] in $(head -c 600 "$1")"; fails=$((fails+1)); fi; }
# BSD date -r <epoch>; GNU date -d @<epoch> (its -r takes a file). Each fails cleanly on the other.
dateat() { date -r "$1" "$2" 2>/dev/null || date -d "@$1" "$2"; }
cat > "$T/gh.py" <<'EOF'
import json, os, sys
open(os.environ["GH_LOG"], "a").write(json.dumps(sys.argv[1:]) + "\n")
print("https://github.invalid/o/r/pull/9")
EOF
export GH_LOG="$T/gh.log"

# world <name> [files c2 changes]: origin + primary R at c2 (the bad landing, 10 min ago), c1 its parent
# (2 h ago, clean); the state knows c1 as head and clean, so this pass sees the move (the reflog's time)
# and probes c2. c1 holds two hooks — h.py and g.py, which imports lib/helper.py — and a stub of
# hookwatch itself (a clean sha must carry it); NOSELF=1 leaves the stub out. c2 changes h.py by default.
world() {
  W="$T/$1"; R="$W/primary"; mkdir -p "$W"
  git init -q --bare -b main "$W/origin.git"
  git init -q -b main "$R"; mkdir -p "$R/modules/x/hooks" "$R/modules/x/lib" "$R/modules/lighthouse/bin"
  echo "print('v1')" > "$R/modules/x/hooks/h.py"; printf 'import helper\nhelper.go()\n' > "$R/modules/x/hooks/g.py"
  echo "def go(): pass" > "$R/modules/x/lib/helper.py"
  [ "${NOSELF:-}" = 1 ] || echo "# stub" > "$R/modules/lighthouse/bin/hookwatch"
  git -C "$R" add -A
  GIT_COMMITTER_DATE="@$((N - 7200))" git -C "$R" commit -qm c1
  git -C "$R" remote add origin "$W/origin.git"; git -C "$R" push -q origin main
  for f in ${2:-modules/x/hooks/h.py}; do mkdir -p "$R/$(dirname "$f")"; echo "# v2" >> "$R/$f"; done
  git -C "$R" add -A; GIT_COMMITTER_DATE="@$((N - 600))" git -C "$R" commit -qm c2
  git -C "$R" push -q origin main; git -C "$R" fetch -q origin
  C1=$(git -C "$R" rev-parse HEAD~1); C2=$(git -C "$R" rev-parse HEAD)
  export HOOKWATCH_ROOT="$R" HOOKWATCH_LOGINS="$W/login" HOOKWATCH_STATE="$W/state.json"
  mkdir -p "$W/login/projects/p"
  printf '{"head": "%s", "clean": "%s", "moved_at": %s}\n' "$C1" "$C1" $((N - 7200)) > "$W/state.json"
}
# push3 <file>: a third commit on origin from another clone, changing <file>; C3 its sha
push3() {
  O2="$W/other"; rm -rf "$O2"; git clone -q "$W/origin.git" "$O2"; mkdir -p "$O2/$(dirname "$1")"; echo "# v3" >> "$O2/$1"
  git -C "$O2" add -A; git -C "$O2" commit -qm c3; git -C "$O2" push -q origin main; C3=$(git -C "$O2" rev-parse HEAD)
}
# rec <session> <type> <event> <command> <seconds ago> <field> <text> [timedOut]: one hook attachment
rec() {
  python3 - "$W/login/projects/p/$1.jsonl" "$@" <<'EOF'
import datetime, json, os, sys
f, sid, typ, event, cmd, ago, field, text = sys.argv[1:9]
a = {"type": typ, "hookEvent": event, "hookName": event, "command": cmd}
if field == "blockingError":
    a["blockingError"] = {"blockingError": text, "command": cmd}
else:
    a[field] = text
if len(sys.argv) > 9:
    a["timedOut"] = True
ts = datetime.datetime.fromtimestamp(int(os.environ["HOOKWATCH_NOW"]) - int(ago), datetime.timezone.utc)
open(f, "a").write(json.dumps({"type": "attachment", "attachment": a, "sessionId": sid,
                               "timestamp": ts.isoformat().replace("+00:00", "Z")}) + "\n")
EOF
}
hw() { python3 "$B/hookwatch" "$@"; }
HOOK() { echo "python3 \"$R/modules/x/hooks/h.py\""; }
GHOOK() { echo "python3 $R/modules/x/hooks/g.py"; }
TB() { printf 'Traceback (most recent call last):\n  File "%s/modules/x/hooks/%s", line 1, in <module>\nNameError: name %s is not defined\n' "$R" "${1:-h.py}" "'x'"; }

echo "the thresholds (S3), each --dry-run in a world of its own"
world quiet; rec s1 hook_success PreToolUse "$(HOOK)" 60 stdout ok
hw scan --dry-run > "$T/o" 2>&1
check "$(cat "$T/o")" "" "no fault: a quiet pass says nothing"
world crash; rec s1 hook_non_blocking_error SessionStart "$(HOOK)" 120 stderr "$(TB)"
hw scan --dry-run > "$T/o" 2>&1
has "$T/o" "would pin primary at ${C1:0:12} (crash: h.py (NameError: name 'x' is not defined))" "crash: a traceback through the checkout's modules/"
world crash-old; rec s1 hook_non_blocking_error SessionStart "$(HOOK)" 900 stderr "$(TB)"
hw scan --dry-run > "$T/o" 2>&1
check "$(cat "$T/o")" "" "  a crash from before HEAD moved is the old code's: no fault"
world crash-else; rec s1 hook_non_blocking_error SessionStart "python3 /elsewhere/h.py" 120 stderr "$(R=/elsewhere TB)"
hw scan --dry-run > "$T/o" 2>&1
check "$(cat "$T/o")" "" "  a hook that does not run from the checkout: no fault"
world judge; rec s1 hook_blocking_error PreToolUse "$(HOOK)" 120 blockingError "regatta: core missing (no home file)"
hw scan --dry-run > "$T/o" 2>&1
has "$T/o" "would pin primary at ${C1:0:12} (judge: h.py (core missing))" "judge: a deny that says it cannot judge"
world to3; for s in s1 s2 s3; do rec $s hook_cancelled PreToolUse "$(HOOK)" 120 content "" timed; done
hw scan --dry-run > "$T/o" 2>&1
has "$T/o" "(timeout: h.py (timed out in 3 sessions))" "timeout: one hook in 3 sessions"
world to2; for s in s1 s2 s2; do rec $s hook_cancelled PreToolUse "$(HOOK)" 120 content "" timed; done
hw scan --dry-run > "$T/o" 2>&1
check "$(cat "$T/o")" "" "  in 2 sessions (3 timeouts): no fault"
world deny17; for i in $(seq 17); do rec s1 hook_blocking_error PreToolUse "$(HOOK)" 120 blockingError "no"; done
for i in 1 2 3; do rec s1 hook_success PreToolUse "$(HOOK)" 120 stdout ""; done
hw scan --dry-run > "$T/o" 2>&1
has "$T/o" "(denies: h.py (denied 17 of 20 calls))" "denies: over 80 % of 20 calls"
world deny16; for i in $(seq 15); do rec s1 hook_blocking_error PreToolUse "$(HOOK)" 120 blockingError "no"; done
rec s1 hook_success PreToolUse "$(HOOK)" 120 stdout '{"hookSpecificOutput": {"permissionDecision": "deny"}}'
for i in 1 2 3 4; do rec s1 hook_success PreToolUse "$(HOOK)" 120 stdout ""; done
hw scan --dry-run > "$T/o" 2>&1
check "$(cat "$T/o")" "" "  16 of 20 (a JSON deny counted among them): exactly 80 %, no fault"
world stood; printf '{"head": "%s", "clean": "%s", "moved_at": %s}\n' "$C2" "$C1" $((N - 2400)) > "$W/state.json"
rec s1 hook_non_blocking_error SessionStart "$(HOOK)" 120 stderr "$(TB)"
hw scan > "$T/o" 2>&1
has "$T/o" "which has stood over 30 min: reported, not pinned" "a fault on a HEAD that stood the window: reported, never pinned"
check "$(git -C "$R" symbolic-ref --short HEAD)" "main" "  the primary stays on main"
world first; rm -f "$W/state.json"; rec s1 hook_non_blocking_error SessionStart "$(HOOK)" 120 stderr "$(TB)"
hw scan --dry-run > "$T/o" 2>&1
has "$T/o" "not pinned: no clean sha is known yet" "the first pass knows no clean sha: HEAD@{1} is never guessed (finding 9)"

echo "a fault counts only for a hook the move changed (the landing review, findings 8, 13, 16)"
world untouched; for s in s1 s2 s3; do rec $s hook_cancelled PreToolUse "$(GHOOK)" 120 content "" timed; done
hw scan --dry-run > "$T/o" 2>&1
check "$(cat "$T/o")" "" "g.py times out in 3 sessions, but c2 changed only h.py: no fault"
world viaimport modules/x/lib/helper.py; for s in s1 s2 s3; do rec $s hook_cancelled PreToolUse "$(GHOOK)" 120 content "" timed; done
hw scan --dry-run > "$T/o" 2>&1
has "$T/o" "(timeout: g.py (timed out in 3 sessions))" "  c2 changed lib/helper.py, which g.py imports: the timeout counts"
world overlay; for s in s1 s2 s3; do rec $s hook_cancelled PreToolUse "python3 $T/overlay/hooks/sheep_gate.py" 120 content "" timed; done
hw scan --dry-run > "$T/o" 2>&1
check "$(cat "$T/o")" "" "an overlay hook's timeouts (the replay's four false pins: sheep_gate.py under the overlay) are not this checkout's"
world shim; rec s1 hook_non_blocking_error SessionStart "python3 $T/overlay/hooks/h-shim.py" 120 stderr "$(TB)"
hw scan --dry-run > "$T/o" 2>&1
has "$T/o" "would pin primary at ${C1:0:12} (crash:" "  an overlay shim whose traceback runs through the checkout's changed h.py: a crash"
world quoted; rec s1 hook_success SessionStart "$(HOOK)" 120 stdout "bulletin: the lander's judge did not load (bin/autofinish), yesterday"
hw scan --dry-run > "$T/o" 2>&1
check "$(cat "$T/o")" "" "a SessionStart hook that prints 'did not load' (a bulletin quoting one) is no judge fault"
world jsondeny; rec s1 hook_success PreToolUse "$(HOOK)" 120 stdout '{"hookSpecificOutput": {"permissionDecision": "deny", "permissionDecisionReason": "regatta: core missing"}}'
hw scan --dry-run > "$T/o" 2>&1
has "$T/o" "(judge: h.py (core missing))" "  a JSON deny whose reason says it cannot judge is one"

echo "replay: the reviewer's 3-day replay as a case (0 of its 59 moves pin)"
world replay; for s in s1 s2 s3; do rec $s hook_cancelled PreToolUse "python3 $T/overlay/hooks/sheep_gate.py" 120 content "" timed
  rec $s hook_cancelled PreToolUse "$(GHOOK)" 120 content "" timed; done
hw replay --days 3 > "$T/o" 2>&1
has "$T/o" "replay: 0 of 1 moves in 3 days would pin" "overlay timeouts and an unchanged hook's: the move never pins"
rec s1 hook_non_blocking_error SessionStart "$(HOOK)" 120 stderr "$(TB)"
hw replay --days 3 > "$T/o" 2>&1
has "$T/o" "replay: 1 of 1 moves in 3 days would pin" "  a crash in the hook the move changed: it would"
check "$(git -C "$R" symbolic-ref --short HEAD):$(grep -c offsets "$W/state.json")" "main:0" "  read-only: the checkout and the state untouched"

echo "offsets: a pass reads only what was appended since the last (finding 17)"
world offs; rec s1 hook_success PreToolUse "$(HOOK)" 60 stdout ok
hw scan > /dev/null 2>&1
check "$(python3 -c 'import json, os, sys; s = json.load(open(sys.argv[1])); print(list(s["offsets"].values())[0] == os.path.getsize(sys.argv[2]), len(s["records"]))' "$W/state.json" "$W/login/projects/p/s1.jsonl")" \
  "True 1" "the state keeps each file's offset and the window's matched records"
rec s1 hook_non_blocking_error SessionStart "$(HOOK)" 30 stderr "$(TB)"
hw scan --dry-run > "$T/o" 2>&1
has "$T/o" "would pin primary at ${C1:0:12} (crash:" "  a record appended after the offset is read on the next pass"

echo "the pin and the revert PR (S4, D3-B)"
world pin; rec s1 hook_non_blocking_error SessionStart "$(HOOK)" 120 stderr "$(TB)"
# this world keeps the state where an install does, the config dir, which regatta check reads
mkdir -p "$REGATTA_CONFIG/lighthouse"; mv "$W/state.json" "$REGATTA_CONFIG/lighthouse/hookwatch.json"; unset HOOKWATCH_STATE
ST="$REGATTA_CONFIG/lighthouse/hookwatch.json"
printf 'import sys\nopen(sys.argv[1], "a").write(sys.argv[2] + "\\n")\n' > "$T/post.py"
export HOOKWATCH_POST="python3 $T/post.py $T/posts"; : > "$T/posts"
: > "$GH_LOG"; hw scan > "$T/o" 2>&1
has "$T/o" "hookwatch: pinned primary at ${C1:0:12}, back from ${C2:0:12} (crash: h.py" "a fault within the window pins the primary at the clean sha"
check "$(git -C "$R" rev-parse HEAD):$(git -C "$R" symbolic-ref -q HEAD || echo detached)" "$C1:detached" "  HEAD detached at the clean sha"
check "$(head -1 "$R/modules/x/hooks/h.py")" "print('v1')" "  the pinned primary loads the old hook"
RB="claude/test/$(dateat "$N" +%Y-%m-%d)-hookwatch-revert-${C2:0:7}"
RV=$(git -C "$W/origin.git" rev-parse "$RB" 2>/dev/null)
check "$(git -C "$W/origin.git" rev-parse "$RV^{tree}"):$(git -C "$W/origin.git" rev-parse "$RV^@")" "$(git -C "$R" rev-parse "$C1^{tree}"):$C2" \
  "  the revert pushed as its own claude/* branch: the clean sha's tree on the pinned head, nothing else"
check "$(python3 -c 'import json,sys; a=json.loads(open(sys.argv[1]).readline()); print(a[:5], "--draft" in a)' "$GH_LOG")" \
  "['pr', 'create', '--head', '$RB', '--base'] False" "  a range off the owner's paths: opened ready, for automerge once check passes"
has "$T/o" "revert PR opened: https://github.invalid/o/r/pull/9" "  the pin's line names the PR"
has "$REGATTA_CONFIG/lighthouse/hookwatch.log" "pinned primary at ${C1:0:12}" "  and the line is logged beside the state"
check "$(python3 -c 'import json,sys; p=json.load(open(sys.argv[1]))["pinned"]; print(p["to"] == sys.argv[2], p["from"] == sys.argv[3], p["pr"], p["paths"])' "$ST" "$C1" "$C2")" \
  "True True https://github.invalid/o/r/pull/9 ['modules/x/hooks/h.py']" "  the state records the pin and the file the fault implicated"
# sync.py, the one thing that moves a primary at a session start, leaves a detached one alone and names the pin
push3 README.md
mkdir -p "$REGATTA_CONFIG"; echo "$(cd "$M/.." && pwd)" > "$REGATTA_CONFIG/home"
python3 - "$M/wharf/hooks" "$R" > "$T/sync.out" 2>&1 <<'EOF'
import sys
from pathlib import Path
sys.path.insert(0, sys.argv[1])
import sync
print(sync.sync(Path(sys.argv[2])))
EOF
check "$(git -C "$R" rev-parse HEAD):$(git -C "$R" rev-parse origin/main)" "$C1:$C3" "  sync.py fetches but leaves the pinned primary where it is (origin/main moved on)"
has "$T/sync.out" "primary: pinned by hookwatch at ${C1:0:12}" "  and its note names the pin (finding 14)"
hw scan > "$T/o" 2>&1
has "$T/o" "pinned at ${C1:0:12} since" "a pass while pinned says so"
has "$T/o" "main moved to ${C3:0:12}" "  and that main moved since — a commit that leaves h.py as it was ends nothing"
hw scan > "$T/o2" 2>&1
check "$(grep -c 'pinned at .* since' "$T/posts"):$(grep -c "pinned at ${C1:0:12} since" "$T/o2")" "1:1" \
  "  posted once per change of origin/main: a second pass prints, posts nothing (finding 18)"
python3 "$M/regatta/bin/regatta" check > "$T/rc" 2>&1
has "$T/rc" "--  pinned: primary detached at ${C1:0:12} by hookwatch" "regatta check reports the pin as a finding"
push3 modules/x/hooks/h.py
hw scan > "$T/o" 2>&1
has "$T/o" "unpinned itself — origin/main ${C3:0:12} carries the revert or a fix" "origin/main changes h.py again: the pin ends by itself (finding 14)"
check "$(git -C "$R" symbolic-ref --short HEAD):$(git -C "$R" rev-parse HEAD):$(python3 -c 'import json,sys; s=json.load(open(sys.argv[1])); print(s["pinned"], int(s["moved_at"]))' "$ST")" \
  "main:$C3:None $N" "  on main, fast-forwarded to it, on probation from now"
unset HOOKWATCH_POST

echo "unpin, and a person's own checkout"
world unp; rec s1 hook_non_blocking_error SessionStart "$(HOOK)" 120 stderr "$(TB)"
hw scan --no-pr > /dev/null 2>&1
hw unpin > "$T/o" 2>&1
check "$(git -C "$R" symbolic-ref --short HEAD):$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["pinned"])' "$W/state.json")" "main:None" \
  "unpin: back on main, the pin cleared"
world hand; rec s1 hook_non_blocking_error SessionStart "$(HOOK)" 120 stderr "$(TB)"
hw scan --no-pr > /dev/null 2>&1
git -C "$R" checkout -q main
HOOKWATCH_NOW=$((N + 60)) hw scan > "$T/o" 2>&1
check "$(python3 -c 'import json,sys; s=json.load(open(sys.argv[1])); print(s["pinned"], s["head"] == sys.argv[2], int(s["moved_at"]))' "$W/state.json" "$C2")" "None True $((N + 60))" \
  "a person's own checkout of main ends the pin and starts probation, as unpin does (finding 19)"
HOOKWATCH_NOW=$((N + 60 + 1900)) hw scan > /dev/null 2>&1
check "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["clean"] == sys.argv[2])' "$W/state.json" "$C2")" "True" \
  "  and only a quiet window after that makes it the clean sha"

echo "the revert held for the owner (finding 1)"
world held "modules/x/hooks/h.py .claude/workflow.json"; rec s1 hook_non_blocking_error SessionStart "$(HOOK)" 120 stderr "$(TB)"
: > "$GH_LOG"; hw scan > "$T/o" 2>&1
check "$(python3 -c 'import json,sys; print("--draft" in json.loads(open(sys.argv[1]).readline()))' "$GH_LOG")" "True" \
  "a range that touches .claude/workflow.json: the revert opens as a draft, which automerge never lands"
has "$T/o" "as a draft — it touches .claude/workflow.json" "  and the pin's line says why"
world unfetched; rec s1 hook_non_blocking_error SessionStart "$(HOOK)" 120 stderr "$(TB)"
push3 README.md; : > "$GH_LOG"
hw scan > "$T/o" 2>&1
has "$T/o" "no revert PR: origin/main (${C3:0:12}" "origin/main moved but not fetched here: the pass fetches first, and opens nothing"
check "$(wc -l < "$GH_LOG" | tr -d ' ')" "0" "  gh never ran"

echo "what is never pinned, or never reverted"
world moved; rec s1 hook_non_blocking_error SessionStart "$(HOOK)" 120 stderr "$(TB)"
O2="$W/other"; git clone -q "$W/origin.git" "$O2"; echo x >> "$O2/modules/x/hooks/h.py"; git -C "$O2" commit -qam c3
git -C "$O2" push -q origin main; git -C "$R" fetch -q origin; : > "$GH_LOG"
hw scan > "$T/o" 2>&1
has "$T/o" "no revert PR: origin/main" "origin/main past the pinned head: pinned, but no revert PR (it would not be the exact inverse)"
check "$(git -C "$R" rev-parse HEAD):$(wc -l < "$GH_LOG" | tr -d ' ')" "$C1:0" "  the pin holds; gh never ran"
world branch; rec s1 hook_non_blocking_error SessionStart "$(HOOK)" 120 stderr "$(TB)"; GIT_COMMITTER_DATE="@$((N - 600))" git -C "$R" checkout -q -b feature
hw scan > "$T/o" 2>&1
has "$T/o" "not pinned: the primary is not on a checked-out main" "a primary on another branch: reported, not pinned"
world dirty; rec s1 hook_non_blocking_error SessionStart "$(HOOK)" 120 stderr "$(TB)"; echo "print('mine')" > "$R/modules/x/hooks/h.py"
hw scan > "$T/o" 2>&1
has "$T/o" "not pinned: the primary has tracked changes" "a primary with tracked changes: reported, not pinned"
check "$(cat "$R/modules/x/hooks/h.py")" "print('mine')" "  and the change is untouched"
world noclean; rec s1 hook_non_blocking_error SessionStart "$(HOOK)" 120 stderr "$(TB)"
printf '{"head": "%s", "moved_at": %s}\n' "$C1" $((N - 7200)) > "$W/state.json"
hw scan > "$T/o" 2>&1
has "$T/o" "not pinned: no clean sha is known yet" "no clean sha known: reported, not pinned"
NOSELF=1 world noself; rec s1 hook_non_blocking_error SessionStart "$(HOOK)" 120 stderr "$(TB)"
hw scan > "$T/o" 2>&1
has "$T/o" "has no hookwatch: pinned there, the LaunchAgent would run nothing" "a clean sha without hookwatch: never pinned to (finding 9)"
world dry; rec s1 hook_non_blocking_error SessionStart "$(HOOK)" 120 stderr "$(TB)"; GIT_COMMITTER_DATE="@$((N - 600))" git -C "$R" checkout -q -b side
HOOKWATCH_POST="python3 $T/post.py $T/posts-dry" hw scan --dry-run > "$T/o" 2>&1
check "$(grep -c 'not pinned' "$T/o"):$([ -e "$T/posts-dry" ] && echo posted || echo none):$([ -e "$W/hookwatch.log" ] && echo logged || echo none)" "1:none:none" \
  "--dry-run prints only: no post, no log line (finding 15)"

echo "the LaunchAgent: printed, never loaded here"
hw install --dry-run > "$T/o" 2>&1
has "$T/o" "<key>Label</key><string>regatta.hookwatch</string>" "install --dry-run prints the plist"
has "$T/o" "<key>StartInterval</key><integer>600</integer>" "  every 10 min"
H=$HOME; HOOKWATCH_POST="x y" HOOKWATCH_GH=/opt/gh hw install --dry-run > "$T/o" 2>&1
has "$T/o" "<key>PATH</key><string>/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:$H/.local/bin</string>" "  the plist carries helm's PATH: gh is found under launchd (finding 12)"
has "$T/o" "<key>REGATTA_CONFIG</key><string>$REGATTA_CONFIG</string>" "  and REGATTA_CONFIG"
has "$T/o" "<key>HOOKWATCH_GH</key><string>/opt/gh</string>" "  and every HOOKWATCH_* set at install"
CLAUDE_UNATTENDED=dispatch hw install > "$T/o" 2>&1; rc=$?
check "$rc:$([ -e "$T/h/Library/LaunchAgents/regatta.hookwatch.plist" ] && echo written || echo none)" "1:none" "  install refuses an unattended caller"

[ "$fails" -eq 0 ] && echo "hookwatch: all ok" || echo "hookwatch: $fails failed"
[ "$fails" -eq 0 ]
