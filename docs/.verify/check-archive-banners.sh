#!/usr/bin/env bash
# Archive banner checker: walks docs/history/**/*.md and fails if any
# file's first 10 lines don't contain "**ARCHIVED" (the agreed banner
# convention from Wave 1 D2).
#
# The banner is a load-bearing reader signal — without it, a snapshot doc
# could be mistaken for current guidance. README.md inside history/ is
# exempt (it's the archive INDEX, not an archived artifact).
#
# Exit codes:
#   0 — every history doc has a banner
#   1 — one or more missing banner
#   2 — script invocation error
#
# Run from platform root:
#   bash docs/.verify/check-archive-banners.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DOCS_ROOT="$PLATFORM_ROOT/docs"

if [ ! -d "$DOCS_ROOT/history" ]; then
  echo "ERROR: docs/history not found" >&2
  exit 2
fi

missing=0
total=0

while IFS= read -r mdfile; do
  base=$(basename "$mdfile")
  # Skip the archive index README.md — it's the INDEX, not an archive
  if [ "$base" = "README.md" ]; then
    continue
  fi
  total=$((total + 1))
  head -10 "$mdfile" | grep -q '\*\*ARCHIVED'
  if [ $? -ne 0 ]; then
    echo "$mdfile: MISSING **ARCHIVED banner in first 10 lines"
    missing=$((missing + 1))
  fi
done < <(find "$DOCS_ROOT/history" -name '*.md' -type f)

echo
echo "------------------------------------------"
echo "  scanned: $total history docs"
echo "  missing: $missing banners"
echo "------------------------------------------"

if [ "$missing" -gt 0 ]; then
  exit 1
fi
exit 0
