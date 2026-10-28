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
# none is GitHub's 404; with $T/gh/vars/fail a GET fails with no output at all (gh's own failure).
mkdir -p "$T/bin" "$T/gh"
cat > "$T/bin/gh" <<'EOF'
#!/usr/bin/env bash
D="$FAKE_GH"
args="$*"
echo "$args" >> "$D/calls"
case "$args" in
  *"/actions/runners/registration-token --jq .token"|*"/actions/runners/remove-token --jq .token") echo "$FAKE_TOKEN" ;;
  *"/actions/runners") [ -e "$D/runners.fail" ] && { echo "HTTP 403" >&2; exit 1; }
    cat "$D/runners.json" 2>/dev/null || echo '{"total_count":0,"runners":[]}' ;;
  *"/actions/workflows/check.yml/runs?status=queued&per_page=20") cat "$D/queued.json" 2>/dev/null || echo '{"workflow_runs":[]}' ;;
  *" --jq .private") p=$(cat "$D/private" 2>/dev/null || echo true); [ "$p" = fail ] && { echo "HTTP 404" >&2; exit 1; }; echo "$p" ;;
  *"/actions/permissions/fork-pr-workflows-private-repos") f=$(cat "$D/forkpr" 2>/dev/null || echo false)
    [ "$f" = fail ] && { echo "HTTP 403" >&2; exit 1; }
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
  *"/status") cat "$D/status.json" 2>/dev/null || echo '{"statuses":[]}' ;;
  *"/check-runs") cat "$D/checkruns.json" 2>/dev/null || echo '{"check_runs":[]}' ;;
  *"-X POST "*"/actions/variables --input -") mkdir -p "$D/vars"; cat > "$D/vars/post.json"
    n=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["name"])' "$D/vars/post.json")
    [ -e "$D/vars/$n.json" ] && { echo "HTTP 409" >&2; exit 1; }; mv "$D/vars/post.json" "$D/vars/$n.json" ;;
  *"-X PATCH "*"/actions/variables/"*" --input -") n=${args##*/actions/variables/}; n=${n%% *}
    [ -e "$D/vars/$n.json" ] || { echo "gh: Not Found (HTTP 404)" >&2; exit 1; }; cat > "$D/vars/$n.json" ;;
  *"/actions/variables/"*) n=${args##*/}; [ -e "$D/vars/fail" ] && exit 1
    [ -e "$D/vars/$n.json" ] && cat "$D/vars/$n.json" || { echo '{"message":"Not Found"}'; echo "gh: Not Found (HTTP 404)" >&2; exit 1; } ;;
  *) echo "fake gh: unhandled $args" >&2; exit 1 ;;
esac
EOF
chmod +x "$T/bin/gh"
# A fake ssh: records its argv and stdin in $T/ssh, then runs the remote command here, as the runner Mac
# would, with HOME=$T/ssh/home and $T/ssh/rbin (fake launchctl, curl, stat) first on PATH.
mkdir -p "$T/ssh/home" "$T/ssh/rbin"
# The runner script is macOS's and reads a size with BSD `stat -f %z`; GNU stat's -f is the file
# system's status, so on CI's ubuntu every size read 0 and the download cases took another path.
# This stat answers only that form, by wc, on both systems (wharf's check runs in CI since B5).
cat > "$T/ssh/rbin/stat" <<'EOF'
#!/usr/bin/env bash
[ "$1" = -f ] && [ "$2" = %z ] && [ -f "$3" ] && { wc -c < "$3" | tr -d ' '; exit 0; }
echo "fake stat: only -f %z FILE (got: $*)" >&2; exit 1
EOF
cat > "$T/bin/ssh" <<'EOF'
#!/usr/bin/env bash
D="$FAKE_SSH"
printf '%s\n' "$@" >> "$D/argv"
tee -a "$D/stdin" | HOME="$D/home" PATH="$D/rbin:$PATH" bash -c "${@: -1}"
EOF
cat > "$T/ssh/rbin/launchctl" <<'EOF'
#!/usr/bin/env bash
case "$1" in list) cat "$FAKE_SSH/loaded" 2>/dev/null; echo "-	0	com.apple.other" ;; *) echo "launchctl $*" >> "$FAKE_SSH/launchctl" ;; esac
EOF
# the runner Mac's architecture is $FAKE_ARCH's (arm64 unless a case sets it), on any machine the suite runs on
cat > "$T/ssh/rbin/uname" <<'EOF'
#!/usr/bin/env bash
[ "$1" = -m ] && { echo "${FAKE_ARCH:-arm64}"; exit 0; }
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
export PATH="$T/bin:$PATH" FAKE_GH="$T/gh" FAKE_SSH="$T/ssh" FAKE_TOKEN="$TOKEN"
echo '{"strict": false, "contexts": ["check"]}' > "$T/gh/rsc.json"

newrepo() { # newrepo <dir>: a repo on a claude/* branch with Actions' check.yml and protection
  local r="$1"
  mkdir -p "$r/.github/workflows"
  git -C "$r" init -q -b main
  git -C "$r" remote add origin https://github.com/acme/demo.git
  sed 's/{{COMMAND}}/sh check.sh/' "$TPL/.github/workflows/check.yml" > "$r/.github/workflows/check.yml"
  cp "$TPL/.github/main-protection.json" "$r/.github/main-protection.json"
  git -C "$r" add -A && git -C "$r" -c user.name=t -c user.email=t@t commit -qm init
  git -C "$r" checkout -q -b claude/test/2026-10-18-ci
}
ctx() { python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['required_status_checks']['contexts'])" "$1"; }
yamlok() { ruby -ryaml -e 'd = YAML.safe_load(File.read(ARGV[0])); puts d["jobs"].keys.sort.join(",") + "|" + d["workflows"].keys.sort.join(",")' "$1"; }

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
check "$(ruby -ryaml -e 'puts YAML.safe_load(File.read(ARGV[0]))["jobs"]["check"]["steps"][1]["run"]["command"]' "$R/.circleci/config.yml" | tr '\n' ';')" "sh check.sh;echo done;" "a two-line command survives"
"$CP" "$R" --to actions > /dev/null 2>&1
check "$(ruby -ryaml -e 'puts YAML.safe_load(File.read(ARGV[0]))["jobs"]["check"]["steps"][1]["run"]' "$R/.github/workflows/check.yml" | tr '\n' ';')" "sh check.sh;echo done;" "…both ways"
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
check "$(ruby -ryaml -e 'puts YAML.safe_load(File.read(ARGV[0]))["jobs"]["check"]["runs-on"].join(",")' "$R/.github/workflows/check.yml")" "self-hosted,macOS,laptop" "check.yml runs on the labels key's [self-hosted, macOS, laptop]"
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
grep -q 'no online runner labelled self-hosted, macOS, laptop' "$T/out"; check "$?" "0" "…and warns with no runner online"
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
open(p,"w").write(t.replace("runs-on: [self-hosted, macOS, laptop]", "runs-on: [self-hosted, macOS, othermac]", 1))
PY
"$CP" "$R" > "$T/out" 2>&1; grep -q 'self-hosted (ci.json)' "$T/out"; check "$?" "0" "a file on another Mac's labels is still self-hosted"
grep -q 'no online runner labelled self-hosted, macOS, othermac' "$T/out"; check "$?" "0" "…and status asks for the file's labels, not the key's"
"$CP" "$R" --to self-hosted > /dev/null 2>&1; check "$?" "2" "…but not this config's form: a re-run holds it as a hand edit (review 2026-10-21, 4)"
"$CP" "$R" --to self-hosted --force > /dev/null 2>&1; check "$?" "0" "…--force takes it"
check "$(grep -c 'runs-on: \[self-hosted, macOS, laptop\]' "$R/.github/workflows/check.yml")" "1" "…and writes this config's labels"
rm "$R/.github/ci.json"
"$CP" "$R" > "$T/out" 2>&1; grep -q 'self-hosted (inferred' "$T/out"; check "$?" "0" "this config's literal form, no ci.json: self-hosted inferred"
sed 's/runs-on: \[self-hosted, macOS, laptop\]/runs-on: [self-hosted, macOS, oldmac]/' "$R/.github/workflows/check.yml" > "$T/v2.yml" && mv "$T/v2.yml" "$R/.github/workflows/check.yml"
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
check "$(ruby -ryaml -e 'puts YAML.safe_load(File.read(ARGV[0]))["jobs"]["check"]["runs-on"]' "$R/.github/workflows/check.yml")" \
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
check "$(grep -c 'runs-on: \[self-hosted, macOS, laptop\]' "$R/.github/workflows/check.yml")" "1" "no twin, no flag: the literal labels, as before"

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
check "$(grep -c 'runs-on: \[self-hosted, macOS, laptop\]' "$R/.github/workflows/check.yml")" "1" "…keeps the literal form (6)"
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
stepnames() { ruby -ryaml -e 'puts YAML.safe_load(File.read(ARGV[0]))["jobs"]["check"]["steps"].map { |s| s["name"] || s["uses"] }.join("|")' "$1"; }
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
check "$(grep -c 'runs-on: \[self-hosted, macOS, laptop\]' "$R/.github/workflows/check.yml")" "1" "an allowlist without .github/: the literal stays"
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
check "$(grep -c 'runs-on: \[self-hosted, macOS, laptop\]' "$R/.github/workflows/check.yml")" "1" "another .github/ file published: the literal stays (8)"
R="$T/lr7"; newrepo "$R"; "$CP" "$R" --to self-hosted > /dev/null 2>&1
mkdir -p "$R/.opensource"; printf '.github/workflows/check.yml\n' > "$R/.opensource/allowlist.txt"
"$CP" "$R" --to self-hosted > /dev/null 2>&1
check "$(grep -cxF "    $VARLINE" "$R/.github/workflows/check.yml")" "1" "the old .opensource/ allowlist listing check.yml: the variable form (3)"

echo "the self-hosted kind's name from the config dir (the scrub, 2026-10-22)"
# The owner's repos' ci.json name the kind after the first runner Mac; wharf/ci-runner-kind carries it.
printf 'buildbox\n' > "$REGATTA_CONFIG/wharf/ci-runner-kind"
R="$T/k1"; newrepo "$R"
"$CP" "$R" --to buildbox > "$T/out" 2>&1; check "$?" "0" "the key's name: --to buildbox"
check "$(python3 -c "import json; print(json.load(open('$R/.github/ci.json'))['provider'])")" "buildbox" "…ci.json records it"
"$CP" "$R" > "$T/out" 2>&1; grep -q 'buildbox (ci.json)' "$T/out"; check "$?" "0" "…status names it"
"$CP" "$R" --to self-hosted > /dev/null 2>&1; check "$?" "2" "…and the default name is no kind beside it"
rm -f "$REGATTA_CONFIG/wharf/ci-runner-kind" "$R/.github/ci.json"
"$CP" "$R" > "$T/out" 2>&1; grep -q 'self-hosted (inferred' "$T/out"; check "$?" "0" "key and ci.json gone: the same check.yml reads as self-hosted, inferred from runs-on"

echo "the pick: lanes, budgets, the trust refusals (lighthouse-ops S1)"
# lighthouse's keys in the suite's config dir: four lanes (the runner Mac, a Linux guest, hosted ubuntu
# on one account, a CircleCI org), one budget, the log dir, and this host as the ops host. Usage is
# the desk's file, written here by hand as `lighthouse ops usage --write` would.
mkdir -p "$REGATTA_CONFIG/lighthouse" "$REGATTA_CONFIG/regatta" "$T/logs"
printf '%s\n' "$T/logs" > "$REGATTA_CONFIG/regatta/log-dir"
# --apply refuses inside a Claude Code session: the suite stands in for the desk's job
unset CLAUDECODE CLAUDE_CODE_SESSION_ID CLAUDE_UNATTENDED
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

echo "the pick's trust refusals: every flip to a self-hosted lane"
R="$T/pk3"; pickrepo "$R"; usage ok 100
echo true > "$T/gh/forkpr"; "$CP" "$R" --pick --apply > "$T/out" 2>&1
grep -q 'lane mac: refused, acme/demo runs fork pull requests' "$T/out"; check "$?" "0" "a private repo running fork PRs' workflows: the Mac lane refused"
check "$(varval)" "unset" "…a macOS repo then has no lane, and nothing is written"
echo fail > "$T/gh/forkpr"; "$CP" "$R" --pick > "$T/out" 2>&1
grep -q 'lane mac: refused, could not read whether acme/demo runs fork' "$T/out"; check "$?" "0" "fork PRs' setting unread: refused"
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
R="$T/pk6"; newrepo "$R"; "$CP" "$R" --to circleci > /dev/null 2>&1
"$CP" "$R" --pick > "$T/out" 2>&1; check "$?" "2" "a repo on circleci: refused, the pick moves an Actions check only"
"$CP" "$R" --apply > /dev/null 2>&1; check "$?" "2" "--apply without --pick: a usage error"

echo "the review of 2026-10-21: the suite's own git config (15)"
check "$(git config --global --list 2>/dev/null | wc -l | tr -d ' ')" "0" "git reads the suite's global config, not the caller's (15)"

echo
if [ "$fails" = 0 ]; then echo "test_ci_provider: all ok"; else echo "test_ci_provider: $fails FAILED"; exit 1; fi
