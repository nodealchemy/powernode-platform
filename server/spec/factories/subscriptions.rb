# frozen_string_literal: true

FactoryBot.define do
  factory :subscription do
    association :account
    association :plan
    quantity { 1 }
    current_period_start { 1.month.ago }
    current_period_end { 1.month.from_now }
    metadata { {} }

    trait :active do
      status { 'active' }
    end

    trait :trialing do
      status { 'trialing' }
      trial_end { 14.days.from_now }
    end

    trait :past_due do
      status { 'past_due' }
    end

    trait :canceled do
      status { 'canceled' }
      canceled_at { 1.day.ago }
    end

    trait :unpaid do
      status { 'unpaid' }
    end

    trait :incomplete do
      status { 'incomplete' }
    end

    trait :incomplete_expired do
      status { 'incomplete_expired' }
    end

    trait :paused do
      status { 'paused' }
    end

    trait :ended do
      status { 'ended' }
      ended_at { 1.day.ago }
    end

    trait :without_plan do
      plan { nil }
    end

    trait :with_stripe do
      stripe_subscription_id { "sub_#{SecureRandom.hex(12)}" }
    end

    trait :with_paypal do
      paypal_subscription_id { "I-#{SecureRandom.hex(8).upcase}" }
    end
  end
end
