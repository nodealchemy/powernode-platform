#!/usr/bin/env bash
# Read-only MCP-action checker: walks every .md under docs/, extracts every
# MCP action **call site** (pattern: `platform.<action>(`), and verifies
# each against the platform's tool registry at
# server/app/services/ai/tools/platform_api_tool_registry.rb.
#
# Only extracts call-site invocations. Prose mentions like "the
# system_create_node action" are NOT checked — they're hand-curated and
# would generate too many false positives.
#
# Lines inside markdown blockquotes (`> `) or shell-comment lines (`#`) or
# JS-comment lines (`//`) are skipped — those are aspirational annotations.
#
# Aspirational actions documented in docs/.verify/ASPIRATIONAL_MCP.md are
# expected unknowns; this script reports all unknowns and reviewers
# cross-check against the catalog.
#
# Exit codes:
#   0 — all referenced call-site actions exist, OR registry unreachable
#   1 — one or more referenced actions are unknown to the registry
#   2 — script invocation error
#
# Run from platform root:
#   bash docs/.verify/check-mcp-actions.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DOCS_ROOT="$PLATFORM_ROOT/docs"
REGISTRY="$PLATFORM_ROOT/server/app/services/ai/tools/platform_api_tool_registry.rb"

if [ ! -f "$REGISTRY" ]; then
  echo "WARN: tool registry not found at $REGISTRY" >&2
  echo "WARN: skipping MCP action verification (best-effort)." >&2
  exit 0
fi

echo "Registry: $REGISTRY"

known_actions=$(mktemp)
found_actions=$(mktemp)
missing_actions=$(mktemp)
trap 'rm -f "$known_actions" "$found_actions" "$missing_actions"' EXIT

# Extract registered action names from registry. We capture every quoted
# string that looks like an action identifier (snake_case, lowercase). The
# registry uses these as the keys in the action_definitions hash.
grep -oE '"([a-z][a-z0-9_]+)"' "$REGISTRY" 2>/dev/null \
  | tr -d '"' | sort -u > "$known_actions"

action_count=$(wc -l < "$known_actions" 2>/dev/null | tr -d ' ')
[ -z "$action_count" ] && action_count=0
echo "  $action_count candidate identifiers in registry"

# Extract call-site references from docs: `platform.<action>(` pattern.
# Skip:
#   - blockquote lines (`> `)
#   - JS-style comments (`//`)
#   - shell-style comments inside fenced blocks (very approximate)
#   - .verify/ directory (this script and ASPIRATIONAL_MCP.md reference action names in tables)
find "$DOCS_ROOT" -name '*.md' -type f \
  -not -path "$DOCS_ROOT/.verify/*" \
  -print0 \
  | xargs -0 grep -vhE '^[[:space:]]*(//|>)' 2>/dev/null \
  | grep -ohE 'platform\.[a-z][a-z0-9_]+\(' 2>/dev/null \
  | sed 's/^platform\.//; s/($//' \
  | sort -u > "$found_actions"

found_count=$(wc -l < "$found_actions" 2>/dev/null | tr -d ' ')
[ -z "$found_count" ] && found_count=0
echo "  $found_count distinct call-site actions in docs"

comm -23 "$found_actions" "$known_actions" 2>/dev/null > "$missing_actions"
missing_count=$(wc -l < "$missing_actions" 2>/dev/null | tr -d ' ')
[ -z "$missing_count" ] && missing_count=0

if [ "$missing_count" -gt 0 ]; then
  echo
  echo "UNKNOWN actions (referenced via platform.X() but not in registry):"
  while IFS= read -r action; do
    [ -z "$action" ] && continue
    echo "  $action"
    grep -rln "platform\.${action}(" "$DOCS_ROOT" 2>/dev/null \
      | grep -v "$DOCS_ROOT/.verify/" \
      | head -3 \
      | sed 's/^/    referenced in: /'
  done < "$missing_actions"
fi

echo
echo "------------------------------------------"
echo "  known:    $action_count candidate identifiers"
echo "  refed:    $found_count"
echo "  unknown:  $missing_count"
echo "------------------------------------------"

if [ "$missing_count" -gt 0 ]; then
  echo "Cross-check unknowns against docs/.verify/ASPIRATIONAL_MCP.md."
  exit 1
fi
exit 0
