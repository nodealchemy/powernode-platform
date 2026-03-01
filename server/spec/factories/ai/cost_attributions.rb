# frozen_string_literal: true

FactoryBot.define do
  factory :ai_cost_attribution, class: "Ai::CostAttribution" do
    account
    association :provider, factory: :ai_provider
    source_type { "workflow" }
    source_id { SecureRandom.uuid }
    source_name { "Test Workflow" }
    cost_category { "ai_inference" }
    amount_usd { 0.50 }
    currency { "USD" }
    attribution_date { Date.current }
    tokens_used { 1000 }
    api_calls { 5 }
    cost_per_token { 0.0005 }
    compute_minutes { nil }
    storage_gb { nil }
    model_name { "gpt-4" }
    roi_metric_id { nil }
    metadata { {} }

    trait :agent do
      source_type { "agent" }
      source_name { "Test Agent" }
    end

    trait :execution do
      source_type { "execution" }
      source_name { "Agent Execution" }
    end

    trait :provider_source do
      source_type { "provider" }
      source_name { "Test Provider" }
    end

    trait :team do
      source_type { "team" }
      source_name { "Agent Team" }
    end

    trait :ai_inference do
      cost_category { "ai_inference" }
      tokens_used { 2000 }
      api_calls { 10 }
    end

    trait :ai_training do
      cost_category { "ai_training" }
      tokens_used { 50000 }
      amount_usd { 5.00 }
    end

    trait :embedding do
      cost_category { "embedding" }
      tokens_used { 10000 }
      amount_usd { 0.10 }
      model_name { "text-embedding-ada-002" }
    end

    trait :storage do
      cost_category { "storage" }
      tokens_used { nil }
      storage_gb { 10.5 }
      amount_usd { 2.50 }
    end

    trait :compute do
      cost_category { "compute" }
      tokens_used { nil }
      compute_minutes { 60 }
      amount_usd { 1.20 }
    end

    trait :api_calls_category do
      cost_category { "api_calls" }
      api_calls { 100 }
      amount_usd { 0.10 }
    end

    trait :bandwidth do
      cost_category { "bandwidth" }
      amount_usd { 0.05 }
    end

    trait :other do
      cost_category { "other" }
      amount_usd { 0.25 }
    end

    trait :high_cost do
      amount_usd { 100.00 }
      tokens_used { 200000 }
      api_calls { 500 }
    end

    trait :low_cost do
      amount_usd { 0.001 }
      tokens_used { 10 }
      api_calls { 1 }
    end

    trait :with_roi_metric do
      association :roi_metric, factory: :ai_roi_metric
    end

    trait :yesterday do
      attribution_date { Date.yesterday }
    end

    trait :last_week do
      attribution_date { 1.week.ago.to_date }
    end

    trait :with_metadata do
      metadata do
        {
          "request_id" => SecureRandom.uuid,
          "user_id" => SecureRandom.uuid,
          "session_id" => SecureRandom.hex(16),
          "region" => "us-east-1"
        }
      end
    end
  end
end
