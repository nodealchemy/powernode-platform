# frozen_string_literal: true

FactoryBot.define do
  factory :ai_worktree, class: "Ai::Worktree" do
    worktree_session factory: :ai_worktree_session
    account { worktree_session.account }
    sequence(:branch_name) { |n| "worktree/test#{SecureRandom.hex(4)}/task-#{n}" }
    sequence(:worktree_path) { |n| "/tmp/worktrees/test/task-#{n}-#{SecureRandom.hex(4)}" }
    status { "pending" }
    locked { false }
    healthy { true }
    commit_count { 0 }
    metadata { {} }

    trait :creating do
      status { "creating" }
    end

    trait :ready do
      status { "ready" }
      ready_at { Time.current }
      base_commit_sha { SecureRandom.hex(20) }
      head_commit_sha { SecureRandom.hex(20) }
    end

    trait :in_use do
      status { "in_use" }
      ready_at { 30.minutes.ago }
      base_commit_sha { SecureRandom.hex(20) }
      head_commit_sha { SecureRandom.hex(20) }
    end

    trait :completed do
      status { "completed" }
      ready_at { 1.hour.ago }
      completed_at { Time.current }
      duration_ms { 1800000 }
      base_commit_sha { SecureRandom.hex(20) }
      head_commit_sha { SecureRandom.hex(20) }
      files_changed { 5 }
      lines_added { 120 }
      lines_removed { 30 }
    end

    trait :failed do
      status { "failed" }
      completed_at { Time.current }
      error_message { "Task execution failed" }
      error_code { "EXECUTION_FAILED" }
    end

    trait :merged do
      status { "merged" }
      ready_at { 2.hours.ago }
      completed_at { 1.hour.ago }
      base_commit_sha { SecureRandom.hex(20) }
      head_commit_sha { SecureRandom.hex(20) }
    end

    trait :cleaned_up do
      status { "cleaned_up" }
    end

    trait :locked do
      locked { true }
      lock_reason { "provisioning" }
      locked_at { Time.current }
    end

    trait :with_agent do
      association :ai_agent, factory: :ai_agent
    end
  end
end
