# Model Router Guide

**Intelligent provider selection, task classification, and cost-optimized routing**

**Version**: 1.0 | **Last Updated**: February 2026

---

## Overview

The Model Router selects the optimal AI provider and model for each request based on configurable rules, task classification, provider scoring, and cost optimization. It supports 7 routing strategies, automatic fallback with retry, and comprehensive routing analytics.

### Key Components

| Component | Purpose |
|-----------|---------|
| `Ai::ModelRouterService` | Core router — rule matching, provider scoring, decision recording |
| `Ai::ModelRoutingRule` | Configurable routing rules with conditions and targets |
| `Ai::RoutingDecision` | Audit trail of all routing decisions with outcomes |
| `Ai::ModelPricing` | Per-model pricing data for cost optimization |
| `ProviderScoring` | Multi-dimensional provider scoring (cost, latency, quality, reliability) |
| `TaskClassification` | Classifies requests into complexity tiers for model selection |
| `RoutingAnalytics` | Statistics, trends, and optimization insights |

---

## Routing Strategies

```ruby
STRATEGIES = %w[cost_optimized latency_optimized quality_optimized
                round_robin weighted hybrid ml_based]

DEFAULT_WEIGHTS = { cost: 0.4, latency: 0.3, quality: 0.2, reliability: 0.1 }
```

| Strategy | Optimizes For | Best When |
|----------|--------------|-----------|
| `cost_optimized` | Lowest cost per token | Budget is primary concern |
| `latency_optimized` | Fastest response time | Real-time user-facing requests |
| `quality_optimized` | Highest output quality | Complex reasoning, code generation |
| `round_robin` | Even distribution | Load testing, fair distribution |
| `weighted` | Performance-based distribution | Balanced production workloads |
| `hybrid` | Multi-factor weighted score | Default production strategy |
| `ml_based` | ML-driven optimization | High-volume with historical data |

---

## Model Tiers & Task Classification

The router classifies tasks into complexity tiers and maps them to appropriate model classes.

```ruby
MODEL_TIERS = {
  economy:  { /* smaller, cheaper models */ },
  standard: { /* balanced models */ },
  premium:  { /* largest, most capable models */ }
}

TASK_TIER_MAP = {
  "simple_query"     => :economy,
  "text_generation"  => :standard,
  "code_generation"  => :premium,
  "complex_reasoning"=> :premium,
  # ...
}
```

The `TaskClassification` concern classifies incoming requests based on:
- Explicit `task_type` in request context
- Estimated token count
- Required capabilities (vision, function calling, etc.)
- Historical performance data

---

## Routing Rules

### Ai::ModelRoutingRule

Account-level rules that match requests to target providers.

```ruby
RULE_TYPES = %w[capability_based cost_based latency_based quality_based custom ml_optimized]
STRATEGIES = %w[round_robin weighted cost_optimized latency_optimized quality_optimized hybrid]
```

**Rule structure:**
- `conditions` (JSON) — criteria for matching (task type, complexity, capabilities)
- `target` (JSON) — provider IDs, model names, routing strategy
- `priority` (Integer) — higher priority rules match first
- `active` (Boolean) — enable/disable without deleting

```ruby
rule = Ai::ModelRoutingRule.create!(
  account: account,
  name: "Route code tasks to premium",
  rule_type: "capability_based",
  priority: 10,
  conditions: { task_type: "code_generation", min_quality: 0.8 },
  target: { provider_ids: [anthropic.id], strategy: "quality_optimized" }
)

rule.matches?(request_context)  # => true/false
rule.record_match!(succeeded: true)
rule.success_rate  # => 0.95
```

---

## Provider Scoring

The `ProviderScoring` concern calculates multi-dimensional scores for each provider.

**Dimensions:**

| Dimension | Weight | Source |
|-----------|--------|--------|
| Cost | 0.4 | `Ai::ModelPricing` + estimated tokens |
| Latency | 0.3 | `Ai::ProviderMetric` average response time |
| Quality | 0.2 | Historical success rate + task-specific quality |
| Reliability | 0.1 | Circuit breaker state + recent error rate |

Scores are normalized to 0-1 range and combined using configurable weights.

---

## Routing Flow

```
Request Context
    │
    ▼
┌──────────────────┐
│ 1. Rule Matching │  Find matching rules by priority
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│ 2. Get Providers │  Filter active providers with required capabilities
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│ 3. Score & Rank  │  Multi-dimensional scoring per strategy
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│ 4. Select Best   │  Pick highest-scoring provider
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│ 5. Record Decision│  Audit trail with scoring breakdown
└──────────────────┘
```

### Usage

```ruby
router = Ai::ModelRouterService.new(
  account: account,
  strategy: "hybrid",
  custom_weights: { cost: 0.5, latency: 0.2, quality: 0.2, reliability: 0.1 }
)

# Route a request (returns routing decision)
decision = router.route(
  task_type: "code_generation",
  estimated_tokens: 2000,
  required_capabilities: ["function_calling"]
)
# => Ai::RoutingDecision with selected_provider, strategy, scoring_breakdown

# Route and execute with automatic fallback
result = router.route_and_execute(request_context, max_retries: 3) do |client, provider|
  client.generate(prompt: "...")
end
```

---

## Routing Decisions

### Ai::RoutingDecision

Comprehensive audit trail for every routing decision.

```ruby
STRATEGIES = %w[round_robin weighted cost_optimized latency_optimized
                quality_optimized hybrid ml_based fallback]
OUTCOMES = %w[succeeded failed timeout fallback rate_limited error]

belongs_to :routing_rule, optional: true
belongs_to :selected_provider, class_name: "Ai::Provider"
```

**Key methods:**
- `record_outcome!(outcome:, cost_usd:, latency_ms:, tokens_used:, quality_score:)`
- `cost_effective?` — compares actual vs estimated cost
- `evaluated_candidates` — returns all scored providers from the decision

**Aggregate statistics:**
```ruby
Ai::RoutingDecision.stats_for_period(account: account, period: 30.days)
# => { total_decisions, success_rate, avg_cost, avg_latency, by_strategy: {...}, by_provider: {...} }
```

---

## API Endpoints

### Rule Management

**Controller**: `Api::V1::Ai::ModelRouterController`

| Method | Path | Permission | Description |
|--------|------|-----------|-------------|
| `GET` | `/api/v1/ai/model_router/rules` | `ai.routing.read` | List rules (paginated) |
| `GET` | `/api/v1/ai/model_router/rules/:id` | `ai.routing.read` | Show rule |
| `POST` | `/api/v1/ai/model_router/rules` | `ai.routing.manage` | Create rule |
| `PATCH` | `/api/v1/ai/model_router/rules/:id` | `ai.routing.manage` | Update rule |
| `DELETE` | `/api/v1/ai/model_router/rules/:id` | `ai.routing.manage` | Delete rule |
| `POST` | `/api/v1/ai/model_router/rules/:id/toggle` | `ai.routing.manage` | Toggle rule active/inactive |
| `GET` | `/api/v1/ai/model_router/decisions` | `ai.routing.read` | List decisions |
| `GET` | `/api/v1/ai/model_router/decisions/:id` | `ai.routing.read` | Show decision |

### Analytics & Optimization

**Controller**: `Api::V1::Ai::ModelRouterAnalyticsController`

| Method | Path | Permission | Description |
|--------|------|-----------|-------------|
| `POST` | `/api/v1/ai/model_router/route` | `ai.routing.manage` | Route a request |
| `GET` | `/api/v1/ai/model_router/statistics` | `ai.routing.read` | Routing statistics |
| `GET` | `/api/v1/ai/model_router/cost_analysis` | `ai.routing.read` | Cost analysis |
| `GET` | `/api/v1/ai/model_router/provider_rankings` | `ai.routing.read` | Provider rankings |
| `GET` | `/api/v1/ai/model_router/recommendations` | `ai.routing.read` | Optimization tips |
| `GET` | `/api/v1/ai/model_router/optimizations` | `ai.routing.read` | List optimizations |
| `POST` | `/api/v1/ai/model_router/optimizations/identify` | `ai.routing.optimize` | Identify opportunities |
| `POST` | `/api/v1/ai/model_router/optimizations/:id/apply` | `ai.routing.optimize` | Apply optimization |

---

## Key Files

| File | Path |
|------|------|
| Router Service | `server/app/services/ai/model_router_service.rb` |
| Provider Scoring | `server/app/services/ai/model_router/provider_scoring.rb` |
| Task Classification | `server/app/services/ai/model_router/task_classification.rb` |
| Routing Analytics | `server/app/services/ai/model_router/routing_analytics.rb` |
| Routing Rule Model | `server/app/models/ai/model_routing_rule.rb` |
| Routing Decision Model | `server/app/models/ai/routing_decision.rb` |
| Model Pricing Model | `server/app/models/ai/model_pricing.rb` |
| Controller | `server/app/controllers/api/v1/ai/model_router_controller.rb` |
| Analytics Controller | `server/app/controllers/api/v1/ai/model_router_analytics_controller.rb` |
