#!/usr/bin/env bash
# Tests for bin/orca-host: which repos each scope's Orca group holds on a Mac (anchor first, twins,
# other hosts' and missing checkouts left out, a knowledge repo kept in, short names unless they
# clash, the worktree base only on the workflow), the plan from what Orca holds (nothing once
# converged, each drifted field alone, extra repos and groups only noted, nestWorkspaces named), the
# runtime client against a fake socket (the answer matched by id past a keepalive, a refusal raised
# with its method), the pairing link's checks (not a link, a phone link, a link to the wrong Mac),
# and the pairs and ssh aliases read from the config dir. Host and repo names are made up.
# Scratch paths only; no Orca, no network.
#   bash modules/wharf-runs/tests/orca-host.sh
set -u
M="$(cd "$(dirname "$0")/.." && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
for v in $(env | sed -n 's/^\(REGATTA[A-Za-z0-9_]*\)=.*/\1/p; s/^\(ORCA_HOST[A-Za-z0-9_]*\)=.*/\1/p'); do unset "$v"; done
unset CLAUDE_REPOS_JSON
export HOME="$T/home" REGATTA_CONFIG="$T/config" CLAUDE_CONFIG_DIR="$T/claude"; mkdir -p "$HOME" "$REGATTA_CONFIG"

python3 - "$M" "$T" <<'EOF'
import base64, fnmatch, importlib.machinery, importlib.util, json, os, socket, sys, threading
from pathlib import Path
M, T = Path(sys.argv[1]), Path(sys.argv[2])

def load(name, path):
    loader = importlib.machinery.SourceFileLoader(name, str(path))
    mod = importlib.util.module_from_spec(importlib.util.spec_from_loader(name, loader))
    loader.exec_module(mod)
    return mod

oh = load("orca_host", M / "bin" / "orca-host")

class sc:
    """The two functions orca-host takes from the wharf module's `scopes`, to their contract: a
    scope's members in its order (a glob matches sorted keys); its folders anchor first, the rest
    in order, twins last. The real one also appends the overlay's own checkout, which `wanted`
    drops unless the scope names it."""
    @staticmethod
    def members(scope, repos):
        out = []
        for m in scope.get("repos") or []:
            hits = sorted(k for k in repos if fnmatch.fnmatchcase(k, m)) if any(c in m for c in "*?[") else [m]
            out += [k for k in hits if k not in out]
        return out
    @staticmethod
    def folders(scope, repos):
        keys = [k for k in sc.members(scope, repos) if k in repos]
        return keys[:1] + [k for k in keys[1:] if not repos[k].get("twin_of")] + [k for k in keys[1:] if repos[k].get("twin_of")]

fails = 0
def check(cond, label):
    global fails
    print(("  ok   " if cond else "  FAIL ") + label)
    fails += not cond

# ---- wanted
base = T / "projects"
repos = {"tools": {}, "notes": {"knowledge": True}, "a": {}, "b/x": {}, "c/x": {},
         "oss/a": {"twin_of": "a"}, "far": {"hosts": ["studio"]}, "gone": {}, "w": {}}
scopes = {"base": {"file": "base.code-workspace", "repos": ["tools", "notes"]},
          "work": {"file": "work.code-workspace", "repos": ["a", "oss/a", "b/x", "c/x", "far", "gone"]},
          "empty": {"file": "e.code-workspace", "repos": ["w"]}}
for k in ["tools", "notes", "a", "b/x", "c/x", "oss/a", "far"]:
    (base / k / ".git").mkdir(parents=True)
(base / "a" / ".claude").mkdir()
(base / "a" / ".claude" / "workflow.json").write_text(json.dumps({"checkpoint": True, "main": "trunk"}))
want = oh.wanted(repos, scopes, "laptop", base, sc)
names = [g["name"] for g in want]
check(names == ["base", "work"], f"a scope with no repo here gets no group (got {names})")
work = want[1]
check([r["key"] for r in work["repos"]] == ["a", "b/x", "c/x"],
      "work: anchor first; twin, other host's repo and missing checkout left out")
check([r["key"] for r in want[0]["repos"]] == ["tools", "notes"],
      "a knowledge repo is in its scope's group: the account guard, not Orca, keeps a login out")
check({r["key"]: r["name"] for r in work["repos"]} == {"a": "a", "b/x": "b/x", "c/x": "c/x"},
      "two repos sharing a folder name are named by key, a lone one by its folder")
a = work["repos"][0]
check(a["base_ref"] == "trunk" and a["base_path"] == str(base / "a" / ".claude" / "worktrees"),
      "a repo on the workflow: its own main, worktrees in .claude/worktrees")
check(work["repos"][1]["base_ref"] == "main" and work["repos"][1]["base_path"] is None,
      "a repo off the workflow: main, and Orca's own worktree home")
check(want[0]["color"] != want[1]["color"] and all(r["color"] == work["color"] for r in work["repos"]),
      "each group its own colour; a repo wears its group's")
check([g["order"] for g in want] == [0, 1], "groups ordered as the registry lists them")

# ---- plan
steps, notes = oh.plan(want, [], [])
kinds = [s[0] for s in steps]
check(kinds.count("group") == 2 and kinds.count("add") == 5 and kinds.count("move") == 5,
      "from an empty Orca: every group created, every repo added and placed")
check(kinds.index("group") < kinds.index("add") < kinds.index("move"), "a group exists before a repo moves into it")

groups = [{"id": "g1", "name": "base", "color": want[0]["color"], "tabOrder": 0},
          {"id": "g2", "name": "work", "color": work["color"], "tabOrder": 1},
          {"id": "g9", "name": "old"}]
def held(g, gid):
    out = []
    for i, r in enumerate(g["repos"]):
        row = {"path": r["path"], "displayName": r["name"], "badgeColor": r["color"],
               "worktreeBaseRef": r["base_ref"], "externalWorktreeVisibility": "show",
               "projectGroupId": gid, "projectGroupOrder": i}
        if r["base_path"]:
            row["worktreeBasePath"] = r["base_path"]
        out.append(row)
    return out
orca = held(want[0], "g1") + held(work, "g2") + [{"path": "/tmp/scratch", "displayName": "scratch"}]
steps, notes = oh.plan(want, groups, orca)
check(steps == [], f"converged: no steps (got {steps})")
check(any("scratch" in n for n in notes) and any("'old'" in n for n in notes),
      "a repo and a group no scope names are noted, never removed")
orca[2]["badgeColor"] = "#000000"
orca[3]["projectGroupOrder"] = 0
orca[4]["externalWorktreeVisibility"] = "hide"
steps, _ = oh.plan(want, groups, orca)
check(steps == [("set", "a", a["path"], {"badgeColor": work["color"]}),
                ("move", "b/x", work["repos"][1]["path"], "work", 1),
                ("show", "c/x", work["repos"][2]["path"])],
      f"each drift is one step and only that field (got {steps})")
left = [dict(g, repos=[dict(r) for r in g["repos"]]) for g in want]
left[1]["repos"][1]["base_path"] = None
cur = [dict(o) for o in orca]; cur[3]["worktreeBasePath"] = work["repos"][1]["path"] + "/.claude/worktrees"
cur[2]["badgeColor"] = work["color"]; cur[3]["projectGroupOrder"] = 1; cur[4]["externalWorktreeVisibility"] = "show"
steps, _ = oh.plan(left, groups, cur)
check(steps == [("set", "b/x", work["repos"][1]["path"], {"worktreeBasePath": ""})],
      f"a repo that left the workflow gets Orca's own worktree home back (got {steps})")
for bad in (["pair", "studio", "--link"], ["pair", "studio", "--link", "orca://pair?code=x"]):
    check(oh.main(bad) == 2, f"--link takes only '-': {bad[2:]} refused, no traceback, the link kept out of argv")
_, notes = oh.plan(want, groups, orca, nest=True)
check(any("nestWorkspaces" in n for n in notes), "nestWorkspaces on is named")

# ---- the runtime client, against a fake socket
sock_path = str(T / "o.sock")
srv = socket.socket(socket.AF_UNIX); srv.bind(sock_path); srv.listen(4)
seen = []
def serve():
    for _ in range(2):
        c, _ = srv.accept()
        req = json.loads(c.makefile().readline())
        seen.append(req)
        c.sendall(b'{"_keepalive":true}\n')
        if req["method"] == "projectGroup.list":
            c.sendall((json.dumps({"id": "other", "ok": True}) + "\n" +
                       json.dumps({"id": req["id"], "ok": True, "result": {"groups": [{"id": "g"}]}}) + "\n").encode())
        else:
            c.sendall((json.dumps({"id": req["id"], "ok": False, "error": {"message": "nope"}}) + "\n").encode())
        c.close()
threading.Thread(target=serve, daemon=True).start()
data = T / "orca"; data.mkdir()
(data / "orca-runtime.json").write_text(json.dumps({"transports": [{"kind": "websocket", "endpoint": "ws://x"},
                                                                   {"kind": "unix", "endpoint": sock_path}],
                                                    "authToken": "tok"}))
rt = oh.Runtime(data, timeout=5)
check(rt.call("projectGroup.list") == {"groups": [{"id": "g"}]}, "the answer is the line with the request's id")
check(seen[0]["authToken"] == "tok" and seen[0]["params"] == {}, "the request carries the owner token")
try:
    rt.call("repo.update", {"repo": "path:/x"})
    check(False, "a refusal raises")
except oh.OrcaError as e:
    check("repo.update" in str(e) and "nope" in str(e), "a refusal raises, naming the method and Orca's message")
try:
    oh.Runtime(T / "none").call("repo.list")
    check(False, "no runtime file raises")
except oh.OrcaError as e:
    check("not running" in str(e), "no runtime file: 'not running'")

# ---- pairing links
def link(offer):
    return "orca://pair?code=" + base64.urlsafe_b64encode(json.dumps(offer).encode()).decode().rstrip("=")
good = {"v": 2, "endpoint": "ws://192.0.2.51:6768", "scope": "runtime", "deviceToken": "secret"}
addrs = {"192.0.2.51", "studio.example.ts.net"}
check(oh.check_offer(oh.decode_link(link(good)), "studio", addrs) is None, "a runtime link to the peer passes")
check("not a runtime" in (oh.check_offer(dict(good, scope="mobile"), "studio", addrs) or ""), "a phone link is refused")
why = oh.check_offer(dict(good, endpoint="ws://198.51.100.7:6768"), "studio", addrs) or ""
check("198.51.100.7" in why and "secret" not in why, "a link to another address is refused, the token never echoed")
try:
    oh.decode_link("https://example.com/?code=x")
    check(False, "a non-link raises")
except oh.OrcaError as e:
    check("not an Orca pairing link" in str(e), "a non-link raises")
try:
    oh.decode_link("orca://pair?code=" + base64.urlsafe_b64encode(b"[1]").decode())
    check(False, "a code that is no object raises")
except oh.OrcaError as e:
    check("does not decode" in str(e), "a code that decodes to a list: an error, no traceback")
import io as _io
sys.stdin = _io.StringIO(link(dict(good, scope="mobile")))
os.environ["ORCA_HOST_SSH"] = "false-ssh-never-run"
check(oh.main(["--on", "studio", "pair", "laptop", "--link", "-"]) == 1,
      "--on … --link -: a phone link on stdin is refused here, before any ssh")
sys.stdin = sys.__stdin__

# ---- the registry, the CLI
reg = T / "reg.json"
reg.write_text(json.dumps({"repos": {"a": {}}, "scopes": {"s": {"repos": ["a"]}}}))
os.environ["CLAUDE_REPOS_JSON"] = str(reg)
check(oh.registry() == ({"a": {}}, {"s": {"repos": ["a"]}}), "the registry is the core's repos_json()")
reg.write_text(json.dumps({"repos": {"a": {}}, "scopes": ["s"]}))
try:
    oh.registry()
    check(False, "a registry of the wrong shape raises")
except oh.OrcaError as e:
    check("not a map" in str(e), "a registry whose scopes are a list: an error, no traceback")
del os.environ["CLAUDE_REPOS_JSON"]
app = T / "Orca.app"; (app / "Contents/Resources/bin").mkdir(parents=True); (app / "Contents/Resources/bin/orca").write_text("")
plotly = T / "plotly"; plotly.mkdir(); (plotly / "orca").write_text("#!/bin/sh\n"); (plotly / "orca").chmod(0o755)
saved, saved_path = oh.ORCA_APP, os.environ["PATH"]
oh.ORCA_APP, os.environ["PATH"] = app, f"{plotly}:{saved_path}"
check(oh.orca_bin() == str(app / "Contents/Resources/bin/orca"),
      "the app's own CLI before an `orca` first on PATH (plotly's chart tool shares the name)")
oh.ORCA_APP, os.environ["PATH"] = saved, saved_path

# ---- --on PEER pair: the clipboard, a dry run, the peer's name
calls, sent = [], []
class Done:
    def __init__(self, out=""): self.stdout, self.returncode = out, 0
def fake_run(argv, **kw):
    calls.append(argv[0])
    return Done(link(good) if argv[0] == "pbpaste" else "")
real_run, real_on = oh.subprocess.run, oh.run_on
oh.subprocess.run = fake_run
oh.run_on = lambda peer, argv, stdin=None: sent.append((peer, argv)) or 0
oh.main(["--on", "Studio", "pair", "laptop", "--dry-run"])
check(calls == ["pbpaste"] and sent == [("studio", ["pair", "laptop", "--dry-run", "--link", "-"])],
      "--on Studio pair --dry-run: the peer lower-cased, the link sent on stdin, the clipboard kept")
calls.clear(); sent.clear()
oh.main(["--on", "studio", "pair", "laptop"])
check(calls == ["pbpaste", "pbcopy"], "  the real run clears the clipboard after")
oh.subprocess.run, oh.run_on = real_run, real_on

# ---- the core found from a copy outside any checkout (what --on runs): the home file as the core reads it
outside = T / "outside" / "bin"; outside.mkdir(parents=True)
(outside / "orca-host").write_text((M / "bin" / "orca-host").read_text())
root = M.parent.parent
(Path(os.environ["REGATTA_CONFIG"]) / "home").write_text(f"﻿\n  {root}  \n")
try:
    copy = load("orca_host_copy", outside / "orca-host")
    check(copy.core_hooks() == str(root / "modules" / "regatta" / "hooks"),
          "a copy outside the checkout finds the core by a home file with a BOM and a blank first line")
except SystemExit:
    check(False, "a copy outside the checkout finds the core by a home file with a BOM and a blank first line")
(Path(os.environ["REGATTA_CONFIG"]) / "home").unlink()

# ---- peers, from the config dir
cfg = Path(os.environ["REGATTA_CONFIG"])
check(oh.peers_of("laptop") == [] and oh.ssh_alias("studio") is None,
      "no config, no overlay: no Mac pairs, no peer is reachable")
(cfg / "wharf-runs").mkdir()
(cfg / "wharf-runs" / "orca-pairs").write_text("Laptop:Studio\n\n")
(cfg / "wharf-runs" / "ssh").write_text("﻿studio:Studio-Agent\n")
check(oh.peers_of("laptop") == ["studio"] and oh.peers_of("studio") == [],
      "the pairs go one way: the laptop holds the studio's Orca, the studio holds none; names lower-cased")
check(oh.ssh_alias("studio") == "Studio-Agent", "the ssh alias per peer as written, a BOM and blank lines ignored")

# ---- check and setup print their whole report when a peer tool or a key is missing
import contextlib, io
def run(argv):
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        rc = oh.main(argv)
    return rc, out.getvalue()
def no_scopes(rt):
    raise oh.OrcaError("no `scopes` tool found")
oh.runtime_up, oh.scope_steps, oh.relay_signed_in = (lambda: True), no_scopes, (lambda: True)
oh.common.host_name = lambda: "laptop"   # this Mac's own name would expect no pairing
oh.cli = lambda *a, **k: {"environments": [{"name": "studio"}]}
rc, out = run(["check"])
check(rc == 1 and "✗ scopes: no `scopes` tool found" in out and "paired with studio" in out,
      "check: no scopes tool is a fault line, and the pairings still print")
(cfg / "Orca.app").mkdir(); oh.ORCA_APP = cfg / "Orca.app"
fake = cfg / "bin"; fake.mkdir(); (fake / "orca").write_text("#!/bin/sh\n"); (fake / "orca").chmod(0o755)
oh.orca_env = lambda: {"PATH": str(fake)}
# lighthouse sits beside this module in the checkout and holds `account`: hidden for this case
real_tool = oh.common.tool; oh.common.tool = lambda n: None if n == "account" else real_tool(n)
rc, out = run(["setup"])
oh.common.tool = real_tool
check(rc == 1 and "orca-sync skipped" in out and "orca-host check:" in out,
      "setup without the account tool, scopes failing: the sync skipped, and check still runs")
(cfg / "legacy").write_text("/nowhere\n")
(cfg / "wharf-runs" / "ssh").unlink()
try:
    oh.ssh_alias("studio")
    check(False, "with an overlay, a missing key raises")
except oh.OrcaError as e:
    check("wharf-runs/ssh missing" in str(e), "with an overlay installed, a missing key is an error naming it")
check(oh.main(["--on", "Studio", "check"]) == 2, "  and --on says so in one line, exit 2, no ssh")
(cfg / "wharf-runs" / "orca-pairs").unlink()
rc, out = run(["check"])
check(rc == 1 and "✗ pairs:" in out and "orca-pairs missing" in out and "orca-host check:" in out,
      "  and check names the missing pairs as a fault, the rest of its report kept")
check("environment rm" not in out, "  and, PAIRS unknown, no working pairing is called unwanted")
sys.exit(1 if fails else 0)
EOF
rc=$?
[ $rc -eq 0 ] && echo "orca-host: all passed" || echo "orca-host: FAILED"
exit $rc
