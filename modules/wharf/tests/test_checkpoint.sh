#!/usr/bin/env bash
# Regression test for wharf's checkpoint.py — run before saving any change to it:
#   bash modules/wharf/tests/test_checkpoint.sh
# The hook is live for EVERY open session in EVERY project the moment the file is saved (on
# 2026-09-10 a parallel session ran a half-migrated version mid-edit), so break it here.
# Throwaway repos under $TMPDIR; needs git, jq, python3. Exit 1 on any failure.
#
# The primary checkout ($R) never takes writes — PreToolUse denies them so it stays on main
# always (2026-09-15). Every session works in its own worktree instead, so most of this file
# runs against worktrees ($WA / $WB), the same way real sessions do.
set -u
MOD="$(cd "$(dirname "$0")/.." && pwd)"   # the wharf module ($M is a fixture repo further down)
HOOK="$MOD/hooks/checkpoint.py"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
# The config dir, before any case moves HOME: the caller's when it names one (an overlay's private
# values, and its `legacy` checkout where keel and autofinish are found until they move), else a
# scratch one with an owner of its own, so the closing lines have someone to address. The core is
# the one beside this module (lib/core_path.py).
if [ -z "${REGATTA_CONFIG:-}" ]; then
  export REGATTA_CONFIG="$T/regatta-config"; mkdir -p "$REGATTA_CONFIG/regatta"; echo Ada > "$REGATTA_CONFIG/regatta/owner"
fi
export REGATTA_CONFIG
unset REGATTA_HOME REGATTA_LEGACY   # the config dir decides, as for a hook
export CLAUDE_CONFIG_DIR="$T/claude-config"   # no plugin registry but the suite's own (C2's last lookup)
core() { python3 -c "import sys; sys.path.insert(0, sys.argv[1]); import checkpoint, common; $1" "$MOD/hooks"; }
# keel is a peer (G4): the D-list cases need it, and skip when it is not installed
KEEL=$(core 'print(common.tool("keel") or "")')
# …and keel's session gate: without hooks/sheep_gate.py (a copy without it)
# never_mirrored fails closed and no mirror case can pass (the scrubs' integration review)
[ -n "$KEEL" ] && [ ! -f "$(dirname "$(dirname "$KEEL")")/hooks/sheep_gate.py" ] && KEEL=
# Trees for the cases that need the module without a peer or without the core: copies, never the
# checkout itself. core-only: the core and wharf, no other module; solo: wharf alone.
mkdir -p "$T/tree-core/.claude-plugin" "$T/tree-core/modules" "$T/tree-solo/modules"
: > "$T/tree-core/.claude-plugin/marketplace.json"
cp -R "$MOD/../regatta" "$T/tree-core/modules/regatta"; cp -R "$MOD" "$T/tree-core/modules/wharf"; cp -R "$MOD" "$T/tree-solo/modules/wharf"
R="$T/repo"; mkdir -p "$R/.claude" "$T/padA" "$T/padB"
# The hook is installed user-wide and acts only where a project opted in. This repo opts in
# the way the home-automation repo does, including a live-system writer (a deploy script).
cd "$R" && git init -q -b main && printf '.claude/worktrees/\n' > .gitignore \
  && printf '%s\n' '{"checkpoint": true, "main": "main",' \
     '"live_write_regex": "scripts/(?:deploy|helpers)\\.py\\b(?![^|;&]*--check-only)"}' > .claude/workflow.json \
  && git add .gitignore .claude/workflow.json && git -c user.name=t -c user.email=t@t commit -q -m base
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
# A bare origin, so the hook's own pushes (flow A, 2026-09-22) have somewhere real to go;
# GitHub itself is never spoken to from the suite.
git init -q --bare "$T/origin.git" && git remote add origin "$T/origin.git" && git push -q origin main
export CLAUDE_HOOK_NO_GITHUB=1
# Nor the page mirror: on a Mac with the CLI and a key, every fixture D-list doc would be deployed.
# The one case that tests the mirror lifts this for its own calls, against a stub CLI.
export CLAUDE_HOOK_NO_SHEEP=1
# Nor the session's entrypoint (it once decided whether the form was owed; since 2026-10-14 the
# form is the doc's mirrored page, owed wherever a doc has D-items and the page can deploy).
unset CLAUDE_CODE_ENTRYPOINT
# Nor this Mac's memo state: the hand-over line's form and page are checked against the pins
# (bin/keel line_findings).
export MEMO_STATE_DIR="$T/memo-state" MEMO_SHEEP_STATE="$T/memo-sheep"
# The page mirror's status file (bin/sheep mirror_port): a mirror running on this Mac would
# turn the turn's 🐑 note into localhost links; the mirror case below writes its own.
export SPACESHEEP_CONFIG_DIR="$T/ss-config"
# Nor its unattended mark: run by a dispatch session, every "attended" case would be judged
# unattended and fail (four did, 2026-10-05). The unattended cases set it per call.
unset CLAUDE_UNATTENDED REGATTA_UNATTENDED
# Nor the launcher: every SessionEnd below would leave a detached bin/autofinish behind, judging
# these throwaway repos into the real dated log. The autofinish cases lift it, against a stub.
export CLAUDE_HOOK_NO_AUTOFINISH=1
R=$(pwd -P)
WA="$R/.claude/worktrees/a"
WB="$R/.claude/worktrees/b"
fails=0
# BSD stat takes -f, GNU stat -c; the GNU form fails cleanly on a Mac, so try it first.
fmode()  { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"; }

# ev <A|B> <event> [prompt] [cwd] [last_assistant_message]  — fire a hook event as session A or B
# Each event carries a nonce, the way real payloads differ (prompt ids, message text); without
# it the suite's own repeated identical events would look like the double wiring tested below.
ev() { jq -nc --arg e "$2" --arg p "${3:-}" --arg s "$T/pad$1" --arg id "sess$1-0000" --arg c "${4:-$R}" --arg m "${5:-}" --arg n "$RANDOM$RANDOM" \
  '{hook_event_name:$e,prompt:$p,scratchpad_dir:$s,session_id:$id,cwd:$c,last_assistant_message:$m,nonce:$n}' | python3 "$HOOK"; }
# tool <A|B> <tool> <input-json> [cwd]  — prints deny|allow
tool() { jq -nc --arg t "$2" --argjson i "$3" --arg id "sess$1-0000" --arg c "${4:-$R}" \
  '{hook_event_name:"PreToolUse",tool_name:$t,tool_input:$i,session_id:$id,cwd:$c}' | python3 "$HOOK" \
  | jq -r '.hookSpecificOutput.permissionDecision // "allow"' 2>/dev/null | grep . || echo allow; }
# toolreason <A|B> <tool> <input-json> [cwd]  — prints the deny reason (empty if allowed)
toolreason() { jq -nc --arg t "$2" --argjson i "$3" --arg id "sess$1-0000" --arg c "${4:-$R}" \
  '{hook_event_name:"PreToolUse",tool_name:$t,tool_input:$i,session_id:$id,cwd:$c}' | python3 "$HOOK" \
  | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2>/dev/null; }
summ() { printf '%s\n\nwhy\n' "$2" > "$T/pad$1/commit-summary.md"; }
msg() { git -C "${1:-$R}" log -1 --format=%B; }
ok() { if eval "$2"; then echo "  ok   $1"; else echo "  FAIL $1"; fails=$((fails+1)); fi; }

echo "opt-in: silent everywhere a project didn't ask for it"
# A plain folder and a repo with no workflow.json: every event prints nothing, writes allowed.
P="$T/plain"; N="$T/noopt"; mkdir -p "$P" "$N"
git -C "$N" init -q -b main && touch "$N/x" && git -C "$N" add x && git -C "$N" commit -q -m x
for d in "$P" "$N"; do
  out=$( { ev A UserPromptSubmit "hi" "$d"; ev A Stop "" "$d"; ev A SessionEnd "" "$d"; } 2>&1 )
  ok "no output at all in $(basename "$d")" '[ -z "$out" ]'
  ok "  write on its main allowed" '[ "$(tool A Edit "{\"file_path\":\"$d/x\"}" "$d")" = allow ]'
done
echo 1 > "$N/x"; ev A Stop "" "$N" >/dev/null
ok "  no checkpoint, no branch made in the non-opted repo" \
  '[ "$(git -C "$N" rev-list --count HEAD)" = 1 ] && [ "$(git -C "$N" branch --show-current)" = main ]'
mkdir -p "$N/.claude" && printf '{"checkpoint": false}' > "$N/.claude/workflow.json"
ok "checkpoint:false counts as not opted in" \
  '[ "$(tool A Edit "{\"file_path\":\"$N/x\"}" "$N")" = allow ]'
printf 'not json' > "$N/.claude/workflow.json"
ok "unreadable workflow.json counts as not opted in, silently" \
  '[ -z "$(ev A UserPromptSubmit "hi" "$N" 2>&1)" ]'
printf '{"checkpoint": true, "main": "trunk"}' > "$N/.claude/workflow.json"
git -C "$N" branch -m main trunk
ok "custom main name: write on trunk denied, reason names trunk" \
  'toolreason A Edit "{\"file_path\":\"$N/x\"}" "$N" | grep -q "stays on trunk"'
ok "no .env in the project: the recipe leaves out the .env link" \
  '! toolreason A Edit "{\"file_path\":\"$N/x\"}" "$N" | grep -q "ln -s"'
touch "$N/.env"
ok "a project with .env: the recipe includes the link" \
  'toolreason A Edit "{\"file_path\":\"$N/x\"}" "$N" | grep -q "ln -s"'
ok "no live_write_regex: a deploy-looking command is not a write" \
  '[ "$(tool A Bash "{\"command\":\"python3 scripts/deploy.py x.yaml\"}" "$N")" = allow ]'

echo "orphaned -raw backups are swept on a prompt (finish.md → Nothing to finish?)"
# GIT_COMMITTER_DATE also stamps the reflog entry, which is what the grace check reads.
GIT_COMMITTER_DATE='2020-01-01T00:00:00Z' git branch claude/old-done-raw main   # merged long ago, plain gone
git branch claude/just-merged-raw main                                          # minutes old: still the rollback
GIT_COMMITTER_DATE='2020-01-01T00:00:00Z' git branch claude/live-raw main       # its plain branch still exists
git branch claude/live main
GIT_COMMITTER_DATE='2020-01-01T00:00:00Z' git branch claude/held-raw main       # a worktree sits on it
git worktree add -q "$T/held" claude/held-raw
out=$(ev A UserPromptSubmit "morning")
ok "old, plain gone, unheld: deleted and reported" \
  '! git show-ref -q --verify refs/heads/claude/old-done-raw && echo "$out" | grep -q "old-done-raw"'
ok "within the 2 h grace: kept" 'git show-ref -q --verify refs/heads/claude/just-merged-raw'
ok "plain branch alive: kept" 'git show-ref -q --verify refs/heads/claude/live-raw'
ok "checked out in a worktree: kept" 'git show-ref -q --verify refs/heads/claude/held-raw'
GIT_COMMITTER_DATE='2020-01-01T00:00:00Z' git branch claude/second-raw main
ev A UserPromptSubmit "again" >/dev/null
ok "at most once an hour: a second prompt doesn't sweep" 'git show-ref -q --verify refs/heads/claude/second-raw'
touch -t 202001010000 .git/claude/raw-sweep; ev A UserPromptSubmit "later" >/dev/null
ok "  ...and does once the hour is up" '! git show-ref -q --verify refs/heads/claude/second-raw'
git worktree remove "$T/held"
git branch -D claude/held-raw claude/live-raw claude/live claude/just-merged-raw >/dev/null
ev A Stop >/dev/null

echo "an agent pushes its own branch and nothing else — in every folder, opted in or not"
ok "push to claude/*: allowed" \
  '[ "$(tool A Bash "{\"command\":\"git push -u origin claude/2026-09-19-topic\"}")" = allow ]'
ok "  without -u too" \
  '[ "$(tool A Bash "{\"command\":\"git push origin claude/x\"}")" = allow ]'
ok "  --force-with-lease on claude/* (/finish rewrites)" \
  '[ "$(tool A Bash "{\"command\":\"git push --force-with-lease origin claude/x\"}")" = allow ]'
ok "  a fully-qualified ref" \
  '[ "$(tool A Bash "{\"command\":\"git push origin HEAD:refs/heads/claude/x\"}")" = allow ]'
ok "bare git push: denied even on a claude/* branch" \
  '[ "$(tool A Bash "{\"command\":\"git push\"}")" = deny ]'
ok "  claude/x:main is denied" \
  '[ "$(tool A Bash "{\"command\":\"git push origin claude/x:main\"}")" = deny ]'
ok "  bare --force is denied" \
  '[ "$(tool A Bash "{\"command\":\"git push --force origin claude/x\"}")" = deny ]'
ok "  --no-verify would skip pre-push: denied" \
  '[ "$(tool A Bash "{\"command\":\"git push --no-verify origin claude/x\"}")" = deny ]'
ok "  -c core.hooksPath unhooks the repo: denied" \
  '[ "$(tool A Bash "{\"command\":\"git -c core.hooksPath=/dev/null push origin claude/x\"}")" = deny ]'
ok "  --receive-pack runs code on the far side: denied" \
  '[ "$(tool A Bash "{\"command\":\"git push --receive-pack=/x origin claude/x\"}")" = deny ]'
ok "git push: denied" '[ "$(tool A Bash "{\"command\":\"git push origin main\"}")" = deny ]'
ok "git push --force-with-lease: denied" \
  '[ "$(tool A Bash "{\"command\":\"git push --force-with-lease\"}")" = deny ]'
ok "git -C elsewhere push: denied" '[ "$(tool A Bash "{\"command\":\"git -C /tmp/x push\"}")" = deny ]'
ok "git -c k=v push: denied" '[ "$(tool A Bash "{\"command\":\"git -c user.name=x push\"}")" = deny ]'
ok "push after &&: denied" '[ "$(tool A Bash "{\"command\":\"git commit -m x && git push\"}")" = deny ]'
ok "push in a plain folder: denied" '[ "$(tool A Bash "{\"command\":\"git push\"}" "$P")" = deny ]'
ok "push in a non-opted repo: denied" '[ "$(tool A Bash "{\"command\":\"git push\"}" "$N")" = deny ]'
ok "git log --grep push: allowed" '[ "$(tool A Bash "{\"command\":\"git log --grep push\"}" "$N")" = allow ]'
ok "grep for the words git push: allowed" \
  '[ "$(tool A Bash "{\"command\":\"grep -n \\\"git push\\\" rules.md\"}" "$P")" = allow ]'
ok "a quoted pipe before git push (grep pattern): allowed" \
  '[ "$(tool A Bash "{\"command\":\"grep -E '"'"'a|git push|b'"'"' f.md\"}" "$P")" = allow ]'
ok "env VAR=x git push: denied" '[ "$(tool A Bash "{\"command\":\"GIT_TRACE=1 git push\"}" "$P")" = deny ]'
ok "push in a subshell: denied" '[ "$(tool A Bash "{\"command\":\"(cd x; git push)\"}" "$P")" = deny ]'

echo "a branch never tracks origin/main — VS Code's Sync would push it there (2026-09-24)"
# In the plain folder $P, so the only guard that can answer is this one (on main every
# checkout is a write and denied anyway, which would make the deny cases prove nothing).
ok "checkout -b from origin/main: denied" \
  '[ "$(tool A Bash "{\"command\":\"git checkout -b claude/x origin/main\"}" "$P")" = deny ]'
ok "  switch -c too" '[ "$(tool A Bash "{\"command\":\"git switch -c claude/x origin/main\"}" "$P")" = deny ]'
ok "  -t / --track too" \
  '[ "$(tool A Bash "{\"command\":\"git checkout --track -b claude/x origin/main\"}" "$P")" = deny ]'
ok "  in a sibling repo too" \
  '[ "$(tool A Bash "{\"command\":\"git -C /tmp/w checkout -b claude/x origin/main\"}" "$P")" = deny ]'
ok "  branch <name> origin/main" '[ "$(tool A Bash "{\"command\":\"git branch claude/x origin/main\"}" "$P")" = deny ]'
ok "  branch -u origin/main" '[ "$(tool A Bash "{\"command\":\"git branch -u origin/main\"}" "$P")" = deny ]'
ok "  --set-upstream-to=origin/main" \
  '[ "$(tool A Bash "{\"command\":\"git branch --set-upstream-to=origin/main claude/x\"}" "$P")" = deny ]'
ok "  after && too" \
  '[ "$(tool A Bash "{\"command\":\"git fetch && git checkout -b claude/x origin/main\"}" "$P")" = deny ]'
ok "  --no-track makes it fine" \
  '[ "$(tool A Bash "{\"command\":\"git checkout -b claude/x --no-track origin/main\"}" "$P")" = allow ]'
ok "  worktree add -b … origin/main: denied" \
  '[ "$(tool A Bash "{\"command\":\"git worktree add .claude/worktrees/x -b claude/x origin/main\"}" "$P")" = deny ]'
ok "    with --no-track: allowed" \
  '[ "$(tool A Bash "{\"command\":\"git worktree add --no-track .claude/worktrees/x -b claude/x origin/main\"}" "$P")" = allow ]'
ok "    from local main: allowed" \
  '[ "$(tool A Bash "{\"command\":\"git worktree add .claude/worktrees/x -b claude/x main\"}" "$P")" = allow ]'
ok "  from local main (the recipe): allowed" \
  '[ "$(tool A Bash "{\"command\":\"git checkout -b claude/x main\"}" "$P")" = allow ]'
ok "  worktree add -b … main: allowed" \
  '[ "$(tool A Bash "{\"command\":\"git worktree add .claude/worktrees/t -b claude/x main\"}" "$P")" = allow ]'
ok "  tracking origin/claude/x is fine" \
  '[ "$(tool A Bash "{\"command\":\"git checkout -b claude/x origin/claude/x\"}" "$P")" = allow ]'
ok "  checkout origin/main -- path (a restore, no branch): allowed" \
  '[ "$(tool A Bash "{\"command\":\"git checkout origin/main -- docs/x.md\"}" "$P")" = allow ]'
ok "  git log origin/main..HEAD: allowed" \
  '[ "$(tool A Bash "{\"command\":\"git log --oneline origin/main..HEAD\"}" "$P")" = allow ]'
ok "commit message mentioning push: allowed" \
  '[ "$(tool A Bash "{\"command\":\"git commit -m push-later\"}" "$P")" = allow ]'

echo "main always stays main"
ev A UserPromptSubmit "just a question" >/dev/null; ev A Stop >/dev/null
ok "question-only turn on main: no branch, no claim" \
  '[ "$(git branch --show-current)" = main ] && [ ! -e .git/claude/owner.json ]'
out=$(ev A UserPromptSubmit "build the blue widget")
ok "on main: proactively told to make a worktree" 'echo "$out" | grep -q "worktree add"'
ok "write on main: denied" '[ "$(tool A Edit "{\"file_path\":\"$R/a\"}")" = deny ]'
ok "write on main: deny reason names the worktree recipe" \
  'toolreason A Edit "{\"file_path\":\"$R/a\"}" | grep -q "git worktree add"'
ev A Stop >/dev/null
ok "denied write left main clean, still on main" \
  '[ -z "$(git status --porcelain)" ] && [ "$(git branch --show-current)" = main ]'

echo "a detached primary is denied writes as main is (hookwatch's pin; autofinish-exclude landing review, finding 6)"
git -C "$R" checkout -q --detach
out=$(ev A UserPromptSubmit "a session opened in the pinned primary"); rc=$?
ok "a session's prompt in the pinned primary: the hook runs, no crash" '[ "$rc" = 0 ]'
ok "write on a detached primary: denied" '[ "$(tool A Edit "{\"file_path\":\"$R/a\"}")" = deny ]'
ok "  the reason names the pin and its unpin" 'toolreason A Edit "{\"file_path\":\"$R/a\"}" | grep -q "hookwatch unpin"'
ok "  a git commit there: denied" '[ "$(tool A Bash "{\"command\":\"git commit --allow-empty -m x\"}")" = deny ]'
ok "  a read there: allowed" '[ "$(tool A Bash "{\"command\":\"git log -1\"}")" = allow ]'
# from a session in another worktree, the usual case (the re-review of finding 6)
git -C "$R" worktree add -q "$T/pinwt" -b claude/pin-wt main
ok "  a write into it from a session in a worktree: denied" \
  '[ "$(tool A Edit "{\"file_path\":\"$R/a\"}" "$T/pinwt")" = deny ]'
ok "  a git -C <it> commit from a worktree: denied" \
  '[ "$(tool A Bash "{\"command\":\"git -C $R commit --allow-empty -m x\"}" "$T/pinwt")" = deny ]'
git -C "$R" worktree remove --force "$T/pinwt"; git -C "$R" branch -q -D claude/pin-wt
ev A Stop >/dev/null
git -C "$R" checkout -q main
ok "  left clean, and back on main" '[ -z "$(git status --porcelain)" ] && [ "$(git branch --show-current)" = main ]'

echo "the one exception: launching a finished branch"
# A real branch to launch, so the merge shapes carry something — the second review of 2026-09-24
# found the carry record turning `git merge claude/x` on main from allow into deny, which the
# first version of this test never saw because claude/topic did not exist.
git branch claude/topic main
ok "git merge --ff-only on main: allowed" \
  '[ "$(tool A Bash "{\"command\":\"git merge --ff-only claude/topic\"}")" = allow ]'
ok "  plain git merge: allowed" '[ "$(tool A Bash "{\"command\":\"git merge claude/topic\"}")" = allow ]'
ok "  git merge --no-ff -m: allowed" \
  '[ "$(tool A Bash "{\"command\":\"git merge --no-ff -m launch claude/topic\"}")" = allow ]'
ok "  and nothing is recorded on main" '[ ! -f .git/claude/carries ]'
ok "git switch on main: still denied (not part of merging)" \
  '[ "$(tool A Bash "{\"command\":\"git switch claude/topic\"}")" = deny ]'
ok "git add on main outside a merge: still denied" \
  '[ "$(tool A Bash "{\"command\":\"git add -A\"}")" = deny ]'
ok "Edit on main outside a merge: still denied" '[ "$(tool A Edit "{\"file_path\":\"$R/a\"}")" = deny ]'
touch .git/MERGE_HEAD
ok "git add on main mid-merge: allowed" '[ "$(tool A Bash "{\"command\":\"git add -A\"}")" = allow ]'
ok "git commit on main mid-merge: allowed" '[ "$(tool A Bash "{\"command\":\"git commit -m x\"}")" = allow ]'
ok "git checkout --ours on main mid-merge: allowed" \
  '[ "$(tool A Bash "{\"command\":\"git checkout --ours a\"}")" = allow ]'
ok "Edit on main mid-merge (resolving a conflict): allowed" \
  '[ "$(tool A Edit "{\"file_path\":\"$R/a\"}")" = allow ]'
ok "git switch on main mid-merge: still denied" \
  '[ "$(tool A Bash "{\"command\":\"git switch claude/topic\"}")" = deny ]'
ok "deploy on main mid-merge: still denied (not conflict resolution)" \
  '[ "$(tool A Bash "{\"command\":\"python3 scripts/deploy.py x.yaml\"}")" = deny ]'
ok "git checkout <claude ref> -- <path> on main mid-merge (resolving a conflict): allowed" \
  '[ "$(tool A Bash "{\"command\":\"git checkout claude/topic -- a\"}")" = allow ]'
ok "  add && commit --no-edit mid-merge: allowed, both resolve verbs" \
  '[ "$(tool A Bash "{\"command\":\"git add a && git commit --no-edit\"}")" = allow ]'
ok "  add && switch mid-merge: the add does not excuse the switch (D7) — denied" \
  '[ "$(tool A Bash "{\"command\":\"git add a && git switch claude/topic\"}")" = deny ]'
rm .git/MERGE_HEAD
# The exception is per verb (the owner's D7, 2026-09-25): a `git merge` excuses itself, not the line.
# Before, `git merge x && git checkout claude/y -- f` went through on main whole.
for shape in "git merge claude/topic && git checkout claude/topic -- a" "git merge claude/topic && git add -A" \
             "git merge claude/topic && git commit --amend -m x" "git merge claude/topic; git reset --hard HEAD~1" \
             "git pull --ff-only && git pull" "git merge -m 'launch' claude/topic && git stash"; do
  ok "D7, on main — the merge excuses only itself, denied: $shape" '[ "$(tool A Bash "{\"command\":\"$shape\"}")" = deny ]'
done
for shape in "git merge claude/topic && git log -1" "git fetch -q && git merge --ff-only claude/topic" \
             "git -c merge.ff=only merge claude/topic" "git pull -q --ff-only && git merge --ff-only claude/topic" "git merge --abort"; do
  ok "D7, on main — launching alone, allowed: $shape" '[ "$(tool A Bash "{\"command\":\"$shape\"}")" = allow ]'
done
ok "git add on main after the merge concludes: denied again" \
  '[ "$(tool A Bash "{\"command\":\"git add -A\"}")" = deny ]'
ok "Edit on main after the merge concludes: denied again" '[ "$(tool A Edit "{\"file_path\":\"$R/a\"}")" = deny ]'
git branch -D claude/topic >/dev/null

# Every session works in its own worktree from here on, same as a real one would after
# following the deny reason above.
git worktree add -q "$WA" -b claude/test-a main
GA="$(git -C "$WA" rev-parse --absolute-git-dir)/claude"  # $WA's own .git/.../claude/ state dir

echo "checkpoints (inside a worktree, like a real session)"
ev A UserPromptSubmit $'<ide_opened_file>x</ide_opened_file>\nBuild the blue widget' "$WA" >/dev/null
echo 1 > "$WA/a"; summ A "Widget: add"; out=$(ev A Stop "" "$WA")
ok "main untouched" '[ "$(git log -1 --format=%s main)" = base ]'
otip() { git -C "$T/origin.git" rev-parse --verify -q "refs/heads/$1"; }
ok "  first checkpoint is pushed to origin, and says so" \
  '[ "$(otip claude/test-a)" = "$(git -C "$WA" rev-parse HEAD)" ] && echo "$out" | grep -q "claude/test-a is on origin"'
ok "  ...and looks for its WIP PR once (the pr-checked marker)" '[ -e "$GA/pr-checked" ]'
ok "  summary + prompt + session trailer" \
  'msg "$WA" | grep -q "^Widget: add" && msg "$WA" | grep -q "^> Build the blue widget" && msg "$WA" | grep -q "^Claude-Session: sessA-00"'
ok "  IDE noise stripped" '! msg "$WA" | grep -q ide_opened_file'
ok "  summary consumed" '[ ! -e "$T/padA/commit-summary.md" ]'
ev A UserPromptSubmit "tweak it" "$WA" >/dev/null; echo 2 >> "$WA/a"; ev A Stop "" "$WA" >/dev/null
ok "no summary, no response text: wip(no-summary) subject" \
  'msg "$WA" | head -1 | grep -q "^wip(no-summary): tweak it"'
ok "a second checkpoint inside the push spacing is not pushed yet" \
  '[ "$(otip claude/test-a)" != "$(git -C "$WA" rev-parse HEAD)" ]'
touch -t 202001010000 "$GA/pushed"; ev A Stop "" "$WA" >/dev/null
ok "  ...and is once the spacing is up, even on a turn that committed nothing" \
  '[ "$(otip claude/test-a)" = "$(git -C "$WA" rev-parse HEAD)" ]'
echo "a branch that already landed is never pushed again (regatta#171 after #169, 2026-10-25)"
# Through the real hook: the suite never asks GitHub, so the answer is the state dir's cached one.
printf '{"branch": "claude/test-a", "number": 169, "url": "https://github.com/o/r/pull/169"}\n' > "$GA/spent.json"
before=$(otip claude/test-a); echo 5 >> "$WA/a"; summ A "Widget: after landing"; touch -t 202001010000 "$GA/pushed"
out=$(ev A Stop "" "$WA")
ok "  Stop in a spent worktree: committed, not pushed" \
  '[ "$(otip claude/test-a)" = "$before" ] && msg "$WA" | grep -q "^Widget: after landing"'
ok "  ...and the session hears it landed as #169, with the fresh-branch recipe" \
  'echo "$out" | grep -q "already landed as #169" && echo "$out" | grep -q "worktree is spent" && echo "$out" | grep -q "worktree add /.*/\.claude/worktrees/<topic> -b claude/"'
touch -t 202001010000 "$GA/pushed"; out=$(ev A Stop "" "$WA")
ok "  ...once per stranded commit, not every turn" '! echo "$out" | grep -q "already landed"'
out=$(ev A UserPromptSubmit "next?" "$WA")
ok "  ...and the model hears it at the next prompt (a Stop note reaches the screen only)" \
  'echo "$out" | grep -q "no longer pushes this branch" && echo "$out" | grep -q "EnterWorktree"'
rm -f "$GA/spent.json"; touch -t 202001010000 "$GA/pushed"; ev A Stop "" "$WA" >/dev/null
ok "  without the answer the push goes ahead, as before" '[ "$(otip claude/test-a)" = "$(git -C "$WA" rev-parse HEAD)" ]'
# In process, against a fake GitHub (common.api), as test_repos.sh fakes it: what is asked and when.
L="$T/landed"; git init -q --bare "$L-origin.git"
git clone -q "$L-origin.git" "$L" 2>/dev/null && git -C "$L" -c user.name=t -c user.email=t@t commit -q --allow-empty -m base && git -C "$L" push -q origin HEAD:main 2>/dev/null
git -C "$L" checkout -q -B main
cat > "$T/landed.py" <<'PY'
import json, os, subprocess, sys, urllib.parse
from pathlib import Path
sys.path.insert(0, sys.argv[1])
import checkpoint as cp, common, sync
repo, origin, states = sys.argv[2], sys.argv[3], Path(sys.argv[4])
os.environ.pop("CLAUDE_HOOK_NO_GITHUB", None); os.environ.pop("CLAUDE_HOOK_NO_PUSH", None)
cp.ROOT, cp.MAIN = repo, "main"
common.repo_slug = lambda url: "o/r"
common.token = lambda: "tok"

MERGED = {"number": 169, "state": "closed", "merged_at": "2026-10-25T01:00:00Z",
          "html_url": "https://github.com/o/r/pull/169", "head": {"sha": "0" * 40}}
OPEN = {"number": 172, "state": "open", "merged_at": None, "html_url": "https://github.com/o/r/pull/172"}
CLOSED = {"number": 150, "state": "closed", "merged_at": None}

class GH:
    def __init__(self, prs=(), status=200):
        self.prs, self.status, self.calls = list(prs), status, []
        common.api = self.api
    def api(self, method, path, body=None, tok=None, timeout=15):
        self.calls.append((method, path))
        if self.status != 200:
            return self.status, None
        if method == "GET" and "state=all" in path:  # as GitHub: each PR names its head and base
            br = urllib.parse.unquote(path.split("head=", 1)[1].split(":", 1)[1])
            return 200, [dict(p, head=dict({"ref": br}, **p.get("head", {})),
                              base=p.get("base", {"ref": "main"})) for p in self.prs]
        if method == "GET" and "state=open" in path:
            return 200, [p for p in self.prs if p["state"] == "open"]
        if method == "POST" and path.endswith("/pulls"):
            return 201, {"number": 9, "html_url": "https://github.com/o/r/pull/9"}
        return 201, {}
    def posted(self):
        return any(m == "POST" and p.endswith("/pulls") for m, p in self.calls)

def git(*a):
    return subprocess.run(["git", "-C", repo, "-c", "user.name=t", "-c", "user.email=t@t", *a],
                          capture_output=True, text=True).stdout.strip()
def tip(b):
    return subprocess.run(["git", "-C", origin, "rev-parse", "--verify", "-q", "refs/heads/" + b],
                          capture_output=True, text=True).stdout.strip()
n = [0]
def commit():
    n[0] += 1
    Path(repo, "f").write_text(str(n[0]))
    git("add", "f"); git("commit", "-q", "-m", "c%d" % n[0])
def branch(name, upstream=False):
    git("checkout", "-q", "-b", name, "main"); commit()
    if upstream:
        git("push", "-q", "-u", "origin", name); commit()
    st = states / name.replace("/", "-"); st.mkdir(parents=True)
    return st
def case(name, cond):
    print(name, "pass" if cond else "fail")

b = "claude/x/2026-10-24-host-power"; st = branch(b)
gh = GH([MERGED]); note = cp.publish(st, b, "sess")
case("L1", note and "already landed as #169" in note and "pull/169" in note and tip(b) == "" and not gh.posted()
     and json.loads((st / "spent.json").read_text())["number"] == 169)
q = [p for m, p in gh.calls if m == "GET"]
case("L2", len(q) == 1 and "state=all" in q[0] and "head=o:claude%2Fx%2F2026-10-24-host-power" in q[0])
commit(); gh = GH([MERGED]); note = cp.publish(st, b, "sess")
case("L3", note and "#169" in note and gh.calls == [] and tip(b) == "")
case("L4", cp.publish(st, b, "sess") is None and gh.calls == [])
case("L5", "#169" in (cp.publish(st, b, "sess", force=True) or ""))
(st / sync.UNPUSHED).write_text("sess")
pushed, ok = sync.push_left(cp, st, b, "sess")
case("L6", ok and "#169" in (pushed or "") and "\n" not in pushed and not (st / sync.UNPUSHED).exists() and tip(b) == "")

b = "claude/x/2026-10-27-reopened"; st = branch(b, upstream=True)
gh = GH([OPEN, MERGED]); cp.publish(st, b, "sess", force=True)
case("L7", tip(b) == git("rev-parse", "HEAD") and not (st / "spent.json").exists())
b = "claude/x/2026-10-27-abandoned"; st = branch(b)
gh = GH([CLOSED]); note = cp.publish(st, b, "sess")
case("L8", tip(b) == git("rev-parse", "HEAD") and "is on origin" in (note or "") and gh.posted())
b = "claude/x/2026-10-27-offline"; st = branch(b)
gh = GH([MERGED], status=0); cp.publish(st, b, "sess")
case("L9", tip(b) == git("rev-parse", "HEAD") and not (st / "spent.json").exists())
b = "claude/x/2026-10-27-tokenless"; st = branch(b)
gh = GH([MERGED]); common.token = lambda: None; cp.publish(st, b, "sess"); common.token = lambda: "tok"
case("L10", tip(b) == git("rev-parse", "HEAD") and gh.calls == [])
b = "claude/x/2026-10-27-nogithub"; st = branch(b)
gh = GH([MERGED]); os.environ["CLAUDE_HOOK_NO_GITHUB"] = "1"; cp.publish(st, b, "sess"); os.environ.pop("CLAUDE_HOOK_NO_GITHUB")
case("L11", tip(b) == git("rev-parse", "HEAD") and gh.calls == [])
b = "claude/x/2026-10-27-renamed"; st = branch(b)
(st / "spent.json").write_text(json.dumps({"branch": "claude/x/old-name", "number": 99}) + "\n")
gh = GH([]); cp.publish(st, b, "sess")
case("L12", tip(b) == git("rev-parse", "HEAD") and any("state=all" in p for _, p in gh.calls))
b = "claude/x/2026-10-27-reused"; st = branch(b)
gh = GH([dict(MERGED, merge_commit_sha=git("rev-parse", "main"))]); cp.publish(st, b, "sess")
case("L13", tip(b) == git("rev-parse", "HEAD") and not (st / "spent.json").exists())
b = "claude/x/2026-10-27-pushed-by-hand"; st = branch(b)
gh = GH([MERGED]); cp.publish(st, b, "sess"); held = (st / "spent.json").exists()
git("push", "-q", "-u", "origin", b); commit()
gh = GH([OPEN, MERGED]); cp.publish(st, b, "sess", force=True)
case("L14", held and tip(b) == git("rev-parse", "HEAD") and len(gh.calls) >= 1)
b = "claude/x/2026-10-27-stacked"; st = branch(b)
gh = GH([dict(MERGED, base={"ref": "claude/x/parent"})]); cp.publish(st, b, "sess")
case("L15", tip(b) == git("rev-parse", "HEAD") and not (st / "spent.json").exists())
b = "claude/x/2026-10-27-unfiltered"; st = branch(b)
gh = GH([dict(MERGED, head={"ref": "claude/x/someone-else"})]); cp.publish(st, b, "sess")
case("L16", tip(b) == git("rev-parse", "HEAD") and not (st / "spent.json").exists())
PY
python3 "$T/landed.py" "$MOD/hooks" "$L" "$L-origin.git" "$T/landed-states" > "$T/landed.out" 2>&1
lcase() { lc=$1; ok "$2" 'grep -qx "$lc pass" "$T/landed.out"'; }
lcase L1 "  first push of a landed branch (the #171 shape): not pushed, no WIP PR, the answer kept"
lcase L2 "  ...asked once, by head branch, open and closed alike (state=all)"
lcase L3 "  a later commit: the kept answer, no second lookup"
lcase L4 "  the same commit again: quiet"
lcase L5 "  ...unless the push is forced (session end, sync): said again"
lcase L6 "  sync's push_left: no retry marker left for a landed branch"
lcase L7 "  an open PR beside the merged one: live again, pushed"
lcase L8 "  closed unmerged only: pushed, and its WIP PR opened, as before"
lcase L9 "  GitHub unreachable: pushed, as before, nothing kept"
lcase L10 "  no token: pushed, GitHub never asked"
lcase L11 "  CLAUDE_HOOK_NO_GITHUB: pushed, GitHub never asked"
lcase L12 "  a kept answer for another branch name: ignored, asked afresh"
lcase L13 "  a merge commit HEAD already holds (a reused name, forked after): pushed, nothing kept"
lcase L14 "  a kept yes whose origin ref moved since (pushed by hand, PR reopened): asked again, pushed"
lcase L15 "  merged into another branch, not main: pushed"
lcase L16 "  a PR from another head (GitHub ignoring the filter): pushed"
grep -q "Traceback" "$T/landed.out" && { echo "  FAIL landed.py raised:"; sed 's/^/    /' "$T/landed.out"; fails=$((fails+1)); }

echo "checkpoints (continued)"
rm -f "$GA/pr-checked"; echo 3 >> "$WA/a"; touch -t 202001010000 "$GA/pushed"; ev A Stop "" "$WA" >/dev/null
ok "  a branch that came with an upstream (a pickup seed) still gets its PR looked for" '[ -e "$GA/pr-checked" ]'

out=$(ev A UserPromptSubmit "thoughts?" "$WA")
ok "reminder shown next turn after a no-summary commit" 'echo "$out" | grep -q "commit-summary.md"'
ev A Stop "" "$WA" >/dev/null
ev A UserPromptSubmit "do it" "$WA" >/dev/null; echo 3 >> "$WA/a"; summ A "Widget: tweak"; ev A Stop "" "$WA" >/dev/null
ok "discussion turn's prompt rides the next commit" \
  'msg "$WA" | grep -q "^> thoughts?" && msg "$WA" | grep -q "^> do it"'
ev A UserPromptSubmit "polish it" "$WA" >/dev/null; echo 4a >> "$WA/a"
ev A Stop "" "$WA" "Widget: polished the edges and added a fallback." >/dev/null
ok "no summary file, but a chat response: derived instead of wip(no-summary)" \
  'msg "$WA" | head -1 | grep -qv "^wip(no-summary)" && msg "$WA" | grep -q "polished the edges"'
ev A UserPromptSubmit "start" "$WA" >/dev/null; echo 4 >> "$WA/a"; ev A UserPromptSubmit "next" "$WA" >/dev/null
ok "interrupted turn: committed as between-turns" 'msg "$WA" | head -1 | grep -q "^wip: changes between turns"'
ev A Stop "" "$WA" >/dev/null
echo S=1 > "$WA/.env"; ev A Stop "" "$WA" >/dev/null
ok ".env refused, nothing staged" \
  '[ -z "$(git -C "$WA" diff --cached --name-only)" ] && ! git -C "$WA" log --format=%B | grep -q "S=1"'
rm "$WA/.env"
touch "$GA/finishing"; summ A "Widget: rename"; echo f > "$WA/f"; ev A Stop "" "$WA" >/dev/null
ok "/finish marker: no commit" '[ -n "$(git -C "$WA" status --porcelain)" ]'
ok "/finish marker: summary preserved, not thrown away" '[ -e "$T/padA/commit-summary.md" ]'
ok "/finish marker: says why it is quiet" \
  'ev A UserPromptSubmit "still going" "$WA" | grep -q "finishing\` is set"'
rm "$GA/finishing"; ev A Stop "" "$WA" >/dev/null
ok "preserved summary is committed once unblocked" 'msg "$WA" | grep -q "^Widget: rename"'
ok "  held back by the spacing" '[ "$(otip claude/test-a)" != "$(git -C "$WA" rev-parse HEAD)" ]'
ev A SessionEnd "" "$WA"
ok "SessionEnd pushes whatever the spacing held back" '[ "$(otip claude/test-a)" = "$(git -C "$WA" rev-parse HEAD)" ]'

# An abandoned /finish leaves `finishing` behind, and it then muted checkpoints for every
# later session in the checkout — silently, because a stale marker also suppresses the
# off_workflow nag. Cost a turn's work 2026-09-10→11. It must age out and say so.
touch "$GA/finishing"; touch -t 202001010000 "$GA/finishing"
ok "stale /finish marker: reported on submit" \
  'ev A UserPromptSubmit "next session" "$WA" | grep -q "stale .finishing. marker"'
ok "  and removed" '[ ! -e "$GA/finishing" ]'
summ A "Widget: after stale"; echo g > "$WA/g"; ev A Stop "" "$WA" >/dev/null
ok "  checkpoints work again" 'msg "$WA" | grep -q "^Widget: after stale"'

git -C "$WA" switch -q -c master
ok "off-workflow branch: warned on submit" \
  'ev A UserPromptSubmit "should not checkpoint" "$WA" | grep -q "checkpoints are OFF"'
echo o > "$WA/o"
ok "off-workflow branch: warned + no commit on stop" \
  'ev A Stop "" "$WA" | grep -q "NOT checkpointed" && [ -n "$(git -C "$WA" status --porcelain)" ]'
rm -f "$WA/o"; git -C "$WA" switch -q claude/test-a; git -C "$WA" branch -D master >/dev/null

echo "wired twice in one session (user-wide + a project's leftover shim)"
payload=$(jq -nc --arg s "$T/padA" --arg c "$WA" '{hook_event_name:"UserPromptSubmit",prompt:"twice",scratchpad_dir:$s,session_id:"sessA-0000",cwd:$c,prompt_id:"p-1"}')
echo "$payload" | python3 "$HOOK" >/dev/null; echo "$payload" | python3 "$HOOK" >/dev/null
ok "the same prompt event twice: queued once" '[ "$(jq "[.[]|select(.prompt==\"twice\")]|length" "$GA/prompts.json")" = 1 ]'
ok "a doubled PreToolUse is never skipped (skipping would mean allow)" \
  '[ "$(tool A Edit "{\"file_path\":\"$R/a\"}")" = deny ] && [ "$(tool A Edit "{\"file_path\":\"$R/a\"}")" = deny ]'
ev A Stop "" "$WA" >/dev/null

echo "a worktree forked before the project opted in follows the main checkout"
git worktree add -q "$T/old" -b claude/old-fork main
rm "$T/old/.claude/workflow.json"; git -C "$T/old" commit -qam "as if forked before the opt-in"
ev A UserPromptSubmit "old worktree" "$T/old" >/dev/null; echo x > "$T/old/x"; ev A Stop "" "$T/old" >/dev/null
ok "checkpoints still go there" 'git -C "$T/old" log -1 --format=%B | grep -q "^> old worktree"'
git worktree remove --force "$T/old"; git branch -D claude/old-fork >/dev/null

echo "lock (two sessions contending for one worktree)"
tool A Edit "{\"file_path\":\"$WA/a\"}" "$WA" >/dev/null   # A writes there: owns that worktree
ok "B's prompt gets a read-only notice" 'ev B UserPromptSubmit "LT002 projector" "$WA" | grep -q "read-only here"'
ok "B Edit inside A's worktree: deny" '[ "$(tool B Edit "{\"file_path\":\"$WA/b\"}" "$WA")" = deny ]'
ok "B Write to its own scratchpad: allow" '[ "$(tool B Write "{\"file_path\":\"$T/padB/x\"}" "$WA")" = allow ]'
ok "B git commit there: deny" '[ "$(tool B Bash "{\"command\":\"git add -A && git commit -m x\"}" "$WA")" = deny ]'
ok "B deploy a file there: deny" '[ "$(tool B Bash "{\"command\":\"python3 scripts/deploy.py x.yaml\"}" "$WA")" = deny ]'
ok "B deploy --check-only there: allow" '[ "$(tool B Bash "{\"command\":\"python3 scripts/deploy.py --all --check-only\"}" "$WA")" = allow ]'
ok "B git log / ha.py there: allow" '[ "$(tool B Bash "{\"command\":\"git log -3; python3 scripts/ha.py state x\"}" "$WA")" = allow ]'
# Inline code can write anything and carries no write verb (lock-script-writes, 2026-10-04: a
# `python3 - <<EOF … write_text … EOF` rewrote a file under another session's lock).
bashc() { tool "$1" Bash "$(jq -nc --arg c "$2" '{command:$c}')" "$3"; }
HD=$(printf "python3 - <<'EOF'\nfrom pathlib import Path\nPath('bin/x').write_text('y')\nEOF")
ok "B python3 - <<EOF with a write_text body there: deny" '[ "$(bashc B "$HD" "$WA")" = deny ]'
ok "  the reason names the lock and the inline code" \
  'r=$(toolreason B Bash "$(jq -nc --arg c "$HD" "{command:\$c}")" "$WA"); echo "$r" | grep -q "belongs to another" && echo "$r" | grep -q "inline code"'
ok "B python3 -c \"open(x,w)\" there: deny" '[ "$(bashc B "python3 -c \"open('"'"'x'"'"','"'"'w'"'"')\"" "$WA")" = deny ]'
ok "B node -e with a write there: deny" '[ "$(bashc B "node -e \"require('"'"'fs'"'"').writeFileSync('"'"'x'"'"','"'"'y'"'"')\"" "$WA")" = deny ]'
ok "B perl -pi -e there: deny" '[ "$(bashc B "perl -pi -e '"'"'s/a/b/'"'"' x" "$WA")" = deny ]'
ok "B ruby -e, and a heredoc piped into python3, there: deny" \
  '[ "$(bashc B "ruby -e 1" "$WA")" = deny ] && [ "$(bashc B "$(printf "cat <<EOF | python3\nprint(1)\nEOF")" "$WA")" = deny ]'
# A named program is a tool the repo ships, run as a reader runs it; only inline code is denied.
ok "B python3 -m py_compile / script.py --help / json.tool there: allow" \
  '[ "$(bashc B "python3 -m py_compile x.py" "$WA")" = allow ] && [ "$(bashc B "python3 scripts/ha.py --help" "$WA")" = allow ] && [ "$(bashc B "echo {} | python3 -m json.tool" "$WA")" = allow ]'
ok "B a heredoc body that mentions python3 -c, fed to grep, there: allow" \
  '[ "$(bashc B "$(printf "grep -c x y <<EOF\npython3 -c 1\nEOF")" "$WA")" = allow ]'
ok "A, the owner, runs the same inline code in its own worktree: allow" \
  '[ "$(bashc A "$HD" "$WA")" = allow ] && [ "$(bashc A "node -e 1" "$WA")" = allow ]'
# The first review's bypasses (2026-10-04), each one an agent's everyday spelling.
for c in "$(printf "python3 <<'EOF' 2>&1 | tail -3\nopen('x','w')\nEOF")" "$(printf 'python3 \\\n  -c 1')" \
    "/usr/bin/env python3 -c 1" "$(printf "python3 -v <<EOF\nx\nEOF")" "perl -I . -e 1" \
    "node --input-type module -e 1" "eval \"python3 -c 1\"" "$(printf 'cat <<< hi\npython3 -c 1')" \
    "uv run python -c 1" "$(printf "python3 /dev/stdin <<EOF\nx\nEOF")"; do
  ok "B $(printf '%s' "$c" | head -1) there: deny" '[ "$(bashc B "$c" "$WA")" = deny ]'
done
ok "B from the primary, cd <A's worktree> && python3 -c: deny (judged where the cd goes)" \
  '[ "$(bashc B "cd $WA && python3 -c 1" "$R")" = deny ]'
# The primary never takes a lock, but a stale owner.json there must not start gating it.
mkdir -p .git/claude && printf '{"session": "other-0000", "branch": "main", "seen": %s}' "$(date +%s)" > .git/claude/owner.json
ok "inline code on the primary's main, even beside a stray lock file: allow, as before" \
  '[ "$(bashc B "python3 -c 1" "$R")" = allow ]'
rm .git/claude/owner.json
echo u > "$WA/u"; ev B Stop "" "$WA" >/dev/null
ok "B's Stop doesn't commit dirt it doesn't own" '[ -n "$(git -C "$WA" status --porcelain)" ]'
git -C "$WA" add -A; git -C "$WA" commit -q -m u
ahome=$(git -C "$WA" branch --show-current); git -C "$WA" switch -q -c claude/other
ok "branch switched under owner: warned" 'ev A UserPromptSubmit "carry on" "$WA" | grep -q "branch changed under"'
ev A Stop "" "$WA" >/dev/null; git -C "$WA" switch -q "$ahome"
jq '.seen -= 7300' "$GA/owner.json" > "$T/o" && mv "$T/o" "$GA/owner.json"
ok "owner idle > 2 h: next writer takes over" \
  '[ "$(tool B Edit "{\"file_path\":\"$WA/b\"}" "$WA")" = allow ] && jq -e ".session==\"sessB-0000\"" "$GA/owner.json" >/dev/null'
ev A SessionEnd "" "$WA"; ok "SessionEnd of a non-owner keeps the lock" '[ -e "$GA/owner.json" ]'
ev B SessionEnd "" "$WA"; ok "SessionEnd of the owner frees it" '[ ! -e "$GA/owner.json" ]'
ok "no lock: inline python3/node/perl allowed, and they claim no lock" \
  '[ "$(bashc B "$HD" "$WA")" = allow ] && [ "$(bashc B "node -e 1; perl -e 1" "$WA")" = allow ] && [ ! -e "$GA/owner.json" ]'

echo "hand-over (pickup next: the owner opens a fresh tab on its own worktree)"
handover() { jq ".handover = $(date +%s)" "$GA/owner.json" > "$T/o" && mv "$T/o" "$GA/owner.json"; }
tool A Edit "{\"file_path\":\"$WA/a\"}" "$WA" >/dev/null; handover
echo h > "$WA/h"; ev A Stop "" "$WA" >/dev/null
ok "the owner's Stop after the hand-over commits and keeps the mark" \
  '[ -z "$(git -C "$WA" status --porcelain)" ] && jq -e ".session==\"sessA-0000\" and .handover" "$GA/owner.json" >/dev/null'
ok "the new session's prompt gets no read-only notice" '! ev B UserPromptSubmit "next stage" "$WA" | grep -q "read-only"'
ok "  its first write is allowed and takes the lock, unmarked" \
  '[ "$(tool B Edit "{\"file_path\":\"$WA/b\"}" "$WA")" = allow ] && jq -e ".session==\"sessB-0000\" and (.handover|not)" "$GA/owner.json" >/dev/null'
ok "  and the old one is locked out again" '[ "$(tool A Edit "{\"file_path\":\"$WA/a\"}" "$WA")" = deny ]'
ev B SessionEnd "" "$WA"; tool A Edit "{\"file_path\":\"$WA/a\"}" "$WA" >/dev/null; handover
ok "a new prompt in the old session withdraws the hand-over, and says so" \
  'ev A UserPromptSubmit "one more thing" "$WA" | grep -q "hand-over withdrawn" && jq -e ".handover|not" "$GA/owner.json" >/dev/null'
ok "  so the new tab is locked out after all" '[ "$(tool B Edit "{\"file_path\":\"$WA/b\"}" "$WA")" = deny ]'
handover
ok "a background task finishing in the old session keeps the mark" \
  'ev A UserPromptSubmit "<task-notification><task-id>x</task-id></task-notification>" "$WA" >/dev/null; jq -e ".session==\"sessA-0000\" and .handover" "$GA/owner.json" >/dev/null'
ok "the new tab's first write by Bash (git commit) takes a marked lock" \
  '[ "$(bashc B "git commit -m x" "$WA")" = allow ] && jq -e ".session==\"sessB-0000\"" "$GA/owner.json" >/dev/null'
echo d > "$WA/d"; ev A Stop "" "$WA" >/dev/null
ok "  the old session's Stop then commits nothing and leaves the lock with the tab" \
  '[ -n "$(git -C "$WA" status --porcelain)" ] && jq -e ".session==\"sessB-0000\"" "$GA/owner.json" >/dev/null'
ok "claim() never writes over another session's fresh lock (taken while a hook ran), and says so" \
  '[ "$(python3 -c "import sys;sys.path.insert(0,sys.argv[1]);import checkpoint as c;from pathlib import Path;print(c.claim(Path(sys.argv[2]),\"sessA-0000\",\"x\"))" "$(dirname "$HOOK")" "$GA")" = False ] && jq -e ".session==\"sessB-0000\"" "$GA/owner.json" >/dev/null'
git -C "$WA" add -A; git -C "$WA" commit -qm d
ev B SessionEnd "" "$WA"; ev A SessionEnd "" "$WA"

echo "worktree independence (A's and B's own, separate worktrees)"
tool A Edit "{\"file_path\":\"$WA/a\"}" "$WA" >/dev/null   # A re-claims its own worktree
git worktree add -q "$WB" -b claude/test-b main
ok "B in its own worktree: no read-only notice" '! ev B UserPromptSubmit "projector in worktree" "$WB" | grep -q "read-only"'
ok "B Edit in its own worktree: allow" '[ "$(tool B Edit "{\"file_path\":\"$WB/p\"}" "$WB")" = allow ]'
echo p > "$WB/p"; summ B "Projector: doc"; ev B Stop "" "$WB" >/dev/null
ok "B's checkpoint goes into its worktree with B's prompt" 'msg "$WB" | grep -q "^> projector in worktree"'
ok "A still owns its own worktree" 'jq -e ".session==\"sessA-0000\"" "$GA/owner.json" >/dev/null'
ok "A Edit in B's worktree: deny" '[ "$(tool A Edit "{\"file_path\":\"$WB/p\"}" "$WB")" = deny ]'
ok "B's worktree changes invisible to the primary checkout" '[ -z "$(git status --porcelain)" ]'
ok "primary checkout is still on main, untouched throughout" \
  '[ "$(git branch --show-current)" = main ] && [ ! -e .git/claude/owner.json ]'
ok "B's first checkpoint went to origin too" '[ "$(otip claude/test-b)" = "$(git -C "$WB" rev-parse HEAD)" ]'

echo "carries: content taken from another claude/* branch is recorded on the allow path only (D2, 2026-09-24)"
# A owns $WA (claude/test-a); B owns $WB (claude/test-b), whose commit `p` is on no other branch.
# A record is `<kind> <commit> <branch>`: merge/rebase take a whole branch, the rest a part.
CA="$GA/carries"; GB="$(git -C "$WB" rev-parse --absolute-git-dir)/claude"
shab=$(git -C "$WB" rev-parse HEAD); shamain=$(git rev-parse main)
# carrynote <command>  — the hook's systemMessage for that command as session A in $WA
carrynote() { jq -nc --arg c "$WA" --arg cmd "$1" \
  '{hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$cmd},session_id:"sessA-0000",cwd:$c}' \
  | python3 "$HOOK" | jq -r '.systemMessage // empty' 2>/dev/null; }
carry() { carrynote "$1" >/dev/null; }
carried() { [ -f "$CA" ] && grep -qx "$1" "$CA"; }
none() { [ ! -f "$CA" ]; }
ok "checkout <claude ref> -- <path>: a partial carry pinned to the commit, and the note says so" \
  'carrynote "git checkout claude/test-b -- p" | grep -q "carries claude/test-b (checkout)" && carried "checkout $shab claude/test-b"'
ok "  the command itself is still allowed" \
  '[ "$(tool A Bash "{\"command\":\"git checkout claude/test-b -- p\"}" "$WA")" = allow ]'
ok "  recorded twice: one line, no second note" \
  '[ "$(grep -c . "$CA")" = 1 ] && [ -z "$(carrynote "git checkout claude/test-b -- p")" ]'; rm -f "$CA"
carry "git checkout main -- x";                     ok "checkout main -- x: not a carry" none
carry "git checkout -b claude/new";                 ok "checkout -b: not a carry" none
carry "git checkout claude/test-b";                 ok "a plain branch switch: not a carry" none
carry "git checkout claude/test-a -- a";            ok "own branch: not a carry" none
carry "git log claude/test-b";                      ok "reading another branch's log: not a carry" none
carry "git log --oneline claude/test-b > log.txt";  ok "  a log written to a file: still a read" none
carry "git diff main claude/test-b";                ok "a diff nobody applies: not a carry" none
carry "git diff --stat main...claude/test-b >/dev/null"; ok "  a diff to /dev/null: not a carry" none
carry "git diff main...claude/test-b > review.patch";    ok "  a diff saved for review: not a carry" none
carry "git show claude/test-b:p > p";               ok "git show <ref>:<path> > file: a read, not a carry" none
carry "git show claude/test-b:p | head";            ok "  piped to a reader: not a carry" none
carry "grep claude/test-b notes.md";                ok "mentioning a branch: not a carry" none
carry "echo git checkout claude/test-b -- x";       ok "an echo of a carry command: not a carry" none
carry "git commit -m 'x; git merge claude/test-b'"; ok "a carry command inside a quoted message: not a carry" none
carry $'cat > s.sh <<\'EOF\'\ngit merge claude/test-b\nEOF';            ok "a heredoc body: not a carry" none
carry $'git commit -F - <<EOF\ngit cherry-pick claude/test-b\nEOF';    ok "  a commit message fed by heredoc: not a carry" none
carry "git checkout -p claude/test-b -- p";          ok "checkout -p: a partial carry" 'carried "checkout $shab claude/test-b"'; rm -f "$CA"
carry "git checkout claude/test-b~1 -- p";           ok "an older commit of the branch: recorded, pinned to that commit" 'carried "checkout $shamain claude/test-b"'; rm -f "$CA"
carry "git restore --source origin/claude/test-b p"
ok "restore --source origin/<ref>: recorded, origin/ stripped" 'carried "restore $shab claude/test-b"'; rm -f "$CA"
carry "git restore -s claude/test-b -- p";          ok "restore -s <ref> -- <path>: recorded" 'carried "restore $shab claude/test-b"'; rm -f "$CA"
carry "git cherry-pick $shab";                      ok "cherry-pick <sha>: resolved to the branch holding it, pinned" 'carried "cherry-pick $shab claude/test-b"'; rm -f "$CA"
carry "git cherry-pick -x ${shab:0:8}";             ok "  a short sha, the full commit recorded" 'carried "cherry-pick $shab claude/test-b"'; rm -f "$CA"
carry "git cherry-pick $shamain";                   ok "cherry-pick a sha on main: not a carry" none
carry "git cherry-pick --continue";                 ok "cherry-pick --continue: not a carry" none
carry "git merge claude/test-b";                    ok "merge <claude ref>: a whole carry, pinned to its tip" 'carried "merge $shab claude/test-b"'; rm -f "$CA"
carry "git merge main";                             ok "merge main: not a carry" none
carry "git merge --abort";                          ok "merge --abort: not a carry" none
carry "git rebase origin/main";                     ok "rebase origin/main: not a carry" none
carry "git rebase claude/test-b";                   ok "rebase onto <claude ref>: a whole carry" 'carried "rebase $shab claude/test-b"'; rm -f "$CA"
carry "git pull origin claude/test-b";              ok "pull <remote> <claude ref>: a whole carry (merge)" 'carried "merge $shab claude/test-b"'; rm -f "$CA"
carry "cp ../b/p p";                                ok "cp from a sibling worktree, relative path: recorded at its HEAD" 'carried "cp $shab claude/test-b"'; rm -f "$CA"
carry "cp $WB/p ./p";                               ok "  absolute path: recorded" 'carried "cp $shab claude/test-b"'; rm -f "$CA"
carry "cat $WB/p > p";                              ok "cat … > from a sibling worktree: recorded" 'carried "cp $shab claude/test-b"'; rm -f "$CA"
carry "cat $WB/p";                                  ok "reading a sibling's file: not a carry" none
carry "diff $WB/p p";                               ok "diff against a sibling worktree, no redirect: not a carry" none
carry "cp $WA/a b";                                 ok "cp inside the own worktree: not a carry" none
carry "wc -l < ../a/a";                             ok "the own worktree reached via ../: not a carry" none
carry "cp $R/.gitignore y";                         ok "cp from the primary checkout (main): not a carry" none
carry "git diff main claude/test-b | git apply";    ok "git diff <ref> | git apply: recorded (apply)" 'carried "apply $shab claude/test-b"'; rm -f "$CA"
carry "git -C $WB diff | git apply";                ok "git -C <sibling> diff | git apply: recorded" 'carried "apply $shab claude/test-b"'; rm -f "$CA"
carry "git diff main...claude/test-b | git apply --check -R";  ok "  | git apply --check: only looks, not a carry" none
carry "git show claude/test-b:p | patch --dry-run -p1";        ok "  | patch --dry-run: not a carry" none
carry "git -C $WB diff | git apply --stat";                    ok "  | git apply --stat: not a carry" none
carry "git -C $WB diff | git apply --stat --apply";            ok "  | git apply --stat --apply: really applies, recorded" 'carried "apply $shab claude/test-b"'; rm -f "$CA"
carry "git merge-tree claude/test-b main";                     ok "git merge-tree: a read, not a carry" none
carry "git log --oneline main..claude/test-b";                 ok "git log main..<ref>: not a carry" none
carry "cd $WA && git checkout claude/test-b -- p"; ok "cd <own worktree> && checkout …: recorded" 'carried "checkout $shab claude/test-b"'; rm -f "$CA"
# Launching on main stays allowed whatever the merge carries (the second review's fx5 shapes).
for shape in "git merge --ff-only claude/test-b" "git merge claude/test-b" "git merge --no-ff -m launch claude/test-b"; do
  ok "on main: '${shape%% claude*}' … claude/test-b: allowed" '[ "$(tool A Bash "{\"command\":\"$shape\"}")" = allow ]'
done
ok "  and none of that recorded anything, on main or in the worktree, nor took a lock on main" \
  '[ ! -f .git/claude/carries ] && none && [ ! -e .git/claude/owner.json ]'
for shape in "git merge claude/test-b && cp $WB/p p" "git merge claude/test-b && git cherry-pick claude/test-b" \
             "git merge claude/test-b && git show claude/test-b:p | git apply"; do
  ok "D7, on main — the merge's own record is excused, the second carry is not: denied — ${shape//$T/\$T}" \
    '[ "$(tool A Bash "{\"command\":\"$shape\"}")" = deny ] && [ ! -f .git/claude/carries ]'
done
for shape in "cd $WA && git merge claude/test-b" "git -C $WA merge claude/test-b"; do
  ok "from main into the worktree this session owns: '${shape//$T/\$T}': allowed" '[ "$(tool A Bash "{\"command\":\"$shape\"}")" = allow ]'
  ok "  a merge INTO that worktree is a carry there (D4): recorded there, nothing on main" \
    'carried "merge $shab claude/test-b" && [ ! -f .git/claude/carries ]'; rm -f "$CA"
done
ok "reads that mention a branch, run on main: allowed" \
  '[ "$(tool A Bash "{\"command\":\"git show claude/test-b:p | patch --dry-run -p1\"}")" = allow ] \
   && [ "$(tool A Bash "{\"command\":\"git log --oneline main..claude/test-b\"}")" = allow ] \
   && [ "$(tool A Bash "{\"command\":\"git merge --ff-only origin/main\"}")" = allow ]'
# The allow path only. A denied command never runs, so it must leave no record. A carry is
# judged by the checkout it ends up in (D4): from the primary checkout, `cd <A's worktree> && …`
# is A's write, allowed and recorded there; into a worktree another session owns, denied.
ok "from a session whose cwd is the primary checkout, into the worktree it owns: allowed, recorded there, nothing on main" \
  '[ "$(tool A Bash "{\"command\":\"cd $WA && git checkout claude/test-b -- p\"}")" = allow ] && carried "checkout $shab claude/test-b" && [ ! -f .git/claude/carries ]'
rm -f "$CA"
ok "on main itself: denied, nothing recorded" \
  '[ "$(tool A Bash "{\"command\":\"git checkout claude/test-b -- x\"}")" = deny ] && [ ! -f .git/claude/carries ]'
ok "a cp from a sibling worktree is a write: denied on main" '[ "$(tool A Bash "{\"command\":\"cp $WB/p x\"}")" = deny ]'
ok "a locked-out session: denied, nothing recorded" \
  '[ "$(tool B Bash "{\"command\":\"git checkout claude/test-b -- p\"}" "$WA")" = deny ] && none'
ok "  its cp from a sibling into the worktree A owns: denied too, nothing recorded" \
  '[ "$(tool B Bash "{\"command\":\"cp $WB/p p\"}" "$WA")" = deny ] && none'
ok "  git -C <the worktree A owns> from the one B owns: a write into A's worktree, denied, nothing recorded" \
  '[ "$(tool B Bash "{\"command\":\"git -C $WA checkout claude/test-b -- p\"}" "$WB")" = deny ] && none'
ok "B carrying from A in the worktree B owns: allowed and recorded there" \
  '[ "$(tool B Bash "{\"command\":\"cp $WA/a x\"}" "$WB")" = allow ] && grep -q "^cp [0-9a-f]* claude/test-a$" "$GB/carries"'
rm -f "$GB/carries"

echo "pickup archive --confirmed is the owner's to type (D6, 2026-09-26)"
for shape in "/Users/x/projects/layer/bin/pickup archive claude/x --confirmed" "~/projects/layer/bin/pickup archive x --repo /tmp/r --confirmed" \
             "cd /tmp && python3 bin/pickup archive x --confirmed"; do
  ok "denied, from anywhere: $shape" '[ "$(tool A Bash "{\"command\":\"$shape\"}" "$P")" = deny ]'
done
ok "  the reason says whose it is and what to hand over" \
  'toolreason A Bash "{\"command\":\"bin/pickup archive x --confirmed\"}" "$P" | grep -q "pickup review"'
for shape in "bin/pickup review claude/x" "bin/pickup archive claude/x" "git commit -m 'pickup archive x --confirmed is the owner only'"; do
  ok "allowed: $shape" '[ "$(tool A Bash "{\"command\":\"$shape\"}" "$P")" = allow ]'
done

echo "deleting a claude/* branch or a worktree is the owner's act, never an agent's (D1, 2026-09-25)"
del() { tool A Bash "{\"command\":\"$1\"}" "${2:-$WA}"; }
for shape in "git branch -D claude/test-b" "git branch -d claude/test-b" "git branch --delete claude/test-b" \
             "git branch -Dr origin/claude/test-b" "cd $WB && git branch -D claude/test-b" "git -C $R branch -D claude/test-b" \
             "git branch --force -d claude/test-b" "git update-ref -d refs/heads/claude/test-b" \
             "git worktree remove $WB" "git worktree remove --force $WB"; do
  ok "denied: ${shape//$T/\$T}" '[ "$(del "$shape")" = deny ]'
done
ok "  the reason says it is never an agent's act and what happens instead (archived at session start)" \
  'toolreason A Bash "{\"command\":\"git branch -D claude/test-b\"}" "$WA" | grep -q "never an agent'"'"'s act" \
   && toolreason A Bash "{\"command\":\"git branch -D claude/test-b\"}" "$WA" | grep -q "archived by the session-start hook"'
ok "denied in a plain folder too" '[ "$(del "git branch -D claude/test-b" "$P")" = deny ]'
ok "denied on the primary checkout too" '[ "$(del "git branch -D claude/test-b" "$R")" = deny ]'
ok "a branch that is not claude/*: decided as before (a write in the own worktree: allowed)" \
  '[ "$(del "git branch -D feature")" = allow ]'
ok "  and on main: denied as before, by the main gate" '[ "$(del "git branch -D feature" "$R")" = allow ]'
ok "renaming a claude/* branch: not a deletion" '[ "$(del "git branch -m claude/test-b claude/test-c")" = allow ]'
ok "git worktree prune / list / add: allowed as before" \
  '[ "$(del "git worktree prune")" = allow ] && [ "$(del "git worktree list --porcelain")" = allow ] \
   && [ "$(del "git worktree add .claude/worktrees/c -b claude/test-c main")" = allow ]'
ok "/finish's own -raw handling: listing and re-pointing a -raw branch stay allowed" \
  '[ "$(del "git branch --list claude/*-raw")" = allow ] && [ "$(del "git branch -f claude/test-a-raw HEAD")" = allow ]'
GIT_COMMITTER_DATE='2020-01-01T00:00:00Z' git branch claude/gone-raw main; touch -t 202001010000 .git/claude/raw-sweep
ev A UserPromptSubmit "sweep still runs" "$WA" >/dev/null
ok "the hook's own -raw sweep still deletes (a subprocess, not a Bash command)" '! git show-ref -q --verify refs/heads/claude/gone-raw'

echo "one whitelisted shape is judged by the checkout it names; everything else by the baseline (D4, narrowed 2026-09-25)"
# d5 <command> [cwd]  — the decision for session A, the command passed verbatim (quotes, $, backticks)
d5() { jq -nc --arg c "${2:-$R}" --arg cmd "$1" \
  '{hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$cmd},session_id:"sessA-0000",cwd:$c}' \
  | python3 "$HOOK" | jq -r '.hookSpecificOutput.permissionDecision // "allow"' 2>/dev/null | grep . || echo allow; }
# A sibling opted-in repo with a free worktree, a plain repo that never opted in, a marked one.
S2="$T/sib"; mkdir -p "$S2/.claude" && git -C "$S2" init -q -b main && printf '.claude/worktrees/\n' > "$S2/.gitignore" \
  && printf '%s\n' '{"checkpoint": true, "main": "main",' '"live_write_regex": "scripts/deploy\\.py\\b(?![^|;&]*--check-only)"}' > "$S2/.claude/workflow.json" \
  && git -C "$S2" add -A && git -C "$S2" commit -qm base && git -C "$S2" worktree add -q "$S2/.claude/worktrees/sa" -b claude/sa main
SA="$S2/.claude/worktrees/sa"
N2="$T/noopt2"; git init -q -b main "$N2" && touch "$N2/x" && git -C "$N2" add x && git -C "$N2" commit -qm x
M2="$T/marked2"; mkdir -p "$M2/.claude" && git -C "$M2" init -q -b main && printf 'never\n' > "$M2/.claude/no-workflow" && touch "$M2/x" && git -C "$M2" add -A && git -C "$M2" commit -qm x
d4() { tool A Bash "{\"command\":\"$1\"}" "${2:-$R}"; }
ok "plain git commit on main: denied, unchanged" '[ "$(d4 "git commit -m x")" = deny ]'
ok "cd <the worktree this session owns> && git commit, from main: allowed" '[ "$(d4 "cd $WA && git commit -m x")" = allow ]'
ok "  git -C form: allowed" '[ "$(d4 "git -C $WA commit -m x")" = allow ]'
ok "cd <a worktree another session owns> && git commit, from main: denied by its lock" '[ "$(d4 "cd $WB && git commit -m x")" = deny ]'
ok "cd <a sibling primary on main, opted in> && git commit: judged by that primary (D8) — denied" \
  '[ "$(d4 "cd $S2 && git commit -m x")" = deny ]'
ok "two git steps after the cd: allowed (the /finish recipe)" '[ "$(d4 "cd $WA && git add -A && git commit -m x")" = allow ]'
for shape in "cd $WA && git commit -m 'git add the thing'" "cd $WA && git commit -m x; true" \
             "cd $WA && GIT_DIR=$R/.git git commit -m x" \
             "cd $WA && git commit -m x && python3 scripts/deploy.py x.yaml" \
             "cd $WA && git commit -m \"\$(date)\"" "cd $WA && git commit -m x || true"; do
  ok "not the whitelisted shape, so the baseline (main) decides: denied — ${shape//$T/\$T}" '[ "$(d5 "$shape")" = deny ]'
done
# Global options before the verb — `git -c k=v <verb>`, a second `-C`, `"git"`, `--git-dir=… --work-tree=…`
# — are writes since the owner's D6 (2026-09-25); the baseline's regex had never matched them. None is
# the whitelisted shape (`-c`, a git-dir override and a second `-C` are refused there), so on main
# the baseline denies them.
for shape in "cd $WA && git -c k=v commit -m x" "git -C $WA -C $WB commit -m x" \
             "cd $WA && git --git-dir=$R/.git --work-tree=$R commit -m x" "git -c 'user.name=a b' -C $WA commit -m x"; do
  ok "D6: a write the baseline now reads — denied on main: ${shape//$T/\$T}" '[ "$(d5 "$shape")" = deny ]'
done
ok "  git -c k=v commit in the worktree this session owns: allowed" '[ "$(d5 "git -c k=v commit -m x" "$WA")" = allow ]'
ok "  …in one another session owns: denied by its lock (before D6 it was not a write at all)" \
  '[ "$(d5 "git -c k=v commit -m x" "$WB")" = deny ]'
t0=$(date +%s); v=$(d5 "git $(printf -- '-c %.0s' $(seq 60))commit -m x"); t1=$(date +%s)
ok "  sixty repeated -c are decided at once (the draft prefix was exponential in them) — denied on main" \
  '[ "$v" = deny ] && [ $((t1 - t0)) -lt 5 ]'
ok "  reads with global options stay reads on main: --no-pager log, -c k=v status, -C x diff" \
  '[ "$(d5 "git --no-pager log -1")" = allow ] && [ "$(d5 "git -c color.ui=never status")" = allow ] && [ "$(d5 "git -C $WA diff")" = allow ]'
ok "a --git-dir override is not the shape; the baseline reads \`.git commit\` as a write, as it always did: denied" \
  '[ "$(d5 "cd $WA && git --git-dir=$R/.git commit -m x")" = deny ]'
ok "cd <a sibling worktree, free> && git commit: allowed, and its lock is now this session's" \
  '[ "$(d4 "cd $SA && git commit -m x")" = allow ] && jq -e ".session==\"sessA-0000\"" "$(git -C "$SA" rev-parse --absolute-git-dir)/claude/owner.json" >/dev/null'
ok "  so another session writing there is denied" '[ "$(tool B Bash "{\"command\":\"cd $SA && git commit -m x\"}" "$R")" = deny ]'
ok "cd <a repo that never opted in> && git commit: allowed (no gate there)" '[ "$(d4 "cd $N2 && git commit -m x")" = allow ]'
ok "cd <a no-workflow repo> && git commit: allowed" '[ "$(d4 "cd $M2 && git commit -m x")" = allow ]'
ok "a deploy script on main: denied, unchanged" '[ "$(d4 "python3 scripts/deploy.py x.yaml")" = deny ]'
ok "  cd <own worktree> && the deploy script: a script keeps the baseline — denied on main, knowingly (deploy.py anchors on its own path)" '[ "$(d4 "cd $WA && python3 scripts/deploy.py x.yaml")" = deny ]'
ok "  cd <unopted repo> && python3 <this repo's deploy script by absolute path>: denied — it would deploy this repo" \
  '[ "$(d4 "cd $N2 && python3 $R/scripts/deploy.py x.yaml")" = deny ]'
ok "  cd <sibling primary> && its deploy script: denied by the sibling's own live_write_regex" '[ "$(d4 "cd $S2 && python3 scripts/deploy.py x.yaml")" = deny ]'
ok "  --check-only there: allowed" '[ "$(d4 "cd $S2 && python3 scripts/deploy.py --all --check-only")" = allow ]'
ok "  cd <a repo with no live_write_regex> && a deploy script: the session's regex still decides — denied" '[ "$(d4 "cd $N2 && python3 scripts/deploy.py x.yaml")" = deny ]'
for shape in '(git commit -m x)' 'git commit -m x;true' 'git add f|cat' 'git add f&' 'echo "git add"' "echo 'git add'" 'echo `git add`'; do
  ok "the floor's endings, as the baseline had them — denied on main: $shape" '[ "$(d5 "$shape")" = deny ]'
done
for shape in "find . -name '*.pyc' -delete" 'rm -f .claude/settings.local.json' 'mv notes.md .claude/agents/notes.md' "find .claude -name '*.md'" \
             "grep -rn 'branch -D claude/' rules skills" "grep -rn 'worktree remove' skills" 'git log --oneline --grep "worktree remove"' \
             'git commit -m "Rules: never a deletion, not worktree remove"' 'git branch -d old-feature && git log -1 claude/test-b' \
             'git commit -m "drop claude/x -d"' 'git branch -m claude/laptop/2026-09-25-topic' 'ls .claude/worktrees' 'cat .claude/worktrees/b/f'; do
  ok "ordinary work, not a deletion: allowed — $shape" '[ "$(d5 "$shape" "$WA")" = allow ]'
done
# The shape's deny side (the owner's D8, 2026-09-25): X on its main is judged by X. Before, from a
# worktree the baseline judged by the session's own checkout and let a commit onto main through.
for shape in "cd $R && git commit -m x" "git -C $R commit -m x" "cd $R && git add -A && git commit -m x" \
             "cd $R/.claude && git commit -m x" "git -C $R checkout claude/test-b -- p" \
             "cd $R && git merge claude/test-a && git checkout claude/test-b -- p"; do
  ok "D8, from a worktree into the primary on main — denied: ${shape//$T/\$T}" '[ "$(d5 "$shape" "$WA")" = deny ]'
done
ok "  the reason says how the primary was reached and gives the recipe by absolute path" \
  'r=$(toolreason A Bash "{\"command\":\"cd $R && git commit -m x\"}" "$WA"); echo "$r" | grep -q "reached from a session in $WA" \
   && echo "$r" | grep -qF "git -C $R worktree add $R/.claude/worktrees/<topic>"'
for shape in "cd $R && git merge claude/test-a" "git -C $R merge --ff-only claude/test-a" "git -C $R pull -q --ff-only" \
             "cd $R && git pull --ff-only && git log -1" "git -C $R worktree add $R/.claude/worktrees/z -b claude/test-z main" "cd $R && git status"; do
  ok "D8, launching and reads there stay allowed: ${shape//$T/\$T}" '[ "$(d5 "$shape" "$WA")" = allow ]'
done
ok "  and took no lock on the primary" '[ ! -e .git/claude/owner.json ]'
ok "from a plain folder, cd <an opted-in primary> && git commit: judged by that primary (D8) — denied" '[ "$(d4 "cd $R && git commit -m x" "$P")" = deny ]'
ok "  cd <its worktree this session owns>: allowed" '[ "$(d4 "cd $WA && git commit -m x" "$P")" = allow ]'
ok "two targets in one command: not the shape, the baseline (main) denies" '[ "$(d4 "cd $WA && git commit -m x; cd $R && git commit -m y")" = deny ]'
ok "git merge-tree / merge-base on main: reads, allowed" \
  '[ "$(d4 "git merge-tree claude/test-b main")" = allow ] && [ "$(d4 "git merge-base main claude/test-b")" = allow ]'
ok "git pull --ff-only on main: launching, allowed (/finish brings the primary down)" \
  '[ "$(d4 "git pull -q --ff-only")" = allow ] && [ "$(d4 "git -C $R pull -q --ff-only" "$WA")" = allow ]'
ok "  a plain git pull on main: denied" '[ "$(d4 "git pull")" = deny ]'
# Edit/Write/NotebookEdit are judged by the FILE's checkout (D2, coding-on-workflow,
# 2026-09-26). Before, any path outside the session's own checkout was allowed with no gate.
fw() { tool "$1" "$2" "{\"file_path\":\"$3\"}" "$4"; }
ok "D2: from a worktree, Edit on the primary's main: denied" '[ "$(fw A Edit "$R/a" "$WA")" = deny ]'
ok "  the reason says where the session is and gives the recipe by absolute path" \
  'r=$(toolreason A Edit "{\"file_path\":\"$R/a\"}" "$WA"); echo "$r" | grep -q "reached from a session in $WA" \
   && echo "$r" | grep -qF "git -C $R worktree add $R/.claude/worktrees/<topic>"'
ok "  Write into a folder main does not have yet: judged by the nearest existing one — denied" '[ "$(fw A Write "$R/newdir/sub/f.md" "$WA")" = deny ]'
ok "  NotebookEdit too" '[ "$(tool A NotebookEdit "{\"notebook_path\":\"$R/n.ipynb\"}" "$WA")" = deny ]'
ok "  from a worktree, Edit on another opted-in repo's main: denied" '[ "$(fw A Edit "$S2/x" "$WA")" = deny ]'
ok "  from a plain folder, Edit on an opted-in main: denied" '[ "$(fw A Edit "$R/a" "$P")" = deny ]'
ok "  from the primary, Edit in the worktree this session owns: allowed (the file's checkout, not the cwd)" '[ "$(fw A Edit "$WA/new.md" "$R")" = allow ]'
ok "  from the primary, Edit in a worktree another session owns: denied by its lock" '[ "$(fw A Edit "$WB/p" "$R")" = deny ]'
ok "  from a sibling repo, into its worktree this session holds: allowed; another session there: denied" \
  '[ "$(fw A Edit "$SA/f" "$R")" = allow ] && [ "$(fw B Edit "$SA/f" "$R")" = deny ]'
ok "  a repo that never opted in, a no-workflow repo, a path in no repo: allowed" \
  '[ "$(fw A Edit "$N2/x" "$WA")" = allow ] && [ "$(fw A Edit "$M2/x" "$WA")" = allow ] && [ "$(fw A Write "$T/padA/notes.md" "$WA")" = allow ]'
touch "$S2/.git/MERGE_HEAD"
ok "  another repo's main mid-merge: resolving it is allowed, as on one's own" '[ "$(fw A Edit "$S2/x" "$WA")" = allow ]'
rm "$S2/.git/MERGE_HEAD"
ok "  the session's own checkout: judged as before — its main denied, its own worktree allowed" \
  '[ "$(fw A Edit "$R/a" "$R")" = deny ] && [ "$(fw A Edit "$WA/a" "$WA")" = allow ]'
ok "the primary checkout took no lock from any of this" '[ ! -e .git/claude/owner.json ]'
ok "a lock taken in a sibling through cd is remembered by this session, in its own file…" 'grep -q "sib/.git/worktrees/sa$" .git/claude/claimed-sessA-0000'
ev A SessionEnd
ok "  …and released with its own at SessionEnd" '[ ! -e "$(git -C "$SA" rev-parse --absolute-git-dir)/claude/owner.json" ] && [ ! -e .git/claude/claimed-sessA-0000 ]'

echo "hidden shapes, subshells and unresolvable targets: the baseline decides, never weaker than it was (fourth and fifth reviews)"
WS="$R/.claude/worktrees/with space"; git worktree add -q "$WS" -b claude/test-sp main
SP="$T/R2 sp"; mkdir -p "$SP/.claude" && git -C "$SP" init -q -b main && printf '{"checkpoint": true, "main": "main"}' > "$SP/.claude/workflow.json" \
  && touch "$SP/x" && git -C "$SP" add -A && git -C "$SP" commit -qm x
ln -s "$R" "$T/link"; ln -s "$T/loop" "$T/loop"
for shape in 'if true; then git commit -m x; fi' 'for f in f; do git add $f; done' 'echo f | xargs git add' 'bash -c "git commit -m x"' \
             'timeout 30 git commit -m x' '{ git commit -m x; }' 'nice git commit -m x' '! git commit -m x' 'git commit -m x || true' \
             'true && git commit -m x &' 'cd . && git commit -m x' 'if true; then git switch -c stray; fi' 'eval "git commit -m x"' \
             "(cd $WA && git status) && git commit -m x" "W=$R; cd \"\$W\" && git commit -m x" 'cd $PWD && git commit -m x' \
             'cd /no/such/dir && git commit -m x' 'cd `pwd` && git commit -m x' \
             "git -C $WA commit -m x && git -C $R commit -m x" "pushd $WA && popd && git commit -m x" "cd $T/loop && git commit -m x" \
             "cd $WA/.. && git commit -m x" "cd $T/link/.claude/worktrees/a/../.. && git commit -m x" \
             $'echo ok\ngit commit -m x' 'echo $(git commit -m x)' 'echo `git commit -m x`' '\git commit -m x' \
             'command git commit -m x' 'exec git commit -m x' "env GIT_DIR=$R/.git git commit -m x" "cd /tmp && GIT_DIR=$R/.git GIT_WORK_TREE=$R git commit -am x" \
             "export GIT_DIR=$R/.git; cd $P && git commit -am x" '/usr/bin/git commit -m x' "bash -lc 'git commit -m x'" \
             'find . -maxdepth 0 -exec git add f \;' "(cd $WA; git commit -m x); git commit -m y" "((cd $WA && git commit -m x))" \
             "cd $WA && (git commit -m x)" "cd $WA | git commit -m x" "cd $WA & git commit -m x" "false && cd $WA; git commit -m x" \
             "if false; then cd $WA; fi; git commit -m x" "true || cd $WA; git commit -m x" "bash -c \"cd $WA\"; git commit -m x" \
             $'(cd '"$WA"$' && git -c k=v commit -m ok); bash <<\'EOF\'\ngit commit -m sneaky\nEOF' "git -C $WA -c k=v add f && find . -maxdepth 0 -exec git add f \\;" \
             "cd $WA && python3 scripts/deploy.py a.yaml; cd $R && bash -lc 'python3 scripts/deploy.py b.yaml'" $'bash <<\'EOF\'\npython3 scripts/deploy.py b.yaml\nEOF'; do
  ok "on main, denied: ${shape//$T/\$T}" '[ "$(d5 "$shape")" = deny ]'
done
for shape in "git -C $WB commit -m x" "cd $WB && git commit -m x"; do
  ok "from a worktree into one another session owns: denied — ${shape//$T/\$T}" '[ "$(d5 "$shape" "$WA")" = deny ]'
done
for shape in 'git -C "$HOME" -C . commit -m x' '"git" commit -m x' "'git' add f" "git -C .claude/worktrees/a -C ../../.. commit -m x"; do
  ok "D6, the baseline reads it now — denied on main: $shape" '[ "$(d5 "$shape")" = deny ]'
done
ok "D8, from a worktree, cd <another opted-in repo on its main, path with a space> && git commit: denied" \
  '[ "$(d5 "cd \"$SP\" && git commit -m x" "$WA")" = deny ]'
# Kept gaps, knowingly (D8 closes the plain form only): a separator, a subshell or GIT_DIR takes the
# command out of the shape, and the baseline judges by the session's own worktree.
for shape in "cd $R; git commit -m x" "(cd $R && git commit -m x)" \
             "GIT_DIR=$R/.git git commit -m x" "(cd $R && git status) && git commit -m x"; do
  ok "from a worktree, the baseline judges by this worktree: allowed, as it always was — ${shape//$T/\$T}" '[ "$(d5 "$shape" "$WA")" = allow ]'
done
ok "cd into a worktree whose path has a space, from main: allowed" '[ "$(d5 "cd \"$WS\" && git commit -m x")" = allow ]'
for shape in 'B=claude/test-b; git branch -D "$B"' 'for b in claude/test-b; do git branch -D $b; done' 'echo claude/test-b | xargs git branch -D' \
             "printf 'delete refs/heads/claude/test-b\\n' | git update-ref --stdin" 'git update-ref --no-deref -d refs/heads/claude/test-b' \
             "W=$WB; git worktree remove \"\$W\"" 'if true; then git branch -D claude/test-b; fi' 'timeout 5 git branch -D claude/test-b' \
             "bash -c 'git branch -D claude/test-b'" 'git branch --delete --force claude/test-b' 'git branch -fd claude/test-b' \
             'git branch -D -- claude/test-b' "git branch -D 'claude/test-b'"; do
  ok "D1 through a hidden shape, denied: ${shape//$T/\$T}" '[ "$(d5 "$shape" "$WA")" = deny ]'
done
ok "rm -rf of a worktree directory (the workaround after a denied worktree remove): denied" \
  '[ "$(d5 "rm -rf .claude/worktrees/b")" = deny ] && [ "$(d5 "rm -rf $WB" "$WA")" = deny ]'
for shape in 'git branch --del claude/test-b' 'git branch --delet claude/test-b' 'git branch -D claude/{test-b,x}' 'git branch -D {claude/test-b,zz}' \
             'git branch -D claude/test-*' 'git branch -q -D claude/test-b' 'git branch -D claude/test-b feature' 'git branch -m claude/test-b gone' \
             "git worktree remove -f $WB" "bash -xc 'git branch -D claude/test-b'" "bash -lc 'git branch -D claude/test-b'" \
             'echo "$(git branch -D claude/test-b)"' '/usr/bin/git branch -D claude/test-b' 'git branch -D clau""de/test-b' \
             $'bash <<\'EOF\'\ngit branch -D claude/test-b\nEOF'; do
  ok "D1 (fifth review), denied: ${shape//$T/\$T}" '[ "$(d5 "$shape" "$WA")" = deny ]'
done
for shape in 'rm -r ".claude/worktrees/b"' 'rm -rf .claude/worktrees' 'rm -rf .claude' 'cd .claude && rm -rf worktrees/b' \
             '/bin/rm -rf .claude/worktrees/b' 'find .claude/worktrees -delete' 'mv .claude/worktrees/b /tmp/b'; do
  ok "D1 (fifth review), denied on the primary: $shape" '[ "$(d5 "$shape")" = deny ]'
done
# 2026-09-28: `rm <…>/.claude/worktrees/tidy/scripts/archive.py`, a file a session
# had made in its own worktree, was denied as "rm of a worktree directory" — the test was
# `.claude/worktrees` anywhere in the path. D1 covers the machinery only: `.claude`, the worktrees
# directory, a worktree, a worktree's .git; `mv` INTO a worktree is not a deletion either.
for shape in "rm $WA/scripts/archive.py" "rm -rf $WA/build/" "cd $WA && rm -rf scripts/old" \
             "cd $R/.claude/worktrees && rm a/scripts/x.py" "rm -rf .claude/worktrees/*/build" "mv $WA/a.py $WA/b.py" \
             "mv notes.md $WB" "mv notes.md $WB/docs/" "mv notes.md $R/.claude/worktrees" "find $WA/build -delete" \
             "rm $WA/.github/ci.yml" "rm -rf $WA/vendor/lib/.git" "bash -c 'rm $WA/scripts/x.py'" \
             $'bash <<\'EOF\'\nrm '"$WA"$'/scripts/x.py\nEOF' "echo \$(rm -rf $WA/build)"; do
  ok "inside a worktree, ordinary work — allowed: ${shape//$T/\$T}" '[ "$(d5 "$shape" "$WA")" = allow ]'
done
for shape in "rm -rf $WB/" "rm -rf .claude/worktrees/*" "rm -rf $R/.claude/worktrees/" "rm $WB/.git" "rm -rf $WB/scripts/.." \
             "rm -rf $WA/scripts/../../b" "cd $WA/scripts && rm -rf ../../b" "cd $R/.claude/worktrees && rm -rf b" \
             "mv $WB /tmp/b" "mv $WB $R/.claude/worktrees/c" "mv $WB/.git /tmp/g" "mv x $WB/.git" "mv -t /tmp $WB" \
             "mv --target-directory /tmp $WB" "find $WB -delete" "find $R/.claude/worktrees -name b -delete" \
             "bash -c 'rm -rf $WB/.git'" $'bash <<\'EOF\'\nrm -rf '"$WB"$'/\nEOF' $'bash <<\'EOF\'\nrm -f '"$WB"$'/.git\nEOF' \
             $'bash <<\'EOF\'\nrm -rf '"$WA"$'/scripts/../../b\nEOF' $'bash <<\'EOF\'\nmv '"$WB"$' /tmp/b\nEOF' \
             $'bash <<\'EOF\'\nfind '"$WB"$' -delete\nEOF' "echo \$(rm -rf $WB)"; do
  ok "the worktree machinery itself, still denied: ${shape//$T/\$T}" '[ "$(d5 "$shape" "$WA")" = deny ]'
done
ok "  the reason names what it was: a worktree's .git file" \
  'toolreason A Bash "{\"command\":\"rm $WB/.git\"}" "$WA" | grep -q "rm of a worktree.s .git file"'
ok "git worktree remove from a repo that never opted in: denied all the same" '[ "$(d5 "git worktree remove /tmp/whatever" "$N2")" = deny ]'
ok "not deletions, allowed as before: --merged, --no-merged, -D of a non-claude branch, a log under the worktrees dir" \
  '[ "$(d5 "git branch --merged main" "$WA")" = allow ] && [ "$(d5 "git branch -a --no-merged" "$WA")" = allow ] \
   && [ "$(d5 "git branch -D feature" "$WA")" = allow ] && [ "$(d5 "git log --oneline -- .claude/worktrees/" "$WA")" = allow ]'
ok "out of scope, unchanged: git branch -f, rm of a ref file" \
  '[ "$(d5 "git branch -f claude/test-a-raw HEAD" "$WA")" = allow ] && [ "$(d5 "rm .git/refs/heads/claude/test-b" "$WA")" = allow ]'
git worktree remove --force "$WS"; git branch -D claude/test-sp >/dev/null; rm -rf "$SP" "$T/link" "$T/loop"
git -C "$S2" worktree remove --force "$SA"; rm -rf "$S2" "$N2" "$M2"

echo "a push that fails is one note, never a retry and never a lost commit"
git remote set-url origin "$T/nowhere.git"
echo q > "$WB/q"; touch -t 202001010000 "$(git -C "$WB" rev-parse --absolute-git-dir)/claude/pushed"
out=$(ev B Stop "" "$WB")
ok "the commit is made and the failure is reported" \
  'echo "$out" | grep -q "push of claude/test-b failed" && [ -z "$(git -C "$WB" status --porcelain)" ]'
ok "  the next turn does not retry inside the spacing" '! ev B Stop "" "$WB" | grep -q "push of"'
git remote set-url origin "$T/origin.git"

echo "a repo that must never join the workflow (.claude/no-workflow)"
# The 2026-09-17 accident: `/new-project . --adopt` takes "." from whichever session is open,
# and adopted the knowledge layer — where ~/.claude points at the main checkout, so a worktree
# edit is live nowhere until it merges. The marker makes that mistake impossible to repeat.
M="$T/marked"; mkdir -p "$M/.claude"
g() { git -C "$M" -c user.name=t -c user.email=t@t "$@"; }
g init -q -b main && touch "$M/x" && g add x && g commit -q -m x
printf 'the shared layer must stay editable on main\nmore prose nobody quotes\n' > "$M/.claude/no-workflow"
printf '{"checkpoint": true, "main": "main"}' > "$M/.claude/workflow.json"   # slipped in beside it
ok "an opt-in beside the marker is inert: write on its main allowed" \
  '[ "$(tool A Edit "{\"file_path\":\"$M/x\"}" "$M")" = allow ]'
ok "  and the hook stays silent there" \
  '[ -z "$( { ev A UserPromptSubmit "hi" "$M"; ev A Stop "" "$M"; } 2>&1 )" ]'
rm "$M/.claude/workflow.json"
ok "Write of the opt-in file: denied" \
  '[ "$(tool A Write "{\"file_path\":\"$M/.claude/workflow.json\"}" "$M")" = deny ]'
ok "  denied from a session whose cwd is another repo entirely" \
  '[ "$(tool A Write "{\"file_path\":\"$M/.claude/workflow.json\"}" "$R")" = deny ]'
ok "  the reason quotes the marker's first line only" \
  'toolreason A Write "{\"file_path\":\"$M/.claude/workflow.json\"}" "$M" | grep -q "editable on main" \
   && ! toolreason A Write "{\"file_path\":\"$M/.claude/workflow.json\"}" "$M" | grep -q "nobody quotes"'
ok "/new-project's own command, absolute path: denied" \
  '[ "$(tool A Bash "{\"command\":\"cd $M && printf x > .claude/workflow.json && git add -A\"}" "$R")" = deny ]'
ok "/new-project's own command with a bare dot, run in the marked repo: denied" \
  '[ "$(tool A Bash "{\"command\":\"cd . && printf x > .claude/workflow.json && git add -A\"}" "$M")" = deny ]'
ok "no cd at all, run in the marked repo: denied" \
  '[ "$(tool A Bash "{\"command\":\"printf x > .claude/workflow.json\"}" "$M")" = deny ]'
ok "cp/tee forms of the same write: denied" \
  '[ "$(tool A Bash "{\"command\":\"cp /tmp/w .claude/workflow.json\"}" "$M")" = deny ] \
   && [ "$(tool A Bash "{\"command\":\"echo x | tee $M/.claude/workflow.json\"}" "$R")" = deny ]'
ok "mentioning the file without writing it: allowed (reads, history, greps)" \
  '[ "$(tool A Bash "{\"command\":\"cat .claude/workflow.json\"}" "$M")" = allow ] \
   && [ "$(tool A Bash "{\"command\":\"git log -- .claude/workflow.json\"}" "$M")" = allow ] \
   && [ "$(tool A Bash "{\"command\":\"ls -l $M/.claude/workflow.json\"}" "$R")" = allow ]'
ok "the file was never created by any of that" '[ ! -e "$M/.claude/workflow.json" ]'
ok "ordinary writes and commits in the marked repo stay allowed" \
  '[ "$(tool A Edit "{\"file_path\":\"$M/x\"}" "$M")" = allow ] \
   && [ "$(tool A Bash "{\"command\":\"git add -A && git commit -m x\"}" "$M")" = allow ]'
g add -A && g commit -q -m marker
g worktree add -q "$T/marked-wt" -b claude/wt main
rm "$T/marked-wt/.claude/no-workflow"
printf '{"checkpoint": true, "main": "main"}' > "$T/marked-wt/.claude/workflow.json"
ok "a worktree can't opt the repo in behind the marker's back" \
  '[ "$(tool A Edit "{\"file_path\":\"$T/marked-wt/x\"}" "$T/marked-wt")" = allow ]'
U="$T/unmarked"; mkdir -p "$U/.claude"; git -C "$U" init -q -b main
ok "a repo with no marker: adopting it is still allowed" \
  '[ "$(tool A Write "{\"file_path\":\"$U/.claude/workflow.json\"}" "$U")" = allow ] \
   && [ "$(tool A Bash "{\"command\":\"cd $U && printf x > .claude/workflow.json\"}" "$R")" = allow ]'

if [ -z "$KEEL" ]; then
echo "the D-list cases: skipped, keel not installed (G4) — the absent case is below"
else
echo "a doc that asks the owner something is pushed at once, and the reply carries its link (/keel, 2026-09-29)"
# origin reads as github.com, so a slug exists; insteadOf sends the traffic to a bare repo.
F="$T/fb"; mkdir -p "$F/.claude"; git init -q --bare "$T/fb-origin.git"
fg() { git -C "$F" "$@"; }
fg init -q -b main && printf '.claude/worktrees/\n' > "$F/.gitignore" \
  && printf '{"checkpoint": true, "main": "main"}' > "$F/.claude/workflow.json" \
  && fg add -A && fg commit -q -m base \
  && fg config "url.$T/fb-origin.git.insteadOf" https://github.com/owner/repo.git \
  && fg remote add origin https://github.com/owner/repo.git && fg push -q origin main
WD="$F/.claude/worktrees/d"; fg worktree add -q "$WD" -b claude/fb main
WD=$(cd "$WD" && pwd -P); GD="$(git -C "$WD" rev-parse --absolute-git-dir)/claude"
EDIT=https://github.com/owner/repo/edit/claude/fb/docs/m.md
BLOB=https://github.com/owner/repo/blob/claude/fb/docs/m.md
form() {  # form <doc>: a mirrored page for it — the form since 2026-10-14; unpinned, any page passes
  echo "https://spacesheep.dev/@sam/$(basename "$1" .md)"; }
# fev <last_assistant_message> [stop_hook_active] [cwd]  — session A's Stop (default cwd $WD)
fev() { jq -nc --arg s "$T/padA" --arg c "${3:-$WD}" --arg m "$1" --argjson a "${2:-false}" --arg n "$RANDOM$RANDOM" \
  '{hook_event_name:"Stop",scratchpad_dir:$s,session_id:"sessA-0000",cwd:$c,last_assistant_message:$m,stop_hook_active:$a,nonce:$n}' \
  | python3 "$HOOK"; }
fotip() { git -C "$T/fb-origin.git" rev-parse --verify -q refs/heads/claude/fb; }
ev A UserPromptSubmit "start" "$WD" >/dev/null; echo 1 > "$WD/a.txt"; fev "started" >/dev/null
ok "  the first checkpoint is pushed (the ordinary first push)" '[ "$(fotip)" = "$(git -C "$WD" rev-parse HEAD)" ]'
mkdir -p "$WD/docs"; printf '# Memo\n\n**D1 — Ship it?** Body.\n➤ Answer: yes.\n' > "$WD/docs/m.md"
out=$(fev "Wrote the memo.")
ok "  a turn adding an answer line is pushed at once, inside the push spacing" \
  '[ "$(fotip)" = "$(git -C "$WD" rev-parse HEAD)" ]'
ok "  ...and its reply is blocked once for the hand-over line, naming keel line" \
  '[ "$(echo "$out" | jq -r .decision)" = block ] && echo "$out" | jq -r .reason | grep -qF "keel line $WD/docs/m.md"'
ok "  ...and what the line lacks" 'echo "$out" | jq -r .reason | grep -qF "no line ends with the file link [m.md]($WD/docs/m.md#L1)"'
FM=$(form "$WD/docs/m.md")
printf -- '- **D2 — And this?**\n  ➤ Answer: no.\n' >> "$WD/docs/m.md"
out=$(fev "Memo: added D2 — [course]($FM) | [github]($BLOB) — [m.md]($WD/docs/m.md#L1)")
ok "  a reply that already ends with the line is not blocked" \
  '[ "$(fotip)" = "$(git -C "$WD" rev-parse HEAD)" ] && ! echo "$out" | grep -q "\"decision\""'
printf '**D3 — Third.** ➤ Answer: maybe.\n' >> "$WD/docs/m.md"
out=$(fev "Memo: D3." true)
ok "  blocked once already (stop_hook_active): no second block" '! echo "$out" | grep -q "\"decision\""'
perl -pi -e 's/➤ Answer: yes\./➤ Answer: no, wait./' "$WD/docs/m.md"
out=$(fev "Merged the answers.")
ok "  answers arriving (answer lines only, no D-item added): pushed at once, no block" \
  '[ "$(fotip)" = "$(git -C "$WD" rev-parse HEAD)" ] && ! echo "$out" | grep -q "\"decision\""'
perl -pi -e 's/➤ Answer: no\./➤ Answer: typed in the tab./' "$WD/docs/m.md"
ev A UserPromptSubmit "answered" "$WD" >/dev/null
ok "  the owner's tab edits are committed at the prompt" \
  'git -C "$WD" log -1 --format=%s | grep -q "^wip: changes between turns"'
fev "Read the answers." >/dev/null
ok "  ...and pushed at that turn's Stop, inside the push spacing" '[ "$(fotip)" = "$(git -C "$WD" rev-parse HEAD)" ]'
printf 'Approved.\n' >> "$WD/docs/m.md"
ev A UserPromptSubmit "answered" "$WD" >/dev/null; fev "Read it." >/dev/null
ok "  free text under a D (no answer line) in an answered doc: pushed at once too" \
  '[ "$(fotip)" = "$(git -C "$WD" rev-parse HEAD)" ]'
printf -- '# Indented\n\n- **D1 — Q?** Body.\n  ➤ Answer: x\n' > "$WD/docs/i.md"; fev "Wrote i. answer: $EDIT" >/dev/null
printf 'Fine by me.\n' >> "$WD/docs/i.md"
ev A UserPromptSubmit "answered" "$WD" >/dev/null; out=$(fev "Read it." false "$WD/docs")
ok "  a doc whose only answer line is indented, from a subfolder cwd: pushed at once, no block" \
  '[ "$(fotip)" = "$(git -C "$WD" rev-parse HEAD)" ] && ! echo "$out" | grep -q "\"decision\""'
printf '# Spaced\n\n**D1 — Q?** ➤ Answer: yes.\n' > "$WD/docs/a b.md"
out=$(fev "Wrote another.")
ok "  a path with a space: the block names keel line on the quoted path, no TAB" \
  'echo "$out" | jq -r .reason | grep -qF "keel line '"'"'$WD/docs/a b.md'"'"'" && ! echo "$out" | jq -r .reason | grep -q "$(printf "\t")"'
printf -- '# Relayed\n\n- **D1 — Land it?** Body.\n  ➤ Answer:\n' > "$WD/docs/r.md"
git -C "$WD" add docs/r.md && git -C "$WD" commit -q -m "Docs: D1 (relayed)"; fev "RELAYED TO the skipper." >/dev/null
ok "  a D-item the session committed itself (bin/ask relay) is pushed at once, inside the push spacing" \
  '[ "$(fotip)" = "$(git -C "$WD" rev-parse HEAD)" ]'
echo plain > "$WD/plain.txt"; git -C "$WD" add plain.txt && git -C "$WD" commit -q -m "plain"; fev "Done." >/dev/null
ok "  ...while its own commit of no doc still waits for the spacing" '[ "$(fotip)" != "$(git -C "$WD" rev-parse HEAD)" ]'
perl -pi -e 's/➤ Answer: typed in the tab\./➤ Answer: typed offline./' "$WD/docs/m.md"
ev A UserPromptSubmit "answered" "$WD" >/dev/null; mv "$T/fb-origin.git" "$T/fb-origin.off"
out=$(fev "Read them.")
ok "  tab edits with origin down: the forced push fails once, reported" 'echo "$out" | grep -q "push of claude/fb failed"'
ok "  ...and the next Stop, the wip commit still HEAD, does not retry it" '! fev "Still offline." | grep -q "push of"'
mv "$T/fb-origin.off" "$T/fb-origin.git"; git -C "$WD" push -q origin claude/fb  # leaves no unpushed doc for the mirror's deploy count
echo "  keel's own word on a page that deployed (a row's note: the publish budget's warning) joins the turn's note (spacesheep-tiers)"
cat > "$T/keel-note" <<'EOF'
import json, sys
print(json.dumps({"doc": sys.argv[-1], "url": "https://spacesheep.dev/@sam/n", "sha": "x", "deployed": True,
                  "note": "keel: 360 spacesheep publishes from this Mac in 24 h, near its part of the account's cap"}))
EOF
ok "  the 🐑 note ends with the warning" '[ "$(env -u CLAUDE_HOOK_NO_SHEEP python3 -c "import sys; sys.path.insert(0, sys.argv[1]); import checkpoint as c
c.ROOT, c.MEMO = sys.argv[2], sys.argv[3]
def no(): raise ImportError(\"stub\")
c._memo_module = no
print(c.sheep_pages(\"claude/fb\", [\"docs/s.md\"])[1])" "$MOD/hooks" "$WD" "$T/keel-note")" = "🐑 docs/s.md → https://spacesheep.dev/@sam/n · ⚠ keel: 360 spacesheep publishes from this Mac in 24 h, near its part of the account'"'"'s cap" ]'
echo "  the page mirror (orchestration E3): a stub CLI, a pinned page, the line's space part"
SS="$T/ss"; mkdir -p "$SS/state"
printf '#!/bin/sh\necho "$*" >> "%s/cli.log"\necho %s\n' "$SS" \
  "'{\"uuid\":\"sp-9\",\"url\":\"https://spacesheep.dev/@sam/sheep-memo\"}'" > "$SS/spacesheep"; chmod +x "$SS/spacesheep"
sfev() { (unset CLAUDE_HOOK_NO_SHEEP; export MEMO_SHEEP_BIN="$SS/spacesheep" MEMO_SHEEP_STATE="$SS/state" SPACESHEEP_KEY=ss_test
          fev "$@"); }
printf '# Sheep\n\n- **D1 — Mirror it?** Body.\n  ➤ Answer: yes.\n' > "$WD/docs/s.md"
SBLOB=https://github.com/owner/repo/blob/claude/fb/docs/s.md; FS=https://spacesheep.dev/@sam/sheep-memo
out=$(sfev "Wrote s. [github]($SBLOB) — [s.md]($WD/docs/s.md#L1)")
ok "  a pushed D-list doc is deployed once, after the push" \
  '[ "$(grep -c "^deploy" "$SS/cli.log")" = 1 ] && [ "$(fotip)" = "$(git -C "$WD" rev-parse HEAD)" ]'
ok "  ...a line without the page is blocked: with D-items the page is the form, and the course link is missing" \
  '[ "$(echo "$out" | jq -r .decision)" = block ] && echo "$out" | jq -r .reason | grep -qF "the course link is missing"'
ok "  ...and the turn's note names the page" 'echo "$out" | jq -r .systemMessage | grep -qF "docs/s.md → https://spacesheep.dev/@sam/sheep-memo"'
printf -- '- **D2 — Again?**\n  ➤ Answer: no.\n' >> "$WD/docs/s.md"
out=$(sfev "D2. [course]($FS) | [github]($SBLOB) — [s.md]($WD/docs/s.md#L1)")
ok "  a reply carrying the whole line (the page as form) passes, and the pinned space is updated" \
  '! echo "$out" | grep -q "\"decision\"" && grep -q -- "--space sp-9" "$SS/cli.log"'
mkdir -p "$SPACESHEEP_CONFIG_DIR"; sleep 120 > /dev/null 2>&1 & SSPID=$!
printf '{"pid": %s, "port": 4999, "site": "https://spacesheep.dev"}\n' "$SSPID" > "$SPACESHEEP_CONFIG_DIR/mirror.json"
printf -- '- **D2b — Mirrored?**\n  ➤ Answer: yes.\n' >> "$WD/docs/s.md"
out=$(sfev "D2b. [course](http://localhost:4999/@sam/sheep-memo) | [github]($SBLOB) | [space](https://spacesheep.dev/@sam/sheep-memo) — [s.md]($WD/docs/s.md#L1)")
ok "  with a mirror running, the note names the page at the mirror, and the line's local form link passes, space last" \
  'echo "$out" | jq -r .systemMessage | grep -qF "docs/s.md → http://localhost:4999/@sam/sheep-memo" && ! echo "$out" | grep -q "\"decision\""'
kill "$SSPID" 2>/dev/null; rm -f "$SPACESHEEP_CONFIG_DIR/mirror.json"
printf -- '- **D3 — Off?**\n  ➤ Answer: yes.\n' >> "$WD/docs/s.md"
fev "D3. answer: https://github.com/owner/repo/edit/claude/fb/docs/s.md" >/dev/null
ok "  CLAUDE_HOOK_NO_SHEEP (the suite's default): no deploy" '[ "$(grep -c "^deploy" "$SS/cli.log")" = 3 ]'
echo "  the form — the page — is owed wherever the doc has D-items and the page deploys (since 2026-10-14)"
printf -- '- **D4 — Form?**\n  ➤ Answer: yes.\n' >> "$WD/docs/s.md"
out=$(sfev "D4. [github]($SBLOB) — [s.md]($WD/docs/s.md#L1)")
ok "  ...a line without the form is blocked, the form link missing" \
  '[ "$(echo "$out" | jq -r .decision)" = block ] && echo "$out" | jq -r .reason | grep -qF "the course link is missing"'
printf -- '- **D5 — Form again?**\n  ➤ Answer: yes.\n' >> "$WD/docs/s.md"
out=$(sfev "D5. [course](http://127.0.0.1:8765/gone/) | [github]($SBLOB) — [s.md]($WD/docs/s.md#L1)")
ok "  ...a memo serve form link for a doc that has a page is blocked (the page is the form; review 2026-10-16)" \
  '[ "$(echo "$out" | jq -r .decision)" = block ] && echo "$out" | jq -r .reason | grep -qF "has a spacesheep page"'
printf -- '- **D6 — No page, unattended?**\n  ➤ Answer: yes.\n' >> "$WD/docs/s.md"
out=$(CLAUDE_UNATTENDED=test fev "D6. [github]($SBLOB) — [s.md]($WD/docs/s.md#L1)")
ok "  ...no page can deploy (CLAUDE_HOOK_NO_SHEEP) and an unattended run opens no memo serve: no form owed" '! echo "$out" | grep -q "\"decision\""'
printf -- '- **D7 — Asked in the reply?**\n  ➤ Answer:\n' >> "$WD/docs/s.md"
out=$(fev $'Please answer:\n- **D7 — Asked in the reply?**\n  ➤ Answer:')
ok "  ...a reply that itself asks (➤ Answer:) is bin/paste-paths' to judge: no second block here" \
  '! echo "$out" | grep -q "\"decision\""'

printf 'Prose quoting the ➤ Answer: marker mid-line.\n' > "$WD/docs/prose.md"; echo 2 >> "$WD/a.txt"
out=$(fev "Notes.")
ok "  prose that quotes the marker mid-line, and a.txt: no block, no early push" \
  '! echo "$out" | grep -q "\"decision\"" && [ "$(fotip)" != "$(git -C "$WD" rev-parse HEAD)" ]'
printf -- '# Agent\n\nEach item in this shape:\n\n    ```\n    - **D3 — <the decision>** (context).\n      - A — <option>\n\n      ➤ Recommended: B\n\n      ➤ Answer:\n    ```\n' > "$WD/docs/shape.md"
out=$(fev "Taught the shape.")
ok "  a fenced D-item example (agents/architect.md): no block, no early push (every match is inside a fence)" \
  '! echo "$out" | grep -q "\"decision\"" && [ "$(fotip)" != "$(git -C "$WD" rev-parse HEAD)" ]'
printf -- '\n- **D4 — Real one?** Body.\n  ➤ Answer:\n' >> "$WD/docs/shape.md"
out=$(fev "Added a real item.")
ok "  ...the same doc with a real D-item below the fence still blocks once for its links" \
  '[ "$(echo "$out" | jq -r .decision)" = block ] && echo "$out" | jq -r .reason | grep -qF "docs/shape.md"'
fev "Links. answer: https://github.com/owner/repo/edit/claude/fb/docs/shape.md" >/dev/null
printf -- '\nAnother example:\n\n```\n- **D9 — <example>**\n  ➤ Answer:\n```\n' >> "$WD/docs/shape.md"
out=$(fev "Added a second example.")
ok "  ...a commit adding only a fenced example to that doc asks nothing: no block (memo-lint-fixes item 3)" \
  '! echo "$out" | grep -q "\"decision\""'
printf -- '# Long fence\n\n````\nan example that opens a block it never closes:\n```\n- **D3 — <example>**\n  ➤ Answer:\n````\n' > "$WD/docs/long.md"; echo 6 >> "$WD/a.txt"
out=$(fev "Wrote the long-fence doc.")
ok "  a \`\`\`\` fence does not close at an inner \`\`\`: its example asks nothing, no early push (item 2)" \
  '! echo "$out" | grep -q "\"decision\"" && [ "$(fotip)" != "$(git -C "$WD" rev-parse HEAD)" ]'
printf -- '# Older shape\n\n~~~\nnot an item\n~~~\n\n1. **D1 Run the sweep nightly?**\n   ➤ Answer: yes\n' > "$WD/docs/old.md"; echo 3 >> "$WD/a.txt"
out=$(fev "Wrote the old-shape doc.")
ok "  an older shape memo does not parse (numbered, no separator after D1) stays an answer doc: pushed at once" \
  '[ "$(fotip)" = "$(git -C "$WD" rev-parse HEAD)" ]'
printf -- '# Inline, numbered\n\n1. **D1 Run the sweep nightly?** ➤ Answer: yes\n' > "$WD/docs/old2.md"; echo 4 >> "$WD/a.txt"
out=$(fev "Wrote another old-shape doc.")
ok "  an inline numbered \`1. **D1 Run …** ➤ Answer: yes\` stays an answer doc: pushed at once" \
  '[ "$(fotip)" = "$(git -C "$WD" rev-parse HEAD)" ]'
printf -- '# Inline, bold id\n\n**D2** Keep it? ➤ Answer: yes\n' > "$WD/docs/old3.md"; echo 5 >> "$WD/a.txt"
out=$(fev "And a third.")
ok "  an inline \`**D2** Keep it? ➤ Answer: yes\` stays an answer doc: pushed at once" \
  '[ "$(fotip)" = "$(git -C "$WD" rev-parse HEAD)" ]'

echo "  a GitHub link GitHub cannot show is blocked (registrar-access D7, 2026-10-04)"
git clone -q "$T/fb-origin.git" "$T/fb-web" 2>/dev/null; git -C "$T/fb-web" checkout -q claude/fb
perl -pi -e 's/➤ Answer: typed in the tab\./➤ Answer: typed on GitHub./' "$T/fb-web/docs/m.md"
git -C "$T/fb-web" -c user.name=t -c user.email=t@t commit -qam "Answer on GitHub" && git -C "$T/fb-web" push -q origin claude/fb 2>/dev/null
git -C "$WD" fetch -q origin 2>/dev/null
out=$(fev "Read it. answer: $EDIT")
ok "  only GitHub moved (the owner answered there): its copy is the newer, the link passes" '! echo "$out" | grep -q "\"decision\""'
printf -- '- **D4 — Fourth?**\n  ➤ Answer: yes.\n' >> "$WD/docs/m.md"
out=$(fev "D4 added. answer: $EDIT")
ok "  both moved: the push is refused, and the reply carrying the link is blocked" \
  '[ "$(echo "$out" | jq -r .decision)" = block ] && echo "$out" | jq -r .reason | grep -qF "keel line $WD/docs/m.md"'
out=$(fev "D4 added. answer: $EDIT" true)
ok "  ...once only (stop_hook_active)" '! echo "$out" | grep -q "\"decision\""'

fi

echo "keel absent (G4): no page, no hand-over-line block — skipped, never a crash"
# The core-only tree with a config that names no legacy checkout: common.tool("keel") is None.
NK="$T/no-keel"; mkdir -p "$NK/regatta"; [ -f "$REGATTA_CONFIG/regatta/owner" ] && cp "$REGATTA_CONFIG/regatta/owner" "$NK/regatta/owner"
nk() { REGATTA_CONFIG="$NK" python3 -c "import sys; sys.path.insert(0, sys.argv[1]); import checkpoint; $1" "$T/tree-core/modules/wharf/hooks" 2>&1; }
ok "  common.tool(\"keel\") is None there" '[ "$(nk "print(checkpoint.MEMO)")" = None ]'
ok "  the page: none, no deploy started" '[ "$(nk "print(checkpoint.sheep_pages(\"b\", [\"docs/d.md\"]))")" = "({}, None)" ]'
ok "  keel as a module: an ImportError each caller's except takes (no block)" \
  '[ "$(nk "
try:
    checkpoint._memo_module()
except ImportError as e:
    print(e)")" = "keel not installed" ]'
echo "in_place: a repo's records are written on its main (the vault, docs/record/personal-on-workflow-2026-09-29.md)"
# A scratch vault the config dir names as atlas's `atlas/vault` (the deny recipe for a knowledge
# repo names knowledge-commit; lib/knowledge.py), opted in with records, and auto-memory reaching
# it through a link the way ~/.claude/projects/<p>/memory does. The key goes into a copy of the
# suite's config dir, never the caller's, and the copy is used until the section ends.
CFG_BEFORE_VAULT=$REGATTA_CONFIG; KV="$T/vault-config"; cp -R "$REGATTA_CONFIG" "$KV" 2>/dev/null || mkdir -p "$KV"
mkdir -p "$KV/atlas"; export REGATTA_CONFIG="$KV"
O="$T/other"; mkdir -p "$O" && git -C "$O" init -q -b main
V="$T/notes"; mkdir -p "$V/.claude" "$V/memory/p" "$V/me" "$V/dreams"
printf '.claude/worktrees/\n' > "$V/.gitignore"
printf '{"checkpoint": true, "main": "main", "merge": "auto", "in_place": ["memory/", "dreams/", "log.md"]}\n' > "$V/.claude/workflow.json"
echo core > "$V/me/core.md"; echo m > "$V/memory/p/a.md"; echo l > "$V/log.md"
git -C "$V" init -q -b main && git -C "$V" add -A && git -C "$V" commit -qm base
V=$(cd "$V" && pwd -P); printf 'notes\n%s\n' "$V" > "$KV/atlas/vault"; mkdir -p "$T/claude-projects/p" && ln -s "$V/memory/p" "$T/claude-projects/p/memory"
ok "a memory Write through the link, from a session in another repo: allowed" \
  '[ "$(tool A Write "{\"file_path\":\"$T/claude-projects/p/memory/new.md\"}" "$O")" = allow ]'
ok "  a gated path in the same vault, from there: denied" \
  '[ "$(tool A Write "{\"file_path\":\"$V/me/core.md\"}" "$O")" = deny ]'
r=$(toolreason A Write "{\"file_path\":\"$V/me/core.md\"}" "$O")
ok "  ...with knowledge-commit's recipe, never git -C (a pinned session can't run it; item 16)" \
  'echo "$r" | grep -qF "knowledge-commit notes --open <slug>" && ! echo "$r" | grep -q "git -C"'
ok "  ...and the records it may write instead" 'echo "$r" | grep -qF "memory, dreams, log.md"'
ok "  climbing out of a record with .. is judged by where it ends up: denied" \
  '[ "$(tool A Write "{\"file_path\":\"$V/memory/../me/core.md\"}" "$O")" = deny ]'
ok "a session in the vault itself: dreams/x.md on main allowed (the dream)" \
  '[ "$(tool A Write "{\"file_path\":\"$V/dreams/x.md\"}" "$V")" = allow ]'
ok "  log.md, a file entry: allowed" '[ "$(tool A Edit "{\"file_path\":\"$V/log.md\"}" "$V")" = allow ]'
ok "  me/core.md: denied" '[ "$(tool A Edit "{\"file_path\":\"$V/me/core.md\"}" "$V")" = deny ]'
ok "  a name that only starts like a record (logbook.md): denied" \
  '[ "$(tool A Write "{\"file_path\":\"$V/logbook.md\"}" "$V")" = deny ]'
ok "  no lock taken by an in-place write" '[ ! -f "$V/.git/claude/owner.json" ]'
ok "  git commit on that main: still denied" \
  '[ "$(tool A Bash "{\"command\":\"git commit -m x\"}" "$V")" = deny ]'
out=$(ev A UserPromptSubmit "dream" "$V")
ok "  the prompt note names the in-place records, not a bare 'writes here are denied'" \
  'echo "$out" | jq -r .hookSpecificOutput.additionalContext | grep -qF "in-place records (memory, dreams, log.md)"'
echo more >> "$V/log.md"; echo d > "$V/dreams/x.md"
out=$(ev A Stop "" "$V")
ok "  Stop with only in-place dirt on main: no 'slipped past' warning" '! echo "$out" | grep -q "slipped past"'
echo hand >> "$V/me/core.md"; out=$(ev A Stop "" "$V")
ok "  Stop with a gated file dirty on main: warned" 'echo "$out" | grep -q "slipped past"'
git -C "$V" checkout -q -- me/core.md
VW="$V/.claude/worktrees/w"; git -C "$V" worktree add -q "$VW" -b claude/w main
ok "in a claude/* worktree of the vault, a memory write is ordinary work: allowed" \
  '[ "$(tool A Write "{\"file_path\":\"$VW/memory/p/b.md\"}" "$VW")" = allow ]'
ok "  ...and it claims that worktree's lock as any write does" \
  '[ "$(jq -r .session "$(git -C "$VW" rev-parse --absolute-git-dir)/claude/owner.json")" = sessA-0000 ]'
ok "  session B is locked out of it, records included" \
  '[ "$(tool B Write "{\"file_path\":\"$VW/memory/p/c.md\"}" "$VW")" = deny ]'
printf '{"checkpoint": true, "main": "main", "in_place": "memory/"}\n' > "$V/.claude/workflow.json"
ok "an in_place that is not a list grants nothing" \
  '[ "$(tool A Write "{\"file_path\":\"$T/claude-projects/p/memory/new.md\"}" "$O")" = deny ]'
export REGATTA_CONFIG="$CFG_BEFORE_VAULT"

echo "a worktree Claude Code spawned (worktree-<slug>) joins the workflow at its first write (orchestration E2)"
# The way 2.1.288 makes one: `worktree add --no-track -B worktree-<slug> <path> origin/<main>`.
mkdir -p "$T/padC"
spawn() { git -C "$R" fetch -q origin && git -C "$R" worktree add -q --no-track -B "worktree-$1" "$R/.claude/worktrees/$1" origin/main; }
br() { git -C "$R/.claude/worktrees/$1" branch --show-current; }
spawn bridge-r1
tool C Bash '{"command":"ls"}' "$R/.claude/worktrees/bridge-r1" >/dev/null
ok "a read changes nothing: still worktree-bridge-r1" '[ "$(br bridge-r1)" = worktree-bridge-r1 ]'
tool C Write "{\"file_path\":\"$R/.claude/worktrees/bridge-r1/n.md\"}" "$R/.claude/worktrees/bridge-r1" >/dev/null
ok "the first Write renames it to claude/<host>/<date>-bridge-r1" \
  'case "$(br bridge-r1)" in claude/*/20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]-bridge-r1) true ;; *) false ;; esac'
spawn bridge-r2
tool C Bash '{"command":"git commit --allow-empty -m x"}' "$R/.claude/worktrees/bridge-r2" >/dev/null
ok "  and so does a git write in Bash" 'case "$(br bridge-r2)" in claude/*-bridge-r2) true ;; *) false ;; esac'
spawn bridge-r3
echo dirt > "$R/.claude/worktrees/bridge-r3/d.txt"
ev C Stop "" "$R/.claude/worktrees/bridge-r3" >/dev/null
ok "  a write no PreToolUse saw is adopted at Stop, and checkpointed" \
  'case "$(br bridge-r3)" in claude/*-bridge-r3) [ -z "$(git -C "$R/.claude/worktrees/bridge-r3" status --porcelain)" ] ;; *) false ;; esac'
git clone -q "$T/origin.git" "$T/ahead" && echo 1 > "$T/ahead/up" && git -C "$T/ahead" add up \
  && git -C "$T/ahead" commit -qm up && git -C "$T/ahead" push -q origin main
spawn bridge-r4
tool C Write "{\"file_path\":\"$R/.claude/worktrees/bridge-r4/n.md\"}" "$R/.claude/worktrees/bridge-r4" >/dev/null
ok "  a spawn from an origin/main that local main lags is still adopted" 'case "$(br bridge-r4)" in claude/*-bridge-r4) true ;; *) false ;; esac'
spawn bridge-r5 && echo 1 > "$R/.claude/worktrees/bridge-r5/own" && git -C "$R/.claude/worktrees/bridge-r5" add own \
  && git -C "$R/.claude/worktrees/bridge-r5" commit -qm own
out=$(jq -nc --arg c "$R/.claude/worktrees/bridge-r5" --arg f "$R/.claude/worktrees/bridge-r5/n.md" \
  '{hook_event_name:"PreToolUse",tool_name:"Write",tool_input:{file_path:$f},session_id:"sessC-0000",cwd:$c}' | python3 "$HOOK")
ok "  one with commits of its own keeps its name" '[ "$(br bridge-r5)" = worktree-bridge-r5 ]'
ok "    and its writes stay quiet (no note per write)" '! echo "$out" | grep -q "commits of its own"'
echo dirt > "$R/.claude/worktrees/bridge-r5/d.txt"
ok "    the turn's Stop says why it was not renamed" \
  'ev C Stop "" "$R/.claude/worktrees/bridge-r5" | grep -q "has commits of its own"'
spawn bridge-r6
ok "  a prompt in a fresh spawn before any write: no false checkpoints-OFF nag" \
  '! ev C UserPromptSubmit "hi" "$R/.claude/worktrees/bridge-r6" | grep -q "checkpoints are OFF"'
ok "    but a prompt where it has commits of its own still gets it" \
  'ev C UserPromptSubmit "hi" "$R/.claude/worktrees/bridge-r5" | grep -q "checkpoints are OFF"'

echo "the /move marker: a worktree whose branch went on elsewhere takes no writes (teleport design E4)"
WM="$R/.claude/worktrees/mv"; git -C "$R" worktree add -q "$WM" -b claude/laptop/2026-10-02-mv main
GM="$(git -C "$WM" rev-parse --absolute-git-dir)/claude"
tool A Edit "{\"file_path\":\"$WM/a\"}" "$WM" >/dev/null   # A owns it, as the session that moved would
ev A UserPromptSubmit "before the move" "$WM" >/dev/null
printf '{"to": "buildbox", "session": "65046969-aaaa", "from_session": "sessA-0000", "at": %s, "branch": "claude/laptop/2026-10-02-mv", "pending": false}\n' \
  "$(date +%s)" > "$GM/teleported.json"
HM=$(core 'print(common.host_name())')
LAPTOP=$(core 'print(common.LAPTOP)')   # the config's laptop, the host that types every leg (a word without one)
if [ "$HM" = "$LAPTOP" ]; then back="/move --from-buildbox 'mv' to bring it back"; else back="on $LAPTOP: /move --to-home sends it back"; fi
ok "Edit there, even by the lock's owner: denied, the reason says where it went and the way back" \
  'toolreason A Edit "{\"file_path\":\"$WM/a\"}" "$WM" | grep -qF "moved to buildbox at" \
   && toolreason A Edit "{\"file_path\":\"$WM/a\"}" "$WM" | grep -qF "$back"'
ok "  git push of its own branch there, the one push shape allowed elsewhere: denied with the reason" \
  'toolreason A Bash "{\"command\":\"git push --force-with-lease -u origin claude/laptop/2026-10-02-mv\"}" "$WM" | grep -qF "moved to buildbox"'
ok "  …and through -C from the primary" \
  'toolreason B Bash "{\"command\":\"git -C $WM push -u origin claude/laptop/2026-10-02-mv\"}" "$R" | grep -qF "moved to buildbox"'
ok "  the same push from an unmarked worktree: still allowed" \
  '[ "$(tool B Bash "{\"command\":\"git push -u origin claude/test-b\"}" "$WB")" = allow ]'
ok "  the reason names the session it went on as" 'toolreason A Edit "{\"file_path\":\"$WM/a\"}" "$WM" | grep -qF "(session 65046969)"'
ok "  git commit there: denied with the reason" \
  'toolreason A Bash "{\"command\":\"git add -A && git commit -m x\"}" "$WM" | grep -qF "moved to buildbox"'
ok "  a deploy there: denied" '[ "$(tool A Bash "{\"command\":\"python3 scripts/deploy.py x.yaml\"}" "$WM")" = deny ]'
ok "  reads there: allowed" '[ "$(tool A Bash "{\"command\":\"git log -3; git status; cat a\"}" "$WM")" = allow ]'
ok "  a Write to the scratchpad: allowed" '[ "$(tool A Write "{\"file_path\":\"$T/padA/x\"}" "$WM")" = allow ]'
ok "  Edit into it from another checkout: denied with the reason" \
  'toolreason B Edit "{\"file_path\":\"$WM/a\"}" "$R" | grep -qF "moved to buildbox"'
ok "  cd <it> && git commit from the primary: denied with the reason" \
  'toolreason B Bash "{\"command\":\"cd $WM && git commit -m x\"}" "$R" | grep -qF "moved to buildbox"'
out=$(ev A UserPromptSubmit "still typing in the old tab" "$WM")
ok "a prompt there prints the line to the owner and tells Claude" \
  'echo "$out" | jq -r .systemMessage | grep -qF "moved to buildbox" \
   && echo "$out" | jq -r .hookSpecificOutput.additionalContext | grep -qF "moved to buildbox"'
ok "  and the moved session's lock is released, so the one bringing it back is not locked out" '[ ! -e "$GM/owner.json" ]'
ok "  no commit-summary reminder there" '! echo "$out" | grep -qF "commit-summary"'
echo left > "$WM/left"; head_before=$(git -C "$WM" rev-parse HEAD)
out=$(ev A Stop "" "$WM"); ev A UserPromptSubmit "again" "$WM" >/dev/null
ok "  Stop says the changed file is not checkpointed" 'echo "$out" | grep -qF "NOT checkpointed — moved to buildbox"'
ok "  dirt there is neither committed at Stop nor at the next prompt" \
  '[ "$(git -C "$WM" rev-parse HEAD)" = "$head_before" ] && [ -n "$(git -C "$WM" status --porcelain)" ]'
ok "  and nothing was pushed" '[ -z "$(otip claude/laptop/2026-10-02-mv)" ]'
printf '{"session": "sessA-0000", "branch": "claude/laptop/2026-10-02-mv", "seen": %s}' "$(date +%s)" > "$GM/owner.json"
ev A SessionEnd "" "$WM"
ok "SessionEnd still frees the lock, and pushes nothing" \
  '[ ! -e "$GM/owner.json" ] && [ -z "$(otip claude/laptop/2026-10-02-mv)" ]'
printf '{"to": "buildbox", "session": "65046969-aaaa", "at": 1e18, "pending": false}\n' > "$GM/teleported.json"
ok "a marker whose time is out of range (ns, say) still denies — never a crash that fails open" \
  'toolreason A Edit "{\"file_path\":\"$WM/a\"}" "$WM" | grep -qF "moved to buildbox at ?"'
printf '{"to": "%s", "session": null, "at": %s, "branch": "claude/laptop/2026-10-02-mv", "pending": true}\n' \
  "$LAPTOP" "$(date +%s)" > "$GM/teleported.json"
ok "a pending marker: the reason names the target and the line to type there" \
  'toolreason A Edit "{\"file_path\":\"$WM/a\"}" "$WM" | grep -qF "waiting to move to $LAPTOP" \
   && toolreason A Edit "{\"file_path\":\"$WM/a\"}" "$WM" | grep -qE "On $LAPTOP: /move --from-[a-z0-9-]+ '"'"'mv'"'"'"'
printf 'not json' > "$GM/teleported.json"
ok "an unreadable marker blocks nothing (never a stuck worktree over a bad file)" \
  '[ "$(tool A Edit "{\"file_path\":\"$WM/a\"}" "$WM")" = allow ]'
rm "$GM/teleported.json"
ok "the marker gone (the work came back): writes allowed again" '[ "$(tool A Edit "{\"file_path\":\"$WM/a\"}" "$WM")" = allow ]'

echo "session titles (A4): Stop names the session <repo>: <topic> from its branch, once"
WT="$R/.claude/worktrees/titles"; git -C "$R" worktree add -q "$WT" -b claude/laptop/2026-10-04-title-demo main
# stopt <session-id> <transcript>  — a Stop carrying transcript_path, as the real payload does
stopt() { jq -nc --arg id "$1" --arg tp "$2" --arg c "$WT" --arg n "$RANDOM$RANDOM" \
  '{hook_event_name:"Stop",session_id:$id,transcript_path:$tp,cwd:$c,last_assistant_message:"",nonce:$n}' | python3 "$HOOK"; }
titles() { grep -c "\"customTitle\":\"$2\"" "$1"; }
TP1="$T/t1.jsonl"; printf '%s\n' '{"type":"ai-title","aiTitle":"Some guess","sessionId":"t1"}' > "$TP1"
out=$(stopt t1 "$TP1")
ok "an untitled session gets custom-title and agent-name, as /rename writes them" \
  '[ "$(titles "$TP1" "repo: title demo")" = 1 ] && grep -qF "\"agentName\":\"repo: title demo\"" "$TP1"'
ok "  and Stop says so" 'echo "$out" | jq -r .systemMessage | grep -qF "named this session “repo: title demo”"'
ok "  the sidecar VS Code's list reads, as /rename writes it, owner-only" \
  '[ "$(cat "$T/t1/custom-title.json")" = "{\"customTitle\":\"repo: title demo\"}" ] && [ "$(fmode "$T/t1/custom-title.json")" = 600 ]'
stopt t1 "$TP1" >/dev/null
ok "  a second Stop writes nothing more" '[ "$(titles "$TP1" "repo: title demo")" = 1 ] && [ "$(wc -l < "$TP1")" -eq 3 ]'
TP7="$T/t7.jsonl"; printf '%s' '{"type":"user","message":"cut sho' > "$TP7"
stopt t7 "$TP7" >/dev/null
ok "a torn last line gets its newline first: the record stands on its own line" \
  '[ "$(sed -n 2p "$TP7" | jq -r .customTitle)" = "repo: title demo" ]'
TP2="$T/t2.jsonl"; printf '%s\n' '{"type":"user","message":{"content":"mentions \"custom-title\" in text"}}' > "$TP2"
stopt t2 "$TP2" >/dev/null
ok "the word in a message is not a title: the session is still named" '[ "$(titles "$TP2" "repo: title demo")" = 1 ]'
TP3="$T/t3.jsonl"; printf '%s\n' '{"type":"custom-title","customTitle":"mine","sessionId":"t3"}' > "$TP3"
stopt t3 "$TP3" >/dev/null
ok "an existing custom-title (a /rename, a /move fork) is kept" \
  '[ "$(wc -l < "$TP3")" -eq 1 ] && grep -qF "\"customTitle\":\"mine\"" "$TP3" && [ ! -e "$T/t3" ]'
TP4="$T/t4.jsonl"; out=$(stopt t4 "$TP4")
ok "a transcript not there yet: nothing written, not even the file, no warning" \
  '! echo "$out" | grep -qF "title" && [ ! -e "$TP4" ] && [ ! -e "$T/t4" ]'
: > "$TP4"; stopt t4 "$TP4" >/dev/null
ok "  the next Stop, once it exists, names it" '[ "$(titles "$TP4" "repo: title demo")" = 1 ]'
TP5="$T/t5.jsonl"; : > "$TP5"; chmod 444 "$TP5"
out=$(stopt t5 "$TP5"); chmod 644 "$TP5"
ok "a failed write costs a note, never the hook" 'echo "$out" | jq -r .systemMessage | grep -qF "session title failed"'
stopt t5 "$TP5" >/dev/null
ok "  and is tried again at the next Stop: the records are committed, the sidecar is kept" \
  '[ "$(titles "$TP5" "repo: title demo")" = 1 ] && [ -e "$T/t5/custom-title.json" ]'
TP6="$T/t6.jsonl"; : > "$TP6"
jq -nc --arg tp "$TP6" --arg c "$R" '{hook_event_name:"Stop",session_id:"t6",transcript_path:$tp,cwd:$c,nonce:"x6"}' | python3 "$HOOK" >/dev/null
ok "on main: no title" '[ ! -s "$TP6" ]'
GT="$(git -C "$WT" rev-parse --absolute-git-dir)/claude"
printf '{"session": "other-0000", "branch": "claude/laptop/2026-10-04-title-demo", "seen": %s}' "$(date +%s)" > "$GT/owner.json"
TP8="$T/t8.jsonl"; : > "$TP8"; stopt t8 "$TP8" >/dev/null; rm "$GT/owner.json"
ok "a session locked out of the worktree: no title" '[ ! -s "$TP8" ] && [ ! -e "$T/t8" ]'
ok "topics: no word left, no title; empty dashes collapse; old and new branch shapes" \
  '[ "$(cd "$(dirname "$HOOK")" && python3 -c "import checkpoint as c; print([c.branch_topic(b) for b in [\"claude/laptop/2026-10-04\", \"claude/buildbox/2026-10-04-\", \"claude/a/b/c\", \"claude/x/2026-10-04-a--b\", \"claude/2026-09-22-files-local-first\", \"claude/laptop/2026-10-04-session-titles\"]])")" \
   = "[None, None, None, '"'"'a b'"'"', '"'"'files local first'"'"', '"'"'session titles'"'"']" ]'

echo "an unattended run (CLAUDE_UNATTENDED, bin/dispatch) is read-only on live systems"
# Its own repo, the home repo's shape: a deploy regex plus an unattended-only regex for what acts on
# the house without being a deploy. The worktree is on a claude/* branch, where a deploy is allowed.
U="$T/unatt"; mkdir -p "$U/.claude" && git -C "$U" init -q -b main \
  && printf '%s\n' '{"checkpoint": true, "main": "main",' \
     '"live_write_regex": "scripts/deploy\\.py\\b(?![^|;&]*--check-only)",' \
     '"unattended_deny_regex": "scripts/ha\\.py\\s+call\\b"}' > "$U/.claude/workflow.json" \
  && printf '.claude/worktrees/\n' > "$U/.gitignore" && git -C "$U" add -A && git -C "$U" commit -q -m base
U=$(cd "$U" && pwd -P); UW="$U/.claude/worktrees/u"
git -C "$U" worktree add -q "$UW" -b claude/test-unattended main
ut() { CLAUDE_UNATTENDED=dispatch tool A Bash "{\"command\":\"$1\"}" "$UW"; }
ok "attended: a deploy on a claude/* branch is allowed" \
  '[ "$(tool A Bash "{\"command\":\"python3 scripts/deploy.py x.yaml\"}" "$UW")" = allow ]'
ok "unattended: the same deploy is denied" '[ "$(ut "python3 scripts/deploy.py x.yaml")" = deny ]'
ok "  and the reason says why and what to do instead" \
  'CLAUDE_UNATTENDED=dispatch toolreason A Bash "{\"command\":\"python3 scripts/deploy.py x.yaml\"}" "$UW" | grep -q "open item for the owner"'
ok "unattended: --check-only is a read, allowed" '[ "$(ut "python3 scripts/deploy.py x.yaml --check-only")" = allow ]'
ok "unattended: the repo's unattended_deny_regex is denied" '[ "$(ut "python3 scripts/ha.py call light.turn_on")" = deny ]'
ok "  attended, the same call is allowed" \
  '[ "$(tool A Bash "{\"command\":\"python3 scripts/ha.py call light.turn_on\"}" "$UW")" = allow ]'
ok "unattended: a reading ha.py is allowed" '[ "$(ut "python3 scripts/ha.py state light.kitchen")" = allow ]'
ok "unattended: any --live-ok or --estate-ok is denied — nobody gave that yes" \
  '[ "$(ut "python3 scripts/other.py --live-ok")" = deny ] && [ "$(ut "bin/x --estate-ok")" = deny ]'
ok "unattended: ordinary work (tests, git status) is allowed" \
  '[ "$(ut "bash scripts/test.sh && git status")" = allow ]'
shed=$(cd "$MOD/hooks" && CLAUDE_UNATTENDED=dispatch python3 - <<'PYSHED'
import importlib.util as u
s = u.spec_from_file_location("cp_shed", "checkpoint.py"); m = u.module_from_spec(s); s.loader.exec_module(m)
deny = ["env -u CLAUDE_UNATTENDED bin/dispatch b --mode yolo", "unset CLAUDE_UNATTENDED; bin/dispatch b",
        "CLAUDE_UNATTENDED= bin/helm mode s yolo", "CLAUDE_UNATTENDED='' bin/helm mode s yolo",
        "DISPATCH_LABEL=x bin/dispatch b --yolo", "cd x && env FOO=1 DISPATCH_LABEL=y bin/dispatch b", "env -i bin/dispatch b",
        "export CLAUDE_UNATTENDED= && bin/helm mode s yolo", "export CLAUDE_UNATTENDED=''; bin/x", "export DISPATCH_LABEL=x; bin/dispatch b",
        "export FOO=1 DISPATCH_LABEL=x", "export FOO DISPATCH_LABEL=x", "declare -x DISPATCH_LABEL=x", "typeset -gx CLAUDE_UNATTENDED=",
        "export -n CLAUDE_UNATTENDED; bin/x", "declare +x CLAUDE_UNATTENDED", "typeset +x CLAUDE_UNATTENDED", "declare -g +x CLAUDE_UNATTENDED",
        "local DISPATCH_LABEL=y"]
# a shed inside a quoted second shell passes on purpose: that is intent, not accident (the hook's header)
allow = ['git commit -qm "Fix: env -u CLAUDE_UNATTENDED is denied"', "grep -n DISPATCH_LABEL= bin/dispatch",
         "CLAUDE_UNATTENDED=dispatch bash tests/x.sh", "export CLAUDE_UNATTENDED=dispatch; bash t.sh", "export PATH=/x:$PATH && make",
         "declare -x FOO=1", "export -n FOO", "bash -c 'unset CLAUDE_UNATTENDED; bin/x'", "grep -n 'export -n CLAUDE_UNATTENDED' x"]
print([c for c in deny if "sheds" not in (m.unattended_live(c, "/tmp") or "")], [c for c in allow if m.unattended_live(c, "/tmp")])
PYSHED
)
ok "unattended: shedding CLAUDE_UNATTENDED (export, declare, an un-export too) or typing DISPATCH_LABEL is denied; a mention is no act (skipper-modes landing review 20, follow-ups item 2)" \
  '[ "$shed" = "[] []" ]'
# the marker's new name (vendor-fence's stage 1): dropping it is a shed too, and either name alone marks the run
shed2=$(cd "$MOD/hooks" && env -u CLAUDE_UNATTENDED REGATTA_UNATTENDED=dispatch python3 - <<'PYSHED2'
import importlib.util as u
s = u.spec_from_file_location("cp_shed2", "checkpoint.py"); m = u.module_from_spec(s); s.loader.exec_module(m)
deny = ["env -u REGATTA_UNATTENDED bin/dispatch b --mode yolo", "unset REGATTA_UNATTENDED; bin/dispatch b",
        "REGATTA_UNATTENDED= bin/helm mode s yolo", "export -n REGATTA_UNATTENDED; bin/x", "declare +x REGATTA_UNATTENDED",
        "env -u CLAUDE_UNATTENDED bin/dispatch b", "unset CLAUDE_UNATTENDED; bin/x", "env -i bin/dispatch b"]
allow = ['git commit -qm "Fix: env -u REGATTA_UNATTENDED is denied"', "REGATTA_UNATTENDED=dispatch bash tests/x.sh",
         "grep -n 'unset REGATTA_UNATTENDED' x"]
print([c for c in deny if "sheds" not in (m.unattended_live(c, "/tmp") or "")], [c for c in allow if m.unattended_live(c, "/tmp")],
      m.unattended_mark())
PYSHED2
)
ok "unattended under REGATTA_UNATTENDED alone: dropping either name is denied, a mention is no act (vendor-fence stage 1)" \
  '[ "$shed2" = "[] [] REGATTA_UNATTENDED=dispatch" ]'
old_only=$(cd "$MOD/hooks" && env -u REGATTA_UNATTENDED CLAUDE_UNATTENDED=dispatch python3 -c '
import importlib.util as u
s = u.spec_from_file_location("cp_old", "checkpoint.py"); m = u.module_from_spec(s); s.loader.exec_module(m)
print(m.unattended_mark(), "sheds" in (m.unattended_live("unset REGATTA_UNATTENDED; bin/x", "/tmp") or ""))')
ok "  the old name alone is still honoured: the run reads unattended and its new name may not be dropped" \
  '[ "$old_only" = "CLAUDE_UNATTENDED=dispatch True" ]'
rec=$(cd "$MOD/hooks" && CLAUDE_UNATTENDED=dispatch HOME="$T/rh" PLANS_DIR="$T/rh/pl" python3 - <<'PYREC'
import importlib.util as u
s = u.spec_from_file_location("cp_rec", "checkpoint.py"); m = u.module_from_spec(s); s.loader.exec_module(m)
deny = ["echo '{}' > ~/Library/Logs/claude-weekly/plans/s1/plan.json", "printf x >> $HOME/Library/Logs/claude-weekly/plans/branch-modes.json",
        "jq . /tmp/x > ${HOME}/Library/Logs/claude-weekly/run-seed-runs/a.json", "sed -i.bak s/ask/yolo/ ~/Library/Logs/claude-weekly/run-seed-runs/a.json",
        "cp /tmp/r.json ~/Library/Logs/claude-weekly/run-seed-runs/r.json", "python3 -c 'import json' ~/Library/Logs/claude-weekly/plans/s/plan.json",
        "tee ~/Library/Logs/claude-weekly/plans/branch-modes.json < /tmp/y", "find ~/Library/Logs/claude-weekly/run-seed-runs -name x -delete",
        "printf x > " + m.os.environ["PLANS_DIR"] + "/s/plan.json",
        "echo '{\"by\": \"yolo\", \"eff_mode\": \"yolo\"}' > .git/claude/autofinish.json",
        "cp /tmp/a.json /r/.git/worktrees/w/claude/autofinish.json",
        "echo '{\"by\": \"sam\"}' > .git/worktrees/w/claude/autofinish", "touch /r/.git/claude/autofinish",
        "cp /tmp/b.json /r/.git/claude/autofinish-briefs/claude%2Fx%2F2026-10-24-y.json", "mkdir -p .git/claude/autofinish-briefs"]
allow = ["cat ~/Library/Logs/claude-weekly/plans/s1/plan.json", "jq .mode ~/Library/Logs/claude-weekly/run-seed-runs/a.json",
         "cat .git/worktrees/w/claude/autofinish.json", "jq .hold /r/.git/claude/autofinish.json",
         "ls ~/Library/Logs/claude-weekly/run-seed-runs", "bin/plan report --task x --status running", "ls ~/Library/Logs/claude-weekly/plans-old",
         "cat .git/claude/autofinish-briefs/b.json", "cat .git/worktrees/w/claude/autofinish",
         "cp /tmp/c.json .git/worktrees/w/claude/autofinish-chain.json"]
print([c for c in deny if "skipper's record" not in (m.unattended_live(c, "/tmp") or "")], [c for c in allow if m.unattended_live(c, "/tmp")])
PYREC
)
ok "unattended: a hand edit of plan.json, branch-modes.json, a run record, /autofinish's marker or the yes at the brief by Bash is denied; a read is not (follow-ups item 7; autofinish-exclude landing review, finding 11)" \
  '[ "$rec" = "[] []" ]'
fm=$(cd "$MOD/hooks" && env -u CLAUDE_UNATTENDED HOME="$T/rh" python3 - <<'PYFORCE'
import importlib.util as u
s = u.spec_from_file_location("cp_force", "checkpoint.py"); m = u.module_from_spec(s); s.loader.exec_module(m)
home = m.os.environ["HOME"]
deny = ["touch ~/Library/Caches/run-seed/force/s1", "echo x > $HOME/Library/Caches/run-seed/force/s1",
        "mkdir -p ${HOME}/Library/Caches/run-seed/force", "cp /tmp/m " + home + "/Library/Caches/run-seed/force/s1",
        "python3 -c 'open(1)' ~/Library/Caches/run-seed/force/s1", "tee ~/Library/Caches/run-seed/force/s1 < /dev/null",
        "python3 modules/wharf-runs/hooks/force_mark.py < /tmp/p", "cp /tmp/p " + home + "/Library/Caches/run-seed/queue/outbox/p.json",
        "cp /tmp/e " + home + "/Library/Caches/run-seed/queue-local/vault/x.json"]
allow = ["ls ~/Library/Caches/run-seed/force", "cat ~/Library/Caches/run-seed/force/s1", "ls ~/Library/Caches/run-seed/forceful",
         "git commit -qm 'the force mark: ~/Library/Caches/run-seed/force'", "git add modules/wharf-runs/hooks/force_mark.py",
         "grep -n PHRASE modules/wharf-runs/hooks/force_mark.py"]
print([c for c in deny if not m.record_write(c, m.force_re())], [c for c in allow if m.record_write(c, m.force_re())],
      [c for c in deny if "the force mark" not in str((m.handle_bash(c, m.Path("/tmp"), None) or {}).get("hookSpecificOutput", {}).get("permissionDecisionReason"))])
PYFORCE
)
ok "every session, attended too: a hand write of the force mark or the queue's folders, or a hand run of force_mark.py, by Bash is denied; a read is not (dispatch-queue S4)" \
  '[ "$fm" = "[] [] []" ]'
fm2=$(cd "$MOD/hooks" && env -u CLAUDE_UNATTENDED HOME="$T/rh" python3 - <<'PYFORCE2'
import importlib.util as u
s = u.spec_from_file_location("cp_force2", "checkpoint.py"); m = u.module_from_spec(s); s.loader.exec_module(m)
F = "~/projects/regatta/modules/wharf-runs/hooks/force_mark.py"
RS = "~" + "/Library/Caches/run-seed"   # spelled in two halves: the publish gate reads a typed home path
deny = ["ssh peer 'python3 " + F + " < /tmp/p'", "ssh -p 22 peer python3 " + F, "ssh peer bash -c 'python3 " + F + "'",
        "ssh peer 'touch " + RS + "/force/s1'", "ssh peer 'echo x > " + RS + "/force/s1'",
        "ssh -E " + RS + "/force/s1 peer true", "ssh peer \"python3 -c 'open(1)' " + RS + "/queue/x\"",
        "gh issue create --body-file " + RS + "/force/s1", "gh run download -D " + RS + "/queue",
        "bash -c 'ssh peer python3 " + F + "'", "gh alias set fm '!python3 " + F + "'",
        "gh release download v1 -R o/r -O " + F, "gh pr diff 3 -R o/r --patch --output " + F,
        "gh pr diff 3 -R o/r --patch --output=" + F, "gh issue create -R o/r --title t --body \"$(python3 " + F + " < /tmp/p)\"",
        "gh pr comment 3 --body \"`python3 " + F + "`\"",
        "gh pr comment 3 --body-file <(python3 " + F + " < /tmp/p)", "gh pr comment 3 --body-file=<(python3 " + F + " < /tmp/p)",
        "gh pr comment 3 --body x >(python3 " + F + ")", "ssh peer cat <(python3 " + F + ")",
        "ssh peer \"cat `python3 " + F + "`\"", "ssh peer 'cat `python3 " + F + " < /tmp/p`'",
        "ssh peer 'cat <(python3 " + F + " < /tmp/p)'"]
allow = ["ssh peer 'cat " + F + "'", "ssh -o BatchMode=yes peer grep -n PHRASE " + F, "ssh peer 'ls " + RS + "/force'",
         "gh issue create -R o/r --title 'checkpoint denies a read of force_mark.py over ssh' --body 'see " + F + "'",
         "gh issue close 2 -R o/r -c 'fixed: force_mark.py'"]
print([c for c in deny if not m.record_write(c, m.force_re())], [c for c in allow if m.record_write(c, m.force_re())])
PYFORCE2
)
ok "  …an ssh HOST '<cmd>' is judged as its own command line, a gh text naming force_mark.py is prose, every main denial kept (regatta-logbook#2, queue S10)" \
  '[ "$fm2" = "[] []" ]'
mkdir -p "$T/rh/Library/Caches/run-seed/force"
FJ=$(jq -nc --arg p "$T/rh/Library/Caches/run-seed/force/s1" '{file_path:$p,content:"x"}')
ok "  …and by the Write tool, attended or not" \
  '[ "$(HOME="$T/rh" tool A Write "$FJ" "$UW")" = deny ] && [ "$(HOME="$T/rh" CLAUDE_UNATTENDED=dispatch tool A Write "$FJ" "$UW")" = deny ]'
mkdir -p "$T/rh/Library/Logs/claude-weekly/plans/s1"
RJ=$(jq -nc --arg p "$T/rh/Library/Logs/claude-weekly/plans/s1/plan.json" '{file_path:$p,content:"{}"}')
ok "  …and by the Write tool, unattended only" \
  '[ "$(HOME="$T/rh" CLAUDE_UNATTENDED=dispatch tool A Write "$RJ" "$UW")" = deny ] && [ "$(HOME="$T/rh" tool A Write "$RJ" "$UW")" = allow ]'
BJ=$(jq -nc --arg p "$T/rh/r/.git/claude/autofinish-briefs/b.json" '{file_path:$p,content:"{}"}')
ok "  …the yes at the brief by the Write tool too" '[ "$(HOME="$T/rh" CLAUDE_UNATTENDED=dispatch tool A Write "$BJ" "$UW")" = deny ]'
ok "unattended outside any opted-in repo: a consent flag is denied too, and nothing else is" \
  '[ "$(CLAUDE_UNATTENDED=dispatch tool A Bash "{\"command\":\"x --live-ok\"}" "$P")" = deny ] \
   && [ "$(CLAUDE_UNATTENDED=dispatch tool A Bash "{\"command\":\"python3 scripts/deploy.py x\"}" "$P")" = allow ]'
# First review (2026-10-04): the raw text denied a mention as if it were a run.
ok "unattended: naming a live script in git, grep or a commit message is allowed" \
  '[ "$(ut "git add scripts/deploy.py && git diff -- scripts/deploy.py")" = allow ] \
   && [ "$(ut "grep -rn -- --live-ok scripts/")" = allow ] \
   && [ "$(ut "git commit -m \\\"scripts/ha.py call: document --live-ok\\\"")" = allow ]'
ok "unattended: from a folder outside the repo, its live script by absolute path is denied" \
  '[ "$(CLAUDE_UNATTENDED=dispatch tool A Bash "{\"command\":\"python3 $UW/scripts/deploy.py x.yaml\"}" "$P")" = deny ]'
ok "  and so is cd into the repo first" \
  '[ "$(CLAUDE_UNATTENDED=dispatch tool A Bash "{\"command\":\"cd $U && python3 scripts/ha.py call x\"}" "$P")" = deny ]'
# Second review (2026-10-04): any route to the script that does not spell it from the repo root.
mkdir -p "$UW/scripts" && touch "$UW/scripts/deploy.py" "$UW/scripts/ha.py"
ok "unattended: a relative path from a sibling folder is denied" \
  '[ "$(CLAUDE_UNATTENDED=dispatch tool A Bash "{\"command\":\"python3 ../unatt/.claude/worktrees/u/scripts/deploy.py x\"}" "$P")" = deny ]'
ok "  and cd/pushd into scripts/ first, and a doubled slash" \
  '[ "$(ut "cd scripts && python3 deploy.py x")" = deny ] && [ "$(ut "pushd scripts && python3 ha.py call x")" = deny ] \
   && [ "$(ut "python3 scripts//deploy.py x")" = deny ]'
ok "  a find that runs something is no reader; one that lists is" \
  '[ "$(ut "find . -name x -exec y --live-ok ;")" = deny ] && [ "$(ut "find scripts -name deploy.py")" = allow ]'
ok "  python3 -m py_compile on a live script only reads" '[ "$(ut "python3 -m py_compile scripts/deploy.py")" = allow ]'
rm -r "$UW/scripts"
printf '{"checkpoint": true, "main": "main"}' > "$UW/.claude/workflow.json"
ok "the run cannot switch its guard off: the regexes come from the primary checkout" \
  '[ "$(ut "python3 scripts/deploy.py x.yaml")" = deny ] && [ "$(ut "python3 scripts/ha.py call x")" = deny ]'
git -C "$UW" checkout -q -- .claude/workflow.json
cp "$U/.claude/workflow.json" "$T/unatt.json"
printf '{"checkpoint": true, "main": "main", "unattended_deny_regex": "scripts/(ha"}' > "$U/.claude/workflow.json"
ok "an unattended_deny_regex that does not compile denies, and says why" \
  '[ "$(ut "python3 scripts/other.py")" = deny ] \
   && CLAUDE_UNATTENDED=dispatch toolreason A Bash "{\"command\":\"python3 scripts/other.py\"}" "$UW" | grep -q "does not compile"'
ok "  attended, nothing changes" '[ "$(tool A Bash "{\"command\":\"python3 scripts/other.py\"}" "$UW")" = allow ]'
cp "$T/unatt.json" "$U/.claude/workflow.json"

echo "autofinish: the idle clock, the two triggers, and the panel told what holds its branch (design E3, E6)"
WF="$R/.claude/worktrees/af"
git -C "$R" worktree add -q "$WF" -b claude/laptop/2026-10-05-af main
SF="$(git -C "$WF" rev-parse --absolute-git-dir)/claude"
AFS="$T/af-stub"; AFC="$T/af-calls"; AFSTATE="$T/af-state"; mkdir -p "$AFSTATE"
# The stub launcher: records each call; a --dry-run answers with $AFSTUB_VERDICT, as
# `<repo> <branch> <verdict>`. The hook runs it directly, so it needs only its #!.
printf '#!/bin/sh\necho "$*" >> "%s"\ncase " $* " in *" --dry-run "*) echo "repo claude/x ${AFSTUB_VERDICT:-start (C)}";; esac\n' "$AFC" > "$AFS"
chmod +x "$AFS"
# af <cmd…>: one hook call with the launcher switched on, pointed at the stub, and disarmed
af() { CLAUDE_HOOK_NO_AUTOFINISH= CLAUDE_AUTOFINISH_BIN="$AFS" AUTOFINISH_STATE_DIR="$AFSTATE" "$@"; }
# stopx <session> <reply> [stop_hook_active]: a Stop in $WF with the reply as last_assistant_message
stopx() { jq -nc --arg s "$T/pad$1" --arg id "sess$1-0000" --arg c "$WF" --arg m "$2" --argjson a "${3:-false}" --arg n "$RANDOM$RANDOM" \
  '{hook_event_name:"Stop",scratchpad_dir:$s,session_id:$id,cwd:$c,last_assistant_message:$m,stop_hook_active:$a,nonce:$n}' | python3 "$HOOK"; }
calls() { sleep 0.3; i=0; while [ ! -s "$AFC" ] && [ $i -lt 30 ]; do sleep 0.1; i=$((i+1)); done; cat "$AFC" 2>/dev/null; }
DECL=$(core 'print(common.DECLARED_LINES[1])')   # "<OWNER>, THIS SESSION IS DONE — IT LANDS BY ITSELF.", the old line
NDECL=$(core 'print(common.DECLARED_LINES[0])')   # "… IT LAUNCHES BY ITSELF.", DECLARED_LINE since rename S4
# a map run (bench/rename-map.sh) keeps this line, which holds both words, and rewrites DECL's: then it fails
ok "rename guard: DECL keeps its land word, NDECL the launch one — the old line stays tested" '[ "$DECL" != "$NDECL" ]'

ev A Stop "" "$WF" "Committed and pushed: the change is in." >/dev/null
ok "Stop writes claude/last-reply with the reply — the launcher's idle clock" \
  'grep -qx "Committed and pushed: the change is in." "$SF/last-reply"'
long=$(python3 -c 'print("x" * 5000 + "\nthe end")'); ev A Stop "" "$WF" "$long" >/dev/null
ok "  only the reply's tail, 4,000 characters" \
  '[ "$(wc -c < "$SF/last-reply" | tr -d " ")" = 4000 ] && tail -1 "$SF/last-reply" | grep -qx "the end"'
long=$(python3 -c 'print("```\n" + "code\n" * 1000 + "```\n\nthe end")'); ev A Stop "" "$WF" "$long" >/dev/null
ok "  never cut inside a code block: its closing fence would read as an opener and hide the end" \
  '! grep -qF "code" "$SF/last-reply" && ! grep -qF "\`\`\`" "$SF/last-reply" && tail -1 "$SF/last-reply" | grep -qx "the end"'
python3 -c 'import json,time,sys; json.dump({"session":"sessB-0000","branch":"claude/laptop/2026-10-05-af","seen":time.time()},open(sys.argv[1],"w"))' "$SF/owner.json"
ev A Stop "" "$WF" "a reader's reply" >/dev/null
ok "  never by a session another one locks out" '! grep -q "a reader" "$SF/last-reply"'
rm -f "$SF/owner.json"

rm -f "$AFC"; af ev A SessionEnd "" "$WF" >/dev/null
ok "SessionEnd hands the worktree to the launcher, a minute on, detached" \
  '[ "$(calls)" = "--worktree $WF --after 60 --log" ]'
rm -f "$AFC"; ev A SessionEnd "" "$WF" >/dev/null; sleep 0.5
ok "  not with the launcher switched off (the suites)" '[ ! -e "$AFC" ]'
rm -f "$AFC"; af ev A SessionEnd "" "$R" >/dev/null; sleep 0.5
ok "  nor on main" '[ ! -e "$AFC" ]'

rm -f "$AFC"; out=$(AFSTUB_VERDICT="wait: idle 0 min" af stopx A "Built it.

$DECL")
ok "the declared line with a dry run that says wait: the reply is blocked once, with the verdict" \
  '[ "$(echo "$out" | jq -r .decision)" = block ] && echo "$out" | jq -r .reason | grep -qF "says \`wait: idle 0 min\`"'
ok "  the check is this session's own: --session, and the reply from last-reply" \
  'head -1 "$AFC" | grep -qF -- "--worktree $WF --dry-run --session sessA-0000 --reply $SF/last-reply"'
ok "  and nothing is handed on" '[ "$(wc -l < "$AFC" | tr -d " ")" = 1 ]'
rm -f "$AFC"; out=$(AFSTUB_VERDICT="wait: idle 0 min" af stopx A "Built it.

$NDECL")
ok "  the new declared line (rename S2) is checked the same, and the block quotes the line the reply said" \
  '[ "$(echo "$out" | jq -r .decision)" = block ] && echo "$out" | jq -r .reason | grep -qF "ends with \`$NDECL\`, but"'
rm -f "$AFC"; out=$(AFSTUB_VERDICT="wait: idle 0 min" af stopx A "Built it.

$DECL" true)
ok "  blocked once only: stop_hook_active lets it through to the launcher" \
  '[ "$(echo "$out" | jq -r ".decision // empty")" = "" ] && calls | grep -qF -- "--worktree $WF --session sessA-0000 --reply $SF/last-reply --log"'
rm -f "$AFC"; out=$(af stopx A "Built it.

$DECL")
ok "the declared line with a dry run that says start: no block, the launcher judges it detached" \
  '[ "$(echo "$out" | jq -r ".decision // empty")" = "" ] && [ "$(calls | grep -c -- "--log")" = 1 ]'
ok "  and the note says it is disarmed" 'echo "$out" | jq -r .systemMessage | grep -qF "autofinish judges this branch now — disarmed: logged only"'
rm -f "$AFC"; out=$(af stopx A "Built it.

$NDECL")
ok "  the new declared line too (rename S2)" \
  '[ "$(echo "$out" | jq -r ".decision // empty")" = "" ] && [ "$(calls | grep -c -- "--log")" = 1 ]'
echo x >> "$WF/dep.txt"; printf 'Deploy: the thing\n\nwhy\n\nDeployed: home\n' > "$T/padA/commit-summary.md"
rm -f "$AFC"; out=$(af stopx A "Deployed it.")
ok "a turn whose own commit says Deployed: hands the branch to the launcher at once (rule L)" \
  'calls | grep -qF -- "--worktree $WF --session sessA-0000 --reply $SF/last-reply --log"'
echo y >> "$WF/dep.txt"; printf 'Docs: the thing\n\nwhy\n\nDeployed: no\n' > "$T/padA/commit-summary.md"
rm -f "$AFC"; out=$(af stopx A "Done, nothing went live.")
ok "  not when it says Deployed: no" '[ -z "$(calls)" ]'
echo '{"by": "sam", "ts": "2026-10-05T10:00:00+02:00"}' > "$AFSTATE/armed"
rm -f "$AFC"; out=$(af stopx A "Built it.

$DECL")
ok "  armed: it says it starts on start" 'echo "$out" | jq -r .systemMessage | grep -qF "armed: it starts /finish when the verdict is start"'
rm "$AFSTATE/armed"
rm -f "$AFC"; af stopx A "Built it, nothing asked." >/dev/null; sleep 0.5
ok "an ordinary reply with no override: the launcher is not called" '[ ! -e "$AFC" ]'
BY=$(core 'print(common.OVERRIDE_BY)')   # the owner's /autofinish marks its override so (the config's owner)
echo '{"by": "'"$BY"'", "ts": 1, "now": true}' > "$SF/autofinish"
rm -f "$AFC"; out=$(af stopx A "Built it, nothing asked.")
ok "/autofinish now: the turn's end hands it to the launcher, no line needed and no check" \
  '[ "$(calls)" = "--worktree $WF --session sessA-0000 --reply $SF/last-reply --log" ]'
echo '{"by": "'"$BY"'", "ts": 1, "now": false}' > "$SF/autofinish"
rm -f "$AFC"; af stopx A "Built it, nothing asked." >/dev/null; sleep 0.5
ok "  plain /autofinish: the sweep's 40 minutes, not the turn's end" '[ ! -e "$AFC" ]'
rm -f "$SF/autofinish"

# R2: the runner holds the lock; the panel the owner left is told why and refused, never stolen from
python3 - "$SF" <<'EOF'
import json, sys, time, datetime
sf = sys.argv[1]
json.dump({"session": "sessR-0000", "branch": "claude/laptop/2026-10-05-af", "seen": time.time()}, open(sf + "/owner.json", "w"))
json.dump({"started": datetime.datetime.now().astimezone().isoformat(timespec="seconds"), "session": "sessR-0000",
           "tip": "abc", "by": "sweep", "rule": "A", "window": "finish · af · laptop", "ended": None,
           "outcome": None, "pr": None, "gate": None}, open(sf + "/autofinish.json", "w"))
EOF
HHMM=$(date +%H:%M)
RUNLINE="autofinish is running /finish on this branch since $HHMM (window \"finish · af · laptop\", session sessR-00, account unchanged, rule A); wait, or /autofinish off"
ok "R2: an Edit from the panel is refused, and the reason names the run" \
  'toolreason A Edit "{\"file_path\":\"$WF/x.md\"}" "$WF" | grep -qF "$RUNLINE"'
ok "  a git commit too" 'toolreason A Bash "{\"command\":\"git commit -qm x\"}" "$WF" | grep -qF "$RUNLINE"'
ok "  and the lock still names the runner" '[ "$(jq -r .session "$SF/owner.json")" = sessR-0000 ]'
out=$(ev A UserPromptSubmit "still there?" "$WF")
ok "the panel's next prompt is told once, not offered a worktree" \
  'echo "$out" | jq -r .systemMessage | grep -qF "🤖 $RUNLINE" && ! echo "$out" | jq -r .systemMessage | grep -q "read-only here"'
out=$(ev A UserPromptSubmit "and now?" "$WF")
ok "  once: the next prompt's note is quiet, its context still says it" \
  '! echo "$out" | jq -r ".systemMessage // empty" | grep -q "autofinish" && echo "$out" | jq -r .hookSpecificOutput.additionalContext | grep -qF "$RUNLINE"'
out=$(ev R UserPromptSubmit "runner's own" "$WF")
ok "  the runner's own session is never told about itself" '! echo "$out" | grep -q "autofinish is running"'
ev A UserPromptSubmit '<agent-message from="run-finish">autofinish picked up this branch</agent-message>' "$WF" >/dev/null
ok "  the run's message waking the panel is never queued as a prompt (autofinish-run notify)" \
  '! grep -q "autofinish picked up" "$SF/prompts.json" && grep -q "still there?" "$SF/prompts.json"'
python3 - "$SF" <<'EOF'
import json, sys, datetime
p = sys.argv[1] + "/autofinish.json"; r = json.load(open(p))
r.update(ended=datetime.datetime.now().astimezone().isoformat(), outcome="landed", pr=42)  # the outcome word written until S4; launched is said for it
json.dump(r, open(p, "w"))
EOF
rm -f "$SF/owner.json"
out=$(ev A UserPromptSubmit "what happened?" "$WF")
# Either word (rename S3, 2026-10-19): the phrase comes from regatta's core, whose S3 half lands apart
# from this repo's; each order must leave both checks green. Rename S8 (a week on) asserts the new word only.
ok "after the run: this branch launched as #N, once" \
  'echo "$out" | jq -r .systemMessage | grep -qE "🤖 this branch (landed|launched) as #42" && echo "$out" | jq -r .hookSpecificOutput.additionalContext | grep -qE "This branch (landed|launched) as #42\."'
out=$(ev A UserPromptSubmit "again" "$WF")
ok "  and not again" '! echo "$out" | grep -qE "(landed|launched) as"'
out=$(ev B UserPromptSubmit "another tab" "$WF")
ok "  another session hears it once too" 'echo "$out" | jq -r .systemMessage | grep -qE "this branch (landed|launched) as #42"'
python3 - "$SF" <<'EOF'
import json, sys
p = sys.argv[1] + "/autofinish.json"; r = json.load(open(p))
r.update(started="2026-10-05T11:00:00+02:00", outcome="stopped", gate="G4 open items", pr=None)
json.dump(r, open(p, "w"))
EOF
out=$(ev A UserPromptSubmit "and this one?" "$WF")
ok "a stopped run: autofinish stopped here at <gate>" 'echo "$out" | jq -r .systemMessage | grep -qF "🤖 autofinish stopped here at G4 open items"'
python3 - "$SF" <<'EOF'
import json, sys
p = sys.argv[1] + "/autofinish.json"; r = json.load(open(p))
r.update(started="2026-10-05T12:00:00+02:00", ended=None, outcome=None, gate=None)
json.dump(r, open(p, "w"))
EOF
out=$(ev B UserPromptSubmit "a runner that died" "$WF")
ok "  a record never ended whose lock is gone (a runner that died) says nothing" '! echo "$out" | grep -q "autofinish"'
rm -f "$SF/autofinish.json" "$SF/autofinish.said"
git -C "$R" worktree remove --force "$WF"

echo "no regatta core: the hook fails closed (regatta-modules C4, B1 launch review, 2026-10-17)"
# An empty config dir and no REGATTA_HOME: `import common` raises. Dying there was exit 1, which
# Claude Code reads as no objection — the main-write and bare-push denies were gone. Run from the
# solo tree (wharf without the core beside it, no registry): the checkout itself always has one.
NC="$T/nocore"; mkdir -p "$NC"
SOLO="$T/tree-solo/modules/wharf/hooks/checkpoint.py"
LINE="regatta core not found — clone the regatta repo, then write the config dir (the core's install.sh, or the overlay's bootstrap.sh --config)"
nct() { jq -nc --arg t "$1" --argjson i "$2" --arg c "${3:-$R}" \
  '{hook_event_name:"PreToolUse",tool_name:$t,tool_input:$i,session_id:"sessA-0000",cwd:$c}' \
  | env -u REGATTA_HOME REGATTA_CONFIG="$NC" python3 "$SOLO" 2>"$T/nc.err"; echo "rc=$?"; }
dec() { echo "$1" | head -1 | jq -r '.hookSpecificOutput.permissionDecision // "allow"' 2>/dev/null; }
out=$(nct Write "{\"file_path\":\"$R/x.txt\",\"content\":\"x\"}")
ok "a Write on main: denied" '[ "$(dec "$out")" = deny ]'
ok "  the reason names the fix" 'echo "$out" | head -1 | jq -r .hookSpecificOutput.permissionDecisionReason | grep -qF "$LINE"'
ok "  exit 0, the one line on stderr" '[ "$(echo "$out" | tail -1)" = rc=0 ] && [ "$(grep -cF "checkpoint: $LINE (" "$T/nc.err")" = 1 ]'
out=$(nct Bash '{"command":"git push"}' "$P")
ok "a bare push, from a plain folder: denied" '[ "$(dec "$out")" = deny ]'
out=$(nct Bash '{"command":"git push -u origin claude/laptop/2026-10-18-x"}' "$R")
ok "  even the allowed shape: no core, no check of the /move marker" '[ "$(dec "$out")" = deny ]'
out=$(nct Bash '{"command":"cd /x && git commit -qm x"}' "$P")
ok "a git verb that writes: denied" '[ "$(dec "$out")" = deny ]'
out=$(nct Edit "{\"file_path\":\"$P/y.txt\"}" "$P")
ok "an Edit outside any git work tree: passes, said once" '[ "$out" = rc=0 ] && [ "$(grep -cF "$LINE" "$T/nc.err")" = 1 ]'
out=$(nct Bash '{"command":"bash ~/projects/layer/bootstrap.sh --config"}' "$R")
ok "  the fix itself, and a read: pass" '[ "$out" = rc=0 ] && [ "$(nct Bash "{\"command\":\"git status\"}" "$R")" = rc=0 ]'
# B1 finish review: the floor is fallback_bash()'s, bar LIVEISH_RE, and a stale core can be pulled
out=$(nct Bash '{"command":"git branch -D claude/laptop/2026-10-18-x"}' "$P")
ok "a claude/* branch deletion, from a plain folder: denied (D1)" '[ "$(dec "$out")" = deny ]'
out=$(nct Bash '{"command":"git worktree remove --force .claude/worktrees/x"}' "$P")
ok "  a worktree removal: denied" '[ "$(dec "$out")" = deny ]'
out=$(nct Bash '{"command":"git -C ~/projects/regatta pull --ff-only"}' "$P")
ok "a pull --ff-only (the stale core's repair): passes" '[ "$out" = rc=0 ]'
out=$(nct Bash '{"command":"git pull"}' "$P")
ok "  a plain pull: denied" '[ "$(dec "$out")" = deny ]'
out=$(nct Bash '{"command":"python3 -c \"open(1)\""}' "$P")
ok "inline program code: denied" '[ "$(dec "$out")" = deny ]'
out=$(jq -nc --arg c "$P" '{hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:"scripts/deploy.sh --live-ok"},session_id:"sessA-0000",cwd:$c}' \
  | env -u REGATTA_HOME REGATTA_CONFIG="$NC" CLAUDE_UNATTENDED=dispatch python3 "$SOLO" 2>/dev/null)
ok "  an unattended consent flag: denied" '[ "$(dec "$out")" = deny ]'
ln -s "$R" "$T/nc-link"
out=$(nct Write "{\"file_path\":\"$T/nc-link/x.txt\",\"content\":\"x\"}" "$P")
ok "a Write through a link into a work tree (~/.claude/rules): denied" '[ "$(dec "$out")" = deny ]'
for k in "syntax:def (" "attribute-less:X = 1"; do
  mkdir -p "$T/core-${k%%:*}/modules/regatta/hooks"; cp -R "$MOD" "$T/core-${k%%:*}/modules/wharf"   # the broken core beside wharf
  printf '%s\n' "${k#*:}" > "$T/core-${k%%:*}/modules/regatta/hooks/common.py"
  out=$(jq -nc --arg c "$R" '{hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:"git commit -qm x"},session_id:"sessA-0000",cwd:$c}' \
    | REGATTA_HOME="$T/core-${k%%:*}" REGATTA_CONFIG="$NC" python3 "$T/core-${k%%:*}/modules/wharf/hooks/checkpoint.py" 2>/dev/null; echo "rc=$?")
  ok "a ${k%%:*} core, not a missing one: a commit denied, exit 0" '[ "$(dec "$out")" = deny ] && [ "$(echo "$out" | tail -1)" = rc=0 ]'
done
out=$(jq -nc --arg c "$R" '{hook_event_name:"Stop",session_id:"sessA-0000",cwd:$c}' \
  | env -u REGATTA_HOME REGATTA_CONFIG="$NC" python3 "$SOLO" 2>"$T/nc.err"; echo "rc=$?")
ok "Stop: no output, exit 0, the one line" '[ "$out" = rc=0 ] && [ "$(grep -cF "checkpoint: $LINE (" "$T/nc.err")" = 1 ]'
ok "imported (sync.py): the ImportError reaches the importer" \
  '[ "$(env -u REGATTA_HOME REGATTA_CONFIG="$NC" python3 -c "import sys; sys.path.insert(0, \"$(dirname "$SOLO")\"); import checkpoint" 2>&1 | tail -1 | grep -cE "^(ImportError|ModuleNotFoundError):")" = 1 ]'
mkdir -p "$T/reg/plugins"
printf '{"plugins": {"regatta@regatta": [{"scope": "user", "installPath": "%s"}]}}\n' "$T/tree-core/modules/regatta" > "$T/reg/plugins/installed_plugins.json"
out=$(jq -nc --arg c "$R" --arg f "$R/x.txt" '{hook_event_name:"PreToolUse",tool_name:"Write",tool_input:{file_path:$f},session_id:"sessA-0000",cwd:$c}' \
  | env -u REGATTA_HOME REGATTA_CONFIG="$NC" CLAUDE_CONFIG_DIR="$T/reg" python3 "$SOLO" 2>/dev/null | jq -r .hookSpecificOutput.permissionDecisionReason)
ok "the core as an installed plugin (C2's registry): found, so a write on main is the module's deny, not the fallback's" \
  'echo "$out" | grep -q worktree && ! echo "$out" | grep -qF "$LINE"'

echo "autofinish absent or found (G1): the lander child starts only when common.tool finds one"
AF1="$R/.claude/worktrees/g1"; git -C "$R" worktree add -q "$AF1" -b claude/laptop/2026-10-19-g1 main
mkdir -p "$T/g1-legacy/bin" "$T/g1-cfg/regatta"; [ -f "$REGATTA_CONFIG/regatta/owner" ] && cp "$REGATTA_CONFIG/regatta/owner" "$T/g1-cfg/regatta/owner"
printf '#!/bin/sh\necho "$*" >> "%s"\n' "$T/g1-calls" > "$T/g1-legacy/bin/autofinish"; chmod +x "$T/g1-legacy/bin/autofinish"
g1() { jq -nc --arg c "$AF1" --arg s "$T/padA" '{hook_event_name:"SessionEnd",session_id:"sessA-0000",cwd:$c,scratchpad_dir:$s}' \
  | env -u CLAUDE_HOOK_NO_AUTOFINISH -u CLAUDE_AUTOFINISH_BIN AUTOFINISH_STATE_DIR="$T/g1-state" REGATTA_CONFIG="$T/g1-cfg" "$@" \
    python3 "$T/tree-core/modules/wharf/hooks/checkpoint.py" 2>"$T/g1.err"; echo "rc=$?"; }
mkdir -p "$T/g1-state"; echo "x" > "$AF1/g1.txt"
ok "  absent (no module has it; an overlay's copy is no fallback since B14b): the turn ends, exit 0, nothing on stderr" \
  '[ "$(g1)" = rc=0 ] && [ ! -s "$T/g1.err" ] && sleep 0.5 && [ ! -e "$T/g1-calls" ]'
ok "  found (CLAUDE_AUTOFINISH_BIN, the stand-in for common.tool's answer): the child starts" \
  '[ "$(g1 CLAUDE_AUTOFINISH_BIN="$T/g1-legacy/bin/autofinish")" = rc=0 ] && i=0 && while [ ! -s "$T/g1-calls" ] && [ $i -lt 30 ]; do sleep 0.1; i=$((i+1)); done && grep -q -- "--worktree $AF1" "$T/g1-calls"'

echo; [ $fails -eq 0 ] && echo "all passed" || { echo "$fails FAILED"; exit 1; }
