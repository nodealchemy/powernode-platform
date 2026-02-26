#!/usr/bin/env bash
# SSE Bridge + Powernode MCP Smoke Test
# Validates the full chain: daemon → token → session → MCP tools → SSE stream
#
# Usage:
#   ./scripts/sse-mcp-smoke.sh              # Quick smoke (~15s, 17 checks)
#   ./scripts/sse-mcp-smoke.sh --full       # Extended (~45s, adds MCP phases 1,3)
#   ./scripts/sse-mcp-smoke.sh --with-ping  # Wait 35s for SSE keepalive ping
#
# Reuses:
#   .claude/hooks/mcp-helper.sh      — mcp_token(), mcp_session(), mcp_call()
#   scripts/mcp-smoke-test.sh        — Phase 0 introspection (9 tools)
#   .claude/hooks/workspace-sse-daemon.sh — PID/log file locations

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ─────────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────────
PLATFORM_URL="${POWERNODE_URL:-http://localhost:3000}"
API_URL="${PLATFORM_URL}/api/v1"
MCP_ENDPOINT="${PLATFORM_URL}/api/v1/mcp/message"

PID_FILE="/tmp/powernode_sse_daemon.pid"
LOG_FILE="/tmp/powernode_sse_daemon.log"
TOKEN_FILE="/tmp/powernode_mcp_token.txt"
SESSION_FILE="/tmp/powernode_sse_session.txt"
IDS_CACHE_FILE="/tmp/powernode_sse_ids_cache.txt"

# Parse flags
FULL_MODE=false
WITH_PING=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --full)      FULL_MODE=true; shift ;;
    --with-ping) WITH_PING=true; shift ;;
    -h|--help)   head -12 "$0" | tail -10; exit 0 ;;
    *)           echo "Unknown option: $1"; exit 1 ;;
  esac
done

# ─────────────────────────────────────────────────
# Counters & Helpers
# ─────────────────────────────────────────────────
TOTAL_PASS=0
TOTAL_FAIL=0

pass() {
  local label="$1"
  local detail="${2:-}"
  TOTAL_PASS=$((TOTAL_PASS + 1))
  if [[ -n "$detail" ]]; then
    echo "  PASS  $label — $detail"
  else
    echo "  PASS  $label"
  fi
}

fail() {
  local label="$1"
  local detail="${2:-}"
  TOTAL_FAIL=$((TOTAL_FAIL + 1))
  if [[ -n "$detail" ]]; then
    echo "  FAIL  $label — $detail"
  else
    echo "  FAIL  $label"
  fi
}

# ─────────────────────────────────────────────────
# Banner
# ─────────────────────────────────────────────────
echo "============================================="
echo "  SSE Bridge + MCP Smoke Test"
echo "============================================="
echo "  Platform:  $PLATFORM_URL"
echo "  Mode:      $(if $FULL_MODE; then echo "full"; else echo "quick"; fi)"
echo ""

# ─────────────────────────────────────────────────
# Layer 1 — Infrastructure (4 checks)
# ─────────────────────────────────────────────────
echo "--- Layer 1: Infrastructure (4 checks) ---"

# 1.1 Backend health
HEALTH=$(curl -s --max-time 5 "${API_URL}/health" 2>/dev/null || true)
if echo "$HEALTH" | jq -r '.data.status' 2>/dev/null | grep -q "healthy"; then
  pass "Backend health" "$(echo "$HEALTH" | jq -r '.data.status' 2>/dev/null)"
else
  fail "Backend health" "not responding at ${API_URL}/health"
  echo ""
  echo "  ABORT: Backend must be running. Start with:"
  echo "    sudo systemctl start powernode-backend@default"
  echo ""
  echo "  PASS: $TOTAL_PASS  FAIL: $TOTAL_FAIL"
  exit 1
fi

# 1.2 Daemon process alive
if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
  pass "Daemon process" "PID $(cat "$PID_FILE")"
else
  fail "Daemon process" "not running (start with: .claude/hooks/workspace-sse-daemon.sh start)"
fi

# 1.3 Daemon log recency (< 5 min old)
if [[ -f "$LOG_FILE" ]]; then
  LOG_AGE=$(( $(date +%s) - $(stat -c%Y "$LOG_FILE") ))
  if (( LOG_AGE < 300 )); then
    pass "Daemon log recency" "${LOG_AGE}s old"
  else
    fail "Daemon log recency" "${LOG_AGE}s old (>300s stale)"
  fi
else
  fail "Daemon log recency" "log file missing"
fi

# 1.4 State files exist
MISSING_FILES=""
for f in "$TOKEN_FILE" "$SESSION_FILE" "$IDS_CACHE_FILE"; do
  if [[ ! -f "$f" || ! -s "$f" ]]; then
    MISSING_FILES="$MISSING_FILES $(basename "$f")"
  fi
done
if [[ -z "$MISSING_FILES" ]]; then
  pass "State files" "token, session, IDs cache all present"
else
  fail "State files" "missing:$MISSING_FILES"
fi

echo ""

# ─────────────────────────────────────────────────
# Layer 2 — Auth Chain (3 checks)
# ─────────────────────────────────────────────────
echo "--- Layer 2: Auth Chain (3 checks) ---"

# Source mcp-helper for token/session functions
# Temporarily disable errexit — mcp-helper sets it
set +e
source "$PROJECT_DIR/.claude/hooks/mcp-helper.sh" 2>/dev/null
set -eo pipefail

# 2.1 Token acquisition
TOKEN=""
TOKEN=$(mcp_token 2>/dev/null) || true
if [[ -n "$TOKEN" && ${#TOKEN} -gt 10 ]]; then
  pass "Token acquisition" "${TOKEN:0:8}... (${#TOKEN} chars)"
else
  fail "Token acquisition" "mcp_token() returned empty/short"
  echo ""
  echo "  ABORT: Cannot proceed without a valid token."
  echo ""
  echo "  PASS: $TOTAL_PASS  FAIL: $TOTAL_FAIL"
  exit 1
fi

# 2.2 Session retrieval
SESSION=""
SESSION=$(mcp_session 2>/dev/null) || true
if [[ -n "$SESSION" ]]; then
  pass "Session retrieval" "${SESSION:0:12}..."
else
  fail "Session retrieval" "mcp_session() returned empty"
fi

# 2.3 Token validity via JSON-RPC ping
PING_PAYLOAD=$(python3 -c "
import json
print(json.dumps({
    'jsonrpc': '2.0',
    'id': 1,
    'method': 'ping',
    'params': {}
}))
" 2>/dev/null)

PING_RESP=$(curl -sS --max-time 5 \
  -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H "Mcp-Session-Id: ${SESSION:-none}" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -d "$PING_PAYLOAD" \
  "$MCP_ENDPOINT" 2>/dev/null) || true

# A successful ping returns a JSON-RPC response without an error
PING_ERR=$(echo "$PING_RESP" | jq -r '.error.code // empty' 2>/dev/null)
if [[ -z "$PING_ERR" && -n "$PING_RESP" ]]; then
  pass "Token validity (ping)" "JSON-RPC responded"
else
  fail "Token validity (ping)" "error: $(echo "$PING_RESP" | jq -r '.error.message // "no response"' 2>/dev/null)"
fi

echo ""

# ─────────────────────────────────────────────────
# Layer 3 — MCP Tool Calls (9 checks via mcp-smoke-test.sh --phase 0)
# ─────────────────────────────────────────────────
echo "--- Layer 3: MCP Tool Calls (9 checks) ---"

SMOKE_SCRIPT="$SCRIPT_DIR/mcp-smoke-test.sh"
if [[ ! -x "$SMOKE_SCRIPT" ]]; then
  echo "  WARN: $SMOKE_SCRIPT not found or not executable"
  echo "  Skipping MCP tool tests"
  TOTAL_FAIL=$((TOTAL_FAIL + 9))
else
  # Build phase list: always phase 0; --full adds 1,3
  PHASES="0"
  if $FULL_MODE; then
    PHASES="0,1,3"
  fi

  # Capture output and exit code
  SMOKE_OUTPUT=$(MCP_TOKEN="$TOKEN" "$SMOKE_SCRIPT" --phase "$PHASES" --skip-cleanup 2>&1) || true

  # Parse PASS/FAIL counts from the smoke test output (WARN counts as FAIL)
  SMOKE_PASS=$(echo "$SMOKE_OUTPUT" | grep -c '  PASS  ' || true)
  SMOKE_FAIL=$(echo "$SMOKE_OUTPUT" | grep -cE '  (FAIL|WARN)  ' || true)

  # Relay the tool-level results (indented)
  echo "$SMOKE_OUTPUT" | grep -E '^\s+(PASS|FAIL|WARN|SKIP)\s' | head -50

  TOTAL_PASS=$((TOTAL_PASS + SMOKE_PASS))
  TOTAL_FAIL=$((TOTAL_FAIL + SMOKE_FAIL))
  echo ""
  echo "  (Phase ${PHASES}: ${SMOKE_PASS} pass, ${SMOKE_FAIL} fail)"
fi

echo ""

# ─────────────────────────────────────────────────
# Layer 4 — SSE Connectivity (1 check)
# ─────────────────────────────────────────────────
echo "--- Layer 4: SSE Connectivity (1 check) ---"

SSE_TIMEOUT=5
if $WITH_PING; then
  SSE_TIMEOUT=35
  echo "  (--with-ping: waiting up to ${SSE_TIMEOUT}s for keepalive)"
fi

# Open SSE stream and capture output + HTTP status to temp files.
# ActionController::Live can take a moment to flush the first event, and
# `timeout` killing curl may lose buffered stdout — writing to a file avoids this.
SSE_TMPFILE=$(mktemp /tmp/sse-smoke-XXXXXX)
SSE_STATUS_FILE=$(mktemp /tmp/sse-smoke-status-XXXXXX)
trap "rm -f '$SSE_TMPFILE' '$SSE_STATUS_FILE'" EXIT

timeout "$SSE_TIMEOUT" curl -sS -N \
  -H "Authorization: Bearer $TOKEN" \
  -H "Mcp-Session-Id: ${SESSION:-none}" \
  -H "Accept: text/event-stream" \
  -H "Cache-Control: no-cache" \
  -o "$SSE_TMPFILE" \
  -w "%{http_code}" \
  "$MCP_ENDPOINT" > "$SSE_STATUS_FILE" 2>/dev/null || true

SSE_HTTP_CODE=$(cat "$SSE_STATUS_FILE" 2>/dev/null | tr -d '[:space:]')
SSE_OUTPUT=$(cat "$SSE_TMPFILE" 2>/dev/null || true)

# Check for event: open (initial handshake from stream action)
if echo "$SSE_OUTPUT" | grep -q "^event: open"; then
  if $WITH_PING; then
    # Also check for keepalive ping
    if echo "$SSE_OUTPUT" | grep -q "^event: ping"; then
      pass "SSE stream" "open + keepalive ping received"
    else
      pass "SSE stream" "open received (no ping within ${SSE_TIMEOUT}s)"
    fi
  else
    pass "SSE stream" "event: open received"
  fi
elif echo "$SSE_OUTPUT" | grep -q "^event:"; then
  # Got some event, just not "open" — partial success
  FIRST_EVENT=$(echo "$SSE_OUTPUT" | grep "^event:" | head -1)
  pass "SSE stream" "connected ($FIRST_EVENT)"
elif [[ "$SSE_HTTP_CODE" == "400" ]]; then
  fail "SSE stream" "HTTP 400 — session likely expired (restart daemon: .claude/hooks/workspace-sse-daemon.sh stop && .claude/hooks/workspace-sse-daemon.sh start)"
elif [[ "$SSE_HTTP_CODE" == "401" ]]; then
  fail "SSE stream" "HTTP 401 — token rejected"
elif [[ -n "$SSE_OUTPUT" ]]; then
  fail "SSE stream" "HTTP ${SSE_HTTP_CODE:-?} — unexpected response: ${SSE_OUTPUT:0:100}"
else
  fail "SSE stream" "no response within ${SSE_TIMEOUT}s (HTTP ${SSE_HTTP_CODE:-?})"
fi

# ─────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────
TOTAL=$((TOTAL_PASS + TOTAL_FAIL))

echo ""
echo "============================================="
echo "  SSE + MCP SMOKE TEST COMPLETE"
echo "============================================="
echo "  PASS: $TOTAL_PASS"
echo "  FAIL: $TOTAL_FAIL"
echo "  TOTAL: $TOTAL"
echo ""

if [[ $TOTAL_FAIL -gt 0 ]]; then
  echo "  STATUS: FAILURES DETECTED"
  exit 1
else
  echo "  STATUS: ALL PASSED"
  exit 0
fi
