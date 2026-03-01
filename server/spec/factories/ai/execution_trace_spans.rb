# frozen_string_literal: true

FactoryBot.define do
  factory :ai_execution_trace_span, class: "Ai::ExecutionTraceSpan" do
    association :execution_trace, factory: :ai_execution_trace
    sequence(:name) { |n| "Span #{n}" }
    span_id { SecureRandom.uuid }
    span_type { "llm_call" }
    status { "running" }
    events { [] }
    tokens { {} }
    metadata { {} }

    trait :completed do
      status { "completed" }
      started_at { 5.minutes.ago }
      completed_at { Time.current }
      duration_ms { 300_000 }
    end

    trait :tool_call do
      span_type { "tool_call" }
    end

    trait :failed do
      status { "failed" }
      error { "Span execution failed" }
    end
  end
end
