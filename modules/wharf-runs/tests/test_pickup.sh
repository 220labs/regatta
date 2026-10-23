#!/usr/bin/env bash
# Tests for bin/pickup — a scratch HOME with a repo, a bare origin, a second clone standing in
# for the build Mac, fixture transcripts, a live-session registry and a PR fixture. No network, no
# window opened (PICKUP_NO_START / --dry-run).
#   bash modules/wharf-runs/tests/test_pickup.sh
set -u
B="$(cd "$(dirname "$0")/../bin" && pwd)"   # the module's bin/ (B7: the suites moved to tests/)
# the regatta core's hooks/ (common.py), found as the tools find it (lib/core_path.py); wharf's peers by its tool()
CORE="$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import core_path; print(core_path.hooks() or "")' "$B/../lib")"
[ -n "$CORE" ] || { echo "FAIL: the regatta core is missing"; exit 1; }
# wharf's hooks/ (branches.py, checkpoint.py) and bin/ (session_status.py), the folders pickup imports from
WHOOKS="$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import common; print(common.tool("branches.py").parent)' "$CORE")"
WBIN="$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import common; print(common.tool("session_status.py").parent)' "$CORE")"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fails=0
check() { if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3: expected [$2] got [$1]"; fails=$((fails+1)); fi; }
has()   { if grep -qF -- "$2" "$1"; then echo "  ok   $3"; else echo "  FAIL $3: missing [$2]"; sed 's/^/         | /' "$1" | head -40; fails=$((fails+1)); fi; }
hasnt() { if grep -qF -- "$2" "$1"; then echo "  FAIL $3: unexpected [$2]"; fails=$((fails+1)); else echo "  ok   $3"; fi; }

# a blueprint's front matter is read by PyYAML, installed per user on these Macs: keep its site when HOME
# moves below (bin/blueprintlib.py; dispatch --next and pickup seed read blueprints, wharf-on-orca S5)
export PYTHONUSERBASE="${PYTHONUSERBASE:-$(python3 -m site --user-base)}"
. "$(cd "$(dirname "$0")" && pwd)/config_fixture.sh"; fixture_config "$T/config"   # the suite's own config dir, never the login's (config_fixture.sh)
# words that wharf's own modules spell (branches.py's archive reason, session_status's waiting label, and
# the peer-side form of an ssh command pickup prints): read from them, so this suite follows their scrub
CONFIRMED="$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import branches; print(branches.CONFIRMED)' "$WHOOKS")"
WAITON="$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import session_status as s; print(s.WAITING)' "$WBIN")"
RCH=\''"$(head -1 "${REGATTA_CONFIG:-$HOME/.config/regatta}/home")/modules/wharf-runs/bin/rc-hosts"'\'
export HOME="$T/home" GIT_CONFIG_NOSYSTEM=1
export ACCOUNTS_FILE="$T/no-accounts.json"   # no registry unless a case names one: the default is the config dir's lighthouse/accounts.json, the real one (B9)
mkdir -p "$HOME/.claude/projects" "$HOME/.claude/sessions" "$HOME/projects"
git config --global user.name Test; git config --global user.email t@example.com
git config --global init.defaultBranch main; git config --global advice.detachedHead false
unset CLAUDE_CONFIG_DIR CLAUDE_TRANSCRIPT_ARCHIVE PICKUP_NO_START PICKUP_NO_LAUNCH GH_TOKEN GITHUB_TOKEN
unset CLAUDE_UNATTENDED  # a dispatch session runs this suite: open and next refuse under it
unset VSCODE_PID PICKUP_VSCODE_WINDOW PICKUP_VSCODE_CLI  # a run inside VS Code must not probe its real windows
# …nor find the real `code` on PATH: the caller's window is 1, no CLI, and a window `code` opens
# is waited for 1 s (2026-10-13: a link only ever goes to a window of the session's own repo)
export PICKUP_VSCODE_WINDOW=1 PICKUP_VSCODE_CLI="$T/no-code" PICKUP_VSCODE_WAIT=1
export PICKUP_PRS="$T/prs.json" CLAUDE_CODE_ENTRYPOINT=claude-vscode
export CLAUDE_CODE_SESSION_ID=eeeeeeee-0000-4000-8000-000000000005
# ssh stands in twice: unreachable by default, so no case reaches a real machine; and, for the
# other-machine cases at the end, a stand-in that runs the command with $PEER_HOME as its home.
printf '#!/bin/sh\necho "ssh: connect to host buildbox port 22: Operation timed out" >&2\nexit 255\n' > "$T/ssh-down"
printf '#!/bin/sh\nwhile [ $# -gt 0 ]; do case "$1" in -o) shift 2;; -*) shift;; *) break;; esac; done\nshift\nHOME="$PEER_HOME" PICKUP_HOST=buildbox exec sh -c "$1"\n' > "$T/ssh-peer"
chmod +x "$T/ssh-down" "$T/ssh-peer"
export PICKUP_SSH="$T/ssh-down"
# This machine is the laptop, wherever the suite runs: every peer case reads buildbox as the other
# one, and on the build Mac the real name made buildbox "this machine" (26 failures, 2026-10-08).
export PICKUP_HOST=laptop
P() { python3 "$B/pickup" "$@" > "$T/out" 2>&1; echo $?; }
slug() { python3 -c 'import re,sys;print(re.sub(r"[^A-Za-z0-9]","-",sys.argv[1]))' "$1"; }
# commit <dir> <file> <session8> <prompt>: a checkpoint-shaped commit, as checkpoint.py writes it
commit() {
  (cd "$1" && echo "$4" > "$2" && git add "$2" && git commit -qF - <<EOF
Work on $2

Prompt:
> $4

Co-Authored-By: Claude <noreply@anthropic.com>
Claude-Session: $3
EOF
  )
}

O="$T/origin.git"; git init -q --bare "$O"
mkdir -p "$HOME/projects/demo/.claude" && cd "$HOME/projects/demo" && git init -q .
R=$(pwd -P)
echo '{"checkpoint": true, "main": "main"}' > .claude/workflow.json
printf '.env\n.claude/worktrees/\n.claude/settings.local.json\n' > .gitignore; echo "SECRET=x" > .env
git add -A && git commit -qm init && git remote add origin "$O" && git push -q origin main
A=aaaaaaaa-0000-4000-8000-000000000001; C=cccccccc-0000-4000-8000-000000000003
BA=claude/laptop/2026-09-24-alpha; BB=claude/buildbox/2026-09-23-beta
BC=claude/laptop/2026-09-22-gamma; BD=claude/laptop/2026-09-20-delta
WA="$R/.claude/worktrees/alpha"

git worktree add -q "$WA" -b $BA main && commit "$WA" a.txt aaaaaaaa "fix the alpha widget"
git -C "$WA" push -q -u origin $BA && git branch -q $BA-raw $BA
git clone -q "$O" "$T/buildbox" && git -C "$T/buildbox" checkout -qb $BB
commit "$T/buildbox" b.txt bbbbbbbb "make beta faster" && git -C "$T/buildbox" push -q origin $BB
git worktree add -q "$T/g" -b $BC main && commit "$T/g" c.txt cccccccc "rework gamma" && git worktree remove "$T/g"
git worktree add -q "$T/d" -b $BD main && commit "$T/d" d.txt dddddddd "delta" && git -C "$T/d" push -q origin $BD
git worktree remove "$T/d" && git branch -q -D $BD
BE=claude/laptop/2026-09-21-epsilon   # pushed with nothing main lacks: already in main
git push -q origin main:refs/heads/$BE && git fetch -q origin
# sib: a sibling repo a demo session committed in (`cd sib && git …`), so its transcript is demo's
S=55555555-0000-4000-8000-000000000007; BS=claude/laptop/2026-09-25-sibling
mkdir -p "$HOME/projects/sib" && git -C "$HOME/projects/sib" init -q . && echo s > "$HOME/projects/sib/s.txt"
git -C "$HOME/projects/sib" add -A && git -C "$HOME/projects/sib" commit -qm init
SIB=$(cd "$HOME/projects/sib" && pwd -P)
git -C "$SIB" worktree add -q "$T/s" -b $BS main && commit "$T/s" s2.txt 55555555 "the sibling change" && git -C "$SIB" worktree remove "$T/s"
# zeta: idle for days, its content reached main by another route — hooks/branches.py proves it
BZ=claude/laptop/2026-09-19-zeta; OLD=2026-09-19T10:00:00
git worktree add -q "$T/z" -b $BZ main && echo z > "$T/z/z.txt" && git -C "$T/z" add z.txt
GIT_AUTHOR_DATE=$OLD GIT_COMMITTER_DATE=$OLD git -C "$T/z" commit -qm zeta && git -C "$T/z" push -q origin $BZ
git worktree remove "$T/z" && git branch -q -D $BZ
echo z > z.txt && git add z.txt && git commit -qm "zeta, carried" && git push -q origin main && git fetch -q origin
# eta: its PR merged, but its worktree still holds an uncommitted file — the remaining work
BH=claude/laptop/2026-09-20-eta; WH="$R/.claude/worktrees/eta"
git worktree add -q "$WH" -b $BH main && commit "$WH" h.txt hhhhhhhh "eta" && git -C "$WH" push -q origin $BH
git merge -q --ff-only $BH && git push -q origin main && git fetch -q origin && echo more > "$WH/h.txt"

cat > "$PICKUP_PRS" <<EOF
[{"number": 1, "state": "open", "draft": true, "title": "WIP: alpha", "html_url": "https://example.test/pull/1",
  "updated_at": "2026-09-25T06:00:00Z", "head": {"ref": "$BA"}, "body": "Agent work in progress on **laptop**, session \`aaaaaaaa\`."},
 {"number": 2, "state": "closed", "merged_at": "2026-09-24T00:00:00Z", "title": "Delta", "html_url": "https://example.test/pull/2",
  "updated_at": "2026-09-24T00:00:00Z", "head": {"ref": "$BD"}, "body": ""},
 {"number": 3, "state": "open", "draft": true, "title": "WIP: beta", "html_url": "https://example.test/pull/3",
  "updated_at": "2026-09-24T06:00:00Z", "head": {"ref": "$BB"}, "body": "Agent work in progress on **buildbox**, session \`bbbbbbbb\`."},
 {"number": 5, "state": "closed", "merged_at": "2026-09-21T00:00:00Z", "title": "Eta", "html_url": "https://example.test/pull/5",
  "updated_at": "2026-09-21T00:00:00Z", "head": {"ref": "$BH"}, "body": ""}]
EOF

# transcript <file> <session> <cwd> <branch> <title> <relocatedCwd> <worktree path or ""> <prompt>
transcript() {
  mkdir -p "$(dirname "$1")"
  python3 - "$@" <<'PY'
import json, sys
f, sid, cwd, branch, title, reloc, wt, prompt = sys.argv[1:9]
rec = lambda r: json.dumps(r, separators=(",", ":"))
lines = [rec({"type": "worktree-state", "worktreeSession": {"worktreePath": wt, "worktreeBranch": branch, "sessionId": sid} if wt else None}),
         rec({"parentUuid": None, "isSidechain": False, "type": "user", "message": {"role": "user", "content": prompt},
              "uuid": "u1", "timestamp": "2026-09-25T06:00:00.000Z", "entrypoint": "claude-vscode", "cwd": cwd,
              "sessionId": sid, "gitBranch": branch, "origin": {"kind": "human"}}),
         rec({"parentUuid": "u1", "isSidechain": False, "type": "assistant", "timestamp": "2026-09-25T06:01:00.000Z",
              "message": {"role": "assistant", "content": [{"type": "text", "text": "Done with the first part; next is its test case, then deploy."}]},
              "uuid": "a1", "cwd": cwd, "sessionId": sid, "gitBranch": branch, "entrypoint": "claude-vscode"}),
         rec({"type": "ai-title", "aiTitle": title, "sessionId": sid}),
         rec({"type": "relocated", "sessionId": sid, "relocatedCwd": reloc})]
open(f, "a").write("\n".join(lines) + "\n")
PY
}
# usage <file> <sid> <branch> <ctx> <age_min> [5m | synthetic | agent | sorted]: one API call
# as a transcript records it — the tool result that began the request age_min ago, then the
# assistant record 8 s later (message before type, as real ones are) whose usage sums to ctx:
# 2 input + 300 written (the 1 h bucket, or the 5 min one) + the rest read. `synthetic` is the
# stand-in Claude Code writes for an error, no tool result — given real usage here, so only its
# model marks it; `agent` is an Agent tool's result, which carries a usage object of its own;
# `sorted` writes both records with their keys sorted, timestamp before type.
usage() {
  python3 - "$@" <<'PY'
import datetime, json, sys
f, sid, branch, ctx, age = sys.argv[1:6]
kind = sys.argv[6] if len(sys.argv) > 6 else ""
t0 = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(minutes=float(age))
iso = lambda t: t.strftime("%Y-%m-%dT%H:%M:%S.000Z")
rec = lambda r: json.dumps(r, separators=(",", ":"))
ctx = int(ctx)
use = {"input_tokens": 2, "cache_creation_input_tokens": 300, "cache_read_input_tokens": ctx - 302, "output_tokens": 40,
       "cache_creation": {"ephemeral_1h_input_tokens": 0 if kind == "5m" else 300, "ephemeral_5m_input_tokens": 300 if kind == "5m" else 0}}
model = "claude-opus-5-5"
if kind == "sorted":
    rec = lambda r: json.dumps(r, separators=(",", ":"), sort_keys=True)
user = {"parentUuid": "a", "isSidechain": False, "type": "user", "message": {"role": "user",
        "content": [{"type": "tool_result", "tool_use_id": "t", "content": "ok"}]},
        "uuid": "u", "timestamp": iso(t0), "sessionId": sid, "gitBranch": branch}
if kind == "agent":
    user["toolUseResult"] = {"status": "completed", "usage": {"input_tokens": 5, "output_tokens": 900}}
lines = [rec(user)]
if kind == "synthetic":
    model, lines = "<synthetic>", []
lines.append(rec({"parentUuid": "u", "isSidechain": False, "message": {"model": model, "role": "assistant",
                  "content": [{"type": "text", "text": "ok"}], "usage": use},
                  "type": "assistant", "uuid": "a", "timestamp": iso(t0 + datetime.timedelta(seconds=8)),
                  "sessionId": sid, "gitBranch": branch}))
open(f, "a").write("\n".join(lines) + "\n")
PY
}
PA="$HOME/.claude/projects/$(slug "$WA")/$A.jsonl"         # parked: closed inside its worktree
PC="$HOME/.claude/projects/$(slug "$R")/$C.jsonl"          # exited its worktree before closing
PE="$HOME/.claude/projects/$(slug "$R")/$CLAUDE_CODE_SESSION_ID.jsonl"
transcript "$PA" $A "$WA" $BA "Alpha widget fix" "$WA" "$WA" "fix the alpha widget"
mkdir -p "${PA%.jsonl}/subagents" && echo '{}' > "${PA%.jsonl}/subagents/agent-1.jsonl"
transcript "$PC" $C "$R" $BC "Gamma rework" "$R" "" "rework gamma"
echo '{"type":"custom-title","customTitle":"demo: gamma","sessionId":"'$C'"}' >> "$PC"
echo '{"type":"pr-link","sessionId":"'$C'","prNumber":3,"prRepository":"other/repo"}' >> "$PC"
transcript "$HOME/.claude/projects/$(slug "$R")/$S.jsonl" $S "$R" main "Sibling work" "$R" "" "change sib too"
transcript "$PE" $CLAUDE_CODE_SESSION_ID "$R" main "Pickup" "$R" "" \
  "<command-message>pickup</command-message>
<command-name>/pickup</command-name>
<command-args>the alpha thing</command-args>"

echo "list"
check "$(P list --no-fetch)" "0" "exit 0"
has "$T/out" "4 open" "alpha, beta, gamma, eta are open"
has "$T/out" "eta · claude/laptop/2026-09-20-eta" "a merged PR does not launch a branch whose worktree holds uncommitted work"
has "$T/out" "(1 uncommitted)" "…and the count says why"
hasnt "$T/out" " eta (launched" "…so it is never in the not-open line"
has "$T/out" "session aaaaaaaa \"Alpha widget fix\" · closed" "alpha's session found through its parked transcript"
has "$T/out" "parked in its worktree" "…and it is flagged parked"
has "$T/out" "from buildbox" "beta says where it was made"
has "$T/out" "only on origin" "…and that it exists only there"
has "$T/out" "commits name: bbbbbbbb" "…and names its session from the commit trailer"
has "$T/out" "last asked: \"make beta faster\"" "the last prompt comes from the checkpoint body"
has "$T/out" "session cccccccc \"demo: gamma\"" "a /rename title beats the ai-title"
has "$T/out" "delta (launched: PR #2 merged)" "a merged branch is not a candidate"
has "$T/out" "zeta (launched: " "…nor one hooks/branches.py proves on origin/main"
has "$T/out" "epsilon (in main)" "…nor one with nothing main lacks"
hasnt "$T/out" "alpha-raw" "-raw backups are never listed"
has "$T/out" "this session: claude-vscode, 0 earlier prompt(s)" "a session that only ran /pickup counts as fresh"

echo "the /move marker in list and show (teleport design E4)"
MA="$(git -C "$WA" rev-parse --absolute-git-dir)/claude"; mkdir -p "$MA"
echo "{\"to\":\"buildbox\",\"session\":\"65046969-aaaa\",\"at\":$(date +%s),\"branch\":\"$BA\",\"pending\":false}" > "$MA/teleported.json"
check "$(P list --no-fetch)" "0" "list with a marked worktree"
has "$T/out" "    ⇢ moved to buildbox (session 65046969, just now)" "…names where it went"
check "$(P show alpha --no-fetch)" "0" "show it"
has "$T/out" "  moved     ⇢ moved to buildbox (session 65046969, just now)" "…on its own line"
echo "{\"to\":\"laptop\",\"at\":$(date +%s),\"branch\":\"$BA\",\"pending\":true}" > "$MA/teleported.json"
P list --no-fetch >/dev/null
has "$T/out" "⇢ waiting for laptop (prepared just now)" "a pending marker: waiting for the target"
rm "$MA/teleported.json"
P list --no-fetch >/dev/null
hasnt "$T/out" "⇢" "no marker, no line"

echo "resolve"
check "$(P show a --no-fetch)" "2" "a part matching several branches is ambiguous (exit 2)"
has "$T/out" "  $BD" "…and lists them, launched ones included (open refuses those)"
check "$(P show pr3 --no-fetch)" "0" "pr3 resolves"
has "$T/out" "$BB" "…to beta"
hasnt "$T/out" "cccccccc" "another repo's PR #3 linked in a transcript does not attach its session"
check "$(P show aaaaaaaa --no-fetch)" "0" "a session prefix resolves"
has "$T/out" "handoff   vscode — reopen it in a VS Code tab (unparked first)" "…to alpha, with the VS Code handoff"
check "$(P open delta --no-fetch)" "1" "a launched branch is refused"
has "$T/out" "already on main (PR #2 merged)" "…with the reason"
check "$(P open zeta --no-fetch)" "1" "so is one proved launched another way"
check "$(P open 2026-09-20-eta --dry-run --no-fetch)" "0" "one with a merged PR and a dirty worktree is not refused"
hasnt "$T/out" "already on main" "…its uncommitted file is the work"

echo "a large session: reopen or fresh, as a choice (docs/record/pickup-cold-handoff-2026-09-29.md)"
check "$(P show gamma --no-fetch)" "0" "a transcript with no usage at all"
hasnt "$T/out" "context   " "…prints no context line (fail-open: the old behaviour)"
python3 - "$PA" $A $BA <<'PY'
import json, sys
f, sid, branch = sys.argv[1:4]
say = lambda text: json.dumps({"parentUuid": "a1", "isSidechain": False, "type": "assistant", "timestamp": "2026-09-25T06:02:00.000Z",
                               "message": {"role": "assistant", "content": [{"type": "text", "text": text}]},
                               "uuid": "a2", "sessionId": sid, "gitBranch": branch}, separators=(",", ":"))
open(f, "a").write(say("The widget test passes; the deploy is the last step and waits for your go.") + "\n"
                   + say("Long reply " + "x" * 3000) + "\n")
PY
usage "$PA" $A $BA 62000 200        # its first call: what a fresh session costs here
usage "$PA" $A $BA 180000 190
gd=$(git -C "$WA" rev-parse --absolute-git-dir); mkdir -p "$gd/claude"
echo "{\"session\":\"dead0000-0000-4000-8000-000000000000\",\"branch\":\"$BA\",\"seen\":$(date +%s)}" > "$gd/claude/owner.json"
wts=$(git -C "$R" worktree list --porcelain)
check "$(P show alpha --no-fetch)" "0" "180k, idle 3 h: show"
has "$T/out" "context   180k tokens · last call" "…the context, measured from the last usage record"
has "$T/out" "1 h cache: cold · fresh here ≈ 62k" "…cold after the hour, and the fresh base from this repo's first calls"
has "$T/out" "choice    fresh (recommended) — 180k tokens, idle 3 h (1 h cache, cold): reopening re-writes ~180k at 2×" "…fresh recommended, with the reason"
has "$T/out" "choice    reopen — the whole conversation, at 180k per call" "…and the other exit"
check "$(P open alpha --no-fetch)" "3" "open stops for the choice (exit 3)"
has "$T/out" "choice    fresh (recommended)" "…printing both exits"
has "$T/out" "choose: pickup open '$BA' --reopen | --fresh" "…and the two commands"
check "$([ -f "$PA" ] && echo parked)" "parked" "…the transcript is still parked"
check "$(git -C "$R" worktree list --porcelain)" "$wts" "…no worktree added (and gamma's case below has none to reuse)"
check "$([ -f "$gd/claude/owner.json" ] && echo kept)" "kept" "…no lock touched"
rm -f "$gd/claude/owner.json"
Q=9aaaaaaa-0000-4000-8000-000000000009
transcript "$HOME/.claude/projects/$(slug "$R")/$Q.jsonl" $Q "$R" main "Other work" "$R" "" "something else first"
check "$(CLAUDE_CODE_SESSION_ID=$Q PICKUP_NO_START=1 P open alpha --fresh --no-fetch)" "0" "--fresh from a session with other work"
has "$T/out" "→ new-tab: fresh, as asked" "…opens a new tab"
has "$T/out" "prompt=%2Fpickup%20%27claude%2Flaptop%2F2026-09-24-alpha%27%20--fresh" "…pre-filled with /pickup '<branch>' --fresh"
check "$(CLAUDE_CODE_SESSION_ID=$Q CLAUDE_CODE_ENTRYPOINT=cli PICKUP_NO_START=1 P open alpha --fresh --no-fetch)" "0" "…from a terminal"
has "$T/out" "not opened (PICKUP_NO_START) in $R: claude --name 'demo: alpha' '/pickup '\"'\"'$BA'\"'\"' --fresh'" "…a new Terminal window running it (R1)"
# --account (multi-account design E4): a registry, a secondary config dir, a stub claude for the probe
mkdir -p "$HOME/.acct-b"
printf '{"accounts":[{"label":"acct-b","home":"~/.acct-b","rules":{"week_max":70,"window_max":50}},{"label":"acct-a","home":"~/.claude","primary":true,"rules":{"week_max":95,"window_max":80}}]}' > "$T/accounts.json"
cat > "$T/claude-usage" <<'STUB'
#!/bin/sh
cat > /dev/null
set -- $(cat "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/stub-usage")
echo "{\"type\":\"control_response\",\"response\":{\"subtype\":\"success\",\"request_id\":\"u1\",\"response\":{\"rate_limits\":{\"five_hour\":{\"utilization\":$1},\"seven_day\":{\"utilization\":$2}}}}}"
STUB
chmod +x "$T/claude-usage"
AC() { ACCOUNTS_FILE="$T/accounts.json" ACCOUNT_CLAUDE="$T/claude-usage" CLAUDE_CODE_SESSION_ID=$Q PICKUP_NO_START=1 P "$@"; }
echo "10 20" > "$HOME/.acct-b/stub-usage"; echo "10 20" > "$HOME/.claude/stub-usage"
check "$(CLAUDE_CODE_ENTRYPOINT=cli AC open alpha --fresh --no-fetch)" "0" "--account auto: a fresh Terminal window on a secondary with room"
has "$T/out" "account acct-b: week 20% < 70%" "…says which account and why"
has "$T/out" "in $R: CLAUDE_CONFIG_DIR=$HOME/.acct-b claude --name 'demo: alpha · acct-b'" "…runs under its config dir, the label in the session name (R6)"
rm -f "$HOME/.acct-b/usage-probe.json" "$HOME/.claude/usage-probe.json"; echo "10 80" > "$HOME/.acct-b/stub-usage"
check "$(CLAUDE_CODE_ENTRYPOINT=cli AC open alpha --fresh --no-fetch)" "0" "the secondary short → the primary"
has "$T/out" "in $R: claude --name 'demo: alpha' '/pickup" "…no env, no label"
rm -f "$HOME/.acct-b/usage-probe.json" "$HOME/.claude/usage-probe.json"; echo "10 99" > "$HOME/.claude/stub-usage"
check "$(CLAUDE_CODE_ENTRYPOINT=cli AC open alpha --fresh --no-fetch)" "3" "every account short → exit 3"
has "$T/out" "no account may start $BA now — acct-b: week 80% ≥ 70%" "…naming each, nothing opened"
check "$(AC open alpha --fresh --account acct-b --no-fetch)" "1" "a VS Code tab on a named secondary is refused"
has "$T/out" "a VS Code tab runs on its window's login ($HOME/.claude), not acct-b; use --terminal" "…with the way that works"
check "$(AC open alpha --fresh --account acct-a --no-fetch)" "0" "a VS Code tab on this window's own login, named, is kept"
has "$T/out" "→ new-tab: fresh, as asked" "…and opens the tab"
check "$(AC open alpha --fresh --no-fetch)" "0" "a VS Code tab with --account auto stays on the primary, no pick"
has "$T/out" "→ new-tab: fresh, as asked" "…and opens as before"
rm -f "$HOME/.acct-b/usage-probe.json" "$HOME/.claude/usage-probe.json"; echo "10 80" > "$HOME/.acct-b/stub-usage"
check "$(CLAUDE_CODE_ENTRYPOINT=cli AC open alpha --fresh --account acct-b --no-fetch)" "3" "a named account past its own rules is refused"
has "$T/out" "--account acct-b: week 80% ≥ 70% (week ceiling)" "…naming the rule"
check "$(CLAUDE_CODE_ENTRYPOINT=cli AC open alpha --fresh --account acct-b --force --no-fetch)" "0" "…--force runs it there anyway"
has "$T/out" "in $R: CLAUDE_CONFIG_DIR=$HOME/.acct-b claude --name 'demo: alpha · acct-b'" "…under its config dir, its label in the name"
# work-account E2: a secondary whose deny list names this repo is skipped, and refused by name
printf '{"accounts":[{"label":"acct-b","home":"~/.acct-b","rules":{"week_max":70,"window_max":50},"repos":{"deny":["demo"]}},{"label":"acct-a","home":"~/.claude","primary":true,"rules":{"week_max":95,"window_max":80}}]}' > "$T/accounts.json"
rm -f "$HOME/.acct-b/usage-probe.json" "$HOME/.claude/usage-probe.json"; echo "10 20" > "$HOME/.acct-b/stub-usage"; echo "10 20" > "$HOME/.claude/stub-usage"
check "$(CLAUDE_CODE_ENTRYPOINT=cli AC open alpha --fresh --no-fetch)" "0" "a secondary that denies this repo → the primary"
has "$T/out" "in $R: claude --name 'demo: alpha' '/pickup" "…no env, no label"
check "$(CLAUDE_CODE_ENTRYPOINT=cli AC open alpha --fresh --account acct-b --no-fetch)" "3" "…and --account acct-b is refused here"
has "$T/out" "--account acct-b: demo is on its deny list" "…naming the deny list"
check "$(CLAUDE_CODE_ENTRYPOINT=cli AC open alpha --fresh --account acct-b --force --no-fetch)" "3" "…and --force never crosses a deny list"
printf '{"accounts":[{"label":"acct-b","home":"~/.acct-b","rules":{"week_max":70,"window_max":50}},{"label":"acct-a","home":"~/.claude","primary":true,"rules":{"week_max":95,"window_max":80}}]}' > "$T/accounts.json"
rm -f "$HOME/.acct-b/usage-probe.json" "$HOME/.claude/usage-probe.json"; echo "10 80" > "$HOME/.acct-b/stub-usage"
before=$(git -C "$R" worktree list | wc -l)
check "$(CLAUDE_CODE_ENTRYPOINT=cli AC open alpha --terminal --account acct-b --no-fetch)" "3" "a Terminal reopen on a named account past its rules is refused"
check "$(git -C "$R" worktree list | wc -l)" "$before" "…before any worktree, lock or fork was touched (code review S1)"
check "$(AC open alpha --here --account acct-b --no-fetch)" "0" "--here with a named account"
has "$T/out" "⚠ --account acct-b not applied: here starts nothing" "…says the account was not applied"
printf '{"accounts":[{"label":"gone","home":"~/.claude-gone"},{"label":"oa","provider":"codex","home":"~/.codex-oa"},{"label":"off","home":"~/.acct-b","enabled":false},{"label":"acct-a","home":"~/.claude","primary":true}]}' > "$T/accounts.json"
for a in gone oa off; do
  check "$(CLAUDE_CODE_ENTRYPOINT=cli AC open alpha --fresh --account $a --no-fetch)" "1" "--account $a is refused, no traceback"
done
has "$T/out" "off is disabled" "…a disabled row says so"
echo '{"accounts": [' > "$T/accounts.json"
check "$(CLAUDE_CODE_ENTRYPOINT=cli AC open alpha --fresh --no-fetch)" "0" "a broken registry never blocks a start"
has "$T/out" "⚠ account pick failed" "…it says so and uses the default login"
rm -rf "$HOME/.acct-b" "$HOME/.claude/usage-probe.json" "$HOME/.claude/stub-usage"
check "$([ -f "$PA" ] && echo parked)" "parked" "…the old transcript untouched"
check "$(PICKUP_NO_START=1 P open alpha --fresh --no-fetch)" "0" "--fresh from a session that did nothing else"
has "$T/out" "→ here: fresh, as asked: this session adopts it with the bundle" "…adopts it here"
has "$T/out" "→ adopt it here: EnterWorktree $WA" "…in its worktree"
has "$T/out" "Continues session aaaaaaaa \"Alpha widget fix\" — 180k tokens, closed 3 h ago; its transcript is untouched: pickup open '$BA' --reopen" "…the bundle names the old session and the way back"
check "$(grep -c '^  replied: ' "$T/out")" "3" "…with its last three replies (D1)"
has "$T/out" "replied: Long reply $(printf 'x%.0s' $(seq 1 2488))…" "…a long one cut at exactly 2,500 characters"
check "$([ -f "$PA" ] && echo parked)" "parked" "…and the old transcript is never unparked"
usage "$PA" $A $BA 180000 21
check "$(P show alpha --no-fetch)" "0" "180k, idle 20 min"
has "$T/out" "1 h cache: warm" "…is warm"
has "$T/out" "choice    fresh (recommended) — 180k tokens, idle 20 min (1 h cache, warm): reopening reads 180k per call" "…fresh still recommended, warmth in the reason (D2 b)"
check "$(P open alpha --dry-run --no-fetch)" "3" "…and open still asks"
usage "$PA" $A $BA 180000 10 5m
check "$(P show alpha --no-fetch)" "0" "a 5-minute cache, 10 min idle"
has "$T/out" "5 min cache: cold" "…is cold"
has "$T/out" "re-writes ~180k at 1.25×" "…at that TTL's price"
usage "$PA" $A $BA 99600 9
check "$(P show alpha --no-fetch)" "0" "99,600 tokens"
has "$T/out" "context   99k tokens" "…reads 99k, never a 100k without its choice"
usage "$PA" $A $BA 600000 9; usage "$PA" $A $BA 90000 8
check "$(P show alpha --no-fetch)" "0" "compaction: 600k, then 90k"
has "$T/out" "context   90k tokens" "…the last call wins"
hasnt "$T/out" "choice" "…under 100k, no choice"
check "$(P open alpha --dry-run --no-fetch)" "0" "…and open proceeds as before"
usage "$PA" $A $BA 180000 190; usage "$PA" $A $BA 5000 189 synthetic
check "$(P show alpha --no-fetch)" "0" "a synthetic record after the last call"
has "$T/out" "context   180k tokens" "…is skipped"
check "$(P open alpha --fresh --here --no-fetch)" "2" "--fresh --here is refused (exit 2)"
check "$(P open alpha --fresh --reopen --no-fetch)" "2" "--fresh --reopen is refused (exit 2)"
check "$(CLAUDE_CODE_SESSION_ID=$Q PICKUP_NO_START=1 P open alpha --fresh --note 'and finish the deploy' --no-fetch)" "0" "--fresh --note"
has "$T/out" "%27claude%2Flaptop%2F2026-09-24-alpha%27%20--note%20%27and%20finish%20the%20deploy%27%20--fresh" "…the note travels in the new tab's command"
check "$(CLAUDE_CODE_SESSION_ID=$Q PICKUP_NO_START=1 P open alpha --session aaaaaaaa --fresh --no-fetch)" "0" "--fresh --session"
has "$T/out" "%27%20--session%20aaaaaaaa%20--fresh" "…the session picked travels too"
check "$(P open alpha --session aaaaaaaa --note 'x y' --no-fetch)" "3" "the choice, after --session and --note"
has "$T/out" "choose: pickup open '$BA' --session aaaaaaaa --note 'x y' --reopen | --fresh" "…names the rerun with both"
usage "$PA" $A $BA 185000 80; usage "$PA" $A $BA 185000 35 agent
check "$(P show alpha --no-fetch)" "0" "an Agent tool's result began the last request, 35 min ago"
has "$T/out" "1 h cache: warm" "…its own usage object does not hide it: warm"
echo "  (gamma: sorted keys, and a large session with no worktree yet)"
usage "$PC" $C $BC 150000 190 sorted
check "$(P show gamma --no-fetch)" "0" "a transcript whose keys are sorted (timestamp before type)"
has "$T/out" "context   150k tokens · last call" "…is measured"
has "$T/out" "(idle 3 h) · 1 h cache: cold" "…with its times read"
check "$(P open gamma --no-fetch)" "3" "open stops for the choice"
check "$([ -d "$R/.claude/worktrees/gamma" ] || echo none)" "none" "…before any worktree is made"
check "$(cd "$SIB" && CLAUDE_CODE_SESSION_ID=$Q P open gamma --repo "$R" --no-fetch)" "3" "from another repo's window"
has "$T/out" "choose: pickup open '$BC' --repo $R --reopen | --fresh" "…the rerun carries --repo"
check "$(cd "$SIB" && CLAUDE_CODE_SESSION_ID=$Q PICKUP_NO_START=1 P open gamma --repo "$R" --fresh --no-fetch)" "0" "…--fresh from there"
has "$T/out" "→ window: fresh, as asked: a new Terminal window in that repo adopts it" "…opens a Terminal window, never a tab of this one"
has "$T/out" "in $R: claude --name 'demo: gamma'" "…running from that repo"
check "$(cd "$SIB" && CLAUDE_CODE_SESSION_ID= PICKUP_NO_START=1 P open gamma --repo "$R" --fresh --no-fetch)" "0" "…and from a plain shell"
has "$T/out" "→ window" "…a window too: a shell is no session to adopt anything"
check "$(CLAUDE_CODE_SESSION_ID= PICKUP_NO_START=1 P open gamma --fresh --no-fetch)" "0" "a plain shell in the repo itself"
has "$T/out" "→ window" "…a window as well"
usage "$PC" $C $BC 50000 189   # back under the line for the blocks below

echo "vscode handoff, parked transcript (--reopen: the choice made)"
check "$(P open alpha --reopen --dry-run --no-fetch)" "0" "dry run"
has "$T/out" "would move aaaaaaaa's transcript back" "dry run names the unpark"
has "$T/out" "session=$A&prompt=Picked%20up%20with%20%2Fpickup" "…and the URL, session and pre-filled prompt"
check "$([ -f "$PA" ] && echo still)" "still" "dry run moved nothing"
check "$(PICKUP_NO_START=1 P open alpha --reopen --no-fetch)" "0" "open"
PA2="$HOME/.claude/projects/$(slug "$R")/$A.jsonl"
check "$([ -f "$PA2" ] && [ ! -f "$PA" ] && echo moved)" "moved" "the transcript is back in the repo's slug"
check "$([ -f "${PA2%.jsonl}/subagents/agent-1.jsonl" ] && echo moved)" "moved" "…with its <id>/ folder"
check "$(tail -1 "$PA2")" "{\"type\":\"relocated\",\"sessionId\":\"$A\",\"relocatedCwd\":\"$R\"}" "…ending in ExitWorktree's relocated stamp, compact"
has "$T/out" "not opened (PICKUP_NO_START): vscode://anthropic.claude-code/open?windowId=1&session=$A" "the handoff URL"
has "$T/out" "Worktree: $WA — clean; main has 2 commit(s) this branch lacks." "the prompt names the worktree, its state and how far main moved"
check "$(P show alpha --no-fetch)" "0" "show after the unpark"
hasnt "$T/out" "parked" "…no longer parked"

echo "running session"
start=$(TZ=UTC LC_ALL=C ps -o lstart= -p $$ | xargs)
echo "{\"pid\":$$,\"sessionId\":\"$A\",\"cwd\":\"$WA\",\"procStart\":\"$start\",\"entrypoint\":\"claude-vscode\",\"status\":\"idle\"}" > "$HOME/.claude/sessions/$$.json"
check "$(PICKUP_NO_START=1 P open alpha --no-fetch)" "0" "open a running session"
has "$T/out" "→ live: its session is running now" "…is refused as live"
has "$T/out" "nothing was opened or changed" "…and says nothing changed"
A2=a2a2a2a2-0000-4000-8000-000000000008
transcript "$HOME/.claude/projects/$(slug "$R")/$A2.jsonl" $A2 "$R" $BA "Alpha, an older try" "$R" "" "try alpha another way"
check "$(PICKUP_NO_START=1 P open alpha --session a2a2a2a2 --no-fetch)" "0" "--session picks a closed one while the first runs"
has "$T/out" "→ vscode: reopen it in a VS Code tab" "…and reopens it, judged on the one picked (a traceback before)"
check "$(P open alpha --here --dry-run --no-fetch)" "0" "--here on a branch whose session is running here (/finish <branch>)"
has "$T/out" "⚠ session aaaaaaaa \"Alpha widget fix\" worked on this branch and is running here (idle, pid $$)" "…warns, naming it"
has "$T/out" "end it first: close it where it runs" "…and how to end it"
echo "{\"pid\":$$,\"sessionId\":\"$A\",\"procStart\":\"Mon Jan  1 00:00:00 2001\"}" > "$HOME/.claude/sessions/$$.json"
check "$(P show alpha --no-fetch)" "0" "a registry entry whose procStart does not match"
has "$T/out" "handoff   vscode" "…is a reused pid, not a running session"
rm -f "$HOME/.claude/sessions/$$.json"

echo "adopt here: a branch made on the other machine"
check "$(PICKUP_NO_START=1 P open beta --no-fetch)" "0" "open"
has "$T/out" "→ here: no transcript for it on buildbox: this session adopts it" "no session here, a fresh session adopts"
check "$(git -C "$R/.claude/worktrees/beta" rev-parse --abbrev-ref '@{u}')" "origin/$BB" "the worktree tracks origin"
check "$(readlink "$R/.claude/worktrees/beta/.env")" "$R/.env" ".env is linked"
has "$T/out" "EnterWorktree $R/.claude/worktrees/beta" "it says where to enter"
has "$T/out" "1. make beta faster" "the context bundle carries the prompts"
has "$T/out" "PR #3 open \"WIP: beta\"" "…and the PR"
printf '%s\n' '{"type":"user","message":{"role":"user","content":"something else"},"timestamp":"2026-09-25T07:00:00.000Z","sessionId":"x","gitBranch":"main","origin":{"kind":"human"}}' >> "$PE"
check "$(P show beta --no-fetch)" "0" "the same, from a session that already did other work"
has "$T/out" "handoff   new-tab" "…opens a fresh tab instead of mixing topics"

echo "terminal handoff"
check "$(CLAUDE_CODE_ENTRYPOINT=cli P open gamma --dry-run --no-fetch)" "0" "dry run from a terminal session"
has "$T/out" "would create worktree .claude/worktrees/gamma from $BC" "a branch without a worktree gets one"
has "$T/out" "would run in $R: claude --resume $C" "reopened from the directory whose slug holds it"
check "$(CLAUDE_CODE_ENTRYPOINT=cli PICKUP_NO_START=1 P open gamma --no-fetch)" "0" "open"
check "$(git -C "$R/.claude/worktrees/gamma" symbolic-ref --short HEAD)" "$BC" "the worktree is on the branch"

echo "another repo"
check "$(cd "$T" && P show gamma --repo "$R" --no-fetch)" "0" "show from outside the repo"
has "$T/out" "handoff   terminal — reopen it in a new Terminal window (its session belongs to another repo's window)" "a vscode:// link would open in the wrong window"
check "$(cd "$T" && P open buildbox --repo "$R" --no-fetch)" "1" "a branch there with no session here"
has "$T/out" "open that repo's window and run /pickup $BB there" "…goes back to the owner"

echo "a sibling repo's commit, made by a session of this one"
check "$(cd "$SIB" && P show sibling --no-fetch)" "0" "show from the sibling's window"
has "$T/out" "session 55555555 \"Sibling work\"" "the trailer finds the session in another project's folder"
has "$T/out" "linked by commits" "…by its commits"
has "$T/out" "handoff   terminal — reopen it in a new Terminal window (its session belongs to another repo's window)" "…and reopens it outside this window"
check "$(PICKUP_NO_START=1 P open sibling --repo "$SIB" --no-fetch)" "0" "open it from demo's window"
has "$T/out" "→ vscode: reopen it in a VS Code tab" "demo's window lists it: VS Code"
has "$T/out" "open?windowId=1&session=$S" "…in this window, whose list holds it — not sib's (review 2026-10-14)"
hasnt "$T/out" "unparked" "…and another repo's transcript is never moved"
check "$(PICKUP_VSCODE_WINDOW=0 PICKUP_NO_START=1 P open sibling --repo "$SIB" --no-fetch)" "0" "the same, with this window's id unknown"
has "$T/out" "claude --resume $S" "…reopens in a Terminal window"
hasnt "$T/out" "vscode://" "…never a link to sib's window or the focused one"
check "$([ -f "$HOME/.claude/projects/$(slug "$R")/$S.jsonl" ] && echo stays)" "stays" "…it stays where it was"

echo "origin moved: the other machine pushed"
git -C "$T/buildbox" fetch -q origin && git -C "$T/buildbox" checkout -q -b $BA origin/$BA
commit "$T/buildbox" a2.txt 99999999 "alpha, continued on buildbox" && git -C "$T/buildbox" push -q origin $BA
check "$(PICKUP_NO_START=1 P open alpha --here)" "0" "open fetches, then"
has "$T/out" "✓ fast-forwarded 1 commit(s) from origin" "fast-forwards a clean worktree"
check "$(git -C "$WA" rev-parse HEAD)" "$(git -C "$R" rev-parse origin/$BA)" "…to origin's tip"
commit "$WA" a3.txt aaaaaaaa "local work"
commit "$T/buildbox" a4.txt 99999999 "more on buildbox" && git -C "$T/buildbox" push -q origin $BA
check "$(P show alpha)" "0" "both moved"
has "$T/out" "DIVERGED: 1 local, 1 on origin" "divergence is named, never resolved by force"

echo "locks"
gd=$(git -C "$WA" rev-parse --absolute-git-dir)
mkdir -p "$gd/claude" && echo "{\"session\":\"dead0000-0000-4000-8000-000000000000\",\"branch\":\"$BA\",\"seen\":$(date +%s)}" > "$gd/claude/owner.json"
check "$(PICKUP_NO_START=1 P open alpha --here --no-fetch)" "0" "a lock whose owner is not running"
has "$T/out" "released a stale lock: session dead0000" "…is released"
check "$([ -f "$gd/claude/owner.json" ] || echo gone)" "gone" "…the file is gone"
F=ffffffff-0000-4000-8000-000000000006
echo "{\"session\":\"$F\",\"branch\":\"$BA\",\"seen\":$(date +%s)}" > "$gd/claude/owner.json"
echo "{\"pid\":$$,\"sessionId\":\"$F\",\"procStart\":\"$start\"}" > "$HOME/.claude/sessions/$$.json"
check "$(PICKUP_NO_START=1 P open alpha --here --no-fetch)" "0" "a lock whose owner is running"
has "$T/out" "is running and holds this worktree" "…is kept, and said"
check "$([ -f "$gd/claude/owner.json" ] && echo kept)" "kept" "…the file stays"
rm -f "$HOME/.claude/sessions/$$.json"

echo "next: a stage hands over to the next (docs/subagent-cache-2026-10-04.md D6–D7)"
NX=7e7e7e7e-0000-4000-8000-00000000000a; NEW=8e8e8e8e-0000-4000-8000-00000000000b
PN="$HOME/.claude/projects/$(slug "$WA")/$NX.jsonl"
transcript "$PN" $NX "$WA" $BA "Alpha, stage one" "$WA" "$WA" "design alpha's next part"
usage "$PN" $NX $BA 150000 30; usage "$PN" $NX $BA 80000 1   # a compaction: the last call counts
N() { (cd "$WA" && CLAUDE_CODE_SESSION_ID=$NX PICKUP_NO_START=1 P next "$@"); }
echo "{\"session\":\"$NX\",\"branch\":\"$BA\",\"seen\":$(date +%s)}" > "$gd/claude/owner.json"
check "$(CLAUDE_UNATTENDED=dispatch N "build it" --tab)" "1" "unattended (dispatch): a tab is refused — nobody is there to press Enter"
has "$T/out" "start the next step with dispatch --next" "…and names dispatch"
check "$(CLAUDE_UNATTENDED=dispatch N "build it")" "0" "  continue is not: it needs nobody"
check "$(CLAUDE_UNATTENDED=dispatch P open delta --no-fetch)" "1" "  open refuses too"
has "$T/out" "\`pickup open\` hands a session to Sam, and this is an unattended run" "  …saying why"
check "$(N "build it")" "0" "80k: exit 0"
has "$T/out" "continue — this session is at 80k context, under 120k" "…continue, in this session"
hasnt "$T/out" "vscode://" "…no tab"
hasnt "$gd/claude/owner.json" "handover" "…the lock untouched"
usage "$PN" $NX $BA 130000 0
check "$(N "build it, then /finish")" "0" "130k: exit 0"
has "$T/out" "tab — this session is at 130k context (over 120k)" "…a fresh tab"
has "$T/out" "prompt=%2Fpickup%20%27claude%2Flaptop%2F2026-09-24-alpha%27%20--note%20%27build%20it%2C%20then%20%2Ffinish%27%20--fresh" \
  "…pre-filled with /pickup '<branch>' --note '<next step>' --fresh"
has "$T/out" "✓ lock marked handed over" "…and the lock marked"
check "$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print(d["session"]==sys.argv[2], bool(d.get("handover")), "path" in d)' "$gd/claude/owner.json" $NX)" \
  "True True False" "…still this session's, marked, nothing else written into it"
check "$(P show alpha --no-fetch)" "0" "show a handed-over lock"
has "$T/out" "handed over by 7e7e7e7e" "…says so"
# the new tab: its /pickup --fresh, while the old session still runs
echo "{\"pid\":$$,\"sessionId\":\"$NX\",\"cwd\":\"$WA\",\"procStart\":\"$start\",\"entrypoint\":\"claude-vscode\",\"status\":\"idle\"}" > "$HOME/.claude/sessions/$$.json"
mark() { echo "{\"session\":\"$NX\",\"branch\":\"$BA\",\"seen\":$(date +%s)${1:+,\"handover\":$(date +%s)}}" > "$gd/claude/owner.json"; }
check "$(CLAUDE_CODE_SESSION_ID=$NEW PICKUP_NO_START=1 P open "$BA" --note 'build it' --fresh --no-fetch)" "0" \
  "the new tab's /pickup, exactly as pre-filled, the old session still running"
has "$T/out" "→ here: fresh, as asked" "…adopts it here, not refused as live"
has "$T/out" "✓ took over the lock session 7e7e7e7e handed over (pickup next)" "…taking the lock at once"
check "$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print(d["session"]==sys.argv[2], bool(d.get("handover")))' "$gd/claude/owner.json" $NEW)" \
  "True False" "…the new session's now, unmarked: no third session gets in"
has "$T/out" "which handed this stage over (pickup next); its tab is still open" "…the bundle says the old one handed over"
hasnt "$T/out" "--reopen brings" "…and does not offer to reopen a running session"
hasnt "$T/out" "running here" "…no two-writers warning about the session that handed over"
hasnt "$T/out" "writes here stay refused" "…nor a lock warning"
mark
check "$(CLAUDE_CODE_SESSION_ID=$NEW PICKUP_NO_START=1 P open "$BA" --note 'build it' --fresh --no-fetch)" "0" "the same without the mark"
has "$T/out" "→ live: its session is running now" "…is refused as live, as before"
rm -f "$HOME/.claude/sessions/$$.json"
echo "{\"session\":\"$F\",\"branch\":\"$BA\",\"seen\":$(date +%s)}" > "$gd/claude/owner.json"
echo "{\"pid\":$$,\"sessionId\":\"$F\",\"procStart\":\"$start\"}" > "$HOME/.claude/sessions/$$.json"
check "$(N "x" --tab)" "1" "another running session's lock: refused"
has "$T/out" "not this session's to hand over" "…and why"
rm -f "$HOME/.claude/sessions/$$.json"
check "$(N "x" --tab)" "0" "the same lock, its owner not running (crashed): marked as this session's"
has "$T/out" "✓ lock marked handed over" "…as checkpoint.py would let this session write there anyway"
rm -f "$gd/claude/owner.json"; usage "$PN" $NX $BA 90000 0
check "$(N "x" --tab)" "0" "--tab under 120k, no lock"
has "$T/out" "tab — this session is at 90k context (--tab)" "…says why"
check "$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print(d["session"]==sys.argv[2], bool(d.get("handover")))' "$gd/claude/owner.json" $NX)" \
  "True True" "…and writes a marked lock anyway: the tab's open --fresh keys on it"
check "$(printf 'run `bin/check` and $HOME\n' | (cd "$WA" && CLAUDE_CODE_SESSION_ID=$NX PICKUP_NO_START=1 P next - --tab))" "0" "PROMPT - reads stdin"
has "$T/out" "%60bin%2Fcheck%60%20and%20%24HOME" "…code spans and \$ arrive untouched"
# The window: a stand-in `code --status` names the ancestor whose parent is VSCODE_PID (here the
# test shell) as extension host [7], laid out as VS Code 1.140 prints it.
cat > "$T/code" <<'SH'
#!/bin/bash
p=$PPID
while [ "$p" -gt 1 ]; do pp=$(ps -o ppid= -p "$p" | tr -d ' '); [ "$pp" = "$VSCODE_PID" ] && break; p=$pp; done
printf '    0\t   12\t     1\twindow [7] (demo)\n    0\t   10\t%6s\textension-host [7]\n' "$p"
[ -n "$CODE_ALSO" ] && printf '    0\t   12\t     2\twindow [%s] (other)\n' "$CODE_ALSO"
exit 0
SH
chmod +x "$T/code"
check "$(cd "$WA" && VSCODE_PID=$$ PICKUP_VSCODE_CLI="$T/code" PICKUP_VSCODE_WINDOW= CLAUDE_CODE_SESSION_ID=$NX PICKUP_NO_START=1 P next x --tab)" "0" "inside VS Code"
has "$T/out" "open?windowId=7&prompt=" "…the tab opens in this session's own window, not the focused one"
check "$(cd "$WA" && VSCODE_PID=$$ PICKUP_VSCODE_CLI="$T/code" PICKUP_VSCODE_WINDOW=0 CLAUDE_CODE_SESSION_ID=$NX PICKUP_NO_START=1 P next x --tab)" "1" "PICKUP_VSCODE_WINDOW=0"
hasnt "$T/out" "windowId" "…no windowId"
has "$T/out" "nothing started, the lock left as it is" "…nothing starts: no tab in the focused window, and no Terminal window, which would run at once (2026-10-14)"
check "$(cd "$WA" && VSCODE_PID=$$ PICKUP_VSCODE_CLI="$T/code" PICKUP_VSCODE_WINDOW= CLAUDE_CODE_SESSION_ID=$NX PICKUP_NO_START=1 P next x --tab)" "0" "PICKUP_VSCODE_WINDOW empty"
has "$T/out" "open?windowId=7&prompt=" "…counts as unset: the probe runs"
check "$(cd "$WA" && VSCODE_PID=$$ PICKUP_VSCODE_CLI="$T/code" PICKUP_VSCODE_WINDOW= CODE_ALSO=70 CLAUDE_CODE_SESSION_ID=$NX PICKUP_NO_START=1 P next x --tab)" "1" "window 70 open beside window 7"
hasnt "$T/out" "windowId" "…VS Code's unanchored match would hit either: no windowId"
has "$T/out" "nothing started, the lock left as it is" "…so nothing starts, saying why"
check "$(cd "$WA" && VSCODE_PID=$$ PICKUP_VSCODE_CLI="$T/code" PICKUP_VSCODE_WINDOW= CODE_ALSO=17 CLAUDE_CODE_SESSION_ID=$NX PICKUP_NO_START=1 P next x --tab)" "0" "window 17 open beside window 7"
has "$T/out" "open?windowId=7&prompt=" "…window:7 does not match window:17's start: the id stays"
check "$(cd "$WA" && CLAUDE_CODE_SESSION_ID=$NX PICKUP_STAGE_TOKENS=120k PICKUP_NO_START=1 P next x)" "0" "a malformed PICKUP_STAGE_TOKENS: the default, no traceback"
has "$T/out" "continue — this session is at 90k context, under 120k" "…120k it is"
check "$(cd "$WA" && CLAUDE_CODE_SESSION_ID=$NX CLAUDE_CODE_ENTRYPOINT=cli PICKUP_NO_START=1 P next x --tab)" "1" "from a terminal session: refused"
has "$T/out" "a cli session: the pre-filled tab is VS Code's" "…and why"
check "$(cd "$R" && CLAUDE_CODE_SESSION_ID=$NX PICKUP_NO_START=1 P next x --tab)" "1" "on main: refused"
has "$T/out" "on main, not a claude/* branch" "…and why"
check "$(CLAUDE_CODE_SESSION_ID= P next x)" "1" "no session id: refused"
rm -f "$gd/claude/owner.json"

echo "another repo's branch, fresh, from VS Code: a tab in that repo's own window (2026-10-13)"
# Two listeners stand in for two windows' extension hosts; each window's Claude extension names its
# folders in <config>/ide/<port>.lock, and `code --status` names the host's window (sib 3, demo 5).
listener() { python3 -c 'import socket,sys,time
s=socket.socket(); s.bind(("127.0.0.1",0)); s.listen(); open(sys.argv[1],"w").write(str(s.getsockname()[1])); time.sleep(900)' "$1" & }
listener "$T/port-sib"; LS=$!; listener "$T/port-demo"; LD=$!
trap 'kill $LS $LD 2>/dev/null; rm -rf "$T"' EXIT
for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$T/port-sib" ] && [ -s "$T/port-demo" ] && break; sleep 0.3; done
PS_=$(cat "$T/port-sib"); PD=$(cat "$T/port-demo")
mkdir -p "$HOME/.claude/ide" "$T/locks"
printf '{"pid":1,"workspaceFolders":["%s"],"ideName":"Visual Studio Code","transport":"ws"}' "$SIB" > "$HOME/.claude/ide/$PS_.lock"
printf '{"pid":1,"workspaceFolders":["%s"],"ideName":"Visual Studio Code","transport":"ws"}' "$R" > "$T/locks/$PD.lock"
printf '{"pid":1,"workspaceFolders":["%s"],"ideName":"Visual Studio Code","transport":"ws"}' "$WA" > "$T/locks/wt.lock"
status() { printf '    0\t   12\t     1\twindow [3] (sib)\n    0\t   10\t%6s\textension-host [3]\n    0\t   12\t     2\twindow [%s] (demo)\n    0\t   10\t%6s\textension-host [%s]\n' "$LS" "$1" "$LD" "$1" > "$T/status"; [ -n "${2:-}" ] && printf '    0\t   12\t     4\twindow [%s] (other)\n' "$2" >> "$T/status"; }
cat > "$T/code2" <<'SH'
#!/bin/bash
[ "$1" = --status ] && { cat "$CODE2_STATUS"; exit 0; }
echo "$*" >> "$CODE2_LOG"
[ -n "${CODE2_OPENS:-}" ] && cp "$CODE2_OPENS" "$HOME/.claude/ide/"
exit 0
SH
chmod +x "$T/code2"
FV() { (cd "$SIB" && CODE2_STATUS="$T/status" CODE2_LOG="$T/code2.log" PICKUP_VSCODE_WINDOW=3 PICKUP_VSCODE_CLI="$T/code2" \
        CLAUDE_CODE_SESSION_ID=$Q PICKUP_NO_START=1 P open gamma --repo "$R" --fresh --no-fetch "$@"); }
status 5; cp "$T/locks/$PD.lock" "$HOME/.claude/ide/"; : > "$T/code2.log"
check "$(FV)" "0" "demo's window open beside this one (sib's), which has focus"
has "$T/out" "→ foreign-vscode: fresh, as asked: a new tab in demo's VS Code window adopts it" "…plans foreign-vscode"
has "$T/out" "not opened (PICKUP_NO_START): vscode://anthropic.claude-code/open?windowId=5&prompt=%2Fpickup%20%27${BC//\//%2F}%27%20--fresh" "…one link, carrying demo's window id"
hasnt "$T/out" "windowId=3" "…never this window's"
check "$(cat "$T/code2.log")" "" "…the window was there: nothing to open"
rm "$HOME/.claude/ide/$PD.lock"; cp "$T/locks/wt.lock" "$HOME/.claude/ide/$PD.lock"
check "$(FV)" "0" "demo's only window is on one of its worktrees"
has "$T/out" "?windowId=5&prompt=" "…same repo (git common dir): that window"
rm "$HOME/.claude/ide/$PD.lock"
check "$(CODE2_OPENS="$T/locks/$PD.lock" FV)" "0" "no window on demo: the code CLI opens one"
check "$(cat "$T/code2.log")" "-n $R" "…\`code -n <repo>\` first"
has "$T/out" "✓ \`code -n $R\` opened demo's VS Code window (window 5)" "…its id read once its extension is up"
has "$T/out" "?windowId=5&prompt=" "…then the link"
rm "$HOME/.claude/ide/$PD.lock"; : > "$T/code2.log"
# a repo in a scope: its scope's file opens instead of the bare folder (bin/scopes, 2026-10-14).
# The stub answers `workspace REPO` and `anchor REPO` for the repos SCOPE_MEMBERS names
printf '{"folders": [{"path": "%s"}, {"path": "%s"}]}' "$SIB" "$R" > "$T/demo.code-workspace"
echo '{"folders": []}' > "$T/empty.code-workspace"
cat > "$T/scopes-stub" <<'PY'
import os, sys
verb, repo = sys.argv[1], os.path.realpath(sys.argv[2])
if repo not in [os.path.realpath(m) for m in os.environ["SCOPE_MEMBERS"].split(":")]:
    sys.exit(1)
print(os.environ["SCOPE_FILE"] if verb == "workspace" else os.environ["SCOPE_ANCHOR"])
PY
check "$(CODE2_OPENS="$T/locks/$PD.lock" SCOPE_MEMBERS="$R" SCOPE_ANCHOR="$R" SCOPE_FILE="$T/demo.code-workspace" PICKUP_SCOPES="$T/scopes-stub" FV)" "0" "no window on demo, the anchor of its scope"
check "$(cat "$T/code2.log")" "-n $T/demo.code-workspace" "…\`code -n <its scope's file>\`"
has "$T/out" "?windowId=5&prompt=%2Fpickup%20%27${BC//\//%2F}%27%20--fresh" "…the link goes to demo's window (its first folder), no --repo"
rm "$HOME/.claude/ide/$PD.lock"; : > "$T/code2.log"
check "$(CODE2_OPENS="$T/locks/$PD.lock" SCOPE_MEMBERS="$R" SCOPE_ANCHOR="$R" SCOPE_FILE="$T/empty.code-workspace" PICKUP_SCOPES="$T/scopes-stub" FV)" "0" "a scope file that does not list demo"
check "$(cat "$T/code2.log")" "-n $R" "…the bare folder, never a window that would not show it (review 2026-10-15)"
rm "$HOME/.claude/ide/$PD.lock"; : > "$T/code2.log"

echo "a repo of a scope whose anchor is another: the scope's window (D2, docs/scopes-2026-10-14.md)"
# sib anchors a scope holding demo; sib's window (3) shows both, and the session runs in it
printf '{"pid":1,"workspaceFolders":["%s","%s"],"ideName":"Visual Studio Code","transport":"ws"}' "$SIB" "$R" > "$HOME/.claude/ide/$PS_.lock"
SV() { (cd "$SIB" && CODE2_STATUS="$T/status" CODE2_LOG="$T/code2.log" PICKUP_VSCODE_WINDOW="${SVW-3}" PICKUP_VSCODE_CLI="$T/code2" \
        SCOPE_MEMBERS="$SIB:$R" SCOPE_ANCHOR="$SIB" SCOPE_FILE="$T/demo.code-workspace" PICKUP_SCOPES="$T/scopes-stub" \
        CLAUDE_CODE_SESSION_ID=$Q PICKUP_NO_START=1 P open gamma --repo "$R" --fresh --no-fetch "$@"); }
check "$(SV)" "0" "fresh, from the scope's window, no window on demo"
hasnt "$T/out" "foreign-vscode" "…not another repo's: the scope's window is demo's too"
hasnt "$T/out" "elsewhere" "…never sent elsewhere"
has "$T/out" "→ new-tab" "…a new tab: this session already has other work"
has "$T/out" "?windowId=3&prompt=%2Fpickup%20%27${BC//\//%2F}%27%20--repo%20" "…a tab in this window, its /pickup naming demo"
has "$T/out" "%20--fresh" "…--repo before the closing --fresh, which the skill keys on"
check "$(cat "$T/code2.log")" "" "…no window opened"
check "$(SVW=7 SV)" "0" "a caller in sib's repo but another window (7), the scope's window open"
has "$T/out" "→ foreign-vscode" "…not the scope's window by its own: demo is another repo's (review 2026-10-15)"
has "$T/out" "?windowId=3&prompt=" "…the scope's window (3), found by its folders"
has "$T/out" "--repo%20" "…its /pickup names demo"
rm "$HOME/.claude/ide/$PS_.lock"; : > "$T/code2.log"
printf '{"pid":1,"workspaceFolders":["%s","%s"],"ideName":"Visual Studio Code","transport":"ws"}' "$SIB" "$R" > "$T/locks/scope.lock"
mkdir -p "$T/locks/scope"; cp "$T/locks/scope.lock" "$T/locks/scope/$PD.lock"
check "$(SVW=7 CODE2_OPENS="$T/locks/scope/$PD.lock" SV)" "0" "no window holds demo"
check "$(cat "$T/code2.log")" "-n $T/demo.code-workspace" "…\`code -n <the scope's file>\`, not demo's bare folder"
has "$T/out" "?windowId=5&prompt=%2Fpickup%20" "…the opened scope window found by its folders"
has "$T/out" "--repo%20" "…its /pickup names demo: the tab starts in sib"
rm -f "$HOME/.claude/ide/$PD.lock"
printf '{"pid":1,"workspaceFolders":["%s"],"ideName":"Visual Studio Code","transport":"ws"}' "$SIB" > "$HOME/.claude/ide/$PS_.lock"
: > "$T/code2.log"

# the helpers on their own
python3 - "$B/pickup" "$SIB" "$R" <<'PY' || fails=$((fails+1))
import importlib.machinery, importlib.util, os, sys
from pathlib import Path
loader = importlib.machinery.SourceFileLoader("pickup", sys.argv[1])
m = importlib.util.module_from_spec(importlib.util.spec_from_loader("pickup", loader)); loader.exec_module(m)
sib, demo = Path(sys.argv[2]), Path(sys.argv[3])
bad = 0
def ok(c, label):
    global bad
    print(("  ok   " if c else "  FAIL ") + label); bad += not c
ok(m.with_repo("/pickup 'b' --note 'x y' --fresh", demo) == f"/pickup 'b' --note 'x y' --repo {demo} --fresh",
   "with_repo: --repo before the closing --fresh")
ok(m.with_repo("/pickup b", demo) == f"/pickup b --repo {demo}", "with_repo: appended when there is no --fresh")
m.scope_anchor = lambda root: sib
s = {"path": str(Path("/x") / m.slug(sib) / "id.jsonl")}
ok(m.transcript_home(s, demo, {"repo": None}) == sib, "transcript_home: filed under the scope's anchor → its window")
s = {"path": str(Path("/x") / m.slug(demo) / "id.jsonl")}
ok(m.transcript_home(s, demo, {"repo": sib}) == demo, "transcript_home: filed under root → root's window")
s = {"path": "/x/-elsewhere/id.jsonl"}
ok(m.transcript_home(s, demo, {"repo": sib}) is None, "transcript_home: filed anywhere else → none")
m.vscode_window = lambda: "3"
m.window_first = lambda w: str(sib) if w == "3" else None
ok(m.scoped_here({"entry": "claude-vscode", "repo": sib}, demo), "scoped_here: a VS Code session in the anchor's window")
ok(not m.scoped_here({"entry": "cli", "repo": sib}, demo), "scoped_here: a Terminal session never")
# rename S2 (M13): the status words S5 switches to, compared beside the old ones
for w in ("landed", "launched"):
    ok(m.plan({"status": w, "proof": "PR #1 merged", "mine": False}, {}, demo)[0] == "none", f"plan: a {w} branch has nothing to pick up")
    ok(m.status_text({"status": "probably " + w, "proof": "a hint"}) == f"probably {w}: a hint", f"status_text: probably {w} shows its proof")
ok(not m.foreign_to({"entry": "claude-vscode", "repo": sib}, demo), "foreign_to: the scope's window is home")
m.window_first = lambda w: str(demo)
ok(not m.scoped_here({"entry": "claude-vscode", "repo": sib}, demo),
   "scoped_here: cwd in the anchor's repo, window another's (an EnterWorktree from elsewhere) — not home")
m.window_first = lambda w: None
ok(not m.scoped_here({"entry": "claude-vscode", "repo": sib}, demo), "scoped_here: an unknown window is not home")

# where a parked transcript goes back to: ExitWorktree's destination
park = {"path": str(Path("/x") / (m.slug(demo) + "--claude-worktrees-t") / "id.jsonl"), "parked": True, "cwd0": str(sib)}
ok(m.unpark_home(park, demo) == sib, "unpark_home: started in the scope's anchor → back to the anchor")
ok(m.unpark_home({**park, "cwd0": str(demo)}, demo) == demo, "unpark_home: started in root → root, as before")
ok(m.unpark_home({**park, "cwd0": None}, demo) == demo, "unpark_home: no cwd0 → root")

# plan(): a session filed under the anchor, or parked from it, reopens in the scope's window
me = {"entry": "claude-vscode", "repo": Path("/elsewhere"), "earlier": 1, "id": "me"}
b = {"status": "wip", "mine": False, "name": "claude/x", "peer": None, "host": None}
filed = {"live": None, "place": "other", "parked": False, "path": str(Path("/x") / m.slug(sib) / "id.jsonl"), "cwd0": str(sib)}
ok(m.plan({**b, "sessions": [filed]}, me, demo)[0] == "vscode", "plan: filed under the anchor → vscode (the scope's window)")
m.unpark_possible = lambda s, r: Path(r) == sib
ok(m.plan({**b, "sessions": [{**park, "live": None, "place": "parked"}]}, me, demo)[0] == "vscode",
   "plan: parked from the anchor → vscode, unparked into the anchor")
m.unpark_possible = lambda s, r: False
ok(m.plan({**b, "sessions": [{**park, "live": None, "place": "parked"}]}, me, demo)[0] == "terminal",
   "plan: …and a Terminal reopen when the anchor's slug cannot take it")
m.scoped_here = lambda me_, root: True
ok(m.plan({**b, "sessions": [], "peer": {"host": "buildbox", "transcripts": ["t"]}}, {**me, "repo": sib}, demo)[0] == "elsewhere",
   "plan: a peer's session from the scope's window is not carried here (it would file under demo)")
sys.exit(1 if bad else 0)
PY
check "$(FV)" "0" "no window on demo, and none shows up"
has "$T/out" "opened no window whose id could be read in 1 s" "…says why"
has "$T/out" "not opened (PICKUP_NO_START) in $R: claude --name 'demo: gamma'" "…and starts it in a Terminal window there"
hasnt "$T/out" "vscode://" "…no link to the focused window"
status 5; cp "$T/locks/$PD.lock" "$HOME/.claude/ide/"
check "$(cd "$WA" && CODE2_STATUS="$T/status" PICKUP_VSCODE_WINDOW=3 PICKUP_VSCODE_CLI="$T/code2" CLAUDE_CODE_SESSION_ID=$Q PICKUP_NO_START=1 P open gamma --new-tab --no-fetch)" "0" "a session in sib's window whose cwd is in demo's worktree (2026-10-14)"
has "$T/out" "?windowId=5&" "…demo's window, not its own"
hasnt "$T/out" "windowId=3" "…its own window is sib's"
status 5 50; cp "$T/locks/$PD.lock" "$HOME/.claude/ide/"
check "$(FV)" "0" "demo's window id cannot be told apart (window 50 open too)"
hasnt "$T/out" "windowId" "…no id"
has "$T/out" "in $R: claude --name 'demo: gamma'" "…a Terminal window, never the focused one"
status 5
# the plan line comes before the account's own checks, whose verdict the AC cases above cover
ACCOUNTS_FILE="$T/accounts.json" ACCOUNT_CLAUDE="$T/claude-usage" FV --account acct-a --dry-run >/dev/null
has "$T/out" "→ window: fresh, as asked: a new Terminal window in that repo on acct-a" "…a Terminal window: a tab there runs on its window's login"
check "$(cd "$SIB" && CLAUDE_CODE_ENTRYPOINT=cli PICKUP_VSCODE_CLI="$T/code2" CLAUDE_CODE_SESSION_ID=$Q PICKUP_NO_START=1 P open gamma --repo "$R" --fresh --no-fetch)" "0" "a Terminal caller"
has "$T/out" "→ window: fresh, as asked: a new Terminal window in that repo adopts it" "…still a Terminal window"
check "$(cd "$SIB" && PICKUP_VSCODE_WINDOW=0 PICKUP_VSCODE_CLI="$T/code2" CODE2_STATUS="$T/status" CLAUDE_CODE_SESSION_ID=$Q PICKUP_NO_START=1 P open gamma --repo "$R" --fresh --no-fetch)" "0" "a VS Code caller whose own window id cannot be read"
has "$T/out" "→ window: fresh, as asked: a new Terminal window in that repo adopts it" "…a Terminal window too"
check "$(cd "$SIB" && CODE2_STATUS="$T/status" PICKUP_VSCODE_WINDOW=3 PICKUP_VSCODE_CLI="$T/code2" CLAUDE_CODE_SESSION_ID=$Q P open gamma --repo "$R" --fresh --dry-run --no-fetch)" "0" "--dry-run"
has "$T/out" "would open: vscode://anthropic.claude-code/open?windowId=" "…says the link"
rm -f "$HOME/.claude/ide/"*.lock; { kill $LS $LD; wait $LS $LD; } 2>/dev/null
trap 'rm -rf "$T"' EXIT  # the listeners are gone: their pids may be anyone's by exit (review 2026-10-14)

echo "next in a repo dispatch takes (D1, 2026-10-05): seeded, not a tab"
# the contract dispatch requires, untracked on the primary; a stage branch of its own
printf -- '- physical: none\n' > "$R/AGENTS.md"
BS=claude/laptop/2026-10-05-stage; WS="$R/.claude/worktrees/stage"
git worktree add -q "$WS" -b $BS main && commit "$WS" s.txt 5e5e5e5e "stage one"
cat > "$T/dispatch" <<SH
#!/bin/bash
echo "\$* | session \$CLAUDE_CODE_SESSION_ID" >> "$T/dispatch.calls"
[ -n "\${STUB_RS_FAIL:-}" ] && { echo "dispatch: 3 runs are live already — refused" >&2; exit 2; }
[ -n "\${STUB_RS_DIE:-}" ] && { echo "dispatch: NOT STARTED — no run header" >&2; exit 1; }
echo "started: claude is running \$1 (opus high) in screen run-demo-stage; dispatch --status"
SH
chmod +x "$T/dispatch"
NS() { (cd "$WS" && PICKUP_DISPATCH="$T/dispatch" CLAUDE_CODE_SESSION_ID=$NX PICKUP_NO_START=1 P next "$@"); }
check "$(printf 'Build stage two: the `widget`, then run /finish.\n' | NS - --tab)" "0" "seeded: exit 0"
has "$T/out" "seeded $BS — the next stage runs unattended (dispatch --next" "…the verdict is seeded"
has "$T/out" "started: claude is running $BS" "…dispatch's own lines relayed"
hasnt "$T/out" "vscode://" "…no tab"
has "$T/dispatch.calls" "$BS --next --repo $R | session $NX" "…dispatch --next on the branch, its primary as --repo, this session's id for the lock"
BRIEF="docs/handoff/$(date +%Y-%m-%d)-stage.md"
check "$(git -C "$WS" log -1 --format=%s)" "Seed: the next stage of stage (pickup next)" "…the brief committed last"
check "$(git -C "$WS" show HEAD:$BRIEF | grep -c 'Build stage two: the `widget`, then run /finish.')" "1" "…holding the prompt as given"
check "$([ -z "$(git -C "$WS" status --porcelain)" ] && echo clean)" "clean" "…the worktree clean for dispatch"
check "$([ -f "$(git -C "$WS" rev-parse --absolute-git-dir)/claude/owner.json" ] && echo marked || echo none)" "none" "…no hand-over mark: dispatch frees the lock"
check "$(STUB_RS_FAIL=1 NS "stage three" --tab)" "1" "dispatch refusing: a stop…"
has "$T/out" "dispatch refused or failed (exit 2)" "…naming dispatch"
has "$T/out" "3 runs are live already" "…and its reason"
echo dirt > "$WS/scratch"
check "$(NS "stage four" --tab)" "1" "uncommitted work: refused before any commit"
has "$T/out" "commit the stage's work first" "…and why"
rm "$WS/scratch"
check "$(CLAUDE_UNATTENDED=dispatch NS "stage five" --tab)" "0" "unattended: seeded is allowed (dispatch's guards decide)"
check "$(NS "stage six" --tab --dry-run)" "0" "dry run"
has "$T/out" "seeded (dry run) — would commit the prompt as $BRIEF" "…says what it would do"
check "$(NS "under the threshold")" "0" "under 120k, without --tab…"
has "$T/out" "continue — this session is at" "…continue is unchanged"
rm -f "$R/AGENTS.md"

echo "the other machine: read over ssh (D6), its conversation carried as a fork (D7)"
# the build Mac's home: demo cloned, beta in a worktree with a file never committed, its session's
# transcript, and that session alive under a Remote Control host (entrypoint sdk-cli).
IH="$(cd "$T" && pwd -P)/ihome"; export PEER_HOME="$IH"
mkdir -p "$IH/projects" "$IH/.claude/sessions"
git clone -q "$O" "$IH/projects/demo"
IW="$IH/projects/demo/.claude/worktrees/beta"
git -C "$IH/projects/demo" worktree add -q "$IW" -b $BB origin/$BB && echo wip > "$IW/half.txt"
IB=bbbbbbbb-0000-4000-8000-000000000002
IT="$IH/.claude/projects/$(slug "$IW")/$IB.jsonl"
transcript "$IT" $IB "$IW" $BB "Beta speedup" "$IW" "$IW" "make beta faster"
echo "{\"pid\":$$,\"sessionId\":\"$IB\",\"cwd\":\"$IW\",\"entrypoint\":\"sdk-cli\",\"status\":\"idle\",\"statusUpdatedAt\":$(( ($(date +%s) - 7200) * 1000 )),\"name\":\"demo-b2\"}" > "$IH/.claude/sessions/$$.json"
usage "$IT" $IB $BB 200000 10
check "$(PICKUP_SSH="$T/ssh-peer" P show beta --no-fetch)" "0" "show a branch made on buildbox, buildbox answering"
has "$T/out" "context   200k tokens" "the probe measures the transcript there"
has "$T/out" "choice    reopen — the whole conversation, carried from buildbox, at 200k per call" "…and offers carry vs fresh"
has "$T/out" "1 h cache: cold" "…cold 10 min on: the fork is a new prefix here, whatever buildbox cached"
has "$T/out" "carrying it over forks it here, which re-writes ~200k at 2×" "…and the reason says so"
has "$T/out" "buildbox  worktree $IW, 1 uncommitted, 1 session(s) running on it, transcript found" "it reads the worktree, the sessions and the transcript there"
has "$T/out" "⚠ ALIVE on buildbox: session bbbbbbbb \"demo-b2\"" "a session alive there is named"
has "$T/out" "end it first: ssh buildbox-ssh $RCH --end bbbbbbbb" "…with the line that ends it"
has "$T/out" "⚠ 1 uncommitted file(s) in buildbox's worktree, not on origin: half.txt" "files never committed there are named"
has "$T/out" "handoff   carry — its session is on buildbox" "the handoff now carries the conversation"
hasnt "$T/out" "⇢" "no marker there, no line"
IM="$(git -C "$IW" rev-parse --absolute-git-dir)/claude"; mkdir -p "$IM"
echo "{\"to\":\"laptop\",\"at\":$(date +%s),\"branch\":\"$BB\",\"pending\":true}" > "$IM/teleported.json"
check "$(PICKUP_SSH="$T/ssh-peer" P show beta --no-fetch)" "0" "show it with a marker on buildbox"
has "$T/out" "⇢ waiting for laptop (prepared just now) — the marker on buildbox" "the probe reads the marker there"
rm "$IM/teleported.json"
check "$(CLAUDE_CODE_SESSION_ID=abcdef00-0000-4000-8000-00000000000a PICKUP_SSH="$T/ssh-peer" P open beta --fresh --dry-run --no-fetch)" "0" "--fresh on buildbox's conversation"
has "$T/out" "Continues session bbbbbbbb on buildbox — 200k tokens; its transcript there is untouched: pickup open '$BB' --reopen carries" "…the bundle names it and the way back"
has "$T/out" "replied: Done with the first part; next is its test case, then deploy." "…and carries its replies from there (D1)"
check "$(P show beta --no-fetch)" "0" "buildbox not answering"
has "$T/out" "buildbox  not read (buildbox-ssh: ssh: connect to host buildbox" "…is one line"
has "$T/out" "handoff   new-tab" "…and the handoff is what it was"
check "$(PICKUP_SSH="$T/ssh-peer" CLAUDE_CODE_ENTRYPOINT=cli P open beta --transcript --dry-run --no-fetch)" "0" "--transcript, dry, from a terminal"
has "$T/out" "would copy buildbox:$IT here as a fork" "…names what it would copy"
check "$(PICKUP_SSH="$T/ssh-peer" PICKUP_NO_START=1 P open beta --no-fetch)" "3" "open a 200k conversation there: the choice first"
check "$(PICKUP_SSH="$T/ssh-peer" PICKUP_NO_START=1 P open beta --reopen --no-fetch)" "0" "--reopen carries it"
has "$T/out" "⚠ ALIVE on buildbox" "…warning, never blocking"
has "$T/out" "✓ buildbox's session bbbbbbbb copied here as" "the transcript comes over as a fork"
F=$(ls -t "$HOME/.claude/projects/$(slug "$R")"/*.jsonl | head -1); FID=$(basename "$F" .jsonl)
hasnt "$F" "$IH/projects" "no path under the other machine's projects folder is left in it"
has "$F" "\"cwd\":\"$R/.claude/worktrees/beta\"" "its cwd is this machine's worktree"
has "$F" "\"sessionId\":\"$FID\"" "it has its own id"
has "$F" "🔀 fork · Beta speedup" "it is titled as a fork"
hasnt "$F" "worktree-state" "the other machine's worktree bookkeeping is dropped"
check "$(tail -1 "$F")" "{\"type\":\"relocated\",\"sessionId\":\"$FID\",\"relocatedCwd\":\"$R\"}" "it ends relocated to the repo root"
has "$T/out" "not opened (PICKUP_NO_START): vscode://anthropic.claude-code/open?windowId=1&session=$FID" "the VS Code handoff opens the fork"
has "$T/out" "EnterWorktree $R/.claude/worktrees/beta" "its first message says which worktree to enter"
check "$(grep -c . "$IT")" "7" "the original there is untouched"
rm -f "$IH/.claude/sessions/$$.json"

echo "a branch named for this machine, continued on the other (2026-09-30, a memo in another repo)"
# Made here, then worked on on the build Mac: its commit names the session by its claude.ai
# URL, and the transcript sits in a sibling repo's project folder there. The name no longer
# decides which machine is read.
HM=$PICKUP_HOST
BG=claude/$HM/2026-09-29-crossing; IG=cccccccc-0000-4000-8000-000000000003
git -C "$T/buildbox" checkout -qb $BG origin/main
commit "$T/buildbox" x.txt "https://claude.ai/code/session_01CROSS" "crossing, on buildbox" && git -C "$T/buildbox" push -q origin $BG
git -C "$R" fetch -q origin
transcript "$IH/.claude/projects/$(slug "$IH/projects/other")/$IG.jsonl" $IG "$IH/projects/demo" $BG "Crossing" "$IH/projects/other" "" "crossing, on buildbox"
check "$(PICKUP_SSH="$T/ssh-peer" P show crossing --no-fetch)" "0" "show it, buildbox answering"
has "$T/out" "buildbox  no worktree for it, 0 session(s) running on it, transcript found" "…buildbox is read, though the name says $HM"
has "$T/out" "handoff   carry — its session is on buildbox" "…and its conversation is carried"
check "$(PICKUP_SSH="$T/ssh-peer" CLAUDE_CODE_ENTRYPOINT=cli P open crossing --transcript --dry-run --no-fetch)" "0" "--transcript on it"
has "$T/out" "would copy buildbox:$IH/.claude/projects/$(slug "$IH/projects/other")/$IG.jsonl here as a fork" "…copies that transcript"
check "$(P show crossing --no-fetch)" "0" "buildbox not answering"
has "$T/out" "buildbox  not read" "…is one line"

echo "review and archive — a probably-launched branch is the owner's call (coding-on-workflow D6)"
V="$HOME/projects/rv"; mkdir -p "$V/.claude" && git -C "$V" init -q && echo '{"checkpoint": true, "main": "main"}' > "$V/.claude/workflow.json"
printf 'one\ntwo\n' > "$V/f.md" && git -C "$V" add -A && git -C "$V" commit -qm base && vbase=$(git -C "$V" rev-parse HEAD)
git -C "$V" checkout -qb claude/laptop/2026-09-20-picked && echo three >> "$V/f.md" && git -C "$V" commit -qam "add three"
echo "draft only on the branch" > "$V/g.md" && git -C "$V" add g.md && git -C "$V" commit -qm "a draft"
git -C "$V" checkout -q main && echo zero > "$V/z.md" && git -C "$V" add z.md && git -C "$V" commit -qm "main moves"
git -C "$V" cherry-pick claude/laptop/2026-09-20-picked~1 claude/laptop/2026-09-20-picked >/dev/null   # on main by other shas
echo "main rewrote it" > "$V/g.md" && git -C "$V" commit -qam "main rewrites the draft"
git -C "$V" checkout -qb claude/laptop/2026-09-20-open "$vbase" && echo wip > "$V/w.md" && git -C "$V" add w.md && git -C "$V" commit -qm wip && git -C "$V" checkout -q main
check "$(P review picked --repo "$V" --no-fetch)" 0 "review: exits 0"
has "$T/out" "verdict   probably launched: every commit has an equivalent on main" "  the verdict, with its reason"
has "$T/out" "— on main as " "  each commit named with its equivalent on main"
has "$T/out" "g.md — differs — main edited it since" "  each file: identical, or differs and why"
has "$T/out" "would lose 1 line the branch added that main does not have" "  what archiving would lose: only the branch's own lines main lacks"
has "$T/out" "+ draft only on the branch" "  shown"
has "$T/out" "archive   $B/pickup archive claude/laptop/2026-09-20-picked --confirmed" "  and the two exits, by absolute path"
check "$(P archive picked --repo "$V" --no-fetch)" 1 "archive without --confirmed: refused"
has "$T/out" "it records that Sam confirmed" "  and says why"
check "$(P archive claude/laptop/2026-09-20-open --confirmed --repo "$V" --no-fetch)" 1 "archive of a branch not on main: refused"
has "$T/out" "pick it up instead" "  pick it up instead"
tip=$(git -C "$V" rev-parse claude/laptop/2026-09-20-picked)
check "$(P archive picked --confirmed --repo "$V" --no-fetch)" 0 "archive --confirmed of the probably-launched one: done"
git -C "$V" show-ref -q --verify refs/heads/claude/laptop/2026-09-20-picked; check $? 1 "  the branch is gone from the list"
check "$(git -C "$V" rev-parse refs/archive/claude/laptop/2026-09-20-picked)" "$tip" "  kept under refs/archive at its tip"
grep -q " refs/archive/claude/laptop/2026-09-20-picked $CONFIRMED$" "$V/.git/claude/archived"; check $? 0 "  with the owner's reason in the record (rename S3: branches.CONFIRMED)"
has "$T/out" "restore: git -C $(cd "$V" && pwd -P) branch claude/laptop/2026-09-20-picked refs/archive/" "  and it prints the restore line"

echo "seed — a follow-up for a session that does not exist yet (docs/record/followup-handoff-2026-09-29.md)"
cd "$R"
TODAY=$(date +%F); HN=$PICKUP_HOST
SN=claude/$HN/$TODAY-omega; SB="$T/brief.md"
{ echo "# omega — handoff from demo: tests, $TODAY"; echo "Task: sweep the omega worktrees"; echo "Tier: Opus 5.5 high"
  for i in $(seq 1 27); do echo "Why: evidence line $i"; done; } > "$SB"
check "$(CLAUDE_CODE_SESSION_ID=$Q P seed omega --file "$SB" --dry-run --no-fetch)" 0 "seed --dry-run"
has "$T/out" "would seed $SN in $R: commit docs/handoff/$TODAY-omega.md (30 lines)" "…names the branch, the repo and the file"
git show-ref -q --verify refs/heads/$SN; check $? 1 "…and makes nothing"
check "$(CLAUDE_CODE_SESSION_ID=$Q PICKUP_NO_START=1 P seed omega --file "$SB" --no-fetch)" 0 "seed"
has "$T/out" "seeded $SN in demo — docs/handoff/$TODAY-omega.md, 30 lines; pushed" "…commits and pushes"
check "$(git log --format=%s main..$SN)" "Seed: omega" "one Seed: commit, from local main"
check "$(git diff --name-only main $SN)" "docs/handoff/$TODAY-omega.md" "…adding only the brief, so it is never 'no net change'"
check "$(git show $SN:docs/handoff/$TODAY-omega.md | cmp - "$SB" && echo same)" "same" "…as written"
git log -1 --format=%B $SN > "$T/msg"
has "$T/msg" "> sweep the omega worktrees" "the task is the commit's Prompt"
has "$T/msg" "Seeded-By: demo/9aaaaaaa on $HN" "…with who seeded it"
hasnt "$T/msg" "Claude-Session:" "…and no Claude-Session trailer, so open never picks up the seeding session (R2)"
check "$(git rev-parse origin/$SN)" "$(git rev-parse $SN)" "origin has it"
check "$(git worktree list | grep -c omega)" "0" "no worktree made"
has "$T/out" "→ new-tab: fresh, as asked" "from VS Code with other work: its tab opens at once (D2 b)"
has "$T/out" "prompt=%2Fpickup%20%27claude%2F$HN%2F$TODAY-omega%27%20--fresh" "…pre-filled with /pickup '<branch>' --fresh"
echo "a fresh session where dispatch takes the repo: dispatched, not a tab or a window (the owner, 2026-10-13)"
printf -- '- physical: none\n' > "$R/AGENTS.md"; : > "$T/dispatch.calls"
SP=claude/$HN/$TODAY-psi
check "$(CLAUDE_CODE_SESSION_ID=$Q PICKUP_DISPATCH="$T/dispatch" P seed psi --file "$SB" --no-fetch)" 0 "a seed, started…"
has "$T/out" "dispatched $SP: a fresh session runs it unattended, not a tab" "…is dispatched"
hasnt "$T/out" "vscode://" "…no tab"
has "$T/dispatch.calls" "$SP --repo" "…dispatch on the seed"
has "$T/dispatch.calls" " --next" "…--next: pushed and confirmed from its log"
: > "$T/dispatch.calls"
check "$(CLAUDE_CODE_SESSION_ID=$Q CLAUDE_CODE_ENTRYPOINT=cli PICKUP_DISPATCH="$T/dispatch" P open "$SP" --fresh --note 'mind the cache' --no-fetch)" 0 "open --fresh from a terminal…"
has "$T/dispatch.calls" "--note mind the cache" "…dispatched, the note passed on"
hasnt "$T/out" "new Terminal window" "…no Terminal window"
check "$(CLAUDE_CODE_SESSION_ID=$Q CLAUDE_CODE_ENTRYPOINT=cli PICKUP_DISPATCH="$T/dispatch" PICKUP_NO_START=1 P open alpha --fresh --no-fetch)" 0 "a branch with no brief…"
has "$T/out" "not opened (PICKUP_NO_START)" "…opens its window as before"
check "$(STUB_RS_FAIL=1 CLAUDE_CODE_SESSION_ID=$Q CLAUDE_CODE_ENTRYPOINT=cli PICKUP_DISPATCH="$T/dispatch" PICKUP_NO_START=1 P open "$SP" --fresh --no-fetch)" 0 "dispatch refusing (exit 2)…"
has "$T/out" "dispatch refused it (exit 2), so the tab or window instead" "…the window as before, with its reason"
has "$T/out" "not opened (PICKUP_NO_START)" "…and the window opens"
check "$(STUB_RS_DIE=1 CLAUDE_CODE_SESSION_ID=$Q CLAUDE_CODE_ENTRYPOINT=cli PICKUP_DISPATCH="$T/dispatch" P open "$SP" --fresh --no-fetch)" 1 "dispatch failing after scheduling (exit 1): a stop"
has "$T/out" "dispatch failed (exit 1) — nothing confirmed started" "…naming dispatch"
mkdir -p "$(git -C "$R" rev-parse --path-format=absolute --git-common-dir)/claude/dispatched"
echo "$(date +%s) buildbox $SP" > "$(git -C "$R" rev-parse --path-format=absolute --git-common-dir)/claude/dispatched/psi"
: > "$T/dispatch.calls"
check "$(CLAUDE_CODE_SESSION_ID=$Q PICKUP_DISPATCH="$T/dispatch" P seeds --mine --open --no-fetch)" 0 "seeds --open (finish) after dispatch already sent it…"
has "$T/out" "already dispatched" "…says so"
check "$(grep -c "$SP" "$T/dispatch.calls")" "0" "…and does not send it twice"
rm -f "$R/AGENTS.md"
check "$(P list --no-fetch)" 0 "list"
has "$T/out" "omega · $SN" "the seed is an open branch"
has "$T/out" "seed — not started; brief docs/handoff/$TODAY-omega.md" "…marked as a seed"
has "$T/out" "last asked: \"sweep the omega worktrees\"" "…with its task as last asked"
check "$(P show omega --no-fetch)" 0 "show"
has "$T/out" "seed — not started; brief docs/handoff/$TODAY-omega.md, seeded by demo/9aaaaaaa on $HN" "…names the brief and who seeded it"
check "$(CLAUDE_CODE_SESSION_ID=abcdef01-0000-4000-8000-00000000000b P open omega --fresh --dry-run --no-fetch)" 0 "the fresh tab's /pickup --fresh"
has "$T/out" "→ here: fresh, as asked" "…adopts it"
has "$T/out" "docs/handoff/$TODAY-omega.md" "…and the bundle names the brief"
check "$(cd "$WHOOKS" && python3 -c '
import sys, branches
from pathlib import Path
root = Path(sys.argv[1]); b = branches.collect(root)[sys.argv[2]]; tgt = branches.target(root, "main")
print(branches.prove(root, b, tgt), branches.probably(root, b, tgt))' "$R" "$SN")" "None None" "branches.py: not launched, not even probably (R1)"
check "$(CLAUDE_CODE_SESSION_ID=$Q P seed omega --file "$SB" --no-fetch)" 1 "the same topic again: refused (R7)"
has "$T/out" "omega is already open as $SN" "…naming the branch"
python3 -c 'print("Task: x\n" + "y" * 5000)' > "$T/big.md"
check "$(P seed bigone --file "$T/big.md" --no-fetch)" 1 "a brief over 4,000 characters: refused"
has "$T/out" "over 60 lines or 4,000 characters" "…and says what the cap is"
printf 'no task here\n' > "$T/notask.md"
check "$(P seed notask --file "$T/notask.md" --no-fetch)" 1 "a brief without a Task: line: refused"
check "$(P seed Bad_Topic --file "$SB" --no-fetch)" 1 "a topic that is no branch-name part: refused"
check "$(P seed export-raw --file "$SB" --no-fetch)" 1 "a topic ending in -raw (a /finish backup name): refused"
check "$(P seed kappa --file "$SB" --repo "$SIB" --no-fetch)" 1 "a repo not on the worktree workflow: refused"
has "$T/out" "sib is not on the worktree workflow" "…and says where it goes instead"
check "$(WEEKLY_RUN=sextant CLAUDE_CODE_SESSION_ID=$Q PICKUP_NO_START=1 P seed chi --file "$SB" --no-fetch)" 1 "WEEKLY_RUN: a seed without --no-start is refused (S7 /finish review, F1)"
has "$T/out" "under WEEKLY_RUN=sextant a seed takes --no-start" "…and says why"
check "$(CLAUDE_CODE_SESSION_ID=$Q PICKUP_NO_START=1 P seed phi --file "$SB" --no-start --no-fetch)" 0 "seed --no-start"
has "$T/out" "start it: \`/pickup 'claude/$HN/$TODAY-phi' --fresh\` in a demo tab" "…prints the start line, the full name quoted"
hasnt "$T/out" "vscode://" "…and opens nothing"
has "$T/out" "start it now, unattended: bash $B/dispatch 'claude/$HN/$TODAY-phi' --next --repo $R (Bash" "…and leads with dispatch (2026-10-04), --repo always: dispatch defaults to the launcher repo"
IS=$(cd "$T/buildbox" && pwd -P)
check "$(CLAUDE_CODE_SESSION_ID=$Q PICKUP_NO_START=1 P seed sigma --file "$SB" --repo "$T/buildbox" --no-fetch)" 0 "seed in another repo"
has "$T/out" "seeded claude/$HN/$TODAY-sigma in buildbox" "…is made there"
check "$(git -C "$IS" log --format=%s main..claude/$HN/$TODAY-sigma)" "Seed: sigma" "…on that repo's main"
has "$T/out" "start it: \`/pickup 'claude/$HN/$TODAY-sigma' --fresh\` in a buildbox window" "…prints its start line"
has "$T/out" "a Terminal window that runs it at once" "…and what \"start it\" would cost"
hasnt "$T/out" "not opened (PICKUP_NO_START)" "…and opens nothing without --start (D2's exception)"
check "$(CLAUDE_CODE_SESSION_ID=$Q PICKUP_NO_START=1 P seed tau --file "$SB" --repo "$T/buildbox" --start --no-fetch)" 0 "--start: \"start it\""
has "$T/out" "not opened (PICKUP_NO_START) in $IS: claude --name 'buildbox: tau'" "…a Terminal window in that repo"
# the old names, aliases for a week (S1 of docs/wharf-rename-2026-10-16.md; S8 drops them)
check "$(CLAUDE_CODE_SESSION_ID=$Q PICKUP_NO_LAUNCH=1 P seed rho --file "$SB" --repo "$T/buildbox" --launch --no-fetch)" 0 "alias --launch, under the old PICKUP_NO_LAUNCH"
has "$T/out" "not opened (PICKUP_NO_START) in $IS: claude --name 'buildbox: rho'" "…starts as --start does, and the old env still opens nothing"
check "$(CLAUDE_CODE_SESSION_ID=$Q PICKUP_NO_START=1 P seed omicron --file "$SB" --no-launch --no-fetch)" 0 "alias --no-launch"
has "$T/out" "start it: \`/pickup 'claude/$HN/$TODAY-omicron' --fresh\` in a demo tab" "…prints the start line as --no-start does"
hasnt "$T/out" "vscode://" "…and opens nothing"
check "$(CLAUDE_CODE_SESSION_ID=$Q CLAUDE_CODE_ENTRYPOINT=sdk-cli P open sigma --repo "$T/buildbox" --fresh --dry-run --no-fetch)" 1 "from the phone, another repo's seed still stops"
has "$T/out" "it is buildbox's: open that repo's window" "…rather than adopting another repo's worktree here"
# from VS Code with a `code` CLI: that repo's pre-filled tab — and none to be had is no Terminal (review 2026-10-14)
check "$(CLAUDE_CODE_SESSION_ID=$Q PICKUP_VSCODE_CLI="$T/code2" CODE2_STATUS="$T/status" CODE2_LOG="$T/code2.log" PICKUP_NO_START=1 P seed phi --file "$SB" --repo "$T/buildbox" --no-fetch)" 0 "seed in another repo from VS Code"
has "$T/out" "→ foreign-vscode" "…its window's tab is the plan"
has "$T/out" "nothing started: type" "…no window of that repo shows up: nothing starts"
hasnt "$T/out" "claude --name" "…no Terminal window without --start"
check "$(CLAUDE_CODE_SESSION_ID=$Q PICKUP_VSCODE_CLI="$T/code2" CODE2_STATUS="$T/status" CODE2_LOG="$T/code2.log" PICKUP_NO_START=1 P seed chi --file "$SB" --repo "$T/buildbox" --start --no-fetch)" 0 "…with --start"
has "$T/out" "buildbox: claude --name" "…the Terminal window \"start it\" asks for"
git clone -q "$O" "$T/off" && git -C "$T/off" remote set-url origin "$T/nowhere.git"
check "$(CLAUDE_CODE_SESSION_ID=$Q P seed upsilon --file "$SB" --repo "$T/off" --no-start --no-fetch)" 0 "origin unreachable: seeded anyway"
has "$T/out" "⚠ not pushed — on this machine only until: git -C" "…with the push line (R5)"
check "$(CLAUDE_CODE_SESSION_ID=$Q PICKUP_NO_START=1 P seeds --mine --open --no-fetch)" 0 "seeds --mine --open, /finish's second chance (D2 c)"
has "$T/out" "seed omega · $SN in demo" "…lists this session's seeds"
has "$T/out" "seed phi · " "…every one"
has "$T/out" "prompt=%2Fpickup%20%27claude%2F$HN%2F$TODAY-phi%27%20--fresh" "…and opens a tab for each"
check "$(P seeds --mine --no-fetch)" 0 "seeds --mine from a session that seeded nothing"
has "$T/out" "no seed waiting from this session" "…says so"

echo "seeds started elsewhere — a WIP: PR, nothing committed (docs/record/branch-reaping-2026-10-04.md E3)"
cp "$PICKUP_PRS" "$T/prs.saved"
python3 - "$PICKUP_PRS" "claude/$HN/$TODAY-phi" <<'PY'
import json, sys
p, ref = sys.argv[1:3]
prs = json.load(open(p))
prs.append({"number": 9, "state": "open", "draft": True, "title": "WIP: phi", "html_url": "https://example.test/pull/9",
            "updated_at": "2026-10-04T06:00:00Z", "head": {"ref": ref},
            "body": "Agent work in progress on **buildbox**, session `9f9f9f9f`."})
json.dump(prs, open(p, "w"))
PY
check "$(P list --no-fetch)" 0 "list with phi's WIP PR from the build Mac"
has "$T/out" "seed — started on buildbox (PR #9), nothing committed; brief docs/handoff/$TODAY-phi.md" "…phi reads started on buildbox, not 'not started'"
has "$T/out" "seed — not started; brief docs/handoff/$TODAY-omega.md" "…omega, with no PR, still reads not started"
check "$(CLAUDE_CODE_SESSION_ID=$Q P seeds --mine --no-fetch)" 0 "seeds --mine"
has "$T/out" "seed omega · $SN in demo" "…lists the seed nobody ran"
hasnt "$T/out" "seed phi · " "…but not the one the build Mac ran: /finish opens no second tab for it"
check "$(P archive phi --confirmed --no-fetch)" 1 "archive of the seed the build Mac started: refused"
has "$T/out" "a seed a session has started (started on buildbox (PR #9)" "…naming where it runs"
python3 - "$PICKUP_PRS" <<'PY'
import json, sys
prs = json.load(open(sys.argv[1]))
for p in prs:
    if p["number"] == 9:
        p["title"], p["draft"] = "phi: the work", False
json.dump(prs, open(sys.argv[1], "w"))
PY
check "$(P archive phi --confirmed --no-fetch)" 1 "archive of a seed whose PR the build Mac readied (no longer WIP:): refused"
has "$T/out" "PR #9 is open — a session has it" "…an open PR is enough"
cp "$T/prs.saved" "$PICKUP_PRS"
SQ=$(python3 - "$WHOOKS" "$R" "$SN" <<'PY'
import sys; sys.path.insert(0, sys.argv[1]); import branches
repo, sn = sys.argv[2:4]
base = branches.out(repo, "merge-base", "main", sn)
tree = branches.out(repo, "rev-parse", f"{sn}^{{tree}}")
after = branches.out(repo, "commit-tree", tree, "-p", sn, "-m", "work")  # a commit after the seed, no ref
print(branches.seed_only(repo, base, sn), branches.seed_only(repo, base, after))
PY
)
check "$SQ" "True False" "branches.seed_only: omega is a seed, and is not once a commit follows (one definition, R7)"
echo "a seed nobody wants has an exit: the owner's archive takes an unstarted one (followup-handoff review, applied 2026-10-11)"
stip=$(git rev-parse $SN)
check "$(P archive omega --no-fetch)" 1 "archive of a seed without --confirmed: refused"
check "$(P archive omega --confirmed --no-fetch)" 0 "archive --confirmed of the unstarted seed: done"
has "$T/out" "archived $SN — Unstarted seed, dropped by Sam" "…with a seed's reason, not 'probably launched'"
git show-ref -q --verify refs/heads/$SN; check $? 1 "…the branch is gone from the list"
check "$(git rev-parse refs/archive/$SN)" "$stip" "…kept under refs/archive at its tip"
git ls-remote --exit-code -q origin "refs/heads/$SN" >/dev/null; check $? 2 "…and its GitHub copy went"
grep -q " refs/archive/$SN Unstarted seed, dropped by Sam$" "$(git rev-parse --path-format=absolute --git-common-dir)/claude/archived"; check $? 0 "…the reason in the record"

echo "seed with a blueprint — the handoff as a one-block ship beside its brief (wharf-on-orca S5, B9)"
SBP="$T/brief-bp.md"; BPN=claude/$HN/$TODAY-bluep
printf '# bluep — handoff from demo: tests, %s\nTask: a one-block ship\nTier: Opus 5.5 high\nWhy: evidence\nStart here: a\nDone means: b\nNot this: c\n' "$TODAY" > "$SBP"
check "$(CLAUDE_CODE_SESSION_ID=$Q PICKUP_NO_START=1 P seed bluep --file "$SBP" --no-fetch)" 0 "a complete brief seeds"
has "$T/out" "and its one-block blueprint docs/blueprints/$TODAY-bluep.md" "…and says it wrote the blueprint"
check "$(git diff --name-only main $BPN | tr '\n' ' ')" "docs/blueprints/$TODAY-bluep.md docs/handoff/$TODAY-bluep.md " "…the brief and the blueprint, in the one commit"
check "$(git log --format=%s main..$BPN)" "Seed: bluep" "…still one Seed: commit"
git show $BPN:docs/blueprints/$TODAY-bluep.md | grep -q '^    provider: claude-code$'; check "$?" "0" "…whose block is claude-code"
SQ=$(python3 - "$WHOOKS" "$R" "$BPN" <<'PY'
import sys; sys.path.insert(0, sys.argv[1]); import branches
repo, sn = sys.argv[2:4]
base = branches.out(repo, "merge-base", "main", sn)
print(branches.seed_only(repo, base, sn))
PY
)
check "$SQ" "True" "branches.seed_only: a seed with its blueprint is still a seed (the reaper's definition)"
check "$(P show bluep --no-fetch)" 0 "show"
has "$T/out" "seed — not started; brief docs/handoff/$TODAY-bluep.md" "…marks it a seed, not started, its brief the handoff (pickup's seed test knows the blueprint beside it)"
check "$(CLAUDE_CODE_SESSION_ID=$Q PICKUP_NO_START=1 P seed bluep2 --file "$SBP" --no-fetch --no-blueprint)" 0 "--no-blueprint seeds"
check "$(git diff --name-only main claude/$HN/$TODAY-bluep2)" "docs/handoff/$TODAY-bluep2.md" "…the brief alone"
has "$T/out" "seeded claude/$HN/$TODAY-bluep2" "…said as a seed"
hasnt "$T/out" "blueprint" "…and nothing about a blueprint"
CLAUDE_CODE_SESSION_ID=$Q PICKUP_NO_START=1 P seed bluep3 --file "$SBP" --no-fetch --dry-run >/dev/null
has "$T/out" "and docs/blueprints/$TODAY-bluep3.md" "--dry-run names the blueprint it would commit"
CLAUDE_CODE_SESSION_ID=$Q PICKUP_NO_START=1 P seed yes --file "$SBP" --no-fetch --dry-run >/dev/null
has "$T/out" "and docs/blueprints/$TODAY-yes.md" "a topic YAML reads as a bool (yes) still gets its blueprint: the scalars are quoted"
# a blueprint of that name already on main is a ship's own: never overwritten by a one-block one
mkdir -p "$R/docs/blueprints"; echo "a ship" > "$R/docs/blueprints/$TODAY-bluep4.md"; git -C "$R" add docs/blueprints; git -C "$R" commit -qm "a ship's blueprint of that name"
check "$(CLAUDE_CODE_SESSION_ID=$Q PICKUP_NO_START=1 P seed bluep4 --file "$SBP" --no-fetch)" 0 "a blueprint of the same name on main: the seed still goes"
check "$(git diff --name-only main claude/$HN/$TODAY-bluep4)" "docs/handoff/$TODAY-bluep4.md" "…the brief alone, the ship's blueprint untouched"
has "$T/out" "docs/blueprints/$TODAY-bluep4.md is already on main" "…and says why"

echo "move: the conversation goes with its branch (teleport design E2, E3)"
# mu: a worktree here with a file never committed, worked on by the session running the move.
# Its transcript holds one finished turn and the current one (the /move itself, its tool call
# dangling), a subagent, a tool result and a scratchpad. the build Mac is the ssh-peer stand-in.
export PICKUP_SCRATCH_ROOT="$T/scratch"
BM=claude/laptop/2026-10-03-mu; WM="$R/.claude/worktrees/mu"; MS=f0f0f0f0-0000-4000-8000-00000000000f
git worktree add -q "$WM" -b $BM main && commit "$WM" m.txt f0f0f0f0 "start mu" && git -C "$WM" push -q -u origin $BM
echo half > "$WM/wip.txt"
PM="$HOME/.claude/projects/$(slug "$WM")/$MS.jsonl"; mkdir -p "$(dirname "$PM")"
python3 - "$PM" $MS "$WM" $BM "$HOME" <<'PY'
import json, sys
f, sid, cwd, branch, home = sys.argv[1:6]
rec = lambda r: json.dumps(r, separators=(",", ":"))
base = {"cwd": cwd, "sessionId": sid, "gitBranch": branch, "entrypoint": "claude-vscode", "isSidechain": False}
lines = [
  {**base, "type": "user", "promptId": "p1", "uuid": "u1", "parentUuid": None, "timestamp": "2026-10-03T08:00:00.000Z",
   "origin": {"kind": "human"}, "message": {"role": "user", "content": "build mu"}},
  {**base, "type": "assistant", "uuid": "a1", "parentUuid": "u1", "timestamp": "2026-10-03T08:01:00.000Z", "effort": "high",
   "message": {"model": "claude-opus-5-5", "role": "assistant", "content": [{"type": "text", "text": "Built mu; notes in " + home + "/projects/demo/.claude/worktrees/mu/m.txt"}]}},
  {"type": "ai-title", "aiTitle": "Mu build", "sessionId": sid},
  {**base, "type": "user", "promptId": "p2", "uuid": "u2", "parentUuid": "a1", "timestamp": "2026-10-03T09:00:00.000Z",
   "origin": {"kind": "human"}, "message": {"role": "user", "content": "/move --to-home"}},
  {**base, "type": "assistant", "uuid": "a2", "parentUuid": "u2", "timestamp": "2026-10-03T09:00:05.000Z", "effort": "high",
   "message": {"model": "claude-opus-5-5", "role": "assistant", "content": [{"type": "tool_use", "id": "toolu_DANGLING", "name": "Bash", "input": {}}]}}]
open(f, "w").write("\n".join(rec(r) for r in lines) + "\n")
PY
mkdir -p "${PM%.jsonl}/subagents" "${PM%.jsonl}/tool-results"
echo "{\"type\":\"assistant\",\"sessionId\":\"$MS\",\"timestamp\":\"2026-10-03T08:00:30.000Z\"}" > "${PM%.jsonl}/subagents/agent-m.jsonl"
echo "a tool's long output" > "${PM%.jsonl}/tool-results/out.txt"
PAD="$PICKUP_SCRATCH_ROOT/$(slug "$WM")/$MS/scratchpad"; mkdir -p "$PAD" && echo "draft" > "$PAD/note.txt"
cp "$HOME/.gitconfig" "$IH/.gitconfig"
echo "TOKEN=y" > "$IH/projects/demo/.env"
MV() { CLAUDE_CODE_SESSION_ID=$MS PICKUP_SSH="$T/ssh-peer" PICKUP_NO_START=1 P move "$@" --repo "$WM" --no-fetch; }
check "$(MV --to buildbox)" "3" "a subagent wrote seconds ago: refused"
has "$T/out" "still running (agent-m.jsonl" "…naming it"
check "$(git -C "$WM" status --porcelain | wc -l | tr -d ' ')" "1" "…and nothing was committed"
touch -t 202601010000 "${PM%.jsonl}/subagents/agent-m.jsonl"
# The Bash call running the move writes its own tasks/<id>.output — its stdout and stderr
# (2026-10-04, seen with lsof). That file is the caller, not a background task.
TK="$PICKUP_SCRATCH_ROOT/$(slug "$WM")/$MS/tasks"; mkdir -p "$TK" && echo "running" > "$TK/bgtask.output"
check "$(MV --to buildbox --dry-run)" "3" "a background task wrote seconds ago: refused"
has "$T/out" "still running (bgtask.output" "…naming it"
touch -t 202601010000 "$TK/bgtask.output"
MVOWN() { MV --to buildbox --dry-run; echo $?; }  # MV with P's redirect to $T/out undone: the caller's own file is the output
P() { python3 "$B/pickup" "$@"; }
MVOWN > "$TK/own.output" 2>&1; check "$(tail -1 "$TK/own.output")" "0" "the only fresh file is the caller's own output: passes the gate"
has "$TK/own.output" "would commit 1 file(s)" "…and the move goes on"
rm -f "$TK/own.output"
sleep 30 > "$TK/bg-live.output" & BGP=$!
MVOWN > "$TK/own.output" 2>&1; check "$(tail -1 "$TK/own.output")" "3" "…but a live background task beside it still refuses"
has "$TK/own.output" "still running (bg-live.output" "…naming the task, not the caller"
kill $BGP; wait $BGP 2>/dev/null; rm -f "$TK/bg-live.output" "$TK/own.output"
( MVOWN 2>&1 | cat ) > "$TK/own.output" 2>&1
has "$TK/own.output" "would commit 1 file(s)" "…also when the call pipes it (a shell above holds the file)"
rm -f "$TK/own.output"
P() { python3 "$B/pickup" "$@" > "$T/out" 2>&1; echo $?; }
check "$(MV --to laptop)" "3" "--to this machine's own name: refused"
check "$(MV --to buildbox --dry-run)" "0" "--dry-run"
has "$T/out" "would commit 1 file(s) and push $BM" "…names the commit and push"
check "$(MV --to home)" "0" "move --to home (buildbox)"
has "$T/out" "cut before its current turn (2026-10-03T08:59:59.999Z), claude-opus-5-5 / high" "the cut is before the /move turn, the model read"
check "$(git -C "$WM" status --porcelain)" "" "what was uncommitted is committed"
check "$(git --git-dir="$O" rev-parse $BM)" "$(git -C "$WM" rev-parse HEAD)" "origin has the tip"
IW2="$IH/projects/demo/.claude/worktrees/mu"
check "$(git -C "$IW2" rev-parse HEAD 2>/dev/null)" "$(git -C "$WM" rev-parse HEAD)" "the worktree on buildbox is at the tip"
check "$(readlink "$IW2/.env")" "$IH/projects/demo/.env" "…with its .env linked"
check "$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print(d["model"],d["effortLevel"],d["modelSettings"]["claude-opus-5-5"]["effortLevel"])' "$IW2/.claude/settings.local.json")" \
  "claude-opus-5-5 high high" "…and the model and effort pinned in settings.local.json"
F2=$(ls "$IH/.claude/projects/$(slug "$IW2")"/*.jsonl | head -1); N2=$(basename "$F2" .jsonl)
has "$T/out" "→ moved to buildbox as $N2" "the closing line names the new id"
has "$F2" "\"type\":\"forked-from\"" "the fork says what it inherited"
has "$F2" "\"cutoff\":\"2026-10-03T08:01:00.000Z\"" "…cut at the last record before the /move turn"
hasnt "$F2" "/move --to-home" "the /move prompt stays behind"
hasnt "$F2" "toolu_DANGLING" "…and so does its dangling tool call"
hasnt "$F2" "$HOME/" "no path under this machine's home is left"
has "$F2" "\"cwd\":\"$IW2\"" "its cwd is buildbox's worktree"
check "$(tail -1 "$F2")" "{\"type\":\"relocated\",\"sessionId\":\"$N2\",\"relocatedCwd\":\"$IW2\"}" "it ends relocated to that worktree"
has "$IH/.claude/projects/$(slug "$IW2")/$N2/subagents/agent-m.jsonl" "\"sessionId\":\"$N2\"" "a subagent's records carry the fork's id"
check "$(cat "$IH/.claude/projects/$(slug "$IW2")/$N2/tool-results/out.txt")" "a tool's long output" "tool results are carried"
check "$(cat "$PICKUP_SCRATCH_ROOT/$(slug "$IW2")/$N2/scratchpad/note.txt")" "draft" "the scratchpad is carried"
has "$T/out" "not opened (PICKUP_NO_START): vscode://anthropic.claude-code/open?session=$N2" "the VS Code link opens the fork"
has "$T/out" "Moved%20from%20$HM%20with%20%2Fmove" "…its first message says where it came from"
has "$T/out" "on buildbox: cd $IW2 && claude --resume $N2 --model claude-opus-5-5 --effort high" "without the proof, the Terminal line"
GM="$(git -C "$WM" rev-parse --absolute-git-dir)/claude/teleported.json"
check "$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print(d["to"],d["session"],d["from_session"],d["pending"])' "$GM")" \
  "buildbox $N2 $MS False" "the marker here names where it went"
check "$(grep -c . "$PM")" "5" "the source transcript is untouched"
check "$(MV --to buildbox)" "3" "a second move of the same branch: refused"
has "$T/out" "has already gone: ⇢ moved to buildbox" "…naming where"
check "$(PICKUP_SSH="$T/ssh-peer" P move --check "$N2" --no-fetch)" "1" "--check before a reply there"
echo "{\"type\":\"assistant\",\"sessionId\":\"$N2\",\"effort\":\"medium\",\"timestamp\":\"2026-10-03T10:00:00.000Z\",\"message\":{\"model\":\"claude-opus-5-5\",\"content\":[]}}" >> "$F2"
check "$(PICKUP_SSH="$T/ssh-peer" P move --check "$N2" --no-fetch)" "3" "--check: the effort differs (R2)"
has "$T/out" "source claude-opus-5-5 / high, here claude-opus-5-5 / medium" "…names both"

echo "move --from: the return leg"
echo more > "$IW2/later.txt"
echo "{\"pid\":$$,\"sessionId\":\"$N2\",\"cwd\":\"$IW2\",\"entrypoint\":\"sdk-cli\",\"status\":\"busy\",\"statusUpdatedAt\":$(( $(date +%s) * 1000 )),\"name\":\"demo-mu\"}" > "$IH/.claude/sessions/$$.json"
check "$(MV mu --from buildbox)" "3" "the session there is mid-turn: refused"
has "$T/out" "is mid-turn on $BM" "…and says so"
sed -i '' 's/"status":"busy"/"status":"idle"/' "$IH/.claude/sessions/$$.json"
check "$(MV mu --from buildbox)" "0" "move --from buildbox"
IM2="$(git -C "$IW2" rev-parse --absolute-git-dir)/claude/teleported.json"
check "$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["to"])' "$IM2")" "$HM" "buildbox's worktree is marked, moved here"
check "$(git -C "$IW2" status --porcelain)" "" "what it left is committed there"
check "$(git -C "$WM" log -1 --format=%s)" "wip: moved to $HM" "…pushed, and fast-forwarded here"
check "$([ -f "$GM" ] && echo marked || echo cleared)" "cleared" "this worktree's marker is cleared"
F3=$(ls -t "$HOME/.claude/projects/$(slug "$WM")"/*.jsonl | head -1); N3=$(basename "$F3" .jsonl)
check "$(tail -1 "$F3" | grep -c "\"relocatedCwd\":\"$WM\"")" "1" "it arrives in this worktree, where its pin is read"
has "$F3" "\"from\":{\"sessionId\":\"$N2\",\"host\":\"buildbox\"}" "the fork here names buildbox's session"
hasnt "$F3" "$IH/" "no buildbox path is left in it"
check "$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["effortLevel"])' "$WM/.claude/settings.local.json")" "medium" "the pin is buildbox's last model and effort"
has "$T/out" "ssh buildbox-ssh $RCH --end ${N2:0:8}" "the end line for the session there, never run (D4)"
has "$T/out" "→ moved from buildbox as $N3" "…and the closing line"
rm -f "$IH/.claude/sessions/$$.json"

echo "move --prepare, --cancel, and the gates on the other side"
check "$(CLAUDE_CODE_SESSION_ID=$MS PICKUP_SSH="$T/ssh-down" P move --to buildbox --repo "$WM" --no-fetch)" "0" "buildbox down: prepared instead"
has "$T/out" "preparing the move instead" "…and says so"
has "$T/out" "→ on this machine, once buildbox answers: /move --to-buildbox" "…with the line for later"
check "$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["pending"])' "$GM")" "True" "the marker is pending"
check "$(MV --cancel)" "0" "--cancel"
check "$([ -f "$GM" ] && echo marked || echo cleared)" "cleared" "…drops the pending marker"
check "$(MV mu --from buildbox)" "3" "a second --from of a branch that already left buildbox: refused"
has "$T/out" "has already left buildbox" "…naming it"
echo dirt > "$IW2/x.txt"
check "$(MV --to buildbox)" "3" "a dirty worktree for the branch on buildbox: refused"
has "$T/out" "uncommitted file(s) (x.txt" "…naming the file"
check "$([ -f "$GM" ] && echo marked || echo none)" "none" "…before anything here is marked"
rm "$IW2/x.txt"

echo "move: a second round trip (review 2026-10-03, repros A and B)"
check "$(MV --to buildbox)" "0" "back to buildbox, where the last return leg left its marker"
check "$([ -f "$IM2" ] && echo marked || echo cleared)" "cleared" "…that marker is cleared, so the session there can write"
has "$T/out" "the marker of its last trip back cleared" "…and the move says so"
N4=$(sed -n 's/.*→ moved to buildbox as \([0-9a-f-]*\).*/\1/p' "$T/out")
echo late > "$IW2/late.txt" && git -C "$IW2" add late.txt && git -C "$IW2" commit -qm "late, not pushed"
LATE=$(git -C "$IW2" rev-parse HEAD)
echo "{\"pid\":$$,\"sessionId\":\"$N4\",\"cwd\":\"$IW2\",\"entrypoint\":\"claude-vscode\",\"status\":\"idle\",\"statusUpdatedAt\":$(( $(date +%s) * 1000 )),\"name\":\"demo-mu-2\"}" > "$IH/.claude/sessions/$$.json"
check "$(MV mu --from buildbox)" "0" "back again: a clean worktree there with a commit not pushed"
check "$(git --git-dir="$O" rev-parse $BM)" "$LATE" "…the commit is pushed before the marker stays"
check "$(git -C "$WM" rev-parse HEAD)" "$LATE" "…and it is here"
F5=$(ls -t "$HOME/.claude/projects/$(slug "$WM")"/*.jsonl | head -1)
has "$F5" "\"from\":{\"sessionId\":\"$N4\",\"host\":\"buildbox\"}" "the conversation carried is the live one there, not the last committer's"
has "$T/out" "close session ${N4:0:8} \"demo-mu-2\" on buildbox" "…and the end line names it"
rm -f "$IH/.claude/sessions/$$.json"
check "$(P move --to buildbox --repo "$SIB" --no-fetch)" "3" "a repo off the workflow: refused (E4 review a)"
has "$T/out" "not on the worktree workflow" "…and says why"

echo "move: the cloud (teleport design E6)"
echo cloudy > "$WM/c.txt"
check "$(MV --to cloud)" "0" "move --to cloud"
check "$(git -C "$WM" status --porcelain)" "" "what was uncommitted is committed"
check "$(git --git-dir="$O" rev-parse $BM)" "$(git -C "$WM" rev-parse HEAD)" "…and pushed"
check "$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print(d["to"],d["session"],d["from_session"])' "$GM")" \
  "cloud None $MS" "the marker says the cloud, with no session id yet"
N7=$(sed -n 's/.*claude --resume \([0-9a-f-]*\) .*/\1/p' "$T/out")
has "$T/out" "not opened (PICKUP_NO_START) in $WM: claude --resume $N7 --model claude-opus-5-5 --effort high --name 'demo: mu' /teleport" \
  "a Terminal window continues a fork with /teleport first, model and effort as flags"
F7="$HOME/.claude/projects/$(slug "$WM")/$N7.jsonl"
has "$F7" "\"type\":\"forked-from\"" "the fork is made here and says what it inherited"
hasnt "$F7" "toolu_DANGLING" "…cut before the /move turn, its dangling tool call left behind"
check "$(tail -1 "$F7")" "{\"type\":\"relocated\",\"sessionId\":\"$N7\",\"relocatedCwd\":\"$WM\"}" "…relocated into the worktree, never the root on main"
has "$T/out" "if /teleport there only offers to pull: cd $WM && claude --cloud 'Continue the work on branch $BM" "…with the fallback beside it"
check "$(MV --to cloud)" "3" "a second move to the cloud: refused"
check "$(MV --cancel)" "0" "--cancel takes a cloud marker back"
check "$([ -f "$GM" ] && echo marked || echo cleared)" "cleared" "…and the worktree takes writes again"
check "$(MV --to cloud)" "0" "to the cloud again, nothing left to commit"
# The cloud session pushes to the branch and signs its commit with its link (design E6 (c)).
CS=session_01AbCdEfGh1234567890; git clone -q "$O" "$T/cloud" && git -C "$T/cloud" checkout -q $BM
(cd "$T/cloud" && echo up > cloud.txt && git add cloud.txt && git commit -qm "Cloud work

https://claude.ai/code/$CS" && git push -q origin $BM) && git -C "$R" fetch -q origin
CLOUD_TIP=$(git -C "$T/cloud" rev-parse HEAD)
check "$(MV --cancel)" "3" "--cancel once the cloud has pushed: refused"
has "$T/out" "has pushed to $BM since the move" "…it arrived, so writing here would diverge"
# A checkpoint commit quoting a prompt that holds the link is no cloud session's own (review 2026-10-03).
commit "$WA" q.txt aaaaaaaa "/move --from-cloud https://claude.ai/code/$CS"
check "$(MV alpha --from cloud)" "3" "a branch no cloud session pushed to: refused, a quoted link does not count"
has "$T/out" "no commit on $BA carries a claude.ai/code/session_" "…and says so"
check "$(MV session_01NoSuchSession000 --from cloud)" "3" "an id no branch carries: refused"
check "$(MV "https://claude.ai/code/$CS" --from cloud --dry-run)" "0" "a claude.ai/code link finds its branch"
has "$T/out" "$BM → move from the cloud: $CS" "…and its session"
check "$(MV $CS --from cloud --dry-run)" "0" "so does a bare id, past the commit on alpha that quotes it"
has "$T/out" "$BM → move from the cloud: $CS" "…to the branch the cloud pushed to"
has "$T/out" "would catch up the worktree here and run: claude -p --teleport $CS" "…headless first"
check "$(MV mu --from cloud)" "0" "move --from cloud, by topic, no copy written"
check "$(git -C "$WM" rev-parse HEAD)" "$CLOUD_TIP" "the worktree here has the cloud's commit"
check "$([ -f "$GM" ] && echo marked || echo cleared)" "cleared" "…and its cloud marker is cleared"
has "$T/out" "not opened (PICKUP_NO_START) in $WM: claude --teleport $CS --name 'demo: mu'" "no copy: claude --teleport in a Terminal window"
# A stub claude for the headless leg: it writes the local copy (the cloud's turn on Fable, then the
# "ready" turn on this machine's default) and prints the -p JSON naming it.
cat > "$T/claude-stub" <<'STUB'
#!/usr/bin/env python3
import json, os, re, sys, uuid
from pathlib import Path
assert sys.argv[1:4] == ["-p", "--teleport", "session_01AbCdEfGh1234567890"], sys.argv
sid, cwd = str(uuid.uuid4()), os.getcwd()
d = Path(os.environ["HOME"], ".claude", "projects", re.sub(r"[^A-Za-z0-9]", "-", cwd)); d.mkdir(parents=True, exist_ok=True)
rec = lambda **r: json.dumps({"sessionId": sid, "cwd": cwd, **r})
(d / f"{sid}.jsonl").write_text("\n".join([
  rec(type="user", promptId="c1", timestamp="2026-10-03T11:00:00.000Z", message={"role": "user", "content": "cloud work"}),
  rec(type="assistant", timestamp="2026-10-03T11:01:00.000Z", effort="high", message={"model": "claude-fable-5-1", "content": []}),
  rec(type="user", promptId="c2", timestamp="2026-10-03T12:00:00.000Z", message={"role": "user", "content": "Say ready, nothing else."}),
  rec(type="assistant", timestamp="2026-10-03T12:00:02.000Z", effort="medium", message={"model": "claude-opus-5-5", "content": []})]) + "\n")
print(json.dumps({"type": "result", "session_id": sid, "result": "ready"}))
STUB
chmod +x "$T/claude-stub"
check "$(PICKUP_CLAUDE="$T/claude-stub" MV mu --from cloud)" "0" "move --from cloud, the headless copy written"
N6=$(sed -n 's/.*→ moved from the cloud as \([0-9a-f-]*\).*/\1/p' "$T/out")
check "$([ -n "$N6" ] && [ -f "$HOME/.claude/projects/$(slug "$WM")/$N6.jsonl" ] && echo here)" "here" "the copy is in this worktree's slug"
check "$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print(d["model"],d["effortLevel"])' "$WM/.claude/settings.local.json")" \
  "claude-fable-5-1 high" "the pin is the cloud's last model, not the ready turn's"
has "$T/out" "not opened (PICKUP_NO_START): vscode://anthropic.claude-code/open?session=$N6" "the copy opens in VS Code"
has "$T/out" "Moved%20from%20the%20cloud%20with%20%2Fmove" "…its first message says where it came from"
has "$T/out" "archive it there once this one runs" "the cloud session is the owner's to archive (D4)"
echo "status per session — code rules only (bin/session_status.py; docs/record/jev-sessions-bench-2026-10-02.md D2, D5, D6)"
BT=claude/laptop/2026-09-26-theta
git worktree add -q "$T/th" -b $BT main && commit "$T/th" t.txt tttttttt "theta" && git worktree remove "$T/th"
ST="$HOME/.claude/projects/$(slug "$R")"
# one session file per status: <id8> <cwd> <kind> <last reply> — kind: text, pending (a tool call
# with no result), answered (a pending call, then the owner's next prompt and a plain reply), apierror
python3 - "$ST" "$BT" "$R" "$HOME/projects" <<'PY'
import json, sys
d, branch, repo, root = sys.argv[1:5]
rec = lambda r: json.dumps(r, separators=(",", ":"))
def asst(sid, cwd, content, n, **extra):
    return rec({"parentUuid": None, "isSidechain": False, "message": {"model": extra.pop("model", "claude-opus-5-5"), "id": "msg_%d" % n,
                "type": "message", "role": "assistant", "content": content}, "type": "assistant", "uuid": "a%d" % n,
                "timestamp": "2026-09-26T06:0%d:00.000Z" % n, "cwd": cwd, "sessionId": sid, "gitBranch": branch, **extra})
def human(sid, cwd, text, n):
    return rec({"parentUuid": None, "isSidechain": False, "type": "user", "message": {"role": "user", "content": text},
                "uuid": "u%d" % n, "timestamp": "2026-09-26T06:0%d:00.000Z" % n, "entrypoint": "claude-vscode", "cwd": cwd,
                "sessionId": sid, "gitBranch": branch, "origin": {"kind": "human"}})
text = lambda t: [{"type": "text", "text": t}]
tool = [{"type": "text", "text": "Deploying."}, {"type": "tool_use", "id": "toolu_01PEND", "name": "Bash", "input": {"command": "deploy"}}]
CASES = [
    ("d0000001", repo, "text", "Shipped.\n\nSAM, IT'S FINE — THIS SESSION IS REALLY DONE. YOU HAVEN'T FORGOTTEN ANYTHING."),
    ("d0000002", repo, "text", "One open item above.\n\nSAM, THIS SESSION IS DONE — BUT READ THE NOTE ABOVE BEFORE YOU CLOSE IT."),
    ("d0000003", repo, "text", "Two options in D1.\n\nSAM, THIS SESSION IS WAITING FOR YOU — pick A or B in D1."),
    ("d0000004", repo, "pending", ""),
    ("d0000005", repo, "apierror", "Failed to authenticate: OAuth session expired and could not be refreshed"),
    ("d0000006", repo, "text", "Answer under D1 here: https://github.com/o/r/edit/claude/x/docs/a.md"),
    ("d0000007", repo, "text", "The build is green.\n\nShall I deploy it?"),
    ("d0000008", repo, "text", "The draft is in docs/x.md; paste it into the form when it suits."),
    ("d0000009", repo, "text", "The report is written to docs/report.md."),
    ("d0000010", repo, "answered", "Noted, the report stands."),
    ("d0000011", repo, "text", "SAM, IT'S FINE — THIS SESSION IS REALLY DONE. YOU HAVEN'T FORGOTTEN ANYTHING."),  # live and busy
    ("d0000012", root, "text", "SAM, IT'S FINE — THIS SESSION IS REALLY DONE. YOU HAVEN'T FORGOTTEN ANYTHING."),  # began at ~/projects
    ("d0000013", root, "text", "Still filling the sheet."),  # began at ~/projects, and busy
    ("d0000014", repo, "text", "SAM, IT'S FINE — THIS SESSION IS REALLY DONE. YOU HAVEN'T FORGOTTEN ANYTHING."),  # idle, a task writing
    ("d0000015", repo, "text", "The deploy is ready."),  # live, waiting for input
    ("d0000016", repo, "unanswered", "SAM, THIS SESSION IS DONE — BUT READ THE NOTE ABOVE BEFORE YOU CLOSE IT."),
    ("d0000017", repo, "moved", "SAM, THIS SESSION IS WAITING FOR YOU — pick A or B in D1."),
    ("d0000018", repo, "text", "Reviewers started.\n\nSAM, THIS SESSION IS WAITING FOR SOMETHING — the two reviewers."),
]
for id8, cwd, kind, reply in CASES:
    sid = id8 + "-0000-4000-8000-000000000000"
    lines = [human(sid, cwd, "work on theta", 1)]
    if kind in ("pending", "answered"):
        lines.append(asst(sid, cwd, tool, 2))
    if kind == "answered":
        lines += [human(sid, cwd, "stop, never mind", 3), asst(sid, cwd, text(reply), 4)]
    elif kind == "unanswered":  # the owner asked after the reply; nothing answered it
        lines += [asst(sid, cwd, text(reply), 3), human(sid, cwd, "/todo handoff the rest", 6)]
    elif kind == "moved":  # its last reply is on another branch: theta shows no status for it
        lines.append(rec({**json.loads(asst(sid, cwd, text(reply), 3)), "gitBranch": "claude/laptop/2026-09-26-iota"}))
    elif kind == "apierror":
        lines.append(asst(sid, cwd, text(reply), 2, model="<synthetic>", isApiErrorMessage=True, error="authentication_failed"))
    elif kind == "text":
        lines.append(asst(sid, cwd, [{"type": "thinking", "thinking": "hm"}], 2))
        lines.append(asst(sid, cwd, text(reply), 3))
    lines.append(asst(sid, cwd, [{"type": "thinking", "thinking": "a thinking-only record is not the reply"}], 5))
    open("%s/%s.jsonl" % (d, sid), "w").write("\n".join(lines) + "\n")
PY
start=$(TZ=UTC LC_ALL=C ps -o lstart= -p $$ | xargs)
echo "{\"pid\":$$,\"sessionId\":\"d0000011-0000-4000-8000-000000000000\",\"cwd\":\"$R\",\"procStart\":\"$start\",\"status\":\"busy\"}" > "$HOME/.claude/sessions/$$.json"
# live entries for the rest, one file each (the registry is one file per process): d0000011 also
# idle in a second process, on both sides of the busy one in glob order — the busy one still wins
reg() { echo "{\"pid\":$$,\"sessionId\":\"$1-0000-4000-8000-000000000000\",\"cwd\":\"$R\",\"procStart\":\"$start\",\"status\":\"$2\"}" > "$HOME/.claude/sessions/$3.json"; }
reg d0000011 idle 0-before; reg d0000011 idle zz-after
reg d0000013 busy d13; reg d0000014 idle d14; reg d0000015 waiting d15
export PICKUP_SCRATCH_ROOT="${PICKUP_SCRATCH_ROOT:-$T/scratch}"
mkdir -p "$PICKUP_SCRATCH_ROOT/x/d0000014-0000-4000-8000-000000000000/tasks" && echo "filling" > "$PICKUP_SCRATCH_ROOT/x/d0000014-0000-4000-8000-000000000000/tasks/fill.output"
check "$(P list --no-fetch --json)" 0 "list --json"
python3 -c '
import json, sys
for repo in json.load(open(sys.argv[1]))["repos"]:
    for b in repo["branches"]:
        for v in b["sessions"]:
            if v["id"].startswith("d00000"):
                print(v["id"][:8], v["status"], "(%s)" % v["status_rule"] if v["status_rule"] else "")' "$T/out" > "$T/status"
has "$T/status" "d0000001 done (closing line)" "/finish's fixed line: done"
has "$T/status" "d0000002 done — read the note (closing line)" "…with the note: done — read the note (D6)"
has "$T/status" "d0000003 $WAITON (closing line)" "the WAITING line (orchestration A1): waiting on the owner"
has "$T/status" "d0000004 $WAITON (pending tool call)" "a tool call with no result: waiting on the owner"
has "$T/status" "d0000005 blocked (api error)" "Claude Code's API-error stand-in: blocked"
has "$T/status" "d0000006 $WAITON (memo link)" "a memo edit link: waiting on the owner"
check "$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import session_status as s; print(s.code_rule("Both in the doc.\n\n[course](http://127.0.0.1:5123/tok/) | [github](https://github.com/o/r/blob/b/a.md) — [a.md](/x/a.md#L1)")[1])' "$WBIN")" "memo link" "a hand-over line with a form (memo line): waiting on the owner"
check "$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import session_status as s; print(s.code_rule("Both in the doc.\n\n[form](http://127.0.0.1:5123/tok/) | [github](https://github.com/o/r/blob/b/a.md) — [a.md](/x/a.md#L1)")[1])' "$WBIN")" "memo link" "…and a tail from before 2026-10-17, its link labelled form"
has "$T/status" "d0000007 $WAITON (question)" "a last line ending in ?: waiting on the owner"
has "$T/status" "d0000008 $WAITON (ask-words)" "ask-words in the tail, the keyword rule: waiting on the owner"
has "$T/status" "d0000009 unsure" "no rule fires: unsure, never a guess at done"
has "$T/status" "d0000010 unsure" "a call left open before the owner's next prompt is not pending"
has "$T/status" "d0000011 running (live: busy)" "busy in the registry: running, before any text rule (D5)"
has "$T/status" "d0000012 guarded — open it" "a session begun at the ~/projects root: guarded, its text unread (D3)"
has "$T/status" "d0000013 running (live: busy)" "busy and guarded: running — it reads no text"
has "$T/status" "d0000014 running (live: task)" "idle, but a background task wrote seconds ago: running, not its closing line"
has "$T/status" "d0000015 $WAITON (live: waiting)" "the registry waits for input: waiting on the owner"
has "$T/status" "d0000016 unsure" "a prompt after the last reply, never answered: unsure, not the older done"
has "$T/status" "d0000017 None" "a session whose last reply is on another branch: no status on this one"
has "$T/status" "d0000018 waiting on its own work (closing line)" "WAITING FOR SOMETHING: its own status, never running (D5's busy word)"
check "$(wc -l < "$T/status" | xargs)" "18" "…one status per session, none missing"
check "$(P show theta --no-fetch)" 0 "show theta"
has "$T/out" "live now (busy) → running (live: busy)" "the session line ends in its status"
has "$T/out" "→ done — read the note (closing line)" "…for a closed one too"
rm -f "$HOME/.claude/sessions/$$.json" "$HOME/.claude/sessions/"{0-before,zz-after,d13,d14,d15}.json
check "$(cd "$(python3 -c "import sys; sys.path.insert(0, '$CORE'); import common; print(common.tool('usage-report').parent.parent)")/bench/sessions" && python3 test_collect.py > "$T/guard" 2>&1; echo $?)" 0 "the guard's pinned cases (bench/sessions/test_collect.py)"

echo "brief — a handoff brief onto an existing branch, by plumbing (Lookout and Hail design, S4)"
# its own repo and a scratch bare origin, so no case above can bear on it and nothing reaches GitHub
BO="$T/brief-origin.git"; git init -q --bare "$BO"
BR="$HOME/projects/briefdemo"; mkdir -p "$BR/.claude" && git -C "$BR" init -q . && BR=$(cd "$BR" && pwd -P)
echo '{"checkpoint": true, "main": "main"}' > "$BR/.claude/workflow.json"
printf '.claude/worktrees/\n' > "$BR/.gitignore"
git -C "$BR" add -A && git -C "$BR" commit -qm init && git -C "$BR" remote add origin "$BO" && git -C "$BR" push -q origin main
BP() { python3 "$B/pickup" brief "$@" --repo "$BR" > "$T/out" 2>&1; echo $?; }
BTXT=$'# lookout — the next step\nTask: answer the check-in\nWhy: a worker is done'
BTODAY=$(date +%F)
# a brief as dispatch's --next wants it: the file, nothing committed after it, a local branch
brief_ok() {   # BRANCH
  local f; f=$(git -C "$BR" ls-tree -r --name-only "refs/heads/$1" -- docs/handoff | grep -E "^docs/handoff/[0-9]{4}-[0-9]{2}-[0-9]{2}-${1##*-}\.md$" | sort | tail -1)
  [ -n "$f" ] || { echo "no brief"; return; }
  echo "$(git -C "$BR" diff --name-only "$(git -C "$BR" log -1 --format=%H "refs/heads/$1" -- "$f")" "refs/heads/$1" -- . ':!docs/handoff' | wc -l | tr -d ' ') after, $f"
}

# 1: pushed, local, no worktree
BB1=claude/laptop/2026-10-20-bone
git -C "$BR" worktree add -q "$T/bw1" -b $BB1 main && commit "$T/bw1" one.txt 11111111 "work on bone" && git -C "$T/bw1" push -q -u origin $BB1
git -C "$BR" worktree remove "$T/bw1"
check "$(BP $BB1 --text "$BTXT" --no-fetch)" 0 "brief onto a branch with no worktree"
has "$T/out" "briefed $BB1 in briefdemo — docs/handoff/$BTODAY-bone.md, 3 lines; pushed" "…commits and pushes"
check "$(git -C "$BR" show "refs/heads/$BB1:docs/handoff/$BTODAY-bone.md")" "$BTXT" "…the brief is the text, whole"
check "$(git -C "$BR" log -1 --format=%s refs/heads/$BB1)" "Brief: the next step of bone (pickup brief)" "…a Brief: commit, never a Seed: one"
check "$(git -C "$BR" log -1 --format=%B refs/heads/$BB1 | grep -c '^> answer the check-in')" 1 "…quoting the Task: sentence"
check "$(git -C "$BR" rev-parse refs/heads/$BB1)" "$(git -C "$BO" rev-parse refs/heads/$BB1)" "…and origin has the same tip"
check "$(git -C "$BR" log --format=%s refs/heads/$BB1 | wc -l | tr -d ' ')" 3 "…one commit on top of the work (init, work, brief)"
check "$(brief_ok $BB1)" "0 after, docs/handoff/$BTODAY-bone.md" "dispatch's checks: a local branch, the brief last, nothing after it"
check "$(BP $BB1 --text "$BTXT" --no-fetch)" 1 "the same brief again: refused, nothing to add"
has "$T/out" "already on $BB1 as written" "…says so"

# 2: --dry-run writes nothing
BB2=claude/laptop/2026-10-20-btwo
git -C "$BR" worktree add -q "$T/bw2" -b $BB2 main && commit "$T/bw2" two.txt 22222222 "work on btwo" && git -C "$T/bw2" push -q -u origin $BB2
git -C "$BR" worktree remove "$T/bw2"
tip=$(git -C "$BR" rev-parse refs/heads/$BB2)
check "$(BP $BB2 --text "$BTXT" --dry-run --no-fetch)" 0 "brief --dry-run"
has "$T/out" "would brief $BB2 in $BR: commit docs/handoff/$BTODAY-btwo.md (3 lines)" "…says what it would write"
check "$(git -C "$BR" rev-parse refs/heads/$BB2)" "$tip" "…and moved nothing"

# 3: a dirty worktree
BB3=claude/laptop/2026-10-20-bthree; W3="$BR/.claude/worktrees/bthree"
git -C "$BR" worktree add -q "$W3" -b $BB3 main && commit "$W3" three.txt 33333333 "work on bthree" && git -C "$W3" push -q -u origin $BB3
echo half > "$W3/wip.txt"; tip=$(git -C "$BR" rev-parse refs/heads/$BB3)
check "$(BP $BB3 --text "$BTXT" --no-fetch)" 1 "a worktree with an uncommitted file: refused"
has "$T/out" "with uncommitted changes (wip.txt)" "…naming the file"
check "$(git -C "$BR" rev-parse refs/heads/$BB3)" "$tip" "…and the branch did not move"
rm -f "$W3/wip.txt"

# 4: a worktree held by another session, then the same lock marked handed over, then idle for 2 h
GD3=$(git -C "$W3" rev-parse --absolute-git-dir); mkdir -p "$GD3/claude"
python3 -c 'import json,sys,time; json.dump({"session": "99999999-0000-4000-8000-000000000009", "branch": sys.argv[2], "seen": time.time()}, open(sys.argv[1], "w"))' "$GD3/claude/owner.json" $BB3
check "$(CLAUDE_CODE_SESSION_ID=$Q BP $BB3 --text "$BTXT" --no-fetch)" 1 "a worktree another session holds (owner.json, seen now): refused"
has "$T/out" "is held by session 99999999" "…naming the session"
check "$(git -C "$BR" rev-parse refs/heads/$BB3)" "$tip" "…and the branch did not move"
python3 -c 'import json,sys; o=json.load(open(sys.argv[1])); o["handover"]=True; json.dump(o, open(sys.argv[1], "w"))' "$GD3/claude/owner.json"
check "$(CLAUDE_CODE_SESSION_ID=$Q BP $BB3 --text "$BTXT" --no-fetch)" 0 "…the same lock marked handed over holds nobody out"
check "$(git -C "$W3" status --porcelain | wc -l | tr -d ' ')" 0 "…and the worktree moved with the ref: clean, as dispatch needs"
check "$(cat "$W3/docs/handoff/$BTODAY-bthree.md")" "$BTXT" "…with the brief on disk in it"
check "$(brief_ok $BB3)" "0 after, docs/handoff/$BTODAY-bthree.md" "dispatch's checks pass on a worktree-held branch too"
BB3B=claude/laptop/2026-10-20-bthreeb; W3B="$BR/.claude/worktrees/bthreeb"
git -C "$BR" worktree add -q "$W3B" -b $BB3B main && commit "$W3B" threeb.txt 33333334 "work on bthreeb" && git -C "$W3B" push -q -u origin $BB3B
GD3B=$(git -C "$W3B" rev-parse --absolute-git-dir); mkdir -p "$GD3B/claude"
python3 -c 'import json,sys,time; json.dump({"session": "99999999-0000-4000-8000-000000000009", "branch": sys.argv[2], "seen": time.time() - 3 * 3600}, open(sys.argv[1], "w"))' "$GD3B/claude/owner.json" $BB3B
check "$(CLAUDE_CODE_SESSION_ID=$Q BP $BB3B --text "$BTXT" --no-fetch)" 0 "a lock idle 2 h has gone: the brief goes in"

# 5: origin moved on — the local branch is fast-forwarded first
BB5=claude/laptop/2026-10-20-bfive
git -C "$BR" worktree add -q "$T/bw5" -b $BB5 main && commit "$T/bw5" five.txt 55555555 "work on bfive" && git -C "$T/bw5" push -q -u origin $BB5
git -C "$BR" worktree remove "$T/bw5"
git clone -q "$BO" "$T/brief-peer" && git -C "$T/brief-peer" checkout -q $BB5 && commit "$T/brief-peer" five-more.txt 55555556 "the peer's work on bfive" && git -C "$T/brief-peer" push -q origin $BB5
moved=$(git -C "$T/brief-peer" rev-parse HEAD)
check "$(BP $BB5 --text "$BTXT")" 0 "origin moved on: the brief is made on its tip"
has "$T/out" "fast-forwarded from origin" "…says it fast-forwarded"
check "$(git -C "$BR" rev-parse refs/heads/$BB5~1)" "$moved" "…the brief's parent is origin's commit"
check "$(git -C "$BR" ls-tree --name-only refs/heads/$BB5 | grep -c five-more.txt)" 1 "…so the peer's file is in it"
check "$(git -C "$BR" rev-parse refs/heads/$BB5)" "$(git -C "$BO" rev-parse refs/heads/$BB5)" "…and origin has the brief"

# 6: diverged — local and origin each have a commit the other lacks
BB6=claude/laptop/2026-10-20-bsix
git -C "$BR" worktree add -q "$T/bw6" -b $BB6 main && commit "$T/bw6" six.txt 66666666 "work on bsix" && git -C "$T/bw6" push -q -u origin $BB6
commit "$T/bw6" six-local.txt 66666667 "local only"; git -C "$BR" worktree remove "$T/bw6"
git -C "$T/brief-peer" fetch -q origin && git -C "$T/brief-peer" checkout -q -B $BB6 origin/$BB6 && commit "$T/brief-peer" six-peer.txt 66666668 "origin only" && git -C "$T/brief-peer" push -q origin $BB6
tip=$(git -C "$BR" rev-parse refs/heads/$BB6)
check "$(BP $BB6 --text "$BTXT")" 1 "a branch diverged from origin: refused"
has "$T/out" "has diverged from origin/$BB6" "…says so"
check "$(git -C "$BR" rev-parse refs/heads/$BB6)" "$tip" "…and the branch did not move"

# 7: only on origin; no branch anywhere; names, caps, stdin
BB7=claude/laptop/2026-10-20-bseven
git -C "$T/brief-peer" checkout -q -b $BB7 origin/main && commit "$T/brief-peer" seven.txt 77777777 "work on bseven" && git -C "$T/brief-peer" push -q origin $BB7
check "$(BP $BB7 --text "$BTXT")" 0 "a branch only on origin: made local at its tip, with the brief"
check "$(brief_ok $BB7)" "0 after, docs/handoff/$BTODAY-bseven.md" "…and dispatch's checks pass"
check "$(BP claude/laptop/2026-10-20-nowhere --text "$BTXT")" 1 "no such branch: refused"
check "$(BP main --text "$BTXT")" 1 "a name outside claude/*: refused"
check "$(BP $BB1 --text "$(for i in $(seq 1 61); do echo "line $i"; done)" --no-fetch)" 1 "a brief over 60 lines: refused"
check "$(BP $BB1 --text "" --no-fetch)" 1 "an empty brief: refused"
check "$(printf 'Task: from stdin, `kept` and $HOME\n' | python3 "$B/pickup" brief $BB2 --text - --repo "$BR" --no-fetch > "$T/out" 2>&1; echo $?)" 0 "--text -: the brief from stdin"
check "$(git -C "$BR" show "refs/heads/$BB2:docs/handoff/$BTODAY-btwo.md")" 'Task: from stdin, `kept` and $HOME' "…backticks and \$ untouched"

# 8: the review's cases (S4's /finish, 2026-10-21) — each refusal leaves the branch where it was
BB8=claude/laptop/2026-10-20-beight; W8="$BR/.claude/worktrees/beight"
git -C "$BR" worktree add -q "$W8" -b $BB8 main && commit "$W8" eight.txt 88888888 "work on beight" && git -C "$W8" push -q -u origin $BB8
echo edited >> "$W8/eight.txt"; tip=$(git -C "$BR" rev-parse refs/heads/$BB8)
check "$(BP $BB8 --text "$BTXT" --no-fetch)" 1 "an unstaged edit to a tracked file: refused"
has "$T/out" "with uncommitted changes (eight.txt)" "…naming the file whole (a leading-space status line)"
git -C "$W8" checkout -q -- eight.txt
GD8=$(git -C "$W8" rev-parse --absolute-git-dir); mkdir -p "$GD8/claude" && touch "$GD8/claude/finishing"
check "$(BP $BB8 --text "$BTXT" --no-fetch)" 1 "a worktree with a /finish in progress: refused"
has "$T/out" "has a /finish in progress" "…says so"
rm -f "$GD8/claude/finishing"
git -C "$BR" worktree move "$W8" "$T/beight-elsewhere"
check "$(BP $BB8 --text "$BTXT" --no-fetch)" 1 "a worktree outside .claude/worktrees/<topic>: refused"
has "$T/out" "the run needs it at $BR/.claude/worktrees/beight" "…in dispatch's words"
check "$(git -C "$BR" rev-parse refs/heads/$BB8)" "$tip" "…and the branch did not move"
git -C "$T/beight-elsewhere" checkout -q --detach
GD8=$(git -C "$T/beight-elsewhere" rev-parse --absolute-git-dir); mkdir -p "$GD8/rebase-merge" && printf 'refs/heads/%s\n' $BB8 > "$GD8/rebase-merge/head-name"
check "$(BP $BB8 --text "$BTXT" --no-fetch)" 1 "a worktree mid-rebase on the branch (detached): refused"
has "$T/out" "is mid-rebase at" "…says so"
rm -rf "$GD8/rebase-merge"; git -C "$BR" worktree remove --force "$T/beight-elsewhere"

# 9: a branch deleted on origin (landed) is not pushed back into being
BB9=claude/laptop/2026-10-20-bnine
git -C "$BR" worktree add -q "$T/bw9" -b $BB9 main && commit "$T/bw9" nine.txt 99999990 "work on bnine" && git -C "$T/bw9" push -q -u origin $BB9
git -C "$BR" worktree remove "$T/bw9"; git -C "$BO" update-ref -d refs/heads/$BB9
check "$(BP $BB9 --text "$BTXT")" 1 "a branch origin deleted: refused"
has "$T/out" "is not on origin" "…says so"
check "$(git -C "$BO" rev-parse --verify --quiet refs/heads/$BB9 || echo gone)" gone "…and origin still has no such branch"

# 10: a rejected push takes the brief back and fails
BB10=claude/laptop/2026-10-20-bten
git -C "$BR" worktree add -q "$T/bw10" -b $BB10 main && commit "$T/bw10" ten.txt 10101010 "work on bten" && git -C "$T/bw10" push -q -u origin $BB10
git -C "$BR" worktree remove "$T/bw10"; tip=$(git -C "$BR" rev-parse refs/heads/$BB10)
printf '#!/bin/sh\nwhile read o n r; do [ "$r" = refs/heads/%s ] && exit 1; done; exit 0\n' $BB10 > "$BO/hooks/pre-receive"; chmod +x "$BO/hooks/pre-receive"
check "$(BP $BB10 --text "$BTXT")" 1 "a push origin refuses: the call fails"
has "$T/out" "the brief was taken back" "…and says the brief was taken back"
check "$(git -C "$BR" rev-parse refs/heads/$BB10)" "$tip" "…the branch is where it was"
rm -f "$BO/hooks/pre-receive"

# 11: --dry-run with no origin keeps its sentence; a repo off the workflow is refused
BN="$HOME/projects/briefnoorigin"; mkdir -p "$BN/.claude" && git -C "$BN" init -q . && BN=$(cd "$BN" && pwd -P)
echo '{"checkpoint": true, "main": "main"}' > "$BN/.claude/workflow.json"
git -C "$BN" add -A && git -C "$BN" commit -qm init && git -C "$BN" branch claude/laptop/2026-10-20-bnoor
check "$(python3 "$B/pickup" brief claude/laptop/2026-10-20-bnoor --text "$BTXT" --dry-run --repo "$BN" > "$T/out" 2>&1; echo $?)" 0 "--dry-run with no origin"
has "$T/out" "would brief claude/laptop/2026-10-20-bnoor in $BN: commit docs/handoff/$BTODAY-bnoor.md (3 lines)" "…keeps the whole sentence"
has "$T/out" ", no origin: on this machine only" "…ending in the no-origin tail"
touch "$BN/.claude/no-workflow"
check "$(python3 "$B/pickup" brief claude/laptop/2026-10-20-bnoor --text "$BTXT" --repo "$BN" > "$T/out" 2>&1; echo $?)" 1 "a repo with .claude/no-workflow: refused"
has "$T/out" "is not on the worktree workflow" "…as seed refuses it"
cd "$R"

# Hosts are config, never code: the peers are the lines of wharf-runs/ssh (lower-cased), `home` is the
# dispatch host, and a missing dispatch-host key is one stderr line, never a failure.
echo "hosts from the config keys (wharf-runs/ssh, wharf-runs/dispatch-host)"
HK() {   # HK <config dir> <python expression>: the expression's value in a pickup loaded under that config
  REGATTA_CONFIG="$1" python3 - "$B/pickup" "$2" <<'PY'
import importlib.machinery, importlib.util, sys
l = importlib.machinery.SourceFileLoader("pickup_under_test", sys.argv[1])
m = importlib.util.module_from_spec(importlib.util.spec_from_loader("pickup_under_test", l)); l.exec_module(m)
print(eval(sys.argv[2], vars(m)))
PY
}
HC="$T/hostcfg"; mkdir -p "$HC/regatta" "$HC/wharf-runs"; echo laptop > "$HC/regatta/laptop"; echo Sam > "$HC/regatta/owner"
(cd "$B/.." && pwd -P) > "$HC/home"
printf 'BuildBox:buildbox-ssh\n# a comment\nannex:annex-ssh\n' > "$HC/wharf-runs/ssh"
check "$(HK "$HC" 'sorted(PEERS.items())' 2>/dev/null)" "[('annex', 'annex-ssh'), ('buildbox', 'buildbox-ssh')]" "PEERS are the key's lines, the host lower-cased, a comment skipped"
check "$(HK "$HC" 'host_alias("home")' 2>"$T/err")" "buildbox" "no dispatch-host key: home is the first peer…"
has "$T/err" "no wharf-runs/dispatch-host key" "…with one stderr line saying so"
echo annex > "$HC/wharf-runs/dispatch-host"
check "$(HK "$HC" 'host_alias("home")' 2>"$T/err")" "annex" "the dispatch-host key names what home is"
check "$(wc -c < "$T/err" | tr -d ' ')" "0" "…and says nothing on stderr"
check "$(HK "$HC" 'host_alias("laptop") + " " + host_alias("buildbox")' 2>/dev/null)" "laptop buildbox" "laptop is the core's laptop key, any other name stands for itself"
rm "$HC/wharf-runs/ssh" "$HC/wharf-runs/dispatch-host"
check "$(HK "$HC" 'repr(PEERS) + " " + host_alias("home") + " " + dispatch_where()' 2>&1)" "{} home on the dispatch host, the laptop when it does not answer" "no keys at all: no peers, home stays a name peer_alias refuses, no failure"
check "$(HK "$HC" 'a_peer()' 2>&1)" "<host>" "…and a hint names a placeholder: this Mac is the laptop, and no peer is known"
cd "$R"

echo
[ "$fails" -eq 0 ] && echo "all pickup tests pass" || { echo "$fails pickup test(s) FAILED"; exit 1; }
