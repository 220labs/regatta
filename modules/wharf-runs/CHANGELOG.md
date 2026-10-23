# Changelog — wharf-runs

## Unreleased

- `dispatch-rc watch` nudges a run whose last turn ended on an API error (2026-10-22: an unattended
  `/finish` ended on `API Error: Connection dropped (ECONNRESET)`, sat idle, and was ended 11 minutes
  later with its work committed and its check still running). A session idle a minute on a `server_error`
  stand-in (the `isApiErrorMessage` flag or the `<synthetic>` model, never a text alone; not a rate limit, an
  authentication failure or a safeguards flag) gets one post through the Claude Code adapter's `send()` (hail's
  socket road, read back from the receiver) saying who sent it and why: one a turn, two a run (`nudges` in
  the run record), a post that was refused or could not reach the session spends none. An end on any flagged
  API-error turn (a rate limit and the others too, though never nudged) reads `idle N min, its last turn ended on an API error`, which the harness reports `failed` and `--yolo`
  does not launch from. Cases in `test_dispatch.sh` and `test_harness.sh`.
- `wharf apply --yard` (skipper-resilience S2, 2026-10-22): a ship is laid on its scope's yard
  (`common.scope_yard`), pinned `{repo, branch, rel, digest}` from the committed and pushed blueprint
  (`push it first` otherwise), compiled on the yard or re-run there over its ssh alias with `--pinned`
  and `--laid-by` (who laid it, read on the caller: ssh carries no environment); those two flags are
  refused under a local session or `CLAUDE_UNATTENDED`, and a `laid_by.depth` past dispatch's cap. The
  pinned text is kept as the plan's `blueprint-<ship>.md`, so the tick drives it with no checkout; a pin
  another plan still drives is refused, naming it, and the tick drives one plan per pin. The fence: a
  plain apply (and `--watch`) of a ship whose scope has a yard is refused, off the yard and on it; a
  scope with no yard is refused nothing. Where the repo's scope has a yard, a block's `host:` must be
  some scope's yard. Blueprints take `merge: yes|no` and `sent_by`, and `skipper: scope` names no
  session until the lease; the keel's merge is recorded as plan.json's `merge: {value, why}`. `--gen` is
  taken for S4. Cases in `test_wharf.sh` with a stub ssh and a scratch origin.
- `wharf` start fixes (skipper-resilience S1, 2026-10-22), found by the yard probe: `start_orca` trusts the
  picked login's config dir first, as dispatch does (`dispatch-rc trusted`, then lighthouse's
  `trust-projects`, read back; still untrusted is one failed start); a worktree git just made that Orca's
  list does not show yet defers the start one pass without counting it; a start waits for the studio brake
  (the brake's sentinel file in the home folder, or the stopped process of the job `wharf-runs/brake-label` names); and
  `wharf status --orphans` lists the Orca repos and Runs no plan here accounts for (paged; Orca's legacy row
  and `bin/harness run`'s Runs left out). A block on another host is not braked by this Mac's brake. Cases in
  `test_wharf.sh`.
- `dispatch --if-room` (the Sounding's S7, 2026-10-22): at fire time, after the account pick, a run
  refuses to start when autofinish's `week_tight` says `tight` or `none`, or when reading it raises — for
  the sounding queue's runs at the weekly reset, which spend the week they fire in. No reading (no
  registry, no sample, last week's figure) is room, so at the reset `none` is what refuses in practice.
- `dispatch --at` given twice is refused (exit 2): the last one won, so a rule pinned to `--at reset`
  passed `--at reset --at <clock>` (S7's /finish review, R5).
- Under `WEEKLY_RUN` (aurora's weekly Sextant, in `auto` mode): `dispatch` takes only
  `<branch> --repo R --at reset|reset+30|reset+60 --if-room`, and `pickup seed` only with `--no-start`;
  anything else exits refused (S7's /finish review, F1).
- `bin/headroom` (2026-10-22): whether this host has the memory for one more run — % free, GB of swap
  in use and MB/s swapped over a 2 s sample, read from sysctl and vm_stat on macOS, /proc on Linux —
  against its line in `wharf-runs/headroom`. `dispatch` asks it beside the run cap at all four gates
  and refuses a run past it, refused not queued; a reading it cannot take goes ahead, said. One row
  per check in `headroom.jsonl`. Six runs had left a 16 GB host thrashing with four slots still free.
  `tests/test_headroom.sh`, Linux from a stand-in /proc. Private until the scrub.
- The skipper-modes landing review (2026-10-22): yolo holds `autofinish_exclude` and `in_place`
  too — it lands all the way bar what judges a landing and what every session's hooks run; a deployed
  dnd or yolo branch starts by rule M, not L (its taken docs and its held slice read); in mode `ask`
  rule D never stands a due doc; a `"merge": "auto"` repo's standing yes covers a yolo launch with no
  mode, from a caller without CLAUDE_UNATTENDED, only. dispatch: the unattended raise check bars on
  the target branch's mode (and the ship's task before it writes), `--yolo` is written to plan.json
  as `--mode yolo` is, a dry run asks berth with `--no-log`, and a cancel never sshes the Mac to
  itself. `wharf apply`: a refused blueprint mode stays refused (`mode_refused` in plan.json), and
  the helm tick's `--once` apply counts as unattended. berth: a torn registry is refused (exit 3);
  one load key set without `log` beside an unset one is enforced; the landing starts its log-only
  week, a dated TODO item ends it. Under `WEEKLY_RUN`, `--mode` is refused like every other flag.
- Default-path changes, intended (skipper-modes S6b, S1): berth's pick is the default host of a
  plain `dispatch` (one more ssh to a peer and a `dispatch: berth —` line on stderr).
- Every run record and launchd plist carries the mode: `DISPATCH_MODE` and `task_mode`, `default`
  when nobody set one.
- `autofinish-run --dry` prints a `mode …:` line before the account line.
- `bin/hail` and `hail subs` (Lookout and Hail, S2, 2026-10-21): one verb that delivers a pointer to any
  session `harness` names — Claude Code's inbox socket (S1's wire: an `auth` line with the key file's
  `peerToken`, then the `user` line; only to a session idle 60 s or more, re-read before the post;
  `delivered` read back from the receiver's transcript or status, `held` when nothing shows), `codex
  queue` by an explicit thread, Orca's mailbox or an idle worker's terminal, the adapter roads on a peer
  over ssh, else helm's Talk and file roads. A `send()` in each adapter. `--when idle` keeps a row in
  `hail-subs.jsonl` that `hail subs --fulfil` sends once the target is idle or gone (72 h, then dropped).
  The frame never carries an answer's words. `tests/test_hail.sh`, stubs only. Private until the scrub.
- `pickup brief BRANCH --text T|-` (Lookout and Hail, S4, 2026-10-21): commits
  `docs/handoff/<date>-<topic>.md` onto an existing `claude/*` branch by plumbing (no checkout), so a
  launchd job with no worktree can hand `dispatch` a run; fast-forwards from origin first, refuses a
  diverged branch, a dirty worktree and one held by another session, then pushes.
- `autofinish-run --merge` (Lookout and Hail, S10, 2026-10-21): the owner's up-front `/finish --merge`
  carried into the unattended run (`--by override|typed` only; sweep, chain and yolo refused);
  `autofinish.json` records `merge: true`.
- `orca-serve-agent` moves in from the overlay (D2-B, 2026-10-21): a Mac's Orca as a headless server
  under a LaunchAgent. The label is read from `wharf-runs/serve-label` on the Mac it installs on
  (default `org.regatta.orca-serve`), an older one from `wharf-runs/serve-label-previous`; the owner's
  own labels live in the overlay's config. New `--dry-run` prints the label, the plist and the commands.

- Landing on the mode's ladder (skipper-modes S3b; the owner: "dnd: I want to automerge as well"):
  autofinish's rule M starts a branch whose sent task is in `dnd` or `yolo` whatever its shape,
  `taken` docs included; `held_slice` names what a dnd landing holds at a ready PR (money in the prose,
  a physical repo, `autofinish_exclude`, a path the public twin publishes, a deleted data file, a
  yolo-taken answer) and what every mode holds (the launcher's own gates). `autofinish-run` reads the
  mode from plan.json itself — `--by` grants nothing — gains `--by dnd`, `--rule M`, `--hold`, the
  state's `hold` and gate `held`; mode `ask` holds every launch but a person's. dispatch launches a
  dnd run too (`--by dnd`), reads the mode again at launch, and refuses an unattended `--mode` or
  `--yolo` that raises the caller's mode; `wharf apply` records no raised blueprint mode unattended.
- Skipper modes (S1, S3, S6b; docs/skipper-modes-2026-10-21.md): `dispatch --mode
  default|ask|dnd|yolo` (the plist's DISPATCH_MODE, the record's `task_mode`, read again at fire time
  with plan.json first; `--yolo` is mode yolo) and its prompt gate per mode; a blueprint's `mode:`,
  recorded once by `wharf apply`, which resolves a decision gate as taken in dnd or yolo where
  nothing is held. `berth` (private-first): the host by the scope's `berths`, slots and load,
  log-only while a key ends `log`, a row in berth.jsonl; `dispatch --on auto` the default,
  `--slots`, peers by their `wharf-runs/ssh` alias; `host: auto` on a claude-code block; config-keys
  gain `wharf-runs/load-max` and `load-margin`.
- The wharf rename's S6 (2026-10-20), carried from the overlay: the launch word in `/later`, `/move`
  ("the arrival" for a move's own landing) and `/pickup`.
- `test_wharf` finds helm's console and the old `bin/plan` each where it lives: `libexec/helm` in helm's
  module (B12), the overlay's S5 shim for `plan`; without that shim the old names are skipped, said.

## 0.2.0 — 2026-10-20

- The unattended runs move in (B7): `dispatch`, `dispatch-rc`, `run-seed`, `harness` and its adapters,
  `rc-hosts`, `autofinish`, `autofinish-run`, `pickup`, `blueprintlib`, `wharf`, `check`,
  `hooks/cold_prompt.py`, the skills `/autofinish`, `/later`, `/move`, `/pickup`, and their suites.
  Private until the module's scrub.
- They find the core by `lib/core_path.py` and their peers through `common.tool()`; the registry is
  the core's `repos_json()` (`autofinish` keeps `AUTOFINISH_REPOS`). Without lighthouse's `account`
  a run starts on the one login (G12); without helm's `ask` and `helm` a run's prompt drops their
  lines (G22). `install.sh --schedule` writes the autofinish sweep's agent; `bin/check` with no
  checkout named checks the caller's.

## 0.1.0 — 2026-10-19

- First piece, moved in from the overlay's history: `orca-host` and its suite. The pairs and the
  ssh aliases come from the config dir (`wharf-runs/orca-pairs`, `wharf-runs/ssh`), the registry
  from the core's `repos_json()`, `scopes` and `account` through `common.tool()`; `setup` without
  `account` skips the sync and says so.
- Against the original: `check` and `setup` print their whole report when a peer tool, the
  registry or a key is missing; host names compare lower-case; the app's bundled CLI is preferred
  to any `orca` on PATH; `--on … pair --link -` checks the link here before ssh; a dry `--on`
  pair keeps the clipboard; a pairing code or registry of the wrong shape is an error, never a
  traceback; the projects folder is resolved as Orca records it; `config-keys` names both keys
  for `regatta check`.
