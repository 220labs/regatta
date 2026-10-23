# keel's suites' regatta config dir — sourced by each suite before any case moves HOME.
#   . "$(dirname "$0")/config.sh"; keel_config "$T/config"
# A scratch dir, never the caller's: the owner is `Sam`, the guarded repos `vault` and `archive`,
# the knowledge repos `layer` and `vault`, so no fixture names a real person or repo. The caller's
# `home` file is copied (the core is found through it from a plugin cache), and the overlay, where
# one is installed, is passed as REGATTA_LEGACY rather than its `legacy` file: with no `legacy` file
# the core asks for none of the overlay's keys, and the cases that read an overlay peer still find
# it through tool(). With no overlay and an empty config dir (CI), the same suite runs; an
# overlay-only case skips on `overlay_peers` false.
keel_config() {  # <dir>
  local src="${REGATTA_CONFIG:-"$HOME"/.config/regatta}" d="$1" old=""
  mkdir -p "$d/regatta" "$d/atlas"
  # the core's checkout: the caller's `home` file, else this one (install.sh's line), so a copy of
  # keel made outside the monorepo (paste-paths' isolated cases) still finds the core
  if [ -f "$src/home" ]; then cp "$src/home" "$d/home"
  else (cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd) > "$d/home"; fi
  [ -f "$src/legacy" ] && old=$(sed -n '/./{p;q;}' "$src/legacy")
  if [ -z "${REGATTA_LEGACY:-}" ] && [ -n "$old" ]; then
    export REGATTA_LEGACY="${old/#\~/$HOME}"
  fi
  printf 'Sam\n' > "$d/regatta/owner"
  printf 'vault\narchive\n' > "$d/regatta/guarded"
  printf 'layer\n%s\nATLAS_LAYER\n' "$d/layer" > "$d/atlas/layer"
  printf 'vault\n%s\nATLAS_VAULT\n' "$d/vault" > "$d/atlas/vault"
  export REGATTA_CONFIG="$d"
}

overlay_peers() {  # true when an overlay checkout is reachable (REGATTA_LEGACY at a folder)
  [ -n "${REGATTA_LEGACY:-}" ] && [ -d "$REGATTA_LEGACY" ]
}
