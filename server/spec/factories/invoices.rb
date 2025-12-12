FactoryBot.define do
  factory :invoice do
    # Associations
    association :account
    association :subscription

    # Account and subscription coordination handled by explicit associations

    sequence(:invoice_number) { |n| "INV-#{Date.current.strftime('%Y%m')}-#{n.to_s.rjust(4, '0')}" }
    status { "draft" }
    subtotal_cents { 2999 }
    tax_cents { 300 }
    tax_rate { 0.10 }
    total_cents { 3299 }
    currency { "USD" }
    due_at { 30.days.from_now }
    paid_at { nil }
    stripe_invoice_id { nil }
    paypal_invoice_id { nil }
    metadata { {} }

    trait :with_account do
      association :subscription, factory: [ :subscription, :with_account ]
    end
  end
end
