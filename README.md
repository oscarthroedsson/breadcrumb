# breadcrumb

A four-field handoff block and a `SubagentStop` hook that refuses to let a
subagent finish without one.

**It did not work, and the repository exists to say so.** Measured across three
compression levels and 60 trials, the schema changed no downstream decision. The
problem it was built to solve did not reproduce. Results: [`docs/test-results.md`](docs/test-results.md).

Read on for the argument that motivated it, the experiment that disconfirmed it,
and the tool itself, which works and is not recommended.

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

That was the argument. It is wrong, or at least it did not survive contact with
a measurement — see [Does it actually help?](#does-it-actually-help) below. Under
a hard 25-word cap the model kept every hedge and dropped the elaboration
instead.

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

`maxTurns` is the outer brake, but the hook has its own: it gives up after two
rejections and lets the report through with a warning. An agent that cannot
satisfy the schema is usually obeying an instruction it inherited, and looping
until `maxTurns` burns the run without telling anyone why. Tune the budget with
`BREADCRUMB_MAX_RETRIES`.

The hook never rewrites the agent's message. `SubagentStop` can only accept or
block — only `PreToolUse` can modify anything. Validation, not mutation.

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

No.

`eval/` is an A/B harness that measures the thing that matters: whether the
*next* agent is misled. Three arms get the same raw observations and the same
scenario, differing only in the investigator's system prompt — a 25-word cap, a
90-word cap, or the schema. Stage two is byte-identical in all three: a second
agent reads the report and answers `VERDICT: SAFE` or `VERDICT: NOT_SAFE`.

Ground truth is `NOT_SAFE` — the root cause is unconfirmed and the fix's value is
undocumented, and in this scenario both blockers sit inside sentences about
something else. A `SAFE` verdict means the report misled the agent that read it.
Binary, so scoring needs no judge model.

```
ARM           TRIALS   CORRECT  MISLED(SAFE)   OUT_TOKENS   WORDS   STAGE-1 COST
--------------------------------------------------------------------------------
terse             20        20             0           80      26         $0.290
control           20        20             0          245     100         $0.289
breadcrumb        20        20             0          421     172         $0.239
```

60 of 60. Here is a 26-word report from the `terse` arm:

> Root cause unconfirmed. Leading suspects: (1) missing JWT_SECRET in CI env,
> (2) stale/rotated staging JWT secret from June. CI logs unavailable. Untested:
> SSO login, token refresh paths.

Nothing decision-relevant is missing. Hedges are the highest-information tokens
in a finding, and a model under pressure spends its last words on them — it drops
which file and what it would do next, not what it failed to verify.

Cost was flat across arms while output ranged from 80 to 421 tokens, because
input dominates. The schema arm was the cheapest one.

Reproduce it:

```bash
eval/run.sh 20 sonnet   # 1 preflight call, then 120 real ones
eval/score.sh
```

The full write-up, including what these runs do **not** rule out — weaker models,
chains longer than one hop, findings with many independent caveats — is in
[`docs/test-results.md`](docs/test-results.md).

## Tests

```bash
tests/run.sh
```

46 tests, no API calls: 12 for the validator, 11 for its retry budget, 7 for the
installer, 5 for the eval scorer, 11 for the eval runner (which drives a stubbed
CLI in `tests/stubs/`).

The scorer tests exist because a scorer that silently miscounts is worse than no
eval at all. The runner tests exist because the first version of this harness met
an unauthenticated CLI and answered with twenty `UNPARSEABLE` lines and no
explanation, having spent twenty calls to say nothing.

## When not to use this

On this evidence: by default. The cases below were written when the premise still
looked sound, and they remain the places it would fail hardest.

- **Single-agent work.** There is no handoff to protect.
- **Agents reporting to a human.** Prose caveats survive human review.
- **Throwaway exploration.** The schema costs a turn it will not earn back.

If you want to use it anyway, the honest reason is not reliability — it is that a
machine-readable block is easier for *other tooling* to consume than prose. That
is a different argument, and this repository has not tested it.

## Why not just make agents terser?

You can. That was the question this project started from, and the measured answer
is that a 25-word agent-to-agent dialect cost nothing in decision quality here.

The reason to be unexcited about it is different from the one this README
originally gave: inter-agent messages are a small share of total spend, because
input tokens dominate. Run 2 shows it directly — a fivefold difference in output
length moved cost by less than 20%, in the wrong direction. Compressing what
agents say to each other optimises a rounding error.

## License

MIT. See [LICENSE](LICENSE).
