FactoryBot.define do
  factory :payment_method do
    association :account
    association :user
    provider { "stripe" }
    external_id { "pm_#{SecureRandom.hex(10)}" }
    payment_type { "card" }
    last_four { "4242" }
    expires_at { 1.year.from_now }
    is_default { false }
    metadata { {} }
  end
end
