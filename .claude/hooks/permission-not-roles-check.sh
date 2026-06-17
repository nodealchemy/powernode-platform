#!/bin/bash
# Advisory: access control must use PERMISSIONS, never roles.
# Frontend: currentUser?.permissions?.includes('area.action').
# Backend: current_user.has_permission?('area.action') (not permissions.include?).

INPUT=$(cat)
command -v jq >/dev/null 2>&1 || exit 0
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty')
[[ -z "$FILE_PATH" ]] && exit 0
[[ ! -f "$FILE_PATH" ]] && exit 0

BASENAME=$(basename "$FILE_PATH")
[[ "$BASENAME" == *".test."* || "$BASENAME" == *".spec."* || "$BASENAME" == *"_spec.rb" ]] && exit 0

case "$FILE_PATH" in
  *.ts|*.tsx)
    [[ "$FILE_PATH" != *frontend/src* ]] && exit 0
    M=$(grep -nE "roles\??\.includes\(|\.role\s*===|\brole\s*===" "$FILE_PATH" 2>/dev/null | grep -v '^[[:space:]]*//')
    if [[ -n "$M" ]]; then
      echo "Advisory: role-based access control in $FILE_PATH — use PERMISSIONS, not roles." >&2
      echo "$M" >&2
      echo "Use: currentUser?.permissions?.includes('area.action')" >&2
    fi
    ;;
  *.rb)
    M=$(grep -nE "permissions\.include\?\(" "$FILE_PATH" 2>/dev/null)
    if [[ -n "$M" ]]; then
      echo "Advisory: permissions.include?() in $FILE_PATH returns objects — use has_permission?." >&2
      echo "$M" >&2
      echo "Use: current_user.has_permission?('area.action')" >&2
    fi
    ;;
esac
exit 0
