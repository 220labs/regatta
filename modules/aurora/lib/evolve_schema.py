"""The records Evolve's code reads and writes, as data a validator walks (Evolve S3; stdlib, 3.9).

docs/self-improvement-scope-pass-2026-10-30.md fixes the finding's fields and its lifecycle,
docs/self-improvement-loop-2026-10-30.md the ledgers and the knee rule's `found_by` / `also_found_by`,
docs/self-improvement-portfolio-2026-10-30.md the six routes and `action_id`. Each schema here is a dict
field -> spec, a spec a dict of:

  t         "str" | "int" | "num" | "bool" | "date" | "time" | "list" | "dict" | "any"
  enum      the allowed values (a str field)
  null      True: None is allowed
  opt       True: the field may be absent
  of        a list's item spec, or a dict's nested schema (a dict of specs)
  min, max  a number's bounds, a list's length bounds
  re        a str field's pattern (fullmatch)

`validate(kind, record)` returns a list of one-line problems, [] when the record holds; no field a model
wrote is trusted past it. A record may carry fields beyond the schema (a later step adds them): they are
kept, never refused, so an older reader validates a newer record.

**The lifecycle in three families** (PR 314): an answer, a prepared PR and an observed benefit are three
facts, never one state, so a finding's `status` holds one value per family — proposal `proposed | routed
| parked | killed`, execution `reserved | seeded | queued | running | prepared | shipped | failed |
cancelled` (null until the portfolio reserves it), outcome `pending | benefit_observed | closed_verified |
closure_regression` (null until it ships).

**action_id** = sha256 of (finding id, action version, target scope), the first 16 hex; the cycle id is
provenance only, so next week's retry of the same action keys the same and is refused, and a revised
action (a new `action_version`) is a new one — which holds only for a finding id that names no cycle, so
an id holding its own (`w45`, `2026-W45`, its date) is refused.

**Where plumb reads findings.** plumb's asks matcher (Ring 0, S1) lists findings from
`<log dir>/evolve/findings/*.json`, each with `id`, `date` and `need`; the pass writes
`<anchor>/evolve/<date>.findings.json`. The finding carries `date` and `need` for it; S5 writes plumb's copy of
an open scope's findings there as a list of finding objects (plumb reads a list or one object, never the
findings file's wrapper), and plumb, which prints `status` as one word, is taught to read
`status["proposal"]` in the same change (a confidential scope's findings never leave its anchor). Public code: no host, login or person in any default here.
"""
import datetime as dt
import hashlib
import json
import math
import re

VERSION = 1

KINDS = ("gap", "blind_spot", "strength")
# the asks ledger's levels (plumb's asks, Ring 0), so an ask's level maps onto a lens's cells
LEVELS = ("PS", "CM", "EN", "TH", "PW", "KL", "UX", "CB", "PE", "LP")
ROUTES = ("build", "sound", "pin", "propose", "park", "kill")
CAPITALIZE = ("double_down", "transfer_trial", "extract", "sounding")
PRIVACY = ("open", "guarded", "confidential")
SIZES = ("xs", "s", "m", "l", "xl")
PROPOSAL = ("proposed", "routed", "parked", "killed")
EXECUTION = ("reserved", "seeded", "queued", "running", "prepared", "shipped", "failed", "cancelled")
OUTCOME = ("pending", "benefit_observed", "closed_verified", "closure_regression")
# the coverage register's cell states (the scope-pass component's "By construction"): `stale` a source read
# but old, `inaccessible` one declared and unreadable on this yard — two facts, never one word
CELL_STATES = ("observed", "stale", "source_missing", "unread", "inaccessible", "excluded", "not_applicable", "fenced")
RECEIPTS = ("complete", "quiet", "held", "failed", "not_due")
CAUSES = ("anticipated", "M1", "M2", "M3", "M4", "M5", "M6", "M7", "J", "unknown")
CONFORMANCE = ("dead", "holds", "violated", "worked_around", "unknown")
HEX16 = r"[0-9a-f]{16}"
CYCLE = r"\d{4}-W\d{2}"
DAY = r"\d{4}-\d{2}-\d{2}"


def S(t, **kw):
    kw["t"] = t
    return kw


EVIDENCE_REF = {"source": S("str", min=1), "count": S("int", min=0), "path": S("str", opt=True, null=True),
                "time": S("time", opt=True, null=True)}
BENEFIT = {"check": S("str", min=1), "due": S("date")}

FINDING = {
    "id": S("str", re=r"[a-z0-9][a-z0-9._-]{2,80}"),
    "theme_id": S("str", null=True),
    "scope": S("str"),
    "cycle": S("str", re=CYCLE),
    "date": S("date"),                            # the day found: plumb's matcher lists findings dated before an ask
    "need": S("str", min=1),                             # the need in one line, which plumb's matcher reads beside the title
    "title": S("str", opt=True),
    "process_revision": S("str", min=1),
    "kind": S("str", enum=KINDS),
    "level": S("str", enum=LEVELS),
    "lens": S("str", min=1),
    "goal_ref": S("str", null=True),
    "evidence_refs": S("list", of=S("dict", of=EVIDENCE_REF), min=1),
    "source_freshness": S("dict"),
    "observation": S("str", min=1),
    "hypothesis": S("str"),                       # "unknown" allowed
    "counterevidence": S("str", null=True),
    "p_success": S("num", min=0, max=1, null=True),
    "intervention": S("str", min=1),
    "alternatives": S("list", of=S("str")),
    "smallest_test": S("str", min=1),
    "capitalize_as": S("str", enum=CAPITALIZE, null=True, opt=True),
    "acceptance_check": S("str", min=1),
    "benefit_check": S("dict", of=BENEFIT),
    "observation_window": S("int", min=0),        # days
    "outcome_class": S("str"),
    "reversible": S("bool"),
    "auto_constructible": S("bool"),
    "auto_activatable": S("bool"),
    "size": S("str", enum=SIZES),
    "est_list_usd": S("num", min=0),
    "owner_minutes": S("num", min=0),
    "maintenance_cost": S("str", null=True),
    "proposed_route": S("str", enum=ROUTES),
    "privacy_class": S("str", enum=PRIVACY),
    "wake_when": S("str", null=True, opt=True),
    "cooldown": S("int", min=0, null=True, opt=True),
    "prior_ids": S("list", of=S("str")),
    "supersedes": S("str", null=True),
    "found_by": S("str", min=1),                         # the arm that found it (the knee rule)
    "also_found_by": S("list", of=S("str")),      # every other arm that found it on the same packet
    "status": S("dict", of={"proposal": S("str", enum=PROPOSAL),
                            "execution": S("str", enum=EXECUTION, null=True),
                            "outcome": S("str", enum=OUTCOME, null=True)}),
    "action_version": S("int", min=1),
    "target_scope": S("str", min=1),
    "action_id": S("str", re=HEX16),
}
FINDINGS_FILE = {"version": S("int", min=1), "scope": S("str"), "cycle": S("str", re=CYCLE),
                 "cutoff": S("time"), "findings": S("list", of=S("dict", of=FINDING), max=5)}

CELL = {"lens": S("str"), "source": S("str"), "state": S("str", enum=CELL_STATES),
        "outcome": S("str", null=True), "stakeholder": S("str", null=True), "activity": S("str", null=True),
        "reader": S("str", null=True), "age_days": S("num", null=True), "cited": S("int", min=0, null=True),
        "owner_read": S("bool", null=True), "required": S("bool"), "why": S("str", null=True),
        "review": S("date", null=True, opt=True), "overdue": S("bool", opt=True)}
COLLECTOR = {"id": S("str"), "required": S("bool"), "sources": S("list", of=S("str")),
             "fresh": S("bool"), "why": S("str", null=True)}
MANIFEST = {"scope": S("str"), "cutoff": S("time"), "since": S("time", null=True),
            "collectors": S("list", of=S("dict", of=COLLECTOR)),
            "hashes": S("dict", of={"lenses": S("str"), "profile": S("str", null=True, opt=True),
                                    "north_star": S("str", null=True), "registry": S("str", opt=True)}),
            "refs": S("dict", opt=True), "pass_session": S("str", opt=True),
            "changed": S("list", of=S("str")), "changed_sources": S("list", of=S("str")),
            "overdue": S("list", of=S("str")), "quiet_ok": S("bool"), "why": S("list", of=S("str")),
            "not_judged": S("list", of=S("str"))}
COVERAGE = {"version": S("int", min=1), "time": S("time"), "lenses_sha": S("str"),
            "scopes": S("list", of=S("dict", of={"scope": S("str"), "confidential": S("bool"),
                                                 "counts": S("dict"), "cells": S("list", of=S("dict", of=CELL)),
                                                 "manifest": S("dict", of=MANIFEST), "profile_error": S("bool", opt=True)})),
            "surface": S("dict", of={"items": S("int", min=0), "unobserved": S("list", of=S("str")),
                                     "fenced": S("int", min=0), "ignored": S("int", min=0)}),
            "bad_scopes": S("int", min=0, opt=True), "skipped_confidential": S("int", min=0, opt=True)}

# the night's receipt (the scope-pass component's Output): one word, the cutoff, the cost; a confidential
# scope's export fields beside it, as scope-pass's receipt() writes them — the sha256 of the bytes that left
RECEIPT = {"receipt": S("str", enum=RECEIPTS), "scope": S("str"), "cycle": S("str", re=CYCLE),
           "day": S("date", opt=True), "cutoff": S("time", opt=True, null=True),
           "cost_usd": S("num", min=0, null=True, opt=True),
           "records_ref": S("str", opt=True, null=True), "sha256": S("str", re=r"[0-9a-f]{64}", opt=True, null=True),
           "judge_rev": S("str", opt=True, null=True), "manifest_sha": S("str", opt=True, null=True),
           "time": S("time", opt=True)}

# the ledgers: plumb's asks/ (S1 writes the first three), the portfolio's reservation and start rows (S6)
ASK = {"id": S("str"), "date": S("date"), "ts": S("time"), "week": S("str", re=CYCLE), "project": S("str", null=True),
       "session": S("str"), "sieve": S("str"), "target": S("str", opt=True), "kind": S("str", opt=True, null=True),
       "level": S("str", opt=True, null=True), "detect": S("str", opt=True, null=True),
       "theme": S("str", opt=True, null=True),
       # as plumb's match_rows writes it: the label, and for an anticipated ask the finding and the lead in days
       "match": S("dict", opt=True, null=True, of={"label": S("str", enum=CAUSES), "finding": S("str", opt=True),
                                                    "lead_days": S("int", opt=True)})}
THEME = {"level": S("str", null=True), "kind": S("str", null=True), "sessions": S("dict"),
         "first": S("dict", of={"session": S("str"), "date": S("date")}), "last": S("dict", opt=True),
         "count": S("int", min=0, opt=True), "shipped": S("dict", null=True), "sig": S("list", opt=True)}
OVERRULE = {"id": S("str"), "date": S("date", null=True), "lens": S("str", opt=True, null=True),
            "route": S("str", opt=True, null=True), "gist": S("str", opt=True, max=240)}
RESERVATION = {"action_id": S("str", re=HEX16), "cycle": S("str", re=CYCLE), "provider": S("str"),
               "arm": S("str"), "forecast_usd": S("num", min=0), "actual_usd": S("num", min=0, null=True),
               "at": S("time"), "state": S("str", enum=("held", "reconciled", "released"))}
START = {"action_id": S("str", re=HEX16), "kind": S("str", enum=("seed", "sounding", "build")),
         "at": S("time"), "cycle": S("str", re=CYCLE), "ref": S("str", null=True)}
CONFORMANCE_ROW = {"rule": S("str"), "class": S("str", enum=CONFORMANCE), "applied": S("int", min=0),
                   "breached_ok": S("int", min=0), "breached_failed": S("int", min=0), "blocked": S("int", min=0, opt=True),
                   "unknown": S("int", min=0, opt=True),
                   "sessions": S("int", min=0)}

SCHEMAS = {"finding": FINDING, "findings": FINDINGS_FILE, "coverage": COVERAGE, "cell": CELL, "manifest": MANIFEST,
           "receipt": RECEIPT, "ask": ASK, "theme": THEME, "overrule": OVERRULE, "reservation": RESERVATION,
           "start": START, "conformance": CONFORMANCE_ROW}


def action_id(finding_id, action_version, target_scope):
    """An action's identity: the cycle is never part of it (the portfolio component's barrier)."""
    raw = json.dumps([str(finding_id), int(action_version), str(target_scope)], separators=(",", ":"))
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()[:16]


def read_time(v, date_ok=False):
    """An ISO time read the same on every Python (3.9's fromisoformat refuses `+0100` and compact forms that
    3.11's accepts: round 5): a dashed date, then `T` and a time unless DATE_OK, a `Z` or `±HH[:]MM` offset."""
    m = re.fullmatch(r"(\d{4}-\d{2}-\d{2})(?:[T ](\d{2}:\d{2}(?::\d{2})?)(?:\.(\d{1,6}))?(Z|[+-]\d{2}:?\d{2})?)?", str(v))
    if not m or (m.group(2) is None and not date_ok) or (m.group(3) and m.group(2).count(":") != 2):
        return None
    # 3.9's fromisoformat takes a fraction of 3 or 6 digits only, 3.11's 1 to 6: padded to 6 (the finish review)
    frac = "." + m.group(3).ljust(6, "0") if m.group(3) else ""
    off = m.group(4) or ""
    off = "+00:00" if off == "Z" else off if not off or ":" in off else off[:3] + ":" + off[3:]
    try:
        return dt.datetime.fromisoformat(m.group(1) + ("T" + m.group(2) + frac if m.group(2) else "") + off)
    except ValueError:
        return None


def _is_time(v):
    return read_time(v) is not None


def _finite(v):
    try:
        return math.isfinite(v)
    except OverflowError:   # an int too large for a float is no amount anyone means
        return False


def _is_date(v):
    try:
        dt.date.fromisoformat(str(v))
        return True
    except ValueError:
        return False


def check(spec, v, where, out):
    t = spec["t"]
    if v is None:
        if not spec.get("null"):
            out.append("%s: null where a %s is needed" % (where, t))
        return
    ok = {"str": isinstance(v, str), "int": isinstance(v, int) and not isinstance(v, bool),
          "num": isinstance(v, (int, float)) and not isinstance(v, bool) and _finite(v), "bool": isinstance(v, bool),
          "date": isinstance(v, str) and bool(re.fullmatch(DAY, v)) and _is_date(v),
          "time": isinstance(v, str) and _is_time(v), "list": isinstance(v, list), "dict": isinstance(v, dict),
          "any": True}[t]
    if not ok:
        out.append("%s: %r is no %s" % (where, v if not isinstance(v, (dict, list)) else type(v).__name__, t))
        return
    if "enum" in spec and v not in spec["enum"]:
        out.append("%s: %r is not one of %s" % (where, v, " | ".join(spec["enum"])))
    if "re" in spec and not re.fullmatch(spec["re"], v):
        out.append("%s: %r does not read as %s" % (where, v, spec["re"]))
    n = len(v) if t in ("list", "str") else v if t in ("int", "num") else None
    if n is not None and "min" in spec and n < spec["min"]:
        out.append("%s: %s below %s" % (where, "length %d" % n if t in ("list", "str") else n, spec["min"]))
    if n is not None and "max" in spec and n > spec["max"]:
        out.append("%s: %s above %s" % (where, "length %d" % n if t in ("list", "str") else n, spec["max"]))
    if t == "list" and "of" in spec:
        for i, x in enumerate(v):
            check(spec["of"], x, "%s[%d]" % (where, i), out)
    if t == "dict" and "of" in spec:
        walk(spec["of"], v, where, out)


def walk(schema, rec, where, out):
    for k, spec in schema.items():
        if k not in rec:
            if not spec.get("opt"):
                out.append("%s.%s: missing" % (where, k) if where else "%s: missing" % k)
            continue
        check(spec, rec[k], "%s.%s" % (where, k) if where else k, out)


def validate(kind, rec, outcome_classes=None):
    """[problem] for REC against schema KIND; [] when it holds. A finding is also judged on the rules a
    field-by-field walk cannot say: action_id must be the hash of its own fields, a strength names how it
    is capitalised, the outcome only once something shipped, and the outcome class one lenses.json declares."""
    if kind not in SCHEMAS:
        return ["no schema %r (one of %s)" % (kind, ", ".join(sorted(SCHEMAS)))]
    if not isinstance(rec, dict):
        return ["the record is no object"]
    out = []
    walk(SCHEMAS[kind], rec, "", out)
    if kind == "finding":
        out += finding_rules(rec, outcome_classes)
    if kind == "findings" and isinstance(rec.get("findings"), list):
        for i, f in enumerate(rec["findings"]):
            if isinstance(f, dict):
                out += ["findings[%d]: %s" % (i, p) for p in finding_rules(f, outcome_classes)]
                if f.get("scope") != rec.get("scope") or f.get("cycle") != rec.get("cycle"):
                    out.append("findings[%d]: scope or cycle differs from the file's" % i)
    return out


def id_holds_cycle(fid, cycle, day):
    """Does the id carry the finding's own cycle (`2026-W45`, `w45`) or its own day (`2026-11-08`,
    `20261108`)? Only its own: `w64` or an 8-digit build number elsewhere is no cycle (round 4)."""
    low, marks = fid.lower(), []
    if isinstance(cycle, str) and re.fullmatch(CYCLE, cycle):
        marks += [cycle.lower(), "w" + cycle[-2:]]
    if isinstance(day, str) and re.fullmatch(DAY, day):
        marks += [day, day.replace("-", "")]
    return any(re.search(r"(?<![a-z0-9])%s(?![0-9])" % re.escape(m), low) for m in marks)


def finding_rules(f, outcome_classes=None):
    out = []
    if isinstance(f.get("id"), str) and id_holds_cycle(f["id"], f.get("cycle"), f.get("date")):
        out.append("id: holds a cycle (an action keys on a cycle-free id, so next week's retry is the same action)")
    try:
        if f.get("action_id") != action_id(f["id"], f["action_version"], f["target_scope"]):
            out.append("action_id: not hash(id, action_version, target_scope)")
    except (KeyError, TypeError, ValueError):
        pass
    if f.get("kind") == "strength" and not f.get("capitalize_as"):
        out.append("capitalize_as: a strength names how it is capitalised")
    if not f.get("wake_when") and f.get("cooldown") is None:
        out.append("wake_when | cooldown: one of the two")
    st = f.get("status") if isinstance(f.get("status"), dict) else {}
    if st.get("outcome") and st.get("execution") != "shipped":
        out.append("status.outcome: %r before anything shipped" % st.get("outcome"))
    if st.get("execution") not in (None, "cancelled") and st.get("proposal") != "routed":
        out.append("status.execution: %r on a proposal that is %r, not routed" % (st.get("execution"), st.get("proposal")))
    afb = f.get("also_found_by")
    if f.get("found_by") and isinstance(afb, list) and f.get("found_by") in afb:
        out.append("also_found_by: holds found_by itself")
    oc = f.get("outcome_class")
    if outcome_classes is not None and (not isinstance(oc, str) or oc not in outcome_classes):
        out.append("outcome_class: %r is no class lenses.json declares" % f.get("outcome_class"))
    return out


def describe(kind):
    """The schema as JSON-able data, for `evolve schema KIND`."""
    return SCHEMAS[kind]
