# Integration Test Improvement Roadmap

**Date**: November 26, 2025
**Current Status**: 42% pass rate (62/143 estimated tests)
**Baseline**: 35% pass rate (44/125 tests)
**Improvement**: +20% (+18 tests)

**Source**: Sprint 1 Days 3-4 continuation session findings

---

## Executive Summary

This roadmap provides a prioritized action plan for improving integration test pass rates based on systematic investigation during the Sprint 1 Days 3-4 continuation session. Work is categorized by effort level and impact, with clear time estimates and success criteria.

---

## ✅ Completed Work (Session Results)

### Quick Win #1: MCP Tool Execution Model - 100% ✅
- **Improvement**: 83% → 100% (+5 tests)
- **Time**: 15 minutes
- **Issues Fixed**: Redundant presence validation, column name mismatch
- **Status**: COMPLETE - First 100% integration test achievement

### Quick Win #2: Workflow Validations Association - 60% ✅
- **Improvement**: 30% → 60% (+6 tests)
- **Time**: 30 minutes
- **Issues Fixed**: Missing `has_many :workflow_validations` association
- **Status**: COMPLETE - All 500 errors resolved

### Quick Win #3: Database Constraint & Association Names - 80% ✅
- **Improvement**: 60% → 80% (+4 tests)
- **Time**: 45 minutes
- **Issues Fixed**: Database constraint (13 → 38 types), controller association names
- **Status**: COMPLETE - Major architectural alignment

### Partial Quick Win #4: MCP Tools - 39% ⚠️
- **Improvement**: 0% → 39% (+7 tests)
- **Time**: 30 minutes
- **Issues Fixed**: Missing Account association, factory trait status
- **Status**: PARTIAL - Blocking issues resolved, 8 tests remain
- **Remaining Work**: 3-6 hours (controller investigation)

---

## 🎯 Prioritized Improvement Opportunities

### Tier 1: Quick Wins (1-2 hours each)

#### 1.1 Workflow Validations Test Helper - 100% Goal
**Priority**: MEDIUM
**Current**: 80% (16/20 tests)
**Target**: 100% (20/20 tests)
**Remaining**: 4 tests
**Estimated Time**: 1-2 hours

**Issue**: `expect_success_response` helper hardcoded to expect status 200, but controller returns 201 for successful filtered index responses.

**Investigation Needed**:
- Review `spec/support/auth_helpers.rb:55` implementation
- Determine if helper should accept both 200 and 201
- Or if controller should return 200 instead of 201
- Consider impact on other test suites using this helper

**Risk Level**: MEDIUM (shared test infrastructure)

**Success Criteria**:
- All 4 GET filtering tests pass
- No regressions in other test suites using same helper
- Clear documentation of status code conventions

**Files to Review**:
- `spec/support/auth_helpers.rb` (line 55)
- `app/controllers/api/v1/ai/workflow_validations_controller.rb` (index action)
- `spec/requests/api/v1/ai/workflow_validations_spec.rb` (filtering tests)

---

### Tier 2: Medium-Term Work (3-6 hours each)

#### 2.1 MCP Tools Full Implementation - 100% Goal ⚠️
**Priority**: HIGH (Feature Currently Broken)
**Current**: 39% (7/18 tests)
**Target**: 100% (18/18 tests)
**Remaining**: 8 tests (6 with 500 errors, 1 with 404, 1 calculation error)
**Estimated Time**: 3-6 hours

**Issues Discovered**:

**Issue A: Controller 500 Errors** (6 tests)
- Tests: GET index, GET show, POST execute (3 variations)
- Pattern: All return 500 Internal Server Error
- Investigation: Read `app/controllers/api/v1/mcp_tools_controller.rb`
- Likely: Missing methods, undefined variables, or implementation gaps

**Issue B: Filtering 404 Error** (1 test)
- Test: GET index with enabled status filter
- Pattern: Expected 200, got 404
- Investigation: Check if `enabled` column exists on McpTool model
- Possible: Missing scope or filtering logic

**Issue C: Stats Calculation Error** (1 test)
- Test: GET stats endpoint
- Pattern: Expected `success_count: 5`, got `success_count: 0`
- Root Cause: Stats query likely looking for `status = 'success'` instead of `status = 'completed'`
- Investigation: Read stats endpoint calculation logic

**Risk Level**: LOW (feature already partially broken)

**Success Criteria**:
- All 18 tests passing
- MCP Tools feature fully functional
- Stats calculations accurate

**Files to Investigate**:
- `app/controllers/api/v1/mcp_tools_controller.rb` (primary)
- `app/models/mcp_tool.rb` (check for enabled column/scope)
- Stats calculation service or method

**Documentation**: `docs/platform/MCP_TOOLS_PARTIAL_QUICK_WIN.md`

---

#### 2.2 Circuit Breaker Filtering - 100% Goal
**Priority**: MEDIUM
**Current**: 79% (19/24 tests)
**Target**: 100% (24/24 tests)
**Remaining**: 5 tests
**Estimated Time**: 2-4 hours

**Issue**: All 5 failing tests return 422 validation errors during GET requests with query parameters.

**Pattern**: Similar to Validation Rules filtering issues (same architectural problem)

**Investigation Needed**:
- Review query parameter validation in circuit breaker controller
- Check if filtering scopes properly defined
- Verify factory setup for filtered scenarios

**Risk Level**: LOW (isolated feature)

**Success Criteria**:
- All filtering tests pass
- Query parameter validation working correctly

**Files to Review**:
- `app/controllers/api/v1/admin/circuit_breakers_controller.rb`
- `spec/requests/api/v1/admin/circuit_breakers_spec.rb`
- `spec/factories/circuit_breakers.rb`

---

#### 2.3 Validation Rules Filtering - 80%+ Goal
**Priority**: MEDIUM
**Current**: 48% (11/23 tests)
**Target**: 80%+ (18+/23 tests)
**Remaining**: 12 tests
**Estimated Time**: 3-5 hours

**Issue**: Mix of 500 and 422 errors - identical pattern to Circuit Breakers

**Investigation Needed**:
- Same approach as Circuit Breakers
- Likely shares same root cause (query parameter validation)

**Risk Level**: LOW (isolated feature)

**Success Criteria**:
- At least 80% pass rate achieved
- Filtering logic working correctly

---

### Tier 3: Large-Scale Work (8+ hours each)

#### 3.1 MCP Servers Implementation - 70%+ Goal
**Priority**: MEDIUM
**Current**: 29% (5/17 tests)
**Target**: 70%+ (12+/17 tests)
**Remaining**: 12 tests
**Estimated Time**: 6-10 hours

**Issue**: Multiple 500 errors, missing methods, incomplete implementation

**Investigation Needed**:
- Full feature implementation review
- Check for missing controller actions
- Verify model associations and validations
- Test factory completeness

**Risk Level**: MEDIUM (larger feature)

**Success Criteria**:
- Core CRUD operations working (minimum 70%)
- Clear documentation of remaining incomplete features

---

## 📊 Projected Impact

### If All Tier 1 Completed (1-2 hours work)
- **Pass Rate**: 42% → ~44%
- **Tests Fixed**: +4
- **Features**: Workflow Validations at 100%

### If All Tier 1 + Tier 2 Completed (10-17 hours work)
- **Pass Rate**: 42% → ~55%
- **Tests Fixed**: +24
- **Features**: Workflow Validations 100%, MCP Tools 100%, Circuit Breakers 100%, Validation Rules 80%+

### If All Tiers Completed (18-27 hours work)
- **Pass Rate**: 42% → ~65%
- **Tests Fixed**: +36
- **Features**: All major features at 70%+ pass rate

---

## 🔧 Recommended Approach

### Phase 1: Quick Wins (1-2 hours)
1. Start with Workflow Validations test helper fix
2. Low risk, high confidence
3. Achieves first 100% feature completion

### Phase 2: Feature Unblocking (6-12 hours)
1. Complete MCP Tools (HIGH priority - feature broken)
2. Fix Circuit Breakers filtering
3. Fix Validation Rules filtering

### Phase 3: Large Features (8-10 hours)
1. MCP Servers implementation
2. Other incomplete features as discovered

---

## 🎓 Lessons from Sprint 1 Days 3-4 Session

### Quick Win Patterns
1. **Look for high pass rates** (70%+) with few failures
2. **Clear error messages** indicate isolated issues
3. **Missing associations** are classic quick wins
4. **Factory validation issues** are fast fixes
5. **Database constraint mismatches** can be architectural wins

### Stopping Criteria
1. Time investment approaches 1 hour without resolution
2. Remaining issues have multiple different root causes
3. All passing tests are authorization only (feature logic broken)
4. Would require 3+ hours of controller/service investigation
5. Document partial success and create dedicated task

### Investigation Process
1. Run failing tests with `--fail-fast --backtrace`
2. Check test log for actual errors
3. Read relevant models/controllers
4. Document findings before fixing
5. Apply minimal targeted changes
6. Verify with full test run
7. Stop if new issues emerge

---

## 📁 Related Documentation

### Session Documentation
- **Session Summary**: `docs/platform/SPRINT_1_DAYS_3_4_CONTINUATION_COMPLETE.md`
- **Baseline Report**: `docs/platform/SPRINT_1_INTEGRATION_TESTING_COMPLETE.md`

### Quick Win Documentation
- **Quick Win #1**: `docs/platform/MCP_TOOL_EXECUTION_MODEL_FIXES.md`
- **Quick Win #2**: `docs/platform/WORKFLOW_VALIDATIONS_ASSOCIATION_FIX.md`
- **Quick Win #3**: `docs/platform/WORKFLOW_VALIDATIONS_CONSTRAINT_AND_ASSOCIATION_FIXES.md`
- **Partial Quick Win #4**: `docs/platform/MCP_TOOLS_PARTIAL_QUICK_WIN.md`

---

## 🚀 Next Steps

### Immediate (Next Session)
1. **Option A**: Complete Workflow Validations test helper fix (1-2 hours)
   - Achieves first 100% feature
   - Shared infrastructure improvement
   - Low risk

2. **Option B**: Complete MCP Tools implementation (3-6 hours)
   - HIGH priority (feature currently broken)
   - Builds on partial quick win work
   - Clear roadmap from investigation

3. **Option C**: Circuit Breakers + Validation Rules (5-9 hours)
   - Similar issues, can be tackled together
   - Pattern learning opportunity

### Recommended Sequence
1. Workflow Validations (quick confidence builder)
2. MCP Tools (highest priority - broken feature)
3. Circuit Breakers + Validation Rules (similar patterns)
4. MCP Servers (large feature work)

---

## ✅ Success Metrics

### Sprint Goal
**Target**: 50% integration test pass rate
**Current**: 42%
**Remaining**: +8% (+~11 tests)
**Recommended**: Complete Tier 1 + MCP Tools from Tier 2

### Long-Term Goal
**Target**: 70%+ integration test pass rate
**Current**: 42%
**Remaining**: +28% (+~40 tests)
**Recommended**: Complete all Tier 1 + Tier 2 work

---

*Roadmap created from Sprint 1 Days 3-4 continuation session findings. All estimates based on observed patterns during systematic investigation. Use established quick win process for best results.*
