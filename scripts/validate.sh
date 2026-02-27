#!/bin/bash
# Pre-push validation script for Powernode Platform
# Runs backend specs, TypeScript check, and pattern validation
# Usage: ./scripts/validate.sh [--skip-tests] [--skip-ts] [--skip-patterns] [--skip-secrets]

set -eo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

SKIP_TESTS=false
SKIP_TS=false
SKIP_PATTERNS=false
SKIP_SECRETS=false

for arg in "$@"; do
  case "$arg" in
    --skip-tests)   SKIP_TESTS=true ;;
    --skip-ts)      SKIP_TS=true ;;
    --skip-patterns) SKIP_PATTERNS=true ;;
    --skip-secrets)  SKIP_SECRETS=true ;;
    --help)
      echo "Usage: ./scripts/validate.sh [--skip-tests] [--skip-ts] [--skip-patterns] [--skip-secrets]"
      echo ""
      echo "Runs pre-push validation checks:"
      echo "  1. Backend RSpec tests"
      echo "  2. Frontend TypeScript type check"
      echo "  3. Pattern validation audit"
      echo "  4. Secret scanning (gitleaks)"
      echo ""
      echo "Options:"
      echo "  --skip-tests     Skip RSpec backend tests"
      echo "  --skip-ts        Skip TypeScript type check"
      echo "  --skip-patterns  Skip pattern validation"
      echo "  --skip-secrets   Skip gitleaks secret scanning"
      exit 0
      ;;
  esac
done

echo -e "${BLUE}=== Powernode Pre-Push Validation ===${NC}"
echo "Date: $(date)"
echo ""

RESULTS=()
OVERALL_EXIT=0

# 1. Backend RSpec tests
if [[ "$SKIP_TESTS" == "false" ]]; then
  echo -e "${BLUE}[1/4] Running backend specs...${NC}"
  if (cd "$PROJECT_ROOT/server" && bundle exec rspec --format progress 2>&1); then
    RESULTS+=("${GREEN}PASS${NC} Backend specs")
  else
    RESULTS+=("${RED}FAIL${NC} Backend specs")
    OVERALL_EXIT=1
  fi
  echo ""
else
  RESULTS+=("${YELLOW}SKIP${NC} Backend specs")
fi

# 2. TypeScript type check
if [[ "$SKIP_TS" == "false" ]]; then
  echo -e "${BLUE}[2/4] Running TypeScript type check...${NC}"
  if (cd "$PROJECT_ROOT/frontend" && npx tsc --noEmit 2>&1); then
    RESULTS+=("${GREEN}PASS${NC} TypeScript types")
  else
    RESULTS+=("${RED}FAIL${NC} TypeScript types")
    OVERALL_EXIT=1
  fi
  echo ""
else
  RESULTS+=("${YELLOW}SKIP${NC} TypeScript types")
fi

# 3. Pattern validation
if [[ "$SKIP_PATTERNS" == "false" ]]; then
  echo -e "${BLUE}[3/4] Running pattern validation...${NC}"
  if (cd "$PROJECT_ROOT" && ./scripts/pattern-validation.sh 2>&1); then
    RESULTS+=("${GREEN}PASS${NC} Pattern validation")
  else
    PATTERN_EXIT=$?
    if [[ $PATTERN_EXIT -eq 1 ]]; then
      RESULTS+=("${YELLOW}WARN${NC} Pattern validation (minor issues)")
    else
      RESULTS+=("${RED}FAIL${NC} Pattern validation")
      OVERALL_EXIT=1
    fi
  fi
  echo ""
else
  RESULTS+=("${YELLOW}SKIP${NC} Pattern validation")
fi

# 4. Secret scanning (gitleaks)
if [[ "$SKIP_SECRETS" == "false" ]]; then
  echo -e "${BLUE}[4/4] Running secret scanning (gitleaks)...${NC}"
  if command -v gitleaks &> /dev/null; then
    GITLEAKS_CONFIG=""
    if [[ -f "$PROJECT_ROOT/.gitleaks.toml" ]]; then
      GITLEAKS_CONFIG="--config=$PROJECT_ROOT/.gitleaks.toml"
    fi

    # Scan current working tree (not full history — that's the quarterly audit)
    if gitleaks detect --source="$PROJECT_ROOT" $GITLEAKS_CONFIG --no-git 2>&1; then
      RESULTS+=("${GREEN}PASS${NC} Secret scanning")
    else
      RESULTS+=("${RED}FAIL${NC} Secret scanning (secrets detected!)")
      OVERALL_EXIT=1
    fi
  else
    RESULTS+=("${YELLOW}SKIP${NC} Secret scanning (gitleaks not installed)")
  fi
  echo ""
else
  RESULTS+=("${YELLOW}SKIP${NC} Secret scanning")
fi

# Summary
echo -e "${BLUE}=== Validation Summary ===${NC}"
for result in "${RESULTS[@]}"; do
  echo -e "  $result"
done
echo ""

if [[ $OVERALL_EXIT -eq 0 ]]; then
  echo -e "${GREEN}All checks passed — safe to push.${NC}"
else
  echo -e "${RED}Some checks failed — fix issues before pushing.${NC}"
fi

exit $OVERALL_EXIT
