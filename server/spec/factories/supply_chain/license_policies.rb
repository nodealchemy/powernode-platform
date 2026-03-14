# frozen_string_literal: true

FactoryBot.define do
  factory :supply_chain_license_policy, class: "SupplyChain::LicensePolicy" do
    association :account
    association :created_by, factory: :user
    sequence(:name) { |n| "License Policy #{n}" }
    description { Faker::Lorem.sentence }
    policy_type { %w[allowlist denylist hybrid].sample }
    enforcement_level { %w[log warn block].sample }
    is_active { true }
    is_default { false }
    priority { rand(0..10) }
    allowed_licenses { [] }
    denied_licenses { [] }
    exception_packages { [] }
    block_copyleft { false }
    block_strong_copyleft { false }
    block_unknown { false }
    metadata { {} }

    trait :default do
      is_default { true }
    end

    trait :active do
      is_active { true }
    end

    trait :inactive do
      is_active { false }
    end

    # Policy type traits
    trait :allowlist do
      policy_type { "allowlist" }
      allowed_licenses { %w[MIT Apache-2.0 BSD-3-Clause BSD-2-Clause ISC] }
    end

    trait :denylist do
      policy_type { "denylist" }
      denied_licenses { %w[GPL-3.0-only AGPL-3.0-only GPL-2.0-only] }
    end

    trait :hybrid do
      policy_type { "hybrid" }
      allowed_licenses { %w[MIT Apache-2.0 BSD-3-Clause] }
      denied_licenses { %w[GPL-3.0-only AGPL-3.0-only] }
    end

    # Enforcement level traits
    trait :logging do
      enforcement_level { "log" }
    end

    trait :warning do
      enforcement_level { "warn" }
    end

    trait :blocking do
      enforcement_level { "block" }
    end

    # Strictness traits
    trait :strict do
      enforcement_level { "block" }
      block_copyleft { true }
      block_strong_copyleft { true }
      block_unknown { true }
    end

    trait :permissive do
      enforcement_level { "log" }
      block_copyleft { false }
      block_strong_copyleft { false }
      block_unknown { false }
    end

    trait :block_copyleft_licenses do
      block_copyleft { true }
    end

    trait :block_strong_copyleft_licenses do
      block_strong_copyleft { true }
    end

    trait :block_unknown_licenses do
      block_unknown { true }
    end

    # Priority traits
    trait :high_priority do
      priority { 10 }
    end

    trait :low_priority do
      priority { 0 }
    end

    # Exception traits
    trait :with_exceptions do
      exception_packages do
        [
          {
            "package" => "legacy-package",
            "license" => "GPL-3.0-only",
            "reason" => "Required for legacy support",
            "added_at" => Time.current.iso8601,
            "expires_at" => 1.year.from_now.iso8601
          },
          {
            "package" => "internal-tool",
            "license" => "AGPL-3.0-only",
            "reason" => "Internal use only",
            "added_at" => Time.current.iso8601,
            "expires_at" => nil
          }
        ]
      end
    end

    trait :with_metadata do
      metadata do
        {
          created_source: "automated",
          last_reviewed: Time.current.iso8601,
          reviewer: "security-team"
        }
      end
    end

    # Common policy configurations
    trait :business_standard do
      name { "Business Standard Policy" }
      policy_type { "hybrid" }
      enforcement_level { "block" }
      priority { 5 }
      allowed_licenses { %w[MIT Apache-2.0 BSD-3-Clause BSD-2-Clause ISC MPL-2.0 LGPL-2.1-only] }
      denied_licenses { %w[GPL-3.0-only AGPL-3.0-only SSPL-1.0] }
      block_strong_copyleft { true }
      block_unknown { true }
    end

    trait :oss_friendly do
      name { "OSS Friendly Policy" }
      policy_type { "denylist" }
      enforcement_level { "warn" }
      priority { 3 }
      denied_licenses { %w[SSPL-1.0 BSL-1.0] }
      block_copyleft { false }
      block_strong_copyleft { false }
      block_unknown { false }
    end
  end
end
