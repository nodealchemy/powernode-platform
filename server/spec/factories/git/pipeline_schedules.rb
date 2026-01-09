# frozen_string_literal: true

FactoryBot.define do
  factory :git_pipeline_schedule, class: 'Git::PipelineSchedule' do
    association :repository, factory: :git_repository
    association :account

    sequence(:name) { |n| "Schedule #{n}" }
    description { "Daily CI pipeline run" }
    cron_expression { "0 9 * * *" }  # Every day at 9 AM
    timezone { "UTC" }
    ref { "main" }
    workflow_file { ".github/workflows/ci.yml" }
    inputs { {} }
    is_active { true }
    next_run_at { 1.day.from_now }
    last_run_at { nil }
    last_run_status { nil }
    run_count { 0 }
    success_count { 0 }
    failure_count { 0 }
    consecutive_failures { 0 }

    trait :active do
      is_active { true }
      next_run_at { 1.hour.from_now }
    end

    trait :inactive do
      is_active { false }
      next_run_at { nil }
    end

    trait :with_history do
      run_count { 50 }
      success_count { 45 }
      failure_count { 5 }
      last_run_at { 1.day.ago }
      last_run_status { "success" }
    end

    trait :failing do
      consecutive_failures { 3 }
      last_run_status { "failure" }
      last_run_at { 1.hour.ago }
    end

    trait :overdue do
      is_active { true }
      next_run_at { 1.hour.ago }
    end

    trait :hourly do
      cron_expression { "0 * * * *" }
    end

    trait :weekly do
      cron_expression { "0 9 * * 1" }  # Every Monday at 9 AM
    end

    trait :with_inputs do
      inputs { { "deploy_env" => "staging", "run_tests" => "true" } }
    end
  end
end
