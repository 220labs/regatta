#!/usr/bin/env bash
# Tests for wharf's bin/ci-circleci — a scratch repo and a local stand-in of CircleCI's API (v2 and
# v1.1, a step-output host, an artifact host that redirects); no network, no real token.
#   bash modules/wharf/tests/test_ci_circleci.sh
set -u
M="$(cd "$(dirname "$0")/.." && pwd)"
CC="$M/bin/ci-circleci"
T=$(mktemp -d); T=$(cd "$T" && pwd -P)
fails=0
check() { if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3: expected [$2] got [$1]"; fails=$((fails+1)); fi; }
has() { case "$1" in *"$2"*) echo "  ok   $3";; *) echo "  FAIL $3: [$2] not in [${1:0:400}]"; fails=$((fails+1));; esac; }
hasnt() { case "$1" in *"$2"*) echo "  FAIL $3: [$2] found"; fails=$((fails+1));; *) echo "  ok   $3";; esac; }
export GIT_CONFIG_GLOBAL="$T/gitconfig" GIT_CONFIG_NOSYSTEM=1
printf '[user]\n\tname = t\n\temail = t@t\n[init]\n\tdefaultBranch = main\n' > "$GIT_CONFIG_GLOBAL"
unset CIRCLECI_TOKEN CIRCLECI_PROJECT_SLUG
TOK=tok-SECRET-123

# The stand-in: answers from $T/api/state.json (the workflow and job statuses, rewritten by the
# cases), logs every request as `METHOD path token=<yes|no> body` to $T/api/log
mkdir -p "$T/api"
cat > "$T/api/fake.py" <<'EOF'
import gzip, http.server, json, os, sys
D = sys.argv[1]
PID = "11111111-2222-3333-4444-555555555555"
def state():
    return json.load(open(os.path.join(D, "state.json")))
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass
    def reply(self, code, obj=None, raw=None, headers=()):
        body = raw if raw is not None else json.dumps(obj).encode()
        self.send_response(code)
        for k, v in headers:
            self.send_header(k, v)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def note(self, body=b""):
        with open(os.path.join(D, "log"), "a") as f:
            f.write("%s %s token=%s %s\n" % (self.command, self.path,
                    "yes" if self.headers.get("Circle-Token") == "tok-SECRET-123" else
                    ("other" if self.headers.get("Circle-Token") else "no"), body.decode()))
    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length") or 0))
        self.note(body)
        if self.path.endswith("/pipeline/run"):
            return self.reply(201, {"id": PID, "number": 42, "state": "created"})
        if self.path == "/api/v2/workflow/wf-1/rerun":
            post = state().get("post")
            if post == "no-id":
                return self.reply(202, {"message": "Accepted."})
            if post and post != "unlisted":
                return self.reply(post, {"message": "Busy"})
            if not post:
                # listed at once here; "unlisted" keeps it off the list, as the 202 may come before it is
                st = state(); st["rerun"] = "running"
                json.dump(st, open(os.path.join(D, "state.json"), "w"))
            return self.reply(202, {"workflow_id": "wf-2"})
        self.reply(404, {"message": "Not found"})
    def do_GET(self):
        self.note()
        p, s, port = self.path.split("?")[0], state(), self.server.server_address[1]
        if self.headers.get("Circle-Token") is None and p.startswith(("/api/", "/art/", "/raw/")):
            return self.reply(401, {"message": "You must log in first."})
        if p == "/api/v2/pipeline/%s" % PID:
            return self.reply(200, {"id": PID, "number": 42, "vcs": {"branch": s.get("branch", "claude/x/2026-10-26-t")}})
        if p.endswith("/pipeline/%s/workflow" % PID) and s.get("listfail") and s.get("rerun"):
            return self.reply(404, {"message": "Not found"})
        if p.endswith("/pipeline/42"):
            return self.reply(200, {"id": PID, "number": 42})
        if p.endswith("/pipeline/%s/workflow" % PID):
            if s.get("page2") and "page-token" not in self.path:
                return self.reply(200, {"items": [], "next_page_token": "p2"})
            one = {"id": "wf-1", "name": "linux", "status": s["wf"], "created_at": "2026-10-31T10:00:00Z"}
            two = {"id": "wf-2", "name": "linux", "status": s.get("rerun"),
                   "created_at": s.get("rerun_at", "2026-10-31T11:00:00Z")}
            # newest first, as the live list held a rerun beside its original (2026-10-31)
            return self.reply(200, {"items": ([two] if s.get("rerun") else []) + ([one] if s["wf"] else []),
                                    "next_page_token": None})
        if p.startswith("/api/v2/project/") and p.endswith("/job/7"):
            return self.reply(200, {"number": 7, "name": "linux", "status": s["job"],
                                    "latest_workflow": {"id": "wf-1", "name": "linux"}})
        if p.startswith("/api/v2/project/") and p.endswith("/job/9"):
            return self.reply(200, {"number": 9, "name": "linux", "status": s["rerun"],
                                    "latest_workflow": {"id": "wf-2", "name": "linux"}})
        if p == "/api/v2/workflow/wf-2":
            return self.reply(200, {"id": "wf-2", "name": "linux", "status": s["rerun"], "pipeline_id": PID,
                                    "pipeline_number": 42, "created_at": s.get("rerun_at", "2026-10-31T11:00:00Z")})
        if p.startswith("/api/v2/project/") and p.endswith("/job/8"):
            return self.reply(200, {"number": 8, "name": "orphan", "status": "failed"})
        if p == "/api/v2/workflow/wf-1":
            return self.reply(200, {"id": "wf-1", "name": "linux", "status": s["wf"], "pipeline_id": PID,
                                    "pipeline_number": 42, "created_at": "2026-10-31T10:00:00Z"})
        if p.endswith("/workflow/wf-2/job"):
            return self.reply(200, {"items": [{"job_number": 9, "name": "linux", "status": s["rerun"]}], "next_page_token": None})
        if p.endswith("/workflow/wf-1/job"):
            return self.reply(200, {"items": [{"job_number": 7, "name": "linux", "status": s["job"]}], "next_page_token": None})
        if p.startswith("/api/v1.1/project/") and p.endswith("/7"):
            out = "http://localhost:%d/out/" % port
            return self.reply(200, {"steps": [
                {"name": "Checkout code", "actions": [{"name": "Checkout code", "status": "success", "index": 0, "step": 101, "output_url": out + "1"}]},
                {"name": "the suites", "actions": [{"name": "the twin's line, every suite", "status": "success", "exit_code": 0, "index": 0, "step": 102, "output_url": out + "2"}]},
                {"name": "the verdict", "actions": [{"name": "the verdict", "status": "failed", "exit_code": 1}]}]})
        if p.endswith("/7/artifacts"):
            base = "http://127.0.0.1:%d/art/" % port
            items = [{"path": "twin-logs/1-keel-check.log", "url": base + "keel"},
                     {"path": "twin-logs/logs.tar.gz", "url": base + "gz"},
                     {"path": "twin-logs/summary.txt", "url": base + "moved"}]
            if s.get("evil"):
                items.append({"path": "../../escape", "url": base + "keel"})
            return self.reply(200, {"items": items, "next_page_token": None})
        if p == "/raw/circleci/ORG/PROJ/7/output/0/102":
            return self.reply(200, raw=b"the whole\na\nb\nc\n")
        if p == "/out/1":
            return self.reply(200, raw=gzip.compress(json.dumps([{"message": "clo", "type": "out"}, {"message": "ned\n"}]).encode()),
                              headers=[("Content-Encoding", "gzip")])
        if p == "/out/2":
            return self.reply(200, raw=json.dumps([{"message": "c\n"}]).encode())
        if p == "/art/keel":
            return self.reply(200, raw=b"keel log\n")
        if p == "/art/gz":
            return self.reply(200, raw=gzip.compress(b"tarball"))
        if p == "/art/moved":
            # the artifact host's redirect to storage: the token must not follow it
            self.send_response(302)
            self.send_header("Location", "http://localhost:%d/storage/summary" % port)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        if p == "/storage/summary":
            return self.reply(200, raw=b"=== 13 of 13\n")
        self.reply(404, {"message": "Not found"})
s = http.server.ThreadingHTTPServer(("127.0.0.1", 0), H)
open(os.path.join(D, "port"), "w").write(str(s.server_address[1]))
s.serve_forever()
EOF
echo '{"wf": "success", "job": "success"}' > "$T/api/state.json"
python3 "$T/api/fake.py" "$T/api" & FAKE=$!
trap 'kill $FAKE 2>/dev/null; wait $FAKE 2>/dev/null; rm -rf "$T"' EXIT
for i in $(seq 1 50); do [ -s "$T/api/port" ] && break; sleep 0.1; done
PORT=$(cat "$T/api/port")
export CIRCLECI_API="http://127.0.0.1:$PORT/api/v2" CIRCLECI_API_V1="http://127.0.0.1:$PORT/api/v1.1" \
       CIRCLECI_API_RAW="http://127.0.0.1:$PORT/raw"
state() { echo "$1" > "$T/api/state.json"; }
log() { cat "$T/api/log" 2>/dev/null; }

# The repo: a main checkout with the token in its .env, and a worktree with none of its own
R="$T/repo"
git init -q "$R" && git -C "$R" commit -q --allow-empty -m init
mkdir -p "$R/.circleci"
printf '# a comment first\n\ncircleci/ORG/PROJ\n' > "$R/.circleci/project-slug"
git -C "$R" add .circleci && git -C "$R" commit -q -m slug
printf 'OTHER=1\nexport CIRCLECI_TOKEN="%s"\n' "$TOK" > "$R/.env"
git -C "$R" worktree add -q -b claude/x/2026-10-26-t "$T/wt" main

echo "== trigger"
out=$("$CC" "$T/wt" trigger --param linux=true --param n=3 --param suites="keel wharf" 2>&1); rc=$?
check "$rc" "0" "trigger: exit 0"
has "$out" "pipeline 42 11111111-2222-3333-4444-555555555555 (branch claude/x/2026-10-26-t; linux=True, n=3, suites=keel wharf)" "  names the pipeline, the branch (the worktree's) and the parameters"
L=$(log)
has "$L" "POST /api/v2/project/circleci/ORG/PROJ/pipeline/run token=yes" "  POSTs to the slug from .circleci/project-slug (past its comment), with the main checkout's token"
has "$L" '"config": {"branch": "claude/x/2026-10-26-t"}, "checkout": {"branch": "claude/x/2026-10-26-t"}' "  the branch in the body, for the config and the checkout (the Trigger Pipeline API)"
hasnt "$L" 'definition_id' "  no definition_id unless \$CIRCLECI_DEFINITION_ID names one"
has "$L" '"parameters": {"linux": true, "n": 3, "suites": "keel wharf"}' "  typed parameters: a boolean, an integer, a string"
hasnt "$out" "$TOK" "  the token is never printed"
has "$out" "warning: no origin/claude/x/2026-10-26-t here: push the branch first" "  a branch not on origin: warned, still triggered"
git -C "$R" update-ref refs/remotes/origin/claude/x/2026-10-26-t "$(git -C "$R" rev-parse main~1)"
out=$("$CC" "$T/wt" trigger 2>&1)
has "$out" "is not origin/claude/x/2026-10-26-t" "  a tip origin does not hold: warned that CircleCI runs origin's"
git -C "$R" update-ref refs/remotes/origin/claude/x/2026-10-26-t "$(git -C "$T/wt" rev-parse HEAD)"
out=$("$CC" "$T/wt" trigger 2>&1)
hasnt "$out" "warning" "  the tip origin holds: no warning"
out=$("$CC" "$T/wt" trigger --branch other --slug gh/o/r 2>&1)
has "$(log)" "POST /api/v2/project/gh/o/r/pipeline/run token=yes" "--slug wins over the file"
has "$(log | tail -1)" '{"config": {"branch": "other"}, "checkout": {"branch": "other"}}' "  --branch, and no parameters key without --param"
: > "$T/api/log"
out=$(CIRCLECI_DEFINITION_ID=def-1 "$CC" "$T/wt" trigger 2>&1)
has "$(log)" '"definition_id": "def-1"' "\$CIRCLECI_DEFINITION_ID picks the pipeline definition"
: > "$T/api/log"
out=$(CIRCLECI_TOKEN=env-tok "$CC" "$T/wt" trigger 2>&1)
has "$(log)" "token=other" "\$CIRCLECI_TOKEN wins over the .env"

echo "== jobs and wait"
: > "$T/api/log"
out=$("$CC" "$T/wt" jobs 42 2>&1); rc=$?
check "$rc" "0" "jobs by number: exit 0"
has "$out" "workflow linux: success" "  the workflow"
has "$out" "job 7 linux: success" "  and its job, by number"
has "$(log)" "GET /api/v2/project/circleci/ORG/PROJ/pipeline/42" "  the number read as the pipeline's id"
out=$("$CC" "$T/wt" jobs 11111111-2222-3333-4444-555555555555 2>&1)
has "$out" "job 7 linux: success" "jobs by id"
out=$("$CC" "$T/wt" wait 42 --every 0 2>&1); rc=$?
check "$rc" "0" "wait on a pipeline that succeeded: exit 0"
state '{"wf": "failed", "job": "failed"}'
out=$("$CC" "$T/wt" wait 42 --every 0 2>&1); rc=$?
check "$rc" "1" "wait on a failed one: exit 1"
has "$out" "job 7 linux: failed" "  saying which job"
state '{"wf": "running", "job": "running"}'
out=$("$CC" "$T/wt" wait 42 --every 1 --timeout 1 2>&1); rc=$?
check "$rc" "3" "wait past its timeout: exit 3"
has "$out" "still running after 1 s" "  said"
state '{"wf": "", "job": "", "page2": true}'
out=$("$CC" "$T/wt" wait 42 --every 0 2>&1); rc=$?
check "$rc" "1" "a pipeline that ran no workflow: exit 1, never a wait forever"
has "$out" "the config's \`when\` ran none" "  said"
has "$(log)" "workflow?page-token=p2" "  a paged list read to its last page"

echo "== steps and artifacts"
state '{"wf": "success", "job": "success"}'
: > "$T/api/log"
out=$("$CC" "$T/wt" steps 7 --out "$T/s" 2>&1); rc=$?
check "$rc" "0" "steps: exit 0"
check "$(cat "$T/s/02-the-twin-s-line-every-suite.log")" "the whole
a
b
c" "  a step's whole output from the raw endpoint, one file per step"
has "$out" "4 lines whole  the twin's line" "  said whole"
has "$(log)" "GET /raw/circleci/ORG/PROJ/7/output/0/102 token=yes" "  asked with the token, by the action's index and step"
check "$(cat "$T/s/01-Checkout-code.log")" "cloned" "  no raw output: output_url's, gunzipped, its messages joined"
has "$out" "1 lines tail   Checkout code" "  said tail"
has "$out" "failed    exit 1          0 lines        the verdict" "  a step with no output still listed, with its exit"
check "$(ls "$T/s" | wc -l | tr -d ' ')" "2" "  a file only where there was output"
has "$(log)" "GET /out/1 token=no" "  a host not CircleCI's gets no token"
out=$("$CC" "$T/wt" artifacts 7 --out "$T/a" 2>&1); rc=$?
check "$rc" "0" "artifacts: exit 0"
check "$(cat "$T/a/twin-logs/1-keel-check.log")" "keel log" "  saved at its path"
check "$(cat "$T/a/twin-logs/summary.txt")" "=== 13 of 13" "  through the artifact host's redirect"
check "$(python3 -c 'import sys,gzip; print(gzip.decompress(open(sys.argv[1],"rb").read()).decode())' "$T/a/twin-logs/logs.tar.gz" 2>&1)" "tarball" "  a gzip artifact keeps its own bytes (no sniffing without Content-Encoding)"
has "$(log)" "GET /art/moved token=yes" "  the artifact host gets the token"
has "$(log)" "GET /storage/summary token=no" "  and the redirect's target does not"
state '{"wf": "success", "job": "success", "evil": true}'
out=$("$CC" "$T/wt" artifacts 7 --out "$T/e" 2>&1); rc=$?
check "$rc" "2" "an artifact path that leaves the folder: refused"
check "$([ -e "$T/escape" ] && echo written || echo none)" "none" "  nothing written outside"

echo "== run"
state '{"wf": "success", "job": "success"}'
out=$("$CC" "$T/wt" run --param linux=true --out "$T/r" --every 0 2>&1); rc=$?
check "$rc" "0" "run: exit 0 on success"
check "$(ls "$T/r/7")" "artifacts
steps" "  each job's steps and artifacts under its number"

echo "== rerun"
state '{"wf": "failed", "job": "failed"}'
: > "$T/api/log"
out=$("$CC" "$T/wt" rerun 7 2>&1); rc=$?
check "$rc" "0" "rerun a failed job's workflow: exit 0"
has "$out" "workflow linux wf-1 rerun from failed: wf-2 (pipeline 42)" "  names the workflow, the new one and the pipeline wait takes"
has "$(log)" "GET /api/v2/project/circleci/ORG/PROJ/job/7 token=yes" "  the job read by number, under the slug"
has "$(log)" 'POST /api/v2/workflow/wf-1/rerun token=yes {"from_failed": true}' "  the workflow rerun from failed, with the token"
check "$(log | grep -c 'POST /api/v2/workflow/wf-1/rerun')" "1" "  POSTed once"
hasnt "$out" "not listed" "  and read the rerun back on the pipeline's list"
state '{"wf": "failed", "job": "failed", "post": "unlisted"}'
: > "$T/api/log"
out=$(CIRCLECI_LISTED_WAIT=1 "$CC" "$T/wt" rerun 7 2>&1); rc=$?
check "$rc" "0" "a rerun the list does not show yet: still exit 0, it started"
has "$out" "wf-2 is not listed in its pipeline yet" "  saying a wait before it is reads the original"
check "$(log | grep -c 'POST /api/v2/workflow/wf-1/rerun')" "1" "  POSTed once, polled the list only"
state '{"wf": "failed", "job": "failed", "listfail": true}'
: > "$T/api/log"
out=$("$CC" "$T/wt" rerun 7 2>&1); rc=$?
check "$rc" "0" "a rerun whose read-back fails: still exit 0, it started"
has "$out" "could not read the pipeline's list back" "  saying a wait may read the original"
state '{"wf": "failed", "job": "failed", "branch": "main"}'
: > "$T/api/log"
out=$("$CC" "$T/wt" rerun 7 2>&1); rc=$?
check "$rc" "2" "a job whose pipeline ran on another branch: refused (job numbers are per project)"
has "$out" "job 7 in circleci/ORG/PROJ ran on main, not claude/x/2026-10-26-t: pass --branch main" "  naming both and the way through"
hasnt "$(log)" "POST" "  nothing POSTed"
out=$("$CC" "$T/wt" rerun 7 --branch main 2>&1); rc=$?
check "$rc" "0" "  --branch main: rerun"
for v in nan 30s -1; do
  : > "$T/api/log"
  out=$(CIRCLECI_LISTED_WAIT=$v "$CC" "$T/wt" rerun 7 2>&1); rc=$?
  check "$rc" "2" "CIRCLECI_LISTED_WAIT=$v: refused before any request"
  check "$(cat "$T/api/log")" "" "  nothing asked of the API"
done
state '{"wf": "failed", "job": "failed", "rerun": "failed"}'
: > "$T/api/log"
out=$("$CC" "$T/wt" rerun 9 2>&1); rc=$?
check "$rc" "2" "the rerun's own job: refused, one rerun per pipeline's workflow"
has "$out" "workflow linux wf-2 is a rerun of wf-1 already" "  saying so"
hasnt "$(log)" "POST" "  nothing POSTed"
state '{"wf": "failed", "job": "failed", "rerun": "success", "rerun_at": "2026-10-31T10:00:00.500Z"}'
"$CC" "$T/wt" wait 42 --every 1 >/dev/null 2>&1; rc=$?
check "$rc" "0" "wait: a rerun half a second after its original is newer (times parsed, not compared as text)"
state '{"wf": "failed", "job": "failed", "rerun": "running"}'
"$CC" "$T/wt" wait 42 --every 1 --timeout 1 >/dev/null 2>&1; rc=$?
check "$rc" "3" "wait: a failed original beside a running rerun keeps waiting"
state '{"wf": "failed", "job": "failed", "post": 503}'
: > "$T/api/log"
out=$("$CC" "$T/wt" rerun 7 2>&1); rc=$?
check "$rc" "2" "a rerun POST answered 503: refused"
has "$out" "503" "  saying so"
has "$out" "it may have started: read \`jobs 42\` before any retry" "  and that it may have started"
check "$(log | grep -c 'POST /api/v2/workflow/wf-1/rerun')" "1" "  and not retried: a transient failure may have started it"
state '{"wf": "failed", "job": "failed", "post": "no-id"}'
: > "$T/api/log"
out=$("$CC" "$T/wt" rerun 7 2>&1); rc=$?
check "$rc" "2" "a rerun answered without a workflow id: refused"
has "$out" "the rerun answered without a workflow id" "  saying so"
for st in running success; do
  state "{\"wf\": \"failed\", \"job\": \"failed\", \"rerun\": \"$st\"}"
  : > "$T/api/log"
  out=$("$CC" "$T/wt" rerun 7 2>&1); rc=$?
  check "$rc" "2" "a rerun already there, $st: refused"
  has "$out" "workflow linux wf-1 was rerun already: wf-2 is $st" "  naming it"
  hasnt "$(log)" "POST" "  nothing POSTed"
done
for st in canceled not_run unauthorized; do
  state "{\"wf\": \"$st\", \"job\": \"failed\"}"
  : > "$T/api/log"
  out=$("$CC" "$T/wt" rerun 7 2>&1); rc=$?
  check "$rc" "2" "a workflow that ended $st: refused"
  has "$out" "workflow linux is $st: nothing failed to rerun" "  saying so"
  hasnt "$(log)" "POST" "  nothing POSTed"
done
state '{"wf": "error", "job": "failed"}'
out=$("$CC" "$T/wt" rerun 7 2>&1); rc=$?
check "$rc" "0" "a workflow that ended in error: rerun"
state '{"wf": "failed", "job": "failed", "rerun": "success"}'
out=$("$CC" "$T/wt" wait 42 --every 1 2>&1); rc=$?
check "$rc" "0" "wait: a failed original beside its green rerun exits 0"
has "$out" "workflow linux: failed (replaced by its rerun)" "  the original marked as replaced"
has "$out" "workflow linux: success
" "  the rerun not"
state '{"wf": "failed", "job": "failed", "rerun": "failed"}'
"$CC" "$T/wt" wait 42 --every 1 >/dev/null 2>&1; rc=$?
check "$rc" "1" "wait: a rerun that failed too exits 1"
state '{"wf": "running", "job": "failed"}'
: > "$T/api/log"
out=$("$CC" "$T/wt" rerun 7 2>&1); rc=$?
check "$rc" "2" "a workflow still running: refused"
has "$out" "workflow linux is running: a rerun waits until it ends" "  saying so"
hasnt "$(log)" "POST" "  nothing POSTed"
state '{"wf": "success", "job": "success"}'
out=$("$CC" "$T/wt" rerun 7 2>&1); rc=$?
check "$rc" "2" "a workflow that succeeded: refused, nothing failed to rerun"
out=$("$CC" "$T/wt" rerun 8 2>&1); rc=$?
check "$rc" "2" "a job with no workflow in the answer: refused"
has "$out" "job 8: CircleCI's answer names no workflow" "  saying so"
out=$("$CC" "$T/wt" rerun 2>&1); rc=$?
check "$rc" "2" "rerun without a job: exit 2"
out=$("$CC" "$T/wt" rerun latest 2>&1); rc=$?
check "$rc" "2" "rerun of a job that is no number: exit 2"
hasnt "$(log)" "POST" "  and none of the refusals POSTed"

echo "== refusals"
out=$("$CC" "$T/wt" steps 7 2>&1); rc=$?
check "$rc" "2" "steps without --out: exit 2"
out=$("$CC" "$T/wt" wait 2>&1); rc=$?
check "$rc" "2" "wait without a pipeline: exit 2"
out=$("$CC" "$T/wt" jobs latest 2>&1); rc=$?
check "$rc" "2" "a pipeline that is neither a number nor an id: exit 2"
mv "$R/.env" "$R/env.aside"
out=$("$CC" "$T/wt" jobs 42 2>&1); rc=$?
check "$rc" "2" "no token anywhere: exit 2"
has "$out" "no CIRCLECI_TOKEN" "  saying so"
printf 'CIRCLECI_TOKEN=%s  # a note\n' "$TOK" > "$R/.env"
: > "$T/api/log"
out=$("$CC" "$T/wt" jobs 42 2>&1)
has "$(log)" "token=yes" "a trailing comment after the token is dropped, as the shell drops it"
printf 'CIRCLECI_TOKEN=\n' > "$R/.env"
out=$("$CC" "$T/wt" jobs 42 2>&1)
has "$out" "is empty" "an empty key: refused, never sent"
mv "$R/env.aside" "$R/.env"
rm "$T/wt/.circleci/project-slug"
out=$("$CC" "$T/wt" jobs 42 2>&1); rc=$?
check "$rc" "2" "no slug: exit 2"
has "$out" "no project slug" "  saying where to write it"
out=$(CIRCLECI_PROJECT_SLUG=circleci/ORG/PROJ "$CC" "$T/wt" jobs 42 2>&1)
has "$out" "job 7 linux" "\$CIRCLECI_PROJECT_SLUG serves for the file"
out=$(CIRCLECI_PROJECT_SLUG=circleci/ORG/PROJ "$CC" "$T/wt" jobs 99 2>&1); rc=$?
check "$rc" "2" "an API 404: exit 2"
has "$out" "HTTP 404: Not found" "  the status and CircleCI's message"
hasnt "$out" "$TOK" "  the token in no error"

echo
[ "$fails" -eq 0 ] && echo "test_ci_circleci: all passed" || echo "test_ci_circleci: $fails FAILED"
[ "$fails" -eq 0 ]
