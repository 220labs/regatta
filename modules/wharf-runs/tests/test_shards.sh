#!/usr/bin/env bash
# The selectors against stand-in suites: coverage, refusals, Linux proof runs and the Mac share.
# No process inspection, network or real HOME; also exercise the portable fixture helpers.
set -u
# check.sh's own modes, from whoever started this suite: the stand-in runs below set each where meant
unset WHARF_RUNS_LINUX_PROOF WHARF_RUNS_SKIP_LINUX_OK WHARF_RUNS_CHECK_LANES
D="$(cd "$(dirname "$0")" && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fails=0
check() { if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3: expected [$2] got [$1]"; fails=$((fails+1)); fi; }
export HOME="$T/home"; mkdir -p "$HOME" "$T/config"
. "$D/config_fixture.sh"
printf 'caller must stay unchanged\n' > "$T/caller-gitconfig"
export GIT_CONFIG_GLOBAL="$T/caller-gitconfig"
fixture_config "$T/config"
export HOME="$T/other-home"; mkdir -p "$HOME"
git config --global user.name Moved
check "$(git config --global user.name):$(git config --global user.email):$(git config --global init.defaultBranch)" \
  "Moved:t@t:main" "the fixture's identity survives a HOME move"
check "$(cat "$T/caller-gitconfig")" "caller must stay unchanged" "the caller's global config is untouched"
printf 'busy\n' > "$T/edit"; sedi 's/busy/idle/' "$T/edit"
check "$(cat "$T/edit"):$([ -e "$T/edit.bak" ] && echo backup || echo clean)" "idle:clean" "portable sed edits and removes its backup"
check "$(TZ=UTC dateat 0 +%Y-%m-%d)" "1970-01-01" "an epoch formatted by BSD or GNU date"
in2() { python3 -c 'import datetime; print((datetime.date.today()+datetime.timedelta(days=2)).isoformat())'; }
before="$(in2)"; got="$(days_from_now 2)"; after="$(in2)"   # either side of a midnight the call may straddle
check "$([ "$got" = "$before" ] || [ "$got" = "$after" ] && echo yes || echo "$got")" yes "relative calendar days"
python3 -c 'import plistlib,sys; plistlib.dump(dict(ProgramArguments=["a", "--after", "b"]), open(sys.argv[1], "wb"))' "$T/p.plist"
check "$(plistget "$T/p.plist" ProgramArguments)" '["a","--after","b"]' "plist assertions use the same compact JSON on both OSes"

mkdir -p "$T/tree/tests" "$T/tree/bin" "$T/stub"
cat > "$T/stub/ps" <<'SH'
#!/bin/sh
[ "$#" = 4 ] && [ "$1" = -o ] && [ "$2" = lstart= ] && [ "$3" = -p ] && [ "$4" -gt 0 ] || exit 64
case "${TEST_PS:-}" in deny) exit 1;; empty) exit 0;; esac
printf 'Mon Jan  1 00:00:00 2001\n'
SH
chmod +x "$T/stub/ps"; export PATH="$T/stub:$PATH"
require_process_probe probe > "$T/probe" 2>&1
check "$?" 0 "the process probe uses the arguments the real ps requires"
TEST_PS=deny require_process_probe probe > "$T/probe" 2>&1
check "$?" 2 "denied process inspection refuses a suite before its assertions"
check "$(cat "$T/probe")" "probe: cannot read this test process with ps; process inspection is required" "the refusal names the missing capability"
TEST_PS=empty require_process_probe probe > "$T/probe" 2>&1
check "$?" 2 "an empty ps answer cannot pass process assertions"
rm -f "$T/stub/ps"
cp "$D/check.sh" "$T/tree/tests/check.sh"
runner="$T/tree/tests/check.sh"
bash "$runner" --list-shards > "$T/shards"
check "$?" 0 "listing shards needs no suite execution"
all="$(cut -f2 "$T/shards" | tr ' ' '\n' | sort)"
check "$(printf '%s\n' "$all" | uniq -d)" "" "shards have no overlapping suites"
printf '#!/bin/sh\nprintf "%%s\\n" "$TEST_OS"\n' > "$T/stub/uname"; chmod +x "$T/stub/uname"
for s in $all; do
  printf '#!/bin/sh\necho "ran:%s"\n' "$s" > "$T/tree/tests/$s.sh"
done
export PATH="$T/stub:$PATH" TEST_OS=Linux
run() { bash "$runner" "$@" > "$T/out" 2>&1; }
ran() { sed -n 's/^ran://p' "$T/out" | sort; }
for shard in $(cut -f1 "$T/shards"); do
  [ "$shard" != macos ] || continue
  WHARF_RUNS_LINUX_PROOF=1 run --shard "$shard"; check "$?" 0 "Linux proof selector: $shard exits 0"
  want="$(awk -F'\t' -v s="$shard" '$1==s {print $2}' "$T/shards" | tr ' ' '\n' | sort)"
  check "$(ran)" "$want" "  runs exactly $shard's suites, including candidates"
done
run --shard queue; check "$?:$(ran)" "0:" "off macOS a plain selector leaves the unproven queue shard to a Mac (the twin's rest)"
run --shard dispatch; check "$(ran)" "test_dispatch" "off macOS a plain selector runs its proven suites"
run --shard unknown; check "$?" 2 "an unknown shard is refused"
run --shard; check "$?" 2 "a missing shard name is refused"
run --list-shards extra; check "$?" 2 "extra arguments are refused"
run --shard macos; check "$(ran)" "" "the macOS shard names its OS requirements on Linux"
run; check "$?" 0 "the default Linux mode still runs only proven suites"
proven="$(ran)"
check "$(printf '%s\n' "$proven" | grep -c '^test_dispatch$')" 1 "the unsharded Linux default runs dispatch, proven by #500's Linux run"
check "$(printf '%s\n' "$proven" | grep -c '^test_finish_queue$')" 0 "the unsharded Linux default leaves the unproven queue shard to a Mac"
TEST_OS=Darwin WHARF_RUNS_SKIP_LINUX_OK=1 run
mac="$(ran)"
check "$(printf '%s\n' "$mac" | grep -c '^test_finish_queue$')" 1 "the unsharded Mac remainder still covers the queue shard"
check "$(printf '%s\n' "$proven" "$mac" | sort)" "$all" "the unsharded Linux and Mac shares cover every suite exactly once"
printf '#!/bin/sh\necho "helper: command not found" >&2\nexit 0\n' > "$T/tree/tests/test_dispatch.sh"
run --shard dispatch; check "$?" 1 "a hidden shell error fails a Linux shard even when its suite exits 0"

# share.sh derives shard ids from check.yml's line; both Actions matrices read this list. A copy of the
# module without the repo around it (a plugin install) has no share.sh: said, as test_check.sh does.
repo="$(cd "$D/../../.." && pwd)"
if [ -f "$repo/.github/ci/share.sh" ]; then
mkdir -p "$T/share/.github/ci" "$T/share/.github/workflows" "$T/share/.circleci/parts"
cp "$repo/.github/ci/share.sh" "$T/share/.github/ci/"
cat > "$T/share/.github/workflows/check.yml" <<'YAML'
jobs:
  check:
    steps:
      - name: check
        run: |
          bash modules/wharf-runs/tests/check.sh --shard dispatch && bash modules/wharf-runs/tests/check.sh --shard pickup
YAML
printf 'wharf-runs-dispatch\nwharf-runs-pickup\n' > "$T/share/.github/ci/linux-ids"
printf 'id: [wharf-runs-dispatch, wharf-runs-pickup]\n' > "$T/share/.circleci/parts/check-linux.yml"
check "$(bash "$T/share/.github/ci/share.sh" linux-ids)" '["wharf-runs-dispatch", "wharf-runs-pickup"]' "shard selectors become distinct Linux job ids"
mkdir -p "$T/share/modules/wharf-runs/tests"
printf '#!/bin/sh\n[ "$#" = 2 ] && [ "$1" = --shard ] && [ "$2" = dispatch ] || exit 2\necho dispatched\n' > "$T/share/modules/wharf-runs/tests/check.sh"
bash "$T/share/.github/ci/share.sh" linux wharf-runs-dispatch > "$T/out" 2>&1
check "$?" 0 "a shard id runs its command with the selector intact"
check "$(grep -cx dispatched "$T/out")" 1 "the selected shard executes once"
printf 'id: [wharf-runs-dispatch]\n' > "$T/share/.circleci/parts/check-linux.yml"
bash "$T/share/.github/ci/share.sh" linux-ids > "$T/out" 2>&1
check "$?" 2 "a missing shard in CircleCI's static matrix is refused"

# The real check lines name wharf-runs once (a Mac's lanes; an older branch's check.sh), and share.sh
# expands it into one id per shard. Exercise the shares with the same stand-in suites, so CI wiring
# cannot duplicate or drop a script.
bash "$repo/.github/ci/share.sh" ids > "$T/ids"
check "$?" 0 "the wired check line has ids"
bash "$repo/.github/ci/share.sh" line "$repo" > "$T/line"
check "$?" 0 "the wired check line reads"
bash "$repo/.github/ci/share.sh" linux-ids > "$T/linux-ids"
check "$?" 0 "the wired Linux list agrees with CircleCI"
python3 - "$repo" "$T" <<'PY'
import json, pathlib, sys
repo, t = map(pathlib.Path, sys.argv[1:])
groups = [line.split("\t")[0] for line in (t / "shards").read_text().splitlines()]
commands = ["bash modules/wharf-runs/tests/check.sh --shard " + g for g in groups]
pairs = [line.split("\t", 1) for line in (t / "ids").read_text().splitlines()]
wired = [(i, c) for i, c in pairs if "modules/wharf-runs/tests/" in c]
assert wired == [("wharf-runs-" + g, c) for g, c in zip(groups, commands)], wired
plain = ["bash modules/wharf-runs/tests/check.sh"]
line = (t / "line").read_text().splitlines()
assert [c for c in line if "modules/wharf-runs/tests/" in c] == plain, line
# The root contract is private and absent from the public twin; its workflow is always present.
if (repo / "AGENTS.md").exists():
    contract = next(line for line in (repo / "AGENTS.md").read_text().splitlines() if line.startswith("- check:"))
    contract = contract.split("`", 2)[1].split(" && ")
    assert [c for c in contract if "modules/wharf-runs/tests/" in c] == plain
linux = json.loads((t / "linux-ids").read_text())
# `macos` needs a Mac; `queue` failed on Linux in #500's run (its finish-queue cases read the Mac's claim floors);
# `pickup` failed on the self-hosted runners while their image lacked lsof; the image has it (runner-lsof, 2026-11-06)
candidates = ["wharf-runs-" + g for g in groups if g not in ("macos", "queue")]
assert [i for i in linux if i.startswith("wharf-runs")] == candidates, linux
assert len(groups) == 10 and len(candidates) == 8
# a shard on the Linux list runs LINUX_OK's suites only off macOS: one of its suites off LINUX_OK would be a
# green check-linux that ran nothing, so a suite joins LINUX_OK in the change that lists its shard
import re
linux_ok = set(re.search(r'^LINUX_OK="([^"]*)"', (repo / "modules/wharf-runs/tests/check.sh").read_text(), re.M).group(1).split())
suites = dict(line.split("\t") for line in (t / "shards").read_text().splitlines())
missing = [(i, s) for i in candidates for s in suites[i[len("wharf-runs-"):]].split() if s not in linux_ok]
assert not missing, missing
(t / "commands").write_text("\n".join(commands) + "\n")
(t / "candidates").write_text("\n".join(candidates) + "\n")
(t / "whole-line").write_text(" && ".join(plain))
share = t / "share"
(share / ".github/workflows/check.yml").write_text("jobs:\n  check:\n    steps:\n      - name: check\n        run: |\n          " + " && ".join(plain + ["bash modules/extra/tests/check.sh"]) + "\n")
(share / ".github/ci/linux-ids").write_text("\n".join(candidates) + "\n")
(share / ".circleci/parts/check-linux.yml").write_text("id: [" + ", ".join(candidates) + "]\n")
PY
check "$?" 0 "the workflow and any root contract name wharf-runs once; its ids are all ten groups, eight on Linux"
# Restore the script used above to demonstrate hidden errors before replaying the whole partition.
printf '#!/bin/sh\necho ran:test_dispatch\n' > "$T/tree/tests/test_dispatch.sh"
cp -R "$T/tree/." "$T/share/modules/wharf-runs/"
mkdir -p "$T/share/modules/extra/tests"
printf '#!/bin/sh\necho ran:uncovered\n' > "$T/share/modules/extra/tests/check.sh"
TEST_OS=Darwin bash "$T/share/.github/ci/share.sh" macos > "$T/out" 2>&1
check "$?" 0 "the Mac share executes the wired remainder"
check "$(ran)" "$(printf '%s\n' test_harness test_rc_hosts test_check_ci test_vendor test_handover test_queue test_priority test_after test_rank test_finish_queue test_finish_capable test_lander uncovered | sort)" "the Mac share runs macos, queue and an uncovered command, without Linux candidates"
ran > "$T/covered"
TEST_OS=Linux bash "$T/share/.github/ci/share.sh" rest > "$T/out" 2>&1
check "$?" 0 "the twin's rest on Linux passes: queue and macos leave their suites to a Mac"
check "$(ran)" "uncovered" "  and runs none of the Mac-only suites there"
while IFS= read -r id; do
  TEST_OS=Linux bash "$T/share/.github/ci/share.sh" linux "$id" > "$T/out" 2>&1
  check "$?" 0 "the wired Linux job runs: $id"
  ran >> "$T/covered"
done < "$T/candidates"
check "$(sort "$T/covered")" "$(printf '%s\n' "$all" uncovered | sort)" "the PR's two shares execute every script exactly once"
(cd "$T/share" && TEST_OS=Darwin bash -c "$(cat "$T/whole-line")") > "$T/out" 2>&1
check "$?" 0 "the Mac whole line runs wharf-runs once, in lanes"
check "$(ran)" "$all" "the Mac whole line executes every script exactly once"
TEST_OS=Darwin bash "$T/share/.github/ci/share.sh" whole > "$T/out" 2>&1
check "$?" 0 "share.sh whole passes on a Mac"
check "$(grep -c '^== lanes: [0-9]* at once' "$T/out")" 1 "  runs wharf-runs' check.sh once, not shard by shard"
check "$(grep -c '^== lanes: 3 at once' "$T/out")" 1 "  in its three lanes"
check "$(ran)" "$(printf '%s\n' "$all" uncovered | sort)" "  and executes every script exactly once"
check "$(grep -c "(in wharf-runs-core's run)" "$T/out")" 9 "  its summary names each other shard as run in the first one's"
CHECK_CMDS="$(cat "$T/commands")" python3 "$repo/modules/wharf-runs/bin/check_scope.py" \
  "$repo" origin/main modules/wharf-runs/tests/check.sh > "$T/scope"
check "$?" 0 "the shared scope reader accepts every shard command"
check "$(grep -c '^RUN' "$T/scope"):$(grep -c '^SKIP' "$T/scope")" "10:0" "a wharf-runs test change reaches all ten shards for check and share.sh"
sedi 's/^SUITES="/SUITES="test_extra /' "$T/share/modules/wharf-runs/tests/check.sh"
bash "$T/share/.github/ci/share.sh" ids > "$T/out" 2>&1
check "$?" 2 "a broken shard partition refuses the ids"
check "$(grep -c 'wharf-runs-FAIL' "$T/out"):$(grep -c 'FAIL shard partition: test_extra' "$T/out")" "0:1" "  naming check.sh's own line, never as ids"
else
  echo "  --   skipped: no .github/ci/share.sh beside this module (a copy without the repo)"
fi

[ "$fails" = 0 ] && echo "test_shards: all passed" || echo "test_shards: $fails FAILED"
[ "$fails" = 0 ]
