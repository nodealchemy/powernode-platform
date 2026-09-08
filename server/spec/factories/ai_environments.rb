# frozen_string_literal: true

FactoryBot.define do
  factory :ai_environment, class: "Ai::Environment" do
    association :account
    sequence(:slug) { |n| "env-#{n}" }
    sequence(:name) { |n| "Environment #{n}" }
    tier { 0 }
    default_decision_authority { "trusted" }
    is_protected { false }
    is_default { false }

    trait :prod do
      slug { "prod" }
      name { "Production" }
      tier { 3 }
      default_decision_authority { "supervised" }
      is_protected { true }
    end
  end
end
