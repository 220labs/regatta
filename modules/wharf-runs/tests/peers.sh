#!/usr/bin/env bash
# The optional peers' absent cases (the design's G12, G22) and the hard ones named, never a stack
# trace: wharf-runs beside the core and wharf only, a config naming no legacy checkout, so keel,
# lighthouse's account, plumb's tier_check and helm are all absent. Scratch paths only.
#   bash modules/wharf-runs/tests/peers.sh
set -u
M="$(cd "$(dirname "$0")/.." && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fails=0
check() { if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3: expected [$2] got [$1]"; fails=$((fails+1)); fi; }
has()   { case "$1" in *"$2"*) echo "  ok   $3";; *) echo "  FAIL $3: [$2] not in [${1:0:300}]"; fails=$((fails+1));; esac; }
mkdir -p "$T/tree/.claude-plugin" "$T/tree/modules" "$T/cfg" "$T/claude" "$T/home"; : > "$T/tree/.claude-plugin/marketplace.json"
cp -R "$M/../regatta" "$T/tree/modules/regatta"; cp -R "$M/../wharf" "$T/tree/modules/wharf"; cp -R "$M" "$T/tree/modules/wharf-runs"
R="$T/tree/modules/wharf-runs"
E() { env -u REGATTA_HOME -u REGATTA_LEGACY -u CLAUDE_CODE_OAUTH_TOKEN -u AUTOFINISH_ACCOUNT -u DISPATCH_ACCOUNT -u DISPATCH_ASK -u DISPATCH_HELM \
  REGATTA_CONFIG="$T/cfg" CLAUDE_CONFIG_DIR="$T/claude" HOME="$T/home" CLAUDE_REPOS_JSON="$T/repos.json" "$@"; }
echo '{"repos": {}}' > "$T/repos.json"
# a bin/ file loaded as its callers load it (no .py, a dash): name, then a statement on it as `m`
load() { E python3 -c 'import importlib.machinery as im, importlib.util as iu, sys
l = im.SourceFileLoader(sys.argv[1].replace("-", "_"), sys.argv[2]); m = iu.module_from_spec(iu.spec_from_loader(l.name, l)); l.exec_module(m)
exec(sys.argv[3])' "$1" "$R/bin/$1" "$2" 2>&1; }

echo "peers absent: wharf-runs beside the core and wharf"
check "$(load autofinish 'print([m.common.tool(n) for n in ("keel", "account", "tier_check.py", "helmlib.py", "ask", "helm")])')" \
      "[None, None, None, None, None, None]" "no peer is found"
check "$(load pickup 'print(m.ACCOUNT, m.account_for("/x", {}, type("A", (), {"account": "auto", "dry_run": True})(), True))')" \
      "None (None, {}, None)" "G12: pickup with no account tool starts on the one login"
check "$(load pickup 'import sys
try:
    m.named_account("claude-x", False, True)
except m.Stop as e:
    print(e)')" "--account claude-x: no account tool here (lighthouse is not installed) — nothing was opened" \
      "  --account LABEL without it: refused, said so"
check "$(load autofinish-run 'import os; os.environ.pop("CLAUDE_CONFIG_DIR", None); print(m.ACCOUNT, m.account_pick(type("T", (), {"primary": "/x"})()))')" \
      "None (None, None, 'no account tool (lighthouse not installed) — the login this run was started with')" \
      "G12: autofinish-run with no account tool keeps the login it was started with"
check "$(load autofinish 'print(m.memo_status("/tmp", "x.md"), m.account("pick")[0])')" "None None" \
      "  autofinish: no keel, no D-list verdict; no account, no pick — neither raises"
check "$(load autofinish 'print(m.default_week())')" "(False, None)" "  …and no tier_check: the week reads as not tight"

echo "G22: dispatch with no helm — its lookup (the prompt case is test_dispatch.sh's)"
mkdir -p "$T/stub"; printf '#!/bin/sh\necho "$*" >> "%s/claude.calls"\n' "$T" > "$T/stub/claude"; chmod +x "$T/stub/claude"
check "$(E bash -c 'here="$(cd "$(dirname "$1")/.." && pwd)"; eval "$(sed -n "/^core=\"\"; legacy=/,/^)\"$/p" "$1")"; echo "core=${core:+found} ask=[$p_ask] helm=[$p_helm] keel=[$p_keel] account=[$p_account]"' sh "$R/bin/dispatch" 2>&1 | sed "s|$T|T|g")" \
      "core=found ask=[] helm=[] keel=[] account=[]" "dispatch's lookup: the core found, every optional peer empty"

echo "the core missing: one line, never a traceback"
mkdir -p "$T/alone/modules"; cp -R "$M" "$T/alone/modules/wharf-runs"
for t in autofinish autofinish-run pickup wharf; do
  out=$(E python3 "$T/alone/modules/wharf-runs/bin/$t" --help 2>&1); rc=$?
  check "$rc $(printf '%s' "$out" | grep -c Traceback)" "2 0" "$t without the core: exit 2, no traceback"
done
out=$(E bash "$T/alone/modules/wharf-runs/bin/dispatch" --status 2>&1); rc=$?
check "$rc" "2" "dispatch without the core: exit 2"
has "$out" "the regatta core is missing" "  saying so"
out=$(echo '{"prompt": "/finish"}' | E python3 "$T/alone/modules/wharf-runs/hooks/cold_prompt.py" 2>&1); rc=$?
check "$rc" "0" "cold_prompt (a UserPromptSubmit hook) without the core: exit 0, the prompt passes"
has "$out" "regatta core not found" "  one line on stderr"

echo; [ $fails -eq 0 ] && echo "all passed" || { echo "$fails FAILED"; exit 1; }
