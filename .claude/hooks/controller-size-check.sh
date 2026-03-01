#!/bin/bash
# Advisory hook: warns when a controller file exceeds 300 lines
# Suggests extraction to concerns, service objects, or serializers

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty')

[[ "$FILE_PATH" != *_controller.rb ]] && exit 0
[[ ! -f "$FILE_PATH" ]] && exit 0

LINE_COUNT=$(wc -l < "$FILE_PATH")
if [[ "$LINE_COUNT" -gt 300 ]]; then
  echo "Advisory: $FILE_PATH is $LINE_COUNT lines (target: <300)" >&2
  echo "Consider extracting to concerns, service objects, or serializers" >&2
  if [[ "$LINE_COUNT" -gt 500 ]]; then
    echo "WARNING: File exceeds 500-line modular design limit" >&2
  fi
fi
exit 0
