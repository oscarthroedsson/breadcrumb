#!/usr/bin/env bash
# breadcrumb — SubagentStop hook
#
# Reads the Claude Code hook payload on stdin, pulls the last ```json block out of
# `last_assistant_message`, and validates it against the handoff schema.
#
#   exit 0  report is valid, subagent may finish
#   exit 2  report is invalid, stderr is shown to the subagent, which must rewrite
#
# The hook never rewrites the agent's message. SubagentStop can only accept or
# block; only PreToolUse can modify anything. Validation, not mutation.
#
# It also gives up. After BREADCRUMB_MAX_RETRIES rejections for the same agent it
# lets the report through with a warning, because an agent that cannot satisfy the
# schema is usually obeying a conflicting instruction it inherited, and looping
# until maxTurns burns the run without telling anyone why.
#
# Fails OPEN when jq is missing: a missing dependency must never wedge an agent loop.

set -uo pipefail

if ! command -v jq >/dev/null 2>&1; then
  echo "breadcrumb: jq not found, skipping handoff validation" >&2
  exit 0
fi

payload=$(cat)
message=$(printf '%s' "$payload" | jq -r '.last_assistant_message // ""')

MAX_RETRIES="${BREADCRUMB_MAX_RETRIES:-2}"
STATE_DIR="${TMPDIR:-/tmp}/breadcrumb-attempts"
session=$(printf '%s' "$payload" | jq -r '.session_id // "nosession"')
agent=$(printf '%s' "$payload"   | jq -r '.agent_id // "noagent"')
counter="$STATE_DIR/$(printf '%s-%s' "$session" "$agent" | tr -c 'A-Za-z0-9._-' '_')"
mkdir -p "$STATE_DIR" 2>/dev/null

attempts=0
[ -f "$counter" ] && attempts=$(cat "$counter" 2>/dev/null || echo 0)

# reject <message...> — blocks the finish, or gives up once the budget is spent.
reject() {
  attempts=$((attempts + 1))
  printf '%s' "$attempts" > "$counter" 2>/dev/null

  if [ "$attempts" -gt "$MAX_RETRIES" ]; then
    rm -f "$counter" 2>/dev/null
    echo "breadcrumb: gave up after $MAX_RETRIES rejections — letting the report through." >&2
    echo "  The agent could not produce a valid handoff block. The usual cause is an" >&2
    echo "  instruction it inherited (CLAUDE.md, project conventions) that conflicts" >&2
    echo "  with the schema. The report above is unvalidated; read it yourself." >&2
    exit 0
  fi

  printf '%s\n' "$@" >&2
  echo "Re-send your final message with a corrected block. See .claude/HANDOFF.md." >&2
  echo "(attempt $attempts of $((MAX_RETRIES + 1)))" >&2
  exit 2
}

accept() {
  rm -f "$counter" 2>/dev/null
  exit 0
}

# Last complete ```json fence in the message.
block=$(printf '%s\n' "$message" | awk '
  /^[[:space:]]*```json[[:space:]]*$/  { inblock=1; buf=""; next }
  inblock && /^[[:space:]]*```[[:space:]]*$/ { inblock=0; last=buf; next }
  inblock                              { buf = buf $0 "\n" }
  END                                  { printf "%s", last }
')

if [ -z "${block//[[:space:]]/}" ]; then
  reject "breadcrumb: your report has no \`\`\`json handoff block." \
         "Another agent reads this report and cannot infer what you left out." \
         "End your final message with a fenced json block containing claim," \
         "confidence, evidence and blocked_on."
fi

if ! printf '%s' "$block" | jq -e . >/dev/null 2>&1; then
  reject "breadcrumb: the handoff block is not valid JSON."
fi

problems=$(printf '%s' "$block" | jq -r '
  def check($o; $i):
    ( ["claim","confidence","evidence","blocked_on"] - ($o | keys)
      | if length > 0 then ["object \($i): missing field(s): \(join(", "))"] else [] end )
    + ( if ($o | has("confidence")) and ((["high","medium","low"] | index($o.confidence)) == null)
        then ["object \($i): confidence must be high|medium|low, got \($o.confidence | tojson)"]
        else [] end )
    + ( if (($o.claim? // "") | tostring | length) == 0
        then ["object \($i): claim is empty"] else [] end )
    + ( if (($o.evidence? // "") | tostring | length) == 0
        then ["object \($i): evidence is empty"] else [] end );

  (if type == "array" then . else [.] end)
  | to_entries
  | map(if (.value | type) != "object"
        then ["object \(.key): not an object"]
        else check(.value; .key) end)
  | flatten | .[]
')

if [ -n "$problems" ]; then
  reject "breadcrumb: handoff block does not satisfy the schema." "$problems"
fi

accept
