#!/bin/bash

# Pattern Statistics Generator
# Generates comprehensive statistics about current pattern usage

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

OUTPUT_FILE="docs/platform/PATTERN_USAGE_STATISTICS.md"

echo -e "${BLUE}Generating Pattern Usage Statistics...${NC}"

# Create the output file
cat > "$OUTPUT_FILE" << 'EOF'
# Pattern Usage Statistics

**Generated**: $(date)  
**Platform Version**: $(cat VERSION 2>/dev/null || echo 'Unknown')

This document provides comprehensive statistics about architectural pattern usage across the Powernode platform.

EOF

# Function to add statistics to file
add_stat() {
    local category="$1"
    local description="$2"
    local command="$3"
    local result=$(eval "$command" 2>/dev/null || echo "0")
    
    echo "- **$description**: $result" >> "$OUTPUT_FILE"
}

# Function to add section header
add_section() {
    local title="$1"
    echo "" >> "$OUTPUT_FILE"
    echo "## $title" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
}

# Backend Statistics
add_section "Backend Patterns"

add_stat "backend" "API Controllers with Api::V1 namespace" \
    "find server/app/controllers/api/v1 -name '*.rb' | wc -l"

add_stat "backend" "Controllers using success/error response format" \
    "grep -r 'success:' server/app/controllers/ | wc -l"

add_stat "backend" "Controllers with permission-based authorization" \
    "grep -r 'require_permission' server/app/controllers/ | wc -l"

add_stat "backend" "Controllers using serialization concerns" \
    "grep -r 'include.*Serialization' server/app/controllers/ | wc -l"

add_stat "backend" "Models with UUID primary keys" \
    "grep -r 'string :id, limit: 36' server/db/migrate/ | wc -l"

add_stat "backend" "Models using security concerns" \
    "grep -r 'include.*Security' server/app/models/ | wc -l"

add_stat "backend" "Models with permission methods" \
    "grep -r 'def has_permission?\|def all_permissions' server/app/models/ | wc -l"

add_stat "backend" "Service objects" \
    "find server/app/services -name '*.rb' | wc -l"

add_stat "backend" "Files with frozen_string_literal" \
    "find server/app -name '*.rb' -exec grep -l 'frozen_string_literal' {} \; | wc -l"

# Frontend Statistics  
add_section "Frontend Patterns"

add_stat "frontend" "Components using permission-based access" \
    "grep -r 'hasPermission\|permissions.*includes' frontend/src/ | wc -l"

add_stat "frontend" "Components using theme-aware classes" \
    "grep -r 'bg-theme-\|text-theme-\|border-theme' frontend/src/ | wc -l"

add_stat "frontend" "Components with forwardRef" \
    "grep -r 'forwardRef' frontend/src/ | wc -l"

add_stat "frontend" "Components with displayName" \
    "grep -r '\.displayName' frontend/src/ | wc -l"

add_stat "frontend" "TypeScript interface definitions" \
    "grep -r '^interface ' frontend/src/ | wc -l"

add_stat "frontend" "Custom hooks (useXxx)" \
    "find frontend/src -name 'use*.ts' -o -name 'use*.tsx' | wc -l"

add_stat "frontend" "API service files" \
    "find frontend/src -name '*Api.ts' -o -name '*api.ts' | wc -l"

# Worker Statistics
add_section "Worker Patterns"

add_stat "worker" "Jobs inheriting from BaseJob" \
    "grep -r '< BaseJob' worker/app/jobs/ | wc -l"

add_stat "worker" "Jobs using execute method" \
    "grep -r 'def execute' worker/app/jobs/ | wc -l"

add_stat "worker" "Jobs with API client usage" \
    "grep -r 'api_client\.' worker/app/jobs/ | wc -l"

add_stat "worker" "Jobs with retry logic" \
    "grep -r 'with_api_retry\|sidekiq_retry_in' worker/app/jobs/ | wc -l"

# Code Quality Statistics
add_section "Code Quality"

add_stat "quality" "Backend files missing frozen_string_literal" \
    "find server/app -name '*.rb' -exec grep -L 'frozen_string_literal' {} \; | wc -l"

add_stat "quality" "Worker files missing frozen_string_literal" \
    "find worker/app -name '*.rb' -exec grep -L 'frozen_string_literal' {} \; | wc -l"

add_stat "quality" "Debug statements in backend (should be 0)" \
    "grep -r 'puts \|p \|print ' server/app/ | wc -l"

add_stat "quality" "Console.log statements in frontend (should be 0)" \
    "grep -r 'console.log' frontend/src/ | wc -l"

add_stat "quality" "TypeScript any types" \
    "grep -r ': any' frontend/src/ | grep -v 'node_modules' | wc -l"

# Anti-Pattern Statistics (should be low/zero)
add_section "Anti-Patterns (Should be Zero)"

add_stat "antipattern" "Role-based access in frontend" \
    "grep -r '\.roles.*includes\|\.role.*==' frontend/src/ | grep -v 'formatRole\|member\.roles.*map' | wc -l"

add_stat "antipattern" "Hardcoded colors in frontend" \
    "grep -r 'bg-red-\|bg-blue-\|bg-green-\|text-black\|text-gray-' frontend/src/ | grep -v 'text-white' | wc -l"

add_stat "antipattern" "ApplicationJob inheritance in worker" \
    "grep -r '< ApplicationJob' worker/app/jobs/ | wc -l"

add_stat "antipattern" "ActiveRecord usage in worker" \
    "grep -r 'ActiveRecord' worker/app/ | grep -v 'comments\|# ActiveRecord' | wc -l"

add_stat "antipattern" "Direct perform method in worker jobs" \
    "grep -r 'def perform' worker/app/jobs/ | grep -v BaseJob | wc -l"

# Architecture Statistics
add_section "Architecture Overview"

add_stat "architecture" "Total Backend Controllers" \
    "find server/app/controllers -name '*.rb' | wc -l"

add_stat "architecture" "Total Models" \
    "find server/app/models -name '*.rb' | wc -l"

add_stat "architecture" "Total React Components" \
    "find frontend/src -name '*.tsx' | wc -l"

add_stat "architecture" "Total Worker Jobs" \
    "find worker/app/jobs -name '*.rb' | wc -l"

add_stat "architecture" "Total Database Migrations" \
    "find server/db/migrate -name '*.rb' | wc -l"

# Add footer
cat >> "$OUTPUT_FILE" << 'EOF'

## Pattern Compliance Summary

To check current compliance with these patterns, run:

```bash
# Comprehensive pattern audit
./scripts/pattern-validation.sh

# Quick development check
./scripts/quick-pattern-check.sh

# Pre-commit validation
./scripts/pre-commit-pattern-check.sh
```

## References

- [Platform Patterns Analysis](PLATFORM_PATTERNS_ANALYSIS.md)
- [MCP Documentation Enhancement Plan](MCP_DOCUMENTATION_ENHANCEMENT_PLAN.md)
- [Platform Standardization Recommendations](PLATFORM_STANDARDIZATION_RECOMMENDATIONS.md)

EOF

echo -e "${GREEN}✅ Pattern statistics generated: $OUTPUT_FILE${NC}"

# Also display a summary to console
echo ""
echo -e "${BLUE}=== Quick Statistics Summary ===${NC}"
echo "Backend Controllers (Api::V1): $(find server/app/controllers/api/v1 -name '*.rb' | wc -l)"
echo "Models with UUID: $(grep -r 'string :id, limit: 36' server/db/migrate/ | wc -l)"
echo "Frontend Permission Usage: $(grep -r 'hasPermission' frontend/src/ | wc -l)"
echo "Worker BaseJob Usage: $(grep -r '< BaseJob' worker/app/jobs/ | wc -l)"
echo ""
echo -e "${YELLOW}Anti-Patterns (should be 0):${NC}"
echo "Role-based access: $(grep -r '\.roles.*includes\|\.role.*==' frontend/src/ | grep -v 'formatRole\|member\.roles.*map' | wc -l)"
echo "Debug code: $(grep -r 'puts \|console\.log' server/app/ frontend/src/ | wc -l)"