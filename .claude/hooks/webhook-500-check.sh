#!/bin/bash
# Advisory: inbound webhook receivers MUST return 200/202 on processing errors,
# never 500 (a 500 causes provider retry storms). Scoped to webhook controllers.

INPUT=$(cat)
command -v jq >/dev/null 2>&1 || exit 0
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty')
[[ "$FILE_PATH" != *.rb ]] && exit 0
[[ ! -f "$FILE_PATH" ]] && exit 0

case "$FILE_PATH" in
  *webhook*controller*.rb|*webhooks_controller.rb|*webhook_controller.rb|*/webhooks/*.rb) ;;
  *) exit 0 ;;
esac

M=$(grep -nE 'status:[[:space:]]*(:internal_server_error|500)|head[[:space:]]*\(?[[:space:]]*(:internal_server_error|500)' "$FILE_PATH" 2>/dev/null)
if [[ -n "$M" ]]; then
  echo "Advisory: webhook receiver $FILE_PATH returns 500 — inbound webhooks MUST return 200/202 on processing errors (avoid provider retry storms)." >&2
  echo "$M" >&2
fi
exit 0
