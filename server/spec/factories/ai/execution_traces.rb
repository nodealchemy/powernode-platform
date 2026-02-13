# frozen_string_literal: true

FactoryBot.define do
  factory :ai_execution_trace, class: "Ai::ExecutionTrace" do
    account
    sequence(:name) { |n| "Trace #{n}" }
    trace_id { SecureRandom.uuid }
    trace_type { "workflow" }
    status { "running" }
    metadata { {} }
    total_tokens { 0 }
    total_cost { 0.0 }

    trait :completed do
      status { "completed" }
      started_at { 10.minutes.ago }
      completed_at { Time.current }
      duration_ms { 600_000 }
    end

    trait :agent_trace do
      trace_type { "agent" }
    end

    trait :failed do
      status { "failed" }
      error { "Execution error occurred" }
    end
  end
end
