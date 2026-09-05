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
  # Background the worker restart — it takes ~28s and the hook has a 3s timeout.
  # User-scope unit (installer shape) takes precedence; then the installer's
  # system-scope default unit; then, on a module-composed node (this cell),
  # the generated powernode-<moduleID>-sidekiq.service — DISCOVERED, never
  # guessed, since `systemctl restart` on a name that doesn't exist fails
  # silently and this branch was backgrounded, so a guess here reads as a
  # successful restart that never happened.
  if systemctl --user cat powernode-worker@default.service &>/dev/null; then
    systemctl --user restart powernode-worker@default &
    RESTARTED+=("worker (backgrounded)")
  elif systemctl cat powernode-worker@default.service &>/dev/null; then
    sudo systemctl restart powernode-worker@default &
    RESTARTED+=("worker (backgrounded)")
  else
    WORKER_UNIT="$(systemctl list-units 'powernode-*-sidekiq.service' --no-pager --no-legend --plain 2>/dev/null | awk '{print $1}' | head -1)"
    if [[ -n "$WORKER_UNIT" ]]; then
      sudo systemctl restart "$WORKER_UNIT" &
      RESTARTED+=("worker (backgrounded)")
    else
      echo "⚠ No powernode-worker@default or powernode-*-sidekiq.service unit found — skipping worker restart" >&2
    fi
  fi
fi

if [[ ${#RESTARTED[@]} -gt 0 ]]; then
  IFS=', '
  echo "⟳ Services restarted: ${RESTARTED[*]}" >&2
fi

exit 0
