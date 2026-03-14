# frozen_string_literal: true

FactoryBot.define do
  factory :baas_tenant, class: "BaaS::Tenant" do
    account
    sequence(:name) { |n| "Tenant #{n}" }
    tier { "starter" }
    status { "active" }
    environment { "production" }
    default_currency { "usd" }
    timezone { "UTC" }
    branding { {} }
    metadata { {} }

    trait :free do
      tier { "free" }
    end

    trait :pro do
      tier { "pro" }
    end

    trait :business do
      tier { "business" }
    end

    trait :suspended do
      status { "suspended" }
    end

    trait :pending do
      status { "pending" }
    end

    trait :with_stripe do
      webhook_url { "https://example.com/webhooks/stripe" }
      webhook_secret { SecureRandom.hex(32) }
    end
  end
end
