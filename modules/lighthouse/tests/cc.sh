#!/usr/bin/env bash
# Tests for shell/cc.zsh and `account run` — a scratch HOME and config dir, a fixture registry, a
# stub claude. zsh and Apple clang (the fall-through case): macOS only.
#   bash modules/lighthouse/tests/cc.sh
set -u
if [ "$(uname)" != Darwin ] || ! command -v zsh >/dev/null; then echo "  skip: cc.zsh needs zsh and Apple clang (macOS)"; exit 0; fi
unset REGATTA_HOME REGATTA_LEGACY
M="$(cd "$(dirname "$0")/.." && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export REGATTA_CONFIG="$T/config"; mkdir -p "$REGATTA_CONFIG/lighthouse"; echo seat- > "$REGATTA_CONFIG/lighthouse/cc-prefix"
fails=0
check() { if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3: expected [$2] got [$1]"; fails=$((fails+1)); fi; }

# HOME is the scratch dir: bin/account's Path.home() and cc.zsh's $HOME both read it, so the
# default dir is $T/.claude.
mkdir -p "$T/projects/privy/sub" "$T/projects/other" "$T/bin" "$T/.claude-w" "$T/a b"
cat > "$T/accounts.json" <<'EOF'
{"accounts": [
  {"label": "seat-w", "provider": "claude", "home": "~/.claude-w", "repos": {"deny": ["privy"]}},
  {"label": "seat-s", "provider": "claude", "home": "~/a b"},
  {"label": "seat-f", "provider": "claude", "home": "~/.claude-f", "enabled": false},
  {"label": "seat-p", "provider": "claude", "home": "~/.claude", "primary": true}],
 "capabilities": {}}
EOF
printf '#!/bin/sh\necho "dir=[${CLAUDE_CONFIG_DIR-unset}] tok=[${CLAUDE_CODE_OAUTH_TOKEN-unset}] n=$# args=[$*]"\n' > "$T/bin/claude"
chmod +x "$T/bin/claude"

run() {  # run <cwd> <cc args…>: an interactive-free zsh with only cc.zsh sourced
  local cwd="$1"; shift
  (cd "$cwd" && HOME="$T" ACCOUNTS_FILE="$T/accounts.json" PATH="$T/bin:$PATH" \
     CLAUDE_CONFIG_DIR=/inherited CLAUDE_CODE_OAUTH_TOKEN=leak \
     zsh -fc '. "$1"; shift; cc "$@"' cc "$M/shell/cc.zsh" "$@" 2>&1)
}

check "$(run "$T/projects/other" w --continue 'b c' '')" "dir=[$T/.claude-w] tok=[unset] n=3 args=[--continue b c ]" \
  "cc w: seat-w's dir (the cc-prefix key), args intact, the inherited token dropped"
check "$(run "$T/projects/other" p -p hi)" "dir=[unset] tok=[unset] n=2 args=[-p hi]" \
  "cc p: the default dir runs with CLAUDE_CONFIG_DIR unset"
check "$(run "$T/projects/other" s)" "dir=[$T/a b] tok=[unset] n=0 args=[]" \
  "cc s: a home with a space reaches claude whole"
out=$(run "$T/projects/privy/sub" w); rc=$?
check "$rc $out" "1 account: privy is off seat-w (accounts.json deny list)" \
  "cc w inside a denied repo: refused, claude never starts"
check "$(run "$T/projects/privy/sub" p x | cut -c1-11)" "dir=[unset]" \
  "cc p inside the same repo: the primary has no deny list"
check "$(run "$T/projects/other" q; echo "rc=$?")" "account: no account 'seat-q' in $T/accounts.json
rc=1" \
  "cc q: an unknown label names the registry and fails"
check "$(run "$T/projects/other" f; echo "rc=$?")" "account: seat-f is disabled in $T/accounts.json
rc=1" \
  "cc f: a disabled row is refused, claude never starts"
rm "$REGATTA_CONFIG/lighthouse/cc-prefix"
check "$(run "$T/projects/other" q; echo "rc=$?")" "account: no account 'q' in $T/accounts.json
rc=1" \
  "no cc-prefix key: the letter is the label"
check "$(run "$T/projects/other" --version | head -1 | grep -c clang)" 1 \
  "cc --version: falls through to the C compiler"

[ "$fails" -eq 0 ] && echo "all ok" || { echo "$fails failed"; exit 1; }
