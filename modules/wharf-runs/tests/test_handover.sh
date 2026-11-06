#!/usr/bin/env bash
# Pure hand-over judgments on a scratch repo and HOME. No launcher, network or live state.
set -u
unset CLAUDE_UNATTENDED REGATTA_UNATTENDED CLAUDE_CODE_DISABLE_BACKGROUND_TASKS DISPATCH_BRIEF
B="$(cd "$(dirname "$0")/../bin" && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export REGATTA_CONFIG="$T/config"
. "$B/../tests/config_fixture.sh"; fixture_config "$T/config"
export HOME="$T/home" PYTHONDONTWRITEBYTECODE=1
mkdir -p "$HOME"
python3 - "$B" "$T" <<'PY'
import importlib.machinery, json, os, subprocess, sys, types
from pathlib import Path
sys.path.insert(0, sys.argv[1])
sys.path.insert(0, str(Path(sys.argv[1]).parent / "lib"))
import core_path
core_path.require()
import common, handover as h

k = h.keel_module()
top = Path(sys.argv[2]) / "repo"
top.mkdir()
def git(*args):
    return h.git(top, *args)
git("init", "-q", "-b", "main")
git("config", "user.name", "test")
git("config", "user.email", "t@t")
(top / "file").write_text("base\n")
(top / "docs").mkdir()
(top / "docs/product.md").write_text("# Product — design\n\n- **D1 — Launch it.**\n"
                                    "  Reversible: yes\n  ➤ Recommended: A\n  ➤ Answer:\n")
git("add", ".")
git("commit", "-qm", "base")
git("update-ref", "refs/remotes/origin/main", "main")
branch = "claude/buildbox/2026-10-02-sample-s5"
git("checkout", "-qb", branch)
(top / "docs/handoff").mkdir(parents=True)
brief = top / "docs/handoff/2026-10-02-sample-s5.md"
brief.write_text("Task: build it\nSteps: S3 of docs/course.md\n")
doc = top / "docs/digest.md"
def digest(title="Land sample S5 (A land now / B hold)"):
    return ("# Sample — build digest\n\nWritten by `sr-worker`\n\n"
            "- **D1 — " + title + ".**\n  - A — land\n  - B — hold\n"
            "  Reversible: yes\n  ➤ Recommended: A\n  ➤ Answer:\n")
def commit():
    git("add", ".")
    git("commit", "-qm", "build", "--allow-empty")
def facts():
    return h.facts(top, branch, "main", k, session="build-session")
def judge(reply):
    return h.judge(reply, facts(), common.ending)
ask_file = Path(git("rev-parse", "--absolute-git-dir")) / "claude/ask.json"
def relay_record(rel, title, **fields):
    return dict({"rel": rel, "doc": str(top / rel), "item": "D1", "title": title,
                 "branch": branch, "session": "build-session", "verdict": "delivered", "answered": None}, **fields)
def record_relays(*rows):
    ask_file.parent.mkdir(parents=True, exist_ok=True)
    ask_file.write_text(json.dumps({"asks": rows}))
checks = 0
def check(value, label):
    global checks
    assert value, label
    checks += 1
    print("  ok   " + label)

doc.write_text(digest()); commit()
wait = "🛑 " + common.WAITING_PREFIX + "D1 of docs/digest.md"
check(not judge(wait), "landing-only D1 ending on WAITING hands over")
check(not judge("RELAYED TO run-7 — docs/digest.md D1"), "legacy landing relay hands over")
check(bool(judge("RELAYED TO run-7 — docs/other.md D1")), "a different relayed question still holds")
check(bool(judge("RELAYED TO run-7 — D1 of docs/other.md (landing status: docs/digest.md)")),
      "mentioning a landing doc does not clear another doc's unanswered relay")
check(bool(judge("RELAYED TO run-7 — D1 of other-docs/digest.md")), "a doc path substring never clears another relay")
check(not judge("RELAYED TO run-7 — D1 of " + str(doc)), "an absolute link to this build's landing item hands over")
check(bool(judge("RELAYED TO run-7 — the deployment question")), "an unlinked relay still holds")
for extra in ("🛑 " + common.WAITING_PREFIX + "D1 of docs/digest.md, and rotate the staging deploy key before it lands",
              "RELAYED TO run-7 — docs/digest.md D1; also: which region should the bucket live in?",
              "🛑 " + common.WAITING_PREFIX + "D1 of docs/digest.md, and paste the deploy token into the vault"):
    check("says more" in judge(extra), "a real ask beside the landing ref holds: " + extra[-40:])
check(not judge("🛑 " + common.WAITING_PREFIX + "D1 of docs/digest.md."), "trailing punctuation alone is no second ask")
title = "Land sample S5 (A land now / B hold)."
check(not judge("🛑 " + common.WAITING_PREFIX + "D1 in docs/digest.md (" + title[:60] + ")"), "bin/ask's own WAITING line for the landing item hands over")
check(bool(judge("RELAYED TO skipper-1 — D1, " + title[:60])), "a title-only relay without its ask record holds")
record_relays(relay_record("docs/digest.md", title))
check(not judge("RELAYED TO skipper-1 — D1, " + title[:60]), "bin/ask's recorded RELAYED landing item hands over")
check(bool(judge("RELAYED TO skipper-1 — D1, Choose the storage backend")), "a relay line naming another title holds")
doc.write_text(digest("Launch it")); commit()
relay = "RELAYED TO skipper-1 — D1, Launch it."
record_relays(relay_record("docs/product.md", "Launch it."))
check(bool(judge(relay)), "a recorded unchanged product question holds beside a landing D1 with the same title")
record_relays(relay_record("docs/digest.md", "Launch it."))
check(not judge(relay), "the recorded doc and item identify the obsolete landing question")
record_relays(relay_record("docs/digest.md", "Launch it."), relay_record("docs/product.md", "Launch it."))
check(bool(judge(relay)), "two recorded questions with the same displayed item and title are ambiguous and hold")
for fields in ({"session": "another-session"}, {"branch": "claude/buildbox/other"}, {"item": "D2"},
               {"answered": 1}, {"verdict": "unreachable"}):
    record_relays(relay_record("docs/digest.md", "Launch it.", **fields))
    check(bool(judge(relay)), "an unrelated or ended relay record holds: " + str(fields))
# a question this run relayed and nobody answered holds on any ending, its doc unchanged by the branch
# (the landing review's S2-1, pick A: this run's session only)
design = relay_record("docs/design.md", "Choose the storage backend", item="D3")
for fields in ({}, {"verdict": "unreachable"}, {"verdict": "none"}):
    record_relays(dict(design, **fields))
    for reply in (common.HANDOVER_LINE, "✅ " + common.IDLE_PREFIX + "built", "Built."):
        check("docs/design.md D3" in judge(reply), "an unanswered relay holds: %s, ending %s" % (fields or "delivered", reply[-20:]))
for fields in ({"session": "another-session"}, {"answered": 1}, {"verdict": "dry-run"}):
    record_relays(dict(design, **fields))
    check(not judge(common.HANDOVER_LINE), "another session's, an answered or a dry-run relay is no hold: " + str(fields))
record_relays(relay_record("docs/digest.md", "Launch it."))
check(not judge(common.HANDOVER_LINE), "an unanswered relay of the obsolete landing item itself is no hold")
ask_file.write_text("{")
check(bool(judge(relay)), "an unreadable relay record holds")
doc.write_text(digest()); commit()
check("Do-this-now" in judge("Built.\n\n## Do this now\n\n```\nsecrets set DEPLOY_TOKEN\n```\n"), "a Do-this-now block holds, no closing line needed")
check("moved its work" in judge(common.ADDRESS + "THIS SESSION MOVED TO laptop — CLOSE THIS TAB. THE WORK CONTINUES THERE."),
      "a run that moved its work elsewhere holds")
check(not judge(common.FINISH_LINES[0]), "a finish done line still hands over")
check("note for the owner" in judge("Built. Rotate the deploy key by hand first.\n\n✅ " + common.FINISH_LINES[1]),
      "the finish line that leaves a note for the owner holds")
doc.write_text(digest().replace("  ➤ Answer:\n", "  ➤ Answer: B — hold until the vendor's quota is raised\n")); commit()
check("answered" in judge(common.IDLE_PREFIX + "held per D1"), "a landing item the owner answered hold holds")
doc.write_text(digest().replace("  ➤ Answer:\n", "  ➤ Answer: A\n")); commit()
check(not judge(common.HANDOVER_LINE), "a landing item the owner answered land hands over")
for answer, option in (("B", "postpone the landing"), ("B", "never land this branch; abandon it"), ("Never land it", "hold"),
                       ("A, but rotate the deploy key first", "hold")):
    doc.write_text(digest().replace("  - B — hold\n", "  - B — " + option + "\n").replace("  ➤ Answer:\n", "  ➤ Answer: " + answer + "\n")); commit()
    check("answered" in judge(common.HANDOVER_LINE), "an owner's answer that is no plain land holds: " + answer + " / " + option)
doc.write_text(digest()); commit()
check(bool(judge("⚠ build incomplete\n" + common.HANDOVER_LINE)), "a warning still holds")
check(not judge("✅ " + common.IDLE_PREFIX + "built and checked"), "idle complete build hands over")
check(not judge("Built and checked."), "a completed reply need not carry a magic hand-over line")
doc.write_text(digest().replace("# Sample — build digest", "# Sample").replace("Written by `sr-worker`", "")); commit()
check(not judge(wait), "an explicit own-branch landing title works without a digest heading")
doc.write_text(digest("Launch it").replace("# Sample — build digest", "# Product — design").replace("Written by `sr-worker`", "")); commit()
check(bool(judge(wait)), "a product design's implicit launch question is a real ask")
doc.write_text(digest()); commit()
check(any("landing this build" in e for e in k.lint(doc.read_text(), path=doc)[0]), "keel lint refuses a landing D-item in a build digest")
r = subprocess.run([str(Path(k.__file__)), "lint", str(doc)], capture_output=True, text=True)
check(r.returncode == 1 and "landing this build" in r.stdout, "keel lint CLI enforces the error")
for title in ("Land this branch", "Launch it", "Finish this run", "Merge sample S5", "Should we land sample-s5"):
    check(k.landing_subject(title, branch), "own-branch subject: " + title)
for title in ("Launch the product", "Land other-branch", "Finish the migration", "Land sample S5 after buying credits", "Landing page layout"):
    check(not k.landing_subject(title, branch), "real decision retained: " + title)
check(not any("landing this build" in e for e in k.lint(digest().replace("# Sample — build digest", "# Sample — design").replace("Written by `sr-worker`", "Written by `architect`"))[0]), "attended design is unaffected")
doc.write_text(digest("Choose the storage backend")); commit()
check(bool(judge(common.HANDOVER_LINE)), "non-landing D-item holds even on the hand-over line")
check(bool(judge(wait)), "non-landing D-item holds on WAITING")
doc.write_text("# Sample — build digest\nImplementation and check done.\n"); commit()
pending = common.PENDING_PREFIX + "keel step docs/course.md S3 done --stamp — doc not on main"
check(not judge(pending), "stamp-only ending hands over with a doc absent from this branch")
check(not judge(common.PENDING_PREFIX + "keel step docs/course.md S3 done --branch " + branch + " --stamp"),
      "the stamp command's branch flag is supported")
check(not h.stamp_only(common.PENDING_PREFIX + "stamp S9 in docs/course.md",
                       ["docs/course.md S3 — pending", "docs/other.md S9 — pending"]),
      "a doc and step must match as a pair, never across two owed stamps")
for payload in ("the reviewers, then stamp", "the integration check", "keel step docs/other.md S3 done --stamp", "stamp S9"):
    check(bool(judge(common.PENDING_PREFIX + payload)), "real or mismatched pending work holds: " + payload)
note = h.finish_note(top, branch, "main", k)
check("Stamp owed: docs/course.md S3" in note and "PR body" in note, "finish prompt names the owed stamp in its PR")
course = top / "docs/course.md"
course.write_text("# Course\n\n## Action plan\n\n- **S3 — Build it** · session · status: wip\n")
commit()
unwritable = common.PENDING_PREFIX + "stamp S3 in docs/course.md — could not write the stamp"
check(not judge(unwritable), "an unwritable step stamp the closing line names exactly hands over")
check(not judge(common.PENDING_PREFIX + "Stamp owed: docs/course.md S3"), "the prompt's own Stamp owed line hands over")
check(not judge(common.PENDING_PREFIX + "Stamp owed: docs/course.md S3."), "  and with a closing period (named() cuts it as stamp_only does)")
for path in (str(course), "./docs/course.md", str(top / "docs/../docs/course.md")):
    for payload in ("Stamp owed: %s S3", "keel step %s S3 done --stamp", "stamp S3 in %s"):
        check(not judge(common.PENDING_PREFIX + payload % path), "a normalized stamp path hands over: " + payload % path)
for path in (str(top.parent / "elsewhere/docs/course.md"), "../elsewhere/docs/course.md", "other-docs/course.md"):
    check(bool(judge(common.PENDING_PREFIX + "Stamp owed: %s S3" % path)), "a different document with the same suffix holds: " + path)
check(bool(judge(common.PENDING_PREFIX + "Stamp owed: docs/course.md S3, then the review")), "a Stamp owed line with more work holds")
check(bool(judge(common.HANDOVER_LINE)), "a wip step on this branch holds on the hand-over line")
check(bool(judge(common.PENDING_PREFIX + "stamp S3")), "a stamp wait that names no doc waives no step on this branch")
check("Stamp owed" not in h.finish_note(top, branch, "main", k) and "Still open" in h.finish_note(top, branch, "main", k),
      "without the judge's waiver the finish waives no step whose doc is on this branch")
check("Stamp owed: docs/course.md S3" in h.finish_note(top, branch, "main", k, owed="docs/course.md S3\n"),
      "the judge's waived pair reaches the finish's note")
brief.write_text("Task: build it\nSteps: S3, S4 of docs/course.md\n")
course.write_text("# Course\n\n## Action plan\n\n- **S3 — Build it** · session · status: wip\n- **S4 — Then this** · session · status: not started\n")
commit()
held = judge(unwritable)
check("S4" in held and "not started" in held, "a not-started step holds beside a stamp the line waives")
check(bool(judge(common.HANDOVER_LINE)), "a not-started step holds on the hand-over line")
check("not started" in judge(common.PENDING_PREFIX + "keel step docs/course.md S4 done --stamp"),
      "a not-started step holds even when the closing line names it")
check("docs/course.md S4" not in h.finish_note(top, branch, "main", k, owed="docs/course.md S3\ndocs/course.md S4\n").split("Still open")[0],
      "a not-started step the judge never waived stays out of the finish's waiver")
brief.write_text("Task: build it\nSteps: S7 of docs/course.md\n"); commit()
check("no such step" in judge(common.PENDING_PREFIX + "keel step docs/course.md S7 done --stamp"), "a no-such-step holds even when the line names it")
check(bool(judge(common.HANDOVER_LINE)), "a no-such-step holds on the hand-over line")
check("Stamp owed" not in h.finish_note(top, branch, "main", k, owed="docs/course.md S7\n"), "the finish never waives a no-such-step")
course.write_text("# Course\n\n## Action plan\n\n- **S3 — Build it** · session · status: deferred\n"); commit()
brief.write_text("Task: build it\nSteps: S3 of docs/course.md\n"); commit()
check("deferred" in judge(common.PENDING_PREFIX + "Stamp owed: docs/course.md S3"), "a step keel reads as not started holds even when named")
brief.write_text("Task: build it\nSteps: S3 of docs/course.md.\n"); commit()
check("does not read as its Course doc" in judge(common.HANDOVER_LINE), "a Steps line whose doc is on this branch, misspelt, holds")
course.write_text("# Course\n\n## Action plan\n\n- **S3 — Build it** · session · status: wip\n")
brief.write_text("Task: build it\nSteps: S2 of docs/my+notes.md\n"); commit()
check(bool(judge(common.HANDOVER_LINE)), "a Steps doc no queued finish could carry holds on both roads")
brief.write_text("Task: build it\n"); commit()
check(not judge(common.PENDING_PREFIX + "Stamp owed: docs/course.md S3"), "a Stamp owed line with nothing owed hands over")
brief.write_text("Task: build it\nSteps: S2 of docs/elsewhere.md\n"); commit()
check(not judge(common.HANDOVER_LINE), "a stamp in a doc not on this branch is waived on the hand-over line")
check("Stamp owed: docs/elsewhere.md S2 — the doc is not on this branch" in h.finish_note(top, branch, "main", k),
      "the finish names a doc-not-on-branch stamp as owed")
check("mark it done" in h.next_action("its brief names open steps: docs/course.md S4 — not started"), "an open step names what makes it land")
brief.write_text("Task: build it\nSteps: S3 of docs/course.md\n")
doc.write_text(digest()); commit()
check("remove these obsolete landing questions" in h.finish_note(top, branch, "main", k), "finish removes obsolete landing asks without fabricating answers")
af = importlib.machinery.SourceFileLoader("handover_af", str(Path(sys.argv[1]) / "autofinish-run")).load_module()
target = types.SimpleNamespace(branch=branch, path=str(top), primary=str(top), window="finish-demo")
os.environ["HANDOVER_OWED"] = "docs/course.md S3\n"
prompt = af.start_cmd(target, "finish-fixture", by="handed")[2]
check(prompt.split("\n\n", 1)[0] == "/finish %s --unattended" % branch,
      "the handed prompt's command has no hold or mode flag before its multiline note")
check("Stamp owed: docs/course.md S3" in prompt and "remove these obsolete landing questions" in prompt,
      "the actual handed launcher carries both obligations into its finish prompt")
del os.environ["HANDOVER_OWED"]
prompt = af.start_cmd(target, "finish-fixture", by="handed")[2]
check("Stamp owed" not in prompt and "Still open" in prompt, "the launcher with no waiver from dispatch holds the open step")
# a relaunch of a handed landing (a chain after a review stop, a lander after a login or limit stop) has no env of the
# judge's: it reads the stop it continues, which recorded the note and the waiver (the re-landing's review, 2026-11-06)
stop = {"by": "handed", "handover": True, "owed": ["docs/course.md S3"]}
check(af.handover_of("handed", "chain", stop) == (True, ["docs/course.md S3"]), "a chain relaunch of a handed run keeps its waiver")
check(af.handover_of("lander", "lander", stop) == (True, ["docs/course.md S3"]), "a lander start on a handed stop keeps it too")
check(af.handover_of("lander", "chain", {"by": "lander", "handover": True, "owed": ["docs/course.md S3"]})[0],
      "  and a chain relaunch of that lander run, a second hop")
check(af.handover_of("lander", "lander", {"by": "handed"}) == (True, []), "a handed stop with nothing waived still carries the note")
check(af.handover_of("lander", "lander", {"by": "sweep"}) == (False, []), "a lander start on any other stop carries none")
check(af.handover_of("sweep", "sweep", stop) == (False, []), "a sweep's start carries none")
target.handover = af.handover_of("lander", "lander", stop)
prompt = af.start_cmd(target, "finish-fixture", by="lander")[2]
check("Stamp owed: docs/course.md S3" in prompt and "remove these obsolete landing questions" in prompt,
      "the lander relaunch's finish prompt carries the hand-over's note and waiver")
del target.handover
dq = importlib.machinery.SourceFileLoader("handover_dq", str(Path(sys.argv[1]) / "dispatch-queue")).load_module()
entry = lambda **f: {"tip": "a" * 40, "finish": dict({"by": "handed", "rule": "C", "merge": False, "hold": False}, **f)}
check(dq.finish_bad(entry(owed=["docs/course.md S3"])) is None, "a queued handed finish carries the stamps its judge waived")
check(dq.finish_bad(entry(by="lander", road="login", owed=["docs/course.md S3"])) is None,
      "a queued lander relaunch of a handed stop carries them too")
for bad, label in ((dict(by="sweep", owed=["docs/course.md S3"]), "another --by"), (dict(owed="docs/course.md S3"), "a string"),
                   (dict(owed=["docs/course.md S3; rm -rf"]), "a stray word")):
    check(dq.finish_bad(entry(**bad)), "the queue refuses owed stamps on " + label)
doc.write_bytes(b"\xff")
try:
    facts()
except UnicodeDecodeError:
    check(True, "unreadable changed doc fails closed")
else:
    check(False, "unreadable changed doc fails closed")
check("answer the named" in h.next_action("open for the owner: docs/digest.md D1"), "a held decision names what makes it land")
for why, want in (("refused twice, 60 s apart: 3 other runs are busy (cap 3) — the next step waits for a run to end", "run capacity"),
                  ("autofinish-run exit 5: not started: busy — the next step waits for a run to end", "run capacity"),
                  ("origin/main unreadable here", "fetch origin"),
                  ("the week's budget is unreadable (URLError: Network is unreachable)", "budget"),
                  ("its run record is unreadable (/logs/2026-11-05-network-fix.json)", "repair the named"),
                  ("/srv/wt/question-bank has uncommitted changes", "publish this build"),
                  ("a next step is queued on this branch, or the queue does not read (dispatch --queue)", "queued or scheduled"),
                  ("its brief names open steps: docs/course.md S7 — no such step in its Action plan", "exist in its Course doc")):
    check(want in h.next_action(why), "next action for: " + why[:50])
check("review loop" in h.next_action("its review loop ended cap"), "a review loop at its round cap names its findings, not capacity")
for why, want in (("its last reply stops for the owner: WAITING FOR YOU — D1 raise the cap on the export job", "answer the named"),
                  ("the mode is now default (plan.json): the sweep judges it under that mode's rules", "the mode the owner set"),
                  ("autofinish is disarmed on this Mac", "bin/autofinish arm")):
    check(want in h.next_action(why), "next action reads the cause alone: " + why[:40])
# an owner's D-item the doc held on main, in a doc this branch changes, is the owner's: it holds
git("checkout", "-q", "--", ".")   # the unreadable-doc case's bytes, never committed
git("checkout", "-q", "main")
owner = top / "docs/ci-design.md"
owner.parent.mkdir(exist_ok=True)
owner.write_text("# CI — design\n\nWritten by `architect`\n\n- **D2 — Ship the build (A on tag / B on every push).**\n"
                 "  - A — on tag\n  - B — on every push\n  Reversible: no\n  ➤ Recommended: A\n  ➤ Answer:\n")
git("add", "."); git("commit", "-qm", "owner doc")
git("checkout", "-q", branch); git("merge", "-q", "--no-edit", "main")
owner.write_text(owner.read_text().replace("Written by `architect`\n", "Written by `architect`\n\nA line the build added.\n")); commit()
check("docs/ci-design.md D2" in judge(common.HANDOVER_LINE), "an owner's open D-item from main stays open, never an obsolete landing ask")
print("handover: %d checks, all passed" % checks)
PY
