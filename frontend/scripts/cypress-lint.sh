#!/usr/bin/env bash
#
# cypress-lint.sh — Lint guard for Cypress E2E tests
#
# Detects anti-patterns that make tests unable to fail:
# 1. Defensive non-assertion: cy.get('body').then($body => { if (...) })
# 2. Body-visible-only: cy.get('body').should('be.visible') as sole assertion
# 3. Silent conditional logging: cy.log() inside if-blocks with no assertions
#
# Usage:
#   ./scripts/cypress-lint.sh          # Check all test files
#   ./scripts/cypress-lint.sh --fix    # Show suggested fixes (no auto-fix)
#   ./scripts/cypress-lint.sh <file>   # Check specific file
#

set -euo pipefail

CYAN='\033[0;36m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CYPRESS_DIR="${SCRIPT_DIR}/../cypress/e2e"
EXIT_CODE=0
TOTAL_ISSUES=0

target="${1:-}"

if [[ "$target" == "--fix" ]]; then
  FIX_MODE=true
  target=""
elif [[ -n "$target" && -f "$target" ]]; then
  FIX_MODE=false
else
  FIX_MODE=false
fi

count_matches() {
  local pattern="$1"
  local file="$2"
  grep -cE "$pattern" "$file" 2>/dev/null || true
}

check_file() {
  local file="$1"
  local issues=0
  local rel_path="${file#${SCRIPT_DIR}/../}"
  local count=0

  # Pattern 1: Defensive non-assertion — cy.get('body').then($body =>
  count=$(count_matches "cy\.get\('body'\)\.then\(" "$file")
  if [[ $count -gt 0 ]]; then
    echo -e "${RED}[ANTI-PATTERN]${NC} ${rel_path}: ${count} defensive non-assertion(s)"
    echo -e "  ${YELLOW}→ cy.get('body').then(\$body => { if (...) }) — wraps assertions in conditionals that silently pass${NC}"
    if [[ "$FIX_MODE" == true ]]; then
      echo -e "  ${CYAN}Fix: Replace with cy.assertContainsAny([...]) or cy.assertHasElement([...])${NC}"
    fi
    issues=$((issues + count))
  fi

  # Pattern 2: Body-visible as sole assertion — cy.get('body').should('be.visible')
  count=$(count_matches "cy\.get\('body'\)\.should\('be\.visible'\)" "$file")
  if [[ $count -gt 0 ]]; then
    echo -e "${RED}[ANTI-PATTERN]${NC} ${rel_path}: ${count} body-visible-only assertion(s)"
    echo -e "  ${YELLOW}→ cy.get('body').should('be.visible') — always passes, not a real assertion${NC}"
    if [[ "$FIX_MODE" == true ]]; then
      echo -e "  ${CYAN}Fix: Replace with cy.assertContainsAny([...relevant page content...])${NC}"
    fi
    issues=$((issues + count))
  fi

  # Pattern 3: length >= 0 always-true checks
  count=$(count_matches "length >= 0" "$file")
  if [[ $count -gt 0 ]]; then
    echo -e "${RED}[ANTI-PATTERN]${NC} ${rel_path}: ${count} always-true length check(s)"
    echo -e "  ${YELLOW}→ .length >= 0 — always true, makes the conditional meaningless${NC}"
    if [[ "$FIX_MODE" == true ]]; then
      echo -e "  ${CYAN}Fix: Use .length > 0 or remove the conditional entirely${NC}"
    fi
    issues=$((issues + count))
  fi

  # Pattern 4: || true always-true boolean
  count=$(count_matches "\|\| true" "$file")
  if [[ $count -gt 0 ]]; then
    echo -e "${RED}[ANTI-PATTERN]${NC} ${rel_path}: ${count} always-true boolean(s)"
    echo -e "  ${YELLOW}→ || true — makes the entire expression always true${NC}"
    if [[ "$FIX_MODE" == true ]]; then
      echo -e "  ${CYAN}Fix: Remove || true and test the actual condition${NC}"
    fi
    issues=$((issues + count))
  fi

  TOTAL_ISSUES=$((TOTAL_ISSUES + issues))
  if [[ $issues -gt 0 ]]; then
    EXIT_CODE=1
  fi
}

echo -e "${CYAN}Cypress E2E Lint Guard${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ -n "$target" && -f "$target" ]]; then
  check_file "$target"
else
  while IFS= read -r -d '' file; do
    check_file "$file"
  done < <(find "$CYPRESS_DIR" -name "*.cy.ts" -print0 | sort -z)
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [[ "$TOTAL_ISSUES" -eq 0 ]]; then
  echo -e "${GREEN}✓ No anti-patterns found${NC}"
else
  echo -e "${RED}✗ Found ${TOTAL_ISSUES} anti-pattern(s)${NC}"
  echo -e "${YELLOW}  Run with --fix flag for suggested fixes${NC}"
fi

exit $EXIT_CODE
