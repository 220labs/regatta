# mermaid.min.js — vendored, pinned

What `bin/keel build` (the form) and `keel sheep` (the spacesheep page) inline into a page whose doc
has a ```` ```mermaid ```` fence, so the diagram draws offline with no install and a page without one
stays as small as before. Shape D2-B of docs/design-docs-shape-2026-10-14.md, built as entry S13
(2026-10-15): the owner took Mermaid as a new dependency in that answer.

- Version: **11.17.2** (npm, published 2026-08-25; the last 11.x — 12.0.0 was five weeks old and a new major)
- Source: `https://registry.npmjs.org/mermaid/-/mermaid-11.17.2.tgz`, `package/dist/mermaid.min.js`
- npm integrity of the tarball: `sha512-V6K3C8EBdEsPFZXSKMJe6ppQOENxuHARr9GvHX4hh47lAbhMRD9qf4oEK7LoaRQxULMa80/qt5gHO73aCleBBg==` (checked 2026-10-15)
- sha256 of `mermaid.min.js`: `581ed7d74bd9048d0e3a91363927d72ef22942d7722546b27f7cc29e35390eb8` — `MERMAID_SHA256` in `bin/keel`; a file that does not match is never inlined (the page shows the diagram's source instead, and `keel build` says why)
- License: MIT, `LICENSE` beside it (from the same tarball)
- Private-only: the bundle is never on `.helloworld/allowlist.txt` — the publish gate's word list
  matches inside the minified code, and a word-list hit is rewritten, never exempted. A public
  install has this README and the LICENSE but not the file: its pages show a diagram's source, and
  `keel build` says so (`diagrams show as source`). To draw them, fetch the pinned file as below.
- `.gitattributes` marks it `-diff`: a review reads "binary files differ", not 3.5 MB of one line

To move the pin: fetch the tarball, check its `sha512` against `npm view mermaid@<v> dist.integrity`,
copy `package/dist/mermaid.min.js` and `package/LICENSE` here, update the version and both hashes
above and `MERMAID_SHA256`, and run `bash modules/keel/tests/keel.sh`.
