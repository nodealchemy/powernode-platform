# frozen_string_literal: true

FactoryBot.define do
  factory :revenue_forecast do
    account { nil }
    forecast_date { 1.month.from_now }
    forecast_type { "mrr" }
    forecast_period { "monthly" }
    projected_mrr { 50000 }
    projected_arr { 600000 }
    projected_new_revenue { 5000 }
    projected_expansion_revenue { 3000 }
    projected_churned_revenue { 2000 }
    projected_net_revenue { 56000 }
    projected_new_customers { 10 }
    projected_churned_customers { 2 }
    projected_total_customers { 100 }
    confidence_level { 95 }
    lower_bound { 45000 }
    upper_bound { 55000 }
    actual_mrr { nil }
    accuracy_percentage { nil }
    model_version { "1.0" }
    assumptions { { "growth_rate" => 0.05, "churn_rate" => 0.03, "expansion_rate" => 0.02 } }
    contributing_factors { [{ "factor" => "growth", "impact" => 0.05 }] }
    generated_at { Time.current }

    trait :with_account do
      account
    end

    trait :monthly do
      forecast_period { "monthly" }
    end

    trait :quarterly do
      forecast_period { "quarterly" }
      forecast_date { 3.months.from_now }
      projected_mrr { 55000 }
      projected_arr { 660000 }
      projected_new_revenue { 18000 }
      projected_expansion_revenue { 10000 }
      projected_churned_revenue { 7000 }
    end

    trait :yearly do
      forecast_period { "yearly" }
      forecast_date { 1.year.from_now }
      projected_mrr { 75000 }
      projected_arr { 900000 }
      projected_new_revenue { 100000 }
      projected_expansion_revenue { 50000 }
      projected_churned_revenue { 30000 }
    end

    trait :with_actuals do
      actual_mrr { 48000 }
      accuracy_percentage { 96.0 }
    end

    trait :past do
      forecast_date { 1.month.ago }
    end

    trait :high_growth do
      projected_mrr { 75000 }
      projected_arr { 900000 }
      projected_new_revenue { 15000 }
      projected_expansion_revenue { 8000 }
      projected_churned_revenue { 3000 }
    end

    trait :conservative do
      projected_mrr { 48000 }
      projected_arr { 576000 }
      projected_new_revenue { 3000 }
      projected_expansion_revenue { 1500 }
      projected_churned_revenue { 3500 }
      confidence_level { 90 }
      lower_bound { 42000 }
      upper_bound { 52000 }
    end
  end
end
