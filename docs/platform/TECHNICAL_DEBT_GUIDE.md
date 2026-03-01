# Technical Debt Guide

> **Staleness Warning (2026-02-28)**: This document was last audited in Feb 2026. Several items are now resolved (e.g., 2FA is fully implemented, monitoring services consolidated). The counts and priorities below should be verified against the current codebase before acting on them.

**Comprehensive tracking, deprecation plans, and type improvements**

---

## Table of Contents

1. [Technical Debt Overview](#technical-debt-overview)
2. [Priority Categories](#priority-categories)
3. [High Priority: Missing Backend Integration](#high-priority-missing-backend-integration)
4. [High Priority: Security & Authentication](#high-priority-security--authentication)
5. [Medium Priority: Monitoring & Metrics](#medium-priority-monitoring--metrics)
6. [Medium Priority: Backend Features](#medium-priority-backend-features)
7. [Medium Priority: UI/UX Improvements](#medium-priority-uiux-improvements)
8. [Low Priority: Testing & Phase 2](#low-priority-testing--phase-2)
9. [Deprecation Plans](#deprecation-plans)
10. [TypeScript Improvements](#typescript-improvements)
11. [Cleanup Strategy](#cleanup-strategy)

---

## Technical Debt Overview

### Summary Statistics

| Metric | Count |
|--------|-------|
| **Total Items** | 59 |
| **Critical (Security)** | 1 (2FA resolved) |
| **High Priority** | 8 |
| **Medium Priority** | 38 |
| **Low Priority** | 11 |

### Category Distribution

| Category | Count | Priority |
|----------|-------|----------|
| Missing Backend Integration | 8 | High |
| Security & Authentication | 4 | High |
| UI/UX Improvements | 10 | Medium |
| Monitoring & Metrics | 17 | Medium |
| Backend Features | 11 | Medium |
| Testing Improvements | 7 | Low |
| Workflow System Phase 2 | 3 | Low |

### Estimated Effort

- **Small** (~20 items): 1-4 hours each
- **Medium** (~30 items): 4-16 hours each
- **Large** (~9 items): 16+ hours each

---

## Priority Categories

### Immediate Action Required
1. ~~**Two-Factor Authentication**~~ ✅ Resolved — fully implemented
2. **Worker Service Authentication** - Security vulnerability
3. **Missing Backend Integration** - Core functionality gaps
4. **Worker Activity Logging Fix** - Currently disabled

### Short-term (1-2 Sprints)
1. **Monitoring & Metrics** - Complete unified monitoring
2. **Backend Features** - JWT rotation, maintenance mode
3. **UI/UX Improvements** - Enhanced user experience

### Long-term (Deferred)
1. **Testing Improvements** - Better test coverage
2. **Workflow System Phase 2** - Planned feature release

---

## High Priority: Missing Backend Integration

### API Endpoints Needed

**File**: `frontend/src/pages/app/ApiKeysPage.tsx` (lines 33-34)
```typescript
// TODO: Get from backend
apiUptime: '99.9%',
avgResponseTime: '45ms'
```
- **Impact**: Cannot display real API performance metrics
- **Effort**: Medium - Requires backend endpoint + metrics collection

**File**: `frontend/src/features/system/components/WorkerManagement.tsx` (line 26)
- **Issue**: Worker statistics endpoint not implemented
- **Impact**: Worker management page missing real-time stats
- **Effort**: Medium - Requires worker service API integration

**File**: `frontend/src/features/audit-logs/components/AuditLogExport.tsx` (line 110)
- **Issue**: Export API not implemented
- **Impact**: Cannot export audit logs
- **Effort**: Small - Simple export endpoint needed

**File**: `frontend/src/features/reports/services/reportsService.ts` (line 209)
- **Issue**: New report request format not ready
- **Impact**: Using old report format
- **Effort**: Small - API format change

### Missing Feature Implementations

**File**: `frontend/src/features/ai-providers/components/AiProviderCard.tsx` (line 181)
- **Issue**: Delete provider functionality not implemented
- **Impact**: Cannot delete AI providers from UI
- **Effort**: Small - Add delete confirmation + API call

**File**: `frontend/src/features/ai-agents/components/EditAgentModal.tsx` (line 263)
- **Issue**: Agent status toggle not implemented
- **Impact**: Cannot enable/disable agents
- **Effort**: Small - Add toggle handler + API endpoint

**File**: `frontend/src/pages/app/business/CustomersPage.tsx` (line 169)
- **Issue**: Add customer modal not implemented
- **Impact**: Cannot add customers from UI
- **Effort**: Medium - Create modal + form + validation + API

**File**: `frontend/src/pages/app/ai/WorkflowTemplatesPage.tsx` (line 268)
- **Issue**: Template details modal not implemented
- **Impact**: Cannot view template details
- **Effort**: Medium - Create details view

---

## High Priority: Security & Authentication

### ~~Two-Factor Authentication~~ ✅ RESOLVED

~~**File**: `server/app/controllers/api/v1/settings_controller.rb`~~
- **Status**: Fully implemented via `two_factors_controller.rb` with TOTP, backup codes, and setup verification
- **Resolved**: 2FA is production-ready with enable/disable/verify/backup-codes endpoints

### Worker Authentication

**File**: `server/app/controllers/api/v1/internal/workers_controller.rb` (line 74)
```ruby
# TODO: Implement proper worker service authentication
```
- **Impact**: Worker service authentication not fully implemented
- **Effort**: Medium - Add authentication middleware
- **Priority**: High (security issue)

### Legacy Authentication Removal Plan

**Status**: Planned - Post Phase 3

**Current State**: Dual authentication systems exist:
- **UserToken System** (NEW - Primary): Fully implemented, database-backed
- **JWT System** (LEGACY): Still active for backward compatibility

**Migration Steps**:
1. Audit codebase for JWT usage
2. Validate UserToken coverage
3. Add deprecation warnings (30-60 day timeline)
4. Remove JWT fallback logic
5. Archive JwtService, remove jwt gem

**Files Requiring Changes**:
- `server/app/controllers/api/v1/impersonations_controller.rb` (lines 190-242)
- `server/app/services/jwt_service.rb` (archive/remove)
- `server/Gemfile` (remove jwt gem)

---

## Medium Priority: Monitoring & Metrics

### Unified Monitoring Service

**File**: `server/app/services/unified_monitoring_service.rb`

**Circuit Breaker Monitoring** (line 464):
```ruby
# TODO: Implement circuit breaker status check
```

**Performance Metrics**:
- Line 533: `# TODO: Implement conversation response time tracking`
- Line 602: `# TODO: Implement RPS calculation`
- Line 607: `# TODO: Implement active connections count`

**Cost Analytics**:
- Line 551: `# TODO: Implement detailed cost breakdown by provider`
- Line 556: `# TODO: Implement detailed cost breakdown by agent`
- Line 561: `# TODO: Implement detailed cost breakdown by workflow`
- Line 566: `# TODO: Implement cost trend calculation`

**System Metrics**:
- Line 592: `# TODO: Implement memory metrics collection`
- Line 597: `# TODO: Implement CPU metrics collection`
- Line 612: `# TODO: Implement error metrics collection`

### Base Monitoring Service

**File**: `server/app/services/concerns/base_monitoring_service.rb`
- Line 386: `# TODO: Implement proper uptime tracking`
- Line 436: `# TODO: Implement alert notifications (email, SMS, etc.)`

### Monitoring Service Deprecation

**Status**: Ready for Execution

**Deprecated Services**:
- ❌ `AiMonitoringService` → Replace with `UnifiedMonitoringService`
- ❌ `AiComprehensiveMonitoringService` → Replace with `UnifiedMonitoringService`

**Current Usage** (2 instances):
1. `AiAgentOrchestrationService` (line 79) - Instantiated but never used - **REMOVE**
2. Integration Test Mock (line 352) - **UPDATE to UnifiedMonitoringService**

**Risk Level**: 🟢 LOW RISK

---

## Medium Priority: Backend Features

### Controller Features

**File**: `server/app/controllers/api/v1/admin_settings_controller.rb`

**JWT Management** (line 265):
```ruby
# TODO: Implement JWT secret regeneration
```
- **Impact**: Cannot rotate JWT secrets
- **Effort**: Medium - Requires careful security implementation

**Settings Metadata** (lines 420-421):
```ruby
created_at: 30.days.ago, # TODO: Store actual settings creation time
updated_at: 1.day.ago # TODO: Store actual settings update time
```

**Maintenance Mode** (line 469):
```ruby
maintenance_mode: false, # TODO: Implement maintenance mode
```
- **Impact**: Cannot put system in maintenance mode
- **Effort**: Medium - Requires middleware + admin UI

**Webhook Tracking** (line 715):
```ruby
# TODO: Implement webhook event tracking
```

**File**: `server/app/controllers/api/v1/workers_controller.rb` (line 64)
```ruby
# TODO: Fix activity logging - temporarily disabled due to error
```
- **Impact**: Worker activity not logged
- **Effort**: Small - Debug and re-enable logging

### Model Features

**Files**: `server/app/models/app_subscription.rb`, `marketplace_listing.rb` (line 4)
```ruby
# include AuditLogging # TODO: Enable when AuditLogging concern is available
```
- **Impact**: Missing audit trails for subscriptions and listings

### Service Features

**File**: `server/app/services/concerns/base_workflow_service.rb` (line 208)
```ruby
# TODO: Implement more robust expression evaluation
```
- **Impact**: Limited workflow condition evaluation
- **Effort**: Large - Requires expression parser

---

## Medium Priority: UI/UX Improvements

### Feature Enhancements

**File**: `frontend/src/features/subscriptions/components/SubscriptionStatusIndicator.tsx` (line 15)
- **Issue**: Enhanced trial and expiration indicators not used
- **Effort**: Small - Add conditional styling

**File**: `frontend/src/pages/app/marketplace/AppDetailPage.tsx` (lines 49, 53)
- **Issue**: Publish/unpublish functionality not implemented
- **Effort**: Medium - Add API endpoints + state management

**File**: `frontend/src/pages/app/admin/AdminMarketplacePage.tsx` (lines 102, 542)
- **Issue**: Export and navigation features missing
- **Effort**: Small - Add export handler + routing

**File**: `frontend/src/features/admin/components/PlanFeaturesManager.tsx` (line 823)
- **Issue**: Feature comparison export not implemented
- **Effort**: Small - Add export handler

**File**: `frontend/src/pages/app/UsersPage.tsx` (line 859)
- **Issue**: User actions dropdown menu missing
- **Effort**: Small - Add dropdown component

### Pagination & Navigation

**File**: `frontend/src/features/marketplace/components/webhooks/WebhooksList.tsx` (lines 334, 344)
- **Issue**: Webhook list pagination handlers missing
- **Effort**: Small - Add pagination handlers

### Analytics Display

**File**: `frontend/src/pages/app/business/AnalyticsPage.tsx` (lines 271, 293, 397)
- **Issue**: Last updated timestamp not displayed
- **Effort**: Very Small - Uncomment and display timestamp

**File**: `frontend/src/shared/services/ai/WorkflowsApiService.ts` (line 283)
- **Issue**: Average execution time calculation missing
- **Effort**: Small - Add calculation logic

---

## Low Priority: Testing & Phase 2

### Test Assertions

**File**: `frontend/src/features/admin/components/settings/EmailConfiguration.test.tsx`
- Lines 279, 301, 340, 361, 376 - Missing Redux store assertions
- **Effort**: Small - Add Redux assertions

**File**: `frontend/src/features/payment-gateways/components/GatewayConfigModal.test.tsx`
- Lines 279, 308 - Missing Redux store assertions
- **Effort**: Small - Add Redux assertions

### Workflow System Phase 2

**File**: `server/app/services/mcp/workflow_orchestrator.rb`
- Lines 1154, 1159, 1165 - Phase 2 features not yet implemented
- **Note**: Deferred to Phase 2 development cycle

---

## Deprecation Plans

### Monitoring Services

**Timeline**:
- Phase 1 ✅: Deprecation warnings added
- Phase 2 ✅: Migration guide created
- Phase 3 ⚡: Identify and fix dependencies (Current)
- Phase 4: Remove obsolete services (v2.0)

**Migration Checklist**:
- [ ] Remove unused `@monitoring_service` from AiAgentOrchestrationService
- [ ] Update integration test to use UnifiedMonitoringService
- [ ] Run and verify all tests pass
- [ ] No grep matches for deprecated services in app/

### Legacy Authentication

**Timeline** (Post Phase 3):
- Week 1: Analysis & Preparation
- Week 2-3: Deprecation Period (add warnings, monitor)
- Week 4-5: Grace Period
- Week 6: Legacy Removal
- Week 7: Validation

**Success Criteria**:
- [ ] No JWT references in active codebase
- [ ] All authentication flows use UserToken
- [ ] JWT gem removed from Gemfile
- [ ] All tests passing without JWT

---

## TypeScript Improvements

### Objective

Replace unsafe `any` types with proper TypeScript types for better type safety and IDE support.

### Files Modified

**1. `/src/features/admin/services/adminApi.ts`**
- Created `PaymentGateway` interface
- Updated `AdminSettingsData.payment_gateways` type
- Updated `updateUserStatus` return type to `AdminUser`
- Updated `getGlobalAnalytics` return type with proper structure

**2. `/src/features/admin/services/servicesApi.ts`**
- Updated `getJobStatus` interface (parameters, result, error_details)
- Updated `pollJobUntilComplete` signatures

**3. `/src/features/admin/services/adminSettingsApi.ts`**
- Updated `updateSecurityConfig` return type

### Type Safety Guidelines

**When to use each type**:

1. **`unknown`**: For truly dynamic data
   ```typescript
   result?: unknown // Job results can be any shape
   ```

2. **`Record<string, unknown>`**: For object-like data with unknown properties
   ```typescript
   config: Record<string, unknown>
   ```

3. **Specific interfaces**: When structure is known
   ```typescript
   payment_gateways: PaymentGateway[]
   ```

### Acceptable Remaining `any` Types

- **Dynamic Metadata Fields**: `metadata: Record<string, any>` for audit logs
- **Error Catch Blocks**: `catch (error: any)` - TypeScript limitation
- **Third-Party Library Types**: External libraries without proper types
- **Test Mock Functions**: Test code, not production

### Results

| Metric | Count |
|--------|-------|
| Files Modified | 3 |
| `any` Types Eliminated | 9 |
| New Interfaces Created | 1 (PaymentGateway) |
| Admin Services Type Safety | 100% |

---

## Cleanup Strategy

### Items That Can Be Removed

- Commented-out code in AnalyticsPage (lastUpdated state) if not needed
- Placeholder buttons/handlers that aren't planned for implementation

### Items Requiring Decisions

- **Worker stats endpoint**: Implement or remove functionality?
- **Webhook pagination**: Is this feature still needed?
- **Export features**: Which exports are actually required?

### Tracking Guidelines

**When Adding New TODOs**:
1. Use descriptive TODO comments with context
2. Include estimated effort (Small/Medium/Large)
3. Link related TODOs together
4. Update this document monthly

**When Completing TODOs**:
1. Remove TODO comment from code
2. Mark item as completed in this document
3. Add completion date
4. Reference PR/commit that resolved it

---

## Quick Reference Commands

```bash
# Find TODO comments
grep -r "TODO" server/app/ frontend/src/ --include="*.rb" --include="*.ts" --include="*.tsx"

# Find JWT usage (for legacy auth removal)
grep -r "JwtService" server/app/
grep -r "JWT::" server/app/

# Find deprecated monitoring services
grep -r "AiMonitoringService\|AiComprehensiveMonitoringService" server/app/

# TypeScript any types
grep -r ": any" frontend/src/ | grep -v "node_modules"

# Run pre-commit checks
./scripts/pre-commit-quality-check.sh
```

---

**Document Status**: ✅ Complete
**Consolidates**: TODO_TECHNICAL_DEBT.md, TYPESCRIPT_ANY_TYPE_IMPROVEMENTS.md, MONITORING_SERVICE_DEPRECATION_PLAN.md, LEGACY_AUTHENTICATION_REMOVAL_PLAN.md
**Last Updated**: Auto-generated
**Next Review**: Monthly

