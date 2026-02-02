# frozen_string_literal: true

FactoryBot.define do
  factory :supply_chain_scan_instance, class: "SupplyChain::ScanInstance" do
    association :account
    association :scan_template, factory: :supply_chain_scan_template
    installed_by { nil }
    name { "#{scan_template&.name || 'Security Scan'} Instance" }
    description { "Installed scan instance for automated security scanning" }
    status { "active" }
    configuration do
      {
        severity_threshold: "high",
        scan_depth: 3,
        ignore_dev_dependencies: false
      }
    end
    execution_count { 0 }
    success_count { 0 }
    failure_count { 0 }
    metadata { {} }

    trait :active do
      status { "active" }
    end

    trait :paused do
      status { "paused" }
    end

    trait :disabled do
      status { "disabled" }
    end

    trait :scheduled do
      schedule_cron { "0 0 * * *" } # Daily at midnight
      next_execution_at { 1.day.from_now }
    end

    trait :scheduled_hourly do
      schedule_cron { "0 * * * *" } # Every hour
      next_execution_at { 1.hour.from_now }
    end

    trait :scheduled_weekly do
      schedule_cron { "0 0 * * 0" } # Weekly on Sunday at midnight
      next_execution_at { 1.week.from_now }
    end

    trait :due_for_execution do
      status { "active" }
      schedule_cron { "0 0 * * *" }
      next_execution_at { 1.hour.ago }
    end

    trait :with_execution_history do
      execution_count { 10 }
      success_count { 8 }
      failure_count { 2 }
      last_execution_at { 1.day.ago }
      next_execution_at { 1.day.from_now }
    end

    trait :successful_history do
      execution_count { 20 }
      success_count { 20 }
      failure_count { 0 }
      last_execution_at { 6.hours.ago }
    end

    trait :failing do
      execution_count { 10 }
      success_count { 3 }
      failure_count { 7 }
      last_execution_at { 2.hours.ago }
    end

    trait :never_executed do
      execution_count { 0 }
      success_count { 0 }
      failure_count { 0 }
      last_execution_at { nil }
      next_execution_at { nil }
    end

    trait :with_executions do
      after(:create) do |instance|
        create_list(:supply_chain_scan_execution, 3, :completed, scan_instance: instance, account: instance.account)
      end
    end

    trait :with_custom_config do
      configuration do
        {
          severity_threshold: "critical",
          scan_depth: 5,
          ignore_dev_dependencies: true,
          exclude_patterns: [ "**/test/**", "**/spec/**" ],
          notification_channels: [
            { type: "email", config: { to: "security@example.com" } }
          ]
        }
      end
    end

    trait :minimal_config do
      configuration do
        {
          severity_threshold: "high"
        }
      end
    end

    trait :with_installed_by do
      association :installed_by, factory: :user
    end
  end
end
