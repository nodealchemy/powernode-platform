# frozen_string_literal: true

FactoryBot.define do
  factory :ai_merge_operation, class: "Ai::MergeOperation" do
    worktree_session factory: :ai_worktree_session
    worktree factory: [:ai_worktree, :completed]
    account { worktree_session.account }
    source_branch { worktree.branch_name }
    target_branch { "main" }
    strategy { "merge" }
    status { "pending" }
    merge_order { 0 }
    has_conflicts { false }
    conflict_files { [] }
    rolled_back { false }
    metadata { {} }

    trait :in_progress do
      status { "in_progress" }
      started_at { Time.current }
    end

    trait :completed do
      status { "completed" }
      started_at { 5.minutes.ago }
      completed_at { Time.current }
      merge_commit_sha { SecureRandom.hex(20) }
      duration_ms { 5000 }
    end

    trait :conflict do
      status { "conflict" }
      has_conflicts { true }
      conflict_files { ["src/file1.rb", "src/file2.rb"] }
      conflict_details { "CONFLICT (content): Merge conflict in src/file1.rb" }
      completed_at { Time.current }
    end

    trait :failed do
      status { "failed" }
      error_message { "Merge failed: fatal error" }
      error_code { "MERGE_FAILED" }
      completed_at { Time.current }
    end

    trait :rolled_back do
      status { "rolled_back" }
      merge_commit_sha { SecureRandom.hex(20) }
      rollback_commit_sha { SecureRandom.hex(20) }
      rolled_back { true }
      rolled_back_at { Time.current }
    end

    trait :squash do
      strategy { "squash" }
    end
  end
end
