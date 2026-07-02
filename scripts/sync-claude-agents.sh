#!/usr/bin/env bash
# sync-claude-agents.sh — regenerate .claude/agents/powernode/*.md skeletons from
# platform Ai::Agent records (thin MCP bootstraps; see
# server/app/services/ai/claude_export/agent_skeleton_sync.rb).
#
# Usage:
#   scripts/sync-claude-agents.sh                    # default account, default output dir
#   ACCOUNT_ID=<uuid> scripts/sync-claude-agents.sh   # override the account
#   TARGET_DIR=<path> scripts/sync-claude-agents.sh   # override the output directory
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVER="$REPO/server"
[ -d "$SERVER" ] || { echo "error: $SERVER not found" >&2; exit 1; }

cd "$SERVER"
bin/rails claude:sync_agents
