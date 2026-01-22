# frozen_string_literal: true

FactoryBot.define do
  factory :supply_chain_remediation_plan, class: "SupplyChain::RemediationPlan" do
    association :account
    association :sbom, factory: :supply_chain_sbom
    association :created_by, factory: :user
    plan_type { "manual" }
    status { "draft" }
    approval_status { "pending" }
    auto_executable { false }
    confidence_score { 0.75 }
    target_vulnerabilities { [] }
    upgrade_recommendations { [] }
    breaking_changes { [] }
    metadata { {} }

    trait :manual do
      plan_type { "manual" }
    end

    trait :ai_generated do
      plan_type { "ai_generated" }
      confidence_score { 0.85 }
    end

    trait :auto_fix do
      plan_type { "auto_fix" }
      auto_executable { true }
      confidence_score { 0.95 }
    end

    trait :draft do
      status { "draft" }
    end

    trait :pending_review do
      status { "pending_review" }
    end

    trait :approved do
      status { "approved" }
      approval_status { "approved" }
      approved_at { Time.current }
      association :approved_by, factory: :user
    end

    trait :rejected do
      status { "rejected" }
      approval_status { "rejected" }
      approved_at { Time.current }
      association :approved_by, factory: :user
    end

    trait :executing do
      status { "executing" }
      approval_status { "approved" }
      approved_at { Time.current }
      association :approved_by, factory: :user
    end

    trait :completed do
      status { "completed" }
      approval_status { "approved" }
      approved_at { Time.current }
      association :approved_by, factory: :user
      generated_pr_url { "https://github.com/org/repo/pull/#{rand(100..999)}" }
    end

    trait :failed do
      status { "failed" }
      approval_status { "approved" }
      approved_at { Time.current }
      association :approved_by, factory: :user
      metadata { { "execution_error" => "Failed to create PR" } }
    end

    trait :high_confidence do
      confidence_score { 0.95 }
    end

    trait :low_confidence do
      confidence_score { 0.5 }
    end

    trait :with_vulnerabilities do
      target_vulnerabilities do
        [
          {
            "vulnerability_id" => "CVE-2024-12345",
            "severity" => "critical",
            "package_name" => "lodash",
            "current_version" => "4.17.15"
          },
          {
            "vulnerability_id" => "CVE-2024-67890",
            "severity" => "high",
            "package_name" => "axios",
            "current_version" => "0.21.1"
          }
        ]
      end
    end

    trait :with_upgrades do
      upgrade_recommendations do
        [
          {
            "package_name" => "lodash",
            "current_version" => "4.17.15",
            "target_version" => "4.17.21",
            "reason" => "Fixes CVE-2024-12345",
            "is_breaking" => false,
            "added_at" => Time.current.iso8601
          },
          {
            "package_name" => "axios",
            "current_version" => "0.21.1",
            "target_version" => "1.6.0",
            "reason" => "Fixes CVE-2024-67890",
            "is_breaking" => true,
            "added_at" => Time.current.iso8601
          }
        ]
      end
    end

    trait :with_breaking_changes do
      breaking_changes do
        [
          {
            "package_name" => "axios",
            "from_version" => "0.21.1",
            "to_version" => "1.6.0",
            "description" => "Major version upgrade with API changes"
          }
        ]
      end
    end

    trait :auto_executable_plan do
      auto_executable { true }
      confidence_score { 0.95 }
    end

    trait :with_workflow_run do
      association :workflow_run, factory: :ai_workflow_run
    end
  end
end
