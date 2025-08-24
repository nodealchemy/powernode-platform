#!/bin/bash

# Quick Pattern Check Script for Development
# Performs essential pattern validation checks for rapid feedback

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Quick Pattern Compliance Check ===${NC}"

# Function for quick checks
quick_check() {
    local name="$1"
    local command="$2"
    local expected="$3"
    
    echo -n "$name: "
    result=$(eval "$command" 2>/dev/null || echo "0")
    
    case "$expected" in
        "empty")
            if [[ -z "$result" || "$result" == "0" ]]; then
                echo -e "${GREEN}✓${NC}"
            else
                echo -e "${RED}✗ ($result found)${NC}"
            fi
            ;;
        "positive")
            if [[ "$result" -gt 0 ]]; then
                echo -e "${GREEN}✓ ($result)${NC}"
            else
                echo -e "${RED}✗ (none found)${NC}"
            fi
            ;;
        *)
            if [[ "$result" -eq "$expected" ]]; then
                echo -e "${GREEN}✓ ($result)${NC}"
            else
                echo -e "${YELLOW}⚠ ($result, expected $expected)${NC}"
            fi
            ;;
    esac
}

echo -e "${BLUE}Backend Patterns:${NC}"
quick_check "API Response Format" "grep -r 'success:' server/app/controllers/ | wc -l" "positive"
quick_check "Permission Authorization" "grep -r 'require_permission' server/app/controllers/ | wc -l" "positive"
quick_check "UUID Primary Keys" "grep -r 'string :id, limit: 36' server/db/migrate/ | wc -l" "positive"
quick_check "Debug Code (should be 0)" "grep -r 'puts \|p ' server/app/ | wc -l" "empty"

echo -e "${BLUE}Frontend Patterns:${NC}"
quick_check "Permission-based Access" "grep -r 'hasPermission' frontend/src/ | wc -l" "positive"
quick_check "Role-based Access (should be 0)" "grep -r '\.roles.*includes\|\.role.*==' frontend/src/ | grep -v 'formatRole\|member\.roles.*map' | wc -l" "empty"
quick_check "Theme Classes" "grep -r 'bg-theme-\|text-theme-' frontend/src/ | wc -l" "positive"
quick_check "Console.log (should be 0)" "grep -r 'console.log' frontend/src/ | wc -l" "empty"

echo -e "${BLUE}Worker Patterns:${NC}"
quick_check "BaseJob Inheritance" "grep -r '< BaseJob' worker/app/jobs/ | wc -l" "positive"
quick_check "ApplicationJob (should be 0)" "grep -r '< ApplicationJob' worker/app/jobs/ | wc -l" "empty"
quick_check "Execute Method" "grep -r 'def execute' worker/app/jobs/ | wc -l" "positive"
quick_check "ActiveRecord Usage (should be 0)" "grep -r 'ActiveRecord' worker/app/ | grep -v 'comments' | wc -l" "empty"

echo ""
echo -e "${GREEN}Quick check completed!${NC}"
echo "For comprehensive analysis, run: ./scripts/pattern-validation.sh"