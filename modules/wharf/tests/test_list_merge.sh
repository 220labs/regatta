#!/usr/bin/env bash
# Tests for bin/list-merge — the merge driver for TODO.md and CHANGELOG.md: real rebases and merges in
# scratch repos, with the driver named as `merge.union.driver` the way `list-merge install` names it.
#   bash modules/wharf/tests/test_list_merge.sh
set -u
B="$(cd "$(dirname "$0")/../bin" && pwd)"
LM="$B/list-merge"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fails=0
check() { if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3: expected [$2] got [$1]"; fails=$((fails+1)); fi; }
# git's identity in a file of the suite's own (a moved or bare runner has none; AGENTS.md's Traps); the
# driver is configured per command (-c), so the machine's own config is never read or written
printf '[user]\n\tname = t\n\temail = t@t\n[init]\n\tdefaultBranch = main\n' > "$T/gitconfig"
export GIT_CONFIG_GLOBAL="$T/gitconfig" GIT_CONFIG_NOSYSTEM=1
# the driver line `install` writes, never one of the suite's own (the landing review: a quoted %P passed here
# and broke every real merge)
drvline() { python3 -c 'import sys; from importlib.machinery import SourceFileLoader as L; print(L("lm", sys.argv[1]).load_module().driver_line(sys.argv[2]))' "$LM" "$1"; }
DRV="$(drvline "$LM")"
g() { git -C "$R" -c merge.union.driver="$DRV" "$@"; }
# A citation written in a fixture is spelled through $C, so this file holds none the repo's lint judges.
C="TODO.md"

# setup <dir> <file> <base text>: a repo on main with the union line and <file> committed
setup() {
  R="$1"; git init -q "$R"
  printf 'TODO.md merge=union\nCHANGELOG.md merge=union\nnotes.txt merge=union\n' > "$R/.gitattributes"
  printf '%s' "$3" > "$R/$2"
  git -C "$R" add -A && git -C "$R" commit -qm base
}
# side <branch> <file> <text>: commit <text> as <file> on <branch>, from base
side() { git -C "$R" checkout -q -B "$1" "$BASE"; printf '%s' "$3" > "$R/$2"; git -C "$R" commit -qam "$1"; }
flat() { tr '\n' '|' < "$R/$1"; }

TODO_BASE='# TODO

- [alpha] **Alpha** — a.
  Alpha'"'"'s second line.
- [beta] **Beta** — b.
- [gamma] **Gamma** — c.
'

echo "== TODO.md: the shapes union merged wrong"
setup "$T/a" TODO.md "$TODO_BASE"; BASE=$(git -C "$R" rev-parse HEAD)
side main TODO.md "$TODO_BASE- [delta] **Delta** — d.
"
side work TODO.md '# TODO

- [alpha] **Alpha** — a.
  Alpha'"'"'s second line.
- [beta] **Beta** — b.
'
g rebase -q main >/dev/null 2>&1; check "$?" 0 "a branch that did the last item rebases onto a main that appended"
check "$(flat TODO.md)" "# TODO||- [alpha] **Alpha** — a.|  Alpha's second line.|- [beta] **Beta** — b.|- [delta] **Delta** — d.|" \
  "  gamma stays done, delta is kept"
setup "$T/a-union" TODO.md "$TODO_BASE"; BASE=$(git -C "$R" rev-parse HEAD)
side main TODO.md "$TODO_BASE- [delta] **Delta** — d.
"
side work TODO.md '# TODO

- [alpha] **Alpha** — a.
  Alpha'"'"'s second line.
- [beta] **Beta** — b.
'
git -C "$R" rebase -q main >/dev/null 2>&1
grep -q '\[gamma\]' "$R/TODO.md"; check "$?" 0 "  (without the driver, union brings gamma back: the case is real)"

setup "$T/b" TODO.md "$TODO_BASE"; BASE=$(git -C "$R" rev-parse HEAD)
side main TODO.md "$TODO_BASE- [delta] **Delta** — d.
"
side work TODO.md "$TODO_BASE  Gamma's new line.
"
g rebase -q main >/dev/null 2>&1; check "$?" 0 "a line added under the last item rebases onto a main that appended"
check "$(flat TODO.md | sed 's/.*- \[beta\] \*\*Beta\*\* — b\.|//')" "- [gamma] **Gamma** — c.|  Gamma's new line.|- [delta] **Delta** — d.|" \
  "  it stays under gamma, never under delta"

setup "$T/c" TODO.md "$TODO_BASE"; BASE=$(git -C "$R" rev-parse HEAD)
side main TODO.md "$TODO_BASE- [delta] **Delta** — d.
"
side work TODO.md "$TODO_BASE- [eps] **Eps** — e.
"
g rebase -q main >/dev/null 2>&1; check "$?" 0 "two appends rebase clean"
check "$(tail -2 "$R/TODO.md" | tr '\n' '|')" "- [delta] **Delta** — d.|- [eps] **Eps** — e.|" "  main's first, then the branch's"
git -C "$R" checkout -q -B m2 "$(git -C "$R" rev-parse main)"; g merge -q --no-edit work >/dev/null 2>&1
check "$(grep -c '^- \[' "$R/TODO.md")" "5" "  and a merge of the same takes each item once"

setup "$T/d" TODO.md "$TODO_BASE"; BASE=$(git -C "$R" rev-parse HEAD)
side main TODO.md "$(printf '%s' "$TODO_BASE" | sed 's/Beta\*\* — b\./Beta** — b, said by main./')
"
side work TODO.md "$(printf '%s' "$TODO_BASE" | sed 's/Beta\*\* — b\./Beta** — b, said by the branch./')
"
g rebase -q main >/dev/null 2>&1; check "$?" 1 "both sides rewording one item stop the rebase"
grep -c -E '^(<<<<<<< ours|=======|>>>>>>> theirs)$' "$R/TODO.md" | grep -q '^3$'; check "$?" 0 "  with one conflict around that item alone"
git -C "$R" rebase --abort >/dev/null 2>&1

setup "$T/e" TODO.md "$TODO_BASE"; BASE=$(git -C "$R" rev-parse HEAD)
side main TODO.md "$(printf '%s' "$TODO_BASE" | sed '/\[beta\]/d')
"
side work TODO.md "$(printf '%s' "$TODO_BASE" | sed 's/Beta\*\* — b\./Beta** — b, still open: more found./')
"
g rebase -q main >/dev/null 2>&1; check "$?" 0 "a done on main and an edit on the branch rebase"
grep -q 'still open: more found' "$R/TODO.md"; check "$?" 0 "  the edited item is kept, not lost"

echo "== CHANGELOG.md: the release a branch's line must not land under"
CL_BASE='# Changelog

## Unreleased

- Old one.

## 0.1.0 — 2026-10-01

- First.
'
CL_CUT='# Changelog

## Unreleased

- Main'"'"'s new line.

## 0.2.0 — 2026-11-02

- Old one.

## 0.1.0 — 2026-10-01

- First.
'
CL_BRANCH='# Changelog

## Unreleased

- The branch'"'"'s line,
  on two lines.
- Old one.

## 0.1.0 — 2026-10-01

- First.
'
setup "$T/f" CHANGELOG.md "$CL_BASE"; BASE=$(git -C "$R" rev-parse HEAD)
side main CHANGELOG.md "$CL_CUT"; side work CHANGELOG.md "$CL_BRANCH"
g rebase -q main >/dev/null 2>&1; check "$?" 0 "a branch's line rebases onto a main that cut a release"
check "$(sed -n '/^## Unreleased/,/^## 0.2.0/p' "$R/CHANGELOG.md" | grep -c '^- ')" "2" "  both new lines sit under Unreleased"
check "$(sed -n '/^## 0.2.0/,/^## 0.1.0/p' "$R/CHANGELOG.md" | grep '^- ' | tr '\n' '|')" "- Old one.|" "  and the release holds only what it shipped"
grep -q "^  on two lines.$" "$R/CHANGELOG.md"; check "$?" 0 "  a line's continuation goes with it"
setup "$T/g" CHANGELOG.md "$CL_BASE"; BASE=$(git -C "$R" rev-parse HEAD)
side main CHANGELOG.md "$CL_CUT"; side work CHANGELOG.md "$CL_BRANCH"
g merge -q --no-edit main >/dev/null 2>&1; check "$?" 0 "main merged into the branch, the other way round"
check "$(sed -n '/^## 0.2.0/,/^## 0.1.0/p' "$R/CHANGELOG.md" | grep '^- ' | tr '\n' '|')" "- Old one.|" "  the moved line follows the release, the branch's stays Unreleased"
check "$(sed -n '/^## Unreleased/,/^## 0.2.0/p' "$R/CHANGELOG.md" | grep -c '^- ')" "2" "  beside main's new one"

setup "$T/h" CHANGELOG.md "$CL_BASE"; BASE=$(git -C "$R" rev-parse HEAD)
side main CHANGELOG.md "$(printf '%s' "$CL_BASE" | sed 's/^- Old one\.$/- Main first.\n- Old one./')
"
side work CHANGELOG.md "$(printf '%s' "$CL_BASE" | sed 's/^- Old one\.$/- Branch first.\n- Old one./')
"
g rebase -q main >/dev/null 2>&1; check "$?" 0 "two lines added at the top of Unreleased rebase clean"
check "$(sed -n '/^## Unreleased/,/^## 0.1.0/p' "$R/CHANGELOG.md" | grep -c '^- ')" "3" "  all three lines kept"

echo "== the landing review's shapes (each reproduced a wrong merge)"
HELM_BASE='# Changelog — helm

## Unreleased

- Old.
'
setup "$T/rn" CHANGELOG.md "$HELM_BASE"; BASE=$(git -C "$R" rev-parse HEAD)
side main CHANGELOG.md '# Changelog — helm

## 0.2.0 — 2026-11-02

- Old.
'
side work CHANGELOG.md "$HELM_BASE- New.
"
g rebase -q main >/dev/null 2>&1; check "$?" 0 "a release cut by renaming Unreleased (helm's style) rebases"
check "$(flat CHANGELOG.md)" "# Changelog — helm||## Unreleased||- New.||## 0.2.0 — 2026-11-02||- Old.|" \
  "  the branch's line gets an Unreleased of its own, the release keeps what it shipped"
KAC_BASE='# Changelog

## [Unreleased]

### Added

- x

## [0.1.0]

### Added

- y
'
setup "$T/kac" CHANGELOG.md "$KAC_BASE"; BASE=$(git -C "$R" rev-parse HEAD)
side main CHANGELOG.md '# Changelog

## [Unreleased]

### Added

## [0.2.0]

### Added

- x

## [0.1.0]

### Added

- y
'
side work CHANGELOG.md "$(printf '%s' "$KAC_BASE" | sed 's/^- x$/- x\n- z/')
"
g merge -q --no-edit main >/dev/null 2>&1; check "$?" 0 "Keep a Changelog: each release's ### Added is its own section"
check "$(sed -n '/^## \[Unreleased\]/,/^## \[0.2.0\]/p' "$R/CHANGELOG.md" | grep '^- ' | tr '\n' '|')" "- z|" "  the new line stays Unreleased"
check "$(sed -n '/^## \[0.2.0\]/,/^## \[0.1.0\]/p' "$R/CHANGELOG.md" | grep '^- ' | tr '\n' '|')" "- x|" "  the shipped one stays 0.2.0's"
STAR='# Changelog

* foo
* bar
'
setup "$T/star" CHANGELOG.md "$STAR"; BASE=$(git -C "$R" rev-parse HEAD)
side main CHANGELOG.md '# Changelog

* new A
* foo
* bar
'
side work CHANGELOG.md '# Changelog

* new B
* foo
* bar
'
g rebase -q main >/dev/null 2>&1; check "$?" 0 "\`* \` bullets are items"
check "$(grep -c '^\* ' "$R/CHANGELOG.md")|$(grep -c '^\* foo$' "$R/CHANGELOG.md")" "4|1" "  four lines, none doubled"
BOX='# TODO

- [x] A done
- [x] B done
'
setup "$T/box" TODO.md "$BOX"; BASE=$(git -C "$R" rev-parse HEAD)
side main TODO.md '# TODO

- [x] Z newly done
- [x] A done
- [x] B done
'
side work TODO.md '# TODO

- [x] A done
- [x] B done, with a note
'
g rebase -q main >/dev/null 2>&1; check "$?" 0 "a [x] checkbox is no id: ticked tasks merge by their own lines"
check "$(flat TODO.md)" "# TODO||- [x] Z newly done|- [x] A done|- [x] B done, with a note|" "  each once, the edit kept"
EDIT='# Changelog

## Unreleased

- one
  cont
'
setup "$T/edit" CHANGELOG.md "$EDIT"; BASE=$(git -C "$R" rev-parse HEAD)
side main CHANGELOG.md "$(printf '%s' "$EDIT" | sed 's/^- one$/- one, reworded/')
"
side work CHANGELOG.md "$(printf '%s' "$EDIT" | sed 's/^  cont$/  cont, extended/')
"
g rebase -q main >/dev/null 2>&1; check "$?" 1 "a first-line edit and a continuation edit of one entry: a conflict, never the entry twice"
git -C "$R" rebase --abort >/dev/null 2>&1
TIGHT='# TODO

- [alpha] **Alpha** — a.

- [beta] **Beta** — b.

- [gamma] **Gamma** — c.
'
setup "$T/blank" TODO.md "$TIGHT"; BASE=$(git -C "$R" rev-parse HEAD)
side main TODO.md '# TODO

- [alpha] **Alpha** — a.

- [beta] **Beta** — b.
'
side work TODO.md "$(printf '%s' "$TIGHT" | sed 's/Beta\*\* — b\./Beta** — b, reworded./')
"
g rebase -q main >/dev/null 2>&1; check "$?" 0 "a blank line that moved with a done is no edit: no conflict with a rewording"
check "$(grep -c 'gamma\|reworded' "$R/TODO.md")" "1" "  gamma done, beta reworded"
printf '# TODO\r\n\r\n- [alpha] **A** — a.\r\n' > "$T/co"; printf '# TODO\r\n\r\n- [alpha] **A** — a.\r\n- [beta] **B** — b.\r\n' > "$T/ca"
printf '# TODO\r\n\r\n- [alpha] **A** — a.\r\n- [gamma] **G** — g.\r\n' > "$T/cb"
python3 "$LM" "$T/co" "$T/ca" "$T/cb" TODO.md; check "$?|$(grep -c $'\r$' "$T/ca")|$(wc -l < "$T/ca" | tr -d ' ')" "0|5|5" "a CRLF file keeps its line ends"

echo "== the second review's shapes"
DUP='# Changelog

## Unreleased

- Fix.
- Other.
- Fix.
'
setup "$T/dup1" CHANGELOG.md "$DUP"; BASE=$(git -C "$R" rev-parse HEAD)
side main CHANGELOG.md '# Changelog

## Unreleased

- Other.
- Fix.
'
side work CHANGELOG.md '# Changelog

## Unreleased

- Fix.
- Other.
- Fix, reworded.
'
g rebase -q main >/dev/null 2>&1; rc=$?
check "$rc|$(grep -c '^- Fix' "$R/CHANGELOG.md" 2>/dev/null)" "0|$(printf '%s' "$DUP" > "$T/u-o"; printf '# Changelog\n\n## Unreleased\n\n- Other.\n- Fix.\n' > "$T/u-a"; printf '# Changelog\n\n## Unreleased\n\n- Fix.\n- Other.\n- Fix, reworded.\n' > "$T/u-b"; git merge-file --union -p "$T/u-a" "$T/u-o" "$T/u-b" | grep -c '^- Fix')" \
  "duplicate lines: a delete of one and an edit of the other merge as union would, never a revival"
setup "$T/dup2" CHANGELOG.md "$DUP"; BASE=$(git -C "$R" rev-parse HEAD)
side main CHANGELOG.md '# Changelog

## Unreleased

- Other.
- Fix.
'
side work CHANGELOG.md "$DUP- Fix.
"
g rebase -q main >/dev/null 2>&1
check "$(grep -c '^- Fix\.$' "$R/CHANGELOG.md")" "2" "  a delete of one duplicate and an add of another: two, as both sides imply"
FEN='# TODO

- [alpha] **Alpha** — a.
  ~~~
  ```
  ~~~
- [beta] **Beta** — b.
'
setup "$T/fence" TODO.md "$FEN"; BASE=$(git -C "$R" rev-parse HEAD)
side main TODO.md "$FEN- [gamma] **Gamma** — c.
"
side work TODO.md "$(printf '%s' "$FEN" | sed 's/Alpha\*\* — a\./Alpha** — a, edited./')
"
g rebase -q main >/dev/null 2>&1; check "$?" 0 "a fence closes only on its own marker: ~~~ around \`\`\` is no whole-file conflict"
check "$(grep -c 'a, edited\|\[gamma\]' "$R/TODO.md")" "2" "  the edit and the append both kept"
LATER='# TODO

## Now

- [alpha] **Alpha** — a.

## Later

- [beta] **Beta** — b.
'
setup "$T/later" TODO.md "$LATER"; BASE=$(git -C "$R" rev-parse HEAD)
side main TODO.md "$(printf '%s' "$LATER" | sed 's/^## Later$/## Someday/')
"
side work TODO.md "$LATER- [zeta] **Zeta** — z.
"
g rebase -q main >/dev/null 2>&1; check "$?" 0 "a TODO section renamed on one side"
check "$(sed -n '/^## Someday/,$p' "$R/TODO.md" | grep -c '^- \[')|$(grep -c '^## ' "$R/TODO.md")" "2|2" \
  "  the other side's new item follows it there, and no old heading comes back"
F="$T/fake-crash"; printf '#!/bin/sh\necho crashed >&2\nexit 1\n' > "$F"; chmod +x "$F"
setup "$T/crash" TODO.md "$TODO_BASE"; BASE=$(git -C "$R" rev-parse HEAD)
side main TODO.md "$TODO_BASE- [delta] **Delta** — d.
"; side work TODO.md "$TODO_BASE- [eps] **Eps** — e.
"
git -C "$R" -c merge.union.driver="$(drvline "$F")" rebase -q main >/dev/null 2>&1
check "$?|$(grep -c '^- \[' "$R/TODO.md")" "0|5" "a driver that crashes (exit 1) merges as union: never a conflict holding ours alone"

echo "== round two's shapes"
G4='# Changelog

## Unreleased

- X: the old entry.
- Y: another.
'
setup "$T/g4" CHANGELOG.md "$G4"; BASE=$(git -C "$R" rev-parse HEAD)
side main CHANGELOG.md '# Changelog

## 0.2.0 — 2026-11-02

- X: the old entry.
- Y: another.
'
side work CHANGELOG.md '# Changelog

## Unreleased

- NEW: the branch entry.
- X: the old entry, typo fixed.
- Y: another.
'
g rebase -q main >/dev/null 2>&1; check "$?" 0 "a new entry on top of an edited one, against a release cut"
check "$(sed -n '/^## Unreleased/,/^## 0.2.0/p' "$R/CHANGELOG.md" | grep '^- ' | tr '\n' '|')" "- NEW: the branch entry.|" \
  "  the new entry is Unreleased, never paired as the edit"
check "$(sed -n '/^## 0.2.0/,$p' "$R/CHANGELOG.md" | grep -c '^- X')" "1" "  and the shipped entry stays in the release"
R1='# TODO

## Now

- [alpha] **Alpha** — a.

## Later

- [beta] **Beta** — b.
'
setup "$T/r1" TODO.md "$R1"; BASE=$(git -C "$R" rev-parse HEAD)
side main TODO.md '# TODO

## Now

- [alpha] **Alpha** — a.
- [delta] **Delta** — d.

## Someday plans

- [beta] **Beta** — b.
'
side work TODO.md "$R1- [zeta] **Zeta** — z.
"
g rebase -q main >/dev/null 2>&1; check "$?" 0 "a section renamed past recognition on one side"
check "$(grep -c '^## Later' "$R/TODO.md")|$(sed -n '/^## Someday/,$p' "$R/TODO.md" | grep -c 'zeta')" "0|1" \
  "  never comes back above the others: the new item follows it, as union keeps it"
MV='# TODO

- [aa] **A** — a.
- [bb] **B** — b.
- [cc] **C** — c.
'
setup "$T/mv" TODO.md "$MV"; BASE=$(git -C "$R" rev-parse HEAD)
side main TODO.md "$MV- [dd] **D** — d.
"
side work TODO.md '# TODO

- [cc] **C** — c.
- [aa] **A** — a.
- [bb] **B** — b.
'
g rebase -q main >/dev/null 2>&1
check "$(grep -n '^- \[cc\]' "$R/TODO.md" | head -1 | cut -d: -f1)" "3" "a move on one side is never dropped silently (union keeps it; the lint names a double)"

echo "== round three's shapes"
SW='# TODO

- [aa] **A** — a.
- [bb] **B** — b.
- [cc] **C** — c.
- [dd] **D** — d.
'
setup "$T/swap" TODO.md "$SW"; BASE=$(git -C "$R" rev-parse HEAD)
side main TODO.md '# TODO

- [bb] **B** — b.
- [aa] **A** — a.
- [cc] **C** — c.
- [dd] **D** — d.
'
side work TODO.md '# TODO

- [aa] **A** — a.
- [bb] **B** — b.
- [dd] **D** — d.
- [cc] **C** — c.
'
g rebase -q main >/dev/null 2>&1
ids=$(grep -o '^- \[[a-z]*\]' "$R/TODO.md" | tr -d '\n')
case "$ids" in "- [bb]- [aa]"*"- [dd]"*"- [cc]") r=kept ;; *) r="lost: $ids" ;; esac
check "$r" "kept" "a move on each side goes to union: neither move dropped (a doubled id is the lint's to name)"
SUB='# Changelog

## Unreleased

### Added

- X.

## 0.1.0

### Added

- Y.
'
setup "$T/sub" CHANGELOG.md "$SUB"; BASE=$(git -C "$R" rev-parse HEAD)
side main CHANGELOG.md "$(printf '%s' "$SUB" | sed 's/^## Unreleased$/## 0.2.0/')
"
side work CHANGELOG.md "$(printf '%s' "$SUB" | sed 's/^- X\.$/- NEW.\n- X./')
"
g rebase -q main >/dev/null 2>&1; check "$?" 0 "a cut that renames Unreleased, with Keep a Changelog's ### Added"
check "$(sed -n '/^## Unreleased/,/^## 0.2.0/p' "$R/CHANGELOG.md" | grep '^- \|^### ' | tr '\n' '|')" "### Added|- NEW.|" \
  "  the new line gets its Unreleased and its ### Added back"
check "$(sed -n '/^## 0.2.0/,/^## 0.1.0/p' "$R/CHANGELOG.md" | grep '^- ' | tr '\n' '|')" "- X.|" "  the release keeps what it shipped"

RN='# Changelog

## Unreleased

### Added

- a.
- b.
'
setup "$T/rn4" CHANGELOG.md "$RN"; BASE=$(git -C "$R" rev-parse HEAD)
side main CHANGELOG.md "$(printf '%s' "$RN" | sed 's/^### Added$/### New features/')
"
side work CHANGELOG.md "$RN- NEW.
"
g rebase -q main >/dev/null 2>&1; check "$?" 0 "a subsection renamed under a standing Unreleased (no cut)"
check "$(grep -c '^### Added' "$R/CHANGELOG.md")|$(sed -n '/^### New features/,$p' "$R/CHANGELOG.md" | grep -c 'NEW')" "0|1" \
  "  is never remade: the line stays under the renamed one, as union keeps it"

echo "== the fallback"
setup "$T/i" notes.txt 'a
b
'; BASE=$(git -C "$R" rev-parse HEAD)
side main notes.txt 'a
b
main
'; side work notes.txt 'a
b
work
'
g rebase -q main >/dev/null 2>&1; check "$?" 0 "another union file merges as union"
check "$(flat notes.txt)" "a|b|main|work|" "  both lines kept"
printf 'pre\n' > "$T/fo"; printf 'pre A\n' > "$T/fa"; printf 'pre B\n' > "$T/fb"
python3 "$LM" "$T/fo" "$T/fa" "$T/fb" TODO.md 2>"$T/err"; check "$?" 0 "a file it cannot judge (both changed the preamble) falls back to union"
grep -q 'merged as union' "$T/err"; check "$?" 0 "  and says so"
check "$(tr '\n' '|' < "$T/fa")" "pre A|pre B|" "  union's result"

echo "== install"
R="$T/inst"; git init -q "$R"
python3 "$LM" install "$R" --check --here >/dev/null; check "$?" 1 "install --check in a repo without it: 1"
python3 "$LM" install "$R" --here >/dev/null; check "$?" 0 "install --here sets it, in the repo's own config"
git -C "$R" config --local --get merge.union.driver | grep -q "list-merge.* %O %A %B %P; s=\$?; .*\[ \$r = 129 \] && exec git merge-file --union %A %O %B; .*exit \$r$"
check "$?" 0 "  this file through its shebang, falling back to union"
check "$(git config --global --get merge.union.driver)" "" "  and never the global config"
python3 "$LM" install "$R" --check --here; check "$?" 0 "  and --check passes after"
R="$T/foreign"; git init -q "$R"; git -C "$R" config merge.union.driver "my-own %O %A %B"
python3 "$LM" install "$R" --here >/dev/null; check "$(git -C "$R" config --get merge.union.driver)" "my-own %O %A %B" \
  "a repo's own union driver is left alone"
python3 "$LM" install "$R" --here --force >/dev/null; git -C "$R" config --get merge.union.driver | grep -q list-merge; check $? 0 "  --force replaces it"
R="$T/glob"; git init -q "$R"; G3="$T/glob.gitconfig"; printf '[merge "union"]\n\tdriver = owners-own %%O %%A %%B\n' > "$G3"
GIT_CONFIG_GLOBAL="$G3" python3 "$LM" install "$R" --here >/dev/null
check "$(git -C "$R" config --local --get merge.union.driver)" "" "  and so is one the owner set globally"
cp "$LM" "$T/lm-noexec"; chmod -x "$T/lm-noexec"; R="$T/noexec"; git init -q "$R"
python3 "$T/lm-noexec" install "$R" --here --check >/dev/null; check "$?" 1 "a list-merge that is not executable fails --check"
python3 "$T/lm-noexec" install "$R" --here >/dev/null 2>&1; check "$?|$(git -C "$R" config --get merge.union.driver)" "2|" "  and is never installed"
setup "$T/gone" TODO.md "$TODO_BASE"; BASE=$(git -C "$R" rev-parse HEAD)
side main TODO.md "$TODO_BASE- [delta] **Delta** — d.
"; side work TODO.md "$TODO_BASE- [eps] **Eps** — e.
"
cp "$LM" "$T/lm-moved"; chmod +x "$T/lm-moved"; python3 "$T/lm-moved" install "$R" --here >/dev/null; rm -f "$T/lm-moved"
git -C "$R" rebase -q main >/dev/null 2>&1; check "$?" 0 "a driver whose file is gone merges as union, never jams"
check "$(grep -c '^- \[' "$R/TODO.md")" "5" "  every item kept"
# a copy in a linked worktree names the main checkout's, never its own: /finish removes a worktree
R="$T/wt"; git init -q "$R"; mkdir -p "$R/bin"; cp "$LM" "$R/bin/list-merge"; git -C "$R" add -A; git -C "$R" commit -qm m
git -C "$R" worktree add -q "$T/wt-linked" -b side
python3 "$T/wt-linked/bin/list-merge" install "$T/wt-linked" >/dev/null
check "$(git -C "$R" config --local --get merge.union.driver | grep -o '/[^ ]*list-merge' | head -1 | sed "s|$(cd "$T" && pwd -P)||;s|$T||")" "/wt/bin/list-merge" \
  "install from a worktree names the main checkout's copy"
python3 "$LM" >/dev/null 2>&1; check "$?" 2 "no arguments: usage, exit 2"

[ "$fails" -eq 0 ] && echo "list-merge: all passed" || echo "list-merge: $fails failed"
[ "$fails" -eq 0 ]
