# frozen_string_literal: true

# AI Model Routing Rules — Realistic Examples
# Creates production-ready routing rules that demonstrate all rule types,
# strategies, and condition patterns supported by ModelRouterService.

puts "\n🔀 Seeding AI Model Routing Rules..."

admin_account = Account.find_by(name: "Powernode Admin")

unless admin_account
  puts "⚠️  Powernode Admin account not found — skipping routing rules"
  return
end

# Look up providers by name to wire target.provider_ids dynamically
openai    = admin_account.ai_providers.find_by(name: "OpenAI")
claude    = admin_account.ai_providers.find_by(name: "Claude AI (Anthropic)")
grok      = admin_account.ai_providers.find_by(name: "Grok (X.AI)")

all_provider_ids    = [openai, claude, grok].compact.map(&:id)
premium_ids         = [openai, claude].compact.map(&:id)
economy_ids         = [openai, grok].compact.map(&:id)
openai_ids          = [openai].compact.map(&:id)
claude_ids          = [claude].compact.map(&:id)

puts "  Providers found: OpenAI=#{openai&.id.present?}, Claude=#{claude&.id.present?}, Grok=#{grok&.id.present?}"

rules = [
  # ---------------------------------------------------------------------------
  # COST-BASED RULES — Control spend and optimise for budget
  # ---------------------------------------------------------------------------
  {
    name: "Economy Tier — Bulk Classification & Extraction",
    description: "Route high-volume, low-complexity tasks (classification, extraction, formatting) " \
                 "to the cheapest available models. Keeps cost under $0.002/1K tokens.",
    rule_type: "cost_based",
    priority: 10,
    max_cost_per_1k_tokens: 0.002,
    conditions: {
      "request_types" => %w[completion],
      "max_tokens" => 2000,
      "max_cost_per_token" => 0.000002,
      "model_patterns" => ["gpt-4\\.1-nano", "gpt-4\\.1-mini", "haiku", "claude-haiku.*"]
    },
    target: {
      "provider_ids" => economy_ids,
      "strategy" => "cost_optimized",
      "model_names" => %w[gpt-4.1-nano gpt-4.1-mini claude-haiku-4-5]
    }
  },
  {
    name: "Standard Tier — Summarisation & Analysis",
    description: "Mid-range tasks like summarisation, translation, code review, and general analysis. " \
                 "Balances cost vs quality with a $0.01/1K token ceiling.",
    rule_type: "cost_based",
    priority: 20,
    max_cost_per_1k_tokens: 0.01,
    conditions: {
      "request_types" => %w[completion],
      "max_cost_per_token" => 0.00001,
      "min_tokens" => 500,
      "max_tokens" => 16000
    },
    target: {
      "provider_ids" => all_provider_ids,
      "strategy" => "cost_optimized",
      "model_names" => %w[gpt-4.1-mini o4-mini claude-sonnet-4-5]
    }
  },
  {
    name: "Budget Guard — Hard Cost Ceiling",
    description: "Absolute cost ceiling rule. Any request estimating more than $0.05/1K tokens " \
                 "is forcibly downgraded to economy models. Prevents runaway spend from " \
                 "misconfigured agents or unexpectedly large payloads.",
    rule_type: "cost_based",
    priority: 1,
    max_cost_per_1k_tokens: 0.05,
    conditions: {
      "max_cost_per_token" => 0.00005
    },
    target: {
      "provider_ids" => economy_ids,
      "strategy" => "cost_optimized",
      "model_names" => %w[gpt-4.1-nano gpt-4.1-mini]
    }
  },

  # ---------------------------------------------------------------------------
  # CAPABILITY-BASED RULES — Route by what the model can do
  # ---------------------------------------------------------------------------
  {
    name: "Vision Requests → Multimodal Models",
    description: "When a request requires vision capabilities (image analysis, screenshot understanding, " \
                 "diagram parsing), route exclusively to vision-capable models.",
    rule_type: "capability_based",
    priority: 5,
    conditions: {
      "capabilities" => %w[vision],
      "request_types" => %w[completion]
    },
    target: {
      "provider_ids" => premium_ids,
      "strategy" => "quality_optimized",
      "model_names" => %w[gpt-4.1 claude-opus-4-6 claude-sonnet-4-5]
    }
  },
  {
    name: "Streaming Required → Streaming Providers",
    description: "Requests requiring real-time streaming responses (chat UIs, live dashboards) " \
                 "must go to providers that support SSE/chunked streaming. Optimised for latency.",
    rule_type: "capability_based",
    priority: 15,
    conditions: {
      "capabilities" => %w[streaming],
      "request_types" => %w[completion]
    },
    target: {
      "provider_ids" => all_provider_ids,
      "strategy" => "latency_optimized",
      "model_names" => %w[gpt-4.1-mini claude-sonnet-4-5 grok-3]
    }
  },
  {
    name: "Function Calling → Tool-Capable Models",
    description: "Agent tasks requiring tool use / function calling must route to models with " \
                 "native function-calling support. Ensures MCP tool execution works reliably.",
    rule_type: "capability_based",
    priority: 12,
    conditions: {
      "capabilities" => %w[function_calling],
      "request_types" => %w[completion]
    },
    target: {
      "provider_ids" => premium_ids,
      "strategy" => "quality_optimized",
      "model_names" => %w[gpt-4.1 claude-sonnet-4-5 claude-opus-4-6]
    }
  },
  {
    name: "Embedding Requests → Embedding Models",
    description: "All embedding/vectorisation requests route to dedicated embedding endpoints. " \
                 "These are separate from completion models and use different pricing.",
    rule_type: "capability_based",
    priority: 3,
    conditions: {
      "request_types" => %w[embedding]
    },
    target: {
      "provider_ids" => openai_ids,
      "strategy" => "cost_optimized",
      "model_names" => %w[text-embedding-3-small text-embedding-3-large]
    }
  },

  # ---------------------------------------------------------------------------
  # LATENCY-BASED RULES — Optimise for response time
  # ---------------------------------------------------------------------------
  {
    name: "Real-Time Chat — Sub-2s First Token",
    description: "Interactive chat conversations require fast time-to-first-token. " \
                 "Route to the fastest available models with a 2000ms latency ceiling. " \
                 "Prioritises responsiveness over output quality.",
    rule_type: "latency_based",
    priority: 8,
    max_latency_ms: 2000,
    conditions: {
      "max_latency_ms" => 2000,
      "request_types" => %w[completion],
      "max_tokens" => 4000
    },
    target: {
      "provider_ids" => all_provider_ids,
      "strategy" => "latency_optimized",
      "model_names" => %w[gpt-4.1-mini claude-haiku-4-5 grok-3-mini]
    }
  },
  {
    name: "Guardrail Evaluation — Ultra-Low Latency",
    description: "Guardrail checks (prompt injection detection, toxicity scoring) run in the " \
                 "critical path before agent execution. Must complete in under 500ms to avoid " \
                 "degrading user experience. Uses smallest economy models.",
    rule_type: "latency_based",
    priority: 2,
    max_latency_ms: 500,
    conditions: {
      "max_latency_ms" => 500,
      "max_tokens" => 500,
      "request_types" => %w[completion]
    },
    target: {
      "provider_ids" => economy_ids,
      "strategy" => "latency_optimized",
      "model_names" => %w[gpt-4.1-nano claude-haiku-4-5]
    }
  },
  {
    name: "Batch Processing — Latency Relaxed",
    description: "Background batch jobs (memory consolidation, context compression, bulk analysis) " \
                 "have no latency constraints. Route to cheapest provider regardless of speed.",
    rule_type: "latency_based",
    priority: 50,
    max_latency_ms: 60_000,
    conditions: {
      "max_latency_ms" => 60_000,
      "min_tokens" => 1000,
      "request_types" => %w[completion]
    },
    target: {
      "provider_ids" => economy_ids,
      "strategy" => "cost_optimized",
      "model_names" => %w[gpt-4.1-mini o4-mini]
    }
  },

  # ---------------------------------------------------------------------------
  # QUALITY-BASED RULES — Ensure output meets quality thresholds
  # ---------------------------------------------------------------------------
  {
    name: "Critical Decisions — Premium Models Only",
    description: "High-stakes outputs (financial analysis, compliance decisions, production deployments) " \
                 "require the highest-quality models. Minimum quality score of 0.95. Cost is secondary.",
    rule_type: "quality_based",
    priority: 6,
    min_quality_score: 0.95,
    conditions: {
      "min_quality_score" => 0.95,
      "request_types" => %w[completion]
    },
    target: {
      "provider_ids" => premium_ids,
      "strategy" => "quality_optimized",
      "model_names" => %w[o3 claude-opus-4-6]
    }
  },
  {
    name: "Code Generation — High Quality + Function Calling",
    description: "Code generation and complex reasoning tasks need premium-tier models with " \
                 "strong coding benchmarks. Quality floor of 0.90 with preference for models " \
                 "that support structured output and tool use.",
    rule_type: "quality_based",
    priority: 14,
    min_quality_score: 0.90,
    conditions: {
      "min_quality_score" => 0.90,
      "capabilities" => %w[function_calling],
      "model_patterns" => ["gpt-4.*", "o3.*", "claude-opus.*", "claude-sonnet.*"]
    },
    target: {
      "provider_ids" => premium_ids,
      "strategy" => "quality_optimized",
      "model_names" => %w[gpt-4.1 o3 claude-opus-4-6 claude-sonnet-4-5]
    }
  },
  {
    name: "Customer-Facing Responses — Quality Floor",
    description: "Any output that will be shown directly to end customers (support replies, " \
                 "generated documentation, public content) must meet a minimum quality threshold " \
                 "of 0.85 to protect brand reputation.",
    rule_type: "quality_based",
    priority: 18,
    min_quality_score: 0.85,
    conditions: {
      "min_quality_score" => 0.85,
      "request_types" => %w[completion],
      "max_tokens" => 8000
    },
    target: {
      "provider_ids" => all_provider_ids,
      "strategy" => "hybrid",
      "model_names" => %w[gpt-4.1-mini claude-sonnet-4-5]
    }
  },

  # ---------------------------------------------------------------------------
  # CUSTOM RULES — Complex multi-condition routing
  # ---------------------------------------------------------------------------
  {
    name: "Long-Context Summarisation → Large Window Models",
    description: "Requests with large input payloads (>16K tokens) need models with extended context " \
                 "windows (128K+). Routes to models specifically tuned for long-document processing.",
    rule_type: "custom",
    priority: 7,
    conditions: {
      "min_tokens" => 16_000,
      "request_types" => %w[completion],
      "model_patterns" => ["gpt-4.*", "claude.*"]
    },
    target: {
      "provider_ids" => premium_ids,
      "strategy" => "cost_optimized",
      "model_names" => %w[gpt-4.1 claude-sonnet-4-5 claude-opus-4-6]
    }
  },
  {
    name: "Claude-Only for Sensitive Data",
    description: "Requests flagged for sensitive/regulated data processing (PII, PCI, HIPAA) " \
                 "are restricted to Anthropic models to minimise third-party data exposure. " \
                 "Matches requests where model pattern indicates Claude preference.",
    rule_type: "custom",
    priority: 4,
    conditions: {
      "capabilities" => %w[pii_safe],
      "model_patterns" => ["claude.*"]
    },
    target: {
      "provider_ids" => claude_ids,
      "strategy" => "quality_optimized",
      "model_names" => %w[claude-opus-4-6 claude-sonnet-4-5]
    }
  },
  {
    name: "Multi-Turn Agent Workflows → Balanced Hybrid",
    description: "Multi-step agent workflows that combine tool calling, reasoning, and code execution. " \
                 "Uses hybrid strategy that weighs cost (40%), latency (30%), quality (20%), " \
                 "and reliability (10%) for optimal provider selection across the workflow.",
    rule_type: "custom",
    priority: 22,
    conditions: {
      "capabilities" => %w[function_calling streaming],
      "min_tokens" => 500,
      "max_tokens" => 32_000,
      "request_types" => %w[completion]
    },
    target: {
      "provider_ids" => premium_ids,
      "strategy" => "hybrid",
      "model_names" => %w[gpt-4.1 claude-sonnet-4-5]
    }
  },
  {
    name: "Provider Failover — Round Robin Fallback",
    description: "Catch-all fallback rule at lowest priority. When no other rule matches, " \
                 "distribute requests across all healthy providers using round-robin. " \
                 "Ensures no single provider becomes a bottleneck during outages.",
    rule_type: "custom",
    priority: 999,
    conditions: {
      "request_types" => %w[completion embedding]
    },
    target: {
      "provider_ids" => all_provider_ids,
      "strategy" => "round_robin",
      "model_names" => %w[gpt-4.1-mini claude-sonnet-4-5]
    }
  },

  # ---------------------------------------------------------------------------
  # ML-OPTIMIZED RULES — Data-driven routing
  # ---------------------------------------------------------------------------
  {
    name: "ML-Optimised Task Router",
    description: "Uses historical routing decision data to dynamically select the best provider " \
                 "for each task type. The ML strategy analyses past success rates, latency percentiles, " \
                 "and cost-per-quality metrics to make real-time routing decisions. " \
                 "Requires at least 100 prior routing decisions to be effective.",
    rule_type: "ml_optimized",
    priority: 30,
    conditions: {
      "request_types" => %w[completion],
      "min_tokens" => 100
    },
    target: {
      "provider_ids" => all_provider_ids,
      "strategy" => "hybrid",
      "model_names" => %w[gpt-4.1 gpt-4.1-mini claude-sonnet-4-5 claude-opus-4-6]
    }
  },
  {
    name: "Adaptive Cost Optimiser",
    description: "ML-driven rule that learns which provider offers the best cost-to-quality ratio " \
                 "for different request profiles. Continuously adapts as provider pricing changes " \
                 "or new models are released. Weighted 60% cost, 25% quality, 15% latency.",
    rule_type: "ml_optimized",
    priority: 35,
    max_cost_per_1k_tokens: 0.02,
    conditions: {
      "max_cost_per_token" => 0.00002,
      "request_types" => %w[completion]
    },
    target: {
      "provider_ids" => all_provider_ids,
      "strategy" => "cost_optimized",
      "model_names" => %w[gpt-4.1-mini o4-mini claude-sonnet-4-5 claude-haiku-4-5]
    }
  }
]

created = 0
skipped = 0

rules.each do |rule_data|
  existing = admin_account.ai_model_routing_rules.find_by(name: rule_data[:name])
  if existing
    puts "  ⏭️  Already exists: #{rule_data[:name]}"
    skipped += 1
    next
  end

  admin_account.ai_model_routing_rules.create!(
    name: rule_data[:name],
    description: rule_data[:description],
    rule_type: rule_data[:rule_type],
    priority: rule_data[:priority],
    is_active: true,
    max_cost_per_1k_tokens: rule_data[:max_cost_per_1k_tokens],
    max_latency_ms: rule_data[:max_latency_ms],
    min_quality_score: rule_data[:min_quality_score],
    conditions: rule_data[:conditions],
    target: rule_data[:target]
  )
  puts "  ✅ Created: #{rule_data[:name]} (#{rule_data[:rule_type]}, priority #{rule_data[:priority]})"
  created += 1
rescue ActiveRecord::RecordInvalid => e
  puts "  ❌ Failed: #{rule_data[:name]} — #{e.message}"
end

puts "\n🔀 Model Routing Rules: #{created} created, #{skipped} skipped"
puts "   Rule types: #{rules.map { |r| r[:rule_type] }.tally.map { |k, v| "#{k}(#{v})" }.join(', ')}"
puts "   Priority range: #{rules.map { |r| r[:priority] }.minmax.join(' – ')}"
