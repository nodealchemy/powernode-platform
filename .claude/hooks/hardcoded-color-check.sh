#!/bin/bash
# Advisory: warns on hardcoded Tailwind colors in frontend (use theme-* classes).
# Regex mirrors scripts/fix-hardcoded-colors.sh; text-white is allowed.

INPUT=$(cat)
command -v jq >/dev/null 2>&1 || exit 0
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty')
[[ "$FILE_PATH" != *.ts && "$FILE_PATH" != *.tsx ]] && exit 0
[[ "$FILE_PATH" != *frontend/src* ]] && exit 0
[[ ! -f "$FILE_PATH" ]] && exit 0

BASENAME=$(basename "$FILE_PATH")
[[ "$BASENAME" == *".test."* || "$BASENAME" == *".spec."* ]] && exit 0

M=$(grep -nE '(text|bg|border)-(red|green|blue|yellow|orange|purple|gray|black)-[0-9]' "$FILE_PATH" 2>/dev/null | grep -v 'text-white')
if [[ -n "$M" ]]; then
  echo "Advisory: hardcoded Tailwind colors in $FILE_PATH — use theme classes (bg-theme-*, text-theme-*)." >&2
  echo "$M" >&2
  echo "Fixer: ./scripts/fix-hardcoded-colors.sh" >&2
fi
exit 0
