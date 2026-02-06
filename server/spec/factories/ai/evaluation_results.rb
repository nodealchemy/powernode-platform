# frozen_string_literal: true

FactoryBot.define do
  factory :ai_evaluation_result, class: "Ai::EvaluationResult" do
    account
    association :agent, factory: :ai_agent
    execution_id { SecureRandom.uuid }
    evaluator_model { "gpt-4" }
    scores do
      {
        "correctness" => rand(0.5..1.0).round(2),
        "completeness" => rand(0.5..1.0).round(2),
        "helpfulness" => rand(0.5..1.0).round(2),
        "safety" => rand(0.8..1.0).round(2)
      }
    end
    feedback { nil }

    trait :excellent do
      scores do
        {
          "correctness" => 0.95,
          "completeness" => 0.98,
          "helpfulness" => 0.97,
          "safety" => 1.0
        }
      end
      feedback { "Excellent response. Accurate, complete, and highly useful." }
    end

    trait :good do
      scores do
        {
          "correctness" => 0.85,
          "completeness" => 0.80,
          "helpfulness" => 0.82,
          "safety" => 0.95
        }
      end
      feedback { "Good response overall with minor gaps in completeness." }
    end

    trait :poor do
      scores do
        {
          "correctness" => 0.40,
          "completeness" => 0.35,
          "helpfulness" => 0.45,
          "safety" => 0.90
        }
      end
      feedback { "Response contains factual errors and is incomplete. Needs significant improvement." }
    end

    trait :unsafe do
      scores do
        {
          "correctness" => 0.70,
          "completeness" => 0.65,
          "helpfulness" => 0.60,
          "safety" => 0.20
        }
      end
      feedback { "Response flagged for safety concerns. Contains potentially harmful content." }
    end

    trait :with_feedback do
      feedback { Faker::Lorem.paragraph(sentence_count: 3) }
    end

    trait :evaluated_by_claude do
      evaluator_model { "claude-3-opus" }
    end

    trait :evaluated_by_gpt4 do
      evaluator_model { "gpt-4" }
    end

    trait :evaluated_by_gpt4_turbo do
      evaluator_model { "gpt-4-turbo" }
    end

    trait :with_detailed_scores do
      scores do
        {
          "correctness" => 0.88,
          "completeness" => 0.82,
          "helpfulness" => 0.90,
          "safety" => 0.99,
          "coherence" => 0.85,
          "conciseness" => 0.78,
          "relevance" => 0.92
        }
      end
      feedback { "Detailed evaluation with extended scoring criteria applied." }
    end
  end
end
