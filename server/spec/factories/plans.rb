FactoryBot.define do
  factory :plan do
    sequence(:name) { |n| "Plan #{n}" }
    description { "A great subscription plan" }
    price_cents { 2999 }
    currency { "USD" }
    billing_cycle { "monthly" }
    features { {} }
    limits { {} }
    status { "active" }
    default_roles { [] }
    trial_days { 14 }
    public { true }
  end
end
