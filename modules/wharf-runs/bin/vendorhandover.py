"""Vendor evidence carried by a finish entry, imported by its claiming owner.

The queue transports data only. No path supplied by the builder is a write
destination, and importing evidence never grants review credit by itself.
"""
import fcntl
import importlib.machinery
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
# the hand-over's queue put: `fresh` alone may wait 45 s on the hosts clone's lock and 30 s on its fetch
ENQUEUE_TIMEOUT = 300
MAX_BYTES = 2 * 1024 * 1024
FINISH_ONLY_RE = re.compile(r"(?mi)^[ \t*>_-]*review[*_]*:[*_ \t]*finish only")


def review_tool():
    return importlib.machinery.SourceFileLoader("handover_review", str(HERE / "build-review")).load_module()


def _brief_finish_only(wt, run, branch, tip):
    if not re.fullmatch(r"[0-9a-f]{40}", str(tip or "")):
        return False
    rel = run.get("brief") if isinstance(run, dict) else None
    if isinstance(rel, str) and rel:
        p = Path(rel)
        if p.is_absolute() or ".." in p.parts:
            return False
        targets = [p.as_posix()]
    else:
        topic = str((run.get("topic") if isinstance(run, dict) else None)
                    or re.sub(r"^[0-9]{4}-[0-9]{2}-[0-9]{2}-", "", str(branch or "").rsplit("/", 1)[-1]))
        if not topic:
            return False
        ls = subprocess.run(["git", "-C", str(wt), "ls-tree", "-r", "--name-only", str(tip), "--", "docs/handoff"],
                            capture_output=True, text=True)
        if ls.returncode != 0:
            return False
        pat = re.compile(r"(?:[0-9]{4}-[0-9]{2}-[0-9]{2}-)?%s\.md" % re.escape(topic))
        found = sorted(line for line in ls.stdout.splitlines() if pat.fullmatch(Path(line).name))
        if not found:
            return False
        targets = [found[-1]]
    r = subprocess.run(["git", "-C", str(wt), "show", "%s:%s" % (tip, targets[0])], capture_output=True, text=True)
    return r.returncode == 0 and bool(FINISH_ONLY_RE.search(r.stdout))


def collect(wt, run):
    br = review_tool()
    rec_path, _, repo_root = br.where(wt)
    project = Path(repo_root).name
    review = br.load(rec_path)
    gates = [r for r in br.jsonl(Path(os.environ.get("REVIEW_GATE_LOG") or br.log_path().parent / "review-gate.jsonl"))
             if r.get("branch") == run["branch"] and r.get("project") == project
             and r.get("phase", "finish") == "build" and (br.epoch(r.get("ts")) or 0) >= run["started"]]
    if (run.get("review_mode") == "finish_only" or (review is None and not gates)) and _brief_finish_only(
            wt, run, run.get("branch"), run.get("tip")):
        run = dict(run, review_mode="finish_only")
        review, gates = None, []
    data = {"run": run, "review": review, "gates": gates}
    why = bad(data, run["branch"], run["tip"], project, wt=wt)
    if why:
        raise ValueError(why)
    return data


def bad(data, branch, tip, project=None, wt=None):
    if not isinstance(data, dict) or len(json.dumps(data).encode()) > MAX_BYTES:
        return "vendor evidence is not an object within the size cap"
    run, review, gates = data.get("run"), data.get("review"), data.get("gates")
    finish_only = (
        isinstance(run, dict) and review is None and gates == []
        and (run.get("review_mode") == "finish_only"
             or (wt is not None and run.get("review_mode") is None and _brief_finish_only(wt, run, branch, tip)))
    )
    if not finish_only and (not isinstance(run, dict) or not isinstance(review, dict) or not isinstance(gates, list)):
        return "vendor evidence lacks its run, review or gate rows"
    rows = (run,) if finish_only else (run, review)
    if any(type(r.get("ended")) not in (int, float) or r["ended"] <= 0 for r in rows):
        return "vendor evidence has no numeric end times"
    run_proj = Path(str(run.get("repo") or "")).name
    if (run.get("mode") != "vendor" or run.get("agent") not in ("antigravity", "codex")
            or not run.get("session") or not run.get("ended") or run.get("outcome") != "clean"
            or run.get("branch") != branch or run.get("tip") != tip
            or not run_proj or (project and run_proj != project)):
        return "vendor run does not match the finish's clean tip"
    if finish_only:
        if wt is not None and not _brief_finish_only(wt, run, branch, tip):
            return "vendor finish_only run has no Review: finish only brief at its tip"
        return None
    if not isinstance(review.get("rounds"), list) or not review["rounds"] or any(
            not isinstance(r, dict) for r in review["rounds"]):
        return "vendor evidence has no review rounds"
    expected_proj = project or run_proj
    if (review.get("session") != run["session"] or review.get("branch") != branch
            or review.get("tip") != tip or not review.get("ended") or review.get("outcome") != "clean"
            or review.get("agent") != run["agent"] or review.get("phase", "build") != "build"
            or not review.get("project") or review.get("project") != expected_proj):
        return "vendor review does not match its build"
    br = review_tool()
    if not gates or any(not isinstance(r, dict) or r.get("branch") != branch
                        or r.get("project") != expected_proj or r.get("phase") != "build"
                        or not re.fullmatch(r"[0-9a-f]{40}", str(r.get("head") or ""))
                        or br.epoch(r.get("ts")) is None for r in gates):
        return "vendor gate rows do not match their build"
    return None


def append_once(path, rows):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a+", encoding="utf-8") as f:
        fcntl.flock(f, fcntl.LOCK_EX)
        f.seek(0)
        seen = set(f.read().splitlines())
        for row in rows:
            line = json.dumps(row, sort_keys=True)
            if line not in seen:
                f.write(line + "\n")
                seen.add(line)


def receive(data, wt, branch, tip):
    br = review_tool()
    project = Path(br.where(wt)[2]).name
    why = bad(data, branch, tip, project, wt=wt)
    if why:
        raise ValueError(why)
    folder = br.log_path().parent
    # Keep the source host's paths and findings for comparison; covers falls
    # back to the durable log in this new worktree, never overwrites its loop.
    append_once(folder / "vendor-builds.jsonl", [data["run"]])
    if data.get("review") is not None:
        append_once(br.log_path(), [data["review"]])
    if data.get("gates"):
        append_once(Path(os.environ.get("REVIEW_GATE_LOG") or folder / "review-gate.jsonl"), data["gates"])


def handover(wt, record):
    """Called after dispatch ends the build claim. No Claude budget or ladder
    is read on a builder user; the owner's claimed finish judges its ladder.
    """
    import handover as ho
    import vendorlib as v
    try:
        run = json.loads(Path(record).read_text())
    except (OSError, ValueError) as ex:
        print("== vendor hand-over declined: run record does not read (%s)" % ex)
        return
    if run.get("outcome") != "clean" or run.get("next_scheduled"):
        return
    if str(run.get("launch") or "").startswith(("queued", "declined:", "no launch")):
        return
    if run.get("ending"):
        ending = str(run["ending"]).replace("\r", "").replace("\n", "; ")
        why = ("it was requeued (dispatch --requeue): the session that continues it lands it"
               if re.match(r"^requeued\b", ending) else "it ended (%s)" % ending)
        action = ho.next_action(why) or "run /finish on this branch"
        run["launch"] = "no launch — %s; to land: %s" % (why, action)
        v.save(record, run)
        print("== vendor hand-over: " + run["launch"])
        return
    mode = run.get("dispatch_mode")
    if mode is None:
        mode = "unreadable" if run.get("mode_unread") else (
            os.environ.get("DISPATCH_MODE") or run.get("task_mode") or "default")
    if mode == "ask":
        run["launch"] = "no launch — no hand-over: the mode is ask, the owner lands it; to land: run /finish on this branch"
        v.save(record, run)
        print("== vendor hand-over: " + run["launch"])
        return
    if mode not in ("default", "yolo", "dnd"):
        run["launch"] = "declined: the mode was %s at start; to land: run /finish on this branch" % (mode or "unreadable")
        v.save(record, run)
        print("== vendor hand-over: " + run["launch"])
        return
    text = run.get("last_answer") or ""
    end = v.common.ending(text)
    if end[0] != "handed" and "\u26a0" not in text:
        run["launch"] = "no launch — no hand-over: its last reply did not end on the hand-over line; to land: run /finish on this branch"
        v.save(record, run)
        print("== vendor hand-over: " + run["launch"])
        return
    payload = None
    try:
        v.fence(wt, run["agent"], paths=True)
        base = "origin/" + v.main_name(wt)
        facts = ho.facts(wt, run["branch"], base, session=run.get("session"))
        waived_rows, unwaived = [], []
        for row in facts.get("owed", []):
            (waived_rows if ho.waivable(row, lambda r: end[0] == "handed", facts.get("wip", ())) else unwaived).append(row)
        hold = ho.judge(text, dict(facts, owed=unwaived), v.common.ending)
        if hold:
            action = ho.next_action(hold) or "repair the named refusal, then retry the hand-over"
            run["launch"] = "no launch — %s; to land: %s" % (hold, action)
            v.save(record, run)
            print("== vendor hand-over: " + run["launch"])
            return
        if end[0] != "handed":
            run["launch"] = "no launch — no hand-over: its last reply did not end on the hand-over line; to land: run /finish on this branch"
            v.save(record, run)
            print("== vendor hand-over: " + run["launch"])
            return
        owed = ["%s %s" % r[:2] for r in waived_rows]
        data = collect(wt, run)
        # This is evidence for the queue, never a model message. Scan it whole
        # under its own bound so reports spanning several turns still travel.
        v.fence(wt, run["agent"], text=json.dumps(data), text_limit=MAX_BYTES)
        with tempfile.NamedTemporaryFile("w", suffix=".handover", encoding="utf-8", delete=False) as tf:
            payload = Path(tf.name)
            json.dump(data, tf, indent=2)
            tf.write("\n")
        by = "handed" if mode == "default" else mode
        rule = "C" if mode == "default" else "M"
        rights = {"by": by, "rule": rule, "merge": False, "hold": False,
                  "from": (os.environ.get("DISPATCH_HOST") or v.common.host_name() or "").lower()}
        if owed:
            rights["owed"] = owed
        # No prefer, pin, vendor need or inherited job flags. The owner's
        # claim rechecks mode, keel and every /finish gate on its own row.
        p = subprocess.run([sys.executable, str(HERE / "dispatch-queue"), "enqueue", "--kind", "finish",
                            "--repo", run["repo"], "--branch", run["branch"], "--tip", run["tip"],
                            "--finish", json.dumps(rights), "--build-record", str(payload), "--cwd", str(wt)],
                           env={**os.environ, "CLAUDE_UNATTENDED": "1"}, capture_output=True, text=True,
                           timeout=ENQUEUE_TIMEOUT)
        run["launch"] = "queued: " + p.stdout.strip() if p.returncode == 0 else "declined: " + (p.stderr or p.stdout).strip()[-500:]
    except subprocess.TimeoutExpired:
        # a queue push that hangs would keep dispatch's shell, the record's watcher, alive with no launch written, and
        # helm's stall card waits on that shell (S5's landing review, round 3). The put may still have landed:
        # the owner reads the queue before a /finish
        run["launch"] = ("declined: the queue's enqueue did not answer in %d s; it may be queued — read dispatch --queue"
                         % ENQUEUE_TIMEOUT)
    except (v.Refused, OSError, ValueError) as ex:
        run["launch"] = "declined: " + str(ex)
    except Exception as ex:   # a malformed record (no tip, a bad fact) still writes why, never a bare traceback
        run["launch"] = "declined: %s: %s" % (type(ex).__name__, ex)
    finally:
        if payload is not None:
            payload.unlink(missing_ok=True)
    v.save(record, run)
    print("== vendor hand-over: " + run["launch"])
