# modules/lighthouse — upkeep of the machines

Read `README.md` first: it is the chart, and its "Private values" table is the contract. For an
agent:

- Nothing here names a host, a login, an account or a person, not even in a test: a private value
  is a config-dir key (README), a peer is `common.tool(<name>)`, the overlay is the core's
  `legacy_root()`. Test names are made up (`work`, `main`, `privy`, `server`).
- `bin/account` is read at start time by wharf-runs' dispatch and autofinish-run: prove
  `account pick --repo <repo>` and `account limits` through the overlay's shim before a change
  lands, or every unattended run stops.
- The deny hooks fail closed (README, "The guards"); `secrets_guard` imports no core on purpose.
  A hook's own refusal text is a test case (`tests/hooks.sh`).
- A key only the overlay writes (`lighthouse/accounts.json`, `lighthouse/vault`) is an error where
  the overlay is installed (the config dir's `legacy`), never "nothing to deny": `bin/account`'s
  `overlay_key_missing()`. An absent key read as empty is how a deny hook fails open (B9 review).
  A suite also unsets `SSH_CONNECTION` and the like when the tool reads them: dispatched runs come in over ssh.
- A suite moves HOME and pins `REGATTA_CONFIG` to a scratch dir first; one that needs macOS
  (zsh, Apple clang) skips itself elsewhere with one line.
- check: `bash modules/lighthouse/tests/check.sh`.

## beacon, the support part

beacon (a site's contact form and its bot, one Cloudflare Worker) joined after the upkeep tools;
its chart is `beacon/README.md`.

- Private until its scrub: the upkeep files are on `.helloworld/allowlist.txt`, beacon's are not
  (`beacon/`, `bin/beacon`, `tests/beacon.sh`, `tests/dev.sh`, `tests/upstream_stub.py`,
  `tests/worker.test.mjs`, `.gitignore`). A new beacon file stays off it too; this file,
  `README.md`, `CHANGELOG.md`, `plugin.json` and `tests/check.sh` are public, so what they say of
  beacon is written for the twin, and `tests/check.sh` skips beacon's Node suite where it is absent.
- Every site value comes from the site's config file, never from this module: a test or example
  uses `example` names, and a real site's config and persona live in that site's own repo.
- `beacon/lib/bot.js` is a library: no route, storage or secret in it. Its `PRICES` table is
  written as JSON, because `bin/beacon` reads it to check a config's model.
- The Worker must load under plain Node for `tests/worker.test.mjs`: no `cloudflare:*` import,
  so the Meter is a fetch-interface Durable Object, not RPC. `tests/dev.sh` (opt-in, downloads the
  pinned wrangler, never run by `tests/check.sh`) is where the Workers runtime itself is proved.
- A new sink is one entry in `beacon/worker/sinks.js`'s `SINKS` with its `needs`; `worker.js` does
  not change. `bin/beacon`'s config check names the sinks it accepts.
- beacon's Worker and `bin/beacon` are no live hook or shim: they stay out of the root
  `autofinish_exclude`. Its Node suite needs Node 22.13 or later (`node:sqlite`).

## deadman, the yards' switch

deadman (a dead-man's switch the unattended Macs ping, one Cloudflare Worker) joined after beacon;
its chart is `deadman/README.md`.

- Private until lighthouse's scrub, as beacon: `deadman/`, `bin/deadman`, `tests/deadman.sh` and
  `tests/deadman.test.mjs` stay off `.helloworld/allowlist.txt`; what this file, `README.md`,
  `CHANGELOG.md` and `tests/check.sh` say of it is written for the twin.
- Unlike beacon, `bin/deadman` is in the root `autofinish_exclude`: a yard's tick runs it after
  every pass, so a broken `ping` silences every yard at once and opens an alarm for each.
- The Worker loads under plain Node: `cloudflare:email` is imported in `entry.js` only. Its Node
  suite needs Node 20 or later.
- Every yard, repo, mention and address comes from `lighthouse/deadman.json` in the config dir; a
  test uses made-up names (`alpha`, `beta`, `example/inbox`).
