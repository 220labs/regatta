---
name: sounding
description: Sound an idea before anything is built — a change to one project, to how every project runs, or an idea outside any repo (a venture, a pitch, a tool to build or adopt) — through one architect-family agent picked by scope (`architect`, `sr-architect`, `sounder`). Sounded unless the request starts `firm:`; the doc carries a Landscape of what exists and a one-line Verdict, passes the lint and `reviewer-high`, and reaches the owner by one of three paths — full (the hand-over line), `--light` (a chat questionnaire) or `--yolo` (the reversible picks taken unattended). Use for "sound this out", "is this worth building", "propose …", a kept idea note or a ready proposal, and whenever the owner types /sounding (from a phone, `—light` and `—yolo` are the same flags).
argument-hint: "[firm:] <idea, brief or note path> [--light] [--yolo]"
---

Sound it: $ARGUMENTS

If this project has its own `/sounding` (`.claude/skills/sounding`), run that instead and stop here.

A sounding measures the depth before the ship commits: it writes **one doc** that tests the idea
against what already exists, and builds nothing. The doc is the record whichever path answers it.
The method is the agent's (the architects' shared body: the stance, the Landscape, the options on
fixed axes); this skill picks the agent, writes its brief, checks the doc and hands it over.

**Tools.** `keel` (keel module) and `sparks` (this module) are on the Bash PATH while their plugins
are enabled. Where this skill is linked in by hand, resolve this skill's base directory first
(`cd <base directory> && pwd -P`, since the link's own path leads elsewhere) and run
`../../bin/sparks` and `../../../keel/bin/keel` by absolute path, without leaving the session's
own directory. `keel`, `ask` (the helm module, for the unattended relay), `reviewer-high` and the
three heads are what this skill cannot run without: one that is not installed stops the run before
the spawn, saying which; nothing is substituted for it.

## 1. The head, by scope

| The idea changes … | Agent |
| --- | --- |
| one project: its code, its docs, its workflow | `architect` |
| how every project runs: sessions, repos, machines, models, tools, the workflow itself — or the owner calls it fundamental | `sr-architect` |
| nothing in a repo yet: a venture, a film or content pitch, a marketing project, a tool the owner might build or adopt | `sounder` |

Between two, take the narrower and put the wider question in the brief, for the doc to name. A
project's own agent of the same name wins (its `.claude/agents/`).

## 2. The stance

- The request starts `firm:` → the brief starts `firm:`: the idea is taken as given (probes and
  three options still), and the doc's Verdict reads `firm`.
- Anything else is **sounded**: the brief carries no `firm:`, however sure the request sounds.
  The agent names the idea as a hypothesis, steelmans the other side and writes `Verdict:
  validated | disproved | evolved` under `Status:`.
- Firm by shape, never sounded, and passed on as such: a worker's spec, an answered `➤ Answer:`,
  a `Taken in chat` answer, a `since:` line, the owner's own pushback on a recommendation.

## 3. The peers' two lines

Read the peers file — `$REGATTA_PEERS`, else `regatta/peers.json` in the regatta config dir
(`$REGATTA_CONFIG`, else `.config/regatta` in the home folder); an absent file or key is `auto`.
The brief carries exactly these two lines, one per peer:

```
Peer sparks: <on | off | auto> — <run `<absolute path to sparks> related "<the brief's nouns>"` | off: one line in the Landscape, nothing read | absent: one line in the Landscape>
Peer personal: <on | off | auto> — <one question, `semaphore ask "<q>" --why "<task>"` | off: one line | absent: one line>
```

Found means `sparks` (above) or `semaphore` resolves to a file. An `on` peer that is absent
stops the run before the spawn, naming the peer: the owner declared it, so a missing one is a
broken install, not a thinner Landscape. A repo an employer or another person shares reaches
neither peer: there both lines read `off: a shared repo`. Elsewhere a `personal` question names only
public or open-source work.

## 4. The brief, and the spawn

The brief holds, in this order: the stance (`firm:` or nothing); the idea quoted verbatim, with
where it came from (the chat line, the note's path, the proposal's path and its `## Launch test`
quoted); the kind (`proposal` unless the request names research or design); the one file to
write, as an absolute path; the path flag (full, light or yolo) and what it asks of the D-items;
the peers' two lines; any constraint the request names.

- **The file.** An idea in a repo: `docs/<slug>-<date>.md` in that repo's worktree on this
  session's `claude/*` branch (make the worktree first if the repo's workflow asks for one). An
  idea outside any repo: the knowledge vault, on a branch of its own — atlas's
  `knowledge-commit <vault> --open <slug>` prints where — outside its `ideas/` and `ventures/`
  folders, which are written in place on `main`, where an answer cannot be told from an agent's.
- **Under `--light`** the brief adds: at most four D-items, two to four options each, no
  conditional pick, and a `Reversible: no` item's options each naming its cost (money, a
  dependency, a deletion) — what the questionnaire can carry.
- **A proposal the strategy pass made ready** (Sextant's queue or *launch now*): the doc's D1 is
  `Build: full · light chain · yolo · no`, `Reversible: no`; a `disproved` Verdict parks the
  proposal instead.

Spawn the head with the brief, in the foreground: the next step reads its doc.

## 5. The checks, before the owner sees it

1. `keel lint --strict <doc>`. Fix what is mechanical yourself (a link, a heading word, a cap);
   a missing Landscape, under three linked candidates, or no `Verdict:` line goes back to the
   agent — the same one within about five minutes, else a fresh one with the doc and the
   finding. The lint does not check those three yet: read the doc for them yourself.
2. `reviewer-high`, model opus, on the doc. Apply its fixes yourself; a finding that changes a
   premise goes to a fresh head with the doc and the finding. Ask it, too, for one verdict on the
   light path: `light-ok`, `redesign` (back to the head, then these checks again) or `promote`
   (the full path).
3. Commit the doc on its branch (in the vault, atlas's `knowledge-commit … --in`); so too every
   answer a path below writes into it. A `disproved` doc is still handed over: it is the record of why.

## 6. The three paths

- **full** (the default): `keel line <doc>` and relay the line it prints; the owner answers on
  the doc's page or on GitHub, and `keel pull` takes the answers back as commits.
- **`--light`**, attended only: `keel light <doc> --check`. Nothing open (it says so): the full
  path. Passing, with `light-ok` from step 5:
  `keel light <doc> --plan --review light-ok`, make each `AskUserQuestion` call exactly as
  printed, then `keel light <doc> --write --why "<the owner: --light | session: check passed>"
  --review light-ok`, then `keel line <doc>` all the same (the record reaches the phone; it owes
  no form). The check runs unasked after every attended sounding, flag or not — say in chat when
  it went light; `--yolo` skips it. Refused: `keel light <doc> --check --record` writes why. A
  `promote` verdict, a decision a co-maintainer shares (they read it on GitHub), or `--write`
  exiting 3 (an answer missing): `--record` writes only its own refusals, so put the line
  `Gate: memo — light refused: <why>` where it would (the doc's Gate line, else under the
  `Written by` paragraph). Either way the full path follows.
- **`--yolo`**, only when the owner typed it, and over `--light` when both are: `keel yolo <doc>
  --dry-run`, then `keel yolo <doc>`. It is all or nothing: every open item `Reversible: yes`, it
  takes them all; else it stops at the first that is not (exit 3), writes nothing, and the whole
  list goes the full path — as a ready proposal's `Build:` D1 always does.

**Unattended** (a dispatched run, `CLAUDE_UNATTENDED` set): never the questionnaire — the check
refuses it (C4). The full path's hand-over is the run's relay (`ask relay <doc> <Dn>`), and the
run ends on the line it prints.

## 7. Go on

Once answered: apply the answers (a pick among the doc's options here; a changed premise to a
fresh head), then build by the doc's Action plan, one step per fresh session, through the
project's own finish. A `disproved` or `Build: no` doc ends here.
