#!/usr/bin/env bash
# Tests for bin/orca-host: which repos each scope's Orca group holds on a Mac (anchor first, twins,
# other hosts' and missing checkouts left out, a knowledge repo kept in, short names unless they
# clash, the worktree base only on the workflow), the plan from what Orca holds (nothing once
# converged, each drifted field alone, extra repos and groups only noted, nestWorkspaces named), the
# runtime client against a fake socket (the answer matched by id past a keepalive, a refusal raised
# with its method), the pairing link's checks (not a link, a phone link, a link to the wrong Mac),
# the pairs and ssh aliases read from the config dir, a named node's folder carrying its own pairing
# and ssh (never a wharf-runs/ssh peer, never autofinish-run's landing peer, a torn folder an
# error); then the Linux peer side from a copy loaded as Linux (orca-ide only, ~/.config/orca, the
# guest's installer or the release .deb by apt, the systemd unit restarted, no clipboard, no
# Homebrew PATH on the peer). Host and repo names are made up. Scratch paths only; no Orca, no network.
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
oh.LINUX = False   # the cases up to the Linux block are the Mac's, wherever the suite runs (CI is ubuntu)

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
(cfg / "regatta").mkdir(exist_ok=True); (cfg / "regatta" / "overlay").write_text("/nowhere\n")
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

# ---- a named node's folder carries its pairing (the overlay installed, PEERS missing from here on)
nodes = cfg / "wharf-runs" / "nodes"
(nodes / "acme").mkdir(parents=True)
(nodes / "acme" / "orca-pair").write_text("laptop\n")
(nodes / "acme" / "ssh").write_text("acme-vps\n")
(nodes / "acme" / "scope").write_text("acme\n")
(nodes / "box").mkdir()
(nodes / "box" / "name").write_text("box7\n")
(nodes / ".DS_Store").write_text("")
(cfg / "wharf-runs" / "orca-pairs").write_text("laptop:studio\n")
check(oh.peers_of("laptop") == ["studio", "acme-agent"] and oh.peers_of("studio") == [],
      "a node folder's orca-pair: the laptop holds the node's guest, `<folder>-agent`, after PAIRS; the studio none")
check([n["peer"] for n in oh.node_peers()] == ["acme-agent", "box7-agent"],
      "  the peer is the guest's hostname from the folder's `name` when set, as written; a dot file is no node")
check(oh.reach("acme-agent")[0] == "acme-vps", "  --on's alias is the folder's own ssh, though PEERS is missing")
sent_on = []
class Ran:
    returncode, stdout, stderr = 0, "", ""
os.environ.pop("ORCA_HOST_SSH", None)
real_run = oh.subprocess.run
oh.subprocess.run = lambda argv, **kw: sent_on.append(argv) or Ran()
try:
    rc = oh.run_on("acme-agent", ["check"])
finally:
    oh.subprocess.run = real_run
check(rc == 0 and len(sent_on) == 2 and all(a[:4] == ["ssh", "-o", "ConnectTimeout=10", "acme-vps"] for a in sent_on),
      f"--on acme-agent: the copy and the run both go by the node's ssh alias (got {[a[:4] for a in sent_on]})")
rc, out = run(["--on", "box7-agent", "check"])
check(rc == 2 and str(nodes / "box" / "ssh") in out and "acme-agent" in out,
      "  a node with no ssh: exit 2 naming its folder's ssh key, PEERS missing or not")
oh.cli = lambda *a, **k: {"environments": [{"name": "studio"}, {"name": "acme-agent"}]}
rc, out = run(["check"])
check("paired with acme-agent" in out and "names: acme-agent" not in out and "is also named" not in out,
      "check: the node's pairing is expected, its environment never called unwanted")

# the fence: a node peer is in no wharf-runs/ssh reader, nor autofinish-run's landing peer
(cfg / "wharf-runs" / "ssh").write_text("studio:Studio-Agent\n")
check(not any("acme" in l for l in oh.common.config_lines("wharf-runs/ssh") or []) and oh.ssh_alias("studio") == "Studio-Agent",
      "  the node's pairing writes nothing to wharf-runs/ssh, which every ssh reader reads")
check(oh.ssh_alias("acme-agent") is None and oh.reach("acme-agent")[0] == "acme-vps",
      "  ssh_alias stays PEERS-only, so clock (which reads each peer's alias through it) never dials the node")
readers = sorted(p.relative_to(M.parent).as_posix() for d in ("bin", "lib", "libexec", "hooks")
                 for p in M.parent.glob(f"*/{d}/**/*") if p.is_file()
                 and "wharf-runs/nodes" in p.read_text(encoding="utf-8", errors="replace"))
check(sorted(set(readers) - {"wharf-runs/bin/yard-node"}) == ["wharf-runs/bin/orca-host"],   # yard-node: not on the twin
      f"  only orca-host and yard-node read a node folder: no dispatch, berth, pickup, helm or landing (got {readers})")
os.environ.pop("AUTOFINISH_ON", None)
os.environ["AUTOFINISH_HOST"] = "laptop"
afr = load("afr", M / "bin" / "autofinish-run")
check(afr.peer_of() == ("studio", "Studio-Agent", None), f"  autofinish-run lands on PAIRS' first row, never the node (got {afr.peer_of()})")
(cfg / "wharf-runs" / "orca-pairs").write_text("")
check(afr.peer_of() == (None, None, None) and oh.peers_of("laptop") == ["acme-agent"],
      "  and with the laptop's PAIRS row gone the node still pairs, yet no landing goes to it")
del os.environ["AUTOFINISH_HOST"]
(cfg / "wharf-runs" / "ssh").write_text("studio:Studio-Agent\nacme-agent:elsewhere\n")
rc, out = run(["check"])
check(rc == 1 and "✗ node acme-agent is also named in wharf-runs/ssh" in out, "a node peer PEERS also names is a fault")
check(oh.reach("acme-agent")[0] == "acme-vps", "  and --on still takes the node folder's ssh, never that row")
(cfg / "wharf-runs" / "ssh").write_text("studio:Studio-Agent\n")
(cfg / "wharf-runs" / "orca-pairs").write_text("laptop:studio\nlaptop:acme-agent\n")
(cfg / "wharf-runs" / "finish-on").write_text("laptop:acme-agent\n")
rc, out = run(["check"])
check(rc == 1 and "✗ node acme-agent is also named in wharf-runs/orca-pairs" in out and "landing peer" in out
      and "✗ node acme-agent is also named in wharf-runs/finish-on" in out,
      "a node peer an orca-pairs or finish-on row names is a fault: autofinish-run could land on it")
(cfg / "wharf-runs" / "finish-on").unlink(); (cfg / "wharf-runs" / "orca-pairs").write_text("")

# a node folder that does not read: an error naming it, as a missing key with an overlay
(nodes / "acme" / "orca-pair").write_bytes(b"\xff\xfe laptop\n")
try:
    oh.peers_of("laptop")
    check(False, "an unreadable orca-pair raises")
except oh.OrcaError as e:
    check(str(nodes / "acme" / "orca-pair") in str(e) and "not UTF-8" in str(e), "an orca-pair that is not UTF-8: an error naming it")
(nodes / "acme" / "orca-pair").write_text("laptop\n")
(nodes / "gone").symlink_to(T / "nowhere")
rc, out = run(["check"])
check(rc == 1 and "✗ pairs:" in out and str(nodes / "gone") in out and "environment rm" not in out
      and "orca-host check:" in out and out.count(str(nodes / "gone")) == 1,
      "a node folder whose link's target moved: one pairs fault naming it, nothing called unwanted, the report kept")
rc, out = run(["--on", "gone-agent", "check"])
check(rc == 2 and str(nodes / "gone") in out, "  and --on a peer that could be a node refuses in one line, exit 2")
check(oh.reach("studio")[0] == "Studio-Agent", "  while a Mac peer, which never ends -agent, is still reached")
(nodes / "gone").unlink()
(nodes / "acme" / "orca-pair").unlink(); (nodes / "acme" / "orca-pair").symlink_to(T / "nowhere")
try:
    oh.node_peers()
    check(False, "an orca-pair link whose target moved raises")
except oh.OrcaError as e:
    check(str(nodes / "acme" / "orca-pair") in str(e) and "target moved" in str(e),
          "an orca-pair that is a link whose target moved: an error naming it, never no pairing")
(nodes / "acme" / "orca-pair").unlink(); (nodes / "acme" / "orca-pair").write_text("laptop\n")
(nodes / "box" / "name").unlink(); (nodes / "box" / "name").symlink_to(T / "nowhere")
try:
    oh.node_peers()
    check(False, "a name link whose target moved raises")
except oh.OrcaError as e:
    check(str(nodes / "box" / "name") in str(e), "  and a moved `name` link too: never the peer renamed to the folder's")
(nodes / "box" / "name").unlink()
for line, why in (("laptop:acme-agent", "an orca-pairs row"), ("Laptop", "upper case"), ("laptop_7", "an underscore")):
    (nodes / "acme" / "orca-pair").write_text(line + "\n")
    try:
        oh.node_peers()
        check(False, f"an orca-pair line that is {why} raises")
    except oh.OrcaError as e:
        check(str(nodes / "acme" / "orca-pair") in str(e) and "bare host" in str(e),
              f"an orca-pair line that is {why}: an error naming it, never a node that pairs with no Mac")
(nodes / "acme" / "orca-pair").write_text("laptop\n")
(nodes / "acme-old").mkdir(); (nodes / "acme-old" / "name").write_text("acme\n")
try:
    oh.node_peers()
    check(False, "two folders giving one peer raise")
except oh.OrcaError as e:
    check(str(nodes / "acme") in str(e) and str(nodes / "acme-old") in str(e),
          "two folders that give the same peer: an error naming both, never one ssh taken silently")
(nodes / "acme-old" / "name").unlink(); (nodes / "acme-old").rmdir()
(nodes / "box" / "name").write_text("Box7\n")
try:
    oh.node_peers()
    check(False, "an upper-case name raises")
except oh.OrcaError as e:
    check("no hostname" in str(e), "a `name` in upper case: an error, as yard-node refuses to render it")
(nodes / "box" / "name").write_text("box_7\n")
try:
    oh.node_peers()
    check(False, "a node name that is no hostname raises")
except oh.OrcaError as e:
    check("no hostname" in str(e), "a node `name` that is no hostname: an error, not a peer Tailscale never names")
(nodes / "box" / "name").unlink()
for p in sorted(nodes.rglob("*"), reverse=True):
    p.unlink() if p.is_file() or p.is_symlink() else p.rmdir()
nodes.rmdir()
nodes.symlink_to(T / "nowhere")
try:
    oh.node_peers()
    check(False, "a nodes folder whose link's target moved raises")
except oh.OrcaError as e:
    check(str(nodes) in str(e), "the nodes folder itself a link whose target moved: unreadable, never no nodes")
nodes.unlink()
check(oh.node_peers() == [], "no nodes folder: no node, no error")
(cfg / "wharf-runs" / "ssh").unlink(); (cfg / "wharf-runs" / "orca-pairs").unlink()

# ---- the Linux peer side, from a copy loaded as Linux
os.environ["ORCA_HOST_PLATFORM"] = "linux"
lx = load("orca_host_linux", M / "bin" / "orca-host")
del os.environ["ORCA_HOST_PLATFORM"]
check(lx.LINUX is True, "ORCA_HOST_PLATFORM=linux: the copy takes the Linux branch")
os.environ.pop("XDG_CONFIG_HOME", None)
check(lx.default_data(True) == Path(os.environ["HOME"]) / ".config" / "orca"
      and lx.default_data(False) == Path(os.environ["HOME"]) / "Library/Application Support/orca",
      "the data dir: ~/.config/orca on Linux, Application Support on a Mac")
os.environ["XDG_CONFIG_HOME"] = str(T / "xdg")
check(lx.default_data(True) == T / "xdg" / "orca", "  and $XDG_CONFIG_HOME/orca when it is set")
del os.environ["XDG_CONFIG_HOME"]
lbin = T / "lbin"; lbin.mkdir()
for n in ("orca", "orca-ide"):
    (lbin / n).write_text("#!/bin/sh\n"); (lbin / n).chmod(0o755)
saved_path = os.environ["PATH"]
os.environ["PATH"] = f"{lbin}:{saved_path}"
check(lx.orca_bin() == str(lbin / "orca-ide"), "Linux: orca-ide, never the bare orca beside it (the screen reader, serve's shim)")
(lbin / "orca-ide").unlink()
check(lx.orca_bin() is None, "  and no orca-ide: no CLI, though an orca is on PATH")
os.environ["PATH"] = saved_path
check(not lx.orca_env()["PATH"].startswith("/opt/homebrew/bin:"), "Linux: no Homebrew put first on the CLI's PATH")
check(lx.clipboard() is None, "Linux: no clipboard to read")

units = Path(os.environ["HOME"]) / ".config" / "systemd" / "user"; units.mkdir(parents=True)
(units / "a-other.service").write_text("[Service]\nExecStart=/usr/bin/sleep 1\n")
check(lx.serve_agent() is None, "no unit runs Orca's server: none found")
(units / "orca-serve.service").write_text("[Service]\nExecStart=/usr/local/bin/orca-serve-node\nRestart=on-failure\n")
check(lx.serve_agent() == "orca-serve.service", "the guest's unit (ExecStart its orca-serve-node wrapper) is the server unit")

class Plat:
    def __init__(self, m): self.m = m
    def machine(self): return self.m
real_platform = lx.platform
lx.platform = Plat("x86_64")
check(lx.deb_arch_ok("orca-ide_1.4.237_amd64.deb") and not lx.deb_arch_ok("orca-ide_1.4.237_arm64.deb")
      and not lx.deb_arch_ok("Orca-1.4.237.AppImage"), "x86_64: the amd64 .deb, not the arm64 one, not an AppImage")
lx.platform = Plat("aarch64")
check(lx.deb_arch_ok("orca-ide_1.4.237_arm64.deb") and not lx.deb_arch_ok("orca-ide_1.4.237_amd64.deb"),
      "aarch64: the arm64 .deb")
lx.platform = real_platform

def lrun(argv):
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        rc = lx.main(argv)
    return rc, out.getvalue()
installer = T / "orca-ide-install"; installer.write_text("#!/bin/sh\n")
lx.DEB_INSTALLER = installer
lx.runtime_up = lambda: False
rc, out = lrun(["setup", "--dry-run"])
check(rc == 0 and f"sudo -n {installer}" in out and "systemctl --user restart orca-serve.service" in out,
      "setup --dry-run on Linux: the guest's installer, then a restart of its unit")
check("brew" not in out and "launchctl" not in out and "ln -sf" not in out and "/opt/homebrew" not in out,
      "  and no Homebrew, no launchctl, no CLI symlink")
lx.DEB_INSTALLER = T / "no-installer"
(cfg / "wharf-runs" / "node").mkdir(parents=True)
(cfg / "wharf-runs" / "node" / "orca-release").write_text("v9.9.9\n")
rc, out = lrun(["setup", "--dry-run"])
check("the v9.9.9 .deb" in out and "apt-get install" in out, "  no installer: the node's pinned release's .deb, by apt")
(cfg / "wharf-runs" / "node" / "orca-release").unlink()
rc, out = lrun(["setup", "--dry-run"])
check(f"the {lx.ORCA_RELEASE} .deb" in out, "  and no pin: yard-node's pinned default, not the latest")
(cfg / "wharf-runs" / "node" / "orca-release").write_text("v1;rm\n")
rc, out = lrun(["setup", "--dry-run"])
check(rc != 0 and "a release tag" in out, "  a release that is no tag: refused before any URL")
(cfg / "wharf-runs" / "node" / "orca-release").unlink()
(units / "orca-serve.service").unlink()
saved_disp = {k: os.environ.pop(k, None) for k in ("DISPLAY", "WAYLAND_DISPLAY")}
os.environ["ORCA_HOST_CLI"] = str(lbin / "orca")   # installed: this case is the server's, no install runs
rc, out = lrun(["setup"])
del os.environ["ORCA_HOST_CLI"]
check(rc == 1 and "orca-serve-agent here" in out and "orca open" not in out,
      "no server unit, no display: setup names orca-serve-agent, never `orca open`")
for k, v in saved_disp.items():
    if v is not None:
        os.environ[k] = v
(units / "orca-serve.service").write_text("[Service]\nExecStart=/usr/local/bin/orca-serve-node\n")

argvs, ups = [], iter([False, True])
class Ok:
    returncode, stdout, stderr = 0, "", ""
def lfake(argv, **kw):
    argvs.append(list(argv))
    return Ok()
real_lrun = lx.subprocess.run
lx.subprocess.run = lfake
lx.DEB_INSTALLER = installer
lx.runtime_up = lambda: next(ups, True)
lx.scope_steps = lambda rt: ([], [], [], [])
lx.cli = lambda *a, **k: {"environments": []}
real_tool = lx.common.tool; lx.common.tool = lambda n: None if n == "account" else real_tool(n)
rc, out = lrun(["setup"])
lx.common.tool = real_tool
check(argvs[:2] == [["sudo", "-n", str(installer)], ["systemctl", "--user", "restart", "orca-serve.service"]],
      f"setup on Linux runs the installer, then restarts the unit (got {argvs[:2]})")
argvs.clear()
lx.DEB_INSTALLER = T / "no-installer"
lx.deb_url = lambda release: "https://example.invalid/orca-ide_1_amd64.deb"
with contextlib.redirect_stdout(io.StringIO()):
    rc = lx.install_deb(False)
check(rc == 0 and argvs[0][:2] == ["curl", "-fsSL"] and argvs[1][:2] == ["sudo", "-n"]
      and argvs[1][-3:-1] == ["install", "-y"] and "/" in argvs[1][-1],
      "no installer: the .deb downloaded, then apt-get install by a path apt reads as a file")
lx.subprocess.run = real_lrun

lx.runtime_up = lambda: False
rc, out = lrun(["check"])
check(rc == 1 and "orca-ide is not installed" in out and "Orca.app" not in out and "brew" not in out,
      "check on Linux: orca-ide missing is one fault, naming no app bundle or cask")
pasted = []
lx.subprocess.run = lambda argv, **kw: pasted.append(argv[0]) or Ok()
lx.paired = lambda peer: None
lx.tailscale_addresses = lambda peer: set()
rc, out = lrun(["pair", "buildbox"])
check(rc == 1 and "--link -" in out and pasted == [], "pair on Linux without --link -: said, no pbpaste run")

(cfg / "wharf-runs" / "ssh").write_text("buildbox:buildbox-ssh\n")
sent_ssh = []
lx.subprocess.run = lambda argv, **kw: sent_ssh.append(argv) or Ok()
os.environ.pop("ORCA_HOST_SSH", None)
lx.run_on("buildbox", ["check"])
remote = sent_ssh[-1][-1]
check("[ ! -d /opt/homebrew/bin ]" in remote and not remote.startswith("PATH=/opt/homebrew/bin"),
      "--on: Homebrew's PATH only where the peer has it (a Linux peer has none)")
# the real run: lx.subprocess is the shared module, so its patched run would answer for sh too
lx.subprocess.run = real_lrun
check(real_lrun(["sh", "-n", "-c", remote]).returncode == 0, "  and the remote line parses as sh")
sys.exit(1 if fails else 0)
EOF
rc=$?
[ $rc -eq 0 ] && echo "orca-host: all passed" || echo "orca-host: FAILED"
exit $rc
