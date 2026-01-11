# frozen_string_literal: true

FactoryBot.define do
  factory :git_workflow_trigger, class: 'Devops::GitWorkflowTrigger' do
    association :ai_workflow_trigger
    association :repository, factory: :git_repository, strategy: :null

    event_type { 'push' }
    branch_pattern { '*' }
    path_pattern { nil }
    status { 'active' }
    is_active { true }
    event_filters { {} }
    payload_mapping { {} }
    metadata { {} }
    trigger_count { 0 }

    trait :for_repository do
      association :repository, factory: :git_repository
    end

    trait :push do
      event_type { 'push' }
    end

    trait :pull_request do
      event_type { 'pull_request' }
      event_filters { { 'action' => %w[opened synchronize] } }
    end

    trait :workflow_run do
      event_type { 'workflow_run' }
      event_filters { { 'action' => 'completed', 'workflow_run.conclusion' => 'success' } }
    end

    trait :main_branch do
      branch_pattern { 'main' }
    end

    trait :release_branches do
      branch_pattern { 'release/*' }
    end

    trait :feature_branches do
      branch_pattern { 'feature/*' }
    end

    trait :with_path_filter do
      path_pattern { 'src/**' }
    end

    trait :with_payload_mapping do
      payload_mapping do
        {
          'commit_sha' => 'head_commit.id',
          'commit_message' => 'head_commit.message',
          'branch' => 'ref',
          'author' => 'head_commit.author.name'
        }
      end
    end

    trait :paused do
      status { 'paused' }
    end

    trait :disabled do
      status { 'disabled' }
      is_active { false }
    end

    trait :with_trigger_history do
      trigger_count { 10 }
      last_triggered_at { 1.hour.ago }
    end
  end
end
