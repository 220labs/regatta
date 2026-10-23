"""The question battery, shared by every arm so the comparison is like for like.

One state per decision item, three judgments. The Jev shape (state + typed questions) is the
reference; the LLM arms get the same state and the same question text rendered as a prompt
that asks for the same three numbers. Question ids are for code; the meaning is in the text.
"""
import json
import re

RECOMMENDED_RE = re.compile(r"\s*\((?:recommended|recommend)\)", re.I)


def state_for(item):
    """What the model sees: the decision as the owner saw it, nothing after it."""
    return {"decision": {
        "project": item["repo"],
        "document": item["file"].rsplit("/", 1)[-1],
        "id": item["id"],
        "title": item["title"],
        "body": RECOMMENDED_RE.sub("", item["body"] or ""),
        "prefilled_answer": RECOMMENDED_RE.sub("", item["recommendation"] or ""),
    }, "context": {
        "who_decides": "the owner of these projects, a technical person who builds software, a home "
                       "automation and side ventures with coding agents, optimising for his own attention "
                       "per shipped outcome; he prefers what already exists over new tools, wants hard "
                       "limits named early, and pushes back when a recommendation adds work for him",
        "how_answers_work": HOW_D10 if item.get("shape") == "new" else HOW_OLD,
    }}


HOW_OLD = ("an agent wrote the decision and pre-filled the answer with its recommendation; the owner "
           "either leaves the line as it is, adds a note or a question, or replaces it with a different answer")
# corpus.py marks D10 rows `shape: new`: the recommendation sits on its own line and the answer box
# starts empty, so the same questions read "leaves it as it is" as "writes nothing"
HOW_D10 = ("an agent wrote the decision and recorded its recommendation (shown as prefilled_answer) on "
           "a line of its own; the answer box under it starts empty, and the owner either writes nothing, "
           "takes the recommendation in a word, adds a note or a question, or writes a different answer")


JEV_QUESTIONS = {
    "touched": {
        "type": "noul",
        "instructions": "Will the owner write anything on this decision — an approval in his own words, a "
                        "remark, a question, or a different answer — rather than leave the pre-filled "
                        "`decision.prefilled_answer` exactly as it is?",
        "criteria": {
            "true": "the owner edits the answer line or writes under it, whatever he writes",
            "false": "the owner leaves the line untouched and the recommendation is applied as written",
        },
    },
    "override": {
        "type": "noul",
        "instructions": "Will the owner replace `decision.prefilled_answer` with a materially different "
                        "answer: another of the options, a no where it says yes, a different scope or "
                        "timing, or an instruction the recommendation did not contain?",
        "criteria": {
            "true": "the owner's final answer disagrees with the pre-filled one in substance",
            "false": "the owner keeps the pre-filled answer, possibly adding an approval, a remark or a question",
        },
    },
    "attention": {
        "type": "score",
        "instructions": "How much of the owner's own judgment does this decision need, given `decision.body`?",
        "criteria": [
            "routine: a yes with nothing to weigh; any competent agent would decide the same",
            "worth a glance: a preference or a detail the owner may want to tweak, no real downside either way",
            "needs the owner: a trade-off between things only he can weigh, money, other people, "
            "physical devices, or something hard to undo",
        ],
    },
    "missing_info": {
        "type": "noul",
        "instructions": "Does `decision.body` leave out a fact the owner would need before he could decide "
                        "with confidence, so that his likely reaction is a question back?",
        "criteria": {
            "true": "an important fact, number, or consequence is missing or unclear",
            "false": "the body gives what is needed to decide",
        },
    },
}


def prompt_for(item):
    """The same state and questions as text, for an LLM arm. Asks for one JSON object."""
    q = JEV_QUESTIONS
    return (
        "You predict how the owner of some software projects will answer a decision an agent put to him. "
        "Read the state, then answer four questions as calibrated probabilities and a level. "
        "Return only one JSON object, no prose.\n\n"
        "STATE:\n```json\n" + json.dumps(state_for(item), ensure_ascii=False, indent=1) + "\n```\n\n"
        "QUESTIONS:\n"
        "1. touched — " + q["touched"]["instructions"] + " Answer with the probability (0 to 1) that the "
        "answer is yes, where yes means: " + q["touched"]["criteria"]["true"] + "; and no means: " +
        q["touched"]["criteria"]["false"] + ".\n"
        "2. override — " + q["override"]["instructions"] + " Answer with the probability (0 to 1) that the "
        "answer is yes, where yes means: " + q["override"]["criteria"]["true"] + "; and no means: " +
        q["override"]["criteria"]["false"] + ".\n"
        "3. attention — " + q["attention"]["instructions"] + " Answer with a level: 0 = " +
        q["attention"]["criteria"][0] + "; 1 = " + q["attention"]["criteria"][1] + "; 2 = " +
        q["attention"]["criteria"][2] + ".\n"
        "4. missing_info — " + q["missing_info"]["instructions"] + " Answer with the probability (0 to 1) "
        "that the answer is yes, where yes means: " + q["missing_info"]["criteria"]["true"] + ".\n\n"
        'Output exactly: {"touched": <0..1>, "override": <0..1>, "attention": <0|1|2>, "missing_info": <0..1>}'
    )
