---
name: pickup
description: Pick up work in progress from a vague description — finds the claude/* branch (local, or only on GitHub from the other machine) and the session that worked on it, then hands it back — reopens that session in VS Code or Terminal, or adopts the branch here when its session is on the other machine; when that session is large (100k tokens or more) it offers a fresh session with a context bundle instead, as a choice with a recommendation. Starts a seeded follow-up (`pickup seed`, a branch holding only a handoff brief) in a fresh session. Lists the candidates when the description fits more than one.
disable-model-invocation: true
effort: medium
allowed-tools: Bash(python3 *wharf-runs/*bin/pickup *)
---

Pick up work in progress — rule: git-workflow. The owner's description: $ARGUMENTS

The engine is `bin/pickup` in this skill's module: `../../bin/pickup` from this skill's base
directory. Below, `pickup` stands for `python3 <base directory>/../../bin/pickup`, passed as one
path, never through `cd`, so a skill linked in by hand still reaches its module.

The open branches in this repo, from `pickup list` (it fetched origin and
read GitHub's PRs, every session transcript on this machine and the live-session registry
before this reached you):

!`python3 "${CLAUDE_SKILL_DIR}/../../bin/pickup" list`

The script does the mechanics and the checks. The judgement is yours: which branch the owner
means, and whether handing it over is safe. `pickup show <branch>` prints one branch in full
(prompts, sessions, files, lock, the handoff it would make); `pickup --help` lists the rest.
Always quote the branch name you pass it.

## 1. Which branch

Match the description against every open candidate: topic, branch name, PR title, session
titles, "last asked" — by meaning, not by substring ("the dog camera" is `front-door-watch`).
Run `pickup show` on the close ones when prompts or files would settle it. A PR number or a
session id in the description is exact.

- **One clearly fits** → step 2. Name it in your first line: topic, PR, session title, when
  it was last touched.
- **Several fit, or no description** → ask with `AskUserQuestion`: the best four at most,
  the most recently active plausible one first and marked `(Recommended)`; label = topic,
  description = `PR #N · last here <when> · "<session title>"`. With more than four
  plausible, print the whole list first, numbered as above, so "Other: 6" works. Then stop.
- **None fits** → `pickup list --all` (the other repos in `repos.json`), the `not open`
  line (pickable by name; `open` refuses only a launched one), and the repo's `TODO.md` —
  `/evacuate` leaves unfinished work there. Still nothing: say so, show the list, stop.

## 2. Before handing it over

Stop and ask when one of these holds. Each costs a turn; each has cost more when missed:

- **Superseded.** `carried by <branch>` (another branch took its content — the work goes on
  there), `probably launched`, or the same topic launched under another branch (the `not open`
  line, or a newer branch with the same topic). An open `WIP:` PR is no proof the work is
  still wanted. Whether a branch launched is `hooks/branches.py`'s call, not yours: `launched`
  there is proof and `open` refuses it; `probably` is a hint to check.
- **Still alive on the other machine.** `show` and `open` read it over ssh (D6, 2026-09-25):
  `⚠ ALIVE on <peer>: session …` names the session and the line that ends it, `⚠ N
  uncommitted file(s) …` what is not on origin yet. Ask before handing over, and put the
  end-session line in a **Do this now** block — ending a session is the owner's act. Continuing it
  there (claude.ai/code, the phone) keeps one writer per branch; adopting it here as well has
  two machines pushing one branch, and they diverge. When `show` says `<peer> not read`, fall
  back to the old hints: a last commit under two hours old, or a matching `ListAgents` title.
- **Closed without merging**, or its upstream `gone` — confirm it is the work meant.

## 3. Hand it over

**When `$ARGUMENTS` ends in `--fresh`**, the branch is exact: skip sections 1 and 2 and run
`pickup open '<branch>' --fresh` straight away, with the
`--repo <path>`, `--session <id>` and `--note '<text>'` the arguments carry, if any (a tab in a
scope's window starts in its anchor, so its prefill names the repo), with a Bash timeout of 600000
(where dispatch takes the branch, it waits for the run to confirm its start). This is the tab or window a previous pickup
opened for a fresh start; asking again would loop.

`pickup open '<branch>'`, with the `--repo <path>` the arguments
carry, if any (a tab in a scope's window starts in its anchor, so its prefill names the repo; find
the branch with `pickup show '<branch>' --repo <path>` then too). Add `--note '<instruction>'` only
when the description carries an instruction beyond naming the work ("…and finish the
deploy"); the reopened session gets it after its summary. `--session <id>` picks an older
session when several worked on the branch. Report what it printed in two to four lines, every
✓ and ⚠ kept.

**Exit 3 = a choice.** The session is 100k tokens or more (D1, 2026-09-29;
`docs/record/pickup-cold-handoff-2026-09-29.md`): `open` changed nothing and printed a `context`
line and two `choice` lines. Put them to the owner as one `AskUserQuestion`: the recommended one
first, labelled `(Recommended)`, its reason as the description; the other with what it keeps
(`reopen — the whole conversation, at 181k per call`). Quote `open`'s numbers, never
recompute them. Then rerun the `choose:` line it printed (it keeps `--repo`, `--session` and
`--note`) with `--reopen` or `--fresh` as answered. `--vscode`, `--terminal` and
`--transcript` also count as the choice made — pass one only once the owner chose reopen.

It makes the branch resumable first: a worktree (from origin if that is the only copy, `.env`
linked), a fast-forward when the other machine pushed more, a stale lock released. Then one
handoff:

| handoff | what happened | the owner's part |
| --- | --- | --- |
| `vscode` | the original session opened in a VS Code tab of the window on that repo (never just the focused window; none identified for sure: a Terminal window, with the reason), its first message pre-filled (a transcript parked in a worktree is moved back first, as `ExitWorktree` would) | press Enter in that tab. An empty conversation there means VS Code could not find it: run `open` again with `--terminal` |
| `terminal` | the original session reopened in a new Terminal window, named `<repo>: <topic>` | switch to that window |
| `live` | nothing — the session is running now; `open` says where | switch to it |
| `carry` | the other machine's conversation copied here as a fork (paths rewritten, the original untouched) and opened in a VS Code tab, or a Terminal window from a terminal; its first message says which worktree to enter (D7: tried 2026-09-25 on the build Mac's server session, which continued with its context) | press Enter there |
| `new-tab` | a fresh VS Code tab pre-filled with `/pickup <branch>` in a window of that repo (no session for it here, and this one already has other work); where dispatch takes the repo and the branch has its brief, dispatch starts it instead (below). No window of the repo identified for sure: nothing starts, and the notes say `nothing started: type …` | press Enter there — or type the line the notes give in a window of that repo |
| `elsewhere` | nothing — the branch is another repo's and has no session here (with `--fresh`: `foreign-vscode` from VS Code, a Terminal window in that repo from a terminal) | open that repo's window, `/pickup` there |
| `foreign-vscode` | `--fresh` on another repo's branch from VS Code: that repo's own VS Code window (opened with `code` when none is) gets a new tab pre-filled with `/pickup '<branch>' --fresh`. With a named `--account`, or when no window id can be read for sure, a Terminal window in that repo instead | press Enter in the tab in that repo's window |
| seed | a branch `list` marks `seed — not started`: one `Seed:` commit holding `docs/handoff/<date>-<topic>.md`, made by `/todo handoff` for a session that did not exist yet. `--fresh` hands it over as for `fresh` | press Enter in the new tab, or nothing when adopted here |
| `fresh` (`--fresh`) | this session adopts it with the bundle when it has done nothing else; otherwise, where dispatch takes the repo and the branch carries its brief (a seed always does), `dispatch` starts a fresh session — on the dispatch host, the laptop when it does not answer (the owner, 2026-10-13); elsewhere a new VS Code tab (or Terminal window) pre-filled with `/pickup '<branch>' --fresh` does. `--new-tab`, `--vscode` or `--terminal` keep the tab or window. The old session stays where it was, resumable with `--reopen` | nothing here, or press Enter in the new tab |
| `here` | this session adopts it (its session is gone, or the other machine did not answer); `--here` forces it — `/finish <branch>` runs exactly that before finishing a branch another session left (D3) | nothing |

**`here`**, and a `fresh` adopted here (`→ here: fresh, as asked`): `EnterWorktree` with the path `open` printed (load it with `ToolSearch`
`select:EnterWorktree` if needed), read the context bundle it printed — on a seed, first read the brief
under `docs/handoff/` in full: it is the task, and its `Tier:` line answers the tier question
(ask only if this session runs on a different tier) — then carry out the
instruction if there was one; otherwise say in three lines where the work stands and what is
next, and wait for the owner's go. No `/rename` ask: the checkpoint hook names the session
`<repo>: <topic>` at its first Stop on the branch (A4). No closing line — this is the working
session now.

**Every other handoff**: this session's job is over. End with the one line below, in upper
case, as the very last thing said (`<OWNER>, ` is the owner's name from the core's `regatta/owner`
key, upper-cased, as the core's `ADDRESS` has it; with no owner configured the line starts at `THIS`), so the owner can tell a finished pickup from a working session:

`✅ <OWNER>, THIS WAS ONLY THE PICKUP — CLOSE THIS SESSION. THE WORK CONTINUES <IN THE NEW TAB | IN TERMINAL | IN ITS RUNNING SESSION | IN <REPO>'S WINDOW>.`

A fresh start ends with `… THE WORK CONTINUES IN THE NEW TAB.` (`→ new-tab`), `… IN <REPO>'S
WINDOW.` (`→ foreign-vscode`, when its notes do not say a Terminal window took over) or `… IN
TERMINAL.` (`→ window`: from a terminal, a plain shell, or when the notes say no window was found).

## Never

- Seed from here: a follow-up this pickup turns up is `/todo handoff`, in the session that
  works on it.
- Reopen a session that is running: two processes on one transcript interleave their writes.
  `open` refuses; do not route around it with `claude --resume`.
- `claude --resume` a session `open` stopped on (exit 3) to skip the choice: the choice is
  the owner's, reopen or fresh.
- Open a session of another repo with a `vscode://` link: it opens in this window's session
  list, where the id is unknown.
- Force, reset, rebase, push, or merge into `main` to make a branch resumable. `open` only
  fast-forwards; a divergence goes to the owner, and the checkpoint hook does the pushing.
- Pick up a launched branch (`already on main (…)`): its work is on `main`; new work starts a
  new branch.
