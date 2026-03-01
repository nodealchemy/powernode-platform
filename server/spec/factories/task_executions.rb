# frozen_string_literal: true

FactoryBot.define do
  factory :task_execution do
    association :scheduled_task
    status { "running" }
    started_at { Time.current }
    result { {} }

    trait :running do
      status { "running" }
    end

    trait :completed do
      status { "completed" }
      completed_at { Time.current }
      duration_ms { 5000 }
    end

    trait :failed do
      status { "failed" }
      completed_at { Time.current }
      duration_ms { 1000 }
      error_message { "Execution failed" }
    end

    trait :timeout do
      status { "timeout" }
      completed_at { Time.current }
      duration_ms { 30000 }
      error_message { "Execution timed out" }
    end
  end
end
