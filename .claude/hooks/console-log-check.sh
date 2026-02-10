#!/bin/bash
# Advisory hook: warns when console.log/debug/info is introduced in frontend TS/TSX files
# Suggests using the centralized logger instead

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty')

[[ "$FILE_PATH" != *.ts && "$FILE_PATH" != *.tsx ]] && exit 0
[[ "$FILE_PATH" != *frontend/src* ]] && exit 0
[[ ! -f "$FILE_PATH" ]] && exit 0

BASENAME=$(basename "$FILE_PATH")
[[ "$BASENAME" == "logger.ts" ]] && exit 0
[[ "$BASENAME" == *".test."* || "$BASENAME" == *".spec."* ]] && exit 0
[[ "$BASENAME" == "CodeSamples.tsx" ]] && exit 0

MATCHES=$(grep -n 'console\.\(log\|debug\|info\)(' "$FILE_PATH" 2>/dev/null | grep -v '^\s*//' | grep -v '^\s*\*')
if [[ -n "$MATCHES" ]]; then
  echo "Advisory: console.log/debug/info found in $FILE_PATH" >&2
  echo "$MATCHES" >&2
  echo "Use: import { logger } from '@/shared/utils/logger'" >&2
fi
exit 0
