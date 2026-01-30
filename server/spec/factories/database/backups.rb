# frozen_string_literal: true

FactoryBot.define do
  factory :database_backup, class: "Database::Backup" do
    association :created_by, factory: :user
    backup_type { "full" }
    status { "pending" }
    description { "Test database backup" }
    started_at { Time.current }
    metadata { {} }

    trait :full do
      backup_type { "full" }
    end

    trait :incremental do
      backup_type { "incremental" }
    end

    trait :manual do
      backup_type { "manual" }
    end

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
      duration_seconds { 3600 }
      file_size_bytes { 1024 * 1024 * 100 }
      file_path { "/backups/backup_completed.sql.gz" }
    end

    trait :failed do
      status { "failed" }
      started_at { 1.hour.ago }
      completed_at { Time.current }
      error_message { "Backup failed: disk space insufficient" }
    end
  end
end
