#!/bin/bash

# Pre-commit Pattern Enforcement Hook
# Validates critical patterns before allowing commits

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}Pre-commit Pattern Validation${NC}"

# Get list of staged files
STAGED_FILES=$(git diff --cached --name-only --diff-filter=ACM)

# Check if there are any staged files
if [[ -z "$STAGED_FILES" ]]; then
    echo "No staged files to check"
    exit 0
fi

# Initialize failure flag
FAILED=0

# Function to check staged files
check_staged_pattern() {
    local description="$1"
    local pattern="$2"
    local file_pattern="$3"
    local should_exist="$4"
    
    echo -n "Checking $description... "
    
    # Filter staged files by pattern
    local relevant_files
    if [[ -n "$file_pattern" ]]; then
        relevant_files=$(echo "$STAGED_FILES" | grep "$file_pattern" || true)
    else
        relevant_files="$STAGED_FILES"
    fi
    
    if [[ -z "$relevant_files" ]]; then
        echo -e "${GREEN}N/A${NC}"
        return 0
    fi
    
    local found_violations=""
    for file in $relevant_files; do
        if [[ -f "$file" ]]; then
            local matches=$(grep -l "$pattern" "$file" 2>/dev/null || true)
            if [[ "$should_exist" == "true" && -z "$matches" ]]; then
                found_violations="$found_violations $file"
            elif [[ "$should_exist" == "false" && -n "$matches" ]]; then
                found_violations="$found_violations $file"
            fi
        fi
    done
    
    if [[ -n "$found_violations" ]]; then
        echo -e "${RED}FAIL${NC}"
        echo -e "${RED}  Violating files:$found_violations${NC}"
        FAILED=1
    else
        echo -e "${GREEN}PASS${NC}"
    fi
}

echo ""
echo -e "${BLUE}=== Critical Pattern Checks ===${NC}"

# Backend Pattern Checks
check_staged_pattern "API response format" '"success":' "server/app/controllers/.*\.rb$" "true"
check_staged_pattern "Frozen string literal in backend" "frozen_string_literal: true" "server/app/.*\.rb$" "true"
check_staged_pattern "Debug code in backend" "puts \|p " "server/app/.*\.rb$" "false"

# Frontend Pattern Checks  
check_staged_pattern "Role-based access control (forbidden)" "\.roles.*includes\|\.role.*==" "frontend/src/.*\.tsx?$" "false"
check_staged_pattern "Console.log in frontend" "console\.log" "frontend/src/.*\.tsx?$" "false"
check_staged_pattern "Hardcoded colors" "bg-red-\|bg-blue-\|bg-green-\|text-gray-" "frontend/src/.*\.tsx?$" "false"

# Worker Pattern Checks
check_staged_pattern "ApplicationJob inheritance (forbidden)" "< ApplicationJob" "worker/app/jobs/.*\.rb$" "false"
check_staged_pattern "ActiveRecord usage in worker (forbidden)" "ActiveRecord" "worker/app/.*\.rb$" "false"
check_staged_pattern "Frozen string literal in worker" "frozen_string_literal: true" "worker/app/.*\.rb$" "true"

echo ""

if [[ $FAILED -eq 1 ]]; then
    echo -e "${RED}❌ COMMIT BLOCKED: Pattern violations detected${NC}"
    echo ""
    echo "Please fix the violations above and try again."
    echo "For pattern documentation, see:"
    echo "  - docs/platform/PLATFORM_PATTERNS_ANALYSIS.md"
    echo "  - docs/backend/RAILS_ARCHITECT_SPECIALIST.md"
    echo "  - docs/frontend/REACT_ARCHITECT_SPECIALIST.md"
    echo "  - docs/backend/BACKGROUND_JOB_ENGINEER_SPECIALIST.md"
    echo ""
    echo "To bypass this check (not recommended): git commit --no-verify"
    exit 1
else
    echo -e "${GREEN}✅ All pattern checks passed!${NC}"
    exit 0
fi