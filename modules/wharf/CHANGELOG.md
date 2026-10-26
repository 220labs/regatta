# Changelog — wharf

## Unreleased

- `/finish` step 11.4: a landing another Mac sent here (`--unattended … --from=<host>`, which
  `autofinish-run`'s job writes) takes that host's path, so a laptop sweep's landing merges on the other
  Mac as it would have on the laptop (D2-A of the lander's move, 2026-10-23).

- checkpoint's 🐑 note carries a `keel sheep --hook` row's `note` (keel's publish-budget warning), after
  the pages and any failure (spacesheep-tiers, 2026-10-24).

- sync.py runs `secrets check --fix` only under claude-host (orca-launcher S4, 2026-10-25): `.env` is a link
  into Drive's _secrets, which an ungranted responsible process (Orca's app) blocks on.
- `session_status` reads the core's `handed` closing kind as its own status, `handed to its launch`
  (2026-10-25, yolo-launch review D1-B), so helm can tell a hand-over from a run waiting on its own work.
- checkpoint denies writes in a primary checkout on a detached HEAD (hookwatch's pin) as on main, and
  guards /autofinish's marker and the yes at the brief as records under an unattended run; sync.py names a
  detached primary, and hookwatch's pin when its state names it (autofinish-exclude landing review, 2026-10-24).

- `pr ready` and `pr merge` judge a `by=brief` run by autofinish's `brief_held` (autofinish-exclude S7,
  2026-10-23): the yes at the brief lands class 1 and 3, never class 2, `in_place` or the list.
- `review-gate plan`'s path rule (autofinish-exclude S5, 2026-10-23): a branch that changes a path under
  the base's `autofinish_exclude` or `review_xhigh` gets reviewer xhigh + `/code-review` xhigh at any size
  (a tight week still lowers the second to high); `plan` prints the path, `--json` carries it as `gated`.
- The second landing review of skipper-modes-followups-2 (2026-10-24), main's denials restored: the shed
  guard's command start counts `if`/`elif`/`while`/`until`, `time` and `eval` again; the record guard reads
  a redirect inside awk's quoted program and sed's `w` again, catches sed's combined `-Ei`/`-ni` and gawk's
  `inplace.awk`, follows a `cd` as typed (a two-step `cd`, a relative path from the parent folder, a
  subshell's `cd` ending at its `)`, a loop's own line), judges a redirect by where its target lands, and
  skips heredoc bodies. `pr ready` labels a held launch `hold` itself, `--hold` or not (`held_launch()`).
- The follow-ups' landing review, its smaller findings (2026-10-23): the shed guard reads `unset`, the
  setters and an un-export only at a command's start (`rg export DISPATCH_LABEL=` is a search); the record
  guard catches `awk -i inplace`, reads a `cd` into a record folder as a read and what writes after it
  there as a write, and ignores a commit message quoting a redirect. `pr merge` refuses a held launch's
  own session (`hold` or `keel_hold` in autofinish.json), and the re-check judges by wharf-runs'
  `effective_mode`, naming the start's `land_mode` beside the mode now.
- `pr merge` waits for the base's required checks on the head before merging (2026-10-23). The
  protection refuses a non-admin token while `check` runs, and never an admin's: two PRs merged on
  the laptop before their run finished, which the scoped local check (wharf-runs' `check`) made a hole.
  `common.required_contexts` reads the protection, `check_state` the newest non-skipped run per
  context; a failure refuses at once, a run still going after the wait ends `NOT merged — … still
  running`, and /finish's step 11.4 leaves such a PR to automerge.

- `pr ready` and `pr merge` judge a `--by ship` run's gates and held slice again, as a sweep or mode
  run's (skipper-resilience S6's finish review, 2026-10-23): the keel's yes predates the run's own edits.
- The skipper-modes follow-ups (2026-10-23): the checkpoint hook's shed guard reads the shell's setters
  (`export`, `declare -x`, `typeset`, `local`, `readonly`) as assignments and an un-export (`export -n`,
  `declare +x`) as an unset, and an emptied value before `;` or `&`; under CLAUDE_UNATTENDED it denies a hand
  edit of helm's plans root (plan.json, branch-modes.json) or a dispatch run record — the Write/Edit tools,
  and a Bash command naming one that is no reader. `bin/pr`'s re-check of a mode launch reads the mode now,
  else autofinish.json's `eff_mode`, never a bare `by: yolo`.
- `repos --branches` (knowledge-layers S4, 2026-10-22): a confidential scope's repo is one counted
  line — no name, branch, PR or path — and is never classified or reaped from there; `--scope
  <scope>` lists that scope's repos alone.
- `scopes set SCOPE --yard HOST|none` (skipper-resilience S2, 2026-10-22): the scope's yard, a host
  `lighthouse/hosts` lists, or `null`; `--confidential | --open` is optional now, and `--yard` alone
  keeps the flag and the login. `scopes check` names a yard that is neither a host string nor `null` (`regatta check`
  names one `lighthouse/hosts` does not list), and a confidential
  scope's yard that its anchor is not on (the anchor's `hosts` in the registry).
- The skipper-modes landing review (2026-10-22): `bin/pr ready|merge` holds a `dnd` launch to the
  gates as a sweep's, and judges every mode launch again by autofinish's held slice under the mode
  now (a mode lowered mid-run, or the run's own edit into the slice, stops it); the checkpoint hook
  denies an unattended run a command that sheds CLAUDE_UNATTENDED (`env -u`, `unset`, an emptied
  value, `env -i`) or types `DISPATCH_LABEL=`; the architect pair's `Reversible:` paragraph says what
  `keel yolo` and `--dnd` take now.
- `sync.py` reads the account registry from the config dir's `lighthouse/accounts.json` ($ACCOUNTS_FILE
  over it), as `account` does, no longer from a path into the owner's vault (2026-10-22).
- The scrub (2026-10-22): no host, login, person or overlay path in the module's files. Two keys
  join `wharf/`: `ci-runner-kind`, the self-hosted kind's name in ci.json and `--to` (default
  `self-hosted`), and `hosts`, the Macs a new repo clones on (`github-repo`), all but the laptop
  cloning as the machine account (`repos --github`). The knowledge repos are atlas's
  `atlas/layer` and `atlas/vault`, read by the new `lib/knowledge.py` (checkpoint's
  knowledge-commit recipe, `sync.py`'s fast-forward, `finish-stuck-rebase`'s default). The owner's
  name is the core's `regatta/owner` where a message or status says it (`session_status`'s
  waiting words and ask-words, `branches.CONFIRMED`), else "the owner". `sync.py` reads the
  accounts file as the core does (`lighthouse/accounts.json`) and `secrets` through
  `common.tool()`. `fork_claude_session` opens the fork with `claude -r`. The core-missing line
  names no overlay path. An overlay-written workflow.json's note now names `wharf/repos.json`, so
  each is rewritten once at its next start; the pre-push templates' messages say "the owner",
  so `bin/repos --hooks` proposes each repo's refresh once.
- `/finish --unattended --yolo|--dnd [--hold]` (skipper-modes S3b): without `--hold` the ship's mode is
  the yes and step 11 merges on any host; with it, a ready PR held from automerge and `⚠ step 11 —
  held`.
- `/finish --yolo` reads `Taken unattended (the owner's dnd, …)` beside the yolo line (skipper-modes S2).
- `agents/sounder.md`, the link to sextant's sounder, is gone (the Sounding's S4): a config dir's
  `agents` is now a folder of one link per module agent file, so sextant's file is linked from its
  own module and wharf holds only its seven.
- The architects' shared body gains the Sounding's stance (3a: `firm:` or sounded, a `Verdict:` line)
  and Landscape (4a: what exists, before any build), and the skeleton both lines; carried from the
  overlay's sounding branch (2026-10-21). A third head shares the body: sextant's `sounder`, linked
  here as `agents/sounder.md`; `tests/test_agents.sh` checks all three.
- `scopes` writes the confidential flag (knowledge-layers S1, 2026-10-21; the owner's D3: "make a
  scope configurator on regatta that lets me set which ones are confidential"): `scopes set SCOPE
  --confidential|--open [--login LABEL|--no-login]` edits the one scope's object in the registry's
  text, its hand layout kept and the edit proved by parsing back; `scopes configure` is the
  checklist, toggled by number at a terminal; `scopes paths SCOPE` prints the core's
  `scope_paths`. `check` now fails a flag that is no bool, a login that is no label, and a
  confidential scope whose anchor is on this Mac without `memory/`; it names the flagged scopes.
  Membership (globs) is the core's `scope_members`. `set` and `configure` replace the file in one
  step (a hook never reads it half-written), refuse a registry in a primary checkout on `main`
  (write a `claude/*` worktree's copy through `CLAUDE_REPOS_JSON`), and `set` refuses a flag it
  does not know, a flag as the login, and a call that asks no change (exit 2).
- `ci-provider` moved in from the overlay (2026-10-20; the owner: "ability to switch repos between providers like
  this is useful"), with `templates/ci/` and its suite. It finds the core through `lib/core_path.py`
  and its templates in the module; `repos` loads it as its sibling in `bin/`, never through
  `common.tool()` (missing or raising: `ci: ci-provider unloadable (…)`).
  The runner Mac's ssh alias, labels and user are config keys (`wharf/ci-runner-ssh`,
  `wharf/ci-runner-labels`, `wharf/ci-runner-user`; `config-keys` lists the first two): absent, `--to`
  the self-hosted kind and `--runner` refuse, nothing else changes. `--to <kind> --runs-on-var NAME` (by
  itself CI_RUNS_ON where `.helloworld/` is) writes runs-on through a repository variable, which
  `--runner install` sets and status reads, so a published check.yml names no machine. The composed
  config.yml's marker no longer names the overlay; one composed before still reads as generated.
  The templates' headers (`templates/code/.github/workflows/check.yml`, `templates/ci/`) name no
  host, login or overlay either, and every file rendered from them copies that; an existing repo's
  file differs only in comments, which no switch counts. Only the tool's two runs-on forms are its
  own (the labels key's labels literally, the variable form exactly): any other is a hand edit a
  switch holds, a variable it never writes, and the self-hosted kind only when it names one of the
  key's own labels (the review of 2026-10-21).
- Landing order for the move (2026-10-21): this branch first, then the overlay's
  `2026-10-21-ci-provider-shim` branch (its `ci-provider` becomes a source shim of this file), then
  `bootstrap.sh --config` on each Mac to write `wharf/ci-runner-ssh` and `wharf/ci-runner-labels`.
  Until the last, `regatta check` reports those two keys missing on a Mac with the overlay, and
  a switch to the self-hosted kind and `--runner` refuse there, naming the file.
- The wharf rename's S6 (2026-10-20), carried from the overlay: the launch word in the agents, `/evacuate`,
  `/new-project`, `/todo` and the CI templates' comments.
- Carried from the overlay (the wharf rename's S5, 2026-10-20): `session_status` writes `waiting on
  skipper` (`RELAYED_BEFORE_S5` keeps the old line) and finds helm's `helmlib.py`, else `planlib.py`;
  the launch word in `repos`, `github-repo` and `test_repos.sh`; `/todo` names `bin/helm`'s verbs and
  `DISPATCH_SHIP`. `install.sh --check` probes `planlib.py` when `helmlib.py` is absent, as
  `session_status` reads it.

## 0.2.0 — 2026-10-19

- The second half moved in (the design's B6): `repos`, `scopes`, `github-repo`, `tend`,
  `finish-stuck-rebase`, `fork_claude_session.py`, `session_status.py`; the skills `/new-project`
  and `/fork`; the seven agents (`architect`, `sr-architect`, `worker`, `sr-worker`, `reviewer`,
  `reviewer-high`, `code-reviewer`); their suites.
- The registry, repos.json, is read through the core's `common.repos_json()` alone (C3), never
  a file beside the tool; `github-repo` lands a new line in whichever repo the registry really
  sits in.
- New optional peers through `common.tool()`: `trust-projects` and `rc-hosts` in `repos --clone`
  (G8, G2), `knowledge-commit` in `github-repo` (G6). `session_status` takes the guarded list
  from the registry's `guarded` key (G32), and from helm's planlib only while that key is absent.

## 0.1.0 — 2026-10-19

- First cut, moved in from the overlay (the design's B5): the hooks `checkpoint`, `sync`,
  `branches`, `carried`, `worktree_allow`; `pr` (in `libexec/`, reached as `regatta pr`);
  `review-gate`; the skills `/finish`, `/evacuate`, `/todo`; `templates/code/`; their suites.
- The core is found by `lib/core_path.py`; each optional peer through `common.tool()`: keel,
  autofinish, pickup, usage-report, tier_check, claude-settings, sheep. Absent, each is skipped
  with what is lost named (`install.sh --check`).
- `review-gate` logs to the core's log dir when usage-report is not installed.
