#!/bin/sh
# lighthouse's shell face. Nothing to install beyond the plugin (its bin/ is on the Bash PATH
# while enabled, its hooks in hooks/hooks.json); `cc` is one line in the shell's rc file, which
# this prints. --check: the core, each private value lighthouse reads (README, "Private values")
# and each optional peer, found or not. --remove: nothing to remove outside the plugin.
# The daily `health` job is the installer's own schedule (an overlay's launchd plist).
set -eu
here=$(cd "$(dirname "$0")" && pwd)
case "${1:-}" in
  --check)
    python3 - "$here" <<'PY'
import sys
sys.path.insert(0, sys.argv[1] + "/lib")
import find_core
sys.path.insert(0, find_core.hooks())
import common
print("core:     %s" % common.__file__)
for k in ("accounts.json", "logins.json", "user.json", "env-keys.json", "hosts", "vault", "vaults",
          "gated-tools", "ff", "design-host", "cc-prefix", "shares", "nas", "drive", "yabairc"):
    p = common.CONFIG / "lighthouse" / k
    print("%-9s %s" % ("ok" if p.exists() else "--", "lighthouse/" + k + ("" if p.exists() else " (absent: its default)")))
for t in ("fork_claude_session.py", "worktree_allow.py", "tend", "sync.py", "rc-hosts", "bulletin.py",
          "knowledge-commit", "usage-report"):
    print("%-9s %s" % ("peer" if common.tool(t) else "--", t + ("" if common.tool(t) else " not installed: its verb says so")))
PY
    ;;
  "") echo "lighthouse: nothing to install outside the plugin; for cc, add to the shell's rc file: . '$here/shell/cc.zsh'" ;;
  --remove) echo "lighthouse: nothing to remove outside the plugin" ;;
  *) echo "usage: install.sh [--check | --remove]" >&2; exit 2 ;;
esac
