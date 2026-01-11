# frozen_string_literal: true

FactoryBot.define do
  factory :circuit_breaker_event, class: "Monitoring::CircuitBreakerEvent" do
    circuit_breaker
    event_type { 'success' }
    duration_ms { rand(100..5000) }
    failure_count { 0 }

    trait :success do
      event_type { 'success' }
      duration_ms { rand(100..2000) }
    end

    trait :failure do
      event_type { 'failure' }
      error_message { "Request failed after #{rand(1..10)} attempts" }
      duration_ms { rand(1000..10000) }
      failure_count { circuit_breaker.failure_count + 1 }
    end

    trait :timeout do
      event_type { 'timeout' }
      error_message { 'Request timeout exceeded' }
      duration_ms { 30_000 }
    end

    trait :state_change do
      event_type { 'state_change' }
      old_state { 'closed' }
      new_state { 'open' }
      error_message { 'Circuit breaker opened due to high failure rate' }
      failure_count { 5 }
    end

    trait :opened_to_half_open do
      event_type { 'state_change' }
      old_state { 'open' }
      new_state { 'half_open' }
      error_message { 'Attempting reset after timeout period' }
    end

    trait :half_open_to_closed do
      event_type { 'state_change' }
      old_state { 'half_open' }
      new_state { 'closed' }
      error_message { 'Circuit breaker recovered successfully' }
    end
  end
end
