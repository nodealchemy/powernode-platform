#!/usr/bin/env bash
# Auto-gen header checker: walks docs/reference/auto/*.md and fails if any
# file's first 5 lines don't contain "<!-- AUTO-GENERATED" — the marker
# that says "do not hand-edit; regenerate via the listed command".
#
# README.md inside auto/ is exempt (it's the auto-gen INDEX, not auto-gen
# content itself).
#
# Exit codes:
#   0 — every auto-gen doc has the marker
#   1 — one or more missing marker
#   2 — script invocation error
#
# Run from platform root:
#   bash docs/.verify/check-auto-gen-headers.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
AUTO_ROOT="$PLATFORM_ROOT/docs/reference/auto"

if [ ! -d "$AUTO_ROOT" ]; then
  echo "ERROR: docs/reference/auto/ not found" >&2
  exit 2
fi

missing=0
total=0

while IFS= read -r mdfile; do
  base=$(basename "$mdfile")
  # Skip the auto-gen README.md (index, not auto-gen content)
  if [ "$base" = "README.md" ]; then
    continue
  fi
  total=$((total + 1))
  head -5 "$mdfile" | grep -q '<!-- AUTO-GENERATED'
  if [ $? -ne 0 ]; then
    echo "$mdfile: MISSING <!-- AUTO-GENERATED marker in first 5 lines"
    missing=$((missing + 1))
  fi
done < <(find "$AUTO_ROOT" -name '*.md' -type f)

echo
echo "------------------------------------------"
echo "  scanned: $total auto-gen docs"
echo "  missing: $missing markers"
echo "------------------------------------------"

if [ "$missing" -gt 0 ]; then
  exit 1
fi
exit 0
