# frozen_string_literal: true

FactoryBot.define do
  factory :supply_chain_cve_monitor, class: "SupplyChain::CveMonitor" do
    association :account
    association :created_by, factory: :user
    sequence(:name) { |n| "CVE Monitor #{n}" }
    description { "Monitors CVEs for #{%w[critical high medium].sample} severity vulnerabilities" }
    scope_type { "account_wide" }
    scope_id { nil }
    min_severity { %w[critical high medium low].sample }
    is_active { true }
    notification_channels { [] }
    filters { {} }
    metadata { {} }

    trait :image_scope do
      scope_type { "image" }
      scope_id { SecureRandom.uuid }
    end

    trait :repository_scope do
      scope_type { "repository" }
      scope_id { SecureRandom.uuid }
    end

    trait :account_wide do
      scope_type { "account_wide" }
      scope_id { nil }
    end

    trait :critical_only do
      min_severity { "critical" }
      description { "Monitors critical CVEs only" }
    end

    trait :high_and_above do
      min_severity { "high" }
      description { "Monitors high and critical CVEs" }
    end

    trait :medium_and_above do
      min_severity { "medium" }
      description { "Monitors medium, high and critical CVEs" }
    end

    trait :all_severities do
      min_severity { "low" }
      description { "Monitors all CVE severities" }
    end

    trait :inactive do
      is_active { false }
    end

    trait :active do
      is_active { true }
    end

    trait :with_email_notification do
      notification_channels do
        [
          {
            type: "email",
            config: { to: "security@example.com" },
            added_at: Time.current.iso8601
          }
        ]
      end
    end

    trait :with_slack_notification do
      notification_channels do
        [
          {
            type: "slack",
            config: { webhook_url: "https://hooks.slack.com/services/test" },
            added_at: Time.current.iso8601
          }
        ]
      end
    end

    trait :with_multiple_notifications do
      notification_channels do
        [
          {
            type: "email",
            config: { to: "security@example.com" },
            added_at: Time.current.iso8601
          },
          {
            type: "slack",
            config: { webhook_url: "https://hooks.slack.com/services/test" },
            added_at: Time.current.iso8601
          }
        ]
      end
    end

    trait :due_for_run do
      is_active { true }
      next_run_at { 1.hour.ago }
    end

    trait :not_due do
      is_active { true }
      next_run_at { 1.hour.from_now }
    end

    trait :recently_run do
      last_run_at { 1.hour.ago }
      next_run_at { 23.hours.from_now }
    end

    trait :never_run do
      last_run_at { nil }
      next_run_at { nil }
    end

    trait :with_schedule do
      schedule_cron { "0 * * * *" }
      next_run_at { 1.hour.from_now }
    end

    trait :with_filters do
      filters do
        {
          exclude_packages: [ "test-package" ],
          include_only: [ "critical-package" ],
          min_cvss_score: 7.0
        }
      end
    end

    trait :with_metadata do
      metadata do
        {
          source: "automated",
          last_check: Time.current.iso8601,
          total_cves_found: rand(0..50)
        }
      end
    end

    # Convenience factory for image-scoped monitor with associated image
    trait :for_image do
      scope_type { "image" }
      transient do
        container_image { nil }
      end
      after(:build) do |monitor, evaluator|
        if evaluator.container_image
          monitor.scope_id = evaluator.container_image.id
        else
          monitor.scope_id = SecureRandom.uuid
        end
      end
    end

    # Convenience factory for repository-scoped monitor with associated repository
    trait :for_repository do
      scope_type { "repository" }
      transient do
        repository { nil }
      end
      after(:build) do |monitor, evaluator|
        if evaluator.repository
          monitor.scope_id = evaluator.repository.id
        else
          monitor.scope_id = SecureRandom.uuid
        end
      end
    end
  end
end
