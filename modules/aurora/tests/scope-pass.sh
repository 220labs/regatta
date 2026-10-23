#!/usr/bin/env bash
# scope-pass's suite, and weekly-run's --scope (knowledge-layers S5): one scope's pass under a scratch
# HOME, config dir, registry and vault, every name made up. `node` is confidential (anchor
# node-knowledge, repo `sec`, its word list naming PLUMWORD), `pub` open (anchor pub-knowledge, repo
# `open`), `bare` an anchor whose in_place lacks dreams/, `ghost` an anchor not cloned. where says what
# the pass reads and when it may not run; check holds a confidential scope's repos, paths and words;
# record lands the dream in the anchor and the draft, checked, as the vault's inbox file, or holds it
# back inside the anchor; proof
# says which; weekly-run --scope runs it with a stand-in session. No network, no `claude`, no real
# repo touched (knowledge-commit and account are stand-ins).
#   bash modules/aurora/tests/scope-pass.sh
set -u
D="$(cd "$(dirname "$0")/.." && pwd -P)"
S="$D/bin/scope-pass"; W="$D/bin/weekly-run"
T="$(mktemp -d)"; T="$(cd "$T" && pwd -P)"
trap '[ -n "${KEEP:-}" ] || rm -rf "$T"' EXIT; [ -n "${KEEP:-}" ] && echo "scratch $T"
for v in $(env | sed -n 's/^\(REGATTA[A-Za-z0-9_]*\)=.*/\1/p; s/^\(CLAUDE[A-Za-z0-9_]*\)=.*/\1/p; s/^\(ATLAS[A-Za-z0-9_]*\)=.*/\1/p; s/^\(WEEKLY[A-Za-z0-9_]*\)=.*/\1/p'); do unset "$v"; done
export HOME="$T/u" REGATTA_CONFIG="$T/config" ACCOUNTS_FILE="$T/no-accounts.json" CLAUDE_REPOS_JSON="$T/repos.json" \
       WEEKLY_LOG_DIR="$T/logs" SCOPE_PASS_COMMIT="$T/kc" \
       GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
unset AURORA_SECTIONS AURORA_TODAY AURORA_HOUR
fails=0
check() {
  if [ "$1" = "$2" ]; then echo "  ok  $3"; else echo "  FAIL $3"; echo "       got:  $1"; echo "       want: $2"; fails=$((fails + 1)); fi
}
P="$T/u/projects"; V="$T/vault"; day=$(date +%F)
mkdir -p "$REGATTA_CONFIG/atlas" "$REGATTA_CONFIG/aurora" "$P/sec/docs" "$P/open" "$T/u/.claude/projects"
: > "$REGATTA_CONFIG/aurora/skip-hosts"
printf 'vlt\n%s\n' "$V" > "$REGATTA_CONFIG/atlas/vault"
newrepo() {  # newrepo <dir> <in_place json or ""> — a git repo on main, its workflow committed
  mkdir -p "$1"; git -C "$1" init -q -b main
  [ -n "$2" ] && { mkdir -p "$1/.claude"; printf '{"checkpoint": true, "main": "main", "in_place": %s}\n' "$2" > "$1/.claude/workflow.json"; }
  git -C "$1" add -A; git -C "$1" commit -q --allow-empty -m init
}
newrepo "$V" '["inbox/", "dreams/", "log.md"]'
newrepo "$P/node-knowledge" '["memory/", "dreams/"]'
newrepo "$P/pub-knowledge" ""
newrepo "$P/bare-anchor" '["memory/"]'
newrepo "$P/nw-knowledge" '["dreams/"]'
mkdir -p "$P/node-knowledge/memory/sec" "$P/node-knowledge/dreams" "$P/pub-knowledge/dreams" "$V/memory/open"
printf '# the node'"'"'s own names; `node` too, which the scope'"'"'s own name overrides\nPLUMWORD\nnode\n\n' > "$P/node-knowledge/.claude/words.txt"
git -C "$P/node-knowledge" add -A; git -C "$P/node-knowledge" commit -qm words
cat > "$CLAUDE_REPOS_JSON" <<'EOF'
{"repos": {"node-knowledge": {}, "sec": {}, "pub-knowledge": {}, "open": {}, "bare-anchor": {}, "ghost-knowledge": {}, "nw-knowledge": {}},
 "scopes": {"node": {"file": "n", "repos": ["node-knowledge", "sec"], "confidential": true},
            "pub": {"file": "p", "repos": ["pub-knowledge", "open"]},
            "bare": {"file": "b", "repos": ["bare-anchor"]},
            "ghost": {"file": "g", "repos": ["ghost-knowledge"]},
            "nw": {"file": "w", "repos": ["nw-knowledge"], "confidential": true},
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
wh() { "$S" where "$1" 2>&1 | sed -n "s/^$2 //p"; }

echo "where"
check "$(wh node ready) $(wh node confidential) $(wh node anchor)" "yes yes $P/node-knowledge" "a confidential scope with its anchor here: ready, from the anchor"
check "$(wh node inbox) $(wh node dream)" "$V/inbox/upstream/node.md $P/node-knowledge/dreams/$day.md" "  the inbox file in the vault, the dream in the anchor"
check "$(wh node draft)" "$P/node-knowledge/dreams/$day-upstream.md" "  the draft beside the dream, never in the vault (its SessionEnd hook pushes in_place dirt)"
check "$(wh node memory) $(wh node words) $(wh node members)" "$P/node-knowledge/memory $P/node-knowledge/.claude/words.txt node-knowledge sec" \
  "  its memory in the node, its word list, its members"
check "$(wh pub confidential) $(wh pub memory) $(wh pub words) $(wh pub login)" "no $V/memory/open none none" "an open scope: its members' memory in the vault"
check "$(wh pub ready)" "yes" "  no workflow.json in the anchor: nothing denies the record"
"$S" where bare >/dev/null 2>&1; check "$? $(wh bare ready | grep -c 'dreams/ is not in bare-anchor')" "1 1" "an anchor whose in_place lacks dreams/: not ready, exit 1, naming it"
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
printf 'sec and PLUMWORD\n' > "$f"; "$S" check pub "$f" > /dev/null; check $? 0 "an open scope: nothing to hold"
head -c 40 "$CLAUDE_REPOS_JSON" > "$T/torn.json"
CLAUDE_REPOS_JSON="$T/torn.json" "$S" check node "$f" > /dev/null 2>&1; check $? 2 "a torn registry: exit 2, never a pass"

echo "record and proof"
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
check "$(git -C "$P/node-knowledge" show "main:dreams/$day.md" | head -1)" "# Dream — node — $day" "  the dream on the anchor's main"
check "$(git -C "$P/node-knowledge" log -1 --format=%s)" "Dream: node $day (scope-pass record)" "  committed there, its path alone"
check "$(git -C "$V" show main:inbox/upstream/node.md | grep -c '^U')" 2 "  the draft, checked, as the inbox file on the vault's main"
check "$([ -e "$P/node-knowledge/dreams/$day-upstream.md" ] && echo left || echo gone)" gone "  the draft gone from the anchor"
check "$(git -C "$V" show main:log.md)" "- $day dream --scope node: 1 P-items in the scope's dream, 2 upstream line(s)" "  one log.md line, counts only"
check "$(cat "$T/kc.log")" "vlt -m Upstream: node $day inbox/upstream/node.md log.md" "  through knowledge-commit <vault-name>"
out=$("$S" proof node); check "$? $(echo "$out" | cut -d' ' -f1)" "0 LAUNCHED" "proof: LAUNCHED"
today_vault=$(git -C "$V" rev-parse HEAD)
"$S" record node > /dev/null; check "$? $(grep -c 'dream --scope node' "$V/log.md")" "0 1" "record twice: exit 0, the log line once"

d2=2026-01-04
dream node "$d2"; inbox node "$d2" "Seen in sec on Tuesday" "A clean line"
before=$(cat "$V/inbox/upstream/node.md" | head -1)
"$S" record node --day "$d2" > /dev/null 2> "$T/err"; check "$? $(grep -c 'held — 1 line' "$T/err")" "1 1" "a line naming the scope: held, exit 1"
check "$(head -1 "$V/inbox/upstream/node.md") $(git -C "$V" status --porcelain inbox | wc -l | tr -d ' ')" "# Upstream — node — $day (2 lines) 0" "  the vault's inbox file untouched"
check "$([ -e "$P/node-knowledge/dreams/$d2-upstream.md" ] && echo left || echo gone)" gone "  the draft gone: its text is the held file"
check "$(git -C "$P/node-knowledge" show "main:dreams/$d2-upstream-held.md" | grep -c 'Seen in sec')" 1 "  its text kept inside the anchor, committed"
check "$(git -C "$V" show main:log.md | tail -1)" "- $d2 dream --scope node: held — 1 line(s) named the scope, nothing went upstream" "  the log line: held, a count, no word"
check "$(git -C "$V" show main:log.md | grep -c 'sec')" 0 "  nothing of it on the vault's main"
out=$("$S" proof node --day "$d2"); check "$? $(echo "$out" | cut -d' ' -f1)" "3 HELD" "proof: HELD, exit 3"
inbox node "$d2" "A clean line"
"$S" record node --day "$d2" > /dev/null; check $? 0 "rewritten after a hold: recorded, exit 0"
check "$(git -C "$V" show main:log.md | grep -c "$d2 dream --scope node: held") $(git -C "$V" show main:log.md | grep -c "$d2 dream --scope node: 1 P-items")" "0 1" \
  "  the held log line replaced by the clean one"
out=$("$S" proof node --day "$d2"); check "$? $(echo "$out" | cut -d' ' -f1)" "0 LAUNCHED" "  proof: LAUNCHED, not HELD"
d3=2026-01-11; dream node "$d3"; git -C "$P/node-knowledge" add -A; git -C "$P/node-knowledge" commit -qm "d3"
printf '# Upstream — node — %s (1 lines)\n\nU1. Seen in sec — rules/x.md\n' "$d3" > "$V/inbox/upstream/node.md"
git -C "$V" commit -qam "a leak, as a hook's sweep would make it"
out=$("$S" proof node --day 2026-01-18); check "$? $(echo "$out" | cut -d' ' -f1)" "4 LEAKED" "a leak on the vault's main: LEAKED, exit 4, even with no dream that day"
out=$("$S" proof node --day "$d3"); check "$? $(echo "$out" | cut -d' ' -f1)" "4 LEAKED" "an inbox file on the vault's main naming the scope: LEAKED, exit 4"
"$S" record node --day "$d3" > /dev/null 2> "$T/err"; check "$? $(grep -c '^LEAKED' "$T/err") $(git -C "$V" show main:log.md | grep -c "$d3")" "4 1 0" \
  "  record over it: LEAKED, exit 4, never a 'nothing went upstream' log line"
git -C "$V" checkout -q "$today_vault" -- inbox/upstream/node.md; git -C "$V" commit -qam "undo the leak; today's file again"
dream pub "$day"; inbox pub "$day" "open named, as an open scope may"
"$S" record pub > /dev/null; check "$? $("$S" proof pub | cut -d' ' -f1)" "0 LAUNCHED" "an open scope: its names go up, the global dream reads it whole anyway"
check "$(git -C "$P/pub-knowledge" log -1 --format=%s)" "Dream: pub $day (scope-pass record)" "  committed in an anchor with no workflow.json"
"$S" proof node --day 2026-01-01 > /dev/null; check $? 1 "proof of a day with no pass: exit 1"

echo "weekly-run aurora --scope"
lg="$T/logs/$day-aurora-node.log"
out=$("$W" aurora --scope node --dry-run); check $? 0 "--dry-run: exit 0"
echo "$out" | grep -q "already landed today"; check $? 0 "  says the pass already landed today"
echo "$out" | grep -qE '^  2 dream +claude -p "/aurora dream --scope node" from '"$P/node-knowledge"' \(confidential: yes\)'; check $? 0 "  the session from the anchor"
"$W" aurora --scope node; check "$? $(grep -c 'already, before this run' "$lg")" "0 1" "a real run on a landed day: its proof, no session"
check "$("$W" aurora --scope pub --dry-run | grep -c '^  1 login   the one this run starts on (the scope names none)$')" 1 "  a scope with no login: the login line reads plainly"
out=$("$W" aurora --scope bare --dry-run); check "$? $(echo "$out" | grep -c 'refused: scope bare is not ready — dreams/ is not in')" "1 1" "a scope not ready: refused in one line"
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
for r in node pub; do git -C "$P/$r-knowledge" rm -q "dreams/$day.md"; git -C "$P/$r-knowledge" commit -qm "undo today"; done
git -C "$V" rm -q inbox/upstream/node.md inbox/upstream/pub.md; : > "$V/log.md"; git -C "$V" commit -qam "undo today"
rm -f "$lg"
WEEKLY_CLAUDE="$T/fake-claude" "$W" aurora --scope node; check $? 0 "the session records itself: exit 0"
grep -q "^LAUNCHED dreams/$day.md on node-knowledge's main" "$lg"; check $? 0 "  LAUNCHED in its own log"
check "$(tail -1 "$T/sessions.log")" "CONFIG=default SECTIONS=dream --scope node PWD=$P/node-knowledge" "  /aurora dream --scope node, from the anchor, on the login it started on"
lg="$T/logs/$day-aurora-pub.log"
FAKE_STEP=stop WEEKLY_CLAUDE="$T/fake-claude" "$W" aurora --scope pub; check $? 0 "a session that wrote its files and stopped: exit 0"
grep -q "^== the run left its files unrecorded — scope-pass record pub" "$lg"; check $? 0 "  the backstop recorded them"
grep -q "^LAUNCHED" "$lg"; check $? 0 "  LAUNCHED"
git -C "$P/node-knowledge" rm -q "dreams/$day.md"; git -C "$P/node-knowledge" commit -qm "undo today"
git -C "$V" rm -q inbox/upstream/node.md; grep -v 'scope node:' "$V/log.md" > "$T/log.md"; cp "$T/log.md" "$V/log.md"; git -C "$V" commit -qam "undo today"
lg="$T/logs/$day-aurora-node.log"; rm -f "$lg"
FAKE_LINE="Seen in sec" WEEKLY_CLAUDE="$T/fake-claude" "$W" aurora --scope node; check $? 1 "a session whose inbox file names the scope: exit 1"
grep -q "^FAILED scope node $day: its inbox file named the scope, so it was held inside the anchor" "$lg"; check $? 0 "  FAILED, held"
check "$(grep -c 'Seen in sec' "$V/bulletin.md" 2>/dev/null; true)" "0" "  the bulletin never quotes it"
check "$(grep -c 'node-knowledge' "$V/bulletin.md" 2>/dev/null; true)" "0" "  nor names the anchor (posted from the vault, never the anchor's cwd)"

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

echo; [ "$fails" -eq 0 ] && echo "scope-pass: all ok" || { echo "scope-pass: $fails failed"; exit 1; }
