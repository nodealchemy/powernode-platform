# frozen_string_literal: true

FactoryBot.define do
  factory :circuit_breaker, class: "Monitoring::CircuitBreaker" do
    sequence(:name) { |n| "circuit_breaker_#{n}_#{SecureRandom.hex(3)}" }
    service { %w[ai_provider payment_gateway external_api worker_service].sample }
    provider { %w[openai anthropic stripe paypal].sample }
    state { 'closed' }
    failure_count { 0 }
    success_count { 0 }
    failure_threshold { 5 }
    success_threshold { 2 }
    timeout_seconds { 30 }
    reset_timeout_seconds { 60 }
    configuration do
      {
        auto_reset: true,
        alert_on_open: true,
        max_retry_attempts: 3
      }
    end
    metrics do
      {
        total_requests: 0,
        successes: 0,
        failures: 0
      }
    end

    trait :closed do
      state { 'closed' }
      failure_count { 0 }
      success_count { 10 }
      last_success_at { 1.minute.ago }
    end

    trait :open do
      state { 'open' }
      failure_count { 5 }
      success_count { 0 }
      last_failure_at { 2.minutes.ago }
      opened_at { 2.minutes.ago }
    end

    trait :half_open do
      state { 'half_open' }
      failure_count { 5 }
      success_count { 1 }
      opened_at { 5.minutes.ago }
      half_opened_at { 1.minute.ago }
      last_failure_at { 6.minutes.ago }
    end

    trait :ai_provider_breaker do
      service { 'ai_provider' }
      provider { 'openai' }
      name { 'openai_api_breaker' }
      configuration do
        {
          auto_reset: true,
          alert_on_open: true,
          provider_specific: {
            model: 'gpt-4',
            endpoint: 'chat/completions'
          }
        }
      end
    end

    trait :payment_breaker do
      service { 'payment_gateway' }
      provider { 'stripe' }
      name { 'stripe_payment_breaker' }
      timeout_seconds { 45 }
      configuration do
        {
          auto_reset: false,
          alert_on_open: true,
          critical_service: true
        }
      end
    end

    trait :recently_failed do
      failure_count { 3 }
      last_failure_at { 30.seconds.ago }
      metrics do
        {
          total_requests: 150,
          successes: 147,
          failures: 3,
          last_duration_ms: 5000
        }
      end
    end

    trait :with_events do
      after(:create) do |breaker|
        create_list(:circuit_breaker_event, 5, circuit_breaker: breaker)
      end
    end
  end
end
