# Changelog — lighthouse

## Unreleased

- beacon joins as lighthouse's support part (private until its scrub; chart: `beacon/README.md`):
  a site's contact form and its bot as one Cloudflare Worker (`/contact`, `/chat/start`, `/chat`,
  `/status`), the Meter (a SQLite Durable Object), the `github` sink (an App's RS256 JWT by
  WebCrypto, PKCS#1 wrapped in code), the bot library `beacon/lib/bot.js`, and `bin/beacon
  build|deploy|status`. Tested against stubs in Node and, opt-in, under `wrangler dev`; not
  deployed anywhere.
- beacon, the review gate's fixes before it landed: the soft cap fails closed on an unpriced model
  and counts the long-prompt rates; the charge runs under `ctx.waitUntil`; upstream refusals reach
  `beacon status`; replies are signed and assistant turns must carry their signature; Turnstile's
  host and action are checked; IPv6 counts by /64 and `retry-after` stops at 00:00 UTC; a Meter
  error is 503 `busy`; the build scans pages for private words only, whole texts, `<url><loc>`
  only, and removes only its own build dir; secrets reach wrangler on stdin.
- lighthouse depends on `helloworld` too (beacon's build scans with its word list); `tests/check.sh`
  skips beacon's opt-in `dev.sh` and runs its Node suite where it is present.

## 0.1.0 — 2026-10-19

- First cut, moved in from the overlay: `bin/health`, `claude-settings`, `account` with
  `shell/cc.zsh`, `publish`, `trust-projects`, `tiling`; the hooks `account_guard.py`,
  `secrets_guard.py`, `design_route.py`, `tool_path.py`; their suites. Every private value
  (registry, declared settings, shares, vaults, hosts) comes through the config dir's
  `lighthouse/` keys (README, "Private values"); a missing peer (wharf, atlas, plumb) is a
  printed fallback, never a stack trace.
