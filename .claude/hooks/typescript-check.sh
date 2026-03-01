#!/bin/bash
# Blocking hook: runs tsc --noEmit after TypeScript file edits
# Exit 2 = blocking (Claude must fix), Exit 0 = pass

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty')

# Only check .ts/.tsx files
[[ "$FILE_PATH" != *.ts && "$FILE_PATH" != *.tsx ]] && exit 0
# Only check core frontend source files (not enterprise submodule)
[[ "$FILE_PATH" != *frontend/src/* ]] && exit 0
[[ "$FILE_PATH" == *enterprise/frontend/* ]] && exit 0
[[ ! -f "$FILE_PATH" ]] && exit 0
# Skip test/spec files — type errors there are less critical
BASENAME=$(basename "$FILE_PATH")
[[ "$BASENAME" == *".test."* || "$BASENAME" == *".spec."* ]] && exit 0

# Find frontend directory — always use the core frontend
FRONTEND_DIR=$(echo "$FILE_PATH" | sed 's|/frontend/src/.*|/frontend|')
[[ ! -d "$FRONTEND_DIR" ]] && exit 0

# Use project-local tsc, not npx (avoids npx resolution failures)
TSC="$FRONTEND_DIR/node_modules/.bin/tsc"
[[ ! -x "$TSC" ]] && exit 0

OUTPUT=$(cd "$FRONTEND_DIR" && "$TSC" --noEmit 2>&1)
EXIT_CODE=$?

if [[ $EXIT_CODE -ne 0 ]]; then
  echo "TypeScript type errors found after editing $FILE_PATH:" >&2
  echo "$OUTPUT" | head -20 >&2
  TOTAL_ERRORS=$(echo "$OUTPUT" | grep -c "^.*([0-9]*,[0-9]*): error TS" || true)
  if [[ "$TOTAL_ERRORS" -gt 20 ]]; then
    echo "... ($TOTAL_ERRORS total errors, showing first 20)" >&2
  fi
  exit 2
fi
exit 0
