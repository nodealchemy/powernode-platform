#!/usr/bin/env bash
# Powernode WebSocket Execution Monitor
# Subscribes to AiOrchestrationChannel for real-time execution events
# Usage: bash scripts/monitoring/ws-monitor.sh [token]
# Requires: wscat (npm install -g wscat)

set -eo pipefail

TOKEN="${1:-}"
WS_URL="${WS_URL:-ws://localhost:3000/cable}"

# Check dependencies
if ! command -v wscat &>/dev/null; then
  echo "Error: wscat is not installed. Install with: npm install -g wscat"
  exit 1
fi

if [ -z "$TOKEN" ]; then
  echo "Usage: $0 <jwt-token>"
  echo ""
  echo "Get a token with:"
  echo '  curl -s -X POST http://localhost:3000/api/v1/auth/login \'
  echo '    -H "Content-Type: application/json" \'
  echo '    -d "{\"email\":\"admin@powernode.org\",\"password\":\"...\"}" | jq -r ".data.token"'
  exit 1
fi

echo "Connecting to ${WS_URL}..."
echo "Subscribing to AiOrchestrationChannel..."
echo "Press Ctrl-C to disconnect."
echo "---"

# Connect and subscribe to the channel
wscat -c "${WS_URL}?token=${TOKEN}" \
  --execute "{\"command\":\"subscribe\",\"identifier\":\"{\\\"channel\\\":\\\"AiOrchestrationChannel\\\"}\"}" \
  2>&1 | while IFS= read -r line; do
    # Pretty-print JSON messages
    if echo "$line" | jq . 2>/dev/null; then
      :
    else
      echo "$line"
    fi
  done
