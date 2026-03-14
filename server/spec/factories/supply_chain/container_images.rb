# frozen_string_literal: true

FactoryBot.define do
  factory :supply_chain_container_image, class: "SupplyChain::ContainerImage" do
    association :account
    registry { "gcr.io" }
    sequence(:repository) { |n| "project/application-#{n}" }
    sequence(:tag) { |n| "v1.0.#{n}" }
    sequence(:digest) { |_n| "sha256:#{SecureRandom.hex(32)}" }
    status { "unverified" }
    is_signed { false }
    is_deployed { false }
    critical_vuln_count { 0 }
    high_vuln_count { 0 }
    medium_vuln_count { 0 }
    low_vuln_count { 0 }
    size_bytes { rand(50_000_000..500_000_000) }
    layers { [] }
    deployment_contexts { [] }
    labels { {} }
    metadata { {} }

    # ============================================
    # Status Traits
    # ============================================
    trait :unverified do
      status { "unverified" }
    end

    trait :verified do
      status { "verified" }
      is_signed { true }
    end

    trait :quarantined do
      status { "quarantined" }
      critical_vuln_count { rand(3..10) }
      metadata { { "quarantine_reason" => "Critical vulnerabilities detected" } }
    end

    trait :approved do
      status { "approved" }
      is_signed { true }
      critical_vuln_count { 0 }
      high_vuln_count { 0 }
    end

    trait :rejected do
      status { "rejected" }
      metadata { { "rejection_reason" => "Policy violation - unsigned image" } }
    end

    # ============================================
    # Registry Traits
    # ============================================
    trait :gcr do
      registry { "gcr.io" }
      sequence(:repository) { |n| "my-project/app-#{n}" }
    end

    trait :dockerhub do
      registry { "docker.io" }
      sequence(:repository) { |n| "library/nginx-#{n}" }
    end

    trait :ghcr do
      registry { "ghcr.io" }
      sequence(:repository) { |n| "org/repo-#{n}" }
    end

    trait :ecr do
      registry { "123456789012.dkr.ecr.us-east-1.amazonaws.com" }
      sequence(:repository) { |n| "my-app-#{n}" }
    end

    trait :acr do
      registry { "myregistry.azurecr.io" }
      sequence(:repository) { |n| "my-app-#{n}" }
    end

    # ============================================
    # Signature Traits
    # ============================================
    trait :signed do
      is_signed { true }
    end

    trait :unsigned do
      is_signed { false }
    end

    # ============================================
    # Deployment Traits
    # ============================================
    trait :deployed do
      is_deployed { true }
      deployment_contexts { [ "production", "us-east-1" ] }
    end

    trait :not_deployed do
      is_deployed { false }
      deployment_contexts { [] }
    end

    trait :deployed_to_production do
      is_deployed { true }
      deployment_contexts { [ "production", "kubernetes/prod-cluster" ] }
    end

    trait :deployed_to_staging do
      is_deployed { true }
      deployment_contexts { [ "staging", "kubernetes/staging-cluster" ] }
    end

    # ============================================
    # Vulnerability Traits
    # ============================================
    trait :clean do
      critical_vuln_count { 0 }
      high_vuln_count { 0 }
      medium_vuln_count { 0 }
      low_vuln_count { 0 }
    end

    trait :with_critical_vulns do
      critical_vuln_count { rand(1..5) }
    end

    trait :with_high_vulns do
      high_vuln_count { rand(3..10) }
    end

    trait :with_medium_vulns do
      medium_vuln_count { rand(5..20) }
    end

    trait :with_low_vulns do
      low_vuln_count { rand(10..50) }
    end

    trait :with_mixed_vulns do
      critical_vuln_count { rand(1..3) }
      high_vuln_count { rand(3..7) }
      medium_vuln_count { rand(5..15) }
      low_vuln_count { rand(10..30) }
    end

    trait :high_risk do
      critical_vuln_count { rand(5..10) }
      high_vuln_count { rand(10..20) }
      status { "quarantined" }
    end

    # ============================================
    # Scan Traits
    # ============================================
    trait :recently_scanned do
      last_scanned_at { rand(1..12).hours.ago }
    end

    trait :needs_scan do
      last_scanned_at { nil }
    end

    trait :stale_scan do
      last_scanned_at { rand(25..72).hours.ago }
    end

    # ============================================
    # Size Traits
    # ============================================
    trait :small do
      size_bytes { rand(10_000_000..50_000_000) }
    end

    trait :medium do
      size_bytes { rand(100_000_000..300_000_000) }
    end

    trait :large do
      size_bytes { rand(500_000_000..2_000_000_000) }
    end

    # ============================================
    # Layer Traits
    # ============================================
    trait :with_layers do
      layers do
        Array.new(rand(5..15)) do
          {
            "digest" => "sha256:#{SecureRandom.hex(32)}",
            "size" => rand(1_000_000..50_000_000),
            "created_at" => rand(1..30).days.ago.iso8601
          }
        end
      end
    end

    # ============================================
    # Labels Traits
    # ============================================
    trait :with_labels do
      labels do
        {
          "org.opencontainers.image.title" => Faker::App.name,
          "org.opencontainers.image.version" => tag,
          "org.opencontainers.image.vendor" => Faker::Company.name,
          "org.opencontainers.image.source" => Faker::Internet.url
        }
      end
    end

    # ============================================
    # Association Traits
    # ============================================
    trait :with_sbom do
      association :sbom, factory: :supply_chain_sbom
    end

    trait :with_attestation do
      association :attestation, factory: :supply_chain_attestation
    end

    trait :with_base_image do
      association :base_image, factory: :supply_chain_container_image
    end

    trait :with_scans do
      transient do
        scans_count { 3 }
      end

      after(:create) do |image, evaluator|
        create_list(:supply_chain_vulnerability_scan, evaluator.scans_count,
                    :completed,
                    container_image: image,
                    account: image.account)
      end
    end

    # ============================================
    # Complete Image Trait
    # ============================================
    trait :complete do
      verified
      signed
      with_layers
      with_labels
      recently_scanned
      clean
    end
  end
end
