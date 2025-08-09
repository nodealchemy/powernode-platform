FactoryBot.define do
  factory :invoice_line_item do
    invoice
    description { "Monthly subscription - Pro Plan" }
    quantity { 1 }
    unit_price_cents { 2999 }
    total_cents { 2999 }
    line_type { "subscription" }
    period_start { 1.month.ago.beginning_of_month }
    period_end { 1.month.ago.end_of_month }
    metadata { {} }

    trait :usage_item do
      line_type { "usage" }
      description { "API calls overage" }
      quantity { 1000 }
      unit_price_cents { 5 }
      total_cents { 5000 }
    end

    trait :discount do
      line_type { "discount" }
      description { "Promotional discount" }
      quantity { 1 }
      unit_price_cents { -500 }
      total_cents { -500 }
    end

    trait :tax do
      line_type { "tax" }
      description { "Sales tax" }
      quantity { 1 }
      unit_price_cents { 300 }
      total_cents { 300 }
    end
  end
end
