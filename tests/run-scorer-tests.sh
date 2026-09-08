#!/usr/bin/env bash
# Proves eval/score.sh tallies correctly, without spending any API calls.
# Fabricates an eval output directory with known verdicts and checks the table.

set -uo pipefail
cd "$(dirname "$0")/.."

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0

check() {
  if [ "$2" -eq 0 ]; then printf '%-52s %s\n' "$1" "pass"; pass=$((pass+1))
  else                    printf '%-52s %s\n' "$1" "FAIL"; fail=$((fail+1)); fi
}

mkdir -p "$TMP/control" "$TMP/breadcrumb"

# control: 1 correct, 2 misled. breadcrumb: 3 correct.
printf 'VERDICT: NOT_SAFE\n' > "$TMP/control/1.verdict.txt"
printf 'VERDICT: SAFE\n'     > "$TMP/control/2.verdict.txt"
printf 'VERDICT: SAFE\n'     > "$TMP/control/3.verdict.txt"
for i in 1 2 3; do printf 'VERDICT: NOT_SAFE\n' > "$TMP/breadcrumb/$i.verdict.txt"; done

for i in 1 2 3; do
  echo '{"output_tokens":100,"cost_usd":0.001}' > "$TMP/control/$i.stage1.json"
  echo '{"output_tokens":160,"cost_usd":0.001}' > "$TMP/breadcrumb/$i.stage1.json"
done

table=$(bash eval/score.sh "$TMP")

echo "$table" | grep -qE '^control +3 +1 +2 +0 +100$';    check "control row: 3 trials, 1 correct, 2 misled, 100 tok" $?
echo "$table" | grep -qE '^breadcrumb +3 +3 +0 +0 +160$'; check "breadcrumb row: 3 trials, 3 correct, 160 tok" $?

# NOT_SAFE must never be counted as SAFE by a careless substring match.
rm -f "$TMP"/control/*.verdict.txt
printf 'VERDICT: NOT_SAFE\n' > "$TMP/control/1.verdict.txt"
table=$(bash eval/score.sh "$TMP")
echo "$table" | grep -qE '^control +1 +1 +0 '
check "NOT_SAFE is not miscounted as SAFE" $?

# An empty or garbled verdict counts as unparseable, never as a pass.
printf 'I could not decide.\n' > "$TMP/control/2.verdict.txt"
table=$(bash eval/score.sh "$TMP")
echo "$table" | grep -qE '^control +2 +1 +0 +1 '
check "a garbled verdict counts as unparseable" $?

bash eval/score.sh "$TMP/nope" >/dev/null 2>&1
[ $? -ne 0 ]; check "errors on a missing output directory" $?

printf '%s\n' "-----------------------------------------------------------"
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
