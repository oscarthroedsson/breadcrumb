#!/usr/bin/env bash
# Tests bin/breadcrumb-init.sh against a throwaway target directory.

set -uo pipefail
cd "$(dirname "$0")/.."

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0

check() { # check <description> <condition-exit-code>
  if [ "$2" -eq 0 ]; then printf '%-52s %s\n' "$1" "pass"; pass=$((pass+1))
  else                    printf '%-52s %s\n' "$1" "FAIL"; fail=$((fail+1)); fi
}

./bin/breadcrumb-init.sh "$TMP" >/dev/null
[ -f "$TMP/.claude/HANDOFF.md" ];                    check "installs .claude/HANDOFF.md" $?
[ -x "$TMP/.claude/hooks/validate-handoff.sh" ];     check "installs an executable validator" $?

# The installed validator must actually work from its new location.
jq -n '{last_assistant_message:"```json\n{\"claim\":\"x\",\"confidence\":\"high\",\"evidence\":\"y\",\"blocked_on\":null}\n```"}' \
  | bash "$TMP/.claude/hooks/validate-handoff.sh" >/dev/null 2>&1
check "installed validator accepts a valid handoff" $?

jq -n '{last_assistant_message:"no block here"}' \
  | bash "$TMP/.claude/hooks/validate-handoff.sh" >/dev/null 2>&1
[ $? -eq 2 ];                                        check "installed validator rejects a bare report" $?

# HANDOFF.md is meant to be customised, so a re-run must not clobber it.
echo "LOCALLY EDITED" >> "$TMP/.claude/HANDOFF.md"
./bin/breadcrumb-init.sh "$TMP" >/dev/null
grep -q "LOCALLY EDITED" "$TMP/.claude/HANDOFF.md"
check "re-run keeps a customised HANDOFF.md" $?

./bin/breadcrumb-init.sh "$TMP" --force >/dev/null
grep -q "LOCALLY EDITED" "$TMP/.claude/HANDOFF.md"
[ $? -ne 0 ];                                        check "--force replaces HANDOFF.md" $?

./bin/breadcrumb-init.sh "$TMP/does-not-exist" >/dev/null 2>&1
[ $? -ne 0 ];                                        check "errors on a missing target directory" $?

printf '%s\n' "-----------------------------------------------------------"
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
