# Trading Feature Audit — Code Quality & Architecture

**Date:** 2026-03-31
**Scope:** Full trading extension — backend models, services, controllers, jobs, evaluators, frontend components
**Status:** **CLOSED** — all 32 findings remediated (2026-03-31 through 2026-04-01)
**Companion:** See `TRADING_EFFICIENCY_AUDIT.md` for runtime performance bottlenecks (separate scope)

### Remediation Summary (10 phases)
| Phase | Findings | Key Changes |
|-------|----------|-------------|
| 1 | M4,M11,M13,M15,L1,L2,L5 | LogFormatter, constants, CHECK constraints, error boundaries |
| 2 | C5,C6,C7,C8 | Safety-critical error handling fixes |
| 3 | M5,M6,M7 | N+1 query fixes, SQL optimization |
| 4 | H14,H15 | AASM state machines, held→status merge |
| 5 | M1,M2,L3,L4 | AdapterFactory (29 locations), VenueLifecycleService |
| 6 | H13,M12,L6,L7 | tradingApi.ts split (8 modules), React Query hooks, skeletons |
| 7 | H8,H9,H10,H11 | Controller/concern decomposition (3+4 files) |
| 8 | H3,H6,H7,M14 | Model/adapter/job decomposition, TradingJobBase |
| 9 | H12 | Frontend component decomposition (5→29 sub-components) |
| 10 | C1,C2,C3,C4,H1,H2,H4,H5,M8-M10 | God objects, service decomposition, JSON validation |

---

## 1. Dashboard

### Finding Summary

| Severity | Backend Models/Services | Controllers/Jobs | Frontend | Total |
|----------|------------------------|-------------------|----------|-------|
| Critical | 4 | 1 | 1 | **6** |
| High | 7 | 4 | 2 | **13** |
| Medium | 5 | 2 | 3 | **10** |
| Low | 2 | 0 | 1 | **3** |
| **Total** | **18** | **7** | **7** | **32** |

### Codebase Metrics

| Metric | Value |
|--------|-------|
| Files exceeding 500 lines | 19 |
| Files exceeding 1,000 lines | 8 |
| Largest single file | `live_training_runner.rb` — 3,869 lines |
| Largest single job | `trading_training_session_job.rb` — 2,136 lines |
| Largest frontend file | `tradingApi.ts` — 1,821 lines |
| Overseer concern total | 6,266 lines across 6 concerns |
| Evaluator files | 32 evaluators + 16 concern mixins |

### What Is Working Well

| Area | Detail |
|------|--------|
| Authorization | All endpoints gated with `trading.view/execute/manage/admin/publish/subscribe` |
| TypeScript quality | No `any` types, no `console.log`, strong typing throughout |
| Route structure | Well-organized REST, no dead routes, clean namespace separation |
| DB schema | UUID consistent, decimal precision correct, good index coverage |
| Evaluator architecture | 32 evaluators with 16 well-composed concern mixins |
| Context pattern | `TradingPortfolioContext` properly scoped with localStorage persistence |
| Response format | All controllers use `render_success()`/`render_error()` consistently |

---

## 2. Critical Findings

### 2.1 God Objects — Backend Services

| ID | File | Lines | Issue | Recommendation |
|----|------|-------|-------|----------------|
| C1 | `server/app/services/trading/live_training_runner.rb` | 3,869 | 73 methods — handles market discovery, scoring, strategy creation, learning extraction | Split into `MarketDiscoveryOrchestrator`, `MarketScoringEngine`, `StrategyCreationPipeline`, `LearningExtractor` |
| C2 | `server/app/services/trading/strategy_engine.rb` | 1,398 | 141 conditionals — monolithic tick executor mixing signal eval, order processing, position updates, risk checks | Extract `SignalEvaluator`, `OrderProcessor`, `PositionUpdater`, `RiskChecker` |
| C3 | `worker/app/jobs/trading_training_session_job.rb` | 2,136 | Megajob: tick cache, event listener, session locking, tick loop, profit hunter, rebalancing, state machine | Extract focused collaborators; keep job as thin orchestrator |
| C4 | Overseer concerns (6 files) | 6,266 | Single `BaseDecisionEngine` mixed with 6 massive concerns | Decompose into standalone service objects with explicit interfaces |

**Overseer concern breakdown:**

| Concern | Lines |
|---------|-------|
| `overseer/strategy_lifecycle.rb` | 2,071 |
| `overseer/decision_execution.rb` | 1,322 |
| `overseer/scheduling.rb` | 1,149 |
| `overseer/session_evaluation.rb` | 661 |
| `overseer/promotion_and_advancement.rb` | 598 |
| `overseer/position_safety.rb` | 465 |

### 2.2 Missing Error Handling (Safety-Critical)

| ID | Location | Behavior | Risk | Recommendation |
|----|----------|----------|------|----------------|
| C5 | VenueAdapter `cancel_order` loops | Swallows exceptions silently in `rescue StandardError` | Failed cancellations undetected; positions remain open | Re-raise or return error result object |
| C6 | `StrategyFactoryService` transaction | No rollback on agent/ralph_loop creation failures | Orphaned strategy records with missing dependencies | Wrap full creation chain in single atomic transaction |
| C7 | `LiveTrainingRunner#finalize` | Collects errors into array but marks session `completed` | Sessions marked complete despite partial failures | Introduce `completed_with_errors` state |
| C8 | `RiskManagerService` | Silently skips when `risk_profile` missing | Strategies trade without risk limits | Raise explicit error; require profile before trading |

---

## 3. High Findings

### 3.1 Oversized Backend Files (>400 lines, not in Critical)

| ID | File | Lines | Issue | Recommendation |
|----|------|-------|-------|----------------|
| H1 | `services/trading/strategy_parameter_service.rb` | 771 | 4-layer parameter resolution in single class | Extract per-layer resolvers |
| H2 | `services/trading/strategy_intelligence_service.rb` | 751 | 40+ methods managing scorecard state via shared memory | Split into `ScoreCalculator`, `StateManager`, `MemoryAdapter` |
| H3 | `models/trading/strategy.rb` | 722 | God model: lifecycle, PnL calc, versioning, overseer recommendations | Extract `StrategyLifecycleService`, `StrategyCalculationService` |
| H4 | `services/trading/risk_manager_service.rb` | 641 | Large service with silent-skip behavior | Decompose by risk check type; make skip behavior explicit |
| H5 | `services/trading/strategy_context_builder.rb` | 452 | Overloaded context assembly | Builder pattern with pluggable context providers |
| H6 | `models/trading/training_session.rb` | 452 | Multiple state machine paths, complex cleanup logic | Extract `TrainingSessionCleanupService` |
| H7 | `venue_adapter/prediction_market/kalshi_adapter.rb` | 1,495 | Largest adapter; mixes API, paper trading, market discovery | Split into `KalshiApiClient`, `KalshiPaperTrading`, `KalshiMarketDiscovery` |

### 3.2 Oversized Controllers & Concerns

| ID | File | Lines | Actions | Recommendation |
|----|------|-------|---------|----------------|
| H8 | `controllers/.../portfolios_controller.rb` | 645 | 26 | Split into `PortfoliosCrudController` + `PortfoliosAnalyticsController` |
| H9 | `controllers/.../overseer_controller.rb` | 512 | 25 | Extract cycle/decision actions into separate controller |
| H10 | `controllers/.../training_sessions_controller.rb` | 438 | 19 | Extract lifecycle actions into concern |
| H11 | `concerns/trading/internal/training_lifecycle_actions.rb` | 975 | — | Concern is larger than most controllers; decompose into Initializer, Runner, Finalizer |

### 3.3 Oversized Frontend Components

| ID | File | Lines | Issue | Recommendation |
|----|------|-------|-------|----------------|
| H12 | `StrategyPreviewModal.tsx` | 943 | 35+ hooks/state vars in single component | Extract tab panels into sub-components; use `useReducer` |
| H13 | `tradingApi.ts` | 1,821 | 175 exports, no error handling, no caching, no cancellation | Split by domain; add error wrapper and `AbortController` |

**Additional oversized frontend files (part of H12):**

| File | Lines |
|------|-------|
| `StrategyLifecyclePipeline.tsx` | 867 |
| `TrainingDetailPanel.tsx` | 798 |
| `CreateTrainingSessionModal.tsx` | 747 |
| `PortfolioPage.tsx` | 707 |
| `TrainingListPanel.tsx` | 664 |
| `TradingCommandCenter.tsx` | 487 |
| `CapitalConfigSection.tsx` | 481 |
| `ApprovalQueue.tsx` | 474 |
| `VenueCredentialsSection.tsx` | 448 |
| `OverseerHeartbeat.tsx` | 443 |

### 3.4 State Machine Anti-Patterns

| ID | Model | Issue | Recommendation |
|----|-------|-------|----------------|
| H14 | Strategy | Overlapping `status` and `lifecycle_phase` columns create ambiguous state | Consolidate into single state machine or define explicit valid combinations with DB constraint |
| H15 | TrainingSession | Orthogonal `status` + `held` columns allow contradictory states | Merge `held` into status enum or add CHECK constraint enforcing valid pairs |

---

## 4. Medium Findings

### 4.1 Duplicated Logic (Backend)

| ID | Pattern | Occurrences | Recommendation |
|----|---------|-------------|----------------|
| M1 | Adapter instantiation (`venue.adapter_class.constantize.new`) | 5 locations | Extract `AdapterFactory` with registry pattern |
| M2 | `activate_venue!` / `deactivate_venue!` | 3 locations | Consolidate into `VenueLifecycleService` |
| M3 | Price data fetching with Redis caching | All adapters | Unify via shared `FetchTicker` concern |
| M4 | Log message formatting inconsistency | 40+ instances | Define `LogFormatter` module with standard prefixes |

### 4.2 N+1 Queries & Performance

| ID | File | Issue | Recommendation |
|----|------|-------|----------------|
| M5 | `models/trading/portfolio.rb` (lines 126-138) | `settled_realized_pnl` loads ALL positions, filters in Ruby by `settlement_available_at` | Replace with SQL: `WHERE metadata->>'settlement_available_at' IS NULL OR ...::timestamptz <= NOW()` |
| M6 | `strategy_intelligence_service.rb` | Deserializes entire scorecard hash from shared memory, iterates in code | Add indexed scorecard lookups |
| M7 | `strategy_engine.rb` | `strategy.reload` called mid-tick-loop | Eliminate reload; pass fresh data through method params |

### 4.3 Unvalidated JSON Columns

| ID | Column | Model | Recommendation |
|----|--------|-------|----------------|
| M8 | `parameters` | Strategy | Add JSON Schema validation |
| M9 | `config` | TrainingSession | Add JSON Schema validation |
| M10 | `metadata` | Position | Add JSON Schema validation |

### 4.4 Frontend Duplication & Hardcoding

| ID | Pattern | Scope | Recommendation |
|----|---------|-------|----------------|
| M11 | Status/color maps defined locally instead of using `tradingConstants.ts` | 14+ files | Enforce centralized constants; lint rule |
| M12 | Fetch + error handling pattern repeated | 50+ repetitions | Create `useTradingQuery` hook with standard error/loading |
| M13 | Timing constants (300ms, 2s, 3s, 5s) scattered | 10+ hardcoded values | Move to `tradingConstants.ts` as named exports |

### 4.5 Job Error Handling Inconsistency

| ID | Issue | Recommendation |
|----|-------|----------------|
| M14 | Jobs use different retry strategies: some retry explicitly, some schedule next tick, some let Sidekiq handle, different backoff | Create `TradingJobBase` concern with consistent retry/backoff policy |

### 4.6 Missing DB Constraints

| ID | Issue | Recommendation |
|----|-------|----------------|
| M15 | No CHECK constraints for enum columns (`status`, `lifecycle_phase`, `venue_type`) | Add CHECK constraints for data integrity at DB level |

---

## 5. Low Findings

### 5.1 Smoke Tests in Production Code

| ID | File | Lines | Recommendation |
|----|------|-------|----------------|
| L1 | `services/trading/kalshi_smoke_test.rb` | 526 | Move to `spec/` or dedicated test utility directory |
| L2 | `services/trading/polymarket_smoke_test.rb` | 481 | Move to `spec/` or dedicated test utility directory |

### 5.2 Tight Coupling

| ID | Issue | Recommendation |
|----|-------|----------------|
| L3 | Strategy model calls `StrategyEngine`, `ProvingGroundService`, `SubscriptionLifecycleService` directly | Inject services via constructor or use callbacks/events |
| L4 | VenueAdapter resolves class names via `.constantize` | Use adapter registry hash instead of string-based resolution |

### 5.3 Missing Frontend Infrastructure

| ID | Issue | Recommendation |
|----|-------|----------------|
| L5 | Error boundaries: 1 exists (`WidgetErrorBoundary`), used in 1 place, 123+ components unprotected | Wrap each feature route in an `ErrorBoundary` |
| L6 | No request cancellation or timeouts in `tradingApi.ts` | Add `AbortController` support and default timeouts |
| L7 | No loading skeletons for list/detail views | Add skeleton components for better perceived performance |

---

## 6. Effort Estimation

### Quick Wins (1-2 days each)

| ID | Finding | Effort |
|----|---------|--------|
| M4 | Standardize log formatting | 1 day |
| M11 | Centralize status/color maps | 1 day |
| M13 | Extract timing constants | 0.5 day |
| L1-L2 | Move smoke tests to spec/ | 0.5 day |
| L5 | Add error boundaries to feature routes | 1 day |
| M15 | Add CHECK constraints for enums | 1 day |

**Subtotal: ~5 days**

### Medium Effort (3-5 days each)

| ID | Finding | Effort |
|----|---------|--------|
| M1-M3 | Deduplicate adapter patterns | 3 days |
| M5-M7 | Fix N+1 queries | 3 days |
| M8-M10 | Add JSON schema validation | 3 days |
| M12 | Create `useTradingQuery` hook | 3 days |
| M14 | Standardize job error handling | 2 days |
| H14-H15 | Resolve state machine anti-patterns | 4 days |
| L3-L4 | Decouple Strategy model and adapter resolution | 3 days |
| L6-L7 | Request cancellation + loading skeletons | 3 days |
| H8-H11 | Split oversized controllers/concerns | 5 days |

**Subtotal: ~29 days**

### Large Effort (1-2 weeks each)

| ID | Finding | Effort |
|----|---------|--------|
| C5-C8 | Fix missing error handling (safety-critical) | 5 days |
| H1-H7 | Decompose oversized backend files | 10 days |
| H12 | Decompose oversized frontend components | 5 days |
| H13 | Split and harden `tradingApi.ts` | 5 days |

**Subtotal: ~25 days**

### Architectural (2-4 weeks each)

| ID | Finding | Effort |
|----|---------|--------|
| C1 | Decompose `LiveTrainingRunner` (3,869 lines) | 10 days |
| C2 | Decompose `StrategyEngine` (1,398 lines) | 7 days |
| C3 | Decompose `TradingTrainingSessionJob` (2,136 lines) | 10 days |
| C4 | Decompose Overseer concerns (6,266 lines) | 15 days |

**Subtotal: ~42 days**

### Total Estimated Effort: ~101 days (20 engineering weeks)

**Recommended sequencing:**
1. Quick wins first (1 week) — immediate quality improvement
2. Safety-critical error handling C5-C8 (1 week) — risk reduction
3. N+1 and performance fixes (1 week) — user-facing impact
4. Medium decompositions in parallel with feature work (ongoing)
5. Architectural decompositions as dedicated sprints

---

## Appendix: All Files Referenced (by size)

| File | Lines | Findings |
|------|-------|----------|
| `extensions/trading/server/app/services/trading/live_training_runner.rb` | 3,869 | C1 |
| `extensions/trading/worker/app/jobs/trading_training_session_job.rb` | 2,136 | C3 |
| `extensions/trading/server/app/services/concerns/trading/overseer/strategy_lifecycle.rb` | 2,071 | C4 |
| `extensions/trading/frontend/src/shared/services/tradingApi.ts` | 1,821 | H13 |
| `extensions/trading/server/app/services/trading/venue_adapter/prediction_market/kalshi_adapter.rb` | 1,495 | H7 |
| `extensions/trading/server/app/services/trading/strategy_engine.rb` | 1,398 | C2 |
| `extensions/trading/server/app/services/concerns/trading/overseer/decision_execution.rb` | 1,322 | C4 |
| `extensions/trading/server/app/services/concerns/trading/overseer/scheduling.rb` | 1,149 | C4 |
| `extensions/trading/worker/app/services/trading/evaluators/combinatorial_arbitrage.rb` | 1,001 | — |
| `extensions/trading/server/app/controllers/concerns/trading/internal/training_lifecycle_actions.rb` | 975 | H11 |
| `extensions/trading/frontend/src/features/strategies/components/StrategyPreviewModal.tsx` | 943 | H12 |
| `extensions/trading/server/app/services/trading/venue_adapter/prediction_market/polymarket_adapter.rb` | 864 | — |
| `extensions/trading/frontend/src/shared/components/trading/pipeline/StrategyLifecyclePipeline.tsx` | 867 | H12 |
| `extensions/trading/frontend/src/features/training/components/TrainingDetailPanel.tsx` | 798 | H12 |
| `extensions/trading/server/app/services/trading/strategy_parameter_service.rb` | 771 | H1 |
| `extensions/trading/server/app/services/trading/strategy_intelligence_service.rb` | 751 | H2 |
| `extensions/trading/frontend/src/features/training/components/CreateTrainingSessionModal.tsx` | 747 | H12 |
| `extensions/trading/server/app/models/trading/strategy.rb` | 722 | H3 |
| `extensions/trading/frontend/src/features/portfolio/pages/PortfolioPage.tsx` | 707 | H12 |
| `extensions/trading/frontend/src/features/training/components/TrainingListPanel.tsx` | 664 | H12 |
| `extensions/trading/server/app/services/concerns/trading/overseer/session_evaluation.rb` | 661 | C4 |
| `extensions/trading/server/app/controllers/api/v1/trading/portfolios_controller.rb` | 645 | H8 |
| `extensions/trading/server/app/services/trading/risk_manager_service.rb` | 641 | H4 |
| `extensions/trading/server/app/controllers/concerns/trading/internal/strategy_evaluation_actions.rb` | 632 | — |
| `extensions/trading/server/app/services/concerns/trading/overseer/promotion_and_advancement.rb` | 598 | C4 |
| `extensions/trading/server/app/services/trading/kalshi_smoke_test.rb` | 526 | L1 |
| `extensions/trading/server/app/controllers/api/v1/trading/overseer_controller.rb` | 512 | H9 |
| `extensions/trading/server/app/services/trading/polymarket_smoke_test.rb` | 481 | L2 |
| `extensions/trading/server/app/services/concerns/trading/overseer/position_safety.rb` | 465 | C4 |
| `extensions/trading/server/app/models/trading/training_session.rb` | 452 | H6 |
| `extensions/trading/server/app/services/trading/strategy_context_builder.rb` | 452 | H5 |
| `extensions/trading/server/app/controllers/api/v1/trading/training_sessions_controller.rb` | 438 | H10 |
| `extensions/trading/server/app/controllers/api/v1/trading/strategies_controller.rb` | 413 | — |
| `extensions/trading/server/app/models/trading/portfolio.rb` | 347 | M5 |
