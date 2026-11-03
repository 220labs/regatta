# Regatta

[Regatta](https://github.com/220labs/regatta) is a business-as-code framework. With its `regatta`
CLI installed, this extension shows:

- the **Board**: helm's board, what waits on whom, in the order you act on it;
- **Meetings**, where the navigator is installed.

It looks for `regatta` on your `PATH`, else the clone `$REGATTA_HOME` or the regatta config dir's
`home` file names; the `regatta.cli` setting points elsewhere.

With [Sheepfold](https://github.com/220labs/sheepfold) installed too, a board row about a session
takes that session's title and mark and goes to it, and Sheepfold's session rows say what helm
knows of them (stalled, a skipper).
