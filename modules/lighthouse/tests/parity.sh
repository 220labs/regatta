#!/usr/bin/env bash
# vendor-hooks: the guards a Claude session meets, met by Codex and Antigravity through their own hooks.
#   bash modules/lighthouse/tests/parity.sh
# Two parts. The parity table (parity_rules.py): every rule, a deny case and an allow case, run against
# Claude Code's, Codex's and Antigravity's payload shapes — a rule a CLI cannot meet is a red row. Then
# bin/vendor-hooks on a stand-in HOME: the entries, in place beside another tool's, idempotent, every
# Codex home the registry names, the rules pointer, check's verdicts. Scratch dirs only: HOME moved, the
# config dir pinned, git's identity a file of the suite's own (Traps: a suite that moves HOME and commits).
set -u
LH="$(cd "$(dirname "$0")/.." && pwd)"
MODS="$(dirname "$LH")"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fails=0
check() { if [ "$1" = "$2" ]; then echo "ok   $3"; else echo "FAIL $3: expected [$2] got [$1]"; fails=$((fails+1)); fi; }
has() { case "$1" in *"$2"*) echo "ok   $3";; *) echo "FAIL $3: [$2] not in [$1]"; fails=$((fails+1));; esac; }

export HOME="$T/home" REGATTA_CONFIG="$T/config"
mkdir -p "$HOME" "$REGATTA_CONFIG/regatta"
echo Ada > "$REGATTA_CONFIG/regatta/owner"
printf '[user]\n\tname = t\n\temail = t@t.invalid\n[init]\n\tdefaultBranch = main\n' > "$T/gitconfig"
export GIT_CONFIG_GLOBAL="$T/gitconfig" GIT_CONFIG_NOSYSTEM=1
unset CODEX_HOME GEMINI_CLI_HOME CLAUDE_UNATTENDED REGATTA_UNATTENDED CLAUDE_CODE_DISABLE_BACKGROUND_TASKS \
  CLAUDE_CODE_SESSION_ID CLAUDE_PROJECT_DIR REGATTA_HOME REGATTA_LEGACY
export CLAUDE_CONFIG_DIR="$T/claude-config" CLAUDE_HOOK_NO_GITHUB=1 CLAUDE_HOOK_NO_SHEEP=1 CLAUDE_HOOK_NO_AUTOFINISH=1
export ACCOUNTS_FILE="$T/accounts.json" ACCOUNT_ORCA_FILE="$T/account-orca.json"

# --- fixtures: a vault, the CLIs' logins, an opted-in repo with a claude/* worktree ---------------
SGV="$T/vault"; mkdir -p "$SGV/_secrets"; echo K=1 > "$SGV/_secrets/app.env"; echo notes > "$SGV/notes.md"
export SECRETS_GUARD_DIR="$SGV/_secrets"
mkdir -p "$HOME/.codex" "$HOME/.gemini/config"
echo '{"fixture":"stand-in"}' > "$HOME/.codex/auth.json"; echo 'model = "x"' > "$HOME/.codex/config.toml"
echo '{"stand":"in"}' > "$HOME/.gemini/oauth_creds.json"; echo stand-in > "$HOME/.gemini/jetski-standalone-oauth-token"
echo '{}' > "$HOME/.gemini/settings.json"; mkdir -p "$HOME/.gemini/antigravity-cli"; echo '{}' > "$HOME/.gemini/antigravity-cli/mcp_oauth_tokens.json"
R="$T/repo"; mkdir -p "$R/.claude"
git init -q "$R" && printf '.claude/worktrees/\n' > "$R/.gitignore" && echo '{"checkpoint": true, "main": "main"}' > "$R/.claude/workflow.json" \
  && echo a > "$R/README.md" && git -C "$R" add -A && git -C "$R" commit -qm base
R=$(cd "$R" && pwd -P)
git -C "$R" worktree add -q "$R/.claude/worktrees/t" -b claude/x/2026-10-29-t main
git -C "$R" branch -q claude/x/2026-10-29-old main
WT="$R/.claude/worktrees/t"
CP=""; [ -f "$MODS/wharf/hooks/checkpoint.py" ] && CP="$MODS/wharf/hooks/checkpoint.py"
DISPATCH=""; [ -f "$MODS/wharf-runs/bin/dispatch" ] && DISPATCH="$MODS/wharf-runs/bin/dispatch"
[ -n "$CP" ] || echo "note: wharf is not in this tree — its rows are not judged here"

echo "== the parity table"
PARITY_LIGHTHOUSE="$LH" PARITY_CHECKPOINT="$CP" PARITY_DISPATCH="$DISPATCH" PARITY_SGV="$SGV" \
  PARITY_PRIMARY="$R" PARITY_WORKTREE="$WT" python3 "$LH/tests/parity_rules.py" > "$T/table.out" 2>&1
rc=$?
cat "$T/table.out"
check "$rc" 0 "the parity table: every rule met by every CLI"
check "$(git -C "$WT" status --short | wc -l | tr -d ' ')" 0 "  no case wrote the worktree (the guards judge, the suite never runs the call)"
check "$([ -f "$(git -C "$WT" rev-parse --absolute-git-dir)/claude/owner.json" ] && python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["session"])' "$(git -C "$WT" rev-parse --absolute-git-dir)/claude/owner.json")" \
  "parity-claude" "  the lock is Claude's alone: no vendor call took it (checkpoint's VENDOR)"

echo "== the adapter's edges"
VH="$LH/hooks/vendor_hook.py"
check "$(printf 'not json' | python3 "$VH" antigravity "$LH/hooks/secrets_guard.py")" "{}" "Antigravity, stdin that is no JSON: one {} (it reads anything else as a deny)"
check "$(printf 'not json' | python3 "$VH" codex "$LH/hooks/secrets_guard.py")" "" "Codex, the same: nothing, an allow"
check "$(printf '{"toolCall":{"name":"run_command","args":{"CommandLine":"ls"}}}' | python3 "$VH" antigravity "$T/no-such-guard.py")" "{}" "a guard that is not there: allowed (fails open, as the guards do)"
check "$(printf '{"tool_name":"mcp__fs__read","tool_input":{"path":"%s/_secrets/app.env"},"cwd":"%s"}' "$SGV" "$WT" | python3 "$VH" codex "$LH/hooks/secrets_guard.py")" "" \
  "an MCP tool: not translated, so not judged (docstring; the table has no MCP row)"
P='*** Begin Patch\n*** Update File: ok.txt\n*** Move to: '"$SGV"'/_secrets/moved.env\n*** End Patch\n'
check "$(printf '{"tool_name":"apply_patch","tool_input":{"command":"%s"},"cwd":"%s"}' "$P" "$WT" | python3 "$VH" codex "$LH/hooks/secrets_guard.py" | python3 -c 'import json,sys; print(json.load(sys.stdin)["hookSpecificOutput"]["permissionDecision"])')" \
  "deny" "a patch whose move lands in _secrets: denied (each file of a patch judged)"
check "$(printf '{"tool_name":"Bash","tool_input":{"command":["git","commit","-m","x"]},"cwd":"%s","model":"m"}' "$WT" | python3 "$VH" codex trailer)" "" \
  "an argv-list commit: not rewritten (its shape would change)"
check "$(printf '{"tool_name":"Bash","tool_input":{"command":"git commit -m x\\n\\nCo-Authored-By: A <a@b>"},"cwd":"%s","model":"m"}' "$WT" | python3 "$VH" codex trailer)" "" \
  "a commit that names its co-author already: left as it is"
check "$(printf '{"tool_name":"Bash","tool_input":{"command":"echo git commit"},"cwd":"%s","model":"m"}' "$WT" | python3 "$VH" codex trailer)" "" \
  "\`git commit\` as an argument, not a command: left as it is"
check "$(printf '{"toolCall":{"name":"run_command","args":{"CommandLine":"git -C %s commit -qm z","Cwd":"%s"}},"workspacePaths":["%s"],"modelName":"auto"}' "$WT" "$WT" "$WT" | python3 "$VH" antigravity trailer)" \
  "{\"overwrite\": {\"CommandLine\": \"git -C $WT commit --trailer 'Co-Authored-By: Antigravity <noreply@google.com>' -qm z\"}}" \
  "Antigravity: \`overwrite\` alone, no \`decision\` (its permission flow unchanged); model \`auto\` names the CLI alone"

echo "== the trailer rewrites one simple commit, and allows nothing a guard refuses"
trl() { printf '%s' "$1" | python3 "$VH" codex trailer; }
cj() { python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":json.loads(sys.argv[1])},"cwd":sys.argv[2],"model":"m"}))' "$1" "$2"; }
check "$(trl "$(cj '"git commit -m x && rm -rf y"' "$WT")")" "" "a commit with another command after it: not rewritten (the allow would carry it)"
check "$(trl "$(cj '"git commit -F - <<EOF\nx\nEOF"' "$WT")")" "" "  a heredoc commit: not rewritten"
check "$(trl "$(cj '"ssh h '"'"'git commit -m x'"'"'"' "$WT")")" "" "  a commit inside ssh's quotes: not rewritten"
check "$(trl "$(cj '"git commit -m \"$(whoami)\""' "$WT")")" "" "  a commit with a command substitution: not rewritten"
check "$(trl "$(cj '"git commit -m \"don'"'"'t\" && rm -rf y && echo '"'"'ok'"'"'"' "$WT")")" "" "  an apostrophe inside double quotes, then an operator: not rewritten (quotes read in context)"
check "$(trl "$(cj '"git commit --no-verify -m x"' "$WT")")" "" "  a commit that skips git's hooks (--no-verify): not rewritten, so no allow"
check "$(trl "$(cj '"git -c core.hooksPath=/dev/null commit -m x"' "$WT")")" "" "  …or points core.hooksPath away: not rewritten"
check "$(trl "$(cj '"git commit --no-veri -m x"' "$WT")")" "" "  …or abbreviates --no-verify, as git accepts: not rewritten"
check "$(trl "$(cj '"git -c core.editor=/tmp/x.sh commit"' "$WT")")" "" "  a -c that runs a program (core.editor): not rewritten"
check "$(trl "$(cj '"git commit -m $'"'"'\\'"'"''"'"' ; touch y #'"'"'"' "$WT")")" "" "  ANSI-C quoting hiding an operator: not rewritten"
check "$(trl "$(cj '"git commit -m \"${(e):-x}\""' "$WT")")" "" "  a \${…} expansion (zsh's (e) runs code): not rewritten"
check "$(trl "$(cj '"git commit -m \"it'"'"'s fine\""' "$WT")" | python3 -c 'import json,sys; print(json.load(sys.stdin)["hookSpecificOutput"]["permissionDecision"])')" \
  "allow" "  an apostrophe inside a double-quoted message alone: still rewritten"
check "$(printf '%s' "$(cj '"git commit -m x"' "$WT")" | VENDOR_HOOK_BUDGET=0.5 python3 "$VH" codex trailer 2>/dev/null)" "" \
  "  the guards out of time (no answer): not rewritten — only a clean pass from each carries the allow"
check "$(trl "$(cj '"git commit -qam x"' "$R")")" "" "  a commit a guard refuses (on the primary's main): no allow"
check "$(trl "$(cj '["bash","-lc","git commit -m x"]' "$WT")" | python3 -c 'import json,sys; h=json.load(sys.stdin)["hookSpecificOutput"]; print(h["permissionDecision"], h["updatedInput"]["command"][:2], "--trailer" in h["updatedInput"]["command"][2])')" \
  "allow ['bash', '-lc'] True" "  an argv commit through a shell: its script rewritten, the argv kept"

echo "== a command Codex sends as argv is judged as its script"
check "$(cj '["bash","-lc","git push --no-verify origin claude/x/2026-10-29-t"]' "$WT" | python3 "$VH" codex "$CP" | python3 -c 'import json,sys; s=sys.stdin.read().strip(); print(json.loads(s)["hookSpecificOutput"]["permissionDecision"] if s else "allow")')" \
  deny "bash -lc '<push --no-verify>': denied (a joined argv hid it in quotes)"
check "$(printf '{"tool_name":"write_stdin","tool_input":{"session_id":3,"chars":"cat %s/_secrets/app.env\\n"},"cwd":"%s"}' "$SGV" "$WT" | python3 "$VH" codex "$LH/hooks/secrets_guard.py" | python3 -c 'import json,sys; s=sys.stdin.read().strip(); print(json.loads(s)["hookSpecificOutput"]["permissionDecision"] if s else "allow")')" \
  deny "Codex's write_stdin typing a read of _secrets: denied"

echo "== Antigravity's other readers and shell input"
ag() { printf '{"toolCall":{"name":"%s","args":%s},"workspacePaths":["%s"]}' "$1" "$2" "$WT" | python3 "$VH" antigravity "$LH/hooks/secrets_guard.py" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("decision","allow"))'; }
check "$(ag send_command_input "{\"CommandId\":\"c1\",\"Input\":\"cat $SGV/_secrets/app.env\"}")" deny "send_command_input typing a read of _secrets: denied"
check "$(ag codebase_search "{\"Query\":\"KEY\",\"TargetDirectories\":[\"$SGV/_secrets\"]}")" deny "codebase_search over _secrets: denied"
check "$(ag view_code_item "{\"File\":\"$SGV/_secrets/app.env\",\"NodePaths\":[\"x\"]}")" deny "view_code_item of a _secrets file: denied"
check "$(ag read_url_content "{\"Url\":\"file://$HOME/.codex/auth.json\"}")" deny "read_url_content of a file: URL to Codex's login: denied"
check "$(ag read_url_content '{"Url":"https://example.com/_secrets/app.env"}')" allow "  a web URL: no file read here"
check "$(ag view_file "{\"AbsolutePath\":\"$HOME/.gemini/antigravity-cli/mcp_oauth_tokens.json\"}")" deny "agy's MCP token file a folder down: denied"
check "$(ag write_to_file "{\"TargetFile\":\"$WT/n.txt\",\"CodeContent\":\"$SGV/_secrets/app.env\"}")" allow "  a path written as a file's content is text, not a target"

echo "== one budget for every guard run of a call"
printf 'import time, json\ntime.sleep(2)\nprint(json.dumps({"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"slow"}}))\n' > "$T/slow_guard.py"
P3='*** Begin Patch\n*** Add File: a.txt\n+x\n*** Add File: b.txt\n+x\n*** Add File: c.txt\n+x\n*** End Patch\n'
start=$(date +%s)
out=$(printf '{"tool_name":"apply_patch","tool_input":{"command":"%s"},"cwd":"%s"}' "$P3" "$WT" | VENDOR_HOOK_BUDGET=1.5 python3 "$VH" codex "$T/slow_guard.py" 2>"$T/budget.err")
check "$out" "" "three files past a 1.5 s budget: the call is not judged, so allowed (fails open)"
check "$(( $(date +%s) - start < 6 ))" 1 "  and it returns within the budget, not after every guard ran"
has "$(cat "$T/budget.err")" "out of time" "  said on stderr"

echo "== the CLI logins wall, for a Claude session"
cl() { printf '{"hook_event_name":"PreToolUse","tool_name":"%s","tool_input":%s,"cwd":"%s"}' "$1" "$2" "$WT" | python3 "$LH/hooks/secrets_guard.py" | python3 -c 'import json,sys; s=sys.stdin.read().strip(); print(json.loads(s)["hookSpecificOutput"]["permissionDecision"] if s else "allow")'; }
check "$(cl Bash '{"command":"cat $CODEX_HOME/auth.json"}')" deny "a Codex login behind \$CODEX_HOME: denied"
mkdir -p "$HOME/.codex-work"; echo '{}' > "$HOME/.codex-work/auth.json"
check "$(cl Read "{\"file_path\":\"$HOME/.codex-work/auth.json\"}")" deny "a registry Codex home's login (~/.codex-<label>): denied"
check "$(cl Bash "{\"command\":\"cp -R $HOME/.codex $T/copy\"}")" deny "a recursive copy of a Codex home: denied"
check "$(cl Bash "{\"command\":\"ls -la $HOME/.codex/auth.json\"}")" allow "ls of it: allowed, as for _secrets"
check "$(cl Read "{\"file_path\":\"$WT/docs/auth.json.md\"}")" allow "a file merely named like it: allowed"
check "$(cl Bash "{\"command\":\"cat $HOME/.cod*/*.json\"}")" deny "a glob that matches a Codex login: denied"
check "$(cl Bash "{\"command\":\"cd $HOME/.codex && cat auth.json\"}")" deny "cd into a Codex home, then a relative read: denied"
check "$(cl Bash "{\"command\":\"head -c 20 $HOME/.gemini/jetski-standalone-oauth-token\"}")" deny "agy's keychain fallback file: denied"
check "$(cl Read "{\"file_path\":\"$HOME/.codex/hooks.json\"}")" allow "Codex's hooks.json: a read is fine"
check "$(cl Write "{\"file_path\":\"$HOME/.codex/config.toml\",\"content\":\"x\"}")" deny "  its config.toml (the reviews) by a file tool: denied"
mkdir -p "$T/lnk"; ln -s "$HOME/.gemini/oauth_creds.json" "$T/lnk/creds"
check "$(cl Read "{\"file_path\":\"$T/lnk/creds\"}")" deny "a link to Antigravity's login: denied (resolved)"

echo "== vendor-hooks on a stand-in HOME"
VHK="$LH/bin/vendor-hooks"
export VENDOR_HOOKS_ROOT="$(dirname "$MODS")"
mkdir -p "$HOME/.claude/rules/sub" "$HOME/me"
printf '# login dir\n@~/me/core.md\n@~/me/private.md\n@~/me/gone.md\n' > "$HOME/.claude/CLAUDE.md"; echo core > "$HOME/me/core.md"; echo p > "$HOME/me/private.md"
echo r1 > "$HOME/.claude/rules/a.md"; echo r2 > "$HOME/.claude/rules/sub/b.md"
ORCA='{"type":"command","command":"orca-hook","timeout":10}'
printf '{"hooks":{"PreToolUse":[{"hooks":[%s]}],"Stop":[{"hooks":[%s]}]}}\n' "$ORCA" "$ORCA" > "$HOME/.codex/hooks.json"
printf '{"orca":{"PreToolUse":[{"matcher":"*","hooks":[%s]}]}}\n' "$ORCA" > "$HOME/.gemini/config/hooks.json"
mkdir -p "$T/orca/codex-accounts/9/home"
# the logins: a Codex seat in a tenant beside its Claude seat, whose CLAUDE.md loads less than the default's
mkdir -p "$HOME/.claude-acct-seat/rules"; printf '@~/me/core.md\n' > "$HOME/.claude-acct-seat/CLAUDE.md"; echo seat > "$HOME/.claude-acct-seat/rules/seat.md"
printf '{"accounts":[{"label":"acct-codex","provider":"codex","home":"~/.codex-work","enabled":false},{"label":"acct-seat","provider":"claude","home":"~/.claude-acct-seat"}]}\n' > "$ACCOUNTS_FILE"
printf '{"acct-tenant":{"repos":["x"],"logins":["acct-codex","acct-seat"]}}\n' > "$ACCOUNTS_FILE.tenants"
printf '{"acct-orca":{"provider":"codex","home":"%s"}}\n' "$T/orca/codex-accounts/9/home" > "$ACCOUNT_ORCA_FILE"
out=$(python3 "$VHK" check); rc=$?
check "$rc" 1 "check before apply: exit 1"
has "$out" "no current entry for secrets_guard, checkpoint, trailer" "  it names each missing entry"
check "$(python3 "$VHK" homes | cut -f1 | sort | uniq -c | tr -s ' ' | tr '\n' ';')" " 1 antigravity; 3 codex;" \
  "homes: ~/.codex, the registry's ~/.codex-work and Orca's read-back Codex home; one Antigravity"
out=$(python3 "$VHK" apply --dry-run)
has "$out" "would change: added secrets_guard, added checkpoint, added trailer" "apply --dry-run says what it would add"
check "$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["hooks"]["PreToolUse"]))' "$HOME/.codex/hooks.json")" 1 "  and writes nothing"
out=$(python3 "$VHK" apply); rc=$?
check "$rc" 0 "apply: exit 0"
has "$out" "3 entries of ours not yet reviewed" "  it says Codex runs none until they are reviewed"
cx() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(" ".join((h["command"].split()[-1].strip("\"").rsplit("/",1)[-1] if "vendor_hook" in h["command"] else h["command"]) + ":" + str(g.get("matcher")) for g in d["hooks"]["PreToolUse"] for h in g["hooks"]))' "$1"; }
check "$(cx "$HOME/.codex/hooks.json")" "orca-hook:None secrets_guard.py: checkpoint.py: trailer:" "Codex: Orca's entry first, ours appended after it, matcher \"\""
check "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["hooks"]["Stop"][0]["hooks"][0]["command"])' "$HOME/.codex/hooks.json")" "orca-hook" "  another event's entries untouched"
check "$(cx "$HOME/.codex-work/hooks.json")" "secrets_guard.py: checkpoint.py: trailer:" "the registry's Codex home: its file made, the entries in it"
check "$(cx "$T/orca/codex-accounts/9/home/hooks.json")" "secrets_guard.py: checkpoint.py: trailer:" "Orca's read-back Codex home: the same"
check "$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(sorted(d), d["regatta"]["enabled"], len(d["regatta"]["PreToolUse"][0]["hooks"]), d["regatta"]["PreToolUse"][0]["matcher"])' "$HOME/.gemini/config/hooks.json")" \
  "['orca', 'regatta'] True 3 *" "Antigravity: our key beside Orca's, three handlers, matcher *"
has "$(cat "$HOME/.codex/AGENTS.md")" "- $HOME/me/core.md" "the Codex pointer names the CLAUDE.md's @ file"
has "$(cat "$HOME/.codex/AGENTS.md")" "- $HOME/.claude/rules/sub/b.md" "  every .md under rules/, a subfolder's included"
case "$(cat "$HOME/.codex/AGENTS.md")" in *gone.md*) check gone absent "  an @ file that is not there is not named";; *) check absent absent "  an @ file that is not there is not named";; esac
has "$(cat "$HOME/.codex/AGENTS.md")" "bulletin.py\" --list" "  and the bulletin, by its command"
check "$(grep -c '^- ' "$HOME/.gemini/GEMINI.md")" 3 "the Antigravity pointer: the same three files (no copy of their text)"
case "$(cat "$HOME/.codex/AGENTS.md")" in *private.md*|*CLAUDE.md*) check named unnamed "  neither a file only the default dir loads nor the CLAUDE.md that names it";; *) check unnamed unnamed "  neither a file only the default dir loads nor the CLAUDE.md that names it";; esac
has "$(cat "$HOME/.codex-work/AGENTS.md")" "- $HOME/.claude-acct-seat/rules/seat.md" "the tenant's Codex home: its Claude seat's rules"
has "$(cat "$HOME/.codex-work/AGENTS.md")" "- $HOME/me/core.md" "  and the seat's shared @ file"
case "$(cat "$HOME/.codex-work/AGENTS.md")" in *"$HOME/.claude/rules"*) check default seat "  not the default dir's rules";; *) check seat seat "  not the default dir's rules";; esac
mkdir -p "$REGATTA_CONFIG/lighthouse"; echo "$HOME/me/private.md" > "$REGATTA_CONFIG/lighthouse/vendor-layer"
has "$(VENDOR_HOOKS_ROOT="$VENDOR_HOOKS_ROOT" python3 "$VHK" apply --dry-run)" "AGENTS.md: would change" "the config key lighthouse/vendor-layer replaces the shared set"
rm -f "$REGATTA_CONFIG/lighthouse/vendor-layer"
case "$(cat "$HOME/.codex/AGENTS.md")" in *core*r1*) check copied pointer "  no file's text copied in";; *) check pointer pointer "  no file's text copied in";; esac
out=$(python3 "$VHK" apply)
check "$(printf '%s\n' "$out" | grep -c 'up to date')" 8 "a second apply: every file up to date"
# a reviewed entry keeps its review: the table Codex keys by position still names ours after a re-apply
printf '[hooks.state."%s:pre_tool_use:1:0"]\ntrusted_hash = "sha256:x"\n' "$HOME/.codex/hooks.json" >> "$HOME/.codex/config.toml"
has "$(python3 "$VHK" check)" "2 not yet reviewed (checkpoint, trailer)" "check counts the entries Codex has no review of"
out=$(python3 "$VHK" check); rc=$?
check "$rc" 0 "check after apply: exit 0 (a review is a note, not a gap)"
has "$out" "ok  $HOME/.gemini/config/hooks.json: 3 entries" "  Antigravity's entries ok"
python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["regatta"]["enabled"]=False; json.dump(d,open(p,"w"))' "$HOME/.gemini/config/hooks.json"
python3 "$VHK" apply > /dev/null
check "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["regatta"]["enabled"])' "$HOME/.gemini/config/hooks.json")" False "an owner's enabled: false survives a re-apply"
has "$(python3 "$VHK" check)" "disabled by its owner" "  and check says so"
python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["hooks"]["PreToolUse"][2]["hooks"][0]["command"]="python3 \"/old/hooks/vendor_hook.py\" codex \"/old/checkpoint.py\""; json.dump(d,open(p,"w"))' "$HOME/.codex/hooks.json"
has "$(python3 "$VHK" check)" "no current entry for checkpoint" "an entry that names another checkout: not current"
has "$(python3 "$VHK" apply)" "changed: rewrote checkpoint" "apply rewrites it in place"
check "$(cx "$HOME/.codex/hooks.json")" "orca-hook:None secrets_guard.py: checkpoint.py: trailer:" "  at the same position (Codex's review keys)"
echo "mine" > "$HOME/.codex-work/AGENTS.md"
out=$(python3 "$VHK" apply); rc=$?
check "$rc" 1 "a pointer file that is not ours: apply exits 1"
has "$out" "$HOME/.codex-work/AGENTS.md: not ours" "  names it"
check "$(cat "$HOME/.codex-work/AGENTS.md")" "mine" "  and leaves it alone"
echo "override" > "$HOME/.codex/AGENTS.override.md"
has "$(python3 "$VHK" check)" "AGENTS.override.md: holds text, so Codex reads it" "an AGENTS.override.md with text: check says it shadows the pointer"
echo "theirs" > "$HOME/.codex/AGENTS.md"
out=$(python3 "$VHK" apply); rc=$?
check "$(cat "$HOME/.codex/AGENTS.md")" "theirs" "a foreign AGENTS.md beside an override: apply never writes it"
has "$out" "$HOME/.codex/AGENTS.md: not ours" "  and names it"
python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); g=d["hooks"]["PreToolUse"]; g.insert(0, {"matcher":"", "hooks":[{"type":"command","command":"python3 \"/old/hooks/vendor_hook.py\" codex \"/old/gone_guard.py\""}]}); json.dump(d,open(p,"w"))' "$HOME/.codex-work/hooks.json"
python3 "$VHK" apply > /dev/null
check "$(python3 -c 'import json,sys; g=json.load(open(sys.argv[1]))["hooks"]["PreToolUse"]; print(len(g), g[0]["hooks"])' "$HOME/.codex-work/hooks.json")" "4 []" \
  "an entry of ours no longer wired: dropped, its group kept empty (no later index shifts)"
cmd=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["regatta"]["PreToolUse"][0]["hooks"][0]["command"])' "$HOME/.gemini/config/hooks.json")
moved=${cmd//vendor_hook.py/vendor_hook_moved.py}
check "$(echo '{}' | sh -c "$moved" 2>"$T/moved.err"; echo " rc=$?")" "{} rc=0" "an entry whose adapter moved: agy gets its carry-on, exit 0 (not python's exit 2, a deny)"
has "$(cat "$T/moved.err")" "is gone, so no guard ran" "  one line on stderr says so"
check "$(printf '{"toolCall":{"name":"run_command","args":{"CommandLine":"cat %s/_secrets/app.env"}},"workspacePaths":["%s"]}' "$SGV" "$WT" | sh -c "$cmd" | python3 -c 'import json,sys; print(json.load(sys.stdin)["decision"])')" deny "  and the entry as written still runs the guard"
echo '{not json' > "$HOME/.gemini/config/hooks.json"
has "$(python3 "$VHK" apply)" "does not read" "a hooks file that does not parse: not touched"
check "$(cat "$HOME/.gemini/config/hooks.json")" "{not json" "  byte for byte"

echo
if [ "$fails" -eq 0 ]; then echo "parity: all passed"; else echo "parity: $fails failed"; fi
[ "$fails" -eq 0 ]
