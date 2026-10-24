"""helm send (skipper-resilience S7; the build's send component): a task handed to its scope's
skipper by one verb. Three ways in — a blueprint file, a handoff branch, a `--text` task — and one
shape out: a pinned blueprint on a pushed claude/* branch, laid on the scope's yard by `wharf apply
--yard` over the yard's ssh alias, then a wait for the pickup, then a listener or nothing.

    helm send <blueprint.md> [--scope S] [--plan ID] [--listen | --detach] [--no-merge] [--every MIN] [--json]
    helm send <claude/branch> [--repo R] [--blueprint REL] [...]      a handoff branch: the blueprint it adds
    helm send --text "<task>" --repo R [--topic T] [--tier T] [--model M] [--effort E] [...]
    helm send --listen PLAN [BLOCK] [--every MIN] [--scope S]         the listener: one pull, then exit
    helm send --release [PLAN [BLOCK]]                                this session's listener(s) killed
    helm send --status [--json]                                       this session's sends
    helm send --mark PLAN --by WHO [--from HOST] [--block B] [--gen N]   the yard's half, over ssh

The two safe points. At `wharf apply --yard`'s exit 0 the ship is in the yard's store, `holder: yard`
(gen 0): the yard's tick drives its blocks whether or not a skipper is up — `LAID`, where --detach
returns. At the pickup the scope's skipper holds the lease: skipper.json says `skipper · <scope>`,
gen > 0, and a session whose registry pid lives on the yard (read over ssh from `helm skipper --status
--json`, every HELM_SEND_POLL s for HELM_SEND_WAIT s: 30 and 600) — `PICKED UP … this session may
close`, exit 0; none in the wait is `NOT PICKED UP`, exit 3 (NOT_PICKED), the task still safe on the yard.

What a sent blueprint says: `skipper: scope` (a relay goes to the lease holder, never to the sender,
who may be gone; a `skipper:` or `manager:` naming a session is rewritten, and the send says so) and
`sent_by: <session>`; a --text block also its tier, model and effort. A rewrite is one commit on the
branch by git plumbing (pickup brief's way: no checkout), pushed; the pin is read back from origin,
never from a working tree. On the yard, `--mark` gives each block's task `sent_by`, `sent_at` (the
task's send is `sent`) after the lease's fence (leaselib.fence(pid, "helm send")); the skipper's take
writes `picked_up_at` (leaselib.picked_up) — the tick starts a skipper for a ship with a task sent and
not picked up (skipperlib.needs).

Forced detach: with CLAUDE_CODE_DISABLE_BACKGROUND_TASKS or CLAUDE_UNATTENDED set (a dispatched run)
there is no background shell to listen in, so --listen is refused and --detach taken; the same two
make laid_by unattended, so the ship never merges by the sender's word (wharf's merge_value).

The listener (the design's road A): a pull, never a push — the yard cannot reach a laptop. Run as the
sender's background shell, it waits --every minutes (5), prints `helm skipper --line` from the yard,
and exits, which wakes the session; the session re-runs it until the line says `ended`. It also ends
when the session's claude does (HELM_LISTEN_PARENT, else the nearest `claude` above it), and on
--release, which kills it by its pid file, <send dir>/send-<plan>-<block>.pid. The send dir
(HELM_SEND_DIR, else ~/Library/Caches/helm) holds one record per send, send-<plan>.json: the yard,
its alias, the blocks, the state the sender last saw.

Nothing here calls a model. Tests: HARNESS_SSH replaces ssh, HARNESS_HOST names this Mac, a
HARNESS_PEER_<HOST> line an alias (bin/harness's), HELM_PICKUP the pickup tool. Stdlib only,
Python 3.9; a blueprint is read through wharf-runs' blueprintlib (PyYAML).
"""
import json
import os
import re
import shlex
import signal
import subprocess
import sys
import tempfile
import time
import uuid
from pathlib import Path

HERE = Path(__file__).resolve().parent
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))
import helmlib  # noqa: E402
import leaselib  # noqa: E402

POLL = 30            # seconds between two reads of the pickup
WAIT = 600           # the pickup wait: the tick starts the skipper within 5 minutes, its first turn takes the lease within 1
EVERY = 5.0          # the listener's minutes between pulls (the owner's five)
LAY_TIMEOUT = 1200   # wharf's own ceiling for a lay over ssh (WHARF_YARD_TIMEOUT)
NOT_PICKED = 3       # not picked up in the wait, the task safe on the yard: its own exit, never 1 (any crash or SystemExit)
NOT_LAID = 5         # a lay that left nothing on the yard: its own exit, never 3 (not picked up) nor 4 (the lease)
FORCED = ("CLAUDE_CODE_DISABLE_BACKGROUND_TASKS", "CLAUDE_UNATTENDED")
BLUEPRINT_DIR = "docs/blueprints"
ENDED_RE = re.compile(r"(^|: )ended: ")
TOPIC_RE = re.compile(r"^(?!.*-raw$)[a-z0-9][a-z0-9-]{2,39}$")   # bin/pickup's TOPIC_RE


class Refused(Exception):
    """A send that will not go; str() is the line after `helm send: refused: `, code the exit."""
    def __init__(self, msg, code=2):
        Exception.__init__(self, msg)
        self.code = code


def say(text, json_mode=False):
    print(text, file=sys.stderr if json_mode else sys.stdout, flush=True)


def _env_float(name, default):
    raw = os.environ.get(name)
    if not raw:
        return default
    try:
        return float(raw)
    except ValueError:
        raise Refused("%s=%r is no number of seconds" % (name, raw[:40]))


# ---------------------------------------------------------------------------- peers and hosts

def common():
    try:
        return helmlib._common()
    except ImportError:
        raise Refused("no regatta core here: no registry to read the scope from")


def blueprintlib():
    """wharf-runs' blueprintlib.py, through the core's tool(); Refused when it is not installed."""
    p = helmlib.peer("blueprintlib.py")
    if not p:
        raise Refused("wharf-runs' blueprintlib.py is not here: a blueprint cannot be read (install wharf-runs)")
    if str(p.parent) not in sys.path:
        sys.path.insert(0, str(p.parent))
    import blueprintlib as bl
    return bl


def machine():
    """This Mac's name as repos.json's yards spell it: bin/harness's machine() reading."""
    return os.environ.get("HARNESS_HOST") or helmlib.host()


def ssh_bin():
    return os.environ.get("HARNESS_SSH") or "ssh"


def alias_of(yard):
    """How this Mac reaches YARD over ssh: `wharf-runs/ssh`'s `<host>:<alias>` line (wharf's
    yard_alias), else HARNESS_PEER_<HOST>, else bin/harness's own peers; None when none names it."""
    try:
        lines = common().config_lines("wharf-runs/ssh") or []
    except Refused:
        lines = []
    for line in lines:
        host, _, alias = line.partition(":")
        if host.strip().lower() == yard.lower() and alias.strip():
            return alias.strip()
    env = os.environ.get("HARNESS_PEER_" + yard.upper().replace("-", "_"))
    if env:
        return env
    h = helmlib.peer("harness")
    if h:
        try:
            from importlib.machinery import SourceFileLoader
            mod = SourceFileLoader("harness_for_send", str(h)).load_module()
            return mod.peers().get(yard)
        except Exception:   # noqa: BLE001 — a harness that will not load names no alias
            return None
    return None


# The yard's side of every call, read by `sh -s -- <tool> <args>` there: the yard's own tool, found by
# the yard's own config — the core's module in the checkout the yard's `home` file names (as wharf's
# REMOTE_WHARF finds it; the overlay's shims went with B14b). ssh
# carries no environment, so nothing here is the caller's but the arguments.
REMOTE = r'''set -u
t=$1; shift
case $t in
  wharf) m=modules/wharf-runs/bin/wharf;;
  helm) m=modules/helm/libexec/helm;;
  *) echo "helm send: no remote tool $t" >&2; exit 2;;
esac
c=${REGATTA_CONFIG:-$HOME/.config/regatta}
w=
h=$(head -n 1 "$c/home" 2>/dev/null)
case $h in "~"*) h=$HOME${h#"~"};; esac
if [ -n "$h" ] && [ -x "$h/$m" ]; then w=$h/$m; fi
[ -n "$w" ] || { echo "no $t on $(hostname -s): no core's module ($c)" >&2; exit 2; }
PATH=/opt/homebrew/bin:$HOME/.local/bin:$PATH
export PATH
exec "$w" "$@" </dev/null
'''


def remote(alias, tool, args, timeout=120, capture=True, out=None):
    """(rc, stdout, stderr) of TOOL ARGS on the yard; rc None when ssh did not run or timed out."""
    argv = [ssh_bin(), "-o", "BatchMode=yes", "-o", "ConnectTimeout=10", alias,
            "sh -s -- " + " ".join(shlex.quote(str(x)) for x in [tool] + list(args))]
    try:
        if capture:
            r = subprocess.run(argv, input=REMOTE, capture_output=True, text=True, timeout=timeout)
            return r.returncode, r.stdout, r.stderr
        r = subprocess.run(argv, input=REMOTE, text=True, timeout=timeout, stdout=out)
        return r.returncode, "", ""
    except subprocess.TimeoutExpired:
        return None, "", "ssh %s: no answer in %ds" % (alias, timeout)
    except OSError as e:
        return None, "", "ssh %s: %s" % (alias, e)


# ---------------------------------------------------------------------------- who sends

def sender():
    """The sender's id as `sent_by` carries it: this session's, else a plain shell on this Mac."""
    return os.environ.get("CLAUDE_CODE_SESSION_ID") or "shell@%s" % machine()


def forced_detach():
    return next((n for n in FORCED if os.environ.get(n)), None)


def laid_by():
    """Who lays the ship, as wharf's laid_by_here reads it on the calling Mac — plus a session with no
    background tasks, which only a dispatched run is: unattended, so the ship never merges by its word."""
    raw = os.environ.get("DISPATCH_DEPTH") or "0"
    unattended = (bool(forced_detach()) or raw != "0" or any(os.environ.get(n) for n in helmlib.ENV_NAMES["ship"]))
    return {"mode": "unattended" if unattended else "attended", "depth": int(raw) if raw.isdigit() else 0,
            "session": os.environ.get("CLAUDE_CODE_SESSION_ID"), "host": machine(), "t": helmlib.now()}


# ---------------------------------------------------------------------------- the send dir

def send_dir():
    return Path(os.environ.get("HELM_SEND_DIR") or Path(os.environ.get("HOME") or Path.home()) / "Library/Caches/helm")


def record_path(pid):
    helmlib.plan_dir(pid)   # the id's own check: it names files here
    return send_dir() / ("send-%s.json" % pid)


def pid_path(pid, block=None):
    helmlib.plan_dir(pid)
    if block is not None and not re.match(r"^[A-Za-z0-9._-]+$", block):
        raise Refused("a block id is letters, digits, dot, dash and underscore: %r" % block)
    return send_dir() / ("send-%s-%s.pid" % (pid, block or "ship"))


def read_record(pid):
    try:
        rec = json.loads(record_path(pid).read_text())
    except (OSError, ValueError):
        return None
    return rec if isinstance(rec, dict) else None


def write_record(rec):
    p = record_path(rec["plan"])
    p.parent.mkdir(parents=True, exist_ok=True)
    tmp = p.with_name(".%s.%d" % (p.name, os.getpid()))
    tmp.write_text(json.dumps(rec, indent=1, sort_keys=True))
    tmp.replace(p)


def set_state(pid, state):
    rec = read_record(pid)
    if rec and rec.get("state") != state:
        rec["state"], rec["state_at"] = state, helmlib.now()
        write_record(rec)


def records():
    try:
        files = sorted(send_dir().glob("send-*.json"))
    except OSError:
        return []
    out = []
    for f in files:
        try:
            r = json.loads(f.read_text())
        except (OSError, ValueError):
            continue
        if isinstance(r, dict) and r.get("plan"):
            out.append(r)
    return out


# ---------------------------------------------------------------------------- git

def git(cwd, *argv, **kw):
    """(rc, stdout, stderr) of git in CWD; rc None when it did not run."""
    try:
        r = subprocess.run(["git", "-C", str(cwd)] + [str(x) for x in argv], capture_output=True, text=True,
                           timeout=kw.pop("timeout", 60), **kw)
    except (OSError, subprocess.TimeoutExpired) as e:
        return None, "", str(e)
    return r.returncode, r.stdout, r.stderr


def g(cwd, *argv, **kw):
    """git's stripped stdout, or Refused naming the failed command."""
    rc, out, err = git(cwd, *argv, **kw)
    if rc != 0:
        raise Refused("git %s in %s: %s" % (argv[0], cwd, (err or out).strip()[-200:] or "failed"))
    return out.strip()


def fetch_branch(root, branch):
    """origin's tip of BRANCH, fetched now (one branch, never everything); Refused when origin lacks it."""
    rc, _, err = git(root, "fetch", "-q", "origin", "+refs/heads/%s:refs/remotes/origin/%s" % (branch, branch), timeout=120)
    if rc != 0:
        if "couldn't find remote ref" in err:
            raise Refused("%s is not on origin: push it first — the yard reads origin/%s" % (branch, branch))
        raise Refused("could not fetch %s from origin: %s" % (branch, err.strip()[-200:] or "failed"))
    return g(root, "rev-parse", "refs/remotes/origin/%s" % branch)


def show(root, ref, rel):
    """The file's text at REF, unstripped, or None."""
    rc, out, _ = git(root, "show", "%s:%s" % (ref, rel))
    return out if rc == 0 else None


def main_checkout(path):
    """The main checkout of the repo PATH is in (a worktree's common dir's parent), or None."""
    rc, out, _ = git(path, "rev-parse", "--path-format=absolute", "--git-common-dir")
    if rc != 0 or not out.strip():
        return None
    common_dir = Path(out.strip())
    return common_dir.parent if common_dir.name == ".git" else common_dir


def worktree_of(root, branch):
    """The worktree that has BRANCH checked out, or None."""
    rc, out, _ = git(root, "worktree", "list", "--porcelain")
    cur = None
    for line in out.splitlines() if rc == 0 else []:
        if line.startswith("worktree "):
            cur = Path(line[len("worktree "):])
        elif line == "branch refs/heads/%s" % branch and cur:
            return cur
    return None


def _toplevel(path):
    rc, out, _ = git(path, "rev-parse", "--show-toplevel")
    return Path(out.strip()) if rc == 0 and out.strip() else None


def commit_on_branch(root, branch, rel, text, msg, mine=()):
    """TEXT committed as REL on BRANCH by plumbing (pickup brief's way: a blob, a tree, commit-tree),
    on origin's tip, pushed, then this Mac's branch moved to it — its worktree by `merge --ff-only`
    when that worktree is the caller's own or holds the file it named (MINE; its files move with the
    ref), a line naming the pull when another holds it, else the ref. Refused, nothing changed, when this Mac's branch
    has commits origin lacks or has diverged, the worktree has REL uncommitted, or the push is refused.
    The commit's sha."""
    base = g(root, "rev-parse", "refs/remotes/origin/%s" % branch)
    rc, local, _ = git(root, "rev-parse", "--verify", "--quiet", "refs/heads/%s" % branch)
    local = local.strip() if rc == 0 else ""
    if local and local != base:
        if git(root, "merge-base", "--is-ancestor", base, local)[0] == 0:
            raise Refused("%s has commits origin lacks (local %s, origin %s): push it first — the yard reads origin"
                          % (branch, local[:7], base[:7]))
        if git(root, "merge-base", "--is-ancestor", local, base)[0] != 0:
            raise Refused("%s has diverged from origin/%s (local %s, origin %s): settle it first"
                          % (branch, branch, local[:7], base[:7]))
    wt = worktree_of(root, branch)
    if wt:
        dirty = g(wt, "status", "--porcelain", "--", rel)
        if dirty:
            raise Refused("%s has %s uncommitted at %s: commit it first" % (branch, rel, wt))
    try:
        here = _toplevel(Path.cwd())
    except OSError:   # a cwd removed under the session: no worktree is its own
        here = None
    own = [p.resolve() for p in [here] + list(mine) if p]
    blob = g(root, "hash-object", "-w", "--stdin", input=text)
    with tempfile.TemporaryDirectory() as tmp:
        env = dict(os.environ, GIT_INDEX_FILE=str(Path(tmp) / "index"))
        g(root, "read-tree", base, env=env)
        g(root, "update-index", "--add", "--cacheinfo", "100644,%s,%s" % (blob, rel), env=env)
        tree = g(root, "write-tree", env=env)
    commit = g(root, "commit-tree", tree, "-p", base, "-F", "-", input=msg)
    # origin first: it is what the yard reads; this Mac's branch follows, and a move that fails is a
    # line, never a send undone (the commit is on origin already)
    rc, _, err = git(root, "push", "-q", "origin", "%s:refs/heads/%s" % (commit, branch), timeout=120)
    if rc != 0:
        raise Refused("the push of %s was refused (%s): nothing changed — origin may have moved: send it again"
                      % (branch, (err or "").strip()[-160:] or "failed"))
    note = None
    if wt and wt.resolve() not in own:
        # another session's worktree, maybe: one writer per worktree (rule: git-workflow), so a line, never a write
        note = "%s is checked out at %s, not here: `git -C %s pull --ff-only` there brings %s" % (branch, wt, wt, commit[:7])
    elif wt:
        rc, out, err = git(wt, "merge", "-q", "--ff-only", commit)
        if rc != 0:
            note = "%s at %s not moved to %s (%s): `git -C %s pull --ff-only`" % (branch, wt, commit[:7], (err or out).strip()[-120:], wt)
    elif local:
        rc, _, err = git(root, "update-ref", "refs/heads/%s" % branch, commit, local)
        if rc != 0:
            note = "this Mac's %s not moved to %s (%s)" % (branch, commit[:7], err.strip()[-120:])
    return commit, note


# ---------------------------------------------------------------------------- the blueprint

def front(text):
    """(front matter lines, the index of the closing `---`), or Refused."""
    lines = text.split("\n")
    if not lines or lines[0].rstrip() != "---":
        raise Refused("a blueprint starts with a `---` front matter")
    end = next((i for i in range(1, len(lines)) if lines[i].rstrip() == "---"), None)
    if end is None:
        raise Refused("the blueprint's front matter has no closing `---`")
    return lines, end


def _top(lines, end, key):
    rx = re.compile(r"^%s\s*:" % re.escape(key))
    return next((i for i in range(1, end) if rx.match(lines[i])), None)


def rewrite(text, sid, meta, block_keys=None):
    """(TEXT as sent, [lines saying what changed]): `skipper: scope` and `sent_by: <sid>` at the top
    level (a `manager:` is the same key's old word, and both is refused: it goes); with BLOCK_KEYS,
    a one-block blueprint's tier, model and effort, set right after its `provider:` line."""
    lines, end = front(text)
    notes = []
    old = meta.get("skipper") or meta.get("manager")
    if old not in (None, "scope"):
        notes.append("skipper: %s rewritten to scope — a sent ship's questions go to the scope's lease holder, "
                     "never to a session" % old)
    i = _top(lines, end, "manager")
    if i is not None:
        del lines[i]
        end -= 1
    want = {"skipper": "scope", "sent_by": json.dumps(sid)}
    for key in ("skipper", "sent_by"):
        i = _top(lines, end, key)
        line = "%s: %s" % (key, want[key])
        if i is not None:
            lines[i] = line
        else:
            at = _top(lines, end, "blocks")
            at = end if at is None else at
            lines.insert(at, line)
            end += 1
    if block_keys:
        prov = next((i for i in range(1, end) if re.match(r"^\s+provider\s*:", lines[i])), None)
        if prov is None:
            raise Refused("the blueprint's block names no provider: its tier, model and effort have no place")
        indent = re.match(r"^(\s+)", lines[prov]).group(1)
        for key in ("effort", "model", "tier"):   # inserted after provider:, so tier lands first
            value = block_keys.get(key)
            if not value:
                continue
            rx = re.compile(r"^%s%s\s*:" % (indent, key))
            j = next((k for k in range(1, end) if rx.match(lines[k])), None)
            if j is not None:
                lines[j] = "%s%s: %s" % (indent, key, value)
            else:
                lines.insert(prov + 1, "%s%s: %s" % (indent, key, value))
                end += 1
    return "\n".join(lines), notes


def load(bl, rel, text, key=None):
    try:
        return bl.load(Path(rel), text=text, key=key)
    except bl.BlueprintError as e:
        raise Refused("%s as the yard reads it: %s" % (rel, "; ".join(e.problems)))


def scope_of(bl, repo, want=None):
    """(registry key, scope, yard) of a blueprint's `repo:`, or Refused: a repo in no scope, a scope
    with no yard (every scope until sitting A names one — `scopes set <s> --yard HOST`), a torn registry."""
    c = common()
    if c.registry_unreadable():
        raise Refused("the registry %s does not read: no scope's yard can be told" % c.repos_json())
    key, scope, yard = bl.scope_yard_of(repo)
    if not scope:
        raise Refused("%s is in no scope (scopes check): a send goes to a scope's skipper" % (key or repo))
    if want and scope != want:
        raise Refused("%s is scope %s's, not %s's" % (key or repo, scope, want))
    if not yard:
        raise Refused("scope %s has no yard (scopes set %s --yard HOST names one)" % (scope, scope))
    return key, scope, yard


def destination(bl, repo, want=None):
    """(registry key, scope, yard, alias) a send of REPO goes to, or Refused — every check that needs
    nothing but this Mac's config and one ssh call, made before anything is seeded, committed or laid:
    the scope and its yard (scope_of), not this Mac, an alias here, and a yard whose helm has
    `helm send` (a yard that has not pulled S7 answers neither the mark, the pickup nor the line)."""
    key, scope, yard = scope_of(bl, repo, want)
    if yard == machine():
        raise Refused("this Mac is scope %s's yard: a send goes from another Mac (here, `wharf apply --yard <file>` "
                      "lays it)" % scope)
    alias = alias_of(yard)
    if not alias:
        raise Refused("scope %s's yard %s has no ssh alias here (wharf-runs/ssh: %s:<alias>)" % (scope, yard, yard))
    rc, out, err = remote(alias, "helm", ["send", "--status", "--json"], timeout=60)
    if rc in (None, 255):
        raise Refused("ssh %s: the yard %s does not answer (%s)" % (alias, yard, (err or "").strip()[-160:] or "exit %s" % rc), NOT_LAID)
    if rc == 2:   # argparse's "invalid choice": a helm from before S7
        raise Refused("the yard %s's helm has no `helm send` (exit %s: %s) — pull regatta there first"
                      % (yard, rc, (err or out).strip()[-160:] or "no output"), NOT_LAID)
    if rc != 0:   # a crash there (exit 1) says nothing of its version: could not tell
        raise Refused("the yard %s's `helm send --status` failed (exit %s: %s): it cannot be told the send is safe there"
                      % (yard, rc, (err or out).strip()[-160:] or "no output"), NOT_LAID)
    return key, scope, yard, alias


def topic_of(text):
    words = re.findall(r"[a-z0-9]+", text.lower())
    t = "-".join(words[:5])[:40].strip("-")
    return t if TOPIC_RE.match(t) else None


BRIEF = """# {topic} — sent with helm send from {host}, {date}
Task: {task}
Tier: {tier}
Why: sent by {sender} on {host} to skipper · {scope}, which holds the ship on its yard and hears its questions.
Start here: the task above; the repo's AGENTS.md (else CLAUDE.md).
Done means: the task done and committed on this branch, its check run and passing.
Not this: a landing — the ship's launch lands it.
"""


# ---------------------------------------------------------------------------- the three ways in

def resolve_repo(arg):
    """The main checkout a --repo names (a path, or a registry key under the projects folder)."""
    p = Path(arg).expanduser()
    if not p.is_dir():
        try:
            p = Path(common().PROJECTS) / arg
        except Refused:
            pass
    root = main_checkout(p) if p.is_dir() else None
    if not root:
        raise Refused("--repo %s is no git checkout" % arg)
    return root


def from_path(path):
    """(root, branch, rel) of a committed, pushed blueprint file; Refused otherwise (wharf's caller rules)."""
    f = Path(path).resolve()
    rc, top, _ = git(f.parent, "rev-parse", "--show-toplevel")
    top = top.strip() if rc == 0 else ""
    if not top:
        raise Refused("%s is in no git checkout: the yard reads a blueprint from origin" % f)
    branch = g(top, "rev-parse", "--abbrev-ref", "HEAD")
    if not branch or branch == "HEAD":
        raise Refused("%s is on no branch (a detached HEAD): the yard reads origin/<branch>" % top)
    rc, rel, _ = git(f.parent, "ls-files", "--full-name", "--", f.name)
    rel = rel.strip()
    if rc != 0 or not rel:
        raise Refused("%s is not committed: commit it, then push it — the yard reads origin/%s:<its path>" % (f, branch))
    claude_branch(branch)
    fetch_branch(top, branch)
    if show(top, "refs/remotes/origin/%s" % branch, rel) != f.read_text():
        raise Refused("push it first: the yard reads origin/%s:%s" % (branch, rel))
    return Path(top), branch, rel


def claude_branch(branch):
    if not branch.startswith("claude/"):
        raise Refused("%s is not a claude/* branch: a send commits onto its branch and pushes it, and only a "
                      "claude/* branch is a session's to push" % branch)


def default_base(root):
    for ref in ("refs/remotes/origin/main", "refs/remotes/origin/master"):
        if git(root, "rev-parse", "--verify", "--quiet", ref)[0] == 0:
            return ref
    rc, out, _ = git(root, "symbolic-ref", "-q", "refs/remotes/origin/HEAD")
    return out.strip() if rc == 0 and out.strip() else None


def from_branch(root, branch, blueprint=None):
    """(rel) of the one blueprint BRANCH adds or changes under docs/blueprints/ against origin's main
    (a branch holds every blueprint main has: only its own count), or BLUEPRINT; Refused when there
    is none or more than one."""
    claude_branch(branch)
    tip = fetch_branch(root, branch)
    if blueprint:
        if show(root, tip, blueprint) is None:
            raise Refused("origin/%s has no %s" % (branch, blueprint))
        return blueprint
    # origin's main as it is now (one ref): a stale tracking ref would count main's newer blueprints as the branch's
    git(root, "fetch", "-q", "origin", "+refs/heads/main:refs/remotes/origin/main", timeout=120)
    base = default_base(root)
    rc, mb, _ = git(root, "merge-base", base, tip) if base else (1, "", "")
    mb = mb.strip() if rc == 0 else None
    if mb:
        out = g(root, "diff", "--name-only", "--no-renames", "--diff-filter=AM", mb, tip, "--", BLUEPRINT_DIR + "/")
    else:
        out = g(root, "ls-tree", "-r", "--name-only", tip, "--", BLUEPRINT_DIR + "/")
    found = [x for x in out.splitlines() if x.endswith(".md")]
    if len(found) != 1:
        raise Refused("%s %s under %s/ — name the blueprint (--blueprint <path>)" % (
            branch, "adds no blueprint" if not found else "adds %d blueprints (%s)" % (len(found), ", ".join(found)), BLUEPRINT_DIR))
    return found[0]


def from_text(a, root, scope_want=None):
    """The --text way: the brief (six handoff lines) to a temp file, `pickup seed <topic> --file <it>
    --repo R --no-start`, which commits it and a one-block blueprint on a new claude/* branch and
    pushes; (branch, rel) from its lines. The scope and its yard are checked first: a send with nowhere
    to go seeds no branch."""
    bl = blueprintlib()
    key = bl.repo_key(str(root))
    scope = destination(bl, key or str(root), scope_want)[1]
    topic = a.topic or topic_of(a.text)
    if not topic or not TOPIC_RE.match(topic):
        raise Refused("no seed topic from the text: --topic, 3–40 characters of a-z, 0-9 and -")
    if a.tier and a.tier not in bl.TIERS:
        raise Refused("--tier is one of %s" % ", ".join(bl.TIERS))
    if a.effort and a.effort not in bl.EFFORTS:
        raise Refused("--effort is one of %s" % ", ".join(bl.EFFORTS))
    if a.model and not bl.MODEL_RE.match(a.model):
        raise Refused("--model %r is not a model name" % a.model)
    task = " ".join(a.text.split())
    pickup = os.environ.get("HELM_PICKUP") or helmlib.peer("pickup")
    if not pickup:
        raise Refused("wharf-runs' pickup is not here: --text cannot seed a branch (install wharf-runs)")
    brief = BRIEF.format(topic=topic, host=machine(), date=time.strftime("%Y-%m-%d"), task=task, tier=a.tier or "worker",
                         sender=sender(), scope=scope)
    with tempfile.NamedTemporaryFile("w", suffix=".md", prefix="helm-send-", delete=False) as fh:
        fh.write(brief)
        tmp = fh.name
    try:
        r = subprocess.run([sys.executable, str(pickup), "seed", topic, "--file", tmp, "--repo", str(root), "--no-start"],
                           capture_output=True, text=True, timeout=300)
    except (OSError, subprocess.TimeoutExpired) as e:
        raise Refused("pickup seed: %s" % e)
    finally:
        os.unlink(tmp)
    out = (r.stdout or "") + (r.stderr or "")
    m = re.search(r"^seeded (\S+) in \S+ — .*; (.*)$", out, re.M)
    if r.returncode != 0 or not m:
        raise Refused("pickup seed %s: %s" % (topic, out.strip()[-300:] or "exit %s" % r.returncode))
    branch, pushed = m.group(1), m.group(2)
    if not pushed.startswith("pushed"):
        raise Refused("pickup seeded %s but it is not on origin (%s): the yard reads origin" % (branch, pushed))
    b = re.search(r"and its one-block blueprint (\S+)", out)
    if not b:
        why = re.search(r"no blueprint beside the brief: (.*)", out)
        raise Refused("pickup seeded %s with no blueprint (%s): nothing to lay" % (branch, why.group(1) if why else "no line said why"))
    return branch, b.group(1), {"tier": a.tier or "worker", "model": a.model, "effort": a.effort}, m.group(0)


# ---------------------------------------------------------------------------- the send

def send(a):
    """The verb, on the sender's Mac. Exit: 0 picked up (or laid, detached), 3 not picked up in the
    wait (the task safe on the yard), 2 refused before anything was laid, 4 a lease's refusal, 5 not
    laid; 1 is only ever a crash (AGENTS.md: a probe's "refuse" exit must not be 1)."""
    js = a.json
    forced = forced_detach()
    detach = a.detach
    if forced:
        if a.listen:
            say("helm send: a dispatched run cannot listen (%s is set); sent with --detach" % forced, js)
        detach = True
    if a.listen and a.detach:
        raise Refused("--listen or --detach, not both")
    if a.plan:
        try:
            helmlib.plan_dir(a.plan)
        except ValueError as e:
            raise Refused("--plan: %s" % e)
    sid = sender()
    bl = blueprintlib()
    block_keys, seeded = None, None
    if a.text:
        if a.what:
            raise Refused("--text takes no blueprint or branch")
        if not a.repo:
            raise Refused("--text needs --repo R: the repo whose skipper takes it")
        root = resolve_repo(a.repo)
        branch, rel, block_keys, seeded = from_text(a, root, a.scope)
        say(seeded, js)
        fetch_branch(root, branch)
    else:
        if len(a.what) != 1:
            raise Refused("one blueprint file or one claude/* branch (or --text)")
        what = a.what[0]
        if Path(what).is_file():
            root, branch, rel = from_path(what)
        else:
            name = what[len("origin/"):] if what.startswith("origin/") else what
            if not name.startswith("claude/"):
                raise Refused("%s: no such file, and not a claude/* branch" % what)
            root = resolve_repo(a.repo) if a.repo else main_checkout(Path.cwd())
            if not root:
                raise Refused("%s: run it in the branch's repo, or name it with --repo" % name)
            branch, rel = name, from_branch(root, name, a.blueprint)
    tip = "refs/remotes/origin/%s" % branch
    text = show(root, tip, rel)
    if text is None:
        raise Refused("origin/%s:%s does not read" % (branch, rel))
    try:
        meta = bl.front_matter(text)[0]
    except bl.BlueprintError as e:
        raise Refused("%s is not a blueprint: %s" % (rel, "; ".join(e.problems)))
    if not isinstance(meta.get("repo"), str):
        raise Refused("%s names no repo in its front matter" % rel)
    key, scope, yard, alias = destination(bl, meta["repo"], a.scope)
    load(bl, rel, text, key)   # as it stands: a broken blueprint is refused before any rewrite
    sent, notes = rewrite(text, sid, meta, block_keys)
    for n in notes:
        say("helm send: %s" % n, js)
    if sent != text:
        bp = load(bl, rel, sent, key)
        msg = ("Send: %s to skipper · %s (helm send)\n\nThe blueprint as sent: skipper: scope, so its questions go to the "
               "scope's lease holder, and sent_by: %s.\n\nSent-By: %s on %s\nCo-Authored-By: Claude <noreply@anthropic.com>\n"
               % (bp["name"], scope, sid, sid[:8], machine()))
        mine = [_toplevel(Path(a.what[0]).resolve().parent)] if a.what and Path(a.what[0]).is_file() else []
        commit, note = commit_on_branch(root, branch, rel, sent, msg, mine)
        say("helm send: %s %s committed as sent (%s) and pushed" % (branch, rel, commit[:7]), js)
        if note:
            say("helm send: warning — %s" % note, js)
        fetch_branch(root, branch)
        text = show(root, tip, rel)
        if text != sent:
            raise Refused("origin/%s:%s reads otherwise than the send pushed: someone pushed meanwhile — send it again" % (branch, rel))
    bp = load(bl, rel, text, key)
    blocks = [s["id"] for s in bp["blocks"] if s.get("kind") != "decision"] or [s["id"] for s in bp["blocks"]]
    pin = {"repo": key, "branch": branch, "rel": rel, "digest": bl.digest(bp)}
    pid = a.plan or str(uuid.uuid4())
    helmlib.plan_dir(pid)
    laid = laid_by()
    gen = a.gen if a.gen is not None else ((os.environ.get("SKIPPER_GEN") or "").strip() or None)
    flags = (["apply", "--yard", "--pinned", json.dumps(pin, sort_keys=True), "--laid-by", json.dumps(laid, sort_keys=True),
              "--plan", pid] + (["--no-merge"] if a.no_merge else []) + (["--gen", str(gen)] if gen is not None else []))
    # a rejoined plan is there before the lay: its blocks are read now, so a failed lay is judged by what it added
    before = task_ids(remote(alias, "helm", ["state", pid], timeout=60)) if a.plan else set()
    say("helm send: %s %s:%s pinned at %s; laying it on %s (%s)" % (key, branch, rel, pin["digest"][:12], yard, alias), js)
    lay_timeout = a.lay_timeout if getattr(a, "lay_timeout", None) else _env_float("HELM_SEND_LAY_TIMEOUT", LAY_TIMEOUT)
    rc, _, err = remote(alias, "wharf", flags, timeout=int(lay_timeout), capture=False,
                        out=sys.stderr if js else None)
    lay_note = None
    if rc != 0:
        if err:
            say("helm send: %s" % err, js)
        # wharf's yard side saves the plan, the pin and the lease before its first apply, which can still
        # exit non-zero (Orca down, another apply running, no answer in time): the yard is asked whether
        # the ship is there, and a ship that is goes on as laid. ssh's 255 is asked too: a link that drops
        # after the yard saved the plan exits 255 as well. A rejoined plan (--plan) was there before this
        # lay, so its presence proves nothing: there only when this ship's blocks are new in it (S7's
        # landing reviews); a rejoin of the same ship whose lay failed is NOT LAID
        after = remote(alias, "helm", ["state", pid], timeout=60)
        there = after[0] == 0 and (not a.plan or bool((task_ids(after) - before) & set(blocks)))
        if not there:
            say("NOT LAID on %s: wharf apply --yard exit %s — %s; `--plan %s` rejoins it if it went through after all" % (
                yard, "none" if rc is None else rc,
                "ssh did not reach the yard, or lost it" if rc in (None, 255) else "the lay's own lines above say why",
                pid), js)
            return NOT_LAID
        lay_note = "its first apply exited %s" % ("none (no answer in time)" if rc is None else rc)
        say("helm send: plan %s is on %s although the lay's %s" % (pid, yard, lay_note), js)
    rec = {"plan": pid, "ship": bp["name"], "blocks": blocks, "scope": scope, "yard": yard, "alias": alias, "session": sid,
           "branch": branch, "rel": rel, "digest": pin["digest"], "repo": key, "sent_at": helmlib.now(), "state": "laid"}
    write_record(rec)
    # the sent ship's blocks only (a rejoined plan may hold another ship), and the sender's gen only on a
    # rejoin: a new plan's lease is the yard's gen 0, which the lay itself wrote
    mrc, mout, merr = remote(alias, "helm", timeout=60, args=["send", "--mark", pid, "--by", sid, "--from", machine()]
                             + [x for b in blocks for x in ("--block", b)]
                             + (["--gen", str(gen)] if gen is not None and a.plan else []))
    if mrc == leaselib.REFUSED_EXIT:
        say((merr or mout).strip() or "helm send --mark: refused by the lease", js)
        say("helm send: plan %s is LAID on %s and the tick drives it; only its sent mark was refused — do not send it "
            "again" % (pid, yard), js)
        return leaselib.REFUSED_EXIT
    if mrc != 0:
        say("helm send: warning — the yard did not mark it sent (%s): the tick still drives it, and starts a skipper "
            "for its open block" % ((merr or mout).strip()[-200:] or "exit %s" % mrc), js)
    where = "plan %s, %s" % (pid, "block %s" % blocks[0] if len(blocks) == 1 else "blocks %s" % ", ".join(blocks))
    if detach:
        return close(js, rec, "laid", "LAID on %s, %s — pickup by the tick%s" % (yard, where, " (%s)" % lay_note if lay_note else ""), 0)
    say("helm send: waiting for skipper · %s to pick it up (up to %d min; the tick starts it within 5)"
        % (scope, _env_float("HELM_SEND_WAIT", WAIT) // 60), js)
    who = wait_pickup(alias, pid, scope)
    if who:
        line = "PICKED UP by skipper · %s on %s, %s — this session may close" % (scope, yard, where)
        code = close(js, rec, "picked up", line, 0, session=who)
    else:
        line = "NOT PICKED UP in %d min — the yard holds it (gen 0); helm board on %s" % (_env_float("HELM_SEND_WAIT", WAIT) // 60, yard)
        code = close(js, rec, "not picked up", line, NOT_PICKED)
    if a.listen:
        say(listen_hint(pid, blocks, a.every), js)
    return code


def task_ids(got):
    """The task ids of `helm state`'s (rc, out, err) over ssh; none when it failed or does not parse."""
    rc, out, _ = got
    try:
        return {t["id"] for t in json.loads(out)["tasks"]} if rc == 0 else set()
    except (ValueError, KeyError, TypeError):
        return set()


def close(js, rec, state, line, code, **extra):
    set_state(rec["plan"], state)
    if js:
        print(json.dumps(dict({"state": state, "line": line, "plan": rec["plan"], "blocks": rec["blocks"], "scope": rec["scope"],
                               "yard": rec["yard"], "branch": rec["branch"], "rel": rec["rel"], "digest": rec["digest"]}, **extra),
                         sort_keys=True))
    else:
        print(line, flush=True)
    return code


def listen_hint(pid, blocks, every):
    import skipperlib
    helm = skipperlib.tool_cmd("helm")
    one = blocks[0] if len(blocks) == 1 else ""
    cmd = "%s send --listen %s%s%s" % (helm, pid, " " + one if one else "", "" if every == EVERY else " --every %g" % every)
    return ("listen: run `%s` as a background shell; in %g min it prints the task's line and exits — read it, say one "
            "sentence if it changed, and run it again unless the line says ended. `%s send --release` stops it."
            % (cmd, every, helm))


def picked(status, pid, scope):
    """The session holding PID for SCOPE's skipper, from the yard's `helm skipper --status --json`, or
    None: the third review's pickup — holder `skipper · <scope>`, gen > 0, the session alive there."""
    want = leaselib.holder_of(scope)
    for s in (status or {}).get("scopes") or []:
        for h in s.get("holders") or []:
            if h.get("holder") != want:
                continue
            for x in h.get("ships") or []:
                if x.get("plan") == pid and int(x.get("gen") or 0) > 0 and not x.get("lapsed") and x.get("session_alive"):
                    return x.get("session")
    return None


def wait_pickup(alias, pid, scope):
    poll, wait = _env_float("HELM_SEND_POLL", POLL), _env_float("HELM_SEND_WAIT", WAIT)
    end = time.time() + wait
    while True:
        rc, out, _ = remote(alias, "helm", ["skipper", "--status", "--json"], timeout=60)
        if rc == 0:
            try:
                who = picked(json.loads(out or "{}"), pid, scope)
            except ValueError:
                who = None
            if who:
                return who
        if time.time() + poll > end:
            return None
        time.sleep(poll)


# ---------------------------------------------------------------------------- the yard's half

def mark(a):
    """`helm send --mark PLAN --by WHO`, on the yard over ssh: each open block's task sent by WHO,
    after the lease's fence. A ship a skipper holds already (the tick was quicker than the mark) is
    marked picked up in the same line."""
    pid = a.mark
    if not a.by:
        raise Refused("--mark takes --by <the sender>")
    plan = helmlib.load_plan(pid)
    if plan is None:
        raise Refused("no ship %s here (%s)" % (pid, helmlib.plans_root()))
    # the fence, the lease's read and the marks under the plan's lock, which leaselib.take holds while
    # it takes and marks the pickup: a take comes before the mark or after it, never in between
    with helmlib.locked(pid):
        why = leaselib.fence(pid, "helm send", given=a.gen)
        if why:
            print(why, file=sys.stderr)
            return leaselib.REFUSED_EXIT
        try:
            lease = leaselib.read(pid)
        except leaselib.Unreadable:
            lease = None
        held = lease and lease["holder"] != leaselib.YARD and lease["gen"] > 0 and not leaselib.lapsed(pid, rec=lease)
        now = helmlib.now()
        tasks = [t for t in helmlib.state(pid)["tasks"] if t["status"] not in helmlib.ENDED and (not a.block or t["id"] in a.block)]
        if not tasks:
            # non-zero, never 1 nor 4: the sender's warning line, as a lay that saved the plan before its
            # tasks (another apply running) leaves nothing a later tick would mark
            print("ship %s: no open block to mark%s" % (pid, " named %s" % ", ".join(a.block) if a.block else ""), file=sys.stderr)
            return NOT_PICKED
        for t in tasks:
            ev = {"task": t["id"], "sent_by": a.by, "sent_at": now, "sent_from": a.from_host or None}
            if held:
                ev.update(picked_up_at=lease.get("since") or now, picked_up_by=lease["holder"], lease_gen=lease["gen"])
            helmlib.append_event(pid, ev)
    print("ship %s: %s sent by %s%s" % (pid, ", ".join(t["id"] for t in tasks), a.by[:8],
                                        ", picked up already by %s" % lease["holder"] if held else ""))
    return 0


# ---------------------------------------------------------------------------- the line (helm skipper --line)

def _pr(pr):
    m = re.search(r"(\d+)\D*$", str(pr or ""))
    return "#" + m.group(1) if m else None


def _alive(pid):
    try:
        os.kill(int(pid), 0)
    except (OSError, ValueError, TypeError):
        return False
    return True


def block_state(t, holder, at, pid=None):
    """One block's state in the line's fixed grammar (the design's A): the state, its worker, its open
    questions; or `ended: launched #N | failed: <why> | raised to <owner> (<class>)`."""
    import skipperlib
    st = t["status"]
    if st in helmlib.DONE:
        pr = _pr(t.get("pr"))
        return "ended: %s" % ("launched %s" % pr if pr else st)
    if st == "failed":
        return "ended: failed: %s" % (" ".join(str(t.get("progress") or "no reason given").split())[:200])
    if skipperlib.waits_on_owner(t, pid):
        try:
            owner = common().OWNER_NAME or "the owner"
        except Refused:
            owner = "the owner"
        # the class: a person's block, the decision doc it is gated on, else the questions the owner
        # holds (escalated, held by mode ask or dnd, answered in its doc: skipperlib.owners_ask)
        if t.get("kind") == "human":
            cls = "a person's block"
        elif str(t.get("progress") or "").startswith(skipperlib.OWNER_PROGRESS):
            cls = " ".join(str(t["progress"]).split())[:120]
        else:
            cls = "holds %s" % ", ".join(x["ref"] for x in t["asks"] if x.get("open"))[:120]
        return "ended: raised to %s (%s)" % (owner, cls)
    state = st + (", sent, not picked up" if t.get("send") == "sent" else "")
    sess = t.get("session")
    if not sess:
        worker = "worker not started"
    else:
        import asklib
        reg = asklib.registry(sess)
        if reg and _alive(reg.get("pid")):
            worker = "worker alive %d min" % max(0, (at - float(t.get("started") or t.get("updated") or at)) // 60)
        else:
            worker = "worker gone %d min" % max(0, (at - float(t.get("updated") or at)) // 60)
    k = sum(1 for x in t["asks"] if x.get("open"))
    asks = "%d question%s open%s" % (k, "" if k == 1 else "s", ", with %s" % holder if k else "")
    return "%s, %s; %s" % (state, worker, asks)


def line(pid, block=None):
    """([lines], ended): one line per block of PID (or BLOCK alone) — `<ship>/<block>: <state>; lease gen
    <g> held by <holder>` — and whether every one of them has ended."""
    plan = helmlib.load_plan(pid)
    if plan is None:
        raise Refused("no ship %s here" % pid, 1)
    st = helmlib.state(pid)
    tasks = [t for t in st["tasks"] if block is None or t["id"] == block]
    if block and not tasks:
        raise Refused("ship %s has no block %s (its blocks: %s)" % (pid, block, ", ".join(t["id"] for t in st["tasks"]) or "none"), 1)
    try:
        lease = leaselib.read(pid)
        lease_text = "lease gen %d held by %s" % (lease["gen"], lease["holder"]) if lease else "no lease"
        holder = lease["holder"] if lease else "the board"
    except leaselib.Unreadable:
        lease_text, holder = "the lease does not read", "nobody"
    at = helmlib.now()
    ship = plan.get("topic") or pid
    out, ended = [], bool(tasks)
    for t in tasks:
        s = block_state(t, holder, at, pid)
        if s.startswith("ended: "):
            out.append("%s/%s: %s" % (ship, t["id"], s))
        else:
            ended = False
            out.append("%s/%s: %s; %s" % (ship, t["id"], s, lease_text))
    if not tasks:
        out.append("%s: no block yet; %s" % (ship, lease_text))
    return out, ended


# ---------------------------------------------------------------------------- the listener

def listen(a, parent):
    """One pull: wait --every minutes while the session lives, print the yard's line, exit. A pid file
    names it for --release; the session re-runs it until the line says ended."""
    forced = forced_detach()
    if forced:
        raise Refused("a dispatched run cannot listen (%s is set): its sends go with --detach" % forced)
    if not a.what or len(a.what) > 2:
        raise Refused("--listen PLAN [BLOCK]")
    pid, block = a.what[0], (a.what[1] if len(a.what) > 1 else None)
    rec = read_record(pid) or {}
    alias = rec.get("alias")
    if not alias:
        if not a.scope:
            raise Refused("no send of %s recorded here (%s): name its scope with --scope" % (pid, record_path(pid)))
        c = common()
        yard = c.scope_yard(a.scope)
        alias = alias_of(yard) if yard else None
        if not alias:
            raise Refused("scope %s has no yard this Mac reaches (scopes set %s --yard HOST; wharf-runs/ssh)" % (a.scope, a.scope))
    if block is None and len(rec.get("blocks") or []) == 1:
        block = rec["blocks"][0]
    pf = pid_path(pid, block)
    other = read_pid(pf)
    if other and other[0] != os.getpid() and _alive(other[0]) and is_listener(other[0]):
        raise Refused("a listener for %s %s runs already (pid %d): `helm send --release %s %s` first"
                      % (pid, block or "", other[0], pid, block or ""))
    pf.parent.mkdir(parents=True, exist_ok=True)
    pf.write_text("%d\n%s\n" % (os.getpid(), os.environ.get("CLAUDE_CODE_SESSION_ID") or ""))
    try:
        end = time.time() + max(0.0, float(a.every)) * 60
        while time.time() < end:   # the parent is watched every second: the listener ends within one of it
            if not _alive(parent):
                print("helm send --listen: the session (pid %d) has ended — the listener with it" % parent, flush=True)
                return 0
            time.sleep(max(0.05, min(1.0, end - time.time())))
        rc, out, err = remote(alias, "helm", ["skipper", "--line", pid] + ([block] if block else []), timeout=60)
        text = (out or "").rstrip()
        if rc == 1 and re.search(r"--line: (no ship |ship \S+ has no block )", err or ""):   # permanent: a mistyped plan or block, another yard's
            if "--line: no ship " in err:
                set_state(pid, "ended")   # a missing block ends this listener, never the send's record
            print("%s%s: ended: %s — nothing more to pull" % (pid, "/" + block if block else "", err.strip()[-160:]), flush=True)
            return 0
        if rc != 0 or not text:
            print("%s%s: no line from %s (%s) — the next pull in %g min" % (
                pid, "/" + block if block else "", alias, (err or "").strip()[-160:] or "exit %s" % rc, a.every), flush=True)
            return 0
        print(text, flush=True)
        lines = text.splitlines()
        if lines and all(ENDED_RE.search(x) for x in lines):
            set_state(pid, "ended")
            print("listener: ended — nothing more to pull", flush=True)
        return 0
    finally:
        mine = read_pid(pf)
        if mine and mine[0] == os.getpid():
            try:
                pf.unlink()
            except OSError:
                pass


def read_pid(pf):
    try:
        lines = Path(pf).read_text().splitlines()
        return int(lines[0]), (lines[1] if len(lines) > 1 else "")
    except (OSError, ValueError, IndexError):
        return None


def is_listener(pid):
    """True when PID's command line is a `send --listen`: a pid file outlives its process, and a pid the
    OS has reused is someone else's to keep."""
    try:
        r = subprocess.run(["/bin/ps", "-o", "command=", "-p", str(int(pid))], capture_output=True, text=True, timeout=5)
    except (OSError, subprocess.TimeoutExpired, ValueError):
        return False
    return " send " in " %s " % r.stdout and "--listen" in r.stdout


def release(a):
    """Kill this session's listener(s) by their pid files: PLAN [BLOCK], else every one this session
    (a plain shell: every one) started."""
    me = os.environ.get("CLAUDE_CODE_SESSION_ID") or ""
    if a.what:
        if len(a.what) > 2:
            raise Refused("--release [PLAN [BLOCK]]")
        files = [pid_path(a.what[0], a.what[1] if len(a.what) > 1 else None)]
        if len(a.what) == 1:
            files = sorted(send_dir().glob("send-%s-*.pid" % a.what[0]))
    else:
        try:
            files = sorted(send_dir().glob("send-*.pid"))
        except OSError:
            files = []
    n = 0
    for pf in files:
        got = read_pid(pf)
        if not got:
            continue
        lp, sess = got
        if me and sess and sess != me and not a.what:
            continue   # another session's listener is its own to stop
        if _alive(lp) and is_listener(lp):
            try:
                os.kill(lp, signal.SIGTERM)
                print("released %s (pid %d)" % (pf.name[len("send-"):-len(".pid")], lp))
                n += 1
            except OSError as e:
                print("pid %d: %s" % (lp, e), file=sys.stderr)
                continue
        try:
            pf.unlink()
        except OSError:
            pass
    if not n:
        print("no listener of this session's to release")
    return 0


def status(a):
    """This session's sends (a plain shell: every one here): plan, block, state, listener pid."""
    me = os.environ.get("CLAUDE_CODE_SESSION_ID")
    rows = []
    for r in records():
        if me and r.get("session") != me:
            continue
        for b in r.get("blocks") or [None]:
            got = read_pid(pid_path(r["plan"], b)) or read_pid(pid_path(r["plan"], None))
            live = got[0] if got and _alive(got[0]) else None
            rows.append({"plan": r["plan"], "block": b, "ship": r.get("ship"), "scope": r.get("scope"), "yard": r.get("yard"),
                         "state": r.get("state"), "listener": live, "sent_at": r.get("sent_at")})
    if a.json:
        print(json.dumps(rows, sort_keys=True))
        return 0
    if not rows:
        print("no send of this session's here")
    for x in rows:
        print("%s  %s/%s  %s  on %s (skipper · %s)  listener %s" % (
            x["plan"], x["ship"], x["block"], x["state"], x["yard"], x["scope"], x["listener"] or "none"))
    return 0
