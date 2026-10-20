#!/usr/bin/env bash
# Tests for bin/docs-index — a scratch repo with a map, records, a chart and live files that name
# them. Nothing outside the scratch folder is read or written. The nested-set cases need keel
# (an optional peer, G19): without it they are skipped, said in one line; tests/atlas.sh holds
# the case with keel absent.
#   bash modules/atlas/tests/docs-index.sh
set -u
B="$(cd "$(dirname "$0")/../bin" && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fails=0
# BSD and GNU sed disagree on `-i ''` (GNU takes '' as the script and the real script as a file name); `-i.bak` and a rm work on both.
sedi() { local f="${!#}"; sed -i.bak "$@" && rm -f "$f.bak"; }
check() { if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3: expected [$2] got [$1]"; fails=$((fails+1)); fi; }
has()   { if grep -qF -- "$2" "$1"; then echo "  ok   $3"; else echo "  FAIL $3: missing [$2]"; sed 's/^/         | /' "$1" | head -20; fails=$((fails+1)); fi; }
hasnt() { if grep -qF -- "$2" "$1"; then echo "  FAIL $3: has [$2]"; fails=$((fails+1)); else echo "  ok   $3"; fi; }
DI() { python3 "$B/docs-index" "$@" --repo "$R"; }

R="$T/layer"; O="$T/other"
git init -q -b main "$R"; git -C "$R" config user.email t@t; git -C "$R" config user.name t
mkdir -p "$R/docs" "$R/bin" "$R/docs/handoff" "$R/sextant"
cat > "$R/docs/README.md" <<'EOF'
# docs — the map

mode: dry

| Topic | Chart | Records | Code |
| --- | --- | --- | --- |
| pickup | [pickup.md](pickup.md) | [pickup-a-2026-09-29.md](pickup-a-2026-09-29.md) · [pickup-b-2026-09-25.md](pickup-b-2026-09-25.md) | `bin/pickup` |
| memos | — | [memo-2026-09-20.md](memo-2026-09-20.md) | `bin/memo` |
EOF
printf '# Pickup\n\nWhat exists.\n\nRecords: [pickup-a-2026-09-29.md](pickup-a-2026-09-29.md) · [pickup-b-2026-09-25.md](pickup-b-2026-09-25.md)\n' > "$R/docs/pickup.md"
printf '# Pickup A\n\nBody of A, see [the chart](pickup.md), [B](pickup-b-2026-09-25.md) and [agents](../AGENTS.md).\n' > "$R/docs/pickup-a-2026-09-29.md"
printf '# Pickup B\n\nBody of B links [A](pickup-a-2026-09-29.md).\n' > "$R/docs/pickup-b-2026-09-25.md"
printf '# Memo\n\nBody.\n' > "$R/docs/memo-2026-09-20.md"
printf '#!/bin/sh\n# design: docs/pickup-a-2026-09-29.md (D2), not docs/pickup-a-2026-09-29.mdx\necho\n' > "$R/bin/pickup"
printf '# memo\n' > "$R/bin/memo"
printf '# Agents\n\nThe memo design: docs/memo-2026-09-20.md.\n' > "$R/AGENTS.md"
printf -- '- 2026-09-29 docs/pickup-a-2026-09-29.md landed\n' > "$R/log.md"
printf 'old entry names docs/pickup-a-2026-09-29.md\n' > "$R/sextant/2026-09-28.md"
printf 'brief: [A](../pickup-a-2026-09-29.md), kept: [here](./x.md)\n' > "$R/docs/handoff/2026-10-01-x.md"
git -C "$R" add -A; git -C "$R" commit -qm init

echo "mode and check"
check "$(DI mode)" dry "mode: the map's mode line"
check "$(python3 "$B/docs-index" mode --repo "$T")" none "  no map: none"
DI check > "$T/c1"; check $? 0 "check, not strict: exit 0"
has "$T/c1" "ok    3 records in 2 topics, 1 charts cross-linked, mode dry" "  a good map: ok, with its counts"
has "$T/c1" "3 record(s) without a banner" "  unbannered records: a note, not an error"
printf '# New\n\nx\n' > "$R/docs/new-2026-10-01.md"
DI check --strict > "$T/c2"; check $? 0 "a new record in docs/ without a row: --strict still passes"
has "$T/c2" "1 new record(s) not mapped yet (the next charts run maps them): new-2026-10-01.md" "  a note: the run maps it"
mkdir -p "$R/docs/record"; mv "$R/docs/new-2026-10-01.md" "$R/docs/record/"
DI check --strict > "$T/c2"; check $? 1 "an unmapped record in docs/record/: --strict exits 1"
has "$T/c2" "ERROR docs/record/new-2026-10-01.md has no row in docs/README.md" "  and names it"
rm -r "$R/docs/record"
sedi 's/ · \[pickup-b-2026-09-25.md\](pickup-b-2026-09-25.md)$//' "$R/docs/pickup.md"
DI check --strict > "$T/c3"; check $? 1 "a chart whose Records: lacks one of its row's: exit 1"
has "$T/c3" "Records: lacks pickup-b-2026-09-25.md" "  names the missing record"
git -C "$R" checkout -q docs/pickup.md

echo "banner"
DI banner pickup-a-2026-09-29.md pickup.md > /dev/null
check "$(sed -n 3p "$R/docs/pickup-a-2026-09-29.md")" "> **Record.** Current state: [docs/pickup.md](pickup.md). Below are the design and the decisions as they were made; an open item here is stale unless the chart says otherwise." "banner on line 3, pointing at its chart"
check "$(sed -n 4p "$R/docs/pickup-a-2026-09-29.md")" "" "  a blank line after it ends the quote"
check "$(DI banner pickup-a-2026-09-29.md pickup.md)" "unchanged docs/pickup-a-2026-09-29.md" "  again: unchanged (idempotent)"
check "$(git -C "$R" diff --numstat docs/pickup-a-2026-09-29.md | cut -f1,2)" "2	0" "  the diff is the banner and its blank line, nothing else"
DI banner memo-2026-09-20.md none > /dev/null
has "$R/docs/memo-2026-09-20.md" "> **Record.** No chart yet — the map [docs/README.md](README.md)" "no chart: the map variant"
DI banner pickup-b-2026-09-25.md none > /dev/null
DI check --strict > "$T/c4"; check $? 1 "a banner that disagrees with its row: exit 1"
has "$T/c4" "banner points at no chart, its row at docs/pickup.md" "  says which"
DI banner pickup-b-2026-09-25.md pickup.md > /dev/null
DI check --strict > /dev/null; check $? 0 "  rewritten in place: check passes"
git -C "$R" add -A; git -C "$R" commit -qm banners

printf '# Odd\ntext right under the title\n' > "$R/docs/odd-2026-09-21.md"
DI banner odd-2026-09-21.md none > /dev/null
check "$(sed -n 1p "$R/docs/odd-2026-09-21.md")|$(sed -n 3p "$R/docs/odd-2026-09-21.md" | cut -c1-13)|$(sed -n 5p "$R/docs/odd-2026-09-21.md")" "# Odd|> **Record.**|text right under the title" "a title with text under it: the banner goes below the title, never above"
rm "$R/docs/odd-2026-09-21.md"

echo "move"
git -C "$R" branch -q claude/laptop/2026-10-01-busy
git -C "$R" switch -q claude/laptop/2026-10-01-busy
echo "edit" >> "$R/docs/memo-2026-09-20.md"; git -C "$R" commit -qam busy
git -C "$R" switch -q main
check "$(DI skips | cut -f1)" "docs/memo-2026-09-20.md" "skips: a record an unmerged branch edits"
DI banner memo-2026-09-20.md none > "$T/b1"; check $? 1 "banner on a record a branch edits: refused (R2)"
has "$T/b1" "refused docs/memo-2026-09-20.md: skipped — claude/laptop/2026-10-01-busy edits it" "  and says which branch"
git -C "$R" branch -q claude/laptop/2026-10-01-old-raw claude/laptop/2026-10-01-busy
check "$(DI skips | cut -f2)" "claude/laptop/2026-10-01-busy" "  a -raw backup (/finish's) is not a holder"
printf 'new, not committed: [A](pickup-a-2026-09-29.md)\n' > "$R/docs/extra.md"
DI move pickup-a-2026-09-29.md pickup-b-2026-09-25.md memo-2026-09-20.md > "$T/m1"
has "$R/docs/extra.md" "[A](record/pickup-a-2026-09-29.md)" "an untracked file's link: re-pointed too (the first build's map was one)"
rm "$R/docs/extra.md"
has "$T/m1" "refused memo-2026-09-20.md: skipped — claude/laptop/2026-10-01-busy edits it" "a record in the skip set: refused, with the branch"
[ -f "$R/docs/record/pickup-a-2026-09-29.md" ] && [ ! -e "$R/docs/pickup-a-2026-09-29.md" ]; check $? 0 "the others: moved to docs/record/"
check "$(git -C "$R" diff --cached -M --name-status | grep -c '^R.*docs/pickup-a-2026-09-29.md.*docs/record/pickup-a-2026-09-29.md')" 1 "  as a git mv (a staged rename)"
has "$R/bin/pickup" "design: docs/record/pickup-a-2026-09-29.md (D2)" "a live file's docs/<name>: rewritten"
has "$R/bin/pickup" "not docs/pickup-a-2026-09-29.mdx" "  a longer name that only starts the same: untouched"
has "$R/docs/README.md" "[pickup-a-2026-09-29.md](record/pickup-a-2026-09-29.md)" "the map's link: re-pointed"
has "$R/docs/pickup.md" "(record/pickup-b-2026-09-25.md)" "the chart's Records: link: re-pointed"
has "$R/docs/handoff/2026-10-01-x.md" "[A](../record/pickup-a-2026-09-29.md)" "a relative link from another folder: re-pointed"
has "$R/docs/handoff/2026-10-01-x.md" "[here](./x.md)" "  an unrelated link: left exactly as written"
has "$R/docs/record/pickup-a-2026-09-29.md" "[the chart](../pickup.md), [B](pickup-b-2026-09-25.md) and [agents](../../AGENTS.md)" "the moved record's own links: re-based"
has "$R/docs/record/pickup-a-2026-09-29.md" "Current state: [docs/pickup.md](../pickup.md)" "  its banner too"
has "$R/log.md" "docs/pickup-a-2026-09-29.md landed" "log.md: never rewritten (a record of its day)"
has "$R/sextant/2026-09-28.md" "names docs/pickup-a-2026-09-29.md" "sextant/: never rewritten"
DI check --strict > "$T/c5"; check $? 0 "after the move: check passes"
has "$T/c5" "1 mapped record(s) still in docs/" "  the skipped one: a note"
git -C "$R" add -A; git -C "$R" commit -qm moved
printf 'landed late: docs/pickup-b-2026-09-25.md and [B](../docs/pickup-b-2026-09-25.md)\n' > "$R/bin/late"
DI check --strict > "$T/c6"; check $? 1 "a live file naming a moved record by its old path: exit 1"
has "$T/c6" "ERROR bin/late names a record by the path it left" "  names the file"
check "$(DI relink)" "rewrote bin/late" "relink fixes it"
has "$R/bin/late" "docs/record/pickup-b-2026-09-25.md and [B](../docs/record/pickup-b-2026-09-25.md)" "  the path and the link"
rm "$R/bin/late"
check "$(DI move pickup-a-2026-09-29.md; echo "rc=$?")" "refused pickup-a-2026-09-29.md: already in docs/record/
rc=1" "moving one already moved: refused, exit 1"

echo "move --section and --also"
git -C "$R" branch -q -D claude/laptop/2026-10-01-busy
git init -q -b main "$O"; git -C "$O" config user.email t@t; git -C "$O" config user.name t
printf 'see projects/layer/docs/memo-2026-09-20.md\nand (`layer` docs/memo-2026-09-20.md), (layer docs/memo-2026-09-20.md), layer `docs/memo-2026-09-20.md`\n' > "$O/index.md"
printf 'only prose: (`layer` docs/memo-2026-09-20.md)\n' > "$O/prose.md"
mkdir -p "$O/memory" "$O/.claude"; printf 'then: projects/layer/docs/memo-2026-09-20.md\n' > "$O/memory/n.md"
printf '{"in_place": ["memory/"]}\n' > "$O/.claude/workflow.json"; git -C "$O" add -A; git -C "$O" commit -qm o
DI move memo-2026-09-20.md --section --also "$O" > "$T/m2"
has "$T/m2" "refused memo-2026-09-20.md: named in AGENTS.md, other/index.md, other/prose.md — moves at /embark" "--section: a record a live file outside docs/ or another repo names is refused — a prose-only form included"
[ -f "$R/docs/memo-2026-09-20.md" ]; check $? 0 "  and stays where it is"
printf 'an earlier batch re-based: [m](../memo-2026-09-20.md)\n' >> "$R/docs/record/pickup-b-2026-09-25.md"
DI move memo-2026-09-20.md --also "$O" > /dev/null
has "$R/docs/record/pickup-b-2026-09-25.md" "[m](memo-2026-09-20.md)" "a moved record's ../ link to the record now beside it: set back"
has "$R/AGENTS.md" "docs/record/memo-2026-09-20.md" "the build's form: AGENTS.md rewritten"
has "$O/index.md" "layer/docs/record/memo-2026-09-20.md" "  and --also's repo"
has "$O/index.md" 'and (`layer` docs/record/memo-2026-09-20.md), (layer docs/record/memo-2026-09-20.md), layer `docs/record/memo-2026-09-20.md`' "  in its prose forms too"
has "$O/memory/n.md" "then: projects/layer/docs/memo-2026-09-20.md" "  but never that repo's records (in_place)"

echo "due"
git -C "$R" add -A; git -C "$R" commit -qm memo
echo "change" >> "$R/bin/memo"; git -C "$R" commit -qam "memo change"
check "$(DI due --since '1 hour ago' | grep '^pick')" "pick: memos, pickup" "due: the topics whose code changed, newest first"
check "$(DI due --since '1 hour ago' --max 1 | tail -1)" "skip: pickup (over the cap of 1)" "  over the cap: listed as skipped"
check "$(DI due --since '1 hour ago' --max 1 | grep '^pick')" "pick: memos" "  …and not picked again as the extra chartless slot"
check "$(DI due | head -1)" "since: 7 days ago" "since, before any charts run: 7 days"
git -C "$R" commit -q --allow-empty -m "Charts: 2026-09-27 — dry run"
check "$(DI due | head -1)" "since: 2026-09-27 00:00" "  after one: the run's own day from its subject, from midnight"
printf '# Late\n\nsee [b](../pickup-b-2026-09-25.md)\n' > "$R/docs/record/late-2026-09-30.md"
sedi 's#^| memos | — | #| memos | — | [late-2026-09-30.md](record/late-2026-09-30.md) · #' "$R/docs/README.md"
DI check --strict > "$T/c7"; check $? 1 "a moved record's link that resolves nowhere, its target in docs/record/: exit 1"
has "$T/c7" "docs/record/late-2026-09-30.md: link ../pickup-b-2026-09-25.md is broken" "  names the link"

echo "a nested set is one record row, and the Status line gives a review word (entry S5)"
if ! python3 "$B/../../regatta/bin/regatta" which keel >/dev/null 2>&1; then
  echo "  skip keel is not installed here — no set is known without it (G19; tests/atlas.sh covers that)"
else
S="$T/setrepo"; git init -q -b main "$S"; git -C "$S" config user.email t@t; git -C "$S" config user.name t
mkdir -p "$S/docs"
cat > "$S/docs/README.md" <<'EOF'
# docs — the map

mode: dry

| Topic | Chart | Records | Code |
| --- | --- | --- | --- |
| course | [course.md](course.md) | [course-2026-10-14.md](course-2026-10-14.md) | `bin/keel` |
EOF
printf '# Course\n\nWhat exists.\n\nRecords: [course-2026-10-14.md](course-2026-10-14.md) · [course-part-2026-10-14.md](course-part-2026-10-14.md)\n' > "$S/docs/course.md"
printf '# Course entry\n\nStatus: building — 2 of 2 decisions answered · action plan: 1 of 2 steps done · handed over 2026-10-14\n\n[part](course-part-2026-10-14.md)\n\n## Action plan\n\n- **S1 — a** · session `worker` · after: — · status: done 2026-10-14\n- **S2 — b** · session `worker` · after: S1 · status: not started\n' > "$S/docs/course-2026-10-14.md"
printf '# Course part\n\nStatus: building — 1 of 3 decisions answered · built by entry S1 (1 of 1 done) · handed over 2026-10-14\n' > "$S/docs/course-part-2026-10-14.md"
git -C "$S" add -A; git -C "$S" commit -qm init
python3 "$B/docs-index" check --repo "$S" > "$T/s1"
hasnt "$T/s1" "course-part-2026-10-14.md" "a component of a mapped entry: no note of its own, and the chart may name it"
has "$T/s1" "ok    1 records in 1 topics" "…the set counts as one record row"
python3 "$B/docs-index" reviews --write --repo "$S" > /dev/null
has "$S/docs/README.md" "[course-2026-10-14.md](course-2026-10-14.md) *reviewed*" "no banner tail: the map cell shows the Status line's word (every decision answered)"
sedi 's/2 of 2 decisions answered/1 of 2 decisions answered/' "$S/docs/course-2026-10-14.md"
python3 "$B/docs-index" reviews --write --repo "$S" > /dev/null
has "$S/docs/README.md" "(course-2026-10-14.md) *partial*" "…and follows the count"
sedi 's/^| course |.*$/| course | [course.md](course.md) | [course-2026-10-14.md](course-2026-10-14.md) · [course-part-2026-10-14.md](course-part-2026-10-14.md) | `bin\/keel` |/' "$S/docs/README.md"
sedi 's/^Records: .*$/Records: [course-2026-10-14.md](course-2026-10-14.md)/' "$S/docs/course.md"
python3 "$B/docs-index" check --strict --repo "$S" > "$T/s2"; check $? 1 "a component listed in the row itself still has to be in its chart (the old way is unchanged)"
has "$T/s2" "Records: lacks course-part-2026-10-14.md" "  and says so"
fi

echo "reads"
TD="$T/transcripts"; mkdir -p "$TD"
rd() { printf '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"%s","name":"Read","input":{"file_path":"/x/layer/docs/%s"}}]}}\n{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"%s","content":"%s"}]}}\n' "$1" "$2" "$1" "$3"; }
{ rd a record/x-2026-09-01.md 'l1\nl2\nl3'; rd b pickup.md 'l1'; } > "$TD/2026-09-28-aaaa1111.jsonl"
rd c y-2026-09-02.md 'l1\nl2' > "$TD/2026-09-29-bbbb2222.jsonl"
rd d y-2026-09-02.md 'l1' > "$TD/2026-09-20-cccc3333.jsonl"
DI reads --since 2026-09-27 --dir "$TD" > "$T/r1"
has "$T/r1" "record      2 reads        5 lines    2 sessions" "reads: records in the window, lines from the tool result"
has "$T/r1" "chart       1 reads        1 lines    1 sessions" "  a chart read"
has "$T/r1" "sessions reading a record but no map or chart: 1" "  the session that read only a record (R3's count)"

[ "$fails" = 0 ] && echo "all ok" || { echo "$fails FAILED"; exit 1; }
