#!/usr/bin/env bash
# Pre-loads POWERNODE_MCP_TOKEN for .mcp.json header interpolation.
# Used as a fallback when Claude Code's automatic OAuth flow can't complete.
#
# Reuses the token/session infrastructure from mcp-helper.sh and workspace-sse-daemon.sh.
# Token is cached for 25 minutes (1500s), regenerated via rails runner.

set -eo pipefail

MCP_SERVER_DIR="${POWERNODE_ROOT:-/opt/powernode}/server"
MCP_TOKEN_FILE="/tmp/powernode_mcp_token.txt"
MCP_IDS_CACHE_FILE="/tmp/powernode_sse_ids_cache.txt"
MAX_AGE=1500  # 25 minutes

# Return cached token if fresh
if [[ -f "$MCP_TOKEN_FILE" && -s "$MCP_TOKEN_FILE" ]]; then
  age=$(( $(date +%s) - $(stat -c%Y "$MCP_TOKEN_FILE" 2>/dev/null || echo 0) ))
  if (( age < MAX_AGE )); then
    echo "POWERNODE_MCP_TOKEN=$(cat "$MCP_TOKEN_FILE")"
    exit 0
  fi
fi

# Need cached identifiers from SSE daemon
if [[ ! -f "$MCP_IDS_CACHE_FILE" || ! -s "$MCP_IDS_CACHE_FILE" ]]; then
  echo "POWERNODE_MCP_TOKEN=" # empty — will trigger 401 and OAuth fallback
  exit 0
fi

source "$MCP_IDS_CACHE_FILE"

# Generate fresh token via rails runner
token=$(cd "$MCP_SERVER_DIR" && bin/rails runner "
app = Doorkeeper::Application.find('$OAUTH_APP_ID')
token = Doorkeeper::AccessToken.create!(
  application: app,
  resource_owner_id: '$RESOURCE_OWNER_ID',
  scopes: 'read write',
  expires_in: 7200,
  use_refresh_token: false
)
print token.plaintext_token || token.token
" 2>/dev/null) || true

if [[ -n "$token" && ${#token} -gt 10 ]]; then
  echo -n "$token" > "$MCP_TOKEN_FILE"
  echo "POWERNODE_MCP_TOKEN=$token"
else
  echo "POWERNODE_MCP_TOKEN=" # empty — graceful degradation
fi
