# Changelog — wharf

## Unreleased

- Keep the no-core checkpoint fixture outside temporary directories' inherited git markers; its Edit is only a hook payload and writes no file.

- `pr stuck [--json] [--dry-run]` reads ready agent PRs on the repo's one yard (else the laptop), reports
  required reds by source and requests local DIRTY re-finishes for the tick. List conflicts stay with
  `pr restack`. Unarmed heads rerun only a non-skipped automerge workflow, through the lander's rerun cap;
  held PRs and live runs get no action. Protection contexts come from the repo's file, now excluded from
  autofinish. Offline cases cover the real cap parser/store, check history, trigger grace and dry restack.

- Drop `physical:` from project templates, finish guidance and agent instructions; dnd landing checks no longer require the field.

- A finish's closing line follows who owns its next move: the lander only after `lander armed`
  succeeds, a successful skipper relay, or the owner with the external-finish command. Session
  status names the lander separately from work running in the session (stuck-ships S7).
- `.github/ci/share.sh`'s `macos`, `rest` and `whole` run their commands at once, at most `CI_SHARE_JOBS` at a time
  (a repository variable check.yml passes; unset: 2, `1`: one after another, streamed, as before), each command's
  output printed whole and in the line's order once it ends, the verdict and summary as before; a cancelled share
  stops every running command's tree (mac-share-speed, 2026-11-06). Cases in `test_ci_provider.sh`.
- ci-provider's pick: a self-hosted lane may carry `share_runs_on` in `ci-lanes.json` (mac-share-lane, 2026-11-06), the label
  list it writes to `CI_RUNS_ON` while `CI_LINUX_ELSEWHERE` is on, so the PR check's macOS share can run on a runner Mac with
  no desktop session (no `browser`); off, or with no field, it is `runs_on` as before, and `CI_RUNS_ON_FULL` is never the
  pick's. The share's flip moves `CI_RUNS_ON` in the same pass (logged with `share`, and the restoring call); the runner
  check judges the list in force, and a lane whose share labels no online runner carries has no runner while the share is on.
  A flip to off moves `CI_RUNS_ON` back to `runs_on` before the share's own write, and leaves the share on when that
  write is refused; an unread share keeps the list in force; the share labels go only to a split-form check.yml whose
  `CI_RUNS_ON_FULL` holds a label list (a push takes those) and whose `needs` they meet; the PyYAML probe reads the
  python3 a job runs (the runner's `.path`) (the landing review).
  A runner Mac's probe reads whether the login's python3 imports yaml: install names a missing PyYAML with a warning, and
  `--runner check` with a Mac's labels refuses while it is missing (wharf-runs' pickup suite writes YAML blueprints).
- ci-provider's status reads a repo's own `${{ fromJSON(vars.X || '["self-hosted",…]') }}` runs-on (a JSON label list as
  the default; an overlay repo's `suites` job since coding-ci-linux): the variable's labels when set, the default's when unset,
  so `no online runner labelled` warns again there, once per label set, beside a literal job's (ci-provider-fromjson-list,
  2026-11-06). Every other verb still holds that form as a hand edit.
- review-gate's principal route picks as a finish, with the receipt, so it names the login a landing started on under
  lighthouse's `week-max-finish`; `plan --phase build`, which a build round's prompt passes, keeps a plain pick
  (finish-ceiling's landing review, 2026-11-06).
- `checkpoint.py` pushes mid-turn (run-push-midturn): a Bash or write call's PreToolUse on a claude/* branch origin has (an
  upstream, or the remote-tracking ref of a `--no-track` branch) and with commits origin lacks starts a detached `checkpoint.py push … --spaced` once PUSH_EVERY has passed, so a long
  turn (an unattended run is one) is on GitHub as it goes: on the side ref `refs/wip/<branch>`, forced (it holds the
  newest head only), never the branch (D1-B, the owner 2026-11-06). A rewrite after it (an amend, a rebase) strands
  nothing, no PR, automerge or CI hears of it, and no branch scanner reads it as work; the branch, its `pushed`
  marker and the Stop's paging of the answer docs are as before. Every repo's pre-push template (and the knowledge
  variant) lets an agent push `refs/wip/claude/**`, never a deletion; a repo whose copy predates that refuses the child,
  once per HEAD in `push.log`: `repos --hooks` and the overlay's `bootstrap.sh --hooks` refresh the copies. New verb `checkpoint.py push <worktree>`, which dispatch runs before a lifetime end; a refused push
  names its `[rejected] … (non-fast-forward)` line, "not forced", instead of git's last hint line. One push of a
  checkout at a time (`push.lock`): a push that cannot have it steps back rather than push the same ref beside another,
  and the Stop's or SessionEnd's step-back leaves a detached verb to push the rest. `push --end`, the run's end, holds an unheld
  ready PR back too (a run ended unfinished has a half-done head), and both fail closed when GitHub does not answer;
  the HEAD it held is kept in `end-held` (GitHub not answering included), so the SessionEnd its SIGTERM sets off, a
  detached verb, a later Stop at that HEAD, sync's push of a dead run's leftovers (kept local) and pickup's /move
  hold it as well, and an `--end` refused before it judges the PR keeps an earlier hold; the refusal names the way out (a `hold` label or a draft, then `push --end`, or a new commit).
- A fleet node's runner login from one line (node-runner-user, 2026-11-05): `bin/runner-user`, run as root on a Linux node, makes or repairs the sudo-less login a runner runs as beside the node's sessions (the packages, its own group, subordinate ranges computed past every existing line, linger, CPUWeight 20 on its slice, one ssh key) and fails on a wall that is down: the login listing the node user's home, or `sudo -l -U` allowing it anything. A second run changes nothing. `ci-provider`'s refusal of a Linux host that lacks them names the script and its `scp` + `ssh -t … sudo` line in place of the list of steps; a user namespace, which the script does not give, is still named in full.
- `pr hold` (check-ci-default's landing review, 2026-11-06): labels this branch's PR `hold` as build CI's own, with check_ci.py's
  marker and ownership note, through the token, so an unattended `/finish` re-landing a ready PR holds it before its push
  (it may not call `gh`); an owner's unmarked hold is kept and nothing claimed. Step 11.2 names it.
- A Linux runner's image carries `lsof` (runner-lsof, 2026-11-06): `RUNNER_CONTAINERFILE`'s apt line names it beside procps,
  as hosted ubuntu ships it (pickup's `ide_windows` finds a VS Code window by its listening port: 19 `test_pickup` cases failed
  on a runner without it), and `.github/ci/linux-tools.sh` checks `lsof` and procps (`ps`, `pgrep`) with the other tools, so a runner whose image
  lacks either fails at setup naming the package (a hosted one installs it). A runner takes the image at its next
  `--runner install`.
- A Linux runner's berth parts (free CI S6, docs/free-ci-2026-11-03.md, 2026-11-04): the image is ubuntu:26.04, hosted
  ubuntu-latest's release, by its index digest, its packages upgraded at each build, procps added and the base's own login
  gone (the runner keeps uid 1001); the container is capped by the new live limit `wharf/ci-runner-limits` (modules/wharf/limits,
  `cpus=3,memory=12g` unless set; `--runner limits` is its trial reader), fitted to the host's cores; a user timer rebuilds
  the image weekly with no cache, its kept tarball checked against the pin first, and remove takes it away;
  `--runner check` runs the isolation cases in a container of the image with the unit's options: no /home, no mount but the
  state volume, no socket, no gh or claude config, no capability, cpu.max and memory.max at the cap, none of the host's TCP
  listeners on any of its addresses and not 169.254.169.254:80 reached, github.com:443 reached.
- A dedicated Linux runner host may hold more than one runner (2026-11-05): `<ssh alias>:<N>` in
  `wharf/linux-runner-slots` lets `ci-provider --runner install --instance 2..N` add one beside the first, each its own
  name (`<name>-<instance>`), unit, image and state volume; the host's script counts the other runner names (units,
  registrations and reservations as one set) against N. One stays the rule wherever no line names the host, as beside a
  node's sessions. Install and remove refuse a name another registration holds (a unit or volume alone included), and
  install refuses a second name from a repo whose directory registered one, each before minting a token and again on
  the host; a first install reserves the repo and name before registering, so its owner can retry or remove a failed one.
- `/finish` checks its curated, rebased tip through the PR's CI, with the final review in
  parallel, then releases only its tool-owned hold. Local inputs and live checks stay here.

- `pr ready` carries build CI's hold ownership through curation and releases the label, while
  an explicit `--hold` replaces it with a hold the landing keeps.

- Every scope has its VS Code workspace with nobody running `scopes write` (2026-11-03): `sync.py` runs
  `scopes write --from <the session's primary>` detached at each session start, so a scope added to repos.json gets its
  file at the next start on each Mac and a scope's file follows its repos (one had missed three).
  `--from` writes every open scope and a confidential one only from a session under one of its own
  folders (the fence; never by a slug in the path), moves no retired file, and waits up to a minute for
  another write's lock (giving up leaves the record as it was). What a run refused — a failed run included —
  is kept in that repo's git dir and said once at its next start there, and a fault naming a confidential
  scope the session is outside reads as one line naming none of it, so no confidential scope's name or
  refusal reaches an open session. `REGATTA_SCOPE_FILES=off` (or any value but empty or `inline`) skips the
  step (the knowledge layer's hook suite sets it), `=inline` runs it in place; `--from ""` is refused.
  `write` puts a file that lands inside a git checkout into its `.git/info/exclude`, once; asks VS Code
  which files are open only when one would change; and refuses an option it does not understand.
  A run takes the lock before it reads the registry; under `--from` a scope is open only when its flag is absent or
  false, and a fenced scope whose repos do not read refuses the run in one line naming nothing; a host with no
  registry skips the step.

- The worker briefs hand a completed build's landing to the parent or dispatch: no D-item or question asking to land its own branch. A missing step stamp is named as owed for the landing's PR.
- `pr restack` widened (restack-clean-overlap, the owner 2026-11-04 on #434: "figure out how to make resolution of
  trivial conflicts like that automatic and not rerun the CI"): a ready DIRTY PR restacks when git's plain merge
  conflicts in list files alone, so a path both sides changed in hunks that merge clean (#434's README and
  `limits`) no longer refuses; a both-sides path with a merge attribute other than union on a list file does, and
  a plain-merge conflict names its file. `.helloworld/allowlist.txt` is a list file with no merge attribute (a
  plain merge conflicts there; union revived a path main took off the list, the review's probe): `restack`
  settles its conflict with list-merge's new set merge (a path either side took off stays off, none listed
  twice), and asks for the clone's list-merge driver only where a union file needs it. `pr carry`
  compares, per file, the added and removed lines in order, mode lines included, as bytes, ignoring context and
  hunk positions, in a file that is exactly a clean three-way merge of the PR's change onto main's copy (a
  hand-resolved conflict and a moved line are refused, the review's probes); otherwise the same entries at both
  heads and forks, as before. A path the allowlist would list twice refuses. Merge attributes are read at
  main's tip and the PR's head. The red road: a ready PR whose required check's run was made before main's tip
  landed (the run's `created_at`, which a rerun keeps) is restacked onto main to a new tip, never rerun, once a
  push of the PR's own, and a head-tested status (check-linux) red on a head behind main likewise; one that saw
  main's tip gets `rerun-failed-jobs`, once a run, a refusal said on the PR. Each mark
  is written before the act it bounds, a failed push's source tip included. Nothing moves while a required check
  or its rerun runs, a cancelled run is never red, and a run whose making will not read waits. The checkpoint hook denies `gh pr ready --undo` (and the GraphQL
  `convertPullRequestToDraft`), naming `pr restack`. Suite: `tests/test_restack.sh`, `tests/test_checkpoint.sh`.

- `council run` asks each arm for a complete design on the pen's mandate, not a position paper, and `council
  examine` for an agreement round: what each arm adopts from each paper, and its stand where they disagree (concede,
  hold with evidence, or a compromise), then what only the owner can decide (the principal tier's revision of
  2026-10-30, under S4: "the other 2 models should design as well, not just consult. then they try to agree").
- `scopes set SCOPE --yard HOST` (scopes-node-yard): a confidential scope's own node is a yard too (the core's
  `scope_yard_hosts`), judged with the flag the same write leaves, so `scopes set SCOPE --yard <name>-agent` passes
  on the Mac holding the node's folder and on the node itself; an open scope naming a node, another scope's node,
  the shared node and a host nothing knows are refused, each said why.

- `pr`'s re-judge reads `--by lander` as `handed` (`handed_held`), and as a mode launch when it carries a mode flag in
  `land_by` (stuck-ships S1).
- `principal-architect`'s Receipt bullet names its completion line (`Completion: **<state>** — <why>`), a flagged
  judgement, the council's rows taken as given, and `keel lint --strict`'s principal rule; test_council.sh runs
  sextant's `bin/principal` on its stand-ins (off macOS: every arm refused, the Receipt saying so; on macOS: a paper
  and a critique per arm that answered).
- `pr restack <N> | --all [--dry-run]` (dirty-pr-rebase, the owner 2026-11-03: "We should have a tool for that now
  that resolves in finish"): a ready claude/* PR GitHub marks DIRTY only because main appended to TODO.md or a
  CHANGELOG.md is rebased onto origin/main in a scratch worktree with list-merge as the clone's driver and pushed
  with `--force-with-lease` on the PR's head, so automerge lands it. Pushed only when every path both sides changed
  is a list file merged as union, the rebase is clean, those files hold no conflict markers, `todo-md lint --base`
  passes and a CHANGELOG's Unreleased stays first; else the finding goes on the PR, once a tip. Never main, never a
  merge. `pr carry <before> <after>`: whether a push's patch is the previous head's bar the lists, which check.yml
  and check-linux.yml read to keep that head's green instead of the whole line. Suite: `tests/test_restack.sh`.
  Its review rounds: only PRs opened by the token's own login or the registry's `machine_account` (a collaborator's
  claude/* PR is theirs), never while the head's checks run or are red (a push would cancel them), merge commits
  refused, the rebased patch proved by `carry_verdict` before the push, tree entries compared (mode and type) with
  `-z` names; the workflows judge with the base's copy of `pr` and the newest `check` run. The landing review's: a
  PR labelled `hold` is left alone, a head no workflow ever ran on (GitHub runs none on a PR that conflicts) is
  restacked rather than waited on for good, and an unreadable `check-attr` refuses rather than reads as union.

- `ci-provider` on a Linux host (linux-runner, 2026-11-04; the owner: "can the node help with linux checks as
  well?"): `--runner install|status|remove --host H --name N --labels self-hosted,Linux` installs actions/runner's
  linux-x64 or linux-arm64 build (v2.338.0, size and SHA-256 pinned as the osx ones are) in a rootless Podman
  container (D1-C, the owner: "container"): an image built on the host over a digest-pinned Ubuntu (`ubuntu:26.04` since free CI S6) with
  the suites' packages and no sudo, a quadlet user unit that runs one job a container (the listener's `--once`) and a fresh
  container for the next, no host mount, socket, credential or capability, the registration alone in a named
  volume mounted read-only (and judged there, so a lost volume registers again), at `CPUWeight=20` beside the
  sessions' user units at 100 and `Nice=10`. The entry runs the listener itself and reads its exit: a refused
  registration, a session conflict or a retired version stops its unit (`RestartPreventExitStatus=3`), any other
  exit retries in a fresh container, and SIGTERM reaches the listener. An install re-registers a runner GitHub no
  longer lists. The runner never updates itself, so its pin is bumped within GitHub's 30 days of a newer release. No sudo on
  any road: what the host lacks (podman, uidmap, a user namespace with subordinate uid and gid ranges, slirp4netns,
  linger, the user instance) is
  refused at the probe, each named as the owner's step, before a token is minted. One runner a host (a further
  instance, or another repo's runner or unit there, is refused), registered by its capabilities in
  `wharf/ci-runner-caps.json` and never a label of the host's own, the token on the container's stdin only. The
  probe's `uname -s` must agree with the labels. It routes no check.yml variable: the pick does, for
  check-linux.yml. The runner script reads a size by `wc -c` and a digest by `sha256sum` or `shasum`, so macOS and
  Linux share it.
- The pick's self-hosted Linux lane for the Linux share: an Actions lane whose `runs_on` labels name Linux and whose
  `projects` names the repo with `actions`. Judged by its runner, never a budget: online, it is taken before any
  hosted lane, moving `CI_LINUX_TARGET`, then `CI_LINUX_RUNS_ON` (the `suite` job's runs-on, which check-linux.yml
  now reads, `ubuntu-latest` while unset), then `CI_LINUX_ELSEWHERE`; with no runner carrying its labels, or one
  offline more than a sweep (20 min, three readings of the desk's 15, counted from the first offline sighting the desk's `--apply` keeps in
  `ci-share-runners.json`), the share takes a hosted lane with month left, `CI_LINUX_RUNS_ON` back to its image, or
  goes off. A move back waits an hour, as between CircleCI orgs. A public repo, or one running fork PRs' workflows,
  is never given the lane, nor a check-linux.yml that reads no `CI_LINUX_RUNS_ON`; a value no `suite` job can read
  (a bare word) stands on no lane, so the pick rewrites it. The lane is never check.yml's: the runs-on pick skips it.
- The finish skill's unattended loop (landing-fixes-in-run, the owner, 2026-11-03: "why isn't the fix round part of
  the build?"): when step 1's review finds S1, S2, S? or WRONG items, an unattended `/finish` has them verified by a
  fresh `reviewer-high`, fixes the real ones in the run — a choice by the verifier's `➤ Recommended:` pick when
  `build-review picks` says `take` (Reversible: yes, no conditional pick, none of keel's held classes, a
  `physical: none` repo), written `Taken unattended (the landing by <by>, <date>): <pick>` in the report and the PR
  body — checks, records each round with `build-review round --phase finish` (the build's verifier and cap) and
  lands. It stops only on a `Reversible: no`, unmarked or held choice, or the cap; then it commits the fix round's
  brief and its Do this now dispatches that round at the landing's own priority or `high`, never a plain `normal`
  build. test_review_gate.sh checks that every `build-review` command the skill names is one the landing's allow
  rules let it run.
- `council fences` (the isolation design's S5): the monthly re-probe. One research turn per arm runs the H probes'
  nine commands and one request for a tool its start took away, each judged from the CLI's own log and printed as a
  table, a column per arm; `codex features list` diffed against the pinned list; each stream's step names judged
  against the start's lists and what agy offers against the last run. An arm a case broke is refused by every later
  council verb on this Mac until a fences run holds, row C named as the way out. Off macOS every arm is refused.
  The verdict is the CLI's (antigravity-claude follows antigravity; a broken arm of a CLI wins over a held one in the
  same run); a case counts only as asked, never batched with another, every run of it judged; a timed-out arm's
  log is still read; an arm not judged exits 3; a verdict file that does not read refuses every arm. Every copy
  also loses its `.mcp.json`.
- node-road (2026-11-02): the pre-push template reads its refs from a pipe, never a heredoc, and
  fails closed: under macOS's bash 3.2 a heredoc is a temp file, and in a sandbox that cannot make one the old
  loop never ran and every push passed. `repos --hooks` carries it into each clone.
- `/finish` step 1 off a Mac (node-lands round 1, carried by node-lands-base): the macOS-only suites' `not run on this
  host` lines are the check passing, and a publish gate with no word list is a failed check, never a skipped one; the
  host name is `hostname -s` there.
- sync: a landing whose last `autofinished` line is a stop and whose PR into main merged after it gets a
  `launched <branch> #N` line, once (`settle_landed`): helm's stalls raised such a branch for good, 83 of them
  settled by hand on 2026-10-31. Only a branch whose GitHub copy the fetch pruned is asked (TODO.md [arm-yard]).
- `bin/list-merge`, git's merge driver for `TODO.md` and `CHANGELOG.md` (todo-driver, 2026-11-02; the owner: "apply
  this to release notes as well"): by item, three-way, so a done stands when main appended, a line stays under its
  item, a CHANGELOG line stays under `## Unreleased` when main cut a release, and two edits of one item stop as a
  conflict around it alone; any other union file, a file it cannot judge, or a result that lost an added line
  merges as union, and so does a result whose line counts differ from a three-way merge's. It is each repo's
  own `merge.union.driver` (`list-merge install <repo>`, the main checkout's copy, never over a driver the repo
  set), so `.gitattributes` keeps `merge=union` and anywhere without it (GitHub, CI) merges as before; sync.py
  installs it in each repo it tends. Replayed on main's last 387 list merges: 366 exact, 17 the same lines in
  another order, 3 placed elsewhere, 1 a true conflict, none lost; of about 64,000 fuzzed merges (section placement
  only) 3 placed an item worse than union, each a release cut with a new section on both sides, 1 of the
  12,000 after the last fix round.
- `todo-md`: `lint` wants `CHANGELOG.md merge=union` where a repo has a CHANGELOG.md, and `migrate` writes it; a
  list ending on `and <n>` keeps its last number; a bare `TODO:` before `item <n>` is a code comment; an id in a
  fenced example is never done; a handoff brief may cite the item its own branch did; a module's templates and
  skills are not judged against this repo's list; `check-id <id>` says whether an id may name a new item. check.yml's
  line runs the lint, so a docs-only pull request is judged too.
- fork-read-token (2026-11-02): the fork-PR setting and the runner list, both answered to repo admins only, are read
  with `WHARF_READ_TOKEN` when the gh login cannot (`gh_read`; the desk's machine login refused the Mac lane on every
  pass). ci-provider pops the variable at its start, so no child inherits it; the token serves those two reads, as
  `GH_TOKEN` on that call alone; unread by both is still a refusal.
- `/todo`'s items are unnumbered, each with an id cited as `TODO.md [<id>]` (todo-ids, 2026-10-31): `bin/todo-md`
  lints the shape (an item without an id, a duplicate id, a numbered citation, a live file citing an id
  `TODO.md` lacks, no `TODO.md merge=union` in `.gitattributes`), lists, deletes an item by id and migrates a
  numbered list. The union line is what lets two branches that each append an item merge: without numbers two
  appends still conflicted; `lint --base origin/main` (the core's check passes it) names an item done on main that
  a union merge brought back, judged from the merge-base so a branch merely behind main is not. The template's `TODO.md` and a `.gitattributes` take the shape, and `/new-project`
  copies the latter.

- linux-on-actions (2026-11-02): the Linux share may run on GitHub's hosted ubuntu. An Actions lane in
  `ci-lanes.json` names a repo's share target `actions` in its `projects`; while it does, it alone runs the
  share and the CircleCI lanes are read and said, never chosen (with it out, the share goes off). The variable is
  `CI_LINUX_TARGET` now (was `CI_CIRCLECI_PROJECT`, never set on GitHub; an old log row of it is no runs-on flip).
  main's requirement is read from the branch first (any reader) when it lists checks, else the protection
  endpoint (admins only): the desk's 404, logbook #6. The Actions matrix runs only the suites a PR reaches
  (`share.sh linux-ids <base>`).

- `sr-architect`'s description says its effort is its frontmatter's `high`, and that a parent passes `effort` on the
  Agent call only when the owner names one or for the escalation re-run (xhigh-warning, 2026-11-01: a parent passed `xhigh` on three calls).
- `review-gate skipped --why TEXT [--base REF]` logs a landing whose review `/finish` skipped: `phase` finish, no
  agents, no `diff` or `models`; it asks `build-review covers` first and logs nothing on a no. A merge's line names
  the commit it reviewed (`head`). `/finish` asks `covers` again after step 11.1's rebase. `/finish` step 1 asks `build-review covers` first and skips its review on a tip the build's own
  loop reviewed clean (TODO.md [second-review]'s D1-B, the owner, 2026-11-02).
- `review-gate merge --phase build|finish` marks its log line as a build round's or the landing's (TODO.md [second-review]); `/finish`
  passes `finish`. A line without it, written before, reads by its time as before.
- `review-gate plan`'s principal hold routes (the principal tier's S6): with the week holding the top tier, it
  asks lighthouse's `account pick --repo <repo>` and says spawn here (this session's login has room), run the
  review from the login it names, or wait for the reset each reason names (no login has room, each one's reason
  said); a login account could not read is read once more, a minute on, then needs `account check` (a tenancy
  file that does not read: `account refresh --force`); the JSON's `principal.route` carries it. Pick's own
  room, not `--room fable`: /finish spawns both reviews on Opus, so a login without Fable room is a route, and an unread primary runs as for any pick, said as
  unread (`principal.route.unread`). A reviewer a project puts on Fable is outside the route: /finish stops on it. No answer (no lighthouse, no registry) keeps the plain advice.
  `$REVIEW_GATE_ACCOUNT` names another `account`, for tests. /finish step 1 reads the line so.
- The architects' shared body sizes a step by the block rule (trim S4, 2026-11-02): the longest run of consecutive
  work inside 300–999 expected code lines and one module's suite, cut at any owner answer, live deploy or
  `autofinish_exclude` path; under 300 merged with a neighbour, over 1,000 split; each step line carries
  `· lines: <n>`, which `wharf check <doc>` reads. architect, sr-architect, principal-architect (and sextant's sounder).
- `bin/council` records each CLI's own `--version` as its arm starts (the isolation design's S4, finding 15), read
  once per binary outside the box with no model call: per arm in run.json (`version`) and one line of the Receipt;
  a `--version` with no version number in it reads "unknown (…)", saying why.
- `bin/council` (the isolation design's S3): a run's id is a uuid, never the run dir's basename; `examine` judges
  every source the run recorded again (a brief's repo that became confidential refuses it); the Codex arm hands
  harness `--deadline`, so harness's start waits come out of the arm's bound; the dot rule in `fence_root` is gone
  (the seatbelt quotes paths); the unattended rule and the marker are the core's `common`. Its header names the
  fences F1–F7 in order. Its live table, `settings/models.json`, is on `autofinish_exclude` and `autofinish_leaks`.
- `bin/council`'s copies are written by git (the isolation design's S2): one pack of the commit's trees from
  the home, indexed in the arm's box, a commit made by `commit-tree` and checked out with `core.protectHFS` and
  `core.protectNTFS`, so a `.GIT` folder or a `GIT~1` name fails the arm, named. No attribute of the tree
  applies (an export-ignore path is there, an `eol=crlf` file byte for byte), and the copy is the arm's to write.
  The review's repo is the same with two commits, the merge base and HEAD's tree (never a clone);
  `make_copy`, `tree_matches` and the review's chmod walk are gone. The copy's own `.codex/`, `.agents/`,
  `.gemini/` and `.claude/settings*.json` are stripped (skip-worktree in the review's repo, so its diff is
  untouched) and named in the Receipt. `examine` writes the papers and the draft into each arm's box and names
  them in its prompt, never inlining them.
- `bin/council`'s Codex arm keeps its shell (the owner keeps the account's connectors, 2026-10-30): the
  `codex plugin list` gate, the text-only road and its inline files are gone, and F7 holds instead — every arm's
  login off the disk from its first vendor request (Claude's on a pipe), read at its first tool call, its strings
  looked for in everything the arm leaves; an arm failing F7 is failed and its paper withheld. The Receipt says
  where each login was. The Codex arm's proxy record now has the shape the Receipt reads (a real run would have
  crashed `council receipt`).
- `bin/council`'s arms keep their tools, fenced by where they run (the isolation design's S1): each arm in a
  box of its own under the core's `fence.py` — the seatbelt, a proxy, a scratch home, an allowlisted
  environment — with the Claude arm's Bash, Write, Edit and web tools on (no `--restricted`; Bash only while
  `claude mcp list` names no connector but Anthropic's docs), the Gemini arm reading its copy with its tools on
  under our PreToolUse hook, and the Codex arm text-only while the ChatGPT login has a plugin of the owner's
  installed (`codex plugin list`: Gmail, Google Drive, Google Calendar, Google Contacts today; the review is
  refused meanwhile, needing the shell). The record from each CLI's own log replaces the command witness;
  the Receipt prints what each arm did and the hosts its proxy saw. `--research` opens each proxy to the web.
  A commit holding an env file or a vault folder refuses every arm; a paper holding a credential's shape is
  withheld from examine. Off macOS every arm is refused (no seatbelt).
- `bin/council run|examine|review|receipt` (principal tier S3, docs/principal-tier-2026-10-26.md): blind
  position papers from an Opus arm (`claude -p --restricted`, Read, Glob and Grep), a Codex arm
  (wharf-runs' `harness` research mode) and a Gemini arm (`agy` headless, Gemini 3.8 Flash High, the
  brief and named files inline, "Do not use any tools" first), each on its own read-only copy of the
  commit's tree (from git's objects: no `.gitattributes` export rule applies) outside ~; a blind, shuffled cross-examination; the build path's `codex exec review` on a
  two-commit scratch repo; and the Receipt (requested and observed, login, cost, completion state). A
  confidential scope's repo or an unreadable registry is refused before any copy; a guarded home, brief
  or draft needs each vendor's quote (the gate's `vet`, per source); the Claude arm's login is judged by
  lighthouse's `account allowed` first; an arm without its fence is refused (the Gemini arm's includes
  agy's PreToolUse hook answering ask or deny when run); a Codex command naming a path outside the copy,
  a Codex item the witness does not read (an MCP call, a web search) and agy's empty SUCCESS each fail
  their arm. The rows `council.opus`,
  `council.codex`, `council.antigravity` and `council.antigravity-claude` (off) ship in this module's own
  `settings/models.json`; the config dir's `wharf/models.json` wins over it.
  The landing review's fences (2026-10-28): `--approved` refused from an unattended caller; the run dir
  0700 and marked `.council-run`, each whole-repo copy removed when its verb ends, the Gemini arm given no
  copy (its named files read from the commit, capped in UTF-8 bytes) and its prompt on agy's stdin as one
  stream-json message, never argv; a tool step agy did not deny fails its arm; agy's settings holding an
  unknown key or not reading refuse it, and the stand-ins' settings paths count only beside a stand-in
  agy; the Codex witness also flags a bare `/`, `$TMPDIR`, `$OLDPWD`, a cut `${PWD…}`, `cd -` and
  pushd; the Receipt's login read back (`account which`, the config dir's `.claude.json`, `codex login
  status`; "unknown" for agy), its observed model from claude's modelUsage and agy's init event, "not
  reported by <cli>" for the rest, and `codex exec review`'s all-zero usage said so; a review's scratch
  repo failing records a failed arm, and `receipt` of a dir with no run.json is refused.
- `pr`'s sweep-gate re-judge takes a `handed` run (task-shape S2): judged by wharf-runs' `handed_held`, as its
  start was, so its own edit into a gated path readies (D1-C), and by the mode now: ask, or a mode that will not read,
  holds it, unless its start held it already, on the mode or by `handed_held` (then readied with the `hold` label); with rule M it is re-judged as a
  mode launch. Its stop names the hand-over, not the sweep. The brief and handed roads read no `--name-only` diff
  they never use.
- `ci-provider --pick` (ci-two-orgs, 2026-11-01): the Linux share runs on the CircleCI lane with the most month left
  above its reserve, moved by the repository variable `CI_CIRCLECI_PROJECT` to the project the lane's `projects` names
  for the repo; off when no lane has any, or when it may stand on a lane that is out and cannot be moved or told. An unread lane is never chosen, a move waits an hour unless the lane it
  leaves is out, and the project is written before the share comes on. With no lane naming a project the first is
  judged as before, unless the variable holds a project no lane names, which turns the share off.
- `ci-provider --runner caps` (2026-10-31): each runner's custom labels set to its capabilities in
  `wharf/ci-runner-caps.json`, one PUT per runner, additions before removals, each write's rollback printed
  even when its read-back differs; refused before any write when a runs-on, a variable's or a literal one,
  would be left with no runner, or when `--name` names no runner.
- `--runner install` registers a runner listed in that table with its capabilities, plus any own label of the
  labels key a runs-on or a variable in any workflow still asks for or a file no reader judges names, said; the
  variable it routes never takes that label. A label the runner would not carry is warned of. An already
  configured runner's labels are set by `caps` before the wait for it online.
- `--to self-hosted`'s literal form names what the repo needs, not a machine (2026-10-31): `[self-hosted, macOS,
  <capabilities>]` from ci.json's `needs`, which now takes capabilities beside the lanes' words (no OS named:
  macOS; another OS is refused, for the variable form) and crosses a switch; a literal naming the labels key's labels stays the tool's own,
  and a re-run replaces it, saying so. A `needs` label no runner in the table lists is warned of. The labels key
  keeps the runner's name. The pick meets a capability only on a self-hosted lane naming it, and reads a
  literal on the lane whose list holds it.
- `--runner caps` judges runs-on it did not (2026-10-31): `[macOS, x]`, the label alone, a block list, a quoted
  key and a variable holding one label, in the checkout and on origin's default branch, fetched, which GitHub runs
  until a branch lands, and unread is a refusal; anything but plain labels is unreadable, which refuses a change
  taking a label its text names off every runner, and is said otherwise. Status reads such a literal before the
  labels key, and claims nothing of one it cannot read. The host-write scan reads a literal naming `macOS`.
- The self-hosted kind is `self-hosted` everywhere (2026-10-31): `wharf/ci-runner-kind` now lists older names,
  which ci.json and `--to` read as the kind and `--to` writes back as `self-hosted`. An overlay's key needs no
  change.
- `test_ci_provider.sh` reads YAML with PyYAML rather than ruby, which a Linux node may lack.
- checkpoint's vendor guard denies the kick roads dispatch's deny list names (`dispatch --kick`, `dispatch-queue
  kick`, `dispatch-rc kick-listen`): queue S8 and the Codex guard landed side by side, and the suite's count of the
  list failed on main (the fix landed on main by itself, with no entry; this line records it).
- The finish skill removes a `pickup seed --from` `.review` with its brief on both roads (`git rm` and `git mv`):
  a `.review` left alone made every later dispatch of the branch refused for good (S6's sixth landing review).
- `ci-provider --pick` switches a repo's Linux share by the CircleCI lane's budget (ci-budgets, 2026-10-31): where
  check.yml reads `CI_LINUX_ELSEWHERE`, an over-budget or unread CircleCI account turns it off (the runner takes the
  whole line, and check-linux.yml posts check-linux green itself), and an account under budget turns it back on only
  while main requires check-linux, an hour after the last off; it goes off too when main stops requiring it.
  Same `--apply` guards and log as the runs-on flip; a refused share write exits 3 and leaves the runs-on half running. `gh` missing from PATH is an
  unread answer, not a traceback.
- The Codex and Antigravity guard (`hooks/checkpoint.py`, `vendor_denied`) denies `dispatch-queue kicked`, the kick's
  receiver, which is on no list of dispatch's but which Claude's substring rule `*dispatch-queue kick*` denies (queue-rank,
  2026-10-31).
- `ci-circleci rerun JOB` reruns a job's workflow from failed: once, only a workflow that ended failed or error
  and neither has a rerun nor is one; its pipeline ran on the checkout's branch (or `--branch`'s; job numbers are per project); it returns once the rerun is listed (up to `$CIRCLECI_LISTED_WAIT` s, 0 to 600, read before any request), and a POST that failed says the rerun may have started. `wait` judges the newest workflow of each name, so a green rerun beside its failed
  original exits 0.
- The finish and evacuate skills state their lines with their marks (✅, ⏳, 🛑); checkpoint's declared-line
  refusal suggests the marked WAITING FOR SOMETHING line.
- `session_status` reads WAITING FOR NOTHING (the core's `idle` kind) as done.
- checkpoint judges another CLI's call (vendor-hooks, 2026-10-29): a payload from lighthouse's
  `vendor_hook.py` carries `regatta_cli`, and meets every gate — D1's deletions, the push and tracking denies, a
  write on a primary's main — but takes and honours no worktree lock and records no carry (VENDOR: no vendor
  session reports the end that frees a lock). An unattended one (either marker name, the core's helper) is refused
  every verb on dispatch's launch-time deny list (`vendor_denied`: `git push`, `gh`, `ssh`, `scripts/deploy.py`,
  `pr merge|ready`, the queue's verbs, `requeue` among them since the finish review of 2026-10-31), each judged on a simple command's words; test_checkpoint.sh reads the list
  from dispatch and fails on an entry it does not deny. A vendor call remembers no claim either.

- checkpoint denies every session, attended or not, a hand write of the force mark
  (`force/` in run-seed's cache folder, dispatch-queue S4): it stands for the owner asking for "force" (any wording since 2026-10-30);
  only wharf-runs' `force_mark` hook writes it and only dispatch spends it. Reading it stays allowed.

- `finish-stuck-rebase` says it needs git 2.40 or newer at its start (exit 1, nothing changed), and its
  suite fails once naming the floor on an older git: macOS 12's Apple git 2.37 failed it with
  `fatal: ref HEAD is not a symbolic ref` on a 2016 runner Mac (2026-10-28).
- `branches.seed_task` judges a seed made off another branch's tip (`Seeded-From:`) from that tip, and
  `seed` is a whole carry kind; `pr carried` reads the repo's `carried` pointer beside the worktree's
  (routed comments S3).
- `/finish` step 5 removes a seed's `.review` with its brief (confidential-reach S5).
- `ci-provider --runner install`: a runner whose frozen LANG is no locale on its Mac (C.UTF-8 from a
  newer Mac's ssh, on macOS 12) takes an installed UTF-8 one and restarts, so its jobs no longer run
  in C (ci-fleet follow-ups, 2026-10-27).
- `ci-provider` status says where an automerge.yml reading `<var>_AUTOMERGE` runs, and the runner-Mac scan reads that form.
- `ci-provider --runner` serves a fleet of runner Macs: the osx-x64 build beside osx-arm64 by the Mac's
  `uname -m`, `--host`/`--name`/`--labels` for a further Mac, `--instance N` for a further runner on one
  Mac, and an install that never narrows or re-routes a variable other registered runners serve. The
  split runs-on form (`NAME_FULL` for a push, the nightly run and a hand start) is read and kept as the
  variable form, and status reads both (ci-fleet, 2026-10-27).
- `bin/ci-circleci`: a repo's CircleCI runs through the API (trigger with parameters, wait, step output,
  artifacts), the token read from the main checkout's `.env` and sent to CircleCI's hosts only (circle-linux,
  2026-10-26).
- checkpoint's 🐑 failure hint names `keel sheep <doc>`, not `memo sheep` (peer-manager-relay, 2026-10-26).
- `branches.seed_task` takes a routed seed for a seed (`seed_paths_ok`): a doc the commit's `Routed-By:`
  trailer names, changed by its `Routed:` line alone, besides the brief, so the reaper and the archive's
  dropped-seed road see it (routed comments S2's landing review, 2026-10-26).
- `ci-provider REPO --pick [--apply] [--usage FILE]` (lighthouse-ops S1, the owner's D2-A): the lane a repo's
  check takes, from lighthouse's `ci-lanes.json` and `ci-budgets.json`, its ci.json `needs` (absent: macOS),
  the trust refusals on every self-hosted lane and an online runner, the sampler's queue; hosted minutes only
  on the desk's fresh usage, else over budget. `--apply` writes the runs-on variable on `lighthouse/ops-host`
  only, only in the variable form and only on a change, logging the old value and its undo to `ci-pick.jsonl`.
  A hosted lane's `runs_on` is a hosted image's name (`ubuntu-*`, `macos-*`, `windows-*`); a repo whose
  current lane it no longer fits, whose runners are unread or whose check sat queued exits 3 when no other
  lane takes it.

- checkpoint never pushes a branch that already landed: before a push, `publish()` asks GitHub
  (`common.landed_pr`) whether a pull request from the head merged while none is open, and if so
  keeps the commits local, opens no WIP PR, and tells the session its worktree is spent, with the
  fresh-branch recipe by absolute path, on screen at Stop and to the model at the next prompt. The yes
  is kept per branch in the state dir's `spent.json` with the origin ref beside it (one lookup per
  spent worktree; asked again once that ref moves); a PR whose merge commit HEAD holds (a reused name),
  one into another base, or one from another head is no yes; every GitHub failure pushes as before.
  sync's `push_left` leaves no retry marker for such a branch. A session in #169's old worktree had pushed it back and opened the stale #171
  (night-landings finding 3, 2026-10-25).

- The template's `check.yml` and `automerge.yml` key their concurrency group on draft (`…-draft` / `…-live`), so a
  `synchronize` run that still says draft, and skips, can no longer cancel the `ready_for_review` run
  started a second before it (the 2026-10-25 race; regatta's own the same). A repo made
  from the template before this copies the line by hand.

- The template's `check.yml` names its job `check (draft)` on a draft, so the skipped draft run no longer reports
  under the required `check`; its `automerge.yml` reads the last 20 `check.yml` runs on the head, filtered to those
  not skipped, instead of the newest alone, and reads `hold` live before arming (ci-draft-race step 2, 2026-10-27). Read back live on a draft head: a
  skipped job reports the name expression's text, never `check`.
- `review-gate plan --principal` (principal tier S5): a principal build gets the top tier (reviewer xhigh, CR
  xhigh) at any size, and a tight or lowest week holds it rather than lowering it, saying to review from a login
  with room or wait; a branch whose own brief names a principal tier is found without the flag (through
  wharf-runs' blueprintlib, a peer). `/finish`'s review step says so. A brief that says principal unclearly is
  read as principal, and one `/finish` step 5 removed is read as it stood before.

- Two principal heads (principal tier S2, docs/principal-tier-2026-10-26.md): `principal-architect`, Fable at
  `xhigh`, a fourth head on the architects' body with no probe cap and a mandatory Receipt; `principal-worker`, Opus
  at `xhigh`, on `sr-worker`'s body, which gains a shared marker, with a pre-mortem and a Receipt in its hand-back.
  `test_agents.sh` holds both shared bodies and each head's model, effort and Receipt line.

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
