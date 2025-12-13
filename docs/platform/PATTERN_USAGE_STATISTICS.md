# Pattern Usage Statistics

**Generated**: $(date)  
**Platform Version**: $(cat VERSION 2>/dev/null || echo 'Unknown')

This document provides comprehensive statistics about architectural pattern usage across the Powernode platform.


## Backend Patterns

- **API Controllers with Api::V1 namespace**: 107
- **Controllers using success/error response format**: 29
- **Controllers with permission-based authorization**: 110
- **Controllers using serialization concerns**: 3
- **Models with UUID primary keys**: 0
- **Models using security concerns**: 1
- **Models with permission methods**: 8
- **Service objects**: 158
- **Files with frozen_string_literal**: 439

## Frontend Patterns

- **Components using permission-based access**: 285
- **Components using theme-aware classes**: 12784
- **Components with forwardRef**: 13
- **Components with displayName**: 4
- **TypeScript interface definitions**: 504
- **Custom hooks (useXxx)**: 44
- **API service files**: 45

## Worker Patterns

- **Jobs inheriting from BaseJob**: 66
- **Jobs using execute method**: 85
- **Jobs with API client usage**: 301
- **Jobs with retry logic**: 136

## Code Quality

- **Backend files missing frozen_string_literal**: 0
- **Worker files missing frozen_string_literal**: 0
- **Debug statements in backend (should be 0)**: 989
- **Console.log statements in frontend (should be 0)**: 14
- **TypeScript any types**: 456

## Anti-Patterns (Should be Zero)

- **Role-based access in frontend**: 26
- **Hardcoded colors in frontend**: 32
- **ApplicationJob inheritance in worker**: 0
- **ActiveRecord usage in worker**: 5
- **Direct perform method in worker jobs**: 2

## Architecture Overview

- **Total Backend Controllers**: 117
- **Total Models**: 135
- **Total React Components**: 526
- **Total Worker Jobs**: 81
- **Total Database Migrations**: 76

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

