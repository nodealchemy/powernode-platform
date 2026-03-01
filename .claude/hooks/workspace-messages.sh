#!/usr/bin/env bash
# UserPromptSubmit hook — reads unread workspace messages from the SSE daemon's
# inbox and outputs them as context for Claude Code.
#
# Timeout: 3s (runs on every prompt, must be fast)
# Output: stdout text gets injected into Claude's context
# No output = no context injected (clean no-op when no messages)

set -eo pipefail

# Consume stdin immediately — UserPromptSubmit hooks receive the prompt JSON
# on stdin. If not consumed, child processes (python3, grep) can inadvertently
# read bytes from it, corrupting the user's prompt.
HOOK_INPUT=$(cat)

INBOX_FILE="/tmp/powernode_workspace_inbox.jsonl"
PID_FILE="/tmp/powernode_sse_daemon.pid"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# --- Daemon health check ---
daemon_running() {
  [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null
}

# --- Main ---

# Check if inbox exists and has unread messages
if [[ ! -f "$INBOX_FILE" ]]; then
  # No inbox file — check if daemon is running
  if ! daemon_running; then
    # Only warn if both are missing (first run or daemon never started)
    # Don't spam on every prompt — check if daemon script exists
    if [[ -f "$SCRIPT_DIR/workspace-sse-daemon.sh" ]]; then
      echo "<workspace-status>"
      echo "Workspace SSE daemon is not running. Start with:"
      echo "  .claude/hooks/workspace-sse-daemon.sh start"
      echo "</workspace-status>"
    fi
  fi
  exit 0
fi

# Count unread messages efficiently
# grep -c exits 1 on zero matches, which pipefail treats as error.
# Suppress with true to get clean "0".
unread_count=$(grep -c '"read": false' "$INBOX_FILE" 2>/dev/null || true)
unread_count="${unread_count:-0}"

if [[ "$unread_count" -eq 0 ]]; then
  # No unread messages — check daemon health silently
  if ! daemon_running; then
    echo "<workspace-status>"
    echo "Workspace SSE daemon is not running. Messages may be missed."
    echo "  Start: .claude/hooks/workspace-sse-daemon.sh start"
    echo "</workspace-status>"
  fi
  exit 0
fi

# --- Format unread messages for Claude ---
echo "<workspace-messages>"
echo "You have $unread_count unread workspace message(s):"
echo ""

# Parse and format each unread event
# Using python3 for reliable JSON handling (available on all modern Linux)
python3 -c "
import json, sys

inbox_path = '$INBOX_FILE'
events = []
updated_lines = []

with open(inbox_path, 'r') as f:
    for line in f:
        line = line.strip()
        if not line:
            updated_lines.append('')
            continue
        try:
            evt = json.loads(line)
        except json.JSONDecodeError:
            updated_lines.append(line)
            continue

        if not evt.get('read', True):
            events.append(evt)
            # Mark as read
            evt['read'] = True

        updated_lines.append(json.dumps(evt))

# Collect unique conversation IDs for the reply instruction
conv_ids = set()

# Output formatted messages
for evt in events:
    ts = evt.get('ts', '?')
    time_part = ts.split('T')[1][:8] if 'T' in ts else ts
    event_type = evt.get('event', 'message')
    sender = evt.get('sender', 'Unknown')
    content = evt.get('content', '')
    msg_id = evt.get('message_id', '')
    conv_id = evt.get('conversation_id', '')
    workspace = evt.get('workspace', '')

    if conv_id:
        conv_ids.add(conv_id)

    label = '@mentioned you' if event_type == 'mention' else 'said'
    ws_label = f' in {workspace}' if workspace else ''

    print(f'[{time_part}] {sender} {label}{ws_label}:')
    print(f'  \"{content}\"')
    if msg_id:
        details = f'message_id: {msg_id}'
        if conv_id:
            details += f', conversation: {conv_id}'
        print(f'  ({details})')
    print()

# Output reply instructions with conversation IDs
if conv_ids:
    print('IMPORTANT: If these messages require a response, reply using the MCP tool:')
    print('  Tool: platform.send_message')
    print('  Parameters: { \"action\": \"send_message\", \"conversation_id\": \"<id>\", \"message\": \"<your reply>\" }')
    for cid in sorted(conv_ids):
        print(f'  Active conversation: {cid}')

# Write back with read=true
with open(inbox_path, 'w') as f:
    for line in updated_lines:
        f.write(line + '\n')
" 2>/dev/null

echo "</workspace-messages>"
