#!/usr/bin/env bash
# Send a reply to a workspace conversation via the MCP platform.send_message tool.
#
# Usage:
#   workspace-reply.sh <conversation_id> <message>
#
# Uses the daemon's OAuth token and MCP session for authentication.

set -eo pipefail

PLATFORM_URL="${POWERNODE_URL:-http://localhost:3000}"
MCP_ENDPOINT="${PLATFORM_URL}/api/v1/mcp/message"
TOKEN_FILE="/tmp/powernode_sse_token.txt"
SESSION_FILE="/tmp/powernode_sse_session.txt"

CONVERSATION_ID="$1"
MESSAGE="$2"

if [[ -z "$CONVERSATION_ID" || -z "$MESSAGE" ]]; then
  echo "Usage: $0 <conversation_id> <message>" >&2
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
print(json.dumps({
    'jsonrpc': '2.0',
    'id': 1,
    'method': 'tools/call',
    'params': {
        'name': 'platform.send_message',
        'arguments': {
            'action': 'send_message',
            'conversation_id': sys.argv[1],
            'message': sys.argv[2]
        }
    }
}))
" "$CONVERSATION_ID" "$MESSAGE")

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
