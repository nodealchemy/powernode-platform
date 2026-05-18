#!/usr/bin/env bash
# Read-only link checker: walks every .md under docs/ plus root meta files
# (README.md, CLAUDE.md, CONTRIBUTING.md, CODE_OF_CONDUCT.md, SECURITY.md),
# extracts every [text](path) reference, and verifies the resolved path
# exists on disk.
#
# Skips:
#   - URLs (http/https/mailto/ftp/tel)
#   - Anchor-only links (#section)
#   - docs/history/** (archived; may reference deleted paths intentionally)
#   - docs/reference/auto/** (auto-generated; refreshed nightly)
#   - docs/_consolidation-map.json + docs/_redirects.json
#   - extensions/** (submodule territory; own harnesses)
#
# Exit codes:
#   0 — all links resolve
#   1 — one or more broken links found
#   2 — script invocation error
#
# Output format:
#   <file>:<line>: BROKEN -> <target>
#
# Run from platform root:
#   bash docs/.verify/check-links.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DOCS_ROOT="$PLATFORM_ROOT/docs"

if [ ! -d "$DOCS_ROOT" ]; then
  echo "ERROR: docs/ not found at $DOCS_ROOT" >&2
  exit 2
fi

broken=0
total_links=0
total_files=0

# Build file list: docs/ (excluding history/, reference/auto/, .verify/)
# + root meta files
mdfiles=$(mktemp)
trap 'rm -f "$mdfiles"' EXIT

find "$DOCS_ROOT" -name '*.md' -type f \
  -not -path "$DOCS_ROOT/history/*" \
  -not -path "$DOCS_ROOT/reference/auto/*" \
  -not -path "$DOCS_ROOT/.verify/*" \
  > "$mdfiles"

for root_meta in README.md CLAUDE.md CONTRIBUTING.md CODE_OF_CONDUCT.md SECURITY.md CHANGELOG.md; do
  if [ -f "$PLATFORM_ROOT/$root_meta" ]; then
    echo "$PLATFORM_ROOT/$root_meta" >> "$mdfiles"
  fi
done

while IFS= read -r mdfile; do
  [ -z "$mdfile" ] && continue
  total_files=$((total_files + 1))
  dir="$(dirname "$mdfile")"
  lineno=0

  while IFS= read -r line; do
    lineno=$((lineno + 1))
    # Strip inline code spans (backtick-quoted) — they're literal text,
    # not links. Avoids false positives in docs that describe link syntax.
    stripped_line=$(echo "$line" | sed -E 's/`[^`]*`//g')
    # Extract [text](path) pairs from the stripped line
    matches=$(echo "$stripped_line" | grep -oE '\[[^]]+\]\([^)]+\)' || true)
    [ -z "$matches" ] && continue
    while IFS= read -r match; do
      [ -z "$match" ] && continue
      # Extract the (path) part
      path=$(echo "$match" | sed -E 's/^\[[^]]+\]\(//; s/\)$//')
      # Skip URLs and special schemes
      case "$path" in
        http://*|https://*|mailto:*|ftp://*|tel:*|"#"*) continue ;;
      esac
      # Strip anchor fragment for resolution
      target="${path%%#*}"
      [ -z "$target" ] && continue
      # Skip paths into submodule territory — those have their own harness
      case "$target" in
        extensions/*|*/extensions/*) continue ;;
      esac
      total_links=$((total_links + 1))
      # Resolve relative paths against the file's directory
      if [[ "$target" == /* ]]; then
        echo "$mdfile:$lineno: ABSOLUTE -> $target (use relative paths)"
        broken=$((broken + 1))
        continue
      fi
      resolved="$dir/$target"
      if [ ! -e "$resolved" ]; then
        echo "$mdfile:$lineno: BROKEN -> $target"
        broken=$((broken + 1))
      fi
    done <<< "$matches"
  done < "$mdfile"
done < "$mdfiles"

echo
echo "------------------------------------------"
echo "  scanned: $total_files files / $total_links links"
echo "  broken:  $broken"
echo "------------------------------------------"

if [ "$broken" -gt 0 ]; then
  exit 1
fi
exit 0
