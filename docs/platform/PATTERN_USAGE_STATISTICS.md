# Pattern Usage Statistics

**Generated**: $(date)  
**Platform Version**: $(cat VERSION 2>/dev/null || echo 'Unknown')

This document provides comprehensive statistics about architectural pattern usage across the Powernode platform.


## Backend Patterns

- **API Controllers with Api::V1 namespace**: 44
- **Controllers using success/error response format**: 535
- **Controllers with permission-based authorization**: 32
- **Controllers using serialization concerns**: 3
- **Models with UUID primary keys**: 20
- **Models using security concerns**: 1
- **Models with permission methods**: 8
- **Service objects**: 28
- **Files with frozen_string_literal**: 153

## Frontend Patterns

- **Components using permission-based access**: 105
- **Components using theme-aware classes**: 6480
- **Components with forwardRef**: 11
- **Components with displayName**: 182
- **TypeScript interface definitions**: 261
- **Custom hooks (useXxx)**: 18
- **API service files**: 33

## Worker Patterns

- **Jobs inheriting from BaseJob**: 25
- **Jobs using execute method**: 25
- **Jobs with API client usage**: 136
- **Jobs with retry logic**: 106

## Code Quality

- **Backend files missing frozen_string_literal**: 0
- **Worker files missing frozen_string_literal**: 0
- **Debug statements in backend (should be 0)**: 370
- **Console.log statements in frontend (should be 0)**: 47
- **TypeScript any types**: 320

## Anti-Patterns (Should be Zero)

- **Role-based access in frontend**: 18
- **Hardcoded colors in frontend**: 49
- **ApplicationJob inheritance in worker**: 0
- **ActiveRecord usage in worker**: 0
- **Direct perform method in worker jobs**: 1

## Architecture Overview

- **Total Backend Controllers**: 51
- **Total Models**: 57
- **Total React Components**: 215
- **Total Worker Jobs**: 32
- **Total Database Migrations**: 53

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

