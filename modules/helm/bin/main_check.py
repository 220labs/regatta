"""Main's scheduled check: one persistent finding per repository, read by ask poll.

Only the laptop's ordinary poll acts. The board reads the cache, never GitHub. A red
stays visible through API outages and failed issue writes; only a successful scheduled
run clears it. An issue's destination is pinned from before its POST until it is closed, or
until a lookup finds it was never filed, so a changed helm/logbook-repo is honoured then. Issue
writes are single shots per run (WRITE_TRIES); the card stays when they stop.

Not ask.issue_open/issue_state: the first leads the body with the owner's mention (a nightly red
is a bug and mentions nobody) and both write to the logbook as configured now, not to the pinned
destination a lost reply needs.
"""
import fcntl
import json
import os
import re
import subprocess
import time
from pathlib import Path

import helmlib


def cache_path():
    return Path(os.environ.get("ASK_CACHE_DIR") or Path.home() / "Library/Caches/ask") / "main-check.json"


def read():
    try:
        data = json.loads(cache_path().read_text())
    except FileNotFoundError:
        return {}
    if not isinstance(data, dict) or any(not isinstance(v, dict) for v in data.values()):
        raise ValueError("main-check cache is not a repository table")
    for row in data.values():
        if any(not isinstance(row.get(k), str) for k in ("repo", "url", "conclusion")) or \
                any(not isinstance(row.get(k), int) for k in ("run_number", "run_attempt")) or \
                any(not isinstance(row.get(k, []), list) or any(not isinstance(x, str) for x in row.get(k, []))
                    for k in ("failed", "unfinished")) or \
                (row.get("issue") and (not isinstance(row["issue"], int) or not isinstance(row.get("issue_repo"), str))) or \
                not isinstance(row.get("write_tries", 0), int):
            raise ValueError("main-check cache has an unreadable repository row")
    return data


def write(data):
    p = cache_path()
    tmp = p.with_name(p.name + ".%d.tmp" % os.getpid())
    tmp.write_text(json.dumps(data, ensure_ascii=False, indent=1))
    tmp.replace(p)


def safe(repo):
    """The guard as this pass read it: poll() and cards() read the roots fresh once at their start
    (fresh_guard), and every repository and call is judged against that read. A fresh read per call
    would clear keel's process-wide cache under the board's other card builders mid-render."""
    if not repo:
        return False
    try:
        return not (helmlib.guard_unread() or helmlib.guarded(repo)
                    or helmlib._common().registry_unreadable())
    except Exception:
        return False


def fresh_guard():
    try:
        helmlib.guard_unread(fresh=True)
    except Exception:
        pass


def read_source(repo):
    """(slug, sure): the slug, or None with sure True when the repository plainly is not one to read
    (no check.yml, no schedule, no origin, an origin off GitHub) and False when it could not be told
    (a guard, a read that failed, a git that timed out). Only a sure None lets its row expire."""
    if not safe(repo):
        return None, False
    try:
        text = (Path(repo) / ".github/workflows/check.yml").read_text()
    except FileNotFoundError:
        return None, True
    except (OSError, ValueError):   # a check.yml that is no UTF-8 is that repository's, never the pass's
        return None, False
    # any indentation, and the flow forms (`on: [push, schedule]`, `on: {schedule: …}`): a miss here
    # is a sure "not scheduled", which lets a red's issue close
    if not (re.search(r"^\s+schedule\s*:", text, re.M)
            or re.search(r"^[\"']?on[\"']?\s*:.*\bschedule\b", text, re.M)):
        return None, True
    try:
        r = subprocess.run(["git", "-C", str(repo), "remote", "get-url", "origin"],
                           capture_output=True, text=True, timeout=5)
    except (OSError, subprocess.TimeoutExpired):
        return None, False
    if r.returncode == 2:
        return None, True   # no such remote: git exits 2 for that alone (since 2.30)
    if r.returncode:
        return None, False  # 128: any other git failure (a bad config line, dubious ownership) is unsure
    try:
        return helmlib._common().repo_slug(r.stdout.strip()) or None, True
    except Exception:
        return None, False


def order(run):
    return int(run.get("run_number") or 0), int(run.get("run_attempt") or 1)


def results(jobs):
    failed, unfinished = [], []
    for job in jobs:
        if job.get("conclusion") == "skipped":
            continue  # skipped by its own `if:` (the shares' plan, suite, gather on a runner's night): never meant to run
        steps = [s for s in job.get("steps", []) if str(s.get("name", "")).startswith("nightly ")]
        # Every nightly step skipped: their `if:` kept them off (a repo with no runner variable runs its
        # line in the shares' jobs), or a setup step failed, which is named below. Either way they say
        # nothing about the suites. A step skipped after others ran is a cut, and counts.
        suites = [] if steps and all(s.get("conclusion") == "skipped" for s in steps) else steps
        for step in suites:
            name = step["name"][8:]
            c = step.get("conclusion")
            if c in ("failure", "timed_out"):
                failed.append(name)
            elif c != "success":
                unfinished.append(name)
        if job.get("conclusion") != "success":
            # Also covers setup failures and runs made before the nightly steps landed.
            setup = [s for s in job.get("steps", []) if s not in steps
                     and s.get("conclusion") in ("failure", "timed_out")]
            failed += ["%s / %s" % (job.get("name", "check"), s["name"]) for s in setup]
            if not suites and not setup:
                unfinished.append(job.get("name", "check"))
    return sorted(set(failed)), sorted(set(unfinished))


def body(slug, row):
    lines = ["<!-- helm:main-red:%s -->" % slug,
             "Main's scheduled whole-line check: %s" % row["conclusion"], row["url"]]
    lines += ["Failed: %s" % ", ".join(row["failed"])] if row.get("failed") else []
    lines += ["Cut or not run: %s" % ", ".join(row["unfinished"])] if row.get("unfinished") else []
    if row.get("results_unread"):
        lines.append("Suite results unread; the run is red. The next poll retries the read.")
    return "\n\n".join(lines)


class NoAnswer(ValueError):
    """GitHub never answered (no token, no network): every later repository would wait the same timeout."""


class Gone(ValueError):
    """The issue answered 301, 404 or 410: deleted or transferred, so its identity is dropped."""


GONE_RE = re.compile(r"\bHTTP (301|404|410)\b")
HTTP_RE = re.compile(r"\bHTTP \d{3}\b")
# An issue write is single-shot: tried, then retried once at the next poll, never in a loop (the
# engineering rule). Past this many failures in a row on one run the reader stops writing until the
# next run, and the card says so.
WRITE_TRIES = 2


def visited(repos):
    out = set()
    for r in repos:
        try:
            out.add(str(Path(r).resolve()))
        except OSError:
            pass
    return out


def poll(repos, ask, deadline=None):
    """Called before the expensive scans in the normal laptop poll, never a session.

    The lock covers the issue write and cache commit. A marker lookup recovers an issue
    whose POST succeeded but whose reply (or local commit) was lost.
    """
    if any(os.environ.get(k) for k in ("CLAUDE_CODE_SESSION_ID", "CLAUDE_UNATTENDED",
                                      "REGATTA_UNATTENDED", "CLAUDE_CODE_DISABLE_BACKGROUND_TASKS")):
        return []
    try:
        # the core's own list (AUTOFINISH_CALLER_UNATTENDED too): a fixed list goes stale
        if helmlib._common().unattended_caller():
            return []
    except Exception:
        return []   # no core to ask: never file from a caller that cannot be told
    p = cache_path()
    p.parent.mkdir(parents=True, exist_ok=True)
    notes = []
    with p.with_suffix(".lock").open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return ["main check: another poll is reading it"]
        data = read()  # a torn cache refuses the pass; never overwrite issue identity
        fresh_guard()
        seen = set()
        answered = {}  # resolved path -> its slug this pass; "" when surely not one to read, None when unread
        whole = True   # every repository was asked: only then may a row of one the poll left expire
        for repo in repos:
            if deadline and deadline - time.time() < 60:
                notes.append("main check: the poll's deadline is near")
                whole = False
                break
            slug, sure = read_source(repo)
            try:
                path = str(Path(repo).resolve())
                answered[path] = slug or ("" if sure else None)
            except OSError:
                path = None
            if not slug or slug in seen:
                continue
            seen.add(slug)
            if slug not in data and path:
                # the same checkout under a new slug (a rename, a transfer, `remote set-url`): its row
                # and open issue carry over, and the next write gives the issue the new marker
                old = next((k for k, r in data.items() if k not in seen and r.get("repo") == path), None)
                if old:
                    data[slug] = data.pop(old)
                    # run numbers are per workflow: the new slug may be another repository whose
                    # runs count from 1, so the carried row never shadows them (a rename re-reads once)
                    data[slug].update(run_number=0, run_attempt=0)
            row = data.get(slug, {})
            api = caller(repo, ask, deadline)
            try:
                read_run(slug, repo, row, data, api, ask, notes)
            except NoAnswer as e:
                fault(row, e, repo, notes)
                notes.append("main check: GitHub did not answer; the rest wait for the next poll")
                whole = False
                write(data)
                break
            except (ValueError, KeyError, TypeError, AttributeError, OSError) as e:
                fault(row, e, repo, notes)
            if slug not in data and row.get("fault") and path:
                # a repository whose reads keep failing (a token without Actions read) is kept, so
                # its fault can card once it is old: a reader that cannot read must not look green
                row.update(repo=path, url="", conclusion="unread", run_number=0, run_attempt=0, red=False)
                data[slug] = row
            write(data)
        if whole and repos and not unreadable():
            expire(data, seen, visited(repos), answered, ask, deadline, notes)
            write(data)
    return notes


def unreadable():
    try:
        return bool(helmlib.guard_unread() or helmlib._common().registry_unreadable())
    except Exception:
        return True


# A fault older than this cards on its own: a nightly runs once a day, so a day and a bit of
# failed reads means the next red would go unseen.
FAULT_CARD_AFTER = 26 * 3600


def fault(row, e, repo, notes):
    row["fault"] = str(e)[:160]
    row.setdefault("fault_since", int(time.time()))
    notes.append("main check: %s — %s" % (Path(repo).name, str(e)[:160]))


def caller(repo, ask, deadline):
    def api(method, path, payload=None, gone=False):
        if not safe(repo):
            raise ValueError("repository guard unread or held")
        if deadline and deadline - time.time() < 35:
            raise ValueError("the poll's deadline is near")
        status, result, why = ask.gh_api(method, path, payload)
        err = None
        if gone and (status in (301, 404, 410) or GONE_RE.search(why or "")):
            err = Gone(why or "HTTP %d" % status)
        elif not status and not HTTP_RE.search(why or ""):
            err = NoAnswer(why or "GitHub did not answer")
        elif why or not 200 <= status < 300:
            err = ValueError(why or "GitHub did not answer")
        if err:
            # a POST or PATCH that was sent: one of the run's single shots, spent whatever the reply
            err.write = method != "GET"
            raise err
        return result
    return api


def read_run(slug, repo, row, data, api, ask, notes):
    runs = api("GET", "/repos/%s/actions/workflows/check.yml/runs?branch=main&event=schedule&status=completed&per_page=10" % slug)
    row.pop("fault", None)   # GitHub answered: an earlier pass's fault is history (a later one sets its own)
    row.pop("fault_since", None)
    runs = [r for r in runs["workflow_runs"] if r.get("event") == "schedule"
            and r.get("head_branch") == "main" and r.get("status") == "completed"]
    if not runs:
        return
    run = max(runs, key=order)
    if row and order(run) < order(row):
        return
    conclusion = run.get("conclusion")
    if conclusion not in ("success", "failure", "timed_out", "cancelled", "startup_failure", "action_required", "stale"):
        return  # unknown, neutral or skipped is no green
    changed = order(run) != order(row) or conclusion != row.get("conclusion")
    lookup = not row.get("issue") and (row.get("red") or row.get("lookup_issue"))
    row.update(repo=str(Path(repo).resolve()), run_number=run["run_number"],
               run_attempt=run.get("run_attempt", 1), conclusion=conclusion,
               url=run["html_url"], red=conclusion != "success", lookup_issue=bool(lookup))
    row.pop("expired", None)   # read again: the repository is back in the poll
    if changed:
        row.pop("write_tries", None)   # a new run is a new single shot
    if row["red"] and not row.get("issue"):
        row["lookup_issue"] = True
    data[slug] = row
    if row["red"] and (changed or row.get("results_unread")):
        row.update(failed=[], unfinished=[], results_unread=True)
        write(data)  # the board has the red even if the jobs API does not answer
        try:
            jobs = []
            for page in range(1, 11):
                res = api("GET", "/repos/%s/actions/runs/%s/attempts/%s/jobs?per_page=100&page=%s" %
                          (slug, run["id"], row["run_attempt"], page))
                batch = res["jobs"]
                jobs += batch
                if len(batch) < 100:
                    break
            else:
                raise ValueError("too many jobs to read")
            # a run that never started a job (startup_failure, action_required) is read: nothing ran
            row["failed"], row["unfinished"] = results(jobs) if jobs else ([], ["check"])
            row["results_unread"] = False
        except NoAnswer:
            raise
        except (ValueError, KeyError, TypeError):
            notes.append("main check: %s — suite results unread" % Path(repo).name)
    write(data)
    if row.get("write_tries", 0) >= WRITE_TRIES:
        row["fault"] = "the issue write failed %d times on this run; the next run tries again" % row["write_tries"]
        return
    try:
        for attempt in (1, 2):
            try:
                deliver(slug, row, data, api, ask)
                break
            except Gone as e:
                # deleted or transferred: forget it and look again (a red files a new one), once
                for k in ("issue", "issue_body", "issue_repo", "issue_url"):
                    row.pop(k, None)
                row["lookup_issue"] = row["red"]
                write(data)
                if attempt == 2:
                    again = ValueError("the issue is gone again: %s" % e)
                    again.write = True
                    raise again
    except (ValueError, KeyError, TypeError, AttributeError, OSError) as e:
        if getattr(e, "write", False):
            row["write_tries"] = row.get("write_tries", 0) + 1
        elif isinstance(e, AttributeError):
            # a reply of the wrong shape came after a write was sent: it spends a try, never a loop
            row["write_tries"] = row.get("write_tries", 0) + 1
        raise
    row.pop("write_tries", None)
    row.pop("fault", None)


def deliver(slug, row, data, api, ask):
    """The issue's lifecycle: found or filed on a red, its body kept, closed on a green."""
    if row.get("lookup_issue"):
        pinned = row.get("issue_repo")
        if not row["red"] and not pinned:
            # Nothing was ever posted: every POST pins its destination first. A green with none
            # pinned (a logbook unset or malformed while red) has no issue to close.
            row["lookup_issue"] = False
        else:
            issue = None
            if pinned:
                # a POST went here and its reply may be lost: look there first
                try:
                    issue = find(slug, pinned, api, gone=True)
                except Gone:
                    issue = None   # the destination answers 404 or 410 (a typo, no access): nothing was filed
                if not issue:
                    # nothing there: the pin protected no POST, so a changed logbook is honoured
                    row.pop("issue_repo", None)
                    write(data)
            dest = pinned
            if not issue and row["red"]:
                dest = logbook(ask)
                if dest != pinned:
                    issue = find(slug, dest, api)
                if not issue:
                    row["issue_repo"] = dest  # pinned right before the POST, for a lost reply
                    write(data)
                    issue = api("POST", "/repos/%s/issues" % dest,
                                {"title": "main check red: %s" % slug, "body": body(slug, row), "labels": ["bug"]})
            if issue:
                if not isinstance(issue, dict) or not isinstance(issue.get("number"), int):
                    bad = ValueError("issue reply named no number")
                    bad.write = True   # a POST's reply may be this: the shot is spent, never re-sent each poll
                    raise bad
                row.update(issue=issue["number"], issue_repo=dest)
                remember(row, issue)
                row.setdefault("issue_body", issue.get("body") or "")
            row["lookup_issue"] = False
            write(data)
    if row["red"]:
        text = body(slug, row)
        if row.get("issue_body") != text:
            # state open too: a red night reopens an issue someone closed by hand
            reply = api("PATCH", "/repos/%s/issues/%s" % (row["issue_repo"], row["issue"]), {"body": text, "state": "open"}, gone=True)
            row["issue_body"] = text
            remember(row, reply)
    elif row.get("issue"):
        close(row, "Recovered: " + row["url"], api)


def remember(row, issue):
    """The issue's link as GitHub gives it (canonical case, a moved repo's new name): read back, never built."""
    url = issue.get("html_url") if isinstance(issue, dict) else None
    if isinstance(url, str) and url.startswith("https://"):
        row["issue_url"] = url


def close(row, line, api):
    api("PATCH", "/repos/%s/issues/%s" % (row["issue_repo"], row["issue"]),
        {"state": "closed", "body": row.get("issue_body", "") + "\n\n" + line}, gone=True)
    for k in ("issue", "issue_body", "issue_repo", "issue_url"):
        row.pop(k, None)


def logbook(ask):
    dest, why = ask.logbook()
    if not dest:
        raise ValueError(why)
    return dest


def find(slug, dest, api, gone=False):
    marker = "<!-- helm:main-red:%s -->" % slug
    found = None
    for page in range(1, 11):
        issues = api("GET", "/repos/%s/issues?state=open&labels=bug&per_page=100&page=%s" % (dest, page), gone=gone)
        if not isinstance(issues, list) or any(not isinstance(i, dict) for i in issues):
            raise ValueError("issue list reply is not a list of issues")
        found = next((i for i in issues if marker in (i.get("body") or "") and not i.get("pull_request")), None)
        if found or len(issues) < 100:
            return found
    raise ValueError("too many issues to find the nightly marker")


def expire(data, seen, paths, answered, ask, deadline, notes):
    """A row of a repository the poll no longer reads: its issue closed, then the row dropped. A
    repository still visited but held by a guard keeps its row (the cards hide it meanwhile)."""
    for slug, row in list(data.items()):
        repo = row.get("repo")
        if slug in seen:
            continue
        if repo in paths and answered.get(repo) is None:
            # still in the list and its answer unread: a guard, a failed read or a git that timed out
            # is no reason to close a red's issue. A sure answer (no schedule, no origin, another slug
            # whose row this one did not become) means it left.
            continue
        name = Path(repo or slug).name
        dest = row.get("issue_repo")
        if dest:
            what = row.get("issue_url") or ("https://github.com/%s/issues/%s" % (dest, row["issue"]) if row.get("issue")
                                            else "the open issue marked helm:main-red:%s in %s" % (slug, dest))
            if not safe(repo) or row.get("write_tries", 0) >= WRITE_TRIES:
                notes.append("main check: %s left the poll; %s is left open" % (name, what))
            else:
                try:
                    api = caller(repo, ask, deadline)
                    if not row.get("issue"):
                        # a pin alone: a POST whose reply was lost may have filed it
                        found = find(slug, dest, api, gone=True)
                        if found:
                            row.update(issue=found["number"], issue_body=found.get("body") or "")
                            remember(row, found)
                    if row.get("issue"):
                        close(row, "No longer read: %s left helm's poll." % name, api)
                except Gone:
                    pass
                except (ValueError, KeyError, TypeError, AttributeError, OSError) as e:
                    if getattr(e, "write", False):
                        row["write_tries"] = row.get("write_tries", 0) + 1
                    row["expired"] = True
                    fault(row, e, repo or slug, notes)
                    continue
        notes.append("main check: %s left the poll; its row is dropped" % name)
        del data[slug]


def cards():
    """One Decide card per red repo, or green whose issue could not yet be closed."""
    try:
        data = read()
    except (OSError, ValueError) as e:
        # a torn cache is one card, never nothing: the poll refuses to write over it, so it stays
        # torn until someone looks (a red that hid here would read as a green board)
        return [{"kind": "main-red", "key": "main-red:cache", "column": helmlib.columns()[0],
                 "title": "main check: cache unreadable", "repo": "helm", "url": "",
                 "rule": "%s: %s" % (cache_path(), str(e)[:120])}]
    out = []
    fresh_guard()
    now = time.time()
    for slug, row in data.items():
        stale = bool(row.get("fault")) and now - int(row.get("fault_since") or now) > FAULT_CARD_AFTER
        if not (row.get("red") or row.get("issue") or row.get("lookup_issue") or stale) or not safe(row.get("repo")):
            continue
        detail = ", ".join(row.get("failed", []) + row.get("unfinished", [])) or row.get("conclusion", "unread")
        if not (row.get("red") or row.get("issue") or row.get("lookup_issue")):
            detail = "unread for over a day: " + row["fault"][:80]
        elif row.get("expired"):
            detail = "no longer read; issue still open"
        elif not row.get("red"):
            detail = "recovered; issue still open"
        out.append({"kind": "main-red", "key": "main-red:" + slug, "column": helmlib.columns()[0],
                    "title": "main check: " + detail, "repo": Path(row["repo"]).name, "url": row["url"],
                    "rule": row.get("fault") or "main's scheduled whole-line check", "github":
                    row.get("issue_url") or "https://github.com/%s/issues/%s" % (row.get("issue_repo"), row["issue"]) if row.get("issue") else ""})
    return out
