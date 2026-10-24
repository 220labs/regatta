# modules/lighthouse — upkeep of the machines

Read `README.md` first: it is the chart, and its "Private values" table is the contract. For an
agent:

- Nothing here names a host, a login, an account or a person, not even in a test: a private value
  is a config-dir key (README), a peer is `common.tool(<name>)`, the overlay is the core's
  `overlay_root()`. Test names are made up (`work`, `main`, `privy`, `server`).
- `bin/account` is read at start time by wharf-runs' dispatch and autofinish-run: prove
  `account pick --repo <repo>` and `account limits` through `modules/lighthouse/bin/account` in the main checkout before a change
  lands, or every unattended run stops.
- `account` typed over a plain ssh on the other Mac needs Claude Code's `.local/bin` on PATH first:
  without it `claude_bin()` is a bare `claude`, `auth status` cannot start, and orca-sync and
  doctor read a signed-in login as absent (a false "no login" on a work login, 2026-10-23). The
  laptop's doctor leg sets it; a hand-typed ssh does not.
- The deny hooks fail closed (README, "The guards"); `secrets_guard` imports no core on purpose.
  A hook's own refusal text is a test case (`tests/hooks.sh`).
- A key only the overlay writes (`lighthouse/accounts.json`, `lighthouse/vault`) is an error where
  the overlay is installed (the config dir's `regatta/overlay`), never "nothing to deny": `bin/account`'s
  `overlay_key_missing()`. An absent key read as empty is how a deny hook fails open (B9 review).
  A suite also unsets `SSH_CONNECTION` and the like when the tool reads them: dispatched runs come in over ssh.
- A suite moves HOME and pins `REGATTA_CONFIG` to a scratch dir first; one that needs macOS
  (zsh, Apple clang) skips itself elsewhere with one line.
- check: `bash modules/lighthouse/tests/check.sh`.

## beacon, the support part

beacon (a site's contact form and its bot, one Cloudflare Worker) joined after the upkeep tools;
its chart is `beacon/README.md`.

- Public since its publish review (2026-10-24): `beacon/`, `bin/beacon`, `tests/beacon.sh`,
  `tests/dev.sh`, `tests/upstream_stub.py` and `tests/worker.test.mjs` are on
  `.helloworld/allowlist.txt`, and a new beacon file is listed in the change that adds it. Their
  synthetic pattern hits (example addresses, made-up home folders, test keys) are exempted under that
  date's headers in `.helloworld/exemptions.txt`. `.gitignore` stays off: it names deadman's build.
- Every site value comes from the site's config file, never from this module: a test or example
  uses `example` names, and a real site's config and persona live in that site's own repo.
- `beacon/lib/bot.js` is a library: no route, storage or secret in it. Its `PRICES` table is
  written as JSON, because `bin/beacon` reads it to check a config's model.
- The Worker must load under plain Node for `tests/worker.test.mjs`: no `cloudflare:*` import,
  so the Meter is a fetch-interface Durable Object, not RPC. `tests/dev.sh` (opt-in, downloads the
  pinned wrangler, never run by `tests/check.sh`) is where the Workers runtime itself is proved.
- A new sink is one entry in `beacon/worker/sinks.js`'s `SINKS` with its `needs`, mirrored in
  `bin/beacon`'s `SINK_NEEDS` (`tests/beacon.sh` holds the two equal). A sink that relays (`relay:
  true`, `telegram.js`) brings the hand-off routes, the webhook and the mail handler worker.js
  routes to; one that does not leaves them 503.
- postal-mime is beacon's one npm dependency, for the mail door: pinned in `bin/beacon`
  (`POSTAL_MIME`), written into the build dir's `package.json` and installed there by `deploy`,
  never into the module. `worker.js` takes the parser as `parseMail`, so the Node suite loads
  without it; `tests/dev.sh` runs the real one.
- beacon's Worker and `bin/beacon` are no live hook or shim: they stay out of the root
  `autofinish_exclude`. Its Node suite needs Node 22.13 or later (`node:sqlite`).

## deadman, the yards' switch

deadman (a dead-man's switch the unattended Macs ping, one Cloudflare Worker) joined after beacon;
its chart is `deadman/README.md`.

- Off `.helloworld/allowlist.txt` until listed: `deadman/`, `bin/deadman`, `tests/deadman.sh`
  and `tests/deadman.test.mjs`; what this file, `README.md`,
  `CHANGELOG.md` and `tests/check.sh` say of it is written for the twin.
- Unlike beacon, `bin/deadman` is in the root `autofinish_exclude`: a yard's tick runs it after
  every pass (helm's `stalls_tick.deadman_ping`, skipper-resilience S11), so a broken `ping` silences every yard at once and opens an alarm for each.
- The Worker loads under plain Node: `cloudflare:email` is imported in `entry.js` only. Its Node
  suite needs Node 20 or later.
- Every yard, repo, mention and address comes from `lighthouse/deadman.json` in the config dir; a
  test uses made-up names (`alpha`, `beta`, `example/inbox`).
- **No KV key may stand for "an alarm exists" past a failed GitHub call.** Symptom: a yard goes
  silent and nothing is raised, or an issue opens at every cron. Cause: `open:` kept after a
  refused close skipped the yard for good, and an `open:` put lost after the POST (the day's writes
  spent) raised again. GitHub decides: a ping ends the alarm and owes the close (`closing:`), a
  raise adopts an open issue first, never one owed a close (finish review, 2026-10-22).
- **Every KV write on a failure path is counted against 1,000 a day.** An error written twice per
  cron, or rewritten as an outage's pages or calls change, spends the budget; past it every
  `last:` put fails and every yard reads silent. The Node suite asserts write counts per path.
