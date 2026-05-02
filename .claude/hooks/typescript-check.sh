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

# Find the frontend dir for the edited file (platform OR extension)
FRONTEND_DIR=$(echo "$FILE_PATH" | sed 's|/frontend/src/.*|/frontend|')
[[ ! -d "$FRONTEND_DIR" ]] && exit 0

# Pick the right tsconfig:
# - Platform frontend has tsconfig.json (default)
# - Extension frontends only have tsconfig.check.json — without picking
#   it explicitly, tsc with no config prints its help and exits non-zero,
#   which the hook would surface as a confusing "type errors found".
if [[ -f "$FRONTEND_DIR/tsconfig.json" ]]; then
  TSC_ARGS=(--noEmit)
elif [[ -f "$FRONTEND_DIR/tsconfig.check.json" ]]; then
  TSC_ARGS=(--noEmit -p tsconfig.check.json)
else
  exit 0
fi

# Use the platform's tsc binary. Extension frontends' node_modules is a
# symlink to the platform's node_modules (see scripts/validate.sh).
TSC="$FRONTEND_DIR/node_modules/.bin/tsc"
[[ ! -x "$TSC" ]] && exit 0

OUTPUT=$(cd "$FRONTEND_DIR" && "$TSC" "${TSC_ARGS[@]}" 2>&1)
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
