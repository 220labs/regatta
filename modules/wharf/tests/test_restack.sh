#!/usr/bin/env bash
# Tests for `pr restack` and `pr carry`: a ready claude/* PR GitHub marks DIRTY only because main appended
# to a list file is rebased with list-merge and pushed; anything else is refused with a finding on the PR.
# Real rebases and pushes into a scratch bare origin, with the clone's merge.union.driver set by
# `list-merge install`; GitHub faked (the PR, its comments). No network.
#   bash modules/wharf/tests/test_restack.sh
set -u
unset CLAUDE_UNATTENDED REGATTA_UNATTENDED CLAUDE_CODE_SESSION_ID
B="$(cd "$(dirname "$0")/.." && pwd)"
PR="$B/libexec/pr"; LM="$B/bin/list-merge"
T=$(mktemp -d); T=$(cd "$T" && pwd -P); trap 'rm -rf "$T"' EXIT
export REGATTA_CONFIG="${REGATTA_CONFIG:-$T/regatta-config}"; unset REGATTA_HOME REGATTA_LEGACY
# git's identity in a file of the suite's own (a moved HOME or a bare runner has none; AGENTS.md's Traps)
printf '[user]\n\tname = t\n\temail = t@t\n[init]\n\tdefaultBranch = main\n' > "$T/gitconfig"
export GIT_CONFIG_GLOBAL="$T/gitconfig" GIT_CONFIG_NOSYSTEM=1 PR_RESTACK_WAIT=0
fails=0
check() { if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3: expected [$2] got [$1]"; fails=$((fails+1)); fi; }
has()   { if grep -qF -- "$2" "$1"; then echo "  ok   $3"; else echo "  FAIL $3: missing [$2]"; sed 's/^/        /' "$1" | head -20; fails=$((fails+1)); fi; }
lacks() { if grep -qF -- "$2" "$1"; then echo "  FAIL $3: found [$2]"; fails=$((fails+1)); else echo "  ok   $3"; fi; }
# A citation in a fixture is spelled through $C, so this file holds none the repo's own lint judges.
C="TODO.md"

# GitHub faked: the PRs from $T/pulls.json (number -> PR), comments kept in $T/comments.json, every POST printed
cat > "$T/run.py" <<'PY'
import importlib.machinery, importlib.util, json, os, re, sys
loader = importlib.machinery.SourceFileLoader("prmod", sys.argv[1])
spec = importlib.util.spec_from_loader("prmod", loader); pr = importlib.util.module_from_spec(spec); loader.exec_module(pr)
T = os.environ["T"]
pr.common.token = lambda: "tok"
pr.common.repo_slug = lambda url: "o/r"
def load(name, default):
    try:
        return json.load(open(os.path.join(T, name)))
    except (OSError, ValueError):
        return default
def api(method, path, body=None, tok=None, timeout=15):
    pulls, comments = load("pulls.json", {}), load("comments.json", {})
    if method == "GET" and path == "/user":
        return 200, {"login": "me"}
    m = re.match(r"/repos/o/r/commits/(\w+)/(check-runs|status)", path)
    if method == "GET" and m:
        checks = load("checks.json", {})   # sha -> check run status ("in_progress", "failure"), else all green
        st = checks.get(m.group(1))
        if m.group(2) == "status":
            return 200, {"statuses": []}
        if st == "none":   # a head GitHub never ran a workflow on (a PR that conflicts runs none)
            return 200, {"check_runs": []}
        if st == "automerge-red":   # a red advisory run beside a green check: not a required one
            runs = [{"name": "automerge", "status": "completed", "conclusion": "failure"},
                    {"name": "check", "status": "completed", "conclusion": "success"}]
        elif st is None:
            runs = [{"name": "check", "status": "completed", "conclusion": "success"}]
        else:
            runs = [{"name": "check", "status": "in_progress" if st == "in_progress" else "completed",
                     "conclusion": None if st == "in_progress" else st}]
        name = re.search(r"check_name=([^&]+)", path)
        return 200, {"check_runs": [r for r in runs if not name or r["name"] == name.group(1)]}
    m = re.match(r"/repos/o/r/pulls/(\d+)$", path)
    if method == "GET" and m:
        return (200, pulls[m.group(1)]) if m.group(1) in pulls else (404, None)
    if method == "GET" and path.startswith("/repos/o/r/pulls?"):
        return 200, (list(pulls.values()) if path.endswith("page=1") else [])
    m = re.match(r"/repos/o/r/issues/(\d+)/comments", path)
    if m and method == "GET" and "page=" in path and not path.endswith("page=1"):
        return 200, []
    if m and method == "GET":
        return 200, [{"body": b} for b in comments.get(m.group(1), [])]
    if m and method == "POST":
        comments.setdefault(m.group(1), []).append(body["body"])
        json.dump(comments, open(os.path.join(T, "comments.json"), "w"))
        print("COMMENT", m.group(1), body["body"].split("\n", 1)[1][:200].replace("\n", " "))
        return 201, {}
    print("API?", method, path)
    return 404, None
pr.common.api = api
sys.argv = ["pr"] + sys.argv[2:]
try:
    pr.main()
except SystemExit as e:
    if e.code not in (None, 0) and not isinstance(e.code, int):
        print(e.code)
    print("EXIT", e.code if isinstance(e.code, int) else (0 if e.code is None else 1))
PY
export T
prrun() { out=$1; shift; (cd "$R" && python3 "$T/run.py" "$PR" "$@") > "$out" 2>&1; }

# pull <n> <ref> <sha> [draft] [state] [author] [label]: the PR GitHub shows
pull() {
  python3 - "$T/pulls.json" "$1" "$2" "$3" "${4:-false}" "${5:-dirty}" "${6:-me}" "${7:-}" <<'PY'
import json, sys
f, n, ref, sha, draft, state, author, label = sys.argv[1:]
try:
    d = json.load(open(f))
except (OSError, ValueError):
    d = {}
d[n] = {"number": int(n), "state": "open", "user": {"login": author}, "draft": draft == "true", "mergeable_state": state,
        "head": {"ref": ref, "sha": sha, "repo": {"full_name": "o/r"}}, "base": {"ref": "main"},
        "labels": [{"name": label}] if label else []}
json.dump(d, open(f, "w"))
PY
}

# fresh <name>: a bare origin and its clone on main with the list files and a code file, driver installed
fresh() {
  O="$T/$1.git"; R="$T/$1"; W="$T/$1-other"
  git init -q --bare -b main "$O"; git clone -q "$O" "$R" 2>/dev/null
  mkdir -p "$R/modules/m"
  printf 'TODO.md merge=union\nCHANGELOG.md merge=union\n' > "$R/.gitattributes"
  printf '# TODO\n\n- [alpha] **Alpha** — a.\n' > "$R/TODO.md"
  printf '# Changelog\n\n## Unreleased\n\n- base line\n' > "$R/modules/m/CHANGELOG.md"
  printf 'x = 1\n' > "$R/code.py"
  git -C "$R" add -A; git -C "$R" commit -qm base; git -C "$R" push -q origin main
  "$LM" install "$R" > /dev/null
  git clone -q "$O" "$W" 2>/dev/null
  rm -f "$T/pulls.json" "$T/comments.json" "$T/checks.json"
}
# branch <ref>: start the PR's branch in R from main (pushed after its commits by `ship`)
branch() { git -C "$R" checkout -q -b "$1" origin/main; }
ship() { git -C "$R" push -q origin "$1"; git -C "$R" checkout -q --detach; }   # the worktree leaves the branch
# main_commit <msg>: commit what W holds onto main, as another landing would
main_commit() { git -C "$W" add -A; git -C "$W" commit -qm "$1"; git -C "$W" push -q origin main; }
tip() { git -C "$O" rev-parse "refs/heads/$1"; }

echo "== a DIRTY PR on a TODO.md append: restacked and pushed"
fresh a
branch claude/t/a; printf '\n- [beta] **Beta** — the branch.\n' >> "$R/TODO.md"; printf 'x = 2\n' > "$R/code.py"
git -C "$R" commit -qam "Branch: beta"; ship claude/t/a
git -C "$W" pull -q; printf '\n- [delta] **Delta** — main.\n' >> "$W/TODO.md"; main_commit "TODO: delta"
OLD=$(tip claude/t/a); pull 7 claude/t/a "$OLD"
prrun "$T/a.out" restack 7
has "$T/a.out" "EXIT 0" "exit 0"
has "$T/a.out" "restacked — pushed ${OLD:0:8}" "says it pushed"
NEW=$(tip claude/t/a)
[ "$NEW" != "$OLD" ]; check "$?" 0 "origin's branch moved"
git -C "$O" merge-base --is-ancestor main "$NEW"; check "$?" 0 "  onto main's tip"
check "$(git -C "$O" show "$NEW:TODO.md" | grep -c '^- \[')" 3 "  TODO.md holds alpha, beta and delta"
check "$(git -C "$O" show "$NEW:code.py")" "x = 2" "  the branch's code kept"
has "$T/a.out" "COMMENT 7 **pr restack:** rebased" "a comment says so on the PR"
check "$(git -C "$R" rev-parse refs/heads/claude/t/a)" "$NEW" "the local branch (no worktree on it) follows"
check "$(git -C "$R" worktree list | wc -l | tr -d ' ')" 1 "the scratch worktree is gone"
prrun "$T/carry.out" carry "$OLD" "$NEW"
has "$T/carry.out" "CARRY the patch is ${OLD:0:8}'s, list files aside (TODO.md)" "pr carry: the restack's push carries the green"
has "$T/carry.out" "EXIT 0" "  exit 0"
git -C "$W" pull -q; printf 'x = 3\n' > "$W/code.py"; main_commit "Code: x"
git -C "$R" fetch -q origin
prrun "$T/carry2.out" carry "$OLD" "origin/main"
has "$T/carry2.out" "RUN code.py differs" "pr carry: a head whose code differs runs the whole line"
has "$T/carry2.out" "EXIT 1" "  exit 1"

# a mode change keeps the blob id: the carry must still see it (the build review's probe)
printf '#!/bin/sh\n' > "$W/tool.sh"; chmod +x "$W/tool.sh"; main_commit "tool"
M1=$(git -C "$W" rev-parse HEAD); chmod -x "$W/tool.sh"; printf '\n- [eps] **Eps** — e.\n' >> "$W/TODO.md"
git -C "$W" add -A; git -C "$W" commit -qm "tool -x"; M2=$(git -C "$W" rev-parse HEAD); git -C "$W" push -q origin main
git -C "$R" fetch -q origin
prrun "$T/carry3.out" carry "$M1" "$M2" --base "$M1"
has "$T/carry3.out" "RUN tool.sh differs" "pr carry: a mode change with the same blob runs the whole line"
printf 'a\n' > "$W/run\"me.sh"; main_commit "quoted"; Q1=$(git -C "$W" rev-parse HEAD)
printf 'b\n' > "$W/run\"me.sh"; printf '\n- [zeta] **Zeta** — z.\n' >> "$W/TODO.md"; main_commit "quoted, changed"
Q2=$(git -C "$W" rev-parse HEAD); git -C "$R" fetch -q origin
prrun "$T/carry4.out" carry "$Q1" "$Q2" --base "$Q1"
has "$T/carry4.out" "RUN run\"me.sh differs" "pr carry: a change to a file whose name git quotes runs the whole line"

echo "== a PR holding a merge commit: refused (a rebase would drop the merge's own edit)"
fresh h
branch claude/t/h; printf '\n- [beta] **Beta** — b.\n' >> "$R/TODO.md"; git -C "$R" commit -qam "beta"
git -C "$W" pull -q; printf 'y = 1\n' > "$W/other.py"; main_commit "other"
git -C "$R" fetch -q origin; git -C "$R" merge -q --no-ff --no-commit origin/main > /dev/null 2>&1
printf 'x = 2  # fixed during the merge\n' > "$R/code.py"; git -C "$R" add -A; git -C "$R" commit -qm "Merge origin/main"
ship claude/t/h
git -C "$W" pull -q; printf '\n- [delta] **Delta** — d.\n' >> "$W/TODO.md"; main_commit "TODO: delta"
OLD=$(tip claude/t/h); pull 17 claude/t/h "$OLD"
prrun "$T/h.out" restack 17
has "$T/h.out" "holds 1 merge commit(s)" "a merge commit in the PR: refused"
has "$T/h.out" "EXIT 1" "  exit 1"
check "$(tip claude/t/h)" "$OLD" "  origin untouched"

echo "== a CHANGELOG release cut: the branch's line stays under Unreleased"
fresh b
branch claude/t/b
printf '# Changelog\n\n## Unreleased\n\n- branch line\n- base line\n' > "$R/modules/m/CHANGELOG.md"
git -C "$R" commit -qam "m: branch line"; ship claude/t/b
git -C "$W" pull -q; printf '# Changelog\n\n## 0.2.0\n\n- base line\n- main line\n' > "$W/modules/m/CHANGELOG.md"
main_commit "m: 0.2.0"
OLD=$(tip claude/t/b); pull 8 claude/t/b "$OLD"
prrun "$T/b.out" restack 8
has "$T/b.out" "EXIT 0" "exit 0, pushed"
NEW=$(tip claude/t/b)
git -C "$O" show "$NEW:modules/m/CHANGELOG.md" > "$T/b.md"
check "$(grep -m1 '^## ' "$T/b.md")" "## Unreleased" "Unreleased is the first heading again"
check "$(awk '/^## Unreleased/{u=1;next} /^## /{u=0} u && /^- /' "$T/b.md")" "- branch line" "  the branch's line under it"
check "$(awk '/^## 0.2.0/{u=1;next} /^## /{u=0} u && /^- /' "$T/b.md" | tr '\n' '|')" "- base line|- main line|" "  the release keeps main's lines"

echo "== a code conflict: refused, with a finding on the PR, once a tip"
fresh c
branch claude/t/c; printf 'x = 2\n' > "$R/code.py"; printf '\n- [beta] **Beta** — b.\n' >> "$R/TODO.md"
git -C "$R" commit -qam "Code: two"; ship claude/t/c
git -C "$W" pull -q; printf 'x = 9\n' > "$W/code.py"; printf '\n- [delta] **Delta** — d.\n' >> "$W/TODO.md"; main_commit "Code: nine"
OLD=$(tip claude/t/c); pull 9 claude/t/c "$OLD"
prrun "$T/c.out" restack 9
has "$T/c.out" "EXIT 1" "exit 1"
has "$T/c.out" "refused — a code conflict: code.py changed on both sides" "names the code file"
has "$T/c.out" "COMMENT 9 **pr restack: not restacked.**" "the finding goes on the PR"
check "$(tip claude/t/c)" "$OLD" "origin's branch untouched"
prrun "$T/c2.out" restack 9
has "$T/c2.out" "EXIT 1" "the next pass refuses again"
lacks "$T/c2.out" "COMMENT" "  and says nothing more on the same tip"

echo "== after a restack, a later refusal on the new tip is still said; another login's PR and a running check: left"
fresh i
branch claude/t/i; printf '\n- [beta] **Beta** — b.\n' >> "$R/TODO.md"; printf 'x = 2\n' > "$R/code.py"
git -C "$R" commit -qam "beta"; ship claude/t/i
git -C "$W" pull -q; printf '\n- [delta] **Delta** — d.\n' >> "$W/TODO.md"; main_commit "TODO: delta"
OLD=$(tip claude/t/i); pull 18 claude/t/i "$OLD" false dirty someone-else
prrun "$T/i0.out" restack 18
has "$T/i0.out" "opened by someone-else, not this token's login" "another login's PR: left alone"
lacks "$T/i0.out" "COMMENT" "  nothing said on it"
check "$(tip claude/t/i)" "$OLD" "  its branch untouched"
printf '{"%s": "in_progress"}' "$OLD" > "$T/checks.json"; pull 18 claude/t/i "$OLD"
prrun "$T/i1.out" restack 18
has "$T/i1.out" "not now — the required check \`check\` is still running" "a head whose check runs: not now (a push would cancel it)"
has "$T/i1.out" "EXIT 2" "  exit 2"
check "$(tip claude/t/i)" "$OLD" "  origin untouched"
pull 18 claude/t/i "$OLD" false dirty me hold; rm -f "$T/checks.json"
prrun "$T/i1h.out" restack 18
has "$T/i1h.out" "labelled \`hold\`, it waits for the owner's tap: left alone" "a PR labelled hold: left alone (the finish review)"
lacks "$T/i1h.out" "COMMENT" "  nothing said on it"
check "$(tip claude/t/i)" "$OLD" "  its head untouched"
prrun "$T/i1ha.out" restack --all
lacks "$T/i1ha.out" "#18" "  --all passes it by unsaid"
check "$(tip claude/t/i)" "$OLD" "  still untouched"
pull 18 claude/t/i "$OLD"
printf '{"%s": "failure"}' "$OLD" > "$T/checks.json"
prrun "$T/i1b.out" restack 18
has "$T/i1b.out" "the required check \`check\` ended failure" "a red required check: not now"
printf '{"%s": "automerge-red"}' "$OLD" > "$T/checks.json"
prrun "$T/i2.out" restack 18
rm -f "$T/checks.json"
has "$T/i2.out" "restacked" "its required check green, a red automerge run beside it: restacked"
NEW=$(tip claude/t/i)
git -C "$W" pull -q; printf 'x = 7\n' > "$W/code.py"; main_commit "Code: seven"
git -C "$R" fetch -q origin; pull 18 claude/t/i "$NEW"
prrun "$T/i3.out" restack 18
has "$T/i3.out" "COMMENT 18 **pr restack: not restacked.**" "a later refusal on the restacked tip is said (the push's own comment is no finding)"

echo "== a head no workflow ever ran on (pushed into a conflict): restacked, not held for good"
fresh n
branch claude/t/n; printf '\n- [beta] **Beta** — b.\n' >> "$R/TODO.md"; git -C "$R" commit -qam "beta"; ship claude/t/n
git -C "$W" pull -q; printf '\n- [delta] **Delta** — d.\n' >> "$W/TODO.md"; main_commit "TODO: delta"
OLD=$(tip claude/t/n); pull 19 claude/t/n "$OLD"; printf '{"%s": "none"}' "$OLD" > "$T/checks.json"
prrun "$T/n.out" restack 19
has "$T/n.out" "restacked" "no check run and no status on the head: restacked"
[ "$(tip claude/t/n)" != "$OLD" ] && echo "  ok   pushed" || { echo "  FAIL pushed"; fails=$((fails+1)); }
rm -f "$T/checks.json"

echo "== not a claude/* branch, a draft, a clean PR: left alone"
fresh d
git -C "$R" checkout -q -b feature/x origin/main; printf '\n- [beta] **Beta** — b.\n' >> "$R/TODO.md"
git -C "$R" commit -qam "beta"; ship feature/x
git -C "$W" pull -q; printf '\n- [delta] **Delta** — d.\n' >> "$W/TODO.md"; main_commit "TODO: delta"
OLD=$(tip feature/x); pull 10 feature/x "$OLD"
prrun "$T/d.out" restack 10
has "$T/d.out" "EXIT 1" "a non-claude/* branch: exit 1"
has "$T/d.out" "is not a claude/* branch: left alone" "  says why"
lacks "$T/d.out" "COMMENT" "  says nothing on someone else's PR"
check "$(tip feature/x)" "$OLD" "  its branch untouched"
git -C "$O" branch -q claude/t/d "$OLD"
pull 11 claude/t/d "$OLD" true
prrun "$T/d2.out" restack 11
has "$T/d2.out" "a draft: \`/finish\` curates and readies it" "a draft is /finish's"
pull 12 claude/t/d "$OLD" false clean
prrun "$T/d3.out" restack 12
has "$T/d3.out" "nothing to do (GitHub says clean)" "a clean PR: nothing to do"
has "$T/d3.out" "EXIT 0" "  exit 0"

echo "== the lease, the local branch, a list conflict list-merge cannot settle, --dry-run, --all"
fresh e
branch claude/t/e; printf '\n- [beta] **Beta** — b.\n' >> "$R/TODO.md"; git -C "$R" commit -qam "beta"; ship claude/t/e
git -C "$W" pull -q; printf '\n- [delta] **Delta** — d.\n' >> "$W/TODO.md"; main_commit "TODO: delta"
OLD=$(tip claude/t/e)
pull 13 claude/t/e "$(git -C "$R" rev-parse origin/main)"   # GitHub's head is not origin's tip
prrun "$T/e.out" restack 13
has "$T/e.out" "EXIT 2" "a head origin no longer has: not now, exit 2"
lacks "$T/e.out" "COMMENT" "  nothing said"
pull 13 claude/t/e "$OLD"
prrun "$T/e1.out" restack 13 --dry-run
has "$T/e1.out" "would push ${OLD:0:8}" "--dry-run says what it would push"
check "$(tip claude/t/e)" "$OLD" "  and pushes nothing"
lacks "$T/e1.out" "COMMENT" "  nor comments"
git -C "$R" checkout -q claude/t/e; printf 'y = 1\n' > "$R/more.py"; git -C "$R" add -A; git -C "$R" commit -qm "more"
git -C "$R" checkout -q --detach
prrun "$T/e2.out" restack 13
has "$T/e2.out" "holds commits the PR's head lacks" "a local branch past the head: refused"
check "$(tip claude/t/e)" "$OLD" "  origin untouched"
git -C "$R" update-ref refs/heads/claude/t/e "$OLD"
# the same item edited on both sides: list-merge's conflict stops the rebase
branch claude/t/f
sed -i.bak 's/a\.$/a, the branch./' "$R/TODO.md" && rm -f "$R/TODO.md.bak"; git -C "$R" commit -qam "alpha, branch"; ship claude/t/f
git -C "$W" pull -q; sed -i.bak 's/a\.$/a, main./' "$W/TODO.md" && rm -f "$W/TODO.md.bak"; main_commit "alpha, main"
FOLD=$(tip claude/t/f); pull 14 claude/t/f "$FOLD"
prrun "$T/f.out" restack 14
has "$T/f.out" "the rebase onto origin/main stopped in TODO.md" "one item edited on both sides: the rebase stops, refused"
check "$(tip claude/t/f)" "$FOLD" "  origin untouched"
check "$(git -C "$R" worktree list | wc -l | tr -d ' ')" 1 "  the scratch worktree is gone after a stopped rebase"
pull 15 feature/z "$FOLD"
prrun "$T/all.out" restack --all
has "$T/all.out" "#13 claude/t/e: restacked" "--all restacks the dirty claude/* PR"
has "$T/all.out" "#14 claude/t/f: refused" "  and reports the one it refuses"
lacks "$T/all.out" "feature/z" "  and never looks at another branch's PR"

echo "== no list-merge driver in this clone: not judged"
fresh g
git -C "$R" config --unset merge.union.driver
branch claude/t/g; printf '\n- [beta] **Beta** — b.\n' >> "$R/TODO.md"; git -C "$R" commit -qam "beta"; ship claude/t/g
git -C "$W" pull -q; printf '\n- [delta] **Delta** — d.\n' >> "$W/TODO.md"; main_commit "TODO: delta"
OLD=$(tip claude/t/g); pull 16 claude/t/g "$OLD"
prrun "$T/g.out" restack 16
has "$T/g.out" "merge.union.driver is not list-merge" "a clone without the driver: refused to judge"
has "$T/g.out" "EXIT 2" "  exit 2, nothing said"
check "$(tip claude/t/g)" "$OLD" "  origin untouched"

echo
[ "$fails" = 0 ] && echo "restack: all passed" || echo "restack: $fails failed"
[ "$fails" = 0 ]
