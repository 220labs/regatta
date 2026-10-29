#!/usr/bin/env bash
# Tests for bin/paste-paths — the built-in cases, then two fixture files through the real CLI.
#   bash modules/keel/tests/paste-paths.sh
set -u
B="$(cd "$(dirname "$0")/../bin" && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
T=$(cd "$T" && pwd -P)  # /var is /private/var: the hand-over line's file link is compared resolved anyway
# before any case moves HOME: a scratch config dir, the owner Sam (tests/config.sh)
. "$(dirname "$0")/config.sh"; keel_config "$T/config"
fails=0
# The hand-over line (bin/keel line_findings): what this Mac knows, pinned to the suite. A stub CLI
# makes the page owed (the hook never runs it): as course with D-items, else as local, and as space
# (2026-10-14, 2026-10-26). SPACESHEEP_CONFIG_DIR: never the Mac's own mirror.json, so a running mirror
# changes no case's line
export MEMO_STATE_DIR="$T/state" MEMO_SHEEP_STATE="$T/sheep" MEMO_SHEEP_BIN="$T/spacesheep" SPACESHEEP_KEY=ss_test SPACESHEEP_CONFIG_DIR="$T/ss-config"
unset CLAUDE_UNATTENDED REGATTA_UNATTENDED CLAUDE_CODE_ENTRYPOINT  # each drops a part of the line; the cases that want one set it
printf '#!/bin/sh\nexit 9\n' > "$T/spacesheep"; chmod +x "$T/spacesheep"
unset CLAUDE_UNATTENDED REGATTA_UNATTENDED CLAUDE_HOOK_NO_SHEEP
unset BASH_ENV   # a CI job's PATH, re-read by every bash stub (keel.sh says why)
form() {  # form <doc>: its spacesheep page — the form since 2026-10-14; unpinned, any page passes
  echo "https://spacesheep.dev/@sam/$(basename "$1" .md)"; }
SPACE=https://spacesheep.dev/@sam/orch
check() { if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3: expected [$2] got [$1]"; fails=$((fails+1)); fi; }
has() { case "$1" in *"$2"*) echo "  ok   $3" ;; *) echo "  FAIL $3: [$2] not in [$1]"; fails=$((fails+1)) ;; esac; }

python3 "$B/paste-paths" --self-test > "$T/self" 2>&1; rc=$?
check "$rc" 0 "self-test exits 0"
check "$(grep -c '^FAIL' "$T/self")" 0 "self-test has no FAIL line"

cat > "$T/bad.md" <<'EOF'
# A digest

Run this:

```bash
sh macos/vscode-remote/install.sh
ssh nas 'sh scripts/x.sh'
```

Prose mention of `sh scripts/test.py` is fine.
EOF
cat > "$T/good.md" <<'EOF'
```bash
sh /srv/sam/projects/house/macos/vscode-remote/install.sh
python3 /srv/sam/projects/house/scripts/test.py --check
```
EOF

python3 "$B/paste-paths" "$T/bad.md" > "$T/out" 2>"$T/err"; rc=$?
check "$rc" 1 "a relative sh path is exit 1"
check "$(grep -c "^$T/bad.md:6:" "$T/out")" 1 "the hit names file and line 6"
check "$(grep -c 'scripts/x.sh' "$T/out")" 0 "the ssh remote path is not a hit"
check "$(grep -c 'relative path' "$T/err")" 1 "stderr carries the one-line reason"

python3 "$B/paste-paths" "$T/good.md" > "$T/out" 2>&1; rc=$?
check "$rc" 0 "absolute paths are exit 0"
check "$(wc -c < "$T/out" | tr -d ' ')" 0 "and print nothing"

printf '````markdown\nA block that shows a fence:\n```\nsh scripts/x.sh\n````\n' > "$T/long.md"
python3 "$B/paste-paths" "$T/long.md" > "$T/out" 2>&1; rc=$?
check "$rc" 1 "a \`\`\`\` block does not close at an inner \`\`\`: its relative path is a hit (hooks/common.py's fence rule)"

python3 "$B/paste-paths" "$T/good.md" "$T/bad.md" > "$T/out" 2>&1; rc=$?
check "$rc" 1 "several files: one bad file fails the run"

python3 "$B/paste-paths" > "$T/out" 2>&1; rc=$?
check "$rc" 2 "no arguments: usage, exit 2"

# --stop-hook (dream 2026-09-27 P9): the last reply of a transcript, blocked once
tr_() {  # tr_ <file> <assistant text>: a prompt, a tool round, then the reply
  python3 - "$1" "$2" <<'PY'
import json, sys
f, text = sys.argv[1], sys.argv[2]
rows = [{"type": "user", "message": {"content": "old prompt"}},
        {"type": "assistant", "message": {"content": [{"type": "text", "text": "```bash\nsh old/x.sh\n```"}]}},
        {"type": "user", "message": {"content": "new prompt"}},
        {"type": "assistant", "message": {"content": [{"type": "tool_use", "id": "1"}]}},
        {"type": "user", "message": {"content": [{"type": "tool_result", "tool_use_id": "1"}]}},
        {"type": "assistant", "message": {"content": [{"type": "text", "text": text}]}}]
open(f, "w").write("\n".join(json.dumps(r) for r in rows) + "\n")
PY
}
sh_() { printf '{"transcript_path":"%s","stop_hook_active":%s}' "$1" "${2:-false}" | python3 "$B/paste-paths" --stop-hook; }
tr_ "$T/t1.jsonl" $'Run:\n```bash\npython3 scripts/ha.py errors 20\n```'
check "$(sh_ "$T/t1.jsonl" | grep -c '"decision": "block"')" 1 "stop: a relative path in the last reply blocks"
check "$(sh_ "$T/t1.jsonl" true | wc -c | tr -d ' ')" 0 "  but never twice (stop_hook_active)"
tr_ "$T/t2.jsonl" 'Launched as PR #42, and see [x](vscode://file/a).'
check "$(sh_ "$T/t2.jsonl" | grep -c 'bare PR number.*vscode')" 1 "stop: a bare PR #N and a vscode:// link are named"
tr_ "$T/t3.jsonl" $'Launched: [house#42 (robots)](https://github.com/samco/house/pull/42).\n```bash\nsh /srv/sam/x.sh\n```'
check "$(sh_ "$T/t3.jsonl" | wc -c | tr -d ' ')" 0 "stop: a clean reply passes (and an earlier turn's block is not read)"
# the declared line (rename S4, M3): the new one is said from S4, the old one still ends a reply until S8
tr_ "$T/t3n.jsonl" $'Pushed; the PR is WIP.\n\n✅ SAM, THIS SESSION IS DONE — IT LAUNCHES BY ITSELF.'
check "$(sh_ "$T/t3n.jsonl" | wc -c | tr -d ' ')" 0 "stop: the declared line in its new word passes"
tr_ "$T/t3o.jsonl" $'Pushed; the PR is WIP.\n\n✅ SAM, THIS SESSION IS DONE — IT LANDS BY ITSELF.'
check "$(sh_ "$T/t3o.jsonl" | wc -c | tr -d ' ')" 0 "  and the old one (a session started before S4) is still accepted, not held"
tr_ "$T/t3x.jsonl" $'Pushed; the PR is WIP.\n\n✅ SAM, THIS SESSION IS DONE — IT SAILS BY ITSELF.'
check "$(sh_ "$T/t3x.jsonl" | grep -c 'is not one of the fixed closing lines')" 1 "  while a line in neither word is held"
check "$(grep -c 'IT LANDS BY ITSELF\.' "$0") $(grep -c 'IT LAUNCHES BY ITSELF\.' "$0")" "1 1" "rename guard: the old declared line's fixture keeps its land word (IT LANDS / IT LAUNCHES BY ITSELF)"

# owed-lists (docs/record/owed-check-2026-10-02.md): every item says how it was checked
tr_ "$T/t4.jsonl" $'Done.\n\n**Still owed by you:**\n- Delete the key from settings.json.\n- Paste prompt 2.'
check "$(sh_ "$T/t4.jsonl" | grep -c 'owed item(s) without a check')" 1 "stop: an owed-list with unchecked items blocks"
tr_ "$T/t5.jsonl" $'**Still owed by you:**\n- Delete the key. checked: absent in settings.json\n- Paste prompt 2. not checked: needs the other transcript — ask?'
check "$(sh_ "$T/t5.jsonl" | wc -c | tr -d ' ')" 0 "stop: every item checked passes"
tr_ "$T/t6.jsonl" $'The owed list should name its checks.\nNothing carried forward.\n```text\nStill owed:\n- inside a fence\n```'
check "$(sh_ "$T/t6.jsonl" | wc -c | tr -d ' ')" 0 "stop: prose about owed lists, and a fenced one, pass"

# a reply asking D-items carries its doc's hand-over line, as `keel line` prints it (Sam, 2026-10-07)
R="$T/repo"; mkdir -p "$R/docs"
git -C "$R" init -q -b main && git -C "$R" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
git -C "$R" remote add origin https://github.com/o/r.git
git -C "$R" checkout -q -b claude/x/2026-10-02-orch
cat > "$R/docs/orch-2026-10-02.md" <<'EOF'
# Orchestration

- **D1 — Where the dispatcher runs.** On buildbox.
  ➤ Answer: buildbox, under launchd.
- **D2 — Which model plans.** Fable.
  ➤ Answer: Fable high for the planner.
EOF
git -C "$R" add docs && git -C "$R" -c user.name=t -c user.email=t@t commit -q -m doc
sc_() { printf '{"transcript_path":"%s","stop_hook_active":%s,"cwd":"%s"}' "$1" "${2:-false}" "$R" | python3 "$B/paste-paths" --stop-hook; }
DL=$'Two questions:\n\n- **D1 — Where the dispatcher runs.**\n  ➤ Answer: buildbox, under launchd.\n- **D2 — Which model plans.**\n  ➤ Answer: Fable high for the planner.'
DOC="$R/docs/orch-2026-10-02.md"
F1=$(form "$DOC")
GH=https://github.com/o/r/blob/claude/x/2026-10-02-orch/docs/orch-2026-10-02.md
FL="[orch-2026-10-02.md]($DOC#L1)"
LINE="[course]($F1) | [github]($GH) | [space]($SPACE) — $FL"
tr_ "$T/a.jsonl" "$DL"
check "$(sc_ "$T/a.jsonl" | grep -c "keel line .*/docs/orch-2026-10-02.md")" 1 "line: a branch doc's D-list without its line blocks, naming keel line"
check "$(sc_ "$T/a.jsonl" true | wc -c | tr -d ' ')" 0 "  but never twice (stop_hook_active)"
check "$(sc_ "$T/a.jsonl" | grep -c 'hands no doc')" 0 "  and only the branch-doc finding, not the no-doc one too"
tr_ "$T/b.jsonl" "$DL"$'\n\n'"$LINE"
check "$(sc_ "$T/b.jsonl" | wc -c | tr -d ' ')" 0 "line: the full line — course | github | space — file — passes"
tr_ "$T/b1.jsonl" "$DL"$'\n\n'"[course]($F1) | [github]($GH) — $FL"
check "$(sc_ "$T/b1.jsonl" | wc -c | tr -d ' ')" 0 "line: with D-items the page goes as form, so no space link is owed (2026-10-14)"
tr_ "$T/b2.jsonl" "$DL"$'\n\n'"[github]($GH) | [space]($SPACE) — $FL"
check "$(sc_ "$T/b2.jsonl" | grep -c 'the course link is missing')" 1 "line: no course on a doc with D-items blocks"
tr_ "$T/b4.jsonl" "$DL"$'\n\n'"[course]($F1) | [space]($SPACE) — $FL"
check "$(sc_ "$T/b4.jsonl" | grep -c 'the github link is missing')" 1 "line: no github blocks"
tr_ "$T/b5.jsonl" "$DL"$'\n\n'"[course]($F1) | [github]($GH) | [space]($SPACE) — [orch-2026-10-02.md]($DOC)"
check "$(sc_ "$T/b5.jsonl" | grep -c 'the file link ends #L1')" 1 "line: a file link without #L1 blocks"
tr_ "$T/b6.jsonl" "$DL"$'\n\n'"[course](http://127.0.0.1:9/gone/) | [github]($GH) | [space]($SPACE) — $FL"
check "$(sc_ "$T/b6.jsonl" | grep -cE 'not a running memo serve|has a spacesheep page')" 1 "line: a form link to no running serve blocks (where the doc has a page, as a memo serve form at all: review 2026-10-16)"
tr_ "$T/b7.jsonl" "$DL"$'\n\n'"[docs/orch-2026-10-02.md]($DOC)"$'\nanswer: https://github.com/o/r/edit/claude/x/2026-10-02-orch/docs/orch-2026-10-02.md'
check "$(sc_ "$T/b7.jsonl" | grep -c 'hand-over line is not right')" 1 "line: the retired shape (local link, edit URL) blocks"
# a nested set (shape D4-A): `keel line <entry>` prints one line per file, the entry first; a reply
# that asks a component's items and carries those lines passes (entry S8, 2026-10-15)
cat > "$R/docs/set-2026-10-15.md" <<EOF
# Set — entry (entry doc, 2026-10-15)

Status: proposed — 0 of 1 decision answered · action plan: 0 of 1 step done · handed over 2026-10-15

The [alpha component]($R/docs/set-alpha-2026-10-15.md).

- **D1 — Whether the set ships.** Body.
  ➤ Answer: ship it this week.
EOF
cat > "$R/docs/set-alpha-2026-10-15.md" <<'EOF'
# Set — alpha (component doc, 2026-10-15)

Status: proposed — 0 of 1 decision answered · built by entry S1 (0 of 1 done) · handed over 2026-10-15

- **D1 — Which queue alpha drains.** Body.
  ➤ Answer: the nightly queue only.
EOF
git -C "$R" add docs && git -C "$R" -c user.name=t -c user.email=t@t commit -q -m set
SE="$R/docs/set-2026-10-15.md"; SA="$R/docs/set-alpha-2026-10-15.md"
FE=$(form "$SE"); FA=$(form "$SA")
GHS=https://github.com/o/r/blob/claude/x/2026-10-02-orch/docs
LE="[course]($FE) | [github]($GHS/set-2026-10-15.md) | [space]($SPACE) — [set-2026-10-15.md]($SE#L1)"
LA="[course]($FA) | [github]($GHS/set-alpha-2026-10-15.md) | [space]($SPACE) — [set-alpha-2026-10-15.md]($SA#L1)"
DA=$'One question on alpha:\n\n- **D1 — Which queue alpha drains.**\n  ➤ Answer: the nightly queue only.'
tr_ "$T/s1.jsonl" "$DA"$'\n\n'"$LE"$'\n'"$LA"
check "$(sc_ "$T/s1.jsonl" | wc -c | tr -d ' ')" 0 "line: a set's lines, one per file as keel line <entry> prints them, pass"
tr_ "$T/s2.jsonl" "$DA"$'\n\n'"$LE"
check "$(sc_ "$T/s2.jsonl" | grep -c 'set-alpha-2026-10-15.md, but its hand-over line is not right')" 1 "line: a component's items with only the entry's line block, naming the component"
# The turn's text is the transcript's messages UNION the payload's last one (2026-10-07). The file
# can lag the final message (the gate blocked 137 replies between 2026-10-04 and 2026-10-07, 15 of
# them for a D-list with no doc, and at least four D-lists in chat still passed), and the payload
# holds only that final message, so each source alone has a blind spot. Each case below fails
# against one of the two single-source versions.
lag_() { python3 - "$1" "$2" "$R" <<'PY' | python3 "$B/paste-paths" --stop-hook
import json, sys
print(json.dumps({"transcript_path": sys.argv[1], "last_assistant_message": sys.argv[2], "cwd": sys.argv[3]}))
PY
}
tr_ "$T/lag.jsonl" 'An older reply, already flushed.'
DLC=$'Quick ones, here only:\n\n- **D1 — Rename the session now?**\n  ➤ Answer: yes.'
check "$(lag_ "$T/lag.jsonl" "$DLC" | grep -c 'hands no doc')" 1 "payload: a D-list the transcript does not hold yet still blocks"
: > "$T/empty.jsonl"
check "$(lag_ "$T/empty.jsonl" "$DLC" | grep -c 'hands no doc')" 1 "payload: and blocks with no transcript at all"
check "$(lag_ "$T/lag.jsonl" 'Nothing to answer here.' | wc -c | tr -d ' ')" 0 "payload: both sources clean passes"
# the mirror: text written before the turn's last message is still read (the payload holds only
# the last one), so a payload-only gate would miss this paste block
tr_ "$T/early.jsonl" $'First, the command:\n```bash\npython3 scripts/ha.py errors 20\n```'
check "$(lag_ "$T/early.jsonl" 'Done — that printed nothing.' | grep -c 'relative path')" 1 "payload: a paste block in an earlier message of the turn still blocks"
# the closing-line check judges the payload's final message, not the transcript's stale copy
tr_ "$T/closing.jsonl" $'Here is the plan.\n\nSAM, THIS SESSION IS FINISHED.'
check "$(lag_ "$T/closing.jsonl" 'Done.' | grep -c 'closing line')" 0 "payload: a stale closing line in the transcript does not false-block"
# an earlier message that left a fence open would swallow the appended tail
tr_ "$T/fence.jsonl" $'Checking:\n```bash\nls /srv/sam'
DLF=$'- **D1 — Launch it?**\n  ➤ Answer: yes.'
check "$(lag_ "$T/fence.jsonl" "$DLF" | grep -c 'hands no doc')" 1 "payload: a transcript ending inside a fence does not swallow the tail"
# the turn's own closing line, quoted earlier in the turn, must not suppress the append
tr_ "$T/quoted.jsonl" 'The line will be: `🛑 SAM, THIS SESSION IS WAITING FOR YOU — answer D1.`'
check "$(lag_ "$T/quoted.jsonl" '🛑 SAM, THIS SESSION IS WAITING FOR YOU — answer D1.' | grep -c 'hands no doc')" 1 "payload: a tail quoted earlier in the turn is still appended"

tr_ "$T/c.jsonl" $'Quick ones, here only:\n\n- **D1 — Rename the session now?**\n  ➤ Answer: yes.\n- **D2 — Keep the old branch?**\n  ➤ Answer: no, archive it.'
check "$(sc_ "$T/c.jsonl" | grep -c 'hands no doc')" 1 "line: a chat-only D-list blocks — it needs a doc (Sam, 2026-10-04)"
check "$(sc_ "$T/c.jsonl" | grep -c 'keel line <doc>')" 1 "  naming keel line"
tr_ "$T/b3.jsonl" "$DL"$'\n\n- '"$LINE"$'\n'
check "$(sc_ "$T/b3.jsonl" | wc -c | tr -d ' ')" 0 "line: as a bullet passes"
tr_ "$T/f.jsonl" $'```text\n'"$DL"$'\n```'
check "$(sc_ "$T/f.jsonl" | wc -c | tr -d ' ')" 0 "line: a D-list inside a fence is not read"
tr_ "$T/f2.jsonl" "$DL"$'\n\n```\n'"$LINE"$'\n```'
check "$(sc_ "$T/f2.jsonl" | grep -c 'no line ends with the file link')" 1 "line: the line inside a fence does not count"
tr_ "$T/c2.jsonl" $'Still open:\n- **D2:** seed the planner fix as its own session.\n  ➤ Answer: yes'
check "$(sc_ "$T/c2.jsonl" | grep -c 'come from')" 0 "line: one shared word (planner) is not the doc's item"
check "$(sc_ "$T/c2.jsonl" | grep -c 'hands no doc')" 1 "  so it is a chat-only D-list, which owes a doc"
printf -- '- **D5 — Keep the reaper hourly.**\n  ➤ Answer: hourly, twelve hours idle.\n' > "$R/docs/new.md"
tr_ "$T/n.jsonl" $'- **D5 — Keep the reaper hourly.**\n  ➤ Answer: hourly, twelve hours idle.'
check "$(sc_ "$T/n.jsonl" | grep -c 'docs/new.md')" 1 "line: an untracked doc (written this turn) counts too"
rm "$R/docs/new.md"
tr_ "$T/d.jsonl" "$DL"$'\n\n(restated)\n'"$DL"
check "$(sc_ "$T/d.jsonl" | grep -c '"decision": "block"')" 1 "line: the list restated twice in one reply (an id seen twice) still blocks"
tr_ "$T/m.jsonl" $'- **D1 — Where the dispatcher runs.**\n  ➤ Answer: buildbox, under launchd.\n- **D7 — Rename the tab?**\n  ➤ Answer: yes\n- **D8 — Archive it?**\n  ➤ Answer: no'
check "$(sc_ "$T/m.jsonl" | grep -c '"decision": "block"')" 1 "line: one doc item among chat-only ones still owes the line"
mkdir -p "$T/elsewhere/docs"; cp "$DOC" "$T/elsewhere/docs/"
tr_ "$T/w.jsonl" "$DL"$'\n\n'"[course]($F1) | [github](https://github.com/o/r/blob/main/docs/orch-2026-10-02.md) | [space]($SPACE) — [orch-2026-10-02.md]($T/elsewhere/docs/orch-2026-10-02.md#L1)"
check "$(sc_ "$T/w.jsonl" | grep -c 'no line ends with the file link')" 1 "line: another checkout's copy does not count for the branch doc"
tr_ "$T/w2.jsonl" "$DL"$'\n\n'"[course]($F1) | [github](https://github.com/o/r/blob/main/docs/orch-2026-10-02.md) | [space]($SPACE) — $FL"
check "$(sc_ "$T/w2.jsonl" | grep -c "not this branch's read (blob) view")" 1 "line: main's blob URL is not this branch's"
WAITD="🛑 SAM, THIS SESSION IS WAITING FOR YOU — answer D1 and D2 in the doc."
tr_ "$T/wl.jsonl" $'Both are in the doc.\n\n'"$WAITD"$'\n'"$LINE"
check "$(sc_ "$T/wl.jsonl" | wc -c | tr -d ' ')" 0 "line: after a WAITING line naming D-items, the line passes (only links follow it)"
mkdir -p "$T/vault/docs"; git -C "$T/vault" init -q -b claude/p
cp "$DOC" "$T/vault/docs/p.md"; git -C "$T/vault" add -A; git -C "$T/vault" -c user.name=t -c user.email=t@t commit -q -m p
FP=$(form "$T/vault/docs/p.md")
tr_ "$T/np.jsonl" "$DL"$'\n\n'"[course]($FP) — [p.md]($T/vault/docs/p.md#L1)"
check "$(printf '{"transcript_path":"%s","stop_hook_active":false,"cwd":"%s"}' "$T/np.jsonl" "$T/vault" | python3 "$B/paste-paths" --stop-hook | wc -c | tr -d ' ')" 0 "line: a never-mirrored repo (vault, no GitHub origin) passes without space or github"
printf '# Plain digest\n\nThe open items live in the design doc.\n' > "$R/docs/plain.md"
git -C "$R" add docs && git -C "$R" -c user.name=t -c user.email=t@t commit -q -m plain
tr_ "$T/pl.jsonl" $'Digest written.\n\n'"$WAITD"$'\n'"[github](https://github.com/o/r/blob/claude/x/2026-10-02-orch/docs/plain.md) | [space]($SPACE) — [plain.md]($R/docs/plain.md#L1)"
check "$(sc_ "$T/pl.jsonl" | wc -c | tr -d ' ')" 0 "line: a doc without D-items passes without form (the line starts at github)"
tr_ "$T/pl2.jsonl" $'Digest written.\n\n'"$WAITD"$'\n'"[github](https://github.com/o/r/blob/claude/x/2026-10-02-orch/docs/plain.md) — [plain.md]($R/docs/plain.md#L1)"
check "$(sc_ "$T/pl2.jsonl" | grep -c 'the space link is missing')" 1 "  …but still owes its space"
tr_ "$T/ns.jsonl" "$DL"$'\n\n'"[course]($F1) | [github]($GH) — $FL"
check "$(printf '{"transcript_path":"%s","stop_hook_active":false,"cwd":"%s"}' "$T/ns.jsonl" "$R" | MEMO_SHEEP_BIN="" python3 "$B/paste-paths" --stop-hook | wc -c | tr -d ' ')" 0 "line: no spacesheep CLI on this Mac — no space owed"
# the line owes only what `keel line` can print (review 2026-10-09): bin/keel copied alone, so no
# bin/sheep beside it to find a key; it finds the core through the config dir's home file (lib/find_core.py)
ISO="$T/iso/bin"; mkdir -p "$ISO" "$T/iso/hooks" "$T/iso/lib"; cp "$B/keel" "$ISO/"; cp "$B/../lib/find_core.py" "$T/iso/lib/"; cp "$B/../hooks/sheep_gate.py" "$T/iso/hooks/"  # never_mirrored reads the private list
owed_() { python3 - "$ISO/keel" "$1" "$2" <<'PY'
import sys
from importlib.machinery import SourceFileLoader
print(SourceFileLoader("m", sys.argv[1]).load_module().line_plan(sys.argv[2])["owed"][sys.argv[3]])
PY
}
check "$(unset SPACESHEEP_KEY; HOME="$T" XDG_CONFIG_HOME="$T/nocfg" owed_ "$DOC" course)" "None" "line: no spacesheep key — no page, so the form is memo serve's"
check "$(unset SPACESHEEP_KEY; HOME="$T" XDG_CONFIG_HOME="$T/nocfg" CLAUDE_UNATTENDED=1 owed_ "$DOC" course)" "no SPACESHEEP_KEY — nothing can deploy the page, and an unattended run opens no local form" "  …and none in an unattended run, which opens no local form"
check "$(owed_ "$DOC" course)" "None" "  and with one, the page is owed, as the form"
check "$(CLAUDE_CODE_ENTRYPOINT=sdk-cli owed_ "$DOC" course)" "None" "line: a Remote Control session owes the form too: the page opens on the phone (2026-10-14)"
tr_ "$T/rc.jsonl" "$DL"$'\n\n'"[github]($GH) | [space]($SPACE) — $FL"
check "$(printf '{"transcript_path":"%s","stop_hook_active":false,"cwd":"%s"}' "$T/rc.jsonl" "$R" | CLAUDE_CODE_ENTRYPOINT=sdk-cli python3 "$B/paste-paths" --stop-hook | grep -c 'the course link is missing')" 1 "  so its line without one blocks"
git init -q -b main "$T/plain-main"; mkdir -p "$T/plain-main/docs"; cp "$DOC" "$T/plain-main/docs/d.md"
check "$(CLAUDE_UNATTENDED=1 owed_ "$T/plain-main/docs/d.md" course | grep -c 'uncommitted changes and no checkpoint to commit them')" "1" "line: off claude/*, an uncommitted doc owes no page (sheep refuses it, nothing commits it)"
git -C "$T/plain-main" add -A; git -C "$T/plain-main" -c user.name=t -c user.email=t@t commit -q -m d
check "$(owed_ "$T/plain-main/docs/d.md" course)" "None" "  committed, it does"
git -C "$R" remote set-url origin /tmp/not-github
tr_ "$T/l.jsonl" "$DL"$'\n\n'"[course]($F1) | [space]($SPACE) — $FL"
check "$(sc_ "$T/l.jsonl" | wc -c | tr -d ' ')" 0 "line: no GitHub origin — no github part owed"
check "$(printf '{"transcript_path":"%s","stop_hook_active":false,"cwd":"%s"}' "$T/a.jsonl" "$T" | python3 "$B/paste-paths" --stop-hook | grep -c 'come from')" 0 "line: outside a repo, no branch doc is matched"
check "$(printf '{"transcript_path":"%s","stop_hook_active":false,"cwd":"%s"}' "$T/a.jsonl" "$T" | python3 "$B/paste-paths" --stop-hook | grep -c 'hands no doc')" 1 "  but the doc itself still is owed"

# file links resolve from the VS Code window's folder (the transcript's first cwd), not the worktree
# the session entered — 2026-10-04: `docs/x.md` from a worktree → "Could not open <primary>/docs/x.md"
WT="$R/.claude/worktrees/wt"
git -C "$R" worktree add -q -b claude/x/2026-10-04-wt "$WT"
printf -- '- **D9 — Reap seeds after a fortnight.**\n  ➤ Answer: fourteen days idle.\n' > "$WT/docs/wt-only.md"
git -C "$WT" add docs && git -C "$WT" -c user.name=t -c user.email=t@t commit -q -m wt
tl_() {  # tl_ <file> <assistant text>: tr_ with the start folder $R as the first entry's cwd
  tr_ "$1" "$2"; python3 - "$1" "$R" <<'PY'
import json, sys
rows = [json.loads(l) for l in open(sys.argv[1])]
rows[0]["cwd"] = sys.argv[2]
open(sys.argv[1], "w").write("\n".join(json.dumps(r) for r in rows) + "\n")
PY
}
sw_() { printf '{"transcript_path":"%s","stop_hook_active":false,"cwd":"%s"}' "$1" "$WT" | python3 "$B/paste-paths" --stop-hook; }
tl_ "$T/v1.jsonl" $'See [the doc](docs/wt-only.md).'
check "$(sw_ "$T/v1.jsonl" | grep -c "(docs/wt-only.md) -> (/[^)]*/wt/docs/wt-only.md)")" 1 "links: a worktree-relative link blocks, naming the absolute path"
tl_ "$T/v1b.jsonl" $'See [the doc](.claude/worktrees/wt/docs/wt-only.md).'
check "$(sw_ "$T/v1b.jsonl" | grep -c "(.claude/worktrees/wt/docs/wt-only.md) -> (/[^)]*/wt/docs/wt-only.md)")" 1 "links: relative to the window's folder blocks too (Remote Control reads it from the worktree)"
tl_ "$T/v1c.jsonl" $'[a](docs/wt-only.md#L2), [b](docs/wt-only.md:2), [c](file:///etc/hosts), [d](computer:///etc/hosts)'
check "$(sw_ "$T/v1c.jsonl" | grep -c '4 file link(s).*wt-only.md#L2).*wt-only.md:2).*(file:///etc/hosts) -> (/etc/hosts)')" 1 "links: one finding for all; the line number kept; file:// and computer:// are inert"
tl_ "$T/v1pg.jsonl" $'[page](/Users/x/Downloads/eval/index.html), [p2](computer:///tmp/a.htm#top), [p3](/Users/x/r.html#L1), [ok](https://spacesheep.dev/@x/y), [mirror](http://localhost:4280/@x/y/index.html), [proto](//cdn.example.com/a.html), [doc](/etc/hosts)'
check "$(sw_ "$T/v1pg.jsonl" | grep -c '3 link(s) to a local web page.*SendUserFile.*(/Users/x/Downloads/eval/index.html); (computer:///tmp/a.htm#top); (/Users/x/r.html#L1)')" 1 "links: a local .html page blocks with the SendUserFile fix, #L1 included; a URL, //host and a plain file pass"
check "$(sw_ "$T/v1pg.jsonl" | grep -c 'file link(s) that will not open')" 0 "links: a page link is not also counted as a bad file link"
tl_ "$T/v1pt.jsonl" $'[typo](docs/nope.html)'
check "$(sw_ "$T/v1pt.jsonl" | grep -c '(docs/nope.html) -> no such file')" 1 "links: a relative .html that does not exist is a bad file link, not a page"
tl_ "$T/v1d.jsonl" $'[call](tel:+15550100), [mail](message:%3Cid%3E), [js](javascript:void(0)), [h](~/no-such-file-xyz)'
check "$(sw_ "$T/v1d.jsonl" | grep -c '1 file link(s).*(~/no-such-file-xyz) -> no such file')" 1 "links: other URI schemes pass; ~ is expanded"
tl_ "$T/v1e.jsonl" "$(printf '[x%s](docs/n%s.md) ' 1 1 2 2 3 3 4 4 5 5 6 6 7 7)"$'\n\n- **D9 — Reap seeds after a fortnight.**\n  ➤ Answer: fourteen days idle.'
check "$(sw_ "$T/v1e.jsonl" | grep -c 'hand-over line is not right.*7 file link(s)')" 1 "links: seven bad links stay one finding, after the D-list's own"
check "$(sw_ "$T/v1.jsonl" | grep -c "do not resend it: send only the lines these fixes change or add, corrected, then end with the reply.s ending")" 1 "reason: a fix asks for the changed lines and the reply's ending, not a resend"
check "$(sw_ "$T/v1e.jsonl" | grep -c 'do not resend it: ')" 1 "  any finding, not only a link (Sam, 2026-10-11: updated lines only)"
tl_ "$T/v1p.jsonl" $'Do this now:\n```bash\npython3 scripts/ha.py errors 20\n```'
check "$(sw_ "$T/v1p.jsonl" | grep -c 'and resend it: relative path in a paste block')" 1 "  a paste-block fix is resent whole: Sam copies the block at the top"
tl_ "$T/v1f.jsonl" $'Merged.\n\nrollback: git revert x\n\nSee [the doc](docs/wt-only.md).'
check "$(sw_ "$T/v1f.jsonl" | grep -c 'do not resend it: ')" 1 "  an attended report with a rollback line: the changed lines only"
check "$(CLAUDE_UNATTENDED=dispatch sw_ "$T/v1f.jsonl" | grep -c 'and resend it: ')" 1 "  in a run nobody watches, a report autofinish-run parses (rollback, Shipped:, ⚠) is resent whole: it reads only the last message"
for m in '⚠ step 4 — two open items' $'🚢 ⛵ **Shipped:** x' 'Nothing to land: the branch is empty' 'Nothing to launch: the branch is empty'; do
  tl_ "$T/v1g.jsonl" "$m"$'\n\nSee [the doc](docs/wt-only.md).'
  check "$(CLAUDE_UNATTENDED=dispatch sw_ "$T/v1g.jsonl" | grep -c 'and resend it: ')" 1 "  so is one with '${m:0:16}…'"
done
tl_ "$T/v2.jsonl" "See [the doc]($WT/docs/wt-only.md:2), [a dir]($WT/docs/), [gh](https://github.com/o/r), "$'`[x](nope.md)`.'
check "$(sw_ "$T/v2.jsonl" | wc -c | tr -d ' ')" 0 "links: absolute (with :line, a folder), a URL and a code span pass"
DW=$'- **D9 — Reap seeds after a fortnight.**\n  ➤ Answer: fourteen days idle.'
tl_ "$T/v3.jsonl" "$DW"$'\n\n[wt-only](docs/wt-only.md)'
check "$(sw_ "$T/v3.jsonl" | grep -c 'no line ends with the file link')" 1 "links: a D-list's doc linked relative is not its file link"
FW=$(form "$WT/docs/wt-only.md")
tl_ "$T/v4.jsonl" "$DW"$'\n\n'"[course]($FW) | [space]($SPACE) — [wt-only.md]($WT/docs/wt-only.md#L1)"
check "$(sw_ "$T/v4.jsonl" | wc -c | tr -d ' ')" 0 "links: the same doc's line, linked absolute, satisfies the check"
check "$(printf '{"transcript_path":"%s","stop_hook_active":false,"cwd":"%s"}' "$T/b.jsonl" "$R" | python3 "$B/paste-paths" --stop-hook | wc -c | tr -d ' ')" 0 "links: no cwd recorded in the transcript — the old rule"

# closing lines (orchestration proposal step 10, A1/A2): fixed, last, and owed by a /finish that launched
tf_() {  # tf_ <file> <prompt> <bash command> <reply> [mid]: a human prompt, a skill body, one Bash call,
         # [a background task's notification], an earlier message with an unclosed fence, the reply
  python3 - "$@" <<'PY'
import json, sys
f, prompt, cmd, text = sys.argv[1:5]
rows = [{"type": "user", "message": {"content": "<command-message>finish</command-message>\n<command-name>/finish</command-name>"}},
        {"type": "assistant", "message": {"content": [{"type": "tool_use", "id": "0", "name": "Bash", "input": {"command": "touch .git/claude/finishing"}}]}},
        {"type": "user", "message": {"content": "an earlier turn"}, "origin": {"kind": "human"}},
        {"type": "user", "message": {"content": prompt}, "origin": {"kind": "human"}},
        {"type": "user", "isMeta": True, "message": {"content": [{"type": "text", "text": "Base directory for this skill: …"}]}},
        {"type": "assistant", "message": {"content": [{"type": "tool_use", "id": "1", "name": "Bash", "input": {"command": cmd}}]}},
        {"type": "user", "message": {"content": [{"type": "tool_result", "tool_use_id": "1"}]}}]
flags = sys.argv[5:]
if "bg" in flags:
    rows.append({"type": "assistant", "message": {"content": [{"type": "tool_use", "id": "2", "name": "Bash",
                 "input": {"command": "bash check.sh", "run_in_background": True}}]}})
if "skill" in flags:
    rows.append({"type": "assistant", "message": {"content": [{"type": "tool_use", "id": "3", "name": "Skill",
                 "input": {"skill": "finish"}}]}})
if "mid" in flags:
    rows.append({"type": "user", "message": {"content": "<task-notification>done</task-notification>"},
                 "origin": {"kind": "task-notification"}})
rows += [{"type": "assistant", "message": {"content": [{"type": "text", "text": "Checking:\n```bash\nls"}]}},
         {"type": "user", "isMeta": True, "message": {"content": "Stop hook feedback: …"}},
         {"type": "assistant", "message": {"content": [{"type": "text", "text": text}]}}]
open(f, "w").write("\n".join(json.dumps(r) for r in rows) + "\n")
PY
}
FIN='<command-message>finish</command-message>
<command-name>/finish</command-name>'
EVAC=$'<command-message>evacuate</command-message>\n<command-name>/evacuate</command-name>'
DONE="✅ SAM, IT'S FINE — THIS SESSION IS REALLY DONE. YOU HAVEN'T FORGOTTEN ANYTHING."
WAIT="🛑 SAM, THIS SESSION IS WAITING FOR YOU — pick option A or B."
blocks() { sh_ "$1" | grep -c "$2"; }
quiet() { sh_ "$1" | wc -c | tr -d ' '; }
tf_ "$T/k1.jsonl" "$FIN" 'touch "$(git rev-parse --git-dir)/claude/finishing"' $'Merged.\n\n🚢 ⛵ 🛶 **Shipped:** x'
check "$(blocks "$T/k1.jsonl" 'ends with one of its closing lines')" 1 "closing: a /finish that launched and ended on ship emoji blocks"
check "$(sh_ "$T/k1.jsonl" true | wc -c | tr -d ' ')" 0 "  but never twice (stop_hook_active)"
check "$(blocks "$T/k1.jsonl" 'WAITING FOR YOU')" 1 "  and the reason offers the WAITING line too"
tf_ "$T/k1m.jsonl" "$FIN" 'git status' $'Merged.\n\n🚢 ⛵ **Shipped:** x' mid
check "$(blocks "$T/k1m.jsonl" 'ends with one of its closing lines')" 1 "closing: a background task's notification mid-turn does not hide the /finish"
tf_ "$T/k1p.jsonl" "Looks right — /finish" 'git status' $'Merged.\n\n🚢 ⛵ **Shipped:** x'
check "$(blocks "$T/k1p.jsonl" 'ends with one of its closing lines')" 1 "closing: a /finish asked inside a plain prompt counts"
tf_ "$T/k1g.jsonl" "go" 'touch "$(git rev-parse --git-dir)/claude/finishing"' $'Merged. Nothing else.'
check "$(blocks "$T/k1g.jsonl" 'ends with one of its closing lines')" 1 "closing: a continued 'go' turn that touched the marker owes the line"
tf_ "$T/k1n.jsonl" "do step 10" 'grep -rn x/claude/finishing hooks' $'The suite is still running.'
check "$(quiet "$T/k1n.jsonl")" 0 "closing: a command that only mentions the marker owes nothing"
tf_ "$T/k1d.jsonl" "do not /finish yet, what does Shipped: mean" 'ls' $'Shipped: is the label.'
check "$(quiet "$T/k1d.jsonl")" 0 "closing: /finish mentioned mid-prompt is not a /finish"
tf_ "$T/k1s.jsonl" "wrap it up" 'ls' $'Merged.\n\n🚢 ⛵ **Shipped:** x' skill
check "$(blocks "$T/k1s.jsonl" 'ends with one of its closing lines')" 1 "closing: a /finish run through the Skill tool counts"
tf_ "$T/k1b.jsonl" "$FIN" 'touch "$(git rev-parse --git-dir)/claude/finishing"' $'Step 10.\n\nWaiting for the reviewer in the background.' bg
check "$(quiet "$T/k1b.jsonl")" 0 "closing: a stop waiting on its own background task owes nothing yet"
tf_ "$T/k2t.jsonl" "$FIN" 'git status' $'**Shipped:** x\n\n`✅ SAM, IT’S FINE — THIS SESSION IS REALLY DONE. YOU HAVEN’T FORGOTTEN ANYTHING.`'
check "$(quiet "$T/k2t.jsonl")" 0 "closing: the line in backticks, typographic apostrophes, passes"
tf_ "$T/k2.jsonl" "$FIN" 'git status' $'⛵ 🚢 **Shipped:** x\n\n'"**$DONE**"
check "$(quiet "$T/k2.jsonl")" 0 "closing: the fixed line last, in bold, passes (an unclosed fence earlier in the turn is not read)"
tf_ "$T/k3.jsonl" "$FIN" 'git status' $'⚠ open items: TODO.md has 2. Stopping before Phase 2.'
check "$(quiet "$T/k3.jsonl")" 0 "closing: a Phase 1 stop (no marker, nothing shipped) owes no line"
tf_ "$T/k4.jsonl" "$FIN" 'git status' "$DONE"$'\nHOUSEHOLD: SCHEDULE — FINISHED. Shipped: the schedule.'
check "$(blocks "$T/k4.jsonl" 'only links may follow it')" 1 "closing: a line improvised after the fixed one blocks"
tf_ "$T/k4f.jsonl" "plain" 'ls' "$DONE"$'\n```bash\nrm -rf /x\n```'
check "$(blocks "$T/k4f.jsonl" 'only links may follow it')" 1 "closing: a code block after the fixed line blocks"
tf_ "$T/k4l.jsonl" "plain" 'ls' $'D1 above.\n\n'"$WAIT"$'\n[docs/m.md](/x/docs/m.md) · answer: https://github.com/o/r/edit/b/docs/m.md'
check "$(quiet "$T/k4l.jsonl")" 0 "closing: the memo's links after the WAITING line pass"
tf_ "$T/k5.jsonl" "plain prompt" 'ls' $'Here is the plan.\n\nSAM, THIS SESSION IS FINISHED.'
check "$(blocks "$T/k5.jsonl" 'not one of the fixed closing lines')" 1 "closing: an attempt not in the table blocks, any turn"
tf_ "$T/k5c.jsonl" "plain prompt" 'ls' $'The preview reads:\n\nSAM, THE CAT IS STILL OUTSIDE.'
check "$(quiet "$T/k5c.jsonl")" 0 "closing: other upper-case SAM copy is not an attempt"
tf_ "$T/k5q.jsonl" "plain prompt" 'ls' $'The two lines:\n- `'"$DONE"$'`\n- the other\nWant the WAITING one too?'
check "$(quiet "$T/k5q.jsonl")" 0 "closing: a line quoted in a bullet is not said"
tf_ "$T/k6.jsonl" "plain prompt" 'ls' $'Two options above.\n\n'"$WAIT"
check "$(quiet "$T/k6.jsonl")" 0 "closing: the WAITING line with its ask passes"
WD="🛑 SAM, THIS SESSION IS WAITING FOR YOU — answer D1–D4."
tf_ "$T/kq1.jsonl" "plain prompt" 'ls' $'All four are above.\n\n'"$WD"
check "$(blocks "$T/kq1.jsonl" 'hands no doc')" 1 "D-list doc: a WAITING line naming D-items with no doc blocks (2026-10-04)"
mkdir -p "$T/loose"; printf -- '- **D1 — Loose?** Body.\n  ➤ Answer:\n' > "$T/loose/x-2026-10-04.md"
FX=$(form "$T/loose/x-2026-10-04.md")
tf_ "$T/kq2.jsonl" "plain prompt" 'ls' $'Still open.\n\n'"$WD"$'\n'"[course]($FX) — [x-2026-10-04.md]($T/loose/x-2026-10-04.md#L1)"
check "$(quiet "$T/kq2.jsonl")" 0 "  with the doc's line after it (outside git: form and file only): passes"
tf_ "$T/kq2b.jsonl" "plain prompt" 'ls' $'Still open.\n\n'"$WD"$'\n[docs/x-2026-10-04.md]('"$T/loose/x-2026-10-04.md)"
check "$(blocks "$T/kq2b.jsonl" 'hand-over line is not right')" 1 "  the doc linked bare, without its line: blocks"
tf_ "$T/kq3.jsonl" "plain prompt" 'ls' $'Open: http://127.0.0.1:8765/k3x9/\n\n'"$WD"
check "$(blocks "$T/kq3.jsonl" 'hands no doc')" 1 "  the form's URL alone hands no doc (since 2026-10-07)"
tf_ "$T/kq4.jsonl" "plain prompt" 'ls' $'D3 is done: the flag launched.\n\n'"$WAIT"
check "$(quiet "$T/kq4.jsonl")" 0 "  a D-item named in prose, WAITING line without one: passes"
tf_ "$T/kq5.jsonl" "plain prompt" 'ls' $'All four above.\n\n'"$WD"$'\n\nThey are in the list above.'
check "$(blocks "$T/kq5.jsonl" 'hands no doc')" 1 "  a WAITING line naming D-items that is not last still owes the doc"
check "$(blocks "$T/kq5.jsonl" 'only links may follow it')" 1 "  in the same block as the closing-line finding"
tf_ "$T/kq6.jsonl" "plain prompt" 'ls' $'Built.\n\n🛑 SAM, THIS SESSION IS WAITING FOR YOU — say go once the week resets (per D23).'
check "$(quiet "$T/kq6.jsonl")" 0 "  a D-number cited in parentheses is not an ask"
mkdir -p "$T/My Docs"; printf '# Spaced\n' > "$T/My Docs/a.md"
tf_ "$T/kq7.jsonl" "plain prompt" 'ls' $'Open.\n\n'"$WD"$'\n'"[a.md](<$T/My Docs/a.md#L1>)"
check "$(quiet "$T/kq7.jsonl")" 0 "  an angle-bracket file link (a path with a space): the line of a doc without D-items outside git"
tf_ "$T/kq8.jsonl" "plain prompt" 'ls' $'See http://localhost:8123/config\n\n'"$WD"
check "$(blocks "$T/kq8.jsonl" 'hands no doc')" 1 "  a dev-server URL is not the memo form"
tf_ "$T/kg1.jsonl" "plain prompt" 'ls' $'Stopped: regatta is not on main.\n\n🛑 SAM, THIS SESSION IS WAITING FOR YOU — SAY `go` ONCE REGATTA (#100) HAS MERGED, AND THE CHARTS BUILD STARTS.'
check "$(blocks "$T/kg1.jsonl" 'wait on it yourself')" 1 "say-go: a WAITING line asking for go once a PR merges blocks (2026-10-04)"
tf_ "$T/kg2.jsonl" "plain prompt" 'ls' $'Built.\n\n🛑 SAM, THIS SESSION IS WAITING FOR YOU — type continue when the deploy finishes.'
check "$(blocks "$T/kg2.jsonl" 'wait on it yourself')" 1 "  type continue when a deploy finishes blocks too"
tf_ "$T/kg3.jsonl" "plain prompt" 'ls' $'Built.\n\n🛑 SAM, THIS SESSION IS WAITING FOR YOU — say go to merge it.'
check "$(quiet "$T/kg3.jsonl")" 0 "  a go that is Sam's approval, with no event to wait on, passes"
tf_ "$T/kg4.jsonl" "plain prompt" 'ls' $'Built.\n\n🛑 SAM, THIS SESSION IS WAITING FOR YOU — the check passed; say go to merge.'
check "$(quiet "$T/kg4.jsonl")" 0 "  an approval go beside a finished fact passes"
tf_ "$T/kg5.jsonl" "plain prompt" 'ls' $'Built.\n\n🛑 SAM, THIS SESSION IS WAITING FOR YOU — merge regatta (#100); no need to say go once it has merged, this session polls it.'
check "$(quiet "$T/kg5.jsonl")" 0 "  a negated go-ask passes"
tf_ "$T/kg6.jsonl" "plain prompt" 'ls' $'Built.\n\n🛑 SAM, THIS SESSION IS WAITING FOR YOU — say go once the week passes.'
check "$(quiet "$T/kg6.jsonl")" 0 "  a wait on time passes"
tf_ "$T/kg7.jsonl" "plain prompt" 'ls' $'Built.\n\n🛑 SAM, THIS SESSION IS WAITING FOR YOU — say **`go`** once CI is green.'
check "$(blocks "$T/kg7.jsonl" 'wait on it yourself')" 1 "  bold-and-backticked go once CI is green blocks"
tf_ "$T/kg8.jsonl" "plain prompt" 'ls' $'Built.\n\n🛑 SAM, THIS SESSION IS WAITING FOR YOU — run `/finish` to launch it, then say go once #100 has merged.'
check "$(blocks "$T/kg8.jsonl" 'wait on it yourself')" 1 "  with a command in it: the go finding…"
check "$(blocks "$T/kg8.jsonl" 'Do this now')" 1 "  …and the Do-this-now one, in one block"
tf_ "$T/kg9.jsonl" "plain prompt" 'ls' $'Built.\n\n🛑 SAM, THIS SESSION IS WAITING FOR YOU — say go once #100 merges.\n\nThe charts build follows.'
check "$(blocks "$T/kg9.jsonl" 'wait on it yourself')" 1 "  a WAITING line that is not last is still read for the go"
# rename S4: /finish's text says launch, so the event takes it beside land (the review, 2026-10-19)
tf_ "$T/kg10.jsonl" "plain prompt" 'ls' $'Built.\n\n🛑 SAM, THIS SESSION IS WAITING FOR YOU — say go once it lands.'   # the old word, not launch: a guard
check "$(blocks "$T/kg10.jsonl" 'wait on it yourself')" 1 "  go once it lands blocks (the old word; launch is the new one)"
tf_ "$T/kg11.jsonl" "plain prompt" 'ls' $'Built.\n\n🛑 SAM, THIS SESSION IS WAITING FOR YOU — say go once it launches.'
check "$(blocks "$T/kg11.jsonl" 'wait on it yourself')" 1 "  go once it launches blocks (the new word)"
tf_ "$T/k7.jsonl" "plain prompt" 'ls' $'Two options above.\n\n🛑 SAM, THIS SESSION IS WAITING FOR YOU — '
check "$(blocks "$T/k7.jsonl" 'not one of the fixed closing lines')" 1 "closing: the WAITING line without its ask blocks"
echo "the two waits (2026-10-20): WAITING FOR YOU asks, WAITING FOR SOMETHING says there is nothing to do"
tf_ "$T/kw1.jsonl" "plain prompt" 'ls' $'Reviewers started.\n\n⏳ SAM, THIS SESSION IS WAITING FOR SOMETHING — the two reviewers; it continues by itself.'
check "$(quiet "$T/kw1.jsonl")" 0 "  WAITING FOR SOMETHING on its own work passes"
tf_ "$T/kw2.jsonl" "plain prompt" 'ls' $'Built.\n\n🛑 SAM, THIS SESSION IS WAITING FOR YOU — nothing to do yet; the reviewers are running.'
check "$(blocks "$T/kw2.jsonl" 'end on `[^`]*SAM, THIS SESSION IS WAITING FOR SOMETHING')" 1 "  WAITING FOR YOU saying nothing to do blocks, naming the other line"
tf_ "$T/kw3.jsonl" "plain prompt" 'ls' $'Built.\n\n🛑 SAM, THIS SESSION IS WAITING FOR YOU — nothing to do but approve the merge.'
check "$(quiet "$T/kw3.jsonl")" 0 "  …unless it still asks (a D-item, a step)"
for l in "the reviewers, then pick A or B in D2" "the check; then log in to gh" "say go once you have looked" "the reviewers, then your pick in D2's doc"; do
  tf_ "$T/kw4.jsonl" "plain prompt" 'ls' $'Built.\n\n⏳ SAM, THIS SESSION IS WAITING FOR SOMETHING — '"$l"
  check "$(blocks "$T/kw4.jsonl" 'end on `[^`]*SAM, THIS SESSION IS WAITING FOR YOU')" 1 "  WAITING FOR SOMETHING that asks ('$l') blocks"
done
tf_ "$T/kw4h.jsonl" "plain prompt" 'ls' $'Built.\n\n⏳ SAM, THIS SESSION IS WAITING FOR SOMETHING — autofinish-run, once you approve D3'
check "$(blocks "$T/kw4h.jsonl" 'end on `[^`]*SAM, THIS SESSION IS WAITING FOR YOU')" 1 "  a hand-over line that asks (D3) blocks as a pending one does"
tf_ "$T/kw5.jsonl" "plain prompt" 'ls' $'Built.\n\n⏳ SAM, THIS SESSION IS WAITING FOR SOMETHING — the PR to merge, polled here (per D6).'
check "$(quiet "$T/kw5.jsonl")" 0 "  a D-number cited in parentheses is no ask here either"
for l in "keel's suite (paste-paths.sh) to pass" "the review of D3's build" "the login probe on the other Mac" "the reviewers' approval verdicts" "CI's approval of PR 41" "the gh login check" "the review of the D2 doc"; do
  tf_ "$T/kw6.jsonl" "plain prompt" 'ls' $'Built.\n\n⏳ SAM, THIS SESSION IS WAITING FOR SOMETHING — '"$l"
  check "$(quiet "$T/kw6.jsonl")" 0 "  a name ('$l') is no ask (code review, 2026-10-20)"
done
# dispatch-queue S3: the queue's closing line, as dispatch prints it — the pending kind, no ask (its cap
# words are ASK_EXEMPT_RE's), and the branch name and its priority read as names, never a pick
tf_ "$T/kwq.jsonl" "plain prompt" 'ls' $'Queued (dispatch: queued as fleet:regatta--queue-s4 (normal), rank 2).\n\n⏳ SAM, THIS SESSION IS WAITING FOR SOMETHING — queued claude/laptop/2026-10-27-queue-s4 (normal); the next step waits for a run to end; the skipper finishes it'
check "$(quiet "$T/kwq.jsonl")" 0 "  the queue's closing line passes the Stop lint (dispatch-queue S3)"
check "$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import common; print(common.ending(sys.argv[2])[0])' "$B/../../regatta/hooks" \
  "⏳ SAM, THIS SESSION IS WAITING FOR SOMETHING — queued claude/laptop/2026-10-27-queue-s4 (high); the next step waits for a run to end; the skipper finishes it")" \
  "pending" "  …read as the pending kind (dispatch-rc's said_its_end: no end; the run ends by its hand-off)"
tf_ "$T/kw7.jsonl" "plain prompt" 'ls' $'Two options above.\n\n🛑 SAM, THIS SESSION IS WAITING FOR YOU — nothing to do but pick option A or B.'
check "$(quiet "$T/kw7.jsonl")" 0 "  'nothing to do but <an ask>' stays WAITING FOR YOU"
echo "the third wait (2026-10-29): WAITING FOR NOTHING closes a plain answer; WAITING FOR YOU with nothing owed blocks"
tf_ "$T/kn1.jsonl" "plain prompt" 'ls' $'It reads the config dir first.\n\n✅ SAM, THIS SESSION IS WAITING FOR NOTHING — the answer is above.'
check "$(quiet "$T/kn1.jsonl")" 0 "  WAITING FOR NOTHING on a plain answer passes ('the answer' is a noun, no ask)"
for l in "nothing owed; the answer is above" "nothing is owed" "nothing left to do" "no action needed" "nothing is asked"; do
  tf_ "$T/kn2.jsonl" "plain prompt" 'ls' $'It reads the config dir first.\n\n🛑 SAM, THIS SESSION IS WAITING FOR YOU — '"$l"
  check "$(blocks "$T/kn2.jsonl" 'ends on `[^`]*SAM, THIS SESSION IS WAITING FOR NOTHING')" 1 "  WAITING FOR YOU saying '$l' blocks, naming WAITING FOR NOTHING"
done
for l in "nothing owed but D2" "nothing owed, then approve the merge" "nothing left until you pick A or B"; do
  tf_ "$T/kn3.jsonl" "plain prompt" 'ls' $'Built.\n\n🛑 SAM, THIS SESSION IS WAITING FOR YOU — '"$l"
  check "$(blocks "$T/kn3.jsonl" 'WAITING FOR NOTHING')" 0 "  …unless a qualifier keeps the ask ('$l')"
done
tf_ "$T/kn4.jsonl" "plain prompt" 'ls' $'Built.\n\n🛑 SAM, THIS SESSION IS WAITING FOR YOU — nothing to do yet; the reviewers are running.'
check "$(blocks "$T/kn4.jsonl" 'or on `[^`]*SAM, THIS SESSION IS WAITING FOR NOTHING')" 1 "  the nothing-to-do block names WAITING FOR NOTHING beside WAITING FOR SOMETHING"
for l in "answered; pick A or B next" "say go once you have read it" "log in to gh, then nothing" "D2 and D3 are open in the doc" \
         "log into gh, then nothing" "\`/finish\` when you like" "merge the PR when you are happy" "copy the token to the vault"; do
  tf_ "$T/kn5.jsonl" "plain prompt" 'ls' $'Built.\n\n✅ SAM, THIS SESSION IS WAITING FOR NOTHING — '"$l"
  check "$(blocks "$T/kn5.jsonl" 'end on `[^`]*SAM, THIS SESSION IS WAITING FOR YOU')" 1 "  WAITING FOR NOTHING that asks ('$l') blocks"
done
tf_ "$T/kn7.jsonl" "plain prompt" 'ls' $'## Do this now\n\n```\nopen https://x\n```\n\nBuilt.\n\n✅ SAM, THIS SESSION IS WAITING FOR NOTHING — the answer is above.'
check "$(blocks "$T/kn7.jsonl" 'Do this now block or a')" 1 "  WAITING FOR NOTHING under a Do this now block blocks (finish review, 2026-10-30)"
for l in "nothing pending; merge the PR when you are happy" "nothing required; the PR waits for your merge" "nothing needed beyond the pick between A and B"; do
  tf_ "$T/kn8.jsonl" "plain prompt" 'ls' $'Built.\n\n🛑 SAM, THIS SESSION IS WAITING FOR YOU — '"$l"
  check "$(blocks "$T/kn8.jsonl" 'WAITING FOR NOTHING')" 0 "  WAITING FOR YOU '$l' stays an ask: the ask after the nothing phrase wins (finish review, 2026-10-30)"
done
tf_ "$T/kn6.jsonl" "plain prompt" 'ls' $'Built.\n\n✅ SAM, THIS SESSION IS WAITING FOR NOTHING — '
check "$(blocks "$T/kn6.jsonl" 'not one of the fixed closing lines')" 1 "  WAITING FOR NOTHING without its what blocks"
echo "the marks (2026-10-29): ✅ closeable, ⏳ work goes on, 🛑 the owner owes the next move"
tf_ "$T/km1.jsonl" "plain prompt" 'ls' $'Built.\n\nSAM, THIS SESSION IS WAITING FOR YOU — pick A or B.'
check "$(blocks "$T/km1.jsonl" 'the closing line has no mark')" 1 "  a closing line with no mark blocks"
check "$(sh_ "$T/km1.jsonl" | python3 -c 'import json,sys; print("start it with \U0001F6D1" in json.load(sys.stdin)["reason"])')" "True" "  …naming its kind's mark (🛑 for WAITING FOR YOU)"
tf_ "$T/km2.jsonl" "plain prompt" 'ls' $'Reviewers started.\n\n✅ SAM, THIS SESSION IS WAITING FOR SOMETHING — the two reviewers.'
check "$(blocks "$T/km2.jsonl" 'the closing line opens with')" 1 "  a wrong mark (✅ on WAITING FOR SOMETHING) blocks"
tf_ "$T/km3.jsonl" "plain prompt" 'ls' $'It reads the config dir.\n\n🟢 SAM, THIS SESSION IS WAITING FOR NOTHING — the answer is above.'
check "$(blocks "$T/km3.jsonl" 'the closing line opens with')" 1 "  a mark outside the table (🟢) blocks"
tf_ "$T/km4.jsonl" "plain prompt" 'ls' $'Reviewers started.\n\n**⏳️ SAM, THIS SESSION IS WAITING FOR SOMETHING — the two reviewers.**'
check "$(quiet "$T/km4.jsonl")" 0 "  the right mark passes, inside bold and with U+FE0F after it"
tf_ "$T/km5.jsonl" "plain prompt" 'ls' $'Done.\n\n⏳ RELAYED TO coding-7 — D1, the cadence'
check "$(quiet "$T/km5.jsonl")" 0 "  the RELAYED line takes ⏳"
tf_ "$T/km6.jsonl" "plain prompt" 'ls' $'Built.\n\n🛑SAM, THIS SESSION IS WAITING FOR YOU — pick A or B.'
check "$(blocks "$T/km6.jsonl" 'has no space after its mark')" 1 "  a mark with no space after it blocks, named (it read as no closing line before)"
tf_ "$T/km7.jsonl" "plain prompt" 'ls' $'Moved.\n\n✅ SAM, THIS SESSION MOVED TO buildbox — CLOSE THIS TAB. THE WORK CONTINUES THERE ONCE YOU START IT: claude --resume x'
check "$(blocks "$T/km7.jsonl" 'the closing line opens with')" 1 "  a move that leaves the owner a step wants 🛑, not ✅"
echo "the landing review (2026-10-29): what stays where"
for l in "nothing needed from you" "your question is answered above" "the cadence is settled (D2)"; do
  tf_ "$T/kr1.jsonl" "plain prompt" 'ls' $'It reads the config dir.\n\n✅ SAM, THIS SESSION IS WAITING FOR NOTHING — '"$l"
  check "$(quiet "$T/kr1.jsonl")" 0 "  WAITING FOR NOTHING '$l' passes: 'you' is no ask there, a cited D-item none"
done
for l in "the pick between A and B; nothing else needed" "merge the PR; nothing else needed"; do
  tf_ "$T/kr2.jsonl" "plain prompt" 'ls' $'Built.\n\n🛑 SAM, THIS SESSION IS WAITING FOR YOU — '"$l"
  check "$(quiet "$T/kr2.jsonl")" 0 "  WAITING FOR YOU '$l' stays an ask, as on main (the nothing phrase must open the what)"
done
tf_ "$T/kr3.jsonl" "plain prompt" 'ls' $'Built.\n\n🛑 SAM, THIS SESSION IS WAITING FOR YOU — nothing needed from you'
check "$(blocks "$T/kr3.jsonl" 'ends on `[^`]*SAM, THIS SESSION IS WAITING FOR NOTHING')" 1 "  WAITING FOR YOU 'nothing needed from you' takes WAITING FOR NOTHING"
tf_ "$T/kr4.jsonl" "plain prompt" 'ls' $'Built.\n\n**🛑** SAM, THIS SESSION IS WAITING FOR YOU — pick A or B.'
check "$(quiet "$T/kr4.jsonl")" 0 "  a mark in its own bold, then a space, passes"
check "$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import common; print(common.ending("x\n\n\U0001F6D1 " + common.WAITING_PREFIX + "pick A")[1] == common.WAITING_PREFIX + "pick A")' "$B/../../regatta/hooks")" "True" \
  "  ending() hands back the line without its mark, so every reader compares as before"
WF="🛑 SAM, THIS SESSION IS WAITING FOR YOU — \`/finish\` to launch it, then look at the list."
tf_ "$T/kd1.jsonl" "go" 'ls' $'Built and checked.\n\n'"$WF"
check "$(blocks "$T/kd1.jsonl" 'put it in a \*\*Do this now\*\* block')" 1 "do this now: a WAITING line naming /finish without the block blocks (2026-10-04)"
tf_ "$T/kd2.jsonl" "go" 'ls' $'**Do this now**\n```\n/finish\n```\n\nBuilt and checked.\n\n'"$WF"
check "$(quiet "$T/kd2.jsonl")" 0 "  with the block at the top: passes"
tf_ "$T/kd3.jsonl" "go" 'ls' $'**Do this now**\n```\n/rename layer: x\n```\n\nBuilt.\n\n'"$WF"
check "$(blocks "$T/kd3.jsonl" '`/finish`')" 1 "  a block holding another command does not count"
tf_ "$T/ke1.jsonl" "$FIN" 'git status' $'⚠ step 4 — one open item.\n\n'"$WAIT"
check "$(blocks "$T/ke1.jsonl" 'finishes it from outside')" 1 "external finish: a /finish stopped on a ⚠ gate without the launcher's line blocks (2026-10-11)"
tf_ "$T/ke2.jsonl" "$FIN" 'git status' $'**Do this now**\n```\n/Users/x/projects/layer/bin/autofinish-run /Users/x/projects/r/.claude/worktrees/t\n```\n\n⚠ step 4 — one open item.\n\n'"$WAIT"
check "$(quiet "$T/ke2.jsonl")" 0 "  with the line in the block at the top: passes"
tf_ "$T/ke3.jsonl" "go" 'ls' $'⚠ step 4 — the deploy needs a hand.\n\n'"$WAIT"
check "$(blocks "$T/ke3.jsonl" 'finishes it from outside')" 0 "  a turn that is no /finish is not asked for it"
tf_ "$T/ke3n.jsonl" "go" 'ls' $'⚠ step 4 — one open item before it is launched.\n\n'"$WAIT"
check "$(blocks "$T/ke3n.jsonl" 'finishes it from outside')" 1 "  one whose text says launched (skills/finish's word since rename S4) is"
tf_ "$T/ke3o.jsonl" "go" 'ls' $'⚠ step 4 — one open item before it is landed.\n\n'"$WAIT"   # the old word, not launched: a guard
check "$(blocks "$T/ke3o.jsonl" 'finishes it from outside')" 1 "  and so is one that says landed, the word before launched"
tf_ "$T/ke4.jsonl" "$FIN" 'ls' $'> ⚠ 2 open items before this branch can be finished:\n> 1. x\n\n'"$WAIT"
check "$(blocks "$T/ke4.jsonl" 'finishes it from outside')" 1 "  the attended wording (⚠ N open items) counts too"
tf_ "$T/ke5.jsonl" "drop item 2, go" 'ls' $'⚠ Step 4 — one more open item before this branch can be finished.\n\n'"$WAIT"
check "$(blocks "$T/ke5.jsonl" 'finishes it from outside')" 1 "  a continued /finish turn (no /finish prompt) counts"
tf_ "$T/ke6.jsonl" "$FIN" 'ls' $'⚠ step 4 — one open item.\n\n'"$WAIT"$'\n\nI will wait.'
check "$(blocks "$T/ke6.jsonl" 'finishes it from outside')" 1 "  said at once when the WAITING line is not last (the hook blocks once)"
tf_ "$T/ke7.jsonl" "$FIN" 'ls' $'**Do this now**\n```\n/Users/x/projects/layer/bin/autofinish-run \'/Users/x/My Drive/r/.claude/worktrees/t\'\n```\n\n⚠ step 4 — one open item.\n\n'"$WAIT"
check "$(quiet "$T/ke7.jsonl")" 0 "  a quoted worktree path passes"
tf_ "$T/kd4.jsonl" "go" 'ls' $'Done.\n\n🛑 SAM, THIS SESSION IS WAITING FOR YOU — on laptop: `/move --to-home`.'
check "$(blocks "$T/kd4.jsonl" '`/move`')" 1 "  an unblock command (/move) counts the same"
tf_ "$T/kd5.jsonl" "go" 'ls' $'Doc above.\n\n🛑 SAM, THIS SESSION IS WAITING FOR YOU — read ~/projects/x/docs/a.md and answer D1 and/or D2 at https://github.com/o/r.'$'\n[docs/a.md](/Users/x/docs/a.md)'
check "$(blocks "$T/kd5.jsonl" 'Do this now')" 0 "  paths, and/or and URLs are not commands"
tf_ "$T/kd6.jsonl" "go" 'ls' $'**Do this now**\n```\n/finish\n```\n\nBuilt.\n\n🛑 SAM, THIS SESSION IS WAITING FOR YOU — run /finish: it launches it; logs are in /tmp.'
check "$(quiet "$T/kd6.jsonl")" 0 "  a colon after the command, and a root path like /tmp: still the block's /finish, no false block"
tf_ "$T/k8.jsonl" "$EVAC" 'ls' $'Verdict: CLOSE.\n\n'"$WAIT"
check "$(quiet "$T/k8.jsonl")" 0 "closing: /evacuate may end on the WAITING line"
tf_ "$T/k9.jsonl" "$EVAC" 'ls' $'Verdict: CLOSE. Nothing owed.'
check "$(blocks "$T/k9.jsonl" '/evacuate ends with one of its closing lines')" 1 "closing: /evacuate without a closing line blocks"
tf_ "$T/k9o.jsonl" "$EVAC" 'ls' $'Verdict: **LEAVE OPEN** — the probe context.'
check "$(quiet "$T/k9o.jsonl")" 0 "closing: /evacuate's LEAVE OPEN owes none"
tf_ "$T/k10.jsonl" "plain prompt" 'ls' $'The lines are:\n```text\nSAM, THIS SESSION IS FINISHED.\n```'
check "$(quiet "$T/k10.jsonl")" 0 "closing: a line inside a fence is not read"

# a finished step starts the next one itself (Sam, 2026-10-04): no session handed over to paste
# where dispatch would take the branch — a workflow repo whose contract says `physical: none`
mkdir -p "$R/.claude"; echo '{"checkpoint": true}' > "$R/.claude/workflow.json"; printf -- '- physical: none\n' > "$R/AGENTS.md"
P2="$T/phys"; git -C "$T" init -q -b main phys; mkdir -p "$P2/.claude"; echo '{"checkpoint": true}' > "$P2/.claude/workflow.json"
printf -- '- physical: python3 scripts/test.py --physical\n' > "$P2/AGENTS.md"
sx_() { printf '{"transcript_path":"%s","stop_hook_active":%s,"cwd":"%s"}' "$1" "${3:-false}" "$2" | python3 "$B/paste-paths" --stop-hook; }
WP="🛑 SAM, THIS SESSION IS WAITING FOR YOU — start step 3: \`/pickup 'claude/x/2026-10-04-s3' --fresh\`."
tf_ "$T/h1.jsonl" "go" 'ls' $'Step 2 built.\n\n'"$WP"
check "$(sx_ "$T/h1.jsonl" "$R" | grep -c "hands Sam a session to start.*dispatch '<branch>' --next")" 1 "handoff: a /pickup --fresh for Sam to run blocks, naming dispatch"
check "$(sx_ "$T/h1.jsonl" "$R" | grep -c 'Do this now')" 0 "  instead of asking for a Do-this-now block"
check "$(sx_ "$T/h1.jsonl" "$R" true | wc -c | tr -d ' ')" 0 "  but never twice (stop_hook_active)"
tf_ "$T/h2.jsonl" "go" 'ls' $'Step 2 built. Paste this into a fresh session:\n```text\nBuild step 3 of the model gate.\n```'
check "$(sx_ "$T/h2.jsonl" "$R" | grep -c 'hands Sam a session to start')" 1 "handoff: a prompt to paste into a fresh session blocks"
tf_ "$T/h2b.jsonl" "go" 'ls' $'Step 2 built; the next step\'s exact prompt is in the doc.'
check "$(sx_ "$T/h2b.jsonl" "$R" | grep -c 'hands Sam a session to start')" 1 "handoff: \"the next step's exact prompt\" blocks"
tf_ "$T/h3.jsonl" "go" 'bash ~/projects/layer/bin/dispatch claude/x/2026-10-04-s3 --next' $'Step 3 started (log above). If it stalls: `/pickup \'claude/x/2026-10-04-s3\' --fresh`.'
check "$(sx_ "$T/h3.jsonl" "$R" | wc -c | tr -d ' ')" 0 "handoff: a turn that ran dispatch passes"
tf_ "$T/h3o.jsonl" "go" 'bash ~/projects/layer/bin/run-seed claude/x/2026-10-04-s3 --next' $'Step 3 started (log above). If it stalls: `/pickup \'claude/x/2026-10-04-s3\' --fresh`.'
check "$(sx_ "$T/h3o.jsonl" "$R" | wc -c | tr -d ' ')" 0 "  so does one that ran it by its old name (the shim)"
tf_ "$T/h3g.jsonl" "go" 'grep -rn dispatch bin' $'Done. If it stalls: `/pickup \'claude/x/2026-10-04-s3\' --fresh`.'
check "$(sx_ "$T/h3g.jsonl" "$R" | grep -c 'hands Sam a session to start')" 1 "  a turn whose Bash only grepped for the word does not (dispatch is an ordinary word)"
tf_ "$T/h4.jsonl" "go" 'ls' $'**Do this now**\n```\n/pickup \'claude/x/2026-10-04-s3\' --fresh\n```\n\nNot dispatched: step 3 needs your answer to D2 first.\n\n'"$WP"
check "$(sx_ "$T/h4.jsonl" "$R" | wc -c | tr -d ' ')" 0 "handoff: a reply that says why not dispatch (waits on D2) passes"
check "$(sx_ "$T/h1.jsonl" "$P2" | grep -c 'hands Sam a session to start')" 0 "handoff: a repo that acts on the real world is never dispatched, so no block"
check "$(sx_ "$T/h1.jsonl" "$T" | grep -c 'hands Sam a session to start')" 0 "handoff: outside a repo, nothing"
tf_ "$T/h5.jsonl" $'<command-message>pickup</command-message>\n<command-name>/pickup</command-name>' 'ls' $'It is large: `/pickup \'claude/x/2026-10-04-s3\' --fresh` or --reopen?'
check "$(sx_ "$T/h5.jsonl" "$R" | grep -c 'hands Sam a session to start')" 0 "handoff: /pickup's own choice, asked by Sam, passes"
tf_ "$T/h6.jsonl" "go" 'ls' $'The hook starts a new session only when asked.'
check "$(sx_ "$T/h6.jsonl" "$R" | wc -c | tr -d ' ')" 0 "handoff: prose about sessions is no handoff"
# D1 (2026-10-05, C): `pickup next` decides the split itself — seeded (dispatch --next) where dispatch
# takes the repo, a tab only where it refuses — so each of its three verdicts' replies passes
PN=$'python3 ~/projects/layer/bin/pickup next - <<\'EOF\'\nBuild step 3.\nEOF'
tf_ "$T/h7.jsonl" "go" "$PN" $'Step 2 built. A new VS Code tab has the next step pre-filled.\n\n🛑 SAM, THIS SESSION IS WAITING FOR YOU — press Enter in the new tab.'
check "$(sx_ "$T/h7.jsonl" "$P2" | wc -c | tr -d ' ')" 0 "handoff: pickup next's tab, in a repo dispatch refuses (\"press Enter in the new tab\"), passes"
tf_ "$T/h7b.jsonl" "go" "$PN" $'Step 2 built. Started claude/x/2026-10-04-s3 unattended (dispatch); its window is titled run · s3.'
check "$(sx_ "$T/h7b.jsonl" "$R" | wc -c | tr -d ' ')" 0 "  pickup next's seeded, in a repo dispatch takes, passes"
tf_ "$T/h7c.jsonl" "go" "$PN" $'Under 120k: building step 3 here, then the check and /finish.'
check "$(sx_ "$T/h7c.jsonl" "$R" | wc -c | tr -d ' ')" 0 "  pickup next's continue passes"
check "$(sx_ "$T/h2.jsonl" "$R" | grep -c -- "--next --repo $(cd "$R" && pwd -P)")" 1 "handoff: the hint names dispatch's --repo (its default is layer)"
# ordinary prose that says "new tab" or "new window" is no handoff (review of 2026-10-05)
n=0
for line in "Open the PR in a new tab to see the diff." "Reload VS Code, then open a new window on layer." \
            "Enter the code in the new window that appears." "The lock frees when you open a new session in that worktree." \
            "Paste the URL into a new tab to see the page." "Type your password in the new window that opens." \
            "Paste the token into the new window \`claude setup-token\` opens." "It reproduces only when you start a fresh session." \
            "I updated the next step's prompt in the doc."; do
  n=$((n+1)); tf_ "$T/hp$n.jsonl" "go" 'ls' "Built. $line"
  check "$(sx_ "$T/hp$n.jsonl" "$R" | grep -c 'hands Sam a session to start')" 0 "handoff: prose passes — $line"
done
for line in "Paste this into a fresh Claude Code session." "Start step 3 in a new Claude Code tab." \
            "Then paste the prompt below into a fresh VS Code tab."; do
  n=$((n+1)); tf_ "$T/hp$n.jsonl" "go" 'ls' "Built. $line"
  check "$(sx_ "$T/hp$n.jsonl" "$R" | grep -c 'hands Sam a session to start')" 1 "handoff: still blocks — $line"
done
# the handoff's own repo decides, not the session's: dispatch refuses a repo that is not physical: none
H="$T/home"; mkdir -p "$H/projects"; ln -s "$P2" "$H/projects/phys"; ln -s "$R" "$H/projects/repo"
TODO_LINE="Follow-up handed off: s3 — claude/x/2026-10-04-s3 (phys) waits on Sam's answer to D2; start it with /pickup 'claude/x/2026-10-04-s3' --fresh in a phys window"
tf_ "$T/h8.jsonl" "go" 'ls' "Brief seeded. $TODO_LINE"
check "$(HOME="$H" sx_ "$T/h8.jsonl" "$R" | grep -c 'hands Sam a session to start')" 0 "handoff: /todo's exception line for a physical repo passes, from a seedable session"
TODO_SEED="Follow-up handed off: s3 — claude/x/2026-10-04-s3 (repo) waits on Sam's answer to D2; start it with /pickup 'claude/x/2026-10-04-s3' --fresh in a repo window"
tf_ "$T/h9.jsonl" "go" 'ls' "Brief seeded. $TODO_SEED"
check "$(HOME="$H" sx_ "$T/h9.jsonl" "$P2" | grep -c 'hands Sam a session to start')" 1 "  and one for a seedable repo blocks, from a physical session"
git -C "$P2" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init; git -C "$P2" branch -q claude/x/2026-10-04-p3
tf_ "$T/h10.jsonl" "go" 'ls' $'Step 2 built.\n\n🛑 SAM, THIS SESSION IS WAITING FOR YOU — start step 3: `/pickup \'claude/x/2026-10-04-p3\' --fresh`.'
check "$(HOME="$H" sx_ "$T/h10.jsonl" "$R" | grep -c 'hands Sam a session to start')" 0 "  a branch found only in a physical repo under ~/projects: that repo judges"
tf_ "$T/h11.jsonl" "go" 'ls' "Seeded. Not dispatched, waits on D2: start it with /pickup 'claude/x/2026-10-04-s3' --fresh in a repo window"
check "$(HOME="$H" sx_ "$T/h11.jsonl" "$R" | grep -c 'hands Sam a session to start')" 0 "  /todo's waits-on line names dispatch, so it passes in a seedable repo too"

# an opt-in kept in repos.json lives untracked in the primary only (hooks/sync.py overlay_workflow)
OVP="$T/ovp"; git init -q -b main "$OVP" && printf -- '- physical: none\n' > "$OVP/AGENTS.md"
git -C "$OVP" add AGENTS.md && git -C "$OVP" commit -qm one && git -C "$OVP" worktree add -q "$T/ovp-wt" -b claude/t
mkdir -p "$OVP/.claude" && printf '{"_from": "repos.json", "checkpoint": true}\n' > "$OVP/.claude/workflow.json"
sd_() { python3 - "$B/paste-paths" "$1" <<'EOF'
import sys
from importlib.machinery import SourceFileLoader
print(SourceFileLoader("pp", sys.argv[1]).load_module().seedable(sys.argv[2]))
EOF
}
check "$(sd_ "$T/ovp-wt")" "True" "seedable from a worktree reads the primary's untracked opt-in"
rm "$OVP/.claude/workflow.json"
check "$(sd_ "$T/ovp-wt")" "False" "  and without one, not seedable"

# session-asks R2/B4: a skippered run relays what it would hand Sam; a skipper keeps a listener
af_() {  # af_ <reply> <cwd> [ENV=VAL …]: ask_findings' count; SID=… is this session's id
  python3 - "$B/paste-paths" "$@" <<'PY'
import sys
from importlib.machinery import SourceFileLoader
m = SourceFileLoader("pp", sys.argv[1]).load_module()
env = dict(a.split("=", 1) for a in sys.argv[4:])
sid = env.pop("SID", "s-1")
print(len(m.ask_findings(sys.argv[2].replace("\\n", "\n"), None, sys.argv[3], env, session=sid)))
PY
}
AG="$T/askrepo"; git init -q "$AG"
W='done.\n\n🛑 SAM, THIS SESSION IS WAITING FOR YOU — D1, the cadence'
check "$(af_ "$W" "$AG" CLAUDE_UNATTENDED=dispatch DISPATCH_MANAGER=m1)" 1 "ask: a skippered run's WAITING line naming a D-item is refused once"
check "$(af_ "$W" "$AG" CLAUDE_UNATTENDED=dispatch DISPATCH_SKIPPER=m1)" 1 "  the same under the skipper's new name alone (rename S5: both names read)"
check "$(af_ 'Do this now\n\n```\nssh buildbox-ssh login\n```\n\nthen I go on.' "$AG" CLAUDE_UNATTENDED=dispatch DISPATCH_MANAGER=m1)" 1 "  so is a Do-this-now step (Sam: a login counts too)"
check "$(af_ 'done.\n\n🛑 SAM, THIS SESSION IS WAITING FOR YOU — log in to gh on buildbox, then dispatch --next' "$AG" CLAUDE_UNATTENDED=dispatch DISPATCH_MANAGER=m1)" 1 "  so is a WAITING line naming a manual step"
check "$(af_ "$W" "$AG" CLAUDE_UNATTENDED=dispatch)" 0 "  a run with no skipper may end on it (R6)"
check "$(af_ "$W" "$AG" DISPATCH_MANAGER=m1)" 0 "  an attended session is untouched"
check "$(af_ 'RELAYED TO coding-7 — D1, the cadence' "$AG" CLAUDE_UNATTENDED=dispatch DISPATCH_MANAGER=m1)" 0 "  the RELAYED line passes"
echo "  finding 7: dispatch's own refusals end a run on the WAITING line, and are not asks"
check "$(af_ 'done.\n\n🛑 SAM, THIS SESSION IS WAITING FOR YOU — the next step waits for a run to end (dispatch --next once one has)' "$AG" CLAUDE_UNATTENDED=dispatch DISPATCH_MANAGER=m1)" 0 "  the run cap's line passes"
check "$(af_ 'done.\n\n🛑 SAM, THIS SESSION IS WAITING FOR YOU — the next step waits for Sam to start it (dispatch --next by hand starts a new chain)' "$AG" CLAUDE_UNATTENDED=dispatch DISPATCH_MANAGER=m1)" 0 "  the chain depth's line passes"
check "$(af_ 'done.\n\n🛑 SAM, THIS SESSION IS WAITING FOR YOU — the primary has no room until its weekly reset, Sun 04:00' "$AG" CLAUDE_UNATTENDED=dispatch DISPATCH_MANAGER=m1)" 0 "  an account with no room passes"
echo "  second review, finding 1: every other WAITING line counts — the default flipped"
for l in "the worktree switch needs your approval" "run the six commands above, then /finish" "pick option A or B" "say go to start the four fixes"; do
  check "$(af_ "done.\n\n🛑 SAM, THIS SESSION IS WAITING FOR YOU — $l" "$AG" CLAUDE_UNATTENDED=dispatch DISPATCH_MANAGER=m1)" 1 "  '$l' is an ask"
done
check "$(af_ 'done.\n\n🛑 SAM, THIS SESSION IS WAITING FOR YOU — nothing to do yet; the reviewers are running' "$AG" CLAUDE_UNATTENDED=dispatch DISPATCH_MANAGER=m1)" 0 "  'nothing to do' is not"
check "$(af_ 'done.\n\n🛑 SAM, THIS SESSION IS WAITING FOR YOU — nothing to do but approve D1' "$AG" CLAUDE_UNATTENDED=dispatch DISPATCH_MANAGER=m1)" 1 "  …unless it names a D-item or a step (the signals beat the exemption)"
check "$(af_ 'done.\n\n🛑 SAM, THIS SESSION IS WAITING FOR YOU — nothing is owed' "$AG" CLAUDE_UNATTENDED=dispatch DISPATCH_MANAGER=m1)" 0 "  'nothing is owed' is not either: the lint sends it to WAITING FOR NOTHING, never to a relay too (landing review, 2026-10-29)"
check "$(af_ 'done.\n\n🛑 SAM, THIS SESSION IS WAITING FOR YOU — merge the PR; nothing else needed' "$AG" CLAUDE_UNATTENDED=dispatch DISPATCH_MANAGER=m1)" 1 "  …while an ask with a nothing tail still relays"
for l in "nothing pending; merge the PR when you are happy" "nothing required; the PR waits for your merge" "nothing needed; just merge #12"; do
  check "$(af_ "done.\n\n🛑 SAM, THIS SESSION IS WAITING FOR YOU — $l" "$AG" CLAUDE_UNATTENDED=dispatch DISPATCH_MANAGER=m1)" 1 "  '$l' still relays, as on main (finish review, 2026-10-30)"
done
check "$(af_ 'No Do this now block is owed here.\n\n```\nls\n```\n\nRELAYED TO coding-7 — D1, x' "$AG" CLAUDE_UNATTENDED=dispatch DISPATCH_MANAGER=m1)" 0 "  a mention of Do this now in prose is not the heading"
check "$(af_ '## Do this now\n\n```\nopen https://x\n```\n\nRELAYED TO coding-7 — D1, x' "$AG" CLAUDE_UNATTENDED=dispatch DISPATCH_MANAGER=m1)" 1 "  the heading form with a block under it is"
echo "  finding 9: ask.json counts only for this session"
mkdir -p "$AG/.git/claude"; echo '{"verdict": "unreachable", "session": "s-1"}' > "$AG/.git/claude/ask.json"
check "$(af_ "$W" "$AG" CLAUDE_UNATTENDED=dispatch DISPATCH_MANAGER=m1)" 0 "  bin/ask found no road for this session: the WAITING line is the way"
check "$(af_ "$W" "$AG" CLAUDE_UNATTENDED=dispatch DISPATCH_MANAGER=m1 SID=s-2)" 1 "  an earlier run's verdict is stale: refused"
echo '{"verdict": "unreachable"}' > "$AG/.git/claude/ask.json"
check "$(af_ "$W" "$AG" CLAUDE_UNATTENDED=dispatch DISPATCH_MANAGER=m1)" 1 "  a verdict with no session proves nothing"
echo "  stray-manager B1 ii: no DISPATCH_MANAGER, and this Mac runs a standing skipper"
SMD="$T/manager"; SSD="$T/smsess"; mkdir -p "$SMD" "$SSD"
printf '{"session": "sm-1", "name": "skipper · testmac", "pid": %d, "space": "sp-m"}' $$ > "$SMD/testmac.json"
printf '{"pid": %d, "sessionId": "sm-1", "name": "skipper", "updatedAt": 2}' $$ > "$SSD/sm-1.json"
smenv() { ASK_MANAGER_DIR="$SMD" ASK_SESSIONS_DIR="$SSD" PLAN_HOST=testmac "$@"; }
rm "$AG/.git/claude/ask.json"
check "$(ASK_MANAGER_DIR="$T/no-manager" af_ "$W" "$AG" CLAUDE_UNATTENDED=dispatch)" 0 "  no record: the WAITING line passes, as before the seam"
check "$(smenv af_ "$W" "$AG" CLAUDE_UNATTENDED=dispatch)" 1 "  a live record: the run is skippered, its WAITING line refused"
check "$(smenv python3 -c 'import sys; from importlib.machinery import SourceFileLoader as L; m=L("pp", sys.argv[1]).load_module(); print("standing one, skipper · testmac)" in m.ask_findings(sys.argv[2], None, sys.argv[3], {"CLAUDE_UNATTENDED": "x"}, session="s-1")[0])' "$B/paste-paths" "$(printf "$W")" "$AG")" \
  "True" "  the finding names the Mac's skipper"
echo '{"verdict": "none", "session": "s-1"}' > "$AG/.git/claude/ask.json"
check "$(smenv af_ "$W" "$AG" CLAUDE_UNATTENDED=dispatch)" 1 "  a 'none' recorded before the skipper ran is void: relay again"
echo '{"verdict": "unreachable", "session": "s-1"}' > "$AG/.git/claude/ask.json"
check "$(smenv af_ "$W" "$AG" CLAUDE_UNATTENDED=dispatch)" 0 "  'unreachable' (every road refused) still lets the WAITING line through"
rm "$AG/.git/claude/ask.json"
echo "  review gate 2026-10-16: the hook resolves as the relay does (asklib.resolve), and autofinish's start is no skipper's"
afw_() {  # afw_ <ENV=VAL …>: the finding's text for the WAITING line, or "none"
  python3 - "$B/paste-paths" "$(printf "$W")" "$AG" "$@" <<'PY'
import sys
from importlib.machinery import SourceFileLoader
m = SourceFileLoader("pp", sys.argv[1]).load_module()
env = dict(a.split("=", 1) for a in sys.argv[4:])
f = m.ask_findings(sys.argv[2], None, sys.argv[3], env, session=env.pop("SID", "s-1"))
print(f[0] if f else "none")
PY
}
has "$(smenv afw_ CLAUDE_UNATTENDED=dispatch DISPATCH_MANAGER=gone-1)" "a skipper (this Mac's standing one, skipper · testmac)" \
  "  its own skipper ended (no record): relay sends it to the standing one, and the finding names skipper · testmac"
printf '{"pid": %d, "sessionId": "own-1", "name": "coding-1", "updatedAt": 2}' $$ > "$SSD/own-1.json"
has "$(smenv afw_ CLAUDE_UNATTENDED=dispatch DISPATCH_MANAGER=own-1)" "a skipper (DISPATCH_SKIPPER)" "  its own skipper live: that one, not the standing one"
rm "$SSD/own-1.json"
echo '{"session": "s-1", "by": "sweep", "started": 1}' > "$AG/.git/claude/autofinish.json"
check "$(smenv af_ "$W" "$AG" CLAUDE_UNATTENDED=dispatch)" 0 "  autofinish's /finish --unattended start (its run record names this session): no skipper's, the WAITING line passes (M1 c, M3)"
check "$(smenv af_ "$W" "$AG" CLAUDE_UNATTENDED=dispatch SID=s-2)" 1 "  another session in that worktree is still the standing skipper's"
rm "$AG/.git/claude/autofinish.json"
check "$(python3 - "$B/paste-paths" "$AG" <<'PY'
import sys
from importlib.machinery import SourceFileLoader
m = SourceFileLoader("pp", sys.argv[1]).load_module()
called = []
m.standing = lambda env=None: called.append(1)
print(len(m.ask_findings("all done, nothing asked", None, sys.argv[2], {"CLAUDE_UNATTENDED": "x"}, session="s-1")), len(called))
PY
)" "0 0" "  a turn that asks nothing: standing() is never called (no asklib load, no scutil on every Stop)"
sleep 0 & SMDEAD=$!; wait $SMDEAD
printf '{"pid": %d, "sessionId": "sm-1", "name": "skipper", "updatedAt": 2}' $SMDEAD > "$SSD/sm-1.json"
check "$(smenv af_ "$W" "$AG" CLAUDE_UNATTENDED=dispatch)" 0 "  a record whose session has ended: no skipper, as before"
mf_() {  # mf_ <session> <listening> <alive> <listen row> [cwd]: skipper_findings' count over a scratch runs dir
  python3 - "$B/paste-paths" "$1" "$2" "$T/runs" "$3" "$4" "${5:-}" <<'PY'
import sys
from importlib.machinery import SourceFileLoader
m = SourceFileLoader("pp", sys.argv[1]).load_module()
alive = None if sys.argv[5] == "real" else (lambda st: sys.argv[5] == "yes")
print(len(m.skipper_findings(sys.argv[2], env={"ASK_QUEUE_DIR": sys.argv[4] + "-q"}, runs=sys.argv[4], listening=sys.argv[3] == "yes",
                             cwd=sys.argv[7], alive=alive, listen_row=sys.argv[6])))
PY
}
mkdir -p "$T/runs"
echo '{"manager": "mgr-1", "topic": "demo", "plan_space": "sp-1"}' > "$T/runs/a.json"
echo '{"manager": "mgr-1", "topic": "old", "plan_space": "sp-1", "ended": 1}' > "$T/runs/b.json"
echo '{"manager": "mgr-3", "topic": "nopage"}' > "$T/runs/c.json"
check "$(python3 - "$B/paste-paths" "$T/runs" <<'PY'
import sys
from importlib.machinery import SourceFileLoader
m = SourceFileLoader("pp", sys.argv[1]).load_module()
f = m.skipper_findings("hook-2", env={"ASK_QUEUE_DIR": sys.argv[2] + "-q2", "CLAUDE_CODE_SESSION_ID": "mgr-1"}, runs=sys.argv[2],
                       listening=False, alive=lambda st: True, listen_row="talk")
print(len(f), "--session mgr-1\x60" in f[0] if f else "-", "hook-2" in f[0] if f else "-")
PY
)" "1 True False" "skipper, review gate 2026-10-16: the hook's id differs (after /clear): the run is found by CLAUDE_CODE_SESSION_ID, and listen is told that id, the one it accepts"
check "$(mf_ mgr-1 no yes talk)" 1 "skipper: a live run with a plan page and no listener — start one"
check "$(mf_ mgr-1 yes yes talk)" 0 "  a listener runs: nothing"
check "$(mf_ mgr-2 no yes talk)" 0 "  a session that manages nothing: nothing"
check "$(python3 - "$B/paste-paths" "$T/runs-empty" <<'PY'
import sys
from importlib.machinery import SourceFileLoader
m = SourceFileLoader("pp", sys.argv[1]).load_module()
far = [{"manager": "mgr-9", "topic": "build", "host": "buildbox"}, {"manager": "other", "topic": "x", "host": "buildbox"}]
f = m.skipper_findings("mgr-9", env={"ASK_QUEUE_DIR": sys.argv[2] + "-q"}, runs=sys.argv[2], listening=False,
                       alive=lambda st: True, listen_row="talk", peer_runs=far)
g = m.skipper_findings("mgr-8", env={"ASK_QUEUE_DIR": sys.argv[2] + "-q"}, runs=sys.argv[2], listening=False,
                       alive=lambda st: True, listen_row="talk", peer_runs=far)
print(len(f), "(build)" in f[0] if f else "-", len(g))
PY
)" "1 True 0" "  peer-manager-relay: a live run on a peer (asklib.peer_runs) is told to listen too; another skipper's is not"
echo "  finding 8: only runs that can use a listener, once a session"
check "$(mf_ mgr-3 no yes talk)" 0 "  a run with no plan_space (no Talk address): nothing"
check "$(mf_ mgr-1 no yes none)" 0 "  ask.listen is not talk: nothing"
check "$(mf_ mgr-1 no no talk)" 0 "  the run's claude is gone: nothing"
SKR="$T/skrepo"; git init -q "$SKR"
check "$(mf_ mgr-1 no yes talk "$SKR")" 1 "  the first turn is told"
check "$(mf_ mgr-1 no yes talk "$SKR")" 0 "  the second is not (a marker in the git dir)"
check "$(mf_ mgr-1 yes yes talk "$SKR")" 0 "  second review, finding 4: a listener runs — the marker clears"
check "$(mf_ mgr-1 no yes talk "$SKR")" 1 "  it exited on a wake and none restarted: told once more"
check "$(mf_ mgr-1 no yes talk "$SKR")" 0 "  and only once"
check "$(mf_ mgr-1 no yes talk)" 1 "  no git dir (the listener above cleared its marker): told once"
check "$(ls "$T/runs-q" 2>/dev/null | grep -c '^listen-nagged.mgr-1$')" 1 "  …the marker under the queue dir"
check "$(mf_ mgr-1 no yes talk)" 0 "  …so a cwd-less turn is not told every time"
sleep 30 & LP=$!
printf '{"manager": "mgr-4", "topic": "real", "plan_space": "sp-1", "pid": %d, "proc_start": "%s"}' "$LP" "$(TZ=UTC LC_ALL=C ps -o lstart= -p "$LP" | xargs)" > "$T/runs/d.json"
check "$(mf_ mgr-4 no real talk)" 1 "  dispatch-rc's same(): a running pid with its start time is alive"
printf '{"manager": "mgr-5", "topic": "reused", "plan_space": "sp-1", "pid": %d, "proc_start": "Thu Jan  1 00:00:00 2026"}' "$LP" > "$T/runs/e.json"
check "$(mf_ mgr-5 no real talk)" 0 "  the same pid with another start time is not"
kill "$LP" 2>/dev/null; wait "$LP" 2>/dev/null

# regatta-modules G9, G24: helm (asklib, surfaces, bin/ask) and wharf-runs (dispatch-rc) absent —
# run from a scratch tree of the core and keel alone, since
# wharf-runs lives in this repo since B7 (the AGENTS.md trap: a peer that moves in is found by
# tool()'s modules/*/ search). The hand-over finding still blocks, the skipper reminder and the
# standing-skipper test are skipped, never a traceback.
NP="KEEL_NO_PEERS=1"   # no variable the code reads: the scratch tree hides the peers
G24="$T/g24tree"; mkdir -p "$G24/.claude-plugin" "$G24/modules"; : > "$G24/.claude-plugin/marketplace.json"
cp -R "$B/../../regatta" "$G24/modules/regatta"; cp -R "$B/.." "$G24/modules/keel"
check "$(printf '{"transcript_path":"%s","stop_hook_active":false,"cwd":"%s"}' "$T/b7.jsonl" "$R" | env "$NP" python3 "$G24/modules/keel/bin/paste-paths" --stop-hook | grep -c 'hand-over line is not right')" 1 "G9: peers absent — the hand-over finding still blocks"
check "$(env "$NP" python3 -c 'import sys; from importlib.machinery import SourceFileLoader as L; m = L("pp", sys.argv[1]).load_module(); print(m._asklib(), m._rc(), m.standing({"DISPATCH_MANAGER": "m"}), m.skipper_findings("s", env={}, runs=sys.argv[2]))' "$G24/modules/keel/bin/paste-paths" "$T/runs" 2>&1)" "None None None []" "G24: no asklib, no dispatch-rc, no surfaces — None, and no skipper reminder"
check "$(python3 -c 'import sys; from importlib.machinery import SourceFileLoader as L; m = L("pp", sys.argv[1]).load_module(); print(m._asklib() is not None, m._rc() is not None, m._ask_cmd().endswith("/bin/ask"))' "$B/paste-paths")" "True True True" "  with them: each found through the core's tool()"


[ "$fails" = 0 ] && echo "all pass" || { echo "$fails failed"; exit 1; }
