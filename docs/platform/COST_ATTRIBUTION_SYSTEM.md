# Cost Attribution System

**AI cost tracking, budget management, ROI metrics, and optimization**

**Version**: 3.0 | **Last Updated**: February 2026

---

## Overview

The Cost Attribution System provides comprehensive cost tracking, budget management, and optimization across the AI platform. It covers per-execution cost attribution, agent-level budgets with transaction locking, ROI metrics, and automated optimization opportunity detection.

### Key Components

| Component | Purpose |
|-----------|---------|
| `Ai::CostAttribution` | Per-execution cost records with source and category |
| `Ai::AgentBudget` | Hierarchical budgets with period tracking |
| `Ai::BudgetTransaction` | Debit/credit/reservation transaction ledger |
| `Ai::CostOptimizationLog` | Optimization opportunity tracking |
| `Ai::RoiMetric` | Return on investment calculations |
| `CostOptimizationService` | Analysis, recommendations, and budget management |

---

## Cost Attribution

### Ai::CostAttribution

Records cost for every AI operation with source and category breakdown.

```ruby
SOURCE_TYPES = %w[workflow agent provider team execution]
COST_CATEGORIES = %w[ai_inference ai_training embedding storage compute api_calls bandwidth other]

belongs_to :account
belongs_to :roi_metric, optional: true
belongs_to :provider, class_name: "Ai::Provider", optional: true
```

**Key methods:**
- `self.from_agent_execution(execution)` — creates attribution from execution record
- `self.cost_breakdown_by_category` / `by_source_type` / `by_provider` — aggregate reports
- `self.daily_cost_trend(account, days)` — daily cost over time
- `self.top_cost_sources(account, limit)` — highest-cost sources
- `self.aggregate_to_roi_metrics(account, date:)` — roll up to ROI

---

## Budget Management

### Ai::AgentBudget

Per-agent budgets with hierarchical allocation and period tracking.

```ruby
PERIOD_TYPES = %w[daily weekly monthly total]
CURRENCIES = %w[USD EUR GBP]
UTILIZATION_THRESHOLDS = { warning: 75, danger: 90, exhausted: 100 }

belongs_to :agent, class_name: "Ai::Agent"
belongs_to :parent_budget, optional: true
has_many :child_budgets
has_many :budget_transactions
```

**Key methods (all with pessimistic locking):**
- `debit!(amount_cents, execution:, metadata:)` — debit budget
- `credit!(amount_cents, reason:, metadata:)` — credit/refund
- `reserve!(amount_cents, metadata:)` — reserve budget (pre-execution)
- `spend!(amount_cents, execution:, metadata:)` — spend from reserved amount
- `release_reservation!(amount_cents, metadata:)` — release unused reservation
- `auto_rollover!` — roll unused budget to next period
- `allocate_child(agent:, amount_cents:, period_type:)` — create child budget

**Budget checks:**
- `remaining_cents` — available budget
- `utilization_percentage` — used vs total
- `over_budget?` / `exceeded?` / `nearly_exceeded?` — threshold checks

**Threshold alerts:** Automatically fires alerts at 75% (warning), 90% (danger), and 100% (exhausted) utilization.

### Ai::BudgetTransaction

Ledger of all budget operations.

```ruby
TRANSACTION_TYPES = %w[debit credit reservation release rollover adjustment]

belongs_to :agent_budget
belongs_to :agent_execution, optional: true
```

**Scopes:** `debits`, `credits`, `reservations`, `releases`, `rollovers`, `for_period`, `by_model`, `by_provider`

---

## ROI Metrics

### Ai::RoiMetric

Return on investment calculations per agent, workflow, team, or account.

```ruby
METRIC_TYPES = %w[workflow agent provider team account_total department]
PERIOD_TYPES = %w[daily weekly monthly quarterly yearly]
DEFAULT_HOURLY_RATE = 75.0  # USD for time savings calculation

belongs_to :attributable, polymorphic: true, optional: true
has_many :cost_attributions
```

**Key methods:**
- `calculate_roi` — `(value_generated - total_cost) / total_cost × 100`
- `calculate_net_benefit` — `value_generated - total_cost`
- `time_saved_monetary_value(hourly_rate:)` — converts time savings to USD
- `positive_roi?` — true if ROI > 0
- `break_even_analysis` — days/operations to break even
- `efficiency_metrics` — cost per operation, time saved per dollar

**Aggregate methods:**
- `self.calculate_for_account(account, period_type:, period_date:)` — full account ROI
- `self.roi_trends(account, days:)` — ROI trend over time
- `self.aggregate_for_period(account, period_type:, period_date:)` — period aggregation

---

## Cost Optimization

### Ai::CostOptimizationLog

Tracks optimization opportunities through their lifecycle.

```ruby
OPTIMIZATION_TYPES = %w[provider_switch model_downgrade caching batching rate_optimization usage_reduction]
STATUSES = %w[identified analyzing recommended applied validated rejected expired]
```

**Lifecycle:** `identified` → `analyzing` → `recommended` → `applied` → `validated` | `rejected` | `expired`

**Key methods:**
- `start_analysis!` / `recommend!(details)` / `apply!(applied_state)` / `validate_results!(actual_savings:)` / `reject!(reason)`
- `self.identify_opportunities_for(account)` — multi-step opportunity identification:
  1. Provider opportunities (cheaper alternatives for current usage)
  2. Usage opportunities (reduce unnecessary operations)
  3. Caching opportunities (similar repeated requests)

### CostOptimizationService

Comprehensive cost analysis with 6 included modules:

```ruby
service = Ai::CostOptimizationService.new(account: account, time_range: 30.days)
```

| Module | Methods |
|--------|---------|
| `CostTracking` | `track_real_time_costs`, `start_cost_tracking`, `update_cost_tracking` |
| `CostAnalysis` | `cost_breakdown`, `analyze_cost_trends` |
| `BudgetManagement` | `budget_status`, `generate_budget_recommendations` |
| `ProviderOptimization` | `compare_providers`, `suggest_provider_actions` |
| `UsagePatterns` | Usage pattern analysis and anomaly detection |
| `Recommendations` | `generate_recommendations` (provider, model, caching, usage) |

### Dashboard Data

```ruby
service = Ai::CostOptimizationService.new(account: account, time_range: 30.days)

dashboard = {
  real_time: service.track_real_time_costs,
  budget: service.budget_status(Time.current.beginning_of_month, Time.current),
  breakdown: service.cost_breakdown(30.days.ago, Time.current),
  recommendations: service.generate_recommendations,
  providers: service.compare_providers
}
```

---

## Provider Cost Comparison

```ruby
# Compare all active providers
comparison = service.compare_providers
# => [
#   { provider_name: "Anthropic", total_cost: 850.25, avg_cost_per_execution: 0.12,
#     success_rate: 99.2, cost_efficiency_score: 8.5 },
#   { provider_name: "OpenAI", total_cost: 300.15, avg_cost_per_execution: 0.08,
#     success_rate: 98.1, cost_efficiency_score: 9.1 },
#   ...
# ]

# Cost efficiency formula:
# (success_rate × 0.5) / (avg_cost × 0.3 + avg_response_time/10000 × 0.2)
```

---

## Key Files

| File | Path |
|------|------|
| Cost Attribution Model | `server/app/models/ai/cost_attribution.rb` |
| Agent Budget Model | `server/app/models/ai/agent_budget.rb` |
| Budget Transaction Model | `server/app/models/ai/budget_transaction.rb` |
| ROI Metric Model | `server/app/models/ai/roi_metric.rb` |
| Cost Optimization Log Model | `server/app/models/ai/cost_optimization_log.rb` |
| Cost Optimization Service | `server/app/services/ai/cost_optimization_service.rb` |
| ROI Controller | `server/app/controllers/api/v1/ai/roi_controller.rb` |
| FinOps Controller | `server/app/controllers/api/v1/ai/finops_controller.rb` |

---

**Document Status**: Complete
**Source**: `server/app/models/ai/`, `server/app/services/ai/`
