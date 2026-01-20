# frozen_string_literal: true

FactoryBot.define do
  factory :baas_customer, class: "BaaS::Customer" do
    association :baas_tenant, factory: :baas_tenant
    sequence(:external_id) { |n| "cust_#{SecureRandom.hex(8)}_#{n}" }
    sequence(:email) { |n| "customer#{n}@example.com" }
    name { "Test Customer" }
    status { "active" }
    currency { "usd" }
    balance_cents { 0 }
    address_line1 { nil }
    address_line2 { nil }
    city { nil }
    state { nil }
    postal_code { nil }
    country { nil }
    stripe_customer_id { nil }
    metadata { {} }

    trait :archived do
      status { "archived" }
    end

    trait :deleted do
      status { "deleted" }
    end

    trait :with_balance do
      balance_cents { 5000 }
    end

    trait :with_address do
      address_line1 { "123 Main St" }
      city { "San Francisco" }
      state { "CA" }
      postal_code { "94102" }
      country { "US" }
    end

    trait :with_stripe do
      stripe_customer_id { "cus_#{SecureRandom.alphanumeric(14)}" }
    end
  end
end
