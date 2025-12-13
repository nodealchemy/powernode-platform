#!/bin/bash

# Refined Pattern Validation Script with Fewer False Positives
# Focuses on actual pattern violations vs legitimate usage

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Refined Powernode Pattern Compliance Audit ===${NC}"
echo "Date: $(date)"
echo ""

# Initialize counters
total_checks=0
passed_checks=0
failed_checks=0
warnings=0

# Function to check pattern compliance
check_pattern() {
    local description="$1"
    local command="$2"
    local expected="$3"
    local warning_threshold="$4"
    
    total_checks=$((total_checks + 1))
    echo -n "Checking: $description... "
    
    result=$(eval "$command" 2>/dev/null || echo "0")
    
    if [[ "$expected" == "empty" ]]; then
        if [[ -z "$result" || "$result" -eq 0 ]]; then
            echo -e "${GREEN}✓ PASS${NC}"
            passed_checks=$((passed_checks + 1))
        else
            echo -e "${RED}✗ FAIL${NC} (Found: $result)"
            failed_checks=$((failed_checks + 1))
        fi
    elif [[ "$expected" == "positive" ]]; then
        if [[ "$result" -gt 0 ]]; then
            if [[ -n "$warning_threshold" && "$result" -lt "$warning_threshold" ]]; then
                echo -e "${YELLOW}⚠ WARN${NC} (Found: $result, Expected: >=$warning_threshold)"
                warnings=$((warnings + 1))
            else
                echo -e "${GREEN}✓ PASS${NC} (Found: $result)"
                passed_checks=$((passed_checks + 1))
            fi
        else
            echo -e "${RED}✗ FAIL${NC} (Found: $result)"
            failed_checks=$((failed_checks + 1))
        fi
    else
        if [[ "$result" -eq "$expected" ]]; then
            echo -e "${GREEN}✓ PASS${NC} (Found: $result)"
            passed_checks=$((passed_checks + 1))
        else
            echo -e "${YELLOW}⚠ WARN${NC} (Found: $result, Expected: $expected)"
            warnings=$((warnings + 1))
        fi
    fi
}

echo -e "${BLUE}## Critical Backend Patterns${NC}"

# API Response Format Compliance
check_pattern "API success response format usage" \
    "grep -r 'success: true' server/app/controllers/ | wc -l" \
    "positive" "10"

check_pattern "API error response format usage" \
    "grep -r 'success: false' server/app/controllers/ | wc -l" \
    "positive" "5"

# Controller Pattern Compliance
check_pattern "Api::V1 namespace usage" \
    "find server/app/controllers/api/v1 -name '*.rb' | wc -l" \
    "positive" "5"

check_pattern "Permission-based authorization" \
    "grep -r 'require_permission' server/app/controllers/ | wc -l" \
    "positive" "10"

# Model Structure Compliance
check_pattern "UUID primary key usage" \
    "grep -r 'string :id, limit: 36' server/db/migrate/ | wc -l" \
    "positive" "10"

check_pattern "Model frozen_string_literal compliance" \
    "find server/app/models -name '*.rb' -exec grep -L 'frozen_string_literal' {} \\; | wc -l" \
    "5"

echo ""
echo -e "${BLUE}## Critical Frontend Patterns${NC}"

# Permission-Based Access Control (REFINED)
check_pattern "Permission-based access control usage" \
    "grep -r 'hasPermission\\|permissions.*includes' frontend/src/ | wc -l" \
    "positive" "20"

# REFINED: Only flag actual access control violations, not data display or filtering
check_pattern "Actual role-based access control violations (refined)" \
    "grep -r 'if.*user.*roles.*includes\\|if.*currentUser.*roles.*includes\\|canAccess.*roles' frontend/src/ | grep -v formatRole | grep -v 'filter.*role.*includes\\|filters\\.role.*includes' | wc -l" \
    "empty"

# Theme System Compliance
check_pattern "Theme-aware CSS classes usage" \
    "grep -r 'bg-theme-\\|text-theme-\\|border-theme' frontend/src/ | wc -l" \
    "positive" "50"

# REFINED: Only production console.log, exclude development guards
check_pattern "Production console.log statements (refined)" \
    "grep -r 'console\\.log' frontend/src/ | grep -v 'if.*NODE_ENV.*development' | grep -v '/scripts/' | wc -l" \
    "empty"

echo ""
echo -e "${BLUE}## Worker Pattern Compliance${NC}"

# BaseJob Pattern Compliance
check_pattern "BaseJob inheritance" \
    "grep -r '< BaseJob' worker/app/jobs/ | wc -l" \
    "positive" "5"

check_pattern "Forbidden ApplicationJob inheritance (should be empty)" \
    "grep -r '< ApplicationJob' worker/app/jobs/ | wc -l" \
    "empty"

check_pattern "Execute method usage" \
    "grep -r 'def execute' worker/app/jobs/ | wc -l" \
    "positive" "5"

check_pattern "Forbidden ActiveRecord usage (should be empty)" \
    "grep -r 'ActiveRecord' worker/app/ | grep -v 'comments\\|# ActiveRecord' | wc -l" \
    "empty"

echo ""
echo -e "${BLUE}## Code Quality Patterns (Refined)${NC}"

# REFINED: Backend debug code (exclude comments and string literals)
check_pattern "Backend debug statements (refined)" \
    "grep -r 'puts ' server/app/ | grep -v '#.*puts\\|\".*puts\\|'.*puts' | wc -l" \
    "empty"

# TypeScript Quality (more lenient threshold)
check_pattern "TypeScript any types (should be minimal)" \
    "grep -r ': any' frontend/src/ | grep -v 'node_modules\\|catch.*error: any' | wc -l" \
    "20"

echo ""
echo -e "${BLUE}## Architecture Patterns${NC}"

# Service Architecture
check_pattern "Service object usage" \
    "find server/app/services -name '*.rb' | wc -l" \
    "positive" "5"

check_pattern "Job service integration" \
    "grep -r 'WorkerJobService' server/app/ | wc -l" \
    "positive" "3"

echo ""
echo -e "${BLUE}=== REFINED AUDIT SUMMARY ===${NC}"
echo "Total Checks: $total_checks"
echo -e "Passed: ${GREEN}$passed_checks${NC}"
echo -e "Failed: ${RED}$failed_checks${NC}"
echo -e "Warnings: ${YELLOW}$warnings${NC}"

# Calculate compliance percentage
if [[ $total_checks -gt 0 ]]; then
    compliance_rate=$(( (passed_checks * 100) / total_checks ))
    echo "Compliance Rate: $compliance_rate%"
    
    if [[ $compliance_rate -ge 95 ]]; then
        echo -e "${GREEN}🎉 EXCELLENT: Platform shows excellent pattern compliance!${NC}"
        exit_code=0
    elif [[ $compliance_rate -ge 85 ]]; then
        echo -e "${YELLOW}⚠️ GOOD: Platform shows good compliance with minor issues${NC}"
        exit_code=1
    else
        echo -e "${RED}❌ NEEDS WORK: Platform needs pattern improvements${NC}"
        exit_code=2
    fi
else
    echo -e "${RED}❌ ERROR: No checks were performed${NC}"
    exit_code=3
fi

echo ""
echo -e "${GREEN}This refined audit focuses on actual violations vs false positives.${NC}"
echo "For detailed analysis of specific issues, run individual checks from the script."

exit $exit_code