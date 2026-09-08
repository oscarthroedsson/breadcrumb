# ADR 0001 — A required JSON block, not a prose convention

**Status:** accepted
**Date:** 2026-09-08

## Context

When several agents work in a chain, each one's report becomes the next one's input.
The failure mode is not that agents write badly — it is that compression eats the
words carrying the most information per token: hedges, negations and provenance.

Observed pattern, same finding at three levels of compression:

```
"Det verkar som att JWT_SECRET inte laddas i CI — jag har inte kunnat bekräfta det,
 för jag kommer inte åt CI-loggarna. Verifiera att den matchar prod innan du agerar."

"Trolig orsak: JWT_SECRET saknas i CI. Obekräftat. Verifiera mot prod först."

"JWT_SECRET missing CI. add workflow."
```

The third version is what agent-to-agent traffic converges on, because no social
brake stops it. Three things were lost: `trolig` became fact, `obekräftat` became
silence, `verifiera först` disappeared. The receiving agent acts on a guess.

## Decision

Every agent that hands off to another agent ends its report with a fenced `json`
block containing four required fields:

| Field | Type | Why it is required |
|---|---|---|
| `claim` | string | The finding itself. |
| `confidence` | `high` \| `medium` \| `low` | The hedge, as a field so it cannot be dropped. |
| `evidence` | string | What was actually observed, separating fact from inference. |
| `blocked_on` | string \| null | What must be true before acting. `null` is an explicit statement, not an omission. |

Prose before the block may be as terse as the agent likes. The block may not be
abbreviated.

## Alternatives considered

**A. Prose convention in CLAUDE.md only.** Cheapest, inherited by subagents
automatically. Rejected as the sole mechanism: nothing enforces it, and the fields
that get dropped are exactly the ones an agent under token pressure judges optional.
Kept as layer one — see `docs/layers.md`.

**B. A caveman/telegraphic style for agent traffic.** Rejected. It optimises the
wrong axis. Inter-agent messages are a small share of total token spend in a fleet
(file contents, tool output and system prompts dominate), while a single
misunderstanding costs a whole re-run. It also compresses precisely the epistemic
markers this ADR exists to protect.

**C. Required JSON block, validated by a `SubagentStop` hook.** Chosen. The hook
receives `last_assistant_message` and can block the subagent from finishing with
exit code 2, which forces it to rewrite. This is the only layer that actually
guarantees the format.

## Consequences

- A `SubagentStop` hook that always exits 2 can loop. Every agent shipped with
  breadcrumb sets `maxTurns` as the brake.
- The hook is scoped per agent via frontmatter, not globally in `settings.json`,
  so it does not fire on unrelated subagents in other projects.
- The schema costs roughly 30 tokens per handoff. `confidence: medium` alone is
  three of them, and is the only thing standing between a guess and a deploy.
