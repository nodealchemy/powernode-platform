# frozen_string_literal: true

FactoryBot.define do
  factory :ai_context_access_log, class: "Ai::ContextAccessLog" do
    account
    association :persistent_context, factory: :ai_persistent_context
    action { "read" }
    access_type { "api" }
    success { true }
    changes_summary { {} }
    metadata { {} }

    trait :write do
      action { "write" }
    end

    trait :failed do
      success { false }
      error_message { "Access denied" }
    end

    trait :by_agent do
      association :agent, factory: :ai_agent
    end
  end
end
