# frozen_string_literal: true

FactoryBot.define do
  factory :usage_quota do
    association :account
    association :usage_meter
    association :plan, optional: true
    soft_limit { 1000.0 }
    hard_limit { 1500.0 }
    current_usage { 0.0 }
    allow_overage { true }
    overage_rate { 0.05 }
    warning_threshold_percent { 80 }
    critical_threshold_percent { 95 }
    notify_on_warning { true }
    notify_on_exceeded { true }
    current_period_start { Time.current.beginning_of_month }
    current_period_end { Time.current.end_of_month }

    trait :with_usage do
      current_usage { 500.0 }
    end

    trait :near_limit do
      current_usage { 850.0 }
    end

    trait :exceeded do
      current_usage { 1200.0 }
    end

    trait :hard_exceeded do
      current_usage { 1600.0 }
    end

    trait :no_overage do
      allow_overage { false }
      overage_rate { nil }
    end

    trait :unlimited do
      soft_limit { nil }
      hard_limit { nil }
    end

    trait :soft_limit_only do
      soft_limit { 1000.0 }
      hard_limit { nil }
    end

    trait :hard_limit_only do
      soft_limit { nil }
      hard_limit { 1500.0 }
    end

    trait :no_notifications do
      notify_on_warning { false }
      notify_on_exceeded { false }
    end

    trait :daily_period do
      current_period_start { Time.current.beginning_of_day }
      current_period_end { Time.current.end_of_day }
    end

    trait :weekly_period do
      current_period_start { Time.current.beginning_of_week }
      current_period_end { Time.current.end_of_week }
    end

    trait :yearly_period do
      current_period_start { Time.current.beginning_of_year }
      current_period_end { Time.current.end_of_year }
    end
  end
end
