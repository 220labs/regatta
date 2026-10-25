# Changelog — lighthouse

## Unreleased

- hookwatch's suite builds the revert branch's date with `date -d @<epoch>` where BSD `date -r` fails, so
  the twin's ubuntu CI passes it (220labs/regatta#5, 2026-10-24).
- deadman's state moves from KV to one SQLite-backed Durable Object, `Yards` (skipper-resilience
  S10b): a ping is one request and one row, a cron pass one read and at most one write, so about 340
  yards fit the free plan where KV's 1,000 writes a day held three. Every rule and message stays.
  The issues come from the switch's own GitHub App, made by `deadman app` through GitHub's manifest
  flow (issues write, metadata read, no webhook, private; the owner clicks Create and Install), its
  record and key kept in the config dir at mode 600; a classic token remains the road without it.
  The mail fallback goes through Resend instead of the `send_email` binding. `deploy` makes the ping
  secret in the config dir when none is there, never reading the vault for it; `inbox_repo` and
  `mention` default to the config dir's `helm/inbox-repo` and `helm/mention`; `status` names the road
  the Worker holds. beacon's App JWT and Resend call move to `beacon/worker/outbound.js`, which both
  Workers import.
  After the finish review: `deploy` refuses to make a ping secret on a Mac that knows the switch
  deployed (a Worker URL set), unless `--new-secret`; a pass no longer closes what it raised for a
  yard heard from meanwhile, the object owes it to the next ping (`closing`), so a `/fail` that
  adopted it keeps an open alarm; `app_name` is judged by `deadman app` alone, never a ping; deploy
  says when a Worker may still hold an old App's secrets; `/apply` refuses a prototype key with 400.

- `account` sees paid overage (costs S8, 2026-10-24): the probe's cached reading carries `extra_usage`,
  parsed by the core's `extra_usage()`, and `judge` refuses a row whose extra usage is on, a later row
  of the walk and a pinned ship's login included, unless `account pick --allow-overage`, a person's yes,
  refused (exit 2) under CLAUDE_UNATTENDED. A reading without the field refuses nothing; extra usage the
  user switched off (`user_disabled`) cannot bill and refuses nothing either. `limits --json` carries an
  `overage` flag, which dispatch's `--force` reads (the landing review).

- hookwatch after its landing review (autofinish-exclude, 2026-10-24): a fault counts only for a hook the
  move changed (its file, its imports, its traceback's files); the overlay's own hooks are no longer read
  (the `legacy` prefix is gone; a shim shows through its traceback); a `judge` fault needs an error or a
  deny, not printed words. A pass reads each transcript from its remembered offset; the clean sha is one
  hookwatch saw stand, never HEAD@{1}, and never a sha without hookwatch. The revert PR fetches first and
  opens as a draft when the range touches the base's `autofinish_leaks`, `in_place` or the list. The pin
  ends by itself once origin/main carries a fix; a person's checkout starts probation; a pin posts once
  per change of origin/main; `--dry-run` only prints. `replay` judges the last days' moves read-only
  (the always-on Mac, 2026-10-24: 0 of 59). The plist carries PATH, REGATTA_CONFIG and the HOOKWATCH_* seams.
- `health` names hookwatch's pin and posts it once, whichever check it runs.
- beacon held off the allowlist until the extensions design decides its home (2026-10-24); its
  exemptions left with it.
- beacon's publish-readiness review (2026-10-24), its fixes: the
  Telegram webhook answers 200 to another chat once its secret matches (Telegram retries every
  other reply); a `+token` mail reply counts against its sender's send limits; `build` refuses a
  sitemap page whose host, as listed or after redirects, is not one of `origins`' (a site whose
  apex redirects to `www.`, or back, lists both hosts), and with no word list anywhere warns and
  scans for local paths only (an empty or broken list, a broken link at either default or an
  unmounted config folder, is still refused); `deploy` refuses a `secrets_file` git tracks and a
  public `sink.repo`; a `+token` reply from anyone but the visitor also counts against the
  address's daily limit; the config refuses a `rest_at` outside 0 to 1, a `cap_usd` that is not a
  positive finite number, an unknown `limits` key or a limit that is not
  a positive whole number, and a `max_tokens` outside 1 to 4096; `status` warns, first, when
  `sink.repo` is public. The README gains "Before the first deploy" and says what a hand-off keeps on the server.
- `account doctor` reports the tenants file's own state (2026-10-23): a link that reads nothing with
  no copy (tenancy off), the last good copy in force and its age, a file that does not parse, a tenant
  whose `repos` match nothing or that has no enabled login, a label in two tenants' `logins`, and one no
  enabled row has (parked, off in Orca, a Codex row). Also with no logins file, since the tenants link
  points into the same drive. A refusal for a tenant whose listed labels give it no login names them.
  An `ACCOUNTS_FILE` naming the live key is no fixture; the guard's check after a `cd` passes a
  tenants-file refusal on with its own way in.
- `deadman ping` reads the secret from `lighthouse/deadman-ping-secret` in the config dir between
  `$DEADMAN_PING_SECRET` and the vault's secrets file (skipper-resilience S11): a yard's launchd job
  may be refused the vault's folder on Drive, and the owner can place the secret there once. The file is
  read only at mode 600 or stricter; a looser one is refused in one line that names the path and mode,
  never the value, and the vault is tried next.

- `hookwatch` (autofinish-exclude S3, S4; D3-B, 2026-10-23): reads the hook records of the last 30 min of
  transcripts and, within 30 min of the primary checkout's HEAD moving, pins it at the last clean sha
  (`git checkout --detach`) on a crash through `modules/`, a deny that cannot judge, one hook timing out
  in 3 sessions, or one denying over 80 % of 20 calls; then opens the revert PR, the clean tree on the
  pinned head (tree equality checked), ready for automerge, only while origin/main is that head.
  `scan`, `status`, `unpin`, `install` (the LaunchAgent, every 10 min; refused unattended). Stdlib, no
  core. `regatta check` reports a pin. Not installed on any Mac yet.
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
