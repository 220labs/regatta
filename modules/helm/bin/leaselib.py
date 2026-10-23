"""The lease on a ship (skipper-resilience S4; the build's skipper component, "The lease"): one
file per ship, plans/<id>/skipper.json, saying who holds the ship now — the yard, or the scope's
skipper session — and at which generation. Every hand-over moves the generation by one, and every
acting verb (wharf apply --yard --plan, ask answer|relay --plan|apply --plan, helm skipper
--renew|--stand-down, autofinish-run under DISPATCH_SHIP) checks the caller's generation against it
through fence(): a former holder, or a session that never held the ship, is refused with one event
and exit 4. Raw git, orca and gh are not fenced (the design's K1 count is that check). `helm send`
(S7) is the one verb the design names that is not built yet: it calls fence(pid, "helm send") as
the others do.

    {"holder": "yard" | "skipper · <scope>", "scope": "<scope>", "host": "<yard host>",
     "account": "<label>" | null, "gen": N, "since": <epoch>, "until": <epoch> | null,
     "session": "<session id>" | null, "pid": N | null, "why": "<last transition>"}

Written only under helmlib.locked(pid), by an atomic replace; a plan with no file has no lease and
every verb behaves as before S4. A file that is there but does not read fails closed: fence()
refuses (the torn-registry trap's rule — an unreadable record is never read as "no lease").
Every transition but a renewal is one events.jsonl line with a `lease` key (state() reads only
lines with a `task`, so the board never sees them as a task): `picked up by` (the first skipper,
from the yard's gen 0), `taken by` (a later one, after a hand-back), `held by yard`, `lease lapsed`
(S5's tick), `renewal refused`, `stood down`, `skipper won't start` (S5), and `refused` for an
acting verb fenced out. Stdlib only, Python 3.9 (the yard's /usr/bin/python3); PLANS_DIR moves the
store, as helmlib's.
"""
import json
import os
from pathlib import Path

import helmlib

FILE = "skipper.json"
YARD = "yard"
TTL = 900          # a skipper's lease runs 15 minutes past its last renewal; the sidecar renews every 5
REFUSED_EXIT = 4   # what every fenced verb exits with on a refusal (wharf's 4 already reads "not yours now")
STAND_DOWN = "stand down (helm skipper --stand-down)"


class Unreadable(Exception):
    """skipper.json is there and does not read as a lease: no generation can be told from it."""


class Refused(Exception):
    """A take or a renewal the lease refuses; str() is the line the verb prints."""


def holder_of(scope):
    return "skipper · %s" % scope


def path(pid):
    return helmlib.plan_dir(pid) / FILE


def read(pid):
    """The lease, or None when the ship has none (no file, no plan, an id helmlib refuses); Unreadable
    when the file is there and is not a lease."""
    try:
        p = path(pid)
    except ValueError:
        return None
    try:
        text = p.read_text(encoding="utf-8")
    except FileNotFoundError:
        return None
    except OSError as e:
        raise Unreadable("%s: %s" % (p, e))
    except ValueError:   # UnicodeDecodeError: bytes no writer of ours makes
        raise Unreadable("%s is not UTF-8" % p)
    try:
        rec = json.loads(text)
    except ValueError:
        raise Unreadable("%s is not JSON" % p)
    gen = rec.get("gen") if isinstance(rec, dict) else None
    if not (isinstance(rec, dict) and isinstance(rec.get("holder"), str) and _int(gen) and gen >= 0):
        raise Unreadable("%s is not a lease (holder and gen)" % p)
    # every field a reader does arithmetic on, compares or signals is typed here, so a hand-edited
    # file fails closed in fence() instead of crashing lapsed() or SIGTERMing pid -1 (S4 finish review)
    until, pid_, sess, scope = rec.get("until"), rec.get("pid"), rec.get("session"), rec.get("scope")
    if not ((until is None or (_num(until) and until == until)) and (pid_ is None or (_int(pid_) and pid_ > 1))
            and (sess is None or isinstance(sess, str)) and isinstance(scope, str)):
        raise Unreadable("%s is not a lease (scope, until, session or pid)" % p)
    return rec


def _int(x):
    return isinstance(x, int) and not isinstance(x, bool)


def _num(x):
    return isinstance(x, (int, float)) and not isinstance(x, bool)


def _save(pid, rec):
    """The atomic replace: a reader sees the old lease or the new one, never half of either."""
    p = path(pid)
    tmp = p.with_name("%s.%d.tmp" % (FILE, os.getpid()))
    tmp.write_text(json.dumps(rec, indent=1, ensure_ascii=False, sort_keys=True), encoding="utf-8")
    tmp.replace(p)


def _event(pid, word, rec, **extra):
    ev = {"lease": word, "plan": pid, "holder": rec.get("holder"), "gen": rec.get("gen"), "scope": rec.get("scope"),
          "session": rec.get("session"), "host": helmlib.host(), "why": rec.get("why")}
    ev.update(extra)
    return helmlib.append_event(pid, ev)


def write_yard(pid, scope, host, why, event="held by yard"):
    """The yard holds the ship: gen 0 on a ship with no lease yet (wharf apply --yard), else the gen
    after the file's (a skipper stood down, or S5's tick saw a lapse). One event, `event`."""
    if not helmlib.plan_dir(pid).is_dir():
        raise FileNotFoundError("no ship %s here (%s)" % (pid, helmlib.plan_dir(pid)))
    with helmlib.locked(pid):
        cur = read(pid)   # Unreadable propagates: an unreadable lease is never overwritten as if absent
        rec = {"holder": YARD, "scope": scope, "host": host, "account": None, "gen": 0 if cur is None else cur["gen"] + 1,
               "since": helmlib.now(), "until": None, "session": None, "pid": None, "why": why}
        _save(pid, rec)
        _event(pid, event, rec)
    return rec


def take(pid, scope, session, pid_, account=None):
    """The scope's skipper takes a ship the yard holds: gen + 1, `until` a TTL away. The yard's first
    hold (gen 0) is a `picked up by`; a hold after a hand-back is a `taken by`. A ship this session
    holds already is returned as it is (no new gen). Refused for another scope's ship and while
    another session holds it: a lapsed holder is handed back by the yard (S5's tick) first, so the
    next skipper never takes a ship whose questions the hand-over has not re-hailed."""
    with helmlib.locked(pid):
        cur = read(pid)
        if cur is None:
            raise Refused("refused: ship %s has no lease (only a ship laid with wharf apply --yard has one)" % pid)
        if cur.get("scope") != scope:
            raise Refused("refused: ship %s is scope %s's, not %s's" % (pid, cur.get("scope"), scope))
        if cur["holder"] != YARD:
            if session and cur.get("session") == session:
                return cur
            raise Refused("refused: lease at gen %d held by %s (session %s) — not the yard's to hand on"
                          % (cur["gen"], cur["holder"], str(cur.get("session") or "?")[:8]))
        now = helmlib.now()
        rec = dict(cur, holder=holder_of(scope), gen=cur["gen"] + 1, since=now, until=now + TTL, session=session,
                   pid=pid_, account=account, why="taken from the yard at gen %d" % cur["gen"])
        _save(pid, rec)
        _event(pid, "picked up by" if cur["gen"] == 0 else "taken by", rec)
    return rec


def stand_down(pid, session):
    """This session's ship back to the yard at gen + 1 (`stood down`), checked and written under one
    lock: a ship the yard or another skipper took in between is left alone (Refused), never handed
    back a second time (S4 finish review)."""
    with helmlib.locked(pid):
        cur = read(pid)
        if cur is None or cur["holder"] == YARD or cur.get("session") != session:
            raise Refused("%s: no longer this session's — left as it is" % pid)
        return write_yard(pid, cur.get("scope"), cur.get("host") or helmlib.host(), "stood down: %s" % cur["holder"],
                          event="stood down")


def renew(pid, gen):
    """`until` moved a TTL on, at the caller's generation; refused (one `renewal refused` event) when it
    is not the file's, and on a ship the yard holds (nothing to renew: --hold takes it). No event on
    success: the renewal is the one transition left out of events.jsonl."""
    with helmlib.locked(pid):
        try:
            cur = read(pid)
        except Unreadable as e:
            raise Refused(unreadable_text(e))
        if cur is None:
            raise Refused("refused: ship %s has no lease to renew" % pid)
        if gen != cur["gen"] or cur["holder"] == YARD:
            text = refusal(cur, gen)
            _event(pid, "renewal refused", cur, caller_gen=gen, refused=text)
            raise Refused(text)
        rec = dict(cur, until=helmlib.now() + TTL)
        _save(pid, rec)
    return rec


def refusal(rec, gen):
    return "refused: lease at gen %d held by %s — you are gen %s; %s" % (
        rec["gen"], rec["holder"], "none" if gen is None else gen, STAND_DOWN)


def unreadable_text(e):
    return "refused: the lease does not read (%s) — no generation can be checked; the yard's to fix" % e


def check(pid, gen, rec=None):
    """None when GEN may act on the ship (or it has no lease), else the refusal an acting verb prints
    and exits 4 with. Writes nothing: fence() is the verbs' call, and it writes the event."""
    if rec is None:
        try:
            rec = read(pid)
        except Unreadable as e:
            return unreadable_text(e)
    if rec is None:
        return None
    if gen is None or gen != rec["gen"]:
        return refusal(rec, gen)
    return None


def last_held(pid, session):
    """The newest gen SESSION took this ship at, from its events, or None: what a former holder is told
    it is ("you are gen 1")."""
    best = None
    for e in helmlib.events(pid):
        if e.get("lease") in ("picked up by", "taken by") and e.get("session") == session and isinstance(e.get("gen"), int):
            best = e["gen"] if best is None else max(best, e["gen"])
    return best


def caller_gen(pid, rec, given=None, environ=None):
    """(gen, accepted-by-identity) — --gen N, else the file's gen when CLAUDE_CODE_SESSION_ID is the
    file's `session` (the skipper's own verbs), else SKIPPER_GEN, else the file's gen for a plain shell with no session id (the owner's). Any other session is refused by the mismatch: its
    gen is the last one it held (a former holder), or None. A SKIPPER_GEN that is no number is a
    refusal too (ValueError)."""
    env = os.environ if environ is None else environ
    if given is not None:
        return int(given), True
    sid = env.get("CLAUDE_CODE_SESSION_ID") or ""
    if sid and sid == rec.get("session"):
        # the holder's own session is at the file's gen on every ship it holds: SKIPPER_GEN is one
        # number per process and gens are per ship, so it is never asked first (S4 finish review)
        return rec["gen"], True
    raw = (env.get("SKIPPER_GEN") or "").strip()
    if raw:
        if not raw.isdigit():
            raise ValueError("refused: SKIPPER_GEN=%r is no generation" % raw[:40])
        return int(raw), True
    if not sid:
        return rec["gen"], True
    return last_held(pid, sid), False


def fence(pid, verb, given=None, environ=None, record=True):
    """The check every acting verb runs: None to go ahead (no ship, no lease, or the caller's gen is
    the lease's), else the refusal line to print before exiting REFUSED_EXIT. A refusal writes one
    `refused` event naming the verb, unless RECORD is false (a dry run writes nothing)."""
    if not pid:
        return None
    try:
        rec = read(pid)
    except Unreadable as e:
        text = unreadable_text(e)
        if record and helmlib.plan_dir(pid).is_dir():
            helmlib.append_event(pid, {"lease": "refused", "plan": pid, "verb": verb, "refused": text, "host": helmlib.host()})
        return text
    if rec is None:
        return None
    env = os.environ if environ is None else environ
    try:
        gen, ok = caller_gen(pid, rec, given, env)
    except ValueError as e:
        gen, ok, text = None, False, str(e)
    else:
        text = check(pid, gen, rec) if ok else refusal(rec, gen)
    if text and record:
        _event(pid, "refused", rec, verb=verb, caller_gen=gen, caller_session=env.get("CLAUDE_CODE_SESSION_ID") or None,
               refused=text)
    return text


def lapsed(pid, now=None, rec=None):
    """True when a skipper's lease is past its `until` (the yard's hold never lapses)."""
    if rec is None:
        try:
            rec = read(pid)
        except Unreadable:
            return False
    if not rec or rec.get("holder") == YARD or rec.get("until") is None:
        return False
    return (helmlib.now() if now is None else now) > float(rec["until"])


def ended(pid):
    """True once every ship recorded in the plan has ended (wharf's `ended` on its blueprint record):
    a landed ship's lease is history, never held or renewed."""
    bps = [r for r in ((helmlib.load_plan(pid) or {}).get("blueprints") or {}).values() if isinstance(r, dict)]
    return bool(bps) and all(r.get("ended") for r in bps)


def leases(scope=None, include_ended=False):
    """[(plan id, lease or Unreadable)] for every ship here with a lease file — of SCOPE when given (an
    unreadable one has no scope, so it is listed only without SCOPE) — ended ships left out unless asked."""
    out = []
    for pid in helmlib.list_plans():
        try:
            rec = read(pid)
        except Unreadable as e:
            if scope is None:
                out.append((pid, e))
            continue
        if rec is None or (scope is not None and rec.get("scope") != scope):
            continue
        if not include_ended and ended(pid):
            continue
        out.append((pid, rec))
    return out


def record_path(scope, host=None):
    """S5's per-scope skipper record, `<manager_dir>/<host>-<scope>.json` (the proposal's seam beside
    asklib.standing_manager's `<host>.json`): S4 reads and deletes it, S5's runner writes it."""
    import asklib   # lazily: ask poll and keel's Stop lint never load this file
    return asklib.manager_dir() / ("%s-%s.json" % (host or helmlib.host(), scope))


def read_record(scope, host=None):
    try:
        rec = json.loads(Path(record_path(scope, host)).read_text())
    except (OSError, ValueError):
        return None
    return rec if isinstance(rec, dict) else None
