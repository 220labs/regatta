---
name: new-project
description: "Provision a new project — or adopt an existing folder — onto the shared workflow: git, the AGENTS.md + CLAUDE.md shim with a session contract, TODO.md, .gitignore, the checkpoint opt-in, its GitHub twin, then on both Macs a clone, workspace trust and a Remote Control host, and auto-memory in the vault. Verification command first."
disable-model-invocation: true
argument-hint: <path> [--adopt]
---

Provision a project: $ARGUMENTS

Template: regatta's `modules/wharf/templates/code/` (since B5; `regatta has wharf` prints the module's path). Every project gets the same thin start; what
makes it *this* project is written by hand afterwards, starting with its `check` command —
the thing that lets a session prove its work (DESIGN F8).

**Where the tools are.** A bare tool name in a command below (`github-repo`, `repos`,
`knowledge-commit`, `autofinish`) is a path: where the regatta config dir holds a `legacy`
file (an overlay is installed), `<its first line>/bin/<name>` — the shims the overlay's allow
rules name — else the module's file, which `regatta which <name>` prints (`regatta` is the
core's `bin/regatta`, on PATH in a plugin install).

## 0. Where this runs, and on what

Run from a session opened in the target folder or in `~/projects` — or from any session the
target is an additional working directory of; what matters is the path, not the window. If
this session is isolated in another repo's worktree, Claude Code will refuse the git commands
below — stop and say so rather than working around it.

**Resolve the argument to an absolute path and print it before anything else**, then look for
the marker:

```bash
P=$(cd "<path>" 2>/dev/null && pwd -P) && echo "$P" && ls "$P/.claude/no-workflow" 2>/dev/null
```

A `.claude/no-workflow` there means the repo must never join the workflow: **stop**, quote its
first line, and name the project that was probably meant instead. `.` resolves to whichever
session happens to be open, which is how the knowledge layer was adopted by accident on
2026-09-17 when the target was another project (DESIGN.md D17). The layer joins the
workflow by decision (D9, 2026-09-25) in its own commit — never through this skill; so did
the vault (2026-09-29, docs/record/personal-on-workflow-2026-09-29.md), with its records in place.
No repo carries the marker now; the rule stays for one that wants it. The checkpoint hook
denies the write too, but this skill should never get that far.

## 1. Look before writing

- New path: create it.
- Existing folder (`--adopt`, or the path exists): list what is there. **Never overwrite.**
  An existing `CLAUDE.md` with no `AGENTS.md` → propose moving its tool-neutral content into
  `AGENTS.md` and leaving the shim, and show the split before doing it. An existing
  `.gitignore` → append the template's missing lines only. An existing `TODO.md` → keep.
- Already a git repo: note its default branch; the opt-in's `"main"` must match it.

## 2. Ask what only the owner knows — one question

With `AskUserQuestion`: the one-line purpose, and the `check` command if one exists (tests,
build, lint, a script). "None yet" is allowed; it becomes TODO #1.

## 3. Lay down the files

Copy from the template, replacing `{{PROJECT}}`, `{{ONE_PARAGRAPH}}`, `{{COMMAND}}` with
what the owner said; anything unknown stays as a visible `{{…}}` for the first real session.
`AGENTS.md`, `CLAUDE.md`, `TODO.md`, `.gitignore`, `.claude/settings.json`, and the whole
`.github/` — CI and automerge (`docs/ci-automerge-rollout-2026-10-06.md` in the layer). The
`{{COMMAND}}` in `.github/workflows/check.yml` is the same `check:`; left unfilled, the job
fails on purpose, so once step 4's protection requires it nothing automerges unproved. A check that reads a macOS tool changes
`runs-on`, and then `main-protection.json`'s context, to what `gh pr checks` reports.

Then add this line as the last item of `AGENTS.md`'s session contract, below `open-items:`
(an adopted repo keeps the rest of its contract as it is):

```markdown
- autofinish: all — a branch launches by itself through `/finish`, every gate run, by the start
  rules in `bin/autofinish`'s header (wharf-runs; A records, B small, E any text diff, L a
  deployed branch at once, D a design doc that stood); never a binary, and never a branch
  touching this repo's `in_place` or `autofinish_exclude`, which launches by `/finish` or
  `/autofinish`. `autofinish --dry-run <repo>` says what would start
  today. Why: `docs/autofinish-everything-2026-10-11.md` in the knowledge layer.
```

It matches the keys step 4 writes. A new repo with a real check starts at `"all"` (the owner,
2026-10-11: "autofinish everything"; since 2026-10-14 for new repos), with `docs/` and `TODO.md`
as its records. **Without one** — step 2's "None yet", `{{COMMAND}}` still in the contract — it
starts at `"records"`, and the line above reads `- autofinish: records until the check exists
(TODO #1), then all — …`: nothing would check a code branch, and on the laptop `bin/pr merge`
runs with the owner's admin token, which passes the required CI check by (the owner, 2026-10-14: "secure it
through tests on CI" holds only where there are tests). TODO #1 raises it to `"all"`; a repo narrows it with `"records"` or `"small"`, or adds `autofinish_exclude` for files
a branch must never change unwatched (autofinish-everything-2026-10-11, D1-A). The exclude
starts with `.claude/workflow.json` itself, so no unwatched branch can widen the next one's
rules (`GATES` holds it for the layer, the vault lists it). The line points at
the rules instead of restating them: a copy in every repo's `AGENTS.md` goes stale with the
next rule (rule L launched the day this default did). A shared repo starts at `"all"` too: the safety
is its CI, not a slower launch (the owner's D2-B there, on the first shared repo).

## 4. Git, opt-in and first commit — in ONE command, opt-in last

A repo other people work in (a collaborator who does not run this workflow) keeps the opt-in
out of it: the same keys go into its registry entry (`repos.json`) as `"workflow": {…}` instead
of the `printf` below — through `knowledge-commit layer`, reviewed
(an entry carrying `workflow` is never the unreviewed add-only case) — and `hooks/sync.py`
writes them into each clone, untracked, at the first session start after it launches
(the first shared repo, 2026-10-05). The rest of this step stays, minus the opt-in.

The checkpoint hook denies writes on `main` from the moment `.claude/workflow.json` exists,
so the file is created inside the same Bash call that commits:

`AF` is `all`, or `records` when step 2 gave no check (step 3):

```bash
AF=all
cd <path> && { [ -d .git ] || git init -q -b main; } \
  && printf '{\n  "checkpoint": true,\n  "main": "main",\n  "autofinish": "%s",\n  "records": ["docs/", "TODO.md"],\n  "autofinish_exclude": [".claude/workflow.json"]\n}\n' "$AF" > .claude/workflow.json \
  && git add -A && git commit -q -m "Project: provisioned from wharf's templates/code" \
  && git log --oneline -1
```

(Adopting a repo whose default branch isn't `main`: put its name in `"main"`.)

Then give it its GitHub twin — every new repo gets one (the owner, 2026-09-26):

```bash
github-repo <path>
```

It creates the private `<owner>/<name>` repo (the registry's own repo's owner) (rebase merge only, head deleted on merge), pushes
`main`, installs the pre-push guard, invites the other Macs' machine account (`repos.json`'s
`machine_account`) with push, and registers the repo in the registry's `repos.json` through a
pull request. An adopted repo whose origin is already that owner's gets only the invitation and
the registration. On a Mac whose token is the machine account it stops: the machine account would create the repo under the
wrong owner, so it prints the line to run on the laptop — put that line in the report.
An employer's project passes `--owner <org>` (2026-10-18): the repo is made
in that org, laptop-only, the machine account uninvited, and its registration is reviewed.

Then bring **both Macs** up to the registry — every project gets the same settings on each
(the owner, 2026-10-07): each other Mac accepts the invitation, each Mac clones the repo, trusts it in
every Claude Code login, and runs a Remote Control host for it (`<name> · <host>` on each;
`"rc": false` in its `repos.json` entry opts out). This Mac first, then each other one `wharf/hosts`
names, over the ssh alias `wharf-runs/ssh` gives it:

```bash
repos --clone
ssh <alias> 'git -C <its layer checkout> pull -q --ff-only && <its repos> --clone'
```

The first line runs once `github-repo` has said `registered`; the other Mac's pull brings that line
over. Read each output for the new repo: `cloned` (the other Mac), `trust … trusted`, and
`missing <name> · … → writing and loading` then `running`. A clone that says "Repository not
found" means the invitation was not accepted — `bin/repos --github` on the laptop says which
side is missing.

`github-repo` also sets the GitHub settings automerge needs, once `main` with the workflows is
pushed: the `hold` label (automerge's only brake — `gh pr edit --add-label hold` fails on a repo
without it), `main` protected with `.github/main-protection.json`'s required `check`, and
`.github/repo-settings.json` (`allow_auto_merge`), in that order — the label created (201),
protection and settings read back, and `allow_auto_merge` only once protection holds. Its
`ci settings set: …` line goes in the report, and a `⚠` line names what GitHub refused or what
it would not apply (a `main-protection.json` context no job in `check.yml` has, say).
They are the owner's (the machine account is no admin), which is why github-repo stops
there. On a machine-account Mac, `git rm` `.github/workflows/automerge.yml` before step 4's commit anyway:
an automerge with no required check merges a ready PR at once, unchecked (gh's
`isImmediatelyMergeable`), and the laptop adds it back once the settings are on.

The first pull request's `gh pr checks` must show a `check` context; if it reports another
name, put that name in `main-protection.json`, launch it, and run
`repos --github --apply` on the laptop. The same command sets an
adopted repo (one that already had an origin) once `.github/` is on its `main` through a pull
request; `repos --github` alone says what differs.

The hook denies this command outright in a repo carrying `.claude/no-workflow`. If that
happens, step 0 was skipped — don't work around it; stop and read the marker.

## 5. Memory into the vault

```bash
<the overlay>/bootstrap.sh adopt-memory <path>
```

Moves (or creates) the project's auto-memory directory into
the vault's `memory/<name>/` and links it back, so Aurora's dream sees it.

## 6. Report

What was created or kept, the `check` command (or that there is none — TODO #1), the two
Remote Control hosts (or the line that left one missing), and the next step: the first working session in this project creates its own worktree when it first
writes (the hook says how). If the project has a `.env`, that session links it into the
worktree.
