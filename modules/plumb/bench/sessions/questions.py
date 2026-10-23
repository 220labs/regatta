"""The battery for "is this idle session done, waiting on the owner, blocked or running?" — shared by every
arm so the comparison is like for like (orchestration-landscape D10).

State: the session's last reply, its project, the title Claude gave it, the last prompt and
whether a tool call is still pending. The Jev shape is the reference; the LLM arms get the same
state and the same definitions rendered as a prompt asking for the same answer.
"""
import json

# `running` from week two (D5, 2026-10-02): the owner's note on a background fill round — "not
# blocked, not waiting on the owner. Just WIP — and not OK to close."
LABELS = ("done", "waiting_on_owner", "blocked", "running")
DEFINITIONS = {
    "done": "the session's work is finished or handed on; nothing is owed by the owner and closing "
            "the session loses nothing — a report, a launched change, a 'next: open a session in X'",
    "waiting_on_owner": "the reply asks the owner to do, check, decide, paste, run, answer or look at "
                       "something before the work can continue or count as complete — with or "
                       "without a question mark",
    "blocked": "the session stopped on something neither it nor the owner can settle from this reply: "
               "a limit, an error it could not get past, another machine or process it waits on",
    "running": "the session is mid-work — a background job or a long task it started is still going and "
               "will report by itself; nothing is asked of the owner, and closing it now would lose work",
}


def state_for(row):
    return {"session": {
        "project": row["repo"],
        "title": row.get("title") or "",
        "owners_last_prompt": row.get("last_prompt") or "",
        "tool_call_pending": bool(row.get("pending_tool_calls")),
        "last_reply": (row.get("text") or "")[-2500:],
    }, "context": {
        "who_reads": "the owner runs many coding-agent sessions in parallel and loses track of which "
                     "are finished; he asks each idle session's last reply one thing: is it done, is "
                     "it waiting for me, is it stuck, or is it still working",
    }}


JEV_QUESTIONS = {
    "status": {
        "type": "choice",
        "instructions": "Read `session.last_reply` as the owner would when deciding whether to close "
                        "this session: is the session done, waiting on the owner, blocked, or still running?",
        "criteria": dict(DEFINITIONS),
    },
    "needs_owner": {
        "type": "noul",
        "instructions": "Does `session.last_reply` ask the owner to do or decide something before the "
                        "work can continue or be complete?",
        "criteria": {"true": "yes — an action, check, answer, paste or decision is asked of the owner",
                     "false": "no — nothing is asked of the owner, whatever else the reply says"},
    },
    "handoff": {
        "type": "noul",
        "instructions": "Does `session.last_reply` hand the work on to another session, tab, machine "
                        "or branch, so that this session itself is finished?",
        "criteria": {"true": "yes — it names where the work continues", "false": "no"},
    },
}


def prompt_for(row):
    d = DEFINITIONS
    return (
        "You judge the last reply of an idle coding-agent session for its owner, who runs many sessions "
        "and wants to know whether each is done, waiting on him, blocked, or still running. Read the state and answer "
        "with one JSON object, no prose.\n\n"
        "STATE:\n```json\n" + json.dumps(state_for(row), ensure_ascii=False, indent=1) + "\n```\n\n"
        "Labels: done = " + d["done"] + ". waiting_on_owner = " + d["waiting_on_owner"] + ". blocked = " +
        d["blocked"] + ". running = " + d["running"] + ".\n\n"
        'Output exactly: {"status": "done|waiting_on_owner|blocked|running","p_waiting": <probability 0..1 that the '
        'owner must act before the work can continue>, "handoff": <probability 0..1 that the work was handed '
        "on elsewhere>}"
    )
