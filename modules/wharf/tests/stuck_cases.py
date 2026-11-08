"""Offline cases for stuck-ships S4. Run through test_stuck.sh for an isolated environment."""
import contextlib
import copy
import datetime
import importlib.machinery
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
from urllib.parse import parse_qs, urlsplit

M = Path(__file__).resolve().parents[1]
loader = importlib.machinery.SourceFileLoader("pr_stuck_cases", str(M / "libexec" / "pr"))
spec = importlib.util.spec_from_loader(loader.name, loader)
pr = importlib.util.module_from_spec(spec)
loader.exec_module(pr)

REAL_STUCK_LOCAL = pr.stuck_local   # Recovery patches it per case
REF = "claude/laptop/2026-11-06-topic"
SHA = "a" * 40
BASE = "b" * 40
NOW = 1794000000


def iso(t):
    return datetime.datetime.fromtimestamp(t, datetime.timezone.utc).isoformat()


def pull(**kw):
    p = {"number": 7, "state": "open", "draft": False, "labels": [], "auto_merge": None,
         "mergeable_state": "clean", "head": {"ref": REF, "sha": SHA, "repo": {"full_name": "o/r"}},
         "base": {"ref": "main", "sha": BASE}}
    p.update(kw)
    return p


def check(name="check", result="success", t=NOW, **kw):
    r = {"id": 10, "name": name, "status": "completed", "conclusion": result,
         "started_at": iso(t), "completed_at": iso(t + 1)}
    r.update(kw)
    return r


def workflow(i=20, conclusion="cancelled", **kw):
    r = {"id": i, "head_sha": SHA, "head_branch": REF, "event": "pull_request",
         "status": "completed", "conclusion": conclusion, "created_at": iso(NOW + i),
         "pull_requests": [{"number": 7}]}
    r.update(kw)
    return r


class API:
    """Reject every unexpected verb, path, query or body. REST shapes, not gh-shaped stubs."""
    def __init__(self, p=None, checks=None, statuses=None, runs=None, post=201):
        self.p = p or pull()
        self.checks = checks if checks is not None else [check()]
        self.statuses = statuses or []
        self.runs = runs if runs is not None else [workflow()]
        self.posts = []
        self.post = post

    def __call__(self, method, path, body=None, tok=None, **kw):
        assert tok == "tok", tok
        u = urlsplit(path)
        q = parse_qs(u.query)
        root = "/repos/o/r/"
        assert u.path.startswith(root), path
        route = u.path[len(root):]
        if method == "POST":
            assert route in [f"actions/runs/{r['id']}/rerun" for r in self.runs], path
            assert body == {}, body
            self.posts.append(path)
            return self.post, None
        assert method == "GET" and body is None, (method, path)
        if route == "pulls/7":
            assert q == {}, q
            return 200, copy.deepcopy(self.p)
        assert q.pop("per_page") == ["100"], q
        page = int(q.pop("page")[0])
        if route == "pulls":
            assert q == {"state": ["open"]}, q
            return 200, [copy.deepcopy(self.p)] if page == 1 else []
        if route == f"commits/{SHA}/check-runs":
            assert q == {"filter": ["all"]}, q
            return 200, {"check_runs": copy.deepcopy(self.checks[(page - 1) * 100:page * 100])}
        if route == f"commits/{SHA}/status":   # the combined status: newest per context, never the history
            assert q == {}, q
            return 200, {"statuses": copy.deepcopy(self.statuses[(page - 1) * 100:page * 100])}
        assert route == "actions/workflows/automerge.yml/runs", path
        assert q == {"head_sha": [SHA], "event": ["pull_request"]}, q
        return 200, {"workflow_runs": copy.deepcopy(self.runs[(page - 1) * 100:page * 100])}


class Checks(unittest.TestCase):
    def test_union_and_bad_protection(self):
        with tempfile.TemporaryDirectory() as t:
            p = Path(t) / ".github" / "main-protection.json"
            p.parent.mkdir()
            p.write_text(json.dumps({"required_status_checks": {
                "checks": [{"context": "check"}], "contexts": ["legacy", "check"]}}))
            self.assertEqual(pr.stuck_required(t), ["check", "legacy"])
            p.write_text('{"required_status_checks":{"contexts":"check"}}')
            with self.assertRaises(pr.StuckUnreadable):
                pr.stuck_required(t)
            p.unlink()
            with self.assertRaises(pr.StuckUnreadable):
                pr.stuck_required(t)

    def test_latest_pending_then_newest(self):
        rows = [check(result="cancelled", t=NOW - 100), check(t=NOW),
                check(status="queued", conclusion=None, started_at=None, created_at=iso(NOW - 500))]
        red, pending = pr.stuck_checks(["check"], rows, NOW)
        self.assertEqual((red, pending), ([], ["check"]))
        self.assertEqual(pr.stuck_checks(["check"], rows[:2], NOW), ([], []))
        self.assertEqual(pr.stuck_checks(["check"], list(reversed(rows[:2])), NOW), ([], []))

    def test_status_history_reads_its_newest_row(self):
        # check-linux.yml posts `pending` at its trigger, then the verdict: an old pending row is no pending.
        def st(state, t, i):
            return {"id": i, "context": pr.LINUX_CONTEXT, "state": state, "created_at": iso(t),
                    "target_url": "https://circleci.com/x"}
        ok = [st("success", NOW, 2), st("pending", NOW - 600, 1)]
        self.assertEqual(pr.stuck_checks([pr.LINUX_CONTEXT], ok, NOW), ([], []))
        self.assertEqual(pr.stuck_checks([pr.LINUX_CONTEXT], list(reversed(ok)), NOW), ([], []))
        bad = [st("failure", NOW, 2), st("pending", NOW - 600, 1)]
        red, pending = pr.stuck_checks([pr.LINUX_CONTEXT], bad, NOW)
        self.assertEqual((len(red), pending), (1, []))
        self.assertEqual(red[0]["source"], "circleci")

    def test_trigger_ahead_of_the_clock_is_fresh(self):
        r = check("trigger", completed_at=iso(NOW + 30))
        self.assertEqual(pr.stuck_checks([pr.LINUX_CONTEXT], [r], NOW), ([], [pr.LINUX_CONTEXT]))

    def test_missing_linux_trigger_window(self):
        for age, want in [(3599, "pending"), (3600, "pending"), (3601, "red")]:
            r = check("trigger", completed_at=iso(NOW - age))
            red, pending = pr.stuck_checks([pr.LINUX_CONTEXT], [r], NOW)
            self.assertEqual(bool(pending), want == "pending")
            self.assertEqual(bool(red), want == "red")
        for r in [[], [check("trigger", result="failure")], [check("trigger", completed_at=None)]]:
            self.assertTrue(pr.stuck_checks([pr.LINUX_CONTEXT], r, NOW)[0])
        queued = check("trigger", status="queued", conclusion=None, started_at=None)
        self.assertEqual(pr.stuck_checks([pr.LINUX_CONTEXT], [queued], NOW), ([], [pr.LINUX_CONTEXT]))
        self.assertTrue(pr.stuck_checks(["absent"], [queued], NOW)[0])

    def test_red_sources(self):
        rows = [check(result="failure"), {"context": pr.LINUX_CONTEXT, "state": "error",
                                          "created_at": iso(NOW), "target_url": "https://circleci.com/gh/o/r/1"}]
        red, pending = pr.stuck_checks(["check", pr.LINUX_CONTEXT], rows, NOW)
        self.assertEqual([r["source"] for r in red], ["actions:check", "circleci"])
        rows[1]["target_url"] = "https://github.com/o/r/actions/runs/4"
        self.assertEqual(pr.stuck_checks([pr.LINUX_CONTEXT], rows, NOW)[0][0]["source"], "actions:check-linux.yml")
        self.assertEqual(pending, [])

    def test_pagination_and_short_reads(self):
        api = API(checks=[check(id=i) for i in range(105)])
        with patch.object(pr.common, "api", api):
            rows = pr.stuck_pages("o/r", f"commits/{SHA}/check-runs?filter=all", "tok", "check_runs")
        self.assertEqual(len(rows), 105)
        with patch.object(pr.common, "api", return_value=(403, {})):
            with self.assertRaises(pr.StuckUnreadable):
                pr.stuck_pages("o/r", "pulls?state=open", "tok")
        with patch.object(pr.common, "api", return_value=(200, [{}] * 100)):
            with self.assertRaises(pr.StuckUnreadable):
                pr.stuck_pages("o/r", "pulls?state=open", "tok")


class Owner(unittest.TestCase):
    def test_all_scopes_and_laptop(self):
        reg = {"scopes": {"umbrella": {"repos": ["*"]},
                          "own": {"repos": ["repo"], "yard": "yard"}}}
        with patch.object(pr.common, "read_registry", return_value=(reg, False)), \
                patch.object(pr.common, "repo_key", return_value="repo"):
            self.assertEqual(pr.stuck_owner("repo"), "yard")
            reg["scopes"]["own"].pop("yard")
            self.assertEqual(pr.stuck_owner("repo"), "laptop")
            reg["scopes"]["own"]["yard"] = "yard"
            reg["scopes"]["umbrella"]["yard"] = "elsewhere"
            with self.assertRaises(pr.StuckUnreadable):
                pr.stuck_owner("repo")
        with patch.object(pr.common, "read_registry", return_value=(None, True)):
            with self.assertRaises(pr.StuckUnreadable):
                pr.stuck_owner("repo")

    def test_other_host_does_not_read_github_or_spend(self):
        out = io.StringIO()
        with patch.object(pr, "stuck_owner", return_value="yard"), \
                patch.object(pr.common, "host_name", return_value="laptop"), \
                patch.object(pr.common, "api", side_effect=AssertionError("other host read GitHub")), \
                patch.object(pr, "git", return_value="/scratch/.git"), contextlib.redirect_stdout(out):
            self.assertEqual(pr.stuck(["stuck", "--json"], "o/r", "tok", "main"), 0)
        self.assertEqual(json.loads(out.getvalue())["prs"], [])


class Recovery(unittest.TestCase):
    def setUp(self):
        self.t = tempfile.TemporaryDirectory()
        self.addCleanup(self.t.cleanup)
        self.root = Path(self.t.name)
        self.api = API()
        self.tool = M.parent / "wharf-runs" / "bin" / "autofinish-run"
        self.stack = contextlib.ExitStack()
        self.addCleanup(self.stack.close)
        self.stack.enter_context(patch.dict(os.environ, {"AUTOFINISH_STATE_DIR": str(self.root / "state")}))
        self.stack.enter_context(patch.object(pr.common, "api", self.api))
        self.stack.enter_context(patch.object(pr.common, "tool", side_effect=lambda n: self.tool if n == "autofinish-run" else None))
        self.stack.enter_context(patch.object(pr, "stuck_local", return_value=(None, None, None, False)))

    def rerun(self, dry=False):
        return pr.stuck_rerun("o/r", "tok", pull(), self.root, dry)

    def row(self, **kw):
        self.api.p = pull(**kw)
        return pr.stuck_one("o/r", "tok", self.api.p, self.root, "main", ["check"])

    def test_skip_newest_for_cancelled_and_real_cap(self):
        self.api.runs = [workflow(30, "skipped"), workflow(20)]
        self.assertIn("run 20: rerun HTTP 201", self.rerun())
        self.assertIn("run 20: rerun HTTP 201", self.rerun())
        self.assertIn("not spent", self.rerun())
        self.assertEqual(self.api.posts, ["/repos/o/r/actions/runs/20/rerun"] * 2)

    def test_only_skipped_or_wrong_head_not_rerun(self):
        self.api.runs = [workflow(30, "skipped"), workflow(head_sha=BASE)]
        self.assertIn("no non-skipped", self.rerun())
        self.assertEqual(self.api.posts, [])
        self.assertFalse((self.root / "state").exists())

    def test_pending_dry_and_refused_post(self):
        self.api.runs = [workflow(status="queued", conclusion=None)]
        self.assertIn("already pending", self.rerun())
        self.api.runs = [workflow()]
        self.assertIn("would rerun", self.rerun(True))
        self.assertFalse((self.root / "state").exists())
        self.api.post = 403
        self.assertIn("HTTP 403 (cap spent)", self.rerun())
        self.assertIn("HTTP 403 (cap spent)", self.rerun())
        self.assertIn("not spent", self.rerun())
        self.assertEqual(len(self.api.posts), 2)

    def test_stuck_key_does_not_rerun(self):
        r = subprocess.run([str(self.tool), "lander", "stuck", "--repo", str(self.root), "--branch", REF],
                           capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("not spent", self.rerun())
        self.assertEqual(self.api.posts, [])

    def test_gone_worktree_is_named_and_the_pass_goes_on(self):
        gone = str(self.root / "gone-tree")
        with patch.object(pr, "worktree_of", return_value=gone):
            self.assertEqual(REAL_STUCK_LOCAL(str(self.root), REF), (gone, None, None, False))
        with patch.object(pr, "stuck_local", return_value=(gone, None, None, False)):
            r = self.row(mergeable_state="dirty")
        self.assertEqual((r["kind"], r["request"]), ("dirty", None))
        self.assertIn("worktree here is gone", r["reason"])

    def test_unarmed_with_a_red_status_is_never_rerun(self):
        self.api.statuses = [{"id": 2, "context": "check", "state": "failure", "created_at": iso(NOW)},
                             {"id": 1, "context": "check", "state": "pending", "created_at": iso(NOW - 60)}]
        self.api.checks = []
        r = self.row()
        self.assertEqual(r["kind"], "red", r)
        self.assertEqual(self.api.posts, [])

    def test_pr_changed_before_spend(self):
        for changes in [{"labels": [{"name": "hold"}]}, {"labels": [{"name": "lander-hold"}]},
                        {"head": {"sha": BASE}}, {"draft": True}, {"auto_merge": {"enabled_by": {}}}]:
            self.api.p = pull(**changes)
            self.assertIn("nothing rerun", self.rerun())
        self.assertEqual(self.api.posts, [])
        self.assertFalse((self.root / "state").exists())

    def test_holds_live_and_required_red_never_rerun(self):
        for label in ("hold", "lander-hold"):
            self.assertEqual(self.row(labels=[{"name": label}])["kind"], "held")
        with patch.object(pr, "stuck_local", return_value=("tree", SHA, {}, True)):
            self.assertEqual(self.row()["kind"], "live")
        self.api.checks = [check(result="failure")]
        self.assertEqual(self.row()["kind"], "red")
        self.api.checks += [check(name="other", status="queued", conclusion=None)]
        r = pr.stuck_one("o/r", "tok", pull(), self.root, "main", ["check", "other"])
        self.assertEqual(r["kind"], "pending")
        self.assertEqual(self.api.posts, [])

    def test_dirty_other_host_and_unknown(self):
        r = self.row(mergeable_state="dirty")
        self.assertEqual(r["kind"], "dirty")
        self.assertIsNone(r["request"])
        self.assertIn("another host", r["reason"])
        with patch.object(pr, "stuck_local", return_value=("/here/tree", "c" * 40, {}, False)):
            r = self.row(mergeable_state="dirty")
        self.assertIsNone(r["request"])
        self.assertNotIn("another host", r["reason"])
        self.assertIn("its own /finish", r["reason"])
        r = self.row(mergeable_state="unknown", auto_merge={"enabled_by": {}})
        self.assertEqual(r["kind"], "unknown")
        self.assertEqual(self.api.posts, [])


class Dirty(unittest.TestCase):
    """Real dry restack judgements: no network and no second conflict classifier in stuck."""
    def setUp(self):
        self.t = tempfile.TemporaryDirectory()
        self.addCleanup(self.t.cleanup)
        self.r = Path(self.t.name) / "repo"
        self.r.mkdir()
        self.git("init", "-q", "-b", "main")
        (self.r / ".gitattributes").write_text("CHANGELOG.md merge=union\n")
        (self.r / "CHANGELOG.md").write_text("## Unreleased\n\n- base\n")
        (self.r / "f").write_text("base\n")
        self.git("add", ".")
        self.git("commit", "-qm", "base")
        self.git("checkout", "-qb", REF)
        (self.r / "CHANGELOG.md").write_text("## Unreleased\n\n- branch\n- base\n")
        (self.r / "f").write_text("branch\n")
        self.git("commit", "-qam", "branch")
        self.sha = self.git("rev-parse", "HEAD")
        self.git("update-ref", f"refs/remotes/origin/{REF}", self.sha)
        self.git("checkout", "-q", "main")
        (self.r / "CHANGELOG.md").write_text("## Unreleased\n\n- main\n- base\n")
        self.git("commit", "-qam", "main")
        subprocess.run([str(M / "bin" / "list-merge"), "install", str(self.r), "--here"], check=True,
                       capture_output=True, text=True)

    def git(self, *a):
        r = subprocess.run(["git", "-C", str(self.r), *a], capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stderr)
        return r.stdout.strip()

    def judge(self, stop=None, pr_base=None, gh_main=None, gh_status=200):
        base = self.git("rev-parse", "main")
        self.git("update-ref", "refs/remotes/origin/main", base)
        row = {"head": self.sha, "branch": REF, "worktree": "tree", "kind": "dirty", "request": None}
        p = pull(base={"sha": pr_base or base})
        stop = stop or {"outcome": "launched", "ended": "then", "tip": self.sha}

        def api(method, path, body=None, tok=None, **kw):
            assert (method, path, body, tok) == ("GET", "/repos/o/r/branches/main", None, "tok"), (method, path)
            return gh_status, {"name": "main", "commit": {"sha": gh_main or base}} if gh_status == 200 else None
        with patch.object(pr.common, "api", side_effect=api):
            pr.stuck_dirty("o/r", "tok", str(self.r), p, "main", row, stop)
        return row

    def test_main_is_read_from_the_base_branch_not_the_prs_base(self):
        # GitHub leaves a PR's base.sha at the base of its last push: the fork point here, main moved since.
        (self.r / "f").write_text("main\n")
        self.git("commit", "-qam", "conflict")
        fork = self.git("merge-base", "main", self.sha)
        row = self.judge(pr_base=fork)
        self.assertEqual(row["request"], {"road": "refinish", "worktree": "tree", "head": self.sha}, row)
        row = self.judge(gh_main="c" * 40)
        self.assertEqual((row["kind"], row["request"]), ("unknown", None))
        self.assertIn("not GitHub's", row["reason"])
        row = self.judge(gh_status=404)
        self.assertEqual((row["kind"], row["request"]), ("unknown", None))

    def test_kept_stop_read_from_the_real_store(self):
        (self.r / "f").write_text("main\n")
        self.git("commit", "-qam", "conflict")
        afr = pr.stuck_afr()
        kept = {"outcome": "launched", "ended": "then", "tip": self.sha, "session": "s1"}
        refused = {"outcome": "never-started", "ended": "later", "tip": self.sha, "session": "s2",
                   "by": "lander", "gate": sorted(pr.common.REFUSED_GATES)[0]}
        store = Path(os.environ["AUTOFINISH_STATE_DIR"]) / "lander.json"
        store.parent.mkdir(parents=True, exist_ok=True)
        store.write_text(json.dumps({afr.lander_key(str(self.r), REF): {"stop": kept, "stop_for": "s1"}}))
        try:
            row = self.judge(refused)
            self.assertEqual(row["request"], {"road": "refinish", "worktree": "tree", "head": self.sha}, row)
        finally:
            store.unlink()
        row = self.judge(refused)
        self.assertIsNone(row["request"], row)

    def test_lists_stay_with_restack(self):
        row = self.judge()
        self.assertEqual(row["kind"], "restack", row)
        self.assertIsNone(row["request"])
        self.assertEqual(self.git("rev-parse", f"origin/{REF}"), self.sha)

    def test_code_conflict_requests_only_s1_stop(self):
        (self.r / "f").write_text("main\n")
        self.git("commit", "-qam", "conflict")
        row = self.judge()
        self.assertEqual(row["request"], {"road": "refinish", "worktree": "tree", "head": self.sha}, row)
        for gate in ("G1r", "G4", "held"):
            row = self.judge({"outcome": "stopped", "ended": "then", "gate": gate, "tip": self.sha})
            self.assertIsNone(row["request"], row)
        row = self.judge({"outcome": "launched", "ended": "then", "tip": self.sha, "pushed": BASE})
        self.assertIsNone(row["request"], row)

    def test_refused_lander_start_keeps_its_kept_stop(self):
        # S1's road_stop: a lander start dispatch refused is no stop of its own; the kept stop is judged.
        (self.r / "f").write_text("main\n")
        self.git("commit", "-qam", "conflict")
        kept = {"outcome": "launched", "ended": "then", "tip": self.sha, "session": "s1"}
        refused = {"outcome": "never-started", "ended": "later", "tip": self.sha, "session": "s2",
                   "by": "lander", "gate": sorted(pr.common.REFUSED_GATES)[0]}
        with patch.object(pr, "stuck_lander_entry", return_value={"stop": kept, "stop_for": "s1"}):
            row = self.judge(refused)
        self.assertEqual(row["request"], {"road": "refinish", "worktree": "tree", "head": self.sha}, row)
        with patch.object(pr, "stuck_lander_entry", return_value=None):
            row = self.judge(refused)
        self.assertIsNone(row["request"], row)
        with patch.object(pr, "stuck_lander_entry", side_effect=pr.StuckUnreadable("store torn")):
            row = self.judge()
        self.assertEqual((row["kind"], row["request"]), ("unknown", None))

    def test_another_hosts_stop_is_not_requested(self):
        (self.r / "f").write_text("main\n")
        self.git("commit", "-qam", "conflict")
        stop = {"outcome": "launched", "ended": "then", "tip": self.sha, "host": "elsewhere-host"}
        with patch.dict(os.environ, {"AUTOFINISH_HOST": "this-host"}):
            row = self.judge(stop)
        self.assertIsNone(row["request"], row)
        self.assertIn("another host", row["reason"])
        with patch.dict(os.environ, {"AUTOFINISH_HOST": "elsewhere-host"}):
            row = self.judge(stop)
        self.assertIsNotNone(row["request"], row)

    def test_other_restack_refusals_request_finish_but_unreadable_waits(self):
        # A merge commit or an unsupported merge attribute also needs the branch's own finish.
        # Routing uses restack's verdict, not a particular English conflict message.
        with patch.object(pr, "restack_tree", return_value=(1, "the PR holds merge commits", None)):
            self.assertIsNotNone(self.judge()["request"])
        with patch.object(pr, "restack_tree", return_value=(2, "the driver could not be read", None)):
            row = self.judge()
            self.assertEqual(row["kind"], "unknown")
            self.assertIsNone(row["request"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
