#!/usr/bin/env python3
"""force_mark: the owner's typed message asking for force marks the session for one force run.

UserPromptSubmit. dispatch-queue S4 (docs/dispatch-queue-2026-10-25.md, D3-A; the contract's
"Priorities and the force"): `dispatch --priority force` from an attended session passes only on the
owner's words, and this hook is how dispatch hears them. A prompt whose own words ask for force (PHRASE:
"use the force", or force or forcing as a word, any case; since 2026-10-30, the owner's words
in any wording) writes the mark, `force/<session_id>` in run-seed's cache folder (dispatch's
$cache); every other prompt the owner types in that session removes it, so the mark lives for the turn the owner said it in. dispatch spends
it on use: one phrase, one run. A --next inherits force as high, never as force.

Not the owner's words, so no mark (the frame filters):
- a prompt carrying `agent_id` (a subagent's), which neither writes nor clears the session's mark, or
  starting `<task-notification` or `<agent-message`;
- hail's frame (`HAIL event|report|ask from … — `) and sessionpipe control's (`Message via <host>
  (sessionpipe control, …):`), on any line: a peer's or a device's message relayed into the prompt, and
  every line after the frame is that message, never the owner's;
- the phrase inside quotes ("…", '…', “…”, ‘…’, `…`), a fenced block, a `>` quote line, a
  `<pasted_content>` block or a `<system-reminder>` block: text the owner pasted or quoted, never said.

An unattended session (CLAUDE_UNATTENDED) is never marked: its prompt is dispatch's, not the owner's.
checkpoint.py denies every session a hand write of the mark's folder (FORCE_DIR) and a run of this hook
by hand, so no session writes one by accident (checkpoint guards accidents: a path spelled through `cd` or a
variable passes). A negated phrase ("don't use the force") is no mark. A prompt that is
not the owner's (a notification, an agent message, a frame from its first line) leaves the mark as it is.
Wiring: one line in the overlay's `bootstrap.sh --hooks` (S4), on every host.

Never exits non-zero (exit 2 on UserPromptSubmit erases the prompt), stdlib, Python 3.9.
Tests: modules/wharf-runs/tests/test_priority.sh. No seam: the folder is under HOME, as dispatch reads it.
"""
import json
import os
import bisect
import re
import sys
from pathlib import Path

# Any wording that asks for force, not one phrase (the owner, 2026-10-30: "accept any phrase that suggests use
# of force … I don't want to rewrite my words for your convenience"): "use the force", "force it", "help force
# anything", "forcing it through". The landing review's cases settled what is no ask: a flag or a rank named
# (`--force`, `--priority force`), a word inside another (workforce, forceful), a description ("forced to
# rebase", "brute force"), and git's and the OS's own force verbs, with any spacing or dash between. The third
# review: a verb matches as a prefix (force-pushed, force quits), and the feature's own nouns (the force mark,
# floor, rank, force-ok) and "the/a force" are talk about force, not an ask; the rank named is judged on the
# text before it (RANK: any spelling of `--priority`). Dashes count as an
# ASCII one: an autocorrected —force or –force is the flag named (the fourth landing review, 2026-10-31).
VERBS = (r"push|pull|quit|kill|reload|update|delete|restart|reboot|stop|close|remove|rm|with-lease|merge|"
         r"checkout|add|unlink|eject|unmount|shutdown|install|uninstall|refresh|sync|overwrite|"
         r"reinstall|recreate|rebuild|reset|unwrap|fetch|clean|rebase|commit|tag|link|move|mv|exit|terminate|"
         r"renew|load|touch")
NOUNS = r"mark|marks|rank|entry|entries|floor|ok|flag|option|mode|field|be|majeure|multiplier"
PHRASE = re.compile(r"(?:\buse the |(?<![-\w—–])(?<!brute )(?<!\bthe )(?<!\ba ))forc(?:e|ing)\b"
                    r"(?![\s-]*(?:%s))(?![\s-]*(?:%s)\b)(?![=.]\w)" % (VERBS, NOUNS), re.I)
# the text just before a mention: the rank flag named (any dash or spacing) is talk, no ask; something chosen
# over force ("rather than force") refuses the whole message. Neither reaches across a comma, so "instead of
# waiting, force it" and "top priority: force queue-s4" still ask (the re-probe, 2026-10-30).
RANK = re.compile(r"(?:--?|[—–])priority[\s=:]*$", re.I)
OVER = re.compile(r"\b(?:instead of|rather than|anything but|other than)\s+(?:\w+\s+){0,2}$", re.I)
# a determiner beyond the/a, or a compound noun's head, before a mention is talk about force ("that force run",
# "your force check", "task force", "in force"; the fourth landing review, 2026-10-31): that mention is skipped
TALK = re.compile(r"\b(?:this|that|these|those|your|my|our|their|its|his|her|which|whose|task|police|air|armed|"
                  r"labou?r|work|in|de)\s+$", re.I)
LOOKBACK = 300   # chars of context read before a mention: the whole prefix per mention went quadratic on long prompts
HAIL_FRAME = re.compile(r"^[ \t]*HAIL (event|report|ask) from .+ — ", re.M)   # bin/hail's FRAME_RE
PIPE_FRAME = re.compile(r"^[ \t]*Message via \S+ \(sessionpipe control\b", re.M)   # sessionpipe's frame(), 0.x
NOT_OWNERS = ("<task-notification", "<agent-message")
# what the owner quoted or pasted rather than said: cut before the phrase is looked for
QUOTED = [re.compile(p, re.S) for p in (
    r"<pasted_content\b.*?</pasted_content>", r"<system-reminder>.*?</system-reminder>",
    # VS Code's blocks (an open file's path, a selection; the fourth landing review): keel's doc_answers cuts the same
    r"<(ide_[a-z_]+)>.*?</\1>",
    r"```.*?```", r"`[^`\n]*`", r"(?m)^[ \t]*>.*$",
    # a curly single quote closes at a ’ no letter follows: ‘don’t force it’ is one quote (the second landing review)
    r'"[^"\n]*"', r"“[^”\n]*”", r"‘[^\n]*?’(?!\w)", r"(?<!\w)'[^'\n]*'(?!\w)")]


def mark_dir():
    return Path.home() / "Library" / "Caches" / "run-seed" / "force"   # dispatch's $cache/force


def owners_words(prompt):
    """The prompt's own words with every quoted, pasted or framed part cut, or "" when the whole prompt is
    a frame or a notification (not the owner's message at all)."""
    p = prompt or ""
    if p.lstrip().startswith(NOT_OWNERS):
        return ""
    for rx in (HAIL_FRAME, PIPE_FRAME):   # a frame on any line: it and all after it are the relayed message
        m = rx.search(p)
        if m:
            p = p[:m.start()]
    for rx in QUOTED:
        p = rx.sub(" ", p)
    return p


# A refusal near the ask makes it no ask: a refusing word within WINDOW words either side of it, punctuation
# ignored. Two landing reviews (2026-10-30) found refusals a two-words-back check and then a per-clause check
# missed: "no force, high is enough", "Force? No.", "please don't, force is overkill", "Don't, under any
# circumstances, force it", "No need for high, force or critical". The window keeps the owner's own "do force
# priority instead - we want to get them as soon as possible, so they don't block other work" (its "don't" 13
# words on) an ask. Erring toward no mark costs the owner one retyped word. And the mark is a permission, not an
# order: a session still has to choose `--priority force` from what the owner asked. The third review: a
# contraction typed without its apostrophe ("dont force it") refuses too, a token starts at a letter so a
# straight-quoted 'don't force it' is read, a refusal just before any mention vetoes the whole message ("Never
# use force on these. … the force rank is only for outages."), and a mention in a question refuses the message
# ("why did you force it?"; "can you force it?" and "Should we force it? Yes, force it." err to none).
NEGATED = re.compile(r"^(?:no|not|never|without|avoid|avoiding|stop|nor|neither|overkill|unnecessary|needless"
                     r"|skip|forget|nah|nope|except|excessive|hold"
                     r"|dont|cant|wont|isnt|arent|wasnt|werent|doesnt|didnt|shouldnt|wouldnt|couldnt|havent|hasnt"
                     r"|aint|neednt|\w+n['’]t)$", re.I)
WORD = re.compile(r"\w[\w'’-]*")
WINDOW = 6
VETO = 3   # a refusing word this close before any mention refuses the whole message


def says_force(data):
    words = owners_words(data.get("prompt"))
    toks = [(m.start(), m.group()) for m in WORD.finditer(words)]
    starts = [at for at, _ in toks]
    asked = False
    for m in PHRASE.finditer(words):
        before = words[max(0, m.start() - LOOKBACK):m.start()]
        if RANK.search(before) or TALK.search(before):
            continue
        if OVER.search(before):
            return False
        sentence = (re.search(r"[^.!?\n]*$", before).group()
                    + re.match(r"[^.!?\n]*[.!?]?", words[m.start():m.start() + LOOKBACK]).group())
        if sentence.rstrip().endswith("?"):
            return False   # a question about force vetoes the message: "is force needed? I doubt force helps"
        i = bisect.bisect_left(starts, m.start())
        if any(NEGATED.match(w) for _, w in toks[max(0, i - VETO):i]):
            return False
        near = toks[max(0, i - WINDOW):i] + toks[i:i + WINDOW + (3 if m.group().lower().startswith("use") else 1)]
        asked = asked or not any(NEGATED.match(w) for _, w in near)
    return asked


def not_owners(prompt):
    """The whole prompt is someone else's: a notification, an agent message, a frame on its first line."""
    s = (prompt or "").lstrip()
    return s.startswith(NOT_OWNERS) or bool(HAIL_FRAME.match(s) or PIPE_FRAME.match(s))


def main():
    try:
        data = json.load(sys.stdin)
    except ValueError:
        return
    if os.environ.get("CLAUDE_UNATTENDED") or data.get("agent_id") or not_owners(data.get("prompt")):
        return   # dispatch's prompt, a subagent's, a notification or a frame: not the owner typing, no turn of theirs to end
    sid = str(data.get("session_id") or "")
    if not re.fullmatch(r"[A-Za-z0-9_-]{1,100}", sid):
        return
    try:
        d = mark_dir()
        f = d / sid
        if says_force(data):
            d.mkdir(parents=True, exist_ok=True)
            f.write_text("%s\n" % (data.get("cwd") or ""))
        elif f.exists():
            f.unlink()
    except OSError:
        pass   # a hook never costs the owner the prompt


if __name__ == "__main__":
    try:
        main()
    except Exception:  # noqa: BLE001
        pass
    sys.exit(0)
