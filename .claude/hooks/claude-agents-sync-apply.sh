#!/bin/bash
# Stop hook — consumes this session's agent-sync marker and regenerates the
# Claude Code agent skeletons in the BACKGROUND (a Rails boot exceeds the hook
# budget). Never blocks; writes ONLY under .claude/agents/powernode*/ (that is
# all `rails claude:sync_agents` touches). The canonical set goes to
# .claude/agents/powernode/ — if the regeneration changed a committed file,
# scripts/check-claude-agents-fresh.sh (pattern-validation) is what tells you.

SESSION_ID="${CLAUDE_SESSION_ID:-$$}"
MARKER="/tmp/powernode_claude_agents_sync_${SESSION_ID}.marker"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-/opt/powernode}"

[[ ! -f "$MARKER" ]] && exit 0
rm -f "$MARKER"

[[ -x "$PROJECT_DIR/scripts/sync-claude-agents.sh" ]] || exit 0

(
  cd "$PROJECT_DIR" || exit 1
  env -u BUNDLE_GEMFILE -u ACCOUNT_ID -u INCLUDE_ACCOUNT -u TARGET_DIR \
    POWERNODE_INCLUDE_PRIVATE_EXTENSIONS=0 POWERNODE_DEPLOYED=0 \
    bash scripts/sync-claude-agents.sh >/dev/null 2>&1
) &

echo "⟳ Regenerating Claude Code agent skeletons in background (rails claude:sync_agents)" >&2
exit 0
