# frozen_string_literal: true

FactoryBot.define do
  factory :ai_file_lock, class: "Ai::FileLock" do
    worktree_session factory: :ai_worktree_session
    worktree factory: :ai_worktree
    account { worktree_session.account }
    sequence(:file_path) { |n| "src/file_#{n}.rb" }
    lock_type { "exclusive" }
    acquired_at { Time.current }
    expires_at { nil }

    trait :expired do
      expires_at { 1.hour.ago }
    end

    trait :shared do
      lock_type { "shared" }
    end

    trait :with_ttl do
      expires_at { 1.hour.from_now }
    end
  end
end
