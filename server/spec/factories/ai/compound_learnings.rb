# frozen_string_literal: true

FactoryBot.define do
  factory :ai_compound_learning, class: "Ai::CompoundLearning" do
    account
    sequence(:title) { |n| "Compound Learning #{n}" }
    content { "A learning extracted from execution results" }
    category { "pattern" }
    scope { "team" }
    status { "active" }
    importance_score { 0.5 }
    confidence_score { 0.5 }
    extraction_method { "auto_success" }
    decay_rate { 0.01 }
    access_count { 0 }
    injection_count { 0 }
    positive_outcome_count { 0 }
    negative_outcome_count { 0 }
    tags { [] }
    metadata { {} }

    trait :best_practice do
      category { "best_practice" }
      importance_score { 0.8 }
      confidence_score { 0.8 }
    end

    trait :anti_pattern do
      category { "anti_pattern" }
      importance_score { 0.7 }
      confidence_score { 0.75 }
    end

    trait :high_importance do
      importance_score { 0.9 }
    end

    trait :low_importance do
      importance_score { 0.1 }
    end

    trait :deprecated do
      status { "deprecated" }
    end

    trait :global do
      scope { "global" }
    end
  end
end
