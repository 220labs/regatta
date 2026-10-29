#!/usr/bin/env bash
# Tests for bin/scopes: the registry's faults (a repo in no scope or two, an unknown key, a twin
# as anchor, two scopes on one file, a scope only a glob fills), globs, the folder order (the
# anchor first, twins last, layer always), `write` (paths relative to the file, a folder missing
# here left out, the worktree folders VS Code added kept, undeclared settings dropped, other keys
# kept, a retired file moved aside and a tracked one only named), `of`/`anchor` from a worktree
# path, and `check` on this checkout's own repos.json — the part that fails when a repo is added
# to the registry without a scope.
#   bash modules/wharf/tests/test_scopes.sh
set -u
B="$(cd "$(dirname "$0")/../bin" && pwd)"   # the module's bin/ (B6)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fails=0

python3 - "$B" "$T" <<'EOF' || fails=$((fails+1))
import importlib.machinery, importlib.util, json, os, subprocess, sys
from pathlib import Path
B, T = Path(sys.argv[1]), Path(sys.argv[2])
loader = importlib.machinery.SourceFileLoader("scopes", str(B / "scopes"))
s = importlib.util.module_from_spec(importlib.util.spec_from_loader("scopes", loader))
loader.exec_module(s)
s.LAYER = "layer"  # the registry's own repo, as LAYER reads it from where the file sits

fails = 0
def check(cond, label):
    global fails
    print(("  ok   " if cond else "  FAIL ") + label)
    fails += not cond

repos = {"layer": {}, "a": {}, "b": {}, "c/x": {}, "c/zig-1": {}, "oss/a": {"twin_of": "a"}}
good = {"coding": {"file": "coding.code-workspace", "repos": ["layer"]},
        "work": {"file": "work.code-workspace", "repos": ["a", "b", "oss/a"]},
        "other": {"file": "c/other.code-workspace", "repos": ["c/x", "*zig*"], "settings": {"k": 1}}}
check(s.faults(repos, good) == [], "every repo in one scope, a glob included: no fault")
check(s.members(good["other"], repos) == ["c/x", "c/zig-1"], "a glob adds the keys it matches, after the named ones")
check(s.members({"repos": ["*nothing*", "a"]}, repos) == ["a"], "a glob matching nothing adds nothing")
f = s.faults(repos, {k: v for k, v in good.items() if k != "other"})
check(any("c/x is in no scope" in x for x in f), "a repo in no scope is named")
f = s.faults(repos, {**good, "dup": {"file": "d.code-workspace", "repos": ["a"]}})
check(any("a is in two scopes" in x for x in f), "a repo in two scopes is named")
f = s.faults(repos, {**good, "dup": {"file": "d.code-workspace", "repos": ["x", "*zig*"]}})
check(any("c/zig-1 is in two scopes" in x for x in f), "…also when a glob puts it there")
f = s.faults(repos, {**good, "ghost": {"file": "g.code-workspace", "repos": ["nope"]}})
check(any("names nope" in x for x in f), "a key the registry lacks is named")
f = s.faults(repos, {**good, "work": {"file": "work.code-workspace", "repos": ["oss/a", "a", "b"]}})
check(any("anchor oss/a is a twin" in x for x in f), "a twin as a scope's anchor is refused")
f = s.faults(repos, {**good, "work": {"file": "coding.code-workspace", "repos": ["a", "b", "oss/a"]}})
check(any("would both write coding.code-workspace" in x for x in f), "two scopes on one file are named")
f = s.faults(repos, {**good, "globs": {"file": "z.code-workspace", "repos": ["*q*"]}})
check(any("must name its anchor outright" in x for x in f), "a scope only a glob fills has no anchor: refused")
f = s.faults(repos, {**good, "other": {"file": "c/other.code-workspace", "repos": ["*zig*", "c/x"]}})
check(any("scope other's first entry must name its anchor outright" in x for x in f),
      "a scope whose first entry is a glob is refused, though it names a repo later")
f = s.faults(repos, {**good, "work": {**good["work"], "settings": {"git.branchProtection": ["x"]}}})
check(any("declares git.branchProtection, which hooks/sync.py owns" in x for x in f),
      "declaring git.branchProtection is refused: hooks/sync.py owns it")
f = s.faults(repos, {**good, "nofile": {"repos": ["q"]}})
check(any("scope nofile has no file" in x for x in f), "a scope with no file is named")

check(s.folders(good["work"], repos) == ["a", "b", "oss/a", "layer"], "the anchor first, the twin last, then the layer")
check(s.folders(good["coding"], repos) == ["layer"], "atlas-like: the layer listed once")

check(s.load_jsonc('{"a": "http://x//y", /* c */ "b": [1, 2,], // t\n}') == {"a": "http://x//y", "b": [1, 2]},
      "load_jsonc: comments and trailing commas go, a // inside a string stays")

# a fixture ~/projects: layer, a, b, c/x (no c/zig-1 on this Mac), a worktree of a
P = T / "projects"
for d in ("layer", "a", "b", "c/x", "oss/a"):
    (P / d).mkdir(parents=True)
    subprocess.run(["git", "-C", str(P / d), "init", "-q", "-b", "main"], check=True)
    subprocess.run(["git", "-C", str(P / d), "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q",
                    "--allow-empty", "-m", "init"], check=True)
subprocess.run(["git", "-C", str(P / "a"), "worktree", "add", "-q", str(P / "a/.claude/worktrees/t"), "-b", "t"], check=True)
check(s.resolve(str(P / "a/.claude/worktrees/t"), repos, P) == "a", "a worktree path resolves to its repo")
check(s.resolve(str(P / "c/x"), repos, P) == "c/x", "a nested repo path resolves to its key")
check(s.resolve(str(T), repos, P) is None, "a path in no repo resolves to nothing")

none = s.Opened()  # nothing open: the fixture never asks the live VS Code
# the file there now: VS Code added two worktree folders (one gone since), the owner a setting, a launch key
(P / "c").mkdir(exist_ok=True)
(P / "c/other.code-workspace").write_text(json.dumps({
    "folders": [{"path": "x"}, {"path": "x/.claude/worktrees/gone"}, {"path": "../a/.claude/worktrees/t"}],
    "settings": {"undeclared": True}, "launch": {"v": 1}}))
names = {"layer": "layer (Atlas)"}
out = s.write(repos, good, names, P, False, opened=none)
body = s.load_jsonc((P / "c/other.code-workspace").read_text())
check([f["path"] for f in body["folders"]] == ["x", "../a/.claude/worktrees/t", "../layer"],
      "write: paths relative to the file, the live worktree folder kept right after the anchor (the home repo's"
      " script's order), the gone one dropped, layer last")
check(any("c/zig-1 is not on this Mac" in l for l in out), "…a repo not cloned here left out, with a note")
check(body["folders"][2]["name"] == "layer (Atlas)", "…folder_names give the display name")
check(body["settings"] == {"k": 1}, "…settings exactly as declared: an undeclared one dropped")
check(body["launch"] == {"v": 1}, "…another top-level key kept")
check(json.loads((P / "work.code-workspace").read_text())["folders"][0]["path"] == "a",
      "…plain JSON, no comment: the home repo's script and sync.py parse it strictly")
check([f["name"] for f in json.loads((P / "work.code-workspace").read_text())["folders"]] == ["a", "b", "oss/a", "layer (Atlas)"],
      "…a twin is named by its full key, never a second 'a'")
again = s.write(repos, good, names, P, False, opened=none)
check(again and all("is not on this Mac" in l for l in again), "a second write changes nothing (only the notes again)")
before = (P / "work.code-workspace").read_text()
(P / "work.code-workspace").write_text("{}")
check(any("would write work" in l for l in s.write(repos, good, names, P, True, opened=none)) and
      (P / "work.code-workspace").read_text() == "{}", "--dry-run says, writes nothing")

(P / "work.code-workspace").write_text(before)

# the other writers' marks survive: sync.py's lock list kept, another tool's formatting no rewrite
d = json.loads(before)
d["settings"]["git.branchProtection"] = ["claude/x"]
(P / "work.code-workspace").write_text(json.dumps(d))  # compact, ASCII-escaped: the home repo's script's way
out = s.write(repos, good, names, P, False, opened=none)
check(not any("work.code-workspace" in l and "wrote" in l for l in out),
      "content unchanged in another format: not rewritten")
d["settings"]["stray"] = 1
(P / "work.code-workspace").write_text(json.dumps(d))
s.write(repos, good, names, P, False, opened=none)
check(json.loads((P / "work.code-workspace").read_text())["settings"] == {"git.branchProtection": ["claude/x"]},
      "a rewrite drops an undeclared setting and keeps sync.py's git.branchProtection")

# a scope file whose folder is not on this Mac: a note, no traceback, the rest still written
gone = {**good, "far": {"file": "nowhere/far.code-workspace", "repos": ["zz"]}}
out = s.write({**repos, "zz": {}}, gone, names, P, False, opened=none)
check(any("nowhere/far.code-workspace" in l and "no file written" in l for l in out), "a missing folder for the file: noted, skipped")

# anchor: the file's own first folder when it exists, else the first declared repo on this Mac
check(s.anchor_of(good["work"], repos, P) == Path(os.path.realpath(P / "a")), "anchor: the file's first folder")
(P / "c/other.code-workspace").write_text(json.dumps({"folders": [{"path": "../b"}]}))
check(s.anchor_of(good["other"], repos, P) == Path(os.path.realpath(P / "b")),
      "…a file left with another first folder (a refused write) says what the window has")
check(s.anchor_of({"file": "none.code-workspace", "repos": ["zz", "a"]}, {**repos, "zz": {}}, P) == P / "a",
      "…no file: the first declared repo that is on this Mac")

# retired: an untracked file moves aside; one tracked in git is only named
(P / "old.code-workspace").write_text("{}")
(P / "a/a.code-workspace").write_text("{}")
subprocess.run(["git", "-C", str(P / "a"), "add", "a.code-workspace"], check=True)
out = s.write(repos, good, names, P, False, ["old.code-workspace", "a/a.code-workspace", "never.code-workspace"], none)
check(not (P / "old.code-workspace").exists() and any(P.glob(".scopes-retired/*/old.code-workspace")),
      "a retired file moves into .scopes-retired/<date>/")
check((P / "a/a.code-workspace").exists() and any("tracked in git" in l for l in out),
      "a retired file tracked in git stays, named")

# a file a VS Code window has open is never moved, nor rewritten with a new first folder (2026-10-15:
# moving the open regatta.code-workspace crashed its window's extension host and nine sessions)
STATUS = ("    0\t 10\t 1106\twindow [1] (Orca stat… — atlas (Workspace) — claude-x)\n"
          "    0\t 10\t 1107\twindow [2] (venture (Workspace) — claude-x)\n"
          "    0\t 10\t 1108\twindow [3] (notes.md — writing — claude-x)\n")
STORE = {"windowsState": {"lastActiveWindow": {"workspaceIdentifier": {"configURIPath": "file://" + str(P / "my%20old.code-workspace")}},
                          "openedWindows": [{"folder": "file:///x"}]}}
o = s.Opened(STATUS, STORE)
check(o.names == {"atlas", "venture"}, "code --status: a window's workspace by its title; a folder window is none")
check(bool(o.holds(P / "my old.code-workspace")) and bool(o.holds(P / "c/venture.code-workspace"))
      and not o.holds(P / "writing.code-workspace"),
      "open by storage.json's path (URI-decoded) or by a window title; anything else is not")
check(bool(s.Opened(None, None, running=True).holds(P / "x.code-workspace")),
      "VS Code running, neither readable: every file counts as open")
check(bool(s.Opened(None, STORE, running=True).holds(P / "x.code-workspace")),
      "VS Code running, `code --status` unreadable, storage.json read: still blind (a snapshot misses new windows)")
check(not s.Opened(None, None, running=False).holds(P / "x.code-workspace"), "VS Code not running: nothing is open")

(P / "my old.code-workspace").write_text("{}")
out = s.write(repos, good, names, P, False, ["my old.code-workspace"], o)
check((P / "my old.code-workspace").exists() and any("not retired" in l and "crash" in l for l in out),
      "an open retired file stays where it is, refused with the reason")
(P / "old2.code-workspace").write_text("{}")
check(any("would move" in l for l in s.write(repos, good, names, P, True, ["old2.code-workspace"], none)),
      "…a closed one still moves")

# rewrites of an open file: first folder unchanged is fine (windows 1 and 3 survived); changed is refused
held = s.Opened(None, {"windowsState": {"openedWindows": [
    {"workspaceIdentifier": {"configURIPath": "file://" + str(P / "work.code-workspace")}}]}})
(P / "work.code-workspace").write_text(json.dumps({"folders": [{"path": "a"}], "settings": {"old": 1}}))
out = s.write(repos, good, names, P, False, (), held)
check("wrote work.code-workspace" in out and '"old"' not in (P / "work.code-workspace").read_text(),
      "an open file whose first folder stays is rewritten")
(P / "work.code-workspace").write_text(json.dumps({"folders": [{"path": "b"}, {"path": "a"}]}))
(P / "coding.code-workspace").unlink()
out = s.write(repos, good, names, P, False, (), held)
check(any("work.code-workspace not written: its first folder would change" in l for l in out)
      and json.loads((P / "work.code-workspace").read_text())["folders"][0]["path"] == "b",
      "an open file whose first folder would change is left as it is, refused")
check("wrote coding.code-workspace" in out, "…the other scopes still go")

# confidential (knowledge-layers D3): the flag's type, the login's, and a flagged anchor's memory/
f = s.faults(repos, {**good, "work": {**good["work"], "confidential": "yes", "login": ""}})
check(any("work's confidential is 'yes', not true or false" in x for x in f)
      and any("work's login is '', not an account label" in x for x in f), "a flag that is no bool, a login that is no label: named")
flagged = {**good, "work": {**good["work"], "confidential": True, "login": "w"}}
check(s.faults(repos, flagged) == [], "a scope flagged true with a login: no fault in the list itself")
bad, notes = s.confidential_faults(repos, flagged, P)
check(len(bad) == 1 and "confidential scope work's anchor a has no memory/" in bad[0],
      "a confidential scope whose anchor is here without memory/ fails")
(P / "a/memory").mkdir()
check(s.confidential_faults(repos, flagged, P) == ([], []), "…with memory/ it passes")
bad, notes = s.confidential_faults({**repos, "zz": {}}, {"far": {"file": "f.code-workspace", "repos": ["zz"], "confidential": True}}, P)
check(bad == [] and any("anchor zz is not on this Mac" in n for n in notes), "…an anchor not cloned here is a note, not a fault")
check(s.confidential_faults(repos, good, P) == ([], []), "an open scope's anchor needs no memory/")

# set: one scope's object edited in the text, the layout kept, proved by parsing back
TEXT = ('{\n  "repos": {"a": {}, "b": {}},\n  "scopes": {\n'
        '    "one": {"file": "one.code-workspace", "repos": ["a"]},\n'
        '    "two": {\n      "file": "two.code-workspace",\n      "repos": ["b"],\n      "settings": {"k": 1}\n    }\n'
        '  },\n  "tail": [1,\n           2]\n}\n')
t1 = s.set_key(TEXT, "one", "confidential", True)
check('"one": {"confidential": true, "file"' not in t1 and '"repos": ["a"], "confidential": true}' in t1
      and t1.count("\n") == TEXT.count("\n"), "set on a one-line object: the pair at its end, one line still")
BRACE = '{"scopes": {"two": {"file": "x",\n          "repos": ["b"]\n  }}}\n'
check(s.set_key(s.set_key(BRACE, "two", "confidential", True), "two", "confidential", None) == BRACE,
      "set then unset on an object whose first key sits on its brace line: byte for byte")
t2 = s.set_key(s.set_key(TEXT, "two", "confidential", True), "two", "login", "w")
check('\n      "login": "w",\n      "confidential": true,\n      "file"' in t2, "…on a multi-line object: a line each, at its keys' indent")
check(json.loads(t2)["scopes"]["two"] == {"login": "w", "confidential": True, "file": "two.code-workspace",
                                         "repos": ["b"], "settings": {"k": 1}}, "…and parses to exactly that")
check(s.set_key(s.set_key(t1, "one", "confidential", None), "one", "login", None) == TEXT
      and s.set_key(s.set_key(t2, "two", "login", None), "two", "confidential", None) == TEXT,
      "--open and --no-login take the pairs out again: the text byte for byte")
check(s.set_key(t1, "one", "confidential", False) != t1 and json.loads(s.set_key(t1, "one", "confidential", False))["scopes"]["one"]["confidential"] is False,
      "a value already there is replaced in place")
try:
    s.set_key(TEXT, "nope", "confidential", True)
    check(False, "an unknown scope is refused")
except ValueError as e:
    check("no scope nope" in str(e), "an unknown scope is refused")
R = T / "reg.json"
R.write_text(TEXT)
out = s.set_flags(R, "one", True, "w")
check(out[0].startswith("wrote") and "[x] one — login w" in out[0], "set_flags: writes and says what it now is")
check(s.set_flags(R, "one", True, "w")[0].endswith("unchanged"), "…a second time: unchanged")
s.set_flags(R, "one", False, drop_login=True)
check(R.read_text() == TEXT, "…--open --no-login: the file as it was")
check(s.set_flags(R, "one", True, dry=True)[0].startswith("would write") and R.read_text() == TEXT, "…--dry-run writes nothing")

# the yard (skipper-resilience S2): its type, a confidential scope's yard on its anchor's host, and
# set --yard alone, the other keys kept; `none` written as null, never the pair removed
f = s.faults(repos, {**good, "work": {**good["work"], "yard": 5}, "other": {**good["other"], "yard": None}})
check(any("work's yard is 5, not a host or null" in x for x in f) and not any("other's yard" in x for x in f),
      "a yard that is no host is named; null is no yard, and no fault")
hosted = {**repos, "a": {"hosts": ["laptop", "studio"]}}
check(s.faults(hosted, {**good, "work": {**good["work"], "confidential": True, "yard": "studio"}}) == [],
      "a confidential scope whose yard is a host its anchor is on: no fault")
f = s.faults(hosted, {**good, "work": {**good["work"], "confidential": True, "yard": "far"}})
check(any("confidential scope work's yard far is not a host its anchor a is on (a's hosts: laptop, studio)" in x for x in f),
      "…a yard its anchor is not on: named, with the anchor's hosts")
f = s.faults(repos, {**good, "work": {**good["work"], "confidential": True, "yard": "studio"}})
check(any("anchor a is on (a's hosts: none listed)" in x for x in f), "…an anchor with no hosts listed holds no yard")
check(s.faults(hosted, {**good, "work": {**good["work"], "yard": "far"}}) == [], "an open scope's yard is not held to its anchor's hosts")
t3 = s.set_key(TEXT, "one", "yard", s.NULL)
check(json.loads(t3)["scopes"]["one"] == {"file": "one.code-workspace", "repos": ["a"], "yard": None} and '"yard": null' in t3,
      "set_key with NULL writes a null, the pair kept")
check(s.set_key(s.set_key(t3, "one", "yard", "studio"), "one", "yard", None) == TEXT, "…replaced by a host, then removed: byte for byte")
R.write_text(TEXT)
s.set_flags(R, "one", True, "w")
out = s.set_flags(R, "one", yard="studio")
d = json.loads(R.read_text())["scopes"]["one"]
check(d.get("yard") == "studio" and d.get("confidential") is True and d.get("login") == "w" and "— yard studio" in out[0],
      "set_flags --yard alone: the key written, the flag and the login kept, the yard said")
s.set_flags(R, "one", yard="none")
check(json.loads(R.read_text())["scopes"]["one"]["yard"] is None and s.set_flags(R, "one", yard="none")[0].endswith("— yard none — unchanged"),
      "…--yard none: written as null, said as none")
s.set_flags(R, "one", False, drop_login=True)
check(json.loads(R.read_text())["scopes"]["one"] == {"file": "one.code-workspace", "repos": ["a"], "yard": None},
      "…--open --no-login leave the yard as it is")
R.write_text(TEXT)

# configure: the checklist through set_flags
answers = iter(["2", "1 w", ""])
out = s.configure(R, ask=lambda _: next(answers), show=lambda _: None)
d = json.loads(R.read_text())["scopes"]
check(d["two"].get("confidential") is True and d["one"].get("login") == "w" and "confidential" not in d["one"],
      "configure: a number toggles a scope, `N LABEL` sets its login, a blank line saves")
answers = iter(["1", "q"])
before = R.read_text()
check(s.configure(R, ask=lambda _: next(answers), show=lambda _: None) == ["nothing written"] and R.read_text() == before, "…q leaves the file alone")
sys.exit(1 if fails else 0)
EOF

# the CLI on a fixture registry: check fails a flagged scope whose anchor has no memory/, and
# `set <a scope> --confidential` round-trips a copy of this Mac's registry byte for byte
F="$T/cli"; mkdir -p "$F/cfg/regatta" "$F/projects/know"
echo "$F/projects" > "$F/cfg/regatta/projects"
printf '{"repos": {"know": {}, "layer": {}},\n "scopes": {"sec": {"file": "s.code-workspace", "repos": ["know"]},\n  "atlas": {"file": "a.code-workspace", "repos": ["layer"]}}}\n' > "$F/repos.json"
SC() { REGATTA_CONFIG="$F/cfg" CLAUDE_REPOS_JSON="$F/repos.json" python3 "$B/scopes" "$@"; }
out=$(SC set sec --confidential --login lab 2>&1); [ $? -eq 0 ] && echo "  ok   scopes set sec --confidential --login lab" || { echo "  FAIL scopes set: $out"; fails=$((fails+1)); }
out=$(SC check 2>&1); rc=$?
if [ $rc -eq 1 ] && printf '%s' "$out" | grep -q "confidential scope sec's anchor know has no memory/"; then echo "  ok   scopes check: a flagged scope's anchor without memory/ → exit 1, named"
else echo "  FAIL scopes check should fail on know's missing memory/ (rc $rc): $out"; fails=$((fails+1)); fi
mkdir "$F/projects/know/memory"
out=$(SC check 2>&1); rc=$?
if [ $rc -eq 0 ] && printf '%s' "$out" | grep -q "confidential: sec (lab)"; then echo "  ok   …with memory/ → exit 0, the flag and login named"
else echo "  FAIL scopes check with memory/ (rc $rc): $out"; fails=$((fails+1)); fi
SC list | grep -q '^sec \[confidential, login lab\]' && echo "  ok   scopes lists the flag" || { echo "  FAIL scopes list"; fails=$((fails+1)); }
cp "$F/repos.json" "$F/before.json"
SC set sec --confidental >/dev/null 2>&1; rc1=$?; SC set sec --confidential --login --no-login >/dev/null 2>&1; rc2=$?; SC set sec >/dev/null 2>&1; rc3=$?
if [ "$rc1 $rc2 $rc3" = "2 2 2" ] && cmp -s "$F/repos.json" "$F/before.json"; then echo "  ok   scopes set: a misspelt flag, a flag as the login, no change asked → exit 2, nothing written"
else echo "  FAIL scopes set argument checks (rc $rc1 $rc2 $rc3)"; fails=$((fails+1)); fi
# --yard (skipper-resilience S2): a host lighthouse/hosts lists, or none; alone it keeps the flag
mkdir -p "$F/cfg/lighthouse"; printf 'laptop\nstudio\n' > "$F/cfg/lighthouse/hosts"
out=$(SC set sec --yard nowhere 2>&1); rc=$?
if [ $rc -eq 1 ] && printf '%s' "$out" | grep -q "nowhere is not a host .*lighthouse/hosts lists (laptop, studio)" && cmp -s "$F/repos.json" "$F/before.json"; then
  echo "  ok   scopes set --yard: a host lighthouse/hosts does not list → exit 1, named, nothing written"
else echo "  FAIL scopes set --yard nowhere (rc $rc): $out"; fails=$((fails+1)); fi
SC set sec --yard >/dev/null 2>&1; rc1=$?; SC set sec --yard --open >/dev/null 2>&1; rc2=$?
if [ "$rc1 $rc2" = "2 2" ] && cmp -s "$F/repos.json" "$F/before.json"; then echo "  ok   …--yard with no host, or a flag as its host → exit 2, nothing written"
else echo "  FAIL scopes set --yard argument checks (rc $rc1 $rc2)"; fails=$((fails+1)); fi
out=$(SC set sec --yard studio 2>&1); rc=$?
if [ $rc -eq 0 ] && python3 -c "import json,sys; s=json.load(open(sys.argv[1]))['scopes']['sec']; sys.exit(0 if s.get('yard')=='studio' and s.get('confidential') is True and s.get('login')=='lab' else 1)" "$F/repos.json"; then
  echo "  ok   scopes set sec --yard studio alone: the yard written, the flag and the login kept"
else echo "  FAIL scopes set --yard studio (rc $rc): $out"; fails=$((fails+1)); fi
out=$(SC check 2>&1); rc=$?
if [ $rc -eq 1 ] && printf '%s' "$out" | grep -q "confidential scope sec's yard studio is not a host its anchor know is on"; then
  echo "  ok   scopes check: a confidential scope's yard its anchor is not on → exit 1, named"
else echo "  FAIL scopes check on a confidential yard off its anchor (rc $rc): $out"; fails=$((fails+1)); fi
out=$(SC set sec --yard none 2>&1); rc=$?
if [ $rc -eq 0 ] && python3 -c "import json,sys; s=json.load(open(sys.argv[1]))['scopes']['sec']; sys.exit(0 if 'yard' in s and s['yard'] is None else 1)" "$F/repos.json" \
   && SC check >/dev/null 2>&1; then echo "  ok   …--yard none: null written, and the check passes again"
else echo "  FAIL scopes set --yard none (rc $rc): $out"; fails=$((fails+1)); fi
cp "$F/before.json" "$F/repos.json"
G="$T/gitreg"; git init -q -b main "$G"; cp "$F/before.json" "$G/repos.json"
git -C "$G" add repos.json; git -C "$G" -c user.email=t@t -c user.name=t commit -q -m r
git -C "$G" worktree add -q "$T/gitreg-wt" -b claude/x
out=$(REGATTA_CONFIG="$F/cfg" CLAUDE_REPOS_JSON="$G/repos.json" python3 "$B/scopes" set sec --open 2>&1); rc=$?
if [ $rc -eq 1 ] && printf '%s' "$out" | grep -q "primary checkout" && git -C "$G" diff --quiet; then echo "  ok   scopes set on a primary checkout on main → exit 1, the file untouched"
else echo "  FAIL scopes set should refuse a primary main (rc $rc): $out"; fails=$((fails+1)); fi
REGATTA_CONFIG="$F/cfg" CLAUDE_REPOS_JSON="$T/gitreg-wt/repos.json" python3 "$B/scopes" set sec --open >/dev/null 2>&1 \
  && ! git -C "$T/gitreg-wt" diff --quiet && echo "  ok   …a claude/* worktree's copy is written" \
  || { echo "  FAIL scopes set on a worktree copy"; fails=$((fails+1)); }
# scopes bridge (confidential-reach S8): open, the refusals, --revoke, audit, concern — on a fixture
# config dir, with CLAUDE_UNATTENDED unset but where a case sets it (a dispatched run carries it)
BR="$T/br"; mkdir -p "$BR/cfg/regatta" "$BR/projects"; echo "$BR/projects" > "$BR/cfg/regatta/projects"
for r in ka kb kc ko; do git init -q -b main "$BR/projects/$r"; done
git -C "$BR/projects/ka" remote add origin https://github.com/acct-x/ka.git
printf '{"repos": {"ka": {}, "kb": {}, "kc": {}, "ko": {}},\n "scopes": {"A": {"file": "a", "repos": ["ka"], "confidential": true},\n  "B": {"file": "b", "repos": ["kb"], "confidential": true},\n  "C": {"file": "c", "repos": ["kc"], "confidential": true},\n  "O": {"file": "o", "repos": ["ko"]}}}\n' > "$BR/repos.json"
BRF="$BR/cfg/lighthouse/bridges.json"
SB() { env -u CLAUDE_UNATTENDED -u WEEKLY_RUN -u AUTOFINISH_CALLER_UNATTENDED REGATTA_CONFIG="$BR/cfg" CLAUDE_REPOS_JSON="${SBREG:-$BR/repos.json}" python3 "$B/scopes" bridge "$@"; }
bcase() { if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3: expected [$2] got [$1]"; fails=$((fails+1)); fi; }
nb() { python3 -c "import json,sys; print(len(json.load(open(sys.argv[1]))['bridges']))" "$BRF" 2>/dev/null || echo 0; }
out=$(env CLAUDE_UNATTENDED=1 REGATTA_CONFIG="$BR/cfg" CLAUDE_REPOS_JSON="$BR/repos.json" python3 "$B/scopes" bridge open A B --until +2h --why x 2>&1); rc=$?
bcase "$rc $(nb) $(printf '%s' "$out" | grep -c 'unattended')" "2 0 1" "bridge open under CLAUDE_UNATTENDED: exit 2, nothing written (it stands for the owner's yes)"
SB open A O --until +2h --why x >/dev/null 2>&1; r1=$?; SB open A A --until +2h --why x >/dev/null 2>&1; r2=$?
SB open A B --until +25h --why x >/dev/null 2>&1; r3=$?; SB open A B --until +2h --why ' ' >/dev/null 2>&1; r4=$?
SB open A Z --until +2h --why x >/dev/null 2>&1; r5=$?; SB open A B --until tomorrow --why x >/dev/null 2>&1; r6=$?
bcase "$r1 $r2 $r3 $r4 $r5 $r6 $(nb)" "1 1 1 1 1 1 0" "  refused: an open scope, one scope twice, past 24 h, no why, a scope the registry lacks, no time"
out=$(SB open A B --until +4h --why "joint review" 2>&1); rc=$?
ID=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['bridges'][0]['id'])" "$BRF" 2>/dev/null)
bcase "$rc $(nb) $(printf '%s' "$out" | grep -c "opened bridge $ID: A ↔ B until")" "0 1 1" "bridge open A B: one entry written, said both ways"
bcase "$(python3 -c "import json,sys; e=json.load(open(sys.argv[1]))['bridges'][0]; print(e['from'], e['to'], e['why'], 'one_way' in e, sorted(e))" "$BRF")" \
  "A B joint review False ['by', 'from', 'id', 'opened', 'to', 'until', 'why']" "  the entry: from, to, until, why, by, opened, id"
SB open B C --until +2h --why x >/dev/null 2>&1; rc=$?
bcase "$rc $(nb)" "1 1" "  a second partner for B would chain: refused, nothing written"
SB open B A --until +1h --why again >/dev/null 2>&1; rc=$?
bcase "$rc $(nb)" "0 2" "  the same pair again is no chain (a longer or shorter window beside it)"
out=$(SB audit 2>&1); rc=$?
bcase "$rc $(printf '%s' "$out" | grep -c '^  open ')" "0 2" "bridge audit lists each open entry"
out=$(SB --revoke "$ID" 2>&1); rc=$?
bcase "$rc $(python3 -c "import json,sys; print([bool(e.get('ended')) for e in json.load(open(sys.argv[1]))['bridges']])" "$BRF")" "0 [True, False]" \
  "bridge --revoke ID: ended written on that entry alone, the history kept"
out=$(env CLAUDE_UNATTENDED=1 REGATTA_CONFIG="$BR/cfg" CLAUDE_REPOS_JSON="$BR/repos.json" python3 "$B/scopes" bridge --revoke A 2>&1); rc=$?
bcase "$rc $(SB audit 2>&1 | grep -c '^  ended ')" "0 2" "  --revoke SCOPE ends every open entry it is in, unattended too (ending narrows)"
python3 - "$BRF" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); e = dict(d["bridges"][0]); e.pop("ended"); e.pop("ended_why", None)
e.update(id="old", opened="2026-01-01T00:00:00Z", until="2026-01-01T02:00:00Z"); d["bridges"].append(e)
json.dump(d, open(sys.argv[1], "w"))
PY
out=$(SB audit 2>&1); rc=$?
bcase "$rc $(printf '%s' "$out" | grep -c 'old: A ↔ B.*ended 2026-01-01T02:00:00Z (expired)') $(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['bridges'][-1].get('ended_why'))" "$BRF")" "0 1 expired" \
  "bridge audit: an expired entry is named, and gets its ended (the clock ended it)"
bcase "$(SB audit --since 2026-06-01T00:00:00Z 2>&1 | grep -c 'old:')" "0" "  --since leaves out what opened before"
cp "$BRF" "$BRF.good"; printf '{"bridges": [' > "$BRF"
SB audit >/dev/null 2>&1; r1=$?; SB open A B --until +1h --why x >/dev/null 2>&1; r2=$?
bcase "$r1 $r2 $(cat "$BRF")" '1 1 {"bridges": [' "a torn file: audit exit 1, open refused — the history is never overwritten"
cp "$BRF.good" "$BRF"; SB open A B --until +1h --why x >/dev/null 2>&1
printf '#!/bin/sh\nprintf "%%s\\n" "$@" > "%s/gh-args"; echo https://github.com/acct-x/ka/issues/7\n' "$BR" > "$BR/gh"; chmod +x "$BR/gh"
out=$(cd "$BR/projects/ka" && SCOPES_GH="$BR/gh" SB concern 0123abcd-ffff --text "it read too much" 2>&1); rc=$?
bcase "$rc $(printf '%s' "$out" | grep -c 'issues/7') $(sed -n 4p "$BR/gh-args") $(grep -c 'with B' "$BR/gh-args") $(grep -c 'joint\|kb' "$BR/gh-args")" "0 1 acct-x/ka 1 0" \
  "bridge concern: an issue in the anchor's own repository naming the session and the other scope only"
out=$(cd "$BR/projects/ko" && SCOPES_GH="$BR/gh" SB concern 0123abcd --text x 2>&1); rc=$?
bcase "$rc" "1" "  from an open scope's checkout: refused"
# the S8 landing review's items 6-9
sed 's/"ko": {}}/"ko": {}, "kgone": {}}/; s/"repos": \["ka"\]/"repos": ["kgone", "ka"]/' "$BR/repos.json" > "$BR/repos-anchor.json"
out=$(cd "$BR/projects/ka" && SCOPES_GH="$BR/gh" SBREG="$BR/repos-anchor.json" SB concern 0123abcd --text x 2>&1); rc=$?
bcase "$rc $(sed -n 4p "$BR/gh-args")" "0 acct-x/ka" "  the issue goes to the scope's anchor as the other verbs read it (its first repo present here), not its first entry"
for v in WEEKLY_RUN AUTOFINISH_CALLER_UNATTENDED; do
  n0=$(nb); out=$(env -u CLAUDE_UNATTENDED -u WEEKLY_RUN -u AUTOFINISH_CALLER_UNATTENDED "$v=1" REGATTA_CONFIG="$BR/cfg" CLAUDE_REPOS_JSON="$BR/repos.json" python3 "$B/scopes" bridge open A B --until +1h --why x 2>&1); rc=$?
  bcase "$rc $(( $(nb) - n0 )) $(printf '%s' "$out" | grep -c "$v")" "2 0 1" "bridge open under $v: exit 2, nothing written (an unattended caller, as soundings reads one)"
done
bcase "$(SB audit --since 2026-06-01 2>&1 | grep -c 'old:') $(SB audit --since 2025-12-31 2>&1 | grep -c 'old:')" "0 1" "bridge audit --since takes a plain date (UTC midnight)"
SB audit --since yesterday >/dev/null 2>&1; bcase "$?" "2" "  and refuses what is no date, rather than list everything"
printf '{"repos": {' > "$BR/torn.json"
RID=$(python3 -c "import json,sys; print([e['id'] for e in json.load(open(sys.argv[1]))['bridges'] if not e.get('ended')][-1])" "$BRF")
out=$(SBREG="$BR/torn.json" SB --revoke "$RID" 2>&1); r1=$?
out2=$(SBREG="$BR/torn.json" SB open A B --until +1h --why x 2>&1); r2=$?
bcase "$r1 $r2 $(printf '%s' "$out$out2" | grep -c Traceback) $(printf '%s' "$out2" | grep -c 'registry does not read')" "0 1 0 1" \
  "a torn registry: --revoke still ends a bridge, open refuses in words — no traceback"
LIVE="${CLAUDE_REPOS_JSON:-${REGATTA_CONFIG:-$HOME/.config/regatta}/wharf/repos.json}"
# the registry's first scope, read back from the file, never named here
SCOPE=$( [ -f "$LIVE" ] && python3 -c "import json,sys; print(next(iter(json.load(open(sys.argv[1])).get('scopes') or {}), ''))" "$LIVE" 2>/dev/null)
if [ -n "$SCOPE" ]; then
  cp "$LIVE" "$F/live.json"
  L() { CLAUDE_REPOS_JSON="$F/live.json" python3 "$B/scopes" "$@" >/dev/null 2>&1; }
  L set "$SCOPE" --open --no-login && cp "$F/live.json" "$F/open.json" \
    && L set "$SCOPE" --confidential --login lab-x \
    && python3 -c "import json,sys; s=json.load(open(sys.argv[1]))['scopes'][sys.argv[2]]; sys.exit(0 if s['confidential'] is True and s['login']=='lab-x' else 1)" "$F/live.json" "$SCOPE" \
    && L set "$SCOPE" --open --no-login && cmp -s "$F/live.json" "$F/open.json" \
    && echo "  ok   scopes set <its first scope> --confidential round-trips a copy of this Mac's registry, byte for byte" \
    || { echo "  FAIL scopes set round-trip on a copy of the registry (its first scope)"; fails=$((fails+1)); }
else
  echo "  --   no registry with a scope here: the live round-trip skipped"
fi

# this Mac's registry (the core's repos_json(), C3): every repo in exactly one scope — skipped
# where there is none, as on a CI runner
if [ -z "${CLAUDE_REPOS_JSON:-}" ] && [ ! -e "${REGATTA_CONFIG:-$HOME/.config/regatta}/wharf/repos.json" ] \
   && [ ! -L "${REGATTA_CONFIG:-$HOME/.config/regatta}/wharf/repos.json" ]; then   # a dangling link fails below
  echo "  --   no registry here: the live scopes check skipped"
else
  out=$(python3 "$B/scopes" check 2>&1)
  if [ $? -eq 0 ]; then echo "  ok   $out"; else echo "  FAIL bin/scopes check on this Mac's registry:"; echo "$out" | sed 's/^/       /'; fails=$((fails+1)); fi
fi

[ $fails -eq 0 ] && echo "test_scopes: all ok" || { echo "test_scopes: $fails failing"; exit 1; }
