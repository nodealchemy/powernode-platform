# frozen_string_literal: true

FactoryBot.define do
  factory :analytics_tier do
    sequence(:name) { |n| "Analytics Tier #{n}" }
    slug { %w[free starter pro business].sample }
    description { "Test analytics tier for specs" }
    monthly_price { 0.00 }
    retention_days { 30 }
    cohort_months { 3 }
    csv_export { false }
    api_access { false }
    forecasting { false }
    custom_reports { false }
    api_calls_per_day { 0 }
    is_active { true }
    sort_order { 0 }
    features { {} }

    trait :free do
      name { "Free" }
      slug { "free" }
      monthly_price { 0.00 }
      retention_days { 7 }
      cohort_months { 0 }
      csv_export { false }
      api_access { false }
      api_calls_per_day { 0 }
    end

    trait :starter do
      name { "Starter" }
      slug { "starter" }
      monthly_price { 29.00 }
      retention_days { 30 }
      cohort_months { 3 }
      csv_export { true }
      api_access { false }
      api_calls_per_day { 100 }
    end

    trait :pro do
      name { "Pro" }
      slug { "pro" }
      monthly_price { 99.00 }
      retention_days { 90 }
      cohort_months { 12 }
      csv_export { true }
      api_access { true }
      forecasting { true }
      api_calls_per_day { 1000 }
    end

    trait :business do
      name { "Business" }
      slug { "business" }
      monthly_price { 299.00 }
      retention_days { -1 }
      cohort_months { -1 }
      csv_export { true }
      api_access { true }
      forecasting { true }
      custom_reports { true }
      api_calls_per_day { 100_000 }
    end

    trait :inactive do
      is_active { false }
    end
  end
end
