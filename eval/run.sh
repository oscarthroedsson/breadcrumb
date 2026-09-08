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

if ! command -v claude >/dev/null 2>&1; then
  echo "eval/run.sh: the 'claude' CLI is not on PATH." >&2
  echo "  Install Claude Code, or add its bin directory to PATH." >&2
  exit 1
fi

TRIALS="${1:-5}"
MODEL="${2:-sonnet}"
OUT="eval/out"
ERRLOG="$PWD/$OUT/errors.log"
SANDBOX=$(mktemp -d)          # isolate from this repo's CLAUDE.md and settings
trap 'rm -rf "$SANDBOX"' EXIT

rm -rf "$OUT"; mkdir -p "$OUT/control" "$OUT/breadcrumb"
: > "$OUT/errors.log"

scenario=$(cat eval/scenario.md)
executor_sys=$(cat eval/prompts/executor.txt)

ask() { # ask <system-prompt> <user-prompt> -> result text on stdout
  local json
  json=$( (cd "$SANDBOX" && claude -p "$2" \
      --system-prompt "$1" \
      --model "$MODEL" \
      --output-format json \
      --no-session-persistence \
      --max-budget-usd 0.25 2>>"$ERRLOG") )
  printf '%s' "$json"
}

# One cheap probe before spending twenty calls. An unauthenticated CLI used to
# produce twenty UNPARSEABLE lines and no explanation; now it stops here.
preflight() {
  local json result
  json=$(ask "Reply with exactly PONG and nothing else." "ping")
  result=$(printf '%s' "$json" | jq -r '.result // ""' 2>/dev/null)

  if printf '%s' "$result" | grep -q "PONG"; then
    return 0
  fi

  echo >&2
  echo "preflight failed — not spending the remaining calls." >&2
  echo "  claude CLI said: ${result:-<empty response>}" >&2
  case "$result" in
    *"Invalid API key"*|*"/login"*|*"login"*)
      echo >&2
      echo "  The CLI is installed but not logged in. It has its own auth," >&2
      echo "  separate from the desktop app. Fix it once:" >&2
      echo >&2
      echo "      claude          # then run /login and follow the prompts" >&2
      echo >&2
      echo "  Then re-run this script." >&2 ;;
    *)
      echo "  See $ERRLOG for the CLI's stderr." >&2 ;;
  esac
  exit 1
}

preflight
echo "preflight ok — running $((TRIALS * 4)) calls"
echo

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
