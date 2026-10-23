#!/usr/bin/env bash
# Tests for bin/interruptions and hooks/attention.py — fixture transcripts, logs and repos under a
# scratch HOME. No network, no model.            bash modules/plumb/tests/interruptions.sh
set -u
B="$(cd "$(dirname "$0")/../bin" && pwd)"   # the module's bin/; hooks/ beside it holds attention.py
T=$(mktemp -d) || exit 1; trap 'rm -rf "$T"' EXIT
# no registry unless a case names one: the Mac's own would fence the fixtures' path-less relay rows
export CLAUDE_REPOS_JSON="$T/no-repos.json"
fails=0
check() { if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3: expected [$2] got [$1]"; fails=$((fails+1)); fi; }

# A config dir of its own: the owner the closing lines address is the fixture's (Sam), and no overlay
# is named, so the core and every peer come from this checkout (the public twin runs it the same).
export REGATTA_CONFIG="$T/config"; mkdir -p "$T/config/regatta"; echo Sam > "$T/config/regatta/owner"
export HOME="$T/home"
export ACCOUNTS_FILE="$T/no-registry.json"   # the readers default to the live config dir's registry since 2026-10-22: never read it here
P="$HOME/projects"
export INTERRUPTIONS_SOURCES="$P/transcripts:$T/live"
export ATTENTION_LOG_DIR="$T/logs/attention"
export INTERRUPTIONS_OUTBOX="$T/outbox"
export INTERRUPTIONS_RUNS="$T/runs"   # bin/dispatch's run records: one names seed-run-0002
mkdir -p "$T/runs"; echo '{"session": "seed-run-0002"}' > "$T/runs/r.json"; echo 'not json' > "$T/runs/bad.json"
export INTERRUPTIONS_LOGINS=""      # the default login only: $HOME/.claude.json
unset CLAUDE_CONFIG_DIR
mkdir -p "$P/transcripts/harbor" "$T/live/-x" "$T/outbox"
NOW=$(python3 -c 'import datetime as d; print(d.datetime.now(d.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z"))')
OLD=2020-01-01T00:00:00.000Z
j() { python3 -c "import json,sys; d=json.load(sys.stdin); print($1)"; }
# keel is a peer two cases read (paste-paths' block_reason, the memo parser); a copy without it (the
# public twin while keel is private) skips those two in one line each
KEEL=$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import find_core; sys.path.insert(0, find_core.hooks()); import common; print(common.tool("keel") or "")' "$B/../lib")

echo "the hook"
out=$(echo '{"hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"make deploy"},"session_id":"s3ss10n-id","cwd":"'"$P"'/harbor"}' \
  | python3 "$B/../hooks/attention.py"); rc=$?
check "$out|$rc" "|0" "PermissionRequest: prints nothing (stdout would answer the dialog), exits 0"
echo 'not json' | python3 "$B/../hooks/attention.py"; check "$?" "0" "garbage on stdin: still exit 0"
L=$(cat "$ATTENTION_LOG_DIR"/*.jsonl)
check "$(echo "$L" | wc -l | tr -d ' ')" "1" "one line logged, none for the garbage"
check "$(echo "$L" | j 'd["event"], d["tool"], d["detail"], d["session"]')" "PermissionRequest Bash make deploy s3ss10n-" "the line carries the event, tool, command and session"
python3 -c "import sys; sys.path.insert(0, '$B/../hooks'); import attention as a; print(a.record('Relay', 'answered', detail='which branch?', session='runabcdef99', cwd='$P/bakery'))" > /dev/null
for e in '"Notification","notification_type":"idle_prompt","message":"Claude is waiting for your input"' \
         '"Notification","notification_type":"permission_prompt","message":"Claude needs your permission to use Bash"' \
         '"Notification","notification_type":"elicitation_dialog","message":"MCP server asks for a token"' \
         '"PermissionRequest","tool_name":"AskUserQuestion","tool_input":{}'; do
  echo "{\"hook_event_name\":$e,\"session_id\":\"s3ss10n-id\",\"cwd\":\"$P/harbor\"}" | python3 "$B/../hooks/attention.py"
done
python3 -c "import sys; sys.path.insert(0, '$B/../hooks'); import attention as a; a.record('Relay', 'escalated', detail='merge now?', session='runabcdef99', cwd='$P/bakery')"

# sessionpipe's outbox: a session the hook never logged (counted), the hook's own session (a copy, not counted)
python3 - "$T/outbox/s.jsonl" <<'EOF'
import json, sys, datetime as d
early = (d.datetime.now(d.timezone.utc) - d.timedelta(days=2)).strftime("%Y-%m-%dT%H:%M:%S.000Z")
late = (d.datetime.now(d.timezone.utc) + d.timedelta(minutes=5)).strftime("%Y-%m-%dT%H:%M:%S.000Z")
def ev(t, tool, sid="outboxsession"):
    return {"type": "attention.needed", "time": t, "harness": {"event": "PermissionRequest"},
            "session": {"cwd": "~/projects/household", "id": sid},
            "data": {"kind": "permission", "tool": tool, "message": tool + " x"}}
with open(sys.argv[1], "w") as f:
    # the late Bash is the hook's own session (s3ss10n-id): the log has it, the outbox row is a copy;
    # EnterWorktree is answered by hooks/worktree_allow.py, so no dialog was shown
    for e in (ev(early, "mcp__chrome__navigate"), ev(early, "AskUserQuestion"), ev(late, "Bash", "s3ss10n-id"),
              ev(early, "EnterWorktree")):
        f.write(json.dumps(e) + "\n")
EOF

# One session: a call with four questions (recommended, other option, free text, multiSelect with a
# comma in a label), a call with no pick offered, a declined call, an old call outside 7 days, and
# replies that hand work over or only mention doing so.
python3 - "$P/transcripts/harbor/s1.jsonl" "$NOW" "$OLD" "$P" <<'EOF'
import json, sys
path, now, old, projects = sys.argv[1:]
W = "SAM, THIS SESSION IS WAITING FOR YOU — "
F = "`" * 3
def opt(*ls): return [{"label": l, "description": ""} for l in ls]
def use(tid, qs, ts):
    return {"timestamp": ts, "cwd": projects + "/harbor/.claude/worktrees/x", "sessionId": "abcdef1234",
            "message": {"content": [{"type": "tool_use", "id": tid, "name": "AskUserQuestion", "input": {"questions": qs}}]}}
def res(tid, answers):
    return {"timestamp": now, "toolUseResult": {"answers": answers},
            "message": {"content": [{"type": "tool_result", "tool_use_id": tid, "content": "answered"}]}}
n = [0]
def say(text):
    n[0] += 1
    return {"type": "assistant", "uuid": "u%d" % n[0], "timestamp": now, "cwd": projects + "/harbor", "sessionId": "abcdef1234",
            "message": {"id": "m%d" % n[0], "content": [{"type": "text", "text": text}]}}
def stop(text):
    n[0] += 1
    return {"type": "user", "isMeta": True, "uuid": "h%d" % n[0], "timestamp": now, "cwd": projects + "/harbor",
            "sessionId": "abcdef1234", "message": {"role": "user", "content": "Stop hook feedback:\n" + text}}
q = [{"question": "Q-rec", "options": opt("A (Recommended)", "B")},
     {"question": "Q-other", "options": opt("A (Recommended)", "B")},
     {"question": "Q-free", "options": opt("A (Recommended)", "B")},
     {"question": "Q-multi", "multiSelect": True, "options": opt("x, y (Recommended)", "z (Recommended)", "w")}]
rows = [use("t1", q, now),
        res("t1", {"Q-rec": "A (Recommended)", "Q-other": "B", "Q-free": "Do it yourself, don't ask", "Q-multi": "x, y (Recommended), z (Recommended)"}),
        use("t2", [{"question": "Q-unranked", "options": opt("A", "B")}], now),
        res("t2", {"Q-unranked": "B"}),
        use("t3", [{"question": "Q-declined", "options": opt("A (Recommended)", "B")}], now),
        {"timestamp": now, "message": {"content": [{"type": "tool_result", "tool_use_id": "t3", "is_error": True, "content": "rejected"}]}},
        use("t4", [{"question": "Q-old", "options": opt("A (Recommended)")}], old),
        res("t4", {"Q-old": "A (Recommended)"}),
        say("## Do this now\n\n" + F + "bash\ngit push origin v1\n" + F + "\n\nThen I watch it.\n\n" + W + "push the tag."),
        say("**Do this now**\n\n" + F + "\nclaude auth login\n" + F + "\n\n" + W + "run it as the work account."),
        say("Done here.\n\n" + W + "accept the invite on GitHub, then say go."),
        say("Answers wanted.\n\n" + W + "D2 and D3 in the doc."),
        say("Put the command in a Do this now block next time.\n\nSAM, THIS SESSION IS DONE — CLOSE THIS TAB."),
        say("The work login is fine.\n\n" + W + "say go to land it."),
        say("**Do this now**\n\n" + F + "\n/Users/x/projects/overlay/bin/autofinish-run /Users/x/projects/r/.claude/worktrees/t\n" + F
            + "\n\n\u26a0 step 4 \u2014 one open item.\n\n" + W + "settle D1, then run the line."),
        say("Stopped.\n\n" + W + "open a fresh Terminal window on household and pick it up."),
        stop("Before stopping, fix these in your reply (x) and resend it: bare PR number: PR #2"),
        say("Stopped, again.\n\n" + W + "open a fresh Terminal window on household and pick it up."),
        stop("Before stopping, fix these in your reply (x). Your reply is already on screen, so do not resend it: send only the lines"),
        stop("Talk: start the listener first"),
        {"type": "user", "uuid": "lander", "timestamp": now, "cwd": projects + "/harbor", "sessionId": "unatt0001",
         "message": {"content": "<command-name>/finish</command-name>\n<command-args>claude/x --unattended</command-args>"}},
        dict(stop("Before stopping, fix these in your reply (x) and resend it: bare PR number"), sessionId="unatt0001"),
        dict(stop("Before stopping, fix these in your reply (x) and resend it: bare PR number"), sessionId="seed-run-0002"),
        {"type": "user", "isMeta": True, "uuid": "skill1", "timestamp": now, "cwd": projects + "/harbor", "sessionId": "abcdef1234",
         "message": {"content": "Base directory for this skill: /x — Stop hook feedback: quoted, not a block"}}]
with open(path, "w") as f:
    for r in rows:
        f.write(json.dumps(r) + "\n")
EOF
# a fork in a live login dir copies the same records: counted once
cp "$P/transcripts/harbor/s1.jsonl" "$T/live/-x/fork.jsonl"
# trust: two repos, one trusted
mkdir -p "$P/harbor" "$P/household"; git -C "$P/harbor" init -q; git -C "$P/household" init -q
echo '{"projects": {"'"$P"'": {"hasTrustDialogAccepted": true}, "'"$P"'/harbor": {"hasTrustDialogAccepted": true}}}' > "$HOME/.claude.json"

J=$("$B/interruptions" --days 7 --no-memo --json --list all)
k() { echo "$J" | python3 -c "import json,sys; d=json.load(sys.stdin); print(' '.join(r['kind'] for r in sorted(d['rows'], key=lambda r: r['question']) if r['channel']==sys.argv[2] and r['question'].startswith(sys.argv[1])))" "$1" "${2:-ask}"; }
n() { echo "$J" | j "d['channels']['$1']['n']"; }

echo "ask channel"
check "$(n ask)" "6" "six questions in the window; the fork's copies and the 2020 call are not counted"
check "$(k Q-rec)" "recommended" "the recommended label: predictable"
check "$(k Q-other)" "other-option" "another listed option"
check "$(k Q-free)" "free-text" "the owner's own words"
check "$(k Q-multi)" "recommended" "multiSelect: both recommended labels, one with a comma in it"
check "$(k Q-unranked)" "unranked" "no pick offered is counted apart"
check "$(k Q-declined)" "declined" "a rejected call has no answer"
check "$(k Q-old)" "" "outside --days 7"
check "$(echo "$J" | j 'd["channels"]["ask"]["predictable_pct"]')" "40" "predictable: 2 of the 5 that had a pick"
check "$(echo "$J" | j 'sorted({r["project"] for r in d["rows"] if r["channel"]=="ask"})')" "['harbor']" "project from the cwd, worktree path stripped"
check "$("$B/interruptions" --days 0 --no-memo --json | j 'd["channels"]["ask"]["n"]')" "7" "--days 0 reads all history"

echo "handoff channel"
check "$(n handoff)" "6" "six hand-overs; a D-item ask, a prose mention and a DONE line are not, nor the resend after a Stop block (its repeat row counts it)"
check "$(k 'SAM, THIS SESSION IS WAITING FOR YOU — push' handoff)" "paste" "a Do this now heading with a fenced command: paste"
check "$(k 'SAM, THIS SESSION IS WAITING FOR YOU — run it' handoff)" "login" "the block says auth login: login"
check "$(k 'SAM, THIS SESSION IS WAITING FOR YOU — accept' handoff)" "handback" "a WAITING line with no block: handback"
check "$(k 'SAM, THIS SESSION IS WAITING FOR YOU — say go' handoff)" "handback" "\"login\" the noun in the prose is not a login ask"
check "$(k 'SAM, THIS SESSION IS WAITING FOR YOU — settle' handoff)" "window" "a blocked /finish's lander line: a fresh window (2026-10-11)"
check "$(k 'SAM, THIS SESSION IS WAITING FOR YOU — open a fresh' handoff)" "window" "a WAITING line naming a fresh window: window"

echo "repeat channel"
check "$(echo "$J" | j 'sorted(d["channels"]["repeat"]["kinds"].items())')" "[('lines', 1), ('other', 1), ('unattended', 2), ('whole', 1)]" "one row per Stop hook block: resent whole, corrected lines only, another hook's, unattended (a lander's prompt, a dispatch run record); the fork's copies once; a skill body quoting the words is none"

if [ -z "$KEEL" ]; then echo "  skip: block_reason's real text is keel's paste-paths, not in this copy"; else
python3 - "$B/interruptions" > "$T/kinds" <<'EOF'
import sys, importlib.machinery, importlib.util
loader = importlib.machinery.SourceFileLoader("interruptions", sys.argv[1])
spec = importlib.util.spec_from_loader("interruptions", loader)
i = importlib.util.module_from_spec(spec); loader.exec_module(i)
cases = [(["a [x](docs/y.md) link fix"], {}), (["bare PR number: PR #2"], {}),
         (["/finish ends with one of its closing lines"], {}), (["relative path in a paste block: x"], {}),
         (["the WAITING line asks the owner to run `x` — put it in a **Do this now** block too"], {}),
         (["bare PR number: PR #2"], {"CLAUDE_UNATTENDED": "dispatch"})]
print(" ".join(i.repeat_kind(i.PP.block_reason("r", f, [], env)) for f, env in cases))
EOF
check "$(cat "$T/kinds")" "lines lines lines whole whole whole" "block_reason's real text read back: fixes in the body or the ending are lines; a paste or Do-this-now fix, or any unattended run, whole"
fi

echo "permission, notice, relay, trust"
check "$(n permission)" "2" "the hook's Bash, plus the outbox's navigate from before the hook; AskUserQuestion's dialog left out"
check "$(echo "$J" | j 'sorted(r["kind"] for r in d["rows"] if r["channel"]=="permission")')" "['Bash', 'mcp__chrome__navigate']" "the outbox's row of a session the hook logged is a copy, not counted twice; an auto-approved EnterWorktree is no dialog"
check "$(echo "$J" | j '[r["kind"] for r in d["rows"] if r["channel"]=="notice"]')" "['elicitation_dialog']" "notices: idle and the permission repeat are left out"
check "$(echo "$J" | j 'sorted(d["channels"]["relay"]["kinds"].items())')" "[('answered', 1), ('escalated', 1)]" "relays from record(), both kinds"
check "$(echo "$J" | j 'd["total"]')" "18" "the total leaves relays and unattended repeats out: 6 ask + 6 handoff + 3 repeat + 2 permission + 1 notice"
check "$(echo "$J" | j 'd["trust_waiting"]')" "{'.claude': ['~/projects/household']}" "trust: the repo with no entry waits on a dialog"
check "$("$B/interruptions" --days 7 --no-memo --list predictable | wc -l | tr -d ' ')" "2" "--list predictable prints the predictable rows only"

echo "memo channel"
if [ -z "$KEEL" ]; then echo "  skip: the memo channel reads keel's parser, not in this copy"; else
# a repo outside the bench's six folders still counts; transcripts/ is never read as a repo
R="$P/bakery"; mkdir -p "$R/docs"
g() { git -C "$R" -c user.name=t -c user.email=t@t "$@"; }
g init -q
D="$R/docs/x-2026-10-04.md"
cat > "$D" <<'EOF'
# Fixture

- **D1 — Pick one.**
  A — this
  B — that
  ➤ Recommended: B
  ➤ Answer:

- **D2 — Pick again.**
  A — this
  B — that
  ➤ Recommended: B
  ➤ Answer:
EOF
g add -A; g commit -qm doc
python3 - "$D" <<'EOF'
import sys
p = sys.argv[1]; s = open(p).read()
s = s.replace("Pick one.**\n  A — this\n  B — that\n  ➤ Recommended: B\n  ➤ Answer:\n", "Pick one.**\n  A — this\n  B — that\n  ➤ Recommended: B\n  ➤ Answer:\n  B\n")
s = s.replace("Pick again.**\n  A — this\n  B — that\n  ➤ Recommended: B\n  ➤ Answer:\n", "Pick again.**\n  A — this\n  B — that\n  ➤ Recommended: B\n  ➤ Answer:\n  A\n")
open(p, "w").write(s)
EOF
g commit -qam answers
check "$("$B/interruptions" --days 0 --json | j 'd["channels"]["memo"]["n"], d["channels"]["memo"]["kinds"].get("recommended"), d["channels"]["memo"]["kinds"].get("overruled")')" "2 1 1" "bakery's D1 took the pick, D2 overruled it"
fi

echo "the fence: a confidential scope's rows counted, never quoted (knowledge-layers S4)"
# a made-up registry: harbor and bakery make the confidential scope `node`, household the open `pub`
printf '{"repos": {"harbor": {}, "bakery": {}, "household": {}},\n "scopes": {"node": {"file": "n", "repos": ["harbor", "bakery"], "confidential": true},\n  "pub": {"file": "p", "repos": ["household"]}}}\n' > "$T/repos.json"
FJ=$(CLAUDE_REPOS_JSON="$T/repos.json" "$B/interruptions" --days 0 --json --list all)
f() { echo "$FJ" | j "$1"; }
check "$(f 'd["channels"]["ask"]["n"], d["channels"]["memo"]["n"], d["channels"]["relay"]["n"]')" "7 2 2" "every count stays: the seven questions of all history, both D-items, both relays"
check "$(f 'sorted({r["project"] for r in d["rows"] if r.get("fenced")})')" "['(confidential)']" "  each confidential row's project is (confidential)"
check "$(f 'sum(1 for r in d["rows"] if r.get("fenced") and (r["question"] or r["answer"] or r["note"] or r["recommended"] or r["session"]))')" "0" \
  "  and none keeps its question, pick, answer, note or file"
check "$(f 'sum(1 for r in d["rows"] if "_where" in r)')" "0" "  no row carries the paths it was judged by"
check "$(f 'sorted({r["project"] for r in d["rows"] if not r.get("fenced")})')" "['household']" "  the open scope's rows quoted as before"
check "$(f 'sorted(d["trust_waiting"][".claude"])')" "['(confidential)', '~/projects/household']" "  an untrusted confidential repo counted, not named"
out=$(CLAUDE_REPOS_JSON="$T/repos.json" "$B/interruptions" --days 0 --list all)
check "$(echo "$out" | grep -c 'Q-\|harbor\|bakery\|Pick ')" "0" "--list all: no confidential text"
check "$(echo "$out" | tail -1 | sed 's/^([0-9]* rows/(N rows/')" "(N rows of a confidential scope: counted, not listed — its own pass reads them)" "  one line counts them"
SJ=$(CLAUDE_REPOS_JSON="$T/repos.json" "$B/interruptions" --days 0 --json --list all --scope node)
check "$(echo "$SJ" | j 'd["scope"], d["channels"]["ask"]["n"], d["channels"]["memo"]["n"], d["channels"]["permission"]["n"], sorted({r["project"] for r in d["rows"]})')" \
  "node 7 2 1 ['bakery', 'harbor']" "--scope node: its own rows, quoted (all history: the 2020 call too), household's gone"
check "$(echo "$SJ" | j 'sum(1 for r in d["rows"] if r["question"] == "Q-rec")')" "1" "  the question text is there"
check "$(echo "$SJ" | j 'd["trust_waiting"]')" "{'.claude': ['~/projects/bakery']}" "  its untrusted repo named, the other scope's left out"
PJ2=$(CLAUDE_REPOS_JSON="$T/repos.json" "$B/interruptions" --days 0 --json --list all --scope pub)
check "$(echo "$PJ2" | j 'd["channels"]["ask"]["n"], d["channels"]["memo"]["n"], d["channels"]["permission"]["n"], d["trust_waiting"]')" \
  "0 0 1 {'.claude': ['~/projects/household']}" "--scope pub: the open scope's alone, the confidential one not even counted"
CLAUDE_REPOS_JSON="$T/repos.json" "$B/interruptions" --scope nope > /dev/null 2> "$T/scope.err"
check "$? $(cat "$T/scope.err")" "2 interruptions: no scope 'nope' in the registry" "an unknown scope: exit 2, one line"


echo "a multiSelect answer that comes back as a list"
mkdir -p "$T/listans/r"
printf '%s\n' '{"timestamp": "'"$NOW"'", "cwd": "'"$P"'/household", "sessionId": "list0001", "message": {"content": [{"type": "tool_use", "id": "tl", "name": "AskUserQuestion", "input": {"questions": [{"question": "Q-list", "multiSelect": true, "options": [{"label": "z (Recommended)"}, {"label": "w"}]}]}}]}}' \
  '{"timestamp": "'"$NOW"'", "toolUseResult": {"answers": {"Q-list": ["z (Recommended)"]}}, "message": {"content": [{"type": "tool_result", "tool_use_id": "tl", "content": "ok"}]}}' > "$T/listans/r/l.jsonl"
check "$(INTERRUPTIONS_SOURCES="$T/listans" "$B/interruptions" --days 7 --no-memo --json --list all 2>&1 | j '[(r["kind"], r["answer"]) for r in d["rows"] if r["question"] == "Q-list"]')" \
  "[('recommended', 'z (Recommended)')]" "joined and judged, never a crash (this Mac's week, 2026-10-22)"


echo "no peers: the regatta core alone (regatta-modules G13, G14)"
PR="$(cd "$B/.." && pwd)"
core=$(python3 - "$PR" <<'PYC'
import os, sys
lib = os.path.join(sys.argv[1], "lib")
if os.path.isfile(os.path.join(lib, "find_core.py")):
    sys.path.insert(0, lib); import find_core; sys.path.insert(0, find_core.hooks())
else:
    sys.path.insert(0, os.path.join(sys.argv[1], "hooks"))
import common; print(os.path.dirname(os.path.dirname(os.path.realpath(common.__file__))))
PYC
)
fc="$PR/lib/find_core.py"; [ -f "$fc" ] || fc="$core/../plumb/lib/find_core.py"
PL="$T/peerless"; PM="$PL/modules/plumb"
mkdir -p "$PL/.claude-plugin" "$PM/bin" "$PM/hooks" "$PM/lib" "$T/no-plugins"
echo '{"name":"peerless","owner":{"name":"t"},"plugins":[]}' > "$PL/.claude-plugin/marketplace.json"
cp -R "$core" "$PL/modules/regatta"; cp "$fc" "$PM/lib/"; cp "$PR/bin/interruptions" "$PM/bin/"
cp "$PR/hooks/attention.py" "$PM/hooks/"; cp -R "$PR/bench" "$PM/bench"
out=$(env REGATTA_HOME="$PL" REGATTA_LEGACY="$T/no-legacy" CLAUDE_CONFIG_DIR="$T/no-plugins" INTERRUPTIONS_LOGINS="" python3 -c "
from importlib.machinery import SourceFileLoader as L
i = L('interruptions', '$PM/bin/interruptions').load_module(); print(i.trust_waiting(), i.PP.REPEAT_WHOLE, i.KEEL.ask_parts is i._ask_parts)" 2> "$T/pl.err")
check "$out" "{} resend it:  True" "G13, G14: no trust-projects (lighthouse): no trust row; no keel: paste-paths' phrases as literals, ask_parts from the copy"
check "$(cat "$T/pl.err")" "interruptions: bin/keel unreadable (FileNotFoundError: keel not installed); its ask_parts taken from the copy here
interruptions: paste-paths unreadable (FileNotFoundError: keel not installed); its phrases taken as literals" "  …each said in one line"

[ "$fails" -eq 0 ] && echo "all ok" || { echo "$fails failed"; exit 1; }
