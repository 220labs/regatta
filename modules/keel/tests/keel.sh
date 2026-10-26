#!/usr/bin/env bash
# Tests for bin/keel — every decision shape found in the repos, the form page and its
# merge, list, url, link and pull. No network (a local bare repo stands in for GitHub), no model.
#                                                          bash modules/keel/tests/keel.sh
set -u
T=$(mktemp -d)
# before any case moves HOME: a scratch config dir, the owner Sam (tests/config.sh)
. "$(dirname "$0")/config.sh"; keel_config "$T/config"
B="$(cd "$(dirname "$0")/../bin" && pwd)"
# Peers in other modules, through the core's tool() (C2): atlas's docs-index, wharf's hooks/
# (branches.py). On the Macs they resolve into the overlay until those modules move.
peer() { python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import find_core; sys.path.insert(0, find_core.hooks()); import common; print(common.tool(sys.argv[2]) or "")' "$B/../lib" "$1"; }
DI=$(peer docs-index); WH=$(dirname "$(peer branches.py)")
export MEMO_STATE_DIR="$T/state"   # a form Save logs a touch (memo status); never into ~/.local/state
# Mermaid is fetched on a diagram page's first build (bin/keel, MERMAID_URLS): never here. The cache
# is the suite's own, and the cases that fetch name a file:// stand-in (KEEL_MERMAID_URL).
export KEEL_CACHE_DIR="$T/keel-cache" KEEL_MERMAID_FETCH=0
# `keel line` starts `memo serve` detached; each registers in $MEMO_STATE_DIR/serve — stop them all
reap() { for f in "$T"/state/serve/*.json; do [ -f "$f" ] && kill "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["pid"])' "$f")" 2>/dev/null; done; }
# Nothing reaches the real spacesheep: `keel line` mirrors every doc it hands over, and with the
# CLI and a key on this Mac a fixture became a real page (2026-10-07, this suite's first run of
# `line`). Empty MEMO_SHEEP_BIN = no CLI, no fallback; the sheep cases set a stub per call.
export MEMO_SHEEP_BIN="" MEMO_SHEEP_STATE="$T/sheep-state"
# The spacesheep mirror's status file lives in the CLI's config dir: a mirror running on this Mac
# would turn every expected space link into localhost (bin/sheep's local_url). The mirror cases
# write their own mirror.json here.
export SPACESHEEP_CONFIG_DIR="$T/ss-config"
# An unattended /finish or dispatch build runs this suite with CLAUDE_UNATTENDED set, and `line`
# then owes no form, so ten cases failed there and nowhere else (2026-10-09). The cases that want
# it set it per call. CLAUDE_CODE_ENTRYPOINT=sdk-cli (a Remote Control session running the suite)
# keeps every link https the same way, so the mirror's cases would fail there (review, 2026-10-16).
unset CLAUDE_UNATTENDED CLAUDE_CODE_ENTRYPOINT
trap 'reap; rm -rf "$T"' EXIT
fails=0
# BSD and GNU sed disagree on `-i ''` (GNU takes '' as the script and the real script as a file name); `-i.bak` and a rm work on both.
sedi() { local f="${!#}"; sed -i.bak "$@" && rm -f "$f.bak"; }
check() { if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3: expected [$2] got [$1]"; fails=$((fails+1)); fi; }
has()   { if grep -qF -- "$2" "$1"; then echo "  ok   $3"; else echo "  FAIL $3: missing [$2]"; fails=$((fails+1)); fi; }
lacks() { if grep -qF -- "$2" "$1"; then echo "  FAIL $3: found [$2]"; fails=$((fails+1)); else echo "  ok   $3"; fi; }

cat > "$T/memo.md" <<'EOF'
# Repo sync — design (2026-09-22)

Status: answered. A `<script>alert(1)</script>` in prose must never run.

## 1. Findings

| Cut | Top | Share |
| --- | --- | --- |
| Model | Opus $983 | 67% |

**F1 — Not a decision.** Context is the driver.

## 5. Decisions

Legend: D = decision. Answer inline after ➤; the recommendation is pre-filled.

- **D1 — Keep `ExitWorktree` at the end.** Moves the transcript back.
  Second body line.
  ➤ Answer: yes.

- **D2 — Naming convention via `/rename`.**
  ➤ Answer: yes, but only where a session outlives one sitting — not for
  two-minute questions.

**D3 — Fast-forward `main` at session start?** One paragraph of body.

More body after a blank line.

➤ Answer: yes.

D4 — **Own script, no ccusage.** ➤ Answer: own script.

**D5. Archive subagent transcripts.** Extend the hook.

➤ Answer: yes.

- **D6 — No answer line yet.** Body only.

```
- **D9 — inside a fence, not an item.**
➤ Answer: no.
```

## 6. Open

Open feedback goes below this line.

---
EOF

echo "parse"
"$B/keel" parse "$T/memo.md" > "$T/parse.json"
py() { python3 -c "import json,sys; d=json.load(open('$T/parse.json')); $1"; }
check "$(py 'print(len(d["items"]))')" "6" "six decisions, the fenced one skipped"
check "$(py 'print([i["id"] for i in d["items"]])')" "['D1', 'D2', 'D3', 'D4', 'D5', 'D6']" "ids in order"
check "$(py 'print(d["items"][0]["title"])')" 'Keep `ExitWorktree` at the end.' "D1 title from the bold span"
check "$(py 'print(d["items"][0]["body"])')" $'Moves the transcript back.\nSecond body line.' "D1 body: inline + continuation"
check "$(py 'print(d["items"][1]["answer"])')" "yes, but only where a session outlives one sitting — not for two-minute questions." "D2 answer joins its wrapped line"
check "$(py 'print(d["items"][2]["body"])')" $'One paragraph of body.\n\nMore body after a blank line.' "D3 body spans a blank line"
check "$(py 'print(d["items"][3]["title"], "|", d["items"][3]["answer"])')" "Own script, no ccusage. | own script." "D4: title after the dash, answer on the same line"
check "$(py 'print(d["items"][4]["title"])')" "Archive subagent transcripts." "D5: dot separator"
check "$(py 'print(d["items"][5]["answer"])')" "None" "D6: no answer line"
check "$(py 'print(d["feedback_line"])')" "45" "open-feedback line found (0-based)"

echo "build (--form)"
"$B/keel" build "$T/memo.md" -o "$T/page.html" > "$T/build.out"
has "$T/build.out" "6 decisions" "build reports the count"
has "$T/page.html" "<title>Repo sync — design (2026-09-22)</title>" "title from the H1"
has "$T/page.html" 'id="ans-D1"' "a field per decision"
has "$T/page.html" 'id="ans-D6"' "…including the one with no answer line"
has "$T/page.html" '&lt;script&gt;alert(1)&lt;/script&gt;' "prose HTML is escaped"
lacks "$T/page.html" "<script>alert(1)" "…and never live"
has "$T/page.html" "<th>Cut</th>" "tables render"
has "$T/page.html" "<strong>F1 — Not a decision.</strong>" "findings stay prose"
lacks "$T/page.html" 'id="ans-D9"' "fenced example is not a field"
has "$T/page.html" '"slug": "repo-sync-design-2026-09-22"' "store key from the title"
lacks "$T/page.html" "Open feedback goes below" "the feedback marker line is not rendered"
check "$(grep -c 'window.claude' "$T/page.html")" "1" "the page reaches the store through claude.use only"

echo "merge (--form) — store document"
cat > "$T/answers.json" <<'EOF'
{"data": {"items": {"D1": "yes.", "D2": "no, rename every session.", "D3": "yes.", "D4": "own script.", "D5": "yes.", "D6": "later.", "D7": "ignored"},
          "feedback": "Ship it this week.", "savedAt": "2026-09-23T06:00:00Z", "version": 3}}
EOF
"$B/keel" merge "$T/memo.md" "$T/answers.json" > "$T/merged.md" 2> "$T/merge.err"
has "$T/merge.err" "changed: D2, D6" "only the changed answers are named"
has "$T/merge.err" "unchanged: D1, D3, D4, D5" "unchanged ones listed"
has "$T/merge.err" "unknown ids ignored: D7" "an id the memo lacks is reported, not written"
has "$T/merged.md" "  ➤ Answer: no, rename every session." "D2 rewritten with its indent kept"
lacks "$T/merged.md" "two-minute questions." "…and the old wrapped continuation removed"
has "$T/merged.md" "- **D6 — No answer line yet.** Body only." "D6 body intact"
check "$(grep -A1 'D6 — No answer' "$T/merged.md" | tail -1)" "  ➤ Answer: later." "D6 gets an answer line, indented under its bullet"
has "$T/merged.md" "D4 — **Own script, no ccusage.** ➤ Answer: own script." "D4 untouched"
check "$(grep -c '➤ Answer: no\.$' "$T/merged.md")" "1" "the fenced example is untouched"
has "$T/merged.md" "Open feedback goes below this line." "feedback marker kept"
check "$(grep -v '^$' "$T/merged.md" | tail -1)" "**Sam, $(date +%F):** Ship it this week." "feedback is the last text, dated"
check "$(grep -v '^$' "$T/merged.md" | tail -2 | head -1)" "---" "…below the rule that follows the marker"
check "$(grep -c 'Ship it this week' "$T/merged.md")" "1" "appended once"

echo "merge (--form) — copied text, in place"
cp "$T/memo.md" "$T/memo2.md"
printf 'D1: yes.\nD3: no, keep it manual.\nFeedback: fine\nsecond line\n' | "$B/keel" merge "$T/memo2.md" - --write > "$T/w.out"
has "$T/w.out" "changed: D3; unchanged: D1; feedback: added" "text form parsed and written"
has "$T/memo2.md" "➤ Answer: no, keep it manual." "D3 rewritten in place"
has "$T/memo2.md" "**Sam, $(date +%F):** fine" "feedback line"

echo "merge (--form) — nothing to do leaves the file byte-identical"
cp "$T/memo.md" "$T/memo3.md"
printf '{"items": {"D1": "yes."}, "feedback": ""}' > "$T/same.json"
"$B/keel" merge "$T/memo3.md" "$T/same.json" --write > /dev/null
check "$(cmp -s "$T/memo.md" "$T/memo3.md" && echo same)" "same" "no-op merge changes nothing"

echo "parse — prose that starts with D<n>., and the memo's own replies (pipeline, 2026-09-30)"
cat > "$T/replied.md" <<'EOF'
# Runner service

A 4K render during a recording is the one collision worth a rule:
D2.

Prose again, wrapped so a line starts
D3: with a colon.
D20**: a closing bold from the line above.
3. D1–D3 are still open, a range.

## Decisions

**D1 — Land the retime branch first.** One runner file.
➤ Answer: yes; land it through its PR.
> **Done.** Accepted 2026-09-30. E-1 unchanged.
> Moved to Drive per your open feedback.

**D2 — The queue pauses for music.** Only for the DAW.
➤ Answer: yes, including the brake.
this is OK for now, but we need this configurable.
> **Done.** Accepted. One change of place
> (`W/PAUSE.studio`), not of meaning.

**D3. Jobs travel through the NAS.** Never by ssh.
➤ Answer: the NAS.

**D4 — D2, revisited.** A title may start with another id.
➤ Answer: **Yes** — the recommendation.
> Sam (2026-09-21): No, later.

## Open feedback
EOF
"$B/keel" parse "$T/replied.md" > "$T/parse.json"
check "$(py 'print([i["id"] for i in d["items"]])')" "['D1', 'D2', 'D3', 'D4']" "a wrapped 'D2.', 'D3:' or 'D20**:' line, or a range 'D1–D3', is prose, not a decision"
check "$(py 'print(d["items"][1]["title"])')" "The queue pauses for music." "D2 is the real one"
check "$(py 'print(d["items"][0]["answer"])')" "yes; land it through its PR." "an answer stops at its > **Done.** reply"
check "$(py 'print(d["items"][1]["answer"])')" "yes, including the brake. this is OK for now, but we need this configurable." "…keeping Sam's plain note under it"
check "$(py 'print(d["items"][3]["title"])')" "D2, revisited." "a title that starts with another id is not a range"
check "$(py 'print(d["items"][3]["answer"])')" "**Yes** — the recommendation. > Sam (2026-09-21): No, later." "an older '> Sam (date):' answer stays part of the answer"
check "$(py 'print(d["feedback_line"])')" "30" "a reply that mentions open feedback is not the feedback marker"
printf '{"items": {"D1": "no, build first.", "D2": "yes, including the brake. this is OK for now, but we need this configurable."}}' > "$T/rep.json"
"$B/keel" merge "$T/replied.md" "$T/rep.json" > "$T/replied.out" 2> "$T/replied.err"
has "$T/replied.err" "changed: D1; unchanged: D2" "merge sees the note as part of D2's answer"
check "$(grep -A1 '➤ Answer: no, build first.' "$T/replied.out" | tail -1)" "> **Done.** Accepted 2026-09-30. E-1 unchanged." "merge rewrites the answer and keeps the reply below it"
check "$(grep -cF 'Done.** Accepted 2026-09-30' "$T/replied.out")" "1" "…once"

printf '# Twice\n\n**D1 — First.** ➤ Answer: yes.\n\n**D1 — Again.** ➤ Answer: no.\n' > "$T/dup.md"
"$B/keel" parse "$T/dup.md" > /dev/null 2> "$T/dup.err"; rc=$?
check "$rc" "1" "one id twice exits non-zero"
has "$T/dup.err" "D1 appears twice, at lines 3 and 5" "…naming both lines"

echo "list"
mkdir -p "$T/root/repo-a/docs" "$T/root/films/repo-b/docs" "$T/root/repo-a/.claude/worktrees/x/docs"
cp "$T/memo.md" "$T/root/repo-a/docs/one.md"
cp "$T/memo.md" "$T/root/repo-a/.claude/worktrees/x/docs/wt.md"
cp "$T/memo.md" "$T/root/repo-a/.claude/worktrees/x/docs/one.md"
printf '# Plain notes\n\nNo decisions here.\n' > "$T/root/repo-a/docs/notes.md"
mkdir -p "$T/root/repo-c/.git" "$T/root/repo-a/skills"
printf '# Retime plan\n\n**D1 — Retime.** ➤ Answer: yes.\n' > "$T/root/repo-c/retime.md"
printf '# Not a memo\n\n**D1 — Inside a folder.** ➤ Answer: yes.\n' > "$T/root/repo-a/skills/x.md"
mkdir -p "$T/root/repo-a/docs/record"
printf '# Moved record\n\n**D1 — Kept.** ➤ Answer: yes.\n' > "$T/root/repo-a/docs/record/rec-2026-09-01.md"
cp "$T/root/repo-a/docs/record/rec-2026-09-01.md" "$T/root/repo-a/.claude/worktrees/x/docs/rec-2026-09-01.md"  # forked before the move
sleep 1
printf '# Poem plan\n\n**D1 — Print it.** ➤ Answer: yes.\n' > "$T/root/films/repo-b/docs/plan.md"
cp "$T/dup.md" "$T/root/repo-a/docs/dup.md"
"$B/keel" list --root "$T/root" > "$T/list.out" 2> "$T/list.err"
check "$(grep -c '^ *[0-9]' "$T/list.out")" "5" "five memos: plain notes, a non-repo folder, a duplicate id, and a worktree copy of a landed memo, skipped"
has "$T/list.out" "Moved record" "a record moved to docs/record/ is listed (docs map D2 (b))"
check "$(grep -c 'Moved record' "$T/list.out")" "1" "…once: a worktree forked before the move is not a second, unlanded copy"
has "$T/list.err" "dup.md: D1 appears twice" "list names the memo it skipped for a duplicate id"
has "$T/list.out" "Retime plan" "a memo at a repo's top level is listed"
lacks "$T/list.out" "Not a memo" "…but not any folder's *.md"
has "$T/list.out" "repo-a@x" "a memo only in a worktree (not landed yet) is listed"
check "$(grep -c 'worktrees/x/docs/one.md' "$T/list.out")" "0" "…but not one whose checkout has it"
has "$T/list.out" "films/repo-b" "two-level repos found"
has "$T/list.out" "(6 decisions, 1 unanswered)" "counts per memo"
mkdir -p "$T/eroot/repo-e/.git" "$T/eroot/repo-e/.claude/worktrees/embark-d/docs/embark" "$T/eroot/repo-e/docs/embark"
printf '# Embark sitting\n\n**D1 — Sit.** ➤ Answer: yes.\n' > "$T/eroot/repo-e/.claude/worktrees/embark-d/docs/embark/embark-d.md"
printf '# Landed sitting\n\n**D1 — Sat.** ➤ Answer: yes.\n' > "$T/eroot/repo-e/docs/embark/embark-c.md"
"$B/keel" list --root "$T/eroot" > "$T/elist.out" 2>&1
has "$T/elist.out" "repo-e@embark-d" "a docs/embark/ memo only on its branch's worktree is listed (helm cards the sitting through it)"
has "$T/elist.out" "Landed sitting" "…and one landed in docs/embark/"
check "$("$B/keel" list --root "$T/root" --json 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["title"])')" "Poem plan" "json form, newest first"

echo "open"
O="$T/oroot"; mkdir -p "$O/repo-a/docs/record" "$O/repo-a/.claude/worktrees/x/docs" "$O/films/repo-b/docs"
printf '# Merge author leak\n\nbody, no Status line\n' > "$O/repo-a/docs/postmortem-2026-10-10-merge-author.md"
printf '# Post-mortem: resolved one\n\nStatus: resolved 2026-10-10 — gate test green, hard push read back\n' > "$O/repo-a/docs/b-post-mortem.md"
printf '# Post-mortem: archived\n\nno Status line, but archived\n' > "$O/repo-a/docs/record/c-postmortem.md"
printf '# Postmortem: the heading names it\n\n**Status:** open — Sam owes the hard push\n' > "$O/repo-a/docs/heading.md"
printf '# Pick one\n\n**D1 — A.** ➤ Answer: yes.\n\n**D2 — B.**\n\n➤ Answer:\n' > "$O/repo-a/docs/decide.md"
printf '# All answered\n\n**D1 — A.** ➤ Answer: yes.\n' > "$O/repo-a/docs/done.md"
printf '# Design\n\nStatus: open — waits on Alex\n' > "$O/films/repo-b/docs/design.md"
printf '# Design, closed\n\nStatus: shipped\n' > "$O/films/repo-b/docs/shipped.md"
cp "$O/repo-a/docs/postmortem-2026-10-10-merge-author.md" "$O/repo-a/.claude/worktrees/x/docs/"  # the checkout has it: no second row
printf '# Postmortem: only in a branch\n' > "$O/repo-a/.claude/worktrees/x/docs/wt-postmortem.md"
mkdir -p "$O/repo-a/.git"; printf '# repo-a\n\nD3-C). Prose that parse reads as a D-item.\nD31-B, and more prose.\n' > "$O/repo-a/AGENTS.md"
"$B/keel" open --root "$O" > "$T/open.out" 2> "$T/open.err"
"$B/keel" open --root "$O" --json > "$T/open.json" 2>/dev/null
oj() { python3 -c "import json; d=json.load(open('$T/open.json')); $1"; }
check "$(oj 'print(len(d))')" "6" "six rows: archived, answered, other Status and AGENTS.md (option references D3-C, D31-B are no D-items) skipped, and the worktree copy of a doc the checkout has"
check "$(oj 'print([r["kind"] for r in d])')" "['post-mortem', 'post-mortem', 'post-mortem', 'post-mortem', 'decisions', 'open']" "post-mortems first, then decisions, then open docs"
check "$(oj 'print(sorted(r["what"] for r in d if r["kind"] == "post-mortem"))')" "['Sam owes the hard push', 'no Status line', 'no Status line', 'resolved, not archived — git mv to docs/record/']" "a post-mortem with no Status line says so; an open one shows its text; a resolved one outside docs/record/ says so"
check "$(oj 'print([r["what"] for r in d if r["kind"] != "post-mortem"])')" "['1 of 2 unanswered', 'waits on Alex']" "decisions: N of M unanswered; open doc: the text after open"
check "$(oj 'print([r["repo"] for r in d if "wt-" in r["path"]])')" "['repo-a@x']" "a post-mortem only in a worktree is listed, labelled as list does"
check "$(oj 'print(sorted(r["repo"] for r in d if r["kind"] == "open"))')" "['films/repo-b']" "two-level repos found"
lacks "$T/open.out" "c-postmortem" "nothing from docs/record/"
has "$T/open.out" "$O/films/repo-b/docs/design.md" "the absolute path follows each row"
has "$T/open.out" "resolved but still outside it is listed too" "a legend at the end, naming the not-archived rule"
check "$(grep -c '^ *[0-9]' "$T/open.out")" "6" "text form: one numbered row per doc"
printf '# Design\n\nStatus: resolved 2026-10-10 — done\n' > "$O/films/repo-b/docs/design.md"
check "$("$B/keel" open --root "$O" --json | python3 -c 'import json,sys; print(sum(r["kind"] == "open" for r in json.load(sys.stdin)))')" "0" "a Status that is not open drops the doc"
check "$("$B/keel" open --root "$T/nothing")" "nothing open under $T/nothing" "an empty root says so"

# Repos deeper than two levels (films/productions/<group>/<slug> hid 220-film's post-mortem until 2026-10-10)
Dp="$T/deep"; mkdir -p "$Dp/a/b/c/repo/.git" "$Dp/a/b/c/repo/docs" "$Dp/x/y/z/gitfile/docs" "$Dp/x/node_modules/m/docs" "$Dp/x/node_modules/m/.git" "$Dp/a/b/c/d/five/.git" "$Dp/a/b/c/d/five/docs"
printf '# Post-mortem: deep\n\nno Status line\n' > "$Dp/a/b/c/repo/docs/postmortem-x.md"
printf '# Plan\n\n**D1 — Go?**\n\n➤ Answer:\n' > "$Dp/x/y/z/gitfile/docs/plan.md"
echo "gitdir: elsewhere" > "$Dp/x/y/z/gitfile/.git"  # a worktree or submodule: .git is a file
printf '# Post-mortem: vendored\n' > "$Dp/x/node_modules/m/docs/postmortem-v.md"
printf '# Post-mortem: depth 5\n' > "$Dp/a/b/c/d/five/docs/postmortem-t.md"
check "$("$B/keel" open --root "$Dp" --json | python3 -c 'import json,sys; print(sorted(r["repo"] for r in json.load(sys.stdin)))')" "['a/b/c/repo', 'x/y/z/gitfile']" "open finds repos 3-4 levels deep (.git a dir or a file), not a real repo under node_modules, nor one at depth 5 beside the depth-4 one"
check "$("$B/keel" list --root "$Dp" --json | python3 -c 'import json,sys; print([r["repo"] for r in json.load(sys.stdin)])')" "['x/y/z/gitfile']" "list gains them too"
"$B/keel" open --root "$Dp" > "$T/deep.out"; "$B/keel" list --root "$Dp" > "$T/deep-list.out" 2>/dev/null
has "$T/deep.out" " c/repo " "open's repo column shows the last two segments (a/b/c/repo → c/repo)"
lacks "$T/deep.out" "a/b/c/repo " "…not the whole path"
has "$T/deep-list.out" " z/gitfile " "list's repo column the same"
lacks "$T/deep-list.out" "x/y/z/gitfile " "…not the whole path"

echo "open — review fixes of 2026-10-10"
# the live case: 220-film's critic doc has D3 twice; it was dropped, and with it nine empty answers
Rv="$T/review"; mkdir -p "$Rv/r/.git" "$Rv/r/docs" "$Rv/r/.claude/worktrees/w1/docs" "$Rv/r/.claude/worktrees/w2/docs"
printf '# Critic\n\n**D1 — A.**\n\n➤ Answer:\n\n**D1 — A again.**\n\n➤ Answer:\n' > "$Rv/r/docs/critic.md"
printf '# Numbered\n\n1. **D1 — Pick a name.** Body, no answer line yet.\n' > "$Rv/r/docs/numbered.md"
printf '# Sourced\n\nStatus: open-sourced 2026-10-01\n' > "$Rv/r/docs/sourced.md"
printf '# Opened\n\nStatus: opened by Sam\n' > "$Rv/r/docs/opened.md"
printf '# Bold\n\nStatus: **open** — waits on Alex\n' > "$Rv/r/docs/bold.md"
printf '# Dated\n\n**Status (2026-10-10):** open — dated label\n' > "$Rv/r/docs/dated.md"
printf '# Post-mortem: dated resolved\n\n**Status (2026-10-10):** resolved 2026-10-10 — read back\n' > "$Rv/r/docs/dated-postmortem.md"
printf '# Post-mortem: resolved with a question\n\nStatus: resolved 2026-10-10 — done\n\n**D1 — Still asked?**\n\n➤ Answer:\n' > "$Rv/r/docs/asked-postmortem.md"
printf '# Branch only\n\nStatus: open — in two worktrees\n' > "$Rv/r/.claude/worktrees/w1/docs/wt.md"
cp "$Rv/r/.claude/worktrees/w1/docs/wt.md" "$Rv/r/.claude/worktrees/w2/docs/wt.md"
touch -t 202601010000 "$Rv/r/.claude/worktrees/w1/docs/wt.md"
ln -s "$Rv/nowhere" "$Rv/r/docs/dangling.md"; ln -s "$Rv/nowhere" "$Rv/r/.claude/worktrees/w2/docs/dangling-wt.md"
"$B/keel" open --root "$Rv" --json > "$T/rv.json" 2>"$T/rv.err"; check "$?" "0" "a dangling file (also in a worktree) skips that file, the scan goes on"
rj() { python3 -c "import json; d=json.load(open('$T/rv.json')); $1"; }
check "$(rj 'print([r["what"] for r in d if r["path"].endswith("critic.md")])')" "['unparseable — D1 appears twice, at lines 3 and 7 — renumber or reword one']" "a doc that will not parse is a decisions row, not dropped"
check "$(rj 'print([r["kind"] for r in d if r["path"].endswith("critic.md")])')" "['decisions']" "…of kind decisions"
check "$(rj 'print([r["what"] for r in d if r["path"].endswith("numbered.md")])')" "['1 of 1 unanswered']" "a numbered \`1. **D1 — …**\` item with no answer line is seen by the pre-filter"
check "$(rj 'print(sorted(r["what"] for r in d if r["kind"] == "open"))')" "['dated label', 'in two worktrees', 'waits on Alex']" "open: a word of its own (open-sourced, opened are not), \`**open**\` stripped, a dated label read; one row for a doc in two worktrees"
check "$(rj 'print([r["repo"] for r in d if r["path"].endswith("wt.md")])')" "['r@w2']" "…the newest worktree copy"
check "$(rj 'print(sorted((r["kind"], r["what"]) for r in d if "postmortem" in r["path"]))')" "[('decisions', '1 of 1 unanswered'), ('post-mortem', 'resolved, not archived — git mv to docs/record/'), ('post-mortem', 'resolved, not archived — git mv to docs/record/')]" "a resolved post-mortem outside docs/record/ is a row; one with an unanswered D-item is a decisions row too; a dated Status label reads"
# one list row per doc, whichever worktree
check "$("$B/keel" list --root "$Rv" --json 2>/dev/null | python3 -c 'import json,sys; print(sorted(r["decisions"] for r in json.load(sys.stdin)))')" "[1, 1]" "list: the numbered and the resolved-with-question docs; the critic (unparseable) is named on stderr, not listed"
printf '# Notes\n\nD3-C). A reference to option C of D3.\nD31-B, another.\n' > "$T/ref.md"
check "$("$B/keel" parse "$T/ref.md" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["items"]))')" "0" "an option reference (D3-C, D31-B) is no D-item"
# a group folder with its own docs/ and no .git still has repos below it
Gp="$T/group"; mkdir -p "$Gp/group/docs" "$Gp/group/repo/.git" "$Gp/group/repo/docs"
printf '# G\n\nStatus: open — group docs\n' > "$Gp/group/docs/g.md"; printf '# R\n\nStatus: open — repo docs\n' > "$Gp/group/repo/docs/r.md"
check "$("$B/keel" open --root "$Gp" --json | python3 -c 'import json,sys; print(sorted(r["repo"] for r in json.load(sys.stdin)))')" "['group', 'group/repo']" "a docs/ folder without .git does not shadow the repos below it"
# the repo column is wide enough for a long worktree name
Lb="$T/long"; mkdir -p "$Lb/p/q/r/repo/.git" "$Lb/p/q/r/repo/.claude/worktrees/averyverylongworktreename/docs"
printf '# L\n\nStatus: open — long\n' > "$Lb/p/q/r/repo/.claude/worktrees/averyverylongworktreename/docs/l.md"
has <("$B/keel" open --root "$Lb") "r/repo@averyverylongworktreename " "the repo column is widened to fit, never cut"

echo "link + pull — a bare repo plays GitHub"
# origin's URL reads as github.com (what locate() parses); insteadOf sends the traffic to the bare repo.
G="$T/git"; mkdir -p "$G"
git init -q --bare "$G/gh.git"
URL=https://github.com/owner/repo.git
gitc() { git -C "$1" -c user.name=t -c user.email=t@t -c "url.$G/gh.git.insteadOf=$URL" "${@:2}"; }
mkclone() { git clone -q "$G/gh.git" "$1" 2>/dev/null; git -C "$1" remote set-url origin "$URL"; }
mkclone "$G/here"
gitc "$G/here" checkout -q -b claude/x
mkdir -p "$G/here/docs"; cp "$T/memo.md" "$G/here/docs/m.md"
gitc "$G/here" add docs/m.md; gitc "$G/here" commit -qm memo
M="$G/here/docs/m.md"
run() { (export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0="url.$G/gh.git.insteadOf" GIT_CONFIG_VALUE_0="$URL" \
          GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t; "$B/keel" "$@"); }

# `line` (since 2026-10-07; `url` is its old name): one line on stdout, why a part is missing on stderr
MP="$(cd "$(dirname "$M")" && pwd -P)/m.md"
BLOB=https://github.com/owner/repo/blob/claude/x/docs/m.md
run line "$M" > "$T/u1.out" 2> "$T/u1.err"; rc=$?
check "$(wc -l < "$T/u1.out" | tr -d ' ')" "1" "line: exactly one line on stdout"
check "$(sed -E 's#^\[course\]\(http://127\.0\.0\.1:[0-9]+/[A-Za-z0-9_-]+/\) — #FORM — #' "$T/u1.out")" "FORM — [m.md]($MP#L1)" "line: the form, then the file name linked absolute with #L1"
check "$rc" "1" "line: exit 1 while GitHub lacks the branch — the github part is owed (idea-redaction, 2026-10-04)"
has "$T/u1.err" "keel line: no github — docs/m.md is not on GitHub yet" "…and stderr says why"
lacks "$T/u1.out" "github.com" "…printing no GitHub link at all"
has "$T/u1.err" "the form is memo serve's (no page)" "…the form is memo serve's where the doc has no page (no CLI here; 2026-10-14)"
lacks "$T/u1.err" "keel line: no space" "…and no space is owed with D-items: the page would be the form"
FORM=$(sed -E 's#^\[course\]\(([^)]*)\).*#\1#' "$T/u1.out")
check "$(curl -s -o /dev/null -w '%{http_code}' "$FORM")" "200" "line started a live form for the doc"
# a serve killed by a signal leaves its registry file; a dead pid's file is dropped, and an entry
# past its deadline is not reused (review 2026-10-09)
python3 -c 'import json, sys, time; json.dump({"path": sys.argv[2], "url": "http://127.0.0.1:9/dead/", "pid": 99999999, "started": time.time() + 9, "deadline": time.time() + 999}, open(sys.argv[1], "w"))' "$T/state/serve/99999999.json" "$MP"
python3 -c 'import json, os, sys, time; json.dump({"path": sys.argv[2], "url": "http://127.0.0.1:9/old/", "pid": os.getppid(), "started": time.time() + 9, "deadline": time.time() - 1}, open(sys.argv[1], "w"))' "$T/state/serve/1.json" "$MP"
lsv() { python3 -c 'import sys; from importlib.machinery import SourceFileLoader as L; print([e["url"] for e in L("m", sys.argv[1]).load_module().live_serves(sys.argv[2])])' "$B/keel" "$MP"; }
check "$(lsv | grep -c 'dead\|old')" 0 "live_serves: neither a dead pid's entry nor one past its deadline"
check "$([ -f "$T/state/serve/99999999.json" ] && echo kept || echo gone)" "gone" "…and the dead pid's file is removed"
rm -f "$T/state/serve/1.json"
holds() { python3 -c 'import sys; from importlib.machinery import SourceFileLoader as L; m = L("m", sys.argv[1]).load_module(); print(m.origin_holds(sys.argv[2], "claude/x", "docs/m.md", sys.argv[3]))' "$B/keel" "$G/here" "$M"; }
check "$(holds)" "False" "origin_holds (paste-paths): False while GitHub lacks the branch"

run link "$M" > "$T/l1.out" 2>&1; rc=$?
check "$rc" "1" "link: exit 1 for a memo GitHub lacks"
has "$T/l1.out" "not on GitHub yet" "…and says so"
has "$T/l1.out" "push -u origin claude/x" "…with the branch's own push"

gitc "$G/here" push -q -u origin claude/x 2>/dev/null
run url "$M" > "$T/u2.out" 2> "$T/u2.err"; rc=$?
check "$(cat "$T/u2.out")" "[course]($FORM) | [github]($BLOB) — [m.md]($MP#L1)" "url (line's old name): the running form reused, then GitHub's read view, then the file"
check "$rc" "0" "…exit 0: every part owed is there"
lacks "$T/u2.out" "/edit/" "…never the edit page"
check "$(holds)" "True" "origin_holds: True once pushed"
echo "local edit" >> "$M"
run line "$M" > "$T/u3.out" 2> "$T/u3.err"; rc=$?
check "$rc" "0" "line on a claude/* branch: an uncommitted change only ahead of GitHub links, pending the Stop's push"
has "$T/u3.err" "keel line: github pending:" "…and says it is pending"
gitc "$G/here" checkout -q -- docs/m.md
run link "$M" > "$T/l2.out" 2>&1
has "$T/l2.out" "Repo sync — design (2026-09-22) — 6 decisions" "link names the title and the count"
has "$T/l2.out" "| [github]($BLOB) —" "…then the line"

mkclone "$G/web"; gitc "$G/web" checkout -q claude/x
perl -pi -e 's/➤ Answer: own script\./➤ Answer: ccusage after all./' "$G/web/docs/m.md"
gitc "$G/web" commit -qam "Answer D4"; gitc "$G/web" push -q origin claude/x 2>/dev/null
run link "$M" > "$T/l4.out" 2>&1
has "$T/l4.out" "keel line: github GitHub has commits this checkout lacks" "link points at pull when GitHub is ahead"
run url "$M" > "$T/u5.out" 2>&1
has "$T/u5.out" "[github]($BLOB)" "line still links when only GitHub moved (its copy is the newer)"

echo "line_findings — the one reader of the line (the Stop hooks')"
lf() { python3 -c 'import sys; from importlib.machinery import SourceFileLoader as L; m = L("m", sys.argv[1]).load_module(); print(" / ".join(m.line_findings(sys.argv[3], sys.argv[2])) or "ok")' "$B/keel" "$M" "$1"; }
GOOD="$(cat "$T/u2.out")"
check "$(lf "Answer D1–D6 in the doc:"$'\n\n'"$GOOD")" "ok" "the line memo printed passes"
check "$(lf "- $GOOD")" "ok" "…as a bullet too"
check "$(lf $'```\n'"$GOOD"$'\n```')" "no line ends with the file link [m.md]($MP#L1) after [course](…) | [github](…) —" "…but not inside a fence"
check "$(lf "${GOOD/\#L1/}")" "the file link ends #L1 ($MP#L1), so VS Code opens it as text" "no #L1: named"
check "$(lf "${GOOD/\[m.md\]/[docs/m.md]}")" "the file link's text is the file name, m.md" "the link text is the file name"
check "$(lf "[github]($BLOB) — [m.md]($MP#L1)")" "the course link is missing" "no course on a doc with D-items: named"
check "$(lf "[course]($FORM) — [m.md]($MP#L1)")" "the github link is missing" "no github: named"
check "$(lf "[course]($FORM) — [github]($BLOB) [m.md]($MP#L1)")" "the parts go on the file link's line, \` | \` between them and \` — \` before the file link / the course link is missing / the github link is missing" "parts off the chain do not count"
check "$(lf "[github]($BLOB) | [course]($FORM) — [m.md]($MP#L1)")" "the links go course | github | space, each once, then any others" "out of order: named"
check "$(lf "[Form]($FORM) | [github]($BLOB) — [m.md]($MP#L1)")" "the labels are exactly course, github, space (not 'Form') / the course link is missing" "labels exactly"
check "$(lf "[form]($FORM) | [github]($BLOB) — [m.md]($MP#L1)")" "the labels are exactly course, github, space (not 'form') / the course link is missing" "the label before 2026-10-17, form, is named as wrong"
check "$(lf "[course]($FORM) | [github](${BLOB/blob/edit}) — [m.md]($MP#L1)")" "the github link is not this branch's read (blob) view of docs/m.md" "the edit URL is not the github part"
check "$(lf "[course](http://127.0.0.1:1/deadbeef/) | [github]($BLOB) — [m.md]($MP#L1)")" "the course link is not a running memo serve of this doc — memo line prints the form (the doc's page, or a fresh serve where it has none)" "a dead form is named"
check "$(lf "[course]($FORM) | [github]($BLOB) | [artifact](https://claude.ai/a/1) — [m.md]($MP#L1)")" "ok" "another format after the three passes"
check "$(lf "[course]($FORM) | [github]($BLOB) | [space](https://example.com/x) — [m.md]($MP#L1)")" "the space link is not a spacesheep.dev page (https://example.com/x)" "a space link elsewhere is named"
check "$(CLAUDE_UNATTENDED=1 lf "[github]($BLOB) — [m.md]($MP#L1)")" "ok" "an unattended run owes no form where no page can be made"
# a CLI and a key on this Mac: the page is owed, as the form (2026-10-14); unpinned, any page passes
plf() { MEMO_SHEEP_BIN=/bin/echo SPACESHEEP_KEY=k lf "$@"; }
check "$(plf "[course](https://spacesheep.dev/@sam/m) | [github]($BLOB) — [m.md]($MP#L1)")" "ok" "with a page: the page is the form"
check "$(plf "[github]($BLOB) — [m.md]($MP#L1)")" "the course link is missing" "…owed attended too: the page is the form wherever it can be made"
check "$(CLAUDE_UNATTENDED=1 plf "[github]($BLOB) — [m.md]($MP#L1)")" "the course link is missing" "…owed in an unattended run too"
check "$(plf "[course](https://example.com/x) | [github]($BLOB) — [m.md]($MP#L1)")" "the course link is not a spacesheep.dev page (https://example.com/x)" "…and a form link elsewhere is named"
check "$(plf "[course]($FORM) | [github]($BLOB) — [m.md]($MP#L1)")" "the course link is a memo serve form, but this doc has a spacesheep page — the page is the form (memo line prints it once the doc is committed)" "…a memo serve form is refused for a doc that has a page (review 2026-10-16: an uncommitted doc once got one)"

run pull "$M" > "$T/p1.out" 2>&1
has "$T/p1.out" "fast-forwarded claude/x" "pull fast-forwards"
has "$T/p1.out" "D4 → ccusage after all." "…and names the new answer"
has "$T/p1.out" "changed: D4; unchanged: D1, D2, D3, D5, D6; feedback: none" "…and only that one"
run pull "$M" > "$T/p2.out" 2>&1
has "$T/p2.out" "nothing new on GitHub" "a second pull is a no-op"

gitc "$G/web" pull -q 2>/dev/null
perl -pi -e 's/^Open feedback goes below this line\.$/Open feedback goes below this line.\n\nShip it./' "$G/web/docs/m.md"
gitc "$G/web" commit -qam "Feedback"; gitc "$G/web" push -q origin claude/x 2>/dev/null
echo "other" > "$G/here/other.txt"; gitc "$G/here" add other.txt; gitc "$G/here" commit -qm "session work"
run pull "$M" > "$T/p3.out" 2>&1
has "$T/p3.out" "rebased this branch's own commits" "both moved: the session's commit is rebased on top"
has "$T/p3.out" "feedback: changed" "…and the feedback is noticed"
check "$(git -C "$G/here" log --format=%s -1)" "session work" "…which stays last"

gitc "$G/web" pull -q 2>/dev/null
perl -pi -e 's/➤ Answer: own script|➤ Answer: ccusage after all\./➤ Answer: web./' "$G/web/docs/m.md"
gitc "$G/web" commit -qam "web D4"; gitc "$G/web" push -q origin claude/x 2>/dev/null
perl -pi -e 's/➤ Answer: ccusage after all\./➤ Answer: here./' "$M"
gitc "$G/here" commit -qam "here D4"
before=$(git -C "$G/here" rev-parse HEAD)
run line "$M" > "$T/u4.out" 2>&1; rc=$?
check "$rc" "1" "line leaves github out when both sides changed the memo (registrar-access D7, 2026-10-04)"
lacks "$T/u4.out" "[github]" "…printing no link to either copy"
has "$T/u4.out" "the two have split" "…and names it"
has "$T/u4.out" "keel pull" "…with the pull, then the push"
run pull "$M" > "$T/p4.out" 2>&1; rc=$?
check "$rc" "1" "a conflicting pull stops"
has "$T/p4.out" "conflicts" "…and says why"
check "$(git -C "$G/here" rev-parse HEAD)" "$before" "…leaving the branch as it was"
check "$(ls "$(git -C "$G/here" rev-parse --git-dir)" | grep -c rebase-)" "0" "…with no rebase in progress"

gitc "$G/here" reset -q --hard origin/claude/x; gitc "$G/web" pull -q 2>/dev/null
printf '\n**D1 — Again, by mistake.** ➤ Answer: no.\n' >> "$G/web/docs/m.md"
gitc "$G/web" commit -qam "dup"; gitc "$G/web" push -q origin claude/x 2>/dev/null
run pull "$M" > "$T/p5.out" 2>&1; rc=$?
check "$rc" "1" "a pull that brings a duplicate id exits non-zero"
has "$T/p5.out" "fast-forwarded claude/x" "…after saying the branch moved"
has "$T/p5.out" "answers not compared: D1 appears twice" "…and why the answers are not named"

echo "D10 shape — Recommended fixed, the Answer block Sam's"
cat > "$T/d10.md" <<'EOF'
# Answer lines — design

Some context before the list.

| Option | Cost |
| --- | --- |
| Keep | none |

## Decisions

- **D1 — Pick the format.** Two ways to go.
  A — answer on the arrow line
  B — answer in the block under it
  ➤ Recommended: B
  ➤ Answer:


- **D2 — Ship this week?** Plain yes or no.
  - a nested point
  ➤ Recommended: yes, Friday.
  ➤ Answer:
  A - not a letter answer, just words
  and a second line

  > **Done.** Reply, not answer.

- **D3 — Old shape still reads.**
  ➤ Answer: yes, pre-filled.

## Open feedback
EOF
"$B/keel" parse "$T/d10.md" > "$T/parse.json"
check "$(py 'print([i["id"] for i in d["items"]])')" "['D1', 'D2', 'D3']" "three items"
check "$(py 'print(d["items"][0]["recommended"], "|", repr(d["items"][0]["answer"]))')" "B | ''" "D1: Recommended read apart; an empty block is an empty answer"
check "$(py 'print(d["items"][0]["options"])')" "[['A', 'answer on the arrow line'], ['B', 'answer in the block under it']]" "D1: options A and B"
check "$(py 'print(d["items"][0]["body"])')" $'Two ways to go.\nA — answer on the arrow line\nB — answer in the block under it' "D1: body stops at Recommended"
check "$(py 'print(d["items"][1]["answer"])')" $'A - not a letter answer, just words\nand a second line' "D2: the whole block is the answer, lines kept, the reply left out"
check "$(py 'print([i["shape"] for i in d["items"]])')" "['new', 'new', 'old']" "shapes: new, new, old"

echo "D10 shape — the form"
"$B/keel" build "$T/d10.md" -o "$T/d10.html" > /dev/null
has "$T/d10.html" '<span class="k">Recommended</span><strong>B</strong> — answer in the block under it' "Recommended shown read-only, the letter with its option"
check "$(grep -o '<textarea id="ans-D1"[^>]*></textarea>' "$T/d10.html" | wc -l | tr -d ' ')" "1" "D1's answer box is empty"
has "$T/d10.html" '<button type="button" class="opt" data-letter="A">' "options are buttons in a card"
has "$T/d10.html" 'id="take-D1"' "a take-the-recommendation button"
has "$T/d10.html" 'id="acceptall" title="Accept all recommendations">Accept all<span class="more"> recommendations</span>' "one click to agree with everything (D5, 2026-10-04)"
has "$T/d10.html" 'var ACCEPT_ALL = "= recommended (accept all)"' "…marked apart from a per-card take"
has "$T/d10.html" '<textarea id="ans-D3" rows="2">yes, pre-filled.</textarea>' "old shape still pre-filled"
has "$T/d10.html" 'data-at="2" data-q="Some context before the list."' "prose carries its source line"
has "$T/d10.html" 'data-row="Keep"' "a table row carries its first cell"
has "$T/d10.html" 'data-q="- a nested point"' "a nested bullet in a card carries its line"
lacks "$T/d10.html" 'data-q="➤' "no ➤ line is notable"

echo "D10 shape — pull: a two-line answer typed on GitHub"
gitc "$G/here" reset -q --hard origin/claude/x
cp "$T/d10.md" "$G/here/docs/d10.md"; gitc "$G/here" add docs/d10.md; gitc "$G/here" commit -qm "d10 memo"
gitc "$G/here" push -q origin claude/x 2>/dev/null
gitc "$G/web" pull -q 2>/dev/null
perl -0pi -e 's/(➤ Recommended: B\n  ➤ Answer:\n)/$1  A - typed on the phone\n  and a second line\n/' "$G/web/docs/d10.md"
gitc "$G/web" commit -qam "Answer D1 in two lines"; gitc "$G/web" push -q origin claude/x 2>/dev/null
run pull "$G/here/docs/d10.md" > "$T/p6.out" 2>&1; rc=$?
check "$rc" "0" "pull takes in a D10 answer"
has "$T/p6.out" "D1 → A - typed on the phone" "…names D1 with its first line"
has "$T/p6.out" "and a second line" "…and its second"
has "$T/p6.out" "changed: D1; unchanged: D2, D3; feedback: none" "…and only D1, the empty block read as unanswered before"
check "$(git -C "$G/here" show HEAD:docs/d10.md | grep -c 'and a second line')" "2" "…the commit itself on the branch (D1's line beside D2's)"

echo "D10 shape — merge: answers as blocks, notes in place"
cat > "$T/d10.json" <<'EOF'
{"items": {"D1": "A - great idea\nsecond thought", "D2": "A - not a letter answer, just words\nand a second line", "D3": "yes, pre-filled."},
 "comments": [
   {"at": 2, "quote": "Some context before the list.", "text": "Context is thin."},
   {"at": 6, "row": "Keep", "quote": "| Keep | none |", "text": "cheap"},
   {"at": 10, "quote": "- **D1 — Pick the format.** Two ways to go.", "text": "Good framing."},
   {"at": 18, "quote": "- a nested point", "text": "nested note"},
   {"at": 99, "quote": "a line long gone", "text": "orphan"}],
 "feedback": ""}
EOF
"$B/keel" merge "$T/d10.md" "$T/d10.json" > "$T/d10.out" 2> "$T/d10.err"
has "$T/d10.err" "changed: D1; unchanged: D2, D3" "only D1 changed; D2's block compares line by line"
has "$T/d10.err" "notes: 4" "four notes placed"
has "$T/d10.err" "put under feedback: 1" "the orphan goes to feedback"
check "$(grep -A3 '➤ Recommended: B' "$T/d10.out" | tail -3 | tr '\n' '|')" "  ➤ Answer:|  A - great idea|  second thought|" "D1 answer written under the line, indented"
has "$T/d10.out" "  ➤ Recommended: B" "the recommendation is untouched"
check "$(grep -A2 '^Some context' "$T/d10.out" | tail -1)" "**Sam, $(date +%F):** Context is thin." "a prose note lands under its paragraph"
check "$(grep -A2 '^| Keep' "$T/d10.out" | tail -1)" "**Sam, $(date +%F):** (row “Keep”) cheap" "a row note lands under the table"
check "$(grep -A2 'Two ways to go' "$T/d10.out" | tail -1)" "  **Sam, $(date +%F):** Good framing." "a note on a card line stays inside its list item"
check "$(grep -A2 'a nested point' "$T/d10.out" | tail -1)" "    **Sam, $(date +%F):** nested note" "a nested note at the nested item's indent"
has "$T/d10.out" "(on “a line long gone”) orphan" "the orphan quotes its line"
cp "$T/d10.out" "$T/d10b.md"
"$B/keel" parse "$T/d10b.md" > "$T/parse.json"
check "$(py 'print(d["items"][0]["answer"])')" $'A - great idea\nsecond thought' "merged memo reads back the same answer"
check "$(py 'print(d["items"][0]["recommended"], len(d["items"]))')" "B 3" "…its recommendation and three items"

echo "D10 shape — copied text"
printf 'D1: B\nD2: = recommended\nNote L3: from the phone\n  second line\nNote L7 row "Keep": ok\nFeedback: done\n' | "$B/keel" merge "$T/d10.md" - > "$T/d10t.out" 2> "$T/d10t.err"
has "$T/d10t.err" "changed: D1, D2" "text form: D1 and D2"
has "$T/d10t.err" "notes: 2" "text form: notes placed by line"
check "$(grep -A3 '^Some context' "$T/d10t.out" | tail -2 | tr '\n' '|')" "**Sam, $(date +%F):** from the phone|second line|" "a multi-line note keeps its lines"
check "$(grep -A1 '➤ Recommended: yes, Friday.' "$T/d10t.out" | tail -1)" "  ➤ Answer:" "D2 Answer line alone"
has "$T/d10t.out" "  = recommended" "…its answer under it"
check "$(grep -c 'Done.\*\* Reply, not answer.' "$T/d10t.out")" "1" "the reply survives once"
printf 'D2: = recommended (accept all)\n' | "$B/keel" merge "$T/d10.md" - > "$T/d10a.out" 2> "$T/d10a.err"
has "$T/d10a.out" "  = recommended (accept all)" "accept all: the marker lands as the answer (D5)"

echo "D10 shape — review cases (2026-10-03)"
cat > "$T/r1.md" <<'EOF'
# R

1. **D1 — Numbered.** Body one.
   ➤ Recommended: A hybrid: keep both
   A — one
   B — two

   Why: cheaper.
   ➤ Answer:
   I think so.
   D2 — same as here

- **D2 — Last.** Body.
  ➤ Recommended: B
  ➤ Answer:


---

**Suggested order:** D1 first.

| k | v |
| --- | --- |
| | x |
| | y |

## Open feedback
EOF
"$B/keel" parse "$T/r1.md" > "$T/parse.json"
check "$(py 'print([i["id"] for i in d["items"]])')" "['D1', 'D2']" "an answer line 'D2 — same as here' is Sam's words, not a phantom D2"
check "$(py 'print(d["items"][0]["answer"])')" $'I think so.\nD2 — same as here' "…and stays in D1's answer"
check "$(py 'print(d["items"][0]["recommended"])')" "A hybrid: keep both" "Recommended stops before options under it"
check "$(py 'print(d["items"][0]["options"])')" "[['A', 'one'], ['B', 'two']]" "options between Recommended and Answer are found"
"$B/keel" build "$T/r1.md" -o "$T/r1.html" > /dev/null
has "$T/r1.html" '<span class="k">Recommended</span>A hybrid: keep both</div>' "a recommendation starting with the article A is not option A"
has "$T/r1.html" 'Why: cheaper.' "the lines between Recommended and Answer are on the card"
has "$T/r1.html" 'data-row="row 1"' "an empty first cell is named by its row"
has "$T/r1.html" 'data-row="row 2"' "…so two rows never share a note"
printf '{"items": {"D2": "A"}}' > "$T/r1.json"
"$B/keel" merge "$T/r1.md" "$T/r1.json" > "$T/r1.out" 2> "$T/r1.err"; rc=$?
check "$rc" "0" "a D-list closed with --- merges"
has "$T/r1.out" "**Suggested order:** D1 first." "…and the prose after it stays"
cat > "$T/r2.md" <<'EOF'
# R2

- **D1 — Pick.** Body.
  ➤ Recommended: B
  ➤ Answer:
  agent forgot to close the list

Lesson, for the next session.

## Open feedback
EOF
printf '{"items": {"D1": "A"}}' > "$T/r2.json"
"$B/keel" merge "$T/r2.md" "$T/r2.json" > /dev/null 2> "$T/r2.err"; rc=$?
check "$rc" "1" "merge refuses to rewrite a block that ran into prose below the list"
has "$T/r2.err" "end the D-list with a heading or \`---\`" "…and says how to fix the memo"
printf '{"items": {}, "comments": [{"at": 2, "quote": "1. **D1 — Numbered.** Body one.", "text": "N1"}, {"at": 24, "row": "row 1", "quote": "| | y |", "text": "first"}, {"at": 24, "row": "row 2", "quote": "| | y |", "text": "second"}]}' > "$T/r3.json"
"$B/keel" merge "$T/r1.md" "$T/r3.json" > "$T/r3.out" 2>/dev/null
check "$(grep -A2 'D1 — Numbered' "$T/r3.out" | tail -1)" "   **Sam, $(date +%F):** N1" "a note in a numbered item keeps the item's 3-column indent"
check "$(grep -o 'row “row [12]”' "$T/r3.out" | tr '\n' ' ')" "row “row 1” row “row 2” " "two notes on one table keep their order"
cp "$T/r3.out" "$T/r3b.md"
"$B/keel" merge "$T/r3b.md" "$T/r3.json" > "$T/r3c.out" 2>/dev/null
check "$(grep -c 'N1$' "$T/r3c.out")" "1" "merging the same notes again adds nothing"
printf 'D1: B\nNote L3 on "1. **D1 — Numbered.** Body one.": moved?\nNote L3 on "a line that is not there": lost\nFeedback: one\n  two\n' | "$B/keel" merge "$T/r1.md" - > "$T/r4.out" 2> "$T/r4.err"
has "$T/r4.err" "notes: 1" "text form: a note whose quote matches is placed"
has "$T/r4.err" "put under feedback: 1" "…one whose quote does not goes to feedback"
has "$T/r4.out" $'one\ntwo' "multi-line feedback loses the page's two-space indent"

echo "bulleted options (2026-10-04) — parse, build, merge round trip"
cat > "$T/bul.md" <<'EOF'
# Bullets — design

Written by `architect` (Fable 5.1, `high`) on 2026-10-04 for a test.

## Decisions

- **D1 — Pick the format** (one line of context).
  - A — answer on the arrow line
  - B — answer in the block under it

  ➤ Recommended: B

  ➤ Answer:

- **D2 — Ship this week?** Plain yes or no.
  - A — yes
  - B — no

  ➤ Recommended: none until P1 shows it builds

  ➤ Answer:

**D3 — Not a list item** (context).

- A — the lint
- B — nothing

➤ Recommended: A if P1 shows X, else B

➤ Answer:

---

## Open feedback
EOF
"$B/keel" parse "$T/bul.md" > "$T/parse.json"
check "$(py 'print([i["id"] for i in d["items"]])')" "['D1', 'D2', 'D3']" "bullets: three items"
check "$(py 'print(d["items"][0]["options"])')" "[['A', 'answer on the arrow line'], ['B', 'answer in the block under it']]" "bullets: D1's options"
check "$(py 'print(d["items"][2]["options"])')" "[['A', 'the lint'], ['B', 'nothing']]" "bullets: D3's options, outside a list item"
check "$(py 'print([(i["recommended"], i["answer"], i["shape"]) for i in d["items"]])')" "[('B', '', 'new'), ('none until P1 shows it builds', '', 'new'), ('A if P1 shows X, else B', '', 'new')]" "bullets: Recommended read across the blank line, answers empty"
"$B/keel" build "$T/bul.md" -o "$T/bul.html" > /dev/null
check "$(grep -o '<button type="button" class="opt" data-letter="[AB]">' "$T/bul.html" | wc -l | tr -d ' ')" "6" "bullets: every option a button on its card"
has "$T/bul.html" '<span class="k">Recommended</span><strong>B</strong> — answer in the block under it' "bullets: the letter shows its option"
check "$(grep -o '<textarea id="ans-D[123]"[^>]*></textarea>' "$T/bul.html" | wc -l | tr -d ' ')" "3" "bullets: three empty answer boxes"
lacks "$T/bul.html" '<li data-at="8"' "bullets: an option is not a plain list item"
printf '{"items": {"D1": "A - great idea\\nsecond thought", "D3": "B"}}' > "$T/bul.json"
"$B/keel" merge "$T/bul.md" "$T/bul.json" > "$T/bul.out" 2> "$T/bul.err"
has "$T/bul.err" "changed: D1, D3" "bullets: merge names D1 and D3"
check "$(grep -A3 '^  ➤ Answer:' "$T/bul.out" | head -4 | tr '\n' '|')" "  ➤ Answer:|  A - great idea|  second thought||" "bullets: D1's answer under its line, a blank line before D2"
check "$(grep -A1 '^➤ Answer:' "$T/bul.out" | tr '\n' '|')" "➤ Answer:|B|" "bullets: D3 at column 0"
has "$T/bul.out" "  - B — answer in the block under it" "bullets: options untouched"
cp "$T/bul.out" "$T/bul2.md"
"$B/keel" parse "$T/bul2.md" > "$T/parse.json"
check "$(py 'print([(i["answer"], i["recommended"], len(i["options"])) for i in d["items"]])')" "[('A - great idea\nsecond thought', 'B', 2), ('', 'none until P1 shows it builds', 2), ('B', 'A if P1 shows X, else B', 2)]" "bullets: the merged memo reads back"
# unmarked items warn since the Keel (2026-10-15, layer section 2); the fixture keeps its line numbers
check "$("$B/keel" lint "$T/bul.md" | grep -v 'no `Reversible: yes|no` line'; echo "rc=${PIPESTATUS[0]}")" "rc=0" "lint: the new shape, conditional picks, empty answers — nothing but the unmarked items"
check "$("$B/keel" lint "$T/bul.md" | grep -c 'no `Reversible: yes|no` line')" "3" "lint: each open item with no Reversible line warns"
check "$("$B/keel" lint "$T/bul2.md" | grep -c 'no `Reversible: yes|no` line')" "1" "…an answered one does not"
check "$("$B/keel" lint "$T/bul2.md" >/dev/null; echo "rc=$?")" "rc=0" "lint: Sam's answers in the new shape are Sam's, never a pre-fill"
check "$("$B/keel" lint "$T/d10.md" | grep -c 'warning: D1 .*bullets')" "1" "lint: plain option lines warn"
check "$("$B/keel" lint "$T/d10.md" >/dev/null; echo "rc=$?")" "rc=0" "…a warning only"

echo "lint — the autofinish design: ed7ca88 (D8 rested on R15, listed as not verified) and b957aa6"
# Verbatim excerpts: the header, D8's options section, the risks it cites, the decisions and "Not
# verified" of ed7ca88; the header, three risks, the decisions and the not-verified block of the
# third pass (b957aa6). Copied, not read by ref: both branches get archived.
cat > "$T/af-old.md" <<'LINT_OLD'
# Autofinish — the normal process, run without the wait for Sam (design, 2026-10-02; revised 2026-10-03, twice)

Written by `sr-architect` (Fable 5.1, `xhigh`) on 2026-10-02 for Sam's ask of the same day: "I really need simple tasks to autofinish, I don't need to review every change. Figure out how to do it." Read against the hooks, skills and scripts in [layer](/srv/sam/projects/layer), every repo under `/srv/sam/projects`, GitHub (`gh`, read-only), seven days of transcripts, the decisions bench, and the Claude Code hooks reference fetched 2026-10-02. Nothing is built; Sam answers in section 10.

### D8 — The wait, the trigger, and how the runner runs (decided 2026-10-03; stands)

**The wait: 40 minutes (`IDLE_MIN`), from the worktree's last `Stop`, with no prompt queued since.** The lock's `OWNER_TTL` stays 2 hours.

| Trigger | Attention | Cost | Breaks | Reversal | Limits |
| --- | --- | --- | --- | --- | --- |
| **A. ✔ launchd on both Macs, `org.example.claude.autofinish`, `StartInterval 300`, `RunAtLoad`, `bin/autofinish --sweep` over `repos.json`; plus `SessionEnd` spawning the lander 60 s later** | zero | zero model calls per tick; the `usage` plist's shape | nothing | `--unschedule` | a Mac asleep runs nothing and holds no warm cache; buildbox needs `--schedule` once (Do this now) |
| **B. A Stop-armed one-shot watcher per worktree** | zero | one sleeper per active worktree | nothing | kill it | depends on a detached child surviving its parent (R4) |
| **C. The session-start sweep only** | zero | zero | nothing | — | misses an idle session with no new start |
| **D. An `async: true` Stop hook that sleeps 40 min** | zero | a sleeper per turn | nothing | — | undocumented reaping |

| Runner | Attention | Cost | Breaks | Reversal | Limits |
| --- | --- | --- | --- | --- | --- |
| **A. ✔ Restart inside the cache window; cold after it.** Last assistant record under 55 min old: process alive → `claude -p --continue <id> --fork-session --session-id <uuid> "/finish"` from the worktree, the parent transcript untouched; process gone → `claude -p --continue <id> "/finish"`. Older → cold `claude -p "/finish"` in the worktree. Tool list: [bin/weekly-run](/srv/sam/projects/layer/bin/weekly-run)'s plus `Agent`, `EnterWorktree`, `Bash(git:*)`, the contract's `check:` and deploy verbs as the contract names them, `~/projects/layer/bin/*`; no `AskUserQuestion`; `--permission-mode acceptEdits`; `caffeinate -i`; a 40 min cap. Before the run the lander writes `owner.json` with the runner's id; after it, removes it | zero | warm: the same `/finish` Sam would have typed, at the same moment's cache; cold: 60–80 k per call, commit bodies for context | nothing | kill the run; `finishing` TTL 2 h; the lock released in `finally` | R5, R14, R15 probes first |
| **B. Always cold** | zero | an eighth of the reads per call, no conversation | nothing | same | G3 and G4 see only commit bodies |
| **C. Always restart** | zero | past the hour a full re-write | nothing | same | — |

**Recommendation: A for both.** What would change it: landings at minute 50 or later more than a tenth of the time → the interval drops to 120 s; a fork that does not read the cache (R15) → 600 s and cold.

## 9. Risks, each with the check that catches it

- **R4 — the `SessionEnd` child dies with the process.** Check: E3's probe; if it dies, the launchd sweep is the only trigger and the doc says so.
- **R5 — `claude -p --continue … "/finish"` does not dispatch a `disable-model-invocation` skill.** Check: E2's probe (i); the fallback copy is kept byte-identical by a test.
- **R14 — the runner cannot take the lock, or `--fork-session` refuses `--session-id`.** Check: E2 probe (iii); fallback: `owner.json` written with a placeholder the hook accepts for 120 s from any new session id in that worktree, tested the same way.
- **R15 — the fork does not read the parent's cache.** Check: E2 probe (ii); under 50 % of the parent's context → runners go cold, the row records it, the interval goes to 600 s.

## 10. Decisions

Legend: one line each; the recommendation is pre-filled after `➤ Answer:`. Change it in place; "go" accepts all twelve.

**D1 — What may start unattended: records-only diffs (rule A), judged by code; small code where the repo opts in (rule B). The records lists are the D1 table.**
➤ Answer: yes, lists as in the table.
> **Accepted 2026-10-03** ("All good"); its "deterministic landing" half is superseded by D12 on Sam's correction: the start is deterministic, the landing is `/finish`.

**D2 — Trigger (first form).**
➤ Answer: yes.
> **Accepted 2026-10-03, superseded by D8.**

**D3 — Each Mac starts runners for its own worktrees; the buildbox "explicit yes" stays for typed `/finish` landings; no runner on buildbox until its token is renewed.**
➤ Answer: yes.
> **Accepted 2026-10-03** ("All good"); amended: an approval, not a review stage; moot on buildbox for now.

**D4 — Sam learns from the PR (body and stop comments), the session-start note, `bin/repos --branches` and `/dream`; undo is the rollback line.**
➤ Answer: yes.
> **Accepted 2026-10-03** ("All good"); stops added as PR comments.

**D5 — One clause in `me/core.md`, one sentence in `rules/git-workflow.md`, the `/rewind` line moved to lessons.**
➤ Answer: yes, as E5 words them.
> **Accepted 2026-10-03** ("All good"); reworded: "the same `/finish`, started for Sam".

**D6 — Rule B on for `pipeline` and `books` now, `layer` after the 2026-10-04 reset; off for `house`, `household`, `archive`, `vault`.**
➤ Answer: yes.
> **Accepted 2026-10-03** ("All good").

**D7 — `/autofinish` is Sam's per-session start rule: it lifts the shape, size, repo and week rules for one session and no gate; the runner is a plain `/finish`.**
➤ Answer: yes.
> **Re-decided 2026-10-03** on Sam's correction: the first form lifted the review and ran `/finish --now`; both are gone.

**D8 — Idle = 40 min, decoupled from the lock; a launchd sweep every 5 min on both Macs plus `SessionEnd`; the runner continues the session (a fork while it is open) inside a 55-minute cache window, else cold, and owns the lock while it runs; every ask is a stop.**
➤ Answer: yes.
> **Decided 2026-10-03; stands**, with "every ask is a stop" made explicit.

**D9 — The fast lane is `/finish` itself (`/finish <branch> --merge` from the phone); `/autofinish now` only frees the panel; nothing skips a gate.**
➤ Answer: yes.
> **Re-decided 2026-10-03** on Sam's correction: the `--now` mode that skipped the review and the open-items gate is withdrawn.

**D10 — Labels first; a rule against Jev after 60 rows; Jev widens rule A only at the bar; guarded repos never sent.**
➤ Answer: yes.
> **Decided 2026-10-03; stands.**

**D11 — A design doc's recommendations stand at a deadline the doc names: by default `link + 24 h` in repos with `live: none`, only on Sam's `/keel stand` in `house` and `household`; any touch by Sam voids it; stood items get the `Applied` reply; the doc lands through `/finish`; the build starts from a seed now, from the dispatcher after a week.**
➤ Answer: yes.

**D12 — Records-only branches get a `/finish` run like every other branch; the deterministic squash is dropped.**
➤ Answer: yes.

## 13. Not verified

- The hooks reference was fetched 2026-10-02; `async: true` and the 1.5 s `SessionEnd` budget are not probed here.
- That a detached child spawned at `SessionEnd` outlives the `claude` process (R4).
- That `claude -p --continue … "/finish"` dispatches a `disable-model-invocation` skill (R5); that `--continue --fork-session --session-id` are accepted together and the fork reads the parent's cache (R14, R15); that a `-p` restart re-enters the worktree by itself.
- The `/finish` token figures count main-session records only; the "wrote and never finished" count misses Bash-only writes.
- GitHub auto-merge needing Pro on a private repo: recollection.
- Whether `bootstrap.sh --schedule` can run on buildbox from an agent over ssh (auto mode refused remote shell writes on 2026-09-21).
- The 24-hour default (D11) rests on 39 measured answer latencies; the per-doc engagement rates were not recomputed here beyond the bench's F14.
- `bin/weekly-run`, `DESIGN.md` and `README.md` changed on disk while the first draft was written (`/horizon` became `/sextant`); the records list was re-read on 2026-10-03.

## Open feedback
LINT_OLD
cat > "$T/af-new.md" <<'LINT_NEW'
# Autofinish — the normal process, run without the wait for Sam, at no more than a typed `/finish` costs (design, 2026-10-02; third pass 2026-10-04)

Written by `sr-architect` (Fable 5.1, `xhigh`). First pass 2026-10-02 for Sam's ask "I really need simple tasks to autofinish, I don't need to review every change." Second pass 2026-10-03 on Sam's correction: "the goal of autofinish is to not skip reasonable review stages … through normal process through all the gates". This third pass, 2026-10-04, on Sam's second correction: "if the sweep pays for context twice it doesn't make sense at all - this is supposed to be a cost-saving feature. … We need to find a solution that actually helps make it most cost-efficient while still reliable. This doc is definitely not ready for my answers." Every number below was read today from this Mac's transcripts, the installed CLI (2.1.288), eight headless probes, and Anthropic's pricing, prompt-caching and scheduled-tasks pages; section 14 says what was not run. Git holds the two earlier passes (`7d899f2`, `ed7ca88`); what no longer bears on a decision is cut, not archived here.

**Legend.** **D<n>** a decision only Sam makes (section 12): D1–D10 and D12 are decided and listed with Sam's words; D11, D13, D14, D15 are open and carry no pre-filled answer. **E<n>** an edit, in build order (section 9), one `sr-worker` session each. **R<n>** a risk with the check that catches it (section 11). **G<n>** a gate or stage of `/finish`, numbered by its step in [skills/finish/SKILL.md](/srv/sam/projects/layer/skills/finish/SKILL.md). **P<n>** a probe run today (section 4). Inside an options table the options are **A, B, C…** and ✔ marks the recommendation. "The runner" is the `/finish` the lander starts: since this pass, always a fresh headless session in the branch's worktree. "The lander" is [bin/autofinish](/srv/sam/projects/layer/bin/autofinish), not yet built. "Warm" means the session's prompt cache is inside its one-hour life; "cold" means it is not. "$" is API list price for the same tokens, the proxy every doc here uses ([bin/usage-report](/srv/sam/projects/layer/bin/usage-report)); the plan's own percentages are the truth. A claim marked *(unverified)* was read, not run.

## 11. Risks, each with the check that catches it

- **R4 — the `SessionEnd` child dies with the process.** Check: E3's probe; if it dies, the sweep is the only trigger and the doc says so.
- **R25 — auto's classifier refuses `bin/pr merge` in the headless runner** (a remote write it has not judged before). Check: E1's acceptance run; the allowlist names [bin/pr](/srv/sam/projects/layer/bin/pr) exactly, and an allow rule approves before the classifier looks (lessons, 2026-10-04); if it still refuses, the runner stops at `pr ready` and the session-start note says so — today's buildbox path, not a failure.
- **R27 — the cold runner's cost drifts above the warm-typed median.** Check: E8's `$` column against the median `/dream` recomputes; above it two weeks running → D13 is reopened with the rows.

## 12. Decisions

**Decided earlier — kept, not reopened.** Sam, 2026-10-03: "All good, I also want to provide explicit override to do it for sessions that I think are safe to do that way, and we refine a threshold on how to do it together. Lower the waittime of auto-finish to 40 minutes so the cache does not expire, you cannot miss it. And let me provide fast lane instruction to auto-finish instantly in case I need something deployed ASAP. We should also learn which sessions I touched and which ones I didn't to predict what to auto-finish. Maybe Jav can help here to decide." And the correction the same day: "the goal is just to make it automated so that … they would go through normally through normal process through all the gates … I don't want to rush things in."

| Decided | What stands |
| --- | --- |
| D1 | Start rules A (records only, everywhere on the workflow) and B (small code where the repo opts in), judged by code; the records lists of the second pass's D1 table |
| D2, D8 (trigger half) | Idle 40 minutes, decoupled from the lock; a launchd sweep on both Macs plus `SessionEnd`; "you cannot miss it". The sweep interval is 10 minutes now (the cache no longer binds); the 40 minutes stays as the "Sam is done" signal |
| D3 | Each Mac starts runners for its own worktrees; buildbox's "explicit yes" stays for typed landings; no runner there until its token is renewed |
| D4 | Sam learns from the PR body and stop comments, the session-start line, `bin/repos --branches`, `/dream`; undo is the rollback line |
| D5 | One clause in [me/core.md](/srv/sam/projects/vault/me/core.md), one sentence in [rules/git-workflow.md](/srv/sam/projects/layer/rules/git-workflow.md), the `/rewind` line moved to lessons |
| D6 | Rule B on for `pipeline` and `books`, `layer` after the 2026-10-04 reset; off for `house`, `household`, `archive`, `vault` |
| D7 | `/autofinish` lifts only the start rules (shape, size, repo, the week's pause), never a gate |
| D9 | The fast lane is `/finish` itself; nothing lighter |
| D10 | Labels first; a rule against Jev after 60 rows; Jev gates nothing until the bar |
| D12 | A records-only branch runs a `/finish` (prose-only, so no review), never the deterministic squash. Priced now: about $2.3 a branch, 17 a week, about $40 — the cost of "through all the gates", kept |
| D8 (runner half) | **Reopened** by the cost constraint → D13 |

**Open — Sam's to answer.** One line each; options as letters; nothing pre-filled.

- **D11 — A design doc's recommendations stand at a deadline the doc names.** Today 13 of 31 idle branches are memos waiting on pre-filled `➤ Answer:` lines; Sam answers per document, within the hour when at all, and half the items never. Any touch by Sam before the deadline voids it; stood items get the `> **Applied.**` reply; the doc lands through the runner; the build starts from a seed (E10), from the dispatcher after a week (E11). Full options and evidence: `ed7ca88` section 6, D11.
  A — by default at link + 24 h in repos whose contract says `live: none`; only on Sam's `/keel stand <doc>` in `house` and `household`
  B — only ever on Sam's `/keel stand <doc>`, in every repo
  C — never: the memos wait for "go"
  ➤ Recommended: A
  ➤ Answer:


- **D13 — How the runner runs** (the reopened half of D8; section 2 is the evidence).
  A — a fresh headless session in the branch's worktree: `claude -p "/finish <branch> --unattended" --session-id <id> --permission-mode auto`, the lock pre-written, the bundle as its record; $2.34 median, independent of the old session's cache, model and tab
  B — an in-session one-shot (`CronCreate` at +40 min) — needs a model-invocable copy of `/finish`, fires only while the panel is open and idle, late or never in both VS Code trials
  C — the forked restart of the second pass — an unprobed cache hit at best equal to A, a full re-write or a refusal otherwise
  D — B first, A as the fallback when B did not start — B's reliability plus a second mechanism, for at most $0.2–0.5 a branch on sessions under 200k
  ➤ Recommended: A
  ➤ Answer:


- **D14 — A `/finish` Sam types into a cold or Fable session runs in the same fresh runner.** The 23 % of typed finishes that come after an hour cost $9.92 against $2.34 (about $175 a week at last fortnight's rate); a Fable session's $14.35 becomes about $2. The hook decides before any model call, so the cold session pays nothing; `/finish --here` keeps it in the tab. Depends on the one-click design's hook or E7's minimal one.
  A — yes, by default, when the session's last call is over 55 min old or its model is Fable; `/finish --here` overrides; the panel reply is the hook's one line and the PR carries the report
  B — opt-in only: the hook prints the saving and `/finish --fresh` starts the runner
  C — no: a typed `/finish` always runs in its session
  ➤ Recommended: A
  ➤ Answer:


- **D15 — The mechanism against the next unprobed premise** (section 8; E0).
  A — the lint in [bin/keel](/srv/sam/projects/layer/bin/keel), run by the Stop hook on a D-list doc changed this turn (blocks once), plus the "Cost per outcome" block and the hypothesis rule in both architect definitions
  B — the definitions only; no lint
  C — nothing beyond this doc
  ➤ Recommended: A
  ➤ Answer:


---

## 14. What this costs Sam, counted; and what is not verified

- **New decisions:** four (D11, D13, D14, D15), eleven already decided. Removed per week, at last week's rates: the `/finish` prompt and its report on up to 43 branches (17 records, 26 small code), the "is this one finished" question for each; with D14, the $7.60 re-write on about 23 typed finishes and the $12 Fable premium, with no change to what Sam types.
- **New verbs Sam may type, never must:** `/autofinish [now|off]`, `/keel stand <doc>`, `/finish --here`.
- **New places to look:** none. A stop is one PR comment and one session-start line.
- **New manual steps:** none; buildbox's `--schedule` runs over ssh from the parent.
- **New spend:** about $50 a week (2.5 % of the Max week) for the sessions that never ran `/finish`; the rest replaces spend Sam pays today at the same or a lower price.

**Not verified.**

- **The claim the recommendation depends on:** that `/finish <branch> --unattended` lands end to end from a fresh `-p` session on this Mac. Every piece is probed — dispatch of a `disable-model-invocation` skill under `-p` (`weekly-run`'s two landings), `auto` mode and hooks under `-p` (2026-10-04), `EnterWorktree` under `-p` (2026-09-26), `--session-id` (P8), an allow rule approving before the classifier (2026-10-04) — but the whole has not run. **The probe:** E1's acceptance run on one records-only `layer` branch, watched, before E2–E7 build on it. If `bin/pr merge` is refused there (R25), the runner stops at `pr ready` and the laptop's typed `/finish` or Sam's tap merges — a degradation to the buildbox path, not a failure.
- That a `-p` fork of a **VS Code** session reads, re-writes or is refused (its tool list was not read). The design does not depend on it; it decides between C's best and worst case only.
- That a `SessionEnd` child outlives the `claude` process (R4; E3 probes it; the sweep covers the miss).
- The near-cold sample is nine runs (p25 $1.16, p75 $3.83); the warm sample 129. R27 keeps measuring. Rerun by the parent session (2026-10-04): `bench/finish_cost.py 14` prints 29 runs where `/finish` was the first or second prompt, starting at 72–280k context and costing $0.89–12.78, so "first prompt" is not "fresh"; the nine-run selection is not printed by the script as committed. The one comparison that survives either way: a fresh run avoids the late ($9.92) and Fable ($14.35) cases.
- The Max-week share ($20 per 1 %) divides a list-price proxy by a percentage read on day 6; the plan's accounting is unpublished.
- Whether `bootstrap.sh --schedule` over ssh is refused by auto mode (a remote write, 2026-09-21); if so, the line comes back for Sam once.
- The 24-hour default of D11 rests on 39 measured answer latencies (unchanged from the second pass).

## Open feedback

LINT_NEW
"$B/keel" lint --strict "$T/af-old.md" > "$T/lint-old.out"; rc=$?
check "$rc" "1" "lint --strict: ed7ca88, read as it was handed over, fails"
has "$T/lint-old.out" "D8 (line 63): the pick 'yes.' rests on R4, R5, R14, R15, listed as not verified" "…on D8, naming R15 (and the R-items of its section)"
check "$(grep -c ': D[1-79] \|: D1[0-2] ' "$T/lint-old.out")" "0" "…on nothing else: the other picks rest on nothing unverified"
check "$("$B/keel" lint "$T/af-old.md"; echo "rc=$?")" "$T/af-old.md: no findings
rc=0" "lint: the same doc answered (replies, pre-dated pre-fills) is quiet — its picks are Sam's now"
"$B/keel" lint "$T/af-new.md" > "$T/lint-new.out"; rc=$?
check "$rc" "0" "lint: b957aa6 passes"
lacks "$T/lint-new.out" "rests on" "…no pick rests on its not-verified block"
check "$(grep -c 'warning: D1[1345] .*bullets' "$T/lint-new.out")" "4" "…its four items warn: options in the old shape"
cp "$T/af-new.md" "$T/af-new2.md"
perl -0pi -e 's/(D13 — How the runner runs\*\* \(the reopened half of D8)/$1; see R25/' "$T/af-new.md"
check "$("$B/keel" lint "$T/af-new.md" | grep -c 'D13 .*rests on R25')" "1" "lint: cite R25 (defined, listed as not verified) in D13 and it fails"
perl -0pi -e 's/➤ Recommended: A(\n  ➤ Answer:\n\n\n- \*\*D14)/➤ Recommended: none until E1 lands one branch$1/' "$T/af-new.md"
check "$("$B/keel" lint "$T/af-new.md" >/dev/null; echo "rc=$?")" "rc=0" "…and a conditional pick on the same item passes"
perl -0pi -e 's/(D13 — How the runner runs\*\* \(the reopened half of D8)/$1; see R25/; s/(➤ Recommended: A\n  ➤ Answer:\n)(\n\n- \*\*D14)/$1  A, go.\n$2/' "$T/af-new2.md"
check "$("$B/keel" lint "$T/af-new2.md" >/dev/null; echo "rc=$?")" "rc=0" "…and once Sam answered it (\"A, go.\"), it is Sam's"
perl -0pi -e 's/^(- \*\*R25 [^\n]*)\n//m' "$T/af-new.md"
perl -0pi -e 's/none until E1 lands one branch/A/' "$T/af-new.md"
check "$("$B/keel" lint "$T/af-new.md" >/dev/null; echo "rc=$?")" "rc=0" "lint: an id the doc never defines is not one of its ids"
cat > "$T/ids.md" <<'EOF'
# Ids

Written by `architect` (Fable 5.1, `high`) on 2026-10-04 for "a test".

## Risks

- **R2 — the cache misses.** Check: a probe.
- **R3 — the lock is lost.** Check: a test.

## Notes

**Not verified.** R2, and the Q4 count in [the log](docs/x.md#L12), `S3` too.

- **D1 — Restart** (cites R3, Q4, L12 and S3).
  - A — restart
  - B — fresh

  ➤ Recommended: A

  ➤ Answer:

---
EOF
check "$("$B/keel" lint "$T/ids.md" >/dev/null; echo "rc=$?")" "rc=0" "lint: a bold lead's list ends at its blank line (R3 below it is not listed); Q4, #L12, a code span — not ids"
perl -0pi -e 's/cites R3, Q4/cites R2, Q4/' "$T/ids.md"
check "$("$B/keel" lint "$T/ids.md" | grep -c 'D1 .*rests on R2')" "1" "…R2, defined and listed, still counts"
cat > "$T/ids2.md" <<'EOF'
# Ids, defined by a heading; a token in the Not verified list

### R4 — the lock is lost

Body.

## Not verified

- R4 is unprobed.
- A1 path untested.

- **D1 — Lock** (cites A1).
  - A — keep it
  - B — drop it

  ➤ Recommended: A

  ➤ Answer:

---
EOF
check "$("$B/keel" lint "$T/ids2.md" >/dev/null; echo "rc=$?")" "rc=0" "lint: \"- A1 path untested\" in the Not verified list does not define A1"
perl -0pi -e 's/\(cites A1\)/(cites R4)/' "$T/ids2.md"
check "$("$B/keel" lint "$T/ids2.md" | grep -c 'D1 .*rests on R4')" "1" "lint: a heading \"### R4 — …\" defines R4"
cat > "$T/pre.md" <<'EOF'
# Pre-filled

Written by `architect` (Fable 5.1, `high`) on 2026-10-04 for "a test".

## Decisions

- **D1 — Pick.** Body.
  ➤ Answer: B

---
EOF
check "$("$B/keel" lint "$T/pre.md" | grep -c "warning: D1 (line 8): an architect doc's .➤ Answer:. holds text ('B') — if it isn't Sam's, empty it")" "1" "lint: an architect's old-shape answer text, dated 2026-10-04, is a warning"
check "$("$B/keel" lint "$T/pre.md" >/dev/null; echo "rc=$?")" "rc=0" "…never an error: it cannot be told from Sam's own answer"
check "$(sed 's/2026-10-04/2026-10-02/' "$T/pre.md" > "$T/pre2.md"; "$B/keel" lint "$T/pre2.md")" "$T/pre2.md: no findings" "…and not before the rule's date"

echo "lint — review round 5: conditional picks, definitions, fences, markers, ranges"
lintdoc() {  # lintdoc <file> <recommended> [extra Not-verified lines] [D-item text]: a one-item doc
  cat > "$1" <<EOF
# Doc

## Risks

- **R2 — the cache misses.** Check: a probe.
- **R15 — the fork misses.** Check: a probe.

## Not verified

${3:-- R15 is unprobed.}

## Decisions

- **D1 — Restart** (${4:-cites R15}).
  - A — restart
  - B — fresh

  ➤ Recommended: $2

  ➤ Answer:

---
EOF
}
lintdoc "$T/c1.md" "A, simplest even if R15 turns out wrong"
check "$("$B/keel" lint "$T/c1.md" | grep -c 'D1 .*rests on R15')" "1" "conditional: \"A, simplest even if R15 turns out wrong\" is a bare pick"
lintdoc "$T/c2.md" "A — cheapest if the fork reads the cache (R15)"
check "$("$B/keel" lint "$T/c2.md" | grep -c 'D1 .*rests on R15')" "1" "conditional: \"A — cheapest if the fork reads the cache\" (no else) is a bare pick"
lintdoc "$T/c3.md" "A if P1 shows the cache read, else B"
check "$("$B/keel" lint "$T/c3.md" >/dev/null; echo "rc=$?")" "rc=0" "conditional: \"A if … else B\" passes"
lintdoc "$T/c4.md" "none until P1 runs"
check "$("$B/keel" lint "$T/c4.md" >/dev/null; echo "rc=$?")" "rc=0" "conditional: \"none until …\" passes"
lintdoc "$T/c5.md" "A" "- **A1 — the probe path**: untested." "cites A1"
check "$("$B/keel" lint "$T/c5.md" | grep -c 'D1 .*rests on A1')" "1" "definition under Not verified: bold-led \"**A1 —\" counts"
lintdoc "$T/c6.md" "A" "| A1 | the probe path, untested |" "cites A1"
check "$("$B/keel" lint "$T/c6.md" | grep -c 'D1 .*rests on A1')" "1" "definition under Not verified: a table row \"| A1 |\" counts"
lintdoc "$T/c7.md" "A" "- A1 path untested." "cites A1"
check "$("$B/keel" lint "$T/c7.md" >/dev/null; echo "rc=$?")" "rc=0" "definition under Not verified: \"- A1 path untested\" is a sentence, not A1's definition"
cat > "$T/c8.md" <<'EOF'
# Doc

- **R15 — the fork misses.** Check: a probe.

## Not verified

```
# a comment in a fence is not a heading
```

- R15 is unprobed.

## Decisions

~~~
- **D9 — an example in a tilde fence**
  ➤ Answer:
~~~

- **D1 — Restart** (cites R15).
  - A — restart
  - B — fresh

  ➤ Recommended: A

  ➤ Answer:

---
EOF
check "$("$B/keel" lint "$T/c8.md" | grep -c 'D1 .*rests on R15')" "1" "fences: a \"# comment\" in a fence neither ends the Not verified section nor starts one"
check "$("$B/keel" parse "$T/c8.md" | python3 -c 'import json,sys; print([i["id"] for i in json.load(sys.stdin)["items"]])')" "['D1']" "fences: a ~~~-fenced example D-item does not parse"
for lead in '- **Not verified:**' '*Not verified.*' 'Not verified:' '### Not yet verified' '### What is not verified'; do
  cat > "$T/c9.md" <<EOF
# Doc

- **R15 — the fork misses.** Check: a probe.

## Notes

$lead

- R2 is fine.

- R15 is unprobed.

## Decisions

- **D1 — Restart** (cites R15).
  - A — restart
  - B — fresh

  ➤ Recommended: A

  ➤ Answer:

---
EOF
  check "$("$B/keel" lint "$T/c9.md" | grep -c 'D1 .*rests on R15')" "1" "markers: \"$lead\" opens a Not verified list (a loose one: past its blank lines)"
done
cat > "$T/c10.md" <<'EOF'
# Doc

- **R15 — the fork misses.** Check: a probe.

The fork reads the cache (R15) *(unverified: not read)*.

- **D1 — Restart** (cites R15).
  - A — restart
  - B — fresh

  ➤ Recommended: A

  ➤ Answer:

---
EOF
check "$("$B/keel" lint "$T/c10.md" | grep -c 'D1 .*rests on R15')" "1" "markers: an inline *(unverified)* marks the ids on its line"
lintdoc "$T/c11.md" "A" "- R2 - 3 runs failed, R15 untested." "cites R3"
sedi 's/^- \*\*R15 — the fork misses.\*\* Check: a probe.$/- **R3 — the lock.** Check: a test./' "$T/c11.md"
check "$("$B/keel" lint "$T/c11.md" >/dev/null; echo "rc=$?")" "rc=0" "ranges: \"R2 - 3 runs\" is not a range (R3 is not listed)"
lintdoc "$T/c12.md" "A" "- R2–4 are unprobed." "cites R3"
sedi 's/^- \*\*R15 — the fork misses.\*\* Check: a probe.$/- **R3 — the lock.** Check: a test./' "$T/c12.md"
check "$("$B/keel" lint "$T/c12.md" | grep -c 'D1 .*rests on R3')" "1" "ranges: \"R2–4\" expands to R3"
cp "$T/af-old.md" "$G/here/docs/af.md"; perl -0pi -e 's/(\*\*D11 — [^\n]*\n)➤ Answer: yes\./$1  ➤ Recommended: yes, rests on R15\n  ➤ Answer:/' "$G/here/docs/af.md"
gitc "$G/here" add docs/af.md; gitc "$G/here" commit -qm "af memo"
gitc "$G/here" push -q origin claude/x 2>/dev/null
run link "$G/here/docs/af.md" > "$T/l9.out" 2>&1; rc=$?
check "$rc" "0" "link still links a doc lint fails"
has "$T/l9.out" "lint:   D11 (line" "…and prints the findings under the links"

echo "memo-lint-fixes (2026-10-05) — the post-landing review of #134, one case per finding"
ids() { "$B/keel" parse "$1" | python3 -c 'import json,sys; print([i["id"] for i in json.load(sys.stdin)["items"]])'; }
lintdoc "$G/here/docs/l.md" "A"
run url "$G/here/docs/l.md" > "$T/ul.out" 2>&1
has "$T/ul.out" "lint:   D1" "item 1: url prints the lint's findings, as link does"
python3 "$B/keel" serve "$T/c1.md" --idle 5 > "$T/sl.out" 2>&1 &
spid=$!
for _ in $(seq 50); do grep -q '^lint:' "$T/sl.out" && break; sleep 0.1; done
kill "$spid" 2>/dev/null
check "$(head -1 "$T/sl.out" | cut -c1-17)" "http://127.0.0.1:" "…serve keeps the URL as its first line"
has "$T/sl.out" "lint:   D1" "…and prints the findings after it"

printf -- '# F\n\n````\n```\n- **D9 — x** body\n  ➤ Answer: no\n```\n````\n\n- **D1 — Real.** Body.\n  ➤ Answer: yes\n' > "$T/f1.md"
check "$(ids "$T/f1.md")" "['D1']" "item 2: a \`\`\`\` fence does not close at an inner \`\`\`"

cat > "$T/n1.md" <<'EOF'
# Doc

- **R15 — the fork misses.** Check: a probe.
- **R16 — the cache misses.** Check: a probe.

## Not verified

- R15 is unprobed.

- **D1 — Restart** (cites R16).
  - A — restart
  - B — fresh

  ➤ Recommended: A

  ➤ Answer:

---
EOF
check "$("$B/keel" lint "$T/n1.md" >/dev/null; echo "rc=$?")" "rc=0" "item 4: \`## Not verified\` ends at an un-headed D-list (R16, cited by D1, is not listed)"
lintdoc "$T/n2.md" "B, even if R15 is wrong; nothing else"
check "$("$B/keel" lint "$T/n2.md" | grep -c 'D1 .*rests on R15')" "1" "…\"B, even if R15 is wrong; nothing else\" is a bare pick"
cat > "$T/n3.md" <<'EOF'
# Doc

- **R15 — the fork misses.** Check: a probe.

## Notes

**Not verified** (background claims only):

- R15 is unprobed.

## Decisions

- **D1 — Restart** (cites R15).
  - A — restart
  - B — fresh

  ➤ Recommended: A

  ➤ Answer:

---
EOF
check "$("$B/keel" lint "$T/n3.md" | grep -c 'D1 .*rests on R15')" "1" "…a lead with trailing text ending in a colon opens the list after a blank line"
lintdoc "$T/n4.md" "A"
for h in '## **Not verified**' '## Claims not verified'; do
  sed "s/^## Not verified\$/$h/" "$T/n4.md" > "$T/n5.md"
  check "$("$B/keel" lint "$T/n5.md" | grep -c 'D1 .*rests on R15')" "1" "…the heading \"$h\" lists R15"
done

printf -- '# W\n\n- **D1 — Pick.** Body.\n  - A — one way that is long enough\n    to wrap onto a second line\n  - B — the other\n\n  ➤ Recommended: A\n\n  ➤ Answer:\n\n---\n' > "$T/w1.md"
check "$("$B/keel" parse "$T/w1.md" | python3 -c 'import json,sys; print(json.load(sys.stdin)["items"][0]["options"])')" \
  "[['A', 'one way that is long enough to wrap onto a second line'], ['B', 'the other']]" "item 5: an option wrapped onto a second line keeps every option"
printf -- '# Q\n\n- **D1 — Pick.** Body.\n  ➤ Answer: yes\n  ```\n  - **D9 — example**\n    ➤ Answer: no\n  ```\n\n- **D2 — Next.** Body.\n  ➤ Answer: no\n' > "$T/q1.md"
check "$(ids "$T/q1.md")" "['D1', 'D2']" "…a fence right under \`➤ Answer: yes\` ends the answer: no phantom D9"
check "$("$B/keel" parse "$T/q1.md" | python3 -c 'import json,sys; print(json.load(sys.stdin)["items"][0]["answer"])')" "yes" "…and D1's answer is just \"yes\""

A6="$T/a6"; git init -q -b claude/x "$A6"
cat > "$A6/d.md" <<'EOF'
# Arch

Written by `architect` (Fable 5.1, `high`) on 2026-10-05 for "a test".

## Decisions

- **D1 — Pick.** Body.
  - A — one
  - B — two

  ➤ Recommended: B

  ➤ Answer: B

---
EOF
git -C "$A6" add d.md && git -C "$A6" -c user.name=t -c user.email=t@t commit -qm doc
check "$("$B/keel" lint "$A6/d.md" | grep -c "warning: D1 .*holds text ('B')")" "1" "item 6: an architect's \`➤ Answer: B\` under \`➤ Recommended: B\`, one commit, warns"
perl -pi -e 's/➤ Answer: B$/➤ Answer:/' "$A6/d.md"; git -C "$A6" -c user.name=t -c user.email=t@t commit -qam empty
perl -pi -e 's/➤ Answer:$/➤ Answer: B/' "$A6/d.md"; git -C "$A6" -c user.name=t -c user.email=t@t commit -qam "Sam answers"
check "$("$B/keel" lint "$A6/d.md")" "$A6/d.md: no findings" "…the same B in a later commit is Sam's: quiet"
git -C "$A6" show claude/x~2:d.md > "$A6/d2.md"; git -C "$A6" add d2.md; git -C "$A6" -c user.name=t -c user.email=t@t commit -qm "a second doc"
git -C "$A6" branch -q main claude/x~1
check "$("$B/keel" lint "$A6/d2.md" | grep -c "holds text")" "1" "…a pre-fill committed on the branch, main behind it, warns"
git -C "$A6" branch -qf main claude/x
check "$("$B/keel" lint "$A6/d2.md")" "$A6/d2.md: no findings" "…but not once that commit is on main: /finish folds the doc and Sam's answers into one"

echo "memo-lint-fixes — the review's cases (2026-10-05)"
for pick in "A if R15 holds else B" "A if R15 holds, else **B**" "A if the probe shows X, else option B" "A if X — else B"; do
  lintdoc "$T/r1.md" "$pick"
  check "$("$B/keel" lint "$T/r1.md" >/dev/null; echo "rc=$?")" "rc=0" "conditional: \"$pick\" passes"
done
lintdoc "$T/r2.md" "A"
sed 's/^## Not verified$/## Verified and not verified/' "$T/r2.md" > "$T/r3.md"
check "$("$B/keel" lint "$T/r3.md" >/dev/null; echo "rc=$?")" "rc=0" "a heading \"Verified and not verified\" is not a Not-verified section"
cat > "$T/r4.md" <<'EOF'
# Doc

- **R15 — the fork misses.** Check: a probe.

## Notes

- **Not verified** (background claims only):

  - R15 is unprobed.

## Decisions

- **D1 — Restart** (cites R15).
  - A — restart
  - B — fresh

  ➤ Recommended: A

  ➤ Answer:

---
EOF
check "$("$B/keel" lint "$T/r4.md" | grep -c 'D1 .*rests on R15')" "1" "a bulleted lead ending in a colon opens the list after a blank line"
printf -- '# W\n\n- **D1 — Pick.** Body.\n  - A — one way\n    1. step one\n  - B — two\n      | col | x |\n\n  ➤ Recommended: A\n\n  ➤ Answer:\n\n---\n' > "$T/r5.md"
check "$("$B/keel" parse "$T/r5.md" | python3 -c 'import json,sys; print(json.load(sys.stdin)["items"][0]["options"])')" \
  "[['A', 'one way'], ['B', 'two']]" "an option's numbered sub-list or table row is not its text"
printf -- '# F\n\n````\n```\n- **D9 — x** body\n  ➤ Answer: no\n```\n````\n\n~~~\n**inside a tilde fence**\n~~~\n\n- **D1 — Real.** Body.\n  ➤ Answer: yes\n' > "$T/r6.md"
"$B/keel" build "$T/r6.md" -o "$T/r6.html" >/dev/null
lacks "$T/r6.html" "<li>D9" "the form renders a \`\`\`\` fence's example D-item as code, not a list item"
lacks "$T/r6.html" "<strong>inside a tilde fence</strong>" "…and a ~~~ fence as code, not markup"

echo "sheep — the spacesheep mirror (a stub CLI and a stub MCP server; nothing leaves the machine)"
S="$T/sheep"; mkdir -p "$S/bin" "$S/state"
cat > "$S/bin/spacesheep" <<'EOF'
#!/usr/bin/env bash
# deploy → the server's JSON; versions → the newest version named as `sheep` named it
echo "$* key=${SPACESHEEP_KEY:-none}" >> "$SHEEP_T/cli.log"
echo "${PATH%%:*}" > "$SHEEP_T/path0"
case "$*" in *"--space sp-weird"*) echo "✗ the server is unwell"; echo "✗ the server is unwell" >&2; echo "HTTP 404 in a body" >&2; exit 1 ;; esac  # S3: a 404 that is not the CLI's not-found line
case "$*" in *"--space sp-gone"*) echo "✗ space not found" >&2; exit 1 ;; esac  # M19: a pin the server lost
case "$1" in
  deploy) n=$(grep -c '^deploy' "$SHEEP_T/cli.log"); cp "$2/index.html" "$SHEEP_T/page.html"
          m=$(printf '%s\n' "$@" | grep -A1 '^-m$' | tail -1); echo "$m" > "$SHEEP_T/version"
          printf '{"uuid":"sp-1","url":"https://spacesheep.dev/@sam/memo","sha":"x%s","is_update":%s}\n' "$n" "$([ "$n" -gt 1 ] && echo true || echo false)" ;;
  versions) printf '{"versions":[{"version_name":"%s","created_at":"2026-10-03T22:00:00Z"}]}\n' "$(cat "$SHEEP_T/version")" ;;
  read) [ "$2" = sp-gone ] && { echo "✗ space not found" >&2; exit 1; }  # R6: a space the server lost
        [ -f "$SHEEP_T/read-fail" ] && { echo "✗ cannot read" >&2; exit 1; }; cat "$SHEEP_T/page.html" ;;  # the live page: the last one deployed
esac
EOF
chmod +x "$S/bin/spacesheep"
# tools/call answers as an event stream, initialize as JSON — both of the CLI's read paths
cat > "$S/mcp.py" <<'EOF'
import json, os, sys
from http.server import BaseHTTPRequestHandler, HTTPServer
T = os.environ["SHEEP_T"]
class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def web(self, code, body):
        with open(T + "/web.log", "a") as f:
            f.write(json.dumps({"path": self.path, "auth": self.headers.get("Authorization"), "cookie": self.headers.get("Cookie"), "code": code}) + "\n")
        self.send_response(code); self.send_header("Content-Type", "application/json"); self.end_headers()
        self.wfile.write(body.encode())
    def do_GET(self):  # the viewer's comments route: web-comments.json, behind the traded cookie
        ok = os.path.exists(T + "/web-comments.json") and self.headers.get("Cookie") == "ss_app=tok-1"
        self.web(200, open(T + "/web-comments.json").read()) if ok else self.web(401, '{"error": "unauthorized"}')
    def do_POST(self):
        if self.path == "/api/account/web-session":  # the key's trade, only while web-comments.json exists
            self.rfile.read(int(self.headers.get("Content-Length") or 0))
            if os.path.exists(T + "/web-comments.json"):
                return self.web(200, '{"cookie": "ss_app", "token": "tok-1", "expires_in": 43200}')
            return self.web(404, '{"error": "not found"}')
        msg = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        with open(T + "/mcp.log", "a") as f:
            f.write(json.dumps({"auth": self.headers.get("Authorization"), "ua": self.headers.get("User-Agent"), "sid": self.headers.get("Mcp-Session-Id"), **msg}) + "\n")
        if "id" not in msg:
            self.send_response(202); self.end_headers(); return
        if msg["method"] == "initialize":
            body = json.dumps({"jsonrpc": "2.0", "id": msg["id"], "result": {}})
            self.send_response(200); self.send_header("Content-Type", "application/json")
            self.send_header("Mcp-Session-Id", "s-42"); self.end_headers(); self.wfile.write(body.encode()); return
        name = msg["params"]["name"]
        text = open(T + "/comments.txt").read() if name == "list_comments" else '{"ok": true}'
        if name == "live_events":  # the room: events.json, past `after`, as spacesheep answers it
            after = msg["params"]["arguments"].get("after", 0)
            evs = json.load(open(T + "/events.json")) if os.path.exists(T + "/events.json") else []
            out = [e for e in evs if e["seq"] > after]
            text = json.dumps({"events": out, "next_after": max([after] + [e["seq"] for e in out]), "tabs_open": 1})
            if after > 0 and os.path.exists(T + "/live-raw"):  # an answer made up by the test: an empty room says next_after 0
                text = open(T + "/live-raw").read()
        res = {"jsonrpc": "2.0", "id": msg["id"], "result": {"content": [{"type": "text", "text": text}]}}
        if name == "add_comment" and os.path.exists(T + "/fail-add"):  # M4: a reply that fails part-way
            res = {"jsonrpc": "2.0", "id": msg["id"], "error": {"message": "boom"}}
        if name == "list_comments" and os.path.exists(T + "/fail-list"):  # R6: a page whose comments do not read
            res = {"jsonrpc": "2.0", "id": msg["id"], "error": {"message": "unwell"}}
        self.send_response(200); self.send_header("Content-Type", "text/event-stream"); self.end_headers()
        self.wfile.write(("event: message\ndata: %s\n\n" % json.dumps(res)).encode())
s = HTTPServer(("127.0.0.1", 0), H)
open(T + "/port", "w").write(str(s.server_address[1]))
s.serve_forever()
EOF
SHEEP_T="$S" python3 "$S/mcp.py" & MCP_PID=$!; disown $MCP_PID
trap 'kill $MCP_PID 2>/dev/null; reap; rm -rf "$T"' EXIT
for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$S/port" ] && break; sleep 0.2; done
mkclone "$G/sh"; gitc "$G/sh" checkout -q -b claude/sh; mkdir -p "$G/sh/docs"
cat > "$G/sh/docs/s.md" <<'EOF'
# Mirror me

Some context worth a note.

| Option | Cost |
| --- | --- |
| Keep | cheap |

- **D1 — Ship it?** Body.
  ➤ Answer: yes.

- **D2 — Which way?** Two ways.
  A — one
  B — two
  ➤ Recommended: B
  ➤ Answer:

---

## Open feedback
EOF
gitc "$G/sh" add docs/s.md; gitc "$G/sh" commit -qm "mirror memo"
SM="$G/sh/docs/s.md"
srun() { (export SHEEP_T="$S" MEMO_SHEEP_BIN="$S/bin/spacesheep" MEMO_SHEEP_STATE="$S/state" SPACESHEEP_KEY=ss_test \
          MEMO_SHEEP_MCP="http://127.0.0.1:$(cat "$S/port")/mcp" MEMO_SHEEP_APP="http://127.0.0.1:$(cat "$S/port")" \
          REGATTA_SHEEP_DIR="$S/budget"; unset REGATTA_SHEEP_PLAN; run "$@"); }

srun sheep "$SM" > "$T/s1.out" 2>&1; rc=$?
check "$rc" "0" "sheep deploys a memo"
check "$(python3 -c 'import json,sys; print([json.loads(l)["by"] for l in open(sys.argv[1])])' "$S/budget/deploys.jsonl" 2>&1)" "['keel']" "…and the publish goes in this Mac's deploy log, which helm's redeploys share (spacesheep-tiers)"
check "$(cat "$S/path0")" "$S/bin" "…with the CLI's own folder first on PATH, so its node is found (buildbox, 2026-10-05)"
has "$T/s1.out" "page:   https://spacesheep.dev/@sam/memo (" "…and prints the page"
SHA=$(git -C "$G/sh" rev-parse --short HEAD)
PD=$(python3 -c 'import hashlib,re; k="sh@claude/sh:docs/s.md"; print(re.sub(r"[^a-z0-9]+", "-", k.lower()).strip("-")[:50] + "-" + hashlib.sha1(k.encode()).hexdigest()[:8])')
has "$S/cli.log" "deploy $S/state/pages/$PD --title Mirror me -m claude/sh@$SHA --no-manifest --json key=ss_test" "first deploy: a new space titled from the memo, named <branch>@<sha>, no manifest, the key in the environment"
check "$(python3 -c 'import sys; from importlib.machinery import SourceFileLoader as L; m = L("m", sys.argv[1]).load_module(); a = "x" * 70 + "-one"; b = "x" * 70 + "-two"; print(m.page_dir(a) == m.page_dir(b), m.page_dir(a) == m.page_dir(a), len(m.page_dir(a).name))' "$B/keel")" "False True 59" "M8: the page folder is the key's slug cut at 50 plus its hash — two long keys sharing a 60-character slug no longer share a folder (179 pins had 148 folders)"
has "$S/page.html" 'data-ss-id="D1"' "the page anchors D1's card"
has "$S/page.html" 'data-ss-id="D2"' "…and D2's"
PID=$(python3 -c 'import hashlib; print("b-" + hashlib.sha1(b"Some context worth a note.\x00").hexdigest()[:8])')
has "$S/page.html" "data-ss-id=\"$PID\"" "a paragraph is a block anchor, by its text, not its line number"
check "$(grep -o 'data-ss-id="b-[0-9a-f]*"[^>]*><td>Keep' "$S/page.html" | wc -l | tr -d ' ')" "1" "a table row is one too"
check "$(python3 -c 'import re,sys; h=open(sys.argv[1]).read(); c=re.search(r"<section class=\"card\" id=\"card-D2\".*?</section>", h, re.S).group(0); print(c.count(" data-ss-id=\"D2\""), c.count("class=\"opt\""), c.count("id=\"ans-D2\""))' "$S/page.html")" "1 2 1" "the page is the form (2026-10-14): D2's card anchored, its options buttons, its answer box"
has "$S/page.html" '"emit": "memo-save"' "…its Save goes out as the memo-save event"
has "$S/page.html" "\"sha\": \"$(git -C "$G/sh" rev-parse HEAD)\"" "…naming the commit the page shows"
has "$S/page.html" "window.ss.emit(M.emit, ev)" "…through spacesheep's page bridge"
has "$S/page.html" 'name="viewport"' "…laid out for a phone"
check "$(head -c 15 "$S/page.html")$(tail -c 14 "$S/page.html")" "<!doctype html></body></html>" "…a whole document: spacesheep gives a fragment no page bridge (probed 2026-10-14)"
check "$(grep -o 'name="viewport"' "$S/page.html" | wc -l | tr -d ' ')" "1" "…one viewport tag, not two"
has "$S/page.html" "https://github.com/owner/repo/edit/claude/sh/docs/s.md" "the footer carries the edit link"
srun sheep "$SM" > "$T/s1b.out" 2>&1
check "$(grep -c '^deploy' "$S/cli.log")" "1" "the same commit again: no redeploy"
has "$T/s1b.out" "already showing this commit" "…and it says so"
gitc "$G/sh" push -q -u origin claude/sh 2>/dev/null  # url links only what GitHub holds
srun line "$SM" > "$T/s2.out" 2> "$T/s2.err"
check "$(cat "$T/s2.out")" "[course](https://spacesheep.dev/@sam/memo) | [github](https://github.com/owner/repo/blob/claude/sh/docs/s.md) — [s.md]($(cd "$G/sh/docs" && pwd -P)/s.md#L1)" "line: with D-items the page is the form, first; then GitHub, then the file (2026-10-14)"
has "$T/s2.err" "memo sheep wait" "…and stderr names the listener that wakes the session on a Save"
check "$(grep -c '^deploy' "$S/cli.log")" "1" "…the pinned page already shows this commit: no deploy"
# The mirror (bin/sheep local_url): with a live mirror.json the space link is its local address,
# and line_findings takes that address as the pinned page — only while that mirror runs.
mkdir -p "$SPACESHEEP_CONFIG_DIR"; sleep 300 > /dev/null 2>&1 & MPID=$!
trap 'kill $MPID $MCP_PID 2>/dev/null; reap; rm -rf "$T"' EXIT
printf '{"pid": %s, "port": 4999, "site": "https://spacesheep.dev"}\n' "$MPID" > "$SPACESHEEP_CONFIG_DIR/mirror.json"
srun line "$SM" > "$T/s2m.out" 2>/dev/null
has "$T/s2m.out" "[course](http://localhost:4999/@sam/memo) | " "line: with a mirror running, the form link is its local address"
CLAUDE_CODE_ENTRYPOINT=sdk-cli srun line "$SM" > "$T/s2r.out" 2>/dev/null
has "$T/s2r.out" "[course](https://spacesheep.dev/@sam/memo) | " "…not in a Remote Control session, read on the phone — but the form is still there"
CLAUDE_UNATTENDED=1 srun line "$SM" > "$T/s2u.out" 2>/dev/null
has "$T/s2u.out" "[course](https://spacesheep.dev/@sam/memo) | " "…nor in an unattended run"
# the pin lives in srun's state dir: the check must compare against it, not just the URL's shape
slf() { MEMO_SHEEP_STATE="$S/state" python3 -c 'import sys; from importlib.machinery import SourceFileLoader as L; m = L("m", sys.argv[1]).load_module(); print(" / ".join(m.line_findings(sys.argv[3], sys.argv[2])) or "ok")' "$B/keel" "$SM" "$1"; }
SLINE=$(tail -1 "$T/s2m.out")
check "$(slf "$SLINE")" "ok" "…and the hand-over check takes the local address as the doc's page"
check "$(slf "${SLINE//@sam\/memo/@sam/other}" | grep -o "not this doc's page")" "not this doc's page" "…but a local address of another page is still named"
check "$(slf "${SLINE//localhost:4999/localhost:4998}" | grep -o "not a spacesheep.dev page")" "not a spacesheep.dev page" "…and a localhost link with no mirror on its port is refused"
SU=$(python3 -c 'import sys; from importlib.machinery import SourceFileLoader as L; m = L("s", sys.argv[1]).load_module()
for u in sys.argv[2:]: print(m.local_url(u), m.web_url(m.local_url(u)))' "$B/sheep" https://spacesheep.dev/@a/b?x=1 https://0f8e7d6c-1111-4222-8333-944455556666.spacesheep.app/i.html https://spacesheep.dev https://github.com/o/r https://evil.spacesheep.dev.example.com/x)
check "$SU" "http://localhost:4999/@a/b?x=1 https://spacesheep.dev/@a/b?x=1
http://0f8e7d6c-1111-4222-8333-944455556666.localhost:4999/i.html https://0f8e7d6c-1111-4222-8333-944455556666.spacesheep.app/i.html
http://localhost:4999/ https://spacesheep.dev/
https://github.com/o/r https://github.com/o/r
https://evil.spacesheep.dev.example.com/x https://evil.spacesheep.dev.example.com/x" "sheep local_url / web_url: the CLI's address map, both ways; other hosts untouched"
check "$("$B/sheep" url https://spacesheep.dev/@a/b)" "http://localhost:4999/@a/b" "sheep url prints the local address"
check "$(CLAUDE_CODE_ENTRYPOINT=sdk-cli "$B/sheep" url https://spacesheep.dev/@a/b) $(CLAUDE_UNATTENDED=1 "$B/sheep" url https://spacesheep.dev/@a/b)" \
  "https://spacesheep.dev/@a/b https://spacesheep.dev/@a/b" "…but the https link in a Remote Control or unattended run (chat_page's guard, shared: sheep chat_url)"
printf '{"pid": %s, "port": 4999, "site": "http://localhost:8787"}\n' "$MPID" > "$SPACESHEEP_CONFIG_DIR/mirror.json"
check "$("$B/sheep" url https://spacesheep.dev/@a/b)" "https://spacesheep.dev/@a/b" "…not a mirror of another site (a dev server)"
kill "$MPID" 2>/dev/null; wait "$MPID" 2>/dev/null
printf '{"pid": %s, "port": 4999, "site": "https://spacesheep.dev"}\n' "$MPID" > "$SPACESHEEP_CONFIG_DIR/mirror.json"
check "$("$B/sheep" url https://spacesheep.dev/@a/b)" "https://spacesheep.dev/@a/b" "…nor a mirror.json whose process is gone"
printf '{"pid": 0, "port": 4999, "site": "https://spacesheep.dev"}\n' > "$SPACESHEEP_CONFIG_DIR/mirror.json"
check "$("$B/sheep" url https://spacesheep.dev/@a/b)" "https://spacesheep.dev/@a/b" "…nor pid 0, which kill(0) would call alive"
printf '{"pid": 1, "port": 4999, "site": "https://spacesheep.dev"}\n' > "$SPACESHEEP_CONFIG_DIR/mirror.json"
check "$("$B/sheep" url https://spacesheep.dev/@a/b)" "https://spacesheep.dev/@a/b" "…nor a pid another user holds (EPERM: a stale file, as the CLI reads it)"
printf '{"pid": %s, "port": 4999}\n' "$$" > "$SPACESHEEP_CONFIG_DIR/mirror.json"; chmod 000 "$SPACESHEEP_CONFIG_DIR/mirror.json"
check "$("$B/sheep" url https://spacesheep.dev/@a/b 2>&1)" "https://spacesheep.dev/@a/b" "…nor an unreadable mirror.json, and no traceback"
chmod 600 "$SPACESHEEP_CONFIG_DIR/mirror.json"
rm -f "$SPACESHEEP_CONFIG_DIR/mirror.json"
cp "$S/version" "$T/version.keep"  # the stub's newest version: `sheep check` below reads s.md's
mkdir -p "$G/sh/notes"; printf '# Plain\n\nNo questions here.\n' > "$G/sh/notes/plain.md"; gitc "$G/sh" add notes; gitc "$G/sh" commit -qm plain
gitc "$G/sh" push -q origin claude/sh 2>/dev/null
srun line "$G/sh/notes/plain.md" > "$T/s2p.out" 2> "$T/s2p.err"; rc=$?
check "$(sed -E 's#\(https://spacesheep[^)]*\)#(PAGE)#' "$T/s2p.out")" "[github](https://github.com/owner/repo/blob/claude/sh/notes/plain.md) | [space](PAGE) — [plain.md]($(cd "$G/sh/notes" && pwd -P)/plain.md#L1)" "a doc without D-items: no form, the line starts at github, and it is mirrored too"
check "$rc" "0" "…exit 0: no form is owed"
has "$T/s2p.err" "keel line: no course — no D-items" "…stderr says why no course link"
has "$S/page.html" "Comments work too" "…its page takes notes, feedback and comments"
# M7: by hand the same doc is mirrored as `line` does; the checkpoint's hook still skips it
printf '# Plain two\n\nNo questions here either.\n' > "$G/sh/notes/plain2.md"; gitc "$G/sh" add notes; gitc "$G/sh" commit -qm plain2
srun sheep "$G/sh/notes/plain2.md" > "$T/s2q.out" 2>&1; rc=$?
check "$rc" "0" "M7: memo sheep <doc> by hand mirrors a doc without D-items"
has "$T/s2q.out" "page:   https://spacesheep.dev/@sam/memo (" "…and prints its page"
check "$(srun sheep --hook "$G/sh/notes/plain2.md")" "" "…while the hook path still skips it, silently"
gitc "$G/sh" reset -q --hard HEAD~1
srun sheep pull > "$T/s2u1.out" 2>&1; rc=$?
check "$rc" "1" "M7: sheep pull with no doc is a usage line, rc 1"
has "$T/s2u1.out" "usage: memo sheep <doc> | sheep pull <doc>" "…not \"pull: no such file\""
srun sheep check > "$T/s2u2.out" 2>&1
has "$T/s2u2.out" "usage: memo sheep <doc>" "…and so for check"
run sheep -h > "$T/s2h.out" 2>&1
has "$T/s2h.out" "Deploy a memo's page to spacesheep" "sheep -h has a description"
gitc "$G/sh" reset -q --hard HEAD~1; gitc "$G/sh" push -q -f origin claude/sh 2>/dev/null; cp "$T/version.keep" "$S/version"
srun sheep check "$SM" > "$T/s3.out" 2>&1; rc=$?
check "$rc" "0" "check: current"
has "$T/s3.out" "current (docs/s.md, claude/sh@$SHA, from the page's newest version)" "…naming the version it read"
echo "change" >> "$SM"
srun sheep "$SM" > "$T/s4.out" 2>&1; rc=$?
check "$rc" "1" "sheep refuses a memo with uncommitted changes"
has "$T/s4.out" "commit first" "…and says why"
gitc "$G/sh" commit -qam "edit"
srun sheep check "$SM" > "$T/s5.out" 2>&1; rc=$?
check "$rc" "1" "check: behind once the memo moved"
has "$T/s5.out" "behind by 1 commit" "…by one commit"
srun sheep "$SM" > /dev/null 2>&1
check "$(grep -c -- '--space sp-1' "$S/cli.log")" "1" "a changed memo updates the pinned space"
# M19: the pinned space is gone on the server — drop the pin, deploy as new, once (the stub refuses sp-gone as the CLI says "not found")
echo "edit two" >> "$SM"; gitc "$G/sh" commit -qam "edit two"
python3 -c 'import json,sys; f=sys.argv[1]; d=json.load(open(f)); [v.update(space="sp-weird", taken=["old"], events_after=7, saves=[{"seq": 99, "at": "2026-10-15T00:00:00Z", "data": {"items": {"D1": "keep me"}}}], refused_saves=[{"seq": 98}]) for k, v in d.items() if k.endswith("docs/s.md")]; json.dump(d, open(f, "w"))' "$S/state/sheep.json"
n0=$(grep -c '^deploy' "$S/cli.log")
srun sheep "$SM" > "$T/s4w.out" 2>&1; rc=$?
check "$rc" "1" "S3: a 404 in the CLI's body that is not its own not-found line is a failed deploy, not a lost space"
check "$(grep -c '^deploy' "$S/cli.log")" "$((n0 + 1))" "…with no second deploy"
check "$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); p=[v for k, v in d.items() if k.endswith("docs/s.md")][0]; print(p["space"], len(p["saves"]))' "$S/state/sheep.json")" "sp-weird 1" "…and the pin untouched"
python3 -c 'import json,sys; f=sys.argv[1]; d=json.load(open(f)); [v.update(space="sp-gone") for k, v in d.items() if k.endswith("docs/s.md")]; json.dump(d, open(f, "w"))' "$S/state/sheep.json"
n0=$(grep -c '^deploy' "$S/cli.log")
srun sheep --hook "$SM" > "$T/s4h.out" 2>&1
check "$(grep -c '^deploy' "$S/cli.log")" "$((n0 + 1))" "S3: the hook's budget (20 s) is under one deploy timeout: no retry there"
srun sheep "$SM" > "$T/s4g.out" 2>&1; rc=$?
check "$rc" "0" "M19: a pinned space the server reports not found: the page is deployed as a new one"
check "$(grep '^deploy' "$S/cli.log" | tail -2 | awk '{print ($0 ~ /--space sp-gone/) ? "refused" : "new"}' | tr '\n' ' ')" "refused new " "…the refused deploy, then one without --space (once)"
check "$(grep -c '^deploy' "$S/cli.log")" "$((n0 + 3))" "…and no more than those two (after the hook's one)"
check "$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); p=[v for k, v in d.items() if k.endswith("docs/s.md")][0]; print(p["space"], p["old_space"], p.get("taken"), len(p["saves"]), len(p["refused_saves"]), p.get("events_after"))' "$S/state/sheep.json")" "sp-1 sp-gone ['old'] 1 1 None" "S3: the pin holds the new space and keeps what is Sam's — pending and refused Saves, taken threads — dropping the old cursor"
python3 -c 'import json,sys; f=sys.argv[1]; d=json.load(open(f)); [(v.pop("saves", None), v.pop("refused_saves", None), v.update(taken=[])) for k, v in d.items() if k.endswith("docs/s.md")]; json.dump(d, open(f, "w"))' "$S/state/sheep.json"
has "$T/s4g.out" "space sp-gone is gone on spacesheep" "…and says so on stderr"
gitc "$G/sh" reset -q --hard HEAD~1
python3 -c 'import json,sys; f=sys.argv[1]; d=json.load(open(f)); [v.pop("fmt", None) for v in d.values()]; json.dump(d, open(f, "w"))' "$S/state/sheep.json"
srun sheep "$SM" > /dev/null 2>&1
check "$(grep -c -- '--space sp-1' "$S/cli.log")" "2" "a page of the read-only shape (no fmt) is redeployed as the form, same commit or not"
gitc "$G/sh" reset -q --hard HEAD~1

mkdir -p "$T/vault"; git -C "$T/vault" init -q -b claude/p; mkdir -p "$T/vault/docs"
cp "$SM" "$T/vault/docs/p.md"; gitc "$T/vault" add -A; gitc "$T/vault" commit -qm p
srun sheep "$T/vault/docs/p.md" > "$T/s6.out" 2>&1; rc=$?
check "$rc" "1" "vault is never mirrored"
has "$T/s6.out" "never mirrored" "…and says so"
check "$(srun sheep --hook "$T/vault/docs/p.md")" "" "…and the hook skips it without a word"
mkdir -p "$T/Archive/docs"; git -C "$T/Archive" init -q -b claude/c; cp "$SM" "$T/Archive/docs/c.md"; gitc "$T/Archive" add -A; gitc "$T/Archive" commit -qm c
srun sheep "$T/Archive/docs/c.md" > "$T/s6c.out" 2>&1; rc=$?
check "$rc $(grep -c 'Archive is private' "$T/s6c.out")" "1 1" "archive is never mirrored either (hooks/sheep_gate.py's one list, case-folded)"
check "$(SHEEP_T="$S" MEMO_SHEEP_STATE="$S/state" MEMO_SHEEP_BIN=/nonexistent SPACESHEEP_KEY=k run sheep --hook "$SM"; echo "rc=$?")" "rc=0" "the hook with no CLI: silent, exit 0 (MEMO_SHEEP_BIN set means no fallback)"
check "$(srun sheep --hook "$SM" | python3 -c 'import json,sys; print(json.loads(sys.stdin.readline())["url"])')" "https://spacesheep.dev/@sam/memo" "the hook prints a JSON line with the page"
check "$(srun sheep --hook --budget 0 "$SM" | python3 -c 'import json,sys; print(json.loads(sys.stdin.readline())["error"][:30])')" "the hook's time ran out first " "no deploy is started past the hook's budget"

cat > "$S/comments.txt" <<EOF
{"comments": [
 {"id": "c1r", "body": "and tell Alex", "parent_id": "c1", "created_at": "2026-10-03T21:01:00Z"},
 {"id": "c1", "body": "no — wait for Monday", "anchor_id": "D1", "created_at": "2026-10-03T21:00:00Z", "resolved": false,
  "replies": [{"id": "c1b", "body": "memo: seen", "is_bot": true}]},
 {"id": "c2", "body": "A, after all", "anchor_id": "D2", "created_at": "2026-10-03T20:00:00.123456789Z"},
 {"id": "c3", "body": "B is fine", "anchor_id": "D2", "created_at": "2026-10-03T19:00:00Z"},
 {"id": "c4", "body": "thin", "anchor_id": "$PID", "created_at": "2026-10-03T19:30:00Z"},
 {"id": "c5", "body": "whole thing reads well", "created_at": "2026-10-03T19:40:00Z"},
 {"id": "c6", "body": "old point", "anchor_id": "D1", "resolved": true}
]}
EOF
# the deploys above read the comments too (the anchor carry, 2026-10-24): count this pull's calls alone
: > "$S/mcp.log"
srun sheep pull "$SM" > "$T/p1.out" 2>&1; rc=$?
check "$rc" "0" "pull previews"
check "$(git -C "$G/sh" status --porcelain docs/s.md)" "" "…writing nothing"
has "$T/p1.out" "would merge 4 threads" "…four threads: D1, D2's newest, a note, feedback"
has "$T/p1.out" "kept open: [c3] superseded by the newer [c2] on D2" "the older D2 comment is superseded"
check "$(grep -c '"tools/call"' "$S/mcp.log")" "2" "a preview makes two calls: list_comments, live_events for the page's Saves"
has "$S/mcp.log" '"name": "live_events", "arguments": {"uuid": "sp-1", "after": 0, "wait_seconds": 0}' "…from the start of the room, without waiting"
check "$(grep -c '"initialize"' "$S/mcp.log")" "1" "…in one MCP session"
has "$S/mcp.log" '"auth": "Bearer ss_test"' "the key goes as a Bearer header"
has "$S/mcp.log" '"ua": "memo/1' "a named User-Agent: Cloudflare 403s urllib's default before spacesheep sees the key"
has "$S/mcp.log" '"sid": "s-42"' "the session id from initialize is echoed"
srun sheep pull --write "$SM" > "$T/p2.out" 2>&1; rc=$?
check "$rc" "0" "pull --write (the flag before the doc too)"
check "$(grep -A1 'D1 — Ship it' "$SM" | tail -1)" "  ➤ Answer: no — wait for Monday and tell Alex" "D1: root and Sam's reply (listed before its parent), the bot's left out"
check "$(grep -A2 '➤ Recommended: B' "$SM" | tail -1)" "  A, after all" "D2: the newest comment is the answer block"
check "$(grep -A2 '^Some context' "$SM" | tail -1)" "**Sam, $(date +%F):** thin" "a block comment is a note under its line"
has "$SM" "**Sam, $(date +%F):** whole thing reads well" "an unanchored comment is open feedback"
check "$(grep -c '"add_comment"' "$S/mcp.log")" "5" "one memo: reply per thread taken, and one on the superseded"
check "$(grep -c '"resolve_comment"' "$S/mcp.log")" "0" "A: none resolved — a taken thread stays open on the page, its marker in place (2026-10-24)"
has "$S/mcp.log" '"parent_id": "c1"' "the reply is in the thread"
has "$S/mcp.log" '"parent_id": "c3"' "the superseded D2 thread gets its reply too, and is marked taken, so no later pull reverts D2"
gitc "$G/sh" checkout -q -- docs/s.md
srun sheep pull "$SM" > "$T/p2b.out" 2>&1
has "$T/p2b.out" "would merge 0 threads" "threads taken once are never taken again (the pin records them)"

cat > "$S/comments.txt" <<'EOF'
Comments on "Mirror me" (3 threads)
[id: t1] on D1 · Sam · 2026-10-03T21:00 · open
  not yet
  [id: t1a] Claude · reply
    memo: noted
[id: t2] on D1 · Sam · resolved
  done already
- [id: t3] Sam on D2: B, and soon — ask Claude first
Reactions: D1 👍 2
EOF
srun sheep pull "$SM" > "$T/p3.out" 2>&1
has "$T/p3.out" "would merge 2 threads" "the text form: two open threads"
has "$T/p3.out" "[t1] → D1: not yet" "…t1 on D1, the bot's reply and the resolved thread left out"
has "$T/p3.out" "[t3] → D2: B, and soon — ask Claude first" "…t3's body on its own line, its words not read as a bot"
lacks "$T/p3.out" "Reactions" "an unindented tally line is nobody's words"

cp "$S/comments.txt" "$T/comments.synthetic"
cat > "$S/comments.txt" <<'EOF'
To answer a thread, call add_comment with parent_id = its first [id: …]; resolve it with resolve_comment and that id.

[id: a3625b49-060b-488e-a780-20ea73ba1978] @someone@example.org (2026-10-04T22:03:11.894Z)
I did this now!
---
EOF
srun sheep pull "$SM" > "$T/p3r.out" 2>&1
has "$T/p3r.out" "would merge 1 thread" "the real answer's shape (2026-10-04): body under the header, closed by ---"
has "$T/p3r.out" "open feedback" "…an unanchored comment is open feedback"
lacks "$T/p3r.out" "---" "…the closing --- is nobody's words"
cat > "$S/comments.txt" <<'EOF'
[id: t9] on D1 · Sam · open
  not yet
Reactions: D1 👍 2
EOF
srun sheep pull "$SM" > "$T/p3t.out" 2>&1
lacks "$T/p3t.out" "Reactions" "the indented shape: a tally after an open header's indented body is nobody's words"
# The viewer's JSON route, the real shape (2026-10-14): every comment carries Sam's author_email;
# only `via` tells the Co-shepherd's reply from Sam's words (F7 in memo-on-spacesheep-2026-10-11).
cat > "$S/web-comments.json" <<'EOF'
{"comments": [
 {"id": "w1", "parent_id": null, "author_email": "i@x", "body": "B, from the phone", "anchor_id": "D2", "resolved_at": null, "created_at": "2026-10-14T10:00:00Z", "via": null},
 {"id": "w2", "parent_id": "w1", "author_email": "i@x", "body": "Yes, the memo is in solid shape", "anchor_id": null, "resolved_at": null, "created_at": "2026-10-14T10:01:00Z", "via": "co-shepherd"},
 {"id": "w4", "parent_id": null, "author_email": "i@x", "body": "posted by a session", "anchor_id": null, "resolved_at": null, "created_at": "2026-10-14T10:03:00Z", "via": "session"},
 {"id": "w3", "parent_id": null, "author_email": "i@x", "body": "already taken", "anchor_id": null, "resolved_at": "2026-10-14T10:02:00Z", "created_at": "2026-10-14T09:00:00Z", "via": null}
], "reactions": [], "anchor_reactions": []}
EOF
: > "$S/web.log"
srun sheep pull "$SM" > "$T/pw.out" 2>&1
has "$T/pw.out" "[w1] → D2: B, from the phone" "the JSON route: an anchored comment answers its card"
lacks "$T/pw.out" "solid shape" "…a reply whose via is the Co-shepherd is never Sam's words"
lacks "$T/pw.out" "posted by a session" "…nor any other via: only null is Sam's (E1)"
lacks "$T/pw.out" "not yet" "…and the route wins over list_comments' text"
has "$S/web.log" '"path": "/api/account/web-session", "auth": "Bearer ss_test"' "…the key trades for the web session"
has "$S/web.log" '"path": "/api/space/sp-1/comments", "auth": null, "cookie": "ss_app=tok-1", "code": 200' "…whose cookie, never the key, reads the comments"
rm "$S/web-comments.json"
cp "$T/comments.synthetic" "$S/comments.txt"

perl -pi -e 's/➤ Answer: yes\./➤ Answer: typed on GitHub./' "$SM"; gitc "$G/sh" commit -qam "Answer D1 on GitHub"
srun sheep pull "$SM" > "$T/p4.out" 2>&1
has "$T/p4.out" "kept open: [t1] D1 changed in git after it (git's answer kept)" "both channels: a git answer newer than the comment wins, and the summary says so"
sedi 's/2026-10-03T21:00/2099-01-01T00:00/' "$S/comments.txt"
srun sheep pull "$SM" > "$T/p5.out" 2>&1
has "$T/p5.out" "[t1] → D1: not yet" "…a comment newer than the git answer wins over it, redeploy or not"

perl -0pi -e 's/# Mirror me\n/# Mirror me\n\nA new line above everything.\n/' "$SM"; gitc "$G/sh" commit -qam "lines added above"
srun sheep "$SM" > /dev/null 2>&1
printf '{"comments": [{"id": "n1", "body": "still thin", "anchor_id": "%s"}]}\n' "$PID" > "$S/comments.txt"
srun sheep pull --write "$SM" > /dev/null 2>&1
check "$(grep -A2 '^Some context' "$SM" | tail -1)" "**Sam, $(date +%F):** still thin" "lines added above a block: its comment still lands under it"
gitc "$G/sh" checkout -q -- docs/s.md

echo "sheep — the publish budget: keel never skips, warns once per crossing, names a cap refusal (spacesheep-tiers)"
cat > "$T/kbudget.py" <<'PY'
import json, os, sys, time
from importlib.machinery import SourceFileLoader as L
m = L("m", sys.argv[1]).load_module()
log = os.path.join(os.environ["REGATTA_SHEEP_DIR"], "deploys.jsonl")
os.makedirs(os.path.dirname(log), exist_ok=True)
if sys.argv[2] != "-":
    with open(log, "w") as f:
        for _ in range(int(sys.argv[2])):
            f.write(json.dumps({"ts": time.time(), "by": "helm-board", "ok": True}) + "\n")
cached = os.environ.get("KB_CACHED") == "1"
w = m.sheep_book(sys.argv[4], "docs/x.md", cached=cached)
print(sum(1 for l in open(log) if '"ok": true' in l), w or "-", m.sheep_cap_words(sys.argv[4], sys.argv[3], cached=cached) or "-")
PY
mkdir -p "$T/kb-cfg/sheep"; echo 2 > "$T/kb-cfg/sheep/machines"
printf '#!/bin/sh\necho "$*" >> "%s/kb-calls"\necho "{\\"pro\\": false, \\"enabled\\": false}"\n' "$T" > "$T/kb-cli"; chmod +x "$T/kb-cli"
kb() { env REGATTA_CONFIG="$T/kb-cfg" REGATTA_SHEEP_DIR="$T/kb-${KB_DIR:-$1}" MEMO_SHEEP_BIN="" ${KB_PLAN:+REGATTA_SHEEP_PLAN=$KB_PLAN} \
         python3 "$T/kbudget.py" "$B/keel" "$1" "$2" "${KB_CLI:-/nonexistent}" 2>&1; }
check "$(KB_PLAN=free kb 10 "space not found")" "11 - -" "under the line: the deploy logged, no warning, an ordinary failure not called the cap"
KB_PLAN=free kb 179 "deploy refused — rate_limited: too many publishes (retry in 3600s)" > "$T/kb.out"
has "$T/kb.out" "keel: 180 spacesheep publishes from this Mac in 24 h, near its part of the account's cap (spacesheep Free: 400 a day, shared by 2 machines" "at 180 on Free over two machines: keel warns, and still deploys"
has "$T/kb.out" "refused for the account's 24-hour publish cap (400 on spacesheep Free, spacesheep.dev/plans; this Mac 180 in 24 h)" "  a cap refusal is named as one"
check "$(grep -c '"ok": false' "$T/kb-179/deploys.jsonl")" "1" "  …and goes in the log, which pauses helm's redeploys too"
check "$(KB_PLAN=free KB_DIR=179 kb - "x" | cut -c1-6)" "181 - " "  the next deploy over the line: no second warning (once per crossing)"
KB_PLAN=free KB_DIR=179 kb 5 "x" > /dev/null; KB_PLAN=free KB_DIR=179 kb 179 "x" > "$T/kb2.out"
has "$T/kb2.out" "keel: 180 spacesheep" "  back under the line, then over again: a new crossing warns again"
KB_DIR=hook KB_CACHED=1 KB_CLI="$T/kb-cli" kb 179 "deploy refused — publish limit reached for 24h" > "$T/kb3.out"
has "$T/kb3.out" "180 keel: 180 spacesheep publishes from this Mac in 24 h, near its part of the account's cap (spacesheep Free, as far as this Mac knows: 400 a day, shared by 2 machines" \
  "the hook's path, no cached plan: Free's line, worded as not known, never 'unknown'"
lacks "$T/kb3.out" "nknown" "  …in the warning and the cap's words alike"
check "$(cat "$T/kb-calls" 2>/dev/null | wc -l | tr -d ' ')" "0" "  …and the CLI is never run there (its 20 s read past the checkpoint's 30 s kill)"
KB_DIR=hand KB_CLI="$T/kb-cli" kb 179 "x" > /dev/null
check "$(cat "$T/kb-calls" 2>/dev/null)" "talk status" "  by hand, over Free's line, the plan is read through the CLI"

echo "sheep — M3, M5, M4, M20, M16, M18: the page's comments, read and kept (2026-10-15)"
# M3: the text form's real shape (2026-10-04, 2026-10-08): a group line, the Co-shepherd's reply with
# the tree glyph on its first body line, a resolved thread. The bot is not Sam, whatever the header.
cat > "$S/comments.txt" <<'EOF'
To answer a thread, call add_comment with parent_id = its first [id: …]; resolve it with resolve_comment and that id.

[on the whole page]
[id: m1] @sam@example.invalid (2026-10-08T10:00:00.000Z)
@spacesheep is this good?
  ↳ [id: m2] @Co-shepherd 🐑 (asked by sam@example.invalid) (2026-10-08T10:01:00.000Z)
  ↳ Yes, the memo is in solid shape.
  A few strengths: the options are clear.
---
[RESOLVED] [id: m3] @sam@example.invalid (2026-10-04T22:03:11.894Z)
I did this now!
---
EOF
rm -f "$S/web-comments.json"
srun sheep pull "$SM" > "$T/m3.out" 2>&1
has "$T/m3.out" "[m1] → open feedback: @spacesheep is this good?" "M3: the root is Sam's words, and nothing of the Co-shepherd's reply comes with it"
lacks "$T/m3.out" "solid shape" "…the reply under a Co-shepherd / asked-by / sheep header is a bot's"
has "$T/m3.out" "resolved on the page, not read: [m3] I did this now!" "…a [RESOLVED] thread is not taken; it is named once (M20)"
check "$(python3 - "$B/keel" "$S/comments.txt" <<'EOF'
import sys
from importlib.machinery import SourceFileLoader as L
m = L("m", sys.argv[1]).load_module()
ts = m.comment_threads(open(sys.argv[2]).read())
print([(t["id"], t["resolved"], [(r["id"], r["bot"], r["text"][:3]) for r in t["replies"]]) for t in ts])
for h in ("@Co-shepherd 🐑 (asked by x@y)", "@robot 🤖", "@x (via co-shepherd)", "@sam@example.invalid (2026-10-08)"):
    print(bool(m.BOT_HEAD_RE.search(h)), end=" ")
EOF
)" "[('m1', False, [('m2', True, 'Yes')]), ('m3', True, [])]
True True True False " "…the parsed shape: the reply is a bot's with its leading ↳ stripped; [RESOLVED] reads as resolved; the other bot headers match, Sam's does not"

# M5: the server's words for a page nobody commented on are an empty page, not a new shape
echo "a real sample, kept" > "$S/state/list_comments.last.txt"
echo "No comments or reactions on this space." > "$S/comments.txt"
srun sheep pull "$SM" > "$T/m5.out" 2>&1
lacks "$T/m5.out" "shape is new" "M5: an empty page prints no 'shape is new' alarm"
check "$(cat "$S/state/list_comments.last.txt")" "a real sample, kept" "…and leaves the last real sample alone"
has "$T/m5.out" "would merge 0 threads" "…and reads as no threads"

# M4: a pull --write whose reply fails part-way took the memo's words in: the next pull must not append them again
cat > "$S/comments.txt" <<'EOF'
{"comments": [
 {"id": "f1", "body": "first loose thought", "created_at": "2026-10-15T09:00:00Z"},
 {"id": "f2", "body": "second loose thought", "created_at": "2026-10-15T09:01:00Z"}
]}
EOF
touch "$S/fail-add"
srun sheep pull --write "$SM" > "$T/m4a.out" 2>&1; rc=$?
rm -f "$S/fail-add"
check "$rc" "1" "M4: a reply that fails after the memo was written ends the pull with rc 1"
check "$(grep -c 'first loose thought' "$SM")" "1" "…the memo holds the first thread's words"
check "$(grep -c 'second loose thought' "$SM")" "1" "…and the second's, though its reply never went"
check "$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); p=[v for k, v in d.items() if k.endswith("docs/s.md")][0]; print(sorted(set(p["taken"]) & {"f1", "f2"}))' "$S/state/sheep.json")" "['f1', 'f2']" "…and both are recorded as taken, not only the one whose reply went"
check "$(python3 -c 'import json,sys; r=[json.loads(l) for l in open(sys.argv[1]) if l.strip()]; print([x["event"] for x in r if x["path"].endswith("/sh/docs/s.md")][-1:])' "$MEMO_STATE_DIR/touches.jsonl")" "['save']" "M16: a pull --write that changed the memo records the touch (as a form Save: status reads event save)"
gitc "$G/sh" commit -qam "two loose thoughts"
srun sheep pull --write "$SM" > "$T/m4b.out" 2>&1
check "$(grep -c 'first loose thought' "$SM") $(grep -c 'second loose thought' "$SM")" "1 1" "the next pull appends nothing twice"
# …and a thread whose words are already in the memo (the failed write was never recorded) is not appended either
python3 -c 'import json,sys; f=sys.argv[1]; d=json.load(open(f)); [v.update(taken=[t for t in v["taken"] if t not in ("f1", "f2")]) for k, v in d.items() if k.endswith("docs/s.md")]; json.dump(d, open(f, "w"))' "$S/state/sheep.json"
srun sheep pull --write "$SM" > "$T/m4c.out" 2>&1
check "$(grep -c 'first loose thought' "$SM") $(grep -c 'second loose thought' "$SM")" "1 1" "M4: with the taken list lost, the pull still drops feedback already in the doc"
has "$T/m4c.out" "[f1] → open feedback" "…while the thread itself is still taken and replied to"
gitc "$G/sh" commit -qam "again" 2>/dev/null

# M20: a reply under a thread already taken, and a thread resolved on the page unread
cat > "$S/comments.txt" <<'EOF'
{"comments": [
 {"id": "f1", "body": "first loose thought", "created_at": "2026-10-15T09:00:00Z", "resolved_at": "2026-10-15T09:30:00Z"},
 {"id": "f1a", "parent_id": "f1", "body": "memo: taken into docs/s.md", "via": "claude", "created_at": "2026-10-15T09:30:00Z"},
 {"id": "f1b", "parent_id": "f1", "body": "wait, I meant the opposite", "created_at": "2026-10-15T11:00:00Z"},
 {"id": "u1", "body": "closed in the viewer, unread", "created_at": "2026-10-15T10:00:00Z", "resolved_at": "2026-10-15T10:05:00Z"}
]}
EOF
srun sheep pull "$SM" > "$T/m20a.out" 2>&1
has "$T/m20a.out" "late reply: [f1] 1 new reply after it was taken, not read: wait, I meant the opposite" "M20: a reply under a taken thread is named"
has "$T/m20a.out" "resolved on the page, not read: [u1] closed in the viewer, unread" "…and a thread resolved in the viewer without being taken is named, not dropped silently"
srun sheep pull "$SM" > "$T/m20b.out" 2>&1
has "$T/m20b.out" "late reply: [f1]" "…a preview records nothing: it names them again"
srun sheep pull --write "$SM" > "$T/m20c.out" 2>&1
has "$T/m20c.out" "late reply: [f1]" "…--write names them"
srun sheep pull "$SM" > "$T/m20d.out" 2>&1
lacks "$T/m20d.out" "late reply" "…once: the next pull has no late reply for it"
lacks "$T/m20d.out" "resolved on the page" "…nor the unread one"
printf '%s\n' '{"comments": [{"id": "f1", "body": "first loose thought", "created_at": "2026-10-15T09:00:00Z", "resolved_at": "2026-10-15T09:30:00Z"}, {"id": "f1b", "parent_id": "f1", "body": "wait, I meant the opposite", "created_at": "2026-10-15T11:00:00Z"}, {"id": "f1c", "parent_id": "f1", "body": "and one more", "created_at": "2026-10-15T12:00:00Z"}]}' > "$S/comments.txt"
srun sheep pull "$SM" > "$T/m20e.out" 2>&1
has "$T/m20e.out" "late reply: [f1] 1 new reply after it was taken, not read: and one more" "…a further reply is a new late reply"
rm -f "$S/state/list_comments.last.txt"
gitc "$G/sh" checkout -q -- docs/s.md

# M18: prune drops the pins of branches gone from origin and over 14 days old, with their page folders; local state only
PS="$T/prune-state"; mkdir -p "$PS"
python3 - "$B/keel" "$PS" "$G/sh" <<'EOF'
import json, os, sys
os.environ["MEMO_SHEEP_STATE"] = sys.argv[2]
from importlib.machinery import SourceFileLoader as L
m = L("m", sys.argv[1]).load_module()
top = sys.argv[3]
old = "2026-09-01T00:00:00+00:00"
pins = {
 "sh@claude/gone:docs/a.md": {"branch": "claude/gone", "deployed": old, "repo_path": top, "space": "s1"},
 "sh@claude/sh:docs/s.md": {"branch": "claude/sh", "deployed": old, "repo_path": top, "space": "s2"},
 "sh@claude/young:docs/y.md": {"branch": "claude/young", "deployed": "2026-10-14T00:00:00+00:00", "repo_path": top, "space": "s3"},
 "nowhere@claude/x:docs/z.md": {"branch": "claude/x", "deployed": old, "repo_path": top + "-missing", "space": "s4"},
 "sh@claude/lost:docs/l.md": {},
}
os.makedirs(os.path.join(sys.argv[2]), exist_ok=True)
json.dump(pins, open(os.path.join(sys.argv[2], "sheep.json"), "w"))
for k in pins:
    d = m.page_dir(k); d.mkdir(parents=True, exist_ok=True); (d / "index.html").write_text("x")
EOF
pr() { (export MEMO_SHEEP_STATE="$PS" MEMO_NOW=2026-10-15T12:00:00Z; run sheep "$@"); }
NCALL=$(wc -l < "$S/mcp.log")
pr prune --dry-run > "$T/pr1.out" 2>&1; rc=$?
check "$rc" "0" "M18: prune --dry-run"
has "$T/pr1.out" "would drop sh@claude/gone:docs/a.md: branch claude/gone gone, deployed 44 days ago" "…names the pin whose branch is gone and old"
has "$T/pr1.out" "would drop sh@claude/lost:docs/l.md: an empty pin" "…and an empty pin"
lacks "$T/pr1.out" "claude/sh:docs/s.md" "…keeps a pin whose branch lives"
lacks "$T/pr1.out" "claude/young" "…and one deployed within 14 days"
lacks "$T/pr1.out" "nowhere@" "…and one whose repo cannot be found"
has "$T/pr1.out" "2 pins to drop, 3 kept" "…and counts them"
check "$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))))' "$PS/sheep.json")" "5" "…a dry run drops nothing"
pr prune > "$T/pr2.out" 2>&1
has "$T/pr2.out" "2 pins dropped, 3 kept" "prune drops them"
check "$(python3 -c 'import json,sys; print(sorted(json.load(open(sys.argv[1]))))' "$PS/sheep.json")" "['nowhere@claude/x:docs/z.md', 'sh@claude/sh:docs/s.md', 'sh@claude/young:docs/y.md']" "…leaving the others in the file"
check "$(ls "$PS/pages" | wc -l | tr -d ' ')" "3" "…and removes the dropped pins' page folders"
check "$(wc -l < "$S/mcp.log")" "$NCALL" "…without a call to spacesheep"

echo "sheep — review 2026-10-16: one-word notes, the line while uncommitted, a mirror's via, a second Save from one page load"
# S2: a note "Keep" and feedback "Mirror" are words of the memo itself ("Keep" a table cell, "Mirror me" its title);
# a substring match called them already taken and dropped them while resolving their threads
cat > "$S/comments.txt" <<EOF
{"comments": [
 {"id": "k1", "body": "Keep", "anchor_id": "$PID", "created_at": "2026-10-16T09:00:00Z"},
 {"id": "k2", "body": "Mirror", "created_at": "2026-10-16T09:01:00Z"}
]}
EOF
srun sheep pull --write "$SM" > "$T/s2a.out" 2>&1
check "$(grep -c "^\*\*Sam, $(date +%F):\*\* Keep$" "$SM")" "1" "S2: a one-word note that is also a word of the memo is written, not judged already there"
check "$(grep -c "^\*\*Sam, $(date +%F):\*\* Mirror$" "$SM")" "1" "…and so is one-word feedback"
gitc "$G/sh" commit -qam "one-word notes"
srun sheep pull --write "$SM" > "$T/s2b.out" 2>&1
check "$(grep -c "^\*\*Sam, $(date +%F):\*\* Keep$" "$SM")" "1" "…and neither is written twice by the next pull"
python3 -c 'import json,sys; f=sys.argv[1]; d=json.load(open(f)); [v.update(taken=[t for t in v.get("taken", []) if t not in ("k1", "k2")]) for k, v in d.items() if k.endswith("docs/s.md")]; json.dump(d, open(f, "w"))' "$S/state/sheep.json"
printf '{"comments": [{"id": "k1", "body": "Keep", "anchor_id": "%s"}, {"id": "k2", "body": "Mirror"}]}\n' "$PID" > "$S/comments.txt"
srun sheep pull --write "$SM" > /dev/null 2>&1
check "$(grep -c "^\*\*Sam, $(date +%F):\*\* Keep$" "$SM")" "1" "…and a real duplicate (taken list lost, words in the memo as merge writes them) is still dropped"
gitc "$G/sh" reset -q --hard HEAD~1

# S2: `memo line` on a claude/* branch with the doc uncommitted is pending, not a failed deploy: the pin's page, or a
# missing form that makes the Stop hook ask again — never a memo serve form the hook then accepts
echo "an edit not committed yet" >> "$SM"
srun line "$SM" > "$T/s2n.out" 2> "$T/s2n.err"
has "$T/s2n.out" "[course](https://spacesheep.dev/@sam/memo)" "S2: line with the doc uncommitted prints the pin's page as the form"
lacks "$T/s2n.out" "127.0.0.1" "…not a memo serve form"
has "$T/s2n.err" "the page shows the previous commit" "…and says the page is the previous commit"
gitc "$G/sh" checkout -q -- docs/s.md
cp "$SM" "$G/sh/docs/np.md"; gitc "$G/sh" add docs/np.md; gitc "$G/sh" commit -qm "np"
echo "an edit not committed yet" >> "$G/sh/docs/np.md"
srun line "$G/sh/docs/np.md" > "$T/s2m.out" 2> "$T/s2m.err"; rc=$?
lacks "$T/s2m.out" "[course]" "…with no page yet: no course link"
lacks "$T/s2m.out" "127.0.0.1" "…and no memo serve one"
has "$T/s2m.err" "keel line: no course — docs/np.md has uncommitted changes" "…the form is missing, with the reason"
check "$rc" "1" "…exit 1: the form is owed, so the Stop hook asks again once the checkpoint deploys it"
gitc "$G/sh" checkout -q -- docs/np.md; gitc "$G/sh" reset -q --hard HEAD~1
LREPLY="[course](http://127.0.0.1:1/x/) | [github](https://github.com/owner/repo/blob/claude/sh/docs/s.md) — [s.md]($(cd "$G/sh/docs" && pwd -P)/s.md#L1)"
check "$(MEMO_SHEEP_BIN="$S/bin/spacesheep" SPACESHEEP_KEY=ss_test MEMO_SHEEP_STATE="$S/state" python3 -c 'import sys; from importlib.machinery import SourceFileLoader as L; m = L("m", sys.argv[1]).load_module(); print(" / ".join(m.line_findings(sys.argv[3], sys.argv[2])))' "$B/keel" "$SM" "$LREPLY" | grep -o "the course link is a memo serve form, but this doc has a spacesheep page")" "the course link is a memo serve form, but this doc has a spacesheep page" "the hook refuses a memo serve form link for a doc that has a page"

# S2: a comment through the localhost mirror may carry a via other than null; only known agents are not Sam's words
cat > "$S/web-comments.json" <<'EOF'
{"comments": [
 {"id": "x1", "parent_id": null, "author_email": "i@x", "body": "from the mirror", "anchor_id": null, "resolved_at": null, "created_at": "2026-10-16T10:00:00Z", "via": "mirror"},
 {"id": "x2", "parent_id": null, "author_email": "i@x", "body": "from the shepherd", "anchor_id": null, "resolved_at": null, "created_at": "2026-10-16T10:01:00Z", "via": "co-shepherd"}
], "reactions": [], "anchor_reactions": []}
EOF
srun sheep pull "$SM" > "$T/s2v.out" 2>&1
has "$T/s2v.out" "[x1] → open feedback: from the mirror" "S2: an unknown via is read as Sam's words"
has "$T/s2v.out" "comment [x1] came via 'mirror', not a known agent — read as Sam's words" "…and named, so a wrong guess shows"
lacks "$T/s2v.out" "from the shepherd" "…while a known agent's is still not"
rm -f "$S/web-comments.json"

long=$(printf 'x%.0s' $(seq 250))
printf '# %s\n\n- **D1 — Ship it?** Body.\n  ➤ Recommended: yes\n  ➤ Answer:\n\n---\n' "$long" > "$G/sh/docs/long.md"
gitc "$G/sh" add docs/long.md; gitc "$G/sh" commit -qm "long title"
srun sheep "$G/sh/docs/long.md" > /dev/null 2>&1
has "$S/cli.log" "--title $(printf 'x%.0s' $(seq 199))… -m" "a title over spacesheep's 200 characters goes as its first 199 and an ellipsis (2026-10-13)"

echo "sheep — the page's Save: pull takes it, wait wakes on it (2026-10-14)"
gitc "$G/sh" checkout -q -- docs/s.md
printf '{"comments": [{"id": "q1", "body": "B please", "anchor_id": "D2", "created_at": "2026-10-14T09:00:00Z"}]}\n' > "$S/comments.txt"
cat > "$S/events.json" <<'EOF'
[{"seq": 1, "at": "2026-10-14T09:40:00.000Z", "name": "memo-pick", "data": {"d": "D1"}, "from": {"name": "sam"}},
 {"seq": 2, "at": "2026-10-14T09:43:33.805Z", "name": "memo-save", "from": {"name": "sam", "seed": "1e"},
  "data": {"sha": "abc", "items": {"D2": "A - the page's pick", "D1": ""}, "comments": [{"at": 2, "row": "", "quote": "Some context worth a note.", "text": "from the page"}],
           "feedback": "sent from the phone", "savedAt": "2026-10-14T09:43:33Z"}}]
EOF
: > "$S/mcp.log"
srun sheep pull "$SM" > "$T/v1.out" 2>&1; rc=$?
check "$rc" "0" "pull previews a Save from the page"
has "$T/v1.out" "[save 2, 2026-10-14 09:43, by sam] → D2, 1 note, feedback" "…naming what it carries; the other event and the empty D1 are not answers"
has "$T/v1.out" "kept open: [q1] D2 answered by the page's Save" "…a comment on the decision the Save answers is superseded, not taken"
has "$T/v1.out" "would merge 0 threads and 1 Save from the page" "…the count says so"
check "$(git -C "$G/sh" status --porcelain docs/s.md)" "" "…a preview writes nothing"
srun sheep pull --write "$SM" > "$T/v2.out" 2>&1; rc=$?
check "$rc" "0" "pull --write takes the Save"
check "$(grep -A2 '➤ Recommended: B' "$SM" | tail -1)" "  A - the page's pick" "…D2's answer is the page's"
has "$SM" "**Sam, $(date +%F):** sent from the phone" "…and its feedback"
check "$(grep -A2 '^Some context' "$SM" | tail -1)" "**Sam, $(date +%F):** from the page" "…and its note, under its line"
check "$(python3 -c 'import json,sys; r=[json.loads(l) for l in open(sys.argv[1]) if l.strip()]; print([x["event"] for x in r if x["path"].endswith("/sh/docs/s.md")][-1:])' "$MEMO_STATE_DIR/touches.jsonl")" "['save']" "…and records the touch a form Save did: the doc no longer stands (F9)"
has "$S/mcp.log" '"parent_id": "q1"' "…the superseded comment is replied to and marked taken, so no later pull reverts D2"
check "$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); p=[v for k, v in d.items() if k.endswith("docs/s.md")][0]; print(p["events_after"], len(p["saves"]))' "$S/state/sheep.json")" "2 0" "…the cursor past both events, no Save left pending"
# the receipt (2026-10-20): the pin keeps it for the next deploy, and every open tab gets it at once
check "$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); r=[v for k, v in d.items() if k.endswith("docs/s.md")][0]["receipt"]; print(r["saves"], r["what"], r["refused"], r["at"][:4])' "$S/state/sheep.json")" \
      "['2026-10-14T09:43:33Z'] D2, 1 note, the feedback [] $(date +%Y)" "…and keeps a receipt: the Save's own time, what the doc took"
check "$(grep '"live_push"' "$S/mcp.log" | python3 -c 'import json,sys; a=json.loads(sys.stdin.readline())["params"]["arguments"]["edits"][0]; print(a["anchor"], a["op"], "data-receipt=" in a["html"], "09:43:33Z" in a["html"])')" \
      "keel-receipt replace True True" "…pushed to the page's receipt block on every open tab (live_push)"
has "$T/v2.out" "receipt: pushed to the page" "…and says so"
lacks "$T/v1.out" "receipt:" "…a preview sends none"
gitc "$G/sh" commit -qam "answers from the page"
srun sheep pull "$SM" > "$T/v3.out" 2>&1
has "$T/v3.out" "would merge 0 threads — " "a Save is taken once"

cat > "$S/events.json" <<'EOF'
[{"seq": 3, "at": "2026-10-14T10:00:00Z", "name": "memo-save", "data": {"items": {"D1": "later, on Friday"}, "comments": [], "feedback": ""}}]
EOF
srun sheep wait "$SM" --idle 20 > "$T/w1.out" 2>&1; rc=$?
check "$rc" "0" "wait exits when a Save is in the room (the exit wakes the session)"
has "$T/w1.out" "memo sheep wait: a Save from the page — taking it in" "…saying what woke it"
check "$(grep -A1 'D1 — Ship it' "$SM" | tail -1)" "  ➤ Answer: later, on Friday" "…with the Save in the memo"
has "$T/w1.out" "next: commit docs/s.md on claude/sh" "…and the next step named"
gitc "$G/sh" commit -qam "D1 from the page"

srun sheep wait "$SM" --idle 0 > "$T/w2.out" 2>&1; rc=$?
check "$rc" "0" "wait with nothing on the page stops at --idle"
has "$T/w2.out" "nothing on the page in 0 min" "…and says nothing came"

printf '{"comments": [{"id": "old", "body": "said before the wait"}]}\n' > "$S/comments.txt"
srun sheep wait "$SM" --idle 20 --poll 1 --quiet 1 > "$T/w3.out" 2>&1 &
wpid=$!
sleep 1.5
srun sheep wait "$SM" --idle 5 > "$T/w4.out" 2>&1
has "$T/w4.out" "another wait already listens" "a second wait on the same page steps aside"
printf '{"comments": [{"id": "old", "body": "said before the wait"}, {"id": "new1", "body": "and one more thing", "anchor_id": "D1", "created_at": "2099-01-01T00:00:00Z"}]}\n' > "$S/comments.txt"
for _ in $(seq 100); do kill -0 "$wpid" 2>/dev/null || break; sleep 0.1; done
check "$(kill -0 "$wpid" 2>/dev/null && echo running || echo exited)" "exited" "wait exits on a new comment once the comments go quiet"
kill "$wpid" 2>/dev/null
has "$T/w3.out" "memo sheep wait: 1 new comment thread — taking it in" "…one new thread: the one open before the wait is not new"
check "$(grep -A1 'D1 — Ship it' "$SM" | tail -1)" "  ➤ Answer: and one more thing" "…and the comment is taken into the memo"
gitc "$G/sh" checkout -q -- docs/s.md
rm -f "$S/events.json"

echo "sheep — threads kept, anchors carried, successors in place (docs/sheep-threads-2026-10-24.md)"
# a helper module call: python3 "$KP" <keel> <fn-body> reads sys.argv; written to a file, never a quoted heredoc in "$(…)" (bash 3.2)
KP="$T/kp.py"
cat > "$KP" <<'PY'
import json, os, sys
from importlib.machinery import SourceFileLoader as L
m = L("m", sys.argv[1]).load_module()
what, args = sys.argv[2], sys.argv[3:]
if what == "ids":  # the blocks of a page: id and quote, one per line
    for b in m.live_blocks(open(args[0]).read()):
        print("%s\t%s" % (b[0], b[1]))
elif what == "pin":  # one field of one pin, as JSON
    print(json.dumps((m.pins().get(args[0]) or {}).get(args[1]), sort_keys=True))
elif what == "match":  # carry_match over (id, quote, row, at) rows given as JSON
    print(json.dumps(m.carry_match(*json.loads(args[0])), sort_keys=True))
elif what == "ratio":
    import difflib
    print("%.2f" % difflib.SequenceMatcher(None, args[0], args[1], autojunk=False).ratio())
elif what == "openwords":
    pin = m.pins().get(args[0]) or {}
    threads = m.comment_threads(json.load(open(args[1])))
    print(sorted(m.open_words(threads, pin)))
elif what == "blob":
    print(json.dumps(m.sheep_blob(args[0])[2]))
elif what == "family":
    print(m.id_family(args[0]))
elif what == "late":  # late_replies over a comments file, the thread ids in args[0] taken: [(thread id, [reply ids])]
    th = m.comment_threads(json.load(open(args[1])))
    print(json.dumps([(t["id"], [r["id"] for r in rs]) for t, rs in m.late_replies(th, {}, set(args[0].split()))]))
elif what == "shifts":  # repeat_shifts over (id, quote, row, at) rows given as JSON
    print(json.dumps(m.repeat_shifts(*json.loads(args[0])), sort_keys=True))
elif what == "routetimeout":  # a socket that takes the connection and never answers (finding 13)
    import socket
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    s.listen(5)
    m.SHEEP_APP = "http://127.0.0.1:%d" % s.getsockname()[1]
    try:
        m.sheep_comments(None, "k", "sp", timeout=1, fallback=False)
    except m.Stop as e:
        print(e, "failed" in m._WEB)
PY
kp() { (export SHEEP_T="$S" MEMO_SHEEP_BIN="$S/bin/spacesheep" MEMO_SHEEP_STATE="$S/state" SPACESHEEP_KEY=ss_test \
          MEMO_SHEEP_MCP="http://127.0.0.1:$(cat "$S/port")/mcp" MEMO_SHEEP_APP="http://127.0.0.1:$(cat "$S/port")"; python3 "$KP" "$B/keel" "$@"); }
# finish review (2026-10-25): the "line is gone" reply is no take, so an owner's reply typed before it is still late
cat > "$T/late.json" <<'EOF'
{"comments": [
 {"id": "L1", "parent_id": null, "body": "first", "anchor_id": "D1", "resolved_at": null, "created_at": "2026-10-25T09:00:00Z", "via": null},
 {"id": "L1a", "parent_id": "L1", "body": "memo: taken into docs/x.md as D1's answer", "via": "claude", "created_at": "2026-10-25T09:01:00Z"},
 {"id": "L1b", "parent_id": "L1", "body": "actually B", "via": null, "created_at": "2026-10-25T09:02:00Z"},
 {"id": "L1c", "parent_id": "L1", "body": "memo: the line this was on is gone from the page", "via": "claude", "created_at": "2026-10-25T09:03:00Z"}
]}
EOF
check "$(kp late L1 "$T/late.json")" '[["L1", ["L1b"]]]' "finish review: a reply typed before the gone-reply is still late (only a take's reply counts as the ack)"
TK="sh@claude/sh:docs/t.md"
cat > "$G/sh/docs/t.md" <<'EOF'
# Carry me

Alpha line that stays put.

Beta line about the cache warming on Monday morning.

Gamma line that will be rewritten entirely.

- **D1 — Go?** Body.

  ➤ Recommended: yes

  ➤ Answer:

---
EOF
gitc "$G/sh" add docs/t.md; gitc "$G/sh" commit -qm "carry me"
srun sheep "$G/sh/docs/t.md" > "$T/k1.out" 2>&1
kp ids "$S/page.html" > "$T/k1.ids"
BETA=$(grep 'Beta line' "$T/k1.ids" | cut -f1); GAMMA=$(grep 'Gamma line' "$T/k1.ids" | cut -f1); ALPHA=$(grep 'Alpha line' "$T/k1.ids" | cut -f1)
check "$(echo "$BETA $GAMMA" | grep -cE '^b-[0-9a-f]{8} b-[0-9a-f]{8}$')" "1" "B: the first page names each block by its line's hash"
# A: a taken thread stays open, and a reply under it after the take is still named and still wakes a wait
cat > "$S/web-comments.json" <<EOF
{"comments": [
 {"id": "a1", "parent_id": null, "body": "yes, go", "anchor_id": "D1", "resolved_at": null, "created_at": "2026-10-24T10:00:00Z", "via": null},
 {"id": "kb", "parent_id": null, "body": "Monday is too early", "anchor_id": "$BETA", "resolved_at": null, "created_at": "2026-10-24T10:01:00Z", "via": null},
 {"id": "kg", "parent_id": null, "body": "gamma needs a source", "anchor_id": "$GAMMA", "resolved_at": null, "created_at": "2026-10-24T10:02:00Z", "via": null}
]}
EOF
n0=$(grep -c '"resolve_comment"' "$S/mcp.log")
srun sheep pull --write "$G/sh/docs/t.md" > "$T/k2.out" 2>&1; rc=$?
check "$rc" "0" "A: pull --write takes the three threads"
has "$T/k2.out" "replied in 3 threads, left open" "…replies in each and says they stay open"
check "$(grep -c '"resolve_comment"' "$S/mcp.log")" "$n0" "…and resolves none"
gitc "$G/sh" commit -qam "taken"
# a1r is dated after the commit above, as a real late reply is: one older than the doc's commit loses to git (git_answer_since)
cat > "$S/web-comments.json" <<EOF
{"comments": [
 {"id": "a1", "parent_id": null, "body": "yes, go", "anchor_id": "D1", "resolved_at": null, "created_at": "2026-10-24T10:00:00Z", "via": null},
 {"id": "a1m", "parent_id": "a1", "body": "memo: taken into docs/t.md as D1's answer", "anchor_id": null, "resolved_at": null, "created_at": "2026-10-24T10:05:00Z", "via": "claude"},
 {"id": "a1r", "parent_id": "a1", "body": "on second thought, wait", "anchor_id": null, "resolved_at": null, "created_at": "2030-01-01T11:00:00Z", "via": null},
 {"id": "kb", "parent_id": null, "body": "Monday is too early", "anchor_id": "$BETA", "resolved_at": null, "created_at": "2026-10-24T10:01:00Z", "via": null},
 {"id": "kg", "parent_id": null, "body": "gamma needs a source", "anchor_id": "$GAMMA", "resolved_at": null, "created_at": "2026-10-24T10:02:00Z", "via": null}
]}
EOF
srun sheep pull "$G/sh/docs/t.md" > "$T/k3.out" 2>&1
has "$T/k3.out" "would merge 1 thread " "A: an open thread already taken is not taken again (the pin's taken, not the thread's state)…"
has "$T/k3.out" "[a1] → D1: on second thought, wait" "R11: …while the owner's reply under it is taken in, as D1's answer"
lacks "$T/k3.out" "late reply:" "…and not merely named as late"
check "$(kp openwords "$TK" "$S/web-comments.json")" "['a1+late']" "…and wakes a wait (open_words), while the taken threads count for nothing"
cp "$S/state/sheep.json" "$T/k3.pins"
python3 -c 'import json,sys; f=sys.argv[1]; d=json.load(open(f)); d[sys.argv[2]]["taken"]=[]; json.dump(d, open(f, "w"))' "$S/state/sheep.json" "$TK"
srun sheep pull "$G/sh/docs/t.md" > "$T/k3b.out" 2>&1
has "$T/k3b.out" "would merge 3 threads" "A: a pin that lost its taken still skips the thread holding this tool's taken-into reply…"
has "$T/k3b.out" "[a1] → D1: on second thought, wait" "R2: …and takes the reply under it as late, not the root again"
check "$(kp openwords "$TK" "$S/web-comments.json")" "['a1+late', 'kb', 'kg']" "R2: open_words reads the taken-into reply too: the thread wakes a wait only for its late reply"
cp "$T/k3.pins" "$S/state/sheep.json"
# R2: the old c1 fixture — a taken-into reply with no time, the owner's reply after it, no pin at all
cat > "$T/c1old.json" <<'EOF'
{"comments": [
 {"id": "c1r", "body": "and tell Alex", "parent_id": "c1", "created_at": "2026-10-03T21:01:00Z"},
 {"id": "c1", "body": "no — wait for Monday", "anchor_id": "D1", "created_at": "2026-10-03T21:00:00Z", "resolved": false,
  "replies": [{"id": "c1b", "body": "memo: taken into docs/s.md", "is_bot": true}]}
]}
EOF
check "$(kp openwords "nopin@claude/x:docs/none.md" "$T/c1old.json")" "['c1+late']" "R2: with no pin, a thread taken by its reply is no open thread, and the reply after it is late"
srun sheep pull --write "$G/sh/docs/t.md" > "$T/k3w.out" 2>&1
check "$(sed -n '/➤ Answer:/,/^---/p' "$G/sh/docs/t.md" | grep -o -e 'yes, go' -e 'on second thought, wait' | wc -l | tr -d ' ')" "2" "R11: --write puts the thread's words again as D1's answer, the reply after the root"
gitc "$G/sh" commit -qam "late reply taken"
srun sheep pull "$G/sh/docs/t.md" > "$T/k3c.out" 2>&1
has "$T/k3c.out" "would merge 0 threads" "…once: the take records the reply as seen"
# B: an edited line keeps its id and so its thread; a rewritten one gets one reply; the rest untouched
sedi -e 's/Monday morning/Tuesday morning/' -e 's/^Gamma line that will be rewritten entirely\./Completely different words, about the budget./' "$G/sh/docs/t.md"
gitc "$G/sh" commit -qam "edit beta, rewrite gamma"; TSHA=$(git -C "$G/sh" log -1 --format=%h -- docs/t.md)
srun sheep "$G/sh/docs/t.md" > "$T/k4.out" 2>&1; rc=$?
check "$rc" "0" "B: the redeploy"
kp ids "$S/page.html" > "$T/k4.ids"
check "$(grep "^$BETA	" "$T/k4.ids" | cut -f2)" "Beta line about the cache warming on Tuesday morning." "B: the edited line inherits the commented id"
check "$(grep -c "^$GAMMA	" "$T/k4.ids")" "0" "…the rewritten one does not (below the ratio)"
check "$(grep "^$ALPHA	" "$T/k4.ids" | cut -f2)" "Alpha line that stays put." "…and an untouched line keeps its own"
check "$(kp ratio 'Beta line about the cache warming on Monday morning.' 'Beta line about the cache warming on Tuesday morning.') $(kp ratio 'Gamma line that will be rewritten entirely.' 'Completely different words, about the budget.')" "0.93 0.20" "…the two ratios, against CARRY_RATIO 0.6"
check "$(kp pin "$TK" ss | python3 -c 'import json,sys; print(json.load(sys.stdin)[sys.argv[1]]["quote"])' "$BETA")" "Beta line about the cache warming on Tuesday morning." "…the pin maps the inherited id to the new line, for merge"
check "$(grep '"add_comment"' "$S/mcp.log" | grep -c "the line this was on is gone from $TSHA; the thread stays here")" "1" "B: the thread on the rewritten line gets one memo: reply naming the commit"
has "$S/mcp.log" '"parent_id": "kg", "body": "memo: the line this was on is gone' "…in that thread"
# the reply is on the page now; a later deploy edits another line and must not reply twice, nor drop the inherited id
python3 - "$S/web-comments.json" "$TSHA" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["comments"].append({"id": "kgm", "parent_id": "kg", "body": "memo: the line this was on is gone from %s; the thread stays here." % sys.argv[2], "via": "claude", "created_at": "2026-10-24T12:00:00Z"})
json.dump(d, open(sys.argv[1], "w"))
PY
python3 -c 'import json,sys; f=sys.argv[1]; d=json.load(open(f)); d[sys.argv[2]]["ss"]={}; json.dump(d, open(f, "w"))' "$S/state/sheep.json" "$TK"
sedi -e 's/Tuesday morning/Tuesday at nine/' -e 's/^Alpha line that stays put\./Alpha line that stays put, mostly./' "$G/sh/docs/t.md"
gitc "$G/sh" commit -qam "edit beta again"
srun sheep "$G/sh/docs/t.md" > "$T/k5.out" 2>&1
kp ids "$S/page.html" > "$T/k5.ids"
check "$(grep "^$BETA	" "$T/k5.ids" | cut -f2)" "Beta line about the cache warming on Tuesday at nine." "B: a second edit keeps the inherited id: read back from the live page, with the pin's ss emptied (the other Mac's deploy)"
check "$(grep -c "^$ALPHA	" "$T/k5.ids")" "0" "…while an edited line nobody commented on takes its new hash"
check "$(grep '"add_comment"' "$S/mcp.log" | grep -c 'the line this was on is gone')" "1" "…and the orphaned thread is not told twice"
# carry_match: one-to-one, best ratio first, the nearer line breaking a tie, the row label kept apart
check "$(kp match '[[["o1","the cache warms at nine","",3],["o2","the cache warms at ten","",9]],[["n1","the cache warms at nine!","",4],["n2","the cache warms at noon","",20]],["o1","o2"]]')" '{"n1": "o1", "n2": "o2"}' "carry_match: each old id to one new block, the best ratio first"
check "$(kp match '[[["o1","same words here","",3]],[["n1","same words here.","",30],["n2","same words here.","",4]],["o1"]]')" '{"n2": "o1"}' "…a tie goes to the nearer line"
check "$(kp match '[[["o1","a cell","Keep",3]],[["n1","a cell","Drop",3]],["o1"]]')" '{}' "…and never across row labels"
check "$(kp match '[[["o1","a line","",3],["o2","a line","",5]],[["o1","a line","",3],["n2","a line!","",5]],["o2"]]')" '{"n2": "o2"}' "…an id still rendered is not gone, and only a commented one is carried"
# a live page that will not read: the deploy goes on, the carry waits for the next one
touch "$S/read-fail"
sedi -e 's/Tuesday at nine/Tuesday at ten/' "$G/sh/docs/t.md"; gitc "$G/sh" commit -qam "edit beta, read fails"
srun sheep "$G/sh/docs/t.md" > "$T/k6.out" 2>&1; rc=$?
rm -f "$S/read-fail"
check "$rc" "0" "B: a live page that does not read still deploys"
has "$T/k6.out" "the comments' anchors not carried this time (the live page did not read" "…and says the carry waits"
sedi -e 's/^Alpha line that stays put, mostly\./Alpha line that stays put, mostly, again./' "$G/sh/docs/t.md"; gitc "$G/sh" commit -qam "edit alpha after the skipped carry"
srun sheep "$G/sh/docs/t.md" > "$T/k7.out" 2>&1
kp ids "$S/page.html" > "$T/k7.ids"
check "$(grep "^$BETA	" "$T/k7.ids" | cut -f2)" "Beta line about the cache warming on Tuesday at ten." "B: the next deploy catches the skipped carry up: the heir published under its own id takes the commented id back"
check "$(grep '"add_comment"' "$S/mcp.log" | grep -c 'the line this was on is gone')" "1" "…and tells no thread its line is gone"
check "$(kp match '[[["o1","- A — land it now","",3]],[["n1","- B — hold it now","",3]],["o1"]]')" '{}' "carry_match: a short line carries only as a near-copy (0.82 here, CARRY_SHORT_RATIO 0.88)"
gitc "$G/sh" reset -q --hard HEAD~2
rm -f "$S/web-comments.json"

# R1, R8, R9 (the second landing review): a thread told its line is gone stays put, and costs no read;
# a repeated line keeps its copy's number when an earlier copy goes
cat > "$G/sh/docs/t2.md" <<'EOF'
# Repeat and delete

Delta line about the deploy on Friday evening.

Delta line about the deploy on Sunday evening.

Echo line about the weekly budget review meeting.

Same line twice.

Filler between the two copies of the line.

Same line twice.

- **D1 — Go?** Body.

  ➤ Recommended: yes

  ➤ Answer:

---
EOF
gitc "$G/sh" add docs/t2.md; gitc "$G/sh" commit -qm "repeat and delete"
srun sheep "$G/sh/docs/t2.md" > "$T/r1a.out" 2>&1
kp ids "$S/page.html" > "$T/r1a.ids"
FRI=$(grep 'Friday' "$T/r1a.ids" | cut -f1); SUN=$(grep 'Sunday' "$T/r1a.ids" | cut -f1); ECHO=$(grep 'Echo line' "$T/r1a.ids" | cut -f1)
SAME1=$(grep 'Same line twice' "$T/r1a.ids" | sed -n 1p | cut -f1); SAME2=$(grep 'Same line twice' "$T/r1a.ids" | sed -n 2p | cut -f1)
check "$SAME2" "$SAME1-2" "R9: a repeated line's second copy is numbered -2"
cat > "$S/web-comments.json" <<EOF
{"comments": [
 {"id": "rf", "parent_id": null, "body": "friday is wrong", "anchor_id": "$FRI", "resolved_at": null, "created_at": "2026-10-24T10:00:00Z", "via": null},
 {"id": "re", "parent_id": null, "body": "echo needs a number", "anchor_id": "$ECHO", "resolved_at": null, "created_at": "2026-10-24T10:01:00Z", "via": null},
 {"id": "rs", "parent_id": null, "body": "the second copy is the one", "anchor_id": "$SAME2", "resolved_at": null, "created_at": "2026-10-24T10:02:00Z", "via": null}
]}
EOF
python3 - "$G/sh/docs/t2.md" <<'PY'
import sys
f = sys.argv[1]
lines = open(f).read().split("\n")
lines = [l for l in lines if "Friday evening" not in l]
del lines[lines.index("Same line twice.")]
open(f, "w").write("\n".join(lines))
PY
gitc "$G/sh" commit -qam "drop friday and the first copy"
srun sheep "$G/sh/docs/t2.md" > "$T/r1b.out" 2>&1
kp ids "$S/page.html" > "$T/r1b.ids"
check "$(grep "^$SAME2	" "$T/r1b.ids" | cut -f2)" "Same line twice." "R9: deleting a repeated line's first copy leaves the second copy its number, and so its thread"
check "$(grep -c "^$SAME1	" "$T/r1b.ids")" "0" "…the deleted copy's number is on no block"
check "$(grep '"add_comment"' "$S/mcp.log" | grep -c '"parent_id": "rs"')" "0" "…and the second copy's thread gets no false \"gone\" reply"
check "$(grep '"add_comment"' "$S/mcp.log" | grep '"parent_id": "rf"' | grep -c 'the line this was on is gone')" "1" "R1: the deleted line's thread is told once"
python3 - "$S/web-comments.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["comments"].append({"id": "rfm", "parent_id": "rf", "body": "memo: the line this was on is gone from abc1234; the thread stays here.", "via": "claude", "created_at": "2026-10-24T12:00:00Z"})
json.dump(d, open(sys.argv[1], "w"))
PY
sedi -e 's/weekly budget/monthly budget/' "$G/sh/docs/t2.md"; gitc "$G/sh" commit -qam "edit echo"
srun sheep "$G/sh/docs/t2.md" > "$T/r1c.out" 2>&1
kp ids "$S/page.html" > "$T/r1c.ids"
check "$(grep "^$SUN	" "$T/r1c.ids" | cut -f2)" "Delta line about the deploy on Sunday evening." "R1: a told thread does not move to a similar line (0.93) at a later deploy: the Sunday line keeps its own id"
check "$(grep -c "^$FRI	" "$T/r1c.ids")" "0" "…the gone line's id is on no block"
check "$(grep "^$ECHO	" "$T/r1c.ids" | cut -f2)" "Echo line about the monthly budget review meeting." "…while the edited, commented line still inherits its id"
check "$(grep '"add_comment"' "$S/mcp.log" | grep -c '"parent_id": "rf"')" "1" "…and the told thread is not told twice"
check "$(kp match '[[["o1","the cache warms at nine","",3]],[["n1","the cache warms at nine!","",4]],["o1","n1"]]')" '{}' "R1: carry_match never makes a block whose own id comments name another thread's heir"
# R8: with only the told thread's id missing, a deploy reads no live page
python3 - "$S/web-comments.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["comments"] = [c for c in d["comments"] if c["id"] in ("rf", "rfm")]
json.dump(d, open(sys.argv[1], "w"))
PY
n0=$(grep -c '^read' "$S/cli.log")
sedi -e 's/two copies of the line/two copies of that line/' "$G/sh/docs/t2.md"; gitc "$G/sh" commit -qam "edit the filler"
srun sheep "$G/sh/docs/t2.md" > "$T/r1d.out" 2>&1; rc=$?
check "$rc $(grep -c '^read' "$S/cli.log")" "0 $n0" "R8: a told thread is no reason to read the live page on every later deploy"
rm -f "$S/web-comments.json"

# C1: a renamed doc deploys into its old page; the old pin points at it
python3 -c 'import json,sys; f=sys.argv[1]; d=json.load(open(f)); d[sys.argv[2]]["space"]="sp-t"; json.dump(d, open(f, "w"))' "$S/state/sheep.json" "$TK"
mkdir -p "$G/sh/docs/record"; gitc "$G/sh" mv docs/t.md docs/record/t.md; gitc "$G/sh" commit -qm "archive t"
srun sheep "$G/sh/docs/record/t.md" > "$T/c1.out" 2>&1; rc=$?
check "$rc" "0" "C: a renamed doc deploys"
check "$(grep '^deploy' "$S/cli.log" | tail -1 | grep -c -- '--space sp-t')" "1" "…into the page its old path had"
has "$T/c1.out" "docs/record/t.md renamed from docs/t.md" "…and says so"
check "$(kp pin "$TK" moved_to)" '"sh@claude/sh:docs/record/t.md"' "…the old pin says where the page went"
check "$(kp pin "$TK" space)" "null" "…and gives the space up, so the drain and the lookout pass it by"
check "$(kp pin sh@claude/sh:docs/record/t.md taken | python3 -c 'import json,sys; print(sorted(json.load(sys.stdin)))')" "['a1', 'kb', 'kg']" "…the new pin keeps the threads already taken"
n0=$(grep -c '^deploy' "$S/cli.log")
check "$(kp blob "$TK" 2>/dev/null)" "false" "C: a deploy of the old key (the lookout's) deploys nothing"
check "$(grep -c '^deploy' "$S/cli.log")" "$n0" "…not a single deploy"
printf '# Revived\n\n- **D1 — Again?** Body.\n\n  ➤ Recommended: yes\n\n  ➤ Answer:\n\n---\n' > "$G/sh/docs/t.md"
gitc "$G/sh" add docs/t.md; gitc "$G/sh" commit -qm "t revived"
srun sheep "$G/sh/docs/t.md" > "$T/c1r.out" 2>&1
check "$(grep '^deploy' "$S/cli.log" | tail -1 | grep -c -- '--space')" "0" "C: a doc revived at its old path gets a page of its own, not the renamed doc's"
check "$(kp pin "$TK" moved_to)" "null" "…and its pin forgets the move"
gitc "$G/sh" rm -q docs/t.md; gitc "$G/sh" commit -qm "t gone again"
# C2: a doc whose head says it supersedes another gets a page of its own (D3-A, 2026-10-25: the handover is not built)
cat > "$G/sh/docs/u.md" <<'EOF'
# Old plan

- **D1 — Which?** Old question.

  ➤ Recommended: A

  ➤ Answer:

---
EOF
gitc "$G/sh" add docs/u.md; gitc "$G/sh" commit -qm "old plan"
srun sheep "$G/sh/docs/u.md" > /dev/null 2>&1
python3 -c 'import json,sys; f=sys.argv[1]; d=json.load(open(f)); d[sys.argv[2]]["space"]="sp-u"; json.dump(d, open(f, "w"))' "$S/state/sheep.json" "sh@claude/sh:docs/u.md"
printf '# New plan\n\nSupersedes: `docs/u.md`\n\n- **D1 — Something else?** A new question.\n\n  ➤ Recommended: B\n\n  ➤ Answer:\n\n---\n' > "$G/sh/docs/v.md"
gitc "$G/sh" add docs/v.md; gitc "$G/sh" commit -qm "new plan"
srun sheep "$G/sh/docs/v.md" > "$T/c2.out" 2>&1; rc=$?
check "$rc $(grep '^deploy' "$S/cli.log" | tail -1 | grep -c -- '--space')" "0 0" "C2: a doc headed Supersedes: deploys to a page of its own"
check "$(kp pin sh@claude/sh:docs/u.md space) $(kp pin sh@claude/sh:docs/u.md moved_to)" '"sp-u" null' "…and the old doc keeps its page"
gitc "$G/sh" push -q origin claude/sh 2>/dev/null
# C3: a doc read from main after its branch landed takes the branch's page
# the bare repo has no main yet: this clone makes its own, so the landing is a local fast-forward
mkclone "$G/lm"; git -C "$G/lm" symbolic-ref HEAD refs/heads/main; printf 'lm\n' > "$G/lm/README"; gitc "$G/lm" add README; gitc "$G/lm" commit -qm init
gitc "$G/lm" checkout -q -b claude/lm; mkdir -p "$G/lm/docs"
printf '# Landed\n\n- **D1 — Land?** Body.\n\n  ➤ Recommended: yes\n\n  ➤ Answer:\n\n---\n' > "$G/lm/docs/w.md"
gitc "$G/lm" add docs/w.md; gitc "$G/lm" commit -qm "w"
srun sheep "$G/lm/docs/w.md" > /dev/null 2>&1
python3 -c 'import json,sys; f=sys.argv[1]; d=json.load(open(f)); d[sys.argv[2]]["space"]="sp-w"; json.dump(d, open(f, "w"))' "$S/state/sheep.json" "lm@claude/lm:docs/w.md"
gitc "$G/lm" checkout -q main; gitc "$G/lm" merge -q --ff-only claude/lm
srun sheep "$G/lm/docs/w.md" > "$T/c3.out" 2>&1; rc=$?
check "$rc" "0" "C: the landed doc deploys from main"
check "$(grep '^deploy' "$S/cli.log" | tail -1 | grep -c -- '--space sp-w')" "1" "…into the branch's page, not a new one"
has "$T/c3.out" "docs/w.md landed from claude/lm" "…and says so"
check "$(kp pin lm@claude/lm:docs/w.md moved_to)" '"lm@main:docs/w.md"' "…the branch's pin points at main's"
# …but main does not take a page from a branch still at work on the doc
gitc "$G/lm" checkout -q -b claude/lm2; printf '# Busy\n\n- **D1 — Wait?** Body.\n\n  ➤ Recommended: yes\n\n  ➤ Answer:\n\n---\n' > "$G/lm/docs/x.md"
gitc "$G/lm" add docs/x.md; gitc "$G/lm" commit -qm "x"
srun sheep "$G/lm/docs/x.md" > /dev/null 2>&1
python3 -c 'import json,sys; f=sys.argv[1]; d=json.load(open(f)); d[sys.argv[2]]["space"]="sp-x"; json.dump(d, open(f, "w"))' "$S/state/sheep.json" "lm@claude/lm2:docs/x.md"
gitc "$G/lm" checkout -q main; printf '# Busy\n\nmain'"'"'s own copy\n\n- **D1 — Wait?** Body.\n\n  ➤ Recommended: yes\n\n  ➤ Answer:\n\n---\n' > "$G/lm/docs/x.md"
gitc "$G/lm" add docs/x.md; gitc "$G/lm" commit -qm "x on main"
srun sheep "$G/lm/docs/x.md" > /dev/null 2>&1
check "$(grep '^deploy' "$S/cli.log" | tail -1 | grep -c -- '--space')" "0" "…a branch whose doc differs and whose ref lives keeps its page"
check "$(kp pin lm@claude/lm2:docs/x.md moved_to)" "null" "…and its pin"
printf '# Same\n\n- **D1 — Keep?** Body.\n\n  ➤ Recommended: yes\n\n  ➤ Answer:\n\n---\n' > "$G/lm/docs/y.md"
gitc "$G/lm" add docs/y.md; gitc "$G/lm" commit -qm "y on main"; gitc "$G/lm" checkout -q -b claude/lm3
printf 'other\n' > "$G/lm/other.txt"; gitc "$G/lm" add other.txt; gitc "$G/lm" commit -qm "lm3 at work elsewhere"
srun sheep "$G/lm/docs/y.md" > /dev/null 2>&1
python3 -c 'import json,sys; f=sys.argv[1]; d=json.load(open(f)); d[sys.argv[2]]["space"]="sp-y"; json.dump(d, open(f, "w"))' "$S/state/sheep.json" "lm@claude/lm3:docs/y.md"
gitc "$G/lm" checkout -q main
srun sheep "$G/lm/docs/y.md" > /dev/null 2>&1
check "$(grep '^deploy' "$S/cli.log" | tail -1 | grep -c -- '--space')" "0" "…nor from a live branch that never changed the doc, though its blob is main's"
check "$(kp pin lm@claude/lm3:docs/y.md moved_to)" "null" "…which keeps its pin"

# the second landing review: R3, R4, R10 (what proves a landing); R5 and R6 went with Supersedes: (D3-A)
setspace() { python3 -c 'import json,sys; f=sys.argv[1]; d=json.load(open(f)); d[sys.argv[2]]["space"]=sys.argv[3]; json.dump(d, open(f, "w"))' "$S/state/sheep.json" "$1" "$2"; }
lastspace() { grep '^deploy' "$S/cli.log" | tail -1 | grep -o -- '--space [^ ]*' | cut -d' ' -f2; }
doc() { printf '# %s\n\n%b- **D1 — %s?** Body.\n\n  ➤ Recommended: yes\n\n  ➤ Answer:\n\n---\n' "$1" "$2" "$1"; }
doc Idle "" > "$G/lm/docs/z.md"; gitc "$G/lm" add docs/z.md; gitc "$G/lm" commit -qm "z on main"
gitc "$G/lm" checkout -q -b claude/lm4
srun sheep "$G/lm/docs/z.md" > /dev/null 2>&1; setspace lm@claude/lm4:docs/z.md sp-z
gitc "$G/lm" checkout -q main
srun sheep "$G/lm/docs/z.md" > /dev/null 2>&1
check "$(lastspace)" "" "R3: …nor from a branch with no commits of its own, merged by the ancestor test"
check "$(kp pin lm@claude/lm4:docs/z.md moved_to)" "null" "…which keeps its pin"
doc Dropped "" > "$G/lm/docs/q.md"; gitc "$G/lm" add docs/q.md; gitc "$G/lm" commit -qm "q on main"
gitc "$G/lm" checkout -q -b claude/lm5; doc Dropped "A line main never got.\n\n" > "$G/lm/docs/q.md"; gitc "$G/lm" commit -qam "q on lm5"
srun sheep "$G/lm/docs/q.md" > /dev/null 2>&1; setspace lm@claude/lm5:docs/q.md sp-q
gitc "$G/lm" checkout -q main; gitc "$G/lm" branch -q -D claude/lm5
srun sheep "$G/lm/docs/q.md" > /dev/null 2>&1
check "$(lastspace)" "" "R4: a branch deleted unmerged hands main no page: its page's own commit holds another blob"
check "$(kp pin lm@claude/lm5:docs/q.md moved_to)" "null" "…and keeps its pin, pending Saves and all"
doc Worktree "" > "$G/lm/docs/r.md"; gitc "$G/lm" add docs/r.md; gitc "$G/lm" commit -qm "r on main"
gitc "$G/lm" worktree add -q "$G/lm-wt" -b claude/lm6
doc Worktree "Changed in the worktree.\n\n" > "$G/lm-wt/docs/r.md"; gitc "$G/lm-wt" commit -qam "r on lm6"
srun sheep "$G/lm-wt/docs/r.md" > /dev/null 2>&1; setspace lm@claude/lm6:docs/r.md sp-r
check "$(kp pin lm@claude/lm6:docs/r.md fork)" "\"$(git -C "$G/lm" rev-parse main)\"" "R3: a claude/* deploy records where the branch left main"
gitc "$G/lm" merge -q --ff-only claude/lm6
srun sheep "$G/lm/docs/r.md" > "$T/r10a.out" 2>&1
check "$(lastspace)" "sp-r" "R10: main takes a landed branch's page though the branch's worktree is still here"
has "$T/r10a.out" "docs/r.md landed from claude/lm6" "…and says so"
doc GiveWay "" > "$G/lm/docs/g.md"; gitc "$G/lm" add docs/g.md; gitc "$G/lm" commit -qm "g on main"
srun sheep "$G/lm/docs/g.md" > /dev/null 2>&1; setspace lm@main:docs/g.md sp-gm
gitc "$G/lm" checkout -q -b claude/lm7; doc GiveWay "Changed on lm7.\n\n" > "$G/lm/docs/g.md"; gitc "$G/lm" commit -qam "g on lm7"
srun sheep "$G/lm/docs/g.md" > /dev/null 2>&1; setspace lm@claude/lm7:docs/g.md sp-g7
gitc "$G/lm" checkout -q main; gitc "$G/lm" merge -q --ff-only claude/lm7
echo '{"comments": []}' > "$S/web-comments.json"
srun sheep "$G/lm/docs/g.md" > "$T/r10b.out" 2>&1
check "$(lastspace)" "sp-g7" "R10: main's own page, empty, gives way to the landed branch's"
has "$T/r10b.out" "main's empty page gave way to it" "…and says so"
check "$(kp pin lm@main:docs/g.md gave_up_space) $(kp pin lm@claude/lm7:docs/g.md moved_to)" '"sp-gm" "lm@main:docs/g.md"' "…main's pin names the page it gave up, the branch's points at main's"
doc Kept "" > "$G/lm/docs/h.md"; gitc "$G/lm" add docs/h.md; gitc "$G/lm" commit -qm "h on main"
srun sheep "$G/lm/docs/h.md" > /dev/null 2>&1; setspace lm@main:docs/h.md sp-hm
gitc "$G/lm" checkout -q -b claude/lm9; doc Kept "Changed on lm9.\n\n" > "$G/lm/docs/h.md"; gitc "$G/lm" commit -qam "h on lm9"
srun sheep "$G/lm/docs/h.md" > /dev/null 2>&1; setspace lm@claude/lm9:docs/h.md sp-h9
gitc "$G/lm" checkout -q main; gitc "$G/lm" merge -q --ff-only claude/lm9
echo '{"comments": [{"id": "hm1", "parent_id": null, "body": "a thought on main", "anchor_id": null, "resolved_at": null, "created_at": "2026-10-24T10:00:00Z", "via": null}]}' > "$S/web-comments.json"
srun sheep "$G/lm/docs/h.md" > "$T/r10c.out" 2>&1
check "$(lastspace)" "sp-hm" "R10: main's own page with a thread on it keeps it"
check "$(kp pin lm@main:docs/h.md kept_over)" '["lm@claude/lm9:docs/h.md"]' "…and records the branch, so its page is read once"

# the third landing review (2026-10-25): findings 3 and 5-15
check "$(kp family b-12345678) $(kp family b-12345678-2) $(kp family b-1234abcd-3)" "b-12345678 b-12345678 b-1234abcd" "finding 5: an all-digit hash is no copy number; a number after the hash is"
check "$(kp shifts '[[["b-11111111","x","",1]],[["b-22222222","x","",1]]]')" '{}' "finding 5: two all-digit hashes are not copies of one line"
check "$(kp routetimeout)" "the comments route did not answer in 1s False" "finding 13: a read the hook's budget cut short does not mark the route failed"
# finding 7: a copy inserted above a commented line leaves the thread on its line
cat > "$G/sh/docs/t3.md" <<'EOF'
# Copies

Intro line about the copies.

Same words, said once.

Outro line about the copies.

- **D1 — Go?** Body.

  ➤ Recommended: yes

  ➤ Answer:

---
EOF
gitc "$G/sh" add docs/t3.md; gitc "$G/sh" commit -qm "copies"
srun sheep "$G/sh/docs/t3.md" > /dev/null 2>&1
SAMEW=$(kp ids "$S/page.html" | grep 'Same words' | cut -f1)
cat > "$S/web-comments.json" <<EOF
{"comments": [{"id": "c7", "parent_id": null, "body": "this one, not a copy", "anchor_id": "$SAMEW", "resolved_at": null, "created_at": "2026-10-25T10:00:00Z", "via": null}]}
EOF
perl -0pi -e 's/# Copies\n/# Copies\n\nSame words, said once.\n/' "$G/sh/docs/t3.md"; gitc "$G/sh" commit -qam "a copy above"
srun sheep "$G/sh/docs/t3.md" > /dev/null 2>&1
check "$(kp ids "$S/page.html" | grep -A1 'Intro line' | tail -1 | cut -f1)" "$SAMEW" "finding 7: a copy inserted above a commented line leaves the thread's id on its line"
check "$(kp ids "$S/page.html" | grep 'Same words' | head -1 | cut -f1)" "$SAMEW-3" "…and the copy above takes a number no block had"
n0=$(grep -c '^read' "$S/cli.log")
perl -pi -e 's/^Outro line about the copies\./Outro line about the copies, edited./' "$G/sh/docs/t3.md"; gitc "$G/sh" commit -qam "edit the outro"
srun sheep "$G/sh/docs/t3.md" > /dev/null 2>&1
check "$(grep -c '^read' "$S/cli.log") $(kp ids "$S/page.html" | grep -A1 'Intro line' | tail -1 | cut -f1)" "$n0 $SAMEW" "…and the next deploy keeps both copies' numbers from this Mac's last page, with no read"
# finding 15: an inherited id is kept from the pin's aliases, with no read of the live page
cat > "$G/sh/docs/t4.md" <<'EOF'
# Alias

Kappa line about the release train leaving on Monday.

Lambda line nobody comments on.

- **D1 — Go?** Body.

  ➤ Recommended: yes

  ➤ Answer:

---
EOF
gitc "$G/sh" add docs/t4.md; gitc "$G/sh" commit -qm "alias"
srun sheep "$G/sh/docs/t4.md" > /dev/null 2>&1
KAPPA=$(kp ids "$S/page.html" | grep 'Kappa line' | cut -f1)
cat > "$S/web-comments.json" <<EOF
{"comments": [{"id": "k15", "parent_id": null, "body": "Monday is a holiday", "anchor_id": "$KAPPA", "resolved_at": null, "created_at": "2026-10-25T10:00:00Z", "via": null}]}
EOF
sedi -e 's/leaving on Monday/leaving on Tuesday/' "$G/sh/docs/t4.md"; gitc "$G/sh" commit -qam "kappa on tuesday"
srun sheep "$G/sh/docs/t4.md" > /dev/null 2>&1
check "$(kp ids "$S/page.html" | grep 'Kappa line' | cut -f1)" "$KAPPA" "finding 15: the edited line inherits the commented id"
n0=$(grep -c '^read' "$S/cli.log")
sedi -e 's/^Lambda line nobody comments on\./Lambda line nobody ever comments on./' "$G/sh/docs/t4.md"; gitc "$G/sh" commit -qam "edit lambda"
srun sheep "$G/sh/docs/t4.md" > /dev/null 2>&1
check "$(grep -c '^read' "$S/cli.log") $(kp ids "$S/page.html" | grep 'Kappa line' | cut -f1)" "$n0 $KAPPA" "…and a later deploy keeps it from the pin's aliases, with no read of the live page"
# finding 3: a deleted line's thread not yet told never moves onto a similar neighbour the deploy did not add
cat > "$G/sh/docs/t5.md" <<'EOF'
# Untold

Mu line about the deploy window on Friday evening.

Mu line about the deploy window on Sunday evening.

Nu line nobody comments on.

- **D1 — Go?** Body.

  ➤ Recommended: yes

  ➤ Answer:

---
EOF
gitc "$G/sh" add docs/t5.md; gitc "$G/sh" commit -qm "untold"
srun sheep "$G/sh/docs/t5.md" > /dev/null 2>&1
FRIM=$(kp ids "$S/page.html" | grep 'Friday' | cut -f1); SUNM=$(kp ids "$S/page.html" | grep 'Sunday' | cut -f1)
cat > "$S/web-comments.json" <<EOF
{"comments": [{"id": "f3", "parent_id": null, "body": "friday is wrong", "anchor_id": "$FRIM", "resolved_at": null, "created_at": "2026-10-25T10:00:00Z", "via": null}]}
EOF
perl -ni -e 'print unless /Friday evening/' "$G/sh/docs/t5.md"; gitc "$G/sh" commit -qam "drop friday"
touch "$S/fail-add"
srun sheep "$G/sh/docs/t5.md" > "$T/f3a.out" 2>&1; rc=$?
rm -f "$S/fail-add"
check "$rc" "0" "finding 3: a deploy whose \"gone\" reply fails still deploys"
sedi -e 's/^Nu line nobody comments on\./Nu line nobody ever comments on./' "$G/sh/docs/t5.md"; gitc "$G/sh" commit -qam "edit nu"
srun sheep "$G/sh/docs/t5.md" > /dev/null 2>&1
check "$(kp ids "$S/page.html" | grep 'Sunday' | cut -f1)" "$SUNM" "finding 3: the next deploy leaves the untold thread off the unchanged Sunday line (0.93)"
check "$(grep '"add_comment"' "$S/mcp.log" | grep '"parent_id": "f3"' | grep -c 'the line this was on is gone')" "2" "…and tells it its line is gone, the failed try and this one"
# finding 11: a reply typed between a take's write and its commit is taken in, not lost to git's answer
cat > "$G/sh/docs/t6.md" <<'EOF'
# Late

- **D1 — Go?** Body.

  ➤ Recommended: yes

  ➤ Answer:

---
EOF
gitc "$G/sh" add docs/t6.md; gitc "$G/sh" commit -qm "late"
srun sheep "$G/sh/docs/t6.md" > /dev/null 2>&1
cat > "$S/web-comments.json" <<'EOF'
{"comments": [{"id": "l1", "parent_id": null, "body": "yes, go now", "anchor_id": "D1", "resolved_at": null, "created_at": "2026-10-25T09:00:00Z", "via": null}]}
EOF
srun sheep pull --write "$G/sh/docs/t6.md" > /dev/null 2>&1
python3 - "$S/web-comments.json" <<'PY'
import datetime, json, sys
d = json.load(open(sys.argv[1]))
now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
d["comments"] += [{"id": "l1m", "parent_id": "l1", "body": "memo: taken into docs/t6.md as D1's answer", "via": "claude", "created_at": now},
                  {"id": "l1r", "parent_id": "l1", "body": "actually, hold it", "via": None, "created_at": now}]
json.dump(d, open(sys.argv[1], "w"))
PY
sleep 1.2; gitc "$G/sh" commit -qam "the take, committed after the reply"
srun sheep pull "$G/sh/docs/t6.md" > "$T/f11.out" 2>&1
has "$T/f11.out" "[l1] → D1: actually, hold it" "finding 11: a reply typed between a take's write and its commit is taken in"
lacks "$T/f11.out" "changed in git after it" "…not kept out by the answer the take itself wrote"
rm -f "$S/web-comments.json"
# finding 14: a redeploy after main fast-forwarded keeps the fork recorded before, so the landing is still proved
doc Forked "" > "$G/lm/docs/f.md"; gitc "$G/lm" add docs/f.md; gitc "$G/lm" commit -qm "f on main"
F0=$(git -C "$G/lm" rev-parse main)
gitc "$G/lm" checkout -q -b claude/lm11; doc Forked "Changed on lm11.\n\n" > "$G/lm/docs/f.md"; gitc "$G/lm" commit -qam "f on lm11"
srun sheep "$G/lm/docs/f.md" > /dev/null 2>&1
gitc "$G/lm" checkout -q main; gitc "$G/lm" merge -q --ff-only claude/lm11; gitc "$G/lm" checkout -q claude/lm11
python3 -c 'import json,sys; f=sys.argv[1]; d=json.load(open(f)); d[sys.argv[2]]["fmt"]="an older format"; json.dump(d, open(f, "w"))' "$S/state/sheep.json" lm@claude/lm11:docs/f.md
srun sheep "$G/lm/docs/f.md" > /dev/null 2>&1; setspace lm@claude/lm11:docs/f.md sp-f
check "$(kp pin lm@claude/lm11:docs/f.md fork)" "\"$F0\"" "finding 14: a redeploy after main fast-forwarded keeps the fork recorded before"
gitc "$G/lm" checkout -q main
srun sheep "$G/lm/docs/f.md" > /dev/null 2>&1
check "$(lastspace)" "sp-f" "…so main still proves the landing and takes the page"
# finding 12: on main, a landed branch's page of a renamed doc wins over main's page of the old path
doc Renamed "" > "$G/lm/docs/a12.md"; gitc "$G/lm" add docs/a12.md; gitc "$G/lm" commit -qm "a12 on main"
srun sheep "$G/lm/docs/a12.md" > /dev/null 2>&1; setspace lm@main:docs/a12.md sp-a12m
gitc "$G/lm" checkout -q -b claude/lm12; gitc "$G/lm" mv docs/a12.md docs/b12.md; gitc "$G/lm" commit -qm "a12 renamed b12"
doc Renamed "Changed on lm12.\n\n" > "$G/lm/docs/b12.md"; gitc "$G/lm" commit -qam "b12 on lm12"
srun sheep "$G/lm/docs/b12.md" > /dev/null 2>&1; setspace lm@claude/lm12:docs/b12.md sp-b12
gitc "$G/lm" checkout -q main; gitc "$G/lm" merge -q --ff-only claude/lm12
srun sheep "$G/lm/docs/b12.md" > "$T/f12.out" 2>&1
check "$(lastspace)" "sp-b12" "finding 12: on main, the landed branch's page wins over main's page of the doc's old path"
has "$T/f12.out" "docs/b12.md landed from claude/lm12" "…and says so"
# findings 9 and 6: main's page gives way only when its comments read, and its room holds no Save
doc Unread "" > "$G/lm/docs/g2.md"; gitc "$G/lm" add docs/g2.md; gitc "$G/lm" commit -qm "g2 on main"
srun sheep "$G/lm/docs/g2.md" > /dev/null 2>&1; setspace lm@main:docs/g2.md sp-g2m
gitc "$G/lm" checkout -q -b claude/lm13; doc Unread "Changed on lm13.\n\n" > "$G/lm/docs/g2.md"; gitc "$G/lm" commit -qam "g2 on lm13"
srun sheep "$G/lm/docs/g2.md" > /dev/null 2>&1; setspace lm@claude/lm13:docs/g2.md sp-g13
gitc "$G/lm" checkout -q main; gitc "$G/lm" merge -q --ff-only claude/lm13
rm -f "$S/web-comments.json"; cp "$S/comments.txt" "$T/comments.kept" 2>/dev/null || :; printf 'a shape this tool has never seen\n' > "$S/comments.txt"
srun sheep "$G/lm/docs/g2.md" > "$T/f9.out" 2>&1
cp "$T/comments.kept" "$S/comments.txt" 2>/dev/null || :
check "$(lastspace)" "sp-g2m" "finding 9: main's page whose comments come back unreadable does not give way"
has "$T/f9.out" "cannot read" "…and says why"
setspace lm@main:docs/g2.md sp-g2m  # the stub answers every deploy with sp-1
echo '{"comments": []}' > "$S/web-comments.json"
cat > "$S/events.json" <<'EOF'
[{"seq": 1, "at": "2026-10-25T10:00:00Z", "name": "memo-save", "data": {"items": {"D1": "no, wait"}, "comments": [], "feedback": ""}}]
EOF
srun sheep "$G/lm/docs/g2.md" > "$T/f6.out" 2>&1
rm -f "$S/events.json"
check "$(kp pin lm@main:docs/g2.md kept_over) $(kp pin lm@main:docs/g2.md space)" '["lm@claude/lm13:docs/g2.md"] "sp-g2m"' "finding 6: a Save still in main's room keeps main's page"
has "$T/f6.out" "a Save not taken in" "…and says so"
# finding 10: main's page giving way drops what main kept of it; finding 8: a pin with no sha reads cleanly
doc Cursor "" > "$G/lm/docs/g3.md"; gitc "$G/lm" add docs/g3.md; gitc "$G/lm" commit -qm "g3 on main"
srun sheep "$G/lm/docs/g3.md" > /dev/null 2>&1; setspace lm@main:docs/g3.md sp-g3m
python3 -c 'import json,sys; f=sys.argv[1]; d=json.load(open(f)); d[sys.argv[2]].update(events_after=5, receipt={"at": "x"}, opens_seen={"s|c": 1}); json.dump(d, open(f, "w"))' "$S/state/sheep.json" lm@main:docs/g3.md
gitc "$G/lm" checkout -q -b claude/lm14; doc Cursor "Changed on lm14.\n\n" > "$G/lm/docs/g3.md"; gitc "$G/lm" commit -qam "g3 on lm14"
srun sheep "$G/lm/docs/g3.md" > /dev/null 2>&1; setspace lm@claude/lm14:docs/g3.md sp-g14
gitc "$G/lm" checkout -q main; gitc "$G/lm" merge -q --ff-only claude/lm14
srun sheep "$G/lm/docs/g3.md" > /dev/null 2>&1
check "$(lastspace) $(kp pin lm@main:docs/g3.md events_after) $(kp pin lm@main:docs/g3.md receipt) $(kp pin lm@main:docs/g3.md opens_seen)" "sp-g14 null null null" "finding 10: main's page giving way drops main's cursors and receipt with it"
python3 -c 'import json,sys; f=sys.argv[1]; d=json.load(open(f)); d[sys.argv[2]].pop("sha", None); d[sys.argv[2]].pop("branch", None); json.dump(d, open(f, "w"))' "$S/state/sheep.json" lm@main:docs/g3.md
srun sheep check "$G/lm/docs/g3.md" > "$T/f8.out" 2>&1; rc=$?
check "$rc" "0" "finding 8: sheep check on a pin with no sha (a deploy that failed after it took a page over) answers"
lacks "$T/f8.out" "Traceback" "…with no KeyError"
# the finish review: the owner's set-aside words (refused_saves) on main's pin keep main's page, as a pending Save does
doc Refused "" > "$G/lm/docs/g4.md"; gitc "$G/lm" add docs/g4.md; gitc "$G/lm" commit -qm "g4 on main"
srun sheep "$G/lm/docs/g4.md" > /dev/null 2>&1; setspace lm@main:docs/g4.md sp-g4m
python3 -c 'import json,sys; f=sys.argv[1]; d=json.load(open(f)); d[sys.argv[2]].update(refused_saves=[{"D1": "C, with a cap"}]); json.dump(d, open(f, "w"))' "$S/state/sheep.json" lm@main:docs/g4.md
gitc "$G/lm" checkout -q -b claude/lm15; doc Refused "Changed on lm15.\n\n" > "$G/lm/docs/g4.md"; gitc "$G/lm" commit -qam "g4 on lm15"
srun sheep "$G/lm/docs/g4.md" > /dev/null 2>&1; setspace lm@claude/lm15:docs/g4.md sp-g15
gitc "$G/lm" checkout -q main; gitc "$G/lm" merge -q --ff-only claude/lm15
echo '{"comments": []}' > "$S/web-comments.json"
srun sheep "$G/lm/docs/g4.md" > /dev/null 2>&1
check "$(kp pin lm@main:docs/g4.md kept_over) $(kp pin lm@main:docs/g4.md refused_saves)" '["lm@claude/lm15:docs/g4.md"] [{"D1": "C, with a cap"}]' "the finish review: set-aside words on main's pin keep main's page"
rm -f "$S/web-comments.json"

echo "serve — the form on 127.0.0.1, Save writes into the memo"
cp "$T/memo.md" "$T/s.md"
python3 "$B/keel" serve "$T/s.md" --idle 20 > "$T/s.out" 2>&1 &
spid=$!
for _ in $(seq 50); do grep -q '^http://' "$T/s.out" && break; sleep 0.1; done
U=$(head -1 "$T/s.out")
case "$U" in http://127.0.0.1:*/*/) echo "  ok   prints its URL first";; *) echo "  FAIL prints its URL first: got [$U]"; fails=$((fails+1));; esac
curl -s "$U" > "$T/s.html"
has "$T/s.html" "<title>Repo sync" "GET serves the form"
has "$T/s.html" '"post": "/' "…wired to post back to the server"
check "$(curl -s -o /dev/null -w '%{http_code}' "${U%/*/}/wrong/")" "404" "another path is 404 (the token guards it)"
check "$(curl -s -o /dev/null -w '%{http_code}' -H 'Origin: http://evil.test' -H 'Content-Type: application/json' -d '{"items":{"D1":"x"}}' "${U}answers")" "403" "a POST from another origin is refused"
lacks "$T/s.md" "➤ Answer: x" "…and wrote nothing"
curl -s -H 'Content-Type: application/json' -d '{"items":{"D1":"no.","D2":"yes, but only where a session outlives one sitting — not for two-minute questions."},"feedback":"fine by me"}' "${U}answers" > "$T/s.json"
has "$T/s.json" '"closed": true' "Save answers, and says the page is done"
has "$T/s.md" "➤ Answer: no." "…the changed answer is in the memo"
has "$T/s.md" "fine by me" "…and the feedback"
for _ in $(seq 30); do kill -0 "$spid" 2>/dev/null || break; sleep 0.1; done
check "$(kill -0 "$spid" 2>/dev/null && echo running || echo exited)" "exited" "the server exits after the first Save (that wakes the session)"
has "$T/s.out" "saved s.md: changed: D1;" "…after printing what changed"
kill "$spid" 2>/dev/null

echo "serve — a refused Save is answered and printed, and the server stays up (review 2026-10-04)"
printf '# R\n\n- **D1 — Q?** Body.\n  A — x\n  ➤ Recommended: A\n  ➤ Answer:\n\nProse below the list, no heading.\n' > "$T/r.md"
python3 "$B/keel" serve "$T/r.md" --idle 20 > "$T/r.out" 2>&1 &
rpid=$!
for _ in $(seq 50); do grep -q '^http://' "$T/r.out" && break; sleep 0.1; done
U=$(head -1 "$T/r.out")
code=$(curl -s -o "$T/r.json" -w '%{http_code}' -H 'Content-Type: application/json' -d '{"items":{"D1":"A"}}' "${U}answers")
check "$code" "409" "a merge guard refusal is a 409, not an empty reply"
has "$T/r.json" "runs into line" "…with the reason for the page"
has "$T/r.out" "refused r.md:" "…and a line for the session"
check "$(kill -0 "$rpid" 2>/dev/null && echo running || echo exited)" "running" "…and the server stays up for a second Save"
kill "$rpid" 2>/dev/null
python3 "$B/keel" serve "$T/nope.md" > "$T/n.out" 2>&1; rc=$?
printf -- '# P\n\n- **D1 — Q?** Body.\n  A — x\n  ➤ Recommended: A\n  ➤ Answer:\n\n- **D2 — R?** Body.\n  ➤ Recommended: B\n  ➤ Answer:\n\n---\n\n## Open feedback\n' > "$T/p.md"
cp "$T/p.md" "$T/p0.md"
python3 "$B/keel" serve "$T/p.md" --keep --idle 20 > "$T/p.out" 2>&1 &
ppid=$!
for _ in $(seq 50); do grep -q '^http://' "$T/p.out" && break; sleep 0.1; done
U=$(head -1 "$T/p.out")
code=$(curl -s -o "$T/p.json" -w '%{http_code}' -H 'Content-Type: application/json' -d '{"items":{"D1":"B\n- **D2 — same as above** z"}}' "${U}answers")
check "$code" "409" "an answer that would make the memo unparseable is refused (code review 2026-10-04)"
check "$(cmp -s "$T/p.md" "$T/p0.md" && echo same || echo changed)" "same" "…and the memo is left as it was"
check "$(curl -s -o /dev/null -w '%{http_code}' -H 'Content-Length: abc' -d 'x' "${U}answers")" "400" "a bad Content-Length is a 400, not an empty reply"
kill "$ppid" 2>/dev/null
python3 "$B/keel" serve "$T/nope.md" > "$T/n.out" 2>&1; rc=$?
check "$rc" "1" "serve on a missing memo exits 1 before printing a URL"
lacks "$T/n.out" "http://" "…and prints none"

echo "the page through merge's guards, and its opens (memo serve's cases, kept when it retired 2026-10-14)"
cp "$SM" "$T/s0.md"
cat > "$S/events.json" <<'EOF'
[{"seq": 4, "at": "2026-10-14T11:00:00Z", "name": "memo-open", "data": {"sha": "abc"}, "from": {"name": "sam", "seed": "v1"}},
 {"seq": 5, "at": "2026-10-14T11:00:06Z", "name": "memo-open", "data": {"sha": "abc"}, "from": {"name": "sam", "seed": "v1"}},
 {"seq": 6, "at": "2026-10-14T11:05:00Z", "name": "memo-open", "data": {"sha": "abc"}, "from": {"name": "sam", "seed": "v1"}},
 {"seq": 7, "at": "2026-10-14T11:06:00Z", "name": "memo-save", "from": {"name": "sam"},
  "data": {"sha": "abc", "items": {"D2": "B\n- **D1 — same as above** z"}, "comments": [], "feedback": ""}}]
EOF
srun sheep pull --write "$SM" > "$T/g1.out" 2>&1; rc=$?
check "$rc" "0" "a Save that would make the memo unparseable is set aside, not a blocker (review 2026-10-14)"
check "$(cmp -s "$SM" "$T/s0.md" && echo same || echo changed)" "same" "…and the memo is left as it was"
has "$T/g1.out" "refused save 7" "…named"
check "$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); p=[v for k, v in d.items() if k.endswith("docs/s.md")][0]; print(len(p["saves"]), [r["seq"] for r in p["refused_saves"]])' "$S/state/sheep.json")" "0 [7]" "…kept in refused_saves, gone from the queue: the next pull is not blocked"
check "$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); r=[v for k, v in d.items() if k.endswith("docs/s.md")][0]["receipt"]; print(r["saves"], len([x for x in r["refused"] if x["why"]]))' "$S/state/sheep.json")" \
      "[] 1" "…and the page's receipt says it was refused, with why"
has "$T/g1.out" "receipt: the page redeployed with it" "…and, the doc unchanged, the page is redeployed with it at once: no commit would carry it"
check "$(python3 -c 'import html,json,re,sys; h=open(sys.argv[1]).read(); m=re.search(r"data-ss-id=\"keel-receipt\" hidden data-receipt=\"([^\"]*)\"", h); print(len(json.loads(html.unescape(m.group(1)))["refused"]))' "$S/page.html")" \
      "1" "…the deployed page carries the refused receipt"
check "$(python3 -c 'import json,sys; r=[json.loads(l) for l in open(sys.argv[1]) if l.strip()]; r=[x for x in r if x["path"].endswith("/sh/docs/s.md")]; print(len(r), sorted(r[-1]), int(r[0]["ts"]))' "$MEMO_STATE_DIR/opens.jsonl")" \
      "2 ['branch', 'doc', 'path', 'repo', 'ts', 'who'] 1791975600" "page opens drain into opens.jsonl at the event's time, with the viewer's name; a repeat within a minute is one open (one load emitted three, 2026-10-14)"
cat > "$S/events.json" <<'EOF'
[{"seq": 8, "at": "2026-10-14T11:05:20Z", "name": "memo-open", "data": {"sha": "abc"}, "from": {"name": "sam", "seed": "v1"}}]
EOF
srun sheep pull "$SM" > /dev/null 2>&1
check "$(grep -c '/sh/docs/s.md' "$MEMO_STATE_DIR/opens.jsonl")" "2" "…and across drains: a wait's long poll returns at the first emit"
rm -f "$S/events.json"

echo "the reading heartbeat (crew design S6): memo-read into reads.jsonl, and sheep drain"
has "$S/page.html" '"read": "memo-read"' "the page carries the heartbeat's event name"
check "$(python3 -c 'import re,sys; h=open(sys.argv[1]).read(); i=h.index("if (M.emit && M.read)"); b=h[i:i+900]; print(all(t in b for t in ("isTrusted", "\"wheel\", \"keydown\", \"pointerdown\", \"touchstart\"", "visibilityState", "60000", "15000")), "scroll" in b or "pointermove" in b)' "$S/page.html")" \
      "True False" "…counting only trusted wheel, keydown, pointerdown, touchstart while visible, once a minute on a 15 s timer — no scroll, no pointermove"
check "$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print([v["fmt"] for k, v in d.items() if k.endswith("docs/s.md")])' "$S/state/sheep.json")" "[8]" "…and the pin is PAGE_FMT 8: an older page is redeployed with it"
# a state of its own, so the cursors and logs above stay as the cases after them expect
RS="$S/state-r" RM="$T/state-r"; mkdir -p "$RS"
SMKEY=$(python3 -c 'import json,sys; print([k for k in json.load(open(sys.argv[1])) if k.endswith("docs/s.md")][0])' "$S/state/sheep.json")
python3 - "$S/state/sheep.json" "$RS/sheep.json" "$SMKEY" <<'PY'
import datetime as dt, json, sys
d = json.load(open(sys.argv[1])); k = sys.argv[3]
now = dt.datetime.now().isoformat(timespec="seconds")
pin = {x: d[k][x] for x in ("space", "url", "sha", "fmt", "branch", "repo_path")}
pin.update(deployed=now)
old = dt.datetime(2026, 1, 1).isoformat(timespec="seconds")  # a page of last winter: past the horizon
json.dump({k: pin, "zz@claude/zz:docs/z.md": {"space": "sp-2", "branch": "claude/zz", "deployed": now},
           "old@claude/old:docs/o.md": {"space": "sp-3", "branch": "claude/old", "deployed": old}}, open(sys.argv[2], "w"))
PY
rrun() { (export SHEEP_T="$S" MEMO_SHEEP_BIN="$S/bin/spacesheep" MEMO_SHEEP_STATE="$RS" MEMO_STATE_DIR="$RM" SPACESHEEP_KEY=ss_test \
          MEMO_SHEEP_MCP="http://127.0.0.1:$(cat "$S/port")/mcp" MEMO_SHEEP_APP="http://127.0.0.1:$(cat "$S/port")"; run "$@"); }
rows() { python3 -c 'import json,sys
r = [json.loads(l) for l in open(sys.argv[1]) if l.strip()] if __import__("os").path.exists(sys.argv[1]) else []
print(len(r), " ".join("%s:%s" % (x["who"], int(x["ts"])) for x in r if x["doc"] == sys.argv[2]))' "$RM/$1" "$2"; }
echo '{"comments": []}' > "$S/comments.txt"
cat > "$S/events.json" <<'EOF'
[{"seq": 1, "at": "2026-10-19T10:00:00Z", "name": "memo-read", "data": {"sha": "abc"}, "from": {"name": "sam", "seed": "v1"}}]
EOF
rrun sheep pull "$SM" > "$T/rd1.out" 2>&1
check "$(rows reads.jsonl docs/s.md)" "1 sam:1792404000" "a memo-read is one reads.jsonl row: the event's time, the viewer's name"
check "$(python3 -c 'import json,sys; r=[json.loads(l) for l in open(sys.argv[1])][0]; print(sorted(r), r["branch"], r["path"].endswith("/sh/docs/s.md"))' "$RM/reads.jsonl")" \
      "['branch', 'doc', 'path', 'repo', 'ts', 'who'] claude/sh True" "…shaped like an open's row: {doc, repo, branch, path, ts, who}"
check "$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(len(d[sys.argv[2]].get("saves") or []), d[sys.argv[2]]["events_after"])' "$RS/sheep.json" "$SMKEY")" "0 1" "…and no Save: the cursor moves, nothing queued"
lacks "$T/rd1.out" "memo-read" "…and the pull prints nothing of it"
test -f "$RM/opens.jsonl"; check "$?" "1" "…nor is it an open"
cat > "$S/events.json" <<'EOF'
[{"seq": 1, "at": "2026-10-19T10:00:00Z", "name": "memo-read", "data": {"sha": "abc"}, "from": {"name": "sam", "seed": "v1"}},
 {"seq": 2, "at": "2026-10-19T10:00:20Z", "name": "memo-read", "data": {"sha": "abc"}, "from": {"name": "sam", "seed": "v2"}},
 {"seq": 3, "at": "2026-10-19T10:00:25Z", "name": "memo-read", "data": {"sha": "abc"}, "from": {"name": "alex", "seed": "z1"}},
 {"seq": 4, "at": "2026-10-19T10:00:40Z", "name": "memo-read", "data": {"sha": "abc"}, "from": {"name": "sam", "seed": "v1"}}]
EOF
rrun sheep pull "$SM" > /dev/null 2>&1
check "$(rows reads.jsonl docs/s.md)" "3 sam:1792404000 alex:1792404025 sam:1792404040" \
      "a repeat from one viewer within 30 s is dropped (another tab), across drains; another viewer's row is kept; 40 s from the last kept is a row"
cat >> "$S/events.json.new" <<'EOF'
[{"seq": 5, "at": "2026-10-19T10:01:40Z", "name": "memo-read", "data": {"sha": "abc"}, "from": {"name": "sam", "seed": "v1"}}]
EOF
mv "$S/events.json.new" "$S/events.json"
rrun sheep wait "$SM" --idle 3 --poll 1 > "$T/rdw.out" 2>&1; rc=$?
check "$rc/$(grep -c 'nothing on the page' "$T/rdw.out")" "0/1" "wait is not woken by a heartbeat: it listens out its --idle"
check "$(rows reads.jsonl docs/s.md | cut -d' ' -f1)" "4" "…and the heartbeat it heard is logged"
# sheep drain: every pin of the last 14 days, rows from the pin, both cursors moved
cat > "$S/events.json" <<'EOF'
[{"seq": 6, "at": "2026-10-19T11:00:00Z", "name": "memo-open", "data": {"sha": "abc"}, "from": {"name": "sam", "seed": "v1"}},
 {"seq": 7, "at": "2026-10-19T11:00:30Z", "name": "memo-read", "data": {"sha": "abc"}, "from": {"name": "sam", "seed": "v1"}}]
EOF
n0=$(grep -c '"tools/call"' "$S/mcp.log")
rrun sheep drain > "$T/dr1.out" 2>&1; rc=$?
check "$rc" "0" "sheep drain runs"
has "$T/dr1.out" "keel sheep drain: 2 pages, 2 reads (0 repeats dropped), 2 opens, 0 Saves held for its doc's pull" "…over the two recent pins, not last winter's, and says what it took"
check "$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d[sys.argv[2]]["events_after"], d["zz@claude/zz:docs/z.md"]["events_after"], d["old@claude/old:docs/o.md"].get("events_after"))' "$RS/sheep.json" "$SMKEY")" \
      "7 7 None" "…moving both cursors, and leaving the old pin alone"
check "$(rows reads.jsonl docs/z.md)" "6 sam:1792407630" "…a pathless pin's read lands under its key's doc"
check "$(python3 -c 'import json,sys,os; r=[json.loads(l) for l in open(sys.argv[1]) if l.strip()]; z=[x for x in r if x["doc"]=="docs/z.md"][0]; print(z["repo"] == os.path.expanduser("~/projects/zz"), z["branch"])' "$RM/reads.jsonl")" \
      "True claude/zz" "…its repo ~/projects/<the key's repo> where the pin has no repo_path, its branch the pin's"
check "$(MEMO_STATE_DIR="$RM" python3 -c 'import sys; from importlib.machinery import SourceFileLoader as L; m = L("m", sys.argv[1]).load_module(); print(m.logged_opens(m.doc_key(sys.argv[2])))' "$B/keel" "$SM")" \
      "1" "…and an open drained without a path still counts in logged_opens for its branch (status's opened)"
rrun sheep drain --if-due > "$T/dr2.out" 2>&1; rc=$?
check "$rc/$(wc -c < "$T/dr2.out" | tr -d ' ')/$(($(grep -c '"tools/call"' "$S/mcp.log") - n0))" "0/0/4" "--if-due within 6 h of the last drain: silent, no call (the 4 are the first drain's)"
rrun sheep drain --if-due > "$T/dr3.out" 2>&1
check "$(cat "$T/dr3.out")" "" "…and a second time, still nothing"
(export MEMO_NOW=$(( $(date +%s) + 7 * 3600 )); rrun sheep drain --if-due > "$T/dr4.out" 2>&1)
has "$T/dr4.out" "keel sheep drain: " "…7 h later it drains again"
rrun sheep drain --bogus > "$T/dr5.out" 2>&1; check "$?" "1" "sheep drain with an unknown flag is refused"
# a drain that ran beside another hands back events the other already logged (review, 2026-10-19)
cat > "$S/events.json" <<'EOF'
[{"seq": 5, "at": "2026-10-19T10:59:00Z", "name": "memo-read", "data": {"sha": "abc"}, "from": {"name": "sam", "seed": "v1"}},
 {"seq": 6, "at": "2026-10-19T11:00:00Z", "name": "memo-open", "data": {"sha": "abc"}, "from": {"name": "sam", "seed": "v1"}}]
EOF
r0=$(rows reads.jsonl docs/z.md | cut -d' ' -f1)
rrun sheep drain > "$T/dr6.out" 2>&1
check "$(rows reads.jsonl docs/z.md | cut -d' ' -f1)" "$r0" "a read at or below the pin's cursor is not logged again, though it is older than the last kept"
has "$T/dr6.out" "0 reads (0 repeats dropped), 0 opens" "…nor an open"
check "$(MEMO_STATE_DIR="$RM" python3 -c 'import sys; from importlib.machinery import SourceFileLoader as L; m = L("m", sys.argv[1]).load_module()
k = m.doc_key(sys.argv[2]); row = {"doc": k[2], "repo": k[0], "branch": k[1], "path": "/nowhere"}
print(m.touch_row(row, "save"), [r["event"] for r in m.logged_touches(sys.argv[2], k, 0)])' "$B/keel" "$SM")" \
      "True ['save']" "a Save the drain holds is a touch under the doc's key, so stand's sweep never stands over it (F9)"
rm -f "$S/events.json"

# S2: a next_after below the cursor is a suspicion, not a restart: an empty answer says 0 too
echo '{"comments": []}' > "$S/comments.txt"
cat > "$S/events.json" <<'EOF'
[{"seq": 1, "at": "2026-10-14T09:40:00Z", "name": "memo-save", "from": {"name": "sam"}, "data": {"items": {"D2": "A - old room"}, "comments": [], "feedback": ""}},
 {"seq": 7, "at": "2026-10-14T11:06:00Z", "name": "memo-save", "from": {"name": "sam"}, "data": {"items": {"D2": "A - old room"}, "comments": [], "feedback": ""}}]
EOF
echo '{"events": [], "next_after": 0}' > "$S/live-raw"
CUR=$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print([v for k, v in d.items() if k.endswith("docs/s.md")][0]["events_after"])' "$S/state/sheep.json")
srun sheep pull "$SM" > "$T/e1.out" 2>&1
lacks "$T/e1.out" "[save 1" "S2: an empty answer with next_after 0 does not make the room restarted: old Saves are not read again"
has "$T/e1.out" "would merge 0 threads — " "…nothing is taken"
check "$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print([v for k, v in d.items() if k.endswith("docs/s.md")][0]["events_after"])' "$S/state/sheep.json")" "$CUR" "…and the cursor stands"
# …a real restart: the room counts from 1 again, with events newer than any seen
cat > "$S/events.json" <<'EOF'
[{"seq": 1, "at": "2026-10-16T08:00:00Z", "name": "memo-save", "from": {"name": "sam"}, "data": {"items": {"D2": "B - the new room"}, "comments": [], "feedback": ""}}]
EOF
srun sheep pull "$SM" > "$T/e2.out" 2>&1
has "$T/e2.out" "[save 1, 2026-10-16 08:00, by sam] → D2" "…a restart shown by an event newer than any seen is read from seq 1"
# …a Save repeated in one answer is one Save
rm -f "$S/live-raw"
cat > "$S/events.json" <<'EOF'
[{"seq": 2, "at": "2026-10-16T09:00:00Z", "name": "memo-save", "from": {"name": "sam"}, "data": {"items": {"D1": "later"}, "comments": [], "feedback": ""}},
 {"seq": 2, "at": "2026-10-16T09:00:00Z", "name": "memo-save", "from": {"name": "sam"}, "data": {"items": {"D1": "later"}, "comments": [], "feedback": ""}}]
EOF
srun sheep pull "$SM" > "$T/e3.out" 2>&1
check "$(grep -c '\[save 2,' "$T/e3.out")" "1" "…and a Save the room repeats is taken once (de-duplicated by seq and time)"
rm -f "$S/live-raw"
srun sheep pull --write "$SM" > /dev/null 2>&1
gitc "$G/sh" checkout -q -- docs/s.md

# S3: a second Save from one page load names the same old commit; the first one's answer is not git's change
OLD=$(git -C "$G/sh" rev-parse HEAD)
cat > "$S/events.json" <<EOF
[{"seq": 3, "at": "2026-10-16T10:00:00Z", "name": "memo-save", "from": {"name": "sam"}, "data": {"sha": "$OLD", "items": {"D2": "A - first"}, "comments": [], "feedback": ""}}]
EOF
srun sheep pull --write "$SM" > "$T/f1.out" 2>&1
check "$(grep -A2 '➤ Recommended: B' "$SM" | tail -1)" "  A - first" "S3: a Save is taken"
gitc "$G/sh" commit -qam "first Save"
cat > "$S/events.json" <<EOF
[{"seq": 3, "at": "2026-10-16T10:00:00Z", "name": "memo-save", "from": {"name": "sam"}, "data": {"sha": "$OLD", "items": {"D2": "A - first"}, "comments": [], "feedback": ""}},
 {"seq": 4, "at": "2026-10-16T10:05:00Z", "name": "memo-save", "from": {"name": "sam"}, "data": {"sha": "$OLD", "items": {"D2": "B - second"}, "comments": [], "feedback": ""}}]
EOF
srun sheep pull --write "$SM" > "$T/f2.out" 2>&1
lacks "$T/f2.out" "git changed it after the page's commit" "…a second Save from the same page load is not held back by the first"
check "$(grep -A2 '➤ Recommended: B' "$SM" | tail -1)" "  B - second" "…the newer Save wins"
gitc "$G/sh" commit -qam "second Save"
sedi 's/  B - second/  typed on GitHub/' "$SM"; gitc "$G/sh" commit -qam "answer on GitHub"
cat > "$S/events.json" <<EOF
[{"seq": 5, "at": "2026-10-16T10:10:00Z", "name": "memo-save", "from": {"name": "sam"}, "data": {"sha": "$OLD", "items": {"D2": "A - third"}, "comments": [], "feedback": ""}}]
EOF
srun sheep pull "$SM" > "$T/f3.out" 2>&1
has "$T/f3.out" "D2 (git changed it after the page's commit)" "…but an answer git changed since is still git's"
rm -f "$S/events.json"
gitc "$G/sh" reset -q --hard "$OLD"
python3 -c 'import json,sys; f=sys.argv[1]; d=json.load(open(f)); [v.pop("saves", None) for v in d.values()]; json.dump(d, open(f, "w"))' "$S/state/sheep.json"

# S4: a Save drained into the pin while a wait listens wakes it at the next round, not only at its start
echo '{"comments": []}' > "$S/comments.txt"
srun sheep wait "$SM" --idle 12 --poll 1 --quiet 1 > "$T/w5.out" 2>&1 &
wpid=$!
# Inject only once the wait is past its start-up check and in its loop: a Save there already wakes it
# with the same words, and the case would pass without the per-round check it is for (review 2026-10-18).
for _ in $(seq 100); do grep -q "listening on" "$T/w5.out" 2>/dev/null && break; sleep 0.1; done
sleep 1.5
# The drain goes through keel's own update_pin, as a real `sheep pull` does. An in-place json.dump
# here truncates sheep.json under the live wait: when its own locked update_pin (drain_saves, every
# round) reads that empty file, it writes back a map without the Save — and without the pin's space
# (red 2026-10-18 under load, on both Macs; proved by widening that window to 3 s: 2 of 2 failed).
check "$(MEMO_SHEEP_STATE="$S/state" python3 -c 'import sys; from importlib.machinery import SourceFileLoader as L; m = L("m", sys.argv[1]).load_module(); print(len([m.update_pin(k, lambda p: dict(p, saves=[{"seq": 77, "at": "2026-10-16T12:00:00Z", "from": "t", "data": {"items": {"D1": "drained answer"}, "comments": [], "feedback": ""}}])) for k in list(m.pins()) if k.endswith("docs/s.md")]))' "$B/keel")" "1" "S4: the Save is drained into the one pin the wait listens on"
for _ in $(seq 100); do kill -0 "$wpid" 2>/dev/null || break; sleep 0.1; done
check "$(kill -0 "$wpid" 2>/dev/null && echo running || echo exited)" "exited" "S4: a wait wakes on a Save a pull drained into the pin while it listened"
kill "$wpid" 2>/dev/null
has "$T/w5.out" "memo sheep wait: a Save already drained from the page — taking it in" "…saying what woke it"
check "$(grep -A1 'D1 — Ship it' "$SM" | tail -1)" "  ➤ Answer: drained answer" "…and taking it in"
gitc "$G/sh" checkout -q -- docs/s.md

# S4: the comments route failing is remembered for the run: one web-session POST and one warning across a wait's polls
: > "$S/web.log"
srun sheep wait "$SM" --idle 5 --poll 1 --quiet 1 > "$T/w6.out" 2>&1
check "$(grep -c 'web-session' "$S/web.log")" "1" "S4: the key is traded for a web session once, though the route failed and the wait polled again"
check "$(grep -c 'the comments route failed' "$T/w6.out")" "1" "…and the warning is printed once"

echo "status / stand — recommendations stand at link + 24 h (D11-A, E10)"
# One bare repo per case plays GitHub (a touch on a branch voids every doc on it). Commit dates
# and MEMO_NOW pin the clock: the link is 2026-10-01 09:00 UTC, so the deadline 2026-10-02 09:00.
export TZ=UTC
ST="$T/stand"; mkdir -p "$ST"
# helm's ships, which the sweep reads for a branch's mode (skipper-modes S1): the suite's own, never the Mac's
export PLANS_DIR="$T/plans"; mkdir -p "$PLANS_DIR"
SURL=https://github.com/owner/
sg() { git -c user.name=t -c user.email=t@t -c "url.$ST/.insteadOf=$SURL" -C "$1" "${@:2}"; }
scommit() { local r=$1 d=$2; shift 2; GIT_AUTHOR_DATE=$d GIT_COMMITTER_DATE=$d git -c user.name=t -c user.email=t@t -C "$r" commit -q "$@"; }
mrun() { (export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0="url.$ST/.insteadOf" GIT_CONFIG_VALUE_0="$SURL" \
          GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t; "$B/keel" "$@"); }
mkdoc() {  # file, number of D-items — D10's shape, every item Reversible: yes, every answer block empty
  mkdir -p "$(dirname "$1")"
  { printf '# Stand me\n\nContext.\n\n## Decisions\n\n'
    for n in $(seq "$2"); do printf -- '- **D%d — Item %d?** Body.\n  - A — yes\n  - B — no\n\n  Reversible: yes\n\n  ➤ Recommended: A, pick %d\n\n  ➤ Answer:\n\n' "$n" "$n" "$n"; done
    printf '## Open feedback\n'; } > "$1"
}
mkrepo() {  # name, the contract's physical line ("" = no line), D-items (default 3)
  local r="$ST/$1"
  git init -q --bare "$ST/$1.git"; git init -q -b main "$r"; git -C "$r" remote add origin "$SURL$1.git"
  { printf '# %s\n\n## Session contract\n\n- check: true\n' "$1"; [ -n "$2" ] && printf '%s\n' "$2"; } > "$r/AGENTS.md"
  sg "$r" add AGENTS.md; scommit "$r" 2026-09-30T09:00:00Z -m contract; sg "$r" push -q origin main 2>/dev/null
  sg "$r" checkout -q -b claude/x
  mkdoc "$r/docs/${DOC:-d.md}" "${3:-3}"; sg "$r" add docs
  scommit "$r" 2026-10-01T09:00:00Z -m "Design: d" -m "Prompt:
> design it" -m "Claude-Session: abc12345"
  sg "$r" push -q origin claude/x 2>/dev/null
}
field() { python3 -c 'import json,sys
try: print(json.loads(sys.argv[1])[sys.argv[2]])
except Exception: print("error: " + sys.argv[1])' "$1" "$2"; }
status() { mrun status --json "$ST/$1/docs/${DOC:-d.md}" 2>&1; }

mkrepo none "- physical: none"
export MEMO_NOW=2026-10-02T08:00:00Z
S=$(status none)
check "$(field "$S" verdict)" "stands-at" "before the deadline: stands-at"
check "$(field "$S" deadline)" "2026-10-02T09:00:00+00:00" "…the deadline is the link commit + 24 h"
check "$(python3 -c 'import json,sys; print(sorted(json.loads(sys.argv[1])))' "$S")" \
      "['branch', 'deadline', 'doc', 'items', 'reason', 'repo', 'review', 'standable', 'unanswered', 'unstandable', 'verdict']" "--json carries the lander's contract, E14's review and S3's standable items beside it"
mrun stand --apply "$ST/none/docs/d.md" > "$T/sa0.out" 2>&1; rc=$?
check "$rc" "1" "--apply refuses before the deadline"
export MEMO_NOW=2026-10-02T09:00:01Z
S=$(status none)
check "$(field "$S" verdict)/$(field "$S" items)/$(field "$S" unanswered)" "due/3/3" "at the deadline, untouched: due, 3 of 3 unanswered"
mrun status "$ST/none/docs/d.md" > "$T/s1.out" 2>&1
check "$(wc -l < "$T/s1.out" | tr -d ' ')" "1" "plain status: one human line"
has "$T/s1.out" "docs/d.md (claude/x): due — deadline 2026-10-02 09:00 UTC passed" "…naming the verdict and the deadline"
mrun stand --apply "$ST/none/docs/d.md" > "$T/sa1.out" 2>&1; rc=$?
check "$rc" "0" "--apply on a due doc"
has "$T/sa1.out" "stood — D1, D2, D3" "…names the items it stood"
check "$(grep -c '^  > \*\*Applied.\*\* Stood 2026-10-02: no objection by 2026-10-02 09:00 UTC — A, pick ' "$ST/none/docs/d.md")" "3" "…an Applied reply under every unanswered item, with its Recommended pick"
"$B/keel" parse "$ST/none/docs/d.md" > "$T/parse.json"
check "$(py 'print([i["answer"] for i in d["items"]])')" "['', '', '']" "…the answer blocks stay empty"
has "$ST/none/docs/d.md" "  > **Applied.** Stood 2026-10-02: no objection by 2026-10-02 09:00 UTC — A, pick 2" "…D2's own pick"
check "$(git -C "$ST/none" log -1 --format=%B | grep -c '^Stood-By: autofinish$')" "1" "…committed with the Stood-By trailer"
check "$(git -C "$ST/none" status --porcelain)" "" "…and nothing left uncommitted"
check "$(field "$(status none)" verdict)" "stood" "after --apply: stood"
mrun stand --apply "$ST/none/docs/d.md" > "$T/sa2.out" 2>&1; rc=$?
check "$rc" "1" "a second --apply refuses"
printf '# New\n\n- **D1 — Q?** B.\n  ➤ Recommended: A\n\n  ➤ Answer:\n' > "$ST/none/docs/e.md"
mrun status --json "$ST/none/docs/e.md" > "$T/s2.out" 2>&1; rc=$?
check "$rc" "1" "a doc GitHub never showed has no link: no verdict, exit 1"
has "$T/s2.out" "has no link" "…and says so"

mkrepo big "- physical: none" 11
S=$(status big)
check "$(field "$S" verdict)/$(field "$S" items)" "too-big/11" "11 D-items: too-big"
mrun stand --by 0 "$ST/big/docs/d.md" > "$T/sb.out" 2>&1; rc=$?
check "$rc" "1" "…the explicit line refused too: never stands"
mrun stand --apply "$ST/big/docs/d.md" > /dev/null 2>&1; rc=$?
check "$rc" "1" "…and --apply refuses"

mkrepo gh "- physical: none"
git clone -q "$ST/gh.git" "$ST/gh-web" 2>/dev/null; git -C "$ST/gh-web" checkout -q claude/x
echo "typo fixed" > "$ST/gh-web/README.md"; git -C "$ST/gh-web" add README.md
GIT_AUTHOR_NAME=iMachine GIT_AUTHOR_EMAIL=i@m GIT_COMMITTER_NAME=GitHub GIT_COMMITTER_EMAIL=noreply@github.com \
  GIT_AUTHOR_DATE=2026-10-01T15:00:00Z GIT_COMMITTER_DATE=2026-10-01T15:00:00Z git -C "$ST/gh-web" commit -qm "Update README.md"
git -C "$ST/gh-web" push -q origin claude/x 2>/dev/null
S=$(status gh)
check "$(field "$S" verdict)" "voided" "a commit authored iMachine and committed GitHub, on another file, only on GitHub: voided"
case "$(field "$S" reason)" in *"a GitHub web edit"*"author iMachine"*) echo "  ok   …named as a GitHub web edit";; *) echo "  FAIL …named as a GitHub web edit: $S"; fails=$((fails+1));; esac

mkrepo ghnf "- physical: none"
git clone -q "$ST/ghnf.git" "$ST/ghnf-web" 2>/dev/null; git -C "$ST/ghnf-web" checkout -q claude/x
echo "typo fixed" > "$ST/ghnf-web/README.md"; git -C "$ST/ghnf-web" add README.md
GIT_AUTHOR_NAME=iMachine GIT_AUTHOR_EMAIL=i@m GIT_COMMITTER_NAME=GitHub GIT_COMMITTER_EMAIL=noreply@github.com \
  GIT_AUTHOR_DATE=2026-10-01T15:00:00Z GIT_COMMITTER_DATE=2026-10-01T15:00:00Z git -C "$ST/ghnf-web" commit -qm "Update README.md"
git -C "$ST/ghnf-web" push -q origin claude/x 2>/dev/null
check "$(field "$(mrun status --json --no-fetch "$ST/ghnf/docs/d.md" 2>&1)" verdict)" "due" \
  "--no-fetch: origin as last fetched — the web edit unseen (the lander's dry run)"
check "$(git -C "$ST/ghnf" rev-parse origin/claude/x)" "$(git -C "$ST/ghnf" rev-parse claude/x)" "…and no remote-tracking ref moved"
check "$(field "$(status ghnf)" verdict)" "voided" "…the plain status fetches and sees it: voided (a start's own judging)"

mkrepo agent "- physical: none"
echo "work" > "$ST/agent/x.txt"; echo "more" >> "$ST/agent/docs/d.md"; sg "$ST/agent" add -A
scommit "$ST/agent" 2026-10-01T10:00:00Z -m "Docs: tidy" -m "Claude-Session: abc12345"
check "$(field "$(status agent)" verdict)" "due" "a checkpoint with no prompt (the agent's own) is no touch"
echo "again" > "$ST/agent/x.txt"; sg "$ST/agent" add -A
scommit "$ST/agent" 2026-10-01T11:00:00Z -m "Work" -m "Prompt:
> what about D2?" -m "Claude-Session: abc12345"
S=$(status agent)
check "$(field "$S" verdict)/$(field "$S" deadline)" "stands-at/2026-10-02T11:00:00+00:00" "a checkpoint quoting a prompt after the link restarts the 24 h clock (entry D4-A), it no longer voids"
case "$(field "$S" reason)" in *"the clock restarted at 2026-10-01 11:00 UTC (a prompt in the session"*) echo "  ok   …named as a prompt";; *) echo "  FAIL …named as a prompt: $S"; fails=$((fails+1));; esac
check "$(field "$(MEMO_NOW=2026-10-02T11:00:01Z status agent)" verdict)" "due" "…and 24 h after the prompt, quiet, it is due"

mkrepo hand "- physical: none"
echo "Sam's note." >> "$ST/hand/docs/d.md"; sg "$ST/hand" add -A; scommit "$ST/hand" 2026-10-01T12:00:00Z -m "note"
check "$(field "$(status hand)" verdict)" "voided" "a commit on the doc with no agent trailer (Sam's own): voided"

mkrepo queued "- physical: none"
mkdir -p "$ST/queued/.git/claude"
printf '[{"session": "abc12345", "prompt": "hm", "ts": %s}]' "$(python3 -c 'import datetime as d; print(d.datetime(2026,10,1,12,tzinfo=d.timezone.utc).timestamp())')" > "$ST/queued/.git/claude/prompts.json"
S=$(status queued)
check "$(field "$S" verdict)/$(field "$S" deadline)" "stands-at/2026-10-02T12:00:00+00:00" "a prompt queued in the worktree's prompts.json after the link: the clock restarts"

mkrepo edit "- physical: none"
echo "typed here" >> "$ST/edit/docs/d.md"
S=$(status edit)
check "$(field "$S" verdict)/$(field "$S" deadline)" "stands-at/2026-10-03T09:00:01+00:00" "an uncommitted edit to the doc holds the clock at now + 24 h while it stays"

mkrepo void "- physical: none"
mrun stand --void "$ST/void/docs/d.md" > "$T/sv.out" 2>&1
has "$T/sv.out" "touched" "stand --void records a touch"
check "$(field "$(status void)" verdict)" "voided" "…and the doc reads voided"

mkrepo save "- physical: none"
# the touch `sheep pull --write` records for a Save from the page (tested in the sheep section)
python3 -c 'import sys; from importlib.machinery import SourceFileLoader as L; L("m", sys.argv[1]).load_module().record_touch(sys.argv[2], "save")' "$B/keel" "$ST/save/docs/d.md"
S=$(status save)
check "$(field "$S" verdict)" "voided" "a form Save: voided, from the touch log alone"
case "$(field "$S" reason)" in *"a form Save"*) echo "  ok   …named as a form Save";; *) echo "  FAIL …named as a form Save: $S"; fails=$((fails+1));; esac

mkrepo phys "- physical: a sweep of the house's devices"
mkdir -p "$ST/phys/.git/claude"
printf '[{"session": "abc12345", "prompt": "stand it", "ts": %s}]' "$(python3 -c 'import datetime as d; print(d.datetime(2026,10,1,12,tzinfo=d.timezone.utc).timestamp())')" > "$ST/phys/.git/claude/prompts.json"
check "$(field "$(status phys)" verdict)" "physical" "physical: not none, no Stands line: physical, past the deadline too"
mrun stand --apply "$ST/phys/docs/d.md" > /dev/null 2>&1; rc=$?
check "$rc" "1" "…--apply refuses"
mrun stand --by 2 "$ST/phys/docs/d.md" > "$T/sp.out" 2>&1
has "$T/sp.out" "stands at 2026-10-02 11:00 UTC (2026-10-02T11:00:01+00:00)" "stand --by 2: two hours from now"
check "$(sed -n 3p "$ST/phys/docs/d.md" | grep -c '^Stands: 2026-10-02T11:00:01+00:00 — set 2026-10-02T09:00:01+00:00')" "1" "…one Stands: line, under the title"
S=$(status phys)
check "$(field "$S" verdict)/$(field "$S" deadline)" "stands-at/2026-10-02T11:00:01+00:00" "…the explicit line overrides the deadline; the prompt before it is no touch"
mrun stand --by 0 "$ST/phys/docs/d.md" > /dev/null 2>&1
check "$(grep -c '^Stands:' "$ST/phys/docs/d.md")" "1" "stand --by 0 rewrites the line, never a second"
check "$(field "$(status phys)" verdict)" "due" "…and the doc is due now"
mrun stand --apply "$ST/phys/docs/d.md" > /dev/null 2>&1; rc=$?
check "$rc/$(field "$(status phys)" verdict)" "0/stood" "with the explicit line a physical repo's doc stands"

mkrepo physc "- physical: a real send into Messages"
mrun stand --by 0 "$ST/physc/docs/d.md" > /dev/null 2>&1
sg "$ST/physc" add -A; scommit "$ST/physc" 2026-10-02T09:00:30Z -m "Memo: stand d now" -m "Prompt:
> /keel stand docs/d.md --by 0" -m "Claude-Session: abc12345"
check "$(field "$(status physc)" verdict)" "due" "the checkpoint that commits the Stands line, quoting the prompt that asked for it, is no touch"
echo "later" > "$ST/physc/x.txt"; sg "$ST/physc" add -A
scommit "$ST/physc" 2026-10-02T09:00:40Z -m "Work" -m "Prompt:
> one more thing" -m "Claude-Session: abc12345"
S=$(status physc)
check "$(field "$S" verdict)/$(field "$S" deadline)" "stands-at/2026-10-03T09:00:40+00:00" "…a prompt after it restarts the explicit line's clock too"

mkrepo nocontract ""
S=$(status nocontract)
check "$(field "$S" verdict)" "no-contract" "no physical: line in the contract: no-contract"
mrun stand --by 0 "$ST/nocontract/docs/d.md" > "$T/sn.out" 2>&1; rc=$?
check "$rc" "1" "…stand refuses: never stands, by either path"
lacks "$ST/nocontract/docs/d.md" "Stands:" "…and writes no line"
mrun stand --apply "$ST/nocontract/docs/d.md" > /dev/null 2>&1; rc=$?
check "$rc" "1" "…nor --apply"
echo "the stand sweep's apply: Reversible: yes with a bare pick only, part-stood for the rest (entry S3, D4-A)"
# five items: D1 yes, D2 no, D3 unmarked, D4 yes with a conditional pick, D5 yes but reopened
mkrepo mixed "- physical: none" 5
python3 - "$ST/mixed/docs/d.md" <<'PY'
import re, sys
p = sys.argv[1]; t = open(p).read()
t = t.replace("- **D2 — Item 2?** Body.\n  - A — yes\n  - B — no\n\n  Reversible: yes", "- **D2 — Item 2?** Body.\n  - A — yes\n  - B — no\n\n  Reversible: no")
t = t.replace("- **D3 — Item 3?** Body.\n  - A — yes\n  - B — no\n\n  Reversible: yes\n\n", "- **D3 — Item 3?** Body.\n  - A — yes\n  - B — no\n\n")
t = t.replace("➤ Recommended: A, pick 4", "➤ Recommended: A if the probe passes, else B")
t = t.replace("  ➤ Recommended: A, pick 5\n\n  ➤ Answer:\n", "  ➤ Recommended: A, pick 5\n\n  ➤ Answer:\n  B\n\n  > **Reopened.** B needs a vendor the repo lacks.\n")
open(p, "w").write(t)
PY
sg "$ST/mixed" add docs; scommit "$ST/mixed" 2026-10-01T09:00:00Z --amend -m "Design: d" -m "Claude-Session: abc12345"
sg "$ST/mixed" push -q -f origin claude/x 2>/dev/null
S=$(status mixed)
check "$(field "$S" verdict)/$(field "$S" unanswered)" "due/5" "a due doc with five open items (the reopened one is open)"
check "$(field "$S" standable)" "['D1']" "…standable: the one Reversible: yes item with a bare pick"
check "$(field "$S" unstandable)" "[['D2', 'Reversible: no'], ['D3', 'unmarked'], ['D4', 'conditional'], ['D5', 'reopened']]" "…the rest named, each with why"
mrun stand --apply "$ST/mixed/docs/d.md" > "$T/sm.out" 2>&1; rc=$?
check "$rc" "0" "--apply stands what it can, no all-answered refusal"
has "$T/sm.out" "stood — D1 (" "…D1 stood"
has "$T/sm.out" "open: D2 Reversible: no, D3 unmarked, D4 conditional, D5 reopened" "…the open ones named"
check "$(grep -c '> \*\*Applied.\*\* Stood' "$ST/mixed/docs/d.md")" "1" "…one Applied reply, none under a reopened item"
has "$ST/mixed/docs/d.md" "  > **Reopened.** B needs a vendor the repo lacks." "…the reopened item's reply untouched"
check "$(git -C "$ST/mixed" log -1 --format=%B | grep -c '^Still open, Sam.s to answer: D2 (Reversible: no), D3 (unmarked), D4 (conditional), D5 (reopened).$')" "1" "…the commit says what is still open"
S=$(status mixed)
check "$(field "$S" verdict)" "part-stood" "after a partial stand: part-stood, never stood"
case "$(field "$S" reason)" in *"4 still open: D2 Reversible: no"*) echo "  ok   …the reason counts what is open";; *) echo "  FAIL …the reason counts what is open: $S"; fails=$((fails+1));; esac
mrun stand --apply "$ST/mixed/docs/d.md" > /dev/null 2>&1; check "$?" "1" "…and no second stand"
python3 -c 'import json,sys; r=[json.loads(l) for l in open(sys.argv[1])][-1]; print(r["repo"], r["branch"], r["doc"], r["stood"], r["open"])' "$MEMO_STATE_DIR/stood.jsonl" > "$T/stoodrow"
check "$(cat "$T/stoodrow")" "mixed claude/x docs/d.md ['D1'] ['D2', 'D3', 'D4', 'D5']" "…logged in stood.jsonl for the bulletin (S9)"
python3 - "$ST/mixed/docs/d.md" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
for n in (2, 3, 4):
    t = t.replace("➤ Recommended: A, pick %d\n\n  ➤ Answer:\n" % n, "➤ Recommended: A, pick %d\n\n  ➤ Answer:\n  B\n" % n, 1)
t = t.replace("➤ Recommended: A if the probe passes, else B\n\n  ➤ Answer:\n", "➤ Recommended: A if the probe passes, else B\n\n  ➤ Answer:\n  A\n")
t = t.replace("  > **Reopened.** B needs a vendor the repo lacks.\n", "  > **Reopened.** B needs a vendor the repo lacks.\n\n  > **Applied.** A, as Sam then wrote.\n")
open(p, "w").write(t)
PY
sg "$ST/mixed" add docs; scommit "$ST/mixed" 2026-10-02T10:00:00Z -m "answers"
check "$(field "$(status mixed)" verdict)" "stood" "Sam answers the rest: stood"

mkrepo nonestand "- physical: none" 2
sedi 's/^  Reversible: yes$/  Reversible: no/' "$ST/nonestand/docs/d.md"
sg "$ST/nonestand" add docs; scommit "$ST/nonestand" 2026-10-01T09:00:00Z --amend -m "Design: d" -m "Claude-Session: abc12345"
sg "$ST/nonestand" push -q -f origin claude/x 2>/dev/null
cp "$ST/nonestand/docs/d.md" "$T/ns.before"
mrun stand --apply "$ST/nonestand/docs/d.md" > "$T/sns.out" 2>&1; rc=$?
check "$rc" "1" "nothing standable: --apply refuses"
has "$T/sns.out" "nothing stands — D1 Reversible: no, D2 Reversible: no" "…and says why"
check "$(cmp -s "$ST/nonestand/docs/d.md" "$T/ns.before" && echo same)/$(git -C "$ST/nonestand" log -1 --format=%s)" "same/Design: d" "…writes and commits nothing"

echo "yolo and a reopened item (entry S3): not settled, and it stops the run"
printf '%s\n' '# Y' '' '## Decisions' '' '- **D1 — Q?** B.' '  - A — x' '  - B — y' '' '  Reversible: yes' '' '  ➤ Recommended: A' '' '  ➤ Answer:' '  B' '' '  > **Reopened.** B cannot be built here.' '' > "$T/yreo.md"
"$B/keel" parse "$T/yreo.md" > "$T/parse.json"
check "$(py 'print(d["items"][0]["settled"], d["items"][0]["answered"])')" "False False" "a reopened item: neither settled nor answered"
cp "$T/yreo.md" "$T/yreo.before"
"$B/keel" yolo "$T/yreo.md" > "$T/yreo.out"; rc=$?
check "$rc" "3" "yolo stops at a reopened item (exit 3)"
has "$T/yreo.out" "reopened" "…naming why"
check "$(cmp -s "$T/yreo.md" "$T/yreo.before" && echo same)" "same" "…and Sam's B is never overwritten by the pick"

echo "stand --sweep: every due doc on a claude/* worktree, stood and pushed, at most hourly (entry S3)"
# GitHub's owner/repo shape wants a flat name: the clones move under the sweep's root, their bare
# "GitHub" stays where the URL rewrite finds it
mkdir -p "$ST/sw"
mkrepo swa "- physical: none" 2; mv "$ST/swa" "$ST/sw/a"
mkrepo swb "- physical: none" 2; mv "$ST/swb" "$ST/sw/b"
mkdir -p "$ST/sw/b/.git/claude"
printf '{"session": "live1234", "branch": "claude/x", "seen": %s}' "$(python3 -c 'import datetime as d; print(d.datetime(2026,10,2,8,30,tzinfo=d.timezone.utc).timestamp())')" > "$ST/sw/b/.git/claude/owner.json"   # seen 30 min before MEMO_NOW
git -C "$ST/sw/a" worktree add -q "$ST/sw/a/.claude/worktrees/w2" -b claude/w2 main 2>/dev/null
mkdoc "$ST/sw/a/.claude/worktrees/w2/docs/e.md" 1; sg "$ST/sw/a/.claude/worktrees/w2" add docs
scommit "$ST/sw/a/.claude/worktrees/w2" 2026-10-01T09:00:00Z -m "Design: e" -m "Claude-Session: abc12345"
sg "$ST/sw/a/.claude/worktrees/w2" push -q origin claude/w2 2>/dev/null
git -C "$ST/sw/a" checkout -q main 2>/dev/null; mkdoc "$ST/sw/a/docs/m.md" 1; sg "$ST/sw/a" add docs
scommit "$ST/sw/a" 2026-10-01T09:00:00Z -m "a doc on main"; sg "$ST/sw/a" push -q origin main 2>/dev/null
git -C "$ST/sw/a" worktree add -q "$ST/sw/a/.claude/worktrees/x" claude/x 2>/dev/null
mrun stand --sweep --root "$ST/sw" --dry-run > "$T/sw0.out" 2>&1
has "$T/sw0.out" "a claude/x docs/d.md: would stand — D1, D2" "sweep --dry-run: names what would stand"
has "$T/sw0.out" "a claude/w2 docs/e.md: would stand — D1" "…in every worktree of the checkout, not the primary alone"
has "$T/sw0.out" "b claude/x docs/d.md: skipped — held by session live1234, seen 30m ago" "…a worktree a session holds (owner file within 2 h) is skipped"
lacks "$T/sw0.out" "docs/m.md" "…a doc on main is never swept"
mkdir -p "$PLANS_DIR/m1"; echo '{"id": "m1", "tasks": {"w2": {"branch": "claude/w2", "mode": "ask"}}}' > "$PLANS_DIR/m1/plan.json"
mrun stand --sweep --root "$ST/sw" --dry-run > "$T/sw0m.out" 2>&1
has "$T/sw0m.out" "a claude/w2 docs/e.md: skipped — mode ask (ship m1, task w2): nobody answers it but Sam" \
  "…a branch whose sent task is in mode ask is skipped: nothing answers it but Sam (skipper-modes S1)"
has "$T/sw0m.out" "a claude/x docs/d.md: would stand — D1, D2" "…another branch's doc still stands"
check "$(mrun status --json "$ST/sw/a/.claude/worktrees/w2/docs/e.md" 2>&1 | python3 -c 'import json, sys; print(json.load(sys.stdin)["verdict"])')" "ask-mode" \
  "…and its status says ask-mode, never due: autofinish's rule D cannot stand it either (landing review 8)"
rm -rf "$PLANS_DIR/m1"
check "$(git -C "$ST/sw/a/.claude/worktrees/x" log -1 --format=%s)" "Design: d" "…the dry run writes nothing"
printf '# Bad\n\n- **D1 — one.**\n  ➤ Answer:\n\n- **D1 — two.**\n  ➤ Answer:\n' > "$ST/sw/a/.claude/worktrees/w2/docs/bad.md"
sg "$ST/sw/a/.claude/worktrees/w2" add docs; scommit "$ST/sw/a/.claude/worktrees/w2" 2026-10-01T09:00:00Z -m "Design: bad"
mrun stand --sweep --root "$ST/sw" --dry-run > "$T/swbad.out" 2>&1
has "$T/swbad.out" "a claude/w2 docs/bad.md: unparseable — D1 appears twice" "…a doc that does not parse is named, never the sweep's end (the 2026-10-18 dream's D2)"
has "$T/swbad.out" "a claude/x docs/d.md: would stand — D1, D2" "…and the sweep goes on"
sg "$ST/sw/a/.claude/worktrees/w2" rm -q docs/bad.md; scommit "$ST/sw/a/.claude/worktrees/w2" 2026-10-01T09:00:00Z -m "Design: drop bad"
mrun stand --sweep --if-armed --root "$ST/sw" > "$T/sw1.out" 2>&1
check "$(cat "$T/sw1.out")" "" "--if-armed and not armed: nothing at all"
mrun stand --arm > /dev/null; test -f "$MEMO_STATE_DIR/sweep-armed"; check "$?" "0" "--arm writes the switch"
mrun stand --sweep --if-armed --root "$ST/sw" > "$T/sw2.out" 2>&1
has "$T/sw2.out" "a claude/x docs/d.md: stood — D1, D2 (" "armed: the due doc stood"
has "$T/sw2.out" "stand sweep: 3 docs on claude/* worktrees, 2 stood" "…one summary line"
check "$(git -C "$ST/swa.git" log -1 --format=%B claude/x | grep -c '^Stood-By: autofinish$')" "1" "…committed with Stood-By and pushed: GitHub has it"
check "$(git -C "$ST/swa.git" log -1 --format=%B claude/w2 | grep -c '^Stood-By: autofinish$')" "1" "…the second worktree's branch too"
check "$(git -C "$ST/sw/b" log -1 --format=%s)" "Design: d" "…the held worktree untouched"
mrun stand --sweep --if-armed --root "$ST/sw" > "$T/sw3.out" 2>&1
has "$T/sw3.out" "stand sweep: ran 0m ago; next after 60m" "a second run inside the hour does nothing"
mrun stand --disarm > /dev/null; test -f "$MEMO_STATE_DIR/sweep-armed"; check "$?" "1" "--disarm removes the switch"

unset MEMO_NOW

echo "yolo — E12, all the way (skipper-modes D1): every bare pick taken unattended, the first without one stops and nothing is written"
ydoc() {   # FILE MARK1 MARK2 REC2 — two items; MARK "" leaves the item unmarked
  { echo "# Y"; echo; echo 'Written by `architect` (Fable 5.1, `high`) on 2026-10-08 for "t".'; echo; echo "## Decisions"; echo
    for n in 1 2; do
      if [ "$n" = 1 ]; then mk="$2"; rc="B"; else mk="$3"; rc="$4"; fi
      echo "- **D$n — Item $n.** Context."; echo "  - A — one"; echo "  - B — two"; echo
      [ -n "$mk" ] && { echo "  Reversible: $mk"; echo; }
      echo "  ➤ Recommended: $rc"; echo; echo "  ➤ Answer:"; echo
    done
    echo "---"; echo; echo "## Open feedback"; } > "$1"
}
ydoc "$T/y1.md" yes yes A
python3 "$B/keel" yolo "$T/y1.md" --date 2026-10-08 > "$T/y1.out"; rc=$?
check "$rc" "0" "every open item Reversible: yes: exit 0, the run goes on"
check "$(python3 "$B/keel" parse "$T/y1.md" | python3 -c 'import json,sys; print([(i["id"], i["answer"], i["reversible"], i["answered"]) for i in json.load(sys.stdin)["items"]])')" \
  "[('D1', \"Taken unattended (Sam's yolo, 2026-10-08): B\", 'yes', True), ('D2', \"Taken unattended (Sam's yolo, 2026-10-08): A\", 'yes', True)]" \
  "…each answer block holds the Taken unattended line with its Recommended pick"
check "$(python3 "$B/keel" lint "$T/y1.md")" "$T/y1.md: no findings" "…and the doc still lints clean (no pre-fill warning)"
python3 "$B/keel" yolo "$T/y1.md" > "$T/y1b.out"; rc=$?
check "$rc" "0" "a second pass: nothing open, exit 0"
has "$T/y1b.out" "no open decision" "…and says so"
ydoc "$T/y2.md" yes no A
python3 "$B/keel" yolo "$T/y2.md" --date 2026-10-21 > "$T/y2.out"; rc=$?
check "$rc" "0" "a Reversible: no item is taken too: --yolo goes all the way (skipper-modes D1)"
check "$(grep -c "Taken unattended (Sam's yolo, 2026-10-21)" "$T/y2.md")" "2" "…both picks written"
ydoc "$T/y3.md" "" yes A
python3 "$B/keel" yolo "$T/y3.md" > "$T/y3.out"; rc=$?
check "$rc" "0" "an unmarked item with a bare pick is taken too"
ydoc "$T/y4.md" yes yes "none until the probe runs"; cp "$T/y4.md" "$T/y4.orig"
python3 "$B/keel" yolo "$T/y4.md" > "$T/y4.out"; rc=$?
check "$rc" "3" "a conditional pick stops it (a probe nobody ran)"
has "$T/y4.out" "stopped at D2" "…naming the item"
check "$(cmp -s "$T/y4.md" "$T/y4.orig" && echo same)" "same" "…and nothing is written, not even D1's pick"
ydoc "$T/y4b.md" yes no ""
python3 "$B/keel" yolo "$T/y4b.md" > "$T/y4b.out"; rc=$?
check "$rc" "3" "an item with no pick stops it"

echo "yolo --dnd — D1-A: the picks bar the held classes, each held item printed for a relay (exit 4)"
mkdir -p "$T/ydn"; git -C "$T/ydn" init -q; printf -- '- physical: none\n' > "$T/ydn/AGENTS.md"   # a physical: none repo
ydoc "$T/yd0.md" yes yes A
python3 "$B/keel" yolo "$T/yd0.md" --dnd > "$T/yd0.out"; rc=$?
check "$rc $(grep -c "Sam's dnd" "$T/yd0.md")" "4 0" "--dnd: a doc whose repo has no physical: line holds every item, read as physical (landing review 17)"
has "$T/yd0.out" "no \`physical:\` line" "…and says why"
ydoc "$T/ydn/yd1.md" yes no A
python3 "$B/keel" yolo "$T/ydn/yd1.md" --dnd --date 2026-10-21 > "$T/yd1.out"; rc=$?
check "$rc" "0" "--dnd: a plain Reversible: no item is taken (nothing held): exit 0"
check "$(grep -c "Taken unattended (Sam's dnd, 2026-10-21)" "$T/ydn/yd1.md")" "2" "…written as Sam's dnd"
check "$(python3 "$B/keel" parse "$T/ydn/yd1.md" | python3 -c 'import json,sys; print([(i["answered"], i["settled"]) for i in json.load(sys.stdin)["items"]])')" \
  "[(True, True), (True, True)]" "…settled, so dispatch's launch gate reads it past the gate"
mkdir -p "$T/ydr"; git -C "$T/ydr" init -q; printf -- '- physical: none\n' > "$T/ydr/AGENTS.md"
ydoc "$T/ydr/d.md" yes no A
python3 - "$T/ydr/d.md" <<'PYX'
import sys
p = sys.argv[1]; s = open(p).read()
s = s.replace("  - A — one\n", "  - A — one, a $12/yr domain\n", 1)          # D1: real money
i = s.index("- **D2")
s = s[:i] + s[i:].replace("  - B — two\n", "  - B — two, $40 ($0.78 effective) of tokens\n", 1)   # D2: a model cost only
open(p, "w").write(s)
PYX
python3 "$B/keel" yolo "$T/ydr/d.md" --dnd --date 2026-10-21 > "$T/yd2.out"; rc=$?
check "$rc" "4" "--dnd: an item with real money in an option is held: exit 4"
has "$T/yd2.out" "held D1 (line" "…named as held"
has "$T/yd2.out" "money in an option" "…with its class"
check "$(grep -c "Taken unattended (Sam's dnd" "$T/ydr/d.md")" "1" "…a model cost (\$list (\$eff effective)) is no money: D2 is taken"
for cls in "delete the old table:a deletion" "publish to the public twin:a public publish" "wait for the third-party answer:a third party's answer"; do
  ydoc "$T/ydn/yd3.md" yes yes A; w="${cls%%:*}"
  python3 - "$T/ydn/yd3.md" "$w" <<'PYX'
import sys
p = sys.argv[1]; s = open(p).read(); s = s.replace("  - A — one\n", "  - A — one, " + sys.argv[2] + "\n", 1); open(p, "w").write(s)
PYX
  python3 "$B/keel" yolo "$T/ydn/yd3.md" --dnd > "$T/yd3.out"; rc=$?
  check "$rc $(grep -c "held D1" "$T/yd3.out")" "4 1" "--dnd holds ${cls#*:}"
done
ydoc "$T/ydn/yd4.md" "" yes A
python3 "$B/keel" yolo "$T/ydn/yd4.md" --dnd > "$T/yd4.out"; rc=$?
check "$rc" "4" "--dnd holds an unmarked item (the yolo pass takes it)"
has "$T/yd4.out" "not marked Reversible" "…and says why"
ydoc "$T/ydn/yd5.md" yes yes "none until the probe runs"
python3 "$B/keel" yolo "$T/ydn/yd5.md" --dnd > "$T/yd5.out"; rc=$?
check "$rc $(grep -c "Sam's dnd" "$T/ydn/yd5.md")" "4 1" "--dnd: a conditional pick is held, not a stop: the rest is taken"
mkdir -p "$T/ydp"; git -C "$T/ydp" init -q; printf -- '- physical: a sweep of the house\n' > "$T/ydp/AGENTS.md"
ydoc "$T/ydp/d.md" yes yes A; cp "$T/ydp/d.md" "$T/ydp.orig"
python3 "$B/keel" yolo "$T/ydp/d.md" --dnd > "$T/yd6.out"; rc=$?
check "$rc $(cmp -s "$T/ydp/d.md" "$T/ydp.orig" && echo same)" "4 same" "--dnd in a repo whose contract is not physical: none holds every item"
ydoc "$T/ydn/yd7.md" yes no A; cp "$T/ydn/yd7.md" "$T/yd7.orig"
python3 "$B/keel" yolo "$T/ydn/yd7.md" --dnd --dry-run > "$T/yd7.out"; rc=$?
check "$rc $(cmp -s "$T/ydn/yd7.md" "$T/yd7.orig" && echo same)" "0 same" "--dry-run --dnd: the verdict, nothing written"
has "$T/yd7.out" "would take D2: Taken unattended (Sam's dnd" "…and the dnd line it would write"
python3 "$B/keel" yolo "$T/ydn/yd1.md" --dnd > "$T/yd8.out"; rc=$?
check "$rc" "0" "--dnd on a doc it already took: nothing open, exit 0"
ydoc "$T/y5.md" no yes A
python3 - "$T/y5.md" <<'PYX'
import sys
p = sys.argv[1]; s = open(p).read()
s = s.replace("  ➤ Answer:\n", "  ➤ Answer:\n  A, Sam's own\n", 1)   # D1 answered by Sam
open(p, "w").write(s)
PYX
python3 "$B/keel" yolo "$T/y5.md" --date 2026-10-08 > "$T/y5.out"; rc=$?
check "$rc" "0" "an item Sam answered is skipped, even one marked no"
has "$T/y5.md" "A, Sam's own" "…Sam's answer stays"
check "$(grep -c 'Taken unattended' "$T/y5.md")" "1" "…and only the open item is taken"
ydoc "$T/y6.md" yes yes A; cp "$T/y6.md" "$T/y6.orig"
python3 "$B/keel" yolo "$T/y6.md" --dry-run > "$T/y6.out"; rc=$?
check "$rc $(cmp -s "$T/y6.md" "$T/y6.orig" && echo same)" "0 same" "--dry-run: the verdict, nothing written"
has "$T/y6.out" "would take D2" "…and what it would take"
ydoc "$T/y7.md" "" yes A
python3 - "$T/y7.md" <<'PYX'
import sys
p = sys.argv[1]; s = open(p).read()
s = s.replace("  ➤ Answer:\n", "  ➤ Answer:\n  Reversible: yes\n", 1)   # in Sam's box: not the agent's mark
open(p, "w").write(s)
PYX
check "$(python3 "$B/keel" parse "$T/y7.md" | python3 -c 'import json,sys; print(json.load(sys.stdin)["items"][0]["reversible"])')" "None" "a Reversible line in the answer box is not the agent's mark"
rmark() { printf -- '- **D1 — X.** C.\n  - A — a\n\n  %s\n\n  ➤ Recommended: A\n\n  ➤ Answer:\n\n---\n' "$1" > "$T/rm.md"
  python3 "$B/keel" parse "$T/rm.md" | python3 -c 'import json,sys; print(json.load(sys.stdin)["items"][0]["reversible"])'; }
check "$(rmark '**Reversible:** yes') $(rmark '- **Reversible:** no') $(rmark '*Reversible:* yes.')" "yes no yes" \
  "the bold label, with the colon inside it, reads (review of 2026-10-08)"
check "$(rmark 'Reversible: yes, as long as the old table is kept') $(rmark 'Reversible: yes|no') $(rmark 'Reversible: no — deletes the table')" "None None no" \
  "a hedged yes, or the template's yes|no, is unmarked; a no may carry its reason"
ydoc "$T/y8.md" yes no A
python3 - "$T/y8.md" <<'PYX'
import sys
p = sys.argv[1]; s = open(p).read()
i = s.index("- **D2")
s = s[:i] + s[i:].replace("  ➤ Answer:\n", "  ➤ Answer:\n\n> Proceeding with A (unattended).\n", 1)   # a session's own reply
open(p, "w").write(s)
PYX
check "$(python3 "$B/keel" parse "$T/y8.md" | python3 -c 'import json,sys; print([(i["answered"], i["settled"]) for i in json.load(sys.stdin)["items"]])')" \
  "[(False, False), (True, False)]" "parse: answered counts a session's own > reply, settled (the landing's test) does not"
python3 "$B/keel" yolo "$T/y8.md" > "$T/y8.out"; rc=$?
check "$rc $(grep -c 'took D2' "$T/y8.out")" "0 1" "…so yolo still takes D2's pick: the session's reply never cleared the gate"

echo "review status — unseen · opened · partial · reviewed, stood beside it (E14)"
export MEMO_NOW=2026-10-02T08:00:00Z
rv() { python3 -c 'import json,sys
try: r = json.loads(sys.argv[1])["review"]; print(r[sys.argv[2]])
except Exception: print("error: " + sys.argv[1])' "$1" "$2"; }
mkrepo rvu "- physical: none"
S=$(status rvu)
check "$(rv "$S" word)/$(rv "$S" phrase)" "unseen/unseen 0/3, stands Fri 09:00" "a doc nobody opened: unseen, with when it stands"
mrun status "$ST/rvu/docs/d.md" > "$T/rv1.out" 2>&1
has "$T/rv1.out" "· review: unseen 0/3, stands Fri 09:00" "…the plain line says it too"
echo "more context" >> "$ST/rvu/docs/d.md"; sg "$ST/rvu" add -A
scommit "$ST/rvu" 2026-10-01T10:00:00Z -m "Docs: tidy" -m "Claude-Session: abc12345"
check "$(rv "$(status rvu)" word)" "unseen" "an agent's checkpoint on the doc is not Sam: still unseen"

mkrepo rvy "- physical: none"
python3 - "$ST/rvy/docs/d.md" <<'PYX'
import sys
p = sys.argv[1]; s = open(p).read()
open(p, "w").write(s.replace("  ➤ Answer:\n", "  ➤ Answer:\n  Taken unattended (Sam's yolo, 2026-10-01): A\n"))
PYX
S=$(status rvy)
check "$(field "$S" verdict) $(rv "$S" word) $(rv "$S" taken)" "taken unseen 3" \
  "memo yolo's picks are not Sam's: verdict taken (the sweep never lands it), review unseen (review of 2026-10-08)"
check "$(field "$S" lands) $(field "$S" mode) $(field "$S" taken_by)" "False None ['yolo']" \
  "  S3b: with no sent task on the branch, a taken doc lands by Sam's tap (yolo-veto D1 for default)"
mkdir -p "$PLANS_DIR/m3"; echo '{"id": "m3", "tasks": {"x": {"branch": "claude/x", "mode": "yolo"}}}' > "$PLANS_DIR/m3/plan.json"
S=$(status rvy)
check "$(field "$S" verdict) $(field "$S" lands) $(field "$S" mode)" "taken True yolo" "  …a ship in mode yolo lands it by itself: the mode is read, not the record line"
echo '{"id": "m3", "tasks": {"x": {"branch": "claude/x", "mode": "dnd"}}}' > "$PLANS_DIR/m3/plan.json"
check "$(field "$(status rvy)" lands)" "False" "  …lowered to dnd, a yolo pick (no holds applied) does not land"
rm -rf "$PLANS_DIR/m3"

mkrepo rvm "- physical: none"
python3 - "$ST/rvm/docs/d.md" <<'PYX'
import sys
p = sys.argv[1]; s = open(p).read()
open(p, "w").write(s.replace("  ➤ Answer:\n", "  ➤ Answer:\n  Relayed from manager · buildbox (yes item, 2026-10-15): A\n"))
PYX
S=$(status rvm)
check "$(field "$S" verdict) $(rv "$S" word) $(rv "$S" taken)" "taken unseen 3" \
  "a manager's relayed answer is not Sam's: taken, so rule D never lands it (stray-manager B1 iii)"
# helm's asklib reads the owner's name from regatta/owner once helm's scrub lands; before it, the two
# cases relaying the owner's own word would test helm's old literal, not keel, and skip
AOWN=$(python3 - "$(peer asklib.py)" <<'PYX'
import sys
from importlib.machinery import SourceFileLoader as L
a = L("a", sys.argv[1]).load_module() if sys.argv[1] else None
fn = a and (getattr(a, "relayed_by_owner", None) or next((getattr(a, n) for n in sorted(dir(a)) if n.startswith("relayed_by_")), None))
print("yes" if fn and fn("Relayed from manager (x) (Sam's form, 2026-10-16): A") is not False else "no")
PYX
)
skip_aown() { echo "  --   skipped: $1 (helm's asklib does not read regatta/owner yet: helm's scrub)"; }
mkrepo rvi "- physical: none"
python3 - "$ST/rvi/docs/d.md" <<'PYX'
import sys
p = sys.argv[1]; s = open(p).read()
open(p, "w").write(s.replace("  ➤ Answer:\n", "  ➤ Answer:\n  Relayed from manager · buildbox (Sam, Session tab (signed), 2026-10-15): B\n", 1))
PYX
S=$(status rvi)
if [ "$AOWN" = yes ]; then
  check "$(rv "$S" taken) $([ "$(field "$S" verdict)" != taken ] && echo not-taken)" "0 not-taken" "  one Sam answered on the Session tab, relayed: Sam's word, not taken"
else skip_aown "one Sam answered on the Session tab"; fi
# review gate 2026-10-16: the test is asklib's relayed_by_owner, and it fails closed
rvx() {  # rvx <repo> <answer line>: one item answered with that line; prints taken and the verdict
  mkrepo "$1" "- physical: none"
  python3 - "$ST/$1/docs/d.md" "$2" <<'PYX'
import sys
p = sys.argv[1]; s = open(p).read()
open(p, "w").write(s.replace("  ➤ Answer:\n", "  ➤ Answer:\n  %s\n" % sys.argv[2]))
PYX
  S=$(status "$1"); echo "$(rv "$S" taken) $([ "$(field "$S" verdict)" = taken ] && echo taken || echo not-taken)"
}
check "$(rvx rvp 'Relayed from manager (buildbox) (yes item, 2026-10-16): A')" "3 taken" \
  "  a 'who' with a parenthesis, --from \"manager (buildbox)\": still the manager's, taken (it failed open)"
if [ "$AOWN" = yes ]; then
  check "$(rvx rvf "Relayed from manager (buildbox) (sam's form, 2026-10-16): A")" "0 not-taken" "  \"sam's form\", any case, behind that 'who': Sam's"
else skip_aown "\"sam's form\" behind a 'who'"; fi
check "$(rvx rvs 'Relayed from manager · buildbox (Session tab, Sam (signed), 2026-10-16): A')" "3 taken" \
  "  'Session tab, Sam (signed)': the source does not begin with Sam — taken"
check "$(rvx rvb 'Relayed from manager · buildbox (Sam, 2026-10-16): A')" "3 taken" "  a bare 'Sam' names no route: taken"

mkrepo rvo "- physical: none"
# what drain_saves writes for a `memo-open` from the page (tested in the sheep section)
python3 -c 'import sys; from importlib.machinery import SourceFileLoader as L; L("m", sys.argv[1]).load_module().record_open(sys.argv[2])' "$B/keel" "$ST/rvo/docs/d.md"
check "$(python3 -c 'import json,sys
r = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
r = [x for x in r if x["path"].endswith("/rvo/docs/d.md")]
print(len(r), sorted(r[-1]), r[-1]["doc"], r[-1]["branch"])' "$MEMO_STATE_DIR/opens.jsonl")" \
      "1 ['branch', 'doc', 'path', 'repo', 'ts', 'who'] docs/d.md claude/x" "a page open logs one row in opens.jsonl: doc, repo, branch, ts, who"
S=$(status rvo)
check "$(rv "$S" word)/$(field "$S" verdict)" "opened/stands-at" "an open logged: opened — and an open is no touch, the doc still stands"

mkrepo rvg "- physical: none"
git clone -q "$ST/rvg.git" "$ST/rvg-web" 2>/dev/null; git -C "$ST/rvg-web" checkout -q claude/x
echo "a typo fixed on GitHub" >> "$ST/rvg-web/docs/d.md"; git -C "$ST/rvg-web" add docs
GIT_AUTHOR_NAME=iMachine GIT_AUTHOR_EMAIL=i@m GIT_COMMITTER_NAME=GitHub GIT_COMMITTER_EMAIL=noreply@github.com \
  GIT_AUTHOR_DATE=2026-10-01T15:00:00Z GIT_COMMITTER_DATE=2026-10-01T15:00:00Z git -C "$ST/rvg-web" commit -qm "Update d.md"
git -C "$ST/rvg-web" push -q origin claude/x 2>/dev/null
check "$(rv "$(status rvg)" word)" "opened" "a GitHub web edit of the doc (committer GitHub, author iMachine), not pulled yet, nothing answered: opened"

mkrepo rvp "- physical: none"
python3 - "$ST/rvp/docs/d.md" <<'PY'
import sys; p = sys.argv[1]; s = open(p).read()
open(p, "w").write(s.replace("  ➤ Answer:\n", "  ➤ Answer:\n  B — not this one\n", 1))
PY
S=$(status rvp)
check "$(rv "$S" word)/$(rv "$S" answered)" "partial/1" "one of three answered (typed, not yet committed): partial 1/3"
mkrepo rvn "- physical: none"
printf '\n**Sam, 2026-10-01:** why not both?\n' >> "$ST/rvn/docs/d.md"
check "$(rv "$(status rvn)" phrase)" "partial 0/3, stands Sat 08:00" "a note and no answer: partial 0/3 (typed, uncommitted: the clock waits a day from now)"

mkrepo rvr "- physical: none"
python3 - "$ST/rvr/docs/d.md" <<'PY'
import sys; p = sys.argv[1]; s = open(p).read()
open(p, "w").write(s.replace("  ➤ Answer:\n", "  ➤ Answer:\n  = recommended (accept all)\n"))
PY
S=$(status rvr)
check "$(rv "$S" phrase)/$(field "$S" verdict)" "reviewed 3/3 (accept all)/answered" "every item answered by the accept-all Save: reviewed (accept all)"

mkrepo rvw "- physical: none" 11
check "$(rv "$(status rvw)" phrase)" "unseen 0/11, waits" "over ten D-items: waits beside the status"

DOC=s-2026-10-01.md mkrepo rvs "- physical: none"
export MEMO_NOW=2026-10-02T09:00:01Z
DOC=s-2026-10-01.md
mrun stand --apply "$ST/rvs/docs/s-2026-10-01.md" > "$T/rvs.out" 2>&1; rc=$?
check "$rc" "0" "stand --apply on an unseen record"
S=$(status rvs)
check "$(rv "$S" word)/$(rv "$S" stood)/$(rv "$S" phrase)" "unseen/True/unseen 0/3, stood" "stood never reads reviewed: the Applied replies are not Sam's"
check "$(grep -c '^> \*\*Record' "$ST/rvs/docs/s-2026-10-01.md")" "0" \
      "…a repo with no docs map gets no banner from the stamp: nothing asked for one there"
check "$(git -C "$ST/rvs" status --porcelain)" "" "…and --apply's Stood-By commit leaves the tree clean"
python3 - "$ST/rvs/docs/s-2026-10-01.md" <<'PY'
import sys; p = sys.argv[1]; l = open(p).read().split("\n")
l[2:2] = ["> **Record.** Current state: [chart](../x.md), kept by hand.", ""]
open(p, "w").write("\n".join(l))
PY
mrun status --stamp "$ST/rvs/docs/s-2026-10-01.md" > /dev/null 2>&1
check "$(sed -n 3p "$ST/rvs/docs/s-2026-10-01.md")" "> **Record.** Current state: [chart](../x.md), kept by hand. · review: unseen → stood" \
      "…a banner already there keeps its own text and takes the word at its end"
unset DOC

mkrepo rvt "- physical: none"
python3 - "$ST/rvt/docs/d.md" <<'PY'
import sys; p = sys.argv[1]; s = open(p).read()
s = s.replace("  ➤ Answer:\n", "  ➤ Answer:\n\n> **Taken as recommended (A)** — unanswered; say so to change.\n", 1)
open(p, "w").write(s + "\n> Sam flagged in chat that this one matters.\n> Context: the wrapped line of a quote.\n")
PY
S=$(status rvt)
check "$(rv "$S" word)/$(rv "$S" answered)/$(rv "$S" notes)" "unseen/0/0" \
      "an agent's own reply (not Done/Applied/…) and a quote starting with the name are not Sam's: still unseen"

mkrepo rvm "- physical: none"
R2="$ST/rvm"
mkdir -p "$R2/docs/record"
printf '# docs\n\nmode: dry\n\n| Topic | Chart | Records | Code |\n| --- | --- | --- | --- |\n| stand | — | [m-2026-10-01.md](m-2026-10-01.md) | `bin/x` |\n' > "$R2/docs/README.md"
mkdoc "$R2/docs/m-2026-10-01.md" 2
python3 - "$R2/docs/m-2026-10-01.md" <<'PY'
import sys; p = sys.argv[1]; s = open(p).read()
open(p, "w").write(s.replace("  ➤ Answer:\n", "  ➤ Answer:\n  A\n"))
PY
sg "$R2" add -A; scommit "$R2" 2026-10-01T09:30:00Z -m "Design: m" -m "Claude-Session: abc12345"
mrun status --stamp "$R2/docs/m-2026-10-01.md" > "$T/rvm.out" 2>&1
has "$T/rvm.out" "stamped docs/m-2026-10-01.md: review: reviewed" "status --stamp on a reviewed record"
check "$(sed -n 3p "$R2/docs/m-2026-10-01.md")" "> **Record.** No chart yet — the map [docs/README.md](README.md) says where the newest state is. · review: reviewed" \
      "…a new banner where it had none, the map's own form, the word at its end"
mrun status --stamp "$R2/docs/m-2026-10-01.md" > "$T/rvm2.out" 2>&1
has "$T/rvm2.out" "unchanged docs/m-2026-10-01.md" "…stamping again changes nothing"
check "$(grep -c '^> \*\*Record' "$R2/docs/m-2026-10-01.md")" "1" "…one banner, never a second"
python3 "$DI" check --repo "$R2" > "$T/rvc.out"
has "$T/rvc.out" "1 Records cell(s) lack their record's review word (docs-index reviews --write): m-2026-10-01.md" "docs-index check notes a Records cell without the word"
python3 "$DI" reviews --write --repo "$R2" > /dev/null
has "$R2/docs/README.md" "| stand | — | [m-2026-10-01.md](m-2026-10-01.md) *reviewed* | \`bin/x\` |" "reviews --write: the word as a suffix in the Records cell"
python3 "$DI" reviews --repo "$R2" > "$T/rvr2.out"
has "$T/rvr2.out" "ok    every Records cell" "…then nothing is stale"
sg "$R2" add -A; scommit "$R2" 2026-10-01T09:40:00Z -m "Docs: stamp" -m "Claude-Session: abc12345"
python3 "$DI" move m-2026-10-01.md --repo "$R2" > /dev/null
check "$(sed -n 3p "$R2/docs/record/m-2026-10-01.md")" "> **Record.** No chart yet — the map [docs/README.md](../README.md) says where the newest state is. · review: reviewed" \
      "the stamp survives docs-index move (the banner's link re-based, the word kept)"
has "$R2/docs/README.md" "[m-2026-10-01.md](record/m-2026-10-01.md) *reviewed*" "…and so does the map's suffix"
printf '# Stand\n\nx\n\nRecords: [m-2026-10-01.md](record/m-2026-10-01.md)\n' > "$R2/docs/stand.md"
sedi 's/| stand | — |/| stand | [stand.md](stand.md) |/' "$R2/docs/README.md"
python3 "$DI" banner m-2026-10-01.md stand.md --repo "$R2" > /dev/null
check "$(sed -n 3p "$R2/docs/record/m-2026-10-01.md" | sed 's/.*\(· review: .*\)$/\1/')" "· review: reviewed" "…and a banner rewrite (the charts run) keeps it"
python3 "$DI" check --strict --repo "$R2" > "$T/rvc2.out"; rc=$?
check "$rc" "0" "…and the map checks clean with it"

mkdoc "$R2/docs/n-2026-10-02.md" 1
mrun status --stamp "$R2/docs/n-2026-10-02.md" > /dev/null 2>&1
has "$R2/docs/n-2026-10-02.md" "No chart yet" "a record stamped before the map has it: the no-chart banner"
sedi 's/| \[m-2026-10-01.md\](record\/m-2026-10-01.md) \*reviewed\* |/| [m-2026-10-01.md](record\/m-2026-10-01.md) *reviewed*, [n-2026-10-02.md](n-2026-10-02.md) |/' "$R2/docs/README.md"
printf '# Stand\n\nx\n\nRecords: [m-2026-10-01.md](record/m-2026-10-01.md), [n-2026-10-02.md](n-2026-10-02.md)\n' > "$R2/docs/stand.md"
python3 "$DI" check --repo "$R2" > "$T/rvc3.out"
has "$T/rvc3.out" "banner points at no chart, its row at docs/stand.md (docs-index banner n-2026-10-02.md docs/stand.md fixes it)" \
    "…mapped later into a charted row: check names the fix (the charts run's step 3)"
python3 "$DI" banner n-2026-10-02.md stand.md --repo "$R2" > /dev/null
python3 "$DI" check --strict --repo "$R2" > "$T/rvc4.out"; rc=$?
check "$rc" "0" "…and after it the map checks clean"
has "$R2/docs/n-2026-10-02.md" "· review: unseen" "…with the stamped word kept"
sg "$R2" add -A; scommit "$R2" 2026-10-02T09:40:00Z -m "Docs: map n" -m "Claude-Session: abc12345"
cur=$(git -C "$R2" symbolic-ref --short HEAD)
git -C "$R2" branch -q -f main HEAD 2>/dev/null; git -C "$R2" checkout -q -b claude/other
echo "another branch's line" >> "$R2/docs/n-2026-10-02.md"; sg "$R2" add -A
scommit "$R2" 2026-10-02T09:45:00Z -m "Docs: other" -m "Claude-Session: def67890"
git -C "$R2" checkout -q "$cur"
mrun status --stamp "$R2/docs/n-2026-10-02.md" > "$T/rvk.out" 2>&1
has "$T/rvk.out" "skipped docs/n-2026-10-02.md: claude/other edits it too" "a record another unmerged branch edits is not stamped (R2, as docs-index banner)"

python3 "$B/keel" list --root "$ST" --limit 0 > "$T/rvl.out" 2>&1
check "$(grep -A0 'Stand me' "$T/rvl.out" | grep -c '· unseen 0/11, waits$')" "2" "memo list gains the column (the two 11-item fixtures: unseen 0/11, waits)"
has "$T/rvl.out" "review: unseen — no sign of Sam · opened — the form was loaded (the page anywhere, memo serve on this Mac)" "…and a legend: opened is not read (R34)"
check "$(awk '/— stood: the deadline answered these, not Sam —/{h=1} h && /, stood$/{print "under"; exit}' "$T/rvl.out")" "under" \
      "…and a stood doc sits under its own header (R35)"

touch -t 202609300000 "$ST/rvu/.git/refs/heads/claude/x"
python3 - "$ST/rvu" "$WH" > "$T/rvb.out" 2>&1 <<'PY'
import sys, time
sys.path.insert(0, sys.argv[2])
import branches
done, maybe, pending = branches.survey(sys.argv[1], now=time.time() + 30 * 86400, reviews=True)
for b in pending:
    print(branches.describe(b, time.time()))
PY
has "$T/rvb.out" "docs/d.md: unseen 0/3, due" "hooks/branches.py: an unlanded branch's description carries its doc's review status"
git clone -q "$ST/rvu.git" "$ST/rvu-clone" 2>/dev/null; git -C "$ST/rvu-clone" checkout -q main 2>/dev/null
python3 - "$ST/rvu-clone" "$WH" > "$T/rvb2.out" 2>&1 <<'PY'
import sys, time
sys.path.insert(0, sys.argv[2])
import branches
done, maybe, pending = branches.survey(sys.argv[1], now=time.time() + 30 * 86400, reviews=True)
for b in pending:
    print(branches.describe(b, time.time()))
PY
has "$T/rvb2.out" "docs/d.md: unseen 0/3 (tip)" "…a branch no worktree holds: read from its tip, and says so"
unset MEMO_NOW

echo "the Open feedback marker is a heading, never a mention (2026-10-09)"
cat > "$T/fbm.md" <<'EOF'
# Marker design (2026-10-09)

**Defaults taken** (conventional answers; a line in Open feedback reopens any):

## Decisions

- **D1 — First.** Body.
  - A — one
  - B — two

  ➤ Recommended: A

  ➤ Answer:

- **D2 — Second.** Body.
  - A — one
  - B — two

  ➤ Recommended: B

  ➤ Answer:

## 12. Open feedback

Sam writes here.
EOF
"$B/keel" parse "$T/fbm.md" > "$T/parse.json"
check "$(py 'print(d["feedback_line"])')" "22" "a prose mention above the items is not the marker: the numbered heading is"
"$B/keel" build "$T/fbm.md" -o "$T/fbm.html" > /dev/null
check "$(grep -o '<section class="card" id="card-D[0-9]"' "$T/fbm.html" | wc -l | tr -d ' ')" "2" "…the form has one card per item"
check "$(grep -o '<button type="button" class="opt" data-letter="[AB]">' "$T/fbm.html" | wc -l | tr -d ' ')" "4" "…and every option row a button"
check "$("$B/keel" lint "$T/fbm.md" | grep -v 'no `Reversible: yes|no` line'; echo "rc=${PIPESTATUS[0]}")" "rc=0" "…lint is quiet"
# a prose mention inside an item's own body does not cut the item short either
sedi 's/^- \*\*D1 — First\.\*\* Body\./- **D1 — First.** Body, see Open feedback below./' "$T/fbm.md"
"$B/keel" parse "$T/fbm.md" > "$T/parse.json"
check "$(py 'print(d["items"][0]["body"].splitlines()[0], len(d["items"]), d["feedback_line"])')" "Body, see Open feedback below. 2 22" "a mention in an item's body stays body"

# Every item gets its card, wherever it sits; the feedback section is the first marker after the last
# item (feedback_section, 2026-10-10). A marker above an item is prose on the page.
cat > "$T/fbl.md" <<'EOF'
# Late item (2026-10-09)

- **D1 — Before.** Body.
  - A — one
  - B — two

  ➤ Recommended: A

  ➤ Answer:

## Open feedback

Sam's earlier note.

- **D2 — After the marker.** The form dropped this until 2026-10-10.
  - A — one
  - B — two

  ➤ Recommended: A

  ➤ Answer:
EOF
"$B/keel" parse "$T/fbl.md" > "$T/parse.json"
check "$(py 'print(len(d["items"]), d["feedback_line"])')" "2 None" "an item under a marker: both parsed, and that marker is not the feedback section"
"$B/keel" build "$T/fbl.md" -o "$T/fbl.html" > /dev/null
check "$(grep -o '<section class="card" id="card-D[0-9]"' "$T/fbl.html" | wc -l | tr -d ' ')" "2" "…the form has a card for each, the late one too"
has "$T/fbl.html" "Sam&#x27;s earlier note." "…and the old section's text is on the page, as prose"
check "$("$B/keel" lint "$T/fbl.md" | grep -c ': warning: D2 (line 15): sits under the feedback section (line 11)'; "$B/keel" lint "$T/fbl.md" >/dev/null; echo "rc=$?")" "1
rc=0" "lint: an unanswered item under the section is a warning naming both lines, not an error"
printf '{"items": {"D2": "B"}, "feedback": "late thought"}' > "$T/fbl.json"
"$B/keel" merge "$T/fbl.md" "$T/fbl.json" > "$T/fbl.out" 2>/dev/null
check "$(grep -c '^## Open feedback$' "$T/fbl.out") $(grep -n '^\*\*Sam, [0-9-]*:\*\* late thought$' "$T/fbl.out" | cut -d: -f1)" "2 26" "…a Save answers D2 and opens a new section at the end, under it"
check "$(sed -n 22p "$T/fbl.out")" "  B" "…D2's answer written into its own block"
# answered, the item is a reply thread's record: quiet
printf '  B\n' >> "$T/fbl.md"
"$B/keel" parse "$T/fbl.md" > "$T/parse.json"
check "$(py 'print(d["items"][1]["answer"])')" "B" "(fixture: D2 answered)"
check "$("$B/keel" lint "$T/fbl.md" | grep -v 'D1 (line 3): no `Reversible: yes|no` line'; echo "rc=${PIPESTATUS[0]}")" "rc=0" "…an answered item under the section: lint is quiet"
# a second section after the last item is the feedback section; a Save writes under it, no third
printf '\n## Open feedback\n\nNewer.\n' >> "$T/fbl.md"
"$B/keel" parse "$T/fbl.md" > "$T/parse.json"
check "$(py 'print(d["feedback_line"])')" "23" "the first marker after the last item is the section"
"$B/keel" merge "$T/fbl.md" "$T/fbl.json" > "$T/fbl.out" 2>/dev/null
check "$(grep -c '^## Open feedback$' "$T/fbl.out") $(grep -n '^\*\*Sam, [0-9-]*:\*\* late thought$' "$T/fbl.out" | cut -d: -f1)" "2 28" "…and a Save's feedback goes under it, after Newer."

# block_stop: a lead with text after it ends the last answer block (it became D1's answer, review 2026-10-09)
printf '# Lead\n\n- **D1 — One.** Body.\n  - A — x\n  - B — y\n\n  ➤ Recommended: A\n\n  ➤ Answer:\n\n**Open feedback.** Anything the decisions miss goes here.\n' > "$T/fbk.md"
"$B/keel" parse "$T/fbk.md" > "$T/parse.json"
check "$(py 'print(repr(d["items"][0]["answer"]), d["items"][0]["answered"], d["feedback_line"])')" "'' False 10" "a feedback lead with text ends the answer block: D1 stays open"
sedi '10d' "$T/fbk.md"
"$B/keel" parse "$T/fbk.md" > "$T/parse.json"
check "$(py 'print(repr(d["items"][0]["answer"]), d["feedback_line"])')" "'' 9" "…right under \`➤ Answer:\` with no blank line too"
printf '{"items": {"D1": "B"}, "feedback": ""}' > "$T/fbk.json"
"$B/keel" merge "$T/fbk.md" "$T/fbk.json" > "$T/fbk.out" 2>/dev/null
check "$(grep -c '^\*\*Open feedback\.\*\* Anything the decisions miss goes here\.$' "$T/fbk.out")" "1" "…and a Save keeps the feedback line"

# the old shape's answer continuation stops at the section too (it swallowed the line, review 2026-10-09)
printf '# Old\n\n**D1 — One?** Body.\n\n➤ Answer: yes\nOpen feedback: the line Sam wrote.\n' > "$T/fbo.md"
"$B/keel" parse "$T/fbo.md" > "$T/parse.json"
check "$(py 'print(d["items"][0]["answer"], d["feedback_line"])')" "yes 5" "old shape: a lead right under \`➤ Answer: yes\` is the section, not the answer"
printf '{"items": {"D1": "no"}, "feedback": ""}' > "$T/fbo.json"
"$B/keel" merge "$T/fbo.md" "$T/fbo.json" > "$T/fbo.out" 2>/dev/null
check "$(sed -n '5,6p' "$T/fbo.out" | tr '\n' '|')" "➤ Answer: no|Open feedback: the line Sam wrote.|" "…a Save rewrites the answer and keeps the feedback"

# Aurora's dreams, /embark and sextant: `## Feedback from Sam` is the section; merge writes under it
printf '# Dream\n\n- **D1 — One.** Body.\n  ➤ Answer: yes\n\n## 6. Feedback from Sam\n\n(empty)\n' > "$T/fbi.md"
"$B/keel" parse "$T/fbi.md" > "$T/parse.json"
check "$(py 'print(d["feedback_line"])')" "5" "## N. Feedback from Sam is the section"
printf '{"items": {}, "feedback": "noted"}' > "$T/fbi.json"
"$B/keel" merge "$T/fbi.md" "$T/fbi.json" > "$T/fbi.out" 2>/dev/null
check "$(grep -c 'Open feedback' "$T/fbi.out") $(grep -c '^\*\*Sam, .*:\*\* noted$' "$T/fbi.out")" "0 1" "…a Save writes under it, no second section"

# indentation and code: an indented lead is an item's body, a 4-space or fenced heading is code
printf '# Indent\n\n- **D1 — One.** Body.\n  Open feedback:\n  ➤ Answer: yes\n\n    ## Open feedback\n\n```\n## Open feedback\n```\n\nEnd.\n' > "$T/fbx.md"
"$B/keel" parse "$T/fbx.md" > "$T/parse.json"
check "$(py 'print(d["feedback_line"], d["items"][0]["answer"])')" "None yes" "an indented lead, a 4-space and a fenced heading are not the marker"

# the shapes that must keep working: heading (numbered, closed, qualified, bold), a bare line, bold or
# italic leads (with text after them too), a colon (with text too), the template phrase
i=0
for shape in '## Open feedback' '## 12. Open feedback' '## Open feedback ##' '## Open feedback (Sam)' '## **Open feedback**' \
    '## Feedback from Sam' '### 11. Feedback from Sam' 'Open feedback' '**Open feedback**' '**Open feedback:**' '**Open feedback.**' \
    '**Open feedback.** Anything the decisions miss goes here.' '_Open feedback_' 'Open feedback:' 'Open feedback: none yet.' \
    'Open feedback goes below this line.' '## Open feedback and notes'; do
  i=$((i+1))
  printf '# Shape\n\n- **D1 — One.** Body.\n  - A — x\n  - B — y\n\n  ➤ Recommended: A\n\n  ➤ Answer:\n\n%s\n\nNotes.\n' "$shape" > "$T/fbs$i.md"
  "$B/keel" parse "$T/fbs$i.md" > "$T/parse.json"
  check "$(py 'print(d["feedback_line"], repr(d["items"][0]["answer"]))')" "10 ''" "feedback shape detected: $shape"
done
# …and the things that look like it are not: a reply quote, a legend's mention, an item line, prose
# that opens with the words, a bare `## Feedback` (pipeline's 13-working-with-humans.md: a content section)
printf '# Not\n\n- **D1 — Open feedback form.** Body.\n  ➤ Answer: yes\n\n> **Done.** Moved per your Open feedback\n\n> Open feedback:\n\n`➤ Answer:` goes in the box; Open feedback at the bottom.\n\nOpen feedback is where Sam writes.\n\n## Feedback\n' > "$T/fbn.md"
"$B/keel" parse "$T/fbn.md" > "$T/parse.json"
check "$(py 'print(d["feedback_line"], len(d["items"]))')" "None 1" "a reply, a quoted lead, a legend, an item title, prose and a bare ## Feedback are not the marker"
# …but any line opening with the words still ends an answer block, marker or not (review, 2026-10-10:
# narrowing block_stop to the marker made these D1's answer — answered, so yolo and stand skipped it)
i=0
for shape in 'Open feedback (anything else):' 'Open feedback — anything the decisions miss.' 'Open feedback, if any:' \
    '  Open feedback:' 'Open feedback:none'; do
  i=$((i+1))
  printf '# Loose\n\n- **D1 — One.** Body.\n  - A — x\n  - B — y\n\n  ➤ Recommended: A\n\n  ➤ Answer:\n\n%s\n\nNotes.\n' "$shape" > "$T/fbz$i.md"
  "$B/keel" parse "$T/fbz$i.md" > "$T/parse.json"
  check "$(py 'print(repr(d["items"][0]["answer"]), d["items"][0]["answered"])')" "'' False" "a loose lead ends the answer block: $shape"
done

echo "the Keel: steps, goals, the derived Status line (entry S1, 2026-10-15)"
K="$T/keel"; mkdir -p "$K"
kp() { "$B/keel" parse "$1" > "$T/kp.json"; python3 -c "import json; d=json.load(open('$T/kp.json')); $2"; }
cat > "$K/one.md" <<'EOF'
# One — a single Course doc (design, 2026-10-15)

Written by `architect` (Fable 5.1, `high`) on 2026-10-15 for "a test".

Status: answered — 2 of 2 decisions answered · action plan: 0 of 3 steps done · handed over 2026-10-15 · first answer 2026-10-15

## Summary — what this proposes

Short.

## Goals — how we will know it worked

| Goal | Today | Target | How |
| --- | --- | --- | --- |
| G1 — docs never opened | 20 % | ≤ 10 % | `keel status`, weekly |
| G2 — median hours to first answer | 2.0 h | ≤ 2 h | the Status line's dates |

## The system — how the parts work together

### Fundamental decisions

- **D1 — The name.** Body.
  - A — Keel
  - B — none

  Reversible: no

  ➤ Recommended: A

  ➤ Answer:
  A

- **D2 — The words.** Body.
  - A — as listed
  - B — fewer

  Reversible: yes

  ➤ Recommended: A

  ➤ Answer:
  A

## Action plan — the steps, in order, with their status

- **S1 — the grammars in `bin/keel`** · session `sr-worker` · after: D1, D2 · gate: `bin/keel` · status: not started
- **S2 — the architects write the shape** · session `worker` · after: S1, D1 · status: not started
- **S3 — Sam opens it** · human (only Sam sees what he sees) · after: S2 · status: not started

## Not verified

- Nothing.
EOF
check "$(kp "$K/one.md" 'print([(x["id"], x["kind"], x["after"], x["status"]) for x in d["steps"]])')" "[('S1', 'session', ['D1', 'D2'], 'not started'), ('S2', 'session', ['S1', 'D1'], 'not started'), ('S3', 'human', ['S2'], 'not started')]" "keel: the S-lines, their kind, after: and status"
check "$(kp "$K/one.md" 'print([(g["id"], g["metric"], g["target"], g["measured"]) for g in d["goals"]])')" "[('G1', 'docs never opened', '≤ 10 %', None), ('G2', 'median hours to first answer', '≤ 2 h', None)]" "keel: the G-rows"
check "$(kp "$K/one.md" 'k=d["keel"]; print(k["word"], k["decisions"], k["plan"], k["line"] == k["derived"])')" "answered [2, 2] [0, 3] True" "keel: every D answered, no step started — answered, and the line agrees"
check "$("$B/keel" lint "$K/one.md"; echo "rc=$?")" "$K/one.md: no findings
rc=0" "keel: a doc whose Status line agrees lints clean"
# building: one step done (D6's form, date and branch after the word)
sedi 's/^\(- \*\*S1 — .*status: \)not started$/\1done 2026-10-15 claude\/laptop\/2026-10-15-x/' "$K/one.md"
check "$(kp "$K/one.md" 'k=d["keel"]; print(k["word"], k["plan"], d["steps"][0]["status"])')" "building [1, 3] done" "keel: a step done — building, 1 of 3"
check "$("$B/keel" lint "$K/one.md" | grep -c 'says answered, derives building')" "1" "keel: lint fails a Status line that disagrees"
"$B/keel" lint "$K/one.md" > /dev/null; check "rc=$?" "rc=1" "…with exit 1"
"$B/keel" status --stamp "$K/one.md" > "$T/ks.out" 2>&1
has "$T/ks.out" "stamped one.md: Status: building — 2 of 2 decisions answered · action plan: 1 of 3 steps done · handed over 2026-10-15 · first answer 2026-10-15" "keel: --stamp rewrites the line, dates kept"
check "$(sed -n 5p "$K/one.md")" "Status: building — 2 of 2 decisions answered · action plan: 1 of 3 steps done · handed over 2026-10-15 · first answer 2026-10-15" "…in the file, at its own line"
"$B/keel" status --stamp "$K/one.md" > "$T/ks.out" 2>&1
has "$T/ks.out" "unchanged one.md:" "…and a second stamp changes nothing"
check "$("$B/keel" lint "$K/one.md"; echo "rc=$?")" "$K/one.md: no findings
rc=0" "…after which lint is clean"
# part done is a started step (the keel build's S8, 2026-10-15)
sedi 's/^\(- \*\*S2 — .*status: \)not started$/\1part done 2026-10-15 (memo line <entry>); rules part in batch 3/' "$K/one.md"
check "$(kp "$K/one.md" 'print(d["steps"][1]["status"], d["keel"]["word"], d["keel"]["plan"])')" "wip building [1, 3]" "keel: \`part done\` reads as wip — started, not done"
# built, then measured
sedi 's/status: part done.*$/status: done 2026-10-15/; s/^\(- \*\*S3 — .*status: \)not started$/\1superseded 2026-10-16 — by S9/' "$K/one.md"
check "$(kp "$K/one.md" 'print(d["keel"]["word"], d["keel"]["plan"])')" "built [3, 3]" "keel: every step done or superseded — built"
printf '\n> **Measured, 2026-10-20:** G1 = 9 %% (target ≤ 10 %%) — keel status\n' > "$T/m1"
sed -i.bak "/^| G2 — /r $T/m1" "$K/one.md" && rm -f "$K/one.md.bak"
check "$(kp "$K/one.md" 'print(d["keel"]["word"], [g["measured"] for g in d["goals"]])')" "built ['2026-10-20', None]" "keel: one goal measured of two — still built"
printf '> **Measured, 2026-10-21:** G2 = 1.5 h (target ≤ 2 h) — the dates\n' > "$T/m2"
sed -i.bak "/^> \*\*Measured, 2026-10-20/r $T/m2" "$K/one.md" && rm -f "$K/one.md.bak"
check "$(kp "$K/one.md" 'print(d["keel"]["word"])')" "measured" "keel: every goal measured, every step done — measured"
# blocked: a step its session marked so
sedi 's/^\(- \*\*S3 — .*status: \)superseded.*$/\1blocked — the NAS does not play over HTTP/' "$K/one.md"
check "$(kp "$K/one.md" 'print(d["keel"]["word"])')" "blocked" "keel: a blocked step — blocked, before measured"
# superseded is the line's own word (Aurora writes it): kept
sedi 's/^Status: [a-z]* —/Status: superseded —/' "$K/one.md"
check "$(kp "$K/one.md" 'print(d["keel"]["word"])')" "superseded" "keel: a superseded doc stays superseded"
# a dangling after:
sedi 's/^\(- \*\*S2 — .*after: \)S1, D1/\1S7, D1, D9, G4/' "$K/one.md"
"$B/keel" lint "$K/one.md" > "$T/kl.out"
has "$T/kl.out" "S2: after: names S7, which the doc does not define" "keel: lint fails an after: naming a missing step"
has "$T/kl.out" "S2: after: names D9, which the doc does not define" "…a missing decision"
has "$T/kl.out" "S2: after: names G4, which the doc does not define" "…a missing goal"

echo "the Keel: Reopened, and the doc it reopens"
cat > "$K/reo.md" <<'EOF'
# Reopen (design, 2026-10-15)

Status: answered — 1 of 1 decision answered · action plan: 0 of 1 step done · handed over 2026-10-15

- **D1 — Pick.** Body.
  - A — one
  - B — two

  Reversible: yes

  ➤ Recommended: A

  ➤ Answer:
  B

  > **Reopened.** B needs the NAS on HTTP, which it is not; asking again.

## Action plan — the steps

- **S1 — build it** · session `worker` · after: D1 · status: not started
EOF
check "$(kp "$K/reo.md" 'print(d["items"][0]["answered"], d["items"][0]["reopened"], d["keel"]["word"], d["keel"]["decisions"])')" "False True blocked [0, 1]" "keel: a Reopened reply opens the item again; the step waiting on it blocks the doc"
printf '\n  > **Applied.** B, once the share moved to HTTP.\n' >> "$T/ap"
sed -i.bak "/^  > \*\*Reopened\./r $T/ap" "$K/reo.md" && rm -f "$K/reo.md.bak"
check "$(kp "$K/reo.md" 'print(d["items"][0]["answered"], d["items"][0]["reopened"], d["keel"]["word"])')" "True False answered" "keel: a later bold reply closes it again — the last one decides"
# an old doc carries no Keel: no word judged, no caps
check "$(kp "$T/memo.md" 'print(d["keel"]["derived"], d["steps"], d["goals"])')" "None [] []" "keel: an old doc has no derived line and no steps"

echo "the Keel: a nested set — entry, components, cross-file ids (shape D4-A)"
R="$T/kroot/proj/docs"; mkdir -p "$R" "$T/kroot/proj/.git"
cat > "$R/topic-2026-10-15.md" <<EOF
# Topic — entry (entry doc, 2026-10-15)

Status: answered — 1 of 1 decision answered · action plan: 0 of 3 steps done · handed over 2026-10-15

Components: [alpha]($R/topic-alpha-2026-10-15.md) · [beta](/elsewhere/docs/topic-beta-2026-10-15.md) · baselines in the [record]($R/topic-research-2026-10-15.md).

- **D1 — Whole.** Body.
  - A — yes
  - B — no

  Reversible: yes

  ➤ Recommended: A

  ➤ Answer:
  A

## Action plan — the steps

- **S1 — alpha's part** · session \`worker\` · after: D1, alpha D1 · status: done 2026-10-15 claude/x
- **S2 — beta's part** · session \`worker\` · after: S1, beta D2 · status: not started
- **S3 — both** · human (Sam) · after: S1, S2, alpha D9 · status: not started
EOF
cat > "$R/topic-alpha-2026-10-15.md" <<'EOF'
# Topic — alpha (component doc, 2026-10-15)

Status: answered — 1 of 1 decision answered · built by entry S1, S3 (0 of 2 done) · handed over 2026-10-15

- **D1 — Alpha.** As entry D1 says; beta D3 is beta's.
  - A — yes
  - B — no

  Reversible: yes

  ➤ Recommended: A

  ➤ Answer:
  A
EOF
cat > "$R/topic-beta-2026-10-15.md" <<'EOF'
# Topic — beta (component doc, 2026-10-15)

Status: proposed — 0 of 2 decisions answered · built by entry S2 (0 of 1 done) · handed over 2026-10-15

- **D1 — Beta one.** Body.
  - A — yes
  - B — no

  Reversible: yes

  ➤ Recommended: A

  ➤ Answer:

- **D2 — Beta two.** Body.
  - A — yes
  - B — no

  Reversible: no

  ➤ Recommended: B

  ➤ Answer:
EOF
printf '# Topic — the research record (2026-10-15)\n\n- **D1 — quoted, not asked.** ➤ Answer: x\n' > "$R/topic-research-2026-10-15.md"
ks() { python3 -c 'import sys; from importlib.machinery import SourceFileLoader as L; m = L("m", sys.argv[1]).load_module(); s = m.set_of(sys.argv[2]); print(s and (s["entry"].name, sorted(s["slugs"])))' "$B/keel" "$1"; }
check "$(ks "$R/topic-alpha-2026-10-15.md")" "('topic-2026-10-15.md', ['alpha', 'beta', 'entry'])" "set: a component finds its entry and siblings (a link to another worktree's copy counts by name)"
check "$(ks "$R/topic-2026-10-15.md")" "('topic-2026-10-15.md', ['alpha', 'beta', 'entry'])" "set: the entry finds its components; the linked record with no Status line is none"
check "$(ks "$K/one.md")" "None" "set: a single doc is in none"
check "$(kp "$R/topic-alpha-2026-10-15.md" 'k=d["keel"]; print(k["word"], k["plan"], k["built_by"])')" "building [1, 2] ['S1', 'S3']" "set: a component's steps are the entry's it names — S1 done, so building"
check "$(kp "$R/topic-beta-2026-10-15.md" 'k=d["keel"]; print(k["word"], k["decisions"], k["plan"])')" "proposed [0, 2] [0, 1]" "set: beta's own D open — proposed"
"$B/keel" lint --set "$R/topic-2026-10-15.md" > "$T/kset.out"; rc=$?
check "rc=$rc" "rc=1" "lint --set: exit 1 on a finding"
has "$T/kset.out" "S3: after: names alpha D9, which the set does not hold" "lint --set: an after: naming another file's missing D"
lacks "$T/kset.out" "alpha D1, which" "…a present one passes"
lacks "$T/kset.out" "beta D2, which" "…in any component"
has "$T/kset.out" "topic-alpha-2026-10-15.md: line 5: beta D3 — topic-beta-2026-10-15.md has no D3" "lint --set: a prose reference to a missing item, across files"
lacks "$T/kset.out" "entry D1 —" "…entry D1 resolves to the entry"
has "$T/kset.out" "topic-alpha-2026-10-15.md: the Status line (line 3) says answered, derives building" "lint --set: each component's line is checked against the entry's steps"
lacks "$T/kset.out" "topic-research" "lint --set: the record is not linted as part of the set"
"$B/keel" status --stamp "$R/topic-2026-10-15.md" > "$T/kst.out" 2>&1
has "$T/kst.out" "stamped topic-2026-10-15.md: Status: building — 1 of 1 decision answered · action plan: 1 of 3 steps done · handed over 2026-10-15" "status --stamp on an entry: the entry's line"
has "$T/kst.out" "stamped topic-alpha-2026-10-15.md: Status: building — 1 of 1 decision answered · built by entry S1, S3 (1 of 2 done) · handed over 2026-10-15" "…and each component's"
has "$T/kst.out" "unchanged topic-beta-2026-10-15.md:" "…an agreeing one untouched"
"$B/keel" open --root "$T/kroot" --json > "$T/kopen.json"
check "$(python3 -c "import json,os; print([(os.path.basename(r['path']), bool(r.get('set'))) for r in json.load(open('$T/kopen.json')) if 'topic' in r['path']])")" "[('topic-beta-2026-10-15.md', True)]" "open: a component with open items is a row of its own, marked as in a set"
touch "$R/topic-beta-2026-10-15.md"; sleep 1; touch "$R/topic-alpha-2026-10-15.md"
"$B/keel" list --root "$T/kroot" --limit 0 --json > "$T/klist.json"
check "$(python3 -c "import json,os; print([os.path.basename(r['path']) for r in json.load(open('$T/klist.json'))])")" "['topic-2026-10-15.md', 'topic-alpha-2026-10-15.md', 'topic-beta-2026-10-15.md', 'topic-research-2026-10-15.md']" "list: the set together, the entry first, though a component is newer"
"$B/keel" list --root "$T/kroot" --limit 0 > "$T/klist.txt"
has "$T/klist.txt" "↳ Topic — alpha" "list: a component row is marked"
check "$(python3 -c "import json,os; print([(os.path.basename(r['path']), r.get('keel')) for r in json.load(open('$T/klist.json')) if r.get('keel')][:2])")" "[('topic-2026-10-15.md', {'word': 'building', 'steps': [1, 3]}), ('topic-alpha-2026-10-15.md', {'word': 'building', 'steps': [1, 2]})]" "list --json: a doc that carries the Keel gets its word and k of j steps, a component its entry's (entry S5)"
check "$(python3 -c "import json; print([r['path'].rsplit('/',1)[1] for r in json.load(open('$T/klist.json')) if not r.get('keel')])")" "['topic-research-2026-10-15.md']" "…and a doc without one gets none"
check "$(python3 - "$(dirname "$( (peer helm_render.py; peer plan_render.py) | grep -m1 .)")" "$T/klist.json" <<'PYX'
import json, sys
sys.path.insert(0, sys.argv[1])  # helm's board renderer, through the core's tool()
try:
    import helm_render as pr
except ImportError:  # a peer from before rename S5 (helm-vocabulary H1)
    import plan_render as pr
rows = json.load(open(sys.argv[2]))
folded = pr.memo_rows(rows)
print([(r["path"].rsplit("/", 1)[1], r.get("open"), r.get("files")) for r in folded if "topic" in r["path"]], pr.keel_text(folded[0].get("keel"), folded[0].get("files")))
PYX
)" "[('topic-2026-10-15.md', 2, 4)] building · 1 of 3 steps · 4 files" "the board: a set is one memo card — the entry's, with the set's open items, its Keel word and k of j steps (entry S5)"
CLAUDE_UNATTENDED=1 "$B/keel" line "$R/topic-2026-10-15.md" > "$T/kline.out" 2> "$T/kline.err"; rc=$?
check "$(cut -c1-200 "$T/kline.out" | sed 's/(.*$//')" "[topic-2026-10-15.md]
[topic-alpha-2026-10-15.md]
[topic-beta-2026-10-15.md]" "line <entry>: one line per file of the set, the entry first (entry S8)"
check "rc=$rc" "rc=0" "…exit 0 when no file owes a missing part"
CLAUDE_UNATTENDED=1 "$B/keel" line "$R/topic-beta-2026-10-15.md" > "$T/kline1.out" 2>/dev/null
check "$(wc -l < "$T/kline1.out" | tr -d ' ')" "1" "line <component>: that file's line alone"

echo "the Keel: the caps warn, never fail (shape D1-A)"
python3 - "$K/one.md" "$K/long.md" <<'PY'
import sys
t = open(sys.argv[1]).read().replace("Short.", " ".join(["word"] * 720))
t = t.replace("Status: superseded", "Status: blocked")
open(sys.argv[2], "w").write(t)
PY
"$B/keel" lint "$K/long.md" > "$T/kcap.out"
has "$T/kcap.out" "warning: Summary + Goals + System: " "caps: a long top warns"
has "$T/kcap.out" "over 700 (shape D1-A)" "…naming the cap"

echo "a dated doc's title names its kind — research, proposal, design (Sam, 2026-10-16)"
# kk <file> <title>: lints a one-line architect doc; prints `rc=<rc> <the output, path cut>` —
# exact, so a crash (a traceback, rc 1) or a path that happens to hold "kind" never passes a case
kk() { printf '# %s\n\nWritten by `architect` (Fable 5.1, `high`) on 2026-10-17 for "x".\n\nShort.\n' "$2" > "$K/$1"
       "$B/keel" lint "$K/$1" > "$T/kkind.out" 2>&1; echo "rc=$? $(sed "s|$K/$1||" "$T/kkind.out")"; }
check "$(kk kd-2026-10-17.md 'X — y (design, 2026-10-17)')" "rc=0 : no findings" "kind: a known kind warns nothing"
check "$(kk kn-2026-10-17.md 'X — y (design, 2026-10-02; fourth pass 2026-10-04)')" "rc=0 : no findings" "kind: a note after the date is no second kind"
check "$(kk kb-2026-10-17.md 'X — y (**proposal**, 2026-10-17)')" "rc=0 : no findings" "kind: markdown around the kind is stripped"
check "$(kk ku-2026-10-17.md 'X — y (_research_, 2026-10-17)')" "rc=0 : no findings" "…underscores too"
check "$(kk ke-2026-10-17.md 'X — y (entry doc, 2026-10-17)')" "rc=0 : no findings" "kind: a set's part passes"
check "$(kk kv-2026-10-17.md 'X — y (evidence, 2026-10-17)')" "rc=0 : no findings" "…its evidence file too (review 2026-10-17)"
out=$(kk ko-2026-10-17.md 'X — y (musing, 2026-10-17)'); check "${out%% *}" "rc=0" "kind: an unknown one is a warning, never an error"
has "$T/kkind.out" "warning: the title's kind \`musing\` is none of research, proposal, design" "…and names the kinds"
kk kp-2026-10-17.md 'X — y (designer notes, 2026-10-17)' > /dev/null
has "$T/kkind.out" "warning: the title's kind \`designer notes\`" "kind: an exact word, never a prefix"
kk kz-2026-10-17.md 'X — y' > /dev/null
has "$T/kkind.out" "warning: the title does not end" "kind: none warns"
check "$(kk old-2026-10-16.md 'X — y')" "rc=0 : no findings" "kind: a doc dated before the rule landed is never judged by it"
check "$(kk undated.md 'X — y')" "rc=0 : no findings" "kind: an undated doc (a chart) is never judged"
printf '# X — y\n\nShort.\n' > "$K/digest-2026-10-17.md"; "$B/keel" lint "$K/digest-2026-10-17.md" > "$T/kkind.out" 2>&1
check "$(sed "s|$K/||" "$T/kkind.out")" "digest-2026-10-17.md: no findings" "kind: a doc no architect wrote (a digest) is never judged"

echo "Mermaid in the form and the page: pinned, fetched once, inlined only where a diagram is (entry S13)"
cat > "$K/dia.md" <<'EOF'
# Diagram (design, 2026-10-15)

```mermaid
flowchart TD
  A[architect] -->|writes| C[doc<br/>in git]
  C --> F & G
```

```js
var notADiagram = 1;
```

- **D1 — Draw it?** Body.
  - A — yes
  - B — no

  Reversible: yes

  ➤ Recommended: A

  ➤ Answer:
EOF
"$B/keel" build "$K/dia.md" -o "$T/dia.html" > /dev/null 2> "$T/dia.err"
has "$T/dia.html" '<pre class="mermaid" data-at="' "mermaid: the fence is a diagram block, still noteable"
has "$T/dia.html" 'A[architect] --&gt;|writes| C[doc&lt;br/&gt;in git]' "…its source escaped, never raw HTML"
# Not vendored (the shareable scrub, 2026-10-23): with no cached copy and no fetch, the page shows
# the source and the build says so once.
lacks "$T/dia.html" 'mermaid.run({querySelector:"pre.mermaid"})' "…no cached build, no fetch: no script"
has "$T/dia.err" "diagrams show as source" "…and the build says the diagrams show as source"
has "$T/dia.html" '<pre data-at="' "mermaid: another fence stays code"
"$B/keel" build "$K/one.md" -o "$T/nodia.html" > /dev/null
lacks "$T/nodia.html" 'mermaid.run(' "mermaid: a page with no diagram carries no script"
check "$([ "$(wc -c < "$T/nodia.html")" -lt 200000 ] && echo small)" "small" "…and stays small"
check "$(python3 -c 'import sys; from importlib.machinery import SourceFileLoader as L; m = L("m", sys.argv[1]).load_module(); print(" ".join(u.split("/")[2] for u in m.MERMAID_URLS if u.endswith("/mermaid@%s/dist/mermaid.min.js" % m.MERMAID_VERSION)))' "$B/keel")" "cdn.jsdelivr.net unpkg.com" "mermaid: both sources are the pinned version's dist file"
has "$B/../vendor/mermaid/README.md" "$(sed -n 's/^MERMAID_SHA256 = "\([0-9a-f]*\)".*/\1/p' "$B/keel")" "…and its README names the same hash"
has "$B/../vendor/mermaid/README.md" "$(sed -n 's/^MERMAID_VERSION = "\([0-9.]*\)".*/\1/p' "$B/keel")" "…and the same version"
check "$(git -C "$B/.." ls-files vendor/mermaid | grep -c 'mermaid.min.js')" "0" "mermaid: no bundle is tracked"
# The fetch, against a stand-in whose hash the case pins: a match is cached and inlined; a mismatch
# is neither; a cached file that is not the pin is fetched again.
printf 'var mermaid = {run: function () {}};\n' > "$T/fake-mermaid.js"
cat > "$T/mfetch.py" <<'PY'
import hashlib, os, sys
from pathlib import Path
from importlib.machinery import SourceFileLoader as L
m = L("m", sys.argv[1]).load_module()
fake = Path(sys.argv[2]).read_bytes()
if sys.argv[4] == "pin-fake":
    m.MERMAID_SHA256 = hashlib.sha256(fake).hexdigest()
m.MERMAID_JS = Path(sys.argv[5])
page = m.build(Path(sys.argv[3]).read_text(), "dia.md")
cached = m.MERMAID_JS.read_bytes() if m.MERMAID_JS.exists() else b""
print("inlined" if b"var mermaid = {run" in page.encode() else "not inlined", '<pre class="mermaid"' in page,
      "cached" if cached == fake else "not cached")
Path(sys.argv[6]).write_text(page)
PY
MC="$T/mcache/mermaid.min.js"
KEEL_MERMAID_FETCH= KEEL_MERMAID_URL="file://$T/fake-mermaid.js" python3 "$T/mfetch.py" "$B/keel" "$T/fake-mermaid.js" "$K/dia.md" pin-fake "$MC" "$T/diaf.html" > "$T/diaf.out" 2> "$T/diaf.err"
check "$(cat "$T/diaf.out")" "inlined True cached" "mermaid: a fetch that matches the pin is cached and inlined"
check "$(wc -c < "$T/diaf.err" | tr -d ' ')" "0" "…quietly"
has "$T/diaf.html" 'mermaid.run({querySelector:"pre.mermaid"})' "…and run on the diagram blocks"
check "$(grep -o '</script' "$T/diaf.html" | wc -l | tr -d ' ')" "$(grep -o '<script' "$T/diaf.html" | wc -l | tr -d ' ')" "mermaid: every script tag closes once — the inlined text holds no </script"
KEEL_MERMAID_FETCH=0 python3 "$T/mfetch.py" "$B/keel" "$T/fake-mermaid.js" "$K/dia.md" pin-fake "$MC" "$T/diaf.html" > "$T/diaf.out" 2> "$T/diaf.err"
check "$(cat "$T/diaf.out")" "inlined True cached" "mermaid: once cached, no fetch is needed"
# With the pinned build cached, a page with no diagram still carries none (the case above, with no
# cache, could not fail; the landing review, 2026-10-23).
KEEL_MERMAID_FETCH=0 python3 "$T/mfetch.py" "$B/keel" "$T/fake-mermaid.js" "$K/one.md" pin-fake "$MC" "$T/nodiac.html" > "$T/nodiac.out" 2>&1
check "$(cat "$T/nodiac.out")" "not inlined False cached" "mermaid: a cached build is never inlined into a page with no diagram"
check "$([ "$(wc -c < "$T/nodiac.html")" -lt 200000 ] && echo small)" "small" "…and that page stays small"
rm -rf "$T/mcache"
KEEL_MERMAID_FETCH= KEEL_MERMAID_URL="file://$T/fake-mermaid.js" python3 "$T/mfetch.py" "$B/keel" "$T/fake-mermaid.js" "$K/dia.md" real-pin "$MC" "$T/diaf.html" > "$T/diab.out" 2> "$T/diab.err"
check "$(cat "$T/diab.out")" "not inlined True not cached" "mermaid: a fetched file that is not the pinned build is neither inlined nor kept; the source still shows"
has "$T/diab.err" "not fetched" "…and the build says why"
mkdir -p "$T/mcache"; cp "$T/fake-mermaid.js" "$MC"
KEEL_MERMAID_FETCH=0 python3 "$T/mfetch.py" "$B/keel" "$T/fake-mermaid.js" "$K/dia.md" real-pin "$MC" "$T/diaf.html" > "$T/diab.out" 2> "$T/diab.err"
check "$(cat "$T/diab.out")" "not inlined True cached" "mermaid: a cached file that is not the pin is never inlined"
has "$T/diab.err" "is not the pinned build" "…and the build says why"
lacks "$T/diab.err" "not fetched" "…and tries no fetch under KEEL_MERMAID_FETCH=0"
# other bytes in the cache and no marker, so the case can only pass by fetching (the B-gate review, 2026-10-24)
printf 'stale\n' > "$MC"; rm -f "$MC.failed"
KEEL_MERMAID_FETCH= KEEL_MERMAID_URL="file://$T/fake-mermaid.js" python3 "$T/mfetch.py" "$B/keel" "$T/fake-mermaid.js" "$K/dia.md" pin-fake "$MC" "$T/diaf.html" > "$T/diar.out" 2> /dev/null
check "$(cat "$T/diar.out")" "inlined True cached" "mermaid: a cached file that is not the pin is fetched again and replaced"
check "$(cmp -s "$MC" "$T/fake-mermaid.js" && echo same)" "same" "…the cache now holds the pin"
check "$([ -e "$MC.failed" ] && echo marker || echo none)" "none" "…and a good fetch leaves no hold-off marker"
rm -rf "$T/mcache"
# A failed fetch holds every process off for MERMAID_RETRY: the hooks that build pages have short
# deadlines, and a hung network must not cost each of them the timeout.
KEEL_MERMAID_FETCH= KEEL_MERMAID_URL="file://$T/no-such-mermaid.js" python3 "$T/mfetch.py" "$B/keel" "$T/fake-mermaid.js" "$K/dia.md" pin-fake "$MC" "$T/diaf.html" > /dev/null 2>&1
KEEL_MERMAID_FETCH= KEEL_MERMAID_URL="file://$T/fake-mermaid.js" python3 "$T/mfetch.py" "$B/keel" "$T/fake-mermaid.js" "$K/dia.md" pin-fake "$MC" "$T/diaf.html" > "$T/diah.out" 2> "$T/diah.err"
check "$(cat "$T/diah.out")" "not inlined True not cached" "mermaid: after a failed fetch, the next process does not fetch"
has "$T/diah.err" "a fetch failed under 10 min ago" "…and says so"
rm -rf "$T/mcache"
# A cache that cannot be written still draws the page from the verified bytes.
: > "$T/mblock"
KEEL_MERMAID_FETCH= KEEL_MERMAID_URL="file://$T/fake-mermaid.js" python3 "$T/mfetch.py" "$B/keel" "$T/fake-mermaid.js" "$K/dia.md" pin-fake "$T/mblock/mermaid.min.js" "$T/diaf.html" > "$T/diaw.out" 2> "$T/diaw.err"
check "$(cat "$T/diaw.out")" "inlined True not cached" "mermaid: an unwritable cache still inlines the fetched pin"
has "$T/diaw.err" "not cached" "…and says the cache was not written"
rm -f "$T/mblock"
mkdir -p "$T/mcache"; cp "$T/fake-mermaid.js" "$MC"
KEEL_MERMAID_FETCH=0 python3 - "$B/keel" "$K/dia.md" "$T/fake-mermaid.js" "$MC" > "$T/dias.out" <<'PY'
import hashlib, sys
from pathlib import Path
from importlib.machinery import SourceFileLoader as L
m = L("m", sys.argv[1]).load_module()
m.MERMAID_SHA256 = hashlib.sha256(Path(sys.argv[3]).read_bytes()).hexdigest()
m.MERMAID_JS = Path(sys.argv[4])
page, _ = m.sheep_page(Path(sys.argv[2]).read_text(), "dia.md", {"rel": "docs/dia.md", "sha": "abcdef0", "branch": "claude/x"})
print('<pre class="mermaid"' in page, "var mermaid = {run" in page)
PY
check "$(cat "$T/dias.out")" "True True" "mermaid: the spacesheep page keeps the diagram block and inlines the cached build"
rm -rf "$T/mcache"

echo "the form's footer: ↑ and ↓ between decisions, k/n answered (entry S14)"
has "$T/dia.html" 'id="prev" title="Previous decision or note">↑<span class="sr"> Previous decision or note</span>' "footer: a ↑ button"
has "$T/dia.html" 'id="next" title="Next decision or note">↓<span class="sr"> Next decision or note</span>' "footer: a ↓ button"
has "$T/dia.html" '<span class="count" id="count" role="status">0/1<span class="cw"> answered</span></span>' "footer: the count as the doc stands"
"$B/keel" build "$K/reo.md" -o "$T/reo.html" > /dev/null
has "$T/reo.html" '>1/1<span class="cw"> answered</span></span>' "…an answered box counts"
has "$T/dia.html" '<button type="button" class="state" id="state" data-tone="idle">' "footer: the state is a word on a button (2026-10-20)…"
has "$T/dia.html" '<span class="pop" id="status" role="status">Nothing saved yet.</span>' "…with the whole sentence in its pop-up"
lacks "$T/dia.html" '<div data-ss-id="keel-receipt"' "…and no receipt block off spacesheep"
python3 - "$B/keel" "$K/dia.md" > "$T/rcp.out" <<'PY'
import sys
from pathlib import Path
from importlib.machinery import SourceFileLoader as L
m = L("m", sys.argv[1]).load_module()
r = {"at": "2026-10-20T11:42:00+02:00", "saves": ["2026-10-20T09:40:00Z"], "what": "D1, \"1 note\" <b>", "refused": []}
page, _ = m.sheep_page(Path(sys.argv[2]).read_text(), "dia.md", {"rel": "docs/dia.md", "sha": "abcdef0", "branch": "claude/x", "receipt": r})
blank, _ = m.sheep_page(Path(sys.argv[2]).read_text(), "dia.md", {"rel": "docs/dia.md", "sha": "abcdef0", "branch": "claude/x"})
i = page.index('data-ss-id="keel-receipt"')
print(i < page.index("window.MEMO"), '\\&quot;1 note\\&quot; &lt;b&gt;' in page[i:i + 400], '<div data-ss-id="keel-receipt" hidden data-receipt="{}"></div>' in blank,
      "--fire-1" in page, "--fire-1" in m.build(Path(sys.argv[2]).read_text(), "dia.md"))
PY
check "$(cat "$T/rcp.out")" "True True True True False" "the spacesheep page: its receipt block before the script, escaped; empty without one; the skin on spacesheep only"
printf '# No items\n\nJust prose.\n' > "$K/noitems.md"
"$B/keel" build "$K/noitems.md" -o "$T/noitems.html" > /dev/null
lacks "$T/noitems.html" 'id="prev"' "footer: no decisions, no arrows"
# The behaviour, in a real browser when this Mac has one (CI's ubuntu has none: skipped there)
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
if [ -x "$CHROME" ]; then
  python3 - "$B/keel" "$K/one.md" "$T/navp.html" <<'PY'
import sys
from pathlib import Path
from importlib.machinery import SourceFileLoader as L
m = L("m", sys.argv[1]).load_module()
probe = """<script>var log=[];
Element.prototype.scrollIntoView=function(){log.push(this.id); window.scrollTo(0, this.getBoundingClientRect().top+scrollY-12);};
window.addEventListener('load',function(){
  var $=function(i){return document.getElementById(i);};
  log.push($('count').textContent);
  var sp=document.createElement('div'); sp.style.height='3000px'; document.querySelector('main').appendChild(sp);
  for(var i=0;i<4;i++) $('next').click();
  log.push($('status').textContent);
  $('prev').click();
  var ta=$('ans-D1'); ta.value=''; ta.dispatchEvent(new Event('input')); log.push($('count').textContent);
  $('stwrap').classList.add('open'); var c=$('count').getBoundingClientRect(), q=$('status').getBoundingClientRect();
  log.push(c.width>20&&q.left>=0&&q.right<=innerWidth?'fits':'overflows');
  log.push($('stwrap').getBoundingClientRect().left-c.right>=10?'clear':'cramped');
  var p=document.createElement('pre'); p.id='probe'; p.textContent=log.join(' | '); document.body.appendChild(p);});
</script>"""
Path(sys.argv[3]).write_text(m.PAGE_HEAD + probe + m.build(Path(sys.argv[2]).read_text(), "one.md") + "</body></html>")
PY
  # Bounded: headless Chrome in an unattended buildbox session never returned and hung the suite
  # for 20 minutes (2026-10-19, B4); a run that has to be killed is a skip, said, not a failure.
  perl -e 'alarm shift; exec @ARGV' 90 "$CHROME" --headless=new --disable-gpu --no-first-run --user-data-dir="$T/chrome" --virtual-time-budget=4000 \
    --window-size=500,700 --dump-dom "file://$T/navp.html" 2>/dev/null > "$T/navp.dom"; crc=$?
  sed -n 's/.*<pre id="probe">\([^<]*\)<.*/\1/p' "$T/navp.dom" > "$T/navp.out"
  if [ "$crc" = 142 ]; then echo "  skip footer in Chrome: Chrome did not finish in 90 s (no window server for this session?)"
  else check "$(cat "$T/navp.out")" "2/2 answered | card-D1 | card-D2 | card-feedback | No decision, note or feedback further down. | card-D2 | 1/2 answered | fits | clear" "footer in Chrome: ↓ walks the cards to the feedback and stops there, ↑ goes back, the count follows the boxes, keeps its width beside the state, the open pop-up stays on the page, and the state pill clears the count by 10 px or more"; fi
  # The spacesheep page as the viewer frames it (2026-10-20): its runtime pads <html> under the floating
  # header (scroll-padding-top), where ↓ used to re-pick the card it had just put in place. A note with
  # words is a stop and counts; the receipt says Taken on load and when a pull pushes a new one; a Save
  # this browser sent after the newest receipt says Sent. Presses a second apart: no smooth scroll in flight.
  python3 - "$B/keel" "$K/one.md" "$T/navq.html" "$T/navr.html" <<'PY'
import json, sys
from pathlib import Path
from importlib.machinery import SourceFileLoader as L
m = L("m", sys.argv[1]).load_module()
text = Path(sys.argv[2]).read_text()
r = {"at": "2026-10-20T09:42:00Z", "saves": ["2026-10-20T09:40:00Z"], "what": "D1", "refused": []}
page, _ = m.sheep_page(text, "one.md", {"rel": "docs/one.md", "sha": "abcdef0", "branch": "claude/x", "receipt": r})
slug = m.slugify(m.title_of(text, "one"))
inset = "<style>html{padding-top:56px!important;scroll-padding-top:56px}</style>"
probe = """<script>var log=[]; try{localStorage.clear()}catch(e){}
var orig=Element.prototype.scrollIntoView;
Element.prototype.scrollIntoView=function(){log.push(this.id||this.className); orig.call(this,{block:'start',behavior:'auto'});};
window.addEventListener('load',function(){ setTimeout(function(){
  var $=function(i){return document.getElementById(i);};
  log.push($('state-word').textContent);
  var p=document.querySelector('main p[data-at]'); p.click(); var t=document.querySelector('.note textarea'); t.value='a note'; t.dispatchEvent(new Event('input'));
  log.push($('count').textContent);
  var fb=$('feedback'); fb.value='more'; fb.dispatchEvent(new Event('input')); log.push($('count').textContent+' / '+$('count').title);
  fb.value=''; fb.dispatchEvent(new Event('input'));
  var sp=document.createElement('div'); sp.style.height='3000px'; document.querySelector('main').appendChild(sp); window.scrollTo(0,0);
  var i=0;
  (function press(){ if(i++<5){ $('next').click(); setTimeout(press,1000); return; }
    t.value=''; t.dispatchEvent(new Event('input'));  // the note gone: nothing unsaved, so the receipt shows
    document.querySelector('[data-ss-id="keel-receipt"]').outerHTML='<div data-ss-id="keel-receipt" hidden data-receipt=\\'{"at":"2030-01-01T10:00:00Z","saves":["2030-01-01T09:59:00Z"],"what":"D1, 1 note","refused":[]}\\'></div>';
    localStorage.setItem('memo-sent:'+window.MEMO.slug,'2030-01-01T09:59:00Z');
    document.dispatchEvent(new CustomEvent('ss:live',{detail:{mode:'patch',ids:['keel-receipt']}}));
    log.push($('state-word').textContent+': '+$('status').textContent.split(' at ')[0]);
    var pre=document.createElement('pre'); pre.id='probe'; pre.textContent=log.join(' | '); document.body.appendChild(pre);
  })(); }, 300); });
</script>"""
sent = """<script>try{localStorage.clear();localStorage.setItem('memo-sent:%s','2099-01-01T00:00:00Z')}catch(e){}
window.addEventListener('load',function(){ setTimeout(function(){
  var n=document.getElementById('next').getBoundingClientRect(), pin=document.createElement('div');
  pin.style.cssText='position:absolute;z-index:2147483645;width:28px;height:28px;left:'+(n.left+scrollX)+'px;top:'+(n.top+scrollY)+'px';
  document.body.appendChild(pin);
  var hit=document.elementFromPoint(n.left+n.width/2, n.top+n.height/2);
  document.getElementById('stwrap').classList.add('open');
  var b=document.querySelector('.bar').getBoundingClientRect(), s=document.getElementById('state').getBoundingClientRect(), q=document.getElementById('status').getBoundingClientRect();
  var fits=s.left>=b.left&&s.right<=b.right&&q.left>=b.left&&q.right<=b.right?'fits':'overflows';
  var pre=document.createElement('pre'); pre.id='probe'; pre.textContent=document.getElementById('state-word').textContent+' | '+(hit===pin?'pin':hit.id)+' | '+fits; document.body.appendChild(pre); }, 300); });
</script>""" % slug
Path(sys.argv[3]).write_text(page.replace("<body>", "<body>" + inset + probe, 1))
Path(sys.argv[4]).write_text(page.replace("<body>", "<body>" + sent, 1))
# the newest Save refused while an earlier one was taken; then answers the doc kept; then a whole-page morph
bad = {"at": "2026-10-20T10:06:00Z", "saves": ["2026-10-20T10:00:00Z"], "what": "D1", "kept": [],
       "refused": [{"saved": "2026-10-20T10:05:00Z", "why": "an answer that reads as a D-item"}]}
page2, _ = m.sheep_page(text, "one.md", {"rel": "docs/one.md", "sha": "abcdef0", "branch": "claude/x", "receipt": bad})
partly = '{"at":"2030-01-01T10:00:00Z","saves":["2030-01-01T09:59:00Z"],"what":"D2","kept":["D1 (git changed it after the page\\u0027s commit)"],"refused":[]}'
taken = '{"at":"2031-01-01T10:00:00Z","saves":["2031-01-01T09:59:00Z"],"what":"D2","refused":[]}'
seq = """<script>try{localStorage.clear()}catch(e){}
window.addEventListener('load',function(){ setTimeout(function(){
  var $=function(i){return document.getElementById(i);}, log=[$('state-word').textContent];
  var put=function(r, mode){ var el=document.querySelector('[data-ss-id="keel-receipt"]'); el.setAttribute('data-receipt', r);
    document.dispatchEvent(new CustomEvent('ss:live',{detail:{mode:mode,ids:['keel-receipt']}})); log.push($('state-word').textContent); };
  put(%r, 'patch'); put(%r, 'morph');
  var pre=document.createElement('pre'); pre.id='probe'; pre.textContent=log.join(' | '); document.body.appendChild(pre); }, 300); });
</script>""" % (partly, taken)
Path(sys.argv[4].replace("navr", "navs")).write_text(page2.replace("<body>", "<body>" + seq, 1))
PY
  perl -e 'alarm shift; exec @ARGV' 90 "$CHROME" --headless=new --disable-gpu --no-first-run --user-data-dir="$T/chrome" --virtual-time-budget=9000 \
    --window-size=500,700 --dump-dom "file://$T/navq.html" 2>/dev/null > "$T/navq.dom"; crc=$?
  perl -e 'alarm shift; exec @ARGV' 90 "$CHROME" --headless=new --disable-gpu --no-first-run --user-data-dir="$T/chrome" --virtual-time-budget=2000 \
    --window-size=500,700 --dump-dom "file://$T/navr.html" 2>/dev/null > "$T/navr.dom"; rrc=$?
  perl -e 'alarm shift; exec @ARGV' 90 "$CHROME" --headless=new --disable-gpu --no-first-run --user-data-dir="$T/chrome" --virtual-time-budget=2000 \
    --window-size=500,700 --dump-dom "file://$T/navs.html" 2>/dev/null > "$T/navs.dom"; src=$?
  if [ "$crc" = 142 ] || [ "$rrc" = 142 ] || [ "$src" = 142 ]; then echo "  skip the spacesheep footer in Chrome: Chrome did not finish in 90 s"
  else
    check "$(sed -n 's/.*<pre id="probe">\([^<]*\)<.*/\1/p' "$T/navq.dom")" \
      "Taken | 2/2 answered · ✎1 · 1 note | 2/2 answered · ✎2 · 1 note · feedback written / 2 of 2 decisions answered · 1 note · feedback written | note | card-D1 | card-D2 | card-feedback | Taken: Taken into the doc" \
      "the spacesheep footer in Chrome: Taken from the deployed receipt; a note and the feedback count as one ✎ beside the tally, never on it; a note is a stop; ↓ moves under the header's inset; a pushed receipt says Taken"
    check "$(sed -n 's/.*<pre id="probe">\([^<]*\)<.*/\1/p' "$T/navr.dom")" "Sent | next | fits" \
      "…a Save sent after the newest receipt says Sent, not the older Taken; ↓ takes the click over a spacesheep comment pin (z-index 2147483645); the pill and its open pop-up stay inside the bar"
    check "$(sed -n 's/.*<pre id="probe">\([^<]*\)<.*/\1/p' "$T/navs.dom")" "Refused | Partly | Partly" \
      "…the newest Save refused says Refused though an earlier one was taken; answers the doc kept say Partly; a whole-page morph re-says nothing"
  fi
else
  echo "  skip footer in Chrome: no Chrome on this machine"
fi

echo "keel step: the one writer of a step's status (entry D6-A, S4)"
sed -e 's/^\(- \*\*S[0-9]* — .*status: \).*$/\1not started/' -e 's/^Status: [a-z]* —/Status: answered —/' "$K/one.md" > "$K/step.md"
"$B/keel" step "$K/step.md" S1 done --branch claude/laptop/2026-10-15-x --date 2026-10-15 --stamp > "$T/step.out"; rc=$?
check "$rc" "0" "step: done"
has "$T/step.out" "step.md S1: status: done 2026-10-15 claude/laptop/2026-10-15-x (was: not started)" "…says what it wrote and what was there"
has "$K/step.md" "- **S1 — the grammars in \`bin/keel\`** · session \`sr-worker\` · after: D1, D2 · gate: \`bin/keel\` · status: done 2026-10-15 claude/laptop/2026-10-15-x" "…the field rewritten in place, the others kept"
has "$T/step.out" "stamped step.md: Status: building" "…--stamp: the Status line follows"
"$B/keel" step "$K/step.md" S2 blocked --note "waits · on a probe" > /dev/null
has "$K/step.md" "· status: blocked — waits , on a probe" "step: a note after an em dash, its · made harmless"
check "$(kp "$K/step.md" 'print([x["status"] for x in d["steps"]])')" "['done', 'blocked', 'not started']" "…and keel parse reads every word back"
printf '%s\n' '# X' '' '## Action plan' '' '- **S1 — no field yet** · session `worker` · after: —' > "$K/nofield.md"
"$B/keel" step "$K/nofield.md" S1 wip > /dev/null
has "$K/nofield.md" "- **S1 — no field yet** · session \`worker\` · after: — · status: wip" "step: a line with no status field gets one"
"$B/keel" step "$K/step.md" S9 done > /dev/null 2>&1; check "$?" "1" "step: an id the Action plan lacks is refused"
"$B/keel" step "$K/step.md" S1 finished > /dev/null 2>&1; check "$?" "1" "step: a word that is no step word is refused"
cp "$K/step.md" "$K/step.before"; "$B/keel" step "$K/step.md" S2 blocked --note "waits · on a probe" > "$T/step2.out"
lacks "$T/step2.out" "(was:" "step: the same status again changes nothing"
check "$(cmp -s "$K/step.md" "$K/step.before" && echo same)" "same" "…byte for byte"

echo "keel landing: /finish and autofinish refuse a branch whose brief names an open step (entry D6-A, S7)"
L="$T/landing"; git init -q -b main "$L"
lg() { git -c user.name=t -c user.email=t@t -C "$L" "$@"; }
mkdir -p "$L/docs/handoff"
printf '%s\n' '# C' '' 'Status: building — 0 of 0 decisions answered · action plan: 1 of 3 steps done · handed over 2026-10-15' '' '## Action plan' '' \
  '- **S1 — one** · session `worker` · after: — · status: done 2026-10-15 claude/x' \
  '- **S2 — two** · session `worker` · after: S1 · status: not started' \
  '- **S3 — three** · session `worker` · after: S1 · status: not started' > "$L/docs/course.md"
printf 'Task: an old brief on main\nSteps: S3 of docs/course.md\n' > "$L/docs/handoff/2026-10-01-old.md"
lg add -A; lg commit -qm base
lg checkout -q -b claude/x
printf '# x — batch\nTask: build S1 and S2\nSteps: S1, S2 of `docs/course.md`\n' > "$L/docs/handoff/2026-10-15-x.md"
lg add -A; lg commit -qm brief
(cd "$L" && "$B/keel" landing > "$T/land1.out"); rc=$?
check "$rc" "1" "landing: a brief of this branch names S2, still not started — refused"
has "$T/land1.out" "open step: docs/handoff/2026-10-15-x.md names docs/course.md S2 — not started" "…naming the brief, the doc and the step"
lacks "$T/land1.out" " S1 " "…a done step is no refusal"
lacks "$T/land1.out" "2026-10-01-old.md" "…a brief already on main is not this branch's"
has "$T/land1.out" "nothing written" "…and says it wrote nothing"
check "$(lg status --porcelain)" "" "…and wrote nothing"
"$B/keel" step "$L/docs/course.md" S2 done --branch claude/x > /dev/null; lg commit -qam "S2 done"
check "$("$B/keel" landing "$L"; echo "rc=$?")" "landing: no brief on this branch names an open step
rc=0" "landing: every named step done — lands"
"$B/keel" step "$L/docs/course.md" S2 superseded --note "by docs/other.md" > /dev/null; lg commit -qam "S2 superseded"
check "$("$B/keel" landing "$L" > /dev/null; echo $?)" "0" "landing: superseded counts as closed"
printf 'Task: more\nSteps: S9 of /Users/someone/projects/repo/docs/course.md\n' > "$L/docs/handoff/2026-10-15-y.md"; lg add -A; lg commit -qm y
"$B/keel" landing "$L" > "$T/land2.out"; rc=$?
check "$rc" "1" "landing: a step the doc lacks cannot be shown done — refused"
has "$T/land2.out" "names docs/course.md S9 — no such step in its Action plan" "…an absolute path read from its docs/ on"
printf 'Task: a brief without a Steps line\n' > "$L/docs/handoff/2026-10-15-y.md"; lg commit -qam "no steps"
check "$("$B/keel" landing "$L" > /dev/null; echo $?)" "0" "landing: a brief with no Steps: line names none (every brief before 2026-10-15)"

echo "keel embark: /embark's list — the open items the sweep cannot take, by block reason (review D4-A, entry S5)"
E="$T/embroot"; mkdir -p "$E/a/docs" "$E/p/docs"
for r in a p; do git init -q -b main "$E/$r"; done
git -C "$E/p" remote add origin git@github.com:o/p.git
printf '# P\n\n- physical: house — live\n' > "$E/p/AGENTS.md"
doc() { # <file> <items…>: a doc of D-items, each given as "title|reversible|pick"
  f="$1"; shift; n=0; { echo "# $(basename "$f" .md)"; echo; echo "## Decisions"; echo
    for spec in "$@"; do n=$((n+1)); IFS='|' read -r ti rv pk <<< "$spec"
      echo "- **D$n — $ti**"; echo "  - A — one"; echo "  - B — two"; echo
      [ -n "$rv" ] && { echo "  Reversible: $rv"; echo; }
      echo "  ➤ Recommended: $pk"; echo; echo "  ➤ Answer:"; echo; done; } > "$f"; }
doc "$E/a/docs/old-2026-10-01.md" "irreversible|no|A" "unmarked one||A" "either way|yes|A if the probe passes, else B" "bare pick|yes|B"
doc "$E/a/docs/young-2026-10-14.md" "too new|no|A"
doc "$E/p/docs/phys-2026-10-01.md" "in a physical repo|yes|A"
for r in a p; do git -C "$E/$r" add -A; done
GIT_AUTHOR_DATE=2026-10-01T00:00:00Z GIT_COMMITTER_DATE=2026-10-01T00:00:00Z git -c user.name=t -c user.email=t@t -C "$E/a" commit -q -m old -m "Claude-Session: x" -- docs/old-2026-10-01.md
GIT_AUTHOR_DATE=2026-10-14T20:00:00Z GIT_COMMITTER_DATE=2026-10-14T20:00:00Z git -c user.name=t -c user.email=t@t -C "$E/a" commit -q -m young -m "Claude-Session: x"
GIT_AUTHOR_DATE=2026-10-01T00:00:00Z GIT_COMMITTER_DATE=2026-10-01T00:00:00Z git -c user.name=t -c user.email=t@t -C "$E/p" commit -q -m phys -m "Claude-Session: x"
MEMO_NOW=2026-10-15T00:00:00Z "$B/keel" embark --root "$E" --json > "$T/emb.json"; rc=$?
check "$rc" "0" "embark: runs, read-only"
check "$(python3 -c "import json; print([(r['reason'], r['id']) for r in json.load(open('$T/emb.json'))])")" "[('Reversible: no', 'D1'), ('unmarked', 'D2'), ('conditional', 'D3'), ('physical repo', 'D1'), ('no link', 'D4')]" "embark: grouped in the brief's order — an item's own reason first, then the doc's; the sweep-less repo and the physical repo each named"
check "$(python3 -c "import json; print(sorted(set(r['doc'].rsplit('/', 1)[1] for r in json.load(open('$T/emb.json')))))")" "['old-2026-10-01.md', 'phys-2026-10-01.md']" "…a doc handed over under 72 h ago is not listed"
check "$(python3 -c "import json; print([r['age_h'] for r in json.load(open('$T/emb.json'))][:1])")" "[336.0]" "…ages counted from the commit that added the doc"
MEMO_NOW=2026-10-15T00:00:00Z "$B/keel" embark --root "$E" > "$T/emb.out"
has "$T/emb.out" "5 items in 2 docs — oldest first in each group" "embark: the heading counts items and docs"
has "$T/emb.out" "Reversible: no — 1" "…a group heading with its count"
has "$T/emb.out" "14d · a · D2 unmarked one — $E/a/docs/old-2026-10-01.md#L" "…each item: age, repo, id, title, its doc and line"
check "$(MEMO_NOW=2026-10-15T00:00:00Z "$B/keel" embark --root "$E" --hours 400 | head -1 | cut -c1-130)" "Open items the stand sweep cannot take, in docs handed over more than 400 h ago: 0 items in 0 docs — oldest first in each group" "embark --hours: a doc younger than that is left out"
check "$(git -C "$E/a" status --porcelain)" "" "embark: wrote nothing"

echo "knowledge-numbers: /sextant measures G1-G6 of the entry, one row each (entry S10)"
GN="$T/gn"; mkdir -p "$GN/docs"
{ echo "# Course"; echo; echo "## Goals — how we will know it worked"; echo
  echo "| Goal | Today | Target | How |"; echo "| --- | --- | --- | --- |"
  echo "| G1 — docs never opened 3 days after hand-over | 20 % (15 of 76) | ≤ 10 % | \`unseen\` |"
  echo "| G2 — opened docs abandoned part-way | 8 % (5 of 60) | ≤ 5 % | \`partial\` |"
  echo "| G3 — median hours to first answer | 2.0 h (n = 69) | ≤ 2 h | the Status line's dates |"
  echo "| G4 — answered docs with a build trace | 42 % (25 of 60, proxy) | ≥ 80 % | any S-step done |"
  echo "| G5 — overrule rate, a band | 25 % | 15–35 % | kept vs overruled |"
  echo "| G6 — open docs older than 7 days | 13 of 31 | ≤ 5 | keel open |"
  echo "| G7 — a goal this tool has no measure for | — | — | — |"; } > "$GN/docs/design-docs-2026-10-14.md"
python3 - "$(dirname "$(peer knowledge-numbers)")" "$GN" "$E" > "$T/gn.out" <<'PYX'
import sys, datetime as dt
from importlib.machinery import SourceFileLoader as L
from pathlib import Path
kn = L("kn", sys.argv[1] + "/knowledge-numbers").load_module()
now = dt.datetime(2026, 10, 15, tzinfo=dt.timezone.utc).timestamp()
for g in kn.course_goals(now, root=Path(sys.argv[2]), projects=Path(sys.argv[3])):
    print(g["id"], "|", g["value"] if g["value"] is not None else "not measured — " + g["why"])
print("missing:", [g["id"] for g in kn.course_goals(now, root=Path(sys.argv[3]) / "nope", projects=Path(sys.argv[3]))])
PYX
has "$T/gn.out" "G1 | 100 % (2 of 2)" "G1: the unseen share of docs handed over 3 to 28 days ago (the docs under 72 h left out)"
has "$T/gn.out" "G2 | not measured — only a Course doc's Status line dates its first answer" "G2: not measured, and why"
has "$T/gn.out" "G3 | not measured — a Status line keeps the day of the first answer, not the hour" "G3: not measured, and why"
has "$T/gn.out" "G4 | not measured — only a Course doc carries S-steps" "G4: not measured, and why"
has "$T/gn.out" "G5 | not measured — no doc handed over in the last 28 days has an item " "G5: not measured while no item was answered — never a guess"
has "$T/gn.out" "G6 | 2 of 3 (age from the file name)" "G6: open rows with a file-name date over 7 days old"
has "$T/gn.out" "G7 | not measured — no measure for G7 in bin/knowledge-numbers yet" "a goal the tool has no measure for says so"
has "$T/gn.out" "missing: ['G1–G6']" "no entry doc on the checkout: one row saying so"

echo "knowledge-numbers: projects with a transcript this week and no memory link (TODO item 5, 2026-10-19)"
MU="$T/mu"; mkdir -p "$MU/projects/linked" "$MU/projects/plain" "$MU/projects/old" "$MU/vault/memory/linked" "$MU/cfg/projects"
python3 - "$(dirname "$(peer knowledge-numbers)")" "$MU" > "$T/mu.out" <<'PYX'
import os, sys, time
from importlib.machinery import SourceFileLoader as L
from pathlib import Path
kn = L("kn", sys.argv[1] + "/knowledge-numbers").load_module()
mu = Path(sys.argv[2]); kn.PROJECTS, kn.VAULT = mu / "projects", mu / "vault"
proj = mu / "cfg" / "projects"
def folder(name, body="x", age=0, memory=None):
    f = proj / name; f.mkdir(parents=True, exist_ok=True)
    t = f / "s.jsonl"; t.write_text(body); os.utime(t, (time.time() - age,) * 2)
    if memory == "link":
        (f / "memory").symlink_to(mu / "vault" / "memory" / "linked")
    elif memory == "dir":
        (f / "memory").mkdir()
    return f
P = kn.slug(kn.PROJECTS)
folder(P + "-linked", memory="link")
folder(P + "-plain", memory="dir")
folder(P + "-plain--claude-worktrees-topic")      # folds into plain
folder(P + "-old", age=8 * 86400, memory="dir")   # nothing this week
folder(P + "-empty", body="", memory="dir")       # an empty transcript is not a session
folder("-private-tmp-probe")                      # a scratchpad
folder(kn.slug(mu))                               # a session opened outside ~/projects
print(kn.memory_unlinked(time.time(), dirs=[mu / "cfg"]))
PYX
has "$T/mu.out" "['plain']" "only plain counts: linked, old, empty, a scratchpad and a non-project folder do not"

echo "regatta-modules G10, G33: atlas's docs-index and helm's asklib absent"
# A monorepo of the core and keel alone: the core's tool() finds neither (atlas sits beside keel
# since B10, so the real checkout would find docs-index). NP: no variable, kept for the env calls.
NP="KEEL_NO_PEERS=1"
mkdir -p "$T/no-atlas/.claude-plugin" "$T/no-atlas/modules"
cp "$B/../../../.claude-plugin/marketplace.json" "$T/no-atlas/.claude-plugin/"
cp -R "$(cd "$B/../../regatta" && pwd)" "$(cd "$B/.." && pwd)" "$T/no-atlas/modules/"
NB="$T/no-atlas/modules/keel/bin"
check "$(env "$NP" python3 -c 'import sys; from importlib.machinery import SourceFileLoader as L; k = L("k", sys.argv[1]).load_module(); print(k.docs_index(), k._asklib(), k.taken_answer("Relayed from manager (x) (yes item, 2026-10-16): A"), k.taken_answer(k.YOLO_ANSWER % ("2026-10-16", "A")))' "$NB/keel" 2>&1)" \
      "None None False True" "G10/G33: no docs-index, no asklib — a relayed answer reads as Sam's, a yolo pick is still taken"
check "$(python3 -c 'import sys; from importlib.machinery import SourceFileLoader as L; k = L("k", sys.argv[1]).load_module(); print(k.docs_index() is not None, k.taken_answer("Relayed from manager (x) (yes item, 2026-10-16): A"))' "$B/keel" 2>&1)" \
      "True True" "  with them: found through the core's tool(), and the relayed answer is taken"
mkdir -p "$T/g10/docs" && git -C "$T/g10" init -q && printf '# R\n\n- **D1 — x.**\n  Reversible: yes\n  ➤ Recommended: A\n  ➤ Answer: A\n' > "$T/g10/docs/r-2026-10-01.md"
check "$(cd "$T/g10" && env "$NP" python3 "$NB/keel" status docs/r-2026-10-01.md --stamp 2>&1 | grep -c 'docs-index (atlas) is not installed')" 1 "G10: keel stamp without atlas says so in one line"
mkdir -p "$T/g11/.claude"
# Absent means absent from this checkout too: lighthouse sits beside keel since B9, so the case runs
# sheep from a scratch checkout holding only the core and keel's own files, no plugin registry.
G11R="$T/g11/regatta"; mkdir -p "$G11R/.claude-plugin" "$G11R/modules/regatta" "$G11R/modules/keel" "$T/g11/cfg"
cp "$B/../../../.claude-plugin/marketplace.json" "$G11R/.claude-plugin/"
cp -R "$B/../../regatta/hooks" "$G11R/modules/regatta/"
for d in bin hooks lib; do cp -R "$B/../$d" "$G11R/modules/keel/"; done
check "$(env "$NP" CLAUDE_CONFIG_DIR="$T/g11/cfg" python3 -c 'import sys; from pathlib import Path; from importlib.machinery import SourceFileLoader as L; s = L("s", sys.argv[1]).load_module()
try: s.gate_file(Path(sys.argv[2]) / "settings.json", True)
except s.Refused as e: print(e)' "$G11R/modules/keel/bin/sheep" "$T/g11/.claude" 2>&1)" \
      "claude-settings (lighthouse) is not installed — settings are not written; check and audit still read" "G11: sheep's settings writer absent — the verb refuses in one line"
if [ -f "$B/../../lighthouse/bin/claude-settings" ]; then
  check "$(env "$NP" CLAUDE_CONFIG_DIR="$T/g11/cfg" python3 -c 'import sys; from importlib.machinery import SourceFileLoader as L; s = L("s", sys.argv[1]).load_module(); print(s._claude_settings().__name__)' "$B/sheep" 2>&1)" \
        "claude_settings" "  with lighthouse in the checkout: its writer is found through the core's tool()"
fi

echo "knowledge-numbers: /sextant reads the Wharf goals G1-G5, each a number with its source (wharf S8)"
WG="$T/wg"; mkdir -p "$WG/docs"
# the dispatch Mac, as the overlay names it (wharf-runs/ssh): buildbox here. plumb's own wording of
# the host and the owner is its scrub's, so the rows below match around those words.
mkdir -p "$REGATTA_CONFIG/wharf-runs" && printf 'buildbox:buildbox-ssh\n' > "$REGATTA_CONFIG/wharf-runs/ssh"
{ echo "# Wharf"; echo; echo "## Goals — how we will know it worked"; echo
  echo "| Goal | Today | Target | How, when |"; echo "| --- | --- | --- | --- |"
  echo "| G1 — ships built end to end by \`wharf apply\` | 0 | 1 | \`plan.json\` |"
  echo "| G2 — asks that reached Sam past a live skipper | 0 | 0 | \`Relay\` rows |"
  echo "| G3 — buildbox starts that never reach a first prompt | 4 of 5 | 0 | \`FAILED: never busy\` |"
  echo "| G4 — live lines of the layer | 33,892 | 34,300 | \`wc -l\` |"
  echo "| G5 — old words in live files | 1,141 | 0 | \`bin/test_vocabulary.sh\` |"; } > "$WG/docs/wharf-on-orca-2026-10-17.md"
python3 - "$(dirname "$(peer knowledge-numbers)")" "$WG" > "$T/wg.out" <<'PYX'
import sys, json, datetime as dt
from importlib.machinery import SourceFileLoader as L
from pathlib import Path
kn = L("kn", sys.argv[1] + "/knowledge-numbers").load_module()
root = Path(sys.argv[2])
now = dt.datetime(2026, 10, 19, 12).timestamp()
iso = lambda t: dt.datetime.fromtimestamp(t).astimezone().isoformat(timespec="seconds")
def mk(name):
    (root / name).mkdir(parents=True, exist_ok=True)
    return root / name
def line(tag, g):
    print(tag, g["id"], "|", g["value"] if g["value"] is not None else "not measured — " + g["why"])
def show(tag, only=None, **kw):
    for g in kn.wharf_goals(now, root=kw.pop("root", root), **kw):
        if only is None or g["id"] in only:
            line(tag, g)
one = lambda days: {"x": False}   # a stub for the ssh read

# an empty week: a plans directory with nothing in it, an attention log with no Relay row, no dispatch log
plans, att, logs = mk("e/plans"), mk("e/attention"), mk("e/logs")
(att / "2026-10.jsonl").write_text(json.dumps({"ts": iso(now), "event": "PermissionRequest", "type": "x"}) + "\n")
show("empty", plans=plans, attention=att, logs=logs, scan=lambda days: {}, host="laptop")

# one ship built: a blueprint with an Orca Run that wharf marked ended this week, one worker session on
# record, the skipper's (`by`) and a lander's reports beside it; a ship half built (a block landed, not
# ended), a cancelled twin that ended, and a blueprint with no Run
plans, att, logs = mk("s/plans"), mk("s/attention"), mk("s/logs")
d = plans / "p1"; d.mkdir()
(d / "plan.json").write_text(json.dumps({
    "tasks": {"a": {"ship": "yard"}, "launch-a": {"ship": "yard"}, "z": {"ship": "twin"}, "h": {"ship": "half"}, "h2": {"ship": "half"}},
    "blueprints": {"yard": {"orca_run": "run_1", "by": "skip0000-1", "created_run": now - 3600, "accepted": now - 60,
                            "ended": now - 1000, "blocks": {"a": "d1", "launch-a": "d2"}},
                   "half": {"orca_run": "run_3", "blocks": {"h": "d4", "h2": "d5"}},
                   "twin": {"orca_run": "run_2", "cancelled": "a duplicate", "ended": now - 900, "blocks": {"z": "d3"}},
                   "noyet": {"accepted": now, "blocks": {}}}}))
events = [{"task": "a", "status": "running", "t": now - 3000, "session": "abc12345-0000"},
          {"task": "launch-a", "status": "waiting", "t": now - 2000},
          {"task": "a", "status": "done", "t": now - 2500, "session": "skip0000-1"},
          {"task": "launch-a", "status": "launched", "t": now - 1000, "session": "land0000-1"},
          {"task": "h", "status": "landed", "t": now - 950},
          {"task": "h2", "status": "running", "t": now - 940},
          {"task": "z", "status": "landed", "t": now - 900}]
(d / "events.jsonl").write_text("\n".join(json.dumps(e) for e in events) + "\nnot json\n")
show("ship", ("G1",), plans=plans, attention=att, logs=logs, scan=one, host="laptop")

# one escalated relay from the ship's worker (session abc12345), made before the last re-accept; a stranger's,
# the skipper's and the lander's escalations and an answered one beside it
(att / "2026-10.jsonl").write_text("\n".join(json.dumps(r) for r in [
    {"ts": iso(now - 1200), "event": "Relay", "type": "escalated", "session": "abc12345", "detail": "doc#D1 — A"},
    {"ts": iso(now - 1150), "event": "Relay", "type": "escalated", "session": "skip0000", "detail": "doc#D4 — A"},
    {"ts": iso(now - 1100), "event": "Relay", "type": "escalated", "session": "land0000", "detail": "doc#D5 — A"},
    {"ts": iso(now - 500), "event": "Relay", "type": "escalated", "session": "zzzz9999", "detail": "doc#D2 — A"},
    {"ts": iso(now - 400), "event": "Relay", "type": "answered", "session": "abc12345", "detail": "doc#D3 — A"}]) + "\n")
show("relay", ("G2",), plans=plans, attention=att, logs=logs, scan=one, host="laptop")
# no ship records a worker session: the rows cannot be tied to a ship, said instead of a 0
(d / "events.jsonl").write_text(json.dumps({"task": "a", "status": "running", "t": now - 3000, "session": None}) + "\n")
show("nosession", ("G2",), plans=plans, attention=att, logs=logs, scan=one, host="laptop")

# G3: dispatch logs this week — one never busy twice (the retry), one fine, one refused by the week, one
# holding two starts of the day (one never busy), one whose retry got busy; an old one and a run-seed
# log are no start of this week's
for name, body in [("2026-10-18-dispatch-a.log", "FAILED: never busy in 300 s\nnever started interactively — retrying once\nFAILED: never busy in 300 s\n== exit 3 at x\n"),
                   ("2026-10-18-dispatch-b.log", "ran\n== exit 0 at x\n"),
                   ("2026-10-18-dispatch-c.log", "FAILED: acct-b: week 97 % >= 95 %\n"),
                   ("2026-10-17-dispatch-d.log", "FAILED: never busy in 300 s\n== exit 3 at x\nran\n== exit 0 at y\n"),
                   ("2026-10-16-dispatch-e.log", "FAILED: never busy in 300 s\nnever started interactively — retrying once\n== exit 0 at x\n"),
                   ("2026-10-02-dispatch-old.log", "FAILED: never busy in 300 s\n"),
                   ("2026-10-18-run-seed-x.log", "FAILED: never busy in 300 s\n")]:
    (logs / name).write_text(body)
show("buildbox", ("G3",), plans=plans, attention=att, logs=logs, scan=lambda days: {"a": True, "b": False, "c": False, "d": False}, host="laptop")
show("local", ("G3",), plans=plans, attention=att, logs=logs, host="buildbox")
def down(days):
    raise kn.NotMeasured("buildbox is not readable over ssh buildbox-ssh (stub)")
show("down", ("G3",), plans=plans, attention=att, logs=logs, scan=down, host="laptop")
def broken(days):
    raise RuntimeError("a | b")
show("broken", ("G3",), plans=plans, attention=att, logs=logs, scan=broken, host="laptop")

# G4 and G5 on a checkout with two of the baseline's files and the land words on three lines of two files
r = mk("c")
(r / "bin").mkdir(); (r / "hooks").mkdir(); (r / "docs").mkdir()
(r / "bin/ask").write_text("a\nb\nc\n"); (r / "hooks/attention.py").write_text("x\n"); (r / "bin/wharf").write_text("w\n" * 10)
(r / "bin/tool").write_text("it landed\nnothing\nthe lander lands\n"); (r / "hooks/h.py").write_text("Land here\nlandscape\n")
(r / "docs/wharf-on-orca-2026-10-17.md").write_text((root / "docs/wharf-on-orca-2026-10-17.md").read_text())
show("tiny", ("G4", "G5"), root=r, plans=plans, attention=att, logs=logs, scan=one, host="laptop")
(r / "bin/test_vocabulary.sh").write_text("echo 'vocabulary: 2 old words'\nexit 1\n")
(r / "hooks/attention.py").write_text("#!/usr/bin/env python3\n# Source shim: moved to a regatta module\n")
show("shim", ("G4",), root=r, plans=plans, attention=att, logs=logs, scan=one, host="laptop")
show("vocab", ("G5",), root=r, plans=plans, attention=att, logs=logs, scan=one, host="laptop")
# a checkout without the baseline's files or the grep's paths, and one without the wharf doc
# a checkout from before rename S5: bin/plan and planlib.py hold the text bin/helm and helmlib.py hold after it
o = mk("pre"); (o / "bin").mkdir(); (o / "docs").mkdir()
(o / "bin/plan").write_text("p\n" * 5); (o / "bin/planlib.py").write_text("l\n" * 2); (o / "bin/wharf").write_text("w\n")
(o / "docs/wharf-on-orca-2026-10-17.md").write_text((root / "docs/wharf-on-orca-2026-10-17.md").read_text())
show("pre", ("G4",), root=o, plans=plans, attention=att, logs=logs, scan=one, host="laptop")
b = mk("bare"); (b / "docs").mkdir()
(b / "docs/wharf-on-orca-2026-10-17.md").write_text((root / "docs/wharf-on-orca-2026-10-17.md").read_text())
show("bare", ("G4", "G5"), root=b, plans=plans, attention=att, logs=logs, scan=one, host="laptop")
print("nodoc:", [g["id"] + " " + (g["why"] or "")[:24] for g in kn.wharf_goals(now, root=mk("nodoc"))])
PYX
has "$T/wg.out" "empty G1 | 0 of 0 ships with an Orca Run" "G1, an empty week: 0 of 0, with its source"
has "$T/wg.out" "empty G2 | 0 — no \`Relay\` row \`escalated\` (attention log, 0 Relay rows in the last 7 days)" "G2, an empty week: 0 with its source"
has "$T/wg.out" "empty G3 | not measured — no " "G3, no start logged: not measured, never a 0"
has "$T/wg.out" " in the last 7 days records a start" "…none in the last 7 days (the dispatch Mac named plumb's way)"
has "$T/wg.out" "ship G1 | 1 of 2 ships with an Orca Run built, 1 this week — plan.json blueprints with \`orca_run\` that wharf marked \`ended\`" "G1: the ended ship counts; the half-built one, the cancelled twin and the blueprint with no Run do not"
has "$T/wg.out" "relay G2 | 1 of 4 escalated rows from a ship worker while its ship was open (attention log, 5 Relay rows in the last 7 days)" "G2: the worker's relay before a re-accept counts; the skipper's, the lander's, a stranger's and an answered one do not"
has "$T/wg.out" "nosession G2 | not measured — 4 \`Relay\` rows \`escalated\`, but no ship worker's session is recorded" "G2, no worker session on record: says so"
has "$T/wg.out" "buildbox G3 | 1 of 4 starts never busy" "G3: one per log (the retry's second line counts once)"
has "$T/wg.out" "this Mac: 2 of 5" "G3: one per start — two starts in one log, a retry that got busy is no failure; a refused start, an old log and a run-seed log are no start"
has "$T/wg.out" "local G3 | 2 of 5 starts never busy — \`FAILED: never busy\` and exit 3, one per start, " "G3 on buildbox itself: the local logs, no ssh"
check "$(grep -F 'local G3 |' "$T/wg.out" | grep -c 'over ssh')" "0" "…its own logs, never over ssh"
has "$T/wg.out" "down G3 | not measured — buildbox is not readable over ssh buildbox-ssh (stub); this Mac: 2 of 5" "G3, buildbox unreachable: why, and this Mac's number"
has "$T/wg.out" "broken G3 | not measured — the read failed: RuntimeError: a / b" "an unexpected error costs one row, never the run; a | in it cannot break the table"
has "$T/wg.out" "tiny G4 | 4 lines — \`wc -l\` over the baseline's 2 files (evidence section 2); 14 with bin/wharf, bin/plan; MISSING " "G4: wc -l over the files present, bin/wharf beside, the missing named"
has "$T/wg.out" "tiny G5 | 3 land lines in 2 files — INTERIM read: the rename doc's S8 grep, not bin/test_vocabulary.sh (not built yet)" "G5: the S8 grep counted (landscape is no land word), and it says it is the interim one"
has "$T/wg.out" "; SHIM hooks/attention.py, moved to regatta" "G4: a file that became a regatta shim is named, so its drop is not read as a cut"
has "$T/wg.out" "vocab G5 | bin/test_vocabulary.sh exits 1 — vocabulary: 2 old words" "G5: bin/test_vocabulary.sh, once it exists, is the read"
has "$T/wg.out" "pre G4 | 7 lines — \`wc -l\` over the baseline's 2 files (evidence section 2); 8 with bin/wharf; MISSING " "G4 before S5: bin/plan and planlib.py counted as the baseline's, bin/plan not again beside it"
has "$T/wg.out" "bare G4 | not measured — none of the baseline's 34 files is on this checkout" "G4: no file to count is not a 0"
has "$T/wg.out" "bare G5 | not measured — none of the grep's paths" "G5: no path to grep is not a 0"
has "$T/wg.out" "nodoc: ['G1–G5 docs/wharf-on-orca-2026-" "no wharf doc on the checkout: one row saying so"


echo "light — B1 of docs/light-gate-2026-10-16.md: --check, --plan, --write from the session's transcript"
LT="$T/light"; mkdir -p "$LT/tr/proj"
# the surface is recorded from the environment: pinned here, so a suite run in VS Code reads the same
export TERM_PROGRAM=""
ldoc() {  # FILE N [REC] — N items, three options each, Reversible: yes, ➤ Recommended: REC (default A)
  { echo "# Light me (design, 2026-10-16)"; echo
    echo 'Written by `Claude` (Opus 5.5, `high`) on 2026-10-16 for "t".'; echo "Second line of the paragraph."; echo
    echo "## Decisions"; echo
    for n in $(seq "$2"); do
      echo "- **D$n — Which recorder $n.** Context for $n. More context."; echo "  - A — Voice Memos — the app on the Mac"
      echo "  - B — Files: a folder in iCloud"; echo "  - C — Something else entirely with many words here"; echo
      echo "  Reversible: yes"; echo; echo "  ➤ Recommended: ${3:-A}"; echo; echo "  ➤ Answer:"; echo
    done
    echo "---"; echo; echo "## Open feedback"; } > "$1"
}
ltrans() {  # PLAN OUT SPEC — a transcript: each call of PLAN as a tool_use, and its result as SPEC (one object per call) says
  python3 - "$1" "$2" "$3" <<'PYX'
import json, sys
plan, spec = json.load(open(sys.argv[1])), json.loads(sys.argv[3])
with open(sys.argv[2], "w") as out:
    for k, call in enumerate(plan["calls"]):
        s = spec[k] if k < len(spec) else {}
        qtext = lambda key: next(q["question"] for q in call["questions"]
                                 if q["question"].startswith(key + " —") or (key == "feedback" and q["header"] == "Feedback"))
        uid = "toolu_%d" % k
        out.write(json.dumps({"type": "assistant", "sessionId": "lsess", "timestamp": s.get("asked", "2026-10-16T07:52:58Z"),
                              "message": {"content": [{"type": "tool_use", "id": uid, "name": "AskUserQuestion", "input": call}]}}) + "\n")
        if s.get("declined"):
            continue
        tur = {"questions": call["questions"], "answers": {qtext(a): v for a, v in s.get("answers", {}).items()}}
        if "annotations" in s:
            tur["annotations"] = {qtext(a): {"notes": v} for a, v in s["annotations"].items()}
        tur.update(s.get("extra", {}))
        out.write(json.dumps({"type": "user", "sessionId": "lsess", "timestamp": s.get("answered", "2026-10-16T07:57:14Z"),
                              "message": {"content": [{"type": "tool_result", "tool_use_id": uid, "content": "answered"}]},
                              "toolUseResult": tur}) + "\n")
PYX
}
lplan() { "$B/keel" light "$1" --plan --review light-ok > "$LT/plan.json"; }
# --write takes reviewer-high's verdict (D3); a call that names its own --review keeps it
lwrite() { local r=(--review light-ok); case " $* " in *" --review "*) r=();; esac
  KEEL_TRANSCRIPTS="$LT/tr" CLAUDE_CODE_SESSION_ID=lsess "$B/keel" light "$@" ${r[@]+"${r[@]}"}; }  # bash 3.2 + set -u
lp() { python3 -c "import json,sys; d=json.load(open('$LT/plan.json')); $1"; }
lans() { "$B/keel" parse "$1" | python3 -c 'import json,sys; [print(i["id"], i["answer"]) for i in json.load(sys.stdin)["items"]]'; }

ldoc "$LT/two.md" 2
"$B/keel" light "$LT/two.md" --check > "$LT/c.out"; rc=$?
check "$rc" "0" "--check: two open items, three options each, a bare pick, attended: light"
has "$LT/c.out" "light — 2 open D-items, 1 call; surface terminal" "…says how many items and calls, and the surface"
ldoc "$LT/five.md" 5
"$B/keel" light "$LT/five.md" --check > "$LT/c.out"; rc=$?
check "$rc" "1" "C1: five open items are not light (D4 as revised: four per chain)"
has "$LT/c.out" "C1 size: 5 open D-items, at most 4" "…and says why"
ldoc "$LT/c2.md" 1
sedi 's/^  - C — Something else.*$/  - C — c\
  - D — d\
  - E — e/' "$LT/c2.md"
"$B/keel" light "$LT/c2.md" --check > "$LT/c.out"; rc=$?
check "$rc" "1" "C2: five options are no chip question"
has "$LT/c.out" "C2 options: D1 has 5" "…named with the count"
ldoc "$LT/c3.md" 2 "none until the probe runs"
"$B/keel" light "$LT/c3.md" --check > "$LT/c.out"; rc=$?
check "$rc" "1" "C3: a conditional pick is not ready"
has "$LT/c.out" "C3 ready: D1's pick is conditional" "…a probe nobody ran"
ldoc "$LT/c3b.md" 1 "Z"
"$B/keel" light "$LT/c3b.md" --check > "$LT/c.out"
has "$LT/c.out" "C3 ready: D1's pick (Z) names none of its options" "C3: a pick naming no option cannot go first as (Recommended)"
CLAUDE_UNATTENDED=1 "$B/keel" light "$LT/two.md" --check > "$LT/c.out"; rc=$?
check "$rc" "1" "C4: an unattended run is not light"
has "$LT/c.out" "C4 attended: CLAUDE_UNATTENDED is set" "…it relays instead"
cp "$LT/five.md" "$LT/five-r.md"
"$B/keel" light "$LT/five-r.md" --check --record > /dev/null
check "$(sed -n 6p "$LT/five-r.md")" "Gate: memo — light refused: C1 size: 5 open D-items, at most 4 (a fifth makes it a full memo, light D4)" \
  "--check --record: the refusal is a Gate line under the Written by paragraph, so it is a row too"
"$B/keel" light "$LT/five.md" --plan --review light-ok > /dev/null 2>&1; rc=$?
check "$rc" "1" "--plan refuses a doc the check refuses"
"$B/keel" light "$LT/two.md" --plan > "$LT/c.out" 2>&1; rc=$?
check "$rc" "1" "--plan without reviewer-high's verdict: refused before Sam is asked (D3)"
has "$LT/c.out" "--review light-ok" "…naming the verdict it needs"
"$B/keel" light "$LT/two.md" --plan --review promote > /dev/null 2>&1; rc=$?
check "$rc" "1" "--plan --review promote: a full memo, no questionnaire"
CLAUDE_CODE_ENTRYPOINT=claude-vscode "$B/keel" light "$LT/two.md" --check > "$LT/c.out"
has "$LT/c.out" "surface vscode" "the VS Code side panel (TERM_PROGRAM empty) is recorded as vscode"

ldoc "$LT/three.md" 3; lplan "$LT/three.md"
check "$(lp 'print([len(c["questions"]) for c in d["calls"]])')" "[4]" "--plan, 3 items: one call, three questions and Open feedback"
check "$(lp 'q=d["calls"][-1]["questions"][-1]; print(q["header"], [o["label"] for o in q["options"]])')" \
  "Feedback ['No (Recommended)', 'Not now']" "…Open feedback last, its options only No-shaped (Other is the yes)"
check "$(lp 'print([o["label"] for o in d["calls"][0]["questions"][0]["options"]])')" \
  "['Voice Memos (Recommended)', 'Files', 'Something else entirely with many']" \
  "…labels: before ' — ' or ':', at most five words; the Recommended one tagged"
check "$(lp 'print([o["description"] for o in d["calls"][0]["questions"][0]["options"]])')" \
  "['the app on the Mac', 'a folder in iCloud', 'Something else entirely with many words here']" "…descriptions: the rest, or the whole text when the label was cut"
check "$(lp 'print(d["calls"][0]["questions"][0]["question"], "|", d["calls"][0]["questions"][0]["header"])')" \
  "D1 — Which recorder 1. Context for 1. | D1 recorder" "…question: the D-id, the title and the body's first sentence; header D<n> and a telling word"
ldoc "$LT/four.md" 4 B; lplan "$LT/four.md"
check "$(lp 'print([[q["header"] for q in c["questions"]] for c in d["calls"]])')" \
  "[['D1 recorder', 'D2 recorder', 'D3 recorder'], ['D4 recorder', 'Feedback']]" "--plan, 4 items: two calls, three then one, Open feedback only in the last"
check "$(lp 'print(d["calls"][0]["questions"][0]["options"][0]["label"])')" "Files (Recommended)" "…the Recommended option goes first"
check "$(lp 'qs=[q["question"] for c in d["calls"] for q in c["questions"]]; print(len(set(qs)) == len(qs))')" "True" "…every question unique"
ldoc "$LT/long.md" 1
sedi 's/^- \*\*D1 — Which recorder 1\.\*\* Context for 1\. More context\.$/- **D1 — Recordingdestinations everywhere.** '"$(printf 'word%.0s ' $(seq 80))"'end./' "$LT/long.md"
lplan "$LT/long.md"
check "$(lp 'q=d["calls"][0]["questions"][0]; print(q["header"], len(q["header"]) <= 12, len(q["question"]) <= 200, q["question"].endswith("…"))')" \
  "D1 Recording True True True" "…a long title word is cut to 12 characters, a long question near 200 with an ellipsis"

# the write: D1 the pick, D2 another option, D3 typed in Other; Open feedback "No" is never feedback
lplan "$LT/three.md"; cp "$LT/three.md" "$LT/three.orig"
ltrans "$LT/plan.json" "$LT/tr/proj/lsess.jsonl" '[{"answers": {"D1": "Voice Memos (Recommended)", "D2": "Files", "D3": "Actually, an iMessage from myself would be ideal.", "feedback": "No (Recommended)"}}]'
lwrite "$LT/three.md" --write --why "Sam: --light" --review light-ok > "$LT/w.out"; rc=$?
check "$rc" "0" "--write: every item has a tap on record"
check "$(lans "$LT/three.md")" "D1 Taken in chat (Sam, 2026-10-16 07:57Z): A — Voice Memos (Recommended)
D2 Taken in chat (Sam, 2026-10-16 07:57Z): B — Files
D3 Taken in chat (Sam, 2026-10-16 07:57Z): Other — Actually, an iMessage from myself would be ideal." \
  "…the pick, another option and Other, each with its letter and the label as tapped"
check "$(sed -n 6p "$LT/three.md")" "Gate: light — Sam in chat (terminal); asked 2026-10-16T07:52:58Z, answered 07:57:14Z (4 min 16 s); why: Sam: --light; review: light-ok" \
  "…one Gate line under the Written by paragraph: surface, asked, answered, how long, why, the review"
check "$("$B/keel" parse "$LT/three.md" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["gate"]["mode"], [(i["answered"], i["settled"]) for i in d["items"]])')" \
  "light [(True, True), (True, True), (True, True)]" "…parse reports the gate; every item answered and settled"
lacks "$LT/three.md" "**Sam, 2026-10-16:**" "…Open feedback's \"No\" is never written as feedback"
check "$("$B/keel" lint "$LT/three.md")" "$LT/three.md: no findings" "…and the doc lints clean"
lwrite "$LT/three.md" --write --why x > "$LT/w2.out"; rc=$?
check "$rc" "0" "a second --write: nothing open, exit 0"
has "$LT/w2.out" "no open decision" "…and says so"
"$B/keel" light "$LT/three.md" --check --record > "$LT/c.out"; rc=$?
check "$rc $(sed -n 6p "$LT/three.md" | cut -c1-11)" "0 Gate: light" "--check --record on a doc answered in chat: nothing to ask, exit 0, its Gate: light line kept"
has "$LT/c.out" "nothing open" "…and says so"

lmiss() {  # NAME SPEC EXPECT DESC — a result that is no answer: exit 3 and the doc as it was
  cp "$LT/three.orig" "$LT/$1.md"; lplan "$LT/$1.md"; ltrans "$LT/plan.json" "$LT/tr/proj/lsess.jsonl" "$2"
  lwrite "$LT/$1.md" --write --why x > "$LT/$1.out"; local rc=$?
  check "$rc $(cmp -s "$LT/$1.md" "$LT/three.orig" && echo same)" "3 same" "$4: exit 3, nothing written"
  has "$LT/$1.out" "$3" "…saying why"
}
ALL='"D1": "Files", "D2": "Files", "D3": "Files"'
lmiss afk "[{\"answers\": {$ALL}, \"extra\": {\"afkTimeoutMs\": 60000}}]" "timed out (afkTimeoutMs)" "afkTimeoutMs: the taps a timeout submitted are not answers"
lmiss follow "[{\"answers\": {$ALL}, \"extra\": {\"followUp\": true}}]" "Sam asked a follow-up" "followUp: no answer, the session answers the follow-up first"
lmiss declined '[{"declined": true}]' "no result on record" "a declined dialog (no result)"
lmiss partial '[{"answers": {"D1": "Files", "D2": "Files"}}]' "D3: no answer to it in the result" "one item without an answer"
cp "$LT/three.orig" "$LT/never.md"; : > "$LT/tr/proj/lsess.jsonl"
lwrite "$LT/never.md" --write --why x > "$LT/never.out"; rc=$?
check "$rc" "3" "never asked: exit 3"
has "$LT/never.out" "never asked" "…saying so"

cp "$LT/three.orig" "$LT/notes.md"; lplan "$LT/notes.md"
ltrans "$LT/plan.json" "$LT/tr/proj/lsess.jsonl" "[{\"answers\": {$ALL, \"feedback\": \"Next time, fewer options.\"}, \"annotations\": {\"D1\": \"only the Mac's\"}, \"extra\": {\"response\": \"Ship it, but tell Alex.\"}}]"
lwrite "$LT/notes.md" --write --why "session: check passed" > /dev/null; rc=$?
check "$rc" "0" "--write with an annotation, Open feedback typed in Other, and a typed response"
check "$("$B/keel" parse "$LT/notes.md" | python3 -c 'import json,sys; print(json.load(sys.stdin)["items"][0]["answer"])')" \
  "Taken in chat (Sam, 2026-10-16 07:57Z): B — Files

**Sam, 2026-10-16:** only the Mac's" "…the annotation goes under its item as Sam's note"
check "$(sed -n '/^## Open feedback/,$p' "$LT/notes.md" | grep -c '^\*\*Sam, 2026-10-16:\*\*')" "1" "…Open feedback: one note"
has "$LT/notes.md" "Next time, fewer options." "…holding Other's text"
has "$LT/notes.md" "Ship it, but tell Alex." "…and the typed response"

ldoc "$LT/four-w.md" 4; lplan "$LT/four-w.md"
ltrans "$LT/plan.json" "$LT/tr/proj/lsess.jsonl" '[{"answers": {"D1": "Files", "D2": "Files", "D3": "Files"}, "asked": "2026-10-16T09:10:00Z", "answered": "2026-10-16T09:12:00Z"}, {"answers": {"D4": "Voice Memos (Recommended)"}, "asked": "2026-10-16T09:13:00Z", "answered": "2026-10-16T09:14:30Z"}]'
lwrite "$LT/four-w.md" --write --why "Sam: --light" > "$LT/w4.out"; rc=$?
check "$rc" "0" "--write over two calls"
has "$LT/four-w.md" "asked 2026-10-16T09:10:00Z, answered 09:14:30Z (4 min 30 s); why: Sam: --light; review: light-ok" \
  "…asked at the first call, answered at the last, the review's verdict recorded"
has "$LT/w4.out" "open feedback: none on record" "…Open feedback unanswered: ask once in chat"
cp "$LT/three.orig" "$LT/redo.md"
lwrite "$LT/redo.md" --write --why x --review redesign > /dev/null 2>&1; rc=$?
check "$rc $(cmp -s "$LT/redo.md" "$LT/three.orig" && echo same)" "1 same" "--review redesign: not a light doc, nothing written (light D3)"
KEEL_TRANSCRIPTS="$LT/tr" CLAUDE_CODE_SESSION_ID= "$B/keel" light "$LT/redo.md" --write --why x --review light-ok > "$LT/ns.out" 2>&1; rc=$?
check "$rc" "1" "--write with no session id: refused"
has "$LT/ns.out" "CLAUDE_CODE_SESSION_ID is unset" "…naming the variable"
"$B/keel" light "$LT/redo.md" --write --review light-ok > /dev/null 2>&1; rc=$?
check "$rc" "1" "--write without --why: refused (the Gate line's why)"

# the /finish review's cases (2026-10-19)
ldoc "$LT/colon.md" 1; sedi 's/^  - A — Voice Memos — the app on the Mac$/  - A — Nag at 07:35 on school days — the extra one/' "$LT/colon.md"
lplan "$LT/colon.md"
check "$(lp 'print(d["calls"][0]["questions"][0]["options"][0]["label"])')" "Nag at 07:35 on school (Recommended)" \
  "a chip label is cut only at a word's end: 07:35 stays whole"
ldoc "$LT/both.md" 1 "A and B"
"$B/keel" light "$LT/both.md" --check > "$LT/c.out"; rc=$?
check "$rc" "1" "C3: a pick of two options is not one chip"
has "$LT/c.out" "is not one option" "…and says so"
ldoc "$LT/reop.md" 1; sedi 's/^  ➤ Answer:$/  ➤ Answer: B\
\
  > **Reopened.** B needs a probe first./' "$LT/reop.md"
"$B/keel" light "$LT/reop.md" --check > "$LT/c.out"; rc=$?
check "$rc" "1" "C3: a reopened item is not light (--write's read-back could never take it)"
has "$LT/c.out" "D1 is reopened" "…named"
ldoc "$LT/chk.md" 2; sedi '0,/^  ➤ Answer:$/s//  ➤ Answer:\
\
  > **Checked.** reviewer-high: the premise holds./' "$LT/chk.md"
"$B/keel" light "$LT/chk.md" --check > "$LT/c.out"
has "$LT/c.out" "light — 2 open D-items" "a session's own reply under an empty box keeps the item open"
cp "$LT/three.orig" "$LT/typed.md"; lplan "$LT/typed.md"
ltrans "$LT/plan.json" "$LT/tr/proj/lsess.jsonl" '[{"answers": {}, "extra": {"response": "Neither; split the doc in two first."}}]'
lwrite "$LT/typed.md" --write --why x > "$LT/typed.out"; rc=$?
check "$rc" "3" "a typed response and no taps: exit 3, nothing written"
has "$LT/typed.out" "Sam typed instead of choosing: Neither; split the doc in two first." "…and Sam's words are shown"
cp "$LT/three.orig" "$LT/retitle.md"; lplan "$LT/retitle.md"
ltrans "$LT/plan.json" "$LT/tr/proj/lsess.jsonl" '[{"answers": {"D1": "Files", "D2": "Files", "D3": "Files"}}]'
sedi 's/Which recorder 2\./Which recorder, two./' "$LT/retitle.md"
lwrite "$LT/retitle.md" --write --why x > /dev/null; rc=$?
check "$rc $(lans "$LT/retitle.md" | sed -n 2p | cut -c1-2)" "0 D2" "a title fixed after --plan: the answer is found by its D-id"
printf '# Quoted\n\n## Decisions\n\n- **D1 — Q?** Body.\n  - A — a\n  - B — b\n\n  ➤ Answer: A\n\n## Notes\n\nGate: light — an example line, quoted\n' > "$LT/quoted.md"
check "$("$B/keel" parse "$LT/quoted.md" | python3 -c 'import json,sys; print(json.load(sys.stdin)["gate"])')" "None" \
  "a Gate line below the first D-item is prose, not the doc's gate"

# in a repo: status reads answered, the review reviewed, and line_plan owes no form once all is answered
mkrepo lit "- physical: none"
owed_course() { python3 -c 'import sys
from importlib.machinery import SourceFileLoader
print(SourceFileLoader("k", sys.argv[1]).load_module().line_plan(sys.argv[2])["owed"]["course"])' "$B/keel" "$1"; }
check "$(owed_course "$ST/lit/docs/d.md")" "None" "line_plan: an open doc owes the form"
lplan "$ST/lit/docs/d.md"
ltrans "$LT/plan.json" "$LT/tr/proj/lsess.jsonl" '[{"answers": {"D1": "yes (Recommended)", "D2": "no", "D3": "yes (Recommended)", "feedback": "Not now"}}]'
lwrite "$ST/lit/docs/d.md" --write --why "Sam: --light" --review light-ok > /dev/null; rc=$?
check "$rc" "0" "--write in a repo"
sg "$ST/lit" add docs; scommit "$ST/lit" 2026-10-16T08:00:00Z -m "Docs: answers taken in chat" -m "Claude-Session: abc12345"
S=$(MEMO_NOW=2026-10-16T09:00:00Z status lit)
check "$(field "$S" verdict) $(rv "$S" word) $(rv "$S" taken)" "answered reviewed 0" \
  "status: answered; the review reads reviewed — the taps are Sam's, none taken (P1)"
check "$(owed_course "$ST/lit/docs/d.md")" "every D-item is answered in chat (Gate: light) — nothing left for a form" "line_plan: a doc answered in chat owes no form (L5)"
grep -v '^Gate: light' "$ST/lit/docs/d.md" > "$ST/lit/docs/e.md"
check "$(owed_course "$ST/lit/docs/e.md")" "None" \
  "…but an answered doc with no light gate still owes it (an old-shape doc's answers are pre-filled picks)"
unset TERM_PROGRAM
echo
if [ "$fails" = 0 ]; then echo "all green"; else echo "$fails failing"; exit 1; fi
