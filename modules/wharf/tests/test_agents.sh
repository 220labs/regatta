#!/usr/bin/env bash
# The architect pair, and sextant's sounder on the same body: one method and output spec, three scopes, one effort since 2026-10-04 (xhigh-design-test D1) (the owner, 2026-10-04: "I want
# to make sure architect and sr-architect are mostly the same, and any differences are
# intentional"). Everything from the `<!-- shared:` marker down must be byte-identical in all three (the pair and sextant's sounder);
# what differs sits above it, each difference with its reason. The same idea as the reviewer pair
# below (from bin/test_review_gate.sh until B5). And the D-item shape the shared body teaches is the one bin/keel
# reads and lints clean. No network, no model.
#   bash modules/wharf/tests/test_agents.sh
set -u
B="$(cd "$(dirname "$0")/.." && pwd)"   # the module (B6)
A="$B/agents"
# keel is a peer (its own module, or an overlay's legacy bin/): found through the core, its cases skipped without it.
KEEL=$(python3 "$B/../regatta/bin/regatta" which keel 2>/dev/null) || KEEL=""   # none: a line on stdout, exit 1
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fails=0
check() { if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3: expected [$2] got [$1]"; fails=$((fails+1)); fi; }

echo "agents: the architect pair has one body"
shared() { awk '/^<!-- shared:/{f=1} f' "$1"; }
check "$(grep -c '^<!-- shared:' "$A/architect.md") $(grep -c '^<!-- shared:' "$A/sr-architect.md")" "1 1" "one shared marker in each"
check "$(shared "$A/architect.md" | wc -l | tr -d ' ')" "$(shared "$A/sr-architect.md" | wc -l | tr -d ' ')" "the shared parts are the same length"
if shared "$A/architect.md" | diff -q - <(shared "$A/sr-architect.md") > /dev/null; then echo "  ok   the shared parts are identical"
else echo "  FAIL the shared parts differ — edit one, copy its shared part to the other:"; shared "$A/architect.md" | diff - <(shared "$A/sr-architect.md") | head -20; fails=$((fails+1)); fi
check "$(shared "$A/architect.md" | wc -l | tr -d ' ' | awk '{print ($1 > 40)}')" "1" "the shared part is the body, not a stub"
check "$(grep -c '^effort: high$' "$A/architect.md")" "1" "architect runs at high"
check "$(grep -c '^effort: high$' "$A/sr-architect.md")" "1" "sr-architect runs at high too (xhigh only as an escalation, docs/xhigh-design-test-2026-10-04.md D1)"
for f in architect sr-architect; do
  check "$(sed -n 's/^effort: //p' "$A/$f.md") $(grep -o '^- \*\*Effort `[a-z]*`' "$A/$f.md" | grep -o '`[a-z]*`' | tr -d '`')" "high high" "$f's body says the effort its frontmatter sets"
done
check "$(grep -h '^model:' "$A/architect.md" "$A/sr-architect.md" | sort -u)" "model: fable" "both on Fable"
check "$(grep -h '^tools:' "$A/architect.md" "$A/sr-architect.md" | sort -u | wc -l | tr -d ' ')" "1" "the same tools"
check "$(grep -c 'sr-architect' "$A/architect.md" | awk '{print ($1 > 0)}') $(grep -c '\[architect\](architect.md)' "$A/sr-architect.md")" "1 1" "each names the other where it says what differs"

# A probe without these runs every user hook against the real repos (sync, the vault commit and
# push, the transcript archive) in auto mode, with Bash and the claude.ai connectors (Gmail send,
# Drive share). Probed 2026-10-04 on 2.1.289 (lessons/claude-code.md): this shape authenticates
# on the Max login with an empty tool list, no MCP server, no hook record, mode default.
check "$(shared "$A/architect.md" | grep -c "^claude -p --restricted --strict-mcp-config --settings '{\"disableAllHooks\":true}' --tools \"\" --model claude-sonnet-5-5")" "1" "the probe shape: restricted, no MCP, every hook off, no tools"
check "$(shared "$A/architect.md" | tr '\n' ' ' | grep -c 'Forbidden: `--add-dir`, any bypass permission mode, `--dangerously-skip-permissions`')" "1" "…and names what a probe may never add"

# The Sounding (the proposer design's S1): every idea is sounded unless `firm:`, and every doc says
# what exists before it builds. keel lint --strict will refuse a doc without them (S2, not built yet).
echo "agents: the stance and the Landscape (Sounding S1)"
body=$(shared "$A/architect.md" | tr '\n' ' ' | tr -s ' ')
check "$(echo "$body" | grep -c '3a\. \*\*The stance — firm, or sounded\*\*.*A brief that starts `firm:` is taken as given')" "1" "3a: firm: fixes a brief, anything else is sounded"
check "$(echo "$body" | grep -c '`Verdict: validated | disproved | evolved | firm — <one sentence>` under `Status:`')" "1" "  …and a sounded doc carries a Verdict line"
check "$(echo "$body" | grep -c 'never used as the axis the options are scored on')" "1" "  …and its idea is a hypothesis, never the scoring axis"
check "$(echo "$body" | grep -c '4a\. \*\*The Landscape — what exists, before any build\*\*')" "1" "4a: the Landscape, before the first options table"
check "$(echo "$body" | grep -c 'At least three candidates linked (a web URL or an absolute path), or one line `Landscape: none, because …`')" "1" "  …three linked candidates, or none with a reason"
check "$(echo "$body" | grep -c 'sparks related "<the brief.s nouns>"')" "1" "  …and the ideas pool asked through sparks related"
check "$(shared "$A/architect.md" | grep -c '^\[Verdict: <validated | disproved | evolved | firm> — <one sentence>\]')" "1" "the skeleton has the Verdict line"
check "$(shared "$A/architect.md" | grep -A1 '^## Landscape — what exists ' | grep -c '^### Fundamental decisions')" "1" "  …and the Landscape heading before the D-items and the first component"

# The third head on the body (the proposer design's D1-B, D4-A): sextant's sounder, for an idea
# outside any repo. Its file sits in the sextant module; a checkout without it skips these cases.
S="$B/../sextant/agents/sounder.md"
echo "agents: the sounder is the third head on the same body"
if [ -f "$S" ]; then
  check "$(grep -c '^<!-- shared:' "$S")" "1" "one shared marker"
  # S4 replaced S1's stopgap link here with one link per module agent file in a config dir's
  # agents/: a sounder.md back in wharf would shadow sextant's file under the same name.
  [ ! -e "$A/sounder.md" ] && [ ! -L "$A/sounder.md" ]; check $? 0 "wharf's agents/ holds no sounder.md (sextant's is linked from its own module)"
  if shared "$A/architect.md" | diff -q - <(shared "$S") > /dev/null; then echo "  ok   its shared part is the architects'"
  else echo "  FAIL the sounder's shared part differs — copy architect.md's shared part to it:"; shared "$A/architect.md" | diff - <(shared "$S") | head -20; fails=$((fails+1)); fi
  check "$(grep -c '^name: sounder$' "$S") $(sed -n 's/^model: //p' "$S") $(sed -n 's/^effort: //p' "$S")" "1 fable high" "named sounder, on Fable at high"
  check "$(grep -h '^tools:' "$A/architect.md" "$S" | sort -u | wc -l | tr -d ' ')" "1" "  …with the architects' tools"
  head_=$(awk '/^<!-- shared:/{exit} {print}' "$S" | tr '\n' ' ' | tr -s ' ')
  check "$(echo "$head_" | grep -c 'Scope: an idea outside any repo\*\* — a venture, a film or content pitch, a marketing project')" "1" "its scope: an idea outside any repo"
  check "$(echo "$head_" | grep -c 'four gates — \*\*pain, wallet, channel, build\*\*')" "1" "  …held to the ventures README's four gates"
  check "$(echo "$head_" | grep -c '## Money flow — .*## Smallest test — ')" "1" "  …with the two components every sounding has"
  check "$(echo "$head_" | grep -c "The Landscape's partner place leads")" "1" "  …and the partners first in its Landscape"
  check "$(echo "$head_" | grep -c 'it stays on its seeded `claude/\*` branch\|It stays on its seeded `claude/\*` branch')" "1" "  …and its doc on its own branch until answered"
  check "$(awk '/^<!-- shared:/{exit} {print}' "$S" | grep -c '/Users/')" "0" "its head names no absolute home path (the body's are the scrub's)"
else echo "  --   sextant's agents/sounder.md not in this checkout: its cases skipped"; fi

echo "agents: the reviewer pair has one body, two efforts"
# From bin/test_review_gate.sh, which went to regatta's wharf module with review-gate (B5); the
# agents stay here until B6 moves them, and their cases with them.
body() { awk 'f>=2{print} /^---$/{f++}' "$1"; }
check "$(body "$A/reviewer.md" | shasum)" "$(body "$A/reviewer-high.md" | shasum)" "reviewer-high has reviewer's body"
check "$(grep -c '^effort: high$' "$A/reviewer-high.md")" "1" "reviewer-high runs at high"
check "$(grep -c '^effort: xhigh$' "$A/reviewer.md")" "1" "reviewer runs at xhigh"
check "$(grep -c '^model: opus$' "$A/code-reviewer.md")" "1" "code-reviewer pinned to Opus"
check "$(ls "$A" | grep -c code-reviewer-high)" "0" "no code-reviewer-high: the level in args sets the effort"

if [ -n "$KEEL" ]; then
echo "agents: the D-item shape they teach is the one memo reads"
{ echo "# Example"; echo; echo 'Written by `architect` (Fable 5.1, `high`) on 2026-10-04 for "a test".'; echo; echo "## Decisions"; echo
  shared "$A/architect.md" | awk '/^ *```$/{n++; next} n%2==1' | sed -n '/D3 —/,$p' | sed 's/^    //'
  echo "---"; echo; echo "## Open feedback"; } > "$T/shape.md"
check "$(python3 "$KEEL" parse "$T/shape.md" | python3 -c 'import json,sys; i=json.load(sys.stdin)["items"]; print(len(i), i[0]["id"], [o[0] for o in i[0]["options"]], i[0]["recommended"], repr(i[0]["answer"]), i[0]["shape"])')" \
  "1 D3 ['A', 'B', 'C'] B '' new" "the example parses: three options, Recommended B, an empty answer"
# …but for its placeholder `Reversible: yes|no`, which keel lint warns on until the architect picks (the Keel, 2026-10-15)
check "$(python3 "$KEEL" lint "$T/shape.md")" "$T/shape.md: warning: D3 (line 7): no \`Reversible: yes|no\` line — no default can ever take it (yolo, the stand sweep); mark it above \`➤ Recommended:\`" "…and lints clean (bullets, no pre-fill) but for the placeholder Reversible mark"
check "$(python3 "$KEEL" parse "$T/shape.md" | python3 -c 'import json,sys; print(json.load(sys.stdin)["items"][0]["reversible"])')" "None" \
  "…and its Reversible: mark is the placeholder, unmarked until the architect picks (E12)"
else echo "  --   keel not installed: the D-item shape cases skipped"; fi
check "$(shared "$A/architect.md" | tr '\n' ' ' | grep -c '`no` for anything physical, money, a new *dependency or a deletion')" "1" "…and says what is never reversible"

echo
if [ "$fails" = 0 ]; then echo "all green"; else echo "$fails failing"; exit 1; fi
