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
# Lines inside markdown blockquotes (`> `) or JS-comment lines (`//`) are
# skipped — those are aspirational annotations. NOT `#` lines: this header
# claimed they were for a long time and the code never did it, and adding it
# would REDUCE coverage (a `#` line in a fenced shell block is a real call site
# a reader would copy). Measured 2026-09-10: zero call sites in docs/ sit
# behind any of these prefixes, so the filters hide nothing today.
#
# Aspirational actions documented in docs/.verify/ASPIRATIONAL_MCP.md are
# EXPECTED unknowns and this script now READS that catalog (IMP-01a05ec2).
# Before, it only told the reader to go and cross-check by hand, so it exited 1
# on every single run — two catalogued actions (cost_analysis, recent_events)
# are real MCP verbs the running server exposes that a static grep of the
# registry cannot see. The CI step is advisory, so that never failed a
# workflow; it did something quieter and worse. A step that is red every time
# is one nobody reads, and a genuinely NEW unknown just moved the count from 2
# to 3 inside an already-failing step. The point of subtracting the catalog is
# to restore a GREEN BASELINE, so that red means something again.
#
# Exit codes:
#   0 — every unknown is catalogued as aspirational, OR registry unreachable
#   1 — one or more referenced actions are unknown AND not catalogued
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
all_unknown=$(mktemp)
allowlisted=$(mktemp)
expected_actions=$(mktemp)
stale_actions=$(mktemp)
trap 'rm -f "$known_actions" "$found_actions" "$missing_actions" "$all_unknown" "$allowlisted" "$expected_actions" "$stale_actions"' EXIT

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

comm -23 "$found_actions" "$known_actions" 2>/dev/null > "$all_unknown"

# The aspirational catalog, read rather than merely pointed at. Its table rows
# lead with the action in backticks: `| `cost_analysis` | doc | note |`. Only
# the FIRST cell is taken, so a note mentioning another verb cannot silently
# widen the allowlist.
ASPIRATIONAL="$SCRIPT_DIR/ASPIRATIONAL_MCP.md"
if [ -f "$ASPIRATIONAL" ]; then
  grep -oE '^\|[[:space:]]*`[a-z][a-z0-9_]+`' "$ASPIRATIONAL" 2>/dev/null \
    | tr -d '|` ' | sort -u > "$allowlisted"
else
  : > "$allowlisted"
fi

# Unknown AND not catalogued — the only thing that fails this check.
comm -23 "$all_unknown" "$allowlisted" 2>/dev/null > "$missing_actions"
# Unknown AND catalogued — reported, never fatal.
comm -12 "$all_unknown" "$allowlisted" 2>/dev/null > "$expected_actions"
# Catalogued but not referenced anywhere any more. An allowlist nobody
# re-examines rots into a permanent exemption for a doc that has moved on, so
# name it — the same failure this check exists to catch, one level up.
comm -13 "$all_unknown" "$allowlisted" 2>/dev/null > "$stale_actions"

missing_count=$(wc -l < "$missing_actions" 2>/dev/null | tr -d ' ')
[ -z "$missing_count" ] && missing_count=0
expected_count=$(wc -l < "$expected_actions" 2>/dev/null | tr -d ' ')
[ -z "$expected_count" ] && expected_count=0
stale_count=$(wc -l < "$stale_actions" 2>/dev/null | tr -d ' ')
[ -z "$stale_count" ] && stale_count=0

report_actions() {
  while IFS= read -r action; do
    [ -z "$action" ] && continue
    echo "  $action"
    grep -rln "platform\.${action}(" "$DOCS_ROOT" 2>/dev/null \
      | grep -v "$DOCS_ROOT/.verify/" \
      | head -3 \
      | sed 's/^/    referenced in: /'
  done < "$1"
}

if [ "$missing_count" -gt 0 ]; then
  echo
  echo "UNKNOWN actions (referenced via platform.X() but in neither the registry"
  echo "nor docs/.verify/ASPIRATIONAL_MCP.md):"
  report_actions "$missing_actions"
fi

# Printed even though they pass: an expected unknown that stops being expected
# should be visible BEFORE it becomes a failure, and a silent allowlist is one
# nobody revisits.
if [ "$expected_count" -gt 0 ]; then
  echo
  echo "EXPECTED unknowns (catalogued in ASPIRATIONAL_MCP.md — not a failure):"
  report_actions "$expected_actions"
fi

if [ "$stale_count" -gt 0 ]; then
  echo
  echo "STALE allowlist rows (in ASPIRATIONAL_MCP.md, no longer referenced by any doc —"
  echo "delete the row so the catalog keeps describing reality):"
  sed 's/^/  /' "$stale_actions"
fi

echo
echo "------------------------------------------"
echo "  known:     $action_count candidate identifiers"
echo "  refed:     $found_count"
echo "  expected:  $expected_count (catalogued)"
echo "  stale:     $stale_count (catalogued, unreferenced)"
echo "  unknown:   $missing_count"
echo "------------------------------------------"

if [ "$missing_count" -gt 0 ]; then
  echo "Either fix the doc, or add a row to docs/.verify/ASPIRATIONAL_MCP.md."
  exit 1
fi
exit 0
