#!/usr/bin/env bash
# Tests eval/run.sh against a stubbed claude CLI. No API calls.
#
# The regression this exists for: an unauthenticated CLI used to produce twenty
# UNPARSEABLE lines and no explanation, having spent twenty calls to say nothing.

set -uo pipefail
cd "$(dirname "$0")/.."

pass=0; fail=0
check() {
  if [ "$2" -eq 0 ]; then printf '%-52s %s\n' "$1" "pass"; pass=$((pass+1))
  else                    printf '%-52s %s\n' "$1" "FAIL"; fail=$((fail+1)); fi
}

STUBDIR="$PWD/tests/stubs"
restore() { rm -rf eval/out; }
trap restore EXIT

# --- unauthenticated CLI ------------------------------------------------------
out=$(PATH="$STUBDIR:$PATH" STUB_MODE=noauth bash eval/run.sh 5 sonnet 2>&1)
rc=$?
[ "$rc" -ne 0 ];                                  check "aborts when the CLI is not logged in" $?
grep -q "preflight failed" <<<"$out";         check "says preflight failed, not UNPARSEABLE" $?
grep -q "/login" <<<"$out";                   check "points at /login as the fix" $?
[ ! -e eval/out/control/1.verdict.txt ];          check "spends no trial calls after a failed probe" $?

# --- working CLI --------------------------------------------------------------
out=$(PATH="$STUBDIR:$PATH" STUB_MODE=ok bash eval/run.sh 2 sonnet 2>&1)
rc=$?
[ "$rc" -eq 0 ];                                  check "completes a run against a working CLI" $?
grep -q "preflight ok" <<<"$out";             check "reports preflight ok before running" $?
[ -s eval/out/control/2.report.md ];              check "writes a report per trial" $?
[ -s eval/out/breadcrumb/2.verdict.txt ];         check "writes a verdict per trial" $?

table=$(bash eval/score.sh)
grep -qE '^control +2 +2 +0 +0 ' <<<"$table";      check "score.sh reads the run it just produced" $?

# --- missing CLI --------------------------------------------------------------
EMPTY=$(mktemp -d)
out=$(PATH="$EMPTY:/usr/bin:/bin" bash eval/run.sh 2 sonnet 2>&1)
rc=$?
rm -rf "$EMPTY"
[ "$rc" -ne 0 ];                                  check "aborts when claude is not on PATH" $?
grep -qi "not on PATH" <<<"$out";             check "says the CLI is missing from PATH" $?

printf '%s\n' "-----------------------------------------------------------"
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
