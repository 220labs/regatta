#!/usr/bin/env bash
# scope-pass's suite, and weekly-run's --scope (knowledge-layers S5): one scope's pass under a scratch
# HOME, config dir, registry and vault, every name made up. `node` is confidential (anchor
# node-knowledge, repo `sec`, its word list naming PLUMWORD), `pub` open (anchor pub-knowledge, repo
# `open`), `bare` an anchor with no `records` (none needed: a pull request lands the dream), `np` one
# whose in_place lacks dreams/, `ghost` an anchor not cloned. where says what
# the pass reads and when it may not run; check holds a confidential scope's repos, paths and words;
# record (Evolve S2) puts the dream on the anchor's records branch, pushed with a ready pull request
# (SCOPE_PASS_PR stands in for GitHub), and the draft — its heading made
# export-safe, scanned, judged, its SHA-256 the receipt — as the vault's inbox file, or holds it back
# inside the anchor; proof
# says which; weekly-run --scope runs it with a stand-in session. No network, no `claude`, no real
# repo touched (knowledge-commit and account are stand-ins).
#   bash modules/aurora/tests/scope-pass.sh
set -u
D="$(cd "$(dirname "$0")/.." && pwd -P)"
S="$D/bin/scope-pass"; W="$D/bin/weekly-run"
T="$(mktemp -d)"; T="$(cd "$T" && pwd -P)"
trap '[ -n "${KEEP:-}" ] || rm -rf "$T"' EXIT; [ -n "${KEEP:-}" ] && echo "scratch $T"
for v in $(env | sed -n 's/^\(REGATTA[A-Za-z0-9_]*\)=.*/\1/p; s/^\(CLAUDE[A-Za-z0-9_]*\)=.*/\1/p; s/^\(ATLAS[A-Za-z0-9_]*\)=.*/\1/p; s/^\(WEEKLY[A-Za-z0-9_]*\)=.*/\1/p; s/^\(GATE_[A-Za-z0-9_]*\)=.*/\1/p'); do unset "$v"; done
export HOME="$T/u" REGATTA_CONFIG="$T/config" ACCOUNTS_FILE="$T/no-accounts.json" CLAUDE_REPOS_JSON="$T/repos.json" \
       WEEKLY_LOG_DIR="$T/logs" SCOPE_PASS_COMMIT="$T/kc" SCOPE_PASS_PR="$T/pr" \
       GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
unset AURORA_SECTIONS AURORA_TODAY AURORA_HOUR
fails=0
check() {
  if [ "$1" = "$2" ]; then echo "  ok  $3"; else echo "  FAIL $3"; echo "       got:  $1"; echo "       want: $2"; fails=$((fails + 1)); fi
}
P="$T/u/projects"; V="$T/vault"; day=$(date +%F)
mkdir -p "$REGATTA_CONFIG/atlas" "$REGATTA_CONFIG/aurora" "$P/sec/docs" "$P/open" "$T/u/.claude/projects"
# the weekly jobs run on this host (weekly-run's host rule: aurora/host; no scope here names a yard)
python3 -c "import sys; sys.path.insert(0, sys.argv[1]); import common; print(common.host_name())" "$D/../regatta/hooks" > "$REGATTA_CONFIG/aurora/host"
printf 'vlt\n%s\n' "$V" > "$REGATTA_CONFIG/atlas/vault"
newrepo() {  # newrepo <dir> <in_place json or ""> [records json] — a git repo on main, its workflow committed
  mkdir -p "$1"; git -C "$1" init -q -b main
  [ -n "$2" ] && { mkdir -p "$1/.claude"; printf '{"checkpoint": true, "main": "main", "in_place": %s, "records": %s}\n' "$2" "${3:-[]}" > "$1/.claude/workflow.json"; }
  git -C "$1" add -A; git -C "$1" commit -q --allow-empty -m init
}
newrepo "$V" '["inbox/", "dreams/", "log.md"]'
newrepo "$P/node-knowledge" '["memory/", "dreams/"]' '["dreams/"]'
newrepo "$P/pub-knowledge" ""
newrepo "$P/bare-anchor" '["memory/", "dreams/"]'
newrepo "$P/nw-knowledge" '["dreams/"]' '["dreams/"]'
newrepo "$P/np-knowledge" '["memory/"]' '["dreams/"]'
host=$(python3 -c "import sys; sys.path.insert(0, sys.argv[1]); import common; print(common.host_name())" "$D/../regatta/hooks")
rb="claude/$host/$day-scope-pass"; mark="confidential:$(printf node | shasum -a 256 | cut -c1-8)"
unrecord() {  # unrecord <anchor> — today's records branch gone, here and on its origin (a scratch one)
  git -C "$1" update-ref -d "refs/heads/$rb"
  [ "$1" = "$P/node-knowledge" ] && git -C "$T/node-origin.git" update-ref -d "refs/heads/$rb"
  git -C "$1" update-ref -d "refs/remotes/origin/$rb" 2>/dev/null; true
}
mkdir -p "$P/node-knowledge/memory/sec" "$P/node-knowledge/dreams" "$P/pub-knowledge/dreams" "$V/memory/open"
printf '# the node'"'"'s own names; `node` too, which the scope'"'"'s own name overrides\nPLUMWORD\nnode\nPlum Orchard\nre:TKT-[0-9]+  # every ticket id\n\n' > "$P/node-knowledge/.claude/words.txt"
git -C "$P/node-knowledge" add -A; git -C "$P/node-knowledge" commit -qm words
cat > "$CLAUDE_REPOS_JSON" <<'EOF'
{"repos": {"node-knowledge": {}, "sec": {}, "pub-knowledge": {}, "open": {}, "bare-anchor": {}, "ghost-knowledge": {}, "nw-knowledge": {}, "np-knowledge": {}},
 "scopes": {"node": {"file": "n", "repos": ["node-knowledge", "sec"], "confidential": true},
            "pub": {"file": "p", "repos": ["pub-knowledge", "open"]},
            "bare": {"file": "b", "repos": ["bare-anchor"]},
            "ghost": {"file": "g", "repos": ["ghost-knowledge"]},
            "nw": {"file": "w", "repos": ["nw-knowledge"], "confidential": true},
            "np": {"file": "q", "repos": ["np-knowledge"]},
            "globby": {"file": "x", "repos": ["sec*"], "confidential": true},
            "seat": {"file": "s", "repos": ["node-knowledge"], "confidential": true, "login": "seat-login"}}}
EOF
# knowledge-commit's stand-in: `<name> -m <msg> <paths…>` from the vault, the straight form without the push
cat > "$T/kc" <<'EOF'
#!/bin/sh
echo "$@" >> "$(dirname "$0")/kc.log"
shift; m="$2"; shift 2
git add -- "$@" && git commit -qm "$m" -- "$@"
EOF
chmod +x "$T/kc"
# GitHub's stand-in for the records branch's pull request: `open|find <anchor> <branch> <main>`; `open`
# readies it, `find` answers what $T/pr.state says (ready unless the case writes another word)
cat > "$T/pr" <<'EOF'
#!/bin/sh
echo "$*" >> "$(dirname "$0")/pr.log"
[ $# = 4 ] || { echo "pr stand-in: want <verb> <anchor> <branch> <main>, got $*" >&2; exit 2; }
case "$1" in
  open) echo "ready https://example.invalid/pr/1" ;;
  find) st=$(cat "$(dirname "$0")/pr.state" 2>/dev/null || echo ready); echo "$st https://example.invalid/pr/1" ;;
  *) echo "pr stand-in: unknown verb $1" >&2; exit 2 ;;
esac
EOF
chmod +x "$T/pr"
wh() { "$S" where "$1" 2>&1 | sed -n "s/^$2 //p"; }

echo "where"
check "$(wh node ready) $(wh node confidential) $(wh node anchor)" "yes yes $P/node-knowledge" "a confidential scope with its anchor here: ready, from the anchor"
check "$(wh node inbox) $(wh node dream)" "$V/inbox/upstream/node.md $P/node-knowledge/dreams/$day.md" "  the inbox file in the vault, the dream in the anchor"
check "$(wh node draft)" "$P/node-knowledge/dreams/$day-upstream.md" "  the draft beside the dream, never in the vault (its SessionEnd hook pushes in_place dirt)"
check "$(wh node memory) $(wh node words) $(wh node members)" "$P/node-knowledge/memory $P/node-knowledge/.claude/words.txt node-knowledge sec" \
  "  its memory in the node, its word list, its members"
check "$(wh pub confidential) $(wh pub memory) $(wh pub words) $(wh pub login)" "no $V/memory/open none none" "an open scope: its members' memory in the vault"
check "$(wh pub ready)" "yes" "  no workflow.json in the anchor: nothing denies the record"
"$S" where bare >/dev/null 2>&1; check "$? $(wh bare ready)" "0 yes" "an anchor with no records list: ready (a pull request lands the dream, not autofinish)"
"$S" where np >/dev/null 2>&1; check "$? $(wh np ready | grep -c 'dreams/ is not in np-knowledge.s in_place')" "1 1" "an anchor whose in_place lacks dreams/: not ready (the session's draft would be denied in the checkout)"
check "$(wh np ready | grep -c 'add "dreams/" to its "in_place" list on a claude/\* branch')" 1 "  naming the exact edit, not only a command that reports ok on an existing anchor"
check "$(wh node records-branch)" "$rb" "  the records branch: claude/<host>/<day>-scope-pass, no term of the scope"
check "$(wh ghost ready | grep -c 'not cloned here')" 1 "an anchor not cloned here: not ready"
"$S" where nw >/dev/null 2>&1; check "$? $(wh nw ready | grep -c 'no .claude/words.txt')" "1 1" "a confidential scope with no word list: not ready"
"$S" where globby > "$T/out" 2>&1; check "$? $(grep -c 'has no anchor' "$T/out") $(grep -c Traceback "$T/out")" "1 1 0" "  a glob first: no anchor, one line, no traceback"
"$S" where nope > /dev/null 2> "$T/err"; check "$? $(grep -c "no scope 'nope'" "$T/err")" "2 1" "an unknown scope: exit 2"

echo "check — a confidential scope's inbox file"
f="$T/f.md"
ck() { printf '%s\n' "$1" > "$f"; "$S" check node "$f" > "$T/ck.out" 2>&1; echo "$? $(sed -n 's/^.*: names \([a-z]*\) .*$/\1/p' "$T/ck.out" | sort -u | tr '\n' ' ')"; }
check "$(ck 'U1. A hook beats a third line of prose — rules/engineering.md')" "0 " "a generalised line: clean"
check "$(ck 'Learned in the node scope, three sessions')" "0 " "  the scope's name alone is allowed (the file carries it), even where its word list holds it"
check "$(ck 'Seen in sec twice')" "1 repo " "a member repo by name: held"
check "$(ck 'see node-knowledge/docs/x.md')" "1 repo " "  the anchor by name"
check "$(ck 'insecure secrets')" "0 " "  a repo name inside a longer word is not a hit (word edges)"
check "$(ck "read $P/sec/docs/a.md")" "1 path repo " "a path of the scope's: held"
t='~'; check "$(ck "read $t/projects/sec/docs/a.md")" "1 path repo " "  its ~ form"
check "$(ck "in $T/u/.claude/projects/$(printf %s "$P/sec" | sed 's/[^A-Za-z0-9]/-/g')--claude-worktrees-gone/a.jsonl")" "1 path repo " \
  "  a login's project folder of a removed worktree (its slug names the repo too)"
check "$(ck 'the plumword client')" "1 word " "a word of the node's list, case-blind: held"
check "$(ck 'U1. x')$(printf 'U2. PLUMWORD\nU3. sec\n' >> "$f"; "$S" check node "$f" | tail -1 | cut -c1-9)" "0 2 line(s)" "  every hit named, one summary line"
check "$(ck "$(printf 'U1. the Plum\n   Orchard client')")" "1 word " "a two-word name split by a hard wrap: held"
check "$(grep -c "f.md:1: names word Plum Orchard" "$T/ck.out")" 1 "  named by the line it starts on"
check "$(ck 'the plum  orchard client')" "1 word " "  any run of whitespace between its words"
check "$(ck 'a plum, orchard')" "0 " "  never across a comma"
check "$(ck "$(printf '> the Plum\n> Orchard client')")" "1 word " "  nor past a blockquote's wrap"
check "$(ck "$(printf '/* the Plum\n * Orchard client */')")" "1 word " "  nor past a block comment's wrap"
check "$(ck "$(printf -- '- the Plum\n- Orchard client')")" "1 word " "  nor past a bullet's or a -- comment's wrap"
check "$(ck "$(printf 'ends on Plum\n\nOrchard Road opens')")" "0 " "  never across a blank line: no name spans paragraphs"
printf 'a Plum\n%s\n' "$(printf '#%.0s' $(seq 1 60))" > "$f"
s0=$(date +%s); "$S" check node "$f" > /dev/null 2>&1; rc=$?; s1=$(date +%s)
check "$rc $([ $((s1 - s0)) -lt 10 ] && echo fast)" "0 fast" "  a line of 60 #s after half a name: no exponential backtracking"
check "$(ck 'see tkt-4411 for it')" "1 pattern " "a re: line of the word list holds a family of ids, case-blind"
check "$(ck 'TKT- alone, XTKT-12 inside a word')" "0 " "  on word edges, never an empty id"
printf 'see tkt-4411 for it\n' > "$f"; "$S" check node "$f" > "$T/o" 2> "$T/e"; "$S" check node "$f" --json > "$T/j" 2> "$T/je"
check "$(cat "$T/o" "$T/e" "$T/j" "$T/je" | grep -c '\[0-9\]') $(grep -c 'names pattern words.txt line 5$' "$T/o") $(grep -c 'names pattern words.txt line 5$' "$T/je")" "0 1 1" \
  "  a hit names the word list's line, never the pattern, in stdout, stderr or --json's stderr"
cp "$P/node-knowledge/.claude/words.txt" "$T/words.keep0"
printf 're:TKT-\\d+\nre:tkt-\\D+\n' >> "$P/node-knowledge/.claude/words.txt"
check "$(ck 'see tkt-ab here')" "1 pattern " "  two patterns alike but for letter case are both kept (\\d and \\D differ only so)"
cp "$T/words.keep0" "$P/node-knowledge/.claude/words.txt"
cp "$P/node-knowledge/.claude/words.txt" "$T/words.keep"
printf 're:^ZQ-[0-9]+$\nre:no[a-z]e\nRE:QQ-[0-9]+\n' >> "$P/node-knowledge/.claude/words.txt"
check "$(ck "$(printf 'intro\nZQ-12')")" "1 pattern " "  a ^ in a pattern anchors each line, not the file"
check "$(ck "$(printf 'intro\r\nZQ-12\r\nmore')")" "1 pattern " "  and each CRLF line: \$ before a CR"
check "$(ck 'see QQ-7')" "1 pattern " "  an RE: prefix is the pattern form too"
check "$(ck 'Learned in the node scope')" "0 " "  a pattern that names the scope itself: exempt in the draft, as a literal word is"
cp "$T/words.keep" "$P/node-knowledge/.claude/words.txt"
for bad in 're:TKT-[0-9' 're:x*' 're:(?P=Brightwater)' 're:(?i)tkt-1' 're:Brightwater(?i)' 're:(?u)tkt-1' 're:Brightwater-[0-9]{4294967296}' 're:[a-z]' 're:\b' \
           're:(?-i:tkt)-[0-9]+' 're:Brightwater|x(?s:.)y' 're:[2-9]' 're:q' 're:(?=@)' 're:(?:TKT-[0-9]+)?(?=@)' 're:TKT-[0-9]+(?(1)>)' 're:--' 're:[-|]{2,}' \
           're:[a-z]{2,}' 're:\d\d' 're:the'; do
  printf '%s\n' "$bad" >> "$P/node-knowledge/.claude/words.txt"
  printf 'nothing of the node\n' > "$f"
  "$S" check node "$f" > /dev/null 2> "$T/err"; rc=$?
  out=$("$S" check node "$f" --json 2>/dev/null)
  check "$rc $(grep -c 'words.txt line 7' "$T/err") $(echo "$out" | grep -ic 'TKT\|Brightwater') $(wh node ready | grep -c 'line 7') $(grep -c Brightwater "$T/err")" "2 1 0 1 0" \
    "a re: line that holds nothing ($bad): exit 2, not ready, no word of the pattern in what it prints"
  cp "$T/words.keep" "$P/node-knowledge/.claude/words.txt"
done
{ printf '\357\273\277re:ZZB-[0-9]+\n'; cat "$T/words.keep"; } > "$P/node-knowledge/.claude/words.txt"
check "$(ck 'see ZZB-41')" "1 pattern " "a BOM before the list's first line: that line still reads, its re: a pattern"
cp "$T/words.keep" "$P/node-knowledge/.claude/words.txt"
for enc in latin1 utf16 bommid nul; do
  case $enc in
    latin1) { cat "$T/words.keep"; printf 'M\374ller\n'; } ;;
    utf16)  python3 -c 'import sys; sys.stdout.buffer.write(open(sys.argv[1], encoding="utf-8").read().encode("utf-16"))' "$T/words.keep" ;;
    bommid) { cat "$T/words.keep"; printf '\357\273\277Brightwater\n'; } ;;
    nul)    { cat "$T/words.keep"; printf 'Bright\000water\n'; } ;;
  esac > "$P/node-knowledge/.claude/words.txt"
  printf 'nothing of the node\n' > "$f"
  "$S" check node "$f" > /dev/null 2> "$T/err"; rc=$?
  check "$rc $(wh node ready | grep -c '^no ') $(grep -c 'not UTF-8\|NUL, a BOM' "$T/err")" "2 1 1" \
    "a word list that does not read as plain UTF-8 ($enc): exit 2, not ready — its words would never match, a silent pass"
done
cp "$T/words.keep" "$P/node-knowledge/.claude/words.txt"
printf 're:ACME-#?[0-9]+\nC# Labs\nre:ZZW-[0-9]+ # a trailing comment\n' >> "$P/node-knowledge/.claude/words.txt"
check "$(ck 'see ACME-123')" "1 pattern " "a # inside a re: pattern is the pattern's, never a comment"
check "$(ck 'the C# Labs team')" "1 word " "  and inside a plain word: C# Labs holds, never cut to C"
check "$(ck 'see ZZW-9')" "1 pattern " "  a # after a space still starts a comment"
cp "$T/words.keep" "$P/node-knowledge/.claude/words.txt"
printf 're:(a+)+b\n' >> "$P/node-knowledge/.claude/words.txt"
printf '%s\n' "$(printf 'a%.0s' $(seq 1 60))" > "$f"
s0=$(date +%s); SCOPE_PASS_SCAN_SECONDS=1 "$S" check node "$f" > /dev/null 2> "$T/err"; rc=$?; s1=$(date +%s)
check "$rc $(grep -c 'ran past 1 s' "$T/err") $([ $((s1 - s0)) -lt 10 ] && echo fast)" "2 1 fast" \
  "a pattern that backtracks catastrophically: the scan stops at its limit, exit 2, never a hang"
cp "$T/words.keep" "$P/node-knowledge/.claude/words.txt"
printf 're:(.|.|.|.)*QQ\n' >> "$P/node-knowledge/.claude/words.txt"
printf 'nothing of the node\n' > "$f"
s0=$(date +%s); SCOPE_PASS_SCAN_SECONDS=1 "$S" check node "$f" > /dev/null 2> "$T/err"; rc=$?
w=$(SCOPE_PASS_SCAN_SECONDS=1 "$S" where node | sed -n 's/^ready //p'); s1=$(date +%s)
check "$rc $(grep -c 'line 7: its re: pattern backtracks' "$T/err") $(echo "$w" | grep -c '^no .*line 7') $([ $((s1 - s0)) -lt 10 ] && echo fast)" "2 1 1 fast" \
  "  a pattern that backtracks on the load-time probe: stopped by the clock there too, exit 2, not ready, never a hang of where"
cp "$T/words.keep" "$P/node-knowledge/.claude/words.txt"
printf 'nothing of the node\n' > "$f"
for lim in -1 0 inf nan x; do SCOPE_PASS_SCAN_SECONDS=$lim "$S" check node "$f" > /dev/null 2> "$T/err"; printf '%s ' "$?$(grep -c Traceback "$T/err")"; done > "$T/lims"
check "$(cat "$T/lims")" "00 00 00 00 00 " "  a scan limit that is no positive number: the default, never a traceback"
printf 're:ID[[]0-9]+\n' >> "$P/node-knowledge/.claude/words.txt"
check "$(wh node ready) $(ck 'see ID[0-9] there')" "yes 1 pattern " "  a pattern that only warns of a nested set: ready, and it holds"
cp "$T/words.keep" "$P/node-knowledge/.claude/words.txt"
printf 're:(?=-)\n' >> "$P/node-knowledge/.claude/words.txt"
printf 'nothing of the node - at all\n' > "$f"
"$S" check node "$f" > /dev/null 2> "$T/err"; check "$? $(grep -c 'line 7: its re: pattern can match an empty string' "$T/err")" "2 1" \
  "a bare lookahead: refused where the list is read (its least width is 0), exit 2, never a hold of every draft nor a pass"
cat > "$T/nest.py" <<'PYEND'
import re, sys, time
sys.dont_write_bytecode = True   # a load beside the tool would leave a __pycache__ in the module on Linux
from importlib.machinery import SourceFileLoader
sp = SourceFileLoader("scope_pass", sys.argv[1]).load_module()
t0 = time.monotonic()
try:
    with sp.clock(0.5):
        with sp.clock(5):
            pass
        re.search(r"(a+)+b", "a" * 32)
    print("no-raise")
except sp._ScanLate:
    print("late", "fast" if time.monotonic() - t0 < 5 else "slow")
PYEND
check "$(python3 "$T/nest.py" "$S")" "late fast" "  a clock inside a clock leaves the outer one armed"
cp "$T/words.keep" "$P/node-knowledge/.claude/words.txt"
printf 'sec and PLUMWORD\n' > "$f"; "$S" check pub "$f" > /dev/null; check $? 0 "an open scope: nothing to hold"
head -c 40 "$CLAUDE_REPOS_JSON" > "$T/torn.json"
CLAUDE_REPOS_JSON="$T/torn.json" "$S" check node "$f" > /dev/null 2>&1; check $? 2 "a torn registry: exit 2, never a pass"
"$S" check nw "$f" > /dev/null 2> "$T/err"; check "$? $(grep -c 'no .claude/words.txt' "$T/err")" "2 1" "a confidential scope with no word list: exit 2 — a scan without its names would pass them"

echo "check --judge --json — a brief leaving the node (confidential-reach S5)"
# The judge is the gate's scope.brief row, read from a table of the suite's own; `claude` is a stand-in
# that logs each call and answers leak when the text says Larkspur (a made-up client's city).
cat > "$T/models.json" <<'EOF'
{"defaults": {"claude": {"model": "opus"}},
 "sites": {"scope.brief": {"kind": "classify", "provider": "claude", "model": "sonnet"},
           "other.site": {"kind": "classify", "provider": "off", "when_off": "skip"}}}
EOF
cat > "$T/claude" <<'EOF'
#!/bin/sh
# as the gate calls it: `-p` and a `--json-schema` the reply follows, or the stand-in refuses as claude would
case " $* " in *" -p "*) ;; *) echo "claude stand-in: no -p" >&2; exit 2 ;; esac
case " $* " in *" --json-schema "*) ;; *) echo "claude stand-in: no --json-schema" >&2; exit 2 ;; esac
in=$(cat); echo call >> "$(dirname "$0")/claude.calls"; printf '%s\n' "$in" > "$(dirname "$0")/claude.prompt"
case "$in" in *Larkspur*) v=leak;; *) v=clean;; esac
printf '{"type": "result", "is_error": false, "total_cost_usd": 0.004, "structured_output": {"text": "%s"}}\n' "$v"
EOF
chmod +x "$T/claude"
export GATE_LOG="$T/gate.jsonl"
J() { GATE_TABLE="${TABLE:-$T/models.json}" CLAUDE_BIN="${CB:-$T/claude}" "$S" check node "$f" --judge --json 2> "$T/judge.err"; }
key() { python3 -c 'import json, sys; d = json.loads(sys.stdin.read().strip().splitlines()[-1]); print(" ".join(str(d.get(k)) for k in sys.argv[1:]))' "$@"; }
printf 'Task: add a retry to the uploader\nWhy: the nightly job drops a file now and then\n' > "$f"
out=$(J); check "$? $(echo "$out" | key scan judge site provider model)" "0 clean clean scope.brief claude sonnet" "a clean brief: the scan and the judge both clean, exit 0"
check "$(echo "$out" | key sha256)" "$(shasum -a 256 "$f" | cut -d' ' -f1)" "  the sha256 of the bytes judged"
check "$(echo "$out" | key cost_usd) $(wc -l < "$T/claude.calls" | tr -d ' ')" "0.004 1" "  its cost, one judge call"
check "$(grep -c '"site": "scope.brief"' "$GATE_LOG")" 1 "  logged as the gate logs every classify"
printf 'Task: add a retry to the uploader\nWhy: the Larkspur depot drops a file now and then\n' > "$f"
out=$(J); check "$? $(echo "$out" | key scan judge)" "1 clean leak" "a brief the scan passes and the judge calls a leak: exit 1"
grep -q 'judge (claude, sonnet): leak' "$T/judge.err"; check $? 0 "  said on stderr"
: > "$T/claude.calls"
printf 'Task: retry the uploader\nWhy: PLUMWORD asked\n' > "$f"
out=$(J); check "$? $(echo "$out" | key scan hits judge)" "1 hits 1 None" "a scan hit: exit 1, no judge"
check "$(wc -l < "$T/claude.calls" | tr -d ' ')" 0 "  the judge never sees what the scan refused"
check "$(echo "$out" | grep -c PLUMWORD) $(grep -c PLUMWORD "$T/judge.err")" "0 1" "  the verdict names no term (it goes into an open repo); stderr does"
printf 'Task: add a retry to the uploader\n' > "$f"
TABLE="$T/no-row.json"; printf '{"sites": {"other.site": {"kind": "classify", "provider": "off"}}}\n' > "$TABLE"
out=$(TABLE="$TABLE" J); check "$? $(echo "$out" | key scan judge)" "2 clean error" "no scope.brief row: exit 2, never a pass"
grep -q 'no row for scope.brief' "$T/judge.err"; check $? 0 "  naming the missing row"
printf '{"sites": {"scope.brief": {"kind": "classify", "provider": "off", "when_off": "skip"}}}\n' > "$TABLE"
out=$(TABLE="$TABLE" J); check "$? $(echo "$out" | key judge)" "2 error" "a row off with when_off skip: exit 2 — no judge is no pass"
unset TABLE   # the two cases below judge with the good table: each fails on the claude it names alone
printf '#!/bin/sh\necho "not json"\n' > "$T/bad-claude"; chmod +x "$T/bad-claude"
out=$(CB="$T/bad-claude" J); check "$? $(echo "$out" | key judge)" "2 error" "a judge that answers no JSON: exit 2"
grep -q 'no row for scope.brief\|row is off' "$T/judge.err"; check $? 1 "  by the reply, not the table"
out=$(CB="$T/no-such-claude" J); check "$? $(echo "$out" | key judge)" "2 error" "no claude at all: exit 2"
grep -q 'no row for scope.brief\|row is off' "$T/judge.err"; check $? 1 "  by the missing claude, not the table"
: > "$T/claude.calls"
printf 'Task: retry the uploader\nWhy: the Node asked\n' > "$f"
out=$(J); check "$? $(echo "$out" | key scan hits judge)" "1 hits 1 None" "a brief naming the scope itself: a scan hit under --judge (S5's landing review)"
check "$(wc -l < "$T/claude.calls" | tr -d ' ')" 0 "  no judge"
check "$(echo "$out" | key scope)" "confidential:$(printf node | shasum -a 256 | cut -c1-8)" "  the verdict names the scope by its marker, never its name"
check "$(echo "$out" | grep -ic node)" 0 "  nor anywhere else"
out=$("$S" check node "$f" --json 2>/dev/null); check "$? $(echo "$out" | key scan)" "0 clean" "  without --judge (the pass's draft): the name stays exempt, its heading carries it"
printf 'Task: x\n' > "$f"
out=$(GATE_TABLE="$T/models.json" CLAUDE_BIN="$T/claude" "$S" check nw "$f" --judge --json 2>/dev/null); check "$? $(echo "$out" | key scan judge)" "2 error None" "  no word list: exit 2 before any judge"
out=$("$S" check node "$f" --json 2>/dev/null); check "$? $(echo "$out" | key scan judge)" "0 clean None" "--json without --judge: the scan's verdict alone"
unset GATE_LOG

echo "record and proof"
# record judges a confidential scope's draft on the gate's scope.upstream row: the suite's table and
# its stand-in claude (leak on Larkspur); the anchor has an origin, so the records branch goes there
python3 -c 'import json, sys; t = json.load(open(sys.argv[1])); t["sites"]["scope.upstream"] = {"kind": "classify", "provider": "claude", "model": "sonnet"}; json.dump(t, open(sys.argv[1], "w"))' "$T/models.json"
export GATE_TABLE="$T/models.json" CLAUDE_BIN="$T/claude"
git init -q --bare "$T/node-origin.git"; git -C "$P/node-knowledge" remote add origin "$T/node-origin.git"
printf '#!/bin/sh\n[ "$(git symbolic-ref --short HEAD)" = main ] && { echo "pre-commit: no commits on main" >&2; exit 1; }\nexit 0\n' > "$P/node-knowledge/.git/hooks/pre-commit"
chmod +x "$P/node-knowledge/.git/hooks/pre-commit"   # as a pipeline's that refuses main: the old commit there failed outright
: > "$T/claude.calls"
inbox() {  # inbox <scope> <day> <lines…> — the session's draft, in the anchor
  local s=$1 d=$2; shift 2
  { printf '# Upstream — %s — %s (%d lines)\n\n' "$s" "$d" "$#"; local n=0 l; for l in "$@"; do n=$((n + 1)); printf 'U%d. %s — rules/x.md\n' "$n" "$l"; done; } > "$P/$s-knowledge/dreams/$d-upstream.md"
}
dream() { printf '# Dream — %s — %s\n\nP1. a change — AGENTS.md\n' "$1" "$2" > "$P/$1-knowledge/dreams/$2.md"; }
"$S" record node > /dev/null 2> "$T/err"; check "$? $(grep -c 'no dream at' "$T/err")" "1 1" "no dream yet: refused"
dream node "$day"
"$S" record node > /dev/null 2> "$T/err"; check "$? $(grep -c 'no draft' "$T/err")" "1 1" "no draft: refused (a quiet week writes one too)"
printf 'U1. x\n' > "$P/node-knowledge/dreams/$day-upstream.md"
"$S" record node > /dev/null 2> "$T/err"; check "$? $(grep -c "heading" "$T/err")" "1 1" "a draft without this pass's heading: refused"
inbox node "$day" "A check beats a rule" "Name the tier first"
out=$("$S" record node); check $? 0 "a clean pass: exit 0"
grep -q "weekly review is about to send these lines out" "$T/claude.prompt"; check $? 0 "  judged with scope.upstream's question (UP_CONTEXT), not the brief's"
check "$(git -C "$P/node-knowledge" show "$rb:dreams/$day.md" | head -1)" "# Dream — node — $day" "  the dream on the anchor's records branch (kl-s5 D1-B), past a pre-commit that refuses main"
check "$(git -C "$P/node-knowledge" log -1 --format=%s "$rb") $(git -C "$P/node-knowledge" diff --name-only main "$rb" | tr '\n' ' ')" \
  "Dream: node $day (scope-pass record) dreams/$day-receipt.json dreams/$day.md " "  committed there, the dream and its receipt alone"
check "$(git -C "$T/node-origin.git" rev-parse -q --verify "refs/heads/$rb" | wc -l | tr -d ' ')" 1 "  on its origin"
check "$(cat "$T/pr.log")" "open $P/node-knowledge $rb main" "  its pull request opened and readied: the anchor's own merge lands it (kl-s5 D1-B)"
echo "$out" | grep -q '^pull request https://example.invalid/pr/1 ready'; check $? 0 "  said in record's output"
check "$(git -C "$P/node-knowledge" symbolic-ref --short HEAD) $(git -C "$P/node-knowledge" log -1 --format=%s main)" "main words" "  the checkout and its main untouched"
rm -f "$P/node-knowledge/.git/hooks/pre-commit"   # the cases below commit on the anchor's main by hand
check "$([ -e "$P/node-knowledge/dreams/$day.md" ] && echo left || echo gone)" gone "  the working-tree copy gone: an untracked one blocks the landing's fast-forward"
check "$(git -C "$V" show main:inbox/upstream/node.md | grep -c '^U')" 2 "  the draft, checked, as the inbox file on the vault's main"
check "$(git -C "$V" show main:inbox/upstream/node.md | head -1)" "# Upstream — $day" "  its heading export-safe, \`# Upstream — <day>\`: no scope, no count"
check "$(git -C "$V" show main:inbox/upstream/node.md | grep -ic node)" 0 "  nowhere else either"
check "$(wc -l < "$T/claude.calls" | tr -d ' ')" 1 "  judged once, on scope.upstream"
sha=$(git -C "$V" show main:inbox/upstream/node.md | shasum -a 256 | cut -d' ' -f1)
check "$(git -C "$P/node-knowledge" show "$rb:dreams/$day-receipt.json" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["receipt"], d["scope"], d["sha256"], d["scan"], d["judge"], d["site"], d["cycle"], d["records_ref"], len(d["judge_rev"]))')" \
  "complete $mark $sha clean clean scope.upstream $(date +%G-W%V) $rb 12" "  the receipt: complete, the bytes' sha256, scan and judge, the cycle, the records ref, the judge's revision; no term"
check "$("$S" receipt node | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["receipt"], d["verified"], d["cycle"])')" "complete True $(date +%G-W%V)" "  \`receipt\`: verified against the vault's file, for weekly-run and the barrier"
check "$(echo "$out" | tail -1)" "receipt complete sha256 $sha scan clean judge clean" "  said in record's last line, for the night's log"
check "$([ -e "$P/node-knowledge/dreams/$day-upstream.md" ] && echo left || echo gone)" gone "  the draft gone from the anchor"
check "$(git -C "$V" show main:log.md)" "- $day evolve --scope node: complete" "  one log.md line, a word, never a count (the log is pushed)"
check "$(cat "$T/kc.log")" "vlt -m Upstream: node $day inbox/upstream/node.md log.md" "  through knowledge-commit <vault-name>"
out=$("$S" proof node); check "$? $(echo "$out" | cut -d' ' -f1)" "5 WAITING" "proof before the anchor's merge: WAITING, exit 5 — never LAUNCHED off main"
echo "$out" | grep -q "pull request is ready, https://example.invalid/pr/1"; check $? 0 "  naming the ready pull request that lands it"
for s in none draft unknown; do echo $s > "$T/pr.state"
  out=$("$S" proof node); check "$? $(echo "$out" | cut -d' ' -f1)" "1 MISSING" "  a pull request $s (no token, no GitHub, none open): MISSING, exit 1 — never a WAITING nothing lands"
done
cp "$P/node-knowledge/.claude/words.txt" "$T/words.keep5"; printf 're:TKT-[0-9\n' >> "$P/node-knowledge/.claude/words.txt"
out=$("$S" proof node 2>&1); check "$? $(echo "$out" | grep -c 'words.txt line')" "2 1" \
  "  that MISSING on a list broken at load: exit 2, naming the list (weekly-run starts no session record would refuse)"
cp "$T/words.keep5" "$P/node-knowledge/.claude/words.txt"
rm -f "$T/pr.state"
git -C "$T/node-origin.git" update-ref refs/heads/main "refs/heads/$rb"   # the anchor's merge, on GitHub
out=$("$S" proof node); check "$? $(echo "$out" | cut -d' ' -f1)" "0 LAUNCHED" "proof once the dream is on the anchor's main (origin's, fetched): LAUNCHED"
echo "$out" | grep -q "on node-knowledge's origin/main;"; check $? 0 "  naming origin's main"
: > "$T/claude.calls"
CLAUDE_BIN="$T/no-such-claude" "$S" record node > /dev/null 2> "$T/err"; check "$? $(grep -c 'evolve --scope node' "$V/log.md")" "0 1" "record twice: exit 0, the log line once (the dream read from its branch)"
check "$(wc -l < "$T/claude.calls" | tr -d ' ') $(grep -c 'not judged again' "$T/err")" "0 1" "  bytes a current complete receipt names: no second judge, a gate outage changes nothing"
git -C "$T/node-origin.git" update-ref -d "refs/heads/$rb"   # GitHub deletes a merged head; the tracking ref stays
git -C "$P/node-knowledge" fetch -q origin main; git -C "$P/node-knowledge" reset -q --keep origin/main   # sync.py's fast-forward
: > "$T/pr.log"
"$S" record node > /dev/null 2>&1; rc=$?
check "$(git -C "$P/node-knowledge" status --porcelain | wc -l | tr -d ' ') $(grep -c '^open' "$T/pr.log")" "0 0" "  the checkout fast-forwarded: its tracked copies kept, no pull request opened again"
check "$rc $(git -C "$T/node-origin.git" rev-parse -q --verify "refs/heads/$rb" | wc -l | tr -d ' ')" "0 0" "  after the landing, nothing new: the merged branch is not pushed back"
check "$(git -C "$P/node-knowledge" show "$rb:dreams/$day-receipt.json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["receipt"])')" complete "  the complete receipt kept"
dream node "$day"; printf 'P2. a second thought — TODO.md\n' >> "$P/node-knowledge/dreams/$day.md"; inbox node "$day" "A check beats a rule" "A second pass the same day"
"$S" record node > /dev/null 2> "$T/err"; check "$? $(git -C "$T/node-origin.git" rev-parse -q --verify "refs/heads/$rb" | wc -l | tr -d ' ')" "0 1" \
  "  a second pass after the landing: recorded, the branch pushed again from main past the stale tracking ref"
check "$(git -C "$P/node-knowledge" log --format=%s "origin/main..$rb" | wc -l | tr -d ' ') $(git -C "$P/node-knowledge" diff --name-only origin/main "$rb" | tr '\n' ' ')" \
  "1 dreams/$day-receipt.json dreams/$day.md " "    one commit on origin's main: its own change alone"
out=$("$S" proof node); check "$? $(echo "$out" | cut -d' ' -f1)" "5 WAITING" "    proof: WAITING for its own pull request, not LAUNCHED by the first one's"
c2=$(git -C "$P/node-knowledge" rev-parse "$rb")
inbox node "$day" "A third thought" "Before the second one merged"
"$S" record node > /dev/null 2> "$T/err"; rc=$?
git -C "$P/node-knowledge" merge-base --is-ancestor "$c2" "$rb"; check "$rc $? $(git -C "$P/node-knowledge" rev-list --count "origin/main..$rb")" "0 0 2" \
  "  a third pass before the second's pull request merged: built on it, never forced over it (the third review)"
today_vault=$(git -C "$V" rev-parse HEAD)

d2=2026-01-04
dream node "$d2"; inbox node "$d2" "Seen in sec on Tuesday" "A clean line"
before=$(cat "$V/inbox/upstream/node.md" | head -1)
"$S" record node --day "$d2" > /dev/null 2> "$T/err"; check "$? $(grep -c 'held — 1 line' "$T/err")" "3 1" "a line naming the scope: held, exit 3 (its own code: rewrite the draft)"
check "$(head -1 "$V/inbox/upstream/node.md") $(git -C "$V" status --porcelain inbox | wc -l | tr -d ' ')" "# Upstream — $day 0" "  the vault's inbox file untouched"
check "$([ -e "$P/node-knowledge/dreams/$d2-upstream.md" ] && echo left || echo gone)" gone "  the draft gone: its text is the held file"
check "$(git -C "$P/node-knowledge" show "claude/$host/$d2-scope-pass:dreams/$d2-upstream-held.md" | grep -c 'Seen in sec')" 1 "  its text kept inside the anchor, committed on its records branch"
check "$(git -C "$V" show main:log.md | tail -1)" "- $d2 evolve --scope node: held" "  the log line: held, no count, no term"
check "$(git -C "$V" show main:log.md | grep -c 'sec')" 0 "  nothing of it on the vault's main"
out=$("$S" proof node --day "$d2"); check "$? $(echo "$out" | cut -d' ' -f1)" "3 HELD" "proof: HELD, exit 3"
inbox node "$d2" "A clean line"
"$S" record node --day "$d2" > /dev/null; check $? 0 "rewritten after a hold: recorded, exit 0"
check "$(git -C "$P/node-knowledge" show "claude/$host/$d2-scope-pass:dreams/$d2-receipt.json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["receipt"])')" complete "  the held receipt replaced by the complete one"
check "$(git -C "$V" show main:log.md | grep -c "$d2 evolve --scope node: held") $(git -C "$V" show main:log.md | grep -c "$d2 evolve --scope node: complete")" "0 1" \
  "  the held log line replaced by the clean one"
out=$("$S" proof node --day "$d2"); check "$? $(echo "$out" | cut -d' ' -f1)" "5 WAITING" "  proof: WAITING on its pull request, not HELD"
d4=2026-01-25; dream node "$d4"; inbox node "$d4" "A clean line" "The Larkspur depot drops a file"
"$S" record node --day "$d4" > /dev/null 2> "$T/err"; check "$? $(grep -c 'the judge found something' "$T/err")" "3 1" "a draft the scan passes and the judge calls a leak: held, exit 3"
check "$(git -C "$V" show main:log.md | grep "$d4")" "- $d4 evolve --scope node: held" "  the log line names no term"
check "$(git -C "$P/node-knowledge" show "claude/$host/$d4-scope-pass:dreams/$d4-receipt.json" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["receipt"], d["judge"])')" "held leak" "  its receipt: held, leak"
out=$("$S" proof node --day "$d4"); check "$? $(echo "$out" | cut -d' ' -f1)" "3 HELD" "  proof: HELD"
inbox node "$d4" "A clean line" "The Larkspur depot drops a file"   # the same bytes again, as a retry after a failed push finds them
CLAUDE_BIN="$T/no-such-claude" "$S" record node --day "$d4" > /dev/null 2> "$T/err"
check "$? $(grep -c 'held again, not judged' "$T/err")" "3 1" "  the same bytes again: held from the leak receipt, never judged a second time (the landing's scoped review)"
d5=2026-02-01; dream node "$d5"; inbox node "$d5" "A clean line"
CLAUDE_BIN="$T/no-such-claude" "$S" record node --day "$d5" > /dev/null 2> "$T/err"; check "$? $(grep -c 'the judge could not tell' "$T/err")" "1 1" "no judge: not recorded, exit 1 — a retry, never a hold; no judgment is no export"
check "$([ -e "$P/node-knowledge/dreams/$d5-upstream.md" ] && echo kept || echo gone) $(git -C "$V" show main:inbox/upstream/node.md | grep -c "$d5")" "kept 0" "  the draft kept for a retry, nothing in the vault"
out=$("$S" proof node --day "$d5"); check "$? $(echo "$out" | cut -d' ' -f1) $(echo "$out" | grep -c 'record retries it')" "1 MISSING 1" "  proof: MISSING, exit 1 (weekly-run's backstop records again), not HELD"
"$S" receipt node --day "$d5" > /dev/null; check $? 1 "  \`receipt\`: exit 1, not 3"
"$S" record node --day "$d5" > /dev/null; check "$? $("$S" proof node --day "$d5" | cut -d' ' -f1)" "0 WAITING" "  the retry with a judge: recorded, WAITING on its pull request"
rb5="claude/$host/$d5-scope-pass"; d5rc=$(git -C "$P/node-knowledge" show "$rb5:dreams/$d5-receipt.json")
sed -i.bak 's/^U1\. A clean line/U1. A cleaner line/' "$V/inbox/upstream/node.md" && rm -f "$V/inbox/upstream/node.md.bak"
git -C "$V" commit -qam "an edit after the judge, as a hand or a hook's sweep would make it"
out=$("$S" proof node --day "$d5"); check "$? $(echo "$out" | cut -d' ' -f1) $(echo "$out" | grep -c 'not the text judged')" "4 LEAKED 1" \
  "bytes changed after the judge, no name in them: LEAKED, exit 4 — the receipt binds the bytes"
git -C "$V" checkout -q HEAD~1 -- inbox/upstream/node.md; git -C "$V" commit -qam "the judged bytes again"
# A later run that holds, on the same day, never turns the judged file into a LEAKED (finding 6)
inbox node "$d5" "Seen in sec"
"$S" record node --day "$d5" > /dev/null 2>&1; check $? 3 "a held re-record after a complete one the same day: held, exit 3"
check "$(git -C "$P/node-knowledge" show "$rb5:dreams/$d5-receipt.json")" "$d5rc" "  the complete receipt untouched"
check "$(git -C "$P/node-knowledge" show "$rb5:dreams/$d5-receipt-held.json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["receipt"])')" held "  the held one beside it"
out=$("$S" proof node --day "$d5"); check "$? $(echo "$out" | cut -d' ' -f1)" "5 WAITING" "  proof: the judged file still certified, never LEAKED"
# A receipt of another judge revision names these bytes: a stale receipt, MISSING, not a leak. The
# records branch gets that receipt by git's plumbing, as record writes it.
echo "$d5rc" | python3 -c 'import json,sys; d=json.load(sys.stdin); d["judge_rev"]="000000000000"; print(json.dumps(d))' > "$T/old-rc.json"
A="$P/node-knowledge"; blob=$(git -C "$A" hash-object -w "$T/old-rc.json")
GIT_INDEX_FILE="$T/idx" git -C "$A" read-tree "$rb5"
GIT_INDEX_FILE="$T/idx" git -C "$A" update-index --cacheinfo "100644,$blob,dreams/$d5-receipt.json"
c=$(git -C "$A" commit-tree "$(GIT_INDEX_FILE="$T/idx" git -C "$A" write-tree)" -p "$rb5" -m "a receipt of an older judge")
git -C "$A" update-ref "refs/heads/$rb5" "$c"; rm -f "$T/idx"
out=$("$S" proof node --day "$d5"); check "$? $(echo "$out" | cut -d' ' -f1-4)" "1 MISSING a current receipt" "a receipt of another judge revision: MISSING a current receipt, exit 1, not LEAKED"
d3=2026-01-11; dream node "$d3"; git -C "$P/node-knowledge" add -A; git -C "$P/node-knowledge" commit -qm "d3"
printf '# Upstream — node — %s (1 lines)\n\nU1. Seen in sec — rules/x.md\n' "$d3" > "$V/inbox/upstream/node.md"
git -C "$V" commit -qam "a leak, as a hook's sweep would make it"
out=$("$S" proof node --day 2026-01-18); check "$? $(echo "$out" | cut -d' ' -f1)" "4 LEAKED" "a leak on the vault's main: LEAKED, exit 4, even with no dream that day"
out=$("$S" proof node --day "$d3"); check "$? $(echo "$out" | cut -d' ' -f1)" "4 LEAKED" "an inbox file on the vault's main naming the scope: LEAKED, exit 4"
cp "$P/node-knowledge/.claude/words.txt" "$T/words.keep2"; printf 're:TKT-[0-9\n' >> "$P/node-knowledge/.claude/words.txt"
out=$("$S" proof node --day "$d3" 2>/dev/null); check "$? $(echo "$out" | cut -d' ' -f1)" "4 LEAKED" "  a broken re: line in the list hides no LEAKED"
"$S" record node --day "$d3" > /dev/null 2> "$T/err"; check "$? $(grep -c 'not ready' "$T/err")" "2 1" "  record on that list: not ready, exit 2 (a retry never passes it)"
cp "$T/words.keep2" "$P/node-knowledge/.claude/words.txt"
"$S" record node --day "$d3" > /dev/null 2> "$T/err"; check "$? $(grep -c '^LEAKED' "$T/err") $(git -C "$V" show main:log.md | grep -c "$d3")" "4 1 0" \
  "  record over it: LEAKED, exit 4, never a 'nothing went upstream' log line"
git -C "$V" checkout -q "$today_vault" -- inbox/upstream/node.md; git -C "$V" commit -qam "undo the leak; today's file again"
# A day certified clean before the list held TKT ids; then the list gains them, and a broken line
# (refused at load) beside them: the fallback read still finds the TKT id, never a LAUNCHED
d6=2026-02-08; cp "$P/node-knowledge/.claude/words.txt" "$T/words.keep4"; aa=$(printf 'a%.0s' $(seq 1 40))
grep -v '^re:TKT' "$T/words.keep4" > "$P/node-knowledge/.claude/words.txt"
dream node "$d6"; inbox node "$d6" "Filed as TKT-12 @ noon, then $aa"
"$S" record node --day "$d6" > /dev/null 2>&1; rc=$?
cp "$T/words.keep4" "$P/node-knowledge/.claude/words.txt"; printf 're:(?=@)\n' >> "$P/node-knowledge/.claude/words.txt"
out=$("$S" proof node --day "$d6" 2>/dev/null); check "$rc $? $(echo "$out" | cut -d' ' -f1)" "0 4 LEAKED" \
  "a broken pattern hides no leak another pattern finds: LEAKED, exit 4, never LAUNCHED"
# one pattern that finds the id, then stalls on the a's past the clock: its hit before the stall counts
grep -v '^re:TKT' "$T/words.keep4" > "$P/node-knowledge/.claude/words.txt"; printf 're:TKT-[0-9]+|(a+)+b\n' >> "$P/node-knowledge/.claude/words.txt"
out=$(SCOPE_PASS_SCAN_SECONDS=1 "$S" proof node --day "$d6" 2>/dev/null); check "$? $(echo "$out" | cut -d' ' -f1)" "4 LEAKED" \
  "  a pattern's hit before it stalls is kept by the fallback read: LEAKED, never LAUNCHED"
cp "$T/words.keep4" "$P/node-knowledge/.claude/words.txt"
git -C "$V" checkout -q "$today_vault" -- inbox/upstream/node.md; git -C "$V" commit -qam "today's file again"
dream pub "$day"; inbox pub "$day" "open named, as an open scope may"
pubmain=$(git -C "$P/pub-knowledge" rev-parse main)
"$S" record pub > /dev/null; check "$? $("$S" proof pub | cut -d' ' -f1)" "0 MISSING" "an open scope: its names go up, the global dream reads it whole anyway"
check "$("$S" proof pub | grep -c 'has no origin, so nothing lands it')" 1 "  an anchor with no origin: MISSING, a hand merge named — never WAITING, nothing would land it"
check "$(git -C "$P/pub-knowledge" log -1 --format=%s "$rb")" "Dream: pub $day (scope-pass record)" "  committed in an anchor with no workflow.json, on a local branch (no origin)"
git -C "$P/pub-knowledge" merge -q --ff-only "$rb"   # the hand merge
check "$("$S" proof pub | cut -d' ' -f1)" "LAUNCHED" "  merged into its main: LAUNCHED"
printf '\nmore\n' >> "$P/pub-knowledge/dreams/$day.md"; inbox pub "$day" "open named, as an open scope may"
"$S" record pub > /dev/null 2>&1
check "$([ -e "$P/pub-knowledge/dreams/$day.md" ] && echo kept || echo gone) $(git -C "$P/pub-knowledge" diff --name-only main "$rb" | tr '\n' ' ')" "kept dreams/$day.md " \
  "  a re-record after the landing: the checkout's tracked dream kept (finding 11), the branch restarted from main"
git -C "$P/pub-knowledge" checkout -q -- "dreams/$day.md"
check "$(git -C "$V" show main:inbox/upstream/pub.md | head -1)" "# Upstream — $day" "  an open scope's heading the same safe form"
cp "$V/inbox/upstream/pub.md" "$T/pub.ok"
printf '# Upstream — pub — %s (1 lines)\n\nU1. open named, as an open scope may — rules/x.md\n' "$day" > "$V/inbox/upstream/pub.md"; git -C "$V" commit -qam "a legacy heading"
out=$("$S" proof pub); check "$? $(echo "$out" | cut -d' ' -f1)" "1 MISSING" "a legacy heading on the vault's main never certifies a pass: MISSING, not LAUNCHED"
{ printf '# Upstream — %s\n\n' "$day"; echo "U1. a line nobody judged — rules/x.md"; } > "$V/inbox/upstream/pub.md"; git -C "$V" commit -qam "bytes no receipt names"
out=$("$S" proof pub); check "$? $(echo "$out" | grep -c 'its sha256 differs from the receipt')" "1 1" "  the safe heading over other bytes: no receipt certifies it (an open scope: MISSING, exit 1)"
"$S" receipt pub > "$T/rcpt"; check "$? $(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["verified"])' "$T/rcpt")" "1 False" "  \`receipt\`: not verified, exit 1"
cp "$T/pub.ok" "$V/inbox/upstream/pub.md"; git -C "$V" commit -qam "the certified bytes again"
check "$("$S" proof pub | cut -d' ' -f1)" "LAUNCHED" "  the certified bytes again: LAUNCHED"
git -C "$P/pub-knowledge" reset -q --hard "$pubmain"
"$S" proof node --day 2026-01-01 > /dev/null; check $? 1 "proof of a day with no pass: exit 1"

echo "weekly-run aurora --scope"
lg="$T/logs/$day-aurora-node.log"
out=$("$W" aurora --scope node --dry-run); check $? 0 "--dry-run: exit 0"
echo "$out" | grep -q "recorded today, waiting on its pull request"; check $? 0 "  says the pass is recorded today and waits on its pull request (proof 5, not landed)"
echo "$out" | grep -qE '^  2 dream +claude -p "/aurora dream --scope node" from '"$P/node-knowledge"' \(confidential: yes\)'; check $? 0 "  the session from the anchor"
"$W" aurora --scope node; check "$? $(grep -c 'already, before this run' "$lg")" "0 1" "a real run on a landed day: its proof, no session"
check "$("$W" aurora --scope pub --dry-run | grep -c '^  1 login   the one this run starts on (the scope names none)$')" 1 "  a scope with no login: the login line reads plainly"
out=$("$W" aurora --scope np --dry-run); check "$? $(echo "$out" | grep -c 'refused: scope np is not ready — dreams/ is not in')" "1 1" "a scope not ready: refused in one line"
out=$("$W" aurora --scope 'x;y' 2>&1); check "$?" 2 "a scope name that is no name: exit 2"
out=$("$W" sextant --scope pub 2>&1); check "$?" 2 "--scope is aurora's alone"

# The stand-in session: writes what the section writes; $1 = record (the Record step) or stop (killed before it)
cat > "$T/fake-claude" <<EOF
#!/usr/bin/env bash
s=\${sections##* }; d=\$(date +%F); a="$P/\$s-knowledge"; [ "\$s" = seat ] && a="$P/node-knowledge"
mkdir -p "\$a/dreams"
printf '# Dream — %s — %s\n\nP1. x — AGENTS.md\nP2. y — TODO.md\n' "\$s" "\$d" > "\$a/dreams/\$d.md"
printf '# Upstream — %s — %s (1 lines)\n\nU1. %s — rules/x.md\n' "\$s" "\$d" "\${FAKE_LINE:-A generalised line}" > "\$a/dreams/\$d-upstream.md"
echo "CONFIG=\${CLAUDE_CONFIG_DIR:-default} SECTIONS=\$sections PWD=\$PWD" >> "$T/sessions.log"
[ "\${FAKE_STEP:-record}" = record ] && "$S" record "\$s"
true
EOF
chmod +x "$T/fake-claude"
for r in node pub; do unrecord "$P/$r-knowledge"; done
git -C "$V" rm -q inbox/upstream/node.md inbox/upstream/pub.md; : > "$V/log.md"; git -C "$V" commit -qam "undo today"
rm -f "$lg"
WEEKLY_CLAUDE="$T/fake-claude" "$W" aurora --scope node; check $? 0 "the session records itself: exit 0"
grep -q "^WAITING dreams/$day.md on node-knowledge's $rb, pushed; its pull request is ready" "$lg"; check $? 0 "  WAITING in its own log: the dream's pull request is ready, the anchor's merge lands it"
grep -q '^FAILED' "$lg"; check $? 1 "  no FAILED line, nothing posted"
grep -q '^RECEIPT {"receipt": "complete", "verified": true' "$lg"; check $? 0 "  the verified receipt in the night's log, for the barrier"
check "$(tail -1 "$T/sessions.log")" "CONFIG=default SECTIONS=dream --scope node PWD=$P/node-knowledge" "  /aurora dream --scope node, from the anchor, on the login it started on"
lg="$T/logs/$day-aurora-pub.log"
FAKE_STEP=stop WEEKLY_CLAUDE="$T/fake-claude" "$W" aurora --scope pub; check $? 1 "a session that wrote its files and stopped, in an anchor nothing lands from: exit 1, said"
grep -q "^== the run left its files unrecorded — scope-pass record pub" "$lg"; check $? 0 "  the backstop recorded them"
grep -q "^MISSING dreams/$day.md on pub-knowledge's main: .* has no origin" "$lg"; check $? 0 "  proof: MISSING, no origin lands it"
unrecord "$P/node-knowledge"
git -C "$V" rm -q inbox/upstream/node.md; grep -v 'scope node:' "$V/log.md" > "$T/log.md"; cp "$T/log.md" "$V/log.md"; git -C "$V" commit -qam "undo today"
lg="$T/logs/$day-aurora-node.log"; rm -f "$lg"
FAKE_LINE="Seen in sec" WEEKLY_CLAUDE="$T/fake-claude" "$W" aurora --scope node; check $? 1 "a session whose inbox file names the scope: exit 1"
grep -q "^FAILED scope node $day: its draft was held inside the anchor, nothing went upstream" "$lg"; check $? 0 "  FAILED, held"
check "$(grep -c 'Seen in sec' "$V/bulletin.md" 2>/dev/null; true)" "0" "  the bulletin never quotes it"
check "$(grep -c 'node-knowledge' "$V/bulletin.md" 2>/dev/null; true)" "0" "  nor names the anchor (posted from the vault, never the anchor's cwd)"

aa=$(printf 'a%.0s' $(seq 1 40))
printf 'x %s y\n' "$aa" > "$V/inbox/upstream/node.md"; git -C "$V" add inbox/upstream/node.md; git -C "$V" commit -qm "a run of a's"
cp "$P/node-knowledge/.claude/words.txt" "$T/words.keep3"; printf 're:(a+)+b\n' >> "$P/node-knowledge/.claude/words.txt"
n0=$(grep -c 'SECTIONS=dream --scope node' "$T/sessions.log"); rm -f "$lg"
SCOPE_PASS_SCAN_SECONDS=1 WEEKLY_CLAUDE="$T/fake-claude" "$W" aurora --scope node > /dev/null 2>&1; check $? 1 "a word list that cannot judge the vault's current file (a pattern past the clock on it): exit 1"
check "$(grep -c 'SECTIONS=dream --scope node' "$T/sessions.log")" "$n0" "  no session started (it would end the same way)"
grep -q "^FAILED scope node $day: its anchor's .claude/words.txt cannot judge the text" "$lg"; check $? 0 "  FAILED, naming the word list"
check "$(SCOPE_PASS_SCAN_SECONDS=1 "$W" aurora --scope node --dry-run | grep -cF 'its word list cannot judge (scope-pass proof node says why): a real run stops at its proof, no session')" 1 \
  "  --dry-run says the real run stops at its proof"
git -C "$V" rm -q inbox/upstream/node.md; git -C "$V" commit -qm "undo the a's"
unrecord "$P/node-knowledge"; rm -f "$P/node-knowledge/dreams/$day"*   # a clean day: the held case above left its receipt
n0=$(grep -c 'SECTIONS=dream --scope node' "$T/sessions.log"); rm -f "$lg"
SCOPE_PASS_SCAN_SECONDS=1 FAKE_LINE="mail them $aa" WEEKLY_CLAUDE="$T/fake-claude" "$W" aurora --scope node > /dev/null 2>&1; check $? 1 "a list only this draft trips: exit 1"
check "$(grep -c 'SECTIONS=dream --scope node' "$T/sessions.log")" "$((n0 + 1))" "  one session (nothing could tell before it)"
grep -q "^FAILED scope node $day: its anchor's .claude/words.txt cannot judge the text" "$lg"; check $? 0 "  FAILED from record's exit 2, never 'record retries it'"
# proof's own verdict stands over record's word-list stop: a copy of the module whose scope-pass is a
# stand-in answering proof from $T/sp.codes, one exit code per call (the real one for where)
mkdir -p "$T/mods"; cp -R "$D" "$T/mods/aurora"; ln -s "$D/../regatta" "$T/mods/regatta"
cat > "$T/mods/aurora/bin/scope-pass" <<EOF
#!/bin/sh
case "\$1" in
  where) exec "$S" "\$@" ;;
  proof) n=\$((\$(cat "$T/sp.n" 2>/dev/null || echo 0) + 1)); echo \$n > "$T/sp.n"
         c=\$(echo \$(cat "$T/sp.codes") | cut -d' ' -f\$n); c=\${c:-1}
         case \$c in 4) echo "LEAKED stand-in" ;; 2) echo "scope-pass proof: .claude/words.txt line 7: stand-in" ;; *) echo "MISSING stand-in" ;; esac
         exit \$c ;;
  record) echo "scope-pass record: .claude/words.txt: a re: line matches an empty string in this text" >&2; exit 2 ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$T/mods/aurora/bin/scope-pass"
rm -f "$T/sp.n" "$lg"; echo "1 1 4" > "$T/sp.codes"
FAKE_STEP=stop WEEKLY_CLAUDE="$T/fake-claude" "$T/mods/aurora/bin/weekly-run" aurora --scope node > /dev/null 2>&1; check $? 1 "proof LEAKED after the backstop's record stopped on the word list: exit 1"
grep -q "^FAILED scope node $day: LEAKED" "$lg"; check $? 0 "  FAILED LEAKED, never the word list's stop over it"
rm -f "$T/sp.n" "$lg"; echo "4 2" > "$T/sp.codes"; n0=$(grep -c 'SECTIONS=dream --scope node' "$T/sessions.log")
WEEKLY_NOW=2026-01-02 WEEKLY_CLAUDE="$T/fake-claude" "$T/mods/aurora/bin/weekly-run" aurora --scope node > /dev/null 2>&1
check "$? $(grep -c "^FAILED scope node $day: LEAKED" "$lg") $(grep -c 'SECTIONS=dream --scope node' "$T/sessions.log")" "1 1 $n0" \
  "  a day's LEAKED before a later day's word-list stop: LEAKED, and no session"
rm -f "$T/sp.n" "$lg"; echo "2 4" > "$T/sp.codes"
WEEKLY_NOW=2026-01-02 WEEKLY_CLAUDE="$T/fake-claude" "$T/mods/aurora/bin/weekly-run" aurora --scope node > /dev/null 2>&1
check "$? $(grep -c "^FAILED scope node $day: LEAKED" "$lg") $(grep -c 'SECTIONS=dream --scope node' "$T/sessions.log")" "1 1 $n0" \
  "  and a word-list stop before a later day's LEAKED: every day read, LEAKED, no session"
rm -f "$T/sp.n" "$lg"; echo "2 5" > "$T/sp.codes"
WEEKLY_NOW=2026-01-02 WEEKLY_CLAUDE="$T/fake-claude" "$T/mods/aurora/bin/weekly-run" aurora --scope node > /dev/null 2>&1
check "$? $(grep -c 'already, before this run' "$lg")" "0 1" "  a word-list stop before a later day's WAITING: already done, exit 0"
rm -f "$P/node-knowledge/dreams/$day"*
cp "$T/words.keep3" "$P/node-knowledge/.claude/words.txt"; unrecord "$P/node-knowledge"
printf 're:TKT-[0-9\n' >> "$P/node-knowledge/.claude/words.txt"
out=$("$S" proof node 2>&1); check "$? $(echo "$out" | grep -c 'words.txt line')" "2 1" "proof on a list broken at load, no vault file to trip it: exit 2, naming the list"
# weekly-run through the real where on that list: proof decides, no session
lg="$T/logs/$day-aurora-node.log"; rm -f "$lg"; n0=$(grep -c 'SECTIONS=dream --scope node' "$T/sessions.log")
WEEKLY_CLAUDE="$T/fake-claude" "$W" aurora --scope node > /dev/null 2>&1
check "$? $(grep -c "^FAILED scope node $day: its anchor's .claude/words.txt cannot judge" "$lg") $(grep -c 'SECTIONS=dream --scope node' "$T/sessions.log")" "1 1 $n0" \
  "weekly-run on a list refused at load: FAILED naming the word list, no session"
check "$("$W" aurora --scope node --dry-run | grep -c 'a real run stops at its proof, no session')" 1 "  --dry-run says so"
printf '# Upstream — %s\n\nU1. Seen in sec — rules/x.md\n' "$day" > "$V/inbox/upstream/node.md"; git -C "$V" add inbox/upstream/node.md; git -C "$V" commit -qm "a leak"
rm -f "$lg"; WEEKLY_CLAUDE="$T/fake-claude" "$W" aurora --scope node > /dev/null 2>&1
check "$? $(grep -c "^FAILED scope node $day: LEAKED" "$lg") $(grep -c 'SECTIONS=dream --scope node' "$T/sessions.log")" "1 1 $n0" \
  "  and a leak on the vault's main: LEAKED stands over the list refused at load, no session"
git -C "$V" rm -q inbox/upstream/node.md; git -C "$V" commit -qm "undo the leak"
cp "$T/words.keep3" "$P/node-knowledge/.claude/words.txt"
chmod 000 "$P/node-knowledge/.claude/words.txt"
if [ -r "$P/node-knowledge/.claude/words.txt" ]; then echo "  skip  an unreadable word list (this user reads a mode-000 file)"; else
  printf 'nothing of the node\n' > "$f"; "$S" check node "$f" > /dev/null 2> "$T/err"; rc=$?
  check "$rc $(grep -c 'words.txt: cannot be read' "$T/err") $(grep -c Traceback "$T/err") $(wh node ready | grep -c 'cannot be read')" "2 1 0 1" \
    "an unreadable word list: exit 2, not ready, never a traceback"
fi
chmod 644 "$P/node-knowledge/.claude/words.txt"

echo "weekly-run --scope: a scope's login"
lg="$T/logs/$day-aurora-seat.log"
WEEKLY_ACCOUNT="$T/no-such-account" WEEKLY_CLAUDE="$T/fake-claude" "$W" aurora --scope seat; check $? 1 "confidential, its login unproved: exit 1"
grep -q "^FAILED scope seat $day: confidential, and its login seat-login could not be proved here" "$lg"; check $? 0 "  not run on another seat"
check "$(grep -c 'SECTIONS=dream --scope seat' "$T/sessions.log")" 0 "  no session started"
printf '#!/bin/sh\necho "{\\"skipped\\": [[\\"seat-login\\", \\"week at 99%%\\"]]}"\nexit 3\n' > "$T/acct"; chmod +x "$T/acct"
WEEKLY_ACCOUNT="$T/acct" WEEKLY_CLAUDE="$T/fake-claude" "$W" aurora --scope seat > /dev/null 2>&1; check $? 1 "its login has no room: exit 1"
grep -q "^FAILED scope seat $day: its login seat-login cannot run it now (seat-login: week at 99%)" "$lg"; check $? 0 "  saying why, never another seat"
check "$(grep -c "Aurora's scope pass did not run" "$V/bulletin.md")" 2 "  one bulletin line each refusal"
check "$(grep -c 'week at 99' "$V/bulletin.md")" 0 "  account's reasons in the log alone (they can name the anchor)"
printf '#!/bin/sh\necho "{\\"account\\": \\"primary\\", \\"env\\": {\\"CLAUDE_CONFIG_DIR\\": \\"%s/other-dir\\"}}"\n' "$T" > "$T/acct"; chmod +x "$T/acct"
WEEKLY_ACCOUNT="$T/acct" WEEKLY_CLAUDE="$T/fake-claude" "$W" aurora --scope seat > /dev/null 2>&1; check $? 1 "account pick answers another login: exit 1"
grep -q "^FAILED scope seat $day: confidential, and its login seat-login could not be proved here — not run on another seat (account pick chose primary)" "$lg"; check $? 0 "  never on that seat"
check "$(grep -c 'other-dir' "$T/sessions.log")" 0 "  no session started there"
printf '#!/bin/sh\necho "$*" > "%s/acct.args"\necho "{\\"account\\": \\"seat-login\\", \\"env\\": {\\"CLAUDE_CONFIG_DIR\\": \\"%s/seat-dir\\"}}"\n' "$T" "$T" > "$T/acct"; chmod +x "$T/acct"
WEEKLY_ACCOUNT="$T/acct" WEEKLY_CLAUDE="$T/fake-claude" "$W" aurora --scope seat > /dev/null 2>&1
check "$(cat "$T/acct.args")" "pick --repo $P/node-knowledge --json" "account pick --repo <anchor>"
check "$(grep 'SECTIONS=dream --scope seat' "$T/sessions.log" | tail -1 | cut -d' ' -f1)" "CONFIG=$T/seat-dir" "  the session runs in the picked login's config dir"

cp "$P/node-knowledge/.claude/words.txt" "$T/words.bak"; printf 'Before\n' >> "$P/node-knowledge/.claude/words.txt"
"$S" record node > /dev/null 2> "$T/err"; rc=$?
check "$([ "$rc" -ne 0 ] && echo refused || echo "passed $rc")" refused "bytes a complete receipt names, and a word added since: the scan still runs and refuses (the third review)"
cp "$T/words.bak" "$P/node-knowledge/.claude/words.txt"
echo; [ "$fails" -eq 0 ] && echo "scope-pass: all ok" || { echo "scope-pass: $fails failed"; exit 1; }
