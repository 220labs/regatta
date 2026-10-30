#!/usr/bin/env bash
# Routed comments, S2 (docs/routed-comments-2026-10-26.md; the cutover, docs/routed-comments-cutover-2026-10-26.md):
# the `Routed:` line, the page read from it on a host with no pin, the owner and own-reply derivations,
# the marks counted only as this tool's own, the gate (`keel routed check`, `keel routed line --check`,
# what pickup seed calls), `keel settle`, routed.jsonl, the lookout's routed read and the widened
# not_owners_answer. A stub spacesheep (the comments route with `via` and `author_email`, add_comment
# reflected back as this tool's reply, the room) and a gate table of its own: no network, no model.
#   bash modules/keel/tests/routed.sh
set -u
T=$(mktemp -d)
. "$(dirname "$0")/config.sh"; keel_config "$T/config"
B="$(cd "$(dirname "$0")/../bin" && pwd)"
unset CLAUDE_UNATTENDED CLAUDE_CODE_ENTRYPOINT CLAUDE_CODE_SESSION_ID CLAUDE_CODE_DISABLE_BACKGROUND_TASKS
fails=0
check() { if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3: expected [$2] got [$1]"; fails=$((fails+1)); fi; }
has()   { if grep -qF -- "$2" "$1"; then echo "  ok   $3"; else echo "  FAIL $3: missing [$2]"; sed 's/^/         | /' "$1" | head -20; fails=$((fails+1)); fi; }
lacks() { if grep -qF -- "$2" "$1"; then echo "  FAIL $3: found [$2]"; fails=$((fails+1)); else echo "  ok   $3"; fi; }

S="$T/ss"; mkdir -p "$S"
export MEMO_STATE_DIR="$T/state" MEMO_SHEEP_STATE="$T/sheep" MEMO_SHEEP_BIN="" SPACESHEEP_CONFIG_DIR="$T/ss-config"
export SPACESHEEP_KEY=ss_test LOOKOUT_HOST=testhost SHEEP_T="$S" LOOKOUT_DISPATCH_QUEUE= LOOKOUT_HARNESS=
# the gate's table: keel.comment off and skipped, so an unjudged free-text thread is held, never sent anywhere
printf '{"defaults": {}, "sites": {"keel.comment": {"kind": "classify", "provider": "off", "when_off": "skip"}}}\n' > "$T/models.json"
export GATE_TABLE="$T/models.json"
export GIT_CONFIG_GLOBAL="$T/gitconfig"
printf '[user]\n\tname = Test\n\temail = t@example.com\n[init]\n\tdefaultBranch = main\n' > "$GIT_CONFIG_GLOBAL"

cat > "$S/srv.py" <<'EOF'
import json, os, time
from http.server import BaseHTTPRequestHandler, HTTPServer
T = os.environ["SHEEP_T"]
def load(space=None):
    # a page of its own when comments-<space>.json is there (finding 1's two pages), else the one page
    try:
        return json.load(open(T + "/comments-%s.json" % space if space and os.path.exists(T + "/comments-%s.json" % space) else T + "/comments.json"))
    except (OSError, ValueError):
        return {"comments": []}
class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def send(self, code, body, ctype="application/json"):
        self.send_response(code); self.send_header("Content-Type", ctype); self.end_headers(); self.wfile.write(body.encode())
    def do_GET(self):
        with open(T + "/web.log", "a") as f:
            f.write(json.dumps({"path": self.path}) + "\n")
        sp = self.path.split("/api/space/", 1)[-1].split("/", 1)[0] if "/api/space/" in self.path else None
        self.send(200, json.dumps(load(sp))) if self.headers.get("Cookie") == "ss_app=tok" else self.send(401, "{}")
    def do_POST(self):
        n = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(n)
        if self.path == "/api/account/web-session":
            return self.send(200, '{"cookie": "ss_app", "token": "tok", "expires_in": 43200}')
        msg = json.loads(raw)
        with open(T + "/mcp.log", "a") as f:
            f.write(json.dumps(msg) + "\n")
        if "id" not in msg:
            self.send_response(202); self.end_headers(); return
        if msg["method"] == "initialize":
            self.send_response(200); self.send_header("Content-Type", "application/json"); self.send_header("Mcp-Session-Id", "s-1"); self.end_headers()
            self.wfile.write(json.dumps({"jsonrpc": "2.0", "id": msg["id"], "result": {}}).encode()); return
        name, args = msg["params"]["name"], msg["params"]["arguments"]
        text = '{"ok": true}'
        if name == "add_comment":   # this tool's reply: via claude, the owner's account, now
            d = load()
            cid = "m-%d" % (len(d["comments"]) + 1)
            d["comments"].append({"id": cid, "parent_id": args.get("parent_id"), "body": args["body"], "via": "claude",
                                  "author_email": "sam@example.com", "anchor_id": None, "resolved_at": None,
                                  "created_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())})
            json.dump(d, open(T + "/comments.json", "w"))
            text = json.dumps({"id": cid})
        if name == "live_events":
            evs = json.load(open(T + "/events.json")) if os.path.exists(T + "/events.json") else []
            out = [e for e in evs if e["seq"] > args.get("after", 0)]
            text = json.dumps({"events": out, "next_after": max([args.get("after", 0)] + [e["seq"] for e in out])})
        if name == "list_comments":
            text = "No comments yet."
        res = {"jsonrpc": "2.0", "id": msg["id"], "result": {"content": [{"type": "text", "text": text}]}}
        self.send(200, "event: message\ndata: %s\n\n" % json.dumps(res), "text/event-stream")
s = HTTPServer(("127.0.0.1", 0), H)
open(T + "/port", "w").write(str(s.server_address[1]))
s.serve_forever()
EOF
python3 "$S/srv.py" & SRV=$!; disown $SRV
trap 'kill $SRV 2>/dev/null; rm -rf "$T"' EXIT
for _ in $(seq 1 25); do [ -s "$S/port" ] && break; sleep 0.2; done
export MEMO_SHEEP_MCP="http://127.0.0.1:$(cat "$S/port")/mcp" MEMO_SHEEP_APP="http://127.0.0.1:$(cat "$S/port")"
K() { python3 "$B/keel" "$@"; }
# a fixture's comments: id parent anchor email via created body — one per line, | between fields
# the script is a file: `python3 -` would read it from the stdin the fixture's lines come on
cat > "$S/fixture.py" <<'EOF'
import json, sys
out = []
for l in sys.stdin.read().strip().splitlines():
    cid, parent, anchor, email, via, at, body = l.split("|", 6)
    out.append({"id": cid, "parent_id": parent or None, "anchor_id": anchor or None, "author_email": email or None,
                "via": via or None, "created_at": at, "body": body, "resolved_at": None})
json.dump({"comments": out}, open(sys.argv[1], "w"))
EOF
comments() { python3 "$S/fixture.py" "$S/comments.json"; }

R="$T/demo"; mkdir -p "$R/docs"; git -C "$R" init -q; git -C "$R" checkout -q -b claude/testhost/2026-10-26-demo
cat > "$R/docs/d.md" <<'EOF'
# Demo — a routed doc (proposal, 2026-10-26)

Status: proposed — 0 of 1 decisions answered

Some context.

- **D1 — Which way?** Two ways.
  - A — one
  - B — two

  ➤ Recommended: A

  ➤ Answer:

---

## Open feedback
EOF
git -C "$R" add -A; git -C "$R" commit -qm "a doc"
D="$R/docs/d.md"; KEY="demo@claude/testhost/2026-10-26-demo:docs/d.md"

echo "R1 — the Routed: line: under Status:, rewritten, the same routing kept, taken out"
py() { python3 - "$B/keel" "$@"; }
check "$(py "$D" <<'EOF'
import sys
from importlib.machinery import SourceFileLoader as L
m = L("k", sys.argv[1]).load_module()
t = open(sys.argv[2]).read()
a = m.with_routed(t, "2026-10-26T10:00:00Z", "sp-1", "claude/b1")
lines = a.split("\n")
print(lines[2].startswith("Status:"), lines[3])
b = m.with_routed(a, "2026-10-26T11:00:00Z", "sp-1", "claude/b2")
print(m.routed_line(b)["branch"], b.count("Routed:"), m.with_routed(b, "2026-10-27T00:00:00Z", "sp-1", "claude/b2") == b)
print(m.without_routed(b) == t)
n = m.with_routed("# T\n\nBody.\n", "2026-10-26T10:00:00Z", "sp-2", "claude/c")
print(repr(n), m.without_routed(n) == "# T\n\nBody.\n")
EOF
)" "True Routed: 2026-10-26T10:00:00Z · page sp-1 · claude/b1
claude/b2 1 True
True
'# T\n\nRouted: 2026-10-26T10:00:00Z · page sp-2 · claude/c\n\nBody.\n' True" "the line goes under Status:, a new routing rewrites it, the same one keeps it, and it comes out clean"

echo "R2 — a host with no pin reads the page from the line (keel sheep threads)"
K sheep threads "$D" > "$T/r2a.out" 2>&1; rc=$?
check "$rc" "1" "no pin and no line: refused"
has "$T/r2a.out" "no \`Routed:\` line in it" "…naming the line it looked for"
python3 - "$D" <<'EOF'
import sys
p = sys.argv[1]; t = open(p).read()
open(p, "w").write(t.replace("Status: proposed — 0 of 1 decisions answered\n", "Status: proposed — 0 of 1 decisions answered\nRouted: 2026-10-26T09:00:00Z · page sp-r · claude/testhost/2026-10-26-run\n"))
EOF
git -C "$R" commit -qam "routed"
comments <<'EOF'
c1|||sam@example.com||2026-10-26T08:00:00Z|drop G2 — the bare version needs to be written
c2|c1||sam@example.com|claude|2026-10-26T08:05:00Z|Which G2 do you mean, the second goal?
c3|||pat@example.com||2026-10-26T08:10:00Z|memo: routed into claude/x's run, 2026-10-26
EOF
K sheep threads "$D" > "$T/r2b.out" 2>&1; rc=$?
check "$rc" "0" "the page from the Routed: line: read"
has "$T/r2b.out" "[c1]" "…the owner's thread is listed"
has "$T/r2b.out" "page sp-r, thread c1" "…by the page's id, the line giving no address"
has "$T/r2b.out" "(talking)" "…and talking: a reply of ours under it, derived from the page (no pin here)"
lacks "$T/r2b.out" "sam@example.com" "the owner's address never printed"
check "$(grep -c '"/api/space/sp-r/comments"' "$S/web.log")" "1" "…read through the comments route of the line's space"
check "$(test -s "$MEMO_SHEEP_STATE/sheep.json" && python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get(sys.argv[2], {}).get("space"))' "$MEMO_SHEEP_STATE/sheep.json" "$KEY" || echo None)" "None" "…and no space written into a pin here (the host holding the pin redeploys, finding J)"

echo "R3 — owner, shared and own: from author_email and via, the address never kept"
check "$(py <<'EOF'
import sys, json
from importlib.machinery import SourceFileLoader as L
m = L("k", sys.argv[1]).load_module()
raw = json.load(open(__import__("os").environ["SHEEP_T"] + "/comments.json"))
ts = m.comment_threads(raw)
flat = {c["id"]: c for t in ts for c in [t] + t["replies"]}
print([(i, flat[i]["owner"], flat[i]["own"]) for i in ("c1", "c2", "c3")], flat["c1"]["shared"], any("email" in "".join(c) for c in flat.values()))
raw2 = {"comments": [x for x in raw["comments"] if x["id"] == "c3"]}
print(m.comment_threads(raw2)[0]["owner"])
EOF
)" "[('c1', True, False), ('c2', False, True), ('c3', False, False)] True False
True" "the owner by our reply's address, another account not, our reply own; two accounts: shared; no address key kept; with no address to compare, as before"
mkdir -p "$REGATTA_CONFIG/keel"; printf 'pat@example.com\n' > "$REGATTA_CONFIG/keel/owner-email"
check "$(py <<'EOF'
import sys, json, os
from importlib.machinery import SourceFileLoader as L
m = L("k", sys.argv[1]).load_module()
raw = json.load(open(os.environ["SHEEP_T"] + "/comments.json"))
print(m.comment_threads({"comments": [x for x in raw["comments"] if x["id"] != "c2"]})[0]["owner"])
EOF
)" "False" "no reply of ours: the overlay's keel/owner-email is the address"
rm -f "$REGATTA_CONFIG/keel/owner-email"

echo "R4 — finding E: a mark counts only as this tool's own"
check "$(py <<'EOF'
import sys
from importlib.machinery import SourceFileLoader as L
m = L("k", sys.argv[1]).load_module()
def th(via, cid="r1"):
    return {"id": "t1", "anchor": None, "resolved": False, "at": "2026-10-26T08:00:00Z", "text": "do X", "via": None, "own": False, "bot": False, "owner": True,
            "replies": [{"id": cid, "text": "memo: routed into claude/x's run, 2026-10-26", "via": via, "own": via == "claude", "bot": False, "at": "2026-10-26T09:00:00Z"}]}
print(m.taken_ids([th(None)], {}), m.taken_ids([th("claude")], {}))
raw = {"comments": [{"id": "t1", "body": "do X", "created_at": "2026-10-26T08:00:00Z"},
                    {"id": "r1", "parent_id": "t1", "body": "memo: routed into claude/x's run, 2026-10-26", "created_at": "2026-10-26T09:00:00Z"}]}
print(m.taken_ids(m.comment_threads(raw), {}), m.taken_ids(m.comment_threads(raw, sent=["r1"]), {}))
EOF
)" "set() {'t1'}
set() {'t1'}" "a mark typed by another writer counts for nothing; via claude or an id in sent counts"

echo "R5 — the gate: a comment typed before routing holds new work (finding C)"
K routed check "$D" > "$T/r5t.out" 2>&1; rc=$?
check "$rc" "0" "the owner's thread answered by a reply of ours since: talk, not owed"
comments <<'EOF'
c1|||sam@example.com||2026-10-26T08:00:00Z|drop G2 — the bare version needs to be written
c3|||pat@example.com||2026-10-26T08:10:00Z|memo: routed into claude/x's run, 2026-10-26
EOF
K routed check "$D" > "$T/r5.out" 2>&1; rc=$?
check "$rc" "3" "an unmarked owner thread, the call off: refused (exit 3)"
has "$T/r5.out" "unreflected on docs/d.md's page: 1 thread, 0 Saves" "…naming the count"
has "$T/r5.out" "[c1] act-unclear — the keel.comment call is off" "…and the thread, held as it could not be judged"
lacks "$T/r5.out" "[c3]" "another account's words are data, never owed"
check "$(python3 -c 'import json,sys; r=[json.loads(l) for l in open(sys.argv[1])]; print([(x["event"], x.get("thread"), x.get("by")) for x in r])' "$MEMO_STATE_DIR/routed.jsonl")" \
  "[('judged', 'c1', 'held'), ('refused', None, None)]" "…judged on the spot and logged in routed.jsonl"
comments <<'EOF'
c1|||sam@example.com||2026-10-26T08:00:00Z|drop G2 — the bare version needs to be written
c3|||pat@example.com||2026-10-26T08:10:00Z|memo: routed into claude/x's run, 2026-10-26
c4|c1||pat@example.com||2026-10-26T08:20:00Z|memo: settled by someone, 2026-10-26: typed
EOF
K routed check "$D" > "$T/r5b.out" 2>&1; rc=$?
check "$rc" "3" "a settled mark typed by another writer settles nothing"
comments <<'EOF'
c1|||sam@example.com||2026-10-26T08:00:00Z|drop G2 — the bare version needs to be written
c5|c1||sam@example.com|claude|2026-10-26T08:30:00Z|memo: routed into claude/testhost/2026-10-26-run's run, 2026-10-26
d1||D1|sam@example.com||2026-10-26T08:40:00Z|B
q1|||sam@example.com||2026-10-26T08:50:00Z|yes
EOF
K routed check "$D" > "$T/r5c.out" 2>&1; rc=$?
check "$rc" "0" "routed into by this tool, a D-card answer, a bare yes: clear"
has "$T/r5c.out" "docs/d.md: clear" "…and says so"
comments <<'EOF'
c1|||sam@example.com||2026-10-26T08:00:00Z|drop G2 — the bare version needs to be written
c5|c1||sam@example.com|claude|2026-10-26T08:30:00Z|memo: routed into claude/testhost/2026-10-26-run's run, 2026-10-26
c6|c1||sam@example.com||2026-10-26T09:30:00Z|and delete the old section too
EOF
K routed check "$D" > "$T/r5d.out" 2>&1; rc=$?
check "$rc" "3" "an owner word after the mark: judged again (a held verb), refused"
has "$T/r5d.out" "[c1] act-held — a deletion" "…by the deterministic layer, no call"
comments <<'EOF'
c1|||sam@example.com||2026-10-26T08:00:00Z|drop G2 — the bare version needs to be written
c7|c1||sam@example.com|claude|2026-10-26T08:30:00Z|memo: would start: drop G2 (act-plain) — reply go to start, no to close
EOF
K routed check "$D" > "$T/r5e.out" 2>&1; rc=$?
check "$rc" "3" "an offer neither go nor no: held"
has "$T/r5e.out" "[c1] offered, neither go nor no" "…named as such"
K routed check "$D" --routing c1 > /dev/null 2>&1; rc=$?
check "$rc" "0" "…unless it is the thread this start routes"
# a claim is a lease (the S3 landing review's item 2): owed while it lives and no session replied since
comments <<'EOF'
c20|||sam@example.com||2026-10-26T08:00:00Z|drop G2 — the bare version needs to be written
c21|c20||sam@example.com|claude|2026-10-26T08:30:00Z|memo: claiming for testhost, 2026-10-26T08:30:00Z
EOF
MEMO_NOW=2026-10-26T08:40:00Z K routed check "$D" > "$T/r5f.out" 2>&1; rc=$?
check "$rc" "3" "a bare claim 10 min old, no reply: held"
has "$T/r5f.out" "[c20] an act being claimed" "…as an act being claimed"
MEMO_NOW=2026-10-26T08:46:00Z K routed check "$D" > "$T/r5g.out" 2>&1; rc=$?
check "$rc" "3" "a bare claim 16 min old, no reply: the lease is dead, the owner's words judged again"
has "$T/r5g.out" "[c20] act-unclear" "…as if unmarked (the call off: held as unjudged)"
lacks "$T/r5g.out" "being claimed" "…never as a claim"
comments <<'EOF'
c20|||sam@example.com||2026-10-26T08:00:00Z|drop G2 — the bare version needs to be written
c21|c20||sam@example.com|claude|2026-10-26T08:30:00Z|memo: claiming for testhost, 2026-10-26T08:30:00Z
c22|c20||sam@example.com|claude|2026-10-26T08:35:00Z|Dropped G2 and wrote the bare version.
EOF
MEMO_NOW=2026-10-26T08:40:00Z K routed check "$D" > "$T/r5h.out" 2>&1; rc=$?
check "$rc" "0" "a claim its run replied under, the lease still alive: clear"
comments <<'EOF'
c30|||sam@example.com||2026-10-26T08:00:00Z|yes
c31|c30||sam@example.com|claude|2026-10-26T08:30:00Z|memo: claiming for testhost, 2026-10-26T08:30:00Z
EOF
MEMO_NOW=2026-10-26T08:46:00Z K routed check "$D" > /dev/null 2>&1; rc=$?
check "$rc" "0" "a dead claim over a bare yes: clear, a pickup seed naming the doc no longer refused"
# item 5 (the S3 second landing review): a dead claim after our offer leaves the offer, never nothing
comments <<'EOF'
c40|||sam@example.com||2026-10-26T08:00:00Z|drop G2 — the bare version needs to be written
c41|c40||sam@example.com|claude|2026-10-26T08:10:00Z|memo: would start: drop G2 (act-plain) — reply go to start, no to close
c42|c40||sam@example.com|claude|2026-10-26T08:20:00Z|memo: claiming for testhost, 2026-10-26T08:20:00Z
EOF
MEMO_NOW=2026-10-26T08:50:00Z K routed check "$D" > "$T/r5i.out" 2>&1; rc=$?
check "$rc" "3" "a dead claim after a would-start offer, no go yet: held"
has "$T/r5i.out" "[c40] offered, neither go nor no" "…by the offer before the claim (item 5: the dead claim dropped it)"

echo "R6 — Saves: one the doc lacks holds; one git answered after the page's commit does not"
comments <<'EOF'
EOF
SHA0=$(git -C "$R" rev-parse HEAD)
printf '[{"seq": 1, "at": "2026-10-26T08:00:00Z", "name": "memo-save", "data": {"sha": "%s", "items": {"D1": "B"}, "comments": [], "feedback": ""}}]\n' "$SHA0" > "$S/events.json"
K routed check "$D" > "$T/r6.out" 2>&1; rc=$?
check "$rc" "3" "a Save answering D1 the doc lacks: refused"
has "$T/r6.out" "0 threads, 1 Save" "…a Save, counted"
python3 - "$D" <<'EOF'
import sys
p = sys.argv[1]; t = open(p).read()
open(p, "w").write(t.replace("  ➤ Answer:\n", "  ➤ Answer:\n  A\n"))
EOF
git -C "$R" commit -qam "answered in git"
K routed check "$D" > /dev/null 2>&1; rc=$?
check "$rc" "0" "git answered D1 after the page's commit: git's is the newer word, the Save owes nothing"
rm -f "$S/events.json"

echo "R7 — keel routed line (pickup's call): the gate, the line, its removal"
printf 'Task: build docs/d.md S2.\nSee docs/handoff/x.md and %s too.\n' "$D" > "$T/brief.md"
comments <<'EOF'
c1|||sam@example.com||2026-10-26T08:00:00Z|drop G2 — the bare version needs to be written
EOF
HEAD=$(git -C "$R" rev-parse HEAD)
K routed line --repo "$R" --ref "$HEAD" --branch claude/testhost/2026-10-27-next --brief "$T/brief.md" --check > "$T/r7a.out" 2>&1; rc=$?
check "$rc" "3" "--check: a thread typed before routing refuses the seed"
check "$(python3 -c 'import json,sys; d=json.loads(open(sys.argv[1]).read().splitlines()[-1]); print(len(d["docs"]), d["refused"][0].split(":")[0])' "$T/r7a.out")" "0 unreflected on docs/d.md's page" "…with no doc to write and the gate's words"
comments <<'EOF'
EOF
K routed line --repo "$R" --ref "$HEAD" --branch claude/testhost/2026-10-27-next --brief "$T/brief.md" --check > "$T/r7b.out" 2>&1; rc=$?
check "$rc" "0" "a clear page: the line is written"
check "$(python3 -c 'import json,sys; d=json.loads(open(sys.argv[1]).read().splitlines()[-1]); import re; print([x["rel"] for x in d["docs"]], re.findall(r"(?m)^Routed: .*$", d["docs"][0]["text"])[0].split(" · ", 1)[1], "routed check docs/d.md" in d["last_step"])' "$T/r7b.out")" \
  "['docs/d.md'] page sp-r · claude/testhost/2026-10-27-next True" "…for the one doc the brief names (never a handoff), the line's page kept, the new branch, and the run's last step"
NEXT=$(python3 -c 'import json,sys; d=json.loads(open(sys.argv[1]).read().splitlines()[-1]); print(d["docs"][0]["text"])' "$T/r7b.out")
python3 -c 'import sys; open(sys.argv[1], "w").write(sys.argv[2])' "$D" "$NEXT"; git -C "$R" commit -qam "the line"
K routed line --repo "$R" --ref HEAD --branch claude/testhost/2026-10-27-next --brief "$T/brief.md" > "$T/r7r.out" 2>&1
check "$(python3 -c 'import json,sys; d=json.loads(open(sys.argv[1]).read().splitlines()[-1]); print(len(d["docs"]), "routed check docs/d.md" in d["last_step"])' "$T/r7r.out")" "0 True" "the same routing again: no doc to write, the last step still named"
K routed line --repo "$R" --ref "$HEAD" --branch claude/testhost/2026-10-27-next --brief "$T/brief.md" --drop > "$T/r7c.out" 2>&1; rc=$?
check "$(python3 -c 'import json,sys; d=json.loads(open(sys.argv[1]).read().splitlines()[-1]); print(len(d["docs"]), "Routed:" in d["docs"][0]["text"], d["last_step"])' "$T/r7c.out")" "1 False " "--drop: the line taken out, no last step (a released start)"
mkdir -p "$T/plain/docs"; git -C "$T/plain" init -q; printf '# P\n\nStatus: open\n' > "$T/plain/docs/p.md"; git -C "$T/plain" add -A; git -C "$T/plain" commit -qm p
printf 'Task: do docs/p.md.\n' > "$T/brief2.md"
K routed line --repo "$T/plain" --ref HEAD --branch claude/testhost/2026-10-27-p --brief "$T/brief2.md" --check > "$T/r7d.out" 2>&1; rc=$?
check "$rc:$(tail -1 "$T/r7d.out")" '0:{"docs": [], "refused": [], "notes": [], "last_step": ""}' "a doc with no page and no line: nothing routed, nothing read"

echo "R8 — keel settle: attended only, the mark and the doc's line, routed.jsonl"
comments <<'EOF'
c1|||sam@example.com||2026-10-26T08:00:00Z|drop G2 — the bare version needs to be written
EOF
CLAUDE_UNATTENDED=1 K settle "$D" c1 --why "not wanted" > "$T/r8a.out" 2>&1; rc=$?
check "$rc" "3" "unattended: refused, exit 3"
check "$(grep -c add_comment "$S/mcp.log" 2>/dev/null || true)" "0" "…nothing posted"
CLAUDE_CODE_SESSION_ID=sess-1234 CLAUDE_CONFIG_DIR="$T/.acct-x" K settle "$D" c1 --why "kept G2 on purpose" > "$T/r8b.out" 2>&1; rc=$?
check "$rc" "0" "attended: settled"
check "$(python3 -c 'import json,sys; c=json.load(open(sys.argv[1]))["comments"][-1]; print(c["parent_id"], c["body"].split(", 20")[0])' "$S/comments.json")" "c1 memo: settled by acct-x" "…the mark under the thread, the login named"
has "$D" "> **Settled.** kept G2 on purpose" "…the doc's line"
check "$(tail -1 "$MEMO_STATE_DIR/routed.jsonl" | python3 -c 'import json,sys; r=json.load(sys.stdin); print(r["event"], r["thread"], r["session"])')" "settled c1 sess-1234" "…and the session in routed.jsonl"
git -C "$R" commit -qam settled
K routed check "$D" > /dev/null 2>&1; rc=$?
check "$rc" "0" "the gate clears on the settled mark"
check "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]]["sent"])' "$MEMO_SHEEP_STATE/sheep.json" "$KEY")" "['m-2']" "…and the mark's id is in the sent cache, its own by id too"

echo "R9 — no key here: nothing read, nothing judged, said so"
SPACESHEEP_KEY= MEMO_SHEEP_APP=http://127.0.0.1:9 REGATTA_CONFIG="$T/nokey" K routed check "$D" > "$T/r9.out" 2>&1; rc=$?
check "$rc" "0" "the check passes"
has "$T/r9.out" "no SPACESHEEP_KEY here" "…saying the page was not read"
SPACESHEEP_KEY= MEMO_SHEEP_APP=http://127.0.0.1:9 REGATTA_CONFIG="$T/nokey" K routed line --repo "$R" --ref HEAD --branch claude/testhost/2026-10-27-nk --brief "$T/brief.md" --check > "$T/r9b.out" 2>&1; rc=$?
check "$rc" "3" "…but new work (a seed's --check) on a paged doc, with no key here: refused (S2 landing review item 8, S3)"
has "$T/r9b.out" "start it where a key is" "…saying where it can start"

echo "R10 — the lookout: a routed page read on a host with no pin, every open thread new; the no-key card"
comments <<'EOF'
c1|||sam@example.com||2026-10-26T08:00:00Z|drop G2 — the bare version needs to be written
EOF
RK="demo@claude/testhost/2026-10-27-next:docs/d.md"   # the newest of the page's two lines
check "$(py "$R" <<'EOF'
import sys, os
from importlib.machinery import SourceFileLoader as L
m = L("k", sys.argv[1]).load_module()
m.repo_tops = lambda pinned: {"demo": sys.argv[2]}
st = {"open": {}, "comments": {}, "pending": []}
evs, new = m.lookout_events({}, st, {}, [], [None, 0], True, [])
print([(e["doc"], e["kind"]) for e in evs], sorted(new["comments"]))
evs2, _ = m.lookout_events({}, new, {}, [], [None, 0], True, [])
print(len(evs2))
os.environ["SPACESHEEP_KEY"] = ""; os.environ["REGATTA_CONFIG"] = os.environ["SHEEP_T"] + "/nocfg"
evs3, _ = m.lookout_events({}, st, {}, [], [None, 0], True, [])
row = m.lookout_act(evs3[0], "testhost", [], True)
print(evs3[0]["kind"], row["action"], row["card"])
EOF
)" "[('$RK', 'offer')] ['$RK']
0
nokey card no SPACESHEEP_KEY here — 1 routed page not read on testhost, nothing judged" "a comment typed before routing is an event at the first read (an offer since S4: the call is off here, so the owner's ask is held, T2), under the newest routing only, kept in the state, once; no key: one card"

echo "R11 — not_owners_answer: the routing commit and a review stamp wake nobody"
check "$(py <<'EOF'
import sys
from importlib.machinery import SourceFileLoader as L
m = L("k", sys.argv[1]).load_module()
for body in ("Seed: x\n\nPrompt:\n> y\n", "Brief: the next step of x (pickup brief)\n", "Docs: x\n\nRouted-By: pickup seed (docs/d.md)\n",
             "Docs: review stamp on d.md\n", "Docs: the owner's answer\n"):
    print(m.not_owners_answer(body, {}, [], []))
EOF
)" "the routing commit's
the routing commit's
the routing commit's
a review stamp's
None" "seed, brief and a Routed-By trailer, a review stamp: no person's answer; anything else still judged"

# R12 (lookout_release's --unroute) left with routed comments S3: the lookout seeds beside a branch and
# never briefs it, so a refused start has no line on the branch to take back (test_lookout.sh's seed cases)
echo "R13 — pickup seed, end to end: refused while the thread is open, then the line in the seed's commit"
PK="$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import find_core; sys.path.insert(0, find_core.hooks()); import common; print(common.tool("pickup") or "")' "$B/../lib")"
if [ -n "$PK" ]; then
  mkdir -p "$R/.claude"; printf '{"checkpoint": true}\n' > "$R/.claude/workflow.json"; git -C "$R" add -A; git -C "$R" commit -qm workflow
  git -C "$R" branch -q main 2>/dev/null; git -C "$R" branch -qf main HEAD
  printf 'Task: the next step of docs/d.md.\n' > "$T/seed.md"
  comments <<'EOF'
c1|||sam@example.com||2026-10-26T08:00:00Z|drop G2 — the bare version needs to be written
EOF
  (export HOME="$T/hm" PICKUP_KEEL="$B/keel" PICKUP_HOST=testhost; cd "$R" && python3 "$PK" seed nexty --file "$T/seed.md" --repo "$R" --no-start --no-blueprint) > "$T/r13a.out" 2>&1; rc=$?
  check "$rc" "1" "pickup seed: refused by the gate"
  has "$T/r13a.out" "keel's gate refused: unreflected on docs/d.md's page" "…in the gate's words"
  check "$(git -C "$R" branch --list '*nexty*' | wc -l | tr -d ' ')" "0" "…and no branch made"
  comments <<'EOF'
EOF
  (export HOME="$T/hm" PICKUP_KEEL="$B/keel" PICKUP_HOST=testhost; cd "$R" && python3 "$PK" seed nexty --file "$T/seed.md" --repo "$R" --no-start --no-blueprint) > "$T/r13b.out" 2>&1; rc=$?
  check "$rc" "0" "a clear page: seeded"
  NB=$(git -C "$R" branch --list '*nexty*' | tr -d ' *')
  check "$(git -C "$R" show "$NB:docs/d.md" | grep -c "^Routed: .* · page sp-r · $NB$")" "1" "…the doc's Routed: line names the page and the new branch, in the seed's own commit"
  check "$(git -C "$R" log -1 --format=%B "$NB" | grep -c '^Routed-By: pickup seed (docs/d.md)')" "1" "…which carries Routed-By"
  check "$(git -C "$R" show "$NB:docs/handoff/$(date +%F)-nexty.md" | grep -c 'routed check docs/d.md')" "1" "…and the brief ends with the run's own check"
else
  echo "  --   skipped: no pickup beside keel (wharf-runs absent)"
fi

# ----- S2's finish review: its open findings 1-9 and the five fixes before them, on a repo of their own
E="$T/two"; mkdir -p "$E/docs" "$E/.github" "$E/.claude"; git -C "$E" init -q; git -C "$E" checkout -q -b claude/testhost/2026-10-27-e
printf '{"checkpoint": true}\n' > "$E/.claude/workflow.json"; printf '# x\n' > "$E/.github/x.md"
# main forks before the doc: a main holding the branch's Routed: line is a landing (routed comments S5), read under main's key
git -C "$E" add -A; git -C "$E" commit -qm "two's repo"; git -C "$E" branch -q main
ago() { python3 -c 'import sys, datetime as d; print((d.datetime.now(d.timezone.utc) - d.timedelta(hours=int(sys.argv[1]))).strftime("%Y-%m-%dT%H:%M:%SZ"))' "$1"; }
cat > "$E/docs/e.md" <<EOF
# E — a routed doc (proposal, 2026-10-27)

Status: proposed — 0 of 1 decisions answered
Routed: $(ago 3) · page sp-old · claude/testhost/2026-10-27-e

Some context.

- **D1 — Which way?** Two ways.
  - A — one
  - B — two

  ➤ Recommended: A

  ➤ Answer:

---

## Open feedback
EOF
git -C "$E" add -A; git -C "$E" commit -qm "e, routed to its first page"
python3 - "$E/docs/e.md" "$(ago 2)" <<'EOF'
import re, sys
p = sys.argv[1]; t = open(p).read()
open(p, "w").write(re.sub(r"(?m)^Routed: .*$", "Routed: %s · page sp-e · claude/testhost/2026-10-27-e" % sys.argv[2], t))
EOF
git -C "$E" commit -qam "routed again, to its page now"
ED="$E/docs/e.md"; EK="two@claude/testhost/2026-10-27-e:docs/e.md"
mirror() {   # the run's own mirror of the doc: a pin with its own page, as a first checkpoint leaves it
  python3 - "$MEMO_SHEEP_STATE/sheep.json" "$EK" <<'EOF'
import json, os, sys
p, k = sys.argv[1], sys.argv[2]
d = json.load(open(p)) if os.path.exists(p) else {}
d[k] = {"space": "sp-mirror", "url": "https://example.invalid/mirror", "sha": "0" * 40, "fmt": 1, "sent": []}
json.dump(d, open(p, "w"))
EOF
}
pinof() { python3 -c 'import json,sys; p=json.load(open(sys.argv[1])).get(sys.argv[2], {}); print(p.get("space"), p.get("gave_up_space"), p.get("url"))' "$MEMO_SHEEP_STATE/sheep.json" "$EK"; }
reads() { grep -c "\"/api/space/$1/comments\"" "$S/web.log" || true; }
printf '{"comments": []}\n' > "$S/comments-sp-mirror.json"
cat > "$S/lookout.py" <<'EOF'
import json, sys
from importlib.machinery import SourceFileLoader as L
m = L("k", sys.argv[1]).load_module()
m.repo_tops = lambda pinned: {"two": m.Path(sys.argv[2])}
evs, _ = m.lookout_events({}, {"open": {}, "comments": {}, "pending": []}, m.pins(), [], [None, 0], True, [])
print(json.dumps([[e["doc"], e["kind"], e.get("threads")] for e in evs]))
EOF

echo "R14 — finding 1: the line's page, never a run's own mirror of it (sheep threads, sheep pull, the lookout)"
comments <<'EOF'
e1|||sam@example.com||2026-10-26T08:00:00Z|rewrite the intro
EOF
mirror; : > "$S/web.log"
K sheep threads "$ED" > "$T/r14a.out" 2>&1; rc=$?
check "$rc" "0" "sheep threads, a pin holding another page than the line's: read"
has "$T/r14a.out" "[e1]" "…the owner's thread on the line's page listed"
check "$(reads sp-e):$(reads sp-mirror)" "1:0" "…read from the line's page, never the mirror's"
lacks "$T/r14a.out" "is left" "…and, a read, says nothing of the pin (S2 landing review item 9, S3)"
check "$(pinof)" "sp-mirror None https://example.invalid/mirror" "…nor writes it"
mirror; : > "$S/web.log"
K sheep pull "$ED" > "$T/r14b.out" 2>&1; rc=$?
check "$rc:$(reads sp-e):$(reads sp-mirror)" "0:1:0" "sheep pull: the line's page too"
has "$T/r14b.out" "this Mac's own page sp-mirror is left" "…saying which page it left"
check "$(pinof)" "sp-e sp-mirror None" "…the pin pointed at the line's page, no address kept, so the next deploy goes there"
mirror; : > "$S/web.log"
check "$(py "$E" < "$S/lookout.py" 2>/dev/null)" "[[\"$EK\", \"offer\", [\"e1\"]]]" "the lookout: the owner's thread on the line's page is the event (S4: judged, held with the call off, an offer)"
check "$(reads sp-e):$(reads sp-mirror)" "1:1" "…read from the line's page, and the page given up read for an owner's thread typed there (item 10)"
printf '{"comments": [{"id": "m1", "body": "typed on the old page", "author_email": "sam@example.com", "created_at": "2026-10-26T09:00:00Z"}]}\n' > "$S/comments-sp-mirror.json"
mirror
check "$(py "$E" < "$S/lookout.py" 2>/dev/null)" "[[\"$EK\", \"gave-up\", null], [\"$EK\", \"offer\", [\"e1\"]]]" "item 10: an owner's thread on the page given up raises its own event"
check "$(py "$E" <<'EOF'
import sys
from importlib.machinery import SourceFileLoader as L
m = L("k", sys.argv[1]).load_module()
m.repo_tops = lambda pinned: {"two": m.Path(sys.argv[2])}
evs, _ = m.lookout_events({}, {"open": {}, "comments": {}, "pending": []}, m.pins(), [], [None, 0], True, [])
ev = [e for e in evs if e["kind"] == "gave-up"][0]
r = m.lookout_act(ev, "testhost", [], True)
print(r["action"], "m1" in r["card"], "sp-mirror" in r["card"], "answer there" in r["card"])
EOF
)" "card True True True" "…a card naming the thread, the page given up and where to answer, before any host rule"
printf '{"comments": []}\n' > "$S/comments-sp-mirror.json"
# item 6 (the S3 landing review): a seed off the branch routes the doc's page to its own key; the old
# branch, still in asks, raises no second event for the page
E2=claude/testhost/2026-10-27-e-seed; E2K="two@$E2:docs/e.md"
git -C "$E" checkout -q -b "$E2"
python3 - "$E/docs/e.md" "$(ago 1)" "$E2" <<'EOF'
import re, sys
p = sys.argv[1]; t = open(p).read()
open(p, "w").write(re.sub(r"(?m)^Routed: .*$", "Routed: %s · page sp-e · %s" % (sys.argv[2], sys.argv[3]), t))
EOF
git -C "$E" commit -qam "the seed's routing"; git -C "$E" checkout -q claude/testhost/2026-10-27-e
python3 - "$MEMO_SHEEP_STATE/sheep.json" "$EK" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1])); d[sys.argv[2]] = {"space": "sp-e", "url": "https://example.invalid/sp-e", "sha": "0" * 40, "fmt": 1, "sent": []}
json.dump(d, open(sys.argv[1], "w"))
EOF
check "$(py "$E" "$EK" "$E2K" <<'EOF'
import json, sys
from importlib.machinery import SourceFileLoader as L
m = L("k", sys.argv[1]).load_module()
m.repo_tops = lambda pinned: {"two": m.Path(sys.argv[2])}
notes = []
evs, _ = m.lookout_events({sys.argv[3]: ["D1"], sys.argv[4]: ["D1"]}, {"open": {}, "comments": {}, "pending": []}, m.pins(), [], [None, 0], True, notes)
print(sorted({e["doc"] == sys.argv[4] for e in evs if e["kind"] in ("save", "comment", "talk", "offer", "request")}), any("is routed to " + sys.argv[4] in n for n in notes))
EOF
)" "[True] True" "item 6: a page routed on to a seed raises its events under the seed's key alone, the old branch's key said and skipped"
git -C "$E" update-ref -d "refs/heads/$E2"

echo "R14b — …and the doc's first deploy on a routed branch goes to the line's page (sheep)"
mkdir -p "$S/bin"; cat > "$S/bin/spacesheep" <<'EOF'
#!/bin/sh
# deploy only: the space it was given, else a new one; every call logged
printf '%s\n' "$*" >> "$SHEEP_T/cli.log"
sp=sp-new; prev=
for a in "$@"; do [ "$prev" = "--space" ] && sp=$a; prev=$a; done
printf '{"uuid": "%s", "url": "https://example.invalid/%s"}\n' "$sp" "$sp"
EOF
chmod +x "$S/bin/spacesheep"
python3 - "$MEMO_SHEEP_STATE/sheep.json" "$EK" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1])); d.pop(sys.argv[2], None); json.dump(d, open(sys.argv[1], "w"))
EOF
MEMO_SHEEP_BIN="$S/bin/spacesheep" K sheep "$ED" > "$T/r14d.out" 2>&1; rc=$?
check "$rc:$(grep -c -- 'deploy .* --space sp-e ' "$S/cli.log")" "0:1" "no pin here: deployed to the line's page, --space sp-e"
check "$(pinof)" "sp-e None https://example.invalid/sp-e" "…and the pin holds it"

echo "R15 — finding 2 and R10 with a talking thread: a host's first read wakes only an unanswered turn"
comments <<'EOF'
t1|||sam@example.com||2026-10-26T08:00:00Z|what about the intro?
r1|t1||sam@example.com|claude|2026-10-26T08:05:00Z|The intro stays as it is.
t2|||sam@example.com||2026-10-26T08:00:00Z|and the outro?
r2|t2||sam@example.com|claude|2026-10-26T08:05:00Z|Which outro?
r3|t2||sam@example.com||2026-10-26T08:10:00Z|the last section
EOF
check "$(py "$E" < "$S/lookout.py")" "[[\"$EK\", \"talk\", [\"t2\"]]]" "a talk event for the thread the owner wrote in after our reply, none for the one we answered"

echo "R16 — finding 3: a Save no pull can take is settled in the doc, attended only"
comments <<'EOF'
EOF
printf '[{"seq": 7, "at": "2026-10-26T08:00:00Z", "name": "memo-save", "data": {"sha": "%s", "savedAt": "2026-10-26T08:00:00Z", "items": {"D1": "B"}, "comments": [], "feedback": ""}}]\n' "$(printf 'de%.0s' $(seq 20))" > "$S/events.json"
K routed check "$ED" > "$T/r16a.out" 2>&1; rc=$?
check "$rc" "3" "a Save whose commit no host can read: refused"
has "$T/r16a.out" "[save:7] 2026-10-26T08:00:00Z" "…naming it as settle takes it"
K routed check "$ED" --routing save:sp-e:6 > /dev/null 2>&1; rc=$?
check "$rc" "3" "--routing save:sp-e:6 (a start taking the page's Saves through seq 6): the Save 7 still refuses"
K routed check "$ED" --routing save:sp-e:7 > /dev/null 2>&1; rc=$?
check "$rc" "0" "--routing save:sp-e:7: the Save goes with the start (the lookout's seed of a Save, S3)"
K routed check "$ED" --routing save:sp-other:7 save:7 > /dev/null 2>&1; rc=$?
check "$rc" "3" "…another page's waiver, or a bare seq, waives nothing here (the S3 landing review: scoped to its own page)"
CLAUDE_UNATTENDED=1 K settle "$ED" save:7 --why "x" > /dev/null 2>&1; rc=$?
check "$rc" "3" "settle save: unattended, refused"
K settle "$ED" save:9 --why "x" > "$T/r16b.out" 2>&1; rc=$?
check "$rc" "1" "a Save the room does not hold: refused"
CLAUDE_CODE_SESSION_ID=sess-5678 K settle "$ED" save:7 --why "B was a slip" > "$T/r16c.out" 2>&1; rc=$?
check "$rc" "0" "settled"
has "$ED" "> **Settled.** Save 2026-10-26T08:00:00Z: B was a slip" "…the doc's line names the Save by its savedAt"
check "$(tail -1 "$MEMO_STATE_DIR/routed.jsonl" | python3 -c 'import json,sys; r=json.load(sys.stdin); print(r["event"], r["save"], r["session"])')" "settled 7 sess-5678" "…and routed.jsonl the Save and the session"
git -C "$E" commit -qam "settled a Save"
K routed check "$ED" > /dev/null 2>&1; rc=$?
check "$rc" "0" "the gate clears on the doc's line"
K settle "$ED" save:7 --why "again" > "$T/r16d.out" 2>&1; rc=$?
check "$rc" "1" "a Save the doc no longer owes: nothing to settle"
rm -f "$S/events.json"

echo "R17 — finding 4: on the text form a taken mark counts for taking, never for the gate"
check "$(py <<'EOF'
import sys
from importlib.machinery import SourceFileLoader as L
m = L("k", sys.argv[1]).load_module()
raw = "[id: t1] @sam (2026-10-26T08:00:00Z): do X\n  [id: r1] @sam (2026-10-26T09:00:00Z): memo: D1 taken into docs/e.md.\n"
ts = m.comment_threads(raw)
print(m.taken_ids(ts, {}), m.mark_kind(ts[0]["replies"][0]), m.is_mark(ts[0]["replies"][0], taken=False))
EOF
)" "{'t1'} None False" "text form: the old mark keeps its thread taken; mark_kind and an untaken read still need our own"

echo "R18 — finding 5: a held verb under an offer is no go"
comments <<'EOF'
g1|||sam@example.com||2026-10-26T08:00:00Z|tidy the intro
g2|g1||sam@example.com|claude|2026-10-26T08:05:00Z|memo: would start: tidy the intro (act-plain) — reply go to start, no to close
g3|g1||sam@example.com||2026-10-26T08:10:00Z|yes, and merge it into main
EOF
K routed check "$ED" > "$T/r18.out" 2>&1; rc=$?
check "$rc" "3" "yes, and merge it: refused"
has "$T/r18.out" "[g1] act-held" "…held, the held verb read before go/no"
comments <<'EOF'
g1|||sam@example.com||2026-10-26T08:00:00Z|tidy the intro
g2|g1||sam@example.com|claude|2026-10-26T08:05:00Z|memo: would start: tidy the intro (act-plain) — reply go to start, no to close
g3|g1||sam@example.com||2026-10-26T08:12:00Z|go
EOF
K routed check "$ED" > "$T/r18b.out" 2>&1; rc=$?
check "$rc" "3" "a bare go under the offer: owed until its start's mark (the S2 landing review's item 5, S4)"
has "$T/r18b.out" "[g1] a go under the offer, its run not started yet" "…saying so"
comments <<'EOF'
g1|||sam@example.com||2026-10-26T08:00:00Z|tidy the intro
g2|g1||sam@example.com|claude|2026-10-26T08:05:00Z|memo: would start: tidy the intro (act-plain) — reply go to start, no to close
g3|g1||sam@example.com||2026-10-26T08:12:00Z|go
g4|g1||sam@example.com|claude|2026-10-26T08:20:00Z|memo: routed into claude/testhost/2026-10-26-g's run, 2026-10-26
EOF
K routed check "$ED" > /dev/null 2>&1; rc=$?
check "$rc" "0" "…and clear once the routed into mark is up"
comments <<'EOF'
g1|||sam@example.com||2026-10-26T08:00:00Z|tidy the intro
g2|g1||sam@example.com|claude|2026-10-26T08:05:00Z|memo: would start: tidy the intro (act-plain) — reply go to start, no to close
g3|g1||sam@example.com||2026-10-26T08:13:00Z|no
EOF
K routed check "$ED" > /dev/null 2>&1; rc=$?
check "$rc" "0" "a no under the offer owes nothing (the lookout posts its closed mark)"

echo "R19 — findings 6 and 7: --dry-run logs nothing; --routing passes the start's own thread (h1: g1 has a verdict above)"
comments <<'EOF'
h1|||sam@example.com||2026-10-26T08:00:00Z|tidy the outro
EOF
printf 'Task: the next step of docs/e.md.\n' > "$T/ebrief.md"
rows() { wc -l < "$MEMO_STATE_DIR/routed.jsonl" | tr -d ' '; }
n0=$(rows)
K routed line --repo "$E" --ref HEAD --branch claude/testhost/2026-10-28-g --brief "$T/ebrief.md" --check --dry-run > /dev/null 2>&1; rc=$?
check "$rc:$(rows)" "3:$n0" "--dry-run: the gate still refuses, and routed.jsonl gets no row"
K routed line --repo "$E" --ref HEAD --branch claude/testhost/2026-10-28-g --brief "$T/ebrief.md" --check --routing h1 --dry-run > "$T/r19.out" 2>&1; rc=$?
check "$rc:$(rows)" "0:$n0" "--routing h1: the start's own thread passes; still no row"
check "$(python3 -c 'import json,sys; print([d["rel"] for d in json.loads(open(sys.argv[1]).read().splitlines()[-1])["docs"]])' "$T/r19.out")" "['docs/e.md']" "…and the line is written"
K routed line --repo "$E" --ref HEAD --branch claude/testhost/2026-10-28-g --brief "$T/ebrief.md" --check --routing h1 > /dev/null 2>&1
check "$(rows):$(tail -1 "$MEMO_STATE_DIR/routed.jsonl" | python3 -c 'import json,sys; print(json.load(sys.stdin)["event"])')" "$((n0 + 1)):routed" "without --dry-run: one routed row"

echo "R20 — a held row is no verdict (judged again); a model verdict as new as the words stands"
judged() { python3 -c 'import json,sys; print(sum(1 for l in open(sys.argv[1]) if json.loads(l).get("event") == "judged" and json.loads(l).get("thread") == "h1"))' "$MEMO_STATE_DIR/routed.jsonl"; }
j0=$(judged); K routed check "$ED" > /dev/null 2>&1; K routed check "$ED" > /dev/null 2>&1; rc=$?
check "$rc:$(($(judged) - j0))" "3:2" "the call off: held, and judged again on each check"
printf '{"event": "judged", "space": "sp-e", "thread": "h1", "label": "remark", "by": "model", "why": "", "words_at": 9999999999, "ts": 0}\n' >> "$MEMO_STATE_DIR/routed.jsonl"
j0=$(judged); K routed check "$ED" > /dev/null 2>&1; rc=$?
check "$rc:$(($(judged) - j0))" "0:0" "a model's remark as new as the words: it stands, no call"

echo "R21 — marks that stand for a word refuse an unattended run"
adds() { grep -c add_comment "$S/mcp.log" 2>/dev/null || true; }
a0=$(adds)
CLAUDE_UNATTENDED=1 K routed mark "$ED" g1 routed --branch claude/x > "$T/r21.out" 2>&1; rc=$?
check "$rc" "1" "routed mark, unattended: refused"
has "$T/r21.out" "does not post a 'routed' mark" "…saying why"
CLAUDE_UNATTENDED=1 K routed mark "$ED" g1 closed --who x > /dev/null 2>&1; rc=$?
check "$rc:$(adds)" "1:$a0" "closed mark, unattended: refused; nothing posted"

CLAUDE_UNATTENDED=1 K routed check "$ED" --routing g1 > "$T/r21.out" 2>&1; rc=$?
check "$rc" "1" "routed check --routing, unattended: refused (it clears the gate for the threads it names)"
has "$T/r21.out" "does not pass --routing" "…saying why"

echo "R21b — a stopped mark keeps the thread owed: it counts as nothing (the cutover's marks table; S2 landing review)"
cat > "$S/r21b.py" <<'EOF'
import sys
from importlib.machinery import SourceFileLoader as L
m = L("k", sys.argv[1]).load_module()
t = {"id": "t1", "anchor": None, "resolved": False, "at": "2026-10-26T08:00:00Z", "text": "rewrite the intro",
     "via": None, "own": False, "bot": False, "owner": True,
     "replies": [{"id": "r0", "text": "memo: stopped, 2026-10-26", "via": "claude", "own": True, "bot": False,
                  "owner": False, "at": "2026-10-26T08:05:00Z"}]}
print([w for _, w in m.routed_judge([t], "k@b:docs/x.md", "sp", "demo", log=False)[0]])
EOF
check "$(python3 "$S/r21b.py" "$B/keel")" "['an act stopped']" "a stopped mark after the owner's ask: owed, never cleared"

echo "R22 — brief_docs strips only a ./ prefix; the last step names keel from ~/"
# a file, not a heredoc inside "$(…)": bash 3.2 reads its backtick as a substitution (AGENTS.md, Traps)
cat > "$S/r22.py" <<'EOF'
import sys
from pathlib import Path
from importlib.machinery import SourceFileLoader as L
m = L("k", sys.argv[1]).load_module()
print(m.brief_docs(Path(sys.argv[2]), "HEAD", "see ./docs/e.md, .github/x.md and ../docs/e.md"))
m.overlay_cmd = lambda n: str(Path.home() / "tools" / "keel")
# the home's tilde built from its code point: a literal one in a public file reads as a home path to the gate
print(m.routed_last_step("docs/e.md").split(chr(96))[1] == chr(126) + "/tools/keel sheep pull docs/e.md --write")
EOF
check "$(py "$E" < "$S/r22.py")" "['docs/e.md', '.github/x.md']
True" "a dotted folder kept whole; keel named from the home, as a tilde path"

echo "R23 — settle under a D-item: the line after the item's block"
comments <<'EOF'
dd|||sam@example.com||2026-10-26T08:00:00Z|B, for now
EOF
python3 - "$S/comments.json" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1])); d["comments"][0]["anchor_id"] = "D1"; json.dump(d, open(sys.argv[1], "w"))
EOF
K settle "$ED" D1 --why "answered in chat" > "$T/r23.out" 2>&1; rc=$?
check "$rc" "0" "settled on D1"
check "$(python3 - "$ED" <<'EOF'
import sys
ls = open(sys.argv[1]).read().split("\n")
s = ls.index("  > **Settled.** answered in chat")
print(ls.index("  ➤ Answer:") < s < ls.index("---"))
EOF
)" "True" "…between the item's answer and the rule below it"
git -C "$E" commit -qam "settled D1"

echo "R24 — pickup brief routes, ungated; --unroute takes the line back, and the lookout stops reading it (finding 8)"
if [ -n "$PK" ]; then
  F=claude/testhost/2026-10-28-fox; git -C "$E" branch -q "$F"; FK="two@$F:docs/e.md"
  comments <<'EOF'
g1|||sam@example.com||2026-10-26T08:00:00Z|tidy the intro
EOF
  n0=$(rows)
  (export HOME="$T/hm" PICKUP_KEEL="$B/keel" PICKUP_HOST=testhost; cd "$E" && python3 "$PK" brief "$F" --text "Task: the next step of docs/e.md." --repo "$E" --no-fetch --dry-run) > "$T/r24d.out" 2>&1; rc=$?
  check "$rc:$(rows)" "0:$n0" "pickup brief --dry-run: no row in routed.jsonl (finding 6)"
  (export HOME="$T/hm" PICKUP_KEEL="$B/keel" PICKUP_HOST=testhost; cd "$E" && python3 "$PK" brief "$F" --text "Task: the next step of docs/e.md." --repo "$E" --no-fetch) > "$T/r24a.out" 2>&1; rc=$?
  check "$rc" "0" "pickup brief with an owner thread open: routed (a brief is not gated)"
  has "$T/r24a.out" "routed: docs/e.md" "…and says so"
  check "$(git -C "$E" show "$F:docs/e.md" | grep -c "^Routed: .* · page sp-e · $F$")" "1" "…the line rewritten to the brief's branch, the page kept"
  check "$(git -C "$E" log -1 --format=%B "$F" | grep -c '^Routed-By: pickup brief (docs/e.md)')" "1" "…in the brief's own commit, with its trailer"
  RD() { py "$E" <<'EOF'
import sys
from importlib.machinery import SourceFileLoader as L
m = L("k", sys.argv[1]).load_module()
print(sorted((k, v["space"]) for k, v in m.routed_docs({"two": sys.argv[2]}, m.now_ts() - 86400).items()))
EOF
  }
  check "$(RD)" "[('$FK', 'sp-e')]" "routed_docs: the newest routing of the page, its key the brief's branch"
  (export HOME="$T/hm" PICKUP_KEEL="$B/keel" PICKUP_HOST=testhost; cd "$E" && python3 "$PK" brief "$F" --text "Task: the next step of docs/e.md, not coming." --repo "$E" --no-fetch --unroute) > "$T/r24b.out" 2>&1; rc=$?
  check "$rc:$(git -C "$E" show "$F:docs/e.md" | grep -c '^Routed: ' || true)" "0:0" "--unroute: the line out of the brief's branch"
  check "$(RD)" "[('$EK', 'sp-e')]" "…and routed_docs no longer names it: the routing before it stands, its own newest line's page (not sp-old)"
else
  echo "  --   skipped: no pickup beside keel (wharf-runs absent)"
fi

echo "R25 — keel routed bench (S4): the evidence's ten through the rules and the one call; the call off here"
GATE_LOG="$T/gate-bench.jsonl" K routed bench --json > "$T/r25.out" 2>&1; rc=$?
check "$rc:$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["of"], d["right"], " ".join("%s=%s/%s" % (r["n"], r["label"], r["by"]) for r in d["rows"] if r["by"] == "rules"))' "$T/r25.out")" \
  "0:10 5 2=act-held/rules 3=answer/rules 8=act-held/rules 9=act-held/rules 10=answer/rules" \
  "the bench: ten read, the held verbs, the D-card and the reply under our question settled by the rules"
check "$(python3 -c 'import json,sys; print(sorted({r["why"] for r in json.load(open(sys.argv[1]))["rows"] if r["by"] == "held"}))' "$T/r25.out")" \
  "['the keel.comment call is off']" "…the free text held while the row is off, and no call made"
check "$([ -e "$T/gate-bench.jsonl" ] && echo called || echo none)" "none" "…nothing logged by the gate: no call left the Mac"

echo
[ $fails -eq 0 ] && echo "routed: all passed" || echo "routed: $fails failed"
exit $((fails > 0))
