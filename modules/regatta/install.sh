#!/bin/sh
# The core's shell face: name this clone in ${REGATTA_CONFIG:-~/.config/regatta}/home, which every
# shim and script reads to find the core. --check: `regatta check`. --remove: the home file goes.
set -eu
here=$(cd "$(dirname "$0")/../.." && pwd)
# The main checkout, never a linked worktree: /finish removes a worktree, and every hook would
# then fail "core missing". A worktree's install.sh names the clone it belongs to.
common=$(git -C "$here" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
[ -n "$common" ] && [ "$(basename "$common")" = .git ] && here=$(dirname "$common")
cfg=${REGATTA_CONFIG:-$HOME/.config/regatta}
case "${1:-}" in
  --check) exec "$here/modules/regatta/bin/regatta" check ;;
  --remove)
    if [ "$(head -1 "$cfg/home" 2>/dev/null)" = "$here" ]; then rm -f "$cfg/home"; echo "removed $cfg/home"
    else echo "left $cfg/home: it names another clone, not $here" >&2; fi ;;
  "") mkdir -p "$cfg"; printf '%s\n' "$here" > "$cfg/home"; echo "$cfg/home → $here" ;;
  *) echo "usage: install.sh [--check | --remove]" >&2; exit 2 ;;
esac
