---
name: name
description: Take an idea note to a decided name — domain, GitHub org and package handles probed against the registries, priced, trademark-searched, and put to the owner as one naming doc with a decision list. Use for "name this", "find a name for <idea>", "is <name> free", or when an idea becomes a project and needs a name, domain and org.
argument-hint: <idea note or its title> [candidate names…]
effort: high
allowed-tools: Bash(name-check:*), Bash(*/bin/name-check:*), Bash(gh api:*), WebSearch
---

Name it: $ARGUMENTS

If this project has its own `/name` (`.claude/skills/name` or `.claude/commands/name.md`),
run that instead and stop here: the project's version wins.

The engine is `name-check` (its header lists every probe and why): on the Bash PATH while the
helloworld plugin is enabled; where this skill is linked in by hand instead, run it by path,
`../../bin/name-check` from this skill's base directory. The skill reads the idea, probes, searches trademarks and writes the doc. It never buys,
registers, creates or renames anything: a name ends at the owner's answer, and what follows is
section 6.

## 1. Read the idea

Find the idea note: a path, or match the words against the ideas folder the owner keeps (the
`ideas` link in the regatta config dir, `helloworld/ideas`, when there is one); ask when several
fit or none is named. Read it whole, `## Your notes` most of all: what the name must carry lives
there. Write down each meaning the note gives, quoted, with who wrote it and when.

- **A name the note already gives is given, not a candidate.** Then the job is to confirm it:
  alternatives are optional, and only ones that add a meaning the note did not have.
- A meaning you found yourself (a pun, a number's other life, a word in another language) is
  offered, and the doc says so — never folded into what the note said.
- No name in the note: up to eight candidates, each with the meaning from the note it carries.

## 2. Probe — registries, not recall

```
name-check <name> [<name>…] --tlds io,ai,dev,com
```

Add the TLDs the note mentions. Probe the handle forms too: a name with a hyphen and without
(`foo-labs` and `foolabs`), since an org may already sit on one of them. The table is the
registry's answer: `free` is not a registrar quote (a premium name still reads free) and `?`
is unknown, never free. Paste the table into the doc as printed, with its probe time.

Then look closer, with the same probes by hand, at what matters to the decision:

- A **taken handle** the name wants: `gh api users/<name>` — `type`, `created_at`, and for an
  org `gh api orgs/<name>/members` and repos. It may be the owner's own, made this week.
- A **taken domain** the name wants: its RDAP record (registered, expires, registrar,
  nameservers). Parked, lapsing soon, or a different field altogether — say which.
- The **product names** the note mentions get one `name-check` line each: a taken
  `<product>.dev` is a finding even if nobody asked.

**Short and sweet, every time** (the owner, 2026-10-11: "like google.com -> goog.le / g.co"). Beside
the full name, probe the short forms a person would rather type or print, one `name-check` run:

- **Domain hacks**: the name's last letters as its TLD (`unli.st`, `gener.al`, `admissi.on` —
  only where that TLD exists).
- **The name's own word for a TLD**: a word from its meaning as the second level, a real TLD as
  the rest (`admit.one` for a ticket, `ga.watch`).
- **Initials and stems** on a TLD that fits the field (`ga.one`, `unli.fm`).

`name-check` says `not at Porkbun` for a ccTLD it cannot price (`.st`, `.al`, `.film`): that
is not a no, and the doc names where it is sold. A two-letter or dictionary-word name that
reads `free` is the likeliest to be premium or registry-reserved: say so, priced only at the
cart. A short form is a redirect to the full domain unless it reads well aloud on its own; the
doc's D2 offers the best one or two, never a list.

## 3. Price

The table's last row is Porkbun's public price list: first year / renewal / 10 years. The
renewal is the real price; the first year is a loss-leader. Say what the list does not: .ai is
often sold with a two-year minimum; .dev and .app are on the HSTS preload list (HTTPS only,
which GitHub Pages provides).

## 4. Trademark

Web-search the name, alone and with the field the idea is in ("<name> software", "<name>
trademark", "<name> inc"). For each hit: who, since when, what they sell, and whether it is the
same trademark class (a cosmetics maker and a software tool rarely collide; a similar-sounding
software mark might). Search ranking counts too: who a search for the name finds first.

Then a **Not checked** line, always: the official registers (USPTO, EUIPO, WIPO). USPTO's search
has returned no machine-readable answer on every run so far, so the doc says to search
tmsearch.uspto.gov by hand before anything is filed or printed.

## 5. The doc

`docs/naming-<yyyy-mm-dd>.md` in the project the name is for (its worktree, per the git
workflow), or in the repo the idea will become; ask if neither exists. In this order:

1. `# Naming <Name> — <date>`, then **Where it came from**: the note's title and date, the
   meanings quoted, any offered meaning marked as offered.
2. **Where it stands**: one paragraph — the name, what is free, what is taken, what is not.
3. **Availability, probed <date>**: the `name-check` table and its notes; what section 2 found
   about taken handles and domains, in plain sentences.
4. **Price**: per TLD, first year, renewal, 10 years; the caveats from section 3.
5. **Trademark**: the hits, then **Not checked**.
6. **Also found**: what the probes turned up that nobody asked about.
7. **Decisions**: a legend line, then D1… each ending in `➤ Recommended: <pick>` and an empty
   `➤ Answer:` — the owner's alone; text there reads as answered. The usual set: D1 name (how it is written in
   prose and as a handle), D2 domain (which TLD, and why not the others, priced), D3 GitHub
   org (create, or rename one that exists — a rename someone else sees asks them first), then
   one per finding that needs an owner.
8. `## Your notes` with an empty comment block — the owner's.

Hand the doc to the owner the way this setup hands over a doc to answer (on its own branch, when
there is such a flow). When answers come back, reply under each (`> **Done.** …`) and record the
decision with its date and words.

## 6. After the answer

- **Buying is the owner's**, in the registrar's browser cart. Porkbun's API buys from account
  credit, not a card: one run's API purchase failed five times on it. A project's own buying
  script is for the owner's explicit "buy it", once, and the purchase is read back over RDAP
  (registered, expires, registrar), never assumed from the API's answer.
- **The org and handles**: create or rename only on the owner's answer; write the result into the
  doc's answer line.
- **The branding work** that follows (logo, wording, the site) gets its own branch and session,
  seeded with a brief naming this doc.
- A name for a project that does not exist yet goes on to the project's creation with the decided
  handle as its folder and repo name; once it is ready to go public, `helloworld` is the door.

End with the name, the doc as a link and the open decisions, and say that the owner's answer is
what the work waits on.
