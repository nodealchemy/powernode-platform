#!/usr/bin/env bash
# Workspace SSE Daemon — maintains an SSE connection to the Powernode MCP endpoint
# and writes workspace events (mentions, messages) to a JSONL inbox file.
#
# Usage:
#   workspace-sse-daemon.sh start   — Start daemon in background
#   workspace-sse-daemon.sh stop    — Stop running daemon
#   workspace-sse-daemon.sh status  — Show daemon status
#   workspace-sse-daemon.sh tail    — Tail recent events
#   workspace-sse-daemon.sh refresh — Force token refresh

set -eo pipefail

# --- Configuration ---
PLATFORM_URL="${POWERNODE_URL:-http://localhost:3000}"
SSE_ENDPOINT="${PLATFORM_URL}/api/v1/mcp/message"
SERVER_DIR="${POWERNODE_ROOT:-/opt/powernode}/server"

INBOX_FILE="/tmp/powernode_workspace_inbox.jsonl"
PID_FILE="/tmp/powernode_sse_daemon.pid"
LOG_FILE="/tmp/powernode_sse_daemon.log"
TOKEN_FILE="/tmp/powernode_sse_token.txt"
SESSION_FILE="/tmp/powernode_sse_session.txt"
SEEN_FILE="/tmp/powernode_sse_seen_ids.txt"

# Identifiers resolved at startup via rails runner (survives re-seeds)
AGENT_ID_FILE="/tmp/powernode_sse_agent_id.txt"
IDS_CACHE_FILE="/tmp/powernode_sse_ids_cache.txt"

resolve_identifiers() {
  # Return cached values if fresh (< 1 hour old)
  if [[ -f "$IDS_CACHE_FILE" ]] && [[ -s "$IDS_CACHE_FILE" ]]; then
    local age
    age=$(( $(date +%s) - $(stat -c%Y "$IDS_CACHE_FILE") ))
    if (( age < 3600 )); then
      source "$IDS_CACHE_FILE"
      if [[ -n "${OAUTH_APP_ID:-}" && -n "${AGENT_ID:-}" && -n "${RESOURCE_OWNER_ID:-}" ]]; then
        return 0
      fi
    fi
  fi

  log "Resolving identifiers via rails runner..."
  local result
  result=$(cd "$SERVER_DIR" && bin/rails runner '
agent = Ai::Agent.find_by(agent_type: "mcp_client", status: "active")
abort "No active mcp_client agent found" unless agent
app = Doorkeeper::Application.find_by(name: "Claude Code (powernode)")
app ||= Doorkeeper::Application.first
abort "No OAuth application found" unless app
owner = agent.account.users.order(:created_at).first
abort "No resource owner found" unless owner
puts "OAUTH_APP_ID=\"#{app.id}\""
puts "AGENT_ID=\"#{agent.id}\""
puts "RESOURCE_OWNER_ID=\"#{owner.id}\""
' 2>>"$LOG_FILE") || { log "ERROR: Failed to resolve identifiers"; return 1; }

  echo "$result" > "$IDS_CACHE_FILE"
  source "$IDS_CACHE_FILE"
  log "Resolved: agent=$AGENT_ID owner=$RESOURCE_OWNER_ID app=$OAUTH_APP_ID"
}

MAX_INBOX_LINES=100
TOKEN_REFRESH_INTERVAL=1800  # 30 minutes
MAX_BACKOFF=30
NUDGE_COOLDOWN=10  # seconds between tmux nudges (prevents spam)

# --- Tmux Injection ---
# Finds the tmux pane running Claude Code and injects the message content
# directly as a prompt. Slash commands (/clear, /commit) are passed through
# as-is so Claude Code handles them natively.
_last_nudge=0

nudge_claude() {
  local message_content="${1:-}"
  local now
  now=$(date +%s)

  # Rate-limit: don't inject more often than NUDGE_COOLDOWN seconds
  if (( now - _last_nudge < NUDGE_COOLDOWN )); then
    log "Inject skipped (cooldown)"
    return
  fi

  # Find the tmux pane running claude
  local target
  target=$(tmux list-panes -a -F '#{session_name}:#{window_index}.#{pane_index} #{pane_current_command}' 2>/dev/null \
    | grep -m1 ' claude$' \
    | cut -d' ' -f1) || true

  if [[ -z "$target" ]]; then
    log "Inject: no tmux pane running claude found"
    return
  fi

  # Strip leading @mention of our agent name and trailing punctuation/space
  local cleaned
  cleaned=$(echo "$message_content" | sed 's/^@Claude Code ([^)]*) #[0-9]*[, :]* *//')

  # Use the actual message content as the prompt, or a default fallback
  local prompt="${cleaned:-check workspace messages}"

  # Send text with -l (literal) to handle special chars, pause, then Enter.
  tmux send-keys -t "$target" -l "$prompt" 2>/dev/null && \
    sleep 0.2 && \
    tmux send-keys -t "$target" Enter 2>/dev/null && {
    _last_nudge=$now
    log "Injected to tmux pane $target: ${prompt:0:60}"
  } || {
    log "Inject: tmux send-keys failed for $target"
  }
}

# --- Logging ---
log() {
  echo "[$(date -Iseconds)] $*" >> "$LOG_FILE"
}

log_and_echo() {
  local msg="[$(date -Iseconds)] $*"
  echo "$msg" >> "$LOG_FILE"
  echo "$msg"
}

# --- Token Management ---
refresh_token() {
  log "Refreshing OAuth token via rails runner..."

  local ruby_script
  ruby_script=$(cat <<RUBY
app = Doorkeeper::Application.find("$OAUTH_APP_ID")
token = Doorkeeper::AccessToken.create!(
  application: app,
  resource_owner_id: "$RESOURCE_OWNER_ID",
  scopes: "read write",
  expires_in: 7200,
  use_refresh_token: false
)
print token.plaintext_token || token.token
RUBY
)

  local new_token
  new_token=$(cd "$SERVER_DIR" && bin/rails runner "$ruby_script" 2>>"$LOG_FILE")

  if [[ -n "$new_token" && ${#new_token} -gt 10 ]]; then
    echo -n "$new_token" > "$TOKEN_FILE"
    log "Token refreshed successfully (${#new_token} chars)"
    return 0
  else
    log "ERROR: Token refresh failed — got empty or short response"
    return 1
  fi
}

get_token() {
  if [[ -f "$TOKEN_FILE" && -s "$TOKEN_FILE" ]]; then
    cat "$TOKEN_FILE"
  else
    return 1
  fi
}

# --- MCP Session Management ---
ensure_session() {
  if [[ -f "$SESSION_FILE" && -s "$SESSION_FILE" ]]; then
    local existing
    existing=$(cat "$SESSION_FILE")
    local check_script="s = McpSession.active.find_by(session_token: \"$existing\"); print s ? \"active\" : \"expired\""
    local status
    status=$(cd "$SERVER_DIR" && bin/rails runner "$check_script" 2>>"$LOG_FILE") || true
    if [[ "$status" == "active" ]]; then
      return 0
    fi
    log "Session $existing expired, creating new one"
  fi

  local session_script
  session_script=$(cat <<RUBY
session = McpSession.active
  .where(ai_agent_id: "$AGENT_ID")
  .order(last_activity_at: :desc)
  .first

unless session
  user = User.find("$RESOURCE_OWNER_ID")
  session = McpSession.create!(
    user: user,
    account: user.account,
    protocol_version: "2025-11-25",
    client_info: { name: "workspace-sse-daemon", version: "1.0" },
    ip_address: "127.0.0.1",
    user_agent: "workspace-sse-daemon/1.0",
    expires_at: 24.hours.from_now,
    oauth_application_id: "$OAUTH_APP_ID",
    ai_agent_id: "$AGENT_ID"
  )
end
print session.session_token
RUBY
)

  local session_token
  session_token=$(cd "$SERVER_DIR" && bin/rails runner "$session_script" 2>>"$LOG_FILE")

  if [[ -n "$session_token" ]]; then
    echo -n "$session_token" > "$SESSION_FILE"
    log "MCP session: $session_token"
    return 0
  else
    log "ERROR: Failed to get/create MCP session"
    return 1
  fi
}

# --- Deduplication ---
mark_seen() {
  local msg_id="$1"
  echo "$msg_id" >> "$SEEN_FILE"
  # Keep file bounded
  if [[ -f "$SEEN_FILE" ]]; then
    local count
    count=$(wc -l < "$SEEN_FILE")
    if (( count > 500 )); then
      tail -200 "$SEEN_FILE" > "${SEEN_FILE}.tmp" && mv "${SEEN_FILE}.tmp" "$SEEN_FILE"
    fi
  fi
}

is_seen() {
  local msg_id="$1"
  [[ -n "$msg_id" && -f "$SEEN_FILE" ]] && grep -qF "$msg_id" "$SEEN_FILE"
}

# --- Inbox Management ---
write_event() {
  local json="$1"
  echo "$json" >> "$INBOX_FILE"
  if [[ -f "$INBOX_FILE" ]]; then
    local count
    count=$(wc -l < "$INBOX_FILE")
    if (( count > MAX_INBOX_LINES )); then
      tail -$((MAX_INBOX_LINES / 2)) "$INBOX_FILE" > "${INBOX_FILE}.tmp" && mv "${INBOX_FILE}.tmp" "$INBOX_FILE"
    fi
  fi
}

# --- SSE Event Processor ---
# Uses python3 for robust JSON parsing — avoids shell string escaping nightmares.
# Reads the raw SSE data JSON and writes a normalized inbox entry.
process_sse_event() {
  local event_type="$1"
  local data="$2"

  # Skip non-workspace events
  case "$event_type" in
    ping|open) return ;;
    message) return ;;  # MCP JSON-RPC notifications
    message_created|mention|ai_response_complete) ;;
    *) log "Ignoring event type: $event_type"; return ;;
  esac

  # Use python3 for all JSON operations — safe against any content.
  # Handles two broadcast formats:
  #   1. ActionCable channel: {type, message: {id, sender_type, sender_info: {name}, content, ...}}
  #   2. MCP session pubsub:  {type, conversation_id, workspace, message: {id, sender, content, ...}}
  local result
  result=$(python3 -c "
import json, sys
from datetime import datetime, timezone

raw = sys.argv[1]
event_type = sys.argv[2]
seen_file = sys.argv[3]

try:
    d = json.loads(raw)
except json.JSONDecodeError:
    sys.exit(1)

# The event may have a nested 'message' object (both broadcast formats do)
msg = d.get('message', {}) if isinstance(d.get('message'), dict) else {}

# Extract message_id for dedup — try message.id first, then top-level
msg_id = str(msg.get('id', '') or d.get('message_id', '') or '')

# Check dedup — but allow ai_response_complete to update existing entries
# (message_created fires with partial streaming content, ai_response_complete has the full text)
is_update = False
if msg_id:
    try:
        with open(seen_file, 'r') as f:
            if msg_id in f.read():
                if event_type == 'ai_response_complete':
                    is_update = True  # Fall through to build full entry with UPDATE: prefix
                else:
                    print('DEDUP')
                    sys.exit(0)
    except FileNotFoundError:
        pass

# Extract sender — multiple possible locations:
#   - message.sender (MCP pubsub format: plain string)
#   - message.sender_info.name (ActionCable format: object)
#   - top-level sender_name (manual/test broadcasts)
sender = ''
if isinstance(msg.get('sender'), str) and msg['sender']:
    sender = msg['sender']
elif isinstance(msg.get('sender_info'), dict):
    sender = msg['sender_info'].get('name', '')
if not sender:
    sender = d.get('sender_name', '') or d.get('sender', '') or ''
    if isinstance(sender, dict):
        sender = sender.get('name', '')
sender = sender or 'Unknown'

# Extract content — from message.content or top-level
content = str(msg.get('content', '') or d.get('content', '') or '')

# Extract workspace name — top-level only (MCP pubsub format has it)
workspace = str(d.get('workspace', '') or d.get('workspace_name', '') or '')

# Conversation ID — top-level or from d
conv_id = str(d.get('conversation_id', '') or '')

entry = {
    'ts': datetime.now(timezone.utc).isoformat(),
    'event': event_type,
    'workspace': workspace,
    'sender': sender,
    'content': content,
    'message_id': msg_id,
    'conversation_id': conv_id,
    'read': False
}

prefix = 'UPDATE:' if is_update else ''
print(prefix + json.dumps(entry))
" "$data" "$event_type" "$SEEN_FILE" 2>>"$LOG_FILE") || return

  if [[ "$result" == "DEDUP" ]]; then
    log "Dedup: skipping duplicate event"
    return
  fi

  if [[ "$result" == UPDATE:* ]]; then
    # ai_response_complete with full content — replace the partial entry in inbox
    local updated_json="${result#UPDATE:}"
    local update_msg_id
    update_msg_id=$(echo "$updated_json" | python3 -c "import sys,json; print(json.load(sys.stdin).get('message_id',''))" 2>/dev/null) || true

    if [[ -n "$update_msg_id" && -f "$INBOX_FILE" ]]; then
      # Replace the line containing this message_id with the updated entry
      python3 -c "
import sys, json

msg_id = sys.argv[1]
new_entry = sys.argv[2]
inbox = sys.argv[3]

lines = []
replaced = False
with open(inbox, 'r') as f:
    for line in f:
        line = line.rstrip('\n')
        if not line:
            continue
        try:
            entry = json.loads(line)
            if entry.get('message_id') == msg_id:
                lines.append(new_entry)
                replaced = True
                continue
        except (json.JSONDecodeError, AttributeError):
            pass
        lines.append(line)

if not replaced:
    lines.append(new_entry)

with open(inbox, 'w') as f:
    f.write('\n'.join(lines) + '\n')
" "$update_msg_id" "$updated_json" "$INBOX_FILE" 2>>"$LOG_FILE"
      log "UPDATE [$event_type] msg_id=$update_msg_id — replaced partial with complete content"
    fi
    return
  fi

  if [[ -n "$result" ]]; then
    write_event "$result"
    # Extract fields via python (tab-delimited to preserve names with spaces)
    local fields msg_id sender content
    fields=$(echo "$result" | python3 -c "
import sys, json
e = json.load(sys.stdin)
print(e.get('message_id','') + '\t' + e.get('sender','?') + '\t' + e.get('content','')[:120])
" 2>/dev/null) || fields="?\t?\t?"
    IFS=$'\t' read -r msg_id sender content <<< "$fields"
    [[ -n "$msg_id" ]] && mark_seen "$msg_id"
    log "EVENT [$event_type] from $sender"

    # Desktop notification
    if command -v notify-send &>/dev/null; then
      local urgency="normal"
      [[ "$event_type" == "mention" ]] && urgency="critical"
      notify-send -u "$urgency" -i dialog-information -a "Powernode" \
        "$sender" "$content" 2>/dev/null || true
    fi

    # Inject into Claude Code via tmux — skip our own agent's messages to avoid loops
    if [[ "$sender" != *Claude\ Code* ]]; then
      nudge_claude "$content"
    fi
  fi
}

# --- SSE Connection ---
run_sse_loop() {
  local token session_id
  token=$(get_token) || { log "ERROR: No token available"; return 1; }
  session_id=$(cat "$SESSION_FILE" 2>/dev/null) || { log "ERROR: No session available"; return 1; }

  log "Connecting to SSE: $SSE_ENDPOINT (session: ${session_id:0:12}...)"

  # Pipe curl directly into the read loop.
  curl -sS -N \
    --max-time 0 \
    -H "Authorization: Bearer $token" \
    -H "Mcp-Session-Id: $session_id" \
    -H "Accept: text/event-stream" \
    -H "Cache-Control: no-cache" \
    "$SSE_ENDPOINT" 2>>"$LOG_FILE" | {
    set +eo pipefail  # Disable errexit in subshell — process_sse_event may fail non-fatally
    local current_event="" current_data=""

    log "SSE read loop started"

    while IFS= read -r line; do
      line="${line%$'\r'}"

      if [[ "$line" == event:* ]]; then
        current_event="${line#event: }"
      elif [[ "$line" == data:* ]]; then
        if [[ -z "$current_data" ]]; then
          current_data="${line#data: }"
        else
          current_data="${current_data}${line#data: }"
        fi
      elif [[ -z "$line" ]]; then
        if [[ -n "$current_event" && -n "$current_data" ]]; then
          process_sse_event "$current_event" "$current_data" || log "process_sse_event failed for $current_event"
        fi
        current_event=""
        current_data=""
      fi
    done

    log "SSE read loop exited"
  }
  local exit_code=$?

  log "SSE connection closed (exit: $exit_code)"
  return 1
}

# --- Daemon Loop ---
_run_daemon_loop() {
  trap '_cleanup' EXIT SIGTERM SIGINT

  # Resolve identifiers before anything else
  resolve_identifiers || { log "ERROR: Cannot resolve identifiers"; exit 1; }

  local backoff=1
  local last_token_refresh
  last_token_refresh=$(date +%s)

  while true; do
    # Periodic token refresh
    local now
    now=$(date +%s)
    if (( now - last_token_refresh > TOKEN_REFRESH_INTERVAL )); then
      log "Periodic token refresh..."
      if refresh_token; then
        last_token_refresh=$now
        backoff=1
      fi
    fi

    # Ensure session is valid
    ensure_session || { sleep "$backoff"; continue; }

    # Run SSE connection (blocks until disconnect)
    if run_sse_loop; then
      backoff=1
    else
      log "SSE disconnected, reconnecting in ${backoff}s..."
      sleep "$backoff"
      backoff=$(( backoff * 2 ))
      (( backoff > MAX_BACKOFF )) && backoff=$MAX_BACKOFF
    fi
  done
}

_cleanup() {
  # Prevent re-entry from signal during cleanup
  trap '' EXIT SIGTERM SIGINT
  log "Daemon shutting down..."
  rm -f "$PID_FILE"
  # Kill all children (curl etc.)
  kill 0 2>/dev/null || true
  log "Daemon stopped"
}

# --- Daemon Control ---
start_daemon() {
  if is_running; then
    log_and_echo "Daemon already running (PID: $(cat "$PID_FILE"))"
    return 0
  fi

  log_and_echo "Starting workspace SSE daemon..."

  # Resolve identifiers (concierge agent, OAuth app, resource owner)
  resolve_identifiers || { log_and_echo "ERROR: Cannot resolve identifiers"; return 1; }

  # Ensure token
  if [[ ! -f "$TOKEN_FILE" ]] || [[ ! -s "$TOKEN_FILE" ]]; then
    log_and_echo "No token found, refreshing..."
    refresh_token || { log_and_echo "ERROR: Cannot start without token"; return 1; }
  fi

  # Ensure session
  ensure_session || { log_and_echo "ERROR: Cannot start without MCP session"; return 1; }

  # Launch daemon in background via nohup
  nohup "$0" _daemon >> "$LOG_FILE" 2>&1 &
  local daemon_pid=$!
  disown "$daemon_pid" 2>/dev/null || true
  echo "$daemon_pid" > "$PID_FILE"

  log_and_echo "Daemon started (PID: $daemon_pid)"
  log_and_echo "  Inbox:   $INBOX_FILE"
  log_and_echo "  Log:     $LOG_FILE"
  log_and_echo "  Session: $(cat "$SESSION_FILE" 2>/dev/null | head -c 12)..."
}

stop_daemon() {
  if ! is_running; then
    log_and_echo "Daemon is not running"
    rm -f "$PID_FILE"
    # Kill any orphaned curl SSE connections from previous runs
    pkill -f "curl.*Mcp-Session-Id.*text/event-stream.*${SSE_ENDPOINT}" 2>/dev/null || true
    return 0
  fi

  local pid
  pid=$(cat "$PID_FILE")
  log_and_echo "Stopping daemon (PID: $pid)..."

  # Kill the entire process group to catch curl child processes.
  # The daemon runs with its own PGID (equal to its PID via setsid).
  kill -- -"$pid" 2>/dev/null || kill "$pid" 2>/dev/null || true

  # Wait for clean shutdown (up to 5s)
  local i=0
  while (( i < 10 )) && kill -0 "$pid" 2>/dev/null; do
    sleep 0.5
    i=$((i + 1))
  done

  if kill -0 "$pid" 2>/dev/null; then
    log_and_echo "Force-killing daemon..."
    kill -9 -- -"$pid" 2>/dev/null || kill -9 "$pid" 2>/dev/null || true
  fi

  # Safety net: kill any lingering curl SSE connections for this endpoint
  pkill -f "curl.*Mcp-Session-Id.*text/event-stream.*${SSE_ENDPOINT}" 2>/dev/null || true

  rm -f "$PID_FILE"
  log_and_echo "Daemon stopped"
}

is_running() {
  [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null
}

show_status() {
  if is_running; then
    local pid
    pid=$(cat "$PID_FILE")
    echo "Workspace SSE daemon: RUNNING (PID: $pid)"
    local inbox_count=0
    [[ -f "$INBOX_FILE" ]] && inbox_count=$(wc -l < "$INBOX_FILE")
    echo "  Inbox:   $INBOX_FILE ($inbox_count events)"
    echo "  Log:     $LOG_FILE"
    echo "  Token:   $TOKEN_FILE ($(stat -c%s "$TOKEN_FILE" 2>/dev/null || echo 0) bytes)"
    echo "  Session: $(cat "$SESSION_FILE" 2>/dev/null || echo 'none')"
    echo ""
    local unread=0
    [[ -f "$INBOX_FILE" ]] && unread=$(grep -c '"read": false' "$INBOX_FILE" 2>/dev/null || true)
    echo "  Unread events: ${unread:-0}"
    echo ""
    echo "  Last 3 log entries:"
    tail -3 "$LOG_FILE" 2>/dev/null | sed 's/^/    /'
  else
    echo "Workspace SSE daemon: STOPPED"
    if [[ -f "$PID_FILE" ]]; then
      echo "  (stale PID file exists — daemon may have crashed)"
    fi
  fi
}

tail_events() {
  if [[ ! -f "$INBOX_FILE" ]]; then
    echo "No events (inbox file does not exist)"
    return
  fi

  local count
  count=$(wc -l < "$INBOX_FILE")
  echo "Last 10 events (of $count total):"
  echo ""

  tail -10 "$INBOX_FILE" | python3 -c "
import json, sys
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        e = json.loads(line)
        ts = e.get('ts', '?')
        evt = e.get('event', '?')
        sender = e.get('sender', '?')
        content = e.get('content', '')[:60]
        status = 'read' if e.get('read') else 'UNREAD'
        print(f'  [{ts}] ({evt}) {sender}: {content} [{status}]')
    except json.JSONDecodeError:
        print(f'  [parse error] {line[:60]}')
" 2>/dev/null
}

# --- Main ---
case "${1:-}" in
  start)
    start_daemon
    ;;
  stop)
    stop_daemon
    ;;
  status)
    show_status
    ;;
  tail)
    tail_events
    ;;
  refresh)
    refresh_token && echo "Token refreshed" || echo "Token refresh failed"
    ;;
  _daemon)
    # Internal: called by start_daemon via nohup
    _run_daemon_loop
    ;;
  *)
    echo "Usage: $0 {start|stop|status|tail|refresh}"
    exit 1
    ;;
esac
