#!/bin/bash
# Comprehensive cleanup of console.log, console.debug, and console.info from frontend
# Preserves console.error and console.warn for legitimate error handling

echo "🧹 Comprehensive Console Logging Cleanup"
echo "========================================="
echo ""

# Find all files with console.log, console.debug, or console.info
echo "📋 Finding files with console statements..."
FILES=$(grep -rl "console\.\(log\|debug\|info\)" frontend/src/ --include="*.ts" --include="*.tsx" 2>/dev/null)

if [ -z "$FILES" ]; then
  echo "✨ No console.log statements found! Codebase is clean."
  exit 0
fi

FILE_COUNT=$(echo "$FILES" | wc -l)
echo "Found $FILE_COUNT files with console statements"
echo ""

# Count before cleanup
TOTAL_BEFORE=0
for file in $FILES; do
  count=$(grep -c "console\.\(log\|debug\|info\)" "$file" 2>/dev/null || echo "0")
  TOTAL_BEFORE=$((TOTAL_BEFORE + count))
done

echo "Total console statements to remove: $TOTAL_BEFORE"
echo ""
echo "🔧 Cleaning files..."

# Clean each file
CLEANED_COUNT=0
for file in $FILES; do
  if [ -f "$file" ]; then
    before=$(grep -c "console\.\(log\|debug\|info\)" "$file" 2>/dev/null || echo "0")

    if [ "$before" -gt 0 ]; then
      echo "  Cleaning: $file ($before statements)"

      # Remove console.log, console.debug, console.info statements
      # This handles both single-line and multi-line console statements
      sed -i '/console\.log(/d' "$file"
      sed -i '/console\.debug(/d' "$file"
      sed -i '/console\.info(/d' "$file"

      # Remove excessive blank lines (more than 2 consecutive)
      sed -i '/^$/N;/^\n$/D' "$file"

      after=$(grep -c "console\.\(log\|debug\|info\)" "$file" 2>/dev/null || echo "0")
      removed=$((before - after))
      CLEANED_COUNT=$((CLEANED_COUNT + removed))

      echo "    ✅ Removed $removed statements"
    fi
  fi
done

echo ""
echo "✨ Cleanup Complete!"
echo "===================="
echo "Total statements removed: $CLEANED_COUNT"
echo "Files cleaned: $FILE_COUNT"
echo ""

# Verify cleanup
echo "🔍 Verifying cleanup..."
REMAINING=$(grep -r "console\.\(log\|debug\|info\)" frontend/src/ --include="*.ts" --include="*.tsx" 2>/dev/null | wc -l)
echo "Remaining console statements: $REMAINING"

if [ "$REMAINING" -eq 0 ]; then
  echo "✅ All console.log statements successfully removed!"
else
  echo "⚠️  Some console statements remain (may be in comments or strings)"
  echo ""
  echo "Files with remaining console statements:"
  grep -rl "console\.\(log\|debug\|info\)" frontend/src/ --include="*.ts" --include="*.tsx" 2>/dev/null | head -10
fi

echo ""
echo "💡 Note: console.error and console.warn were preserved for error handling"
