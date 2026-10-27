# builders/ — which model and effort builds a specced task

A builder bench: an arm (one model at one effort) rebuilds a task that already landed, from the
brief its build session was given, in a clone that cannot see the landed answer; the tests the
landed diff added grade it. `bench` is the whole harness, stdlib Python 3.9; its header is the
method.

    bench prepare TASK --work DIR          # bundle the seed, read the hidden tests, grade seed and tip
    bench run TASK --arm sonnet:high --rep 1 --work DIR --out results.jsonl
    bench drive plan.json --work DIR --out results.jsonl --self <the caller's session id>
    bench ledger results.jsonl --self <id>
    bench table results.jsonl --ratio <effective ÷ list>

- **One run is one verb.** `run` takes a task and an arm and appends one JSON line; `drive` and any
  continuous bench call it. The row: hidden cases passed of the hidden total (all, some, none),
  suite green or the stable cases lost, list cost from the transcripts, wall time, the build's
  diff lines in `modules/`, how the run ended, and the isolation hits (`void` when one could reach
  the landed answer).
- **A task is a JSON file** naming the source checkout, the seed commit (the brief's), the landed
  tip, the branch, the brief, the hidden test files and the grade scripts. Tasks name real
  branches, so they live with the results in the private repo, never here.
- **Grading goes through wharf-runs' `check`**, under its slots: the grade tree's check line is the
  grade scripts alone. A case is a suite's `  ok   <label>` line.
- **The budget.** Each run gets `--max-budget-usd` and is ended from its transcript past it too.
  `drive` starts nothing once the ledger (every row, every live run, the `--self` sessions) passes
  `--stop`, nor a run whose budget could take the ledger past `--ceiling`; a ledger it cannot
  read stops it.
- **The stops outside the ledger.** A session's cap ends the session, not the driver it started:
  one ran 15 h past its session, on a login past its week ceiling. So before each start `drive`
  also stops once the Claude Code session that started it is gone (its claude process, read from
  `CLAUDE_PID` or the walk up `ps` at start), once `--until <epoch|ISO>` has passed, or once the
  login its runs spend (the config dir's, matched by home in lighthouse's `account limits --all
  --parked --json --cached`) is parked, locked, past its week ceiling or otherwise not eligible
  (paid overage on, a `same_as` twin; the 5-hour window alone is no stop). A cached reading over
  2 h old, or one without window figures, counts as could-not-tell. An idle but open session
  counts as alive: an attended start that may outlast its window takes `--until`. Each writes one `STOP:`
  line naming why and exits 0; an in-flight run finishes and writes its row. Run by hand from a
  shell with neither a session nor `--until`, the session stop is off, as before. An account tool
  that cannot answer is logged once, and the ledger's `--stop` still decides.

What it does not measure: review findings (no model grades the build), and anything a hidden test
does not reach. A verdict inside the spread of an arm's own repeats is "no measured difference".
