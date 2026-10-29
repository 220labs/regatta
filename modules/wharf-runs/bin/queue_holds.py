"""queue_holds — does dispatch's queue hold a branch's next step: the one reader autofinish's `queue_hold`,
helm's stalls (`poll_queue`) and sextant's soundings (`in_dispatch_queue`) share (dispatch-queue S4, carried
from S3's third landing review, item 7: three lookups with three timeouts, and soundings' one `has` per entry).

    h = queue_holds.Holds(<dispatch-queue or a stand-in>)
    h.why(repo, branch, here=None)   # why the queue holds it, or None

One `dispatch-queue list --all --json` per Holds, read at the first question (most passes ask none) and
kept: a hung home costs one TIMEOUT, not one per branch. REPO is a path, or a name as stalls keeps one; an
entry is the branch's by its branch and its repo as the entry names it (dispatch-queue's repo_word: relative
to the projects folder, else absolute), since branch names repeat across repos by design (AGENTS.md). HERE,
this host's name: a `running` entry on it is the branch's own run, not a next step (autofinish's rule).

The readers' rule: a queue that does not answer holds every branch ("has an entry"). Since S4 a torn
node-local store holds only the branches whose keys it names (the list's `bad_stores`: its file names, read
when a file is not) — one torn local store held every branch in the fleet before (S3's in-round review 1).
By key, not by the repo's scope: route() also puts an open repo dispatched from a confidential checkout
there, and a registry read here could name a scope first that route() did not (the landing review). The
fleet ref, a local store that names no keys, and an answer with no `bad_stores` (an older dispatch-queue)
hold every branch, as before; `_spawn` is a local store like any (`local=_spawn`), holding by its keys. key_of
is dispatch-queue's, copied: loading that file here would start its core and registry in every reader, and a
case in test_priority.sh fails the moment the two differ. No dispatch-queue at all: nothing held. Python 3.9, stdlib only.
"""
import json
import os
import re
import subprocess
import sys
import threading
from pathlib import Path

HERE = Path(__file__).resolve().parent
TIMEOUT = 90   # list's fetch may wait 45 s for the clone's lock and 30 s for the home (S3's review, item 10)


_COMMON = []


def _common():
    """The regatta core, loaded once (None without one): its PROJECTS names a repo relative to it."""
    if not _COMMON:
        try:
            sys.path.insert(0, str(HERE.parent / "lib"))
            import core_path  # noqa: PLC0415
            core_path.add()
            import common  # noqa: PLC0415
            _COMMON.append(common)
        except Exception:
            _COMMON.append(None)
    return _COMMON[0]


def topic_of(branch):
    """dispatch-queue's topic_of and key_of, the same lines (a case in test_priority.sh compares them)."""
    return re.sub(r"^[0-9]{4}-[0-9]{2}-[0-9]{2}-", "", branch.rsplit("/", 1)[-1])


def key_of(repo, branch):
    return re.sub(r"[^A-Za-z0-9._-]", "_", "%s--%s" % (os.path.basename(str(repo).rstrip("/")), topic_of(branch)))


class Holds:
    def __init__(self, q=None, timeout=TIMEOUT):
        self.q = str(q) if q else str(HERE / "dispatch-queue")
        self.timeout = timeout
        self._lock = threading.Lock()
        self._got = None

    def read(self):
        """(entries, bad stores, why-unreadable): entries None when the queue gave no answer at all."""
        with self._lock:
            if self._got is None:
                self._got = self._read()
            return self._got

    def _read(self):
        if not Path(self.q).exists():
            return [], [], None
        try:
            r = subprocess.run([self.q, "list", "--all", "--json"], capture_output=True, text=True, timeout=self.timeout)
        except (OSError, subprocess.TimeoutExpired):
            return None, [], "dispatch's queue gave no answer"
        if r.returncode != 0:
            said = (r.stderr or r.stdout or "").strip().splitlines()[:1]
            return None, [], "dispatch's queue could not tell (exit %d%s)" % (r.returncode, ": " + said[0] if said else "")
        try:
            d = json.loads(r.stdout)
        except ValueError:
            d = None
        if not isinstance(d, dict):
            return None, [], "dispatch's queue gave no answer"
        entries = [e for e in d.get("entries") or [] if isinstance(e, dict)]
        why = "dispatch's queue does not read (%s)" % ("; ".join(map(str, d.get("why") or [])) or "unreadable")
        if not d.get("unreadable"):
            return entries, [], None
        bad = [b for b in d.get("bad_stores") or [] if isinstance(b, dict) and b.get("store")]
        return entries, bad or [{"store": "*"}], why

    def why(self, repo, branch, here=None):
        entries, bad, why = self.read()
        if entries is None:
            return "%s: a queued step counts as there" % why
        if bad and self._store_holds(repo, branch, bad):
            return "%s: a queued step counts as there" % why
        words = self._words(repo)
        name = None if "/" in str(repo) else str(repo)
        for e in entries:
            if e.get("branch") != branch:
                continue
            er = str(e.get("repo") or "")
            if er not in words and not (name and os.path.basename(er) == name):
                continue
            if here and e.get("state") == "running" and (e.get("running_on") or "").lower() == here.lower():
                continue
            return "its next step waits in dispatch's queue (%s %s)" % (e.get("qid") or "an entry", e.get("state") or "?")
        return None

    @staticmethod
    def _words(repo):
        words = {str(repo)}
        if "/" in str(repo):
            p = Path(str(repo)).resolve()
            words.add(str(p))
            c = _common()
            try:
                words.add(str(p.relative_to(c.PROJECTS.resolve())))
            except (ValueError, AttributeError):
                pass
        return words

    @staticmethod
    def _store_holds(repo, branch, bad):
        """True when BRANCH of REPO may sit in a store in BAD: any store but a node-local one naming its keys
        holds every branch; such a store holds the branches whose key it names."""
        if any(not str(b["store"]).startswith("local=") or not b.get("keys") for b in bad):
            return True
        k = key_of(repo, branch)
        return any(k in b["keys"] for b in bad)
