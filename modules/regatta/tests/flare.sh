#!/usr/bin/env bash
# `regatta flare`'s cases: the issue it builds, the scan that refuses a public leak, the filing through
# a stand-in `gh` (never the real one: nothing reaches GitHub), the retry that returns the first receipt,
# and the link it falls back to without `gh`. Scratch HOME, config dir and TMPDIR; check.sh runs it.
#   bash modules/regatta/tests/flare.sh
set -u
M="$(cd "$(dirname "$0")/.." && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
for v in $(env | sed -n 's/^\(REGATTA[A-Za-z0-9_]*\)=.*/\1/p; s/^\(CLAUDE[A-Za-z0-9_]*\)=.*/\1/p; s/^\(DISPATCH_[A-Za-z0-9_]*\)=.*/\1/p'); do unset "$v"; done
unset HELLOWORLD_WORDLIST OPENSOURCE_WORDLIST GH_TOKEN GITHUB_TOKEN
export HOME="$T/h" REGATTA_CONFIG="$T/config" TMPDIR="$T/tmp"; mkdir -p "$HOME" "$REGATTA_CONFIG" "$TMPDIR"
# a scratch private word list, as a Mac with one has it (no list: the patterns alone, said on stderr)
export HELLOWORLD_WORDLIST="$T/words.txt"; printf 'zzprivword\n' > "$HELLOWORLD_WORDLIST"
fails=0
check() { if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3: expected [$2] got [$1]"; fails=$((fails+1)); fi; }
FB() { "$M/bin/regatta" flare "$@"; }
J() { python3 -c "import json, sys; d = json.load(sys.stdin); print($1)"; }

# The stand-in: `auth status` exits $GH_AUTH (0), `issue list` prints $GH_LIST ([]), `issue create` prints
# $GH_CREATE, or refuses a --label while $GH_NOLABEL is set; every call is logged, and the body file a
# create names is kept for the cases to read.
mkdir -p "$T/bin"
cat > "$T/bin/gh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_LOG"
case "$1 $2" in
  "auth status") exit "${GH_AUTH:-0}" ;;
  "issue list") printf '%s\n' "${GH_LIST:-[]}" ;;
  "issue create")
    case " $* " in *" --label "*) [ -n "${GH_NOLABEL:-}" ] && { echo "could not add label: 'question' not found" >&2; exit 1; } ;; esac
    while [ $# -gt 0 ]; do [ "$1" = "--body-file" ] && cp "$2" "$GH_BODY"; shift; done
    printf '%s\n' "$GH_CREATE" ;;
esac
SH
chmod +x "$T/bin/gh"
export PATH="$T/bin:$PATH" GH_LOG="$T/gh.log" GH_BODY="$T/body.md" GH_CREATE="https://github.com/o/r/issues/7"
calls() { [ -f "$GH_LOG" ] && grep -c . "$GH_LOG" || echo 0; }

echo "flare: arguments"
FB "x" --client-id short --dry-run >/dev/null 2>&1; check $? 2 "a client id under 8 characters: exit 2"
FB "x" --client-id 'has space!' --dry-run >/dev/null 2>&1; check $? 2 "  one with other characters: exit 2"
FB "  " --client-id fb-empty-01 --dry-run >/dev/null 2>&1; check $? 2 "an empty message: exit 2"
FB "$(python3 -c 'print("a" * 20001)')" --client-id fb-long-001 --dry-run >/dev/null 2>&1; check $? 2 "a message over 20,000 characters: exit 2"
FB "x" --client-id fb-repo-001 --repo 'not a repo' --dry-run >/dev/null 2>&1; check $? 2 "a repo that is not OWNER/NAME: exit 2"

echo "flare: the issue it builds (--dry-run)"
printf 'step one\nran ``` inside\n' > "$T/a.log"
out=$(FB "$(printf 'keel line prints nothing\nExpected one line.')" --client-id fb-dry-0001 --tag keel --tag cli --attach "$T/a.log" --dry-run)
check $? 0 "a dry run exits 0"
check "$(printf '%s\n' "$out" | sed -n 's/^repo: *//p')" "220labs/regatta" "  the default repo is the public one"
check "$(printf '%s\n' "$out" | sed -n 's/^title: *//p')" "keel line prints nothing" "  the title is the message's first line"
check "$(printf '%s\n' "$out" | sed -n 's/^label: *//p')" "bug" "  a bug by default"
check "$(printf '%s\n' "$out" | grep -c '^Category: bug  $')" 1 "  the category, in the body (a stranger's label is dropped)"
check "$(printf '%s\n' "$out" | grep -c '^Tags: keel, cli$')" 1 "  the tags, in order"
check "$(printf '%s\n' "$out" | grep -c '^- Modules: .*regatta ')" 1 "  the environment names the modules and versions"
check "$(printf '%s\n' "$out" | grep -c '^<summary>\|^<details><summary>a.log</summary>$')" 1 "  the attachment folds under its file name"
check "$(printf '%s\n' "$out" | grep -c '^````$')" 2 "  in a fence longer than any it holds"
check "$(printf '%s\n' "$out" | grep -c '^<sub>Filed with regatta flare, id fb-dry-0001</sub>$')" 1 "  the id, visible, for the retry's search"
check "$(calls)" 0 "  and gh was never called"
check "$(FB "$(python3 -c 'print("w " * 60)')" --client-id fb-dry-0002 --dry-run | sed -n 's/^title: *//p' | python3 -c 'import sys; print(len(sys.stdin.read().rstrip("\n")))')" 78 \
  "a long first line is cut to 78 characters and an ellipsis"
check "$(FB "an idea" --client-id fb-dry-0003 --category idea --dry-run | sed -n 's/^label: *//p')" "enhancement" "an idea is GitHub's enhancement label"
mkdir -p "$REGATTA_CONFIG/regatta"; printf 'o/r\n' > "$REGATTA_CONFIG/regatta/flare-repo"
check "$(FB "x y" --client-id fb-dry-0004 --dry-run | sed -n 's/^repo: *//p')" "o/r" "the config key names the repo"
check "$(FB "x y" --client-id fb-dry-0005 --repo a/b --dry-run | sed -n 's/^repo: *//p')" "a/b" "  --repo wins over it"
python3 -c 'print("head\n" + "x" * 80000 + "\nTHE END")' > "$T/big.log"
out=$(FB "big" --client-id fb-dry-0006 --attach "$T/big.log" --dry-run)
check "$(printf '%s\n' "$out" | grep -c '^(the last [0-9]* of 800[0-9]* characters)$')" 1 "an attachment past what an issue holds keeps its tail, and says so"
check "$(printf '%s\n' "$out" | grep -c '^THE END$') $(printf '%s\n' "$out" | grep -c '^head$')" "1 0" "  the end is in, the head is not"
out=$(FB "$(python3 -c 'print("m" * 19000)')" --client-id fb-dry-0007 --attach "$T/big.log" --dry-run)
check "$(printf '%s\n' "$out" | sed '1,/^label:/d; /^(dry run/d' | wc -c | awk '{print ($1 <= 65536)}')" 1 "  a long message and a long log together still fit GitHub's 65,536"

echo "flare: the scan (the issue is public)"
# The fixtures are assembled at run time, so this file's own text passes the publish gate it tests.
MP="/Us""ers/someone/projects/x" AT="@" KEY="gh""p_abcdefghijklmnopqrstuvwxyz0123456789"
out=$(FB "it failed reading $MP" --client-id fb-scan-001 --dry-run 2>&1)
check $? 3 "a machine path: refused, exit 3"
check "$(printf '%s\n' "$out" | grep -c 'machine path')" 2 "  named in the title and the body"
printf 'token %s\n' "$KEY" > "$T/key.log"
FB "a clean message" --client-id fb-scan-002 --attach "$T/key.log" --dry-run >/dev/null 2>&1
check $? 3 "  a credential shape in the attachment: refused too"
printf 'commit 1d43be8e2f\nAuthor: x\n\n    Co-authored-by: Someone <%s>\n' "someone${AT}private-mail.example" > "$T/trailer.log"
FB "a clean message" --client-id fb-scan-003 --attach "$T/trailer.log" --dry-run >/dev/null 2>&1
check $? 3 "  an address on a trailer line is scanned, not dropped"
FB "it broke on the zzprivword box" --client-id fb-scan-004 --dry-run >/dev/null 2>&1
check $? 3 "  a word from the private list: refused"
printf 'took 1234567 ms in commit 1d43be8e2f, session 0b5e1c2a-1111-4222-8333-944445555666\n' > "$T/ids.log"
FB "same as https://github.com/o/r/issues/3" --client-id keel-20261024 --attach "$T/ids.log" --dry-run >/dev/null 2>&1
check $? 0 "  shas, uuids, digit runs, an issue link and a dated id pass: a bug report needs them"
check "$(calls)" 0 "  nothing was sent"

echo "flare: filing through gh"
out=$(FB "it broke" --client-id fb-send-0001 --category idea --json)
check $? 0 "filed: exit 0"
check "$(printf '%s' "$out" | J 'd["created"], d["number"], d["url"], d["repo"]')" "True 7 https://github.com/o/r/issues/7 o/r" "  the receipt"
check "$(grep -c '^issue create --repo o/r --title it broke --body-file .* --label enhancement$' "$GH_LOG")" 1 "  gh got the repo, title and label"
check "$(grep -c '^issue list --repo o/r --author @me --state all' "$GH_LOG")" 1 "  after listing the caller's own issues for the id"
check "$(grep -c '^<sub>Filed with regatta flare, id fb-send-0001</sub>$' "$GH_BODY")" 1 "  the body it filed carries the id"
LOGS=$(python3 -I -c "import sys; sys.path.insert(0, '$M/hooks'); import common; print(common.LOG_DIR)")
check "$(J 'd["url"]' < "$LOGS/flare/o--r--fb-send-0001.json")" "https://github.com/o/r/issues/7" "  the receipt is kept"
n=$(calls); out=$(FB "it broke" --client-id fb-send-0001 --json)
check "$(printf '%s' "$out" | J 'd["created"], d["url"]')" "False https://github.com/o/r/issues/7" "a retry with the id: the first receipt, created false"
check "$(calls)" "$n" "  from the kept receipt, without calling gh"
out=$(GH_LIST='[{"number": 3, "url": "https://github.com/o/r/issues/3", "body": "x\n<sub>Filed with regatta flare, id fb-send-0002</sub>\n"}]' \
  FB "again" --client-id fb-send-0002 --json)
check "$(printf '%s' "$out" | J 'd["created"], d["number"]')" "False 3" "no kept receipt, but the search finds the marker: created false"
check "$(grep -c '^issue create' "$GH_LOG")" 1 "  and nothing new is filed"
out=$(GH_LIST='[{"number": 4, "url": "u", "body": "id fb-send-00030 mentioned"}]' FB "near" --client-id fb-send-0003 --json)
check "$(printf '%s' "$out" | J 'd["created"]')" "True" "a search hit without the exact marker is not the report"
GH_CREATE="something odd" FB "odd" --client-id fb-send-0004 >/dev/null 2>&1
check $? 2 "gh printing no issue link: exit 2"
GH_LIST="not json" FB "odd" --client-id fb-send-0005 >/dev/null 2>&1
check $? 2 "  gh listing no JSON: exit 2, never the scan's 3 or a crash's 1"
n=$(grep -c '^issue create' "$GH_LOG")
check "$(FB "it broke" --client-id fb-send-0001 --repo a/b --json | J 'd["created"], d["repo"]')" "True a/b" "  the id's receipt is per repo: another repo files anew"
out=$(GH_NOLABEL=1 FB "a fork" --client-id fb-send-0006 --category question --json)
check "$(printf '%s' "$out" | J 'd["created"]') $(grep -c '^Category: question' "$GH_BODY")" "True 1" "a repo without the label: filed unlabelled, the category in the body"
check "$(CLAUDE_UNATTENDED=1 FB "unattended" --client-id fb-send-0007 >/dev/null 2>&1; echo $?)" 2 "an unattended run never sends"
check "$(CLAUDE_UNATTENDED=1 FB "unattended" --client-id fb-send-0007 --dry-run >/dev/null 2>&1; echo $?)" 0 "  but dry-runs"
S="$T/solo"; mkdir -p "$S/.claude-plugin" "$S/modules"; cp -R "$M" "$S/modules/regatta"; cp "$M/../../.claude-plugin/marketplace.json" "$S/.claude-plugin/"
out=$(env -u HELLOWORLD_WORDLIST python3 "$S/modules/regatta/libexec/flare" "no gate here" --client-id fb-solo-0001 --json 2>"$T/solo.err")
check "$(printf '%s' "$out" | J 'd["created"], d["scanned"]')" "True False" "no helloworld: the receipt is still JSON, and says it went unscanned"
check "$(grep -c 'not scanned' "$T/solo.err")" 1 "  the notice on stderr"

echo "flare: the link without gh"
out=$(GH_AUTH=1 FB "no gh here" --client-id fb-web-00001 --attach "$T/a.log" --json 2>/dev/null)
check "$(printf '%s' "$out" | J 'd["created"]')" "None" "gh signed out: created null"
check "$(printf '%s' "$out" | J 'd["url"].startswith("https://github.com/o/r/issues/new?title=no+gh+here&labels=bug&body=")')" "True" "  a prefilled new-issue link"
check "$(printf '%s' "$out" | J 'open(d["attachment"]).read().count("step one")')" 1 "  the attachment saved to paste"
check "$(printf '%s' "$out" | J '"step+one" in d["url"]')" "False" "  and kept out of the link"
out=$(FB "$(python3 -c 'print("long line " * 1500)')" --client-id fb-web-00002 --web --json)
check "$(printf '%s' "$out" | J 'len(d["url"]) <= 7500, "fb-web-00002" in d["url"]')" "True True" "--web: a long body is cut to fit a link, the id kept"

[ "$fails" -eq 0 ] && echo "flare: all ok" || echo "flare: $fails failed"
[ "$fails" -eq 0 ]
