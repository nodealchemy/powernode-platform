# frozen_string_literal: true

FactoryBot.define do
  factory :ai_ab_test, class: "Ai::AbTest" do
    association :account
    association :created_by, factory: :user

    test_id { SecureRandom.uuid }
    sequence(:name) { |n| "A/B Test #{n}" }
    description { "Testing variant performance" }
    status { "draft" }
    target_type { "workflow" }
    target_id { SecureRandom.uuid }
    variants do
      [
        { "id" => "control", "name" => "Control", "description" => "Original version" },
        { "id" => "variant_a", "name" => "Variant A", "description" => "Modified version" }
      ]
    end
    traffic_allocation { { "control" => 0.5, "variant_a" => 0.5 } }
    success_metrics { [ { "name" => "conversion_rate", "goal" => "maximize" } ] }
    results { {} }
    total_impressions { 0 }
    total_conversions { 0 }

    trait :draft do
      status { "draft" }
    end

    trait :running do
      status { "running" }
      started_at { 1.week.ago }
      total_impressions { 500 }
      total_conversions { 50 }
      results do
        {
          "control" => { "impressions" => 250, "conversions" => 22 },
          "variant_a" => { "impressions" => 250, "conversions" => 28 }
        }
      end
    end

    trait :paused do
      status { "paused" }
      started_at { 2.weeks.ago }
      total_impressions { 1000 }
      total_conversions { 95 }
    end

    trait :completed do
      status { "completed" }
      started_at { 1.month.ago }
      ended_at { Time.current }
      total_impressions { 5000 }
      total_conversions { 450 }
      winning_variant { "variant_a" }
      statistical_significance { 95.5 }
      results do
        {
          "control" => { "impressions" => 2500, "conversions" => 200 },
          "variant_a" => { "impressions" => 2500, "conversions" => 250 }
        }
      end
    end

    trait :cancelled do
      status { "cancelled" }
      started_at { 1.week.ago }
      ended_at { Time.current }
      total_impressions { 200 }
      total_conversions { 15 }
    end

    trait :workflow_test do
      target_type { "workflow" }
      description { "Testing workflow variations" }
    end

    trait :agent_test do
      target_type { "agent" }
      description { "Testing agent behavior variations" }
    end

    trait :prompt_test do
      target_type { "prompt" }
      description { "Testing prompt variations" }
      variants do
        [
          { "id" => "prompt_v1", "name" => "Original Prompt", "config" => { "prompt" => "You are a helpful assistant." } },
          { "id" => "prompt_v2", "name" => "Enhanced Prompt", "config" => { "prompt" => "You are an expert assistant with deep knowledge." } }
        ]
      end
    end

    trait :model_test do
      target_type { "model" }
      description { "Testing model performance comparison" }
      variants do
        [
          { "id" => "gpt4", "name" => "GPT-4", "config" => { "model" => "gpt-4" } },
          { "id" => "claude3", "name" => "Claude 3", "config" => { "model" => "claude-3-opus" } }
        ]
      end
    end

    trait :provider_test do
      target_type { "provider" }
      description { "Testing provider performance comparison" }
    end

    trait :multivariate do
      variants do
        [
          { "id" => "control", "name" => "Control", "description" => "Original" },
          { "id" => "variant_a", "name" => "Variant A", "description" => "Change 1" },
          { "id" => "variant_b", "name" => "Variant B", "description" => "Change 2" },
          { "id" => "variant_c", "name" => "Variant C", "description" => "Change 3" }
        ]
      end
      traffic_allocation do
        { "control" => 0.25, "variant_a" => 0.25, "variant_b" => 0.25, "variant_c" => 0.25 }
      end
    end

    trait :uneven_traffic do
      traffic_allocation { { "control" => 0.8, "variant_a" => 0.2 } }
    end

    trait :with_multiple_metrics do
      success_metrics do
        [
          { "name" => "conversion_rate", "goal" => "maximize", "weight" => 0.5 },
          { "name" => "response_time", "goal" => "minimize", "weight" => 0.3 },
          { "name" => "user_satisfaction", "goal" => "maximize", "weight" => 0.2 }
        ]
      end
    end

    trait :statistically_significant do
      status { "completed" }
      total_impressions { 10000 }
      total_conversions { 950 }
      statistical_significance { 99.2 }
      winning_variant { "variant_a" }
      results do
        {
          "control" => { "impressions" => 5000, "conversions" => 400 },
          "variant_a" => { "impressions" => 5000, "conversions" => 550 }
        }
      end
    end

    trait :insufficient_data do
      status { "running" }
      started_at { 1.day.ago }
      total_impressions { 50 }
      total_conversions { 5 }
      results do
        {
          "control" => { "impressions" => 25, "conversions" => 2 },
          "variant_a" => { "impressions" => 25, "conversions" => 3 }
        }
      end
    end
  end
end
