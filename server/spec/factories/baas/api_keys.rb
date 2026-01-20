# frozen_string_literal: true

FactoryBot.define do
  factory :baas_api_key, class: "BaaS::ApiKey" do
    association :baas_tenant, factory: :baas_tenant
    sequence(:name) { |n| "API Key #{n}" }
    key_prefix { "sk_test" }
    key_hash { Digest::SHA256.hexdigest("sk_test_#{SecureRandom.alphanumeric(32)}") }
    key_type { "secret" }
    environment { "production" }
    status { "active" }
    scopes { ["read", "write"] }
    rate_limit_per_minute { 100 }
    rate_limit_per_day { 10000 }
    total_requests { 0 }
    last_used_at { nil }
    expires_at { nil }
    metadata { {} }

    trait :production do
      key_prefix { "sk_live" }
      environment { "production" }
    end

    trait :staging do
      key_prefix { "sk_stag" }
      environment { "staging" }
    end

    trait :development do
      key_prefix { "sk_test" }
      environment { "development" }
    end

    trait :publishable do
      key_type { "publishable" }
      key_prefix { "pk_test" }
    end

    trait :restricted do
      key_type { "restricted" }
      key_prefix { "rk_test" }
      scopes { ["read"] }
    end

    trait :revoked do
      status { "revoked" }
    end

    trait :expired do
      status { "expired" }
      expires_at { 1.day.ago }
    end

    trait :expiring_soon do
      expires_at { 7.days.from_now }
    end
  end
end
