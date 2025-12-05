#!/bin/bash
# Convert relative imports to path aliases for better maintainability
# Converts: import ... from '../../../shared/utils'
# To:       import ... from '@/shared/utils'

echo "📦 Relative Import Conversion - Path Alias Migration"
echo "===================================================="
echo ""

# Path alias mappings
# @/ points to frontend/src/
declare -A IMPORT_PATTERNS=(
  ["../../../shared/"]="@/shared/"
  ["../../shared/"]="@/shared/"
  ["../shared/"]="@/shared/"
  ["../../../features/"]="@/features/"
  ["../../features/"]="@/features/"
  ["../features/"]="@/features/"
  ["../../components/"]="@/shared/components/"
  ["../components/"]="@/shared/components/"
)

# Find all TypeScript/TSX files
echo "📋 Finding files with relative imports..."
FILES=$(find frontend/src -name "*.tsx" -o -name "*.ts" | grep -v "node_modules" | grep -v "\.test\.")

if [ -z "$FILES" ]; then
  echo "No files found!"
  exit 1
fi

TOTAL_FILES=0
TOTAL_CONVERSIONS=0

# Process each file
for file in $FILES; do
  if [ ! -f "$file" ]; then
    continue
  fi

  FILE_CHANGES=0

  # Check if file has relative imports
  if grep -qE "from ['\"][.]{1,3}/" "$file" 2>/dev/null; then

    # Apply each import pattern conversion
    for old_pattern in "${!IMPORT_PATTERNS[@]}"; do
      new_pattern="${IMPORT_PATTERNS[$old_pattern]}"

      # Count occurrences before replacement
      before=$(grep -o "from ['\"]${old_pattern}" "$file" 2>/dev/null | wc -l)

      if [ "$before" -gt 0 ]; then
        # Replace the import pattern
        sed -i "s|from ['\"]${old_pattern}|from '${new_pattern}|g" "$file"
        sed -i "s|from ['\"]${old_pattern}|from \"${new_pattern}|g" "$file"
        FILE_CHANGES=$((FILE_CHANGES + before))
        TOTAL_CONVERSIONS=$((TOTAL_CONVERSIONS + before))
      fi
    done

    if [ "$FILE_CHANGES" -gt 0 ]; then
      echo "  ✅ $file ($FILE_CHANGES conversions)"
      TOTAL_FILES=$((TOTAL_FILES + 1))
    fi
  fi
done

echo ""
echo "✨ Import Conversion Complete!"
echo "=============================="
echo "Files modified: $TOTAL_FILES"
echo "Total conversions: $TOTAL_CONVERSIONS"
echo ""

# Verify remaining relative imports
echo "🔍 Checking for remaining relative imports..."
REMAINING=$(grep -rE "from ['\"]\.\./" frontend/src/ \
  --include="*.tsx" --include="*.ts" \
  | grep -v "node_modules" \
  | grep -v "\.test\." \
  | wc -l)

echo "Remaining relative imports: $REMAINING"

if [ "$REMAINING" -gt 0 ]; then
  echo ""
  echo "Files with remaining relative imports:"
  grep -rlE "from ['\"]\.\./" frontend/src/ \
    --include="*.tsx" --include="*.ts" \
    | grep -v "node_modules" \
    | grep -v "\.test\." \
    | head -20
  echo ""
  echo "💡 Some relative imports may need manual review for proper path mapping"
fi

echo ""
echo "✅ Import consistency improved!"
echo ""
echo "📝 Note: Run 'npm run typecheck' to verify all imports resolve correctly"
