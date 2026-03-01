# frozen_string_literal: true

FactoryBot.define do
  factory :ai_provider_metric, class: "Ai::ProviderMetric" do
    account
    association :provider, factory: :ai_provider
    granularity { "minute" }
    recorded_at { Time.current.beginning_of_minute }
    request_count { 10 }
    success_count { 9 }
    failure_count { 1 }
    timeout_count { 0 }
    rate_limit_count { 0 }
    total_input_tokens { 1000 }
    total_output_tokens { 500 }
    total_tokens { 1500 }
    total_cost_usd { 0.015 }
    avg_latency_ms { 250.0 }
    min_latency_ms { 100.0 }
    max_latency_ms { 500.0 }
    p50_latency_ms { 200.0 }
    p95_latency_ms { 400.0 }
    p99_latency_ms { 480.0 }
    error_breakdown { {} }
    model_breakdown { {} }
    consecutive_failures { 0 }

    trait :daily do
      granularity { "day" }
      recorded_at { Time.current.beginning_of_day }
    end

    trait :hourly do
      granularity { "hour" }
      recorded_at { Time.current.beginning_of_hour }
    end

    trait :with_model_breakdown do
      model_breakdown do
        {
          "gpt-4.1" => { "requests" => 5, "tokens" => 1000, "cost" => 0.01 },
          "claude-sonnet-4" => { "requests" => 5, "tokens" => 500, "cost" => 0.005 }
        }
      end
    end

    trait :unhealthy do
      success_count { 5 }
      failure_count { 5 }
      consecutive_failures { 6 }
    end
  end
end
