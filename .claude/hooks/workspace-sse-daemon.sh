#!/usr/bin/env bash
# Workspace SSE Daemon — maintains an SSE connection to the Powernode MCP endpoint
# and writes workspace events (mentions, messages) to a JSONL inbox file.
#
# Usage:
#   workspace-sse-daemon.sh start   — Start daemon in background
#   workspace-sse-daemon.sh stop    — Stop running daemon
#   workspace-sse-daemon.sh reload  — SIGHUP: reconnect SSE with fresh channels
#   workspace-sse-daemon.sh status  — Show daemon status
#   workspace-sse-daemon.sh tail    — Tail recent events
#   workspace-sse-daemon.sh refresh — Force token refresh

set -eo pipefail

# --- Configuration ---
PLATFORM_URL="${POWERNODE_URL:-http://localhost:3000}"
SSE_ENDPOINT="${PLATFORM_URL}/api/v1/mcp/message"
SERVER_DIR="${POWERNODE_ROOT:-/opt/powernode}/server"
CC_CREDENTIALS="${HOME}/.claude/.credentials.json"

# Detect remote mode: POWERNODE_URL is not localhost
_is_remote() {
  [[ "$PLATFORM_URL" != *"localhost"* && "$PLATFORM_URL" != *"127.0.0.1"* ]]
}

# Extract OAuth token from Claude Code's credentials (remote mode only)
_cc_token() {
  [[ -f "$CC_CREDENTIALS" ]] || return 1
  python3 -c "
import json, sys, time
with open(sys.argv[1]) as f:
    d = json.load(f)
for key, val in d.get('mcpOAuth', {}).items():
    if key.startswith('powernode'):
        expires = val.get('expiresAt', 0)
        if expires > time.time() * 1000:
            print(val['accessToken'], end='')
            sys.exit(0)
        else:
            sys.exit(1)
sys.exit(1)
" "$CC_CREDENTIALS" 2>/dev/null
}

# Per-instance mode: INSTANCE_ID is the Claude Code PID that owns this daemon.
# When set, all file paths are keyed by this ID for full session isolation.
# Set via: INSTANCE_ID=<pid> workspace-sse-daemon.sh start
INSTANCE_ID="${INSTANCE_ID:-}"

if [[ -n "$INSTANCE_ID" ]]; then
  INBOX_FILE="/tmp/powernode_workspace_inbox_${INSTANCE_ID}.jsonl"
  PID_FILE="/tmp/powernode_sse_daemon_${INSTANCE_ID}.pid"
  LOG_FILE="/tmp/powernode_sse_daemon_${INSTANCE_ID}.log"
  SESSION_FILE="/tmp/powernode_mcp_session_${INSTANCE_ID}.txt"
  SESSION_NAME_FILE="/tmp/powernode_mcp_session_name_${INSTANCE_ID}.txt"
  SEEN_FILE="/tmp/powernode_sse_seen_ids_${INSTANCE_ID}.txt"
else
  INBOX_FILE="/tmp/powernode_workspace_inbox.jsonl"
  PID_FILE="/tmp/powernode_sse_daemon.pid"
  LOG_FILE="/tmp/powernode_sse_daemon.log"
  SESSION_FILE="/tmp/powernode_sse_session.txt"
  SESSION_NAME_FILE="/tmp/powernode_sse_session_name.txt"
  SEEN_FILE="/tmp/powernode_sse_seen_ids.txt"
fi

TOKEN_FILE="/tmp/powernode_mcp_token.txt"  # Shared — same OAuth credentials

# --- Session Discovery ---
# Picks an unclaimed session from the session/discover response.
# Checks /tmp/powernode_mcp_session_*.txt files to see which sessions are
# already claimed by other live Claude Code instances. Returns 0 and prints
# the session token on success, or returns 1 if no unclaimed session available.
_pick_unclaimed_session() {
  local discover_json="$1"
  local preferred_token="${2:-}"
  local my_instance="${INSTANCE_ID:-}"

  python3 -c "
import json, sys, os, glob, signal

data = json.loads(sys.argv[1])
my_instance = sys.argv[2] if len(sys.argv) > 2 else ''
preferred = sys.argv[3] if len(sys.argv) > 3 else ''

sessions = data.get('result', {}).get('sessions', [])
if not sessions:
    sys.exit(1)

# Build set of session tokens already claimed by live processes
claimed = {}
for f in glob.glob('/tmp/powernode_mcp_session_*.txt'):
    # Extract PID from filename: powernode_mcp_session_<PID>.txt
    base = os.path.basename(f)
    # Skip name files
    if 'name' in base:
        continue
    parts = base.replace('powernode_mcp_session_', '').replace('.txt', '')
    try:
        pid = int(parts)
    except ValueError:
        continue
    # Skip our own instance (allow re-claiming)
    if my_instance and str(pid) == str(my_instance):
        continue
    # Check if claimant is alive
    try:
        os.kill(pid, 0)
    except OSError:
        continue  # Dead process — claim is stale
    # Read the claimed session token
    try:
        with open(f) as fh:
            token = fh.read().strip()
            if token:
                claimed[token] = pid
    except (IOError, OSError):
        continue

# Prefer previously-held session to maintain instance affinity
if preferred:
    for s in sessions:
        token = s.get('session_token', '')
        if token == preferred and token not in claimed:
            display = s.get('display_name', '') or ''
            agent_id = s.get('agent_id', '') or ''
            print(token + '\t' + display + '\t' + agent_id)
            sys.exit(0)

# Fall back to first unclaimed session (newest first, already sorted by server)
for s in sessions:
    token = s.get('session_token', '')
    if token and token not in claimed:
        # Print token, display_name, and agent_id tab-separated
        display = s.get('display_name', '') or ''
        agent_id = s.get('agent_id', '') or ''
        print(token + '\t' + display + '\t' + agent_id)
        sys.exit(0)

# All sessions claimed
sys.exit(1)
" "$discover_json" "$my_instance" "$preferred_token" 2>>"$LOG_FILE"
}

_CURL_PID=""

MAX_INBOX_LINES=100
TOKEN_REFRESH_INTERVAL=1800  # 30 minutes
MAX_BACKOFF=30
NUDGE_COOLDOWN=10  # seconds between tmux nudges (prevents spam)
SSE_READ_TIMEOUT=90  # seconds — server pings every 30s; 3 missed pings = stale connection

# --- Tmux Injection ---
# Finds the tmux pane running Claude Code and injects the message content
# directly as a prompt. Slash commands (/clear, /commit) are passed through
# as-is so Claude Code handles them natively.
#
# If the user has text in the input, it is saved, cleared, and restored after
# the nudge prompt is submitted.
_last_nudge=0
PENDING_RESTORE_FILE="/tmp/powernode_nudge_restore.txt"

nudge_claude() {
  local message_content="${1:-}"
  local now
  now=$(date +%s)

  # Rate-limit: don't inject more often than NUDGE_COOLDOWN seconds
  if (( now - _last_nudge < NUDGE_COOLDOWN )); then
    log "Inject skipped (cooldown)"
    return
  fi

  # Find the tmux pane running claude — in per-instance mode, target only our pane
  local target
  if [[ -n "$INSTANCE_ID" ]]; then
    # Find the pane whose child is our specific Claude PID
    target=$(tmux list-panes -a -F '#{session_name}:#{window_index}.#{pane_index} #{pane_pid}' 2>/dev/null \
      | while read -r pane_ref pane_pid; do
          pgrep -P "$pane_pid" 2>/dev/null | while read cpid; do
            [[ "$cpid" == "$INSTANCE_ID" ]] && echo "$pane_ref" && break 2
          done
        done) || true
  else
    target=$(tmux list-panes -a -F '#{session_name}:#{window_index}.#{pane_index} #{pane_current_command}' 2>/dev/null \
      | grep -m1 ' claude$' \
      | cut -d' ' -f1) || true
  fi

  if [[ -z "$target" ]]; then
    log "Inject: no tmux pane running claude found"
    return
  fi

  # Capture the input prompt line from the bottom 6 lines of the pane.
  # The TUI prompt is "❯" (U+276F) followed by a non-breaking space (U+00A0),
  # so we match on the ❯ character alone and strip "❯<nbsp>" prefix.
  # Restrict to tail -6 to avoid matching ❯ in conversation scrollback.
  local prompt_line saved_text
  prompt_line=$(tmux capture-pane -t "$target" -p | tail -6 | grep -m1 '^❯' || true)
  # Strip the prompt prefix: ❯ followed by non-breaking space (U+00A0 = \xc2\xa0)
  saved_text=$(printf '%s' "$prompt_line" | sed "s/^❯$(printf '\xc2\xa0')//")
  # Trim trailing whitespace
  saved_text=$(printf '%s' "$saved_text" | sed 's/[[:space:]]*$//')

  if [[ -n "$saved_text" ]]; then
    log "Saving user input for restore: ${saved_text:0:60}"
    printf '%s' "$saved_text" > "$PENDING_RESTORE_FILE"

    # Clear the input with Ctrl+U (kill entire line — standard Unix binding)
    tmux send-keys -t "$target" C-u 2>/dev/null
    sleep 0.1
  fi

  # Pass slash commands through literally; otherwise invoke /workspace.
  # The UserPromptSubmit hook injects full workspace context on every prompt.
  local prompt
  if [[ "$message_content" == /* ]]; then
    prompt="$message_content"
  else
    prompt="/workspace"
  fi

  # Send text with -l (literal) to handle special chars, pause, then Enter.
  tmux send-keys -t "$target" -l "$prompt" 2>/dev/null && \
    sleep 0.2 && \
    tmux send-keys -t "$target" Enter 2>/dev/null && {
    _last_nudge=$now
    log "Injected to tmux pane $target: ${prompt:0:60}"

    # Schedule input restoration in background
    if [[ -s "$PENDING_RESTORE_FILE" ]]; then
      _restore_input_async "$target" &
    fi
  } || {
    log "Inject: tmux send-keys failed for $target"
  }
}

# Waits for Claude to finish processing, then restores saved input text.
# Runs as a background subshell so the main event loop isn't blocked.
_restore_input_async() {
  local target="$1"
  local max_wait=120  # seconds to wait before giving up
  local elapsed=0

  # First, wait a few seconds for Claude to start processing (prompt disappears)
  sleep 5

  # Then wait for the input prompt to reappear (❯ visible near bottom of pane),
  # which means Claude has finished and is ready for input again.
  while (( elapsed < max_wait )); do
    sleep 3
    elapsed=$((elapsed + 3))

    # Check if the prompt line is visible — indicates Claude is idle and waiting
    local has_prompt
    has_prompt=$(tmux capture-pane -t "$target" -p 2>/dev/null | tail -6 | grep -c '^❯' || true)

    if [[ "${has_prompt:-0}" -gt 0 ]] && [[ -s "$PENDING_RESTORE_FILE" ]]; then
      local restore_text
      restore_text=$(<"$PENDING_RESTORE_FILE")
      rm -f "$PENDING_RESTORE_FILE"

      # Small delay to let TUI fully settle
      sleep 0.5
      tmux send-keys -t "$target" -l "$restore_text" 2>/dev/null && {
        log "Restored user input: ${restore_text:0:60}"
      } || {
        log "Restore failed: tmux send-keys error"
      }
      return
    fi
  done

  # Timed out — clean up without restoring
  rm -f "$PENDING_RESTORE_FILE"
  log "Restore abandoned (timeout after ${max_wait}s)"
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
  # Remote mode: read token from Claude Code's credentials file
  if _is_remote; then
    log "Refreshing token from Claude Code credentials..."
    local cc_token
    cc_token=$(_cc_token) || {
      log "ERROR: Cannot read Powernode OAuth token from CC credentials. Reconnect via /mcp."
      return 1
    }
    echo -n "$cc_token" > "$TOKEN_FILE"
    log "Token refreshed from CC credentials (${#cc_token} chars)"
    return 0
  fi

  # Local mode: generate via rails runner
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
  # Remote mode: always read fresh from credentials (avoids stale tokens after OAuth rotation)
  if _is_remote; then
    local cc_token
    cc_token=$(_cc_token) || {
      # Fall back to cached file if credentials read fails
      if [[ -f "$TOKEN_FILE" && -s "$TOKEN_FILE" ]]; then
        cat "$TOKEN_FILE"
        return 0
      fi
      return 1
    }
    echo -n "$cc_token" > "$TOKEN_FILE"
    echo "$cc_token"
    return 0
  fi

  # Local mode: use cached file
  if [[ -f "$TOKEN_FILE" && -s "$TOKEN_FILE" ]]; then
    cat "$TOKEN_FILE"
  else
    return 1
  fi
}

# --- MCP Session Management ---
# In per-instance mode, the daemon reuses the session created by mcp-helper.sh
# (written to SESSION_FILE by mcp_ensure_session). No separate session needed.
# In remote mode, creates a session via HTTP initialize handshake.
# In shared mode (legacy), discovers the CLI's active session from the DB.
ensure_session() {
  # Reuse cached session if fresh (< 1 hour) AND not a placeholder "powernode-helper" session.
  # Placeholder sessions are created before the real Claude Code MCP client initializes —
  # they have the wrong identity and should be upgraded via re-discovery.
  if [[ -f "$SESSION_FILE" && -s "$SESSION_FILE" ]]; then
    local age
    age=$(( $(date +%s) - $(stat -c%Y "$SESSION_FILE") ))
    if (( age < 3600 )); then
      local cached_name
      cached_name=$(cat "$SESSION_NAME_FILE" 2>/dev/null)
      if [[ "$cached_name" != *"powernode-helper"* ]]; then
        return 0
      fi
      log "Upgrading placeholder 'powernode-helper' session — re-discovering real session"
    else
      log "Session file stale (${age}s old)"
    fi
  fi

  # Remote mode: discover existing session (created by Claude Code CLI)
  if _is_remote; then
    log "Remote mode — discovering CLI session via session/discover..."
    local token
    token=$(get_token) || { log "ERROR: No token for session discovery"; return 1; }

    local discover_payload='{"jsonrpc":"2.0","id":"discover-1","method":"session/discover","params":{}}'
    local discover_response
    discover_response=$(curl -sS -X POST \
      -H "Authorization: Bearer $token" \
      -H "Content-Type: application/json" \
      -H "Accept: application/json" \
      -d "$discover_payload" \
      "$SSE_ENDPOINT" 2>>"$LOG_FILE") || { log "ERROR: session/discover request failed"; return 1; }

    local picked
    picked=$(_pick_unclaimed_session "$discover_response" "${_PREFERRED_SESSION:-}") || {
      log "No unclaimed sessions available — waiting for CLI to connect"
      return 1
    }

    local session_token display_name discovered_agent_id
    IFS=$'\t' read -r session_token display_name discovered_agent_id <<< "$picked"

    if [[ -n "$session_token" && ${#session_token} -gt 10 ]]; then
      echo -n "$session_token" > "$SESSION_FILE"
      [[ -n "$display_name" ]] && echo -n "$display_name" > "$SESSION_NAME_FILE"
      if [[ -n "$discovered_agent_id" && "$discovered_agent_id" != "${AGENT_ID:-}" ]]; then
        log "Agent ID set from discover: ${AGENT_ID:-none} -> $discovered_agent_id"
        AGENT_ID="$discovered_agent_id"
      fi
      log "Discovered session: ${session_token:0:12}... (${display_name:-unknown})"
      return 0
    else
      log "ERROR: Session discovery returned invalid token"
      return 1
    fi
  fi

  # Local mode: check if stored session is still active via rails runner
  if [[ -f "$SESSION_FILE" && -s "$SESSION_FILE" ]]; then
    local existing
    existing=$(cat "$SESSION_FILE")
    local check_script
    check_script="s = McpSession.find_by(session_token: \"$existing\"); if s&.active?; print [\"active\", s.display_name || s.ai_agent&.name || \"MCP\"].join(\"\t\"); elsif s&.reactivatable?; s.reactivate!; print [\"active\", s.display_name || s.ai_agent&.name || \"MCP\"].join(\"\t\"); else; print \"expired\"; end"
    local result
    result=$(cd "$SERVER_DIR" && bin/rails runner "$check_script" 2>>"$LOG_FILE") || true
    if [[ "$result" == active* ]]; then
      local session_name
      IFS=$'\t' read -r _ session_name <<< "$result"
      [[ -n "$session_name" ]] && echo -n "$session_name" > "$SESSION_NAME_FILE"
      return 0
    fi
    log "Session ${existing:0:12}... expired"
  fi

  # Per-instance mode: actively discover session via HTTP (same as remote mode).
  # Previously this was a passive wait for mcp-helper.sh to write the session file,
  # but after removing the _mcp_create_session() fallback, nobody writes it during
  # reconnection. HTTP discovery works regardless of local/remote mode.
  if [[ -n "$INSTANCE_ID" ]]; then
    log "Per-instance mode — discovering session via HTTP..."

    # Refresh token from source (CC credentials or rails runner), then read it.
    # Don't rely on cached TOKEN_FILE — it may be stale after SSE disconnect.
    refresh_token || true
    local token
    token=$(get_token) || { log "ERROR: No token for session discovery"; return 1; }

    local discover_payload='{"jsonrpc":"2.0","id":"discover-pi","method":"session/discover","params":{}}'
    local discover_response
    discover_response=$(curl -sS -X POST \
      -H "Authorization: Bearer $token" \
      -H "Content-Type: application/json" \
      -H "Accept: application/json" \
      -d "$discover_payload" \
      "$SSE_ENDPOINT" 2>>"$LOG_FILE") || { log "ERROR: session/discover request failed"; return 1; }

    local picked
    picked=$(_pick_unclaimed_session "$discover_response" "${_PREFERRED_SESSION:-}") || {
      log "No unclaimed sessions available — waiting for CLI to connect"
      return 1
    }

    local session_token display_name discovered_agent_id
    IFS=$'\t' read -r session_token display_name discovered_agent_id <<< "$picked"

    if [[ -n "$session_token" && ${#session_token} -gt 10 ]]; then
      echo -n "$session_token" > "$SESSION_FILE"
      [[ -n "$display_name" ]] && echo -n "$display_name" > "$SESSION_NAME_FILE"
      if [[ -n "$discovered_agent_id" && "$discovered_agent_id" != "${AGENT_ID:-}" ]]; then
        log "Agent ID set from discover: ${AGENT_ID:-none} -> $discovered_agent_id"
        AGENT_ID="$discovered_agent_id"
      fi
      log "Discovered session: ${session_token:0:12}... (${display_name:-unknown})"
      return 0
    else
      log "ERROR: Session discovery returned invalid token"
      return 1
    fi
  fi

  # Shared mode fallback: find any active CLI session
  local session_script
  session_script=$(cat <<RUBY
session = McpSession.active
  .where(oauth_application_id: "$OAUTH_APP_ID")
  .order(last_activity_at: :desc)
  .first

session ||= McpSession.active
  .where(ai_agent_id: "$AGENT_ID")
  .order(last_activity_at: :desc)
  .first

if session
  agent_id = session.ai_agent_id || "$AGENT_ID"
  print [session.session_token, session.display_name || session.ai_agent&.name || "MCP", agent_id].join("\t")
end
RUBY
)

  local result
  result=$(cd "$SERVER_DIR" && bin/rails runner "$session_script" 2>>"$LOG_FILE") || true

  if [[ -n "$result" ]]; then
    local session_token session_name synced_agent_id
    IFS=$'\t' read -r session_token session_name synced_agent_id <<< "$result"
    echo -n "$session_token" > "$SESSION_FILE"
    echo -n "${session_name:-MCP}" > "$SESSION_NAME_FILE"
    if [[ -n "$synced_agent_id" && "$synced_agent_id" != "${AGENT_ID:-}" ]]; then
      log "Agent ID updated from session: ${AGENT_ID:-none} -> $synced_agent_id"
      AGENT_ID="$synced_agent_id"
    fi
    log "Sharing CLI session: ${session_token:0:12}... (${session_name})"
    return 0
  else
    log "No active CLI session found — waiting for CLI to connect"
    return 1
  fi
}

# --- Parent Process Monitor ---
# In per-instance mode, the daemon should exit when its parent Claude process dies.
_check_parent_alive() {
  [[ -z "$INSTANCE_ID" ]] && return 0  # Shared mode — no parent to check
  kill -0 "$INSTANCE_ID" 2>/dev/null && return 0
  log "Parent process $INSTANCE_ID is dead — daemon shutting down"
  return 1
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
  # All workspace messages arrive via the workspace channel broadcast. The python
  # processor detects if this agent is @mentioned (by ID or @Name in content) and
  # promotes event_type to 'mention' for downstream nudge decisions.
  local result
  result=$(python3 -c "
import json, sys
from datetime import datetime, timezone

raw = sys.argv[1]
event_type = sys.argv[2]
seen_file = sys.argv[3]
my_agent_id = sys.argv[4] if len(sys.argv) > 4 else ''

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

# Detect @mentions: check structured metadata and text @Name pattern.
# If this agent is mentioned, promote event_type to 'mention' so the daemon
# knows to nudge (for idle wake-up) vs quiet delivery (for active work).
effective_event = event_type
if my_agent_id and event_type in ('message_created', 'ai_response_complete'):
    metadata = msg.get('metadata', {}) or {}
    mentions = metadata.get('mentions') or msg.get('content_metadata', {}).get('mentions') or []
    mentioned = False
    if mentions:
        mentioned_ids = [str(m.get('id', '')) for m in mentions if isinstance(m, dict)]
        mentioned = my_agent_id in mentioned_ids
    if not mentioned and my_agent_id and content:
        # Text fallback: @AgentName pattern (agent name not available here,
        # but mentioned_agent_id in top-level is set by server for direct mentions)
        mentioned_id = str(d.get('mentioned_agent_id', '') or '')
        mentioned = mentioned_id == my_agent_id
    if mentioned:
        effective_event = 'mention'

entry = {
    'ts': datetime.now(timezone.utc).isoformat(),
    'event': effective_event,
    'workspace': workspace,
    'sender': sender,
    'content': content,
    'message_id': msg_id,
    'conversation_id': conv_id,
    'read': False
}

prefix = 'UPDATE:' if is_update else ''
print(prefix + json.dumps(entry))
" "$data" "$event_type" "$SEEN_FILE" "${AGENT_ID:-}" 2>>"$LOG_FILE") || return

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
    # Includes effective_event which may be 'mention' even when SSE event_type is 'message_created'
    local fields msg_id sender content effective_event
    fields=$(echo "$result" | python3 -c "
import sys, json
e = json.load(sys.stdin)
print(e.get('message_id','') + '\t' + e.get('sender','?') + '\t' + e.get('content','')[:120] + '\t' + e.get('event','message_created'))
" 2>/dev/null) || fields="?\t?\t?\tmessage_created"
    IFS=$'\t' read -r msg_id sender content effective_event <<< "$fields"
    [[ -n "$msg_id" ]] && mark_seen "$msg_id"
    log "EVENT [$effective_event] from $sender"

    # Desktop notification
    if command -v notify-send &>/dev/null; then
      local urgency="normal"
      [[ "$effective_event" == "mention" ]] && urgency="critical"
      notify-send -u "$urgency" -i dialog-information -a "Powernode" \
        "$sender" "$content" 2>/dev/null || true
    fi

    # Inject into Claude Code via tmux — only for @mentions and slash commands.
    # Regular messages are delivered quietly via the Stop hook (when Claude is
    # active) or UserPromptSubmit (on next user input). The status line shows
    # an unread count for passive awareness.
    local should_nudge=false
    if [[ "$sender" == *Claude\ Code* ]]; then
      : # Never nudge for our own messages (avoid loops)
    elif [[ "$effective_event" == "mention" ]]; then
      should_nudge=true  # @mentions still nudge (proactive for idle)
    elif [[ "$content" == /* ]]; then
      should_nudge=true  # Slash commands need literal tmux injection
    fi
    # Regular messages no longer nudge — delivered via Stop hook when active,
    # or via UserPromptSubmit when user next types. Status line shows unread count.

    if [[ "$should_nudge" == true ]]; then
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

  # Start curl in background via process substitution, capture its PID.
  # This allows _kill_orphan_curls to kill only THIS daemon's curl — not
  # other instances' connections (which caused cascading disconnects).
  exec 3< <(curl -sS -N \
    --max-time 0 \
    -H "Authorization: Bearer $token" \
    -H "Mcp-Session-Id: $session_id" \
    -H "Accept: text/event-stream" \
    -H "Cache-Control: no-cache" \
    "$SSE_ENDPOINT" 2>>"$LOG_FILE")
  _CURL_PID=$!

  {
    set +eo pipefail  # Disable errexit — process_sse_event may fail non-fatally
    local current_event="" current_data=""

    log "SSE read loop started (read timeout: ${SSE_READ_TIMEOUT}s, curl PID: $_CURL_PID)"

    while IFS= read -t "$SSE_READ_TIMEOUT" -r line; do
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

    log "SSE read loop exited (read timeout or EOF)"
  } <&3
  exec 3<&-
  local exit_code=$?

  # Kill only THIS daemon's curl process — not other instances' connections.
  _kill_orphan_curls

  log "SSE connection closed (exit: $exit_code) — will reconnect"
  return 1
}

_kill_orphan_curls() {
  # Kill only THIS daemon's curl process — not other instances' connections.
  # Previously used pgrep -f which matched ALL curl SSE processes system-wide,
  # causing cascading disconnects when one daemon's read loop timed out.
  if [[ -n "$_CURL_PID" ]] && kill -0 "$_CURL_PID" 2>/dev/null; then
    kill "$_CURL_PID" 2>/dev/null
    sleep 0.5
    kill -9 "$_CURL_PID" 2>/dev/null || true
    log "Killed own curl PID $_CURL_PID"
  fi
  _CURL_PID=""
}

# --- Daemon Loop ---
_run_daemon_loop() {
  trap '_cleanup' EXIT SIGTERM SIGINT

  # SIGHUP → reload: kill curl to break the SSE read loop, then reconnect
  # immediately (skip backoff). Useful for picking up new channel subscriptions
  # after a workspace team change without a full stop/start cycle.
  _RELOAD_REQUESTED=0
  trap '_RELOAD_REQUESTED=1; _kill_orphan_curls' SIGHUP

  local _PREFERRED_SESSION=""
  local _DIRECT_RETRY=0
  local backoff=1
  local last_token_refresh
  last_token_refresh=$(date +%s)

  while true; do
    # In per-instance mode, exit when parent Claude process dies
    _check_parent_alive || break

    # If no token available, poll with backoff until credentials appear
    if ! get_token >/dev/null 2>&1; then
      log "No token available — waiting for credentials (backoff: ${backoff}s)..."
      sleep "$backoff"
      backoff=$(( backoff * 2 ))
      (( backoff > MAX_BACKOFF )) && backoff=$MAX_BACKOFF
      continue
    fi

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
      _DIRECT_RETRY=0  # Reset direct reconnect counter on success
    else
      # After SSE disconnect, refresh token immediately instead of waiting
      # for the 30-minute periodic interval — the disconnect may be caused
      # by an expired token.
      log "SSE disconnected — refreshing token before reconnect..."
      if refresh_token; then
        last_token_refresh=$(date +%s)
        backoff=1  # Fresh token — reconnect quickly
        log "Token refreshed successfully after disconnect"
      else
        log "Token refresh failed — will retry on next iteration"
      fi

      # If SIGHUP triggered this disconnect, skip backoff and reconnect immediately
      if [[ "$_RELOAD_REQUESTED" -eq 1 ]]; then
        _RELOAD_REQUESTED=0
        log "Reload requested — reconnecting immediately with fresh channels..."
        backoff=1
        _DIRECT_RETRY=0
        continue
      fi

      # Try direct reconnect with our known session first — the server will
      # reactivate the revoked session automatically when it receives the SSE
      # GET request. This avoids the TOCTOU race where multiple daemons all
      # delete their session files and call session/discover simultaneously,
      # potentially grabbing the same session.
      _PREFERRED_SESSION=$(cat "$SESSION_FILE" 2>/dev/null) || true
      _DIRECT_RETRY=$(( ${_DIRECT_RETRY:-0} + 1 ))

      if [[ -n "$_PREFERRED_SESSION" && $_DIRECT_RETRY -le 3 ]]; then
        log "Direct reconnect attempt $_DIRECT_RETRY/3 with ${_PREFERRED_SESSION:0:12}..."
        # Keep session file intact — run_sse_loop will use the existing session
        sleep "$backoff"
        backoff=$(( backoff * 2 ))
        (( backoff > MAX_BACKOFF )) && backoff=$MAX_BACKOFF
        continue
      fi

      # Either no preferred session or 3 direct attempts failed — rediscover
      _DIRECT_RETRY=0
      rm -f "$SESSION_FILE"
      log "Cleared session for rediscovery, reconnecting in ${backoff}s..."
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
  rm -f "$PID_FILE" "$SESSION_NAME_FILE" "$SEEN_FILE"
  # Kill orphan curl SSE connections
  _kill_orphan_curls
  # Kill all children
  kill 0 2>/dev/null || true
  log "Daemon stopped"
}

# --- Daemon Control ---
start_daemon() {
  # Cross-caller mutual exclusion — prevents concurrent bootstrap from
  # mcp-sse-autostart, workspace-messages, or manual invocation.
  # Uses fd 200 (distinct from fd 9 in mcp-sse-autostart.sh) but the SAME
  # lock file path for cross-caller coordination.
  local LOCK_FILE="/tmp/powernode_sse_daemon_${INSTANCE_ID:-shared}.lock"
  exec 200>"$LOCK_FILE"
  if ! flock -n 200; then
    log_and_echo "Daemon startup already in progress (another caller holds lock)"
    return 0
  fi

  if is_running; then
    log_and_echo "Daemon already running (PID: $(cat "$PID_FILE"))"
    exec 200>&-
    return 0
  fi

  log_and_echo "Starting workspace SSE daemon..."

  # Clean stale session claim files — remove claims from dead PIDs, not just old files.
  # This prevents a dead Claude Code instance from permanently "claiming" a session.
  for f in /tmp/powernode_mcp_session_*.txt; do
    [[ -f "$f" ]] || continue
    [[ "$f" == *name* ]] && continue  # skip name files
    local claim_pid
    claim_pid=$(basename "$f" | sed 's/powernode_mcp_session_//;s/\.txt//')
    if [[ "$claim_pid" =~ ^[0-9]+$ ]] && ! kill -0 "$claim_pid" 2>/dev/null; then
      rm -f "$f" "/tmp/powernode_mcp_session_name_${claim_pid}.txt"
      log "Cleaned stale claim from dead PID $claim_pid"
    fi
  done
  # Also clean very old files as safety net
  find /tmp -maxdepth 1 -name 'powernode_mcp_session_*' -mmin +1440 -delete 2>/dev/null || true
  find /tmp -maxdepth 1 -name 'powernode_mcp_session_name_*' -mmin +1440 -delete 2>/dev/null || true

  # Try to get a token — if unavailable, daemon launches anyway and polls for credentials
  if [[ ! -f "$TOKEN_FILE" ]] || [[ ! -s "$TOKEN_FILE" ]]; then
    log_and_echo "No token found, refreshing..."
    refresh_token || log_and_echo "No token yet — daemon will poll for credentials"
  fi

  # Try to discover session — non-blocking, daemon loop will retry with backoff
  ensure_session || log_and_echo "No session yet — daemon will retry with backoff"

  # Launch daemon in background via setsid + nohup (propagate POWERNODE_URL for remote mode).
  # setsid gives the daemon its own process group (PGID = daemon PID), so that
  # _cleanup's `kill 0` and stop_daemon's `kill -- -PID` only affect the daemon
  # and its children — NOT the parent Claude Code session.
  INSTANCE_ID="$INSTANCE_ID" POWERNODE_URL="$PLATFORM_URL" setsid nohup "$0" _daemon >> "$LOG_FILE" 2>&1 &
  local daemon_pid=$!
  disown "$daemon_pid" 2>/dev/null || true
  echo "$daemon_pid" > "$PID_FILE"

  # Release lock now that PID file is written — other callers will see is_running() = true
  exec 200>&-

  log_and_echo "Daemon started (PID: $daemon_pid)"
  log_and_echo "  Inbox:   $INBOX_FILE"
  log_and_echo "  Log:     $LOG_FILE"
  log_and_echo "  Session: $(cat "$SESSION_FILE" 2>/dev/null | head -c 12)..."
}

stop_daemon() {
  if ! is_running; then
    log_and_echo "Daemon is not running"
    rm -f "$PID_FILE"
    # No global pkill — other daemons' curls are their own business.
    # The process group kill below handles this daemon's children.
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

  rm -f "$PID_FILE"
  log_and_echo "Daemon stopped"
}

is_running() {
  [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null
}

reload_daemon() {
  if ! is_running; then
    log_and_echo "Daemon is not running — nothing to reload"
    return 1
  fi

  local pid
  pid=$(cat "$PID_FILE")
  log_and_echo "Sending SIGHUP to daemon (PID: $pid)..."
  kill -HUP "$pid" 2>/dev/null
  log_and_echo "Reload signal sent — daemon will reconnect with fresh channels"
}

show_status() {
  if [[ -n "$INSTANCE_ID" ]]; then
    _show_instance_status
  else
    _show_discovery_status
  fi
}

# Single-instance status — used when INSTANCE_ID is set (normal hook invocation)
_show_instance_status() {
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

# Discovery mode — scans all instances when invoked without INSTANCE_ID (manual CLI use)
_show_discovery_status() {
  echo "=== Workspace SSE Daemon — Multi-Instance Status ==="
  echo ""

  local found=0

  # Scan all per-instance PID files
  for pid_file in /tmp/powernode_sse_daemon_*.pid; do
    [[ -f "$pid_file" ]] || continue
    found=$((found + 1))

    local instance_id daemon_pid
    instance_id=$(basename "$pid_file" | sed 's/powernode_sse_daemon_//;s/\.pid//')
    daemon_pid=$(cat "$pid_file" 2>/dev/null)

    local daemon_status="DEAD"
    [[ -n "$daemon_pid" ]] && kill -0 "$daemon_pid" 2>/dev/null && daemon_status="RUNNING"

    local parent_status="DEAD"
    [[ "$instance_id" =~ ^[0-9]+$ ]] && kill -0 "$instance_id" 2>/dev/null && parent_status="ALIVE"

    echo "Instance $instance_id:"
    echo "  Daemon:  $daemon_status (PID: ${daemon_pid:-?})"
    echo "  Parent:  $parent_status (Claude PID: $instance_id)"

    local inbox_file="/tmp/powernode_workspace_inbox_${instance_id}.jsonl"
    local session_file="/tmp/powernode_mcp_session_${instance_id}.txt"
    local log_file="/tmp/powernode_sse_daemon_${instance_id}.log"

    local inbox_count=0 unread=0
    if [[ -f "$inbox_file" ]]; then
      inbox_count=$(wc -l < "$inbox_file")
      unread=$(grep -c '"read": false' "$inbox_file" 2>/dev/null || true)
    fi
    echo "  Inbox:   $inbox_count events (${unread:-0} unread)"
    echo "  Session: $(cat "$session_file" 2>/dev/null | head -c 16 || echo 'none')..."

    if [[ -f "$log_file" ]]; then
      echo "  Last log: $(tail -1 "$log_file" 2>/dev/null | head -c 100)"
    fi

    # Flag anomalies
    if [[ "$daemon_status" == "RUNNING" && "$parent_status" == "DEAD" ]]; then
      echo "  ⚠ ORPHAN: daemon running but parent Claude is dead — will self-terminate"
    fi
    if [[ "$daemon_status" == "DEAD" && "$parent_status" == "ALIVE" ]]; then
      echo "  ⚠ MISSING: Claude is alive but has no daemon — restart with: INSTANCE_ID=$instance_id $0 start"
    fi

    echo ""
  done

  # Detect orphan daemons not tracked by any PID file
  local tracked_pids=""
  for pid_file in /tmp/powernode_sse_daemon_*.pid; do
    [[ -f "$pid_file" ]] || continue
    local p
    p=$(cat "$pid_file" 2>/dev/null)
    [[ -n "$p" ]] && tracked_pids="$tracked_pids $p"
  done

  local orphan_count=0
  while IFS= read -r opid; do
    [[ -z "$opid" ]] && continue
    if [[ " $tracked_pids " != *" $opid "* ]]; then
      if [[ "$orphan_count" -eq 0 ]]; then
        echo "ORPHAN DAEMONS (not tracked by any PID file):"
      fi
      orphan_count=$((orphan_count + 1))
      echo "  PID $opid — kill with: kill $opid"
    fi
  done < <(pgrep -f "workspace-sse-daemon.sh _daemon" 2>/dev/null || true)
  [[ "$orphan_count" -gt 0 ]] && echo ""

  # Shared token file status
  if [[ -f "$TOKEN_FILE" ]]; then
    local token_age
    token_age=$(( $(date +%s) - $(stat -c%Y "$TOKEN_FILE" 2>/dev/null) ))
    echo "Shared token: $TOKEN_FILE ($(stat -c%s "$TOKEN_FILE" 2>/dev/null || echo 0) bytes, ${token_age}s old)"
  else
    echo "Shared token: NOT FOUND"
  fi

  if [[ "$found" -eq 0 && "$orphan_count" -eq 0 ]]; then
    echo "No daemon instances found."
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
  reload)
    reload_daemon
    ;;
  refresh)
    refresh_token && echo "Token refreshed" || echo "Token refresh failed"
    ;;
  _daemon)
    # Internal: called by start_daemon via nohup
    _run_daemon_loop
    ;;
  *)
    echo "Usage: $0 {start|stop|reload|status|tail|refresh}"
    exit 1
    ;;
esac
