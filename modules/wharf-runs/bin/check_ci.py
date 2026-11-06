"""check's --ci road; internal, never a second command. Exit 75 asks check to run locally.

All subprocess output is captured: a refused remote may echo credentials. Only check names and
failed CI log lines are printed. A CI green never populates the local pass memory (different hosts).
"""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "lib"))
import core_path

MARK = "<!-- wharf-runs check --ci -->"
PR_FIELDS = "number,isDraft,headRefOid,body,baseRefName,isCrossRepository,labels"


class Unavailable(Exception):
    pass


def wip_title(branch):
    """`WIP: <topic>`, as checkpoint's open_wip_pr titles its PRs: helm's board reads a WIP title as
    a running build, any other as one waiting on the owner."""
    topic = re.sub(r"^\d{4}-\d{2}-\d{2}-", "", branch.rsplit("/", 1)[-1]).replace("-", " ")
    return "WIP: " + (topic or branch)


class CI:
    def __init__(self, wt, out, minutes, merge_main):
        self.wt, self.out = Path(wt), Path(out)
        self.minutes, self.merge_main = minutes, merge_main
        self.slug = None
        self.deadline = None

    def run(self, *args, ok=(0,), timeout=60, full=False):
        if self.deadline is not None:
            timeout = min(timeout, self.deadline - time.monotonic())
            if timeout <= 0:
                raise Unavailable("no CI verdict within --ci-wait")
        try:
            p = subprocess.run(args, cwd=self.wt, capture_output=True, text=True,
                               timeout=timeout, stdin=subprocess.DEVNULL,
                               env=dict(os.environ, GIT_TERMINAL_PROMPT="0", GH_PROMPT_DISABLED="1"))
        except (OSError, subprocess.TimeoutExpired):
            raise Unavailable("command could not answer") from None
        if p.returncode not in ok:
            raise Unavailable("command refused")
        return p if full else p.stdout.strip()

    def git(self, *args, **kwargs):
        return self.run("git", *args, **kwargs)

    def gh(self, *args, **kwargs):
        return self.run("gh", *args, "--repo", self.slug, **kwargs)

    def data(self, *args, **kwargs):
        try:
            return json.loads(self.gh(*args, **kwargs))
        except ValueError:
            raise Unavailable("CI response did not read") from None

    def say(self, line):
        line = self.scrub(line)
        print(line, flush=True)
        with (self.out / "summary").open("a") as f:
            f.write(line + "\n")

    @staticmethod
    def scrub(text):
        for key, value in os.environ.items():
            if re.search(r"TOKEN|SECRET|PASSWORD", key, re.I) and len(value) >= 4:
                text = text.replace(value, "***")
        return text

    def failed(self, why):
        self.say("FAILED " + why)
        return 1

    def fence(self):
        # One snapshot, every scope, judged by the core's own fence (fenced_scopes): the worktree and
        # its main checkout (a bare `<repo>/.bare` layout included), and guarded repos too.
        try:
            if not core_path.add():
                raise Unavailable("core missing; cannot judge confidentiality")
            import common
            reg, bad = common.read_registry()
            if bad:
                raise Unavailable("scope registry does not read")
            if common.fenced_scopes(str(self.wt), reg):
                raise Unavailable("confidential scope")
            return common
        except (ImportError, OSError, ValueError, TypeError, AttributeError):
            raise Unavailable("scope registry could not be judged") from None

    def required(self):
        # origin/main's rule, never the branch's own: a branch may not narrow what its green means
        # (the unattended local road reads origin/main's check line for the same reason).
        try:
            rule = json.loads(self.git("show", "origin/main:.github/main-protection.json"))["required_status_checks"]
            names = list(dict.fromkeys([r["context"] for r in rule.get("checks", [])] + rule.get("contexts", [])))
            if not names or not all(isinstance(n, str) and n for n in names):
                raise ValueError()
            return names
        except (Unavailable, OSError, ValueError, KeyError, TypeError):
            raise Unavailable("required checks do not read") from None

    def find_pr(self, branch):
        rows = self.data("pr", "list", "--head", branch, "--state", "open", "--json", PR_FIELDS)
        rows = [r for r in rows if r.get("baseRefName") == "main" and r.get("isCrossRepository") is False]
        if len(rows) > 1:
            raise Unavailable("ambiguous PR")
        return rows[0] if rows else None

    def hold(self, pr, common):
        original = body = pr.get("body") or ""
        owned = any(note in body for note in common.HOLD_NOTES)
        held = any(label.get("name") == "hold" for label in pr.get("labels", []))
        args = ["pr", "edit", str(pr["number"]), "--add-label", "hold"]
        if not held and not owned:
            # A pre-existing unmarked hold belongs to its owner. Claim only the label CI adds,
            # so /finish can release it without releasing a manual brake.
            body = body.rstrip() + "\n\n" + common.CI_HOLD_NOTE
        if pr.get("isDraft") and MARK not in body:
            # Persist CI provenance before readying a checkpoint draft. The next check may
            # need to merge main again; a ready PR without MARK looks curated by /finish.
            body = body.rstrip() + "\n\n" + MARK
        if body != original:
            body_file = self.out / "ci-pr.md"
            body_file.write_text(body + "\n")
            args += ["--body-file", str(body_file)]
        self.gh(*args)
        pr.update(body=body, labels=[{"name": "hold"}])

    def same_head(self, number, head, timeout=60):
        pr = self.data("pr", "view", str(number), "--json", "headRefOid,state", timeout=timeout)
        return pr.get("state") == "OPEN" and pr.get("headRefOid") == head and self.git("rev-parse", "HEAD") == head

    def failure_lines(self, row, index):
        link = row.get("link") or ""
        match = re.search(r"/actions/runs/(\d+)(?:/job/(\d+))?", link)
        if not match:
            return "failed log unavailable" + ("; " + link if link else "")
        args = ["run", "view", match[1], "--log-failed"]
        if match[2]:
            args += ["--job", match[2]]
        try:
            log = self.gh(*args)
        except Unavailable:
            return "failed log unavailable; " + link
        log = self.scrub(log)
        (self.out / ("ci-%02d.log" % index)).write_text(log + "\n")
        lines = [s.strip() for s in log.splitlines() if re.search(
            r"FAIL|error|Error|Assertion|Traceback|not ok|expected|fatal:", s)]
        return " | ".join(lines or log.splitlines()[-5:]) or "failed log empty"

    def wait(self, number, head, names):
        deadline = time.monotonic() + self.minutes * 60
        self.deadline = deadline
        print("check: CI PR #%s, head %s; waiting up to %s min" % (number, head[:12], self.minutes), flush=True)
        while time.monotonic() < deadline:
            budget = max(0.01, min(60, deadline - time.monotonic()))
            if not self.same_head(number, head, budget):
                return self.failed("CI head moved or PR closed; rerun check for the current head")
            # Under --json gh exits 0 with pending rows too (its exporter returns before the pending
            # error, cli/cli pkg/cmd/pr/checks/checks.go). A head with no context yet, as just after a
            # push, is exit 1 with no stdout and "no checks reported" on stderr: pending, never a
            # fallback. Other malformed output is no verdict. Missing required contexts must still wait.
            p = self.run("gh", "pr", "checks", str(number), "--json", "name,bucket,link", "--repo", self.slug,
                         ok=(0, 1, 8), timeout=budget, full=True)
            if p.returncode == 1 and not p.stdout.strip() and "no checks reported" in p.stderr:
                rows = []
            else:
                try:
                    rows = json.loads(p.stdout)
                except ValueError:
                    raise Unavailable("CI response did not read") from None
            groups = [[r for r in rows if r.get("name") == n] for n in names]
            # A required failure is already a red verdict, even with another context pending
            # or absent. Waiting for both would let a timeout erase it via a local fallback.
            failed = any(r.get("bucket") in {"fail", "cancel", "skipping"} for g in groups for r in g)
            terminal = {"pass", "fail", "cancel", "skipping"}
            if rows and (failed or all(g and all(r.get("bucket") in terminal for r in g) for g in groups)):
                if not failed and not self.same_head(number, head, budget):
                    return self.failed("CI head moved or PR closed; rerun check for the current head")
                passed = sum(bool(g) and all(r["bucket"] == "pass" for r in g) for g in groups)
                if passed == len(names):
                    for n in names:
                        self.say(time.strftime("%H:%M") + " rc=0 0s CI " + n)
                    # what the contract's line runs and CI's never does (the publish gate): said, as the
                    # local road says a branch-only command, and exit 3 (check's UNRUN road)
                    unrun = [c for c in os.environ.get("CHECK_CI_UNRUN", "").split("\n") if c.strip()]
                    for c in unrun:
                        self.say("UNRUN " + c)
                    self.say("DONE %d/%d" % (passed, len(names)))
                    return 3 if unrun else 0
                failures = [r for r in rows if r.get("bucket") in {"fail", "cancel"}
                            or (r.get("name") in names and r.get("bucket") == "skipping")]
                for i, row in enumerate(failures, 1):
                    self.say(time.strftime("%H:%M") + " rc=1 0s CI " + row["name"] + " — " + self.failure_lines(row, i))
                return self.failed("%d/%d CI checks passed" % (passed, len(names)))
            time.sleep(min(15, max(0, deadline - time.monotonic())))
        raise Unavailable("no CI verdict within --ci-wait")

    def check(self):
        common = self.fence()  # before gh, fetch, push or any PR mutation
        if not shutil.which("gh"):
            raise Unavailable("no gh")
        branch = self.git("symbolic-ref", "--quiet", "--short", "HEAD")
        if not branch.startswith("claude/"):
            raise Unavailable("CI needs this worktree's own claude/* branch")
        if self.git("status", "--porcelain"):
            raise Unavailable("uncommitted work is not on the CI head")
        self.slug = common.repo_slug(self.git("remote", "get-url", "origin"))
        if not self.slug:
            raise Unavailable("origin is not a GitHub repo")
        pr = self.find_pr(branch)
        if not pr and self.data("pr", "list", "--head", branch, "--state", "merged", "--base", "main",
                                "--json", "number"):
            # a spent worktree: pushing would recreate the deleted branch and open a stale PR
            raise Unavailable("branch already landed")
        self.git("fetch", "--no-tags", "origin", "+refs/heads/main:refs/remotes/origin/main")
        names = self.required()
        base = self.git("merge-base", "origin/main", "HEAD")
        needs_merge = base != self.git("rev-parse", "origin/main")
        if needs_merge:
            body = (pr or {}).get("body") or ""
            ready = pr and not pr.get("isDraft") and ("curated by `/finish`" in body
                     or (MARK not in body and common.HOLD_NOTE not in body))
            if ready and not self.merge_main:
                # never merge main into a ready PR (it leaves it unlandable); no fix clears this,
                # so it is no red verdict: the local line answers instead
                raise Unavailable("PR readied by /finish and main moved")
        # Ensure the label exists; an already-existing label returns nonzero. hold()/create
        # must themselves succeed, so a network/auth failure cannot leave a ready PR unheld.
        self.gh("label", "create", "hold", "--color", "B60205", "--description", "automerge stays off while set", ok=(0, 1))
        if pr:
            self.hold(pr, common)  # before any push: an existing ready PR must not automerge
        if needs_merge:
            try:
                self.git("merge", "--no-edit", "origin/main")
            except Unavailable:
                files = self.git("diff", "--name-only", "--diff-filter=U").splitlines()
                try:
                    self.git("merge", "--abort")
                except Unavailable:
                    return self.failed("merge of origin/main could not be aborted; inspect the worktree")
                return self.failed("merge of origin/main conflicted: " + ", ".join(files))
        head = self.git("rev-parse", "HEAD")
        self.git("push", "origin", "HEAD:refs/heads/" + branch)
        if not pr:
            body_file = self.out / "ci-pr.md"
            body_file.write_text("Build check through PR CI. `/finish` still curates and lands this branch.\n\n"
                                 + MARK + "\n\n" + common.CI_HOLD_NOTE + "\n")
            # a draft first: gh adds the label in a second call, and a ready PR whose label call failed
            # would be armed by automerge; hold() then labels it and only then is it readied
            self.gh("pr", "create", "--draft", "--head", branch, "--base", "main", "--label", "hold",
                    "--title", wip_title(branch), "--body-file", str(body_file))
            pr = self.find_pr(branch)
        if not pr:
            raise Unavailable("no open PR")
        self.hold(pr, common)
        if pr.get("isDraft"):
            self.gh("pr", "ready", str(pr["number"]))  # held before leaving draft
        return self.wait(pr["number"], head, names)


def main():
    ci = CI(sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4] == "1")
    try:
        return ci.check()
    except (Unavailable, OSError, ValueError, TypeError, KeyError, AttributeError) as e:
        # Do not echo arbitrary exception messages (subprocess errors may contain a remote URL).
        why = str(e) if isinstance(e, Unavailable) else "CI response did not read"
        print("check: CI unavailable (%s); falling back to local check" % why, flush=True)
        return 75


if __name__ == "__main__":
    sys.exit(main())
