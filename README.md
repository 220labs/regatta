<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/banner-night.svg">
  <img src="assets/banner-day.svg" alt="Sailboats cross a finish line under fireworks, drawn in text characters">
</picture>

# Regatta

**Regatta is an open framework for a business run by agents. You make the decisions; the agents
do the rest.**

For a founder or a small team with more ideas than hours. Say an idea into your phone; agents
weigh it against your goals, plan it, build it and ship it, then count what happened and write
down what was learnt. You see only the questions that need you, in one document, each with a
recommendation, and every answer is kept with your name on it.

Public Beta: several small businesses already run on it unattended, for the people who started
them. The 220 Labs team supports integrations and pilots, big and small: get in touch at
[220labs.dev/regatta](https://220labs.dev/regatta/).

It runs on Claude Code. Each module is a plugin of its own: take one, or all of them. Every
module needs the core.

| Module | What it does |
| --- | --- |
| [`regatta`](modules/regatta/README.md) | The shared base every module stands on |
| [`atlas`](modules/atlas/README.md) | Writes down what was learnt, where the next agent looks |
| [`helloworld`](modules/helloworld/README.md) | Names a project and publishes it behind a privacy scan |
| [`plumb`](modules/plumb/README.md) | Counts your time per project and what the agents cost |
| [`keel`](modules/keel/README.md) | Puts the questions that need you in one document and takes your answers back |
| [`wharf`](modules/wharf/README.md) | Gives each agent its own branch and lands its work through review |
| [`wharf-runs`](modules/wharf-runs/README.md) | Starts agents on work while nobody is at the keyboard |
| [`helm`](modules/helm/README.md) | Breaks a large idea into steps and keeps the agents on them moving |
| [`aurora`](modules/aurora/README.md) | Reads the week overnight and suggests what to change |

## Install

From a clone, the shell face first: `sh modules/regatta/install.sh` names the clone in the
config dir, then `sh modules/<module>/install.sh --check` says what a module still needs.

In Claude Code: `claude plugin marketplace add 220labs/regatta`, then
`claude plugin install regatta@regatta` and any module, e.g. `claude plugin install helloworld@regatta`.

## Report a bug

In Claude Code, `/regatta:flare <what went wrong>` files it as an issue here, with the versions and
the failing output attached, after showing it to you. Or open a Bug or an Idea on the repo's
[Issues](https://github.com/220labs/regatta/issues/new/choose) page.

## Check

`claude plugin validate --strict . && bash modules/regatta/tests/check.sh && bash modules/helloworld/tests/check.sh && bash modules/plumb/tests/check.sh && { [ ! -f modules/keel/hooks/sheep_gate.py ] || bash modules/keel/tests/check.sh; } && bash modules/sextant/tests/check.sh && bash modules/wharf-runs/tests/check.sh && bash modules/lighthouse/tests/check.sh && bash modules/wharf/tests/check.sh && bash modules/aurora/tests/check.sh && bash modules/atlas/tests/check.sh && { [ ! -f modules/keel/hooks/sheep_gate.py ] || [ ! -f modules/wharf-runs/bin/dispatch ] || bash modules/helm/tests/check.sh; }`

Licence: MIT (`LICENSE`).
