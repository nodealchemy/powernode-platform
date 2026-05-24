#!/bin/bash
# Install git hooks for code quality enforcement and secret scanning

echo "🔧 Installing Git Hooks..."
echo "=========================="
echo ""

GIT_HOOKS_DIR=".git/hooks"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

if [ ! -d "$GIT_HOOKS_DIR" ]; then
  echo "❌ Error: Not a git repository (no .git/hooks directory found)"
  exit 1
fi

# Check if gitleaks is installed
check_gitleaks() {
  if command -v gitleaks &> /dev/null; then
    echo "✅ gitleaks found: $(gitleaks version 2>/dev/null || echo 'installed')"
    return 0
  else
    echo "⚠️  gitleaks not found - secret scanning will be skipped"
    echo "   Install: brew install gitleaks (macOS) or go install github.com/gitleaks/gitleaks/v8@latest"
    return 1
  fi
}

echo "Checking dependencies..."
if check_gitleaks; then
  GITLEAKS_AVAILABLE="true"
else
  GITLEAKS_AVAILABLE="false"
fi
echo ""

# Install pre-commit hook
echo "Installing pre-commit hook..."
cat > "$GIT_HOOKS_DIR/pre-commit" << 'HOOK_EOF'
#!/bin/bash
# Powernode Platform - Pre-commit Quality & Security Check
# This hook runs automated quality checks and secret scanning before allowing a commit

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "🔍 Running pre-commit checks..."
echo ""

# Run quality checks
echo "📋 Quality Checks..."
"$PROJECT_ROOT/scripts/pre-commit-quality-check.sh"
QUALITY_EXIT=$?

if [ $QUALITY_EXIT -ne 0 ]; then
  echo ""
  echo "❌ Quality checks failed. Fix issues before committing."
  exit 1
fi

# Run secret scanning with gitleaks
echo ""
echo "🔐 Secret Scanning..."

if command -v gitleaks &> /dev/null; then
  # Scan staged files only for faster pre-commit
  if [ -f "$PROJECT_ROOT/.gitleaks.toml" ]; then
    GITLEAKS_CONFIG="--config=$PROJECT_ROOT/.gitleaks.toml"
  else
    GITLEAKS_CONFIG=""
  fi

  # Get list of staged files
  STAGED_FILES=$(git diff --cached --name-only --diff-filter=ACMR)

  if [ -n "$STAGED_FILES" ]; then
    # Create temp directory for staged content
    TEMP_DIR=$(mktemp -d)
    trap "rm -rf $TEMP_DIR" EXIT

    # Export staged content to temp directory
    for file in $STAGED_FILES; do
      dir=$(dirname "$file")
      mkdir -p "$TEMP_DIR/$dir"
      git show ":$file" > "$TEMP_DIR/$file" 2>/dev/null || true
    done

    # Run gitleaks on staged content
    if gitleaks detect --source="$TEMP_DIR" $GITLEAKS_CONFIG --no-git --verbose 2>&1; then
      echo "✅ No secrets detected in staged files"
    else
      echo ""
      echo "🚨 SECRETS DETECTED!"
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo "Potential secrets found in staged files."
      echo ""
      echo "If this is a false positive, you can:"
      echo "  1. Add pattern to .gitleaks.toml allowlist"
      echo "  2. Use 'git commit --no-verify' (not recommended)"
      echo ""
      echo "If this is a real secret:"
      echo "  1. Remove the secret from the file"
      echo "  2. Use environment variables instead"
      echo "  3. Add to .env (which is gitignored)"
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      exit 1
    fi
  else
    echo "ℹ️  No files staged for commit"
  fi
else
  echo "⚠️  gitleaks not installed - skipping secret scan"
  echo "   Install: brew install gitleaks (macOS)"
  echo "            go install github.com/gitleaks/gitleaks/v8@latest"
fi

echo ""
echo "✅ All pre-commit checks passed!"
HOOK_EOF

chmod +x "$GIT_HOOKS_DIR/pre-commit"

echo "✅ Pre-commit hook installed!"
echo ""

# Install pre-push hook (submodule pointer integrity + docs link check)
echo "Installing pre-push hook..."
cat > "$GIT_HOOKS_DIR/pre-push" << 'PUSH_HOOK_EOF'
#!/bin/bash
# Powernode Platform - Pre-push Gate
#
# Runs two checks before allowing push:
#   1. Submodule pointer integrity — every submodule pointer in HEAD must
#      be reachable on the same remote we're pushing the parent to.
#      Catches the "publish-before-pointer" failure mode that broke
#      build-platform-modules CI on 2026-05-24 (supply-chain pointer
#      bumped to da97052 before the submodule commit was pushed).
#   2. Docs link checker — broken links in docs/.
#
# Bypass (use sparingly):
#   git push --no-verify
#
# Pre-push receives: $1=remote-name $2=remote-url, then ref lines on stdin.

PUSH_REMOTE="${1:-origin}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# --- Submodule pointer check -------------------------------------------------
POINTER_CHECKER="$PROJECT_ROOT/scripts/verify-submodule-pointers.sh"
if [ -x "$POINTER_CHECKER" ]; then
  echo "🔗 Verifying submodule pointers against remote '$PUSH_REMOTE'..."
  if ! PUSH_REMOTE="$PUSH_REMOTE" bash "$POINTER_CHECKER" --remote "$PUSH_REMOTE"; then
    echo ""
    echo "❌ Submodule pointer check failed."
    echo "   Push the missing submodule commit(s) first, OR bypass with:"
    echo "     git push --no-verify"
    exit 1
  fi
else
  echo "ℹ️  scripts/verify-submodule-pointers.sh not found or not executable — skipping submodule check"
fi

# --- Docs link check ---------------------------------------------------------
LINK_CHECKER="$PROJECT_ROOT/docs/.verify/check-links.sh"
if [ ! -x "$LINK_CHECKER" ]; then
  echo "ℹ️  docs/.verify/check-links.sh not found or not executable — skipping doc link check"
  exit 0
fi

echo "🔗 Running docs link check..."
if bash "$LINK_CHECKER"; then
  echo "✅ Docs link check passed"
  exit 0
else
  echo ""
  echo "❌ Docs link check failed."
  echo "   Fix the broken links above, or bypass with: git push --no-verify"
  exit 1
fi
PUSH_HOOK_EOF

chmod +x "$GIT_HOOKS_DIR/pre-push"

echo "✅ Pre-push hook installed (submodule pointer + docs link check)!"
echo ""
echo "📋 Installed Checks:"
echo "  1. No console.log in production code"
echo "  2. No hardcoded color classes"
echo "  3. No puts/print in Ruby code"
echo "  4. All Ruby files have frozen_string_literal"
echo "  5. TypeScript 'any' type warnings"
echo "  6. Secret scanning with gitleaks (if installed)"
echo "  7. Submodule pointer integrity on push (scripts/verify-submodule-pointers.sh)"
echo "  8. Docs link check on push (docs/.verify/check-links.sh)"
echo ""
echo "🔐 Secret Scanning:"
if [ "$GITLEAKS_AVAILABLE" = "true" ]; then
  echo "   ✅ gitleaks is available - secrets will be scanned"
else
  echo "   ⚠️  gitleaks not installed - install for secret scanning"
  echo "      brew install gitleaks (macOS)"
  echo "      go install github.com/gitleaks/gitleaks/v8@latest"
fi
echo ""
echo "💡 To bypass checks (not recommended):"
echo "   git commit --no-verify"
echo ""
echo "✨ Git hooks installation complete!"
