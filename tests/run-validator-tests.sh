#!/usr/bin/env bash
# Runs every fixture in tests/fixtures through the SubagentStop validator.
# Fixture naming: <name>.<expected exit code>.txt

set -uo pipefail
cd "$(dirname "$0")/.."

HOOK="templates/hooks/validate-handoff.sh"
pass=0; fail=0

printf '%-28s %-8s %-8s %s\n' "FIXTURE" "EXPECT" "GOT" "RESULT"
printf '%s\n' "-----------------------------------------------------------"

for f in tests/fixtures/*.txt; do
  base=$(basename "$f" .txt)
  name=${base%.*}
  expected=${base##*.}

  # Build the same payload Claude Code sends a SubagentStop hook.
  payload=$(jq -n --rawfile msg "$f" \
    '{hook_event_name:"SubagentStop", agent_id:"test", last_assistant_message:$msg}')

  stderr=$(printf '%s' "$payload" | bash "$HOOK" 2>&1 >/dev/null)
  got=$?

  if [ "$got" = "$expected" ]; then
    printf '%-28s %-8s %-8s %s\n' "$name" "$expected" "$got" "pass"
    pass=$((pass+1))
  else
    printf '%-28s %-8s %-8s %s\n' "$name" "$expected" "$got" "FAIL"
    [ -n "$stderr" ] && printf '  stderr: %s\n' "$stderr"
    fail=$((fail+1))
  fi
done

printf '%s\n' "-----------------------------------------------------------"
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
