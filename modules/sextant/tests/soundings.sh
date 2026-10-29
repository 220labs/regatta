#!/usr/bin/env bash
# soundings: Sextant's sounding queue (the Sounding design's S7). Scratch dirs only: a pool of
# proposals, two repos (one `physical: none`, one not), a fake origin; no network, no model.
#   bash modules/sextant/tests/soundings.sh
set -u
D="$(cd "$(dirname "$0")/.." && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fails=0
check() { if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3: expected [$2] got [$1]"; fails=$((fails+1)); fi; }
has() { case "$1" in *"$2"*) echo "  ok   $3";; *) echo "  FAIL $3: missing [$2] in [$1]"; fails=$((fails+1));; esac; }
export SOUNDINGS_QUEUE="$T/pool/soundings.json" SOUNDINGS_PROPOSALS="$T/pool/proposals" SOUNDINGS_TODAY=2026-10-25
unset CLAUDE_UNATTENDED
S() { python3 "$D/bin/soundings" "$@"; }
mkdir -p "$T/pool/proposals"
prop() {  # prop <slug> <status> <repo or -> [no-launch]
  { printf -- '---\nstatus: %s\nupdated: 2026-10-20\n---\n# %s\n\n## Why\n- a reason\n\n' "$2" "$1"
    [ "${4:-}" = no-launch ] || { printf '## Launch test\n- gain: one page a week saved\n'; [ "$3" = - ] || printf -- '- repo: %s\n' "$3"; printf -- '- first step: a worker writes the page\n\n'; }
    printf '## Log\n- 2026-10-20 created\n'; } > "$T/pool/proposals/$1.md"
}
mkrepo() {  # mkrepo <dir> <physical>
  git init -q -b main "$1"; printf -- '- physical: %s\n' "$2" > "$1/AGENTS.md"
  git -C "$1" add . && git -C "$1" -c user.name=t -c user.email=t@t commit -qm init
  git init -q --bare "$1.git"; git -C "$1" remote add origin "$1.git"; git -C "$1" push -q origin main
}
mkrepo "$T/calm" none; mkrepo "$T/live" desk
for s in a b c d e f; do prop "$s" ready "$T/calm"; done
prop nolaunch ready "$T/calm" no-launch; prop norepo ready -; prop seed seed "$T/calm"; prop phys ready "$T/live"

echo "add — the owner's pick"
out=$(CLAUDE_UNATTENDED=dispatch S add a 2>&1); check $? 1 "an unattended caller cannot queue (nothing queued unasked)"
has "$out" "nothing is queued unasked" "  and says why"
[ ! -f "$SOUNDINGS_QUEUE" ]; check $? 0 "  nothing written"
S add a >/dev/null; check $? 0 "the owner queues a"
check "$(python3 -c 'import json,sys; e=json.load(open(sys.argv[1]))["entries"][0]; print(e["slug"], e["state"], e["added"])' "$SOUNDINGS_QUEUE")" "a queued 2026-10-25" "  queued, dated"
S add a >/dev/null 2>&1; check $? 1 "a second add of a queued entry is refused"
S add nosuch >/dev/null 2>&1; check $? 1 "a proposal that does not exist is refused"
S add ../x >/dev/null 2>&1; check $? 1 "a slug that is not one is refused (no path out of proposals/)"
out=$(S add seed); has "$out" "held until it clears: the proposal is \`status: seed\`, not ready" "a seed can be queued, held, and says why"
for s in nolaunch norepo phys b c d e f; do S add "$s" >/dev/null; done
S add --branch x a >/dev/null 2>&1; check $? 2 "--branch without --now is a usage error"

echo "next — the gates, the caps, the stagger"
j=$(S next --json)
py() { printf '%s' "$j" | python3 -c "import json,sys; d=json.load(sys.stdin); print($1)"; }
check "$(py "d['room']")" 3 "nothing dispatched or open: room for three this week"
check "$(py "' '.join(o['slug'] for o in d['dispatch'])")" "a b c" "the three oldest that clear the gates, in the order queued"
check "$(py "' '.join(o['at'] for o in d['dispatch'])")" "reset reset+30 reset+60" "staggered at the reset, never further ahead"
check "$(py "d['dispatch'][0]['topic']")" "sounding-a" "the topic is sounding-<slug>"
has "$(py "d['dispatch'][0]['commands'][2]")" "--at reset --if-room" "dispatch carries --if-room: the week is read at fire time"
held=$(py "'|'.join(h['slug'] + ': ' + h['why'] for h in d['held'])")
has "$held" "nolaunch: the proposal has no \`## Launch test\` section" "held: no Launch test"
has "$held" "norepo: its Launch test names no \`repo:\`" "held: no repo"
has "$held" "seed: the proposal is \`status: seed\`, not ready" "held: not ready"
has "$held" "phys: $T/live's contract must say \`physical: none\` (it says: - physical: desk)" "held: a repo that is not physical: none"
has "$held" "d: the caps: 3 of 3 dispatched" "held: past the week's three"

echo "brief — the seeded run's brief"
f=$(S brief a --out "$T/brief.md"); check "$f" "$T/brief.md" "brief prints the file it wrote"
grep -q '^Task: sound the proposal `a`' "$T/brief.md"; check $? 0 "  a Task: line (pickup seed requires one)"
grep -q '^> - gain: one page a week saved' "$T/brief.md"; check $? 0 "  the Launch test quoted"
grep -q 'ask relay <doc> D1' "$T/brief.md"; check $? 0 "  asks through ask relay (the standing manager)"
grep -q 'Build: full · light chain' "$T/brief.md"; check $? 0 "  the Build D1"
check "$([ "$(wc -l < "$T/brief.md")" -le 60 ] && [ "$(wc -c < "$T/brief.md")" -le 4000 ] && echo fits)" fits "  within pickup seed's 60 lines / 4,000 characters"
S brief nolaunch --out "$T/x.md" >/dev/null 2>&1; check $? 1 "no Launch test: no brief"

echo "mark — scheduled, and the counts"
S mark a scheduled --branch claude/h/2026-10-25-sounding-a >/dev/null 2>&1; check $? 1 "scheduled needs --at too"
S mark a scheduled --branch claude/h/2026-10-25-sounding-a --at reset --repo "$T/calm" >/dev/null; check $? 0 "a scheduled"
S mark a scheduled --branch x --at reset >/dev/null 2>&1; check $? 1 "  only a queued entry is scheduled"
S mark b scheduled --branch claude/h/2026-10-25-sounding-b --at reset+30 --repo "$T/calm" >/dev/null
j=$(S next --json)
check "$(py "d['week'], d['open'], d['room']")" "2 2 1" "two dispatched, two open: room for one"
check "$(py "d['dispatch'][0]['slug'], d['dispatch'][0]['at']")" "c reset+60" "  the third slot goes to the next queued"
S mark nosuch done >/dev/null 2>&1; check $? 1 "mark refuses an entry not queued"
S mark c bogus >/dev/null 2>&1; check $? 1 "mark refuses a state it does not know"
CLAUDE_UNATTENDED=dispatch S mark c launched >/dev/null 2>&1; check $? 1 "an unattended run cannot record a launch now"
out=$(WEEKLY_RUN=sextant S add d 2>&1); check $? 1 "the weekly job cannot queue either (WEEKLY_RUN, weekly-run's own mark)"
has "$out" "WEEKLY_RUN=sextant" "  naming which mark refused it"
WEEKLY_RUN=sextant S mark c launched >/dev/null 2>&1; check $? 1 "  nor record a launch now"

echo "the five open, earlier weeks counted"
prop h ready "$T/calm"; prop i ready "$T/calm"
# i's branch holds a commit main lacks: a sounding launched by hand and still with the owner
git -C "$T/calm" checkout -q -b claude/h/i && echo i > "$T/calm/i.md" && git -C "$T/calm" add i.md \
  && git -C "$T/calm" -c user.name=t -c user.email=t@t commit -qm i && git -C "$T/calm" checkout -q main
S add h --now >/dev/null; S add i --now --branch claude/h/i --repo "$T/calm" >/dev/null
check "$(python3 -c 'import json,sys; print([e["state"] for e in json.load(open(sys.argv[1]))["entries"] if e["slug"] in "hi"])' "$SOUNDINGS_QUEUE")" "['launched', 'launched']" "launch now is recorded as launched"
j=$(SOUNDINGS_TODAY=2026-11-08 S next --json)
check "$(py "d['week'], d['open'], d['room']")" "0 4 1" "two weeks on: the week is fresh, four still open: room for one"
S mark c scheduled --branch claude/h/c --at reset --repo "$T/calm" >/dev/null
j=$(S next --json)
check "$(py "d['open'], d['room']")" "5 0" "five open: no room, whatever the week"
has "$(py "' '.join(h['why'] for h in d['held'])")" "5 of 5 open" "  the held ones name the cap"

echo "refresh — a branch on main, a parked proposal"
git -C "$T/calm" checkout -q -b claude/h/2026-10-25-sounding-a && echo x > "$T/calm/doc.md" && git -C "$T/calm" add doc.md \
  && git -C "$T/calm" -c user.name=t -c user.email=t@t commit -qm doc && git -C "$T/calm" push -q origin claude/h/2026-10-25-sounding-a
git -C "$T/calm" checkout -q main
out=$(S refresh); case "$out" in *"a: done"*) check "a done" "a open" "a's branch is pushed, not on main: still open";; *) echo "  ok   a's branch is pushed, not on main: still open";; esac
has "$out" "b: done" "b's branch is neither on origin nor here: launched and reaped, done"
git -C "$T/calm" merge -q --ff-only claude/h/2026-10-25-sounding-a && git -C "$T/calm" push -q origin main && git -C "$T/calm" fetch -q origin
out=$(S refresh); has "$out" "a: done" "a's branch reached main: done"
sed -i.bak 's/^status: ready/status: parked/' "$T/pool/proposals/f.md" && rm -f "$T/pool/proposals/f.md.bak"
out=$(S refresh); has "$out" "f: parked" "a parked proposal (disproved) parks its queued entry"
check "$(python3 -c 'import json,sys; print(len([e for e in json.load(open(sys.argv[1]))["entries"] if e["state"] in ("scheduled","launched")]))' "$SOUNDINGS_QUEUE")" 2 "two still open after the refresh: h (no branch to read) and i (its branch off main)"

echo "refresh — a rebase-merged landing, a squash, a run that never started (the S7 /finish review)"
export SOUNDINGS_QUEUE="$T/pool/q2.json"
for x in j k l m; do prop "$x" ready "$T/calm"; S add "$x" >/dev/null; done
gc() { git -C "$T/calm" -c user.name=t -c user.email=t@t "$@"; }
up() { git -C "$T/calm" push -q origin "$1"; }
# j: one commit, landed by rebase onto a main that moved — a new sha, no ancestor
git -C "$T/calm" checkout -q -b claude/h/j main && echo j > "$T/calm/j.md" && git -C "$T/calm" add j.md && gc commit -qm "Docs: j" && up claude/h/j
git -C "$T/calm" checkout -q main && echo moved > "$T/calm/moved.md" && git -C "$T/calm" add moved.md && gc commit -qm moved
gc cherry-pick claude/h/j >/dev/null && up main && git -C "$T/calm" fetch -q origin
# k: two commits, landed as one squash (cherry finds neither; the files match)
git -C "$T/calm" checkout -q -b claude/h/k main~2 && echo k1 > "$T/calm/k.md" && git -C "$T/calm" add k.md && gc commit -qm k1 \
  && echo k2 > "$T/calm/k.md" && gc commit -qam k2 && up claude/h/k
git -C "$T/calm" checkout -q main && echo k2 > "$T/calm/k.md" && git -C "$T/calm" add k.md && gc commit -qm "Docs: k" \
  && up main && git -C "$T/calm" fetch -q origin
# l: a seed only, never started; m: a seed with a run's commit after it
for x in l m; do
  git -C "$T/calm" checkout -q -b "claude/h/$x" main && mkdir -p "$T/calm/docs/handoff" && echo brief > "$T/calm/docs/handoff/$x.md" \
    && git -C "$T/calm" add docs/handoff && gc commit -qm "Seed: sounding-$x" && up "claude/h/$x"
done
echo run > "$T/calm/m-run.md" && git -C "$T/calm" add m-run.md && gc commit -qm "Checkpoint: m" && up claude/h/m
git -C "$T/calm" checkout -q main
for x in j k l m; do S mark "$x" scheduled --branch "claude/h/$x" --at reset --repo "$T/calm" >/dev/null; done
out=$(SOUNDINGS_TODAY=2026-11-01 S refresh)
has "$out" "j: done" "a branch landed by rebase (a new sha on main) is done"
has "$out" "k: done" "  and one landed as a squash (every changed file the same on main)"
case "$out" in *"l: queued"*) check "l requeued at 7 days" "l held" "a seed only, seven days on: still scheduled (the reset may be today)";; *) echo "  ok   a seed only, seven days on: still scheduled (the reset may be today)";; esac
printf '#!/bin/sh\nexit 3\n' > "$T/dq-has"; chmod +x "$T/dq-has"
out=$(SOUNDINGS_TODAY=2026-11-02 SOUNDINGS_DISPATCH_QUEUE="$T/dq-has" S refresh)
case "$out" in *"l: queued"*) check "l requeued" "l held" "  eight days on, but dispatch's queue holds it (queued at fire time, dispatch-queue S3): still scheduled";; *) echo "  ok   eight days on, but dispatch's queue holds it (queued at fire time, dispatch-queue S3): still scheduled";; esac
printf '#!/bin/sh\nexit 5\n' > "$T/dq-crash"; chmod +x "$T/dq-crash"
out=$(SOUNDINGS_TODAY=2026-11-02 SOUNDINGS_DISPATCH_QUEUE="$T/dq-crash" S refresh)
case "$out" in *"l: queued"*) check "l requeued on a crash" "l held" "  a queue that crashed (exit 5) holds it too, never read as no entry (S3's landing review, item 5)";; *) echo "  ok   a queue that crashed (exit 5) holds it too, never read as no entry (S3's landing review, item 5)";; esac
printf '#!/bin/sh\nexit 0\n' > "$T/dq-none"; chmod +x "$T/dq-none"
out=$(SOUNDINGS_TODAY=2026-11-02 SOUNDINGS_DISPATCH_QUEUE="$T/dq-none" S refresh)
has "$out" "l: queued" "  eight days on, still a seed and in no queue: back to queued (refused at fire time, or never fired)"
case "$out" in *"m: "*) check "m changed" "m scheduled" "a seed with a run's commit after it stays scheduled";; *) echo "  ok   a seed with a run's commit after it stays scheduled";; esac
j=$(SOUNDINGS_TODAY=2026-11-02 S next --json)
check "$(py "[o['commands'][0] for o in d['dispatch'] if o['slug'] == 'l']")" "['dispatch claude/h/l --repo $T/calm --at reset --if-room']" "  next dispatches its branch again, no second seed"
S mark m queued >/dev/null; check $? 0 "mark queued returns a scheduled entry by hand"
check "$(python3 -c 'import json,sys; e=[e for e in json.load(open(sys.argv[1]))["entries"] if e["slug"]=="m"][0]; print(e["state"], e["branch"], e["at"], e["scheduled"])' "$SOUNDINGS_QUEUE")" "queued claude/h/m None None" "  its branch kept, its slot and date cleared"
S mark m queued >/dev/null 2>&1; check $? 1 "  only a scheduled entry goes back"
git -C "$T/calm" checkout -q -b claude/h/n main && echo n > "$T/calm/n.md" && git -C "$T/calm" add n.md && gc commit -qm n && git -C "$T/calm" checkout -q main
check "$(python3 - "$D/bin/soundings" "$T/calm" <<'PY'
import sys
from importlib.machinery import SourceFileLoader
print(SourceFileLoader("soundings", sys.argv[1]).load_module().merged(sys.argv[2], "claude/h/n"))
PY
)" False "a branch whose commit main lacks is not merged (no proof holds)"
# o: its one path is non-ASCII, which git C-quotes without -z; ls-tree then found it on neither side (F2)
git -C "$T/calm" checkout -q -b claude/h/o main && echo o > "$T/calm/doc-é.md" && git -C "$T/calm" add . && gc commit -qm o && git -C "$T/calm" checkout -q main
check "$(python3 - "$D/bin/soundings" "$T/calm" <<'PY'
import sys
from importlib.machinery import SourceFileLoader
print(SourceFileLoader("soundings", sys.argv[1]).load_module().merged(sys.argv[2], "claude/h/o"))
PY
)" False "  nor one whose only path git quotes (a non-ASCII name; the S7 /finish review's F2)"
export SOUNDINGS_QUEUE="$T/pool/soundings.json"

echo "the pool through Sparks' config"
mkdir -p "$T/notes/proposals" "$T/cfg/sextant"; cp "$T/pool/proposals/e.md" "$T/notes/proposals/"
printf '{"split": "topics", "notes": "%s"}\n' "$T/notes" > "$T/cfg/sextant/sparks.json"
out=$(env -u SOUNDINGS_QUEUE -u SOUNDINGS_PROPOSALS SPARKS_CONFIG="$T/cfg/sextant/sparks.json" python3 "$D/bin/soundings" add e 2>&1); check $? 0 "the queue is found beside Sparks' pool"
[ -f "$T/notes/soundings.json" ]; check $? 0 "  soundings.json in the pool's folder"
out=$(env -u SOUNDINGS_QUEUE -u SOUNDINGS_PROPOSALS SPARKS_CONFIG="$T/none.json" python3 "$D/bin/soundings" list 2>&1); check $? 1 "no pool configured: refused, said"
has "$out" "no ideas pool" "  naming what is missing"
echo '{broken' > "$T/bad.json"
SOUNDINGS_QUEUE="$T/bad.json" S list >/dev/null 2>&1; check $? 1 "an unreadable queue is refused, never overwritten"
check "$(cat "$T/bad.json")" "{broken" "  left as it was"

echo "G27: the launch's peers absent — the owner's line, never a stack trace"
# From a copy of the core and this module alone (AGENTS.md's "peer absent" trap: common.tool() searches
# modules/*/ first, so the checkout's own wharf-runs and keel would be found).
NP="$T/np"; mkdir -p "$NP/.claude-plugin" "$NP/modules" "$T/np-cfg" "$T/np-cc"
cp "$D/../../.claude-plugin/marketplace.json" "$NP/.claude-plugin/"
cp -R "$D/../regatta" "$D" "$NP/modules/"; rm -rf "$NP/modules/sextant/.git"
export SOUNDINGS_QUEUE="$T/g27.json"
prop g ready "$T/calm"; S add g >/dev/null
npS() { env -u REGATTA_HOME -u REGATTA_LEGACY -u SOUNDINGS_BY_HAND REGATTA_CONFIG="$T/np-cfg" CLAUDE_CONFIG_DIR="$T/np-cc" \
          python3 "$NP/modules/sextant/bin/soundings" "$@" 2>&1; }
out=$(npS next); check $? 0 "next exits 0 with pickup, dispatch and keel absent"
check "$(printf '%s\n' "$out" | grep -c '^by hand g: ')" 1 "  one line for the candidate"
has "$out" "pickup (wharf-runs), dispatch (wharf-runs), keel (keel) are not installed" "  naming each absent peer and its module"
has "$out" "the owner types: /sounding $T/pool/proposals/g.md, then soundings mark g launched --branch <its branch> --repo $T/calm" "  and the line the owner would type"
check "$(printf '%s\n' "$out" | grep -cE 'Traceback|pickup seed|^dispatch ')" 0 "  no stack trace, no command it could not run"
check "$(npS next --json | python3 -c 'import json,sys; o=json.load(sys.stdin)["dispatch"][0]; print(o["commands"], "by_hand" in o)')" "[] True" "  --json: no commands, a by_hand line"
out=$(SOUNDINGS_BY_HAND="sextant's own runner schedules nothing" S next)
has "$out" "by hand g: sextant's own runner schedules nothing — the owner types: /sounding" "SOUNDINGS_BY_HAND (the own runner): the same line, the peers present or not"
python3 -c 'import json,sys; f=sys.argv[1]; d=json.load(open(f)); d["entries"][0]["branch"]="claude/x/sounding-g"; json.dump(d, open(f, "w"))' "$T/g27.json"
out=$(npS next)
has "$out" "the owner starts the seed claude/x/sounding-g in $T/calm (pickup), then soundings mark g launched --branch claude/x/sounding-g" "a seeded entry: its seed named, never a second /sounding"
check "$(printf '%s\n' "$out" | grep -c '/sounding ')" 0 "  no fresh /sounding line"
python3 -c 'import json,sys; f=sys.argv[1]; d=json.load(open(f)); d["entries"][0].pop("branch"); json.dump(d, open(f, "w"))' "$T/g27.json"
if python3 "$D/../regatta/bin/regatta" which pickup >/dev/null 2>&1 && python3 "$D/../regatta/bin/regatta" which keel >/dev/null 2>&1; then
  out=$(env -u SOUNDINGS_BY_HAND python3 "$D/bin/soundings" next)
  has "$out" "pickup seed sounding-g --file" "the peers present (this checkout): the commands, as before"
else echo "  skip  the peers are not in this checkout (an install of sextant without keel and wharf-runs)"; fi
export SOUNDINGS_QUEUE="$T/pool/soundings.json"

echo; [ "$fails" = 0 ] && echo "soundings: all passed" || { echo "soundings: $fails FAILED"; exit 1; }
