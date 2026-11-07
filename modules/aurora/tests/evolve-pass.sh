#!/usr/bin/env bash
# evolve's S5 suite: sections/evolve-scope.md (<= 180 lines, dream --scope aliased), scope profiles and the
# knowledge-layer refusal, evolve where/open/critic/record (quiet earned vs refused, atlas staged outside the
# vault and committed into <vault>/evolve/, confidential export gate, open-scope $ASKS_FINDINGS export into
# plumb's asks), templates/meeting.md + evolve meetings (repo-committed notes only), hidden-future replay with
# canary leak detection, and shadow passes on regatta, atlas and film. Scratch paths only; no network, no live claude.
#   bash modules/aurora/tests/evolve-pass.sh
set -u
D="$(cd "$(dirname "$0")/.." && pwd -P)"
E="$D/bin/evolve"
SP="$D/bin/scope-pass"
ASKS="$D/../plumb/bin/asks"
T="$(mktemp -d)"; T="$(cd "$T" && pwd -P)"
trap '[ -n "${KEEP:-}" ] || rm -rf "$T"' EXIT; [ -n "${KEEP:-}" ] && echo "scratch $T"
for v in $(env | sed -n 's/^\(REGATTA[A-Za-z0-9_]*\)=.*/\1/p; s/^\(CLAUDE[A-Za-z0-9_]*\)=.*/\1/p; s/^\(EVOLVE[A-Za-z0-9_]*\)=.*/\1/p; s/^\(GATE_[A-Za-z0-9_]*\)=.*/\1/p; s/^\(ATLAS_[A-Za-z0-9_]*\)=.*/\1/p; s/^\(ASKS_[A-Za-z0-9_]*\)=.*/\1/p; s/^\(SCOPE_PASS_[A-Za-z0-9_]*\)=.*/\1/p'); do unset "$v"; done
unset ACCOUNTS_FILE

export HOME="$T/h" REGATTA_CONFIG="$T/config" GIT_CONFIG_GLOBAL="$T/gitconfig"
mkdir -p "$T/h/.claude/projects" "$REGATTA_CONFIG/regatta" "$REGATTA_CONFIG/aurora/scopes" "$REGATTA_CONFIG/atlas" "$REGATTA_CONFIG/sextant" "$REGATTA_CONFIG/helm"
printf '[user]\n\tname = t\n\temail = t@example.invalid\n[init]\n\tdefaultBranch = main\n' > "$GIT_CONFIG_GLOBAL"
P="$T/projects"; L="$T/log"
mkdir -p "$P" "$L"
printf '%s\n' "$P" > "$REGATTA_CONFIG/regatta/projects"
printf '%s\n' "$L" > "$REGATTA_CONFIG/regatta/log-dir"
printf 'testhost\n' > "$REGATTA_CONFIG/regatta/host-name"
export EVOLVE_STATE="$L/aurora/evolve" ASKS_FINDINGS="$L/evolve/findings" CLAUDE_REPOS_JSON="$REGATTA_CONFIG/repos.json"

fails=0
check() {
  if [ "$1" = "$2" ]; then echo "  ok  $3"; else echo "  FAIL $3"; echo "       got:  $1"; echo "       want: $2"; fails=$((fails + 1)); fi
}
cat > "$T/j.py" <<'PY'
import json, sys
d = json.load(sys.stdin)
print(eval(sys.argv[1]))
PY
j() { python3 "$T/j.py" "$1"; }
now() { python3 -c 'import datetime as d, sys; print((d.datetime.now(d.timezone.utc) + d.timedelta(days=float(sys.argv[1]))).isoformat(timespec="seconds"))' "${1:-0}"; }
mkrepo() { mkdir -p "$P/$1"; git -C "$P/$1" init -q; printf '# %s\n' "$1" > "$P/$1/AGENTS.md"; git -C "$P/$1" add -A; git -C "$P/$1" commit -qm init; }

# ---- Setup: layer, vault, regatta, atlas, film, and confidential scope -------------------------------------
mkrepo layer-repo; mkrepo vault-repo; mkrepo regatta-repo; mkrepo film-prod; mkrepo secret-node
printf 'layer\n%s\n' "$P/layer-repo" > "$REGATTA_CONFIG/atlas/layer"
printf 'vault\n%s\n' "$P/vault-repo" > "$REGATTA_CONFIG/atlas/vault"
printf '%s\n' "$P/layer-repo" > "$REGATTA_CONFIG/regatta/overlay"
printf 'owner\n' > "$REGATTA_CONFIG/regatta/owner"
: > "$REGATTA_CONFIG/regatta/guarded"
: > "$REGATTA_CONFIG/regatta/orca-deny"
mkdir -p "$P/vault-repo/inbox/upstream" "$P/vault-repo/dreams" "$P/vault-repo/evolve"
printf '# Log\n\n' > "$P/vault-repo/log.md"
git -C "$P/vault-repo" add -A; git -C "$P/vault-repo" commit -qm "vault init"

mkdir -p "$P/regatta-repo/.claude" "$P/regatta-repo/dreams" "$P/regatta-repo/evolve"
printf '{"main": "main", "in_place": ["dreams/"]}\n' > "$P/regatta-repo/.claude/workflow.json"
printf '# Principles\n- Every routed finding carries a dated benefit check.\n' > "$P/regatta-repo/PRINCIPLES.md"
printf '# TODO\n' > "$P/regatta-repo/TODO.md"
git -C "$P/regatta-repo" add -A; git -C "$P/regatta-repo" commit -qm "regatta workflow without evolve/"

mkdir -p "$P/film-prod/.claude" "$P/film-prod/cuts"
printf 'Read `cut-notes`.\n' > "$P/film-prod/.claude/scope-pass.md"
printf '{"time": "%s"}\n' "$(now)" > "$P/film-prod/cuts/notes.jsonl"
cat > "$P/film-prod/.claude/evolve-scope.json" <<'J'
{"sources": [{"id": "cut-notes", "lens": "product", "kind": "path", "at": "{anchor}/cuts/notes.jsonl", "fresh_days": 14, "reader": "pass"}],
 "outcome_classes": {"festival_cut": {"observation_days": 21, "about": "festival cut locked"}},
 "observation_windows": {"product": 21},
 "bars": {"product": "zero dropped reels per cut"},
 "not_applicable": ["commercial"],
 "radar_queries": ["aces color pipeline 2026"]}
J
git -C "$P/film-prod" add -A; git -C "$P/film-prod" commit -qm "film anchor profile"

mkdir -p "$P/secret-node/.claude" "$P/secret-node/dreams" "$P/secret-node/evolve"
printf 'ACMECORP\nPROJECTZETA\n' > "$P/secret-node/.claude/words.txt"
cat > "$REGATTA_CONFIG/aurora/scopes/clientx.json" <<'J'
{"outcome_classes": {"secret_milestone": {"observation_days": 14}}}
J
git -C "$P/secret-node" add -A; git -C "$P/secret-node" commit -qm "secret init"

cat > "$CLAUDE_REPOS_JSON" <<'J'
{"repos": {"layer-repo": {}, "regatta-repo": {}, "film-prod": {}, "secret-node": {}},
 "scopes": {"regatta": {"repos": ["regatta-repo"]},
            "atlas": {"repos": ["layer-repo"]},
            "film": {"repos": ["film-prod"]},
            "umbrella": {"repos": ["secret-node", "regatta-repo"]},
            "clientx": {"repos": ["secret-node"], "confidential": true}}}
J

printf '{"goals": [{"id": "g1"}]}\n' > "$REGATTA_CONFIG/sextant/north-star.json"
printf '{"time": "%s"}\n' "$(now)" > "$L/ops.jsonl"
printf '{"time": "%s"}\n' "$(now)" > "$L/ops-verdicts.jsonl"
printf 'denial\n' > "$L/fence.log"

# Simple git-commit stand-in for SCOPE_PASS_COMMIT (validates vault name and commits requested paths on main)
cat > "$T/vcommit.sh" <<'SH'
#!/usr/bin/env bash
set -eu
vname="$1"; shift
[ "$vname" = "vault" ] || { echo "bad vault $vname" >&2; exit 2; }
[ "$1" = "-m" ] || { echo "expected -m" >&2; exit 2; }
msg="$2"; shift 2
git add -- "$@"
git diff --cached --quiet || git commit -qm "$msg"
SH
chmod +x "$T/vcommit.sh"
export SCOPE_PASS_COMMIT="$T/vcommit.sh"

# ---- 1. Section file size, aliases, and real pass-reader coverage ------------------------------------------
echo "sections/evolve-scope.md — Ring 1 cap, aliases, and zero unread pass sources"
lines=$(wc -l < "$D/skills/aurora/sections/evolve-scope.md" | tr -d ' ')
check "$([ "$lines" -le 180 ] && echo ok || echo "over:$lines")" "ok" "evolve-scope.md is <= 180 lines ($lines)"
check "$(grep -c 'evolve-scope.md' "$D/skills/aurora/SKILL.md") $(grep -c 'evolve-scope.md' "$D/skills/aurora/sections/dream-scope.md") $(grep -c 'evolve-scope.md' "$D/skills/aurora/sections/dream.md")" \
  "2 3 1" "SKILL.md, dream-scope.md and dream.md alias dream --scope to evolve-scope.md"
cov=$("$E" coverage --scope regatta --json --no-record)
check "$(echo "$cov" | j '[c["source"] for c in d["scopes"][0]["cells"] if c["reader"] == "pass" and c["state"] == "unread"]')" "[]" \
  "every reader=pass source in lenses.json is read by the real evolve-scope.md"

# ---- 2. Scope profiles: config dir, anchor fallback, knowledge-layer refusal, fenced anchor ----------------
echo "scope profiles — config dir first, anchor fallback, layer refusal, custom outcome_classes"
cov_f=$("$E" coverage --scope film --json --no-record)
check "$(echo "$cov_f" | j 'd["scopes"][0]["profile_error"], [c["state"] for c in d["scopes"][0]["cells"] if c["source"] == "cut-notes"]')" \
  "(False, ['observed'])" "film loads <anchor>/.claude/evolve-scope.json when no config-dir profile exists"
cov_u=$("$E" coverage --scope umbrella --json --no-record)
check "$(echo "$cov_u" | j 'd["scopes"][0]["profile_error"]')" "False" \
  "open scope whose first repo is confidential never opens that anchor's evolve-scope.json"
mkdir -p "$P/layer-repo/.claude"
printf '{"not_applicable": ["commercial"]}\n' > "$P/layer-repo/.claude/evolve-scope.json"
cov_a=$("$E" coverage --scope atlas --json --no-record)
check "$(echo "$cov_a" | j 'd["scopes"][0]["profile_error"], any("knowledge layer" in w for w in d["scopes"][0]["manifest"]["why"])')" \
  "(True, True)" "a profile placed inside the knowledge layer is refused (profile_error, never quiet)"
"$E" where atlas > "$T/where-bad.txt"; check "$? $(grep -c '^ready no — .*knowledge layer' "$T/where-bad.txt")" "1 1" \
  "  evolve where atlas reports ready no naming the knowledge-layer refusal"
rm -f "$P/layer-repo/.claude/evolve-scope.json"
printf '{"not_applicable": ["commercial", "meetings"]}\n' > "$REGATTA_CONFIG/aurora/scopes/atlas.json"
"$E" where atlas > "$T/where-atlas.txt"; check "$? $(grep -c '^ready yes$' "$T/where-atlas.txt") $(grep -c '^vault-records true$' "$T/where-atlas.txt")" "0 1 1" \
  "  once moved to <config>/aurora/scopes/atlas.json, atlas is ready and targets vault-records"

# Validate custom outcome_class from film's anchor profile
cat > "$T/mk_finding.py" <<'PY'
import json, sys
sys.path.insert(0, sys.argv[1])
import evolve_schema as s
sc, oc, day, cyc, out = sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5], sys.argv[6]
f = {"id": "%s-cut-cadence" % sc.replace(":", "-"), "theme_id": "cut-cadence", "scope": sc, "cycle": cyc, "date": day,
     "need": "keep cut feedback fresh before lock", "process_revision": "evolve-scope@s5",
     "kind": "gap", "level": "UX", "lens": "product", "goal_ref": None,
     "evidence_refs": [{"source": "todo", "count": 3}], "source_freshness": {"todo": 1.0},
     "observation": "3 reels lacked cut notes", "hypothesis": "notes written after review",
     "counterevidence": "Reel 1 shipped cleanly without notes last cycle.", "p_success": 0.75,
     "intervention": "Require cut-notes entry before cut lock", "alternatives": ["park"],
     "smallest_test": "one reel", "acceptance_check": "evolve coverage --scope film --json exits 0",
     "benefit_check": {"check": "0 reels missing notes", "due": "2026-12-04"}, "observation_window": 21,
     "outcome_class": oc, "reversible": True, "auto_constructible": True, "auto_activatable": False,
     "size": "s", "est_list_usd": 3.0, "owner_minutes": 2, "maintenance_cost": None,
     "proposed_route": "build", "privacy_class": "open", "cooldown": 14, "prior_ids": [], "supersedes": None,
     "found_by": "pass", "also_found_by": [], "status": {"proposal": "proposed", "execution": None, "outcome": None},
     "action_version": 1, "target_scope": sc}
f["action_id"] = s.action_id(f["id"], 1, sc)
wrap = {"version": 1, "scope": sc, "cycle": cyc, "cutoff": day + "T21:00:00+00:00", "findings": [f]}
json.dump(wrap, open(out, "w"), indent=1)
PY
python3 "$T/mk_finding.py" "$D/lib" film festival_cut 2026-11-06 2026-W45 "$T/film-f.json"
"$E" validate findings "$T/film-f.json" --quiet; check "$?" 0 "evolve validate accepts a custom outcome_class declared in the scope's profile"
python3 "$T/mk_finding.py" "$D/lib" regatta festival_cut 2026-11-06 2026-W45 "$T/reg-bad-oc.json"
"$E" validate findings "$T/reg-bad-oc.json" --quiet > /dev/null; check "$?" 1 "  and refuses that outcome_class on another scope whose profile did not declare it"

# ---- 3. evolve where readiness on workflow.json in_place ---------------------------------------------------
echo "evolve where — workflow.json requires both dreams/ and evolve/ in in_place"
"$E" where regatta --day 2026-11-06 > "$T/w-reg1.txt"; rc=$?
check "$rc $(grep -c 'evolve/ not in the anchor.s in_place' "$T/w-reg1.txt")" "1 1" "missing evolve/ in .claude/workflow.json -> ready no (exit 1)"
printf '{"main": "main", "in_place": ["dreams/", "evolve/"]}\n' > "$P/regatta-repo/.claude/workflow.json"
git -C "$P/regatta-repo" commit -qam "add evolve/ to in_place"
"$E" where regatta --day 2026-11-06 > "$T/w-reg2.txt"; rc=$?
check "$rc $(grep -c '^ready yes$' "$T/w-reg2.txt")" "0 1" "with dreams/ and evolve/ in in_place -> ready yes (exit 0)"

# ---- 4. evolve open: rotating deep lens, research status, quiet earned vs refused --------------------------
echo "evolve open — rotating deep lens, outside: stale vs complete, quiet receipt earned and refused"
op1=$("$E" open regatta --day 2026-11-02 --quiet-exit --json); rc1=$?
check "$rc1 $(echo "$op1" | j 'd["outside"], d["quiet_ok"]')" "0 ('stale', False)" \
  "first open with no research artefact: outside=stale, not quiet (exit 0)"
dl_w1=$(echo "$op1" | j 'd["deep_lens"]')
dl_w2=$("$E" open regatta --day 2026-11-09 --json | j 'd["deep_lens"]')
dl_film_w1=$("$E" open film --day 2026-11-02 --json | j 'd["deep_lens"]')
check "$([ "$dl_w1" != "$dl_w2" ] && [ "$dl_w1" != "$dl_film_w1" ] && echo rotated)" "rotated" \
  "deep lens rotates across consecutive weeks ($dl_w1 -> $dl_w2) and across scopes ($dl_film_w1)"
mkdir -p "$L/sextant"
printf '{"status": "incomplete", "time": "%s"}\n' "$(now)" > "$L/sextant/2026-11-06-research.json"
check "$("$E" open regatta --day 2026-11-06 --json | j 'd["outside"]')" "stale" "an incomplete research artefact still records outside: stale"
printf '{"status": "complete", "time": "%s"}\n' "$(now)" > "$L/sextant/2026-11-06-research.json"
check "$("$E" open regatta --day 2026-11-06 --json | j 'd["outside"]')" "complete" "a complete research artefact of the night records outside: complete"

# ---- 5. evolve critic: deterministic cold checks + blinded model critic on gate evolve.critic --------------
echo "evolve critic — deterministic cold checks, blinded model critic, and confidential vendor guard"
cat > "$T/claude-stub.py" <<'PY'
#!/usr/bin/env python3
import json, os, sys
args = sys.argv[1:]
prompt = sys.stdin.read()
log_f = os.environ.get("STUB_LOG")
if log_f:
    open(log_f, "w").write(json.dumps({"args": args, "prompt": prompt}))
assert "-p" in args and "--output-format" in args and "--json-schema" in args, f"missing flags: {args}"
assert "--tools" in args and "--no-session-persistence" in args, f"missing isolation flags: {args}"
schema = json.loads(args[args.index("--json-schema") + 1])
if "UPSTREAM" in prompt or "confidential project" in prompt:
    # scope.upstream classify call
    out = {"items": {k: "clean" for k in schema.get("properties", {}).get("items", {}).get("properties", {})}}
    if not out["items"]:
        out = {k: "clean" for k in schema.get("required", [])}
else:
    # evolve.critic generate call
    mode = os.environ.get("CRITIC_MODE", "pass")
    out = {fid: {"verdict": mode, "reason": "acceptance check does not test intervention" if mode == "drop" else "sound"}
           for fid in schema.get("required", [])}
print(json.dumps({"is_error": False, "total_cost_usd": 0.012, "structured_output": out}))
PY
chmod +x "$T/claude-stub.py"

python3 "$T/mk_finding.py" "$D/lib" regatta code 2026-11-06 2026-W45 "$T/reg-good.json"
CLAUDE_BIN="$T/claude-stub.py" STUB_LOG="$T/critic-call.json" "$E" critic "$T/reg-good.json" --scope regatta --require-model --json > "$T/critic-ok.json"; check "$?" 0 \
  "evolve critic passes a sound finding through deterministic checks and gate evolve.critic"
check "$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print("--model" in d["args"], "claude-sonnet-5-5" in d["args"], "owner_minutes" in d["prompt"])' "$T/critic-call.json")" \
  "True True False" "  uses claude-sonnet-5-5 from models.json and strips owner_minutes preferences from the cold packet"
CLAUDE_BIN="$T/claude-stub.py" CRITIC_MODE=drop "$E" critic "$T/reg-good.json" --scope regatta --json > "$T/critic-drop.json"; check "$?" 1 \
  "  a finding dropped by the blinded critic exits 1 and names its reason"

# Deterministic refusals: blind_spot without sensor, strength with n < 5, missing counterevidence on build
python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
f = d["findings"][0]
f["kind"] = "blind_spot"
f["intervention"] = "Remind people in prose"
f["acceptance_check"] = "looks better"
f["counterevidence"] = ""
json.dump(d, open(sys.argv[2], "w"))
' "$T/reg-good.json" "$T/reg-bad-critic.json"
GATE_EVOLVE_CRITIC_PROVIDER=off "$E" critic "$T/reg-bad-critic.json" --scope regatta --json > "$T/det-bad.json"; rc=$?
check "$rc $(j 'len(d["deterministic"]) >= 2' < "$T/det-bad.json")" "1 True" \
  "  deterministic checks catch a blind_spot without a sensor and a build without counterevidence even when the model is off"

# Confidential vendor guard on evolve.critic
MARK="confidential:$(printf clientx | python3 -c 'import hashlib,sys; print(hashlib.sha256(sys.stdin.read().encode()).hexdigest()[:8])')"
python3 "$T/mk_finding.py" "$D/lib" "$MARK" secret_milestone 2026-11-06 2026-W45 "$T/conf-good.json"
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); d["findings"][0]["privacy_class"]="confidential"; json.dump(d, open(sys.argv[1],"w"))' "$T/conf-good.json"
GATE_EVOLVE_CRITIC_PROVIDER=codex CLAUDE_BIN="$T/claude-stub.py" "$E" critic "$T/conf-good.json" --scope clientx > /dev/null 2>&1
check "$?" 2 "  non-claude provider on evolve.critic is refused (exit 2) for a confidential scope"

# ---- 6. evolve record: regatta records branch + plumb export, quiet earned, due benefit check wake ---------
echo 'evolve record — open scope records branch, $ASKS_FINDINGS -> plumb asks, quiet earned and due-check wake'
"$E" open regatta --day 2026-11-06 > /dev/null
mkdir -p "$P/regatta-repo/evolve"
cp "$T/reg-good.json" "$P/regatta-repo/evolve/2026-11-06.findings.json"
printf '# Evolve — regatta — 2026-11-06\n\nOne validated finding.\n' > "$P/regatta-repo/evolve/2026-11-06.md"
"$E" record regatta --day 2026-11-06 --cost 0.42 > "$T/rec-reg.txt"; check "$?" 0 "evolve record regatta lands complete (exit 0)"
br=$("$E" where regatta --day 2026-11-06 | sed -n 's/^records-branch //p')
check "$(git -C "$P/regatta-repo" cat-file -t "$br:evolve/2026-11-06.findings.json") $([ ! -e "$P/regatta-repo/evolve/2026-11-06.findings.json" ] && echo cleaned)" \
  "blob cleaned" "  committed on records-branch via git plumbing and untracked working-tree copy removed"
git -C "$P/regatta-repo" show "$br:evolve/2026-11-06-receipt.json" > "$T/reg-rc.json"
"$E" validate receipt "$T/reg-rc.json" --quiet; check "$?" 0 "  committed evolve/<day>-receipt.json validates against RECEIPT schema"
check "$([ -f "$ASKS_FINDINGS/regatta-2026-11-06.json" ] && echo exported)" "exported" "  open scope findings exported to \$ASKS_FINDINGS"
# Verify plumb's asks load_findings() reads the exported file and formats 3-family status
check "$(ASKS_FINDINGS="$ASKS_FINDINGS" ASKS_STATE="$T/asks-st" python3 -c '
from importlib.machinery import SourceFileLoader
m = SourceFileLoader("asks", "'"$ASKS"'").load_module()
fs = m.load_findings()
st = fs[0]["status"]
st_word = (st.get("proposal") or "proposed") if isinstance(st, dict) else st
print(len(fs), fs[0]["id"], st_word)
')" "1 regatta-cut-cadence proposed" "  plumb/bin/asks loads the exported S5 finding list and reads its 3-family status"

# Quiet receipt earned on unchanged scope
"$E" open regatta --day 2026-11-07 --quiet-exit --json > "$T/q-earned.json"; check "$?" 3 \
  "unchanged scope with fresh collector receipts and 0 due checks earns quiet at \$0 (exit 3)"
check "$(j 'd["receipt"]["receipt"], d["receipt"]["cost_usd"]' < "$T/q-earned.json") $(grep -c '2026-11-07 evolve --scope regatta: quiet' "$P/vault-repo/log.md")" \
  "('quiet', 0.0) 1" "  writes valid quiet receipt at cost 0.0 and logs quiet in vault/log.md"

# Merge a routed finding with due benefit_check <= 2026-12-05 and verify quiet is refused on 2026-12-05
git -C "$P/regatta-repo" merge -q --ff-only "$br"
python3 -c '
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d["findings"][0]["status"] = {"proposal": "routed", "execution": "shipped", "outcome": "pending"}
d["findings"][0]["benefit_check"] = {"check": "0 broken reels", "due": "2026-12-04"}
json.dump(d, open(p, "w"), indent=1)
' "$P/regatta-repo/evolve/2026-11-06.findings.json"
git -C "$P/regatta-repo" commit -qam "routed finding shipped"
"$E" open regatta --day 2026-11-08 > /dev/null
"$E" coverage --scope regatta --promote > /dev/null
printf '{"time": "%s"}\n' "$(now)" > "$EVOLVE_STATE/receipts/regatta/week-digest.json"
op_due=$("$E" open regatta --day 2026-12-05 --quiet-exit --json); rc_due=$?
check "$rc_due $(echo "$op_due" | j 'len(d["reconciled"]["due_checks"]), d["quiet_ok"]')" "0 (1, False)" \
  "a due benefit_check wakes the pass: quiet refused (exit 0, not 3) and reconciled lists the due check"

# ---- 7. atlas records: staged outside <vault> and <layer>, committed into <vault>/evolve/ ------------------
echo "atlas pass — staged outside <vault>, committed into <vault>/evolve/, <layer> untouched"
stg_a=$("$E" where atlas --day 2026-11-06 | sed -n 's/^staging //p')
stg_loc=outside
case "$stg_a" in
  "$P/vault-repo"*|"$P/layer-repo"*) stg_loc=bad ;;
esac
check "$stg_loc" "outside" \
  "atlas staging dir sits outside both <vault> and <layer>"
mkdir -p "$stg_a/evolve"
python3 "$T/mk_finding.py" "$D/lib" atlas code 2026-11-06 2026-W45 "$stg_a/evolve/2026-11-06.findings.json"
printf '# Evolve — atlas — 2026-11-06\n\nKnowledge pass.\n' > "$stg_a/evolve/2026-11-06.md"
layer_head_before=$(git -C "$P/layer-repo" rev-parse HEAD)
"$E" record atlas --day 2026-11-06 > /dev/null; check "$?" 0 "evolve record atlas commits into <vault>/evolve/ (exit 0)"
check "$(git -C "$P/vault-repo" cat-file -t HEAD:evolve/2026-11-06.findings.json) $([ ! -d "$stg_a" ] && echo cleaned) $(git -C "$P/layer-repo" status --porcelain | wc -l | tr -d ' ')" \
  "blob cleaned 0" "  committed on <vault> main, staging cleaned, <layer> completely untouched ($([ "$(git -C "$P/layer-repo" rev-parse HEAD)" = "$layer_head_before" ] && echo same-head))"

# ---- 8. Confidential scope: export gate required, held on leak, never exported to $ASKS_FINDINGS -----------
echo "confidential scope — export gate enforced, held on words.txt hit, never exported to \$ASKS_FINDINGS"
mkdir -p "$P/secret-node/evolve"
cp "$T/conf-good.json" "$P/secret-node/evolve/2026-11-06.findings.json"
printf '# Evolve — confidential — 2026-11-06\n' > "$P/secret-node/evolve/2026-11-06.md"
"$E" record clientx --day 2026-11-06 > /dev/null 2>&1; check "$?" 1 \
  "confidential scope without dreams/<day>-upstream.md is refused (never bypasses scope-pass export gate)"
printf '# Dream — 2026-11-06\nInternal note on ACMECORP.\n' > "$P/secret-node/dreams/2026-11-06.md"
printf '# Upstream — 2026-11-06\n\nU1. ACMECORP taught us to fence paths — rules/engineering.md\n' > "$P/secret-node/dreams/2026-11-06-upstream.md"
CLAUDE_BIN="$T/claude-stub.py" "$E" record clientx --day 2026-11-06 > /dev/null 2>&1; check "$?" 3 \
  "confidential upstream draft naming a words.txt term exits 3 (held)"
check "$(ls "$ASKS_FINDINGS" | grep -ic 'clientx\|secret\|confidential')" 0 "  held confidential pass writes nothing to \$ASKS_FINDINGS"
printf '# Upstream — 2026-11-06\n\nU1. Validate schemas before export — rules/engineering.md\n' > "$P/secret-node/dreams/2026-11-06-upstream.md"
CLAUDE_BIN="$T/claude-stub.py" "$E" record clientx --day 2026-11-06 > /dev/null; check "$?" 0 \
  "clean confidential draft passes scan + scope.upstream judge and records complete (exit 0)"
check "$(ls "$ASKS_FINDINGS" | grep -ic 'clientx\|secret\|confidential')" 0 "  completed confidential pass STILL writes nothing to \$ASKS_FINDINGS"

# ---- 9. templates/meeting.md & evolve meetings (committed notes only) --------------------------------------
echo "evolve meetings — templates/meeting.md, committed notes only, recordings refused"
check "$([ -f "$D/skills/aurora/templates/meeting.md" ] && echo present)" "present" "templates/meeting.md exists"
mkdir -p "$P/layer-repo/meetings"
cp "$D/skills/aurora/templates/meeting.md" "$P/layer-repo/meetings/untracked.md"
sed -i.bak 's/Read before: no/Read before: yes/' "$P/layer-repo/meetings/untracked.md"; rm -f "$P/layer-repo/meetings/untracked.md.bak"
m0=$("$E" meetings --scope atlas --json); rc_m0=$?
check "$rc_m0 $(echo "$m0" | j 'd["state"], d["meetings"], d["uncommitted_ignored"]')" "1 ('source_missing', 0, 1)" \
  "uncommitted meeting note is ignored (source_missing, never read before commit)"
rm -f "$P/layer-repo/meetings/untracked.md"
cat > "$P/layer-repo/meetings/2026-11-04-sync.md" <<'MD'
# Meeting — 2026-11-04 — Architecture sync
Date: 2026-11-04
Read before: no

## Pre-brief
- **Outcome needed:** settle schema fields

## After-action
- **Settled:** 3-family status

## Commitments
- If coverage shows unread cells, then wire the source in evolve-scope.md — due: none · Confirmed: pending
- If shadow wall time exceeds 2400s, then split lenses into two sessions — due: 2026-11-15 · Confirmed: yes
MD
git -C "$P/layer-repo" add meetings/2026-11-04-sync.md; git -C "$P/layer-repo" commit -qm "commit meeting note"
m1=$("$E" meetings --scope atlas --json); rc_m1=$?
check "$rc_m1 $(echo "$m1" | j 'd["meetings"], d["prebriefs_read"], d["commitments"], d["undated_commitments"], d["unconfirmed_commitments"]')" \
  "1 (1, 0, 2, 1, 1)" "committed note parsed: 1 meeting, 0 pre-briefs read, 1 undated and 1 unconfirmed commitment (exit 1)"
sed -i.bak 's/Read before: no/Read before: yes/; s/due: none/due: 2026-11-10/' "$P/layer-repo/meetings/2026-11-04-sync.md"
rm -f "$P/layer-repo/meetings/2026-11-04-sync.md.bak"
git -C "$P/layer-repo" commit -qam "read pre-brief and date commitment"
"$E" meetings --scope atlas --json > "$T/m2.json"; check "$?" 0 "pre-brief read and all commitments dated -> exit 0"
printf 'audio\n' > "$P/layer-repo/meetings/call.m4a"
"$E" meetings --scope atlas --json > "$T/m3.json"; rc_m3=$?
rm -f "$P/layer-repo/meetings/call.m4a"
check "$rc_m3 $(j 'd["recordings_refused"]' < "$T/m3.json")" "1 1" "a recording file (.m4a) in meetings/ is refused without opening"

# ---- 10. Hidden-future replay & canary leak detection ------------------------------------------------------
echo "evolve replay — future masking, E recall + negative lead_days, N/J separation, canary leak detection"
cat > "$T/replay-asks.jsonl" <<'JL'
{"id": "a0", "date": "2026-10-25", "ts": "2026-10-25T10:00:00Z", "week": "2026-W43", "project": "regatta-repo", "session": "s0", "sieve": "ask", "target": "system", "detect": "E", "theme": "cut-cadence"}
{"id": "a1", "date": "2026-11-11", "ts": "2026-11-11T10:00:00Z", "week": "2026-W46", "project": "regatta-repo", "session": "s1", "sieve": "ask", "target": "system", "detect": "E", "theme": "cut-cadence"}
{"id": "a2", "date": "2026-11-14", "ts": "2026-11-14T10:00:00Z", "week": "2026-W46", "project": "regatta-repo", "session": "s2", "sieve": "ask", "target": "system", "detect": "E", "theme": "unseen-gap"}
{"id": "a3", "date": "2026-11-15", "ts": "2026-11-15T10:00:00Z", "week": "2026-W46", "project": "regatta-repo", "session": "s3", "sieve": "ask", "target": "system", "detect": "N", "theme": "backlog-item"}
{"id": "a4", "date": "2026-11-16", "ts": "2026-11-16T10:00:00Z", "week": "2026-W46", "project": "regatta-repo", "session": "s4", "sieve": "ask", "target": "system", "detect": "J", "theme": "taste-call"}
JL
rep=$("$E" replay --cutoff 2026-11-06 --asks "$T/replay-asks.jsonl" --findings "$T/reg-good.json" --window 28 --json); rc_r=$?
check "$rc_r $(echo "$rep" | j 'd["canary_leak"], d["past_asks_visible"], d["future_e_asks"], d["anticipated_e"], d["recall_e"], d["backlog_n"], d["excluded_j"], d["median_lead_days"]')" \
  "0 (False, 1, 2, 1, 0.5, 1, 1, -5)" \
  "replay at 2026-11-06: 1/2 E anticipated (recall 0.5, lead -5d), 1 N backlog, 1 J excluded, canary_leak=False"
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); d["findings"][0]["evidence_refs"][0]["time"]="2026-11-12T00:00:00Z"; json.dump(d,open(sys.argv[2],"w"))' "$T/reg-good.json" "$T/reg-leak.json"
"$E" replay --cutoff 2026-11-06 --asks "$T/replay-asks.jsonl" --findings "$T/reg-leak.json" --json > "$T/rep-leak.json"; rc_lk=$?
check "$rc_lk $(j 'd["canary_leak"]' < "$T/rep-leak.json")" "1 True" "post-cutoff evidence timestamp in a finding is caught as canary_leak (exit 1)"

# ---- 11. Shadow runs on regatta (code), atlas (knowledge/vault) and film (non-code) ------------------------
echo "evolve shadow — regatta, atlas and film non-destructive shadow passes"
printf '{"not_applicable": ["commercial"]}\n' > "$REGATTA_CONFIG/aurora/scopes/atlas.json"
for sc in regatta atlas film; do
  GATE_EVOLVE_CRITIC_PROVIDER=off "$E" shadow --scope "$sc" --day 2026-11-06 --out "$T/sh-$sc" --json > "$T/sh-$sc.json"; rc_s=$?
  "$E" validate findings "$T/sh-$sc/evolve/2026-11-06.findings.json" --scope "$sc" --quiet; rc_v=$?
  check "$rc_s $rc_v $(j 'd["split_needed"], d["findings_count"] == d["findings_with_check"] and d["findings_count"] <= 5' < "$T/sh-$sc.json")" \
    "0 0 (False, True)" "shadow pass on $sc: valid findings (<= 5, every one with a runnable check), split_needed=False"
done

# ---- 12. The landing review's fixes (S5's finish, 2026-11-07) ----------------------------------------------
echo "landing review — own session from the environment, --if-drafted, guarded critic, global runs, confidential receipt"
CLAUDE_CODE_SESSION_ID=pass-s5-env "$E" open film --day 2026-11-20 --json > /dev/null
check "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("pass_session"))' "$EVOLVE_STATE/manifests/film.opening.json")" \
  "pass-s5-env" "open takes the pass's own session from CLAUDE_CODE_SESSION_ID, so its transcript never wakes next week"
out=$("$E" record film --day 2026-12-04 --if-drafted 2>&1); rc=$?
check "$rc $(printf '%s' "$out" | grep -c 'nothing drafted')" "0 1" "record --if-drafted with nothing drafted: exit 0, one line (weekly-run's fallback)"

cp "$REGATTA_CONFIG/regatta/guarded" "$T/guarded.keep"
printf 'regatta-repo\n' > "$REGATTA_CONFIG/regatta/guarded"
rm -f "$T/critic-guarded.json"
CLAUDE_BIN="$T/claude-stub.py" STUB_LOG="$T/critic-guarded.json" "$E" critic "$T/reg-good.json" --scope regatta --json > "$T/crit-g.json"
check "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["meta"]["gate"])' "$T/crit-g.json" 2>/dev/null) $([ -f "$T/critic-guarded.json" ] && echo sent || echo unsent)" \
  "skipped unsent" "a guarded scope's findings never reach the critic's model without the owner's quote (gate.vet, every vendor)"
CLAUDE_BIN="$T/claude-stub.py" "$E" critic "$T/reg-good.json" --scope regatta --require-model > /dev/null 2>&1
check "$?" 2 "  with --require-model the guarded scope is refused"
rm -f "$T/critic-guarded2.json"
CLAUDE_BIN="$T/claude-stub.py" STUB_LOG="$T/critic-guarded2.json" "$E" critic "$T/reg-good.json" --json > /dev/null
check "$([ -f "$T/critic-guarded2.json" ] && echo sent || echo unsent)" unsent "  with no --scope the file's own scope is judged, and its guarded source is not sent"
CLAUDE_BIN="$T/claude-stub.py" "$E" critic "$T/reg-good.json" --scope film --json > /dev/null 2>&1
check "$?" 2 "  a --scope other than the file's own is refused"
cp "$T/guarded.keep" "$REGATTA_CONFIG/regatta/guarded"
GATE_LOG="$T/gate-critic.jsonl" CLAUDE_BIN="$T/claude-stub.py" "$E" critic "$T/reg-good.json" --scope regatta --json > /dev/null
check "$(grep -c '"site": "evolve.critic"' "$T/gate-critic.jsonl" 2>/dev/null)" 1 "  each critic call writes one gate.jsonl row, so the meters see its spend"

# a confidential scope's profile is the config dir's alone, in every run (the round-2 leak: a global run that
# skipped the anchor's copy left its {log} file unfenced and named it). Declared there, the file is fenced, never named;
# a torn copy in the anchor is never read, by the scope's own run either.
cp "$REGATTA_CONFIG/aurora/scopes/clientx.json" "$T/clientx-prof.keep"
cat > "$REGATTA_CONFIG/aurora/scopes/clientx.json" <<'J'
{"outcome_classes": {"secret_milestone": {"observation_days": 14}},
 "sources": [{"id": "secret-ledger", "lens": "product", "kind": "path", "at": "{log}/ACMECORP-ledger.jsonl", "fresh_days": 14, "reader": "pass"}]}
J
printf '{"time": "%s"}\n' "$(now)" > "$L/ACMECORP-ledger.jsonl"
"$E" coverage --no-record > "$T/glob-cov.txt" 2>&1
check "$(grep -c ACMECORP "$T/glob-cov.txt")" 0 "a global coverage run fences, never names, a file a confidential scope's profile declares"
printf '{"sources": "not a list"}\n' > "$P/secret-node/.claude/evolve-scope.json"
"$E" coverage --scope clientx --no-record > "$T/own-cov.txt" 2>&1
check "$(grep -c 'cannot be read' "$T/own-cov.txt")" 0 "  a torn profile in the confidential anchor is never read, by its own run either"
rm -f "$P/secret-node/.claude/evolve-scope.json" "$L/ACMECORP-ledger.jsonl"
cp "$T/clientx-prof.keep" "$REGATTA_CONFIG/aurora/scopes/clientx.json"

cat > "$T/vcommit-noop.sh" <<'SH'
#!/usr/bin/env bash
exit 0
SH
chmod +x "$T/vcommit-noop.sh"
python3 "$T/mk_finding.py" "$D/lib" "$MARK" secret_milestone 2026-11-13 2026-W46 "$P/secret-node/evolve/2026-11-13.findings.json"
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); d["findings"][0]["privacy_class"]="confidential"; json.dump(d, open(sys.argv[1],"w"))' "$P/secret-node/evolve/2026-11-13.findings.json"
printf '# Evolve — confidential — 2026-11-13\n' > "$P/secret-node/evolve/2026-11-13.md"
printf '# Dream — 2026-11-13\nA note.\n' > "$P/secret-node/dreams/2026-11-13.md"
printf '# Upstream — 2026-11-13\n\nU1. Validate schemas before export — rules/engineering.md\n' > "$P/secret-node/dreams/2026-11-13-upstream.md"
out=$(SCOPE_PASS_COMMIT="$T/vcommit-noop.sh" CLAUDE_BIN="$T/claude-stub.py" "$E" record clientx --day 2026-11-13 2>&1); rc=$?
printf '%s\n' "$out" > "$T/conf-noop.out"
check "$rc $(printf '%s' "$out" | grep -c 'does not verify')" "1 1" "a confidential scope whose export receipt does not verify is never recorded complete"
check "$([ -f "$EVOLVE_STATE/receipts/$(printf '%s' "$MARK" | tr ':' '-')/2026-11-13-receipt.json" ] && echo written || echo none)" none \
  "  and no receipt is written for it"

echo; [ "$fails" -eq 0 ] && echo "evolve-pass: all ok" || { echo "evolve-pass: $fails failed"; exit 1; }
