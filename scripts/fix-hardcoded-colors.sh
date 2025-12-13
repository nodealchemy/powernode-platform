#!/bin/bash
# Fix hardcoded Tailwind colors with theme-aware classes
# This script converts hardcoded color classes to theme classes for proper dark mode support

echo "🎨 Hardcoded Colors Cleanup - Theme System Fix"
echo "=============================================="
echo ""

# Color mappings from hardcoded to theme classes
declare -A COLOR_MAP=(
  # Text colors
  ["text-gray-600"]="text-theme-muted"
  ["text-gray-700"]="text-theme-secondary"
  ["text-gray-800"]="text-theme-primary"
  ["text-gray-900"]="text-theme-primary"
  ["text-gray-500"]="text-theme-muted"
  ["text-gray-400"]="text-theme-muted/70"
  ["text-black"]="text-theme-primary"

  # Success/Green
  ["text-green-600"]="text-theme-success"
  ["text-green-500"]="text-theme-success"
  ["text-green-700"]="text-theme-success"
  ["bg-green-100"]="bg-theme-success/10"
  ["bg-green-500"]="bg-theme-success"
  ["bg-green-600"]="bg-theme-success"
  ["border-green-500"]="border-theme-success"

  # Error/Red
  ["text-red-600"]="text-theme-danger"
  ["text-red-500"]="text-theme-danger"
  ["text-red-700"]="text-theme-danger"
  ["bg-red-100"]="bg-theme-danger/10"
  ["bg-red-500"]="bg-theme-danger"
  ["bg-red-600"]="bg-theme-danger"
  ["border-red-500"]="border-theme-danger"

  # Warning/Orange/Yellow
  ["text-orange-600"]="text-theme-warning"
  ["text-orange-500"]="text-theme-warning"
  ["text-yellow-600"]="text-theme-warning"
  ["bg-orange-100"]="bg-theme-warning/10"
  ["bg-yellow-100"]="bg-theme-warning/10"
  ["bg-orange-500"]="bg-theme-warning"
  ["border-orange-500"]="border-theme-warning"

  # Info/Blue
  ["text-blue-600"]="text-theme-info"
  ["text-blue-500"]="text-theme-info"
  ["text-blue-700"]="text-theme-info"
  ["bg-blue-100"]="bg-theme-info/10"
  ["bg-blue-500"]="bg-theme-info"
  ["bg-blue-600"]="bg-theme-info"
  ["border-blue-500"]="border-theme-info"

  # Purple (map to interactive primary)
  ["text-purple-600"]="text-theme-interactive-primary"
  ["text-purple-500"]="text-theme-interactive-primary"
  ["bg-purple-100"]="bg-theme-interactive-primary/10"
  ["bg-purple-500"]="bg-theme-interactive-primary"
  ["border-purple-500"]="border-theme-interactive-primary"

  # Background colors
  ["bg-gray-100"]="bg-theme-surface"
  ["bg-gray-50"]="bg-theme-surface"
  ["bg-gray-200"]="bg-theme-border"
  ["bg-gray-800"]="bg-theme-surface"
  ["bg-gray-900"]="bg-theme-background"

  # Border colors
  ["border-gray-300"]="border-theme"
  ["border-gray-200"]="border-theme"
  ["border-gray-400"]="border-theme"
)

# Find all TypeScript/TSX files in frontend (exclude node_modules and test files)
echo "📋 Finding files with hardcoded colors..."
FILES=$(find frontend/src -name "*.tsx" -o -name "*.ts" | grep -v "node_modules" | grep -v "\.test\.")

if [ -z "$FILES" ]; then
  echo "No files found!"
  exit 1
fi

TOTAL_FILES=0
TOTAL_REPLACEMENTS=0

# Process each file
for file in $FILES; do
  if [ ! -f "$file" ]; then
    continue
  fi

  FILE_CHANGES=0

  # Check if file has any hardcoded colors
  if grep -qE "(text|bg|border)-(red|green|blue|yellow|orange|purple|gray|black)-[0-9]" "$file" 2>/dev/null; then
    # Apply each color mapping
    for old_color in "${!COLOR_MAP[@]}"; do
      new_color="${COLOR_MAP[$old_color]}"

      # Count occurrences before replacement
      before=$(grep -o "$old_color" "$file" 2>/dev/null | wc -l)

      if [ "$before" -gt 0 ]; then
        # Replace the color (but NOT text-white which is allowed on colored backgrounds)
        sed -i "s/${old_color}/${new_color}/g" "$file"
        FILE_CHANGES=$((FILE_CHANGES + before))
        TOTAL_REPLACEMENTS=$((TOTAL_REPLACEMENTS + before))
      fi
    done

    if [ "$FILE_CHANGES" -gt 0 ]; then
      echo "  ✅ $file ($FILE_CHANGES replacements)"
      TOTAL_FILES=$((TOTAL_FILES + 1))
    fi
  fi
done

echo ""
echo "✨ Color Fix Complete!"
echo "====================="
echo "Files modified: $TOTAL_FILES"
echo "Total replacements: $TOTAL_REPLACEMENTS"
echo ""

# Verify remaining hardcoded colors
echo "🔍 Checking for remaining hardcoded colors..."
REMAINING=$(grep -rE "(text|bg|border)-(red|green|blue|yellow|orange|purple|gray|black)-[0-9]" frontend/src/ \
  --include="*.tsx" --include="*.ts" \
  | grep -v "text-white" \
  | grep -v "\.test\." \
  | wc -l)

echo "Remaining hardcoded colors: $REMAINING"

if [ "$REMAINING" -gt 0 ]; then
  echo ""
  echo "Files with remaining hardcoded colors (may need manual review):"
  grep -rlE "(text|bg|border)-(red|green|blue|yellow|orange|purple|gray|black)-[0-9]" frontend/src/ \
    --include="*.tsx" --include="*.ts" \
    | grep -v "\.test\." \
    | head -20
  echo ""
  echo "💡 Some colors may require manual mapping to appropriate theme classes"
fi

echo ""
echo "✅ Theme system integrity improved!"
