#!/bin/bash
# Install git hooks for code quality enforcement

echo "🔧 Installing Git Hooks..."
echo "=========================="
echo ""

GIT_HOOKS_DIR=".git/hooks"

if [ ! -d "$GIT_HOOKS_DIR" ]; then
  echo "❌ Error: Not a git repository (no .git/hooks directory found)"
  exit 1
fi

# Install pre-commit hook
echo "Installing pre-commit hook..."
cat > "$GIT_HOOKS_DIR/pre-commit" << 'EOF'
#!/bin/bash
# Powernode Platform - Pre-commit Quality Check
# This hook runs automated quality checks before allowing a commit

./scripts/pre-commit-quality-check.sh
EOF

chmod +x "$GIT_HOOKS_DIR/pre-commit"

echo "✅ Pre-commit hook installed!"
echo ""
echo "📋 Installed Checks:"
echo "  1. No console.log in production code"
echo "  2. No hardcoded color classes"
echo "  3. No puts/print in Ruby code"
echo "  4. All Ruby files have frozen_string_literal"
echo "  5. TypeScript 'any' type warnings"
echo ""
echo "💡 To bypass checks (not recommended):"
echo "   git commit --no-verify"
echo ""
echo "✨ Git hooks installation complete!"
