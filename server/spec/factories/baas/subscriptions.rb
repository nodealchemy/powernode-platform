# frozen_string_literal: true

FactoryBot.define do
  factory :baas_subscription, class: "BaaS::Subscription" do
    association :baas_tenant, factory: :baas_tenant
    association :baas_customer, factory: :baas_customer
    sequence(:external_id) { |n| "sub_#{SecureRandom.hex(8)}_#{n}" }
    plan_external_id { "plan_pro_monthly" }
    status { "active" }
    billing_interval { "month" }
    billing_interval_count { 1 }
    unit_amount { 9900 }
    currency { "usd" }
    quantity { 1 }
    current_period_start { Time.current.beginning_of_month }
    current_period_end { Time.current.end_of_month }
    trial_end { nil }
    cancel_at_period_end { false }
    canceled_at { nil }
    ended_at { nil }
    cancellation_reason { nil }
    stripe_subscription_id { nil }

    trait :trialing do
      status { "trialing" }
      trial_end { 14.days.from_now }
    end

    trait :canceled do
      status { "canceled" }
      canceled_at { Time.current }
      ended_at { Time.current }
    end

    trait :cancel_at_period_end do
      cancel_at_period_end { true }
      cancellation_reason { "customer_request" }
    end

    trait :past_due do
      status { "past_due" }
    end

    trait :paused do
      status { "paused" }
    end

    trait :yearly do
      billing_interval { "year" }
      billing_interval_count { 1 }
      unit_amount { 99000 }
    end

    trait :quarterly do
      billing_interval { "month" }
      billing_interval_count { 3 }
      unit_amount { 27000 }
    end

    trait :with_stripe do
      stripe_subscription_id { "sub_#{SecureRandom.alphanumeric(14)}" }
    end
  end
end
