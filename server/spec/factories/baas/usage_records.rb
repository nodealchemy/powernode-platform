# frozen_string_literal: true

FactoryBot.define do
  factory :baas_usage_record, class: "BaaS::UsageRecord" do
    association :baas_tenant, factory: :baas_tenant
    sequence(:customer_external_id) { |n| "cust_#{SecureRandom.hex(4)}_#{n}" }
    subscription_external_id { nil }
    meter_id { "api_calls" }
    idempotency_key { nil }
    quantity { 1 }
    action { "increment" }
    event_timestamp { Time.current }
    billing_period_start { Time.current.beginning_of_month }
    billing_period_end { Time.current.end_of_month }
    status { "pending" }
    processed_at { nil }
    invoice_id { nil }
    properties { {} }
    metadata { {} }

    trait :processed do
      status { "processed" }
      processed_at { Time.current }
    end

    trait :invoiced do
      status { "invoiced" }
      invoice_id { SecureRandom.uuid }
    end

    trait :failed do
      status { "failed" }
    end

    trait :set_action do
      action { "set" }
    end

    trait :storage do
      meter_id { "storage_gb" }
      quantity { 10 }
      action { "set" }
    end

    trait :bandwidth do
      meter_id { "bandwidth_gb" }
      quantity { 100 }
    end

    trait :with_idempotency do
      idempotency_key { SecureRandom.uuid }
    end

    trait :with_subscription do
      sequence(:subscription_external_id) { |n| "sub_#{SecureRandom.hex(4)}_#{n}" }
    end
  end
end
