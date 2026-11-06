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
        if m.group(2) == "status":   # statuses.json: sha -> [{"context", "state"}]
            return 200, {"statuses": load("statuses.json", {}).get(m.group(1), [])}
        if st == "none":   # a head GitHub never ran a workflow on (a PR that conflicts runs none)
            return 200, {"check_runs": []}
        if isinstance(st, dict):   # a finished run with its start and its Actions run: {"conclusion", "started", "run"}
            runs = [{"name": "check", "status": "completed", "conclusion": st["conclusion"], "started_at": st["started"],
                     "details_url": f"https://github.com/o/r/actions/runs/{st['run']}/job/1"}]
        elif st == "automerge-red":   # a red advisory run beside a green check: not a required one
            runs = [{"name": "automerge", "status": "completed", "conclusion": "failure"},
                    {"name": "check", "status": "completed", "conclusion": "success"}]
        elif st is None:
            runs = [{"name": "check", "status": "completed", "conclusion": "success"}]
        else:
            runs = [{"name": "check", "status": "in_progress" if st == "in_progress" else "completed",
                     "conclusion": None if st == "in_progress" else st}]
        name = re.search(r"check_name=([^&]+)", path)
        return 200, {"check_runs": [r for r in runs if not name or r["name"] == name.group(1)]}
    if method == "GET" and path.endswith("/protection/required_status_checks"):
        ctxs = load("contexts.json", None)   # else hidden from the token: ["check"]
        return (200, {"contexts": ctxs}) if ctxs else (404, None)
    m = re.match(r"/repos/o/r/actions/runs/(\d+)/rerun-failed-jobs$", path)
    if method == "POST" and m:
        if os.path.exists(os.path.join(T, "rerun-refused")):
            print("RERUN-REFUSED", m.group(1))
            return 403, {"message": "Resource not accessible by integration"}
        print("RERUN", m.group(1))
        return 201, {}
    m = re.match(r"/repos/o/r/actions/runs/(\d+)$", path)
    if method == "GET" and m:   # the run's creation, from checks.json's "created" of the run with that id
        runs = [v for v in list(load("checks.json", {}).values()) + list(load("status-runs.json", {}).values())
                if isinstance(v, dict) and str(v.get("run")) == m.group(1)]
        if not runs or not runs[0].get("created"):
            return 404, None
        return 200, {"id": int(m.group(1)), "created_at": runs[0]["created"], "status": runs[0].get("run_status", "completed"),
                     "conclusion": runs[0].get("run_conclusion", "failure")}
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
        text = body["body"].split("\n", 1)[1] if body["body"].startswith("<!--") else body["body"]
        print("COMMENT", m.group(1), text[:200].replace("\n", " "))
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
  printf 'r%s\n' 1 2 3 4 5 6 7 8 9 10 11 12 > "$R/README.md"
  git -C "$R" add -A; git -C "$R" commit -qm base; git -C "$R" push -q origin main
  "$LM" install "$R" --here > /dev/null   # this copy, the one pr's carry runs
  git clone -q "$O" "$W" 2>/dev/null
  rm -f "$T/pulls.json" "$T/comments.json" "$T/checks.json" "$T/contexts.json" "$T/statuses.json" "$T/status-runs.json" "$T/rerun-refused"
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
has "$T/c.out" "refused — a code conflict: code.py conflicts under git's plain merge" "names the code file"
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
has "$T/i1b.out" "red (check): when its run was made cannot be read, and no Actions run to rerun" "a red required check, no start, no run: left"
check "$(tip claude/t/i)" "$OLD" "  origin untouched"
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

echo "== #434's shape: DIRTY on a CHANGELOG line, a README hunk each side git merges clean: restacked, carried"
fresh k
branch claude/t/k
printf '# Changelog\n\n## Unreleased\n\n- base line\n- branch line\n' > "$R/modules/m/CHANGELOG.md"
sed -i.bak 's/^r10$/r10, the branch/' "$R/README.md" && rm -f "$R/README.md.bak"
git -C "$R" commit -qam "m: branch line, README"; ship claude/t/k
git -C "$W" pull -q; printf '# Changelog\n\n## Unreleased\n\n- base line\n- main line\n' > "$W/modules/m/CHANGELOG.md"
sed -i.bak 's/^r2$/r2, main/' "$W/README.md" && rm -f "$W/README.md.bak"; main_commit "m: main line, README"
OLD=$(tip claude/t/k); pull 20 claude/t/k "$OLD"
prrun "$T/k.out" restack 20
has "$T/k.out" "EXIT 0" "exit 0"
has "$T/k.out" "restacked — pushed ${OLD:0:8}" "  pushed"
has "$T/k.out" "list-merge: modules/m/CHANGELOG.md; git's plain merge: README.md" "  says which merge took which path"
NEW=$(tip claude/t/k)
check "$(git -C "$O" show "$NEW:README.md" | sed -n '2p;10p' | tr '\n' '|')" "r2, main|r10, the branch|" "  README.md holds both hunks"
check "$(git -C "$O" show "$NEW:modules/m/CHANGELOG.md" | grep -c '^- ')" 3 "  CHANGELOG.md holds base, branch and main lines"
prrun "$T/k2.out" carry "$OLD" "$NEW"
has "$T/k2.out" "CARRY the patch is ${OLD:0:8}'s, list files aside (modules/m/CHANGELOG.md); README.md by its own lines" "pr carry: carried, README.md judged by its lines"

echo "== the same with README hunks that overlap: refused, with a finding"
fresh l
branch claude/t/l
printf '# Changelog\n\n## Unreleased\n\n- base line\n- branch line\n' > "$R/modules/m/CHANGELOG.md"
sed -i.bak 's/^r5$/r5, the branch/' "$R/README.md" && rm -f "$R/README.md.bak"
git -C "$R" commit -qam "m: branch line, README"; ship claude/t/l
git -C "$W" pull -q; printf '# Changelog\n\n## Unreleased\n\n- base line\n- main line\n' > "$W/modules/m/CHANGELOG.md"
sed -i.bak 's/^r5$/r5, main/' "$W/README.md" && rm -f "$W/README.md.bak"; main_commit "m: main line, README"
OLD=$(tip claude/t/l); pull 21 claude/t/l "$OLD"
prrun "$T/l.out" restack 21
has "$T/l.out" "EXIT 1" "exit 1"
has "$T/l.out" "refused — a code conflict: README.md conflicts under git's plain merge" "  names README.md"
lacks "$T/l.out" "CHANGELOG.md conflicts" "  not the list file"
has "$T/l.out" "COMMENT 21 **pr restack: not restacked.**" "  the finding goes on the PR"
check "$(tip claude/t/l)" "$OLD" "  origin untouched"
check "$(git -C "$R" worktree list | wc -l | tr -d ' ')" 1 "  the scratch worktree is gone"

echo "== a both-sides path under a merge driver GitHub never runs: refused before the rebase"
fresh q
printf 'TODO.md merge=union\nCHANGELOG.md merge=union\nREADME.md merge=union\n' > "$W/.gitattributes"; git -C "$W" pull -q; main_commit "attrs"
git -C "$R" fetch -q origin
branch claude/t/q; sed -i.bak 's/^r10$/r10, b/' "$R/README.md" && rm -f "$R/README.md.bak"
printf '\n- [beta] **Beta** — b.\n' >> "$R/TODO.md"; git -C "$R" commit -qam "b"; ship claude/t/q
git -C "$W" pull -q; sed -i.bak 's/^r2$/r2, m/' "$W/README.md" && rm -f "$W/README.md.bak"
printf '\n- [delta] **Delta** — d.\n' >> "$W/TODO.md"; main_commit "m"
OLD=$(tip claude/t/q); pull 22 claude/t/q "$OLD"
prrun "$T/q.out" restack 22
has "$T/q.out" "README.md (merge=union) changed on both sides, with a merge attribute git's plain merge does not have" "a union README: refused"
check "$(tip claude/t/q)" "$OLD" "  origin untouched"

echo "== the carry: a context-only shift in code carries; a changed line, a space, a moved line do not"
fresh s
printf 'def a():\n    pass\n\n\ndef b():\n    return 1\n' > "$W/lib.py"; git -C "$W" pull -q; main_commit "lib"
git -C "$R" fetch -q origin
branch claude/t/s; sed -i.bak 's/return 1/return 2/' "$R/lib.py" && rm -f "$R/lib.py.bak"
printf '\n- [beta] **Beta** — b.\n' >> "$R/TODO.md"; git -C "$R" commit -qam "lib: two"; ship claude/t/s
git -C "$W" pull -q; printf 'import os\n\n\n' | cat - "$W/lib.py" > "$W/lib.new" && mv "$W/lib.new" "$W/lib.py"
printf '\n- [delta] **Delta** — d.\n' >> "$W/TODO.md"; main_commit "lib: import"
OLD=$(tip claude/t/s); pull 23 claude/t/s "$OLD"
prrun "$T/s.out" restack 23
has "$T/s.out" "restacked — pushed ${OLD:0:8}" "a code hunk whose context main moved: restacked"
NEW=$(tip claude/t/s)
check "$(git -C "$O" show "$NEW:lib.py" | sed -n '1p;9p' | tr '\n' '|')" "import os|    return 2|" "  main's import and the branch's line"
prrun "$T/s1.out" carry "$OLD" "$NEW"
has "$T/s1.out" "CARRY" "  pr carry: carried"
has "$T/s1.out" "lib.py by its own lines" "  lib.py judged by its lines"
# the same commit replayed, its added line changed (an amend keeps author, date and message)
git -C "$R" checkout -q --detach "$NEW"; sed -i.bak 's/return 2/return 3/' "$R/lib.py" && rm -f "$R/lib.py.bak"
git -C "$R" commit -qa --amend --no-edit; A1=$(git -C "$R" rev-parse HEAD)
prrun "$T/s2.out" carry "$OLD" "$A1"
has "$T/s2.out" "RUN lib.py differs between the two patches (its added or removed lines)" "a non-list file whose added line changed: no carry"
git -C "$R" checkout -q --detach "$NEW"; sed -i.bak 's/return 2/return 2 /' "$R/lib.py" && rm -f "$R/lib.py.bak"
git -C "$R" commit -qa --amend --no-edit; A2=$(git -C "$R" rev-parse HEAD)
prrun "$T/s3.out" carry "$OLD" "$A2"
has "$T/s3.out" "RUN lib.py differs" "  a space added inside the line: no carry (never patch-id)"
git -C "$R" checkout -q --detach "$NEW"
python3 - "$R/lib.py" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
t = t.replace("    return 2\n", "    return 1\n").replace("    pass\n", "    return 2\n")
open(p, "w").write(t)
PY
git -C "$R" commit -qam "lib: the line in a()"; A3=$(git -C "$R" rev-parse HEAD)
prrun "$T/s4.out" carry "$OLD" "$A3"
has "$T/s4.out" "RUN lib.py differs between the two patches" "  a later commit that moves the change: no carry"
git -C "$R" checkout -q --detach

echo "== the allowlist is a list file: DIRTY on it, restacked by the set merge, carried"
fresh u
mkdir -p "$W/.helloworld"; printf 'a.txt\nm.txt\n' > "$W/.helloworld/allowlist.txt"
printf 'TODO.md merge=union\nCHANGELOG.md merge=union\n.helloworld/allowlist.txt merge=union\n' > "$W/.gitattributes"
git -C "$W" pull -q; main_commit "allowlist"; git -C "$R" fetch -q origin
branch claude/t/u; printf 'a.txt\nb.txt\nm.txt\n' > "$R/.helloworld/allowlist.txt"
printf 'b\n' > "$R/b.txt"; git -C "$R" add -A; git -C "$R" commit -qm "b"; ship claude/t/u
git -C "$W" pull -q; printf 'a.txt\nc.txt\nm.txt\n' > "$W/.helloworld/allowlist.txt"
printf 'c\n' > "$W/c.txt"; main_commit "c"
OLD=$(tip claude/t/u); pull 24 claude/t/u "$OLD"
prrun "$T/u.out" restack 24
has "$T/u.out" "restacked — pushed ${OLD:0:8}" "DIRTY on the allowlist: restacked"
has "$T/u.out" "list-merge: .helloworld/allowlist.txt" "  as a list file"
NEW=$(tip claude/t/u)
check "$(git -C "$O" show "$NEW:.helloworld/allowlist.txt" | sort | tr '\n' ' ')" "a.txt b.txt c.txt m.txt " "  both new lines kept"
prrun "$T/u1.out" carry "$OLD" "$NEW"
has "$T/u1.out" ".helloworld/allowlist.txt by its own lines" "  pr carry: judged by its lines, carried"

echo "== red on a base main has moved past: restacked to a new tip, never a rerun; then a rerun, once"
fresh v
branch claude/t/v; printf 'x = 2\n' > "$R/code.py"; git -C "$R" commit -qam "x"; ship claude/t/v
git -C "$W" pull -q; printf 'y = 1\n' > "$W/other.py"; main_commit "other: the fix"
OLD=$(tip claude/t/v); pull 25 claude/t/v "$OLD" false blocked
printf '{"%s": {"conclusion": "failure", "started": "2000-01-01T00:00:00Z", "created": "2000-01-01T00:00:00Z", "run": 77}}' "$OLD" > "$T/checks.json"
prrun "$T/v.out" restack 25
has "$T/v.out" "EXIT 0" "exit 0"
has "$T/v.out" "restacked — its required check (check) failed on a base main has since moved past" "  restacked"
lacks "$T/v.out" "RERUN" "  never a rerun"
NEW=$(tip claude/t/v)
[ "$NEW" != "$OLD" ]; check "$?" 0 "  a new tip"
git -C "$O" merge-base --is-ancestor main "$NEW"; check "$?" 0 "  onto main's tip"
has "$T/v.out" "COMMENT 25 **pr restack:** its required check (check) failed on a base main has since moved past" "  the PR is told (before the push)"
prrun "$T/v0.out" carry "$OLD" "$NEW"
has "$T/v0.out" "CARRY" "  (pr carry would carry, but check.yml carries only a green)"
# red again on the tip the red road made, main not moved since: its failed jobs rerun, once
git -C "$R" fetch -q origin; pull 25 claude/t/v "$NEW" false blocked
printf '{"%s": {"conclusion": "failure", "started": "2999-01-01T00:00:00Z", "created": "2999-01-01T00:00:00Z", "run": 78}}' "$NEW" > "$T/checks.json"
prrun "$T/v1.out" restack 25
has "$T/v1.out" "RERUN 78" "red after main last moved: its failed jobs rerun"
has "$T/v1.out" "rerun — the failed jobs of run 78 (check): its run was made after main last moved" "  says so"
check "$(tip claude/t/v)" "$NEW" "  the tip stays"
prrun "$T/v2.out" restack 25
lacks "$T/v2.out" "RERUN" "  once a run"
has "$T/v2.out" "after its rerun was asked: its own fix comes first" "  then the red is the PR's own"
# main moves again: the tip the red road made is never red-restacked again
git -C "$W" pull -q; printf 'z = 1\n' > "$W/more.py"; main_commit "more"
printf '{"%s": {"conclusion": "failure", "started": "2000-01-01T00:00:00Z", "created": "2000-01-01T00:00:00Z", "run": 79}}' "$NEW" > "$T/checks.json"
prrun "$T/v3.out" restack 25
check "$(tip claude/t/v)" "$NEW" "a red-restacked tip, main moved again: not restacked again"
lacks "$T/v3.out" "RERUN" "  nor its stale run rerun (it would replay the merge main moved past)"
has "$T/v3.out" "on a tip a red restack made already: its own fix comes first" "  it says why"

echo "== red: a hand rerun after main's fix still tests the old merge: restacked by the run's creation, not the attempt's start"
fresh w
branch claude/t/w; printf 'x = 2\n' > "$R/code.py"; git -C "$R" commit -qam "x"; ship claude/t/w
git -C "$W" pull -q; printf 'y = 1\n' > "$W/other.py"; main_commit "other: the fix"
OLD=$(tip claude/t/w); pull 26 claude/t/w "$OLD" false blocked
printf '{"%s": {"conclusion": "failure", "started": "2999-01-01T00:00:00Z", "created": "2000-01-01T00:00:00Z", "run": 80}}' "$OLD" > "$T/checks.json"
prrun "$T/w.out" restack 26
has "$T/w.out" "restacked — its required check (check) failed on a base main has since moved past" "attempt started after, run made before main moved: restacked"
lacks "$T/w.out" "RERUN" "  never a rerun"
[ "$(tip claude/t/w)" != "$OLD" ] && echo "  ok   a new tip" || { echo "  FAIL a new tip"; fails=$((fails+1)); }
# a rerun GitHub refuses: said on the PR, never asked again, never read as done
NEW=$(tip claude/t/w); git -C "$R" fetch -q origin; pull 26 claude/t/w "$NEW" false blocked
printf '{"%s": {"conclusion": "failure", "started": "2999-01-01T00:00:00Z", "created": "2999-01-01T00:00:00Z", "run": 81}}' "$NEW" > "$T/checks.json"
touch "$T/rerun-refused"
prrun "$T/w1.out" restack 26
has "$T/w1.out" "the rerun of run 81 was refused (HTTP 403); said on the PR, not asked again" "a refused rerun: said"
has "$T/w1.out" "COMMENT 26 **pr restack:** GitHub refused the rerun of run 81" "  on the PR too"
has "$T/w1.out" "EXIT 1" "  exit 1"
prrun "$T/w2.out" restack 26
lacks "$T/w2.out" "RERUN" "  not asked again"
rm -f "$T/rerun-refused" "$T/checks.json"

echo "== red: a running required check, a cancelled run, an unreadable run, a push that fails: no push, no loop"
fresh rr
branch claude/t/rr; printf 'x = 2\n' > "$R/code.py"; git -C "$R" commit -qam "x"; ship claude/t/rr
git -C "$W" pull -q; printf 'y = 1\n' > "$W/other.py"; main_commit "other"
OLD=$(tip claude/t/rr); pull 30 claude/t/rr "$OLD" false blocked
printf '["check", "ci/circleci: check-linux"]' > "$T/contexts.json"
printf '{"%s": [{"context": "ci/circleci: check-linux", "state": "pending"}]}' "$OLD" > "$T/statuses.json"
printf '{"%s": {"conclusion": "failure", "started": "2000-01-01T00:00:00Z", "created": "2000-01-01T00:00:00Z", "run": 90}}' "$OLD" > "$T/checks.json"
prrun "$T/rr1.out" restack 30
has "$T/rr1.out" "nothing to do" "check red, check-linux still running: nothing yet (a push would cancel it)"
check "$(tip claude/t/rr)" "$OLD" "  origin untouched"
rm -f "$T/contexts.json" "$T/statuses.json"
printf '{"%s": {"conclusion": "cancelled", "started": "2000-01-01T00:00:00Z", "created": "2000-01-01T00:00:00Z", "run": 91}}' "$OLD" > "$T/checks.json"
prrun "$T/rr2.out" restack 30
lacks "$T/rr2.out" "RERUN" "a cancelled run: never rerun"
check "$(tip claude/t/rr)" "$OLD" "  nor restacked"
printf '{"%s": {"conclusion": "failure", "started": "2000-01-01T00:00:00Z", "run": 92}}' "$OLD" > "$T/checks.json"
prrun "$T/rr3.out" restack 30
has "$T/rr3.out" "not now — a red run's making could not be read" "a run whose making will not read: not now, never the attempt's start"
has "$T/rr3.out" "EXIT 2" "  exit 2"
printf '{"%s": {"conclusion": "failure", "started": "2000-01-01T00:00:00Z", "created": "2000-01-01T00:00:00Z", "run": 93}}' "$OLD" > "$T/checks.json"
GD="$R/.git"; printf '#!/bin/sh\necho "guard: refused" >&2\nexit 1\n' > "$GD/hooks/pre-push"; chmod +x "$GD/hooks/pre-push"
prrun "$T/rr4.out" restack 30
has "$T/rr4.out" "the push was refused" "a push the guard refuses: not pushed"
check "$(grep -c 'pushing as' "$T/rr4.out")" 1 "  one mark comment"
prrun "$T/rr5.out" restack 30
has "$T/rr5.out" "a red restack of this tip was tried already" "the next pass: tried already"
lacks "$T/rr5.out" "COMMENT" "  no comment a tick"
rm -f "$GD/hooks/pre-push" "$T/checks.json"

echo "== red on a head-tested status: judged by the fork; its rerun running: nothing; no driver needed"
fresh hs
branch claude/t/hs; printf 'x = 2\n' > "$R/code.py"; git -C "$R" commit -qam "x"; ship claude/t/hs
git -C "$W" pull -q; printf 'y = 1\n' > "$W/other.py"; main_commit "the Linux fix"
git -C "$R" config --unset merge.union.driver   # a red PR with no list file needs no driver
OLD=$(tip claude/t/hs); pull 31 claude/t/hs "$OLD" false blocked
printf '["check", "ci/circleci: check-linux"]' > "$T/contexts.json"
printf '{"%s": [{"context": "ci/circleci: check-linux", "state": "failure", "target_url": "https://github.com/o/r/actions/runs/95"}]}' "$OLD" > "$T/statuses.json"
printf '{"x": {"run": 95, "created": "2999-01-01T00:00:00Z", "run_status": "in_progress"}}' > "$T/status-runs.json"
prrun "$T/hs1.out" restack 31
has "$T/hs1.out" "nothing to do" "check-linux red, its rerun running: nothing (a push would cancel it)"
check "$(tip claude/t/hs)" "$OLD" "  origin untouched"
printf '{"x": {"run": 95, "created": "2999-01-01T00:00:00Z"}}' > "$T/status-runs.json"
prrun "$T/hs2.out" restack 31
has "$T/hs2.out" "restacked — its required check (ci/circleci: check-linux) failed on a base main has since moved past" "a head-tested red on a head behind main, run made after main landed: restacked, never rerun"
lacks "$T/hs2.out" "RERUN" "  no rerun"
lacks "$T/hs2.out" "merge.union.driver" "  no driver asked for"
NEW=$(tip claude/t/hs); git -C "$R" fetch -q origin; pull 31 claude/t/hs "$NEW" false blocked
printf '{"%s": [{"context": "ci/circleci: check-linux", "state": "failure", "target_url": "https://github.com/o/r/actions/runs/96"}]}' "$NEW" > "$T/statuses.json"
printf '{"x": {"run": 96, "created": "2000-01-01T00:00:00Z"}}' > "$T/status-runs.json"
prrun "$T/hs3.out" restack 31
has "$T/hs3.out" "RERUN 96" "the same red on main's tip: its failed jobs rerun"
has "$T/hs3.out" "its head is on main's tip" "  says why"
printf '{"%s": [{"context": "ci/circleci: check-linux", "state": "failure", "target_url": "https://github.com/o/r/actions/runs/97"}]}' "$NEW" > "$T/statuses.json"
printf '{"x": {"run": 97, "created": "2000-01-01T00:00:00Z", "run_conclusion": "cancelled"}}' > "$T/status-runs.json"
prrun "$T/hs4.out" restack 31
lacks "$T/hs4.out" "RERUN" "a check-linux failure whose run was cancelled: never rerun (the landing review)"
check "$(tip claude/t/hs)" "$NEW" "  nor restacked"
rm -f "$T/contexts.json" "$T/statuses.json" "$T/status-runs.json"

echo "== the carry refuses a hand-resolved conflict and a moved line whose lines are the same"
fresh x
printf 'A = 1\n' > "$W/k.py"; printf 'def a():\n    pass\n\n\ndef b():\n    pass\n' > "$W/v.py"
git -C "$W" pull -q; main_commit "k, v"; git -C "$R" fetch -q origin
branch claude/t/x; printf 'A = 1\nP = A + 1\n' > "$R/k.py"; git -C "$R" commit -qam "P"; ship claude/t/x
B1=$(tip claude/t/x)
git -C "$W" pull -q; printf 'B = 2\n' > "$W/k.py"; main_commit "k: no A"; git -C "$R" fetch -q origin
git -C "$R" checkout -q --detach origin/main; printf 'B = 2\nP = A + 1\n' > "$R/k.py"
GIT_AUTHOR_DATE="$(git -C "$R" log -1 --format=%ad --date=raw "$B1")" git -C "$R" commit -qam "P"; H1=$(git -C "$R" rev-parse HEAD)
prrun "$T/x1.out" carry "$B1" "$H1"
has "$T/x1.out" "RUN k.py differs between the two patches (not what a clean merge onto main's copy makes)" "a conflict resolved by hand, the PR's lines kept: no carry"
git -C "$R" checkout -q --detach "$B1"; printf 'def a():\n    pass\n    validate(x)\n\n\ndef b():\n    pass\n' > "$R/v.py"
git -C "$R" commit -qam "v"; B2=$(git -C "$R" rev-parse HEAD)
printf 'def a():\n    pass\n\n\ndef b():\n    pass\n    validate(x)\n' > "$R/v.py"; git -C "$R" commit -qa --amend --no-edit; H2=$(git -C "$R" rev-parse HEAD)
prrun "$T/x2.out" carry "$B2" "$H2" --base "$B1"
has "$T/x2.out" "RUN v.py differs between the two patches (not what a clean merge" "an amend that moves a line, the same lines: no carry"
git -C "$R" checkout -q --detach

echo "== the allowlist: a path both sides list, a path main took off; a union main adds after the fork is read"
fresh y
mkdir -p "$W/.helloworld"; printf 'a.txt\nz.txt\n' > "$W/.helloworld/allowlist.txt"
printf 'TODO.md merge=union\nCHANGELOG.md merge=union\n.helloworld/allowlist.txt merge=union\n' > "$W/.gitattributes"
git -C "$W" pull -q; main_commit "allowlist"; git -C "$R" fetch -q origin
branch claude/t/y; printf 'a.txt\nb.txt\nc.txt\ny.txt\nz.txt\n' > "$R/.helloworld/allowlist.txt"; git -C "$R" commit -qam "b c y"; ship claude/t/y
git -C "$W" pull -q; printf 'a.txt\nc.txt\nx.txt\nz.txt\n' > "$W/.helloworld/allowlist.txt"; main_commit "c x"
OLD=$(tip claude/t/y); pull 27 claude/t/y "$OLD"
prrun "$T/y.out" restack 27
has "$T/y.out" "refused — the rebased patch is not the PR's: .helloworld/allowlist.txt differs" "both sides list c.txt: the PR's own +c.txt is gone, so no push"
lacks "$T/y.out" "twice" "  never a doubled line"
check "$(tip claude/t/y)" "$OLD" "  origin untouched"
fresh y2   # the repo's own shape: no attribute on the allowlist, so a plain merge conflicts there
mkdir -p "$W/.helloworld"; printf 'a.txt\nx.txt\nz.txt\n' > "$W/.helloworld/allowlist.txt"
git -C "$W" pull -q; main_commit "allowlist"; git -C "$R" fetch -q origin
branch claude/t/y2; printf 'a.txt\nx.txt\ny.txt\nz.txt\n' > "$R/.helloworld/allowlist.txt"; git -C "$R" commit -qam "y"; ship claude/t/y2
git -C "$W" pull -q; printf 'a.txt\nz.txt\n' > "$W/.helloworld/allowlist.txt"; main_commit "x private again"
OLD=$(tip claude/t/y2); pull 29 claude/t/y2 "$OLD"
prrun "$T/y2.out" restack 29
has "$T/y2.out" "restacked" "main took x.txt off the list, the branch listed y.txt beside it: restacked"
check "$(git -C "$O" show "$(tip claude/t/y2):.helloworld/allowlist.txt" | tr '\n' ' ')" "a.txt y.txt z.txt " "  x.txt stays off (union would bring it back)"
git -C "$W" fetch -q origin; git -C "$W" checkout -q --detach "$OLD"; git -C "$W" rebase -q origin/main > /dev/null 2>&1; check "$?" 1 "  a plain rebase elsewhere conflicts there, never unions"
git -C "$W" rebase --abort 2>/dev/null; git -C "$W" checkout -q main
fresh z
branch claude/t/z; printf 'r%s\n' 1 1b 2 3 4 5 6 7 8 9 10 11 12 > "$R/README.md"
printf '\n- [beta] **Beta** — b.\n' >> "$R/TODO.md"; git -C "$R" commit -qam "b"; ship claude/t/z
git -C "$W" pull -q; printf 'TODO.md merge=union\nCHANGELOG.md merge=union\nREADME.md merge=union\n' > "$W/.gitattributes"
printf 'r%s\n' 1 1m 2 3 4 5 6 7 8 9 10 11 12 > "$W/README.md"; printf '\n- [delta] **Delta** — d.\n' >> "$W/TODO.md"; main_commit "m"
OLD=$(tip claude/t/z); pull 28 claude/t/z "$OLD"
prrun "$T/z.out" restack 28
has "$T/z.out" "README.md (merge=union) changed on both sides" "a union main added after the fork: read at main's tip, refused"
check "$(tip claude/t/z)" "$OLD" "  origin untouched"
rm -f "$T/checks.json"

echo
[ "$fails" = 0 ] && echo "restack: all passed" || echo "restack: $fails failed"
[ "$fails" = 0 ]
