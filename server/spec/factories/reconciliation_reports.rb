FactoryBot.define do
  factory :reconciliation_report do
    report_type { 'daily' }
    gateway { 'stripe' }
    sequence(:report_date) { |n| Date.current - n.days }
    sequence(:reconciliation_date) { |n| Date.current - n.days }
    reconciliation_type { 'daily' }
    date_range_start { 1.day.ago.beginning_of_day }
    date_range_end { 1.day.ago.end_of_day }
    discrepancies_count { 0 }
    high_severity_count { 0 }
    medium_severity_count { 0 }
    summary do
      {
        'local_payments' => 50,
        'stripe_payments' => 48,
        'paypal_payments' => 2,
        'total_amount_variance' => 0
      }
    end

    trait :with_discrepancies do
      discrepancies_count { 5 }
      high_severity_count { 2 }
      medium_severity_count { 3 }
      summary do
        {
          'local_payments' => 50,
          'stripe_payments' => 45,
          'paypal_payments' => 2,
          'total_amount_variance' => 15000
        }
      end
    end

    trait :high_priority do
      discrepancies_count { 3 }
      high_severity_count { 3 }
      medium_severity_count { 0 }
    end

    trait :weekly do
      reconciliation_type { 'weekly' }
      date_range_start { 1.week.ago.beginning_of_week }
      date_range_end { 1.week.ago.end_of_week }
    end

    trait :monthly do
      reconciliation_type { 'monthly' }
      date_range_start { 1.month.ago.beginning_of_month }
      date_range_end { 1.month.ago.end_of_month }
    end
  end
end