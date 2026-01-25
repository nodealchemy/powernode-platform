# frozen_string_literal: true

FactoryBot.define do
  factory :scheduled_task do
    sequence(:name) { |n| "Scheduled Task #{n}" }
    task_type { "database_backup" }
    cron_expression { "0 0 * * *" }
    is_active { true }
    parameters { {} }
    success_count { 0 }
    failure_count { 0 }

    trait :database_backup do
      task_type { "database_backup" }
      parameters { { "backup_type" => "full" } }
    end

    trait :data_cleanup do
      task_type { "data_cleanup" }
      parameters { { "days_to_keep" => 30 } }
    end

    trait :system_health_check do
      task_type { "system_health_check" }
      parameters { { "check_database" => true, "check_redis" => true } }
    end

    trait :report_generation do
      task_type { "report_generation" }
      parameters { { "report_type" => "usage_summary" } }
    end

    trait :custom_command do
      task_type { "custom_command" }
      parameters { { "command" => "echo 'test'" } }
    end

    trait :active do
      is_active { true }
    end

    trait :inactive do
      is_active { false }
    end

    trait :with_executions do
      after(:create) do |task|
        task.update!(
          last_run_at: 1.hour.ago,
          last_status: "completed",
          success_count: 10,
          failure_count: 1,
          next_run_at: 1.day.from_now
        )
      end
    end

    trait :hourly do
      cron_expression { "0 * * * *" }
    end

    trait :daily do
      cron_expression { "0 0 * * *" }
    end

    trait :weekly do
      cron_expression { "0 0 * * 0" }
    end

    trait :monthly do
      cron_expression { "0 0 1 * *" }
    end
  end
end
