# Changelog — lighthouse

## Unreleased

- `account doctor` reports the tenants file's own state (2026-10-23): a link that reads nothing with
  no copy (tenancy off), the last good copy in force and its age, a file that does not parse, a tenant
  whose `repos` match nothing or that has no enabled login, a label in two tenants' `logins`, and one no
  enabled row has (parked, off in Orca, a Codex row). Also with no logins file, since the tenants link
  points into the same drive. A refusal for a tenant whose listed labels give it no login names them.
  An `ACCOUNTS_FILE` naming the live key is no fixture; the guard's check after a `cd` passes a
  tenants-file refusal on with its own way in.

- deadman joins as lighthouse's switch for the unattended Macs (private until its scrub; chart:
  `deadman/README.md`): one Cloudflare Worker, cron every 5 minutes, one KV namespace; a Mac that
  pinged and went quiet past the period and grace is one GitHub issue that mentions the owner,
  closed by its next ping; a braked ping holds it off, a failed pass raises at once, a refused
  token falls back to one mail. `bin/deadman build|deploy|ping|status`; status names the GitHub
  token 14 days before it ends. Tested against stubs; not deployed anywhere.
- `health` reads the Orca serve agent: on a Mac with its LaunchAgent, launchd's pid for the label
  (`wharf-runs/serve-label`) and `orca orchestration run-list` answering, one line a day; a missing
  pid or a list that does not answer is posted once, under its own state file.
- beacon hands a visitor to a person when they ask (2026-10-22): with a relaying sink the bot hears
  a request for a person in any language and its reply says the people are busy and asks for an
  address; the chat takes it in the conversation, Skip beside Send, and the address is read from a
  sentence too. A hand-off with an address files an issue and opens a topic; without one, the topic
  alone. New config key `person_ask`, the chat's own line for "Talk to a person".
- beacon's `telegram` sink, two-way (2026-10-22): every form send, chat hand-off ("Talk to a person"
  in the widget) and mail to the site's address is a forum topic in the people's Telegram group,
  and an issue (a chat hand-off only when the visitor left an address); their reply in the topic reaches the visitor's chat panel while it polls, else
  their mailbox (Resend) with a `Reply-To` whose token is an HMAC of the conversation, and the
  visitor's mail reply comes back to the same topic. New: the Conversation Durable Object, the
  routes `/chat/handoff`, `/chat/say`, `/chat/poll` and `/telegram`, the Worker's email handler
  (forwards first, never throws past it), `/close` in a topic, and postal-mime, pinned and
  installed in the build dir only. Tested against a stub Bot API and mail sender in Node and,
  opt-in, under `wrangler dev`; not deployed by this change.

- The fence (knowledge-layers S2, 2026-10-21): `secrets_guard` refuses a confidential scope's paths
  — checkouts, `git worktree list` entries, the transcripts folder, each login's session folder
  (`projects/<slug>/`, its `.jsonl` logs and memory both: the digest's D1-A, as the core names it) — to a
  session whose cwd or start directory is outside the scope, by Read, Edit, Write, NotebookEdit,
  Grep, Glob and Bash (`ls`, `stat` and a command after a `cd` in refused too; git judged by its
  tree, a grep's pattern as text). It reads the registry's flag with the stdlib, names the way out,
  and logs one line per refusal to `<log-dir>/fence.log`. The hook's matcher gains Glob
  (`Read|Grep|Glob`).
  The landing review's gaps, closed (2026-10-22): a grep whose pattern rides its option (`-ex`,
  `--regexp=x`) and `rg --files`; a walker with no path from a folder that holds the scope (`grep -r`,
  `rg`, `find`, `ls -R`, `du`, `tree`) and find or `ls -R` over one; `echo`/`printf` of a glob into it;
  `git diff --no-index`; a removed worktree's session folder (`<slug>--claude-worktrees-<topic>`). A cwd
  inside a scope's paths is logged as `-`.
  A walker's folders are its arguments that exist, else its cwd unless it reads a pipe; only the scope
  folders this Mac has count, and a glob match that is a fenced folder's own name only names it
  (`ls -d`, `for` loops over the projects folder pass). Plain `git diff <path>`, clone and fetch of the
  scope, `GIT_DIR=` and `pushd` are judged too.
  A copier walks only its sources (`cp x <projects>/` passes), `rm`/`chmod` only with `-r`; `cd` and
  `git -C` take a glob's first match; `find -maxdepth` counts. The secrets wall no longer judges a
  grep's pattern as a folder (`ls -p ~ | grep -v /`).
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
