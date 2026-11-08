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
unset PLAN_HARNESS REGATTA_COUNCIL_ARM REGATTA_UNATTENDED CLAUDE_UNATTENDED CLAUDE_CODE_DISABLE_BACKGROUND_TASKS
unset SESSIONPIPE_STATE SESSIONPIPE_CONFIG SESSIONPIPE_SOCKET SHEEP_POLICY_HOME
unset BASH_ENV   # a CI job's PATH, re-read by every bash stub (keel.sh says why)
export HOME="$T/home" REGATTA_CONFIG="$T/config"
export XDG_STATE_HOME="$T/state" XDG_CONFIG_HOME="$T/xdg-config"
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

# a council arm (wharf's bin/council): its run dir's marker, or the variable its arm_env sets (the
# council's landing review, 2026-10-28)
CR="$T/council-1/arms/codex/copy"; mkdir -p "$CR/docs"; : > "$T/council-1/.council-run"; chmod 700 "$T/council-1"
mkdir -p "$T/stray/sub"; : > "$T/stray/.council-run"; chmod 755 "$T/stray"
check "$(sg "{\"cwd\":\"$T/stray/sub\"}")" sent "a marker in a dir open to others (no run dir council makes): sent, never silenced (round 6)"
check "$(sg "{\"cwd\":\"$CR/docs\"}")" dropped "an event from under a council run dir: dropped"
check "$(printf '{"workspacePaths":["file://%s"]}' "$T/council-1/arms/antigravity/empty" | (cd "$P/open" && rm -f "$T/ran"; python3 "$H/sheep_gate.py" "$T/hook" antigravity Stop >/dev/null 2>&1; [ -f "$T/ran" ] && echo sent || echo dropped))" \
  dropped "  antigravity's workspace there too"
check "$(REGATTA_COUNCIL_ARM=1 sg "{\"cwd\":\"$P/open\"}")" dropped "  an arm's hook (REGATTA_COUNCIL_ARM), wherever it runs"
check "$(sg "{\"cwd\":\"$T/council-1x\"}")" sent "  a sibling folder with no marker: sent"
# the marker's one home is the core's common (the council's third landing review, finding 24); the gate's own
# name is for a keel with no core beside it, and must be the same
check "$(python3 - "$H" <<'PY'
import sys, types
m = types.ModuleType("sg"); m.__file__ = sys.argv[1] + "/sheep_gate.py"
exec(compile(open(m.__file__).read(), m.__file__, "exec"), m.__dict__)
got = m.council_marker()   # it puts the core it found on sys.path
import common
print(got == common.COUNCIL_MARKER == m.COUNCIL_MARKER, common.__file__.startswith(sys.argv[1].rsplit("/modules/", 1)[0]))
PY
)" "True True" "  the marker read from the core's common.COUNCIL_MARKER (this checkout's), the gate's fallback the same name"

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
# carries `workspacePaths` (file:// URIs). On agy 1.5.2 silence allows the tool,
# while sessionpipe's own `{}` denies it: discard the sender's stdout on every path.
reg true
sgh() {   # sgh <harness> <event> <event json> → "sent|dropped <stdout>"
  rm -f "$T/ran"; o=$(printf '%s' "$3" | (cd "$P/open" && python3 "$H/sheep_gate.py" "$T/hook" "$1" "$2") 2>/dev/null)
  echo "$([ -f "$T/ran" ] && echo sent || echo dropped) $o"
}
check "$(sgh codex Stop "{\"cwd\":\"$P/know\"}")" "dropped " "codex: a confidential cwd dropped, nothing printed"
e6=$(printf '{"cwd":"%s","transcript_path":"%s"}' "$P/open" "$HOME/.codex/sessions/2026/10/26/rollout-x.jsonl")
check "$(sgh codex Stop "$e6")" "sent " "codex: an open cwd sent (its rollout path is not read as a slug)"
check "$(sgh antigravity PreToolUse "{\"workspacePaths\":[\"file://$P/know\"]}")" "dropped " \
  "antigravity: a confidential reporting event dropped without denying the tool"
e7=$(printf '{"workspacePaths":["file://%s","file://%s"]}' "$P/open" "$P/kn%6Fw")
check "$(sgh antigravity Stop "$e7")" "dropped " \
  "antigravity: any confidential workspace drops it, a URI's escapes decoded"
check "$(sgh antigravity Stop "{\"workspacePaths\":[\"file://$P/open\"]}")" "sent " \
  "antigravity: an open workspace sent with empty stdout"
check "$(sgh antigravity Stop '{}')" "sent " "antigravity: no workspaces judges the process's cwd (open here)"
check "$(sgh antigravity Stop 'not json')" "dropped " "antigravity: malformed stdin prints nothing"
printf '#!/bin/sh\ncat > /dev/null; echo ran > "%s"; echo '"'"'{"decision":"allow"}'"'"'\n' "$T/ran" > "$T/hook"
check "$(sgh antigravity PreToolUse "{\"workspacePaths\":[\"$P/open\"]}")" 'sent ' \
  "antigravity: sessionpipe's stdout dropped (a plain path in workspacePaths too)"
check "$(python3 - "$H/sheep_gate.py" "$T/hook" "$P/open" <<'PY'
import json, subprocess, sys
gate, hook, folder = sys.argv[1:]
p = subprocess.run([sys.executable, gate, hook, "antigravity", "PreToolUse"],
                   input=json.dumps({"workspacePaths": [folder]}).encode(),
                   capture_output=True, cwd=folder)
print(p.returncode == 0 and p.stdout == b"")
PY
)" True "antigravity: allow stdout has zero bytes, including no newline"
printf '#!/bin/sh\ncat > /dev/null; echo ran > "%s"; echo oops\n' "$T/ran" > "$T/hook"
check "$(sgh antigravity PreToolUse "{\"workspacePaths\":[\"$P/open\"]}")" "sent " "antigravity: a non-JSON answer never reaches it"
check "$(sgh codex PreToolUse "{\"cwd\":\"$P/open\"}")" "sent oops" "codex: sessionpipe's stdout still passes through"
rm -f "$T/hook"
check "$(sgh antigravity Stop "{\"workspacePaths\":[\"$P/open\"]}")" "dropped " "antigravity: a hook that cannot run still prints nothing"
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
check "$(shp 'print(all(all(g in json.load(open(p))["hooks"][ev] for ev, gs in s.builder_hooks(n)["hooks"].items() for g in gs) if n == "codex" else json.load(open(p))[s.AG_KEY] == s.builder_hooks(n)[s.AG_KEY] for n, p in s.harness_files()))')" True \
  "  builder trust entries are exactly the groups gate writes for both harnesses"
check "$(python3 -c 'import json,sys; h=json.load(open(sys.argv[1]))["hooks"]; ss=h["SessionStart"]; print(len(h), ss[0]["hooks"][0]["command"], ss[1]["hooks"][0]["command"].endswith("codex SessionStart"), ss[1]["hooks"][0]["command"].startswith("python3 \""), "matcher" in ss[1], h["PreToolUse"][0]["matcher"] == "", ss[1]["hooks"][0]["timeout"])' "$X/.codex/hooks.json")" \
  "12 orca codex True True False True 5" "  codex: Orca's group kept first, ours gated after it, matcher \"\" on tool events only, timeout 5"
check "$(python3 -c 'import json,sys; c=json.load(open(sys.argv[1])); e=c["sessionpipe"]; print(c["orca-status"]["Stop"][0]["command"], e["enabled"], e["PreToolUse"][0]["matcher"], e["PreToolUse"][0]["hooks"][0]["timeout"], e["Stop"][0]["command"].endswith("antigravity Stop"), e["Stop"][0]["timeout"])' "$X/.gemini/config/hooks.json")" \
  "orca ag True * 15 True 15" "  antigravity: Orca's key untouched, ours sessionpipe's own shape, gated, timeout 15"
mkdir -p "$X/cc/projects"
check "$(shp 'import pathlib; p = pathlib.Path("'"$X"'/cc/settings.json"); s.gate_file(p, False, s.seed_command()); h = json.load(open(p))["hooks"]; print(h["PreToolUse"][0]["hooks"][0]["timeout"], h["PermissionRequest"][0]["hooks"][0]["timeout"])')" \
  "5 130" "  claude-code: PreToolUse stays timeout 5, PermissionRequest 130"
rm -rf "$X/cc"
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

# A stand-in for sessionpipe 0.5.0: each instance has facts with a per-session line
# cursor, and Stop/Interrupt/SessionEnd read every transcript line after it (worker.js).
# It validates the harness/event/identity it consumes; no real sender or HOME is used.
reg true
cat > "$T/pipe.js" <<'JS'
// Identity and filename spelling from sessionpipe 0.5.0's worker.js, in its own
// language: a Python copy would hide differences in JS truthiness and UTF-16.
const fs = require('node:fs'), path = require('node:path'), assert = require('node:assert');
const [name, event] = process.argv.slice(2);
assert(['claude-code', 'codex', 'antigravity'].includes(name));
assert(['Stop', 'Interrupt', 'SessionEnd', 'PreToolUse', 'UserPromptSubmit', 'SessionStart'].includes(event));
const s = JSON.parse(fs.readFileSync(0, 'utf8'));
const id = name === 'antigravity' ? s.conversationId ?? s.session_id ?? s.sessionId
         : name === 'claude-code' ? s.session_id ?? s.sessionId : s.session_id;
if (!id) process.exit(0);
const state = process.env.SESSIONPIPE_STATE;
fs.mkdirSync(state, {recursive: true});
fs.appendFileSync(path.join(state, 'calls'), event + '\n');
if (!['Stop', 'Interrupt', 'SessionEnd'].includes(event)) process.exit(0);
const safeId = (s) => String(s).replace(/[^A-Za-z0-9_.-]/g, '_').slice(0, 160);
const facts = path.join(state, 'facts', safeId(name), safeId(id) + '.json');
fs.mkdirSync(path.dirname(facts), {recursive: true});
const cur = fs.existsSync(facts) ? JSON.parse(fs.readFileSync(facts, 'utf8')) : {};
const lines = fs.readFileSync(s.transcript_path, 'utf8').trimEnd().split('\n');
fs.appendFileSync(path.join(state, 'sent'), lines.slice(Number(cur.transcript_line) || 0).map(l => l + '\n').join(''));
fs.writeFileSync(facts, JSON.stringify({transcript_line: lines.length}));
JS
cat > "$T/cursor.py" <<'PY'
import hashlib, importlib.util, json, os, shutil, stat, subprocess, sys
from pathlib import Path
t, hooks, projects = map(Path, sys.argv[1:])
env = dict(os.environ, SESSIONPIPE_STATE=str(t / "instance-a"))
registry = Path(env["REGATTA_CONFIG"]) / "wharf/repos.json"
good = registry.read_text()
failures = 0
node = shutil.which("node")
assert node, "sessionpipe requires Node"
def check(ok, label):
    global failures
    print(("  ok   " if ok else "  FAIL ") + label, flush=True)
    failures += not ok
def send(sid, cwd="open", event="Stop", text=None, name="claude-code", field="session_id", transcript=None):
    transcript = transcript or t / (str(sid) + ".jsonl")
    if text is not None:
        with transcript.open("a") as f:
            f.write(text + "\n")
    payload = {field: sid, "cwd": str(projects / cwd), "transcript_path": str(transcript)}
    if name == "antigravity":
        payload["workspacePaths"] = [str(projects / cwd)]
    p = subprocess.run([sys.executable, str(hooks / "sheep_gate.py"), node,
                        str(t / "pipe.js"), name, event], input=json.dumps(payload).encode(),
                       env=env, cwd=projects / cwd, capture_output=True)
    check(p.returncode == 0 and not p.stderr and p.stdout == b"",
          str(sid) + ": hook succeeds with expected stdout and no stub errors")
def sent():
    return "".join(p.read_text() for p in sorted(t.glob("instance-*/sent")))

# Reproduce the cursor leak directly against the stand-in: dropping an event alone
# leaves transcript_line behind, so the next allowed Stop sends the dropped turn too.
repro_tx = t / "repro.jsonl"
repro_tx.write_text("open-turn-1\n")
subprocess.run([node, str(t / "pipe.js"), "claude-code", "Stop"],
               input=json.dumps(dict(session_id="repro", cwd=str(projects / "open"),
                                     transcript_path=str(repro_tx))).encode(), env=env, check=True)
with repro_tx.open("a") as f:
    f.write("dropped-confidential-turn\nopen-turn-2\n")
subprocess.run([node, str(t / "pipe.js"), "claude-code", "Stop"],
               input=json.dumps(dict(session_id="repro", cwd=str(projects / "open"),
                                     transcript_path=str(repro_tx))).encode(), env=env, check=True)
check(sent() == "open-turn-1\ndropped-confidential-turn\nopen-turn-2\n",
      "stand-in reproduces the cursor leak when an intermediate turn's event was dropped alone")
before = sent()

send("cross", text="open-before")
send("cross", "know", "PreToolUse", "confidential-turn")
send("cross", text="open-after")
check(sent() == before + "open-before\n", "open -> confidential -> open never replays dropped turns")
before = sent()
send("clean", text="clean-one")
send("clean", text="clean-two")
check(sent() == before + "clean-one\nclean-two\n", "a never-dropped session sends every turn once")

before = sent()
registry.write_text('{"scopes":')
send("torn", text="unreadable-registry-turn")
check(sent() == before, "a torn registry drops everything")
registry.write_text(good)
send("torn", text="repaired-registry-turn")
check(sent() == before + "unreadable-registry-turn\nrepaired-registry-turn\n",
      "B: registry repair sends the next event; cursor replay during the gap is accepted")

before = sent()
cfg = Path(env["REGATTA_CONFIG"]) / "regatta"
guarded = cfg / "guarded"
guarded_text = guarded.read_text()
guarded.unlink()
guarded.mkdir()   # unreadable as text, even for root
(cfg / "overlay").write_text(str(t / "overlay"))
send("guarded-unread", text="guarded-unreadable-turn")
check(sent() == before, "an unreadable guarded key drops the event")
guarded.rmdir()
guarded.write_text(guarded_text)
(cfg / "overlay").unlink()
send("guarded-unread", text="guarded-repaired-turn")
check(sent() == before + "guarded-unreadable-turn\nguarded-repaired-turn\n",
      "B: repairing guarded sends the next event without a lasting marker")

before = sent()
(cfg / "overlay").write_text(str(t / "incomplete-overlay"))
send("core-unread", text="core-unreadable-turn")
check(sent() == before, "a core import failure drops the event")
(cfg / "overlay").unlink()
send("core-unread", text="core-repaired-turn")
check(sent() == before + "core-unreadable-turn\ncore-repaired-turn\n",
      "B: a repaired core sends the next event without a lasting marker")
before = sent()

env["SESSIONPIPE_STATE"] = str(t / "instance-b")
env["SESSIONPIPE_CONFIG"] = str(t / "second-config.json")
send("cross", event="SessionEnd", text="end-after-switch")
check(sent() == before, "a second instance cannot replay the session at SessionEnd")
registry.write_text(good.replace('"confidential": true', '"confidential": false'))
send("cross", event="SessionStart")
send("cross", text="scope-now-open")
check(sent() == before, "resume and a scope switch to open keep the old session fenced")
send("new-open", "know", text="new-session-in-open-scope")
check(sent() == before + "new-session-in-open-scope\n", "a new session follows the current scope flag")
registry.write_text(good)
before = sent()
send("new-open", "know", text="scope-private-again")
registry.write_text(good.replace('"confidential": true', '"confidential": false'))
send("new-open", "know", text="scope-open-again")
check(sent() == before, "switching the scope private and back cannot replay the private interval")
registry.write_text(good)
for name, field in (("codex", "session_id"), ("antigravity", "conversationId"),
                    ("antigravity", "sessionId"), ("claude-code", "sessionId")):
    sid = name + "-" + field
    before = sent()
    send(sid, text="before-" + sid, name=name, field=field)
    check(sent() == before + "before-" + sid + "\n", name + ": an open Stop with " + field + " is sent")
    before = sent()
    send(sid, "know", "PreToolUse", "private-" + sid, name, field)
    send(sid, text="after-" + sid, name=name, field=field)
    check(sent() == before, name + ": dropped session remains fenced with " + field)

# A tool event may be dropped for its text while the session stays in an open cwd.
# No transcript field is needed to remember the denial; it may not exist yet.
before = sent()
payload = dict(session_id="text-drop", cwd=str(projects / "open"),
               tool_input=dict(file_path=str(projects / "know" / "notes.md")))
subprocess.run([sys.executable, str(hooks / "sheep_gate.py"), node,
                str(t / "pipe.js"), "claude-code", "PreToolUse"],
               input=json.dumps(payload).encode(), env=env, cwd=projects / "open", check=True)
send("text-drop", text="turn-after-private-tool")
check(sent() == before, "a raw-text drop without a transcript blocks the later Stop")

# Marker contents are never parsed: even a damaged entry is a denial. The store
# itself failing to open also denies, and restoring it keeps earlier denials.
root = Path(env["XDG_STATE_HOME"]) / "regatta/sheep-gate"
marker = root / hashlib.sha256(b"claude-code/cross").hexdigest()
marker.rmdir()
marker.symlink_to(root / "absent")
send("cross", text="damaged-marker")
check(sent() == before, "a dangling marker still denies the session")
saved = root.with_name("saved-gate")
root.rename(saved)
root.write_text("not a directory")
send("unavailable", text="gate-store-unavailable")
check(sent() == before, "an unavailable gate store fails closed")
root.unlink()
root.symlink_to(saved)
send("symlink-store", text="gate-store-symlink")
check(sent() == before, "a symlinked gate store fails closed")
root.unlink()
saved.rename(root)
send("cross", text="store-restored")
check(sent() == before, "restoring the store preserves an existing denial")
send("codex-int", text="before-int", name="codex")
check(sent() == before + "before-int\n", "codex Interrupt case: the initial open Stop is sent")
before = sent()
send("codex-int", "know", "PreToolUse", "private-int", "codex")
send("codex-int", event="Interrupt", text="after-int", name="codex")
check(sent() == before, "codex: Interrupt on a dropped session cannot replay private turns")
for bad_id in ({}, [], 123, True):
    send(bad_id, "know", "PreToolUse", "private-nonstring", transcript=t / "nonstring.jsonl")
    send(bad_id, text="public-nonstring", transcript=t / "nonstring.jsonl")
check(sent() == before, "non-string session ids (truthy in JS) are dropped")
send("readonly", text="before-readonly")
check(sent() == before + "before-readonly\n", "read-only case: the initial open Stop is sent")
before = sent()
root.chmod(0o500)
send("readonly", "know", "PreToolUse", "private-readonly")
root.chmod(0o700)
send("readonly", text="public-readonly")
check(sent() == before, "a drop in a read-only store stays fenced after mode 0700 is restored")
check((root / hashlib.sha256(b"claude-code/readonly").hexdigest()).is_dir(),
      "the read-only store was repaired and the verified drop recorded")
send("same_fact", text="before-alias")
check(sent() == before + "before-alias\n", "alias case: the initial open Stop is sent")
before = sent()
send("same:fact", "know", "PreToolUse", "private-alias")
send("same_fact", text="public-alias")
check(sent() == before, "ids sharing a sessionpipe facts filename share a denial")

# Case-insensitive filesystems also alias safe ids that differ only in case.
# Use one explicit transcript so this replay regression runs on Linux as well.
for name, field in (("claude-code", "session_id"), ("claude-code", "sessionId"),
                    ("codex", "session_id"), ("antigravity", "conversationId"),
                    ("antigravity", "session_id"), ("antigravity", "sessionId")):
    for private_id, alias in (("ABC", "abc"), ("def", "DEF")):
        prefix = name + "-" + field + "-case-"
        private_id, alias = prefix + private_id, prefix + alias
        transcript = t / (alias + ".jsonl")
        before = sent()
        send(alias, text="before-case-alias", name=name, field=field, transcript=transcript)
        check(sent() == before + "before-case-alias\n", name + ": the initial case-alias Stop is sent")
        before = sent()
        send(private_id, "know", "PreToolUse", "private-case-alias", name, field, transcript)
        for event in ("Stop", "SessionEnd"):
            send(alias, event=event, text="after-case-alias", name=name, field=field, transcript=transcript)
            check(sent() == before, name + ": " + event + " with a case alias cannot replay private turns (" + field + ")")

before = sent()
for private_id, alias in (("astral😀", "astral__"), ("u" * 159 + "😀", "u" * 159 + "_")):
    send(alias, text="before-unicode-alias")
    check(sent() == before + "before-unicode-alias\n", "Unicode alias: the initial open Stop is sent")
    before = sent()
    send(private_id, "know", "PreToolUse", "private-unicode")
    send(alias, text="public-unicode")
    check(sent() == before, "UTF-16 replacements and truncation share sessionpipe's marker")

# XDG's relative values must not make the marker store depend on the process cwd.
env["XDG_STATE_HOME"] = "relative-state"
send("relative-state", text="before-relative-state")
check(sent() == before + "before-relative-state\n", "relative XDG: the initial open Stop is sent")
before = sent()
send("relative-state", "know", "PreToolUse", "private-relative-state")
send("relative-state", text="after-relative-state")
check(sent() == before, "a relative XDG value uses the home fallback for the lasting denial")
check((Path(env["HOME"]) / ".local/state/regatta/sheep-gate" /
       hashlib.sha256(b"claude-code/relative-state").hexdigest()).is_dir(), "relative XDG marker is at the home fallback")
env["XDG_STATE_HOME"] = str(t / "state")

send("prefix", text="before-prefix")
check(sent() == before + "before-prefix\n", "prefix case: the initial open Stop is sent")
before = sent()
payload = dict(session_id="prefix", cwd=str(projects / "open"),
               tool_input=dict(command="cat " + str(projects / "knowledge-base" / "notes.md")))
subprocess.run([sys.executable, str(hooks / "sheep_gate.py"), node, str(t / "pipe.js"), "claude-code", "PreToolUse"],
               input=json.dumps(payload).encode(), env=env, cwd=projects / "open", check=True)
send("prefix", text="after-prefix")
check(sent() == before + "after-prefix\n", "a sibling path named in a tool input with the confidential root as a prefix does not fence a session")

# A root named only as a prefix (`know.`, `know-wt/…`, a Codex cwd `know-topic`) is main's
# substring denial: that event is dropped, with no lasting marker.
def calls():
    return "".join(p.read_text() for p in sorted(t.glob("instance-*/calls")))
for tag, text in (("wt", "cat " + str(projects / "know-wt" / "secret.md")),
                  ("dot", "see " + str(projects / "know") + "."),
                  ("bak", "cat " + str(projects / "know.bak" / "notes.md")),
                  ("tilde", "see ~/" + str((projects / "know").relative_to(Path(env["HOME"]))) + ".")):
    sid = "loose-" + tag
    payload = dict(session_id=sid, cwd=str(projects / "open"), tool_input=dict(command=text))
    c0 = calls()
    subprocess.run([sys.executable, str(hooks / "sheep_gate.py"), node, str(t / "pipe.js"), "claude-code", "PreToolUse"],
                   input=json.dumps(payload).encode(), env=env, cwd=projects / "open", check=True)
    check(calls() == c0, tag + ": a prefix-only name drops the event, as main did")
    check(not (root / hashlib.sha256(("claude-code/" + sid).encode()).hexdigest()).exists(),
          tag + ": a prefix-only name leaves no lasting marker")
before = sent()
(projects / "know-topic").mkdir(exist_ok=True)
c0 = calls()
send("codex-know-topic", "know-topic", text="codex-outside-worktree", name="codex")
check(sent() == before and calls() == c0, "codex: a cwd named <root>-<topic> is dropped, as main did")

# Check policy exceptions and the fast path independently of the sender stub.
spec = importlib.util.spec_from_file_location("gate", hooks / "sheep_gate.py")
g = importlib.util.module_from_spec(spec)
spec.loader.exec_module(g)
def unread(*args):
    reads.append(True)
    raise OSError("policy read failed")
reads = []
policy = g.confidential_roots
g.confidential_roots = unread
g.main(["unused", "claude-code", "Stop"], json.dumps(dict(session_id="cross")).encode())
check(not reads, "an existing marker is checked before a broken policy")
g.main(["unused", "claude-code", "Stop"], json.dumps(dict(session_id="policy-exception")).encode())
check(not (root / hashlib.sha256(b"claude-code/policy-exception").hexdigest()).exists(),
      "a policy exception leaves no lasting marker")
g.confidential_roots = policy
send("policy-exception", text="after-policy-exception")
check(sent() == before + "after-policy-exception\n", "the event after a policy exception is sent")

payload = dict(session_id="concurrent-drop", cwd=str(projects / "open"))
recorded = []
def fence_during_policy(raw):
    g.session_dropped("claude-code", payload, True)
    recorded.append(True)
    return None
text_reason = g._text_reason
g._text_reason = fence_during_policy
check(g.confidential_roots() is not None, "the concurrent-drop case starts with readable policy")
forwarded = []
class Sender:
    def __init__(self, argv, *args, **kwargs):
        forwarded.append(argv[-1])
    def communicate(self, raw):
        if forwarded[-1] == "PreToolUse":
            g.session_dropped("codex", codex_payload, True)
popen = g.subprocess.Popen
g.subprocess.Popen = Sender
try:
    g.main(["unused", "claude-code", "Stop"], json.dumps(payload).encode())
    check(recorded and not forwarded, "a denial recorded during policy evaluation is rechecked before forwarding")
    g._text_reason = text_reason
    codex_payload = dict(session_id="concurrent-codex", turn_id="t1", cwd=str(projects / "open"))
    g.main(["unused", "codex", "PreToolUse"], json.dumps(codex_payload).encode())
    check(forwarded == ["PreToolUse"],
          "a denial recorded while PreToolUse sends blocks Codex's synthetic UserPromptSubmit")
finally:
    g.subprocess.Popen = popen
    g._text_reason = text_reason

# A store that does not exist and cannot be made holds no marker: open sessions still send.
locked = t / "locked-state"
locked.mkdir()
locked.chmod(0o500)
env["XDG_STATE_HOME"] = str(locked)
before = sent()
send("no-store", text="open-without-store")
check(os.geteuid() == 0 or sent() == before + "open-without-store\n",
      "a store that cannot be created does not silence an open session")
locked.chmod(0o700)
# A file in the store's path makes the store impossible: no marker, open sessions send.
(t / "state-file").write_text("not a directory")
env["XDG_STATE_HOME"] = str(t / "state-file")
before = sent()
send("file-in-path", text="open-file-in-path")
check(sent() == before + "open-file-in-path\n", "a file in the store's path does not silence an open session")
env["XDG_STATE_HOME"] = str(t / "state")
# The owner's store at 0600 is repaired on read: open sessions send, fences still hold.
root.chmod(0o600)
before = sent()
send("unsearchable", text="open-unsearchable")
check(sent() == before + "open-unsearchable\n", "an unsearchable owner store is repaired and does not silence an open session")
check(os.geteuid() == 0 or stat.S_IMODE(root.stat().st_mode) & 0o700 == 0o700, "the unsearchable store's owner mode is repaired")
send("cross", text="cross-after-repair")
check(sent() == before + "open-unsearchable\n", "the repaired store keeps an existing denial")
sys.exit(bool(failures))
PY
python3 "$T/cursor.py" "$T" "$H" "$P" || fails=$((fails+1))

# sessionpipe 0.5.0's Codex adapter accepts these hook names, not `heartbeat` or
# `attention.cleared`. A peer stub must validate its argv (AGENTS.md, Traps).
export SP_LOG="$T/sp.jsonl"
cat > "$T/sessionpipe-hook" <<'PY'
#!/usr/bin/env python3
import json, os, sys
allowed = {
    "codex": {"SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest",
              "Stop", "Interrupt", "SubagentStart", "SubagentStop", "PreCompact", "PostCompact", "SessionEnd"},
    "claude-code": {"PreToolUse", "PostToolUse", "PermissionRequest"},
    "antigravity": {"PreToolUse", "PostToolUse"},
}
if len(sys.argv) != 3 or sys.argv[2] not in allowed.get(sys.argv[1], set()):
    with open(os.environ["SP_LOG"], "a") as f:
        f.write(json.dumps({"bad_argv": sys.argv[1:]}) + "\n")
    sys.exit(2)
raw = sys.stdin.read()
with open(os.environ["SP_LOG"], "a") as f:
    f.write(json.dumps({"harness": sys.argv[1], "event": sys.argv[2], "payload": json.loads(raw), "raw": raw}) + "\n")
if sys.argv[2] == "PermissionRequest":
    print('{"fixture":"permission answer"}')
elif sys.argv[2] == "UserPromptSubmit":
    print("activity output must be discarded")
PY
chmod +x "$T/sessionpipe-hook"
export XDG_STATE_HOME="$T/state"
sp_run() {   # the hook's stdout is kept too: telemetry must never answer an approval
  : > "$SP_LOG"
  [ -n "${KEEP_BEATS:-}" ] || rm -rf "$T/state/keel"              # each case starts unthrottled
  [ -n "${KEEP_GATES:-}" ] || rm -rf "$T/state/regatta/sheep-gate"  # and unfenced unless testing persistence
  printf '%s' "$3" | (cd "$P/open" && python3 "$H/sheep_gate.py" "$T/sessionpipe-hook" "$1" "$2") > "$T/sp.stdout"
  python3 -c 'import json,sys; print(" ".join(x.get("event", "BAD_ARGV") for x in map(json.loads, open(sys.argv[1]))))' "$SP_LOG"
}
sp_payload() {
  printf '{"session_id":"build-1","turn_id":"turn-1","cwd":"%s","model":"model-a","tool_name":"exec_command","tool_use_id":"call-1","tool_input":{"command":"%s"},"prompt":"never copy this","transcript_path":"/rollout.jsonl"}' "$1" "${2:-echo ok}"
}
ce=$(sp_payload "$P/open")
check "$(sp_run codex PreToolUse "$ce")" "PreToolUse UserPromptSubmit" \
  "codex: tool start kept, then a supported tier-0 activity signal"
check "$(python3 -c 'import json,sys; a,b=map(json.loads,open(sys.argv[1])); print(a["raw"]==sys.argv[2], b["payload"]==dict(session_id="build-1",turn_id="turn-1",cwd=sys.argv[3],model="model-a"))' "$SP_LOG" "$ce" "$P/open")" \
  "True True" "  original bytes intact; activity has the same session and turn, no prompt, tool text or transcript"
check "$(wc -c < "$T/sp.stdout" | tr -d ' ')" 0 "  synthetic activity's stdout never reaches the CLI"
check "$(sp_run codex PostToolUse "$ce")" PostToolUse \
  "codex: tool end sends no activity (its job could land a turn.started after Stop's turn.ended)"
check "$(PLAN_HARNESS=codex sp_run codex PreToolUse "$ce")" "PreToolUse UserPromptSubmit" \
  "codex: a harness run's tools still refresh activity"
sp_run codex PreToolUse "$ce" > /dev/null
check "$(KEEP_BEATS=1 sp_run codex PreToolUse "$ce")" PreToolUse "codex: a second tool within a minute sends no second signal"
other=$(printf '%s' "$ce" | sed 's/"build-1"/"build-2"/')
check "$(KEEP_BEATS=1 sp_run codex PreToolUse "$other")" "PreToolUse UserPromptSubmit" "  another session has its own minute"
for f in "$T"/state/keel/sheep-beats/*; do touch -t 202001010000 "$f"; done
check "$(KEEP_BEATS=1 sp_run codex PreToolUse "$ce")" "PreToolUse UserPromptSubmit" "  a minute on, the signal is due again"
chmod 500 "$T/state/keel/sheep-beats"; rm -f "$T"/state/keel/sheep-beats/* 2>/dev/null
if [ -w "$T/state/keel/sheep-beats" ]; then echo "  skip unwritable stamp (running as root)"; else
  check "$(KEEP_BEATS=1 sp_run codex PreToolUse "$ce")" PreToolUse "  a stamp that will not write sends nothing"; fi
chmod 700 "$T/state/keel/sheep-beats"
check "$(PLAN_HARNESS=codex sp_run codex PermissionRequest "$ce")" "" \
  "codex: harness exec uses --approve-for-me, so no owner attention is sent"
check "$(wc -c < "$T/sp.stdout" | tr -d ' ')" 0 "  suppression prints no approval decision"
check "$(sp_run codex PermissionRequest "$ce")" PermissionRequest "codex: a hand-started session still reports owner attention"
check "$(REGATTA_UNATTENDED=1 sp_run codex PermissionRequest "$ce")" PermissionRequest \
  "  unattended alone does not mean auto-approved"
check "$(PLAN_HARNESS=other sp_run codex PermissionRequest "$ce")" PermissionRequest "  another harness marker suppresses nothing"
check "$(PLAN_HARNESS=codex sp_run claude-code PermissionRequest "$ce")" PermissionRequest \
  "claude-code: its permission/control path stays intact, even with a Codex marker"
check "$(cat "$T/sp.stdout")" '{"fixture":"permission answer"}' "  its answer still passes through (sessionpipe answers claude-code only)"
check "$(sp_run claude-code PreToolUse "$ce")" PreToolUse "claude-code: no synthetic activity"
check "$(sp_run antigravity PostToolUse "$ce")" PostToolUse "antigravity: no synthetic activity"
for ev in Stop Interrupt SessionEnd; do
  check "$(sp_run codex "$ev" "$ce")" "$ev" "codex: $ev stays terminal, no synthetic working signal"
done
minimal=$(printf '{"session_id":"build-1","cwd":"%s","tool_name":"exec_command"}' "$P/open")
check "$(sp_run codex PreToolUse "$minimal")" PreToolUse "codex: no turn_id, no activity (it would read as a new prompt)"
check "$(sp_run codex PreToolUse '{}')" PreToolUse "codex: missing session/tool makes no activity"
slashtool=$(printf '{"session_id":"build-1","turn_id":"turn-1","cwd":"%s","tool_name":"mcp/some tool"}' "$P/open")
check "$(sp_run codex PreToolUse "$slashtool")" "PreToolUse UserPromptSubmit" "codex: any tool name refreshes activity (the signal names no tool)"
for ev in PreToolUse PostToolUse PermissionRequest; do
  check "$(PLAN_HARNESS=codex sp_run codex "$ev" "$(sp_payload "$P/know")")" "" \
    "codex: confidential cwd drops $ev and any synthetic event"
done
check "$(sp_run codex PreToolUse "$(sp_payload "$P/open" "cat $P/know/notes.md")")" "" \
  "codex: private tool text drops the activity signal too"
check "$(sp_run codex PreToolUse "$(sp_payload "$CR/docs")")" "" "codex: council run sends no activity"
check "$(REGATTA_COUNCIL_ARM=1 sp_run codex PreToolUse "$ce")" "" "codex: council arm marker sends no activity"
check "$(sp_run codex PreToolUse 'not json')" "" "codex: malformed input sends no activity"
fenced_open=$(printf '%s' "$ce" | sed 's/"build-1"/"build-fenced"/')
fenced_know=$(sp_payload "$P/know" | sed 's/"build-1"/"build-fenced"/')
check "$(KEEP_GATES=1 sp_run codex PreToolUse "$fenced_open")" "PreToolUse UserPromptSubmit" \
  "codex fence: open tool and activity send before any confidential drop"
check "$(KEEP_GATES=1 sp_run codex PreToolUse "$fenced_know")" "" \
  "  confidential tool drops and records the session marker"
check "$(KEEP_GATES=1 sp_run codex PreToolUse "$fenced_open")" "" \
  "  after returning to open, neither PreToolUse nor synthetic UserPromptSubmit sends"
check "$(KEEP_GATES=1 sp_run codex Stop "$fenced_open")" "" \
  "  nor does a later open Stop"
perm_open=$(printf '%s' "$ce" | sed 's/"build-1"/"build-perm"/')
perm_know=$(sp_payload "$P/know" | sed 's/"build-1"/"build-perm"/')
check "$(KEEP_GATES=1 PLAN_HARNESS=codex sp_run codex PermissionRequest "$perm_open")" "" \
  "  auto-approved open PermissionRequest suppresses attention without fencing the session"
check "$(KEEP_GATES=1 PLAN_HARNESS=codex sp_run codex PreToolUse "$perm_open")" "PreToolUse UserPromptSubmit" \
  "  …next open tool and activity still send"
check "$(KEEP_GATES=1 PLAN_HARNESS=codex sp_run codex PermissionRequest "$perm_know")" "" \
  "  confidential PermissionRequest under PLAN_HARNESS=codex records the session marker"
check "$(KEEP_GATES=1 PLAN_HARNESS=codex sp_run codex PreToolUse "$perm_open")" "" \
  "  …and blocks later open tools and activity"
torn_ce=$(printf '%s' "$ce" | sed 's/"build-1"/"build-torn"/')
cp "$REGATTA_CONFIG/wharf/repos.json" "$T/sp-good.json"
printf '{"scopes":' > "$REGATTA_CONFIG/wharf/repos.json"
check "$(KEEP_GATES=1 sp_run codex PreToolUse "$torn_ce")" "" "codex: torn registry drops original and synthetic activity"
rm "$REGATTA_CONFIG/wharf/repos.json"
ln -s "$T/missing-registry.json" "$REGATTA_CONFIG/wharf/repos.json"
check "$(KEEP_GATES=1 sp_run codex PreToolUse "$torn_ce")" "" "codex: dangling registry link drops original and synthetic activity"
rm "$REGATTA_CONFIG/wharf/repos.json"
cp "$T/sp-good.json" "$REGATTA_CONFIG/wharf/repos.json"
check "$(KEEP_GATES=1 sp_run codex PreToolUse "$torn_ce")" "PreToolUse UserPromptSubmit" \
  "  B: once the registry reads again, the session's tool and activity send"

[ $fails -eq 0 ] && echo "sheep_gate: all ok" || { echo "sheep_gate: $fails failing"; exit 1; }
