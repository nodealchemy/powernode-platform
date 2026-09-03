#!/bin/bash
# PostToolUse hook (Edit|Write) — marks the Claude Code agent skeletons for
# regeneration when a platform agent SEED changed during this session
# (server/db/seeds/** or extensions/*/server/db/seeds/**). The committed
# .claude/agents/powernode/*.md are generated from the canonical seeded agents,
# so a seed edit is the moment they go stale. Marker consumed by the Stop hook
# (claude-agents-sync-apply.sh). Same pattern as service-restart-marker/apply.

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

[[ -z "$FILE_PATH" ]] && exit 0

case "$FILE_PATH" in
  */server/db/seeds/*|*/server/db/seeds.rb) ;;
  *) exit 0 ;;
esac

SESSION_ID="${CLAUDE_SESSION_ID:-$$}"
MARKER="/tmp/powernode_claude_agents_sync_${SESSION_ID}.marker"

if [[ ! -f "$MARKER" ]]; then
  touch "$MARKER"
  echo "⟳ Claude Code agent skeletons will be regenerated at end of response (seed changed)" >&2
fi

exit 0
