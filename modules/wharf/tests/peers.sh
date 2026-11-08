#!/usr/bin/env bash
# The optional peers' absent cases not in the other suites (the design's G2, G3, G5, G6, G8, G32): wharf beside
# the core and nothing else, a config naming no legacy checkout. Each lookup is None, and each
# caller takes the fallback its comment names — never a stack trace. Scratch paths only.
#   bash modules/wharf/tests/peers.sh
set -u
unset CLAUDE_CODE_SESSION_ID CLAUDE_UNATTENDED REGATTA_UNATTENDED CLAUDE_CODE_DISABLE_BACKGROUND_TASKS
for v in $(env | sed -n 's/^\(DISPATCH_[A-Za-z0-9_]*\)=.*/\1/p'); do unset "$v"; done
M="$(cd "$(dirname "$0")/.." && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fails=0
check() { if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3: expected [$2] got [$1]"; fails=$((fails+1)); fi; }
mkdir -p "$T/tree/.claude-plugin" "$T/tree/modules" "$T/cfg" "$T/claude"; : > "$T/tree/.claude-plugin/marketplace.json"
cp -R "$M/../regatta" "$T/tree/modules/regatta"; cp -R "$M" "$T/tree/modules/wharf"
py() { env -u REGATTA_HOME -u REGATTA_LEGACY -u CLAUDE_HOOK_NO_AUTOFINISH -u CLAUDE_AUTOFINISH_BIN REGATTA_CONFIG="$T/cfg" CLAUDE_CONFIG_DIR="$T/claude" HOME="$T/home" \
  python3 -c "import sys; sys.path.insert(0, sys.argv[1]); $1" "$T/tree/modules/wharf/hooks" 2>&1; }

echo "peers absent: wharf and the core alone"
check "$(py 'import checkpoint, common; print([common.tool(n) for n in ("keel", "autofinish", "pickup", "usage-report", "tier_check.py", "claude-settings", "sheep")])')" \
      "[None, None, None, None, None, None, None]" "no peer is found"
check "$(py 'import branches; print(branches.MEMO_TOOL, branches.memo_tool())')" "None None" "G5: branches reads no D-lists without keel"
check "$(py 'import branches; b = type("B", (), {"name": "claude/laptop/2026-10-19-x"})(); print(branches.review_line(b))')" \
      "pickup review claude/laptop/2026-10-19-x (with wharf-runs installed)" "G3: the review line names pickup and the module it comes with"
check "$(py 'import sync; print(sync.user_settings_notes())')" "([], [])" "G8: no claude-settings, no settings note"
check "$(py 'import os; os.environ.pop("CLAUDE_HOOK_NO_SHEEP", None); import sync; print(sync.sheep_notes())')" "[]" "  no sheep, no sessionpipe note"
check "$(py 'import checkpoint; print(checkpoint.MEMO, checkpoint.spawn_autofinish("--worktree", "/x"))')" "None False" "G1, G4: checkpoint finds neither keel nor the lander, and starts nothing"
check "$(py 'import checkpoint, common, pathlib; r = checkpoint.autofinish_at_stop(pathlib.Path("/x"), {"last_assistant_message": "Done.\n\n" + common.DECLARED_LINE}, "s", pathlib.Path("/x"), True); print(r[1], "no autofinish is installed" in (r[0] or ""))')" \
      "None True" "G1: the declared line with no lander is blocked, not noted — nothing would launch the branch"
mkdir -p "$T/claude/plugins"; echo '{"plugins": [{"installPath": 1}]}' > "$T/claude/plugins/installed_plugins.json"
check "$(py 'import checkpoint; print(checkpoint.common._installed_roots(), checkpoint.common.tool("keel"))')" "[] None" "  a registry of the wrong shape is none, never a raise at the deny hook's import"
echo '{"plugins": {"keel@regatta": [{"scope": "user", "installPath": 1}, {"projectPath": 2, "installPath": "/x"}]}}' > "$T/claude/plugins/installed_plugins.json"
check "$(py 'import checkpoint; print(checkpoint.common._installed_roots())')" "[]" "  …nor rows of the wrong shape"
rm "$T/claude/plugins/installed_plugins.json"

# B6's tools, loaded as their callers load them (a file in bin/, no .py), against a scratch registry
load() { printf 'import importlib.machinery, importlib.util\nl = importlib.machinery.SourceFileLoader("%s", "%s/tree/modules/wharf/bin/%s")\n%s = importlib.util.module_from_spec(importlib.util.spec_from_loader("%s", l)); l.exec_module(%s)\n' "$1" "$T" "$1" "$2" "$1" "$2"; }
mkdir -p "$T/reg/overlay" "$T/home/projects/secret/x"
printf '{"machine_account": "m", "guarded": ["secret"], "repos": {"overlay": {"github": "o/overlay"}}}\n' > "$T/reg/overlay/repos.json"
printf '{"repos": {}}\n' > "$T/reg/bare.json"
rpy() { CLAUDE_REPOS_JSON="$1" py "$2"; }
check "$(rpy "$T/reg/overlay/repos.json" "$(load repos r)
r.trust_and_host()")" "  trust: skipped — trust-projects not installed (lighthouse); each new repo asks once
  rc: skipped — rc-hosts not installed (wharf-runs); no Remote Control hosts loaded" "G2, G8: repos --clone skips trust and the rc hosts, each named"
check "$(rpy "$T/reg/overlay/repos.json" "$(load github-repo g)
g.register(\"k\", \"o/k\", \"k\")" | sed "s|$T|T|")" "github-repo: ⚠ knowledge-commit not installed (atlas) — add k to T/reg/overlay/repos.json by hand" \
      "G6: github-repo without knowledge-commit says to add the line by hand"
check "$(rpy "$T/reg/overlay/repos.json" "sys.path.insert(0, \"$T/tree/modules/wharf/bin\"); import session_status as s; print(s.GUARDED, s.guarded_path(\"$T/home/projects/secret/x\"), s.guarded_path(\"$T/home/projects/overlay\"))" 2>&1 | tail -1)" \
      "('secret',) True False" "G32: session_status's guard is the registry's list, with no helmlib (or planlib)"
check "$(rpy "$T/reg/bare.json" "sys.path.insert(0, \"$T/tree/modules/wharf/bin\"); import session_status as s; print(s.GUARDED)" 2>&1 | tail -1)" "()" \
      "  a registry without the list, and no helmlib (or planlib): nothing named guarded (a stranger's default)"

echo "closing classes: the core table and wharf agree (stuck-ships S7)"
for owner in "" Sam; do
  mkdir -p "$T/cfg/regatta"; printf '%s\n' "$owner" > "$T/cfg/regatta/owner"
  check "$(py 'sys.path.insert(0, sys.argv[1] + "/../bin"); import session_status as s, common
cases = ((common.LANDER_PREFIX + "fix round 1 of 3", "lander", s.LANDER, "⏳"),
         (common.PENDING_PREFIX + "the lander’s suite (test_lander.sh), then the two reviewers", "pending", s.PENDING, "⏳"),
         (common.HANDOVER_LINE, "handed", s.HANDED, "⏳"),
         (common.PENDING_PREFIX + "the reviewers", "pending", s.PENDING, "⏳"),
         (common.WAITING_PREFIX + "settle the check red on main", "waiting", s.WAITING, "🛑"),
         ("RELAYED TO skipper-1 — the open item", "relayed", s.RELAYED, "⏳"),
         (common.FINISH_LINES[0], "done", s.DONE, "✅"),
         (common.IDLE_PREFIX + "answered", "idle", s.DONE, "✅"))
for line, kind, status, mark in cases:
    text = common.marked(kind, line)
    print(common.ending(text)[0] == kind, common.ending_mark(text) == (mark, mark), s.closing(text) == status)
line = common.marked("lander", cases[0][0])
print(common.ending(line + "\n[doc](/tmp/course.md)")[0] == "lander",
      common.ending("```\n" + line + "\n```")[0] is None,
      common.ending(line + "\nMore prose.")[2][0] == "after",
      common.closing_kind(common.PENDING_PREFIX + "the reviewers, then " + cases[0][0]) == "pending")')" \
"True True True
True True True
True True True
True True True
True True True
True True True
True True True
True True True
True True True True" "classes, marks and ending boundaries, owner=[$owner]"
done

echo; [ $fails -eq 0 ] && echo "all passed" || { echo "$fails FAILED"; exit 1; }
