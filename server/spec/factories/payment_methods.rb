# frozen_string_literal: true

FactoryBot.define do
  factory :payment_method do
    association :account
    gateway { "stripe" }
    external_id { "pm_#{SecureRandom.hex(10)}" }
    payment_type { "card" }
    last_four { "4242" }
    brand { "visa" }
    exp_month { 12 }
    exp_year { 1.year.from_now.year }
    cardholder_name { "John Doe" }
    is_default { false }
    is_active { true }
    metadata { {} }

    trait :stripe do
      gateway { "stripe" }
      payment_type { "card" }
    end

    trait :paypal do
      gateway { "paypal" }
      payment_type { "paypal" }
      last_four { nil }
      brand { nil }
      exp_month { nil }
      exp_year { nil }
      cardholder_name { nil }
    end
  end
end
