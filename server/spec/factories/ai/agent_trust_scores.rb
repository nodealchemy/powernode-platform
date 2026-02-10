# frozen_string_literal: true

FactoryBot.define do
  factory :ai_agent_trust_score, class: "Ai::AgentTrustScore" do
    account
    association :agent, factory: :ai_agent
    reliability { 0.5 }
    cost_efficiency { 0.5 }
    safety { 1.0 }
    quality { 0.5 }
    speed { 0.5 }
    overall_score { 0.5 }
    tier { "supervised" }
    evaluation_count { 0 }
    evaluation_history { [] }
    last_evaluated_at { Time.current }

    trait :monitored do
      tier { "monitored" }
      overall_score { 0.5 }
      reliability { 0.6 }
      evaluation_count { 15 }
    end

    trait :trusted do
      tier { "trusted" }
      overall_score { 0.75 }
      reliability { 0.8 }
      safety { 0.9 }
      quality { 0.8 }
      evaluation_count { 25 }
    end

    trait :autonomous do
      tier { "autonomous" }
      overall_score { 0.92 }
      reliability { 0.95 }
      safety { 0.95 }
      quality { 0.9 }
      speed { 0.8 }
      evaluation_count { 50 }
    end
  end
end
