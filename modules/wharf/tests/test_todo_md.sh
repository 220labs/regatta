#!/usr/bin/env bash
# Tests for bin/todo-md — TODO.md items by id: the lint, list, done, migrate, and the proof the ids and
# the union line were for: two branches that each append an item merge and rebase without a conflict.
# Scratch repos only.
#   bash modules/wharf/tests/test_todo_md.sh
set -u
B="$(cd "$(dirname "$0")/../bin" && pwd)"
TM="$B/todo-md"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fails=0
check() { if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3: expected [$2] got [$1]"; fails=$((fails+1)); fi; }
# git's identity in a file of the suite's own (a moved or bare runner has none; AGENTS.md's Traps)
printf '[user]\n\tname = t\n\temail = t@t\n[init]\n\tdefaultBranch = main\n' > "$T/gitconfig"
export GIT_CONFIG_GLOBAL="$T/gitconfig" GIT_CONFIG_NOSYSTEM=1
# A citation written in a fixture is spelled through $C (an id) or $N (a number), so this file holds none
# the repo's own lint would judge.
C="TODO.md" N="TODO"

# repo <dir>: a git repo with a well-formed TODO.md, the union line, one live and one record file.
repo() {
  local R="$1"
  git init -q "$R"
  cat > "$R/TODO.md" <<'EOF'
# TODO — what a fresh session must pick up

- [alpha] **Alpha** — first thing. Context: `docs/a.md`.
  Second line of alpha.
- [beta-2] **Beta** — second thing.

- [gamma] **Gamma** — third thing.
EOF
  printf 'TODO.md merge=union\nCHANGELOG.md merge=union\n' > "$R/.gitattributes"
  mkdir -p "$R/docs" "$R/src"
  printf 'see %s [alpha]\n' "$C" > "$R/src/code.py"
  printf 'see %s [beta-2] and %s [gone]\n' "$C" "$C" > "$R/docs/old-2026-10-01.md"
  git -C "$R" add -A && git -C "$R" commit -qm base
}

echo "== lint"
R="$T/ok"; repo "$R"
out=$("$TM" lint "$R"); check "$?" 0 "a clean repo passes"
check "$(echo "$out" | tail -1)" "todo-md: 3 items, 3 citations, 0 findings" "  and counts its items and citations"
printf '1. **Numbered** — x\n' >> "$R/TODO.md"
out=$("$TM" lint "$R"); check "$?" 1 "a numbered item fails"
echo "$out" | grep -q "TODO.md:8: a numbered item"; check $? 0 "  naming its line"
R="$T/bare"; repo "$R"; printf -- '- **No id** — x\n' >> "$R/TODO.md"
"$TM" lint "$R" | grep -q "an item without an id"; check $? 0 "a bullet without an id fails"
R="$T/dup"; repo "$R"; printf -- '- [alpha] **Alpha again**\n' >> "$R/TODO.md"
"$TM" lint "$R" | grep -q "id \[alpha\] is a duplicate"; check $? 0 "a duplicate id fails"
R="$T/long"; repo "$R"; printf -- '- [abcdefghij-abcdefghij-abcde] **Long**\n' >> "$R/TODO.md"
"$TM" lint "$R" | grep -q "longer than 24"; check $? 0 "an id over 24 characters fails"
R="$T/noattr"; repo "$R"; git -C "$R" rm -q .gitattributes
"$TM" lint "$R" | grep -q "^  FAIL .gitattributes: no \`TODO.md merge=union\` line"; check $? 0 "no union line fails"
R="$T/fence"; repo "$R"; printf '\n```\n1. not an item\n- neither\n```\n' >> "$R/TODO.md"
"$TM" lint "$R" >/dev/null; check "$?" 0 "list markers inside a fenced block are no items"

echo "== citations"
R="$T/cite"; repo "$R"
printf 'see %s [missing]\n' "$C" >> "$R/src/code.py"
out=$("$TM" lint "$R"); check "$?" 1 "a live file citing an id TODO.md lacks fails"
echo "$out" | grep -q "src/code.py:2: TODO.md \[missing\] names no item"; check $? 0 "  naming the file and line"
echo "$out" | grep -q "docs/old"; check $? 1 "  a record (docs/) may cite an item since done"
R="$T/cl"; repo "$R"; mkdir -p "$R/m"; printf -- '- %s [gone] was fixed\n' "$C" > "$R/m/CHANGELOG.md"
"$TM" lint "$R" >/dev/null; check "$?" 0 "  and so may a CHANGELOG"
printf 'TODO.md merge=union\n' > "$R/.gitattributes"
"$TM" lint "$R" | grep -q "no \`CHANGELOG.md merge=union\` line (m/CHANGELOG.md"; check $? 0 "a CHANGELOG with no union line fails, named"
"$TM" migrate "$R" >/dev/null; check "$?" 0 "  and migrate adds the line"
check "$(tail -1 "$R/.gitattributes")|$("$TM" lint "$R" >/dev/null; echo $?)" "CHANGELOG.md merge=union|0" "  after which the lint passes"
for form in "$N item 6" "$N.md item 16" "the $N.md's items 10 and 12" "\`$N.md\` item 14" "$N.md: item 29" \
            "$N.md, item 5" "$N.md 36" "\`$N.md\` #6" "$N.md
  item 3"; do
  R="$T/num$RANDOM"; repo "$R"; printf 'x (%s)\n' "$form" > "$R/src/new.md"
  "$TM" lint "$R" | grep -q "a numbered citation"; check $? 0 "a numbered citation in a live file fails: $(echo "$form" | tr '\n' ' ')"
done
for form in "# $N: 3 retries before giving up" "$N 2 things" "$C, 10 is the cap" "# $N #42: wait for upstream" "x ($N 7)" "# $N
1. a list"; do
  R="$T/notnum$RANDOM"; repo "$R"; printf '%s\n' "$form" > "$R/src/n.py"
  "$TM" lint "$R" >/dev/null; check "$?" 0 "no citation: $(echo "$form" | tr '\n' ' ')"
done
R="$T/wrap"; repo "$R"; printf 'see %s\n  [missing] (b)\n' "$C" > "$R/src/w.md"
"$TM" lint "$R" | grep -q "src/w.md:1: TODO.md \[missing\]"; check $? 0 "a citation a reflow wrapped is judged"
R="$T/link"; repo "$R"; printf 'see %s [the list](TODO.md)\n' "$C" > "$R/src/l.md"
"$TM" lint "$R" >/dev/null; check "$?" 0 "TODO.md [text](link) is a link, not a citation"
R="$T/digits"; repo "$R"; printf -- '- [404] **Fix the 404 page**\n' >> "$R/TODO.md"
"$TM" lint "$R" | grep -q "TODO.md:8: an item without an id"; check $? 0 "an all-digit id is no id (done would refuse it as a number)"
R="$T/box"; repo "$R"; printf -- '- [x] **A checked box**\n' >> "$R/TODO.md"
"$TM" lint "$R" | grep -q "TODO.md:8: an item without an id"; check $? 0 "a task list's [x] is a checkbox, no id"
R="$T/bad"; repo "$R"; printf 'see %s [12] and %s [Alpha]\n' "$C" "$C" > "$R/src/bad.py"
out=$("$TM" lint "$R"); check "$(echo "$out" | grep -c 'is no id')" "2" "a bracket that is no id and no <placeholder> fails"
R="$T/tick"; repo "$R"; printf 'see `%s` [missing]\n' "$C" > "$R/src/t.md"
"$TM" lint "$R" | grep -q "names no item"; check $? 0 "a backticked TODO.md citation is judged"
R="$T/brief"; repo "$R"; mkdir -p "$R/docs/handoff"; printf 'Start here: %s [gone]\n' "$C" > "$R/docs/handoff/b.md"
"$TM" lint "$R" | grep -q "docs/handoff/b.md:1: TODO.md \[gone\] names no item"; check $? 0 "a handoff brief is live: its citation of a done item fails"
R="$T/foreign"; repo "$R"; printf 'see [%s 2](../other/TODO.md) and [%s 3](/x/elsewhere/TODO.md#L4)\n' "$N" "$N" > "$R/src/f.md"
"$TM" lint "$R" >/dev/null; check "$?" 0 "another repo's numbered citation, as a link, is not this lint's"
R="$T/wt-main/proj"; mkdir -p "$T/wt-main"; repo "$R"; git -C "$R" worktree add -q "$T/wt-main/proj-wt" -b side 2>/dev/null
printf 'see [%s item 1](/mnt/other-mac/proj/TODO.md)\n' "$N" > "$T/wt-main/proj-wt/src/abs.md"
"$TM" lint "$T/wt-main/proj-wt" | grep -q "src/abs.md:1: a numbered citation"; check $? 0 "from a worktree, a link to the repo's own list by another Mac's path is still the repo's"
R="$T/other-target"; repo "$R"; printf 'see [%s item 2](docs/plan.md)\n' "$N" > "$R/src/o.md"
"$TM" lint "$R" | grep -q "src/o.md:1: a numbered citation"; check $? 0 "a numbered citation linking to a file that is no TODO.md is judged"
R="$T/past"; repo "$R"; printf "see [other's %s item 8 (ssh runs)](../other/TODO.md)\n" "$N" > "$R/src/p.md"
"$TM" lint "$R" >/dev/null; check "$?" 0 "another repo's linked citation with words past the number is not this lint's"
R="$T/paths"; repo "$R"
printf 'other: `other/TODO.md` item 3, /elsewhere/x/%s [far], %s [<id>], TODO 2026-10-31, TODO.md:46\n' "$C" "$C" > "$R/src/b.md"
"$TM" lint "$R" >/dev/null; check "$?" 0 "another repo's item (a path), a placeholder, a date and a line ref pass"
R="$T/head"; repo "$R"; printf '# %s\n\n1. a list under a heading\n' "$N" > "$R/src/h.md"
"$TM" lint "$R" >/dev/null; check "$?" 0 "a heading over a numbered list is no citation (a bare number stays on its line)"
R="$T/notodo"; repo "$R"; git -C "$R" rm -q TODO.md
out=$("$TM" lint "$R"); check "$?" 0 "no TODO.md: an id citation is judged for its form only"
echo "$out" | grep -q "no TODO.md"; check $? 0 "  and it says so"

echo "== list"
R="$T/list"; repo "$R"
check "$("$TM" list "$R" | tr '\t' '|' | tr '\n' ' ')" "alpha|Alpha beta-2|Beta gamma|Gamma " "one line per item: id, tab, title"

echo "== done"
R="$T/done"; repo "$R"
out=$("$TM" done alpha "$R"); check "$?" 0 "done <id> deletes the item"
check "$(sed -n 3p "$R/TODO.md")" "- [beta-2] **Beta** — second thing." "  its continuation line with it"
echo "$out" | grep -q "still cited (live, the lint fails it until it changes): src/code.py:1"; check $? 0 "  and names the live file that still cites it"
echo "$out" | grep -q "docs/old"; check $? 1 "  not the record"
"$TM" done gamma "$R" >/dev/null
check "$(tail -c 200 "$R/TODO.md" | tail -2 | tr '\n' '|')" "|- [beta-2] **Beta** — second thing.|" "the last item: no trailing blank line left behind"
"$TM" done beta-2 "$R" >/dev/null
check "$(cat "$R/TODO.md")" "# TODO — what a fresh session must pick up" "the list emptied: its heading alone"
R="$T/mid"; repo "$R"; "$TM" done beta-2 "$R" >/dev/null
check "$(sed -n 4,6p "$R/TODO.md" | tr '\n' '|')" "  Second line of alpha.||- [gamma] **Gamma** — third thing.|" "an item between two: one blank line stays, never two"
R="$T/donewrap"; repo "$R"; printf 'see %s\n  [alpha] here\n' "$C" > "$R/src/code.py"
"$TM" done alpha "$R" | grep -q "still cited (live, the lint fails it until it changes): src/code.py:1"; check $? 0 "done names a wrapped citation too"
R="$T/note"; repo "$R"; printf '\nDeferred items live in docs/x.md.\n' >> "$R/TODO.md"
"$TM" done gamma "$R" >/dev/null
check "$(tail -1 "$R/TODO.md")" "Deferred items live in docs/x.md." "a closing paragraph at column 0 is the file's: done keeps it"
check "$("$TM" list "$R" | cut -f1 | tr '\n' ' ')" "alpha beta-2 " "  and it is no item"
R="$T/donenum"; repo "$R"
out=$("$TM" done 2 "$R" 2>&1); check "$?" 2 "a number is refused"
echo "$out" | grep -q "ids since 2026-10-31, not numbers: \`todo-md list"; check $? 0 "  with a pointer to list"
check "$(git -C "$R" status --short)" "" "  and nothing written"
"$TM" done nope "$R" 2>/dev/null; check "$?" 1 "an unknown id: exit 1"
R="$T/byte"; repo "$R"; printf '\377\n' >> "$R/TODO.md"; cp "$R/TODO.md" "$T/byte.kept"
"$TM" lint "$R" >/dev/null 2>&1; check "$?" 1 "an unreadable TODO.md stops the lint"
"$TM" migrate "$R" >/dev/null 2>&1; check "$?" 1 "  and migrate"
cmp -s "$R/TODO.md" "$T/byte.kept"; check $? 0 "  which writes nothing back (never an emptied file)"

echo "== migrate"
R="$T/mig"; git init -q "$R"
cat > "$R/TODO.md" <<'EOF'
# TODO

1. **keel: the B4 review's follow-ups** — x
   continued.
2. **Fix the dimmer floor (2026-10-01)** — y
- **orca-launcher S5 review leftovers** — z
10. **Ten** — w
    deeper.
EOF
mkdir -p "$R/src"
printf 'a %s item 1, %s.md items 1 and 2, [%s 2](/on/another/mac/mig/TODO.md#L4), `%s.md`: item 10, `other/TODO.md` item 1, %s item 7\n' "$N" "$N" "$N" "$N" "$N" > "$R/src/d.md"
git -C "$R" add -A && git -C "$R" commit -qm base
out=$("$TM" migrate "$R" --dry-run); check "$?" 0 "migrate --dry-run"
check "$(git -C "$R" status --short)" "" "  writes nothing"
echo "$out" | grep -q "#1 -> \[keel-b4\]"; check $? 0 "  an auto id from the title: keel-b4"
echo "$out" | grep -q "#2 -> \[fix-dimmer-floor\]"; check $? 0 "  fix-dimmer-floor"
echo "$out" | grep -qF "(unnumbered, --ids key orca-launcher-s5) -> [orca-launcher-s5]"; check $? 0 "  orca-launcher-s5"
echo "$out" | grep -qF "  cite src/d.md:1: …a $N item 1 -> $C [keel-b4]"; check $? 0 "  each citation's rewrite, with the words before it"
echo "$out" | grep -q "left (a number with no item, or another repo's: fix by hand): src/d.md:1: $N item 7"; check $? 0 "  a number with no item is left, and named"
printf '{"2": "dimmer"}\n' > "$T/ids.json"
"$TM" migrate "$R" --ids "$T/ids.json" >/dev/null; check "$?" 0 "migrate with --ids"
check "$(sed -n 3,9p "$R/TODO.md" | tr '\n' '|')" "- [keel-b4] **keel: the B4 review's follow-ups** — x|   continued.|- [dimmer] **Fix the dimmer floor (2026-10-01)** — y|- [orca-launcher-s5] **orca-launcher S5 review leftovers** — z|- [ten] **Ten** — w|    deeper.|" \
  "  heads to ids, continuation lines kept as they were (an old branch's edit of one stays one-sided)"
check "$(cat "$R/src/d.md")" "a $C [keel-b4], $C [keel-b4] and $C [dimmer], $C [dimmer], $C [ten], \`other/TODO.md\` item 1, $N item 7" \
  "  citations rewritten: one, a pair, a link to a line, a backticked one; another repo's left"
check "$(cat "$R/.gitattributes")" "TODO.md merge=union" "  the union line written"
out=$("$TM" lint "$R"); check "$?" 1 "  the lint then fails only the number with no item"
check "$(echo "$out" | grep -c FAIL)" "1" "  (one finding)"
R="$T/res"; git init -q "$R"; printf '# T\n\n1. **keel: the B4 review** — x\n2. **Other** — y\n' > "$R/TODO.md"
printf 'the list: [%s](TODO.md), [%s](TODO.md#L3)\n' "$C" "$C" > "$R/r.md"
printf '{"2": "keel-b4"}\n' > "$T/res.json"
out=$("$TM" migrate "$R" --ids "$T/res.json"); check "$?" 0 "an --ids pick an earlier item's auto id would take"
check "$("$TM" list "$R" | cut -f1 | tr '\n' ' ')" "keel-b4-2 keel-b4 " "  is reserved first: the owner's pick wins"
check "$(cat "$R/r.md")" "the list: [$C](TODO.md), $C" "a plain link to the file stays; one to a line of it goes"
echo "$out" | grep -qF "  link r.md:1: [$C](TODO.md#L3) -> $C"; check $? 0 "  and is named"
R="$T/keys"; git init -q "$R"; printf '# T\n\n- **keel B4** — x\n- **keel B4 again** — y\n1. **404** page\n' > "$R/TODO.md"
out=$("$TM" migrate "$R" --dry-run)
echo "$out" | grep -qF "(unnumbered, --ids key keel-b4-again)"; check $? 0 "an unnumbered item's --ids key is printed"
echo "$out" | grep -qF "#1 -> [item-404]"; check $? 0 "a title of digits alone gets item-<n>, never an all-digit id"
printf '{"keel-b4": "first", "keel-b4-again": "second"}\n' > "$T/keys.json"
"$TM" migrate "$R" --ids "$T/keys.json" >/dev/null
check "$("$TM" list "$R" | cut -f1 | tr '\n' ' ')" "first second item-404 " "  and the keys a dry run printed still pick"
R="$T/fl"; git init -q "$R"; printf '# T\n\n1. **One** — x\n2. **Two** — y\n' > "$R/TODO.md"; mkdir -p "$R/src"
printf 'mine [%s 2](../TODO.md), theirs [%s 2](../../other/TODO.md), [%s, 2026 list](../TODO.md)\n' "$N" "$N" "$C" > "$R/src/x.md"
"$TM" migrate "$R" >/dev/null
check "$(cat "$R/src/x.md")" "mine $C [two], theirs [$N 2](../../other/TODO.md), [$C, 2026 list](../TODO.md)" \
  "migrate unwraps only this repo's numbered link; another repo's, and a plain one with a year, stay"
R="$T/r3"; git init -q "$R"; printf '# T\n\n1. **One** — x\n2. **Two** — y\n' > "$R/TODO.md"; mkdir -p "$R/src"
printf 'see [%s 2](../TODO.md) for details; %s item 1, 10 minutes left; [%s item 1 (x)](../../other/TODO.md)\n' "$N" "$N" "$N" > "$R/src/y.md"
out=$("$TM" migrate "$R")
check "$(cat "$R/src/y.md")" "see $C [two] for details; $C [one], 10 minutes left; [$N item 1 (x)](../../other/TODO.md)" \
  "a linked number is rewritten where it stands, a list takes no stray number, another repo's link stays"
echo "$out" | grep -qF "(another repo's, by its link: check by hand)"; check $? 0 "  and the other repo's is named as left"
R="$T/r4"; git init -q "$R"; printf '# T\n\n1. **One** — x\n2. **Two** — y\n4. **Four** — z\n' > "$R/TODO.md"; mkdir -p "$R/src"
printf '%s items 1, 2 and 4 are obsolete. %s items 1 and 2 are done. %s item 1a; %s items 1-2.\n[%s 9](../TODO.md#L3) [%s 1](https://github.com/o/r4/blob/claude/h/x/TODO.md?plain=1)\n' "$N" "$N" "$C" "$C" "$N" "$N" > "$R/src/z.md"
out=$("$TM" migrate "$R")
check "$(head -1 "$R/src/z.md")" "$C [one], $C [two] and $C [four] are obsolete. $C [one] and $C [two] are done. $C item 1a; $C items 1-2." \
  "a list after and keeps its last number; item 1a is no item 1; a range is left whole"
check "$(tail -1 "$R/src/z.md")" "[$N 9](../TODO.md#L3) $C [one]" "  a number with no item keeps its link; this repo's blob on a slashed branch, with a query, is its own"
check "$(echo "$out" | grep -c 'src/z.md:2: TODO 9')" "1" "  a link's number left is named once"
"$TM" lint "$R" | grep -q "a numbered citation ($C items 1-2)"; check $? 0 "the lint fails the range"
"$TM" migrate "$R" >/dev/null; check "$?" 1 "a migrated repo with a file that mentions TODO: nothing to act on, exit 1"
mkdir -p "$R/sub"; ( cd "$R/sub" && "$TM" list . | head -1 | cut -f1 ) > "$T/sub.out"
check "$(cat "$T/sub.out")" "one" "run from a subfolder, the tool reads the checkout's TODO.md"
R="$T/nest"; repo "$R"; mkdir -p "$R/tpl"; printf '# T\n\n- [inner] **Inner**\n' > "$R/tpl/TODO.md"
check "$("$TM" list "$R/tpl" | cut -f1)" "inner" "a folder with its own TODO.md is that list's repo, not the checkout's"
R="$T/nl"; git init -q "$R"; printf '# T\n\n1. **One** — x\n2. **Two** — y\n3. **Three** — z\n4. **Four** — w\n' > "$R/TODO.md"
printf 'Steps, after %s item 3,\n4. Run it\n' "$N" > "$R/a.md"; "$TM" migrate "$R" >/dev/null
check "$(tr '\n' '|' < "$R/a.md")" "Steps, after $C [three],|4. Run it|" "a list never crosses a line break into the next line's list marker"
R="$T/glob"; repo "$R"; printf '*.md merge=union\n' > "$R/.gitattributes"
"$TM" lint "$R" >/dev/null; check "$?" 0 "union is git's answer: *.md merge=union counts"
printf 'TODO.md merge=union\nTODO.md -merge\n' > "$R/.gitattributes"
"$TM" lint "$R" | grep -q "no \`TODO.md merge=union\`"; check $? 0 "  and a later -merge undoes it"
R="$T/lnk"; repo "$R"; printf '*.bin binary\n' > "$T/shared-attrs"; git -C "$R" rm -q .gitattributes; ln -s "$T/shared-attrs" "$R/.gitattributes"
"$TM" migrate "$R" >/dev/null 2>&1; check "$?" 1 "a linked .gitattributes is refused, never rewritten"
check "$(cat "$T/shared-attrs")" "*.bin binary" "  and its target is untouched"
R="$T/fork"; repo "$R"; git -C "$R" remote add origin https://github.com/me/fork.git
printf "see [%s item 1](https://github.com/other/fork/blob/main/TODO.md) and [%s item 2](https://github.com/me/fork/blob/claude/h/d-x/TODO.md)\n" "$N" "$N" > "$R/src/f.md"
check "$("$TM" lint "$R" | grep -c 'numbered citation')" "1" "a fork's list is another repo's; this repo's on a slashed branch is its own"
R="$T/attr"; repo "$R"; git -C "$R" rm -q .gitattributes
"$TM" migrate "$R" >/dev/null; check "$?" 0 "migrate that writes only the union line exits 0"
check "$(cat "$R/.gitattributes")" "TODO.md merge=union" "  and wrote it"
printf '{"1": "Bad Id"}\n' > "$T/bad.json"; R="$T/mig2"; git init -q "$R"; printf '1. **x**\n' > "$R/TODO.md"
"$TM" migrate "$R" --ids "$T/bad.json" >/dev/null 2>&1; check "$?" 2 "an id from --ids that breaks the shape is refused"

echo "== two branches that each add an item"
R="$T/merge"; repo "$R"; B0=$(git -C "$R" rev-parse main)
git -C "$R" checkout -qb one; printf -- '- [delta] **Delta** — from branch one.\n' >> "$R/TODO.md"; git -C "$R" commit -qam "add delta"
git -C "$R" checkout -q main; git -C "$R" checkout -qb two; printf -- '- [epsilon] **Epsilon** — from branch two.\n' >> "$R/TODO.md"; git -C "$R" commit -qam "add epsilon"
git -C "$R" checkout -q main
git -C "$R" merge -q --no-edit one >/dev/null 2>&1; check "$?" 0 "the first lands"
git -C "$R" merge -q --no-edit two >/dev/null 2>&1; check "$?" 0 "the second merges without a conflict"
check "$("$TM" list "$R" | cut -f1 | tr '\n' ' ')" "alpha beta-2 gamma delta epsilon " "  both items are in"
"$TM" lint "$R" >/dev/null; check "$?" 0 "  and the lint passes"
git -C "$R" checkout -q -b three "$B0"
printf -- '- [zeta] **Zeta** — from branch three.\n' >> "$R/TODO.md"; git -C "$R" commit -qam "add zeta"
git -C "$R" rebase -q main >/dev/null 2>&1; check "$?" 0 "a third, rebased onto that main as /finish does, rebases clean"
check "$("$TM" list "$R" | cut -f1 | tr '\n' ' ')" "alpha beta-2 gamma delta epsilon zeta " "  all six in"
R="$T/nounion"; repo "$R"; git -C "$R" rm -q .gitattributes; git -C "$R" commit -qm "no union"
git -C "$R" checkout -qb one; printf -- '- [delta] **Delta**\n' >> "$R/TODO.md"; git -C "$R" commit -qam d
git -C "$R" checkout -q main; printf -- '- [epsilon] **Epsilon**\n' >> "$R/TODO.md"; git -C "$R" commit -qam e
git -C "$R" merge -q --no-edit one >/dev/null 2>&1; check "$?" 1 "without the union line the same two appends conflict (why the line)"
git -C "$R" merge --abort 2>/dev/null
R="$T/both"; repo "$R"
git -C "$R" checkout -qb one; sed -i.bak 's/^- \[alpha\] \*\*Alpha\*\* — first thing./- [alpha] **Alpha** — first thing, edited on one./' "$R/TODO.md" && rm -f "$R/TODO.md.bak"; git -C "$R" commit -qam e1
git -C "$R" checkout -q main; sed -i.bak 's/^- \[alpha\] \*\*Alpha\*\* — first thing./- [alpha] **Alpha** — first thing, edited on main./' "$R/TODO.md" && rm -f "$R/TODO.md.bak"; git -C "$R" commit -qam e2
git -C "$R" merge -q --no-edit one >/dev/null 2>&1
"$TM" lint "$R" | grep -q "id \[alpha\] is a duplicate"; check $? 0 "two edits of one item under union: the lint fails the duplicate"

R="$T/back"; repo "$R"; B0=$(git -C "$R" rev-parse main)
"$TM" done gamma "$R" >/dev/null; git -C "$R" commit -qam "done gamma"
git -C "$R" checkout -qb late "$B0"; printf -- '- [delta] **Delta**\n' >> "$R/TODO.md"; git -C "$R" commit -qam "add delta"
git -C "$R" rebase -q main >/dev/null 2>&1; check "$?" 0 "a branch appending beside an item main did rebases clean"
check "$("$TM" list "$R" | cut -f1 | tr '\n' ' ')" "alpha beta-2 gamma delta " "  and union brings the done item back"
"$TM" lint "$R" >/dev/null; check "$?" 0 "  which the plain lint cannot see"
out=$("$TM" lint "$R" --base main); check "$?" 1 "  lint --base main fails it"
echo "$out" | grep -q "\[gamma\] was done on main and is back"; check $? 0 "  naming the item"
GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=color.diff GIT_CONFIG_VALUE_0=always "$TM" lint "$R" --base main >/dev/null; check "$?" 1 "  a colour diff setting does not switch the guard off"
out=$("$TM" lint "$R" --base no-such-ref 2>&1 >/dev/null); check "$?" 0 "  a ref git cannot read judges nothing"
check "$out" "todo-md: --base no-such-ref: git cannot read it here; done items not judged" "  and says so"
"$TM" lint "$R" --base --x >/dev/null 2>&1; check "$?" 2 "  a flag given as the ref is refused"
R="$T/behind"; repo "$R"; B0=$(git -C "$R" rev-parse main)
"$TM" done gamma "$R" >/dev/null; git -C "$R" commit -qam "done gamma"
git -C "$R" checkout -qb stale "$B0"; echo x > "$R/f.txt"; git -C "$R" add f.txt; git -C "$R" commit -qm f
"$TM" lint "$R" --base main >/dev/null; check "$?" 0 "a branch behind a main that did an item is not judged as bringing it back"
git -C "$R" merge -q --no-edit main >/dev/null 2>&1
check "$("$TM" list "$R" | cut -f1 | tr '\n' ' ')|$("$TM" lint "$R" --base main >/dev/null; echo $?)" "alpha beta-2 |0" "  and once it takes main the item is gone and the lint passes"

echo "== the landing review (2026-11-02)"
R="$T/glue"; git init -q "$R"
printf '# TODO\n\n1. **Arm the yard** — x\n' > "$R/TODO.md"
printf 'see %s item 1(a) and %s item 1 (c)\n' "$N" "$N" > "$R/notes.md"
git -C "$R" add -A && git -C "$R" commit -qm base
"$TM" migrate "$R" >/dev/null
check "$(cat "$R/notes.md")" "see $C [arm-yard] (a) and $C [arm-yard] (c)" \
  "a number glued to (a) gets a space, never a Markdown link [id](a)"
check "$("$TM" lint "$R" | tail -1)" "todo-md: 1 items, 2 citations, 0 findings" "  and the lint counts both citations"
"$TM" lint "$T/no-such-folder" >/dev/null 2>&1; check "$?" 2 "lint of a folder that does not exist: exit 2, never a pass"
R="$T/sub"; repo "$R"; mkdir -p "$R/tpl"
printf '# TODO\n\n- [check] **Check** — x\n' > "$R/tpl/TODO.md"; echo 'TODO.md merge=union' > "$R/tpl/.gitattributes"
git -C "$R" add -A && git -C "$R" commit -qm tpl; echo x > "$R/f.txt"; git -C "$R" add f.txt; git -C "$R" commit -qm f
"$TM" lint "$R/tpl" --base HEAD~1 >/dev/null; check "$?" 0 "--base from a folder with its own list reads that list at the base, not the root's"

echo "== the follow-ups (todo-driver, 2026-11-02)"
R="$T/and3"; git init -q "$R"
printf '# TODO\n\n1. **One** — a\n2. **Two** — b\n3. **Three** — c\n' > "$R/TODO.md"
printf '%s 1, 2 and 3 are done.\n' "$N" > "$R/notes.md"; git -C "$R" add -A && git -C "$R" commit -qm base
"$TM" migrate "$R" >/dev/null
check "$(cat "$R/notes.md")" "$C [one], $C [two] and $C [three] are done." "a list ending on 'and N' keeps its last number"
R="$T/rfc"; repo "$R"; printf '# %s: item 2 of the RFC is unhandled\n' "$N" > "$R/src/x.py"
"$TM" lint "$R" >/dev/null; check "$?" 0 "a code comment's bare TODO: then 'item 2' is no citation"
R="$T/fenced"; repo "$R"
printf '\nThe shape:\n\n```\n- [example-id] **What** — where\n```\n' >> "$R/TODO.md"; git -C "$R" commit -qam fence
git -C "$R" checkout -qb next; printf -- '- [example-id] **Now real** — x\n' >> "$R/TODO.md"; git -C "$R" commit -qam real
"$TM" lint "$R" --base main >/dev/null; check "$?" 0 "an id shown in a fenced example was never an item: not done, not back"
R="$T/ids"; repo "$R"; "$TM" done gamma "$R" >/dev/null; git -C "$R" commit -qam "done gamma"
"$TM" check-id gamma "$R" >/dev/null; check "$?" 1 "check-id: a done id is never free"
"$TM" check-id alpha "$R" >/dev/null; check "$?" 1 "  nor one in use"
"$TM" check-id fresh-one "$R" >/dev/null; check "$?" 0 "  a new one is"
"$TM" check-id Bad_Id "$R" >/dev/null; check "$?" 1 "  and a bad shape is refused"
printf '\n```\n- [gamma] **an example**\n```\n' >> "$R/TODO.md"; git -C "$R" commit -qam "example borrows gamma"
"$TM" check-id gamma "$R" >/dev/null; check "$?" 1 "  a done id a fenced example later borrows is still used"
R="$T/brief"; repo "$R"; mkdir -p "$R/docs/handoff"; printf 'Do %s [beta-2].\n' "$C" > "$R/docs/handoff/b.md"
git -C "$R" add -A && git -C "$R" commit -qm brief; git -C "$R" checkout -qb build
"$TM" done beta-2 "$R" >/dev/null; git -C "$R" commit -qam "done beta-2"
"$TM" lint "$R" --base main >/dev/null; check "$?" 0 "a handoff brief may cite the item its own branch did"
printf 'and %s [alpha-gone]\n' "$C" >> "$R/docs/handoff/b.md"
"$TM" lint "$R" --base main | grep -q "alpha-gone\] names no item"; check $? 0 "  but not an id nobody had"
R="$T/tpl"; repo "$R"; mkdir -p "$R/modules/w/templates" "$R/modules/w/skills/s"
printf 'see %s [check]\n' "$C" > "$R/modules/w/templates/AGENTS.md"; printf 'see %s [check]\n' "$C" > "$R/modules/w/skills/s/SKILL.md"
"$TM" lint "$R" | grep -c 'names no item' | tr -d ' ' > "$T/tpl-n"
check "$(cat "$T/tpl-n")" "1" "a module's templates cite other repos' items, never judged here; its skills are this repo's own, judged"
"$TM" lint "$R" | grep -q 'modules/w/skills/s/SKILL.md:1:'; check $? 0 "  the skill is the one named"

echo "== records keep their numbers (the rollout, 2026-11-02)"
R="$T/rec"; git init -q "$R"; printf '# TODO\n\n1. **One** — a\n2. **Two** — b\n' > "$R/TODO.md"; mkdir -p "$R/docs" "$R/sextant" "$R/src"
printf 'then %s item 2 meant another item\n' "$N" > "$R/docs/old-2026-09-01.md"
printf 'week: %s 1 decided\n' "$N" > "$R/sextant/2026-09-28.md"; printf '%s 2 earlier\n' "$N" > "$R/log.md"
printf 'live: %s item 2\n' "$N" > "$R/src/live.md"; git -C "$R" add -A && git -C "$R" commit -qm base
"$TM" migrate "$R" >/dev/null
check "$(cat "$R/docs/old-2026-09-01.md")|$(cat "$R/sextant/2026-09-28.md")|$(cat "$R/log.md")" \
  "then $N item 2 meant another item|week: $N 1 decided|$N 2 earlier" "migrate leaves a record's numbers as written: docs/, a dated file, log.md"
check "$(cat "$R/src/live.md")" "live: $C [two]" "  and rewrites a live file's"
"$TM" lint "$R" >/dev/null; check "$?" 0 "  the lint passes the records' numbers: they name the list as it stood that day"

echo "== usage"
"$TM" frob >/dev/null 2>&1; check "$?" 2 "an unknown verb: exit 2"

[ "$fails" -eq 0 ] && echo "todo-md: all passed" || echo "todo-md: $fails failed"
[ "$fails" -eq 0 ]
