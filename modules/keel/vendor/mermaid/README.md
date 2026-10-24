# Mermaid — pinned, fetched once

What `bin/keel build` (the form) and `keel sheep` (the spacesheep page) inline into a page whose doc
has a ```` ```mermaid ```` fence, so the diagram draws with no install and a page without one stays as
small as before. Shape D2-B of docs/design-docs-shape-2026-10-14.md, built as entry S13
(2026-10-15): the owner took Mermaid as a new dependency in that answer.

- Version: **11.17.2** (npm, published 2026-08-25; the last 11.x — 12.0.0 was five weeks old and a
  new major) — `MERMAID_VERSION` in `bin/keel`
- sha256 of `mermaid.min.js`: `581ed7d74bd9048d0e3a91363927d72ef22942d7722546b27f7cc29e35390eb8` —
  `MERMAID_SHA256` in `bin/keel`
- Source: the package's `dist/mermaid.min.js` from jsDelivr, else unpkg (`MERMAID_URLS`); both
  served these bytes when checked (2026-10-23). The npm tarball's integrity, for moving the pin:
  `sha512-V6K3C8EBdEsPFZXSKMJe6ppQOENxuHARr9GvHX4hh47lAbhMRD9qf4oEK7LoaRQxULMa80/qt5gHO73aCleBBg==`
  (checked 2026-10-15)
- License: MIT, `LICENSE` beside this file (from the same tarball)

Not in the repo (since the shareable scrub, 2026-10-23): every module file targets going public, and the publish
gate's word list matches inside the minified code. The first page that draws a diagram fetches the
file into the cache (`KEEL_CACHE_DIR`, else `~/Library/Caches/keel` on a Mac and `$XDG_CACHE_HOME/keel`
or `~/.cache/keel` elsewhere, as `mermaid-<version>.min.js`) and keeps it only when its sha256 is the
pin; a cached file that is not the pin is fetched again, and a cache that cannot be written still
draws that page. Offline, or with `KEEL_MERMAID_FETCH=0`, the page shows the diagram's source and
`keel build` says why (`diagrams show as source`). A fetch gets 8 s for all sources together, and
one under way or failed leaves `mermaid-<version>.min.js.failed` beside the cache, which holds every
process off for 10 minutes (a long-running `keel serve` retries after that too): the checkpoint's page deploy and `keel line` have short deadlines. `KEEL_MERMAID_URL`
names one source in place of the CDNs.

To move the pin: fetch the tarball, check its `sha512` against `npm view mermaid@<v> dist.integrity`,
take `package/dist/mermaid.min.js`'s sha256 and `package/LICENSE`, update the version and both hashes
above, `MERMAID_VERSION` and `MERMAID_SHA256`, and run `bash modules/keel/tests/keel.sh`.
