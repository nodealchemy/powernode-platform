#!/usr/bin/env bash
# Standalone MCP/SSE daemon + Claude Code status for tmux status bar
# Handles multiple Claude Code sessions without interference

PID_FILE="/tmp/powernode_sse_daemon.pid"
SESSION_FILE="/tmp/powernode_sse_session.txt"
SESSION_NAME_FILE="/tmp/powernode_sse_session_name.txt"
STALE_THRESHOLD=15  # seconds — statusline.sh updates every ~5s

# --- MCP daemon status ---
if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE" 2>/dev/null)" 2>/dev/null; then
  NAME=$(cat "$SESSION_NAME_FILE" 2>/dev/null)
  NAME="${NAME:-MCP}"
  if [[ -s "$SESSION_FILE" ]]; then
    MCP_STATUS="${NAME}: LIVE"
  else
    MCP_STATUS="${NAME}: IDLE"
  fi
else
  MCP_STATUS="MCP: DOWN"
fi

# --- Claude Code instance status (per-instance files) ---
# TUI sessions write to /tmp/claude-status-tmux-<PID> via statusline.sh.
# Headless/teammate sessions don't have a TUI status line.
CLAUDE_STATUS=""

# Try to find the Claude process in the active tmux pane
PANE_PID=$(tmux display-message -p '#{pane_pid}' 2>/dev/null)
if [[ -n "$PANE_PID" ]]; then
  for cpid in $(pgrep -P "$PANE_PID" 2>/dev/null); do
    # Check for per-instance status file (TUI sessions)
    if [[ -f "/tmp/claude-status-tmux-${cpid}" ]]; then
      CLAUDE_STATUS=$(cat "/tmp/claude-status-tmux-${cpid}" 2>/dev/null)
      break
    fi
    # Detect running claude process without status file (headless/teammate)
    if [[ -z "$CLAUDE_STATUS" ]] && pgrep -x claude -P "$PANE_PID" >/dev/null 2>&1; then
      CLAUDE_STATUS="Claude: active"
      break
    fi
  done
fi

# Fallback: most recently modified status file with a live process
if [[ -z "$CLAUDE_STATUS" ]]; then
  NOW=$(date +%s)
  for f in $(ls -t /tmp/claude-status-tmux-* 2>/dev/null); do
    INST_PID="${f##*-}"
    if kill -0 "$INST_PID" 2>/dev/null; then
      AGE=$(( NOW - $(stat -c%Y "$f" 2>/dev/null || echo 0) ))
      if (( AGE < STALE_THRESHOLD )); then
        CLAUDE_STATUS=$(cat "$f" 2>/dev/null)
        break
      fi
    else
      rm -f "$f"  # Clean up stale files from dead processes
    fi
  done
fi

CLAUDE_STATUS="${CLAUDE_STATUS:-Claude: offline}"

echo "${MCP_STATUS} | ${CLAUDE_STATUS}"
