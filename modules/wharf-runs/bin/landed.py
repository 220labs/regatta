"""landed — has a claude/* branch landed on its repo's origin/<main>: the one reader dispatch-queue's claim
(an entry's `--after`) and helm's dependency check share (dispatch-queue S9, the owner's "add after-landed",
2026-10-28: a ship's next step waits until the previous one has landed, not until it is built).

    s = landed.sighting(repo, branch)         # at enqueue: {"branch", "seen", "work", "fork"} — its tip on origin now
    v, why, new = landed.judge(repo, branch, sightings=[{"sha", "fork"}...], seen=sha, fetch=True)

judge's verdict is one of `landed`, `waiting` (not landed, and it may yet), `gone` (its ref is off origin —
archived or deleted — and nothing proves it landed: it never will by itself) and `unknown` (could not tell: a
fetch failed, a git step failed, no origin). A reader holds on anything but `landed`. NEW is a sighting to keep
(the live tip, with its fork, while main lacks it), or None.

The repos land by rebase-merge only (wharf's `pr`, D9), so a landed tip is never an ancestor of main, and main
moves on over its files at the next landing (the S9 landing review: three landed queue steps read as waiting on
main's current files alone). A proof that held is kept in the repo's common git dir (`claude/after-landed.json`,
road 0, valid while the branch has done nothing past the proved head), so every reader on the Mac — helm's,
which never fetches — reads it. Three roads beside it, each one already the repo's own proof:
  1. content — every path the branch changed since its fork (deletions included) reads, mode and blob, as it
     did at some first-parent commit of origin/<main> after that fork (wharf's `branches.tree_entries`, over the
     commits that touched those paths, the newest MAX_COMMITS): the branch's work was on main at that commit;
     The brief under `docs/handoff/` is no path of the proof: /finish removes it, so no tip before /finish matches;
  2. `bin/pr merge`'s record — a `<branch> <sha> via #N` line in the common git dir's `launched` (or `landed`)
     file, which it writes for a branch the merged one carried, counted while every known tip is an ancestor of
     <sha> (with none known, every ref gone, the record stands alone, as road 3's PR does) and <sha> held work
     main lacked (its own proof takes "merged" and "no net change", which this refuses);
  3. GitHub's word — a PR from the branch into <main>, merged, none open, its head holding every known tip (the
     branch did nothing after it; the trap of a PR matched by branch name alone), or a known tip that is no
     descendant of the head and was committed before the merge (a copy from before /finish rewrote it). Asked
     when fetching, and by helm at most once per GH_RECHECK per branch, a failed ask included; a GitHub that does
     not answer is `unknown`, never `gone`.
A road-1 proof from one candidate is refused while the live or local tip descends from it with work beyond it
(the branch pushed again after landing: the successor would start without that work; the third review).
Every refusal of AGENTS.md's trap on vacuous landing proofs is kept: no road takes "no net change" (a branch with
no path changed since its fork proves nothing), or a tip that is an ancestor of main with no fork recorded before
it got there (a branch never written to, or reset onto main, reads the same as a merged one), or a gone ref by
itself, or a fork that is not on main (dispatch's `git branch … origin/<branch>` records a creation at the
branch's own work tip), or a tip with nothing of its own against the main it holds. A sighting's fork is read against main as ls-remote served it in the same call as the branch, so a branch
reset onto a newer main than an earlier fetch is never recorded as work. A git step that fails (a timeout, a
fork failure) is `unknown`, never a "no" another test then reads as proof.

The tips judged: origin's (live), the local branch, sync's `refs/archive/…` copies, and the sightings; roads
0, 2 and 3 hold every one of them that is here, and a proof by road 2 or 3 while a recorded sighting is not here
reads `unknown` (with every ref gone, a PR or a record matched by name alone proved work it never held; the third
review); with no proof, such a branch reads `gone` as before.
A git step that fails on one candidate skips that candidate, and the verdict is `unknown` only when no road
proves it. `fetch` False reads origin/<main> and origin/<branch> as the repo last fetched them and fetches no
PR head; with `github="cached"` (helm's state()) it may still ask GitHub's API, at most once per GH_RECHECK
per branch, which errs on the holding side. No core or no wharf: roads 1 and 2 by this
file's own git, road 3 not asked. Python 3.9, stdlib.
"""
import json
import os
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
GIT_TIMEOUT = 60
MAX_COMMITS = 300   # main's first-parent commits that touched the branch's paths, newest first, read for road 1
LS_CHUNK = 500
_HEADS = {}         # (repo, branch, fetch) -> (main's sha, tip or None) | Unknown
_MODS = {}


class Unknown(Exception):
    """A step that could not tell: the verdict is `unknown`, which holds."""


def _git(repo, *args, timeout=GIT_TIMEOUT):
    env = dict(os.environ, GIT_TERMINAL_PROMPT="0", LC_ALL="C", LANG="C")
    for k in [k for k in env if k.startswith("GIT_") and k not in ("GIT_TERMINAL_PROMPT", "GIT_SSH", "GIT_SSH_COMMAND",
                                                                       "GIT_CONFIG_GLOBAL", "GIT_CONFIG_SYSTEM")]:
        env.pop(k, None)   # a hook's GIT_DIR or GIT_INDEX_FILE would aim every step at the caller's repo
    if not env.get("GIT_SSH_COMMAND"):
        env["GIT_SSH_COMMAND"] = "ssh -o BatchMode=yes -o ConnectTimeout=15"
    try:
        return subprocess.run(["git", "-C", str(repo)] + list(args), capture_output=True, text=True, timeout=timeout, env=env)
    except subprocess.TimeoutExpired:
        return subprocess.CompletedProcess(args, 124, "", "timeout")
    except OSError as x:
        return subprocess.CompletedProcess(args, 125, "", str(x))


def _out(repo, *args):
    r = _git(repo, *args)
    return r.stdout.strip() if r.returncode == 0 else ""


def _must(repo, *args):
    """stdout of a git step that has to answer, else Unknown."""
    r = _git(repo, *args)
    if r.returncode != 0:
        raise Unknown("git %s failed (%s)" % (args[0], (r.stderr.strip().splitlines() or ["exit %d" % r.returncode])[-1][:120]))
    return r.stdout


def _exists(repo, sha):
    return bool(sha) and _git(repo, "cat-file", "-e", "%s^{commit}" % sha).returncode == 0


def _anc(repo, a, b):
    """True, False — or Unknown: `merge-base --is-ancestor` says 1 for no and anything else for a failure, which
    read as "no" handed a branch on main to a proof that then called it merged (the landing review)."""
    r = _git(repo, "merge-base", "--is-ancestor", a, b)
    if r.returncode in (0, 1):
        return r.returncode == 0
    raise Unknown("merge-base --is-ancestor failed (exit %d)" % r.returncode)


def _mod(name, path):
    if name not in _MODS:
        m = None
        try:
            if path:
                from importlib.machinery import SourceFileLoader  # noqa: PLC0415
                import importlib.util  # noqa: PLC0415
                ld = SourceFileLoader(name, str(path))
                m = importlib.util.module_from_spec(importlib.util.spec_from_loader(ld.name, ld))
                ld.exec_module(m)
        except Exception:   # a core it cannot find, a file mid-edit: that road's proof is not asked
            m = None
        _MODS[name] = m
    return _MODS[name]


def core():
    if "common" not in _MODS:
        try:
            sys.path.insert(0, str(HERE.parent / "lib"))
            import core_path  # noqa: PLC0415
            core_path.add()
            import common  # noqa: PLC0415
            _MODS["common"] = common
        except Exception:
            _MODS["common"] = None
    return _MODS["common"]


def branches_mod():
    """wharf's branches.py through the core's tool lookup (as wharf's runner loads it), or None."""
    c = core()
    return _mod("branches", c.tool("branches.py") if c else None)


def main_name(repo):
    """The repo's main: workflow.json's `main` in the repo's main checkout, else `main` (branches.main_branch)."""
    top = _out(repo, "rev-parse", "--path-format=absolute", "--git-common-dir")
    for root in [Path(repo)] + ([Path(top).parent] if top else []):
        try:
            return json.loads((root / ".claude" / "workflow.json").read_text()).get("main") or "main"
        except (OSError, ValueError, AttributeError):
            continue
    return "main"


def heads(repo, branch, fetch=True):
    """(main's sha, the branch's sha on origin or None), read together: with FETCH one ls-remote of both refs,
    their commits fetched where missing; without, the repo's refs/remotes/origin/*. Unknown when origin does
    not answer or there is none."""
    key = (str(repo), branch, fetch)
    if key in _HEADS:
        if isinstance(_HEADS[key], Unknown):
            raise _HEADS[key]
        return _HEADS[key]
    main = main_name(repo)
    try:
        if not _out(repo, "config", "--get", "remote.origin.url"):
            raise Unknown("no origin")
        if not fetch:
            m = _out(repo, "rev-parse", "--verify", "-q", "refs/remotes/origin/%s^{commit}" % main)
            if not m:
                raise Unknown("origin/%s is not here" % main)
            res = (m, _out(repo, "rev-parse", "--verify", "-q", "refs/remotes/origin/%s^{commit}" % branch) or None)
        else:
            r = _git(repo, "ls-remote", "origin", "refs/heads/%s" % main, "refs/heads/%s" % branch)
            if r.returncode != 0:
                raise Unknown("ls-remote origin failed (%s)" % ((r.stderr.strip().splitlines() or ["exit %d" % r.returncode])[-1][:120]))
            got = {ref: sha for sha, ref in (l.split("\t", 1) for l in r.stdout.splitlines() if "\t" in l)}
            m, tip = got.get("refs/heads/%s" % main), got.get("refs/heads/%s" % branch)
            if not m:
                raise Unknown("origin has no %s" % main)
            for sha, name in [(m, main)] + ([(tip, branch)] if tip else []):
                if not _exists(repo, sha):
                    f = _git(repo, "fetch", "-q", "origin", "+refs/heads/%s:refs/remotes/origin/%s" % (name, name))
                    if f.returncode != 0 or not _exists(repo, sha):
                        raise Unknown("could not fetch %s from origin" % name)
            res = (m, tip)
    except Unknown as x:
        _HEADS[key] = x
        raise
    _HEADS[key] = res
    return res


def sighting(repo, branch, fetch=True):
    """The predecessor as dispatch records it at enqueue: {"branch", "seen": its tip on origin or "", "work":
    whether main (read in the same ls-remote) lacked it, "fork": its merge-base with that main when work}. Work
    is a sighting judge() trusts later; an answer that could not tell records none."""
    out = {"branch": branch, "seen": "", "work": False, "fork": ""}
    try:
        m, tip = heads(repo, branch, fetch)
        if tip:
            out["seen"] = tip
            if not _anc(repo, tip, m):
                out.update(work=True, fork=_must(repo, "merge-base", tip, m).strip())
    except Unknown:
        pass
    return out


DROPPED = ("docs/handoff/",)   # /finish removes the brief (step 5): a path no landing ever brings to main
GH_RECHECK = 600               # a reader that asks GitHub through the proof file (helm) asks a branch once per this


def changed(repo, fork, tip):
    """The paths TIP changed since FORK (renames as delete + add), bar the ones /finish drops (DROPPED), or Unknown."""
    return [p for p in _must(repo, "diff", "--no-ext-diff", "--no-renames", "--name-only", "-z", fork, tip).split("\0")
            if p and not p.startswith(DROPPED)]


def entries(repo, treeish, paths):
    """{path: "mode sha"} of PATHS in TREEISH (absent paths absent), or Unknown."""
    bm = branches_mod()
    if bm:
        got = bm.tree_entries(repo, treeish, paths)
        if got is None:
            raise Unknown("ls-tree %s failed" % treeish[:10])
        return got
    out = {}
    for i in range(0, len(paths), LS_CHUNK):
        for item in _must(repo, "ls-tree", "-z", treeish, "--", *paths[i:i + LS_CHUNK]).split("\0"):
            if item:
                meta, _, path = item.partition("\t")
                mode, _, rest = meta.partition(" ")
                out[path] = "%s %s" % (mode, rest.split(" ")[-1])
    return out


def own_work(repo, sha, main):
    """SHA holds work main lacks: it is not on MAIN, and its diff from their merge-base (the main it already
    holds, a merged-in main included) changes a path /finish keeps. A branch that merged main and resolved every
    path to main's side, or checked main's copy of a file out, has none (the second landing review)."""
    if _anc(repo, sha, main):
        return False
    return bool(changed(repo, _must(repo, "merge-base", sha, main).strip(), sha))


def on_main_once(repo, tip, fork, main):
    """Road 1: the first-parent commit of MAIN, after FORK, at which every path TIP changed reads as at TIP —
    or None. Only commits that touched those paths are read (between them the paths do not change), newest
    first, MAX_COMMITS of them; a branch that changed nothing /finish keeps proves nothing."""
    paths = changed(repo, fork, tip)
    if not paths:
        return None
    want = entries(repo, tip, paths)
    revs = _must(repo, "rev-list", "--first-parent", "--max-count=%d" % MAX_COMMITS, "%s..%s" % (fork, main), "--", *paths).split()
    for c in revs:
        if entries(repo, c, paths) == want:
            return c
    return None


def launched_record(repo, branch, tips, main):
    """Road 2: bin/pr merge's line for BRANCH (written for a branch the merged one carried) whose commit every
    known tip is an ancestor of, and which itself held work main lacked (own_work against its merge-base: pr
    merge writes it once branches.prove holds, and prove's "merged" and "no net change" are the vacuous proofs
    this reader refuses — the second landing review). The line, or None."""
    bm = branches_mod()
    if not bm:
        return None
    for line in bm.launched_lines(repo):
        name, sha, via = bm.parse_launched(line)
        if name == branch and sha and _exists(repo, sha) and all(_anc(repo, t, sha) for t in tips) \
                and own_work(repo, sha, main):
            return "%s at %s" % (via or "bin/pr merge", sha[:7])
    return None


def _prs(repo, branch):
    """GitHub's pull requests whose head is BRANCH (head.ref checked), or Unknown when GitHub did not answer.
    LANDED_PRS names a JSON file {branch: [pr, ...]} standing in for GitHub (the tests); None: no GitHub here."""
    stub = os.environ.get("LANDED_PRS")
    if stub:
        try:
            return [p for p in (json.loads(Path(stub).read_text()).get(branch) or []) if isinstance(p, dict)]
        except (OSError, ValueError):
            raise Unknown("the LANDED_PRS stand-in does not read")
    c = core()
    if not c or os.environ.get("LANDED_NO_GH"):
        return None
    slug = c.repo_slug(_out(repo, "config", "--get", "remote.origin.url") or "")
    if not slug:
        return None
    from urllib.parse import quote  # noqa: PLC0415
    try:
        st, prs = c.api("GET", "/repos/%s/pulls?state=all&per_page=20&head=%s:%s" % (slug, slug.split("/")[0], quote(branch, safe="")))
    except Exception as x:   # any: GitHub's word could not be had
        raise Unknown("GitHub's pulls list failed (%s)" % type(x).__name__)
    if st != 200 or not isinstance(prs, list):
        raise Unknown("GitHub's pulls list gave %s" % (st or "no answer"))
    return [p for p in prs if isinstance(p, dict) and (p.get("head") or {}).get("ref") == branch]


def _before(repo, sha, when):
    """SHA was committed before WHEN (GitHub's ISO time): a copy of the branch from before /finish rewrote it
    (a stale local tip, the brief still in it), never work done after the PR merged."""
    import datetime  # noqa: PLC0415
    try:
        t = datetime.datetime.fromisoformat(str(when).replace("Z", "+00:00")).timestamp()
        return int(_must(repo, "log", "-1", "--format=%ct", sha).strip() or 0) < t
    except (ValueError, TypeError):
        return False


def held_by(repo, t, head, merged_at=None):
    """Tip T did nothing past HEAD: an ancestor of it, or (given MERGED_AT) a copy from before /finish rewrote
    the branch — no descendant of HEAD, committed before the merge."""
    if _anc(repo, t, head):
        return True
    return bool(merged_at) and not _anc(repo, head, t) and _before(repo, t, merged_at)


def merged_upstream(repo, branch, tips, main, fetch=True):
    """Road 3: GitHub's word — a PR from BRANCH into MAIN, merged, none from it open, and every known tip an
    ancestor of (or equal to) its head, or no descendant of it and committed before it merged (a copy from before
    /finish rewrote the branch; a descendant committed before the merge holds work the PR never had): the branch has done nothing since that PR landed (a name reused, or work committed after the merge,
    is no landing; the trap of a PR matched by branch name alone). Its head is fetched
    (the PR's own ref) when it is not here; with no tip known (every ref gone) the merged PR stands alone.
    (proof text, head, merged_at) or None; without FETCH a head not here is Unknown, never fetched; Unknown when GitHub did not answer (never `gone` for it)."""
    prs = _prs(repo, branch)
    if not prs or any(p.get("state") == "open" for p in prs):
        return None
    for pr in sorted(prs, key=lambda p: str(p.get("merged_at") or ""), reverse=True):
        head = (pr.get("head") or {}).get("sha") or ""
        if not pr.get("merged_at") or (pr.get("base") or {}).get("ref") != main or not head:
            continue
        if tips:
            if not _exists(repo, head) and fetch:
                _git(repo, "fetch", "-q", "origin", "refs/pull/%s/head" % pr.get("number"))
            if not _exists(repo, head):
                raise Unknown("PR #%s's head %s is not here" % (pr.get("number"), head[:7]))
            if not all(held_by(repo, t, head, pr.get("merged_at")) for t in tips):
                continue
        return "its PR #%s merged into %s at %s" % (pr.get("number"), main, head[:7]), head, pr.get("merged_at")
    return None


def proofs_file(repo):
    top = _out(repo, "rev-parse", "--path-format=absolute", "--git-common-dir")
    return Path(top or (Path(repo) / ".git")) / "claude" / "after-landed.json"


def proofs(repo):
    try:
        d = json.loads(proofs_file(repo).read_text())
        return d if isinstance(d, dict) else {}
    except (OSError, ValueError):
        return {}


def keep_proof(repo, branch, **fields):
    """BRANCH's line in the repo's proof file (its common git dir: every reader on this Mac, every worktree),
    merged with FIELDS, under a lock, through a temp name of this process's."""
    import fcntl  # noqa: PLC0415
    import time  # noqa: PLC0415
    p = proofs_file(repo)
    try:
        p.parent.mkdir(parents=True, exist_ok=True)
        with open(p.with_name(".after-landed.lock"), "w") as lk:
            fcntl.flock(lk, fcntl.LOCK_EX)
            d = proofs(repo)
            d[branch] = dict(d.get(branch) or {}, at=int(time.time()), **fields)
            tmp = p.with_name(".after-landed.%d.tmp" % os.getpid())
            tmp.write_text(json.dumps(d, sort_keys=True, indent=1))
            os.replace(tmp, p)
    except OSError:
        pass


def reflog_fork(repo, branch, tip, main):
    """The local branch's fork, from its reflog's creation entry (`branch: Created from …`), when that commit is
    on MAIN — dispatch's `git branch … origin/<branch>` records a creation at the branch's own work tip, and a
    fork there drops every earlier commit from the proof (the second landing review) — and TIP still holds a
    `commit` entry of that reflog (wharf's own_work rule); else None."""
    lines = [l.partition(" ") for l in (_out(repo, "reflog", "show", "--format=%H %gs", "refs/heads/%s" % branch) or "").splitlines()]
    if not lines or not lines[-1][2].startswith("branch: Created from"):
        return None
    fork = lines[-1][0]
    if not _anc(repo, fork, main):
        return None
    if not any(what.startswith("commit") and _anc(repo, sha, tip) for sha, _, what in lines):
        return None
    return fork


def _sha_of(s):
    return (s.get("sha") if isinstance(s, dict) else s) or ""


def judge(repo, branch, sightings=(), seen="", fetch=True, github=None):
    """(verdict, why, new_sighting) for BRANCH of REPO against origin/<main> (the module's header). SIGHTINGS:
    {"sha", "fork"} (or a bare sha) seen on the branch while main lacked it; SEEN: the tip recorded at enqueue
    whatever it was (it tells a branch deleted from origin from one never pushed). GITHUB: ask road 3 — always
    when FETCH (the default); "cached" asks it at most once per GH_RECHECK per branch, through the proof file
    (helm's state(), which never fetches)."""
    if not (Path(repo) / ".git").exists() and not _out(repo, "rev-parse", "--git-dir"):
        return "unknown", "no clone of the repo here", None
    import time  # noqa: PLC0415
    github = fetch if github is None else github
    main = main_name(repo)
    ref = "origin/%s" % main
    gh_unknown = None
    try:
        m, live = heads(repo, branch, fetch)
        local = _out(repo, "rev-parse", "--verify", "-q", "refs/heads/%s^{commit}" % branch) or None
        archived = [x for x in (_out(repo, "rev-parse", "--verify", "-q", "%s^{commit}" % r)
                                for r in ("refs/archive/%s" % branch, "refs/archive/origin/%s" % branch)) if x]
        tips = [t for t in (live, local) if t]
        # every tip known to this reader, for roads 0, 2 and 3: a sighting or SEEN recorded but not here leaves
        # them unable to say the branch did nothing since (the third review: with every ref gone, a PR matched
        # by name alone proved work it never held)
        recorded = [x for x in [_sha_of(s) for s in sightings] + [seen] if x]
        missing = [x for x in recorded if not _exists(repo, x)]
        known = list(dict.fromkeys(tips + archived + [x for x in recorded if x not in missing]))
        # road 0: a landing this Mac proved before (the proof file), while the branch has done nothing since
        pf = proofs(repo).get(branch) or {}
        head = pf.get("head") or ""
        if pf.get("landed") and head and _exists(repo, head) and not missing \
                and all(held_by(repo, t, head, pf.get("merged_at")) for t in known):
            return "landed", pf["landed"], None
        cands = [(t, None) for t in [live, local] + archived if t]   # (sha, the fork recorded with it or None)
        if local:
            cands.append((local, reflog_fork(repo, branch, local, m)))
        cands += [(_sha_of(s), (s.get("fork") if isinstance(s, dict) else None) or None) for s in sightings if _sha_of(s)]
        new = None
        if live and not _anc(repo, live, m):
            new = {"sha": live, "fork": _must(repo, "merge-base", live, m).strip()}
        tried, proof, cand_unknown = set(), None, None
        for sha, fork in cands:
            if not _exists(repo, sha):
                continue
            try:   # one candidate's failed git step (a pathspec too long, a timeout) never sinks the others
                on_main = _anc(repo, sha, m)
                if fork and not (_exists(repo, fork) and _anc(repo, fork, m) and _anc(repo, fork, sha)):
                    fork = None
                if not fork:
                    if on_main:
                        continue   # on main with no fork recorded before: never written to, or reset onto main
                    fork = _must(repo, "merge-base", sha, m).strip()
                if (sha, fork) in tried:
                    continue   # deduped on the resolved fork: (live, None) and its stored sighting are one scan
                tried.add((sha, fork))
                if not on_main and not own_work(repo, sha, m):
                    continue   # nothing of its own against the main it holds (main merged in and taken whole)
                at = on_main_once(repo, sha, fork, m)
                # a tip that descends from this candidate with work beyond it: the branch went on after the work
                # that landed, and a successor started now would lack it (the third review)
                if at and any(t != sha and _anc(repo, sha, t) and changed(repo, sha, t) for t in tips):
                    at = None
            except Unknown as x:
                cand_unknown = cand_unknown or str(x)
                continue
            if at:
                proof = ("every file it changed read so on %s at %s (its tip %s)" % (ref, at[:7], sha[:7]), sha, None)
                break
        def unseen(road):   # a road that would prove it, while a tip it was seen at is not here to hold against it
            return "%s would prove it, but a tip it was seen at (%s) is not here" % (road, missing[0][:7])
        if not proof:
            try:
                rec = launched_record(repo, branch, known, m)
            except Unknown as x:
                rec, cand_unknown = None, cand_unknown or str(x)
            if rec and missing:
                rec, cand_unknown = None, cand_unknown or unseen("bin/pr merge's record")
            if rec:
                proof = ("bin/pr merge recorded it: %s" % rec, tips[0] if tips else (archived[0] if archived else ""), None)
        if not proof and github:
            if github is True or time.time() - int(pf.get("gh_checked") or 0) >= GH_RECHECK:
                try:
                    proof = merged_upstream(repo, branch, known, main, fetch)
                    if proof and missing:
                        proof, gh_unknown = None, unseen("its merged PR")
                except Unknown as x:
                    gh_unknown = str(x)
                finally:
                    if github == "cached":   # a failed ask too: a GitHub that is down is not asked on every render
                        keep_proof(repo, branch, gh_checked=int(time.time()))
        if proof:
            keep_proof(repo, branch, landed=proof[0], head=proof[1] or (tips[0] if tips else ""), merged_at=proof[2])
            return "landed", proof[0], None
        if cand_unknown:
            return "unknown", cand_unknown, None
        if live and _anc(repo, live, m):
            return "unknown", ("its tip is on %s, but nothing shows a commit of its own — a branch never written to, "
                               "or one reset onto main, reads the same" % ref), None
        if live:
            return "waiting", "not on %s yet" % ref, new
        if gh_unknown:
            return "unknown", "its ref is off origin, and %s" % gh_unknown, None
        if archived:
            return "gone", "archived (refs/archive/…) and not proved on %s" % ref, None
        if local or seen or any(_sha_of(s) for s in sightings):
            return "gone", "deleted from origin and not proved on %s" % ref, None
        if not fetch:
            return "unknown", "not on origin as this Mac last fetched it, and nothing here proves it landed", None
        return "waiting", "not on origin yet", None
    except Unknown as x:
        return "unknown", str(x), None


def reset():
    """The per-process caches, cleared (a long-lived reader re-judging later; the tests)."""
    _HEADS.clear()


if __name__ == "__main__":
    # landed.py judge REPO BRANCH [--seen SHA] [--sighting SHA[:FORK]]... [--no-fetch]: one line, `<verdict> <why>`;
    # landed.py sighting REPO BRANCH: the JSON enqueue records; landed.py main REPO: the main's name;
    # exit 0 landed, 3 waiting or gone, 4 unknown (never 1: a crash exits 1, AGENTS.md's probe trap)
    a = sys.argv[1:]
    if len(a) == 2 and a[0] == "main":
        print(main_name(a[1]))
        sys.exit(0)
    if len(a) < 3 or a[0] not in ("judge", "sighting"):
        print("usage: landed.py judge|sighting REPO BRANCH [--seen SHA] [--sighting SHA[:FORK]]... [--no-fetch]", file=sys.stderr)
        sys.exit(2)
    verb, repo, br, rest = a[0], a[1], a[2], a[3:]
    fetch, seen, sights = "--no-fetch" not in rest, "", []
    for i, x in enumerate(rest):
        if x == "--seen" and i + 1 < len(rest):
            seen = rest[i + 1]
        if x == "--sighting" and i + 1 < len(rest):
            sha, _, fork = rest[i + 1].partition(":")
            sights.append({"sha": sha, "fork": fork})
    if verb == "sighting":
        print(json.dumps(sighting(repo, br, fetch)))
        sys.exit(0)
    v, why, _ = judge(repo, br, sights, seen, fetch)
    print("%s %s" % (v, why))
    sys.exit({"landed": 0, "waiting": 3, "gone": 3}.get(v, 4))
