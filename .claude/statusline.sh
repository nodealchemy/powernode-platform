#!/usr/bin/env bash
# Powernode status line for Claude Code
# Displays: [Model] | ctx% | $cost

set -euo pipefail

read -r MODEL CTX COST < <(
  jq -r '[
    (.model.display_name // "Unknown"),
    (.context_window.used_percentage // 0 | floor),
    (.cost.total_cost_usd // 0)
  ] | @tsv' 2>/dev/null || echo "Unknown 0 0"
)

if (( CTX >= 90 )); then
  CTX_COLOR="\033[31m"
elif (( CTX >= 70 )); then
  CTX_COLOR="\033[33m"
else
  CTX_COLOR="\033[32m"
fi

OUTPUT=$(printf "[%s] | %b%d%%\033[0m ctx | \$%s" \
  "$MODEL" "$CTX_COLOR" "$CTX" "$COST")

PLAIN=$(printf "[%s] | %d%% ctx | \$%s" "$MODEL" "$CTX" "$COST")

printf '%s' "$OUTPUT"

TMUX_FILE="/tmp/claude-status-tmux-${PPID}"
printf '%s' "$PLAIN" > "$TMUX_FILE"
