#!/bin/bash
# Advisory: heuristic N+1 — iterating a bare .all (use .includes(:assoc)).
# Conservative: flags only the clear .all.each / .all.map inline antipattern.

INPUT=$(cat)
command -v jq >/dev/null 2>&1 || exit 0
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty')
[[ "$FILE_PATH" != *.rb ]] && exit 0
[[ ! -f "$FILE_PATH" ]] && exit 0
case "$FILE_PATH" in
  *_spec.rb) exit 0 ;;
esac

M=$(grep -nE '\.all\.(each|map)\b' "$FILE_PATH" 2>/dev/null)
if [[ -n "$M" ]]; then
  echo "Advisory: possible N+1 in $FILE_PATH — iterating a bare .all. Use .includes(:assoc) when the block touches relations." >&2
  echo "$M" >&2
fi
exit 0
