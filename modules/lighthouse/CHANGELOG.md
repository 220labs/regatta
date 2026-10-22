# Changelog — lighthouse

## Unreleased

- `account_guard` judges where the session started ($CLAUDE_PROJECT_DIR, else the event's cwd), not where
  its shell is now (2026-10-22). The event's cwd follows a `cd`, so a work-login session started in an open
  repo that later moved its shell to the projects folder had every following prompt blocked (it holds the vault): 18 in
  4 days on the owner's Macs. The deny list governs where sessions start (the hook's header), and
  CLAUDE_PROJECT_DIR keeps the start across a `cd` (a two-prompt headless probe).
  Where the shell went is judged too, bar the "holds" rule: a `cd` into a denied or a tenant's repo is still refused.
- `account pick --repo` honours a scope's `login` (knowledge-layers S1, 2026-10-21): a repo in a
  scope that names one is picked onto that row alone, waits (exit 3) when it cannot run rather
  than move to another seat, and a ship pinned elsewhere moves to it. `limits --repo` marks every
  other row ineligible and denied (dispatch's `--account` and `--force` never cross it); a folder
  that is no git repo finds its scope by path; a registry that does not read makes every pick wait.
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
- Tenants (multi-tenancy, 2026-10-20): the registry's `tenants` and a row's `tenant` send an
  organisation's repos to its own login. Every other row is refused them, the default dir's
  included. `pick --repo` routes there and waits rather than falls back. `allowed`, `run` and
  `account_guard` (now also on the default dir while a tenant exists) name the way in, and
  `doctor` checks the VS Code profile ties. Tenant entries may be globs, matched by repo key and
  by path. On the default dir the guard asks only inside a tenant's folder, and fails open there.
- The tenants file (2026-10-22): `lighthouse/tenants.json`, `{name: {repos, logins}}`, holds the
  whole of tenancy when written — the registry's `tenants` and rows' `tenant` are then ignored — so
  an organisation's list can live apart from the registry (the owner keeps it in the vault). Each good
  read is copied beside the key, and that copy holds while the link reads nothing or is gone, in
  `account` and the guard alike: never failing open onto another seat. A fixture `ACCOUNTS_FILE`
  reads its own `<it>.tenants`, never the live key.
- Carried from the overlay (the wharf rename's S5, 2026-10-20): the launch word in `claude-settings`
  and `tiling`'s prose and messages.

## 0.1.0 — 2026-10-19

- First cut, moved in from the overlay: `bin/health`, `claude-settings`, `account` with
  `shell/cc.zsh`, `publish`, `trust-projects`, `tiling`; the hooks `account_guard.py`,
  `secrets_guard.py`, `design_route.py`, `tool_path.py`; their suites. Every private value
  (registry, declared settings, shares, vaults, hosts) comes through the config dir's
  `lighthouse/` keys (README, "Private values"); a missing peer (wharf, atlas, plumb) is a
  printed fallback, never a stack trace.
