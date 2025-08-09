FactoryBot.define do
  factory :invoice do
    subscription
    sequence(:invoice_number) { |n| "INV-#{Date.current.strftime('%Y%m')}-#{n.to_s.rjust(4, '0')}" }
    status { "draft" }
    subtotal_cents { 2999 }
    tax_cents { 300 }
    total_cents { 3299 }
    currency { "USD" }
    due_date { 30.days.from_now }
    paid_at { nil }
    payment_attempted_at { nil }
    stripe_invoice_id { nil }
    paypal_invoice_id { nil }
    metadata { {} }

    trait :with_account do
      association :subscription, factory: [ :subscription, :with_account ]
    end
  end
end
