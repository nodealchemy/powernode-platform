#!/usr/bin/env bash
# Shared inbox formatter — reads unread workspace messages from the JSONL inbox
# and outputs them as <workspace-messages> context for Claude Code.
#
# Sourced by both:
#   - workspace-messages.sh (UserPromptSubmit hook)
#   - workspace-stop-check.sh (Stop hook)
#
# Expects: CLAUDE_PID set by the caller (identifies the inbox file)
# Output:  <workspace-messages> XML on stdout if unread messages exist
#
# Design: READ-ONLY inbox. Read-state tracked in a separate file to avoid
# race conditions with the SSE daemon writing to the inbox concurrently.

# Resolve the actual Claude Code PID by walking up the process tree.
# When Claude Code spawns hooks, PPID may point to an intermediate shell,
# not the Claude Code process itself. The daemon keys its inbox by the
# Claude Code PID, so we must find it reliably.
_resolve_claude_pid() {
  local pid="$1"
  # Walk up the process tree looking for a 'claude' process
  while [[ -n "$pid" && "$pid" != "1" && "$pid" != "0" ]]; do
    local comm
    comm=$(ps -p "$pid" -o comm= 2>/dev/null) || break
    if [[ "$comm" == "claude" ]]; then
      echo "$pid"
      return 0
    fi
    pid=$(ps -p "$pid" -o ppid= 2>/dev/null | tr -d ' ') || break
  done
  return 1
}

# Try direct PID first, then walk process tree, then scan for active daemon
RESOLVED_PID=""
if [[ -f "/tmp/powernode_workspace_inbox_${CLAUDE_PID}.jsonl" ]]; then
  RESOLVED_PID="$CLAUDE_PID"
elif RESOLVED_PID=$(_resolve_claude_pid "$CLAUDE_PID"); then
  : # found via process tree walk
else
  # Fallback: find inbox from the active daemon's PID file
  for pf in /tmp/powernode_sse_daemon_*.pid; do
    [[ -f "$pf" ]] || continue
    dpid=$(cat "$pf" 2>/dev/null) || continue
    kill -0 "$dpid" 2>/dev/null || continue
    instance=$(basename "$pf" | sed 's/powernode_sse_daemon_//;s/\.pid//')
    if [[ -f "/tmp/powernode_workspace_inbox_${instance}.jsonl" ]]; then
      RESOLVED_PID="$instance"
      break
    fi
  done
fi

CLAUDE_PID="${RESOLVED_PID:-$CLAUDE_PID}"
INBOX_FILE="/tmp/powernode_workspace_inbox_${CLAUDE_PID}.jsonl"
READ_STATE="/tmp/powernode_workspace_read_${CLAUDE_PID}.ids"

# Fast exit if no inbox
if [[ ! -f "$INBOX_FILE" ]]; then
  return 0 2>/dev/null || exit 0
fi

# Capture formatted output into a variable first — prevents orphaned
# <workspace-messages> tags if python3 fails mid-output.
FORMATTED=$(timeout 2 python3 -c "
import json, os, sys

inbox_path = '$INBOX_FILE'
read_state_path = '$READ_STATE'

# Load seen message IDs
seen_ids = set()
if os.path.exists(read_state_path):
    with open(read_state_path, 'r') as f:
        for line in f:
            line = line.strip()
            if line:
                seen_ids.add(line)

# Parse inbox — collect unread events (IDs not in read-state)
unread = []
new_ids = []
with open(inbox_path, 'r') as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            evt = json.loads(line)
        except json.JSONDecodeError:
            continue
        msg_id = evt.get('message_id', '')
        if msg_id and msg_id not in seen_ids:
            unread.append(evt)
            new_ids.append(msg_id)

if not unread:
    sys.exit(0)

# Format output
conv_ids = set()
lines = []
lines.append(f'You have {len(unread)} unread workspace message(s):')
lines.append('')

for evt in unread:
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

    lines.append(f'[{time_part}] {sender} {label}{ws_label}:')
    lines.append(f'  \"{content}\"')
    if msg_id:
        details = f'message_id: {msg_id}'
        if conv_id:
            details += f', conversation: {conv_id}'
        lines.append(f'  ({details})')
    lines.append('')

if conv_ids:
    lines.append('IMPORTANT: If these messages require a response, reply using the platform.send_message MCP tool:')
    lines.append('  tool: platform.send_message')
    lines.append('  params: conversation_id=<id>, message=<your reply>')
    for cid in sorted(conv_ids):
        lines.append(f'  Active conversation: {cid}')

print('\n'.join(lines))

# Append new IDs to read-state file
if new_ids:
    all_ids = list(seen_ids) + new_ids
    # Bound to last 200 IDs via atomic rename
    if len(all_ids) > 200:
        all_ids = all_ids[-200:]
    tmp_path = read_state_path + '.tmp'
    with open(tmp_path, 'w') as f:
        for mid in all_ids:
            f.write(mid + '\n')
    os.rename(tmp_path, read_state_path)
" 2>/dev/null || true)

# Only emit XML wrapper if there's actual content
if [[ -n "$FORMATTED" ]]; then
  echo "<workspace-messages>"
  echo "$FORMATTED"
  echo "</workspace-messages>"
fi
