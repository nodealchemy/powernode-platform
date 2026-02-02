# frozen_string_literal: true

FactoryBot.define do
  factory :git_pipeline, class: 'Devops::GitPipeline' do
    association :repository, factory: :git_repository
    association :account

    sequence(:external_id) { |n| "pipeline#{n}" }
    sequence(:name) { |n| "CI Pipeline #{n}" }
    status { 'pending' }
    conclusion { nil }
    trigger_event { 'push' }
    ref { 'refs/heads/main' }
    sha { SecureRandom.hex(20) }
    actor_username { 'testuser' }
    web_url { nil }
    logs_url { nil }
    sequence(:run_number) { |n| n }
    run_attempt { 1 }
    total_jobs { 3 }
    completed_jobs { 0 }
    failed_jobs { 0 }
    duration_seconds { nil }
    workflow_config { {} }
    started_at { nil }
    completed_at { nil }

    trait :pending do
      status { 'pending' }
      conclusion { nil }
    end

    trait :running do
      status { 'in_progress' }
      conclusion { nil }
      started_at { 5.minutes.ago }
      completed_jobs { 1 }
    end

    trait :completed do
      status { 'completed' }
      conclusion { 'success' }
      started_at { 10.minutes.ago }
      completed_at { 5.minutes.ago }
      completed_jobs { 3 }
      duration_seconds { 300 }
    end

    trait :success do
      status { 'completed' }
      conclusion { 'success' }
      started_at { 10.minutes.ago }
      completed_at { 5.minutes.ago }
      completed_jobs { 3 }
      failed_jobs { 0 }
      duration_seconds { 300 }
    end

    trait :failure do
      status { 'completed' }
      conclusion { 'failure' }
      started_at { 10.minutes.ago }
      completed_at { 5.minutes.ago }
      completed_jobs { 2 }
      failed_jobs { 1 }
      duration_seconds { 180 }
    end

    trait :cancelled do
      status { 'completed' }
      conclusion { 'cancelled' }
      started_at { 10.minutes.ago }
      completed_at { 3.minutes.ago }
      completed_jobs { 1 }
      duration_seconds { 420 }
    end

    trait :with_workflow_config do
      workflow_config do
        {
          file: '.github/workflows/ci.yml',
          name: 'CI',
          on: { push: { branches: [ 'main' ] } }
        }
      end
    end
  end
end
