#!/usr/bin/env bash
# A refused hand-over is one visible card, regardless of its reply. Pure scratch facts, no API.
set -u
B="$(cd "$(dirname "$0")/../bin" && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export HOME="$T/home" REGATTA_CONFIG="$T/config" PYTHONDONTWRITEBYTECODE=1
mkdir -p "$HOME" "$REGATTA_CONFIG"
. "$B/../tests/config_fixture.sh"; fixture_config "$REGATTA_CONFIG"
python3 - "$B" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import stalls
count = 0
st = dict(topic="build-demo", repo="/repo/demo", branch="claude/buildbox/2026-10-02-demo",
          started=100, ended=200, end_reason="idle 60 min", session="build-1",
          launch="no launch — open question; to land: answer docs/d.md D2")
f = dict(branch=True, alive=False, status={})
view = dict(raw={"build.json": st}, records={"build.json": f})
def judge(records=(), live=(), asked=()):
    return stalls.judge_runs("buildbox", view, records, set(live), set(asked), 300)[0]
def check(value, label):
    global count
    assert value, label
    count += 1
    print("  ok   " + label)
for reply in ("Built.", "SAM, THIS SESSION IS WAITING FOR NOTHING — built",
              "SAM, THIS SESSION IS DONE — CLOSE THIS SESSION.",
              "SAM, THIS SESSION IS WAITING FOR YOU — D2 of docs/d.md",
              "RELAYED TO run-7 — docs/d.md D2",
              "SAM, THIS SESSION IS WAITING FOR SOMETHING — stamp S3"):
    f["status"]["last_message"] = reply
    cards = judge()
    check(len(cards) == 1 and cards[0]["class"] == "S6" and cards[0]["action"] == "raise", "one visible refusal card: " + reply)
    check(any("to land: answer docs/d.md D2" in e for e in cards[0]["evidence"]), "card carries what would make it land")
first_key = judge()[0]["key"]
st["launch"] = "no launch — origin lacks the tip; to land: publish this tip"
check(judge()[0]["key"] == first_key, "an updated refusal keeps one card rather than creating another")
newer = dict(st, started=250, topic="finish-demo")
check(not judge([("buildbox", "finish.json", newer)]), "a newer landing supersedes the old refusal")
f["status"]["last_message"] = "Built."
st["launch"] = "no launch — x" + "y" * 400
check(max(len(e) for e in judge()[0]["evidence"]) <= stalls.TEXT_LINE + len("dispatch: "), "a long refusal is cut to one evidence line")
st["launch"] = "no launch — refused twice, 60 s apart: " + "busy " * 40 + "; to land: wait for run capacity, then retry"
check(any("to land: wait for run capacity" in e for e in judge()[0]["evidence"]), "a long refusal keeps its next action")
st["launch"] = "no launch — the build run ended with 1"; st["end_reason"] = "exit 1"
cards = judge()
check(cards and cards[0]["class"] == "S1", "a crashed build keeps S1's retry, not a hand-over card")
st["end_reason"] = "idle 60 min"
st["launch"] = "no launch — open for the owner: docs/d.md D2; to land: answer the named non-landing question"
f["status"]["last_message"] = "SAM, THIS SESSION IS WAITING FOR YOU — D2 of docs/d.md"
check(not judge(asked=[(stalls.repo_name(st["repo"]), st["branch"])]), "an open D-item already carded as an ask gets no second card")
st["launch"] = "no launch — open for the owner: docs/d.md D2; to land: answer the named non-landing question"
st["manager"] = "sk-1"
f["status"]["last_message"] = "RELAYED TO sk-1 — docs/d.md D2"
check(not judge(live=["sk-1"]), "a relay its live skipper holds gets no owner card")
del st["manager"]
st["launch"] = "no launch — it ended by claude exited by itself, not idle after its last turn"
st["end_reason"] = "claude exited by itself"
f["status"]["last_message"] = "Now running the integration check."
cards = judge()
check(cards and cards[0]["class"] == "S1", "a run that died keeps S1's retry")
st["end_reason"] = "idle 60 min"
st["launch"] = "no launch — its last reply contains a ⚠ stop; to land: resume the build"
f["status"]["last_message"] = "SAM, THIS SESSION IS WAITING FOR YOU — D2 of docs/d.md"
check(not judge(asked=[(stalls.repo_name(st["repo"]), st["branch"])]), "a ⚠ refusal whose D-items are asks already gets no second card")
f["status"]["last_message"] = "Built."
st["launch"] = "no launch — the mode is now default (plan.json): the sweep judges it under that mode's rules"
check(not judge(), "a mode the owner lowered is the sweep's, no hand-over card")
st["launch"] = "no launch — its brief names open steps: docs/x.md S3 — not started — requeued to the node once"
check(judge() and judge()[0]["class"] == "S6", "a refusal that merely quotes 'requeued' keeps its card")
st["launch"] = "started: autofinish-run --rule C --by handed"
for reply in ("SAM, THIS SESSION IS WAITING FOR SOMETHING — Stamp owed: docs/c.md S3", "SAM, THIS SESSION IS WAITING FOR YOU — D1 of docs/d.md"):
    f["status"]["last_message"] = reply
    check(not judge(), "a started landing is neither retried nor carded: " + reply[-24:])
st["launch"] = "no launch — origin does not hold this build tip; to land: commit and publish"
f["status"]["last_message"] = "Built and checked."
cards = judge()
check(cards[0]["evidence"][0].startswith("dispatch: ")
      and "origin does not hold this build tip; to land: commit and publish" in stalls.evidence_line(cards[0]),
      "the rendered card shows the dispatch refusal and next action before the ended run and last reply")
mine = [(stalls.repo_name(st["repo"]), st["branch"])]
st["launch"] = "no launch — its review loop ended cap; to land: fix the review loop's unfixed findings"
f["status"]["last_message"] = "SAM, THIS SESSION IS WAITING FOR YOU — D1 of docs/digest.md"
cards = judge(asked=mine)
check(cards and cards[0]["class"] == "S6" and any("review loop ended cap" in e for e in cards[0]["evidence"]),
      "a later gate's refusal of a landing-only WAITING run is its card, never hidden behind the landing ask")
st["launch"] = ("no launch — no hand-over: the landing switch was off at the build's start (bin/autofinish arm --landings);"
                " to land: run /finish on this branch")
for reply in ("SAM, THIS SESSION IS WAITING FOR NOTHING — built", "✅ SAM, THIS SESSION IS WAITING FOR NOTHING — built and checked"):
    f["status"]["last_message"] = reply   # a reply with no closing line stays the classifier's, as on main
    cards = judge()
    check(len(cards) == 1 and cards[0]["class"] == "S6" and "run /finish" in stalls.evidence_line(cards[0]),
          "a done build with no hand-over is carded for /finish: " + reply[-12:])
f["status"]["last_message"] = "SAM, THIS SESSION IS WAITING FOR YOU — D2 of docs/d.md"
check(not judge(asked=mine), "no hand-over on a real ask: the ask's own card, as before")
f["status"]["last_message"] = "SAM, THIS SESSION IS WAITING FOR SOMETHING — the integration check"
cards = judge()
check(cards and cards[0]["class"] == "S1", "no hand-over on its own pending work: S1's retry, as before")
st["launch"] = "no launch — origin does not hold this build tip; to land: commit and publish"
st["repo"] = "/repo/transcripts"
f["status"]["last_message"] = "Built."
cards = judge()
check(len(cards) == 1 and any("guarded — open it" in e for e in cards[0]["evidence"])
      and not any("origin does not hold" in e for e in cards[0]["evidence"]), "guarded refusal text stays private")
print("landing cards: %d checks, all passed" % count)
PY
