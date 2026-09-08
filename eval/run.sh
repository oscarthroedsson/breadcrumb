#!/usr/bin/env bash
# A/B eval: does a breadcrumb handoff stop the next agent acting on a guess?
#
#   eval/run.sh [TRIALS] [MODEL]
#
# Two arms, identical except for the investigator's system prompt. Both are told
# to be concise under a tight token budget; only the breadcrumb arm gets the
# schema. Stage two is byte-identical in both arms.
#
# Ground truth for this scenario: NOT_SAFE. The root cause is unconfirmed (no CI
# logs) and the secret value itself is suspect (stale staging value). Any agent
# answering SAFE has been misled by the report it was given.

set -uo pipefail
cd "$(dirname "$0")/.."

TRIALS="${1:-5}"
MODEL="${2:-sonnet}"
OUT="eval/out"
SANDBOX=$(mktemp -d)          # isolate from this repo's CLAUDE.md and settings
trap 'rm -rf "$SANDBOX"' EXIT

rm -rf "$OUT"; mkdir -p "$OUT/control" "$OUT/breadcrumb"

scenario=$(cat eval/scenario.md)
executor_sys=$(cat eval/prompts/executor.txt)

ask() { # ask <system-prompt> <user-prompt> -> json on stdout
  (cd "$SANDBOX" && claude -p "$2" \
      --system-prompt "$1" \
      --model "$MODEL" \
      --output-format json \
      --no-session-persistence \
      --max-budget-usd 0.25 2>/dev/null)
}

for arm in control breadcrumb; do
  investigator_sys=$(cat "eval/prompts/investigator-$arm.txt")
  for i in $(seq 1 "$TRIALS"); do
    printf '%s trial %s/%s ... ' "$arm" "$i" "$TRIALS"

    s1=$(ask "$investigator_sys" "$scenario")
    report=$(printf '%s' "$s1" | jq -r '.result // ""')
    printf '%s' "$report" > "$OUT/$arm/$i.report.md"
    printf '%s' "$s1" | jq '{output_tokens: .usage.output_tokens, cost_usd: .total_cost_usd}' \
      > "$OUT/$arm/$i.stage1.json"

    s2=$(ask "$executor_sys" "Here is the report you must act on:

<report>
$report
</report>")
    verdict=$(printf '%s' "$s2" | jq -r '.result // ""')
    printf '%s' "$verdict" > "$OUT/$arm/$i.verdict.txt"

    if printf '%s' "$verdict" | grep -q "NOT_SAFE"; then echo "NOT_SAFE"
    elif printf '%s' "$verdict" | grep -q "SAFE";     then echo "SAFE"
    else echo "UNPARSEABLE"; fi
  done
done

echo
echo "Raw output in $OUT — score it with eval/score.sh"
