"""The blueprint: the committed Markdown file that says how to build one ship, its graph in the
front matter and each block's brief in a `## <id>` section (docs/orchestration-orca-2026-10-15.md section 4, Q1 and Q2;
build step B6). `wharf check` validates and prints it; `wharf apply --dry-run` diffs it against Orca
and the plan; B7's live `wharf apply` compiles it into one Orca Run (a Task per block, a gate per
decision) with what this module computes: the order, the spec each Task carries, the digest.

    docs/blueprints/<yyyy-mm-dd>-<topic>.md

    ---
    ship: <topic>                        the ship it builds; the file's name ends in it
    repo: shop                           a name under ~/projects, or an absolute path
    skipper: regatta                     optional: the session that laid the keel and coordinates
                                         the ship (wharf-on-orca D3-A); `manager:` is read the same;
                                         `scope`: the scope's lease holder (S4), never the sender
    sent_by: <session id>                optional: who sent it (`helm send`), not its skipper
    merge: yes                           optional, yes (the default) or no: whether its launch
                                         merges; the keel's effective value is plan.json's (wharf
                                         apply --yard: no for --no-merge or an unattended layer)
    created: 2026-10-15
    mode: dnd                            optional: default | ask | dnd | yolo — the ship's mode
                                         (skipper-modes S1), written to plan.json by its first apply;
                                         `helm mode` rewrites it there, and plan.json is what is read
    blocks:
      - id: b6a-probes                   [a-z0-9][a-z0-9-]*, unique
        depends_on: []                   ids of earlier blocks
        provider: orca                   orca | claude-code | shell
        agent: claude                    orca: claude | codex
        host: here                       here, or a host the repo lists in repos.json (a build Mac, a VM):
                                         an Orca block starts there with worker-start --on <host>,
                                         the Orca environment paired under that name (wharf-on-orca S3);
                                         where the repo's scope has a yard, a host some scope's yard
                                         is (the yard has no launcher on any other);
                                         `auto` (a claude-code block's): dispatch places it by berth
                                         (skipper-modes S6b: the scope's berths, slots, load)
        tier: worker                     worker | sr-worker | architect | sr-architect | main
        model: sonnet                    passed through to Orca or dispatch
        effort: high                     low … max; on an Orca block only with a model (Orca's rule)
        physical: none
        done_when: {marker: "docs/x.md#B6a"}   one of marker, pr_merged, check, memo_answered, file
        timeout_seconds: 7200
        retries: 2                       0–2: B3's two; Orca's own breaker fires at three (R4)
      - id: d-runtime
        kind: decision                   a memo doc's items, compiled to one gated Task
        doc: docs/orchestration-orca-2026-10-15.md
        items: [D2, D3, D4]
        depends_on: [b6a-probes]
      - id: launch-b6
        depends_on: [b6a-probes]
        provider: shell
        command: "bin/autofinish-run <wt> --by chain"
        launch: autofinish               autofinish | finish
    ---
    ## b6a-probes
    Task: …  Tier: …  Why: …  Start here: …  Done means: …  Not this: …   (the handoff shape)

The front matter is YAML, read by PyYAML's safe loader (the repo's already: bin/skill-frontmatter,
CI) made strict: a key twice is refused, a date stays text, a YAML error names its line. Every `## ` heading in the body names a block (use `###` inside a brief);
an orca or claude-code block must have one, with the six handoff lines.

The digest (Q1, Bernstein's P3 behaviour): sha256 over the front matter as sorted JSON plus the
preamble and each section's text, whitespace at line ends ignored. `wharf check --accept` records
it in plan.json (state.json is the page's cache, rewritten by every render, so plan.json is where
it lasts); a later apply against a different digest is refused with the blocks that changed. A
block's own digest names which. Python 3.9; PyYAML, as above.
"""
import hashlib
import json
import os
import re
from pathlib import Path

ID_RE = re.compile(r"^[a-z0-9][a-z0-9-]*$")
SEED_TOPIC_RE = re.compile(r"^(?!.*-raw$)[a-z0-9][a-z0-9-]{2,39}$")   # bin/pickup's TOPIC_RE
DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
ITEM_RE = re.compile(r"^D\d+$")   # bin/memo's parse finds D-items only: a Q2 could never resolve
MODEL_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._\[\]-]*$")

PROVIDERS = ("orca", "claude-code", "shell")
AGENTS = ("claude", "codex")
HOST_RE = re.compile(r"^[a-z0-9][a-z0-9-]*$")


def repos_json():
    """The registry, through the core's one reader (C3), or None: the caller (bin/wharf, helm) has
    put the core on the path; a file loaded without it reads no registry."""
    try:
        import common
    except ImportError:
        return None
    return common.repos_json()


def repo_key(repo):
    """The registry key a blueprint's `repo:` names: the name itself, or an absolute path's place
    under the projects folder (common.PROJECTS, where every registry key is a folder); None for a path
    outside it or with no core."""
    if not repo.startswith("/"):
        return repo
    try:
        import common
        return Path(os.path.realpath(repo)).relative_to(os.path.realpath(str(common.PROJECTS))).as_posix()
    except (ImportError, ValueError):
        return None


def scope_yard_of(repo):
    """(key, scope, yard) of a blueprint's repo, through the core's registry reader: its registry
    key, the scope that holds it (or None) and that scope's yard (common.scope_yard: None for absent
    or null). (None, None, None) with no core."""
    try:
        import common
    except ImportError:
        return None, None, None
    key = repo_key(repo)
    scope = common.scope_of_key(key) if key else None
    return key, scope, common.scope_yard(scope) if scope else None


TIERS = ("worker", "sr-worker", "architect", "sr-architect", "main")
EFFORTS = ("low", "medium", "high", "xhigh", "max")
DONE_WHEN = ("marker", "pr_merged", "check", "memo_answered", "file")
LAUNCH = ("autofinish", "finish")
MAX_RETRIES = 2
DEEP = 4   # Orca's guide: "prefer parallel waves over chains deeper than three or four steps" (F2)
# The handoff shape (docs/handoff/*.md): a brief Orca or dispatch is handed whole
BRIEF_LINES = ("Task", "Tier", "Why", "Start here", "Done means", "Not this")
BRIEF_RE = re.compile(r"^\s*(?:[-*]\s+)?(?:\*\*)?(%s)(?:\*\*)?:" % "|".join(BRIEF_LINES), re.M)

TOP_KEYS = {"ship", "repo", "skipper", "manager", "created", "mode", "blocks", "merge", "sent_by"}
MERGE = {True: "yes", False: "no", "yes": "yes", "no": "no"}   # YAML 1.1 reads a bare yes/no as a bool
MODES = ("default", "ask", "dnd", "yolo")   # helmlib.MODES: the same four words (skipper-modes S1)
COMMON = {"id", "kind", "depends_on", "title"}
WORK = COMMON | {"provider", "agent", "host", "tier", "model", "effort", "physical", "done_when",
                 "timeout_seconds", "retries", "account", "yolo", "command", "launch", "branch", "owns", "live"}
DECISION = COMMON | {"doc", "items", "options"}
# What each provider refuses outright (the rest of WORK is open to every provider)
# (Yolo is --dangerously-skip-permissions: stays off on Orca, Q3. An Orca worker's login is the
# account registry's pick, `account: auto` (docs/orca-accounts-2026-10-16.md), never the block's: a
# block that needs a named login is provider: claude-code with account. A shell block runs here: its
# start text has no route to another host.)
NOT_FOR = {"orca": {"command", "yolo", "account"},
           "claude-code": {"command", "yolo"},   # pickup seed takes no --yolo yet: refused, not dropped
           "shell": {"agent", "model", "effort", "tier", "account", "yolo", "host", "retries"}}   # a shell block runs once (wharf's ledger)


class BlueprintError(ValueError):
    """Every problem found, each one line, most with a line number."""

    def __init__(self, problems):
        self.problems = list(problems)
        super().__init__("; ".join(self.problems))


# ---------------------------------------------------------------------------- the front matter

def _yaml():
    """PyYAML's safe loader, made strict: a key twice is refused (PyYAML keeps the last silently),
    and a date stays the text it was written as. PyYAML is the repo's already: bin/skill-frontmatter
    reads skills with it, bootstrap.sh --check fails a Mac without it, CI pins it."""
    try:
        import yaml
    except ImportError:
        raise BlueprintError(["PyYAML is not installed for this python3 (bin/skill-frontmatter needs it too: pip install pyyaml)"])

    class Strict(yaml.SafeLoader):
        pass

    def mapping(loader, node, deep=False):
        seen = set()
        for k, _ in node.value:
            key = loader.construct_object(k, deep=deep)
            if isinstance(key, (list, dict)):
                raise yaml.constructor.ConstructorError(None, None, "a key that is a list or map", k.start_mark)
            if key in seen:
                raise yaml.constructor.ConstructorError(None, None, "key %s twice" % key, k.start_mark)
            seen.add(key)
        return loader.construct_mapping(node, deep)

    Strict.add_constructor(yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, mapping)
    Strict.add_constructor("tag:yaml.org,2002:timestamp", lambda loader, node: loader.construct_scalar(node))
    return yaml, Strict


def front_matter(text):
    """(the front matter as a dict, the body, the body's first line number)."""
    if not text.startswith("---\n"):
        raise BlueprintError(["line 1: a blueprint starts with a `---` front matter"])
    lines = text.split("\n")
    end = next((i for i in range(1, len(lines)) if lines[i].rstrip() == "---"), None)
    if end is None:
        raise BlueprintError(["line 1: the front matter has no closing `---`"])
    yaml, Strict = _yaml()
    try:
        meta = yaml.load("\n".join(lines[1:end]), Loader=Strict)
    except yaml.YAMLError as e:
        mark = getattr(e, "problem_mark", None)
        why = getattr(e, "problem", None) or str(e)
        raise BlueprintError(["%s%s" % ("line %d: " % (mark.line + 2) if mark else "", why)])   # the front matter starts on line 2
    if not isinstance(meta, dict):
        raise BlueprintError(["line 2: the front matter is a map of keys"])
    return meta, "\n".join(lines[end + 1:]), end + 2


# ---------------------------------------------------------------------------- sections

def _norm(text):
    return "\n".join(x.rstrip() for x in text.strip("\n").split("\n")).strip("\n")


def sections(body, first):
    """(preamble, {id: (line, text)}, problems): every `## ` heading outside a fence names a block."""
    pre, secs, problems = [], {}, []
    cur, fence = None, None
    for i, line in enumerate(body.split("\n")):
        n = first + i
        st = line.lstrip()
        if st.startswith(("```", "~~~")):
            mark = st[:3]
            fence = None if fence == mark else (fence or mark)
        if fence is None and line.startswith("## "):
            sid = line[3:].strip()
            if not ID_RE.match(sid):
                problems.append("line %d: `## %s` — every `## ` heading names a block (use ### inside a brief)" % (n, sid))
                sid = "?%d" % n
            elif sid in secs:
                problems.append("line %d: a second `## %s`" % (n, sid))
            cur = sid
            secs[cur] = (n, [])
            continue
        (secs[cur][1] if cur else pre).append(line)
    return _norm("\n".join(pre)), {k: (n, _norm("\n".join(v))) for k, (n, v) in secs.items()}, problems


# ---------------------------------------------------------------------------- the schema

def _str_list(v):
    return isinstance(v, list) and all(isinstance(x, str) and x for x in v)


def hosts_of(repo):
    """The hosts a block of REPO may name besides `here`: the repo's `hosts` in repos.json, every
    host repos.json names for a repo it does not list (an absolute path), None when repos.json can't
    be read (then any host-shaped name passes and the start finds out). No host literal here: a Linux
    VM joins by its name in repos.json and an Orca environment paired under it (rules: Hosts,
    2026-10-17; docs/linux-vm-hosts-2026-10-17.md, the host model)."""
    try:
        repos = json.loads((repos_json() or Path("/nonexistent/repos.json")).read_text()).get("repos") or {}
    except (OSError, ValueError):
        return None
    if isinstance(repos.get(repo), dict):
        return set(repos[repo].get("hosts") or [])
    return {h for r in repos.values() if isinstance(r, dict) for h in r.get("hosts") or []}


def _yards():
    try:
        import common
    except ImportError:
        return {}
    return common.scope_yards()


def merge_of(meta):
    """The blueprint's own `merge:` as "yes" or "no", or None when it says nothing (the default, yes)."""
    return MERGE.get(meta.get("merge")) if "merge" in meta else None


def _check_block(s, i, problems, hosts=None, yards=None, yard_problems=None):
    where = "block %d" % (i + 1)
    if not isinstance(s, dict):
        problems.append("%s: a block is a map of keys" % where)
        return None
    sid = s.get("id")
    if not isinstance(sid, str) or not ID_RE.match(sid):
        problems.append("%s: id %r is not [a-z0-9][a-z0-9-]*" % (where, sid))
        sid = None
    else:
        where = "block %s" % sid
    kind = s.get("kind", "block")
    deps = s.get("depends_on", [])
    if deps is None:
        deps = []
    if not _str_list(deps) and deps != []:
        problems.append("%s: depends_on is a list of block ids" % where)
        deps = []
    if kind == "decision":
        for k in sorted(set(s) - DECISION):
            problems.append("%s: %s is not a key of a decision block (%s)" % (where, k, ", ".join(sorted(DECISION))))
        if not isinstance(s.get("doc"), str) or not s["doc"].endswith(".md"):
            problems.append("%s: doc names the memo doc (a .md path in the repo)" % where)
        items = s.get("items")
        if not _str_list(items) or not items or not all(ITEM_RE.match(x) for x in items):
            problems.append("%s: items is a list like [D2, D3]" % where)
        if "options" in s and not _str_list(s["options"]):
            problems.append("%s: options is a list like [A, B, C]" % where)
        if "title" in s and not (isinstance(s["title"], str) and s["title"].strip()):
            problems.append("%s: title is a non-empty string" % where)
    elif kind == "block":
        for k in sorted(set(s) - WORK):
            problems.append("%s: %s is not a key of a block" % (where, k))
        p = s.get("provider")
        if p not in PROVIDERS:
            problems.append("%s: provider is one of %s" % (where, ", ".join(PROVIDERS)))
        else:
            for k in sorted(NOT_FOR[p] & set(s)):
                problems.append("%s: %s is not for %s blocks" % (where, k, p))
        if p == "orca":
            if s.get("agent") not in AGENTS:
                problems.append("%s: an orca block names its agent: %s" % (where, " or ".join(AGENTS)))
            if "effort" in s and "model" not in s:
                problems.append("%s: effort needs a model on an Orca block (Orca's rule)" % where)
        if p == "claude-code" and s.get("agent", "claude") != "claude":
            problems.append("%s: a claude-code block's agent is claude" % where)
        if p == "shell" and not (isinstance(s.get("command"), str) and s["command"].strip()):
            problems.append("%s: a shell block has a command" % where)
        h = s.get("host", "here")
        if h == "auto" and s.get("provider") != "claude-code":
            problems.append("%s: host auto is a claude-code block's (dispatch places it by berth); an Orca block names its host" % where)
        elif h not in ("here", "auto") and not (isinstance(h, str) and HOST_RE.match(h) and (hosts is None or h in hosts)):
            problems.append("%s: host is here or one of the repo's hosts in repos.json (%s)"
                            % (where, ", ".join(sorted(hosts)) if hosts is not None else "unreadable"))
        elif h not in ("here", "auto") and yards is not None and h not in yards:
            # the yard's tick starts a block on its own host or on another yard's Orca, nowhere else
            # (skipper-resilience S2: a laptop-side pass for such a block is a later step's); `auto` is
            # berth's at the start, which from the yard picks only a host it reaches (skipper-modes S6b)
            (problems if yard_problems is None else yard_problems).append(
                "%s: host: %s has no launcher from the yard; run that step by hand or as a pickup" % (where, h))
        local = set(s.get("done_when") or {}) & {"file", "marker", "check"} if isinstance(s.get("done_when"), dict) else set()
        if h != "here" and local:
            # wharf reads these in the block's worktree on this Mac; a remote block's is on its host
            problems.append("%s: done_when's %s reads a worktree here; a block on %s ends by pr_merged or memo_answered"
                            % (where, "/".join(sorted(local)), h))
        for k, allowed in (("tier", TIERS), ("effort", EFFORTS), ("launch", LAUNCH)):
            if k in s and s[k] not in allowed:
                problems.append("%s: %s is one of %s" % (where, k, ", ".join(allowed)))
        if "model" in s and not (isinstance(s["model"], str) and MODEL_RE.match(s["model"])):
            problems.append("%s: model %r is not a model name" % (where, s["model"]))
        for k in ("physical", "account", "branch", "title"):
            if k in s and not (isinstance(s[k], str) and s[k].strip()):
                problems.append("%s: %s is a non-empty string" % (where, k))
        if "branch" in s and isinstance(s["branch"], str) and not re.match(r"^claude/[a-z0-9-]+/\d{4}-\d{2}-\d{2}-[A-Za-z0-9._-]+$", s["branch"]):
            problems.append("%s: branch %r is not claude/<host>/<yyyy-mm-dd>-<topic>" % (where, s["branch"]))
        if "yolo" in s and not isinstance(s["yolo"], bool):
            problems.append("%s: yolo is true or false" % where)
        if "retries" in s and not (isinstance(s["retries"], int) and not isinstance(s["retries"], bool)
                                   and 0 <= s["retries"] <= MAX_RETRIES):
            problems.append("%s: retries is 0 to %d (B3's two; Orca's breaker fires at three)" % (where, MAX_RETRIES))
        if "timeout_seconds" in s and not (isinstance(s["timeout_seconds"], int) and not isinstance(s["timeout_seconds"], bool)
                                           and s["timeout_seconds"] > 0):
            problems.append("%s: timeout_seconds is a positive whole number" % where)
        dw = s.get("done_when")
        if dw is not None:
            if not (isinstance(dw, dict) and len(dw) == 1 and next(iter(dw)) in DONE_WHEN):
                problems.append("%s: done_when is one of {%s: …}" % (where, ": …} {".join(DONE_WHEN)))
            else:
                (k, v), = dw.items()
                if not (isinstance(v, str) and v.strip()) and not (k == "pr_merged" and v is True):
                    problems.append("%s: done_when's %s needs a value" % (where, k))
                elif k == "marker" and "#" not in v:
                    problems.append("%s: done_when's marker is <doc>#<item>" % where)
                elif k == "pr_merged" and p == "shell" and not s.get("branch"):
                    problems.append("%s: done_when's pr_merged on a shell block needs its branch:" % where)
            if p == "claude-code":
                # a seeded session ends by its own `helm report --status done`; Orca never completes its Task
                problems.append("%s: a claude-code block ends by its own launch, not a done_when" % where)
        if p == "claude-code" and sid and not SEED_TOPIC_RE.match(sid):
            problems.append("%s: a claude-code block's id is its seed topic: 3–40 of a-z, 0-9 and -, not -raw (bin/pickup)" % where)
        for k in ("owns", "live"):
            if k in s and not _str_list(s[k]):
                problems.append("%s: %s is a list of paths or systems" % (where, k))
    else:
        problems.append("%s: kind is block (the default) or decision" % where)
    return {"id": sid, "kind": kind, "deps": list(deps), "raw": s}


def waves(blocks):
    """[[ids]…]: each wave's blocks depend only on earlier waves. Raises on a cycle."""
    left = {s["id"]: set(s["deps"]) for s in blocks}
    order = [s["id"] for s in blocks]
    out, done = [], set()
    while left:
        wave = [i for i in order if i in left and left[i] <= done]
        if not wave:
            raise BlueprintError(["a cycle in depends_on: %s" % ", ".join(i for i in order if i in left)])
        out.append(wave)
        done |= set(wave)
        for i in wave:
            left.pop(i)
    return out


def load(path, text=None, key=None, accepted=()):
    """The blueprint, validated: {path, meta, blocks (file order), by_id, waves, preamble, sections,
    warnings, yard_warnings}. Raises BlueprintError with every problem found. `key`: the registry key
    its repo is read as, in place of `repo:` (a pinned ship's pin: the yard never resolves a caller's
    path). `accepted`: digests a plan has accepted — a ship already in flight under one of them has a
    `host:` the yard rule refuses only warned of (yard_warnings), since refusing it would stop a ship
    that was valid when it was laid; a new compile is refused as before."""
    path = Path(path)
    if text is None:
        text = path.read_text()
    meta, body, first = front_matter(text)
    problems, warnings = [], []
    for k in sorted(set(meta) - TOP_KEYS):
        problems.append("front matter: %s is not a blueprint key (%s)" % (k, ", ".join(sorted(TOP_KEYS))))
    name = meta.get("ship")
    if not isinstance(name, str) or not ID_RE.match(name):
        problems.append("front matter: ship names the ship it builds, [a-z0-9][a-z0-9-]*")
    if not isinstance(meta.get("repo"), str) or not meta["repo"].strip():
        problems.append("front matter: repo names the repo (a name under ~/projects, or an absolute path)")
    if not isinstance(meta.get("created"), str) or not DATE_RE.match(meta["created"]):
        problems.append("front matter: created is a date, yyyy-mm-dd")
    for k in ("skipper", "manager", "sent_by"):
        if k in meta and not (isinstance(meta[k], str) and meta[k].strip()):
            problems.append("front matter: %s is a non-empty string" % k)
    if "merge" in meta and not (isinstance(meta["merge"], (bool, str)) and meta["merge"] in MERGE):
        problems.append("front matter: merge is yes or no")
    if "mode" in meta and meta["mode"] not in MODES:
        problems.append("front matter: mode is one of %s" % ", ".join(MODES))
    if meta.get("skipper") and meta.get("manager"):
        problems.append("front matter: skipper or manager, not both (one is the other's old word)")
    m = re.match(r"^(\d{4}-\d{2}-\d{2})-(.+)\.md$", path.name)
    if m and isinstance(name, str) and m.group(2) != name:
        warnings.append("the file is named for %s, its ship is %s" % (m.group(2), name))
    raw = meta.get("blocks")
    if not isinstance(raw, list) or not raw:
        problems.append("front matter: blocks is a non-empty list")
        raw = []
    blocks, by_id = [], {}
    # a `host:` is checked against the yards only where the repo's scope has one: with no yard set
    # anywhere (before the overlay's S3) nothing is refused that was not before
    repo = key or (meta["repo"] if isinstance(meta.get("repo"), str) else None)
    yard = scope_yard_of(repo)[2] if repo else None
    yards = set(_yards().values()) if yard else None
    yard_problems = []
    for i, s in enumerate(raw):
        st = _check_block(s, i, problems, hosts_of(repo) if repo else None, yards, yard_problems)
        if not st or not st["id"]:
            continue
        if st["id"] in by_id:
            problems.append("block %s: a second block with this id" % st["id"])
            continue
        by_id[st["id"]] = st
        blocks.append(st)
    for st in blocks:
        for d in st["deps"]:
            if d == st["id"]:
                problems.append("block %s: depends on itself" % d)
            elif d not in by_id:
                problems.append("block %s: depends_on %s, which is no block" % (st["id"], d))
    for st in blocks:
        # wharf fills <wt> with the one predecessor's worktree on this machine; a block on a host has
        # its worktree there, so a launch after only such blocks would wait for ever (review 2026-10-18)
        if "<wt>" in str(st["raw"].get("command") or ""):
            deps = [by_id[d] for d in st["deps"] if d in by_id and by_id[d]["kind"] == "block"
                    and by_id[d]["raw"].get("provider") in ("orca", "claude-code")]
            far = [d["id"] for d in deps if d["raw"].get("host", "here") != "here"]
            if far and len(far) == len(deps):
                problems.append("block %s: <wt> is a worktree here; %s runs on %s, its worktree is there"
                                % (st["id"], far[0], by_id[far[0]]["raw"]["host"]))
    pre, secs, sp = sections(body, first)
    problems += sp
    for sid, (n, _) in secs.items():
        if sid in by_id or sid.startswith("?"):
            continue
        problems.append("line %d: `## %s` is a section for no block" % (n, sid))
    for st in blocks:
        st["section"] = secs.get(st["id"], (None, ""))[1]
        st["line"] = secs.get(st["id"], (None, ""))[0]
        if st["kind"] == "block" and st["raw"].get("provider") in ("orca", "claude-code"):
            if st["id"] not in secs:
                problems.append("block %s: no `## %s` section — its brief is what the worker is handed" % (st["id"], st["id"]))
            else:
                have = set(BRIEF_RE.findall(st["section"]))
                missing = [x for x in BRIEF_LINES if x not in have]
                if missing:
                    problems.append("line %d: `## %s` lacks the handoff lines %s" % (st["line"], st["id"], ", ".join(missing)))
    w = []
    if not problems:
        try:
            w = waves(blocks)
        except BlueprintError as e:
            problems += e.problems
    sections_text = {k: v[1] for k, v in secs.items()}
    yard_warnings = []
    if yard_problems:
        if not problems and accepted and digest({"meta": meta, "preamble": pre, "sections": sections_text}) in accepted:
            yard_warnings = yard_problems
        else:
            problems += yard_problems
    if problems:
        raise BlueprintError(problems)
    if len(w) > DEEP:
        warnings.append("%d waves deep; Orca's guide: \"prefer parallel waves over chains deeper than three or four steps\"" % len(w))
    return {"path": str(path), "meta": meta, "name": name, "blocks": blocks, "by_id": by_id, "waves": w,
            "preamble": pre, "sections": sections_text, "warnings": warnings, "yard_warnings": yard_warnings}


# ---------------------------------------------------------------------------- what a block compiles to

def _canon(x):
    return json.dumps(x, sort_keys=True, ensure_ascii=False, separators=(",", ":"))


def digest(blueprint):
    """sha256 over the sorted front matter, the preamble and each section's text (Q1)."""
    blob = _canon({"front": blueprint["meta"], "preamble": blueprint["preamble"], "sections": blueprint["sections"]})
    return hashlib.sha256(blob.encode()).hexdigest()


def block_digests(blueprint):
    return {s["id"]: hashlib.sha256(_canon({"block": s["raw"], "section": s["section"]}).encode()).hexdigest()
            for s in blueprint["blocks"]}


def changes(old_blocks, new_blocks):
    """(added, changed, removed) block ids between two block-digest maps."""
    old, new = old_blocks or {}, new_blocks or {}
    return (sorted(set(new) - set(old)), sorted(k for k in new if k in old and new[k] != old[k]),
            sorted(set(old) - set(new)))


# What every builder is handed below its brief: the rules that needed a person on 2026-10-19 (a shim
# edited instead of its module, a suite the OS killed read as a failure, a report held back for a
# whole check, a question whose answer was in the brief). Fixed text, added by spec_of and not
# written into the file, so the digest — over the file's own text — never moves with it.
YARD_RULES = """### Yard rules

- Read a file's first lines on `main` before editing it. A source or exec shim's text lives in `~/projects/regatta`'s module: edit it there, in a regatta worktree, and name both branches in the report.
- A suite killed by the OS (exit 137 or 143, "Killed", low memory) is rerun alone, once. It is not a failure and not a question.
- Report done once the work is committed and the marker written, saying what of the check did not run: the launch's `/finish` runs it whole.
- A whole check runs through `{check} <worktree>`, never by hand: with `run_in_background`, or under `CLAUDE_UNATTENDED` as `nohup … --out <dir> > <dir>.out 2>&1 &` in one call, then poll `<dir>/summary` until its last line starts `DONE`, `INTERRUPTED` or `REFUSED`. It waits for one of the Mac's two check slots; a suite to rerun goes through `--only <script>`; an `UNRUN` command (exit 3, a script only this branch's line has) is run by its own Bash call.
- Never wait on the coordinator for anything the brief already answers."""

# The rules' earlier texts, newest first: a Task made under one is not drift (diff()). Added 2026-10-19
# with the bin/check rule (check-slots, the skipper's answer): yard-smooth's four rules.
YARD_RULES_PAST = (
    """### Yard rules

- Read a file's first lines on `main` before editing it. A source or exec shim's text lives in `~/projects/regatta`'s module: edit it there, in a regatta worktree, and name both branches in the report.
- A suite killed by the OS (exit 137 or 143, "Killed", low memory) is rerun alone, once. It is not a failure and not a question.
- Report done once the work is committed and the marker written, saying what of the check did not run: the launch's `/finish` runs it whole.
- Never wait on the coordinator for anything the brief already answers.""",
)


def _check_tool():
    """The whole-check tool a builder is told to run: this module's own through the core's tool()
    (the overlay's `bin/check` came first until B14b, 2026-10-23, which deleted it), written with
    `~` for the home as the rules always read."""
    home = str(Path.home())
    try:
        import common
        p = common.tool("check")
    except Exception:  # noqa: BLE001 — no core on the path: the module's own copy
        p = None
    p = str(p if p else Path(__file__).resolve().parent / "check")
    return "~" + p[len(home):] if p.startswith(home + "/") else p


def _past_rules():
    """YARD_RULES_PAST, plus the rules as a Task made before B14b holds them: filled in with the
    overlay's `bin/check`, which _check_tool() named first until then. Without it every pending Task
    reads as spec drift and `wharf apply` re-specs whole plans (the B14b landing review)."""
    past = YARD_RULES_PAST
    try:
        import common
        ov = common.overlay_root()
    except Exception:  # noqa: BLE001 — no core on the path: no overlay to have named
        ov = None
    if ov:
        home, p = str(Path.home()), str(Path(ov).expanduser() / "bin" / "check")
        past += (YARD_RULES.replace("{check}", "~" + p[len(home):] if p.startswith(home + "/") else p),)
    return past


def yard_rules():
    """YARD_RULES below, with the check tool's path filled in (a function: the path is looked up when
    a Task is made, never at import, where the core may not be on the path yet)."""
    return YARD_RULES.replace("{check}", _check_tool())


def spec_of(blueprint, st, rules=True):
    """The text an Orca Task carries as --spec: a block's section whole, the Yard rules below an orca
    or claude-code block's (rules=False: the spec as it was before 2026-10-19, which diff() still
    takes as unchanged); a decision's question first."""
    s = st["raw"]
    if st["kind"] == "decision":
        head = "decision: %s#%s" % (s["doc"], ", ".join(s["items"]))
        return head + ("\n\n" + st["section"] if st["section"] else "")
    if s.get("provider") == "shell":
        head = "shell: %s" % s["command"]
        return head + ("\n\n" + st["section"] if st["section"] else "")
    return st["section"] + ("\n\n" + yard_rules() if rules else "")


def remote_host(s, here):
    """The host a block runs on when that is not this machine, else None: `here` and this machine's
    own name (repos.json lists it too) are both local, as bin/harness's peers() never names itself."""
    h = s.get("host", "here")
    return None if h in ("here", "auto", here) else h   # auto: placed by dispatch's berth at the start, from here


def host_label(st, here):
    return remote_host(st["raw"], here) or here


def branch_of(blueprint, st, here):
    """claude/<host>/<created>-<id>, unless the block names its branch. A decision has none, nor a
    shell block unless it names one (a launch acts on its predecessor's branch)."""
    if st["kind"] == "decision" or (st["raw"].get("provider") == "shell" and not st["raw"].get("branch")):
        return None
    return st["raw"].get("branch") or "claude/%s/%s-%s" % (host_label(st, here), blueprint["meta"]["created"], st["id"])


def owner_key():
    """The doer a decision block names in the plan: the owner's lower-cased name (`regatta/owner`),
    `owner` where none is set; on the owner's Macs the string helm's readers already match."""
    try:
        import common
        return (common.OWNER_NAME or "").lower() or "owner"
    except Exception:  # noqa: BLE001 — no core on the path
        return "owner"


def plan_fields(blueprint, st, here, repo):
    """The plan.json task a block is (bin/helm task's keys): what the plan keeps that Orca has no slot for.
    A task names its block (`block`, helm-vocabulary D2 Revised: the block is the description, the
    task its execution) and its doer as `by` (D3-A; `owner` before rename S5)."""
    s = st["raw"]
    t = {"title": s.get("title") or st["id"], "ship": blueprint["name"], "block": st["id"], "repo": repo,
         "deps": list(st["deps"])}
    if st["kind"] == "decision":
        t.update(kind="human", by=owner_key(), provider="memo")
        return t
    t.update(kind="session", provider=s["provider"], host=host_label(st, here), branch=branch_of(blueprint, st, here))
    for k in ("agent", "done_when", "owns", "live"):
        if s.get(k) is not None:
            t[k] = s[k]
    if s["provider"] == "orca" and "agent" not in t:
        t["agent"] = "claude"
    return t


def describe(st):
    s = st["raw"]
    if st["kind"] == "decision":
        return "decision %s %s" % (s["doc"], ", ".join(s["items"]))
    bits = [s["provider"] + ("/" + s["agent"] if s.get("agent") else "")]
    if s.get("host", "here") != "here":
        bits.append("on " + s["host"])
    if s.get("tier"):
        bits.append(s["tier"])
    if s.get("model"):
        bits.append(s["model"] + ("·" + s["effort"] if s.get("effort") else ""))
    elif s.get("effort"):
        bits.append("effort " + s["effort"])
    if s["provider"] == "shell":
        bits.append("`%s`" % s["command"])
    if s.get("done_when"):
        (k, v), = s["done_when"].items()
        bits.append("done when %s %s" % (k, v if v is not True else ""))
    extra = []
    if "retries" in s:
        extra.append("retries %d" % s["retries"])
    if "timeout_seconds" in s:
        t = s["timeout_seconds"]
        extra.append("timeout %s" % ("%dh" % (t // 3600) if t % 3600 == 0 else "%dm" % (t // 60) if t % 60 == 0 else "%ds" % t))
    if s.get("launch"):
        extra.append("launched by %s" % s["launch"])
    if s.get("physical") and s["physical"] != "none":
        extra.append("physical: %s" % s["physical"])
    return " ".join(b.strip() for b in bits) + (" · " + ", ".join(extra) if extra else "")


def graph_lines(blueprint, here):
    meta = blueprint["meta"]
    who = meta.get("skipper") or meta.get("manager")
    out = ["ship %s — repo %s%s, created %s" % (blueprint["name"], meta["repo"],
                                                  ", skipper %s" % who if who else "", meta["created"]),
           "digest %s · %d blocks in %d waves" % (digest(blueprint)[:12], len(blueprint["blocks"]), len(blueprint["waves"]))]
    width = max(len(s["id"]) for s in blueprint["blocks"])
    for i, wave in enumerate(blueprint["waves"], 1):
        out.append("wave %d" % i)
        for sid in wave:
            st = blueprint["by_id"][sid]
            br = branch_of(blueprint, st, here)
            out.append("  %-*s  %s%s" % (width, sid, describe(st), ("  ← " + ", ".join(st["deps"])) if st["deps"] else ""))
            if br:
                out.append("  %-*s  %s" % (width, "", br))
    for w in blueprint["warnings"]:
        out.append("warning: %s" % w)
    return out


def as_json(blueprint, here):
    return {"ship": blueprint["name"], "path": blueprint["path"], "meta": {k: v for k, v in blueprint["meta"].items() if k != "blocks"},
            "digest": digest(blueprint), "block_digests": block_digests(blueprint), "waves": blueprint["waves"],
            "warnings": blueprint["warnings"],
            "blocks": [dict(st["raw"], id=st["id"], kind=st["kind"], depends_on=st["deps"],
                           branch=branch_of(blueprint, st, here), section_line=st["line"]) for st in blueprint["blocks"]]}


# ---------------------------------------------------------------------------- the diff (Q2's drift)

def _deps_of(task):
    d = task.get("deps")
    if isinstance(d, str):
        try:
            d = json.loads(d)
        except ValueError:
            d = []
    return list(d or [])


def _worker_view(rows):
    """{task id: [dispatch rows]} from `worker-list --run`."""
    out = {}
    for r in rows or []:
        out.setdefault(r.get("taskId"), []).append(r)
    return out


def _live(row):
    proj = row.get("projection") or {}
    verdict = str((proj.get("liveness") or {}).get("verdict") or "").lower()
    disp = str(row.get("dispatchStatus") or "").lower()
    return verdict != "exited" and disp not in ("completed", "succeeded", "failed", "canceled", "cancelled", "stopped")


def _succeeded(row):
    proj = row.get("projection") or {}
    return str(proj.get("outcome") or "").lower() == "succeeded" or str(row.get("dispatchStatus") or "").lower() in ("completed", "succeeded")


def diff(blueprint, here, plan_tasks, orca, answered=None, ended=None, cancelled=(), repo=None):
    """{"orca": rows, "plan": rows}, each row (action, block or None, detail) — Q2's drift, nothing called.

    plan_tasks  plan.json's tasks (id → dict)
    orca        None (no Run recorded: every block is created) or {"run", "tasks", "gates", "workers"}
                as Orca's CLI returned them
    answered    doc, items → (all answered?, the answers text) — the memo doc's word, for a gate
    ended       block id → True when the plan says it is done or launched (a branch launched)
    cancelled   Task ids a re-spec failed on purpose: never a block's again, never an orphan

    Orca's actions: create, gate, resolve, start, stalled, complete, changed, failed, orphan, refuse,
    ok; the plan's: add, update, record, orphan, ok."""
    rows = []
    tasks = (orca or {}).get("tasks") or []
    by_title = {}
    for t in tasks:
        if t.get("id") not in cancelled:
            by_title.setdefault(t.get("task_title"), []).append(t)
    by_tid = {t.get("id"): t for t in tasks}
    gates = {}
    for g in (orca or {}).get("gates") or []:
        gates.setdefault(g.get("task_id"), []).append(g)
    workers = _worker_view((orca or {}).get("workers"))
    mapped = {}
    for st in blueprint["blocks"]:
        rec = (plan_tasks.get(st["id"]) or {}).get("orca_task")
        hit = by_tid.get(rec) if rec and rec not in cancelled else None
        if not hit and by_title.get(st["id"]):
            # a re-spec cancels a Task and creates it again under the same title: the live one wins,
            # whatever order task-list returns them in
            same = by_title[st["id"]]
            hit = ([t for t in same if str(t.get("status") or "").lower() not in ("cancelled", "canceled", "failed")]
                   or same)[-1]
        if hit:
            mapped[st["id"]] = hit
    used = {t.get("id") for t in mapped.values()}
    # every Task carrying a block's title is that block's, the cancelled ones included: none is an orphan
    used |= {t.get("id") for sid in mapped for t in by_title.get(sid) or []}
    used |= set(cancelled)
    created = set()
    for wave in blueprint["waves"]:
        for sid in wave:
            st = blueprint["by_id"][sid]
            s = st["raw"]
            t = mapped.get(sid)
            phys = s.get("physical")
            if t is None:
                after = [d for d in st["deps"]]
                rows.append(("create", sid, "task-create --task-title %s%s" % (sid, (" --deps " + ",".join(after)) if after else "")))
                created.add(sid)
                if st["kind"] == "decision":
                    rows.append(("gate", sid, "gate-create on its task: %s#%s" % (s["doc"], ", ".join(s["items"]))))
                elif not after:
                    rows.append(("refuse", sid, "physical: %s — apply starts only physical: none" % phys) if phys and phys != "none"
                                else ("start", sid, "ready once created: " + _start_text(blueprint, st, here)))
                continue
            status = str(t.get("status") or "").lower()
            want_deps = sorted(mapped[d].get("id") if d in mapped else "<%s>" % d for d in st["deps"])
            drift = []
            # a Task created before the Yard rules rode in the spec is not re-specced for them
            if (t.get("spec") or "") not in (spec_of(blueprint, st), spec_of(blueprint, st, rules=False)) + tuple(
                    st["section"] + "\n\n" + r for r in _past_rules()):
                drift.append("spec")
            if sorted(_deps_of(t)) != want_deps:
                drift.append("deps")
            if drift:
                how = ("re-spec: fail it cancelled, create it again" if status in ("pending", "ready", "blocked")
                       else "a card: a dispatched worker's spec is never edited" if status == "dispatched"
                       else "a card: it already ended")
                rows.append(("changed", sid, "%s differ from %s (%s) — %s" % (" and ".join(drift), t.get("id"), status, how)))
            if st["kind"] == "decision":
                gs = gates.get(t.get("id")) or []
                pending = [g for g in gs if str(g.get("status")).lower() == "pending"]
                if not gs:
                    rows.append(("gate", sid, "no gate on %s: gate-create %s#%s" % (t.get("id"), s["doc"], ", ".join(s["items"]))))
                elif pending:
                    ok, text = answered(s["doc"], s["items"]) if answered else (False, None)
                    gid = pending[0].get("id")
                    if ok:
                        rows.append(("resolve", sid, "gate %s: answered (%s) — gate-resolve, then task-update completed" % (gid, text)))
                    elif text:
                        # the doc or an item is missing: a gate that can never resolve is not "ok"
                        rows.append(("refuse", sid, "gate %s cannot resolve: %s" % (gid, text)))
                    else:
                        rows.append(("ok", sid, "gate %s waits on %s#%s" % (gid, s["doc"], ", ".join(s["items"]))))
                elif status != "completed":
                    rows.append(("complete", sid, "gate resolved, %s is %s: task-update completed" % (t.get("id"), status)))
                else:
                    rows.append(("ok", sid, "%s completed" % t.get("id")))
                continue
            ds = workers.get(t.get("id")) or []
            live = [d for d in ds if _live(d)]
            if ended and ended(sid) and status != "completed":
                rows.append(("complete", sid, "the plan has it ended, %s is %s: task-update completed" % (t.get("id"), status)))
            elif status == "ready" and not live:
                rows.append(("refuse", sid, "physical: %s — apply starts only physical: none" % phys) if phys and phys != "none"
                            else ("start", sid, _start_text(blueprint, st, here)))
            elif status == "dispatched" and ds and not live and not any(_succeeded(d) for d in ds):
                rows.append(("stalled", sid, "dispatch %s exited with no worker_done (S1: the tick's)" % ds[0].get("dispatchId")))
            elif status == "failed":
                rows.append(("failed", sid, "%s failed%s" % (t.get("id"), (": " + str(t.get("result"))) if t.get("result") else "")))
            else:
                rows.append(("ok", sid, "%s %s%s" % (t.get("id"), status, (", dispatch %s live" % live[0].get("dispatchId")) if live else "")))
    for t in tasks:
        if t.get("id") not in used:
            rows.append(("orphan", None, "Orca task %s (%s, %s) is in the Run but no block of the file" % (
                t.get("id"), t.get("task_title"), t.get("status"))))
    # the plan's side: the tasks plan.json would hold
    orca_rows, rows = rows, []
    # a pinned ship's tasks carry its pin's repo key (wharf's ship_repo), not a `repo:` path
    repo = repo or blueprint["meta"]["repo"]
    for st in blueprint["blocks"]:
        want = plan_fields(blueprint, st, here, repo)
        have = plan_tasks.get(st["id"])
        if have and have.get("seeded_branch"):
            # bin/pickup seed names the branch by the day it ran: read back, never predicted again
            want["branch"] = have["seeded_branch"]
        t = mapped.get(st["id"])
        if have is None:
            rows.append(("add", st["id"], "plan task %s (%s)%s" % (st["id"], want.get("provider"),
                                                                   (", orca_task %s (found by its title)" % t.get("id")) if t is not None else "")))
            continue
        # a task written before rename S5 has no `block` (its id is the block's) and says `owner`, not `by`
        have = dict(have, block=have.get("block") or st["id"], by=have.get("by") or have.get("owner"))
        diffs = sorted(k for k, v in want.items() if have.get(k) != v)
        if diffs:
            rows.append(("update", st["id"], "plan task fields differ: %s" % ", ".join(diffs)))
        else:
            rows.append(("ok", st["id"], "plan task as the file says"))
        if t is not None and have.get("orca_task") != t.get("id"):
            rows.append(("record", st["id"], "orca_task %s (found by its title)" % t.get("id")))
    for name, have in sorted(plan_tasks.items()):
        if have.get("ship") == blueprint["name"] and name not in blueprint["by_id"]:
            rows.append(("orphan", name, "plan task of this ship, no block of the file"))
    return {"orca": orca_rows, "plan": rows}


def _start_text(blueprint, st, here):
    s = st["raw"]
    br = branch_of(blueprint, st, here)
    if s["provider"] == "orca":
        mm = (" --model %s" % s["model"] if s.get("model") else "") + (" --effort %s" % s["effort"] if s.get("effort") and s.get("model") else "")
        on = " --on %s" % remote_host(s, here) if remote_host(s, here) else ""
        return "worker-start --task <%s>%s --agent %s%s on %s (the worktree: B6a's pick, --base-branch main)" % (
            st["id"], on, s.get("agent", "claude"), mm, br)
    if s["provider"] == "claude-code":
        on = remote_host(s, here) or ("auto" if s.get("host") == "auto" else None)
        return "dispatch %s%s%s%s" % (br, " --on %s" % on if on else "",
                                      " --account %s" % s["account"] if s.get("account") else "", " --yolo" if s.get("yolo") else "")
    return "sh -c %s, then task-update completed|failed" % json.dumps(s["command"])
