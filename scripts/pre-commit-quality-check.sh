#!/bin/bash
# Pre-commit hook for code quality enforcement
# Prevents commits that violate platform standards

echo "🔍 Running Pre-Commit Quality Checks..."
echo "======================================="

ERRORS=0

# Check 1: No console.log in production code
echo ""
echo "1️⃣  Checking for console.log statements..."
CONSOLE_LOGS=$(git diff --cached --name-only --diff-filter=ACM | \
  grep -E '\.(ts|tsx)$' | \
  xargs grep -l "console\.log\|console\.debug\|console\.info" 2>/dev/null | \
  xargs grep -v "process.env.NODE_ENV === 'development'" 2>/dev/null | \
  xargs grep -v "\.test\." 2>/dev/null || echo "")

if [ -n "$CONSOLE_LOGS" ]; then
  echo "❌ FAILED: Console logging found in:"
  echo "$CONSOLE_LOGS"
  echo ""
  echo "   Fix: Remove console.log statements or wrap in development check:"
  echo "   if (process.env.NODE_ENV === 'development') { console.log(...) }"
  ERRORS=$((ERRORS + 1))
else
  echo "✅ PASSED: No console.log violations"
fi

# Check 2: No hardcoded colors (except text-white)
echo ""
echo "2️⃣  Checking for hardcoded color classes..."
HARDCODED_COLORS=$(git diff --cached --name-only --diff-filter=ACM | \
  grep -E '\.(ts|tsx)$' | \
  grep -v 'pages/public/' | \
  xargs grep -E "(text|bg|border)-(red|green|blue|yellow|orange|purple|gray|black)-[0-9]" 2>/dev/null | \
  grep -v "text-white" | \
  grep -v "\.test\." || echo "")

if [ -n "$HARDCODED_COLORS" ]; then
  echo "❌ FAILED: Hardcoded colors found"
  echo ""
  echo "   Fix: Use theme classes instead:"
  echo "   - text-red-600 → text-theme-danger"
  echo "   - bg-green-100 → bg-theme-success/10"
  echo "   - text-gray-600 → text-theme-muted"
  echo ""
  echo "   Run: ./scripts/fix-hardcoded-colors.sh"
  ERRORS=$((ERRORS + 1))
else
  echo "✅ PASSED: No hardcoded color violations"
fi

# Check 3: No puts/print in Ruby code (excluding seeds and examples which use puts for feedback)
echo ""
echo "3️⃣  Checking for debug statements in Ruby..."
DEBUG_RUBY=$(git diff --cached --name-only --diff-filter=ACM | \
  grep '\.rb$' | \
  grep -v 'seeds' | \
  grep -v 'examples' | \
  xargs grep -E "^\s*(puts|print) " 2>/dev/null || echo "")

if [ -n "$DEBUG_RUBY" ]; then
  echo "❌ FAILED: Debug statements found in Ruby code"
  echo "$DEBUG_RUBY"
  echo ""
  echo "   Fix: Use Rails.logger.debug or logger.debug instead"
  ERRORS=$((ERRORS + 1))
else
  echo "✅ PASSED: No Ruby debug statement violations"
fi

# Check 4: All Ruby files have frozen_string_literal
echo ""
echo "4️⃣  Checking for frozen_string_literal pragma..."
RUBY_FILES=$(git diff --cached --name-only --diff-filter=ACM | grep '\.rb$' || true)
MISSING_FROZEN=""

if [ -n "$RUBY_FILES" ]; then
  # Check each file individually to avoid xargs stdin issues
  for file in $RUBY_FILES; do
    # Skip auto-generated files that don't need frozen_string_literal
    if [[ "$file" == *"schema.rb" ]] || [[ "$file" == *"structure.sql" ]]; then
      continue
    fi
    if [ -f "$file" ] && ! grep -q "frozen_string_literal: true" "$file" 2>/dev/null; then
      MISSING_FROZEN="$MISSING_FROZEN$file"$'\n'
    fi
  done
fi

if [ -n "$MISSING_FROZEN" ]; then
  echo "❌ FAILED: Files missing frozen_string_literal pragma:"
  echo "$MISSING_FROZEN"
  echo ""
  echo "   Fix: Add to top of file:"
  echo "   # frozen_string_literal: true"
  ERRORS=$((ERRORS + 1))
else
  echo "✅ PASSED: All Ruby files have frozen_string_literal"
fi

# Check 5: TypeScript any type usage (warning only)
echo ""
echo "5️⃣  Checking for TypeScript 'any' types (warning)..."
ANY_TYPES=$(git diff --cached --name-only --diff-filter=ACM | \
  grep -E '\.(ts|tsx)$' | \
  xargs grep -c ": any" 2>/dev/null | \
  awk -F: '{sum+=$2} END {print sum}' || echo "0")

if [ "$ANY_TYPES" -gt 0 ]; then
  echo "⚠️  WARNING: $ANY_TYPES 'any' type annotations found"
  echo "   Consider using proper TypeScript types"
else
  echo "✅ PASSED: No 'any' type violations"
fi

# Summary
echo ""
echo "======================================="
if [ $ERRORS -gt 0 ]; then
  echo "❌ Pre-commit checks FAILED ($ERRORS error(s))"
  echo ""
  echo "💡 Fix the issues above and try again"
  echo "   Or use: git commit --no-verify (not recommended)"
  exit 1
else
  echo "✅ All pre-commit checks PASSED!"
  echo ""
  echo "📝 Proceeding with commit..."
  exit 0
fi
