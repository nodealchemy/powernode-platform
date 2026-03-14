# frozen_string_literal: true

FactoryBot.define do
  factory :supply_chain_sbom_diff, class: "SupplyChain::SbomDiff" do
    association :account
    association :base_sbom, factory: :supply_chain_sbom
    association :target_sbom, factory: :supply_chain_sbom
    added_count { 0 }
    removed_count { 0 }
    updated_count { 0 }
    risk_delta { 0.0 }
    added_components { [] }
    removed_components { [] }
    updated_components { [] }
    new_vulnerabilities { [] }
    resolved_vulnerabilities { [] }
    metadata { {} }

    trait :with_changes do
      after(:build) do |instance|
        instance.instance_variable_set(:@skip_compute_diff, true)
      end

      added_count { 3 }
      removed_count { 2 }
      updated_count { 5 }
      added_components do
        [
          {
            purl: "pkg:npm/new-package@1.0.0",
            name: "new-package",
            version: "1.0.0",
            ecosystem: "npm",
            license: "MIT"
          }
        ]
      end
      removed_components do
        [
          {
            purl: "pkg:npm/old-package@0.9.0",
            name: "old-package",
            version: "0.9.0",
            ecosystem: "npm",
            license: "MIT"
          }
        ]
      end
      updated_components do
        [
          {
            purl: "pkg:npm/updated-package@2.0.0",
            name: "updated-package",
            old_version: "1.0.0",
            new_version: "2.0.0",
            ecosystem: "npm"
          }
        ]
      end
    end

    trait :with_new_vulnerabilities do
      after(:build) do |instance|
        instance.instance_variable_set(:@skip_compute_diff, true)
      end

      new_vulnerabilities do
        [
          {
            vulnerability_id: "CVE-2024-12345",
            severity: "critical",
            cvss_score: 9.8,
            component_purl: "pkg:npm/vulnerable-package@1.0.0",
            component_name: "vulnerable-package",
            has_fix: true,
            fixed_version: "1.0.1"
          }
        ]
      end
    end

    trait :with_resolved_vulnerabilities do
      after(:build) do |instance|
        instance.instance_variable_set(:@skip_compute_diff, true)
      end

      resolved_vulnerabilities do
        [
          {
            vulnerability_id: "CVE-2023-54321",
            severity: "high",
            cvss_score: 7.5,
            component_purl: "pkg:npm/fixed-package@2.0.0",
            component_name: "fixed-package",
            has_fix: true,
            fixed_version: "2.0.0"
          }
        ]
      end
    end

    trait :risk_increased do
      after(:build) do |instance|
        instance.instance_variable_set(:@skip_compute_diff, true)
      end

      risk_delta { 15.5 }
    end

    trait :risk_decreased do
      after(:build) do |instance|
        instance.instance_variable_set(:@skip_compute_diff, true)
      end

      risk_delta { -10.3 }
    end

    trait :no_changes do
      after(:build) do |instance|
        instance.instance_variable_set(:@skip_compute_diff, true)
      end

      added_count { 0 }
      removed_count { 0 }
      updated_count { 0 }
      risk_delta { 0.0 }
    end
  end
end
