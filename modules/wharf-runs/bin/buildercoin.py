#!/usr/bin/env python3
"""The builder rotation: dispatch's coin for a build on it, specced or plain Opus (S6 of docs/self-tuning-2026-10-26.md, D2-A).

The finisher rotation's shape (autofinish-run's header), for builders. While the config key
`wharf-runs/builder-rotation` says `until YYYY-MM-DD` and that day has not passed, a run whose brief is
specced — its `Tier:` line names `worker` (and no other model) or Sonnet alone; a blueprint block's `tier: worker`
counts only through the brief's line, and `wharf check` warns when they differ — or plain Opus — the line names
Opus alone, no tier word and no effort but `high`, the rules' default written out (the owner, 2026-11-03) — and
no principal tier, `sr-worker` or other tier, and that no `--model` or `--effort` was given for, draws its
builder once, when dispatch enqueues or schedules it, by the odds the fleet limit `wharf-runs/builder-odds` gives
(`opus-high=1,sonnet-high=2,argon-high=2,gpt-big=1,gpt-mid=1` by default — Opus 5.5, Sonnet 5.5 and Gemini 4 Argon, each
at `high`, and Codex's gpt-6.1-sol at `xhigh` (gpt-big, the Opus mirror) and `high` (gpt-mid, the Sonnet one), 1:2:2:1:1 —
the owner's D2 of docs/argon-builder-arm-2026-11-03.md, and S8's two Sol arms, the owner's pick of 2026-11-04; 3 in 5
Sonnet from 2026-11-03 and 1 in 5 before, both without Argon), each by full id; a positional live value
(`0:0:0:1:1`) reads ahead of a named base line, an arm it omits weighing 0; blueprintlib's `brief_rotates` says which class, and the row keeps it as `brief_class`. No key, a passed day or a
line that does not parse is today's dispatch, unchanged. The fence comes first, as the finisher's, one rule in the
core (`scope_rotates`): a repo any of whose scopes says `"rotation": false` (or a `rotation` that is not a bool), a
repo in no scope, or a registry that does not read or walk draws nothing. A confidential scope draws unless it opts
out so (the owner, 2026-11-04: one scope opts out, the others draw); its row says `scope` and `confidential: true`,
and its vendor arms weigh 0. A run that carries an origin marker draws nothing.

While BOTH Claude weights are zero (Codex takes every new build, the owner, 2026-11-04), a worker or Sonnet brief
takes only gpt-mid and an sr-worker or Opus one only gpt-big (`gpt_class`), Claude tier lines with reasons or an
explicit effort included; a principal tier and every other class keep their Claude route, and any positive Claude
weight restores the old class rule. A zero-weight arm is never drawn, even by DISPATCH_COIN.

An arm whose agent is no `claude` (Argon's `antigravity`, agy-road's provider word; `codex`, S8's) runs only on a builder host, one whose
`wharf-runs/features` line names the agent's feature (`agy`, `codex`): the draw asks the hosts ref for a fresh row of such a host
that may take the repo (`dispatch-queue fresh`), and dispatch adds the feature to the run's --needs. With none, or with no
road for the agent in dispatch yet (ROADS: Codex's since S8, Antigravity's build loop is S4), it draws Opus in its place and says so: the word keeps
the coin drawn and names opus-high (`opus-high:2:…`), and the record and the row say `fallback`. The fire path asks the
road again and falls back the same way; the queue's sweep makes the same Opus word of a vendor entry no host claimed
within REDRAW_AGE (dispatch-queue's).

The arm rides to the run as one word, DISPATCH_ARM=<name>:<coin>:<until>:<forced> (the queue entry's env,
the ssh line, the one-shot's plist), so both roads run the arm drawn once. Its grammar is WORD_GRAMMAR, here, and its
copies (dispatch's two tests, dispatch-queue's and helm's stalls_tick's ARM_WORD) are held to it, a case each. Where the
run fires, dispatch re-reads the brief and asks the key's window, the fence and the odds again, on that host (so every
host that claims runs needs the key): still on the coin, no flag given, the key on, the fence open and the drawn arm's
weight above 0, the arm decides the model and effort and goes into the
run record as `arm` ({name, model, effort, coin, until, forced, agent[, fallback]}) with `arm_source` (`coin`, or `pinned` for a
forced coin); and one row goes to <logs>/builder-rotation.jsonl beside finisher-rotation.jsonl, outside git,
private to this Mac — the fence asked again there, so a repo fenced meanwhile writes none. trim's collect
joins the rows by session; run_vendor writes a vendor run's row at its end, with its conversation, cost,
turns, rounds and outcome. DISPATCH_COIN=0..4 forces the coin (the tests), and the row says `forced`;
DISPATCH_COIN_ROADS (the tests' too, dispatch hands it to the draw alone) names agents the draw may treat as having a road.

    buildercoin.py draw REPO [--needs A,B] [--pin H] [--brief-class CLASS] [--origin MARK]
                                        # stdout: the word, or nothing; stderr: why (only with the key file
                                        # there); a vendor arm's builder host must meet the run's own needs and pin
    buildercoin.py arm WORD [--repo R]  # stdout: "<model> <effort> <word> <record json>"; exit 1, why on stdout, for a
                                        # word that does not read, or with R: the key's window closed today, R fenced, or
                                        # the drawn arm's weight 0; with R, a vendor arm with no road here is its Opus word
    buildercoin.py row WORD --repo R --branch B --topic T --session S [--account A] [--queue Q] [--brief CLASS]
    buildercoin.py specced              # stdin: a brief; exit 0 when specced, 1 when not
    buildercoin.py rotates              # stdin: a brief; stdout: specced or plain, exit 0; nothing, exit 1
    buildercoin.py need WORD            # stdout: the feature the word's arm needs of a host (`agy`), or nothing
    buildercoin.py fallback WORD        # stdout: the Opus word in a vendor arm's place, or the word as given
    buildercoin.py odds                 # stdout: the limit's odds as the draw reads them (`regatta limit`'s trial read); exit 2 refused
    buildercoin.py grammar              # stdout: WORD_GRAMMAR, the one grammar of the word

Exit 0, or 1 for a word or brief that does not read (or an arm the window or fence refuses at fire time); dispatch
reads any non-zero, an uncaught error's 1 included, as no arm.
"""
import argparse
import contextlib
import datetime
import fcntl
import json
import os
import random
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "lib"))
sys.path.insert(0, HERE)
import core_path  # noqa: E402 — the regatta core (C2); none: one line, exit 2
core_path.require()
import common  # noqa: E402

LOGS = os.path.join(os.path.expanduser("~"), "Library", "Logs", "claude-weekly")
ROTATION_KEY = "wharf-runs/builder-rotation"
# the arms in coin order, 0 the pin and every fallback's arm; full ids: an alias floats (the builders bench's harness
# rules); the agent that runs it: `claude`, or a vendor CLI by agy-road's provider word (lighthouse's `account`)
ARMS = (("opus-high", "claude-opus-5-5", "high", "claude"),
        ("sonnet-high", "claude-sonnet-5-5", "high", "claude"),
        ("argon-high", "gemini-4-argon-high", "high", "antigravity"),
        ("gpt-big", "gpt-6.1-sol", "xhigh", "codex"),
        ("gpt-mid", "gpt-6.1-sol", "high", "codex"))
# the feature a builder host's `wharf-runs/features` line names for an agent: what the run's --needs asks of a host
AGENT_NEED = {"antigravity": "agy", "codex": "codex"}
# the agents dispatch's fire path runs: Codex's since S8 (run_vendor); any other vendor arm weighs 0 at the draw until
# its road lands (Antigravity's build loop, S4 of docs/argon-builder-arm-2026-11-03.md; road_weights), and a carried
# word of it fires as its Opus fallback
ROADS = ("claude", "codex")
# a fleet limit (wharf-runs' limits file): a whole weight per arm by its name, `opus-high=1,sonnet-high=2,argon-high=2`,
# an arm left out weighing 0. Positional live values read ahead of a named base.
# An arm added later reads 0 in a value written before it.
ODDS_KEY = "wharf-runs/builder-odds"
ODDS_DEFAULT = (1, 2, 2, 1, 1)         # Opus, Sonnet, Argon, GPT big, GPT mid
ODDS_MAX = 1000                        # a weight past this is a typo, never odds
# The word's one grammar (S3 of the Argon doc): every copy is held to it, a case each (test_builder_coin.sh)
WORD_GRAMMAR = r"(%s):[0-%d]:[0-9]{4}-[0-9]{2}-[0-9]{2}:[01]" % ("|".join(x[0] for x in ARMS), len(ARMS) - 1)
WORD_RE = re.compile(WORD_GRAMMAR)
ODDS_RE = re.compile(r"^\d+(?::\d+){2}(?::\d+:\d+)?$")
ODDS_NAMED_RE = re.compile(r"^([a-z0-9-]+)=(\d+)$")   # one arm's weight in the limit
ODDS_OLD_RE = re.compile(r"^(\d+)/(\d+)$")   # #459's row: n Sonnet draws in d, no Argon
ROTATION_LOG = "builder-rotation.jsonl"   # in LOGS: private to this Mac, outside git
ROTATION_RE = re.compile(r"^(?:until\s+)?(\d{4}-\d{2}-\d{2})$")


def rotation_window(today=None):
    """(end, why): the last day the rotation runs, or None and why it is off (autofinish-run's, its key)."""
    lines, bad = common.config_read(ROTATION_KEY)
    if bad:
        return None, "builder rotation off: %s unreadable (%s)" % (ROTATION_KEY, bad)
    if not lines:
        return None, "builder rotation off: no %s" % ROTATION_KEY
    # bootstrap.sh's config_values writes each word on its own line: joined, both forms read
    text = " ".join(l.strip() for l in lines if l.strip())
    m = ROTATION_RE.match(text)
    try:
        end = datetime.date.fromisoformat(m.group(1)) if m else None
    except ValueError:
        end = None
    if end is None:
        return None, "builder rotation off: %s says %r, not `until YYYY-MM-DD`" % (ROTATION_KEY, text[:60])
    if (today or datetime.date.today()) > end:
        return None, "builder rotation off: it ended %s" % end
    return end, "builder rotation on until %s" % end


def rotation_gate(primary):
    """(why, fields): why None when a build of this repo may rotate and be recorded, else why not; fields the
    row's `scope` and `confidential` (the core's scope_rotates, the one rule autofinish-run's fence asks too). It
    fails closed: a torn registry (asked first, AGENTS.md's fence trap), a scope it cannot walk, no scope, a scope
    whose `rotation` is false or not a bool, and a core older than scope_rotates."""
    reg, bad = common.read_registry()
    if bad:
        return "the scope registry does not read", {}
    rule = getattr(common, "scope_rotates", None)
    if rule is None:
        return "the core has no scope_rotates (older than scope-rotation)", {}
    ok, why, fields = rule(primary, reg)
    return (None, fields) if ok else (why, {})


def rotation_fence(primary):
    """None when a build of this repo may rotate, else why not (rotation_gate's why)."""
    return rotation_gate(primary)[0]


def specced(text):
    """blueprintlib's brief_specced: the one reading dispatch's tier_run makes too (imported here alone: the
    draw, arm and row verbs dispatch runs never need it)."""
    import blueprintlib
    return blueprintlib.brief_specced(text)


def odds_of(text):
    """The weights per arm, in ARMS' order, of a row's `odds` in either form a row has held: `o:s:a` (since S3 of the
    Argon doc) or #459's `n/d` (n Sonnet draws in d, the rest Opus, no Argon); None for anything else. trim's reader (S6)."""
    t = "".join(str(text or "").split())
    m = ODDS_RE.match(t)
    if m:
        w = tuple(int(x) for x in t.split(":"))
        return w if all(x <= ODDS_MAX for x in w) else None
    m = ODDS_OLD_RE.match(t)
    if m:
        n, d = int(m.group(1)), int(m.group(2))
        return (d - n, n, 0) if 0 <= n <= d <= ODDS_MAX and d else None
    return None


def odds_text(w):
    return ":".join(str(x) for x in w)


def odds_named(text):
    """{arm: weight} of the limit's value, `opus-high=1,sonnet-high=2,argon-high=2` (spaces ignored, any order), or
    None: an arm ARMS lacks, one named twice, a weight that is no whole number up to ODDS_MAX."""
    out = {}
    names = [x[0] for x in ARMS]
    for part in "".join(str(text or "").split()).split(","):
        m = ODDS_NAMED_RE.match(part)
        if not m or m.group(1) not in names or m.group(1) in out or int(m.group(2)) > ODDS_MAX:
            return None
        out[m.group(1)] = int(m.group(2))
    return out


def named_text(named):
    """The limit's value as the draw reads it, in ARMS' order: the arms it names (an arm left out weighs 0)."""
    return ",".join("%s=%d" % (x[0], named[x[0]]) for x in ARMS if x[0] in named)


ODDS_DEFAULT_TEXT = named_text({x[0]: w for x, w in zip(ARMS, ODDS_DEFAULT)})


def read_odds():
    """(weights, why) from the fleet limit ODDS_KEY, in ARMS' order, or (None, why) when it does not read: absent, or
    written empty (`regatta limit get`'s reading of a plain key), is ODDS_DEFAULT; one word per line (bootstrap's
    config_values) reads as the line."""
    w, _, why = _read_odds()
    return w, why


def _read_odds():
    lines, bad = common.config_read(ODDS_KEY)
    if bad:
        return None, None, "%s unreadable (%s)" % (ODDS_KEY, bad)
    if not lines:
        return ODDS_DEFAULT, ODDS_DEFAULT_TEXT, "%s's default %s" % (ODDS_KEY, ODDS_DEFAULT_TEXT)
    # a note after `#` or `(` is no text, as in kicklib's readers, and it may span lines (one word per line); an arm per
    # word, split by commas, spaces or lines, reads as one value (the S3 landing review, 2026-11-04)
    body = re.split(r"[#(]", " ".join(lines), maxsplit=1)[0]
    text = ",".join(t for t in re.split(r"[\s,]+", body) if t)
    if not text:
        return ODDS_DEFAULT, ODDS_DEFAULT_TEXT, "%s's default %s" % (ODDS_KEY, ODDS_DEFAULT_TEXT)
    # a positional live value (`0:0:0:1:1`, S8) can stand ahead of a named base line, as live_merge leaves it: the first
    # value wins when it reads as positional, an arm it omits weighing 0
    first = text.split(",", 1)[0]
    positional = odds_of(first) if ":" in first else None
    if positional is not None:
        w = tuple(positional) + (0,) * (len(ARMS) - len(positional))
        return w, first, "%s %s" % (ODDS_KEY, first)
    named = odds_named(text)
    if named is None:
        return None, None, "%s says %r, not `opus-high=W,sonnet-high=W,argon-high=W` (whole weights)" % (ODDS_KEY, text[:60])
    return tuple(named.get(x[0], 0) for x in ARMS), named_text(named), "%s %s" % (ODDS_KEY, named_text(named))


def road_weights(weights, at_draw=False):
    """WEIGHTS with every arm whose agent has no road here weighing 0: an arm dispatch cannot run is never rolled, so
    until its road lands (S4 of docs/argon-builder-arm-2026-11-03.md) the odds are the other arms' (1:2:2 draws as 1:2),
    never Opus in its place: a road-less fallback would move the owner's Sonnet share to Opus and yield no vendor row
    (the S3 landing review, 2026-11-04). The fallback stays for a draw whose builder host is not fresh."""
    return tuple(w if has_road(ARMS[i][3], at_draw) else 0 for i, w in enumerate(weights))


def coin_of(r, weights=ODDS_DEFAULT):
    """The coin for a roll r in range(sum(weights)): the arms take the rolls in ARMS' order, each its weight's share."""
    for coin, w in enumerate(weights):
        if r < w:
            return coin
        r -= w
    raise ValueError("roll past the weights")


def rotates(text):
    """blueprintlib's brief_rotates: "specced", "plain", or None."""
    import blueprintlib
    old = blueprintlib.brief_rotates(text)
    return gpt_class(text) or old


def gpt_class(text):
    """While BOTH Claude weights are zero, worker/Sonnet and sr-worker/Opus
    briefs draw only their size's GPT arm. Principal and every other class stay
    on the old rule. Any positive Claude weight restores that rule at the next draw (a word already drawn keeps its
    arm: dispatch's arm_keep_gpt).
    """
    w, _ = read_odds()
    if w is None or any(w[:2]):
        return None
    return gpt_size(text)


def gpt_size(text):
    """The GPT arm of this brief's size, whatever the odds read: gpt_class's rule, and at fire the test of a drawn word."""
    import blueprintlib
    match = blueprintlib.TIER_LINE_RE.search(text or "")
    line = match.group(1).lower() if match else ""
    if "principal" in line:
        return None
    # A tier word decides alone: sr-worker is big, worker mid, and any other tier (architect, sr-architect,
    # main, …) keeps its Claude route even when it names a model. Only a line with no tier word is read by
    # its model words (an Opus or Sonnet line).
    tier = blueprintlib.brief_tier(text or "")
    if tier == "sr-worker":
        return "gpt-big"
    if tier == "worker":
        return "gpt-mid"
    if tier:
        return None
    if re.search(r"\bopus\b", line):
        return "gpt-big"
    if re.search(r"\bsonnet\b", line):
        return "gpt-mid"
    return None


def has_road(agent, at_draw=False):
    """Whether dispatch runs AGENT's arm here: ROADS; at the draw also DISPATCH_COIN_ROADS (the tests', never the fire's)."""
    extra = os.environ.get("DISPATCH_COIN_ROADS", "").split(",") if at_draw else []
    return agent in ROADS or agent in extra


FRESH_TIMEOUT = 90   # s: the hosts ref's fetch at the draw; past it, no host is known fresh and the draw falls back


def builder_host(primary, need, needs=(), pin=""):
    """(host, None) for a builder host the hosts ref shows fresh, whose features line names NEED and the run's own
    NEEDS, which may take PRIMARY and is the run's PIN when it has one — a host that may claim the whole run — or (None,
    why not): dispatch-queue's `fresh` decides; any answer but its 0 is none (fail to Opus)."""
    q = os.path.join(HERE, "dispatch-queue")
    want = ",".join(sorted({need} | {n for n in needs if n}))
    try:
        r = subprocess.run([sys.executable, q, "fresh", "--repo", primary, "--needs", want] + (["--pin", pin] if pin else []),
                           capture_output=True,
                           text=True, timeout=FRESH_TIMEOUT, stdin=subprocess.DEVNULL)
    except (OSError, subprocess.TimeoutExpired) as e:
        return None, "the hosts ref did not answer (%s)" % type(e).__name__
    try:
        out = json.loads((r.stdout.strip().splitlines() or ["{}"])[-1])
    except ValueError:
        out = {}
    hosts = out.get("hosts") if isinstance(out, dict) else None
    if r.returncode == 0 and isinstance(hosts, list) and hosts:
        return str(hosts[0]), None
    why = (out.get("why") if isinstance(out, dict) else None) or (r.stderr.strip().splitlines() or [""])[-1][:160]
    return None, why or "dispatch-queue fresh exit %d" % r.returncode


def draw(primary, needs=(), pin="", brief_class="", origin=""):
    """(word, why): the arm drawn for a build of this repo, as DISPATCH_ARM's word, or None and why not. NEEDS and PIN
    are the run's own (dispatch's --needs and --pin): a vendor arm's builder host must meet them too, or it falls back."""
    end, why = rotation_window()
    if end is None:
        return None, why
    fenced, fields = rotation_gate(primary)
    if fenced:
        return None, "builder rotation fenced: %s — today's builder, no row" % fenced
    # a confidential scope's build never goes to another vendor's arm (the Argon design's G3 wall, "confidential
    # bytes to Google: 0", which leaned on this fence before scope-rotation let such a scope draw): those arms weigh
    # 0 for it, as a road-less arm does, so its odds stay the claude arms' (1:2:2 draws as 1:2)
    confidential = bool(fields.get("confidential"))
    if origin:
        return None, "builder rotation fenced: an origin marker — today's builder, no row"
    weights, otext, owhy = _read_odds()
    if weights is None:
        return None, "builder rotation off: %s" % owhy
    # A size-pinned override never swaps sr-worker for the mid arm (or vice versa).
    if brief_class in ("gpt-big", "gpt-mid") and not any(weights[:2]):
        weights = tuple(w if ARMS[i][0] == brief_class else 0 for i, w in enumerate(weights))
    if not sum(weights):
        return None, "builder rotation off: %s gives every arm 0" % ODDS_KEY
    rolled = road_weights(weights, True)
    if confidential:
        rolled = tuple(w if ARMS[i][3] == "claude" else 0 for i, w in enumerate(rolled))
    if not sum(rolled):
        return None, "builder rotation off: %s weighs only arms with no road in dispatch yet" % ODDS_KEY
    forced = os.environ.get("DISPATCH_COIN")
    forced = forced if forced in [str(i) for i in range(len(ARMS))] else None
    if forced and not weights[int(forced)]:
        forced = None  # even a test pin cannot draw an arm the owner's odds weigh 0 (a road-less one it may: its fallback)
    coin = int(forced) if forced else coin_of(random.SystemRandom().randrange(sum(rolled)), rolled)
    name, agent, note = ARMS[coin][0], ARMS[coin][3], ""
    if agent != "claude":
        host, fb = (None, "a confidential scope never runs on %s" % agent) if confidential \
            else (None, "no road for %s in dispatch yet (run_vendor)" % agent) if not has_road(agent, True) \
            else builder_host(primary, AGENT_NEED[agent], needs, pin)
        if fb:
            name, note = ARMS[0][0], " — fallback to %s: %s" % (ARMS[0][0], fb)
        else:
            note = " — builder host %s fresh" % host
    return "%s:%d:%s:%d" % (name, coin, end.isoformat(), bool(forced)), "%s; odds %s; coin %d: %s%s%s" % (
        why, otext, coin, ARMS[coin][0], " (forced)" if forced else "", note)


def arm_of(word):
    """The record's `arm` for a word, or None for one that does not read. Its coin is its arm's, or a vendor arm's coin
    under opus-high: the fallback, drawn there and run as Opus (`fallback`, true)."""
    w = word or ""
    if not WORD_RE.fullmatch(w):
        return None
    name, coin, until, forced = w.split(":")
    coin = int(coin)
    fallback = ARMS[coin][0] != name
    if fallback and (name != ARMS[0][0] or ARMS[coin][3] == "claude"):
        return None
    try:
        datetime.date.fromisoformat(until)
    except ValueError:
        return None
    run = ARMS[0] if fallback else ARMS[coin]
    out = {"name": run[0], "model": run[1], "effort": run[2], "coin": coin, "until": until, "forced": forced == "1",
           "agent": run[3]}
    if fallback:
        out["fallback"] = True
    return out


def word_of(arm):
    return "%s:%d:%s:%d" % (arm["name"], arm["coin"], arm["until"], bool(arm["forced"]))


def fallback_word(word):
    """The Opus word in place of a vendor arm's word (the draw's, the fire's and the queue's re-draw), else None."""
    arm = arm_of(word)
    if not arm or arm["agent"] == "claude":
        return None
    return word_of(dict(arm, name=ARMS[0][0]))


def need_of(word):
    """The feature a host must declare to run WORD's arm, or None (a claude arm, a fallback, a word that does not read)."""
    arm = arm_of(word)
    return AGENT_NEED.get(arm["agent"]) if arm else None


@contextlib.contextmanager
def rotation_lock():
    os.makedirs(LOGS, exist_ok=True)
    with open(os.path.join(LOGS, ROTATION_LOG + ".lock"), "a") as lk:
        fcntl.flock(lk, fcntl.LOCK_EX)
        try:
            yield os.path.join(LOGS, ROTATION_LOG)
        finally:
            fcntl.flock(lk, fcntl.LOCK_UN)


def write_row(arm, a):
    """One row for the run, or why none: the fence asked again here, as autofinish-run's rotation_row does."""
    fenced, scope = rotation_gate(a.repo)
    if fenced:
        return "no builder row: %s" % fenced
    odds = read_odds()[0]
    odds = road_weights(odds, True) if odds else odds   # the odds the draw rolled by: a road-less arm weighs 0
    row = {"ts": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
           "host": os.environ.get("DISPATCH_HOST") or common.host_name(),
           "repo": os.path.basename(a.repo), "primary": a.repo, "branch": a.branch, "topic": a.topic,
           "session": a.session, "account": a.account or None, "queue": a.queue or None,
           "arm": arm["name"], "coin": arm["coin"], "forced": arm["forced"], "model": arm["model"],
           "effort": arm["effort"], "until": arm["until"], "brief_class": a.brief or None,   # never `brief`: a run record's `brief` is a path
           # the agent that ran it, and the arm the coin drew: another than `arm` only on a fallback (Opus in a vendor
           # arm's place, no builder host fresh or no road for it; trim keeps those out of the vendor arm's rows)
           "agent": arm["agent"], "drawn": ARMS[arm["coin"]][0], "fallback": bool(arm.get("fallback")),
           # the odds as this host reads them now (the word does not carry the draw's): `o:s:a` since S3 of the Argon
           # doc, `n/d` (Sonnet in d) before it — odds_of reads both; a word drawn before a change and fired after it
           # says the new odds. None when the limit does not read here
           "odds": odds_text(odds) if odds else None,
           # the scope that let it rotate, and whether it is confidential: trim counts such a row in its arm
           # tallies only, never naming it (trimlib's collect_fence)
           "scope": scope.get("scope"), "confidential": bool(scope.get("confidential"))}
    end = getattr(a, "end", None)
    if end:
        row.update({k: end.get(k) for k in ("conversation", "cost", "turns", "rounds", "outcome", "ended", "last_answer")})
    row["arm_source"] = "fallback" if arm.get("fallback") else ("pinned" if arm["forced"] else "coin")
    with rotation_lock() as path:
        with open(path, "a") as f:
            f.write(json.dumps(row, ensure_ascii=False) + "\n")
    return None


def main(argv):
    ap = argparse.ArgumentParser(prog="buildercoin.py")
    sub = ap.add_subparsers(dest="cmd", required=True)
    d = sub.add_parser("draw"); d.add_argument("repo"); d.add_argument("--needs", default=""); d.add_argument("--pin", default="")
    d.add_argument("--brief-class", default=""); d.add_argument("--origin", default="")
    w = sub.add_parser("arm"); w.add_argument("word"); w.add_argument("--repo", default="")
    r = sub.add_parser("row"); r.add_argument("word")
    for k in ("--repo", "--branch", "--topic", "--session"):
        r.add_argument(k, required=True)
    r.add_argument("--account", default=""); r.add_argument("--queue", default="")
    r.add_argument("--brief", default="")   # no choices: a class this list lacks must not lose the row (dispatch's || true)
    sub.add_parser("specced"); sub.add_parser("rotates"); sub.add_parser("odds"); sub.add_parser("grammar")
    n = sub.add_parser("need"); n.add_argument("word")
    fb = sub.add_parser("fallback"); fb.add_argument("word")
    a = ap.parse_args(argv)
    if a.cmd == "grammar":
        print(WORD_GRAMMAR)
        return 0
    if a.cmd == "odds":
        # `regatta limit`'s trial read: the value back as the draw reads it, or exit 2, refused (never 1: a crash)
        w, text, why = _read_odds()
        if w is None:
            print("buildercoin.py: %s" % why, file=sys.stderr)
            return 2
        print(text)
        return 0
    if a.cmd == "specced":
        return 0 if specced(sys.stdin.read()) else 1
    if a.cmd == "rotates":
        c = rotates(sys.stdin.read())
        if c:
            print(c)
        return 0 if c else 1
    if a.cmd == "draw":
        word, why = draw(os.path.realpath(a.repo), [n.strip().lower() for n in a.needs.split(",") if n.strip()], a.pin.strip().lower(), a.brief_class, a.origin)
        if word:
            print(word)
        # with no key file the start is unchanged, said nothing (the finisher's `arm=off` rule)
        if word or "no %s" % ROTATION_KEY not in why:
            print(why, file=sys.stderr)
        return 0
    arm = arm_of(a.word)
    if arm is None:
        print("buildercoin.py: %r is no builder arm" % a.word, file=sys.stderr)
        return 1
    if a.cmd == "arm":
        if a.repo:
            # at fire time: the switch and its end stop a word drawn before them, and a repo fenced since the draw
            # runs today's builder with no arm, so its run, record, row and log agree
            end, why = rotation_window()
            fenced, fields = rotation_gate(os.path.realpath(a.repo)) if end else (None, {})
            if end is None or fenced:
                print(why if end is None else "fenced: %s" % fenced)
                return 1
            if datetime.date.fromisoformat(arm["until"]) < datetime.date.today():
                print("its window ended %s" % arm["until"])
                return 1
            # the odds again: the owner's weight of 0 for the drawn arm stops a word drawn before it, as the switch does
            w, why = read_odds()
            if w is None:
                print("builder odds: %s" % why)
                return 1
            if not w[arm["coin"]]:
                print("%s gives %s 0 now" % (why, ARMS[arm["coin"]][0]))
                return 1
            # the fire-time pre-flight: a vendor arm with no road in this dispatch runs as its Opus fallback, recorded so
            # (never the draw's DISPATCH_COIN_ROADS: dispatch would start `claude` on another vendor's model)
            # and a confidential scope's never leaves for another vendor (G3), whatever word it carries
            if arm["agent"] != "claude" and (not has_road(arm["agent"]) or fields.get("confidential")):
                arm = arm_of(fallback_word(a.word))
        print(arm["model"], arm["effort"], word_of(arm), json.dumps(arm, separators=(",", ":")))
        return 0
    if a.cmd == "need":
        print(need_of(a.word) or "")
        return 0
    if a.cmd == "fallback":
        print(fallback_word(a.word) or a.word)
        return 0
    a.repo = os.path.realpath(a.repo)
    why = write_row(arm, a)
    if why:
        print(why, file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
