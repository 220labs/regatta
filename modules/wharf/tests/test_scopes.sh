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
live = s.opened_now
def asked():
    raise AssertionError("VS Code asked")
s.opened_now = asked
try:
    s.write(repos, good, names, P, False)
    check(True, "…and asks VS Code nothing: `code --status` only once a file would change")
except AssertionError:
    check(False, "…and asks VS Code nothing: `code --status` only once a file would change")
s.opened_now = live
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

# a write made while `code --status` ran (VS Code, sync.py's indicator) is never written over
d["settings"]["stray"] = 2
(P / "work.code-workspace").write_text(json.dumps(d))
theirs = json.dumps({**d, "settings": {**d["settings"], "git.branchProtection": ["claude/y"]}})
class Racing:
    def holds(self, p):
        p.write_text(theirs)
        return None
out = s.write(repos, good, names, P, False, opened=Racing())
check((P / "work.code-workspace").read_text() == theirs and any("changed while this run read it" in l for l in out),
      "a file written while VS Code was asked is left as the other writer wrote it, and said")

# the exclude line is a gitignore pattern: a name holding one of its specials is escaped and matches
E = T / "esc"
subprocess.run(["git", "init", "-q", "-b", "main", str(E)], check=True)
(E / "sec[1] *.code-workspace").write_text("{}")
line = s.exclude(E / "sec[1] *.code-workspace", False)
r = subprocess.run(["git", "-C", str(E), "status", "--porcelain"], capture_output=True, text=True)
check(line and line.startswith("excluded") and r.stdout == "",
      "exclude: `[`, `*` and a space escaped, so git ignores the very file")

# only: the scopes a session may write (write --from); the rest untouched
(P / "work.code-workspace").unlink()
(P / "coding.code-workspace").unlink()
out = s.write(repos, good, names, P, False, opened=none, only={"coding"})
check((P / "coding.code-workspace").exists() and not (P / "work.code-workspace").exists(),
      "only: the named scope written, another left alone")
s.write(repos, good, names, P, False, opened=none)

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
# a confidential scope's own node (scopes-node-yard, 2026-11-03): the core's scope_yard_hosts — its node folder
# here (`scope` and `ssh`), or this host as its node by its payload's clones; never another scope's node,
# never an open scope's; judged with the flag the same write leaves
cp "$F/repos.json" "$F/node-before.json"
yn() {   # yn LABEL WANT_RC GREP ARGS…: SC set ARGS, its rc, its output holding GREP, and the file untouched unless rc 0 and no --dry-run
  label=$1 want=$2 pat=$3; shift 3
  out=$(SC set "$@" 2>&1); rc=$?
  if [ "$rc" = "$want" ] && printf '%s' "$out" | grep -q -- "$pat" && { [ "$rc" = 0 ] || cmp -s "$F/repos.json" "$F/node-before.json"; }; then echo "  ok   $label"
  else echo "  FAIL $label (rc $rc): $out"; fails=$((fails+1)); fi
}
mkdir -p "$F/cfg/wharf-runs/nodes/sec"; echo sec > "$F/cfg/wharf-runs/nodes/sec/scope"; echo sec-agent > "$F/cfg/wharf-runs/nodes/sec/ssh"
yn "scopes set sec --yard sec-agent --dry-run: its own node folder → exit 0, the one line" 0 "^would write .*: \[x\] sec — login lab — yard sec-agent$" sec --yard sec-agent --dry-run
cmp -s "$F/repos.json" "$F/node-before.json" && echo "  ok   …--dry-run writes nothing" || { echo "  FAIL --dry-run wrote"; fails=$((fails+1)); }
yn "…an open scope naming the node → exit 1, said open, nothing written" 1 "atlas is open, and an open scope's yard is never a node" atlas --yard sec-agent
yn "…another scope's node, though the write flags it confidential → exit 1, nothing written" 1 "sec-agent is not a host .*nor a node of atlas's told here" atlas --confidential --yard sec-agent
yn "…a write that opens the scope it names the node of → exit 1" 1 "sec is open, and an open scope's yard is never a node" sec --open --yard sec-agent
yn "…an unlisted host, as before → exit 1, the scope's own node named beside the list" 1 "nowhere is not a host .*lighthouse/hosts lists (laptop, studio), nor sec's own node (sec-agent)" sec --yard nowhere
printf 'laptop\nstudio\nsec-agent\n' > "$F/cfg/lighthouse/hosts"   # the overlay may list the node too
yn "…a node lighthouse/hosts lists, for an open scope → exit 1, nothing written" 1 "atlas is open, and an open scope's yard is never a node" atlas --yard sec-agent
yn "…for another confidential scope → exit 1, nothing written" 1 "sec-agent is not a host .*nor a node of atlas's told here" atlas --confidential --yard sec-agent
yn "…for its own scope, in capitals → exit 0" 0 "yard Sec-Agent\$" sec --yard Sec-Agent --dry-run
printf 'laptop\nstudio\n' > "$F/cfg/lighthouse/hosts"
rm "$F/cfg/wharf-runs/nodes/sec/ssh"
yn "…its node folder with no ssh → exit 1, said why" 1 "nodes/sec names scope sec and no ssh" sec --yard sec-agent
echo sec-agent > "$F/cfg/wharf-runs/nodes/sec/ssh"
out=$(SC set sec --yard sec-agent 2>&1); rc=$?
if [ $rc -eq 0 ] && python3 -c "import json,sys; s=json.load(open(sys.argv[1]))['scopes']['sec']; sys.exit(0 if s.get('yard')=='sec-agent' and s.get('confidential') is True and s.get('login')=='lab' else 1)" "$F/repos.json"; then
  echo "  ok   …written: the yard the node, the flag and the login kept"
else echo "  FAIL scopes set sec --yard sec-agent (rc $rc): $out"; fails=$((fails+1)); fi
cp "$F/node-before.json" "$F/repos.json"
rm -r "$F/cfg/wharf-runs/nodes"; NK="$F/cfg/wharf-runs/node"; mkdir -p "$NK"; echo sec > "$NK/scope"; printf 'know gh/know\n' > "$NK/clones"
HN=$(REGATTA_CONFIG="$F/cfg" python3 -I -c "import sys; sys.path.insert(0, sys.argv[1]); import common; print(common.host_name())" "$B/../../regatta/hooks")
yn "this host as sec's node (its payload's scope names sec) → exit 0" 0 "yard $HN\$" sec --yard "$HN" --dry-run
yn "…another confidential scope naming this node → exit 1" 1 "$HN is not a host .*nor a node of atlas's told here" atlas --confidential --yard "$HN" --dry-run
: > "$NK/scope"
yn "…a shared node (its scope empty), whatever its clones hold → exit 1" 1 "$HN is not a host .*nor a node of sec's told here" sec --yard "$HN" --dry-run
rm "$NK/scope"; printf 'layer gh/layer\n' > "$NK/clones"
yn "…an older render (clones, no scope key) carrying an open scope's repo, this host not named <scope>-agent: no node → exit 1" 1 "$HN is not a host .*nor a node of atlas's told here" atlas --confidential --yard "$HN" --dry-run
rm -r "$F/cfg/wharf-runs"
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
# write --from (wharf's sync.py at every start): every open scope, a confidential one only from a
# session inside it; a file inside a git checkout goes into its .git/info/exclude, so it never dirties it
W="$T/from"; WP="$W/projects"; mkdir -p "$W/cfg/regatta"; echo "$WP" > "$W/cfg/regatta/projects"
for d in layer pub node; do git init -q -b main "$WP/$d"; done
mkdir -p "$WP/node/memory"
cat > "$WP/layer/repos.json" <<'J'
{"repos": {"layer": {}, "pub": {}, "node": {}},
 "scopes": {"coding": {"file": "coding.code-workspace", "repos": ["layer", "pub"]},
            "sec": {"file": "node/sec.code-workspace", "repos": ["node"], "confidential": true}}}
J
FW() { REGATTA_CONFIG="$W/cfg" CLAUDE_REPOS_JSON="$WP/layer/repos.json" python3 "$B/scopes" write "$@" 2>&1; }
out=$(FW --from "$WP/pub"); rc=$?
if [ $rc -eq 0 ] && [ -f "$WP/coding.code-workspace" ] && [ ! -e "$WP/node/sec.code-workspace" ]; then
  echo "  ok   write --from outside a confidential scope: the open scope's file written, the confidential one's not"
else echo "  FAIL write --from outside (rc $rc): $out"; fails=$((fails+1)); fi
mkdir -p "$W/scratch/node/s1"   # a folder named after the scope's repo is not in the scope (the guard-scratch trap)
out=$(FW --from "$W/scratch/node/s1"); rc=$?
[ $rc -eq 0 ] && [ ! -e "$WP/node/sec.code-workspace" ] \
  && echo "  ok   …a path that only carries the scope's name is outside it: judged by its own folders, not a slug" \
  || { echo "  FAIL write --from a scope-named scratch folder (rc $rc): $out"; fails=$((fails+1)); }
out=$(FW --from "$WP/node"); rc=$?
if [ $rc -eq 0 ] && [ -f "$WP/node/sec.code-workspace" ] && grep -qx "/sec.code-workspace" "$WP/node/.git/info/exclude" \
   && [ -z "$(git -C "$WP/node" status --porcelain)" ] && printf '%s' "$out" | grep -q "^excluded /sec.code-workspace"; then
  echo "  ok   …from inside it: written, and kept out of its checkout's git by .git/info/exclude"
else echo "  FAIL write --from inside (rc $rc): $out"; fails=$((fails+1)); fi
out=$(FW --from "$WP/node")
if [ "$out" = "✓ 2 scope files current" ] && [ "$(grep -c sec.code-workspace "$WP/node/.git/info/exclude")" = 1 ]; then
  echo "  ok   …a second run: nothing written, the exclude line not repeated"
else echo "  FAIL write --from, second run: $out"; fails=$((fails+1)); fi
echo '!/sec.code-workspace' > "$WP/node/.gitignore"   # a .gitignore that un-ignores it beats the exclude
FW --from "$WP/node" >/dev/null; out=$(FW --from "$WP/node")
if [ "$(grep -c sec.code-workspace "$WP/node/.git/info/exclude")" = 1 ] && printf '%s' "$out" | grep -q "un-ignores it"; then
  echo "  ok   …un-ignored by its .gitignore: the exclude line never repeated, the conflict named"
else echo "  FAIL write --from, un-ignored file: $out"; fails=$((fails+1)); cat "$WP/node/.git/info/exclude"; fi
rm "$WP/node/.gitignore"
bad=0
FW --from "" >/dev/null; [ $? -eq 2 ] || { bad=1; echo '       not refused: write --from ""'; }
for a in "--from" "--from=$WP/pub" "--frm $WP/pub" "--from --dry-run" "--from $WP/pub --from $WP/node"; do
  # shellcheck disable=SC2086
  FW $a >/dev/null; [ $? -eq 2 ] || { bad=1; echo "       not refused: write $a"; }
done
[ $bad -eq 0 ] && echo "  ok   write refuses what it does not understand (--from with no path or an empty one, --from=, a misspelling, twice) → exit 2" \
  || { echo "  FAIL write's options"; fails=$((fails+1)); }
# a run under another's lock waits, then gives up with exit 3 and no ✓ (each run's `only` differs:
# skipping for an open session's run would drop a confidential one's write)
cat > "$W/lockheld.py" <<'PY'
import fcntl, subprocess, sys
with open(sys.argv[1] + "/wharf/scopes-write.lock", "w") as h:
    fcntl.flock(h, fcntl.LOCK_EX)
    r = subprocess.run(sys.argv[2:], capture_output=True, text=True)
    print(r.returncode, r.stdout.strip())
PY
out=$(REGATTA_CONFIG="$W/cfg" CLAUDE_REPOS_JSON="$WP/layer/repos.json" REGATTA_SCOPES_LOCK_WAIT=1 \
  python3 "$W/lockheld.py" "$W/cfg" python3 "$B/scopes" write --from "$WP/pub")
[ "$out" = "3 " ] && echo "  ok   write --from while another write holds the lock: waits, then exit 3, nothing written, no ✓" \
  || { echo "  FAIL write --from under the lock: [$out]"; fails=$((fails+1)); }

# hooks/sync.py's session-start run: what `write --from` refused is kept in that repo's git dir, and said
# at the next start there, once — never in another repo's session (a confidential refusal stays in its node)
SY="$(cd "$B/../hooks" && pwd)/sync.py"
SR() { REGATTA_CONFIG="$W/cfg" CLAUDE_REPOS_JSON="$WP/layer/repos.json" python3 "$SY" --scope-files-run "$1"; }
SN() { REGATTA_CONFIG="$W/cfg" CLAUDE_REPOS_JSON="$WP/layer/repos.json" python3 -c \
  'import sys; from pathlib import Path; from importlib.machinery import SourceFileLoader as L; print(L("sy", sys.argv[1]).load_module().scope_files_notes(Path(sys.argv[2])))' "$SY" "$1"; }
SR "$WP/pub"
[ "$(SN "$WP/pub")" = "[]" ] && echo "  ok   sync.py --scope-files-run, all written: nothing to say" \
  || { echo "  FAIL sync.py, clean run: $(SN "$WP/pub")"; fails=$((fails+1)); }
cp "$WP/layer/repos.json" "$W/good.json"
python3 -c "import json,sys; d=json.load(open(sys.argv[1])); d['repos']['stray']={}; json.dump(d, open(sys.argv[1],'w'))" "$WP/layer/repos.json"
SR "$WP/node"
out=$(SN "$WP/node")
if printf '%s' "$out" | grep -q "scope workspaces: ✗ stray is in no scope" && [ "$(SN "$WP/node")" = "[]" ]; then
  echo "  ok   …a refused write is said at the next start in that repo, once"
else echo "  FAIL sync.py refused write: $out"; fails=$((fails+1)); fi
[ "$(SN "$WP/pub")" = "[]" ] && echo "  ok   …and never at a start in another repo: a confidential node's refusal stays in it" \
  || { echo "  FAIL sync.py: node's refusal said in pub: $(SN "$WP/pub")"; fails=$((fails+1)); }
printf '{"repos": ' > "$WP/layer/repos.json"
SR "$WP/pub"
out=$(SN "$WP/pub")
printf '%s' "$out" | grep -q "scope workspaces: ✗ bin/scopes write exited" \
  && echo "  ok   …a run that fails with no ✗ line (a torn registry) is recorded as failed, never as clean" \
  || { echo "  FAIL sync.py, torn registry: $out"; fails=$((fails+1)); }
cp "$W/good.json" "$WP/layer/repos.json"
python3 -c "import json,sys; d=json.load(open(sys.argv[1])); d['scopes']['sec']['repos'].append('ghostnode'); json.dump(d, open(sys.argv[1],'w'))" "$WP/layer/repos.json"
SR "$WP/pub"
out=$(SN "$WP/pub")
if printf '%s' "$out" | grep -q "a confidential scope this session is outside" && ! printf '%s' "$out" | grep -q -e sec -e ghostnode; then
  echo "  ok   …a fault naming a confidential scope reaches an open repo's record as one line naming none of it"
else echo "  FAIL sync.py: a confidential scope's fault in pub's record: $out"; fails=$((fails+1)); fi
SR "$WP/node"
printf '%s' "$(SN "$WP/node")" | grep -q "ghostnode" && echo "  ok   …and is named in full at a start inside the scope" \
  || { echo "  FAIL sync.py: the fault not named inside sec: $(SN "$WP/node")"; fails=$((fails+1)); }
# a fenced scope whose repos do not read hides none of them: the open repo's record names nothing
# (the second finish review, 2026-11-03: `"repos": "node"` named node as "in no scope")
python3 -c "import json,sys; d=json.load(open(sys.argv[2])); d['scopes']['sec']['repos']='node'; json.dump(d, open(sys.argv[1],'w'))" "$WP/layer/repos.json" "$W/good.json"
SR "$WP/pub"
out=$(SN "$WP/pub")
if printf '%s' "$out" | grep -q "a malformed confidential scope" && ! printf '%s' "$out" | grep -q -w -e sec -e node; then
  echo "  ok   …a confidential scope whose repos do not read: one line naming none of it"
else echo "  FAIL sync.py: a malformed confidential scope in pub's record: $out"; fails=$((fails+1)); fi
# a confidential flag that is not plainly true or false is fenced, never read as open
python3 -c "import json,sys; d=json.load(open(sys.argv[2])); d['scopes']['sec']['confidential']='true'; d['scopes']['sec']['repos'].append('ghostnode'); json.dump(d, open(sys.argv[1],'w'))" "$WP/layer/repos.json" "$W/good.json"
SR "$WP/pub"
out=$(SN "$WP/pub")
if printf '%s' "$out" | grep -q "a confidential scope this session is outside" && ! printf '%s' "$out" | grep -q -e ghostnode -e "scope sec"; then
  echo "  ok   …a confidential flag written \"true\" is fenced: its faults name none of it in an open repo"
else echo "  FAIL sync.py: a \"true\" flag read as open: $out"; fails=$((fails+1)); fi
cp "$W/good.json" "$WP/layer/repos.json"
out=$(REGATTA_CONFIG="$W/cfg" CLAUDE_REPOS_JSON="$WP/layer/repos.json" REGATTA_SCOPES_LOCK_WAIT=1m python3 "$B/scopes" list 2>&1 >/dev/null; echo "rc=$?")
[ "$out" = "rc=0" ] && echo "  ok   a lock wait that does not read is 60 s, never a crash of every verb" \
  || { echo "  FAIL scopes list under REGATTA_SCOPES_LOCK_WAIT=1m: $out"; fails=$((fails+1)); }
printf '✗ an earlier refusal\n' > "$WP/pub/.git/claude/scope-files"
REGATTA_CONFIG="$W/cfg" CLAUDE_REPOS_JSON="$WP/layer/repos.json" REGATTA_SCOPES_LOCK_WAIT=1 \
  python3 "$W/lockheld.py" "$W/cfg" python3 "$SY" --scope-files-run "$WP/pub" >/dev/null
[ "$(cat "$WP/pub/.git/claude/scope-files")" = "✗ an earlier refusal" ] \
  && echo "  ok   …a run that never got the lock keeps the record as it was, never an empty one" \
  || { echo "  FAIL sync.py, lock never freed: [$(cat "$WP/pub/.git/claude/scope-files")]"; fails=$((fails+1)); }
git init -q -b main "$WP/quiet"
SP() { REGATTA_CONFIG="$W/cfg" CLAUDE_REPOS_JSON="$W/missing.json" REGATTA_SCOPE_FILES="$1" python3 -c \
  'import sys; from pathlib import Path; from importlib.machinery import SourceFileLoader as L; L("sy", sys.argv[1]).load_module().spawn_scope_files(Path(sys.argv[2]))' "$SY" "$WP/quiet"; }
# off, and any value it cannot read, never starts the child: a stand-in Popen counts the calls
cat > "$W/spawncount.py" <<'PY'
import sys
from pathlib import Path
from importlib.machinery import SourceFileLoader as L
m = L("sy", sys.argv[1]).load_module()
calls = []
m.subprocess.Popen = lambda *a, **k: calls.append(a)
m.spawn_scope_files(Path(sys.argv[2]))
print(len(calls))
PY
SPN() { REGATTA_CONFIG="$W/cfg" CLAUDE_REPOS_JSON="$W/missing.json" REGATTA_SCOPE_FILES="$1" python3 "$W/spawncount.py" "$SY" "$WP/quiet"; }
bad=0
for v in off 0 no false bogus; do [ "$(SPN "$v")" = "0" ] || { bad=1; echo "       spawned under REGATTA_SCOPE_FILES=$v"; }; done
[ $bad -eq 0 ] && [ "$(SPN "")" = "1" ] \
  && echo "  ok   REGATTA_SCOPE_FILES=off, or any value but empty or inline, starts no child; empty starts one" \
  || { echo "  FAIL REGATTA_SCOPE_FILES's switch"; fails=$((fails+1)); }
mkdir -p "$W/emptycfg"
[ "$(env -u CLAUDE_REPOS_JSON REGATTA_CONFIG="$W/emptycfg" REGATTA_SCOPE_FILES= python3 "$W/spawncount.py" "$SY" "$WP/quiet")" = "0" ] \
  && echo "  ok   a host with no registry (the public twin's users) starts no child and says nothing" \
  || { echo "  FAIL spawn_scope_files with no registry started a child"; fails=$((fails+1)); }
SP inline
[ -s "$WP/quiet/.git/claude/scope-files" ] && echo "  ok   REGATTA_SCOPE_FILES=inline: run in place (its failure recorded)" \
  || { echo "  FAIL REGATTA_SCOPE_FILES=inline left no record"; fails=$((fails+1)); }

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
