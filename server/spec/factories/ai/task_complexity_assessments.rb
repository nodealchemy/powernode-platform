# frozen_string_literal: true

FactoryBot.define do
  factory :ai_task_complexity_assessment, class: "Ai::TaskComplexityAssessment" do
    account
    classifier_version { "1.0.0" }
    complexity_level { "moderate" }
    complexity_score { 0.5 }
    recommended_tier { "standard" }
    task_type { "code_generation" }
    complexity_signals { {} }
    input_token_count { 500 }
    conversation_depth { 1 }
    tool_count { 2 }

    trait :trivial do
      complexity_level { "trivial" }
      complexity_score { 0.1 }
      recommended_tier { "economy" }
    end

    trait :complex do
      complexity_level { "complex" }
      complexity_score { 0.8 }
      recommended_tier { "premium" }
    end

    trait :expert do
      complexity_level { "expert" }
      complexity_score { 0.95 }
      recommended_tier { "premium" }
    end
  end
end
