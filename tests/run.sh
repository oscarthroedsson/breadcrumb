#!/usr/bin/env bash
# Runs every breadcrumb test suite. Exit code is non-zero if any suite fails.
set -uo pipefail
cd "$(dirname "$0")/.."

rc=0
for suite in tests/run-validator-tests.sh tests/run-installer-tests.sh; do
  echo
  echo "=== $(basename "$suite") ==="
  bash "$suite" || rc=1
done
echo
[ "$rc" -eq 0 ] && echo "ALL SUITES PASSED" || echo "SOME SUITES FAILED"
exit "$rc"
