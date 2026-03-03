#!/usr/bin/env bash
# SessionStart hook: auto-starts the workspace SSE daemon when Claude Code launches.
# Backgrounds the bootstrap to stay within the 3s hook timeout. Uses a one-shot
# marker to prevent re-entry when /clear re-fires SessionStart.
#
# Creates its own MCP session via initialize if none are discoverable (Claude Code
# lazily connects to MCP — no session exists until the first tool call). The server
# allows multiple concurrent sessions per OAuth app, so this is safe.
#
# PostToolUse hook (mcp-sse-autostart.sh) remains as fallback.

INSTANCE_ID="${PPID}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PPID_PARENT=$(ps -p "$PPID" -o ppid= 2>/dev/null | tr -d ' ')

PID_FILE="/tmp/powernode_sse_daemon_${INSTANCE_ID}.pid"
MARKER_FILE="/tmp/powernode_autoconnect_${INSTANCE_ID}.attempted"

# Fast path: daemon already running for this PID or a sibling
if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE" 2>/dev/null)" 2>/dev/null; then
  exit 0
fi
if [[ -n "$PPID_PARENT" && "$PPID_PARENT" != "1" ]]; then
  for spid in $(pgrep -P "$PPID_PARENT" -x claude 2>/dev/null); do
    spf="/tmp/powernode_sse_daemon_${spid}.pid"
    if [[ -f "$spf" ]] && kill -0 "$(cat "$spf" 2>/dev/null)" 2>/dev/null; then
      exit 0
    fi
  done
fi

# One-shot guard: /clear re-fires SessionStart
if [[ -f "$MARKER_FILE" ]]; then
  exit 0
fi

# Clean stale markers from dead PIDs
for f in /tmp/powernode_autoconnect_*.attempted; do
  [[ -f "$f" ]] || continue
  stale_pid=$(basename "$f" | sed 's/powernode_autoconnect_//;s/\.attempted//')
  if [[ "$stale_pid" =~ ^[0-9]+$ ]] && ! kill -0 "$stale_pid" 2>/dev/null; then
    rm -f "$f"
  fi
done

touch "$MARKER_FILE"

# Background subshell: resolve PID, create/discover session, start daemon.
(
  LOG_FILE="/tmp/powernode_sse_daemon_${INSTANCE_ID}.log"
  _log() { echo "[$(date -Iseconds)] Autoconnect: $*" >> "$LOG_FILE"; }

  _update_instance() {
    local new_pid="$1" method="$2"
    _log "Resolved instance via ${method}: $new_pid (was $INSTANCE_ID)"
    INSTANCE_ID="$new_pid"
    export MCP_INSTANCE_ID="$INSTANCE_ID"
    LOG_FILE="/tmp/powernode_sse_daemon_${INSTANCE_ID}.log"
    touch "/tmp/powernode_autoconnect_${INSTANCE_ID}.attempted"
  }

  _resolve_instance() {
    # Original PPID still alive — keep it
    if kill -0 "$INSTANCE_ID" 2>/dev/null; then
      return 0
    fi

    # Poll for a claude child of the ancestor (the session process PostToolUse uses)
    if [[ -n "$PPID_PARENT" && "$PPID_PARENT" != "1" ]]; then
      local polls=0
      while (( polls < 20 )); do
        local real_pid
        real_pid=$(pgrep -P "$PPID_PARENT" -x claude 2>/dev/null | head -1) || true
        if [[ -n "$real_pid" ]]; then
          _update_instance "$real_pid" "sibling-poll(${polls})"
          return 0
        fi
        sleep 0.5
        (( polls++ )) || true
      done

      # No child — ancestor itself may be the session process
      local ancestor_comm
      ancestor_comm=$(ps -p "$PPID_PARENT" -o comm= 2>/dev/null) || true
      if [[ "$ancestor_comm" == "claude" ]] && kill -0 "$PPID_PARENT" 2>/dev/null; then
        _update_instance "$PPID_PARENT" "ancestor-fallback"
        return 0
      fi
    fi

    # Last resort: find inner claude (parent is also claude) without a daemon
    local pids pid
    pids=$(pgrep -u "$(id -u)" -x claude 2>/dev/null) || true
    for pid in $pids; do
      local ppid_of parent_comm
      ppid_of=$(ps -p "$pid" -o ppid= 2>/dev/null | tr -d ' ') || true
      parent_comm=$(ps -p "$ppid_of" -o comm= 2>/dev/null) || true
      if [[ "$parent_comm" == "claude" ]]; then
        local opf="/tmp/powernode_sse_daemon_${pid}.pid"
        if [[ -f "$opf" ]] && kill -0 "$(cat "$opf" 2>/dev/null)" 2>/dev/null; then
          continue  # already has a daemon
        fi
        _update_instance "$pid" "inner-claude-scan"
        return 0
      fi
    done

    _log "Could not resolve Claude PID (PPID $INSTANCE_ID dead, ancestor $PPID_PARENT)"
    return 1
  }

  export MCP_INSTANCE_ID="$INSTANCE_ID"
  source "${SCRIPT_DIR}/mcp-helper.sh"
  set +eo pipefail

  _log "Started (PPID=$INSTANCE_ID, ancestor=$PPID_PARENT)"

  sleep 3

  # Resolve the real Claude PID
  if ! _resolve_instance; then
    _log "ABORTED — cannot determine session PID"
    exit 1
  fi

  # Re-source helper with corrected INSTANCE_ID
  source "${SCRIPT_DIR}/mcp-helper.sh"
  set +eo pipefail

  _log "Instance: $INSTANCE_ID"

  # Check if daemon already started by PostToolUse during our sleep
  pf="/tmp/powernode_sse_daemon_${INSTANCE_ID}.pid"
  if [[ -f "$pf" ]] && kill -0 "$(cat "$pf" 2>/dev/null)" 2>/dev/null; then
    _log "Daemon already running — exiting"
    exit 0
  fi

  # Session discovery/creation + daemon start (3 attempts, 5s apart)
  for attempt in 1 2 3; do
    _log "Attempt ${attempt}: session bootstrap..."
    if mcp_ensure_session >/dev/null 2>&1; then
      _log "SUCCESS on attempt ${attempt} — daemon started for $INSTANCE_ID"
      exit 0
    fi
    _log "Attempt ${attempt} failed"

    # Check if PostToolUse started the daemon while we waited
    if [[ -f "$pf" ]] && kill -0 "$(cat "$pf" 2>/dev/null)" 2>/dev/null; then
      _log "Daemon started by PostToolUse — exiting"
      exit 0
    fi

    sleep 5
  done

  _log "Session not yet available — starting daemon for background discovery"
  mcp_ensure_daemon 2>/dev/null || _log "WARN: daemon start failed"
) >/dev/null 2>&1 &
disown 2>/dev/null || true

exit 0
