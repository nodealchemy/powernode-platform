FactoryBot.define do
  factory :scheduled_report do
    report_type { "MyString" }
    frequency { "MyString" }
    recipients { "MyText" }
    format { "MyString" }
    account { nil }
    user { nil }
    next_run_at { "2025-08-09 20:56:43" }
    last_run_at { "2025-08-09 20:56:43" }
    active { false }
  end
end
