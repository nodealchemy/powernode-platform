FactoryBot.define do
  factory :payment_method do
    association :account
    association :user
    provider { "stripe" }
    external_id { "pm_#{SecureRandom.hex(10)}" }
    payment_type { "card" }
    last_four { "4242" }
    exp_month { 12 }
    exp_year { 1.year.from_now.year }
    is_default { false }
    metadata { {} }
  end
end
