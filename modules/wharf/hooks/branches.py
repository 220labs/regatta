#!/usr/bin/env python3
"""Which `claude/*` branches are done, and which never launched — read-only, for `sync.py` at
session start, `bin/repos --branches`, `bin/pr` and Aurora's weekly dream.

The gap this fills (the home repo, 2026-09-24): a branch whose content reached `main` through
ANOTHER branch's pull request — carried across when a session merged a sibling's live drift —
keeps its own branch and PR, because GitHub deletes only the merged PR's head and an agent may
never delete a branch. And a branch that never launched at all (a session that ended without
`/finish`) was invisible for five days: `bin/repos` said what was not on origin, never what
was not on `main`. Nothing here decides a deletion by itself: archive() acts on the "launched"
group, and — since docs/record/branch-reaping-2026-10-04.md — on two more, past REAP_AFTER idle:
empty branches (empty(): nothing committed, or a seed with nothing after it; an unstarted seed
after SEED_TTL), and superseded ones, every commit's patch on main — C1 with every added line
there too, C2 (`bin/repos --branches --classify --reap` only) with up to 2 % of its lines gone,
removed by main after it took the patches, so still in main's history. Only when sync.py or that flag calls it
(The owner, 2026-09-26: branches are a last-resort backup and managing them is never the owner's job —
coding-on-workflow D4–D6). An archived branch is moved to `refs/archive/…` with a reason, its
GitHub copy removed, and the archive pruned after ARCHIVE_TTL. No paste reaches the owner any more.

Three groups, and only the first is archived by the hooks — a wrong "launched" costs real
work, so it rests on proof that cannot be wrong:

  launched   (a) every tip of the branch, local and on origin, is an ancestor of origin/main; or
             (b) every path the branch changed since its merge-base — deletions, renames and
                 submodule links included — has the same `ls-tree` entry (mode and blob) on
                 origin/main; a branch with no net change against main passes (b) vacuously.
             A line in `<common git dir>/claude/landed` (LANDED_NAME; S4 moves it to `launched`, both read), written by `bin/pr merge`
             only AFTER (a)/(b) held for that branch, counts while every current tip of the branch
             is still an ancestor of the commit the line names (the branch has not moved since).
  probably   `git cherry` finds a patch-equivalent for every commit (only when the branch has no
  launched   merge commits — cherry skips those), or the whole diff applies to origin/main's tree
             in reverse (never for a diff with a mode change). Both are fooled by whitespace, an
             edit to the second of two identical blocks, or a later edit to the same lines
             (review of 2026-09-24), so this group is a hint to check, never a command.
  not on     everything else, with age, files and PR.
  main

A worktree with uncommitted work vetoes both launched groups (a site repo, 2026-09-25: pickup said
"landed: merged" of a branch whose commits were all on main while its worktree held the real
remaining edit). The proofs above speak for commits, never for a working tree: a worktree with a
modified, staged or untracked file that is not ignored — or whose status git could not read —
puts its branch in "not on main", with the count and the proof its commits had.

Launched is a fact about content; finished is another question (the owner, 2026-09-25: "a proposal
was built and pushed on main but never implemented"). For every launched or probably-launched
branch, evidence() reads the .md files it changed as they stand on origin/main and counts what
the repo's own conventions mark as unfinished: unstruck list items under a heading matching
open / still manual / not built / deferred / ideas not built, `➤ Answer:` lines with no
`> **Done.**` (or Applied, Superseded, Revised, Checked) reply beneath, and TODO.md lines naming those files or the branch's topic. The
result rides beside the proof — "open items: docs/x.md (3)" or "no open items found". Open items
are not lost by archiving: they live in files already on main.

A carries record (`.git/…/claude/carries`, written by checkpoint.py when a session took content
from another branch) is a POINTER, never proof: a merge refused on a dirty tree, a resolution
that dropped a file, `merge --abort` and `merge -s ours` all leave the same record (second
review, 2026-09-24). It only annotates a branch outside the launched group: "carried by <branch>
(whole|part), not proved", so a reader knows where to look. When sync.py removes a merged
worktree, its record moves to the common dir's `carried` file first and is read from there.

Bounded on purpose: only branches idle longer than IDLE_AFTER are examined (a young branch is
somebody's live work), a branch held by a worktree whose lock is fresh is skipped, a diff above
MAX_REVERSE_BYTES is not reverse-applied, and the caller may pass a deadline after which the
rest come back unchecked. Stdlib only; every git call has a timeout; any git failure — a
timeout, an argv too long, a bad ref — is "not proved", never "nothing changed".
"""
import calendar
import json
import os
import re
import shlex
import subprocess
import sys
import tempfile
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
CORE_MISSING = ("regatta core not found — clone the regatta repo, then write the config dir "
                "(the core's install.sh, or the overlay's bootstrap.sh --config)")
try:
    sys.path.insert(1, str(Path(__file__).resolve().parent.parent / "lib"))
    import core_path  # noqa: E402 — the regatta core's hooks/ on the path (C2), or nothing
    core_path.add()
    import common  # noqa: E402 — the GitHub client, shared with checkpoint.py, sync.py and bin/pr
except Exception as exc:  # a broken core as well as a missing one: never exit 1
    # No core (docs/regatta-modules-2026-10-16.md C4). Imported — by sync.py, bin/pr, bin/repos,
    # bin/pickup — the error goes to the importer, which says it its own way (sync.py: one quiet
    # line; a CLI: its traceback, a failure it must not hide). Run as a script: one line, exit 0.
    if __name__ != "__main__":
        raise
    print(f"branches: {CORE_MISSING} ({exc})", file=sys.stderr)
    sys.exit(0)

IDLE_AFTER = 24 * 3600
LOCK_TTL = common.OWNER_TTL  # a lock idle this long has gone
MAX_REVERSE_BYTES = 400_000
GIT_TIMEOUT = 20
LS_TREE_CHUNK = 500  # paths per ls-tree call: tens of thousands in one argv is E2BIG
SESSION_NOTE_MAX = 6  # entries per group in the session-start note; the CLI shows all
CARRIES_NAME = "carries"  # per worktree: `<kind> <sha> <branch>` per line — written by checkpoint.py
LANDED_NAME = "landed"  # per repo (common git dir): `<branch> <sha> via #N <date>` — by bin/pr merge
# Rename S2 (docs/wharf-rename-2026-10-16.md, M5): bin/pr merge writes here from S4; readers take
# this file first, then LANDED_NAME, forever — the old file is never moved (launched_lines()).
LAUNCHED_NAME = "launched"
# per repo (common git dir): `<carrier> <kind> <sha> <branch>` — the carries record of a worktree
# sync.py removed, kept so the pointer outlives the worktree (sync.carries_open, 2026-09-29)
CARRIED_NAME = "carried"
ARCHIVE_NAME = "archived"  # per repo (common git dir): `<date> <sha> <ref> <reason>[ · pruned <date>]`
ARCHIVE_TTL_DAYS = 7  # the owner, 2026-09-26: "stick around as an archive for a week, then get pruned"
# pickup archive --confirmed; agents are denied it. The person is the core's owner key (the same
# words as before the scrub on the owner's Macs), else "the owner".
WHO = common.OWNER_NAME or "the owner"   # the person the lists and the archive reason name
CONFIRMED = f"Probably launched, confirmed by {WHO}"
WHOLE_KINDS = {"merge", "rebase"}  # the carry kinds that meant to take a whole branch
# --ignore-submodules=none: with diff.ignoreSubmodules=all set, a gitlink the branch added
# would vanish from the changed paths and an empty list reads as "no net change" (review).
DIFF_FLAGS = ("--no-ext-diff", "--no-color", "--no-textconv", "--ignore-submodules=none",
              "--src-prefix=a/", "--dst-prefix=b/")
EVIDENCE_MAX_FILES = 12  # .md files read per branch for the finished-or-not check
# Headings under which a list item means "not done yet" — the repo's own vocabulary, widened
# after the fourth review found `## Still to do`, `## Next steps`, `## TODO` unread.
OPEN_HEADING_RE = re.compile(r"open|still (?:manual|to do)|to ?do|next|remaining|pending|follow|later"
                             r"|phase|unresolved|not built|deferred|ideas", re.I)
HEADING_RE = re.compile(r"^#{1,6}\s")
BOLD_HEADING_RE = re.compile(r"^\s*\*\*[^*]+\*\*\s*$")  # `**Open items**` alone on a line
ITEM_RE = re.compile(r"^\s*(?:[-*+]|\d+[.)])\s+(.*)$")
STRUCK_RE = re.compile(r"^(?:~~.*~~\s*$|\[x\]|done\b|✅)", re.I)  # an item that is finished
ANSWER_RE = re.compile(r"➤\s*Answer:")
CODE_SPAN_RE = re.compile(r"`[^`]*`")  # `➤ Answer:` in a code span is prose about the shape
OPTION_RE = re.compile(r"^\*{0,2}([A-Z])\*{0,2}\s*[—–-]\s")  # a bulleted option, `- A — …`
# A D-item line as agents write one (bin/keel's ITEM_RE, bold or list-led): its options follow it.
D_ITEM_RE = re.compile(r"^\s*(?:(?:[-*]|\d+\.)\s+)?\*{0,2}D\d+\*{0,2}\s*[—–\-.:]")
REC_RE = re.compile(r"^\s*(?:(?:[-*]|\d+\.)\s+)?➤\s*Recommended:")


def asks_answer(line):
    return bool(ANSWER_RE.search(CODE_SPAN_RE.sub("", line)))


# The reply that settles an answer (the rules on working with the owner, "How to talk"): `> **Done.** …`,
# or the verbs the digests also use for one — Applied, Superseded, Revised, Checked
# (docs/record/architect-process-2026-10-04.md; memo-lint-fixes, 2026-10-05).
DONE_REPLY_RE = re.compile(r"^\s*>\s*\*\*(?:Done|Applied|Superseded|Revised|Checked)\.\*\*")
# Seeds (`pickup seed`, docs/record/followup-handoff-2026-09-29.md): one home for what a seed commit is;
# bin/pickup imports these (docs/record/branch-reaping-2026-10-04.md E1, R7).
SEED_SUBJECT = "Seed: "
SEEDED_BY_RE = re.compile(r"^Seeded-By: (.+?)\s*$", re.M)  # "<repo>/<session id8> on <host>"
HANDOFF_DIR = "docs/handoff"
# A seed also carries the handoff as a one-block blueprint, docs/blueprints/<date>-<topic>.md, beside
# its brief (wharf-on-orca S5, B9): a path there is still "nothing a session wrote" in a seed.
BLUEPRINT_DIR = "docs/blueprints"
# Reaping (docs/record/branch-reaping-2026-10-04.md): an empty branch, or one whose work code proves is
# on main, goes after this long untouched — the grace the owner chose on 2026-09-29 (== sync.py's
# UNPUSHED_GRACE) — and a seed nobody started after SEED_TTL (the owner's D1 = B, 2026-10-04).
REAP_AFTER = 7 * 86400
SEED_TTL = 14 * 86400
MOVED_SHARE = 0.98  # C2: share of a branch's added lines found anywhere on main
DOC_SHARE = 0.90  # C5: share of a doc-only branch's added lines found in main's .md files
MAIN_BLOB_MAX = 2_000_000  # main_lines(): text blobs above this are not read
EMPTY_NEVER = "seed never started"  # the one empty reason that waits SEED_TTL, not REAP_AFTER


def git(repo, *args, input=None, timeout=GIT_TIMEOUT, env=None, text=True):
    try:
        return subprocess.run(["git", "-C", str(repo), *args], input=input, capture_output=True,
                              text=text, timeout=timeout, env=env)
    except subprocess.TimeoutExpired:
        return subprocess.CompletedProcess(args, 124, "" if text else b"", "timeout")
    except OSError as exc:  # E2BIG, ENOENT…: a failure, not an answer
        return subprocess.CompletedProcess(args, 1, "" if text else b"", str(exc))


def out(repo, *args, **kw):
    r = git(repo, *args, **kw)
    return r.stdout.strip() if r.returncode == 0 else ""


def main_branch(repo):
    """The branch the primary checkout rests on: workflow.json's `main`, else `main`."""
    for root in (Path(repo), common_dir(repo).parent):
        try:
            return json.loads((root / ".claude" / "workflow.json").read_text()).get("main") or "main"
        except (OSError, ValueError, AttributeError):
            continue
    return "main"


def common_dir(repo):
    return Path(out(repo, "rev-parse", "--path-format=absolute", "--git-common-dir") or (Path(repo) / ".git"))


def age(seconds):
    if seconds < 3600:
        return "<1 h"
    if seconds < 48 * 3600:
        return f"{int(seconds // 3600)} h"
    return f"{int(seconds // 86400)} d"


def is_ancestor(repo, commit, of):
    return git(repo, "merge-base", "--is-ancestor", commit, of).returncode == 0


class Branch:
    def __init__(self, name):
        self.name = name
        self.local = None  # sha
        self.remote = None  # sha on origin
        self.when = 0  # last commit, unix (the later of the two tips)
        self.worktree = None  # path of the worktree holding it, if any
        self.live = False  # that worktree's lock is fresh
        self.proof = None  # why it counts as launched / probably launched, or None
        self.checked = True  # False when the deadline cut it off
        self.uncommitted = None  # files its worktree holds that no commit has; None = no worktree read
        self.vetoed = None  # "on main: <proof>" / "probably on main: <hint>" that uncommitted work overruled
        self.files = None  # files the branch changes against main (unlaunched only)
        self.pr = None  # (number, state) when the caller knows
        self.carried = []  # [(carrier branch, "whole"|"part")] — pointers, never proof
        self.evidence = None  # [(path, open items)] for a launched branch; None = not checked
        self.docs_checked = 0  # how many changed .md files evidence() read
        self.docs_total = 0  # how many the branch changed (the cap may leave some unread)
        self.empty = None  # (reason, task) when it holds nothing (empty()); pending branches only
        self.touched = 0  # last_touch(): the newest sign of anyone at it, unix
        self.superseded = None  # C1's reason when every commit's patch and added line is on main
        self.reviews = []  # [(doc, phrase)] — the review status of each D-list doc it carries (E14)

    @property
    def open_items(self):
        """One phrase, always: "open items: docs/x.md (3), TODO.md (1)", "no open-item markers
        in 2 changed docs" (or "in 12 of 13" when the cap left some unread), or "not checked"
        (no docs changed, no fork point, or the deadline)."""
        if self.evidence is None or not self.docs_checked and not self.evidence:
            return "not checked"
        if not self.evidence:
            n, total = self.docs_checked, self.docs_total
            of = f"{n} of {total}" if total > n else str(n)
            return f"no open-item markers in {of} changed doc{'s' if total != 1 else ''}"
        return "open items: " + ", ".join(f"{p} ({n})" for p, n in self.evidence)

    @property
    def where(self):
        return "local+origin" if self.local and self.remote else ("local" if self.local else "origin")

    @property
    def tips(self):
        return sorted({s for s in (self.local, self.remote) if s})


def worktrees(repo):
    """[(path, branch, git dir)] for every worktree of the repo, the primary first. The git
    dir is where checkpoint.py keeps that worktree's lock and carries record."""
    result = []
    text = out(repo, "worktree", "list", "--porcelain")
    common_git = common_dir(repo)
    by_path = {}
    for entry in (common_git / "worktrees").glob("*/gitdir"):
        try:
            by_path[Path(entry.read_text().strip()).parent.resolve()] = entry.parent
        except OSError:
            continue
    for block in text.split("\n\n"):
        path = branch = None
        for line in block.splitlines():
            if line.startswith("worktree "):
                path = Path(line[9:])
            elif line.startswith("branch refs/heads/"):
                branch = line[len("branch refs/heads/"):]
        if path is None:
            continue
        try:
            resolved = path.resolve()
        except OSError:
            resolved = path
        gitdir = by_path.get(resolved, common_git if not result else None)
        result.append((path, branch, gitdir))
    return result


def uncommitted(path):
    """Paths in a worktree no commit has — modified, staged, or untracked and not ignored —
    counted as `git status` lists them (an untracked folder is one); 0 for a worktree gone from
    disk, where nothing can be left; None when git could not say, which vetoes like a dirty
    tree. `-unormal` and `--ignore-submodules=none` override a config that would hide some."""
    if not Path(path).is_dir():
        return 0
    r = git(path, "--no-optional-locks", "status", "--porcelain", "--untracked-files=normal",
            "--ignore-submodules=none")
    if r.returncode:
        return None
    return sum(1 for line in r.stdout.splitlines() if line.strip())


def lock_fresh(gitdir, now):
    try:
        owner = json.loads((gitdir / "claude" / "owner.json").read_text())
        return now - owner.get("seen", 0) < LOCK_TTL
    except (OSError, ValueError, AttributeError, TypeError):
        return False


def read_lines(path):
    try:
        return [l.strip() for l in path.read_text().splitlines() if l.strip()]
    except OSError:
        return []


def parse_record(line):
    """A carries line → (kind, sha, branch). `<kind> <sha> <branch>` is the format; a bare
    branch name (the first day's format) parses as an unpinned partial record."""
    parts = line.split()
    if len(parts) >= 3 and re.fullmatch(r"[0-9a-f]{7,40}", parts[1]):
        return parts[0], parts[1], parts[2]
    return "unpinned", None, parts[0]


def launched_lines(repo):
    """bin/pr merge's lines for this repo: the LAUNCHED_NAME file's, then LANDED_NAME's."""
    cdir = common_dir(repo) / "claude"
    return read_lines(cdir / LAUNCHED_NAME) + read_lines(cdir / LANDED_NAME)


def parse_launched(line):
    """A launched line → (branch, sha or None, via). New: `<branch> <sha> via #N <date>`; the
    first day's `<branch> via #N <date>` has no commit and is not proof."""
    parts = line.split()
    if len(parts) >= 2 and re.fullmatch(r"[0-9a-f]{7,40}", parts[1]):
        return parts[0], parts[1], " ".join(parts[2:4])
    return parts[0], None, " ".join(parts[1:3])


parse_landed = parse_launched  # the old name, for bin/pr until rename S4 moves its caller (S8 drops it)


def collect(repo):
    """Every claude/* branch, local and on origin, merged by name; `-raw` backups skipped
    (checkpoint.py sweeps those once their plain branch is gone)."""
    branches = {}
    text = out(repo, "for-each-ref", "--format=%(refname)%09%(objectname)%09%(committerdate:unix)",
               "refs/heads/claude/", "refs/remotes/origin/claude/")
    for line in text.splitlines():
        ref, sha, when = line.split("\t")
        if ref.startswith("refs/heads/"):
            name, side = ref[len("refs/heads/"):], "local"
        else:
            name, side = ref[len("refs/remotes/origin/"):], "remote"
        if name.endswith("-raw"):
            continue
        b = branches.setdefault(name, Branch(name))
        setattr(b, side, sha)
        b.when = max(b.when, int(when or 0))
    return branches


def target(repo, main):
    """Where "launched" is measured: origin's main (the hub); the local main only when there is
    no origin copy at all."""
    for ref in (f"origin/{main}", main):
        if out(repo, "rev-parse", "--verify", "-q", f"{ref}^{{commit}}"):
            return ref
    return None


def changed_paths(repo, base, tip):
    """Paths the branch touched, renames as delete + add; None when git could not say."""
    r = git(repo, "diff", *DIFF_FLAGS, "--name-only", "--no-renames", "-z", base, tip)
    if r.returncode:
        return None
    return [p for p in r.stdout.split("\0") if p]


def tree_entries(repo, treeish, paths):
    """{path: "mode sha"} for the paths that exist in treeish, or None when git failed.
    Chunked: one argv per LS_TREE_CHUNK paths."""
    entries = {}
    for start in range(0, len(paths), LS_TREE_CHUNK):
        r = git(repo, "ls-tree", "-z", treeish, "--", *paths[start:start + LS_TREE_CHUNK])
        if r.returncode:
            return None
        for item in r.stdout.split("\0"):
            if not item:
                continue
            meta, _, path = item.partition("\t")
            mode, _, rest = meta.partition(" ")
            _, _, sha = rest.partition(" ")
            entries[path] = f"{mode} {sha}"
    return entries


def files_identical(repo, tip, tgt):
    """(b): every path the branch changed reads the same — mode and blob — on the target.
    A path deleted on the branch must be absent on the target too. Returns the proof text
    or None."""
    base = out(repo, "merge-base", tgt, tip)
    if not base:
        return None
    paths = changed_paths(repo, base, tip)
    if paths is None:
        return None
    if not paths:
        return "no net change against main"
    ours, theirs = tree_entries(repo, tip, paths), tree_entries(repo, tgt, paths)
    if ours is None or theirs is None:
        return None
    return "every changed file identical on main" if all(ours.get(p) == theirs.get(p) for p in paths) else None


def prove(repo, branch, tgt):
    """Why every tip of `branch` is certainly on `tgt`, or None. (a) then (b), per tip."""
    proofs = set()
    for tip in branch.tips:
        if is_ancestor(repo, tip, tgt):
            proofs.add("merged")
            continue
        proof = files_identical(repo, tip, tgt)
        if not proof:
            return None
        proofs.add(proof)
    return " / ".join(sorted(proofs)) if proofs else None


def probably(repo, branch, tgt):
    """The hint-only signals, per tip; None unless every tip has one."""
    hints = set()
    for tip in branch.tips:
        base = out(repo, "merge-base", tgt, tip)
        if not base:
            return None
        merges = git(repo, "rev-list", "--merges", "-n", "1", f"{base}..{tip}")
        cherry = git(repo, "cherry", tgt, tip)
        if merges.returncode == 0 and not merges.stdout.strip() and cherry.returncode == 0 \
                and cherry.stdout.strip() and all(l.startswith("-") for l in cherry.stdout.splitlines()):
            hints.add("every commit has an equivalent on main")
            continue
        diff = git(repo, "diff", *DIFF_FLAGS, "--binary", base, tip, text=False)
        if diff.returncode or not diff.stdout or len(diff.stdout) > MAX_REVERSE_BYTES:
            return None
        if b"\nold mode " in diff.stdout:
            return None  # a mode change is exactly what `git apply --check` only warns about
        with tempfile.TemporaryDirectory() as d:
            env = dict(os.environ, GIT_INDEX_FILE=os.path.join(d, "index"))
            if git(repo, "read-tree", tgt, env=env).returncode:
                return None
            if git(repo, "apply", "--cached", "--check", "-R", input=diff.stdout, env=env, text=False).returncode:
                return None
        hints.add("net diff applies to main in reverse")
    return " / ".join(sorted(hints)) if hints else None


def changed_files(repo, branch, tgt):
    tip = branch.local or branch.remote
    base = out(repo, "merge-base", tgt, tip)
    paths = changed_paths(repo, base, tip) if base else None
    return len(paths) if paths is not None else None


def open_items_in(text):
    """(unstruck items under an open-ish heading or an unticked `- [ ]` anywhere, `➤ Answer:`
    lines nobody replied to with `> **Done.**` or its kin, DONE_REPLY_RE) in one Markdown document — the repo's own
    conventions for "not done"."""
    lines = text.splitlines()
    in_open, items, answers = False, 0, 0
    fence = common.fenced(lines)
    # The next option letter a D-item's run may take (None outside one), and the D-item's indent
    # and whether it is a list item: its options sit under it — deeper than a list-item D-item,
    # at least as deep as a bold paragraph one — and before its ➤ lines (review, 2026-10-05).
    option, d_indent, d_list = None, 0, False
    for i, (line, fenced) in enumerate(zip(lines, fence)):
        if fenced:
            continue  # an example D-item in a fence (agents/architect.md) asks nothing; nor do its headings or checkboxes
        if HEADING_RE.match(line) or BOLD_HEADING_RE.match(line):
            in_open = bool(OPEN_HEADING_RE.search(line))
            option = None
            continue
        indent = len(line) - len(line.lstrip())
        is_d = bool(D_ITEM_RE.match(line))
        if is_d:
            option, d_indent, d_list = "A", indent, bool(ITEM_RE.match(line))
        elif REC_RE.match(line) or asks_answer(line):
            option = None  # options come before the ➤ lines; nothing after them is one
        m = ITEM_RE.match(line)
        if m:
            body = m.group(1).strip()
            o = OPTION_RE.match(body)
            under = indent > d_indent or (not d_list and indent >= d_indent)
            if o and o.group(1) == option and under:
                # `- A — …`, `- B — …`: a D-item's options (agents/architect.md), not to-dos. Only
                # that run, in order: a `- X — …` item anywhere else is a list item like any other.
                option = chr(ord(option) + 1)
                continue
            if option and not is_d and (option != "A" or not under):
                option = None  # the run is over, or the list left the D-item
            if body.startswith("[ ]"):
                items += 1  # an unticked checkbox is open wherever it sits
            elif in_open and not STRUCK_RE.match(body):
                items += 1
        if asks_answer(line):
            answered = False
            for k in range(i + 1, len(lines)):  # the item's block: up to the next item, heading or answer
                nxt = lines[k]
                if fence[k]:
                    continue  # a fenced example under an answer neither settles nor ends it
                if HEADING_RE.match(nxt) or asks_answer(nxt) or ITEM_RE.match(nxt):
                    break
                if DONE_REPLY_RE.match(nxt):
                    answered = True
                    break
            answers += 0 if answered else 1
    return items, answers


# E14 of docs/autofinish-design-2026-10-02.md: an unlaunched branch that carries a D-list doc says
# whether the owner looked at it — `docs/x.md: unseen 0/5, stands Mon 09:12` — in the 🌿 note and
# `bin/repos --branches`. bin/keel computes it (one rule, the same `memo status` prints); loaded
# as a module, as sync.py loads bin/sheep. Anything it raises costs the phrase, never the survey.
MEMO_TOOL = common.tool("keel")  # a peer (G5): None → the review reads no D-lists
REVIEW_MAX_DOCS = 4  # D-list docs read per branch
D_ID_RE = re.compile(r"\bD\d+\b")
_memo = None


def memo_tool():
    global _memo
    if _memo is None:
        try:
            from importlib.machinery import SourceFileLoader
            if not MEMO_TOOL:
                raise ImportError("keel not installed")
            _memo = SourceFileLoader("memo_tool", str(MEMO_TOOL)).load_module()
            _memo.GIT_TIMEOUT = GIT_TIMEOUT  # its git calls are bounded like this hook's own
        except Exception:
            _memo = False
    return _memo or None


def doc_reviews(repo, branch, tgt, late=lambda: False):
    """[(doc, phrase)] for the D-list docs the branch adds or changes (docs/handoff/ is a seed's
    brief, not a memo). The text is the worktree's file when one holds the branch — an answer
    typed and not committed is the owner's — else the tip's blob; `stands <time>` only with a
    worktree (bin/keel's verdict reads the checkout, never fetching here)."""
    memo = memo_tool()
    tip = branch.local or branch.remote
    if memo is None or not tip:
        return []
    base = out(repo, "merge-base", tgt, tip)
    paths = changed_paths(repo, base, tip) if base else None
    found = []
    held = branch.worktree and Path(branch.worktree).is_dir()  # a listed but deleted worktree is none
    for rel in [p for p in (paths or []) if p.endswith(".md") and not p.startswith(HANDOFF_DIR + "/")]:
        if late() or len(found) >= REVIEW_MAX_DOCS:
            break
        wt = Path(branch.worktree) / rel if held else None
        try:
            if wt is not None and wt.is_file():
                text = wt.read_text(encoding="utf-8")
            else:
                wt = None
                r = git(repo, "show", f"{tip}:{rel}")
                if r.returncode:
                    continue
                text = r.stdout
            if not D_ID_RE.search(text):
                continue  # cheap: no D-list, no parse (any D<n>: a revision doc may start at D6)
            if not memo.parse(text)[1]:
                continue  # D<n> in prose, no D-items: no git call spent on it
            if wt is not None:
                # stand_status computes the review status too: one pass, with the verdict beside it
                try:
                    st = memo.stand_status(str(wt), fetch_first=False)
                    if st.get("review"):
                        found.append((rel, st["review"]["phrase"]))
                        continue
                except Exception:
                    pass  # no link yet, no GitHub origin: no verdict, the status still reads
            rv = memo.review_status(Path(branch.worktree) if wt is not None else repo, branch.tips, rel, text,
                                    branch=branch.name, path=wt, primary=repo)
            if rv is None:
                continue
            # without a worktree there is no blame to tell an architect's pre-filled pick from
            # the owner's answer: the phrase says it was read from the tip
            found.append((rel, memo.review_phrase(rv) + ("" if wt is not None else " (tip)")))
        except Exception:
            continue
    return found


def topic_of(name):
    """`claude/laptop/2026-09-24-cloud-files` → "cloud-files"; too short to search for → ""."""
    topic = re.sub(r"^\d{4}-\d{2}-\d{2}-", "", name.rsplit("/", 1)[-1])
    return topic if len(topic) >= 4 else ""


def evidence(repo, branch, tgt, late=lambda: False):
    """([(path, open items)], docs read) for the .md files the branch changed, read as they
    stand on the target (a file gone from main is skipped), plus TODO.md lines naming those
    files or the branch's topic. ([], n) = nothing found in n docs; (None, 0) = git could not
    say, no fork point is known, or the deadline passed — reported as "not checked"."""
    tip = branch.local or branch.remote
    base = out(repo, "merge-base", tgt, tip)
    if base == tip and branch.local:
        # An ancestor of main (a fast-forward): its commits are main's now, so the merge-base
        # is the tip itself. Where the branch forked is its oldest reflog entry — the commit
        # `git switch -c` created it on. A rebase-merge keeps a real merge-base.
        log = out(repo, "reflog", "show", "--format=%H", f"refs/heads/{branch.name}").splitlines()
        base = log[-1] if log else ""  # one entry = never moved since creation: nothing changed
    elif base == tip:
        base = ""  # origin-only and fast-forwarded: no reflog to say where it forked
    paths = changed_paths(repo, base, tip) if base else None
    if paths is None:
        return None, 0, 0
    found, read = [], 0
    all_docs = [p for p in paths if p.endswith(".md")]
    docs = all_docs[:EVIDENCE_MAX_FILES]
    for p in docs:
        if late():
            return None, 0, 0
        r = git(repo, "show", f"{tgt}:{p}")
        if r.returncode:
            continue
        read += 1
        n = sum(open_items_in(r.stdout))
        if n:
            found.append((p, n))
    todo = git(repo, "show", f"{tgt}:TODO.md")
    if todo.returncode == 0:
        # Whole words, four characters or more: "pa" would match "path" and "parity" (review).
        keys = {k for k in ({Path(p).stem for p in docs} | {topic_of(branch.name)}) if len(k) >= 4}
        keys |= {k.replace("-", " ") for k in keys}
        pats = [re.compile(r"(?<![\w-])" + re.escape(k) + r"(?![\w-])", re.I) for k in keys]
        n = sum(1 for line in todo.stdout.splitlines() if any(p.search(line) for p in pats))
        if n:
            found.append(("TODO.md", n))
    return found, read, len(all_docs)


def survey(repo, main=None, prs=None, now=None, deadline=None, idle_after=IDLE_AFTER, reaping=False,
           reviews=False):
    """The three groups for one repo: (launched, probably, pending), each a list of Branch, idle
    branches only, oldest first. `prs` maps branch name → (number, state, title, updated) when
    the caller looked them up (GitHub is not consulted here). `deadline` is a time.monotonic()
    value; work not done by then is skipped and the branch comes back checked=False.
    `reaping` (sync.py's session start, `bin/repos --classify`): also test C1 on the branches
    a reaper could take — read-only callers skip its cost and its merge-tree objects.
    `reviews` (`bin/repos --branches`): also E14's review status of each pending branch's D-list
    docs; sync.py asks for it separately (add_reviews), after the PR lookup it must not starve."""
    repo = Path(repo).resolve()
    now = now or time.time()
    main = main or main_branch(repo)
    branches = collect(repo)
    tgt = target(repo, main)
    wts = worktrees(repo)
    late = lambda: deadline is not None and time.monotonic() > deadline  # noqa: E731
    gitdirs = {}
    for path, name, gitdir in wts:
        if name in branches:
            branches[name].worktree = path
            branches[name].live = bool(gitdir) and lock_fresh(gitdir, now)
            gitdirs[name] = gitdir
    # bin/pr's launched lines: proof was established when the line was written; it holds while the
    # branch has not moved past the commit named. The worktrees' carries records only annotate.
    recorded = {}
    for line in launched_lines(repo):
        name, sha, via = parse_launched(line)
        b = branches.get(name)
        if b and sha and b.tips and all(is_ancestor(repo, t, sha) for t in b.tips):
            recorded.setdefault(name, f"recorded launched {via} (proved then, unchanged since)")
    held = [(name, [parse_record(l) for l in read_lines(gitdir / "claude" / CARRIES_NAME)] if gitdir else [])
            for path, name, gitdir in wts]
    for line in read_lines(common_dir(repo) / "claude" / CARRIED_NAME):
        carrier, _, rest = line.partition(" ")
        held.append((carrier, [parse_record(rest)] if rest.strip() else []))
    for name, records in held:
        if not records or not name or not name.startswith("claude/"):
            continue
        for kind, sha, source in records:
            src = branches.get(source)
            if src is not None and source != name:
                tag = (name, "whole" if kind in WHOLE_KINDS else "part")
                if tag not in src.carried:
                    src.carried.append(tag)
    done, maybe, pending = [], [], []
    for b in sorted(branches.values(), key=lambda b: b.when):
        if now - b.when < idle_after or b.live:
            continue
        b.pr = (prs or {}).get(b.name)
        if b.worktree is not None:
            # Read before any verdict, so it can veto one; out of time, the branch stays unchecked
            # rather than launched on its commits alone.
            if late():
                b.checked = False
                pending.append(b)
                continue
            b.uncommitted = uncommitted(b.worktree)
        group = pending
        if b.name in recorded:
            b.proof, group = recorded[b.name], done
        elif late():
            b.checked = False
        elif tgt:
            b.proof = prove(repo, b, tgt)
            if b.proof:
                group = done
            else:
                b.proof = probably(repo, b, tgt)
                group = maybe if b.proof else pending
        if group is done:
            b.carried = []  # the commits are proved: the pointer mattered only until now
        if group is not pending and b.worktree is not None and b.uncommitted != 0:
            # Its commits launched; its worktree did not. The proof moves to the description.
            b.vetoed = f"{'on' if group is done else 'probably on'} main: {b.proof}"
            b.proof, group = None, pending
        if group is not pending and b.name not in recorded and not late():
            # launched is a fact about content; finished is the next question (D2)
            b.evidence, b.docs_checked, b.docs_total = evidence(repo, b, tgt, late)
        elif group is pending and b.checked and tgt and not b.vetoed and not late():
            b.files = changed_files(repo, b, tgt)
        if group is not done and b.checked and tgt and not b.vetoed and not late():
            # The reaping clock first (docs/record/branch-reaping-2026-10-04.md): a verdict without its
            # clock would read as idle since 1970, so empty/superseded are set only after it,
            # and only once it read a real time (review, 2026-10-04).
            b.touched = last_touch(repo, b.name, gitdirs.get(b.name), b.tips)
            if b.touched and group is pending and not late():
                b.empty = empty(repo, b, tgt, b.worktree)
            # C1 costs a cherry, carried(), a diff per file and a merge-tree (which writes tree
            # objects): only for a caller that may reap, and only for a branch it could reap.
            if (reaping and b.touched and group is maybe and b.worktree is None and not b.carried
                    and now - b.touched >= REAP_AFTER and not late()):
                b.superseded = superseded(repo, b, tgt, late=late)
        group.append(b)
    for b in done:  # the record-proved ones, checked last: they cost the same and are fewer
        if b.name in recorded and not late():
            b.evidence, b.docs_checked, b.docs_total = evidence(repo, b, tgt, late) if tgt else (None, 0, 0)
    if reviews:
        add_reviews(repo, pending, tgt=tgt, deadline=deadline)
    return done, maybe, pending


def add_reviews(repo, pending, main=None, tgt=None, deadline=None):
    """E14's review status on each pending branch, last of all: it spends only what is left of
    the budget (the session start's is 6 s; about 0.1 s a doc, 0.3 s with `stands <time>` —
    the layer, 2026-10-08), so sync.py calls it after open_prs, never before."""
    repo = Path(repo).resolve()
    tgt = tgt or target(repo, main or main_branch(repo))
    late = lambda: deadline is not None and time.monotonic() > deadline  # noqa: E731
    for b in pending:
        if b.files is not None and tgt and not late():
            b.reviews = doc_reviews(repo, b, tgt, late)


def never_pushed(repo, name):
    """No upstream configured and no origin copy: a branch that can never read `[gone]`, so
    sync.py's merged-worktree removal never sees it (branch-hygiene-2, 2026-09-29)."""
    return not out(repo, "config", "--get", f"branch.{name}.merge") and \
        not out(repo, "rev-parse", "-q", "--verify", f"refs/remotes/origin/{name}")


def reflog(repo, name):
    """[(sha, unix time)] of the branch's reflog, newest first; [] when it has none."""
    entries = []
    for line in out(repo, "reflog", "show", "--date=unix", "--format=%H %gd", f"refs/heads/{name}").splitlines():
        m = re.fullmatch(r"([0-9a-f]{40}) .*@\{(\d+)\}", line)
        if m:
            entries.append((m.group(1), int(m.group(2))))
    return entries


def committed_nothing(repo, name, tip):
    """Whether the branch still points where it was created: its tip is on main because it
    never left it, which proves nothing launched (a worktree made a minute ago)."""
    log = reflog(repo, name)
    return bool(log) and log[-1][0] == tip


def carried(repo, name, tip, tgt, late=lambda: False):
    """Hint, never proof, for a branch gone on GitHub with commits after its merge: every line
    the branch itself added is on `tgt` or on one other local claude/* branch, at the same path.
    The case (a guarded repo, 2026-10-01): the owner answered a memo in a worktree whose PR had merged, the
    session-start sweep committed the answers there, and another branch took them on — so the
    worktree showed no lock. "Added" is the branch's own work: lines of tip:path that neither
    merge-base:path nor tgt:path has, so main moving on or rewriting its own lines changes
    nothing (review, 2026-10-01). Line containment is fooled by reordering and repeated lines,
    so it only ever makes "probably" (the lock), never "launched" (removal). A binary file, a git
    failure or the deadline: None. Contents are bytes, decoded with "replace": a Latin-1 file
    must not raise out of a hook."""
    base = out(repo, "merge-base", tgt, tip)
    paths = changed_paths(repo, base, tip) if base else None
    if not paths:
        return None

    def lines(ref, path):
        r = git(repo, "show", f"{ref}:{path}", text=False)
        if r.returncode:
            return None
        if b"\0" in r.stdout[:8000]:
            raise ValueError("binary")
        return {l.rstrip() for l in r.stdout.decode("utf-8", "replace").splitlines()}

    added = {}
    try:
        for path in paths:
            if late():
                return None
            mine, old, on_main = lines(tip, path), lines(base, path), lines(tgt, path)
            if mine is None:
                if old is not None and on_main is not None:
                    return None  # deleted here, still on main: a removal is work main lacks
                continue
            if old and on_main and (old - mine) & on_main:
                return None  # a line removed here that main still has (review, 2026-10-01)
            left = mine - (old or set()) - (on_main or set())
            if left:
                added[path] = left
        if not added:
            return "every line it adds is on main"
        others = [n for n in out(repo, "for-each-ref", "--format=%(refname:short)", "refs/heads/claude/").splitlines()
                  if n and n != name and not n.endswith("-raw")]
        for other in others:
            if late():
                return None
            if all(want <= (lines(f"refs/heads/{other}", path) or set()) for path, want in added.items()):
                return f"carried by {other}: every line it adds is there or on main"
    except ValueError:
        return None
    return None


# ---- reaping: empty branches, and what code can prove superseded (docs/record/branch-reaping-2026-10-04.md)

ROUTED_BY_RE = re.compile(r"^Routed-By:[^(\n]*\(([^)\n]*)\)[ \t]*$", re.M)


def seed_paths_ok(repo, base, tip, paths, bodies):
    """Whether a seed's changed paths are a seed's: each under docs/handoff/ or docs/blueprints/,
    one brief under docs/handoff/ at least — or a doc a `Routed-By: pickup seed (<doc>, …)` trailer
    names whose diff base..tip is its `Routed:` line alone (keel's routed comments, S2: the seed
    commit writes that line into the doc it routes; the S2 landing review, 2026-10-26)."""
    if not paths or not any(p.startswith(HANDOFF_DIR + "/") for p in paths):
        return False
    routed = {d.strip() for b in bodies for m in ROUTED_BY_RE.finditer(b or "") for d in m.group(1).split(",")}
    for p in paths:
        if p.startswith((HANDOFF_DIR + "/", BLUEPRINT_DIR + "/")):
            continue
        if p not in routed:
            return False
        r = git(repo, "diff", *DIFF_FLAGS, "--no-renames", "-U0", base, tip, "--", p)
        if r.returncode:
            return False
        body = [l for l in r.stdout.splitlines() if l[:1] in "+-" and not l.startswith(("+++", "---"))]
        if not body or any(not l[1:].startswith("Routed:") for l in body):
            return False
    return True


def seed_task(repo, base, tip):
    """The task of a branch that is nothing but a seed — every commit base..tip a `Seed:` commit
    with a `Seeded-By:` trailer, every changed path under docs/handoff/ (or the seed's blueprint
    beside it, docs/blueprints/, with a brief under docs/handoff/ all the same) — as the first `> ` line
    of the oldest commit's body ("" when it has none); None for anything else, and for any git
    failure: only a certain seed is ever reaped as one."""
    if not base or base == tip:
        return None
    r = git(repo, "log", "--reverse", "--format=%s%x1f%b%x1e", f"{base}..{tip}")
    if r.returncode:
        return None
    records = [x.strip("\n") for x in r.stdout.split("\x1e") if x.strip()]
    if not records:
        return None
    for rec in records:
        subject, _, body = rec.partition("\x1f")
        if not subject.startswith(SEED_SUBJECT) or not SEEDED_BY_RE.search(body):
            return None
    paths = changed_paths(repo, base, tip)
    if not seed_paths_ok(repo, base, tip, paths, [rec.partition("\x1f")[2] for rec in records]):
        return None
    body = records[0].partition("\x1f")[2]
    return next((l[2:].strip() for l in body.splitlines() if l.startswith("> ")), "")


def seed_only(repo, base, tip):
    return seed_task(repo, base, tip) is not None


def empty(repo, b, tgt, worktree=None):
    """(reason, task) when every tip of the branch holds nothing a session wrote — from git alone,
    never transcripts, which see one machine (section 2) — or None. Reasons:
      "nothing committed"   the tip is on main and the branch never moved from where it was made
                            (its reflog's oldest entry), or its commits net to nothing (S1, S4);
      "seed never started"  seed commits only, no worktree here and no open PR (S2);
      "seed, nothing committed after it"
                            the same with a worktree here or an open PR: a session ran and wrote
                            nothing (S3; three of them headless on the other Mac, 2026-10-04).
    A tip on main that DID move (a fast-forward merge) is launched, not empty: prove() has it."""
    if not tgt or not b.tips:
        return None
    reasons, task = set(), ""
    for tip in b.tips:
        if is_ancestor(repo, tip, tgt):
            if tip != b.local or not committed_nothing(repo, b.name, tip):
                return None
            reasons.add("nothing committed")
            continue
        base = out(repo, "merge-base", tgt, tip)
        paths = changed_paths(repo, base, tip) if base else None
        if paths is None:
            return None
        if not paths:
            reasons.add("nothing committed")
            continue
        t = seed_task(repo, base, tip)
        if t is None:
            return None
        task = task or t
        reasons.add("seed, nothing committed after it" if worktree is not None or b.pr else EMPTY_NEVER)
    if not reasons:
        return None
    # a seed beside a nothing-committed twin is still a seed: its brief is what the note quotes
    seed = sorted(r for r in reasons if r.startswith("seed"))
    return (seed[0] if seed else "nothing committed"), task


def pr_time(pr):
    """The open PR's `updated_at` (open_prs' fourth field) as unix time, or 0."""
    try:
        return calendar.timegm(time.strptime(pr[3], "%Y-%m-%dT%H:%M:%SZ"))
    except (TypeError, IndexError, ValueError):
        return 0


def reap_reason(b):
    """(reason, task, ttl, clock) for a branch empty() named — the one place the reapers, the
    note and `bin/repos --classify` read it from. An open PR means a session ran the seed (S3,
    7 days), and its update time joins the clock: a seed adopted elsewhere today, its first
    push just made, is not reaped on its commit date (review, 2026-10-04)."""
    reason, task = b.empty
    if reason == EMPTY_NEVER and b.pr:
        reason = "seed, nothing committed after it"
    ttl = SEED_TTL if reason == EMPTY_NEVER else REAP_AFTER
    return reason, task, ttl, max(b.touched, pr_time(b.pr))


def last_touch(repo, name, gitdir=None, tips=()):
    """The idle clock (section 2): the newest of each tip's committer date, the branch's newest
    reflog entry, and — with the worktree's git dir — its `logs/HEAD` newest entry (`worktree
    add` writes that, not the branch reflog: probed 2026-10-04), the lock's `seen`, and the
    mtime of anything in its `claude/` state. Too fresh only delays a reap; the committer date
    bounds it from below (R6)."""
    times = []
    for tip in tips:
        t = out(repo, "log", "-1", "--format=%ct", tip)
        if t.isdigit():
            times.append(int(t))
    log = reflog(repo, name)
    if log:
        times.append(log[0][1])
    if gitdir is not None:
        gitdir = Path(gitdir)
        try:
            tail = (gitdir / "logs" / "HEAD").read_text(errors="replace").splitlines()
        except OSError:
            tail = []
        m = re.search(r"> (\d+) [+-]\d{4}\t", tail[-1]) if tail else None
        if m:
            times.append(int(m.group(1)))
        state = gitdir / "claude"
        try:
            owner = json.loads((state / "owner.json").read_text())
            times.append(float(owner.get("seen") or 0))
        except (OSError, ValueError, AttributeError, TypeError):
            pass
        for p in [state, *(state.iterdir() if state.is_dir() else [])]:
            try:
                times.append(p.lstat().st_mtime)
            except OSError:
                continue
    return max(times or [0])


def file_states(repo, base, tip, tgt, paths=None):
    """{path: "identical" | "edited since" | "differs"} for each path the branch changed — the
    per-file test `pickup review` prints: the same entry on main; main changed the path after the
    branch left it (a pick, a rename, a later edit); or main never touched it, so the branch's
    change is not there. None when git could not say."""
    paths = changed_paths(repo, base, tip) if paths is None else paths
    if paths is None:
        return None
    ours, theirs = tree_entries(repo, tip, paths), tree_entries(repo, tgt, paths)
    if ours is None or theirs is None:
        return None
    states = {}
    for p in paths:
        if ours.get(p) == theirs.get(p):
            states[p] = "identical"
        else:
            r = git(repo, "diff", "--quiet", *DIFF_FLAGS[:4], base, tgt, "--", p)
            if r.returncode not in (0, 1):
                return None
            states[p] = "edited since" if r.returncode == 1 else "differs"
    return states


def cherry_counts(repo, base, tip, tgt):
    """(commits with an equivalent patch on main, commits) since base, or None when the branch
    has merge commits — `git cherry` skips those — or git failed."""
    merges = git(repo, "rev-list", "--merges", "-n", "1", f"{base}..{tip}")
    cherry = git(repo, "cherry", tgt, tip)
    if merges.returncode or merges.stdout.strip() or cherry.returncode:
        return None
    marks = [l[:1] for l in cherry.stdout.splitlines() if l.strip()]
    return sum(1 for m in marks if m == "-"), len(marks)


def added_lines(repo, base, tip, md_only=False):
    """The lines the branch adds (right-stripped, more than three characters — a brace or a blank
    proves nothing), or None when git failed."""
    r = git(repo, "diff", *DIFF_FLAGS[:4], "-U0", base, tip, *(["--", "*.md"] if md_only else []), text=False)
    if r.returncode:
        return None
    lines, in_hunk = [], False
    for raw in r.stdout.decode("utf-8", "replace").splitlines():
        if raw.startswith("diff --git "):
            in_hunk = False  # the `--- a/…` / `+++ b/…` header follows; an added `++x` line does not
        elif raw.startswith("@@"):
            in_hunk = True
        elif in_hunk and raw.startswith("+"):
            s = raw[1:].rstrip()  # leading whitespace kept: an indent-only change is not "the same line" (R8)
            if len(s.strip()) > 3:
                lines.append(s)
    return lines


_MAIN_LINES = {}


def main_lines(repo, tgt, timeout=120):
    """(every line, every line of a .md file) in main's text blobs — right-stripped, longer than three
    characters — for C2's "content moved" and C5's "doc launched elsewhere": one `ls-tree -r` and
    one `cat-file --batch`, cached per main commit. A blob over MAIN_BLOB_MAX or with a NUL in
    its first 8 kB is skipped. None when git failed."""
    sha = out(repo, "rev-parse", "--verify", "-q", f"{tgt}^{{commit}}")
    key = (str(repo), sha)
    if not sha:
        return None
    if key in _MAIN_LINES:
        return _MAIN_LINES[key]
    r = git(repo, "ls-tree", "-r", "-z", "-l", sha)
    if r.returncode:
        return None
    blobs = []
    for item in r.stdout.split("\0"):
        meta, _, path = item.partition("\t")
        parts = meta.split()
        if len(parts) == 4 and parts[1] == "blob" and parts[3].isdigit() and int(parts[3]) <= MAIN_BLOB_MAX:
            blobs.append((parts[2], path.endswith(".md")))
    batch = git(repo, "cat-file", "--batch", input="".join(f"{s}\n" for s, _ in blobs).encode(),
                timeout=timeout, text=False)
    if batch.returncode:
        return None
    data, pos, every, md = batch.stdout, 0, set(), set()
    for _, is_md in blobs:
        nl = data.find(b"\n", pos)
        if nl < 0:
            return None
        head = data[pos:nl].split()
        if len(head) < 3 or not head[2].isdigit():
            return None  # "<sha> missing": the batch is out of step, so nothing after it is right
        size = int(head[2])
        body = data[nl + 1:nl + 1 + size]
        pos = nl + 1 + size + 1
        if b"\0" in body[:8000]:
            continue
        for line in body.decode("utf-8", "replace").splitlines():
            s = line.rstrip()
            if len(s.strip()) > 3:
                every.add(s)
                if is_md:
                    md.add(s)
    _MAIN_LINES.clear()  # one repo at a time: a run over 17 repos must not hold them all
    _MAIN_LINES[key] = (every, md)
    return every, md


def merge_adds(repo, tip, tgt):
    """The paths where merging the branch into main would change main — `git merge-tree
    --write-tree` (git ≥ 2.38), a three-way merge in the object store that touches no ref, index
    or worktree — or None on any failure. [] means launching the branch is a no-op. The signal
    that tells position apart: the review's "second of two identical stanzas" (2026-09-24)
    passes cherry, line containment and the per-file test alike, and fails here (the build of
    2026-10-04 found it, docs/record/branch-reaping-2026-10-04.md section 6 "Built"). `-X ours`: a
    conflicting hunk is one main rewrote after taking the branch's patch (generalized-2, kids/
    start: production.yaml edited again since) — main's side is the newer word; a hunk main
    never touched merges cleanly and shows up here."""
    r = git(repo, "merge-tree", "--write-tree", "--no-messages", "-X", "ours", tgt, tip)
    tree = r.stdout.split("\n", 1)[0].strip() if r.returncode == 0 else ""
    if not re.fullmatch(r"[0-9a-f]{40,64}", tree):
        return None
    d = git(repo, "diff-tree", "-r", "--name-only", "-z", "--no-renames", f"{tgt}^{{tree}}", tree)
    if d.returncode:
        return None
    return [p for p in d.stdout.split("\0") if p]


def share(lines, pool):
    return sum(1 for l in lines if l in pool) / len(lines) if lines else 1.0


def superseded(repo, b, tgt, anywhere=False, late=lambda: False):
    """C1 (and with `anywhere`, C2): the reason every tip's work is on main although the branch
    is not — or None. C1 needs four signals that agree: `git cherry` finds every commit's patch
    on main (no merge commits), carried() finds every line the branch adds on main at the same
    path, no changed file "differs" (each is identical on main, or main edited it since), and a
    three-way merge of the branch into main changes nothing (merge_adds). The design named three;
    the fourth was added at the build, when the first three called the review's "second of two
    identical stanzas" fixture superseded. A whitespace-only difference fails carried() and the
    merge both (R8). C2, weekly only (`bin/repos --branches --classify --reap`): every patch on
    main, MOVED_SHARE of the added lines anywhere in main's text, and the merge changes no path
    main still has — the branch's files were renamed or merged away, nothing else."""
    if not tgt or not b.tips:
        return None
    for tip in b.tips:
        if late():
            return None
        base = out(repo, "merge-base", tgt, tip)
        if not base or base == tip:
            return None
        counts = cherry_counts(repo, base, tip, tgt)
        if not counts or counts[0] != counts[1] or not counts[1]:
            return None
        if anywhere:
            pool = main_lines(repo, tgt)
            added = added_lines(repo, base, tip)
            if pool is None or added is None or share(added, pool[0]) < MOVED_SHARE:
                return None
            # The merge may differ from main only where main no longer has the path at all.
            # Without this, an edit main never took would pass on line containment; a conflict
            # (main rewrote the same lines, whitespace included) is C3's "launched, then edited".
            changed = merge_adds(repo, tip, tgt)
            still = tree_entries(repo, tgt, changed) if changed else {}
            if changed is None or still is None or still:
                return None
            continue
        if carried(repo, b.name, tip, tgt, late) != "every line it adds is on main":
            return None
        states = file_states(repo, base, tip, tgt)
        if states is None or "differs" in states.values():
            return None
        if merge_adds(repo, tip, tgt) != []:
            return None
    return ("superseded: patches on main, content moved" if anywhere
            else "superseded: every commit's patch and every added line are on main")


def last_asked(repo, base, tip):
    """The newest prompt a checkpoint commit quotes (`Prompt:` / `Prompts (oldest first):`
    then `> ` lines), or "" — what the branch was last asked to do, from git alone."""
    text = out(repo, "log", "-n", "30", "--format=%b%x1e", f"{base}..{tip}")
    for body in text.split("\x1e"):
        quoted, inside = [], False
        for line in body.splitlines():
            if re.match(r"^(?:Prompt|Prompts \(oldest first\)):\s*$", line):
                inside, quoted = True, []
            elif inside and line.startswith("> "):
                quoted.append(line[2:].strip())
            elif inside and line.strip():
                inside = False
        if quoted:
            return quoted[-1]
    return ""


CASES = {"C1": "superseded", "C2": "superseded, moved", "C3": "carried", "C4": "PR closed unmerged",
         "C5": "doc launched elsewhere", "C6": "abandoned", "C7": "live"}


def classify(repo, b, tgt, closed=None, now=None):
    """(case, facts) for one idle branch, by section 5's table — C7 (live) checked first, since
    nothing live is ever a candidate, then C1…C6 in order, the first that holds — except that a
    branch a carries pointer names is never C1/C2: the session start skips it, its carrier's
    `bin/pr carried` still has a PR to close, and one rule serves both reapers (review). `closed` maps
    branch → (number, closed date) of PRs closed unmerged (closed_prs()). Facts are what the
    weekly judge reads: patches on main, share of added lines on main, files missing on main,
    idle days, PR, carries pointer, last asked. Reads only; archive() is the caller's."""
    now = now or time.time()
    tip = b.local or b.remote
    base = out(repo, "merge-base", tgt, tip) if tgt and tip else ""
    facts = {"idle": int((now - (b.touched or b.when)) // 86400), "pr": b.pr, "carried": list(b.carried),
             "cherry": None, "share": None, "missing": None, "asked": last_asked(repo, base, tip) if base else ""}
    if b.live or now - (b.touched or b.when) < REAP_AFTER:
        return "C7", facts
    if not base:
        return "C6", facts
    facts["base"] = base
    facts["cherry"] = cherry_counts(repo, base, tip, tgt)
    paths = changed_paths(repo, base, tip) or []
    on_main = tree_entries(repo, tgt, paths) if paths else {}
    facts["missing"] = None if on_main is None else sum(1 for p in paths if p not in on_main)
    pool = main_lines(repo, tgt)
    added = added_lines(repo, base, tip)
    if pool is not None and added is not None:
        facts["share"] = share(added, pool[0])
    if not b.carried and (b.superseded or superseded(repo, b, tgt)):
        return "C1", facts
    if not b.carried and superseded(repo, b, tgt, anywhere=True):
        return "C2", facts
    all_patches = bool(facts["cherry"]) and facts["cherry"][0] == facts["cherry"][1] > 0
    hint = carried(repo, b.name, tip, tgt) or ""
    if b.carried or hint.startswith("carried by ") or all_patches:
        facts["hint"] = hint if hint.startswith("carried by ") else (
            f"launched, then edited: {round(100 * (facts['share'] or 0))} % of its lines remain" if all_patches else "")
        return "C3", facts
    if closed and b.name in closed:
        facts["closed"] = closed[b.name]
        return "C4", facts
    if paths and all(p.endswith(".md") for p in paths) and facts["missing"] == len(paths) and pool is not None:
        md = added_lines(repo, base, tip, md_only=True)
        if md and share(md, pool[1]) >= DOC_SHARE:
            facts["doc_share"] = share(md, pool[1])
            return "C5", facts
    return "C6", facts


def classify_line(b, case, facts):
    """One line per idle branch for `bin/repos --branches --classify` and the weekly judge."""
    parts = []
    if facts.get("cherry"):
        parts.append(f"{facts['cherry'][0]}/{facts['cherry'][1]} patches on main")
    elif "cherry" in facts and facts["cherry"] is None and case != "C7" and facts.get("base"):
        parts.append("patches not compared (merge commits, or git failed)")
    if facts.get("share") is not None:
        parts.append(f"{round(100 * facts['share'])} % of lines anywhere on main")
    if facts.get("missing"):
        parts.append(f"{facts['missing']} file{'s' if facts['missing'] != 1 else ''} missing on main")
    if facts.get("hint"):
        parts.append(facts["hint"])
    if facts.get("closed"):
        parts.append(f"PR #{facts['closed'][0]} closed unmerged {facts['closed'][1]}")
    if facts.get("doc_share") is not None:
        parts.append(f"{round(100 * facts['doc_share'])} % of its lines in main's docs")
    if facts.get("carried"):
        parts.append("carries pointer: " + ", ".join(f"{c} ({how})" for c, how in facts["carried"]))
    parts.append(f"idle {facts['idle']} d")
    pr = facts.get("pr")
    parts.append(f"PR #{pr[0]}" if pr else "PR none")
    if facts.get("asked"):
        asked = facts["asked"]
        parts.append(f"last asked \"{asked[:100] + '…' if len(asked) > 100 else asked}\"")
    return f"{case} {CASES[case]} · {b.name} · " + ", ".join(parts)


def worktree_states(repo, main=None, deadline=None, known=None):
    """[(path, branch, state, why, tip)] for every claude/* worktree — young ones too, unlike
    survey() — for the indicator in VS Code's Repositories view (docs/record/landed-indicator-2026-09-29.md).
    state is "launched" (its branch is gone on GitHub, or recorded by bin/pr, and proved: sync.py
    removes it once nobody is in it), "probably" (its commits are on main but nothing removes it
    yet: never pushed, or its origin copy is still there; or only a hint says so — for a branch
    gone on GitHub, carried(): every line it adds is on main or another claude/* branch) or "wip".
    A worktree with uncommitted work is wip whatever its commits say. A branch gone on GitHub
    that the files cannot prove asks GitHub for a merged PR with exactly its tip (the home repo,
    2026-09-29: six such worktrees, all merged) — once; `known` is the last run's
    {branch: [tip, state, why]}, and a launched verdict for an unchanged tip is reused. None when
    the deadline cut it short — the caller keeps what it wrote last time."""
    repo = Path(repo).resolve()
    main = main or main_branch(repo)
    tgt = target(repo, main)
    late = lambda: deadline is not None and time.monotonic() > deadline  # noqa: E731
    track = dict(l.partition(" ")[::2] for l in out(
        repo, "for-each-ref", "--format=%(refname:short) %(upstream:track)", "refs/heads/claude/").splitlines())
    recorded = {}
    for line in launched_lines(repo):
        name, sha, via = parse_launched(line)
        if sha:
            recorded.setdefault(name, (sha, via))
    states, slug = [], None
    for path, name, gitdir in worktrees(repo)[1:]:
        if not name or not name.startswith("claude/") or name.endswith("-raw") or not path.is_dir():
            continue
        if late():
            return None
        state, why = "wip", "not on main"
        tip = out(repo, "rev-parse", "-q", "--verify", f"refs/heads/{name}")
        dirty = uncommitted(path)
        if dirty != 0:
            why = "uncommitted work" if dirty else "status unreadable"
        elif tip and committed_nothing(repo, name, tip):
            why = "nothing committed yet"
        elif tip and tgt:
            b = Branch(name)
            b.local = tip
            proof = prove(repo, b, tgt)
            rec = recorded.get(name)
            if rec and is_ancestor(repo, tip, rec[0]):
                state, why = "launched", f"recorded launched {rec[1]}"
            elif proof and track.get(name, "").strip() == "[gone]":
                state, why = "launched", f"merged on GitHub: {proof}"
            elif proof:
                state, why = "probably", f"{proof}, " + ("never pushed" if never_pushed(repo, name)
                                                         else "its GitHub copy is still there")
            elif track.get(name, "").strip() == "[gone]":
                why = "gone on GitHub, but commits after the merge"
                prev = (known or {}).get(name) or []
                # the persisted state (sync.py's worktree-states): `launched` from rename S3, both read
                if prev[:2] in ([tip, "landed"], [tip, "launched"]):
                    state, why = "launched", prev[2]
                elif not os.environ.get("CLAUDE_HOOK_NO_GITHUB") and not late():
                    if slug is None:
                        slug = common.repo_slug(out(repo, "remote", "get-url", "origin")) or ""
                    pr = common.merged_pr(slug, name, tip) if slug else None
                    if pr:
                        state, why = "launched", f"merged on GitHub: PR #{pr['number']} with this tip"
                if state == "wip":
                    hint = carried(repo, name, tip, tgt, late)
                    if hint:
                        state, why = "probably", f"gone on GitHub, {hint}"
            else:
                hint = probably(repo, b, tgt)
                if hint:
                    state, why = "probably", hint
        states.append((path, name, state, why, tip))
    if late():
        return None  # a carried() cut short reads as wip: keep the last write instead
    return states


def archive_ref(name, remote=False):
    return f"refs/archive/{'origin/' if remote else ''}{name}"


def archive(repo, b, reason, now=None):
    """Move one branch out of every list, keeping it as a backup: first each tip to
    refs/archive/… (with the reason in its reflog and a line in the `archived` record), then —
    each pinned to the commit archived — the local branch (`branch -D`, which also clears its
    config) and its copy on origin (a push --delete under a lease; the pre-push guard refuses
    deletions from anyone else, hence GIT_PUSH_OK, on the owner's standing D5). Returns (ok, phrase).
    Nothing is removed until its backup exists; a tip that moved since the proof stops there."""
    repo = Path(repo)
    date = time.strftime("%Y-%m-%d", time.localtime(now or time.time()))
    records = []
    for sha, remote in ((b.local, False), (b.remote, True)):
        if not sha or (remote and sha == b.local):
            continue  # one ref when both tips are the same commit
        ref = archive_ref(b.name, remote)
        r = git(repo, "update-ref", "--create-reflog", "-m", f"archived: {reason}", ref, sha)
        if r.returncode:
            return False, f"{b.name}: not archived ({(r.stderr or '').strip()[:80]})"
        records.append(f"{date} {sha} {ref} {reason}")
    path = common_dir(repo) / "claude" / ARCHIVE_NAME
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "a") as f:
        f.write("".join(f"{l}\n" for l in records))
    if b.local:
        if out(repo, "rev-parse", "-q", "--verify", f"refs/heads/{b.name}") != b.local:
            return False, f"{b.name}: archived, but the branch moved since the proof — kept"
        if git(repo, "branch", "-D", b.name).returncode:
            return False, f"{b.name}: archived, but the local branch could not be removed"
    if b.remote:
        r = git(repo, "push", "-q", f"--force-with-lease=refs/heads/{b.name}:{b.remote}", "origin",
                "--delete", b.name, env=dict(os.environ, GIT_PUSH_OK="1"), timeout=40)
        if r.returncode:
            return True, f"{b.name} (its GitHub copy kept: {(r.stderr or 'push failed').strip().splitlines()[-1][:60]})"
        git(repo, "update-ref", "-d", f"refs/remotes/origin/{b.name}")  # gone from VS Code without a fetch
    return True, b.name


def prune_archive(repo, now=None):
    """Delete each archive ref ARCHIVE_TTL_DAYS after its record's date — only if it still
    points at the recorded commit — and mark the line ` · pruned <date>`, so the record keeps
    answering "what happened to branch x" after the ref is gone. Returns how many."""
    path = common_dir(Path(repo)) / "claude" / ARCHIVE_NAME
    lines = read_lines(path)
    if not lines:
        return 0
    today = time.strftime("%Y-%m-%d", time.localtime(now or time.time()))
    cutoff = time.strftime("%Y-%m-%d", time.localtime((now or time.time()) - ARCHIVE_TTL_DAYS * 86400))
    kept, pruned = [], 0
    for line in lines:
        parts = line.split(" ", 3)
        if len(parts) >= 3 and " · pruned " not in line and parts[0] <= cutoff:
            date, sha, ref = parts[:3]
            if out(repo, "rev-parse", "-q", "--verify", ref) == sha:
                git(repo, "update-ref", "-d", ref, sha)
                line += f" · pruned {today}"
                pruned += 1
            elif not out(repo, "rev-parse", "-q", "--verify", ref):
                line += f" · pruned {today}"  # already gone (restored, or removed by hand)
        kept.append(line)
    path.write_text("".join(f"{l}\n" for l in kept))
    return pruned


def review_line(b):
    """The one command the owner runs for a probably-launched branch (D6): its evidence, then carry on
    or archive with their confirmation. `pickup` is wharf-runs' (G3): its path when installed, else
    the bare name and the module it comes with."""
    p = common.tool("pickup")
    return f"{p} review {b.name}" if p else f"pickup review {b.name} (with wharf-runs installed)"


def describe(b, now, full=False):
    parts = [age(now - b.when)]
    if b.empty:
        reason = reap_reason(b)[0]
        parts.insert(0, "seed" if reason == EMPTY_NEVER else
                     "seed, nothing committed after it" if reason.startswith("seed") else "empty")
    if b.superseded:
        parts.insert(0, "superseded")
    if b.files is not None:
        parts.append(f"{b.files} file{'s' if b.files != 1 else ''}")
    parts += [f"{doc}: {phrase}" for doc, phrase in b.reviews]
    if b.uncommitted is None and b.vetoed:
        parts.append("worktree status unreadable")
    elif b.uncommitted:
        parts.append(f"worktree has {b.uncommitted} uncommitted file{'s' if b.uncommitted != 1 else ''}")
    if b.vetoed:
        parts.append(f"commits {b.vetoed}")
    if not b.checked:
        parts.append("unchecked")
    if b.pr:
        parts.append(f"PR #{b.pr[0]}" + ("" if b.pr[1] == "open" else f" {b.pr[1]}"))
    if b.carried:  # survey() clears this for a proved branch: the pointer matters only until then
        parts.append("carried by " + ", ".join(f"{c} ({how})" for c, how in b.carried) + ", not proved")
    if full:
        parts.insert(0, b.where + (f", worktree {b.worktree}" if b.worktree else ""))
    return f"{b.name} ({', '.join(parts)})"


def session_note(repo, done, maybe, pending, now=None, archived=(), pruned=0, reaped=(), superseded_=()):
    """(for the owner, for the model) — the SessionStart message and the context line, or (None,
    None) when there is nothing to say. `archived` are the names sync.py just archived, `done`
    what stays launched (a worktree still holds it). No paste for the owner any more (D4–D6): launched
    branches are archived by the hook; a probably-launched one comes with its review command.
    Capped at SESSION_NOTE_MAX per group; `bin/repos --branches` has the rest. `reaped` are (branch, reason, task) for the empty ones sync.py just archived — each
    seed's task said once, so the idea is seen before it goes (R5); `superseded_` the names it
    archived as C1."""
    now = now or time.time()
    if not done and not maybe and not pending and not archived and not pruned and not reaped and not superseded_:
        return None, None
    repo = Path(repo).resolve()
    lines, capped = [], False

    def cap(group):
        nonlocal capped
        shown = group[:SESSION_NOTE_MAX]
        capped |= len(group) > len(shown)
        return shown, (f" (+{len(group) - len(shown)} more)" if len(group) > len(shown) else "")

    unfinished = [b for b in done if b.evidence]
    if archived:
        names = list(archived)
        lines.append(f"archived {len(names)} launched (kept {ARCHIVE_TTL_DAYS} days, then pruned): "
                     + ", ".join(names[:SESSION_NOTE_MAX]) + (f" +{len(names) - SESSION_NOTE_MAX}" if len(names) > SESSION_NOTE_MAX else ""))
    if reaped:
        clip = lambda t: t if len(t) <= 100 else t[:99] + "…"  # noqa: E731
        lines.append(f"reaped {len(reaped)} empty (kept {ARCHIVE_TTL_DAYS} days, then pruned): " + " · ".join(
            f"{name} ({reason})" + (f" — \"{clip(task)}\"" if task else "") for name, reason, task in reaped[:SESSION_NOTE_MAX])
            + (f" +{len(reaped) - SESSION_NOTE_MAX} (bin/repos --branches)" if len(reaped) > SESSION_NOTE_MAX else ""))
    if superseded_:
        names = list(superseded_)
        lines.append(f"archived {len(names)} superseded — every patch and added line on main (kept "
                     f"{ARCHIVE_TTL_DAYS} days, then pruned): " + ", ".join(names[:SESSION_NOTE_MAX])
                     + (f" +{len(names) - SESSION_NOTE_MAX}" if len(names) > SESSION_NOTE_MAX else ""))
    if pruned:
        lines.append(f"pruned {pruned} archive{'s' if pruned != 1 else ''} older than {ARCHIVE_TTL_DAYS} days")
    if done:
        shown, more = cap(done)
        suffix = ""
        if unfinished:
            suffix += " · open items — " + "; ".join(
                f"{b.name}: {b.open_items[len('open items: '):]}" for b in unfinished[:SESSION_NOTE_MAX])
        lines.append(f"{len(done)} launched, archived once nothing holds it{more}: "
                     + " · ".join(describe(b, now) for b in shown) + suffix)
    if maybe:
        shown, more = cap(maybe)
        lines.append("probably launched — yours to review: " + " · ".join(
            f"{describe(b, now)} → {review_line(b)}" for b in shown) + more)
    if pending:
        shown, more = cap(pending)
        lines.append("not on main: " + " · ".join(describe(b, now) for b in shown) + more)
    if capped:
        lines.append("the rest: bin/repos --branches")
    user = f"🌿 {repo.name}: " + "\n   ".join(lines)
    names = lambda group: ", ".join(b.name for b in group[:SESSION_NOTE_MAX]) + (  # noqa: E731
        f" +{len(group) - SESSION_NOTE_MAX}" if len(group) > SESSION_NOTE_MAX else "")
    model = f"{repo.name} idle claude/* branches — " + "; ".join(
        [f"archived {len(archived)}"] * bool(archived) + [f"reaped {len(reaped)} empty"] * bool(reaped)
        + [f"archived {len(superseded_)} superseded"] * bool(superseded_) + [
            f"{label} {len(group)}: {names(group)}" for label, group in
            (("launched", done), ("launched but open items", unfinished), ("probably launched", maybe),
             ("not on main", pending)) if group]) + \
        (". Launched branches are archived by the hook; probably-launched ones are " + WHO + "'s to review "
         "with `pickup review` — never run `pickup archive --confirmed`, which records their confirmation.")
    return user, model


def report(repo, done, maybe, pending, now=None, with_repo=True):
    """The full listing for the CLI and the weekly digest."""
    now = now or time.time()
    repo = Path(repo).resolve()
    lines = []
    finished = lambda b: f" · {b.open_items}"  # noqa: E731 — always a phrase, "not checked" included
    if done:
        lines.append(f"  launched ({len(done)}) — archived at the next session start once nothing holds them:")
        for b in done:
            lines.append(f"    {describe(b, now, full=True)} — {b.proof}{finished(b)}")
    if maybe:
        lines.append(f"  probably launched ({len(maybe)}) — {WHO}'s to review:")
        for b in maybe:
            lines.append(f"    {describe(b, now, full=True)} — {b.superseded or b.proof}{finished(b)}")
            if b.superseded:
                lines.append("      C1: archived at the next session start in this repo")
            else:
                lines.append(f"      {review_line(b)}")
    if pending:
        lines.append(f"  not on main ({len(pending)}):")
        for b in pending:
            if b.empty:
                reason, task, ttl, _ = reap_reason(b)
                lines.append(f"    {describe(b, now, full=True)} — {reason}, reaped after {ttl // 86400} days idle"
                             + (f": \"{task}\"" if task else ""))
            else:
                lines.append(f"    {describe(b, now, full=True)}")
    live = [l.split(" ", 3) for l in read_lines(common_dir(repo) / "claude" / ARCHIVE_NAME) if " · pruned " not in l]
    live = [a for a in live if len(a) == 4 and out(repo, "rev-parse", "-q", "--verify", a[2]) == a[1]]
    if live:
        lines.append(f"  archived ({len(live)}) — pruned {ARCHIVE_TTL_DAYS} days after the date; restore with the line shown:")
        for date, sha, ref, reason in live:
            name = re.sub(r"^refs/archive/(?:origin/)?", "", ref)
            lines.append(f"    {name} ({date}, {reason}) → git -C {shlex.quote(str(repo))} branch {shlex.quote(name)} {ref}")
    if not lines:
        lines.append("  no idle claude/* branches")
    return "\n".join(lines)


def open_prs(repo, timeout=5, strict=False):
    """{branch: (number, state, title)} for the repo's open pull requests, one request, or {}
    when there is no token, no GitHub remote, or CLAUDE_HOOK_NO_GITHUB is set (the tests).
    `strict`: None instead of {} whenever GitHub did not answer — a reaper must tell "no PR"
    from "not asked" (docs/record/branch-reaping-2026-10-04.md E2: no answer, no reap)."""
    miss = None if strict else {}
    if os.environ.get("CLAUDE_HOOK_NO_GITHUB"):
        return miss
    slug = common.repo_slug(out(repo, "remote", "get-url", "origin"))
    tok = common.token() if slug else None
    if not tok:
        return miss
    st, prs = common.api("GET", f"/repos/{slug}/pulls?state=open&per_page=100", tok=tok, timeout=timeout)
    if st != 200 or not isinstance(prs, list) or (strict and len(prs) >= 100):
        return miss  # a full page may hide more: "cannot tell" is never "no PR" to a reaper
    return {pr["head"]["ref"]: (pr["number"], pr["state"], pr.get("title") or "", pr.get("updated_at") or "")
            for pr in prs if pr.get("head")}


def closed_prs(repo, timeout=10):
    """{branch: (number, closed date)} for pull requests closed WITHOUT merging (C4), the newest
    100; {} offline or under CLAUDE_HOOK_NO_GITHUB."""
    if os.environ.get("CLAUDE_HOOK_NO_GITHUB"):
        return {}
    slug = common.repo_slug(out(repo, "remote", "get-url", "origin"))
    tok = common.token() if slug else None
    if not tok:
        return {}
    st, prs = common.api("GET", f"/repos/{slug}/pulls?state=closed&per_page=100&sort=updated&direction=desc",
                         tok=tok, timeout=timeout)
    if st != 200 or not isinstance(prs, list):
        return {}
    return {pr["head"]["ref"]: (pr["number"], (pr.get("closed_at") or "")[:10])
            for pr in prs if pr.get("head") and not pr.get("merged_at")}


def reap_guard(b, prs):
    """Why a branch with a GitHub copy may not be reaped now, or None. `prs` is open_prs(strict)
    — None when GitHub did not answer: skip this start, say nothing. An open PR not titled `WIP:`
    is a /finish in flight (`bin/pr ready` renames it). A never-pushed branch has no PR and
    reaps offline (E2)."""
    if not b.remote:
        return None
    if prs is None:
        return "GitHub did not answer whether it has a PR"
    pr = prs.get(b.name)
    if pr and not (pr[2] if len(pr) > 2 else "").startswith("WIP:"):
        return f"its PR #{pr[0]} is no longer WIP: — a /finish may be under way"
    return None
