"""Nightly check regressions. No network, peer process, caller config or real HOME."""
import contextlib
import copy
import importlib.machinery
import json
import os
import re
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch
from urllib.parse import parse_qs, urlsplit

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "modules/helm/bin"))
import main_check as m
import helmlib
import helm_render


class Nightly(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.repo = Path(self.temp.name) / "demo"
        self.repo.mkdir()
        self.cache = Path(self.temp.name) / "cache"
        self.env = patch.dict(os.environ, ASK_CACHE_DIR=str(self.cache), PLAN_CACHE_DIR=str(self.cache / "board"))
        self.env.start()
        self.addCleanup(self.env.stop)
        subprocess.run(["git", "init", "-q", str(self.repo)], check=True)
        subprocess.run(["git", "-C", str(self.repo), "remote", "add", "origin", "https://github.com/acme/demo.git"], check=True)
        wf = self.repo / ".github/workflows/check.yml"
        wf.parent.mkdir(parents=True)
        wf.write_text("name: check\non:\n  schedule:\n    - cron: '17 9 * * *'\n")
        self.runs = [self.run_row(1, "failure")]
        self.jobs = [{"name": "check", "conclusion": "failure", "steps": [
            {"name": "nightly regatta", "conclusion": "failure"},
            {"name": "nightly sextant", "conclusion": "success"},
            {"name": "nightly wharf-runs", "conclusion": "failure"}]}]
        self.calls, self.issues = [], []
        self.fail_path = None
        self.fail_method = None   # with self.fail_path: only this method fails
        self.fail_reply = (503, None, "HTTP 503")
        self.gone = {}            # issue number -> the status its PATCH answers (deleted, transferred)
        self.ask = SimpleNamespace(gh_api=self.api, logbook=lambda: ("acme/logbook", None))

    @staticmethod
    def run_row(n, conclusion, attempt=1):
        return {"id": n + 100, "run_number": n, "run_attempt": attempt,
                "event": "schedule", "head_branch": "main", "status": "completed",
                "conclusion": conclusion, "html_url": "https://github.com/acme/demo/actions/runs/%s" % (n + 100)}

    def make_repo(self, name, schedule=True):
        repo = Path(self.temp.name) / name
        repo.mkdir()
        subprocess.run(["git", "init", "-q", str(repo)], check=True)
        subprocess.run(["git", "-C", str(repo), "remote", "add", "origin", "https://github.com/acme/%s.git" % name], check=True)
        if schedule:
            wf = repo / ".github/workflows/check.yml"
            wf.parent.mkdir(parents=True)
            wf.write_text("name: check\non:\n  schedule:\n    - cron: '17 9 * * *'\n")
        return repo

    def api(self, method, path, body=None):
        # Validate the real REST route and query arguments, not just the caller's intent.
        u = urlsplit(path)
        q = parse_qs(u.query)
        self.calls.append((method, path, copy.deepcopy(body)))
        if self.fail_path and self.fail_path in path and self.fail_method in (None, method):
            return self.fail_reply
        if u.path == "/repos/acme/demo/actions/workflows/check.yml/runs":
            self.assertEqual(method, "GET")
            self.assertIsNone(body)
            self.assertEqual(q, {"branch": ["main"], "event": ["schedule"], "status": ["completed"], "per_page": ["10"]})
            return 200, {"workflow_runs": copy.deepcopy(self.runs)}, None
        if re.fullmatch(r"/repos/acme/demo/actions/runs/\d+/attempts/\d+/jobs", u.path):
            self.assertEqual(method, "GET")
            self.assertEqual(q, {"per_page": ["100"], "page": ["1"]})
            return 200, {"jobs": copy.deepcopy(self.jobs)}, None
        book = re.fullmatch(r"/repos/(acme/(?:logbook|other-logbook|logbok))/issues", u.path, re.I)
        if book and book[1].lower() == "acme/logbok":
            return 404, None, "HTTP 404"   # a typo'd logbook: no such repository
        if book:
            if method == "GET":
                self.assertEqual(q, {"state": ["open"], "labels": ["bug"], "per_page": ["100"], "page": ["1"]})
                return 200, [dict(i) for i in self.issues if i.get("state") != "closed" and i["repo"] == book[1].lower()
                             and i["number"] not in self.gone], None
            self.assertEqual(method, "POST")
            self.assertEqual(body["labels"], ["bug"])
            self.assertNotIn("@", body["body"])
            n = len(self.issues) + 1
            issue = dict(body, number=n, repo=book[1].lower(), html_url="https://github.com/%s/issues/%d" % (book[1].lower(), n))
            self.issues.append(issue)
            return 201, issue, None
        one = re.fullmatch(r"/repos/(acme/(?:logbook|other-logbook))/issues/(\d+)", u.path, re.I)
        if one:
            self.assertEqual(method, "PATCH")
            if int(one[2]) in self.gone:
                return self.gone[int(one[2])]
            issue = self.issues[int(one[2]) - 1]
            self.assertEqual(issue["repo"], one[1].lower())
            issue.update(body)
            return 200, issue, None
        raise self.failureException("unexpected API call: %s %s %r" % (method, path, body))

    def poll(self, repos=None, deadline=None):
        return m.poll(repos if repos is not None else [self.repo], self.ask, deadline)

    def test_red_one_card_one_bug_no_mention(self):
        self.assertEqual(self.poll(), [])
        self.assertEqual(len(self.issues), 1)
        self.assertIn("Failed: regatta, wharf-runs", self.issues[0]["body"])
        self.assertIn(self.runs[0]["html_url"], self.issues[0]["body"])
        self.assertEqual(self.issues[0]["labels"], ["bug"])
        cards = m.cards()
        self.assertEqual(len(cards), 1)
        self.assertEqual(cards[0]["kind"], "main-red")
        self.assertEqual(cards[0]["column"], helmlib.columns()[0])
        self.assertEqual(cards[0]["url"], self.runs[0]["html_url"])
        self.assertEqual(self.poll([self.repo, self.repo]), [])
        self.assertEqual(len(self.issues), 1)
        self.assertEqual(sum(c[0] == "PATCH" for c in self.calls), 0)

    def test_new_red_updates_existing_issue(self):
        self.poll()
        self.runs = [self.run_row(2, "failure")]
        self.jobs[0]["steps"][0]["name"] = "nightly helm"
        self.poll()
        self.assertEqual(len(self.issues), 1)
        self.assertIn("Failed: helm, wharf-runs", self.issues[0]["body"])
        self.assertEqual(len(m.cards()), 1)

    def test_green_closes_then_next_red_opens_new_issue(self):
        self.poll()
        self.runs = [self.run_row(2, "success")]
        self.poll()
        self.assertEqual(self.issues[0]["state"], "closed")
        self.assertIn("Recovered: " + self.runs[0]["html_url"], self.issues[0]["body"])
        self.assertEqual(m.cards(), [])
        self.runs = [self.run_row(3, "failure")]
        self.poll()
        self.assertEqual(len(self.issues), 2)

    def test_cut_run_names_failed_and_unfinished_suites(self):
        self.runs = [self.run_row(1, "timed_out")]
        self.jobs[0]["conclusion"] = "timed_out"
        self.jobs[0]["steps"][1]["conclusion"] = "cancelled"
        self.jobs[0]["steps"][2]["conclusion"] = "skipped"
        self.poll()
        self.assertIn("Failed: regatta", self.issues[0]["body"])
        self.assertIn("Cut or not run: sextant, wharf-runs", self.issues[0]["body"])
        self.assertEqual(len(m.cards()), 1)

    def test_cancelled_is_red(self):
        self.runs = [self.run_row(1, "cancelled")]
        self.poll()
        self.assertEqual(len(self.issues), 1)

    def test_api_outage_does_not_clear_red(self):
        self.poll()
        self.fail_path = "/runs?"
        self.assertTrue(self.poll())
        self.assertEqual(len(m.cards()), 1)
        self.assertNotIn("state", self.issues[0])

    def test_unread_jobs_still_alert_and_retry(self):
        self.fail_path = "/jobs?"
        self.assertTrue(self.poll())
        self.assertEqual(len(self.issues), 1)
        self.assertIn("Suite results unread", self.issues[0]["body"])
        self.fail_path = None
        self.poll()
        self.assertIn("Failed: regatta, wharf-runs", self.issues[0]["body"])

    def test_issue_write_failure_preserves_card_and_retries(self):
        self.fail_path = "/issues"
        self.assertTrue(self.poll())
        self.assertEqual(len(m.cards()), 1)
        self.fail_path = None
        self.poll()
        self.assertEqual(len(self.issues), 1)

    def test_close_failure_keeps_card_until_delivered(self):
        self.poll()
        self.runs = [self.run_row(2, "success")]
        self.fail_path = "/issues/1"
        self.assertTrue(self.poll())
        self.assertIn("issue still open", m.cards()[0]["title"])
        self.fail_path = None
        self.poll()
        self.assertEqual(m.cards(), [])
        self.assertEqual(self.issues[0]["state"], "closed")

    def test_lost_cache_commit_recovers_issue_by_marker(self):
        self.poll()
        row = m.read()
        row["acme/demo"].pop("issue")
        m.write(row)
        self.poll()
        self.assertEqual(len(self.issues), 1)
        self.assertEqual(m.read()["acme/demo"]["issue"], 1)

    def test_lost_issue_identity_then_green_still_closes(self):
        self.poll()
        row = m.read()
        row["acme/demo"].pop("issue")
        m.write(row)
        self.runs = [self.run_row(2, "success")]
        self.poll()
        self.assertEqual(len(self.issues), 1)
        self.assertEqual(self.issues[0]["state"], "closed")
        self.assertEqual(m.cards(), [])

    def test_destination_stays_pinned_until_closed(self):
        self.poll()
        self.ask.logbook = lambda: ("acme/other-logbook", None)
        self.runs = [self.run_row(2, "success")]
        self.poll()
        self.assertEqual(self.issues[0]["state"], "closed")

    def test_only_completed_main_schedule_counts(self):
        for change in ({"event": "push"}, {"event": "workflow_dispatch"}, {"head_branch": "topic"},
                       {"status": "in_progress"}, {"conclusion": "neutral"}):
            self.runs = [dict(self.run_row(1, "failure"), **change)]
            self.poll()
        self.assertEqual(self.issues, [])

    def test_newer_green_wins_and_old_rerun_cannot_clear_new_red(self):
        self.runs = [self.run_row(1, "failure"), self.run_row(2, "success")]
        self.poll()
        self.assertEqual(self.issues, [])
        self.runs = [self.run_row(3, "failure")]
        self.poll()
        self.runs = [self.run_row(2, "success", attempt=9)]
        self.poll()
        self.assertEqual(len(m.cards()), 1)
        self.runs = [self.run_row(3, "success", attempt=2)]
        self.poll()
        self.assertEqual(m.cards(), [])

    def test_no_schedule_no_github_origin_or_guarded_no_calls(self):
        with patch.object(helmlib, "guarded", return_value=True):
            self.poll()
        with patch.object(helmlib, "guard_unread", return_value=True):
            self.poll()
        with patch.object(helmlib._common(), "registry_unreadable", return_value=True):
            self.poll()
        wf = self.repo / ".github/workflows/check.yml"
        wf.write_text("name: check\n")
        self.poll()
        self.assertEqual(self.calls, [])

    def test_session_unattended_deadline_and_lock_never_act(self):
        for key in ("CLAUDE_CODE_SESSION_ID", "CLAUDE_UNATTENDED", "REGATTA_UNATTENDED",
                    "CLAUDE_CODE_DISABLE_BACKGROUND_TASKS"):
            with patch.dict(os.environ, {key: "yes"}):
                self.poll()
        self.poll(deadline=time.time() + 10)
        import fcntl
        with m.cache_path().with_suffix(".lock").open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            self.assertIn("another poll", self.poll()[0])
        self.assertEqual(self.calls, [])

    def test_torn_cache_never_overwrites_issue_identity(self):
        self.cache.mkdir()
        m.cache_path().write_text("{")
        with self.assertRaises(ValueError):
            self.poll()
        self.assertEqual(m.cache_path().read_text(), "{")
        self.assertEqual(self.calls, [])

    def test_malformed_row_cannot_crash_board_or_lose_issue_identity(self):
        self.cache.mkdir()
        text = '{"acme/demo": {"red": true, "issue": 1}}'
        m.cache_path().write_text(text)
        self.assertEqual([c["title"] for c in m.cards()], ["main check: cache unreadable"])
        with self.assertRaises(ValueError):
            self.poll()
        self.assertEqual(m.cache_path().read_text(), text)

    def test_normal_poll_reaches_reader_dry_explicit_and_other_host_do_not(self):
        ask = importlib.machinery.SourceFileLoader("ask_main_check_test", str(ROOT / "modules/helm/bin/ask")).load_module()
        with contextlib.ExitStack() as stack:
            stack.enter_context(patch.object(ask, "gh_api", side_effect=self.api))
            stack.enter_context(patch.object(ask, "logbook", side_effect=self.ask.logbook))
            stack.enter_context(patch.object(ask, "memo", return_value=None))
            stack.enter_context(patch.object(ask, "poll_jobs", return_value=([], [])))
            stack.enter_context(patch.object(ask, "run_jobs"))
            stack.enter_context(patch.object(ask, "poll_repos", return_value=[self.repo]))
            stack.enter_context(patch.object(ask, "scan_repo", return_value=[]))
            stack.enter_context(patch.object(ask, "carry_forward", return_value=[]))
            stack.enter_context(patch.object(ask, "poll_tick"))
            stack.enter_context(patch.object(ask, "poll_board"))
            stack.enter_context(patch.object(helmlib, "prefetch_prs"))
            host = stack.enter_context(patch.object(ask.surfaces, "host", return_value=ask.laptop_name()))
            ask.cmd_poll(SimpleNamespace(dry_run=True, repos=None))
            ask.cmd_poll(SimpleNamespace(dry_run=False, repos=[str(self.repo)]))
            host.return_value = "buildbox"
            ask.cmd_poll(SimpleNamespace(dry_run=False, repos=None))
            self.assertEqual(self.calls, [])
            host.return_value = ask.laptop_name()
            ask.cmd_poll(SimpleNamespace(dry_run=False, repos=None))
        self.assertEqual(len(self.issues), 1)

    def test_board_uses_cache_and_deduplicates_intake(self):
        self.poll()
        issue_url = m.cards()[0]["github"]
        with contextlib.ExitStack() as stack:
            # Other board sources have their own suites. Keep this case offline and empty.
            for name in ("poll_cards", "memo_cards", "lookout_cards", "run_cards", "waiting_cards", "road_cards",
                         "todo_cards", "held_cards", "done_cards", "week_line", "talk_note", "paused_note", "ops_row"):
                stack.enter_context(patch.object(helm_render, name, return_value=[] if name.endswith("cards") else None))
            stack.enter_context(patch.object(helmlib, "list_plans", return_value=[]))
            stack.enter_context(patch.object(helmlib, "prefetch_prs", return_value={}))
            stack.enter_context(patch.object(helm_render, "stall_cards", return_value=([], {})))
            stack.enter_context(patch.object(helm_render, "pr_cards", return_value=([], [])))
            stack.enter_context(patch.object(helm_render, "intake_cards", return_value=[{"url": issue_url, "kind": "intake"}]))
            board = helm_render.overview_state()
        cards = [c for col in board["columns"] for c in col["cards"]]
        self.assertEqual([c["kind"] for c in cards], ["main-red"])

    def test_guard_rechecked_before_writes_and_card_render(self):
        api = self.ask.gh_api
        def changed(method, path, body=None):
            result = api(method, path, body)
            if "/jobs?" in path:
                self.guard = patch.object(helmlib, "guard_unread", return_value=True)
                self.guard.start()
                self.addCleanup(self.guard.stop)
            return result
        self.ask.gh_api = changed
        self.poll()
        self.assertEqual(self.issues, [])
        self.assertEqual(m.cards(), [])

    def test_setup_failure_is_named(self):
        self.jobs[0]["steps"].insert(0, {"name": "checkout", "conclusion": "failure"})
        self.poll()
        self.assertIn("check / checkout", self.issues[0]["body"])

    # -- the finish review's fixes, 2026-11-05 -------------------------------------------------------

    def test_lookup_finding_nothing_honours_a_changed_logbook(self):
        # S1: a POST that failed pinned acme/logbook; nothing was filed there, so the new logbook wins
        self.fail_path, self.fail_method = "/logbook/issues", "POST"
        self.assertTrue(self.poll())
        self.assertEqual(m.read()["acme/demo"]["issue_repo"], "acme/logbook")
        self.fail_path = None
        self.ask.logbook = lambda: ("acme/other-logbook", None)
        self.poll()
        self.assertEqual([i["repo"] for i in self.issues], ["acme/other-logbook"])
        self.assertEqual(m.cards()[0]["github"], "https://github.com/acme/other-logbook/issues/1")

    def test_green_after_lost_post_drops_the_pin(self):
        self.fail_path, self.fail_method = "/logbook/issues", "POST"
        self.poll()
        self.fail_path = None
        self.runs = [self.run_row(2, "success")]
        self.poll()
        self.assertNotIn("issue_repo", m.read()["acme/demo"])
        self.assertEqual(m.cards(), [])
        self.ask.logbook = lambda: ("acme/other-logbook", None)
        self.runs = [self.run_row(3, "failure")]
        self.poll()
        self.assertEqual([i["repo"] for i in self.issues], ["acme/other-logbook"])

    def test_gone_issue_is_forgotten_and_refiled_never_retried_forever(self):
        for reply in ((404, None, "HTTP 404"), (410, None, "HTTP 410"), (301, None, "HTTP 301"),
                      (0, None, "gh: Not Found (HTTP 404)")):   # ASK_GH_API's gh: exit 1, the status in stderr
            with self.subTest(reply=reply):
                self.issues, self.gone = [], {}
                m.cache_path().unlink(missing_ok=True)
                self.runs = [self.run_row(1, "failure")]
                self.poll()
                self.gone[1] = reply
                self.runs = [self.run_row(2, "failure")]
                self.assertEqual(self.poll(), [])
                self.assertEqual(len(self.issues), 2)
                self.assertEqual(m.cards()[0]["github"], "https://github.com/acme/logbook/issues/2")
                # and a green whose issue is gone closes nothing, once, and leaves no card
                self.gone[2] = reply
                self.runs = [self.run_row(3, "success")]
                before = len(self.calls)
                self.assertEqual(self.poll(), [])
                self.assertEqual(sum(c[0] == "PATCH" for c in self.calls[before:]), 1)
                self.assertEqual(m.cards(), [])
                self.poll()
                self.assertEqual(sum(c[0] == "PATCH" for c in self.calls[before:]), 1)

    def test_red_night_reopens_an_issue_closed_by_hand(self):
        self.poll()
        self.issues[0]["state"] = "closed"
        self.runs = [self.run_row(2, "failure")]
        self.poll()
        self.assertEqual(len(self.issues), 1)
        self.assertEqual(self.issues[0]["state"], "open")

    def test_run_with_no_jobs_is_read_not_retried(self):
        for conclusion in ("startup_failure", "action_required"):
            with self.subTest(conclusion=conclusion):
                self.issues = []
                m.cache_path().unlink(missing_ok=True)
                self.runs, self.jobs = [self.run_row(1, conclusion)], []
                self.assertEqual(self.poll(), [])
                self.assertIn("Cut or not run: check", self.issues[0]["body"])
                self.assertNotIn("unread", self.issues[0]["body"])
                before = len(self.calls)
                self.poll()
                self.assertFalse([c for c in self.calls[before:] if "/jobs?" in c[1]])

    def test_job_skipped_by_its_if_is_not_cut(self):
        self.jobs += [{"name": n, "conclusion": "skipped", "steps": []} for n in ("plan", "suite", "check (gather)")]
        self.poll()
        self.assertNotIn("Cut or not run", self.issues[0]["body"])
        self.assertIn("Failed: regatta, wharf-runs", self.issues[0]["body"])

    def test_unset_or_malformed_logbook_leaves_no_card_after_green(self):
        for why in ("no helm/logbook-repo value in the config dir", "helm/logbook-repo is 'x', not owner/name"):
            with self.subTest(why=why):
                m.cache_path().unlink(missing_ok=True)
                self.ask.logbook = lambda why=why: (None, why)
                self.runs = [self.run_row(1, "failure")]
                self.assertTrue(self.poll())
                self.assertEqual(m.cards()[0]["rule"], why)
                self.runs = [self.run_row(2, "success")]
                self.assertEqual(self.poll(), [])
                self.assertEqual(m.cards(), [])
        self.assertEqual(self.issues, [])

    def test_row_of_a_repo_the_poll_left_expires_and_closes_its_issue(self):
        self.poll()
        other = self.make_repo("plain", schedule=False)
        notes = self.poll([other])
        self.assertEqual(self.issues[0]["state"], "closed")
        self.assertIn("No longer read", self.issues[0]["body"])
        self.assertEqual(m.read(), {})
        self.assertTrue(any("left the poll" in n for n in notes))
        self.assertEqual(m.cards(), [])

    def test_left_repo_whose_close_fails_is_named_then_dropped(self):
        self.poll()
        other = self.make_repo("plain", schedule=False)
        self.fail_path = "/issues/1"
        self.poll([other])
        self.assertIn("no longer read", m.cards()[0]["title"])
        self.poll([other])
        notes = self.poll([other])
        self.assertTrue(any("is left open" in n and "issues/1" in n for n in notes))
        self.assertEqual(m.read(), {})
        self.assertEqual(sum(c[0] == "PATCH" for c in self.calls), 2)

    def test_guarded_or_cut_pass_never_expires_a_row(self):
        self.poll()
        with patch.object(helmlib, "guarded", return_value=True):
            self.poll()
        self.poll([])
        self.poll(deadline=time.time() + 10)
        with patch.object(m, "read_source", return_value=(None, False)):   # git's origin read timed out
            self.poll()
        self.assertEqual(m.read()["acme/demo"]["issue"], 1)
        self.assertNotIn("state", self.issues[0])

    def test_git_failure_is_unsure_not_a_lost_origin(self):
        # exit 128 (a bad config line) is no "no such remote" (exit 2): the red's issue stays open
        self.poll()
        cfg = self.repo / ".git/config"
        good = cfg.read_text()
        cfg.write_text(good + "\n[broken\n")
        self.assertEqual(m.read_source(self.repo), (None, False))
        self.poll()
        self.assertEqual(m.read()["acme/demo"]["issue"], 1)
        self.assertNotIn("state", self.issues[0])
        cfg.write_text(good)
        subprocess.run(["git", "-C", str(self.repo), "remote", "remove", "origin"], check=True)
        self.assertEqual(m.read_source(self.repo), (None, True))

    def test_schedule_read_at_any_indent_and_in_flow_form(self):
        wf = self.repo / ".github/workflows/check.yml"
        for text in ("name: check\non:\n    schedule:\n      - cron: '1 2 * * *'\n",
                     "name: check\non: [push, schedule]\n", "name: check\n'on': {schedule: [{cron: x}]}\n"):
            wf.write_text(text)
            self.assertEqual(m.read_source(self.repo), ("acme/demo", True), text)
        wf.write_text("name: check\non: [push]\n")
        self.assertEqual(m.read_source(self.repo), (None, True))

    def test_core_unattended_marker_files_nothing(self):
        with patch.dict(os.environ, AUTOFINISH_CALLER_UNATTENDED="1"):
            self.assertEqual(self.poll(), [])
        self.assertEqual(self.calls, [])

    def test_wrong_shape_post_reply_spends_its_shot(self):
        real = self.api

        def api(method, path, body=None):
            st, res, why = real(method, path, body)
            return (st, [res], why) if method == "POST" else (st, res, why)
        self.ask.gh_api = api
        for _ in range(4):
            self.poll()
        # the POST was sent once; the next poll finds what it filed through its pin, never re-posts
        self.assertEqual(sum(c[0] == "POST" for c in self.calls), 1)
        self.assertEqual(len(self.issues), 1)
        self.assertEqual(m.read()["acme/demo"]["issue"], 1)
        self.assertEqual(len(m.cards()), 1)

    def test_reads_that_keep_failing_card_after_a_day(self):
        self.fail_path, self.fail_reply = "/actions/workflows/", (403, None, "HTTP 403")
        self.poll()
        row = m.read()["acme/demo"]
        self.assertEqual((row["conclusion"], row["red"]), ("unread", False))
        self.assertEqual(m.cards(), [])   # one blip is no card
        data = m.read()
        data["acme/demo"]["fault_since"] -= m.FAULT_CARD_AFTER + 60
        m.write(data)
        cards = m.cards()
        self.assertEqual(len(cards), 1)
        self.assertIn("unread for over a day", cards[0]["title"])
        self.fail_path = None   # GitHub answers again: the red is read as any new one
        self.poll()
        self.assertNotIn("fault_since", m.read()["acme/demo"])
        self.assertEqual(len(self.issues), 1)

    def test_repo_that_drops_its_schedule_expires(self):
        self.poll()
        (self.repo / ".github/workflows/check.yml").write_text("name: check\n")
        self.poll()
        self.assertEqual(self.issues[0]["state"], "closed")
        self.assertEqual(m.read(), {})

    def test_torn_cache_shows_one_card(self):
        self.cache.mkdir()
        m.cache_path().write_text("{")
        cards = m.cards()
        self.assertEqual([(c["kind"], c["title"]) for c in cards], [("main-red", "main check: cache unreadable")])

    def test_network_failure_stops_the_pass(self):
        second = self.make_repo("demo2")
        self.fail_path, self.fail_reply = "/actions/", (0, None, "URLError: timed out")
        notes = self.poll([self.repo, second])
        self.assertEqual(len(self.calls), 1)
        self.assertTrue(any("did not answer" in n for n in notes))
        # an HTTP refusal is no outage: the pass goes on (the second repo's call reaches the stub)
        self.fail_reply = (503, None, "HTTP 503")
        self.poll([self.repo, second])
        self.assertEqual(len(self.calls), 3)

    def test_issue_writes_are_bounded_per_run_and_keep_the_card(self):
        self.fail_path, self.fail_method = "/logbook/issues", "POST"
        posts = lambda: len([c for c in self.calls if c[0] == "POST"])
        for _ in range(4):
            self.poll()
        self.assertEqual(posts(), 2)
        card = m.cards()[0]
        self.assertIn("failed 2 times", card["rule"])
        self.runs = [self.run_row(2, "failure")]   # a new run is a new single shot
        self.poll()
        self.assertEqual(posts(), 3)
        self.fail_path = None
        self.runs = [self.run_row(3, "failure")]
        self.poll()
        self.assertEqual(len(self.issues), 1)
        self.assertNotIn("fault", m.read()["acme/demo"])

    def test_board_knows_the_kind(self):
        self.assertEqual(helm_render.QUEUE_GROUPS.get("main-red"), "unstick")
        self.assertIn("'main-red': ['bad', 'main red']", (ROOT / "modules/helm/bin/board.js").read_text())


    # -- the fix round's own review, round 1 (2026-11-05) ---------------------------------------------

    def test_pinned_logbook_that_answers_404_is_dropped_for_the_fixed_one(self):
        self.ask.logbook = lambda: ("acme/logbok", None)
        self.assertTrue(self.poll())
        self.ask.logbook = lambda: ("acme/logbook", None)
        self.poll()
        self.assertEqual([i["repo"] for i in self.issues], ["acme/logbook"])
        self.runs = [self.run_row(2, "success")]
        self.poll()
        self.assertEqual(m.cards(), [])
        self.assertEqual(self.issues[0]["state"], "closed")

    def test_typo_logbook_then_green_leaves_no_card(self):
        self.ask.logbook = lambda: ("acme/logbok", None)
        self.poll()
        self.runs = [self.run_row(2, "success")]
        self.poll()
        self.assertEqual(m.cards(), [])

    def test_renamed_origin_carries_its_row_and_a_green_closes_it(self):
        self.poll()
        subprocess.run(["git", "-C", str(self.repo), "remote", "set-url", "origin", "https://github.com/acme/demo-renamed.git"], check=True)
        api = self.api
        def renamed(method, path, body=None):
            return api(method, path.replace("/repos/acme/demo-renamed/", "/repos/acme/demo/"), body)
        self.ask.gh_api = renamed
        self.runs = [self.run_row(2, "success")]
        self.poll()
        self.assertEqual(self.issues[0]["state"], "closed")
        self.assertIn("Recovered", self.issues[0]["body"])
        self.assertEqual(list(m.read()), ["acme/demo-renamed"])
        self.assertEqual(m.cards(), [])

    def test_repo_back_in_the_poll_is_no_longer_expired(self):
        self.poll()
        other = self.make_repo("plain", schedule=False)
        self.fail_path = "/issues/1"
        self.poll([other])
        self.fail_path = None
        self.runs = [self.run_row(2, "failure")]
        self.poll()
        self.assertNotIn("expired", m.read()["acme/demo"])
        self.assertEqual(m.cards()[0]["title"], "main check: regatta, wharf-runs")

    def test_left_repo_with_a_lost_post_reply_finds_and_closes_it(self):
        api = self.api
        def lost(method, path, body=None):
            result = api(method, path, body)
            return (0, None, "URLError: timed out") if method == "POST" else result
        self.ask.gh_api = lost
        self.poll()
        self.assertEqual(len(self.issues), 1)
        self.assertNotIn("issue", m.read()["acme/demo"])
        self.ask.gh_api = api
        self.poll([self.make_repo("plain", schedule=False)])
        self.assertEqual(self.issues[0]["state"], "closed")
        self.assertEqual(m.read(), {})

    def test_failed_reads_spend_no_write_tries(self):
        self.fail_path, self.fail_reply = "/logbook/issues?", (0, None, "URLError: timed out")
        self.poll()
        self.poll()
        self.assertNotIn("write_tries", m.read()["acme/demo"])
        self.fail_path = None
        self.poll()
        self.assertEqual(len(self.issues), 1)

    def test_card_links_the_issue_as_github_gives_it(self):
        self.ask.logbook = lambda: ("Acme/Logbook", None)
        self.poll()
        self.assertEqual(m.cards()[0]["github"], "https://github.com/acme/logbook/issues/1")

    def test_shares_road_skipped_nightly_steps_are_not_cut(self):
        skipped = [{"name": "nightly %s" % n, "conclusion": "skipped"} for n in ("marketplace", "regatta", "keel")]
        self.jobs = [{"name": "check (the rest)", "conclusion": "success", "steps": [{"name": "check, the rest", "conclusion": "success"}] + skipped},
                     {"name": "suite (keel)", "conclusion": "failure", "steps": [{"name": "the suite", "conclusion": "failure"}]}]
        self.poll()
        self.assertIn("Failed: suite (keel) / the suite", self.issues[0]["body"])
        self.assertNotIn("Cut or not run", self.issues[0]["body"])
        # a setup failure names the setup step, not every suite it kept off
        self.assertEqual(m.results([{"name": "check", "conclusion": "failure", "steps":
                                     [{"name": "checkout", "conclusion": "failure"}] + skipped}]), (["check / checkout"], []))


    # -- build-review round 2 (2026-11-05) -------------------------------------------------------------

    def test_renamed_origin_while_red_keeps_its_issue(self):
        self.poll()
        subprocess.run(["git", "-C", str(self.repo), "remote", "set-url", "origin", "https://github.com/acme/demo-renamed.git"], check=True)
        api = self.api
        self.ask.gh_api = lambda method, path, body=None: api(method, path.replace("/repos/acme/demo-renamed/", "/repos/acme/demo/"), body)
        self.runs = [self.run_row(2, "failure")]
        self.poll()
        self.assertEqual(len(self.issues), 1)
        self.assertNotEqual(self.issues[0].get("state"), "closed")
        self.assertIn("<!-- helm:main-red:acme/demo-renamed -->", self.issues[0]["body"])
        self.assertEqual(list(m.read()), ["acme/demo-renamed"])
        self.runs = [self.run_row(3, "success")]
        self.poll()
        self.assertEqual(self.issues[0]["state"], "closed")
        self.assertIn("Recovered", self.issues[0]["body"])

    def test_check_yml_that_is_no_utf8_skips_that_repo_alone(self):
        bad = self.make_repo("latin", schedule=False)
        wf = bad / ".github/workflows/check.yml"
        wf.parent.mkdir(parents=True)
        wf.write_bytes(b"name: caf\xe9\n")
        self.poll([bad, self.repo])
        self.assertEqual(len(self.issues), 1)

    def test_fault_clears_once_github_answers(self):
        self.poll()
        self.fail_path, self.fail_reply = "/runs?", (0, None, "URLError: timed out")
        self.poll()
        self.assertEqual(m.cards()[0]["rule"], "URLError: timed out")
        self.fail_path = None
        self.runs = [self.run_row(2, "neutral")]
        self.poll()
        self.assertEqual(m.cards()[0]["rule"], "main's scheduled whole-line check")

    def test_removed_origin_expires_the_row(self):
        self.poll()
        subprocess.run(["git", "-C", str(self.repo), "remote", "remove", "origin"], check=True)
        self.poll()
        self.assertEqual(self.issues[0]["state"], "closed")
        self.assertIn("No longer read: demo left", self.issues[0]["body"])
        self.assertEqual(m.read(), {})


class Workflow(unittest.TestCase):
    def test_whole_line_runs_past_failure_and_stays_red(self):
        # Read the real workflow, including the canonical chain's brace/quote cuts.
        text = (ROOT / ".github/workflows/check.yml").read_text()
        canonical = re.search(r"      - name: check\n        if: ([^\n]+)\n        run: \|\n          ([^\n]+)", text)
        self.assertIsNotNone(canonical)
        # the check step's own condition, not a line anywhere in the file: it leaves the night to the steps
        self.assertTrue(canonical[1].startswith("github.event_name != 'schedule' && "), canonical[1])
        chain = canonical[2].split(" && ")
        steps = re.findall(r"      - name: nightly ([^\n]+)\n        if: ([^\n]+)\n        run: \|\n          ([^\n]+)", text)
        self.assertEqual([s[2] for s in steps], chain)
        self.assertEqual(len(steps), 14)
        # each step's name is the suite it runs, so a card's "Failed: wharf" means wharf's suite
        named = {"marketplace": "claude plugin validate --strict .", "regatta": "bash modules/regatta/tests/check.sh",
                 "regatta-classes": "bash modules/regatta/tests/classes.sh", "todo-md": "python3 modules/wharf/bin/todo-md lint ."}
        for name, _, command in steps:
            self.assertIn(named.get(name, "bash modules/%s/tests/check.sh" % name), command, name)
        # the setup gate: the last setup step carries the id the nightly conditions read, before any nightly step
        setup = text.index("        id: setup\n")
        self.assertLess(text.index("      - name: claude CLI\n"), setup)
        self.assertLess(text.index("      - name: a git identity for the suites' scratch commits\n"), setup)
        self.assertLess(setup, text.index("      - name: nightly "))
        with tempfile.TemporaryDirectory() as temp:
            top = Path(temp)
            log = top / "ran"
            binpath = top / "bin"
            binpath.mkdir()
            stub = binpath / "claude"
            stub.write_text('#!/bin/sh\n[ "$*" = "plugin validate --strict ." ] || exit 2\n' + "printf 'marketplace\\n' >> \"$SUITE_LOG\"\nexit 1\n")
            stub.chmod(0o755)
            for name, condition, command in steps:
                # never always(): not after a failed setup step, a cancel or the job's cut; and only where
                # the `check` step would run the whole line (a runner variable), so the twin runs it once
                self.assertEqual(condition, "${{ !cancelled() && github.event_name == 'schedule' && "
                                 "steps.setup.outcome == 'success' && (vars.CI_RUNS_ON || vars.CI_RUNS_ON_FULL) }}")
                self.assertNotIn("continue-on-error", command)
                script = re.search(r"bash (modules/[^ ;]+)", command)
                if script:
                    p = top / script[1]
                    p.parent.mkdir(parents=True, exist_ok=True)
                    p.write_text('[ "$#" -eq 0 ] || exit 2\n' + "printf '%s\\n' '" + name + "' >> \"$SUITE_LOG\"\n" + ("exit 1\n" if name == "regatta" else "exit 0\n"))
                if name in ("helm", "keel"):
                    p = top / "modules/keel/hooks/sheep_gate.py"
                    p.parent.mkdir(parents=True, exist_ok=True)
                    p.touch()
                if name == "todo-md":
                    (top / "TODO.md").touch()
                    p = top / "modules/wharf/bin/todo-md"
                    p.parent.mkdir(parents=True, exist_ok=True)
                    p.write_text("import os, sys\nassert sys.argv[1:] == ['lint', '.']\nopen(os.environ['SUITE_LOG'], 'a').write('todo-md\\n')\n")
            env = dict(os.environ, SUITE_LOG=str(log), PATH=str(binpath) + os.pathsep + os.environ["PATH"])
            # Actions starts each nightly step (`!cancelled()`, so past a red) in its own -e shell, and keeps any failure.
            codes = [subprocess.run(["bash", "-e", "-c", cmd], cwd=top, env=env).returncode for _, _, cmd in steps]
            self.assertTrue(any(codes))
            self.assertEqual(log.read_text().splitlines(), [s[0] for s in steps])


if __name__ == "__main__":
    unittest.main(verbosity=2)
