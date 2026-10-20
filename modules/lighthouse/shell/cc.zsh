# cc — start Claude Code on a chosen login: `cc w`, `cc p`, then any claude args.
#
# Sourced from the shell's rc file (an overlay's bootstrap.sh writes the line; a stranger adds
# `. <this file>` by hand). A function, not a file in bin/, because `cc` is the C compiler: on PATH
# it would shadow /usr/bin/cc for make and every build. A function lives only in the interactive
# shell, and anything but a one-character first word falls through to the real compiler — no
# compiler call starts with one.
#
# `cc X` is `account run <prefix>X`, the prefix the config dir's `lighthouse/cc-prefix` (none
# without it: `cc w` runs the row labelled `w`): the label, the env (an inherited
# CLAUDE_CONFIG_DIR and CLAUDE_CODE_OAUTH_TOKEN dropped) and the deny-list and disabled-row
# refusals all live in bin/account, so a row added to the registry is reachable here with no edit.
# It replaces the hand-pick `cswap switch` did, which moved the default dir's own login and with it
# every panel, Remote Control host and routine (2026-10-07). bin/account is this module's, found
# from this file's own path when it is sourced.
typeset -g _LIGHTHOUSE_ACCOUNT="${${(%):-%x}:A:h:h}/bin/account"
cc() {
  if [[ $# -ge 1 && ${#1} -eq 1 ]]; then
    local prefix
    prefix=$(head -1 "${REGATTA_CONFIG:-$HOME/.config/regatta}/lighthouse/cc-prefix" 2>/dev/null)
    local label="$prefix$1"
    shift
    "$_LIGHTHOUSE_ACCOUNT" run "$label" "$@"
  else
    command cc "$@"
  fi
}
