"""check's --ci road; internal, never a second command. Exit 75 asks check to run locally.

All subprocess output is captured: a refused remote may echo credentials. Only check names and
failed CI log lines are printed. A CI green never populates the local pass memory (different hosts).
"""
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "lib"))
import core_path

MARK = "<!-- wharf-runs check --ci -->"
PR_FIELDS = "number,isDraft,headRefOid,body,baseRefName,isCrossRepository,labels"
# check owns this explicit list: CI has no private word list. Match contract commands exactly,
# never infer local work from a filename. These cheap commands run beside CI, without a slot.
LOCAL_COMMANDS = ("python3 modules/helloworld/bin/helloworld check . --ref HEAD",)


class Unavailable(Exception):
    pass


def wip_title(branch):
    """Match checkpoint's WIP titles, which helm reads as a running build."""
    topic = re.sub(r"^\d{4}-\d{2}-\d{2}-", "", branch.rsplit("/", 1)[-1]).replace("-", " ")
    return "WIP: " + (topic or branch)


class CI:
    def __init__(self, wt, out, minutes, merge_main, reuse_only=False):
        self.wt, self.out = Path(wt), Path(out)
        self.minutes, self.merge_main = minutes, merge_main
        self.slug = None
        self.deadline = None
        self.reuse_only = reuse_only
        self.local_head = None
        self.ci_passed = 0
        self.defer_failure = False
        self.failure = None
        self.existing_red = False

    def run(self, *args, ok=(0,), timeout=60, raw=False):
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
        return p if raw else p.stdout.strip()

    def git(self, *args, **kwargs):
        return self.run("git", *args, **kwargs)

    def gh(self, *args, **kwargs):
        return self.run("gh", *args, "--repo", self.slug, **kwargs)

    def data(self, *args, **kwargs):
        try:
            return json.loads(self.gh(*args, **kwargs))
        except ValueError:
            raise Unavailable("CI response did not read") from None

    def checks(self, number, timeout=60):
        p = self.gh("pr", "checks", str(number), "--json", "name,bucket,link",
                    ok=(0, 1, 8), timeout=timeout, raw=True)
        # Before CI starts, gh exits 1 with this diagnostic and no JSON. Treat only that
        # response as missing contexts: auth/network errors must still fall back locally.
        if p.returncode == 1 and not p.stdout.strip() and re.fullmatch(
                r"no checks reported on the '[^\r\n]+' branch", p.stderr.strip()):
            return []
        try:
            rows = json.loads(p.stdout)
        except ValueError:
            raise Unavailable("CI response did not read") from None
        if not isinstance(rows, list) or not all(isinstance(row, dict) for row in rows):
            raise Unavailable("CI response did not read")
        return rows

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
        self.failure = why
        if not self.defer_failure:
            self.say("FAILED " + why)
        return 1

    def fence(self):
        # One snapshot, every scope, judged by the core's own fence: the worktree and its main
        # checkout (a bare `<repo>/.bare` layout included), and guarded repos too.
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
        # Main's rule, never the branch's: a branch may not narrow what its green means.
        try:
            text = self.git("show", "origin/main:.github/main-protection.json", ok=(0, 128))
            if text:
                rule = json.loads(text)["required_status_checks"]
            else:
                # gh api takes a repository in its endpoint, not a --repo option.
                rule = json.loads(self.run("gh", "api", "repos/%s/branches/main/protection/required_status_checks" % self.slug))
            names = list(dict.fromkeys([r["context"] for r in rule.get("checks", [])] + rule.get("contexts", [])))
            if not names:
                raise Unavailable("no required checks")
            if not all(isinstance(n, str) and n for n in names):
                raise ValueError()
            return names
        except (OSError, ValueError, KeyError, TypeError):
            raise Unavailable("required checks do not read") from None

    def workflow(self):
        # Recognise the ordinary event block, scalar and flat list without a YAML dependency.
        # An unfamiliar flow mapping is no answer; never mistake a nested branch name for an event.
        try:
            for path in (self.wt / ".github/workflows").glob("*"):
                if path.suffix not in {".yml", ".yaml"}:
                    continue
                block = False
                indent = None
                for line in path.read_text().splitlines():
                    line = line.split("#", 1)[0].rstrip()
                    if not line.strip():
                        continue
                    on = re.fullmatch(r'''(?:on|'on'|"on"): *(.*)''', line)
                    if on:
                        value = on[1].strip()
                        if value.strip("'\"") == "pull_request":
                            return
                        if value.startswith("[") and value.endswith("]"):
                            if "pull_request" in [v.strip().strip("'\"") for v in value[1:-1].split(",")]:
                                return
                        block = not value
                        continue
                    if block:
                        depth = len(line) - len(line.lstrip())
                        if depth == 0:
                            block = False
                        else:
                            if indent is None:
                                indent = depth
                            if depth == indent and re.fullmatch(r'''(?:pull_request|'pull_request'|"pull_request"):.*''', line.strip()):
                                return
        except (OSError, ValueError):
            raise Unavailable("PR workflow does not read") from None
        raise Unavailable("no PR workflow")

    def local_commands(self):
        texts = [(self.wt / "AGENTS.md").read_text()]
        if os.environ.get("CLAUDE_UNATTENDED"):
            text = self.git("show", "origin/main:AGENTS.md", ok=(0, 128))
            if not text:
                text = self.git("show", "main:AGENTS.md")
            # Keep main's obligations and include gates the branch adds. Only commands on
            # check's explicit list may run here; this never executes arbitrary branch text.
            texts.insert(0, text)
        commands = []
        for text in texts:
            for line in text.splitlines():
                if line.startswith("- check:"):
                    match = re.match(r"- check: `([^`]+)`", line)
                    if not match:
                        raise Unavailable("check contract is not a command line")
                    commands.extend(c.strip() for c in match[1].split(" && ") if c.strip() in LOCAL_COMMANDS)
                    break
            else:
                raise Unavailable("no check contract")
        return list(dict.fromkeys(commands))

    def green(self, pr, names):
        """Read only: reuse a green on this exact tree, including a curated commit rewrite."""
        if not pr or pr.get("isDraft"):
            return False
        head = pr.get("headRefOid")
        if not head or not re.fullmatch(r"[0-9a-f]{40,64}", head):
            return False
        tree = self.git("rev-parse", "HEAD^{tree}")
        if self.git("rev-parse", head + "^{tree}", ok=(0, 128)) != tree:
            return False
        rows = self.checks(pr["number"])
        groups = [[r for r in rows if r.get("name") == n] for n in names]
        green = all(g and all(r.get("bucket") == "pass" for r in g) for g in groups)
        red = any(r.get("bucket") in {"fail", "cancel", "skipping"} for g in groups for r in g)
        if (green or red) and self.same_head(pr["number"], head):
            self.existing_red = red
            return green
        return False

    def complete(self, number, head, names, commands, reused=False):
        jobs = []
        self.defer_failure = True
        if self.reuse_only:
            print("logs: " + str(self.out), flush=True)
        try:
            for i, command in enumerate(commands, 1):
                log = (self.out / ("local-%02d-helloworld.log" % i)).open("w")
                try:
                    p = subprocess.Popen(shlex.split(command), cwd=self.wt, stdout=log, stderr=log,
                                         stdin=subprocess.DEVNULL)
                finally:
                    log.close()
                jobs.append((command, p, time.monotonic()))
            if reused:
                self.ci_passed = len(names)
                self.say("PASSED " + time.strftime("%Y-%m-%d %H:%M") + " CI")
                rc = 0
            else:
                rc = self.wait(number, head, names, finish=False)
        finally:
            # Even an unavailable CI verdict must leave no private gate running in the background.
            local_passed = 0
            for command, p, start in jobs:
                code = p.wait()
                local_passed += code == 0
                self.say(time.strftime("%H:%M") + " rc=%d %ds %s" % (code, time.monotonic() - start, command))
            self.defer_failure = False
            self.deadline = None
        if rc:
            if commands:
                return self.failed("%d/%d checks passed; %s" %
                                   (self.ci_passed + local_passed, len(names) + len(commands), self.failure))
            return self.failed(self.failure or "CI checks failed")
        if not self.same_head(number, head) or self.git("status", "--porcelain"):
            return self.failed("CI head moved or worktree changed; rerun check")
        passed, total = self.ci_passed + local_passed, len(names) + len(commands)
        if passed != total:
            return self.failed("%d/%d checks passed (local inputs included)" % (passed, total))
        unrun = list(dict.fromkeys(c for c in os.environ.get("CHECK_CI_UNRUN", "").splitlines()
                                  if c.strip() and c not in commands))
        for command in unrun:
            self.say("UNRUN " + command)
        self.say("DONE %d/%d" % (passed, total))
        return 3 if unrun else 0

    def find_pr(self, branch):
        rows = self.data("pr", "list", "--head", branch, "--state", "open", "--json", PR_FIELDS)
        rows = [r for r in rows if r.get("baseRefName") == "main" and r.get("isCrossRepository") is False]
        if len(rows) > 1:
            raise Unavailable("ambiguous PR")
        return rows[0] if rows else None

    @staticmethod
    def launched(pr):
        """Ready, curated by `/finish`'s `pr ready`, and no `hold` label on it."""
        return (not pr.get("isDraft") and "curated by `/finish`" in (pr.get("body") or "")
                and not any(label.get("name") == "hold" for label in pr.get("labels") or []))

    def hold(self, pr, common):
        original = body = pr.get("body") or ""
        owned = any(note in body for note in common.HOLD_NOTES)
        held = any(label.get("name") == "hold" for label in pr.get("labels", []))
        args = ["pr", "edit", str(pr["number"]), "--add-label", "hold"]
        if not held and not owned:
            # A pre-existing unmarked hold belongs to its owner. Claim only the label CI adds,
            # so /finish can release it without releasing a manual brake.
            body = body.rstrip() + "\n\n" + common.CI_HOLD_NOTE
        if (pr.get("isDraft") or not held) and MARK not in body:
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
        return (pr.get("state") == "OPEN" and pr.get("headRefOid") == head
                and self.git("rev-parse", "HEAD") == (self.local_head or head))

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

    def wait(self, number, head, names, finish=True):
        deadline = time.monotonic() + self.minutes * 60
        self.deadline = deadline
        print("check: CI PR #%s, head %s; waiting up to %s min" % (number, head[:12], self.minutes), flush=True)
        while time.monotonic() < deadline:
            budget = max(0.01, min(60, deadline - time.monotonic()))
            if not self.same_head(number, head, budget):
                return self.failed("CI head moved or PR closed; rerun check for the current head")
            # gh returns 8 for pending checks and 1 for failures or no checks yet. Missing
            # required contexts wait; malformed output and command errors are unavailable.
            rows = self.checks(number, timeout=budget)
            groups = [[r for r in rows if r.get("name") == n] for n in names]
            # A required failure is already a red verdict, even with another context pending
            # or absent. Waiting for both would let a timeout erase it via a local fallback.
            failed = any(r.get("bucket") in {"fail", "cancel", "skipping"} for g in groups for r in g)
            terminal = {"pass", "fail", "cancel", "skipping"}
            if failed or all(g and all(r.get("bucket") in terminal for r in g) for g in groups):
                if not failed and not self.same_head(number, head, budget):
                    return self.failed("CI head moved or PR closed; rerun check for the current head")
                passed = sum(bool(g) and all(r["bucket"] == "pass" for r in g) for g in groups)
                self.ci_passed = passed
                if passed == len(names):
                    for n in names:
                        self.say(time.strftime("%H:%M") + " rc=0 0s CI " + n)
                    if finish:
                        self.say("DONE %d/%d" % (passed, len(names)))
                    return 0
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
        self.workflow()
        branch = self.git("symbolic-ref", "--quiet", "--short", "HEAD")
        if not branch.startswith("claude/"):
            raise Unavailable("CI needs this worktree's own claude/* branch")
        if self.git("status", "--porcelain"):
            raise Unavailable("uncommitted work is not on the CI head")
        self.slug = common.repo_slug(self.git("remote", "get-url", "origin"))
        if not self.slug:
            raise Unavailable("origin is not a GitHub repo")
        names = self.required()
        commands = self.local_commands()
        self.local_head = self.git("rev-parse", "HEAD")
        pr = self.find_pr(branch)
        if self.green(pr, names):
            return self.complete(pr["number"], pr["headRefOid"], names, commands, reused=True)
        if self.reuse_only:
            raise Unavailable("no matching CI green")
        if self.existing_red:
            return self.complete(pr["number"], pr["headRefOid"], names, commands)
        if not pr and self.data("pr", "list", "--head", branch, "--state", "merged", "--base", "main",
                                "--json", "number"):
            # A spent worktree must not recreate its deleted branch or open a stale PR.
            raise Unavailable("branch already landed")
        self.git("fetch", "--no-tags", "origin", "+refs/heads/main:refs/remotes/origin/main")
        names = self.required()
        base = self.git("merge-base", "origin/main", "HEAD")
        needs_merge = base != self.git("rev-parse", "origin/main")
        if needs_merge:
            if self.merge_main == "never":
                return self.failed("main moved; use /finish to rebase before CI")
            body = (pr or {}).get("body") or ""
            ready = pr and not pr.get("isDraft") and ("curated by `/finish`" in body
                     or (MARK not in body and common.HOLD_NOTE not in body))
            if ready and not self.merge_main:
                raise Unavailable("PR readied by /finish and main moved")
        if pr and self.launched(pr) and not self.merge_main:
            # A PR `/finish` launched: `pr ready` spent CI's hold, and nothing would take a new one
            # off, so holding it again turns automerge off for good. Its own head is only waited on;
            # a newer local tip is held first by `pr hold` (/finish 11.2), or checked here.
            if pr.get("headRefOid") == self.local_head:
                return self.complete(pr["number"], pr["headRefOid"], names, commands)
            raise Unavailable("PR launched by /finish is unheld; `pr hold` first")
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
        head = self.local_head = self.git("rev-parse", "HEAD")
        commands = self.local_commands()  # a build merge may have changed the contract
        self.git("push", "origin", "HEAD:refs/heads/" + branch)
        if not pr:
            body_file = self.out / "ci-pr.md"
            body_file.write_text("Build check through PR CI. `/finish` still curates and lands this branch.\n\n"
                                 + MARK + "\n\n" + common.CI_HOLD_NOTE + "\n")
            # gh labels in a second call; a failed label call must leave a draft, never arm automerge.
            self.gh("pr", "create", "--draft", "--head", branch, "--base", "main", "--label", "hold",
                    "--title", wip_title(branch), "--body-file", str(body_file))
            pr = self.find_pr(branch)
        if not pr:
            raise Unavailable("no open PR")
        self.hold(pr, common)
        if pr.get("isDraft"):
            self.gh("pr", "ready", str(pr["number"]))  # held before leaving draft
        return self.complete(pr["number"], head, names, commands)


def main():
    merge = "never" if sys.argv[4] == "never" else sys.argv[4] == "1"
    ci = CI(sys.argv[1], sys.argv[2], int(sys.argv[3]), merge, len(sys.argv) > 5 and sys.argv[5] == "reuse")
    try:
        return ci.check()
    except (Unavailable, OSError, ValueError, TypeError, KeyError, AttributeError) as e:
        # Do not echo arbitrary exception messages (subprocess errors may contain a remote URL).
        why = str(e) if isinstance(e, Unavailable) else "CI response did not read"
        if not ci.reuse_only:
            print("check: CI unavailable (%s); falling back to local check" % why, flush=True)
        return 75


if __name__ == "__main__":
    sys.exit(main())
