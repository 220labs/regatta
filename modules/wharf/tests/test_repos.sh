#!/usr/bin/env bash
# Tests for the GitHub side of bin/repos and its helpers in hooks/common.py: --github's CI and
# automerge settings (common.ci_settings) with its --apply refusals, the merge wait bin/pr merge
# and sparks share (common.merge_pr_waiting), open_pr's `hold` on a non-draft fallback and
# ready_pr taking it off, and `repos --hooks` opening its PR as a draft. GitHub is a fake
# common.api and a fake `gh` on PATH: nothing here speaks to GitHub.
#   bash modules/wharf/tests/test_repos.sh
export REGATTA_CONFIG="${REGATTA_CONFIG:-$HOME/.config/regatta}"   # before any case moves HOME: the core and the private files are found there (regatta-modules B1)
set -u
B="$(cd "$(dirname "$0")/../bin" && pwd)"   # the module's bin/: the tools under test (B6)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
# A scratch registry, never the real one (C3): its folder's name is the registry's home repo, as
# github-repo reads it from where the file really sits.
mkdir -p "$T/reg/overlay"
printf '{"machine_account": "m", "repos": {"overlay": {"github": "o/overlay"}}}\n' > "$T/reg/overlay/repos.json"
export CLAUDE_REPOS_JSON="$T/reg/overlay/repos.json"
fails=0

# ---- the Python cases: one process, a fake GitHub per case ----------------------------------------
python3 - "$B" <<'EOF' || fails=$((fails+1))
import base64, contextlib, importlib.machinery, importlib.util, io, json, sys
from pathlib import Path
B = Path(sys.argv[1])
sys.path.insert(0, str(B.parent / "lib"))
import core_path
core_path.require()
import common

fails = 0
def check(cond, label):
    global fails
    print(("  ok   " if cond else "  FAIL ") + label)
    fails += not cond

SETTINGS = json.loads((B.parent / "templates" / "code" / ".github" / "repo-settings.json").read_text())
PROT = json.loads((B.parent / "templates" / "code" / ".github" / "main-protection.json").read_text())
CHECK = (B.parent / "templates" / "code" / ".github" / "workflows" / "check.yml").read_text()  # its job is `check`
FULL = {common.CHECK_YML: CHECK, common.AUTOMERGE_YML: "on: pull_request",
        common.REPO_SETTINGS: json.dumps(SETTINGS), common.MAIN_PROTECTION: json.dumps(PROT)}
def files(**over):
    """FULL with some files replaced; None removes one."""
    f = dict(FULL)
    for k, v in over.items():
        k = {"check": common.CHECK_YML, "prot": common.MAIN_PROTECTION, "am": common.AUTOMERGE_YML}[k]
        if v is None:
            f.pop(k)
        else:
            f[k] = v
    return f


class GitHub:
    """Just enough of the REST API: a repo, its main's protection, its labels, its files."""
    def __init__(self, repo=None, prot=None, labels=("hold",), files=None, refuse=None):
        self.repo = dict({"default_branch": "main", "full_name": "o/r"}, **(repo or {}))
        self.prot, self.labels, self.files = prot, set(labels), dict(files or {})
        self.refuse = refuse or {}  # (method, path fragment) -> status
        self.calls = []

    def writes(self):
        return [(m, p) for m, p in self.calls if m != "GET"]

    def api(self, method, path, body=None, tok=None, timeout=15):
        self.calls.append((method, path))
        for (m, frag), st in self.refuse.items():
            if m == method and frag in path:
                return st, {"message": "refused"}
        bare = path.split("?")[0]
        if bare == "/repos/o/r":
            if method == "PATCH":
                self.repo.update(body)
            return 200, dict(self.repo)
        if bare.endswith("/branches/main/protection"):
            if method == "PUT":
                self.prot = {"required_status_checks": {"contexts": body["required_status_checks"]["contexts"]}}
            return (200, self.prot) if self.prot else (404, {"message": "Branch not protected"})
        if bare.startswith("/repos/o/r/labels"):
            if method == "POST":
                self.labels.add(body["name"])
                return 201, body
            return (200, {}) if bare.rsplit("/", 1)[1] in self.labels else (404, None)
        if bare.startswith("/repos/o/r/contents/"):
            f = self.files.get(bare[len("/repos/o/r/contents/"):])
            return (200, {"encoding": "base64", "content": base64.b64encode(f.encode()).decode()}) if f else (404, None)
        return 404, None


def run(gh, apply=False, knowledge=False, files=FULL):
    common.api = gh.api
    return common.ci_settings("o/r", files.get, tok="t", apply=apply, knowledge=knowledge, repo=dict(gh.repo))


ON = dict(SETTINGS)
OFF = dict(SETTINGS, allow_auto_merge=False)
GOOD = {"required_status_checks": {"contexts": ["check"]}}

print("ci_settings: read-only")
gh = GitHub(ON, GOOD)
bad, text = run(gh)
check((bad, text) == (0, "ci settings ok") and not gh.writes(), f"all three as the files say: ok, nothing written [{text}]")
gh = GitHub(OFF, None, labels=())
bad, text = run(gh)
check(bad == 4 and "DIFFER" in text and "main unprotected" in text and "no hold label" in text
      and "allow_auto_merge=False" in text and "HAZARD: main requires no check" in text and not gh.writes(),
      f"three off, and the no-check hazard: reported, nothing written [{text}]")
gh = GitHub(ON, None)
bad, text = run(gh)
check(text.startswith("ci settings HAZARD: main requires no check while automerge.yml is on main and allow_auto_merge is on")
      and not gh.writes(), f"auto-merge on while main is unprotected: its own HAZARD line, first (the home repo) [{text}]")
gh = GitHub(ON, {"required_status_checks": None})
bad, text = run(gh)
check("HAZARD" in text, f"  …and with protection that requires nothing [{text}]")
gh = GitHub(ON, {"required_status_checks": {"contexts": ["build"]}})
bad, text = run(gh)
check(bad == 1 and "main requires ['build']" in text, f"the wrong required context is off [{text}]")
gh = GitHub(ON, {"required_status_checks": {"checks": [{"context": "check", "app_id": 15368}]}})
check(run(gh) == (0, "ci settings ok"), "contexts read from `checks` too (GitHub's newer field)")
gh = GitHub(ON, GOOD, refuse={("GET", "/protection"): 403})
bad, text = run(gh)
check(bad == 1 and "protection unreadable (HTTP 403)" in text, f"a 403 is reported, not fatal [{text}]")
gh = GitHub(OFF)
check(run(gh, files={k: v for k, v in FULL.items() if k != common.AUTOMERGE_YML}) == (0, "")
      and not gh.calls, "no automerge.yml on main: nothing to say, no request")

print("ci_settings: --apply")
gh = GitHub(OFF, None, labels=())
bad, text = run(gh, apply=True)
order = [m for m, _ in gh.writes()]
check(bad == 0 and text.startswith("ci settings set:") and order == ["POST", "PUT", "PATCH"],
      f"label, then protection, then allow_auto_merge — each read back [{order}; {text}]")
check(gh.repo["allow_auto_merge"] is True and gh.prot and "hold" in gh.labels, "  and GitHub holds all three")
gh = GitHub(OFF, None, labels=())
bad, text = run(gh, apply=True, files={k: v for k, v in FULL.items() if k != common.CHECK_YML})
check(bad >= 1 and "no check.yml" in text and [m for m, _ in gh.writes()] == ["POST"],
      f"no check.yml: only the hold label, no protection, no allow_auto_merge [{text}]")
gh = GitHub(OFF, None, refuse={("PUT", "/protection"): 403})
bad, text = run(gh, apply=True)
check(bad == 3 and "protection (HTTP 403)" in text and "settings left off until protection holds" in text
      and "HAZARD" in text and ("PATCH", "/repos/o/r") not in gh.writes(), f"protection refused: allow_auto_merge stays off [{text}]")
gh = GitHub(ON, None, refuse={("PUT", "/protection"): 403})
bad, text = run(gh, apply=True)
check(gh.repo["allow_auto_merge"] is False and "allow_auto_merge turned off" in text
      and [m for m, _ in gh.writes()] == ["PUT", "PATCH"], f"  …and one already on is turned off, not left on [{text}]")
for label, over in (("unreadable", {"prot": None}), ("requiring no check", {"prot": json.dumps({"enforce_admins": False})}),
                    ("with empty contexts", {"prot": json.dumps(dict(PROT, required_status_checks={"strict": False, "contexts": []}))})):
    gh = GitHub(OFF, None)
    bad, text = run(gh, apply=True, files=files(**over))
    check(not gh.writes() and "protection and allow_auto_merge not applied" in text and gh.repo["allow_auto_merge"] is False,
          f"main-protection.json {label}: no PUT, no allow_auto_merge [{text}]")
gh = GitHub(ON, None)
bad, text = run(gh, apply=True, files=files(prot=None))
check(gh.repo["allow_auto_merge"] is False and [m for m, _ in gh.writes()] == ["PATCH"] and "HAZARD" in text,
      f"  …and with auto-merge already on and main unprotected: turned off [{text}]")

print("ci_settings: the required context must be a job in check.yml")
TIER0 = json.dumps(dict(PROT, required_status_checks={"strict": False, "contexts": ["tier0-offline"]}))
gh = GitHub(OFF, None)
bad, text = run(gh, apply=True, files=files(prot=TIER0))
check(not gh.writes() and "requires ['tier0-offline'], a name no job in check.yml has" in text,
      f"a context check.yml has no job for: refused, nothing written [{text}]")
NAMED = "name: ci\non: pull_request\njobs:\n  tier0:  # the offline lines\n    name: 'tier0-offline'\n    runs-on: ubuntu-latest\n    steps:\n      - name: not-a-job\n"
gh = GitHub(OFF, None)
bad, text = run(gh, apply=True, files=files(prot=TIER0, check=NAMED))
check(bad == 0 and [m for m, _ in gh.writes()] == ["PUT", "PATCH"], f"  a job's `name:` is a context [{text}]")
gh = GitHub(OFF, None)
run(gh, apply=True, files=files(prot=json.dumps(dict(PROT, required_status_checks={"contexts": ["tier0"]})), check=NAMED))
check(not gh.writes(), "  but not its key: GitHub reports a named job under its name only")
COMMENTED = "on: pull_request\njobs:\n  first:\n    runs-on: ubuntu-latest\n# a column-0 comment inside jobs:\n  later:\n    runs-on: ubuntu-latest\n"
gh = GitHub(OFF, None)
run(gh, apply=True, files=files(prot=json.dumps(dict(PROT, required_status_checks={"contexts": ["later"]})), check=COMMENTED))
check([m for m, _ in gh.writes()] == ["PUT", "PATCH"], "  a job after a column-0 comment is still a job")
gh = GitHub(OFF, None)
bad, text = run(gh, apply=True, files=files(prot=json.dumps(dict(PROT, required_status_checks={"contexts": ["not-a-job"]})), check=NAMED))
check(not gh.writes(), f"  a step's `name:` is not [{text}]")
gh = GitHub(OFF, None)
run(gh, apply=True, files=files(prot=json.dumps(dict(PROT, required_status_checks={"contexts": ["check (3.9)"]}))))
check([m for m, _ in gh.writes()] == ["PUT", "PATCH"], "  a matrix leg `check (3.9)` of job `check` is")
gh = GitHub({"allow_auto_merge": True}, None, labels=())
bad, text = run(gh, apply=True, knowledge=True)
check(bad == 1 and "knowledge repo" in text and "automerge.yml on main" in text and not gh.writes(),
      f"a knowledge repo with automerge: reported, nothing applied [{text}]")
gh = GitHub(OFF, None, labels=())
check(run(gh, apply=True, knowledge=True, files={common.CHECK_YML: "x"}) == (0, "") and not gh.writes(),
      "a knowledge repo with check.yml only: fine as it is (D2)")
gh = GitHub(OFF, None, files=FULL)
common.api = gh.api
read = common.contents_reader("o/r", "main", tok="t")
check(read(common.AUTOMERGE_YML) == "on: pull_request" and read(".github/none.yml") is None,
      "contents_reader: a file on GitHub's main, None when absent")

print("bin/repos --github")
loader = importlib.machinery.SourceFileLoader("repos_bin", str(B / "repos"))
spec = importlib.util.spec_from_loader("repos_bin", loader)
repos = importlib.util.module_from_spec(spec)
loader.exec_module(repos)
gh = GitHub(dict(OFF, **common.MERGE_POLICY), None, labels=(), files=FULL)
common.api, common.token = gh.api, (lambda: "t")
out = io.StringIO()
with contextlib.redirect_stdout(out):
    try:
        repos.github_settings({"r": {"github": "o/r"}, "k": {"github": "o/r", "knowledge": True}}, False)
        code = 0
    except SystemExit as e:
        code = e.code
lines = out.getvalue().splitlines()
check(code == 1 and len(lines) == 2 and "ok — rebase only, delete on merge · ci settings HAZARD" in lines[0] and "DIFFER" in lines[0]
      and "knowledge repo" in lines[1] and not gh.writes(), f"one line per repo, policy then ci; exit 1; read-only {lines}")
with contextlib.redirect_stdout(io.StringIO()):
    try:
        repos.github_settings({"k": {"github": "o/r", "knowledge": True}}, True)
    except SystemExit:
        pass
check(not gh.writes(), "--apply on a knowledge repo writes nothing")

print("bin/repos: the machine account (2026-10-07)")
M = repos.machine_account()
check(bool(M), f"repos.json names it [{M}]")
class Access:
    """GitHub's collaborator and invitation endpoints, for one repo o/x and the account M."""
    def __init__(self, perm="none", invited=False, me=None, invites=(), list_status=200):
        self.perm, self.invited, self.me, self.invites, self.list_status = perm, invited, me, list(invites), list_status
        self.calls = []
    def api(self, method, path, body=None, tok=None, timeout=15):
        self.calls.append((method, path))
        if path.endswith(f"/collaborators/{M}/permission"):
            return 200, {"permission": self.perm}
        if path == "/repos/o/x/invitations":
            return 200, [{"invitee": {"login": M}}] if self.invited else []
        if method == "PUT" and path == f"/repos/o/x/collaborators/{M}":
            return 201, {"id": 1}
        if path == "/user":
            return 200, {"login": self.me}
        if path == "/user/repository_invitations":
            return (self.list_status, self.invites) if self.list_status == 200 else (self.list_status, {"message": "rate limited"})
        if method == "PATCH" and path.startswith("/user/repository_invitations/"):
            return 204, None
        return 404, None
def writes(acc):
    return [c for c in acc.calls if c[0] != "GET"]
common.api = Access(perm="write").api
check(repos.collaborator("o/x", "t", False) == (0, ""), "push already: silent")
common.api = Access(invited=True).api
r, note = repos.collaborator("o/x", "t", False)
check(r == 0 and "invited, not yet accepted" in note, f"invited: said, not a failure [{note}]")
acc = Access(); common.api = acc.api
r, note = repos.collaborator("o/x", "t", False)
check(r == 1 and "has no push" in note and not writes(acc), "neither: a failure, nothing written")
class Expired(Access):
    def api(self, method, path, body=None, tok=None, timeout=15):
        if path == "/repos/o/x/invitations":
            return 200, [{"invitee": {"login": M}, "expired": True}]
        return Access.api(self, method, path, body, tok, timeout)
acc = Expired(); common.api = acc.api
r, note = repos.collaborator("o/x", "t", True)
check(r == 0 and ("PUT", f"/repos/o/x/collaborators/{M}") in acc.calls, f"an expired invitation counts as none: --apply invites anew [{note}]")
acc = Access(); common.api = acc.api
r, note = repos.collaborator("o/x", "t", False, knowledge=True)
check(r == 1 and "invite by hand" in note, f"a knowledge repo's report says what --apply will say [{note}]")
acc = Access(); common.api = acc.api
r, note = repos.collaborator("o/x", "t", True)
check(r == 0 and ("PUT", f"/repos/o/x/collaborators/{M}") in acc.calls, f"--apply invites it [{note}]")
acc = Access(); common.api = acc.api
r, note = repos.collaborator("o/x", "t", True, knowledge=True)
check(r == 1 and "invite by hand" in note and not writes(acc), "--apply on a knowledge repo: reported, not invited (D2)")
def accept(acc, reg, tok="t"):
    common.api, common.token = acc.api, (lambda: tok)
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        repos.accept_invitations(reg)
    return out.getvalue()
REG = {"x": {"github": "o/x"}, "y": {"github": "o/y"}}
INV = [{"id": 1, "repository": {"full_name": "o/x"}, "inviter": {"login": "o"}},
       {"id": 2, "repository": {"full_name": "o/y"}, "inviter": {"login": "someone"}},
       {"id": 3, "repository": {"full_name": "o/z"}, "inviter": {"login": "o"}}]
acc = Access(me="sam", invites=INV); out = accept(acc, REG)
check(not out and not writes(acc), "a token that is not the machine account: accepts nothing")
acc = Access(me=M, invites=INV); out = accept(acc, REG, tok=None)
check(not out and not acc.calls, "no token: no request at all")
acc = Access(me=M, invites=INV); out = accept(acc, REG)
check(writes(acc) == [("PATCH", "/user/repository_invitations/1")] and "x: " in out,
      f"the machine account: only a listed repo's invitation from its owner [{out.strip()}]")
acc = Access(me=M, list_status=403); out = accept(acc, REG)
check("unreadable (HTTP 403)" in out and not writes(acc),
      f"an error body is said, not iterated (it crashed --clone before) [{out.strip()}]")

print("merge_pr_waiting")
class PR:
    """merge answers in order; then the PR's state per poll; `runs`: the check-runs answer per read."""
    def __init__(self, merges, polls, runs=()):
        self.merges, self.polls, self.runs, self.slept, self.n = list(merges), list(polls), list(runs), [], 0
    def api(self, method, path, body=None, tok=None, timeout=15):
        if method == "PUT":
            self.n += 1
            ok = self.merges.pop(0) if self.merges else False
            return (200, {"message": "merged"}) if ok else (405, {"message": "required check is expected"})
        if "/check-runs" in path:
            return 200, {"check_runs": self.runs.pop(0) if len(self.runs) > 1 else (self.runs[0] if self.runs else [])}
        return 200, (self.polls.pop(0) if len(self.polls) > 1 else self.polls[0])
def wait(p, **kw):
    common.api = p.api
    return common.merge_pr_waiting("o/r", 7, tok="t", sleep=p.slept.append, **kw)
ARMED, BARE, MERGED = {"state": "open", "auto_merge": {"merge_method": "rebase"}}, {"state": "open"}, \
    {"state": "closed", "merged_at": "2026-10-06T10:00:00Z", "auto_merge": None}
p = PR([True], [BARE])
check(wait(p) == (True, "merged") and not p.slept, "merged at once: no wait")
p = PR([False], [ARMED, ARMED, MERGED])
ok, msg = wait(p)
check(ok and "by automerge" in msg and "required check is expected" in msg and p.slept == [10, 10] and p.n == 1,
      f"armed, then merged two polls on: launched [{msg}]")
p = PR([False, True], [BARE])
check(wait(p) == (True, "merged") and p.slept == [5] and p.n == 2, "not armed: one retry 5 s on, which merges (sparks')")
p = PR([False, False], [BARE])
ok, msg = wait(p)
check(not ok and msg == "required check is expected" and p.slept == [5],
      "no automerge, refused twice: ends after the one retry, the first refusal's message")
p = PR([False, False], [BARE, BARE, BARE, ARMED, MERGED])
ok, _ = wait(p, automerge=True)
check(ok and p.slept == [5, 10, 10, 10], f"automerge: waits for the arming, then the merge [{p.slept}]")
p = PR([False, False], [BARE])
ok, _ = wait(p, automerge=True)
check(not ok and sum(p.slept) == common.AUTOMERGE_GRACE + 5, f"automerge that never arms: gives up after the grace [{sum(p.slept)} s]")
p = PR([False], [ARMED, ARMED, BARE])
ok, _ = wait(p, automerge=True)
check(not ok and p.slept == [10, 10, 5], f"armed, then disarmed (a hold): stops waiting [{p.slept}]")
p = PR([False], [ARMED])
ok, _ = wait(p)
check(not ok and sum(p.slept) == common.AUTOMERGE_WAIT, f"armed forever: stops at the wait [{sum(p.slept)} s]")

for label, state in (("a conflict (mergeable False)", {"mergeable": False}),
                     ("a conflict (mergeable_state dirty)", {"mergeable": None, "mergeable_state": "dirty"}),
                     ("a draft", {"draft": True}), ("a `hold`", {"labels": [{"name": "hold"}]})):
    p = PR([False], [dict(BARE, **state)])
    ok, _ = wait(p, automerge=True)
    check(not ok and p.slept == [] and p.n == 1, f"not armed and {label}: ends at once, no retry, no grace [{p.slept}]")

print("merge_pr_waiting: the required check first (an admin token is not refused)")
OK_RUN, PENDING, FAILED = [{"status": "completed", "conclusion": "success"}], [{"status": "in_progress", "conclusion": None}], \
    [{"status": "completed", "conclusion": "failure"}]
SKIPPED = [{"status": "completed", "conclusion": "skipped"}]
p = PR([True], [BARE], [OK_RUN])
check(wait(p, head="abc12345", contexts=["check"]) == (True, "merged") and not p.slept and p.n == 1, "the check passed: merged at once")
p = PR([True], [BARE], [PENDING, PENDING, OK_RUN])
ok, _ = wait(p, head="abc12345", contexts=["check"])
check(ok and p.slept == [10, 10] and p.n == 1, f"the check running: polled until it passes, then merged [{p.slept}]")
p = PR([True], [BARE], [FAILED])
ok, msg = wait(p, head="abc12345", contexts=["check"])
check(not ok and "ended failure on abc12345" in msg and p.n == 0, f"the check failed: refused, nothing PUT [{msg}]")
p = PR([True], [ARMED], [PENDING])
ok, msg = wait(p, head="abc12345", contexts=["check"])
check(not ok and "still running" in msg and "(armed)" in msg and p.n == 0 and sum(p.slept) == common.AUTOMERGE_WAIT,
      f"still running at the wait: refused, says automerge lands it [{msg}]")
p = PR([True], [ARMED, MERGED], [PENDING])
ok, msg = wait(p, head="abc12345", contexts=["check"])
check(ok and "by automerge" in msg and p.n == 0, f"automerge merged it while the check was polled [{msg}]")
p = PR([True], [BARE], [SKIPPED + OK_RUN])
check(wait(p, head="abc12345", contexts=["check"])[0] and p.n == 1, "a draft's skipped run answers nothing; the run behind it does")
p = PR([True], [BARE], [SKIPPED])
ok, msg = wait(p, head="abc12345", contexts=["check"])
check(not ok and "still running" in msg and p.n == 0, "only a skipped run: pending, never a pass")
p = PR([True], [BARE], [FAILED])
check(wait(p, head="abc12345", contexts=[]) == (True, "merged") and p.n == 1, "no required context: merged as before")
check(common.check_state("o/r", "abc12345", ["check"]) == ("failure", "the required check `check` ended failure on abc12345"),
      "check_state reads the newest non-skipped run")
class Prot:
    def __init__(self, st, body): self.st, self.body = st, body
    def api(self, method, path, body=None, tok=None, timeout=15): return self.st, self.body
common.api = Prot(200, {"contexts": ["check", 3]}).api
check(common.required_contexts("o/r", "main") == ["check"], "required_contexts: the protection's string contexts")
common.api = Prot(404, {"message": "Branch not protected"}).api
check(common.required_contexts("o/r", "main") == [], "…none when the branch is not protected")

print("open_pr / ready_pr")
class Pulls:
    def __init__(self, draft_status):
        self.draft_status, self.calls, self.bodies, self.edits = draft_status, [], [], []
    def api(self, method, path, body=None, tok=None, timeout=15):
        self.calls.append((method, path))
        if path.endswith("/pulls") and method == "POST":
            self.bodies.append(body)
            if body["draft"] and self.draft_status != 201:
                return self.draft_status, {"message": "Draft pull requests are not supported"}
            return 201, {"number": 5, "draft": body["draft"], "body": body["body"], "base": {"repo": {"full_name": "o/r"}}}
        if path == "/repos/o/r/labels" and method == "POST":
            return 422, {"message": "Validation Failed", "errors": [{"code": "already_exists"}]}
        if path.endswith("/labels") and method == "POST":
            return 200, [{"name": "hold"}]
        if method == "PATCH":
            self.edits.append(body)
            return 200, {"number": 5, "body": body["body"]}
        return 200, {"data": {"markPullRequestReadyForReview": {"pullRequest": {"isDraft": False}}}}
g = Pulls(422); common.api = g.api
pr = common.open_pr("o/r", "claude/x", "main", "WIP: x", "body", tok="t")
writes = [(m, p) for m, p in g.calls if m != "GET"]
check(pr and pr.get("_held") and ("POST", "/repos/o/r/issues/5/labels") in g.calls
      and common.HOLD_NOTE in g.bodies[-1]["body"], "draft refused (422): opened ready, labelled hold, said so in the body")
check(writes.index(("POST", "/repos/o/r/labels")) < len(writes) - 2 and writes[-2] == ("POST", "/repos/o/r/pulls"),
      "  the label made first (an existing one's 422 ignored), then the PR, then the label on it")
check(common.ready_pr(pr, tok="t") and ("DELETE", "/repos/o/r/issues/5/labels/hold") in g.calls,
      "ready_pr takes open_pr's hold off")
check(len(g.edits) == 1 and common.HOLD_NOTE not in g.edits[0]["body"] and g.edits[0]["body"] == "body"
      and common.HOLD_NOTE not in pr["body"] and not pr["_held"], "  and strips HOLD_NOTE: the mark is spent")
n = len(g.calls)
check(common.ready_pr(pr, tok="t") and not any(m == "DELETE" for m, _ in g.calls[n:]),
      "  a second ready (the owner labelled it `hold` since) takes nothing off")
g = Pulls(201); common.api = g.api
pr = common.open_pr("o/r", "claude/x", "main", "WIP: x", "body", tok="t")
check(pr["draft"] and not pr.get("_held") and not any("labels" in p for _, p in g.calls), "a draft: no label")
pr = {"number": 9, "draft": False, "body": "the owner's hold, not ours", "base": {"repo": {"full_name": "o/r"}}}
check(common.ready_pr(pr, tok="t") and common.ready_pr(pr, tok="t") and not any(m in ("DELETE", "PATCH") for m, _ in g.calls),
      "a hold open_pr did not add stays, across two readies")
sys.exit(1 if fails else 0)
EOF

# ---- repos --hooks: hook_branch's PR is a draft ---------------------------------------------------
echo "repos --hooks"
git init -q --bare "$T/origin.git"
git init -q -b main "$T/r"
mkdir -p "$T/r/scripts/git-hooks" "$T/bin"
printf '#!/bin/sh\nexit 0\n' > "$T/r/scripts/git-hooks/pre-push"; chmod +x "$T/r/scripts/git-hooks/pre-push"
git -C "$T/r" add -A && git -C "$T/r" -c user.name=t -c user.email=t@t commit -q -m init
git -C "$T/r" remote add origin "$T/origin.git"
git -C "$T/r" push -q origin main
printf '#!/bin/sh\necho "$@" >> "%s/gh.args"\necho https://github.com/o/r/pull/3\n' "$T" > "$T/bin/gh"; chmod +x "$T/bin/gh"
out=$(cd "$T" && PATH="$T/bin:$PATH" GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t \
  python3 -c "
import importlib.machinery, importlib.util, sys
from pathlib import Path
l = importlib.machinery.SourceFileLoader('r', '$B/repos'); s = importlib.util.spec_from_loader('r', l)
m = importlib.util.module_from_spec(s); l.exec_module(m)
repo = Path('$T/r')
print(m.hook_branch(repo, repo / 'scripts/git-hooks/pre-push', m.TEMPLATES / 'pre-push'))")
if grep -q -- "pr create --draft" "$T/gh.args" 2>/dev/null; then echo "  ok   the PR is opened as a draft [$out]"
else echo "  FAIL hook_branch did not open a draft: [$(cat "$T/gh.args" 2>/dev/null)] [$out]"; fails=$((fails+1)); fi

# ---- github-repo: an adopted origin is read back before anything is registered (review, 2026-10-14) ----
echo "github-repo: the adopted path"
mkdir -p "$T/home/projects"
git init -q -b main "$T/home/projects/adopt"
git -C "$T/home/projects/adopt" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
git -C "$T/home/projects/adopt" remote add origin https://github.com/o/adopt.git
HOME="$T/home" python3 - "$B" "$T/home/projects/adopt" <<'EOF' || fails=$((fails+1))
import importlib.machinery, importlib.util, io, contextlib, subprocess, sys
B, repo = sys.argv[1], sys.argv[2]
l = importlib.machinery.SourceFileLoader("gr", f"{B}/github-repo"); s = importlib.util.spec_from_loader("gr", l)
gr = importlib.util.module_from_spec(s); l.exec_module(gr)
from pathlib import Path
gr.PROJECTS = Path(repo).resolve().parent   # mktemp's /var is /private/var once resolved
fails = 0
def check(ok, label):
    global fails
    print(f"  {'ok  ' if ok else 'FAIL'} {label}"); fails += not ok
def run(repo_status, main_there, invite_status=201):
    calls, registered = [], []
    def api(method, path, body=None, tok=None, timeout=15):
        calls.append((method, path))
        if path == "/user": return 200, {"login": "o"}
        if path == "/repos/o/adopt": return repo_status, ({"owner": {"login": "o"}} if repo_status == 200 else {})
        if method == "PUT": return invite_status, None
        return 404, None
    real = gr.git
    gr.git = lambda r, *a, env=None: (subprocess.CompletedProcess(a, 0, "abc\trefs/heads/main\n" if main_there else "", "")
                                      if a[:1] == ("ls-remote",) else real(r, *a, env=env))
    gr.common.api, gr.common.token, gr.machine = api, (lambda: "t"), "m"
    gr.register = lambda *a: registered.append(a)
    sys.argv = ["github-repo", repo]
    out = io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(out):
        try:
            gr.main(); code = 0
        except SystemExit as e:
            code = e.code
    gr.git = real
    return str(code), registered, calls
code, reg, _ = run(404, True)
check("does not read back" in code and not reg, f"an origin GitHub does not know: refused, not registered [{code}]")
code, reg, calls = run(200, False)
check("has no main" in code and not reg and not [c for c in calls if c[0] == "PUT"], f"no main on GitHub: refused before inviting [{code}]")
code, reg, _ = run(200, True, invite_status=403)
check("not registered" in code and not reg, f"an invitation that fails: not registered [{code}]")
code, reg, _ = run(200, True)
check(reg and reg[0][1] == "o/adopt", "read back, with main, invited: registered")
sys.exit(1 if fails else 0)
EOF

# ---- github-repo --owner: an org repo is created in the org, laptop-only, machine not invited (2026-10-18) ----
echo "github-repo: --owner ORG"
git init -q -b main "$T/home/projects/orgrepo"
git -C "$T/home/projects/orgrepo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
HOME="$T/home" python3 - "$B" "$T/home/projects/orgrepo" <<'EOF' || fails=$((fails+1))
import importlib.machinery, importlib.util, io, contextlib, sys
B, repo = sys.argv[1], sys.argv[2]
l = importlib.machinery.SourceFileLoader("gr", f"{B}/github-repo"); s = importlib.util.spec_from_loader("gr", l)
gr = importlib.util.module_from_spec(s); l.exec_module(gr)
from pathlib import Path
gr.PROJECTS = Path(repo).resolve().parent
calls = []
def api(method, path, body=None, tok=None, timeout=15):
    calls.append((method, path))
    return (200, {"login": "o"}) if path == "/user" else (404, None)
gr.common.api, gr.common.token, gr.machine = api, (lambda: "t"), "m"
sys.argv = ["github-repo", repo, "--owner", "Org", "--dry-run"]
out = io.StringIO()
with contextlib.redirect_stdout(out), contextlib.redirect_stderr(out):
    try:
        gr.main(); code = 0
    except SystemExit as e:
        code = e.code
said = out.getvalue()
ok = (code == 0 and "create private Org/orgrepo" in said and "invite" not in said
      and f"hosts: {gr.common.LAPTOP})" in said and ("GET", "/repos/Org/orgrepo") in calls)
print(f"  {'ok  ' if ok else 'FAIL'} dry run names the org, laptop-only, no invitation [{code}] {said.strip()}")
sys.exit(0 if ok else 1)
EOF


echo "repos --branches: the fence (knowledge-layers S4)"
# A made-up confidential scope `node` (repo sec) and an open `pub` (repo open), each with one idle
# claude/* branch, under a scratch HOME; no origin, so no PR lookup.
(
  export HOME="$T/fh" PJ="$T/fh/projects" CLAUDE_HOOK_NO_GITHUB=1 CLAUDE_REPOS_JSON="$T/fence.json"
  printf '{"repos": {"sec": {}, "open": {}},\n "scopes": {"node": {"file": "n", "repos": ["sec"], "confidential": true},\n  "pub": {"file": "p", "repos": ["open"]}}}\n' > "$CLAUDE_REPOS_JSON"
  for r in sec open; do
    g() { GIT_COMMITTER_DATE="2026-01-01T00:00:00" GIT_AUTHOR_DATE="2026-01-01T00:00:00" git -C "$PJ/$r" -c user.name=t -c user.email=t@t "$@"; }
    mkdir -p "$PJ/$r"; git -C "$PJ/$r" init -q -b main; g commit -q --allow-empty -m init
    g checkout -q -b "claude/h/2026-01-01-$r-PLUMTOPIC"; echo x > "$PJ/$r/f-$r.txt"; g add -A; g commit -q -m "$r work"; g checkout -q main
  done
  f=0
  ck() { if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3: expected [$2] got [$1]"; f=1; fi; }
  out=$("$B/repos" --branches)
  ck "$(echo "$out" | grep -c 'sec')" "0" "no --scope: nothing of the confidential repo is named"
  ck "$(echo "$out" | grep -c "^a confidential scope's repo — 1 idle claude/\* branches (launched 0, probably launched 0, not on main 1): counted, not listed")" "1" \
    "  one line counts its branch"
  ck "$(echo "$out" | grep -c 'open-PLUMTOPIC')" "1" "  the open repo's branch listed as before"
  out=$("$B/repos" --branches --scope node)
  ck "$(echo "$out" | grep -c 'sec-PLUMTOPIC') $(echo "$out" | grep -c 'open\|confidential')" "1 0" "--scope node: its own branch, by name, nothing else"
  out=$("$B/repos" --branches --scope pub "$PJ/sec" "$PJ/open")
  ck "$(echo "$out" | grep -c 'open-PLUMTOPIC') $(echo "$out" | grep -c 'sec\|confidential')" "1 0" "--scope pub, checkouts named: the confidential one left out, not even counted"
  out=$("$B/repos" --branches --classify "$PJ/sec")
  ck "$(echo "$out" | grep -c 'sec\|C[1-6]')" "0" "--classify: a confidential checkout named on the line is still one counted line"
  "$B/repos" --branches --scope nope > /dev/null 2> "$T/fence.err"
  ck "$? $(cat "$T/fence.err")" "1 repos: no scope 'nope' in the registry" "an unknown scope: refused, one line"
  exit $f
) || fails=$((fails+1))

[ "$fails" -eq 0 ] && echo "test_repos: all passed" || { echo "test_repos: $fails failed"; exit 1; }
