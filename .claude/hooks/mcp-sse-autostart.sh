#!/usr/bin/env bash
# PostToolUse hook: auto-starts the workspace SSE daemon on first Powernode MCP tool call.
# Triggered by any mcp__powernode__* tool use. Idempotent — exits immediately if daemon is live.
#
# Uses flock to prevent concurrent bootstrap when multiple MCP tools fire in quick
# succession. The lock is held by the backgrounded subshell until bootstrap completes,
# so subsequent hook invocations exit instantly instead of spawning duplicate daemons.

INSTANCE_ID="${PPID}"
PID_FILE="/tmp/powernode_sse_daemon_${INSTANCE_ID}.pid"
LOCK_FILE="/tmp/powernode_sse_daemon_${INSTANCE_ID}.lock"

# Fast path: daemon already running
if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE" 2>/dev/null)" 2>/dev/null; then
  exit 0
fi

# Acquire non-blocking lock — if another hook invocation is already bootstrapping, exit.
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  exit 0
fi

# Double-check after acquiring lock (daemon may have started between fast-path and lock)
if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE" 2>/dev/null)" 2>/dev/null; then
  exec 9>&-
  exit 0
fi

# Bootstrap session + daemon in background to avoid blocking the hook.
# The subshell inherits fd 9, keeping the flock held until bootstrap completes.
# This prevents any concurrent hook invocation from entering the critical section.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
(
  export MCP_INSTANCE_ID="$INSTANCE_ID"
  source "${SCRIPT_DIR}/mcp-helper.sh"
  mcp_ensure_session >/dev/null 2>&1
  # fd 9 (flock) is released when this subshell exits
) &
disown 2>/dev/null || true

# Close our copy of the lock fd — the backgrounded subshell still holds it
# via inherited file descriptor, so the lock remains active.
exec 9>&-

exit 0
