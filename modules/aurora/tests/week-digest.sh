#!/usr/bin/env bash
# week-digest's suite: the fence (knowledge-layers S4) over synthetic transcripts and docs under a
# scratch HOME and config dir, one made-up confidential scope (`node`: repo `sec`) and one open
# (`pub`: repo `open`). Without --scope a confidential session is counted, never quoted, and
# --promote-tags never reads its folder; --scope reads that scope alone; a torn registry quotes
# nothing. No network, no real repo touched.
#   bash modules/aurora/tests/week-digest.sh
set -u
D="$(cd "$(dirname "$0")/.." && pwd -P)"
W="$D/bin/week-digest"
T="$(mktemp -d)"; T="$(cd "$T" && pwd -P)"
trap 'rm -rf "$T"' EXIT
for v in $(env | sed -n 's/^\(REGATTA[A-Za-z0-9_]*\)=.*/\1/p; s/^\(CLAUDE[A-Za-z0-9_]*\)=.*/\1/p'); do unset "$v"; done
export HOME="$T/u" REGATTA_CONFIG="$T/config" ACCOUNTS_FILE="$T/no-accounts.json" CLAUDE_REPOS_JSON="$T/repos.json"
fails=0
check() {
  if [ "$1" = "$2" ]; then echo "  ok  $3"; else echo "  FAIL $3"; echo "       got:  $1"; echo "       want: $2"; fails=$((fails + 1)); fi
}
P="$T/u/projects"; L="$T/u/.claude/projects"
mkdir -p "$REGATTA_CONFIG" "$P/sec/docs" "$P/open/docs" "$P/transcripts/sec" "$P/transcripts/open"
printf '{"repos": {"sec": {}, "open": {}},\n "scopes": {"node": {"file": "n", "repos": ["sec"], "confidential": true},\n  "pub": {"file": "p", "repos": ["open"]}}}\n' > "$CLAUDE_REPOS_JSON"
slug() { printf '%s' "$1" | sed 's/[^A-Za-z0-9]/-/g'; }
NOW=$(python3 -c 'import datetime as d; print(d.datetime.now(d.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z"))')
session() {   # session <file> <id> <prompt>
  mkdir -p "$(dirname "$1")"
  printf '{"type": "user", "origin": {"kind": "human"}, "sessionId": "%s", "timestamp": "%s", "message": {"content": "%s"}}\n' "$2" "$NOW" "$3" > "$1"
}
session "$L/$(slug "$P/sec")/a.jsonl" sec-live-1 "PLUMWORD in the live folder"
session "$L/$(slug "$P/sec")--claude-worktrees-gone/b.jsonl" sec-tree-2 "PLUMWORD from a removed worktree"
session "$P/transcripts/sec/c.jsonl" sec-arch-3 "PLUMWORD in the archive"
session "$L/$(slug "$P/open")/d.jsonl" open-live-4 "open words here"
session "$P/transcripts/open/e.jsonl" open-arch-5 "open words archived"
printf 'x\n<!-- promote: coding --> PLUMWORD tag\n' > "$P/sec/docs/a.md"
printf '<!-- promote: coding --> open tag\n' > "$P/open/docs/b.md"
printf '<!-- promote: coding --> not markdown\n' > "$P/open/docs/c.txt"

echo "no --scope: a confidential scope's sessions counted, never quoted"
out=$("$W" --days 7); check $? 0 "exit 0"
check "$(echo "$out" | grep -c PLUMWORD)" 0 "  no line of the confidential scope's"
check "$(echo "$out" | grep -c 'open words')" 2 "  the open scope's prompts, live and archived"
check "$(echo "$out" | head -1 | grep -o '2 sessions, 2 prompts')" "2 sessions, 2 prompts" "  the heading counts the two it read"
check "$(echo "$out" | grep -o '^_3 sessions of a confidential scope: counted, never opened')" "_3 sessions of a confidential scope: counted, never opened" \
  "  one line says three were counted by name, not opened (live, a removed worktree's, the archive)"

echo "--scope"
out=$("$W" --days 7 --scope node)
check "$(echo "$out" | grep -c PLUMWORD) $(echo "$out" | grep -c 'open words')" "3 0" "the confidential scope's own pass reads it, and nothing else"
check "$(echo "$out" | head -1 | grep -o '3 sessions, 3 prompts.*scope node')" "3 sessions, 3 prompts ($(date +%F)) — scope node" "  the heading names the scope"
out=$("$W" --days 7 --scope pub)
check "$(echo "$out" | grep -c PLUMWORD) $(echo "$out" | grep -c 'open words') $(echo "$out" | grep -c 'confidential')" "0 2 0" \
  "an open scope: its own, the confidential one not even counted"
"$W" --scope nope > /dev/null 2> "$T/err"; check "$? $(cat "$T/err")" "2 week-digest: no scope 'nope' in the registry" "an unknown scope: exit 2, one line"

echo "--promote-tags"
out=$("$W" --promote-tags)
check "$out" "$P/open/docs/b.md:1:<!-- promote: coding --> open tag
(2 folder(s) of a confidential scope not read — its own pass reads them)" "grep -rn's lines, the confidential checkout and archive never read"
check "$("$W" --promote-tags --scope pub)" "$P/open/docs/b.md:1:<!-- promote: coding --> open tag" "  --scope pub: the confidential folders not even counted"
"$W" --promote-tags --scope > /dev/null 2> "$T/err"; check "$? $(cat "$T/err")" "2 week-digest: --scope needs a scope's name" "  --scope with no name: exit 2, one line"
check "$("$W" --promote-tags --scope node)" "$P/sec/docs/a.md:2:<!-- promote: coding --> PLUMWORD tag" "  --scope: that scope's tags alone"

echo "a torn registry: nothing quoted"
head -c 30 "$T/repos.json" > "$T/torn.json"
out=$(CLAUDE_REPOS_JSON="$T/torn.json" "$W" --days 7)
check "$(echo "$out" | grep -c 'PLUMWORD\|open words') $(echo "$out" | grep -o '^_5 sessions')" "0 _5 sessions" "every session counted by name, none opened (fails closed)"
CLAUDE_REPOS_JSON="$T/torn.json" "$W" --scope pub > /dev/null 2>&1; check $? 2 "  and a scope asked of it refused"
check "$(CLAUDE_REPOS_JSON="$T/none.json" "$W" --days 7 | grep -c 'PLUMWORD')" 3 "no registry at all: no scope is confidential, all quoted (as before S4)"

echo "evolve S1: the fence before open, the window by a prompt's own time, every login, forks, --json"
# a fenced transcript is never opened: a file that is not JSON at all, in a confidential folder, counts and breaks nothing
printf 'not json at all\n' > "$L/$(slug "$P/sec")/junk.jsonl"
out=$("$W" --days 7); check "$(echo "$out" | grep -o '^_4 sessions of a confidential')" "_4 sessions of a confidential" "a fenced file is counted by name"
# a fenced file made unreadable is still counted: nothing opens it
chmod 000 "$L/$(slug "$P/sec")/junk.jsonl"
out=$("$W" --days 7 2>&1); check "$(echo "$out" | grep -o '^_4 sessions of a confidential')" "_4 sessions of a confidential" "  and an unreadable one: it is never opened"
chmod 644 "$L/$(slug "$P/sec")/junk.jsonl"; rm -f "$L/$(slug "$P/sec")/junk.jsonl"
# the window is the prompt's own time: a fresh file (mtime now) holding an old prompt and a new one
OLD=$(python3 -c 'import datetime as d; print((d.datetime.now(d.timezone.utc)-d.timedelta(days=30)).strftime("%Y-%m-%dT%H:%M:%S.000Z"))')
mkdir -p "$L/$(slug "$P/open")"
printf '{"type": "user", "origin": {"kind": "human"}, "sessionId": "mix-6", "timestamp": "%s", "message": {"content": "OLDWORD from last month"}}\n{"type": "user", "origin": {"kind": "human"}, "sessionId": "mix-6", "timestamp": "%s", "message": {"content": "NEWWORD this week"}}\n' "$OLD" "$NOW" > "$L/$(slug "$P/open")/f.jsonl"
out=$("$W" --days 7); check "$(echo "$out" | grep -c OLDWORD) $(echo "$out" | grep -c NEWWORD)" "0 1" "an old prompt in a fresh file is outside the window"
# another login dir's transcripts are read
OTHER="$T/u/.claude-x"; mkdir -p "$OTHER/projects"
printf '{"accounts": [{"label": "x", "home": "%s"}]}\n' "$OTHER" > "$T/accounts.json"
session "$OTHER/projects/$(slug "$P/open")/g.jsonl" other-login-7 "OTHERLOGIN prompt"
check "$(ACCOUNTS_FILE="$T/accounts.json" "$W" --days 7 | grep -c OTHERLOGIN) $("$W" --days 7 | grep -c OTHERLOGIN)" "1 0" "a second login dir is read once the registry lists it"
# a fork that copied a prompt without a forked-from record is not counted twice
session "$L/$(slug "$P/open")/h.jsonl" fork-8 "open words here"
check "$("$W" --days 7 | grep -c 'open words here')" 1 "a prompt another session holds, same time and words, counts once"
echo "--json"
out=$("$W" --days 7 --json); check $? 0 "exit 0"
check "$(echo "$out" | python3 -c '
import json, sys
d = json.load(sys.stdin)
p = [x for s in d["sessions"] for x in s["prompts"]]
print(len(d["sessions"]), len(p), d["fenced"]["sessions"], any("PLUMWORD" in x["text"] for x in p), sorted(p[0]))')" \
  "3 3 3 False ['marked', 'text', 'ts']" "sessions, prompts, fenced counted; no fenced word; each prompt ts, text, marked"
long=$(python3 -c 'print("LONG " * 200)')
session "$L/$(slug "$P/open")/i.jsonl" long-9 "$long"
check "$("$W" --days 7 --json | python3 -c '
import json, sys
d = json.load(sys.stdin)
print(max(len(x["text"]) for s in d["sessions"] for x in s["prompts"]))')" 999 "the text is whole, not cut to --max-chars"
check "$("$W" --days 7 | grep -c '\[…\]')" 1 "  and the text interface still cuts"
check "$("$W" --days 7 --json --scope node | python3 -c '
import json, sys
d = json.load(sys.stdin); print(d["scope"], len(d["sessions"]), d["fenced"]["sessions"])')" "node 3 0" "--scope reads its own confidential sessions"

echo "evolve S11: a session's archive and live copies merged by event uuid, the newest kept"
# the archive copy is older and holds u1 (old words) and u2; the live copy holds u1 (edited) and u3 and not u2
ev() {   # ev <id> <uuid> <timestamp> <words>
  printf '{"type": "user", "origin": {"kind": "human"}, "sessionId": "%s", "uuid": "%s", "timestamp": "%s", "message": {"content": "%s"}}\n' "$1" "$2" "$3" "$4"
}
T1=$(python3 -c 'import datetime as d; print((d.datetime.now(d.timezone.utc)-d.timedelta(hours=3)).strftime("%Y-%m-%dT%H:%M:%S.000Z"))')
T2=$(python3 -c 'import datetime as d; print((d.datetime.now(d.timezone.utc)-d.timedelta(hours=2)).strftime("%Y-%m-%dT%H:%M:%S.000Z"))')
T3=$(python3 -c 'import datetime as d; print((d.datetime.now(d.timezone.utc)-d.timedelta(hours=1)).strftime("%Y-%m-%dT%H:%M:%S.000Z"))')
mkdir -p "$P/transcripts/open" "$L/$(slug "$P/open")"
{ ev merge-10 u1 "$T1" "MERGEOLD first words"; ev merge-10 u2 "$T2" "MERGEARCH only the archive has this"; } > "$P/transcripts/open/m.jsonl"
{ ev merge-10 u1 "$T1" "MERGENEW first words, the live copy"; ev merge-10 u3 "$T3" "MERGELIVE only the live copy has this"; } > "$L/$(slug "$P/open")/m.jsonl"
ago() { python3 -c 'import os, sys, time; t = time.time() - float(sys.argv[2]) * 3600; os.utime(sys.argv[1], (t, t))' "$1" "$2"; }   # portable: BSD touch has no -d "2 hours ago"
ago "$P/transcripts/open/m.jsonl" 2
out=$("$W" --days 7 --json)
check "$(echo "$out" | python3 -c '
import json, sys
d = json.load(sys.stdin)
s = [x for x in d["sessions"] if x["session"] == "merge-10"]
print(len(s), [p["text"].split()[0] for p in s[0]["prompts"]], s[0]["source"])')" \
  "1 ['MERGENEW', 'MERGEARCH', 'MERGELIVE'] live" "one session, three events (the uuid u1 once, from the newer file), oldest first"
out=$("$W" --days 7)
check "$(echo "$out" | grep -c MERGE) $(echo "$out" | grep -c MERGEOLD)" "3 0" "  the text form counts them the same"
# the other way round: the archive copy is the newer file, and wins u1
ago "$P/transcripts/open/m.jsonl" 1; ago "$L/$(slug "$P/open")/m.jsonl" 2
check "$("$W" --days 7 | grep -c MERGEOLD) $("$W" --days 7 | grep -c MERGENEW)" "1 0" "the newest file wins, whichever folder it is in"
# a line with no uuid is keyed by its time and words: two copies of it count once
{ printf '{"type": "user", "origin": {"kind": "human"}, "sessionId": "nouuid-11", "timestamp": "%s", "message": {"content": "NOUUID words"}}\n' "$T1"; } > "$P/transcripts/open/n.jsonl"
cp "$P/transcripts/open/n.jsonl" "$L/$(slug "$P/open")/n.jsonl"
check "$("$W" --days 7 | grep -c NOUUID)" 1 "a line with no uuid in both copies counts once"
rm -f "$P/transcripts/open/m.jsonl" "$L/$(slug "$P/open")/m.jsonl" "$P/transcripts/open/n.jsonl" "$L/$(slug "$P/open")/n.jsonl"

echo "evolve-readers: a launcher's prompt is not the owner's (the core's transcript.machine_start)"
M="$T/u/.claude-m/projects/$(slug "$P/open")"; mkdir -p "$M"
printf '{"accounts": [{"label": "m", "home": "%s"}]}\n' "$T/u/.claude-m" > "$T/accounts-m.json"
mline() {   # mline <session> <text as a JSON string>
  printf '{"type": "user", "origin": {"kind": "human"}, "sessionId": "%s", "timestamp": "%s", "message": {"content": %s}}\n' "$1" "$NOW" "$2"
}
mline disp-1 '"You are an unattended session started by dispatch on host-a at 2026-11-03 21:59 UTC; nobody is watching. MACHWORD"' > "$M/m1.jsonl"
{ mline disp-2 '"You are an unattended session started by dispatch on host-a; MACHWORD"'; mline disp-2 '"OWNERWORD typed over Remote Control"'; } > "$M/m2.jsonl"
mline land-3 '"<command-message>finish is running…</command-message>\n<command-name>/finish</command-name>\n<command-args>claude/h/2026-11-01-x --unattended --merge</command-args>"' > "$M/m3.jsonl"
mline seed-4 "\"/pickup 'claude/h/2026-10-31-seed' --fresh\"" > "$M/m4.jsonl"
{ mline own-5 '"You are a great help, OWNERWORD: add a rule for this"'; mline own-5 '"<command-message>finish</command-message>\n<command-name>/finish</command-name>"'; } > "$M/m5.jsonl"
cp "$M/m1.jsonl" "$P/transcripts/open/m1-copy.jsonl"   # the archive's copy of a launcher's session: one session, counted once
out=$(ACCOUNTS_FILE="$T/accounts-m.json" "$W" --days 7)
check "$(echo "$out" | grep -c MACHWORD) $(echo "$out" | grep -c OWNERWORD) $(echo "$out" | grep -c 'claude/h/2026-1')" "0 2 0" \
  "a dispatch brief, autofinish-run's launch and a seed's pickup tab are left out; the owner's prompts stay"
check "$(echo "$out" | grep -c '^- /finish$')" 1 "  a /finish the owner typed is the owner's"
check "$(echo "$out" | grep -o '^_4 prompts a launcher typed, in 4 sessions (autofinish 1, dispatch 2, pickup 1)')" \
  "_4 prompts a launcher typed, in 4 sessions (autofinish 1, dispatch 2, pickup 1)" "  one line counts them by launcher, the archive's copy once"
check "$(ACCOUNTS_FILE="$T/accounts-m.json" "$W" --days 7 --json | python3 -c '
import json, sys
d = json.load(sys.stdin)
p = [x["text"] for s in d["sessions"] for x in s["prompts"]]
print(d["machine"], sum("MACHWORD" in t for t in p), sum("OWNERWORD" in t for t in p), sorted(s["session"] for s in d["sessions"] if s["session"][:4] in ("disp", "land", "seed", "own-")))')" \
  "{'prompts': 4, 'sessions': 4, 'by': {'autofinish': 1, 'dispatch': 2, 'pickup': 1}} 0 2 ['disp-2', 'own-5']" \
  "--json: the machine counts; a launcher's session with an owner's prompt keeps that prompt alone"
check "$("$W" --days 7 --json | python3 -c 'import json, sys; print(json.load(sys.stdin)["machine"])')" \
  "{'prompts': 1, 'sessions': 1, 'by': {'dispatch': 1}}" "  the archive's copy alone, without the login that ran it: the same session"
check "$("$W" --days 7 --json --scope node | python3 -c 'import json, sys; print(json.load(sys.stdin)["machine"])')" \
  "{'prompts': 0, 'sessions': 0, 'by': {}}" "  none read: zero, never absent"
# a session relaunched after it was archived: the archive holds one launch, the live copy that and a second
LATER=$(python3 -c 'import datetime as d; print((d.datetime.now(d.timezone.utc)+d.timedelta(minutes=5)).strftime("%Y-%m-%dT%H:%M:%S.000Z"))')
mline land-7 '"/finish claude/h/2026-11-01-y --unattended"' > "$P/transcripts/open/m7.jsonl"
{ mline land-7 '"/finish claude/h/2026-11-01-y --unattended"'
  printf '{"type": "user", "origin": {"kind": "human"}, "sessionId": "land-7", "timestamp": "%s", "message": {"content": "/finish claude/h/2026-11-01-y --unattended --merge"}}\n' "$LATER"; } > "$M/m7.jsonl"
cp "$M/m1.jsonl" "$M/m8.jsonl"; sed -i.bak 's/disp-1/fork-8/' "$M/m8.jsonl"; rm -f "$M/m8.jsonl.bak"   # a fork's copy of a brief, another id
check "$(ACCOUNTS_FILE="$T/accounts-m.json" "$W" --days 7 --json | python3 -c 'import json, sys; print(json.load(sys.stdin)["machine"])')" \
  "{'prompts': 6, 'sessions': 5, 'by': {'autofinish': 3, 'dispatch': 2, 'pickup': 1}}" \
  "  the archive's older copy and the live one merge (both launches counted), and a fork's copy of a brief counts once"
# a repo the archive names by its folder (`_x`) and the live slug by its tail (`-x`): one session, one brief
mkdir -p "$P/_x" "$P/transcripts/_x" "$T/u/.claude-m/projects/$(slug "$P/_x")"
mline disp-9 '"You are an unattended session started by dispatch on host-a; in _x"' > "$P/transcripts/_x/m9.jsonl"
cp "$P/transcripts/_x/m9.jsonl" "$T/u/.claude-m/projects/$(slug "$P/_x")/m9.jsonl"
check "$(ACCOUNTS_FILE="$T/accounts-m.json" "$W" --days 7 --json | python3 -c 'import json, sys; print(json.load(sys.stdin)["machine"])')" \
  "{'prompts': 7, 'sessions': 6, 'by': {'autofinish': 3, 'dispatch': 3, 'pickup': 1}}" \
  "  a repo whose archive name differs from its live slug: its brief counts once"

# weekly-run's and sextant-run's `claude -p "/aurora <section>"`, raw as Claude Code records it: the launcher's, one rule with asks
mline wk-10 '"<command-message>aurora</command-message>\n<command-name>/aurora</command-name>\n<command-args>dream</command-args>"' > "$M/m10.jsonl"
mline wk-11 '"/sextant"' > "$M/m11.jsonl"
check "$(ACCOUNTS_FILE="$T/accounts-m.json" "$W" --days 7 --json | python3 -c '
import json, sys
d = json.load(sys.stdin)
print(d["machine"]["by"].get("weekly"), [s["session"] for s in d["sessions"] if s["session"].startswith("wk-")])')" "2 []" \
  "  weekly-run's /aurora and sextant-run's /sextant are a launcher's, as asks' sieve reads them"

echo "an older core (no transcript.machine_start): the read refuses in one line, --promote-tags still runs"
mkdir -p "$T/old/modules"; cp -R "$D/../regatta" "$T/old/modules/regatta"; cp -R "$D" "$T/old/modules/aurora"
printf 'TAIL_BYTES = 2_000_000\n' > "$T/old/modules/regatta/hooks/transcript.py"
out=$("$T/old/modules/aurora/bin/week-digest" --days 7 2>&1); check "$? $out" \
  "2 week-digest: the regatta core predates transcript.machine_start — update the regatta plugin" "  the week's read: exit 2, the one line"
"$T/old/modules/aurora/bin/week-digest" --promote-tags > /dev/null 2>&1; check $? 0 "  --promote-tags: exit 0"

[ "$fails" -eq 0 ] && echo "week-digest: all ok" || { echo "week-digest: $fails failed"; exit 1; }
