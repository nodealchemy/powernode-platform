# frozen_string_literal: true

FactoryBot.define do
  factory :ai_circuit_breaker, class: "Ai::CircuitBreaker" do
    account
    association :agent, factory: :ai_agent
    action_type { "execute_tool" }
    state { "closed" }
    failure_count { 0 }
    success_count { 0 }
    failure_threshold { 5 }
    success_threshold { 3 }
    cooldown_seconds { 300 }
    history { [] }

    trait :open do
      state { "open" }
      failure_count { 5 }
      opened_at { Time.current }
    end

    trait :half_open do
      state { "half_open" }
      half_opened_at { Time.current }
    end
  end
end
