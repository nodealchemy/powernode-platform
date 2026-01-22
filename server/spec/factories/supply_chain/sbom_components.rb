# frozen_string_literal: true

FactoryBot.define do
  factory :supply_chain_sbom_component, class: "SupplyChain::SbomComponent" do
    association :sbom, factory: :supply_chain_sbom
    association :account
    sequence(:purl) { |n| "pkg:npm/package-#{n}@#{Faker::App.semantic_version}" }
    sequence(:name) { |n| "package-#{n}" }
    version { Faker::App.semantic_version }
    ecosystem { "npm" }
    dependency_type { "direct" }
    depth { 0 }
    risk_score { rand(0..100) }
    has_known_vulnerabilities { false }
    is_outdated { false }
    license_spdx_id { "MIT" }
    license_compliance_status { "compliant" }
    metadata { {} }
    properties { {} }

    # ============================================
    # Ecosystem Traits
    # ============================================
    trait :npm do
      ecosystem { "npm" }
      sequence(:purl) { |n| "pkg:npm/@scope/package-#{n}@#{Faker::App.semantic_version}" }
      namespace { "@scope" }
    end

    trait :gem do
      ecosystem { "gem" }
      sequence(:purl) { |n| "pkg:gem/ruby-package-#{n}@#{Faker::App.semantic_version}" }
      sequence(:name) { |n| "ruby-package-#{n}" }
    end

    trait :pip do
      ecosystem { "pip" }
      sequence(:purl) { |n| "pkg:pypi/python-package-#{n}@#{Faker::App.semantic_version}" }
      sequence(:name) { |n| "python-package-#{n}" }
    end

    trait :maven do
      ecosystem { "maven" }
      sequence(:purl) { |n| "pkg:maven/com.example/java-package-#{n}@#{Faker::App.semantic_version}" }
      sequence(:name) { |n| "java-package-#{n}" }
      namespace { "com.example" }
    end

    trait :gradle do
      ecosystem { "gradle" }
      sequence(:purl) { |n| "pkg:gradle/com.example/gradle-package-#{n}@#{Faker::App.semantic_version}" }
      sequence(:name) { |n| "gradle-package-#{n}" }
      namespace { "com.example" }
    end

    trait :go do
      ecosystem { "go" }
      sequence(:purl) { |n| "pkg:golang/github.com/example/go-package-#{n}@v#{Faker::App.semantic_version}" }
      sequence(:name) { |n| "go-package-#{n}" }
      namespace { "github.com/example" }
    end

    trait :cargo do
      ecosystem { "cargo" }
      sequence(:purl) { |n| "pkg:cargo/rust-package-#{n}@#{Faker::App.semantic_version}" }
      sequence(:name) { |n| "rust-package-#{n}" }
    end

    trait :nuget do
      ecosystem { "nuget" }
      sequence(:purl) { |n| "pkg:nuget/DotNet.Package.#{n}@#{Faker::App.semantic_version}" }
      sequence(:name) { |n| "DotNet.Package.#{n}" }
    end

    trait :composer do
      ecosystem { "composer" }
      sequence(:purl) { |n| "pkg:composer/vendor/php-package-#{n}@#{Faker::App.semantic_version}" }
      sequence(:name) { |n| "php-package-#{n}" }
      namespace { "vendor" }
    end

    trait :hex do
      ecosystem { "hex" }
      sequence(:purl) { |n| "pkg:hex/elixir-package-#{n}@#{Faker::App.semantic_version}" }
      sequence(:name) { |n| "elixir-package-#{n}" }
    end

    trait :pub do
      ecosystem { "pub" }
      sequence(:purl) { |n| "pkg:pub/dart-package-#{n}@#{Faker::App.semantic_version}" }
      sequence(:name) { |n| "dart-package-#{n}" }
    end

    trait :cocoapods do
      ecosystem { "cocoapods" }
      sequence(:purl) { |n| "pkg:cocoapods/ios-pod-#{n}@#{Faker::App.semantic_version}" }
      sequence(:name) { |n| "ios-pod-#{n}" }
    end

    trait :swift do
      ecosystem { "swift" }
      sequence(:purl) { |n| "pkg:swift/github.com/example/swift-package-#{n}@#{Faker::App.semantic_version}" }
      sequence(:name) { |n| "swift-package-#{n}" }
    end

    trait :other do
      ecosystem { "other" }
      sequence(:purl) { |n| "pkg:generic/custom-package-#{n}@#{Faker::App.semantic_version}" }
    end

    # ============================================
    # Dependency Type Traits
    # ============================================
    trait :direct do
      dependency_type { "direct" }
      depth { 0 }
    end

    trait :transitive do
      dependency_type { "transitive" }
      depth { rand(1..5) }
    end

    trait :dev do
      dependency_type { "dev" }
      depth { 0 }
    end

    trait :optional do
      dependency_type { "optional" }
    end

    trait :peer do
      dependency_type { "peer" }
    end

    # ============================================
    # Vulnerability Traits
    # ============================================
    trait :vulnerable do
      has_known_vulnerabilities { true }
      risk_score { rand(60..100) }
    end

    trait :not_vulnerable do
      has_known_vulnerabilities { false }
    end

    trait :with_vulnerabilities do
      transient do
        vulnerabilities_count { 2 }
      end

      after(:create) do |component, evaluator|
        create_list(:supply_chain_sbom_vulnerability, evaluator.vulnerabilities_count,
                    sbom: component.sbom,
                    component: component,
                    account: component.account)
        component.update_column(:has_known_vulnerabilities, true)
      end
    end

    # ============================================
    # License Traits
    # ============================================
    trait :mit_licensed do
      license_spdx_id { "MIT" }
      license_compliance_status { "compliant" }
    end

    trait :apache_licensed do
      license_spdx_id { "Apache-2.0" }
      license_compliance_status { "compliant" }
    end

    trait :gpl_licensed do
      license_spdx_id { "GPL-3.0-only" }
      license_compliance_status { "review_required" }
    end

    trait :agpl_licensed do
      license_spdx_id { "AGPL-3.0-only" }
      license_compliance_status { "non_compliant" }
    end

    trait :unlicensed do
      license_spdx_id { nil }
      license_compliance_status { "unknown" }
    end

    trait :license_compliant do
      license_compliance_status { "compliant" }
    end

    trait :license_non_compliant do
      license_compliance_status { "non_compliant" }
    end

    trait :license_review_required do
      license_compliance_status { "review_required" }
    end

    trait :license_unknown do
      license_compliance_status { "unknown" }
    end

    # ============================================
    # Risk Traits
    # ============================================
    trait :high_risk do
      risk_score { rand(70..100) }
      has_known_vulnerabilities { true }
    end

    trait :medium_risk do
      risk_score { rand(30..69) }
    end

    trait :low_risk do
      risk_score { rand(0..29) }
      has_known_vulnerabilities { false }
    end

    # ============================================
    # Outdated Traits
    # ============================================
    trait :outdated do
      is_outdated { true }
      latest_version { "#{version.split('.').first.to_i + 1}.0.0" }
    end

    trait :up_to_date do
      is_outdated { false }
      latest_version { version }
    end

    # ============================================
    # Depth Traits
    # ============================================
    trait :shallow do
      depth { rand(0..1) }
    end

    trait :deep do
      depth { rand(3..10) }
    end
  end
end
