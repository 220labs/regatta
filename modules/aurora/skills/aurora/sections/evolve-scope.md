# Evolve, one scope — the per-scope pass (`/aurora evolve --scope <scope>`, aliased by `dream --scope`)

One scope of the registry at one explicit cycle id and evidence cutoff (`docs/self-improvement-scope-pass-2026-10-30.md`),
run from `<anchor>` on the scope's login and yard in three ordered operations: **reconcile** last cycle's
routed items and due benefit checks, **inspect** the window's delta through the fourteen lenses of
`<module>/lenses.json` with one rotating deep lens, and **propose** at most five validated findings after a
blinded critic checks the cold artefact. `<regatta>`, `<module>`, `<vault>`, `<layer>` and `<owner>`:
the aurora skill's "Where things are". `--days N` widens the window (default 7).

## 0. Where and open — stop if not ready or earned quiet

```bash
<module>/bin/scope-pass where <scope>
<module>/bin/evolve where <scope>
```

Each prints `<name> <value>` lines (`<anchor>`, `<staging>`, `<profile>`, `<deep-lens>`, `<outside>`,
`<dream>`, `<draft>`, `<inbox>`, `<section>`, `<words>`, `<memory>`, `<members>`, `<records-branch>`).
On `ready no — <why>` from either, stop, say the why in one line, and write nothing. Never post to the
bulletin from this pass: `weekly-run` posts from the vault. Read only this scope's repos, `<vault>` and
`<layer>` — never another scope's folders, and never `<projects>` wholesale.

Run the zero-token collectors and open the collector manifest:

```bash
<module>/bin/evolve open <scope> --quiet-exit
```

`open` and `record` take this session's id from the environment as the pass's own (`--session` names another),
so the pass's transcript never wakes next week's run. `open` runs the installed collectors, writes their run receipts, reads `<module>/lenses.json` (never copy
the lens list into prose or another file), checks tonight's `research` artefact (`{log}/sextant/research`
or `sextant/<date>-research.json`, marking `outside: stale` when absent or incomplete), reconciles carried
findings, picks this cycle's `<deep-lens>`, and runs `evolve coverage --scope <scope> --open`.
- **Exit 3 (`quiet`)**: every required collector reported fresh, no declared source or git ref outside
  `dreams/` and `evolve/` moved since the last `complete` pass, no exclusion is overdue, and no
  `benefit_check` is due. `open` wrote the `quiet` receipt at zero model cost — stop and write nothing else.
- **Exit 2**: a collector, the registry, `lenses.json` or the scope's profile failed (`held` / `failed`,
  never quiet, leaving the last complete cutoff where it was). Say why in one line and stop.

## 1. Reconcile first

Read `open`'s JSON summary and `<staging>` / `carried-findings` (`evolve/*.findings.json`):
1. Every item with `status.proposal == "routed"`: check its execution reference (`status.execution`, PR or
   branch) and whether `status.outcome` has matured.
2. Every item whose `benefit_check.due <= <date>`: run or read its check and state whether the benefit
   held, regressed (`closure_regression`), or stays `pending`. Mature failures stay visible.
3. Accepted work not yet built is a closure gap on the existing `id` (`prior_ids`), never new discovery;
   a killed or parked item is not re-proposed before its `cooldown` or `wake_when` without new evidence.

## 2. Inspect — fourteen lenses, one rotating deep lens

Gather the scoped readers not already in `open`'s packet:

```bash
<module>/bin/week-digest --days 7 --scope <scope>
<module>/bin/week-digest --promote-tags --scope <scope>
<regatta> knowledge-numbers --scope <scope>
<regatta> interruptions --days 7 --list all --scope <scope>
<regatta> repos --branches --scope <scope>
<module>/bin/evolve meetings --scope <scope>
<module>/bin/evolve conformance --scope <scope> --days 7
```

Walk every lens in `<module>/lenses.json` not listed in `<profile>`'s `not_applicable`, reading its
declared sources and `<profile>`'s `sources`, `bars` and `observation_windows`:
- **1–6** (`strategy`, `commercial`, `product`, `engineering`, `tools`, `process`): `north-star`
  (`north-star.json`), `principles` (`PRINCIPLES.md`), `ops` intake and `beacon`, `probes`, `todo`
  (`TODO.md`), `board` (`keel`), `review-gate` (`review-gate.jsonl`), `build-review`
  (`build-review.jsonl`), `trim`, `helm`, `dispatch`, `account`, `week-digest`, `interruptions`, and
  `repo-git`.
- **7–8** (`people`, `meetings`): only what the owner wrote and committed — `meeting-notes` in
  `<anchor>/meetings/` (`templates/meeting.md`: pre-brief `Read before`, after-action, dated if-then
  commitments `Confirmed: yes|pending`). Never read mail, calendar, contact books, recordings or an
  employer tool's transcripts; absent notes stay `source_missing`.
- **9–14** (`money`, `attention`, `knowledge`, `reliability`, `outside`, `loop`): `usage-report`,
  `gate-log` (`gate.jsonl`), `ci-usage` (`ci-usage.json`), `crew-report`, `overrules`,
  `knowledge-numbers`, `agents-md` (`AGENTS.md`) and `<memory>` (`MEMORY.md`), `fence-log` (`fence.log`),
  `health`, `research` (if `open` reported `outside: stale`, record `outside: stale` and propose no
  unverified vendor claim) and `soundings`, `asks` ledgers, `carried-findings` and `scope-pass-md`
  (`.claude/scope-pass.md`, run as the scope's own ritual when present; `<vault>/me/*.md` and
  `<layer>/rules/*.md` read so upstream lines never duplicate what exists).

Give `<deep-lens>` full trace depth: read the underlying rows, name `counterevidence`, and trace one
root mechanism rather than skimming. Every candidate must earn its `kind`:
- **`gap`**: declared bar minus observed state (`north-star`, `PRINCIPLES.md`, `G<n>`, dated `TODO.md`,
  repeated `✱` corrections, 4× identical interruptions). Without a declared bar, report `"no bar for this lens"`.
- **`blind_spot`**: from `coverage` (`unread`, `source_missing`, `inaccessible`, `stale`, unobserved
  surface), 21-day venture / 60-day tool silence, unmatched `E`/`N` asks, or a challenger mode — valid
  only when `intervention` adds a sensor or scheduled observation.
- **`strength`**: repeatable mechanism ≥ 2 MADs past fleet median with `n >= 5` (under 5: watch line
  only), naming `capitalize_as` (`double_down | transfer_trial | extract | sounding`).

## 3. Blinded critic and draft — at most five findings

Draft in `<staging>` (for `atlas`, `<staging>` sits outside `<vault>` so `atlas`'s SessionEnd hook never
commits unchecked dirt; for other scopes `<staging>` is `<anchor>`):
1. `<staging>/evolve/<date>.findings.json` — `findings` schema (`version: 1`, `scope`, `cycle`, `cutoff`,
   at most 5 `findings`), each `action_id` from `<module>/bin/evolve action-id <id> <version> <target_scope>`,
   with `evidence_refs` counts, `acceptance_check`, dated `benefit_check`, `outcome_class` and `status`.
2. `<staging>/evolve/<date>.md` — readable summary: `# Evolve — <scope> — <date>`, `## Reconciled`,
   `## Deep lens: <deep-lens>`, `## Outside` (`complete` or `outside: stale`), `## Findings`, and
   `## Feedback from <owner>`.
3. When `<dream>` and `<draft>` apply (non-layer anchors), write `<dream>` and `<draft>` (`# Upstream — <date>`,
   generalised `U1…` lines with counts and kinds only; confidential scopes name no `<members>`, path,
   `<words>` entry or scope name, and run `<module>/bin/scope-pass check <scope> --judge` until `clean`).

Run the blinded critic over the cold artefact (stripped of owner preferences and overrule history; on a
confidential scope Anthropic-only inside the node, never an external challenger):

```bash
<module>/bin/evolve critic <staging>/evolve/<date>.findings.json --scope <scope>
<module>/bin/evolve validate findings <staging>/evolve/<date>.findings.json --scope <scope>
```

Drop or tighten any finding the critic or validator flags (unrunnable `acceptance_check`, missing
`counterevidence`, undated `benefit_check`, a `blind_spot` that adds no sensor, or an `id` holding its cycle).

## 4. Record and report

```bash
<module>/bin/evolve record <scope>
```

`record` validates the findings, commits `atlas`'s files into `<vault>` (through `knowledge-commit`, never
leaving drafts in the layer) or commits `evolve/<date>.*` with `scope-pass record <scope>` onto
`<records-branch>` (removing untracked working-tree copies, judging and writing `<inbox>` and the export
receipt), exports an open scope's findings list for plumb's `asks` matcher (never a confidential scope's),
and promotes the opening manifest (`evolve coverage --scope <scope> --promote`):
- **0** — recorded (`complete`). Unattended: stop. Interactive: one line per upstream item, top finding,
  and `<records-branch>` (or `<vault>/evolve/<date>.md` for `atlas`).
- **3** — held: a confidential scan or `scope.upstream` `leak` moved the draft to `dreams/<date>-upstream-held.md`;
  rewrite `<draft>` without the leak and run `record` again.
- **1** — could not finish (schema refusal, judge/commit/push failure): fix only a schema or heading error
  it names; never rewrite lines for a judge or push outage — say why in one line and stop.
- **4** — LEAKED: stop, and say only that; `weekly-run` posts it.
- **2** — the node's word list cannot judge the draft (a `re:` line it refuses, or a scan past its time
  limit), or the registry/profile is unreadable: say so in one line and stop; the owner fixes
  `.claude/words.txt` in the node, and nothing you rewrite in the draft changes it.
