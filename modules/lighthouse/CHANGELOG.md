# Changelog — lighthouse

## Unreleased

- vendor_hook decides two things of its own for an unattended Antigravity run (vendor-road-fixes):
  a tool allowlist (AG_TOOLS, plus agy's `command_status`, `wait` and `wait_5_seconds`, which touch no
  path; `read_url_content`, `run_command` with `BypassSandbox` and every other tool denied), and a deny
  of a file-tool write into a `.git` folder for Codex and agy alike. builder-host's sweep now re-applies
  the entry for agy too, so the note below on "no re-apply in its sweep" holds only for a host made before.

- The login guard (2026-11-06): `account` never picks a Claude row whose home is not signed in (`.claude.json` holds no
  `oauthAccount`, or neither `.credentials.json` nor, on a Mac, the keychain holds a login) or is signed in as another
  account than the logins file's entry for the row (its `email`, or an `account_uuid`). The refusal leads judge's
  reasons on every road: pick and `--cached`, a pinned ship (it moves), the overdraw pass, the primary's at-once road;
  `limits` (a `login_off` field), `check` and `doctor` say it. With neither the logins file nor its local copy, the
  primary is refused (its login cannot be checked) and the other rows are judged as before.
  A logins file or copy that is there but does not read refuses every row; where an entry writes `account_uuid`, it
  alone decides. dispatch reads the guard's refusals as host-local on an unpinned walk of a fleet entry, which is
  queued again; a pinned entry, a host-local store's or a named login fails plainly (wharf-runs' CHANGELOG).
  Where a row takes a shared login from a row the guard refuses, the duplicates marked before it name the row that
  took it (`same_as`), never the refused one.
- Design handoffs stay in the repo that owns the work; routing no longer asks for a sibling with a `physical:` contract field.

- vendor_hook answers Antigravity with nothing on an allow, and its trailer
  rewrite as `overwrite` beside `"decision": "allow"`: agy 1.5.2 denies a call
  on `{}` and on an `overwrite` with no decision (probed on a Linux node), so
  an Argon build whose only hook was regatta's would have every tool denied at
  its first turn, and agy's simple commits were refused on the laptop. The
  entry's launcher text is unchanged (its gone-adapter `{}` stays, a deny on
  agy): a change there rewrites every Codex and agy entry, and agy's builder
  compares its entry exactly with no re-apply in its sweep (TODO.md
  [agy-ff-reapply]).

- agy-pick-orca (2026-11-06): for an Antigravity row (`"provider": "antigravity"`), `account`'s `limits()` (live and
  `--cached`) reads Orca's `antigravity` card on this host (`session.usedPercent`, `weekly.usedPercent`, resets, and
  `updatedAt` as the reading's sample time, settled as percent used against Orca 1.4.245's `1 - remaining_fraction`),
  and `judge()` applies the row's week ceiling, window rules (`pace()` at sample time) and lock check as for a Codex
  row, so `account pick --provider antigravity` answers the row and wharf-runs' `harness run --harness agy` needs no
  stand-in. Reads only where the row's home exists and is `run_home("antigravity")` and at most one Antigravity row is
  enabled there (Orca's card names no account: two enabled rows refuse); a card over 1 h old (`ORCA_MAX_AGE_S`, matching
  `orca_wake`) or a headless Orca fails closed as unknown, and a live pick never runs such a row through the tenant's or
  the primary's unknown-limits fallback (a `--cached` pick, the vendor fence's ownership read, still does). `account
  check` marks an Antigravity row with no fresh card ⚠. `dispatch --harness agy` still has no registry or Orca reading on a
  builder host, which the builder arm owns. Cases in `tests/account.sh` and wharf-runs' `tests/test_agy.sh`.
  On a fenced repo the fence's `--cached` check now refuses an Antigravity row whose fresh cached card is past its
  ceiling or window rules, while a stale or missing card still passes through the tenant fallback, and the council's
  Gemini arm has no live pick after it. A lock's skip line names the latest reset among the locked windows, a Codex row's too.

- `ci-lanes.json`: a self-hosted lane's `share_runs_on` (README, Private values), read by wharf's ci-provider pick (mac-share-lane, 2026-11-06).
- Account limit pairs (account-limit-pairs, 2026-11-07): every account limit now has one shape — a `soft_max` (a lift
  may pass it: pace on either window, and `--overdraw` on the week) and a `hard_max` (nothing passes it) — across both
  windows: `week_soft_max` and `week_hard_max`, `week_finish_hard_max`, `week_lend_hard_max` (hard: neither pace nor
  `--overdraw` lifts a lent row past it), and `window_soft_max` (lowered by exhaustion margin) and `window_hard_max`
  (default 90, on a row the pair reaches: one with a new window key, budgets.json's `*` included; old keys keep their reading). Week pace lifts a row past `week_soft_max` while its week spend is under the week's elapsed share at the
  reading's own sample time and under `week_hard_max`; `--overdraw` lifts `week_soft_max` up to `week_hard_max` (100 when
  none is set), and `reserve` raises `week_soft_max` on `day` or `last_hours`. `budgets.json` takes `"*"` for global
  defaults (`budgets.json` row > `budgets.json` `*` > registry row > default). `modules/lighthouse/limits` declares
  `lighthouse/week-soft-max`, `lighthouse/week-hard-max`, `lighthouse/week-finish-hard-max`, `lighthouse/window-soft-max`
  and `lighthouse/window-hard-max` (`account limit-read`); old JSON keys (`week_max`, `window_max`, `free_below`,
  `pace_headroom`, `lend_max`, `reserve.week_max`) and old live keys (`week-max` own hard / `*:` soft, `week-max-finish`,
  `overdraw-max`) keep reading as aliases, with a single stderr warning when both old and new are set on the same row.
  A registry ceiling rule present but no number (`week_soft_max`, `week_max`, `week_hard_max`, `window_soft_max`,
  `window_max`, `window_hard_max`) refuses the row, naming the key, rather than read as its default.
- `lighthouse/overdraw-max` (`<login>:<pct>`, `*:<pct>`, set live via `regatta limit`) caps the week bar `account`'s `lift()` judges a lifted row at in place of 100, naming `to the overdraw ceiling N%` (absent or invalid, 100, a login's bad own line leaving `*:` to serve it, an unreadable file said on stderr; finishes keep `lighthouse/week-max-finish` and own `week-max` or finish-ceiling rows stay unlifted).
- The lend bar (2026-11-05): `rules.lend_max`, in the registry or budgets.json, is a week ceiling for every repo
  that is not the login's own (its scope's or its tenant's); its own work keeps `week_max`. Past it, `pick` and
  `limits --repo` refuse another's repo in judge's week wording, and a ship pinned there moves to another login;
  `limits --repo` says `lends`, which dispatch's --next reads; a `lend_max` that is present but no number from 0 to
  100 lends nothing. `pick --overdraw` lifts a lent row last, after every other row past its own week ceiling, so
  the tenant's own room is spent last. First use: a tenant's login at 50% for anything but its tenant's repos.
- Finish ceilings keep the normal week ceiling when the live layer is inaccessible, including on
  Python 3.14 where path predicates suppress permission errors; a readable base never widens that failed read.

- `lighthouse/week-max-finish` gives launcher-proven finish picks a higher weekly ceiling, per login
  or `*:`, without admitting builds. `account pick --for finish` alone grants nothing: the launcher
  supplies a consumed pipe receipt. Invalid or unreadable values keep the normal ceiling; valid
  values never exceed 100 and only raise it. Verdicts name `finish ceiling`. A `*:` line reads as `week-max`'s, over a
  row that sets no ceiling of its own; a line that is no ceiling turns `*:` off; the overdraw never lifts a row this
  ceiling judged, so a line holds on the launchers' `--overdraw` road. Cases in `tests/account.sh`, a Codex login's
  among them.

- The Engine room's S4 (docs/engine-room-2026-11-02.md): `hosts sample`'s row carries `checks` (this login's wharf-runs
  check slots: busy, cap, waiting) and `features` (`dispatch-queue features`), and its `records.stale` counts what
  `dispatch-rc settle --stale` would end, so one Settle clears it. `hosts --json`'s queue entries, finish entries
  among them, carry `pin_kind`
  (`typed`, `login`, empty for none or held; an unknown kind null), `pinned_why` in fixed words (never the reason's
  text: no commit, path or branch) `by`, the waiting session's first 8, and `pin_login` (its run names a login, so repin never moves it; never the
  label). `ops`' check count skips a pid of 0 and check's ticket being written, as `hosts` does. Cases in `tests/hosts.sh`.

- `hosts sample`: a named node's row carries its scope as the core's `scope_marker` (`scope`, never the name;
  `confidential:unread` where `wharf-runs/node/scope` does not read, through the core's node reader, so a link whose target moved is unread), so hail's message discovery skips a confidential
  scope's node whatever it is named (node-hail); a named node rendered before that key takes the core's own verdict
  from its `wharf-runs/node/clones` (`nodes_here`). A builder user's row (`wharf-runs/host` set) carries `builder: true`.
- reef grows a host back once its median and newest load are under 0.6× load-max, with at most one sample at or over
  that and none over load-max (2026-11-04; it was every sample under half). A hold now names what kept it from cold:
  the laptop, at its floor all day, is held by memory (free never over 2× headroom's avail), not by load.
- overdraw (2026-11-04): `account pick --overdraw [--job TEXT]` — with no login under its week bar, the first in
  the walk refused by that bar alone runs the job while its week is under 100% (its callers ask for a build of priority
  high or force and for every finish); every earlier refusal and the
  5-hour rules still judge, a row with `rules.overdraw: false` is never lifted, a primary only with
  `rules.overdraw: true`, a login's own live week-max line holds, and a primary of unknown limits waits for the
  pass. The pick only decides; `account overdraw-log` logs it once the job started: a line in the log dir's
  overdraw.jsonl and a note in the logbook (helm's `issue_note`: one issue per login and week, then comments).
  The core's Orca row loses its 100% last-day reserve.
- tenant-unknown-last (2026-11-04): `pick --repo` of a tenant's repo runs an unreadable own login (one not
  signed in yet) only once every row was tried, so it no longer shadows a later login of the tenant that is
  eligible; `pick --ship` moves a ship pinned to such a login there too.
- The budgets file's edges (budgets-edges, 2026-11-02, from #360 and #401): an owner's cap is a cap — inside a row's
  `reserve` window (`day` or `last_hours`) a budgeted `week_max` that tightens the row (below the registry's own
  `week_max`) and is lower than the reserve's reads in its place, named `<the window>, capped by budgets.json`
  (before, the reserve lifted a tightening budget). The session's pick, reversible: the brief's min() is taken for a
  tightening budget only, so a loosening one (the live file's two rows) keeps its reserve as before, and on a row the
  budget tightens, a login's own live line (`regatta limit`) takes the budget's place there as on any day (a tighter
  one caps the reserve, a looser one leaves it); a row no budget tightens judges as before, a live line included. A label no row has is said on stderr outside
  `--json` (not for one the logins file lists for another host only) and by `doctor` (`budgets.json names <label>, which no login row
  has`: a fix, or info where the logins file lists that login for another host); no row changes. A removed source
  leaves no stale copy in force: past its gate, `refresh` removes `.budgets.json.last` where the key is gone, or its
  link's file is missing ("no such file", never another stat error) from a folder that is there; a drive away keeps
  the copy, and outside claude-host, where a key links into a drive, refresh still refuses. `doctor` names a copy with
  no source, and, outside claude-host, a copy that differs from its file and was refreshed within 30 min (an edit the
  tick has not copied yet: it copies only under claude-host). `budgets_candidate` runs once per pass
  (`budgets_link_text` folded into it); cases for `link_budgets`' FileExistsError race and the scratch link's OSError;
  comments cite #401 for "the build's round N". Not changed: a budgets link refresh made stays on the old vault's file
  after the tenants key is relinked (refresh never replaces a link; `doctor`'s info line offers the relink), and a
  file Drive deletes and recreates during a tick drops the copy until the next one. From the landing review: a
  later refresh that finds the source still removed and no copy left exits 0 (the tick's exit 1 stays a real
  outage's); doctor's dangling-link line outside the tenants target's folder is a fix where that folder is there
  (the vault moved); doctor's unmatched label listed for this host says to add its
  row; the not-copied-yet line offers no `refresh --force` (from a shell it opens the link outside claude-host);
  the live line is read in a reserve window only on a row a budget tightens, so a bad line's warning no longer
  names the registry's rule where the reserve judges; the core's G4 fixture names a label no row has. From the
  `/finish` review: a link whose file is gone while a budgets.json reads beside the tenants link's target (the vault
  moved) keeps its copy, so a tightening cap holds until a person relinks; refresh's line says so.
- `reef seed` (2026-11-04): a host with no `lighthouse/reef` line (nor `*:`) gets
  `mode=on,run=1-<cap>,check=1-<slots>` from its own limits; a new node's clone unit asks for it once as it joins the
  fleet, and its first sweep seeds (`reef apply --seed`). A hand set outside the bounds holds while its range stands.
- reef (2026-11-04): each host tunes its own check slots and run cap from its measured load, within the owner's
  `lighthouse/reef` bounds (a live limit); the sweep's `hosts sample --put --refresh` starts `reef apply` on a host
  with a line. Hosts at 2-6× their load limit while a new node idled was the cause (the owner, 2026-11-04).

- finish-as-task (2026-11-02): `hosts` keeps the fleet store alone, a finish being a fleet entry now; `local=_land`
  is gone with the Mac-local landing queue, and a run claimed from any `local=` store counts as confined.

- deny-drift (2026-11-03; the owner, 2026-11-02: "remove this denylist cruft and rely on confidential scopes only"):
  `account` reads no row's `"repos": {"deny": […]}` any more, in `pick`, `limits --repo`, `allowed`, `run` or
  `holds_denied`; tenancy (the vault's tenant included) and a scope's `login` route, and the walk's order says which
  login goes first. `doctor` names a row still carrying the key, and a `regatta/orca-deny` that names a repo, as a fix
  (`ignored since 2026-11-03`); the deny-list workspace roster (`denied_workspaces`) and the G3 line about deny entries
  tenancy derives are gone, `tenant_ties` covering a workspace that opens a git repo. `denied(…, routes=False)` and
  `holds_denied(…, deny_list=…)` keep their signatures for any caller. An Orca dir no row names is named so in a tenancy
  refusal; one signed in as a row's login keeps that row's label (the contact-book hook reads it). One wall a list
  may have been fails closed: a row whose ignored list names the vault, on a host where no tenant holds the vault,
  stays off it until one does, a shell moved into it included, and `doctor` (with or without a logins file) says to write the tenant first. account_guard's header says the same. A `regatta/orca-deny` naming the vault does not hold it: where no tenant does, doctor says so.

- An account's cooldown and margin count only its own exhaustion records (cooldown-account, 2026-11-02): the primary's
  week lock, in an Orca login's profile log, held that login a day past its own reset. A record whose `account` (or,
  where both carry one, `org`: a new record stamps it) is another seat's is ignored; one with no `account` (or a value
  that is no id), or a home whose login does not read, counts as before. Orca's profile setup mirrors the default
  config dir's top-level files into each profile at each selection (a copy, read live; a link is handled the same
  way), so a profile's `exhaustion.jsonl` may hold the primary's records, which are skipped; a write dedupes only
  against its own seat's records. The copy also drops the profile's own records until it records again (the doc's
  Left open). The same copy took `usage-probe.json`, so the profile's row read the
  primary's whole reading: a probe's cached reading is now stamped with the login it read (`account`, `org`), and
  `limits` reads one of another seat, or, on an Orca row, one with no stamp where the home's login reads, as no
  reading (an unstamped one elsewhere is the row's own, so the caches written before the stamp still read) — it probes
  again, or under `--cached` reads unknown, and a failed probe never falls back to it; `check` and `doctor` name such
  a cache (info).
  A write whose home's `.claude.json` reads no login (after one re-read) records nothing, and `account exhausted`
  exits 0 with a stderr line, so the status line does not retry at every render; a log that cannot be appended to
  records nothing and exits 1, so it tries again. A time written as a quoted number reads as that time. `check` and `doctor` name a log that is a
  link or holds another seat's records still in force (info; a fix for a link on a row whose login does not read).
- fork-read-token (2026-11-02): `ops pick` passes the desk's `GITHUB_TOKEN` to ci-provider as `WHARF_READ_TOKEN`,
  for the admin-only reads the machine login cannot make (the fork-PR setting, the runner list); the token needs
  `Administration: read` on the repo. A `WHARF_READ_TOKEN` the job inherited is dropped, never forwarded.
- `account refresh` links the budgets key itself (budgets-link, 2026-11-01): where `lighthouse/budgets.json` is
  neither a file nor a link, `tenants.json` is a link, and a `budgets.json` sits beside that link's target, it links
  the key there, past its own claude-host gate, so a new host or a rebuilt config dir reads the owner's budgets within
  the usage tick's 15 min with no hand-made link and no overlay line. It never replaces a file or a link; `doctor`
  names a key it would link (`budgets_candidate`), a sibling it refuses (itself a link, or one `drive_backed()` would
  judge otherwise than the tenants link), a budgets link that leads nowhere (an `rm` offered only where refresh would
  link it again, a fix only where the dead link pointed into that target's own folder) or no longer sits beside that
  target, a live link whose text reads as outside a drive while its file is in one (the hooks would open the drive
  outside claude-host; relinked by its real path), and stays quiet on a plain file. A deleted key is linked again: a plain `{}` keeps a host on the registry's
  rules.
- A live week ceiling (live-limits, 2026-11-01): `lighthouse/week-max`'s `<login>:<pct>` stands over that row's
  `rules.week_max` in `account`'s ceiling, `*:<pct>` only over a row that sets none (a reserve still first); `account week-max LOGIN` reads it, and
  `regatta limit` sets it.
- `account pick --room fable` (the principal tier's S6, docs/principal-tier-2026-10-26.md): only a Claude row
  whose reading carries a weekly window scoped to Fable, that week under the row's week ceiling; a row whose
  plan lacks Fable (the Pro fallback) is skipped, and one whose Fable is unknown too, the primary included (no
  "rather than nothing" for a head that may not run). Exit 3 when none has room. An unknown room, or `--room`
  with a Codex provider or kind, refuses with exit 3 before any probe, never the plain walk an unknown `--kind`
  falls back to (an unknown room before the registry is read). A ship pinned to a row whose plan lacks Fable, or whose
  Fable room is unknown, moves; one whose Fable week is full waits. A plan without Fable leads a row's skip.
- `account limits --hide AGENT:FAMILY` drops one bucket family of an Orca agent's card from that call's answer, its 5h
  and week taken again from the buckets left (`hide_families`); each Orca bucket carries its `family` and `win` in the
  cards' words (`bucket_words`: Gemini 5h, Claude/GPT week). The widget passes it; the desk never does (2026-11-01).
- A confined routing login is named in its tenant's `"confined": {label: [key or glob]}`, never in `logins`
  (agy-confine-fail-closed, 2026-11-01). The tenants file is one file in the shared drive and every Mac reads it at
  its own lighthouse: an account older than the confine read `logins` alone, so a label there owned the whole
  tenant, the vault included, on that Mac (the account before the first confine answered `owns: true` in the
  vault's repo; a case runs it from the history). Out of `logins`, an older account takes the row for no tenant's
  and refuses it the tenant's repos. `tenant set --confine LABEL=KEY,…` writes `confined` and refuses a label
  `--logins` also names; a set without the flag keeps and re-judges the confine (one that drops a covered repo is
  refused); a bare `--confine` drops it. The first form, `"confine"` beside `logins`, now confines each label it
  names to nothing until a set rewrites it, and no writer widens it: a set without the flag carries it over as
  `confined` once the label leaves `--logins` and refuses while it is still there, an explicit or bare `--confine`
  refuses the same, a label none of `logins` is never made a member, and `tenant drop`'s vault restore line moves
  it into `--confine` and leaves out the routing logins of an entry that does not read. A `confined` that is no object, or names a label no codex or antigravity row has (a typo, a seat),
  confines every routing login in the entry's `logins` to nothing. Doctor names each of these, a label in both
  keys and a Claude row in `confined`, and says where a label two tenants hold sits in each. vendor-hooks gives a
  confined login's home its tenant's layer, as one in `logins`, and reads a string `logins` as one label. `account add` on an Antigravity row says agy keeps
  its login itself, never Codex's sign-in line.
- `account`: a Claude reading whose `limits[]` names `weekly_all` and only weekly kinds has no 5-hour window and is
  judged on its week, as Codex prolite is (the primary's, 2026-11-01: get_usage's `five_hour` null and the inference
  headers' week alone, read as "limits unknown" and refused by `pick --ship`); `limits --json` says so per row,
  `no_five_hour`, and the text says "5h unknown" for a lost figure. `pick --ship` takes a primary whose reading lost its
  figures, as `pick` does. `limits --hide LABELS` leaves rows out, a hidden registry login unprobed (the widget's
  `plumb/widget-hide`).
- `bin/hosts` (the Engine room's S2, docs/fleet-page-2026-11-01.md): `hosts sample [--put]` builds this host's row from the
  run record files (never `dispatch-rc status`), headroom, the slots and the cached logins, fenced by the core's
  registry_unreadable() and scope_resolver (every scope walked; a confidential run a count), and `--put` hands it to
  `dispatch-queue hosts put` (`--refresh`, the sweep's: whatever the row says); `hosts --json` merges the ref's rows, the fleet queue and `local=_land`, the logins by label
  and the peer records. `tests/hosts.sh`.
- `ops sample`'s `weeks` carry each reading's `sampled` time, `here`, and Orca's agents (Antigravity, Cursor) as `report`
  rows; after the row the desk's job reads again, one `account limits LABEL` each, every login set up here whose reading
  is over 30 minutes old, at most once a half hour (account's probe: no model call, no new login), and says which
  came back fresh; `week_cap` leaves out report rows and readings over 6 hours old; `ops status` gives each reading's
  age (2026-11-01: the desk read whatever its host's last pick left).
- `lighthouse/ci-lanes.json`: a CircleCI lane takes `projects`, the project of its org per repo, which wharf's pick
  moves the Linux share to (ci-two-orgs, 2026-11-01).
- A tenant's logins may name an Antigravity row (agy-tenant, 2026-10-31: the owner's word to put another person's
  agy login, its telemetry off, in the owner tenant): `"provider": "antigravity"`, its home agy's own
  (`$GEMINI_CLI_HOME`, else `~/.gemini`). `pick --provider antigravity --repo` answers the tenant's own and says it
  `owns` the repo, the vendor fence's yes, as a Codex row does; `tenant set` takes the label only while its home is
  the one an agy run here uses. The row routes only: it sets no environment (agy picks its keychain login
  itself), is never probed, `limits --all` leaves it out (Orca's report card is its figure), `check` reads no
  login of it, `run` refuses it. The tenant routes, the skip line and doctor's roster name each routing vendor's
  rows (`codex`, `antigravity`), not Codex's alone. Its home binds no account, as a Codex home does: the row stands
  for whichever agy login the Mac's keychain holds. Cases in `tests/account.sh`.
- A tenant may confine a routing login to part of its repos (the first form, replaced by `"confined"` the next
  day, the entry above): `"confine": {label: [key or glob]}` in its tenants-file entry, written by `tenant set … --confine LABEL=KEY[,KEY…]` (kept by a later set without the flag, dropped with
  the label). The row then owns, and `pick` runs it on, only those of the tenant's repos; elsewhere in the tenant
  pick skips it saying so, so the vendor fence refuses. Why: the owner tenant holds the vault and the guarded repos
  beside the scope another person's login was meant for, and tenancy alone would have given it all of them. It only
  narrows: a malformed value confines to nothing, a Claude row is refused (a seat's guard reads its tenant
  whole), and so is a key the tenant's `--repos` do not cover. A `confine` that is no object, or names a label that
  is none of the tenant's logins, confines every routing login of it to nothing, and doctor names it; one on a
  Claude row, or on a registry row, is never read. The vault's restore line carries the confine, a repeated
  `--confine` adds, `pick --ship` and `limits LABEL --repo` read it too.
- CI budget alarms (ci-budgets, 2026-10-31): after each row `ops sample` files one logbook issue, through helm's
  `ask` (`helm/logbook-repo`, led by `helm/mention`, label `budget`), per account each time it crosses its week share
  or into its month reserve, on ci-provider's own terms, and closes it when the account is back under
  and the alarm is a day old (a step up closes the issue it supersedes; a refused close is retried)
  (`ci-budget-alarms.json` in the log dir). The intake reads `budget` as an alarm kind (rung 4, no model). `ops.json`
  gains `pick_repos` and `pick_apply`: the 15-minute job picks those repos, applying only when `pick_apply` is true.
  `ci-budgets.json`'s top-level `reserve` now reaches `ops` as it reaches the pick.
- The budgets file (the owner, 2026-10-31: "put the budget caps in a regatta config that I can edit myself,
  quickly"): `lighthouse/budgets.json`, `{label: {week_max, window_max, free_below}}`, overrides those rules of a
  registry row, and a ceiling it sets reads `week ceiling, budgets.json`. Optional: absent, the registry's rules;
  torn, its last good copy, else the registry's; a value that is no finite number from 0 to 100, or an unknown key, is
  skipped with a stderr line. Drive-backed like the tenants file (`refresh` keeps `.budgets.json.last`), except that a
  hook never opens the link to seed a missing copy. Cases in `tests/account.sh`; G4 in the core's check.
- A tenant's logins may name a Codex row (the owner, 2026-10-30: the vault's tenant "should also allow my codex"):
  `account tenant set` takes any claude or codex label (the refusal reads "no claude or codex row"), so
  `pick --provider codex --repo` runs a tenant's repo on its own Codex login and skips the others with the
  tenant's line, each vendor's pick naming its own vendor's rows. A Codex label is the vendor fence's yes for the
  tenant's confidential and guarded repos, and every Codex road runs on `CODEX_HOME` (or the default Codex home), so `tenant set`
  takes one only while its home is that one. Routing only: the guard, `allowed`, `run`,
  VS Code profiles and every line telling a Claude session where to go still read the Claude rows alone, `tenant set` refuses Codex labels alone, and doctor
  says when a tenant has a Codex login and no Claude one (its Claude sessions have nowhere to start). Cases in `tests/account.sh`.
- Free below (the owner, 2026-10-30: "if the window is under 70% then the pace rule doesn't apply. Under 70% we can run anything."): a 5-hour spend under a row's `rules.free_below`
  runs whatever `window_max`, the margin after an exhaustion or the pace say; those judge only from 70% up, and the
  week ceiling as before. Off by default (0); the owner's registry is to set 70 per row (the overlay's own free-below change; until it lands, off everywhere). The reason reads `5h 60% under 70% (runs whatever the pace)`. 6 cases in `tests/account.sh`.
- Pace (2026-10-30, the owner: "if the spend is lower than pace and we still have 5-10% to go, we should just
  launch"): `account`'s judge lets a row over its flat 5-hour limit run while its 5-hour spend is under the window's
  elapsed share, `100 * (1 - (reset - now) / 5 h)`, with `rules.pace_headroom` points left (default 10). The reason
  names it (`5h 55% under pace 92% (10 points headroom)`), so `pick`, `limits`, tier_check and dispatch's queue lines
  say why a row passed; a refusal names the pace it is over, or the headroom it lacks. No reset inside the window's
  future, the flat limit alone. The week ceiling, a cooldown, paid overage and the deny list judge as before. A Codex
  reading keeps its window's own length (`five_hour_window_s`) for the pace (an Orca report row's is shown, never judged). Every other reader of a 5-hour
  verdict takes this one, so none changed. 17 cases in `tests/account.sh`; the two margin cases moved off pace.
- Pace is read at the reading's sample time, not now (landing review, 2026-10-30): a failed probe's stale
  reading, which `pick` falls back to, stayed refused only until the clock lifted its pace. And a `free_below` or
  `pace_headroom` that is no number reads as its default, with one stderr line, rather than a TypeError in every
  pick. Pace prints at most 99%, so a window not yet over never reads "pace 100%". 6 cases.
- secrets_guard's fence covers a confidential scope's scratch folders (guard-scratch, 2026-10-29): Claude Code's
  `<tmp>/claude-<uid>/<slug>/` for each of the scope's trees and each removed worktree's
  (`<slug>--claude-worktrees-<topic>`), as the core's `scope_match` fences them for usage-report since
  trim-cross-host. A sibling slug (`<slug>-site`) and an open repo's own scratch stay open; a torn registry
  still fails open. A scratch cwd never makes a session the scope's own (inside is judged on the scope's paths),
  and a walker over the temp folder is refused while a confidential scratch folder exists. The root is Claude Code's: `CLAUDE_CODE_TMPDIR`, else `/tmp`; `SECRETS_GUARD_SCRATCH_ROOT` points the suite at a stand-in.
- The desk's jobs find `claude` (2026-10-29): `install.sh --schedule` ends both plists' PATH with the home
  folder's `.local/bin`, the native installer's home for `claude`, as helm's and hookwatch's do; and `ops classify`'s gate
  probe holds the queue, no try spent, when a row's provider command (`$CLAUDE_BIN`, else `claude`) is not on the
  job's PATH, naming the command and the PATH (the home as `~`), or when a row has no classify adapter in the gate (a
  `codex` row); the Linux face's printed units carry the same PATH. The desk's first pass had spent a try on each issue.
- Every CLI, one rule set (vendor-hooks, the owner's D2-A, 2026-10-29): `hooks/vendor_hook.py` runs a Claude
  PreToolUse guard unchanged inside Codex's and Antigravity's own hooks — Codex's `Bash` and `apply_patch` (each
  file of a patch judged), Antigravity's `run_command` and file tools, under both the names its docs give and the
  ones it sends — and answers in each CLI's shape; a `git commit` there gains `Co-Authored-By: <CLI> <model>`.
  `bin/vendor-hooks apply|check|homes` writes the entries for `secrets_guard` and wharf's checkpoint, and a rules
  pointer naming the files a Claude session loads, into every Codex home the registry names and Antigravity's,
  in place beside Orca's and sessionpipe's (Codex keys its review by position); `install.sh --vendor` runs it,
  `--check` reports it. `secrets_guard` closes Codex's `auth.json` and Antigravity's `oauth_creds.json` to every
  session, Claude's included. `tests/parity.sh`: each rule, a deny and an allow case, on all three CLIs.
  The landing review's fixes (2026-10-30): a Codex argv `[<sh>, -lc, <script>]` is judged as its script; the
  trailer rewrites only one simple `git commit` that both guards pass (Codex's rewrite needs an allow; agy's
  `overwrite` goes without a `decision`); agy's other readers and shell input (`view_code_item`,
  `read_url_content` for a `file:` URL, `codebase_search`, `send_command_input`, `write_stdin`, …) are judged; one
  25 s budget per call. The logins wall takes globs and agy's keychain fallback files
  (`jetski-standalone-oauth-token`, `mcp_oauth_tokens.json`, `plugin-secrets.json`), and each CLI's hooks and trust
  files are closed to a file tool. The pointer is the tenant's: its Claude seat's `rules/` and only the `@` files
  every seat loads (or `lighthouse/vendor-layer`), never the CLAUDE.md; a foreign AGENTS.md is never written,
  a group of ours is never dropped (Codex's review indexes), and an entry whose adapter moved fails open with one line.
  The finish review's (2026-10-31): the trailer's allow needs a clean pass from each guard (one out of time,
  absent, exiting abnormally or reporting its own crash is no pass, so no rewrite); its one-simple-commit test
  reads quotes in context (an apostrophe inside double quotes had let an operator ride along) and refuses
  ANSI-C `$'…'` quoting and any `${…}`; a commit with `--no-verify` (abbreviated too), `-n`, a `core.hooksPath`
  or any `-c` but the author's name and address gets no trailer; agy's `CodeEdit` is text; and the entry runs `python3 -I`, so a repo's own `json.py` never loads inside the hook.
- An adapter from before the one entry (no `ENTRIES` line in `vendor_hook.py`) read `guards` as a guard path and
  allowed every call: `vendor-hooks apply` refuses one and `check` reports it (vendor-hooks-names' finish review).
- One named entry per CLI (vendor-hooks-names, 2026-10-31; the owner read three indistinguishable PreToolUse
  entries in Codex's /hooks as a bug): `vendor_hook.py <cli> guards` runs `secrets_guard` and wharf's checkpoint at
  once (the first deny in that order the answer: one after another, a slow secrets_guard starved checkpoint, the finish
  review), then the trailer, under one 25 s deadline, so each Codex home and agy's `regatta` key
  hold one handler: one approval in Codex, one launcher start per tool call instead of three. Codex's carries
  `statusMessage` `regatta guards: secrets, checkpoint, trailer`, the name its /hooks lists (a handler without one
  reads "Unnamed hook"; probed live on codex-cli 0.166.0); agy has no such field, its key names it. `apply` merges
  the older one-per-guard shape into the first of its groups, never touching another tool's, and drops the emptied
  groups at the end; `check` calls that shape stale. Each Mac's owner trusts the one entry once in Codex's /hooks.
  The one-guard and `trailer` forms stay for a home not yet re-applied. Cases in `tests/parity.sh`, one on a copy
  of the older shape (`tests/fixtures/codex-hooks-2026-10-31.json`); the parity table runs through the one entry.

- The desk's sense, logged (lighthouse-ops S5, 2026-10-28): `ops classify` takes each new open issue the intake
  holds through four rows of the core's gate (`lighthouse.importance`, `.urgency`, `.cost`, `.clarity`; Sonnet in
  the shipped table), derives the ladder's rung from the labels and the issue's kind and author, judges every cap
  of `lighthouse/ops.json` before a lay (runs a day and a repo a day, open `ops:auto` PRs, the desk's share of
  the week against S2's token weeks, importance, cost, labels, repos, the place, the held-class scan), and
  appends one verdict row to `ops-verdicts.jsonl` — labels and metadata, never a title, a body or an address.
  Nothing is laid, commented, labelled or seeded: S6's `ops send` does that. A contact, a stall or an alarm is
  rung 4 by kind and never reaches a model; a confidential repo is classified only on its yard; a gate row that
  fails writes its reason and the pass goes on, the issue retried next pass. No `ops.json`, the desk is off. It
  runs in the 10-minute intake job after `ingest`. `ops digest [--days 7]` counts the logged week by rung, kind
  and would, the caps' refusals, rung-1 candidates on published paths (D4's fact) and the gate's spend.
- The intake, from S4's landing review (S5): `ingest` also reads `helm/logbook-repo` and beacon's `sink.repo`
  (an unlabelled issue there a contact), keyed by slug; `lighthouse/ops-bots` names the Apps that file for the
  issue road (author `bot`, not `stranger`); each repo's open set is re-read once a day, dropping a gone
  issue's card (`event: dropped`); the first cursor is the newest `updated_at` read, not this host's clock;
  and a pass that reads no repo at all exits 5.
- From S5's landing review: the first cursor is the newest update of any issue (one unpaginated page, read
  before the open set), so a second pass never replays a repo's history; every issue in beacon's sink is a
  contact whatever its labels, and the sink keeps that kind when the logbook or the registry names its slug; a
  gate that cannot resolve its four rows holds the queue and spends no try (exit 3); an issue GitHub answers
  from another repo (a transfer) is never sent; an issue closed at its fetch is not marked done, so reopened
  unchanged it is classified; every fetch counts against `CLASSIFY_MAX`; a named path loses a sentence's
  closing punctuation; an autofinish that exits at import is "unread", not the pass's end.

- account.sh deletes under HOME through `rm_own` (the core's lint, 2026-10-27).
- The desk's intake (lighthouse-ops S4, 2026-10-27): `ops ingest` reads every fleet repo in the registry (its
  `github`) for issues and comments since that repo's cursor, with the machine account's `gh`, and each Project
  `lighthouse/ops-projects` names with the desk's token, into the log dir's `intake.jsonl`: one row an event —
  repo, number, event, kind (deadman, stall, contact, bug, other, by label), label, state, created, seen, the
  author's kind (self, member, stranger), the body's hash and the scope; never a body, a title or an email. A
  first pass cards what is open and never reads the history; an unchanged repo writes nothing; a read that
  fails writes its reason once and the pass goes on. A confidential scope is read only on its own yard
  (`skipped: fenced` elsewhere), and a torn registry ingests nothing (exit 3). `intake-state.json` holds the
  cursors and the open set, which `ops intake [--json]` lists for helm's board, re-judged against the registry
  as it reads. Only in the desk's job on the ops host; `install.sh --schedule` loads it every 10 minutes beside
  the sampler, and on Linux prints its unit's lines.
- The desk's sampler (lighthouse-ops S2, 2026-10-27): `ops sample` appends one row to the log dir's
  `ops.jsonl` — the dispatch queue, the run slots, the 5-minute load per core, headroom's memory, the
  check slots, the CI budgets from S1's usage read (and `ci-usage.json` with it), the token's standing as
  `token.plan` and `token.project` (`ok`, `refused`, `absent`; a GraphQL read of the viewer's Projects,
  never a write), the token weeks and the week's cost — each read bounded, side by side, a failed one its
  field's null and why. Only in the desk's own job on `lighthouse/ops-host`; `--print` reads no token and
  writes nothing. `ops status` prints the last row, `--json` with its board line and its clock-free sig;
  `ops is-host` answers the host rule. `install.sh --schedule` loads the 15-minute LaunchAgent on the ops
  host alone, refusing any other, and on Linux prints the systemd unit's lines for yard-node S5.
- Tenancy that cannot be read fails closed (confidential-reach S7b, 2026-10-27): a tenants key that reads
  nothing with no last good copy (a new Mac, a drive away before its first read) refuses every repo to every
  row, the default dir's included, where it used to turn tenancy off and let the work seats into the vault
  once their deny lists went. Each refusal, stderr, `refresh` and `account doctor` say "closed" and name the
  read that opens it; only `{}` or no key at all turns tenancy off. `account setup` seeds the copy first.
  `account_guard` reads it the same way (every repo asked about), and asks `allowed` for a default-dir start in
  the home or the projects folder while the default dir is refused the vault, which its prefilter never did.
  `tenant drop` of the vault's tenant warns; doctor names a repo two tenants' entries both take (`tenant set`
  refuses two globs that take one cloned repo), the default dir outside the vault's tenant, and a dir signed in
  to a seat whose tenancy refusals it lacks, where only a deny list counted. While closed, no write outlives the
  state: claudeMdExcludes and trust's external-imports No wait until tenancy reads. `tenant set` that leaves the
  vault out warns as `drop` does, and a key inside another's folder counts as both tenants'.
- `ops usage` and `ops pick` (lighthouse-ops S1): CI minutes and credits per budgeted account from GitHub's
  billing usage endpoint and CircleCI's insights, with the owner's token read from `lighthouse/secrets/ops.env`
  (0700, 0600, no link) in the desk's own job only; `pick` runs wharf's `ci-provider --pick` per repo.
- `secrets_guard` closes the folders `lighthouse/guarded-dirs` lists, Drive mounted or not (the desk's token dir).
- `account limits --orca` runs `orca open` when Orca's newest agent reading is over an hour old
  (`orca_wake`): Orca reads limits only while its window is focused and keeps the last after it closes,
  so the widget's Antigravity card went 5 days stale. Once an hour at most (Orca takes focus), never
  under `CLAUDE_UNATTENDED`, waiting 30 s at most. An answer with no agent's reading keeps every last
  reading, where one agent left `unavailable` used to wipe the rest (2026-10-26).
- health: a free-disk line — under 50 GB free on the data volume fails and is posted once, naming the
  three biggest folders one `du -x` pass finds (Chrome's APFS clone folders left out);
  under 100 GB warns in the log. Read-only; `df` gives the free space (2026-10-25).
- The vault as a tenant (confidential-reach S7, 2026-10-26): `account tenant set NAME --repos … --logins …`
  and `tenant drop NAME`, the tenants file's one writer — through the link, read back, the hooks' copy
  refreshed; refused unattended (exit 2), and refusing a login another tenant has, a repo another tenant
  holds, an unknown label, or a file that does not read. `holds_denied` binds the vault's tenant
  (`lighthouse/vault`): a folder holding its repos is off every row but the tenant's, the default dir's and a
  dir no row names included; a row refused the vault by tenancy is an employer's (`employer()`). `account
  doctor` reports each tenant, a deny-list entry a tenant already refuses (G3), and a vault refused no
  login. `tenant_ties` counts the default profile as the default dir's login. `account_guard`'s prefilter
  leaves out the default dir's own tenant, so its prompts in the vault's repos start no subprocess. An
  unsynced Orca login's holds refusal is a ' holds ' line, so a `cd` into the projects folder is not refused.
- deadman: `inbox_repo` defaults to the config dir's `helm/logbook-repo`, helm's renamed stall-road key;
  the old `helm/inbox-repo` is not read (2026-10-25).
- `account setup` writes the first-start keys into every login dir this Mac carries, Orca's and the
  default one included, and `account add` into a new one (orca-launcher S2, docs/orca-launcher-2026-10-24.md):
  `hasCompletedOnboarding`, `lastOnboardingVersion` (the installed `claude --version`), `numStartups`,
  `claudeInChromeDefaultEnabled` as the Chrome offer's own default (No; `/chrome` turns it on), and on each
  trusted project the external-imports dialog answered No ahead. Without them an interactive
  start waits at the theme picker though the login is good, which `-p` and `auth status` never show
  (a login dir on the always-on Mac, 2026-10-24). Only an absent key (or a not-yet-done false) is written; a Yes, or Approved in either form, is kept; a file that does
  not parse is left as it was; a Claude Code save that takes the keys is met by one read-back and one
  rewrite, as trust-projects does. `account check` fails a dir lacking any of them, naming each.
- beacon: `round_icon` — a config whose icon is a round badge of its own gets it filling the round pill
  (40px, a 4px rim) and larger and bare in the window's header (38px). `/chat` answers `offer: true` on a
  reply holding the hand-off sentence where the sink relays, and the widget puts a "Talk to a person"
  button under it; the footer's link stays (2026-10-24).
- Drive-backed reads local (orca-launcher S4, 2026-10-25): outside claude-host `allowed`, `limits` and every
  load_registry read the tenants file's local copy first, `allowed` the logins file's (`.logins.json.last`,
  new), and the link only with no copy yet; account_guard and design_route read the copies first. `account
  refresh` re-reads both links (exit 3 outside claude-host unless `--force`). `doctor` names a missing copy, and one
  that differs from its file 30 min after the last refresh: the tick is not running it through claude-host.
  Only a link into a cloud drive is read local-first: a plain tenants file reads as it is, so `{}` still ends
  tenancy at once on a host without claude-host; `refresh --force` refuses an unattended caller.
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
- `account pick --repo` and `limits --repo` take a registry key as well as a path, and refuse an argument that is
  neither (exit 3; `pick --json` prints JSON alone): a bare key was read as a path in the cwd, matched no deny
  list and picked as if none applied (found 2026-10-24).
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
- health: a start-path canary line (orca-launcher S7, docs/orca-launcher-2026-10-24.md): `clock canary check
  --json` on this Mac, and a failing beat is posted like a failing check, under its own state file, naming
  the beats without their minutes (`HEALTH_CANARY`, `HEALTH_CANARY_CMD`). A Mac without wharf-runs' clock skips
  in one line; an exit that is not the failing verdict, or output that is not findings (exit 0 included), posts
  "could not tell". Under the studio brake (`~/.studio-brake`) it is not read: no beat fires while Orca is frozen.
  The privacy line names a refusal charged to Orca for a job it started (`rc-hosts --tcc-survey` counts them).

## 0.1.0 — 2026-10-19

- First cut, moved in from the overlay: `bin/health`, `claude-settings`, `account` with
  `shell/cc.zsh`, `publish`, `trust-projects`, `tiling`; the hooks `account_guard.py`,
  `secrets_guard.py`, `design_route.py`, `tool_path.py`; their suites. Every private value
  (registry, declared settings, shares, vaults, hosts) comes through the config dir's
  `lighthouse/` keys (README, "Private values"); a missing peer (wharf, atlas, plumb) is a
  printed fallback, never a stack trace.
