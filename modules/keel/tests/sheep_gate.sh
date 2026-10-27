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

unset CLAUDE_REPOS_JSON CLAUDE_PROJECT_DIR REGATTA_HOME ACCOUNTS_FILE CODEX_HOME GEMINI_CLI_HOME
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
cp "$T/good.json" "$REGATTA_CONFIG/wharf/repos.json"; mkdir -p "$REGATTA_CONFIG/regatta"; echo "$T/nowhere" > "$REGATTA_CONFIG/regatta/overlay"
check "$(sg "{\"cwd\":\"$P/open\"}")" dropped "a core that does not import beside a registry (config incomplete): every event dropped"
rm "$REGATTA_CONFIG/regatta/overlay"
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

# sheep's claude_dirs: sessionpipe's own list plus each login dir the account registry names that
# holds a settings.json — an Orca profile sits outside the home folder's .claude* dirs (B14b: its entries kept the
# overlay's gate path after B14a's `gate`); a row whose dir has no settings.json is left out
SH="$T/sh"; mkdir -p "$SH/.claude" "$T/orca-prof" "$T/bare-prof"; echo '{}' > "$T/orca-prof/settings.json"
printf '{"accounts": [{"label": "a", "provider": "claude", "home": "%s"}, {"label": "b", "provider": "claude", "home": "%s"}, {"label": "c", "provider": "codex", "home": "%s"}]}\n' \
  "$T/orca-prof" "$T/bare-prof" "$T/orca-prof" > "$T/acc.json"
dirs_at() { HOME="$SH" ACCOUNTS_FILE="$1" CLAUDE_CONFIG_DIR= python3 -c 'import importlib.machinery,sys; sys.argv=["sheep"]; print(" ".join(str(d) for d in importlib.machinery.SourceFileLoader("sheep", "'"$H"'/../bin/sheep").load_module().claude_dirs()))' 2>&1; }
check "$(dirs_at "$T/acc.json")" "$(cd "$SH/.claude" && pwd -P) $(cd "$T/orca-prof" && pwd -P)" "sheep: claude_dirs adds a registry row's login dir that holds a settings.json"
check "$(dirs_at "$T/none.json")" "$(cd "$SH/.claude" && pwd -P)" "  no registry: sessionpipe's own list, as before"
# is_gated: the overlay's shim no longer counts (B14b deleted it); only this gate file does
check "$(SHEEP_GATE="$R/modules/keel/hooks/sheep_gate.py" python3 -c 'import importlib.machinery,sys; sys.argv=["sheep"]; s = importlib.machinery.SourceFileLoader("sheep", "'"$H"'/../bin/sheep").load_module()
print(s.is_gated(s.gated("node x.js claude-code Stop")), s.is_gated("python3 \"/old/overlay/hooks/sheep_gate.py\" node x.js claude-code Stop"))' 2>&1)" "True False" \
  "sheep: is_gated takes this gate's path, never the overlay's old shim"

# Codex and Antigravity behind the same gate (2026-10-26). Codex's event carries `cwd`; Antigravity's
# carries `workspacePaths` (file:// URIs) and reads the hook's stdout as its answer — anything but
# JSON is a deny, so the gate prints `{}` on every path that sends nothing.
reg true
sgh() {   # sgh <harness> <event> <event json> → "sent|dropped <stdout>"
  rm -f "$T/ran"; o=$(printf '%s' "$3" | (cd "$P/open" && python3 "$H/sheep_gate.py" "$T/hook" "$1" "$2") 2>/dev/null)
  echo "$([ -f "$T/ran" ] && echo sent || echo dropped) $o"
}
check "$(sgh codex Stop "{\"cwd\":\"$P/know\"}")" "dropped " "codex: a confidential cwd dropped, nothing printed"
e6=$(printf '{"cwd":"%s","transcript_path":"%s"}' "$P/open" "$HOME/.codex/sessions/2026/10/26/rollout-x.jsonl")
check "$(sgh codex Stop "$e6")" "sent " "codex: an open cwd sent (its rollout path is not read as a slug)"
check "$(sgh antigravity PreToolUse "{\"workspacePaths\":[\"file://$P/know\"]}")" "dropped {}" \
  "antigravity: a confidential workspace dropped, and {} printed (silence would deny the tool)"
e7=$(printf '{"workspacePaths":["file://%s","file://%s"]}' "$P/open" "$P/kn%6Fw")
check "$(sgh antigravity Stop "$e7")" "dropped {}" \
  "antigravity: any confidential workspace drops it, a URI's escapes decoded"
check "$(sgh antigravity Stop "{\"workspacePaths\":[\"file://$P/open\"]}")" "sent {}" \
  "antigravity: an open workspace sent; a hook that prints nothing still answers {}"
check "$(sgh antigravity Stop '{}')" "sent {}" "antigravity: no workspaces judges the process's cwd (open here)"
check "$(sgh antigravity Stop 'not json')" "dropped {}" "antigravity: stdin that is not JSON answers {}"
printf '#!/bin/sh\ncat > /dev/null; echo ran > "%s"; echo '"'"'{"decision":"allow"}'"'"'\n' "$T/ran" > "$T/hook"
check "$(sgh antigravity PreToolUse "{\"workspacePaths\":[\"$P/open\"]}")" 'sent {}' \
  "antigravity: the gate's own {} is the one answer, sessionpipe's stdout dropped (a plain path in workspacePaths too)"
printf '#!/bin/sh\ncat > /dev/null; echo ran > "%s"; echo oops\n' "$T/ran" > "$T/hook"
check "$(sgh antigravity PreToolUse "{\"workspacePaths\":[\"$P/open\"]}")" "sent {}" "antigravity: a non-JSON answer never reaches it"
check "$(sgh codex PreToolUse "{\"cwd\":\"$P/open\"}")" "sent oops" "codex: sessionpipe's stdout still passes through"
rm -f "$T/hook"
check "$(sgh antigravity Stop "{\"workspacePaths\":[\"$P/open\"]}")" "dropped {}" "antigravity: a hook that cannot run still answers {}"
printf '#!/bin/sh\ncat > /dev/null; echo ran > "%s"\n' "$T/ran" > "$T/hook"; chmod +x "$T/hook"

# sheep writes the gated entries into Codex's and Antigravity's hooks.json beside Orca's, keeps
# them current, counts them, and forgets their private outbox sessions by harness.
X="$T/hx"; mkdir -p "$X/.claude/projects" "$X/.codex" "$X/.gemini/config" "$X/state"
L="$X/sessionpipe-hook"; printf '#!/bin/sh\n' > "$L"; chmod +x "$L"; G="$H/sheep_gate.py"
printf '{"hooks": {"Stop": [{"hooks": [{"type": "command", "command": "python3 \\"%s\\" \\"%s\\" claude-code Stop"}]}]}}\n' "$G" "$L" > "$X/.claude/settings.json"
printf '{"hooks": {"SessionStart": [{"hooks": [{"type": "command", "command": "orca codex"}]}]}}\n' > "$X/.codex/hooks.json"
printf '{"orca-status": {"Stop": [{"type": "command", "command": "orca ag"}]}}\n' > "$X/.gemini/config/hooks.json"
shp() { HOME="$X" SHEEP_GATE="$G" SESSIONPIPE_STATE="$X/state" CLAUDE_CONFIG_DIR= ACCOUNTS_FILE="$T/none.json" python3 -c 'import importlib.machinery,sys,json; sys.argv=["sheep"]
s = importlib.machinery.SourceFileLoader("sheep", "'"$H"'/../bin/sheep").load_module()
'"$1" 2>&1; }
check "$(shp 'print(s.seed_command() == "\"'"$L"'\"", [n for n, p in s.harness_files()])')" "True ['codex', 'antigravity']" \
  "sheep: the seed is Claude Code's command; both harness folders found"
check "$(shp 'print(" ".join(str(p.name) for p in s.hook_totals()[4]))')" "hooks.json hooks.json" \
  "  check: both hooks files dark before the gate"
check "$(shp 'seed = s.seed_command(); print(*(len(s.gate_harness(n, p, False, seed)[0]) for n, p in s.harness_files()))')" "12 5" \
  "  gate adds Codex's 12 events and Antigravity's 5"
check "$(python3 -c 'import json,sys; h=json.load(open(sys.argv[1]))["hooks"]; ss=h["SessionStart"]; print(len(h), ss[0]["hooks"][0]["command"], ss[1]["hooks"][0]["command"].endswith("codex SessionStart"), ss[1]["hooks"][0]["command"].startswith("python3 \""), "matcher" in ss[1], h["PreToolUse"][0]["matcher"] == "")' "$X/.codex/hooks.json")" \
  "12 orca codex True True False True" "  codex: Orca's group kept first, ours gated after it, matcher \"\" on tool events only"
check "$(python3 -c 'import json,sys; c=json.load(open(sys.argv[1])); e=c["sessionpipe"]; print(c["orca-status"]["Stop"][0]["command"], e["enabled"], e["PreToolUse"][0]["matcher"], e["Stop"][0]["command"].endswith("antigravity Stop"), e["Stop"][0]["timeout"])' "$X/.gemini/config/hooks.json")" \
  "orca ag True * True 5" "  antigravity: Orca's key untouched, ours sessionpipe's own shape, gated"
check "$(shp 'seed = s.seed_command(); print(*(len(s.gate_harness(n, p, False, seed)[0]) for n, p in s.harness_files()), s.counts(s.harness_survey("codex", json.load(open(s.harness_files()[0][1])))))')" \
  "0 0 {'gated': 12, 'ungated': 0, 'absent': 0}" "  a second gate changes nothing; every Codex event gated"
check "$(shp 't = s.hook_totals(); print(t[0], len(t[4]))')" "{'gated': 18, 'ungated': 0, 'absent': 13} 0" \
  "  check: the harness files count with the Claude dir, none dark"
# sessionpipe's own install writes them ungated (R1): gate puts the gate back in front
python3 -c 'import json,sys; p=sys.argv[1]; c=json.load(open(p)); h=c["sessionpipe"]["Stop"][0]; h["command"]=h["command"].split("\" ",1)[1]; json.dump(c,open(p,"w"))' "$X/.gemini/config/hooks.json"
check "$(shp 'print(s.hook_totals()[0]["ungated"], s.gate_harness("antigravity", s.harness_files()[1][1], False, None)[0], s.hook_totals()[0]["ungated"])')" \
  "1 ['gated Stop'] 0" "  an ungated Antigravity entry counts, and gate (no seed needed) gates it again"
printf '[hooks.state."%s:session_start:1:0"]\nenabled = true\ntrusted_hash = "sha256:x"\n\n[hooks.state."%s:stop:0:0"]\nenabled = true\n' \
  "$X/.codex/hooks.json" "$X/.codex/hooks.json" > "$X/.codex/config.toml"
check "$(shp 'print(s.codex_unreviewed(s.harness_files()[0][1]))')" "11" \
  "  codex_unreviewed: 11 of our 12 entries have no trusted_hash (Orca's entry is not ours)"
# an owner's `enabled: false` stays: hooked (not dark), and gate keeps it off
python3 -c 'import json,sys; p=sys.argv[1]; c=json.load(open(p)); c["sessionpipe"]["enabled"]=False; json.dump(c,open(p,"w"))' "$X/.gemini/config/hooks.json"
check "$(shp 'f = s.harness_files()[1][1]; print(len(s.hook_totals()[4]), s.gate_harness("antigravity", f, False, s.seed_command())[0], json.load(open(f))["sessionpipe"]["enabled"])')" \
  "0 [] False" "  a disabled Antigravity entry is hooked, not dark, and gate leaves it disabled"
# a notify sessionpipe's own install wrote runs ungated: counted, at the top level only
cp "$X/.codex/config.toml" "$X/toml.bak"
{ printf 'notify = ["%s", "codex", "notify"]\n\n' "$L"; cat "$X/toml.bak"; } > "$X/.codex/config.toml"
check "$(shp 'print(s.codex_notify(s.harness_files()[0][1]), s.hook_totals()[0]["ungated"])')" "True 1" \
  "  codex: sessionpipe in notify is one ungated entry"
{ printf 'notify = ["/x/SkyComputerUseClient", "turn-ended", "--previous-notify", "[\\"%s\\",\\"codex\\",\\"notify\\"]"]\n' "$L"; cat "$X/toml.bak"; } > "$X/.codex/config.toml"
check "$(shp 'print(s.codex_notify(s.harness_files()[0][1]))')" "True" "  …chained behind Computer Use's --previous-notify too"
{ cat "$X/toml.bak"; printf '\n[x]\nnotify = ["%s", "codex", "notify"]\n' "$L"; } > "$X/.codex/config.toml"
check "$(shp 'print(s.codex_notify(s.harness_files()[0][1]))')" "False" "  …but not inside a [table], where Codex never reads it"
cp "$X/toml.bak" "$X/.codex/config.toml"
# Gemini CLI: gate never writes it, so any sessionpipe entry there is ungated (a bare install's)
printf '{"hooks": {"AfterAgent": [{"hooks": [{"type": "command", "command": "\\"%s\\" gemini-cli AfterAgent"}]}]}}\n' "$L" > "$X/.gemini/settings.json"
check "$(shp 'print(s.gemini_cli_ungated(), s.hook_totals()[0]["ungated"])')" "1 1" "  gemini-cli: a sessionpipe entry in its settings counts ungated"
rm "$X/.gemini/settings.json"
mkdir -p "$X/odd"; printf '{"hooks": {"Stop": [{"hooks": [{"type": "command", "command": "\\"%s\\" gemini-cli Stop"}]}]}}\n' "$L" > "$X/odd/hooks.json"
check "$(shp 'import pathlib
try: s.gate_file(pathlib.Path("'"$X"'/odd/hooks.json"), True, None, "codex")
except s.Refused as e: print("refused:", str(e).split(" —")[0])')" "refused: no sessionpipe command of codex's or Claude Code's to copy" \
  "  nothing to copy a command from: refused, not a crash"
mkdir -p "$X/state/outbox/codex" "$X/state/outbox/antigravity"
printf '{"session":{"id":"c1","cwd":"%s"}}\n' "$P/know" > "$X/state/outbox/codex/c1.jsonl"
printf '{"session":{"id":"a1","cwd":"%s"}}\n' "$P/open" > "$X/state/outbox/antigravity/a1.jsonl"
check "$(shp 'print([k for k, _ in s.private_sessions()], s.split_key("codex:c1"), s.split_key("abc-1"))')" \
  "['codex:c1'] ('codex', 'c1') ('claude-code', 'abc-1')" \
  "  forget-private: a Codex session in a confidential repo found, forgotten by its harness"

[ $fails -eq 0 ] && echo "sheep_gate: all ok" || { echo "sheep_gate: $fails failing"; exit 1; }
