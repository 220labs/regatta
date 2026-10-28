#!/usr/bin/env bash
# crew-report's use of the core's attribution: a session, or every session under a folder glob,
# counted to another project (prompt time and model cost), read through common.attribution from the
# state dir's attribution.jsonl; the reader's own rules are the core's suite (tests/attribution.sh).
# Synthetic transcripts under a scratch HOME and config dir; every name made up (proj-a, proj-b,
# proj-c, sess-1 …).
# Week 2026-W10 (UTC), gap 20 min. Prompts:
#   sess-1  proj-a                                   10:00 10:05   (5 min)
#   sess-2  proj-a/.claude/worktrees/topic-1         11:00 11:10, then its sub/ folder 11:12   (12 min)
#   sess-3  proj-b                                   12:00 12:03   (3 min)
#   sess-4  proj-a/.claude/worktrees/topic-10        13:00         (one prompt: 0 min)
# usage-report is a stub: sess-1 $2.00, sess-2 $1.50 + a subagent's $0.50 (same sessionId), sess-3 $0.25.
#   bash modules/plumb/tests/crew-report-attribution.sh
set -u
D="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
export HOME="$T/home" REGATTA_CONFIG="$T/config" TZ=UTC ACCOUNTS_FILE="$T/accounts.json"
unset CLAUDE_CONFIG_DIR CREW_REPORT_CONFIG REGATTA_LEGACY REGATTA_HOME CLAUDE_CODE_SESSION_ID
export CREW_REPORT_NO_DRAIN=1 CREW_REPORT_KEEL=none CREW_REPORT_PUBLISH=none CREW_REPORT_USAGE_REPORT="$T/usage-report"
mkdir -p "$HOME/.claude/projects/-x" "$HOME/projects/proj-a/.git" "$HOME/projects/proj-b/.git" \
         "$HOME/projects/proj-c/.git" "$HOME/projects/not-a-repo" "$REGATTA_CONFIG"
printf '{"accounts": [{"label": "one", "provider": "claude", "home": "~/.claude", "primary": true}]}\n' > "$ACCOUNTS_FILE"
printf '{"cache": "", "transcripts": ""}\n' > "$T/cfg.json"
AF="$HOME/.local/state/regatta/attribution.jsonl"   # the core's default under the scratch HOME

python3 - "$HOME" <<'PY'
import json, sys
home = sys.argv[1]
P = home + "/projects/"
n = [0]
def ev(sid, ts, cwd):
    n[0] += 1
    return {"type": "user", "uuid": "u%03d" % n[0], "sessionId": sid, "timestamp": ts, "cwd": cwd,
            "entrypoint": "claude-vscode", "origin": {"kind": "human"}, "message": {"role": "user", "content": "go"}}
def write(name, rows):
    with open(home + "/.claude/projects/-x/" + name + ".jsonl", "w") as f:
        for r in rows:
            f.write(json.dumps(r) + "\n")
W1 = P + "proj-a/.claude/worktrees/topic-1"
write("sess-1", [ev("sess-1", "2026-03-02T10:00:00Z", P + "proj-a"), ev("sess-1", "2026-03-02T10:05:00Z", P + "proj-a")])
write("sess-2", [ev("sess-2", "2026-03-02T11:00:00Z", W1), ev("sess-2", "2026-03-02T11:10:00Z", W1),
                 ev("sess-2", "2026-03-02T11:12:00Z", W1 + "/sub")])
write("sess-3", [ev("sess-3", "2026-03-02T12:00:00Z", P + "proj-b"), ev("sess-3", "2026-03-02T12:03:00Z", P + "proj-b")])
write("sess-4", [ev("sess-4", "2026-03-02T13:00:00Z", P + "proj-a/.claude/worktrees/topic-10")])
PY

cat > "$T/usage-report" <<'STUB'
def data_dir():
    return "/nowhere"
def load_rows(c, a, b):
    return [{"session": "sess-1", "project": "proj-a", "cost": "2.00", "host": ""},
            {"session": "sess-2", "project": "proj-a", "cost": "1.50", "host": ""},
            {"session": "sess-2", "project": "proj-a", "cost": "0.50", "host": ""},
            {"session": "sess-3", "project": "proj-b", "cost": "0.25", "host": ""}] + (
           [{"session": "sess-5", "project": "proj-a", "cost": "1.00", "host": ""}] if __import__("os").path.exists(__import__("os").environ["CREW_EXTRA"]) else [])
STUB
export CREW_EXTRA="$T/extra"

rc=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; echo "$2" | sed 's/^/     /'; rc=1; }
has() { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1" "$2" ;; esac; }
lacks() { case "$2" in *"$3"*) bad "$1" "$2" ;; *) ok "$1" ;; esac; }
run() { CREW_REPORT_CONFIG="$T/cfg.json" python3 "$D/bin/crew-report" week --week 2026-W10 2>&1; }
rows() { mkdir -p "$(dirname "$AF")"; printf '%s\n' "$@" > "$AF"; }

# No file: the report is what it was, and so with attribution turned off.
rm -f "$AF"
base=$(run)
has "no file: proj-a is 6 prompts and 17 min" "$base" "| proj-a | 6 · 17 min |"
has "no file: proj-a's cost is sess-1 + sess-2" "$base" "| \$4.00 "
lacks "no file: no attributed line" "$base" "attributed:"
rows '{"ts": "2026-03-03T09:00:00Z", "project": "proj-b", "session": "sess-1"}'
mkdir -p "$REGATTA_CONFIG/regatta"; : > "$REGATTA_CONFIG/regatta/attribution"
off=$(run)
rm -f "$REGATTA_CONFIG/regatta/attribution"
[ "$base" = "$off" ] && ok "off: the same report with regatta/attribution empty, rows or not" || bad "off: the same report with regatta/attribution empty" "$base
--
$off"

# A session row moves its prompts and its cost, a subagent's row included.
rows '{"ts": "2026-03-03T09:00:00Z", "project": "proj-b", "session": "sess-1", "why": "test"}'
out=$(run)
has "session row: proj-a keeps 12 min of sess-2" "$out" "| proj-a | 4 · 12 min |"
has "session row: proj-b holds 10:00-10:05 and 12:00-12:03 (8 min)" "$out" "| proj-b | 4 · 8 min |"
has "session row: the cost moved with it (proj-b 2.25, proj-a 2.00)" "$out" "| \$2.25 "
has "session row: the attributed line" "$out" "attributed: 1 session, 0 path rules — 5 min, \$2.00"

rows '{"ts": "2026-03-03T09:00:00Z", "project": "proj-b", "session": "sess-2"}'
out=$(run)
has "session row: a subagent's cost follows its parent session" "$out" "attributed: 1 session, 0 path rules — 12 min, \$2.00"

# A path row matches a worktree cwd and a subfolder of it, not a sibling whose name starts the same.
rows '{"ts": "2026-03-03T09:00:00Z", "project": "proj-b", "path": "proj-a/.claude/worktrees/topic-1", "why": "test"}'
out=$(run)
has "path row: sess-2 moved, sess-1 and sess-4 stay (proj-a 3 prompts, 5 min)" "$out" "| proj-a | 3 · 5 min |"
has "path row: proj-b holds sess-2 (incl. its sub/ prompt) and sess-3" "$out" "| proj-b | 5 · 15 min |"
has "path row: the attributed line (cost through the session's folder)" "$out" "attributed: 0 sessions, 1 path rule — 12 min, \$2.00"
rows '{"ts": "2026-03-03T09:00:00Z", "project": "proj-b", "path": "proj-a/.claude/worktrees/topic-*"}'
out=$(run)
has "path row: a glob takes topic-1 and topic-10" "$out" "| proj-a | 2 · 5 min |"
rows '{"ts": "2026-03-03T09:00:00Z", "project": "proj-b", "path": "proj-a"}'
out=$(run)
has "path row: a repo's folder takes every session under it" "$out" "| proj-b | 8 · 20 min |"

# A session row beats a path row, whichever is newer.
rows '{"ts": "2026-03-04T09:00:00Z", "project": "proj-b", "path": "proj-a/.claude/worktrees/topic-1"}' \
     '{"ts": "2026-03-02T09:00:00Z", "project": "proj-c", "session": "sess-2"}'
out=$(run)
has "session beats path: sess-2 is proj-c's" "$out" "| proj-c | 3 · 12 min |"
has "session beats path: proj-b has only its own" "$out" "| proj-b | 2 · 3 min |"

# The newest ts wins among rows of one kind, whatever the file order.
rows '{"ts": "2026-03-04T09:00:00Z", "project": "proj-c", "session": "sess-1"}' \
     '{"ts": "2026-03-02T09:00:00Z", "project": "proj-b", "session": "sess-1"}'
out=$(run)
has "newest session row wins (file order does not)" "$out" "| proj-c | 2 · 5 min |"
lacks "newest session row wins: not the older target" "$out" "| proj-b | 4 "
rows '{"ts": "2026-03-04T09:00:00Z", "project": "proj-c", "path": "proj-a/.claude/worktrees/topic-1"}' \
     '{"ts": "2026-03-05T09:00:00Z", "project": "proj-b", "path": "proj-a/.claude/worktrees/topic-1/sub"}' \
     '{"ts": "2026-03-02T09:00:00Z", "project": "proj-b", "path": "proj-a/.claude/worktrees/topic-1"}'
out=$(run)
has "newest path row wins where two match (the sub/ prompt goes to proj-b)" "$out" "| proj-b | 3 · 3 min |"
has "newest path row wins: the rest of sess-2 goes to proj-c" "$out" "| proj-c | 2 · 10 min |"

# A malformed line is skipped with one warning each; the good rows still count; never fatal.
rows 'not json' \
     '{"ts": "2026-03-03T09:00:00Z", "project": "proj-b"}' \
     '{"ts": "2026-03-03T09:00:00Z", "project": "proj-b", "session": "sess-1", "path": "proj-a"}' \
     '[1, 2]' \
     '{"ts": "2026-03-03T09:00:00Z", "project": "proj-b", "session": "sess-1"}'
out=$(run)
has "malformed: the good row applies" "$out" "attributed: 1 session, 0 path rules"
n=$(printf '%s\n' "$out" | grep -c 'is not an attribution row: skipped')
[ "$n" = 4 ] && ok "malformed: one warning per bad line (4)" || bad "malformed: one warning per bad line (4)" "$n
$out"
has "malformed: the warning names the line" "$out" "attribution.jsonl line 3 is not an attribution row: skipped"
CREW_REPORT_CONFIG="$T/cfg.json" python3 "$D/bin/crew-report" week --week 2026-W10 >/dev/null 2>&1 && ok "malformed: exit 0" || bad "malformed: exit 0" ""

# The attributed: line's numbers: one session and one path rule together.
rows '{"ts": "2026-03-03T09:00:00Z", "project": "proj-b", "session": "sess-1"}' \
     '{"ts": "2026-03-03T09:00:00Z", "project": "proj-b", "path": "proj-a/.claude/worktrees/topic-1"}'
out=$(run)
has "attributed line: 1 session, 1 path rule, 17 min, 4.00 list" "$out" "attributed: 1 session, 1 path rule — 17 min, \$4.00"
has "attributed line: proj-a is left with sess-4's lone prompt" "$out" "| proj-a | 1 · 0 min |"
rows '{"ts": "2026-03-03T09:00:00Z", "project": "proj-a", "session": "sess-1"}'
out=$(run)
lacks "attributed line: a row that moves nothing is not counted" "$out" "attributed:"

# A swap counts both halves: 5 min left proj-a and 3 min left proj-b.
rows '{"ts": "2026-03-03T09:00:00Z", "project": "proj-b", "session": "sess-1"}' \
     '{"ts": "2026-03-03T09:00:00Z", "project": "proj-a", "session": "sess-3"}'
out=$(run)
has "attributed line: a swap of two sessions moves 8 min" "$out" "attributed: 2 sessions, 0 path rules — 8 min"

# A session that starts in the primary checkout and enters a worktree: its cost follows the path row
# on the worktree, as its worktree prompts do (sess-5, $1.00; only this case adds it).
python3 - "$HOME" <<'PY5'
import json, sys
home = sys.argv[1]; P = home + "/projects/"
def ev(u, ts, cwd):
    return {"type": "user", "uuid": u, "sessionId": "sess-5", "timestamp": ts, "cwd": cwd,
            "entrypoint": "claude-vscode", "origin": {"kind": "human"}, "message": {"role": "user", "content": "go"}}
W2 = P + "proj-a/.claude/worktrees/topic-2"
with open(home + "/.claude/projects/-x/sess-5.jsonl", "w") as f:
    for r in (ev("u501", "2026-03-02T14:00:00Z", P + "proj-a"), ev("u502", "2026-03-02T14:05:00Z", W2),
              ev("u503", "2026-03-02T14:09:00Z", W2)):
        f.write(json.dumps(r) + "\n")
PY5
touch "$CREW_EXTRA"
rows '{"ts": "2026-03-03T09:00:00Z", "project": "proj-c", "path": "proj-a/.claude/worktrees/topic-2"}'
out=$(run)
has "worktree entered later: its worktree prompts move" "$out" "| proj-c | 2 · 4 min |"
has "worktree entered later: its cost moves with them" "$out" "attributed: 0 sessions, 1 path rule — 9 min, \$1.00"
rm -f "$CREW_EXTRA" "$HOME/.claude/projects/-x/sess-5.jsonl"

# A row the core's verb wrote is read back by the report (the two halves of the mechanism meet).
rm -f "$AF"
python3 "$D/../regatta/libexec/attribution" add proj-b --session sess-1 >/dev/null 2>&1 || bad "verb: add exits 0" ""
out=$(run)
has "verb: the report reads the row regatta attribution add wrote" "$out" "attributed: 1 session, 0 path rules — 5 min, \$2.00"
rm -f "$AF"

exit $rc
