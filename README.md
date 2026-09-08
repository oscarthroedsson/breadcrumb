# breadcrumb

Agents that report to other agents drop the words that matter most.

`breadcrumb` is a four-field handoff block and a `SubagentStop` hook that refuses
to let a subagent finish without one.

---

## The problem

Here is one finding, at three levels of compression:

```
"Det verkar som att JWT_SECRET inte laddas i CI — jag har inte kunnat bekräfta
 det, för jag kommer inte åt CI-loggarna. Verifiera att den matchar prod först."

"Trolig orsak: JWT_SECRET saknas i CI. Obekräftat. Verifiera mot prod först."

"JWT_SECRET missing CI. add workflow."
```

The first two are fine. A human reads either and knows not to act yet.

The third is what agent-to-agent traffic converges on, because nothing stops it.
Compression eats hedges, negations and provenance first — they look like filler
and carry the most information per token. Three things were lost: *trolig* became
fact, *obekräftat* became silence, *verifiera först* disappeared. The next agent
adds the secret, guesses the value, and ships the wrong one.

This is not a writing problem. It is a protocol problem, and it needs a protocol.

## The format

```json
{
  "claim": "auth.spec.ts returns 401 in CI — JWT_SECRET appears not to be loaded",
  "confidence": "medium",
  "evidence": "passes locally, fails in CI; CI logs not accessible from here",
  "blocked_on": "confirm the workflow secret matches the one prod uses"
}
```

Four required fields. `confidence` is the hedge, as a field, so it cannot be
dropped. `evidence` separates what was seen from what was inferred. `blocked_on`
is `null` when nothing blocks — writing `null` is a statement, omitting the field
is not. Optional: `proposed_fix`, `not_checked`, `files`.

The prose before the block may be as terse as you like. The block may not.

Full spec: [`templates/HANDOFF.md`](templates/HANDOFF.md).
Why it is enforced rather than suggested: [ADR 0001](docs/adr/0001-handoff-schema.md).

## Setup

```bash
git clone https://github.com/OscarThroedsson/breadcrumb.git ~/code/breadcrumb
cd /path/to/your/project
~/code/breadcrumb/bin/breadcrumb-init.sh
```

That writes `.claude/HANDOFF.md` and `.claude/hooks/validate-handoff.sh`. Then add
to any agent in `.claude/agents/` whose output another agent reads:

```yaml
maxTurns: 25
hooks:
  SubagentStop:
    - hooks:
        - type: command
          command: ${CLAUDE_PROJECT_DIR}/.claude/hooks/validate-handoff.sh
```

`maxTurns` is not optional. A `SubagentStop` hook that keeps rejecting can loop
with an agent that keeps failing to satisfy it.

Requires [`jq`](https://jqlang.github.io/jq/). Without it the validator fails
**open** — a missing dependency must never wedge an agent loop — so the format is
documented but not enforced.

### As a skill

Copy [`skills/breadcrumb/`](skills/breadcrumb/SKILL.md) into `~/.claude/skills/`
and run `/breadcrumb` in a project. It installs the files, lists your agents,
asks which ones hand off to other agents, wires those, and verifies the hook
actually fires before reporting success.

## Three layers, cheapest first

| Layer | Cost | Guarantee |
|---|---|---|
| A paragraph in `CLAUDE.md` | 2 min | None, but inherited by every subagent automatically |
| The paragraph in each agent's body | 10 min | Agents produce the block on the first try |
| The `SubagentStop` hook | 20 min | Enforced — exit 2 blocks the finish and forces a rewrite |

Use all three. The hook alone works, but costs a wasted turn on every handoff,
because the agent only learns the requirement by failing it.

## Does it actually help?

`eval/` is an A/B harness that measures the thing that matters: whether the
*next* agent is misled.

Both arms get the same raw observations and the same instruction to be concise
under a tight token budget. Only the breadcrumb arm gets the schema. Stage two is
byte-identical in both arms: a second agent reads the report and answers
`VERDICT: SAFE` or `VERDICT: NOT_SAFE`.

The scenario's ground truth is `NOT_SAFE` — the root cause is unconfirmed and the
secret value is itself suspect. Any `SAFE` verdict means the report misled the
agent that read it. Binary, so scoring needs no judge model.

```bash
eval/run.sh 5 sonnet   # 1 preflight call, then 20 real ones, ~$0.40
eval/score.sh
```

The runner probes the CLI with one cheap call before spending the rest. If the
`claude` CLI is not logged in it stops there and says so — the CLI has its own
authentication, separate from the desktop app, so `claude` followed by `/login`
once is usually all it needs.

```
ARM           TRIALS   CORRECT  MISLED(SAFE)      UNPARSEABLE   OUT_TOKENS
--------------------------------------------------------------------------
control            5         ?             ?                ?            ?
breadcrumb         5         ?             ?                ?            ?
```

**Results are not filled in yet.** They will be published in
[`docs/test-results.md`](docs/test-results.md) with the raw transcripts, once the
harness has been run against a real account. Do not cite a number for this
project until that file exists — the harness is tested, the hypothesis is not.

## Tests

```bash
tests/run.sh
```

35 tests, no API calls: 12 for the validator, 7 for the installer, 5 for the eval
scorer, 11 for the eval runner (which drives a stubbed CLI in `tests/stubs/`).

The scorer tests exist because a scorer that silently miscounts is worse than no
eval at all. The runner tests exist because the first version of this harness met
an unauthenticated CLI and answered with twenty `UNPARSEABLE` lines and no
explanation, having spent twenty calls to say nothing.

## When not to use this

- **Single-agent work.** There is no handoff to protect.
- **Agents reporting to a human.** Prose caveats survive human review.
- **Throwaway exploration.** The schema costs a turn it will not earn back.

## Why not just make agents terser?

That was the original idea, and it is the wrong axis. Inter-agent messages are a
small share of total spend in a fleet — file contents, tool output and system
prompts dominate — while a single misunderstanding costs a whole re-run. And
terseness compresses exactly the epistemic markers this project exists to protect.
`confidence: medium` costs three tokens. It is the only thing between a guess and
a deploy.

## License

MIT. See [LICENSE](LICENSE).
