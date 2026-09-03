#!/usr/bin/env bash
# sync-claude-agents.sh — regenerate the Claude Code subagent skeletons from
# platform Ai::Agent records (thin MCP bootstraps; see
# server/app/services/ai/claude_export/agent_skeleton_sync.rb).
#
# Usage:
#   scripts/sync-claude-agents.sh                    # CANONICAL set -> .claude/agents/powernode/ (committed)
#   ACCOUNT_ID=<uuid> scripts/sync-claude-agents.sh   # an account's OWN agents -> .claude/agents/powernode-local/ (ignored)
#   TARGET_DIR=<path> scripts/sync-claude-agents.sh   # override the output directory
# Freshness of the committed set is gated by scripts/check-claude-agents-fresh.sh.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVER="$REPO/server"
[ -d "$SERVER" ] || { echo "error: $SERVER not found" >&2; exit 1; }

cd "$SERVER"
bin/rails claude:sync_agents
