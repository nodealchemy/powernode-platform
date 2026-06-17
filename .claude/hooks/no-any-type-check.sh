#!/bin/bash
# Advisory: warns on TypeScript `any` (: any / as any) in frontend source.
# tsc permits `any`, so this is the only mechanical nudge toward precise types.

INPUT=$(cat)
command -v jq >/dev/null 2>&1 || exit 0
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty')
[[ "$FILE_PATH" != *.ts && "$FILE_PATH" != *.tsx ]] && exit 0
[[ "$FILE_PATH" == *.d.ts ]] && exit 0
[[ "$FILE_PATH" != *frontend/src* ]] && exit 0
[[ ! -f "$FILE_PATH" ]] && exit 0

BASENAME=$(basename "$FILE_PATH")
[[ "$BASENAME" == *".test."* || "$BASENAME" == *".spec."* ]] && exit 0

M=$(grep -nE ':[[:space:]]*any\b|\bas[[:space:]]+any\b' "$FILE_PATH" 2>/dev/null | grep -v '^[[:space:]]*//' | grep -v '^[[:space:]]*\*')
if [[ -n "$M" ]]; then
  echo "Advisory: 'any' type in $FILE_PATH — prefer a precise type (No \`any\`)." >&2
  echo "$M" >&2
fi
exit 0
