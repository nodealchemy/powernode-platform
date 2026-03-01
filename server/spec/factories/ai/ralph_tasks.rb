# frozen_string_literal: true

FactoryBot.define do
  factory :ai_ralph_task, class: "Ai::RalphTask" do
    association :ralph_loop, factory: :ai_ralph_loop

    sequence(:task_key) { |n| "task_#{n}" }
    description { "A test task for Ralph Loop" }
    status { "pending" }
    priority { 0 }
    sequence(:position) { |n| n }
    dependencies { [] }
    acceptance_criteria { "Task should complete successfully" }
    metadata { {} }

    trait :pending do
      status { "pending" }
    end

    trait :in_progress do
      status { "in_progress" }
    end

    trait :passed do
      status { "passed" }
      iteration_completed_at { Time.current }
      completed_in_iteration { 1 }
    end

    trait :failed do
      status { "failed" }
      error_message { "Task failed" }
      error_code { "TASK_FAILURE" }
    end

    trait :skipped do
      status { "skipped" }
    end

    trait :blocked do
      status { "blocked" }
      error_message { "Waiting for dependencies" }
    end

    trait :high_priority do
      priority { 10 }
    end

    trait :medium_priority do
      priority { 5 }
    end

    trait :low_priority do
      priority { 1 }
    end

    trait :with_dependencies do
      dependencies { %w[task_1 task_2] }
    end
  end
end
