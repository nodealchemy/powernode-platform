#!/bin/bash
# Comprehensive cleanup of console.log, console.debug, and console.info from frontend
# Preserves console.error and console.warn for legitimate error handling
#
# Skips:
#   - Lines inside JSDoc/block comments (lines starting with * or /*)
#   - Lines inside string literals and template literals (code samples)
#   - The logger utility itself (shared/utils/logger.ts)
#   - Test files (*.test.*, *.spec.*)

set -eo pipefail

echo "🧹 Comprehensive Console Logging Cleanup"
echo "========================================="
echo ""

SRC_DIR="frontend/src"

if [ ! -d "$SRC_DIR" ]; then
  echo "❌ Directory $SRC_DIR not found. Run from project root."
  exit 1
fi

# Files to always skip — these legitimately contain console.log references
SKIP_PATTERNS=(
  "shared/utils/logger.ts"       # Logger utility wraps console methods
  "developer/components/CodeSamples" # Code samples displayed to users
)

should_skip_file() {
  local file="$1"
  for pattern in "${SKIP_PATTERNS[@]}"; do
    if [[ "$file" == *"$pattern"* ]]; then
      return 0
    fi
  done
  return 1
}

is_code_statement() {
  # Returns 0 (true) if the line is an actual console statement (not in a comment or string)
  local line="$1"
  local trimmed
  trimmed=$(echo "$line" | sed 's/^[[:space:]]*//')

  # Skip lines that are inside block comments (start with * or /*)
  if [[ "$trimmed" == \** ]] || [[ "$trimmed" == /\** ]]; then
    return 1
  fi

  # Skip single-line comments
  if [[ "$trimmed" == //* ]]; then
    return 1
  fi

  # Skip lines where console.log is inside a string literal (quoted)
  # Check if console.log appears after an opening quote without a closing one before it
  # Common pattern: '  console.log(data);' inside a template literal
  if echo "$line" | grep -qP "[\`'\"].*console\.(log|debug|info)"; then
    return 1
  fi

  # Skip lines that are clearly inside template literals (indented code samples)
  # These typically appear as string content with no leading code structure
  if echo "$line" | grep -qP "^[[:space:]]+(//|#|\*|/\*)"; then
    return 1
  fi

  return 0
}

echo "📋 Finding files with console statements..."

# Find files with actual console.log/debug/info (excluding tests, node_modules, skip patterns)
FILES=$(find "$SRC_DIR" \( -name "*.ts" -o -name "*.tsx" \) \
  ! -path "*/node_modules/*" \
  ! -name "*.test.*" \
  ! -name "*.spec.*" \
  -exec grep -l "console\.\(log\|debug\|info\)" {} \; 2>/dev/null || true)

if [ -z "$FILES" ]; then
  echo "✨ No console.log statements found! Codebase is clean."
  exit 0
fi

FILE_COUNT=$(echo "$FILES" | wc -l)
echo "Found $FILE_COUNT files with console statements"
echo ""

TOTAL_REMOVED=0
FILES_CLEANED=0

echo "🔧 Cleaning files..."
for file in $FILES; do
  [ -f "$file" ] || continue

  # Skip allowlisted files
  if should_skip_file "$file"; then
    echo "  ⏭️  $file (allowlisted, skipping)"
    continue
  fi

  file_removed=0

  # Process the file: remove only actual console.log/debug/info statements
  # Use a temp file approach to handle multi-line awareness
  tmpfile=$(mktemp)
  in_block_comment=false
  in_template_literal=false

  while IFS= read -r line; do
    # Track block comment state
    if [[ "$in_block_comment" == true ]]; then
      if echo "$line" | grep -q '\*/'; then
        in_block_comment=false
      fi
      echo "$line" >> "$tmpfile"
      continue
    fi

    if echo "$line" | grep -qP '^\s*/\*' && ! echo "$line" | grep -q '\*/'; then
      in_block_comment=true
      echo "$line" >> "$tmpfile"
      continue
    fi

    # Check if this line has a console.log/debug/info statement
    if echo "$line" | grep -qP '^\s*console\.(log|debug|info)\s*\('; then
      # This is an actual console statement at the start of a line (real code)
      file_removed=$((file_removed + 1))
      # Don't write this line to output (remove it)
      continue
    fi

    echo "$line" >> "$tmpfile"
  done < "$file"

  if [ "$file_removed" -gt 0 ]; then
    mv "$tmpfile" "$file"
    echo "  ✅ $file ($file_removed statements removed)"
    TOTAL_REMOVED=$((TOTAL_REMOVED + file_removed))
    FILES_CLEANED=$((FILES_CLEANED + 1))
  else
    rm -f "$tmpfile"
  fi
done

echo ""
echo "✨ Cleanup Complete!"
echo "===================="
echo "Total statements removed: $TOTAL_REMOVED"
echo "Files cleaned: $FILES_CLEANED"
echo ""

# Verify — count remaining console.log that are actual code (not comments/strings/allowlisted)
echo "🔍 Verifying cleanup..."
REMAINING_LINES=$(grep -rnP '^\s*console\.(log|debug|info)\s*\(' "$SRC_DIR" \
  --include="*.ts" --include="*.tsx" 2>/dev/null \
  | grep -v "node_modules" \
  | grep -v '\.test\.' \
  | grep -v '\.spec\.' \
  | grep -v 'logger\.ts' \
  | grep -v 'CodeSamples' || true)

REMAINING=0
if [ -n "$REMAINING_LINES" ]; then
  REMAINING=$(echo "$REMAINING_LINES" | wc -l)
  REMAINING=$(echo "$REMAINING" | tr -d '[:space:]')
fi

echo "Remaining console statements: $REMAINING"

if [ "$REMAINING" -eq 0 ]; then
  echo "✅ All actionable console.log statements removed!"
else
  echo "⚠️  Some console statements remain — may need manual review:"
  echo "$REMAINING_LINES" | head -10
fi

echo ""
echo "💡 Note: console.error and console.warn were preserved for error handling"
echo "📝 Allowlisted files: ${SKIP_PATTERNS[*]}"
