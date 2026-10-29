---
name: later
description: Schedule a seeded or work-in-progress claude/* branch to start by itself, unattended, on this Mac or the dispatch host — by default 10 minutes after the weekly limit resets, or at a time the owner names. Like /pickup, but the session starts later with nobody there. Use for "start this after the reset", "run it tonight on the build Mac", "queue this for Monday".
disable-model-invocation: true
effort: medium
allowed-tools: Bash(pickup:*), Bash(python3 *wharf-runs/*bin/pickup *), Bash(dispatch:*), Bash(*wharf-runs/*bin/dispatch *)
---

Schedule work to start later — the owner's description: $ARGUMENTS

The engine is `dispatch` (its header says what it does), and `pickup` lists the branches: on the
Bash PATH while the plugin is enabled, else `../../bin/dispatch` and `../../bin/pickup` from this
skill's base directory, passed as one path, never through `cd`. Below, `dispatch` and `pickup`
mean whichever of the two you have. `dispatch` writes a one-shot
launchd job that starts the run in a worktree of the branch and removes itself. It needs a
branch with a handoff brief (`docs/handoff/<YYYY-MM-DD>-<topic>.md`, what `/todo handoff` writes).
The run is a visible session (Remote Control, screen run-<repo>-<topic>; never headless — an
untrusted repo is trusted first): it builds, tests and commits; the checkpoint hook pushes; it never launches, and it is
ended once idle (at the latest after 8 h). The owner's `/finish` does the launch, or `/pickup` opens
the branch to read it.

## 1. Which branch, where, when

- **Branch:** as `/pickup` section 1 (skills/pickup/SKILL.md) — run `python3
  pickup list`, match by meaning, ask when several fit. A branch with no
  brief cannot be scheduled: say so and offer `/todo handoff` instead.
- **When:** `reset` unless the owner names a time. "after the reset", "when my tokens are back",
  nothing said → `--at reset --priority low` (the next weekly reset + 10 min; `reset+MIN` for another
  gap; a Fable seed `reset+60`, under Tier). Where the queue is on (`wharf-runs/queue-repo` set), at
  its time the one-shot enters dispatch's queue, aged from then (dispatch-queue S3): `low` lets a run
  the owner sent since go first, and an entry waiting past two hours ranks as `normal`. Without a
  queue home the one-shot runs at its time as before, and `low` is only its record's. A named time keeps `normal` unless the owner says so.
  A named time → `--at "YYYY-MM-DD HH:MM"` in the *target host's* local time; with `--on` the
  engine takes only `reset` or an epoch, so turn the clock time into `@EPOCH` first.
- **Where:** the dispatch host by default since 2026-10-13 (`wharf-runs/dispatch-host` in the
  regatta config dir, else the first host `wharf-runs/ssh` names) — dispatch adds `--on <it>
  --fallback here` when no host is named, and this Mac takes it only when that host does not
  answer; `--on HOST` names another host the ssh key lists, `--on here` when the owner says this
  Mac. A named clock time stays here (ambiguous across hosts): give `@EPOCH` for a peer. Say which
  you chose.
- **Never a repo with a live system** (one that drives a house: a repo whose contract says `live:`
  something). The run is unattended and its `python3`/`bash` are not fenced from `scripts/*.py`
  that act on the house; only a repo with `live: none` (git is the only state) can be scheduled.
  For the others, offer `/pickup` for when the owner is there.
- **Tier:** the brief's `Tier:` line, mapped by the owner's model-routing rules → `--model opus
  --effort high` is the default; Fable `--model fable --effort high`; Opus medium for copy.
  **A Fable seed defaults to `--at reset+60`**, Opus keeps `reset`: the 04:10 Fable seed of
  2026-10-04 got HTTP 429 "needs usage credits for Fable" ten minutes after the reset and ran
  on Opus (docs/record/aurora-sequence-2026-10-04.md E4, R4). Back to `reset` once a Fable run
  at +60 and one at +10 have both succeeded; if the +60 one 429s too, the cause is the Fable
  share, not timing — say so, and do not schedule Fable at the week's start.

## 2. Before scheduling

Stop and ask when one of these holds:

- The branch is **alive** somewhere (`pickup show` says ALIVE, or a worktree holds its lock):
  two writers diverge. Ask whether to schedule anyway.
- **The brief cannot be done yet.** If part of "done means" needs data that does not exist at
  that time (a benchmark week still running), schedule the part that can be done and pass the
  rest as `--note "Do only X; Y waits for <date>, leave it and say so"`. The run decides from
  the brief alone and does not ask.
- The week is very tight and the work is Fable-sized: say what it will cost against the new
  week, once, and let the owner choose.

## 3. Schedule it, then prove it

```
dispatch '<branch>' --at reset --priority low [--repo ~/projects/<repo>] [--on HOST|here] [--model opus --effort high] [--note '…']
```

`--repo` is required for a branch outside the default repo (the overlay's checkout where one is
installed, else this regatta clone; `pickup list` names the repo); it must sit under the projects
folder for `--on`. `reset` is read from this Mac's plan cache, so it is the reset of
the account signed in *here*: say in the closing line which account the job runs under on the
target host (a peer's launchd job uses that Mac's own login; the probe shows whether it works).
A time already past is refused; `--on` without `--at` starts it on that host in about two minutes.

`--on HOST` runs the peer's own regatta core (the checkout its config dir's `home` file names): if
the command says dispatch there is missing or predates a flag, `git -C <that checkout> pull
--ff-only` over `ssh <its alias>` (the alias: the host's line in `wharf-runs/ssh`; routine, yours
to run), then again. Read the job back, do not trust the exit code: `launchctl print
gui/$(id -u)/<the label dispatch printed>` (`<prefix>.dispatch.<repo>.<topic>.<YYYYmmddHHMM>`,
the prefix `wharf-runs/label-prefix`, else `org.regatta.claude`) on that host (over ssh for a
peer) shows the calendar interval.
The first run on a host gets a probe first: the same command with `--probe --at <two minutes
from now>` (it has its own label, `….probe.<minute>`, so it cannot cancel the real job). It takes
the visible path — Remote Control in its own screen, the prompt "reply with the single word ok",
ended by the watcher a minute after it answers. Read its log for `probe answered: ok`: that proves a
launchd-started `claude` is logged in and the interactive run works (`--probe --headless` tests
`claude -p` alone). Schedule the real job after the probe has fired.

End with one line: `Scheduled: <topic> on <host> for <local time> (<model> <effort>); log <path>`
(the log path as dispatch printed it, as a `file://` link). It starts without anyone. The outcome
is in the session's transcript — `dispatch --status` lists each run with its VS Code link and last
activity (a headless run's answer is in the log) — and in the branch's PR. `dispatch --end <topic>`
ends a run early. To cancel, you run it:
`dispatch '<branch>' --cancel [--repo …]` (from any other Mac it looks on the dispatch host too).
