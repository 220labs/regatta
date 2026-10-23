#!/usr/bin/env python3
"""SessionStart hook: bring `main` down from GitHub — in the repo the session opens and in
the two knowledge repos every session loads. The other half of "GitHub is the source of
truth between the two machines" (docs/record/repo-sync-2026-09-22.md, flow C); the checkpoint hook
sends work up, this brings `main` back. Before it existed the other Mac ran sessions against a
CLAUDE.md four commits stale, silently.

Per repo, in its PRIMARY checkout only (a session in a worktree still moves the primary's
main, never its own branch): fetch with prune; if HEAD is main and the tree is clean,
fast-forward to origin/main; say what moved. Never rebases, resets or stashes — a main with
commits origin lacks is reported, not touched. Also deletes local claude/* branches whose
upstream is gone (merged on GitHub, auto-deleted there) and no worktree holds — the one
deletion here, of a branch GitHub already removed.

At every start, unthrottled, a repo that keeps its opt-in in the layer's repos.json rather than in git (a
repo shared with people off this workflow: a shared repo) gets it written into its primary checkout
as an untracked, git-excluded .claude/workflow.json (overlay_workflow), after the layer's fast-forward.

Before pruning, the same pass tends the repo's `claude/*` worktrees that nobody is in — no
fresh lock, no running session owning, queued in or standing in them, no rebase or /finish
under way (docs/record/shipping-and-pickup-2026-09-25.md, the owner's D4 and D5):
  - one a dead session left DIRTY — it died mid-turn, so no Stop committed and no SessionEnd
    pushed, and nothing looked at it again (household `imessage-setup`: 3 files, 2.5 days) —
    gets one checkpoint through checkpoint.py's own path (secrets refused, the session's
    queued prompts quoted, its Claude-Session trailer), then one push, which opens its WIP PR
    if it had none. Only in a repo on the checkpoint workflow, and only when no dirty file
    changed within 2 h: a writer neither the lock nor the registry shows (a subagent writing
    through Bash, the owner by hand) is still at it. A push that fails or runs out of time leaves
    `sync-unpushed` in the worktree's state and is retried at the next start. A branch GitHub
    already merged and deleted is committed but never pushed: that would put it back, with a
    WIP PR of commits main has. From then on the branch is complete on origin and /pickup
    sees everything.
  - one that is CLEAN, whose branch GitHub deleted (`[gone]`: merged there) and whose tip is
    proved on main — hooks/branches.py's proof (an ancestor, or every changed file identical),
    else GitHub's merged PR whose head was exactly this tip — is removed with `git worktree
    remove`, so prune_gone takes the branch in the same pass and checkpoint.py's sweep the
    `-raw` within the hour. The third deletion the hooks make, same class as the other two:
    only what a merge already made redundant. Kept: a worktree holding any ignored file but a
    `.env` link and caches (a screenshot, a database), one whose tip is not proved (commits
    after the merge), and one whose `carries` record names a branch whose PR is still open,
    which `bin/pr carried` would close (carries_open).
    Kept ones say nothing: the branch note below lists their branch anyway.
  - one that is CLEAN, whose branch NEVER had an upstream (so it can never read `[gone]`),
    whose tip is proved on main and moved off where it was created, and that nothing touched
    for UNPUSHED_GRACE (7 days: last commit, reflog entry or lock) — removed through the same
    guards (carries, ignored files), and the branch archived in the same pass (the owner's D3,
    2026-09-29; docs/record/landed-indicator-2026-09-29.md). Until then the indicator locks it.
  - one that is CLEAN and whose branch holds NOTHING (hooks/branches.py empty(): made and never
    committed to, commits that net to nothing, or a `Seed:` commit with nothing after it), idle
    UNPUSHED_GRACE by branches.last_touch — removed through the same guards, its branch archived
    in the same step with the reason `empty: …`; a branch on GitHub only once GitHub said its PR
    is `WIP:` or absent (docs/record/branch-reaping-2026-10-04.md E2).
  - one carrying the /move marker (common.MOVED_FILE: its branch went on on another machine or
    in the cloud) is never committed or pushed — what is left in it went with the move — and
    `--worktrees` names it `moved to <host>`, and files changed in it after the move are said at
    every start. Clean, it is removed like the rest, marker and all, once its tip proves on main —
    which a tip the target went on from rarely does; `move --from` (E3) is what retires it
    (teleport design E4 and R7, 2026-10-02).
TEND_BUDGET seconds per repo, checked between steps; a fault costs only that repo's tending.
`git status` runs with --no-optional-locks here: it never refreshes another worktree's index.

After the fetch, the same pass takes the repo's idle `claude/*` branches (hooks/branches.py):
a launched one that nothing holds is ARCHIVED — moved to refs/archive/… with its proof as the
reason, its GitHub copy removed under a lease — and each archive is pruned seven days later
(The owner, 2026-09-26: branches are a last-resort backup, and managing them is never the owner's job;
coding-on-workflow D4–D6). Also archived, nothing holding them and idle REAP_AFTER: empty
branches (a seed nobody started after SEED_TTL, the owner's D1 = B) with each seed's task said once,
and C1-superseded ones — every commit's patch, every added line and a three-way merge on main
(docs/record/branch-reaping-2026-10-04.md E2, E8). Probably launched ones are listed with the `pickup
review` line for the owner; not on main, as before. No paste reaches the owner. Bounded by REPORT_BUDGET seconds per
repo; imported lazily, so a fault in it can never cost the fast-forward. The same note opens with
the autofinish runs that ended since the last start — launched as #N, stopped at a gate, died — each said
once (autofinished_line; bin/autofinish's header has the file).

  sync.py --report [<repo>]   print that branch note for one repo and nothing else: no fetch,
                              no prune, no fast-forward, no marker (read-only; the one network
                              call is a GET of the repo's open PRs for their numbers)
  sync.py --indicator [off|on] [<repo>]
                              write the lock VS Code shows on launched worktrees now and list
                              each claude/* worktree's state; off removes ours and keeps it
                              off at every start until on
  sync.py --worktrees [<repo>]
                              what the worktree pass would do to each claude/* worktree, and
                              why — acts on nothing, and reads [gone] and origin's branches as
                              of the last fetch
  sync.py --tend <repo>       the session start's pass for that one repo only — sync() and the
                              indicator, the same JSON out — without the knowledge repos, the
                              declared user settings, `secrets check --fix` or the sessionpipe
                              check: bin/tend's call, for a repo no session opens (launchd cannot
                              read Drive's _secrets; aurora-sequence open feedback, 2026-10-05)

Rate-limited to once per SYNC_EVERY per repo, since many sessions start in a day. Stdlib
only; never blocks a session from starting; offline is a quiet no-op.

One exception to the rate limit, and it costs the start nothing: every start also runs
the INDICATOR, detached — the launched and probably-launched claude/* worktrees go into VS Code's
`git.branchProtection`, which draws a lock on their branch in the Repositories view (the owner's
D1, 2026-09-29, docs/record/landed-indicator-2026-09-29.md). Its one message, a file it cannot
write, reaches the owner at the next start, once.
"""
import json
import os
import re
import subprocess
import sys
import time
import urllib.parse
from pathlib import Path

SYNC_EVERY = 600
# Seconds of git work per repo for the branch note; the rest is "unchecked". The hook keeps 6;
# the test suite raises it (CLAUDE_REPORT_BUDGET) so its counts do not depend on machine load.
REPORT_BUDGET = float(os.environ.get("CLAUDE_REPORT_BUDGET") or 6)
BUSY = ("rebase-merge", "rebase-apply", "MERGE_HEAD", "CHERRY_PICK_HEAD", "REVERT_HEAD")
# Seconds for the worktree pass per repo, checked before each worktree, each push and each
# GitHub lookup — not a hard cap: a first push that opens its WIP PR can take ~85 s on a bad
# network. Claude Code gives a command hook 600 s (2.1.282), so a slow start, never a killed
# one; what is left over waits for the next session start. The tests raise it.
TEND_BUDGET = float(os.environ.get("CLAUDE_TEND_BUDGET") or 20)
UNPUSHED = "sync-unpushed"  # per worktree: a D5 commit whose push failed or ran out of time
OWNER_TTL = 2 * 3600      # == common.OWNER_TTL, a copy: common is imported only lazily here — a lock idle this long has gone
CORE_MISSING = ("regatta core not found — clone the regatta repo, then write the config dir "
                "(the core's install.sh, or the overlay's bootstrap.sh --config)")
UNPUSHED_GRACE = 7 * 86400  # the owner, 2026-09-29 D3: a never-pushed branch on main goes after 7 days idle
# The indicator (docs/record/landed-indicator-2026-09-29.md): seconds of git per repo, in a detached
# run no start waits for; out of time, the last write stands. The home repo's 19 worktrees took
# 2.7–6 s on 2026-09-29 (6 with its GitHub lookups), so a 4 s budget there never finished.
INDICATOR_BUDGET = float(os.environ.get("CLAUDE_INDICATOR_BUDGET") or 60)
STATES_NAME = "worktree-states"  # per repo (common git dir): what the indicator last wrote
FINISHING_TTL = 2 * 3600  # == checkpoint.FINISHING_TTL: an older marker is an abandoned /finish
# Ignored files a merged worktree may hold and still be removed: regenerated, or a link.
DISPOSABLE = {".DS_Store", "__pycache__", ".pytest_cache", ".mypy_cache", ".ruff_cache", "node_modules"}
REGISTRY = Path(os.environ.get("CLAUDE_CONFIG_DIR") or "~/.claude").expanduser() / "sessions"
# The regatta core's hooks/ on the path (lib/core_path.py, C2), for the lazy `import common`s
# below; nothing when there is none, and main() says so in one line.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "lib"))
import core_path  # noqa: E402
import knowledge  # noqa: E402 — stdlib only: atlas's two keys, read before the core is known
core_path.add()
# The knowledge repos, fast-forwarded at every start beside the session's own (lib/knowledge.py:
# atlas's `atlas/layer` and `atlas/vault` keys, each with its own override variable); none
# without the keys, and main() says so in one line where an overlay should have written them.
KNOWLEDGE = knowledge.paths()


def git(repo, *args, timeout=30):
    return subprocess.run(["git", "-C", str(repo), *args], capture_output=True, text=True,
                          timeout=timeout)


def primary(cwd):
    """The primary checkout that owns this directory (through any worktree), or None."""
    r = git(cwd, "rev-parse", "--path-format=absolute", "--git-common-dir")
    if r.returncode:
        return None
    common = Path(r.stdout.strip())
    return common.parent.resolve() if common.name == ".git" else None


def main_branch(repo):
    try:
        cfg = json.loads((repo / ".claude" / "workflow.json").read_text())
        return cfg.get("main") or "main"
    except (OSError, ValueError):
        return "main"


def prune_gone(repo):
    """claude/* branches whose upstream no longer exists — merged and auto-deleted on GitHub —
    and that no worktree has checked out. Each is archived first (refs/archive/…, pruned after
    seven days, D4), then removed. Returns the names."""
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import branches  # noqa: E402
    refs = git(repo, "for-each-ref", "--format=%(refname:short) %(objectname) %(upstream:track)", "refs/heads/claude/")
    held = set(re.findall(r"^branch refs/heads/(\S+)$", git(repo, "worktree", "list", "--porcelain").stdout, re.M))
    gone = []
    for line in refs.stdout.splitlines():
        name, _, rest = line.partition(" ")
        sha, _, track = rest.partition(" ")
        if track.strip() == "[gone]" and name not in held:
            b = branches.Branch(name)
            b.local = sha
            # "gone", not "merged": a reaped seed's twin on the other machine reads [gone] too
            ok, _ = branches.archive(repo, b, "gone on GitHub")
            if ok:
                gone.append(name)
    return gone


def read_json(path):
    try:
        return json.loads(Path(path).read_text())
    except (OSError, ValueError):
        return None


def live_sessions():
    """{session id: cwd} for every Claude Code process running on this machine: its registry
    record (~/.claude/sessions/<pid>.json) with the pid alive. bin/pickup's test without the
    procStart match — a reused pid can only make this pass more careful."""
    live = {}
    for f in REGISTRY.glob("*.json"):
        e = read_json(f)
        if not isinstance(e, dict) or not e.get("sessionId"):
            continue
        try:
            os.kill(int(e.get("pid")), 0)
        except PermissionError:
            pass  # alive, another user's
        except (OSError, TypeError, ValueError):
            continue
        live[e["sessionId"]] = e.get("cwd") or ""
    return live


def inside(child, parent):
    try:
        Path(child).resolve().relative_to(Path(parent).resolve())
        return True
    except (ValueError, OSError):
        return False


def attended(path, gitdir, live, now):
    """Why someone may still be in this worktree, or None. Any doubt counts as someone."""
    state = gitdir / "claude"
    if any((gitdir / m).exists() for m in BUSY):
        return "a rebase or merge is in progress"
    finishing = state / "finishing"
    if finishing.exists() and now - finishing.stat().st_mtime < FINISHING_TTL:
        return "a /finish is running"
    owner = read_json(state / "owner.json") or {}
    if now - float(owner.get("seen") or 0) < OWNER_TTL:
        return "its lock is fresh"
    queued = {e.get("session") for e in (read_json(state / "prompts.json") or []) if isinstance(e, dict)}
    if ({owner.get("session")} | queued) & set(live):
        return "its session is running"
    if any(cwd and inside(cwd, path) for cwd in live.values()):
        return "a running session is in it"
    return None


def checkpointing(repo):
    """Whether the checkpoint hook commits in this repo — D5 commits only where it would."""
    if (repo / ".claude" / "no-workflow").exists():
        return False
    return bool((read_json(repo / ".claude" / "workflow.json") or {}).get("checkpoint"))


OVERLAY_PATH = ".claude/workflow.json"


def overlay_workflow(repo):
    """Write, refresh or remove the opt-in a repo keeps out of git (common.workflow_overlay:
    the repo's `workflow` in the registry, repos.json) as an untracked .claude/workflow.json in its
    primary checkout, listed in the clone's .git/info/exclude so `git status` stays clean and
    the fast-forward is never blocked by it. Runs at every start, unthrottled, after the
    registry's own fast-forward (main()): it must exist before the first prompt's checkpoint. Never touches
    a repo that tracks its own workflow.json or a hand-made one (no OVERLAY_MARK); removes its
    own beside .claude/no-workflow; keeps it when repos.json cannot be read. Readers that look
    only at the primary's file (bin/pickup's seed) see the repo from its first session start."""
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import common  # noqa: E402
    target = repo / OVERLAY_PATH
    if not git(repo, "ls-files", "--error-unmatch", OVERLAY_PATH).returncode:
        return []
    current = read_json(target) if target.exists() else None
    ours = isinstance(current, dict) and common.OVERLAY_MARK in current
    if target.exists() and not ours:
        return []
    cfg = None if (repo / ".claude" / "no-workflow").exists() else common.workflow_overlay(repo)
    if cfg == common.UNREADABLE:
        return [f"⚠ {repo.name}: the registry (repos.json) or the origin could not be read — "
                f"the workflow opt-in is {'kept as it was' if ours else 'not written'}"]
    if cfg is None:
        if ours:
            target.unlink()
            return [f"{repo.name}: off the worktree workflow — the registry (repos.json) no longer opts it in"
                    if not (repo / ".claude" / "no-workflow").exists()
                    else f"{repo.name}: off the worktree workflow — it carries .claude/no-workflow"]
        return []
    if not exclude(repo, "/" + OVERLAY_PATH):  # every start: a lost line would dirty main
        return [f"⚠ {repo.name}: {OVERLAY_PATH} is not ignored (a .gitignore un-ignores it?) — "
                "the workflow opt-in is not written"]
    # The note names the registry as the config dir's `wharf/repos.json` (before the scrub, by the
    # overlay's path): an opt-in written by an older sync.py is rewritten once, at its next start.
    want = {common.OVERLAY_MARK: "wharf/repos.json, written by hooks/sync.py; not in git, "
                                 "edit repos.json instead", **cfg}
    if current == want:
        return []
    write_atomic(target, json.dumps(want, indent=2) + "\n")  # checkpoint.py may read it any moment
    return [f"{repo.name}: on the worktree workflow from the registry (repos.json) "
            f"({'refreshed' if ours else 'written'}: {OVERLAY_PATH}, untracked, not in git)"]


def dirty_paths(porcelain_z):
    """The paths in `git status --porcelain -z` output; a rename's source (the field after it)
    is skipped."""
    items, out, skip = porcelain_z.split("\0"), [], False
    for item in items:
        if skip:
            skip = False
            continue
        if len(item) > 3:
            out.append(item[3:])
            skip = item[0] in "RC" or item[1] in "RC"
    return out


def in_place_entries(repo):
    """The records an opted-in repo writes on its main (workflow.json `in_place`; the vault's
    memory/, bulletin.md …), normalized; [] for a repo without them."""
    if not checkpointing(repo):
        return []
    v = (read_json(repo / ".claude" / "workflow.json") or {}).get("in_place")
    return [e.strip("/") for e in v if isinstance(e, str) and e.strip("/")] if isinstance(v, list) else []


def gated_dirt(repo):
    """Dirty paths of `repo` outside its in-place records — what keeps main from a fast-forward.
    Dirt under in_place does not (the owner's D3, 2026-09-29): git refuses a fast-forward that would
    overwrite a dirty file by itself (probed, docs/record/personal-on-workflow-2026-09-29.md section 1),
    and a record nobody else touched rides along untouched. bin/health uses this too."""
    entries = in_place_entries(repo)
    rels = dirty_paths(git(repo, "status", "--porcelain", "-z").stdout)
    return [r for r in rels if not any(r.rstrip("/") == e or r.startswith(e + "/") for e in entries)]


def recently_touched(path, rels, now, cap=500):
    """Whether any dirty path changed within OWNER_TTL — a writer the lock and the registry
    cannot see (a subagent writing only through Bash, a session editing a sibling worktree by
    path, the owner by hand) is still at it (review, 2026-09-25). A dead session's files are older
    than its lock. An untracked folder is walked: its own mtime misses edits deeper down."""
    seen = 0
    for rel in rels:
        top = path / rel.rstrip("/")
        for p in ([top] + (list(top.rglob("*"))[:cap] if top.is_dir() and not top.is_symlink() else [])):
            seen += 1
            try:
                if now - p.lstat().st_mtime < OWNER_TTL:
                    return True
            except OSError:
                continue  # deleted: nothing to date it by
            if seen > cap:
                return True  # too much to date cheaply: count it as someone's
    return False


def push_left(cp, state, name, sid):
    """publish(), then whether origin has the branch's tip. A miss leaves the UNPUSHED marker,
    so the next session start tries again — the worktree is clean by then and nothing else
    would look at it (review, 2026-09-25)."""
    pushed = cp.publish(state, name, sid, force=True)
    ahead = git(cp.ROOT, "rev-list", "--count", "@{u}..HEAD")
    if ahead.returncode == 0 and ahead.stdout.strip() == "0":
        (state / UNPUSHED).unlink(missing_ok=True)
        return pushed, True
    (state / UNPUSHED).write_text(sid)
    return pushed, False


def commit_left(repo, main, path, name, gitdir, deadline, merged=False):
    """D5: checkpoint what a dead session left in `path`, through checkpoint.py's own path, and
    push it — unless its branch was merged and deleted on GitHub (`merged`): a push would put
    the branch back, with a WIP PR of commits main already has, so that commit stays local and
    the note says so. Returns a note."""
    import checkpoint as cp  # noqa: E402 — lazily: only a dirty dead worktree pays for it
    state = gitdir / "claude"
    owner = read_json(state / "owner.json") or {}
    queue = cp.load_queue(state / "prompts.json")
    sid = owner.get("session") or next((e["session"] for e in reversed(queue) if e.get("session")), None) \
        or "unknown"
    cp.ROOT, cp.MAIN = str(path), main
    fallback = (f"wip: left by session {sid[:8]}, committed at session start "
                f"({cp.common.host_name()}, {time.strftime('%Y-%m-%d %H:%M')})")
    try:
        note, made = cp.checkpoint(None, [e["prompt"] for e in queue], fallback,
                                   claude_made_it=False, session=sid)
    except subprocess.CalledProcessError as exc:
        return f"⚠ {repo.name}: {path.name} holds files a dead session left; committing failed: " \
               f"{(exc.stderr or str(exc)).strip()[:160]}"
    if not made:
        return f"⚠ {repo.name}: {path.name} ({name}) holds files a dead session left — {note}" if note else None
    cp.save_queue(state / "prompts.json", [])
    sha = git(path, "rev-parse", "--short", "HEAD").stdout.strip()
    said = f"{repo.name}: committed what session {sid[:8]} left in {path.name} ({sha})"
    if merged:
        return said + f" — kept local: {name} was merged and deleted on GitHub; look before pushing"
    if time.monotonic() > deadline:
        (state / UNPUSHED).write_text(sid)
        return said + " — not pushed yet, out of time; the next session start pushes it"
    pushed, ok = push_left(cp, state, name, sid)
    return said + (f" · {pushed}" if pushed else "") + ("" if ok else " — not on origin yet; retried next start")


def push_again(repo, main, path, name, gitdir):
    """The retry for a D5 commit whose push missed (UNPUSHED). Returns a note."""
    import checkpoint as cp  # noqa: E402
    state = gitdir / "claude"
    cp.ROOT, cp.MAIN = str(path), main
    sid = (state / UNPUSHED).read_text().strip() or "unknown"
    pushed, ok = push_left(cp, state, name, sid)
    if ok:
        return f"{repo.name}: pushed what session {sid[:8]} left in {path.name}" + (f" · {pushed}" if pushed else "")
    return f"⚠ {repo.name}: {path.name} ({name}) still not on origin" + (f" — {pushed}" if pushed else "")


def keepers(path):
    """Ignored files in a worktree that removing it would lose — everything but DISPOSABLE and
    a `.env` link — or None when git could not say."""
    r = git(path, "--no-optional-locks", "status", "--porcelain", "--ignored", "-z")
    if r.returncode:
        return None
    kept = []
    for item in r.stdout.split("\0"):
        if not item.startswith("!! "):
            continue
        rel = item[3:].rstrip("/")
        leaf = Path(rel).name
        if leaf in DISPOSABLE or leaf.endswith(".pyc") or (leaf == ".env" and (path / rel).is_symlink()):
            continue
        kept.append(rel)
    return kept


def carries_open(repo, name, gitdir, deadline):
    """Why this worktree's carries record still has a job, or None once it is spent. `bin/pr
    carried --launched-via N` reads the record here to close the open PRs of the branches it took
    content from; removing the worktree would take the record along (review, 2026-09-24). What
    only it can still do is that close: the source's `launched`-file line (`landed` before S4) it also writes is a proof
    survey() makes for itself at the next start, from the source's own commits. So the record
    is spent once no source it names has an open PR.

    Six of the home repo's worktrees sat for days on records whose job was over (2026-09-29): `bin/pr
    merge` had run carried at each merge, found the partly carried source not yet on main, and
    left it open; each source then launched through its own PR, or the owner closed it. Nothing reads
    a record again after the merge, so a record that must be spent by hand is never spent.

    A source with no ref on origin has no open PR — GitHub closes a PR whose head is deleted —
    so only the rest cost a GitHub GET. In the hook that ref is as of this pass's pruning fetch;
    `--worktrees` fetches nothing, so it reads the last one. Offline, out of time or an answer
    that is not a list: kept, as before. The pointer itself survives the removal: remove_merged
    copies the record into the common dir's `carried` file, which branches.py reads too — a
    source closed unmerged (the home repo's serenade-script, #27) keeps its "carried by" note."""
    import branches  # noqa: E402
    sources = sorted({s for _, _, s in map(branches.parse_record,
                                             branches.read_lines(gitdir / "claude" / branches.CARRIES_NAME))
                      if s != name})
    on_origin = [s for s in sources
                 if git(repo, "rev-parse", "-q", "--verify", f"refs/remotes/origin/{s}").returncode == 0]
    if not on_origin:
        return None
    slug = branches.common.repo_slug(git(repo, "remote", "get-url", "origin").stdout.strip())
    tok = None if not slug or os.environ.get("CLAUDE_HOOK_NO_GITHUB") else branches.common.token()
    owner = (slug or "").split("/")[0]
    for s in on_origin:
        if not tok or time.monotonic() > deadline:
            return f"it carries {s}, and GitHub was not asked whether its PR is open"
        st, prs = branches.common.api("GET", f"/repos/{slug}/pulls?state=open&per_page=5&head="
                                             f"{owner}:{urllib.parse.quote(s, safe='')}", tok=tok)
        if st != 200 or not isinstance(prs, list):
            return f"it carries {s}, and GitHub did not say whether its PR is open"
        if prs:
            return f"it carries {s}, whose PR #{prs[0].get('number')} is still open"
    return None


def remove_merged(repo, main, path, name, gitdir, deadline, dry=False):
    """D4: remove a clean worktree whose branch is gone on GitHub and proved on main. Returns a
    note for a removal or a failure; None when it is kept (dry: a line either way)."""
    import branches  # noqa: E402
    tip = git(path, "rev-parse", "HEAD").stdout.strip()
    tgt = branches.target(repo, main)
    proof = None
    if tip and tgt:
        b = branches.Branch(name)
        b.local = tip
        proof = branches.prove(repo, b, tgt)
    if tip and not proof and time.monotonic() < deadline and not os.environ.get("CLAUDE_HOOK_NO_GITHUB"):
        # The file proof fails once main edits the same files again — the usual state of a
        # worktree left a day after its merge (the home repo's unraid-mgmt, PR #7). GitHub knows better.
        slug = branches.common.repo_slug(git(repo, "remote", "get-url", "origin").stdout.strip())
        pr = branches.common.merged_pr(slug, name, tip) if slug else None
        if pr:
            proof = f"PR #{pr['number']} merged with this tip"
    return drop(repo, path, name, gitdir, proof, dry, "merged",
                None if proof else f"gone on GitHub, but not proved on {main}", deadline)


def remove_unpushed(repo, main, path, name, gitdir, now, dry=False, deadline=float("inf")):
    """The owner's D3 of 2026-09-29 (docs/record/landed-indicator-2026-09-29.md): a clean worktree whose
    branch never had an upstream can never read `[gone]`, so remove_merged never sees it —
    branch-hygiene-2 sat four days with its tip on main. Removed once its commits are proved on
    main and nothing touched it for UNPUSHED_GRACE: until then the indicator shows it as
    probably launched. report() archives the branch in the same pass (kept 7 days more)."""
    import branches  # noqa: E402
    tip = git(path, "rev-parse", "HEAD").stdout.strip()
    tgt = branches.target(repo, main)
    if not tip or not tgt or branches.committed_nothing(repo, name, tip):
        return f"  keep    {path.name} ({name}): never pushed, nothing committed yet" if dry else None
    b = branches.Branch(name)
    b.local = tip
    proof = branches.prove(repo, b, tgt)
    if not proof:
        return f"  keep    {path.name} ({name}): never pushed, not on {main}" if dry else None
    last = branches.last_touch(repo, name, gitdir, [tip])  # the one idle clock (branch-reaping E1)
    if now - last < UNPUSHED_GRACE:
        left = int((UNPUSHED_GRACE - (now - last)) // 86400) + 1
        return (f"  keep    {path.name} ({name}): on {main}, never pushed — removed after "
                f"{UNPUSHED_GRACE // 86400} days idle ({left} d left)") if dry else None
    return drop(repo, path, name, gitdir, proof, dry, "never pushed, on main", deadline=deadline)


def remove_empty(repo, main, path, name, gitdir, b, found, now, prs, dry=False, deadline=float("inf"), reaped=None):
    """docs/record/branch-reaping-2026-10-04.md E2: a clean worktree whose branch holds nothing —
    made and never committed to, a seed adopted with nothing after it, or commits that net to
    nothing — goes after UNPUSHED_GRACE idle (branches.last_touch: tip, reflogs, the worktree's
    logs/HEAD, lock, state files), through drop()'s guards, and its branch is archived in the
    same step: report() would no longer know the branch had been adopted. [gone] is not needed —
    a seed reaped on the other machine leaves its twin here. A branch with a GitHub copy waits
    while GitHub has not answered (`prs()`, asked lazily, is None) or its PR is no longer `WIP:` (a /finish in
    flight). `found` is branches.empty()'s (reason, task); `reaped` collects (branch, reason,
    task) for the session note. Returns a note (dry: a line either way; else None when kept)."""
    import branches  # noqa: E402
    reason, task = found
    label = f"empty ({reason})"
    idle = now - branches.last_touch(repo, name, gitdir, b.tips)
    if idle < UNPUSHED_GRACE:
        left = int((UNPUSHED_GRACE - idle) // 86400) + 1
        return (f"  keep    {path.name} ({name}): {label} — removed after {UNPUSHED_GRACE // 86400} days "
                f"idle ({left} d left)") if dry else None
    held = branches.reap_guard(b, prs() if b.remote else None)  # GitHub asked only now, when it matters
    if held:
        return f"  keep    {path.name} ({name}): {label}, but {held}" if dry else None
    note = drop(repo, path, name, gitdir, f"idle {int(idle // 86400)} d", dry, label, deadline=deadline)
    if dry or path.exists():
        return note  # dry, or kept by drop()'s guards, or its removal failed (a ⚠ note)
    ok, phrase = branches.archive(repo, b, f"empty: {reason}")
    if not ok:
        return f"⚠ {repo.name}: removed empty worktree {path.name}; {phrase}"
    if reaped is not None:
        reaped.append((phrase, reason, task))
        return None
    return note


def drop(repo, path, name, gitdir, proof, dry, label, unproved=None, deadline=float("inf")):
    """The guards every removal shares, then `git worktree remove`. `proof` None = kept with
    `unproved` as the reason. Returns a note (dry: a line either way; else None when kept)."""
    carries = carries_open(repo, name, gitdir, deadline) if proof else None
    kept = keepers(path) if proof and not carries else None
    if dry:
        why = (unproved if not proof else
               f"{label}, but {carries} — bin/pr carried reads it here" if carries else
               f"{label}, but holds ignored {', '.join(kept[:3])}" if kept else
               f"{label}, but git could not list its ignored files" if kept is None else f"{label}: {proof}")
        return f"  {'remove' if proof and kept == [] else 'keep':<7} {path.name} ({name}): {why}"
    if not proof or kept != []:
        return None
    if not keep_carries(repo, name, gitdir):
        return None
    r = git(repo, "worktree", "remove", str(path))
    if r.returncode:
        return f"⚠ {repo.name}: could not remove {label} worktree {path.name}: {r.stderr.strip()[:160]}"
    return f"{repo.name}: removed {label} worktree {path.name} ({name}: {proof})"


def keep_carries(repo, name, gitdir):
    """Copy a worktree's carries record into the common dir's `carried` file before the worktree
    goes, so branches.py still says where a source's content went (carries_open). False when it
    could not be written: then the worktree stays."""
    import branches  # noqa: E402
    lines = branches.read_lines(gitdir / "claude" / branches.CARRIES_NAME)
    if not lines:
        return True
    record = branches.common_dir(repo) / "claude" / branches.CARRIED_NAME
    try:
        have = set(branches.read_lines(record))
        new = [f"{name} {l.strip()}" for l in lines if f"{name} {l.strip()}" not in have]
        record.parent.mkdir(parents=True, exist_ok=True)
        with record.open("a") as f:
            f.writelines(l + "\n" for l in new)
        return True
    except OSError:
        return False


def tend_worktrees(repo, main, cwd, dry=False, reaped=None):
    """D5, then D4, for every claude/* worktree nobody is in. Returns notes. `dry`: act on
    nothing and return one line per worktree saying what would happen and why. `reaped`
    collects the empty branches archived here, for report()'s note."""
    import branches  # noqa: E402
    import common  # noqa: E402 — the /move marker's reader
    deadline = time.monotonic() + TEND_BUDGET
    now, live, here = time.time(), live_sessions(), Path(cwd) if cwd else None
    commits = checkpointing(repo)
    tgt, prs = branches.target(repo, main), []

    def emptiness(path, name):
        b = branches.Branch(name)
        b.local = git(path, "rev-parse", "HEAD").stdout.strip() or None
        b.remote = branches.out(repo, "rev-parse", "-q", "--verify", f"refs/remotes/origin/{name}") or None
        return b, (branches.empty(repo, b, tgt, worktree=path) if b.local and tgt else None)

    def asked():  # one GET of the open PRs per pass, only once a branch with a GitHub copy needs it
        if not prs:
            prs.append(branches.open_prs(repo, strict=True) if time.monotonic() < deadline else None)
        return prs[0]
    tracks = git(repo, "for-each-ref", "--format=%(refname:short) %(upstream:track)", "refs/heads/claude/")
    gone = {l.partition(" ")[0] for l in tracks.stdout.splitlines() if l.partition(" ")[2].strip() == "[gone]"}
    notes = []
    say = lambda verb, path, name, why: notes.append(f"  {verb:<7} {path.name} ({name}): {why}")  # noqa: E731
    for path, name, gitdir in branches.worktrees(repo)[1:]:
        if not name or not name.startswith("claude/") or name.endswith("-raw") or gitdir is None:
            continue
        why = ("missing on disk" if not path.is_dir() else "the session opens in it"
               if here and inside(here, path) else attended(path, gitdir, live, now))
        if why:
            if dry:
                went = common.moved(gitdir / "claude") if path.is_dir() else None
                say("keep", path, name, why + (f" — {common.moved_line(went)}" if went else ""))
            continue
        if time.monotonic() > deadline:
            notes.append(f"{repo.name}: worktree pass out of time at {path.name}; the rest next start")
            break
        status = git(path, "--no-optional-locks", "status", "--porcelain", "-z")
        if status.returncode:
            continue
        rels = dirty_paths(status.stdout)
        files = len(rels)
        went = common.moved(gitdir / "claude")
        # Empty (docs/record/branch-reaping-2026-10-04.md): only for a clean worktree the /move marker
        # does not hand elsewhere — a moved branch may be growing on the other machine.
        b, found = (None, None) if files or went else emptiness(path, name)
        if went and (files or (gitdir / "claude" / UNPUSHED).exists()):
            # The /move marker: the branch goes on elsewhere — never committed or pushed here (a
            # commit would fork the branch from the one growing there). Files changed after the
            # move are said at every start: nothing else would carry them. Clean, it goes the
            # way any other does below — but only once its tip proves, and a tip the target
            # rewrote rarely does (review, 2026-10-02: E3's return leg is the real cleanup).
            if dry:
                say("keep", path, name, common.moved_line(went)
                    + (f" — {files} uncommitted left behind" if files else ""))
            elif files:
                notes.append(f"⚠ {repo.name}: {path.name} ({name}) {common.moved_line(went)}, "
                             f"but {files} file(s) changed here since — not committed; carry them over or drop them")
        elif files and not commits:
            if dry:
                say("keep", path, name, f"{files} uncommitted, but the repo is off the checkpoint workflow")
        elif files and recently_touched(path, rels, now):
            if dry:
                say("keep", path, name, f"{files} uncommitted, changed within 2 h — someone may be at it")
        elif files:
            if dry:
                say("commit", path, name, f"{files} uncommitted, nobody in it"
                    + (" — kept local: merged on GitHub" if name in gone else ""))
            else:
                notes.append(commit_left(repo, main, path, name, gitdir, deadline, merged=name in gone))
        elif commits and (gitdir / "claude" / UNPUSHED).exists() and name not in gone:
            if dry:
                say("push", path, name, "a commit made at an earlier session start is not on origin yet")
            else:
                notes.append(push_again(repo, main, path, name, gitdir))
        elif name in gone and not (found and found[0].startswith("seed")):
            notes.append(remove_merged(repo, main, path, name, gitdir, deadline, dry))
        elif found:
            notes.append(remove_empty(repo, main, path, name, gitdir, b, found, now,
                                      asked, dry, deadline, reaped))
        elif branches.never_pushed(repo, name):
            notes.append(remove_unpushed(repo, main, path, name, gitdir, now, dry, deadline))
        elif dry:
            say("keep", path, name, common.moved_line(went) if went else "clean, its branch is not gone on GitHub")
    return [n for n in notes if n]


def reap_candidates(branches, maybe, pending, now):
    """(branch, reason, task, group) that report(act) may archive besides the launched ones
    (docs/record/branch-reaping-2026-10-04.md E2, E8): empty branches — a seed nobody started after
    SEED_TTL, the rest after REAP_AFTER idle — and C1-superseded ones after REAP_AFTER. Never one
    a worktree holds (tend_worktrees has those), a fresh lock, or a carries pointer names."""
    found = []
    for group in (pending, maybe):
        for b in group:
            # touched 0 is "the clock was not read", never "idle since 1970" (review, 2026-10-04)
            if b.worktree is not None or b.live or b.carried or not b.checked or not b.touched:
                continue
            if group is pending and b.empty:
                reason, task, ttl, clock = branches.reap_reason(b)
                if now - clock >= ttl:
                    found.append((b, reason, task, group))
            elif group is maybe and b.superseded and now - b.touched >= branches.REAP_AFTER:
                found.append((b, b.superseded, "", group))
    return found


AUTOFINISHED_SHOWN = 6  # ended runs named per start; the rest are in `bin/repos --branches`


def autofinished_line(repo, act):
    """The repo's autofinish runs that ended since the last start said them — the lines E1's
    runner appends to <common git dir>/claude/autofinished (bin/autofinish's header) — as one
    line, or None. Each is said once: `act` (a session start) records how many were said; the
    read-only --report shows the unsaid ones and records nothing. Design section 7: "the next
    session start in that repo says it once"."""
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import common  # noqa: E402 — lazily, like branches: a fault here costs only this line
    cdir = Path(git(repo, "rev-parse", "--path-format=absolute", "--git-common-dir").stdout.strip())
    ended = common.autofinished(cdir)
    said_path = cdir / "claude" / (common.AUTOFINISHED + ".said")
    try:
        said = int(said_path.read_text().strip() or 0)
    except (OSError, ValueError):
        said = 0
    if said > len(ended):
        said = 0  # the file was cut short: what it holds now is new
    new = ended[said:]
    if act and new:
        said_path.write_text(f"{len(ended)}\n")
    if not new:
        return None
    shown = new[-AUTOFINISHED_SHOWN:]
    more = f" (+{len(new) - len(shown)} more: bin/repos --branches)" if len(new) > len(shown) else ""
    return f"🤖 {Path(repo).name} autofinish: " + " · ".join(common.autofinished_phrase(e) for e in shown) + more


def report(repo, main=None, act=False, reaped=None):
    """(note for the owner, context for the model) about the repo's idle branches, or (None, None).
    With `act` (the session start, never --report), launched branches nothing holds are archived,
    then empty and superseded ones past their idle time (reap_candidates; each with a GitHub
    copy only once GitHub said its PR is `WIP:` or absent), and old archives pruned. `reaped`
    holds what tend_worktrees already reaped, for the same note. Any failure is one line for
    the owner and never a lost session start. The PR lookup is skipped when nothing is idle, so a
    quiet repo costs no network. The runs autofinish ended since the last start come first
    (autofinished_line), for both readers."""
    try:
        af = autofinished_line(repo, act)
    except Exception as exc:
        af = f"⚠ autofinish lines for {Path(repo).name} failed: {exc}"
    user, model = _report(repo, main, act, reaped)
    if not af:
        return user, model
    return "\n".join(x for x in (af, user) if x), "\n".join(x for x in (af, model) if x)


def _report(repo, main, act, reaped):
    try:
        sys.path.insert(0, str(Path(__file__).resolve().parent))
        import branches  # noqa: E402 — lazily: a fault here must not reach the fast-forward
        main = main or main_branch(repo)
        deadline = time.monotonic() + REPORT_BUDGET
        done, maybe, pending = branches.survey(repo, main, deadline=deadline, reaping=act)
        archived, pruned, failed, reaped, gone_super = [], 0, [], list(reaped or []), []
        prs = None
        if (maybe or pending) and time.monotonic() < deadline:
            prs = branches.open_prs(repo, strict=True)
            for b in maybe + pending:
                b.pr = (prs or {}).get(b.name)
        if pending and time.monotonic() < deadline:  # E14: what the PR lookup left of the budget
            branches.add_reviews(repo, pending, main, deadline=deadline)
        if act:
            for b in [b for b in done if b.worktree is None and not b.live]:
                ok, phrase = branches.archive(repo, b, f"launched: {b.proof}")
                (archived if ok else failed).append(phrase)
                if ok:
                    done.remove(b)
            for b, reason, task, group in reap_candidates(branches, maybe, pending, time.time()):
                if branches.reap_guard(b, prs):
                    continue  # offline, or a /finish in flight: the next start looks again, quietly
                why = reason if reason.startswith("superseded") else f"empty: {reason}"
                ok, phrase = branches.archive(repo, b, why)
                if not ok:
                    failed.append(phrase)
                    continue
                group.remove(b)
                if group is maybe:
                    gone_super.append(phrase)
                else:
                    reaped.append((phrase, reason, task))
            pruned = branches.prune_archive(repo)
        user, model = branches.session_note(repo, done, maybe, pending, archived=archived, pruned=pruned,
                                            reaped=reaped, superseded_=gone_super)
        if failed:
            user = (user or f"🌿 {Path(repo).name}:") + "\n   ⚠ " + "; ".join(failed)
        return user, model
    except Exception as exc:
        return f"⚠ branch report for {Path(repo).name} failed: {exc}", None


def sync(repo, cwd=None):
    """One repo. Returns (notes for the owner, notes for the model), each possibly empty. `cwd` is
    where the session opens: a worktree it is in is never tended."""
    name = repo.name
    if git(repo, "remote", "get-url", "origin").returncode:
        return [], []
    gitdir = Path(git(repo, "rev-parse", "--path-format=absolute", "--git-common-dir").stdout.strip())
    marker = gitdir / "claude" / "synced"
    if marker.exists() and time.time() - marker.stat().st_mtime < SYNC_EVERY:
        return [], []
    marker.parent.mkdir(parents=True, exist_ok=True)
    marker.touch()
    if any((gitdir / m).exists() for m in BUSY):
        return [], []
    try:
        if git(repo, "fetch", "-q", "--prune", "origin", timeout=40).returncode:
            return [], []  # offline: nothing to report, try again in SYNC_EVERY
    except subprocess.TimeoutExpired:
        return [], []
    notes, reaped = [], []
    main = main_branch(repo)
    try:
        sys.path.insert(0, str(Path(__file__).resolve().parent))
        notes += tend_worktrees(repo, main, cwd, reaped=reaped)
    except Exception as exc:  # the fast-forward below must still happen
        notes.append(f"⚠ {name}: the worktree pass failed: {exc}")
    pruned = prune_gone(repo)
    if pruned:
        notes.append(f"{name}: archived merged {', '.join(pruned)} (kept 7 days)")
    head = git(repo, "symbolic-ref", "--quiet", "--short", "HEAD").stdout.strip()
    counts = git(repo, "rev-list", "--left-right", "--count", f"{main}...origin/{main}")
    if head == main and not counts.returncode:
        ahead, behind = (int(x) for x in counts.stdout.split())
        if behind and not ahead:
            try:  # answers typed here that a launched branch carried (hooks/carried.py)
                import carried  # noqa: E402 — lazily, and a fault in it never costs the fast-forward
                settled = carried.settle(repo, f"origin/{main}", whole=True)
                if settled:
                    notes.append(f"{name}: discarded the primary's copy of {', '.join(settled)} — "
                                 "main carries it, line for line or recorded verbatim (copy in .git/claude/carried/)")
            except Exception as exc:
                notes.append(f"⚠ {name}: the carried-answers check failed: {exc}")
            if gated_dirt(repo):
                notes.append(f"{name}: main is {behind} behind origin, left alone — the tree is dirty")
            elif git(repo, "merge", "-q", "--ff-only", f"origin/{main}").returncode == 0:
                notes.append(f"{name}: main +{behind} from origin")
            else:
                notes.append(f"{name}: main could not fast-forward to origin")
        elif ahead and not behind:
            notes.append(f"{name}: main has {ahead} commit{'s' if ahead != 1 else ''} origin lacks — push it")
        elif ahead and behind:
            notes.append(f"{name}: main diverged from origin ({ahead} here, {behind} there) — resolve by hand")
    for_model = list(notes)
    user_note, model_note = report(repo, main, act=True, reaped=reaped)
    if user_note:
        notes.append(user_note)
    if model_note:
        for_model.append(model_note)
    return notes, for_model


def settings_file(repo):
    """(path, None) — where the indicator writes `git.branchProtection` for this repo — or
    (None, why not). A git-ignored `<repo>.code-workspace` (the home repo regenerates one and keeps
    its `settings`) wins; else `.vscode/settings.json`, only while git does not track it: the
    hook never edits a committed file, and excludes this one so `main` stays clean."""
    ws = repo / f"{repo.name}.code-workspace"
    if ws.exists() and git(repo, "check-ignore", "-q", ws.name).returncode == 0:
        return ws, None
    vs = repo / ".vscode" / "settings.json"
    if git(repo, "ls-files", "--error-unmatch", ".vscode/settings.json").returncode == 0:
        return None, ".vscode/settings.json is tracked"
    return vs, None


def exclude(repo, line="/.vscode/settings.json"):
    """Add the line to the repo's info/exclude (shared by every worktree) once. True when git
    then ignores the file: a `!.vscode/settings.json` in a .gitignore beats info/exclude
    (gitignore(5)), and the file would dirty `main` and stop its fast-forward (review)."""
    gitdir = Path(git(repo, "rev-parse", "--path-format=absolute", "--git-common-dir").stdout.strip())
    path = gitdir / "info" / "exclude"
    text = path.read_text() if path.exists() else ""
    if line not in text.splitlines():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text + ("" if not text or text.endswith("\n") else "\n") + line + "\n")
    return git(repo, "check-ignore", "-q", line.lstrip("/")).returncode == 0


def write_atomic(path, text):
    """Replace the file in one step: a reader (VS Code, the home repo's workspace script, which
    rebuilds from nothing on a JSON error) never sees it half-written."""
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(f".{path.name}.{os.getpid()}.tmp")
    tmp.write_text(text)
    os.replace(tmp, path)


def indicator(repo, main=None, mode=None):
    """The lock on launched worktrees in VS Code's Repositories view (the owner's D1 of 2026-09-29,
    docs/record/landed-indicator-2026-09-29.md): VS Code draws `$(lock)` for a branch listed in
    `git.branchProtection`, so the launched and probably-launched claude/* branches go there — local
    only, nothing renamed. Only names this wrote before are ever removed; the owner's own entries
    stay. `mode` "off" removes ours and keeps them off at every later start until "on".
    Runs detached at each session start (spawn_indicator): the home repo's 19 worktrees cost 3–6 s,
    which no start should wait for (review). One run at a time per repo (flock); a second one
    leaves. A problem goes in the record's `problem`; indicator_notes() says it at a start, once."""
    import branches  # noqa: E402
    import fcntl  # noqa: E402 — POSIX only, as every machine running these hooks is
    common = Path(git(repo, "rev-parse", "--path-format=absolute", "--git-common-dir").stdout.strip())
    record = common / "claude" / STATES_NAME
    record.parent.mkdir(parents=True, exist_ok=True)
    with open(record.with_name(STATES_NAME + ".lock"), "w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            return  # another start is writing it now
        prev = read_json(record) or {}
        off = mode == "off" or (bool(prev.get("off")) and mode != "on")
        if off:
            states = []
        else:
            states = branches.worktree_states(repo, main or main_branch(repo),
                                              deadline=time.monotonic() + INDICATOR_BUDGET, known=prev.get("states"))
            if states is None:
                return  # out of time: the last write stands
        names = sorted(n for _, n, s, _, _ in states if s != "wip")
        ours = set(prev.get("names") or [])
        path, problem = settings_file(repo)
        created = bool(prev.get("created"))
        if path is not None and (names or ours):
            data = read_json(path) if path.exists() else {}
            if not isinstance(data, dict):
                path, problem = None, f"{path.name} is not plain JSON (comments?)"
            elif path.name == "settings.json" and not exclude(repo):
                path, problem = None, ".vscode/settings.json is not ignored (a .gitignore un-ignores it?)"
            else:
                target = data.setdefault("settings", {}) if path.suffix == ".code-workspace" else data
                current = list(target.get("git.branchProtection") or [])
                wanted = list(dict.fromkeys([x for x in current if x not in ours] + names))
                if wanted != current:
                    if wanted:
                        target["git.branchProtection"] = wanted
                    else:
                        target.pop("git.branchProtection", None)
                    if not data and path.name == "settings.json" and created:
                        path.unlink(missing_ok=True)
                        created = False
                    else:
                        created = created or not path.exists()
                        write_atomic(path, json.dumps(data, indent=2, ensure_ascii=False) + "\n")
        text = json.dumps({
            "file": str(path) if path else None, "names": names if path else sorted(ours),
            "created": created, "off": off, "problem": problem if (names or ours) else None,
            "states": {n: [tip, s, why, str(p)] for p, n, s, why, tip in states}}, indent=1, ensure_ascii=False) + "\n"
        if not record.exists() or record.read_text() != text:
            write_atomic(record, text)


def spawn_indicator(repo):
    """indicator() in a detached child, so the session start never waits for it (review,
    2026-09-29). CLAUDE_INDICATOR_INLINE=1 runs it in place — the tests read its result."""
    if os.environ.get("CLAUDE_INDICATOR_INLINE"):
        indicator(repo)
        return
    subprocess.Popen([sys.executable, str(Path(__file__).resolve()), "--indicator-run", str(repo)],
                     stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                     start_new_session=True)


def indicator_notes(repo):
    """The problem the last indicator run recorded, once per distinct problem: the start
    keeps what it said in its own file, which the detached run never writes."""
    common = Path(git(repo, "rev-parse", "--path-format=absolute", "--git-common-dir").stdout.strip())
    problem = (read_json(common / "claude" / STATES_NAME) or {}).get("problem") or ""
    said = common / "claude" / (STATES_NAME + ".said")
    if problem == (said.read_text() if said.exists() else ""):
        return []
    said.parent.mkdir(parents=True, exist_ok=True)
    said.write_text(problem)
    return [f"⚠ {repo.name}: launched-worktree lock not shown — {problem}"] if problem else []


def secrets_notes(repo):
    """`secrets check --fix` for the session's repo (the core's bin/secrets): a key its
    .env.example names and Drive's file lacks becomes an empty `KEY=` there, and the lines worth
    a look come back — `!!` failures, `--` waiting. Quiet when all is well; a missing tool or a
    slow Drive never blocks the start. The tool through common.tool(), never beside a knowledge
    repo (the B5 review: that path breaks once the overlay's shims go, B14)."""
    if not repo or not (repo / ".env.example").exists():
        return []
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import common  # noqa: E402
    tool = common.tool("secrets")
    if not tool:
        return []
    try:
        r = subprocess.run([sys.executable, str(tool), "check", str(repo), "--fix"],
                           capture_output=True, text=True, timeout=20)
    except Exception as exc:
        return [f"secrets check: {exc}"]
    return [line for line in (r.stdout + r.stderr).splitlines() if line.startswith(("!!", "--"))][:6]


def user_settings_notes():
    """The declared user settings (docs/record/machine-settings-2026-09-29.md): apply them when
    settings/user.json changed since this Mac last did, and tell the model about drift. No
    network, three small JSON reads when nothing changed; outside the per-repo rate limit.
    It runs after the knowledge repos' fast-forward above, so a declaration that merged
    elsewhere is applied at the session start that pulls it (the one that pulls a new sync.py
    still runs the old one — R2)."""
    import common  # noqa: E402 — claude-settings is lighthouse's: through common.tool(), absent → nothing (G8)
    tool = common.tool("claude-settings")
    if not tool or not tool.exists():
        return [], []
    try:
        r = subprocess.run([sys.executable, str(tool), "session-start"], capture_output=True,
                           text=True, timeout=5)
        out = json.loads(r.stdout or "{}")
        return out.get("user") or [], out.get("model") or []
    except Exception as exc:  # a settings note is never worth a session start
        return [f"⚠ settings: {exc}"], []


def sheep_notes():
    """sessionpipe hook entries without the vault's gate (bin/sheep; orchestration proposal
    E1, R1): a `sessionpipe install` or `update` rewrites every entry ungated, and from then on
    a vault session reports like any other. One read of settings.json while sessionpipe is
    not installed; quiet while every entry is gated. On a Mac where the control daemon is paired,
    also what `sheep control` would fix and a plist only `pair` repairs (session-listen B1)."""
    if os.environ.get("CLAUDE_HOOK_NO_SHEEP"):  # the suites (the switch checkpoint.py and keel use for the page mirror too): this Mac's hooks and daemon are not theirs
        return []
    import common  # noqa: E402 — sheep is keel's: through common.tool(), absent → nothing
    tool = common.tool("sheep")
    lives = [Path(os.environ.get("CLAUDE_CONFIG_DIR") or "~/.claude").expanduser() / "settings.json",
             Path("~/.claude/settings.json").expanduser()]  # a login dir never hooked has no "sessionpipe"
    try:
        if not tool or not tool.exists() or not any(p.exists() and "sessionpipe" in p.read_text(encoding="utf-8")
                                        for p in lives):
            return []
        from importlib.machinery import SourceFileLoader
        mod = SourceFileLoader("sheep", str(tool)).load_module()
        total, _, _, _, dark = mod.hook_totals()
    except Exception as exc:  # never worth a session start
        return [f"⚠ sheep check: {exc}"]
    out = []
    if total["ungated"]:
        out.append(f"⚠ sessionpipe: {total['ungated']} hook entr{'y' if total['ungated'] == 1 else 'ies'} "
                   f"without the vault's gate — run {tool} gate")
    if dark:
        out.append(f"⚠ sessionpipe: {', '.join(str(p.parent) for p in dark)} never hooked — "
                   f"its sessions do not reach the page mirror; run {tool} gate")
    try:  # the control daemon on a paired Mac (session-listen B1): a repo it cannot reach, a stale plist
        out.extend(mod.control_notes())
    except Exception as exc:
        out.append(f"⚠ sheep control: {exc}")
    return out


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "--worktrees":
        repo = primary(Path(sys.argv[2] if len(sys.argv) > 2 else ".").expanduser())
        if repo is None:
            sys.exit("sync.py --worktrees: not inside a git repo")
        sys.path.insert(0, str(Path(__file__).resolve().parent))
        lines = tend_worktrees(repo, main_branch(repo), Path.cwd(), dry=True)
        print("\n".join([f"{repo.name}: {'on' if checkpointing(repo) else 'off'} the checkpoint workflow"]
                        + (lines or ["  no claude/* worktrees"])))
        return
    if len(sys.argv) > 2 and sys.argv[1] == "--indicator-run":  # spawn_indicator's detached child
        sys.path.insert(0, str(Path(__file__).resolve().parent))
        indicator(Path(sys.argv[2]))
        return
    if len(sys.argv) > 1 and sys.argv[1] == "--indicator":
        mode = sys.argv[2] if sys.argv[2:3] in (["off"], ["on"]) else None
        rest = sys.argv[3:] if mode else sys.argv[2:]
        repo = primary(Path(rest[0] if rest else ".").expanduser())
        if repo is None:
            sys.exit("sync.py --indicator: not inside a git repo")
        sys.path.insert(0, str(Path(__file__).resolve().parent))
        indicator(repo, mode=mode)
        rec = read_json(Path(git(repo, "rev-parse", "--path-format=absolute", "--git-common-dir").stdout.strip())
                        / "claude" / STATES_NAME) or {}
        mark = {"launched": "🔒 launched", "landed": "🔒 launched", "probably": "🔒 probably", "wip": "   wip     "}
        head = f"{repo.name}: git.branchProtection in {rec.get('file') or 'nothing'}" + (
            " — off (sync.py --indicator on)" if rec.get("off") else "") + (
            f" — ⚠ {rec['problem']}" if rec.get("problem") else "")
        print("\n".join([head] + [f"  {mark.get(v[1], v[1])} {Path(v[3]).name} — {v[2]}"
                                  for v in (rec.get("states") or {}).values()]))
        return
    if len(sys.argv) > 1 and sys.argv[1] == "--report":
        repo = primary(Path(sys.argv[2] if len(sys.argv) > 2 else ".").expanduser())
        if repo is None:
            sys.exit("sync.py --report: not inside a git repo")
        user_note, model_note = report(repo)
        print(user_note or f"{repo.name}: no idle claude/* branches")
        if model_note:
            print("[context] " + model_note)
        return
    if sys.argv[1:2] == ["--tend"]:
        if len(sys.argv) < 3:  # never fall through to the whole session start
            sys.exit("usage: sync.py --tend <repo>")
        repo = primary(Path(sys.argv[2]).expanduser())
        if repo is None:
            sys.exit("sync.py --tend: not inside a git repo")
        u, m = tend_repo(repo, repo)
        emit(u, m)
        return
    try:
        data = json.loads(sys.stdin.read() or "{}")
    except ValueError:
        data = {}
    # The session start needs the core (common, and checkpoint and branches, which import it).
    # Without it every step below would fail on its own and say so: one line instead, a quiet
    # exit (docs/regatta-modules-2026-10-16.md C4).
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    try:
        import common  # noqa: F401,E402
    except ImportError as exc:
        print(f"sync: {CORE_MISSING} ({exc})", file=sys.stderr)
        return
    gone = knowledge.missing()
    if gone:
        print(f"sync: {', '.join(gone)} missing from the regatta config dir — no knowledge repo "
              "fast-forwarded (the overlay's bootstrap.sh --config writes them)", file=sys.stderr)
    record_account(data)
    cwd = Path(data.get("cwd") or os.environ.get("CLAUDE_PROJECT_DIR") or ".")
    repos, seen = [], set()
    for repo in [primary(cwd), *[p for p in KNOWLEDGE if (p / ".git").is_dir()]]:
        if repo and repo.resolve() not in seen:
            seen.add(repo.resolve())
            repos.append(repo)
    for_user, for_model = [], []
    for r in repos:
        u, m = tend_repo(r, cwd)
        for_user.extend(u)
        for_model.extend(m)
    for r in repos:  # after the loop: the layer's repos.json has just been fast-forwarded
        try:
            overlaid = overlay_workflow(r)
        except Exception as exc:  # a missing opt-in only costs checkpoints, never the start
            overlaid = [f"⚠ {r.name}: the repos.json opt-in failed: {exc}"]
        for_user.extend(overlaid)
        for_model.extend(overlaid)
    # The secrets lines are for both readers: the owner acts on a `!!`, the model must not
    # build on a key that is still `--` waiting.
    secrets = secrets_notes(primary(cwd))
    for_user.extend(secrets)
    for_model.extend(secrets)
    u, m = user_settings_notes()
    for_user.extend(u)
    for_model.extend(m)
    sheep = sheep_notes()  # both readers: the model can run the fix, the owner sees the leak
    for_user.extend(sheep)
    for_model.extend(sheep)
    emit(for_user, for_model)


def record_account(data):
    """Which account this session runs on, for usage-report (work-account E6): one line
    {"session", "account", "t"} in <data>/<host>/accounts.jsonl — usage-report's own data folder,
    which `pull` already brings from the other Macs. The label is the registry row whose dir this
    session runs under (CLAUDE_CONFIG_DIR, else ~/.claude); none known → nothing written. The
    registry is lighthouse's: the config dir's `lighthouse/accounts.json`, $ACCOUNTS_FILE in tests,
    as the core's login_dirs() reads it. Never raises."""
    try:
        sid = (data or {}).get("session_id")
        if not sid:
            return
        home = Path.home()
        here = Path(os.environ.get("CLAUDE_CONFIG_DIR") or home / ".claude").expanduser().absolute()
        label = None
        sys.path.insert(0, str(Path(__file__).resolve().parent))
        import common
        reg = Path(os.environ.get("ACCOUNTS_FILE") or common.CONFIG / "lighthouse" / "accounts.json")
        for a in common.account_rows(json.loads(reg.read_text()).get("accounts"), home):
            if (a.get("provider") or "claude") == "claude" and common.account_home(a, home) == here:
                label = a.get("label")
                break
        if not label:
            return
        # The write goes to a detached child: data_dir() is the NAS share when it is mounted, and a
        # stale SMB mount blocks is_dir/open for tens of seconds — session start must never wait on
        # it (review 2026-10-06). The child loads usage-report for data_dir() and this_host().
        script = (
            "import json, sys, time\n"
            "from importlib.machinery import SourceFileLoader\n"
            "ur = SourceFileLoader('usage_report', sys.argv[1]).load_module()\n"
            "f = ur.data_dir() / ur.this_host() / 'accounts.jsonl'\n"
            "f.parent.mkdir(parents=True, exist_ok=True)\n"
            "with f.open('a') as fh:\n"
            "    fh.write(json.dumps({'session': sys.argv[2], 'account': sys.argv[3], 't': int(time.time())}) + '\\n')\n")
        ur = common.tool("usage-report")  # plumb's (G7): absent → no record, as any failure here
        if not ur:
            return
        ur_path = str(ur)
        p = subprocess.Popen([sys.executable, "-c", script, ur_path, sid, label], stdin=subprocess.DEVNULL,
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        if os.environ.get("SYNC_RECORD_WAIT"):  # tests read the file right after the hook
            p.wait(timeout=30)
    except Exception:
        pass


def tend_repo(repo, cwd):
    """sync() and the launched-worktree lock for one repo: (notes for the owner, notes for the model)."""
    u, m = sync(repo, cwd)
    try:
        u = u + indicator_notes(repo)
        spawn_indicator(repo)
    except Exception as exc:  # a lock icon is never worth a session start
        u = u + [f"⚠ {repo.name}: the launched-worktree lock failed: {exc}"]
    return u, m


def emit(for_user, for_model):
    """The SessionStart hook's JSON, or nothing when both lists are empty."""
    if for_user or for_model:
        out = {}
        if for_user:
            out["systemMessage"] = "⇣ " + " · ".join(for_user)
        if for_model:
            out["hookSpecificOutput"] = {"hookEventName": "SessionStart",
                                        "additionalContext": "⇣ " + " · ".join(for_model)}
        print(json.dumps(out, ensure_ascii=False))


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(json.dumps({"systemMessage": f"⚠ sync hook failed: {exc}"}))
    sys.exit(0)
