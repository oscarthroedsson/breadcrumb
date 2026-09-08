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
