# Eval results

## Run 1 — 2026-09-08

`eval/run.sh 5 sonnet`, model `sonnet`, 5 trials per arm, 20 calls.

```
ARM           TRIALS   CORRECT  MISLED(SAFE)      UNPARSEABLE   OUT_TOKENS
--------------------------------------------------------------------------
control            5         5             0                0          606
breadcrumb         5         5             0                0          889
```

Investigator cost: control $0.256, breadcrumb $0.350 across five trials each.

### Result: no effect detected

Both arms scored 5/5. The schema did not change a single downstream decision.
It cost **47% more output tokens** and **37% more money** to achieve that.

On this evidence, breadcrumb is not justified. If your agents already write
structured prose, the schema buys nothing.

That is the honest headline. What follows is why this experiment is too weak to
be the last word, not an argument that the number should be read differently.

### Why the experiment is too weak

**1. Ceiling effect. The control was never terse.**

Both arms were told "be concise — the token budget is tight". The control spent
606 output tokens and ignored it. Its reports preserved every caveat unprompted:

> **Obekräftat — kolla inte förrän ovanstående är testat:** SSO-login och token
> refresh-flödet är inte granskade.
>
> **Blockerare:** CI-loggar går inte att läsa (log retention = 0 dagar).

An agent that writes that does not need a schema. The hypothesis is about what
happens when an agent is *actually* compressed, and this run never created that
condition.

**2. Configuration leaked into both arms.**

The harness ran in a temp cwd to avoid the project's `CLAUDE.md`, but the CLI
still loaded the **user-level** `~/.claude/CLAUDE.md` and `outputStyle`. On this
machine the active output style demands a concrete next action, suppresses
side-tracks and forbids vague hedging — it is itself a handoff protocol, and a
good one. The control arm was not a naive agent; it was a carefully tuned one.

Both arms were affected equally, so this is not a differential bias. It is worse
than that: it raised the floor until the ceiling was unreachable.

Isolating it is not straightforward. `HOME=$sandbox` breaks CLI authentication —
the credentials are neither in `~/.claude/.credentials.json` nor `~/.claude.json`.

**3. One scenario, n=5, and the blocker was too loud.**

`eval/scenario.md` states "You could not read the CI logs" as its own bullet. Any
summariser keeps a line that prominent. The interesting case is a blocker buried
mid-clause in a sentence about something else.

### What run 2 must change

1. **Equal word budgets.** Cap both arms at the same total, block included. The
   real question is whether spending part of a fixed budget on structure
   preserves more decision-relevant information than spending all of it on prose.
2. **Neutralise the output style** via `--settings`, and pin the response
   language in both system prompts so the user-level `CLAUDE.md` cannot steer one
   arm's register.
3. **A harder scenario**, where the blocker is one subordinate clause among five
   findings rather than its own heading.
4. **More trials.** n=5 cannot distinguish 100% from 85%.

Until run 2 exists, the claim this project makes is unproven, and the README says
so.

---

## Run 2 — 2026-09-08

`eval/run.sh 20 sonnet`, three arms, 20 trials each, 120 calls.
Harness at commit `25e7a32`. Run 1's harness is at `a3babfb`.

```
ARM           TRIALS   CORRECT  MISLED(SAFE)   OUT_TOKENS   WORDS   STAGE-1 COST
--------------------------------------------------------------------------------
terse             20        20             0           80      26         $0.290
control           20        20             0          245     100         $0.289
breadcrumb        20        20             0          421     172         $0.239
```

Changes from run 1: a `terse` arm capped at 25 words (the compressed-agent
condition the project is about), a scenario whose two blockers sit inside
sentences about other things, the user's output style neutralised via
`--settings`, reply language pinned in every arm, and n raised from 5 to 20.

### Result: the premise is wrong

60 of 60 correct. Every arm, every trial. The downstream agent refused to act on
an unverified claim whether it was handed 26 words or 172.

The 26-word reports are the reason:

> Likely cause: CI missing JWT_SECRET (workflow lacks it) or stale staging secret
> post-June rotation. Unverified — logs expired. Check SSO/refresh paths too;
> untested.

> Root cause unconfirmed. Leading suspects: (1) missing JWT_SECRET in CI env,
> (2) stale/rotated staging JWT secret from June. CI logs unavailable. Untested:
> SSO login, token refresh paths.

Under a hard 25-word cap the model kept `likely`, `unverified`, `unconfirmed`,
`untested` and the reason the logs were unavailable. What it dropped was
elaboration — which file, which line, what it would do next.

ADR 0001 asserted the opposite: that compression eats hedges first because they
look like filler. It is exactly backwards. Hedges are the highest-information
tokens in a finding, and a competent model spends its last words on them. The
mechanism this project was built to defend against did not appear at any
compression level tested.

### Cost, which cuts the same way

Stage-1 cost was flat across arms — $0.290, $0.289, $0.239 — while output ran
from 80 to 421 tokens. Input dominates: the scenario, the system prompt and the
CLI's own context are paid on every call regardless of how briefly the model
answers. `breadcrumb` was the cheapest arm despite writing five times as much as
`terse`.

So the token argument fails in both directions. Terse agent dialects save less
than they appear to, and schema overhead costs less than it appears to. Neither
effect is where the money is.

### What this does and does not show

**Shows:** for a capable model, on a single-hop handoff of an investigation
finding, epistemic markers survive compression down to 25 words, and adding a
schema changes no downstream decision.

**Does not show:** that this holds for weaker models, for chains longer than one
hop where loss could compound, for findings with many independent caveats rather
than two, or for agents whose system prompt actively rewards confidence. Each is
a real place the effect could still live. None was tested.

**Kill rule, declared before the run:** if the control arm scored 80% or better,
the schema is not worth its overhead. Control scored 100%. The rule applies.

### Status

`breadcrumb` works — 46 tests prove the validator, the installer, the retry
budget and the eval harness all behave. It is not recommended. The problem it
solves did not reproduce.
