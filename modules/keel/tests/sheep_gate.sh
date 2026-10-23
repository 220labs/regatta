#!/usr/bin/env bash
# Tests for hooks/sheep_gate.py's confidential scopes (knowledge-layers S1): a session in a repo
# of a scope flagged `"confidential": true` in the registry sends nothing to sessionpipe, nor does
# an event that names such a path; an open scope's, and every repo when no registry is found,
# send as before. The rest of the gate's cases are layer's hooks/test_hooks.sh, "sheep".
# A scratch HOME and config dir, a stub hook that records it ran. No network.
#   bash modules/keel/tests/sheep_gate.sh
set -u
H="$(cd "$(dirname "$0")/../hooks" && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fails=0
check() { if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3: expected [$2] got [$1]"; fails=$((fails+1)); fi; }

unset CLAUDE_REPOS_JSON CLAUDE_PROJECT_DIR REGATTA_HOME ACCOUNTS_FILE
export HOME="$T/home" REGATTA_CONFIG="$T/config"
P="$HOME/projects"; mkdir -p "$REGATTA_CONFIG/regatta"; printf 'vault\n' > "$REGATTA_CONFIG/regatta/guarded"; mkdir -p "$REGATTA_CONFIG/wharf" "$P/know/.claude/worktrees/x" "$P/open"
printf '#!/bin/sh\ncat > /dev/null; echo ran > "%s"\n' "$T/ran" > "$T/hook"; chmod +x "$T/hook"
reg() {   # reg <confidential: true|false>
  printf '{"repos": {"know": {}, "open": {}},\n "scopes": {"sec": {"file": "s.code-workspace", "repos": ["know"], "confidential": %s},\n  "lab": {"file": "l.code-workspace", "repos": ["open"]}}}\n' "$1" > "$REGATTA_CONFIG/wharf/repos.json"
}
sg() {    # sg <event json> → sent | dropped
  rm -f "$T/ran"; printf '%s' "$1" | (cd "$P/open" && python3 "$H/sheep_gate.py" "$T/hook" claude-code Stop) >/dev/null 2>&1
  [ -f "$T/ran" ] && echo sent || echo dropped
}
slug() { printf '%s' "$1" | sed 's/[^A-Za-z0-9]/-/g'; }

reg true
check "$(sg "{\"cwd\":\"$P/know\"}")" dropped "a cwd in a confidential scope's repo: dropped"
check "$(sg "{\"cwd\":\"$P/know/.claude/worktrees/x\"}")" dropped "…its worktree too"
check "$(sg "{\"cwd\":\"$P/open\"}")" sent "an open scope's repo: sent"
# events with a comma inside braces are built by printf: macOS bash 3.2 brace-expands `{a,b}`
# inside "$(…)" (AGENTS.md, Traps)
e1=$(printf '{"cwd":"%s","tool_input":{"file_path":"%s"}}' "$P/open" "$P/know/notes.md")
e2=$(printf '{"cwd":"%s","tool_input":{"command":"cat ~/projects/know/a"}}' "$P/open")
e3=$(printf '{"cwd":"/nowhere","transcript_path":"%s"}' "$HOME/.claude/projects/$(slug "$P/know")/s.jsonl")
e4=$(printf '{"cwd":"/nowhere","transcript_path":"%s"}' "$HOME/.claude/projects/$(slug "$P/open")/s.jsonl")
check "$(sg "$e1")" dropped "an open session's event that names a confidential path: dropped"
check "$(sg "$e2")" dropped "…by its ~ form too"
check "$(sg "$e3")" dropped "a transcript filed under the confidential repo's slug: dropped"
check "$(sg "$e4")" sent "…an open repo's slug: sent"
check "$(cd "$P/open" && python3 -c "import sys; sys.path.insert(0, '$H'); import sheep_gate as g; print(bool(g.private_reason('$P/know')), bool(g.private_reason('$P/open')))")" \
  "True False" "private_reason (bin/sheep's forget-private and audit) agrees"
check "$(python3 -c "import sys; sys.path.insert(0, '$H'); import sheep_gate as g; print(g.private_part('know'), g.private_part('$P/open/x'))")" \
  "know None" "private_part (keel's never_mirrored, helm's guarded) names a confidential repo by its folder"
mkdir -p "$P/nest/deep"; printf '{"repos": {"nest/deep": {}, "open": {}}, "scopes": {"n": {"file": "n", "repos": ["nest/deep"], "confidential": true}}}\n' > "$T/nest.json"
check "$(CLAUDE_REPOS_JSON="$T/nest.json" sg "{\"cwd\":\"$P/nest\"}")" dropped "a folder that holds a nested confidential repo: dropped"
e5=$(printf '{"cwd":"%s","tool_input":{"file_path":"/x/orca/claude-profiles/p/home/projects/%s/memory/a.md"}}' "$P/open" "$(slug "$P/know")")
check "$(sg "$e5")" dropped "an event that names the confidential repo's slug under any login dir (an Orca profile's): dropped"
# the fence fails closed when a registry is there but cannot be read (the /finish review of S1)
cp "$REGATTA_CONFIG/wharf/repos.json" "$T/good.json"; head -c 60 "$T/good.json" > "$REGATTA_CONFIG/wharf/repos.json"
check "$(sg "{\"cwd\":\"$P/open\"}")" dropped "a torn registry: every event dropped, an open repo's too"
cp "$T/good.json" "$REGATTA_CONFIG/wharf/repos.json"; echo "$T/nowhere" > "$REGATTA_CONFIG/legacy"
check "$(sg "{\"cwd\":\"$P/open\"}")" dropped "a core that does not import beside a registry (config incomplete): every event dropped"
rm "$REGATTA_CONFIG/legacy"
check "$(sg "{\"cwd\":\"$P/open\"}")" sent "…the config whole again: an open repo's sent"
reg false
check "$(sg "{\"cwd\":\"$P/know\"}")" sent "the flag off: the same repo is sent"
check "$(sg "$e1") $(sg "$e3")" "sent sent" "…and the events that name it"
rm "$REGATTA_CONFIG/wharf/repos.json"
check "$(sg "{\"cwd\":\"$P/know\"}")" sent "no registry: as before the flag (PRIVATE_REPOS alone)"
check "$(sg "{\"cwd\":\"$P/vault\"}")" dropped "…and vault still dropped"

# sheep's GATE: REGATTA_HOME at a worktree resolves to its main checkout, never the worktree a
# /finish removes (B14a landing review, 2026-10-23)
R="$T/rg"; mkdir -p "$R/modules/keel/hooks"; : > "$R/modules/keel/hooks/sheep_gate.py"
git -C "$R" init -q && git -C "$R" add -A && git -C "$R" -c user.name=t -c user.email=t@t commit -qm x \
  && git -C "$R" worktree add -q "$T/rg-wt" 2>/dev/null
gate_at() { REGATTA_HOME="$1" SHEEP_GATE= python3 -c 'import importlib.machinery,sys; sys.argv=["sheep"]; print(importlib.machinery.SourceFileLoader("sheep", "'"$H"'/../bin/sheep").load_module().GATE)' 2>&1; }
check "$(gate_at "$T/rg-wt")" "$(cd "$R" && pwd -P)/modules/keel/hooks/sheep_gate.py" "sheep: REGATTA_HOME at a worktree gates at its main checkout"
check "$(gate_at "$R")" "$R/modules/keel/hooks/sheep_gate.py" "  …and the main checkout itself as given"

[ $fails -eq 0 ] && echo "sheep_gate: all ok" || { echo "sheep_gate: $fails failing"; exit 1; }
