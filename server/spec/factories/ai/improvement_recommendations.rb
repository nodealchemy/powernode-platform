# frozen_string_literal: true

FactoryBot.define do
  factory :ai_improvement_recommendation, class: "Ai::ImprovementRecommendation" do
    account
    recommendation_type { "provider_switch" }
    target_type { "Ai::Agent" }
    target_id { SecureRandom.uuid }
    current_config { {} }
    recommended_config { {} }
    evidence { {} }
    confidence_score { 0.75 }
    status { "pending" }
    approved_by { nil }
    applied_at { nil }

    trait :pending do
      status { "pending" }
    end

    trait :approved do
      status { "approved" }
      association :approved_by, factory: :user
    end

    trait :applied do
      status { "applied" }
      association :approved_by, factory: :user
      applied_at { Time.current }
    end

    trait :dismissed do
      status { "dismissed" }
    end

    trait :high_confidence do
      confidence_score { rand(0.85..0.99).round(4) }
    end

    trait :low_confidence do
      confidence_score { rand(0.30..0.50).round(4) }
    end

    trait :provider_switch do
      recommendation_type { "provider_switch" }
      target_type { "Ai::Agent" }
      current_config do
        {
          "provider" => "openai",
          "model" => "gpt-4",
          "monthly_cost" => 250.00
        }
      end
      recommended_config do
        {
          "provider" => "anthropic",
          "model" => "claude-3-sonnet",
          "estimated_monthly_cost" => 150.00
        }
      end
      evidence do
        {
          "cost_comparison" => { "current" => 250.00, "recommended" => 150.00 },
          "quality_comparison" => { "current" => 0.92, "recommended" => 0.94 },
          "sample_size" => 500,
          "analysis_period_days" => 30
        }
      end
    end

    trait :team_composition do
      recommendation_type { "team_composition" }
      target_type { "Ai::AgentTeam" }
      current_config do
        {
          "team_size" => 3,
          "roles" => %w[lead researcher writer]
        }
      end
      recommended_config do
        {
          "team_size" => 4,
          "roles" => %w[lead researcher writer reviewer],
          "reason" => "Adding reviewer role improves output quality by 15%"
        }
      end
      evidence do
        {
          "quality_scores" => { "without_reviewer" => 0.78, "with_reviewer" => 0.93 },
          "task_completion_rate" => { "current" => 0.85, "projected" => 0.95 },
          "sample_size" => 200
        }
      end
    end

    trait :timeout_adjustment do
      recommendation_type { "timeout_adjustment" }
      target_type { "Ai::Workflow" }
      current_config do
        {
          "timeout_ms" => 30000,
          "avg_execution_ms" => 28500
        }
      end
      recommended_config do
        {
          "timeout_ms" => 60000,
          "reason" => "Current timeout too close to average execution time"
        }
      end
      evidence do
        {
          "timeout_failures" => 45,
          "total_executions" => 300,
          "p95_execution_ms" => 42000,
          "p99_execution_ms" => 55000
        }
      end
    end

    trait :model_upgrade do
      recommendation_type { "model_upgrade" }
      target_type { "Ai::Agent" }
      current_config do
        {
          "model" => "gpt-3.5-turbo",
          "quality_score" => 0.72
        }
      end
      recommended_config do
        {
          "model" => "gpt-4",
          "estimated_quality_score" => 0.91,
          "estimated_cost_increase" => "3x"
        }
      end
      evidence do
        {
          "quality_comparison" => { "current" => 0.72, "recommended" => 0.91 },
          "error_rate" => { "current" => 0.12, "recommended" => 0.03 },
          "sample_size" => 100
        }
      end
    end

    trait :cost_optimization do
      recommendation_type { "cost_optimization" }
      target_type { "Ai::Workflow" }
      current_config do
        {
          "monthly_cost" => 500.00,
          "execution_count" => 10000
        }
      end
      recommended_config do
        {
          "caching_enabled" => true,
          "batch_size" => 10,
          "estimated_monthly_cost" => 300.00
        }
      end
      evidence do
        {
          "duplicate_request_rate" => 0.35,
          "cacheable_requests" => 3500,
          "estimated_savings_pct" => 40
        }
      end
    end
  end
end
