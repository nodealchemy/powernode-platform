# frozen_string_literal: true

FactoryBot.define do
  factory :ai_roi_metric, class: "Ai::RoiMetric" do
    account
    metric_type { "account_total" }
    period_type { "daily" }
    period_date { Date.current }
    ai_cost_usd { 10.00 }
    infrastructure_cost_usd { 2.00 }
    total_cost_usd { 12.00 }
    time_saved_hours { 5.0 }
    time_saved_value_usd { 375.00 }
    error_reduction_value_usd { 50.00 }
    throughput_value_usd { 100.00 }
    total_value_usd { 525.00 }
    roi_percentage { 4275.00 }
    net_benefit_usd { 513.00 }
    tasks_completed { 100 }
    tasks_automated { 85 }
    errors_prevented { 10 }
    manual_interventions { 5 }
    cost_per_task_usd { 0.12 }
    value_per_task_usd { 5.25 }
    baseline_cost_usd { nil }
    baseline_time_hours { nil }
    efficiency_gain_percentage { nil }
    accuracy_rate { nil }
    customer_satisfaction_score { nil }
    attributable_type { nil }
    attributable_id { nil }
    metadata { {} }

    trait :workflow do
      metric_type { "workflow" }
      attributable_type { "Ai::Workflow" }
    end

    trait :agent do
      metric_type { "agent" }
      attributable_type { "Ai::Agent" }
    end

    trait :provider do
      metric_type { "provider" }
      attributable_type { "Ai::Provider" }
    end

    trait :team do
      metric_type { "team" }
      attributable_type { "Ai::AgentTeam" }
    end

    trait :department do
      metric_type { "department" }
    end

    trait :weekly do
      period_type { "weekly" }
      period_date { Date.current.beginning_of_week }
    end

    trait :monthly do
      period_type { "monthly" }
      period_date { Date.current.beginning_of_month }
    end

    trait :quarterly do
      period_type { "quarterly" }
      period_date { Date.current.beginning_of_quarter }
    end

    trait :yearly do
      period_type { "yearly" }
      period_date { Date.current.beginning_of_year }
    end

    trait :positive_roi do
      ai_cost_usd { 50.00 }
      total_cost_usd { 60.00 }
      total_value_usd { 300.00 }
      roi_percentage { 400.00 }
      net_benefit_usd { 240.00 }
    end

    trait :negative_roi do
      ai_cost_usd { 200.00 }
      total_cost_usd { 250.00 }
      total_value_usd { 100.00 }
      roi_percentage { -60.00 }
      net_benefit_usd { -150.00 }
    end

    trait :break_even do
      ai_cost_usd { 100.00 }
      total_cost_usd { 100.00 }
      total_value_usd { 100.00 }
      roi_percentage { 0.00 }
      net_benefit_usd { 0.00 }
    end

    trait :with_baseline do
      baseline_cost_usd { 500.00 }
      baseline_time_hours { 40.0 }
      efficiency_gain_percentage { 87.5 }
    end

    trait :with_quality_metrics do
      accuracy_rate { 0.95 }
      customer_satisfaction_score { 4.5 }
    end

    trait :high_volume do
      tasks_completed { 1000 }
      tasks_automated { 950 }
      errors_prevented { 50 }
      manual_interventions { 25 }
    end

    trait :low_volume do
      tasks_completed { 10 }
      tasks_automated { 8 }
      errors_prevented { 1 }
      manual_interventions { 2 }
    end

    trait :with_metadata do
      metadata do
        {
          "total_tokens" => 500000,
          "total_api_calls" => 1000,
          "attribution_count" => 50,
          "primary_use_case" => "customer_support"
        }
      end
    end
  end
end
