# frozen_string_literal: true

FactoryBot.define do
  factory :ai_worktree_session, class: "Ai::WorktreeSession" do
    account
    association :initiated_by, factory: :user
    repository_path { Rails.root.join("tmp", "test_repo_#{SecureRandom.hex(4)}").to_s }
    base_branch { "main" }
    status { "pending" }
    merge_strategy { "sequential" }
    max_parallel { 4 }
    total_worktrees { 3 }
    completed_worktrees { 0 }
    failed_worktrees { 0 }
    auto_cleanup { true }
    configuration { {} }
    merge_config { {} }
    metadata { {} }

    trait :provisioning do
      status { "provisioning" }
      started_at { Time.current }
    end

    trait :active do
      status { "active" }
      started_at { 1.hour.ago }
    end

    trait :merging do
      status { "merging" }
      started_at { 1.hour.ago }
    end

    trait :completed do
      status { "completed" }
      started_at { 1.hour.ago }
      completed_at { Time.current }
      duration_ms { 3600000 }
      completed_worktrees { 3 }
    end

    trait :failed do
      status { "failed" }
      started_at { 1.hour.ago }
      completed_at { Time.current }
      error_message { "All worktrees failed" }
      error_code { "ALL_FAILED" }
    end

    trait :cancelled do
      status { "cancelled" }
      started_at { 1.hour.ago }
      completed_at { Time.current }
    end

    trait :integration_branch_strategy do
      merge_strategy { "integration_branch" }
      integration_branch { "integration/test" }
    end

    trait :manual_strategy do
      merge_strategy { "manual" }
    end

    trait :abort_policy do
      configuration { { "failure_policy" => "abort" } }
    end

    trait :with_worktrees do
      transient do
        worktrees_count { 3 }
      end

      after(:create) do |session, evaluator|
        create_list(:ai_worktree, evaluator.worktrees_count, worktree_session: session, account: session.account)
      end
    end
  end
end
