# frozen_string_literal: true

FactoryBot.define do
  factory :ai_cost_optimization_log, class: "Ai::CostOptimizationLog" do
    account
    optimization_type { "provider_switch" }
    status { "identified" }
    description { "Consider switching to a more cost-effective provider" }
    resource_type { "provider" }
    resource_id { SecureRandom.uuid }
    current_cost_usd { 100.00 }
    optimized_cost_usd { 80.00 }
    potential_savings_usd { 20.00 }
    savings_percentage { 20.00 }
    actual_savings_usd { nil }
    recommendation do
      {
        "current_provider" => "Provider A",
        "alternatives" => [ "Provider B", "Provider C" ],
        "reason" => "Same capabilities at lower cost"
      }
    end
    before_state { {} }
    after_state { {} }
    identified_at { Time.current }
    applied_at { nil }
    validated_at { nil }
    analysis_period_start { 30.days.ago.to_date }
    analysis_period_end { Date.current }

    trait :analyzing do
      status { "analyzing" }
    end

    trait :recommended do
      status { "recommended" }
      recommendation do
        {
          "current_provider" => "Provider A",
          "alternatives" => [ "Provider B" ],
          "reason" => "Same capabilities at lower cost",
          "confidence" => 0.85,
          "estimated_impact" => "medium"
        }
      end
    end

    trait :applied do
      status { "applied" }
      applied_at { 1.day.ago }
      after_state do
        {
          "new_provider" => "Provider B",
          "applied_by" => SecureRandom.uuid
        }
      end
    end

    trait :validated do
      status { "validated" }
      applied_at { 1.week.ago }
      validated_at { Time.current }
      actual_savings_usd { 18.50 }
    end

    trait :rejected do
      status { "rejected" }
      recommendation do
        {
          "current_provider" => "Provider A",
          "rejection_reason" => "Provider B does not meet SLA requirements"
        }
      end
    end

    trait :expired do
      status { "expired" }
      identified_at { 45.days.ago }
    end

    trait :provider_switch do
      optimization_type { "provider_switch" }
      resource_type { "provider" }
      description { "Switch to more cost-effective provider with same capabilities" }
    end

    trait :model_downgrade do
      optimization_type { "model_downgrade" }
      resource_type { "workflow" }
      description { "Use a smaller, less expensive model for simple tasks" }
      potential_savings_usd { 30.00 }
      recommendation do
        {
          "current_model" => "gpt-4",
          "recommended_model" => "gpt-3.5-turbo",
          "reason" => "Task complexity does not require GPT-4 capabilities"
        }
      end
    end

    trait :caching do
      optimization_type { "caching" }
      resource_type { "agent" }
      description { "Implement response caching for repetitive queries" }
      potential_savings_usd { 25.00 }
      recommendation do
        {
          "cache_hit_rate_estimate" => 0.3,
          "suggestion" => "Implement semantic caching for similar prompts"
        }
      end
    end

    trait :batching do
      optimization_type { "batching" }
      resource_type { "workflow" }
      description { "Batch similar requests to reduce API overhead" }
      potential_savings_usd { 15.00 }
      recommendation do
        {
          "current_request_pattern" => "individual",
          "recommended_batch_size" => 10,
          "suggestion" => "Group similar requests into batches"
        }
      end
    end

    trait :rate_optimization do
      optimization_type { "rate_optimization" }
      resource_type { "account" }
      description { "Optimize API rate usage to avoid overages" }
      potential_savings_usd { 50.00 }
    end

    trait :usage_reduction do
      optimization_type { "usage_reduction" }
      resource_type { "workflow" }
      description { "Reduce unnecessary API calls through prompt optimization" }
      potential_savings_usd { 40.00 }
      recommendation do
        {
          "current_avg_tokens" => 2000,
          "recommended_avg_tokens" => 1200,
          "suggestion" => "Optimize prompts to be more concise"
        }
      end
    end

    trait :high_impact do
      potential_savings_usd { 500.00 }
      current_cost_usd { 1000.00 }
      savings_percentage { 50.00 }
    end

    trait :low_impact do
      potential_savings_usd { 5.00 }
      current_cost_usd { 50.00 }
      savings_percentage { 10.00 }
    end

    trait :with_before_state do
      before_state do
        {
          "provider" => "Provider A",
          "monthly_cost" => 100.00,
          "avg_latency_ms" => 300,
          "avg_tokens_per_request" => 1500
        }
      end
    end

    trait :with_after_state do
      status { "applied" }
      applied_at { 1.day.ago }
      after_state do
        {
          "provider" => "Provider B",
          "monthly_cost" => 80.00,
          "avg_latency_ms" => 350,
          "avg_tokens_per_request" => 1500
        }
      end
    end
  end
end
