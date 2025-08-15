FactoryBot.define do
  factory :account do
    sequence(:name) { |n| "Test Company #{n}" }
    sequence(:subdomain) { |n| "company-#{n}" }
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
      payment_provider { 'stripe' }
    end

    trait :with_paypal_data do
      paypal_customer_id { "PP_#{SecureRandom.hex(12)}" }
      payment_provider { 'paypal' }
    end
  end
end
