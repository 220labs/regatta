#!/usr/bin/env bash
# The check line in shares, so a run waits on its slowest suite and not on their sum. Each suite that
# passes on Linux (the list in linux-ids, beside this file) runs as a job of its own, in parallel; the
# rest of the line runs in one more job.
#   - The private repo's PR check: the Linux jobs run on GitHub Actions or CircleCI (the repository
#     variable CI_LINUX_TARGET; .github/workflows/check-linux.yml, .circleci/parts/check-linux.yml),
#     and the Actions `check` on a self-hosted Mac runs only the rest (check.yml's macOS-share step,
#     taken when the repository variable CI_LINUX_ELSEWHERE is `true`). The owner, 2026-10-26: "can we
#     help regatta build queue with turning on circle ci for it? … I want to build fast";
#     docs/ci-linux-split-2026-10-26.md.
#   - The public twin, and any repo whose check.yml reads no runner variable: check.yml's `suite`
#     jobs run the Linux list on ubuntu-latest, its `check (the rest)` job the rest, and `gather`
#     reports both as `check` (free CI's S2, 2026-11-04: about 7 minutes, not 15).
#
#   share.sh ids            each command of the check line, its id first (tab-separated)
#   share.sh line DIR       DIR's check line, one command a line (check.yml's `check` step)
#   share.sh linux ID       run the command whose id is ID (one `suite` job)
#   share.sh macos [--scoped]  run every command whose id is not on the Linux list, past a failure;
#                           --scoped (a
#                           pull request: check.yml) runs only those the change reaches, check_scope.py's
#                           verdicts over what the PR's merge commit adds to its base, a `SKIP <id>` line
#                           for the rest; a change that cannot be read runs them all (free-ci S3)
#   share.sh whole [--scoped]  every command, Linux-list suites included, past a failure; --scoped
#                           is the Macs' PR road while CI_LINUX_ELSEWHERE is not true
#   share.sh rest [--scoped]   the same as macos, where the rest runs on Linux (the twin)
#   share.sh macos-scope    the verdicts `macos --scoped` runs by, said, nothing run (it reads GitHub's
#                           merge ref: HEAD^1 is the base, HEAD the PR's merge commit; on a local
#                           merge it reads only that merge's first-parent delta, not a branch's fork)
#   share.sh verdicts DIR   the fan-in: a `pass` file in DIR for every id on the Linux list
#   share.sh scope [BASE]   `RUN <why>` when HEAD's change since its fork from BASE (origin/main)
#                           reaches a Linux suite, else `NONE <why>`: the PR trigger's question
#   share.sh linux-ids [BASE]  the Linux list as one JSON array: a job matrix (check-linux.yml's,
#                           linux-on-actions 2026-11-02; check.yml's on the twin); with BASE, only
#                           the ids HEAD's change since its fork from BASE reaches
#
# The line is check.yml's `check` step, so a module that appends its check there lands in the rest
# until it joins the Linux list. An id is `plugin` for `claude plugin validate`, the module for its
# tests/check.sh, `<module>-<shard>` for tests/check.sh --shard NAME (and one per shard for a plain
# check.sh whose script answers --list-shards: wharf-runs'), `<module>-<script>` for another script,
# `line-<n>` for any other command (its place in the line). In the private repo, on a pull request only: a push, the nightly run and a hand start
# run the whole line on a Mac (check.yml), so every Darwin branch is still run each day.
# Public since free CI's S2 (2026-11-04; .circleci/ held it before, unpublished): it names no
# machine and no login, and reads a private file only where the file exists.
set -u
repo="$(cd "$(dirname "$0")/../.." && pwd)"
here="$(cd "$(dirname "$0")" && pwd)"

line_of() {
    # DIR's check line: the `run:` block of the step named `check` in DIR's check.yml, its `&&`s
    # outside braces and quotes as the cuts (here since S2; .circleci/twin-linux.sh asks this one)
    python3 - "$1/.github/workflows/check.yml" <<'PY'
import re, sys
lines = open(sys.argv[1]).read().splitlines()
start = next(i for i, l in enumerate(lines) if re.match(r"^\s*- name: check\s*$", l))
run, key = [], None
for l in lines[start + 1:]:
    ind = len(l) - len(l.lstrip())
    if key is None:
        if re.match(r"^\s*- ", l):
            break
        if re.match(r"^\s*run: \|", l):
            key = ind; run.append(l)
        continue
    # the block ends at the first line back at the key's column or left of it: the next step, or a
    # job after this one (check is not the file's last job since the shares' road, S2)
    if l.strip() and ind <= key:
        break
    run.append(l)
# a `#` line would comment out the whole joined line, an apostrophe in it open a quote
text = " ".join(l.strip() for l in run[1:] if l.strip() and not l.strip().startswith("#"))
cmds, cur, depth, quote, i = [], "", 0, None, 0
while i < len(text):
    c = text[i]
    if quote:
        quote = None if c == quote else quote
    elif c in "'\"":
        quote = c
    elif c == "{":
        depth += 1
    elif c == "}":
        depth -= 1
    elif depth == 0 and text.startswith("&&", i):
        cmds.append(cur.strip()); cur = ""; i += 2
        continue
    cur += c
    i += 1
if cur.strip():
    cmds.append(cur.strip())
if not cmds:
    sys.exit("no command in the check step")
print("\n".join(cmds))
PY
}

ids() {
    local cmds
    cmds="$(line_of "$repo")" || return 2
    local n=0
    printf '%s\n' "$cmds" | while IFS= read -r cmd; do
        local id path shard shards
        n=$((n + 1))
        case "$cmd" in
            *"claude plugin validate"*) id=plugin ;;
            *)
                path="$(printf '%s' "$cmd" | grep -o 'modules/[a-z0-9-]*/tests/[A-Za-z0-9_.-]*\.sh' | tail -1)"
                # any other command is the line's own (`line-<n>`): in the macOS share until the
                # matrix names it, never a refusal of both shares
                if [ -z "$path" ]; then id="line-$n"
                else
                    id="$(printf '%s' "$path" | sed -E 's#modules/([^/]*)/tests/(.*)\.sh#\1-\2#; s#-check$##')"
                    if [ "${path##*/}" = check.sh ]; then
                        shard="$(printf '%s' "$cmd" | sed -nE 's/.* --shard ([a-z0-9-]+)([ ;}].*)?$/\1/p')"
                        [ -z "$shard" ] || id="$id-$shard"
                        # a plain `bash <module>/tests/check.sh` whose script lists shards is one row per
                        # shard: the line keeps one command (a Mac's lanes; a branch's older check.sh), the
                        # shares judge and run each shard by its own id (wharf-runs-linux's landing review)
                        if [ -z "$shard" ] && [ "$cmd" = "bash $path" ] && grep -q -e '--list-shards)' "$repo/$path" 2>/dev/null; then
                            # its status first, then cut: a failed partition check's FAIL line must not become ids
                            # stdout alone: a shell's warning on stderr (a locale, BASH_ENV) is no shard name
                            errf="$(mktemp)"
                            shards="$(bash "$repo/$path" --list-shards </dev/null 2>"$errf")" \
                                || { echo "share.sh: $path --list-shards: $shards $(cat "$errf")" >&2; rm -f "$errf"; return 2; }
                            rm -f "$errf"
                            shards="$(printf '%s\n' "$shards" | cut -f1)"
                            [ -n "$shards" ] || { echo "share.sh: $path --list-shards named no shard" >&2; return 2; }
                            if printf '%s\n' "$shards" | grep -qv '^[a-z0-9-]*$'; then
                                echo "share.sh: $path --list-shards printed a name that is no shard's: $(printf '%s' "$shards" | grep -v '^[a-z0-9-]*$' | head -1)" >&2; return 2
                            fi
                            for shard in $shards; do printf '%s-%s\t%s --shard %s\n' "$id" "$shard" "$cmd" "$shard"; done
                            continue
                        fi
                    fi
                fi
                ;;
        esac
        printf '%s\t%s\n' "$id" "$cmd"
    done
}

linux_ids() {
    # the Linux list: linux-ids beside this file, one id a line, `#` to the line's end and blanks skipped
    local ids
    ids="$(sed -e 's/#.*//' -e 's/[[:space:]]//g' "$here/linux-ids" 2>/dev/null | grep -v '^$' | tr '\n' ' ')"
    [ -n "$ids" ] || { echo "share.sh: no Linux list in $here/linux-ids" >&2; return 2; }
    # a duplicate would be two matrix legs of one suite (the twin has no CircleCI matrix to catch it)
    local dup
    # shellcheck disable=SC2086 — the list is words, one id each
    dup="$(printf '%s\n' $ids | sort | uniq -d | tr '\n' ' ')"
    [ -z "$dup" ] || { echo "share.sh: $here/linux-ids names ${dup% } more than once" >&2; return 2; }
    echo " $ids"
}

circleci_ids() {
    # <list>: CircleCI's static matrix cannot read linux-ids, so where the private .circleci/ is (the
    # twin has none) its `id:` list must hold the same ids, or both shares would drift apart
    local part="$repo/.circleci/parts/check-linux.yml" got want
    [ -f "$part" ] || return 0
    got="$(sed -n -E 's/^ *id: \[(.*)\] *$/\1/p' "$part" | tr -d ' ' | tr ',' '\n' | grep -v '^$' | sort | tr '\n' ' ')"
    # shellcheck disable=SC2086 — the list is words, one id each
    want="$(printf '%s\n' $1 | sort | tr '\n' ' ')"
    [ "$got" = "$want" ] || { echo "share.sh: .circleci/parts/check-linux.yml's id matrix ($got) is not .github/ci/linux-ids ($want)" >&2; return 1; }
}

on_linux() { case "$2" in *" $1 "*) return 0 ;; esac; return 1; }

verify() {
    # every Linux id names a command of the line: a renamed suite must not leave both shares
    local all lx id dup bad=0
    all="$(ids)" || return 2
    lx="$(linux_ids)" || return 2
    for id in $lx; do
        printf '%s\n' "$all" | cut -f1 | grep -qx "$id" || { echo "share.sh: Linux id $id names no command of check.yml's line" >&2; bad=1; }
    done
    # two commands under one id would run as one `bash -c`, the first one's failure masked by the last
    dup="$(printf '%s\n' "$all" | cut -f1 | sort | uniq -d | tr '\n' ' ')"
    [ -z "$dup" ] || { echo "share.sh: two commands of the line share an id: $dup" >&2; bad=1; }
    circleci_ids "$lx" || bad=1
    return $bad
}

macos_scope() {
    # The Macs' PR job, scoped (free-ci S3): one `<id><TAB>RUN|SKIP<TAB><why>` line per command of the line
    # (stdin: the `ids` pairs), after a `SCOPE<TAB><said>` line, by check_scope.py's rules (the verdicts
    # the in-session `check <worktree>` gives). The change is what the pull request's merge commit adds to
    # its base: HEAD^1..HEAD, a shallow checkout of refs/pull/N/merge holding both (check.yml's
    # fetch-depth 2). Never refuses: whatever cannot be read (HEAD no merge, git or check_scope.py failing,
    # a verdict count that does not match) says why and runs every command, more checking, never fewer.
    # A change under .github/ (this script included), or to check_scope.py, runs the whole line as
    # well: check_scope.py counts .github/ as reaching no suite, and those files are the CI that runs the line.
    local pairs reason="" changed verdicts parents wf
    pairs="$(cat)"
    parents="$(git -C "$repo" rev-list --parents -n 1 HEAD 2>/dev/null | wc -w | tr -d ' ')"
    if [ "$parents" != 3 ]; then reason="HEAD is not the merge of a pull request's head into its base"
    else
        # quotePath off: a non-ASCII name comes quoted otherwise, and misses its docs/ prefix
        changed="$(git -C "$repo" -c core.quotePath=false diff --no-renames --name-only HEAD^1 HEAD 2>/dev/null)" \
            || reason="the change since the base could not be read"
    fi
    if [ -z "$reason" ]; then
        # a scope never judges its own change: a PR that edits the rules would be cut by the rules it edits
        wf="$(printf '%s\n' "$changed" | grep -m1 -E '^(\.github/|modules/wharf-runs/bin/check_scope\.py$)')" \
            && reason="$wf changed: the CI or the scope that runs the line"
    fi
    if [ -z "$reason" ]; then
        verdicts="$(CHECK_CMDS="$(printf '%s\n' "$pairs" | cut -f2-)" \
                    python3 "$repo/modules/wharf-runs/bin/check_scope.py" "$repo" "the pull request's base" "$changed")" \
            || reason="check_scope.py could not judge the change"
    fi
    if [ -z "$reason" ]; then
        PAIRS="$pairs" VERDICTS="$verdicts" python3 -c '
import os, sys
ids = [l.split("\t", 1)[0] for l in os.environ["PAIRS"].split("\n") if l]
lines = [l for l in os.environ["VERDICTS"].split("\n") if l]
said = [l.split("\t", 1)[1] for l in lines if l.startswith("SCOPE\t")]
vs = [l for l in lines if not l.startswith("SCOPE\t")]
if len(said) != 1 or len(ids) != len(vs) or any(v.split("\t", 1)[0] not in ("RUN", "SKIP") for v in vs): sys.exit(3)
print("SCOPE\t" + said[0])
for i, v in zip(ids, vs):
    k, _, why = v.partition("\t")
    print("%s\t%s\t%s" % (i, k, why))' || reason="check_scope.py gave a verdict list that does not match the line"
    fi
    if [ -n "$reason" ]; then
        echo "SCOPE	the whole line: $reason"
        printf '%s\n' "$pairs" | while IFS=$'\t' read -r id _; do printf '%s\tRUN\t%s\n' "$id" "$reason"; done
    fi
}

run_one() {
    # one command from the repo's root; stdin off, as twin-linux.sh's run
    local cmd="$1" t0 rc
    echo "=== $cmd"
    t0=$(date +%s)
    (cd "$repo" && bash -c "$cmd") </dev/null
    rc=$?
    echo "=== rc=$rc $(( $(date +%s) - t0 ))s"
    return $rc
}

case "${1:-}" in
    ids) ids ;;
    line)
        [ -n "${2:-}" ] || { echo "usage: $0 line DIR" >&2; exit 2; }
        line_of "$2"
        ;;
    linux)
        [ -n "${2:-}" ] || { echo "usage: $0 linux ID" >&2; exit 2; }
        verify || exit 2
        cmd="$(ids | awk -F'\t' -v id="$2" '$1 == id { print $2 }')"
        [ -n "$cmd" ] || { echo "share.sh: no command with id $2" >&2; exit 2; }
        run_one "$cmd"
        ;;
    macos-scope)
        # the verdicts `macos --scoped` runs by, said, nothing run: a SCOPE line, then `<id> RUN|SKIP <why>`
        verify || exit 2
        echo "scope input: HEAD^1 ($(git -C "$repo" rev-parse --short HEAD^1 2>/dev/null || echo unreadable))..HEAD ($(git -C "$repo" rev-parse --short HEAD 2>/dev/null || echo unreadable)); a local merge reads its first-parent delta, not the branch's fork" >&2
        ids | macos_scope
        ;;
    macos|rest|whole)
        # --scoped (check.yml's pull_request step): the suites the change reaches, a `SKIP <id>` for the rest
        scoped=""
        case "${2:-}" in --scoped) scoped=1 ;; "") ;; *) echo "usage: $0 $1 [--scoped]" >&2; exit 2 ;; esac
        verify || exit 2
        lx="$(linux_ids)" || exit 2
        all="$(ids)" || exit 2
        verdict=""
        if [ -n "$scoped" ]; then
            verdict="$(printf '%s\n' "$all" | macos_scope)"
            printf '%s\n' "$verdict" | awk -F'\t' '$1 == "SCOPE" { print "=== scope: " $2 }'
        fi
        summary=(); failed=0
        # `whole` runs a command ids split into shards once, as the line names it (a Mac's three lanes),
        # not shard by shard in one lane each; every shard of it shares one module's scope verdict
        line=""; [ "$1" != whole ] || { line="$(line_of "$repo")" || exit 2; }
        ran_base=""; ran_id=""; ran_rc=""
        while IFS=$'\t' read -r id cmd; do
            # `whole` runs every line here; the other shares leave a Linux-list id (a wharf-runs shard included:
            # each shard is its own id since wharf-runs-linux) to its Linux job
            if [ "$1" != whole ] && on_linux "$id" "$lx"; then summary+=("LINUX  $id"); continue; fi
            if [ -n "$scoped" ]; then
                # a command the verdicts do not name runs: never fewer than the line
                sk="$(printf '%s\n' "$verdict" | awk -F'\t' -v id="$id" '$1 == id && $2 == "SKIP" { print $3; exit }')"
                if [ -n "$sk" ]; then echo "SKIP $id: $sk"; summary+=("SKIP  $id"); continue; fi
            fi
            base="${cmd% --shard *}"
            if [ -n "$line" ] && [ "$base" != "$cmd" ] && printf '%s\n' "$line" | grep -Fxq -- "$base"; then
                if [ "$base" = "$ran_base" ]; then
                    if [ "$ran_rc" = 0 ]; then summary+=("PASS  $id (in $ran_id's run)"); else summary+=("FAIL  $id (in $ran_id's run)"); fi
                    continue
                fi
                ran_base="$base"; ran_id="$id"; cmd="$base"
            fi
            t0=$(date +%s)
            if run_one "$cmd"; then r=0; summary+=("PASS $(( $(date +%s) - t0 ))s  $id")
            else r=1; failed=$((failed + 1)); summary+=("FAIL $(( $(date +%s) - t0 ))s  $id"); fi
            [ "$cmd" != "$ran_base" ] || ran_rc=$r
        done <<< "$all"
        echo
        if [ "$1" = whole ]; then echo "=== the whole line: $failed failed"
        elif [ "$1" = rest ]; then echo "=== the rest of the line: $failed failed (the LINUX lines run in jobs of their own)"
        else echo "=== the macOS share: $failed failed (a LINUX line is check-linux's, which scopes its own)"; fi
        printf '%s\n' "${summary[@]}"
        [ "$failed" -eq 0 ]
        ;;
    scope)
        # Does the PR's change reach a Linux suite? The Actions trigger asks before it spends credits
        # (.github/workflows/check-linux.yml). check_scope.py judges the Linux ids' module suites against
        # what HEAD changed since its fork from BASE. A command that is no module's suite (`plugin`, a
        # `line-<n>`) is left out, not filtered by its verdict's wording: a change it would see (a
        # plugin.json, the marketplace) reaches a module or the whole line anyway. A change under
        # .github/ runs, as the macOS share's scope does: the Linux commands are read from check.yml's line, and
        # check_scope.py counts most of .github/ as reaching no suite (.github/ci/ as the whole line, the two
        # check workflows as wharf's, whose suite reads them). Since every module declares the core, which is on the
        # Linux list, any change under modules/ reads RUN: NONE is a PR of docs and records only.
        # Prints `RUN <said>` or `NONE <said>`; exit 2 when it cannot tell (the caller runs).
        base="${2:-origin/main}"
        verify || exit 2
        lx="$(linux_ids)" || exit 2
        # an `if`, not a `case`: macOS's bash 3.2 misreads a pattern's lone `)` inside "$(…)"
        cmds="$(ids | while IFS=$'\t' read -r id cmd; do
                  if [ "$id" = plugin ] || [ "${id#line-}" != "$id" ]; then continue; fi
                  on_linux "$id" "$lx" && printf '%s\n' "$cmd"; done)"
        mb="$(git -C "$repo" merge-base "$base" HEAD 2>/dev/null)" || { echo "share.sh: no fork point from $base" >&2; exit 2; }
        # quotePath off: a non-ASCII name comes quoted otherwise, and misses its docs/ prefix
        changed="$(git -C "$repo" -c core.quotePath=false diff --no-renames --name-only "$mb" HEAD)" || exit 2
        wf="$(printf '%s\n' "$changed" | grep -m1 -E '^\.github/')" && { echo "RUN $wf changed: the CI that runs the line"; exit 0; }
        # any module or manifest change runs, said outright: today every module declaring the core gives the
        # same verdict, but a module that declared nothing would leave `plugin` (left out above) unrun
        mc="$(printf '%s\n' "$changed" | grep -m1 -E '^(modules|\.claude-plugin)/')" && { echo "RUN $mc changed"; exit 0; }
        verdicts="$(CHECK_CMDS="$cmds" python3 "$repo/modules/wharf-runs/bin/check_scope.py" "$repo" "$base" "$changed")" || exit 2
        said="$(printf '%s\n' "$verdicts" | sed -n 's/^SCOPE\t//p')"
        [ -n "$said" ] || { echo "share.sh: check_scope.py said nothing" >&2; exit 2; }
        if printf '%s\n' "$verdicts" | grep -q '^RUN'; then echo "RUN $said"
        else echo "NONE no Linux suite is reached by what changed since $base"; fi
        ;;
    linux-ids)
        # With BASE, only the ids HEAD's change since its fork from BASE reaches, by check_scope.py's
        # rules (the Macs' check scope): Actions' matrix is built per run, so a PR spends minutes on the
        # suites it reaches, not all of them (the landing review, 2026-11-02). `plugin` and a `line-<n>`
        # are no module's suite and always run; a change under .github/, or to
        # check_scope.py, runs the whole list, as the macOS share's scope does; a list that comes out empty runs
        # the whole list, never an empty matrix.
        verify || exit 2
        lx="$(linux_ids)" || exit 2
        if [ -n "${2:-}" ]; then
            mb="$(git -C "$repo" merge-base "$2" HEAD 2>/dev/null)" || { echo "share.sh: no fork point from $2" >&2; exit 2; }
            changed="$(git -C "$repo" -c core.quotePath=false diff --no-renames --name-only "$mb" HEAD)" || exit 2
            if ! printf '%s\n' "$changed" | grep -q -E '^(\.github/|modules/wharf-runs/bin/check_scope\.py$)'; then
                pairs="$(ids | while IFS=$'\t' read -r id cmd; do on_linux "$id" "$lx" && printf '%s\t%s\n' "$id" "$cmd"; done)"
                verdicts="$(CHECK_CMDS="$(printf '%s\n' "$pairs" | cut -f2-)" \
                            python3 "$repo/modules/wharf-runs/bin/check_scope.py" "$repo" "$2" "$changed")" || exit 2
                reached="$(PAIRS="$pairs" VERDICTS="$verdicts" python3 -c '
import os, sys
ids = [l.split("\t", 1)[0] for l in os.environ["PAIRS"].split("\n") if l]
vs = [l.split("\t", 1)[0] for l in os.environ["VERDICTS"].split("\n") if l and not l.startswith("SCOPE")]
if len(ids) != len(vs): sys.exit("share.sh: check_scope.py gave %d verdicts for %d ids" % (len(vs), len(ids)))
print(" ".join(i for i, v in zip(ids, vs) if v == "RUN"))')" || exit 2
                [ -z "$reached" ] || lx=" $reached "
            fi
        fi
        # shellcheck disable=SC2086 — the list is words, one id each
        python3 -c 'import json, sys; print(json.dumps(sys.argv[1:]))' $lx
        ;;
    verdicts)
        [ -d "${2:-}" ] || { echo "usage: $0 verdicts DIR" >&2; exit 2; }
        lx="$(linux_ids)" || exit 2
        bad=0
        for id in $lx; do
            v="$(cat "$2/$id" 2>/dev/null || echo missing)"
            echo "$v  $id"
            [ "$v" = pass ] || bad=1
        done
        exit $bad
        ;;
    *) sed -n '2,43p' "$0" >&2; exit 2 ;;
esac
