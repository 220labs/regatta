#!/usr/bin/env bash
# Tests for wharf's bin/ci-provider — scratch git repos and a fake `gh` on PATH; no network, no GitHub.
#   bash modules/wharf/tests/test_ci_provider.sh
set -u
M="$(cd "$(dirname "$0")/.." && pwd)"
B="$M/bin"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
TPL="$M/templates/code"
fails=0
check() { if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3: expected [$2] got [$1]"; fails=$((fails+1)); fi; }
CP="$B/ci-provider"
# The caller's config dir, before the suite pins its own: only the word-list case reads it, through
# helloworld's lookup (empty or unset: helloworld's default)
CALLER_CONFIG="${REGATTA_CONFIG:-}"
# git reads a global config of the suite's own, and no system one: the caller's ~/.gitconfig (a
# hook path, an init template, a default branch) never reaches a scratch repo (review 2026-10-21, 15)
export GIT_CONFIG_GLOBAL="$T/gitconfig" GIT_CONFIG_NOSYSTEM=1
# the fake gh logs a token call by GH_TOKEN, and ci-provider reads WHARF_READ_TOKEN: neither from the caller
unset GH_TOKEN GITHUB_TOKEN WHARF_READ_TOKEN
: > "$GIT_CONFIG_GLOBAL"
# A scratch config dir of its own, whatever the caller's REGATTA_CONFIG: every key a case reads is
# pinned here, so the suite passes the same on a Mac whose login names real hosts and on a runner
# with none (wharf-runs' suites passed on one Mac only for reading its real config, 2026-10-20).
export REGATTA_CONFIG="$T/config"
mkdir -p "$REGATTA_CONFIG/wharf"
# the runner Mac's keys, synthetic: the ssh alias, its labels (the first of its own names the
# runner), its user; a case that wants one absent moves it aside and back
printf 'laptop-ci\n' > "$REGATTA_CONFIG/wharf/ci-runner-ssh"
printf 'self-hosted\nmacOS\nlaptop\n' > "$REGATTA_CONFIG/wharf/ci-runner-labels"
printf 'ci\n' > "$REGATTA_CONFIG/wharf/ci-runner-user"

# A fake gh: required checks in $T/gh/rsc.json, commit statuses in $T/gh/status.json; a PATCH
# body is kept in $T/gh/patch.json and becomes the new required checks. Every call is logged in
# $T/gh/calls; the repo's privacy is $T/gh/private (`fail`: unreadable), whether it runs fork PRs'
# workflows $T/gh/forkpr (true, false or `fail`; false by default), its collaborators
# $T/gh/collabs.json, its runners $T/gh/runners.json ($T/gh/runners.fail: unread), its queued check
# runs $T/gh/queued.json, and both runner tokens are $TOKEN. Its
# repository variables are $T/gh/vars/<NAME>.json: a POST or PATCH body becomes one, a GET of
# none is GitHub's 404; with $T/gh/vars/fail a GET fails with no output at all (gh's own failure), with
# $T/gh/vars/<NAME>.unread a GET of that one does, and with $T/gh/vars/<NAME>.refuse GitHub refuses its write.
mkdir -p "$T/bin" "$T/gh"
cat > "$T/bin/gh" <<'EOF'
#!/usr/bin/env bash
D="$FAKE_GH"
args="$*"
echo "$args" >> "$D/calls"
[ -n "${GH_TOKEN:-}" ] && echo "$args" >> "$D/tokcalls"
[ -n "${WHARF_READ_TOKEN:-}" ] && echo "$args" >> "$D/leak"
case "$args" in
  *"/actions/runners/registration-token --jq .token"|*"/actions/runners/remove-token --jq .token") echo "$FAKE_TOKEN" ;;
  *"/actions/runners") [ -e "$D/runners.fail" ] && { echo "HTTP 403" >&2; exit 1; }
    # with an admin named (forkpr.admin), the runner list is an admin's read too, as on GitHub
    [ -e "$D/forkpr.admin" ] && [ "${GH_TOKEN:-}" != "$(cat "$D/forkpr.admin")" ] && { echo "HTTP 404" >&2; exit 1; }
    cat "$D/runners.json" 2>/dev/null || echo '{"total_count":0,"runners":[]}' ;;
  *"/actions/workflows/check.yml/runs?status=queued&per_page=20") cat "$D/queued.json" 2>/dev/null || echo '{"workflow_runs":[]}' ;;
  *" --jq .private") p=$(cat "$D/private" 2>/dev/null || echo true); [ "$p" = fail ] && { echo "HTTP 404" >&2; exit 1; }; echo "$p" ;;
  *"/actions/permissions/fork-pr-workflows-private-repos") f=$(cat "$D/forkpr" 2>/dev/null || echo false)
    # an admin's token reads it where the login cannot: $D/forkpr.admin names that token
    [ "$f" = fail ] && [ -n "${GH_TOKEN:-}" ] && [ "$GH_TOKEN" = "$(cat "$D/forkpr.admin" 2>/dev/null)" ] && f=false
    [ "$f" = fail ] && { echo "HTTP 404" >&2; exit 1; }
    echo "{\"run_workflows_from_fork_pull_requests\":$f,\"send_write_tokens_to_workflows\":false,\"send_secrets_and_variables\":false,\"require_approval_for_fork_pr_workflows\":false}" ;;
  *"/collaborators?per_page=100") cat "$D/collabs.json" 2>/dev/null || echo '[{"login":"alice","permissions":{"admin":true,"push":true,"pull":true}},{"login":"bob","permissions":{"admin":false,"maintain":false,"push":true,"pull":true}},{"login":"carol","permissions":{"admin":false,"push":false,"pull":true}}]' ;;
  # GitHub answers a PATCH, contexts or checks alike, with both lists (a context's app_id: null here)
  *"-X PATCH"*required_status_checks*) cat > "$D/patch.json"
    python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); ch=d.get("checks")
ctx=[c["context"] for c in ch] if ch is not None else d.get("contexts", [])
ch=[{"context": c["context"], "app_id": c.get("app_id")} for c in ch] if ch is not None else [{"context": c, "app_id": None} for c in ctx]
json.dump({"strict": d.get("strict"), "contexts": ctx, "checks": ch}, open(sys.argv[2], "w"))' "$D/patch.json" "$D/rsc.json"
    cat "$D/rsc.json" ;;
  *required_status_checks*) cat "$D/rsc.json" ;;
  *"/branches/main") [ -e "$D/branch.json" ] || { echo "fake gh: no branch.json" >&2; exit 1; }; cat "$D/branch.json" ;;
  *"/status") cat "$D/status.json" 2>/dev/null || echo '{"statuses":[]}' ;;
  *"/check-runs") cat "$D/checkruns.json" 2>/dev/null || echo '{"check_runs":[]}' ;;
  *"-X POST "*"/actions/variables --input -") mkdir -p "$D/vars"; cat > "$D/vars/post.json"
    n=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["name"])' "$D/vars/post.json")
    [ -e "$D/vars/$n.refuse" ] && { rm -f "$D/vars/post.json"; echo "HTTP 403" >&2; exit 1; }
    [ -e "$D/vars/$n.json" ] && { echo "HTTP 409" >&2; exit 1; }; mv "$D/vars/post.json" "$D/vars/$n.json" ;;
  *"-X PATCH "*"/actions/variables/"*" --input -") n=${args##*/actions/variables/}; n=${n%% *}
    [ -e "$D/vars/$n.refuse" ] && { echo "HTTP 403" >&2; exit 1; }
    [ -e "$D/vars/$n.json" ] || { echo "gh: Not Found (HTTP 404)" >&2; exit 1; }; cat > "$D/vars/$n.json" ;;
  *"/actions/variables/"*) n=${args##*/}; { [ -e "$D/vars/fail" ] || [ -e "$D/vars/$n.unread" ]; } && exit 1
    [ -e "$D/vars/$n.json" ] && cat "$D/vars/$n.json" || { echo '{"message":"Not Found"}'; echo "gh: Not Found (HTTP 404)" >&2; exit 1; } ;;
  # a runner's custom labels set (PUT) or cleared (DELETE) in runners.json, answered as GitHub does
  *"-X PUT "*"/actions/runners/"*"/labels --input -"|*"-X DELETE "*"/actions/runners/"*"/labels")
    [ -e "$D/labels.fail" ] && { echo "HTTP 422" >&2; exit 1; }
    id=${args##*/actions/runners/}; id=${id%%/*}; body='{"labels":[]}'; case "$args" in *PUT*) body=$(cat) ;; esac
    python3 "$D/setlabels.py" "$D/runners.json" "$id" "$body" ;;
  *) echo "fake gh: unhandled $args" >&2; exit 1 ;;
esac
EOF
cat > "$T/gh/setlabels.py" <<'EOF'
import json, sys
path, rid, body = sys.argv[1], int(sys.argv[2]), json.loads(sys.argv[3])
d = json.load(open(path))
r = next(r for r in d["runners"] if r["id"] == rid)
r["labels"] = [l for l in r["labels"] if l.get("type") != "custom"] + [{"name": n, "type": "custom"} for n in body["labels"]]
json.dump(d, open(path, "w"))
print(json.dumps({"total_count": len(r["labels"]), "labels": r["labels"]}))
EOF
chmod +x "$T/bin/gh"
# A fake ssh: records its argv and stdin in $T/ssh, then runs the remote command here, as the runner Mac
# would, with HOME=$T/ssh/home and $T/ssh/rbin (fake launchctl, curl, stat) first on PATH.
mkdir -p "$T/ssh/home" "$T/ssh/rbin"
# The runner script read a size with BSD `stat -f %z` until it learnt Linux (linux-runner): GNU stat's -f is
# the file system's status, so on CI's ubuntu every size read 0. It reads `wc -c` now; this stat stays, so a
# script that went back to the BSD form would still read right here, and fails on any other form.
cat > "$T/ssh/rbin/stat" <<'EOF'
#!/usr/bin/env bash
[ "$1" = -f ] && [ "$2" = %z ] && [ -f "$3" ] && { wc -c < "$3" | tr -d ' '; exit 0; }
echo "fake stat: only -f %z FILE (got: $*)" >&2; exit 1
EOF
cat > "$T/bin/ssh" <<'EOF'
#!/usr/bin/env bash
D="$FAKE_SSH"
printf '%s\n' "$@" >> "$D/argv"
tee -a "$D/stdin" | env -u XDG_CONFIG_HOME HOME="$D/home" PATH="$D/rbin:$PATH" bash -c "${@: -1}"
EOF
cat > "$T/ssh/rbin/launchctl" <<'EOF'
#!/usr/bin/env bash
case "$1" in list) cat "$FAKE_SSH/loaded" 2>/dev/null; echo "-	0	com.apple.other" ;; *) echo "launchctl $*" >> "$FAKE_SSH/launchctl" ;; esac
EOF
# the runner host's architecture is $FAKE_ARCH's (arm64 unless a case sets it) and its system $FAKE_SYSTEM's
# (Darwin unless a case sets Linux), on any machine the suite runs on
cat > "$T/ssh/rbin/uname" <<'EOF'
#!/usr/bin/env bash
[ "$1" = -m ] && { echo "${FAKE_ARCH:-arm64}"; exit 0; }
[ "$1" = -s ] && { echo "${FAKE_SYSTEM:-Darwin}"; exit 0; }
exec /usr/bin/uname "$@"
EOF
# and its installed locales $FAKE_LOCALES's (unset: C, en_US.UTF-8, C.UTF-8 and the suite's own LANG),
# written in pieces with a pause and a long tail, as the real one is: a `locale -a | grep -q` reader
# then meets SIGPIPE under pipefail, as on a Mac (497 of 500 there, 2026-10-27), not a single write
cat > "$T/ssh/rbin/locale" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = -a ]; then
  for l in ${FAKE_LOCALES:-C en_US.UTF-8 C.UTF-8 ${LANG:-}}; do printf '%s\n' "$l"; done
  sleep 0.2
  for i in $(seq 1 400); do printf 'zz_%s.UTF-8\n' "$i"; done
  exit 0
fi
exec /usr/bin/locale "$@"
EOF
cat > "$T/ssh/rbin/curl" <<'EOF'
#!/usr/bin/env bash
echo "curl $*" >> "$FAKE_SSH/curl"; exit 22
EOF
chmod +x "$T/bin/ssh" "$T/ssh/rbin/"*
TOKEN="AAAFAKERUNNERTOKEN0123456789"
# git as it is, bar what reaches origin, which is no network here: $T/gh/fetch.fail, origin unreachable;
# $T/gh/default, its default branch (main; `none`: an origin with no branch yet), the one a fetch finds
REAL_GIT=$(command -v git)
cat > "$T/bin/git" <<'EOF'
#!/usr/bin/env bash
b=$(cat "$FAKE_GH/default" 2>/dev/null || echo main)
case " $* " in
  *" ls-remote --symref origin HEAD "*) [ -e "$FAKE_GH/fetch.fail" ] && { echo "fatal: unable to access origin" >&2; exit 128; }
    [ "$b" = none ] || printf 'ref: refs/heads/%s\tHEAD\n' "$b"; exit 0 ;;
  *" fetch -q origin +refs/heads/$b:"*) [ -e "$FAKE_GH/fetch.fail" ] && exit 128; exit 0 ;;
  *" fetch -q origin "*) echo "fatal: couldn't find remote ref" >&2; exit 128 ;;
esac
exec "$REAL_GIT" "$@"
EOF
chmod +x "$T/bin/git"
export PATH="$T/bin:$PATH" FAKE_GH="$T/gh" FAKE_SSH="$T/ssh" FAKE_TOKEN="$TOKEN" REAL_GIT
echo '{"strict": false, "contexts": ["check"]}' > "$T/gh/rsc.json"

newrepo() { # newrepo <dir>: a repo on a claude/* branch with Actions' check.yml and protection
  local r="$1"
  mkdir -p "$r/.github/workflows"
  git -C "$r" init -q -b main
  git -C "$r" remote add origin https://github.com/acme/demo.git
  sed 's/{{COMMAND}}/sh check.sh/' "$TPL/.github/workflows/check.yml" > "$r/.github/workflows/check.yml"
  cp "$TPL/.github/main-protection.json" "$r/.github/main-protection.json"
  git -C "$r" add -A && git -C "$r" -c user.name=t -c user.email=t@t commit -qm init
  git -C "$r" update-ref refs/remotes/origin/main HEAD
  git -C "$r" checkout -q -b claude/test/2026-10-18-ci
}
ctx() { python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['required_status_checks']['contexts'])" "$1"; }
# yamlread FILE EXPR: EXPR, python over the parsed file as d, printed as one string (a block scalar's
# last newline not doubled). PyYAML, which every host that runs this suite has: ruby is not on all of them
yamlread() { python3 -c 'import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
s = str(eval(sys.argv[2]))
print(s, end="" if s.endswith("\n") else "\n")' "$1" "$2"; }
yamlok() { yamlread "$1" '",".join(sorted(d["jobs"])) + "|" + ",".join(sorted(d["workflows"]))'; }

echo "switching"
R="$T/a"; newrepo "$R"
git -C "$R" checkout -q main
"$CP" "$R" --to circleci > /dev/null 2>&1; check "$?" "2" "on main: refused, the switch happens on a branch"
git -C "$R" checkout -q claude/test/2026-10-18-ci
"$CP" "$R" --to circleci > "$T/out" 2>&1; check "$?" "0" "actions → circleci"
check "$(test -e "$R/.github/workflows/check.yml" && echo there || echo gone)" "gone" "check.yml removed"
check "$(grep -c 'sh check.sh' "$R/.circleci/parts/check.yml")" "1" "the part runs the same command"
check "$(head -1 "$R/.circleci/config.yml" | cut -c1-34)" "# GENERATED by wharf's ci-provider" "config.yml is generated"
check "$(yamlok "$R/.circleci/config.yml")" "check|check" "config.yml parses: job check, workflow check"
check "$(ctx "$R/.github/main-protection.json")" "['ci/circleci: check']" "main-protection.json requires CircleCI's status"
check "$(python3 -c "import json; d=json.load(open('$R/.github/ci.json')); print(d['provider'], d['check'])")" "circleci sh check.sh" "ci.json records the provider and the command"
grep -q 'ci-provider .* --protect' "$T/out"; check "$?" "0" "it says --protect comes after the first green run"

cp -R "$R" "$T/a1"
"$CP" "$R" --to actions > /dev/null 2>&1; check "$?" "0" "circleci → actions"
check "$(grep -A1 'run: |' "$R/.github/workflows/check.yml" | tail -1 | sed 's/^ *//')" "sh check.sh" "check.yml back, same command"
check "$(test -e "$R/.circleci" && echo there || echo gone)" "gone" "nothing of CircleCI left when check was the only part"
check "$(ctx "$R/.github/main-protection.json")" "['check']" "protection back to Actions' check"
"$CP" "$R" --to circleci > /dev/null 2>&1
check "$(cd "$T/a1" && find .circleci .github -type f | sort | xargs shasum | shasum)" \
      "$(cd "$R" && find .circleci .github -type f | sort | xargs shasum | shasum)" "a round trip leaves the same files"

echo "a repo's own CircleCI jobs"
R="$T/b"; newrepo "$R"; mkdir -p "$R/.circleci"
cat > "$R/.circleci/config.yml" <<'EOF'
# The untrusted harness (its reasons, kept through every switch).
version: 2.1

jobs:
  port:
    machine:
      image: ubuntu-2204:2026.05.1
    steps:
      - checkout

workflows:
  proof-port:
    jobs:
      - port
EOF
"$CP" "$R" --to circleci > /dev/null 2>&1; check "$?" "0" "a hand-written config is adopted"
check "$(grep -c 'untrusted harness' "$R/.circleci/parts/main.yml")" "1" "…as parts/main.yml, comments kept"
check "$(grep -c '^version:' "$R/.circleci/config.yml")" "1" "one version line"
check "$(yamlok "$R/.circleci/config.yml")" "check,port|check,proof-port" "both parts composed"
check "$(grep -c 'untrusted harness' "$R/.circleci/config.yml")" "1" "the part's comment reaches config.yml"
"$CP" "$R" --compose > "$T/out" 2>&1; check "$(grep -c 'already composed' "$T/out")" "1" "compose is idempotent"
"$CP" "$R" --to actions > /dev/null 2>&1
check "$(yamlok "$R/.circleci/config.yml")" "port|proof-port" "back to actions: the harness stays on CircleCI"
python3 -c "import sys; p=sys.argv[1]; t=open(p).read(); open(p,'w').write(t.replace('# GENERATED','# EDITED',1))" "$R/.circleci/config.yml"
"$CP" "$R" --to circleci > "$T/out" 2>&1; check "$?" "2" "a hand edit beside parts/ is refused"
grep -q 'edited by hand' "$T/out"; check "$?" "0" "…and says why"

echo "refusals"
R="$T/c"; newrepo "$R"; mkdir -p "$R/.circleci/parts"
printf 'jobs:\n  check:\n    docker:\n      - image: x\n    steps: [checkout]\nworkflows:\n  w:\n    jobs: [check]\n' > "$R/.circleci/parts/zz.yml"
"$CP" "$R" --to circleci > "$T/out" 2>&1; check "$?" "2" "two parts defining job check: refused"
grep -q 'both define jobs `check`' "$T/out"; check "$?" "0" "…naming both parts"
R="$T/d"; newrepo "$R"; touch "$R/.github/workflows/automerge.yml"
"$CP" "$R" --to circleci > "$T/out" 2>&1; check "$?" "2" "automerge.yml: refused (it waits on Actions)"
R="$T/e"; newrepo "$R"
"$CP" "$R" --to circleci --check $'sh check.sh\necho done' > /dev/null 2>&1
check "$(yamlread "$R/.circleci/config.yml" 'd["jobs"]["check"]["steps"][1]["run"]["command"]' | tr '\n' ';')" "sh check.sh;echo done;" "a two-line command survives"
"$CP" "$R" --to actions > /dev/null 2>&1
check "$(yamlread "$R/.github/workflows/check.yml" 'd["jobs"]["check"]["steps"][1]["run"]' | tr '\n' ';')" "sh check.sh;echo done;" "…both ways"
"$CP" "$R" --to circleci --dry-run > "$T/out" 2>&1
check "$(grep -c 'would' "$T/out" | tr -d ' ' | sed 's/^[1-9][0-9]*$/some/')" "some" "--dry-run says what it would do"
check "$(test -e "$R/.circleci/parts/check.yml" && echo wrote || echo none)" "none" "…and writes nothing"

echo "protect (fake gh)"
R="$T/f"; newrepo "$R"; "$CP" "$R" --to circleci > /dev/null 2>&1
echo '{"strict": false, "contexts": ["check"]}' > "$T/gh/rsc.json"
echo '{"statuses":[]}' > "$T/gh/status.json"
"$CP" "$R" --protect > "$T/out" 2>&1; check "$?" "2" "no green ci/circleci: check yet: refused"
check "$(python3 -c "import json; print(json.load(open('$T/gh/rsc.json'))['contexts'])")" "['check']" "…and GitHub untouched"
echo '{"statuses":[{"context":"ci/circleci: check","state":"success"}]}' > "$T/gh/status.json"
"$CP" "$R" --protect --dry-run > /dev/null 2>&1
check "$(python3 -c "import json; print(json.load(open('$T/gh/rsc.json'))['contexts'])")" "['check']" "--dry-run changes nothing"
"$CP" "$R" --protect > "$T/out" 2>&1; check "$?" "0" "green: protected"
check "$(python3 -c "import json; d=json.load(open('$T/gh/patch.json')); print(sorted(d), d['contexts'])")" "['contexts', 'strict'] ['ci/circleci: check']" "the PATCH carries only strict and contexts"
grep -q "read back: \['ci/circleci: check'\]" "$T/out"; check "$?" "0" "the result is read back"
"$CP" "$R" --protect > "$T/out" 2>&1; check "$(grep -c 'already requires' "$T/out")" "1" "a second --protect is a no-op"
"$CP" "$R" > "$T/out" 2>&1; check "$?" "0" "status runs"
grep -q 'circleci (ci.json)' "$T/out"; check "$?" "0" "status names the provider"

echo "a check name other than the provider's default (ci.json context)"
R="$T/g"; newrepo "$R"
"$CP" "$R" --to circleci --context "test-and-merge/check" > /dev/null 2>&1; check "$?" "0" "--to circleci --context"
check "$(python3 -c "import json; print(json.load(open('$R/.github/ci.json')).get('context'))")" "test-and-merge/check" "ci.json keeps the name"
check "$(ctx "$R/.github/main-protection.json")" "['test-and-merge/check']" "main-protection.json requires it"
"$CP" "$R" --to circleci > /dev/null 2>&1
check "$(python3 -c "import json; print(json.load(open('$R/.github/ci.json')).get('context'))")" "test-and-merge/check" "a second --to on the same provider keeps it"
echo '{"strict": false, "contexts": ["check"]}' > "$T/gh/rsc.json"
echo '{"statuses":[{"context":"ci/circleci: check","state":"success"}]}' > "$T/gh/status.json"
"$CP" "$R" --protect > /dev/null 2>&1; check "$?" "2" "--protect wants that name, not the default"
echo '{"statuses":[{"context":"test-and-merge/check","state":"success"}]}' > "$T/gh/status.json"
"$CP" "$R" --protect > /dev/null 2>&1; check "$?" "0" "…and protects once it reported"
check "$(python3 -c "import json; print(json.load(open('$T/gh/rsc.json'))['contexts'])")" "['test-and-merge/check']" "GitHub requires that name"
"$CP" "$R" --to actions > /dev/null 2>&1
check "$(python3 -c "import json; print(json.load(open('$R/.github/ci.json')).get('context'))")" "None" "a switch to the other provider drops it"
check "$(ctx "$R/.github/main-protection.json")" "['check']" "…and requires Actions' default"

echo "the review of 2026-10-18: which step is the check"
R="$T/h"; newrepo "$R"
python3 - "$R/.github/workflows/check.yml" <<'PY'
import sys; p=sys.argv[1]; t=open(p).read()
t=t.replace("      - name: check\n", "      - name: git identity\n        run: |\n          git config --global user.name ci\n      - name: check\n", 1)
open(p,"w").write(t)
PY
"$CP" "$R" --to circleci --dry-run > "$T/out" 2>&1
grep -q '(check: sh check.sh)' "$T/out"; check "$?" "0" "a setup step before it: the step named check is the check"
"$CP" "$R" --to circleci > "$T/out" 2>&1; check "$?" "2" "…and check.yml holding more than the template is refused"
grep -q 'force' "$T/out"; check "$?" "0" "…naming --force"
check "$(test -e "$R/.circleci" && echo wrote || echo none)" "none" "…writing nothing"
"$CP" "$R" --to circleci --force > /dev/null 2>&1; check "$?" "0" "--force takes it"
R="$T/h2"; newrepo "$R"
python3 - "$R/.github/workflows/check.yml" <<'PY'
import sys; p=sys.argv[1]; t=open(p).read()
t=t.replace("      - name: check\n", "      - name: deps\n        run: |\n          pip install x\n      - run: |\n          sh other.sh\n", 1)
open(p,"w").write(t)
PY
"$CP" "$R" --to circleci --dry-run > "$T/out" 2>&1; check "$?" "2" "two run blocks, none named check: refused"
"$CP" "$R" --to circleci --dry-run --check 'sh check.sh' --force > /dev/null 2>&1; check "$?" "0" "…--check names it"
R="$T/h3"; newrepo "$R"; "$CP" "$R" --to circleci > /dev/null 2>&1
python3 -c "import json,sys; p=sys.argv[1]; d=json.load(open(p)); d['check']='sh stale.sh'; open(p,'w').write(json.dumps(d))" "$R/.github/ci.json"
"$CP" "$R" --to actions > /dev/null 2>&1
check "$(grep -c 'sh check.sh' "$R/.github/workflows/check.yml")" "1" "the live part wins over ci.json's record"

echo "the review of 2026-10-18: compose and hand edits"
R="$T/i"; newrepo "$R"; "$CP" "$R" --to circleci > /dev/null 2>&1
sed -i.bak 's/resource_class: small/resource_class: large/' "$R/.circleci/config.yml" && rm -f "$R/.circleci/config.yml.bak"   # not -i '': GNU sed reads '' as the script
"$CP" "$R" --compose > "$T/out" 2>&1; check "$?" "2" "--compose over a hand-edited body: refused"
check "$(grep -c 'resource_class: large' "$R/.circleci/config.yml")" "1" "…the edit kept"
"$CP" "$R" --to actions > /dev/null 2>&1; check "$?" "2" "--to actions over it: refused too"
R="$T/j"; newrepo "$R"; mkdir -p "$R/.circleci"
printf 'version: 2.1\njobs:\n  check:\n    docker:\n      - image: x\n    steps: [checkout]\nworkflows:\n  w:\n    jobs: [check]\n' > "$R/.circleci/config.yml"
"$CP" "$R" --to circleci > "$T/out" 2>&1; check "$?" "2" "adopting a config with its own job check: refused"
check "$(test -e "$R/.circleci/parts" && echo partial || echo clean)" "clean" "…before writing anything"
check "$(test -e "$R/.github/workflows/check.yml" && echo kept || echo gone)" "kept" "…check.yml still there"
R="$T/k"; newrepo "$R"; mkdir -p "$R/.circleci"
printf 'version: 2.1\norbs:\n  node: circleci/node@5.2.0\njobs:\n  port: &port\n    docker:\n      - image: x\n    steps: [checkout]\n  port2: *port\nworkflows:\n  w:\n    jobs:\n      - node/test\n      - port\n' > "$R/.circleci/config.yml"
"$CP" "$R" --to circleci > "$T/out" 2>&1; check "$?" "0" "an orb job and an alias are adopted"
R="$T/l"; newrepo "$R"; mkdir -p "$R/.circleci/parts"
printf 'jobs:\n    port:\n      docker:\n        - image: x\nworkflows:\n    p:\n      jobs: [port]\n' > "$R/.circleci/parts/a.yml"
"$CP" "$R" --to circleci > "$T/out" 2>&1; check "$?" "2" "a part indented 4 spaces: refused"
grep -q 'compose needs 2' "$T/out"; check "$?" "0" "…saying why"
R="$T/m"; newrepo "$R"; mkdir -p "$R/.circleci/parts"
printf 'setup: true\njobs:\n  port:\n    docker:\n      - image: x\nworkflows:\n  p:\n    jobs: [port]\n' > "$R/.circleci/parts/a.yml"
"$CP" "$R" --to circleci > "$T/out" 2>&1; check "$?" "2" "an inline top-level key (setup: true): refused"
grep -q 'inline value' "$T/out"; check "$?" "0" "…as an inline value"
R="$T/m2"; newrepo "$R"
"$CP" "$R" --compose --context x > /dev/null 2>&1; check "$?" "2" "--context without --to: an error, not ignored"
R="$T/m3"; newrepo "$R"
python3 - "$R/.github/workflows/check.yml" <<'PY'
import sys; p=sys.argv[1]; t=open(p).read()
t=t.replace("      - name: check\n        run: |\n          sh check.sh\n", "      - name: git identity\n        run: |\n          git config --global user.name ci\n      - name: check\n        run: sh check.sh\n", 1)
open(p,"w").write(t)
PY
"$CP" "$R" --to circleci --dry-run --force > "$T/out" 2>&1
grep -q '(check: sh check.sh)' "$T/out"; check "$?" "0" "a one-line run: under the step named check is the check"
"$CP" "$R" --to actions > /dev/null 2>&1; check "$?" "2" "a re-run on the same provider: its extra step refused too"
R="$T/m4"; newrepo "$R"
python3 - "$R/.github/workflows/check.yml" <<'PY'
import sys; p=sys.argv[1]; t=open(p).read()
open(p,"w").write(t.replace("\njobs:", "\nenv:\n  MODE: strict\njobs:", 1))
PY
"$CP" "$R" --to circleci > /dev/null 2>&1; check "$?" "2" "a top-level env: is refused, not dropped"

echo "the review of 2026-10-18: --protect keeps the other required checks"
R="$T/n"; newrepo "$R"
python3 -c "import json,sys; p=sys.argv[1]; d=json.load(open(p)); d['required_status_checks']['contexts']=['check','lint']; open(p,'w').write(json.dumps(d))" "$R/.github/main-protection.json"
"$CP" "$R" --to circleci > /dev/null 2>&1
check "$(ctx "$R/.github/main-protection.json")" "['lint', 'ci/circleci: check']" "main-protection.json: check swapped, lint kept"
echo '{"strict": true, "contexts": ["check", "ci/circleci: port"]}' > "$T/gh/rsc.json"
echo '{"statuses":[{"context":"ci/circleci: check","state":"success"}]}' > "$T/gh/status.json"
"$CP" "$R" --protect > "$T/out" 2>&1; check "$?" "0" "--protect with two required checks"
check "$(python3 -c "import json; print(json.load(open('$T/gh/rsc.json'))['contexts'])")" "['ci/circleci: port', 'ci/circleci: check']" "…the other one kept"
grep -q 'rollback: ' "$T/out"; check "$?" "0" "…and the PATCH that undoes it printed"
R="$T/n2"; newrepo "$R"
"$CP" "$R" --to circleci --context X > /dev/null 2>&1
echo '{"strict": false, "contexts": ["X"]}' > "$T/gh/rsc.json"
"$CP" "$R" --to circleci --context Y > /dev/null 2>&1
check "$(python3 -c "import json; print(json.load(open('$R/.github/ci.json')).get('replaces'))")" "['X']" "a replaced context is recorded"
echo '{"statuses":[{"context":"Y","state":"success"}]}' > "$T/gh/status.json"
"$CP" "$R" --protect > /dev/null 2>&1
check "$(python3 -c "import json; print(json.load(open('$T/gh/rsc.json'))['contexts'])")" "['Y']" "…and --protect swaps it out on GitHub"
R="$T/o"; newrepo "$R"
echo '{"required_status_checks": null, "enforce_admins": false}' > "$R/.github/main-protection.json"
"$CP" "$R" --to circleci > /dev/null 2>&1; check "$?" "0" "main-protection.json with null required checks"
check "$(ctx "$R/.github/main-protection.json")" "['ci/circleci: check']" "…gets CircleCI's"

echo "self-hosted: Actions on the runner Mac's self-hosted runner"
echo '{"strict": false, "contexts": ["check"]}' > "$T/gh/rsc.json"
R="$T/p"; newrepo "$R"; cp "$R/.github/workflows/check.yml" "$T/p.ubuntu.yml"
"$CP" "$R" --to self-hosted > "$T/out" 2>&1; check "$?" "0" "actions → self-hosted"
check "$(yamlread "$R/.github/workflows/check.yml" '",".join(d["jobs"]["check"]["runs-on"])')" "self-hosted,macOS" "check.yml asks for a self-hosted macOS runner, not the labels key's machine"
check "$(grep -c "^ *if: .*!github.event.pull_request.draft" "$R/.github/workflows/check.yml")" "1" "…the draft skip kept"
check "$(grep -c 'cancel-in-progress: true' "$R/.github/workflows/check.yml")" "1" "…the concurrency block kept"
check "$(grep -c "^ *group: check-.*pull_request.draft && 'draft' || 'live'" "$R/.github/workflows/check.yml")" "1" "…its group keyed on draft (the 2026-10-25 race)"
check "$(grep -c "^ *name: \${{ github.event.pull_request.draft && 'check (draft)' || 'check' }}$" "$R/.github/workflows/check.yml")" "1" "…its job named check (draft) on a draft, so a skipped run is never the required check"
check "$(grep -c "per_page=20" "$TPL/.github/workflows/automerge.yml")" "1" "…the template's automerge reads the last 20 runs, not the newest alone"
check "$(grep -c "carries hold (read live)" "$TPL/.github/workflows/automerge.yml")" "1" "…and reads hold live before arming, as the draft-keyed group no longer cancels a stale labeled run"
check "$(grep -A1 'run: |' "$R/.github/workflows/check.yml" | tail -1 | sed 's/^ *//')" "sh check.sh" "…the same command"
check "$(python3 -c "import json; d=json.load(open('$R/.github/ci.json')); print(d['provider'], d['check'])")" "self-hosted sh check.sh" "ci.json records self-hosted"
check "$(ctx "$R/.github/main-protection.json")" "['check']" "main's required check stays check"
grep -q 'no --protect' "$T/out"; check "$?" "0" "it says no --protect is needed"
grep -q -- '--runner install' "$T/out"; check "$?" "0" "it names the runner install"
"$CP" "$R" --to self-hosted > /dev/null 2>&1; check "$?" "0" "a re-run on self-hosted: its own runs-on is no extra"
"$CP" "$R" > "$T/out" 2>&1; grep -q 'self-hosted (ci.json)' "$T/out"; check "$?" "0" "status names self-hosted"
grep -q 'no online runner labelled self-hosted, macOS:' "$T/out"; check "$?" "0" "…and warns with no runner online"
rm "$R/.github/ci.json"
"$CP" "$R" > "$T/out" 2>&1; grep -q 'self-hosted (inferred' "$T/out"; check "$?" "0" "without ci.json, self-hosted inferred from runs-on"
"$CP" "$R" --to actions > /dev/null 2>&1; check "$?" "0" "self-hosted → actions"
check "$(shasum < "$R/.github/workflows/check.yml")" "$(shasum < "$T/p.ubuntu.yml")" "…the ubuntu file back, byte for byte"
"$CP" "$R" --protect > "$T/out" 2>&1; check "$(grep -c 'already requires' "$T/out")" "1" "--protect: check is already required"
R="$T/p2"; newrepo "$R"; touch "$R/.github/workflows/automerge.yml"
"$CP" "$R" --to self-hosted > "$T/out" 2>&1; check "$?" "0" "automerge.yml is no refusal for self-hosted"
grep -q 'automerge.yml stays on ubuntu-latest' "$T/out"; check "$?" "0" "…its hosted minute named"
R="$T/p3"; newrepo "$R"
echo '{"provider": "actions", "check": "sh check.sh", "context": "mac check"}' > "$R/.github/ci.json"
"$CP" "$R" --to self-hosted > /dev/null 2>&1
check "$(python3 -c "import json; print(json.load(open('$R/.github/ci.json')).get('context'))")" "mac check" "a context crosses actions → self-hosted (same job)"
R="$T/p4"; newrepo "$R"; "$CP" "$R" --to circleci > /dev/null 2>&1
"$CP" "$R" --to self-hosted > "$T/out" 2>&1; check "$?" "0" "circleci → self-hosted"
grep -q -- "--protect" "$T/out"; check "$?" "0" "…and that one needs --protect"

echo "self-hosted: a two-image macOS matrix"
R="$T/pm"; newrepo "$R"
python3 - "$R/.github/workflows/check.yml" "$R/.github/main-protection.json" <<'PY'
import json, sys
p = sys.argv[1]; t = open(p).read()
t = t.replace("    runs-on: ubuntu-latest\n", "    strategy:\n      matrix:\n        os: [macos-latest, macos-15]\n    runs-on: ${{ matrix.os }}\n", 1)
open(p, "w").write(t)
q = sys.argv[2]; d = json.load(open(q)); d["required_status_checks"]["contexts"] = ["check (macos-latest)", "check (macos-15)", "lint"]
open(q, "w").write(json.dumps(d))
PY
"$CP" "$R" --to self-hosted > /dev/null 2>&1; check "$?" "2" "a matrix is more than the template: refused without --force"
"$CP" "$R" --to self-hosted --force > "$T/out" 2>&1; check "$?" "0" "…--force takes it"
check "$(grep -cE '^ +(strategy|matrix):' "$R/.github/workflows/check.yml")" "0" "…one job, no matrix"
check "$(ctx "$R/.github/main-protection.json")" "['lint', 'check']" "the matrix names leave main-protection.json, lint stays"
grep -q -- "--protect" "$T/out"; check "$?" "0" "…so the switch says --protect"
grep -q 'no --protect' "$T/out"; check "$?" "1" "…not 'no --protect'"
echo '{"strict": false, "contexts": ["check (macos-latest)", "check (macos-15)", "lint"]}' > "$T/gh/rsc.json"
echo '{"statuses":[{"context":"check","state":"success"}]}' > "$T/gh/status.json"
"$CP" "$R" --protect > /dev/null 2>&1; check "$?" "0" "--protect once check reported"
check "$(python3 -c "import json; print(json.load(open('$T/gh/rsc.json'))['contexts'])")" "['lint', 'check']" "…GitHub's matrix names swapped for check"
echo '{"strict": false, "contexts": ["check"]}' > "$T/gh/rsc.json"

echo "self-hosted: a public repo never runs on the runner Mac"
R="$T/q"; newrepo "$R"; : > "$T/gh/calls"; rm -f "$T/ssh/argv"
echo false > "$T/gh/private"
"$CP" "$R" --to self-hosted > "$T/out" 2>&1; check "$?" "2" "--to self-hosted on a public repo: refused"
grep -q 'is public' "$T/out"; check "$?" "0" "…saying why"
check "$(shasum < "$R/.github/workflows/check.yml")" "$(shasum < "$T/p.ubuntu.yml")" "…check.yml untouched"
"$CP" "$R" --runner install > "$T/out" 2>&1; check "$?" "2" "--runner install on a public repo: refused"
check "$(test -e "$T/ssh/argv" && echo ssh || echo none)" "none" "…no ssh"
check "$(grep -c token "$T/gh/calls")" "0" "…no token asked for"
echo fail > "$T/gh/private"
"$CP" "$R" --to self-hosted > /dev/null 2>&1; check "$?" "2" "privacy unread: refused, not guessed"
echo true > "$T/gh/private"

echo "self-hosted: the runner (fake gh, fake ssh)"
R="$T/r"; newrepo "$R"
fakerunner() { # fakerunner <dir> <word>: a runner's svc.sh and config.sh, its status saying <word>
  mkdir -p "$1"
  cat > "$1/svc.sh" <<EOF
#!/usr/bin/env bash
case "\$1" in
  install) echo "\$HOME/Library/LaunchAgents/actions.runner.acme-demo.laptop.plist" > .service ;;
  start) echo "1	0	actions.runner.acme-demo.laptop" > "\$FAKE_SSH/loaded"; echo started >> "\$FAKE_SSH/svc" ;;
  stop) rm -f "\$FAKE_SSH/loaded"; echo stopped >> "\$FAKE_SSH/svc" ;;
  status) echo "status actions.runner.acme-demo.laptop: $2" ;;
  uninstall) rm -f .service "\$FAKE_SSH/loaded" ;;
esac
EOF
  cat > "$1/config.sh" <<'EOF'
#!/usr/bin/env bash
[ "${ACTIONS_RUNNER_INPUT_TOKEN:-}" = "$FAKE_TOKEN" ] && echo "$1" >> "$FAKE_SSH/envtoken"
[ "$1" = remove ] && rm -f .runner
[ "$1" = --unattended ] && echo '{"gitHubUrl": "https://github.com/acme/demo"}' > .runner && printf 'LANG=%s\n' "${LANG:-}" > .env
echo "config.sh $*"
EOF
  chmod +x "$1/svc.sh" "$1/config.sh"
}
RD="$T/ssh/home/actions-runners/acme/demo"; fakerunner "$RD" nested
touch "$RD/.runner"  # configured already: the download is a later case's
echo '{"total_count":1,"runners":[{"id":7,"name":"laptop","os":"macOS","status":"online","busy":false,"labels":[{"name":"self-hosted"},{"name":"macOS"},{"name":"ARM64"},{"name":"laptop"}]}]}' > "$T/gh/runners.json"
"$CP" "$R" --runner install --dry-run > "$T/out" 2>&1; check "$?" "0" "--runner install --dry-run"
check "$(test -e "$T/ssh/argv" && echo ssh || echo none)" "none" "…no ssh"
: > "$T/gh/calls"
"$CP" "$R" --runner install > "$T/out" 2>&1; check "$?" "0" "--runner install"
check "$(cat "$T/ssh/svc" 2>/dev/null)" "started" "…the service installed and started"
grep -q 'runner laptop online' "$T/out"; check "$?" "0" "…read back online from GitHub"
check "$(grep -cx 'laptop-ci' "$T/ssh/argv")" "$(grep -cx 'BatchMode=yes' "$T/ssh/argv")" "…every ssh to the alias the ssh key names"
check "$(grep -c "$TOKEN" "$T/out")" "0" "the token is in none of its output"
check "$(grep -c "$TOKEN" "$T/ssh/argv")" "0" "…nor in ssh's argv"
check "$(grep -c 'registration-token' "$T/gh/calls")" "0" "configured already on the runner Mac: no registration token minted (K)"
check "$(grep -c "$TOKEN" "$T/ssh/stdin" 2>/dev/null)" "0" "…none on ssh's stdin"
check "$(grep -cx 'actions-runners/acme/demo' "$T/ssh/argv")" "$(grep -cx 'install' "$T/ssh/argv")" "one directory per repo, nested owner/repo (J)"
"$CP" "$R" --runner install > "$T/out" 2>&1; check "$?" "0" "a second install: no-op"
check "$(cat "$T/ssh/svc")" "started" "…the loaded service not started twice"
: > "$T/gh/calls"
"$CP" "$R" > "$T/out" 2>&1
check "$(grep -c '/actions/runners' "$T/gh/calls")" "0" "status of an actions repo: no runners API call (K)"
echo '{"provider": "self-hosted", "check": "sh check.sh"}' > "$R/.github/ci.json"
"$CP" "$R" > "$T/out" 2>&1
grep -q 'runner laptop: online, labels self-hosted, macOS, ARM64, laptop' "$T/out"; check "$?" "0" "status of an self-hosted repo lists the runners"
rm "$R/.github/ci.json"
"$CP" "$R" --runner status > "$T/out" 2>&1; check "$?" "0" "--runner status"
grep -q 'status actions.runner.acme-demo.laptop: nested' "$T/out"; check "$?" "0" "…svc.sh's status from the runner Mac"
echo '{"total_count":0,"runners":[]}' > "$T/gh/runners.json"
"$CP" "$R" --runner remove > "$T/out" 2>&1; check "$?" "0" "--runner remove"
check "$(cat "$T/ssh/envtoken")" "remove" "…config.sh got the token in ACTIONS_RUNNER_INPUT_TOKEN"
check "$(test -e "$RD/.runner" && echo kept || echo gone)" "gone" "…and deregistered"
check "$(grep -c "$TOKEN" "$T/out")" "0" "…the token in none of its output"
check "$(grep -c "$TOKEN" "$T/ssh/argv")" "0" "…nor in ssh's argv"
check "$(grep -c "$TOKEN" "$T/ssh/stdin")" "1" "…it went on ssh's stdin"
: > "$T/gh/calls"
"$CP" "$R" --runner remove > "$T/out" 2>&1; check "$?" "0" "a second remove: nothing configured"
check "$(grep -c 'remove-token' "$T/gh/calls")" "0" "…and no remove token minted"
DIST="$T/ssh/home/actions-runners/.dist"; mkdir -p "$DIST"
dd if=/dev/zero of="$DIST/actions-runner-osx-arm64-2.338.0.tar.gz" bs=1 count=0 seek=128562863 2>/dev/null
"$CP" "$R" --runner install > "$T/out" 2>&1; check "$?" "2" "a tarball of the right size, wrong SHA-256: refused"
grep -q 'SHA-256 is not' "$T/out"; check "$?" "0" "…saying so"
check "$(test -e "$DIST/actions-runner-osx-arm64-2.338.0.tar.gz" && echo kept || echo removed)" "removed" "…and removed"
check "$(test -e "$T/ssh/curl" && echo fetched || echo none)" "none" "…with no download"
check "$(grep -c "$TOKEN" "$T/out")" "0" "…the registration token in none of its output"
"$CP" "$R" --runner install > "$T/out" 2>&1; check "$?" "2" "no tarball: fetched from the pinned URL (here it fails)"
check "$(cut -d' ' -f2- "$T/ssh/curl" | grep -c 'releases/download/v2.338.0/actions-runner-osx-arm64-2.338.0.tar.gz')" "1" "…that URL"

echo "the second review of 2026-10-19: a fresh install, end to end (K)"
# the pinned tarball swapped, in-process, for a small one holding the fake config.sh and svc.sh
R="$T/r2"; newrepo "$R"; rm -rf "$T/ssh/home/actions-runners/acme"; : > "$T/ssh/stdin"; rm -f "$T/ssh/envtoken"
fakerunner "$T/tarball" fresh; (cd "$T/tarball" && tar czf "$DIST/fake-runner.tar.gz" svc.sh config.sh)
echo '{"total_count":1,"runners":[{"id":8,"name":"laptop","status":"online","labels":[{"name":"self-hosted"},{"name":"macOS"},{"name":"laptop"}]}]}' > "$T/gh/runners.json"
: > "$T/gh/calls"
cat > "$T/fresh.py" <<'PY'
import hashlib, importlib.machinery, importlib.util, os, sys
loader = importlib.machinery.SourceFileLoader("cp", sys.argv[1])
spec = importlib.util.spec_from_loader("cp", loader); m = importlib.util.module_from_spec(spec); loader.exec_module(m)
tgz = sys.argv[3]
m.RUNNER_URL = "https://example.invalid/fake-runner.tar.gz"
m.RUNNER_SIZE = os.path.getsize(tgz)
m.RUNNER_SHA256 = hashlib.sha256(open(tgz, "rb").read()).hexdigest()
sys.exit(m.main([sys.argv[2], "--runner", "install"]))
PY
python3 "$T/fresh.py" "$CP" "$R" "$DIST/fake-runner.tar.gz" > "$T/out" 2>&1; check "$?" "0" "not configured: a fresh install"
check "$(grep -c 'registration-token' "$T/gh/calls")" "1" "…one registration token minted"
check "$(cat "$T/ssh/envtoken" 2>/dev/null)" "--unattended" "…handed to config.sh in ACTIONS_RUNNER_INPUT_TOKEN"
check "$(grep -c "$TOKEN" "$T/out")" "0" "…in none of its output"
check "$(test -f "$T/ssh/home/actions-runners/acme/demo/.runner" && echo nested || echo elsewhere)" "nested" "…into the nested directory"

echo "the second review of 2026-10-19: runners installed in the flat directory (J)"
FLAT="$T/ssh/home/actions-runners/acme-demo"; rm -rf "$T/ssh/home/actions-runners/acme"
fakerunner "$FLAT" flat
printf '\xef\xbb\xbf{"agentId": 3, "gitHubUrl": "https://github.com/acme/demo", "workFolder": "_work"}' > "$FLAT/.runner"
"$CP" "$R" --runner status > "$T/out" 2>&1; check "$?" "0" "--runner status, a runner installed flat before 2026-10-19"
grep -q 'status actions.runner.acme-demo.laptop: flat' "$T/out"; check "$?" "0" "…found in the flat directory"
R="$T/r3"; newrepo "$R"; git -C "$R" remote set-url origin https://github.com/a-b/c.git
fakerunner "$T/ssh/home/actions-runners/a-b-c" other
printf '{"gitHubUrl": "https://github.com/a/b-c"}' > "$T/ssh/home/actions-runners/a-b-c/.runner"
"$CP" "$R" --runner status > "$T/out" 2>&1
grep -q 'not configured: .*actions-runners/a-b/c' "$T/out"; check "$?" "0" "a-b/c is not a/b-c: another repo's flat a-b-c is not this one's"
grep -q 'status actions.runner' "$T/out"; check "$?" "1" "…its svc.sh never run"
echo '{"total_count":0,"runners":[]}' > "$T/gh/runners.json"

echo "bin/repos reads a CircleCI repo as CI"
git -C "$T/a" -c user.name=t -c user.email=t@t commit -qam circleci 2>/dev/null; git -C "$T/a" add -A; git -C "$T/a" -c user.name=t -c user.email=t@t commit -qm circleci
git -C "$T/a" update-ref refs/remotes/origin/main HEAD
check "$(python3 - "$B" "$T/a" <<'PY'
import importlib.machinery, importlib.util, sys
from pathlib import Path
loader = importlib.machinery.SourceFileLoader("repos", str(Path(sys.argv[1]) / "repos"))
spec = importlib.util.spec_from_loader("repos", loader); m = importlib.util.module_from_spec(spec); loader.exec_module(m)
print(m.ci_state(Path(sys.argv[2]), {}))
PY
)" "ci ok (circleci)" "ci_state: ci ok (circleci)"

commit() { git -C "$1" add -A && git -C "$1" -c user.name=t -c user.email=t@t commit -qm "$2"; }
echo '{"strict": false, "contexts": ["check"]}' > "$T/gh/rsc.json"; echo '{"statuses":[]}' > "$T/gh/status.json"

echo "the review of 2026-10-19: run from a subdirectory (1)"
R="$T/s1"; newrepo "$R"; mkdir -p "$R/sub/deeper"
(cd "$R/sub/deeper" && "$CP" --to circleci > "$T/out" 2>&1); check "$?" "0" "--to from a subdirectory, REPO defaulted"
check "$(find "$R/sub" -name '.circleci' -o -name '.github' | wc -l | tr -d ' ')" "0" "…writes nothing under the subdirectory"
check "$(test -e "$R/.github/workflows/check.yml" && echo kept || echo gone)" "gone" "…and switches the top level's check.yml"
check "$(test -e "$R/.circleci/parts/check.yml" && echo there || echo none)" "there" "…into the top level's .circleci"
mkdir -p "$R/other"; "$CP" "$R/other" > "$T/out" 2>&1; grep -q 'circleci (ci.json)' "$T/out"; check "$?" "0" "a subdirectory as REPO: its checkout's provider"
mkdir -p "$T/notgit"; "$CP" "$T/notgit" --to actions > "$T/out" 2>&1; check "$?" "2" "outside a git checkout: refused"

echo "the review of 2026-10-19: a switch to Actions and the draft skip (2)"
R="$T/s2"; newrepo "$R"; "$CP" "$R" --to circleci > /dev/null 2>&1; commit "$R" circleci
"$CP" "$R" --to actions > "$T/out" 2>&1; check "$?" "0" "circleci → actions"
grep -q 'gh pr ready' "$T/out"; check "$?" "0" "…it says the PR leaves draft before check reports"
echo '{"strict": false, "contexts": ["ci/circleci: check"]}' > "$T/gh/rsc.json"
echo '{"check_runs":[{"name":"check","status":"completed","conclusion":"skipped"}]}' > "$T/gh/checkruns.json"
"$CP" "$R" --protect > "$T/out" 2>&1; check "$?" "2" "--protect over a skipped check (a draft's head): refused"
grep -q 'gh pr ready' "$T/out"; check "$?" "0" "…naming the way out"
check "$(python3 -c "import json; print(json.load(open('$T/gh/rsc.json'))['contexts'])")" "['ci/circleci: check']" "…GitHub untouched"
echo '{"check_runs":[{"name":"check","status":"completed","conclusion":"success"}]}' > "$T/gh/checkruns.json"
"$CP" "$R" --protect > /dev/null 2>&1; check "$?" "0" "…and protects once the ready PR's run is green"
rm -f "$T/gh/checkruns.json"

echo "the review of 2026-10-19: app_id pins (3)"
R="$T/s3"; newrepo "$R"
echo '{"strict": true, "contexts": ["check", "lint"], "checks": [{"context": "check", "app_id": 15368}, {"context": "lint", "app_id": 42}]}' > "$T/gh/rsc.json"
"$CP" "$R" --to circleci > /dev/null 2>&1
echo '{"statuses":[{"context":"ci/circleci: check","state":"success"}]}' > "$T/gh/status.json"
"$CP" "$R" --protect > "$T/out" 2>&1; check "$?" "0" "--protect over pinned checks"
check "$(python3 -c "import json; d=json.load(open('$T/gh/patch.json')); print(sorted(d), d.get('checks'))")" \
      "['checks', 'strict'] [{'context': 'lint', 'app_id': 42}, {'context': 'ci/circleci: check'}]" "…the PATCH is checks: lint keeps app 42, the new one auto-selects"
grep -q "rollback: .*\"app_id\": 15368" "$T/out"; check "$?" "0" "…and the rollback restores the old pin"
R="$T/s3b"; newrepo "$R"
python3 -c "import json,sys; p=sys.argv[1]; d=json.load(open(p)); d['required_status_checks']={'strict': False, 'checks': [{'context': 'check', 'app_id': 15368}, {'context': 'lint', 'app_id': 42}]}; open(p,'w').write(json.dumps(d))" "$R/.github/main-protection.json"
"$CP" "$R" --to circleci > /dev/null 2>&1
check "$(python3 -c "import json; r=json.load(open('$R/.github/main-protection.json'))['required_status_checks']; print('contexts' in r, r.get('checks'))")" \
      "False [{'context': 'lint', 'app_id': 42}, {'context': 'ci/circleci: check'}]" "main-protection.json in checks form keeps its pins"
echo '{"strict": false, "contexts": ["check"]}' > "$T/gh/rsc.json"

echo "the review of 2026-10-19: an Actions expression in the command (4)"
R="$T/s4"; newrepo "$R"
sed 's/sh check\.sh$/sh check.sh --os ${{ runner.os }}/' "$R/.github/workflows/check.yml" > "$T/s4.yml" && mv "$T/s4.yml" "$R/.github/workflows/check.yml"
"$CP" "$R" --to actions --dry-run > "$T/out" 2>&1; check "$?" "0" "a run: with \${{ }} is the check"
grep -qF '(check: sh check.sh --os ${{ runner.os }})' "$T/out"; check "$?" "0" "…read as is"
R="$T/s4b"; newrepo "$R"; cp "$TPL/.github/workflows/check.yml" "$R/.github/workflows/check.yml"
printf '# x\n\n- check: `make test`\n' > "$R/AGENTS.md"
"$CP" "$R" --to actions --dry-run > "$T/out" 2>&1
grep -qF '(check: make test)' "$T/out"; check "$?" "0" "the bare {{COMMAND}} placeholder is still skipped for AGENTS.md's"

echo "the review of 2026-10-19: name after the key, a leading --- (6)"
R="$T/s6"; newrepo "$R"; "$CP" "$R" --to circleci > /dev/null 2>&1
python3 - "$R/.circleci/parts/check.yml" <<'PY'
import sys; p=sys.argv[1]; t=open(p).read()
old = "      - run:\n          name: check\n          command: |\n            sh check.sh\n"
assert old in t
t = t.replace(old, "      - run:\n          name: deps\n          command: |\n            pip install x\n"
                   "      - run:\n          command: |\n            sh check.sh\n          name: check\n", 1)
open(p, "w").write(t)
PY
"$CP" "$R" --to actions --force --dry-run > "$T/out" 2>&1; check "$?" "0" "CircleCI: name: check after command: is the check"
grep -qF '(check: sh check.sh)' "$T/out"; check "$?" "0" "…its command read"
R="$T/s6a"; newrepo "$R"
python3 - "$R/.github/workflows/check.yml" <<'PY'
import sys; p=sys.argv[1]; t=open(p).read()
old = "      - name: check\n        run: |\n          sh check.sh\n"
assert old in t
t = t.replace(old, "      - run: |\n          git config --global user.name ci\n"
                   "      - run: |\n          sh check.sh\n        name: check\n", 1)
open(p, "w").write(t)
PY
"$CP" "$R" --to circleci --force --dry-run > "$T/out" 2>&1; check "$?" "0" "Actions: name: check after run: is the check"
grep -qF '(check: sh check.sh)' "$T/out"; check "$?" "0" "…its command read"
R="$T/s6b"; newrepo "$R"; mkdir -p "$R/.circleci"
printf -- '---\nversion: 2.1\njobs:\n  port:\n    docker:\n      - image: x\n    steps: [checkout]\nworkflows:\n  w:\n    jobs: [port]\n' > "$R/.circleci/config.yml"
"$CP" "$R" --to circleci > "$T/out" 2>&1; check "$?" "0" "a config.yml starting with --- is adopted"
check "$(yamlok "$R/.circleci/config.yml")" "check,port|check,w" "…and composes"
R="$T/s6c"; newrepo "$R"; mkdir -p "$R/.circleci"
printf 'version: 2.1\nsetup: true\njobs:\n  port:\n    docker:\n      - image: x\nworkflows:\n  w:\n    jobs: [port]\n' > "$R/.circleci/config.yml"
"$CP" "$R" --to circleci > "$T/out" 2>&1; check "$?" "2" "an adopted config compose cannot take: refused"
grep -q '\.circleci/config\.yml' "$T/out"; check "$?" "0" "…naming the file that exists, config.yml"

echo "the review of 2026-10-19: one definition of the provider, here and in bin/repos (5)"
cistate() { python3 - "$B" "$1" <<'PY'
import importlib.machinery, importlib.util, sys
from pathlib import Path
loader = importlib.machinery.SourceFileLoader("repos", str(Path(sys.argv[1]) / "repos"))
spec = importlib.util.spec_from_loader("repos", loader); m = importlib.util.module_from_spec(spec); loader.exec_module(m)
print(m.ci_state(Path(sys.argv[2]), {}))
PY
}
R="$T/s5"; newrepo "$R"; "$CP" "$R" --to circleci > /dev/null 2>&1; rm "$R/.github/ci.json"
commit "$R" "circleci, no ci.json"; git -C "$R" update-ref refs/remotes/origin/main HEAD
"$CP" "$R" > "$T/out" 2>&1; grep -q 'circleci (inferred' "$T/out"; check "$?" "0" "parts/check.yml without ci.json: ci-provider infers circleci"
check "$(cistate "$R")" "ci ok (circleci)" "…and bin/repos agrees"
R="$T/s5b"; newrepo "$R"; touch "$R/.github/workflows/automerge.yml"
echo '{"provider": "circleci", "check": "sh check.sh"}' > "$R/.github/ci.json"
commit "$R" "ci.json says circleci, no config"; git -C "$R" update-ref refs/remotes/origin/main HEAD
"$CP" "$R" > "$T/out" 2>&1; grep -q 'circleci (ci.json)' "$T/out"; check "$?" "0" "ci.json circleci beside check.yml: ci-provider says circleci"
check "$(cistate "$R")" "ci ok" "…but check.yml is on main, so bin/repos reads it as the Actions CI that runs (second review, N)"

echo "the review of 2026-10-19: replaces, spent once on main (7)"
echo '{"strict": false, "contexts": ["check"]}' > "$T/gh/rsc.json"
R="$T/s7"; newrepo "$R"
"$CP" "$R" --to circleci --context X > /dev/null 2>&1; "$CP" "$R" --to circleci --context Y > /dev/null 2>&1
check "$(python3 -c "import json; print(json.load(open('$R/.github/ci.json')).get('replaces'))")" "['X']" "on the branch: X recorded"
commit "$R" "context Y"; git -C "$R" checkout -q main; git -C "$R" merge -q --ff-only claude/test/2026-10-18-ci
git -C "$R" checkout -q -b claude/test/2026-10-19-next
echo '{"strict": false, "contexts": ["Y", "X"]}' > "$T/gh/rsc.json"   # X: since reused by another job
echo '{"statuses":[{"context":"Y","state":"success"}]}' > "$T/gh/status.json"
"$CP" "$R" --protect > "$T/out" 2>&1; check "$?" "0" "--protect on a later branch"
check "$(python3 -c "import json; print(json.load(open('$T/gh/rsc.json'))['contexts'])")" "['Y', 'X']" "…keeps X, spent when the switch landed"
"$CP" "$R" --to circleci --context Z > /dev/null 2>&1
check "$(python3 -c "import json; print(json.load(open('$R/.github/ci.json')).get('replaces'))")" "['Y']" "a later switch: replaces holds Y, not the spent X"
echo '{"strict": false, "contexts": ["check"]}' > "$T/gh/rsc.json"; echo '{"statuses":[]}' > "$T/gh/status.json"

echo "the second review of 2026-10-19: who can run code on the runner Mac (A, B)"
R="$T/u1"; newrepo "$R"; touch "$R/.github/workflows/automerge.yml"
"$CP" "$R" --to self-hosted > "$T/out" 2>&1; check "$?" "0" "--to self-hosted"
grep -q 'write collaborators.*: alice, bob$' "$T/out"; check "$?" "0" "…names the write collaborators, push or above, as a warning"
grep -q 'carol' "$T/out"; check "$?" "1" "…not a read-only one"
grep -qi 'studio lacks' "$T/out"; check "$?" "1" "automerge's reason no longer names the old runner Mac's missing gh (B)"
grep -q 'automerge.yml stays on ubuntu-latest.*authenticated' "$T/out"; check "$?" "0" "…it is: no runner-Mac job with a gh it does not need"
grep -q 'write collaborators.*runner Mac as ci, with' "$T/out"; check "$?" "0" "…the user key named in the warning"
check "$(grep -c 'Any write collaborator' "$R/.github/workflows/check.yml")" "1" "check.yml's comment states the trust boundary"
check "$(grep -c 'any write collaborator can run code there' "$TPL/.github/workflows/check.yml")" "1" "…and so does the template's"
"$CP" "$R" --runner install --dry-run > "$T/out" 2>&1
grep -q 'write collaborators.*: alice, bob$' "$T/out"; check "$?" "0" "--runner install names them too"

echo "the second review of 2026-10-19: fork PRs' workflows on a private repo (C)"
R="$T/u2"; newrepo "$R"; rm -f "$T/ssh/argv"; : > "$T/gh/calls"
echo true > "$T/gh/forkpr"
"$CP" "$R" --to self-hosted > "$T/out" 2>&1; check "$?" "2" "--to self-hosted on a repo that runs fork PRs' workflows: refused"
grep -q 'fork' "$T/out"; check "$?" "0" "…saying why"
check "$(shasum < "$R/.github/workflows/check.yml")" "$(shasum < "$T/p.ubuntu.yml")" "…check.yml untouched"
"$CP" "$R" --runner install > "$T/out" 2>&1; check "$?" "2" "--runner install there: refused"
check "$(test -e "$T/ssh/argv" && echo ssh || echo none)" "none" "…no ssh"
check "$(grep -c token "$T/gh/calls")" "0" "…no token asked for"
echo fail > "$T/gh/forkpr"
"$CP" "$R" --to self-hosted > /dev/null 2>&1; check "$?" "2" "the setting unread: refused, not guessed"
echo '{"provider": "self-hosted", "check": "sh check.sh"}' > "$R/.github/ci.json"
echo true > "$T/gh/forkpr"
"$CP" "$R" > "$T/out" 2>&1; grep -q '⚠.*fork' "$T/out"; check "$?" "0" "status warns when a repo on self-hosted runs fork PRs' workflows"
echo false > "$T/gh/private"
"$CP" "$R" > "$T/out" 2>&1; grep -q '⚠.*is public' "$T/out"; check "$?" "0" "…and when it is public"
echo true > "$T/gh/private"; rm -f "$T/gh/forkpr"

echo "the second review of 2026-10-19: a hand-written matrix keeps its names (E)"
R="$T/u3"; newrepo "$R"
python3 - "$R/.github/workflows/check.yml" "$R/.github/main-protection.json" <<'PY'
import json, sys
p = sys.argv[1]; t = open(p).read()
t = t.replace("    runs-on: ubuntu-latest\n", "    strategy:\n      matrix:\n        os: [macos-latest, macos-15]\n    runs-on: ${{ matrix.os }}\n", 1)
open(p, "w").write(t)
q = sys.argv[2]; d = json.load(open(q)); d["required_status_checks"]["contexts"] = ["check (macos-latest)", "check (macos-15)", "lint"]
open(q, "w").write(json.dumps(d))
PY
echo '{"provider": "actions", "check": "sh check.sh", "context": "check (macos-15)"}' > "$R/.github/ci.json"
echo '{"strict": false, "contexts": ["check (macos-latest)", "check (macos-15)", "lint"]}' > "$T/gh/rsc.json"
echo '{"statuses":[{"context":"check (macos-15)","state":"success"}]}' > "$T/gh/status.json"
"$CP" "$R" > "$T/out" 2>&1; grep -q 'protection differs' "$T/out"; check "$?" "1" "status: a matrix on disk reporting its names is no difference"
"$CP" "$R" --protect --force > "$T/out" 2>&1; check "$?" "0" "--protect --force there"
check "$(python3 -c "import json; print(json.load(open('$T/gh/rsc.json'))['contexts'])")" "['check (macos-latest)', 'check (macos-15)', 'lint']" "…leaves the matrix's names required"
"$CP" "$R" --to self-hosted --force > "$T/out" 2>&1; check "$?" "0" "a switch to self-hosted (--force: one job)"
check "$(python3 -c "import json; print(json.load(open('$R/.github/ci.json')).get('context'))")" "None" "…the matrix name in ci.json's context is not carried into the one-job file"
check "$(ctx "$R/.github/main-protection.json")" "['lint', 'check']" "…main-protection.json requires check"
check "$(python3 -c "import json; print('check (macos-15)' in json.load(open('$R/.github/ci.json')).get('replaces', []))")" "True" "…and --protect will swap the old name out"
echo '{"strict": false, "contexts": ["check"]}' > "$T/gh/rsc.json"; echo '{"statuses":[]}' > "$T/gh/status.json"

echo "the second review of 2026-10-19: block scalar headers (F)"
for hdr in '|-' '|+' '|2' '| # the check' '>' '>-'; do
  R="$T/u4"; rm -rf "$R"; newrepo "$R"
  python3 - "$R/.github/workflows/check.yml" "$hdr" <<'PY'
import sys; p, h = sys.argv[1], sys.argv[2]; t = open(p).read()
old = "        run: |\n          sh check.sh\n"
assert old in t
open(p, "w").write(t.replace(old, "        run: %s\n          sh check.sh\n          --fast\n" % h, 1))
PY
  case "$hdr" in '>'*) want='sh check.sh --fast' ;; *) want='sh check.sh; --fast' ;; esac
  "$CP" "$R" --to circleci --dry-run --force > "$T/out" 2>&1
  grep -qF "(check: $want)" "$T/out"; check "$?" "0" "run: $hdr is a block: $want"
done

echo "the second review of 2026-10-19: protection compared as a set (G)"
R="$T/u5"; newrepo "$R"
python3 -c "import json,sys; p=sys.argv[1]; d=json.load(open(p)); d['required_status_checks']['contexts']=['check','lint']; open(p,'w').write(json.dumps(d, indent=2)+'\n')" "$R/.github/main-protection.json"
cp "$R/.github/main-protection.json" "$T/u5.prot"
"$CP" "$R" --to self-hosted > "$T/out" 2>&1; check "$?" "0" "actions → self-hosted with check before lint"
check "$(shasum < "$R/.github/main-protection.json")" "$(shasum < "$T/u5.prot")" "…main-protection.json not rewritten for an order"
grep -q 'no --protect' "$T/out"; check "$?" "0" "…and the next step says no --protect"

echo "the second review of 2026-10-19: several check runs of one name (H)"
R="$T/u6"; newrepo "$R"; "$CP" "$R" --to circleci > /dev/null 2>&1; commit "$R" circleci
"$CP" "$R" --to actions > /dev/null 2>&1
echo '{"strict": false, "contexts": ["ci/circleci: check"]}' > "$T/gh/rsc.json"
echo '{"check_runs":[{"name":"check","status":"completed","conclusion":"skipped","completed_at":"2026-10-19T10:00:00Z"},{"name":"check","status":"completed","conclusion":"success","completed_at":"2026-10-19T09:00:00Z"}]}' > "$T/gh/checkruns.json"
"$CP" "$R" --protect > "$T/out" 2>&1; check "$?" "0" "skipped listed before success (5ad09a8adb's shape): the success counts"
echo '{"check_runs":[{"name":"check","status":"completed","conclusion":"failure","completed_at":"2026-10-19T09:00:00Z"},{"name":"check","status":"completed","conclusion":"cancelled","completed_at":"2026-10-19T10:00:00Z"},{"name":"check","status":"in_progress","conclusion":null}]}' > "$T/gh/checkruns.json"
"$CP" "$R" > "$T/out" 2>&1; grep -q 'reported on HEAD: check=cancelled' "$T/out"; check "$?" "0" "no success: the newest completed run"
rm -f "$T/gh/checkruns.json"; echo '{"strict": false, "contexts": ["check"]}' > "$T/gh/rsc.json"

echo "the second review of 2026-10-19: a malformed ci.json (I)"
R="$T/u7"; newrepo "$R"; echo '{"provider": "actions",' > "$R/.github/ci.json"
"$CP" "$R" --to self-hosted > "$T/out" 2>&1; check "$?" "2" "--to over a malformed ci.json: a refusal"
grep -q 'Traceback' "$T/out"; check "$?" "1" "…not a traceback"
grep -q 'ci.json' "$T/out"; check "$?" "0" "…naming the file"

echo "the second review of 2026-10-19: a broken self-hosted render gates only self-hosted (L)"
R="$T/u8"; newrepo "$R"
sed 's/runs-on: ubuntu-latest/runs-on: macos-latest/' "$TPL/.github/workflows/check.yml" > "$T/u8.tmpl"
sed 's/{{COMMAND}}/sh check.sh/' "$T/u8.tmpl" > "$R/.github/workflows/check.yml"
cat > "$T/u8.py" <<'PY'
import importlib.machinery, importlib.util, sys
loader = importlib.machinery.SourceFileLoader("cp", sys.argv[1])
spec = importlib.util.spec_from_loader("cp", loader); m = importlib.util.module_from_spec(spec); loader.exec_module(m)
m.ACTIONS_TEMPLATE = sys.argv[2]
sys.exit(m.main(sys.argv[3:]))
PY
python3 "$T/u8.py" "$CP" "$T/u8.tmpl" "$R" --to actions --dry-run > "$T/out" 2>&1; check "$?" "0" "a template with no ubuntu runs-on: --to actions still works"
python3 "$T/u8.py" "$CP" "$T/u8.tmpl" "$R" --to circleci --dry-run > "$T/out" 2>&1; check "$?" "0" "…and --to circleci"
python3 "$T/u8.py" "$CP" "$T/u8.tmpl" "$R" --to self-hosted --dry-run > "$T/out" 2>&1; check "$?" "2" "…only --to self-hosted refuses it"

echo "the second review of 2026-10-19: bin/repos ci_state (D, N, M)"
cat > "$T/cistate.py" <<'PY'
import importlib.machinery, importlib.util, sys
from pathlib import Path
loader = importlib.machinery.SourceFileLoader("repos", str(Path(sys.argv[1]) / "repos"))
spec = importlib.util.spec_from_loader("repos", loader); m = importlib.util.module_from_spec(spec); loader.exec_module(m)
mode = sys.argv[3] if len(sys.argv) > 3 else ""
if mode.startswith("peer="):   # repos loads its sibling bin/ci-provider from CI_PROVIDER: the seam patched here
    m.CI_PROVIDER = Path(mode[5:]) / "bin" / "ci-provider"
if mode == "notool":   # common.tool() finds nothing: repos never asks it for its own sibling (review 2026-10-21, 13)
    m.common.tool = lambda name: None
if mode == "count":
    real, n = m.git, []
    def counting(repo, *args):
        n.append(args)
        return real(repo, *args)
    m.git = counting
    m.ci_state(Path(sys.argv[2]), {})
    print(sum(1 for a in n if a == ("show", "origin/main:.github/workflows/check.yml")))
elif mode == "doc":
    import re
    src = Path(m.__file__).read_text()   # bin/repos is a source shim since B6: its __file__ is the module's copy
    body = src[src.index("def ci_state"):src.index("\ndef ", src.index("def ci_state") + 1)]
    outs = set(re.findall(r'return f?"((?:ci|NO CI)[^"{]*)', body))
    print(sorted(o.rstrip(" (") for o in outs if o.rstrip(" (") not in m.__doc__))
else:
    print(m.ci_state(Path(sys.argv[2]), {}))
PY
R="$T/s5"   # circleci on origin/main, no check.yml there
mkdir -p "$T/absent/bin"
check "$(python3 "$T/cistate.py" "$B" "$R" "peer=$T/absent")" "ci: ci-provider unloadable (FileNotFoundError: [Errno 2] No such file or directory: '$T/absent/bin/ci-provider')" "ci-provider missing: a line, not a crash (D, 13)"
mkdir -p "$T/raising/bin"; echo 'raise RuntimeError("boom")' > "$T/raising/bin/ci-provider"
check "$(python3 "$T/cistate.py" "$B" "$R" "peer=$T/raising")" "ci: ci-provider unloadable (RuntimeError: boom)" "ci-provider raising on load: the same (D, 13)"
check "$(python3 "$T/cistate.py" "$B" "$R" notool)" "ci ok (circleci)" "common.tool() finding nothing: repos still loads its sibling, never a silent Actions (13)"
R="$T/u9"; newrepo "$R"; git -C "$R" update-ref refs/remotes/origin/main main
check "$(python3 "$T/cistate.py" "$B" "$R" count)" "1" "check.yml read once per repo (D)"
R="$T/u10"; newrepo "$R"
echo '{"provider": "circleci", "check": "sh check.sh"}' > "$R/.github/ci.json"; commit "$R" "ci.json says circleci"
git -C "$R" update-ref refs/remotes/origin/main HEAD
check "$(python3 "$T/cistate.py" "$B" "$R")" "ci lacks automerge.yml" "ci.json circleci, check.yml on main: Actions runs it, read as Actions CI (N)"
git -C "$R" rm -q .github/workflows/check.yml; commit "$R" "no check.yml"; git -C "$R" update-ref refs/remotes/origin/main HEAD
check "$(python3 "$T/cistate.py" "$B" "$R")" "NO CI (circleci, no .circleci/config.yml)" "…nothing runs: NO CI (N)"
check "$(python3 "$T/cistate.py" "$B" "$R" doc)" "[]" "bin/repos' docstring names every ci_state output (M)"
check "$(grep -c '"actions"|"self-hosted"|"circleci"' "$CP")" "1" "ci-provider's header gives ci.json's three providers (M)"

echo "the move to wharf: the runner Mac's keys, absent (2026-10-20)"
mkdir -p "$T/aside"; mv "$REGATTA_CONFIG/wharf/"* "$T/aside/"
R="$T/v1"; newrepo "$R"; cp "$R/.github/workflows/check.yml" "$T/v1.ubuntu.yml"; : > "$T/gh/calls"; rm -f "$T/ssh/argv"
"$CP" "$R" --to self-hosted > "$T/out" 2>&1; check "$?" "2" "--to self-hosted with no labels key: refused"
grep -q "ci-runner-labels" "$T/out"; check "$?" "0" "…naming the file to write"
grep -q 'Traceback' "$T/out"; check "$?" "1" "…not a traceback"
check "$(shasum < "$R/.github/workflows/check.yml")" "$(shasum < "$T/v1.ubuntu.yml")" "…check.yml untouched"
check "$(wc -l < "$T/gh/calls" | tr -d ' ')" "0" "…GitHub not asked"
"$CP" "$R" --runner status > "$T/out" 2>&1; check "$?" "2" "--runner status with no keys: refused"
grep -q "ci-runner-ssh\|ci-runner-labels" "$T/out"; check "$?" "0" "…naming a file to write"
"$CP" "$R" --runner install > /dev/null 2>&1; check "$?" "2" "--runner install: refused"
"$CP" "$R" --runner remove > /dev/null 2>&1; check "$?" "2" "--runner remove: refused"
check "$(test -e "$T/ssh/argv" && echo ssh || echo none)" "none" "…no ssh"
"$CP" "$R" --to circleci > /dev/null 2>&1; check "$?" "0" "--to circleci needs no runner key"
"$CP" "$R" --to actions > /dev/null 2>&1; check "$?" "0" "…nor --to actions"
"$CP" "$R" > /dev/null 2>&1; check "$?" "0" "…nor status"
cp "$T/aside/ci-runner-labels" "$REGATTA_CONFIG/wharf/"
"$CP" "$R" --to self-hosted > "$T/out" 2>&1; check "$?" "0" "labels without the user key: --to self-hosted works"
grep -q 'runner Mac as the runner.s user' "$T/out"; check "$?" "0" "…the user left unnamed"
printf 'self-hosted\nmacOS\n' > "$REGATTA_CONFIG/wharf/ci-runner-labels"
"$CP" "$R" --to self-hosted > "$T/out" 2>&1; check "$?" "2" "labels with none of the Mac's own: refused"
mv "$T/aside/"* "$REGATTA_CONFIG/wharf/"

echo "the move to wharf: what the published file names, and files from before the move"
R="$T/v2"; newrepo "$R"; grep '^ *#' "$R/.github/workflows/check.yml" > "$T/v2.before"
"$CP" "$R" --to self-hosted > /dev/null 2>&1
check "$(grep '^ *#' "$R/.github/workflows/check.yml" | grep -vxF -f "$T/v2.before" | grep -ci 'laptop\|ci-runner\| as ci\b')" "0" "the comment it adds to check.yml names no machine or user: only runs-on does"
python3 - "$R/.github/workflows/check.yml" <<'PY'
import sys; p=sys.argv[1]; t=open(p).read()
open(p,"w").write(t.replace("runs-on: [self-hosted, macOS]", "runs-on: [self-hosted, macOS, othermac]", 1))
PY
"$CP" "$R" > "$T/out" 2>&1; grep -q 'self-hosted (ci.json)' "$T/out"; check "$?" "0" "a file on another Mac's labels is still self-hosted"
grep -q 'no online runner labelled self-hosted, macOS, othermac' "$T/out"; check "$?" "0" "…and status asks for the file's labels, not the key's"
"$CP" "$R" --to self-hosted > /dev/null 2>&1; check "$?" "2" "…but not this config's form: a re-run holds it as a hand edit (review 2026-10-21, 4)"
"$CP" "$R" --to self-hosted --force > /dev/null 2>&1; check "$?" "0" "…--force takes it"
check "$(grep -c 'runs-on: \[self-hosted, macOS\]' "$R/.github/workflows/check.yml")" "1" "…and writes what the repo needs"
rm "$R/.github/ci.json"
"$CP" "$R" > "$T/out" 2>&1; grep -q 'self-hosted (inferred' "$T/out"; check "$?" "0" "this config's literal form, no ci.json: self-hosted inferred"
sed 's/runs-on: \[self-hosted, macOS\]/runs-on: [self-hosted, macOS, oldmac]/' "$R/.github/workflows/check.yml" > "$T/v2.yml" && mv "$T/v2.yml" "$R/.github/workflows/check.yml"
"$CP" "$R" > "$T/out" 2>&1; grep -q 'actions (inferred' "$T/out"; check "$?" "0" "another Mac's labels, no ci.json: not this config's runner, read as actions (review 2026-10-21, 5)"
R="$T/v3"; newrepo "$R"; "$CP" "$R" --to circleci > /dev/null 2>&1
python3 - "$R/.circleci/config.yml" <<'PY'
import sys; p=sys.argv[1]; t=open(p).read()
open(p,"w").write(t.replace("# GENERATED by wharf's ci-provider", "# GENERATED by _overlay bin/ci-provider", 1))
PY
"$CP" "$R" --compose > "$T/out" 2>&1; check "$?" "0" "a config.yml composed before the move reads as generated"
check "$(head -1 "$R/.circleci/config.yml" | cut -c1-34)" "# GENERATED by wharf's ci-provider" "…recomposed under the new marker"

echo "the variable form: runs-on from a repository variable (regatta#53's), 2026-10-20"
echo '{"strict": false, "contexts": ["check"]}' > "$T/gh/rsc.json"; rm -rf "$T/gh/vars"
VARLINE="runs-on: \${{ fromJSON(vars.CI_RUNS_ON || '\"ubuntu-latest\"') }}"
R="$T/w1"; newrepo "$R"; mkdir -p "$R/.helloworld"; cp "$R/.github/workflows/check.yml" "$T/w1.ubuntu.yml"
"$CP" "$R" --to self-hosted > "$T/out" 2>&1; check "$?" "0" "a repo with a public twin (.helloworld/): --to self-hosted"
check "$(grep -cxF "    $VARLINE" "$R/.github/workflows/check.yml")" "1" "…runs-on reads CI_RUNS_ON, ubuntu-latest where unset"
check "$(diff "$T/w1.ubuntu.yml" "$R/.github/workflows/check.yml" | grep '^>' | grep -ci 'laptop\|\[self-hosted\|"self-hosted"')" "0" "…and nothing it writes names the machine or its labels"
check "$(yamlread "$R/.github/workflows/check.yml" 'd["jobs"]["check"]["runs-on"]')" \
      "\${{ fromJSON(vars.CI_RUNS_ON || '\"ubuntu-latest\"') }}" "…a YAML string Actions evaluates"
grep -q 'sets CI_RUNS_ON to \["self-hosted","macOS","laptop"\]' "$T/out"; check "$?" "0" "…the next step names the variable and its value"
grep -q 'runs on ubuntu-latest, hosted' "$T/out"; check "$?" "0" "…and says the check runs hosted until then"
"$CP" "$R" --to self-hosted > /dev/null 2>&1; check "$?" "0" "a re-run: the variable form is no extra"
rm -rf "$R/.helloworld"
"$CP" "$R" --to self-hosted > /dev/null 2>&1
check "$(grep -cxF "    $VARLINE" "$R/.github/workflows/check.yml")" "1" "…and keeps the form without .helloworld/, read from check.yml"
rm "$R/.github/ci.json"; "$CP" "$R" > "$T/out" 2>&1
grep -q 'self-hosted (inferred' "$T/out"; check "$?" "0" "without ci.json, the variable form is inferred self-hosted"
"$CP" "$R" --to actions > /dev/null 2>&1; check "$?" "0" "variable form → actions"
check "$(shasum < "$R/.github/workflows/check.yml")" "$(shasum < "$T/w1.ubuntu.yml")" "…the ubuntu file back, byte for byte"
R="$T/w2"; newrepo "$R"
"$CP" "$R" --to self-hosted --runs-on-var MAC_LABELS > /dev/null 2>&1; check "$?" "0" "--runs-on-var NAME on a private-only repo"
check "$(grep -c 'vars.MAC_LABELS ||' "$R/.github/workflows/check.yml")" "1" "…reads that variable"
R="$T/w3"; newrepo "$R"
"$CP" "$R" --to self-hosted --runs-on-var 'GITHUB_X' > "$T/out" 2>&1; check "$?" "2" "a GITHUB_ variable name: refused"
"$CP" "$R" --to self-hosted --runs-on-var '9x' > /dev/null 2>&1; check "$?" "2" "…and one starting with a digit"
"$CP" "$R" --to actions --runs-on-var X > /dev/null 2>&1; check "$?" "2" "--runs-on-var without --to self-hosted: an error"
"$CP" "$R" --to self-hosted > /dev/null 2>&1
check "$(grep -c 'runs-on: \[self-hosted, macOS\]' "$R/.github/workflows/check.yml")" "1" "no twin, no flag: the literal labels, as before"

echo "the variable form: status and the runner (fake gh, fake ssh)"
R="$T/w4"; newrepo "$R"; mkdir -p "$R/.helloworld"; "$CP" "$R" --to self-hosted > /dev/null 2>&1
echo '{"total_count":1,"runners":[{"id":9,"name":"laptop","status":"online","labels":[{"name":"self-hosted"},{"name":"macOS"},{"name":"laptop"}]}]}' > "$T/gh/runners.json"
"$CP" "$R" > "$T/out" 2>&1; grep -q 'runs-on variable CI_RUNS_ON is unset' "$T/out"; check "$?" "0" "status: the variable unset, said"
: > "$T/gh/calls"
"$CP" "$R" --runner install --dry-run > "$T/out" 2>&1; check "$?" "0" "--runner install --dry-run"
grep -q 'would create variable CI_RUNS_ON: None → \["self-hosted","macOS","laptop"\]' "$T/out"; check "$?" "0" "…says it would create the variable"
check "$(grep -c -- '-X POST\|-X PATCH' "$T/gh/calls")" "0" "…and writes nothing"
"$CP" "$R" --runner install > "$T/out" 2>&1; check "$?" "0" "--runner install"
check "$(python3 -c "import json; d=json.load(open('$T/gh/vars/CI_RUNS_ON.json')); print(d['name'], d['value'])")" 'CI_RUNS_ON ["self-hosted","macOS","laptop"]' "…POSTs the variable: the labels key's labels"
grep -q 'variable CI_RUNS_ON: \["self-hosted","macOS","laptop"\] (read back)' "$T/out"; check "$?" "0" "…and reads it back"
check "$(grep -n 'runner laptop online\|variable CI_RUNS_ON:' "$T/out" | cut -d: -f2 | tr '\n' '|')" "  GitHub|  variable CI_RUNS_ON|" "…only once the runner is online"
: > "$T/gh/calls"; "$CP" "$R" --runner install > "$T/out" 2>&1
grep -q 'variable CI_RUNS_ON already' "$T/out"; check "$?" "0" "a second install: the variable already right"
check "$(grep -c -- '-X POST repos/acme/demo/actions/variables\|-X PATCH' "$T/gh/calls")" "0" "…nothing written"
echo '{"name":"CI_RUNS_ON","value":"[\"self-hosted\",\"macOS\",\"othermac\"]"}' > "$T/gh/vars/CI_RUNS_ON.json"
"$CP" "$R" > "$T/out" 2>&1
grep -q 'runs-on variable CI_RUNS_ON: \["self-hosted","macOS","othermac"\]' "$T/out"; check "$?" "0" "status reads the variable"
grep -q 'no online runner labelled self-hosted, macOS, othermac' "$T/out"; check "$?" "0" "…and asks the runners for its labels"
"$CP" "$R" --runner install > "$T/out" 2>&1; check "$?" "0" "a variable holding other labels"
check "$(grep -c -- '-X PATCH repos/acme/demo/actions/variables/CI_RUNS_ON' "$T/gh/calls")" "1" "…is PATCHed"
grep -q 'rollback: gh api -X PATCH repos/acme/demo/actions/variables/CI_RUNS_ON' "$T/out"; check "$?" "0" "…and the PATCH that undoes it printed"
"$CP" "$R" > "$T/out" 2>&1; grep -q 'no online runner labelled' "$T/out"; check "$?" "1" "status: the variable's labels online, no warning"
echo '{"total_count":0,"runners":[]}' > "$T/gh/runners.json"; : > "$T/gh/calls"
"$CP" "$R" --runner remove > "$T/out" 2>&1; check "$?" "0" "--runner remove"
grep -q 'gh api -X DELETE repos/acme/demo/actions/variables/CI_RUNS_ON' "$T/out"; check "$?" "0" "…prints the variable's DELETE"
check "$(grep -c -- '-X DELETE' "$T/gh/calls")" "0" "…and never runs it"
check "$(test -e "$T/gh/vars/CI_RUNS_ON.json" && echo kept || echo gone)" "kept" "…the variable kept"
R="$T/w5"; newrepo "$R"; "$CP" "$R" --to self-hosted > /dev/null 2>&1; : > "$T/gh/calls"
"$CP" "$R" --runner install --dry-run > /dev/null 2>&1
check "$(grep -c 'actions/variables' "$T/gh/calls")" "0" "the literal form: no variable read or written"
rm -rf "$T/gh/vars"

echo "a fleet: another runner Mac by --host, an Intel one, a further instance (2026-10-27)"
RH="$T/ssh/home"  # the fake runner Mac's home: one name, so no line reads as a machine path
R="$T/w6"; newrepo "$R"; mkdir -p "$R/.helloworld"; "$CP" "$R" --to self-hosted > /dev/null 2>&1
rm -rf "$T/ssh/home/actions-runners/acme" "$DIST"/actions-runner-osx-*; : > "$T/ssh/argv"; : > "$T/ssh/curl"
mkdir -p "$T/gh/vars"; echo '{"name":"CI_RUNS_ON","value":"[\"self-hosted\",\"macOS\",\"laptop\"]"}' > "$T/gh/vars/CI_RUNS_ON.json"
LAPTOP='{"id":9,"name":"laptop","status":"online","labels":[{"name":"self-hosted"},{"name":"macOS"},{"name":"laptop"}]}'
OLDMAC='{"id":10,"name":"oldmac","status":"online","labels":[{"name":"self-hosted"},{"name":"macOS"},{"name":"X64"},{"name":"fleet"}]}'
echo "{\"total_count\":2,\"runners\":[$LAPTOP,$OLDMAC]}" > "$T/gh/runners.json"
FLEET="--host old-ci --name oldmac --labels self-hosted,macOS,fleet"
FAKE_ARCH=x86_64 "$CP" "$R" --runner install $FLEET > "$T/out" 2>&1; check "$?" "2" "an Intel Mac, not configured, no tarball: fetched (here it fails)"
grep -q 'on the runner Mac as the runner.s user,' "$T/out"; check "$?" "0" "…the trust warning never names the key's user for another Mac"
"$CP" "$R" --runner install --dry-run --host ci@old-ci --name oldmac --labels self-hosted,macOS,fleet > "$T/out" 2>&1
grep -q 'on the runner Mac as ci,' "$T/out"; check "$?" "0" "…and names the user --host logs in as"
check "$(grep -c 'releases/download/v2.338.0/actions-runner-osx-x64-2.338.0.tar.gz' "$T/ssh/curl")" "1" "…the pinned osx-x64 build"
check "$(grep -cx 'old-ci' "$T/ssh/argv")" "2" "…over ssh to --host, probe and install"
check "$(grep -c "oldmac fleet\$" "$T/ssh/argv")" "2" "…each call naming --name and --labels' own"
: > "$T/ssh/curl"; FAKE_ARCH=ppc "$CP" "$R" --runner install $FLEET > "$T/out" 2>&1; check "$?" "2" "an architecture with no pinned build: refused"
grep -q "no runner build is pinned for it" "$T/out"; check "$?" "0" "…saying so"
check "$(wc -l < "$T/ssh/curl" | tr -d ' ')" "0" "…before any download"
fakerunner "$RH/actions-runners/acme/demo" fleet; touch "$RH/actions-runners/acme/demo/.runner"
: > "$T/gh/calls"; FAKE_ARCH=ppc "$CP" "$R" --runner install $FLEET > "$T/out" 2>&1; check "$?" "0" "configured already: no build needed, whatever the architecture"
grep -q 'variable CI_RUNS_ON left at \["self-hosted","macOS","laptop"\]: registered runner laptop carries its labels' "$T/out"; check "$?" "0" "…the variable, served by another online runner, left as it is"
check "$(grep -c -- '-X PATCH\|-X POST repos/acme/demo/actions/variables' "$T/gh/calls")" "0" "…nothing written"
grep -q "value='\[\"self-hosted\",\"macOS\",\"fleet\"\]'" "$T/out"; check "$?" "0" "…and the PATCH that would route it printed"
echo "{\"total_count\":2,\"runners\":[${LAPTOP/online/offline},$OLDMAC]}" > "$T/gh/runners.json"; : > "$T/gh/calls"
"$CP" "$R" --runner install $FLEET > "$T/out" 2>&1; check "$?" "0" "the variable's runner registered but offline (asleep)"
check "$(grep -c -- '-X PATCH' "$T/gh/calls")" "0" "…still the fleet: the variable left (review 2026-10-27)"
python3 - "$CP" > "$T/out" 2>&1 <<'PY'; check "$?" "2" "the runner list unread: the variable is never written on a guess"
import importlib.machinery, importlib.util, sys
l = importlib.machinery.SourceFileLoader("cp", sys.argv[1]); s = importlib.util.spec_from_loader("cp", l)
m = importlib.util.module_from_spec(s); l.exec_module(m)
m.runners_of = lambda s: (None, "HTTP 403")
try:
    m.served("acme/demo", '["self-hosted","macOS","laptop"]', "oldmac")
except m.Refusal as e:
    print(e); sys.exit(2)
PY
grep -q "could not read acme/demo's runners (HTTP 403)" "$T/out"; check "$?" "0" "…and says so"
python3 - "$CP" > "$T/out" 2>&1 <<'PY'; check "$?" "0" "a bare label in the variable (no JSON): fromJSON fails on it, so it routes nowhere"
import importlib.machinery, importlib.util, sys
l = importlib.machinery.SourceFileLoader("cp", sys.argv[1]); s = importlib.util.spec_from_loader("cp", l)
m = importlib.util.module_from_spec(s); l.exec_module(m)
m.variable = lambda s, v: ("box1", None)
m.runners_of = lambda s: ([{"name": "other", "labels": [{"name": "box1"}]}], None)
m.set_variable = lambda s, v, labels, dry: print("set %s %s" % (v, ",".join(labels)))
m.route_variable("acme/demo", "CI_RUNS_ON", m.Target("h", ("self-hosted", "macOS", "box1"), "box1", 1), True)
print("served=%s" % m.served("acme/demo", "box1", "box1"))
print("caps=%s" % sorted(m.variable_labels("box1")))
PY
grep -qF "set CI_RUNS_ON self-hosted,macOS,box1" "$T/out"; check "$?" "0" "…install sets it (landing review 2026-11-01), never 'already routes'"
grep -qF "served=[]" "$T/out"; check "$?" "0" "…no other runner serves it"
grep -qF "caps=['box1']" "$T/out"; check "$?" "0" "…while caps still reads \${{ vars.X }}'s bare label"
python3 - "$CP" > "$T/out" 2>&1 <<'PY'; check "$?" "0" "the host-write scan reads a block list holding self-hosted beside an expression"
import importlib.machinery, importlib.util, sys
l = importlib.machinery.SourceFileLoader("cp", sys.argv[1]); s = importlib.util.spec_from_loader("cp", l)
m = importlib.util.module_from_spec(s); l.exec_module(m)
t = "jobs:\n  a:\n    runs-on:\n      - self-hosted\n      - ${{ matrix.h }}\n    steps: []\n"
print(m.runs_on_runner_mac(t, None), m.runs_on_runner_mac(t.replace("self-hosted", "ubuntu-latest"), None))
PY
check "$(tail -1 "$T/out")" "True False" "…and not one without it (landing review 2026-11-01)"
echo "{\"total_count\":1,\"runners\":[$OLDMAC]}" > "$T/gh/runners.json"
"$CP" "$R" --runner install $FLEET > "$T/out" 2>&1; check "$?" "0" "no other runner registered with the variable's labels"
check "$(python3 -c "import json; print(json.load(open('$T/gh/vars/CI_RUNS_ON.json'))['value'])")" '["self-hosted","macOS","fleet"]' "…routed to this runner's labels"
NEWMAC='{"id":11,"name":"newmac","status":"online","labels":[{"name":"self-hosted"},{"name":"macOS"},{"name":"newmac"},{"name":"fleet"}]}'
echo "{\"total_count\":1,\"runners\":[$NEWMAC]}" > "$T/gh/runners.json"; : > "$T/gh/calls"
"$CP" "$R" --runner install --host old-ci --name newmac --labels self-hosted,macOS,newmac,fleet > "$T/out" 2>&1; check "$?" "0" "a newcomer whose labels cover the variable's"
grep -q 'variable CI_RUNS_ON already routes to \["self-hosted","macOS","fleet"\]: newmac carries its labels' "$T/out"; check "$?" "0" "…joins the fleet the variable names"
check "$(grep -c -- '-X PATCH' "$T/gh/calls")" "0" "…never narrowed to it (review 2026-10-27)"
R2="$T/w7"; newrepo "$R2"; git -C "$R2" remote set-url origin https://github.com/acme/demo-2.git
fakerunner "$RH/actions-runners/acme/demo-2" second; printf '{"gitHubUrl": "https://github.com/acme/demo"}' > "$RH/actions-runners/acme/demo-2/.runner"
"$CP" "$R2" --runner status > "$T/out" 2>&1; check "$?" "2" "acme/demo-2's own folder holding acme/demo's 2nd runner: refused"
grep -q 'status actions.runner' "$T/out"; check "$?" "1" "…its svc.sh never run"
rm -rf "$RH/actions-runners/acme/demo-2"
fakerunner "$RH/actions-runners/acme/demo-2" other; printf '{"gitHubUrl": "https://github.com/acme/demo-2"}' > "$RH/actions-runners/acme/demo-2/.runner"
"$CP" "$R" --runner status --instance 2 > "$T/out" 2>&1; check "$?" "2" "--instance 2 where acme/demo-2's own runner lives: refused"
grep -q "holds another repo's runner" "$T/out"; check "$?" "0" "…saying whose"
grep -q 'status actions.runner' "$T/out"; check "$?" "1" "…its svc.sh never run"
rm -rf "$RH/actions-runners/acme/demo-2"
"$CP" "$R" --runner status --host old-ci > /dev/null 2>&1; check "$?" "2" "--host without --name: an error (two Macs would share a name)"
echo "{\"total_count\":1,\"runners\":[$OLDMAC]}" > "$T/gh/runners.json"
printf 'LANG=C.UTF-8\n' > "$RH/actions-runners/acme/demo/.env"; printf '1\t0\tactions.runner.acme-demo.laptop\n' > "$T/ssh/loaded"; : > "$T/ssh/svc"
FAKE_LOCALES="C en_US.UTF-8" "$CP" "$R" --runner install $FLEET > "$T/out" 2>&1; check "$?" "0" "a runner whose LANG is no locale on its Mac (C.UTF-8 on macOS 12)"
check "$(cat "$RH/actions-runners/acme/demo/.env")" "LANG=en_US.UTF-8" "…takes an installed UTF-8 one (2026-10-27)"
check "$(tr '\n' ' ' < "$T/ssh/svc")" "stopped started " "…and restarts, so the jobs read it"
grep -q 'LANG C.UTF-8 is no locale here: en_US.UTF-8' "$T/out"; check "$?" "0" "…saying so"
: > "$T/ssh/svc"; "$CP" "$R" --runner install $FLEET > /dev/null 2>&1
check "$(cat "$RH/actions-runners/acme/demo/.env"; grep -c stopped "$T/ssh/svc")" "LANG=en_US.UTF-8
0" "an installed LANG: left as it is, no restart"
printf 'OTHER=1\n' > "$RH/actions-runners/acme/demo/.env"; : > "$T/ssh/svc"
FAKE_LOCALES="C en_US.UTF-8" "$CP" "$R" --runner install $FLEET > "$T/out" 2>&1; check "$?" "0" "a runner with no LANG at all (C too)"
check "$(tr '\n' ' ' < "$RH/actions-runners/acme/demo/.env")" "OTHER=1 LANG=en_US.UTF-8 " "…gains an installed UTF-8 one, the rest kept"
printf 'LANG=xx_XX.UTF-8\n' > "$RH/actions-runners/acme/demo/.env"
FAKE_LOCALES="C" "$CP" "$R" --runner install $FLEET > "$T/out" 2>&1; check "$?" "0" "no UTF-8 locale on the Mac at all"
grep -q 'neither en_US.UTF-8 nor C.UTF-8 is installed: jobs run in C' "$T/out"; check "$?" "0" "…said, never silent"
"$CP" "$R" --runner status --instance 2 > "$T/out" 2>&1; check "$?" "0" "--instance 2: status"
grep -q 'not configured: .*actions-runners/acme/demo-2$' "$T/out"; check "$?" "0" "…in <repo>-2"
grep -q "acme/demo's runner laptop-2 " "$T/out"; check "$?" "0" "…named <name>-2"
"$CP" "$R" --host old-ci > /dev/null 2>&1; check "$?" "2" "--host without --runner: an error"
"$CP" "$R" --runner status --instance 0 > /dev/null 2>&1; check "$?" "2" "--instance 0: an error"
"$CP" "$R" --runner status --name -x > /dev/null 2>&1; check "$?" "2" "a --name starting with '-': an error"
"$CP" "$R" --runner status --labels macOS,fleet > "$T/out" 2>&1; check "$?" "2" "--labels without self-hosted: refused"
echo '{"total_count":0,"runners":[]}' > "$T/gh/runners.json"; rm -rf "$T/gh/vars" "$T/ssh/home/actions-runners/acme"

echo "the review of 2026-10-21: what every rendered file names (1, 2)"
# Private words through helloworld's own list and matcher, where one is installed (its own lookup,
# under the caller's config dir): the scan prints counts, never a word. CI has none: said, skipped.
cat > "$T/wordscan.py" <<'PY'
import importlib.machinery, importlib.util, sys
loader = importlib.machinery.SourceFileLoader("hw", sys.argv[1])
spec = importlib.util.spec_from_loader("hw", loader); m = importlib.util.module_from_spec(spec); loader.exec_module(m)
try:
    _, words = m.wordlist()
except m.Refused:
    print("no list"); sys.exit(0)
rx = m.words_regex(words)
print(" ".join(str(len(m.text_hits(open(f, encoding="utf-8").read(), rx, only={"private word"}))) for f in sys.argv[2:]))
PY
R="$T/x1"; newrepo "$R"; mkdir -p "$R/.helloworld"; "$CP" "$R" --to self-hosted > /dev/null 2>&1
R2="$T/x1c"; newrepo "$R2"; "$CP" "$R2" --to circleci > /dev/null 2>&1
HW="$M/../helloworld/bin/helloworld"
SCANNED=("$TPL/.github/workflows/check.yml" "$M/templates/ci/circleci-check.yml" "$R/.github/workflows/check.yml" "$R2/.circleci/parts/check.yml" "$R2/.circleci/config.yml")
if [ -f "$HW" ]; then
  if [ -n "$CALLER_CONFIG" ]; then hits=$(REGATTA_CONFIG="$CALLER_CONFIG" python3 "$T/wordscan.py" "$HW" "${SCANNED[@]}")
  else hits=$(env -u REGATTA_CONFIG python3 "$T/wordscan.py" "$HW" "${SCANNED[@]}"); fi
  if [ "$hits" = "no list" ]; then echo "  skip the private-word scan: no private word list here (helloworld's lookup)"
  else check "$hits" "0 0 0 0 0" "the templates, a variable-form check.yml and a composed CircleCI config hold no private word (1, 2)"; fi
else echo "  skip the private-word scan: helloworld is not in this checkout"; fi
check "$(grep -c "a self-hosted runner on a Mac of one's own" "$TPL/.github/workflows/check.yml")" "1" "the template's header names the runner generically (1)"
check "$(grep -c "^# wharf's templates/ci/circleci-check.yml" "$R2/.circleci/parts/check.yml")" "1" "the CircleCI part names wharf's template (2)"
python3 - "$R2/.circleci/parts/check.yml" <<'PY'
import sys; p = sys.argv[1]; t = open(p).read().split("\n")
t[1] = "# an older header's wording, from wherever the template lived then"
open(p, "w").write("\n".join(t))
PY
"$CP" "$R2" --to actions > /dev/null 2>&1; check "$?" "0" "a part whose header reads otherwise is still the template's: comments are no difference (2)"

echo "the review of 2026-10-21: runs-on is the tool's only in its own two forms (3, 4, 5)"
echo '{"strict": false, "contexts": ["check"]}' > "$T/gh/rsc.json"; echo '{"statuses":[]}' > "$T/gh/status.json"; rm -rf "$T/gh/vars"
echo '{"total_count":0,"runners":[]}' > "$T/gh/runners.json"
setruns() { # setruns <repo> <value>: check.yml's first runs-on line set to value, by hand
  python3 - "$1/.github/workflows/check.yml" "$2" <<'PY'
import re, sys; p, v = sys.argv[1], sys.argv[2]
t = open(p, newline="").read()
open(p, "w", newline="").write(re.sub(r"(?m)^( *)runs-on: [^\r\n]*", lambda m: m.group(1) + "runs-on: " + v, t, count=1))
PY
}
R="$T/x4"; newrepo "$R"; setruns "$R" "[self-hosted, linux, gpu]"; cp "$R/.github/workflows/check.yml" "$T/x4.yml"
"$CP" "$R" > "$T/out" 2>&1; grep -q 'actions (inferred' "$T/out"; check "$?" "0" "a hand-written [self-hosted, linux, gpu]: not self-hosted (4)"
"$CP" "$R" --to self-hosted > "$T/out" 2>&1; check "$?" "2" "…--to self-hosted holds it as a hand edit (4)"
"$CP" "$R" --to actions > /dev/null 2>&1; check "$?" "2" "…and so does --to actions (4)"
check "$(shasum < "$R/.github/workflows/check.yml")" "$(shasum < "$T/x4.yml")" "…check.yml untouched (4)"
"$CP" "$R" --to self-hosted --force > /dev/null 2>&1; check "$?" "0" "…--force replaces it (4)"
R="$T/x3"; newrepo "$R"; setruns "$R" '${{ fromJSON(vars.GPU_POOL) }}'
"$CP" "$R" > "$T/out" 2>&1; grep -q 'actions (inferred' "$T/out"; check "$?" "0" "runs-on reading a variable of the repo's own: not self-hosted (3)"
"$CP" "$R" --to self-hosted > /dev/null 2>&1; check "$?" "2" "…nor the tool's form: --to self-hosted holds it (3)"
setruns "$R" "\${{ fromJSON(vars.CI_RUNS_ON || '\"macos-latest\"') }}"
"$CP" "$R" > "$T/out" 2>&1; grep -q 'actions (inferred' "$T/out"; check "$?" "0" "…a near miss of the tool's shape neither (3)"
setruns "$R" '${{ fromJSON(vars.GPU_POOL) }}'
echo '{"provider": "self-hosted", "check": "sh check.sh"}' > "$R/.github/ci.json"
RD="$T/ssh/home/actions-runners/acme/demo"; rm -rf "$T/ssh/home/actions-runners/acme" "$T/ssh/home/actions-runners/acme-demo"; fakerunner "$RD" x; touch "$RD/.runner"
ONLINE='{"total_count":1,"runners":[{"id":9,"name":"laptop","status":"online","labels":[{"name":"self-hosted"},{"name":"macOS"},{"name":"laptop"}]}]}'
echo "$ONLINE" > "$T/gh/runners.json"; : > "$T/gh/calls"
"$CP" "$R" --runner install > "$T/out" 2>&1; check "$?" "0" "--runner install where runs-on reads GPU_POOL by hand (3)"
check "$(grep -c 'actions/variables' "$T/gh/calls")" "0" "…GPU_POOL never read or written: the tool did not write it (3)"
R="$T/x5"; newrepo "$R"; setruns "$R" "[macOS, laptop]"
"$CP" "$R" > "$T/out" 2>&1; grep -q 'self-hosted (inferred' "$T/out"; check "$?" "0" "[macOS, laptop], no ci.json: self-hosted, by the labels key's own label (5)"
setruns "$R" "laptop"
"$CP" "$R" > "$T/out" 2>&1; grep -q 'self-hosted (inferred' "$T/out"; check "$?" "0" "…the label alone too (5)"
setruns "$R" "[self-hosted, macOS, othermac]"
"$CP" "$R" > "$T/out" 2>&1; grep -q 'actions (inferred' "$T/out"; check "$?" "0" "…a literal naming none of its own labels is not (4, 5)"

echo "the review of 2026-10-21: a re-run keeps the file's form; the variable's next steps (6, 16, 17, 9, 7)"
rm -rf "$T/gh/vars"
R="$T/x6"; newrepo "$R"; "$CP" "$R" --to self-hosted > /dev/null 2>&1; mkdir -p "$R/.helloworld"
"$CP" "$R" --to self-hosted > /dev/null 2>&1; check "$?" "0" "a literal self-hosted file, .helloworld/ added: a re-run (6)"
check "$(grep -c 'runs-on: \[self-hosted, macOS\]' "$R/.github/workflows/check.yml")" "1" "…keeps the literal form (6)"
: > "$T/gh/calls"
"$CP" "$R" --runner install --dry-run > "$T/out" 2>&1
grep -q 'no repository variable set: check.yml.s runs-on names the labels itself' "$T/out"; check "$?" "0" "--runner install --dry-run on it: no variable, and why (16)"
"$CP" "$R" --runner install > "$T/out" 2>&1; check "$?" "0" "--runner install on it"
grep -q 'no repository variable set: check.yml.s runs-on names the labels itself' "$T/out"; check "$?" "0" "…says no variable was set, and why (16)"
check "$(grep -c 'actions/variables' "$T/gh/calls")" "0" "…and asks GitHub for none (16)"
"$CP" "$R" --to self-hosted --runs-on-var CI_RUNS_ON > "$T/out" 2>&1; check "$?" "0" "--runs-on-var switches it to the variable form (6)"
check "$(grep -cxF "    $VARLINE" "$R/.github/workflows/check.yml")" "1" "…runs-on reads CI_RUNS_ON (6)"
grep -q '^next: .*only once CI_RUNS_ON is set' "$T/out"; check "$?" "0" "…the next step: the check reaches the runner Mac only once the variable is set (6)"
"$CP" "$R" --runner install > "$T/out" 2>&1; check "$?" "0" "--runner install creates the variable"
grep -q 'rollback: gh api -X DELETE repos/acme/demo/actions/variables/CI_RUNS_ON$' "$T/out"; check "$?" "0" "…and prints the DELETE that undoes the create (17)"
FULLLINE="runs-on: \${{ fromJSON(github.event_name != 'pull_request' && vars.CI_RUNS_ON_FULL || vars.CI_RUNS_ON || '\"ubuntu-latest\"') }}"
setruns "$R" "${FULLLINE#runs-on: }"
"$CP" "$R" > "$T/out" 2>&1; grep -q 'runs-on variable CI_RUNS_ON' "$T/out"; check "$?" "0" "the split form (whole-line runs on CI_RUNS_ON_FULL): read as the variable form (2026-10-27)"
: > "$T/gh/calls"; "$CP" "$R" --runner install --dry-run > "$T/out" 2>&1; check "$?" "0" "…--runner install reads its variable"
grep -q 'would then route the repository variable CI_RUNS_ON that' "$T/out"; check "$?" "0" "…and would route CI_RUNS_ON, never CI_RUNS_ON_FULL"
"$CP" "$R" --to self-hosted > "$T/out" 2>&1; check "$?" "0" "…a re-run of --to self-hosted"
check "$(grep -cxF "    $FULLLINE" "$R/.github/workflows/check.yml")" "1" "…keeps the split form"
grep -q "# A push, the nightly run and a hand start take CI_RUNS_ON_FULL's labels" "$R/.github/workflows/check.yml"; check "$?" "0" "…and says what it does"
printf '    runs-on: ${{ fromJSON(vars.CI_RUNS_ON || %s) }}\n' "'\"ubuntu-latest\"'" > "$R/.github/workflows/automerge.yml"
"$CP" "$R" > "$T/out" 2>&1; grep -q 'CI_RUNS_ON_AUTOMERGE' "$T/out"; check "$?" "1" "an automerge.yml without its own variable: status names none"
printf '    runs-on: ${{ fromJSON(vars.CI_RUNS_ON_AUTOMERGE || vars.CI_RUNS_ON || %s) }}\n' "'\"ubuntu-latest\"'" > "$R/.github/workflows/automerge.yml"
"$CP" "$R" > "$T/out" 2>&1; grep -q "runs-on variable CI_RUNS_ON_AUTOMERGE is unset: automerge.yml takes CI_RUNS_ON's runners" "$T/out"; check "$?" "0" "automerge.yml reads CI_RUNS_ON_AUTOMERGE, unset: status says it queues with the checks (ci-queue-health)"
mkdir -p "$T/gh/vars"; echo '{"name":"CI_RUNS_ON_AUTOMERGE","value":"\"ubuntu-latest\""}' > "$T/gh/vars/CI_RUNS_ON_AUTOMERGE.json"
"$CP" "$R" > "$T/out" 2>&1; grep -qF 'runs-on variable CI_RUNS_ON_AUTOMERGE (automerge.yml): "ubuntu-latest"' "$T/out"; check "$?" "0" "…set: its value"
rm -f "$T/gh/vars/CI_RUNS_ON_AUTOMERGE.json" "$R/.github/workflows/automerge.yml"
setruns "$R" "\${{ fromJSON(github.event_name != 'pull_request' && vars.OTHER_FULL || vars.CI_RUNS_ON || '\"ubuntu-latest\"') }}"
"$CP" "$R" --runner install --dry-run > "$T/out" 2>&1; check "$?" "0" "a split form whose two names differ: --runner install --dry-run"
grep -q 'route the repository variable' "$T/out"; check "$?" "1" "…the repo's own form, its variable never this tool's"
setruns "$R" "${VARLINE#runs-on: }"
echo '{"total_count":0,"runners":[]}' > "$T/gh/runners.json"
"$CP" "$R" --runner remove > "$T/out" 2>&1; check "$?" "0" "--runner remove with the variable set"
grep -q 'repository variable CI_RUNS_ON holds \["self-hosted","macOS","laptop"\]' "$T/out"; check "$?" "0" "…says what it holds, read (9)"
touch "$RD/.runner"; rm -f "$T/gh/vars/CI_RUNS_ON.json"
"$CP" "$R" --runner remove > "$T/out" 2>&1
grep -q 'repository variable CI_RUNS_ON is unset' "$T/out"; check "$?" "0" "…unset: said so (9)"
grep -q 'still asks for' "$T/out"; check "$?" "1" "…never that it still asks for the labels (9)"
touch "$RD/.runner"; mkdir -p "$T/gh/vars"; touch "$T/gh/vars/fail"
"$CP" "$R" --runner remove > "$T/out" 2>&1
grep -q 'repository variable CI_RUNS_ON: unread' "$T/out"; check "$?" "0" "…unread: said so (9)"
touch "$RD/.runner"; echo "$ONLINE" > "$T/gh/runners.json"; : > "$T/gh/calls"
"$CP" "$R" --runner install > "$T/out" 2>&1; check "$?" "2" "the variable unread (gh failing with no output): --runner install refuses (7)"
check "$(grep -c -- '-X POST repos/acme/demo/actions/variables\|-X PATCH repos/acme/demo/actions/variables' "$T/gh/calls")" "0" "…and writes no variable (7)"
"$CP" "$R" > "$T/out" 2>&1; grep -q 'runs-on variable CI_RUNS_ON: (unread' "$T/out"; check "$?" "0" "…status says unread, not unset (7)"
rm -f "$T/gh/vars/fail"

echo "the review of 2026-10-21: the label list as YAML writes it (8, 10, 11)"
R="$T/x8"; newrepo "$R"; "$CP" "$R" --to self-hosted > /dev/null 2>&1
setruns "$R" "[self-hosted, macOS, laptop]  # the runner Mac"
"$CP" "$R" > "$T/out" 2>&1; grep -q 'no online runner labelled' "$T/out"; check "$?" "1" "a trailing comment on runs-on: its labels online, no warning (8)"
"$CP" "$R" --to self-hosted > /dev/null 2>&1; check "$?" "0" "…and a re-run takes the commented line as the tool's (8)"
setruns "$R" "[self-hosted, macOS, laptop]"
python3 -c "import sys; p=sys.argv[1]; t=open(p).read(); open(p,'w',newline='').write(t.replace('\n','\r\n'))" "$R/.github/workflows/check.yml"
"$CP" "$R" > "$T/out" 2>&1; grep -q 'no online runner labelled' "$T/out"; check "$?" "1" "CRLF line ends: no CR in the last label (8)"
setruns "$R" "['self-hosted', \"macOS\", laptop]"
"$CP" "$R" > "$T/out" 2>&1; grep -q 'no online runner labelled' "$T/out"; check "$?" "1" "quoted labels: unquoted (8)"
R="$T/x10"; newrepo "$R"; mkdir -p "$R/.helloworld"; "$CP" "$R" --to self-hosted > /dev/null 2>&1
mkdir -p "$T/gh/vars"; echo '{"name":"CI_RUNS_ON","value":"\"ubuntu-latest\""}' > "$T/gh/vars/CI_RUNS_ON.json"
echo '{"total_count":0,"runners":[]}' > "$T/gh/runners.json"
"$CP" "$R" > "$T/out" 2>&1; grep -q 'no online runner labelled' "$T/out"; check "$?" "1" "a variable holding a JSON string: hosted, no runner warning (10)"
rm -rf "$T/gh/vars"
R="$T/x11"; newrepo "$R"
"$CP" "$R" --to self-hosted --runs-on-var $'X\n' > /dev/null 2>&1; check "$?" "2" "a variable name with a trailing newline: refused (11)"

echo "the review of 2026-10-21: the runner keys, read once per command (12)"
cat > "$T/reads.py" <<'PY'
import collections, contextlib, importlib.machinery, importlib.util, io, sys
loader = importlib.machinery.SourceFileLoader("cp", sys.argv[1])
spec = importlib.util.spec_from_loader("cp", loader); m = importlib.util.module_from_spec(spec); loader.exec_module(m)
n, real = collections.Counter(), m.common.config_read
def counting(name):
    n[name] += 1
    return real(name)
m.common.config_read = counting
with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
    rc = m.main(sys.argv[3:])
open(sys.argv[2], "w").write("%s %d %d" % (rc, n["wharf/ci-runner-labels"], n["wharf/ci-runner-ssh"]))
PY
R="$T/x12"; newrepo "$R"; "$CP" "$R" --to self-hosted > /dev/null 2>&1; touch "$RD/.runner"; echo "$ONLINE" > "$T/gh/runners.json"
python3 "$T/reads.py" "$CP" "$T/reads" "$R" --runner install > /dev/null 2>&1
check "$(cat "$T/reads")" "0 1 1" "--runner install reads the labels and the ssh keys once each (12)"
python3 "$T/reads.py" "$CP" "$T/reads" "$R" --to self-hosted > /dev/null 2>&1
check "$(cut -d' ' -f1-2 "$T/reads")" "0 1" "--to self-hosted reads the labels once (12)"
cp "$REGATTA_CONFIG/wharf/ci-runner-ssh" "$T/ssh.key"; printf -- '-oBatchMode=no\n' > "$REGATTA_CONFIG/wharf/ci-runner-ssh"; rm -f "$T/ssh/argv"
"$CP" "$R" --runner status > "$T/out" 2>&1; check "$?" "2" "an ssh alias starting with -: refused (12)"
check "$(test -e "$T/ssh/argv" && echo ssh || echo none)" "none" "…ssh never run with it (12)"
grep -q 'ci-runner-ssh' "$T/out"; check "$?" "0" "…naming the file (12)"
mv "$T/ssh.key" "$REGATTA_CONFIG/wharf/ci-runner-ssh"
echo '{"total_count":0,"runners":[]}' > "$T/gh/runners.json"

echo "a job on the runner Mac keeps out of its login's own (the move of eight repos, 2026-10-21)"
rm -rf "$T/gh/vars"
stepnames() { yamlread "$1" '"|".join(s.get("name") or s["uses"] for s in d["jobs"]["check"]["steps"])'; }
R="$T/gcg1"; newrepo "$R"
"$CP" "$R" --to self-hosted > "$T/out" 2>&1; check "$?" "0" "--to self-hosted"
check "$(stepnames "$R/.github/workflows/check.yml")" "git config --global in this job's own file|actions/checkout@v4|check" \
      "the GIT_CONFIG_GLOBAL step comes first, before the checkout; the file parses"
check "$(grep -cxF '        run: echo "GIT_CONFIG_GLOBAL=$RUNNER_TEMP/gitconfig" >> "$GITHUB_ENV"' "$R/.github/workflows/check.yml")" "1" \
      "…it points git's global config at the job's temp dir"
for w in 'real HOME' 'headless Chrome' '--prefix "$RUNNER_TEMP/npm"' '$GITHUB_PATH' 'one job at a time'; do
  grep -qF -- "$w" "$R/.github/workflows/check.yml"; check "$?" "0" "…its comment names: $w"
done
rm "$R/.github/ci.json"
"$CP" "$R" --to self-hosted > /dev/null 2>&1; check "$?" "0" "a re-run on it, no ci.json"
check "$(python3 -c "import json; print(json.load(open('$R/.github/ci.json'))['check'])")" "sh check.sh" "…reads the check step's command, not the guard's"
"$CP" "$R" --to actions > /dev/null 2>&1; check "$?" "0" "self-hosted → actions"
check "$(grep -c GIT_CONFIG_GLOBAL "$R/.github/workflows/check.yml")" "0" "…the ubuntu file has no guard step"
# an self-hosted file as the tool wrote it before the step: still its own, and a re-run adds the step
R="$T/gcg2"; newrepo "$R"; "$CP" "$R" --to self-hosted > /dev/null 2>&1
python3 - "$R/.github/workflows/check.yml" <<'EOF'
import re, sys
f = sys.argv[1]; s = open(f).read()
s = re.sub(r"(?m)^      # The runner runs as its login.*?\n(?=      - uses: actions/checkout)", "", s, flags=re.S)
open(f, "w").write(s)
EOF
check "$(grep -c GIT_CONFIG_GLOBAL "$R/.github/workflows/check.yml")" "0" "(an self-hosted file without the step)"
"$CP" "$R" > "$T/out" 2>&1; grep -q '⚠ check.yml sets no GIT_CONFIG_GLOBAL' "$T/out"; check "$?" "0" "status warns that it has no GIT_CONFIG_GLOBAL step"
"$CP" "$R" --to self-hosted > /dev/null 2>&1; check "$?" "0" "a re-run takes it as the tool's own, without --force"
check "$(grep -c 'GIT_CONFIG_GLOBAL=' "$R/.github/workflows/check.yml")" "1" "…and adds the step"
"$CP" "$R" > "$T/out" 2>&1; grep -q 'GIT_CONFIG_GLOBAL' "$T/out"; check "$?" "1" "…status says nothing of it then"

echo "a job on the runner Mac: the check command's host writes refused"
R="$T/gcg3"; newrepo "$R"
"$CP" "$R" --to self-hosted --check 'npm install -g some-cli && sh check.sh' > "$T/out" 2>&1; check "$?" "2" "npm install -g in the check command: refused"
grep -q '⚠ the check command:1 runs npm install -g on the runner Mac: .*--prefix "$RUNNER_TEMP/npm"' "$T/out"; check "$?" "0" "…the line and the fix said"
check "$(grep -c GIT_CONFIG_GLOBAL "$R/.github/workflows/check.yml")" "0" "…the checkout as it was"
"$CP" "$R" --to self-hosted --check 'npm i --global some-cli && sh check.sh' > /dev/null 2>&1; check "$?" "2" "npm i --global: refused too"
"$CP" "$R" --to self-hosted --check 'npm install -g --prefix "$RUNNER_TEMP/npm" some-cli && sh check.sh' > "$T/out" 2>&1; check "$?" "0" "npm install -g --prefix: no refusal"
grep -q '⚠ the check command' "$T/out"; check "$?" "1" "(no host-write warning for the command)"
grep -q 'runs npm install -g' "$T/out"; check "$?" "1" "…and no host-write line"
R="$T/gcg4"; newrepo "$R"
"$CP" "$R" --to self-hosted --check 'sudo make install && sh check.sh' > "$T/out" 2>&1; check "$?" "2" "sudo in the check command: refused"
grep -q 'runs sudo on the runner Mac' "$T/out"; check "$?" "0" "…said"
"$CP" "$R" --to self-hosted --check 'apt-get install -y jq && sh check.sh' > /dev/null 2>&1; check "$?" "2" "apt-get unguarded: refused"
"$CP" "$R" --to self-hosted --check 'if command -v apt-get >/dev/null; then apt-get install -y jq; fi; sh check.sh' > /dev/null 2>&1
check "$?" "0" "apt-get behind command -v: no refusal"
"$CP" "$R" --to self-hosted --check 'git config --global user.name CI && sh check.sh' > "$T/out" 2>&1
check "$?" "0" "git config --global in the check command: the guard step covers it"
grep -q 'runs git config --global' "$T/out"; check "$?" "1" "…nothing said"
"$CP" "$R" --to self-hosted --check 'sudo make install && sh check.sh' --force > "$T/out" 2>&1; check "$?" "0" "--force writes it anyway"
grep -q 'runs sudo on the runner Mac' "$T/out"; check "$?" "0" "…and still says the line"
"$CP" "$R" --to actions --check 'sudo make install && sh check.sh' > /dev/null 2>&1; check "$?" "0" "--to actions: nothing refused (a hosted runner is thrown away)"

echo "a job on the runner Mac: what the switch leaves is said, line by line"
R="$T/gcg5"; newrepo "$R"
printf '#!/bin/sh\n# npm install -g in a comment is no command\nnpm i -g left-pad\nsudo true\n' > "$R/check.sh"
"$CP" "$R" --to self-hosted > "$T/out" 2>&1; check "$?" "0" "a script the command names: no refusal"
grep -q '⚠ check.sh:3 runs npm install -g' "$T/out"; check "$?" "0" "…its npm -g said, with file and line"
grep -q '⚠ check.sh:4 runs sudo' "$T/out"; check "$?" "0" "…its sudo said"
grep -q 'check.sh:2' "$T/out"; check "$?" "1" "…a comment is not"
R="$T/gcg6"; newrepo "$R"; W="$R/.github/workflows"
cat > "$W/release.yml" <<'EOF'
name: release
on: push
jobs:
  build:
    runs-on: [self-hosted, macOS, laptop]
    steps:
      - name: identity
        run: git config --global user.name CI
      - name: deps
        run: sudo apt-get install -y jq
      - name: linux only
        if: runner.os == 'Linux'
        run: |
          echo deps
          apt-get install -y zip
EOF
cat > "$W/lint.yml" <<'EOF'
name: lint
on: push
jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - run: git config --global user.name CI
      - run: npm install -g eslint
EOF
cat > "$W/node.yml" <<'EOF'
name: node
on: push
jobs:
  node:
    runs-on: ${{ fromJSON(vars.CI_RUNS_ON || '"ubuntu-latest"') }}
    steps:
      - run: echo "GIT_CONFIG_GLOBAL=$RUNNER_TEMP/gitconfig" >> "$GITHUB_ENV"
      - uses: actions/setup-node@v4
        with:
          node-version: 22
      - run: npm install -g some-cli
      - run: git config --global user.name CI
EOF
cat > "$W/am.yml" <<'EOF'
name: am
on: push
jobs:
  am:
    runs-on: ${{ fromJSON(vars.CI_RUNS_ON_AUTOMERGE || vars.CI_RUNS_ON || '"ubuntu-latest"') }}
    steps:
      - run: npm install -g some-cli
EOF
"$CP" "$R" --to self-hosted > "$T/out" 2>&1; check "$?" "0" "other workflows: no refusal"
grep -q '⚠ .github/workflows/release.yml:8 runs git config --global' "$T/out"; check "$?" "0" "…a runner-Mac workflow's git config --global without the guard: said"
grep -q 'release.yml:10 runs sudo' "$T/out"; check "$?" "0" "…its sudo"
grep -q 'release.yml:10 runs apt-get' "$T/out"; check "$?" "0" "…its unguarded apt-get"
grep -q 'release.yml:15' "$T/out"; check "$?" "1" "…not an apt-get in a step that runs on Linux only"
grep -q 'lint.yml' "$T/out"; check "$?" "1" "…nothing of an ubuntu workflow"
grep -q 'node.yml' "$T/out"; check "$?" "1" "…nor of one with the guard and setup-node"
grep -q 'am.yml:7 runs npm install -g' "$T/out"; check "$?" "0" "…an automerge.yml on its own runner variable is scanned as a runner-Mac workflow (ci-queue-health review)"
"$CP" "$R" > "$T/out" 2>&1; grep -q 'release.yml:8 runs git config --global' "$T/out"; check "$?" "0" "status says them too"

echo "a publishing repo's check.yml names no host (twin)"
R="$T/gcg7"; newrepo "$R"; "$CP" "$R" --to self-hosted > /dev/null 2>&1
mkdir -p "$R/.helloworld"; printf '# what goes public\nREADME.md\n' > "$R/.helloworld/allowlist.txt"
"$CP" "$R" --to self-hosted > /dev/null 2>&1
check "$(grep -c 'runs-on: \[self-hosted, macOS\]' "$R/.github/workflows/check.yml")" "1" "an allowlist without .github/: the literal stays"
printf '.github/workflows/check.yml\n' >> "$R/.helloworld/allowlist.txt"
"$CP" "$R" > "$T/out" 2>&1; grep -q '⚠ check.yml is published' "$T/out"; check "$?" "0" "status: a published check.yml naming the labels warned"
"$CP" "$R" --to self-hosted > /dev/null 2>&1; check "$?" "0" "the allowlist lists .github/: a re-run"
check "$(grep -cxF "    $VARLINE" "$R/.github/workflows/check.yml")" "1" "…takes the variable form, over the literal"
check "$(grep -c 'laptop' "$R/.github/workflows/check.yml")" "0" "…and the file names no label of the Mac's own"
"$CP" "$R" > "$T/out" 2>&1; grep -q 'is published' "$T/out"; check "$?" "1" "…status says nothing then"
R="$T/gcg8"; newrepo "$R"; "$CP" "$R" --to self-hosted > /dev/null 2>&1
"$CP" "$R" --to self-hosted --twin > /dev/null 2>&1; check "$?" "0" "--twin on a literal self-hosted file"
check "$(grep -cxF "    $VARLINE" "$R/.github/workflows/check.yml")" "1" "…the variable form"
"$CP" "$R" --to self-hosted --twin --runs-on-var MAC_LABELS > /dev/null 2>&1
check "$(grep -c 'vars.MAC_LABELS' "$R/.github/workflows/check.yml")" "1" "--twin with --runs-on-var: the variable named"
"$CP" "$R" --to actions --twin > /dev/null 2>&1; check "$?" "2" "--twin without --to self-hosted: an error"

echo "the landing review of 2026-10-21: the scan's edges"
R="$T/lr1"; newrepo "$R"
"$CP" "$R" --to self-hosted --check 'npm install --location=global z && sh check.sh' > /dev/null 2>&1; check "$?" "2" "npm --location=global: refused (1)"
"$CP" "$R" --to self-hosted --check 'npm -g install z && sh check.sh' > /dev/null 2>&1; check "$?" "2" "npm -g install: refused (1)"
"$CP" "$R" --to self-hosted --check 'npm install && cc -g -o t t.c && sh check.sh' > /dev/null 2>&1; check "$?" "0" "a -g after the npm command ends: no refusal (1)"
"$CP" "$R" --to self-hosted --check 'npm install --global-style x && sh check.sh' > /dev/null 2>&1; check "$?" "0" "--global-style is not -g (1)"
"$CP" "$R" --to self-hosted --check 'if command -v apt-get >/dev/null; then sudo apt-get install -y jq; fi; sh check.sh' > /dev/null 2>&1
check "$?" "0" "sudo apt-get behind command -v: no refusal (11)"
"$CP" "$R" --to self-hosted --check 'docker build --platform linux/amd64 . && apt-get install -y jq && sh check.sh' > /dev/null 2>&1
check "$?" "2" "a bare linux on the line guards no apt-get (12)"
R="$T/lr2"; newrepo "$R"; W="$R/.github/workflows"
cat > "$W/home.yml" <<'EOF'
name: home
on: push
jobs:
  a:
    runs-on: [self-hosted, macOS]
    steps:
      - run: echo "HOME=$RUNNER_TEMP/home" >> "$GITHUB_ENV"
      - run: git config --global user.name CI
EOF
cat > "$W/jobs.yml" <<'EOF'
name: jobs
on: push
jobs:
  a:
    runs-on: self-hosted
    steps:
      - run: echo "GIT_CONFIG_GLOBAL=$RUNNER_TEMP/gitconfig" >> "$GITHUB_ENV"
  b:
    runs-on: self-hosted
    steps:
      - uses: actions/setup-node@v4
      - run: git config --global user.name CI
      - run: npm install -g some-cli
      - run: apt-get install -y jq
        if: runner.os == 'Linux'
EOF
printf 'name: bad\non: push\njobs:\n  a:\n    runs-on: self-hosted\n    steps:\n      - run: echo caf\351\n' > "$W/latin1.yml"
"$CP" "$R" --to self-hosted > "$T/out" 2>&1; check "$?" "0" "other workflows of other shapes: no refusal, no traceback (13)"
grep -q 'Traceback' "$T/out"; check "$?" "1" "…a non-UTF-8 workflow read (13)"
grep -q 'home.yml' "$T/out"; check "$?" "1" "…a HOME under \$RUNNER_TEMP guards git config --global (7)"
grep -q '⚠ .github/workflows/jobs.yml:12 runs git config --global' "$T/out"; check "$?" "0" "…another job's guard guards nothing, on a bare self-hosted (4, 5)"
grep -q 'jobs.yml:13 runs npm install -g' "$T/out"; check "$?" "0" "…setup-node with no node-version is no guard (6)"
grep -q 'jobs.yml:14' "$T/out"; check "$?" "1" "…an if: after run: guards its apt-get (12)"
R="$T/lr3"; newrepo "$R"
"$CP" "$R" --to self-hosted --check 'sudo make install && sh check.sh' --force > /dev/null 2>&1
"$CP" "$R" > "$T/out" 2>&1; check "$(grep -c 'runs sudo' "$T/out")" "1" "status says a check-step sudo once (9)"
R="$T/lr4"; newrepo "$R"; "$CP" "$R" --to self-hosted > /dev/null 2>&1
sed -i.bak 's/^      - name: check$/      - name: test/' "$R/.github/workflows/check.yml" && rm -f "$R/.github/workflows/check.yml.bak"
check "$(grep -c '^      - name: test$' "$R/.github/workflows/check.yml")" "1" "(a guarded file, its check step renamed)"
"$CP" "$R" --to actions --force > /dev/null 2>&1; check "$?" "0" "…its command still read past the guard step (14)"
R="$T/lr5"; newrepo "$R"
printf '      - run: echo extra\n' >> "$R/.github/workflows/check.yml"
"$CP" "$R" --to self-hosted --check 'sudo make install && sh check.sh' > "$T/out" 2>&1; check "$?" "2" "a hand-edited file and a sudo command: refused"
grep -q 'holds more than its template' "$T/out"; check "$?" "0" "…the holds-more refusal first, before --force is offered (15)"
R="$T/lr6"; newrepo "$R"; "$CP" "$R" --to self-hosted > /dev/null 2>&1
mkdir -p "$R/.helloworld"; printf '.github/dependabot.yml\n' > "$R/.helloworld/allowlist.txt"
"$CP" "$R" --to self-hosted > /dev/null 2>&1
check "$(grep -c 'runs-on: \[self-hosted, macOS\]' "$R/.github/workflows/check.yml")" "1" "another .github/ file published: the literal stays (8)"
R="$T/lr7"; newrepo "$R"; "$CP" "$R" --to self-hosted > /dev/null 2>&1
mkdir -p "$R/.opensource"; printf '.github/workflows/check.yml\n' > "$R/.opensource/allowlist.txt"
"$CP" "$R" --to self-hosted > /dev/null 2>&1
check "$(grep -cxF "    $VARLINE" "$R/.github/workflows/check.yml")" "1" "the old .opensource/ allowlist listing check.yml: the variable form (3)"

echo "the self-hosted kind: its one name, an older one read as an alias (2026-10-31)"
# ci.json files from before the rename name the kind after a runner Mac; wharf/ci-runner-kind lists such names.
printf 'buildbox\n' > "$REGATTA_CONFIG/wharf/ci-runner-kind"
provider() { python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['provider'])" "$1/.github/ci.json"; }
R="$T/k1"; newrepo "$R"
"$CP" "$R" --to self-hosted > /dev/null 2>&1; check "$?" "0" "the default name, with an alias listed: --to self-hosted"
check "$(provider "$R")" "self-hosted" "…ci.json records the kind's own name"
python3 - "$R/.github/ci.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); d["provider"] = "buildbox"; d["context"] = "my-check"
json.dump(d, open(sys.argv[1], "w"))
PY
"$CP" "$R" > "$T/out" 2>&1; check "$?" "0" "a ci.json naming the old kind: status"
grep -q 'self-hosted (ci.json, by its older name buildbox)' "$T/out"; check "$?" "0" "…reads as the kind, and says the old name"
grep -q 'no online runner labelled' "$T/out"; check "$?" "0" "…and judges its runners as the kind's"
cat > "$T/ctx.py" <<'PY'
import importlib.machinery, importlib.util, sys
loader = importlib.machinery.SourceFileLoader("cp", sys.argv[1])
spec = importlib.util.spec_from_loader("cp", loader); m = importlib.util.module_from_spec(spec); loader.exec_module(m)
print(m.required_context(sys.argv[2], m.SELF))
PY
check "$(python3 "$T/ctx.py" "$CP" "$R")" "my-check" "…its context is main's required check"
"$CP" "$R" --to self-hosted > "$T/out" 2>&1; check "$?" "0" "a re-run on the old name"
check "$(provider "$R")" "self-hosted" "…ci.json moves to the kind's own name"
check "$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['context'])" "$R/.github/ci.json")" "my-check" "…its context kept: the same kind, not a switch"
R="$T/k2"; newrepo "$R"
"$CP" "$R" --to buildbox > "$T/out" 2>&1; check "$?" "0" "--to the old name"
check "$(provider "$R")" "self-hosted" "…writes the kind's own name"
"$CP" "$R" --to buildbox --runs-on-var POOL > /dev/null 2>&1; check "$?" "0" "…and takes the kind's flags"
printf 'buildbox\nolderbox\nactions\ncircleci\nself-hosted\n' > "$REGATTA_CONFIG/wharf/ci-runner-kind"
R="$T/k3"; newrepo "$R"; printf '{"provider": "olderbox", "check": "sh check.sh"}\n' > "$R/.github/ci.json"
"$CP" "$R" > "$T/out" 2>&1; grep -q 'self-hosted (ci.json, by its older name olderbox)' "$T/out"; check "$?" "0" "a second line of the key: an alias too"
printf '{"provider": "actions", "check": "sh check.sh"}\n' > "$R/.github/ci.json"
"$CP" "$R" > "$T/out" 2>&1; grep -q 'actions (ci.json)' "$T/out"; check "$?" "0" "…a provider's own name in the key is no alias"
printf 'buildbox\n' > "$REGATTA_CONFIG/wharf/ci-runner-kind"
printf '{"provider": ["buildbox"], "check": "sh check.sh"}\n' > "$R/.github/ci.json"
"$CP" "$R" > "$T/out" 2>&1; grep -q 'Traceback' "$T/out"; check "$?" "1" "…a provider that is no string: no traceback"
rm -f "$REGATTA_CONFIG/wharf/ci-runner-kind"
R="$T/k4"; newrepo "$R"
"$CP" "$R" --to buildbox > "$T/out" 2>&1; check "$?" "2" "the key gone: the old name is no kind"
grep -q 'invalid choice' "$T/out"; check "$?" "0" "…said by the usage error"
printf '{"provider": "buildbox", "check": "sh check.sh"}\n' > "$R/.github/ci.json"
"$CP" "$R" > "$T/out" 2>&1; grep -q 'buildbox (ci.json)' "$T/out"; check "$?" "0" "…a ci.json holding it reads as it says, nothing guessed"
R="$T/k5"; newrepo "$R"; "$CP" "$R" --to self-hosted > /dev/null 2>&1; rm "$R/.github/ci.json"
"$CP" "$R" > "$T/out" 2>&1; grep -q 'self-hosted (inferred' "$T/out"; check "$?" "0" "no ci.json: the same check.yml reads as self-hosted, inferred from runs-on"

echo "the pick: lanes, budgets, the trust refusals (lighthouse-ops S1)"
# lighthouse's keys in the suite's config dir: four lanes (the runner Mac, a Linux guest, hosted ubuntu
# on one account, a CircleCI org), one budget, the log dir, and this host as the ops host. Usage is
# the desk's file, written here by hand as `lighthouse ops usage --write` would.
mkdir -p "$REGATTA_CONFIG/lighthouse" "$REGATTA_CONFIG/regatta" "$T/logs"
printf '%s\n' "$T/logs" > "$REGATTA_CONFIG/regatta/log-dir"
# --apply refuses inside a Claude Code session: the suite stands in for the desk's job
unset CLAUDECODE CLAUDE_CODE_SESSION_ID CLAUDE_UNATTENDED REGATTA_UNATTENDED
LANES="$REGATTA_CONFIG/lighthouse/ci-lanes.json"; BUDGETS="$REGATTA_CONFIG/lighthouse/ci-budgets.json"
USAGE="$T/logs/ci-usage.json"; PLOG="$T/logs/ci-pick.jsonl"
"$CP" "$T/a" --pick > "$T/out" 2>&1; check "$?" "2" "no lanes file: refused"
grep -q "no lanes: write $LANES" "$T/out"; check "$?" "0" "…naming the file to write"
cat > "$LANES" <<'EOF'
{"lanes": [
 {"name": "mac", "runs_on": ["self-hosted", "macOS", "laptop"], "runs": ["macos"]},
 {"name": "guest", "runs_on": ["self-hosted", "linux", "guest"], "runs": ["linux"]},
 {"name": "hosted", "runs_on": "ubuntu-latest", "runs": ["linux", "public"], "account": "gh-main"},
 {"name": "circle", "provider": "circleci", "runs": ["linux"], "account": "cci"}]}
EOF
cat > "$BUDGETS" <<'EOF'
{"reserve": 0.2, "accounts": {"gh-main": {"provider": "github", "user": "acme", "month_minutes": 3000, "week_share": 0.5},
 "cci": {"provider": "circleci", "org_slug": "gh/acme", "month_credits": 30000}}}
EOF
python3 -c "import sys; sys.path.insert(0, sys.argv[1]); import common; print(common.host_name())" "$M/../regatta/hooks" \
  > "$REGATTA_CONFIG/lighthouse/ops-host"
usage() { # usage <state> [month] [net] [age-s]: the desk's file for gh-main
  python3 -c 'import json,sys,time; s,m,n,age=sys.argv[2],float(sys.argv[3]),float(sys.argv[4]),int(sys.argv[5])
row={"state":s,"month_used":m,"week_used":m/2,"net_amount":n,"unit":"minutes"} if s=="ok" else {"state":s,"why":"no GITHUB_TOKEN"}
json.dump({"as_of":int(time.time())-age,"accounts":{"gh-main":row}},open(sys.argv[1],"w"))' "$USAGE" "$1" "${2:-100}" "${3:-0}" "${4:-0}"; }
MACRUN='{"total_count":1,"runners":[{"id":7,"name":"laptop","status":"online","busy":false,"labels":[{"name":"self-hosted"},{"name":"macOS"},{"name":"ARM64"},{"name":"laptop"}]}]}'
pickrepo() { # pickrepo <dir> [needs-json]: a repo in the variable form, its variable unset, private, no fork PRs
  newrepo "$1"; "$CP" "$1" --to self-hosted --runs-on-var CI_RUNS_ON > /dev/null 2>&1
  [ -n "${2:-}" ] && printf '{"provider": "self-hosted", "check": "sh check.sh", "needs": %s}\n' "$2" > "$1/.github/ci.json"
  rm -rf "$T/gh/vars" "$T/gh/runners.fail" "$T/gh/queued.json" "$PLOG" "$T/logs/ops.jsonl"
  echo true > "$T/gh/private"; echo false > "$T/gh/forkpr"; echo "$MACRUN" > "$T/gh/runners.json"; }
varval() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["value"])' "$T/gh/vars/CI_RUNS_ON.json" 2>/dev/null || echo unset; }

R="$T/pk1"; pickrepo "$R"; rm -f "$USAGE"
"$CP" "$R" --pick > "$T/out" 2>&1; check "$?" "0" "a private repo, needs absent, the runner Mac online: picked"
grep -q '  pick: mac (\["self-hosted","macOS","laptop"\])' "$T/out"; check "$?" "0" "…the Mac lane: needs absent reads as macOS"
grep -q 'lane guest: not eligible, the repo needs macos' "$T/out"; check "$?" "0" "…never guessed onto Linux: the guest is not eligible (flipping regatta whole is refused)"
check "$(varval)" "unset" "…without --apply nothing is written"
"$CP" "$R" --pick --apply > "$T/out" 2>&1; check "$?" "0" "--apply on the ops host"
check "$(varval)" '["self-hosted","macOS","laptop"]' "…the variable holds the lane's labels"
check "$(python3 -c 'import json,sys; r=json.loads(open(sys.argv[1]).readline()); print(r["from"], r["to"], r["old"], r["undo"])' "$PLOG")" \
  "hosted mac None gh api -X DELETE repos/acme/demo/actions/variables/CI_RUNS_ON" "…the flip logged: from, to, the old value, the call that undoes it"
"$CP" "$R" --pick --apply > "$T/out" 2>&1; grep -q 'pick: mac, unchanged' "$T/out"; check "$?" "0" "a second pick: unchanged"
check "$(wc -l < "$PLOG" | tr -d ' ')" "1" "…and nothing more logged: --apply writes only when the pick changed"

echo "the pick with no token: every hosted lane over budget"
R="$T/pk2"; pickrepo "$R" '["linux"]'; rm -f "$USAGE"
mkdir -p "$T/gh/vars"; echo '{"name":"CI_RUNS_ON","value":"[\"self-hosted\",\"linux\",\"guest\"]"}' > "$T/gh/vars/CI_RUNS_ON.json"
"$CP" "$R" --pick --apply > "$T/out" 2>&1; check "$?" "3" "a Linux repo, no usage file, the guest offline: exit 3, its current lane fails"
grep -q 'lane hosted: over budget, no usage at' "$T/out"; check "$?" "0" "…the hosted lane is over budget: unread usage is never a zero"
grep -q 'lane guest: refused, no online runner labelled self-hosted, linux, guest' "$T/out"; check "$?" "0" "…a lane with no online runner is refused"
grep -q 'no lane: every eligible lane is refused or over budget' "$T/out"; check "$?" "0" "…no lane: the pick fails closed"
check "$(varval)" '["self-hosted","linux","guest"]' "…and writes nothing: the variable keeps the guest's labels"
usage absent; "$CP" "$R" --pick > "$T/out" 2>&1
grep -q 'lane hosted: over budget, usage of gh-main unread (no GITHUB_TOKEN)' "$T/out"; check "$?" "0" "the desk's row with the token absent: over budget, said"
usage ok 100 0 7200; "$CP" "$R" --pick > "$T/out" 2>&1
grep -q 'over budget, usage at .* is 120 min old' "$T/out"; check "$?" "0" "usage two hours old: over budget"
usage ok 100; "$CP" "$R" --pick --apply > "$T/out" 2>&1
grep -q 'lane hosted: eligible, 2300 of 3000 minutes left above the reserve' "$T/out"; check "$?" "0" "fresh usage under the cap: eligible, what is left said"
check "$(varval)" '"ubuntu-latest"' "…--apply sets the hosted image's name"
usage ok 2500; "$CP" "$R" --pick > "$T/out" 2>&1
grep -q 'over budget, gh-main used 2500 of 3000 minutes, the reserve 20% kept' "$T/out"; check "$?" "0" "the reserve is never spent"
usage ok 100 0.5; "$CP" "$R" --pick > "$T/out" 2>&1
grep -q 'over budget, gh-main pays beyond its plan this month (netAmount 0.50)' "$T/out"; check "$?" "0" "netAmount above zero: over budget"
python3 -c 'import json,sys,time; json.dump({"as_of":int(time.time()),"accounts":{"gh-main":{"state":"ok","month_used":100,"week_used":1600,"net_amount":0}}},open(sys.argv[1],"w"))' "$USAGE"
"$CP" "$R" --pick > "$T/out" 2>&1
grep -q 'gh-main used 1600 minutes this week, its share 1500' "$T/out"; check "$?" "0" "over the week share: over budget"
grep -q 'lane circle: CircleCI, advisory' "$T/out"; check "$?" "0" "a CircleCI lane is reported, never picked"

echo "the pick: the Linux share (CI_LINUX_ELSEWHERE) by the CircleCI lane's budget (ci-budgets)"
cp "$T/gh/rsc.json" "$T/gh/rsc.keep"; R="$T/pk2s"; pickrepo "$R"; echo '      # the share: vars.CI_LINUX_ELSEWHERE' >> "$R/.github/workflows/check.yml"
cusage() { # cusage <credits used this month>: the desk's file for cci, gh-main under budget
  python3 -c 'import json,sys,time; m=float(sys.argv[2])
json.dump({"as_of":int(time.time()),"accounts":{"cci":{"state":"ok","month_used":m,"week_used":0,"net_amount":0,"unit":"credits"},
 "gh-main":{"state":"ok","month_used":100,"week_used":50,"net_amount":0,"unit":"minutes"}}},open(sys.argv[1],"w"))' "$USAGE" "$1"; }
share() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["value"])' "$T/gh/vars/CI_LINUX_ELSEWHERE.json" 2>/dev/null || echo unset; }
mkdir -p "$T/gh/vars"; echo '{"name":"CI_LINUX_ELSEWHERE","value":"true"}' > "$T/gh/vars/CI_LINUX_ELSEWHERE.json"
echo '{"strict":false,"contexts":["check","ci/circleci: check-linux"],"checks":[{"context":"check","app_id":null},{"context":"ci/circleci: check-linux","app_id":-1}]}' > "$T/gh/rsc.json"
cusage 1000; "$CP" "$R" --pick > "$T/out" 2>&1
grep -q 'share CI_LINUX_ELSEWHERE: true, stays (lane circle: 22900 of 30000 credits left above the reserve)' "$T/out"; check "$?" "0" "the share on, CircleCI under budget: stays on, the margin counted"
cusage 23000; "$CP" "$R" --pick > "$T/out" 2>&1
grep -q 'share CI_LINUX_ELSEWHERE: true → false (lane circle: cci used 25300 of 30000 credits, the reserve 20% kept)' "$T/out"; check "$?" "0" "CircleCI past its reserve: the share goes off"
check "$(share)" "true" "…without --apply nothing is written"
"$CP" "$R" --pick --apply > "$T/out" 2>&1; check "$?" "0" "--apply on the ops host"
check "$(share)" "false" "…the share off: the runner Mac takes the whole line"
check "$(python3 -c 'import json,sys; r=[json.loads(l) for l in open(sys.argv[1])]; r=[x for x in r if x["variable"]=="CI_LINUX_ELSEWHERE"][0]; print(r["from"], r["to"], r["lane"], r["undo"])' "$PLOG")" \
  "true false circle gh api -X PATCH repos/acme/demo/actions/variables/CI_LINUX_ELSEWHERE -f name=CI_LINUX_ELSEWHERE -f value=true" "…logged with the PATCH that undoes it"
"$CP" "$R" --pick > "$T/out" 2>&1
grep -q 'share CI_LINUX_ELSEWHERE: false, stays (lane circle: cci used 25300' "$T/out"; check "$?" "0" "…and stays off while over budget"
cusage 1000; echo '{"strict":false,"contexts":["check"],"checks":[{"context":"check","app_id":null}]}' > "$T/gh/rsc.json"
"$CP" "$R" --pick --apply > "$T/out" 2>&1
grep -q "share CI_LINUX_ELSEWHERE: false, stays: lane circle is under budget, but main does not require check-linux, so a red Linux run would block nothing" "$T/out"; check "$?" "0" "under budget, check-linux not required: the share stays off (the rollout's order)"
check "$(share)" "false" "…nothing written"
mv "$T/gh/rsc.json" "$T/gh/rsc.away"; "$CP" "$R" --pick --apply > "$T/out" 2>&1
grep -q "share CI_LINUX_ELSEWHERE: false, stays: lane circle is under budget, but main's required checks unread" "$T/out"; check "$?" "0" "…the protection unread: never taken for required"
echo '{"strict":false,"contexts":["check","ci/circleci: check-linux"],"checks":[{"context":"check","app_id":null},{"context":"ci/circleci: check-linux","app_id":-1}]}' > "$T/gh/rsc.json"
"$CP" "$R" --pick --apply > "$T/out" 2>&1
grep -q 'share CI_LINUX_ELSEWHERE: false, stays: lane circle is under budget, but the share went off 0 min ago (on waits 60 min)' "$T/out"; check "$?" "0" "under budget, required, but off moments ago: held (a budget near its line flaps)"
check "$(share)" "false" "…nothing written"
backdate() { python3 -c 'import json,sys; r=[json.loads(l) for l in open(sys.argv[1])]
for x in r: x["at"]-=7200 if x.get("variable")=="CI_LINUX_ELSEWHERE" else 0
open(sys.argv[1],"w").write("".join(json.dumps(x)+"\n" for x in r))' "$PLOG"; }
backdate
CLAUDE_CODE_SESSION_ID=s-1 "$CP" "$R" --pick --apply > "$T/out" 2>&1; check "$?" "2" "the share's --apply inside a Claude Code session: refused"
check "$(share)" "false" "…nothing written"
"$CP" "$R" --pick --apply > "$T/out" 2>&1
grep -q 'share CI_LINUX_ELSEWHERE: false → true' "$T/out"; check "$?" "0" "under budget, check-linux required, off two hours ago: said…"
check "$(share)" "true" "…and the share back on"
echo '{"strict":false,"contexts":["check"],"checks":[{"context":"check","app_id":null}]}' > "$T/gh/rsc.json"
"$CP" "$R" --pick --apply > "$T/out" 2>&1
grep -q 'share CI_LINUX_ELSEWHERE: true → false (lane circle: main does not require check-linux)' "$T/out"; check "$?" "0" "on, under budget, main no longer requires check-linux: said…"
check "$(share)" "false" "…and the share off (a red Linux run would block nothing)"
echo '{"strict":false,"contexts":["check","ci/circleci: check-linux"],"checks":[{"context":"check","app_id":null},{"context":"ci/circleci: check-linux","app_id":-1}]}' > "$T/gh/rsc.json"
echo '{"name":"CI_LINUX_ELSEWHERE","value":"true"}' > "$T/gh/vars/CI_LINUX_ELSEWHERE.json"
rm -f "$USAGE"; "$CP" "$R" --pick --apply > "$T/out" 2>&1
grep -q 'share CI_LINUX_ELSEWHERE: true → false (lane circle: no usage at' "$T/out"; check "$?" "0" "no usage: said…"
check "$(share)" "false" "…and the share goes off (fail closed, as a hosted lane)"
rm -f "$T/gh/vars/CI_LINUX_ELSEWHERE.json" "$T/gh/rsc.away"; mv "$T/gh/rsc.keep" "$T/gh/rsc.json"
check "$(python3 -c 'import importlib.machinery as m, importlib.util as u, os, sys; l=m.SourceFileLoader("cp", sys.argv[1]); c=u.module_from_spec(u.spec_from_loader("cp", l)); l.exec_module(c); os.environ["PATH"]=sys.argv[2]; print(c.gh("repos/acme/demo"))' "$CP" "$T/empty-path")" \
  "(False, 'gh is not on PATH')" "a shell whose PATH lacks gh (a plain ssh shell on the ops host): unread, never a traceback"

echo "the pick: the Linux share moves between two CircleCI orgs (ci-two-orgs)"
cp "$LANES" "$T/lanes.two"; cp "$BUDGETS" "$T/budgets.two"; cp "$T/gh/rsc.json" "$T/gh/rsc.two"
SLUG_O=gh/acme/demo; SLUG_A=circleci/ORG/PROJ
cat > "$LANES" <<'EOF'
{"lanes": [
 {"name": "mac", "runs_on": ["self-hosted", "macOS", "laptop"], "runs": ["macos"]},
 {"name": "oauth", "provider": "circleci", "runs": ["linux"], "account": "cci-o", "projects": {"acme/demo": "gh/acme/demo"}},
 {"name": "app", "provider": "circleci", "runs": ["linux"], "account": "cci-a", "projects": {"acme/demo": "circleci/ORG/PROJ"}}]}
EOF
cat > "$BUDGETS" <<'EOF'
{"reserve": 0.2, "accounts": {"cci-o": {"provider": "circleci", "org_slug": "gh/acme", "month_credits": 30000},
 "cci-a": {"provider": "circleci", "org_slug": "circleci/ORG", "month_credits": 30000}}}
EOF
ousage() { # ousage <oauth's month or `unread`> <app's month or `unread`>: the desk's file for both orgs
  python3 -c 'import json,sys,time
def row(v): return {"state":"unread","why":"no token"} if v=="unread" else {"state":"ok","month_used":float(v),"week_used":0,"net_amount":0,"unit":"credits"}
json.dump({"as_of":int(time.time()),"accounts":{"cci-o":row(sys.argv[2]),"cci-a":row(sys.argv[3])}},open(sys.argv[1],"w"))' "$USAGE" "$1" "$2"; }
# project: the variable's value, `unset` with none
project() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["value"])' "$T/gh/vars/CI_LINUX_TARGET.json" 2>/dev/null || echo unset; }
setvar() { printf '{"name":"%s","value":"%s"}\n' "$1" "$2" > "$T/gh/vars/$1.json"; }
tworepo() { # tworepo <dir>: the share on, its trigger reading the variable, the file naming the OAuth project
  pickrepo "$1"; echo '      # the share: vars.CI_LINUX_ELSEWHERE' >> "$1/.github/workflows/check.yml"
  mkdir -p "$1/.circleci" "$T/gh/vars"; printf '# a comment first\n%s\n' "$SLUG_O" > "$1/.circleci/project-slug"
  echo '          PROJECT: ${{ vars.CI_LINUX_TARGET }}' > "$1/.github/workflows/check-linux.yml"
  setvar CI_LINUX_ELSEWHERE true
  echo '{"strict":false,"contexts":["check","ci/circleci: check-linux"],"checks":[{"context":"check","app_id":null},{"context":"ci/circleci: check-linux","app_id":-1}]}' > "$T/gh/rsc.json"; }
backproj() { python3 -c 'import json,sys; r=[json.loads(l) for l in open(sys.argv[1])]
for x in r: x["at"]-=7200
open(sys.argv[1],"w").write("".join(json.dumps(x)+"\n" for x in r))' "$PLOG"; }
logrow() { python3 -c 'import json,sys; r=[json.loads(l) for l in open(sys.argv[1])]; r=[x for x in r if x["variable"]==sys.argv[2]][-1]; print(r["from"], r["to"], r["lane"], r["undo"])' "$PLOG" "$1"; }

R="$T/two"; tworepo "$R"
ousage 1000 2000; "$CP" "$R" --pick --apply > "$T/out" 2>&1; check "$?" "0" "both orgs under budget, the file names the one with more left: exit 0"
grep -q 'share lane oauth: eligible, 22900 of 30000 credits left above the reserve' "$T/out"; check "$?" "0" "…each lane's reading said"
grep -q 'share CI_LINUX_ELSEWHERE: true, stays (lane oauth:' "$T/out"; check "$?" "0" "…the current lane with the most left stays: the variable unset reads as the file's project"
check "$(project)" "unset" "…nothing moved, nothing written"
ousage 23000 1000; "$CP" "$R" --pick > "$T/out" 2>&1; check "$?" "0" "oauth → app: oauth past its reserve, app under"
grep -q 'share lane oauth: not chosen, cci-o used 25300 of 30000 credits, the reserve 20% kept' "$T/out"; check "$?" "0" "…the lane that is out said"
grep -q "share CI_LINUX_TARGET: $SLUG_O → $SLUG_A (lane app: 22900 of 30000 credits left above the reserve)" "$T/out"; check "$?" "0" "…the move said, from the file's project"
check "$(project)" "unset" "…without --apply nothing is written"
CLAUDE_CODE_SESSION_ID=s-1 "$CP" "$R" --pick --apply > "$T/out" 2>&1; check "$?" "2" "the move's --apply inside a Claude Code session: refused"
check "$(project)" "unset" "…nothing written"
"$CP" "$R" --pick --apply > "$T/out" 2>&1; check "$?" "0" "--apply on the ops host"
check "$(project)" "$SLUG_A" "…the project moved to the App org's"
check "$(share)" "true" "…the share stays on: only the org moved"
check "$(logrow CI_LINUX_TARGET)" "$SLUG_O $SLUG_A app gh api -X DELETE repos/acme/demo/actions/variables/CI_LINUX_TARGET" "…logged with the DELETE that sends the trigger back to the file"
"$CP" "$R" --pick --apply > "$T/out" 2>&1; check "$(grep -c CI_LINUX_TARGET "$PLOG")" "1" "a second pass: nothing more logged"
ousage 1000 23000; "$CP" "$R" --pick --apply > "$T/out" 2>&1; check "$?" "0" "app → oauth: app past its reserve, moments after the last move"
check "$(project)" "$SLUG_O" "…moved at once: a lane that is out is left whatever the hold says"
check "$(share)" "true" "…the share still on"
check "$(logrow CI_LINUX_TARGET)" "$SLUG_A $SLUG_O oauth gh api -X PATCH repos/acme/demo/actions/variables/CI_LINUX_TARGET -f name=CI_LINUX_TARGET -f value=$SLUG_A" "…logged with the PATCH that undoes it"
grep -v '"CI_RUNS_ON"' "$PLOG" > "$T/plog.moves"; cp "$T/plog.moves" "$PLOG"   # the Mac lane's own flip aside
check "$(python3 -c 'import importlib.machinery as m, importlib.util as u, sys; l=m.SourceFileLoader("cp", sys.argv[1]); c=u.module_from_spec(u.spec_from_loader("cp", l)); l.exec_module(c); print(c.last_flip("acme/demo"))' "$CP")" \
  "0" "a project move is no runs-on flip: it hides no queued run from stale_lane"
ousage 9000 1000; "$CP" "$R" --pick --apply > "$T/out" 2>&1
grep -q "share CI_LINUX_TARGET: stays on lane oauth: lane app has more left, but the project moved 0 min ago (a move waits 60 min)" "$T/out"; check "$?" "0" "both under, the other has more, moved moments ago: held (two orgs near one reading would swap)"
check "$(project)" "$SLUG_O" "…nothing written"
backproj; "$CP" "$R" --pick --apply > "$T/out" 2>&1
check "$(project)" "$SLUG_A" "…past the hold: the lane with the most month left takes it"
ousage 1000 1000; backproj; "$CP" "$R" --pick --apply > "$T/out" 2>&1
check "$(project)" "$SLUG_A" "a tie stays where it is"

R="$T/two2"; tworepo "$R"
ousage 23000 23000; "$CP" "$R" --pick --apply > "$T/out" 2>&1; check "$?" "0" "both orgs over"
grep -q 'share CI_LINUX_ELSEWHERE: true → false (lane oauth: cci-o used 25300' "$T/out"; check "$?" "0" "…the share goes off, the lane it stands on named"
check "$(share)" "false" "…off: the runner takes the whole line"
check "$(project)" "unset" "…and the project is left as it is"
ousage 23000 1000; "$CP" "$R" --pick --apply > "$T/out" 2>&1
grep -q 'share CI_LINUX_ELSEWHERE: false, stays: lane app is under budget, but the share went off 0 min ago' "$T/out"; check "$?" "0" "one org back under, off moments ago: held"
check "$(project)" "unset" "…and nothing moved: an off share has no use for a project"
backproj; echo '{"strict":false,"contexts":["check"],"checks":[{"context":"check","app_id":null}]}' > "$T/gh/rsc.json"
"$CP" "$R" --pick --apply > "$T/out" 2>&1
grep -q 'share CI_LINUX_ELSEWHERE: false, stays: lane app is under budget, but main does not require check-linux' "$T/out"; check "$?" "0" "one org under, check-linux not required: the share stays off"
check "$(project)" "unset" "…nothing moved"
echo '{"strict":false,"contexts":["check","ci/circleci: check-linux"],"checks":[{"context":"check","app_id":null},{"context":"ci/circleci: check-linux","app_id":-1}]}' > "$T/gh/rsc.json"
touch "$T/gh/vars/CI_LINUX_TARGET.refuse"; "$CP" "$R" --pick --apply > "$T/out" 2>&1; check "$?" "3" "the project's write refused on the way on: exit 3"
grep -q '⚠ share CI_LINUX_TARGET not written: GitHub refused' "$T/out"; check "$?" "0" "…said"
check "$(share)" "false" "…and the share stays off: never on at the org the pick judged out"
rm -f "$T/gh/vars/CI_LINUX_TARGET.refuse"; "$CP" "$R" --pick --apply > "$T/out" 2>&1; check "$?" "0" "the write goes through"
check "$(project)" "$SLUG_A" "…the project written…"
check "$(share)" "true" "…and the share on, at the org under budget"
check "$(python3 -c 'import json,sys; print(" ".join(x["variable"] for x in map(json.loads, open(sys.argv[1]))))' "$PLOG" | sed 's/.* \(CI_LINUX_TARGET CI_LINUX_ELSEWHERE\)$/\1/')" "CI_LINUX_TARGET CI_LINUX_ELSEWHERE" "…in that order"

R="$T/two5"; tworepo "$R"; touch "$T/gh/vars/CI_LINUX_TARGET.refuse"
ousage 23000 1000; "$CP" "$R" --pick --apply > "$T/out" 2>&1; check "$?" "3" "on, its lane out, the move refused: exit 3"
check "$(share)" "false" "…and the share off: it never runs at an org the pick judged out"
grep -q 'share CI_LINUX_ELSEWHERE: true → false (lane oauth: it is out, and the move to lane app was refused)' "$T/out"; check "$?" "0" "…naming the lane it left"
check "$(project)" "unset" "…the project where it was"
setvar CI_LINUX_ELSEWHERE true; ousage 9000 1000; rm -f "$PLOG"; "$CP" "$R" --pick --apply > "$T/out" 2>&1; check "$?" "3" "on, its lane still able, a better one's move refused: exit 3"
check "$(share)" "true" "…and the share stays on, where it can run"
rm -f "$T/gh/vars/CI_LINUX_TARGET.refuse"
echo '{"strict":false,"contexts":["check"],"checks":[{"context":"check","app_id":null}]}' > "$T/gh/rsc.json"
"$CP" "$R" --pick --apply > "$T/out" 2>&1
check "$(project) $(share)" "unset false" "on, a lane with more left, main no longer requiring check-linux: off, and no move"
R="$T/two10"; tworepo "$R"; setvar CI_LINUX_ELSEWHERE false; touch "$T/gh/vars/CI_LINUX_TARGET.refuse"; ousage 9000 1000
"$CP" "$R" --pick --apply > "$T/out" 2>&1; check "$?" "3" "off, its lane able, a better one's move refused on the way on: exit 3"
check "$(project) $(share)" "unset true" "…on where it stands, which can run it"
check "$(logrow CI_LINUX_ELSEWHERE | cut -d' ' -f1-3)" "false true oauth" "…and the log names the lane it came on at, not the refused one"
rm -f "$T/gh/vars/CI_LINUX_TARGET.refuse"
R="$T/two6"; tworepo "$R"; setvar CI_LINUX_TARGET "$SLUG_A"; ousage 23000 23000; "$CP" "$R" --pick > "$T/out" 2>&1
grep -q 'share CI_LINUX_ELSEWHERE: true → false (lane app: cci-a used 25300' "$T/out"; check "$?" "0" "both over, standing on the second lane: that lane named"
setvar CI_LINUX_TARGET "$SLUG_A "; ousage 9000 1000; "$CP" "$R" --pick --apply > "$T/out" 2>&1
check "$(project)" "$SLUG_A" "a padded variable, which the trigger would refuse, reads as no lane's and is rewritten"
printf 'gh/acme/demo \n' > "$R/.circleci/project-slug"; rm -f "$T/gh/vars/CI_LINUX_TARGET.json"; rm -f "$PLOG"; ousage 1000 2000; "$CP" "$R" --pick --apply > "$T/out" 2>&1
check "$(project)" "$SLUG_O" "a file line the trigger would refuse reads as no lane's: the variable takes over"
printf 'gh/acme/demo\r\n' > "$R/.circleci/project-slug"; rm -f "$T/gh/vars/CI_LINUX_TARGET.json" "$PLOG"; "$CP" "$R" --pick --apply > "$T/out" 2>&1
check "$(project)" "$SLUG_O" "…a CR too, which grep keeps: the pick reads the line as the trigger does"
printf '# a comment first\n%s\n' "$SLUG_O" > "$R/.circleci/project-slug"
R="$T/two8"; tworepo "$R"; setvar CI_LINUX_TARGET circleci/ORG/THIRD; touch "$T/gh/vars/CI_LINUX_TARGET.refuse"; ousage 1000 2000
"$CP" "$R" --pick --apply > "$T/out" 2>&1; check "$?" "3" "on a project no lane names, the move refused: exit 3"
check "$(share)" "false" "…off: where it runs is judged by nobody"
grep -q 'true → false (lane oauth: no lane names its project, and the move to lane oauth was refused)' "$T/out"; check "$?" "0" "…saying so, no lane called out"
rm -f "$T/gh/vars/CI_LINUX_TARGET.refuse"
cp "$LANES" "$T/lanes.named"
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); [x.pop("projects",None) for x in d["lanes"]]; json.dump(d,open(sys.argv[1],"w"))' "$LANES"
R="$T/two7"; tworepo "$R"; touch "$T/gh/vars/CI_LINUX_TARGET.unread"; ousage 1000 23000; "$CP" "$R" --pick --apply > "$T/out" 2>&1
check "$(share)" "true" "two lanes, neither naming a project, the variable unread: a healthy share stays on"
setvar CI_LINUX_ELSEWHERE false; rm -f "$PLOG"; "$CP" "$R" --pick --apply > "$T/out" 2>&1
check "$(share)" "false" "…and an off one does not come on: the variable may be one left behind"
setvar CI_LINUX_ELSEWHERE true; rm -f "$T/gh/vars/CI_LINUX_TARGET.unread"; "$CP" "$R" --pick --apply > "$T/out" 2>&1
grep -q 'share CI_LINUX_ELSEWHERE: true, stays (lane oauth:' "$T/out"; check "$?" "0" "two lanes, neither naming a project, the variable unset: the first judged, as before"
setvar CI_LINUX_TARGET "$SLUG_A"; "$CP" "$R" --pick --apply > "$T/out" 2>&1
grep -q "share CI_LINUX_ELSEWHERE: true → false (lane oauth: CI_LINUX_TARGET holds $SLUG_A, which no lane names)" "$T/out"; check "$?" "0" "neither naming one, a variable left behind: the trigger goes where no lane is judged, so off"
check "$(share)" "false" "…off"
"$CP" "$R" --pick --apply > "$T/out" 2>&1; check "$?" "3" "…and every pass says so with exit 3 until someone clears it"
setvar CI_LINUX_ELSEWHERE true; "$CP" "$R" --pick > "$T/out" 2>&1; check "$?" "3" "…a pass without --apply as well"
setvar CI_LINUX_ELSEWHERE true; setvar CI_LINUX_TARGET "$SLUG_O"; "$CP" "$R" --pick --apply > "$T/out" 2>&1
check "$(share)" "true" "neither naming one, the variable equal to the file: nothing left behind"
setvar CI_LINUX_TARGET "$SLUG_A"; : > "$R/.github/workflows/check-linux.yml"; "$CP" "$R" --pick --apply > "$T/out" 2>&1
check "$(share)" "true" "neither naming one, a trigger that ignores the variable: it steers nothing"
cp "$T/lanes.named" "$LANES"
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); d["lanes"][2].pop("projects"); json.dump(d,open(sys.argv[1],"w"))' "$LANES"
R="$T/two9"; tworepo "$R"; touch "$T/gh/vars/CI_LINUX_TARGET.unread"; ousage 1000 23000
"$CP" "$R" --pick --apply > "$T/out" 2>&1
check "$(share)" "true" "unread, and only a lane that names no project out: the share cannot stand there"
cp "$T/lanes.named" "$LANES"; : > "$R/.github/workflows/check-linux.yml"; ousage 23000 1000; "$CP" "$R" --pick --apply > "$T/out" 2>&1
check "$(share)" "false" "unread, a trigger that ignores it, the file's lane out: where it stands is known, so off"
setvar CI_LINUX_ELSEWHERE true; ousage 1000 23000; "$CP" "$R" --pick --apply > "$T/out" 2>&1
check "$(share)" "true" "…the file's lane able, another out: it stays, on the lane it is known to stand on"
rm -f "$T/gh/vars/CI_LINUX_TARGET.unread"
cp "$T/lanes.named" "$LANES"

R="$T/two3"; tworepo "$R"; setvar CI_LINUX_TARGET "$SLUG_A"
ousage 1000 unread; "$CP" "$R" --pick --apply > "$T/out" 2>&1; check "$?" "0" "one org unread, and the share on it"
grep -q 'share lane app: not chosen, usage of cci-a unread (no token)' "$T/out"; check "$?" "0" "…unread never counts as left"
check "$(project)" "$SLUG_O" "…the project leaves it, at once"
ousage unread 1000; backproj; "$CP" "$R" --pick --apply > "$T/out" 2>&1
check "$(project)" "$SLUG_A" "the other one unread: the same, the other way"
ousage 1000 unread; rm -f "$PLOG"; setvar CI_LINUX_ELSEWHERE false; setvar CI_LINUX_TARGET "$SLUG_A"; "$CP" "$R" --pick --apply > "$T/out" 2>&1
check "$(project) $(share)" "$SLUG_O true" "off, coming on, the project on the unread org: it comes on at the one that reads"
ousage unread unread; "$CP" "$R" --pick --apply > "$T/out" 2>&1; check "$(share)" "false" "both unread: the share goes off (fail closed)"
setvar CI_LINUX_ELSEWHERE true; rm -f "$USAGE"; "$CP" "$R" --pick --apply > "$T/out" 2>&1
grep -q 'share lane oauth: not chosen, no usage at' "$T/out"; check "$?" "0" "no usage file: both lanes not chosen…"
check "$(share)" "false" "…and the share off"

R="$T/two4"; tworepo "$R"; touch "$T/gh/vars/CI_LINUX_TARGET.unread"; ousage 23000 1000
"$CP" "$R" --pick --apply > "$T/out" 2>&1; check "$?" "0" "the project variable unread, a lane out: not a failure"
grep -q 'share CI_LINUX_TARGET: unread' "$T/out"; check "$?" "0" "…said"
grep -q 'share CI_LINUX_ELSEWHERE: true → false (lane oauth: CI_LINUX_TARGET is unread, and a lane it may stand on is out)' "$T/out"; check "$?" "0" "…naming the lane that is out, not the able one"
check "$(project)" "unset" "…nothing moved: what stands is unknown"
check "$(share)" "false" "…and the share off, which needs no project, for it may stand on that lane"
setvar CI_LINUX_ELSEWHERE true
ousage 1000 2000; "$CP" "$R" --pick --apply > "$T/out" 2>&1; check "$?" "0" "unread, every lane able: exit 0"
check "$(share)" "true" "…the share left as it is"
echo '{"strict":false,"contexts":["check"],"checks":[{"context":"check","app_id":null}]}' > "$T/gh/rsc.json"
"$CP" "$R" --pick --apply > "$T/out" 2>&1; check "$(share)" "false" "unread, a lane able, main no longer requiring check-linux: off, which needs no project"
setvar CI_LINUX_ELSEWHERE true
echo '{"strict":false,"contexts":["check","ci/circleci: check-linux"],"checks":[{"context":"check","app_id":null},{"context":"ci/circleci: check-linux","app_id":-1}]}' > "$T/gh/rsc.json"
ousage 23000 23000; "$CP" "$R" --pick --apply > "$T/out" 2>&1
check "$(share)" "false" "unread, and no lane under budget: the share still goes off, which needs no project"
ousage 1000 23000; backproj; "$CP" "$R" --pick --apply > "$T/out" 2>&1; check "$?" "0" "unread, off, a lane under: exit 0"
grep -q 'share CI_LINUX_TARGET: unread' "$T/out"; check "$?" "0" "…said"
check "$(share)" "false" "…and it does not come on: nowhere known to come on at"
setvar CI_LINUX_ELSEWHERE true
rm -f "$T/gh/vars/CI_LINUX_TARGET.unread"
ousage 23000 1000; printf '# the variable, in a comment: CI_LINUX_TARGET\n' > "$R/.github/workflows/check-linux.yml"; "$CP" "$R" --pick --apply > "$T/out" 2>&1
grep -q 'share lane app: not chosen, check-linux.yml reads no CI_LINUX_TARGET, so its project is out of reach' "$T/out"; check "$?" "0" "a trigger that reads no variable: a move there would move nothing"
check "$(project)" "unset" "…nothing written"
check "$(share)" "false" "…and with oauth over, the share goes off"
setvar CI_LINUX_ELSEWHERE true; setvar CI_LINUX_TARGET "$SLUG_A"; rm -f "$PLOG"; ousage 1000 23000; "$CP" "$R" --pick --apply > "$T/out" 2>&1
grep -q 'share CI_LINUX_ELSEWHERE: true, stays (lane oauth:' "$T/out"; check "$?" "0" "the variable on the App org, a trigger that ignores it: the file's org is where the share stands"
check "$(share)" "true" "…so it stays on, judged by that org"
rm -f "$T/gh/vars/CI_LINUX_TARGET.json"
setvar CI_LINUX_ELSEWHERE true; rm -f "$R/.github/workflows/check-linux.yml" "$PLOG"; ousage 1000 2000; "$CP" "$R" --pick --apply > "$T/out" 2>&1
grep -q 'share CI_LINUX_ELSEWHERE: true, stays (lane oauth:' "$T/out"; check "$?" "0" "no check-linux.yml at all: the file's project still stands"
echo '          PROJECT: ${{ vars.CI_LINUX_TARGET }}' > "$R/.github/workflows/check-linux.yml"
sed -i.bak 's/"projects": {"acme\/demo": "circleci\/ORG\/PROJ"}/"projects": {"acme\/other": "circleci\/ORG\/PROJ"}/' "$LANES" && rm -f "$LANES.bak"
ousage 23000 1000; "$CP" "$R" --pick --apply > "$T/out" 2>&1
grep -q 'share lane app: not chosen, names no project for acme/demo' "$T/out"; check "$?" "0" "a lane that names another repo's project only: never this repo's"
check "$(project) $(share)" "unset false" "…nothing moved, and the share off: oauth is over"
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); d["lanes"][2]["projects"]=["circleci/ORG/PROJ"]; json.dump(d,open(sys.argv[1],"w"))' "$LANES"
"$CP" "$R" --pick > "$T/out" 2>&1; check "$?" "2" "a lane's projects that is no map: refused"
grep -q "lane app's \`projects\` maps" "$T/out"; check "$?" "0" "…naming the lane"
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); d["lanes"][2]["projects"]={"acme/demo":"not a slug"}; json.dump(d,open(sys.argv[1],"w"))' "$LANES"
"$CP" "$R" --pick > "$T/out" 2>&1; check "$?" "2" "a project that is no slug: refused at the pick, never a held pull request"
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); d["lanes"][2]["projects"]={"demo":"circleci/ORG/PROJ"}; json.dump(d,open(sys.argv[1],"w"))' "$LANES"
"$CP" "$R" --pick > "$T/out" 2>&1; check "$?" "2" "a key that is no <owner>/<repo>: refused"
cp "$T/lanes.two" "$LANES"; cp "$T/budgets.two" "$BUDGETS"; mv "$T/gh/rsc.two" "$T/gh/rsc.json"; rm -rf "$T/gh/vars"; rm -f "$PLOG"

echo "the pick: the Linux share on GitHub Actions beside the CircleCI orgs (linux-on-actions)"
cp "$LANES" "$T/lanes.gha"; cp "$BUDGETS" "$T/budgets.gha"; cp "$T/gh/rsc.json" "$T/gh/rsc.gha"
cat > "$LANES" <<'EOF'
{"lanes": [
 {"name": "mac", "runs_on": ["self-hosted", "macOS", "laptop"], "runs": ["macos"]},
 {"name": "oauth", "provider": "circleci", "runs": ["linux"], "account": "cci-o", "projects": {"acme/demo": "gh/acme/demo"}},
 {"name": "app", "provider": "circleci", "runs": ["linux"], "account": "cci-a", "projects": {"acme/demo": "circleci/ORG/PROJ"}},
 {"name": "gha", "runs_on": "ubuntu-latest", "runs": ["linux", "public"], "account": "gh-u", "projects": {"acme/demo": "actions"}}]}
EOF
cat > "$BUDGETS" <<'EOF'
{"reserve": 0.2, "accounts": {"cci-o": {"provider": "circleci", "org_slug": "gh/acme", "month_credits": 30000},
 "cci-a": {"provider": "circleci", "org_slug": "circleci/ORG", "month_credits": 30000},
 "gh-u": {"provider": "github", "user": "acme", "month_minutes": 3000}}}
EOF
gusage() { # gusage <oauth credits> <app credits> <github minutes>: the desk's file for all three accounts
  python3 -c 'import json,sys,time
def row(v, u): return {"state":"ok","month_used":float(v),"week_used":0,"net_amount":0,"unit":u}
json.dump({"as_of":int(time.time()),"accounts":{"cci-o":row(sys.argv[2],"credits"),"cci-a":row(sys.argv[3],"credits"),"gh-u":row(sys.argv[4],"minutes")}},open(sys.argv[1],"w"))' "$USAGE" "$1" "$2" "$3"; }
R="$T/gha"; tworepo "$R"; setvar CI_LINUX_ELSEWHERE false; rm -f "$PLOG"
gusage 29443 33299 2; "$CP" "$R" --pick --apply > "$T/out" 2>&1; check "$?" "0" "both CircleCI orgs over, GitHub's minutes under: exit 0"
grep -q 'share CI_LINUX_TARGET: gh/acme/demo → actions (lane gha: 2398 of 3000 minutes left above the reserve)' "$T/out"; check "$?" "0" "…the Actions lane judged by the GitHub minutes"
grep -q 'share lane oauth: not chosen, an Actions lane runs the share for acme/demo' "$T/out"; check "$?" "0" "…the CircleCI lanes read and said, not chosen"
check "$(project) $(share)" "actions true" "…the target moves to actions, then the share comes on"
check "$(logrow CI_LINUX_TARGET)" "gh/acme/demo actions gha gh api -X DELETE repos/acme/demo/actions/variables/CI_LINUX_TARGET" "…the move logged with its undo (created: a DELETE, back to the file's project)"
rm -f "$PLOG"; setvar CI_LINUX_TARGET actions
gusage 10000 33299 100; "$CP" "$R" --pick > "$T/out" 2>&1
grep -q 'share CI_LINUX_ELSEWHERE: true, stays (lane gha:' "$T/out"; check "$?" "0" "13,000 credits left (43%) against 2,300 minutes (77%): the share of the month left decides, never the raw number"
gusage 1000 33299 2500; "$CP" "$R" --pick > "$T/out" 2>&1
grep -q "share lane oauth: not chosen, an Actions lane runs the share for acme/demo" "$T/out"; check "$?" "0" "GitHub's minutes past the reserve, OAuth has credits: CircleCI is read, never chosen once the Actions lane is in the file"
grep -q "actions → gh/acme/demo" "$T/out"; check "$?" "1" "…the target never moves back to CircleCI"
gusage 29443 33299 2500; "$CP" "$R" --pick --apply > "$T/out" 2>&1
check "$(share)" "false" "every lane out: the share off, the Macs take the whole line"
rm -f "$T/gh/rsc.json" "$PLOG"; setvar CI_LINUX_ELSEWHERE false
echo '{"name":"main","protected":true,"protection":{"required_status_checks":{"contexts":["check","ci/circleci: check-linux"],"checks":[{"context":"check","app_id":null},{"context":"ci/circleci: check-linux","app_id":null}]}}}' > "$T/gh/branch.json"
gusage 29443 33299 2; "$CP" "$R" --pick --apply > "$T/out" 2>&1
check "$(share)" "true" "the protection endpoint refused (not an admin), the branch's own read names check-linux: the share comes on (logbook #6)"
rm -f "$T/gh/branch.json"; setvar CI_LINUX_ELSEWHERE false; rm -f "$PLOG"
"$CP" "$R" --pick --apply > "$T/out" 2>&1
grep -q "main's required checks unread" "$T/out"; check "$?" "0" "neither read answers: said unread"
check "$(share)" "false" "…never taken for required, the share stays off"
echo '{"name":"main","protected":true,"protection":{"enabled":false,"required_status_checks":{"enforcement_level":"off","contexts":[],"checks":[]}}}' > "$T/gh/branch.json"
"$CP" "$R" --pick --apply > "$T/out" 2>&1
grep -q "main's required checks unread" "$T/out"; check "$?" "0" "the branch's read lists nothing (a ruleset, or protection it cannot see): the protection endpoint judges, unread here"
check "$(share)" "false" "…never read as \"not required\""
rm -f "$T/gh/branch.json"
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); d["lanes"][3]["projects"]={"acme/demo":"gh/acme/demo"}; json.dump(d,open(sys.argv[1],"w"))' "$LANES"
"$CP" "$R" --pick > "$T/out" 2>&1; check "$?" "2" "an Actions lane whose target is a CircleCI project: refused"
grep -q "lane gha's \`projects\` maps" "$T/out"; check "$?" "0" "…naming the lane"
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); d["lanes"][3]["projects"]={"acme/demo":"actions"}; d["lanes"][0]["projects"]={"acme/demo":"actions"}; json.dump(d,open(sys.argv[1],"w"))' "$LANES"
"$CP" "$R" --pick > "$T/out" 2>&1; check "$?" "2" "a self-hosted lane naming the share: refused (GitHub's hosted runners only)"
grep -q "lane gha's" "$T/out"; check "$?" "1" "…and not for the Actions lane, which is valid again"
echo '{"at": 9999999999, "repo": "acme/demo", "variable": "CI_CIRCLECI_PROJECT", "from": "a", "to": "b"}' > "$PLOG"
check "$(python3 -c 'import importlib.machinery as m, importlib.util as u, sys; l=m.SourceFileLoader("cp", sys.argv[1]); c=u.module_from_spec(u.spec_from_loader("cp", l)); l.exec_module(c); print(c.last_flip("acme/demo"))' "$CP")" \
  "0" "a log row under the variable's old name (CI_CIRCLECI_PROJECT) is no runs-on flip either"
cp "$T/lanes.gha" "$LANES"; cp "$T/budgets.gha" "$BUDGETS"; mv "$T/gh/rsc.gha" "$T/gh/rsc.json"; rm -rf "$T/gh/vars"; rm -f "$PLOG"
# share.sh is public since free CI's S2 (.github/ci/, beside its list); a copy without it says skip
SH="$M/../../.github/ci/share.sh"
if [ -f "$SH" ]; then
  bash "$SH" linux-ids > "$T/out" 2>&1 || true
  check "$(python3 -c 'import json,sys; v=json.load(open(sys.argv[1])); print(isinstance(v, list) and "plugin" in v and "helm" in v)' "$T/out" 2>&1)" "True" "share.sh linux-ids: the Linux list as one JSON array, the Actions road's matrix"
  bash "$SH" linux-ids HEAD > "$T/out" 2>&1 || true
  check "$(python3 -c 'import json,sys; v=json.load(open(sys.argv[1])); print(isinstance(v, list) and "plugin" in v)' "$T/out" 2>&1)" "True" "share.sh linux-ids BASE: a JSON array of the ids reached (nothing changed: the whole list)"
  # the list is linux-ids beside share.sh; CircleCI's static matrix must hold the same ids, where it is
  S="$T/share"; mkdir -p "$S/.github/ci" "$S/.github/workflows" "$S/.circleci/parts"
  cp "$SH" "$S/.github/ci/share.sh"; cp "$M/../../.github/workflows/check.yml" "$S/.github/workflows/check.yml"
  printf '# a comment, then the ids\nplugin\n\n  helm  # trailing words go\n' > "$S/.github/ci/linux-ids"
  check "$(bash "$S/.github/ci/share.sh" linux-ids 2>&1)" '["plugin", "helm"]' "share.sh reads linux-ids: one id a line, comments and blanks skipped"
  check "$(bash "$S/.github/ci/share.sh" line "$S" | head -1)" "claude plugin validate --strict ." "share.sh line DIR: DIR's check line, its first command"
  # the step's block ends at its own column: a job after check's (the shares' road) is no part of the line
  mkdir -p "$T/share-fx/.github/workflows"
  printf '%s\n' 'jobs:' '  check:' '    steps:' '      - name: check' '        run: |' '          a && { b || c; }' '' '          && d' \
    '  plan:' '    if: >-' '      x && y' '    steps:' '      - run: e' > "$T/share-fx/.github/workflows/check.yml"
  check "$(bash "$S/.github/ci/share.sh" line "$T/share-fx" | tr '\n' '|')" "a|{ b || c; }|d|" "…up to the block's end, never into the job after it"
  printf '              id: [helm, plugin]\n' > "$S/.circleci/parts/check-linux.yml"
  check "$(bash "$S/.github/ci/share.sh" linux-ids 2>&1)" '["plugin", "helm"]' "…a CircleCI matrix of the same ids, in any order: the same list"
  printf '              id: [plugin, helm, keel]\n' > "$S/.circleci/parts/check-linux.yml"
  bash "$S/.github/ci/share.sh" linux-ids > "$T/out" 2>&1; check "$?" "2" "…a CircleCI matrix of other ids: refused, so the shares cannot drift"
  grep -q "is not .github/ci/linux-ids" "$T/out"; check "$?" "0" "…saying which file differs"
  rm -rf "$S/.circleci"; printf 'helm\nplugin # a comment\nhelm\n' > "$S/.github/ci/linux-ids"
  bash "$S/.github/ci/share.sh" linux-ids > "$T/out" 2>&1; check "$?" "2" "a linux-ids naming one id twice: refused, never two legs of one suite"
  grep -q "names helm more than once" "$T/out"; check "$?" "0" "…naming it"
  : > "$S/.github/ci/linux-ids"
  bash "$S/.github/ci/share.sh" linux-ids > /dev/null 2>&1; check "$?" "2" "an empty linux-ids: refused, never an empty matrix"
  # check.yml's two roads: the shares' jobs only where no runner variable is set, each behind check's own
  # condition, and their verdict under `check` only when every share passed (free CI's S2)
  cat > "$T/roads.py" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
j = d["jobs"]
base = "(github.event_name != 'push' || vars.CI_SKIP_MAIN_PUSH != 'true')"
free = "!vars.CI_RUNS_ON && !vars.CI_RUNS_ON_FULL"
bad = []
if list(j)[0] != "check": bad.append("check is not the first job (ci-provider reads its runs-on first)")
for n in ("plan", "gather"):
    if base not in j[n]["if"] or free not in j[n]["if"] or "draft" not in j[n]["if"]: bad.append(n + "'s if")
if j["suite"]["needs"] != "plan": bad.append("suite needs plan")
if sorted(j["gather"]["needs"]) != ["check", "plan", "suite"]: bad.append("gather's needs")
if not j["gather"]["name"].startswith("${{") or "'check'" not in j["gather"]["name"]: bad.append("gather's name")
if "'check (the rest)'" not in j["check"]["name"]: bad.append("check's name on the shares' road")
steps = {s.get("name"): s.get("if", "") for s in j["check"]["steps"]}
if "share.sh rest" not in [s.get("run", "") for s in j["check"]["steps"] if s.get("name") == "check, the rest"][0]: bad.append("the rest's step")
for n in ("check", "check, the macOS share"):
    if "(vars.CI_RUNS_ON || vars.CI_RUNS_ON_FULL)" not in steps[n]: bad.append(n + " runs on the shares' road too")
if "share.sh linux" not in j["suite"]["steps"][-1]["run"]: bad.append("suite's step")
print(bad or "ok")
PY
  check "$(python3 "$T/roads.py" "$M/../../.github/workflows/check.yml" 2>&1)" "ok" "check.yml: the shares' road beside the runner's, one verdict named check"
else
  echo "  skip no .github/ci/share.sh in this copy"
fi

echo "check-linux.yml's trigger: the project variable, else the file, each org's road (ci-two-orgs)"
# The workflow's own step run under a stand-in curl, against a scratch checkout. .github/workflows/check-linux.yml
# is private (off the allowlist): the twin has none, and says skip.
WF="$M/../../.github/workflows/check-linux.yml"
if [ -f "$WF" ]; then
  W="$T/ciwf"; mkdir -p "$W/bin" "$W/tmp"
  cat > "$W/extract.py" <<'PY'
import sys
lines = open(sys.argv[1], encoding="utf-8").read().splitlines()
at = next(i for i, l in enumerate(lines) if l.strip() == "run: |")
pad = len(lines[at + 1]) - len(lines[at + 1].lstrip())
# the trigger's step only: up to the next job key (two spaces, a name, a colon), never the jobs after it
end = next((i for i in range(at + 1, len(lines)) if lines[i][:2] == "  " and lines[i][2:3].isalpha() and lines[i].rstrip().endswith(":")), len(lines))
open(sys.argv[2], "w").write("\n".join(l[pad:] for l in lines[at + 1:end]) + "\n")
PY
  python3 "$W/extract.py" "$WF" "$W/step.sh"
  cat > "$W/bin/curl" <<'PY'
#!/usr/bin/env python3
import os, sys
a = sys.argv[1:]
url = next(x for x in a if x.startswith("https://"))
post = "-X" in a and a[a.index("-X") + 1] == "POST"
if "api.github.com" in url and not post:
    ans, code = '{"statuses":[]}', "200"
elif post:
    body = "".join(sys.stdin.read().split())
    open(os.environ["CURL_LOG"], "a").write("%s %s\n" % (url, body))
    ans, code = ('{}' if "api.github.com" in url else '{"id":"p-1","number":7}'), "201"
    if os.environ.get("CURL_NO_PIPELINE"):
        ans, code = '{"message":"Ignoring pipeline due to CI skip in the commit"}', "200"
else:
    ans, code = '{"state":"created"}', "200"
if "-o" in a:
    open(a[a.index("-o") + 1], "w").write(ans)
else:
    sys.stdout.write(ans)
if "-w" in a:
    sys.stdout.write(code)
PY
  chmod +x "$W/bin/curl"
  git init -q --bare "$W/origin.git"
  git clone -q "$W/origin.git" "$W/co" 2>/dev/null
  mkdir -p "$W/co/.circleci"
  printf 'parameters:\n  check_linux:\n    type: boolean\n' > "$W/co/.circleci/config.yml"
  printf '# the default\ngh/acme/demo\n' > "$W/co/.circleci/project-slug"
  mkdir -p "$W/co/.github/ci"
  printf 'case "$1" in linux-ids) echo %s ;; *) echo "RUN a stand-in scope" ;; esac\n' "'[\"helm\"]'" > "$W/co/.github/ci/share.sh"
  git -C "$W/co" checkout -q -b b; git -C "$W/co" add -A; git -C "$W/co" -c user.name=t -c user.email=t@t commit -qm x
  git -C "$W/co" push -q origin b 2>/dev/null
  step() { # step <PROJECT>: the workflow's step, as GitHub runs it; prints its exit code
    : > "$W/calls"
    : > "$W/ghout"
    (cd "$W/co" && env PATH="$W/bin:$PATH" CURL_LOG="$W/calls" RUNNER_TEMP="$W/tmp" GH_TOKEN=x CIRCLECI_TOKEN=tok ELSEWHERE=true \
      PROJECT="$1" REPO=acme/demo SHA="$(git rev-parse HEAD)" BRANCH=b BASE=main GITHUB_OUTPUT="$W/ghout" \
      RUN_URL=https://github.com/acme/demo/actions/runs/1 ACTIONS_RUNS=https://github.com/acme/demo/actions/runs/ \
      bash -e "$W/step.sh" > "$W/out" 2>&1); echo "$?"; }
  grep -q 'gather:' "$W/step.sh"; check "$?" "1" "the extracted step stops at the next job"
  bash -n "$W/step.sh"; check "$?" "0" "…and parses as bash"
  check "$(step actions)" "0" "the Actions road"
  check "$(tr '\n' ' ' < "$W/ghout")" 'road=actions ids=["helm"] ' "…its outputs: the road and share.sh's scoped list"
  grep -q '"state":"pending","context":"ci/circleci:check-linux"' "$W/calls"; check "$?" "0" "…check-linux pending on the head first"
  mv "$W/co/.github/ci/share.sh" "$W/co/.circleci/share.sh"
  check "$(step actions)" "0" "a head forked before free CI's S2, share.sh under .circleci/: the same road"
  check "$(tr '\n' ' ' < "$W/ghout")" 'road=actions ids=["helm"] ' "…its outputs read from the old path"
  grep -q '"state":"pending","context":"ci/circleci:check-linux"' "$W/calls"; check "$?" "0" "…check-linux pending there too"
  mv "$W/co/.circleci/share.sh" "$W/co/.github/ci/share.sh"
  check "$(step '')" "0" "the variable unset"
  check "$(cat "$W/calls")" 'https://circleci.com/api/v2/project/gh/acme/demo/pipeline {"branch":"b","parameters":{"check_linux":true}}' "…the file's project, an OAuth project's road"
  check "$(step gh/acme/other)" "0" "the variable on an OAuth project"
  check "$(cat "$W/calls")" 'https://circleci.com/api/v2/project/gh/acme/other/pipeline {"branch":"b","parameters":{"check_linux":true}}' "…takes the variable over the file"
  check "$(step circleci/ORG/PROJ)" "0" "the variable on a GitHub App project"
  check "$(cat "$W/calls")" 'https://circleci.com/api/v2/project/circleci/ORG/PROJ/pipeline/run {"config":{"branch":"b"},"checkout":{"branch":"b"},"parameters":{"check_linux":true}}' "…the Trigger Pipeline road, which alone takes one"
  grep -q 'pipeline p-1 created' "$W/out"; check "$?" "0" "…and the job waits for it as on the OAuth road"
  export CURL_NO_PIPELINE=1; check "$(step circleci/ORG/PROJ)" "1" "a 200 on that road, no pipeline created: the job fails"
  unset CURL_NO_PIPELINE
  grep -q 'CircleCI started no pipeline: Ignoring pipeline due to CI skip' "$W/out"; check "$?" "0" "…saying so, not 'refused'"
  printf '# only a comment\n' > "$W/co/.circleci/project-slug"; git -C "$W/co" add -A; git -C "$W/co" -c user.name=t -c user.email=t@t commit -qm y; git -C "$W/co" push -q origin b 2>/dev/null
  check "$(step '')" "1" "no variable, and a file with no slug: the job fails"
  check "$(cat "$W/calls")" "" "…nothing triggered"
  grep -q "'' is no project slug" "$W/out"; check "$?" "0" "…in one line, not silently"
  check "$(step 'gh/acme')" "1" "a variable that is no project slug: the job fails"
  check "$(cat "$W/calls")" "" "…nothing triggered"
  grep -q "'gh/acme' is no project slug" "$W/out"; check "$?" "0" "…in one line"
  grep -q 'PROJECT: ${{ vars.CI_LINUX_TARGET }}' "$WF"; check "$?" "0" "the step's env takes the repository variable"
  check "$(grep -cF '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' "$WF" "$CP" | cut -d: -f2 | tr '\n' ' ')" "1 1 " "the trigger and the pick read a project slug alike"
else
  echo "  skip the twin has no check-linux.yml"
fi

echo "the pick's trust refusals: every flip to a self-hosted lane"
R="$T/pk3"; pickrepo "$R"; usage ok 100
echo true > "$T/gh/forkpr"; "$CP" "$R" --pick --apply > "$T/out" 2>&1
grep -q 'lane mac: refused, acme/demo runs fork pull requests' "$T/out"; check "$?" "0" "a private repo running fork PRs' workflows: the Mac lane refused"
check "$(varval)" "unset" "…a macOS repo then has no lane, and nothing is written"
echo fail > "$T/gh/forkpr"; "$CP" "$R" --pick > "$T/out" 2>&1
grep -q 'lane mac: refused, could not read whether acme/demo runs fork' "$T/out"; check "$?" "0" "fork PRs' setting unread: refused"
echo adm1n > "$T/gh/forkpr.admin"; rm -f "$T/gh/tokcalls"
WHARF_READ_TOKEN=wrong "$CP" "$R" --pick > "$T/out" 2>&1
grep -q "lane mac: refused, could not read whether acme/demo runs fork pull requests' workflows (HTTP 404; WHARF_READ_TOKEN: HTTP 404)" "$T/out"; check "$?" "0" "…a read token that cannot read it either: still refused, both answers said"
WHARF_READ_TOKEN=adm1n "$CP" "$R" --pick > "$T/out" 2>&1
grep -q 'lane mac: eligible' "$T/out"; check "$?" "0" "the login cannot read it, the desk's read token can (the 404 on every pass, 2026-11-02): the Mac lane eligible"
check "$(sort -u "$T/gh/tokcalls")" "api repos/acme/demo/actions/permissions/fork-pr-workflows-private-repos
api repos/acme/demo/actions/runners" "…the token used for the two admin reads (the setting, the runner list), never for another call"
check "$([ -e "$T/gh/leak" ] && echo leaked || echo none)" "none" "…and WHARF_READ_TOKEN reaches no child: ci-provider pops it at its start"
echo false > "$T/gh/forkpr"; rm -f "$T/gh/tokcalls"
WHARF_READ_TOKEN=adm1n "$CP" "$R" --pick > "$T/out" 2>&1
check "$(cat "$T/gh/tokcalls" 2>/dev/null)" "api repos/acme/demo/actions/runners" "…a login that reads the setting itself: the token only where the login could not"
rm -f "$T/gh/forkpr.admin" "$T/gh/tokcalls" "$T/gh/leak"
echo false > "$T/gh/forkpr"; echo fail > "$T/gh/private"; "$CP" "$R" --pick > "$T/out" 2>&1; check "$?" "2" "privacy unread: the whole pick refused"
grep -q 'could not read whether acme/demo is private' "$T/out"; check "$?" "0" "…saying so"
echo false > "$T/gh/private"; printf '{"provider": "self-hosted", "check": "sh check.sh", "needs": []}\n' > "$R/.github/ci.json"
rm -f "$USAGE"; "$CP" "$R" --pick > "$T/out" 2>&1
grep -q 'lane mac: not eligible, the repo needs public' "$T/out"; check "$?" "0" "a public repo: no self-hosted lane is eligible"
grep -q 'lane hosted: eligible, a public repo.s hosted minutes are free' "$T/out"; check "$?" "0" "…the hosted lane is, free, with no usage at all"
echo true > "$T/gh/private"; touch "$T/gh/runners.fail"; "$CP" "$R" --pick > "$T/out" 2>&1
grep -q "lane mac: refused, the repo's runners are unread" "$T/out"; check "$?" "0" "runners unread: refused"
rm -f "$T/gh/runners.fail"; echo '{"total_count":1,"runners":[{"id":7,"name":"laptop","status":"offline","labels":[{"name":"self-hosted"},{"name":"macOS"},{"name":"laptop"}]}]}' > "$T/gh/runners.json"
"$CP" "$R" --pick > "$T/out" 2>&1
grep -q 'lane mac: refused, no online runner labelled' "$T/out"; check "$?" "0" "the runner offline: refused"
cp "$LANES" "$T/lanes.keep"
sed 's/"runs": \["macos"\]}/"runs": ["macos", "public"]}/' "$T/lanes.keep" > "$LANES"
"$CP" "$R" --pick > "$T/out" 2>&1; check "$?" "2" "a self-hosted lane listing public: the lanes file refused"
grep -q 'lane mac is self-hosted and lists `public`' "$T/out"; check "$?" "0" "…saying why"
cp "$T/lanes.keep" "$LANES"

echo "the pick: queue, staleness, the ops host, a repo not migrated"
R="$T/pk4"; pickrepo "$R" '[]'; usage ok 100
python3 -c 'import json,sys,time; print(json.dumps({"as_of":int(time.time()),"ci":{"lanes":{"mac":{"queued_s_p50":900}}}}))' > "$T/logs/ops.jsonl"
"$CP" "$R" --pick > "$T/out" 2>&1
grep -q 'lane mac: eligible, queue 900s' "$T/out" && grep -q '  pick: hosted' "$T/out"; check "$?" "0" "the Mac's queue over the max: the hosted lane, under budget"
rm -f "$USAGE"; "$CP" "$R" --pick > "$T/out" 2>&1
grep -q '  pick: mac' "$T/out"; check "$?" "0" "…over budget: back to the shortest self-hosted queue"
rm -f "$T/logs/ops.jsonl"; usage ok 100
mkdir -p "$T/gh/vars"; echo '{"name":"CI_RUNS_ON","value":"[\"self-hosted\",\"macOS\",\"laptop\"]"}' > "$T/gh/vars/CI_RUNS_ON.json"
python3 -c 'import json,time; print(json.dumps({"workflow_runs":[{"id":1,"created_at":time.strftime("%Y-%m-%dT%H:%M:%SZ",time.gmtime(time.time()-2400))}]}))' > "$T/gh/queued.json"
"$CP" "$R" --pick > "$T/out" 2>&1
grep -q 'lane mac: skipped, a check sat queued 40 min on it' "$T/out" && grep -q '  pick: hosted' "$T/out"; check "$?" "0" "a check queued 40 min on its lane: that lane skipped (D2-A)"
printf '{"at":%d,"repo":"acme/demo"}\n' "$(($(date +%s) - 1200))" > "$PLOG"
"$CP" "$R" --pick > "$T/out" 2>&1
grep -q '  pick: mac, unchanged' "$T/out"; check "$?" "0" "…but a run queued before the pick's last flip never makes the new lane stale (landing review)"
rm -f "$PLOG"
CLAUDE_CODE_SESSION_ID=s-1 "$CP" "$R" --pick --apply > "$T/out" 2>&1; check "$?" "2" "--apply inside a Claude Code session: refused, the desk's job applies"
echo other-host > "$REGATTA_CONFIG/lighthouse/ops-host"
"$CP" "$R" --pick --apply --dry-run > "$T/out" 2>&1; check "$?" "0" "--apply --dry-run off the ops host: runs, writes nothing"
grep -q 'would update variable CI_RUNS_ON' "$T/out"; check "$?" "0" "…saying what it would write"
"$CP" "$R" --pick --apply > "$T/out" 2>&1; check "$?" "2" "--apply off the ops host: refused"
grep -q "not lighthouse/ops-host's other-host" "$T/out"; check "$?" "0" "…naming the host it writes on"
rm -f "$REGATTA_CONFIG/lighthouse/ops-host"; "$CP" "$R" --pick --apply > "$T/out" 2>&1; check "$?" "2" "…no ops host at all: refused, the desk is off"
check "$(varval)" '["self-hosted","macOS","laptop"]' "…and the variable untouched"
python3 -c "import sys; sys.path.insert(0, sys.argv[1]); import common; print(common.host_name())" "$M/../regatta/hooks" \
  > "$REGATTA_CONFIG/lighthouse/ops-host"
R="$T/pk5"; newrepo "$R"; "$CP" "$R" --to self-hosted > /dev/null 2>&1; usage ok 100
printf '{"provider": "self-hosted", "check": "sh check.sh", "needs": []}\n' > "$R/.github/ci.json"
python3 -c 'import json,sys,time; print(json.dumps({"as_of":int(time.time()),"ci":{"lanes":{"mac":{"queued_s_p50":900}}}}))' > "$T/logs/ops.jsonl"
rm -f "$T/gh/queued.json"; "$CP" "$R" --pick > "$T/out" 2>&1; check "$?" "0" "a literal runs-on: the pick reports"
grep -q 'check.yml reads no runs-on variable' "$T/out"; check "$?" "0" "…says it is not migrated"
"$CP" "$R" --pick --apply > "$T/out" 2>&1; check "$?" "2" "…and --apply is refused: never written"
rm -f "$T/logs/ops.jsonl"
echo "the pick: the landing review's cases"
R="$T/pk7"; pickrepo "$R"; usage ok 100; echo true > "$T/gh/forkpr"
mkdir -p "$T/gh/vars"; echo '{"name":"CI_RUNS_ON","value":"[\"self-hosted\",\"macOS\",\"laptop\"]"}' > "$T/gh/vars/CI_RUNS_ON.json"
"$CP" "$R" --pick > "$T/out" 2>&1; check "$?" "3" "the repo's current lane refused (fork PRs on) and no other: exit 3, for the desk to card"
grep -q '⚠ current lane mac fails: acme/demo runs fork pull requests' "$T/out"; check "$?" "0" "…naming why"
echo false > "$T/gh/forkpr"; grep -v 'GIT_CONFIG_GLOBAL=' "$R/.github/workflows/check.yml" > "$T/wf" && cp "$T/wf" "$R/.github/workflows/check.yml"
"$CP" "$R" --pick > "$T/out" 2>&1
grep -q 'lane mac: refused, check.yml lacks the GIT_CONFIG_GLOBAL step' "$T/out"; check "$?" "0" "a check.yml without the guard step: the self-hosted lane refused, as --to self-hosted would"
sed 's/"runs_on": \["self-hosted", "macOS", "laptop"\]/"runs_on": ["macOS", "laptop"]/' "$T/lanes.keep" > "$LANES"
R="$T/pk8"; pickrepo "$R"; usage ok 100; echo true > "$T/gh/forkpr"
"$CP" "$R" --pick > "$T/out" 2>&1
grep -q 'lane mac: refused, acme/demo runs fork pull requests' "$T/out"; check "$?" "0" "a label list without self-hosted is a runner's lane: the trust refusals run (landing review)"
sed 's/"runs_on": \["self-hosted", "macOS", "laptop"\]/"runs_on": "self-hosted"/' "$T/lanes.keep" > "$LANES"
"$CP" "$R" --pick > "$T/out" 2>&1; check "$?" "2" "a string runs_on naming a self-hosted runner: the lanes file refused"
sed 's/"runs_on": \["self-hosted", "macOS", "laptop"\]/"runs_on": "macOS"/' "$T/lanes.keep" > "$LANES"
"$CP" "$R" --pick > "$T/out" 2>&1; check "$?" "2" "a string runs_on that is an automatic label (macOS): refused, no hosted image's name (the second landing review)"
cp "$T/lanes.keep" "$LANES"
echo "the pick: the second landing review's cases"
setmac() { mkdir -p "$T/gh/vars"; echo '{"name":"CI_RUNS_ON","value":"[\"self-hosted\",\"macOS\",\"laptop\"]"}' > "$T/gh/vars/CI_RUNS_ON.json"; }
echo false > "$T/gh/forkpr"   # pickrepo's --to reads the last case's fork PRs
R="$T/pk9"; pickrepo "$R"; usage ok 100; setmac; echo false > "$T/gh/private"
"$CP" "$R" --pick > "$T/out" 2>&1; check "$?" "3" "a public repo still on the runner Mac, no lane takes it: exit 3, not 0"
grep -q '⚠ current lane mac fails: the repo needs public' "$T/out"; check "$?" "0" "…naming why"
R="$T/pk10"; pickrepo "$R"; usage ok 100; setmac; touch "$T/gh/runners.fail"
"$CP" "$R" --pick > "$T/out" 2>&1; check "$?" "3" "the current lane's runners unread and no other lane: exit 3"
R="$T/pk11"; pickrepo "$R"; usage ok 100; printf '{"at": 1, "repo": "acme/de\n' > "$PLOG"; echo '{"at": 5, "repo": "acme/demo"}' >> "$PLOG"
check "$(python3 -c 'import importlib.machinery as m, importlib.util as u, sys; l=m.SourceFileLoader("cp", sys.argv[1]); o=u.module_from_spec(u.spec_from_loader("cp", l)); l.exec_module(o); print(o.last_flip("acme/demo"))' "$CP")" "5" "a torn line in ci-pick.jsonl costs that line only"
cp "$T/lanes.keep" "$LANES"
R="$T/pk20"; pickrepo "$R" '["macos", "browser"]'; usage ok 100
"$CP" "$R" --pick > "$T/out" 2>&1; check "$?" "3" "a capability no lane names: no lane takes the repo"
grep -q 'lane mac: not eligible, the repo needs browser, the lane runs macos' "$T/out"; check "$?" "0" "…the Mac lane lacks it"
grep -q 'lane hosted: not eligible, the repo needs browser, macos' "$T/out"; check "$?" "0" "…a hosted image carries no capability"
sed 's/"macOS", "laptop"/"macOS", "browser"/' "$T/lanes.keep" > "$LANES"
echo '{"total_count":1,"runners":[{"id":7,"name":"laptop","status":"online","labels":[{"name":"self-hosted"},{"name":"macOS"},{"name":"browser"}]}]}' > "$T/gh/runners.json"
"$CP" "$R" --pick > "$T/out" 2>&1; check "$?" "0" "a lane whose label list names the capability"
grep -q '  pick: mac (\["self-hosted","macOS","browser"\])' "$T/out"; check "$?" "0" "…takes the repo"
R="$T/pk21"; pickrepo "$R" '["macos", "BROWSER"]'; usage ok 100
echo '{"total_count":1,"runners":[{"id":7,"name":"laptop","status":"online","labels":[{"name":"self-hosted"},{"name":"macOS"},{"name":"browser"}]}]}' > "$T/gh/runners.json"
"$CP" "$R" --pick > "$T/out" 2>&1; check "$?" "0" "…in any case, as GitHub compares labels"
R="$T/pk22"; pickrepo "$R" '["linux", "macOS"]'; usage ok 100
sed 's/"runs": \["macos"\]/"runs": ["macos", "linux"]/' "$T/lanes.keep" > "$LANES"
"$CP" "$R" --pick > "$T/out" 2>&1
grep -q 'lane mac: eligible' "$T/out"; check "$?" "0" "a lane word in a capital reads as the lane word, never a capability"
R="$T/pk23"; pickrepo "$R" '["macos", "guest"]'; usage ok 100; cp "$T/lanes.keep" "$LANES"
"$CP" "$R" --pick > "$T/out" 2>&1
grep -q 'lane mac: not eligible, the repo needs guest' "$T/out"; check "$?" "0" "a label of another lane's list is no capability of this one"
cp "$T/lanes.keep" "$LANES"
R="$T/pk25"; pickrepo "$R" '["linux"]'; usage ok 100
"$CP" "$R" --pick > "$T/out" 2>&1
grep -q 'lane mac: not eligible, the repo needs linux' "$T/out"; check "$?" "0" "an OS the lane's list names and its runs does not: not met by the list"
R="$T/pk24"; newrepo "$R"; "$CP" "$R" --to self-hosted > /dev/null 2>&1; usage ok 100
rm -rf "$T/gh/vars" "$T/gh/queued.json" "$PLOG" "$T/logs/ops.jsonl"; echo true > "$T/gh/private"; echo true > "$T/gh/forkpr"; echo "$MACRUN" > "$T/gh/runners.json"
"$CP" "$R" --pick > "$T/out" 2>&1; check "$?" "3" "the literal form, [self-hosted, macOS], fork PRs on: exit 3"
grep -q '⚠ current lane mac fails' "$T/out"; check "$?" "0" "…its lane is the one whose list holds it, so the desk still cards it"
sed 's/"macOS", "laptop"/"macOS", "browser"/' "$T/lanes.keep" > "$LANES"
sed 's/runs-on: .*/runs-on: [self-hosted, macOS, browser]/' "$R/.github/workflows/check.yml" > "$T/pk.yml"; cp "$T/pk.yml" "$R/.github/workflows/check.yml"
printf '{"provider": "self-hosted", "check": "sh check.sh", "needs": ["macos", "browser"]}\n' > "$R/.github/ci.json"
"$CP" "$R" --pick > "$T/out" 2>&1; check "$?" "3" "a literal of capabilities: exit 3 too"
echo false > "$T/gh/forkpr"; cp "$T/lanes.keep" "$LANES"
R="$T/pk26"; newrepo "$R"; "$CP" "$R" --to self-hosted > /dev/null 2>&1; usage ok 100
sed 's/"macOS", "laptop"/"macOS", "browser"/' "$T/lanes.keep" > "$LANES"; echo "$MACRUN" > "$T/gh/runners.json"
"$CP" "$R" --pick > "$T/out" 2>&1; check "$?" "0" "a literal served by a runner the lane's list asks more of: no card"
grep -q 'current lane' "$T/out"; check "$?" "1" "…the lane not called failing"
cp "$T/lanes.keep" "$LANES"
echo '{"total_count":1,"runners":[{"id":7,"name":"laptop","status":"offline","labels":[{"name":"self-hosted"},{"name":"macOS"}]}]}' > "$T/gh/runners.json"
"$CP" "$R" --pick > "$T/out" 2>&1; check "$?" "3" "…and with no runner serving the literal, the card stands"
sed 's/"self-hosted", "linux", "guest"/"self-hosted", "browser", "guest"/' "$T/lanes.keep" > "$LANES"
python3 - "$LANES" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); d["lanes"][0], d["lanes"][1] = d["lanes"][1], d["lanes"][0]
d["lanes"][1]["runs_on"] = ["self-hosted", "macOS", "browser"]
json.dump(d, open(sys.argv[1], "w"))
PY
R="$T/pk27"; newrepo "$R"; printf '{"provider": "actions", "check": "sh check.sh", "needs": ["macos", "browser"]}\n' > "$R/.github/ci.json"
"$CP" "$R" --to self-hosted > /dev/null 2>&1; usage ok 100
sed 's/runs-on: .*/runs-on: [self-hosted, browser]/' "$R/.github/workflows/check.yml" > "$T/pk.yml"; cp "$T/pk.yml" "$R/.github/workflows/check.yml"
echo '{"total_count":1,"runners":[{"id":7,"name":"laptop","status":"online","labels":[{"name":"self-hosted"},{"name":"macOS"},{"name":"browser"}]}]}' > "$T/gh/runners.json"
"$CP" "$R" --pick > "$T/out" 2>&1; check "$?" "0" "a literal two lanes hold, a Linux one first: no false card"
grep -q 'lane mac$\|: lane mac' "$T/out"; check "$?" "0" "…it sits on the lane the repo fits"
cp "$T/lanes.keep" "$LANES"
R="$T/pk6"; newrepo "$R"; "$CP" "$R" --to circleci > /dev/null 2>&1
"$CP" "$R" --pick > "$T/out" 2>&1; check "$?" "2" "a repo on circleci: refused, the pick moves an Actions check only"
"$CP" "$R" --apply > /dev/null 2>&1; check "$?" "2" "--apply without --pick: a usage error"

echo "capabilities: a runner's custom labels from wharf/ci-runner-caps.json (2026-10-31)"
CAPS="$REGATTA_CONFIG/wharf/ci-runner-caps.json"
R="$T/cap1"; newrepo "$R"; mkdir -p "$R/.helloworld"; "$CP" "$R" --to self-hosted > /dev/null 2>&1
printf 'jobs:\n  merge:\n    runs-on: ${{ fromJSON(vars.CI_RUNS_ON_AUTOMERGE || vars.CI_RUNS_ON) }}\n' > "$R/.github/workflows/automerge.yml"
rm -rf "$T/gh/runners.fail" "$T/gh/vars"; mkdir -p "$T/gh/vars"
RO='{"name":"self-hosted","type":"read-only"},{"name":"macOS","type":"read-only"}'
cat > "$T/gh/runners.json" <<EOF
{"total_count":3,"runners":[{"id":21,"name":"fast","status":"online","labels":[$RO,{"name":"box1","type":"custom"}]},{"id":22,"name":"slow","status":"offline","labels":[$RO,{"name":"old-check","type":"custom"}]},{"id":23,"name":"spare","status":"online","labels":[$RO,{"name":"keep-me","type":"custom"}]}]}
EOF
echo '{"name":"CI_RUNS_ON","value":"[\"self-hosted\",\"macOS\",\"box1\"]"}' > "$T/gh/vars/CI_RUNS_ON.json"
cat > "$T/customs.py" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1]))
print(" ".join("%s=%s" % (r["name"], ",".join(l["name"] for l in r["labels"] if l.get("type") == "custom")) for r in d["runners"]))
EOF
customs() { python3 "$T/customs.py" "$T/gh/runners.json"; }
rm -f "$CAPS"
"$CP" "$R" --runner caps > "$T/out" 2>&1; check "$?" "2" "no ci-runner-caps.json: refused"
grep -q 'no capabilities: write .*ci-runner-caps.json' "$T/out"; check "$?" "0" "…naming the file"
echo '{"fast": ["macOS"]}' > "$CAPS"
"$CP" "$R" --runner caps > /dev/null 2>&1; check "$?" "2" "an automatic label in the table: refused"
echo '{"fast": ["bad label"]}' > "$CAPS"
"$CP" "$R" --runner caps > /dev/null 2>&1; check "$?" "2" "a capability that is no label: refused"
echo '{"fast": "browser"}' > "$CAPS"
"$CP" "$R" --runner caps > /dev/null 2>&1; check "$?" "2" "a runner's capabilities not a list: refused"
echo '{"fast": ["browser", "whole-line"], "slow": []}' > "$CAPS"; : > "$T/gh/calls"
"$CP" "$R" --runner caps > "$T/out" 2>&1; check "$?" "2" "dropping the label a variable routes on: refused"
grep -q 'variable CI_RUNS_ON asks for .*box1.*which fast carries now and no runner would after' "$T/out"; check "$?" "0" "…naming the variable and the runner"
check "$(grep -c -- '-X PUT\|-X DELETE' "$T/gh/calls")" "0" "…before any write"
echo '{"fast": ["box1", "browser", "whole-line"], "slow": [], "gone": ["x"]}' > "$CAPS"; : > "$T/gh/calls"
"$CP" "$R" --runner caps --dry-run > "$T/out" 2>&1; check "$?" "0" "the old label kept beside the new: --dry-run"
grep -qF "would set runner fast's capabilities: box1 → box1, browser, whole-line" "$T/out"; check "$?" "0" "…says the change"
check "$(grep -c -- '-X PUT\|-X DELETE' "$T/gh/calls")" "0" "…and writes nothing"
"$CP" "$R" --runner caps > "$T/out" 2>&1; check "$?" "0" "--runner caps"
check "$(customs)" "fast=box1,browser,whole-line slow= spare=keep-me" "…fast PUT, slow cleared, spare untouched"
grep -q 'runner spare: not in ci-runner-caps.json, left at keep-me' "$T/out"; check "$?" "0" "…an unlisted runner said, left"
grep -q 'ci-runner-caps.json lists gone: acme/demo has no runner of that name' "$T/out"; check "$?" "0" "…a listed name with no runner said"
grep -q 'variable CI_RUNS_ON_AUTOMERGE' "$T/out"; check "$?" "1" "…an unset variable judged by nothing"
grep -qF "rollback: echo '{\"labels\": [\"box1\"]}' | gh api -X PUT repos/acme/demo/actions/runners/21/labels --input -" "$T/out"; check "$?" "0" "…the PUT that undoes it printed"
check "$(grep -c -- '-X DELETE repos/acme/demo/actions/runners/22/labels' "$T/gh/calls")" "1" "…an empty list is GitHub's DELETE"
echo '{"name":"CI_RUNS_ON","value":"[\"self-hosted\",\"macOS\",\"browser\"]"}' > "$T/gh/vars/CI_RUNS_ON.json"
echo '{"fast": ["browser", "whole-line"], "slow": []}' > "$CAPS"
"$CP" "$R" --runner caps > "$T/out" 2>&1; check "$?" "0" "the variable moved to a capability: the old label dropped"
check "$(customs)" "fast=browser,whole-line slow= spare=keep-me" "…fast carries its capabilities alone"
grep -qF 'variable CI_RUNS_ON (["self-hosted","macOS","browser"]): fast' "$T/out"; check "$?" "0" "…the variable served by fast, said"
: > "$T/gh/calls"; "$CP" "$R" --runner caps > "$T/out" 2>&1; check "$?" "0" "a second run"
check "$(grep -c -- '-X PUT\|-X DELETE' "$T/gh/calls")" "0" "…writes nothing"
grep -q 'runner fast: already browser, whole-line' "$T/out"; check "$?" "0" "…says each runner already right"
echo '{"fast": ["gpu"], "spare": []}' > "$CAPS"
"$CP" "$R" --runner caps --name spare > "$T/out" 2>&1; check "$?" "0" "--name: one runner only"
check "$(customs)" "fast=browser,whole-line slow= spare=" "…spare cleared, fast left though the table differs"
touch "$T/gh/labels.fail"; echo '{"fast": ["browser"]}' > "$CAPS"
"$CP" "$R" --runner caps > /dev/null 2>&1; check "$?" "2" "GitHub refusing the PUT: exit 2"
rm -f "$T/gh/labels.fail"
"$CP" "$R" --runner caps --host x --name fast > "$T/out" 2>&1; check "$?" "2" "--runner caps with --host: a usage error"
grep -q 'do not go with it' "$T/out"; check "$?" "0" "…caps' own guard, not --host's"
"$CP" "$R" --runner caps --name nosuch > "$T/out" 2>&1; check "$?" "2" "--name naming no runner: refused"
grep -q 'has no runner named nosuch: nothing written' "$T/out"; check "$?" "0" "…saying so"
echo '{"fast": ["Browser", "browser", "whole-line"]}' > "$CAPS"; : > "$T/gh/calls"
"$CP" "$R" --runner caps --name fast > "$T/out" 2>&1; check "$?" "0" "a capability spelt twice in two cases"
check "$(grep -c -- '-X PUT\|-X DELETE' "$T/gh/calls")" "0" "…one label, as GitHub keeps it: nothing written"
echo '{"laptop": ["browser", "whole-line"]}' > "$CAPS"
"$CP" "$R" --runner install --dry-run > "$T/out" 2>&1; check "$?" "0" "install with the runner in the table"
grep -q 'config.sh --name laptop --labels browser,whole-line;' "$T/out"; check "$?" "0" "…registers its capabilities, not the Mac's own label"
echo '{"laptop": []}' > "$CAPS"
"$CP" "$R" --runner install --dry-run > /dev/null 2>&1; check "$?" "2" "install of a runner listed with no capabilities: refused"
R2="$T/cap2"; newrepo "$R2"; mkdir -p "$R2/.github/workflows"
printf 'jobs:\n  check:\n    runs-on: [self-hosted, macOS, browser]\n' > "$R2/.github/workflows/check.yml"
echo '{"fast": ["whole-line"]}' > "$CAPS"; : > "$T/gh/calls"
"$CP" "$R2" --runner caps > "$T/out" 2>&1; check "$?" "2" "dropping the label a literal runs-on routes on: refused"
grep -q "check.yml's runs-on asks for .*browser.*which fast carries now and no runner would after" "$T/out"; check "$?" "0" "…naming the file and the runner"
check "$(grep -c -- '-X PUT\|-X DELETE' "$T/gh/calls")" "0" "…before any write"
echo '{"laptop": ["browser", "whole-line"]}' > "$CAPS"
"$CP" "$R2" --runner install --dry-run > "$T/out" 2>&1; check "$?" "0" "install on a literal runs-on of capabilities, the runner in the table"
grep -q 'config.sh --name laptop --labels browser,whole-line;' "$T/out"; check "$?" "0" "…registers them: the table carries what the literal asks for"
grep -q 'would not carry' "$T/out"; check "$?" "1" "…with nothing to warn of"
printf 'jobs:\n  check:\n    runs-on: [self-hosted, macOS, laptop]\n' > "$R2/.github/workflows/check.yml"
"$CP" "$R2" --runner install --dry-run > "$T/out" 2>&1; check "$?" "0" "install on a literal naming the labels key's label"
grep -q 'config.sh --name laptop --labels browser,whole-line,laptop;' "$T/out"; check "$?" "0" "…keeps the key's label beside the capabilities, never instead of them"
grep -q 'laptop keeps laptop beside its capabilities' "$T/out"; check "$?" "0" "…said"
echo '{}' > "$CAPS"; printf 'jobs:\n  check:\n    runs-on: [self-hosted, macOS, browser]\n' > "$R2/.github/workflows/check.yml"
"$CP" "$R2" --runner install --dry-run > "$T/out" 2>&1; check "$?" "0" "install of a runner the table lacks, a literal of capabilities"
grep -q "⚠ a runs-on asks for browser, which runner laptop would not carry" "$T/out"; check "$?" "0" "…warns that the job would queue"

echo "capabilities: a literal runs-on judged like a variable, whatever its shape (2026-10-31)"
# a runner named after its Mac, and that name its one custom label: the shape caps would strip
RO='{"name":"self-hosted","type":"read-only"},{"name":"macOS","type":"read-only"}'
echo "{\"total_count\":1,\"runners\":[{\"id\":31,\"name\":\"box1\",\"status\":\"online\",\"labels\":[$RO,{\"name\":\"box1\",\"type\":\"custom\"}]}]}" > "$T/gh/runners.json"
keep_runners=$(cat "$T/gh/runners.json")
echo '{"box1": ["browser", "whole-line"]}' > "$CAPS"
R3="$T/cap3"; newrepo "$R3"; mkdir -p "$R3/.github/workflows"; WF3="$R3/.github/workflows/check.yml"; rm -f "$R3/.github/workflows/automerge.yml"
stranded() { # stranded <label> <the job's runs-on, as the file's lines>: refused, by name, and no write
  : > "$T/gh/calls"; printf 'jobs:\n  check:\n%b\n' "$2" > "$WF3"
  "$CP" "$R3" --runner caps --dry-run > "$T/out" 2>&1; check "$?" "2" "$1: refused, in a dry run too"
  grep -q "check.yml's runs-on asks for .*box1.*which box1 carries now and no runner would after: nothing written" "$T/out"; check "$?" "0" "…naming the runs-on and the runner"
  "$CP" "$R3" --runner caps > /dev/null 2>&1; check "$?" "2" "…and for real"
  check "$(grep -c -- '-X PUT\|-X DELETE' "$T/gh/calls")" "0" "…before any write"; }
stranded "[self-hosted, macOS, <the runner's name>]" '    runs-on: [self-hosted, macOS, box1]'
stranded "with no self-hosted in it, [macOS, <the name>]" '    runs-on: [macOS, box1]'
stranded "the label alone" '    runs-on: box1'
stranded "quoted, and a comment after it" "    runs-on: ['self-hosted', \"box1\"]  # the Mac"
stranded "a block list" '    runs-on:\n      - self-hosted\n      - macOS\n      - box1\n    steps: []'
stranded "a block list at the key's own indent" '    runs-on:\n    - self-hosted\n    # the Mac\n    - box1'
printf 'jobs:\n  check:\n    runs-on: [self-hosted, macOS, browser]\n' > "$WF3"; : > "$T/gh/calls"
"$CP" "$R3" --runner caps --dry-run > "$T/out" 2>&1; check "$?" "0" "the same runner once check.yml asks for a capability: --dry-run passes"
grep -qF "would set runner box1's capabilities: box1 → browser, whole-line" "$T/out"; check "$?" "0" "…says the change"
grep -qF "check.yml's runs-on ([self-hosted, macOS, browser]): box1" "$T/out"; check "$?" "0" "…and who serves the runs-on after it"
"$CP" "$R3" --runner caps > "$T/out" 2>&1; check "$?" "0" "…and the write"
check "$(customs)" "box1=browser,whole-line" "…the runner carries its capabilities alone"
echo "$keep_runners" > "$T/gh/runners.json"; : > "$T/gh/calls"
printf 'jobs:\n  check:\n    runs-on: ubuntu-latest\n  mac:\n    runs-on: macos-14\n' > "$WF3"
"$CP" "$R3" --runner caps > "$T/out" 2>&1; check "$?" "0" "hosted images in runs-on: nothing to strand"
grep -q 'ubuntu-latest\|macos-14' "$T/out"; check "$?" "1" "…and nothing said of them"
echo "$keep_runners" > "$T/gh/runners.json"
printf 'jobs:\n  check:\n    runs-on: ${{ matrix.os }}\n  two:\n    runs-on: { group: g }\n  three:\n    runs-on:\n      group: g\n    steps: []\n' > "$WF3"
"$CP" "$R3" --runner caps --dry-run > "$T/out" 2>&1; check "$?" "0" "shapes no reader here can judge, naming no label going: not refused"
check "$(grep -c "⚠ check.yml's runs-on .*not judged" "$T/out")" "3" "…each said, not passed in silence"

echo "the literal form from ci.json's needs: capabilities, never a host name (2026-10-31)"
needs() { printf '{"provider": "self-hosted", "check": "sh check.sh", "needs": %s}\n' "$2" > "$1/.github/ci.json"; }
runson() { grep '^ *runs-on:' "$1/.github/workflows/check.yml" | sed 's/^ *//'; }
echo '{"total_count":0,"runners":[]}' > "$T/gh/runners.json"; rm -f "$CAPS"
R="$T/n1"; newrepo "$R"; "$CP" "$R" --to self-hosted > /dev/null 2>&1; check "$?" "0" "no needs: --to self-hosted"
check "$(runson "$R")" "runs-on: [self-hosted, macOS]" "…macOS alone, as an absent needs reads everywhere"
check "$(grep -ci laptop "$R/.github/workflows/check.yml")" "0" "…and no line of the file names the labels key's machine"
needs "$R" '["macos", "browser", "git-2.43"]'
"$CP" "$R" --to self-hosted > "$T/out" 2>&1; check "$?" "0" "a capability added to needs: the re-run is the tool's own, no --force"
grep -q 'any runner carrying these takes the job' "$T/out"; check "$?" "1" "…a change that narrows the job says nothing of widening"
check "$(runson "$R")" "runs-on: [self-hosted, macOS, browser, git-2.43]" "…each capability asked for"
grep -q 'until one labelled self-hosted, macOS, browser, git-2.43 is online' "$T/out"; check "$?" "0" "…and the next step names them"
check "$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['needs'])" "$R/.github/ci.json")" "['macos', 'browser', 'git-2.43']" "…ci.json keeps needs"
"$CP" "$R" --to self-hosted > /dev/null 2>&1; check "$?" "0" "…a further re-run"
check "$(runson "$R")" "runs-on: [self-hosted, macOS, browser, git-2.43]" "…holds"
"$CP" "$R" --to actions > /dev/null 2>&1; check "$?" "0" "away to actions"
check "$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['needs'])" "$R/.github/ci.json")" "['macos', 'browser', 'git-2.43']" "…needs crosses a switch: it is the repo's"
"$CP" "$R" --to self-hosted > /dev/null 2>&1
check "$(runson "$R")" "runs-on: [self-hosted, macOS, browser, git-2.43]" "…and back asks for the same"
needs "$R" '["browser", "macOS", "public", "Browser", "BROWSER"]'
"$CP" "$R" --to self-hosted --force > /dev/null 2>&1; check "$?" "0" "needs in any order, with public and a repeat"
check "$(runson "$R")" "runs-on: [self-hosted, macOS, browser]" "…the OS first, each label once, public no label"
for os in '["macos", "linux"]' '["linux"]' '["windows", "browser"]'; do
  needs "$R" "$os"; "$CP" "$R" --to self-hosted --force > "$T/out" 2>&1; check "$?" "2" "needs $os: refused in the literal form, a Mac's"
  grep -q 'the literal form asks for a runner Mac' "$T/out"; check "$?" "0" "…saying why"
  check "$(runson "$R")" "runs-on: [self-hosted, macOS, browser]" "…nothing written"
done
needs "$R" '["macos", "linux"]'
"$CP" "$R" --to self-hosted --force --runs-on-var POOL > /dev/null 2>&1; check "$?" "0" "…the variable form takes them: a lane decides"
for bad in '"macos"' '["bad label"]' '["evil]\nrun: x"]' '[1]' '["-x"]'; do
  R="$T/n2"; rm -rf "$R"; newrepo "$R"; printf '{"provider": "actions", "check": "sh check.sh", "needs": %s}\n' "$bad" > "$R/.github/ci.json"; cp "$R/.github/workflows/check.yml" "$T/n2.yml"
  "$CP" "$R" --to self-hosted > "$T/out" 2>&1; check "$?" "2" "needs $bad: refused"
  grep -q "must list some of" "$T/out"; check "$?" "0" "…saying what it may hold"
  check "$(cmp -s "$T/n2.yml" "$R/.github/workflows/check.yml" && echo same)" "same" "…check.yml untouched"
done
R="$T/n3"; newrepo "$R"; "$CP" "$R" --to self-hosted > /dev/null 2>&1; needs "$R" '["macos", "browser"]'
sed 's/runs-on: \[self-hosted, macOS\]/runs-on: [self-hosted, macOS, laptop]/' "$R/.github/workflows/check.yml" > "$T/n3.yml" && mv "$T/n3.yml" "$R/.github/workflows/check.yml"
"$CP" "$R" --to self-hosted > "$T/out" 2>&1; check "$?" "0" "a literal as this tool wrote it before: the labels key's labels, no --force"
check "$(runson "$R")" "runs-on: [self-hosted, macOS, browser]" "…a re-run moves it to capabilities"
sed 's/runs-on: \[self-hosted, macOS, browser\]/runs-on: [self-hosted, macOS, gpu]/' "$R/.github/workflows/check.yml" > "$T/n3.yml" && mv "$T/n3.yml" "$R/.github/workflows/check.yml"
"$CP" "$R" --to self-hosted > "$T/out" 2>&1; check "$?" "2" "a label neither needs nor the key names: a hand edit, held"
grep -q "its runs-on, \[self-hosted, macOS, gpu\], is not this tool's: that is .self-hosted., the OS" "$T/out"; check "$?" "0" "…saying what it may name"
R="$T/n4"; newrepo "$R"; "$CP" "$R" --to self-hosted > /dev/null 2>&1; needs "$R" '["macos", "browser"]'; "$CP" "$R" --to self-hosted > /dev/null 2>&1
mkdir -p "$R/.helloworld"
"$CP" "$R" --to self-hosted > /dev/null 2>&1; check "$?" "0" "a literal of capabilities, .helloworld/ added: a re-run"
check "$(runson "$R")" "runs-on: [self-hosted, macOS, browser]" "…keeps the literal form, as a literal on the runner Mac did"
: > "$T/gh/calls"; "$CP" "$R" --runner install --dry-run > "$T/out" 2>&1
grep -q "names the labels itself (the literal form)" "$T/out"; check "$?" "0" "…--runner install says why it sets no variable"

echo "the landing review of 2026-11-01: what still routes, and what stays a hand edit"
# a change caps judges on what GitHub runs, not only on this checkout
R="$T/rv1"; newrepo "$R"; WF="$R/.github/workflows/check.yml"
printf 'jobs:\n  check:\n    runs-on: [self-hosted, macOS, box1]\n' > "$WF"
git -C "$R" add -A; git -C "$R" -c user.name=t -c user.email=t@t commit -qm main; git -C "$R" update-ref refs/remotes/origin/main HEAD
printf 'jobs:\n  check:\n    runs-on: [self-hosted, macOS, browser]\n' > "$WF"
echo "$keep_runners" > "$T/gh/runners.json"; echo '{"box1": ["browser"]}' > "$CAPS"; : > "$T/gh/calls"
"$CP" "$R" --runner caps > "$T/out" 2>&1; check "$?" "2" "a branch that moved its literal, main still naming the label: refused"
grep -q "origin/main:check.yml's runs-on asks for .*box1.*which box1 carries now" "$T/out"; check "$?" "0" "…naming main's file"
check "$(grep -c -- '-X PUT\|-X DELETE' "$T/gh/calls")" "0" "…before any write"
git -C "$R" add -A; git -C "$R" -c user.name=t -c user.email=t@t commit -qm moved; git -C "$R" update-ref refs/remotes/origin/main HEAD
"$CP" "$R" --runner caps --dry-run > "$T/out" 2>&1; check "$?" "0" "the move on main: the label may go"
git -C "$R" update-ref -d refs/remotes/origin/main; : > "$T/gh/calls"
"$CP" "$R" --runner caps > "$T/out" 2>&1; check "$?" "2" "origin/main unreadable: refused, a write would follow"
grep -q "could not read origin/main's workflows" "$T/out"; check "$?" "0" "…saying so"
check "$(grep -c -- '-X PUT\|-X DELETE' "$T/gh/calls")" "0" "…before any write"
git -C "$R" update-ref refs/remotes/origin/main HEAD; touch "$T/gh/fetch.fail"
"$CP" "$R" --runner caps > "$T/out" 2>&1; check "$?" "2" "origin unreachable: refused"
grep -q 'could not reach origin' "$T/out"; check "$?" "0" "…saying so"
rm -f "$T/gh/fetch.fail"
echo master > "$T/gh/default"; git -C "$R" update-ref refs/remotes/origin/master HEAD
"$CP" "$R" --runner caps --dry-run > /dev/null 2>&1; check "$?" "0" "a default branch of another name: fetched by the name origin gives"
printf 'jobs:\n  check:\n    runs-on: [self-hosted, box1]\n' > "$R/.github/workflows/old.yml"
git -C "$R" add -A; git -C "$R" -c user.name=t -c user.email=t@t commit -qm old; git -C "$R" update-ref refs/remotes/origin/master HEAD
rm "$R/.github/workflows/old.yml"; "$CP" "$R" --runner caps --dry-run > "$T/out" 2>&1; check "$?" "2" "…and judged"
grep -q "origin/master:old.yml's runs-on asks for" "$T/out"; check "$?" "0" "…by that name"
echo none > "$T/gh/default"
"$CP" "$R" --runner caps --dry-run > "$T/out" 2>&1; check "$?" "0" "an origin with no branch yet: it runs nothing"
grep -q 'origin has no default branch yet' "$T/out"; check "$?" "0" "…said"
rm -f "$T/gh/default"; git -C "$R" update-ref refs/remotes/origin/main HEAD
printf 'jobs:\n  check:\n    runs-on: [self-hosted, box1]\n' > "$R/.github/workflows/nächtlich.yml"
git -C "$R" add -A; git -C "$R" -c user.name=t -c user.email=t@t commit -qm umlaut; git -C "$R" update-ref refs/remotes/origin/main HEAD
rm "$R/.github/workflows/nächtlich.yml"; "$CP" "$R" --runner caps --dry-run > "$T/out" 2>&1; check "$?" "2" "a workflow on origin with a name git quotes: read, and judged"
git -C "$R" checkout -q -- .github/workflows; rm "$R/.github/workflows/nächtlich.yml"
git -C "$R" add -A; git -C "$R" -c user.name=t -c user.email=t@t commit -qm gone; git -C "$R" update-ref refs/remotes/origin/main HEAD
git -C "$R" rev-parse HEAD:.github/workflows/check.yml > "$T/blob"; BLOB=$(cat "$T/blob")
OBJ="$R/.git/objects/$(cut -c1-2 "$T/blob")/$(cut -c3- "$T/blob")"; mv "$OBJ" "$T/blob.keep"
"$CP" "$R" --runner caps > "$T/out" 2>&1; check "$?" "2" "a workflow on origin/main that cannot be read: refused, never read as empty"
mv "$T/blob.keep" "$OBJ"
# a runs-on no reader here can judge
unjudged() { # unjudged <label> <rc> <the job's lines>
  printf 'jobs:\n  check:\n%b\n' "$3" > "$WF3"; echo "$keep_runners" > "$T/gh/runners.json"; : > "$T/gh/calls"
  "$CP" "$R3" --runner caps > "$T/out" 2>&1; check "$?" "$2" "$1"
  [ "$2" = 0 ] || check "$(grep -c -- '-X PUT\|-X DELETE' "$T/gh/calls")" "0" "…before any write"; }
unjudged "a runner group's mapping naming the label going: refused" 2 '    runs-on: { group: g, labels: [box1] }'
unjudged "a block mapping naming it: refused" 2 '    runs-on:\n      group: g\n      labels: [box1]'
unjudged "a matrix over it: refused" 2 '    strategy:\n      matrix:\n        os: [box1]\n    runs-on: ${{ matrix.os }}'
unjudged "a quoted expression: refused" 2 '    strategy:\n      matrix:\n        os: [box1]\n    runs-on: "${{ matrix.os }}"'
unjudged "an expression in a flow list: refused" 2 '    strategy:\n      matrix:\n        h: [box1]\n    runs-on: [self-hosted, "${{ matrix.h }}"]'
unjudged "a quoted expression in a block list: refused" 2 '    strategy:\n      matrix:\n        h: [box1]\n    runs-on:\n      - self-hosted\n      - "${{ matrix.h }}"'
unjudged "an anchor: refused" 2 '    runs-on: &mac [self-hosted, box1]'
unjudged "a space before the colon: refused" 2 '    runs-on : box1'
unjudged "a block scalar: refused" 2 '    runs-on: >-\n      box1'
unjudged "a YAML tag: refused" 2 '    runs-on: !!seq [box1]'
unjudged "a label that only starts alike is no mention" 0 '    strategy:\n      matrix:\n        os: [box10, my-box1]\n    runs-on: ${{ matrix.os }}'
grep -q "⚠ check.yml's runs-on .*not judged" "$T/out"; check "$?" "0" "…said, not judged"
echo "{\"total_count\":1,\"runners\":[{\"id\":32,\"name\":\"arm\",\"status\":\"online\",\"labels\":[$RO,{\"name\":\"macos-arm\",\"type\":\"custom\"}]}]}" > "$T/gh/runners.json"
echo '{"arm": ["browser"]}' > "$CAPS"; printf 'jobs:\n  check:\n    runs-on: macos-arm\n' > "$WF3"
"$CP" "$R3" --runner caps --dry-run > "$T/out" 2>&1; check "$?" "2" "a runner's label shaped like a hosted image: judged, refused"
printf 'jobs:\n  check:\n    runs-on: [self-hosted, caf\xe9-box]\n' > "$WF3"
"$CP" "$R3" --runner caps --dry-run > "$T/out" 2>&1; grep -q 'Traceback' "$T/out"; check "$?" "1" "a workflow byte that is not UTF-8: no traceback"
# --runner install asks the same judge as caps
R2="$T/cap6"; newrepo "$R2"; WF2="$R2/.github/workflows/check.yml"; echo '{"laptop": ["browser", "whole-line"]}' > "$CAPS"
installs() { # installs <label> <the --labels it should register> <check.yml's job> [nightly.yml's job]
  printf 'jobs:\n  check:\n%b\n' "$3" > "$WF2"; rm -f "$R2/.github/workflows/nightly.yml"
  [ -z "${4:-}" ] || printf 'jobs:\n  n:\n%b\n' "$4" > "$R2/.github/workflows/nightly.yml"
  "$CP" "$R2" --runner install --dry-run > "$T/out" 2>&1; check "$?" "0" "$1"
  grep -q "config.sh --name laptop --labels $2;" "$T/out"; check "$?" "0" "…registers $2"; }
KEPT=browser,whole-line,laptop
installs "a block list naming the key's label" "$KEPT" '    runs-on:\n      - self-hosted\n      - laptop'
installs "another workflow naming it" "$KEPT" '    runs-on: [self-hosted, macOS]' '    runs-on: [self-hosted, macOS, laptop]'
installs "a second job naming it" "$KEPT" '    runs-on: [self-hosted, macOS, browser]\n  two:\n    runs-on: [self-hosted, macOS, laptop]'
installs "a file it cannot read naming it" "$KEPT" '    strategy:\n      matrix:\n        os: [laptop]\n    runs-on: ${{ matrix.os }}'
installs "a literal only another runner serves: no reason to keep the key's label" browser,whole-line '    runs-on: [macOS, gpu]'
grep -q "⚠ a runs-on asks for gpu, which runner laptop would not carry" "$T/out"; check "$?" "0" "…warned"
installs "a matrix naming no label of the key's" browser,whole-line '    runs-on: ${{ matrix.os }}'
grep -q "⚠ check.yml's runs-on .*not judged" "$T/out"; check "$?" "0" "…said, not judged"
installs "hosted images: nothing asked" browser,whole-line '    runs-on: ubuntu-latest'
grep -q 'would not carry' "$T/out"; check "$?" "1" "…nothing warned of"
echo '{"laptop": []}' > "$CAPS"; printf 'jobs:\n  check:\n    runs-on: [self-hosted, macOS, browser]\n' > "$WF2"
"$CP" "$R2" --runner install --dry-run > /dev/null 2>&1; check "$?" "2" "a table row with no capabilities: refused whatever the workflows say"
printf 'self-hosted\nmacOS\nmacos-arm\n' > "$T/rv.labels"; cp "$REGATTA_CONFIG/wharf/ci-runner-labels" "$T/rv.labels.keep"; cp "$T/rv.labels" "$REGATTA_CONFIG/wharf/ci-runner-labels"
echo '{"macos-arm": ["browser"]}' > "$CAPS"; printf 'jobs:\n  check:\n    runs-on: macos-arm\n' > "$WF2"
"$CP" "$R2" --runner install --dry-run > "$T/out" 2>&1
grep -q 'config.sh --name macos-arm --labels browser,macos-arm;' "$T/out"; check "$?" "0" "the key's label shaped like a hosted image: kept, as caps judges it"
cp "$T/rv.labels.keep" "$REGATTA_CONFIG/wharf/ci-runner-labels"
rm -f "$R2/.github/workflows/nightly.yml"
# the variable form beside what caps cannot read: capabilities registered, the variable left on them
echo '{"laptop": ["browser", "whole-line"]}' > "$CAPS"; rm -rf "$T/gh/vars"; mkdir -p "$T/gh/vars"
echo '{"name":"CI_RUNS_ON","value":"[\"self-hosted\",\"macOS\",\"browser\"]"}' > "$T/gh/vars/CI_RUNS_ON.json"
VARON="\${{ fromJSON(vars.CI_RUNS_ON || '\"ubuntu-latest\"') }}"
printf 'jobs:\n  check:\n    runs-on: %s\n' "$VARON" > "$WF2"; printf 'jobs:\n  n:\n    runs-on: ${{ matrix.os }}\n' > "$R2/.github/workflows/nightly.yml"
"$CP" "$R2" --runner install --dry-run > "$T/out" 2>&1
grep -q 'config.sh --name laptop --labels browser,whole-line;' "$T/out"; check "$?" "0" "the variable form, a hosted matrix beside it: capabilities registered"
grep -q 'already routes to .*laptop carries its labels' "$T/out"; check "$?" "0" "…the variable left on them"
printf 'jobs:\n  n:\n    runs-on: [self-hosted, laptop]\n' > "$R2/.github/workflows/nightly.yml"; rm -f "$T/gh/vars/CI_RUNS_ON.json"
"$CP" "$R2" --runner install --dry-run > "$T/out" 2>&1
grep -q 'config.sh --name laptop --labels browser,whole-line,laptop;' "$T/out"; check "$?" "0" "the variable form, a literal naming the key's label: kept"
grep -q 'would create variable CI_RUNS_ON: None → \["self-hosted","macOS","browser","whole-line"\]' "$T/out"; check "$?" "0" "…the kept label never reaches the variable"
# a variable beside the one install moves: read, as a fresh registration meets no other judge
echo '{"laptop": ["browser", "whole-line"]}' > "$CAPS"; rm -rf "$T/gh/vars"; mkdir -p "$T/gh/vars"
echo '{"name":"CI_RUNS_ON","value":"[\"self-hosted\",\"macOS\",\"browser\"]"}' > "$T/gh/vars/CI_RUNS_ON.json"
echo '{"name":"CI_RUNS_ON_FULL","value":"[\"self-hosted\",\"macOS\",\"laptop\"]"}' > "$T/gh/vars/CI_RUNS_ON_FULL.json"
printf 'jobs:\n  check:\n    runs-on: %s\n' "\${{ fromJSON(github.event_name != 'pull_request' && vars.CI_RUNS_ON_FULL || vars.CI_RUNS_ON || '\"ubuntu-latest\"') }}" > "$WF2"; rm -f "$R2/.github/workflows/nightly.yml"
"$CP" "$R2" --runner install --dry-run > "$T/out" 2>&1
grep -q 'config.sh --name laptop --labels browser,whole-line,laptop;' "$T/out"; check "$?" "0" "a split form's _FULL naming the key's label: kept"
printf 'jobs:\n  check:\n    runs-on: [self-hosted, macOS]\n' > "$WF2"
printf 'jobs:\n  m:\n    runs-on: %s\n' "\${{ fromJSON(vars.CI_RUNS_ON_AUTOMERGE || vars.CI_RUNS_ON || '\"ubuntu-latest\"') }}" > "$R2/.github/workflows/automerge.yml"
rm -rf "$T/gh/vars"; mkdir -p "$T/gh/vars"; echo '{"name":"CI_RUNS_ON_AUTOMERGE","value":"[\"self-hosted\",\"macOS\",\"laptop\"]"}' > "$T/gh/vars/CI_RUNS_ON_AUTOMERGE.json"
"$CP" "$R2" --runner install --dry-run > "$T/out" 2>&1
grep -q 'config.sh --name laptop --labels browser,whole-line,laptop;' "$T/out"; check "$?" "0" "a literal check.yml, automerge's variable naming it: kept"
echo '{"name":"CI_RUNS_ON_AUTOMERGE","value":"[\"self-hosted\",\"macOS\",\"gpu\"]"}' > "$T/gh/vars/CI_RUNS_ON_AUTOMERGE.json"
"$CP" "$R2" --runner install --dry-run > "$T/out" 2>&1
grep -q "⚠ a runs-on asks for gpu, which runner laptop would not carry" "$T/out"; check "$?" "0" "…one it would not carry: warned"
echo '{"name":"CI_RUNS_ON_AUTOMERGE","value":"{\"group\":\"g\",\"labels\":[\"laptop\"]}"}' > "$T/gh/vars/CI_RUNS_ON_AUTOMERGE.json"
"$CP" "$R2" --runner install --dry-run > "$T/out" 2>&1
grep -q 'config.sh --name laptop --labels browser,whole-line,laptop;' "$T/out"; check "$?" "0" "a variable holding a mapping that names the key's label: kept"
rm -rf "$T/gh/vars"; rm -f "$R2/.github/workflows/automerge.yml"
# no table, or --labels: no write rests on origin's workflows, so an unreachable origin stops nothing
rm -f "$CAPS"; touch "$T/gh/fetch.fail"
"$CP" "$R2" --runner install --dry-run > "$T/out" 2>&1; check "$?" "0" "no table, origin unreachable: an install is not stopped"
"$CP" "$R2" --runner install --dry-run --host h2 --name box2 --labels self-hosted,macOS,shared > /dev/null 2>&1; check "$?" "0" "…nor a fleet Mac's, by --labels"
echo '{"laptop": ["browser"]}' > "$CAPS"
"$CP" "$R2" --runner install --dry-run > "$T/out" 2>&1; check "$?" "2" "a listed runner, origin unreachable: refused, a write rests on it"
rm -f "$T/gh/fetch.fail"
echo '{"laptop": ["browser", "whole-line"]}' > "$CAPS"
printf 'jobs:\n  check:\n    runs-on: [self-hosted, macOS, laptop]\n' > "$WF2"; printf '{"provider": "self-hosted", "check": "sh check.sh"}\n' > "$R2/.github/ci.json"
"$CP" "$R2" --runner install --dry-run > "$T/out" 2>&1
grep -q "names the labels itself (the literal form)" "$T/out"; check "$?" "0" "the old literal on a capped runner: still read as the literal form"
rm -f "$R2/.github/ci.json"
# a real install on a configured runner: its labels PUT, and the wait for them met
LCFG='{"total_count":1,"runners":[{"id":41,"name":"laptop","status":"online","labels":[{"name":"self-hosted","type":"read-only"},{"name":"macOS","type":"read-only"},{"name":"laptop","type":"custom"}]}]}'
fakerunner "$RD" nested; touch "$RD/.runner"; echo "$LCFG" > "$T/gh/runners.json"; rm -f "$R2/.github/workflows/nightly.yml"
printf 'jobs:\n  check:\n    runs-on: [self-hosted, macOS, laptop]\n' > "$WF2"
"$CP" "$R2" --runner install > "$T/out" 2>&1; check "$?" "0" "a real install, configured, a literal naming the key's label"
check "$(customs)" "laptop=browser,whole-line,laptop" "…capabilities PUT beside the label the literal asks for"
printf 'jobs:\n  check:\n    runs-on: [self-hosted, macOS, browser]\n' > "$WF2"; echo "$LCFG" > "$T/gh/runners.json"
"$CP" "$R2" --runner install > "$T/out" 2>&1; check "$?" "0" "a real install, configured, a literal of capabilities"
check "$(customs)" "laptop=browser,whole-line" "…the runner carries its capabilities alone"
printf 'jobs:\n  check:\n    runs-on: %s\n' "$VARON" > "$WF2"; echo "$LCFG" > "$T/gh/runners.json"; mkdir -p "$T/gh/vars"
echo '{"name":"CI_RUNS_ON","value":"[\"self-hosted\",\"macOS\",\"laptop\"]"}' > "$T/gh/vars/CI_RUNS_ON.json"
"$CP" "$R2" --runner install > "$T/out" 2>&1; check "$?" "0" "a real install, configured, the variable naming the key's label"
check "$(customs)" "laptop=browser,whole-line,laptop" "…the label stays until the variable has moved"
check "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["value"])' "$T/gh/vars/CI_RUNS_ON.json")" '["self-hosted","macOS","browser","whole-line"]' "…which it then has"
"$CP" "$R2" --runner caps > "$T/out" 2>&1; check "$?" "0" "…and --runner caps drops it"
check "$(customs)" "laptop=browser,whole-line" "…leaving the capabilities"
rm -rf "$T/gh/vars"
printf 'self-hosted\nmacOS\nlaptop\n' > "$REGATTA_CONFIG/wharf/ci-runner-labels"
printf 'jobs:\n  check:\n    runs-on: [self-hosted, macOS, browser]\n' > "$WF2"
printf 'buildbox\n' > "$REGATTA_CONFIG/wharf/ci-runner-kind"; printf '{"provider": "buildbox", "check": "sh check.sh"}\n' > "$R2/.github/ci.json"
"$CP" "$R2" --runner install --dry-run > "$T/out" 2>&1
grep -q 'no repository variable set' "$T/out"; check "$?" "0" "install on a ci.json naming the old kind: read as the kind"
rm -f "$REGATTA_CONFIG/wharf/ci-runner-kind" "$R2/.github/ci.json"
# a variable holding one label: a fleet's, read as caps reads it
echo '{"laptop": ["browser"]}' > "$CAPS"; rm -rf "$T/gh/vars"; mkdir -p "$T/gh/vars"; printf 'jobs:\n  check:\n    runs-on: %s\n' "$VARON" > "$WF2"
echo '{"name":"CI_RUNS_ON","value":"\"shared\""}' > "$T/gh/vars/CI_RUNS_ON.json"
echo '{"total_count":1,"runners":[{"id":42,"name":"box1","status":"online","labels":[{"name":"self-hosted","type":"read-only"},{"name":"macOS","type":"read-only"},{"name":"shared","type":"custom"}]}]}' > "$T/gh/runners.json"
"$CP" "$R2" --runner install --dry-run > "$T/out" 2>&1
grep -q 'variable CI_RUNS_ON left at "shared": registered runner box1 carries its labels' "$T/out"; check "$?" "0" "a variable of one label another runner carries: never re-routed to the newcomer"
# a variable caps cannot read
rm -rf "$T/gh/vars"; mkdir -p "$T/gh/vars"; echo '{"box1": ["browser"]}' > "$CAPS"
echo '{"name":"RUNNER","value":"box1"}' > "$T/gh/vars/RUNNER.json"
unjudged "a variable holding one plain label: refused" 2 '    runs-on: ${{ vars.RUNNER }}'
grep -q "variable RUNNER asks for box1, which box1 carries now" "$T/out"; check "$?" "0" "…naming the variable"
unjudged "the same in another case: GitHub's contexts ignore it" 2 '    runs-on: ${{ VARS.RUNNER }}'
unjudged "a variable in a block list: refused" 2 '    runs-on:\n      - self-hosted\n      - ${{ vars.RUNNER }}'
unjudged "a quoted key: refused" 2 '    "runs-on": [self-hosted, box1]'
echo '{"name":"RUNNER","value":"\"ubuntu-latest\""}' > "$T/gh/vars/RUNNER.json"
unjudged "a variable holding a hosted image: nothing to judge" 0 '    runs-on: ${{ vars.RUNNER }}'
grep -q "not judged\|no registered runner carries it" "$T/out"; check "$?" "1" "…nothing said"
echo "{\"total_count\":1,\"runners\":[{\"id\":33,\"name\":\"arm\",\"status\":\"online\",\"labels\":[$RO,{\"name\":\"macos-arm\",\"type\":\"custom\"}]}]}" > "$T/gh/runners.json"
echo '{"name":"RUNNER","value":"\"macos-arm\""}' > "$T/gh/vars/RUNNER.json"; echo '{"arm": ["browser"]}' > "$CAPS"
printf 'jobs:\n  check:\n    runs-on: ${{ fromJSON(vars.RUNNER) }}\n' > "$WF3"
"$CP" "$R3" --runner caps --dry-run > "$T/out" 2>&1; check "$?" "2" "a variable holding a runner's label shaped like a hosted image: judged, refused"
echo '{"box1": ["browser"]}' > "$CAPS"
# a label moving between runners leaves the fleet no poorer
echo "{\"total_count\":2,\"runners\":[{\"id\":34,\"name\":\"box1\",\"status\":\"online\",\"labels\":[$RO,{\"name\":\"gpu\",\"type\":\"custom\"}]},{\"id\":35,\"name\":\"box2\",\"status\":\"online\",\"labels\":[$RO,{\"name\":\"gpu\",\"type\":\"custom\"}]}]}" > "$T/gh/runners.json"
printf 'jobs:\n  check:\n    strategy:\n      matrix:\n        os: [gpu]\n    runs-on: ${{ matrix.os }}\n' > "$WF3"
"$CP" "$R3" --runner caps --dry-run > "$T/out" 2>&1; check "$?" "0" "a label a matrix names leaving one runner of two: not refused"
echo '{"box1": ["browser"], "box2": ["browser"]}' > "$CAPS"
"$CP" "$R3" --runner caps --dry-run > "$T/out" 2>&1; check "$?" "2" "…leaving both: refused"
grep -q "takes off every runner" "$T/out"; check "$?" "0" "…saying so"
echo '{"box1": ["browser"]}' > "$CAPS"
echo '{"name":"RUNNER","value":"{\"group\":\"g\",\"labels\":[\"self-hosted\",\"box1\"]}"}' > "$T/gh/vars/RUNNER.json"
unjudged "a variable holding a runner group's mapping: refused, by what it names" 2 '    runs-on: ${{ fromJSON(vars.RUNNER) }}'
grep -q "variable RUNNER's runs-on .* is no label list or variable this tool reads" "$T/out"; check "$?" "0" "…naming the variable"
echo '{"name":"RUNNER","value":"box1"}' > "$T/gh/vars/RUNNER.json"
unjudged "a variable's name in lower case: GitHub's is upper" 2 '    runs-on: ${{ vars.runner }}'
unjudged "a variable mixed with a label: refused" 2 '    runs-on: [self-hosted, box1, "${{ vars.EXTRA }}"]'
unjudged "a label as an unset variable's default: refused" 2 "    runs-on: \${{ vars.UNSET || 'box1' }}"
unjudged "a fromJSON default naming it: refused" 2 "    runs-on: \${{ fromJSON(vars.POOL || '[\"self-hosted\",\"box1\"]') }}"
unjudged "an expression choosing it: refused" 2 "    runs-on: \${{ github.event_name == 'push' && 'box1' || vars.CI_RUNS_ON }}"
unjudged "a chain of variables to a hosted image: routed_vars' alone" 0 "    runs-on: \${{ fromJSON(vars.A_AUTOMERGE || vars.A || '\"ubuntu-latest\"') }}"
grep -q "not judged" "$T/out"; check "$?" "1" "…nothing said"
rm -rf "$T/gh/vars"; mkdir -p "$T/gh/vars"
# what stays a hand edit, and what `needs` says
rm -f "$CAPS"
R="$T/rvA"; newrepo "$R"; printf '{"check": "sh check.sh", "needs": ["macos", "browser"]}\n' > "$R/.github/ci.json"; "$CP" "$R" --to self-hosted > /dev/null 2>&1
printf '{"check": "sh check.sh", "needs": ["macos", "browser"]}\n' > "$R/.github/ci.json"
"$CP" "$R" > "$T/out" 2>&1; grep -q 'self-hosted (inferred' "$T/out"; check "$?" "0" "a capability literal, ci.json with needs and no provider: self-hosted, inferred"
R="$T/rvD"; newrepo "$R"; printf '{"provider": "self-hosted", "check": "sh check.sh"}\n' > "$R/.github/ci.json"
printf 'jobs:\n  check:\n    runs-on: [macOS, browser]\n' > "$R/.github/workflows/check.yml"
echo '{"total_count":1,"runners":[{"id":7,"name":"box","status":"online","labels":[{"name":"self-hosted"},{"name":"macOS"},{"name":"browser"}]}]}' > "$T/gh/runners.json"
"$CP" "$R" > "$T/out" 2>&1; grep -q 'no online runner labelled' "$T/out"; check "$?" "1" "status on a literal with no self-hosted, a runner carrying it: no false alarm"
printf 'jobs:\n  check:\n    runs-on:\n      - self-hosted\n      - browser\n' > "$R/.github/workflows/check.yml"
"$CP" "$R" > "$T/out" 2>&1; grep -q 'no online runner labelled' "$T/out"; check "$?" "1" "…nor on a block list"
printf 'jobs:\n  check:\n    runs-on: ${{ matrix.os }}\n' > "$R/.github/workflows/check.yml"
"$CP" "$R" > "$T/out" 2>&1; grep -q 'no online runner labelled' "$T/out"; check "$?" "1" "…nor on one it cannot read: nothing claimed"
for shape in '${{ vars.RUNNER }}' '${{ fromJSON(vars.A || vars.B) }}' '[self-hosted, macOS, "${{ matrix.pool }}"]'; do
  printf 'jobs:\n  check:\n    runs-on: %s\n' "$shape" > "$R/.github/workflows/check.yml"
  "$CP" "$R" > "$T/out" 2>&1; grep -q 'no online runner labelled' "$T/out"; check "$?" "1" "status on $shape: nothing claimed"
done
printf 'jobs:\n  n:\n    runs-on: [macOS, browser]\n    steps:\n      - run: sudo make\n' > "$R/.github/workflows/nightly.yml"
"$CP" "$R" > "$T/out" 2>&1; grep -q 'nightly.yml:.* runs sudo on the runner Mac' "$T/out"; check "$?" "0" "the host-write scan reads a capability literal with no self-hosted in it"
printf 'jobs:\n  n:\n    runs-on:\n      - macOS\n      - browser\n    steps:\n      - run: sudo make\n' > "$R/.github/workflows/nightly.yml"
"$CP" "$R" > "$T/out" 2>&1; grep -q 'nightly.yml:.* runs sudo on the runner Mac' "$T/out"; check "$?" "0" "…and a block list"
echo '{"total_count":0,"runners":[]}' > "$T/gh/runners.json"
for empty in '[]' '["public"]'; do
  R="$T/rvB"; rm -rf "$R"; newrepo "$R"; printf '{"provider": "actions", "check": "sh check.sh", "needs": %s}\n' "$empty" > "$R/.github/ci.json"
  "$CP" "$R" --to self-hosted > /dev/null 2>&1; check "$?" "0" "needs $empty"
  check "$(runson "$R")" "runs-on: [self-hosted, macOS]" "…macOS, never a bare [self-hosted] a Linux runner would take"
  "$CP" "$R" --to self-hosted > /dev/null 2>&1; check "$?" "0" "…a re-run is its own"
done
echo '{"laptop": ["browser"]}' > "$CAPS"; R="$T/rvC"; newrepo "$R"; printf '{"provider": "actions", "check": "sh check.sh", "needs": ["linx"]}\n' > "$R/.github/ci.json"
"$CP" "$R" --to self-hosted --runs-on-var POOL > "$T/out" 2>&1; check "$?" "0" "a mistyped word, the variable form"
grep -q "⚠ no runner in ci-runner-caps.json lists linx" "$T/out"; check "$?" "0" "…warned there too"
rm -f "$CAPS"; R="$T/rv2"; newrepo "$R"; "$CP" "$R" --to self-hosted > /dev/null 2>&1
for lit in '[self-hosted, linux]' '[self-hosted, Linux]' '[self-hosted, windows]' '[self-hosted]' 'self-hosted'; do
  sed "s/runs-on: .*/runs-on: $lit/" "$R/.github/workflows/check.yml" > "$T/rv.yml"; cp "$T/rv.yml" "$R/.github/workflows/check.yml"
  "$CP" "$R" --to self-hosted > /dev/null 2>&1; check "$?" "2" "$lit, ci.json needing macOS: held as a hand edit, as on main"
  "$CP" "$R" --to actions > /dev/null 2>&1; check "$?" "2" "…by --to actions too"
done
"$CP" "$R" --to self-hosted --force > /dev/null 2>&1; needs "$R" '["linux"]'
sed "s/runs-on: .*/runs-on: [self-hosted, Linux]/" "$R/.github/workflows/check.yml" > "$T/rv.yml"; cp "$T/rv.yml" "$R/.github/workflows/check.yml"
"$CP" "$R" --to actions > /dev/null 2>&1; check "$?" "0" "[self-hosted, Linux] where needs says linux: the tool's own, --to actions takes it"
"$CP" "$R" --to self-hosted --runs-on-var POOL > /dev/null 2>&1; check "$?" "0" "…and the variable form carries a Linux need"
R="$T/rv2b"; newrepo "$R"; needs "$R" '["macos", "browser"]'; "$CP" "$R" --to self-hosted > /dev/null 2>&1; needs "$R" '["macos"]'
"$CP" "$R" --to self-hosted > "$T/out" 2>&1; check "$?" "2" "a capability dropped from needs: held"
grep -q "a label just dropped from .needs. leaves the line to edit by hand" "$T/out"; check "$?" "0" "…saying how to go on"
R="$T/rv3"; newrepo "$R"; setruns "$R" "[self-hosted, linux]"
"$CP" "$R" > "$T/out" 2>&1; grep -q 'actions (inferred' "$T/out"; check "$?" "0" "[self-hosted, linux], no ci.json: not the runner Mac, as on main"
R="$T/rv4"; newrepo "$R"; printf '{"provider": "actions", "check": "sh check.sh", "needs": ["browser"]}\n' > "$R/.github/ci.json"
"$CP" "$R" --to self-hosted > /dev/null 2>&1; check "$?" "0" "a capability with no OS beside it"
check "$(runson "$R")" "runs-on: [self-hosted, macOS, browser]" "…reads as macOS, as an absent needs does"
R="$T/rv5"; newrepo "$R"; "$CP" "$R" --to self-hosted > /dev/null 2>&1
sed "s/runs-on: .*/runs-on: [self-hosted, macOS, laptop]/" "$R/.github/workflows/check.yml" > "$T/rv.yml"; cp "$T/rv.yml" "$R/.github/workflows/check.yml"
"$CP" "$R" --to self-hosted > "$T/out" 2>&1; check "$?" "0" "a re-run off the labels key's literal"
grep -qF 'runs-on [self-hosted, macOS, laptop] → [self-hosted, macOS]' "$T/out"; check "$?" "0" "…says what it widens"
R="$T/rv6"; newrepo "$R"; echo '{"laptop": ["browser"]}' > "$CAPS"; printf '{"provider": "actions", "check": "sh check.sh", "needs": ["macos", "browsr"]}\n' > "$R/.github/ci.json"
"$CP" "$R" --to self-hosted > "$T/out" 2>&1; check "$?" "0" "a mistyped capability"
grep -q "⚠ no runner in ci-runner-caps.json lists browsr" "$T/out"; check "$?" "0" "…warned, as needs is open to any label"
R="$T/rv7"; newrepo "$R"
"$CP" "$R" --to self-hosted --runs-on-var CI_RUNS_ON > "$T/out" 2>&1
grep -q 'sets CI_RUNS_ON to \["self-hosted","macOS","browser"\]' "$T/out"; check "$?" "0" "the variable form's next step: what install will set, not the labels key's"
rm -f "$CAPS"; R="$T/rv8"; newrepo "$R"; printf '{"provider": ["x"], "check": "sh check.sh"}\n' > "$R/.github/ci.json"
"$CP" "$R" --to actions > "$T/out" 2>&1; grep -q 'Traceback' "$T/out"; check "$?" "1" "a provider that is no string, on --to: no traceback"

rm -f "$CAPS"; rm -rf "$T/gh/vars"; echo '{"total_count":0,"runners":[]}' > "$T/gh/runners.json"

echo "a Linux host's runner: the Linux share's suites, by capabilities (linux-runner, 2026-11-04)"
# The fake host as Linux (D1-C, a rootless container): FAKE_SYSTEM=Linux for its uname; a podman that keeps
# images, volumes and the build context under $T/ssh and runs the real entry script over a fresh copy of the
# image's runner for every `run` (its paths moved under $T/ssh), refusing with $T/ssh/nopodman, nouserns or
# nosubuids; a systemctl that knows --user only and starts a unit by running its Image, Volume and Exec through
# that podman; a loginctl whose linger is off with $T/ssh/nolinger; and a sudo that is never to be called
cat > "$T/ssh/rbin/sudo" <<'EOF'
#!/usr/bin/env bash
echo "sudo $*" >> "$FAKE_SSH/sudo"; exit 1
EOF
cat > "$T/ssh/rbin/podman" <<'EOF'
#!/usr/bin/env bash
D="$FAKE_SSH"
echo "podman $*" >> "$D/podman"
key() { printf '%s' "$1" | tr '/:' '__'; }
case "$1" in
  --version) [ -e "$D/nopodman" ] && exit 127; echo "podman version 4.9.3" ;;
  unshare) [ -e "$D/nopodman" ] && exit 127; [ -e "$D/nouserns" ] && exit 1
    if [ "$2" = test ]; then shift; exec "$@"; fi
    echo "         0       1000          1"
    case "$3" in */uid_map) [ -e "$D/nosubuids" ] || echo "         1     100000      65536" ;;
                 *) [ -e "$D/nosubgids" ] || echo "         1     100000      65536" ;; esac ;;
  build) ctx="${@: -1}"; tag=; prev=; for a in "$@"; do [ "$prev" = -t ] && tag=$a; prev=$a; done
    # the reference grammar podman's containers/image applies: lower case, separators between letters and digits
    printf '%s' "${tag#localhost/}" | grep -Eqx '[a-z0-9]+(([._]|__|-+)[a-z0-9]+)*' || { echo "fake podman: invalid reference format: $tag" >&2; exit 125; }
    for f in Containerfile entry.sh runner.tar.gz; do [ -f "$ctx/$f" ] || { echo "fake podman: no $f in the context" >&2; exit 1; }; done
    rm -rf "$D/img/$(key "$tag")"; mkdir -p "$D/img/$(key "$tag")"; cp "$ctx/Containerfile" "$ctx/entry.sh" "$ctx/runner.tar.gz" "$D/img/$(key "$tag")/" ;;
  image) case "$2" in exists) [ -d "$D/img/$(key "$3")" ] ;; prune) echo "pruned $*" >> "$D/prune" ;; *) exit 125 ;; esac ;;
  rmi) rm -rf "$D/img/$(key "$2")" ;;
  volume) case "$2" in create) mkdir -p "$D/vol/${@: -1}" ;; rm) [ -d "$D/vol/$3" ] && rm -rf "$D/vol/$3" ;;
            inspect) [ -d "$D/vol/${@: -1}" ] && echo "$D/vol/${@: -1}" ;; exists) [ -d "$D/vol/$3" ] ;; esac ;;
  run) shift; vol= ent=
    while [ $# -gt 0 ]; do case "$1" in --rm|-i) shift ;; -v) vol=$2; shift 2 ;; --entrypoint) ent=$2; shift 2 ;;
      --cap-drop=*|--cap-add=*|--security-opt=*|--network=*|--cpus=*|--memory=*|--memory-swap=*) echo "$1" >> "$D/runopts"; shift ;; *) break ;; esac; done
    img="$D/img/$(key "$1")"; shift
    [ -d "$img" ] || { echo "fake podman: no image" >&2; exit 125; }
    # --runner check's cases (free CI S6): their argv kept, their output and exit what the case wrote
    if [ "$ent" = python3 ]; then [ "$1" = -c ] && { printf '%s' "$2" > "$D/checkpy"; shift 2; }; printf '%s\n' "$@" > "$D/checkargs"; cat "$D/checkout" 2>/dev/null; exit "$(cat "$D/checkrc" 2>/dev/null || echo 0)"; fi
    V="$D/vol/${vol%%:*}"; mkdir -p "$V"
    [ "${vol#*:}" = /state:ro ] || [ "${vol#*:}" = /state:U ] || { echo "fake podman: a mount other than the state volume: $vol" >&2; exit 125; }
    if [ "$ent" = cat ]; then
      [ -e "$D/copy.fail" ] && { echo "fake podman: registration copy failed" >&2; exit 23; }
      cat "$V/${1#/state/}"; exit
    fi
    R="$D/ctr"; rm -rf "$R"; mkdir -p "$R"; tar xzf "$img/runner.tar.gz" -C "$R"
    sed -e "s#/runner/actions-runner#$R#g" -e "s#/state#$V#g" "$img/entry.sh" > "$D/entry.run"
    sum() { find "$V" -type f -exec cksum {} + 2>/dev/null | sort; }
    before=$(sum); rc=0; sh "$D/entry.run" "$@" || rc=$?
    if [ "${vol#*:}" = /state:ro ] && [ "$(sum)" != "$before" ]; then echo "fake podman: a write to a read-only volume" >&2; exit 125; fi
    exit $rc ;;
esac
EOF
cat > "$T/ssh/rbin/systemctl" <<'EOF'
#!/usr/bin/env bash
D="$FAKE_SSH"
[ "$1" = --user ] || { echo "system $*" >> "$D/systemctl"; echo "fake systemctl: --user only" >&2; exit 1; }
shift
u="$(cd ~ && pwd)/.config/containers/systemd/${2%.service}.container"
case "$1" in
  show-environment) [ -e "$D/nousersd" ] && exit 1; echo "HOME=$HOME" ;;
  daemon-reload) echo daemon-reload >> "$D/systemctl" ;;
  reset-failed) echo "reset-failed $2" >> "$D/systemctl" ;;
  is-active) [ -e "$D/active" ] ;;
  start) echo "start $2" >> "$D/systemctl"
    rc=0; podman run --rm -v "$(sed -n 's/^Volume=//p' "$u")" "$(sed -n 's/^Image=//p' "$u")" $(sed -n 's/^Exec=//p' "$u") < /dev/null || rc=$?
    echo "exit $rc" >> "$D/systemctl"; [ "$rc" = 0 ] && touch "$D/active"; true ;;
  # each unit named its own line; only the runner's own unit is the one "active" stands for (the rebuild's are not)
  stop) shift; for n in "$@"; do echo "stop $n" >> "$D/systemctl"; case $n in *-rebuild.*) ;; *) rm -f "$D/active" ;; esac; done ;;
  enable|disable) echo "$*" >> "$D/systemctl" ;;
  --no-pager) echo "systemctl status $3"; [ -e "$D/active" ] || exit 3 ;;
esac
EOF
cat > "$T/ssh/rbin/loginctl" <<'EOF'
#!/usr/bin/env bash
[ -e "$FAKE_SSH/nolinger" ] && echo no || echo yes
EOF
# newuidmap, newgidmap and slirp4netns stand-ins, so the probe finds them on any machine the suite runs on
for c in newuidmap newgidmap slirp4netns; do printf '#!/bin/sh\nexit 0\n' > "$T/ssh/rbin/$c"; done
# the host's cores ($FAKE_NPROC, 4 unless a case sets it), and its addresses and listeners for --runner check:
# an eth0 and a tailscale0 address, loopback, a wildcard sshd on both families, a listener on the Tailscale
# address alone, and resolved's stub on loopback, in iproute2's one-line forms
printf '#!/bin/sh\necho "${FAKE_NPROC:-4}"\n' > "$T/ssh/rbin/nproc"
cat > "$T/ssh/rbin/ip" <<'EOF'
#!/bin/sh
[ "$1 $2 $3" = "-o addr show" ] || exit 1
printf '%s\n' '1: lo    inet 127.0.0.1/8 scope host lo\       valid_lft forever preferred_lft forever' \
  '1: lo    inet6 ::1/128 scope host noprefixroute \       valid_lft forever preferred_lft forever' \
  '2: eth0    inet 192.0.2.12/24 metric 100 brd 192.0.2.255 scope global dynamic eth0\       valid_lft 86000sec' \
  '2: eth0    inet6 fe80::17ff:fe00:1/64 scope link \       valid_lft forever preferred_lft forever' \
  '3: tailscale0    inet 198.51.100.7/32 scope global tailscale0\       valid_lft forever preferred_lft forever'
EOF
cat > "$T/ssh/rbin/ss" <<'EOF'
#!/bin/sh
[ "$1" = -Hltn ] || exit 1
printf '%s\n' 'LISTEN 0      4096   127.0.0.53%lo:53        0.0.0.0:*' 'LISTEN 0      4096         0.0.0.0:22        0.0.0.0:*' \
  'LISTEN 0      511    198.51.100.7:7400      0.0.0.0:*' 'LISTEN 0      4096            [::]:22           [::]:*'
EOF
chmod +x "$T/ssh/rbin/nproc" "$T/ssh/rbin/ip" "$T/ssh/rbin/ss"
chmod +x "$T/ssh/rbin/sudo" "$T/ssh/rbin/podman" "$T/ssh/rbin/systemctl" "$T/ssh/rbin/loginctl" "$T/ssh/rbin/newuidmap" "$T/ssh/rbin/newgidmap" "$T/ssh/rbin/slirp4netns"
fakelinux() { # fakelinux <dir>: the Linux build's config.sh and run.sh, as the image holds them
  mkdir -p "$1/bin"
  cat > "$1/config.sh" <<'EOF'
#!/usr/bin/env bash
[ "${ACTIONS_RUNNER_INPUT_TOKEN:-}" = "$FAKE_TOKEN" ] && echo "$1" >> "$FAKE_SSH/envtoken"
echo "config.sh $*" >> "$FAKE_SSH/config"
if [ "$1" = remove ]; then rm -f .runner .credentials; fi
if [ "$1" = --unattended ]; then
  [ -e "$FAKE_SSH/configure.fail" ] && { echo "fake config: registration failed" >&2; exit 23; }
  while [ $# -gt 0 ]; do [ "$1" = --url ] && url=$2; [ "$1" = --name ] && nm=$2; shift; done
  printf '{"agentName": "%s", "gitHubUrl": "%s"}\n' "$nm" "$url" > .runner; echo cred > .credentials; printf 'LANG=%s\n' "${LANG:-}" > .env
fi
EOF
  cat > "$1/bin/Runner.Listener" <<'EOF'
#!/usr/bin/env bash
echo "Runner.Listener $* $(test -f .runner && test -f .credentials && echo registered || echo bare)" >> "$FAKE_SSH/runsh"
exit "$(cat "$FAKE_SSH/listener" 2>/dev/null || echo 0)"
EOF
  chmod +x "$1/config.sh" "$1/bin/Runner.Listener"
}
CAPS="$REGATTA_CONFIG/wharf/ci-runner-caps.json"
UNITS="$RH/.config/containers/systemd"
echo true > "$T/gh/private"; echo false > "$T/gh/forkpr"; rm -f "$T/gh/fetch.fail" "$T/gh/default" "$T/gh/runners.fail"
R="$T/lx"; newrepo "$R"; mkdir -p "$R/.helloworld"; "$CP" "$R" --to self-hosted > /dev/null 2>&1
# the fake host holds no runner of the earlier cases (a-b-c, flat ones): one runner a Linux host
rm -rf "$RH/actions-runners/"* "$T/gh/vars" "$UNITS"; rm -f "$CAPS"
: > "$T/ssh/argv"; : > "$T/ssh/curl"; : > "$T/gh/calls"; : > "$T/ssh/stdin"; rm -f "$T/ssh/envtoken"
LX="--host node-ci --name lnx1 --labels self-hosted,Linux"
"$CP" "$R" --runner install --dry-run $LX > "$T/out" 2>&1; check "$?" "2" "a Linux runner the capabilities file does not list: refused"
grep -q "a Linux runner registers by its capabilities, never a label of the host's own: list lnx1 in" "$T/out"; check "$?" "0" "…naming the file to list it in"
"$CP" "$R" --runner install --dry-run --host node-ci --labels self-hosted,Linux > "$T/out" 2>&1; check "$?" "2" "--host without --name: refused, as before"
echo '{"lnx1": ["linux-share"]}' > "$CAPS"
"$CP" "$R" --runner install --dry-run $LX --instance 2 > "$T/out" 2>&1; check "$?" "2" "a second instance on a Linux host: refused"
grep -q "one runner a Linux host" "$T/out"; check "$?" "0" "…one job at a time beside its sessions"
"$CP" "$R" --runner install --dry-run --host node-ci --name 'lnx/1' --labels self-hosted,Linux > "$T/out" 2>&1; check "$?" "2" "a Linux runner's name that cannot name a unit: refused"
grep -q "\-\-name: letters, digits" "$T/out"; check "$?" "0" "…saying why"
for bad in Lnx1 lnx1- lnx..1; do
  "$CP" "$R" --runner install --dry-run --host node-ci --name "$bad" --labels self-hosted,Linux > "$T/out" 2>&1; check "$?" "2" "a Linux runner's name no image reference takes ($bad): refused before any ssh"
  grep -q "names a Linux runner's image, unit and volume: lower-case letters and digits" "$T/out"; check "$?" "0" "…saying what it takes"
done
"$CP" "$R" --runner install --dry-run --host node-ci --name lnx1 --labels self-hosted,macOS > "$T/out" 2>&1; check "$?" "2" "Mac labels with no label of its own and --name: refused, as before"
"$CP" "$R" --runner install --dry-run $LX > "$T/out" 2>&1; check "$?" "0" "--runner install --dry-run, a Linux host: the plan"
check "$(test -s "$T/ssh/argv" && echo ssh || echo none)" "none" "…no ssh"
grep -q 'uname -s. (Linux, or refused)' "$T/out"; check "$?" "0" "…the probe's system must say Linux"
grep -q "whether it lacks what a rootless container needs (podman, a user namespace with subordinate uids, a network helper, linger, the user instance: refused, naming each)" "$T/out"; check "$?" "0" "…and what a rootless container needs"
grep -qF "x86_64 https://github.com/actions/runner/releases/download/v2.338.0/actions-runner-linux-x64-2.338.0.tar.gz (227660598 bytes, SHA-256 af4b794c1bc4)" "$T/out"; check "$?" "0" "…the pinned linux-x64 build, its size and digest"
grep -qF "aarch64 https://github.com/actions/runner/releases/download/v2.338.0/actions-runner-linux-arm64-2.338.0.tar.gz (140012091 bytes, SHA-256 628b4a725848)" "$T/out"; check "$?" "0" "…and linux-arm64's for an aarch64 host"
grep -q "osx-" "$T/out"; check "$?" "1" "…no macOS build in a Linux plan"
grep -qF "build the image localhost/ci-runner-lnx1 from it over docker.io/library/ubuntu@sha256:6a06111c3b0a8600feadb270aec771dc239bf407b25625f93f44ab00e11f4d3c (no sudo in it)" "$T/out"; check "$?" "0" "…the image over the pinned base"
grep -q "config.sh --name lnx1 --labels linux-share in a container of it, the token on its stdin" "$T/out"; check "$?" "0" "…registered with its capabilities, never the host's name, the token on stdin"
grep -q "a rootless container a job (the listener's --once), no host mount, socket or credential, in the login's app.slice at CPUWeight=20 beside the sessions' 100, Nice=10" "$T/out"; check "$?" "0" "…the service: a rootless container a job, below the host's sessions"
grep -q -E 'sudo -n|svc\.sh' "$T/out"; check "$?" "1" "…and no sudo or svc.sh in it"
grep -q "no runs-on variable routed: a Linux runner takes acme/demo's Linux share" "$T/out"; check "$?" "0" "…check.yml's variable never routed to it"
check "$(grep -c 'actions/variables' "$T/gh/calls")" "0" "…nor read"
"$CP" "$R" --runner remove --dry-run $LX > "$T/out" 2>&1; check "$?" "0" "--runner remove --dry-run, a Linux host"
grep -q "stop and remove the unit ci-runner-lnx1.service, config.sh remove in a container of its image, then its volume and image" "$T/out"; check "$?" "0" "…the container's road, not svc.sh's"

DIST="$RH/actions-runners/.dist"; mkdir -p "$DIST"
fakelinux "$T/lxtar"; (cd "$T/lxtar" && tar czf "$DIST/fake-linux.tar.gz" config.sh bin)
LXRUN='{"id":40,"name":"lnx1","os":"Linux","status":"online","busy":false,"labels":[{"name":"self-hosted","type":"read-only"},{"name":"Linux","type":"read-only"},{"name":"X64","type":"read-only"},{"name":"linux-share","type":"custom"}]}'
echo "{\"total_count\":1,\"runners\":[$LXRUN]}" > "$T/gh/runners.json"
cat > "$T/freshlx.py" <<'PY'
import hashlib, importlib.machinery, importlib.util, os, sys
loader = importlib.machinery.SourceFileLoader("cp", sys.argv[1])
spec = importlib.util.spec_from_loader("cp", loader); m = importlib.util.module_from_spec(spec); loader.exec_module(m)
tgz = sys.argv[4]
m.RUNNER_LINUX_X64_URL = "https://example.invalid/fake-linux.tar.gz"
m.RUNNER_LINUX_X64_SIZE = os.path.getsize(tgz)
m.RUNNER_LINUX_X64_SHA256 = hashlib.sha256(open(tgz, "rb").read()).hexdigest()
sys.exit(m.main([sys.argv[2], "--runner", sys.argv[3]] + sys.argv[5:]))
PY
lx() { FAKE_SYSTEM=Linux FAKE_ARCH=x86_64 python3 "$T/freshlx.py" "$CP" "$R" "$1" "$DIST/fake-linux.tar.gz" $LX; }
export RUNNER_RETRY_PAUSE=0   # the entry's pause before a retried container, 30 s in the image: none in the fakes
: > "$T/gh/calls"; rm -rf "$T/ssh/sudo" "$T/ssh/podman" "$T/ssh/config" "$T/ssh/active" "$T/ssh/systemctl" "$T/ssh/runsh" "$T/ssh/img" "$T/ssh/vol"
lx install > "$T/out" 2>&1; check "$?" "0" "a fresh install on a Linux host"
check "$(grep -c 'registration-token' "$T/gh/calls")" "1" "…one registration token minted"
check "$(cat "$T/ssh/envtoken" 2>/dev/null)" "--unattended" "…handed to config.sh in ACTIONS_RUNNER_INPUT_TOKEN, inside the container"
check "$(grep -c "$TOKEN" "$T/out")" "0" "…in none of its output"
check "$(grep -c "$TOKEN" "$T/ssh/argv")" "0" "…nor in ssh's argv"
check "$(grep -c "$TOKEN" "$T/ssh/podman")" "0" "…nor in any podman argv"
check "$(grep -c "$TOKEN" "$UNITS/ci-runner-lnx1.container")" "0" "…nor in the unit"
check "$(grep -c -- "--unattended --replace --disableupdate --url https://github.com/acme/demo --name lnx1 --labels linux-share --work _work" "$T/ssh/config")" "1" "…config.sh: its name, its capabilities as labels, no self-update (the image holds the pin)"
b=$(grep -n '^podman build' "$T/ssh/podman" | head -1 | cut -d: -f1); c=$(grep -n ' configure ' "$T/ssh/podman" | head -1 | cut -d: -f1)
check "$([ -n "$b" ] && [ -n "$c" ] && [ "$b" -lt "$c" ] && echo before || echo "b=$b c=$c")" "before" "…the image built before anything is registered"
grep -q 'websockets-15.0.1-py3-none-any.whl' "$T/ssh/img/localhost_ci-runner-lnx1/Containerfile"; check "$?" "0" "…the image carries websockets, which linux-tools.sh's hosted road installs with sudo"
grep -qF "FROM docker.io/library/ubuntu@sha256:6a06111c3b0a8600feadb270aec771dc239bf407b25625f93f44ab00e11f4d3c" "$T/ssh/img/localhost_ci-runner-lnx1/Containerfile"; check "$?" "0" "…over the pinned base"
check "$(cmp -s "$T/ssh/img/localhost_ci-runner-lnx1/runner.tar.gz" "$DIST/fake-linux.tar.gz" && echo same || echo differs)" "same" "…from the tarball verified on the host"
grep -q '^USER runner$' "$T/ssh/img/localhost_ci-runner-lnx1/Containerfile"; check "$?" "0" "…its jobs as an unprivileged user"
grep -v '^#' "$T/ssh/img/localhost_ci-runner-lnx1/Containerfile" | grep -qw sudo; check "$?" "1" "…with no sudo in the image"
check "$(cat "$RH/actions-runners/acme/demo/.runner" 2>/dev/null)" '{"agentName": "lnx1", "gitHubUrl": "https://github.com/acme/demo"}' "…the registration's .runner copied out of the volume to the host"
check "$(ls -A "$T/ssh/vol/ci-runner-lnx1-state" | tr '\n' ' ')" ".credentials .env .runner " "…the registration itself in the state volume"
for want in 'Image=localhost/ci-runner-lnx1' 'Exec=run' 'Volume=ci-runner-lnx1-state:/state:ro' 'DropCapability=ALL' 'NoNewPrivileges=true' 'Restart=always' 'CPUWeight=20' 'Nice=10'; do
  grep -qxF "$want" "$UNITS/ci-runner-lnx1.container"; check "$?" "0" "…the quadlet unit: $want"
done
check "$(grep -c -E '^(Volume|Mount)=' "$UNITS/ci-runner-lnx1.container")" "1" "…no mount but the state volume"
grep -q -i -E 'sock|PublishPort|Network=host|Secret=|Environment=' "$UNITS/ci-runner-lnx1.container"; check "$?" "1" "…no socket, host network, secret or environment"
check "$(grep -c 'start ci-runner-lnx1.service' "$T/ssh/systemctl")" "1" "…started as a user unit"
check "$(cat "$T/ssh/runsh" 2>/dev/null)" "Runner.Listener run --once registered" "…its container takes one job, its registration loaded from the volume"
grep -q 'chown runner:runner /state' "$T/ssh/img/localhost_ci-runner-lnx1/Containerfile"; check "$?" "0" "…the image's /state the runner's, so a fresh volume is too (podman 4.9 copies its owner after :U)"
check "$(grep -c '^pruned' "$T/ssh/prune" 2>/dev/null)" "1" "…dangling images pruned after the build (one a container still uses goes at a later install)"
grep -q -- '--filter label=ci-provider.runner' "$T/ssh/prune"; check "$?" "0" "…the runner's own alone, by the label the image carries"
grep -qxF 'RestartPreventExitStatus=3' "$UNITS/ci-runner-lnx1.container"; check "$?" "0" "…the unit stops on the entry's exit 3, a runner that can take no job"
check "$(test -e "$T/ssh/sudo" && cat "$T/ssh/sudo" || echo none)" "none" "…and no sudo run"
grep -q "system " "$T/ssh/systemctl"; check "$?" "1" "…nor the system's systemctl"
grep -q 'systemctl status ci-runner-lnx1.service' "$T/out"; check "$?" "0" "…its status from systemd"
grep -q 'runner lnx1 online, labels self-hosted, Linux, X64, linux-share' "$T/out"; check "$?" "0" "…read back online from GitHub, its capabilities among its labels"
grep -q "no runs-on variable routed" "$T/out"; check "$?" "0" "…the Linux share's runs-on left to the pick"
check "$(grep -c 'actions/variables' "$T/gh/calls")" "0" "…no repository variable read or written"
: > "$T/gh/calls"; lx install > "$T/out" 2>&1; check "$?" "0" "a second install on the Linux host"
check "$(grep -c 'token' "$T/gh/calls")" "0" "…no token minted"
check "$(grep -c '^podman build' "$T/ssh/podman")" "2" "…the image rebuilt, so a reinstall takes a changed one"
check "$(grep -c ' configure ' "$T/ssh/podman")" "1" "…never registered twice"
check "$(grep -c 'start ci-runner-lnx1.service' "$T/ssh/systemctl")" "1" "…the active unit not started again (its next job takes the new image)"
check "$(grep -cxE 'stop ci-runner-lnx1-rebuild\.(timer|service)' "$T/ssh/systemctl")" "4" "…each of the two installs stopped a weekly rebuild under way before its image is built (its tarball would race the install's)"
: > "$T/gh/calls"; FAKE_SYSTEM=Linux "$CP" "$R" --runner remove --host node-ci --name other1 --labels self-hosted,Linux > "$T/out" 2>&1; check "$?" "2" "remove under a name the host's runner does not have: refused"
grep -q "node-ci holds another runner (.*ci-runner-lnx1.container), not other1: nothing removed" "$T/out"; check "$?" "0" "…naming the runner it holds"
check "$(test -e "$RH/actions-runners/acme/demo/.runner" && echo kept || echo gone)" "kept" "…the real runner's .runner kept"
check "$(grep -c 'remove-token' "$T/gh/calls")" "0" "…and no token minted"
mv "$UNITS/ci-runner-lnx1.container" "$T/unit.keep"
FAKE_SYSTEM=Linux "$CP" "$R" --runner remove --host node-ci --name other1 --labels self-hosted,Linux > "$T/out" 2>&1; check "$?" "0" "…with the real runner's unit file gone, nothing to refuse on: remove goes on"
check "$(test -e "$RH/actions-runners/acme/demo/.runner" && echo kept || echo gone)" "kept" "…and keeps the .runner another name holds (its agentName)"
grep -q "the Linux share: nothing deregistered from here" "$T/out"; check "$?" "0" "…claiming no deregistration"
mv "$T/unit.keep" "$UNITS/ci-runner-lnx1.container"
touch "$T/gh/runners.fail"; : > "$T/gh/calls"; lx install > /dev/null 2>&1
check "$(grep -c 'registration-token' "$T/gh/calls")" "0" "a configured runner, GitHub's list unread: no token, the volume's registration kept"
rm -f "$T/gh/runners.fail"
keep=$(cat "$T/gh/runners.json"); echo '{"total_count":31,"runners":[]}' > "$T/gh/runners.json"; : > "$T/gh/calls"; lx install > /dev/null 2>&1
check "$(grep -c 'registration-token' "$T/gh/calls")" "0" "a configured runner, GitHub's list one page of more: no token (only a whole list says none)"
echo '{"runners":[]}' > "$T/gh/runners.json"; : > "$T/gh/calls"; lx install > /dev/null 2>&1
check "$(grep -c 'registration-token' "$T/gh/calls")" "0" "…nor where the list carries no total_count"
printf '%s\n' "$keep" > "$T/gh/runners.json"
for code in 0 2 134; do
  echo "$code" > "$T/ssh/listener"; rm -f "$T/ssh/active"; : > "$T/ssh/systemctl"; lx install > "$T/out" 2>&1
  [ "$code" = 0 ] && { grep -q "the listener exited 0 within 30 s: a fresh container after a pause" "$T/out"; check "$?" "0" "a listener that exits 0 at once (a revoked credential's Shutting down): paused like a failure"; }
  check "$(grep '^exit' "$T/ssh/systemctl")" "exit 0" "the listener's exit $code (its job done, retryable, a crash): the container ends for a fresh one"
done
for code in 1:"GitHub refused its registration" 5:"a session conflict" 7:"a version GitHub retired: bump ci-provider's Linux pin"; do
  echo "${code%%:*}" > "$T/ssh/listener"; rm -f "$T/ssh/active"; : > "$T/ssh/systemctl"; lx install > "$T/out" 2>&1
  check "$(grep '^exit' "$T/ssh/systemctl")" "exit 3" "the listener's exit ${code%%:*}: exit 3, which stops the unit"
  grep -qF "the listener exited ${code%%:*}, ${code#*:}" "$T/out"; check "$?" "0" "…saying its remedy"
  grep -q "reset-failed ci-runner-lnx1.service" "$T/ssh/systemctl"; check "$?" "0" "…and the next install resets it before its start"
done
# a stop while the listener runs: the entry passes TERM on and exits 0 at once, never into its 30 s pause
E="$T/termrun"; rm -rf "$E"; mkdir -p "$E/root/bin" "$E/state"; echo x > "$E/state/.runner"
printf '#!/bin/sh\ntrap "exit 143" TERM\n: > "%s/live"\ni=0; while [ $i -lt 60 ]; do sleep 1; i=$((i+1)); done\n' "$E" > "$E/root/bin/Runner.Listener"; chmod +x "$E/root/bin/Runner.Listener"
sed -e "s#/runner/actions-runner#$E/root#g" -e "s#/state#$E/state#g" "$T/ssh/img/localhost_ci-runner-lnx1/entry.sh" > "$E/entry"
RUNNER_RETRY_PAUSE=30 sh "$E/entry" run > "$E/out" 2>&1 & epid=$!
n=0; while [ ! -e "$E/live" ] && [ $n -lt 50 ]; do sleep 0.1; n=$((n+1)); done
sleep 0.2; t0=$(date +%s); kill -TERM "$epid"; rc=0; wait "$epid" || rc=$?; t1=$(date +%s)
check "$rc" "0" "a TERM while the listener runs: the entry exits 0"
check "$([ $((t1 - t0)) -le 4 ] && echo prompt || echo "$((t1 - t0)) s")" "prompt" "…within seconds, never into the pause"
grep -q "after a pause" "$E/out"; check "$?" "1" "…and says no pause"
rm -rf "$E"
rm -f "$T/ssh/listener"; lx install > /dev/null 2>&1
FAKE_SYSTEM=Linux "$CP" "$R" --runner status $LX > "$T/out" 2>&1; check "$?" "0" "--runner status on the Linux host"
grep -q 'systemctl status ci-runner-lnx1.service' "$T/out"; check "$?" "0" "…the user unit's status"
mv "$T/ssh/active" "$T/ssh/active.keep"; FAKE_SYSTEM=Linux "$CP" "$R" --runner status $LX > "$T/out" 2>&1; check "$?" "0" "--runner status of a stopped unit: reported, not a failed read"
grep -q "the unit is not active (systemctl status exit 3)" "$T/out"; check "$?" "0" "…saying so"
mv "$T/ssh/active.keep" "$T/ssh/active"
: > "$T/gh/calls"; FAKE_SYSTEM=Darwin "$CP" "$R" --runner remove $LX > "$T/out" 2>&1; check "$?" "2" "remove with Linux labels, the host a Mac: refused"
grep -q "node-ci is Darwin, and the runner's labels name Linux: nothing removed" "$T/out"; check "$?" "0" "…saying both"
check "$(grep -c 'remove-token' "$T/gh/calls")" "0" "…before any token"
: > "$T/gh/calls"; FAKE_SYSTEM=Darwin "$CP" "$R" --runner install $LX > "$T/out" 2>&1; check "$?" "2" "Linux labels, the host a Mac: refused"
grep -q "node-ci is Darwin, and the runner's labels name Linux" "$T/out"; check "$?" "0" "…saying both"
check "$(grep -c 'token' "$T/gh/calls")" "0" "…before any token"
FAKE_SYSTEM=Linux "$CP" "$R" --runner install > "$T/out" 2>&1; check "$?" "2" "Mac labels (the keys'), the host Linux: refused"
grep -q "laptop-ci is Linux, and the runner's labels do not name Linux" "$T/out"; check "$?" "0" "…saying both"
rm -rf "$T/ssh/img/localhost_ci-runner-lnx1"; : > "$T/ssh/stdin"
: > "$T/gh/calls"; FAKE_SYSTEM=Linux "$CP" "$R" --runner remove --host node-ci --name lnx1 > "$T/out" 2>&1; check "$?" "2" "--runner remove with the runner's image gone: refused"
check "$(grep -c 'remove-token' "$T/gh/calls")" "0" "…found by the probe: no token minted"
grep -q "the image localhost/ci-runner-lnx1 is gone: --runner install rebuilds it" "$T/out"; check "$?" "0" "…naming the way back"
check "$(test -e "$RH/actions-runners/acme/demo/.runner" && echo kept || echo gone)" "kept" "…the registration kept"
lx install > "$T/out" 2>&1; check "$?" "0" "…install rebuilds the image, the registration kept"
check "$(grep -c ' configure ' "$T/ssh/podman")" "1" "…still registered once"
check "$(grep -c '^stop ci-runner-lnx1.service$' "$T/ssh/systemctl")" "0" "…the refused remove left the unit running"
check "$(test -e "$UNITS/ci-runner-lnx1.container" && echo kept || echo gone)" "kept" "…and its unit file"
mv "$T/ssh/vol/ci-runner-lnx1-state" "$T/ssh/vol.keep"; : > "$T/gh/calls"
FAKE_SYSTEM=Linux "$CP" "$R" --runner status $LX > "$T/out" 2>&1
grep -q "the state volume ci-runner-lnx1-state holds no registration" "$T/out"; check "$?" "0" "a lost state volume: status says so"
lx install > "$T/out" 2>&1; check "$?" "0" "…and an install registers again"
check "$(grep -c 'registration-token' "$T/gh/calls")" "1" "…a token minted for it, the host's .runner copy not taken for a registration"
check "$(grep -c ' configure ' "$T/ssh/podman")" "2" "…configured a second time"
echo '{"total_count":0,"runners":[]}' > "$T/gh/runners.json"; : > "$T/gh/calls"; : > "$T/ssh/systemctl"; rm -f "$T/ssh/active"
lx install > "$T/out" 2>&1
check "$(grep -c '^stop ci-runner-lnx1.service' "$T/ssh/systemctl")" "1" "…its unit stopped before the registration is replaced, even one is-active reads as down (waiting out RestartSec)"
grep -q "GitHub lists no runner lnx1: registering it again" "$T/out"; check "$?" "0" "a registration GitHub no longer lists (a runner it deleted): registered again"
check "$(grep -c 'registration-token' "$T/gh/calls")" "1" "…a token minted though the volume holds a registration"
check "$(grep -c ' configure ' "$T/ssh/podman")" "3" "…configured again (config.sh --replace)"
: > "$T/ssh/stdin"; : > "$T/ssh/systemctl"; rm -f "$T/ssh/envtoken"; rm -rf "$T/ssh/vol.keep"
FAKE_SYSTEM=Linux "$CP" "$R" --runner remove --host node-ci --name lnx1 > "$T/out" 2>&1; check "$?" "0" "--runner remove on the Linux host, the keys' Mac labels given"
check "$(head -1 "$T/ssh/systemctl")" "stop ci-runner-lnx1.service" "…the user unit stopped"
check "$(test -e "$UNITS/ci-runner-lnx1.container" && echo kept || echo gone)" "gone" "…and its unit file removed"
check "$(cat "$T/ssh/envtoken" 2>/dev/null)" "remove" "…config.sh remove in a container, the token in ACTIONS_RUNNER_INPUT_TOKEN"
check "$(test -e "$RH/actions-runners/acme/demo/.runner" && echo kept || echo gone)" "gone" "…and deregistered"
check "$(test -d "$T/ssh/vol/ci-runner-lnx1-state" && echo kept || echo gone)" "gone" "…its volume removed"
check "$(test -d "$T/ssh/img/localhost_ci-runner-lnx1" && echo kept || echo gone)" "gone" "…and its image"
check "$(grep -c "$TOKEN" "$T/ssh/stdin")" "1" "…the remove token on ssh's stdin"
grep -q "the Linux share: deregistered, no runner carries its lane's labels" "$T/out"; check "$?" "0" "…and says where the share goes, not check.yml's variable (the host's uname -s, not the labels)"
lx install > /dev/null 2>&1; touch "$T/gh/runners.fail"
FAKE_SYSTEM=Linux "$CP" "$R" --runner remove --host node-ci --name lnx1 > "$T/out" 2>&1; check "$?" "0" "remove with GitHub's runner list unread"
grep -q "GitHub's runner list unread (HTTP 403): whether lnx1 is gone is not known here" "$T/out"; check "$?" "0" "…saying so, never that no runner is left"
grep -q "the Linux share: deregistered from here; GitHub's list unread" "$T/out"; check "$?" "0" "…nor that no runner carries the lane's labels"
rm -f "$T/gh/runners.fail"
echo "{\"total_count\":1,\"runners\":[$LXRUN]}" > "$T/gh/runners.json"
lx install > "$T/out" 2>&1; check "$?" "0" "an install again, for the lost volume's case"
mv "$T/ssh/vol/ci-runner-lnx1-state" "$T/vol.keep"
FAKE_SYSTEM=Linux "$CP" "$R" --runner remove --host node-ci --name lnx1 > "$T/out" 2>&1; check "$?" "0" "remove with the state volume lost"
grep -q "the state volume holds no registration: nothing deregistered from here" "$T/out"; check "$?" "0" "…saying nothing was deregistered from the host"
grep -q "GitHub still lists lnx1 (online): gh api -X DELETE repos/acme/demo/actions/runners/40" "$T/out"; check "$?" "0" "…and the DELETE that clears GitHub's record"
grep -q "the Linux share: nothing deregistered from here, so it stays where the pick put it" "$T/out"; check "$?" "0" "…never that the share was deregistered"
echo '{"total_count":0,"runners":[]}' > "$T/gh/runners.json"
check "$(test -e "$RH/actions-runners/acme/demo/.runner" && echo kept || echo gone)" "gone" "…and its own .runner removed (its agentName)"
rm -rf "$T/vol.keep"
mkdir -p "$RH/actions-runners/other/repo"; echo '{"gitHubUrl": "https://github.com/other/repo"}' > "$RH/actions-runners/other/repo/.runner"
: > "$T/gh/calls"; FAKE_SYSTEM=Linux FAKE_ARCH=x86_64 "$CP" "$R" --runner install $LX > "$T/out" 2>&1; check "$?" "2" "another repo's runner on the Linux host: refused"
grep -q "node-ci holds a runner already (.*actions-runners/other/repo): one runner a Linux host" "$T/out"; check "$?" "0" "…naming it"
check "$(grep -c 'registration-token' "$T/gh/calls")" "0" "…nothing minted"
rm -rf "$RH/actions-runners/other"; mkdir -p "$UNITS"; : > "$UNITS/ci-runner-lnx9.container"; : > "$T/gh/calls"
FAKE_SYSTEM=Linux FAKE_ARCH=x86_64 "$CP" "$R" --runner install $LX > "$T/out" 2>&1; check "$?" "2" "another runner's unit on the Linux host: refused"
grep -q "node-ci holds a runner already (.*ci-runner-lnx9.container)" "$T/out"; check "$?" "0" "…naming it"
# a dedicated runner host may hold more (wharf/linux-runner-slots, 2026-11-05): the probe passes the count, and
# the probe's `room` lets install past the other-runner check; podman marked missing stops each case right after that check, so no state moves
SLOTS="$REGATTA_CONFIG/wharf/linux-runner-slots"; echo 'node-ci:2' > "$SLOTS"; cp "$CAPS" "$T/caps.keep"
echo '{"lnx1": ["linux-share"], "lnx1-2": ["linux-share"], "lnx1-3": ["linux-share"]}' > "$CAPS"
"$CP" "$R" --runner install --dry-run $LX --instance 2 > "$T/out" 2>&1; check "$?" "0" "a second instance where linux-runner-slots says 2 (lnx1-2, listed): planned"
"$CP" "$R" --runner install --dry-run $LX --instance 3 > "$T/out" 2>&1; check "$?" "2" "…a third: refused"
grep -q "node-ci:<N>" "$T/out"; check "$?" "0" "…naming the key that would allow it"
touch "$T/ssh/nopodman"; : > "$T/ssh/argv"
FAKE_SYSTEM=Linux FAKE_ARCH=x86_64 "$CP" "$R" --runner install $LX > "$T/out" 2>&1; check "$?" "2" "one other runner's unit under 2 slots: past the other-runner check"
grep -q "holds a runner already" "$T/out"; check "$?" "1" "…never refused for it"
grep -q "lacks what a rootless runner container needs" "$T/out"; check "$?" "0" "…stopped at the next check, the case's missing podman"
grep -q "^CI_RUNNER_SLOTS=2 bash -c " "$T/ssh/argv"; check "$?" "0" "…the count handed to the host's script"
: > "$UNITS/ci-runner-lnx8.container"
FAKE_SYSTEM=Linux FAKE_ARCH=x86_64 "$CP" "$R" --runner install $LX > "$T/out" 2>&1; check "$?" "2" "two others under 2 slots: refused"
grep -q "node-ci holds a runner already (.*): 2 runners a host its wharf/linux-runner-slots names" "$T/out"; check "$?" "0" "…naming the count"
rm -f "$UNITS/ci-runner-lnx8.container"; mkdir -p "$RH/actions-runners/other/repo"; echo '{"agentName": "lnx7"}' > "$RH/actions-runners/other/repo/.runner"
FAKE_SYSTEM=Linux FAKE_ARCH=x86_64 "$CP" "$R" --runner install $LX > "$T/out" 2>&1; check "$?" "2" "one unit and another runner's registration under 2 slots: two names, refused"
grep -q "node-ci holds a runner already (.*): 2 runners a host its wharf/linux-runner-slots names" "$T/out"; check "$?" "0" "…each a slot (a lone registration still reserves one)"
echo '{"agentName": "lnx9"}' > "$RH/actions-runners/other/repo/.runner"
FAKE_SYSTEM=Linux FAKE_ARCH=x86_64 "$CP" "$R" --runner install $LX > "$T/out" 2>&1; check "$?" "2" "a unit and the registration of the same name under 2 slots: one runner, past the other-runner check"
grep -q "holds a runner already" "$T/out"; check "$?" "1" "…never refused for it"
grep -q "lacks what a rootless runner container needs" "$T/out"; check "$?" "0" "…stopped at the case's missing podman"
mv "$UNITS/ci-runner-lnx9.container" "$T/lnx9.keep"
FAKE_SYSTEM=Linux FAKE_ARCH=x86_64 "$CP" "$R" --runner install $LX > "$T/out" 2>&1; check "$?" "2" "another repo's registration alone under 2 slots: past the other-runner check"
grep -q "holds a runner already" "$T/out"; check "$?" "1" "…never refused for it"
rm -rf "$RH/actions-runners/other"; mv "$T/lnx9.keep" "$UNITS/ci-runner-lnx9.container"; rm -f "$T/ssh/nopodman"
FAKE_SYSTEM=Linux "$CP" "$R" --runner remove --host node-ci --name other1 --labels self-hosted,Linux > "$T/out" 2>&1; check "$?" "2" "remove under 2 slots, a name the host does not hold: refused"
grep -q "node-ci holds another runner (.*ci-runner-lnx9.container), not other1: nothing removed" "$T/out"; check "$?" "0" "…as with one slot: the slots let only install past"
check "$(test -e "$UNITS/ci-runner-lnx9.container" && echo kept || echo gone)" "kept" "…the unit it holds kept"
# the repo's directory registered under another name: never room for a second name, which would orphan the first
D="$RH/actions-runners/acme/demo"; mkdir -p "$D"; rm -f "$T/demo.keep"; [ ! -e "$D/.runner" ] || mv "$D/.runner" "$T/demo.keep"
echo '{"agentName": "lnx1-3", "gitHubUrl": "https://github.com/acme/demo"}' > "$D/.runner"; : > "$UNITS/ci-runner-lnx1-3.container"
cksum "$D/.runner" "$UNITS/ci-runner-lnx1-3.container" > "$T/own.before"; : > "$T/gh/calls"; : > "$T/ssh/systemctl"
FAKE_SYSTEM=Linux FAKE_ARCH=x86_64 "$CP" "$R" --runner install $LX > "$T/out" 2>&1; check "$?" "2" "under 2 slots, the repo's directory registered as lnx1-3: an install as lnx1 refused"
grep -q "node-ci: this repo's runner there is lnx1-3, not lnx1: --runner remove --name lnx1-3 first" "$T/out"; check "$?" "0" "…naming the runner to remove first"
check "$(grep -c 'registration-token' "$T/gh/calls")" "0" "…nothing minted"
cat > "$T/own.py" <<'PY2'
import hashlib, importlib.machinery, importlib.util, os, sys
loader = importlib.machinery.SourceFileLoader("cp", sys.argv[1])
spec = importlib.util.spec_from_loader("cp", loader); m = importlib.util.module_from_spec(spec); loader.exec_module(m)
target = m.Target("node-ci", ("self-hosted", "Linux", "linux-share"), "lnx1", 1)
target.slots = 2
tgz = sys.argv[2]
asset = ("https://example.invalid/fake-linux.tar.gz", os.path.getsize(tgz), hashlib.sha256(open(tgz, "rb").read()).hexdigest())
sys.exit(m.ssh_runner("install", "acme/demo", target, token=os.environ["FAKE_TOKEN"], asset=asset,
                     files=m.linux_files("acme/demo", target.name, m.DEFAULT_LIMITS)))
PY2
FAKE_SYSTEM=Linux FAKE_ARCH=x86_64 python3 "$T/own.py" "$CP" "$DIST/fake-linux.tar.gz" > "$T/out" 2>&1; check "$?" "7" "…and the host's install itself refuses it, without relying on the probe"
grep -q "is runner lnx1-3's: --runner remove --name lnx1-3 first" "$T/out"; check "$?" "0" "…saying whose the directory is"
check "$(cksum "$D/.runner" "$UNITS/ci-runner-lnx1-3.container")" "$(cat "$T/own.before")" "…the directory's registration and the first runner's unit unchanged"
check "$(test -s "$T/ssh/systemctl" && echo changed || echo untouched)" "untouched" "…no service stopped or reloaded"
rm -f "$D/.runner" "$UNITS/ci-runner-lnx1-3.container"; [ ! -e "$T/demo.keep" ] || mv "$T/demo.keep" "$D/.runner"
# a name another repo's runner holds is never room, slots or not: its unit, image and volume are the name's
echo 'node-ci:3' > "$SLOTS"; echo '{"lnx1": ["linux-share"], "lnx9-2": ["linux-share"]}' > "$CAPS"
mv "$UNITS/ci-runner-lnx9.container" "$T/lnx9.keep"; : > "$UNITS/ci-runner-lnx9-2.container"; touch "$T/ssh/nopodman"
mkdir -p "$RH/actions-runners/other/repo"; echo '{"agentName": "lnx9-2"}' > "$RH/actions-runners/other/repo/.runner"; : > "$T/gh/calls"
FAKE_SYSTEM=Linux FAKE_ARCH=x86_64 "$CP" "$R" --runner install --host node-ci --name lnx9 --labels self-hosted,Linux --instance 2 > "$T/out" 2>&1; check "$?" "2" "under 3 slots, a name another repo's runner holds: refused"
grep -q "node-ci holds runner name lnx9-2 for another registration: nothing minted" "$T/out"; check "$?" "0" "…naming it"
check "$(grep -c 'registration-token' "$T/gh/calls")" "0" "…nothing minted"
# A directory of this repo's under a different name must not claim the sibling's volume as configured.
OWN="$RH/actions-runners/acme/demo-2"; VOL="$T/ssh/vol/ci-runner-lnx9-2-state"; IMG="$T/ssh/img/localhost_ci-runner-lnx9-2"
mkdir -p "$OWN" "$VOL" "$IMG"
echo '{"agentName": "lnx1-2", "gitHubUrl": "https://github.com/acme/demo"}' > "$OWN/.runner"
echo '{"agentName": "lnx9-2", "gitHubUrl": "https://github.com/other/repo"}' > "$VOL/.runner"
echo 'original unit' > "$UNITS/ci-runner-lnx9-2.container"; echo 'original image' > "$IMG/kept"
rm -f "$T/ssh/nopodman"; before=$(cksum "$OWN/.runner" "$VOL/.runner" "$UNITS/ci-runner-lnx9-2.container" "$IMG/kept")
: > "$T/gh/calls"; : > "$T/ssh/systemctl"
FAKE_SYSTEM=Linux FAKE_ARCH=x86_64 "$CP" "$R" --runner install --host node-ci --name lnx9 --labels self-hosted,Linux --instance 2 > "$T/out" 2>&1; check "$?" "2" "a configured repo installing under a sibling's name: refused"
grep -q "holds runner name lnx9-2 for another registration: nothing minted" "$T/out"; check "$?" "0" "…even though both the repo directory and the named volume hold registrations"
check "$(grep -c 'registration-token' "$T/gh/calls")" "0" "…before any token"
FAKE_SYSTEM=Linux "$CP" "$R" --runner remove --host node-ci --name lnx9 --labels self-hosted,Linux --instance 2 > "$T/out" 2>&1; check "$?" "2" "a configured repo removing a sibling's name: refused"
grep -q "holds runner name lnx9-2 for another registration: nothing removed" "$T/out"; check "$?" "0" "…the same ownership check protects remove"
check "$(grep -c 'remove-token' "$T/gh/calls")" "0" "…before a remove token"
# Recheck on the host, too: a name can be claimed after the caller's probe, before its install.
cat > "$T/nameheld.py" <<'PY'
import hashlib, importlib.machinery, importlib.util, os, sys
loader = importlib.machinery.SourceFileLoader("cp", sys.argv[1])
spec = importlib.util.spec_from_loader("cp", loader); m = importlib.util.module_from_spec(spec); loader.exec_module(m)
name, instance, slug = ("lnx1", 1, "other/repo") if len(sys.argv) > 4 else ("lnx9", 2, "acme/demo")
target = m.Target("node-ci", ("self-hosted", "Linux", "linux-share"), name, instance)
target.slots = 3
tgz = sys.argv[2]
asset = ("https://example.invalid/fake-linux.tar.gz", os.path.getsize(tgz), hashlib.sha256(open(tgz, "rb").read()).hexdigest())
sys.exit(m.ssh_runner(sys.argv[3], slug, target, token=os.environ["FAKE_TOKEN"], asset=asset,
                     files=m.linux_files(slug, target.name, m.DEFAULT_LIMITS)))
PY
for verb in install remove; do
  FAKE_SYSTEM=Linux FAKE_ARCH=x86_64 python3 "$T/nameheld.py" "$CP" "$DIST/fake-linux.tar.gz" "$verb" > "$T/out" 2>&1; check "$?" "7" "the host $verb itself refuses the held name, without relying on the probe"
done
check "$(cksum "$OWN/.runner" "$VOL/.runner" "$UNITS/ci-runner-lnx9-2.container" "$IMG/kept")" "$before" "…both registrations, the unit and the image unchanged"
check "$(test -s "$T/ssh/systemctl" && echo changed || echo untouched)" "untouched" "…no service stopped or reloaded"
# A lone unit or volume has no `other` line: the name's refusal must stand alone.
rm -rf "$RH/actions-runners/other" "$VOL" "$IMG"; rm -f "$UNITS/ci-runner-lnx9-2.container"
for held in unit volume; do
  if [ "$held" = unit ]; then : > "$UNITS/ci-runner-lnx9-2.container"; else mkdir -p "$VOL"; fi
  : > "$T/gh/calls"
  FAKE_SYSTEM=Linux FAKE_ARCH=x86_64 "$CP" "$R" --runner install --host node-ci --name lnx9 --labels self-hosted,Linux --instance 2 > "$T/out" 2>&1; check "$?" "2" "a held name's $held alone, with no other runner directory: refused"
  grep -q "holds runner name lnx9-2 for another registration: nothing minted" "$T/out"; check "$?" "0" "…the name guard stands without an other-runner line"
  check "$(grep -c 'registration-token' "$T/gh/calls")" "0" "…nothing minted"
  rm -rf "$VOL"; rm -f "$UNITS/ci-runner-lnx9-2.container"
done
rm -rf "$OWN"
rm -rf "$RH/actions-runners/other" "$UNITS/ci-runner-lnx9-2.container" "$T/ssh/nopodman"; mv "$T/lnx9.keep" "$UNITS/ci-runner-lnx9.container"
echo '{"lnx1": ["linux-share"], "lnx1-2": ["linux-share"], "lnx1-3": ["linux-share"]}' > "$CAPS"
rm -f "$SLOTS"
"$CP" "$R" --runner remove --dry-run $LX --instance 2 > "$T/out" 2>&1; check "$?" "0" "remove of instance 2 once the slots line is gone: planned, never refused"
"$CP" "$R" --runner install --dry-run $LX --instance 2 > "$T/out" 2>&1; check "$?" "2" "…while its install is refused"
: > "$T/ssh/argv"
FAKE_SYSTEM=Linux FAKE_ARCH=x86_64 "$CP" "$R" --runner install $LX > /dev/null 2>&1
grep -q "^CI_RUNNER_SLOTS=" "$T/ssh/argv"; check "$?" "1" "no slots line: the probe's command as before"; mv "$T/caps.keep" "$CAPS"
rm -f "$UNITS/ci-runner-lnx9.container"
# A failed first registration owns its partial state. Test retry and remove both before configure succeeds
# and after it writes the volume's registration but copying .runner to the host fails.
PENDING="$RH/actions-runners/acme/demo/.runner-pending"; VOL="$T/ssh/vol/ci-runner-lnx1-state"
OTHER="$T/lx-other"; newrepo "$OTHER"; git -C "$OTHER" remote set-url origin https://github.com/other/repo.git
cp "$CAPS" "$T/caps.partial.keep"; echo '{"lnx1": ["linux-share"], "lnx2": ["linux-share"]}' > "$CAPS"
echo "{\"total_count\":1,\"runners\":[$LXRUN]}" > "$T/gh/runners.json"
for failure in configure copy; do
  for recovery in install remove; do
    touch "$T/ssh/$failure.fail"; : > "$T/gh/calls"; : > "$T/ssh/podman"
    lx install > "$T/out" 2>&1; check "$?" "2" "$failure fails on a first install before $recovery: reported"
    grep -q "fake .*failed" "$T/out"; check "$?" "0" "…reached the injected failure"
    check "$(cat "$PENDING" 2>/dev/null)" "$(printf 'acme/demo\nlnx1')" "…the repo and runner name reserved before registration"
    check "$(test -d "$VOL" && echo exists || echo absent)" "exists" "…the partial volume exists"
    check "$(test -f "$RH/actions-runners/acme/demo/.runner" && echo exists || echo absent)" "absent" "…no .runner copied to the host"
    check "$(test -f "$UNITS/ci-runner-lnx1.container" && echo exists || echo absent)" "absent" "…no unit installed"
    # The reservation protects the name even with slots available, from a different repo or name alike.
    echo 'node-ci:2' > "$SLOTS"; : > "$T/gh/calls"; : > "$T/ssh/systemctl"
    before=$(cksum "$PENDING")
    for verb in install remove; do
      FAKE_SYSTEM=Linux "$CP" "$OTHER" --runner "$verb" $LX > "$T/out" 2>&1; check "$?" "2" "…another repo cannot $verb the pending name"
      grep -q 'holds runner name lnx1 for another registration' "$T/out"; check "$?" "0" "…refused by ownership"
      FAKE_SYSTEM=Linux "$CP" "$R" --runner "$verb" --host node-ci --name lnx2 --labels self-hosted,Linux > "$T/out" 2>&1; check "$?" "2" "…the owning repo cannot $verb under a different name"
      grep -q 'holds runner name lnx2 for another registration' "$T/out"; check "$?" "0" "…the reservation checks the runner name as well as the repo"
      FAKE_SYSTEM=Linux FAKE_ARCH=x86_64 python3 "$T/nameheld.py" "$CP" "$DIST/fake-linux.tar.gz" "$verb" pending > "$T/out" 2>&1; check "$?" "7" "…the host $verb itself refuses another repo's pending name"
    done
    check "$(grep -c -E 'registration-token|remove-token' "$T/gh/calls")" "0" "…neither refusal mints a token"
    check "$(cksum "$PENDING")" "$before" "…the reservation unchanged"
    check "$(test -s "$T/ssh/systemctl" && echo changed || echo untouched)" "untouched" "…no service changed by the refusals"
    # A partial install also occupies the default host's one slot.
    rm -f "$SLOTS"; FAKE_SYSTEM=Linux "$CP" "$OTHER" --runner install --host node-ci --name lnx2 --labels self-hosted,Linux > "$T/out" 2>&1; check "$?" "2" "…a pending registration occupies the default host's one slot"
    grep -q 'holds a runner already' "$T/out"; check "$?" "0" "…another name is refused by capacity"
    echo 'node-ci:2' > "$SLOTS"; : > "$UNITS/ci-runner-lnx9.container"
    mkdir -p "$RH/actions-runners/sibling/repo"
    echo '{"agentName": "lnx9", "gitHubUrl": "https://github.com/sibling/repo"}' > "$RH/actions-runners/sibling/repo/.runner"
    FAKE_SYSTEM=Linux "$CP" "$OTHER" --runner install --host node-ci --name lnx2 --labels self-hosted,Linux > "$T/out" 2>&1; check "$?" "2" "…a pending registration and sibling fill two slots"
    grep -q 'holds a runner already' "$T/out"; check "$?" "0" "…the pending directory counted toward the slots limit"
    # A sibling cannot prevent the owner recovering its reserved slot, including remove (which reads no slots key).
    rm -f "$T/ssh/$failure.fail"; : > "$T/gh/calls"; : > "$T/ssh/podman"
    lx "$recovery" > "$T/out" 2>&1; check "$?" "0" "…the owner can $recovery after $failure fails, beside a sibling"
    check "$(test -f "$PENDING" && echo kept || echo gone)" "gone" "…the pending reservation cleared"
    mint=0; [ "$failure:$recovery" = configure:install ] && mint=1
    check "$(grep -c 'registration-token' "$T/gh/calls")" "$mint" "…registration token only for an unfinished configure"
    mint=0; [ "$failure:$recovery" = copy:remove ] && mint=1
    check "$(grep -c 'remove-token' "$T/gh/calls")" "$mint" "…remove token only when the volume holds a registration"
    if [ "$recovery" = install ]; then
      check "$(test -f "$RH/actions-runners/acme/demo/.runner" && test -f "$UNITS/ci-runner-lnx1.container" && echo configured || echo absent)" "configured" "…the retry finishes installing"
      mint=0; [ "$failure" = configure ] && mint=1
      check "$(grep -c ' configure ' "$T/ssh/podman")" "$mint" "…a registration already in the volume is kept"
      lx remove > "$T/out" 2>&1; check "$?" "0" "…the recovered runner removes normally"
    fi
    check "$(test -d "$VOL" && echo kept || echo gone)" "gone" "…the partial volume cleaned up"
    check "$(test -d "$T/ssh/img/localhost_ci-runner-lnx1" && echo kept || echo gone)" "gone" "…its image cleaned up"
    check "$(test -f "$UNITS/ci-runner-lnx9.container" && echo kept || echo gone)" "kept" "…the sibling's unit kept"
    rm -f "$UNITS/ci-runner-lnx9.container" "$SLOTS"
    rm -rf "$RH/actions-runners/sibling"
  done
done
mv "$T/caps.partial.keep" "$CAPS"
for lack in nopodman nouserns nosubuids nosubgids nolinger nousersd; do
  touch "$T/ssh/$lack"; : > "$T/gh/calls"
  FAKE_SYSTEM=Linux FAKE_ARCH=x86_64 "$CP" "$R" --runner install $LX > "$T/out" 2>&1; check "$?" "2" "a Linux host that lacks one thing ($lack): refused"
  check "$(grep -c 'registration-token' "$T/gh/calls")" "0" "…found by the probe: nothing minted"
  rm -f "$T/ssh/$lack"
done
touch "$T/ssh/nosubuids" "$T/ssh/nolinger"; FAKE_SYSTEM=Linux FAKE_ARCH=x86_64 "$CP" "$R" --runner install $LX > "$T/out" 2>&1
# the refusal names runner-user only where it is in the checkout: the public twin, which lacks it until its publish
# review, reads every remedy in full (round 2 of the node-runner-user review)
RU=0; [ -f "$B/runner-user" ] && RU=1
if [ "$RU" = 1 ]; then
  grep -q "node-ci lacks what a rootless runner container needs (subuids, linger), the owner's to give with sudo first: wharf's runner-user gives the login all of it" "$T/out"; check "$?" "0" "…all of them at once, named as the owner's step"
  q=$(python3 -c 'import shlex, sys; print(shlex.quote(sys.argv[1]))' "$(cd "$B" && pwd -P)/runner-user")   # as the refusal quotes it
  grep -qF "scp $q <key>.pub <node>: && ssh -t <node> sudo bash runner-user --node-user <the node's login> --login <node-ci's login> --key-file <key>.pub (<node> the node's own login's alias, which has sudo; <key>.pub the key node-ci logs in with; the runner login is its own, never the node's); nothing minted" "$T/out"; check "$?" "0" "…by runner-user's one line, its path this checkout's"
else
  grep -q "node-ci lacks what a rootless runner container needs, the owner's to give with sudo first: a subordinate uid and gid range for the login" "$T/out"; check "$?" "0" "…each lack named as the owner's step (no runner-user here)"
  grep -q "linger for the login (loginctl enable-linger <login>)" "$T/out"; check "$?" "0" "…all of them at once"
fi
check "$(grep -c 'which it does not give' "$T/out")" "0" "…nothing left over for what the script gives"
touch "$T/ssh/nopodman"; FAKE_SYSTEM=Linux FAKE_ARCH=x86_64 "$CP" "$R" --runner install $LX > "$T/out" 2>&1
if [ "$RU" = 1 ]; then w="needs (podman, "; else w="podman (apt-get install podman)"; fi
grep -qF "$w" "$T/out"; check "$?" "0" "…podman's absence among them"
check "$(test -e "$RH/actions-runners/acme/demo/.runner" && echo configured || echo absent)" "absent" "…nothing configured"
# newuidmap and slirp4netns hidden: what the probe says then depends on this machine's own, so the expectation is read
# from the same fact (a stand-in's absence cannot hide a real one on PATH)
rm -f "$T/ssh/nopodman" "$T/ssh/nosubuids" "$T/ssh/nolinger"
touch "$T/ssh/nouserns"; mv "$T/ssh/rbin/newuidmap" "$T/ssh/rbin/newuidmap.off"; mv "$T/ssh/rbin/slirp4netns" "$T/ssh/rbin/slirp4netns.off"
want=userns; command -v newuidmap > /dev/null 2>&1 || want=uidmap
net=0; command -v slirp4netns > /dev/null 2>&1 || net=1
FAKE_SYSTEM=Linux FAKE_ARCH=x86_64 "$CP" "$R" --runner install $LX > "$T/out" 2>&1
case $want$RU in uidmap1) w="needs (uidmap" ;; uidmap0) w="the uidmap package (newuidmap and newgidmap" ;; *) w="an unprivileged user namespace for podman (Ubuntu's apparmor package ships the profile" ;; esac
grep -qF "$w" "$T/out"; check "$?" "0" "a namespace podman cannot make: named by newuidmap's presence ($want)"
if [ "$RU" = 1 ]; then w="needs (.*network)"; else w="slirp4netns, podman 4.9's rootless network"; fi
check "$(grep -c "$w" "$T/out")" "$net" "…and the network helper's absence named where it is absent"
mv "$T/ssh/rbin/newuidmap.off" "$T/ssh/rbin/newuidmap"; mv "$T/ssh/rbin/slirp4netns.off" "$T/ssh/rbin/slirp4netns"; rm -f "$T/ssh/nouserns"
check "$(test -e "$T/ssh/sudo" && echo ran || echo none)" "none" "no sudo on any Linux road"
cat > "$T/lacks.py" <<'PY'
import importlib.machinery, importlib.util, sys
l = importlib.machinery.SourceFileLoader("cp", sys.argv[1]); s = importlib.util.spec_from_loader("cp", l)
m = importlib.util.module_from_spec(s); l.exec_module(m)
try:
    m.refuse_lacks(m.Probe(False, "x86_64", "Linux", None, ["uidmap", "network", "subuids"]), "node-ci")
except m.Refusal as e:
    print(e)
for lacks in (["userns"], ["userns", "linger"], ["user-systemd"]):
    try:
        m.refuse_lacks(m.Probe(False, "x86_64", "Linux", None, lacks), "node-ci")
    except m.Refusal as e:
        print(e)
isfile = m.os.path.isfile
m.os.path.isfile = lambda p: False if p.endswith("/runner-user") else isfile(p)   # the twin: no runner-user beside it
try:
    m.refuse_lacks(m.Probe(False, "x86_64", "Linux", None, ["uidmap", "subuids"]), "node-ci")
except m.Refusal as e:
    print("twin: %s" % e)
m.os.path.isfile = isfile
m.refuse_lacks(m.Probe(False, "arm64", "Darwin", None, ["podman"]), "mac")
print("a Mac: nothing")
PY
python3 "$T/lacks.py" "$CP" > "$T/out" 2>&1; check "$?" "0" "each lacks word's remedy, as the owner reads it"
if [ "$RU" = 1 ]; then
  grep -qF "needs (uidmap, network, subuids), the owner's to give with sudo first: wharf's runner-user" "$T/out"; check "$?" "0" "…uidmap's, the network helper's and the ranges', runner-user's to give"
  grep -qF "sudo bash runner-user --node-user" "$T/out"; check "$?" "0" "…with its one line, the copy in the node user's home"
  grep -qF "runner-user gives the login what it can, one line from this Mac" "$T/out"; check "$?" "0" "…with a lack it does not give beside one it does: what it can, the rest named"
else
  grep -qF "the uidmap package (newuidmap and newgidmap" "$T/out"; check "$?" "0" "…uidmap's (no runner-user here: in full)"
  grep -qF "slirp4netns, podman 4.9's rootless network (apt-get install slirp4netns)" "$T/out"; check "$?" "0" "…the network helper's"
  grep -qF "a subordinate uid and gid range for the login (its lines in /etc/subuid and /etc/subgid)" "$T/out"; check "$?" "0" "…the ranges'"
fi
grep -qF "node-ci lacks what a rootless runner container needs, the owner's to give with sudo first: an unprivileged user namespace for podman" "$T/out"; check "$?" "0" "…a user namespace alone, which it does not give: the remedy in full, no script"
grep -qF "twin: node-ci lacks what a rootless runner container needs, the owner's to give with sudo first: the uidmap package" "$T/out"; check "$?" "0" "…and where runner-user is not in the checkout (the twin), every remedy in full"
grep -qF "node-ci lacks what a rootless runner container needs, the owner's to give with sudo first: the login's systemd user instance" "$T/out"; check "$?" "0" "…the user instance alone, with linger there: in full, as runner-user would not mend it"
grep -qx "a Mac: nothing" "$T/out"; check "$?" "0" "…and a Mac's probe never refused for them"
echo "a Linux runner's berth parts: ubuntu 26.04, the live cap, the weekly rebuild, --runner check (free CI S6)"
rm -rf "$RH/actions-runners/acme" "$UNITS" "$RH/.config/systemd" "$T/ssh/img" "$T/ssh/vol"
rm -f "$T/ssh/active" "$T/ssh/runopts" "$T/ssh/checkargs" "$T/ssh/checkpy" "$T/ssh/checkout" "$T/ssh/checkrc" "$T/ssh/nopodman" \
  "$T/ssh/nosubuids" "$T/ssh/nosubgids" "$T/ssh/nolinger" "$T/ssh/nouserns" "$T/ssh/nousersd" "$T/ssh/listener" \
  "$REGATTA_CONFIG/wharf/ci-runner-limits"
echo '{"lnx1": ["linux-share"]}' > "$CAPS"
echo "{\"total_count\":1,\"runners\":[$LXRUN]}" > "$T/gh/runners.json"
U2="$RH/.config/systemd/user"; RD="$RH/actions-runners/acme/demo"; CF="$T/ssh/img/localhost_ci-runner-lnx1/Containerfile"
: > "$T/ssh/systemctl"
"$CP" "$R" --runner install --dry-run $LX > "$T/out" 2>&1; check "$?" "0" "the plan, with the berth's parts"
grep -qF "capped at --cpus 3 --memory 12g (wharf/ci-runner-limits, at most the host's cores)" "$T/out"; check "$?" "0" "…the container capped at the live limit's default, 3 cores and 12 GB"
grep -qF "its weekly rebuild, the user timer ci-runner-lnx1-rebuild.timer" "$T/out"; check "$?" "0" "…and rebuilt weekly"
lx install > "$T/out" 2>&1; check "$?" "0" "a fresh install with the berth's parts"
grep -qxF 'PodmanArgs=--cpus=3 --memory=12g --memory-swap=12g' "$UNITS/ci-runner-lnx1.container"; check "$?" "0" "…the unit caps its container: 3 cores, 12 GB, no swap past it"
grep -qF 'FROM docker.io/library/ubuntu@sha256:6a06111c3b0a8600feadb270aec771dc239bf407b25625f93f44ab00e11f4d3c' "$CF"; check "$?" "0" "…the image over ubuntu:26.04's digest, hosted ubuntu-latest's release"
grep -q 'apt-get upgrade -y' "$CF"; check "$?" "0" "…its packages upgraded at every build"
grep -q 'tzdata procps lsof' "$CF"; check "$?" "0" "…procps (ps, pgrep) and lsof (pickup's window probe) among them, which hosted ubuntu ships"
grep -q 'useradd -m -u 1001 -d /runner' "$CF"; check "$?" "0" "…the runner at uid 1001, so an earlier install's volume stays its own"
grep -q 'userdel -r ubuntu' "$CF"; check "$?" "0" "…the base's own login gone, so a job sees no /home"
grep -qxF 'OnCalendar=weekly' "$U2/ci-runner-lnx1-rebuild.timer"; check "$?" "0" "…a weekly user timer"
grep -qxF 'Persistent=true' "$U2/ci-runner-lnx1-rebuild.timer"; check "$?" "0" "…that catches up a week the host was off"
grep -qF "ExecStart=/bin/sh $RD/rebuild.sh ci-runner-lnx1 $DIST/fake-linux.tar.gz $(wc -c < "$DIST/fake-linux.tar.gz" | tr -d ' ') " "$U2/ci-runner-lnx1-rebuild.service"; check "$?" "0" "…its service: rebuild.sh with the pin"
grep -qxF 'CPUWeight=20' "$U2/ci-runner-lnx1-rebuild.service"; check "$?" "0" "…at the runner's weight"
grep -qF 'enable --now ci-runner-lnx1-rebuild.timer' "$T/ssh/systemctl"; check "$?" "0" "…enabled"
check "$(test -x "$RD/rebuild.sh" && echo yes || echo no)" "yes" "…rebuild.sh beside the image's context"
read -r rbsh rbscript rbargs < <(sed -n 's/^ExecStart=//p' "$U2/ci-runner-lnx1-rebuild.service")
rb() { env HOME="$RH" PATH="$T/ssh/rbin:$PATH" sh "$rbscript" $rbargs; }
: > "$T/ssh/podman"; rm -f "$T/ssh/prune"; rb > "$T/out" 2>&1; check "$?" "0" "the weekly rebuild, run as its timer runs it"
grep -q '^podman build -q --no-cache -t localhost/ci-runner-lnx1 image$' "$T/ssh/podman"; check "$?" "0" "…the same context, no cache"
grep -q -- '--filter label=ci-provider.runner' "$T/ssh/prune" 2>/dev/null; check "$?" "0" "…the runner's old images pruned"
check "$(test -e "$RD/image/runner.tar.gz" && echo kept || echo gone)" "gone" "…the tarball's copy gone from the context after"
cp "$DIST/fake-linux.tar.gz" "$T/tgz.keep"; printf x >> "$DIST/fake-linux.tar.gz"
: > "$T/ssh/podman"; rb > "$T/out" 2>&1; check "$?" "1" "a kept tarball that is not the pinned one: no rebuild"
grep -q "is not the pinned build: --runner install fetches it again" "$T/out"; check "$?" "0" "…saying what to do"
check "$(grep -c '^podman build' "$T/ssh/podman")" "0" "…and nothing built"
cp "$T/tgz.keep" "$DIST/fake-linux.tar.gz"

echo 'cpus=2,memory=8g' > "$REGATTA_CONFIG/wharf/ci-runner-limits"
check "$("$CP" --runner limits 2>&1)" "cpus=2,memory=8g" "--runner limits: the live limit's value, as install reads it"
check "$(cd "$(dirname "$CP")/.." && bin/ci-provider --runner limits 2>&1)" "cpus=2,memory=8g" "…the limits file's trial read, from the module's folder"
lx install > "$T/out" 2>&1; check "$?" "0" "a reinstall with a new cap"
grep -qxF 'PodmanArgs=--cpus=2 --memory=8g --memory-swap=8g' "$UNITS/ci-runner-lnx1.container"; check "$?" "0" "…the unit rewritten with it"
for bad in 'cpus=3 memory=12g' 'cpus=0,memory=12g' 'cpus=3,memory=100m' 'cpus=3,memory=12G' 'memory=12g,cpus=3'; do
  printf '%s\n' "$bad" > "$REGATTA_CONFIG/wharf/ci-runner-limits"
  "$CP" --runner limits > "$T/out" 2>&1; check "$?" "2" "a cap it cannot read ($bad): refused, never the default"
done
grep -q "want one line \`cpus=<cores>,memory=<n>g\`" "$T/out"; check "$?" "0" "…saying the shape"
: > "$T/ssh/argv"; : > "$T/gh/calls"
"$CP" "$R" --runner install $LX > "$T/out" 2>&1; check "$?" "2" "install with that cap: refused"
check "$(wc -c < "$T/ssh/argv" | tr -d ' '):$(wc -c < "$T/gh/calls" | tr -d ' ')" "0:0" "…before any ssh or GitHub call"
rm -f "$REGATTA_CONFIG/wharf/ci-runner-limits"
mkdir -p "$REGATTA_CONFIG/live/wharf"
printf '%s\n' 'cpus=2,memory=8g' > "$REGATTA_CONFIG/live/wharf/ci-runner-limits"
check "$("$CP" --runner limits 2>&1)" "cpus=2,memory=8g" "--runner limits: the live layer's value (what regatta limit set writes)"
printf '%s\n' 'cpus=3,memory=12G' > "$REGATTA_CONFIG/live/wharf/ci-runner-limits"
"$CP" --runner limits > "$T/out" 2>&1; check "$?" "2" "a live-layer cap it cannot read: refused"
grep -qF "$REGATTA_CONFIG/live/wharf/ci-runner-limits is" "$T/out"; check "$?" "0" "…naming the live layer's file, where the value came from"
rm -rf "$REGATTA_CONFIG/live/wharf"
check "$("$CP" --runner limits 2>&1)" "cpus=3,memory=12g" "no live value: the default"
"$CP" --runner limits --host node-ci --name lnx1 > "$T/out" 2>&1; check "$?" "2" "--runner limits with a runner named: refused (it reads the key alone)"
FAKE_NPROC=2 lx install > "$T/out" 2>&1; check "$?" "0" "a 2-core host"
grep -qF "the cap's 3 cores are more than the host's 2: 2" "$T/out"; check "$?" "0" "…the cap fitted to it, said"
grep -qxF 'PodmanArgs=--cpus=2 --memory=12g --memory-swap=12g' "$UNITS/ci-runner-lnx1.container"; check "$?" "0" "…and written"
lx install > /dev/null 2>&1

printf 'ok   cpu.max reads 3 cores\nall cases passed\n' > "$T/ssh/checkout"; echo 0 > "$T/ssh/checkrc"; : > "$T/ssh/runopts"
FAKE_SYSTEM=Linux "$CP" "$R" --runner check $LX > "$T/out" 2>&1; check "$?" "0" "--runner check: the cases, in a container of the runner's image"
grep -q 'all cases passed' "$T/out"; check "$?" "0" "…their lines printed"
grep -q 'cpu.max reads %s cores' "$T/ssh/checkpy"; check "$?" "0" "…the cases' python handed to the container"
check "$(tr '\n' ' ' < "$T/ssh/checkargs")" "3 12g 169.254.169.254:80 192.0.2.12:22 198.51.100.7:22 198.51.100.7:7400 -- github.com:443 " \
  "…the unit's cap, then every listener on each of the host's addresses (wildcard ones on each, loopback and link-local skipped) and the metadata service, then github.com"
check "$(tr '\n' ' ' < "$T/ssh/runopts")" "--cap-drop=ALL --security-opt=no-new-privileges --cpus=3 --memory=12g --memory-swap=12g " "…with the unit's own options"
grep -q 'ci-runner-lnx1-state:/state:ro' "$T/ssh/podman"; check "$?" "0" "…and its state volume, read-only"
# the options are the unit's, never the check's own: a unit that lost one is checked without it, and a key the check
# cannot replay refuses it
cp "$UNITS/ci-runner-lnx1.container" "$T/unit.keep"
sed -e '/^NoNewPrivileges=/d' -e 's/^DropCapability=ALL$/AddCapability=NET_RAW/' "$T/unit.keep" > "$UNITS/ci-runner-lnx1.container"; : > "$T/ssh/runopts"
FAKE_SYSTEM=Linux "$CP" "$R" --runner check $LX > "$T/out" 2>&1; check "$?" "0" "a unit without NoNewPrivileges, adding a capability"
check "$(tr '\n' ' ' < "$T/ssh/runopts")" "--cap-add=NET_RAW --cpus=3 --memory=12g --memory-swap=12g " "…checked with its own options, not the check's"
awk '{ print } /^NoNewPrivileges=/ { print "Mount=type=bind,source=/home,destination=/devel" }' "$T/unit.keep" > "$UNITS/ci-runner-lnx1.container"; : > "$T/ssh/checkargs"
FAKE_SYSTEM=Linux "$CP" "$R" --runner check $LX > "$T/out" 2>&1; check "$?" "2" "a unit with a key the check cannot replay: refused"
grep -q "sets Mount, which --runner check cannot replay" "$T/out"; check "$?" "0" "…naming it"
check "$(wc -c < "$T/ssh/checkargs" | tr -d ' ')" "0" "…and no container run"
cp "$T/unit.keep" "$UNITS/ci-runner-lnx1.container"
echo 8 > "$T/ssh/checkrc"; printf 'FAIL none of the host'"'"'s 4 listeners and addresses, nor the metadata service, reached: 198.51.100.7:7400\n' > "$T/ssh/checkout"
FAKE_SYSTEM=Linux "$CP" "$R" --runner check $LX > "$T/out" 2>&1; check "$?" "2" "a failed case: exit 2"
grep -q "a case failed above: a job on node-ci sees or reaches what it must not" "$T/out"; check "$?" "0" "…saying so, after the case's line"
echo 1 > "$T/ssh/checkrc"; printf 'Traceback (most recent call last):\n' > "$T/ssh/checkout"
FAKE_SYSTEM=Linux "$CP" "$R" --runner check $LX > "$T/out" 2>&1; check "$?" "2" "the cases crashed (exit 1): refused"
check "$(grep -c 'a case failed above' "$T/out"):$(grep -c 'could not tell' "$T/out")" "0:1" "…as could not tell, never as a failed case"
"$CP" "$R" --runner check --dry-run $LX > "$T/out" 2>&1; check "$?" "0" "--runner check --dry-run"
grep -q "nothing written, nothing minted" "$T/out"; check "$?" "0" "…says what it would read"
FAKE_SYSTEM=Linux "$CP" "$R" --runner check > "$T/out" 2>&1; check "$?" "2" "--runner check with a Mac's labels: refused"
mv "$T/ssh/rbin/ss" "$T/ssh/rbin/ss.off"; printf '#!/bin/sh\nexit 0\n' > "$T/ssh/rbin/ss"; chmod +x "$T/ssh/rbin/ss"; : > "$T/ssh/checkargs"
FAKE_SYSTEM=Linux "$CP" "$R" --runner check $LX > "$T/out" 2>&1; check "$?" "2" "--runner check on a host whose ss lists no listener: refused, never a vacuous pass"
grep -q "read no address or no listener" "$T/out"; check "$?" "0" "…saying so"
check "$(wc -c < "$T/ssh/checkargs" | tr -d ' ')" "0" "…and no container run"
mv "$T/ssh/rbin/ss.off" "$T/ssh/rbin/ss"
rm -f "$T/ssh/checkout" "$T/ssh/checkrc"
: > "$T/ssh/systemctl"
lx remove > "$T/out" 2>&1; check "$?" "0" "remove with the berth's parts"
grep -qF 'disable --now ci-runner-lnx1-rebuild.timer' "$T/ssh/systemctl"; check "$?" "0" "…the rebuild timer disabled"
grep -qxF 'stop ci-runner-lnx1-rebuild.service' "$T/ssh/systemctl"; check "$?" "0" "…and a rebuild under way stopped"
check "$(ls "$U2" 2>/dev/null | grep -c rebuild):$(test -e "$RD/rebuild.sh" && echo kept || echo gone)" "0:gone" "…its units and rebuild.sh gone"
FAKE_SYSTEM=Linux "$CP" "$R" --runner check $LX > "$T/out" 2>&1; check "$?" "2" "--runner check with no unit installed: refused"
grep -q "no unit .*ci-runner-lnx1.container: --runner install first" "$T/out"; check "$?" "0" "…saying so"

# the cases themselves, on this machine: what is readable everywhere (a stand-in cgroup, a listener here)
mkdir -p "$T/cg"; echo "300000 100000" > "$T/cg/cpu.max"; echo $((12 << 30)) > "$T/cg/memory.max"
python3 - "$CP" "$T/cg" > "$T/out" 2>&1 <<'PY'; check "$?" "0" "the cases' python, run here"
import importlib.machinery, importlib.util, os, socket, subprocess, sys
l = importlib.machinery.SourceFileLoader("cp", sys.argv[1]); s = importlib.util.spec_from_loader("cp", l)
m = importlib.util.module_from_spec(s); l.exec_module(m)
srv = socket.socket(); srv.bind(("127.0.0.1", 0)); srv.listen(); port = srv.getsockname()[1]
shut = socket.socket(); shut.bind(("127.0.0.1", 0)); gone = shut.getsockname()[1]; shut.close()
env = dict(os.environ, RUNNER_CHECK_CGROUP=sys.argv[2])
# a capability stand-in: a non-root process's status with the bounding set a unit without DropCapability leaves
st = os.path.join(sys.argv[2], "status")
z = "0000000000000000"
open(st, "w").write("NoNewPrivs:\t1\nCapInh:\t%s\nCapPrm:\t%s\nCapEff:\t%s\nCapBnd:\t00000000a80425fb\nCapAmb:\t%s\n" % (z, z, z, z))
r = subprocess.run([sys.executable, "-c", m.RUNNER_CHECK_PY, "3", "12g", "--"], env=dict(env, RUNNER_CHECK_STATUS=st),
                   capture_output=True, text=True, timeout=120)
print(r.stdout)
open(st, "w").write("NoNewPrivs:\t1\nCapInh:\t%s\nCapPrm:\t%s\nCapEff:\t%s\nCapBnd:\t%s\nCapAmb:\t%s\n" % (z, z, z, z, z))
r = subprocess.run([sys.executable, "-c", m.RUNNER_CHECK_PY, "3", "12g", "--"], env=dict(env, RUNNER_CHECK_STATUS=st),
                   capture_output=True, text=True, timeout=120)
print(r.stdout)
r = subprocess.run([sys.executable, "-c", m.RUNNER_CHECK_PY, "3", "12g", "127.0.0.1:%d" % port, "127.0.0.1:%d" % gone,
                    "--", "127.0.0.1:%d" % port], env=env, capture_output=True, text=True, timeout=120)
print("rc", r.returncode); print(r.stdout.replace(str(port), "PORT"))
open(os.path.join(sys.argv[2], "cpu.max"), "w").write("max 100000\n")
r = subprocess.run([sys.executable, "-c", m.RUNNER_CHECK_PY, "3", "12g", "--"], env=env, capture_output=True, text=True, timeout=120)
print(r.stdout)
PY
grep -qx 'rc 8' "$T/out"; check "$?" "0" "…a reached target fails it, with the cases' own code"
grep -qx 'ok   cpu.max reads 3 cores' "$T/out"; check "$?" "0" "…cpu.max read as cores"
grep -qx 'ok   memory.max reads 12g' "$T/out"; check "$?" "0" "…memory.max as the cap"
grep -qx "FAIL none of the host's 2 listeners and addresses, nor the metadata service, reached: 127.0.0.1:PORT" "$T/out"; check "$?" "0" "…the reached one named, the closed one not"
grep -qx 'ok   127.0.0.1:PORT reached (the positive case: the network works)' "$T/out"; check "$?" "0" "…the positive case"
grep -qx 'FAIL cpu.max reads 3 cores: max 100000' "$T/out"; check "$?" "0" "…an uncapped cgroup fails"
grep -qx 'FAIL no capability: CapBnd 00000000a80425fb' "$T/out"; check "$?" "0" "…a bounding set left whole fails it, though CapEff is 0"
grep -qx 'ok   no capability' "$T/out"; check "$?" "0" "…every set empty passes it"
rm -f "$T/ssh/nopodman" "$T/ssh/nosubuids" "$T/ssh/nolinger" "$CAPS"; rm -rf "$RH/actions-runners/acme" "$T/lxtar" "$UNITS" "$T/ssh/img" "$T/ssh/vol"
echo '{"total_count":0,"runners":[]}' > "$T/gh/runners.json"
FAKE_SYSTEM=Darwin FAKE_ARCH=arm64 python3 - "$CP" > "$T/out" 2>&1 <<'PY'; check "$?" "0" "the pinned builds by system and architecture"
import importlib.machinery, importlib.util, sys
l = importlib.machinery.SourceFileLoader("cp", sys.argv[1]); s = importlib.util.spec_from_loader("cp", l)
m = importlib.util.module_from_spec(s); l.exec_module(m)
print(" ".join(m.runner_asset(a, o)[0].rsplit("/", 1)[1].rsplit("-", 1)[0] for o, a in
               [("Darwin", "arm64"), ("Darwin", "x86_64"), ("Linux", "x86_64"), ("Linux", "aarch64"), ("Linux", "arm64")]))
for o, a in [("Linux", "ppc64le"), ("FreeBSD", "x86_64")]:
    try:
        m.runner_asset(a, o); print("no refusal")
    except m.Refusal as e:
        print("refused:", o, a)
PY
check "$(sed -n 1p "$T/out")" "actions-runner-osx-arm64 actions-runner-osx-x64 actions-runner-linux-x64 actions-runner-linux-arm64 actions-runner-linux-arm64" "…macOS's two, Linux's two (aarch64 and arm64 alike)"
check "$(sed -n 2,3p "$T/out" | tr '\n' '|')" "refused: Linux ppc64le|refused: FreeBSD x86_64|" "…another architecture or system: refused"

echo "check-linux.yml: the suites' runs-on from CI_LINUX_RUNS_ON, ubuntu-latest by default (linux-runner)"
WF="$M/../../.github/workflows/check-linux.yml"
if [ -f "$WF" ]; then
  python3 - "$WF" > "$T/out" 2>&1 <<'PY'
import json, re, sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
ro = d["jobs"]["suite"]["runs-on"]
print(ro)
m = re.fullmatch(r"\$\{\{ fromJSON\(vars\.(\w+) \|\| '(.*)'\) \}\}", ro)
name, default = m.group(1), m.group(2)
# GitHub's `||` takes the variable unless it is unset or empty, and fromJSON parses what it gets
for v in ({}, {name: ""}, {name: '["self-hosted","Linux","linux-share"]'}):
    print(json.dumps(json.loads(v.get(name) or default)))
PY
  check "$(sed -n 1p "$T/out")" "\${{ fromJSON(vars.CI_LINUX_RUNS_ON || '\"ubuntu-latest\"') }}" "the suite job's runs-on reads the repository variable"
  check "$(sed -n 2,4p "$T/out" | tr '\n' '|')" '"ubuntu-latest"|"ubuntu-latest"|["self-hosted", "Linux", "linux-share"]|' "…unset or empty: GitHub's hosted ubuntu-latest; set: the runner's labels"
  check "$(grep -c 'export HOME="$RUNNER_TEMP/home" TMPDIR="$RUNNER_TEMP/tmp"' "$WF")" "1" "…a self-hosted job's suite step keeps to the job's own HOME and TMPDIR"
  check "$(python3 -c 'import importlib.machinery as m, importlib.util as u, sys; l=m.SourceFileLoader("cp", sys.argv[1]); c=u.module_from_spec(u.spec_from_loader("cp", l)); l.exec_module(c); print(c.LINUX_RUNS_VAR, c.trigger_reads_runs_on(sys.argv[2]))' "$CP" "$M/../..")" \
    "CI_LINUX_RUNS_ON True" "…the variable the pick moves, which it reads this checkout's workflow for"
else
  echo "  skip the twin has no check-linux.yml"
fi

echo "linux-tools.sh on a persistent runner: no sudo, the job's own HOME, Node and the CLI kept (linux-runner)"
LTS="$M/../../.github/ci/linux-tools.sh"
if [ ! -f "$LTS" ]; then
  echo "  skip no .github/ci/linux-tools.sh here"
elif [ "$(uname -s)" != Linux ] || ! command -v xz > /dev/null || ! /usr/bin/python3 -c 'import yaml' 2> /dev/null; then
  echo "  skip linux-tools.sh runs on Linux, with xz and the system python3's PyYAML"
else
  LT="$T/lt"; LH="$LT/hm"; JH1="$LT/job1/home"; JH2="$LT/job2/home"   # the login's HOME, two jobs' own
  mkdir -p "$LT/stub" "$LT/srv" "$LH" "$LT/cache" "$LT/pkg/node-v22.99.0-linux-a/bin"
  case "$(uname -m)" in aarch64|arm64) NA=arm64 ;; *) NA=x64 ;; esac
  NODE="node-v22.99.0-linux-$NA"; mv "$LT/pkg/node-v22.99.0-linux-a" "$LT/pkg/$NODE"
  printf '#!/bin/sh\necho v22.99.0\n' > "$LT/pkg/$NODE/bin/node"
  # npm as the Node build ships it, first on the script's PATH once Node is in: an install into --prefix
  cat > "$LT/pkg/$NODE/bin/npm" <<'EOF'
#!/usr/bin/env bash
echo "npm $*" >> "$LT_LOG/npm"
prefix=""; while [ $# -gt 0 ]; do [ "$1" = --prefix ] && prefix=$2; shift; done
[ -n "$prefix" ] || prefix="$(dirname "$(dirname "$0")")"
mkdir -p "$prefix/bin"; printf '#!/bin/sh\necho "9.9.9 (Claude Code)"\n' > "$prefix/bin/claude"; chmod +x "$prefix/bin/claude"
EOF
  chmod +x "$LT/pkg/$NODE/bin/node" "$LT/pkg/$NODE/bin/npm"
  (cd "$LT/pkg" && tar -cJf "$LT/srv/$NODE.tar.xz" "$NODE")
  (cd "$LT/srv" && sha256sum "$NODE.tar.xz" > SHASUMS256.txt && echo "0000  node-v22.99.0-win-x64.zip" >> SHASUMS256.txt)
  cat > "$LT/stub/curl" <<'EOF'
#!/usr/bin/env bash
echo "curl $*" >> "$LT_LOG/curl"
out=""; url=""; here=""
while [ $# -gt 0 ]; do case "$1" in -o) out=$2; shift ;; -fsSLO) here=1 ;; http*) url=$1 ;; esac; shift; done
[ -n "$here" ] && out=${url##*/}
cp "$LT_LOG/srv/${url##*/}" "$out"
EOF
  printf '#!/usr/bin/env bash\necho "sudo $*" >> "$LT_LOG/sudo"; exit 1\n' > "$LT/stub/sudo"
  # the runner image's websockets, for the system python3 these cases run: a stand-in, unset by the case that lacks it
  mkdir -p "$LT/py/websockets/sync"; echo 'version = "15.0.1"' > "$LT/py/websockets/version.py"
  : > "$LT/py/websockets/__init__.py"; : > "$LT/py/websockets/sync/__init__.py"; echo 'connect = None' > "$LT/py/websockets/sync/client.py"
  export PYTHONPATH="$LT/py"
  for c in jq ruby sqlite3 lsof ps pgrep; do printf '#!/bin/sh\nexit 0\n' > "$LT/stub/$c"; done
  chmod +x "$LT/stub/"*
  ltrun() { # ltrun <job>: linux-tools.sh as job <job> of a self-hosted runner, its own RUNNER_TEMP, one tool cache
    mkdir -p "$LT/job$1"
    (env HOME="$LH" PATH="$LT/stub:$PATH" LT_LOG="$LT" RUNNER_ENVIRONMENT=self-hosted RUNNER_TEMP="$LT/job$1" \
       RUNNER_TOOL_CACHE="$LT/cache" GIT_CONFIG_GLOBAL="$LH/.gitconfig-login" bash "$LTS" > "$LT/out$1" 2>&1); echo "$?"; }
  LT_LOG="$LT"; export LT_LOG
  check "$(ltrun 1)" "0" "the first job on a persistent runner"
  check "$(grep -c "$NODE.tar.xz" "$LT/curl")" "1" "…Node fetched once, checked against nodejs.org's sums"
  check "$(grep -c 'npm install -g --prefix' "$LT/npm")" "1" "…the CLI installed into a prefix of its own"
  check "$(test -e "$LT/sudo" && echo sudo || echo none)" "none" "…no sudo"
  CLIV="$(grep -o '@anthropic-ai/claude-code@[0-9.]*' "$M/../../.github/workflows/check.yml" | head -1)"; CLIV="${CLIV##*@}"
  check "$(cut -d: -f1-2 "$JH1/.linux-path")" "$LT/cache/regatta-linux/claude-code-$CLIV/bin:$LT/cache/regatta-linux/$NODE/bin" "…the PATH, in the job's own HOME: the kept CLI, then the kept Node"
  check "$(git config --file "$JH1/.gitconfig" user.name)" "CI" "…git config --global in the job's own file"
  check "$(ls -A "$LH" | tr '\n' ' ')" "" "…the runner login's HOME untouched"
  grep -q '9.9.9 (Claude Code)' "$LT/out1"; check "$?" "0" "…and the CLI runs"
  check "$(ltrun 2)" "0" "the next job on the same runner"
  check "$(grep -c "$NODE.tar.xz" "$LT/curl")" "1" "…Node kept, not fetched again"
  check "$(grep -c 'npm install' "$LT/npm")" "1" "…nor the CLI installed again"
  check "$(grep -c 'kept from an earlier job' "$LT/out2")" "2" "…both said"
  check "$(test -s "$JH2/.linux-path" && echo own || echo none)" "own" "…the PATH in this job's own HOME"
  if ! env -u PYTHONPATH /usr/bin/python3 -c 'import websockets' 2> /dev/null; then
    mkdir -p "$LT/job4"
    (env -u PYTHONPATH HOME="$LH" PATH="$LT/stub:$PATH" LT_LOG="$LT" RUNNER_ENVIRONMENT=self-hosted RUNNER_TEMP="$LT/job4" \
       RUNNER_TOOL_CACHE="$LT/cache" bash "$LTS" > "$LT/out4" 2>&1); check "$?" "1" "an image without websockets: the job fails"
    grep -q "this runner lacks websockets 14+" "$LT/out4"; check "$?" "0" "…naming it, never a quiet skip of the kick socket's cases"
    check "$(test -e "$LT/sudo" && echo sudo || echo none)" "none" "…and never runs sudo"
  fi
  # lsof and ps/pgrep, which pickup's window probe and the process suites need: an image without either fails at setup
  # (runner-lsof). The script runs on a PATH of its own tools (links to what it calls before and around its `need` check)
  # and the stubs, so a host that ships lsof and ps in /usr/bin still has the case run
  mkdir -p "$LT/min"
  for t in bash dirname mkdir readlink ls head cat env sh tr; do ln -sf "$(command -v $t)" "$LT/min/$t"; done
  for c in lsof ps; do
    rm -f "$LT/stub/$c"
    mkdir -p "$LT/job$c"
    (env HOME="$LH" PATH="$LT/stub:$LT/min" LT_LOG="$LT" RUNNER_ENVIRONMENT=self-hosted RUNNER_TEMP="$LT/job$c" \
       RUNNER_TOOL_CACHE="$LT/cache" /bin/bash "$LTS" > "$LT/out$c" 2>&1); check "$?" "1" "an image without $c: the job fails"
    pkg=$c; [ "$c" != ps ] || pkg=procps
    grep -q "this runner lacks.* $pkg\b.*: add it to the image (ci-provider's RUNNER_CONTAINERFILE) and run --runner install again" "$LT/out$c"; check "$?" "0" "…naming $pkg, and the image it belongs in"
    check "$(test -e "$LT/sudo" && echo sudo || echo none)" "none" "…and never runs sudo or apt-get"
    printf '#!/bin/sh\nexit 0\n' > "$LT/stub/$c"; chmod +x "$LT/stub/$c"
  done
  rm -f "$LT/stub/ruby"
  if env PATH="$LT/stub:/usr/bin:/bin" bash -c 'command -v ruby' > /dev/null; then
    echo "  skip this host has ruby on /usr/bin: the missing-package case needs a host without it"
  else
    mkdir -p "$LT/job3"
    (env HOME="$LH" PATH="$LT/stub:/usr/bin:/bin" LT_LOG="$LT" RUNNER_ENVIRONMENT=self-hosted RUNNER_TEMP="$LT/job3" \
       RUNNER_TOOL_CACHE="$LT/cache" bash "$LTS" > "$LT/out3" 2>&1); check "$?" "1" "a package the runner lacks: the job fails"
    grep -q "this runner lacks ruby: add it to the image (ci-provider's RUNNER_CONTAINERFILE) and run --runner install again" "$LT/out3"; check "$?" "0" "…naming it, and the image it belongs in"
    check "$(test -e "$LT/sudo" && echo sudo || echo none)" "none" "…and never runs sudo or apt-get"
  fi
  unset PYTHONPATH LT_LOG   # the stand-in websockets and the log are this block's: no later case inherits them
fi

echo "the pick: the Linux share on a self-hosted Linux lane (linux-runner, 2026-11-04)"
cp "$LANES" "$T/lanes.lx"; cp "$BUDGETS" "$T/budgets.lx"; cp "$T/gh/rsc.json" "$T/gh/rsc.lx"
cat > "$LANES" <<'EOF'
{"lanes": [
 {"name": "mac", "runs_on": ["self-hosted", "macOS", "laptop"], "runs": ["macos"]},
 {"name": "oauth", "provider": "circleci", "runs": ["linux"], "account": "cci-o", "projects": {"acme/demo": "gh/acme/demo"}},
 {"name": "gha", "runs_on": "ubuntu-latest", "runs": ["linux", "public"], "account": "gh-u", "projects": {"acme/demo": "actions"}},
 {"name": "node", "runs_on": ["self-hosted", "Linux", "linux-share"], "runs": ["linux"], "projects": {"acme/demo": "actions"}}]}
EOF
cat > "$BUDGETS" <<'EOF'
{"reserve": 0.2, "accounts": {"cci-o": {"provider": "circleci", "org_slug": "gh/acme", "month_credits": 30000},
 "cci-a": {"provider": "circleci", "org_slug": "circleci/ORG", "month_credits": 30000},
 "gh-u": {"provider": "github", "user": "acme", "month_minutes": 3000}}}
EOF
STATE="$T/logs/ci-share-runners.json"
MACR='{"id":7,"name":"laptop","status":"online","busy":false,"labels":[{"name":"self-hosted"},{"name":"macOS"},{"name":"ARM64"},{"name":"laptop"}]}'
lxrunners() { # lxrunners online|offline|none: the runner list, the Mac's and the Linux host's runner in that state
  case "$1" in none) echo "{\"total_count\":1,\"runners\":[$MACR]}" ;;
    *) echo "{\"total_count\":2,\"runners\":[$MACR,${LXRUN/online/$1}]}" ;; esac > "$T/gh/runners.json"; }
runs() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["value"])' "$T/gh/vars/CI_LINUX_RUNS_ON.json" 2>/dev/null || echo unset; }
lxrepo() { # lxrepo <dir>: tworepo's, its check-linux.yml routing the suites by CI_LINUX_RUNS_ON, the share off,
  # check.yml already on the Mac lane (so the runs-on half writes nothing beside the share)
  tworepo "$1"; printf '    runs-on: ${{ fromJSON(vars.CI_LINUX_RUNS_ON) }}\n' >> "$1/.github/workflows/check-linux.yml"
  echo '{"name":"CI_RUNS_ON","value":"[\"self-hosted\",\"macOS\",\"laptop\"]"}' > "$T/gh/vars/CI_RUNS_ON.json"
  setvar CI_LINUX_ELSEWHERE false; rm -f "$PLOG" "$STATE"; }
NODEL='["self-hosted","Linux","linux-share"]'
R="$T/lxp"; lxrepo "$R"; lxrunners online
gusage 29443 33299 100; "$CP" "$R" --pick > "$T/out" 2>&1; check "$?" "0" "the Linux host's runner online, GitHub's minutes under budget too"
grep -q "share lane node: eligible, a runner labelled self-hosted, Linux, linux-share is online" "$T/out"; check "$?" "0" "…the self-hosted lane judged by its runner, no budget"
grep -qF "share CI_LINUX_RUNS_ON: unset → $NODEL (lane node:" "$T/out"; check "$?" "0" "…taken before the hosted lane: it bills nothing"
grep -q -- "--apply sets CI_LINUX_RUNS_ON to it" "$T/out"; check "$?" "0" "…said, and without --apply nothing written"
check "$(project) $(runs) $(share)" "unset unset false" "…nothing written"
check "$(test -e "$STATE" && echo kept || echo none)" "none" "…nor any sighting kept"
"$CP" "$R" --pick --apply > "$T/out" 2>&1; check "$?" "0" "--apply"
check "$(project) $(runs) $(share)" "actions $NODEL true" "…CI_LINUX_TARGET actions, CI_LINUX_RUNS_ON the lane's labels, CI_LINUX_ELSEWHERE true"
check "$(python3 -c 'import json,sys; print(" ".join(json.loads(l)["variable"] for l in open(sys.argv[1])))' "$PLOG")" \
  "CI_LINUX_TARGET CI_LINUX_RUNS_ON CI_LINUX_ELSEWHERE" "…in that order, the share last, each logged"
check "$(logrow CI_LINUX_RUNS_ON)" "None $NODEL node gh api -X DELETE repos/acme/demo/actions/variables/CI_LINUX_RUNS_ON" "…the runs-on with the DELETE that sends the suites back to ubuntu-latest"
"$CP" "$R" --pick --apply > "$T/out" 2>&1
grep -q "share CI_LINUX_ELSEWHERE: true, stays (lane node: a runner labelled" "$T/out"; check "$?" "0" "a second pick: it stays"
check "$(wc -l < "$PLOG" | tr -d ' ')" "3" "…nothing more written"
check "$(python3 -c 'import importlib.machinery as m, importlib.util as u, sys; l=m.SourceFileLoader("cp", sys.argv[1]); c=u.module_from_spec(u.spec_from_loader("cp", l)); l.exec_module(c); print(c.last_flip("acme/demo"))' "$CP")" \
  "0" "…a runs-on flip of the share is no flip of check.yml's runs-on (stale_lane)"
lxrunners offline; "$CP" "$R" --pick > "$T/out" 2>&1
grep -q "share CI_LINUX_ELSEWHERE: true, stays (lane node: its runner is offline 0 min, held a sweep before the share leaves it)" "$T/out"; check "$?" "0" "its runner offline: the share stays a sweep"
check "$(test -e "$STATE" && echo kept || echo none)" "none" "…a report keeps no sighting"
"$CP" "$R" --pick --apply > "$T/out" 2>&1
check "$(python3 -c 'import json,sys; print(sorted(json.load(open(sys.argv[1]))["acme/demo"]))' "$STATE")" "['node']" "…--apply keeps when it first saw it offline"
check "$(runs) $(share)" "$NODEL true" "…nothing moves"
mv "$STATE" "$T/state.keep"; CLAUDE_CODE_SESSION_ID=s-1 "$CP" "$R" --pick --apply > /dev/null 2>&1
check "$(test -e "$STATE" && echo kept || echo none)" "none" "…a session's --apply keeps no sighting: only the desk's job writes it"
mv "$T/state.keep" "$STATE"
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); d["acme/demo"]["node"]-=16*60; json.dump(d,open(sys.argv[1],"w"))' "$STATE"
"$CP" "$R" --pick --apply > "$T/out" 2>&1
grep -q "stays (lane node: its runner is offline 16 min, held a sweep before the share leaves it)" "$T/out"; check "$?" "0" "a second offline reading a sweep on: held, as a one-job runner may be between containers"
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); d["acme/demo"]["node"]-=5*60; json.dump(d,open(sys.argv[1],"w"))' "$STATE"
"$CP" "$R" --pick --apply > "$T/out" 2>&1; check "$?" "0" "offline past a sweep"
grep -q "share lane node: not chosen, its runner labelled self-hosted, Linux, linux-share has been offline 21 min: gone" "$T/out"; check "$?" "0" "…the lane counts as gone"
check "$(project) $(runs) $(share)" 'actions "ubuntu-latest" true' "…the share on the hosted lane, CI_LINUX_RUNS_ON back to its image at once"
lxrunners online; "$CP" "$R" --pick --apply > "$T/out" 2>&1
grep -q "stays on lane gha: lane node has more left, but the project moved 0 min ago" "$T/out"; check "$?" "0" "the runner back: the move back waits an hour"
check "$(runs)" '"ubuntu-latest"' "…held there"
check "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["acme/demo"])' "$STATE")" "{}" "…the sighting cleared"
python3 -c 'import json,sys,time; r=[json.loads(l) for l in open(sys.argv[1])]
for x in r: x["at"]-=7200
open(sys.argv[1],"w").write("".join(json.dumps(x)+"\n" for x in r))' "$PLOG"
"$CP" "$R" --pick --apply > "$T/out" 2>&1
check "$(runs) $(share)" "$NODEL true" "…and back on the Linux host's runner an hour later"
lxrunners none; gusage 29443 33299 2500; "$CP" "$R" --pick --apply > "$T/out" 2>&1; check "$?" "0" "no runner carries the lane's labels, GitHub's minutes past the reserve"
grep -q "share CI_LINUX_ELSEWHERE: true → false (lane node: no runner labelled self-hosted, Linux, linux-share)" "$T/out"; check "$?" "0" "…the lane gone at once: the share off, the Macs take the whole line"
check "$(share)" "false" "…written"
setvar CI_LINUX_ELSEWHERE true; lxrunners online; rm -f "$PLOG"
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); d["lanes"]=d["lanes"][:3]; json.dump(d,open(sys.argv[1],"w"))' "$LANES"
"$CP" "$R" --pick --apply > "$T/out" 2>&1
check "$(share)" "false" "the lane gone from the lanes file, the hosted one past its reserve: the share off"
cat > "$LANES" <<'EOF'
{"lanes": [
 {"name": "gha", "runs_on": "ubuntu-latest", "runs": ["linux", "public"], "account": "gh-u", "projects": {"acme/demo": "actions"}},
 {"name": "node", "runs_on": ["self-hosted", "Linux", "linux-share"], "runs": ["linux"], "projects": {"acme/demo": "actions"}}]}
EOF
R="$T/lxq"; tworepo "$R"; setvar CI_LINUX_ELSEWHERE false; rm -f "$PLOG" "$STATE"; lxrunners online; gusage 29443 33299 100
"$CP" "$R" --pick --apply > "$T/out" 2>&1
grep -q "share lane node: not chosen, check-linux.yml reads no CI_LINUX_RUNS_ON, so its suites would run on GitHub's hosted runners" "$T/out"; check "$?" "0" "a check-linux.yml that reads no CI_LINUX_RUNS_ON: the self-hosted lane is never chosen"
check "$(project) $(runs) $(share)" "actions unset true" "…the hosted lane takes the share, the runs-on variable untouched"
R="$T/lxr"; lxrepo "$R"; lxrunners online; echo false > "$T/gh/private"
"$CP" "$R" --pick --apply > "$T/out" 2>&1
grep -q "share lane node: not chosen, acme/demo is public: the Linux share on a self-hosted lane would let a fork" "$T/out"; check "$?" "0" "a public repo: never on the self-hosted lane"
check "$(runs)" "unset" "…its runs-on never moved there"
echo true > "$T/gh/private"; echo true > "$T/gh/forkpr"; rm -f "$T/gh/vars/CI_LINUX_TARGET.json"; setvar CI_LINUX_ELSEWHERE false
"$CP" "$R" --pick > "$T/out" 2>&1
grep -q "share lane node: not chosen, acme/demo runs fork pull requests' workflows" "$T/out"; check "$?" "0" "…nor a private one that runs fork PRs' workflows"
echo false > "$T/gh/forkpr"; touch "$T/gh/vars/CI_LINUX_RUNS_ON.unread"
"$CP" "$R" --pick --apply > "$T/out" 2>&1
grep -q "share CI_LINUX_TARGET: unread (CI_LINUX_RUNS_ON: " "$T/out"; check "$?" "0" "CI_LINUX_RUNS_ON unread: where the share stands is unknown, said"
check "$(share)" "false" "…nothing comes on"
rm -f "$T/gh/vars/CI_LINUX_RUNS_ON.unread"
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); d["lanes"][1]["runs_on"]=["self-hosted","macOS","Linux"]; json.dump(d,open(sys.argv[1],"w"))' "$LANES"
"$CP" "$R" --pick > "$T/out" 2>&1; check "$?" "2" "a self-hosted share lane naming macOS: refused"
grep -q "lane node is self-hosted: the Linux share runs on GitHub's hosted runners, or on a self-hosted Linux lane" "$T/out"; check "$?" "0" "…naming the lane"
cat > "$LANES" <<'EOF'
{"lanes": [
 {"name": "gha", "runs_on": "ubuntu-latest", "runs": ["linux", "public"], "account": "gh-u", "projects": {"acme/demo": "actions"}}]}
EOF
R="$T/lxs"; lxrepo "$R"; lxrunners online; setvar CI_LINUX_ELSEWHERE true; setvar CI_LINUX_TARGET actions
setvar CI_LINUX_RUNS_ON ubuntu-latest; gusage 29443 33299 100; "$CP" "$R" --pick --apply > "$T/out" 2>&1
check "$(runs)" '"ubuntu-latest"' "CI_LINUX_RUNS_ON a bare word, which fromJSON refuses: stands on no lane, rewritten as the hosted lane's JSON"
python3 - "$CP" > "$T/out" 2>&1 <<'PY2'
import importlib.machinery, importlib.util, sys
l = importlib.machinery.SourceFileLoader("cp", sys.argv[1]); s = importlib.util.spec_from_loader("cp", l)
m = importlib.util.module_from_spec(s); l.exec_module(m)
print(" ".join(str(m.runs_value(v) is m.BAD_RUNS) for v in (None, "", '"ubuntu-latest"', '["a"]', "ubuntu-latest", "[]", "3", '[1]')))
PY2
check "$(cat "$T/out")" "False False False False True True True True" "…unset, empty, a JSON image or label list read; a bare word, [], a number or a non-string list stand nowhere"
cat > "$LANES" <<'EOF'
{"lanes": [
 {"name": "node", "runs_on": ["self-hosted", "Linux", "linux-share"], "runs": ["linux"], "projects": {"acme/demo": "actions"}}]}
EOF
R="$T/lxt"; lxrepo "$R"; printf '{"provider": "self-hosted", "check": "sh check.sh", "needs": ["linux"]}\n' > "$R/.github/ci.json"
lxrunners online; "$CP" "$R" --pick > "$T/out" 2>&1
grep -q "lane node: a share lane, the Linux share's suites only" "$T/out"; check "$?" "0" "a repo that needs linux: the share lane is never check.yml's"
grep -q "  pick: node" "$T/out"; check "$?" "1" "…never picked for CI_RUNS_ON"
echo "{\"name\":\"CI_RUNS_ON\",\"value\":\"[\\\"self-hosted\\\",\\\"Linux\\\",\\\"linux-share\\\"]\"}" > "$T/gh/vars/CI_RUNS_ON.json"
"$CP" "$R" --pick > "$T/out" 2>&1; check "$?" "3" "check.yml set on the share lane by hand, no other lane: exit 3, for the desk to card"
grep -q "⚠ current lane node fails: a share lane, the Linux share's suites only" "$T/out"; check "$?" "0" "…saying why"
mkdir -p "$T/ro"; chmod 555 "$T/ro"
python3 - "$CP" "$T/ro" > "$T/out" 2>&1 <<'PY2'
import importlib.machinery, importlib.util, pathlib, sys
l = importlib.machinery.SourceFileLoader("cp", sys.argv[1]); s = importlib.util.spec_from_loader("cp", l)
m = importlib.util.module_from_spec(s); l.exec_module(m)
m.common.LOG_DIR = pathlib.Path(sys.argv[2]) / "logs"
c = m.ShareCtx(".", "acme/demo", {}, {}, None, 1000.0)
c.seen("node", 1000.0); c.save(True, False); print("returned")
PY2
check "$(tail -1 "$T/out")" "returned" "the sightings' log dir unwritable: said, never a raise out of the pick"
grep -q "⚠ share runners not recorded at" "$T/out"; check "$?" "0" "…in one line"
chmod 755 "$T/ro"
cp "$T/lanes.lx" "$LANES"; cp "$T/budgets.lx" "$BUDGETS"; mv "$T/gh/rsc.lx" "$T/gh/rsc.json"; rm -rf "$T/gh/vars"; rm -f "$PLOG" "$STATE"
echo '{"total_count":0,"runners":[]}' > "$T/gh/runners.json"

echo "the review of 2026-10-21: the suite's own git config (15)"
check "$(git config --global --list 2>/dev/null | wc -l | tr -d ' ')" "0" "git reads the suite's global config, not the caller's (15)"

echo
if [ "$fails" = 0 ]; then echo "test_ci_provider: all ok"; else echo "test_ci_provider: $fails FAILED"; exit 1; fi
