#!/bin/bash

# Pattern Validation Script for Powernode Platform
# Validates compliance with discovered architectural patterns

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Powernode Platform Pattern Compliance Audit ===${NC}"
echo "Date: $(date)"
echo "Platform Version: $(cat VERSION 2>/dev/null || echo 'Unknown')"
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
    # Clean up result - remove newlines and get just the first number
    result=$(echo "$result" | tr -d '\n' | grep -o '[0-9]*' | head -1 | grep -v '^$' || echo "0")
    
    if [[ "$expected" == "empty" ]]; then
        if [[ -z "$result" || "$result" -eq 0 ]]; then
            echo -e "${GREEN}✓ PASS${NC}"
            passed_checks=$((passed_checks + 1))
        else
            echo -e "${RED}✗ FAIL${NC} (Found: $result)"
            failed_checks=$((failed_checks + 1))
        fi
    elif [[ "$expected" == "positive" ]]; then
        if [[ "$result" -gt 0 ]] 2>/dev/null; then
            if [[ -n "$warning_threshold" && "$result" -lt "$warning_threshold" ]] 2>/dev/null; then
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

echo -e "${BLUE}## Backend Pattern Compliance${NC}"

# API Response Format Compliance
check_pattern "API response format compliance" \
    "grep -r 'render json:' server/app/controllers/ | grep -c '\"success\":' 2>/dev/null" \
    "positive" "10"

check_pattern "Success response usage" \
    "grep -r 'success: true' server/app/controllers/ | wc -l" \
    "positive" "5"

check_pattern "Error response usage" \
    "grep -r 'success: false' server/app/controllers/ | wc -l" \
    "positive" "5"

# Controller Pattern Compliance
check_pattern "Api::V1 namespace usage" \
    "find server/app/controllers/api/v1 -name '*.rb' | wc -l" \
    "positive" "5"

check_pattern "Controller serialization concerns" \
    "grep -r 'include.*Serialization' server/app/controllers/ | wc -l" \
    "positive" "3"

check_pattern "Permission-based authorization" \
    "grep -r 'require_permission' server/app/controllers/ | wc -l" \
    "positive" "10"

# Model Structure Compliance
check_pattern "UUID primary key usage" \
    "grep -r 'string :id, limit: 36' server/db/migrate/ | wc -l" \
    "positive" "10"

check_pattern "Model frozen_string_literal pragma" \
    "find server/app/models -name '*.rb' -exec grep -L 'frozen_string_literal' {} \; | wc -l" \
    "empty"

check_pattern "Permission method implementation" \
    "grep -r 'def has_permission?' server/app/models/ | wc -l" \
    "positive" "1"

check_pattern "Model concern usage" \
    "grep -r 'include.*Security\|include.*Concern' server/app/models/ | wc -l" \
    "positive" "2"

echo ""
echo -e "${BLUE}## Frontend Pattern Compliance${NC}"

# Permission-Based Access Control (CRITICAL)
check_pattern "Permission-based access control usage" \
    "grep -r 'hasPermission\|permissions.*includes' frontend/src/ | wc -l" \
    "positive" "20"

check_pattern "Forbidden role-based access (should be empty)" \
    "grep -r 'if.*roles.*includes\|roles.*includes.*return\|canAccess.*roles\|hasRole.*roles\|checkRole.*roles' frontend/src/ | grep -v 'display\|format\|badge\|map\|filter\|length' | wc -l" \
    "empty"

check_pattern "Forbidden user role access (should be empty)" \
    "grep -r 'currentUser.*roles\?\.' frontend/src/ | grep -v 'display\|format\|badge\|member\.roles\|user\.roles.*map' | wc -l" \
    "empty"

# Theme System Compliance
check_pattern "Theme-aware CSS classes usage" \
    "grep -r 'bg-theme-\|text-theme-\|border-theme' frontend/src/ | wc -l" \
    "positive" "50"

check_pattern "Forbidden hardcoded colors (should be minimal)" \
    "grep -r 'bg-red-\|bg-white\|text-black\|border-gray-' frontend/src/ | grep -v 'text-white' | wc -l" \
    "5"

# Component Structure
check_pattern "React component forwardRef usage" \
    "grep -r 'forwardRef' frontend/src/ | wc -l" \
    "positive" "10"

check_pattern "Component displayName usage" \
    "grep -r '\.displayName' frontend/src/ | wc -l" \
    "positive" "10"

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

check_pattern "Forbidden perform method overrides (should be empty)" \
    "grep -r 'def perform' worker/app/jobs/ | grep -v BaseJob | wc -l" \
    "empty"

check_pattern "Forbidden ActiveRecord usage (should be empty)" \
    "grep -r 'ActiveRecord' worker/app/ | grep -v 'comments\|# ActiveRecord' | wc -l" \
    "empty"

echo ""
echo -e "${BLUE}## Code Quality Patterns${NC}"

# Frozen String Literal
check_pattern "Backend frozen_string_literal compliance" \
    "find server/app -name '*.rb' -exec grep -L 'frozen_string_literal' {} \; | wc -l" \
    "empty"

check_pattern "Worker frozen_string_literal compliance" \
    "find worker/app -name '*.rb' -exec grep -L 'frozen_string_literal' {} \; | wc -l" \
    "empty"

# Debug Code (should be empty)
check_pattern "Backend debug code (should be empty)" \
    "grep -r 'puts \|p \|print ' server/app/ | wc -l" \
    "empty"

check_pattern "Frontend debug code (should be empty)" \
    "grep -r 'console.log' frontend/src/ | wc -l" \
    "empty"

check_pattern "TypeScript any types (should be minimal)" \
    "grep -r ': any' frontend/src/ | grep -v 'node_modules' | wc -l" \
    "5"

echo ""
echo -e "${BLUE}## Architecture Patterns${NC}"

# Service Architecture
check_pattern "Service object usage" \
    "find server/app/services -name '*.rb' | wc -l" \
    "positive" "5"

check_pattern "Job service integration" \
    "grep -r 'WorkerJobService' server/app/ | wc -l" \
    "positive" "3"

# Navigation Structure (should be flat, no children)
check_pattern "Forbidden submenu navigation (should be empty)" \
    "grep -c 'children:' frontend/src/config/navigation.tsx 2>/dev/null" \
    "empty"

echo ""
echo -e "${BLUE}=== AUDIT SUMMARY ===${NC}"
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
        echo -e "${RED}❌ NEEDS WORK: Platform needs significant pattern improvements${NC}"
        exit_code=2
    fi
else
    echo -e "${RED}❌ ERROR: No checks were performed${NC}"
    exit_code=3
fi

echo ""
echo "For detailed pattern documentation, see:"
echo "- docs/platform/PLATFORM_PATTERNS_ANALYSIS.md"
echo "- docs/platform/PLATFORM_STANDARDIZATION_RECOMMENDATIONS.md"
echo "- Individual MCP specialist documentation in docs/{backend,frontend,testing}/"

exit $exit_code