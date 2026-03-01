#!/bin/bash

TOKEN="eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIwMTk5YjBmNi0xYTY5LTc2ZjYtOWU3ZC04NWYyMmQ0ZjQ0MDUiLCJhY2NvdW50X2lkIjoiMDE5OWIwZjYtMTg5MC03YWJlLWE2YzAtMTRmNzAzZjQ4NmNjIiwiZW1haWwiOiJhZG1pbkBwb3dlcm5vZGUub3JnIiwicGVybWlzc2lvbl92ZXJzaW9uIjoiOTFlYWJkZGEiLCJ2ZXJzaW9uIjoyLCJ0eXBlIjoiYWNjZXNzIiwiZXhwIjoxNzU5NjMyNDI4LCJpYXQiOjE3NTk2MzE1MjgsImp0aSI6IjM2Y2Y3OTI5YzM0Y2M5MGYwYzczMTQ5YjU3ZDhkZTFkIiwidmVyc2lvbiI6Mn0.GercWvoDIwx61ti5rM3LYh0NfMNCWaw_9pS88p9xQHA"
AGENT_ID="0199b1da-1f5b-7ffa-8b11-c295285e1911"

echo "==========================================="
echo "TEST: Update Agent Model in Configuration"
echo "==========================================="
echo ""
echo "Updating agent with configuration.model = claude-sonnet-4-20250514"
echo ""

curl -s -X PATCH \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "agent": {
      "configuration": {
        "model": "claude-sonnet-4-20250514",
        "max_tokens": 2048,
        "temperature": 0.7
      }
    }
  }' \
  "http://localhost:3000/api/v1/ai/agents/${AGENT_ID}" | jq '.success, .data.agent.configuration'

echo ""
echo "==========================================="
echo "Verifying update in database..."
echo "==========================================="

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SERVER_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$SERVER_DIR" && rails runner "
agent = AiAgent.find('0199b1da-1f5b-7ffa-8b11-c295285e1911')
puts 'Model in configuration: ' + (agent.configuration['model'] || 'NOT SET')
puts 'Max tokens: ' + (agent.configuration['max_tokens']&.to_s || 'NOT SET')
puts 'Temperature: ' + (agent.configuration['temperature']&.to_s || 'NOT SET')
"
