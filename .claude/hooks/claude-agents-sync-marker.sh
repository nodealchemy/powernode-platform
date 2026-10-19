#!/bin/bash
# PostToolUse hook (Edit|Write) — marks the Claude Code agent skeletons for
# regeneration when their SOURCE changed during this session. Since C4 the
# committed .claude/agents/powernode/*.md are the thin loaders of the canonical
# roster: a pure function of Ai::Agents::CanonicalRoster and
# Ai::ClaudeExport::ThinLoader (no seed or agent row reaches them), so an edit
# to either — or to the exporter — is the moment they go stale. Marker consumed
# by the Stop hook (claude-agents-sync-apply.sh). Same pattern as
# service-restart-marker/apply.

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

[[ -z "$FILE_PATH" ]] && exit 0

case "$FILE_PATH" in
  */server/app/services/ai/agents/canonical_roster.rb|*/server/app/services/ai/claude_export/*.rb) ;;
  *) exit 0 ;;
esac

SESSION_ID="${CLAUDE_SESSION_ID:-$$}"
MARKER="/tmp/powernode_claude_agents_sync_${SESSION_ID}.marker"

if [[ ! -f "$MARKER" ]]; then
  touch "$MARKER"
  echo "⟳ Claude Code agent skeletons will be regenerated at end of response (seed changed)" >&2
fi

exit 0
