#!/usr/bin/env bash
# Powernode MCP status line for Claude Code
# Displays: [Model] powernode: STATUS | ctx% | $cost

set -euo pipefail

PID_FILE="/tmp/powernode_sse_daemon_${PPID}.pid"
# Per-instance session (keyed by Claude Code PID), fallback to daemon's shared session
INSTANCE_SESSION="/tmp/powernode_mcp_session_${PPID}.txt"
if [[ -f "$INSTANCE_SESSION" && -s "$INSTANCE_SESSION" ]]; then
  SESSION_FILE="$INSTANCE_SESSION"
else
  SESSION_FILE="/tmp/powernode_sse_session.txt"
fi

# Parse session JSON from stdin in one jq call
read -r MODEL CTX COST < <(
  jq -r '[
    (.model.display_name // "Unknown"),
    (.context_window.used_percentage // 0 | floor),
    (.cost.total_cost_usd // 0)
  ] | @tsv' 2>/dev/null || echo "Unknown 0 0"
)

# Determine MCP daemon status
if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE" 2>/dev/null)" 2>/dev/null; then
  if [[ -s "$SESSION_FILE" ]]; then
    STATUS="\033[32mLIVE\033[0m"  # green
  else
    STATUS="\033[33mIDLE\033[0m"  # yellow
  fi
else
  STATUS="\033[31mDOWN\033[0m"    # red
fi

# Context color: green <70%, yellow 70-89%, red 90+%
if (( CTX >= 90 )); then
  CTX_COLOR="\033[31m"   # red
elif (( CTX >= 70 )); then
  CTX_COLOR="\033[33m"   # yellow
else
  CTX_COLOR="\033[32m"   # green
fi

OUTPUT=$(printf "[%s] powernode: %b | %b%d%%\033[0m ctx | $%s" \
  "$MODEL" "$STATUS" "$CTX_COLOR" "$CTX" "$COST")

PLAIN=$(printf "[%s] powernode: %s | %d%% ctx | $%s" "$MODEL" \
  "$(echo -e "$STATUS" | sed 's/\x1b\[[0-9;]*m//g')" "$CTX" "$COST")

# Unread workspace messages (read-state architecture: inbox is read-only,
# seen IDs tracked in a separate file)
INBOX="/tmp/powernode_workspace_inbox_${PPID}.jsonl"
READ_STATE="/tmp/powernode_workspace_read_${PPID}.ids"
UNREAD=0
if [[ -f "$INBOX" ]]; then
  if [[ -f "$READ_STATE" ]]; then
    # Count inbox message IDs not present in read-state file
    TOTAL=$(grep -co '"message_id": *"[^"]*"' "$INBOX" 2>/dev/null || echo 0)
    READ=$(wc -l < "$READ_STATE" 2>/dev/null || echo 0)
    UNREAD=$(( TOTAL > READ ? TOTAL - READ : 0 ))
  else
    # No read-state file — all inbox messages are unread
    UNREAD=$(grep -c '"message_id"' "$INBOX" 2>/dev/null || true)
  fi
fi
if (( UNREAD > 0 )); then
  OUTPUT="${OUTPUT} | \033[33m${UNREAD} unread\033[0m"
  PLAIN="${PLAIN} | ${UNREAD} unread"
fi

# Display in Claude Code statusline
printf '%s' "$OUTPUT"

# Also write to per-instance temp file for tmux status bar (strip ANSI for tmux plain text).
# Uses $PPID (Claude Code's PID) so multiple sessions don't overwrite each other.
TMUX_FILE="/tmp/claude-status-tmux-${PPID}"
printf '%s' "$PLAIN" > "$TMUX_FILE"
