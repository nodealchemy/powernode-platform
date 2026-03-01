#!/usr/bin/env bash
# Powernode AI Execution Monitor - 4-pane tmux layout
# Usage: bash scripts/monitoring/tmux-monitor.sh [session-name]

set -eo pipefail

SESSION_NAME="${1:-powernode-monitor}"

# Check if tmux is installed
if ! command -v tmux &>/dev/null; then
  echo "Error: tmux is not installed. Install with: sudo apt install tmux"
  exit 1
fi

# Kill existing session if it exists
tmux kill-session -t "$SESSION_NAME" 2>/dev/null || true

# Create new session with first pane (backend logs)
tmux new-session -d -s "$SESSION_NAME" -n "monitor" \
  "echo '=== Backend Logs ===' && sudo journalctl --follow --no-tail -u powernode-backend@default --output=short-iso"

# Split horizontally for worker logs (top-right)
tmux split-window -h -t "$SESSION_NAME:monitor" \
  "echo '=== Worker Logs ===' && sudo journalctl --follow --no-tail -u powernode-worker@default --output=short-iso"

# Split bottom-left for execution control
tmux split-window -v -t "$SESSION_NAME:monitor.0" \
  "echo '=== Execution Control ===' && echo 'Use this pane for API commands and rails console.' && echo '' && echo 'Quick commands:' && echo '  # Get auth token:' && echo '  TOKEN=\$(curl -s -X POST http://localhost:3000/api/v1/auth/login -H \"Content-Type: application/json\" -d \"{\\\"email\\\":\\\"admin@powernode.org\\\",\\\"password\\\":\\\"...\\\"}\" | jq -r \".data.token\")' && echo '' && echo '  # Check team executions:' && echo '  curl -s http://localhost:3000/api/v1/ai/agent_teams -H \"Authorization: Bearer \$TOKEN\" | jq' && echo '' && bash"

# Split bottom-right for Claude Code agent
tmux split-window -h -t "$SESSION_NAME:monitor.2" \
  "echo '=== Agent Pane ===' && echo 'Launch Claude Code or other tools here.' && bash"

# Set equal pane sizes
tmux select-layout -t "$SESSION_NAME:monitor" tiled

# Focus on execution control pane
tmux select-pane -t "$SESSION_NAME:monitor.2"

# Attach to session
echo "Attaching to tmux session: $SESSION_NAME"
echo "Detach with: Ctrl-b d"
echo "Kill with: tmux kill-session -t $SESSION_NAME"
tmux attach-session -t "$SESSION_NAME"
