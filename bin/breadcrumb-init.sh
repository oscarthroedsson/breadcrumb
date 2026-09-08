#!/usr/bin/env bash
# breadcrumb-init — install the handoff schema and validator into a project.
#
#   breadcrumb-init.sh [TARGET_DIR] [--force]
#
# Idempotent. Never clobbers an existing .claude/HANDOFF.md unless --force is
# given, because that file is meant to be edited per project.

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TARGET="${PWD}"
FORCE=0

for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
    -*)      echo "breadcrumb-init: unknown flag: $arg" >&2; exit 1 ;;
    *)       TARGET=$(cd "$arg" 2>/dev/null && pwd) || { echo "breadcrumb-init: no such directory: $arg" >&2; exit 1; } ;;
  esac
done

CLAUDE_DIR="$TARGET/.claude"
mkdir -p "$CLAUDE_DIR/hooks"

if [ -f "$CLAUDE_DIR/HANDOFF.md" ] && [ "$FORCE" -eq 0 ]; then
  echo "kept    .claude/HANDOFF.md (already present, use --force to replace)"
else
  cp "$REPO_ROOT/templates/HANDOFF.md" "$CLAUDE_DIR/HANDOFF.md"
  echo "wrote   .claude/HANDOFF.md"
fi

cp "$REPO_ROOT/templates/hooks/validate-handoff.sh" "$CLAUDE_DIR/hooks/validate-handoff.sh"
chmod +x "$CLAUDE_DIR/hooks/validate-handoff.sh"
echo "wrote   .claude/hooks/validate-handoff.sh"

if ! command -v jq >/dev/null 2>&1; then
  echo "warn    jq not found — the validator will fail open until it is installed"
fi

echo
echo "Next: wire an agent to it by adding this to its frontmatter in .claude/agents/"
echo
cat <<'FRONTMATTER'
maxTurns: 25
hooks:
  SubagentStop:
    - hooks:
        - type: command
          command: ${CLAUDE_PROJECT_DIR}/.claude/hooks/validate-handoff.sh
FRONTMATTER
