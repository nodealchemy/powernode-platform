# frozen_string_literal: true

FactoryBot.define do
  factory :usage_summary do
    association :account
    association :usage_meter
    period_start { Time.current.beginning_of_month }
    period_end { Time.current.end_of_month }
    total_quantity { 500.0 }
    billable_quantity { 500.0 }
    event_count { 100 }
    calculated_amount { 25.00 }
    is_billed { false }
    quota_exceeded { false }
    quota_used { 500.0 }

    trait :billed do
      is_billed { true }
      association :invoice
    end

    trait :quota_exceeded do
      quota_exceeded { true }
      quota_limit { 400.0 }
      quota_used { 500.0 }
    end

    trait :with_subscription do
      association :subscription
    end

    trait :empty do
      total_quantity { 0.0 }
      billable_quantity { 0.0 }
      event_count { 0 }
      calculated_amount { 0.0 }
    end
  end
end
