# frozen_string_literal: true

FactoryBot.define do
  factory :ai_model_routing_rule, class: "Ai::ModelRoutingRule" do
    account
    sequence(:name) { |n| "Routing Rule #{n}" }
    description { "A test routing rule for model selection" }
    rule_type { "capability_based" }
    priority { 100 }
    is_active { true }
    conditions do
      {
        "capabilities" => ["text_generation"],
        "max_cost_per_token" => 0.01
      }
    end
    target do
      {
        "strategy" => "cost_optimized",
        "provider_ids" => [],
        "model_names" => []
      }
    end
    times_matched { 0 }
    times_succeeded { 0 }
    times_failed { 0 }
    last_matched_at { nil }
    max_cost_per_1k_tokens { nil }
    max_latency_ms { nil }
    min_quality_score { nil }

    trait :inactive do
      is_active { false }
    end

    trait :cost_based do
      rule_type { "cost_based" }
      conditions do
        {
          "max_cost_per_token" => 0.005,
          "min_tokens" => 100,
          "max_tokens" => 10000
        }
      end
      target do
        {
          "strategy" => "cost_optimized"
        }
      end
    end

    trait :latency_based do
      rule_type { "latency_based" }
      max_latency_ms { 500.0 }
      conditions do
        {
          "max_latency_ms" => 500
        }
      end
      target do
        {
          "strategy" => "latency_optimized"
        }
      end
    end

    trait :quality_based do
      rule_type { "quality_based" }
      min_quality_score { 0.85 }
      conditions do
        {
          "min_quality_score" => 0.85
        }
      end
      target do
        {
          "strategy" => "quality_optimized"
        }
      end
    end

    trait :ml_optimized do
      rule_type { "ml_optimized" }
      target do
        {
          "strategy" => "hybrid"
        }
      end
    end

    trait :custom do
      rule_type { "custom" }
      conditions do
        {
          "request_types" => ["chat", "completion"],
          "model_patterns" => ["gpt-4.*", "claude-3.*"]
        }
      end
    end

    trait :high_priority do
      priority { 10 }
    end

    trait :low_priority do
      priority { 900 }
    end

    trait :with_stats do
      times_matched { 100 }
      times_succeeded { 95 }
      times_failed { 5 }
      last_matched_at { 1.hour.ago }
    end

    trait :poorly_performing do
      times_matched { 50 }
      times_succeeded { 30 }
      times_failed { 20 }
      last_matched_at { 2.hours.ago }
    end
  end
end
