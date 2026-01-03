# frozen_string_literal: true

FactoryBot.define do
  factory :git_pipeline_job do
    association :git_pipeline
    association :account

    sequence(:external_id) { |n| "job#{n}" }
    sequence(:name) { |n| "Build Job #{n}" }
    status { 'pending' }
    conclusion { nil }
    step_number { 1 }
    runner_name { nil }
    runner_id { nil }
    runner_os { nil }
    logs_url { nil }
    logs_content { nil }
    duration_seconds { nil }
    steps { [] }
    outputs { {} }
    started_at { nil }
    completed_at { nil }

    trait :pending do
      status { 'pending' }
      conclusion { nil }
    end

    trait :running do
      status { 'in_progress' }
      conclusion { nil }
      started_at { 2.minutes.ago }
      runner_name { 'ubuntu-latest' }
      runner_os { 'Linux' }
    end

    trait :success do
      status { 'completed' }
      conclusion { 'success' }
      started_at { 5.minutes.ago }
      completed_at { 2.minutes.ago }
      duration_seconds { 180 }
      runner_name { 'ubuntu-latest' }
      runner_os { 'Linux' }
    end

    trait :failure do
      status { 'completed' }
      conclusion { 'failure' }
      started_at { 5.minutes.ago }
      completed_at { 3.minutes.ago }
      duration_seconds { 120 }
      runner_name { 'ubuntu-latest' }
      runner_os { 'Linux' }
    end

    trait :with_logs do
      logs_content do
        <<~LOGS
          Running tests...
          ✓ Test 1 passed
          ✓ Test 2 passed
          ✓ Test 3 passed
          All tests passed!
        LOGS
      end
    end

    trait :with_steps do
      steps do
        [
          { name: 'Checkout', status: 'completed', conclusion: 'success', number: 1 },
          { name: 'Setup Ruby', status: 'completed', conclusion: 'success', number: 2 },
          { name: 'Run tests', status: 'running', conclusion: nil, number: 3 }
        ]
      end
    end

    trait :with_outputs do
      outputs do
        {
          test_results: '15 passed, 0 failed',
          coverage: '85.5%'
        }
      end
    end
  end
end
