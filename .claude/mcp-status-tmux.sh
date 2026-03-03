#!/usr/bin/env bash
# Per-instance MCP/SSE daemon status for tmux status bar.
# Only outputs when Claude Code is running in this pane — otherwise outputs
# nothing, letting tmux fall back to its default status-right content.

# --- Resolve Claude PID for this tmux pane ---
# Accept pane_pid as $1 (passed by tmux's #{pane_pid} expansion in status-right).
CLAUDE_PID=""
PANE_PID="${1:-}"
if [[ -z "$PANE_PID" ]]; then
  # No pane PID provided — cannot resolve instance.
  # Caller should pass #{pane_pid} via tmux status-right format.
  exit 0
fi
for cpid in $(pgrep -P "$PANE_PID" 2>/dev/null); do
  if ps -p "$cpid" -o comm= 2>/dev/null | grep -q '^claude$'; then
    CLAUDE_PID="$cpid"
    break
  fi
done

# No Claude running in this pane — output nothing (tmux shows default)
[[ -z "$CLAUDE_PID" ]] && exit 0

# --- Per-instance daemon status ---
PID_FILE="/tmp/powernode_sse_daemon_${CLAUDE_PID}.pid"
SESSION_FILE="/tmp/powernode_mcp_session_${CLAUDE_PID}.txt"
NAME_FILE="/tmp/powernode_mcp_session_name_${CLAUDE_PID}.txt"

NAME=$(cat "$NAME_FILE" 2>/dev/null)
NAME="${NAME:-MCP}"

if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE" 2>/dev/null)" 2>/dev/null; then
  if [[ -f "$SESSION_FILE" && -s "$SESSION_FILE" ]]; then
    echo "${NAME}: LIVE"
  else
    echo "${NAME}: IDLE"
  fi
else
  echo "${NAME}: DOWN"
fi
