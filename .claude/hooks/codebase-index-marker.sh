#!/bin/bash
# PostToolUse hook (Edit|Write) — batches changed source file paths for re-indexing.
# Each Claude session uses its own batch file (keyed by SESSION_ID).
# Consumed by codebase-index-apply.sh (Stop hook).

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

[[ -z "$FILE_PATH" ]] && exit 0

# Only index source files
case "$FILE_PATH" in
  *.rb|*.ts|*.tsx|*.js|*.jsx|*.py) ;;
  *) exit 0 ;;
esac

SESSION_ID="${CLAUDE_SESSION_ID:-$$}"
BATCH_FILE="/tmp/powernode_reindex_${SESSION_ID}.txt"

# Dedup within this session's batch
if [[ -f "$BATCH_FILE" ]] && grep -qxF "$FILE_PATH" "$BATCH_FILE" 2>/dev/null; then
  exit 0
fi

echo "$FILE_PATH" >> "$BATCH_FILE"
exit 0
