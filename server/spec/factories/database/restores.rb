# frozen_string_literal: true

FactoryBot.define do
  factory :database_restore, class: "Database::Restore" do
    association :database_backup
    association :initiated_by, factory: :user
    status { "pending" }
    description { "Test database restore" }
    started_at { Time.current }
    metadata { {} }

    trait :pending do
      status { "pending" }
    end

    trait :in_progress do
      status { "running" }
      started_at { Time.current }
    end

    trait :completed do
      status { "completed" }
      started_at { 1.hour.ago }
      completed_at { Time.current }
      duration_seconds { 300 }
    end

    trait :failed do
      status { "failed" }
      started_at { 1.hour.ago }
      completed_at { Time.current }
      error_message { "Restore failed: invalid backup file" }
    end
  end
end
