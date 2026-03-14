# frozen_string_literal: true

FactoryBot.define do
  factory :supply_chain_image_policy, class: "SupplyChain::ImagePolicy" do
    association :account
    association :created_by, factory: :user
    sequence(:name) { |n| "Image Policy #{n}" }
    description { Faker::Lorem.sentence }
    policy_type { "registry_allowlist" }
    enforcement_level { "warn" }
    is_active { true }
    priority { 0 }
    require_signature { false }
    require_sbom { false }
    max_critical_vulns { nil }
    max_high_vulns { nil }
    match_rules { {} }
    rules { { "allowed_registries" => [ "gcr.io", "docker.io" ] } }
    metadata { {} }

    trait :registry_allowlist do
      policy_type { "registry_allowlist" }
      rules do
        {
          "allowed_registries" => [ "gcr.io", "docker.io" ],
          "denied_registries" => []
        }
      end
    end

    trait :signature_required do
      policy_type { "signature_required" }
      require_signature { true }
      require_sbom { false }
    end

    trait :signature_with_sbom do
      policy_type { "signature_required" }
      require_signature { true }
      require_sbom { true }
    end

    trait :vulnerability_threshold do
      policy_type { "vulnerability_threshold" }
      max_critical_vulns { 1 }
      max_high_vulns { 5 }
    end

    trait :custom do
      policy_type { "custom" }
      rules do
        {
          "checks" => [
            { "type" => "label_required", "key" => "app" }
          ]
        }
      end
    end

    trait :blocking do
      enforcement_level { "block" }
    end

    trait :warning do
      enforcement_level { "warn" }
    end

    trait :logging do
      enforcement_level { "log" }
    end

    trait :active do
      is_active { true }
    end

    trait :inactive do
      is_active { false }
    end

    trait :with_registry_matching do
      match_rules do
        {
          "registries" => [ "gcr.io", "docker.io" ],
          "repositories" => [ "project/.*" ],
          "tags" => [ "v[0-9]+\\..*" ]
        }
      end
    end

    trait :with_label_matching do
      match_rules do
        {
          "labels" => {
            "env" => "prod",
            "managed" => "true"
          }
        }
      end
    end

    trait :high_priority do
      priority { 10 }
    end

    trait :low_priority do
      priority { 0 }
    end
  end
end
