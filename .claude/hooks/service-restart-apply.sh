#!/bin/bash
# Stop hook — consumes restart marker files and applies service restarts.
# Backend uses reload (SIGUSR2, ~30ms). Worker uses full restart (backgrounded).

BACKEND_MARKER="/tmp/powernode_restart_backend.marker"
WORKER_MARKER="/tmp/powernode_restart_worker.marker"
RESTARTED=()

if [[ -f "$BACKEND_MARKER" ]]; then
  rm -f "$BACKEND_MARKER"
  SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)/scripts/reload-backend.sh"
  if bash "$SCRIPT_DIR" 2>/dev/null; then
    RESTARTED+=("backend")
  else
    echo "⚠ Backend reload failed" >&2
  fi
fi

if [[ -f "$WORKER_MARKER" ]]; then
  rm -f "$WORKER_MARKER"
  # Background the worker restart — it takes ~28s and the hook has a 3s timeout
  sudo systemctl restart powernode-worker@default &
  RESTARTED+=("worker (backgrounded)")
fi

if [[ ${#RESTARTED[@]} -gt 0 ]]; then
  IFS=', '
  echo "⟳ Services restarted: ${RESTARTED[*]}" >&2
fi

exit 0
