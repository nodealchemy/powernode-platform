FactoryBot.define do
  factory :scheduled_report do
    name { "Monthly Revenue Report" }
    report_type { "revenue_report" }
    frequency { "monthly" }
    recipients { ["admin@example.com", "billing@example.com"] }
    format { "pdf" }
    association :account
    association :user
    next_run_at { 1.month.from_now.beginning_of_month + 8.hours }
    last_run_at { nil }
    is_active { true }

    trait :daily do
      frequency { "daily" }
      next_run_at { 1.day.from_now.beginning_of_day + 8.hours }
    end

    trait :weekly do
      frequency { "weekly" }
      next_run_at { 1.week.from_now.beginning_of_week + 8.hours }
    end

    trait :inactive do
      is_active { false }
    end

    trait :with_history do
      last_run_at { 1.week.ago }
    end

    trait :analytics_report do
      report_type { "customer_report" }
    end

    trait :csv_format do
      format { "csv" }
    end
  end
end
