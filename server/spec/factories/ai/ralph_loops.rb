# frozen_string_literal: true

FactoryBot.define do
  factory :ai_ralph_loop, class: "Ai::RalphLoop" do
    association :account

    sequence(:name) { |n| "Ralph Loop #{n}" }
    description { "A test Ralph Loop for iterative AI development" }
    status { "pending" }
    association :default_agent, factory: :ai_agent
    max_iterations { 10 }
    current_iteration { 0 }
    scheduling_mode { "manual" }
    branch { "main" }
    configuration { {} }
    prd_json { {} }
    learnings { [] }
    total_tasks { 0 }
    completed_tasks { 0 }
    failed_tasks { 0 }

    trait :pending do
      status { "pending" }
    end

    trait :running do
      status { "running" }
      started_at { Time.current }
    end

    trait :paused do
      status { "paused" }
      started_at { 1.hour.ago }
    end

    trait :completed do
      status { "completed" }
      started_at { 2.hours.ago }
      completed_at { Time.current }
    end

    trait :failed do
      status { "failed" }
      started_at { 1.hour.ago }
      completed_at { Time.current }
      error_message { "Test failure" }
      error_code { "TEST_FAILURE" }
    end

    trait :cancelled do
      status { "cancelled" }
      started_at { 1.hour.ago }
      completed_at { Time.current }
    end

    trait :with_repository do
      repository_url { "https://github.com/test/repo.git" }
      branch { "main" }
    end

    trait :with_tasks do
      after(:create) do |ralph_loop|
        create_list(:ai_ralph_task, 3, ralph_loop: ralph_loop)
        ralph_loop.update!(total_tasks: 3)
      end
    end

    trait :with_learnings do
      learnings do
        [
          { "text" => "Learning 1", "iteration" => 1, "timestamp" => 1.hour.ago.iso8601 },
          { "text" => "Learning 2", "iteration" => 2, "timestamp" => 30.minutes.ago.iso8601 }
        ]
      end
    end

    trait :scheduled do
      scheduling_mode { "scheduled" }
      schedule_config do
        {
          "cron_expression" => "0 * * * *",
          "timezone" => "UTC"
        }
      end
    end

    trait :continuous do
      scheduling_mode { "continuous" }
      schedule_config do
        {
          "iteration_interval_seconds" => 300
        }
      end
    end
  end
end
