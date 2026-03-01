# frozen_string_literal: true

FactoryBot.define do
  factory :ai_ralph_iteration, class: "Ai::RalphIteration" do
    association :ralph_loop, factory: :ai_ralph_loop
    sequence(:iteration_number)
    status { "pending" }
    cost { 0.0 }
    tokens_input { 0 }
    duration_ms { nil }
    check_results { {} }
    ai_response_metadata { {} }
    error_details { {} }

    trait :running do
      status { "running" }
      started_at { Time.current }
    end

    trait :completed do
      status { "completed" }
      started_at { 10.minutes.ago }
      completed_at { Time.current }
      duration_ms { 600_000 }
      checks_passed { true }
    end

    trait :failed do
      status { "failed" }
      started_at { 5.minutes.ago }
      completed_at { Time.current }
      error_message { "Iteration failed" }
      error_code { "ITERATION_ERROR" }
    end
  end
end
