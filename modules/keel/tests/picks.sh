#!/usr/bin/env bash
# rabbit-holes S3 (docs/rabbit-holes-2026-11-02.md, D3-A): the pick class of an answer (`pick_of`: letter,
# recommended, none), intake's reopen of a no-pick answer (merge, `keel pull`), `lint --strict`, `parse` and
# `status --json`, and the hold `keel held` reads from git — released only by the owner's new Answer or a
# `Design-pass:` commit, never a builder's reply. The classifier's cases are the hand-check's set
# (docs/rabbit-holes-2026-11-02/out/answers-handcheck.md): its 5 true no-picks and its false positives, each
# answer's words kept, names and hosts made generic. Scratch repos only; no network.
#   bash modules/keel/tests/picks.sh
set -u
T=$(mktemp -d); T=$(cd "$T" && pwd -P); trap 'rm -rf "$T"' EXIT
. "$(dirname "$0")/config.sh"; keel_config "$T/config"
B="$(cd "$(dirname "$0")/../bin" && pwd)"
unset CLAUDE_UNATTENDED REGATTA_UNATTENDED CLAUDE_CODE_ENTRYPOINT CLAUDE_CODE_SESSION_ID CLAUDE_CODE_DISABLE_BACKGROUND_TASKS
export MEMO_STATE_DIR="$T/state" MEMO_SHEEP_STATE="$T/sheep" MEMO_SHEEP_BIN="" SPACESHEEP_KEY=
export GIT_CONFIG_GLOBAL="$T/gitconfig"
printf '[user]\n\tname = Test\n\temail = t@example.com\n[init]\n\tdefaultBranch = main\n' > "$GIT_CONFIG_GLOBAL"
fails=0
check() { if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3: expected [$2] got [$1]"; fails=$((fails+1)); fi; }
has()   { if grep -qF -- "$2" "$1"; then echo "  ok   $3"; else echo "  FAIL $3: missing [$2]"; sed 's/^/         | /' "$1" | head -20; fails=$((fails+1)); fi; }
lacks() { if grep -qF -- "$2" "$1"; then echo "  FAIL $3: found [$2]"; fails=$((fails+1)); else echo "  ok   $3"; fi; }
AGENT="Co-Authored-By: Claude <noreply@anthropic.com>"

echo "the pick class: the hand-check's set and the basics"
cat > "$T/classes.py" <<'PY'
import os, sys
from importlib.machinery import SourceFileLoader
sys.argv = ["keel"]
k = SourceFileLoader("keel", os.environ["KEEL"]).load_module()
ab = [("A", "one road"), ("B", "another road")]
abc = ab + [("C", "a third way")]
cache = [("A", "keep the cache layer"), ("B", "drop the cache entirely")]
five = abc + [("D", "a fourth"), ("E", "a fifth")]
node = [("A", "run it on the node"), ("B", "rent a cloud VM"), ("C", "keep the cache layer")]
cv = [("A", "rent a cloud VM"), ("B", "a cron job on the node"), ("C", "do nothing for now")]
echoed = [("A", "keep it"), ("B", "drop it"), ("C", "neither: a design pass first")]
topic = [("A", "name it by `<topic>` alone"), ("B", "name it by date and topic")]
longo = [("A", "Rent a cloud VM for the node"), ("B", "A cron job on the Mac"), ("C", "Hold the step in dispatch until the owner answers again")]
land = [("A", "`/finish`'s own review: land the branch through `/finish`"), ("B", "one more dispatched fix round first")]
cases = [
    # the 5 true no-picks (hand-check): none
    ("none", [("A", "a runner on the Mac"), ("B", "a GCP VM"), ("C", "wait")],
     "Let's configure this on the rented VM, that's the one I already have."),
    ("none", [("A", "not now"), ("B", "step up to Max"), ("C", "never")], "I'm already on Max"),
    ("none", [("A", "$190 a month"), ("B", "$120 a month"), ("C", "A, with the challenger monthly")],
     "you can be more relaxed with budget, up to $10 effective on Claude, up to $150 list on Codex"),
    ("none", [("A", "the framework, the rules repo and the profile"), ("B", "plus the knowledge layer"), ("C", "plus the lab")],
     "Everything non-confidential, including the vault"),
    ("none", [("A", "the node pulls"), ("B", "an offer on the fleet ref"), ("C", "the Mac pushes")],
     "I don't like any of these options, but maybe I don't understand. The finish should be handled like any other task"),
    # the hand-check's false positives: picks
    ("recommended", [("A", "type /finish in this branch's session now"), ("B", "hold it: review the list edit first")],
     "land everything, you're a manager, please finish this build for me."),
    ("letter", [("A", "S7 writes the viewer key into the config"), ("B", "leave it unset until the joint test")],
     'Sam, in the managing session\'s chat, 2026-10-21: "Every save taken in, just record who made it." — so the key stays unset'),
    ("letter", [("A", "the managing session runs /finish now"), ("B", "hold it until S6 is ready")],
     'Sam, in the managing session\'s chat, 2026-10-21: "can you dispatch those finishes to the other Mac?" — applied'),
    ("letter", [("A", "carry them to S6 and S7"), ("B", "fix them on this branch first")],
     'Sam, in the managing session\'s chat, 2026-10-22, picked "Land now, fix before arming": this branch lands now'),
    # the basics
    ("letter", ab, "B"), ("letter", ab, "**A**"), ("letter", ab, "Option B — with a twist of my own"),
    ("letter", ab, "go with B, but later"), ("letter", ab, "another road, please"),
    ("letter", ab, "Taken unattended (Sam's yolo, 2026-10-30): A — one road"),
    ("letter", ab, "Taken in chat (Sam, 2026-10-19T10:00Z): B — another road"),
    ("recommended", ab, "as recommended"), ("recommended", ab, "yes"),
    ("none", ab, "yes, but rather a third road"), ("none", ab, "neither"), ("none", ab, "a fourth host, not these"),
    (None, ab, ""), (None, [], "yes"),
    # round 1's review: a refusal is none even where it names the letters, an option's words or the recommendation
    ("none", abc, "Neither A nor B nor C: the finish is a task like any other"), ("none", abc, "None of A, B, C"),
    ("none", abc, "I don't like A, B or C"), ("none", abc, "Not B. Something simpler."),
    ("none", abc, "A simpler road: a cron job"), ("none", abc, "Neither. A cron job is enough"),
    ("none", abc, "the recommendation misses the point"), ("none", abc, "not another road, something else"),
    ("none", abc, "As I said in the chat, none of these"), ("none", abc, "ok no, do something else"),
    ("none", abc, "Yes, I don’t like it though"),
    ("letter", abc, "A is fine for now, let's revisit later"), ("letter", abc, "D1: B, with a note"),
    ("letter", abc, "go with A for now"), ("recommended", abc, "as recommended — the build's manager took it"),
    ("recommended", abc, "Taken unattended (Sam's yolo, 2026-11-03): the one that keeps the cache"),
    # round 2's: the article before any word, a refusal of every option beats a leading letter, more refusal words
    ("none", abc, "A UI-only fix, none of these"), ("none", abc, "A 4th option: rewrite"),
    ("none", abc, "A, but none of these really"), ("none", cache, "I don't want to keep the cache layer"),
    ("none", cache, "Never drop the cache entirely"), ("letter", abc, "A it is"),
    ("letter", abc, "B, I don't like the dependency on the laptop, but it is the simplest"),
    # round 3's (the landing review): a letter refused beside the one picked, the recommendation with a clause,
    # a lowercase letter; a go-ahead that names the owner's own option is none
    ("letter", abc, "A over B"), ("letter", abc, "Prefer A over C"), ("letter", abc, "Let's do B, not C"),
    ("letter", abc, "Go with B but skip the docs part"), ("letter", abc, "A rather than B"),
    ("letter", abc, "I don't like A, go with B"),
    ("letter", abc, "b"), ("letter", abc, "a, with the tweak"),
    ("recommended", abc, "Recommended, with a test too"), ("recommended", abc, "the recommended one"),
    ("recommended", abc, "+1"), ("none", abc, "Recommended is wrong"), ("none", abc, "I don't want to pick A or B"),
    ("none", abc, "Go with the rented VM I already have"), ("none", abc, "Do it on the rented VM"),
    ("none", abc, "OK, use the rented VM"), ("none", abc, "Fine, put it in the core"),
    ("none", abc, "Sure — a cron job on the node"), ("none", abc, "Land it as a plugin of its own"),
    ("none", abc, "Proceed with a third approach: a cron job"), ("none", abc, "a cron job is enough"),
    # round 4's: words right after a letter that refuse it, a recommendation that refuses every option, the
    # owner's own mention of a chat (a relay has a name and its comma first)
    ("none", abc, "C is too complex, I'd rather do something simpler"), ("none", abc, "B misses the point"),
    ("none", abc, "A is wrong"), ("none", abc, "Option B is wrong"), ("letter", abc, "B is out; go with A"),
    ("none", abc, "Recommendation: none of these work"), ("none", abc, "Recommended, but none of these work"),
    ("none", abc, "Recommendation: neither"), ("recommended", abc, "Recommended, but skip the docs"),
    ("none", abc, "As I said in the chat: a cron job on the node"),
    ("none", abc, "Per our discussion in chat: use the rented VM"),
    ("none", abc, "As discussed in a chat with Sam: drop it entirely"),
    ("letter", abc, "A sounds good, but later"),
    # round 5's: a refusal past a list of letters or a quantifier, "not a …", more refusal words, a list "both" of
    # which is no single pick, and the owner's own "As I said, in the chat:" (a relay carries a date)
    ("none", abc, "A and B are both wrong: do a cron job"), ("none", abc, "Both A and B miss the point"),
    ("none", abc, "A, B or C — all too complex"), ("none", abc, "A or B — neither works, a cron job"),
    ("none", abc, "B is the wrong road"), ("none", abc, "B — no, a cron job"), ("none", abc, "B? Nope. A cron job."),
    ("none", abc, "A? B? Neither, a cron job"), ("none", abc, "Drop A"), ("none", abc, "Ditch C, rethink"),
    ("none", abc, "B would break the queue"), ("none", abc, "A is a non-starter; a cron job"),
    ("none", abc, "C — not a chance"), ("none", abc, "C is not a road I want"),
    ("none", abc, "As I said, in the chat: a cron job on the node"), ("none", abc, "Yes, in the chat: a fourth road"),
    ("none", abc, "Why not just drop it? A and B both add a road"), ("none", abc, "A and B both add a road; drop it"),
    ("letter", abc, "A, not B"), ("letter", abc, "B — not C"), ("none", abc, "Both A and B"),
    # an option's own text echoed after its letter is no refusal ("B — no" where B reads "no": a light take)
    ("letter", [("A", "yes"), ("B", "no")], "Taken in chat (Sam, 2026-10-16T08:00Z): B — no"),
    ("letter", [("A", "yes"), ("B", "no")], "B — no"),
    # the landing review's second fix round: a pick is a shape on keel's lists, everything else none (AGENTS.md's
    # trap on a matcher that grants a permission). Item 1's probes, the reviewers' false picks: none
    ("none", abc, "None. B is closest but wrong"), ("none", abc, "(B) is too complex"), ("none", abc, "B) is wrong, do a cron job"),
    ("none", abc, "B is too complex"), ("none", five, "e.g. a cron job"), ("none", five, "E.g. a cron job"),
    ("none", node, "don't run it on the node"), ("none", node, "We shouldn't keep the cache layer"),
    ("none", node, "No need to rent a cloud VM"), ("none", node, "Against: rent a cloud VM"),
    ("none", abc, "Is B really needed?"), ("none", abc, "What does B cost?"), ("none", abc, "B? Why not A?"),
    ("none", abc, "I hate A, B and C"), ("none", abc, "I dislike A"), ("none", abc, "I reject A and B"),
    ("none", abc, "B, no"), ("none", abc, "B, nope"), ("none", abc, "B, no way"), ("none", abc, "B sucks"),
    ("none", abc, "C sounds expensive. Let's talk"), ("none", abc, "Hold on, B worries me"),
    ("none", abc, "Hmm. Let me think about B"), ("none", abc, "I'm not sure, B maybe"),
    # item 3: a lead-in that refuses nothing
    ("letter", abc, "No preference — B"), ("letter", abc, "No strong opinion, B"), ("letter", abc, "No, B"),
    ("none", abc, "No, B is wrong"), ("none", abc, "No B"),
    # item 4: the recommendation taken by a verb, and light's "Other — " off before the rules
    ("recommended", abc, "Go with the recommendation"), ("recommended", abc, "go with recommended"),
    ("recommended", abc, "Yes, as recommended"), ("recommended", abc, "Agree with the recommendation"),
    ("recommended", abc, "I agree"), ("recommended", abc, "Follow your recommendation"),
    ("recommended", abc, "Taken in chat (Sam, 2026-11-05 06:00Z): Other — as recommended"),
    ("letter", abc, "Taken in chat (Sam, 2026-11-05 06:00Z): Other — b"), ("recommended", abc, "Other — as recommended"),
    # item 5: lowercase lists and abbreviations
    ("none", abc, "a, b and c are all bad"), ("none", abc, "a, b, c — all bad"), ("none", five, "e.g. a cron job on the node"),
    # item 6 (Reversible: yes, its recommendation): a delegation is the recommendation
    ("recommended", abc, "your call"), ("recommended", abc, "you have the authority to decide."),
    ("recommended", abc, "You decide"), ("recommended", abc, "Use your judgement"), ("none", abc, "your call, but none of these"),
    # the S1: a tap's chip label after its letter is the option's own words, whatever they start with
    ("letter", [("A", "no extra round take"), ("B", "a round")], "Taken in chat (Sam, 2026-11-05 06:00Z): A — no extra round (Recommended)"),
    ("letter", [("A", "no extra round take"), ("B", "a round")], "Relayed from skipper-1 (skipper, 2026-11-02): A — no extra round. The check is green."),
    ("letter", [("A", "No — keep it as it is"), ("B", "a round")], "A — No (Recommended)"),
    ("letter", [("A", "none (Recommended)"), ("B", "a round")], "A — none (Recommended)"),
    ("none", [("A", "a road"), ("B", "a round")], "A — no, a cron job"),
    # the real answers' sweep (docs/rabbit-holes-2026-11-02.md S3): shapes the allowlist keeps as picks
    ("letter", abc, "B to start, and then we'll configure a yard host"), ("letter", abc, 'A ("finish it", in chat)'),
    ("letter", abc, "B + open locally, then widened"), ("none", abc, "B+C+add video production"),
    ("letter", abc, "C if Orca is installed, B otherwise"), ("letter", abc, "C **Applied (D1-C, at the landing).**"),
    ("letter", abc, "A (it's skipper, not manager - right?)"),
    # round 1 of the second fix round's review loop: a question, a doubt, a retraction or a refusal after a pick,
    # a combination, a delegation of a detail beside the owner's own option, the owner's own dated chat mention: none
    ("none", node, 'A — would that scale?'),
    ("none", node, 'A: what does it cost?'),
    ("none", node, 'B, or is there something cheaper?'),
    ("none", node, 'C — but why?'),
    ("none", node, 'A, really?'),
    ("none", node, 'C. Not sure.'),
    ("none", node, 'B — maybe'),
    ("none", node, 'B — unsure'),
    ("none", node, "A — I'm not sure"),
    ("none", node, "A — let's talk first"),
    ("none", node, 'A — hold on'),
    ("none", node, 'A, not yet'),
    ("none", node, 'A — absolutely not'),
    ("none", node, "A — I'd rather not"),
    ("none", node, 'A — never'),
    ("none", node, 'B; no'),
    ("none", node, 'A! No.'),
    ("none", node, 'rent a cloud VM sounds expensive'),
    ("none", node, 'keep the cache layer seems risky'),
    ("none", node, 'rent a cloud VM? Is that safe?'),
    ("none", node, 'keep the cache layer? why'),
    ("none", node, 'A and B are fine, but C is better'),
    ("none", node, 'Both A and B add risk; something else'),
    ("none", node, 'go with B — or not'),
    ("none", node, "I'd pick B if it were cheaper, but it isn't"),
    ("none", node, 'Go with B. Actually, scrap that, none.'),
    ("none", node, 'Use A. Hmm, no.'),
    ("none", node, 'B, never'),
    ("none", node, 'B, obviously not'),
    ("none", node, 'Go with B — but honestly it is wrong'),
    ("none", node, 'A and B'),
    ("none", node, 'A + C'),
    ("none", node, 'A/B'),
    ("none", node, 'Is it really up to you?'),
    ("none", node, 'up to you? I want a cron job'),
    ("none", node, 'Use your judgement: a cron job, nothing more'),
    ("none", node, 'Your call — but a cron job would be simpler'),
    ("none", node, 'I trust you on the code, but the design needs a fourth road'),
    ("none", node, "I'd normally say it's your call, but here I want a fourth road"),
    ("none", node, 'whatever you recommend elsewhere, here a cron job'),
    ("none", node, 'your decision last week broke the node; rethink'),
    ("none", node, 'up to you which host, the road is a cron job'),
    ("none", node, "Let's configure it on the rented VM I already have, your call on the size"),
    ("none", node, 'A third road: a cron job. Up to you how to schedule it.'),
    ("none", node, 'Use the rented VM I have. I trust you with the details.'),
    ("none", node, 'As I said, in the chat, 2026-11-01: a cron job on the node'),
    ("letter", node, "A — sounds good"), ("letter", abc, "A is fine for now, especially given the rented VM. Have you considered CI?"),
    ("recommended", abc, "Your call."), ("recommended", abc, "up to you"),
    ("recommended", abc, 'Delegated in chat, 2026-10-29: "get them to do it. you have the authority to decide."'),
    # round 2 of the review loop: the recommendation, delegation and go-ahead roads take the same withdrawal test,
    # a combination on every road, more refusals and doubts after a pick, a go-ahead naming a letter: none
    ("none", abc, 'recommended?'),
    ("none", abc, 'Recommended, no'),
    ("none", abc, 'Recommended — maybe'),
    ("none", abc, 'Recommended. Actually no.'),
    ("none", abc, 'Recommended, but maybe not'),
    ("none", abc, 'as recommended, not yet'),
    ("none", abc, "Recommended — let's talk first"),
    ("none", abc, 'As recommended — wait, what does C do?'),
    ("none", abc, 'Recommended. On second thought, C'),
    ("none", abc, 'As recommended? No.'),
    ("none", abc, 'As recommended. Actually no.'),
    ("none", abc, "Go with the recommendation — wait, let's talk first"),
    ("none", abc, 'Per the recommendation? Maybe'),
    ("none", abc, 'Yes?'),
    ("none", abc, 'OK?'),
    ("none", abc, 'ok?'),
    ("none", abc, 'Go ahead?'),
    ("none", abc, 'LGTM?'),
    ("none", abc, 'Merge?'),
    ("none", abc, 'you decide. No.'),
    ("none", abc, 'B — hell no'),
    ("none", abc, 'B — god no'),
    ("none", abc, 'B — please no'),
    ("none", abc, 'B, I hate it'),
    ("none", abc, 'B: against'),
    ("none", abc, 'B — terrible'),
    ("none", abc, "B, but I'm not convinced"),
    ("none", abc, "B — I don't know"),
    ("none", abc, 'B — TBD'),
    ("none", abc, 'B. TBC'),
    ("none", abc, 'go with B, I hate it'),
    ("none", abc, 'Go with A and B'),
    ("none", abc, "I'd pick A and C"),
    ("none", abc, 'A plus B'),
    ("none", abc, 'A with B'),
    ("none", abc, 'A and also B'),
    ("none", abc, 'use B+C'),
    ("none", abc, 'A — I hate it'),
    ("none", abc, 'A — scratch it'),
    ("none", abc, 'B is fine. Actually, use C instead.'),
    ("none", abc, 'go A'),
    ("none", abc, 'ok A'),
    ("none", abc, 'yes A'),
    ("none", node, "rent a cloud VM, I hate it"), ("none", node, "rent a cloud VM and a cron job on the node"),
    ("recommended", abc, "Recommended, but skip the docs part"), ("letter", abc, "B — hell yes"),
    # round 3 of the review loop: another letter chosen after the pick, a but-clause or an aside that takes it back,
    # `;` `!` before a refusal, `-` `+` inside a word, a relay or a delegation record of words that refuse or doubt: none
    ("none", abc, "A works, but I'd prefer B"),
    ("none", abc, 'A is fine, but go with B'),
    ("none", abc, 'A is fine, B is better'),
    ("none", abc, 'A is ok, B is best'),
    ("none", abc, "B is fine in theory, but it won't work for us"),
    ("none", abc, "B, but I'd rather not"),
    ("none", abc, 'B, but not really'),
    ("none", abc, "B, though it's a bad idea"),
    ("none", abc, 'B is fine, but it breaks the node'),
    ("none", abc, "I'd go with B, if it weren't for the cost"),
    ("none", abc, 'B, after a design pass'),
    ("none", abc, 'A is the one to drop'),
    ("none", abc, 'A is the one that breaks the node'),
    ("none", abc, 'A is best avoided'),
    ("none", abc, 'B; too complex'),
    ("none", abc, 'B! Too complex'),
    ("none", abc, 'B; overkill'),
    ("none", abc, 'B; bad idea'),
    ("none", abc, 'B-tree index instead of the cache'),
    ("none", abc, 'A-records via the DNS API instead'),
    ("none", abc, 'C++ instead'),
    ("none", abc, 'B-ish'),
    ("none", abc, 'A-ha, I see now: neither'),
    ("none", abc, 'B. I take that back.'),
    ("none", abc, 'B, let me think'),
    ("none", abc, 'B. Or C.'),
    ("none", abc, "B, but I'd rather we didn't"),
    ("none", abc, 'B (no)'),
    ("none", abc, 'B (not really)'),
    ("none", abc, 'B, I disagree'),
    ("none", abc, 'B — though I dislike it'),
    ("none", abc, "I'd take B, but C too"),
    ("none", abc, "A please, though I'm unsure"),
    ("none", abc, "as recommended, but please don't"),
    ("none", abc, 'Sam, in the managing session\'s chat, 2026-11-05: "no"'),
    ("none", abc, 'Sam, in the managing session\'s chat, 2026-11-05: "I hate all three, think again"'),
    ("none", abc, 'Sam, in the managing session\'s chat, 2026-11-05: "maybe B? let\'s talk first"'),
    ("none", abc, 'Delegated in chat, 2026-11-05: "B or C, you decide"'),
    ("none", abc, 'Delegated in chat, 2026-11-05: "your call? hmm"'),
    ("none", abc, 'Recommended and C'),
    ("none", abc, 'as recommended, plus C'),
    ("none", abc, 'the recommendation with B'),
    ("none", abc, "Recommended, but it won't work"),
    ("none", abc, 'Recommended. I take it back.'),
    ("none", abc, 'The recommendation, which ignores the node, so no'),
    ("none", node, "rent a cloud VM, but it breaks the node"), ("letter", abc, "A is the one"),
    ("letter", abc, "A is best."),
    # this build's review loop, round 1 (the S2s its verifier confirmed): a short answer's later sentence, a capital But,
    # a but-clause naming another letter, "actually" before one
    ("none", cv, "B. But it won't work on the node."), ("none", cv, "B! But it breaks the node."),
    ("none", cv, "B, However, it won't work"), ("none", cv, "B. Though it's a bad idea."), ("none", cv, "B. That won't work."),
    ("none", cv, "B. I don't think so."), ("none", cv, "B. Let's not."), ("none", cv, "B. Can't do it."),
    ("none", cv, "B. It's a bad idea."), ("none", cv, "A, but honestly C"), ("none", cv, "B. Actually C."),
    ("none", cv, "B, But it would break the node"), ("none", cv, "B — However it wont work"),
    # …the pronoun "I" and the article "A" name no letter
    ("letter", cv, "B, but I'd add a test"), ("letter", cv, "B, and I'd like tests too"),
    ("letter", cv, "Go with B, and I will review it"), ("letter", cv, "B — but I want the tests first"),
    ("recommended", cv, "as recommended, but I'd add a test"), ("recommended", cv, "Recommended, and I'd add a test"),
    ("recommended", cv, 'Delegated in chat, 2026-10-29: "you have the authority to decide. A quick note: keep it small."'),
    ("letter", land, "Relayed from f00dcafe (skipper, 2026-11-05): A — land through /finish, but it does not skip the review "
     "(taken by the skipper, f00dcafe: Reversible: yes with a recommendation)"),
    # …a verdict on the pick
    ("none", cv, "B — rejected"), ("none", cv, "B (rejected)"), ("none", cv, "B, rejected"), ("none", cv, "B — veto"),
    ("none", cv, "B — declined"), ("none", cv, "B - denied"), ("none", cv, "B, please do not"), ("none", cv, "B — please don't"),
    ("none", cv, "B (I disagree)"), ("none", cv, "B — talk to me first"), ("none", cv, "B — reconsider"),
    ("none", cv, "B — give me other options"), ("none", cv, "B — dead end"), ("none", cv, "B, but it is broken"),
    # …combinations on every join, the lowercase road's in its own case
    ("none", cv, "A; B"), ("none", cv, "A, also C"), ("none", cv, "A. Also C."), ("none", cv, "A (and C)"),
    ("none", cv, "A - with C"), ("none", cv, "A then B"), ("none", cv, "B but with A's cron"),
    ("none", cv, "Recommended and also C"), ("none", cv, "Recommended, but with C's cron"),
    ("none", cv, "a, and c"), ("none", cv, "a — or c"), ("none", cv, "a — plus c"), ("none", cv, "A With C"),
    # …a pick that echoes its own option's words, a refusal in them included
    ("letter", echoed, "C — neither: a design pass first"), ("letter", echoed, "C, neither: a design pass first"),
    ("none", cv, "A — rent a cloud VM is out; B"),
    # …a condition on the pick stays a pick (round 3 refused each; the owner's real "B, but I don't understand …")
    ("letter", cv, "B, but I don't understand why Opus needs so much time. Use it anyway."),
    ("letter", cv, "B, but don't touch the docs"), ("letter", cv, "B, but not on Fridays"),
    ("letter", cv, "B, but no new dependencies"), ("letter", cv, "B, if it doesn't slow the check"),
    ("letter", cv, "B is better than A"), ("letter", cv, "B is the one we want"), ("letter", cv, "B is best for now"),
    ("letter", cv, "B -- simpler"), ("letter", cv, "B, with tests, run against main"), ("letter", cv, "B): the cron"),
    ("letter", cv, "B, since A won't work on the node"),
    ("letter", cv, "A, but let's list what B would have deleted, in case we need to reconsider."),
    ("letter", cv, 'A — answered by the session as skipper (Reversible: yes; Sam, 2026-10-23: "make it finish, don\'t wait '
     'for me"). Revisit B if it posts more than once a month.'),
    ("letter", cv, "Relayed from skipper (manager, 2026-10-21): A — Taken by the skipper on Sam's words: \"run it\". S1 "
     "starts now; S3b and S8 wait for the rebase fix."),
    # round 2 of this build's loop: a but-clause that refuses (its S1), the letter after a joining word, whole shapes
    # after "is the one", a later sentence's verdict about something else, a switch to another letter, a fallback
    ("none", cv, "B, but I don't want it"),
    ("none", cv, "B, but I'm not doing that"),
    ("none", cv, "B, but honestly no"),
    ("none", cv, "B, but I changed my mind"),
    ("none", cv, "B, but it isn't what we need"),
    ("none", cv, "B, but it doesn't scale"),
    ("none", cv, "B, but that won't fly"),
    ("none", cv, "B, but it's the wrong road"),
    ("none", cv, "B, but it would be wrong"),
    ("none", cv, "B, but I'd rather go another way"),
    ("none", cv, "B, though I'm not sold"),
    ("none", cv, "B, but that goes against the brief"),
    ("none", cv, "go with B, but I changed my mind"),
    ("none", cv, "Relayed from skipper (s, 2026-11-05): B, but the owner doesn't want it"),
    ("none", cv, "Recommended, but I don't want it"),
    ("none", cv, "as recommended, but it doesn't scale"),
    ("none", cv, "Go with the recommendation, but that won't fly"),
    ("none", cv, "B, but A seems safer"),
    ("none", cv, "B, or A if it is cheaper"),
    ("none", cv, "B. Or A might be simpler."),
    ("none", cv, "B and A together"),
    ("none", cv, "B with A for the cron"),
    ("none", cv, "B plus A for the backup"),
    ("none", cv, "B, but A should run first"),
    ("none", cv, "B, but A needs to go first"),
    ("none", cv, "Recommended, but A seems safer"),
    ("none", cv, "B is the one we want to avoid"),
    ("none", cv, "B is the one I'd avoid"),
    ("none", cv, "B is the one we should drop"),
    ("none", cv, "B is the one i would not pick"),
    ("none", cv, "B is best for nobody"),
    ("none", cv, "B is better than A, but neither works"),
    ("none", cv, "B is better for the tests than for us; skip it"),
    ("letter", cv, "Relayed from skipper (skipper, 2026-11-05): A — land it. Wait for CI first."),
    ("letter", cv, "Relayed from skipper (skipper, 2026-11-05): A — land it. Rejected: B, as it repeats the loop."),
    ("letter", cv, "Relayed from skipper (skipper, 2026-11-05): A — land it. Not yet merged; the skipper starts /finish."),
    ("letter", cv, "Relayed from skipper (skipper, 2026-11-05): A. Reconsider B after S5."),
    ("letter", cv, "Relayed from skipper (skipper, 2026-11-05): A, the cap is met. Talk to me if the landing stops."),
    ("letter", cv, "B. Reject A."),
    ("letter", cv, "B. Rethink the docs later."),
    ("letter", cv, "B. Show me more of the logs after."),
    ("letter", cv, "B. It's not right to keep A."),
    ("none", cv, "b, a"),
    ("none", cv, "b, a."),
    ("none", cv, "b, a, c"),
    ("none", cv, "B. Sorry, I meant A"),
    ("none", cv, "B... I mean A"),
    ("none", cv, "B. I want A"),
    ("none", cv, "B. But really, I want A"),
    ("none", cv, "B. Switch to A"),
    ("none", cv, "B. Change to A"),
    ("none", cv, "B. Make it A"),
    ("none", cv, "B. A please"),
    ("none", cv, "B. I want C"),
    ("none", cv, "B looks good but C looks better"),
    ("none", cv, "B, but I'd rather do something else entirely"),
    ("none", cv, "Use the rented VM I have; if that fails, use C"),
    ("none", cv, "Something simpler: a webhook. Failing that, take B"),
    ("none", cv, "I'd build a webhook. If you must, pick B"),
    ("none", cv, "I'd take B if you twisted my arm, but none really work"),
    ("letter", cv, "A Approved"),
    ("letter", cv, "B seems to be the simplest, just don't bother with macOS banner"),
    ("letter", cv, "B — hold. A second reviewer pass would repeat it."),
    ("recommended", cv, "Delegated in chat, 2026-10-29: \"you have the authority to decide. A quick note: keep it small.\""),
    ("letter", cv, "B, but I want the session to open in the scoped window even if it's not targeting the first folder"),
    ("letter", longo, "Rent a cloud VM for the node"), ("letter", longo, "A cron job on the Mac"),
    ("letter", longo, "Hold the step in dispatch until the owner answers again"),
    # round 3 of this build's loop: a later refusal sentence with words after it (its S1), a but-clause without a comma,
    # "let's" only as a go-ahead, the verdict words on every road, more refusals in a but-clause, the owner's own road
    ("none", cv, "B. That won't work for us."),
    ("none", cv, "B. That won't work here."),
    ("none", cv, "B. Let's not do that."),
    ("none", cv, "B. I don't think so, sorry."),
    ("none", cv, "B. It won't scale for us."),
    ("none", cv, "B. That's a bad idea, honestly."),
    ("none", cv, "B. That won't fly with Sam."),
    ("none", cv, "B. Rejected by the team."),
    ("none", cv, "B. Looks fine. Not sure about it though."),
    ("none", cv, "B is fine but I don't want it"),
    ("none", cv, "B looks good but it won't work"),
    ("none", cv, "B sounds good but it doesn't scale"),
    ("none", cv, "B seems right but no"),
    ("none", cv, "A works for me but not really"),
    ("none", cv, "A sounds good but no"),
    ("none", cv, "C is ok but I prefer a fourth road"),
    ("none", cv, "A looks right but I want a different approach"),
    ("none", cv, "A let's do something else instead"),
    ("none", cv, "A let's rethink this"),
    ("none", cv, "A let's drop it"),
    ("none", cv, "B let's skip it"),
    ("none", cv, "C let's revisit later"),
    ("none", cv, "A let's try something different"),
    ("none", cv, "B let's go back to the drawing board"),
    ("none", cv, "Sam, in the managing session's chat, 2026-10-21: \"Rejected.\""),
    ("none", cv, "Sam, in the managing session's chat, 2026-10-21: \"vetoed\""),
    ("none", cv, "Sam, in the managing session's chat, 2026-10-21: \"Denied.\""),
    ("none", cv, "B, but vetoed"),
    ("none", cv, "B, but denied"),
    ("none", cv, "B, but declined"),
    ("none", cv, "B, but that's overkill"),
    ("none", cv, "B, but it's too expensive"),
    ("none", cv, "B, but not at all"),
    ("none", cv, "B, but don't bother"),
    ("none", cv, "B, but I want a different approach"),
    ("none", cv, "B, but I'd prefer something simpler"),
    ("none", cv, "C — I'd go with something else"),
    ("none", cv, "B. Just kidding."),
    ("none", cv, "B. Something else entirely."),
    ("none", cv, "Option B if all else fails; first try a fourth way"),
    ("none", cv, "B — something like it but not it"),
    ("none", cv, "B with a totally different design"),
    ("none", cv, "B, but rethink it"),
    ("none", cv, "B looks good but it won't scale"),
    ("letter", cv, "Go with B but skip the docs part"),
    ("letter", topic, "name it by `<topic>` alone, as the branch does"),
]
for want, opts, answer in cases:
    got = k.pick_of(answer, opts)[0]
    print("%s %s %s" % ("ok  " if got == want else "FAIL", want, answer[:60]))
# the second fix round's S1: every fixture option tapped in a light questionnaire, written as light_write writes it
taps = bad = 0
for _, opts, _ in cases:
    for l, lab, _ in (k.light_options({"options": opts, "recommended": opts[0][0]}) if opts else []):
        got = k.pick_of(k.CHAT_ANSWER % ("2026-11-05 06:00Z", "%s — %s" % (l, lab)), opts)
        taps, bad = taps + 1, bad + (got != ("letter", l))
        if got != ("letter", l):
            print("FAIL tap %s — %s read %s" % (l, lab, got))
print("taps misread: %d of %d" % (bad, taps))
print("letter of a chat quote:", k.pick_of(cases[6][2], cases[6][1])[1])
print("letter of go with B:", k.pick_of("go with B, but later", ab)[1])
print("letter of A over B:", k.pick_of("A over B", abc)[1], k.pick_of("Prefer A over C", abc)[1], k.pick_of("b", abc)[1],
      k.pick_of("B is out; go with A", abc)[1])
# #504's review round: an answer that is one option's whole text picks it; a dash run after a letter stays fast
print("whole option text:", k.pick_of("merge", [("A", "merge"), ("B", "keep them separate")]),
      k.pick_of("No.", [("A", "yes"), ("B", "no")]))
import time
t0 = time.time(); k.pick_of("B. " + "-" * 60, ab); print("dash run fast:", time.time() - t0 < 0.5)
mg, yn = [("A", "merge"), ("B", "keep them separate")], [("A", "yes"), ("B", "no")]
print("a question of an option's words:", k.pick_of("Merge?", mg), k.pick_of("Yes?", yn), k.pick_of("another road?", ab))
print("a conjunction kept before a refusal:", k.pick_of("recommended and no", ab), k.pick_of("recommended then reconsider", ab),
      k.pick_of("recommended but misses the point", ab), k.pick_of("Recommended, and no", ab), k.pick_of("recommended then ship it", ab))
print("go words around an option's text:", k.pick_of("yes, merge", mg), k.pick_of("ok merge", mg), k.pick_of("yes", mg))
print("a negated keel step by its path:", k.brief_steps("Do not run `python3 ./x/modules/keel/bin/keel step docs/x.md S1 done` yet"),
      k.brief_steps("Never run bin/keel step docs/x.md S1"), k.brief_steps("then run `python3 ./x/bin/keel step docs/x.md S1 done`"))
print("but without a comma:", k.pick_of("recommended but overkill", ab), k.pick_of("recommended but too expensive", ab),
      k.pick_of("recommended with tests", ab))
PY
KEEL="$B/keel" python3 "$T/classes.py" > "$T/classes.out" 2>&1
check "$(grep -c "^ok  " "$T/classes.out")" "487" "every classifier case as the hand-check and the review rounds read it"
lacks "$T/classes.out" "FAIL" "…none misread"
grep '^FAIL' "$T/classes.out" | sed 's/^/         | /'
has "$T/classes.out" "taps misread: 0 of" "every fixture option, tapped in chat as light_write writes it, reads as its own letter (the S1)"
has "$T/classes.out" "letter of a chat quote: None" "a chat relay is a pick whose letter is unread"
has "$T/classes.out" "letter of go with B: B" "a letter in the first words is the pick"
has "$T/classes.out" "letter of A over B: A A B A" "the letter picked, never the one refused beside it; a lowercase letter upper-cased"

# a Course doc: D1 with two options and an empty box, S1 after D1, S2 after S1 — written by an agent
R="$T/repo"; git init -q "$R"; mkdir -p "$R/docs"
cat > "$R/docs/d.md" <<'EOF'
# Roads — which road the build takes (design, 2026-11-03)

Status: proposed — 0 of 1 decision answered · action plan: 0 of 2 steps done

- **D1 — which road** (the one question)
  - A — one road
  - B — another road

  Reversible: yes

  ➤ Recommended: A

  ➤ Answer:

## Action plan — the steps

- **S1 — build it** — the work · session `worker` · after: D1 · status: not started
- **S2 — measure** — later · session `worker` · after: S1 · status: not started
EOF
git -C "$R" add -A; git -C "$R" commit -qm "Docs: the design" -m "$AGENT"
BASE=$(git -C "$R" rev-parse HEAD)
k() { (cd "$R" && python3 "$B/keel" "$@"); }
answer() {  # <text>: the box's words, nothing else changed
  python3 - "$R/docs/d.md" "$1" <<'PY'
import re, sys
p, a = sys.argv[1], sys.argv[2]
s = open(p).read()
s = re.sub(r"(  ➤ Answer:\n)(?:  .*\n)*", lambda m: m.group(1) + "  " + a + "\n", s, count=1)
open(p, "w").write(s)
PY
}
reply() {  # <bold word> <text>: a reply under D1, as a builder writes one
  python3 - "$R/docs/d.md" "$1" "$2" <<'PY'
import sys
p, w, t = sys.argv[1:4]
s = open(p).read()
s = s.replace("\n## Action plan", "\n  > **%s** %s\n\n## Action plan" % (w, t), 1)
open(p, "w").write(s)
PY
}
held() { k held docs/d.md "$@" > "$T/held.out" 2>&1; echo $?; }

echo "the owner's no-pick answer holds the step after it"
answer "I don't like any of these options, the finish should be like any other task"
git -C "$R" commit -qam "the owner's answer"
check "$(held S1)" "3" "held: S1's after: names D1, whose answer picks none"
has "$T/held.out" "held: docs/d.md S1 waits on D1" "…naming the step and the item"
has "$T/held.out" "given on the doc's page or on GitHub" "…and what releases it (fix round 2, item 16)"
lacks "$T/held.out" "Design-pass:" "…never the recipe a builder could follow (fix round 2, item 15)"
check "$(held S2)" "0" "S2 waits on S1 alone: not held"
check "$(held)" "3" "no step named: every step of the doc judged"
k lint --strict docs/d.md > "$T/lint.out" 2>&1
has "$T/lint.out" "D1 (line 13): its answer picks no listed option (pick: none)" "lint --strict warns on a none"
k lint docs/d.md > "$T/lint.out" 2>&1
lacks "$T/lint.out" "pick: none" "plain lint stays quiet on an answered doc"
k parse docs/d.md > "$T/parse.json"
check "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["items"][0]["pick"])' "$T/parse.json")" "none" "parse: the item's pick"
NOPICKED=$(git -C "$R" rev-parse HEAD)

echo "a builder's reply, or its own edit of the box, releases nothing"
reply "Revised." "taken as the owner wrote it, rebuilt"
git -C "$R" commit -qam "builder: revised" -m "$AGENT"
check "$(held S1)" "3" "a builder's Revised. under it: still held"
reply "Applied." "in round 2"
git -C "$R" commit -qam "builder: applied" -m "$AGENT"
check "$(held S1)" "3" "a builder's Applied. under it: still held"
answer "B"
git -C "$R" commit -qam "builder: the box" -m "$AGENT"
check "$(held S1)" "3" "a builder's commit that rewrites the box to a letter: still held"
cat > "$T/pstat.py" <<'PY2'
import os, sys
from importlib.machinery import SourceFileLoader
sys.argv = ["keel"]
k = SourceFileLoader("keel", os.environ["KEEL"]).load_module()
print(*k.pick_status(os.environ["DOC"]))
PY2
check "$(cd "$R" && KEEL="$B/keel" DOC=docs/d.md python3 "$T/pstat.py")" "{'D1': 'letter'} ['D1']" "status --json's held agrees with keel held under a box a builder rewrote (round 3)"

echo "the owner's new Answer releases it, judged afresh"
git -C "$R" checkout -q -b again "$NOPICKED"
answer "B"
git -C "$R" commit -qam "the owner answers again"
check "$(held S1)" "0" "the owner's new Answer that picks: released"
answer "still none of these, a third road"
git -C "$R" commit -qam "the owner, a second no-pick"
check "$(held S1)" "3" "a second no-pick answer of the owner's: held again"
git -C "$R" checkout -q -b web "$NOPICKED"
answer "A"
GIT_COMMITTER_NAME=GitHub git -C "$R" commit -qam "builder: the box, rebase-merged" -m "$AGENT"
check "$(held S1)" "3" "a builder's box edit GitHub committed (Rebase and merge keeps its trailer): still held (round 3)"
git -C "$R" checkout -q -b web2 "$NOPICKED"
answer "A"
GIT_COMMITTER_NAME=GitHub git -C "$R" commit -qam "Update d.md"
check "$(held S1)" "0" "a GitHub web edit, no agent trailer: the owner's, released"
git -C "$R" checkout -q -b codex "$NOPICKED"
answer "B"; git -C "$R" commit -qam "builder: the box" -m "Co-Authored-By: Codex gpt-5"
check "$(held S1)" "3" "a Codex session's box edit: still held, as a Claude session's is (round 4)"
git -C "$R" checkout -q -b emptied "$NOPICKED"
answer ""; git -C "$R" commit -qam "Update d.md"
check "$(held S1)" "3" "the owner emptying the box: still held, only a pick releases (round 4)"
git -C "$R" checkout -q -b twice "$NOPICKED"
python3 - "$R/docs/d.md" <<'PY2'
import sys
p = sys.argv[1]; s = open(p).read()
open(p, "w").write(s.replace("\n## Action plan", "\n- **D1 — the same id again**\n\n## Action plan", 1))
PY2
git -C "$R" commit -qam "a D-id twice"
k held docs/d.md S1 > "$T/held.out" 2>&1; check "$?" "4" "a doc keel cannot parse (a D-id twice): could not judge, exit 4, never not held (round 4; fix round 2, item 11)"
has "$T/held.out" "could not tell" "…said so"
check "$(tail -n 1 "$T/held.out" | cut -c1-15)" "could not tell:" "…on its last line, which dispatch and pickup quote (round 5)"

echo "a fresh architect's Design-pass commit releases it"
git -C "$R" checkout -q -b pass "$NOPICKED"
reply "Revised." "design pass: the road is a task like any other; the options rewritten below"
git -C "$R" commit -qam "Docs: the design pass" -m "Design-pass: docs/d.md D1" -m "$AGENT"
check "$(held S1)" "0" "a commit carrying Design-pass: docs/d.md D1: released"
git -C "$R" checkout -q -b otherpass "$NOPICKED"
reply "Revised." "x"; git -C "$R" commit -qam "Docs: another" -m "Design-pass: docs/record/d.md D1" -m "$AGENT"
check "$(held S1)" "3" "a Design-pass naming another doc of the same name, on a commit touching this one, releases nothing"

echo "a brief names its steps"
git -C "$R" checkout -q -b briefs "$NOPICKED"
printf 'Task: build S1\nSteps: S1 of docs/d.md\n' > "$T/b1.md"
(cd "$R" && python3 "$B/keel" held --brief - < "$T/b1.md") > "$T/held.out" 2>&1; check "$?" "3" "a brief's Steps: line names a held step"
printf 'Task: build it\nDone means: `keel step %s/docs/d.md S1 done --branch x --stamp`\n' "$R" > "$T/b2.md"
check "$(k held --brief "$T/b2.md" >/dev/null 2>&1; echo $?)" "3" "a brief's keel step call names it, by absolute path"
printf 'Task: build it\nSteps: S1 of /srv/someone/projects/repo/docs/d.md\n' > "$T/b2b.md"
check "$(k held --brief "$T/b2b.md" >/dev/null 2>&1; echo $?)" "3" "a doc named by another Mac's checkout of this repo: judged here (round 3)"
printf 'Task: build it\nSteps: S1 of /srv/someone/projects/other/docs/d.md\n' > "$T/b2c.md"
k held --brief "$T/b2c.md" > "$T/held.out" 2>&1; check "$?" "4" "another repo's same-named doc: not judged as this one's (round 3), exit 4 (fix round 2, item 14)"
has "$T/held.out" "is not a doc of this repo" "…said so"
printf 'Task: build it\nSteps: S1 of ./docs/d.md\n' > "$T/b2d.md"
k held --brief "$T/b2d.md" > "$T/held.out" 2>&1; check "$?" "3" "./docs/d.md is docs/d.md (round 4)"
has "$T/held.out" "held: docs/d.md S1" "…named as the trailer names it"
printf 'Do: run the suite until it is green, then `keel step docs/d.md S1 done --stamp`\n' > "$T/b2e.md"
check "$(k held --brief "$T/b2e.md" >/dev/null 2>&1; echo $?)" "3" "a keel step call after an \"until\" earlier on its line is still named (round 4)"
printf 'Task: measure\nSteps: S2 of docs/d.md\n' > "$T/b3.md"
check "$(k held --brief "$T/b3.md" >/dev/null 2>&1; echo $?)" "0" "a brief naming S2 alone: not held"
printf 'Task: nothing named\n' > "$T/b4.md"
k held --brief "$T/b4.md" > "$T/held.out" 2>&1; check "$?" "0" "a brief naming no step: not held"
has "$T/held.out" "not held: no step named" "…said so"
check "$(k held --brief "$T/b1.md" --ref "$BASE" >/dev/null 2>&1; echo $?)" "0" "read at the ref before the answer: not held"

echo "intake: a Save's merge reopens a no-pick answer"
git -C "$R" checkout -q -b save "$BASE"
printf '{"items": {"D1": "I do not like any of these"}}\n' > "$T/a.json"
k merge docs/d.md "$T/a.json" --write > "$T/merge.out" 2>&1
has "$T/merge.out" "reopened, no listed option picked: D1" "merge says what it reopened"
has "$R/docs/d.md" "  > **Reopened.** no listed option picked — Sam answers again with a letter" "…the reopen under the item"
check "$(grep -c 'no listed option picked —' "$R/docs/d.md")" "1" "…once"
k parse docs/d.md > "$T/parse.json"
check "$(python3 -c 'import json,sys; i=json.load(open(sys.argv[1]))["items"][0]; print(i["reopened"], i["answered"])' "$T/parse.json")" "True False" "the item reads open again"
git -C "$R" commit -qam "Save" -m "$AGENT"
check "$(held S1)" "3" "a reopen a checkpoint committed holds too (a session's commit took the Save in)"
reply "Revised." "rebuilt on the owner's words"
k parse docs/d.md > "$T/parse.json"
check "$(python3 -c 'import json,sys; i=json.load(open(sys.argv[1]))["items"][0]; print(i["reopened"])' "$T/parse.json")" "True" "a builder's Revised. after the reopen keeps it reopened in the text"
git -C "$R" checkout -q -- docs/d.md
k merge docs/d.md "$T/a.json" --write > "$T/merge.out" 2>&1
check "$(grep -c 'no listed option picked —' "$R/docs/d.md")" "1" "a second Save of the same words writes no second reopen"
printf '{"items": {"D1": "B"}}\n' > "$T/b.json"; printf '{"items": {"D1": "I do not like any of these options either"}}\n' > "$T/none.json"
k merge docs/d.md "$T/b.json" --write > "$T/merge.out" 2>&1
lacks "$T/merge.out" "reopened" "a Save that picks reopens nothing"
k parse docs/d.md > "$T/parse.json"
check "$(python3 -c 'import json,sys; i=json.load(open(sys.argv[1]))["items"][0]; print(i["pick"], i["reopened"], i["answered"])' "$T/parse.json")" "letter False True" "the owner's pick: the reopen no longer binds"
git -C "$R" checkout -q -- docs/d.md

echo "a carried doc keeps its hold"
git -C "$R" checkout -q -b carry "$BASE"
git -C "$R" show save:docs/d.md > "$R/docs/d.md"
git -C "$R" commit -qam "Docs: carried from the design branch" -m "$AGENT"
check "$(held S1)" "3" "the answer and its reopen carried in one session commit: held"

echo "round 1: a Save a session commits releases; a merge, a relay and keel yolo's take do not hold or release wrongly"
git -C "$R" checkout -q -b sessave save
k merge docs/d.md "$T/b.json" --write > "$T/merge.out" 2>&1
has "$R/docs/d.md" "> **Picked.** B — Sam's new Answer, taken in" "the owner's new Save that picks: intake's Picked. line under the reopen"
git -C "$R" commit -qam "Save" -m "$AGENT"
check "$(held S1)" "0" "…a session's checkpoint commit of it releases the hold its reopen started"
printf '{"items": {"D1": "no, none of these after all"}}\n' > "$T/c.json"
k merge docs/d.md "$T/c.json" --write > "$T/merge.out" 2>&1
check "$(grep -c 'no listed option picked —' "$R/docs/d.md")" "2" "a third Save, no pick again: a second reopen after the Picked."
git -C "$R" commit -qam "Save" -m "$AGENT"
check "$(held S1)" "3" "…which holds again"
git -C "$R" checkout -q -b boxed "$NOPICKED"
answer "B"; git -C "$R" commit -qam "builder: the box" -m "$AGENT"
git -C "$R" checkout -q -b side "$NOPICKED"
sed -i.bak 's/· after: S1 · status: not started/· after: S1 · status: not started, measured later/' "$R/docs/d.md" && rm -f "$R/docs/d.md.bak"
git -C "$R" commit -qam "main touches the doc"
git -C "$R" checkout -q boxed; git -C "$R" merge -q --no-ff side -m "Merge side" >/dev/null 2>&1
check "$(held S1)" "3" "a merge after a builder's box edit releases nothing (judged against its own parent, never the owner's)"
git -C "$R" checkout -q -b relayed "$NOPICKED"
answer "Relayed from skipper (manager, 2026-11-03): A, go on"
git -C "$R" commit -qam "Answer: docs/d.md D1 relayed from skipper" -m "Ask-Answered: sk-1"
check "$(held S1)" "3" "a skipper's relayed answer is no owner's new Answer: still held"
cat > "$T/sets.py" <<'PY'
import os, sys
from importlib.machinery import SourceFileLoader
sys.argv = ["keel"]
k = SourceFileLoader("keel", os.environ["KEEL"]).load_module()
k.set_rels = lambda top, ref, rel: {"entry": "docs/d.md", "api": "docs/d.md"}
found, notes = k.held_steps(os.environ["R"], "HEAD", [("docs/e.md", "S1"), ("docs/e.md", "S2")])
print(" | ".join(["%s %s on %s" % (d, s, item) for d, s, item, _ in found] + notes))
PY
printf '%s\n' '# E' '' '## Action plan' '' '- **S1 — a component step** — x · session `worker` · after: entry D1 · status: not started' \
  '- **S2 — another** — x · session `worker` · after: nosuch D1 · status: not started' > "$R/docs/e.md"
git -C "$R" add docs/e.md; git -C "$R" commit -qm "a component" -m "$AGENT"
check "$(KEEL="$B/keel" R="$R" python3 "$T/sets.py" 2>&1)" "docs/e.md S1 on docs/d.md D1 | could not tell: docs/e.md S2's after: nosuch D1 names no file of its set at $(git -C "$R" rev-parse HEAD | cut -c1-12)" \
  "a set's entry D1 is judged in the entry; a slug the set lacks is a note"
git -C "$R" checkout -q -b yolo "$BASE"
sed -i.bak 's/  ➤ Recommended: A/  ➤ Recommended: the one that keeps the cache/' "$R/docs/d.md" && rm -f "$R/docs/d.md.bak"
git -C "$R" commit -qam "a recommendation in words" -m "$AGENT"
k yolo docs/d.md > "$T/yolo.out" 2>&1; check "$?" "0" "keel yolo takes a recommendation that names no letter"
lacks "$R/docs/d.md" "no listed option picked" "…and reopens nothing: its take is the recommendation"
git -C "$R" checkout -q -- docs/d.md

echo "round 2: a relay through merge writes no Picked.; a design pass clears text and hold; the branch's first parents"
git -C "$R" checkout -q -b relay2 save
printf '{"items": {"D1": "Relayed from skipper (manager, 2026-11-03): A, go on"}}\n' > "$T/r.json"
k merge docs/d.md "$T/r.json" --write > "$T/merge.out" 2>&1
lacks "$R/docs/d.md" "> **Picked.**" "a skipper's relayed answer taken in by merge: no Picked. line"
git -C "$R" commit -qam "Answer: docs/d.md D1 relayed from skipper" -m "Ask-Answered: sk-2"
check "$(held S1)" "3" "…and the hold stands"
k parse docs/d.md > "$T/parse.json"
check "$(python3 -c 'import json,sys; i=json.load(open(sys.argv[1]))["items"][0]; print(i["reopened"])' "$T/parse.json")" "True" "…the text stays reopened under a relayed letter"
git -C "$R" checkout -q -b design-bare save
reply "Design pass." "I did it"
git -C "$R" commit -qam "Docs: a design pass, no trailer" -m "$AGENT"
check "$(held S1)" "0" "a Design pass. reply alone, its trailer dropped as /finish's curation drops it: released (fix round 2, item 10)"
k lint --strict docs/d.md > "$T/lint.out" 2>&1
lacks "$T/lint.out" "pick: none" "…and lint --strict is quiet on it (fix round 2, item 8)"
git -C "$R" checkout -q -b design2 save
reply "Design pass." "the road is a task like any other; the options are rewritten above"
git -C "$R" commit -qam "Docs: the design pass" -m "Design-pass: docs/d.md D1" -m "$AGENT"
check "$(held S1)" "0" "a design pass (its reply and trailer): released"
k parse docs/d.md > "$T/parse.json"
check "$(python3 -c 'import json,sys; i=json.load(open(sys.argv[1]))["items"][0]; print(i["reopened"], i["answered"])' "$T/parse.json")" "False True" "…and the text reads it answered too"
git -C "$R" checkout -q -b fp-build "$BASE"
answer "I do not like any of these"; git -C "$R" commit -qam "the owner's no-pick"
git -C "$R" checkout -q -b fp-side "$BASE"
answer "B"; git -C "$R" commit -qam "the owner's B on another line"
sed -i.bak 's/· after: S1 · status: not started/· after: S1 · status: not started, later/' "$R/docs/d.md" && rm -f "$R/docs/d.md.bak"
git -C "$R" commit -qam "a step edit there"
git -C "$R" checkout -q fp-build; git -C "$R" merge -q --no-ff fp-side -m "Merge side" -X ours >/dev/null 2>&1
check "$(grep -c 'I do not like any of these' "$R/docs/d.md") $(held S1)" "1 3" "a side line's owner pick, merged with this line's no-pick kept: still held"
printf 'Task: revise D1\nDone means: D1 revised; do not run `keel step docs/d.md S1 done` until D1 is answered again\n' > "$T/b5.md"
check "$(k held --brief "$T/b5.md" >/dev/null 2>&1; echo $?)" "0" "a brief that says not to run keel step names no step it builds"

echo "the landing review's second fix round: who releases, what cannot be judged, other shapes of history"
PLUMB="Taken-By: keel sheep pull --plumb"
git -C "$R" checkout -q -b any-viewer "$NOPICKED"
answer "B"; git -C "$R" commit -qam "Keel: docs/d.md — 1 Save from the page, taken in by the lookout" -m "Saved-By: Ana
$PLUMB"
check "$(held S1)" "0" "with keel/owner-viewers unset, any plumbed Save is the owner's (round 4's rule): released"
# the owner's page names (the review loop's item 3: the owner's real Saves carry a short name, never regatta/owner)
mkdir -p "$REGATTA_CONFIG/keel"; printf 'sam\nsammy\n' > "$REGATTA_CONFIG/keel/owner-viewers"
git -C "$R" checkout -q -b viewer2 "$NOPICKED"
answer "B"; git -C "$R" commit -qam "Keel: docs/d.md — 1 Save from the page, taken in by the lookout" -m "Saved-By: Sammy
$PLUMB"
check "$(held S1)" "0" "a plumbed Save under any of the owner's listed names: released"
git -C "$R" checkout -q -b collab "$NOPICKED"
answer "B"; git -C "$R" commit -qam "Keel: docs/d.md — 1 Save from the page, taken in by the lookout" -m "Saved-By: Ana
$PLUMB"
check "$(held S1)" "3" "a collaborator's plumbed Save of a letter: still held (item 9)"
git -C "$R" checkout -q -b ownsave "$NOPICKED"
answer "B"; git -C "$R" commit -qam "Keel: docs/d.md — 1 Save from the page, taken in by the lookout" -m "Saved-By: Sam
$PLUMB"
check "$(held S1)" "0" "the owner's plumbed Save of a letter: released"
git -C "$R" checkout -q -b noname "$NOPICKED"
answer "B"; git -C "$R" commit -qam "Keel: docs/d.md — 1 Save from the page, taken in by the lookout" -m "Saved-By: (no name)
$PLUMB"
check "$(held S1)" "3" "a plumbed Save with no viewer's name: still held"
git -C "$R" checkout -q -b collab-picked save
k merge docs/d.md "$T/b.json" --write > "$T/merge.out" 2>&1
git -C "$R" commit -qam "Keel: docs/d.md — 1 Save from the page, taken in by the lookout" -m "Saved-By: Ana
$PLUMB"
check "$(held S1)" "3" "…nor does intake's Picked. line in a collaborator's plumbed Save release it"
cat > "$T/mk.py" <<'PY2'
import os, sys
from importlib.machinery import SourceFileLoader
sys.argv = ["keel"]
k = SourceFileLoader("keel", os.environ["KEEL"]).load_module()
text = open(os.environ["DOC"]).read()
out, rep = k.merge(text, {"items": {"D1": "B"}, "feedback": ""}, others={"D1"})
print("Picked" in out, rep["reopened"])
PY2
git -C "$R" checkout -q save
check "$(KEEL="$B/keel" DOC="$R/docs/d.md" python3 "$T/mk.py" 2>&1 | tail -4)" "False []" "a collaborator's Save of a letter through merge: no Picked. naming the owner (item 13)"
rm -f "$REGATTA_CONFIG/keel/owner-viewers"
git -C "$R" checkout -q -b boxed2 save
answer "B"; git -C "$R" commit -qam "builder: the box" -m "$AGENT"
k parse docs/d.md > "$T/parse.json"
check "$(python3 -c 'import json,sys; i=json.load(open(sys.argv[1]))["items"][0]; print(i["reopened"], i["answered"])' "$T/parse.json")" "True False" \
  "a builder's box edit under intake's reopen keeps the text reopened (item 15)"
git -C "$R" checkout -q -b curated "$BASE"
git -C "$R" show boxed2:docs/d.md > "$R/docs/d.md"; git -C "$R" commit -qam "Keel: the S1 build, curated" -m "$AGENT"
check "$(held S1)" "3" "…and its curation into one session commit still holds (item 15)"
git -C "$R" checkout -q -b generic "$BASE"
answer "B"; reply "Reopened." "cannot build B: the API is gone"; reply "Design pass." "options revised"
git -C "$R" commit -qam "a session's reopen, then a design pass" -m "$AGENT"
k parse docs/d.md > "$T/parse.json"
check "$(python3 -c 'import json,sys; i=json.load(open(sys.argv[1]))["items"][0]; print(i["reopened"])' "$T/parse.json")" "False" \
  "a Design pass. after a session's plain Reopened. closes it, as on main (item 9)"
git -C "$R" checkout -q -b dup "$BASE"
python3 - "$R/docs/d.md" <<'PY2'
import sys
p = sys.argv[1]; s = open(p).read()
open(p, "w").write(s.replace("\n## Action plan", "\n- **D1 — the same id again**\n  - A — x\n  - B — y\n\n## Action plan", 1))
PY2
git -C "$R" commit -qam "Docs: a D-id twice" -m "$AGENT"
answer "I don't like any of these options"; git -C "$R" commit -qam "Update d.md"
check "$(held S1)" "4" "the owner's no-pick answer while the doc has a D-id twice: could not judge"
python3 - "$R/docs/d.md" <<'PY2'
import sys
p = sys.argv[1]; s = open(p).read()
open(p, "w").write(s.replace("- **D1 — the same id again**", "- **D2 — the same id again**", 1))
PY2
git -C "$R" commit -qam "builder: renumber the second D1" -m "$AGENT"
check "$(held S1)" "3" "…and a builder's renumbering leaves it held: the owner's answer in the gap starts the hold (item 6)"
k held docs/nosuch.md > "$T/held.out" 2>&1; check "$?" "4" "keel held <a doc absent at the ref>: could not judge (item 7)"
git -C "$R" checkout -q -b unjudged "$NOPICKED"
printf 'Task: build it\nSteps: S1 of docs/missing.md\n' > "$T/b6.md"
k held --brief "$T/b6.md" > "$T/held.out" 2>&1; check "$?" "4" "a doc absent at the ref, in no commit at all: could not judge, exit 4 (item 14; a typo'd or unfetched path, #504's review round)"
check "$(tail -n 1 "$T/held.out" | cut -c1-15)" "could not tell:" "…on its last line"
printf 'Task: build it\nSteps: S1 of docs/d.md.\n' > "$T/b6s.md"
k held --brief "$T/b6s.md" > "$T/held.out" 2>&1; check "$?" "4" "a doc path with a full stop kept: could not judge, never not held (#504's review round)"
# a doc in history but gone from the ref and from every tip (deleted): could not tell, as item 14 made it
git -C "$R" show "$NOPICKED:docs/d.md" > "$R/docs/gone.md"; git -C "$R" add docs/gone.md; git -C "$R" commit -qm "a design once" -m "$AGENT"
git -C "$R" rm -q docs/gone.md; git -C "$R" commit -qm "and removed" -m "$AGENT"
printf 'Task: build it\nSteps: S1 of docs/gone.md\n' > "$T/b6g.md"
k held --brief "$T/b6g.md" > "$T/held.out" 2>&1; check "$?" "4" "a doc in history, absent at the ref and on every tip: could not judge, exit 4 (item 14)"
check "$(tail -n 1 "$T/held.out" | cut -c1-15)" "could not tell:" "…on its last line"
printf 'Task: build it\nSteps: S9 of docs/d.md\n' > "$T/b7.md"
k held --brief "$T/b7.md" > "$T/held.out" 2>&1; check "$?" "4" "a step the doc lacks: could not judge, exit 4 (item 14)"
has "$T/held.out" "docs/d.md has no step S9" "…naming it"
git -C "$R" checkout -q -b treed "$BASE"
mkdir -p "$R/docs/t.md"; echo x > "$R/docs/t.md/x"; git -C "$R" add -A; git -C "$R" commit -qm "a folder of that name once" -m "$AGENT"
git -C "$R" rm -rq docs/t.md; git -C "$R" show "$NOPICKED:docs/d.md" > "$R/docs/t.md"
git -C "$R" add -A; git -C "$R" commit -qm "the owner's no-pick answer, in the file that replaced it"
k held docs/t.md S1 > "$T/held.out" 2>&1; check "$?" "3" "a path that was a folder at an older commit: every later version read in place (item 12)"
git -C "$R" checkout -q -b wtbase "$BASE"
git -C "$R" worktree add -q "$T/wt-design" -b design-x "$NOPICKED"
printf 'Task: build it\nSteps: S1 of %s/docs/d.md\n' "$T/wt-design" > "$T/b8.md"
k held --brief "$T/b8.md" --ref "$BASE" > "$T/held.out" 2>&1; check "$?" "3" "a doc named by another worktree's path: judged at that worktree's HEAD too (item 13)"
k held --brief "$T/b1.md" --ref "$BASE" > "$T/held.out" 2>&1; check "$?" "0" "…while the same doc named relatively reads at the ref alone"
git -C "$R" checkout -q -b newstep "$BASE"
printf '%s\n' '- **S3 — new on the branch** — x · session `worker` · after: D1 · status: not started' >> "$R/docs/d.md"
git -C "$R" commit -qam "a step only on this branch" -m "$AGENT"
git -C "$R" worktree add -q --detach "$T/wt-old" "$BASE"
printf 'Task: build it\nSteps: S3 of %s/docs/d.md\n' "$T/wt-old" > "$T/b9.md"
k held --brief "$T/b9.md" > "$T/held.out" 2>&1; check "$?" "0" "a doc named by an older checkout's path: a step new on the branch is judged here, never refused (item 4)"
# round 2 of the review loop: the other worktree's HEAD is the newer word only where it holds the ref's last change
git -C "$R" checkout -q -b mainline "$NOPICKED"
git -C "$R" worktree add -q "$T/wt-rel" -b released "$NOPICKED"
(cd "$T/wt-rel" && python3 - docs/d.md <<'PY2'
import re, sys
p = sys.argv[1]; s = open(p).read()
open(p, "w").write(re.sub(r"(  ➤ Answer:\n)(?:  .*\n)*", lambda m: m.group(1) + "  B\n", s, count=1))
PY2
)
git -C "$T/wt-rel" commit -qam "the owner's new Answer on the branch"
echo x > "$R/unrelated.txt"; git -C "$R" add unrelated.txt; git -C "$R" commit -qm "main moves on" -m "$AGENT"
printf 'Task: build it\nSteps: S1 of %s/docs/d.md\n' "$R" > "$T/b10.md"
(python3 "$B/keel" held --repo "$T/wt-rel" --ref HEAD --brief "$T/b10.md") > "$T/held.out" 2>&1
check "$?" "0" "a doc named by the main checkout's path, main moved on: its stale hold never beats the branch's release (round 2, b)"
git -C "$R" checkout -q -b nodoc "$BASE"
git -C "$R" worktree add -q "$T/wt-new" -b design-new "$BASE"
(cd "$T/wt-new" && python3 - docs/d.md docs/new.md <<'PY2'
import re, sys
s = open(sys.argv[1]).read()
open(sys.argv[2], "w").write(re.sub(r"(  ➤ Answer:\n)(?:  .*\n)*", lambda m: m.group(1) + "  B\n", s, count=1))
PY2
)
git -C "$T/wt-new" add docs/new.md; git -C "$T/wt-new" commit -qm "a new design, the owner's B in it"
printf 'Task: build it\nSteps: S1 of %s/docs/new.md\n' "$T/wt-new" > "$T/b11.md"
k held --brief "$T/b11.md" > "$T/held.out" 2>&1
check "$?" "0" "a doc only on another worktree's branch, judged clean there: the ref's could-not-tell stands aside (round 2, a)"
# the landing review (2026-11-05): the ref reads clean, the other worktree's newer version does not: could not tell
git -C "$R" checkout -q -b dupwt "$BASE"
git -C "$R" worktree add -q "$T/wt-dup" -b design-dup "$BASE"
(cd "$T/wt-dup" && python3 - docs/d.md <<'PY2'
import re, sys
p = sys.argv[1]; s = open(p).read()
s = re.sub(r"(  ➤ Answer:\n)(?:  .*\n)*", lambda m: m.group(1) + "  none of these, a third road\n", s, count=1)
open(p, "w").write(s.replace("\n## Action plan", "\n- **D1 — the same id again**\n  - A — x\n  - B — y\n\n## Action plan", 1))
PY2
)
git -C "$T/wt-dup" commit -qam "Update d.md"
printf 'Task: build it\nSteps: S1 of %s/docs/d.md\n' "$T/wt-dup" > "$T/b12.md"
k held --brief "$T/b12.md" --ref "$BASE" > "$T/held.out" 2>&1
check "$?" "4" "the ref clean, the other worktree's newer version unreadable: could not judge, never not held (the landing review)"
# a log that cannot read the doc's history is could not tell, never not held (round 2, item 8)
G="$T/gone"; git init -q "$G"; mkdir -p "$G/docs"; git -C "$R" show "$NOPICKED:docs/d.md" > "$G/docs/d.md"
git -C "$G" add -A; git -C "$G" commit -qm "the owner's no-pick"; echo y > "$G/other.txt"; git -C "$G" add -A; git -C "$G" commit -qm two -m "$AGENT"
first_tree=$(git -C "$G" rev-parse HEAD~1^{tree}); rm -f "$G/.git/objects/${first_tree:0:2}/${first_tree:2}"
(cd "$G" && python3 "$B/keel" held docs/d.md S1) > "$T/held.out" 2>&1; check "$?" "4" "a history git cannot read: could not judge, never not held (round 2)"
# a comments-only plumbed take-in, with the owner's page names set: no Saved-By, the owner's comments (round 2)
mkdir -p "$REGATTA_CONFIG/keel"; printf 'sam\n' > "$REGATTA_CONFIG/keel/owner-viewers"
git -C "$R" checkout -q -b comments "$NOPICKED"
answer "B"; git -C "$R" commit -qam "Keel: docs/d.md — 1 thread, taken in by the lookout" -m "$PLUMB"
check "$(held S1)" "0" "a plumbed take-in of the owner's page comments (no Saved-By): the owner's, released"
rm -f "$REGATTA_CONFIG/keel/owner-viewers"
# round 3 of the review loop (its S1): a seed off main whose design doc lives only on its own branch is judged there
git -C "$R" checkout -q -b seedbase "$BASE"
git -C "$R" checkout -q -b design-only "$BASE"
git -C "$R" show "$NOPICKED:docs/d.md" > "$R/docs/side.md"; git -C "$R" add docs/side.md; git -C "$R" commit -qm "a design, the owner's no-pick"
git -C "$R" checkout -q -b design-ok "$BASE"
git -C "$R" show "$NOPICKED:docs/d.md" | python3 -c 'import re,sys; s=sys.stdin.read(); print(re.sub(r"(  ➤ Answer:\n)(?:  .*\n)*", lambda m: m.group(1) + "  B\n", s, count=1), end="")' > "$R/docs/okside.md"
git -C "$R" add docs/okside.md; git -C "$R" commit -qm "another design, the owner's B"
git -C "$R" checkout -q seedbase
printf 'Task: build it\nSteps: S1 of docs/side.md\n' > "$T/b12.md"; printf 'Task: build it\nSteps: S1 of docs/okside.md\n' > "$T/b13.md"
k held --brief "$T/b12.md" > "$T/held.out" 2>&1; check "$?" "3" "a seed off main, its doc only on a design branch with a no-pick: held there (round 3, the S1)"
k held --brief "$T/b13.md" > "$T/held.out" 2>&1; check "$?" "0" "…and with a pick: not held, never could-not-tell"
# a removed worktree's path is the repo's path (round 3)
printf 'Task: build it\nSteps: S1 of %s/.claude/worktrees/gone-xyz/docs/d.md\n' "$R" > "$T/b14.md"
git -C "$R" checkout -q "$NOPICKED" 2>/dev/null
k held --brief "$T/b14.md" > "$T/held.out" 2>&1; check "$?" "3" "a doc named by a removed worktree's path: judged as the repo's docs/d.md (round 3)"
# a `keel step` quoted from the owner's thread is no step the run builds (round 3)
printf 'Task: answer the thread\n\nThe threads, as the lookout read them:\n    [t1] Sam: once that is in, run keel step docs/missing.md S3 done\n' > "$T/b15.md"
k held --brief "$T/b15.md" > "$T/held.out" 2>&1; check "$?" "0" "a keel step quoted from a thread names no step (round 3)"
# the last commit that changed an answer decides who gave it (round 3)
cat > "$T/ao.py" <<'PY2'
import os, sys
from importlib.machinery import SourceFileLoader
sys.argv = ["keel"]
k = SourceFileLoader("keel", os.environ["KEEL"]).load_module()
print(sorted(k.answer_others(os.environ["R"], os.environ["BASEREF"], "HEAD", "docs/d.md")))
PY2
git -C "$R" checkout -q -b lastword save
answer "A"; git -C "$R" commit -qam "builder: the box" -m "$AGENT"
check "$(KEEL="$B/keel" R="$R" BASEREF=save python3 "$T/ao.py" 2>&1)" "['D1']" "a builder's box edit in a pull's range: someone other than the owner answered"
answer "B"; git -C "$R" commit -qam "Update d.md"
check "$(KEEL="$B/keel" R="$R" BASEREF=save python3 "$T/ao.py" 2>&1)" "[]" "…and the owner's answer after it in the same range: the owner's (round 3)"

echo "this build's review loop, round 1: the holds"
answer_in() {  # <file> <text>: that doc's first box, as answer does for docs/d.md
  python3 - "$R/$1" "$2" <<'PY'
import re, sys
p, a = sys.argv[1], sys.argv[2]
s = open(p).read()
s = re.sub(r"(  ➤ Answer:\n)(?:  .*\n)*", lambda m: m.group(1) + "  " + a + "\n", s, count=1)
open(p, "w").write(s)
PY
}
# item 3: a seed off main whose doc lives on two lines judges each line's tip, not the newest commit by date
git -C "$R" checkout -q -b design3 "$BASE"
git -C "$R" show "$BASE:docs/d.md" > "$R/docs/s3.md"; git -C "$R" add docs/s3.md; git -C "$R" commit -qm "a design" -m "$AGENT"
FORK3=$(git -C "$R" rev-parse HEAD)
answer_in docs/s3.md "I don't like any of these options"; git -C "$R" commit -qam "the owner's no-pick"
NONE3=$(git -C "$R" rev-parse HEAD)
git -C "$R" checkout -q -b sib3 "$FORK3"
sed -i.bak 's/· after: S1 · status: not started/· after: S1 · status: not started, later/' "$R/docs/s3.md" && rm -f "$R/docs/s3.md.bak"
GIT_COMMITTER_DATE=2030-01-01T00:00:00 GIT_AUTHOR_DATE=2030-01-01T00:00:00 git -C "$R" commit -qam "a sibling's step edit, later by date" -m "$AGENT"
git -C "$R" checkout -q seedbase
printf 'Task: build it\nSteps: S1 of docs/s3.md\n' > "$T/b16.md"
k held --brief "$T/b16.md" > "$T/held.out" 2>&1; check "$?" "3" "a sibling line newer by date, without the owner's no-pick: still held on the design line (item 3)"
git -C "$R" checkout -q design3; answer_in docs/s3.md "B"; git -C "$R" commit -qam "the owner's B"
git -C "$R" checkout -q -b sib3b "$NONE3"
sed -i.bak 's/· after: S1 · status: not started/· after: S1 · status: not started, later/' "$R/docs/s3.md" && rm -f "$R/docs/s3.md.bak"
GIT_COMMITTER_DATE=2030-01-02T00:00:00 GIT_AUTHOR_DATE=2030-01-02T00:00:00 git -C "$R" commit -qam "a sibling forked at the no-pick" -m "$AGENT"
git -C "$R" checkout -q seedbase
k held --brief "$T/b16.md" > "$T/held.out" 2>&1; check "$?" "0" "…and a sibling forked before the owner's B no longer holds what the design line released"
git -C "$R" branch -q -D sib3 sib3b design3
# item 11: the owner's no-pick that arrived with no reopen written (a plain fast-forward), then a Save's B: Picked., released
git -C "$R" checkout -q -b ff11 "$BASE"
answer "I don't like any of these options"; git -C "$R" commit -qam "Update d.md"
check "$(held S1)" "3" "the owner's no-pick, fast-forwarded in with no reopen: held"
k merge docs/d.md "$T/b.json" --write > "$T/merge.out" 2>&1; has "$R/docs/d.md" "> **Picked.** B" "…the Save's B writes Picked. though no reopen was written (item 11)"
git -C "$R" commit -qam "checkpoint" -m "$AGENT"
check "$(held S1)" "0" "…and the session's commit of it releases the step"
# item 13: a box a builder rewrote under the reopen: the held line says the owner writes it again in other words
git -C "$R" checkout -q boxed2
check "$(held S1)" "3" "a builder's box under the reopen: still held"
has "$T/held.out" '"B, confirmed"' "…and the line tells the owner the box's B was not their take-in (item 13)"
# item 14: a builder's box edit beside a version that does not read is someone else's answer, never nobody's
git -C "$R" checkout -q -b ao14 save
python3 - "$R/docs/d.md" <<'PY2'
import re, sys
p = sys.argv[1]; s = open(p).read()
s = re.sub(r"(  ➤ Answer:\n)(?:  .*\n)*", lambda m: m.group(1) + "  A\n", s, count=1)
open(p, "w").write(s.replace("\n## Action plan", "\n- **D1 — the same id again**\n  - A — x\n  - B — y\n\n## Action plan", 1))
PY2
git -C "$R" commit -qam "builder: the box, and a D-id twice" -m "$AGENT"
python3 - "$R/docs/d.md" <<'PY2'
import sys
p = sys.argv[1]; s = open(p).read()
open(p, "w").write(s.replace("\n- **D1 — the same id again**\n  - A — x\n  - B — y\n", "", 1))
PY2
git -C "$R" commit -qam "builder: the D-id fixed" -m "$AGENT"
check "$(KEEL="$B/keel" R="$R" BASEREF=save python3 "$T/ao.py" 2>&1)" "['D1']" "a builder's box edit beside a version that does not read: someone else's answer (item 14)"
# items 12 and 16: intake's line goes before a code fence, never into it; a take-in with another viewer's Save writes
# no Picked. for a comment thread's item either
cat > "$T/fence.py" <<'PY2'
import os, sys
from importlib.machinery import SourceFileLoader
sys.argv = ["keel"]
k = SourceFileLoader("keel", os.environ["KEEL"]).load_module()
text = open(os.environ["DOC"]).read().replace("\n## Action plan", "\n  ```bash\n  # note\n  keel pull\n  ```\n\n## Action plan", 1)
out, rep = k.merge(text, {"items": {"D1": "neither of these"}, "feedback": ""})
lines = out.split("\n")
fences = [i for i, l in enumerate(lines) if l.strip().startswith("```")]
print(rep["reopened"], next(i for i, l in enumerate(lines) if "**Reopened.**" in l) > fences[1])
# round 2: a Design pass after the fence, then the owner's second no-pick: the new reopen goes after it, and binds
text2 = "\n".join(l + ("\n\n  > **Design pass.** options revised" if "**Reopened.**" in l else "") for l in out.split("\n"))
text2 = text2.replace("  neither of these\n", "  B\n", 1)
out3, rep3 = k.merge(text2, {"items": {"D1": "still none of these"}, "feedback": ""})
l3, i3, _ = k.parse(out3)
print(rep3["reopened"], k.intake_state(i3[0], l3)[1], k.reopened(i3[0], l3))
print(sorted(k.takein_others({"items": {"D1": "B", "D2": "x"}}, {"D2"}, {"D2"})), sorted(k.takein_others({"items": {"D1": "B"}}, {"D1"}, set())))
PY2
git -C "$R" checkout -q "$BASE" 2>/dev/null
KEEL="$B/keel" DOC="$R/docs/d.md" python3 "$T/fence.py" > "$T/fence.out" 2>&1
check "$(head -1 "$T/fence.out")" "['D1'] True" "intake's reopen goes after a code fence in the item's region, never into it (item 12; round 2)"
check "$(sed -n 2p "$T/fence.out")" "['D1'] reopen True" "…and a second no-pick after a Design pass past the fence: reopened again (round 2)"
check "$(sed -n 3p "$T/fence.out")" "['D1', 'D2'] []" "a take-in with another viewer's Save: no Picked. for any item, a thread's included (item 16)"

echo "this build's review loop, round 2: the holds"
# item 8: a tip whose doc does not read keeps its could-not-tell, whatever a stale sibling line says
git -C "$R" checkout -q -b design8 "$BASE"
git -C "$R" show "$BASE:docs/d.md" > "$R/docs/s8.md"; git -C "$R" add docs/s8.md; git -C "$R" commit -qm "a design" -m "$AGENT"
FORK8=$(git -C "$R" rev-parse HEAD)
answer_in docs/s8.md "I don't like any of these options"; git -C "$R" commit -qam "the owner's no-pick"
python3 - "$R/docs/s8.md" <<'PY2'
import sys
p = sys.argv[1]; s = open(p).read()
open(p, "w").write(s.replace("\n## Action plan", "\n- **D1 — the same id again**\n  - A — x\n  - B — y\n\n## Action plan", 1))
PY2
git -C "$R" commit -qam "builder: a D-id twice" -m "$AGENT"
git -C "$R" checkout -q -b sib8 "$FORK8"
sed -i.bak 's/· after: S1 · status: not started/· after: S1 · status: not started, later/' "$R/docs/s8.md" && rm -f "$R/docs/s8.md.bak"
git -C "$R" commit -qam "a sibling's step edit" -m "$AGENT"
git -C "$R" checkout -q seedbase
printf 'Task: build it\nSteps: S1 of docs/s8.md\n' > "$T/b17.md"
k held --brief "$T/b17.md" > "$T/held.out" 2>&1; check "$?" "4" "a design line whose doc does not read, beside a stale sibling that judges clean: could not tell (round 2)"
git -C "$R" branch -q -D design8 sib8
# item 9: the owner's B that came in by a plain fast-forward after intake's reopen: keel pull's intake writes Picked.
git -C "$R" checkout -q -b rp9 "$BASE"
answer "I don't like any of these options"; git -C "$R" commit -qam "Update d.md"
k merge docs/d.md "$T/none.json" --write > "$T/merge.out" 2>&1; git -C "$R" commit -qam "checkpoint: intake's reopen" -m "$AGENT"
answer "B"; git -C "$R" commit -qam "Update d.md"
cat > "$T/rp.py" <<'PY2'
import os, sys
from pathlib import Path
from importlib.machinery import SourceFileLoader
sys.argv = ["keel"]
k = SourceFileLoader("keel", os.environ["KEEL"]).load_module()
r = Path(os.environ["R"]); k.released_picks(r, "docs/d.md", r / "docs/d.md")
lines, items, _ = k.parse((r / "docs/d.md").read_text())
print(k.reopened(items[0], lines))
PY2
check "$(held S1) $(KEEL="$B/keel" R="$R" python3 "$T/rp.py" 2>&1 | tail -1)" "0 False" "the owner's B fast-forwarded in after the reopen: released in git, and intake's Picked. clears the text (round 2)"
has "$R/docs/d.md" "> **Picked.** B" "…written under the item"
git -C "$R" checkout -q -- docs/d.md
# the finish review: the owner's no-pick fast-forwarded in, never reopened: the "nothing new" road's intake writes the reopen
git -C "$R" checkout -q -b rp13 "$BASE"
answer "I don't like any of these options"; git -C "$R" commit -qam "Update d.md"
check "$(held S1) $(KEEL="$B/keel" R="$R" python3 "$T/rp.py" 2>&1 | tail -1)" "3 True" "the owner's no-pick fast-forwarded in with no reopen: held, and intake writes the reopen into the text"
has "$R/docs/d.md" "> **Reopened.** no listed option picked" "…under the item"
git -C "$R" checkout -q -- docs/d.md
# item 16: the owner's no-pick in a gap, then a builder's renumbering that sets a letter: held
git -C "$R" checkout -q -b g16 "$BASE"
python3 - "$R/docs/d.md" <<'PY2'
import sys
p = sys.argv[1]; s = open(p).read()
open(p, "w").write(s.replace("\n## Action plan", "\n- **D1 — the same id again**\n  - A — x\n  - B — y\n\n## Action plan", 1))
PY2
git -C "$R" commit -qam "Docs: a D-id twice" -m "$AGENT"
answer "none of these, a third road"; git -C "$R" commit -qam "Update d.md"
python3 - "$R/docs/d.md" <<'PY2'
import re, sys
p = sys.argv[1]; s = open(p).read()
s = s.replace("\n- **D1 — the same id again**\n  - A — x\n  - B — y\n", "\n- **D2 — the same id again**\n  - A — x\n  - B — y\n", 1)
open(p, "w").write(re.sub(r"(  ➤ Answer:\n)(?:  .*\n)*", lambda m: m.group(1) + "  B — another road\n", s, count=1))
PY2
git -C "$R" commit -qam "builder: renumbered, the box set" -m "$AGENT"
check "$(held S1)" "3" "the owner's no-pick in a gap, then a builder's renumbering that sets a letter: still held (round 2)"
# item 17: `after: entry D1` in a doc of no set is its own D1
git -C "$R" checkout -q -b e17 "$BASE"
sed 's/· after: D1 · status: not started/· after: entry D1 · status: not started/' "$R/docs/d.md" > "$R/docs/e17.md"
git -C "$R" add docs/e17.md; git -C "$R" commit -qm "a standalone design" -m "$AGENT"
answer_in docs/e17.md "I don't like any of these options"; git -C "$R" commit -qam "the owner's no-pick"
k held docs/e17.md S1 > "$T/held.out" 2>&1; check "$?" "3" "after: entry D1 in a doc of no set: judged as its own D1, held (round 2)"
# item 22: a take-in with another viewer's Save that changed nothing still writes no Picked.
cat > "$T/to.py" <<'PY2'
import os, sys
from importlib.machinery import SourceFileLoader
sys.argv = ["keel"]
k = SourceFileLoader("keel", os.environ["KEEL"]).load_module()
print(sorted(k.takein_others({"items": {"D1": "B"}}, set(), True)))
PY2
check "$(KEEL="$B/keel" python3 "$T/to.py" 2>&1)" "['D1']" "a take-in whose other viewer's Save changed nothing: no Picked. (round 2)"

echo "this build's review loop, round 3: the holds"
# item 9: the owner's real picks made while the doc did not read are the owner's, never held
git -C "$R" checkout -q -b g9 "$BASE"
python3 - "$R/docs/d.md" <<'PY2'
import re, sys
p = sys.argv[1]; s = open(p).read()
s = re.sub(r"(  ➤ Answer:\n)(?:  .*\n)*", lambda m: m.group(1) + "  B\n", s, count=1)
open(p, "w").write(s.replace("\n## Action plan", "\n- **D1 — the same id again**\n  - A — x\n  - B — y\n\n## Action plan", 1))
PY2
git -C "$R" commit -qam "Update d.md"
python3 - "$R/docs/d.md" <<'PY2'
import sys
p = sys.argv[1]; s = open(p).read()
open(p, "w").write(s.replace("\n- **D1 — the same id again**\n", "\n- **D2 — the same id again**\n", 1))
PY2
git -C "$R" commit -qam "builder: renumbered" -m "$AGENT"
check "$(held S1)" "0" "the owner's B in a gap, then a builder's renumbering that keeps it: the owner's, not held (round 3)"
# the landing review (2026-11-05): the gap's boxes are matched by item title, never as one set across boxes — a
# builder's renumbering that sets the no-pick box to another box's words leaves it held
git -C "$R" checkout -q -b g18 "$BASE"
python3 - "$R/docs/d.md" <<'PY2'
import sys
p = sys.argv[1]; s = open(p).read()
open(p, "w").write(s.replace("\n## Action plan", "\n- **D1 — the same id again**\n  - A — x\n  - B — y\n\n  ➤ Answer:\n\n## Action plan", 1))
PY2
git -C "$R" commit -qam "Docs: a D-id twice, each with a box" -m "$AGENT"
python3 - "$R/docs/d.md" <<'PY2'
import re, sys
p = sys.argv[1]; s = open(p).read()
s = re.sub(r"(  ➤ Answer:\n)(?:  .*\n)*", lambda m: m.group(1) + "  none of these, a third road\n", s, count=1)
open(p, "w").write(s.replace("  - B — y\n\n  ➤ Answer:\n", "  - B — y\n\n  ➤ Answer:\n  B\n", 1))
PY2
git -C "$R" commit -qam "Update d.md"
python3 - "$R/docs/d.md" <<'PY2'
import re, sys
p = sys.argv[1]; s = open(p).read()
s = s.replace("\n- **D1 — the same id again**\n", "\n- **D2 — the same id again**\n", 1)
open(p, "w").write(re.sub(r"(  ➤ Answer:\n)(?:  .*\n)*", lambda m: m.group(1) + "  B\n", s, count=1))
PY2
git -C "$R" commit -qam "builder: renumbered, D1's box set to the other box's words" -m "$AGENT"
check "$(held S1)" "3" "the owner's no-pick in a gap, a builder's renumbering that sets it to another box's words: held (the landing review)"
# item 10: released_picks credits the owner only with the owner's answer, never a builder's later box edit
git -C "$R" checkout -q -b rp10 rp9
git -C "$R" checkout -q -- docs/d.md 2>/dev/null
answer "A"; git -C "$R" commit -qam "builder: the box" -m "$AGENT"
KEEL="$B/keel" R="$R" python3 "$T/rp.py" > /dev/null 2>&1
lacks "$R/docs/d.md" "> **Picked.** A" "a builder's box edit after the owner's B: released_picks writes no Picked. naming the owner (round 3)"
git -C "$R" checkout -q -- docs/d.md
# item 8: the fence mask is the core's CommonMark reading: an inner fence line of a longer fence is content
cat > "$T/nest.py" <<'PY2'
import os, sys
from importlib.machinery import SourceFileLoader
sys.argv = ["keel"]
k = SourceFileLoader("keel", os.environ["KEEL"]).load_module()
text = open(os.environ["DOC"]).read()
text = text.replace("  ➤ Answer:\n", "  ➤ Answer:\n  B\n", 1).replace("\n## Action plan", "\n  ````markdown\n  ```\n  > **Reopened.** no listed option picked — an example\n  ```\n  ````\n\n## Action plan", 1)
lines, items, _ = k.parse(text)
print(k.reopened(items[0], lines), k.intake_state(items[0], lines)[1])
PY2
git -C "$R" checkout -q "$BASE" 2>/dev/null
check "$(KEEL="$B/keel" DOC="$R/docs/d.md" python3 "$T/nest.py" 2>&1)" "False None" "an example of intake's line inside a nested fence: no phantom reopen (round 3)"

echo "keel pull: the pick of each changed answer, and intake's reopen"
# origin's URL reads as github.com (what locate() parses); insteadOf sends the traffic to a bare repo (keel.sh's way)
O="$T/origin.git"; git init -q --bare "$O"; URL=https://github.com/owner/repo.git
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0="url.$O.insteadOf" GIT_CONFIG_VALUE_0="$URL"
git -C "$R" checkout -q -b claude/t/2026-11-03-roads "$BASE"
git -C "$R" remote add origin "$URL"; git -C "$R" push -q origin claude/t/2026-11-03-roads 2>/dev/null
W="$T/web"; git clone -q -b claude/t/2026-11-03-roads "$URL" "$W"
python3 - "$W/docs/d.md" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
open(p, "w").write(s.replace("  ➤ Answer:\n", "  ➤ Answer:\n  neither, a third road\n", 1))
PY
GIT_COMMITTER_NAME=GitHub git -C "$W" commit -qam "Update d.md"; git -C "$W" push -q origin claude/t/2026-11-03-roads 2>/dev/null
k pull docs/d.md > "$T/pull.out" 2>&1; check "$?" "0" "pull takes the web edit in"
has "$T/pull.out" "D1 → neither, a third road (pick: none)" "…naming its pick"
has "$T/pull.out" "reopened: D1 — no listed option picked" "…and the reopen it wrote"
has "$R/docs/d.md" "> **Reopened.** no listed option picked" "the reopen is in the doc, for the checkpoint to commit"
check "$(held S1)" "3" "held from the web edit alone, before the reopen is committed"
k status docs/d.md --json --no-fetch > "$T/status.json" 2>/dev/null
check "$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get("picks"), d.get("held"))' "$T/status.json")" "{'D1': 'none'} ['D1']" "status --json: the picks and the held items"
git -C "$R" commit -qam "checkpoint" -m "$AGENT"; git -C "$R" push -q origin claude/t/2026-11-03-roads 2>/dev/null
git -C "$W" pull -q --ff-only origin claude/t/2026-11-03-roads 2>/dev/null
python3 - "$W/docs/d.md" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
open(p, "w").write(s.replace("  neither, a third road\n", "  B\n", 1))
PY
GIT_COMMITTER_NAME=GitHub git -C "$W" commit -qam "Update d.md"; git -C "$W" push -q origin claude/t/2026-11-03-roads 2>/dev/null
k pull docs/d.md > "$T/pull.out" 2>&1
has "$T/pull.out" "D1 → B (pick: letter B)" "the owner's new Answer through pull: a letter"
lacks "$T/pull.out" "reopened:" "…which reopens nothing"
check "$(held S1)" "0" "…and releases the step"
git -C "$R" commit -qam "checkpoint" -m "$AGENT"; git -C "$R" push -q origin claude/t/2026-11-03-roads 2>/dev/null
git -C "$W" pull -q --ff-only origin claude/t/2026-11-03-roads 2>/dev/null
python3 - "$W/docs/d.md" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
open(p, "w").write(s.replace("  B\n", "  no, still a third road\n", 1))
PY
GIT_COMMITTER_NAME=GitHub git -C "$W" commit -qam "Update d.md"; git -C "$W" push -q origin claude/t/2026-11-03-roads 2>/dev/null
k pull docs/d.md > "$T/pull.out" 2>&1; git -C "$R" commit -qam "checkpoint" -m "$AGENT"; git -C "$R" push -q origin claude/t/2026-11-03-roads 2>/dev/null
check "$(held S1)" "3" "the owner's second no-pick through pull: held again"
git -C "$W" pull -q --ff-only origin claude/t/2026-11-03-roads 2>/dev/null
python3 - "$W/docs/d.md" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
open(p, "w").write(s.replace("  no, still a third road\n", "  A\n", 1))
PY
git -C "$W" commit -qam "builder on another host: the box" -m "$AGENT"; git -C "$W" push -q origin claude/t/2026-11-03-roads 2>/dev/null
k pull docs/d.md > "$T/pull.out" 2>&1
lacks "$T/pull.out" "picked:" "a builder's box edit pulled from GitHub: no Picked. taken in as the owner's (round 2, item 13)"
git -C "$R" commit -qam "checkpoint" -m "$AGENT"
check "$(held S1)" "3" "…and the step stays held"
has "$T/classes.out" "whole option text: ('letter', 'A') ('letter', 'B')" "an answer that is one option's whole text picks it (#504's review round)"
has "$T/classes.out" "a question of an option's words: ('none', None) ('none', None) ('none', None)" "a question made of an option's words is no pick (round 2)"
has "$T/classes.out" "but without a comma: ('none', None) ('none', None) ('recommended', None)" "a recommendation's but-clause read without a comma (round 2)"
has "$T/classes.out" "a conjunction kept before a refusal: ('none', None) ('none', None) ('none', None) ('none', None) ('recommended', None)" "a recommendation's and/then/but clause that refuses: none (round 3)"
has "$T/classes.out" "go words around an option's text: ('letter', 'A') ('letter', 'A') ('recommended', None)" "go words around one option's own text pick it, never the recommendation (round 3)"
has "$T/classes.out" "a negated keel step by its path: [] [] [('docs/x.md', 'S1')]" "a negated keel step named by its path names no step (round 3)"
has "$T/classes.out" "dash run fast: True" "a long dash run after a letter reads in time (#504's review round: the combo regex backtracked)"

echo "#504's review round: the hold across a move, a stale archive ref, changed options; lint's words"
git -C "$R" checkout -q -b moved "$NOPICKED"
check "$(held S1)" "3" "the owner's no-pick holds before the move"
mkdir -p "$R/docs/record"; git -C "$R" mv docs/d.md docs/record/d.md; git -C "$R" commit -qm "builder: move the doc" -m "$AGENT"
k held docs/record/d.md S1 > "$T/held.out" 2>&1; check "$?" "3" "a builder's git mv of the doc keeps the hold on its new path"
git -C "$R" checkout -q -b arch-old "$BASE"
git -C "$R" show "$NOPICKED:docs/d.md" > "$R/docs/arch.md"; git -C "$R" add docs/arch.md; git -C "$R" commit -qm "a design, the owner's no-pick"
git -C "$R" update-ref refs/archive/arch-old HEAD
git -C "$R" checkout -q -b arch-new "$BASE"
git -C "$R" show design-ok:docs/okside.md > "$R/docs/arch.md"; git -C "$R" add docs/arch.md; git -C "$R" commit -qm "the design rewritten, the owner's B"
git -C "$R" checkout -q --detach "$BASE"
printf 'Task: build it\nSteps: S1 of docs/arch.md\n' > "$T/b20.md"
k held --brief "$T/b20.md" > "$T/held.out" 2>&1; check "$?" "3" "the old line still a branch: its tip holds"
git -C "$R" branch -q -D arch-old
k held --brief "$T/b20.md" > "$T/held.out" 2>&1; check "$?" "0" "…the old line only under refs/archive: no tip of it, the live line's B stands"
git -C "$R" checkout -q -b optmoved "$NOPICKED"
python3 - "$R/docs/d.md" <<'PY2'
import sys
p = sys.argv[1]; s = open(p).read()
open(p, "w").write(s.replace("  - B — another road\n", "  - B — another road\n  - C — I don't like any of these options\n", 1))
PY2
git -C "$R" commit -qam "builder: a third option" -m "$AGENT"
check "$(held S1)" "3" "a builder's new option the owner's words now read as: still held"
lacks "$T/held.out" "confirmed" "…and no confirm asked of a letter the owner never wrote"
has "$T/held.out" "only because the options changed since the answer" "…saying the options changed"
# round 2: a move whose old path stopped reading for a while is cleared by the next version that reads, as unmoved
git -C "$R" checkout -q -b moved-slip "$NOPICKED"
python3 - "$R/docs/d.md" <<'PY2'
import sys
p = sys.argv[1]; s = open(p).read()
open(p, "w").write(s.replace("## Action plan", "- **D1 — a second one**\n  - A — x\n  - B — y\n\n  ➤ Answer:\n\n## Action plan", 1))
PY2
git -C "$R" commit -qam "builder: a D-id twice" -m "$AGENT"
mkdir -p "$R/docs/record"; git -C "$R" mv docs/d.md docs/record/d.md; git -C "$R" commit -qm "builder: move the doc" -m "$AGENT"
sed -i.bak 's/^- \*\*D1 — a second one\*\*/- **D2 — a second one**/' "$R/docs/record/d.md" && rm -f "$R/docs/record/d.md.bak"
git -C "$R" commit -qam "builder: the D-id fixed" -m "$AGENT"
k held docs/record/d.md S1 > "$T/held.out" 2>&1; check "$?" "3" "a move over a version that did not read: the owner's no-pick still holds, never could-not-tell for good"
python3 - "$R/docs/record/d.md" <<'PY2'
import re, sys
p = sys.argv[1]; s = open(p).read()
open(p, "w").write(re.sub(r"(  ➤ Answer:\n)(?:  .*\n)*", lambda m: m.group(1) + "  B\n", s, count=1))
PY2
git -C "$R" commit -qam "the owner's B"
k held docs/record/d.md S1 > "$T/held.out" 2>&1; check "$?" "0" "…and the owner's B on the moved doc releases it"
# round 2: a box a session set to B in the commit that wrote the reopen: the "confirmed" advice, never "options changed"
git -C "$R" checkout -q -b boxreopen "$BASE"
python3 - "$R/docs/d.md" <<'PY2'
import sys
p = sys.argv[1]; s = open(p).read()
open(p, "w").write(s.replace("  ➤ Answer:\n", "  ➤ Answer:\n  B\n\n  > **Reopened.** no listed option picked — x\n", 1))
PY2
git -C "$R" commit -qam "session: B and the reopen" -m "$AGENT"
check "$(held S1)" "3" "a session commit of a builder's B with the reopen: held"
lacks "$T/held.out" "only because the options changed" "…never said to be the options' doing"
has "$T/held.out" '"B, confirmed"' "…the owner asked to write it again"
# round 2: status --json holds what keel held holds where a builder deleted the options
git -C "$R" checkout -q -b noopts "$NOPICKED"
sed -i.bak -e '/^  - A — one road$/d' -e '/^  - B — another road$/d' "$R/docs/d.md" && rm -f "$R/docs/d.md.bak"
git -C "$R" commit -qam "builder: the options dropped" -m "$AGENT"
check "$(held S1) $(k status docs/d.md --json | python3 -c 'import json,sys; print(json.load(sys.stdin).get("held"))')" "3 ['D1']" "options a builder deleted: keel held and status --json agree"
answer ""; git -C "$R" commit -qam "builder: the box emptied" -m "$AGENT"
check "$(held S1) $(k status docs/d.md --json | python3 -c 'import json,sys; print(json.load(sys.stdin).get("held"))')" "3 ['D1']" "…and with the box emptied too (round 3)"
# round 3: a moved doc's hint reads the box at the hold's start on the old path
git -C "$R" checkout -q -b optmoved2 "$NOPICKED"
mkdir -p "$R/docs/x"; git -C "$R" mv docs/d.md docs/x/d.md; git -C "$R" commit -qm "builder: move the doc" -m "$AGENT"
python3 - "$R/docs/x/d.md" <<'PY2'
import sys
p = sys.argv[1]; s = open(p).read()
open(p, "w").write(s.replace("  - B — another road\n", "  - B — another road\n  - C — I don't like any of these options\n", 1))
PY2
git -C "$R" commit -qam "builder: a third option" -m "$AGENT"
k held docs/x/d.md S1 > "$T/held.out" 2>&1; check "$?" "3" "a moved doc whose options changed under the owner's words: held"
has "$T/held.out" "only because the options changed since the answer" "…saying the options changed, as unmoved"
# round 3: an owner's two-paragraph pick in a gap is the owner's, as a one-line one is
git -C "$R" checkout -q -b gap2p "$BASE"
python3 - "$R/docs/d.md" <<'PY2'
import sys
p = sys.argv[1]; s = open(p).read()
open(p, "w").write(s.replace("## Action plan", "- **D1 — a second one**\n  - A — x\n  - B — y\n\n  ➤ Answer:\n\n## Action plan", 1))
PY2
git -C "$R" commit -qam "builder: a D-id twice" -m "$AGENT"
answer $'B\n\n  And keep the old flag for a week.'; git -C "$R" commit -qam "the owner's answer"
sed -i.bak 's/^- \*\*D1 — a second one\*\*/- **D2 — a second one**/' "$R/docs/d.md" && rm -f "$R/docs/d.md.bak"
git -C "$R" commit -qam "builder: the D-id fixed" -m "$AGENT"
check "$(held S1)" "0" "the owner's two-paragraph B in a gap: the owner's pick, not held"
# round 3: a ref named by its name: the note shows its commit
git -C "$R" checkout -q -b fixture/h/2026-11-05-topic "$BASE"
printf 'Task: build it\nSteps: S1 of docs/nowhere.md\n' > "$T/b21.md"
k held --brief "$T/b21.md" --ref refs/heads/fixture/h/2026-11-05-topic > "$T/held.out" 2>&1; check "$?" "4" "a doc absent at a named ref: could not judge"
has "$T/held.out" "is not on $(git -C "$R" rev-parse --short=12 HEAD)" "…naming the ref's commit, never refs/heads/c"
# round 3: the other worktree's newer release beats the ref's stale hold
git -C "$R" worktree add -q "$T/wt-later" -b design-later "$NOPICKED"
python3 - "$T/wt-later/docs/d.md" <<'PY2'
import re, sys
p = sys.argv[1]; s = open(p).read()
open(p, "w").write(re.sub(r"(  ➤ Answer:\n)(?:  .*\n)*", lambda m: m.group(1) + "  B\n", s, count=1))
PY2
git -C "$T/wt-later" commit -qam "the owner's B"
printf 'Task: build it\nSteps: S1 of %s/docs/d.md\n' "$T/wt-later" > "$T/b22.md"
k held --brief "$T/b22.md" --ref "$NOPICKED" > "$T/held.out" 2>&1; check "$?" "0" "a ref's no-pick, released by the owner's B in the worktree the brief names: not held"
# the finish review: a worktree that took the ref's no-pick in by a merge never walked it, so the ref's hold stands
git -C "$R" worktree add -q "$T/wt-merge" -b design-merge "$BASE"
echo x > "$T/wt-merge/other.txt"; git -C "$T/wt-merge" add other.txt; git -C "$T/wt-merge" commit -qm "builder: other work" -m "$AGENT"
git -C "$T/wt-merge" merge -q --no-ff --no-edit "$NOPICKED" -m "Merge the design" -m "$AGENT"
printf 'Task: build it\nSteps: S1 of %s/docs/d.md\n' "$T/wt-merge" > "$T/b23.md"
k held --brief "$T/b23.md" --ref "$NOPICKED" > "$T/held.out" 2>&1; check "$?" "3" "a ref's no-pick the brief's worktree merged in: held"
python3 - "$T/wt-merge/docs/d.md" <<'PY2'
import re, sys
p = sys.argv[1]; s = open(p).read()
open(p, "w").write(re.sub(r"(  ➤ Answer:\n)(?:  .*\n)*", lambda m: m.group(1) + "  B\n", s, count=1))
PY2
git -C "$T/wt-merge" commit -qam "the owner's B"
k held --brief "$T/b23.md" --ref "$NOPICKED" > "$T/held.out" 2>&1; check "$?" "0" "…then the owner's B in that worktree: released, as the worktree reads it (the finish review's round 2)"
git -C "$R" checkout -q --detach "$NOPICKED"
k lint --strict docs/d.md > "$T/lint.out" 2>&1
has "$T/lint.out" "only git's history can hold the step after it" "lint --strict on a no-pick that never met intake: never says nothing holds it"

echo
[ $fails -eq 0 ] && echo "picks: all passed" || echo "picks: $fails failed"
exit $((fails > 0))
