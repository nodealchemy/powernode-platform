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
MCP_TOKEN_FILE="/tmp/powernode_mcp_token.txt"                    # shared (unchanged)
MCP_INSTANCE_ID="${MCP_INSTANCE_ID:-${PPID}}"
MCP_SESSION_FILE="/tmp/powernode_mcp_session_${MCP_INSTANCE_ID}.txt"       # per-instance
MCP_SESSION_NAME_FILE="/tmp/powernode_mcp_session_name_${MCP_INSTANCE_ID}.txt"  # per-instance
MCP_CC_CREDENTIALS="${HOME}/.claude/.credentials.json"           # Claude Code OAuth credentials

# Detect remote mode: POWERNODE_URL is not localhost
_mcp_is_remote() {
  [[ "$MCP_PLATFORM_URL" != *"localhost"* && "$MCP_PLATFORM_URL" != *"127.0.0.1"* ]]
}

# --- Token Management ---

# Extract OAuth access token from Claude Code's credentials file.
# Used in remote mode where rails runner tokens are invalid.
_mcp_cc_token() {
  [[ -f "$MCP_CC_CREDENTIALS" ]] || return 1
  python3 -c "
import json, sys, time
with open(sys.argv[1]) as f:
    d = json.load(f)
for key, val in d.get('mcpOAuth', {}).items():
    if key.startswith('powernode'):
        expires = val.get('expiresAt', 0)
        # expiresAt is in milliseconds
        if expires > time.time() * 1000:
            print(val['accessToken'], end='')
            sys.exit(0)
        else:
            print('EXPIRED', file=sys.stderr)
            sys.exit(1)
sys.exit(1)
" "$MCP_CC_CREDENTIALS" 2>/dev/null
}

# Get or refresh the MCP OAuth token. Returns the token on stdout.
# In remote mode, reads from Claude Code's credentials file.
# In local mode, generates tokens via rails runner.
mcp_token() {
  # Remote mode: always read from Claude Code's credentials file (cheap file read).
  # Skips the age-based cache to avoid stale tokens after OAuth rotation.
  if _mcp_is_remote; then
    local cc_token
    cc_token=$(_mcp_cc_token) || {
      echo "ERROR: Cannot read Powernode OAuth token from Claude Code credentials. Reconnect via /mcp." >&2
      return 1
    }
    echo -n "$cc_token" > "$MCP_TOKEN_FILE"
    echo "$cc_token"
    return 0
  fi

  # Local mode: return cached token if fresh (< 25 min old, avoids expensive rails runner)
  if [[ -f "$MCP_TOKEN_FILE" && -s "$MCP_TOKEN_FILE" ]]; then
    local age
    age=$(( $(date +%s) - $(stat -c%Y "$MCP_TOKEN_FILE") ))
    if (( age < 1500 )); then
      cat "$MCP_TOKEN_FILE"
      return 0
    fi
  fi

  # Local mode: resolve identifiers and generate token via rails runner
  local ids_cache="/tmp/powernode_sse_ids_cache.txt"
  if [[ -f "$ids_cache" && -s "$ids_cache" ]]; then
    source "$ids_cache"
  else
    echo "ERROR: No cached identifiers. Start the SSE daemon first: .claude/hooks/workspace-sse-daemon.sh start" >&2
    return 1
  fi

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

# Picks an unclaimed session from the session/discover response.
# Checks /tmp/powernode_mcp_session_*.txt files to see which sessions are
# already claimed by other live Claude Code instances. Returns 0 and prints
# the session token (tab-separated with display_name) on success.
_mcp_pick_unclaimed_session() {
  local discover_json="$1"
  local my_instance="${MCP_INSTANCE_ID:-}"

  python3 -c "
import json, sys, os, glob

data = json.loads(sys.argv[1])
my_instance = sys.argv[2] if len(sys.argv) > 2 else ''

sessions = data.get('result', {}).get('sessions', [])
if not sessions:
    sys.exit(1)

# Build set of session tokens already claimed by live processes
claimed = {}
for f in glob.glob('/tmp/powernode_mcp_session_*.txt'):
    base = os.path.basename(f)
    if 'name' in base:
        continue
    parts = base.replace('powernode_mcp_session_', '').replace('.txt', '')
    try:
        pid = int(parts)
    except ValueError:
        continue
    if my_instance and str(pid) == str(my_instance):
        continue
    try:
        os.kill(pid, 0)
    except OSError:
        continue  # Dead process — claim is stale
    try:
        with open(f) as fh:
            token = fh.read().strip()
            if token:
                claimed[token] = pid
    except (IOError, OSError):
        continue

# Pick first unclaimed session (newest first, already sorted by server)
for s in sessions:
    token = s.get('session_token', '')
    if token and token not in claimed:
        display = s.get('display_name', '') or ''
        print(token + '\t' + display)
        sys.exit(0)

sys.exit(1)
" "$discover_json" "$my_instance" 2>/dev/null
}

# Create a new MCP session via the initialize handshake.
# NOTE: No longer used as automatic fallback in mcp_ensure_session() because it
# creates a session with clientInfo.name "powernode-helper" instead of the real
# Claude Code identity. Kept for manual debugging use only.
# Returns tab-separated "session_token\tdisplay_name" on stdout.
_mcp_create_session() {
  local token="$1"
  local init_payload
  init_payload=$(python3 -c "
import json
print(json.dumps({
    'jsonrpc': '2.0',
    'id': 'init-helper',
    'method': 'initialize',
    'params': {
        'protocolVersion': '2025-03-26',
        'capabilities': {},
        'clientInfo': {
            'name': 'powernode-helper',
            'version': '1.0'
        }
    }
}))
" 2>/dev/null) || return 1

  local headers_file="/tmp/powernode_mcp_init_headers_$$.txt"
  local init_response
  init_response=$(curl -sS -D "$headers_file" -X POST \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    -d "$init_payload" \
    "$MCP_ENDPOINT" 2>/dev/null) || { rm -f "$headers_file"; return 1; }

  local session_id
  session_id=$(grep -i '^mcp-session-id:' "$headers_file" 2>/dev/null | tr -d '\r' | sed 's/^[^:]*: *//')
  rm -f "$headers_file"

  if [[ -z "$session_id" || ${#session_id} -lt 10 ]]; then
    return 1
  fi

  # Complete the handshake
  local notif_payload='{"jsonrpc":"2.0","method":"notifications/initialized","params":{}}'
  curl -sS -X POST \
    -H "Authorization: Bearer $token" \
    -H "Mcp-Session-Id: $session_id" \
    -H "Content-Type: application/json" \
    -d "$notif_payload" \
    "$MCP_ENDPOINT" >/dev/null 2>&1 || true

  echo "${session_id}	powernode-helper"
}

# Discover an existing MCP session via session/discover.
# Returns failure if no sessions are available yet (daemon retries with backoff).
# Caches the session token to MCP_SESSION_FILE (per-instance path).
mcp_ensure_session() {
  # Reuse cached session if fresh (< 1 hour) AND not a placeholder "powernode-helper" session.
  # Placeholder sessions are created by _mcp_create_session() before the real Claude Code
  # MCP client initializes — they have the wrong identity and should be upgraded.
  if [[ -f "$MCP_SESSION_FILE" && -s "$MCP_SESSION_FILE" ]]; then
    local age
    age=$(( $(date +%s) - $(stat -c%Y "$MCP_SESSION_FILE") ))
    if (( age < 3600 )); then
      local cached_name
      cached_name=$(cat "$MCP_SESSION_NAME_FILE" 2>/dev/null)
      if [[ "$cached_name" != *"powernode-helper"* ]]; then
        cat "$MCP_SESSION_FILE"
        return 0
      fi
      # Fall through to re-discover a real session (upgrade from placeholder)
    fi
  fi

  local token
  token=$(mcp_token) || return 1

  # Discover existing sessions instead of creating a new one
  local discover_payload='{"jsonrpc":"2.0","id":"discover-helper","method":"session/discover","params":{}}'
  local discover_response
  discover_response=$(curl -sS -X POST \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    -d "$discover_payload" \
    "$MCP_ENDPOINT" 2>/dev/null) || return 1

  local picked
  picked=$(_mcp_pick_unclaimed_session "$discover_response") || {
    # No discoverable sessions yet — fail gracefully.
    # The daemon loop retries with exponential backoff, and PostToolUse hook
    # (mcp-sse-autostart.sh) will discover the real session once Claude Code's
    # MCP client initializes. We intentionally do NOT fall back to
    # _mcp_create_session() here because it creates a competing session with
    # the wrong identity ("powernode-helper" instead of "Claude Code #N").
    return 1
  }

  local session_token display_name
  IFS=$'\t' read -r session_token display_name <<< "$picked"

  if [[ -n "$session_token" && ${#session_token} -gt 10 ]]; then
    echo -n "$session_token" > "$MCP_SESSION_FILE"
    [[ -n "$display_name" ]] && echo -n "$display_name" > "$MCP_SESSION_NAME_FILE"
    # Auto-start per-instance SSE daemon for this session
    mcp_ensure_daemon 2>/dev/null || true
    echo "$session_token"
    return 0
  else
    return 1
  fi
}

# Get or create an MCP session token. Returns session token on stdout.
# Uses per-instance session only (no shared fallback in per-instance mode).
mcp_session() {
  local result
  result=$(mcp_ensure_session 2>/dev/null)
  if [[ -n "$result" ]]; then
    echo "$result"
    return 0
  fi
  echo "ERROR: No MCP session available. Run: source .claude/hooks/mcp-helper.sh && mcp_ensure_session" >&2
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

  # Session-expired detection and single retry
  local is_session_error
  is_session_error=$(echo "$response" | python3 -c "
import sys, json
try:
    r = json.load(sys.stdin)
    msg = r.get('error', {}).get('message', '').lower()
    print('yes' if 'session' in msg and any(w in msg for w in ['expired','not found','invalid']) else '')
except: print('')
" 2>/dev/null)

  if [[ "$is_session_error" == "yes" ]]; then
    rm -f "$MCP_SESSION_FILE"
    session_id=$(mcp_session) || return 1
    response=$(curl -sS -X POST \
      -H "Authorization: Bearer $token" \
      -H "Mcp-Session-Id: $session_id" \
      -H "Content-Type: application/json" \
      -H "Accept: application/json" \
      -d "$payload" \
      "$MCP_ENDPOINT" 2>/dev/null)
  fi

  # Pretty-print if python3 available, raw otherwise
  if command -v python3 &>/dev/null; then
    echo "$response" | python3 -m json.tool 2>/dev/null || echo "$response"
  else
    echo "$response"
  fi
}

# --- Daemon Management ---

# Ensure a per-instance SSE daemon is running for this Claude Code session.
# Called automatically after session creation to keep the SSE stream alive.
mcp_ensure_daemon() {
  local pid_file="/tmp/powernode_sse_daemon_${MCP_INSTANCE_ID}.pid"

  # Already running?
  if [[ -f "$pid_file" ]] && kill -0 "$(cat "$pid_file" 2>/dev/null)" 2>/dev/null; then
    return 0
  fi

  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local daemon_script="${script_dir}/workspace-sse-daemon.sh"

  if [[ ! -x "$daemon_script" ]]; then
    echo "WARN: Daemon script not found at $daemon_script" >&2
    return 1
  fi

  # Start per-instance daemon in background
  INSTANCE_ID="$MCP_INSTANCE_ID" "$daemon_script" start >/dev/null 2>&1 &
  disown 2>/dev/null || true

  # Brief wait for PID file to appear
  local tries=0
  while (( tries < 10 )); do
    if [[ -f "$pid_file" ]] && kill -0 "$(cat "$pid_file" 2>/dev/null)" 2>/dev/null; then
      return 0
    fi
    sleep 0.3
    (( tries++ ))
  done

  echo "WARN: Daemon started but PID file not yet confirmed" >&2
  return 0
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
