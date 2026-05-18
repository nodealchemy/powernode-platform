#!/usr/bin/env bash
# Read-only code-reference checker: walks every .md under docs/ plus root
# meta files, extracts backtick-quoted path-shaped strings, and verifies
# the path exists on disk.
#
# Verifies platform paths:
#   - server/app/..., server/db/..., server/spec/..., server/lib/..., server/config/...
#   - frontend/src/..., frontend/e2e/...
#   - worker/app/..., worker/spec/..., worker/config/...
#   - scripts/...
#   - config/...
#   - docs/...
#   - extensions/<slug>/   (existence of the submodule directory only — contents are owned by the submodule's own harness)
#
# Skips:
#   - URLs
#   - Path strings containing spaces
#   - Paths inside submodules (extensions/<slug>/...) past the slug
#   - Paths with glob/wildcards (those have separate validation)
#
# Exit codes:
#   0 — all referenced code paths exist
#   1 — one or more references missing
#   2 — script invocation error
#
# Run from platform root:
#   bash docs/.verify/check-code-refs.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DOCS_ROOT="$PLATFORM_ROOT/docs"

if [ ! -d "$DOCS_ROOT" ]; then
  echo "ERROR: docs/ not found at $DOCS_ROOT" >&2
  exit 2
fi

total=0
missing=0

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
  in_legacy_section=0
  lineno=0
  while IFS= read -r line; do
    lineno=$((lineno + 1))
    # Toggle "legacy paths" mode when we cross into a section that lists
    # consolidated-away source files. These are intentional prose
    # references to deleted paths and should not be flagged.
    if echo "$line" | grep -qiE '^##+ *(Materials previously at|Previously at|Consolidates? content from|Sources?:|Replaces:)'; then
      in_legacy_section=1
      continue
    fi
    # Also flip into legacy mode when the line itself says "consolidates content from"
    if echo "$line" | grep -qiE 'consolidates content from|materials previously at|consolidated from:'; then
      in_legacy_section=1
      continue
    fi
    # Reset legacy mode on any new section header that isn't a "previously" variant
    if echo "$line" | grep -qE '^##+ [A-Z]'; then
      if ! echo "$line" | grep -qiE 'previously at|consolidates? content from|sources?:|replaces:'; then
        in_legacy_section=0
      fi
    fi
    [ "$in_legacy_section" = "1" ] && continue

    # Extract backtick-quoted content (`...`)
    ticks=$(echo "$line" | grep -oE '`[^`]+`' 2>/dev/null || true)
    [ -z "$ticks" ] && continue
    while IFS= read -r tickref; do
      [ -z "$tickref" ] && continue
      raw=$(echo "$tickref" | sed -E 's/^`//; s/`$//')
      # Strip trailing punctuation that's NOT a valid path char
      raw="${raw%[.,;:]}"
      # Heuristic: must contain a slash AND look like a path
      case "$raw" in
        */*) ;;
        *) continue ;;
      esac
      case "$raw" in
        http*|https*|mailto*) continue ;;
        *" "*) continue ;;
        # Skip glob patterns + brace expansion
        *\**|*\?*|*\{*|*\[*) continue ;;
        # Skip placeholder paths containing <var> syntax
        *\<*\>*) continue ;;
      esac
      # Resolve candidate
      target=""
      case "$raw" in
        server/*|frontend/*|worker/*|scripts/*|config/*|docs/*|initramfs/*)
          target="$PLATFORM_ROOT/$raw"
          ;;
        extensions/*)
          # Only check the submodule directory exists, not inner files
          # (those are owned by the submodule's own harness)
          ext_root=$(echo "$raw" | cut -d/ -f1-2)
          target="$PLATFORM_ROOT/$ext_root"
          ;;
        app/services/*|app/models/*|app/controllers/*|app/jobs/*|app/serializers/*|app/channels/*|db/migrate/*|db/seeds/*|spec/*|lib/*)
          target="$PLATFORM_ROOT/server/$raw"
          ;;
        *)
          continue
          ;;
      esac
      total=$((total + 1))
      if [ ! -e "$target" ]; then
        echo "$mdfile:$lineno: MISSING -> $raw"
        missing=$((missing + 1))
      fi
    done <<< "$ticks"
  done < "$mdfile"
done < "$mdfiles"

echo
echo "------------------------------------------"
echo "  checked:  $total code references"
echo "  missing:  $missing"
echo "------------------------------------------"

if [ "$missing" -gt 0 ]; then
  exit 1
fi
exit 0
