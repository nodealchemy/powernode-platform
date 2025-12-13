#!/bin/bash

TOKEN="eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIwMTk5YjBmNi0xYTY5LTc2ZjYtOWU3ZC04NWYyMmQ0ZjQ0MDUiLCJhY2NvdW50X2lkIjoiMDE5OWIwZjYtMTg5MC03YWJlLWE2YzAtMTRmNzAzZjQ4NmNjIiwiZW1haWwiOiJhZG1pbkBwb3dlcm5vZGUub3JnIiwicGVybWlzc2lvbl92ZXJzaW9uIjoiOTFlYWJkZGEiLCJ2ZXJzaW9uIjoyLCJ0eXBlIjoiYWNjZXNzIiwiZXhwIjoxNzU5NjMxODY2LCJpYXQiOjE3NTk2MzA5NjYsImp0aSI6IjZkODJhMDEwOWVmYjhlMTZiMTgzZjRiYmFlNWUxNzgxIiwidmVyc2lvbiI6Mn0.fRmkNJ1huyy6pQ1g4kOKrADff6pq8MlV6MmZhnE2mbI"

echo "Triggering stats endpoint..."
curl -s -H "Authorization: Bearer ${TOKEN}" \
  "http://localhost:3000/api/v1/ai/agents/0199b1da-1f5b-7ffa-8b11-c295285e1911/stats?period=30" >/dev/null

echo "Checking logs for error..."
tail -100 /home/rett/Drive/Projects/powernode-platform/server/log/development.log | \
  grep -B 10 -A 10 "NoMethodError\|undefined method\|ERROR -- :"
