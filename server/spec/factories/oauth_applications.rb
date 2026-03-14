# frozen_string_literal: true

FactoryBot.define do
  factory :oauth_application do
    sequence(:name) { |n| "Test OAuth App #{n}" }
    sequence(:uid) { |n| SecureRandom.hex(16) }
    secret { SecureRandom.hex(32) }
    redirect_uri { "https://example.com/callback" }
    scopes { "read write" }
    confidential { true }
    trusted { false }
    machine_client { false }
    status { "active" }
    rate_limit_tier { "standard" }
    description { "Test OAuth application" }
    metadata { {} }

    trait :active do
      status { "active" }
    end

    trait :suspended do
      status { "suspended" }
    end

    trait :revoked do
      status { "revoked" }
    end

    trait :trusted do
      trusted { true }
    end

    trait :machine_client do
      machine_client { true }
      confidential { true }
    end

    trait :public_client do
      confidential { false }
    end

    trait :premium_tier do
      rate_limit_tier { "premium" }
    end

    trait :business_tier do
      rate_limit_tier { "business" }
    end

    trait :unlimited_tier do
      rate_limit_tier { "unlimited" }
    end

    trait :with_account_owner do
      association :owner, factory: :account
      owner_type { "Account" }
    end

    trait :with_user_owner do
      association :owner, factory: :user
      owner_type { "User" }
    end

    trait :mcp_client do
      confidential { false }
      redirect_uri { "http://127.0.0.1:3456/callback" }
      scopes { "read write workflows files" }
      metadata { { registered_via: "mcp_dynamic_registration" } }
    end
  end
end
