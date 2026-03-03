#!/usr/bin/env bash
# Send a reply to a workspace conversation via the MCP platform.send_message tool.
#
# Usage:
#   workspace-reply.sh <conversation_id> <message> [mentions_json]
#
# Uses the daemon's OAuth token and MCP session for authentication.
# The session file is keyed to Claude's PID — we walk the process tree
# upward from $$ to find the ancestor `claude` process.

set -eo pipefail

# --- Resolve Claude's PID by walking the process tree upward ---
_resolve_claude_pid() {
  local pid=$$
  while [ "$pid" -gt 1 ] 2>/dev/null; do
    local comm
    comm=$(ps -p "$pid" -o comm= 2>/dev/null) || break
    [ "$comm" = "claude" ] && echo "$pid" && return 0
    pid=$(ps -p "$pid" -o ppid= 2>/dev/null | tr -d ' ')
    [ -z "$pid" ] && break
  done
  return 1
}

PLATFORM_URL="${POWERNODE_URL:-http://localhost:3000}"
MCP_ENDPOINT="${PLATFORM_URL}/api/v1/mcp/message"
TOKEN_FILE="/tmp/powernode_mcp_token.txt"

# Session discovery: ancestor walk → glob fallback
CLAUDE_PID=$(_resolve_claude_pid 2>/dev/null || true)
if [[ -n "$CLAUDE_PID" && -f "/tmp/powernode_mcp_session_${CLAUDE_PID}.txt" ]]; then
  SESSION_FILE="/tmp/powernode_mcp_session_${CLAUDE_PID}.txt"
else
  # Glob fallback: pick the first available session file
  SESSION_FILE=""
  for f in /tmp/powernode_mcp_session_*.txt; do
    [[ -f "$f" && -s "$f" ]] && SESSION_FILE="$f" && break
  done
  if [[ -z "$SESSION_FILE" ]]; then
    echo "Error: No MCP session file found. Start the SSE daemon first." >&2
    exit 1
  fi
fi

CONVERSATION_ID="$1"
MESSAGE="$2"
MENTIONS_JSON="${3:-}"

if [[ -z "$CONVERSATION_ID" || -z "$MESSAGE" ]]; then
  echo "Usage: $0 <conversation_id> <message> [mentions_json]" >&2
  exit 1
fi

if [[ ! -f "$TOKEN_FILE" || ! -f "$SESSION_FILE" ]]; then
  echo "Error: SSE daemon token/session not found. Start the daemon first." >&2
  exit 1
fi

TOKEN=$(cat "$TOKEN_FILE")
SESSION=$(cat "$SESSION_FILE")

# Build JSON payload safely with python3 (handles all escaping)
PAYLOAD=$(python3 -c "
import json, sys
args = {
    'action': 'send_message',
    'conversation_id': sys.argv[1],
    'message': sys.argv[2]
}
mentions = sys.argv[3] if len(sys.argv) > 3 and sys.argv[3] else None
if mentions:
    args['mentions'] = json.loads(mentions)
print(json.dumps({
    'jsonrpc': '2.0',
    'id': 1,
    'method': 'tools/call',
    'params': {
        'name': 'platform.send_message',
        'arguments': args
    }
}))
" "$CONVERSATION_ID" "$MESSAGE" "$MENTIONS_JSON")

RESPONSE=$(curl -s -X POST "$MCP_ENDPOINT" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Mcp-Session-Id: $SESSION" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" 2>&1)

# Extract success/error from response
python3 -c "
import json, sys
try:
    r = json.loads(sys.argv[1])
    if 'error' in r:
        print(f'Error: {r[\"error\"][\"message\"]}')
        sys.exit(1)
    result = r.get('result', {})
    content = result.get('content', [{}])
    if content:
        data = json.loads(content[0].get('text', '{}'))
        if data.get('success'):
            print(f'Sent to {data[\"conversation_id\"]} as {data[\"sender\"]} (message_id: {data[\"message_id\"]})')
        else:
            print(f'Error: {data.get(\"error\", \"Unknown error\")}')
            sys.exit(1)
except Exception as e:
    print(f'Error parsing response: {e}')
    print(sys.argv[1][:200])
    sys.exit(1)
" "$RESPONSE"
