# frozen_string_literal: true

FactoryBot.define do
  factory :supply_chain_sbom, class: "SupplyChain::Sbom" do
    association :account
    sequence(:name) { |n| "Application SBOM #{n}" }
    sequence(:sbom_id) { |n| "sbom-#{Time.current.strftime('%Y%m%d%H%M%S')}-#{SecureRandom.hex(4)}" }
    format { "cyclonedx_1_5" }
    version { Faker::App.semantic_version }
    status { "completed" }
    component_count { rand(10..100) }
    vulnerability_count { rand(0..20) }
    risk_score { rand(0..100) }
    ntia_minimum_compliant { true }
    document { { "bomFormat" => "CycloneDX", "specVersion" => "1.5", "components" => [] } }
    metadata { {} }

    # ============================================
    # Associations
    # ============================================
    trait :with_repository do
      association :repository, factory: :devops_repository
    end

    trait :with_pipeline_run do
      association :pipeline_run, factory: :devops_pipeline_run
    end

    trait :with_created_by do
      association :created_by, factory: :user
    end

    # ============================================
    # Status Traits
    # ============================================
    trait :draft do
      status { "draft" }
      document { {} }
      component_count { 0 }
      vulnerability_count { 0 }
    end

    trait :generating do
      status { "generating" }
      document { {} }
      component_count { 0 }
      vulnerability_count { 0 }
    end

    trait :completed do
      status { "completed" }
      document do
        {
          "bomFormat" => "CycloneDX",
          "specVersion" => "1.5",
          "components" => [
            { "name" => "lodash", "version" => "4.17.21", "purl" => "pkg:npm/lodash@4.17.21" }
          ],
          "metadata" => {
            "timestamp" => Time.current.iso8601,
            "supplier" => { "name" => "Test Supplier" },
            "authors" => [{ "name" => "Test Author" }]
          },
          "dependencies" => [
            { "ref" => "pkg:npm/lodash@4.17.21", "dependsOn" => [] }
          ]
        }
      end
    end

    trait :failed do
      status { "failed" }
      document { {} }
      component_count { 0 }
      vulnerability_count { 0 }
      metadata { { "error" => "SBOM generation failed: unable to parse package manifest" } }
    end

    trait :archived do
      status { "archived" }
    end

    # ============================================
    # Format Traits
    # ============================================
    trait :spdx do
      format { "spdx_2_3" }
      document do
        {
          "spdxVersion" => "SPDX-2.3",
          "SPDXID" => "SPDXRef-DOCUMENT",
          "name" => name,
          "packages" => []
        }
      end
    end

    trait :cyclonedx_1_4 do
      format { "cyclonedx_1_4" }
    end

    trait :cyclonedx_1_5 do
      format { "cyclonedx_1_5" }
    end

    trait :cyclonedx_1_6 do
      format { "cyclonedx_1_6" }
    end

    # ============================================
    # Compliance Traits
    # ============================================
    trait :ntia_compliant do
      ntia_minimum_compliant { true }
    end

    trait :ntia_non_compliant do
      ntia_minimum_compliant { false }
    end

    # ============================================
    # Signature Traits
    # ============================================
    trait :signed do
      signature { Base64.encode64(SecureRandom.random_bytes(256)) }
      signature_algorithm { "ECDSA-P256" }
      document_hash { SecureRandom.hex(32) }
    end

    trait :unsigned do
      signature { nil }
      signature_algorithm { nil }
    end

    # ============================================
    # Risk Traits
    # ============================================
    trait :high_risk do
      risk_score { rand(70..100) }
      vulnerability_count { rand(10..50) }
    end

    trait :medium_risk do
      risk_score { rand(30..69) }
      vulnerability_count { rand(5..15) }
    end

    trait :low_risk do
      risk_score { rand(0..29) }
      vulnerability_count { rand(0..5) }
    end

    trait :no_vulnerabilities do
      vulnerability_count { 0 }
      risk_score { 0 }
    end

    # ============================================
    # Component Count Traits
    # ============================================
    trait :small do
      component_count { rand(1..10) }
    end

    trait :medium do
      component_count { rand(50..200) }
    end

    trait :large do
      component_count { rand(500..1000) }
    end

    # ============================================
    # Association Traits for Creating Related Records
    # ============================================
    trait :with_components do
      transient do
        components_count { 5 }
      end

      after(:create) do |sbom, evaluator|
        create_list(:supply_chain_sbom_component, evaluator.components_count, sbom: sbom, account: sbom.account)
        sbom.update_column(:component_count, evaluator.components_count)
      end
    end

    trait :with_vulnerabilities do
      transient do
        vulnerabilities_count { 3 }
      end

      after(:create) do |sbom, evaluator|
        component = create(:supply_chain_sbom_component, sbom: sbom, account: sbom.account)
        create_list(:supply_chain_sbom_vulnerability, evaluator.vulnerabilities_count,
                    sbom: sbom,
                    component: component,
                    account: sbom.account)
        sbom.update_column(:vulnerability_count, evaluator.vulnerabilities_count)
      end
    end

    trait :with_full_document do
      document do
        {
          "bomFormat" => "CycloneDX",
          "specVersion" => "1.5",
          "serialNumber" => "urn:uuid:#{SecureRandom.uuid}",
          "version" => 1,
          "metadata" => {
            "timestamp" => Time.current.iso8601,
            "tools" => [{ "vendor" => "Powernode", "name" => "SBOM Generator", "version" => "1.0.0" }],
            "supplier" => { "name" => Faker::Company.name, "url" => [Faker::Internet.url] },
            "authors" => [{ "name" => Faker::Name.name, "email" => Faker::Internet.email }]
          },
          "components" => Array.new(5) do |i|
            {
              "type" => "library",
              "name" => Faker::Internet.slug,
              "version" => Faker::App.semantic_version,
              "purl" => "pkg:npm/#{Faker::Internet.slug}@#{Faker::App.semantic_version}",
              "licenses" => [{ "license" => { "id" => "MIT" } }]
            }
          end,
          "dependencies" => []
        }
      end
    end
  end
end
