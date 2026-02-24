#!/usr/bin/env bash
# MCP Helper — reusable functions for invoking Powernode MCP tools from Claude Code sessions.
#
# Usage:
#   source .claude/hooks/mcp-helper.sh
#   mcp_token                          # Get/cache OAuth token
#   mcp_call "platform.tool_name" '{}' # Invoke any platform.* tool
#
# Dependencies: curl, python3 (for JSON formatting)
# Token/session files are shared with workspace-sse-daemon.sh

set -eo pipefail

# --- Configuration (shared with workspace-sse-daemon.sh) ---
MCP_PLATFORM_URL="${POWERNODE_URL:-http://localhost:3000}"
MCP_ENDPOINT="${MCP_PLATFORM_URL}/api/v1/mcp/message"
MCP_SERVER_DIR="${POWERNODE_ROOT:-/opt/powernode}/server"
MCP_TOKEN_FILE="/tmp/powernode_mcp_token.txt"
MCP_SESSION_FILE="/tmp/powernode_sse_session.txt"
MCP_IDS_CACHE_FILE="/tmp/powernode_sse_ids_cache.txt"

# --- Token Management ---

# Get or refresh the MCP OAuth token. Returns the token on stdout.
mcp_token() {
  # Return cached token if fresh (< 25 min old)
  if [[ -f "$MCP_TOKEN_FILE" && -s "$MCP_TOKEN_FILE" ]]; then
    local age
    age=$(( $(date +%s) - $(stat -c%Y "$MCP_TOKEN_FILE") ))
    if (( age < 1500 )); then
      cat "$MCP_TOKEN_FILE"
      return 0
    fi
  fi

  # Resolve identifiers (from cache or rails runner)
  if [[ -f "$MCP_IDS_CACHE_FILE" && -s "$MCP_IDS_CACHE_FILE" ]]; then
    source "$MCP_IDS_CACHE_FILE"
  else
    echo "ERROR: No cached identifiers. Start the SSE daemon first: .claude/hooks/workspace-sse-daemon.sh start" >&2
    return 1
  fi

  # Refresh token via rails runner
  local new_token
  new_token=$(cd "$MCP_SERVER_DIR" && bin/rails runner "
app = Doorkeeper::Application.find('$OAUTH_APP_ID')
token = Doorkeeper::AccessToken.create!(
  application: app,
  resource_owner_id: '$RESOURCE_OWNER_ID',
  scopes: 'read write',
  expires_in: 7200,
  use_refresh_token: false
)
print token.plaintext_token || token.token
" 2>/dev/null)

  if [[ -n "$new_token" && ${#new_token} -gt 10 ]]; then
    echo -n "$new_token" > "$MCP_TOKEN_FILE"
    echo "$new_token"
    return 0
  else
    echo "ERROR: Token refresh failed" >&2
    return 1
  fi
}

# --- MCP Session ---

# Get or create an MCP session token. Returns session token on stdout.
mcp_session() {
  if [[ -f "$MCP_SESSION_FILE" && -s "$MCP_SESSION_FILE" ]]; then
    cat "$MCP_SESSION_FILE"
    return 0
  fi

  echo "ERROR: No MCP session. Start the SSE daemon first: .claude/hooks/workspace-sse-daemon.sh start" >&2
  return 1
}

# --- Tool Invocation ---

# Call any platform.* MCP tool.
# Usage: mcp_call "platform.knowledge_health" '{"key": "value"}'
mcp_call() {
  local tool_name="$1"
  local args="$2"
  : "${args:="{}"}"

  local token session_id
  token=$(mcp_token) || return 1
  session_id=$(mcp_session) || return 1

  local request_id
  request_id="$(date +%s)-$$"

  local payload
  payload=$(python3 -c "
import json, sys
print(json.dumps({
    'jsonrpc': '2.0',
    'id': sys.argv[3],
    'method': 'tools/call',
    'params': {
        'name': sys.argv[1],
        'arguments': json.loads(sys.argv[2])
    }
}))
" "$tool_name" "$args" "$request_id" 2>/dev/null) || {
    echo "ERROR: Failed to build JSON payload" >&2
    return 1
  }

  local response
  response=$(curl -sS \
    -X POST \
    -H "Authorization: Bearer $token" \
    -H "Mcp-Session-Id: $session_id" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    -d "$payload" \
    "$MCP_ENDPOINT" 2>/dev/null)

  # Pretty-print if python3 available, raw otherwise
  if command -v python3 &>/dev/null; then
    echo "$response" | python3 -m json.tool 2>/dev/null || echo "$response"
  else
    echo "$response"
  fi
}

# --- Convenience Wrappers ---

# Quick health check
mcp_health() {
  mcp_call "platform.knowledge_health" '{}'
}

# Query learnings by category
mcp_learnings() {
  local query="${1:-}"
  local category="${2:-}"
  local args="{}"
  if [[ -n "$query" && -n "$category" ]]; then
    args="{\"query\": \"$query\", \"category\": \"$category\"}"
  elif [[ -n "$query" ]]; then
    args="{\"query\": \"$query\"}"
  fi
  mcp_call "platform.query_learnings" "$args"
}

# Search shared knowledge
mcp_search() {
  local query="$1"
  mcp_call "platform.search_knowledge" "{\"query\": \"$query\"}"
}
