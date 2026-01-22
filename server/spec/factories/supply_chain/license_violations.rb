# frozen_string_literal: true

FactoryBot.define do
  factory :supply_chain_license_violation, class: "SupplyChain::LicenseViolation" do
    association :account
    association :sbom, factory: :supply_chain_sbom
    association :sbom_component, factory: :supply_chain_sbom_component
    association :license_policy, factory: :supply_chain_license_policy
    association :license, factory: :supply_chain_license
    violation_type { %w[denied copyleft incompatible unknown expired].sample }
    severity { %w[critical high medium low].sample }
    status { "open" }
    description { "License violation detected" }
    exception_requested { false }
    exception_status { nil }
    exception_reason { nil }
    exception_approved_at { nil }
    exception_expires_at { nil }
    ai_remediation { {} }
    metadata { {} }

    # Violation type traits
    trait :denied do
      violation_type { "denied" }
      severity { "high" }
      description { "License is explicitly denied by policy" }
    end

    trait :copyleft do
      violation_type { "copyleft" }
      severity { "high" }
      description { "Copyleft license detected, blocked by policy" }
    end

    trait :incompatible do
      violation_type { "incompatible" }
      severity { "medium" }
      description { "License is incompatible with project license" }
    end

    trait :unknown do
      violation_type { "unknown" }
      severity { "medium" }
      description { "Unknown license detected, blocked by policy" }
    end

    trait :expired do
      violation_type { "expired" }
      severity { "low" }
      description { "License exception has expired" }
    end

    # Severity traits
    trait :critical do
      severity { "critical" }
      violation_type { "denied" }
    end

    trait :high_severity do
      severity { "high" }
    end

    trait :medium_severity do
      severity { "medium" }
    end

    trait :low_severity do
      severity { "low" }
    end

    # Status traits
    trait :open do
      status { "open" }
    end

    trait :reviewing do
      status { "reviewing" }
    end

    trait :resolved do
      status { "resolved" }
      metadata do
        {
          resolution_reason: "Component was updated to a compliant license",
          resolved_at: Time.current.iso8601
        }
      end
    end

    trait :exception_granted do
      status { "exception_granted" }
      exception_requested { true }
      exception_status { "approved" }
      exception_reason { "Required for legacy system support" }
      exception_approved_at { Time.current }
      association :exception_approved_by, factory: :user
    end

    trait :wont_fix do
      status { "wont_fix" }
      metadata do
        {
          wont_fix_reason: "Accepted risk for internal tooling",
          decided_at: Time.current.iso8601
        }
      end
    end

    # Exception traits
    trait :with_exception do
      exception_requested { true }
      exception_status { "pending" }
      exception_reason { "Required for legacy support" }
    end

    trait :with_exception_requested do
      exception_requested { true }
      exception_status { "pending" }
      exception_reason { "Required for legacy support" }
    end

    trait :exception_pending do
      exception_requested { true }
      exception_status { "pending" }
      exception_reason { "Awaiting security team review" }
    end

    trait :exception_approved do
      exception_requested { true }
      exception_status { "approved" }
      exception_reason { "Approved for limited use case" }
      exception_approved_at { 1.day.ago }
      exception_expires_at { 1.year.from_now }
      association :exception_approved_by, factory: :user
    end

    trait :exception_rejected do
      exception_requested { true }
      exception_status { "rejected" }
      exception_reason { "Cannot use this license" }
      exception_approved_at { Time.current }
      association :exception_approved_by, factory: :user
      metadata do
        {
          rejection_reason: "License terms are incompatible with distribution requirements"
        }
      end
    end

    trait :exception_expired do
      exception_requested { true }
      exception_status { "expired" }
      exception_reason { "Was approved for temporary use" }
      exception_approved_at { 1.year.ago }
      exception_expires_at { 1.day.ago }
      association :exception_approved_by, factory: :user
    end

    # AI remediation traits
    trait :with_ai_remediation do
      ai_remediation do
        {
          generated_at: Time.current.iso8601,
          suggestions: [
            {
              type: "upgrade",
              description: "Upgrade to version 2.0.0 which uses MIT license",
              confidence: 0.85,
              effort: "low"
            },
            {
              type: "replace",
              description: "Replace with alternative package 'safe-package'",
              confidence: 0.75,
              effort: "medium"
            }
          ],
          analysis: "The component uses a copyleft license. Consider these alternatives."
        }
      end
    end

    # Metadata traits
    trait :with_metadata do
      metadata do
        {
          detected_at: Time.current.iso8601,
          policy_version: "1.0",
          scan_id: SecureRandom.uuid
        }
      end
    end

    # Actionable trait for finding open violations
    trait :actionable do
      status { %w[open reviewing].sample }
    end

    # Common scenarios
    trait :gpl_violation do
      violation_type { "copyleft" }
      severity { "high" }
      description { "GPL-3.0 license detected, violates corporate policy" }
      after(:build) do |violation|
        violation.license ||= create(:supply_chain_license, :copyleft)
      end
    end

    trait :unknown_license_violation do
      violation_type { "unknown" }
      severity { "medium" }
      description { "Unable to identify license, blocked by policy" }
      license { nil }
    end
  end
end
