#!/usr/bin/env bash
# Stop hook — checks workspace inbox after each Claude response.
# Outputs <workspace-messages> context if unread messages exist.

exec 0</dev/null  # Close stdin — don't block on tool_use JSON

CLAUDE_PID="${PPID}"
export CLAUDE_PID
source "$(cd "$(dirname "$0")" && pwd)/workspace-format-inbox.sh" || true
