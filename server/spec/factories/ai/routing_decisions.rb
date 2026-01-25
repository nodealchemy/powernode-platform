# frozen_string_literal: true

FactoryBot.define do
  factory :ai_routing_decision, class: "Ai::RoutingDecision" do
    account
    association :routing_rule, factory: :ai_model_routing_rule, strategy: :build
    association :selected_provider, factory: :ai_provider, strategy: :build
    request_type { "chat" }
    strategy_used { "cost_optimized" }
    outcome { nil }
    decision_reason { "Selected based on cost optimization" }
    estimated_cost_usd { 0.001 }
    estimated_tokens { 500 }
    actual_cost_usd { nil }
    actual_latency_ms { nil }
    actual_tokens_used { nil }
    quality_score { nil }
    savings_usd { nil }
    alternative_cost_usd { nil }
    request_metadata { {} }
    candidates_evaluated { [] }
    scoring_breakdown { {} }

    trait :successful do
      outcome { "succeeded" }
      actual_cost_usd { 0.0008 }
      actual_latency_ms { 250 }
      actual_tokens_used { 480 }
      quality_score { 0.92 }
    end

    trait :failed do
      outcome { "failed" }
      actual_cost_usd { 0.0 }
      actual_latency_ms { nil }
      actual_tokens_used { 0 }
    end

    trait :timeout do
      outcome { "timeout" }
      actual_latency_ms { 30000 }
    end

    trait :rate_limited do
      outcome { "rate_limited" }
      decision_reason { "Provider rate limit exceeded, using fallback" }
    end

    trait :fallback do
      outcome { "fallback" }
      strategy_used { "fallback" }
      decision_reason { "Primary provider unavailable, using fallback" }
    end

    trait :with_savings do
      outcome { "succeeded" }
      actual_cost_usd { 0.0008 }
      alternative_cost_usd { 0.0015 }
      savings_usd { 0.0007 }
    end

    trait :round_robin do
      strategy_used { "round_robin" }
    end

    trait :weighted do
      strategy_used { "weighted" }
    end

    trait :latency_optimized do
      strategy_used { "latency_optimized" }
    end

    trait :quality_optimized do
      strategy_used { "quality_optimized" }
    end

    trait :ml_based do
      strategy_used { "ml_based" }
    end

    trait :hybrid do
      strategy_used { "hybrid" }
    end

    trait :with_candidates do
      candidates_evaluated do
        [
          {
            "provider_id" => SecureRandom.uuid,
            "provider_name" => "Provider A",
            "score" => 0.95,
            "cost_estimate" => 0.001,
            "latency_estimate" => 200,
            "selected" => true
          },
          {
            "provider_id" => SecureRandom.uuid,
            "provider_name" => "Provider B",
            "score" => 0.85,
            "cost_estimate" => 0.0015,
            "latency_estimate" => 300,
            "selected" => false
          }
        ]
      end
    end

    trait :with_scoring do
      scoring_breakdown do
        {
          "cost_score" => 0.9,
          "latency_score" => 0.85,
          "quality_score" => 0.88,
          "availability_score" => 1.0,
          "weighted_total" => 0.91
        }
      end
    end

    trait :with_metadata do
      request_metadata do
        {
          "user_id" => SecureRandom.uuid,
          "session_id" => SecureRandom.hex(16),
          "model_requested" => "gpt-4",
          "max_tokens" => 1000
        }
      end
    end

    trait :for_workflow do
      association :workflow_run, factory: :ai_workflow_run, strategy: :build
    end

    trait :for_agent do
      association :agent_execution, factory: :ai_agent_execution, strategy: :build
    end
  end
end
