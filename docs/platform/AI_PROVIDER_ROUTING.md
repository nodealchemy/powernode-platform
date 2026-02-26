# AI Provider Routing

**Intelligent provider selection, load balancing, and circuit breaker management**

**Version**: 3.0 | **Last Updated**: February 2026

---

## Overview

Powernode implements intelligent AI provider routing that optimizes for cost, performance, and reliability. The system supports 10 providers, 7 routing strategies, 5 load balancing strategies, and automatic circuit breaker management.

### Supported Providers

| Provider | Adapter | Capabilities |
|----------|---------|-------------|
| Anthropic | `AnthropicAdapter` | Text, vision, function calling |
| OpenAI | `OpenAIAdapter` | Text, vision, embeddings, function calling |
| Ollama | `OllamaAdapter` | Text, local models |
| Azure | `azure` sync | Text, embeddings |
| Google | `google` sync | Text, vision |
| Groq | `groq` sync | Text (fast inference) |
| Grok | `grok` sync | Text |
| Mistral | `mistral` sync | Text, function calling |
| Cohere | `cohere` sync | Text, embeddings, reranking |
| Generic | `generic` sync | Custom API-compatible providers |

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    AI Request                               │
└──────────────────────────┬──────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────┐
│              ModelRouterService                              │
│  TaskClassification → Rule Matching → Provider Scoring       │
│  (see MODEL_ROUTER_GUIDE.md for full details)                │
└──────────────────────────┬──────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────┐
│             ProviderLoadBalancerService                      │
│  Round Robin │ Weighted │ Least Connections │ Performance    │
└──────────────────────────┬──────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────┐
│            ProviderCircuitBreakerService                     │
│  Closed ↔ Open ↔ Half-Open                                  │
└──────────────────────────┬──────────────────────────────────┘
                           │
         ┌─────────────────┼──────────────────┐
         │                 │                  │
    ┌────▼────┐       ┌────▼─────┐       ┌────▼────┐
    │Anthropic│       │ OpenAI   │       │ Ollama  │  ...
    └─────────┘       └──────────┘       └─────────┘
```

---

## Routing Strategies

```ruby
STRATEGIES = %w[cost_optimized latency_optimized quality_optimized
                round_robin weighted hybrid ml_based]

DEFAULT_WEIGHTS = { cost: 0.4, latency: 0.3, quality: 0.2, reliability: 0.1 }
```

For full routing strategy details, task classification, and provider scoring, see [MODEL_ROUTER_GUIDE.md](MODEL_ROUTER_GUIDE.md).

---

## Load Balancing

### Strategies

```ruby
LOAD_BALANCING_STRATEGIES = %w[
  round_robin weighted_round_robin least_connections
  cost_optimized performance_based
]
```

| Strategy | Selection Logic |
|----------|----------------|
| `round_robin` | Redis-backed counter rotation |
| `weighted_round_robin` | Performance-weighted rotation (weight 1-10) |
| `least_connections` | Lowest current active connections |
| `cost_optimized` | Lowest cost per token |
| `performance_based` | Composite: response_time × 0.5 + error_rate × 0.3 + load × 0.2 |

### Weight Calculation

```ruby
# Weight = success_rate/10 - response_time/1000 - load/10
# Clamped to 1-10 range
weight = (success_rate / 10.0) - (avg_response_time / 1000.0) - (current_load / 10.0)
weight.clamp(1, 10).round
```

---

## Circuit Breaker

### State Machine

```
CLOSED ────────────────▶ OPEN ────────────────▶ HALF_OPEN
  │  failures >= 5         │  after timeout         │
  │                        │  (30 seconds)          │
  ◀────────────────────────┤                        │
     3 successes in        │  failure in            │
     half-open             │  half-open             │
                           ◀────────────────────────┘
```

### Configuration

| Parameter | Default | Description |
|-----------|---------|-------------|
| `FAILURE_THRESHOLD` | 5 | Failures before opening |
| `RESET_TIMEOUT` | 30s | Time before half-open |
| `SUCCESS_THRESHOLD` | 3 | Successes to close from half-open |

### Provider Metrics

`Ai::ProviderMetric` records per-provider performance data at configurable granularity.

```ruby
GRANULARITIES = %w[minute hour day week month]
CIRCUIT_STATES = %w[closed open half_open]
```

**Key methods:**
- `calculate_success_rate`, `calculate_error_rate`
- `calculate_avg_cost_per_request`, `calculate_cost_per_1k_tokens`
- `health_status` — returns `healthy`, `degraded`, or `unhealthy`
- `self.aggregate_to_hourly` — rolls up minute metrics
- `self.provider_comparison` — cross-provider comparison

---

## Fallback Handling

### Automatic Fallback

The system automatically retries with alternative providers on failure:

1. Select provider via strategy
2. Execute request
3. On failure: record failure, try next provider
4. On circuit breaker open: skip provider, try next
5. After max retries: raise `NoProvidersAvailableError`

### Fallback Strategies

| Strategy | Description |
|----------|-------------|
| Next Provider | Try next best provider by score |
| Cached Response | Return cached response if available |
| Degraded Mode | Return simplified response |
| Queue Request | Queue for later processing |

---

## Provider Credentials

`Ai::ProviderCredential` manages encrypted API keys per provider.

**Key features:**
- Encrypted credential storage with `encryption_key_id`
- One default credential per provider (auto-set on first creation)
- Health tracking: `record_success!` / `record_failure!(error_message)`
- Expiration monitoring: `expired?`, `expires_soon?`
- Connection testing: `test_connection`

---

## Configuration

### Provider Setup

```ruby
provider = Ai::Provider.create!(
  account: account,
  name: "Anthropic Production",
  provider_type: "anthropic",
  api_endpoint: "https://api.anthropic.com",
  capabilities: { text_generation: true, vision: true, function_calling: true },
  supported_models: ["claude-3-opus", "claude-3-sonnet", "claude-3-haiku"],
  priority_order: 1
)
```

### Model Pricing

```ruby
Ai::ModelPricing.create!(
  model_id: "claude-3-opus",
  provider_type: "anthropic",
  input_per_1k: 0.015,
  output_per_1k: 0.075,
  source: "manual"
)
```

### Routing Rules

See [MODEL_ROUTER_GUIDE.md](MODEL_ROUTER_GUIDE.md) for routing rule configuration.

---

## Best Practices

1. **Multiple Providers** — maintain at least 2 active providers for fallback
2. **Monitor Circuit States** — alert on circuit breaker opens
3. **Tune Weights** — adjust hybrid strategy weights for your workload
4. **Review Decisions** — analyze routing decision logs regularly
5. **Set Timeouts** — configure per-complexity operation timeouts
6. **Credential Rotation** — monitor credential expiration, rotate before expiry
7. **Cost Optimization** — run `platform.get_api_reference` to check provider pricing

---

## Key Files

| File | Path |
|------|------|
| Provider Model | `server/app/models/ai/provider.rb` |
| Provider Credential Model | `server/app/models/ai/provider_credential.rb` |
| Provider Metric Model | `server/app/models/ai/provider_metric.rb` |
| Model Pricing Model | `server/app/models/ai/model_pricing.rb` |
| Load Balancer Service | `server/app/services/ai/provider_load_balancer_service.rb` |
| Circuit Breaker Service | `server/app/services/ai/provider_circuit_breaker_service.rb` |
| Provider Client Service | `server/app/services/ai/provider_client_service.rb` |
| Provider Management | `server/app/services/ai/provider_management_service.rb` |
| LLM Adapter Factory | `server/app/services/ai/llm/adapter_factory.rb` |
| Provider Sync Adapters | `server/app/services/ai/providers/sync/` |

---

**Document Status**: Complete
**Source**: `server/app/services/ai/`, `server/app/models/ai/`
