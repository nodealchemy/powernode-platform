# frozen_string_literal: true

FactoryBot.define do
  factory :account do
    sequence(:name) { |n| "Test Company #{n} #{SecureRandom.hex(3)}" }
    sequence(:subdomain) { |n| "test-#{n}-#{SecureRandom.hex(3)}" }
    status { 'active' }
    settings { {} }

    trait :suspended do
      status { 'suspended' }
    end

    trait :cancelled do
      status { 'cancelled' }
    end

    trait :with_stripe_data do
      stripe_customer_id { "cus_#{SecureRandom.hex(12)}" }
    end

    trait :with_paypal_data do
      paypal_customer_id { "PP_#{SecureRandom.hex(12)}" }
    end
  end
end
