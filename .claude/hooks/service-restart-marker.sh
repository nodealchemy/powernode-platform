#!/bin/bash
# PostToolUse hook (Edit|Write) — marks services for restart based on edited file paths.
# Marker files are consumed by the Stop hook (service-restart-apply.sh).

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

[[ -z "$FILE_PATH" ]] && exit 0

BACKEND_MARKER="/tmp/powernode_restart_backend.marker"
WORKER_MARKER="/tmp/powernode_restart_worker.marker"

# Backend: server/**/*.rb or extensions/*/server/**/*.rb
if [[ "$FILE_PATH" == */server/*.rb ]] || [[ "$FILE_PATH" == */server/**/*.rb ]]; then
  if [[ ! -f "$BACKEND_MARKER" ]]; then
    touch "$BACKEND_MARKER"
    echo "⟳ Backend reload pending (will apply at end of response)" >&2
  fi
fi

# Worker: worker/**/*.rb
if [[ "$FILE_PATH" == */worker/*.rb ]] || [[ "$FILE_PATH" == */worker/**/*.rb ]]; then
  if [[ ! -f "$WORKER_MARKER" ]]; then
    touch "$WORKER_MARKER"
    echo "⟳ Worker restart pending (will apply at end of response)" >&2
  fi
fi

exit 0
