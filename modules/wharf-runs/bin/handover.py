#!/usr/bin/env python3
"""A done build's hand-over: read its asks, with narrow exceptions for landing and stamps.

No writes, network, or change to the attended Stop rules. Dispatch also checks the run, review,
mode, switches and origin; the finish re-reads these facts on its own host for its prompt.
"""
import importlib.machinery
import json
import posixpath
import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "lib"))


def git(top, *args):
    r = subprocess.run(["git", "-C", str(top), *args], capture_output=True, text=True, timeout=30)
    if r.returncode:
        raise ValueError("git %s did not read" % args[0])
    return r.stdout.strip()


def keel_module(path=None):
    if not path:
        import core_path
        core_path.require()
        import common
        path = common.tool("keel")
    if not path:
        raise ValueError("keel is not installed")
    return importlib.machinery.SourceFileLoader("handover_keel", str(path)).load_module()


def facts(top, branch, base, keel=None, session=None):
    """Only branch-added/changed asks count. An unreadable doc is a hold, never an empty list. A D-item
    reads as an obsolete landing question only where this branch added it: one the doc held at the fork
    point (an owner's, from main) is the owner's decision, open as on main."""
    top = Path(top)
    k = keel or keel_module()
    names = git(top, "diff", "--name-only", "-z", "--no-renames", "--diff-filter=AM", base + "...HEAD", "--", "*.md")
    fork = git(top, "merge-base", base, "HEAD")
    out = {"open": [], "landing": [], "stamps": [], "owed": [], "wip": set(), "titles": {}, "top": str(top.absolute()),
           "relays": [], "asked": []}
    # bin/ask's display omits the document. Its per-worktree record is the identity of that question,
    # including one in an unchanged doc that this branch's diff cannot tell us about.
    try:
        recorded = json.loads((Path(git(top, "rev-parse", "--absolute-git-dir")) / "claude/ask.json").read_text())
        rows = recorded.get("asks", []) if isinstance(recorded, dict) else []
        if isinstance(rows, list):
            mine = [r for r in rows if isinstance(r, dict) and r.get("branch") == branch
                    and (session is None or r.get("session") == session) and not r.get("answered")]
            out["relays"] = [r for r in mine if r.get("verdict") not in (None, "none", "unreachable", "dry-run")]
            # Every question this run put through bin/ask and nobody answered, one that reached nobody included:
            # the ending need not name it, and its doc need not be one this branch changed (judge() holds on it).
            # This run's own session only: an earlier session's relay may have been answered through a resume
            # run that never set `answered` (the landing review's pick A, 2026-11-06).
            out["asked"] = [r for r in mine if r.get("verdict") != "dry-run"]
    except (OSError, ValueError):
        pass   # a title-only relay with no readable record holds
    for name in filter(None, names.split("\0")):
        text = (top / name).read_text()
        lines, items, _ = k.parse(text)
        before = subprocess.run(["git", "-C", str(top), "show", "%s:%s" % (fork, name)], capture_output=True, timeout=30)
        old = set()
        if before.returncode == 0:   # absent at the fork: every item is the branch's
            old = {it["id"] for it in k.parse(before.stdout.decode("utf-8"))[1]}
        for it in items:
            key = "%s %s" % (name, it["id"])
            landing = it["id"] not in old and k.landing_subject(it["title"], branch, implicit=k.build_digest(text))
            if k.yolo_settled(it, lines):
                if landing and not answer_lands(it):   # the owner said hold: their word stands
                    out["open"].append(key + " (answered: " + (it["answer"] or "a reply").strip()[:60] + ")")
                continue
            target = "landing" if (landing and not k.reopened(it, lines)) else "open"
            out[target].append(key)
            out["titles"][key] = it["title"]
    # Every step the brief names that its doc does not mark done. Only waived() may excuse one,
    # and only as a status mark: an unstarted or missing step is unfinished work, and holds.
    for _, doc, step, why in k.landing_open(top, base):
        if why == DOC_ABSENT and any((top / d).exists() for d in (doc, doc.rstrip(".,;:)"))):
            why = "the brief names %s, which is on this branch but does not read as its Course doc" % doc
        elif why != DOC_ABSENT:
            try:
                st = {x["id"]: x for x in k.keel_parse((top / doc).read_text().split("\n"))["steps"]}.get(step)
            except (OSError, UnicodeDecodeError):
                st = None
            if st and st.get("status") == "wip":   # keel's word for started and not done: built, its stamp owed
                out["wip"].add((doc, step))
        out["stamps"].append("%s %s — %s" % (doc, step, why))
        out["owed"].append((doc, step, why))
    return out


PLAIN_LAND = re.compile(r"(?:yes|(?:land|launch|merge|ship|finish)(?:\s+(?:it|now|this branch|the branch|this build))*)", re.I)


def answer_lands(it):
    """The owner's answer picks landing only as a bare option letter whose option is a plain land, or a bare
    yes or land; every other answer (a hold, a condition, a free word, a dated reply) is the owner's, and holds."""
    answer = (it.get("answer") or "").strip().rstrip(".!")
    if re.fullmatch(r"[A-Z]", answer):
        answer = dict(it.get("options") or []).get(answer, "").strip().rstrip(".!")
    return bool(PLAIN_LAND.fullmatch(answer))


DOC_ABSENT = "the doc is not on this branch"   # keel's landing_open reason: no stamp can be made here


OWED_WORD = re.compile(r"[\w./-]{1,200}\.md S\d{1,4}")   # dispatch-queue's: what a queued finish may carry


def waivable(row, said, wip):
    """One owed (doc, step, why) row: its doc is truly off this branch, or `said` names it and keel reads the
    step as `wip` (built, its stamp owed); not started, blocked, no status or no such step always holds, and
    so does a doc no queued finish could carry (the queue's OWED_WORD), so both roads judge alike."""
    if not OWED_WORD.fullmatch("%s %s" % row[:2]):
        return False
    return row[2] == DOC_ABSENT or ((row[0], row[1]) in wip and said(row))


def doc_path(doc, top=""):
    """One spelling for a document under this checkout; an outside path stays outside it."""
    if not top:
        return posixpath.normpath(doc)
    root = Path(top).resolve()
    path = (root / doc).resolve()
    try:
        return path.relative_to(root).as_posix()
    except ValueError:
        return path.as_posix()


def named(line, row, top=""):
    """The closing line names this one stamp exactly: its step and its doc, in the stamp grammar."""
    payload = (line or "").split(" — ", 1)[-1].strip().strip("` .")   # stamp_only's own cut: a closing period is no word
    doc, step = row[0], row[1]
    ids = re.findall(r"(?<![/\w])S\d+(?![\w.])", payload)
    docs = [d.strip("`") for d in re.findall(r"[^\s`]+\.md", payload)]
    return step in ids and any(doc_path(d, top) == doc_path(doc, top) for d in docs)


def waived(data, kind, line):
    """(waived, held): a stamp is waived only when its doc is not on this branch, or when the run's
    ⏳ line is a stamp-only wait that names that doc and step; every other open step holds."""
    top = data.get("top", "")
    stamp_wait = kind == "pending" and stamp_only(line, data["stamps"], top=top)
    out, held = [], []
    for row in data.get("owed", []):
        (out if waivable(row, lambda r: stamp_wait and named(line, r, top), data.get("wip", ())) else held).append(row)
    return out, held


def stamp_line(line):
    """The ⏳ line is a stamp wait in the grammar below, whatever is owed."""
    return bool(line) and stamp_only(line, None, grammar_only=True)


def stamp_only(line, stamps, grammar_only=False, top=""):
    """Accept one explicit stamp wait, never 'review then stamp' or an unrelated pending task."""
    if (not stamps and not grammar_only) or not line:
        return False
    payload = line.split(" — ", 1)[-1].strip().strip("` .")
    # A small grammar: naming another activity alongside a stamp must keep the run held.
    matched = re.fullmatch(
        r"(?:the )?(?:keel step\s+`?[^\s`]+\.md`?\s+S\d+\s+done"
        r"(?:\s+--branch\s+[A-Za-z0-9_./-]+)?(?:\s+--stamp)?(?:\s+--branch\s+[A-Za-z0-9_./-]+)?|"
        r"(?:step )?stamp(?:\s+S\d+)?(?:\s+(?:in|of|for)\s+`?[^\s`]+\.md`?)?|"
        r"stamps? owed\s*[:—-]?\s*`?[^\s`]+\.md`?\s+S\d+(?:\s*,\s*S\d+)*)"
        r"(?:\s*[—:;-]\s*(?:the )?(?:doc (?:is )?not on (?:main|this branch)|"
        r"could not (?:make|write) (?:the )?stamp|stamp (?:is )?owed))?", payload, re.I)
    if not matched or grammar_only:
        return bool(matched)
    ids = re.findall(r"(?<![/\w])S\d+(?![\w.])", payload)
    docs = re.findall(r"[^\s`]+\.md", payload)
    pairs = [s.split(" — ", 1)[0].rsplit(" ", 1) for s in stamps]
    return bool(ids or len(stamps) == 1) and all(
        any((not doc or doc_path(doc, top) == doc_path(d, top)) and (not sid or sid == step) for d, step in pairs)
        for doc in (docs or [""]) for sid in (ids or [""]))


def judge(text, data, ending):
    """A hold reason, or empty. A legacy landing ask must resolve to an actual landing D-item."""
    kind, line, problem = ending(text)
    common = sys.modules.get(getattr(ending, "__module__", "")) or _common()
    if "⚠" in text:
        return "its last reply contains a ⚠ stop"
    if common.do_this_now_block(text):
        return "its last reply hands the owner a Do-this-now step"
    if kind == "done" and line == common.FINISH_LINES[1]:
        return "its last reply leaves a note for the owner: " + (line or "")
    if kind == "done" and line not in (common.FINISH_LINES[0],) + tuple(common.DECLARED_LINES):
        return "its last reply moved its work elsewhere: " + (line or "")
    if data["open"]:
        return "open for the owner: " + "; ".join(data["open"])
    top = data.get("top", "")
    unanswered = ["%s %s" % (doc_path(r["rel"], top), r.get("item")) if isinstance(r.get("rel"), str) else
                  "%s (no doc recorded)" % r.get("item") for r in data.get("asked", [])]
    unanswered = [x for x in unanswered if x not in data["landing"]]
    if unanswered:
        return "its relayed or waiting question has no settled answer: " + "; ".join(unanswered) + " (relayed, unanswered)"
    if problem:
        return "its closing line is incomplete or followed by more work"
    held = waived(data, kind, line)[1]
    if held:
        return "its brief names open steps: " + "; ".join("%s %s — %s" % row for row in held)
    if kind in ("waiting", "relayed"):
        # Every referenced D-item must be one of the landing questions; a relayed real ask
        # outside the changed docs is not cleared by a landing D1 elsewhere on the branch.
        refs = re.findall(r"\bD\d+\b", line or "")
        if not data["landing"] or not refs:
            return "its last reply stops for the owner: " + (line or "")
        titles = data.get("titles", {})
        relay = re.fullmatch(r"RELAYED TO \S.* — (D\d+), (.+)", line or "")
        if kind == "relayed" and relay:   # bin/ask's relay line: the item and its title, no doc
            hits = [r for r in data.get("relays", []) if r.get("item") == relay.group(1)
                    and isinstance(r.get("title"), str) and r["title"][:60].strip() == relay.group(2).strip()]
            if len(hits) == 1:
                row = hits[0]
                doc = row.get("rel")
                if isinstance(doc, str):
                    key = "%s %s" % (doc_path(doc, data.get("top", "")), row["item"])
                    if key in data["landing"] and titles.get(key, "")[:60].strip() == relay.group(2).strip():
                        return ""
            return "its relayed or waiting question has no settled answer: " + (line or "")
        said = (line or "").replace("`", "").replace("[", "").replace("]", "")
        mentioned = re.findall(r"[\w./~-]+\.md", said)
        paths = {}
        for doc in mentioned:   # one spelling, as named() and the relay read it: a resolved or linked top alike
            paths[doc] = doc_path(doc[2:] if doc.startswith("./") else doc, data.get("top", ""))
        allowed = {x.rsplit(" ", 1)[0] for x in data["landing"]}
        if not paths or any(rel not in allowed for rel in paths.values()):
            return "its relayed or waiting question has no settled answer: " + (line or "")
        for ref in refs:
            docs = [x.rsplit(" ", 1)[0] for x in data["landing"] if x.endswith(" " + ref)]
            if not any(rel in docs and (re.search(r"\b" + ref + r"\s+(?:of|in)\s+" + re.escape(doc), said)
                                       or re.search(re.escape(doc) + r"(?:#|:\s*|\s+)" + ref + r"\b", said))
                       for doc, rel in paths.items()):
                return "its relayed or waiting question has no settled answer: " + (line or "")
        # The line may say nothing beyond those landing refs: a second ask or a manual step in its
        # prose ("…, and paste the token") is the owner's, whatever D-ref rides beside it.
        rest = said.split(" — ", 1)[1] if " — " in said else said
        for x in data["landing"]:   # bin/ask's WAITING line: `D1 in <doc> (<its title[:60]>)`
            t = titles.get(x, "")[:60].replace("`", "").replace("[", "").replace("]", "")
            if t:
                rest = rest.replace("(" + t + ")", " ")
        for doc in sorted(paths, key=len, reverse=True):
            for ref in refs:
                rest = re.sub(r"\b" + ref + r"\s+(?:of|in)\s+" + re.escape(doc), " ", rest)
                rest = re.sub(re.escape(doc) + r"(?:#|:\s*|\s+)" + ref + r"\b", " ", rest)
        if re.sub(r"\b(?:and|the)\b|[\s,;.&()]+", "", rest, flags=re.I):
            return "its relayed or waiting question says more than its landing question: " + (line or "")
    elif kind in ("pending", "lander") and not stamp_only(line, data["stamps"], top=data.get("top", "")) and not (not data["stamps"] and stamp_line(line)):
        return "its last reply waits on its own work: " + (line or "")
    return ""


def _common():
    import core_path
    core_path.require()
    import common
    return common


def finish_note(top, branch, base, keel=None, owed=None):
    """The finish's prompt note. `owed`: the "doc step" pairs dispatch's judge waived on the run's
    closing line (HANDOVER_OWED); without it only a doc absent from the branch is waived here."""
    data = facts(top, branch, base, keel)
    said = set(filter(None, (owed or "").split("\n"))) if isinstance(owed, str) else set(owed or ())
    notes = ["This is a done build handed to its landing. Never ask whether to land it."]
    if data["landing"]:
        notes.append("Before the open-items gate, remove these obsolete landing questions from the build digest "
                     "(do not invent owner answers): " + "; ".join(data["landing"]) + ".")
    ok = [r for r in data["owed"] if waivable(r, lambda x: "%s %s" % x[:2] in said, data["wip"])]
    if ok:
        notes.append("Stamp owed: " + "; ".join("%s %s — %s" % r for r in ok) + ". These are the build's missing "
                     "status marks. Carry each doc and step into the PR body as owed; do not wait for a stamp or "
                     "write it on another branch. This hand-over may pass the open-step gate with these stamps "
                     "owed, and only these. All implementation, review and other open-item gates still apply.")
    rest = [r for r in data["owed"] if r not in ok]
    if rest:
        notes.append("Still open, and the open-step gate holds them: " + "; ".join("%s %s — %s" % r for r in rest) + ".")
    return "\n".join(notes)


def next_action(why):
    """One next action for every retained refusal, including failures outside the ask judge. Read on dispatch's
    own phrases, in order: the specific causes first, a path or a parenthesised detail never a cause."""
    if re.match(r"origin/\S+ unreadable", why):
        return "fetch origin's main branch on this host, then retry the hand-over"
    if re.match(r"its last reply (?:stops for|leaves a note)|its relayed or waiting question", why):
        return "answer the named non-landing question and resume the build"
    head = re.sub(r"\([^()]*\)|\S+/\S+", " ", why)
    checks = (
        (r"no such step", "make each step the brief's Steps line names exist in its Course doc, then resume the build"),
        (r"\bopen steps?\b", "finish each open step and mark it done (keel step <doc> <S> done --stamp), then retry the hand-over"),
        (r"review loop|review record", "fix the review loop's unfixed findings in the build, then retry the hand-over"),
        (r"waits for a run to end|refused twice|runs are busy|\bcap\b", "wait for run capacity, then retry the hand-over"),
        (r"a next step is (?:scheduled|queued)|\brequeued\b", "let the queued or scheduled build finish, then hand over its result"),
        (r"\bmode is now (?:unreadable|\(|$)", "restore a readable landing mode for this branch, then retry the hand-over"),
        (r"\bmode is now\b", "nothing here: the sweep judges the branch under the mode the owner set"),
        (r"autofinish is disarmed", "arm autofinish on this host (bin/autofinish arm), then retry the hand-over"),
        (r"landing switch is off", "enable this host's landing switch, then retry the hand-over"),
        (r"^open for\b|no settled answer|more than its landing question|\bstops for\b",
         "answer the named non-landing question and resume the build"),
        (r"origin does not hold|origin could not vouch|uncommitted changes", "commit and publish this build's tip to origin, then retry the hand-over"),
        (r"\bbudget\b|\bweek\b|\baccount\b|\blogin\b", "provide a login with budget, then retry the hand-over"),
        (r"\breview\b|⚠|its own work|ended with|not idle|API error|half done|closing line|completed build",
         "resume the build, finish its work and review, and commit the result"),
    )
    for pattern, action in checks:
        if re.search(pattern, head, re.I):
            return action
    return "repair the named refusal, then retry the hand-over on this branch"
