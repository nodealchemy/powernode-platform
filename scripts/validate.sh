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

# 0. Preflight: gem pre-activation doctor (fail fast — a newer-than-locked orphan
# of a boot-critical gem (json, rdoc, ...) crashes boot with "already activated
# <gem>-X", so nothing after this can run reliably; see
# scripts/doctor-gem-preactivation.sh for remediation)
echo -e "${BLUE}[0/4] Gem pre-activation doctor...${NC}"
if "$SCRIPT_DIR/doctor-gem-preactivation.sh"; then
  echo ""
else
  echo ""
  echo -e "${RED}Gem pre-activation doctor FAILED — fix the orphan gem before validating.${NC}"
  exit 1
fi

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

# 2. TypeScript type check (platform + each extension that has tsconfig.check.json)
if [[ "$SKIP_TS" == "false" ]]; then
  echo -e "${BLUE}[2/4] Running TypeScript type check...${NC}"
  TS_OK=true
  if (cd "$PROJECT_ROOT/frontend" && npx tsc --noEmit 2>&1); then
    :
  else
    TS_OK=false
  fi
  # Each extensions/*/frontend/tsconfig.check.json is a tsc gate for that
  # extension's frontend tree (Vite resolves @<slug>/* aliases at runtime,
  # but the platform's main tsconfig.json only includes its own src). Without
  # this loop, runtime ReferenceErrors and TS1005 syntax errors in extension
  # components slip past the validation gate (see history: CanaryMarker +
  # ArchitectureList).
  # tsc needs to walk up from extension source files and find react etc. —
  # it walks up from the file location, so the platform's node_modules has
  # to be reachable from extensions/<slug>/frontend/. We ensure this by
  # symlinking; never commit the symlink (extension .gitignore handles that).
  # Enumerate extension FRONTEND DIRS, not tsconfig.check.json files. Globbing
  # the configs made a missing one a silent skip — which is precisely how
  # marketing and supply-chain stayed unchecked (380 source files) while the
  # gate reported green, and how a real regression (mainNav deleted from
  # PublicPageContainer under a "bump dependencies" commit) survived. An
  # extension frontend must now either ship a config or be named in
  # scripts/tsc-check-optouts.txt with a reason; anything else fails.
  OPTOUT_FILE="$PROJECT_ROOT/scripts/tsc-check-optouts.txt"
  for ext_dir in "$PROJECT_ROOT"/extensions/*/frontend "$PROJECT_ROOT"/extensions/private/*/frontend; do
    [[ -d "$ext_dir" ]] || continue
    ext_slug="$(basename "$(dirname "$ext_dir")")"
    ext_tsconfig="$ext_dir/tsconfig.check.json"

    if [[ ! -f "$ext_tsconfig" ]]; then
      # Opt-out lines are "<slug><whitespace><reason>"; comments start with #.
      # `|| true` is load-bearing: this script runs under `set -eo pipefail`, so
      # a no-match grep (exit 1) inside a command substitution aborts the whole
      # gate — silently, mid-phase, with no summary. That is the exact failure
      # mode this check exists to remove, so it must not introduce one.
      optout_reason="$(grep -E "^${ext_slug}[[:space:]]" "$OPTOUT_FILE" 2>/dev/null | head -1 | sed -E "s/^${ext_slug}[[:space:]]+//" || true)"
      if [[ -n "$optout_reason" ]]; then
        # Printed every run on purpose: an exemption that is invisible stops
        # being a decision and becomes an accident.
        echo -e "${YELLOW}  └─ SKIP extensions/$ext_slug/frontend — not type-checked: ${optout_reason}${NC}"
      else
        echo -e "${RED}  └─ extensions/$ext_slug/frontend has no tsconfig.check.json and no entry in scripts/tsc-check-optouts.txt${NC}"
        TS_OK=false
      fi
      continue
    fi

    if [[ ! -e "$ext_dir/node_modules" ]]; then
      ln -sf "$PROJECT_ROOT/frontend/node_modules" "$ext_dir/node_modules"
    fi
    if (cd "$PROJECT_ROOT/frontend" && npx tsc --noEmit -p "$ext_tsconfig" 2>&1); then
      :
    else
      echo -e "${RED}  └─ extensions/$ext_slug/frontend tsc failed${NC}"
      TS_OK=false
    fi
  done
  if [[ "$TS_OK" == "true" ]]; then
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
      RESULTS+=("${YELLOW}WARN${NC} Pattern validation (non-critical failures — see scripts/pattern-validation.sh)")
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
