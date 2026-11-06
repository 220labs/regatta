#!/usr/bin/env bash
# Landing questions in build digests. No server, network or caller HOME/config state.
set -eu
B="$(cd "$(dirname "$0")/../bin" && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export HOME="$T/home" REGATTA_CONFIG="$T/config" PYTHONDONTWRITEBYTECODE=1
mkdir -p "$HOME" "$REGATTA_CONFIG"
unset CLAUDE_UNATTENDED REGATTA_UNATTENDED CLAUDE_CODE_DISABLE_BACKGROUND_TASKS DISPATCH_BRIEF
. "$B/../tests/config.sh"; keel_config "$T/config"
python3 - "$B/keel" "$T" <<'PY'
import importlib.machinery, os, subprocess, sys
from pathlib import Path
k = importlib.machinery.SourceFileLoader("keel_landing", sys.argv[1]).load_module()
doc = Path(sys.argv[2]) / "digest.md"
count = 0
def check(value, label):
    global count
    assert value, label
    count += 1
    print("  ok   " + label)
def text(title, head="# Example — build digest"):
    return head + "\n\n- **D1 — " + title + ".**\n  - A — one\n  - B — two\n  Reversible: yes\n  ➤ Recommended: A\n  ➤ Answer:\n"
for title in ("Land this branch", "Launch it", "Finish this run", "Should we merge this build"):
    doc.write_text(text(title))
    r = subprocess.run([sys.argv[1], "lint", str(doc)], capture_output=True, text=True)
    check(r.returncode == 1 and "landing this build is the hand-over's work" in r.stdout, "lint refuses: " + title)
for title in ("Launch the product", "Finish the migration", "Land another-branch"):
    check(not k.lint(text(title))[0], "keeps a real decision: " + title)
check(not k.lint(text("Land this branch", "# Example — design"))[0], "attended design lint unchanged")
check(not k.lint(text("Ship it", "# Billing — build plan"))[0], "a '— build plan' heading is no build digest")
check(not k.lint(text("Land this branch", "# Billing — build plan"))[0], "an attended doc that is no build digest keeps its rules")
check(not k.landing_subject("Launch beacon (A now / B after review)", "claude/h/2026-11-04-beacon", implicit=False),
      "a product named like the branch topic, launched in a design doc, stays a decision")
check(not k.landing_subject("Merge the branch (A squash / B rebase)", "claude/h/2026-11-04-ci", implicit=False),
      "a generic 'the branch' outside a build digest is a merge-strategy decision")
check(k.landing_subject("Land ci (A now / B hold)", "claude/h/2026-11-04-ci", implicit=False), "landing the branch's own topic counts in any doc")
os.environ.update(DISPATCH_BRIEF="fixture", REGATTA_UNATTENDED="dispatch")
check(k.lint(text("Land this branch", "# Example"))[0], "dispatch marker catches a build with no digest heading")
check(not k.lint(text("Ship it", "# Product — design"))[0], "a dispatched design's product launch question stands")
os.environ.pop("DISPATCH_BRIEF")
check(not k.landing_subject("Launch it (a public release to customers)", "claude/x/2026-11-05-demo"),
      "a parenthesised qualifier is no option list: the launch stays a product decision")
check(k.landing_subject("Land demo (A land now / B hold)", "claude/x/2026-11-05-demo"), "an (A … / B …) option list is stripped")
print("landing lint: %d checks, all passed" % count)
PY
