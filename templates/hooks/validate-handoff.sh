#!/usr/bin/env bash
# breadcrumb — SubagentStop hook
#
# Reads the Claude Code hook payload on stdin, pulls the last ```json block out of
# `last_assistant_message`, and validates it against the handoff schema.
#
#   exit 0  report is valid, subagent may finish
#   exit 2  report is invalid, stderr is shown to the subagent, which must rewrite
#
# Fails OPEN when jq is missing: a missing dependency must never wedge an agent loop.

set -uo pipefail

if ! command -v jq >/dev/null 2>&1; then
  echo "breadcrumb: jq not found, skipping handoff validation" >&2
  exit 0
fi

payload=$(cat)
message=$(printf '%s' "$payload" | jq -r '.last_assistant_message // ""')

# Last complete ```json fence in the message.
block=$(printf '%s\n' "$message" | awk '
  /^[[:space:]]*```json[[:space:]]*$/  { inblock=1; buf=""; next }
  inblock && /^[[:space:]]*```[[:space:]]*$/ { inblock=0; last=buf; next }
  inblock                              { buf = buf $0 "\n" }
  END                                  { printf "%s", last }
')

if [ -z "${block//[[:space:]]/}" ]; then
  cat >&2 <<'MSG'
breadcrumb: your report has no ```json handoff block.
Another agent reads this report and cannot infer what you left out.
Re-send your final message ending with a fenced json block containing
claim, confidence, evidence and blocked_on. See .claude/HANDOFF.md.
MSG
  exit 2
fi

if ! printf '%s' "$block" | jq -e . >/dev/null 2>&1; then
  echo "breadcrumb: the handoff block is not valid JSON. Re-send it, parseable." >&2
  exit 2
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
  {
    echo "breadcrumb: handoff block does not satisfy the schema."
    printf '%s\n' "$problems"
    echo "Re-send your final message with a corrected block. See .claude/HANDOFF.md."
  } >&2
  exit 2
fi

exit 0
