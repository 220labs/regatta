#!/usr/bin/env bash
# Tests for bin/autofinish --dry-run — a scratch HOME with three workflow repos on bare origins
# (records mode by default, "small", and a vault-style one with no key), one worktree per
# veto and per start rule, fixture transcripts and a live-session registry, a GitHub fixture in
# place of the API, a stub bin/memo, and a pinned clock. No network, nothing started.
#   bash modules/wharf-runs/tests/test_autofinish.sh
# Load-proof since 2026-10-14: every file the idle clock reads (last-reply, transcript, prompts.json)
# and every `mk` commit is aged from the pinned NOW, never left at the real time it was made; the
# other fixture commits stay on real time, read only where a case has no transcript. Before, a fixture made after minute 20 read under
# 40 min idle and `wait`ed (32 cases on every busy run, 2026-10-11, 2026-10-14), and widening the
# clock's lead to two hours (main, 2026-10-14) only moved the cliff: a run took 86 min at load 90.
# TEST_AUTOFINISH_LEAD=0 (the clock's lead over the real start, default 3600 s) proves it: any
# fixture still on real time reads idle 0 there.
set -u
B="$(cd "$(dirname "$0")/../bin" && pwd)"   # the module's bin/ (B7: the suites moved to tests/)
# the regatta core's hooks/ (common.py), found as the tools find it (lib/core_path.py); wharf's peers by its tool()
CORE="$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import core_path; print(core_path.hooks() or "")' "$B/../lib")"
[ -n "$CORE" ] || { echo "FAIL: the regatta core is missing"; exit 1; }
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
fails=0
# BSD and GNU sed disagree on `-i ''` (GNU takes '' as the script and the real script as a file name); `-i.bak` and a rm work on both.
sedi() { local f="${!#}"; sed -i.bak "$@" && rm -f "$f.bak"; }
# BSD date -r <epoch>; GNU date -d @<epoch>. Each fails cleanly on the other.
dateat() { date -r "$1" "$2" 2>/dev/null || date -d "@$1" "$2"; }
check() { if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3: expected [$2] got [$1]"; fails=$((fails+1)); fi; }
has()   { if grep -qF -- "$2" "$1"; then echo "  ok   $3"; else echo "  FAIL $3: missing [$2]"; sed 's/^/         | /' "$1" | head -60; fails=$((fails+1)); fi; }
hasnt() { if grep -qF -- "$2" "$1"; then echo "  FAIL $3: unexpected [$2]"; fails=$((fails+1)); else echo "  ok   $3"; fi; }

. "$(cd "$(dirname "$0")" && pwd)/config_fixture.sh"; fixture_config "$T/config"   # the suite's own config dir, never the login's (config_fixture.sh)
export HOME="$T/home" GIT_CONFIG_NOSYSTEM=1
# the suite runs inside Claude sessions and dispatch runs: their markers gate `arm` and `override`
unset CLAUDECODE CLAUDE_UNATTENDED
# Since E1 is wired, start_runner starts a real claude session: no test may reach it. Every
# case runs against this recording stub unless it names its own.
printf '#!/bin/sh\necho "$1 $2" >> "%s"\n' "$T/default-runner.calls" > "$T/default-runner"; chmod +x "$T/default-runner"
export AUTOFINISH_RUNNER="$T/default-runner"
mkdir -p "$HOME/.claude/projects/fixture" "$HOME/.claude/sessions" "$T/projects"
git config --global user.name Test; git config --global user.email t@example.invalid
git config --global init.defaultBranch main; git config --global advice.detachedHead false
unset CLAUDE_CONFIG_DIR CLAUDE_CODE_OAUTH_TOKEN GH_TOKEN GITHUB_TOKEN CLAUDE_TIER_NOW ACCOUNTS_FILE ACCOUNT_NOW AUTOFINISH_ACCOUNT
export ACCOUNTS_FILE="$T/no-accounts.json"   # no registry unless a case names one: the default is the config dir's lighthouse/accounts.json, the real one (B9)
# The clock is pinned an hour ahead, and the fixture makers (mk, reply, queue) age what they make
# to NOW - 60 min, so everything made below reads 60 min idle however long the suite has run,
# unless a case ages its own files; tier_check reads the same clock (autofinish passes it on).
# Keep the lead under 7200: the arm sits at NOW - 2 h (the arm cases below), and the newsmall and
# oldrepo commits, made at real time, must fall after it.
NOW=$(( $(date +%s) + ${TEST_AUTOFINISH_LEAD:-3600} ))
MADE="$((NOW - 3600)) +0000"  # a fixture commit's date: the idle clock's last fallback is the tip's
echo '{}' > "$T/claude-normal.json"
python3 - "$T/tier-tight.json" "$NOW" <<'EOF'
import datetime, json, sys
now = int(sys.argv[2])
reset = datetime.datetime.fromtimestamp(now + 3 * 86400, datetime.timezone.utc).isoformat()
json.dump({"cachedUsageUtilization": {"fetchedAtMs": now * 1000, "utilization": {"limits": [
    {"kind": "weekly_all", "percent": 85, "resets_at": reset}]}}}, open(sys.argv[1], "w"))
EOF
cat > "$T/memo" <<EOF
#!/bin/sh
# stub bin/memo, every call logged: \`memo status --json [--no-fetch] <doc>\`, the E10 contract —
# \`stood\` once a commit on the doc carries the trailer, else the doc's name picks the verdict —
# and \`memo stand --apply <doc>\`, which commits that trailer as bin/memo does (a *fail* doc fails)
if [ "\$1" = landing ]; then  # \`keel landing\` (entry S7), unlogged: the calls log is status and stand
  f=\$(grep -l '^Steps: ' docs/handoff/*.md 2>/dev/null | head -1)
  [ -n "\$f" ] && { echo "open step: \$f names docs/course.md S2 — not started"; exit 1; }
  echo "landing: no brief on this branch names an open step"; exit 0
fi
for a; do doc=\$a; done
echo "\$*" >> "$T/memo.calls"
if [ "\$1" = stand ]; then
  case "\$doc" in *fail*) echo "memo: replies written but not committed" >&2; exit 1;; esac
  printf '\n  > **Applied.** Stood: no objection — A\n' >> "\$doc"
  git commit -q -m "Memo: \$doc stood" -m "Stood-By: autofinish" -- "\$doc"; exit \$?
fi
if [ -n "\$(git log -1 --format=%h --fixed-strings --grep='Stood-By: autofinish' -- "\$doc")" ]; then
  echo '{"verdict": "stood", "deadline": "2026-10-04T09:00:00+02:00"}'; exit 0
fi
case "\$doc" in
  *partstood*)       echo '{"verdict": "part-stood", "reason": "stood (abc1234); 1 still open: D2 Reversible: no"}';;
  *halfdue*)         echo '{"verdict": "due", "deadline": "2026-10-04T09:00:00+02:00", "unstandable": [["D2", "unmarked"]]}';;
  *due*)             echo '{"verdict": "due", "deadline": "2026-10-04T09:00:00+02:00"}';;
  *stands*|*my\ doc*) echo '{"verdict": "stands-at", "deadline": "2026-10-06T09:00:00+02:00"}';;
  *answered*)        echo '{"verdict": "answered", "deadline": "2026-10-04T09:00:00+02:00"}';;
  *taken*)           echo '{"verdict": "taken", "deadline": null}';;
  *stood*)           echo '{"verdict": "stood", "deadline": "2026-10-04T09:00:00+02:00"}';;
  *)                 echo "memo: no such verdict" >&2; exit 1;;
esac
EOF
chmod +x "$T/memo"
cat > "$T/repos.json" <<'EOF'
{"repos": {"demo": {}, "smallrepo": {}, "personal": {}, "nocheck": {}, "absent": {}}}
EOF
export AUTOFINISH_NOW=$NOW AUTOFINISH_HOST=laptop AUTOFINISH_REPOS="$T/repos.json" \
       AUTOFINISH_PROJECTS="$T/projects" AUTOFINISH_MEMO="$T/memo" AUTOFINISH_GITHUB="$T/gh.json" \
       AUTOFINISH_LOG_DIR="$T/logs" CLAUDE_TIER_CLAUDE_JSON="$T/claude-normal.json" \
       CLAUDE_TIER_APP_HISTORY="$T/no-app-history.json"

# newrepo <name> <workflow.json>: a primary on main, pushed to a bare origin
newrepo() {
  git init -q --bare "$T/origin-$1.git"
  mkdir -p "$T/projects/$1/.claude/" && cd "$T/projects/$1" || exit 1
  git init -q . && echo "$2" > .claude/workflow.json
  mkdir -p docs && echo "# existing" > docs/existing.md && printf '.claude/worktrees/\n' > .gitignore
  git add -A && git commit -qm init && git remote add origin "$T/origin-$1.git" && git push -q origin main
}
sid()  { echo "$(printf %s "$1" | shasum | cut -c1-8)-0000-4000-8000-000000000000"; }
br()   { echo "claude/laptop/2026-10-05-$1"; }
wtp()  { echo "$T/projects/$1/.claude/worktrees/$2"; }
gd()   { git -C "$(wtp "$1" "$2")" rev-parse --absolute-git-dir; }
ago()  { python3 -c 'import os,sys;t=float(sys.argv[2])-60*float(sys.argv[3]);os.utime(sys.argv[1],(t,t))' "$1" "$NOW" "$2"; }
# reply <topic> <text> [sid]: the owning session's transcript, ending in that reply, aged 60 min
# as `ago` would, in the same python3 (one start, not two: mk calls it 147 times)
reply() {
  python3 - "$HOME/.claude/projects/fixture/${3:-$(sid "$1")}.jsonl" "$2" "$NOW" <<'EOF'
import json, os, sys
with open(sys.argv[1], "w") as f:
    f.write(json.dumps({"type": "user", "message": {"role": "user", "content": "go on"}}) + "\n")
    f.write(json.dumps({"type": "assistant", "message": {"role": "assistant", "content": [
        {"type": "text", "text": sys.argv[2]}]}}) + "\n")
t = float(sys.argv[3]) - 60 * 60
os.utime(sys.argv[1], (t, t))
EOF
}
# mk <repo> <topic> <file> <content> [message body]: a worktree with one checkpoint-shaped
# commit, pushed, its lock naming its session, and that session's transcript ending in a plain
# reply. `nopush` as a sixth argument leaves it on this machine only. The setup's bulk (147
# calls), so each value is computed once: the session id and the git dir (read back from git).
mk() {
  local r=$1 t=$2 wt s g b; wt=$(wtp "$1" "$2"); s=$(sid "$t"); b=$(br "$t")
  git -C "$T/projects/$r" worktree add -q "$wt" -b "$b" main
  case $3 in */*) mkdir -p "$wt/${3%/*}";; esac
  printf '%s\n' "$4" > "$wt/$3"
  git -C "$wt" add -A && GIT_COMMITTER_DATE="$MADE" GIT_AUTHOR_DATE="$MADE" git -C "$wt" commit -qm "Work: $t" -m "${5:-Deployed: no}" -m "Claude-Session: ${s:0:8}"
  [ "${6:-}" = nopush ] || git -C "$wt" push -q -u origin "$b"
  g=$(git -C "$wt" rev-parse --absolute-git-dir); mkdir -p "$g/claude"
  echo "{\"session\": \"$s\", \"branch\": \"$b\", \"seen\": 0}" > "$g/claude/owner.json"
  reply "$t" "Done: the change is committed and pushed." "$s"
  echo "$b WIP 0" >> "$T/gh.lines"
}
gh() { echo "$(br "$1") $2 $3" >> "$T/gh.lines"; }  # gh <topic> WIP|ready|none <activity>
ghjson() {
  python3 - "$T/gh.lines" "$T/gh.json" <<'EOF'
import json, sys
out, n = {}, 0
for line in open(sys.argv[1]):
    b, title, act = line.split()
    n += 1
    out[b] = {"pr": None if title == "none" else
              {"number": n, "title": ("WIP: " if title == "WIP" else "") + b.rsplit("-", 1)[-1], "draft": title == "WIP"},
              "activity": int(act)}
json.dump(out, open(sys.argv[2], "w"))
EOF
}
session() { # session <topic> <status> [cwd]: a live registry entry (this shell's pid)
  echo "{\"pid\": $$, \"sessionId\": \"${4:-$(sid "$1")}\", \"cwd\": \"${3:-/elsewhere}\", \"status\": \"$2\"}" \
    > "$HOME/.claude/sessions/$1.json"
}
stood() { # stood <repo> <topic> <doc>: the doc stood by the launcher's own commit, pushed
  local wt; wt=$(wtp "$1" "$2"); printf '\n  > **Applied.** Stood: no objection — A\n' >> "$wt/$3"
  git -C "$wt" commit -qam "Memo: stood" -m "Stood-By: autofinish" && git -C "$wt" push -q
}
runrec() { # runrec <topic> <outcome> <gate>: the worktree's last run, by session r-<topic>, ended 30 min before the clock; prints `ended`
  python3 - "$(gd $D "$1")/claude/autofinish.json" "$NOW" "$2" "$3" "$1" <<'EOF'
import datetime, json, sys
p, now, outcome, gate, topic = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4], sys.argv[5]
iso = datetime.datetime.fromtimestamp(now - 1800).astimezone().isoformat(timespec="seconds")
json.dump({"started": iso, "session": "r-" + topic, "tip": "0" * 40, "by": "sweep", "rule": "A", "window": "finish · x",
           "ended": iso, "outcome": outcome, "pr": None, "gate": gate}, open(p, "w"))
print(iso)
EOF
}
queue() { # queue <topic> <session>: a prompt 5 min ago, the file itself made with the fixture (60 min)
  echo "[{\"session\": \"$2\", \"ts\": $((NOW - 300)), \"prompt\": \"go on\"}]" > "$(gd $D "$1")/claude/prompts.json"
  ago "$(gd $D "$1")/claude/prompts.json" 60
}
DLIST='# A design

- **D1 — Pick one.** Body.
  - A — one way
  - B — the other

  ➤ Recommended: A

  ➤ Answer:
'

echo "setup"
newrepo demo '{"checkpoint": true, "main": "main", "records": ["docs/", "TODO.md"]}'
D=demo
mk $D a-ok docs/note.md "a plain record"
mk $D codespan docs/prose.md 'the shape is `➤ Answer:` then `**D1 —**` — prose about it'
mk $D live-idle docs/live.md "x"; session live-idle idle "$(wtp $D live-idle)" "11111111-0000-4000-8000-000000000000"
mk $D busy docs/busy.md "x"; session busy busy
mk $D busy-ov docs/busyov.md "x"; session busy-ov busy
echo '{"by": "sam", "ts": 1}' > "$(gd $D busy-ov)/claude/autofinish"
mk $D wait docs/wait.md "x"; echo > "$(gd $D wait)/claude/last-reply"; ago "$(gd $D wait)/claude/last-reply" 10
mk $D fallback docs/fallback.md "x"
echo '[]' > "$(gd $D fallback)/claude/prompts.json"; ago "$(gd $D fallback)/claude/prompts.json" 5
ago "$HOME/.claude/projects/fixture/$(sid fallback).jsonl" 30
mk $D code bin/tool.py "print(1)"
mk $D code-marker bin/test_x.sh 'printf "  ➤ Answer:\n- [ ] see docs/handoff/x.md\n"'
mk $D json docs/data.json '{"a": 1}'
mk $D binary docs/blob.md "x"; printf 'a\0b\0c' > "$(wtp $D binary)/docs/blob.md"
git -C "$(wtp $D binary)" commit -qam "binary" -m "Deployed: no" && git -C "$(wtp $D binary)" push -q
mk $D r1 docs/existing.md "$DLIST"
mk $D r1-ov docs/existing.md "$DLIST"; echo '{"by": "sam", "ts": 1}' > "$(gd $D r1-ov)/claude/autofinish"
mk $D r1-new docs/stands-design.md "$DLIST"
mk $D r1-new-ov docs/stands-design.md "$DLIST"; echo '{"by": "sam", "ts": 1}' > "$(gd $D r1-new-ov)/claude/autofinish"
mk $D decide docs/decide.md "**Decide:** which one"
mk $D checkbox TODO.md "- [ ] later"
mk $D seed docs/handoff/2026-10-05-x.md "Task: something"
mk $D steps-open docs/handoff/2026-10-15-y.md "Steps: S2 of docs/course.md"
mk $D deployed docs/dep.md "x" "Deployed: shop scripts/deploy.py"
mk $D dep-code bin/live.py "print(1)" "Deployed: the pack to Drive"
mk $D dep-yes bin/live2.py "print(1)" "Deployed: yes"
mk $D dep-asks bin/live3.py "print(1)" "Deployed: shop"; reply dep-asks "Deployed. Shall I launch it?"
mk $D dep-bin docs/dep.bin "x" "Deployed: shop"; printf 'a\0b' > "$(wtp $D dep-bin)/docs/dep.bin"
git -C "$(wtp $D dep-bin)" commit -qam "binary" -m "Deployed: shop" && git -C "$(wtp $D dep-bin)" push -q
mk $D dep-unpushed bin/live4.py "print(1)" "Deployed: shop" nopush
echo > "$(gd $D deployed)/claude/last-reply"; ago "$(gd $D deployed)/claude/last-reply" 0
mk $D a-idle0 docs/idle0.md "x"; echo > "$(gd $D a-idle0)/claude/last-reply"; ago "$(gd $D a-idle0)/claude/last-reply" 0
mk $D dep-none bin/none.py "print(1)" "Deployed: none"
mk $D dep-future bin/future.py "print(1)" "Deployed: on merge (GitHub Pages)"
mk $D dep-earlier bin/earlier.py "print(1)" "Deployed: shop"; echo y >> "$(wtp $D dep-earlier)/bin/earlier.py"
git -C "$(wtp $D dep-earlier)" commit -qam "a later turn" -m "Deployed: no" && git -C "$(wtp $D dep-earlier)" push -q
echo > "$(gd $D dep-earlier)/claude/last-reply"; ago "$(gd $D dep-earlier)/claude/last-reply" 0
mk $D dep-old bin/old.py "print(1)" "Deployed: shop"
GIT_COMMITTER_DATE="2026-10-01T12:00:00-07:00" git -C "$(wtp $D dep-old)" commit -q --amend --no-edit && git -C "$(wtp $D dep-old)" push -q -f
mk $D dep-busy bin/busy.py "print(1)" "Deployed: shop"; session dep-busy busy
mk $D dep-ov bin/ov.py "print(1)" "Deployed: shop"; echo '{"by": "sam", "ts": 1}' > "$(gd $D dep-ov)/claude/autofinish"
echo > "$(gd $D dep-ov)/claude/last-reply"; ago "$(gd $D dep-ov)/claude/last-reply" 0
mk $D openitem docs/oi.md "x" "Open item: the probe is still owed"
mk $D asks docs/asks.md "x"; reply asks "Shall I launch it?"
mk $D waiting docs/waiting.md "x"; reply waiting "Ready.

SAM, THIS SESSION IS WAITING FOR YOU — answer D1 in the doc"
mk $D pending docs/pending.md "x"; reply pending "Reviewers started.

SAM, THIS SESSION IS WAITING FOR SOMETHING — the two reviewers; it continues by itself"
session pending idle "$(wtp $D pending)"
mk $D pending-gone docs/pgone.md "x"; reply pending-gone "Reviewers started.

SAM, THIS SESSION IS WAITING FOR SOMETHING — the two reviewers; it continues by itself"
mk $D unknown docs/unknown.md "x"; rm "$(gd $D unknown)/claude/owner.json" "$HOME/.claude/projects/fixture/$(sid unknown).jsonl"
mk $D unpushed docs/unpushed.md "x" "Deployed: no" nopush
mk $D ahead docs/ahead.md "x"; echo y >> "$(wtp $D ahead)/docs/ahead.md"; git -C "$(wtp $D ahead)" commit -qam more
mk $D moved docs/moved.md "x"
git clone -q "$T/origin-demo.git" "$T/elsewhere" && git -C "$T/elsewhere" checkout -q "$(br moved)"
echo z >> "$T/elsewhere/docs/moved.md" && git -C "$T/elsewhere" commit -qam "from the other Mac" && git -C "$T/elsewhere" push -q
mk $D nopr docs/nopr.md "x"; gh nopr none 0
mk $D ready docs/ready.md "x"; gh ready ready 0
mk $D activity docs/activity.md "x"; gh activity WIP 2
mk $D override bin/deploy.py "print(2)" "Deployed: shop scripts"; echo '{"by": "sam", "ts": 1}' > "$(gd $D override)/claude/autofinish"
mk $D override-asks bin/deploy2.py "x"; echo '{"by": "sam", "ts": 1}' > "$(gd $D override-asks)/claude/autofinish"; reply override-asks "Deploy now?"
mk $D stray-ov bin/stray.py "x"; echo '{"by": "someone"}' > "$(gd $D stray-ov)/claude/autofinish"
mk $D declared bin/declared.py "x"; echo '{"by": "sam", "ts": 1}' > "$(gd $D declared)/claude/autofinish"
reply declared "Built and committed.

SAM, THIS SESSION IS DONE — IT LANDS BY ITSELF."
echo > "$(gd $D declared)/claude/last-reply"; ago "$(gd $D declared)/claude/last-reply" 5
mk $D declared-n bin/declared-n.py "x"; echo '{"by": "sam", "ts": 1}' > "$(gd $D declared-n)/claude/autofinish"
reply declared-n "Built and committed.

SAM, THIS SESSION IS DONE — IT LAUNCHES BY ITSELF."   # rename S2: the line S4 switches to
echo > "$(gd $D declared-n)/claude/last-reply"; ago "$(gd $D declared-n)/claude/last-reply" 5
mk $D declared-l bin/declared-l.py "x"; echo '{"by": "sam", "ts": 1}' > "$(gd $D declared-l)/claude/autofinish"
reply declared-l "Built and committed.

SAM, THIS SESSION IS DONE — IT LANDS BY ITSELF.
[the doc](https://example.invalid/shop/blob/main/docs/x.md)"
echo > "$(gd $D declared-l)/claude/last-reply"; ago "$(gd $D declared-l)/claude/last-reply" 5
mk $D declared-a docs/declared.md "x"; reply declared-a "SAM, THIS SESSION IS DONE — IT LANDS BY ITSELF."
# rename guard: a map run keeps this line (both words) and would turn the old declared line into the launch one
check "$(grep -c '— IT LANDS BY ITSELF\.' "$B/../tests/test_autofinish.sh")" 3 "rename guard: the old declared line's fixtures keep their land word, not launch"
echo > "$(gd $D declared-a)/claude/last-reply"; ago "$(gd $D declared-a)/claude/last-reply" 5
mk $D d-due docs/due-design.md "$DLIST"; echo > "$(gd $D d-due)/claude/last-reply"; ago "$(gd $D d-due)/claude/last-reply" 0  # idle 0: D waits on its deadline only
reply d-due "The doc is linked.

SAM, THIS SESSION IS WAITING FOR YOU — answer the doc"
mk $D d-broken docs/broken-design.md "$DLIST"
mk $D d-code docs/due-plus-code.md "$DLIST"; echo "x" > "$(wtp $D d-code)/bin.py"
git -C "$(wtp $D d-code)" add -A && git -C "$(wtp $D d-code)" commit -qm more && git -C "$(wtp $D d-code)" push -q
mk $D d-answered docs/answered-design.md "$DLIST"
mk $D d-stood docs/stood-design.md "$DLIST"; stood $D d-stood docs/stood-design.md
mk $D d-stood-nt docs/stood-notrailer.md "$DLIST"
mk $D d-partstood docs/partstood-design.md "$DLIST"
mk $D d-halfdue docs/halfdue-design.md "$DLIST"
mk $D dialog docs/dialog.md "x"; session dialog waiting
mk $D shell docs/shell.md "x"; session shell shell
mk $D spaced "docs/my doc.md" "$DLIST"
mk $D plusplus docs/existing.md "++ b/x
  ➤ Answer:"
mk $D st-stop docs/sts.md "x"; ESTOP=$(runrec st-stop stopped G4)
mk $D st-own docs/sto.md "x"; EOWN=$(runrec st-own stopped G4); queue st-own "r-st-own"
mk $D st-other docs/stt.md "x"; runrec st-other stopped G4 > /dev/null; queue st-other someone-else
mk $D st-ns docs/stn.md "x"; ENS=$(runrec st-ns never-started never-started)
mk $D st-nl docs/stl.md "x"; runrec st-nl never-started not-launched > /dev/null
mk $D st-rf docs/stf.md "x"; runrec st-rf never-started refused > /dev/null
mk $D st-ov docs/stv.md "x"; runrec st-ov stopped G4 > /dev/null; echo "{\"by\": \"sam\", \"ts\": $((NOW - 300))}" > "$(gd $D st-ov)/claude/autofinish"
mk $D st-ovold docs/stw.md "x"; EOVOLD=$(runrec st-ovold stopped G4); echo '{"by": "sam", "ts": 1}' > "$(gd $D st-ovold)/claude/autofinish"
mk $D st-reply docs/str.md "x"; runrec st-reply stopped G4 > /dev/null
echo > "$(gd $D st-reply)/claude/last-reply"; ago "$(gd $D st-reply)/claude/last-reply" 5
mk $D launched docs/launched.md "x"
git -C "$T/projects/$D" merge -q --ff-only "$(br launched)" && git -C "$T/projects/$D" push -q origin main
mk $D probably docs/probably.md "x"
echo "other" > "$T/projects/$D/other.md" && git -C "$T/projects/$D" add other.md && git -C "$T/projects/$D" commit -qm other
git -C "$T/projects/$D" cherry-pick "$(br probably)" >/dev/null  # a new parent, so a new commit: same patch, not same sha
echo "main moved on" >> "$T/projects/$D/docs/probably.md" && git -C "$T/projects/$D" commit -qam "edit after" && git -C "$T/projects/$D" push -q origin main
mk $D dirty docs/dirty.md "x"; echo "by hand" > "$(wtp $D dirty)/docs/handmade.md"
mk $D finishing docs/fin.md "x"; touch "$(gd $D finishing)/claude/finishing"; ago "$(gd $D finishing)/claude/finishing" 10
mk $D teleported docs/tp.md "x"; echo '{"to": "buildbox", "at": 1, "session": "abcdef12"}' > "$(gd $D teleported)/claude/teleported.json"
mk $D r8 .claude/workflow.json '{"checkpoint": true, "main": "main", "records": ["docs/", ".claude/", "bin/"]}'
mk $D fresh docs/fresh.md "x"; git -C "$(wtp $D fresh)" reset -q --hard main
git -C "$T/projects/$D" worktree add -q "$T/projects/$D/.claude/worktrees/notclaude" -b feature main

# made a day before the clock, like oldrepo below: "small" at the arm, so its B was never gated
GIT_COMMITTER_DATE="$((NOW - 86400)) +0000" GIT_AUTHOR_DATE="$((NOW - 86400)) +0000" newrepo smallrepo '{"checkpoint": true, "main": "main", "records": ["docs/"], "autofinish": "small"}'
S=smallrepo
mk $S b-ok bin/tool.py "$(seq 1 10)"
mk $S b-big bin/big.py "$(seq 1 120)"
mk $S a-in-small docs/x.md "x"

newrepo personal '{"checkpoint": true, "main": "main", "merge": "auto", "in_place": ["memory/"]}'
mk personal p-doc docs/p.md "x"
mk personal p-ov docs/p.md "x"; echo '{"by": "sam", "ts": 1}' > "$(gd personal p-ov)/claude/autofinish"
newrepo nocheck '{"checkpoint": false, "main": "main", "records": ["docs/"]}'
mk nocheck n-doc docs/n.md "x"
newrepo offkey '{"checkpoint": true, "main": "main", "records": ["docs/"], "autofinish": "off"}'
mk offkey o-doc docs/o.md "x"
mk offkey o-stood docs/stood-design.md "$DLIST"; stood offkey o-stood docs/stood-design.md
# rule E's repos sit in their own repos file (repos-e.json), so the sweep cases below keep their counts
# oldrepo <name> <workflow.json at the arm> <workflow.json now>: made a day before the clock (so
# before the tests' arm, two hours before it), then flipped on main now — the door reads the first
oldrepo() {
  GIT_COMMITTER_DATE="$((NOW - 86400)) +0000" GIT_AUTHOR_DATE="$((NOW - 86400)) +0000" newrepo "$1" "$2"
  echo "$3" > .claude/workflow.json && git commit -qam flip && git push -q origin main
}
oldrepo allrepo '{"checkpoint": true, "main": "main", "records": ["docs/"]}' '{"checkpoint": true, "main": "main", "records": ["docs/"], "autofinish": "all"}'
AL=allrepo
export AUTOFINISH_LAUNCHER=$AL  # GATES apply in the launcher's own repo only (D1-A, 2026-10-13); this fixture plays the overlay checkout
mk $AL e-big bin/big.py "$(seq 1 120)"
mk $AL e-small bin/tool.py "$(seq 1 10)"
mk $AL e-doc docs/e.md "x"
mk $AL e-bin bin/big.py "$(seq 1 120)"; printf 'a\0b\0c' > "$(wtp $AL e-bin)/bin/blob.dat"
git -C "$(wtp $AL e-bin)" add -A && git -C "$(wtp $AL e-bin)" commit -qm "binary" -m "Deployed: no" && git -C "$(wtp $AL e-bin)" push -q
mk $AL e-hooks hooks/big.py "$(seq 1 120)"
mk $AL e-hooks-small hooks/tool.py "$(seq 1 10)"
mk $AL e-self bin/autofinish-run "$(seq 1 120)"
mk $AL e-wf .claude/workflow.json '{"records": ["bin/"]}'
mk $AL e-boot bootstrap.sh "$(seq 1 10)"
mk $AL e-noowner bin/big.py "$(seq 1 120)"; rm "$(gd $AL e-noowner)/claude/owner.json"  # the session from the tip's trailer
mk $AL e-dans docs/answered-design.md "$DLIST"; seq 1 120 > "$(wtp $AL e-dans)/bin.py"
git -C "$(wtp $AL e-dans)" add -A && git -C "$(wtp $AL e-dans)" commit -qm build -m "Deployed: no" && git -C "$(wtp $AL e-dans)" push -q
mk $AL e-ddue docs/due-plus-code.md "$DLIST"; seq 1 120 > "$(wtp $AL e-ddue)/bin.py"
git -C "$(wtp $AL e-ddue)" add -A && git -C "$(wtp $AL e-ddue)" commit -qm build -m "Deployed: no" && git -C "$(wtp $AL e-ddue)" push -q
oldrepo wassmall '{"checkpoint": true, "main": "main", "records": ["docs/"], "autofinish": "small"}' '{"checkpoint": true, "main": "main", "records": ["docs/"], "autofinish": "all"}'
mk wassmall w-small bin/tool.py "$(seq 1 10)"
mk wassmall w-big bin/big.py "$(seq 1 120)"
# off at the arm, "small" after it (shop/books): its B waits for the door too (review at /finish, 2026-10-08)
oldrepo latesmall '{"checkpoint": true, "main": "main"}' '{"checkpoint": true, "main": "main", "records": ["docs/"], "autofinish": "small"}'
mk latesmall ls-small bin/tool.py "$(seq 1 10)"
newrepo newsmall '{"checkpoint": true, "main": "main", "records": ["docs/"], "autofinish": "small"}'
mk newsmall ns-small bin/tool.py "$(seq 1 10)"
oldrepo allall '{"checkpoint": true, "main": "main", "records": ["docs/"], "autofinish": "all"}' '{"checkpoint": true, "main": "main", "records": ["docs/", "TODO.md"], "autofinish": "all"}'
mk allall aa-small bin/tool.py "$(seq 1 10)"
mk latesmall ls-dans docs/answered-design.md "$DLIST"; seq 1 10 > "$(wtp latesmall ls-dans)/bin.py"
git -C "$(wtp latesmall ls-dans)" add -A && git -C "$(wtp latesmall ls-dans)" commit -qm build -m "Deployed: no" && git -C "$(wtp latesmall ls-dans)" push -q
newrepo badkey '{"checkpoint": true, "main": "main", "records": ["docs/"], "autofinish": "everything"}'
mk badkey u-code bin/x.py "x"
# gaterepo: an "all" repo with a contract whose check line runs two of its files, an
# autofinish_exclude (one entry "./"-spelled), and AGENTS.md among its records (rule A's own)
oldrepo gaterepo '{"checkpoint": true, "main": "main", "records": ["docs/"]}' \
  '{"checkpoint": true, "main": "main", "records": ["docs/", "AGENTS.md"], "autofinish": "all", "autofinish_exclude": ["deploy/", "./scripts/release.sh", "", 7]}'
mkdir -p scripts && echo 'exit 0' > check.sh && echo 'print(0)' > scripts/test.py && echo 'print(1)' > scripts/app.py
printf '# gaterepo\n\n## Session contract\n\n- check: `./check.sh && CHECK=1 python3 scripts/test.py --check` — both; `scripts/app.py` is prose\n' > AGENTS.md
git add -A && git commit -qm contract && git push -q origin main
G=gaterepo
mk $G g-github .github/workflows/ci.yml "on: push"
mk $G g-claude .claude/settings.json '{"x": 1}'
mk $G g-claudemd CLAUDE.md "@AGENTS.md"
mk $G g-check check.sh "exit 0 # weaker"
mk $G g-test scripts/test.py "$(seq 1 120)"
mk $G g-excl deploy/run.py "print(2)"
mk $G g-excl2 scripts/release.sh "echo release"
mk $G g-app scripts/app.py "print(3)"
mk $G g-agents AGENTS.md "# rewritten"
mk $G g-nested app/CLAUDE.md "# looser rules"
mk $G g-githook scripts/git-hooks/pre-push "exit 0"
mk $G g-hooks hooks/tool.py "print(4)"
# a non-list autofinish_exclude or in_place turns the repo off (review at /finish, 2026-10-10; 2026-10-13)
newrepo badexcl '{"checkpoint": true, "main": "main", "records": ["docs/"], "autofinish": "all", "autofinish_exclude": "deploy/"}'
mk badexcl bx-code deploy/run.py "print(2)"
newrepo inplace '{"checkpoint": true, "main": "main", "autofinish": "all", "in_place": ["log.md", "memory/"]}'
mk inplace ip-log memory/note.md "x"
mk inplace ip-code bin/x.py "print(5)"
newrepo inplacerec '{"checkpoint": true, "main": "main", "records": ["log.md", "docs/"], "in_place": ["log.md"]}'
mk inplacerec ipr-log log.md "x"
mk inplacerec ipr-docs docs/a.md "x"
newrepo badinplace '{"checkpoint": true, "main": "main", "autofinish": "all", "in_place": "memory/"}'
mk badinplace bi-code bin/x.py "print(6)"
mk $G g-docs docs/g.md "x"
mk $G g-d docs/due-design.md "$DLIST"; echo "# and the contract" >> "$(wtp $G g-d)/AGENTS.md"
git -C "$(wtp $G g-d)" commit -qam "contract too" -m "Deployed: no" && git -C "$(wtp $G g-d)" push -q
mk $G g-d-ok docs/due-design.md "$DLIST"
mk $G g-excl-dep deploy/live.py "print(2)" "Deployed: deploy/live.py"
mk badkey u-dep bin/y.py "x" "Deployed: shop"
echo '{"repos": {"demo": {}, "smallrepo": {}, "allrepo": {}, "wassmall": {}, "latesmall": {}, "allall": {}, "newsmall": {}, "badkey": {}, "gaterepo": {}, "badexcl": {}, "inplace": {}, "inplacerec": {}, "badinplace": {}}}' > "$T/repos-e.json"
ghjson

line() { grep -F " $(br "$2") " "$1" | sed "s|^[^ ]* $(br "$2") ||"; }  # line <out> <topic> → verdict
# every file in the repos and on origin, with its mtime and content hash: what "read-only" means.
# One python3 for the walk (find -type f's set: regular files, no symlink followed), not a stat,
# shasum and cut per file: over ~4,300 files that was ~17,000 processes, 3.5 min a snapshot on a
# loaded Mac and four snapshots a run (2026-10-17). Same line per file: mtime, SHA-1's first 12, path.
snapshot() {
  python3 - "$T/projects" "$T"/origin-*.git <<'EOF'
import hashlib, os, stat, sys
files = []
for top in sys.argv[1:]:
    for d, _, names in os.walk(top):
        files += [os.path.join(d, n) for n in names]
for f in sorted(files):
    try:  # one unreadable or vanished file is a line of its own, never a cut-short walk
        st = os.lstat(f)
        if stat.S_ISREG(st.st_mode):
            with open(f, "rb") as fh:
                print(int(st.st_mtime), hashlib.sha1(fh.read()).hexdigest()[:12], f)
    except OSError as e:
        print("unreadable", type(e).__name__, f)
EOF
}
snapshot > "$T/before"
python3 "$B/autofinish" --dry-run demo > "$T/out" 2> "$T/err"; check "$?" 0 "dry run exits 0"
check "$(cat "$T/err")" "" "nothing on stderr"
O="$T/out"

echo "rule A and the clock"
check "$(line $O a-ok)" "start (A)" "records-only, idle 60 min, pushed, WIP, quiet → A (Deployed: no is fine)"
check "$(line $O codespan)" "start (A)" "an Answer marker in a code span is prose, not an ask"
check "$(line $O live-idle)" "start (A)" "a live session that is idle does not veto"
check "$(line $O wait)" "wait: idle 10 min" "last-reply 10 min old → wait"
check "$(line $O fallback)" "wait: idle 5 min" "no last-reply: the newest of prompts.json and the transcript"
check "$(line $O fresh)" "skip: nothing committed" "a worktree with no commit of its own"
hasnt "$O" " feature " "a branch outside claude/* is not listed"

echo "vetoes"
check "$(line $O busy)" "skip: busy (session $(sid busy | cut -c1-8))" "a busy live session on the branch"
check "$(line $O busy-ov)" "skip: busy (session $(sid busy-ov | cut -c1-8))" "busy wins over the override"
check "$(line $O dialog)" "skip: busy (session $(sid dialog | cut -c1-8), waiting)" "a session waiting on a dialog is busy too (anything but idle)"
check "$(line $O shell)" "skip: busy (session $(sid shell | cut -c1-8), shell)" "  and one running a shell"
check "$(line $O code)" "skip: not records (bin/tool.py)" "a path outside records"
check "$(line $O code-marker)" "skip: not records (bin/test_x.sh)" "asks markers in code are fixtures, not asks"
check "$(line $O json)" "skip: not text (docs/data.json)" "R13: a non-text file under a records prefix"
check "$(line $O binary)" "skip: binary (docs/blob.md)" "a binary"
check "$(line $O decide)" "skip: asks (docs/decide.md: **Decide:**)" "a Decide line"
check "$(line $O checkbox)" "skip: asks (TODO.md: - [ ])" "an unticked box"
check "$(line $O seed)" "skip: asks (docs/handoff/2026-10-05-x.md: a seed under docs/handoff/)" "a seed"
check "$(line $O steps-open)" "skip: open step (docs/handoff/2026-10-15-y.md names docs/course.md S2 — not started)" \
  "a brief whose Steps: line names an open step: never a start (entry S7, keel landing)"
echo "rule L: a deployed branch launches at once (Sam, 2026-10-13)"
check "$(line $O deployed)" "start (L)" "Deployed: other than no, idle 0 min → L, no wait"
check "$(line $O a-idle0)" "wait: idle 0 min" "  beside a plain doc at idle 0, which waits"
check "$(line $O dep-none)" "skip: not records (bin/none.py)" "  Deployed: none is no deploy"
check "$(line $O dep-future)" "skip: not records (bin/future.py)" "  nor a future 'on merge'"
check "$(line $O dep-earlier)" "start (L)" "  an earlier commit's deploy counts: the tip need not say it"
check "$(line $O dep-old)" "skip: deployed before rule L (shop) — launches by /finish" "  a deploy committed before 2026-10-14 keeps the typed /finish"
check "$(line $O dep-busy)" "skip: busy (session $(sid dep-busy | cut -c1-8))" "  never under a busy session"
check "$(line $O dep-ov)" "start (C)" "  under /autofinish too, the deploy starts at idle 0"
check "$(line $O dep-code)" "start (L)" "  code in a records repo: any shape"
check "$(line $O dep-yes)" "start (L)" "  Deployed: yes"
check "$(line $O dep-asks)" "skip: last reply asks (ends in ?)" "  never under a reply that asks"
check "$(line $O dep-bin)" "skip: binary (docs/dep.bin)" "  never a binary"
check "$(line $O dep-unpushed)" "skip: not pushed" "  never unpushed"
check "$(line $O openitem)" "skip: open item in the tip's message" "an open item in the tip"
check "$(line $O asks)" "skip: last reply asks (ends in ?)" "the last reply asks"
check "$(line $O waiting)" "skip: waiting for Sam (last reply ends in the WAITING line)" "the WAITING line"
check "$(line $O pending)" "skip: waiting on its own work (last reply ends in the WAITING FOR SOMETHING line)" "  and WAITING FOR SOMETHING: never launched under its live session"
check "$(line $O pending-gone)" "start (A)" "  …but with its session gone nothing picks it up: no veto"
check "$(line $O unknown)" "skip: last reply unknown (session $(sid unknown | cut -c1-8))" "no transcript: never a guess"
check "$(line $O unpushed)" "skip: not pushed" "never pushed"
check "$(line $O ahead)" "skip: not pushed (local is ahead of origin)" "local ahead of origin"
check "$(line $O moved)" "skip: moved on origin" "R7: origin moved on"
check "$(line $O nopr)" "skip: no PR" "no PR"
check "$(line $O ready)" "skip: PR #$(grep -n "$(br ready) ready" "$T/gh.lines" | cut -d: -f1) is no longer WIP" "the PR left WIP"
check "$(line $O activity)" "skip: GitHub activity since the tip (2 on #$(grep -n "$(br activity) WIP 2" "$T/gh.lines" | cut -d: -f1))" "comments since the tip"
check "$(line $O launched)" "skip: launched (merged)" "launched"
check "$(line $O probably)" "skip: pickup review (every commit has an equivalent on main)" "R10: probably launched"
check "$(line $O dirty)" "skip: uncommitted (1 files)" "uncommitted work"
check "$(line $O finishing)" "skip: finishing (a /finish is under way)" "a /finish under way"
case "$(line $O teleported)" in "skip: moved (moved to buildbox"*) echo "  ok   a /move marker";; *) echo "  FAIL a /move marker: $(line $O teleported)"; fails=$((fails+1));; esac
check "$(line $O r8)" "skip: not records (.claude/workflow.json)" "R8: the base's records list, not the branch's"

echo "R1: a doc that asks is never started, override or not"
check "$(line $O r1)" "skip: asks (docs/existing.md: **D<n> —**)" "Answer + D1 lines in an existing doc"
check "$(line $O r1-ov)" "skip: asks (docs/existing.md: **D<n> —**)" "… with the override"
check "$(line $O r1-new)" "skip: asks (docs/stands-design.md: memo stands-at 2026-10-06T09:00:00+02:00)" "a new D-list doc that does not stand yet"
check "$(line $O r1-new-ov)" "skip: asks (docs/stands-design.md: memo stands-at 2026-10-06T09:00:00+02:00)" "… with the override"
check "$(line $O spaced)" "skip: asks (docs/my doc.md: memo stands-at 2026-10-06T09:00:00+02:00)" "a doc whose name has a space is read, not passed (git's TAB after +++)"
check "$(line $O plusplus)" "skip: asks (docs/existing.md: ➤ Answer:)" "an added line '++ b/x' does not re-target the lines after it"
python3 - "$B/autofinish" "$(wtp $D a-ok)" <<'EOF' > "$T/unparsed" 2>&1
import sys
from importlib.machinery import SourceFileLoader
m = SourceFileLoader("autofinish", sys.argv[1]).load_module()
real, wt = m.raw, sys.argv[2]
base = m.git(wt, "merge-base", "origin/main", "HEAD")
for diff in ("diff --git a/docs/note.md b/docs/note.md\n@@ -0,0 +1 @@\n+a plain record\nstray text\n",
             "diff --git a/docs/note.md b/docs/note.md\n+++ b/docs/note.md\n"):
    m.raw = lambda repo, *a, timeout=30, d=diff: d if "-U0" in a else real(repo, *a, timeout=timeout)
    print(m.diff_facts(wt, base, "HEAD")[4])
m.raw = real
print(m.diff_facts(wt, base, "HEAD")[3:])
EOF
check "$(cat "$T/unparsed" | tr '\n' ' ')" "['docs/note.md'] ['docs/note.md'] ({'docs/note.md': ['a plain record']}, []) " \
  "a hunk line that is no diff line, or an added line numstat counts and no hunk holds: unparsed (skip: asks), never a pass"

python3 - "$B/autofinish" "$(wtp $D a-ok)" <<'EOF' > "$T/runner-by" 2>&1
import json, sys
from importlib.machinery import SourceFileLoader
from pathlib import Path
m = SourceFileLoader("autofinish", sys.argv[1]).load_module()
st = Path(m.git(sys.argv[2], "rev-parse", "--absolute-git-dir")) / "claude"
st.mkdir(exist_ok=True)
rec, old = st / "autofinish.json", None
if rec.exists():
    old = rec.read_text()
out = [m.runner_by(sys.argv[2], "A")]
for by, outcome in (("yolo", "died"), ("yolo", "stopped"), ("sweep", "died")):
    rec.write_text(json.dumps({"by": by, "outcome": outcome, "ended": "x"}))
    out.append(m.runner_by(sys.argv[2], "A"))
rec.write_text(old) if old is not None else rec.unlink()
print(" ".join(out))
EOF
check "$(cat "$T/runner-by")" "sweep yolo sweep sweep" "a yolo launch that died is retried as yolo (E12); any other run: the sweep's"

echo "rule C"
check "$(line $O override)" "start (C)" "the override lifts records, Deployed and the repo's mode"
check "$(line $O override-asks)" "skip: last reply asks (ends in ?)" "the override keeps the reply veto"
check "$(line $O stray-ov)" "skip: not records (bin/stray.py)" "a marker not written by Sam's /autofinish is no override"
check "$(line $O declared)" "start (C)" "the declared line starts C without the 40 min"
check "$(line $O declared-n)" "start (C)" "  the new declared line too (rename S2: common.DECLARED_LINES)"
check "$(line $O declared-l)" "start (C)" "  a link line after it too, as the Stop hook reads it (common.ending)"
check "$(line $O declared-a)" "wait: idle 5 min" "… and only under the override"

echo "rule D"
check "$(line $O d-due)" "start (D)" "a new D-list doc memo calls due → D, idle or not"
check "$(line $O d-broken)" "skip: memo status unavailable (docs/broken-design.md)" "memo fails → never a start"
check "$(line $O d-code)" "skip: not records (bin.py)" "a stood doc with code beside it is a build, not D"
check "$(line $O d-answered)" "start (D)" "a doc Sam answered in full → D"
check "$(line $O d-stood)" "start (D)" "a doc stood by the launcher's own commit on the branch → D (the start's apply already ran)"
check "$(line $O d-stood-nt)" "skip: asks (docs/stood-notrailer.md: memo stood, but no \`Stood-By: autofinish\` commit on the branch)" \
  "  memo's stood with no Stood-By commit on this branch is no pass"
check "$(line $O d-partstood)" "skip: asks (docs/partstood-design.md: memo part-stood — stood (abc1234); 1 still open: D2 Reversible: no)" \
  "  part-stood (entry S3: no or unmarked items left open by a stand) is refused"
check "$(line $O d-halfdue)" "skip: asks (docs/halfdue-design.md: memo due, but a stand leaves D2 unmarked open)" \
  "  due, but a stand would leave it part-stood: refused before anything is written"
check "$(grep -c -- '^status --json --no-fetch docs/due-design.md$' "$T/memo.calls")" "1" "the dry run asks memo with --no-fetch"
check "$(grep -cv -- '--no-fetch' "$T/memo.calls")" "0" "  every time: a dry run fetches nothing"

echo "a run that stopped waits for a prompt (code review F6)"
check "$(line $O st-stop)" "skip: stopped at G4 ($ESTOP) — waits for a prompt" "stopped, nobody spoke since: skip"
check "$(line $O st-own)" "skip: stopped at G4 ($EOWN) — waits for a prompt" "  a prompt from the run's own session is not one"
check "$(line $O st-other)" "start (A)" "  a prompt from another session since the end lifts it"
check "$(line $O st-reply)" "wait: idle 5 min" "  so does a turn's end since (last-reply), which a checkpoint commit does not clear"
check "$(line $O st-ns)" "skip: stopped at never-started ($ENS) — waits for a prompt" "never-started waits too"
check "$(line $O st-rf)" "start (A)" "  but not a run dispatch refused before any session (gate refused)"
check "$(line $O st-nl)" "start (A)" "  …nor one recorded before 2026-10-17 (gate not-launched, read both ways)"
check "$(line $O st-ov)" "start (C)" "an override set since the end lifts it"
check "$(line $O st-ovold)" "skip: stopped at G4 ($EOVOLD) — waits for a prompt" "  one set before it does not"
AUTOFINISH_MEMO="$T/no-memo" python3 "$B/autofinish" --dry-run demo > "$T/out-nomemo" 2>&1
check "$(line "$T/out-nomemo" d-due)" "skip: memo status unavailable (docs/due-design.md)" "memo missing → never a start"

echo "read-only"
snapshot > "$T/after"
check "$(diff "$T/before" "$T/after" | head -5)" "" "the dry run wrote nothing in the repos or on origin"

echo "rule B and the repo's mode"
python3 "$B/autofinish" --dry-run "$T/projects/smallrepo" > "$T/out-s" 2>&1
check "$(line "$T/out-s" b-ok)" "start (B)" "small code in a small repo, on the laptop → B"
check "$(line "$T/out-s" b-big)" "skip: too big for B (120 inserted lines, needs < 100)" "120 lines"
check "$(line "$T/out-s" a-in-small)" "start (A)" "records-only in a small repo is still A"
AUTOFINISH_HOST=buildbox python3 "$B/autofinish" --dry-run smallrepo > "$T/out-i" 2>&1
check "$(line "$T/out-i" b-ok)" "skip: B is laptop only (host buildbox)" "B on buildbox"
check "$(line "$T/out-i" a-in-small)" "start (A)" "A has no host rule"
python3 "$B/autofinish" --dry-run personal > "$T/out-p" 2>&1
check "$(line "$T/out-p" p-doc)" "skip: off" "no records, no key → off (vault)"
check "$(line "$T/out-p" p-ov)" "start (C)" "the override lifts off"
python3 "$B/autofinish" --dry-run "$T/projects/offkey" > "$T/out-o" 2>&1
check "$(line "$T/out-o" o-doc)" "skip: off" "an explicit off beats a records list"
check "$(line "$T/out-o" o-stood)" "skip: off" "  a stood doc in an off repo never starts"

echo "R6: a tight week pauses A and B, not C or D"
CLAUDE_TIER_CLAUDE_JSON="$T/tier-tight.json" python3 "$B/autofinish" --dry-run demo > "$T/out-t" 2>&1
CLAUDE_TIER_CLAUDE_JSON="$T/tier-tight.json" python3 "$B/autofinish" --dry-run smallrepo >> "$T/out-t" 2>&1
case "$(line "$T/out-t" a-ok)" in "skip: week tight (85% used"*) echo "  ok   A paused";; *) echo "  FAIL A paused: $(line "$T/out-t" a-ok)"; fails=$((fails+1));; esac
case "$(line "$T/out-t" b-ok)" in "skip: week tight (85% used"*) echo "  ok   B paused";; *) echo "  FAIL B paused: $(line "$T/out-t" b-ok)"; fails=$((fails+1));; esac
check "$(line "$T/out-t" override)" "start (C)" "C runs"
check "$(line "$T/out-t" d-due)" "start (D)" "D runs"
check "$(line "$T/out-t" dep-code)" "start (L)" "L runs: the week never pauses a deploy's launch"
AUTOFINISH_HOST=buildbox python3 "$B/autofinish" --dry-run demo > "$T/out-di" 2>&1
check "$(line "$T/out-di" dep-code)" "start (L)" "  nor the host"

echo "rule E: \"all\" repos, after 5 launches since the arm (autofinish-widen D1-A, D2-C, D3-C)"
ES="$T/estate"; mkdir -p "$ES"
ae() { AUTOFINISH_REPOS="$T/repos-e.json" AUTOFINISH_STATE_DIR="$ES" AUTOFINISH_LOG_DIR="$T/logs-e" python3 "$B/autofinish" --dry-run "$@" 2>&1; }
# fin <repo> <min before the clock> <outcome> <branch> [<by>]: autofinish-run's end line in the dated log
fin() {
  local ts; ts=$(python3 -c 'import datetime,sys;print(datetime.datetime.fromtimestamp(float(sys.argv[1])-60*float(sys.argv[2])).astimezone().isoformat(timespec="seconds"))' "$NOW" "$2")
  mkdir -p "$T/logs-e"
  echo "$ts run $1 $4 $3 pr=#1 session=s-${4##*/} tip=abc1234 rule=${6:-A} by=${5:-sweep} — SAM, THIS SESSION IS DONE — BUT READ THE NOTE ABOVE BEFORE YOU CLOSE IT. by=sweep" \
    >> "$T/logs-e/autofinish-${ts:0:10}.log"
}
snapshot > "$T/before-e"
ae $AL > "$T/out-e0"
check "$(line "$T/out-e0" e-big)" "skip: E waits for 5 launches (disarmed)" "a big code diff in an all repo, disarmed: E shut"
check "$(line "$T/out-e0" e-small)" "skip: B waits for 5 launches (disarmed)" "  a small diff there is B, behind the same door: the repo was records before (item 2)"
check "$(line "$T/out-e0" e-doc)" "start (A)" "  records-only there stays A, door or not"
check "$(line "$T/out-e0" e-bin)" "skip: binary (bin/blob.dat)" "  a binary still vetoes"
python3 -c 'import datetime,json,sys;print(json.dumps({"by":"tester","ts":datetime.datetime.fromtimestamp(float(sys.argv[1])-7200).astimezone().isoformat(timespec="seconds")}))' "$NOW" > "$ES/armed"
ae $AL > "$T/out-e1"
check "$(line "$T/out-e1" e-big)" "skip: E waits for 5 launches (0/5)" "armed, nothing launched: 0/5"
check "$(line "$T/out-e1" e-small)" "skip: B waits for 5 launches (0/5)" "  B too, in a repo that was records at the arm"
ae wassmall > "$T/out-w1"
check "$(line "$T/out-w1" w-small)" "start (B)" "  but not in one that was small at the arm: B ran there already"
check "$(line "$T/out-w1" w-big)" "skip: E waits for 5 launches (0/5)" "  E there waits all the same"
ae latesmall > "$T/out-l1"
check "$(line "$T/out-l1" ls-small)" "skip: B waits for 5 launches (0/5)" "  a repo that turned small after the arm: B waits too"
ae newsmall > "$T/out-n1"
check "$(line "$T/out-n1" ns-small)" "skip: B waits for 5 launches (0/5)" "  a small repo born after the arm (its mode then unreadable): B waits, the door fails closed"
ae allall > "$T/out-a1"
check "$(line "$T/out-a1" aa-small)" "start (B)" "  a repo already all at the arm: its B is spared"
check "$(line "$T/out-l1" ls-dans)" "skip: not records (bin.py)" "  an answered D-list doc beside code opens nothing in a small repo (all only)"
fin $AL 300 launched claude/x/old1; fin $AL 200 launched claude/x/old2   # before the arm: not counted
fin $AL 60 stopped claude/x/stop                                        # not a launch
fin $AL 65 launched claude/x/typed typed; fin $AL 62 launched claude/x/ov override   # Sam's, not the sweep's
# l3 ends in the word rename S4 writes: the door counts old and new lines alike (M8, risk R2)
fin $AL 100 landed claude/x/l1; fin $AL 90 landed claude/x/l2; fin $AL 80 launched claude/x/l3; fin $AL 70 landed claude/x/l4
fin $AL 70 launched claude/x/l4                                           # the same run logged twice: one
fin $AL 66 launched claude/x/live sweep L                                 # rule L: the deploy's, not the sweep's judgement
# bury()'s line for a dead run (autofinish-run): "died", never a launch
d=$(python3 -c 'import datetime,sys;print(datetime.datetime.fromtimestamp(float(sys.argv[1])-3000).astimezone().isoformat(timespec="seconds"))' "$NOW")
echo "$d run $AL claude/x/dead died session=s-dead tip=abc1234 rule=E by=sweep — dispatch: busy; commented on #1" >> "$T/logs-e/autofinish-${d:0:10}.log"
grep -h ' landed claude/x/l1 ' "$T"/logs-e/autofinish-2*.log | sed 's|claude/x/l1|claude/x/launchd|' > "$T/logs-e/autofinish-launchd.log"  # not a dated log; l1 is logged landed, never launched: the old word on purpose
ae $AL > "$T/out-e4"
check "$(line "$T/out-e4" e-big)" "skip: E waits for 5 launches (4/5)" "four sweep launches since the arm, three of them in the old word (landed); older, stopped, died, typed, override, rule L, a repeat and the launchd log not counted"
fin demo 50 launched claude/x/l5
ae $AL > "$T/out-e5"
check "$(line "$T/out-e5" e-big)" "start (E)" "the fifth, in another workflow repo, opens E"
check "$(line "$T/out-e5" e-small)" "start (B)" "  and B behind the same door"
check "$(line "$T/out-e5" e-bin)" "skip: binary (bin/blob.dat)" "  a binary still vetoes"
check "$(line "$T/out-e5" e-noowner)" "start (E)" "  a worktree with no owner.json: the session from the tip's trailer"
GL="— launches by /finish or /autofinish only"
check "$(line "$T/out-e5" e-hooks)" "skip: touches a gate (hooks/big.py) $GL" "E never launches hooks/ (item 3: rule C only)"
check "$(line "$T/out-e5" e-self)" "skip: touches a gate (bin/autofinish-run) $GL" "  nor the launcher's own gates"
check "$(line "$T/out-e5" e-wf)" "skip: touches a gate (.claude/workflow.json) $GL" "  nor the launcher's own workflow.json (records or merge would widen it)"
check "$(line "$T/out-e5" e-boot)" "skip: touches a gate (bootstrap.sh) $GL" "  nor bootstrap.sh, which wires every account's hooks"
check "$(line "$T/out-e5" e-hooks-small)" "skip: touches a gate (hooks/tool.py) $GL" "  nor B, under 100 lines (the gates never launch unwatched)"
echo "D1-A (2026-10-13): outside the launcher only a repo's autofinish_exclude and in_place gate; C launches a gate"
mkdir -p "$T/overlay/launcher-repo"
check "$(env -u AUTOFINISH_LAUNCHER -u AUTOFINISH_LANDER REGATTA_LEGACY="$T/overlay/launcher-repo" python3 - "$B/autofinish" <<'EOF' 2>&1
import sys
from importlib.machinery import SourceFileLoader
m = SourceFileLoader("autofinish", sys.argv[1]).load_module()
print(m.LAUNCHER, bool(m.touches_gate("/x/launcher-repo", "main", [], ["hooks/a.py"])), bool(m.touches_gate("/x/shop", "main", [], ["hooks/a.py"])))
EOF
)" "launcher-repo True False" "the launcher is the repo named for the overlay checkout by default: hooks/ gated there, not elsewhere"
# rename S4 (M10): AUTOFINISH_LANDER is the old name of AUTOFINISH_LAUNCHER, read until S8; the new one wins
lname() { env -u AUTOFINISH_LAUNCHER -u AUTOFINISH_LANDER -u REGATTA_LEGACY "$@" python3 -c 'import sys; from importlib.machinery import SourceFileLoader as L; print(L("autofinish", sys.argv[1]).load_module().LAUNCHER)' "$B/autofinish" 2>&1; }
check "$(lname)" "None" "  no overlay installed: no repo is the launcher's"
check "$(lname AUTOFINISH_LANDER=shop)" "shop" "  the old env alone still names the launcher's repo (alias until S8)"
check "$(lname AUTOFINISH_LANDER=shop AUTOFINISH_LAUNCHER=household)" "household" "  beside the new one, the new one wins"
ae gaterepo > "$T/out-g"
check "$(line "$T/out-g" g-github)" "start (B)" ".github/ is no gate any more"
check "$(line "$T/out-g" g-claude)" "start (B)" "  nor .claude/"
check "$(line "$T/out-g" g-claudemd)" "start (B)" "  nor CLAUDE.md"
check "$(line "$T/out-g" g-check)" "start (B)" "  nor the check line's ./check.sh"
check "$(line "$T/out-g" g-test)" "start (E)" "  nor its scripts/test.py"
check "$(line "$T/out-g" g-nested)" "start (B)" "  nor a CLAUDE.md in a folder"
check "$(line "$T/out-g" g-githook)" "start (B)" "  nor the repo-level git hooks"
check "$(line "$T/out-g" g-hooks)" "start (B)" "  and hooks/ outside the launcher's repo is plain code"
check "$(line "$T/out-g" g-excl)" "skip: touches a gate (deploy/run.py) $GL" "autofinish_exclude adds a folder"
check "$(line "$T/out-g" g-excl2)" "skip: touches a gate (scripts/release.sh) $GL" "  and a ./-spelled file; an empty or non-string entry gates nothing"
check "$(line "$T/out-g" g-app)" "start (B)" "a file only the check line's prose names is plain code"
ae badexcl > "$T/out-bx"
check "$(line "$T/out-bx" bx-code)" "skip: off (autofinish_exclude is not a list (str))" "a non-list autofinish_exclude turns the repo off, never open"
ae inplace > "$T/out-ip"
check "$(line "$T/out-ip" ip-log)" "skip: touches a gate (memory/note.md) $GL" "an in_place path is a gate with no autofinish_exclude entry (review, 2026-10-13)"
check "$(line "$T/out-ip" ip-code)" "start (B)" "  and code beside it is not"
ae inplacerec > "$T/out-ipr"
check "$(line "$T/out-ipr" ipr-log)" "skip: touches a gate (log.md) $GL" "  rule A too: an in-place path listed as a record never launches from a branch"
check "$(line "$T/out-ipr" ipr-docs)" "start (A)" "  while the other records launch as A"
ae badinplace > "$T/out-bi"
check "$(line "$T/out-bi" bi-code)" "skip: off (in_place is not a list (str))" "a non-list in_place turns the repo off, never open"
check "$(line "$T/out-g" g-agents)" "start (A)" "rule A unchanged: a record launches as one"
check "$(line "$T/out-g" g-docs)" "start (A)" "  records stay A"
check "$(line "$T/out-g" g-d)" "start (D)" "rule D with the contract in its records: no gate any more"
check "$(line "$T/out-g" g-d-ok)" "start (D)" "  and without"
echo '{"by": "sam", "ts": 1}' > "$(gd $G g-excl)/claude/autofinish"
check "$(line "$(ae gaterepo > "$T/out-gc"; echo "$T/out-gc")" g-excl)" "start (C)" "rule C (Sam's /autofinish) launches a gate"
rm "$(gd $G g-excl)/claude/autofinish"
AUTOFINISH_HOST=buildbox ae gaterepo > "$T/out-gi"
check "$(line "$T/out-gi" g-excl)" "skip: touches a gate (deploy/run.py) $GL" "the gate is named before the host"
check "$(line "$T/out-e5" e-dans)" "start (E)" "a D-list doc answered in full, beside code in an all repo: judged as code"
check "$(line "$T/out-e5" e-ddue)" "skip: asks (docs/due-plus-code.md: memo due, beside code — launches once answered)" "  a due one there is still an ask, never stood in for Sam"
ae smallrepo > "$T/out-e5s"
ae latesmall > "$T/out-l5"
check "$(line "$T/out-l5" ls-small)" "start (B)" "  the door open, its B starts"
check "$(line "$T/out-e5s" b-big)" "skip: too big for B (120 inserted lines, needs < 100)" "  a small repo is unchanged: no E there"
case "$(CLAUDE_TIER_CLAUDE_JSON="$T/tier-tight.json" ae $AL | grep -F " $(br e-big) ")" in
  *"skip: week tight (85% used"*) echo "  ok   the week pauses E";; *) echo "  FAIL the week pauses E"; fails=$((fails+1));; esac
AUTOFINISH_HOST=buildbox ae $AL > "$T/out-ei"
check "$(line "$T/out-ei" e-big)" "skip: E is laptop only (host buildbox)" "E off the laptop"
check "$(line "$T/out-ei" e-small)" "skip: B is laptop only (host buildbox)" "  and B, as before"
check "$(line "$T/out-g" g-excl-dep)" "skip: touches a gate (deploy/live.py) $GL" "rule L never launches a gate"
ae badkey > "$T/out-u"
check "$(line "$T/out-u" u-dep)" "skip: off (unknown autofinish value 'everything')" "  nor in a repo that is off (rule L)"
check "$(line "$T/out-u" u-code)" "skip: off (unknown autofinish value 'everything')" "an unknown value is still off"
snapshot > "$T/after-e"
check "$(diff "$T/before-e" "$T/after-e" | head -5)" "" "the E dry runs wrote nothing in the repos or on origin"
first=$(cat "$ES/armed")
AUTOFINISH_STATE_DIR="$ES" python3 "$B/autofinish" disarm > /dev/null && AUTOFINISH_STATE_DIR="$ES" python3 "$B/autofinish" arm --by tester > /dev/null
check "$(line "$(ae $AL > "$T/out-e6"; echo "$T/out-e6")" e-big)" "start (E)" "a re-arm keeps the count (first-armed), not 0/5"
check "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["ts"] == json.loads(sys.argv[2])["ts"])' "$ES/first-armed" "$first")" "True" "  first-armed holds the first arm's ts"
check "$(python3 - "$CORE" <<'EOF'
import sys
sys.path.insert(0, sys.argv[1])
import common
line = common.RUN_END % ("2026-10-08T01:00:00-07:00", "shop", "claude/x/y", "landed", "", " pr=#7", "abcd1234",
                         "abc1234", "E", "sweep", "acct-c", "SAM, THIS SESSION IS DONE — by=typed", "")
m = common.RUN_LAUNCHED.match(line)
print(m and m.group(3, 4, 5))
m = common.RUN_LAUNCHED.match(line.replace(" landed ", " launched ", 1))
print(m and m.group(3, 4, 5))
EOF
)" "('claude/x/y', 'abcd1234', 'sweep')
('claude/x/y', 'abcd1234', 'sweep')" "autofinish-run's end line and the door's reader share one format (common.RUN_END), in either word (rename S2)"

echo "the week is the picked account's: acct-c first, a denied repo the next row (work-account E5, 2026-10-08)"
ln -s "$T/projects" "$HOME/projects"   # bin/account names a repo by its path under ~/projects
mkdir -p "$HOME/.acct-c"
# pool <acct-c week> <acct-a week> <acct-c 5h> <acct-a 5h> [age s]: acct-c (week_max 70)
# denies smallrepo; both rows read at NOW - age; this login's own reading (tier_check) is 85 %
pool() {
  python3 - "$T/accounts.json" "$HOME" "$NOW" "$@" <<'EOF'
import json, sys
f, home, now = sys.argv[1], sys.argv[2], float(sys.argv[3])
iw, dw, i5, d5 = (float(x) for x in sys.argv[4:8])
at = now - float(sys.argv[8]) if len(sys.argv) > 8 else now
json.dump({"accounts": [
    {"label": "acct-c", "home": home + "/.acct-c", "rules": {"window_max": 50, "week_max": 70}, "repos": {"deny": ["smallrepo"]}},
    {"label": "acct-a", "home": home + "/.claude", "primary": True, "rules": {"window_max": 50}}]}, open(f, "w"))
for d, wk, fh in ((home + "/.acct-c", iw, i5), (home + "/.claude", dw, d5)):
    json.dump({"at": at, "limits": {"five_hour": fh, "seven_day": wk, "five_hour_resets": now + 3600,
                                    "seven_day_resets": now + 3 * 86400, "locked": []}}, open(d + "/usage-probe.json", "w"))
EOF
}
# a probe would run this stand-in claude: a judging that is no start must never reach it
printf '#!/bin/sh\ntouch "%s"\nexit 1\n' "$T/probed" > "$T/probe-claude"; chmod +x "$T/probe-claude"
export ACCOUNT_NOW=$NOW ACCOUNT_CLAUDE="$T/probe-claude"
AP() { ACCOUNTS_FILE="$T/accounts.json" CLAUDE_TIER_CLAUDE_JSON="$T/tier-tight.json" python3 "$B/autofinish" --dry-run "$@"; }
pool 6 85 10 10; AP demo > "$T/out-w" 2>&1; AP smallrepo >> "$T/out-w" 2>&1
check "$(line "$T/out-w" a-ok)" "start (A)" "acct-c at 6 % runs A, though this login's own week reads 85 %"
check "$(line "$T/out-w" b-ok)" "skip: week tight (acct-a 85% used, pace 57.1%)" "B in a repo acct-c denies: the primary's week, named"
pool 69 85 10 10; AP demo > "$T/out-w" 2>&1
check "$(line "$T/out-w" a-ok)" "start (A)" "a secondary 12 points over pace but under its own ceiling (70 %): no pause — the ceiling is its gate"
pool 85 6 10 10; AP demo > "$T/out-w" 2>&1
check "$(line "$T/out-w" a-ok)" "start (A)" "acct-c over its ceiling: the next row, acct-a at 6 %"
pool 85 85 10 10; AP demo > "$T/out-w" 2>&1
check "$(line "$T/out-w" a-ok)" "skip: week tight (acct-a 85% used, pace 57.1%)" "  and acct-a at 85 %: paused on acct-a's week"
pool 85 6 90 10; AP demo > "$T/out-w" 2>&1
check "$(line "$T/out-w" a-ok)" "start (A)" "acct-c with no 5-hour room: the next row's week (acct-a at 6 %)"
pool 6 6 90 90; AP demo > "$T/out-w" 2>&1
case "$(line "$T/out-w" a-ok)" in "skip: no account (acct-c: 5h 90.0% > 50%"*"acct-a: 5h 90.0% > 50%"*) echo "  ok   no row may run: skip: no account, each row's reason";; *) echo "  FAIL no account: $(line "$T/out-w" a-ok)"; fails=$((fails+1));; esac
check "$(line "$T/out-w" override)" "start (C)" "  C's verdict is not gated (its start is: below, rule D's start)"
pool 6 6 10 10 7200; AP demo > "$T/out-w" 2>&1
check "$(line "$T/out-w" a-ok)" "start (A)" "readings two hours old: the dry run judges on them"
check "$([ -e "$T/probed" ] && echo probed || echo none)" "none" "  and no judging so far probed (--cached): no claude -p from a dry run"
pool 6 6 90 90 21600
python3 -c 'import json,sys; f=sys.argv[1]; d=json.load(open(f)); d["limits"]["five_hour_resets"]=float(sys.argv[2])-18000; json.dump(d,open(f,"w"))' "$HOME/.acct-c/usage-probe.json" "$NOW"
AP demo > "$T/out-w" 2>&1
check "$(line "$T/out-w" a-ok)" "start (A)" "acct-c read at 5h 90 % six hours ago, its window reset since: it reads 0 %, start (no overnight pause on a stale reading)"
rm -f "$HOME/.claude/usage-probe.json"; AP smallrepo > "$T/out-w" 2>&1
check "$(line "$T/out-w" b-ok)" "skip: week tight (acct-a 85% used, pace 57.1%)" "the primary with no reading: the default login's own (tier_check), as before"
printf '#!/bin/sh\necho nope\nexit 1\n' > "$T/acct-broken"; chmod +x "$T/acct-broken"
AUTOFINISH_ACCOUNT="$T/acct-broken" AP demo > "$T/out-w" 2>&1
case "$(line "$T/out-w" a-ok)" in "skip: week tight (85% used"*) echo "  ok   an unreadable pick: the default login's week, as before";; *) echo "  FAIL broken pick: $(line "$T/out-w" a-ok)"; fails=$((fails+1));; esac
CLAUDE_CODE_OAUTH_TOKEN=x CLAUDE_CONFIG_DIR="$HOME/.acct-c" AUTOFINISH_ACCOUNT="$T/acct-env" sh -c '
  printf "#!/bin/sh\nenv > %s\nexit 4\n" "$1/acct.env" > "$1/acct-env"; chmod +x "$1/acct-env"; '"$(printf %q "$B")"'/autofinish --dry-run demo' sh "$T" > /dev/null 2>&1
check "$(grep -cE '^(CLAUDE_CODE_OAUTH_TOKEN|CLAUDE_CONFIG_DIR)=' "$T/acct.env")" "0" "bin/account never inherits the caller's login variables (a token would be probed as every row)"
unset ACCOUNT_NOW ACCOUNT_CLAUDE; rm "$HOME/projects"

echo "every repo, and the log"
python3 "$B/autofinish" --dry-run --log > "$T/out-all" 2>&1; check "$?" 0 "all repos exits 0"
has "$T/out-all" "demo $(br a-ok) start (A)" "demo listed"
has "$T/out-all" "smallrepo $(br b-ok) start (B)" "smallrepo listed"
has "$T/out-all" "personal $(br p-doc) skip: off" "personal listed"
hasnt "$T/out-all" "nocheck" "a repo whose workflow.json is not checkpoint: true is left out"
L="$T/logs/autofinish-$(dateat "$NOW" +%Y-%m-%d).log"
check "$(wc -l < "$L" | tr -d ' ')" "$(wc -l < "$T/out-all" | tr -d ' ')" "one log line per verdict"
check "$(grep -cvE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}[+-][0-9:]{5} dry [^ ]+ claude/[^ ]+ (start \([ABCDEL]\)|wait: idle [0-9]+ min|skip: .+)$' "$L")" "0" "every log line is <iso> dry <repo> <branch> <verdict>"
has "$L" " dry demo $(br busy) skip: busy" "greppable by veto"
python3 "$B/autofinish" --dry-run demo > /dev/null 2>&1
check "$(wc -l < "$L" | tr -d ' ')" "$(wc -l < "$T/out-all" | tr -d ' ')" "without --log nothing is appended"

echo "the seam and the arguments"
python3 - "$B/autofinish" <<'EOF' > "$T/seam" 2>&1
import sys
from importlib.machinery import SourceFileLoader
m = SourceFileLoader("autofinish", sys.argv[1]).load_module()
try:
    m.start_runner("/tmp/x", "A")
    print("started")
except RuntimeError:
    print("refused")
EOF
check "$(cat "$T/seam")" "refused" "start_runner calls bin/autofinish-run, which refuses a path that is no claude/* worktree"
python3 "$B/autofinish" > /dev/null 2>&1; check "$?" 2 "no mode is a usage error"

echo "a repo whose opt-in lives in repos.json, not on its origin/main (2026-10-05)"
OV="$T/ov"; git init -q -b main "$OV" && git -C "$OV" commit -q --allow-empty -m one
git -C "$OV" remote add origin https://github.com/acme/shared.git
git -C "$OV" update-ref refs/remotes/origin/main HEAD
printf '{"repos": {"shared": {"github": "acme/shared", "workflow": {"checkpoint": true, "autofinish": "records", "records": ["TODO.md"], "autofinish_exclude": ["deploy/"]}}}}' > "$T/ov-repos.json"
check "$(AUTOFINISH_REPOS="$T/ov-repos.json" python3 - "$B/autofinish" "$OV" <<'EOF' 2>&1
import sys
from importlib.machinery import SourceFileLoader
m = SourceFileLoader("autofinish", sys.argv[1]).load_module()
print(m.repo_config(sys.argv[2], "main"))
EOF
)" "('records', ['TODO.md'], None, ['deploy/'])" "repo_config falls back to the repos.json opt-in, autofinish_exclude too"
check "$(AUTOFINISH_REPOS="$T/ov-repos.json" python3 - "$B/autofinish" "$OV" <<'EOF' 2>&1
import sys
from importlib.machinery import SourceFileLoader
m = SourceFileLoader("autofinish", sys.argv[1]).load_module()
print(m.repo_config(sys.argv[2], "main", m.git(sys.argv[2], "rev-parse", "HEAD"))[0])
EOF
)" "off" "  never at an earlier commit: repos.json only knows today, so the launch door stays shut (review, 2026-10-11)"

mkdir -p "$OV/.claude" && touch "$OV/.claude/no-workflow" && git -C "$OV" add .claude/no-workflow && git -C "$OV" commit -qm no && git -C "$OV" update-ref refs/remotes/origin/main HEAD
check "$(AUTOFINISH_REPOS="$T/ov-repos.json" python3 - "$B/autofinish" "$OV" <<'EOF' 2>&1
import sys
from importlib.machinery import SourceFileLoader
m = SourceFileLoader("autofinish", sys.argv[1]).load_module()
print(m.repo_config(sys.argv[2], "main")[0])
EOF
)" "off" "  but never beside .claude/no-workflow on origin/main"

# ---- E3 and E6: the switch, one worktree, the sweep, the override ---------------------------
export AUTOFINISH_STATE_DIR="$T/state"
AF="python3 $B/autofinish"
echo "arm, disarm, status (Sam, 2026-10-05: three hours dry, then armed)"
check "$($AF status)" "disarmed — verdicts and logs only; nothing starts (autofinish arm)" "disarmed is the default"
$AF arm --by tester > /dev/null
case "$($AF status)" in "armed by tester at 20"*) echo "  ok   arm: status names who and when";; *) echo "  FAIL arm: $($AF status)"; fails=$((fails+1));; esac
check "$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(sorted(d))' "$T/state/armed")" "['by', 'ts']" "  the state file is JSON {by, ts}"
$AF disarm > /dev/null
check "$($AF status | cut -d' ' -f1)" "disarmed" "disarm"
check "$([ -e "$T/state/armed" ] && echo there || echo gone)" "gone" "  the file is gone"

echo "one worktree: --worktree, --after, --session, --reply, and /autofinish now"
mk $D w-idle39 docs/w39.md "x"; echo > "$(gd $D w-idle39)/claude/last-reply"; ago "$(gd $D w-idle39)/claude/last-reply" 39.5
mk $D w-own docs/own.md "x"
# A live session that is not this shell: `session` registers $$, an ancestor of every autofinish
# run here, and an ancestor is never busy for it (the caller's own session running us).
sleep 600 & SLEEPER=$!; trap 'kill $SLEEPER 2>/dev/null; rm -rf "$T"' EXIT
echo "{\"pid\": $SLEEPER, \"sessionId\": \"$(sid w-own)\", \"cwd\": \"/elsewhere\", \"status\": \"busy\"}" > "$HOME/.claude/sessions/w-own.json"
mk $D w-anc docs/anc.md "x"; session w-anc busy
mk $D w-reply docs/reply.md "x"
mk $D now-ov bin/now.py "x"; echo '{"by": "sam", "ts": 1, "now": true}' > "$(gd $D now-ov)/claude/autofinish"
echo > "$(gd $D now-ov)/claude/last-reply"; ago "$(gd $D now-ov)/claude/last-reply" 5
mk $D ov-plain bin/plain.py "x"; echo '{"by": "sam", "ts": 1, "now": false}' > "$(gd $D ov-plain)/claude/autofinish"
echo > "$(gd $D ov-plain)/claude/last-reply"; ago "$(gd $D ov-plain)/claude/last-reply" 5
ghjson
one() { $AF --worktree "$(wtp $D "$1")" --dry-run "${@:2}" 2>&1 | sed "s|^demo $(br "$1") ||"; }
check "$(one a-ok)" "start (A)" "--worktree: the one worktree's verdict, as the dry run's"
check "$(one w-idle39)" "wait: idle 39 min" "39.5 min idle: wait"
s0=$SECONDS; v=$(one w-idle39 --after 60)
check "$v" "start (A)" "--after 60: judged a minute on (the pinned clock moves)"
check "$(( SECONDS - s0 < 30 ))" "1" "  and nothing slept"
check "$(one w-own)" "skip: busy (session $(sid w-own | cut -c1-8))" "a busy session on it: busy"
check "$(one w-own --session "$(sid w-own)")" "start (A)" "  unless it is the caller's own, at its turn's end (--session)"
check "$(one w-own --session "$(sid w-own | cut -c1-8)")" "start (A)" "  its first 8 do too"
check "$(one w-anc)" "start (A)" "  and a busy session among this process's ancestors (a hook, /autofinish's Bash) is the caller"
check "$($AF --dry-run demo 2>&1 | grep -F " $(br w-anc) " | sed "s|^demo $(br w-anc) ||")" "skip: busy (session $(sid w-anc | cut -c1-8))" "  the sweep's dry run has no caller: busy"
printf 'Built it.\n\nShall I launch it?\n' > "$T/reply.txt"
check "$(one w-reply --reply "$T/reply.txt")" "skip: last reply asks (ends in ?)" "--reply: the reply from the file, not the transcript"
check "$(one w-reply --reply "$T/no-such-file")" "start (A)" "  a missing file: the transcript's, as before"
check "$(one now-ov)" "start (C)" "/autofinish now: rule C starts at the turn's end, no 40 min"
check "$(one ov-plain)" "wait: idle 5 min" "plain /autofinish: rule C still waits for idle"
check "$($AF --worktree "$T/projects/$D" --dry-run 2>&1)" "demo main skip: not a claude/* worktree" "the primary checkout is no claude/* worktree"
$AF --worktree "$(wtp $D a-ok)" --log > /dev/null 2>&1
check "$(tail -1 "$L" | cut -d' ' -f2-)" "dry demo $(br a-ok) start (A)" "--log: the one line in the day's log"
check "$(grep -c " start demo" "$L")" "0" "  disarmed: nothing started"

echo "who may arm or override (review, 2026-10-05): never unattended; in a session, only Sam's typed /autofinish"
out=$(CLAUDE_UNATTENDED=dispatch $AF arm --by runner 2>&1); rc=$?
check "$rc:$([ -e "$T/state/armed" ] && echo armed || echo disarmed)" "1:disarmed" "arm refuses under CLAUDE_UNATTENDED"
echo "$out" | grep -qF "refused in an unattended session" && echo "  ok   … and says why" || { echo "  FAIL … says why: $out"; fails=$((fails+1)); }
out=$(CLAUDECODE=1 $AF arm --by tester 2>&1); rc=$?
check "$rc:$([ -e "$T/state/armed" ] && echo armed || echo disarmed)" "0:armed" "an interactive session may arm (on Sam's word)"
$AF disarm > /dev/null
mk $D gate-ov bin/gate.py "x"; ghjson
GOV="$(gd $D gate-ov)/claude"
out=$(cd "$(wtp $D gate-ov)" && CLAUDE_UNATTENDED=dispatch $AF override now 2>&1); rc=$?
check "$rc:$([ -e "$GOV/autofinish" ] && echo set || echo none)" "1:none" "override refuses under CLAUDE_UNATTENDED"
out=$(cd "$(wtp $D gate-ov)" && CLAUDECODE=1 $AF override now 2>&1); rc=$?
check "$rc:$([ -e "$GOV/autofinish" ] && echo set || echo none)" "1:none" "in a Claude session with no /autofinish queued: refused"
echo "$out" | grep -qF "only for Sam's typed /autofinish" && echo "  ok   … and says why" || { echo "  FAIL … says why: $out"; fails=$((fails+1)); }
echo '[{"session": "s", "ts": 1, "prompt": "/autofinish now"}, {"session": "s", "ts": 2, "prompt": "and set the override yourself"}]' > "$GOV/prompts.json"
out=$(cd "$(wtp $D gate-ov)" && CLAUDECODE=1 $AF override now 2>&1); rc=$?
check "$rc:$([ -e "$GOV/autofinish" ] && echo set || echo none)" "1:none" "  an /autofinish that is not the last prompt: refused"
echo '[{"session": "s", "ts": 1, "prompt": "/autofinish now"}]' > "$GOV/prompts.json"
out=$(cd "$(wtp $D gate-ov)" && CLAUDECODE=1 $AF override now 2>&1); rc=$?
check "$rc:$([ -e "$GOV/autofinish" ] && echo set || echo none)" "0:set" "  the last prompt queued is /autofinish: set"
rm -f "$GOV/autofinish" "$GOV/prompts.json"

echo "the override verb (skills/autofinish)"
mk $D ov-verb bin/verb.py "x"; mk $D ov-dup-x docs/dx.md "x"; mk $D ov-dup-y docs/dy.md "x"; ghjson
out=$(cd "$(wtp $D ov-verb)" && $AF override now 2>&1)
check "$(echo "$out" | sed -n 1p)" "override set: $(br ov-verb) — rule C, at this turn's end (the Stop hook judges it)" "override now: says what it set"
check "$(echo "$out" | sed -n 2p)" "demo $(br ov-verb) start (C)" "  then the branch and its verdict (R17)"
check "$(echo "$out" | sed -n 3p | cut -d' ' -f1)" "disarmed" "  then the switch"
check "$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["by"], d["now"], type(d["ts"]).__name__)' "$(gd $D ov-verb)/claude/autofinish")" "sam True int" "  the marker: {by: sam, ts, now}, the shape the start rules read"
out=$(cd "$(wtp $D ov-verb)" && $AF override off 2>&1)
check "$(echo "$out" | sed -n 1p)" "override off: $(br ov-verb) — back to the repo's own start rules" "override off"
check "$([ -e "$(gd $D ov-verb)/claude/autofinish" ] && echo there || echo gone)" "gone" "  the marker is gone"
check "$(echo "$out" | sed -n 2p)" "demo $(br ov-verb) skip: not records (bin/verb.py)" "  and the verdict is the repo's own again"
out=$(cd "$T/projects/$D" && $AF override ov-verb 2>&1)
check "$(echo "$out" | sed -n 1p)" "override set: $(br ov-verb) — rule C, after 40 min idle, or at once on the declared line" "override <topic> from the primary: that branch's worktree"
check "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["now"])' "$(gd $D ov-verb)/claude/autofinish")" "False" "  a plain override: now false"
out=$(cd "$T/projects/$D" && $AF override 2>&1); rc=$?
check "$rc" "1" "override on the primary's main is refused"
echo "$out" | grep -qF "not a claude/* worktree" && echo "  ok   … and says why" || { echo "  FAIL … says why: $out"; fails=$((fails+1)); }
out=$(cd "$T/projects/$D" && $AF override ov-dup 2>&1); rc=$?
check "$rc:$(echo "$out" | grep -c "0 claude/\* worktrees of demo match .ov-dup.")" "1:1" "  a word that names no branch is refused, and says so"
out=$(cd "$T/projects/$D" && $AF override dup-x 2>&1); check "$?:$(echo "$out" | sed -n 1p | cut -d: -f1)" "0:override set" "  a topic's last words name it"
rm -f "$(gd $D ov-dup-x)/claude/autofinish"
rm -f "$(gd $D ov-verb)/claude/autofinish"

echo "the sweep: always logged; armed, one start, never the same tip twice (R7, R12)"
newrepo sw '{"checkpoint": true, "main": "main", "records": ["docs/"]}'
for t in s1 s2 s3; do mk sw $t docs/$t.md "x"; done
mk sw s-wait docs/w.md "x"; echo > "$(gd sw s-wait)/claude/last-reply"; ago "$(gd sw s-wait)/claude/last-reply" 5
ghjson
echo '{"repos": {"sw": {}}}' > "$T/repos-sw.json"
SW() { AUTOFINISH_REPOS="$T/repos-sw.json" AUTOFINISH_LOG_DIR="$T/logs-sw" $AF "$@"; }
LS="$T/logs-sw/autofinish-$(dateat "$NOW" +%Y-%m-%d).log"
out=$(SW --sweep 2>&1)
check "$out" "" "disarmed: the sweep prints nothing (launchd's log stays quiet)"
check "$(grep -c ' dry sw ' "$LS")" "4" "  and logs every worktree's verdict"
check "$(grep -c ' dry sw .* start (A)$' "$LS")" "3" "  three of them start (A)"
check "$(grep -cv ' dry ' "$LS")" "0" "  nothing but dry lines"
$AF arm --by tester > /dev/null
out=$(SW --sweep 2>&1)
check "$(echo "$out" | grep -c '^start sw claude/')" "1" "armed: one start — the cap"
check "$(grep -cE '^[0-9T:+-]{25} start sw claude/laptop/2026-10-05-s[123] A$' "$LS")" "1" "  logged as <iso> start <repo> <branch> <rule>"
check "$(wc -l < "$T/default-runner.calls" | tr -d ' ')" "1" "  the runner called once"
first=$(grep ' start sw ' "$LS" | cut -d' ' -f4)
check "$(wc -l < "$T/state/tried.jsonl" | tr -d ' ')" "1" "  its tip remembered"
SW --sweep > /dev/null 2>&1
second=$(grep ' start sw ' "$LS" | tail -1 | cut -d' ' -f4)
check "$(grep -c ' start sw ' "$LS"):$([ "$first" != "$second" ] && echo other)" "2:other" "the next sweep never retries that tip: it takes the next branch"
printf '#!/bin/sh\necho "$1 $2" >> "%s"\n' "$T/runner.calls" > "$T/runner"; chmod +x "$T/runner"
out=$(AUTOFINISH_RUNNER="$T/runner" SW --sweep 2>&1)
check "$(echo "$out" | cut -d' ' -f1-2)" "start sw" "a runner that starts: one start line"
third=$(echo "$out" | cut -d' ' -f3)
check "$(cat "$T/runner.calls")" "$(cd "$T/projects/sw/.claude/worktrees/$(echo "$third" | sed 's|.*-||')" && pwd -P) A" "  the runner got <worktree> <rule>"
check "$(grep -c " start sw $third A$" "$LS")" "1" "  logged as <iso> start <repo> <branch> <rule>"
out=$(AUTOFINISH_RUNNER="$T/runner" SW --sweep 2>&1)
check "$out" "" "every start-ready tip tried: the sweep starts nothing more"
check "$(wc -l < "$T/runner.calls" | tr -d ' ')" "1" "  the runner ran once in all"
# R7: origin moves between the sweep's dry run and its start → the start judges again and skips
mk sw r7 docs/r7.md "x"; ghjson
git clone -q "$T/origin-sw.git" "$T/sw-elsewhere" && git -C "$T/sw-elsewhere" checkout -q "$(br r7)"
out=$(AUTOFINISH_RUNNER="$T/runner" AUTOFINISH_TEST_BEFORE_START="echo z >> $T/sw-elsewhere/docs/r7.md && git -C $T/sw-elsewhere commit -qam other-mac && git -C $T/sw-elsewhere push -q" \
      SW --sweep 2>&1)
check "$(grep -c " dry sw $(br r7) start (A)$" "$LS")" "1" "R7: the sweep's dry run judged start …"
check "$(tail -1 "$LS" | cut -d' ' -f2-)" "dry sw $(br r7) skip: moved on origin" "  … origin moved before the start: judged again, skipped, logged"
check "$out:$(wc -l < "$T/runner.calls" | tr -d ' ')" ":1" "  and the runner never ran"
# R12: two sweeps never start two runners — the lock
mk sw r12a docs/r12a.md "x"; mk sw r12b docs/r12b.md "x"; ghjson
printf '#!/bin/sh\necho "$1 $2" >> "%s"\nsleep 3\n' "$T/slow.calls" > "$T/slow"; chmod +x "$T/slow"
(AUTOFINISH_RUNNER="$T/slow" SW --sweep > "$T/sweep-a" 2>&1) & SWEEP_A=$!
i=0; while [ ! -s "$T/slow.calls" ] && [ $i -lt 300 ]; do sleep 0.1; i=$((i+1)); done
out=$(AUTOFINISH_RUNNER="$T/slow" SW --sweep 2>&1)
wait "$SWEEP_A"
echo "$out" | grep -q "holds $T/state/sweep.lock; this tick does nothing" && echo "  ok   R12: a second sweep meets the first's lock and does nothing" \
  || { echo "  FAIL R12 second sweep: $out"; fails=$((fails+1)); }
check "$(wc -l < "$T/slow.calls" | tr -d ' ')" "1" "  one runner between them"
check "$([ -e "$T/state/sweep.lock" ] && echo held || echo free)" "free" "  and the lock is freed after"
mkdir "$T/state/sweep.lock"; echo 99999 > "$T/state/sweep.lock/pid"
out=$(AUTOFINISH_RUNNER="$T/slow" $AF --worktree "$(wtp sw r12b)" 2>&1)
echo "$out" | grep -q "holds the lock; the next sweep looks again" && echo "  ok   a --worktree start meets the lock too" \
  || { echo "  FAIL --worktree and the lock: $out"; fails=$((fails+1)); }
touch -t 202001010000 "$T/state/sweep.lock"
out=$(AUTOFINISH_RUNNER="$T/slow" SW --sweep 2>&1)
check "$(echo "$out" | cut -d' ' -f1-2)" "start sw" "  a lock older than 20 min is a sweep that died: taken over"
printf '#!/bin/sh\necho no screen >&2; exit 1\n' > "$T/broken"; chmod +x "$T/broken"
mk sw failing docs/failing.md "x"; ghjson
out=$(AUTOFINISH_RUNNER="$T/broken" $AF --worktree "$(wtp sw failing)" 2>&1)
check "$(echo "$out" | tail -1)" "failed sw $(br failing) A (RuntimeError: no screen)" "a runner that fails: a failed line, the sweep goes on"
check "$(grep -c "\"branch\": \"$(br failing)\"" "$T/state/tried.jsonl")" "0" "  a failed start is not remembered …"
out=$(AUTOFINISH_RUNNER="$T/runner" $AF --worktree "$(wtp sw failing)" 2>&1)
check "$(echo "$out" | tail -1)" "start sw $(br failing) A" "  … so the next try starts it"
# a tip started once whose run dispatch refused (gate refused) may start again
FTIP=$(git -C "$(wtp sw failing)" rev-parse HEAD)
echo "{\"tip\": \"$FTIP\", \"session\": \"x\", \"ended\": \"2026-10-05T10:00:00+02:00\", \"outcome\": \"never-started\", \"gate\": \"refused\"}" \
  > "$(gd sw failing)/claude/autofinish.json"
out=$(AUTOFINISH_RUNNER="$T/runner" $AF --worktree "$(wtp sw failing)" 2>&1)
check "$(echo "$out" | tail -1)" "start sw $(br failing) A" "a started tip whose run dispatch refused starts again"
sedi 's/refused/G4/' "$(gd sw failing)/claude/autofinish.json"
n=$(wc -l < "$T/runner.calls" | tr -d ' ')
out=$(AUTOFINISH_RUNNER="$T/runner" $AF --worktree "$(wtp sw failing)" 2>&1)
check "$(wc -l < "$T/runner.calls" | tr -d ' '):$(echo "$out" | grep -c '^start ')" "$n:0" "  one that ran and stopped does not"

echo "rule D's start: memo stand --apply first, in the worktree (review, 2026-10-05)"
mk $D d-apply docs/apply-due-design.md "$DLIST"; mk $D d-applyfail docs/fail-due-design.md "$DLIST"; ghjson
: > "$T/memo.calls"; : > "$T/runner.calls"
out=$(AUTOFINISH_RUNNER="$T/runner" $AF --worktree "$(wtp $D d-apply)" 2>&1)
check "$(echo "$out" | head -1)" "demo $(br d-apply) start (D)" "a due doc: start (D)"
check "$(sed -n 1p "$T/memo.calls")" "status --json docs/apply-due-design.md" "  judged with a fetch: a start follows (memo status without --no-fetch)"
check "$(grep -c -- '^stand --apply docs/apply-due-design.md$' "$T/memo.calls")" "1" "  memo stand --apply on the due doc"
check "$(git -C "$(wtp $D d-apply)" log -1 --format=%B | grep -c '^Stood-By: autofinish$')" "1" "  committed in the worktree, Stood-By"
check "$(cat "$T/runner.calls")" "$(cd "$(wtp $D d-apply)" && pwd -P) D" "  then the runner, rule D"
check "$(echo "$out" | tail -1)" "start demo $(br d-apply) D" "  logged as a start"
check "$(grep -c "^status" "$T/memo.calls")" "1" "  judged once, not again before the start (F9)"
out=$(AUTOFINISH_RUNNER="$T/runner" $AF --worktree "$(wtp $D d-applyfail)" 2>&1)
case "$(echo "$out" | tail -1)" in "failed demo $(br d-applyfail) D (RuntimeError: memo stand --apply docs/fail-due-design.md: memo: replies written but not committed)") echo "  ok   an apply that fails: a failed start …";;
  *) echo "  FAIL an apply that fails: $out"; fails=$((fails+1));; esac
check "$(wc -l < "$T/runner.calls" | tr -d ' ')" "1" "  … and no runner"

echo "no account at a start: refused before rule D's stand (review, 2026-10-08)"
ln -s "$T/projects" "$HOME/projects"
mk $D d-noacct docs/noacct-due-design.md "$DLIST"; ghjson
: > "$T/memo.calls"; : > "$T/runner.calls"; pool 6 6 90 90
out=$(ACCOUNTS_FILE="$T/accounts.json" ACCOUNT_NOW=$NOW ACCOUNT_CLAUDE=false AUTOFINISH_RUNNER="$T/runner" $AF --worktree "$(wtp $D d-noacct)" 2>&1)
hasnt "$T/memo.calls" "stand" "no memo stand --apply: nothing committed for a run no account could take"
check "$(wc -l < "$T/runner.calls" | tr -d ' ')" "0" "  the runner never called"
has "$T/logs/autofinish-$(dateat "$NOW" +%Y-%m-%d).log" "demo $(br d-noacct) skip: no account (acct-c: 5h 90.0% > 50%" "  logged with each row's reason"
check "$(grep -c "\"branch\": \"$(br d-noacct)\"" "$T/state/tried.jsonl")" "0" "  and not remembered: the next tick tries again"
echo "the gate's pick is the runner's login (review, 2026-10-08)"
printf '#!/bin/sh\necho "$CLAUDE_CONFIG_DIR" >> "%s"\n' "$T/runner-env.calls" > "$T/runner-env"; chmod +x "$T/runner-env"
mk $D d-pick docs/pick-due-design.md "$DLIST"; ghjson
: > "$T/runner-env.calls"; pool 6 6 10 10
ACCOUNTS_FILE="$T/accounts.json" ACCOUNT_NOW=$NOW ACCOUNT_CLAUDE=false AUTOFINISH_RUNNER="$T/runner-env" $AF --worktree "$(wtp $D d-pick)" > /dev/null 2>&1
check "$(cat "$T/runner-env.calls")" "$HOME/.acct-c" "acct-c picked at the start: the runner is handed its dir, not left to pick again"
rm "$HOME/projects"

echo "a runner that died: recorded first, then judged once more (docs/autofinish-died-2026-10-07.md)"
newrepo dead '{"checkpoint": true, "main": "main", "records": ["docs/"]}'
echo '{"repos": {"dead": {}}}' > "$T/repos-dead.json"
DD() { AUTOFINISH_REPOS="$T/repos-dead.json" AUTOFINISH_LOG_DIR="$T/logs-dead" $AF "$@"; }
DS=ffffffff-0000-4000-8000-000000000000
REC="$T/projects/dead/.git/claude/autofinished"
# diedrec <topic> <tip> [days ago]: the state bury() leaves — ended, died — and its line in autofinished;
# ended 5 min before the clock, not the real time: a prompt at NOW - 60 s must read as since it
diedrec() {
  python3 - "$(gd dead "$1")/claude/autofinish.json" "$DS" "$2" "${3:-0}" "$NOW" <<'EOF'
import datetime, json, sys
iso = (datetime.datetime.fromtimestamp(int(sys.argv[5])).astimezone() - datetime.timedelta(days=int(sys.argv[4]), minutes=5)).isoformat(timespec="seconds")
json.dump({"started": iso, "session": sys.argv[2], "tip": sys.argv[3], "by": "sweep", "rule": "A", "window": "finish · x",
           "ended": iso, "outcome": "died", "pr": None, "gate": None}, open(sys.argv[1], "w"))
print(iso)
EOF
}
dline() { mkdir -p "$(dirname "$REC")"; echo "$1 died $(br "$2") ${3:0:7} dispatch: busy" >> "$REC"; }
curate() { git -C "$(wtp dead "$1")" reset -q --soft main && git -C "$(wtp dead "$1")" commit -qm "Docs: curated $1" -m "Deployed: no"; }
mk dead dd-unrec docs/u.md "x"
python3 - "$(gd dead dd-unrec)/claude/autofinish.json" "$DS" "$(git -C "$(wtp dead dd-unrec)" rev-parse HEAD)" "$NOW" <<'EOF'
import datetime, json, sys
iso = datetime.datetime.fromtimestamp(int(sys.argv[4]) - 61 * 60).astimezone().isoformat(timespec="seconds")
json.dump({"started": iso, "session": sys.argv[2], "tip": sys.argv[3], "by": "sweep", "rule": "A", "window": "finish · x",
           "ended": None, "outcome": None, "pr": None, "gate": None}, open(sys.argv[1], "w"))
EOF
echo "{\"session\": \"$DS\", \"branch\": \"$(br dd-unrec)\", \"seen\": 0}" > "$(gd dead dd-unrec)/claude/owner.json"
touch "$(gd dead dd-unrec)/claude/finishing"
mk dead dd-moved docs/m.md "x"; T0=$(git -C "$(wtp dead dd-moved)" rev-parse HEAD); curate dd-moved
E=$(diedrec dd-moved "$T0"); dline "$E" dd-moved "$T0"
mk dead dd-desc docs/d.md "x"; T1=$(git -C "$(wtp dead dd-desc)" rev-parse HEAD)
echo y >> "$(wtp dead dd-desc)/docs/d.md"; git -C "$(wtp dead dd-desc)" commit -qam checkpoint -m "Claude-Session: ffffffff"
git -C "$(wtp dead dd-desc)" push -q; git -C "$(wtp dead dd-desc)" reset -q --hard "$T1"
E=$(diedrec dd-desc "$T1"); dline "$E" dd-desc "$T1"
mk dead dd-other docs/o.md "x"; T2=$(git -C "$(wtp dead dd-other)" rev-parse HEAD)
echo y >> "$(wtp dead dd-other)/docs/o.md"; git -C "$(wtp dead dd-other)" commit -qam "from the other Mac"
git -C "$(wtp dead dd-other)" push -q; git -C "$(wtp dead dd-other)" reset -q --hard "$T2"
E=$(diedrec dd-other "$T2"); dline "$E" dd-other "$T2"
mk dead dd-other-tip docs/p.md "x"; T5=$(git -C "$(wtp dead dd-other-tip)" rev-parse HEAD)
E=$(diedrec dd-other-tip "$T5"); dline "$(diedrec dd-other-tip "$T5" 1)" dd-other-tip 0123456789; dline "$E" dd-other-tip "$T5"
diedrec dd-other-tip "$T5" > /dev/null
mk dead dd-twice docs/t.md "x"; T3=$(git -C "$(wtp dead dd-twice)" rev-parse HEAD)
E=$(diedrec dd-twice "$T3"); dline "$(diedrec dd-twice "$T3" 1)" dd-twice "$T3"; dline "$E" dd-twice "$T3"; diedrec dd-twice "$T3" > /dev/null
mk dead dd-same docs/s.md "x"; T4=$(git -C "$(wtp dead dd-same)" rev-parse HEAD)
echo "{\"ts\": \"x\", \"repo\": \"$T/projects/dead\", \"branch\": \"$(br dd-same)\", \"tip\": \"$T4\", \"rule\": \"A\", \"kind\": \"start\"}" >> "$T/state/tried.jsonl"
E=$(diedrec dd-same "$T4"); dline "$E" dd-same "$T4"
ghjson
DD --dry-run dead > "$O" 2>&1
check "$(line $O dd-unrec)" "skip: died, not recorded yet (no dispatch record 61 min after its start; session ffffffff) — an armed sweep records it" \
  "the dry run reports a dead, unrecorded run"
check "$(grep -c " died $(br dd-unrec) " "$REC")" "0" "  and writes nothing"
check "$(line $O dd-moved)" "skip: died mid-curation (local rewritten since ${T0:0:7}; $(br dd-moved)-raw may hold it) — waits for a prompt" \
  "origin at the dead run's tip, local curated by it: mid-curation, never a /finish that fails its lease (review 2026-10-08)"
check "$(line $O dd-desc)" "start (A)" "origin's tip a descendant committed by that session: no 'moved', judged as usual"
check "$(line $O dd-other)" "skip: moved on origin" "  a commit by anyone else on origin: moved, as before"
check "$(line $O dd-twice)" "skip: died twice ($(dateat $((NOW - 300)) +%Y-%m-%d)) — waits for a prompt" "a second death in a row: died twice"
check "$(line $O dd-other-tip)" "start (A)" "  two deaths on different tips are no pattern: judged once more (review 2026-10-08)"
echo "[{\"session\": \"someone\", \"ts\": $((NOW - 60)), \"prompt\": \"go on\"}]" > "$(gd dead dd-twice)/claude/prompts.json"
ago "$(gd dead dd-twice)/claude/prompts.json" 60
check "$(DD --dry-run dead | line /dev/stdin dd-twice)" "start (A)" "  a prompt since lifts it"
python3 - "$B/autofinish" "$T/projects/dead" "$(br dd-desc)" <<'EOF' > "$T/since"
import sys
from importlib.machinery import SourceFileLoader
from pathlib import Path
m = SourceFileLoader("autofinish", sys.argv[1]).load_module()
seen = {}
real = m.github_state
def spy(repo, branch, since):
    seen[branch] = since
    return real(repo, branch, since)
m.github_state = spy
m.dry_run("dead", Path(sys.argv[2]))
wt = Path(sys.argv[2]) / ".claude/worktrees/dd-desc"
head = float(m.git(wt, "log", "-1", "--format=%ct", "HEAD"))
# the comments GitHub returns: the death's own, and Sam's after the tip
del m.os.environ["AUTOFINISH_GITHUB"]
m.common.repo_slug, m.common.token = (lambda u: "o/r"), (lambda: "tok")
def api(method, path, tok=None, body=None):
    if "/pulls?" in path:
        return 200, [{"number": 7, "title": "WIP: x", "draft": False}]
    if "/issues/7/comments" in path:
        return 200, [{"body": m.DIED_HEAD + " — `/finish x`"}, {"body": "don't launch this yet"}]
    return 200, []
m.common.api = api
gh = m.github_state(Path(sys.argv[2]), "b", head)
print("late enough" if seen[sys.argv[3]] == head and gh["activity"] == 1 else (seen, head, gh))
EOF
check "$(cat "$T/since")" "late enough" "  GitHub's quiet counts from the tip, a comment before the burial still speaks; only the death's own is none (review 2026-10-08)"
: > "$T/runner.calls"
out=$(AUTOFINISH_RUNNER="$T/runner" DD --worktree "$(wtp dead dd-same)" 2>&1)
check "$(echo "$out" | tail -1)" "start dead $(br dd-same) A" "a tip started once whose run died starts again"
was=$($AF status | cut -d' ' -f1); $AF disarm > /dev/null
DD --sweep > /dev/null 2>&1
check "$(grep -c "^[^ ]* died $(br dd-unrec) " "$REC")" "0" "a disarmed sweep buries nothing: verdicts and logs only (review 2026-10-08)"
$AF arm --by tester > /dev/null
out=$(AUTOFINISH_RUNNER="$T/runner" DD --sweep 2>&1)
[ "$was" = armed ] || $AF disarm > /dev/null
check "$(echo "$out" | head -1)" "died dead $(br dd-unrec) — no dispatch record 61 min after its start" "an armed sweep records the dead run first"
check "$(grep -c "^[^ ]* died $(br dd-unrec) " "$REC")" "1" "  one died line in autofinished"
check "$([ -f "$(gd dead dd-unrec)/claude/owner.json" ] && echo held || echo free):$([ -e "$(gd dead dd-unrec)/claude/finishing" ] && echo marker || echo none)" \
  "free:none" "  the dead session's lock and marker gone"
has "$HOME/Library/Logs/claude-weekly/autofinish-$(date +%Y-%m-%d).log" "run dead $(br dd-unrec) died session=ffffffff" "  logged in the runner's shape"
check "$(grep " dry dead $(br dd-unrec) " "$T/logs-dead/autofinish-$(dateat "$NOW" +%Y-%m-%d).log" | tail -1 | cut -d' ' -f5-)" "start (A)" \
  "  then judged once more in the same sweep"

echo "the sweep lock is dropped only by its holder"
python3 - "$B/autofinish" <<'EOF' > "$T/droplock" 2>&1
import os, sys
from importlib.machinery import SourceFileLoader
m = SourceFileLoader("autofinish", sys.argv[1]).load_module()
lock = m.STATE / "sweep.lock"
lock.mkdir(parents=True)
(lock / "pid").write_text("99999")
m.drop_lock()
print("kept" if lock.exists() else "dropped")
(lock / "pid").write_text(str(os.getpid()))
m.drop_lock()
print("kept" if lock.exists() else "dropped")
EOF
check "$(cat "$T/droplock" | tr '\n' ' ')" "kept dropped " "another pid's lock (one that took over a dead sweep's) stays; our own goes"
$AF disarm > /dev/null

echo "the launchd job (the overlay's bootstrap.sh --schedule)"
# The overlay schedules the sweep where one is installed (install.sh --schedule refuses there): its
# bootstrap.sh, found through the core's legacy root; none here, the case is skipped, said so.
OVL=$(REGATTA_LEGACY="$SUITE_OVERLAY" python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import common; o = common.legacy_root(); print(o if o and (o / "bootstrap.sh").is_file() else "")' "$CORE")
# through() too: the job goes behind claude-host once this Mac's sitting is done (none here: a scratch HOME)
[ -n "$OVL" ] && plist=$(C="$HOME/projects/$(basename "$OVL")"; SELF="$OVL"; eval "$(sed -n '/^through()/,/^}/p;/^autofinish_plist()/,/^}/p' "$OVL/bootstrap.sh")"; autofinish_plist)
[ -n "$OVL" ] && echo "$plist" > "$T/af.plist"
[ -n "$OVL" ] || echo "  --   no overlay bootstrap.sh here: its plist case skipped"
if [ -n "$OVL" ] && command -v plutil >/dev/null; then
  plutil -lint "$T/af.plist" >/dev/null 2>&1 && echo "  ok   the plist lints" || { echo "  FAIL plist lint"; fails=$((fails+1)); }
  check "$(plutil -extract Label raw -o - "$T/af.plist" | sed 's/^.*\.autofinish$/<prefix>.autofinish/')" "<prefix>.autofinish" "  label <the overlay's label prefix>.autofinish"
  check "$(plutil -extract StartInterval raw -o - "$T/af.plist")" "600" "  every 10 min"
  check "$(plutil -extract RunAtLoad raw -o - "$T/af.plist")" "true" "  and at load"
  check "$(for k in 0 1 2; do plutil -extract ProgramArguments.$k raw -o - "$T/af.plist"; done | tr '\n' ' ')" \
    "/usr/bin/python3 $HOME/projects/$(basename "$OVL")/bin/autofinish --sweep " "  the primary checkout's autofinish --sweep, under \$HOME"
  check "$(plutil -extract StandardOutPath raw -o - "$T/af.plist")" "$HOME/Library/Logs/claude-weekly/autofinish-launchd.log" "  logs in claude-weekly"
fi

echo "the landing ladder (skipper-modes S3b): rule M for a dnd or yolo branch, held_slice for what it holds"
newrepo modes '{"checkpoint": true, "main": "main", "records": ["docs/"], "autofinish_exclude": ["hooks/"]}'
mkdir -p .helloworld && printf -- '- check: true\n- physical: none\n' > AGENTS.md && printf '# published\npub.md\n' > .helloworld/allowlist.txt
echo '{"a": 1}' > docs/old.json && git add -A && git commit -qm "contract, twin, data" && git push -q origin main
cd "$T" || exit 1
M=modes; RUNS="$HOME/Library/Logs/claude-weekly/run-seed-runs"; mkdir -p "$RUNS"
moderec() { printf '{"branch": "%s", "started": 1, "task_mode": "%s", "repo": "%s"}\n' "$(br "$1")" "$2" "$T/projects/$M" > "$RUNS/$1.json"; }
mk $M m-code bin/x.py "print(1)"; moderec m-code dnd
mk $M m-yolo bin/y.py "print(1)"; moderec m-yolo yolo
mk $M m-ask docs/a.md "a record"; moderec m-ask ask
mk $M m-ask-due docs/due-m.md "$DLIST"; moderec m-ask-due ask
mk $M m-none bin/z.py "print(1)"
mk $M m-taken docs/taken-m.md "$DLIST"; moderec m-taken dnd
mk $M m-taken-default docs/taken-d.md "$DLIST"
mk $M m-open docs/stands-m.md "$DLIST"; moderec m-open dnd
mk $M m-stray TODO.md "- [ ] later"; moderec m-stray yolo
mk $M m-bin docs/blob.bin "x"; printf 'a\0b' > "$(wtp $M m-bin)/docs/blob.bin"; moderec m-bin yolo
git -C "$(wtp $M m-bin)" commit -qam "binary" -m "Deployed: no" && git -C "$(wtp $M m-bin)" push -q
mk $M m-start-rec bin/s.py "print(1)"; moderec m-start-rec dnd
mk $M m-live docs/taken-l.md "$DLIST" "Deployed: the pack to Drive"; moderec m-live dnd
printf '{"branch": "%s", "started": 9, "repo": "%s"}\n' "$(br m-start-rec)" "$T/projects/$M" > "$RUNS/m-start-rec-finish.json"
mk $M hs-money docs/cost.md 'it costs $40 a month; a model run is $10 ($0.19 effective); `$5` in code; | $0 |'
mk $M hs-cost docs/cheap.md 'a model run is $10 ($0.19 effective), a table cell | $0 |, and `echo $1`'
mk $M hs-gate hooks/h.py "print(1)"
mk $M hs-pub pub.md "public words"
mk $M hs-del docs/new.md "x"; git -C "$(wtp $M hs-del)" rm -q docs/old.json && git -C "$(wtp $M hs-del)" commit -qm "drop the data" && git -C "$(wtp $M hs-del)" push -q
mk $M hs-yolo docs/y.md "  Taken unattended (Sam's yolo, 2026-10-22): A"
ghjson
python3 "$B/autofinish" --dry-run "$T/projects/$M" > "$T/out-m" 2>&1
check "$(line "$T/out-m" m-code)" "start (M)" "code in a records repo, the ship in dnd → M (any shape: the mode is the owner's word)"
check "$(line "$T/out-m" m-yolo)" "start (M)" "  in yolo → M"
check "$(line "$T/out-m" m-ask)" "start (A)" "a branch in mode ask is judged by the rules (its runner holds every start)"
check "$(line "$T/out-m" m-ask-due)" "skip: asks (docs/due-m.md: memo due, but mode ask — nobody answers it but Sam)" \
  "  but rule D never stands a due doc in mode ask: a stand would answer for the owner (landing review 8)"
check "$(line "$T/out-m" m-none)" "skip: not records (bin/z.py)" "no sent task: the rules, unchanged"
check "$(line "$T/out-m" m-taken)" "start (M)" "a taken doc in mode dnd: no veto, M"
check "$(line "$T/out-m" m-taken-default)" "skip: asks (docs/taken-d.md: memo taken)" "  with no mode, a taken doc still never starts (yolo-veto D1 for default)"
check "$(line "$T/out-m" m-open)" "skip: asks (docs/stands-m.md: memo stands-at — lands once nothing is open)" "an open item in mode dnd: skip"
check "$(line "$T/out-m" m-stray)" "skip: asks (TODO.md: - [ ])" "  an asks line outside a D-list doc: skip, whatever the mode"
check "$(line "$T/out-m" m-bin)" "skip: binary (docs/blob.bin)" "never a binary, whatever the mode"
check "$(line "$T/out-m" m-start-rec)" "start (M)" "a later --start record (autofinish's own launch) does not hide the build run's mode"
check "$(line "$T/out-m" m-live)" "start (M)" "a deployed dnd branch with a taken doc: rule M, never L's --by sweep (landing review 18)"
CLAUDE_TIER_CLAUDE_JSON="$T/tier-tight.json" python3 "$B/autofinish" --dry-run "$T/projects/$M" > "$T/out-mt" 2>&1
case "$(line "$T/out-mt" m-code)" in "skip: week tight (85% used"*) echo "  ok   the week's pause holds rule M too";; *) echo "  FAIL M paused: $(line "$T/out-mt" m-code)"; fails=$((fails+1));; esac
check "$(line "$T/out-mt" m-live)" "start (M)" "  …but not a deployed one: live ahead of main is drift, as rule L"
python3 - "$B/autofinish" "$T/projects/$M" "$T/projects/demo" "$(wtp $M m-code)" "$(wtp $D a-ok)" "$T/projects/$M/.claude/worktrees" <<'PYHELD' > "$T/held" 2>&1
import os, sys
from importlib.machinery import SourceFileLoader
m = SourceFileLoader("autofinish", sys.argv[1]).load_module()
repo, demo, code, aok, wts = sys.argv[2:7]
w = lambda t: os.path.join(wts, t)
for wt, mode in ((code, "dnd"), (code, "yolo"), (code, "ask"), (code, "default"), (code, None), (w("hs-money"), "dnd"),
                 (w("hs-cost"), "dnd"), (w("hs-gate"), "dnd"), (w("hs-gate"), "yolo"), (w("hs-pub"), "dnd"), (w("hs-del"), "dnd"),
                 (w("hs-yolo"), "dnd"), (w("hs-yolo"), "yolo")):
    print(m.held_slice(repo, wt, "main", mode))
print(m.held_slice(demo, aok, "main", "dnd"))
m.LAUNCHER = "modes"
print(m.held_slice(repo, w("hs-gate"), "main", "yolo"))
print(m.runner_by(code, "M"), m.runner_by(w("hs-cost"), "M"))
PYHELD
check "$(sed -n 1,5p "$T/held" | tr '\n' '|')" "None|None|mode ask — nothing lands by itself|mode default — a taken answer never lands there (yolo-veto D1)|mode default — a taken answer never lands there (yolo-veto D1)|" \
  "held_slice: plain code lands under dnd and yolo; ask, default and no mode hold"
check "$(sed -n 6p "$T/held")" 'money in the diff (docs/cost.md: $4)' "dnd holds money in the prose a branch adds"
check "$(sed -n 7p "$T/held")" "None" "  a model cost (\$list (\$eff effective)), a bare \$0 and a code span are no money"
check "$(sed -n 8,9p "$T/held" | tr '\n' '|')" "a gated path (hooks/h.py: autofinish_exclude or in_place)|a gated path (hooks/h.py: autofinish_exclude or in_place)|" \
  "dnd and yolo both hold autofinish_exclude: yolo stops at what every session's hooks run (the landing review)"
check "$(sed -n 10p "$T/held")" "a public publish (pub.md goes to the public twin)" "dnd holds a path the public twin's allowlist publishes"
check "$(sed -n 11p "$T/held")" "a deletion of data (docs/old.json)" "dnd holds a deleted data file"
check "$(sed -n 12,13p "$T/held" | tr '\n' '|')" "an answer taken under yolo, the ship now dnd (docs/y.md)|None|" "dnd holds a yolo-taken answer (no holds were applied to it); yolo lands it"
check "$(sed -n 14p "$T/held")" "a physical repo (physical: no line in the contract)" "dnd in a repo whose contract has no physical: none holds"
check "$(sed -n 15p "$T/held")" "the launcher's own gate (hooks/h.py)" "yolo still holds the launcher's own gates: no branch lands the gate it is judged by"
check "$(sed -n 16p "$T/held")" "dnd sweep" "runner_by for rule M: the branch's mode, or sweep where it has none (the runner then holds)"
# a sibling repo's newer record of the same branch name, in mode ask, is not this branch's (re-review of the landing fixes)
printf '{"branch": "%s", "started": 2, "task_mode": "ask", "repo": "%s"}\n' "$(br m-code)" "$T/projects/demo" > "$RUNS/m-code-sibling.json"
check "$(python3 -c 'import sys; from importlib.machinery import SourceFileLoader as L; m = L("autofinish", sys.argv[1]).load_module(); print(m.runner_by(sys.argv[2], "M"))' "$B/autofinish" "$(wtp $M m-code)" 2>&1)" "dnd" \
  "  runner_by reads the mode with its repo: a sibling repo's same-named branch in ask does not lower it"
rm -f "$RUNS/m-code-sibling.json"
rm -f "$RUNS"/m-*.json

echo "the launchd job (install.sh --schedule, the module's own)"
LC="$T/lc"; printf '#!/bin/sh\necho "$*" >> "%s"\n[ "$1" = print ] && exit 113\nexit 0\n' "$T/lc.calls" > "$LC"; chmod +x "$LC"
IN() { WHARF_RUNS_LAUNCH_DIR="$T/la" WHARF_RUNS_LAUNCHCTL="$LC" WHARF_RUNS_LOG_DIR="$T/rlogs" sh "$B/../install.sh" "$@"; }
mkdir -p "$T/cfg-ovl" "$T/cfg-bare"; : > "$T/cfg-ovl/legacy"
REGATTA_CONFIG="$T/cfg-ovl" IN --schedule > "$T/in.out" 2>&1; check "$?" "1" "beside an overlay (a legacy file): refused, no second sweep"
check "$(ls "$T/la" 2>/dev/null | wc -l | tr -d ' ')" "0" "  …and no plist written"
REGATTA_CONFIG="$T/cfg-bare" IN --schedule > "$T/in.out" 2>&1; check "$?" "0" "no overlay: scheduled"
IP="$T/la/dev.regatta.autofinish.plist"
if command -v plutil >/dev/null; then
  check "$(plutil -extract StartInterval raw -o - "$IP")" "600" "  every 10 min"
  check "$(plutil -extract RunAtLoad raw -o - "$IP")" "true" "  and at load"
  MAINCO="$(cd "$(git -C "$B" rev-parse --path-format=absolute --git-common-dir)/.." && pwd -P)"
  check "$(for k in 0 1 2; do plutil -extract ProgramArguments.$k raw -o - "$IP"; done | tr '\n' ' ')" \
    "/usr/bin/python3 $MAINCO/modules/wharf-runs/bin/autofinish --sweep " "  the main checkout's autofinish --sweep, never a worktree's"
  check "$(plutil -extract EnvironmentVariables.REGATTA_CONFIG raw -o - "$IP")" "$T/cfg-bare" "  the config dir it was installed with travels"
fi
has "$T/lc.calls" "bootstrap gui/$(id -u) $IP" "  loaded through the launchctl given"
IN --remove > /dev/null 2>&1; check "$([ -f "$IP" ] && echo there || echo gone)" "gone" "--remove deletes the plist"
has "$T/lc.calls" "bootout gui/$(id -u)/dev.regatta.autofinish" "  …after unloading it"

echo
[ "$fails" -eq 0 ] && echo "all autofinish tests passed" || { echo "$fails autofinish test(s) failed"; exit 1; }
