#!/usr/bin/env bash
# Tests for the queue's S9 (docs/dispatch-queue-2026-10-25.md): after-landed — bin/landed.py, the reader that
# proves a predecessor on origin/<main> with every refusal of AGENTS.md's vacuous-proof trap; `--after` in the
# entry, the claim that skips it until the predecessor landed (one case lands it in a bare-origin fixture and
# proves the waiting entry is claimed only after), the cards for a predecessor that will not land, the poll's
# reuse of a young hold, the fired run's merge of origin/main; and landings in the queue — `dispatch --start`'s
# /finish with no room waiting in queue-local/_land, ranked above builds by its kind, claimed for its own process,
# and autofinish-run's `queued` verdict. A suite of its own, apart from test_queue.sh, test_priority.sh and
# test_dispatch.sh, so no two steps edit one file's tail. Scratch HOME, bare repos as origin and the queue's home,
# a stand-in launchctl; no launchd job, session or network is touched. Every name is synthetic.
#   bash modules/wharf-runs/tests/test_after.sh
set -u
unset WEEKLY_RUN CLAUDE_UNATTENDED CLAUDECODE CLAUDE_CODE_DISABLE_BACKGROUND_TASKS CLAUDE_CODE_SESSION_ID CLAUDE_CONFIG_DIR XPC_SERVICE_NAME AUTOFINISH_CALLER_UNATTENDED
unset $(compgen -v | grep '^DISPATCH_')   # every DISPATCH_* a run carries (AGENTS.md: a fixed list goes stale)
B="$(cd "$(dirname "$0")/../bin" && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
. "$(cd "$(dirname "$0")" && pwd)/config_fixture.sh"; fixture_config "$T/config"
fails=0
check() { if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3: expected [$2] got [$1]"; fails=$((fails+1)); fi; }
has()   { if grep -qF -- "$2" "$1"; then echo "  ok   $3"; else echo "  FAIL $3: missing [$2]"; sed 's/^/         | /' "$1" | head -20; fails=$((fails+1)); fi; }
hasnt() { if grep -qF -- "$2" "$1"; then echo "  FAIL $3: unexpected [$2]"; sed 's/^/         | /' "$1" | head -20; fails=$((fails+1)); else echo "  ok   $3"; fi; }
export PYTHONUSERBASE="${PYTHONUSERBASE:-$(python3 -m site --user-base)}"
export HOME="$T/home"; HL="$HOME/Library"; mkdir -p "$HL/LaunchAgents"
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
# origin: a bare repo; REPO is this host's clone (the queue's claim and the reader run in it); OTHER is the
# predecessors' builder elsewhere, so REPO's reflog holds none of their commits (only a recorded sighting does)
git init -q --bare "$T/origin.git"
git clone -q "$T/origin.git" "$T/repo" 2>/dev/null
(cd "$T/repo" && printf -- '- physical: none\n' > AGENTS.md && echo x > f && git add . && git commit -qm init && git push -q origin main)
git clone -q "$T/origin.git" "$T/other" 2>/dev/null
OG=(git -C "$T/other")
BR=claude/laptop/2026-10-29
pred() {   # NAME [FILE]: a branch with a commit of its own, built in OTHER and pushed; prints SHA:FORK, a sighting
  "${OG[@]}" fetch -q origin; "${OG[@]}" checkout -q -B "$BR-$1" origin/main
  echo "$1" > "$T/other/${2:-f-$1}"; "${OG[@]}" add -A; "${OG[@]}" commit -qm "build $1"; "${OG[@]}" push -q -f origin "$BR-$1"
  "${OG[@]}" checkout -q --detach; echo "$("${OG[@]}" rev-parse "$BR-$1"):$("${OG[@]}" rev-parse origin/main)"
}
land() {   # NAME: merged into origin/main (a merge commit)
  "${OG[@]}" fetch -q origin; "${OG[@]}" checkout -q -B main origin/main
  "${OG[@]}" merge -q --no-ff -m "merge $1" "$BR-$1"; "${OG[@]}" push -q origin main; "${OG[@]}" checkout -q --detach
}
rebase_land() {   # NAME: landed as GitHub's rebase-merge leaves it — its commits replayed onto main, new shas
  "${OG[@]}" fetch -q origin; "${OG[@]}" checkout -q -B main origin/main
  GIT_COMMITTER_DATE="@$(( $(date +%s) + 60 )) +0000" "${OG[@]}" cherry-pick "origin/main..$BR-$1" > /dev/null; "${OG[@]}" push -q origin main; "${OG[@]}" checkout -q --detach
}
main_edit() {   # FILE TEXT: a later landing on main that edits FILE
  "${OG[@]}" fetch -q origin; "${OG[@]}" checkout -q -B main origin/main
  echo "$2" >> "$T/other/$1"; "${OG[@]}" add -A; "${OG[@]}" commit -qm "later $1"; "${OG[@]}" push -q origin main; "${OG[@]}" checkout -q --detach
}
L="$B/landed.py"
export LANDED_NO_GH=1   # road 3 (GitHub's merged PR) is never asked of a fixture path
judge() { python3 "$L" judge "$T/repo" "$BR-$1" "${@:2}"; }
git init -q --bare "$T/queue.git"
echo "$T/queue.git" > "$REGATTA_CONFIG/wharf-runs/queue-repo"
QB="$B/dispatch-queue"; LA="$HL/LaunchAgents"; QL="$HL/Logs/claude-weekly/queue.jsonl"
QC=(--cap 3 --launchctl "$T/launchctl" --prefix org.example.claude --jobbin "$B/dispatch")
QGIT=(git --git-dir="$T/queue.git")
cat > "$T/qget.py" <<'PY'
import json, sys
d = json.load(sys.stdin)
print(" ".join(json.dumps(d.get(k)) if isinstance(d.get(k), (list, dict)) else str(d.get(k)) for k in sys.argv[1:]))
PY
qget() { local k=$1; shift; "${QGIT[@]}" show "refs/regatta/queue:queue/$k.json" 2>/dev/null | python3 "$T/qget.py" "$@" 2>/dev/null; }
lget() { local k=$1; shift; python3 "$T/qget.py" "$@" < "$HL/Caches/run-seed/queue-local/_land/$k.json" 2>/dev/null; }
qreset() {
  "${QGIT[@]}" update-ref -d refs/regatta/queue 2>/dev/null
  rm_own "$HL/Caches/run-seed/queue" "$HL/Caches/run-seed/queue-local" "$HL/Logs/claude-weekly/run-seed-runs"
  rm_own "$LA"/*.plist; rm -f "$T/calls" "$QL"
}
enq() { python3 "$QB" enqueue --repo "$T/repo" --branch "$BR-$1" "${QC[@]}" "${@:2}"; }

echo "landed.py: a predecessor proved on origin/main, every vacuous proof refused (AGENTS.md's trap)"
judge never > "$T/out"; check "$?" "3" "never pushed: waiting (exit 3)"
has "$T/out" "waiting not on origin yet" "  said so"
S1=$(pred one)
judge one > "$T/out"; check "$?" "3" "pushed with work, not merged: waiting"
has "$T/out" "not on origin/main yet" "  not on origin/main yet"
check "$(python3 "$L" sighting "$T/repo" "$BR-one" | python3 "$T/qget.py" seen work fork)" "${S1%%:*} True ${S1#*:}" \
  "sighting: its tip on origin, work (main lacks it), and its fork, read in one ls-remote"
land one
judge one --sighting "$S1" > "$T/out"; check "$?" "0" "merged into origin/main, the sighting and its fork recorded before: landed"
has "$T/out" "every file it changed read so on origin/main" "  by the content road"
check "$(python3 -c 'import json,sys; print(sorted(json.load(open(sys.argv[1]))))' "$T/repo/.git/claude/after-landed.json")" "['$BR-one']" \
  "  the proof kept in the repo's after-landed.json"
rm -f "$T/repo/.git/claude/after-landed.json"
judge one > "$T/out"; check "$?" "4" "merged, but no sighting here (built elsewhere, nothing recorded): could not tell, never landed"
has "$T/out" "reset onto main, reads the same" "  saying a reset branch reads the same"
S2=$(pred reset)
"${OG[@]}" fetch -q origin; "${OG[@]}" push -q -f origin "origin/main:refs/heads/$BR-reset"
judge reset --sighting "$S2" > "$T/out"; check "$?" "4" "a branch reset onto main after its sighting: its work never on main — not landed"
S3=$(pred rebased f-rebased)
rebase_land rebased
judge rebased > "$T/out"; check "$?" "0" "rebase-merged (new shas, its tip never an ancestor): landed, no sighting needed"
main_edit f-rebased "a later landing's line"
judge rebased > "$T/out"; check "$?" "0" "  and still after a later landing edits the same file (the S9 review: main's current files alone decayed)"
has "$T/out" "every file it changed read so on origin/main at" "  proved at the commit that landed it"
git -C "$T/repo" fetch -q origin "$BR-rebased:refs/archive/$BR-rebased"
"${OG[@]}" push -q origin --delete "$BR-rebased"
judge rebased > "$T/out"; check "$?" "0" "  and once GitHub deleted the ref and sync archived it (refs/archive/…)"
pred combined f-shared > /dev/null
main_edit f-shared "main's own line, before the landing"
"${OG[@]}" fetch -q origin; "${OG[@]}" checkout -q -B main origin/main; echo combined-and-main > "$T/other/f-shared"
"${OG[@]}" add -A; "${OG[@]}" commit -qm "rebase-merge combined, its conflict resolved"; "${OG[@]}" push -q origin main; "${OG[@]}" checkout -q --detach
judge combined > "$T/out"; check "$?" "3" "a landing whose rebase combined edits: no content proof"
SC=$("${OG[@]}" rev-parse "origin/$BR-combined" 2>/dev/null || git -C "$T/repo" ls-remote origin "refs/heads/$BR-combined" | cut -f1)
mkdir -p "$T/repo/.git/claude"; echo "$BR-combined $SC via #7 2026-10-29" > "$T/repo/.git/claude/launched"
judge combined > "$T/out"; check "$?" "0" "  bin/pr merge's own launched record at its tip: landed (road 2)"
has "$T/out" "bin/pr merge recorded it: via #7" "  saying so"
rm -f "$T/repo/.git/claude/launched"
"${OG[@]}" fetch -q origin; "${OG[@]}" checkout -q -B "$BR-net" origin/main
echo t > "$T/other/tmp-net"; "${OG[@]}" add -A; "${OG[@]}" commit -qm add; "${OG[@]}" rm -q tmp-net; "${OG[@]}" commit -qm drop
"${OG[@]}" push -q origin "$BR-net"; SN=$("${OG[@]}" rev-parse HEAD); "${OG[@]}" checkout -q --detach
judge net --sighting "$SN" > "$T/out"; check "$?" "3" "commits that net to nothing: no landing (\"no net change\" refused)"
S4=$(pred gone)
land gone
"${OG[@]}" push -q origin --delete "$BR-gone"
judge gone --sighting "$S4" --seen "${S4%%:*}" > "$T/out"; check "$?" "0" "merged, then its ref deleted from origin: landed from its sighting"
S5=$(pred drop)
"${OG[@]}" push -q origin --delete "$BR-drop"
git -C "$T/repo" fetch -q origin 2>/dev/null
judge drop --sighting "$S5" --seen "${S5%%:*}" > "$T/out"; check "$?" "3" "deleted from origin unmerged: no landing (a gone ref proves nothing)"
has "$T/out" "gone deleted from origin and not proved" "  gone, deleted unlanded"
S6=$(pred arch)
git -C "$T/repo" fetch -q origin "$BR-arch:refs/archive/$BR-arch"
"${OG[@]}" push -q origin --delete "$BR-arch"
judge arch --sighting "$S6" --seen "${S6%%:*}" > "$T/out"; check "$?" "3" "archived unmerged: no landing"
has "$T/out" "gone archived" "  gone, archived"
cat > "$T/anc.py" <<'PY'
import importlib.util, subprocess, sys
from importlib.machinery import SourceFileLoader
ld = SourceFileLoader("landed", sys.argv[1]); m = importlib.util.module_from_spec(importlib.util.spec_from_loader("landed", ld)); ld.exec_module(m)
real = m._git
def flaky(repo, *a, **k):   # every ancestor test fails as a fork failure would: rc 125, never a "no"
    return subprocess.CompletedProcess(a, 125, "", "fork failed") if a[:2] == ("merge-base", "--is-ancestor") else real(repo, *a, **k)
m._git = flaky
print(m.judge(sys.argv[2], sys.argv[3])[0])
PY
check "$(python3 "$T/anc.py" "$L" "$T/repo" "$BR-one")" "unknown" "an ancestor test that fails (not a plain no): could not tell, never handed on as proof"
git clone -q "$T/origin.git" "$T/lost" 2>/dev/null; git -C "$T/lost" remote set-url origin "$T/nowhere.git"
python3 "$L" judge "$T/lost" "$BR-one" > "$T/out"; check "$?" "4" "an origin that does not answer: could not tell (exit 4, never 1)"
check "$(python3 "$L" main "$T/repo")" "main" "main: the repo's main (workflow.json's, else main)"

echo "the entry and the claim: --after holds it until the predecessor landed (a bare-origin fixture)"
qreset
SA=$(pred alpha); SA=${SA%%:*}
enq step --after "$BR-alpha" > "$T/out"; check "$?" "0" "enqueue --after a predecessor not landed: queued"
check "$(qget repo--step after | python3 -c 'import json,sys; a=json.load(sys.stdin)[0]; print(a["branch"].rsplit("-",1)[-1], a["seen"] == sys.argv[1], a["work"])' "$SA")" \
  "alpha True True" "  the entry carries the predecessor, its tip on origin and that it was work then"
python3 "$QB" claim "${QC[@]}" > "$T/out"
check "$(qget repo--step state)" "queued" "a claim with room: skipped, the predecessor not landed"
hasnt "$T/out" "claimed" "  nothing claimed"
python3 "$QB" list "${QC[@]}" > "$T/out"
has "$T/out" "after $BR-alpha (waiting not on origin/main yet" "the row says after <branch> and the claim's last word"
land alpha
python3 "$QB" claim "${QC[@]}" > "$T/out"
check "$(qget repo--step state)" "claimed" "the predecessor merged on origin: the next claim takes the entry"
P=$(ls "$LA"/org.example.claude.dispatch.repo.step.q*.plist 2>/dev/null | head -1)
check "$(plutil -extract ProgramArguments json -o - "$P" 2>/dev/null | python3 -c 'import json,sys; a=json.load(sys.stdin); i=a.index("--after"); print(a[i+1].rsplit("-",1)[-1], a[-2])')" "alpha --from-queue" \
  "  its job is handed --after <predecessor>, to merge origin/main first"
qreset
enq keep --after "$BR-alpha2" > /dev/null 2>&1
enq keep > /dev/null
check "$(qget repo--keep after | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["branch"].rsplit("-",1)[-1])')" "alpha2" \
  "a later put naming no --after keeps the queued entry's (a retry never drops the dependency)"
enq bad --after main > /dev/null 2> "$T/err"; check "$?" "2" "--after main: refused (no claude/* branch)"
enq self --after "$BR-self" > /dev/null 2> "$T/err"; check "$?" "2" "--after its own branch: refused"
CLAUDE_UNATTENDED=dispatch enq unatt --after "$BR-alpha" > /dev/null 2>&1; check "$?" "0" "an unattended caller may pass --after: it only delays"

echo "the cards: a predecessor that will not land, or a step waiting past the bound — one each, the entry kept"
qreset
SG=$(pred gamma)
enq wait --after "$BR-gamma" > /dev/null
"${OG[@]}" push -q origin --delete "$BR-gamma"
python3 "$QB" claim "${QC[@]}" > /dev/null; python3 "$QB" claim "${QC[@]}" > /dev/null
check "$(grep -c '"card": "after-gone"' "$QL")" "1" "deleted unlanded: one after-gone card over two claims"
check "$(grep '"card": "after-gone"' "$QL" | python3 -c 'import json,sys; e=json.loads(sys.stdin.read()); import os; print(e["branch"].rsplit("-",1)[-1], e["after"].rsplit("-",1)[-1], os.path.realpath(e["repo"]) == os.path.realpath(sys.argv[1]))' "$T/repo")" \
  "wait gamma True" "  naming both branches and the repo"
check "$(qget repo--wait state)" "queued" "  the entry stays queued (could-not-tell holds)"
qreset
pred delta > /dev/null
enq late --after "$BR-delta" > /dev/null
DISPATCH_QUEUE_NOW=$(( $(date +%s) + 49 * 3600 )) python3 "$QB" claim "${QC[@]}" > /dev/null
check "$(grep -c '"card": "after-overdue"' "$QL")" "1" "waiting past 48 h on a predecessor: an after-overdue card"
cat > "$T/poll.py" <<'PY'
import importlib.util, sys, types
from importlib.machinery import SourceFileLoader
ld = SourceFileLoader("dq", sys.argv[1]); m = importlib.util.module_from_spec(importlib.util.spec_from_loader("dq", ld)); ld.exec_module(m)
calls = []
m._LANDED.append(types.SimpleNamespace(judge=lambda *a, **k: (calls.append(1), ("waiting", "not on origin/main yet", None))[1]))
e = {"repo": sys.argv[2], "branch": "claude/laptop/2026-10-29-p", "queued_at": m.now(),
     "after": [{"branch": "claude/laptop/2026-10-29-q", "seen": "", "work": False}]}
a = m.after_holds("fleet:p", e)
b = m.after_holds("fleet:p", e, cached=True)
c = m.after_holds("fleet:p", e)
print(len(calls), a == b == c, bool(a))
PY
check "$(python3 "$T/poll.py" "$QB" "$T/repo")" "2 True True" "the 60 s poll's claim reuses a hold judged within AFTER_RECHECK; every other claim judges again"

echo "the fired run: origin/main merged in first, a merge and never a rebase; a conflict is no start"
eval "$(sed -n '/^after_merge() {/,/^}/p' "$B/dispatch")"
git -C "$T/repo" fetch -q origin
git -C "$T/repo" worktree add -q "$T/wt" -b "$BR-next" origin/main 2>/dev/null
(cd "$T/wt" && echo n > f-next && git add -A && git commit -qm next)
pred epsilon > /dev/null; land epsilon
( here="$(dirname "$B")"; repo="$T/repo"; wt="$T/wt"; branch="$BR-next"; afters=("$BR-epsilon"); fromq="fleet:x"
  after_merge; echo "rc=$?"; after_merge; echo "rc=$?" ) > "$T/out" 2>&1
has "$T/out" "== --after: merged origin/main into $BR-next (a merge, never a rebase)" "a claimed run merges origin/main into its branch"
check "$(git -C "$T/wt" rev-list --parents -n1 HEAD | wc -w | tr -d ' ')" "3" "  a merge commit (two parents), its own commit kept"
has "$T/out" "holds origin/main already" "  again: nothing to merge"
"${OG[@]}" checkout -q -B main origin/main; echo main-side > "$T/other/f-next"; "${OG[@]}" add -A; "${OG[@]}" commit -qm clash; "${OG[@]}" push -q origin main
(cd "$T/wt" && echo branch-side > f-next && git commit -qam mine)
( here="$(dirname "$B")"; repo="$T/repo"; wt="$T/wt"; branch="$BR-next"; afters=("$BR-epsilon"); fromq="fleet:x"
  after_merge; echo "rc=$?" ) > "$T/out" 2>&1
has "$T/out" "FAILED: merging origin/main into $BR-next conflicts (--after); not running" "a conflicting merge: FAILED"
check "$([ -e "$(git -C "$T/wt" rev-parse --git-dir)/MERGE_HEAD" ] && echo merging || echo clean)" "clean" "  and aborted, the worktree as it was"
( here="$(dirname "$B")"; repo="$T/repo"; wt="$T/wt"; branch="$BR-next"; afters=("$BR-never"); fromq=""
  after_merge; echo "rc=$?" ) > "$T/out" 2>&1
has "$T/out" "FAILED: --after $BR-never has not landed" "a one-shot with no claim judges its predecessors at fire time"

echo "dispatch: --after's words, and a brief's After: line"
"$B/dispatch" "$BR-x" --repo "$T/repo" --after main --dry-run > /dev/null 2> "$T/err"; check "$?" "2" "--after main: refused"
has "$T/err" "--after takes a claude/* branch" "  said so"
"$B/dispatch" --start "/finish $BR-x" "$T/wt" "finish · x" --after "$BR-y" > /dev/null 2> "$T/err"; check "$?" "2" "--start takes no --after"
check "$(grep -c 'for b in ${afters\[@\]+"${afters\[@\]}"}; do' "$B/dispatch")" "3" "--after rides every road: the entry (queue_args), the peer's ssh line, the one-shot's plist"
"${OG[@]}" fetch -q origin; "${OG[@]}" checkout -q -B "$BR-briefed" origin/main
mkdir -p "$T/other/docs/handoff"; printf '# briefed\n\nAfter: %s\n\nBuild it.\n' "$BR-zeta" > "$T/other/docs/handoff/2026-10-29-briefed.md"
"${OG[@]}" add -A; "${OG[@]}" commit -qm "Seed: briefed"; "${OG[@]}" push -q origin "$BR-briefed"; "${OG[@]}" checkout -q --detach
git -C "$T/repo" fetch -q origin
mv "$REGATTA_CONFIG/wharf-runs/queue-repo" "$T/queue-repo.off"
"$B/dispatch" "$BR-briefed" --repo "$T/repo" --on here > "$T/out" 2> "$T/err"; check "$?" "2" "a brief's After: line is read as --after: with no queue home, an unlanded predecessor refuses"
has "$T/err" "--after $BR-zeta has not landed" "  naming the brief's predecessor"
has "$T/err" "the next step waits for a run to end" "  in the cap's waiting words"
mv "$T/queue-repo.off" "$REGATTA_CONFIG/wharf-runs/queue-repo"

echo "landings in the queue: dispatch --start's /finish with no room waits in queue-local/_land, above builds"
qreset
sleep 300 & W=$!
python3 "$QB" land --repo "$T/repo" --branch "$BR-ship" --topic finish-ship --pid "$W" "${QC[@]}" > "$T/out"; check "$?" "0" "land: a landing entry"
check "$(lget repo--ship kind host state waiter_pid)" "landing laptop queued $W" "  of kind landing, pinned here, naming its waiting process"
check "$(lget repo--ship args env)" "[] {}" "  and carrying nothing of its run: no flag, no environment"
enq hi --priority high > /dev/null; enq lo > /dev/null
python3 "$QB" list --json "${QC[@]}" > "$T/list"
check "$(python3 -c 'import json,sys; print(" ".join(e["topic"] for e in json.load(open(sys.argv[1]))["entries"] if e["state"] == "queued"))' "$T/list")" \
  "finish-ship hi lo" "  ranked above a high build and a normal one, by its kind"
fenq_dir="$HL/Caches/run-seed/force"; mkdir -p "$fenq_dir"; : > "$fenq_dir/s-suite"
CLAUDE_CODE_SESSION_ID=s-suite enq fo --priority force > /dev/null
python3 "$QB" list --json "${QC[@]}" > "$T/list"
check "$(python3 -c 'import json,sys; print([e["topic"] for e in json.load(open(sys.argv[1]))["entries"] if e["state"] == "queued"][:2])' "$T/list")" \
  "['fo', 'finish-ship']" "  below force, the owner's word for one run"
python3 "$QB" cancel --repo "$T/repo" --branch "$BR-fo" "${QC[@]}" > /dev/null
python3 "$QB" claim --cap 1 --launchctl "$T/launchctl" --prefix org.example.claude --jobbin "$B/dispatch" > "$T/out"
check "$(lget repo--ship state) $(qget repo--hi state) $(qget repo--lo state)" "claimed queued queued" "one free slot: the claim takes the landing, ahead of the builds"
check "$(ls "$LA" | grep -c finish-ship)" "0" "  and starts no job for it: its own dispatch --start runs it"
check "$(cat "$HL/Caches/run-seed/queue/claims/"*_land*.json | python3 "$T/qget.py" pid label)" "$W landing.$W" "  its reservation is held for that process"
python3 "$QB" land-wait "local=_land:repo--ship" --pid "$W" --for 2 "${QC[@]}" > /dev/null; check "$?" "0" "land-wait: 0 once this host claimed it for the process"
python3 "$QB" started "local=_land:repo--ship" --label "landing.$W" --session s-land "${QC[@]}" > /dev/null
check "$([ -e "$HL/Caches/run-seed/queue-local/_land/repo--ship.json" ] && echo kept || echo gone)" "gone" "started: its record holds the slot now, the entry goes"
kill "$W" 2>/dev/null; wait "$W" 2>/dev/null
sleep 300 & W=$!
python3 "$QB" land --repo "$T/repo" --branch "$BR-dead" --pid "$W" "${QC[@]}" > /dev/null
kill "$W" 2>/dev/null; wait "$W" 2>/dev/null
python3 "$QB" claim "${QC[@]}" > /dev/null
check "$([ -e "$HL/Caches/run-seed/queue-local/_land/repo--dead.json" ] && echo kept || echo gone)" "gone" "its dispatch --start gone: the claim takes the entry off, no slot claimed for nobody"
has "$QL" '"event": "landing-gone"' "  logged"
sleep 300 & W=$!
python3 "$QB" land --repo "$T/repo" --branch "$BR-waits" --pid "$W" "${QC[@]}" > /dev/null
( sleep 1; kill "$W" 2>/dev/null ) &
DISPATCH_LAND_POLL=0.2 python3 "$QB" land-wait "local=_land:repo--waits" --pid "$W" --for 20 "${QC[@]}" > /dev/null; check "$?" "3" "land-wait: 3 once its own process is gone (a TERM bash defers past it)"
{ wait "$W"; } 2>/dev/null
qreset
eval "$(sed -n '/^is_landing() {/,/^}/p' "$B/dispatch")"
eval "$(sed -n '/^land_queue() {/,/^}/p' "$B/dispatch")"
( branch="$BR-ship"; lprompt="/finish $BR-ship --unattended --dnd --merge --from=buildbox"; is_landing && echo yes || echo no
  lprompt="/finish $BR-other --unattended"; is_landing && echo yes || echo no
  lprompt="/finish $BR-ship"; is_landing && echo yes || echo no
  lprompt="/finish $BR-ship --unattended and then build all of it"; is_landing && echo yes || echo no
  lprompt="do something else"; is_landing && echo yes || echo no
  branch="main"; lprompt="/finish main --unattended"; is_landing && echo yes || echo no ) > "$T/out"
check "$(tr '\n' ' ' < "$T/out")" "yes no no no no no " "is_landing: autofinish-run's finish prompt for the worktree's own claude/* branch, word for word — no flag, no other text"
( here="$(dirname "$B")"; Q="$QB"; repo="$T/repo"; branch="$BR-ship"; topic="finish-ship"; max_runs=1; landq=""; lsid=s-land
  qctx=(--host laptop --cap 1 --launchctl "$T/launchctl" --prefix org.example.claude --jobbin "$B/dispatch")
  take_lock() { :; }; drop_lock() { :; }; qreserved() { echo 0; }
  ( sleep 2; python3 "$QB" claim --cap 1 --launchctl "$T/launchctl" --prefix org.example.claude --jobbin "$B/dispatch" > /dev/null ) &
  DISPATCH_LAND_POLL=0.3 land_queue "1 other runs are busy"; echo "rc=$? landq=$landq"; wait ) > "$T/out" 2>&1
has "$T/out" "queued as local=_land:repo--ship (a landing), session s-land, rank 1: 1 other runs are busy" "land_queue: the queued line autofinish-run reads, naming its session"
has "$T/out" "== the landing's claim: local=_land:repo--ship, a slot on this Mac" "  then the claim, the slot its own"
has "$T/out" "rc=0 landq=local=_land:repo--ship" "  returning with the start lock held, its queue id kept for the record's queue="

echo "autofinish-run: the queued verdict (night landings' finding 1, built on #281's)"
cat > "$T/af.py" <<'PY'
import importlib.util, io, sys, types
from importlib.machinery import SourceFileLoader
ld = SourceFileLoader("afr", sys.argv[1]); m = importlib.util.module_from_spec(importlib.util.spec_from_loader("afr", ld)); ld.exec_module(m)
p = sys.argv[2]
open(p, "w").write("== start\nqueued as local=_land:repo--ship (a landing), session other, rank 1: a sibling repo's landing of the topic\n")
print(m.log_verdict(p, 0, "abc"))
open(p, "a").write("queued as local=_land:repo--ship (a landing), session abc, rank 1: 3 other runs are busy — it starts at the first free slot\n")
print(m.log_verdict(p, 0, "abc")[0])
open(p, "a").write("== claude 123, session abc, screen s\n")
print(m.log_verdict(p, 0, "abc")[0])
t = types.SimpleNamespace(window="finish · ship")
out = io.StringIO(); old = sys.stdout; sys.stdout = out
rc = m.report_verdict(t, "queued", "queued as local=_land:repo--ship (a landing), session abc, rank 1: busy", 9, "state s; log l", "started: x")
sys.stdout = old
print(rc, out.getvalue().strip())
print(m.peer_verdict("abc", {"ticket": {"session": "abc", "rc": 0, "said": "queued on buildbox: local=_land:repo--ship (a landing)"}, "state": {}}))
PY
python3 "$T/af.py" "$B/autofinish-run" "$T/af.log" > "$T/out" 2>&1
check "$(sed -n 1,3p "$T/out" | tr '\n' ' ')" "None queued started " "log_verdict: a sibling's queued line is no verdict; this session's is queued; its later header, started"
has "$T/out" '0 queued: local=_land:repo--ship (a landing), rank 1: busy — window and Remote Control "finish · ship" once it starts; state s; log l' \
  "report_verdict: queued on stdout, exit 0 — every caller reads the landing as in hand"
has "$T/out" "('queued', 'local=_land:repo--ship (a landing)')" "peer_verdict: the peer's queued line, its prefix dropped"
check "$(grep -c 'refresh_lock(t.state_dir, sid, t.branch)' "$B/autofinish-run")" "2" "the waiter refreshes the worktree's lock while the queue holds the landing"

echo "the S9 landing review's cases"
cat > "$T/sticky.py" <<'PY'
import importlib.util, sys, types
from importlib.machinery import SourceFileLoader
ld = SourceFileLoader("dq", sys.argv[1]); m = importlib.util.module_from_spec(importlib.util.spec_from_loader("dq", ld)); ld.exec_module(m)
said = iter([("landed", "every file it changed read so on origin/main", None), ("waiting", "not on origin/main yet", None)])
calls = []
m._LANDED.append(types.SimpleNamespace(judge=lambda *a, **k: (calls.append(1), next(said))[1]))
e = {"id": "e1", "repo": sys.argv[2], "branch": "claude/laptop/2026-10-29-p", "queued_at": m.now(),
     "after": [{"branch": "claude/laptop/2026-10-29-q", "seen": "", "work": False}]}
print(m.after_holds("fleet:p", e), m.after_holds("fleet:p", e), len(calls))
PY
check "$(python3 "$T/sticky.py" "$QB" "$T/repo")" "None None 1" "a landed verdict is kept and never judged again (a later weaker read cannot unprove it)"
qreset
pred two-a > /dev/null; pred two-b > /dev/null
enq both --after "$BR-two-a" --after "$BR-two-b" > /dev/null
python3 "$QB" claim "${QC[@]}" > /dev/null; python3 "$QB" list "${QC[@]}" > "$T/out"
has "$T/out" "after $BR-two-a (waiting not on origin/main yet" "two predecessors: the row names the first's hold"
has "$T/out" "after $BR-two-b (waiting not on origin/main yet" "  and the second's, never \"proved\" for a branch that still holds"
qreset
sleep 300 & W=$!
python3 "$QB" land --repo "$T/repo" --branch "$BR-sib" --pid "$W" "${QC[@]}" > /dev/null
python3 "$QB" claim "${QC[@]}" > /dev/null
echo '{ torn' > "$HL/Caches/run-seed/queue-local/_land/zz-torn.json"
python3 "$QB" land-wait "local=_land:repo--sib" --pid "$W" --for 2 "${QC[@]}" > /dev/null; check "$?" "0" "land-wait reads its own file: a sibling's torn one is no 'gone'"
kill "$W" 2>/dev/null; { wait "$W"; } 2>/dev/null
rm -f "$HL/Caches/run-seed/queue-local/_land/zz-torn.json"
check "$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import cold_prompt as c; print(c.sent_to("queued on buildbox: local=_land:repo--x (a landing), rank 1"))' "$(dirname "$B")/hooks")" \
  "buildbox" "cold_prompt: a landing queued on the peer names the peer, whose Mac holds the window"
qreset
"${OG[@]}" fetch -q origin; "${OG[@]}" checkout -q -B "$BR-roads" origin/main
mkdir -p "$T/other/docs/handoff"; printf '# roads\n\n- **After:** %s, and %s.\n' "$BR-eta" "$BR-theta" > "$T/other/docs/handoff/2026-10-29-roads.md"
"${OG[@]}" add -A; "${OG[@]}" commit -qm "Seed: roads"; "${OG[@]}" push -q origin "$BR-roads"; "${OG[@]}" checkout -q --detach
git -C "$T/repo" fetch -q origin
"$B/dispatch" "$BR-roads" --repo "$T/repo" --on here > "$T/out" 2> "$T/err"; check "$?" "0" "the queue's road: a direct dispatch with a brief's After: line queues"
check "$(qget repo--roads after | python3 -c 'import json,sys; print(" ".join(a["branch"].rsplit("-",1)[-1] for a in json.load(sys.stdin)))')" "eta theta" \
  "  the entry carries both predecessors from the brief (queue_args), each claude/* name on the line"
"$B/dispatch" "$BR-roads" --repo "$T/repo" --on here --at "$(date -v+2d '+%Y-%m-%d') 10:00" --after "$BR-iota" --dry-run > "$T/out" 2> "$T/err"
has "$T/out" "<string>--after</string><string>$BR-iota</string>" "the one-shot's road: its plist carries --after"
has "$T/out" "<string>--after</string><string>$BR-eta</string>" "  the brief's predecessors too"

echo "the second landing review's cases"
# road 3, GitHub's word, through the LANDED_PRS stand-in: the combined landing pr merge never records for itself
SC=$(git -C "$T/repo" ls-remote origin "refs/heads/$BR-combined" | cut -f1)
printf '{"%s": [{"number": 9, "state": "closed", "merged_at": "2026-10-29T01:00:00Z", "head": {"ref": "%s", "sha": "%s"}, "base": {"ref": "main"}}]}\n' \
  "$BR-combined" "$BR-combined" "$SC" > "$T/prs.json"
rm -f "$T/repo/.git/claude/after-landed.json"
LANDED_PRS="$T/prs.json" judge combined > "$T/out"; check "$?" "0" "a combined rebase-merge, no record: GitHub's merged PR at its tip proves it (road 3)"
has "$T/out" "its PR #9 merged into main at ${SC:0:7}" "  saying so"
cat > "$T/road0.py" <<'PY'
import importlib.util, sys
from importlib.machinery import SourceFileLoader
ld = SourceFileLoader("landed", sys.argv[1]); m = importlib.util.module_from_spec(importlib.util.spec_from_loader("landed", ld)); ld.exec_module(m)
print(m.judge(sys.argv[2], sys.argv[3], fetch=False, github="cached")[0])
PY
check "$(python3 "$T/road0.py" "$L" "$T/repo" "$BR-combined")" "landed" "the proof is kept in the repo's after-landed.json: helm's no-fetch read proves it there (road 0)"
printf '{"%s": [{"number": 9, "state": "open", "head": {"ref": "%s", "sha": "%s"}, "base": {"ref": "main"}}]}\n' "$BR-open" "$BR-open" "$SC" > "$T/prs-open.json"
pred open f-open > /dev/null
LANDED_PRS="$T/prs-open.json" judge open > /dev/null; check "$?" "3" "a PR still open: no landing"
pred ghdown > /dev/null
"${OG[@]}" push -q origin --delete "$BR-ghdown"; git -C "$T/repo" fetch -q --prune origin 2>/dev/null
echo '{ not json' > "$T/prs-bad.json"
LANDED_PRS="$T/prs-bad.json" judge ghdown --seen deadbeef > "$T/out"; check "$?" "4" "its ref gone and GitHub not answering: could not tell, never gone (no card)"
# road 2's vacuous proofs refused: a record pr merge would write for a branch reset onto main
mkdir -p "$T/repo/.git/claude"; echo "$BR-reset $(git -C "$T/repo" ls-remote origin "refs/heads/$BR-reset" | cut -f1) via #8 2026-10-29" > "$T/repo/.git/claude/launched"
judge reset > /dev/null; check "$?" "4" "pr merge's record for a branch reset onto main: no landing (its own proof took \"merged\")"
rm -f "$T/repo/.git/claude/launched"
# the brief, which /finish removes, is no path of the proof
"${OG[@]}" fetch -q origin; "${OG[@]}" checkout -q -B "$BR-briefd" origin/main
mkdir -p "$T/other/docs/handoff"; echo brief > "$T/other/docs/handoff/2026-10-29-briefd.md"; echo work > "$T/other/f-briefd"
"${OG[@]}" add -A; "${OG[@]}" commit -qm "build briefd"; "${OG[@]}" push -q origin "$BR-briefd"
"${OG[@]}" checkout -q -B main origin/main; echo work > "$T/other/f-briefd"; "${OG[@]}" add -A; "${OG[@]}" commit -qm "briefd, finished"
"${OG[@]}" push -q origin main; "${OG[@]}" checkout -q --detach
judge briefd > /dev/null; check "$?" "0" "a tip still holding its brief: the brief is no path of the proof, its work is on main"
# a reflog fork at the branch's own work tip (dispatch's git branch … origin/<branch>) never drops earlier work
pred rf > /dev/null
git -C "$T/repo" fetch -q origin
git -C "$T/repo" branch -q --no-track "$BR-rf" "origin/$BR-rf"
git -C "$T/repo" worktree add -q "$T/wt-rf" "$BR-rf" 2>/dev/null
(cd "$T/wt-rf" && git checkout -q origin/main -- . && git rm -q f-rf && git commit -qm "take main's copy" && git push -q origin "$BR-rf")
judge rf > "$T/out"; check "$?" "3" "work taken back to main's copy on a branch dispatch created from origin/<branch>: no landing"
check "$(python3 "$QB" land-wait "local=_land:repo--none" --pid $$ --for 0 "${QC[@]}" > /dev/null 2>&1; echo $?)" "3" "land-wait with no entry: gone (3)"
sleep 300 & W=$!
python3 "$QB" land --repo "$T/repo" --branch "$BR-out" --pid "$W" "${QC[@]}" > /dev/null
DISPATCH_LAND_POLL=0.1 python3 "$QB" land-wait "local=_land:repo--out" --pid "$W" --for 0.3 "${QC[@]}" > /dev/null; check "$?" "6" "land-wait past --for: 6, never 1 (a crash's exit)"
kill "$W" 2>/dev/null; { wait "$W"; } 2>/dev/null

SX=$(pred moved f-moved); SX=${SX%%:*}
"${OG[@]}" checkout -q "$BR-moved"; echo more > "$T/other/f-moved2"; "${OG[@]}" add -A; "${OG[@]}" commit -qm "after the merge"; "${OG[@]}" push -q origin "$BR-moved"; "${OG[@]}" checkout -q --detach
printf '{"%s": [{"number": 11, "state": "closed", "merged_at": "%s", "head": {"ref": "%s", "sha": "%s"}, "base": {"ref": "main"}}]}\n' \
  "$BR-moved" "2026-01-01T00:00:00Z" "$BR-moved" "$SX" > "$T/prs-moved.json"
LANDED_PRS="$T/prs-moved.json" judge moved > /dev/null; check "$?" "3" "a merged PR, and work committed on the branch after it merged: no landing (road 3)"
printf '{"%s": [{"number": 11, "state": "closed", "merged_at": "%s", "head": {"ref": "%s", "sha": "%s"}, "base": {"ref": "main"}}]}\n' \
  "$BR-moved" "2099-01-01T00:00:00Z" "$BR-moved" "$SX" > "$T/prs-stale.json"
LANDED_PRS="$T/prs-stale.json" judge moved > /dev/null; check "$?" "3" "  a tip that descends from the PR's head, committed before it merged: work the PR never held, no landing"
# a copy from before /finish rewrote the branch: a sibling of the PR's head, never its descendant
SR=$(pred rewr f-rewr); SR=${SR%%:*}
"${OG[@]}" checkout -q "$BR-rewr"; "${OG[@]}" commit -q --amend -m "build rewr, curated"; SH=$("${OG[@]}" rev-parse HEAD)
"${OG[@]}" push -q origin "$SH:refs/pull/12/head"; "${OG[@]}" checkout -q --detach
printf '{"%s": [{"number": 12, "state": "closed", "merged_at": "%s", "head": {"ref": "%s", "sha": "%s"}, "base": {"ref": "main"}}]}\n' \
  "$BR-rewr" "2099-01-01T00:00:00Z" "$BR-rewr" "$SH" > "$T/prs-rewr.json"
LANDED_PRS="$T/prs-rewr.json" judge rewr > /dev/null; check "$?" "0" "  a tip committed before the PR merged, no descendant of its head (a copy from before /finish rewrote it): the PR stands"

echo "the third landing review's cases"
# road 1: a sighting whose work landed, while the branch went on with more work since
SD=$(pred desc f-desc); rebase_land desc
"${OG[@]}" checkout -q "$BR-desc"; echo more > "$T/other/f-desc2"; "${OG[@]}" add -A; "${OG[@]}" commit -qm "more"; "${OG[@]}" push -q origin "$BR-desc"; "${OG[@]}" checkout -q --detach
judge desc --sighting "$SD" > "$T/out"; check "$?" "3" "a sighting's work on main, the branch pushed again with more: no landing (road 1)"
has "$T/out" "waiting" "  waiting, as helm's read with no sighting says"
# road 3 with every ref gone: an older merged PR under the name, the sighting's work never in it
SG=$(pred gone3 f-gone3); git -C "$T/repo" fetch -q origin
"${OG[@]}" push -q origin --delete "$BR-gone3"; git -C "$T/repo" fetch -q --prune origin 2>/dev/null
MH=$(git -C "$T/repo" rev-parse origin/main)
printf '{"%s": [{"number": 13, "state": "closed", "merged_at": "%s", "head": {"ref": "%s", "sha": "%s"}, "base": {"ref": "main"}}]}\n' \
  "$BR-gone3" "2026-01-01T00:00:00Z" "$BR-gone3" "$MH" > "$T/prs-gone3.json"
LANDED_PRS="$T/prs-gone3.json" judge gone3 --seen "${SG%%:*}" --sighting "$SG" > "$T/out"; check "$?" "3" "every ref gone, an older merged PR under its name: the sighting's work holds it (road 3)"
has "$T/out" "gone" "  gone, as a deleted unlanded branch is"
# a fleet entry that says it is a landing is no landing: only this host's _land store holds one
qreset
enq fl > /dev/null
sleep 300 & W=$!
J=$("${QGIT[@]}" show "refs/regatta/queue:queue/repo--fl.json" | python3 -c 'import json,sys; d=json.load(sys.stdin); d.update(kind="landing", waiter_pid=int(sys.argv[1])); print(json.dumps(d))' "$W")
OLD=$("${QGIT[@]}" rev-parse refs/regatta/queue)
export GIT_INDEX_FILE="$T/qidx"; "${QGIT[@]}" read-tree "$OLD"
BL=$(printf '%s\n' "$J" | "${QGIT[@]}" hash-object -w --stdin)
"${QGIT[@]}" update-index --cacheinfo "100644,$BL,queue/repo--fl.json"
NT=$("${QGIT[@]}" write-tree); unset GIT_INDEX_FILE
"${QGIT[@]}" update-ref refs/regatta/queue "$("${QGIT[@]}" commit-tree "$NT" -p "$OLD" -m "a hand-written landing")"
check "$(qget repo--fl kind)" "landing" "  (the fleet entry now says kind landing)"
python3 "$QB" claim "${QC[@]}" > "$T/out"
check "$(qget repo--fl state)" "queued" "a fleet entry of kind landing: never claimed as one (no slot held for a live pid)"
check "$(cat "$HL/Caches/run-seed/queue/claims/"*.json 2>/dev/null | grep -c 'landing\.')" "0" "  no landing reservation"
kill "$W" 2>/dev/null; { wait "$W"; } 2>/dev/null

echo
[ "$fails" = 0 ] && echo "test_after: all passed" || { echo "test_after: $fails failed"; exit 1; }
