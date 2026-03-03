#!/usr/bin/env bash
# UserPromptSubmit hook — delivers unread workspace messages as context.
#
# Timeout: 3s (runs on every prompt, must be fast)
# Output: stdout text injected into Claude's context
# No output = no context injected (clean no-op when no messages)
#
# Rules:
#   - Must NEVER exit non-zero (crashes Claude Code)
#   - Must not spawn background processes (FD inheritance → hangs)
#   - Stdin closed immediately (no blocking on pipe)

exec 0</dev/null  # Close stdin — don't block waiting for prompt JSON

CLAUDE_PID="${PPID}"
export CLAUDE_PID
source "$(cd "$(dirname "$0")" && pwd)/workspace-format-inbox.sh" || true
