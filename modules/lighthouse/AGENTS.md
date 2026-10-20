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
