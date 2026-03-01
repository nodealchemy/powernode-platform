#!/bin/bash
# Convert relative imports to path aliases for better maintainability
#
# ONLY converts cross-boundary imports:
#   ../../../shared/utils       → @/shared/utils
#   ../../features/other-feat/  → @/features/other-feat/
#
# PRESERVES feature-internal imports:
#   ./components/Foo            → unchanged (same directory)
#   ../hooks/useFoo             → unchanged (same feature)

set -eo pipefail

echo "📦 Relative Import Conversion - Path Alias Migration"
echo "===================================================="
echo ""

SRC_ROOT="frontend/src"

if [ ! -d "$SRC_ROOT" ]; then
  echo "❌ Directory $SRC_ROOT not found. Run from project root."
  exit 1
fi

echo "📋 Finding files with relative imports..."

TOTAL_FILES=0
TOTAL_CONVERSIONS=0

# Get the absolute path of SRC_ROOT for realpath resolution
ABS_SRC_ROOT=$(realpath "$SRC_ROOT")

# Process each TypeScript/TSX file (excluding tests and node_modules)
while IFS= read -r -d '' file; do
  [ -f "$file" ] || continue

  file_dir=$(dirname "$file")
  file_conversions=0

  # Determine this file's top-level feature (e.g., "ai", "supply-chain", "admin")
  file_rel="${file#$SRC_ROOT/}"
  file_top_feature=""
  if [[ "$file_rel" == features/* ]]; then
    # Extract: features/ai/audit/pages/Foo.tsx → ai
    file_top_feature=$(echo "$file_rel" | cut -d'/' -f2)
  fi

  # Collect all relative imports from this file
  # Match: from './...' or from "../..."
  while IFS= read -r import_line; do
    # Extract the import path between quotes
    import_path=$(echo "$import_line" | sed -n "s/.*from ['\"]\\([^'\"]*\\)['\"].*/\\1/p")

    # Skip non-relative imports
    [[ "$import_path" == .* ]] || continue

    # Resolve the import path to an absolute filesystem path, then make it relative to SRC_ROOT
    resolved=$(realpath -sm "$file_dir/$import_path" 2>/dev/null) || continue
    resolved_rel="${resolved#$ABS_SRC_ROOT/}"

    # Skip if resolution didn't produce a path under SRC_ROOT
    [[ "$resolved_rel" == /* ]] && continue
    [[ "$resolved_rel" == "$resolved" ]] && continue

    # Determine if this import should be aliased
    new_import=""

    if [[ "$resolved_rel" == shared/* ]]; then
      # Any import resolving to shared/ gets aliased
      new_import="@/$resolved_rel"
    elif [[ "$resolved_rel" == features/* ]]; then
      # Extract the top-level feature of the import target
      import_top_feature=$(echo "$resolved_rel" | cut -d'/' -f2)

      if [ -n "$file_top_feature" ] && [ "$file_top_feature" != "$import_top_feature" ]; then
        # Cross-feature import → alias it
        new_import="@/$resolved_rel"
      elif [ -z "$file_top_feature" ]; then
        # File is NOT in features/ but imports from features/ → alias it
        new_import="@/$resolved_rel"
      fi
      # Same top-level feature → leave relative
    fi

    # Apply the conversion
    if [ -n "$new_import" ]; then
      # Escape special regex characters in both paths for sed
      escaped_old=$(printf '%s\n' "$import_path" | sed 's/[[\\/.*^$()+?{|]/\\&/g')
      escaped_new=$(printf '%s\n' "$new_import" | sed 's/[[\\/.*^$()+?{|]/\\&/g')

      # Replace only in from-string context, preserving quote style
      sed -i "s|from '${escaped_old}'|from '${escaped_new}'|g; s|from \"${escaped_old}\"|from \"${escaped_new}\"|g" "$file"
      file_conversions=$((file_conversions + 1))
    fi
  done < <(grep -E "from ['\"][.]{1,2}/" "$file" 2>/dev/null || true)

  if [ "$file_conversions" -gt 0 ]; then
    echo "  ✅ $file ($file_conversions conversions)"
    TOTAL_FILES=$((TOTAL_FILES + 1))
    TOTAL_CONVERSIONS=$((TOTAL_CONVERSIONS + file_conversions))
  fi
done < <(find "$SRC_ROOT" \( -name "*.tsx" -o -name "*.ts" \) ! -path "*/node_modules/*" ! -name "*.test.*" ! -name "*.spec.*" -print0)

echo ""
echo "✨ Import Conversion Complete!"
echo "=============================="
echo "Files modified: $TOTAL_FILES"
echo "Total conversions: $TOTAL_CONVERSIONS"
echo ""

# Verify: count remaining cross-boundary relative imports
echo "🔍 Checking for remaining cross-boundary relative imports..."
REMAINING=0
while IFS= read -r -d '' file; do
  [ -f "$file" ] || continue

  file_dir=$(dirname "$file")
  file_rel="${file#$SRC_ROOT/}"
  file_top_feature=""
  if [[ "$file_rel" == features/* ]]; then
    file_top_feature=$(echo "$file_rel" | cut -d'/' -f2)
  fi

  while IFS= read -r import_line; do
    import_path=$(echo "$import_line" | sed -n "s/.*from ['\"]\\([^'\"]*\\)['\"].*/\\1/p")
    [[ "$import_path" == .* ]] || continue

    resolved=$(realpath -sm "$file_dir/$import_path" 2>/dev/null) || continue
    resolved_rel="${resolved#$ABS_SRC_ROOT/}"
    [[ "$resolved_rel" == /* ]] && continue
    [[ "$resolved_rel" == "$resolved" ]] && continue

    if [[ "$resolved_rel" == shared/* ]]; then
      REMAINING=$((REMAINING + 1))
    elif [[ "$resolved_rel" == features/* ]]; then
      import_top_feature=$(echo "$resolved_rel" | cut -d'/' -f2)
      if [ -n "$file_top_feature" ] && [ "$file_top_feature" != "$import_top_feature" ]; then
        REMAINING=$((REMAINING + 1))
      fi
    fi
  done < <(grep -E "from ['\"][.]{1,2}/" "$file" 2>/dev/null || true)
done < <(find "$SRC_ROOT" \( -name "*.tsx" -o -name "*.ts" \) ! -path "*/node_modules/*" ! -name "*.test.*" ! -name "*.spec.*" -print0)

echo "Remaining cross-boundary relative imports: $REMAINING"

if [ "$REMAINING" -gt 0 ]; then
  echo ""
  echo "⚠️  Some cross-boundary imports could not be auto-converted."
  echo "Run with manual review for complex cases."
fi

echo ""
echo "✅ Import consistency improved!"
echo ""
echo "📝 Note: Run 'cd frontend && npx tsc --noEmit' to verify all imports resolve correctly"
