# AI Provider Routing

**Intelligent provider selection and load balancing for AI operations**

---

## Table of Contents

1. [Overview](#overview)
2. [Routing Strategies](#routing-strategies)
3. [Load Balancing](#load-balancing)
4. [Circuit Breaker](#circuit-breaker)
5. [Fallback Handling](#fallback-handling)
6. [Configuration](#configuration)

---

## Overview

Powernode implements intelligent AI provider routing that optimizes for cost, performance, and reliability. The system automatically selects the best provider for each request based on configurable strategies.

### Key Components

| Component | Purpose |
|-----------|---------|
| `ModelRouterService` | Request routing and provider selection |
| `ProviderLoadBalancerService` | Load distribution across providers |
| `ProviderCircuitBreakerService` | Fault tolerance and recovery |

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    AI Request                               │
└──────────────────────────┬──────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────┐
│                  ModelRouterService                         │
│  - Strategy selection                                       │
│  - Rule matching                                            │
│  - Provider scoring                                         │
└──────────────────────────┬──────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────┐
│             ProviderLoadBalancerService                     │
│  - Load distribution                                        │
│  - Health tracking                                          │
│  - Metrics collection                                       │
└──────────────────────────┬──────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────┐
│            ProviderCircuitBreakerService                    │
│  - Failure detection                                        │
│  - Circuit state management                                 │
│  - Recovery handling                                        │
└──────────────────────────┬──────────────────────────────────┘
                           │
         ┌─────────────────┼─────────────────┐
         │                 │                 │
    ┌────▼────┐       ┌────▼────┐       ┌────▼────┐
    │ OpenAI  │       │ Anthropic│       │ Azure  │
    └─────────┘       └─────────┘       └─────────┘
```

---

## Routing Strategies

### Available Strategies

```ruby
STRATEGIES = %w[
  cost_optimized        # Minimize cost
  latency_optimized     # Minimize latency
  quality_optimized     # Maximize output quality
  round_robin           # Simple rotation
  weighted              # Weighted distribution
  hybrid                # Multi-factor optimization
  ml_based              # ML-driven routing
].freeze
```

### Cost Optimized

Selects the provider with the lowest cost per token:

```ruby
def select_cost_optimized(providers, request_context)
  estimated_tokens = estimate_token_usage(request_context)

  providers.min_by do |provider|
    cost_score = estimate_provider_cost(provider) * estimated_tokens
    load_penalty = get_provider_current_load(provider) * 0.1
    response_time_penalty = get_provider_avg_response_time(provider) * 0.01

    cost_score + load_penalty + response_time_penalty
  end
end
```

### Latency Optimized

Selects the provider with the fastest response time:

```ruby
def select_latency_optimized(providers)
  providers.min_by do |provider|
    avg_latency = get_provider_avg_response_time(provider)
    current_load = get_provider_current_load(provider)

    # Penalize high load (increases latency)
    avg_latency * (1 + current_load * 0.1)
  end
end
```

### Quality Optimized

Selects based on model quality metrics:

```ruby
def select_quality_optimized(providers, request_context)
  task_type = request_context[:task_type] || 'general'

  providers.max_by do |provider|
    quality_score = get_provider_quality_score(provider, task_type)
    success_rate = get_provider_success_rate(provider)

    quality_score * success_rate
  end
end
```

### Hybrid Strategy

Combines multiple factors with configurable weights:

```ruby
DEFAULT_WEIGHTS = {
  cost: 0.4,
  latency: 0.3,
  quality: 0.2,
  reliability: 0.1
}.freeze

def select_hybrid(providers, request_context, weights)
  providers.min_by do |provider|
    cost_score = normalize_cost(provider, request_context) * weights[:cost]
    latency_score = normalize_latency(provider) * weights[:latency]
    quality_score = (1 - normalize_quality(provider)) * weights[:quality]
    reliability_score = (1 - get_provider_success_rate(provider) / 100) * weights[:reliability]

    cost_score + latency_score + quality_score + reliability_score
  end
end
```

---

## Load Balancing

### Load Balancing Strategies

```ruby
LOAD_BALANCING_STRATEGIES = %w[
  round_robin
  weighted_round_robin
  least_connections
  cost_optimized
  performance_based
].freeze
```

### Round Robin

Simple rotation through available providers:

```ruby
def select_round_robin(providers)
  counter = @redis.incr(round_robin_counter_key)
  @redis.expire(round_robin_counter_key, 1.hour)
  providers[counter % providers.size]
end
```

### Weighted Round Robin

Rotation with performance-based weights:

```ruby
def select_weighted_round_robin(providers)
  weighted_providers = providers.flat_map do |provider|
    weight = calculate_provider_weight(provider)
    [provider] * weight.clamp(1, 10)
  end

  select_round_robin(weighted_providers)
end

def calculate_provider_weight(provider)
  success_rate = get_provider_success_rate(provider)
  avg_response_time = get_provider_avg_response_time(provider)
  current_load = get_provider_current_load(provider)

  weight = (success_rate / 10.0) - (avg_response_time / 1000.0) - (current_load / 10.0)
  weight.clamp(1, 10).round
end
```

### Least Connections

Route to provider with lowest current load:

```ruby
def select_least_connections(providers)
  providers.min_by { |provider| get_provider_current_load(provider) }
end
```

### Performance Based

Optimize for response time and success rate:

```ruby
def select_performance_based(providers)
  providers.min_by do |provider|
    response_time = get_provider_avg_response_time(provider)
    success_rate = get_provider_success_rate(provider)
    current_load = get_provider_current_load(provider)

    # Lower score is better
    response_time * 0.5 + (100 - success_rate) * 0.3 + current_load * 0.2
  end
end
```

---

## Circuit Breaker

### Circuit States

```
CLOSED → OPEN → HALF_OPEN → CLOSED
   │       │        │
   │       │        └── Success → CLOSED
   │       │            Failure → OPEN
   │       │
   │       └── After timeout → HALF_OPEN
   │
   └── Failures exceed threshold → OPEN
```

### Configuration

```ruby
class ProviderCircuitBreakerService
  FAILURE_THRESHOLD = 5           # Failures before opening
  RESET_TIMEOUT = 30.seconds      # Time before half-open
  SUCCESS_THRESHOLD = 3           # Successes to close from half-open

  def record_success
    @failure_count = 0
    if @state == :half_open && @success_count >= SUCCESS_THRESHOLD
      transition_to(:closed)
    end
    @success_count += 1
  end

  def record_failure(error)
    @failure_count += 1
    if @failure_count >= FAILURE_THRESHOLD
      transition_to(:open)
    end
  end

  def provider_available?
    case @state
    when :closed then true
    when :open then time_to_try_again?
    when :half_open then true
    end
  end
end
```

### State Transitions

```ruby
def transition_to(new_state)
  old_state = @state
  @state = new_state

  case new_state
  when :open
    @opened_at = Time.current
    Rails.logger.warn "Circuit opened for provider #{@provider.id}"
    notify_circuit_open
  when :half_open
    Rails.logger.info "Circuit half-open for provider #{@provider.id}"
  when :closed
    @failure_count = 0
    @success_count = 0
    Rails.logger.info "Circuit closed for provider #{@provider.id}"
  end
end
```

---

## Fallback Handling

### Automatic Fallback

```ruby
def execute_with_fallback(request_type, **options, &block)
  max_retries = options.delete(:max_provider_retries) || 3
  attempted_providers = []

  max_retries.times do |attempt|
    begin
      provider = select_provider(options)
      next if attempted_providers.include?(provider.id)

      attempted_providers << provider.id

      credential = provider.provider_credentials.active.first
      raise LoadBalancingError, "No credentials for #{provider.name}" unless credential

      client = Ai::ProviderClientService.new(credential)
      result = yield(client, provider)

      record_execution_success(provider, options)
      return result

    rescue CircuitBreakerOpenError => e
      Rails.logger.warn "Provider #{provider.name} circuit open, trying next"
      record_execution_failure(provider, e, "circuit_breaker_open")
      next

    rescue StandardError => e
      Rails.logger.error "Provider #{provider.name} failed: #{e.message}"
      record_execution_failure(provider, e, "execution_error")

      raise if attempt == max_retries - 1
      next
    end
  end

  raise NoProvidersAvailableError, "All providers failed after #{max_retries} attempts"
end
```

### Fallback Strategies

| Strategy | Description |
|----------|-------------|
| Next Provider | Try next best provider |
| Cached Response | Return cached response if available |
| Degraded Mode | Return simplified response |
| Queue Request | Queue for later processing |

---

## Configuration

### Provider Configuration

```ruby
# Provider settings in configuration JSON
{
  "pricing": {
    "text_generation": {
      "per_1k_tokens": 0.002
    },
    "embeddings": {
      "per_1k_tokens": 0.0001
    }
  },
  "capabilities": {
    "text_generation": true,
    "embeddings": true,
    "vision": false
  },
  "rate_limits": {
    "requests_per_minute": 60,
    "tokens_per_minute": 100000
  }
}
```

### Routing Rules

```ruby
# Account-level routing rules
routing_rules = [
  {
    name: "Cost saving for simple tasks",
    conditions: { complexity: "low" },
    preferred_strategy: "cost_optimized",
    priority: 1
  },
  {
    name: "Quality for complex tasks",
    conditions: { complexity: "high" },
    preferred_strategy: "quality_optimized",
    priority: 2
  }
]
```

### Statistics and Monitoring

```ruby
def load_balancing_stats
  available_providers = get_available_providers

  {
    strategy: @strategy,
    capability: @capability,
    available_providers: available_providers.size,
    providers: available_providers.map do |provider|
      circuit_breaker = ProviderCircuitBreakerService.new(provider)
      {
        id: provider.id,
        name: provider.name,
        current_load: get_provider_current_load(provider),
        circuit_state: circuit_breaker.circuit_state,
        avg_response_time: get_provider_avg_response_time(provider),
        success_rate: get_provider_success_rate(provider),
        cost_per_1k_tokens: estimate_provider_cost(provider),
        last_used: get_provider_last_used(provider)
      }
    end
  }
end
```

---

## Best Practices

### 1. Configure Multiple Providers

Always have at least 2 active providers for fallback capability.

### 2. Monitor Circuit States

Set up alerts for circuit breaker state changes.

### 3. Tune Weights for Your Use Case

Adjust hybrid strategy weights based on your priorities.

### 4. Review Routing Decisions

Regularly analyze routing decision logs to optimize configuration.

### 5. Set Appropriate Timeouts

Configure request timeouts based on expected operation complexity.

---

**Document Status**: Complete
**Last Updated**: 2025-01-30
**Source**: `server/app/services/ai/`
