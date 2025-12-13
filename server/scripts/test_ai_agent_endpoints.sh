#!/bin/bash
# Test AI Agent endpoints after controller fixes

TOKEN="eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIwMTk5YjBmNi0xYTY5LTc2ZjYtOWU3ZC04NWYyMmQ0ZjQ0MDUiLCJhY2NvdW50X2lkIjoiMDE5OWIwZjYtMTg5MC03YWJlLWE2YzAtMTRmNzAzZjQ4NmNjIiwiZW1haWwiOiJhZG1pbkBwb3dlcm5vZGUub3JnIiwicGVybWlzc2lvbl92ZXJzaW9uIjoiOTFlYWJkZGEiLCJ2ZXJzaW9uIjoyLCJ0eXBlIjoiYWNjZXNzIiwiZXhwIjoxNzU5NjMxODY2LCJpYXQiOjE3NTk2MzA5NjYsImp0aSI6IjZkODJhMDEwOWVmYjhlMTZiMTgzZjRiYmFlNWUxNzgxIiwidmVyc2lvbiI6Mn0.fRmkNJ1huyy6pQ1g4kOKrADff6pq8MlV6MmZhnE2mbI"
AGENT_ID="0199b1da-1f5b-7ffa-8b11-c295285e1911"

echo "==========================================="
echo "TEST 1: AI Agent Stats Endpoint"
echo "==========================================="
curl -s -H "Authorization: Bearer ${TOKEN}" \
  "http://localhost:3000/api/v1/ai/agents/${AGENT_ID}/stats?period=30" | jq '.'

echo ""
echo "==========================================="
echo "TEST 2: AI Agent Update Endpoint"
echo "==========================================="
curl -s -X PATCH \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"agent": {"name": "Topic Research Agent", "agent_type": "content_generator"}}' \
  "http://localhost:3000/api/v1/ai/agents/${AGENT_ID}" | jq '.'
