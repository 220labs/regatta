#!/usr/bin/env bash
# Tests for bin/council: run, examine, review and receipt against stand-ins for claude, codex, agy, lighthouse's
# account and dispatch's --cap — no model is called. Since the isolation design's S1 every arm runs under the
# core's fence (hooks/fence.py): a seatbelt over its box, a proxy as its door, a scratch home, an environment
# from an allowlist, the record read from its CLI's own log. On macOS the stand-ins run under the real seatbelt
# and report what they saw — their cwd, argv, environment, a read outside, a write to a read-only config, the
# per-run keychain, our agy hook's answer — as events in the log council keeps; elsewhere every arm is refused,
# and that refusal is the case. The Codex arm goes through the real bin/harness of wharf-runs beside this module,
# its shell on. F7: each stand-in makes its first request to its vendor's host through the proxy, as the real CLIs
# do (the name never resolves offline: the proxy withdraws before it resolves), and reports what of its login it
# still finds after; one that never asks, rewrites its login or leaks it into its log or paper fails its arm. A
# confidential or torn registry, a guarded home, an unattended --approved, a run dir inside ~, a commit holding
# an env file, a feature Codex has on that no one judged, a tool the start did not allow, a step outside our
# hook's list, agy's empty SUCCESS and a paper holding a token's shape each refuse, fail or hold back what they
# concern.
#   bash modules/wharf/tests/test_council.sh
set -u
unset CLAUDE_UNATTENDED REGATTA_UNATTENDED AUTOFINISH_CALLER_UNATTENDED CLAUDE_CODE_DISABLE_BACKGROUND_TASKS CLAUDE_CODE_SESSION_ID CLAUDE_CONFIG_DIR \
      CODEX_HOME REGATTA_COUNCIL_ARM CLAUDE_CODE_OAUTH_TOKEN ANTHROPIC_API_KEY
for v in $(env | sed -n 's/^\(GATE_[A-Z0-9_]*\)=.*/\1/p; s/^\(DISPATCH_[A-Z0-9_]*\)=.*/\1/p; s/^\(STUB_[A-Z0-9_]*\)=.*/\1/p'); do unset "$v"; done
B="$(cd "$(dirname "$0")/../bin" && pwd)"
M="$(cd "$B/.." && pwd)"
# F4's start probe reads every process of this user (finding 1): the session running this suite holds its
# own token, so a stand-in names none (fence.sh has the live read's cases)
HB="$M/../wharf-runs/bin/harness"
FENCE_PY="$M/../regatta/hooks/fence.py"
T=$(mktemp -d "${TMPDIR:-/tmp}/council-test-XXXXXX"); T=$(cd "$T" && pwd -P)
: > "$T/holders-none"; export REGATTA_FENCE_HOLDERS="$T/holders-none"
KC="$T/home"/Library/Keychains/login.keychain-db
trap '[ -f "$KC" ] && /usr/bin/security delete-keychain "$KC" 2>/dev/null; chmod -R u+w "$T" 2>/dev/null; rm -rf "$T"' EXIT
fails=0
check() { if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3: expected [$2] got [$1]"; fails=$((fails+1)); fi; }
has()   { if grep -qF -- "$2" "$1"; then echo "  ok   $3"; else echo "  FAIL $3: missing [$2]"; fails=$((fails+1)); fi; }
hasnt() { if grep -qF -- "$2" "$1"; then echo "  FAIL $3: has [$2]"; fails=$((fails+1)); else echo "  ok   $3"; fi; }
jget()  { python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print($2)" "$1"; }
mode_of() { python3 -c 'import os,sys; print(oct(os.stat(sys.argv[1]).st_mode & 0o777))' "$1"; }
stub()  { python3 -c 'import json,sys
for l in open(sys.argv[1]):
    try: e = json.loads(l)
    except ValueError: continue
    if isinstance(e, dict) and e.get("type") == "stub": print(eval(sys.argv[2], {"d": e})); break' "$1" "$2"; }

FENCE=""; [ "$(uname)" = Darwin ] && [ -x /usr/bin/sandbox-exec ] && FENCE=1
[ -f "$HB" ] && HAVE_HARNESS=1 || HAVE_HARNESS=""
export REGATTA_CONFIG="$T/config" HOME="$T/home" GIT_CONFIG_GLOBAL="$T/gitconfig"
HD="$T/home"   # the suite's HOME, by a name the publish gate reads as no home path (finding 6: never a bare HOME)
BH=box/home   # an arm's scratch HOME under its run dir, likewise
mkdir -p "$REGATTA_CONFIG/regatta" "$REGATTA_CONFIG/wharf-runs" "$HOME" "$T/bin" "$T/runs"
(cd "$M/../.." && pwd -P) > "$REGATTA_CONFIG/home"
echo Sam > "$REGATTA_CONFIG/regatta/owner"
echo laptop > "$REGATTA_CONFIG/regatta/laptop"
echo "$T/logs" > "$REGATTA_CONFIG/regatta/log-dir"
echo "$T/projects" > "$REGATTA_CONFIG/regatta/projects"
echo oss-thing > "$REGATTA_CONFIG/wharf-runs/public-repos"
printf '[user]\n\tname = t\n\temail = t@t\n[init]\n\tdefaultBranch = main\n' > "$GIT_CONFIG_GLOBAL"
export CLAUDE_REPOS_JSON="$T/repos.json"
echo '{"repos": {"site": {}}, "scopes": {"work": {"file": "w.code-workspace", "repos": ["site"]}}}' > "$CLAUDE_REPOS_JSON"
export COUNCIL_TMP="$T/runs" COUNCIL_CLAUDE="$T/bin/claude" COUNCIL_AGY="$T/bin/agy" COUNCIL_ACCOUNT="$T/bin/account" HARNESS_ACCOUNT="$T/bin/account" \
       HARNESS_CODEX="$T/bin/codex" HARNESS_DISPATCH="$T/bin/dispatch" HARNESS_RUNS_DIR="$T/hruns" HARNESS_START_WAIT=8 \
       HARNESS_HOST=laptop GATE_LOG="$T/gate.jsonl" CALLS="$T/calls" STUB_CALLS="$T/calls" STUB_FEATURES="$T/features.txt" \
       COUNCIL_FENCES_STATE="$T/fences-state.json"

# the logins the scratch homes copy: a Claude sign-in, Codex's auth.json, agy's state; a key the arms must not read
mkdir -p "$HD/.claude" "$HD/.codex" "$HD/.gemini/antigravity-cli" "$HD/.ssh"
# synthetic logins, each value an argument of its own (the publish gate reads a key beside its value as a credential)
printf '{"claudeAiOauth": {"accessToken": "%s"}}' STANDIN-CLAUDE-FILE-TOKEN-1 > "$HD/.claude/.credentials.json"
printf '{"oauthAccount": {"emailAddress": "sam@example.com"}}' > "$HD/.claude.json"
printf '{"tokens": {"access_token": "%s"}}' STANDIN-CODEX-ACCESS-TOKEN-1 > "$HD/.codex/auth.json"
printf '{"colorScheme": "dark"}' > "$HD/.gemini/antigravity-cli/settings.json"
echo KEY-THAT-STAYS-HOME > "$HD/.ssh/id_test"
if [ -n "$FENCE" ]; then
  # agy's item in a keychain of the suite's own, under its HOME (the search list follows HOME: record P3)
  mkdir -p "$HD/Library/Keychains"
  /usr/bin/security create-keychain -p t "$KC" && /usr/bin/security set-keychain-settings "$KC" \
    && /usr/bin/security add-generic-password -s gemini -a antigravity -w STAND-IN-AGY-ITEM "$KC" \
    && /usr/bin/security add-generic-password -s "Claude Code-credentials" -a "$USER" -w "$(printf '{"claudeAiOauth": {"accessToken": "%s"}}' STANDIN-CLAUDE-KEYCHAIN-TOKEN)" "$KC"
fi
python3 - "$FENCE_PY" "$STUB_FEATURES" <<'PY'
import sys
from importlib.machinery import SourceFileLoader
f = SourceFileLoader("fence", sys.argv[1]).load_module()
with open(sys.argv[2], "w") as o:
    for n in sorted(f.CODEX_FEATURES):
        o.write("%-40s stable             true\n" % n)
PY

# the home repo: a contract, a named file, two commits on main and one on a branch
H="$T/projects/site"; mkdir -p "$H/docs"
printf '# site\n\n- physical: none\n' > "$H/AGENTS.md"
printf 'the design note\nsecond line\n' > "$H/docs/note.md"
mkdir -p "$H/bin"; printf '#!/bin/sh\n' > "$H/bin/tool"; chmod +x "$H/bin/tool"
git -C "$H" init -q -b main && git -C "$H" add -A && git -C "$H" commit -qm one
echo more >> "$H/docs/note.md"; git -C "$H" commit -qam two
git -C "$H" checkout -qb claude/laptop/2026-10-27-x && echo change > "$H/new.txt" && git -C "$H" add -A && git -C "$H" commit -qm three
git -C "$H" checkout -q main
printf 'Should the site keep its note?\n' > "$T/brief.md"
printf '# Draft\n\nKeep it.\n' > "$T/draft.md"

# The stand-ins. Under the seatbelt one cannot write $CALLS (outside its box): what it sees goes into its own
# log as a {"type": "stub"} event, which council keeps; what it is asked outside an arm (a listing) goes to $CALLS.
cat > "$T/bin/claude" <<'PY'
#!/usr/bin/env python3
import json, os, socket, subprocess, sys
a = sys.argv[1:]
if a == ["--version"]:
    print("2.1.999 (Claude Code)")
    sys.exit(0)
def calls(line):
    try:
        with open(os.environ["STUB_CALLS"], "a") as f:
            f.write(line + "\n")
        return True
    except (OSError, KeyError):
        return False
def pipe():
    # the login on the pipe CLAUDE_CODE_OAUTH_TOKEN_FILE_DESCRIPTOR names (F7): drained, as the CLI does
    fd = os.environ.get("CLAUDE_CODE_OAUTH_TOKEN_FILE_DESCRIPTOR")
    try:
        return os.read(int(fd), 4096).decode() if fd else ""
    except (OSError, ValueError):
        return ""
TOKEN = pipe()
if a[:2] == ["mcp", "list"]:
    calls("claude mcp list cwd=%s cfg=%s pipe=%d" % (os.getcwd(), os.environ.get("CLAUDE_CONFIG_DIR", ""), len(TOKEN)))
    print("Checking MCP server health…\n\nclaude.ai Claude Docs: https://api.anthropic.com/v1/pages/mcp - ✔ Connected")
    if os.environ.get("STUB_CLAUDE_MCP"):
        print("%s: https://mcp.example.test/x - ✔ Connected" % os.environ["STUB_CLAUDE_MCP"])
    sys.exit(0)
def tryread(p):
    try:
        with open(p) as f:
            return "read:" + f.read(30).strip()
    except OSError as e:
        return type(e).__name__
def trywrite(p):
    try:
        with open(p, "a"):
            return "wrote"
    except OSError as e:
        return type(e).__name__
def look(p):
    # what the copy holds at P (S2): a link by its target, a file by its git blob name, else dir or absent
    import hashlib
    if os.path.islink(p):
        return "link:" + os.readlink(p)
    if os.path.isfile(p):
        with open(p, "rb") as f:
            b = f.read()
        return "blob:" + hashlib.sha1(b"blob %d\0" % len(b) + b).hexdigest()
    return "dir" if os.path.isdir(p) else "absent"
def papers():
    # examine's papers beside the copy (S2): {file: its text}
    d = os.path.join("..", "papers")
    return {n: open(os.path.join(d, n)).read() for n in sorted(os.listdir(d))} if os.path.isdir(d) else None
def door(host=b"example.invalid"):
    # one CONNECT through the proxy the environment names: its log says whether research was on
    try:
        hp = os.environ["HTTPS_PROXY"].rsplit(":", 1)
        s = socket.create_connection((hp[0].split("//")[1], int(hp[1])), timeout=5)
        s.sendall(b"CONNECT " + host + b":443 HTTP/1.1\r\n\r\n"); out = s.recv(200).decode().split("\r\n")[0]; s.close()
        return out
    except (OSError, KeyError, IndexError, ValueError) as e:
        return type(e).__name__
# the first request to the vendor, as claude -p makes it (F7: the proxy withdraws the login there)
vendor = None if os.environ.get("STUB_NO_VENDOR") else door(b"api.anthropic.com")
prompt = sys.stdin.read()
tools = a[a.index("--tools") + 1].split(",") if "--tools" in a else []
cfg = os.environ.get("CLAUDE_CONFIG_DIR", "")
obs = {"type": "stub", "cwd": os.getcwd(), "argv": a, "prompt": prompt, "env": sorted(os.environ), "home": os.environ.get("HOME"),
       "cfg": cfg, "cfg_files": sorted(os.listdir(cfg)) if cfg and os.path.isdir(cfg) else None,
       "proxy": os.environ.get("HTTPS_PROXY"), "agents": os.path.isfile("AGENTS.md"), "git": os.path.isdir(".git"),
       "calls_outside": calls("claude arm cwd=%s" % os.getcwd()), "copy_write": trywrite("w.txt"),
       "file_write": trywrite("AGENTS.md"), "papers": papers(),
       "look": {p: look(p) for p in os.environ.get("STUB_LOOK", "").split(":") if p},
       "cfg_write": trywrite(os.path.join(cfg, "settings.json")) if cfg else None, "door": door(),
       "pipe": len(TOKEN), "vendor": vendor is not None,
       "reads": {p: tryread(p) for p in os.environ.get("STUB_READS", "").split(":") if p}}
ev = lambda d: print(json.dumps(d))
ev({"type": "system", "subtype": "init", "tools": tools, "mcp_servers": []})
ev(obs)
if os.environ.get("STUB_FENCES"):
    sys.stdout.flush()
    subprocess.run([sys.executable, os.path.join(os.path.dirname(sys.argv[0]), "fences_events.py"), "claude", os.environ["STUB_FENCES"]])
for name in filter(None, os.environ.get("STUB_CLAUDE_USE", "").split(",")):
    ev({"type": "assistant", "message": {"content": [{"type": "tool_use", "name": name, "input": {"command": "ls"}}]}})
mode = os.environ.get("STUB_CLAUDE", "ok")
text, err = "PAPER from claude", False
if mode == "empty":
    text = ""
elif mode == "error":
    err = True
elif mode == "token":
    text = "PAPER from claude, quoting " + "sk-" + "ant-oat01-STANDINSTANDINSTANDIN"
elif mode == "leak":
    text = "PAPER from claude, quoting its own login: " + TOKEN
elif mode == "ssh":
    r = tryread(os.environ["STUB_SSH"])
    text, err = ("PAPER: " + r, False) if r.startswith("read:") else ("could not read the key: " + r, True)
ev({"type": "result", "is_error": err, "result": text, "total_cost_usd": 0.5, "modelUsage": {"claude-opus-5-5": {"inputTokens": 1}},
    "permission_denials": [{"tool_name": "Grep"}]})
PY
cat > "$T/bin/codex" <<'SH'
#!/bin/sh
# codex 0.162.1's listings and exec --json's events (OpenAI's documented names); the prompt on stdin when argv ends in "-"
[ "$1" = --version ] && { echo "codex-cli 0.999.0"; exit 0; }
case "$1 $2" in
  "login status") echo "Logged in using ChatGPT"; exit 0;;
  "plugin list") echo "codex plugin list CODEX_HOME=${CODEX_HOME:-}" >> "$STUB_CALLS"; exit 0;;
  "features list") cat "$STUB_FEATURES"; exit 0;;
esac
in=$(cat)
# its login read at the start, then its first request to chatgpt.com through the proxy (F7 withdraws it there);
# STUB_CODEX_REWRITE writes it back after, as a token refresh would
auth_before=no; [ -f "$CODEX_HOME/auth.json" ] && auth_before=yes
[ -z "${STUB_NO_VENDOR:-}" ] && python3 -c 'import os, socket
h, p = os.environ["HTTPS_PROXY"].split("//")[1].rsplit(":", 1)
s = socket.create_connection((h, int(p)), timeout=5); s.sendall(b"CONNECT chatgpt.com:443 HTTP/1.1\r\n\r\n"); s.recv(200); s.close()' 2>/dev/null
auth_after=no; [ -f "$CODEX_HOME/auth.json" ] && auth_after=yes
[ -n "${STUB_CODEX_REWRITE:-}" ] && printf '{"tokens": {"access_token": "%s"}}' STANDIN-CODEX-ACCESS-TOKEN-1 > "$CODEX_HOME/auth.json"
review=""; case " $* " in *" review --base "*) review=1;; esac
rv=""; [ -n "$review" ] && rv="log=$(git log --format=%s tip | tr '\n' '|') diff=$(git diff --name-only base tip | tr '\n' '|') modes=$(git diff --summary base tip | grep -c 'mode change') status=$(git status --porcelain | wc -l | tr -d ' ') wt=$(git diff --name-only base | tr '\n' '|') vendor=[$(ls -d .codex 2>/dev/null)]"
python3 -c 'import json, os, sys
print(json.dumps({"type": "stub", "cwd": os.getcwd(), "argv": sys.argv[1], "stdin": sys.argv[2], "review": sys.argv[3],
                  "env": {k: os.environ.get(k) for k in ("CODEX_HOME", "HOME", "HTTPS_PROXY", "GIT_CONFIG_GLOBAL", "GIT_CONFIG_NOSYSTEM")},
                  "names": sorted(os.environ), "auth": [sys.argv[4], sys.argv[5]]}))' "$*" "$in" "$rv" "$auth_before" "$auth_after"
echo '{"type":"thread.started","thread_id":"th-council-'"$$"'"}'
echo '{"type":"turn.started"}'
[ -z "${STUB_CODEX_TEXT:-}" ] && echo '{"type":"item.completed","item":{"id":"c1","type":"command_execution","command":"/bin/zsh -lc '"'"'sed -n 1,5p AGENTS.md'"'"'","exit_code":0,"status":"completed"}}'
[ -n "${STUB_FENCES:-}" ] && python3 "$(dirname "$0")/fences_events.py" codex "$STUB_FENCES"
[ -n "${STUB_CODEX_ITEM:-}" ] && echo '{"type":"item.completed","item":{"id":"x1","type":"'"$STUB_CODEX_ITEM"'"}}'
if [ -n "$review" ]; then
  echo '{"type":"turn.completed","usage":{"input_tokens":0,"cached_input_tokens":0,"output_tokens":0}}'
  echo '{"type":"item.completed","item":{"id":"i1","type":"agent_message","text":"PAPER from codex"}}'
  exit 0
fi
echo '{"type":"turn.completed","usage":{"input_tokens":10,"cached_input_tokens":4,"output_tokens":2}}'
if [ -n "${STUB_CODEX_LONG:-}" ]; then
  python3 -c 'import json; print(json.dumps({"type":"item.completed","item":{"id":"i1","type":"agent_message","text":"# 1. Recommendation HEAD-MARK " + "x" * 9000 + " TAIL-MARK"}}))'
else echo '{"type":"item.completed","item":{"id":"i1","type":"agent_message","text":"PAPER from codex"}}'; fi
echo '{"type":"turn.completed","usage":{"input_tokens":10,"cached_input_tokens":4,"output_tokens":3}}'
SH
cat > "$T/bin/agy" <<'PY'
#!/usr/bin/env python3
# agy 1.4.10's stream-json, cut down to the events council reads (the S0 probes' shapes): the one message on stdin,
# an init naming the model, a tool step per tool the model reached for, the result
import json, os, subprocess, sys
if sys.argv[1:] == ["--version"]:
    print("1.4.99")
    sys.exit(0)
line = sys.stdin.readline()
text = json.loads(line)["message"]["content"][0]["text"] if line.strip() else ""
h = os.environ.get("HOME", "")
def kc(service, account):
    # by length, never the value: a stand-in that printed its secret into its log would fail its arm (F7's scan)
    r = subprocess.run(["/usr/bin/security", "find-generic-password", "-s", service, "-a", account, "-w"], capture_output=True, text=True)
    return "found:%d" % len(r.stdout.strip()) if r.stdout.strip() else "not found"
def hook(tool, shape):
    try:
        cmd = json.load(open(os.path.join(h, ".gemini", "config", "hooks.json")))["council"]["PreToolUse"][0]["hooks"][0]["command"]
        body = {"tool_name": tool} if shape == "1.4.10" else {"toolCall": {"name": tool, "args": {}}}
        r = subprocess.run(["/bin/sh", "-c", cmd], input=json.dumps(body), capture_output=True, text=True)
        return json.loads(r.stdout)["decision"]
    except (OSError, ValueError, KeyError, IndexError) as e:
        return type(e).__name__
def vendor():
    # agy's first request to its vendor through the proxy (F7 withdraws the per-run keychain there)
    import socket
    try:
        hp = os.environ["HTTPS_PROXY"].split("//")[1].rsplit(":", 1)
        s = socket.create_connection((hp[0], int(hp[1])), timeout=5)
        s.sendall(b"CONNECT daily-cloudcode-pa.googleapis.com:443 HTTP/1.1\r\n\r\n"); s.recv(200); s.close()
    except (OSError, KeyError, IndexError, ValueError):
        pass
def trywrite(p):
    try:
        with open(p, "a"):
            return "wrote"
    except OSError as e:
        return type(e).__name__
ev = lambda name, body: print(json.dumps({"event": name, name: body}))
model = sys.argv[sys.argv.index("--model") + 1] if "--model" in sys.argv else "gemini-default"
ev("init", {"model": model, "cwd": os.getcwd(),
            "tools": ["list_dir", "run_command", "call_mcp_tool"] + list(filter(None, os.environ.get("STUB_AGY_TOOLS", "").split(",")))})
item = kc("gemini", "antigravity")
if not os.environ.get("STUB_NO_VENDOR"):
    vendor()
print(json.dumps({"type": "stub", "cwd": os.getcwd(), "argv": sys.argv[1:], "stdin": text, "home": h, "names": sorted(os.environ),
                  "agy_item": item, "agy_item_after": kc("gemini", "antigravity"),
                  "claude_item": kc("Claude Code-credentials", os.environ.get("USER", "")),
                  "hook": {"%s %s" % (t, v): hook(t, v) for t in ("run_command", "call_mcp_tool") for v in ("1.4.10", "1.4.11")},
                  "hooks_write": trywrite(os.path.join(h, ".gemini", "config", "hooks.json")),
                  # agy 1.4.12 writes its refreshed sign-in here (S4's live run): refused to the arm
                  "token_write": trywrite(os.path.join(h, ".gemini", "antigravity-cli", "antigravity-oauth-token"))}))
mode = os.environ.get("STUB_AGY", "ok")
deny = "{'type': 'TOOL_ERROR', 'message': \"tool call denied by pre-tool hook: not in the council arm's tool set\"}"
steps = {"empty": [("browser_get_dom", "ERROR", deny), ("generate_image", "ERROR", deny)],
         "ran": [("list_dir", "DONE", ""), ("call_mcp_tool", "DONE", "")], "denied": [("browser_get_dom", "ERROR", deny)]}.get(mode, [])
if os.environ.get("STUB_FENCES"):
    sys.stdout.flush()
    fm = "bad" if os.environ.get("STUB_AGY_BAD_MODEL") == model else os.environ["STUB_FENCES"]
    subprocess.run([sys.executable, os.path.join(os.path.dirname(sys.argv[0]), "fences_events.py"), "agy", fm])
for i, (name, state, err) in enumerate(steps, 1):
    ev("step_update", {"step_index": i, "state": "ACTIVE", "step_type": "tool", "tool_name": name})
    ev("step_update", {"step_index": i, "state": state, "step_type": "tool", "tool_name": name, "tool_info": {"error": err} if err else {}})
ev("result", {"conversation_id": "cv-1", "status": "SUCCESS", "response": "" if mode == "empty" else "PAPER from gemini",
              "duration_seconds": 1.0, "num_turns": 1, "usage": {"input_tokens": 80, "output_tokens": 20, "total_tokens": 100}})
PY
cat > "$T/bin/account" <<'SH'
#!/bin/sh
# lighthouse's account: `which` names the login, `allowed PATH` is account_guard's question (STUB_DENY refuses)
case "$1" in
  which) echo acct-sam;;
  pick) # the vendor fence's question (common.vendor_refusal): STUB_PICK_FOREIGN names a login the tenant does not own
        if [ -n "${STUB_PICK_FOREIGN:-}" ]; then echo '{"account": "acct-other", "owns": false}'; else echo '{"account": "acct-sam", "owns": true}'; fi;;
  allowed) echo "account allowed $2 cfg=${CLAUDE_CONFIG_DIR:-}" >> "${STUB_CALLS:-$CALLS}"
           [ -z "${STUB_DENY:-}" ] || { echo "$2 is off acct-sam (accounts.json deny list)"; exit 1; };;
esac
SH
printf '#!/bin/sh\n[ "$1" = --cap ] && echo "${STUB_CAP:-6}"\n' > "$T/bin/dispatch"
printf '#!/bin/sh\nexit 1\n' > "$T/bin/no-account"
# council fences' commands as each CLI's log shows them run (S5): canned outputs, so no case needs the network.
# MODE ok: every case holds; bad: /private/tmp lists; loopback: the SSH port answers; short: five of nine run;
# ran: the denied tool ran (Claude's Agent, a Codex sub-agent item, agy's generate_image undenied); refused:
# Claude's Agent asked for and refused by claude itself
cat > "$T/bin/fences_events.py" <<'PY'
import json, os, pwd, shlex, sys
cli, mode = sys.argv[1], sys.argv[2]
# the login's own home, as council's cases name it (finding 12: never ~, the arm's scratch HOME)
LH = os.path.realpath(pwd.getpwuid(os.getuid()).pw_dir)
cases = [("ls .", 0, "AGENTS.md\ndocs"), ("head -1 /etc/hosts", 0, "##"),
         ("head -c 40 %s" % shlex.quote(LH + "/.ssh/known_hosts"), 1, "head: known_hosts: Operation not permitted"),
         ("ls %s" % shlex.quote(LH + "/projects"), 1, "ls: projects: Operation not permitted"),
         ('curl -sS -m 8 -o /dev/null -w "%{http_code}" https://example.com/', 0, "200"),
         ('curl -sS -m 4 -o /dev/null -w "%{http_code}" http://127.0.0.1:22/', 0, "403"),
         ("ls /private/tmp", 1, "ls: /private/tmp: Operation not permitted"),
         ("touch ./probe-wrote && echo wrote", 0, "wrote"),
         ("ls /Library/Preferences", 1, "ls: /Library/Preferences: Operation not permitted")]
if mode == "bad":
    cases[6] = ("ls /private/tmp", 0, "com.apple.launchd.x")
if mode == "loopback":
    cases[5] = (cases[5][0], 1, "curl: (1) Received HTTP/0.9 when not allowed")
if mode == "short":
    cases = cases[:5]
ev = lambda d: print(json.dumps(d))
deny = "{'type': 'TOOL_ERROR', 'message': \"tool call denied by pre-tool hook: not in the council arm's tool set\"}"
for i, (cmd, code, out) in enumerate(cases, 1):
    if cli == "claude":
        ev({"type": "assistant", "message": {"content": [{"type": "tool_use", "id": "tu%d" % i, "name": "Bash", "input": {"command": cmd}}]}})
        ev({"type": "user", "message": {"content": [{"type": "tool_result", "tool_use_id": "tu%d" % i, "is_error": code != 0,
                                                      "content": out if code == 0 else "Exit code %d\n%s" % (code, out)}]}})
    elif cli == "codex":
        ev({"type": "item.completed", "item": {"id": "f%d" % i, "type": "command_execution", "command": "/bin/zsh -lc '%s'" % cmd,
                                               "aggregated_output": out + "\n", "exit_code": code, "status": "completed"}})
    else:
        ev({"event": "step_update", "step_update": {"step_index": 100 + i, "state": "ACTIVE", "step_type": "tool", "tool_name": "run_command"}})
        ev({"event": "step_update", "step_update": {"step_index": 100 + i, "state": "DONE", "step_type": "tool", "tool_name": "run_command",
            "tool_info": {"name": "run_command", "parameters": {"CommandLine": cmd},
                          "output": "Command exited with code %d.\n\nCommand output:\n%s\r\n" % (code, out)}}})
if cli == "claude" and mode in ("ran", "refused"):
    ev({"type": "assistant", "message": {"content": [{"type": "tool_use", "id": "tuA", "name": "Agent", "input": {"prompt": "ls ."}}]}})
    ev({"type": "user", "message": {"content": [{"type": "tool_result", "tool_use_id": "tuA", "is_error": mode == "refused",
        "content": "<tool_use_error>Error: No such tool available: Agent. Agent is disabled for this session</tool_use_error>" if mode == "refused" else "a sub-agent ran"}]}})
if cli == "codex" and mode == "ran":
    ev({"type": "item.completed", "item": {"id": "fA", "type": "collab_tool_call"}})
if cli == "agy" and not os.environ.get("STUB_AGY_UNTRIED"):
    ran = mode == "ran"
    ev({"event": "step_update", "step_update": {"step_index": 200, "state": "DONE" if ran else "ERROR", "step_type": "tool",
        "tool_name": "generate_image", "tool_info": {} if ran else {"error": deny}}})
PY
chmod +x "$T/bin/claude" "$T/bin/codex" "$T/bin/agy" "$T/bin/account" "$T/bin/dispatch" "$T/bin/no-account"
C() { python3 "$B/council" "$@"; }
lastrun() { ls -dt "$T/runs"/council-* 2>/dev/null | head -1; }   # newest by mtime: two runs in one second sort by their suffix
nruns() { ls "$T/runs" | wc -l | tr -d ' '; }
council_py() {   # council_py <python using module c> [arg…]: bin/council loaded as a module, the args from sys.argv[3]
  python3 - "$B/council" "$@" <<'PY'
import sys
from importlib.machinery import SourceFileLoader
c = SourceFileLoader("council", sys.argv[1]).load_module()
exec(sys.argv[2])
PY
}
events_of() { jget "$1/arms/codex/raw.json" 'd["events"]'; }

echo "the rows: wharf's own table, through the core's gate"
check "$(python3 -c "
import sys; from importlib.machinery import SourceFileLoader as L
g = L('gate', '$M/../regatta/bin/gate').load_module(); t = g.module_table('wharf')
print(t == '$M/settings/models.json', [g.resolve('council.' + a, table=t) and g.resolve('council.' + a, table=t)['provider'] for a in ('opus', 'codex', 'antigravity', 'antigravity-claude')], g.resolve('council.antigravity', table=t)['model'])")" \
  "True ['claude', 'codex', 'antigravity', None] gemini-3.8-flash-high" "four rows in modules/wharf/settings/models.json; antigravity-claude off; Gemini 3.8 Flash High"
mkdir -p "$REGATTA_CONFIG/wharf"; cp "$M/settings/models.json" "$REGATTA_CONFIG/wharf/models.json"
check "$(python3 -c "
from importlib.machinery import SourceFileLoader as L
print(L('gate', '$M/../regatta/bin/gate').load_module().module_table('wharf'))")" "$REGATTA_CONFIG/wharf/models.json" "  the config dir's wharf/models.json wins over the module's"
rm -rf "$REGATTA_CONFIG/wharf"

if [ -z "$FENCE" ]; then
  echo "off macOS: no seatbelt, every arm refused (the isolation design's S6 brings a guest)"
  C run --home "$H" --brief "$T/brief.md" --json > /dev/null 2>"$T/err"; check "$?" 1 "run exits 1: no arm ran"
  R=$(lastrun)
  check "$(jget "$R/run.json" '[d["arms"][a]["state"] for a in ("opus", "codex", "antigravity", "antigravity-claude")]')" \
    "['refused', 'refused', 'refused', 'off']" "  each arm on refused, the off arm off"
  check "$(jget "$R/run.json" '"no seatbelt" in d["arms"]["opus"]["why"]')" "True" "  saying why"
  C examine --run "$R" --draft "$T/draft.md" > /dev/null 2>&1; check "$?" 2 "  examine: no arm answered, refused"
  C review --home "$H" > /dev/null 2>&1; check "$?" 1 "  review: its arm refused"
  n0=$(nruns); C fences --home "$H" > "$T/fences-off.txt" 2>&1; check "$?" 2 "  fences (S5): refused, exit 2"
  check "$(grep -c 'refused .*no seatbelt here.*until a guest' "$T/fences-off.txt")" 3 "  every arm of the three refused, saying why"
  check "$(nruns)" "$n0" "  no run dir made, no CLI started"
  check "$([ -e "$T/fences-state.json" ] && echo written || echo none)" none "  no verdict written"
else
echo "run: every arm under the seatbelt, each in its own box"
: > "$CALLS"
SSH_AUTH_SOCK=/tmp/agent.sock ORCA_PANE_KEY=p1 CLAUDE_CODE_MESSAGING_SOCKET=/tmp/m.sock \
  C run --home "$H" --brief "$T/brief.md" --files docs/note.md --json > "$T/run.json" 2>"$T/err"; rc=$?
R=$(lastrun)
check "$rc" 0 "run exits 0"
check "$(jget "$R/run.json" '[d["arms"][a]["state"] for a in ("opus", "codex", "antigravity", "antigravity-claude")]')" \
  "['ok', 'ok', 'ok', 'off']" "opus, codex and gemini answer; the Anthropic arm through Antigravity is off"
check "$(jget "$R/run.json" 'd["commit"] == "'"$(git -C "$H" rev-parse main)"'"')" "True" "  the copy is main's commit"
check "$(mode_of "$R")/$([ -f "$R/.council-run" ] && echo marked)" "0o700/marked" "  the run dir is the owner's alone (0700) and marked for sheep_gate"
check "$(ls -d "$R"/*/*/box 2>/dev/null | wc -l | tr -d ' ')/$([ -f "$R/run.json" ] && [ -f "$R/brief.md" ] && echo kept)" "0/kept" \
  "  every box (copy, scratch home, keychain) removed when the verb ends; run.json, the brief, the papers and logs kept"
check "$(cat "$R/arms/opus/paper.md")/$(cat "$R/arms/codex/paper.md")/$(cat "$R/arms/antigravity/paper.md")" \
  "PAPER from claude/PAPER from codex/PAPER from gemini" "  each paper written"
CL="$R/arms/opus/claude.jsonl"
check "$(stub "$CL" 'd["cwd"]')" "$R/arms/opus/box/copy" "the Claude arm runs in its box's copy"
check "$(stub "$CL" '(d["agents"], d["git"], d["copy_write"], d["file_write"])')" "(True, False, 'wrote', 'wrote')" \
  "  the copy holds the repo, no .git, and the arm writes there, its files included (S2: no longer read-only)"
check "$(stub "$CL" '[x for x in ("--restricted", "--strict-mcp-config", "--setting-sources", "--allowedTools", "stream-json") if x in d["argv"]]')" \
  "['--strict-mcp-config', '--setting-sources', '--allowedTools', 'stream-json']" "  no --restricted; MCP off, user settings only (its scratch dir's), stream-json for the record"
check "$(stub "$CL" 'd["argv"][d["argv"].index("--tools") + 1]')" "Bash,Read,Glob,Grep,Write,Edit" \
  "  every working tool, Bash among them (\`claude mcp list\` names Anthropic's docs connector only); no web tool with --research off (finding 10)"
has "$CALLS" "claude mcp list cwd=$R/arms/opus/box/copy cfg=$R/arms/opus/$BH/.claude pipe=29" "  the MCP gate asked under the scratch config dir, in the copy, the login on its pipe"
check "$(stub "$CL" '(d["home"], d["cfg_files"], d["pipe"], d["vendor"])')" "('$R/arms/opus/box/home', ['.claude.json'], 29, True)" \
  "  a scratch HOME and config dir holding no login: the access token came on a pipe (F7)"
check "$(jget "$R/run.json" '(d["arms"]["opus"]["f7"]["pipe"], d["arms"]["opus"]["f7"]["withdrawn"]["host"], d["arms"]["opus"]["f7"]["files_holding_it"])')" \
  "('CLAUDE_CODE_OAUTH_TOKEN_FILE_DESCRIPTOR', 'api.anthropic.com', 0)" "  F7's record: on a pipe, the first vendor request seen, no file holding it"
check "$(stub "$CL" '[n for n in ("SSH_AUTH_SOCK", "ORCA_PANE_KEY", "CLAUDE_CODE_MESSAGING_SOCKET", "CALLS", "CLAUDECODE", "GIT_CONFIG_GLOBAL") if n in d["env"]]')" "[]" \
  "  its environment an allowlist: no ssh agent, Orca pane, messaging socket or caller's variable"
check "$(stub "$CL" '(d["calls_outside"], d["cfg_write"], d["proxy"].startswith("http://127.0.0.1:"))')" "(False, 'PermissionError', True)" \
  "  under the seatbelt: no write outside its box, none to its own settings.json; its door the proxy"
check "$(stub "$CL" 'd["door"]')/$(python3 -c 'import json,sys; print([(e["host"], e["ok"], e["why"]) for e in map(json.loads, open(sys.argv[1])) if e.get("host") == "example.invalid"])' "$R/arms/opus/proxy.jsonl")" \
  "HTTP/1.1 403 Forbidden/[('example.invalid', False, \"not the CLI's vendor host and research is off\")]" \
  "  a host not the vendor's refused at the door, research off; the proxy's log is council's, beside the box"
check "$(stub "$CL" '"Named files (start there): docs/note.md" in d["prompt"] and "Do not use any tools" not in d["prompt"]')" "True" \
  "  the brief and the named files by name: it reads the copy"
check "$(stub "$CL" 'd["argv"][d["argv"].index("--agent"):d["argv"].index("--agent") + 6]')" \
  "['--agent', 'principal-arm', '--model', 'claude-opus-5-5', '--effort', 'high']" "  its own agent, the row's model and effort"
has "$CALLS" "account allowed $H cfg=" "  its login's tenancy asked first: account allowed, the home's checkout"
AG="$R/arms/antigravity/agy.jsonl"
check "$(stub "$AG" 'd["cwd"]')" "$R/arms/antigravity/box/copy" "the Gemini arm reads a copy like the others"
check "$(stub "$AG" '[x for x in ("--dangerously-skip-permissions", "--disable-slash-commands", "--sandbox", "--mode", "--print-timeout") if x in d["argv"]]')" \
  "['--dangerously-skip-permissions', '--disable-slash-commands', '--print-timeout']" "  tools on: skip-permissions, no --sandbox or plan mode (our hook is its list)"
check "$(stub "$AG" '(d["home"], d["agy_item"], d["claude_item"])')" "('$R/arms/antigravity/box/home', 'found:17', 'not found')" \
  "  a scratch HOME whose per-run keychain holds agy's item and not the login's Claude one (P3)"
check "$(stub "$AG" 'd["agy_item_after"]')/$(jget "$R/run.json" '(d["arms"]["antigravity"]["f7"]["withdrawn"]["ok"], d["arms"]["antigravity"]["f7"]["withdrawn"]["host"])')" \
  "not found/(True, 'daily-cloudcode-pa.googleapis.com')" "  after its first vendor request the per-run keychain is gone (F7)"
check "$(stub "$AG" '(sorted(d["hook"].items()), d["hooks_write"])')" \
  "([('call_mcp_tool 1.4.10', 'deny'), ('call_mcp_tool 1.4.11', 'deny'), ('run_command 1.4.10', 'allow'), ('run_command 1.4.11', 'allow')], 'PermissionError')" \
  "  our hook answers inside the seatbelt, in either agy's shape; hooks.json read-only to the arm"
check "$(stub "$AG" 'd["token_write"]')/$(jget "$R/run.json" 'd["arms"]["antigravity"]["f7"]["files_holding_it"]')" "PermissionError/0" \
  "  agy 1.4.12's token file (antigravity-oauth-token) refused to the arm, so no sign-in lands beside its state (S4)"
check "$(stub "$AG" 'd["stdin"].startswith("You are one arm") and "Named files (start there): docs/note.md" in d["stdin"]')" "True" \
  "  the paper prompt on stdin as one stream-json message (never argv), no no-tools line"
check "$(jget "$R/run.json" '(d["arms"]["antigravity"]["cost"]["tokens"], d["arms"]["antigravity"]["observed"]["model"])')" "(100, 'gemini-3.8-flash-high')" \
  "  its tokens recorded; the model read back from agy's init event"
EV=$(events_of "$R")
check "$(stub "$EV" 'd["cwd"]')" "$R/arms/codex/box/copy" "the Codex arm: its shell, in its copy (no road: F7 fences the account's connectors)"
check "$(stub "$EV" '[x for x in ("--dangerously-bypass-approvals-and-sandbox", "--disable apps", "--disable plugins", "--disable multi_agent", "--disable memories", "--disable shell_tool", "permissions.research", "--approve-for-me") if x in d["argv"]]')" \
  "['--dangerously-bypass-approvals-and-sandbox', '--disable apps', '--disable plugins', '--disable multi_agent', '--disable memories']" \
  "  its own sandbox off (ours holds it), the connectors, sub-agents and memory off, its shell on"
check "$(stub "$EV" '(d["env"]["CODEX_HOME"], d["env"]["HOME"], d["env"]["HTTPS_PROXY"].startswith("http://127.0.0.1:"), "SSH_AUTH_SOCK" in d["names"])')" \
  "('$R/arms/codex/$BH/.codex', '$R/arms/codex/box/home', True, False)" "  a scratch CODEX_HOME, the proxy, an allowlisted environment"
check "$(stub "$EV" '"shell_environment_policy.set={HTTPS_PROXY=" in d["argv"]')" "True" "  the proxy set into its shell too (P2)"
check "$(stub "$EV" "'web_search=\"disabled\"' in d[\"argv\"]")" "True" \
  "  Codex's own web search off with --research off: it runs at OpenAI, past the proxy (the fourth landing review, finding 10)"
hasnt "$CALLS" "codex plugin list" "  \`codex plugin list\` never asked"
check "$(jget "$R/run.json" '(d["arms"]["codex"]["cost"]["usage"]["input_tokens"], d["arms"]["codex"]["record"]["tools"])')" \
  "(20, {'command_execution': 1, 'agent_message': 1})" "  usage summed over both turn.completed; F5 counts its items"
check "$(stub "$EV" 'd["auth"]')/$(jget "$R/run.json" '(d["arms"]["codex"]["f7"]["withdrawn"]["ok"], d["arms"]["codex"]["f7"]["withdrawn"]["host"], d["arms"]["codex"]["f7"]["at_first_tool"], d["arms"]["codex"]["f7"]["files_holding_it"])')" \
  "['yes', 'no']/(True, 'chatgpt.com', [], 0)" "  F7: auth.json there at its start, gone after its first request to chatgpt.com; nothing on disk at the first command, no file holding it"

echo "receipt"
C receipt --run "$R" > "$T/receipt.md"
has "$T/receipt.md" "| Arm (login) | Requested / observed | Cost | Caught | State |" "the Receipt's table"
has "$T/receipt.md" "| opus (acct-sam) | claude-opus-5-5 \`high\` / claude-opus-5-5, effort not reported by claude -p | \$0.50" \
  "  the Claude arm: its login read back (account which), requested and observed, its cost as list and effective"
has "$T/receipt.md" "| antigravity (unknown) | gemini-3.8-flash-high / gemini-3.8-flash-high, effort not reported by agy | 100 tokens (plan, list price not read)" \
  "  the Gemini arm: what agy does not say is said so, not guessed"
has "$T/receipt.md" "| codex (Logged in using ChatGPT) | default \`xhigh\` / not reported by codex exec, effort not reported by codex exec |" \
  "  the Codex arm: \`codex login status\` read back; codex exec names no model or effort"
has "$T/receipt.md" "| antigravity-claude (—) |" "  the off arm is a row"
has "$T/receipt.md" "Completion: **complete** — 3 arms answered" "  three arms answered: complete"
has "$T/receipt.md" "- codex: tools agent_message 1, command_execution 1; through the proxy: chatgpt.com" "  what each arm did, from its own log (F5)"
has "$T/receipt.md" "first commands: \`/bin/zsh -lc 'sed -n 1,5p AGENTS.md'\`" "  its first commands"
has "$T/receipt.md" "- opus: tools none; through the proxy: api.anthropic.com" "  and the hosts its proxy let through or refused"
has "$T/receipt.md" "example.invalid (refused); login on a pipe, never on disk" "  and where its login was (F7)"
has "$T/receipt.md" "; login withdrawn at chatgpt.com; first commands:" "  the Codex arm's withdrawn at its first vendor request"
has "$T/receipt.md" "Each CLI's own \`--version\`, read as its arm started: opus 2.1.999 (Claude Code); codex codex-cli 0.999.0; antigravity 1.4.99." \
  "  each CLI's own --version, read as its arm started (finding 15)"
check "$(jget "$R/run.json" '[d["arms"][a].get("version") for a in ("opus", "codex", "antigravity", "antigravity-claude")]')" \
  "['2.1.999 (Claude Code)', 'codex-cli 0.999.0', '1.4.99', None]" "  and in run.json, per arm (none for the off arm)"
check "$(council_py 'import os, stat
p = os.path.join(sys.argv[3], "noversion"); open(p, "w").write("#!/bin/sh\necho hello; exit 3\n"); os.chmod(p, 0o755)
print(c.cli_version(p))' "$T/bin")" "unknown (\`--version\` exit 3, no version number)" "  a CLI whose --version says nothing usable: unknown, with why, never a guess"
check "$(COUNCIL_ACCOUNT="$T/bin/no-account" council_py 'print(c.claude_login(None))')" "sam@example.com" \
  "  no label: the login's own .claude.json, read back"

echo "F7: the login off the disk"
STUB_CODEX_PLUGINS="gmail google-drive" C run --home "$H" --brief "$T/brief.md" --files docs/note.md --arms codex > /dev/null 2>&1
check "$?" 0 "the Codex arm keeps its shell, whatever the account holds (the owner keeps the connectors: F7 is the fence)"
R=$(lastrun); EV=$(events_of "$R")
check "$(stub "$EV" '(d["cwd"], "--disable shell_tool" in d["argv"], "Do not use any tools" in d["stdin"], "--text-only" in d["argv"])')" \
  "('$R/arms/codex/box/copy', False, False, False)" "  in its copy, no text-only road left"
STUB_CODEX_REWRITE=1 C run --home "$H" --brief "$T/brief.md" --arms codex > /dev/null 2>&1; check "$?" 0 "a login written back after the withdrawal: the kernel refuses the write (auth.json read-only to the arm since S5's review)"
R=$(lastrun); check "$(jget "$R/run.json" '(d["arms"]["codex"]["state"], d["arms"]["codex"]["f7"]["at_first_tool"], d["arms"]["codex"]["f7"]["files_holding_it"])')" \
  "('ok', [], 0)" "  nothing of the login on disk at the first command, nor left"
check "$(grep -c 'auth.json' "$R/arms/codex/arm.sb")" 1 "  harness's profile names the scratch home's read-only files"
STUB_NO_VENDOR=1 C run --home "$H" --brief "$T/brief.md" --arms codex > /dev/null 2>&1; check "$?" 1 "a Codex arm that ran a command with no vendor request first: fails"
R=$(lastrun); check "$(jget "$R/run.json" '"never withdrawn" in d["arms"]["codex"]["why"]')" "True" "  the login was never withdrawn"
STUB_NO_VENDOR=1 STUB_CLAUDE_USE=Bash C run --home "$H" --brief "$T/brief.md" --arms opus > /dev/null 2>&1; check "$?" 1 "  the Claude arm likewise"
STUB_CLAUDE=leak C run --home "$H" --brief "$T/brief.md" --arms opus > /dev/null 2>&1; check "$?" 1 "a Claude arm whose paper quotes its own login: fails"
R=$(lastrun); check "$(jget "$R/run.json" '(d["arms"]["opus"]["state"], "(F7)" in d["arms"]["opus"]["why"], d["arms"]["opus"]["f7"]["files_holding_it"] >= 1)')/$([ -f "$R/arms/opus/paper.md" ] && echo paper || echo none)" \
  "('failed', True, True)/none" "  its log names the file, and the paper is withheld"
check "$(grep -rl STANDIN-CLAUDE-KEYCHAIN-TOKEN "$R" | sed "s|$R/||" | tr '\n' ' ')/$(grep -l 'login withdrawn: F7' "$R/arms/opus/claude.jsonl" | sed "s|$R/||")" "/arms/opus/claude.jsonl" \
  "  the token is in no file of the run: the CLI's own log, which F7 named, rewritten without it (round 5b)"
STUB_NO_VENDOR=1 STUB_AGY=denied C run --home "$H" --brief "$T/brief.md" --arms antigravity > /dev/null 2>&1; check "$?" 1 "an agy arm whose tool step came with no vendor request: fails"
R=$(lastrun); check "$(jget "$R/run.json" '"never withdrawn" in d["arms"]["antigravity"]["why"]')" "True" "  the login was never withdrawn"
cat "$STUB_FEATURES" > "$T/features2.txt"; printf '%-40s stable             true\n' remote_control >> "$T/features2.txt"
STUB_FEATURES="$T/features2.txt" C run --home "$H" --brief "$T/brief.md" --arms codex > /dev/null 2>&1; check "$?" 1 "a feature on that no one judged: the Codex arm refused"
R=$(lastrun); check "$(jget "$R/run.json" '(d["arms"]["codex"]["state"], "remote_control" in d["arms"]["codex"]["why"])')" "('refused', True)" "  naming it"

echo "Claude's Bash fenced by the account (S0's amendment)"
STUB_CLAUDE_MCP=Gmail C run --home "$H" --brief "$T/brief.md" --arms opus > /dev/null 2>&1; check "$?" 0 "the Claude arm answers"
R=$(lastrun); check "$(stub "$R/arms/opus/claude.jsonl" 'd["argv"][d["argv"].index("--tools") + 1]')/$(jget "$R/run.json" 'd["arms"]["opus"]["gate"]["claude mcp list"]')" \
  "Read,Glob,Grep,Write,Edit/['Gmail']" "  without Bash while \`claude mcp list\` names an account's connector"

echo "a failed arm is never a blank row (F5 among the reasons)"
STUB_AGY=empty C run --home "$H" --brief "$T/brief.md" --arms antigravity --json > /dev/null 2>&1; check "$?" 1 "agy's empty SUCCESS: the run fails (its one arm failed)"
R=$(lastrun)
check "$(jget "$R/run.json" '(d["arms"]["antigravity"]["state"], d["arms"]["antigravity"]["denied"])')" "('failed', ['browser_get_dom', 'generate_image'])" \
  "  failed, with the steps our hook denied (read back by its reason)"
[ -f "$R/arms/antigravity/paper.md" ]; check "$?" 1 "  no paper"
C receipt --run "$R" | grep -q "Completion: \*\*incomplete\*\*"; check "$?" 0 "  the Receipt: incomplete"
STUB_AGY=ran C run --home "$H" --brief "$T/brief.md" --arms antigravity > /dev/null 2>&1; check "$?" 1 "agy ran a step outside our hook's list: the arm fails"
R=$(lastrun); check "$(jget "$R/run.json" '(d["arms"]["antigravity"]["state"], "call_mcp_tool" in d["arms"]["antigravity"]["why"])')" "('failed', True)" "  naming it"
STUB_AGY=denied C run --home "$H" --brief "$T/brief.md" --arms antigravity > /dev/null 2>&1; check "$?" 0 "a step our hook denied, then a paper: the arm answers"
STUB_CLAUDE_USE=mcp__gmail__send_email C run --home "$H" --brief "$T/brief.md" --arms opus > /dev/null 2>&1; check "$?" 1 "a Claude tool the start did not allow: the arm fails"
STUB_CODEX_ITEM=mcp_tool_call C run --home "$H" --brief "$T/brief.md" --arms codex > /dev/null 2>&1; check "$?" 1 "a Codex connector call: the arm fails"
R=$(lastrun); check "$(jget "$R/run.json" '"mcp_tool_call" in d["arms"]["codex"]["why"]')" "True" "  naming the item"
STUB_CLAUDE=empty C run --home "$H" --brief "$T/brief.md" --arms opus > /dev/null 2>&1; check "$?" 1 "claude's empty result: a failed arm"

echo "the seatbelt: what an arm cannot reach"
STUB_CLAUDE=ssh STUB_SSH="$HD/.ssh/id_test" C run --home "$H" --brief "$T/brief.md" --arms opus > /dev/null 2>&1; check "$?" 1 "a CLI that opens the login's .ssh fails its arm"
R=$(lastrun); check "$(jget "$R/run.json" '"PermissionError" in d["arms"]["opus"]["why"]')/$(grep -rl KEY-THAT-STAYS-HOME "$R" | wc -l | tr -d ' ')" "True/0" \
  "  the kernel refused the read: the key is nowhere in the run dir"
H6="$T/projects/links"; mkdir -p "$H6"; printf -- '- physical: none\n' > "$H6/AGENTS.md"; echo OUTSIDE-SECRET > "$T/outside.txt"
ln -s "$T/outside.txt" "$H6/out"; printf '@%s\n' "$T/outside.txt" > "$H6/CLAUDE.md"
git -C "$H6" init -q -b main && git -C "$H6" add -A && git -C "$H6" commit -qm one
STUB_READS="out:$T/outside.txt" C run --home "$H6" --brief "$T/brief.md" --arms opus > /dev/null 2>&1; R=$(lastrun)
check "$(stub "$R/arms/opus/claude.jsonl" 'sorted(d["reads"].values())')" "['PermissionError', 'PermissionError']" \
  "a copy's link out and a CLAUDE.md @ import of a path outside: both refused by the kernel (16, 17)"
H7="$T/projects/envs"; mkdir -p "$H7"; printf -- '- physical: none\n' > "$H7/AGENTS.md"; echo K=v > "$H7/.env"
git -C "$H7" init -q -b main && git -C "$H7" add -A && git -C "$H7" commit -qm one; : > "$CALLS"
C run --home "$H7" --brief "$T/brief.md" --arms opus,antigravity > /dev/null 2>&1; check "$?" 1 "a commit holding an env file: every arm refused"
R=$(lastrun); check "$(jget "$R/run.json" '[("secrets guard" in d["arms"][a]["why"] and ".env" in d["arms"][a]["why"]) for a in ("opus", "antigravity")]')" "[True, True]" \
  "  naming the path, never its content"
check "$(grep -c '^claude arm\|^claude mcp' "$CALLS")" "0" "  no CLI called"
C run --home "$H" --brief "$T/brief.md" --arms opus --research > /dev/null 2>&1; R=$(lastrun)
check "$(python3 -c 'import json,sys; print([e["why"].split(":")[0] for e in map(json.loads, open(sys.argv[1])) if e.get("host") == "example.invalid"])' "$R/arms/opus/proxy.jsonl")/$(jget "$R/run.json" 'd["research"]')" \
  "['resolve']/True" "--research: the door admits a public host it can resolve (this one it cannot), recorded in run.json"
check "$(stub "$R/arms/opus/claude.jsonl" 'd["argv"][d["argv"].index("--tools") + 1]')" "Bash,Read,Glob,Grep,Write,Edit,WebFetch,WebSearch" \
  "  and its arm gets the web tools (finding 10)"
C run --home "$H" --brief "$T/brief.md" --arms codex --research > /dev/null 2>&1; R=$(lastrun); EV=$(events_of "$R")
check "$(stub "$EV" "'web_search=\"live\"' in d[\"argv\"]")" "True" "  and Codex's web search on"
echo "a non-Claude arm meets the vendor fence and the spawn gate (the fourth landing review, finding 2)"
echo site > "$REGATTA_CONFIG/regatta/guarded"
STUB_PICK_FOREIGN=1 C run --home "$H" --brief "$T/brief.md" --arms opus,codex,antigravity --approved "google=Sam, 2026-11-01: yes" \
  --approved "openai=Sam, 2026-11-01: yes" --approved "anthropic=Sam, 2026-11-01: yes" > /dev/null 2>&1; R=$(lastrun)
rm -f "$REGATTA_CONFIG/regatta/guarded"
check "$(jget "$R/run.json" '[(a, d["arms"][a]["state"], "tenant owns" in (d["arms"][a].get("why") or "")) for a in ("opus", "codex", "antigravity")]')" \
  "[('opus', 'ok', False), ('codex', 'refused', True), ('antigravity', 'refused', True)]" \
  "  a guarded home on a login its tenant does not own: the Codex and Gemini arms refused, quote or not; Claude's runs"
HV="$T/projects/vault"; mkdir -p "$HV"; printf -- '- physical: none\n' > "$HV/AGENTS.md"
git -C "$HV" init -q -b main && git -C "$HV" add -A && git -C "$HV" commit -qm one
cp "$CLAUDE_REPOS_JSON" "$T/repos.keep"
python3 -c 'import json,sys; d = json.load(open(sys.argv[1])); d["repos"]["vault"] = {}; d["scopes"]["vlt"] = {"file": "v.code-workspace", "repos": ["vault"], "confidential": True}; json.dump(d, open(sys.argv[1], "w"))' "$CLAUDE_REPOS_JSON"
cp "$T/brief.md" "$T/tmp-brief.md"
( cd "$HV" && C run --home "$H" --brief "$T/tmp-brief.md" --arms opus,codex,antigravity --approved "google=Sam, 2026-11-01: yes" \
    --approved "openai=Sam, 2026-11-01: yes" > /dev/null 2>&1 ); R=$(lastrun)
check "$(jget "$R/run.json" '[(a, d["arms"][a]["state"], "confidential scope" in (d["arms"][a].get("why") or "")) for a in ("opus", "codex", "antigravity")]')" \
  "[('opus', 'refused', True), ('codex', 'refused', True), ('antigravity', 'refused', True)]" \
  "  a caller inside a confidential scope, its brief outside any repo: no arm gets it, Claude's included (the spawn gate for every arm, round 1)"
cp "$T/repos.keep" "$CLAUDE_REPOS_JSON"

echo "round 4: a box is never reused, and the spawn gate reads the commit's own branch"
git -C "$H" branch -f claude/laptop/2026-11-01-topic HEAD 2>/dev/null
check "$(council_py 'print(c.commit_branch(sys.argv[3], c.git(sys.argv[3], "rev-parse", "HEAD")))' "$H")" "claude/laptop/2026-11-01-topic" \
  "commit_branch(): the claude/* branch the commit tips, before main"
git -C "$H" branch -D claude/laptop/2026-11-01-topic > /dev/null 2>&1
echo "examine: blind, shuffled per arm"
C run --home "$H" --brief "$T/brief.md" > /dev/null 2>&1; R=$(lastrun)
C examine --run "$R" --draft "$T/draft.md" > /dev/null 2>"$T/err"; check "$?" 0 "examine exits 0"
check "$(jget "$R/run.json" 'sorted(sorted(k.values()) == sorted(["draft", "opus", "antigravity", "codex"]) for k in d["examine_keys"].values())')" \
  "[True, True, True]" "each examiner's key maps its labels to the draft and every paper"
C examine --run "$R" --draft "$T/draft.md" > /dev/null 2>&1
check "$(jget "$R/run.json" 'd["examines"]')/$([ -f "$R/examine-2/opus/prompt.md" ] && echo own)/$(jget "$R/run.json" 'd["examine"]["opus"]["state"]')" "2/own/ok" \
  "a second examine: a phase folder of its own (examine-2), never a box path the first examine's leftovers can write (round 5)"
check "$(jget "$R/run.json" '(len(d["examine_past"]), d["examine_past"][0]["n"], sorted(d["examine_past"][0]["examine_keys"]), d["examine_past"][0]["examine"]["opus"]["state"])')" \
  "(1, 1, ['antigravity', 'codex', 'opus'], 'ok')" "  the first examine's rows and label keys kept in run.json, never saved over (round 6)"
mkdir -p "$R/examine-3/antigravity"
C examine --run "$R" --draft "$T/draft.md" > /dev/null 2>&1
check "$(jget "$R/run.json" '(d["examine"]["antigravity"]["state"], "there already" in d["examine"]["antigravity"]["why"], d["examine"]["opus"]["state"])')" "('refused', True, 'ok')" \
  "an examine whose arm folder is there already (an earlier verb's, or a leftover's): that arm refused, never reused (rounds 4, 5)"
python3 -c 'import fcntl, os, sys, time
fd = os.open(sys.argv[1], os.O_WRONLY | os.O_CREAT, 0o600); fcntl.flock(fd, fcntl.LOCK_EX); open(sys.argv[2], "w").close(); time.sleep(20)' \
  "$R/.examine.lock" "$T/exlock.held" & LKP=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do [ -e "$T/exlock.held" ] && break; sleep 0.2; done
: > "$CALLS"; C examine --run "$R" --draft "$T/draft.md" > /dev/null 2>"$T/err"
check "$?/$(wc -c < "$CALLS" | tr -d ' ')/$(jget "$R/run.json" 'd["examines"]')" "2/0/3" \
  "a second examine of one run while the first runs: refused, no CLI called, the number untouched (round 5b)"
kill "$LKP" 2>/dev/null; wait "$LKP" 2>/dev/null
check "$(stub "$R/examine/opus/claude.jsonl" '("## Paper" in d["prompt"], "../papers/A.md" in d["prompt"], "arms/opus" in d["prompt"], d["cwd"])')" \
  "(False, True, False, '$R/examine/opus/box/copy')" "  papers named by label, never inlined, no arm's name or path; a copy of its own, made again from the commit"
check "$(stub "$R/examine/opus/claude.jsonl" '(sorted(d["papers"]), sorted(d["papers"].values()))')" \
  "(['A.md', 'B.md', 'C.md', 'D.md'], ['# Draft\\n\\nKeep it.\\n', 'PAPER from claude', 'PAPER from codex', 'PAPER from gemini'])" \
  "  the papers and the draft in its box, one file per label (S2)"
[ -f "$R/examine/opus/critique.md" ]; check "$?" 0 "  a critique per examiner"
check "$(ls -d "$R"/*/*/box 2>/dev/null | wc -l | tr -d ' ')" "0" "  every box removed again when examine ends"
C receipt --run "$R" > "$T/receipt2.md"; has "$T/receipt2.md" "| opus, examine (acct-sam) |" "  the Receipt holds the examine rows"
has "$T/receipt2.md" "| opus, examine #1 (acct-sam) |" "  and each earlier examine's (round 6)"
mkdir -p "$R/arms/opus/box/stale"
C examine --run "$R" --draft "$T/draft.md" > /dev/null 2>&1
check "$([ -d "$R/arms/opus/box" ] && echo left || echo gone)" "gone" "  an examine drops every box of its run, a crashed verb's leftover too (round 6)"
STUB_CLAUDE=token C run --home "$H" --brief "$T/brief.md" --arms opus,antigravity > /dev/null 2>&1; R=$(lastrun)
C examine --run "$R" --draft "$T/draft.md" > /dev/null 2>&1; check "$?" 0 "a paper holding a token's shape: examine runs without it"
check "$(jget "$R/run.json" 'd["withheld"]')/$(jget "$R/run.json" 'sorted(d["examine_keys"]["antigravity"].values())')" \
  "{'opus': ['a sk-ant… token']}/['antigravity', 'draft']" "  withheld from every examiner, said by kind"
hasnt "$R/examine/antigravity/prompt.md" "ant-oat01-STANDIN" "  no examiner's prompt holds it"
printf 'Draft quoting g%sp_STANDINSTANDINSTANDINSTANDIN\n' h > "$T/draft-tok.md"
C examine --run "$R" --draft "$T/draft-tok.md" > /dev/null 2>&1; check "$?" 2 "a draft holding a token's shape: examine refused"

echo "review: the build path's codex exec review"
: > "$CALLS"
C review --home "$H" --base main --head claude/laptop/2026-10-27-x --json > /dev/null 2>"$T/err"; check "$?" 0 "review exits 0 on the shell's road"
R=$(lastrun); EV=$(jget "$R/run.json" 'd["arms"]["codex"]["raw"]["events"]' 2>/dev/null || python3 -c 'import glob,os; print(max(glob.glob(os.environ["HARNESS_RUNS_DIR"] + "/*.jsonl"), key=os.path.getmtime))')
check "$(stub "$EV" '(d["cwd"], d["argv"].endswith("review --base base"))')" "('$R/review/box/repo', True)" "  codex exec review --base base in the review's box"
check "$(stub "$EV" 'd["review"]')" "log=head $(git -C "$H" rev-parse --short=12 claude/laptop/2026-10-27-x)|base $(git -C "$H" rev-parse --short=12 main)| diff=new.txt| modes=0 status=0 wt=new.txt| vendor=[]" \
  "  two commits: the merge base, then the branch's tree; the diff is the branch's change alone"
check "$(stub "$EV" '(d["env"]["GIT_CONFIG_GLOBAL"], d["env"]["GIT_CONFIG_NOSYSTEM"])')" "('/dev/null', '1')" "  git's global and system config pointed away"
check "$(cat "$R/review/review.md")/$([ -d "$R/review/box" ] && echo kept || echo removed)" "PAPER from codex/removed" "  the review written; its box removed"
C receipt --run "$R" > "$T/receipt3.md"
has "$T/receipt3.md" "| usage not reported by codex exec review |" "  the Receipt: codex exec review's all-zero usage said so, not a dash"
R=$(lastrun); check "$(jget "$R/run.json" '(d["arms"]["codex"]["f7"]["withdrawn"]["ok"], d["arms"]["codex"]["f7"]["at_first_tool"])')" "(True, [])" \
  "  its login withdrawn at its first vendor request too (F7)"
H3="$T/projects/fresh"; mkdir -p "$H3"; git -C "$H3" init -q -b main && git -C "$H3" commit -q --allow-empty -m root
git -C "$H3" checkout -qb feature && printf -- '- physical: none\n' > "$H3/AGENTS.md" && git -C "$H3" add -A && git -C "$H3" commit -qm first
C review --home "$H3" --base main --head feature > /dev/null 2>"$T/err"; check "$?" 0 "a merge base with an empty tree: reviewed, not a traceback"

echo "unattended: the Codex arm bounded by harness"
CLAUDE_UNATTENDED=dispatch C run --home "$H" --brief "$T/brief.md" --arms codex --timeout 600 > /dev/null 2>&1; check "$?" 0 "an unattended council's Codex arm runs: --timeout, --council and a free slot"
R=$(lastrun)
CLAUDE_UNATTENDED=dispatch C examine --run "$R" --draft "$T/draft.md" > /dev/null 2>&1; check "$?" 0 "  its one examine runs"
CLAUDE_UNATTENDED=dispatch C examine --run "$R" --draft "$T/draft.md" > /dev/null 2>&1; check "$?" 1 "  a second unattended examine: its Codex arm refused (two per council run)"
check "$(jget "$R/run.json" '(d["examine"]["codex"]["state"], "its arms and one examine" in d["examine"]["codex"]["why"])')" "('refused', True)" "  saying why"
STUB_CAP=0 CLAUDE_UNATTENDED=dispatch C run --home "$H" --brief "$T/brief.md" --arms codex --timeout 600 > /dev/null 2>&1; check "$?" 1 "unattended with this Mac's cap full: the Codex arm refused before codex starts"
R=$(lastrun); check "$(jget "$R/run.json" '"the next step waits for a run to end" in d["arms"]["codex"]["why"]')" "True" "  in the cap's own waiting words"
# finding 11: the Codex arm's turn ends at a deadline council sets and hands harness, so harness's start-lock and cap
# waits come out of council's bound (a stand-in harness that records its argv)
cat > "$T/bin/harness-argv" <<HA
import sys
open("$T/harness.argv", "w").write("\\n".join(sys.argv[1:]))
print("no-json")
sys.exit(1)
HA
COUNCIL_HARNESS="$T/bin/harness-argv" C run --home "$H" --brief "$T/brief.md" --arms codex --timeout 600 > /dev/null 2>&1; R=$(lastrun)
check "$(python3 -c 'import json,sys
a = open(sys.argv[1]).read().split("\n"); st = json.load(open(sys.argv[2]))["started"]
dl = float(a[a.index("--deadline") + 1]); print(a[a.index("--timeout") + 1], 595 <= dl - st <= 605)' "$T/harness.argv" "$R/run.json")" "600 True" \
  "the Codex arm hands harness --deadline: council's start plus its --timeout"
fi

echo "a link named for a vendor's folder leaves no copy (the fourth landing review, finding 11)"
HL="$T/projects/vlinks"; mkdir -p "$HL/conf" "$HL/codexconf"; printf -- '- physical: none\n' > "$HL/AGENTS.md"
echo '{"hooks": {}}' > "$HL/conf/settings.json"; echo 'model = "x"' > "$HL/codexconf/config.toml"
ln -s conf "$HL/.claude"; ln -s codexconf "$HL/.codex"
git -C "$HL" init -q -b main && git -C "$HL" add -A && git -C "$HL" commit -qm one
check "$(council_py 'import os, subprocess
h, d = sys.argv[3], sys.argv[4]
sha = subprocess.run(["git", "-C", h, "rev-parse", "main"], capture_output=True, text=True).stdout.strip()
made, stripped = c.git_copy(h, [("copy", "copy of", sha)], d)
print(stripped, [x for x in (".claude", ".codex") if os.path.lexists(os.path.join(d, x))], c.vendor_left(d))' "$HL" "$T/vl-copy")" \
  "['.claude', '.codex'] [] []" "  a tracked .codex link and a .claude link: stripped, nothing of a vendor's left (lstat)"
echo "the fence cases name the login's own home (the fourth landing review, finding 12)"
check "$(council_py 'import pwd, os
lh = os.path.realpath(pwd.getpwuid(os.getuid()).pw_dir)
cmds = [x[0] for x in c.FENCE_CASES]
print(any("~" in x for x in cmds), cmds[2].startswith("head -c 40 " + lh), cmds[3].startswith("ls " + lh))')" "False True True" \
  "  no case names ~ (the arm's scratch HOME): .ssh and projects by the login's real path"
check "$(council_py 'import os
case = c._home_case(".")[1]   # the login home itself exists: a read that ran is not held, nor one that was absent
print(case({"exit": 0, "output": "a\nb"}), case({"exit": 1, "output": "ls: x: No such file or directory"}), case({"exit": 1, "output": "ls: x: Operation not permitted"}))')" \
  "False False True" "  an existing path is held only when the seatbelt denied it, never as absent"

echo "round 2 of the build review"
check "$(council_py 'print(c.vendor_config(".mcp.jſon"), c.vendor_config(".agentſ/x"), c.vendor_config(".claude/ſettings.json"))')" "True True True" \
  "vendor_config(): names compared as APFS compares them (ſ is s)"
check "$(council_py 'import os, time
d = sys.argv[3]; os.makedirs(d, exist_ok=True)
code, _ = c.run_cli(["/bin/sh", "-c", "(sleep 30 & echo $! > %s/kid; wait) & sleep 0.3; exit 0" % d], "", d, dict(os.environ), d + "/log", 10)
time.sleep(0.3); pid = int(open(d + "/kid").read())
try:
    os.kill(pid, 0); alive = True
except OSError:
    alive = False
print(code, alive)' "$T/grp")" "0 False" "run_cli(): what the CLI left running dies with the call (its own process group)"
printf 'A brief.\nghp_%s\n' "$(printf 'a%.0s' $(seq 1 30))" > "$T/brief-tok.md"
C run --home "$H" --brief "$T/brief-tok.md" --arms opus > /dev/null 2>"$T/err"; check "$?" 2 "a brief holding a credential's shape: refused before any arm"
has "$T/err" "ghp_" "  named by kind"
check "$(COUNCIL_FENCES_STATE= HOME="$T/elsewhere" council_py 'import pwd, os; print(c.fences_file().startswith(os.path.realpath(pwd.getpwuid(os.getuid()).pw_dir)))')" "True" \
  "the verdict file sits in the login's own home, whatever HOME says"

echo "refusals before anything is copied"
n=$(nruns)
COUNCIL_TMP="$HD/runs" C run --home "$H" --brief "$T/brief.md" > /dev/null 2>"$T/err"; check "$?" 2 "a run dir inside ~: refused"
has "$T/err" "inside ~" "  saying why"
mkdir -p "$T/dot.ted"
check "$(council_py 'print(c.fence_root(sys.argv[3]) == sys.argv[3])' "$T/dot.ted/r1")" "True" \
  "a run dir with a dot in its path: made (S3: the dot rule was the old Codex profile's; the seatbelt quotes paths)"
rm -rf "$T/dot.ted"
check "$(nruns)" "$n" "  the refused runs made nothing under COUNCIL_TMP"
: > "$CALLS"
echo '{"repos": {"site": {}}, "scopes": {"work": {"file": "w.code-workspace", "repos": ["site"], "confidential": true}}}' > "$CLAUDE_REPOS_JSON"
C run --home "$H" --brief "$T/brief.md" > /dev/null 2>"$T/err"; check "$?" 2 "a confidential scope's repo: refused for every arm"
has "$T/err" "confidential" "  saying why"
mkdir -p "$H/private"; cp "$T/brief.md" "$H/private/brief.md"
H2="$T/projects/other"; mkdir -p "$H2"; printf -- '- physical: none\n' > "$H2/AGENTS.md"; git -C "$H2" init -q -b main && git -C "$H2" add -A && git -C "$H2" commit -qm one
C run --home "$H2" --brief "$H/private/brief.md" --arms opus > /dev/null 2>"$T/err"; check "$?" 2 "a brief in a confidential scope's repo: refused, whatever the home"
mkdir -p "$T/projects/grp/app"; git -C "$T/projects/grp/app" init -q -b main; cp "$T/brief.md" "$T/projects/grp/app/brief.md"
echo '{"repos": {"site": {}, "grp": {}}, "scopes": {"work": {"file": "w.code-workspace", "repos": ["site"]}, "g": {"file": "g.code-workspace", "repos": ["grp"], "confidential": true}}}' > "$CLAUDE_REPOS_JSON"
C run --home "$H2" --brief "$T/projects/grp/app/brief.md" --arms opus > /dev/null 2>"$T/err"
check "$?/$(wc -c < "$CALLS" | tr -d ' ')" "2/0" "a brief in a repo under a confidential group folder (its name no key): refused by its path, no CLI called (round 5)"
echo '{"repos": {"site": {}' > "$CLAUDE_REPOS_JSON"
C run --home "$H" --brief "$T/brief.md" > /dev/null 2>&1; check "$?" 2 "a registry that cannot be read: refused (the fence fails closed)"
C review --home "$H" > /dev/null 2>&1; check "$?" 2 "  review too"
check "$(nruns)/$(wc -c < "$CALLS" | tr -d ' ')" "$n/0" "  nothing copied, no CLI called"
echo '{"repos": {"site": {}}, "scopes": {"work": {"file": "w.code-workspace", "repos": ["site"]}}}' > "$CLAUDE_REPOS_JSON"
for u in REGATTA_UNATTENDED=dispatch CLAUDE_UNATTENDED=dispatch AUTOFINISH_CALLER_UNATTENDED=1; do
  env "$u" python3 "$B/council" run --home "$H" --brief "$T/brief.md" --arms antigravity --approved "google=Sam, 2026-10-28: yes" > /dev/null 2>"$T/err"
  check "$?" 2 "--approved from an unattended caller ($u): refused, the quote being the owner's yes"
done
env CLAUDE_UNATTENDED=dispatch python3 "$B/council" review --home "$H" --approved "openai=Sam, 2026-10-28: yes" > /dev/null 2>&1; check "$?" 2 "  review's too"
C run --home "$H" --brief "$T/brief.md" --arms nope > /dev/null 2>&1; check "$?" 2 "an unknown arm: refused"
n=$(nruns); C run --home "$H" --brief "$T/brief.md" --arms opus,opus > /dev/null 2>"$T/err"; check "$?" 2 "--arms naming opus twice: refused"
check "$(nruns)" "$n" "  nothing made"
C run --home "$H" --brief "$T/brief.md" --arms opus --claude-config "$T/nowhere" > /dev/null 2>&1; check "$?" 2 "a --claude-config that is no directory: refused"
mkdir -p "$T/nothing"; C receipt --run "$T/nothing" > /dev/null 2>"$T/err"; check "$?" 2 "receipt of a dir no verb finished in: refused, not a traceback"

echo "the council's S3 one-liners (the third landing review)"
# finding 5: examine judges every source the run recorded again, as run judged the home
mkdir -p "$T/ex5"; chmod 700 "$T/ex5"; echo "PAPER" > "$T/ex5/paper.md"; cp "$T/brief.md" "$T/ex5/brief.md"
python3 -c 'import json,sys; json.dump({"id": "x", "home": sys.argv[1], "commit": "0" * 40, "brief": sys.argv[2] + "/brief.md",
  "sources": ["site", "secretrepo"], "arms": {"opus": {"state": "ok", "paper": sys.argv[2] + "/paper.md"}}}, open(sys.argv[2] + "/run.json", "w"))' "$H" "$T/ex5"
echo '{"repos": {"site": {}, "secretrepo": {}}, "scopes": {"work": {"file": "w.code-workspace", "repos": ["site"]}, "sec": {"file": "s.code-workspace", "repos": ["secretrepo"], "confidential": true}}}' > "$CLAUDE_REPOS_JSON"
: > "$CALLS"; C examine --run "$T/ex5" --draft "$T/draft.md" > /dev/null 2>"$T/err"
check "$?/$(wc -c < "$CALLS" | tr -d ' ')" "2/0" "examine of a run whose brief's repo became a confidential scope's since: refused, no CLI called"
has "$T/err" "secretrepo is a confidential scope's" "  naming the source"
echo '{"repos": {"site": {}}, "scopes": {"work": {"file": "w.code-workspace", "repos": ["site"]}}}' > "$CLAUDE_REPOS_JSON"
# finding 23: a run's id is a uuid, never the run dir's basename two --out folders share
check "$(council_py 'print(len({c.run_uuid() for _ in range(50)}), len(c.run_uuid()))')" "50 32" "run_uuid: a fresh 32-hex id each time"
mkdir -p "$T/o1" "$T/o2"
C run --home "$H" --brief "$T/brief.md" --arms opus --out "$T/o1/run" > /dev/null 2>&1
C run --home "$H" --brief "$T/brief.md" --arms opus --out "$T/o2/run" > /dev/null 2>&1
check "$(python3 -c 'import json,re,sys; a, b = (json.load(open(x))["id"] for x in sys.argv[1:]); print(a != b, bool(re.match("^[0-9a-f]{32}$", a)))' "$T/o1/run/run.json" "$T/o2/run/run.json")" \
  "True True" "  two runs whose --out folders share a basename: two ids"
C review --home "$H" --base main --out "$T/o3/run" > /dev/null 2>&1
check "$(jget "$T/o3/run/run.json" 'd["id"] != "run" and len(d["id"]) == 32')" "True" "  review's too"
rm -rf "$T/o1/run"
C run --home "$H" --brief "$T/brief.md" --arms opus --out "$T/o1/run" > /dev/null 2>"$T/err"
check "$?/$([ -e "$T/o1/run" ] && echo made || echo none)" "2/none" \
  "an --out an earlier run used, deleted since: refused, nothing made (a leftover's seatbelt still names its boxes; round 5b)"
has "$T/err" "held an earlier council run" "  saying why"
C run --home "$H" --brief "$T/brief.md" --arms opus --out "$T/o1/run/box/x" > /dev/null 2>"$T/err"
check "$?/$([ -e "$T/o1/run" ] && echo made || echo none)" "2/none" \
  "an --out inside a path an earlier run used: refused too (its leftover's write rule covers the subpath; round 6)"
check "$(council_py '
import os
b = sys.argv[3]; os.makedirs(b, exist_ok=True); os.symlink(b + "/elsewhere", b + "/.council-runs-%d" % os.getuid())
os.environ["COUNCIL_TMP"] = b
try:
    c.fence_root(b + "/run"); print("made")
except c.Refused as e:
    print("refused", os.path.exists(b + "/run"))
' "$T/ledger-link")" "refused False" "a ledger that is a link: refused before anything is made, never a traceback (round 6)"
check "$(council_py '
import os
d = sys.argv[3]; os.makedirs(d + "/box", exist_ok=True); S = "SECRET-" + "qrstuvwxyz" * 6
cred = c.fence.Credential("codex", files=[d + "/gone"], secrets=[S]); cred.withdraw()
open(d + "/cli.jsonl", "w").write(S)
out = c.judge_f7({"state": "failed", "why": "codex: 401 " + S[:40], "raw": {"error": S}}, cred, None, d, d + "/box")
print(out["state"], S[:30] in out["why"], S in c.json.dumps(out["raw"]), out["raw"].get("withheld") is not None)
' "$T/f7why")" "failed False False True" "judge_f7(): a failed arm whose error or raw result quotes the login keeps the F7 verdict's words instead (round 6)"
check "$(council_py '
import os
d = sys.argv[3]; os.makedirs(d + "/box", exist_ok=True); S = "SECRET-" + "hijklmnopq" * 6
cred = c.fence.Credential("codex", files=[d + "/gone"], secrets=[S])
out = c.judge_f7({"state": "failed", "why": "codex: " + S[:40], "raw": {"e": 1}}, cred, None, d, d + "/box")
print(out["state"], S[:30] in out["why"], bool(out.get("f7_bad")))
' "$T/f7why2")" "failed False True" "  and so when no file held it (the CLI said it on stderr alone: round 6, its second review)"
check "$(council_py '
import os
d = sys.argv[3]; os.makedirs(d + "/box", exist_ok=True); S = "SECRET-" + "abcdefghij" * 6
cred = c.fence.Credential("codex", files=[d + "/gone"], secrets=[S])
out = c.judge_f7({"state": "ok", "text": "x", "record": {"readable": True, "commands": ["curl -H " + S]}}, cred, None, d, d + "/box")
print(out["state"], S in c.json.dumps(out), out["record"].get("withheld") is not None)
' "$T/f7rec")" "failed False True" "judge_f7(): a record whose commands quote the login is withheld from run.json (the landing review)"
check "$(council_py '
import os
d = sys.argv[3]; os.makedirs(d + "/box", exist_ok=True); S = "SECRET-" + "abcdefghij" * 6
cred = c.fence.Credential("codex", files=[d + "/gone"], secrets=[S])
out = c.judge_f7({"provider": "codex", "state": "ok", "text": "x", "record": {"readable": True, "commands": ["curl -H " + S]}}, cred, None, d, d + "/box")
print(c.judge_arm("codex", out, d, None)["verdict"])
' "$T/f7judge")" "broken" "  judge_arm(): an arm whose record F7 withheld is broken, never unproven (the fix round)"
cat > "$T/f7q.py" <<'PY'
import os
d = sys.argv[3]; os.makedirs(d + "/box", exist_ok=True); S = "SECRET-" + "abcdefghij" * 3 + "\"\\é" + "klmnopqrst" * 3
cred = c.fence.Credential("codex", files=[d + "/gone"], secrets=[S])
out = c.judge_f7({"state": "ok", "text": "x", "record": {"readable": True, "commands": ["curl -H " + S]}}, cred, None, d, d + "/box")
print(out["state"], out["record"].get("withheld") is not None)
PY
check "$(council_py "$(cat "$T/f7q.py")" "$T/f7q")" "failed True" "  a login holding a quote, a backslash or non-ASCII is still found (strings walked, never their JSON dump)"
check "$(council_py 'print(c.fence.outcomes("codex", None), c.arm_log("codex", {"provider": "codex"}, "/nonexistent")[1])')" "[] None" \
  "  a Codex arm with no log (raw.json withheld): no events, never a TypeError (the landing review)"
check "$(COUNCIL_TMP="$T/tmp-new/x" council_py 'import os; print(os.path.isdir(c.fence_root(None)))')" "True" \
  "fence_root(): a COUNCIL_TMP not there yet is made, as before the ledger (round 6)"
mkdir -p "$T/closed-out"; chmod 000 "$T/closed-out"
check "$(council_py '
try:
    c.fence_root(sys.argv[3]); print("made")
except c.Refused as e:
    print("refused")
' "$T/closed-out")" "refused" "fence_root(): an --out it cannot list is refused, never a traceback (round 6c)"
chmod 700 "$T/closed-out"
printf '%s\n' '{"event":"step_update","step_update":{"step_index":1,"state":"DONE","step_type":"tool","tool_name":"search_web"}}' \
  '{"event":"result","result":{"status":"SUCCESS","response":"PAPER"}}' > "$T/agy-web.jsonl"
check "$(council_py '
off = c.agy_result({"observed": {}}, 0, "", sys.argv[3], 60)
on = c.agy_result({"observed": {}}, 0, "", sys.argv[3], 60, True)
print(off["state"], "research off" in str(off.get("why")), on["state"])
' "$T/agy-web.jsonl")" "failed True ok" "agy_result(): a web step with research off fails the arm, with research on it passes; the flag reaches it (round 6, its fourth review: a NameError)"
# finding 24: the unattended rule and the marker have one home, the core's common
check "$(council_py 'import common; print(c.MARKER == common.COUNCIL_MARKER, hasattr(c, "UNATTENDED"), c.unattended())')" "True False None" \
  "council's marker and unattended rule are the core's (common), no copy of the variables here"
check "$(AUTOFINISH_CALLER_UNATTENDED=1 council_py 'print(c.unattended())')" "AUTOFINISH_CALLER_UNATTENDED=1" "  a peer's unattended caller counts"
check "$(REGATTA_UNATTENDED=dispatch COUNCIL_HARNESS=/x/h COUNCIL_ACCOUNT=/x/a COUNCIL_FENCES_STATE=/x/f council_py 'print(c.harness_bin() != "/x/h", c.account_tool() != "/x/a", c.fences_file() != "/x/f")')/$(COUNCIL_HARNESS=/x/h council_py 'print(c.harness_bin())')" \
  "True True True//x/h" "an unattended caller's COUNCIL_HARNESS, COUNCIL_ACCOUNT and COUNCIL_FENCES_STATE are not honoured (the fourth review's S3)"
# the fourth landing review's finding 5: the vendor-neutral marker counts (a second unattended() in common, merged
# with no conflict, shadowed main's and read only the old names)
check "$(REGATTA_UNATTENDED=dispatch council_py 'print(c.unattended())')" "REGATTA_UNATTENDED=dispatch" "  REGATTA_UNATTENDED alone counts"
# finding 6: a fixture is spelled under $HD (the suite's $T/home), never a bare HOME (a block run outside the suite has the real one)
check "$(grep -c '"\$HOME"\{0,1\}/\|^HD=\$HOME' "$0")" 0 "finding 6: no fixture path in this suite starts at a bare HOME"
FR="$T/fake-review"; mkdir -p "$FR"; printf 'PAPER\n' > "$FR/review.md"
python3 -c 'import json, sys; json.dump({"id": "fr", "home": sys.argv[1], "source": "site", "commit": "x", "kind": "review",
  "arms": {"codex": {"state": "ok", "paper": sys.argv[2] + "/review.md"}}}, open(sys.argv[2] + "/run.json", "w"))' "$H" "$FR"
C examine --run "$FR" --draft "$T/draft.md" > /dev/null 2>"$T/err"; check "$?" 2 "examine of a review's run dir: refused, not a traceback"

echo "the vendors' quotes, the login's tenancy"
echo site > "$REGATTA_CONFIG/regatta/guarded"; : > "$CALLS"
C run --home "$H" --brief "$T/brief.md" --arms opus,antigravity > /dev/null 2>&1; check "$?" 1 "a guarded home without the owner's quote: every arm refused"
R=$(lastrun); check "$(jget "$R/run.json" '[("vet" in d["arms"][a]["why"] or "quote" in d["arms"][a]["why"] or "guarded" in d["arms"][a]["why"]) for a in ("opus", "antigravity")]')" "[True, True]" \
  "  refused by the gate's vet, per vendor"
if [ -n "$FENCE" ]; then
  C run --home "$H" --brief "$T/brief.md" --arms opus,antigravity --approved "anthropic=Sam, 2026-10-27: yes" > /dev/null 2>&1
  R=$(lastrun); check "$(jget "$R/run.json" '[d["arms"][a]["state"] for a in ("opus", "antigravity")]')" "['ok', 'refused']" "  Anthropic's quote lets the Claude arm run, not Google's"
  C run --home "$H" --brief "$T/brief.md" --arms antigravity --approved "google=Sam, 2026-10-27: yes" > /dev/null 2>&1
  R=$(lastrun); check "$(jget "$R/run.json" '(d["arms"]["antigravity"]["state"], d["arms"]["antigravity"]["approved"])')" "('ok', 'Sam, 2026-10-27: yes')" "  with Google's quote the Gemini arm runs, the quote recorded"
  C run --home "$H" --brief "$T/brief.md" --arms codex --approved "openai=Sam, 2026-10-28: yes" > /dev/null 2>&1; R=$(lastrun)
  check "$(jget "$R/run.json" '(d["arms"]["codex"]["state"], d["arms"]["codex"].get("approved"))')" "('ok', 'Sam, 2026-10-28: yes')" \
    "  with OpenAI's quote council hands it to harness, which vets the home itself"
fi
rm -f "$REGATTA_CONFIG/regatta/guarded"
H4="$T/projects/notes"; mkdir -p "$H4"; printf 'a guarded brief\n' > "$H4/brief.md"
git -C "$H4" init -q -b main && git -C "$H4" add -A && git -C "$H4" commit -qm one
echo notes > "$REGATTA_CONFIG/regatta/guarded"
C run --home "$H" --brief "$H4/brief.md" --arms opus,antigravity > /dev/null 2>&1; check "$?" 1 "a guarded repo's brief beside an open home: every arm refused"
R=$(lastrun); check "$(jget "$R/run.json" '[d["arms"][a]["state"] for a in ("opus", "antigravity")]')" "['refused', 'refused']" "  by the gate's vet, per vendor"
rm -f "$REGATTA_CONFIG/regatta/guarded"
: > "$CALLS"; STUB_DENY=1 C run --home "$H" --brief "$T/brief.md" --arms opus > /dev/null 2>&1; check "$?" 1 "a login account allowed refuses for the home: the Claude arm refused"
R=$(lastrun); check "$(jget "$R/run.json" '(d["arms"]["opus"]["state"], "account allowed" in d["arms"]["opus"]["why"])')" "('refused', True)" "  saying so"
mkdir -p "$T/rel-cfg"; cp "$HD/.claude/.credentials.json" "$T/rel-cfg/"; : > "$CALLS"
(cd "$T" && CLAUDE_CODE_OAUTH_TOKEN=tok python3 "$B/council" run --home "$H" --brief "$T/brief.md" --arms opus --claude-config rel-cfg > /dev/null 2>&1)
has "$CALLS" "account allowed $H cfg=$T/rel-cfg" "--claude-config relative: account allowed asked under it, absolute"
if [ -n "$FENCE" ]; then
  R=$(lastrun); check "$(stub "$R/arms/opus/claude.jsonl" '("CLAUDE_CODE_OAUTH_TOKEN" in d["env"], d["cfg_files"], d["pipe"])')" "(False, ['.claude.json'], 27)" \
    "  the arm signs in from that dir's login, on a pipe; never the caller's token"
  CT=tok-of-the-caller   # by a name the publish gate reads as no credential
  : > "$CALLS"; CLAUDE_CODE_OAUTH_TOKEN="$CT" C run --home "$H" --brief "$T/brief.md" --arms opus > /dev/null 2>&1; R=$(lastrun)
  check "$(stub "$R/arms/opus/claude.jsonl" '("CLAUDE_CODE_OAUTH_TOKEN" in d["env"], d["cfg_files"], d["pipe"])')" "(False, ['.claude.json'], 17)" \
    "  without it the caller's own token is the arm's login (dispatch pairs the dir and the token), on the pipe too, never in its environment"
fi

echo "the copy (no inline road left)"
check "$(council_py 'print([hasattr(c, n) for n in ("inline_files", "commit_blob", "INLINE_FILE", "INLINE_TOTAL", "NO_TOOLS", "WHERE_INLINE", "codex_road")])')" \
  "[False, False, False, False, False, False, False]" "the text-only road's pieces are gone: every arm reads its copy"
check "$(council_py 'print([hasattr(c, n) for n in ("make_copy", "tree_matches", "tree_entries")], "os.chmod(p, 0o755" in open(sys.argv[1]).read())')" \
  "[False, False, False] False" "S2: make_copy, tree_matches and review_arm's chmod walk are gone"

echo "S2: git writes the copy"
# a tree with what a hand-built copy got wrong: an export-ignore path, an export-subst file, a .gitignore'd tracked
# file, a link, a 2 MB blob, a file an eol attribute would rewrite, and the copy's own config for the arms' CLIs
H5="$T/projects/attrs"; mkdir -p "$H5/docs" "$H5/.codex" "$H5/.agents/skills/x" "$H5/sub/.gemini" "$H5/.claude/agents"
printf -- '- physical: none\n' > "$H5/AGENTS.md"
printf 'held.txt export-ignore\nsubst.txt export-subst\ncrlf.txt text eol=crlf\n' > "$H5/.gitattributes"; printf 'ignored.txt\n' > "$H5/.gitignore"
echo one > "$H5/held.txt"; printf '$Format:%%H$\n' > "$H5/subst.txt"; echo one > "$H5/ignored.txt"; printf 'a\nb\n' > "$H5/crlf.txt"
echo doc > "$H5/docs/x.md"; ln -s docs/x.md "$H5/ln"
python3 -c 'import os, sys; open(sys.argv[1], "wb").write(os.urandom(2 << 20))' "$H5/big.bin"
echo 'model = "x"' > "$H5/.codex/config.toml"; echo s > "$H5/.agents/skills/x/SKILL.md"; echo '{}' > "$H5/sub/.gemini/settings.json"
echo '{}' > "$H5/.claude/settings.local.json"; echo keep > "$H5/.claude/agents/keep.md"
git -C "$H5" init -q -b main && git -C "$H5" add -A 2>/dev/null && git -C "$H5" add -f ignored.txt && git -C "$H5" commit -qm one
git -C "$H5" checkout -qb feat && echo two > "$H5/held.txt" && echo two > "$H5/ignored.txt" && echo 'model = "y"' > "$H5/.codex/config.toml" \
  && git -C "$H5" commit -qam two && git -C "$H5" checkout -q main
cat > "$T/gc.py" <<'PY2'
import hashlib, os, subprocess
h, d = sys.argv[3], sys.argv[4]
sha = lambda r: subprocess.run(["git", "-C", h, "rev-parse", r], capture_output=True, text=True).stdout.strip()
blob = lambda p: hashlib.sha1(b"blob %d\0" % os.path.getsize(p) + open(p, "rb").read()).hexdigest()
made, stripped = c.git_copy(h, [("copy", "copy of", sha("feat"))], d)
print(sorted(os.listdir(d)))
print(open(d + "/subst.txt").read().strip(), open(d + "/held.txt").read().strip(), os.readlink(d + "/ln"))
print([blob(d + "/" + p) == sha("feat:" + p) for p in ("big.bin", "crlf.txt", "held.txt")], os.path.getsize(d + "/big.bin"))
print(os.access(d + "/AGENTS.md", os.W_OK), stripped, os.path.isfile(d + "/.claude/agents/keep.md"))
PY2
council_py "$(cat "$T/gc.py")" "$H5" "$T/gc" > "$T/gc.out" 2>&1
check "$(sed -n 1p "$T/gc.out")" "['.claude', '.gitattributes', '.gitignore', 'AGENTS.md', 'big.bin', 'crlf.txt', 'docs', 'held.txt', 'ignored.txt', 'ln', 'subst.txt']" \
  "git_copy: the commit's whole tree, no .git left, the CLIs' config gone (and the folder it emptied)"
check "$(sed -n 2p "$T/gc.out")" "\$Format:%H\$ two docs/x.md" "  an export-ignore path kept, an export-subst file as committed, a link written as a link"
check "$(sed -n 3p "$T/gc.out")" "[True, True, True] 2097152" "  a 2 MB blob whole, an eol=crlf file byte for byte (no attribute of the tree applies)"
check "$(sed -n 4p "$T/gc.out")" "True ['.agents/skills/x/SKILL.md', '.claude/settings.local.json', '.codex/config.toml', 'sub/.gemini/settings.json'] True" \
  "  the files the arm's to write; .codex/, .agents/, .gemini/ (at any depth) and .claude/settings*.json stripped, the rest of .claude/ kept"
# round 5's S1 (the reviewer's probe p3): a hook or a core.fsmonitor planted in the copy's .git ran as the owner,
# outside every seatbelt. The copy's folder must be new, and every box git call points hooks and fsmonitor away
mkdir -p "$T/gc-hook/.git/hooks"
printf '#!/bin/sh\ntouch "%s"\n' "$T/hook-ran" > "$T/gc-hook/.git/hooks/post-checkout"; chmod +x "$T/gc-hook/.git/hooks/post-checkout"
printf '[core]\n\tfsmonitor = touch %s; false\n' "$T/fsm-ran" > "$T/gc-hook/.git/config"
check "$(council_py 'import subprocess
try:
    c.git_copy(sys.argv[3], [("copy", "copy of", subprocess.run(["git", "-C", sys.argv[3], "rev-parse", "feat"], capture_output=True, text=True).stdout.strip())], sys.argv[4]); print("written")
except c.CopyFailed as e:
    print("CopyFailed", "new folder" in str(e))' "$H5" "$T/gc-hook" 2>&1)/$([ -e "$T/hook-ran" ] && echo ran || echo none)/$([ -e "$T/fsm-ran" ] && echo ran || echo none)" \
  "CopyFailed True/none/none" "  a copy folder already there (a .git planted in it): refused, no hook and no fsmonitor run (rounds 5, 5b)"
check "$(council_py 'e = c.box_git_env(); print([(e["GIT_CONFIG_KEY_%d" % i], e["GIT_CONFIG_VALUE_%d" % i]) for i in range(int(e["GIT_CONFIG_COUNT"]))])')" \
  "[('core.hooksPath', '/dev/null'), ('core.fsmonitor', 'false')]" "  every box git call: no hook, no fsmonitor command"
# the paths git refuses to write: a `.GIT` folder (HFS) and a `GIT~1` name (NTFS), built with mktree as no checkout would
H8="$T/projects/dotgit"; mkdir -p "$H8"; git -C "$H8" init -q -b main
gb=$(echo hook | git -C "$H8" hash-object -w --stdin); gi=$(printf '100644 blob %s\tx\n' "$gb" | git -C "$H8" mktree)
gh=$(printf '040000 tree %s\thooks\n' "$gi" | git -C "$H8" mktree); ga=$(printf -- '- physical: none\n' | git -C "$H8" hash-object -w --stdin)
git -C "$H8" update-ref refs/heads/main "$(printf '040000 tree %s\t.GIT\n100644 blob %s\tAGENTS.md\n' "$gh" "$ga" | git -C "$H8" mktree | xargs git -C "$H8" commit-tree -m hfs)"
git -C "$H8" update-ref refs/heads/ntfs "$(printf '040000 tree %s\tGIT~1\n100644 blob %s\tAGENTS.md\n' "$gh" "$ga" | git -C "$H8" mktree | xargs git -C "$H8" commit-tree -m ntfs)"
for ref in main ntfs; do
  check "$(council_py 'import subprocess
try:
    c.git_copy(sys.argv[3], [("copy", "copy of", subprocess.run(["git", "-C", sys.argv[3], "rev-parse", sys.argv[4]], capture_output=True, text=True).stdout.strip())], sys.argv[5]); print("written")
except c.CopyFailed as e:
    print("CopyFailed", "invalid path" in str(e), sys.argv[6] in str(e))' "$H8" "$ref" "$T/gc-$ref" "$([ $ref = main ] && echo .GIT/hooks/x || echo 'GIT~1/hooks/x')")" \
    "CopyFailed True True" "  a tree holding $([ $ref = main ] && echo "a .GIT folder" || echo "a GIT~1 name"): git refuses it and the copy fails, the path named"
done
if [ -n "$FENCE" ]; then
  C run --home "$H8" --brief "$T/brief.md" --arms opus > /dev/null 2>&1; check "$?" 1 "a home whose commit holds .GIT/: the arm fails"
  R=$(lastrun); check "$(jget "$R/run.json" '(d["arms"]["opus"]["state"], ".GIT/hooks/x" in d["arms"]["opus"]["why"])')" "('failed', True)" "  named"
  STUB_LOOK="big.bin:ln:crlf.txt:.codex:.claude/settings.local.json:.claude/agents/keep.md" C run --home "$H5" --commit feat --brief "$T/brief.md" --arms opus > /dev/null 2>&1
  R=$(lastrun); check "$(stub "$R/arms/opus/claude.jsonl" '[d["look"][p] for p in ("ln", ".codex", ".claude/settings.local.json", ".claude/agents/keep.md")]')" \
    "['link:docs/x.md', 'absent', 'absent', 'blob:$(git -C "$H5" rev-parse feat:.claude/agents/keep.md)']" "the arm's copy: the link a link, the CLIs' config gone, the rest there"
  check "$(stub "$R/arms/opus/claude.jsonl" '[d["look"][p] for p in ("big.bin", "crlf.txt")]')" \
    "['blob:$(git -C "$H5" rev-parse feat:big.bin)', 'blob:$(git -C "$H5" rev-parse feat:crlf.txt)']" "  the 2 MB blob and the eol=crlf file as committed"
  C receipt --run "$R" > "$T/receipt5.md"
  has "$T/receipt5.md" 'Stripped from every copy before its arm started' "  the Receipt names what was stripped"
  has "$T/receipt5.md" '`.agents/skills/x/SKILL.md`, `.claude/settings.local.json`, `.codex/config.toml`, `sub/.gemini/settings.json`' "  path by path"
  : > "$CALLS"; C review --home "$H5" --base main --head feat > /dev/null 2>&1; check "$?" 0 "the review of a branch changing an export-ignore'd, a .gitignore'd and a .codex/ file"
  R=$(lastrun); EV=$(python3 -c 'import glob,os; print(max(glob.glob(os.environ["HARNESS_RUNS_DIR"] + "/*.jsonl"), key=os.path.getmtime))')
  check "$(stub "$EV" '"diff=.codex/config.toml|held.txt|ignored.txt| modes=0 status=0 wt=.codex/config.toml|held.txt|ignored.txt| vendor=[]" in d["review"]')" "True" \
    "  its scratch repo holds every change (the commits' whole trees); .codex/ off the disk, its diff and status untouched (skip-worktree)"
  check "$(jget "$R/run.json" 'd["arms"]["codex"]["stripped"]')" "['.agents/skills/x/SKILL.md', '.claude/settings.local.json', '.codex/config.toml', 'sub/.gemini/settings.json']" \
    "  named in its record"
  # the review's repo keeps the merge base's tree in .git: an env file only the base holds is judged too (finding 4)
  H9="$T/projects/baseenv"; mkdir -p "$H9"; printf -- '- physical: none\n' > "$H9/AGENTS.md"; echo K=v > "$H9/.env"
  git -C "$H9" init -q -b main && git -C "$H9" add -A && git -C "$H9" commit -qm one
  git -C "$H9" checkout -qb feat && git -C "$H9" rm -q .env && git -C "$H9" commit -qm two && git -C "$H9" checkout -q main
  : > "$CALLS"; C review --home "$H9" --base main --head feat > /dev/null 2>&1; check "$?" 1 "a review whose merge base holds an env file the head removed: refused"
  R=$(lastrun); check "$(jget "$R/run.json" '(d["arms"]["codex"]["state"], ".env (base)" in d["arms"]["codex"]["why"])')/$(grep -c '^codex' "$CALLS")" \
    "('refused', True)/0" "  naming the path and the tree it is in (the fourth landing review, finding 4); no codex started"
fi

if [ -n "$FENCE" ]; then
  echo "fences (S5): the monthly re-probe, judged from each CLI's own log"
  check "$(council_py 'print(c.FENCE_ARMS, len(c.FENCE_CASES), all(x[0] in c.fences_prompt("abc") for x in c.FENCE_CASES),
      "/Library/Preferences" in c.fences_prompt("abc"), all(v.split(",")[0] in c.fences_prompt("abc") for v in c.DENIED_TOOL.values() if v), "none of run_command, " in c.fences_prompt("abc"))')" \
    "('opus', 'codex', 'antigravity') 9 True True True True" "the nine commands (brief-h's, /Library/Preferences the ninth) and a denied tool per CLI in the prompt"
  rm -f "$T/fences-state.json"
  STUB_FENCES=ok C fences --home "$H" > "$T/fences1.txt" 2>&1; check "$?" 0 "every case holds: exit 0"
  LV="$(council_py 'print(c.fence.login_home())')/.local/state/regatta/council-fences.json"
  before=$( [ -f "$LV" ] && shasum "$LV" || echo none )
  REGATTA_UNATTENDED=dispatch STUB_FENCES=ok C fences --home "$H" > "$T/fences-un.txt" 2>&1
  check "$( [ -f "$LV" ] && shasum "$LV" || echo none )" "$before" "  an unattended caller with stand-in CLIs writes no verdict (round 3)"
  has "$T/fences-un.txt" "no verdict written" "    saying so"
  # PATH's CLI must be a compiled one for "PATH's CLIs write it": a CI runner puts a `#!` wrapper named claude first on
  # PATH (check.yml's, for the CLI's non-blocking pipes), which verdict_target rightly reads as a stand-in. A link to
  # a compiled binary under the CLI's name is what a real install looks like to it (runner-paths, 2026-11-03).
  mkdir -p "$T/realcli"; ln -sf /bin/sleep "$T/realcli/claude"
  check "$(COUNCIL_FENCES_STATE= council_py 'print(c.verdict_target()[0])')/$(PATH="$T/realcli:$PATH" COUNCIL_FENCES_STATE= COUNCIL_CLAUDE= COUNCIL_AGY= HARNESS_CODEX= council_py 'print(c.verdict_target()[0] == c.fences_file())')/$(council_py 'print(c.verdict_target()[0])')" \
    "None/True/$T/fences-state.json" "  an attended caller with stand-ins and no COUNCIL_FENCES_STATE: no verdict to this Mac's file; PATH's CLIs write it; a named file takes it (round 5)"
  printf '#!/usr/bin/env node\n' > "$T/bin/claude-node"; chmod +x "$T/bin/claude-node"
  check "$(REGATTA_UNATTENDED=dispatch COUNCIL_CLAUDE="$T/bin/claude-node" council_py 'print(c.verdict_target())')" "(None, ['$T/bin/claude-node', '$T/bin/codex', '$T/bin/agy'])" \
    "  a node script in place of claude, unattended: no verdict either (round 4's node rule is the holders scan's alone)"
  mkdir -p "$T/pathfirst"; printf '#!/bin/sh\n' > "$T/pathfirst/claude"; chmod +x "$T/pathfirst/claude"
  check "$(PATH="$T/pathfirst:$PATH" REGATTA_UNATTENDED=dispatch COUNCIL_CLAUDE= COUNCIL_AGY= HARNESS_CODEX= council_py 'print(c.verdict_target())')/$(PATH="$T/realcli:$PATH" COUNCIL_HARNESS=/x/h COUNCIL_CLAUDE= COUNCIL_AGY= HARNESS_CODEX= COUNCIL_FENCES_STATE= council_py 'print(c.verdict_target())')" \
    "(None, ['claude'])/(None, ['/x/h'])" "  a stand-in first on PATH under the CLI's name, or a harness of the caller's: no verdict to this Mac's file (round 5b)"
  R=$(lastrun)
  check "$(grep -c '^[0-9]' "$T/fences1.txt")" 10 "  a row per case and one for the denied tool"
  has "$T/fences1.txt" "opus" "  a column per arm"
  check "$(grep '^verdict' "$T/fences1.txt" | tr -s ' ')" "verdict held held held" "  held, all three"
  check "$(grep '^10 a denied tool' "$T/fences1.txt" | grep -c 'not offered.*no such item.*denied by our hook')" 1 "  the denied tool: not offered (Claude), no such item (Codex), denied by our hook (agy)"
  has "$T/fences1.txt" "ok: 200" "  the cell quotes a short output"
  has "$T/fences1.txt" "antigravity: steps seen: generate_image, run_command" "  agy's step names from its own stream"
  has "$T/fences1.txt" "denied by our hook: generate_image" "  judged against our hook's allowlist"
  has "$T/fences1.txt" "codex features: " "  codex features list diffed against the pinned list"
  has "$T/fences1.txt" "every one judged" "  none new"
  check "$(jget "$R/run.json" '(d["kind"], sorted(d["fences"]), d["fences"]["opus"]["verdict"])')" "('fences', ['antigravity', 'codex', 'opus'], 'held')" "  run.json: kind fences, a verdict per arm"
  check "$(jget "$T/fences-state.json" '[d["clis"][a]["verdict"] for a in ("claude", "codex", "agy")] + [d["offered"]["agy"]]')" \
    "['held', 'held', 'held', ['list_dir', 'run_command', 'call_mcp_tool']]" "  this Mac's verdicts kept per CLI, and what agy offers"
  check "$([ -f "$R/fences.txt" ] && echo kept)" kept "  the table kept in the run dir"
  C examine --run "$R" --draft "$T/draft.md" > /dev/null 2>&1; check "$?" 2 "  examine refuses a fences run"

  STUB_FENCES=bad STUB_AGY_TOOLS=browser_new_thing C fences --home "$H" > "$T/fences2.txt" 2>&1; check "$?" 1 "a case that does not hold: exit 1"
  check "$(grep '^verdict' "$T/fences2.txt" | tr -s ' ')" "verdict broken broken broken" "  broken"
  check "$(grep '^7 /private/tmp denied' "$T/fences2.txt" | grep -o BROKEN | wc -l | tr -d ' ')" 3 "  the cell says so, each arm"
  has "$T/fences2.txt" "opus: REFUSED from now on — ls /private/tmp: expected /private/tmp denied, got exit 0" "  the arm refused with the reason"
  has "$T/fences2.txt" "row C, the APIs" "  C named as the way out"
  has "$T/fences2.txt" "new since the last fences run: browser_new_thing" "  a step agy newly offers, diffed against the last run"
  C run --home "$H" --brief "$T/brief.md" > /dev/null 2>&1
  R=$(lastrun); check "$(jget "$R/run.json" '[(d["arms"][a]["state"], "council fences" in (d["arms"][a]["why"] or "") and "row C" in d["arms"][a]["why"]) for a in ("opus", "codex", "antigravity")]')" \
    "[('refused', True), ('refused', True), ('refused', True)]" "  a later council run refuses each broken arm, naming fences and C"
  C review --home "$H" > /dev/null 2>&1; check "$?" 1 "  review too"
  R=$(lastrun); check "$(jget "$R/run.json" '(d["arms"]["codex"]["state"], "council fences" in d["arms"]["codex"]["why"])')" "('refused', True)" "  its Codex arm refused, naming fences"
  check "$(council_py 'print(c.CLI_OF[c.base_record("antigravity-claude", {"provider": "antigravity"})["provider"]], c.fences_why("agy") is not None)')" \
    "agy True" "  a verdict is the CLI's: antigravity-claude, agy too, is refused with antigravity"
  cp "$T/fences-state.json" "$T/fences-state.keep"; printf '{"clis": {"claude": ' > "$T/fences-state.json"
  C run --home "$H" --brief "$T/brief.md" --arms opus > /dev/null 2>&1
  R=$(lastrun); check "$(jget "$R/run.json" '(d["arms"]["opus"]["state"], "verdicts do not read" in d["arms"]["opus"]["why"])')" "('refused', True)" "a torn verdict file refuses every arm (never read as none)"
  n0=$(nruns); C fences --home "$H" > /dev/null 2>&1; check "$?" 2 "  fences refuses before any arm runs"
  check "$(nruns) $(head -c 20 "$T/fences-state.json")" "$n0 {\"clis\": {\"claude\": " "  no run made, the file not overwritten"
  mv "$T/fences-state.keep" "$T/fences-state.json"
  STUB_FENCES=ok C fences --home "$H" > /dev/null 2>&1; check "$?" 0 "a fences run that holds"
  C run --home "$H" --brief "$T/brief.md" > /dev/null 2>&1
  R=$(lastrun); check "$(jget "$R/run.json" '[d["arms"][a]["state"] for a in ("opus", "codex", "antigravity")]')" "['ok', 'ok', 'ok']" "  clears the refusal"

  STUB_FENCES=refused C fences --home "$H" --arms opus > "$T/fences-refused.txt" 2>&1; check "$?" 0 "Claude's Agent asked for, refused by claude itself: held"
  has "$T/fences-refused.txt" "refused by claude" "  the cell says so"
  has "$T/fences-refused.txt" "refused by the CLI: Agent" "  and its steps line"
  R=$(lastrun); check "$(jget "$R/run.json" '(d["arms"]["opus"]["state"], d["arms"]["opus"]["record"]["denied"])')" "('ok', ['Agent'])" "  F5: a denial, not a failed arm"
  cat > "$T/judge.py" <<'PY'
import json, os, sys
from importlib.machinery import SourceFileLoader
c = SourceFileLoader("council", sys.argv[1]).load_module()
d = sys.argv[2]; os.makedirs(d, exist_ok=True)
def judge(cmds, state="ok", extra=()):
    with open(os.path.join(d, "claude.jsonl"), "w") as f:
        for e in extra:
            f.write(json.dumps(e) + "\n")
        for i, (cmd, code, out) in enumerate(cmds):
            f.write(json.dumps({"type": "assistant", "message": {"content": [{"type": "tool_use", "id": "t%d" % i, "name": "Bash", "input": {"command": cmd}}]}}) + "\n")
            f.write(json.dumps({"type": "user", "message": {"content": [{"type": "tool_result", "tool_use_id": "t%d" % i, "is_error": code != 0, "content": out}]}}) + "\n")
    rec = {"provider": "claude", "state": state}
    if state != "timeout":
        rec["record"] = c.fence.record("claude", os.path.join(d, "claude.jsonl"), list(c.CLAUDE_TOOLS))
    j = c.judge_arm("opus", rec, d, None)
    return j["verdict"], j["cells"][6][0], j["cells"][8][0]
ok = [(x[0], 1 if "Operation" in x[1] or "No such" in x[1] else 0, x[1]) for x in [
    ("ls .", "AGENTS.md"), ("head -1 /etc/hosts", "##"), (c.FENCE_CASES[2][0], "head: Operation not permitted"),
    (c.FENCE_CASES[3][0], "ls: Operation not permitted"), ('curl -sS -m 8 -o /dev/null -w "%{http_code}" https://example.com/', "200"),
    ('curl -sS -m 4 -o /dev/null -w "%{http_code}" http://127.0.0.1:22/', "403"), ("ls /private/tmp", "Operation not permitted"),
    ("touch ./probe-wrote && echo wrote", "wrote"), ("ls /Library/Preferences", "Operation not permitted")]]
batched = ok[:6] + [("ls /private/tmp; ls /Library/Preferences", 1, "com.apple.x\nOperation not permitted"), ok[7]]
twice = ok + [("ls /private/tmp", 0, "com.apple.x")]
broke = ok[:6] + [("ls /private/tmp", 0, "com.apple.x")]
agent = {"type": "assistant", "message": {"content": [{"type": "tool_use", "id": "ag", "name": "Agent", "input": {}}]}}
came = {"type": "user", "message": {"content": [{"type": "tool_result", "tool_use_id": "ag", "is_error": False, "content": "a sub-agent ran"}]}}
print(judge(ok), judge(batched), judge(twice), judge(broke, "timeout"))
agent2 = {"type": "assistant", "message": {"content": [{"type": "tool_use", "id": "ag2", "name": "Agent", "input": {}}]}}
refused = {"type": "user", "message": {"content": [{"type": "tool_result", "tool_use_id": "ag", "is_error": True,
           "content": "<tool_use_error>Error: No such tool available: Agent. Agent is disabled</tool_use_error>"}]}}
cutbash = ok[:8] + [("ls /Library/Preferences", None, None)]
def judge_cut(cmds):
    # the last command's call written with no result, as a kill leaves it
    with open(os.path.join(d, "claude.jsonl"), "w") as f:
        for i, (cmd, code, out) in enumerate(cmds):
            f.write(json.dumps({"type": "assistant", "message": {"content": [{"type": "tool_use", "id": "t%d" % i, "name": "Bash", "input": {"command": cmd}}]}}) + "\n")
            if code is not None:
                f.write(json.dumps({"type": "user", "message": {"content": [{"type": "tool_result", "tool_use_id": "t%d" % i, "is_error": code != 0, "content": out}]}}) + "\n")
    j = c.judge_arm("opus", {"provider": "claude", "state": "timeout"}, d, None)
    return j["verdict"], j["cells"][8]
print(judge(ok, "timeout", [agent, came])[0], judge(ok, "timeout", [agent])[0], judge(ok, "timeout", [agent, came, agent2])[0],
      judge(ok, "timeout", [agent, refused, agent2])[0], c.judge_arm("opus", {"provider": "claude", "state": "timeout"}, d, None)["denied"][1])
print(judge_cut(cutbash))
PY
  check "$(python3 "$T/judge.py" "$B/council" "$T/judge")" \
    "('held', True, True) ('unproven', None, None) ('broken', False, True) ('broken', False, None)
broken unproven broken unproven refused by claude
('unproven', (None, 'cut'))" \
    "the judge: two cases batched in one command are not run; a case run twice judged by both; a timed-out arm's log still read: a call that came back still breaks it (beside a cut one of the same tool too), one the kill cut is unproven, a refusal the log proved stays, a case whose command was cut is not run"
  for m in loopback short ran; do
    STUB_FENCES=$m C fences --home "$H" --arms opus,antigravity > "$T/fences-$m.txt" 2>&1; echo "rc=$?" >> "$T/fences-$m.txt"
  done
  has "$T/fences-loopback.txt" "BROKEN: curl: (1) Received" "loopback answered (no proxy 403, no seatbelt refusal): broken"
  has "$T/fences-loopback.txt" "rc=1" "  exit 1"
  check "$(grep '^verdict' "$T/fences-short.txt" | tr -s ' ')" "verdict unproven unproven" "five of nine run: unproven, not held"
  STUB_FENCES=ok STUB_AGY_UNTRIED=1 C fences --home "$H" --arms antigravity > "$T/fences-untried.txt" 2>&1; check "$?" 3 "agy's denied tool not tried: exit 3"
  check "$(grep '^verdict' "$T/fences-untried.txt" | tr -s ' ')" "verdict unproven" "  unproven, never held"
  has "$T/fences-short.txt" "4 of the 9 commands not run" "  saying how many"
  check "$(jget "$T/fences-state.json" 'd["clis"]["claude"]["verdict"]')" "broken" "  an unproven run keeps the last verdict (loopback's broken)"
  has "$T/fences-short.txt" "rc=3" "  exit 3: an arm could not be judged"
  check "$(grep '^verdict' "$T/fences-ran.txt" | tr -s ' ')" "verdict broken broken" "the denied tool ran: broken"
  has "$T/fences-ran.txt" "RAN: " "  the cell says it ran"

  check "$(council_py 'print(c.vendor_config(".mcp.json"), c.vendor_config("sub/.MCP.json"), c.vendor_config("docs/mcp.json"))')" \
    "True True False" "every copy loses its .mcp.json (claude mcp list runs in the copy, outside the box)"
  check "$(council_py 'print(c.vendor_config(".codex"), c.vendor_config("sub/.Gemini"), c.vendor_config(".claude"), c.vendor_config(".claude", link=True))')" \
    "True True False True" "a vendor folder's name as the last part (a tracked link of it), and .claude as a link (the fourth landing review, finding 11)"
  mkdir -p "$REGATTA_CONFIG/wharf"; python3 - "$M/settings/models.json" "$REGATTA_CONFIG/wharf/models.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
rows = d["sites"]
rows["council.antigravity-claude"] = dict(rows["council.antigravity"], model="claude-on-agy")
json.dump(d, open(sys.argv[2], "w"))
PY
  STUB_FENCES=ok STUB_AGY_BAD_MODEL="$(python3 -c "import json; d=json.load(open('$M/settings/models.json')); print(d['sites']['council.antigravity']['model'])")" \
    C fences --home "$H" --arms antigravity,antigravity-claude > "$T/fences-two.txt" 2>&1; check "$?" 1 "two arms of one CLI, antigravity broken, antigravity-claude held"
  check "$(grep '^verdict' "$T/fences-two.txt" | tr -s ' ') / $(jget "$T/fences-state.json" 'd["clis"]["agy"]["verdict"]')" "verdict broken held / broken" "  the CLI's verdict is broken: a held arm of it never clears it"
  rm -rf "$REGATTA_CONFIG/wharf"
  printf '{"arms": {"codex": {"verdict": "broken"}}}' > "$T/fences-state.json"
  check "$(council_py 'print("do not read" in (c.fences_why("codex") or ""))')" "True" "a verdict file in the shape before the CLI keys reads as torn, never as none"
  printf '{"clis": {"codex": "broken"}}' > "$T/fences-state.json"
  check "$(council_py 'print("do not read" in (c.fences_why("claude") or ""))')" "True" "  an entry that is no verdict: torn, never a crash"
  printf '{"clis": {"codex": {"verdict": "broken", "why": 3}}}' > "$T/fences-state.json"
  check "$(council_py 'print("do not read" in (c.fences_why("codex") or ""))')" "True" "  a why that is no list: torn"
  printf '{"clis": {"codex": {"verdict": "brokn", "why": []}}}' > "$T/fences-state.json"
  check "$(council_py 'print("do not read" in (c.fences_why("codex") or ""))')" "True" "  a damaged verdict: torn, never read as not broken"
  printf '{"clis": {}, "offered": ["x"]}' > "$T/fences-state.json"
  check "$(council_py 'print("do not read" in (c.fences_why("codex") or ""))')" "True" "  an offered list that is no map: torn"
  rm -f "$T/fences-state.json"
  cp "$STUB_FEATURES" "$T/features.bak"; printf '%-40s stable             true\n' brand_new_feature >> "$STUB_FEATURES"
  STUB_FENCES=ok C fences --home "$H" > "$T/fences3.txt" 2>&1; check "$?" 3 "a new feature on: exit 3, the Codex arm unjudged"
  has "$T/fences3.txt" "NEW, unjudged (the Codex arm is refused until fence.CODEX_FEATURES names each): brand_new_feature" "a new stable feature named in the diff"
  check "$(grep '^verdict' "$T/fences3.txt" | tr -s ' ')" "verdict held unproven held" "  the Codex arm refused by harness, unproven"
  check "$(jget "$T/fences-state.json" '"codex" in d["clis"]')" "False" "  no verdict for it"
  mv "$T/features.bak" "$STUB_FEATURES"
  grep -v '^shell_tool ' "$STUB_FEATURES" > "$T/features.cut"; STUB_FEATURES="$T/features.cut" STUB_FENCES=ok C fences --home "$H" --arms codex > "$T/fences4.txt" 2>&1
  has "$T/fences4.txt" "gone since pinned: shell_tool" "a pinned feature no longer on: named"
fi

[ "$fails" = 0 ] && echo "test_council: all passed" || echo "test_council: $fails FAILED"
[ "$fails" = 0 ]
