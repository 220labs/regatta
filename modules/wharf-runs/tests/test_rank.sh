#!/usr/bin/env bash
# Tests for the queue's rank on every claim road (queue-rank, 2026-10-31): a build re-dispatched while its own run
# was busy (`enqueue` → `replaced`) was claimed as that run's --next, reserved `waiting`, and took the run's slot
# the moment it parked — ahead of four landings queued 1-3 h on a full host (the laptop's queue.jsonl, 00:42 PDT).
# Each road — enqueue --claim (dispatch's own call), claim (the fire path's end), claim --event-at (the watcher's,
# as its run parks), sweep (and the kick, which only kickstarts it), poll — meets the same scene: the cap full, a
# finish queued (finish-as-task: a fleet entry like a build, ranked ahead of a build of the same priority), the
# build re-queued as its run's slot frees; the finish takes the slot, the build waits. Then
# the label: a claim through dispatch builds its job's label from `wharf-runs/label-prefix`, never the previous
# prefix. A suite of its own, apart from test_queue.sh, test_after.sh and test_dispatch.sh, so no two steps edit
# one file's tail. Scratch HOME, bare repos as origin and the queue's home, a stand-in launchctl; no launchd job,
# session or network is touched. Every name is synthetic.
#   bash modules/wharf-runs/tests/test_rank.sh
set -u
unset WEEKLY_RUN CLAUDE_UNATTENDED REGATTA_UNATTENDED CLAUDECODE CLAUDE_CODE_DISABLE_BACKGROUND_TASKS CLAUDE_CODE_SESSION_ID CLAUDE_CONFIG_DIR XPC_SERVICE_NAME AUTOFINISH_CALLER_UNATTENDED
unset $(compgen -v | grep '^DISPATCH_')   # every DISPATCH_* a run carries (AGENTS.md: a fixed list goes stale)
B="$(cd "$(dirname "$0")/../bin" && pwd)"
T=$(mktemp -d)
PIDS=()
trap 'for p in "${PIDS[@]+"${PIDS[@]}"}"; do kill "$p" 2>/dev/null; done; rm -rf "$T"' EXIT
. "$(cd "$(dirname "$0")" && pwd)/config_fixture.sh"; fixture_config "$T/config"
fails=0
check() { if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3: expected [$2] got [$1]"; fails=$((fails+1)); fi; }
has()   { if grep -qF -- "$2" "$1"; then echo "  ok   $3"; else echo "  FAIL $3: missing [$2]"; sed 's/^/         | /' "$1" | head -20; fails=$((fails+1)); fi; }
export PYTHONUSERBASE="${PYTHONUSERBASE:-$(python3 -m site --user-base)}"
export HOME="$T/h"; HL="$T/h/Library"; mkdir -p "$HL/LaunchAgents"
fixture_finish_ready   # a finish claim judges as on a Mac, whatever host runs the suite
# a recursive delete under HOME goes through rm_own: only under this suite's own $T (the core's check, home_rm)
rm_own() { local p; for p; do case "$p" in */..|*/../*|*//*) ;; "${T:?}"/?*) rm -rf -- "$p"; continue ;; esac; echo "rm_own: refused $p, outside $T" >&2; return 1; done; }
export ACCOUNTS_FILE="$T/no-accounts.json"
# a moved HOME drops the global git identity (AGENTS.md: a suite that moves HOME and commits)
printf '[user]\n\tname = t\n\temail = t@t\n[init]\n\tdefaultBranch = main\n' > "$T/gitconfig"; export GIT_CONFIG_GLOBAL="$T/gitconfig"
cat > "$T/launchctl" <<EOF
#!/bin/sh
echo "\$*" >> "$T/calls"
exit 0
EOF
chmod +x "$T/launchctl"
export DISPATCH_LAUNCHCTL="$T/launchctl" DISPATCH_DEFAULT_ON= DISPATCH_HOST=laptop
git init -q --bare "$T/origin.git"
git clone -q "$T/origin.git" "$T/repo" 2>/dev/null
(cd "$T/repo" && printf -- '- physical: none\n' > AGENTS.md && echo x > f && git add . && git commit -qm init && git push -q origin main)
git init -q --bare "$T/queue.git"
echo "$T/queue.git" > "$REGATTA_CONFIG/wharf-runs/queue-repo"
BR=claude/laptop/2026-10-31
QB="$B/dispatch-queue"; LA="$HL/LaunchAgents"; QL="$HL/Logs/claude-weekly/queue.jsonl"
RUNS="$HL/Logs/claude-weekly/run-seed-runs"
QC2=(--cap 2 --launchctl "$T/launchctl" --prefix org.example.claude --jobbin "$B/dispatch")
QGIT=(git --git-dir="$T/queue.git")
cat > "$T/qget.py" <<'PY'
import json, sys
d = json.load(sys.stdin)
print(" ".join(json.dumps(d.get(k)) if isinstance(d.get(k), (list, dict)) else str(d.get(k)) for k in sys.argv[1:]))
PY
cat > "$T/jget.py" <<'PY'
import json, sys
d = json.loads(sys.stdin.read().strip().splitlines()[-1])
print(" ".join(json.dumps(d.get(k)) for k in sys.argv[1:]))
PY
qget() { local k=$1; shift; "${QGIT[@]}" show "refs/regatta/queue:queue/$k.json" 2>/dev/null | python3 "$T/qget.py" "$@" 2>/dev/null; }
fin() {   # TOPIC: a finish of $BR-TOPIC queued, as autofinish-run's put makes one (dispatch --queue-finish)
  python3 "$QB" enqueue --kind finish --repo "$T/repo" --branch "$BR-$1" --tip "$(git -C "$T/repo" rev-parse HEAD)" \
    --finish '{"by": "sweep", "rule": "A", "from": "laptop"}' "${QC2[@]}" > /dev/null
}
pst() { TZ=UTC LC_ALL=C ps -o lstart= -p "$1" | xargs; }   # what dispatch records as proc_start
live() { sleep 600 & PIDS+=("$!"); LIVE=$!; }   # a stand-in process; its pid in LIVE
rec() {   # TOPIC PID SESSION [QID]: a busy run's record, as dispatch-rc writes one
  mkdir -p "$RUNS"
  printf '{"mode":"headless","repo":"%s","topic":"%s","branch":"%s-%s","pid":%s,"proc_start":"%s","session":"%s","started":%s%s}' \
    "$T/repo" "$1" "$BR" "$1" "$2" "$(pst "$2")" "$3" "$(date +%s)" "${4:+, \"queue\": \"$4\"}" > "$RUNS/00000000-0000$RANDOM-repo.$1.json"
}
qreset() {
  { for p in "${PIDS[@]+"${PIDS[@]}"}"; do kill "$p"; wait "$p"; done; } 2>/dev/null; PIDS=()
  "${QGIT[@]}" update-ref -d refs/regatta/queue 2>/dev/null
  rm_own "$HL/Caches/run-seed/queue" "$HL/Caches/run-seed/queue-local" "$RUNS"
  rm_own "$LA"/*.plist; rm -f "$T/calls" "$QL"
}
reserved() { python3 "$QB" reserved "${QC2[@]}"; }

# The scene, cap 2: another topic's run busy, and the build `pcf` claimed, started and busy (its record names its
# entry); a finish queued behind them. The host is full.
scene() {
  qreset
  live; rec other "$LIVE" s-other
  python3 "$QB" enqueue --repo "$T/repo" --branch "$BR-pcf" "${QC2[@]}" > /dev/null
  python3 "$QB" claim "${QC2[@]}" > /dev/null
  python3 "$QB" started fleet:repo--pcf --session s-pcf "${QC2[@]}" > /dev/null
  live; PCF=$LIVE; rec pcf "$PCF" s-pcf fleet:repo--pcf
  fin ship
}
requeue() {   # the build re-dispatched on the host its branch runs on: its live entry replaced (item 19's road)
  python3 "$QB" enqueue --repo "$T/repo" --branch "$BR-pcf" "${QC2[@]}" "$@"
}
free() { { kill "$PCF"; wait "$PCF"; } 2>/dev/null; }   # the build's earlier run ends: its slot frees

echo "the scene: cap 2 full, a finish queued, the build's own run busy"
scene
check "$(qget repo--pcf state running_on) $(qget repo--ship kind state) $(reserved)" "running laptop finish queued 0" \
  "  the build's entry running here, the finish queued, no reservation outstanding"
requeue > "$T/out"
check "$(python3 "$T/jget.py" result < "$T/out")" '"replaced"' "  a re-dispatch of the build replaces its live entry"

road() {   # NAME CMD...: the road's claim, run twice — the build's run still busy, then just after it freed
  local name=$1; shift
  echo "road: $name"
  scene; requeue > /dev/null
  "$@" > "$T/out" 2>&1
  check "$(qget repo--pcf state) $(qget repo--ship state) $(reserved)" "queued queued 0" \
    "  the build re-queued while its run is busy: not claimed as that run's --next, nothing reserved (the finish ranks ahead)"
  free
  "$@" > "$T/out" 2>&1
  check "$(qget repo--ship state) $(qget repo--pcf state)" "claimed queued" "  its run's slot frees: the finish takes it, the build waits"
  check "$(cat "$HL/Caches/run-seed/queue/claims/"*.json 2>/dev/null | python3 -c 'import json,sys; print(" ".join(sorted(json.loads(l)["qid"] for l in sys.stdin.read().replace("}{", "}\n{").splitlines() if l.strip())))')" \
    "fleet:repo--ship" "  one reservation, the finish's"
}
road "enqueue --claim (dispatch's own call)" python3 "$QB" enqueue --repo "$T/repo" --branch "$BR-pcf" --claim "${QC2[@]}"
road "claim (the fire path's end)" python3 "$QB" claim "${QC2[@]}"
road "claim --event-at (the watcher's, as its run parks)" python3 "$QB" claim --event-at "$(date +%s)" "${QC2[@]}"
road "sweep (and a kick, which kickstarts it)" python3 "$QB" sweep "${QC2[@]}"
road "poll" python3 "$QB" poll "${QC2[@]}"

echo "road: the enqueue's own JSON says why"
scene
requeue --claim > "$T/out"
check "$(python3 "$T/jget.py" result claimed < "$T/out")" '"replaced" []' "  replaced, claimed nothing"
has "$T/out" '"no_room": "the run cap (2 of 2 busy on laptop)"' "  naming the cap"
has "$QL" '"keys": ["fleet:repo--ship", "fleet:repo--pcf"]' "  the no-room line lists the finish first, the build behind it"

echo "the rule's edges: rank, not a blanket wait"
scene
python3 "$QB" cancel --repo "$T/repo" --branch "$BR-ship" "${QC2[@]}" > /dev/null   # the finish cancelled: its tombstone ranks nowhere
requeue --claim > "$T/out"
check "$(python3 "$T/jget.py" claimed < "$T/out")" '["fleet:repo--pcf"]' \
  "nothing ranked ahead waits: a live run's --next is still claimed on a full host (item 7)"
check "$(reserved)" "0" "  reserved waiting: the run it follows holds the one slot, never both"
qreset
live; rec other "$LIVE" s-other
python3 "$QB" enqueue --repo "$T/repo" --branch "$BR-older" "${QC2[@]}" > /dev/null
sleep 1
python3 "$QB" enqueue --repo "$T/repo" --branch "$BR-pcf" "${QC2[@]}" > /dev/null
live; rec pcf "$LIVE" s-pcf
python3 "$QB" claim "${QC2[@]}" > /dev/null
check "$(qget repo--older state) $(qget repo--pcf state) $(reserved)" "queued queued 0" \
  "an older build waiting with no room ranks ahead of a live run's --next too (age, after priority): neither claimed"

git clone -q "$T/origin.git" "$T/other" 2>/dev/null
OG=(git -C "$T/other")
pred() { "${OG[@]}" fetch -q origin; "${OG[@]}" checkout -q -B "$BR-$1" origin/main
  echo "$1" > "$T/other/f-$1"; "${OG[@]}" add -A; "${OG[@]}" commit -qm "build $1"; "${OG[@]}" push -q -f origin "$BR-$1"; "${OG[@]}" checkout -q --detach; }
landp() { "${OG[@]}" fetch -q origin; "${OG[@]}" checkout -q -B main origin/main
  "${OG[@]}" merge -q --no-ff -m "merge $1" "$BR-$1"; "${OG[@]}" push -q origin main; "${OG[@]}" checkout -q --detach; }
export LANDED_NO_GH=1

echo "an own finish ahead (its topic has a record not ended, its pid dead) finds no room: the stop holds for the --next behind it"
qreset
live; rec other "$LIVE" s-other
python3 "$QB" enqueue --repo "$T/repo" --branch "$BR-pcf" "${QC2[@]}" > /dev/null
python3 "$QB" claim "${QC2[@]}" > /dev/null
python3 "$QB" started fleet:repo--pcf --session s-pcf "${QC2[@]}" > /dev/null
live; PCF=$LIVE; rec pcf "$PCF" s-pcf fleet:repo--pcf
sleep 30 & SH=$!; rec ship "$SH" s-ship; kill "$SH"; wait "$SH" 2>/dev/null
fin ship
requeue > /dev/null
python3 "$QB" claim "${QC2[@]}" > "$T/out" 2>&1
check "$(qget repo--pcf state) $(qget repo--ship state) $(reserved)" "queued queued 0" "  the --next waits, nothing reserved"

echo "an --after entry ahead, its predecessor landed, on a full host: the room filter sets it aside; judged in rank order, landed, it holds the --next behind it"
qreset
live; rec other "$LIVE" s-other
python3 "$QB" enqueue --repo "$T/repo" --branch "$BR-pcf" "${QC2[@]}" > /dev/null
python3 "$QB" claim "${QC2[@]}" > /dev/null
python3 "$QB" started fleet:repo--pcf --session s-pcf "${QC2[@]}" > /dev/null
live; PCF=$LIVE; rec pcf "$PCF" s-pcf fleet:repo--pcf
pred alpha
python3 "$QB" enqueue --repo "$T/repo" --branch "$BR-older" --after "$BR-alpha" "${QC2[@]}" > /dev/null
landp alpha
sleep 1
requeue > /dev/null
python3 "$QB" claim "${QC2[@]}" > "$T/out" 2>&1
check "$(qget repo--older state) $(qget repo--pcf state)" "queued queued" "  neither claimed"
has "$QL" '"keys": ["fleet:repo--older", "fleet:repo--pcf"]' "  the no-room line lists the kept entry first, the --next behind it"
requeue --claim > "$T/out"
has "$T/out" '"no_room": "the run cap (2 of 2 busy on laptop; fleet:repo--older ranks ahead, waiting for a slot)"' \
  "  the enqueue's JSON names the entry ahead (dispatch prints it)"
free
python3 "$QB" claim "${QC2[@]}" > "$T/out" 2>&1
check "$(qget repo--older state) $(qget repo--pcf state)" "claimed queued" "  the slot frees: the --after entry takes it, the --next waits"
qreset

echo "an --after entry ahead whose predecessor has not landed waits on it, not on a slot: it stops nothing behind it"
live; rec other "$LIVE" s-other
python3 "$QB" enqueue --repo "$T/repo" --branch "$BR-pcf" "${QC2[@]}" > /dev/null
python3 "$QB" claim "${QC2[@]}" > /dev/null
python3 "$QB" started fleet:repo--pcf --session s-pcf "${QC2[@]}" > /dev/null
live; PCF=$LIVE; rec pcf "$PCF" s-pcf fleet:repo--pcf
pred beta
python3 "$QB" enqueue --repo "$T/repo" --branch "$BR-older" --after "$BR-beta" "${QC2[@]}" > /dev/null
sleep 1
requeue --claim > "$T/out"
check "$(python3 "$T/jget.py" claimed < "$T/out")" '["fleet:repo--pcf"]' \
  "  the live run's --next is claimed past it (without the after test, a chain --after its own run's branch deadlocks)"
check "$(qget repo--older state) $(reserved)" "queued 0" "  the --after entry still queued; the --next reserved waiting"
qreset

echo "the label: a claim through dispatch takes wharf-runs/label-prefix, never the previous one"
qreset
echo org.next.claude > "$REGATTA_CONFIG/wharf-runs/label-prefix"
echo org.example.claude > "$REGATTA_CONFIG/wharf-runs/label-prefix-previous"
python3 "$QB" enqueue --repo "$T/repo" --branch "$BR-lbl" "${QC2[@]}" > /dev/null
"$B/dispatch" --claim > "$T/out" 2>&1; check "$?" "0" "dispatch's claim road (the watcher's call): exit 0"
check "$(qget repo--lbl state)" "claimed" "  the entry claimed"
check "$(qget repo--lbl job | cut -d. -f1-5)" "org.next.claude.dispatch.repo" "  its job's label under the current prefix"
check "$(ls "$LA" | grep -c '^org\.next\.claude\.dispatch\.repo\.lbl\.q[0-9]*\.plist$') $(ls "$LA" | grep -c '^org\.example\.claude\.dispatch')" "1 0" \
  "  its plist under it, none under the previous prefix"
has "$QL" '"label": "org.next.claude.dispatch.repo.lbl.q' "  and the claimed line in queue.jsonl names it"
check "$(grep -ohE '\b(org|dev|com|info|net|io)\.[a-z0-9]+\.claude\b' "$B/dispatch" "$B/dispatch-queue" "$B/dispatch-rc" | sort -u | tr '\n' ' ')" "org.regatta.claude " \
  "no owner's prefix is spelled in dispatch, dispatch-queue or dispatch-rc: each label comes from the config key, the public default aside"
echo org.example.claude > "$REGATTA_CONFIG/wharf-runs/label-prefix"; rm -f "$REGATTA_CONFIG/wharf-runs/label-prefix-previous"
qreset

echo
[ "$fails" = 0 ] && echo "test_rank: all passed" || { echo "test_rank: $fails failed"; exit 1; }
