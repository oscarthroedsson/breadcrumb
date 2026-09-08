---
name: breadcrumb
description: Set up enforced agent-to-agent handoffs in this project — installs the handoff schema, the SubagentStop validator, and wires chosen subagents to it. Use when the user says "/breadcrumb", asks to set up breadcrumb, wants subagents to report in a structured format, wants to stop agents passing guesses along as facts, or asks how to make multi-agent handoffs reliable.
---

# breadcrumb — set up enforced handoffs

Subagents that report to other agents drop the words carrying the most information:
hedges, negations, provenance. This skill installs a four-field JSON handoff block
and a `SubagentStop` hook that refuses to let an agent finish without one.

## Flow

Do these in order. Report what changed after each numbered step, briefly.

### 1. Install the files

```bash
<path-to-breadcrumb>/bin/breadcrumb-init.sh
```

Run from the project root. It writes `.claude/HANDOFF.md` and
`.claude/hooks/validate-handoff.sh`, and leaves an existing `HANDOFF.md` alone.

If `jq` is missing it says so. Tell the user: the validator fails open without
`jq`, so the format is documented but not enforced. `brew install jq` fixes it.

### 2. Find the subagents

```bash
ls .claude/agents/*.md ~/.claude/agents/*.md 2>/dev/null
```

Only project agents (`.claude/agents/`) should be wired by default — a user-level
agent is shared across every project and wiring it here would surprise them.

**If no agents exist:** offer to create one from
`<path-to-breadcrumb>/templates/agents/investigator.md`, and say plainly that
breadcrumb does nothing until at least one agent hands off to another.

### 3. Ask which agents to wire

Ask once, listing the agents by name with their `description` line so the choice is
informed. Wire only agents whose output another agent reads. An agent that only
ever reports to the human does not need this — a person notices a missing caveat.

### 4. Wire each chosen agent

Add to its frontmatter (keep existing fields):

```yaml
maxTurns: 25
hooks:
  SubagentStop:
    - hooks:
        - type: command
          command: ${CLAUDE_PROJECT_DIR}/.claude/hooks/validate-handoff.sh
```

`maxTurns` is not optional. A `SubagentStop` hook that keeps rejecting can loop
with an agent that keeps failing to satisfy it; `maxTurns` is the brake.

Then append to the agent's body:

```markdown
## Handoff

Another agent reads your report. End it with a fenced json block containing
`claim`, `confidence` (high|medium|low), `evidence` and `blocked_on` (null if
nothing blocks). Never state at high confidence something you inferred rather
than observed. Full format: `.claude/HANDOFF.md`.

Other formatting instructions apply to your prose, not to the block. The block's
shape is fixed and overrides them.
```

### 5. Verify it actually fires

```bash
jq -n '{last_assistant_message:"done, looks fine"}' \
  | bash .claude/hooks/validate-handoff.sh; echo "exit: $?"
```

Expect exit 2 and a message about the missing block. If it exits 0, `jq` is
missing or the file is not executable — say which, do not report success.

### 6. Report

State: which files were written, which agents were wired, and the verification
exit code. If anything was skipped, say what and why.

## If an agent keeps failing the hook

The hook gives up after two rejections and lets the report through with a warning,
so this never burns a whole run. But if you see `breadcrumb: gave up` repeatedly
from the same agent, something it inherited is fighting the schema:

```bash
grep -niE "never|aldrig|no code|max .* lines|kort|brief" CLAUDE.md ~/.claude/CLAUDE.md 2>/dev/null
```

`CLAUDE.md` is inherited by subagents; an output style is not. A presentation rule
living in `CLAUDE.md` therefore reaches every agent you wire.

Report what you found and let the user decide. Do not edit their `CLAUDE.md`.
Moving presentation rules into an output style is one fix; adding an explicit
exception for the block is another; living with the warning is a third.

## When not to use this

- Single-agent work. There is no handoff to protect.
- Agents that only report to a human. Prose caveats survive human review.
- Exploratory or research agents whose output is read once and discarded — the
  schema costs a turn it will not earn back.
