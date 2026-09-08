#!/usr/bin/env bash
# The hook must bound its own rejections. An agent obeying a conflicting inherited
# instruction cannot satisfy the schema, and looping until maxTurns burns the run
# without telling anyone why.

set -uo pipefail
cd "$(dirname "$0")/.."

HOOK="templates/hooks/validate-handoff.sh"
export TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

pass=0; fail=0
check() {
  if [ "$2" -eq 0 ]; then printf '%-52s %s\n' "$1" "pass"; pass=$((pass+1))
  else                    printf '%-52s %s\n' "$1" "FAIL"; fail=$((fail+1)); fi
}

BAD="no handoff block here"
GOOD='```json
{"claim":"x","confidence":"high","evidence":"y","blocked_on":null}
```'

# run <agent> <message> -> sets $rc and $err
run() {
  err=$(jq -n --arg m "$2" --arg a "$1" \
        '{session_id:"retry-suite", agent_id:$a, last_assistant_message:$m}' \
        | bash "$HOOK" 2>&1 >/dev/null)
  rc=$?
}

run a "$BAD"; [ "$rc" -eq 2 ];                  check "1st bad report is rejected" $?
grep -q "attempt 1 of 3" <<<"$err";             check "tells the agent which attempt it is on" $?
run a "$BAD"; [ "$rc" -eq 2 ];                  check "2nd bad report is rejected" $?
run a "$BAD"; [ "$rc" -eq 0 ];                  check "3rd bad report is let through" $?
grep -q "gave up" <<<"$err";                    check "says it gave up rather than passing silently" $?
grep -q "unvalidated" <<<"$err";                check "warns the report is unvalidated" $?
grep -qi "CLAUDE.md" <<<"$err";                 check "names the likely cause" $?

# The budget is per agent, not global.
run b "$BAD"; [ "$rc" -eq 2 ];                  check "a different agent starts with a full budget" $?

# A success clears the count, so a later slip gets the full budget again.
run c "$BAD"; run c "$GOOD"; [ "$rc" -eq 0 ];   check "a valid report is accepted" $?
run c "$BAD"; [ "$rc" -eq 2 ]
grep -q "attempt 1 of 3" <<<"$err";             check "success resets the retry count" $?

# The budget is configurable for projects that want a stricter or looser loop.
BREADCRUMB_MAX_RETRIES=0 run d "$BAD"; [ "$rc" -eq 0 ]
check "BREADCRUMB_MAX_RETRIES=0 gives up immediately" $?

printf '%s\n' "-----------------------------------------------------------"
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
