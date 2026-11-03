# regatta for VS Code

Regatta's board in a VS Code sidebar: what waits on you, in the order you act on it.

- **Board**: helm's board. Sessions waiting on you, questions (one row per doc), pull requests to
  merge, work by hand and blocked work open; stalled runs, the lookout, the desk's intake, other people's, running,
  parked, ships and today's done closed. A click opens the page where a question is answered or a
  ship is followed.
- **Meetings**, where Regatta's navigator is installed: the meeting the navigator listens to and
  the next ones, with a status-bar nudge from five minutes before each.

Needs the `regatta` CLI ([Regatta](https://github.com/220labs/regatta)): `regatta` on `PATH`, the
clone `$REGATTA_HOME` names, or the one in the regatta config dir's `home` file; the `regatta.cli`
setting points elsewhere.

The board is read from the file helm's poll writes, whatever its age. `regatta helm board` reads
every repo's pull requests (over a minute), so the view asks it only on the refresh button, or,
while the view shows and there is no board file at all, at most every 30 minutes.

## With Sheepfold

[Sheepfold](https://github.com/220labs/sheepfold) lists coding-agent sessions. With both installed,
a board row about a session takes its title and mark from Sheepfold and goes to the session, and
Sheepfold's rows say what helm knows of them. Each finds the other at run time; neither needs the
other.

## Settings

| Setting | What it does |
| --- | --- |
| `regatta.cli` | the regatta CLI to run (empty: found as above) |
| `regatta.boardFile` | the board file helm's poll writes (empty: helm's default); `helm board` can write only one named `<dir>/overview/state.json` |
| `regatta.perSection` | rows a board section shows before its fold (5) |
| `regatta.nudges` | the meeting nudge in the status bar (on) |

A setting left unset here takes its value from Sheepfold 0.8.0's, which held these views
(`sheepfold.regatta.cli`, `sheepfold.regatta.boardFile`, `sheepfold.regatta.perSection`, `sheepfold.nudges`).

## Build

```bash
npm ci --ignore-scripts && npm run check
```

compiles, runs the unit tests (node:test, no VS Code needed) and packages `regatta-<version>.vsix`.
