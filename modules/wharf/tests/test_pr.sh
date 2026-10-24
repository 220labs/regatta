#!/usr/bin/env bash
# Tests for bin/pr's stray check: ready and merge refuse a PR that changes a path the branch's
# `<branch>-raw` never changed. The fixture replays ec782b3 (2026-10-11): main gains docs after
# the branch forks, /finish rebuilds with `reset --soft origin/main`, and the commit deletes them.
# A throwaway repo and origin; GitHub faked; no network.   bash modules/wharf/tests/test_pr.sh
set -u
unset CLAUDE_UNATTENDED   # an unattended /finish runs this check too; the cases set it themselves
B="$(cd "$(dirname "$0")/../libexec" && pwd)"   # pr sits outside bin/, reached as `regatta pr` (C1)
T=$(mktemp -d); T=$(cd "$T" && pwd -P); trap 'rm -rf "$T"' EXIT
# the caller's config dir when it names one, else an empty scratch one: the core is the one beside this module
export REGATTA_CONFIG="${REGATTA_CONFIG:-$T/regatta-config}"; unset REGATTA_HOME REGATTA_LEGACY
fails=0
check() { if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3: expected [$2] got [$1]"; fails=$((fails+1)); fi; }
has()   { if grep -qF -- "$2" "$1"; then echo "  ok   $3"; else echo "  FAIL $3: missing [$2]"; fails=$((fails+1)); fi; }
lacks() { if grep -qF -- "$2" "$1"; then echo "  FAIL $3: found [$2]"; fails=$((fails+1)); else echo "  ok   $3"; fi; }

export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
O="$T/origin.git"; R="$T/repo"; W="$T/other"
git init -q --bare -b main "$O"
git clone -q "$O" "$R" 2>/dev/null
g() { git -C "$R" "$@"; }
mkdir -p "$R/docs" "$R/lessons"
echo base > "$R/docs/base.md"; printf 'one\n' > "$R/lessons/claude-code.md"; printf 'a\n\n\n\nz\n' > "$R/log.md"
g add -A; g commit -qm base; g push -q origin main
# the branch: one doc of its own, and the top of a file it shares with main
g checkout -q -b claude/t/topic
echo mine > "$R/docs/mine.md"; printf 'a mine\n\n\n\nz\n' > "$R/log.md"; g add -A; g commit -qm "Docs: mine"
# meanwhile another session merges two docs, a lessons section and the foot of log.md (#276)
git clone -q "$O" "$W" 2>/dev/null
echo theirs > "$W/docs/theirs-a.md"; echo theirs > "$W/docs/theirs-b.md"; printf 'one\ntwo\n' > "$W/lessons/claude-code.md"
printf 'a\n\n\n\nz theirs\n' > "$W/log.md"
git -C "$W" add -A; git -C "$W" commit -qm "Docs: theirs"; git -C "$W" push -q origin main
g fetch -q origin

run() {  # run bin/pr in the repo with GitHub faked; $1 = output file, the rest = argv
  out=$1; shift
  (cd "$R" && python3 - "$B/pr" "$@" <<'PY') > "$out" 2>&1
import importlib.machinery, importlib.util, os, sys
loader = importlib.machinery.SourceFileLoader("prmod", sys.argv[1])
spec = importlib.util.spec_from_loader("prmod", loader); pr = importlib.util.module_from_spec(spec); loader.exec_module(pr)
pr.common.token = lambda: "tok"
pr.common.repo_slug = lambda url: "o/r"
pull = {"number": 7, "title": "WIP: x", "body": "", "draft": True, "html_url": "u7", "base": {"repo": {"full_name": "o/r"}},
        "head": {"sha": os.environ.get("PR_HEAD", "")}}
pr.common.find_pr = lambda slug, name, tok=None: dict(pull)
pr.common.edit_pr = lambda slug, n, tok=None, **f: (print("EDITED") or dict(pull))
pr.common.ready_pr = lambda p, tok=None: print("READIED") or True
pr.common.merge_pr_waiting = lambda slug, n, tok=None, automerge=False: (print("MERGE CALLED") or (True, "ok"))
CARRY = sys.argv[2] == "carried"  # `pr carried`: say which PR number the flag gave; every other verb carries nothing
pr.carried = lambda *a, **k: ["CARRIED %s" % k.get("launched_via")] if CARRY else []
pr.common.api = lambda m, path, *a, **k: (print("API", m, path) or (200, {}))
if sys.argv[2] == "FAILGIT":  # every git call fails: the check must refuse, never pass
    import subprocess
    real = subprocess.run
    pr.subprocess.run = lambda a, **k: real(["false"], **k) if a[0] == "git" and "diff" in a else real(a, **k)
    sys.argv[2] = "STRAYS"
if sys.argv[2] == "STRAYS":
    print("STRAYS", pr.strays("origin/main", "claude/t/topic"))
    sys.exit(0)
sys.argv = ["pr"] + sys.argv[2:]
try:
    pr.main()
except SystemExit as e:
    print("EXIT", e.code if isinstance(e.code, int) else 1, e.code if not isinstance(e.code, int) else "")
PY
}

# no -raw (knowledge-commit, a branch /finish never curated): nothing to judge by
run "$T/none.out" STRAYS
has "$T/none.out" "STRAYS None" "no -raw: the check stands aside"

# the incident: back up to -raw, then reset --soft origin/main and commit -raw's tree
g branch -f claude/t/topic-raw HEAD
g reset -q --soft origin/main; g commit -qm "Docs: mine, curated"
check "$(g diff claude/t/topic-raw HEAD | wc -l | tr -d ' ')" 0 "step 9's proof is empty, as it was for ec782b3"
run "$T/bad.out" STRAYS
has "$T/bad.out" "'D docs/theirs-a.md'" "the stale rebuild: main's new doc reads as deleted"
has "$T/bad.out" "'D docs/theirs-b.md'" "  both of them"
has "$T/bad.out" "'M lessons/claude-code.md'" "  and main's edit to a file only main touched reads as undone"
has "$T/bad.out" "\"M log.md (main's edit undone)\"" "  and main's edit inside a file the branch also changed"
lacks "$T/bad.out" "docs/mine.md" "  the branch's own doc is not a stray"
run "$T/verb.out" strays
has "$T/verb.out" "pr: NOT clean — this PR changes 4 path(s)" "pr strays (step 9, before the push) refuses it, offline"
run "$T/fail.out" FAILGIT
has "$T/fail.out" "pr: could not judge the PR against -raw" "a git call that fails refuses — never reads as no strays"
run "$T/ready.out" ready --title t --body-file /dev/null
has "$T/ready.out" "pr: NOT readied — this PR changes 4 path(s) that claude/t/topic-raw" "pr ready refuses it"
lacks "$T/ready.out" "EDITED" "  before the PR is touched"
lacks "$T/ready.out" "READIED" "  and it stays a draft"
run "$T/merge.out" merge
has "$T/merge.out" "pr: NOT merged — " "pr merge refuses it too"
lacks "$T/merge.out" "MERGE CALLED" "  before asking GitHub to merge"
has "$T/ready.out" "git reset -q --hard claude/t/topic-raw" "  and says to rebuild from -raw, not to back the bad tree up again"
run "$T/ok.out" ready --title t --body-file /dev/null --drops-ok
has "$T/ok.out" "READIED" "--drops-ok: a PR that means it goes through"
CLAUDE_UNATTENDED=1 run "$T/un.out" ready --title t --body-file /dev/null --drops-ok
has "$T/un.out" "--drops-ok is refused unattended" "  but never in an unattended run"
lacks "$T/un.out" "READIED" "  which stays a draft"

# the step-8 way: reset to the merge-base with main, commit, rebase on origin/main
g reset -q --hard claude/t/topic-raw
g reset -q --soft "$(g merge-base main HEAD)"; g commit -qm "Docs: mine, curated"
run "$T/step9.out" strays
has "$T/step9.out" "strays: none" "step 9, before the rebase: main's newer copies are not missing yet, so nothing stray"
g rebase -q origin/main
check "$(g show HEAD:log.md | tr '\n' '|')" "a mine||||z theirs|" "  the rebase keeps both edits to the shared file"
run "$T/good.out" STRAYS
has "$T/good.out" "STRAYS []" "rebuilt from the merge-base and rebased: no strays"
run "$T/good-ready.out" ready --title t --body-file /dev/null
has "$T/good-ready.out" "READIED" "  and pr ready readies it"
PR_HEAD=$(g rev-parse HEAD) run "$T/good-merge.out" merge
has "$T/good-merge.out" "MERGE CALLED" "  and pr merge merges it"
PR_HEAD=0123456789abcdef run "$T/stale-head.out" merge
has "$T/stale-head.out" "pr: NOT merged — the PR's head 01234567 is not this HEAD" "pr merge refuses when GitHub's head is not the HEAD it judged"
lacks "$T/stale-head.out" "MERGE CALLED" "  before asking GitHub to merge"

echo "a sweep's unattended /finish may not launch a gate its own run added (autofinish-widen item 3, 2026-10-10 note)"
echo '{"checkpoint": true, "autofinish": "all"}' > "$T/wf.json"; mkdir -p "$W/.claude"; cp "$T/wf.json" "$W/.claude/workflow.json"
git -C "$W" add -A; git -C "$W" commit -qm "workflow"; git -C "$W" push -q origin main; g fetch -q origin
core() { python3 -c "import sys; sys.path.insert(0, sys.argv[1]); import branches, common; print($1)" "$B/../hooks"; }   # branches finds the core (C2)
ST="$(g rev-parse --absolute-git-dir)/claude/$(core common.AUTOFINISH_RUN)"
mkdir -p "$(dirname "$ST")"
state() { printf '{"by": "%s", "session": "%s", "ended": null}\n' "$1" "$2" > "$ST"; }
sw() { AUTOFINISH_LAUNCHER=repo CLAUDE_CODE_SESSION_ID=5e55-run "$@"; }
AF=$(core 'common.tool("autofinish") or ""')   # wharf-runs' (G1): the gate is its list
if [ -z "$AF" ]; then
  echo "  skip the gate cases: autofinish (wharf-runs) is not installed — a sweep record fails closed instead"
  state sweep 5e55-run
  sw run "$T/sw-noaf.out" ready --title t --body-file /dev/null
  has "$T/sw-noaf.out" "pr: NOT readied — this /finish was started by the autofinish sweep, and its gates could not be read (autofinish (wharf-runs) is not installed)" "no autofinish to read the gates: refused"
  lacks "$T/sw-noaf.out" "READIED" "  and it stays a draft"
else
  state sweep 5e55-run
  sw run "$T/sw-clean.out" ready --title t --body-file /dev/null
  has "$T/sw-clean.out" "READIED" "a sweep run whose curated diff touches no gate: readied"
  state brief 5e55-run
  sw run "$T/sw-bclean.out" ready --title t --body-file /dev/null
  has "$T/sw-bclean.out" "READIED" "a brief run (the yes at the brief, autofinish-exclude S7) with nothing held: readied"
  state sweep 5e55-run
  echo "  a mode launch is judged again by the held slice under the mode now (landing review 1)"
  mkdir -p "$T/mplans/ms"
  mplan() { printf '{"id": "ms", "tasks": {"t": {"branch": "%s", "mode": "%s"}}}\n' "$(g symbolic-ref --short HEAD)" "$1" > "$T/mplans/ms/plan.json"; }
  mplan yolo; state yolo 5e55-run
  PLANS_DIR="$T/mplans" sw run "$T/sw-myolo.out" ready --title t --body-file /dev/null
  has "$T/sw-myolo.out" "READIED" "a yolo launch, still yolo, no gate in the diff: readied"
  mplan default
  PLANS_DIR="$T/mplans" sw run "$T/sw-mlow.out" ready --title t --body-file /dev/null
  has "$T/sw-mlow.out" "touches a gate (held: mode default" "  the ship lowered to default since the start: held"
  lacks "$T/sw-mlow.out" "READIED" "    and it stays a draft"
  mplan dnd; state dnd 5e55-run
  PLANS_DIR="$T/mplans" sw run "$T/sw-mdnd.out" ready --title t --body-file /dev/null
  has "$T/sw-mdnd.out" "touches a gate (held: a physical repo" "  a dnd launch: its held slice is read (here the contract has no physical: none)"
  # follow-ups item 4: with no mode now, the re-check reads the mode landing() judged the start by, never a bare by: yolo
  mkdir -p "$T/noplans"
  state yolo 5e55-run
  PLANS_DIR="$T/noplans" sw run "$T/sw-bare.out" ready --title t --body-file /dev/null
  has "$T/sw-bare.out" "touches a gate (held: mode default" "a mode-less by: yolo run with no eff_mode (landing() gave it no standing yes): held"
  printf '{"by": "yolo", "session": "5e55-run", "ended": null, "eff_mode": "yolo"}\n' > "$ST"
  PLANS_DIR="$T/noplans" sw run "$T/sw-e12.out" ready --title t --body-file /dev/null
  has "$T/sw-e12.out" "READIED" "  …with eff_mode yolo (E12's standing yes, judged at the start): readied"
  printf '{"by": "yolo", "session": "5e55-run", "ended": null, "eff_mode": "yolo"}\n' > "$ST"; mplan default
  PLANS_DIR="$T/mplans" sw run "$T/sw-e12low.out" ready --title t --body-file /dev/null
  has "$T/sw-e12low.out" "touches a gate (held: mode default" "  …but a mode set since is the mode now: held"
  # a ship launch (the keel's yes): a mode-less ship reads `default` from branch_mode, so the re-check takes
  # landing()'s eff_mode, not the plain fallback (the follow-ups landing review)
  printf '{"by": "ship", "session": "5e55-run", "ended": null, "eff_mode": "yolo"}\n' > "$ST"; mplan default
  PLANS_DIR="$T/mplans" sw run "$T/sw-ship.out" ready --title t --body-file /dev/null
  has "$T/sw-ship.out" "READIED" "a ship launch on a ship with no landing mode, judged yolo at the start: readied"
  printf '{"by": "ship", "session": "5e55-run", "ended": null, "eff_mode": "yolo"}\n' > "$ST"; mplan ask
  PLANS_DIR="$T/mplans" sw run "$T/sw-shipask.out" ready --title t --body-file /dev/null
  has "$T/sw-shipask.out" "touches a gate (held: mode ask" "  …but a ship set to ask since: held"
  state sweep 5e55-run
  mkdir -p "$R/hooks"; echo x > "$R/hooks/x.py"; g add -A; g commit -qm "Fix: a hook, in step 1"; g branch -f claude/t/topic-raw HEAD
  sw run "$T/sw-ready.out" ready --title t --body-file /dev/null
  has "$T/sw-ready.out" "pr: NOT readied — this /finish was started by the autofinish sweep, and the curated diff touches a gate (hooks/x.py)" "the run's own hook edit: pr ready refuses"
  lacks "$T/sw-ready.out" "READIED" "  and it stays a draft"
  PR_HEAD=$(g rev-parse HEAD) sw run "$T/sw-merge.out" merge
  has "$T/sw-merge.out" "pr: NOT merged — this /finish was started by the autofinish sweep" "  pr merge refuses it too"
  has "$T/sw-merge.out" "API POST /repos/o/r/issues/7/labels" "  and labels the ready PR hold, so automerge leaves it"
  has "$T/sw-merge.out" "the PR is labelled \`hold\`, so automerge leaves it" "  and says so"
  state brief 5e55-run
  sw run "$T/sw-brief.out" ready --title t --body-file /dev/null
  has "$T/sw-brief.out" "touches a gate (held: the launcher's own gate (hooks/x.py))" "a brief run is judged by brief_held: the launcher's own gate holds it"
  lacks "$T/sw-brief.out" "READIED" "  and it stays a draft"
  state yolo 5e55-run
  sw run "$T/sw-yolo.out" ready --title t --body-file /dev/null
  has "$T/sw-yolo.out" "pr: NOT readied — this /finish was started by the autofinish sweep" "a sweep-started yolo retry is held to the same gate"
  state dnd 5e55-run
  sw run "$T/sw-dnd.out" ready --title t --body-file /dev/null
  has "$T/sw-dnd.out" "the curated diff touches a gate (hooks/x.py)" "a dnd launch is held to the same gate (landing review 1)"
  lacks "$T/sw-merge.out" "MERGE CALLED" "  before asking GitHub"
  state typed 5e55-run
  sw run "$T/sw-typed.out" ready --title t --body-file /dev/null
  has "$T/sw-typed.out" "READIED" "a /finish the owner typed launches a gate as before"
  state sweep 01d-run
  sw run "$T/sw-old.out" ready --title t --body-file /dev/null
  has "$T/sw-old.out" "READIED" "an earlier sweep run's record does not bind this session"
  state sweep 5e55-run
  AUTOFINISH_LAUNCHER=repo CLAUDE_CODE_SESSION_ID= run "$T/sw-noid.out" ready --title t --body-file /dev/null
  has "$T/sw-noid.out" "pr: NOT readied — this /finish was started by the autofinish sweep" "no session id to compare: judged, fail closed"
  echo "  a sibling repo /finish launches: the run's record is in the worktree its transcript started in"
  mkdir -p "$T/runwt" "$T/cfg/projects/x"; git -C "$T/runwt" init -q
  mkdir -p "$(git -C "$T/runwt" rev-parse --absolute-git-dir)/claude"
  mv "$ST" "$(git -C "$T/runwt" rev-parse --absolute-git-dir)/claude/"
  printf '{"type":"x"}\n{"cwd": "%s"}\n' "$T/runwt" > "$T/cfg/projects/x/5e55-run.jsonl"
  CLAUDE_CONFIG_DIR="$T/cfg" sw run "$T/sw-sib.out" ready --title t --body-file /dev/null
  has "$T/sw-sib.out" "pr: NOT readied — this /finish was started by the autofinish sweep" "  pr ready in the sibling refuses the gate"
  CLAUDE_CONFIG_DIR="$T/cfg" AUTOFINISH_LAUNCHER=repo CLAUDE_CODE_SESSION_ID=0ther run "$T/sw-sib2.out" ready --title t --body-file /dev/null
  has "$T/sw-sib2.out" "READIED" "  another session's transcript binds nothing"
fi
rm -f "$ST"

echo "pr carried --launched-via N (rename S4, M6): the old spelling --landed-via is an alias until S8"
run "$T/cv-new.out" carried --launched-via 42
has "$T/cv-new.out" "CARRIED 42" "--launched-via N names the merged PR"
run "$T/cv-old.out" carried --landed-via '#42'
has "$T/cv-old.out" "CARRIED 42" "  --landed-via #N, the old spelling, still does (a /finish older than S4 says it)"
run "$T/cv-bad.out" carried --landed-via x
has "$T/cv-bad.out" "pr: --landed-via needs a PR number, got x" "  and its refusal names the flag it was given"
run "$T/cv-none.out" carried
has "$T/cv-none.out" "CARRIED None" "  no flag: nothing merged to check against"
[ $fails -eq 0 ] && echo "test_pr: all passed" || { echo "test_pr: $fails failed"; exit 1; }
