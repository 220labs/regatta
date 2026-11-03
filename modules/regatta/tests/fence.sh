#!/usr/bin/env bash
# Tests for hooks/fence.py and hooks/agy_hook.py (the council isolation design's S1): the hook's allowlist (both
# agy shapes), the proxy's judgement, the Codex feature gate and Claude's MCP gate read from stand-in listings,
# the F5 record from each CLI's log shapes (the S0 probes'), what may not leave, the arm's environment, the
# scratch homes, and F7 — the proxy withdrawing the login at the first vendor request, the first tool call's
# read, the scan of what an arm leaves, Claude's login on a pipe; on macOS also the seatbelt itself — the profile
# and its probe, a read of ~ and a write to a read-only path refused under wrap(), the per-run keychain holding
# agy's item alone and withdrawn, and our hook run under the profile. No model is called and nothing under the real HOME is read: HOME is a scratch folder, and the
# keychain cases make their own under it. Run by tests/check.sh.
#   bash modules/regatta/tests/fence.sh
set -u
M="$(cd "$(dirname "$0")/.." && pwd)"
for v in $(env | sed -n 's/^\(CLAUDE[A-Za-z0-9_]*\)=.*/\1/p; s/^\(CODEX[A-Za-z0-9_]*\)=.*/\1/p'); do unset "$v"; done
unset SSH_AUTH_SOCK ANTHROPIC_API_KEY REGATTA_UNATTENDED AUTOFINISH_CALLER_UNATTENDED   # the holders stand-in is an attended suite's
T=$(mktemp -d "${TMPDIR:-/tmp}/fence-test-XXXXXX"); T=$(cd "$T" && pwd -P)
export HOME="$T/home"; mkdir -p "$HOME"
HD=$HOME   # the suite's HOME, by a name the publish gate reads as no home path
# F4's start probe refuses while any process of this user holds a credential-named variable (finding 1); a
# session that runs this suite holds its own: the stand-in names none, the live read has its own cases
: > "$T/holders-none"; export REGATTA_FENCE_HOLDERS="$T/holders-none"
cleanup() {
  [ -f "$HD/Library/Keychains/login.keychain-db" ] && /usr/bin/security delete-keychain "$HD/Library/Keychains/login.keychain-db" 2>/dev/null
  chmod -R u+w "$T" 2>/dev/null; rm -rf "$T"
}
trap cleanup EXIT
fails=0
check() { if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3: expected [$2] got [$1]"; fails=$((fails+1)); fi; }
F() { python3 - "$M/hooks" "$@" <<PY
import sys; sys.path.insert(0, sys.argv[1]); import fence
$(cat)
PY
}
FENCE=""; [ "$(uname)" = Darwin ] && [ -x /usr/bin/sandbox-exec ] && FENCE=1

echo "agy_hook: the allowlist of step names"
H() { printf '%s' "$1" | python3 -I "$M/hooks/agy_hook.py"; }
check "$(H '{"tool_name": "run_command", "tool_input": {}}')" '{"decision": "allow"}' "run_command allowed"
check "$(H '{"tool_name": "read_file"}')" '{"decision": "allow"}' "  read_file too: the hook's name for view_file (H5)"
check "$(H '{"tool_name": "browser_click_element"}' | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["decision"], d["reason"])')" \
  "deny not in the council arm's tool set" "a browser tool denied, with the reason F5 reads back"
for x in call_mcp_tool list_plugin_accounts send_message invoke_subagent generate_image schedule; do
  check "$(H "{\"tool_name\": \"$x\"}" | cut -c1-21)" '{"decision": "deny", ' "  $x denied"
done
check "$(H 'not json' | cut -c1-21)/$(H '{"tool": "run_command"}' | cut -c1-21)" '{"decision": "deny", /{"decision": "deny", ' "  no JSON, or no tool_name: denied"
check "$(H '{"toolCall": {"name": "run_command", "args": {"CommandLine": "ls"}}, "modelName": "m"}')/$(H '{"toolCall": {"name": "browser_click_element"}}' | cut -c1-21)" \
  '{"decision": "allow"}/{"decision": "deny", ' "  agy 1.4.11's shape, toolCall.name (record Q3b): run_command allowed, a browser tool denied"
check "$(H '{"toolCall": "run_command"}' | cut -c1-21)" '{"decision": "deny", ' "  a toolCall that is no object: denied"
check "$(H '{"tool_name": "search_web"}' | cut -c1-21)/$(H '{"tool_name": "read_url_content"}' | cut -c1-21)/$(printf '%s' '{"tool_name": "search_web"}' | python3 -I "$M/hooks/agy_hook.py" --research)" \
  '{"decision": "deny", /{"decision": "deny", /{"decision": "allow"}' "  the web tools (Google's side, past the proxy) only with --research, as the other arms' (round 6's second review)"

echo "the proxy's judgement (no DNS: address literals)"
check "$(F <<'PY'
p = fence.Proxy(["api.example.test"])
print(p.judge("example.com", 443)[1], "|", p.judge("1.1.1.1", 443)[1])
r = fence.Proxy([], research=True)
print(r.judge("1.1.1.1", 443)[1], "|", r.judge("1.1.1.1", 80)[1], "|", r.judge("1.1.1.1", 22)[1])
# made-up addresses, each built so no source line holds one: a private range, the CGNAT range, link-local, ULA
for h in ("127.0.0.1", ".".join(["10", "20", "30", "40"]), ".".join(["100", "64", "1", "2"]), ".".join(["169", "254", "1", "1"]), "::1",
          "::ffff:127.0.0.1", "fd" + "00::1"):
    print(h.replace(".", "_").replace(":", "-"), "->", (r.judge(h, 443)[1] or "").split(", ")[-1])
PY
)" "not the CLI's vendor host and research is off | not the CLI's vendor host and research is off
None | None | port 22
127_0_0_1 -> not global
10_20_30_40 -> not global
100_64_1_2 -> not global
169_254_1_1 -> not global
--1 -> not global
--ffff-127_0_0_1 -> not global
fd00--1 -> not global" \
  "research off: only the CLI's own hosts; on: any global address on 443 or 80; loopback, the LAN, the tailnet, link-local and ULA never"
check "$(F <<'PY'
import socket, json
p = fence.Proxy([], research=True)
port = p.start()
def ask(req):
    s = socket.create_connection(("127.0.0.1", port)); s.sendall(req); out = s.recv(400).decode(); s.close(); return out.split("\r\n")[0]
lan = ".".join(["10", "20", "30", "40"]).encode()
print(ask(b"CONNECT 127.0.0.1:443 HTTP/1.1\r\n\r\n"), "|", ask(b"GET http://" + lan + b"/ HTTP/1.1\r\n\r\n"), "|", ask(b"BREW x HTTP/1.1\r\n\r\n"))
p.stop()
print([(d["host"].replace(".", "_"), d["ok"]) for d in p.decisions])
PY
)" "HTTP/1.1 403 Forbidden | HTTP/1.1 403 Forbidden | HTTP/1.1 400 Bad Request
[('127_0_0_1', False), ('10_20_30_40', False)]" "  end to end: CONNECT to loopback and plain http to the LAN refused 403, a request it cannot read 400, each decision noted"

echo "the gates, from stand-in listings"
mkdir -p "$T/bin"
cat > "$T/bin/codex" <<'SH'
#!/bin/sh
case "$1 $2" in
  "features list") cat "$STUB_FEATURES";;
esac
SH
cat > "$T/bin/claude" <<'SH'
#!/bin/sh
printf 'Checking MCP server health…\n\nclaude.ai Claude Docs: https://api.anthropic.com/v1/pages/mcp - ✔ Connected\n'
[ -n "${STUB_MCP:-}" ] && printf '%s: https://mcp.example.test/x - ✔ Connected\n' "$STUB_MCP"
[ -n "${STUB_MCP_LINE:-}" ] && printf '%s\n' "$STUB_MCP_LINE"
exit 0
SH
chmod +x "$T/bin/codex" "$T/bin/claude"
G() { F "$@"; }
check "$(G <<'PY'
print(hasattr(fence, "codex_plugins"), hasattr(fence, "CODEX_PLUGINS_VENDOR"))
PY
)" "False False" "no \`codex plugin list\` gate: the account's connectors are fenced by F7, the login off the disk (the owner, 2026-10-30)"
python3 - "$M/hooks" "$T/features.txt" <<'PY'
import sys; sys.path.insert(0, sys.argv[1]); import fence
with open(sys.argv[2], "w") as f:
    for n in sorted(fence.CODEX_FEATURES):
        f.write("%-40s stable             true\n" % n)
    f.write("%-40s removed            true\n" % "sqlite")
    f.write("%-40s stable             false\n" % "memories")
PY
check "$(STUB_FEATURES="$T/features.txt" G <<PY
import os; print(fence.codex_features(dict(os.environ), "$T/bin/codex"))
PY
)" "(None, None)" "codex_features: every feature on is judged (a removed one is no feature)"
{ cat "$T/features.txt"; printf '%-40s stable             true\n' remote_control; } > "$T/features2.txt"
check "$(STUB_FEATURES="$T/features2.txt" G <<PY
import os; n, why = fence.codex_features(dict(os.environ), "$T/bin/codex"); print(n, "refused" if why else "")
PY
)" "['remote_control'] refused" "  a feature on that no one judged refuses the arm, named"
: > "$T/empty.txt"
check "$(STUB_FEATURES="$T/empty.txt" G <<PY
import os; print(fence.codex_features(dict(os.environ), "$T/bin/codex")[0])
PY
)" "None" "  an empty list: not the table this reads"
check "$(G <<'PY'
f = fence.codex_flags()
print("shell_tool" in f, "code_mode_host" in f, "unified_exec" in f, "memories" in f, "apps" in f, "plugins" in f, "multi_agent" in f)
PY
)" "False False False True True True True" "codex_flags: hygiene — the connectors, sub-agents and memories off, the shell and code mode never"
check "$(G <<PY
import os; print(fence.claude_mcp(dict(os.environ), "$T/bin/claude"))
PY
)" "([], None)" "claude_mcp: Anthropic's own docs connector is no connector to fence"
check "$(STUB_MCP=Gmail G <<PY
import os; print(fence.claude_mcp(dict(os.environ), "$T/bin/claude"))
PY
)" "(['Gmail'], None)" "  an account's Gmail connector is"
check "$(STUB_MCP_LINE='Gmail [needs sign-in] ✗' G <<PY
import os; s, why = fence.claude_mcp(dict(os.environ), "$T/bin/claude"); print(s, "refused" if why and "cannot read" in why else why)
PY
)" "None refused" "  a line it cannot read refuses the arm, never reads as no server (the fourth landing review, finding 8)"
check "$(STUB_MCP_LINE='No MCP servers configured. Use `claude mcp add` to add a server.' G <<PY
import os; print(fence.claude_mcp(dict(os.environ), "$T/bin/claude"))
PY
)" "([], None)" "  the CLI's own line for none is no server"

echo "F5: the record, from each CLI's own log (the shapes S0's probes read)"
L="$T/logs"; mkdir -p "$L"
cat > "$L/claude.jsonl" <<'J'
{"type":"system","subtype":"init","tools":["Bash","Read"],"mcp_servers":[]}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"ls ."}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":"a.txt"}}]}}
{"type":"result","is_error":false,"result":"PAPER","total_cost_usd":0.1}
J
check "$(F <<PY
r = fence.record("claude", "$L/claude.jsonl", ["Bash", "Read"]); print(r["readable"], r["tools"], r["commands"], r["bad"], r["result"]["result"])
PY
)" "True {'Bash': 1, 'Read': 1} ['Bash: ls .', 'Read: a.txt'] [] PAPER" "Claude: tools counted, commands kept, nothing bad"
sed 's/"name":"Read"/"name":"mcp__gmail__send"/; s/"mcp_servers":\[\]/"mcp_servers":[{"name":"gmail"}]/' "$L/claude.jsonl" > "$L/claude-bad.jsonl"
check "$(F <<PY
print(len(fence.record("claude", "$L/claude-bad.jsonl", ["Bash", "Read"])["bad"]))
PY
)" "2" "  an MCP server at init and a tool the start did not allow: both fail the arm"
cat > "$L/codex.jsonl" <<'J'
{"type":"thread.started","thread_id":"t1"}
{"type":"item.started","item":{"id":"c1","type":"command_execution","command":"/bin/zsh -lc 'ls'"}}
{"type":"item.completed","item":{"id":"c1","type":"command_execution","command":"/bin/zsh -lc 'ls'","exit_code":0}}
{"type":"item.completed","item":{"id":"m1","type":"agent_message","text":"PAPER"}}
[1, 2]
{"type":"turn.completed","usage":{"input_tokens":1}}
J
check "$(F <<PY
r = fence.record("codex", "$L/codex.jsonl"); print(r["tools"], r["commands"], r["bad"])
PY
)" "{'command_execution': 1, 'agent_message': 1} [\"/bin/zsh -lc 'ls'\"] []" \
  "Codex: a command counted once (started, then completed)"
printf '{"type":"item.completed","item":{"id":"x","type":"mcp_tool_call"}}\n{"type":"item.completed","item":{"id":"y","type":"collab_tool_call"}}\n' > "$L/codex-bad.jsonl"
check "$(F <<PY
print(len(fence.record("codex", "$L/codex-bad.jsonl")["bad"]))
PY
)" "2" "  a connector call and a sub-agent: each fails the arm with its tools on"
cat > "$L/agy.jsonl" <<'J'
{"event":"init","init":{"model":"m","tools":["run_command","view_file"]}}
{"event":"step_update","step_update":{"step_index":1,"state":"ACTIVE","step_type":"tool","tool_name":"read_file"}}
{"event":"step_update","step_update":{"step_index":1,"state":"DONE","step_type":"tool","tool_name":"read_file","tool_info":{"parameters":"{'Path': 'a'}"}}}
{"event":"step_update","step_update":{"step_index":2,"state":"ERROR","step_type":"tool","tool_name":"browser_get_dom","tool_info":{"error":"{'type': 'TOOL_ERROR', 'message': \"tool call denied by pre-tool hook: not in the council arm's tool set\"}"}}}
{"event":"step_update","step_update":{"step_index":3,"state":"DONE","step_type":"tool","tool_name":"run_command","tool_info":{"parameters":"{'CommandLine': 'ls .'}"}}}
{"event":"result","result":{"status":"SUCCESS","response":"PAPER"}}
J
check "$(F <<PY
r = fence.record("agy", "$L/agy.jsonl"); print(r["tools"], r["denied"], r["bad"], r["commands"], r["result"]["response"])
PY
)" "{'read_file': 1, 'browser_get_dom': 1, 'run_command': 1} ['browser_get_dom'] [] [\"{'CommandLine': 'ls .'}\"] PAPER" \
  "agy: our hook's denial read back by its reason; the allowed steps ran"
printf '%s\n' '{"event":"step_update","step_update":{"step_index":1,"state":"DONE","step_type":"tool","tool_name":"search_web"}}' > "$L/agy-web.jsonl"
printf '%s\n' '{"type":"item.completed","item":{"id":"w","type":"web_search"}}' > "$L/codex-web.jsonl"
check "$(F <<PY
print(len(fence.record("agy", "$L/agy-web.jsonl")["bad"]), len(fence.record("agy", "$L/agy-web.jsonl", research=True)["bad"]),
      len(fence.record("codex", "$L/codex-web.jsonl")["bad"]), len(fence.record("codex", "$L/codex-web.jsonl", research=True)["bad"]))
PY
)" "1 0 1 0" "  a web step that ran with research off fails the arm (agy's search_web the hook never saw, Codex's web_search item); with research on it is allowed (round 6's third review)"
sed 's/"state":"ERROR","step_type":"tool","tool_name":"browser_get_dom","tool_info":{"error":"[^}]*}"}/"state":"ERROR","step_type":"tool","tool_name":"browser_get_dom","tool_info":{"error":"timeout"}/' "$L/agy.jsonl" > "$L/agy-err.jsonl"
sed 's/"state":"ERROR","step_type":"tool","tool_name":"browser_get_dom","tool_info":{"error":"[^}]*}"}/"state":"DONE","step_type":"tool","tool_name":"call_mcp_tool"/' "$L/agy.jsonl" > "$L/agy-ran.jsonl"
check "$(F <<PY
for f in ("agy-err", "agy-ran"):
    print(fence.record("agy", "$L/%s.jsonl" % f)["bad"])
PY
)" "[\"agy's step browser_get_dom (ERROR) is outside our hook's allowlist and the hook did not deny it\"]
[\"agy's step call_mcp_tool (DONE) is outside our hook's allowlist and the hook did not deny it\"]" \
  "  a denied-list step ending in another error, or one that ran: the hook did not deny it, the arm fails"
cat > "$L/agy-echo.jsonl" <<'J'
{"event":"step_update","step_update":{"step_index":10,"state":"DONE","step_type":"tool","tool_name":"run_command","tool_info":{"parameters":"{'CommandLine': 'b'}"}}}
{"event":"step_update","step_update":{"step_index":2,"state":"DONE","step_type":"tool","tool_name":"run_command","tool_info":{"parameters":"{'CommandLine': 'a'}"}}}
{"event":"step_update","step_update":{"step_index":3,"state":"ERROR","step_type":"tool","tool_name":"call_mcp_tool","tool_info":{"error":"fetch failed for x?q=denied by pre-tool hook: not in the council arm's tool set"}}}
{"event":"step_update","step_update":{"step_index":4,"state":"ERROR","step_type":"tool","tool_name":"browser_get_dom","tool_info":{"error":{"type":"TOOL_ERROR","message":"tool call denied by pre-tool hook: not in the council arm's tool set"}}}}
J
check "$(F <<PY
r = fence.record("agy", "$L/agy-echo.jsonl"); print(r["denied"], r["bad"], r["commands"])
PY
)" "['browser_get_dom'] [\"agy's step call_mcp_tool (ERROR) is outside our hook's allowlist and the hook did not deny it\"] [\"{'CommandLine': 'a'}\", \"{'CommandLine': 'b'}\"]" \
  "  the seventh review: a denial is the hook's only when its message is exactly the hook's (agy's dict read whole, an echo of the phrase fails the arm), and steps keep the order they ran (2 before 10)"
check "$(F <<PY
P = fence.Proxy(["example.com"], research=True); P.on_vendor = None
print(P.judge("a" * 64 + ".com", 443)[0], P.judge("a" * 64 + ".com", 443)[1].startswith("resolve:"))
PY
)" "None True" "  the proxy: a 64-byte label refused as unresolvable, never a dead handler (the seventh review)"
check "$(F <<'PY'
import ipaddress as i
print([str(fence.embedded_v4(i.ip_address(a))) for a in ("64:ff9b::7f00:1", "2002:7f00:1::1", "64:ff9b:1::a00:1", "64:ff9b::808:808", "2606:4700::1111", "1.1.1.1")])
PY
)" "['127.0.0.1', '127.0.0.1', '0.0.0.0', '8.8.8.8', 'None', 'None']" \
  "  the IPv4 a NAT64 or 6to4 address carries is judged too: loopback's refused, a public one passes (the seventh review)"
printf '{"event":"step_update","step_update":{"step_index":9,"state":"ACTIVE","step_type":"tool","tool_name":"call_mcp_tool"}}\n' > "$L/agy-active.jsonl"
check "$(F <<PY
print(fence.record("agy", "$L/agy-active.jsonl")["bad"])
PY
)" "[\"agy's step call_mcp_tool (ACTIVE) is outside our hook's allowlist and the hook did not deny it\"]" \
  "  one still running when the log ended (S5's review): the arm fails"
cat > "$L/claude-refused.py" <<'PY'
import json, sys
def log(path, name, text, err=True):
    with open(path, "w") as f:
        f.write(json.dumps({"type": "assistant", "message": {"content": [{"type": "tool_use", "id": "a", "name": name, "input": {}}]}}) + "\n")
        f.write(json.dumps({"type": "user", "message": {"content": [{"type": "tool_result", "tool_use_id": "a", "is_error": err, "content": text}]}}) + "\n")
d = sys.argv[1]
cases = [("Agent", "<tool_use_error>Error: No such tool available: Agent. Agent is disabled for this session</tool_use_error>", True),
         ("Task", "<tool_use_error>Error: No such tool available: Task</tool_use_error>", True),
         ("Agent", "a sub-agent ran and said: No such tool available: Agent.", True),
         ("Agent", "<tool_use_error>Error: No such tool available: Agent. Agent is disabled</tool_use_error>", False),
         ("TaskX", "<tool_use_error>Error: No such tool available: Task</tool_use_error>", True)]
for i, c in enumerate(cases):
    log("%s/c%d.jsonl" % (d, i), *c)
PY
python3 "$L/claude-refused.py" "$L"
check "$(F <<PY
print([(len(r["denied"]), len(r["bad"])) for r in (fence.record("claude", "$L/c%d.jsonl" % i, ["Bash"]) for i in range(5))])
PY
)" "[(1, 0), (1, 0), (0, 1), (0, 1), (0, 1)]" \
  "Claude: a call outside --tools claude refused itself is a denial (its own error, naming that tool); any other result runs"
check "$(F <<PY
for p in ("$L/none.jsonl", "/dev/null"):
    r = fence.record("claude", p, []); print(r["readable"], len(r["bad"]))
PY
)" "False 1
False 1" "  no log, or an empty one: unreadable, the arm fails"

check "$(F <<PY
import json
p = "$T/agy-odd.jsonl"
open(p, "w").write("\\n".join(json.dumps(e) for e in [
    {"event": "step_update", "step_update": {"step_index": 1, "step_type": "agent_response", "state": "DONE"}},
    {"event": "step_update", "step_update": {"step_index": 2, "step_type": "browser_subagent", "state": "DONE"}},
    {"event": "result", "result": "PAPER"}]) + "\\n")
r = fence.record("agy", p)
print([b for b in r["bad"] if "step type" in b], fence.tool_event("agy", {"event": "step_update", "step_update": {"step_type": "browser_subagent"}}),
      fence.tool_event("agy", {"event": "step_update", "step_update": {"step_type": "agent_response"}}))
PY
)" "[\"agy's step type 'browser_subagent' is none the probes saw: F5 cannot judge it\"] True False" \
  "agy: a step of a type no probe saw fails the arm, and counts as a tool call for F7 (the fourth landing review's S3)"
echo "what may not leave"
mkdir -p "$T/tree/_secrets" "$T/tree/docs"; touch "$T/tree/.env" "$T/tree/.env.example" "$T/tree/docs/.env.local" "$T/tree/_secrets/k" "$T/tree/ok.md"
check "$(F <<PY
print(sorted(p for p, _ in fence.leave_paths("$T/tree")))
print(fence.leave_text("see " + "sk-" + "ant-oat01-ABCDEFGHIJKLMNOP and " + "ya29" + ".abcdefghijklmnopqrstuv"), fence.leave_text("a token = os.environ.get(x)"))
PY
)" "['.env', '_secrets', 'docs/.env.local']
['a sk-ant… token', 'a ya29.… token'] []" "a vault folder and env files, an example env file not; a paper's token shapes by kind (the vendor's prefix alone: round 6), code not"
if [ -f "$M/../lighthouse/hooks/secrets_guard.py" ]; then
  check "$(grep -c '^FOLDERS = ("_secrets", "_contacts")$' "$M/../lighthouse/hooks/secrets_guard.py")/$(F <<'PY'
print(fence.VAULT_FOLDERS)
PY
)" "1/('_secrets', '_contacts')" "  the vault folders are lighthouse's secrets guard's own"
fi

echo "the arm's environment: an allowlist"
check "$(SSH_AUTH_SOCK=/x CLAUDE_CODE_OAUTH_TOKEN=t ORCA_PANE_KEY=p CLAUDECODE=1 CLAUDE_CODE_MESSAGING_SOCKET=/m GH_TOKEN=g F <<'PY'
e = fence.arm_env("claude", "/b", 4321, {"CLAUDE_CONFIG_DIR": "/b/cfg"}, path_first="/opt/cli")
print(sorted(e))
print(e["HOME"], e["TMPDIR"], e["https_proxy"], e["HTTPS_PROXY"], e["PATH"].split(":")[0], e["CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"])
PY
)" "['ALL_PROXY', 'CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC', 'CLAUDE_CODE_TMPDIR', 'CLAUDE_CONFIG_DIR', 'DISABLE_AUTOUPDATER', 'HOME', 'HTTPS_PROXY', 'HTTP_PROXY', 'LANG', 'LOGNAME', 'NO_PROXY', 'PATH', 'REGATTA_COUNCIL_ARM', 'SHELL', 'TMPDIR', 'USER', 'all_proxy', 'http_proxy', 'https_proxy', 'no_proxy']
/b/home /b/tmp http://127.0.0.1:4321 http://127.0.0.1:4321 /opt/cli 1" \
  "nothing of the caller's but its names: no ssh agent, login token, Orca pane, nesting mark, messaging socket or GitHub token"

echo "the scratch homes"
# synthetic logins, each value an argument of its own (the publish gate reads a key beside its value as a credential)
mkdir -p "$HD/.codex" "$HD/.claude"; printf '{"tokens": {"access_token": "%s", "account_id": "acct-1"}}' STANDIN-CODEX-ACCESS-01 > "$HD/.codex/auth.json"
check "$(F <<PY
import os, stat
env, ro, cred = fence.arm_home("codex", "$T/box1")
a = env["CODEX_HOME"] + "/auth.json"
print(sorted(os.listdir(env["CODEX_HOME"])), oct(stat.S_IMODE(os.stat(a).st_mode)), [os.path.basename(x) for x in ro])
print(cred.files == [a], len(cred.secrets), cred.present())
PY
)" "['auth.json'] 0o600 ['config.toml', 'AGENTS.md', 'hooks.json', 'auth.json']
True 1 ['auth.json']" "Codex: auth.json alone, 0600; its config and auth.json read-only to the arm (S5); its Credential names the file and holds one secret"
printf '{"mcpOAuth": {}}' > "$HD/.claude/.credentials.json"
check "$(F <<PY 2>&1 | tail -1
fence.arm_home("claude", "$T/box2")
PY
)" "fence.FenceError: no Claude login to copy: $([ "$(uname)" = Darwin ] && printf '%s' "the keychain item 'Claude Code-credentials' is not in this login's keychain (security exit 44)" || printf '%s' "the keychain item 'Claude Code-credentials' did not read (FileNotFoundError)"); $HD/.claude/.credentials.json holds no sign-in" \
  "Claude: a credentials file holding only an MCP server's OAuth is no login (and the scratch HOME's keychain has none)"
printf '{"claudeAiOauth": {"accessToken": "%s", "refreshToken": "%s", "expiresAt": %s}, "mcpOAuth": {}}' \
  STANDIN-CLAUDE-ACCESS-01 STANDIN-CLAUDE-REFRESH-1 "$(( ($(date +%s) + 7200) * 1000 ))" > "$HD/.claude/.credentials.json"
printf '{"oauthAccount": {"emailAddress": "sam@example.com"}, "projects": {"/x": {}}, "userID": "u"}' > "$HD/.claude.json"
check "$(F <<PY
import os, json, time
env, ro, cred = fence.arm_home("claude", "$T/box3", until=time.time() + 1200)
d = env["CLAUDE_CONFIG_DIR"]
print(sorted(os.listdir(d)), json.load(open(d + "/.claude.json")), [os.path.basename(x) for x in ro])
var, fd = cred.open_pipe()
print(var, env.get(var), os.read(fd, 100).decode(), os.read(fd, 100), cred.files, len(cred.secrets), sorted(env))
PY
)" "['.claude.json'] {'oauthAccount': {'emailAddress': 'sam@example.com'}} ['settings.json', 'settings.local.json', 'CLAUDE.md', '.mcp.json']
CLAUDE_CODE_OAUTH_TOKEN_FILE_DESCRIPTOR None STANDIN-CLAUDE-ACCESS-01 b'' [] 2 ['CLAUDE_CONFIG_DIR']" \
  "  no login in the box (F7): .claude.json holding oauthAccount alone; the access token alone on a pipe, drained once; both tokens scanned for"
check "$(F <<PY 2>&1 | tail -1 | sed 's/expires at [0-9:]*, before the run can end ([0-9:]*)/expires at T, before the run can end (T)/'
import time
fence.arm_home("claude", "$T/box3b", until=time.time() + 7200)
PY
)" "fence.FenceError: the Claude login's access token expires at T, before the run can end (T): the arm holds no refresh token and its proxy no refresh host; a session on that login refreshes it" \
  "  a token that expires before the run can end refuses the arm (it holds no refresh token, its proxy no refresh host)"
check "$(F <<PY
import os
# stand-ins of 16 characters or more, as arm_home asks for a login F7 can scan; written in two parts (the publish gate)
for tok in ({"CLAUDE_CODE_OAUTH_TOKEN": "t-oauth" + "-stand-in-01"}, {"ANTHROPIC_API_KEY": "k-api" + "-stand-in-0001", "CLAUDE_CODE_OAUTH_TOKEN": "t"}):
    env, ro, cred = fence.arm_home("claude", "$T/box4-%d" % len(tok), token_env=tok)
    var, fd = cred.open_pipe()
    print(sorted(os.listdir(env["CLAUDE_CONFIG_DIR"])), sorted(env), var, os.read(fd, 50).decode())
PY
)" "['.claude.json'] ['CLAUDE_CONFIG_DIR'] CLAUDE_CODE_OAUTH_TOKEN_FILE_DESCRIPTOR t-oauth-stand-in-01
['.claude.json'] ['CLAUDE_CONFIG_DIR'] CLAUDE_CODE_API_KEY_FILE_DESCRIPTOR k-api-stand-in-0001" \
  "  the caller's own token (no --claude-config) on the pipe too, never in the arm's environment; an API key on Claude's API-key pipe"

echo "F7: the login withdrawn, read at the first tool call, looked for in what an arm leaves"
check "$(F <<'PY'
import json, base64
s = fence.secret_strings
print(len(s(json.dumps({"tokens": {"access_token": "A" * 20, "refresh_token": "R" * 20, "account_id": "u" * 30}, "last_refresh": "2026-10-30T00:00:00Z"}))),
      len(s(b'{"claudeAiOauth": {"accessToken": "' + b"a" * 20 + b'", "expiresAt": 1, "scopes": ["user:inference"]}}')),
      len(s("go-keyring-base64:" + base64.b64encode(json.dumps({"refresh_token": "z" * 20, "id_token_email": "sam" + "@" + "example.com"}).encode()).decode())),
      len(s("STAND-IN-AGY-ITEM")), s("short"), len(s(json.dumps({"api_key": "owner" + "@" + "example.com.au"}))))
PY
)" "2 1 1 1 [] 0" "secret_strings: values under a token, secret, key or password; a keyring's base64 JSON; a blob that is no JSON whole; never an id, an expiry, an address or a short value"
BH=box/home   # an arm's scratch HOME, by a name the publish gate reads as no home path
mkdir -p "$T/f7/arm/$BH/.codex" "$T/f7/arm/box/copy"
check "$(F <<PY
import os
d = "$T/f7/arm"; a = os.path.join(d, "box", "home", ".codex", "auth.json"); S = "SECRET-" + "abcdefghij" * 6
open(a, "w").write('{"tokens": {"access_token": "%s"}}' % S)
c = fence.Credential("codex", files=[a], secrets=[S])
print(c.present(), c.scan([d], own=False), c.scan([d]))
open(d + "/box/copy/note.md", "w").write("a cut copy: " + S[20:60])
open(d + "/log.jsonl", "w").write("nothing of it")
w = c.withdraw()
print(w["ok"], w["left"], c.present(), c.scan([d]), c.in_text("x" + S[33:57] + "x"), c.in_text("nothing"))
PY
)" "['auth.json'] [] ['$BH/.codex/auth.json']
True [] [] ['box/copy/note.md'] True False" \
  "Credential: withdraw() unlinks the login and reads it back; scan() names the files holding it, a cut copy by its windows, never what matched"
check "$(F <<'PY'
t = fence.tool_event
print(t("claude", {"type": "assistant", "message": {"content": [{"type": "text"}]}}),
      t("claude", {"type": "assistant", "message": {"content": [{"type": "tool_use", "name": "Bash"}]}}),
      t("codex", {"type": "item.started", "item": {"type": "command_execution"}}), t("codex", {"type": "item.completed", "item": {"type": "agent_message"}}),
      t("agy", {"event": "step_update", "step_update": {"step_type": "tool"}}), t("agy", {"event": "step_update", "step_update": {"step_type": "agent_response"}}))
PY
)" "False True True False True False" "tool_event: Claude's tool_use, a Codex command, an agy tool step — never a reply"
check "$(F <<PY
import json, os, time
tool = json.dumps({"type": "assistant", "message": {"content": [{"type": "tool_use", "name": "Bash"}]}}) + "\n"
out = []
for n, withdraw in (("1", False), ("2", True)):
    log, a = "$T/f7/ft%s.jsonl" % n, "$T/f7/ft%s.json" % n
    open(a, "w").write("x")
    c = fence.Credential("codex", files=[a])
    ft = fence.FirstTool("claude", log, c, poll=0.02)
    time.sleep(0.1)
    with open(log, "a") as f:
        f.write(json.dumps({"type": "system", "subtype": "init"}) + "\n")
    time.sleep(0.1)
    seen0 = ft.found
    if withdraw:
        c.withdraw()
    with open(log, "a") as f:
        f.write(tool)
    time.sleep(0.3)
    ft.stop()
    out.append((seen0, ft.found))
log, a = "$T/f7/ft3.jsonl", "$T/f7/ft3.json"
open(a, "w").write("x"); open(log, "w").write(tool)
ft = fence.FirstTool("claude", "$T/f7/none.jsonl", fence.Credential("codex", files=[a]), poll=10)
ft.log = log
out.append((ft.stop().found, ft.late))
print(out, fence.FirstTool("codex", None, fence.Credential("codex")).stop().found)
PY
)" "[(None, ['ft1.json']), (None, []), (['ft3.json'], True)] None" \
  "FirstTool: nothing before the first tool call; then what of the login was on disk — the file, or nothing once withdrawn; a call it had not reached read late"
check "$(F <<PY
import os, types
d = "$T/f7/v"; os.makedirs(d + "/box", exist_ok=True); S = "SECRET-" + "abcdefghij" * 6
ns = lambda **k: types.SimpleNamespace(**dict({"found": None, "at": None, "late": False}, **k))
v = lambda cred, first, **k: [b.split(":")[0] for b in fence.f7(cred, first, roots=[d], **k)[1]]
c = fence.Credential("codex", files=[d + "/box/auth.json"], secrets=[S])
print(v(c, ns(found=[])))
open(d + "/box/auth.json", "w").write(S)
print(v(c, ns()))
c.withdraw()
print(v(c, ns(found=[])), v(c, ns(found=["auth.json"])))
open(d + "/box/auth.json", "w").write(S)
print(v(c, ns(found=[])))
os.unlink(d + "/box/auth.json")
print(v(c, ns(found=[]), text="paper " + S))
c2 = fence.Credential("codex", files=[d + "/gone"], secrets=[S]); c2.withdrawn = {"ok": False, "left": ["auth.json"], "why": "EPERM"}
print(v(c2, ns(found=[])))
k = fence.Credential("claude", files=[d + "/box/kept"], secrets=[S], keep="an env token"); open(d + "/box/kept", "w").write(S)
print(v(k, None), fence.f7(k, None, roots=[d])[0])
PY
)" "['the login was never withdrawn, yet the CLI called a tool']
[]
[] ['the login was on disk at the first tool call']
[\"the login's strings are in 1 file(s) the arm left\"]
[\"the paper holds the login's strings\"]
[\"the login's withdrawal left auth.json\"]
[] {'kept': 'an env token', 'files_holding_it': 0}" \
  "f7(): a tool call with no withdrawal, the login on disk at it, a file or a paper holding it, a withdrawal that left it — each fails the arm; a login still where it was put (never withdrawn, or kept) is not counted in its own files"
check "$(F <<PY
import os
d = "$T/f7/s"; os.makedirs(d, exist_ok=True); S = "SECRET-" + "klmnopqrst" * 6
open(d + "/cli.jsonl", "w").write('{"text": "' + S + ' and ' + S[30:60] + '"}\n')
open("$T/f7/record.json", "w").write('{"last_message": "x' + S[-30:] + '"}')
c = fence.Credential("codex", files=[d + "/gone"], secrets=[S]); c.withdraw()
bad = fence.f7(c, None, roots=[d], files=["$T/f7/record.json"])[1]
a, b = open(d + "/cli.jsonl").read(), open("$T/f7/record.json").read()
print(len(bad), any(w in x for x in (a, b) for w in (S, S[-24:], S[len(S) // 2:len(S) // 2 + 24], S[len(S) // 4:len(S) // 4 + 24])),
      "[login withdrawn: F7]" in a and "[login withdrawn: F7]" in b, fence.f7(c, None, roots=[d], files=["$T/f7/record.json"])[0]["files_holding_it"])
PY
)" "1 False True 0" "f7(): the CLI's log and the harness record that held the login are rewritten without it (round 5b: the paper alone was withheld)"
check "$(F <<PY
import os
d = "$T/f7/w"; os.makedirs(d + "/box/copy/x", exist_ok=True); S = "SECRET-" + "uvwxyzabcd" * 6
open(d + "/box/copy/x/auth.json", "w").write(S); open(d + "/cli.jsonl", "w").write(S)
c = fence.Credential("codex", files=[d + "/gone"], secrets=[S]); c.withdraw()
n = fence.f7(c, None, roots=[d], box=d + "/box")[0]["files_holding_it"]
print(n, open(d + "/box/copy/x/auth.json").read() == S, S not in open(d + "/cli.jsonl").read())
PY
)" "2 True True" "f7(): a hit under the arm's box is named and never rewritten (a folder there is the arm's to swap for a link: round 6), one outside it is"
check "$(F <<PY
import os, socket, json
a = "$T/f7/auth3.json"; open(a, "w").write("x")
c = fence.Credential("codex", files=[a])
log = "$T/f7/proxy.jsonl"
p = fence.Proxy(["vendor.test"], log=log, on_vendor=c.withdraw); port = p.start()
def ask(req):
    s = socket.create_connection(("127.0.0.1", port)); s.sendall(req); out = s.recv(400).decode().split("\r\n")[0]; s.close()
    return out.split(" ")[1], os.path.exists(a)
print(ask(b"CONNECT other.test:443 HTTP/1.1\r\n\r\n"), ask(b"CONNECT vendor.test:22 HTTP/1.1\r\n\r\n"))
print(ask(b"CONNECT vendor.test:443 HTTP/1.1\r\n\r\n"), ask(b"CONNECT vendor.test:443 HTTP/1.1\r\n\r\n"))
p.stop()
print([("withdraw" if "withdraw" in l else l["host"]) for l in map(json.loads, open(log))], p.withdrawal["ok"], p.withdrawal["host"], len(p.decisions))
n = []
r = fence.Proxy(["vendor.test"], research=True, on_vendor=lambda: n.append(1) or {"ok": True}); port = r.start()
print(ask(b"CONNECT research.test:443 HTTP/1.1\r\n\r\n")[0], n, r.withdrawal)
r.stop()
PY
)" "('403', True) ('403', True)
('403', False) ('403', False)
['other.test', 'vendor.test', 'withdraw', 'vendor.test', 'vendor.test'] True vendor.test 4
403 [] None" \
  "the proxy's ON_VENDOR: once, at the first request for a vendor host on a port the rule passes, before it resolves and answers; never for another host, research on or off"
echo "the proxy keeps what the arm sent with its request, and judges every plain-http request (the fourth review, finding 7)"
check "$(F <<'PY'
import socket, threading, time
got = []
srv = socket.socket(); srv.bind(("127.0.0.1", 0)); srv.listen(8); up_port = srv.getsockname()[1]
def upstream():
    while True:
        try:
            c, _ = srv.accept()
        except OSError:
            return
        c.settimeout(2); data = b""
        try:
            while True:
                x = c.recv(65536)
                if not x:
                    break
                data += x
                if b"HELLO" in data or (b"BODY" in data):
                    time.sleep(0.3)
                    try:
                        c.settimeout(0.3); data += c.recv(65536)
                    except OSError:
                        pass
                    break
        except OSError:
            pass
        got.append(data); c.sendall(b"HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nok"); c.close()
threading.Thread(target=upstream, daemon=True).start()
p = fence.Proxy(["vendor.test"], research=True)
p.judge = lambda host, port: ((socket.AF_INET, ("127.0.0.1", up_port)), None)   # the address judged elsewhere
port = p.start()
s = socket.create_connection(("127.0.0.1", port)); s.sendall(b"CONNECT vendor.test:443 HTTP/1.1\r\nHost: vendor.test\r\n\r\nHELLO")
s.settimeout(3); s.recv(200); time.sleep(0.8); s.close()
s = socket.create_connection(("127.0.0.1", port))
s.sendall(b"POST http://a.test/x HTTP/1.1\r\nHost: a.test\r\nContent-Length: 4\r\nConnection: keep-alive\r\n\r\nBODY"
          b"GET http://b.test/y HTTP/1.1\r\nHost: b.test\r\n\r\n")
s.settimeout(3); r = b""
try:
    while True:
        x = s.recv(4096)
        if not x:
            break
        r += x
except OSError:
    pass
s.close(); time.sleep(0.3)
s = socket.create_connection(("127.0.0.1", port)); s.sendall(b"POST http://a.test/z HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n4\r\nBODY\r\n0\r\n\r\n")
s.settimeout(3); te = s.recv(200).split(b"\r\n")[0].decode(); s.close()
p.stop(); srv.close()
print(got[0].endswith(b"HELLO"), b"BODY" in got[1], b"b.test" in got[1], b"Connection: close" in got[1], b"keep-alive" in got[1],
      r.endswith(b"ok"), len(got), te)
PY
)" "True True False True False True 2 HTTP/1.1 411 Length Required" \
  "CONNECT: a ClientHello sent with the request reaches the host; plain http: the body sent, a second request never forwarded, Connection: close; chunked refused"
echo "what any process's environment shows an arm (the fourth landing review, finding 1)"
cat > "$T/reexec.py" <<'PY'
import os, sys
sys.path.insert(0, sys.argv[1]); import fence
fence.reexec_clean(sys.argv, pipe=("FAKE_PIPED_TOKEN",))
own = fence.env_names(os.getpid()) or []
print(sorted(n for n in os.environ if fence.SECRET_KEY.search(n)), sorted(fence.PIPED), fence.PIPED.get("FAKE_PIPED_TOKEN") == "pv",
      "SSH_AUTH_SOCK" in os.environ, "FAKE_PIPED_TOKEN" in own, "FAKE_OTHER_SECRET" in own, "COUNCIL_X" in os.environ,
      os.environ.get("GEMINI_CLI_HOME"))
PY
check "$(FAKE_PIPED_TOKEN=pv FAKE_OTHER_SECRET=x SSH_AUTH_SOCK=/x.sock COUNCIL_X=1 GEMINI_CLI_HOME=/x/agy perl -e 'alarm 15; exec @ARGV' python3 "$T/reexec.py" "$M/hooks")" \
  "[] ['FAKE_PIPED_TOKEN'] True False False False True /x/agy" \
  "reexec_clean(): run again from the allowlist, no credential-named variable on its start (none KERN_PROCARGS2 shows), the one it needs on a pipe; agy's home kept (round 6)"
check "$(F <<'PY'
print(fence.holders_why({}), fence.holders_why({"X_TOKEN": 2}).split(" — ")[0].endswith("X_TOKEN in 2"))
import tempfile, os
f = tempfile.NamedTemporaryFile("w", delete=False); f.write("Y_SECRET\n"); f.close()
os.environ["REGATTA_FENCE_HOLDERS"] = f.name
print(fence.env_holders(), fence.probe("/x.sb", "/box")[0].split(":")[0] if fence.available() else "processes of this user hold credential-named variables an arm reads through sysctl (KERN_PROCARGS2), which no seatbelt rule closes")
os.environ["REGATTA_UNATTENDED"] = "dispatch"
print("Y_SECRET" in fence.env_holders())
PY
)" "None True
{'Y_SECRET': 1} processes of this user hold credential-named variables an arm reads through sysctl (KERN_PROCARGS2), which no seatbelt rule closes
False" "holders_why(): names and counts, never a value; the probe refuses first on any; the stand-in list is never an unattended caller's"
if [ -n "$FENCE" ]; then
  ( FAKE_HOLDER_TOKEN=x CLAUDE_CODE_OAUTH_TOKEN_FILE_DESCRIPTOR=3 exec python3 -c 'import time; time.sleep(20)' ) & HP=$!
  sleep 0.5
  check "$(F <<PY
import os
print("FAKE_HOLDER_TOKEN" in (fence.env_names($HP) or []), "FAKE_HOLDER_TOKEN" in fence.env_holders(), "PATH" in (fence.env_names($HP) or []))
PY
)" "True False True" "env_names(): a process's start variables by name; the stand-in list in place of the live read for an attended suite"
  check "$(REGATTA_FENCE_HOLDERS= F <<PY
h = fence.env_holders(); print(h.get("FAKE_HOLDER_TOKEN", 0) >= 1, "CLAUDE_CODE_OAUTH_TOKEN_FILE_DESCRIPTOR" in h)
PY
)" "True False" "  the live read (sysctl, every process of this user) finds a process holding one; the Claude arm's fd number is no credential (round 1)"
  kill "$HP" 2>/dev/null; wait "$HP" 2>/dev/null
fi
echo "round 2 of the build review: links, names, the start environment, the proxy's body"
KH="$T/kb/box/home"; mkdir -p "$KH/Library" "$T/kb/outside"; echo not-a-keychain > "$T/kb/outside/login.keychain-db"
ln -s "$T/kb/outside" "$KH/Library/Keychains"
check "$(F <<PY
print(fence.in_box("$T/kb", "$T/kb/box/x"), fence.in_box("$T/kb/box", "$KH/Library/Keychains/k"), fence.in_box("$T/kb/box", "/etc/hosts"))
PY
)" "True False False" "  in_box(): no link on the way, under the box"
F <<PY
fence.drop_box("$T/kb/box")
PY
check "$(cat "$T/kb/outside/login.keychain-db" 2>/dev/null)/$([ -e "$T/kb/box" ] && echo left || echo gone)" "not-a-keychain/gone" \
  "drop_box(): a keychain reached through a link the arm planted is never handed to security delete-keychain"
check "$(F <<'PY'
import struct
raw = struct.pack("i", 2) + b"/bin/node\0\0\0" + b"\0" * 12 + b"PATH=/usr/bin\0X_TOKEN=v\0"   # argv zero-filled (a retitled process)
print(fence._env_from_procargs(raw), fence._env_from_procargs(struct.pack("i", 1) + b"/x\0x\0A=b\0"))
PY
)" "['PATH', 'X_TOKEN'] ['A']" "_env_from_procargs(): names by shape, never counted from argc (a retitled process zero-fills its argv)"
cat > "$T/again.py" <<'PY'
import sys
sys.path.insert(0, sys.argv[1]); import fence
try:
    fence.reexec_clean(sys.argv)
    print("returned")
except fence.FenceError as e:
    print("refused", "FAKE_BACK_TOKEN" in str(e))
PY
check "$(REGATTA_FENCE_CLEAN=1 FAKE_BACK_TOKEN=x perl -e 'alarm 15; exec @ARGV' python3 "$T/again.py" "$M/hooks")" "refused True" \
  "reexec_clean(): once marked, never a second exec; a credential-named variable there refuses, named, never looped"
check "$(F <<PY
import os
open("$T/stand-in", "w").write("#!/bin/sh\n"); os.chmod("$T/stand-in", 0o755)
open("$T/copy-bin", "wb").write(b"\xcf\xfa\xed\xfe"); os.chmod("$T/copy-bin", 0o755)
os.environ["REGATTA_UNATTENDED"] = "dispatch"
print(fence.stand_in_holders("$T/stand-in", "codex"), fence.stand_in_holders("$T/copy-bin", "codex"), fence.stand_in_holders("sh", "sh"))
PY
)" "{} None None" "stand_in_holders(): a script stand-in only; a copy of a compiled CLI, or the CLI by its bare name, is the real one"
check "$(F <<'PY'
print(fence.leave_names([".ENV", "a/.Env.local", "_Secrets/x", ".env.example"]), fence.fold("ſ"))
PY
)" "[('.ENV', 'an env file the secrets guard closes'), ('a/.Env.local', 'an env file the secrets guard closes'), ('_Secrets/x', 'a vault folder the secrets guard closes')] s" \
  "leave_names(): names compared as APFS compares them"
check "$(F <<'PY'
import socket, time
p = fence.Proxy(["vendor.test"]); port = p.start()
def ask(req):
    s = socket.create_connection(("127.0.0.1", port)); s.sendall(req); s.settimeout(5); out = s.recv(200).split(b"\r\n")[0].decode(); s.close(); return out
t0 = time.time()
a = ask(b"POST http://other.test/ HTTP/1.1\r\nContent-Length: 50000000000\r\n\r\n")
r = fence.Proxy([], research=True); r.judge = lambda h, pt: ((socket.AF_INET, ("127.0.0.1", 9)), None); port = r.start()
b = ask(b"POST http://a.test/ HTTP/1.1\r\nContent-Length: 50000000000\r\n\r\n")
p.stop(); r.stop()
print(a.split(" ")[1], b, time.time() - t0 < 4)
PY
)" "403 HTTP/1.1 413 Payload Too Large True" "the proxy: a refused host answered before any body is read; a body past 16 MiB refused"
echo "round 3 of the build review"
check "$(F <<'PY'
import struct
print(fence._env_from_procargs(struct.pack("i", 1) + b"/x\0x\0MY-TOKEN=v\0A=b\0"))
PY
)" "['MY-TOKEN', 'A']" "_env_from_procargs(): any name before the first =, as an exec environment holds it"
check "$(F <<PY
import json
p = "$T/agy-echo.jsonl"
open(p, "w").write(json.dumps({"event": "step_update", "step_update": {"step_index": 1, "step_type": "tool", "tool_name": "browser_click",
    "state": "ERROR", "tool_info": {"error": "the page said: not in the council arm's tool set"}}}) + "\n")
r = fence.record("agy", p); print(r["denied"], any("browser_click" in b for b in r["bad"]))
PY
)" "[] True" "agy: an error that only echoes our hook's words is no denial of ours (anchored on the hook's own line)"
check "$(F <<'PY'
t = fence.profile("/x/box", 1)
print("com.apple.pasteboard" in t and "(deny mach-lookup" in t, '(deny file-read* (subpath "/opt/homebrew/var")' in t, t.index("(deny mach-lookup") > t.index("(allow mach-lookup)"))
PY
)" "True True True" "the profile closes the clipboard's service and Homebrew's data, after the allows (the last rule wins)"
echo "round 4 of the build review"
check "$(F <<'PY'
import struct
print(fence._env_from_procargs(struct.pack("i", 1) + b"/x\0x\0caf\xc3\xa9=1\0A=b\0"), fence.is_stand_in("/usr/bin/true"))
PY
)" "['café', 'A'] False" "names decoded whatever their bytes; a compiled binary is no stand-in"
printf '#!/usr/bin/env node\n' > "$T/node-cli"; printf '#!/bin/sh\n' > "$T/sh-cli"
check "$(F <<PY
print(fence.is_stand_in("$T/node-cli"), fence.is_stand_in("$T/sh-cli"))
PY
)" "False True" "is_stand_in(): a node launcher (npm's CLIs) is the real CLI; a shell script is a suite's stand-in"
mkdir -p "$HD/.local/bin"; printf 'x' > "$HD/.local/bin/tool"; chmod +x "$HD/.local/bin/tool"; echo other > "$HD/.local/bin/helper"
check "$(F <<PY
real, inst = fence.install_of("$HD/.local/bin/tool")
t = fence.profile("$T/ib/box", 1, reads=[inst])
print(inst == real, '(literal "%s")' % real in t, '(subpath "$HD/.local/bin")' in t)
PY
)" "True True False" "install_of(): a CLI installed in a home folder is read alone, never its neighbours"
ln -s /tmp "$T/linkbox"
check "$(F <<PY
try:
    fence.profile("$T/linkbox", 1); print("built")
except fence.FenceError as e:
    print("refused", "link" in str(e))
PY
)" "refused True" "profile(): a box path that is a link (a leftover's) builds no profile"
check "$(F <<'PY'
import json, tempfile
p = tempfile.mktemp()
open(p, "w").write("\n".join(json.dumps({"event": "step_update", "step_update": {"step_type": "tool", "tool_name": n, "state": "DONE"}}) for n in ("open_browser_url", "run_command")) + "\n")
print(any("open_browser_url" in b for b in fence.record("agy", p)["bad"]))
PY
)" "True" "agy: steps with no index never overwrite each other (a later allowed one hid an earlier one)"
check "$(F <<'PY'
print("uauseractivitypasteboardclient" in fence.profile("/x/box", 1))
PY
)" "True" "the profile closes pboard's second service too"
echo "round 6 of the build review: research waits for the withdrawal; stop() closes open tunnels"
check "$(F <<'PY'
import socket, threading, time
r = fence.Proxy(["vendor.test"], research=True, on_vendor=lambda: {"ok": True})
before = r.judge("1.1.1.1", 443)[1]
r.vendor_once("vendor.test")
after = r.judge("1.1.1.1", 443)[1]
k = fence.Proxy(["vendor.test"], research=True, on_vendor=lambda: {"ok": False, "left": ["auth.json"]})
k.vendor_once("vendor.test")
kept = fence.Proxy(["vendor.test"], research=True, on_vendor=lambda: {"ok": False, "kept": "a CLI that needs it"})
kept.vendor_once("vendor.test")
print(before, "|", after, "|", k.judge("1.1.1.1", 443)[1], "|", kept.judge("1.1.1.1", 443)[1])
v = fence.Proxy(["1.1.1.1"], research=True, on_vendor=lambda: {"ok": True})
v80 = v.judge("1.1.1.1", 80)[1]
v.vendor_once("1.1.1.1")
print(v80, "|", v.judge("1.1.1.1", 80)[1])
f = fence.Proxy(["1.1.1.1"], on_vendor=lambda: {"ok": False, "left": ["auth.json"]})
f.vendor_once("1.1.1.1")
print(f.judge("1.1.1.1", 443)[1])
srv = socket.socket(); srv.bind(("127.0.0.1", 0)); srv.listen(4); up_port = srv.getsockname()[1]
held = []
def upstream():
    c, _ = srv.accept(); held.append(c)
threading.Thread(target=upstream, daemon=True).start()
p = fence.Proxy(["vendor.test"])
p.judge = lambda host, port: ((socket.AF_INET, ("127.0.0.1", up_port)), None)
port = p.start()
s = socket.create_connection(("127.0.0.1", port)); s.sendall(b"CONNECT vendor.test:443 HTTP/1.1\r\n\r\n")
s.settimeout(3); s.recv(200); time.sleep(0.3)
t0 = time.time()
p.stop()
s.settimeout(3)
try:
    end = s.recv(10) == b""   # the tunnel shut by stop(); a timeout is no end (round 6, second review)
except socket.timeout:
    end = False
except OSError:
    end = True
print(end and time.time() - t0 < 1.5, len(p._open))
PY
)" "not the CLI's vendor host, and research opens only once the login is withdrawn (F7) | None | the login's withdrawal did not hold (F7): every connection refused | None
port 80 | None
the login's withdrawal did not hold (F7): every connection refused
True 0" \
  "the proxy with ON_VENDOR: research opens once the withdrawal held (or the login is kept), never before or after a failed one, port 80 too; stop() ends a tunnel still open, at once (round 6)"
echo "drop_box: a link in the box is never followed (the fourth landing review, finding 3)"
mkdir -p "$T/db/box/copy" "$T/db/outside"; chmod 500 "$T/db/outside"; ln -s "$T/db/outside" "$T/db/box/copy/away"
F <<PY
fence.drop_box("$T/db/box")
PY
check "$([ -e "$T/db/box" ] && echo box-left || echo box-gone)/$(python3 -c 'import os,sys; print(oct(os.stat(sys.argv[1]).st_mode & 0o777)[2:])' "$T/db/outside")" "box-gone/500" \
  "drop_box(): the box removed, a folder its link named outside keeps its mode (chmod never follows the link)"
chmod 700 "$T/db/outside"
if [ -z "$FENCE" ]; then
  echo "  note no seatbelt on $(uname): the profile, wrap and keychain cases run on macOS only"
  check "$(F <<'PY'
print(fence.available(), fence.probe("/x", "/y"))
PY
)" "False ['sandbox-exec is not here ($(python3 -c 'import sys; print(sys.platform)')): no seatbelt']" "off macOS: no seatbelt, the probe says so (every arm refused)"
else
  echo "the seatbelt (macOS)"
  B="$T/arm/box"; mkdir -p "$B/copy" "$HD/.ssh"; echo SSH-SECRET > "$HD/.ssh/id_test"; echo ro > "$B/cfg.json"
  # the localhost case names its port: compared without it
  out=$(F <<PY
import os
B = "$B"; P = fence.Proxy([]); port = P.start()
w = lambda name, text: fence.write_profile(os.path.join("$T/arm", name), text)
print(fence.probe(w("arm.sb", fence.profile(B, port, ro=[B + "/cfg.json"])), B, port, ro=[B + "/cfg.json"]))
print([x.split(" (")[0].split(":")[0] for x in fence.probe(w("net.sb", fence.profile(B, port).replace("(deny network*)", "(allow network*)")), B, port)])
print([x.split(":")[0] for x in fence.probe(w("home.sb", fence.profile(B, port, reads=["$HOME"])), B, port)][:3])
print(fence.probe(w("rw.sb", fence.profile(B, port)), B, port, ro=[B + "/cfg.json"]))
P.stop()
PY
)
  check "$out" "[]
['a unix socket outside', 'localhost']
['read $HOME', 'read $HD/.ssh', 'read $HD/.claude']
['write $B/cfg.json: allowed inside']" "probe(): the template holds; an open network, a read of ~ and a writable read-only path are each named"
  W() { /usr/bin/sandbox-exec -f "$T/arm/arm.sb" /bin/sh -c "$1" 2>&1 | head -1; }
  check "$(W "cat $HD/.ssh/id_test")" "cat: $HD/.ssh/id_test: Operation not permitted" "wrap's profile: a key under ~ refused"
  check "$(W "head -c 2 /etc/hosts")|$(W "echo w > $B/copy/w && cat $B/copy/w")|$(W "echo x >> $B/cfg.json; cat $B/cfg.json")" \
    "##|w|/bin/sh: $B/cfg.json: Operation not permitted" "  /etc/hosts read, the copy written, a read-only path in the box refused"
  check "$(W "ls /Library/Preferences >/dev/null && echo read")|$(W "HOME=$B GIT_CONFIG_GLOBAL=/dev/null /usr/bin/git --version 2>/dev/null | cut -c1-11")" \
    "ls: /Library/Preferences: Operation not permitted|git version" "  /Library narrowed (S4): its preferences refused, while git still runs through xcrun's developer dir"
  check "$(F <<PY
import os
B = "$B"; P = fence.Proxy([]); port = P.start()
print([x.split(":")[0] for x in fence.probe(fence.write_profile("$T/arm/lib.sb", fence.profile(B, port, reads=["/Library"])), B, port)])
P.stop()
PY
)" "['read /Library/Preferences']" "  probe(): a profile that reads /Library whole is named"
  DB=/private/var/db
  check "$(W "ls $DB/uuidtext >/dev/null 2>&1 && echo read || echo refused")|$(W "ls $DB/com.apple.xpc.launchd >/dev/null 2>&1 && echo read || echo refused")|$(W "head -c 4 /etc/localtime")" \
    "refused|refused|TZif" "  the OS's db folder narrowed (the sixth landing review's S2): the log's string tables and launchd's job lists refused, the timezone read"
  # the expected list is read at run time: probe() judges a folder only when its `ls` works outside the profile too,
  # and a runner's process (likely a launchd job without Full Disk Access; inferred, not read from a log) cannot `ls`
  # some of them even outside any sandbox (CoreDuet and backgroundtaskmanagement on a self-hosted runner, seen after
  # the principal-council-fences landing), so the case asks the same of this host. A readable folder the profile still
  # shuts stays missing from the answer and fails the case; the order is fence.VAR_DB_PROBED's, uuidtext first as the
  # case removes its deny. A folder this host cannot read is named on a `note:` line: no profile can leak it here, and
  # a host that reads it (every Mac's session) judges it, so this is the host's limit, never a skipped case.
  DBR=""; DBU=""
  for d in uuidtext CoreDuet com.apple.backgroundtaskmanagement spindump; do
    if /bin/ls "$DB/$d" >/dev/null 2>&1; then DBR="$DBR${DBR:+, }'read $DB/$d'"; else DBU="$DBU $d"; fi
  done
  [ -z "$DBU" ] || echo "  note: db folders this host cannot read even unsandboxed, so no profile can leak them here:$DBU"
  check "$(F <<PY
B = "$B"; P = fence.Proxy([]); port = P.start()
text = fence.profile(B, port, reads=["$DB"]).replace('(subpath "$DB/uuidtext")', "")
print([x.split(":")[0] for x in fence.probe(fence.write_profile("$T/arm/db.sb", text), B, port)])
P.stop()
PY
)" "[$DBR]" "  probe(): a profile that reads the db folder whole, the log's string tables with it, is named folder by folder (the ones this host reads)"
  check "$(W "ls $DB/CoreDuet >/dev/null 2>&1 && echo read || echo refused")|$(W "python3 -c 'import os; m, s = os.openpty(); os.write(s, b\"ok\"); print(os.read(m, 2).decode())' 2>/dev/null")" \
    "refused|ok" "  the seventh review: the db folder is the timezone alone (CoreDuet refused), and the arm's own pty works"
  check "$(F <<PY
B = "$B"; P = fence.Proxy([]); port = P.start()
text = fence.profile(B, port).replace('(extension "com.apple.sandbox.pty")', "")
print([x.split(":")[0] for x in fence.probe(fence.write_profile("$T/arm/pty.sb", text), B, port)])
P.stop()
PY
)" "['open a terminal outside']" "  probe(): a profile that opens every pty, the owner's terminals with them, is named (the seventh review)"
  check "$(F <<PY
print(fence.wrap(["claude", "-p"], "/p.sb"))
PY
)" "['/usr/bin/sandbox-exec', '-f', '/p.sb', 'claude', '-p']" "wrap(): the CLI under sandbox-exec"

  echo "the folders above a read-only path (the fourth landing review, finding 6)"
  check "$(F <<PY
B = "$B"; print([x[len(B):] for x in fence.ro_ancestors(B, [B + "/a/b/c.json", B + "/a/d/", B + "/top.json"])])
PY
)" "['/a', '/a/b']" "ro_ancestors(): each folder between the box and a read-only path, once, outermost first"
  mkdir -p "$B/cfgd/inner"; echo ro > "$B/cfgd/inner/hooks.json"
  out=$(F <<PY
B = "$B"; P = fence.Proxy([]); port = P.start(); ro = [B + "/cfgd/inner/hooks.json"]
text = fence.profile(B, port, ro=ro)
print(fence.probe(fence.write_profile("$T/arm/anc.sb", text), B, port, ro=ro))
old = "\n".join(l for l in text.splitlines() if not ("(literal" in l and "cfgd" in l and "hooks.json" not in l))
print([x.split(" (")[0][len("write " + B):] + ":" + x.split(": ")[-1] for x in fence.probe(fence.write_profile("$T/arm/old.sb", old), B, port, ro=ro)])
P.stop()
PY
)
  check "$out" "[]
['/cfgd:allowed inside', '/cfgd/inner:allowed inside']" \
    "probe(): with each folder above the read-only path held, it holds; without (the old profile), each rename is named"
  A() { /usr/bin/sandbox-exec -f "$T/arm/anc.sb" /bin/sh -c "$1" 2>&1 | head -1; }
  check "$(A "mv $B/cfgd/inner $B/cfgd/moved && echo moved")|$(A "mv $B/cfgd $B/cfgd2 && echo moved")|$(A "echo x > $B/cfgd/inner/other && echo wrote")" \
    "mv: rename $B/cfgd/inner to $B/cfgd/moved: Operation not permitted|mv: rename $B/cfgd to $B/cfgd2: Operation not permitted|wrote" \
    "  under it: neither folder renamed (the hooks.json stays where the CLI reads it), a new file beside it still written"
    echo "drop_box against an arm's process flipping its keychain folder for a link (round 3)"
  cat > "$T/fake-security" <<'SH'
#!/bin/sh
python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$3" >> "$FAKE_SEC_LOG"
SH
  chmod +x "$T/fake-security"; : > "$T/sec.log"; mkdir -p "$T/race-out"; echo x > "$T/race-out/login.keychain-db"
  for i in 1 2 3 4 5 6 7 8; do
    RB="$T/race/$i/box"; RK="$RB/home"; mkdir -p "$RK/Library/Keychains"; echo k > "$RK/Library/Keychains/login.keychain-db"
    F <<PY
fence.write_profile("$T/race/$i/arm.sb", fence.profile("$RB", None))
PY
    /usr/bin/sandbox-exec -f "$T/race/$i/arm.sb" /bin/sh -c "cd '$RK/Library' && while :; do mv Keychains Kd 2>/dev/null; ln -s '$T/race-out' Keychains 2>/dev/null; rm Keychains 2>/dev/null; mv Kd Keychains 2>/dev/null; done" &
    RP=$!; sleep 0.3
    FAKE_SEC_LOG="$T/sec.log" F <<PY
fence.SECURITY = "$T/fake-security"
fence.drop_box("$RB")
PY
    kill "$RP" 2>/dev/null; wait "$RP" 2>/dev/null
  done
  check "$(grep -c "$T/race-out" "$T/sec.log")/$(cat "$T/race-out/login.keychain-db")" "0/x" \
    "  eight boxes, a sandboxed loop flipping each: security is never handed a path outside the box (the box is renamed out of its write rule first)"

  echo "drop_box on a box its arm made unrenameable (round 4)"
  UB="$T/ub/box"; UH="$UB/home"; mkdir -p "$UH/Library/Keychains"; echo k > "$UH/Library/Keychains/login.keychain-db"; : > "$T/sec2.log"
  chflags uchg "$UB"
  FAKE_SEC_LOG="$T/sec2.log" F > /dev/null 2>"$T/ub.err" <<PY
fence.SECURITY = "$T/fake-security"
fence.drop_box("$UB")
PY
  check "$(wc -l < "$T/sec2.log" | tr -d ' ')/$([ -d "$UB" ] && echo left)" "0/left" "  the rename refused: no security call, the box left for the owner"
  check "$(grep -c "could not be closed" "$T/ub.err")" 1 "    saying so"
  chflags nouchg "$UB"

  echo "agy's scratch HOME and its per-run keychain (macOS)"
  KC="$HD/Library/Keychains/login.keychain-db"; mkdir -p "$HD/Library/Keychains" "$HD/.gemini/antigravity-cli"
  printf '{"colorScheme": "dark", "trustedWorkspaces": ["/x"], "permissions": {"allow": ["*"]}}' > "$HD/.gemini/antigravity-cli/settings.json"
  echo id > "$HD/.gemini/antigravity-cli/installation_id"
  /usr/bin/security create-keychain -p t "$KC" && /usr/bin/security set-keychain-settings "$KC" \
    && /usr/bin/security add-generic-password -s gemini -a antigravity -w FAKE-AGY-ITEM-STAND-IN "$KC" \
    && /usr/bin/security add-generic-password -s "Claude Code-credentials" -a "$USER" -w STAND-IN-ITEM-2 "$KC"
  check "$?" 0 "a keychain of the test's own under its HOME, holding a stand-in agy item and a stand-in Claude item"
  AB="$T/agy/box"; mkdir -p "$AB"
  check "$(F <<PY
import os, json, subprocess
env, ro, cred = fence.arm_home("agy", "$AB")
h = env["HOME"]
print(json.load(open(h + "/.gemini/antigravity-cli/settings.json")), os.path.getsize(h + "/.gemini/config/mcp_config.json"))
hook = json.load(open(h + "/.gemini/config/hooks.json"))["council"]["PreToolUse"][0]
print(hook["matcher"], hook["hooks"][0]["command"].endswith("$AB/hook/agy_hook.py"), oct(os.stat("$AB/hook/agy_hook.py").st_mode & 0o777))
k = lambda s, a: subprocess.run(["/usr/bin/security", "find-generic-password", "-s", s, "-a", a, "-w"], capture_output=True, text=True,
                                env={"HOME": h, "PATH": "/usr/bin:/bin"}).stdout.strip() or "not found"
print(k("gemini", "antigravity"), k("Claude Code-credentials", os.environ["USER"]))
PY
)" "{'colorScheme': 'dark'} 0
* True 0o444
FAKE-AGY-ITEM-STAND-IN not found" "agy's home: settings cut to colorScheme, no MCP server, our hook alone (read-only); its keychain holds agy's item and not Claude's"
  check "$(F <<PY
import os
env, ro, cred = fence.arm_home("agy", "$T/agy/box-t")
t = env["HOME"] + "/.gemini/antigravity-cli/antigravity-oauth-token"
print(t in ro, cred.files == [t], [os.path.basename(f) for f in fence.Credential.in_box("agy", "$T/agy/box-t").files])
open(t, "w").write("x"); print(cred.present()); cred.withdraw(); print(cred.present(), os.path.exists(t))
fence.drop_box("$T/agy/box-t")
PY
)" "True True ['antigravity-oauth-token']
['antigravity-oauth-token', 'the per-run keychain']
[] False" "  agy 1.4.12's token file: read-only to the arm, one of its login's files, so F7 withdraws it and names it (S4)"
  check "$(F <<PY
import os, json
env, ro = None, None
P = fence.Proxy([]); port = P.start()
h = "$AB/home"
ro = [h + "/.gemini/config/hooks.json", h + "/.gemini/config/mcp_config.json", h + "/.gemini/antigravity-cli/settings.json", "$AB/hook/"]
prof = fence.write_profile("$T/agy/arm.sb", fence.profile("$AB", port, ro=ro))
print(fence.probe(prof, "$AB", port, ro=ro))
cmd = json.load(open(h + "/.gemini/config/hooks.json"))["council"]["PreToolUse"][0]["hooks"][0]["command"]
import subprocess
for t in ("run_command", "call_mcp_tool"):
    for shape in ({"tool_name": t}, {"toolCall": {"name": t}}):
        r = subprocess.run(fence.wrap(["/bin/sh", "-c", cmd], prof), input=json.dumps(shape), capture_output=True, text=True,
                           env={"PATH": "/usr/bin:/bin", "HOME": h})
        print(t, json.loads(r.stdout)["decision"])
P.stop()
PY
)" "[]
run_command allow
run_command allow
call_mcp_tool deny
call_mcp_tool deny" "  under its profile: the probe holds with its configs and hook read-only, and our hook answers there, in either shape"
  check "$(F <<PY
import os, subprocess
c = fence.Credential.in_box("agy", "$AB")
before = c.present()
w = c.withdraw()
k = subprocess.run(["/usr/bin/security", "find-generic-password", "-s", "gemini", "-a", "antigravity"], capture_output=True,
                   env={"HOME": "$AB/home", "PATH": "/usr/bin:/bin"}).returncode
print(before, w["ok"], w["left"], c.present(), k)
PY
)/$(/usr/bin/security list-keychains -d user | grep -c "$KC")" "['the per-run keychain'] True [] [] 44/1" \
    "F7's withdrawal: the per-run keychain deleted, agy's item no longer found under the scratch HOME; the test HOME's own keychain untouched"
  check "$(F <<PY
import os
fence.drop_box("$AB")
print(os.path.exists("$AB"), "$AB" in open(os.devnull).read() or "$AB/home" in os.popen("HOME=$AB/home /usr/bin/security list-keychains -d user").read())
PY
)/$(/usr/bin/security list-keychains -d user | grep -c "$KC")" "False False/1" \
    "drop_box(): the per-run keychain deleted and the box gone; the test HOME's own keychain still listed"
fi

[ "$fails" -eq 0 ] && echo "fence: all ok" || echo "fence: $fails failed"
[ "$fails" -eq 0 ]
