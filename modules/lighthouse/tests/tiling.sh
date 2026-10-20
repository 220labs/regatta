#!/usr/bin/env bash
# tiling.sh — bin/tiling's own decisions: which desktop install binds, which space apply tiles
# and which it floats (everything else is yabai's and the Dock's). Pure functions: no yabai, no Dock.
#   bash modules/lighthouse/tests/tiling.sh
set -u
here="$(cd "$(dirname "$0")/../bin" && pwd)"
/usr/bin/python3 - "$here/tiling" <<'PY'
import sys, importlib.machinery, importlib.util
loader = importlib.machinery.SourceFileLoader("t", sys.argv[1])
spec = importlib.util.spec_from_loader("t", loader); m = importlib.util.module_from_spec(spec); loader.exec_module(m)
def prefs(*spaces, display="Main", bound=None):
    p = {"SpacesDisplayConfiguration": {"Management Data": {"Monitors": [
        {"Display Identifier": display, "Spaces": [{"uuid": u, "type": t} for u, t in spaces]}]}}}
    if bound:
        p["app-bindings"] = {"com.apple.terminal": bound}
    return p
d = [("", 0), ("B", 0), ("C", 0), ("D", 0), ("E", 0)]
# yabai's list: the claude desktop E moved to index 6 behind a full-screen space; C still bsp from before
live = [{"index": 1, "uuid": "", "type": "float"}, {"index": 2, "uuid": "B", "type": "float"},
        {"index": 3, "uuid": "FS", "type": "float"}, {"index": 4, "uuid": "C", "type": "bsp"},
        {"index": 5, "uuid": "D", "type": "float"}, {"index": 6, "uuid": "E", "type": "bsp"}]
cases = [
    ("install: fifth desktop", m.desktop_uuid(prefs(*d)), "E"),
    ("install: full-screen space skipped", m.desktop_uuid(prefs(d[0], d[1], ("FS", 4), *d[2:])), "E"),
    ("install: four desktops", m.desktop_uuid(prefs(*d[:4])), None),
    ("install: no main display", m.desktop_uuid(prefs(*d, display="X")), None),
    ("install: empty prefs", m.desktop_uuid({}), None),
    ("binding read", m.bound_uuid(prefs(*d, bound="E")), "E"),
    ("no binding", m.bound_uuid(prefs(*d)), None),
    ("apply: tiles the bound desktop wherever it moved, floats the stale bsp", m.plan(live, "E"), (6, [4])),
    ("apply: desktop 1's empty uuid", m.plan(live, ""), (1, [4, 6])),
    ("apply: bound desktop gone floats every bsp", m.plan(live, "Z"), (None, [4, 6])),
    ("apply: no binding matches nothing", m.plan(live, None), (None, [4, 6])),
]
# apply at yabai's start: a half-written answer is retried, not a crash (2026-10-06's reboot)
answers = iter([(0, "[\n"), (1, ""), (0, "[]"), (0, '[{"index": 5}]')])   # [] too: never zero spaces
m.yabai = lambda *a: m.subprocess.CompletedProcess(a, *next(answers), "")
m.time.sleep = lambda s: None
cases.append(("apply: polls until the spaces parse", m.query_spaces(), [{"index": 5}]))
m.yabai = lambda *a: m.subprocess.CompletedProcess(a, 0, "[\n", "")
cases.append(("apply: never parses -> None", m.query_spaces(wait=0), None))
bad = [(n, want, got) for n, got, want in cases if got != want]
for n, want, got in bad:
    print("FAIL %s: want %r, got %r" % (n, want, got))
print("tiling: %d/%d ok" % (len(cases) - len(bad), len(cases)))
sys.exit(1 if bad else 0)
PY
